-- unrealUI :: modules/swingbar.lua
--
-- Movable auto-attack timing for the main hand, off hand and ranged weapon.
-- UnitAttackSpeed (with an independent offhand equipment check), UnitRangedDamage,
-- GetInventoryItemLink and IsAutoRepeatAction are OFFICIAL_CLIENT_DOCUMENTATION
-- on this client. GetTime is measured by api.json / core.time.v1.
--
-- rangedshot.v1 captured Auto Shot activation well before its first native
-- cycle notification. GetActionCooldown stayed 0/0/1 throughout, and damage
-- arrived later with variable delay. Use the measured ACTIONBAR_UPDATE_COOLDOWN
-- cadence while auto-repeat is active, excluding cast/interrupt batches. This
-- is a cycle signal, not proof of an exact projectile animation timestamp.
-- Wands retain their previous fallback until their own shot lifecycle has been
-- measured.
--
-- Every lane runs the same event clock, because the same defect was measured on
-- both sides: the timer used to start when the attack was switched on and then
-- free-run, so it invented cycles the client never performed. The melee window
-- of that same capture (Worn Axe, UnitAttackSpeed 2.00) put five consecutive
-- swings 2.029-2.038s apart -- mean 2.0345s, spread 9ms -- so the combat log is
-- a stable swing anchor, but the real cycle is 1.7% longer than the reported
-- speed. A clock that wraps on the reported speed therefore restarts ~35ms
-- early every cycle and drifts further whenever a swing is delayed. Each lane
-- now waits for an observed attack, anchors on it, and holds at ready instead
-- of wrapping, so the fill can only ever run slightly ahead of the next swing,
-- never behind it and never through a swing that did not happen.
--
-- meleeswing.v1 then measured the same weapon live: eight swings, six of them
-- 2.024-2.041s apart against the reported 2.00s, so the lane reached ready
-- 20-35ms early on every one of them. The fill therefore runs on the observed
-- cycle rather than the reported speed -- the median of the last few accepted
-- intervals, floored at the reported speed because the client cannot swing
-- faster than that, and capped so one bad window cannot stretch the bar. The
-- label keeps reporting the weapon's own speed. The remaining two intervals in
-- that capture were 2.130 and 2.138, during the part of the run where the
-- player stepped out of melee reach and back; a delayed swing is held at ready,
-- which is the whole point of not wrapping.
--
-- A lane is only shown while the target is actually reachable by that attack.
-- The ranged lane can ask the client directly, because IsActionInRange reports
-- 0 for an out-of-range auto-repeat slot. The melee lanes cannot: the same
-- documentation states melee Auto Attack always returns 1 and never measures
-- distance, so they go through the shared U.MeleeInteractRange, which is that
-- CheckInteractDistance approximation in one place. Its range is wider than
-- melee reach, so the melee lanes appear slightly before the first swing can
-- land rather than lingering while the player runs in.

local U = UnrealUI
local M = U.media

local SB = U.RegisterModule("swingbar")

local WIDTH = 180
local TEXT_SIZE = 6
-- Twenty percent thinner than the previous 8-unit lane. The compact text is
-- taller than the bar, so stacked lanes retain enough separation for their
-- labels not to collide.
local ROW_HEIGHT = 6.4
local ROW_GAP = 3
local STATE_INTERVAL = 0.08
local EQUIPMENT_INTERVAL = 0.5
local RANGE_INTERVAL = 0.15
-- How far past due a main-hand clock may be for a spell hit to be read as an
-- on-next-swing ability rather than an unrelated one. See OnSpecialSwing.
local SPECIAL_SWING_GRACE = 0.2

-- Cycle-length learning. A median over a short window ignores the occasional
-- delayed cycle instead of chasing it, and the accept band keeps a doubled or
-- jittered interval out of the window in the first place.
local PERIOD_SAMPLES = 5
local PERIOD_MIN_SAMPLES = 3
local PERIOD_MAX_SCALE = 1.2
local PERIOD_ACCEPT_LOW = 0.9
local PERIOD_ACCEPT_HIGH = 1.35

local COLOR_MAIN = { 1.00, 1.00, 1.00, 1.00 }
local COLOR_OFF = { 1.00, 1.00, 1.00, 1.00 }
local COLOR_RANGED = { 1.00, 1.00, 1.00, 1.00 }

-- These documented globals are stable for the life of the addon. Resolve them
-- once to avoid repeating guarded global lookups in the animation loop.
local getTime = U.G("GetTime")
local unitAttackSpeed = U.G("UnitAttackSpeed")
local unitRangedDamage = U.G("UnitRangedDamage")
local getTimeVerified = false

local config
local anchor
local lanes = {}
local laneOrder = {}
local nextStateAt = 0
local nextEquipmentAt = 0
local nextRangeAt = 0
local meleeInRange = true
local rangedInRange = true
local layoutMainShown, layoutOffShown, layoutRangedShown
local tickInterval
local Tick
local UpdateTickRate
local rangedClock = { generation = 0, casting = false }

local function InvalidateRangedPulse()
  rangedClock.generation = rangedClock.generation + 1
end

-- An event-clock lane has no anchor until the client reports an actual attack,
-- so dropping the anchor is how the lane is returned to "nothing observed yet".
local function ClearLaneClock(lane)
  if not lane then return end
  lane.startedAt = nil
  lane.lastText = nil
  -- Swings the client actually reported for this engagement. Kept apart from
  -- startedAt because PLAYER_ENTER_COMBAT anchors the lane too, and a consumer
  -- asking "is anything really swinging" must not be answered by that event.
  lane.swings = 0
end

local function ClearRangedClock()
  InvalidateRangedPulse()
  ClearLaneClock(lanes.ranged)
end

-- A lane with an event clock is only meaningful once something anchored it.
local function LaneReady(lane)
  return lane ~= nil and (not lane.eventClock or lane.startedAt ~= nil)
end

-- The cycle the lane actually runs at. Until enough intervals have been seen
-- this is the reported speed; after that it is the measured median, floored at
-- the reported speed so the fill can never claim a swing came early, and capped
-- so a run of delayed cycles cannot stretch it indefinitely.
local function LanePeriod(lane)
  local speed = lane.speed
  if not speed then return nil end
  local period = lane.period
  if not period or period < speed then return speed end
  local ceiling = speed * PERIOD_MAX_SCALE
  if period > ceiling then return ceiling end
  return period
end

local function ForgetLanePeriod(lane)
  lane.intervals = nil
  lane.period = nil
end

local function RecordLaneInterval(lane, interval)
  local speed = lane.speed
  if not speed or not interval then return end
  if interval < speed * PERIOD_ACCEPT_LOW or
     interval > speed * PERIOD_ACCEPT_HIGH then return end

  local list = lane.intervals
  if not list then list = {} lane.intervals = list end
  table.insert(list, interval)
  if table.getn(list) > PERIOD_SAMPLES then table.remove(list, 1) end

  local count = table.getn(list)
  if count < PERIOD_MIN_SAMPLES then lane.period = nil return end
  local sorted, i = {}, nil
  for i = 1, count do sorted[i] = list[i] end
  table.sort(sorted)
  local middle = math.floor(count / 2)
  if math.mod(count, 2) == 1 then
    lane.period = sorted[middle + 1]
  else
    lane.period = (sorted[middle] + sorted[middle + 1]) / 2
  end
end

-- Every event clock is anchored here, so every measured cycle is learned here.
local function AnchorLane(lane, at)
  if not lane then return end
  if lane.startedAt then RecordLaneInterval(lane, at - lane.startedAt) end
  lane.startedAt = at
  lane.lastText = nil
end

local function Now()
  if type(getTime) ~= "function" then return 0 end
  local ok, value = true, nil
  if getTimeVerified then
    value = getTime()
  else
    ok, value = pcall(getTime)
    if ok and type(value) == "number" then getTimeVerified = true end
  end
  return ok and tonumber(value) or 0
end

local function Positive(value)
  value = tonumber(value)
  if value and value > 0 then return value end
  return nil
end

local function EnsureConfig()
  if not config then config = U.ModuleConfig("swingbar", { enabled = true }) end
  return config
end

-- behavior.json / swingfont.requested_sizes_change_rendered_metrics.v1:
-- U.CreateLabel with inherited GameFontNormalSmall rendered requests 9, 7 and
-- 6 at the same native size 10 (identical width 123). The shared "Original"
-- route deliberately preserves that FontObject. This component explicitly
-- needs smaller text, so apply only a stock path that U.ResolveFont has already
-- verified changes rendered width across sizes.
local function ApplySwingTextSize(label)
  if not label or not label.SetFont or type(U.ResolveFont) ~= "function" then
    return false
  end
  local path = U.ResolveFont()
  if type(path) ~= "string" or path == "" then return false end
  return pcall(label.SetFont, label, path, TEXT_SIZE, "OUTLINE")
end

local function SetLaneSpeed(lane, speed, now)
  speed = Positive(speed)
  if lane.speed == speed then return end

  -- Preserve progress through a haste or equipment change instead of jumping
  -- the fill back to zero. A newly available lane begins a fresh cycle.
  if lane.eventClock then
    -- Keep the actual cycle timestamp through a speed change. Equipment and
    -- activation may supply a speed, but neither supplies a first swing.
    if not speed then lane.startedAt = nil end
  elseif lane.speed and speed and lane.startedAt then
    local progress = (now - lane.startedAt) / lane.speed
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    lane.startedAt = now - progress * speed
  elseif speed then
    lane.startedAt = now
  else
    lane.startedAt = nil
  end

  -- Haste and equipment changes make every learned interval stale.
  ForgetLanePeriod(lane)
  lane.speed = speed
  lane.lastText = nil
end

local function ReadWeaponSpeeds(now)
  local mainSpeed, offSpeed
  if type(unitAttackSpeed) == "function" then
    local ok, mainValue, offValue = pcall(unitAttackSpeed, "player")
    if ok then
      mainSpeed = Positive(mainValue)
      -- On this client the second speed can be present merely because slot
      -- 18 holds a gun. Require a real melee weapon in slot 17; shields,
      -- held items and unknown/uncached equipment never create an OH lane.
      if U.HasOffhandWeapon() then offSpeed = Positive(offValue) end
    end
  end

  local rangedSpeed
  if U.HasRangedWeapon() then
    if type(unitRangedDamage) == "function" then
      local ok, value = pcall(unitRangedDamage, "player")
      if ok then rangedSpeed = Positive(value) end
    end
  end

  SetLaneSpeed(lanes.main, mainSpeed, now)
  SetLaneSpeed(lanes.off, offSpeed, now)
  SetLaneSpeed(lanes.ranged, rangedSpeed, now)
end

local function MeleeInRange()
  -- U.MeleeInteractRange carries the CheckInteractDistance index quirk for
  -- every consumer; nil means the client could not answer.
  local inRange = U.MeleeInteractRange("target")
  if inRange == nil then return true end
  return inRange
end

local function RefreshRange()
  local ranged, inRange = U.RangedAttackState()
  local valid = U.IsAttackTargetValid()
  rangedInRange = valid and inRange == true
  -- Shoot's real min/max range wins over the generous melee proxy. Only one
  -- weapon mode is displayed, even if the client's attack flags overlap.
  meleeInRange = valid and MeleeInRange() and not (ranged and rangedInRange)
end

local function AnyLaneActive()
  local i
  for i = 1, table.getn(laneOrder) do
    local lane = laneOrder[i]
    if lane.active and LaneReady(lane) then return true end
  end
  return false
end

UpdateTickRate = function()
  if not anchor or not Tick then return end
  -- Weapon/range state keeps its established 0.08s fallback while idle.
  -- Promote to render-frame cadence only for a lane whose fill is moving.
  local interval = (EnsureConfig().enabled and AnyLaneActive()) and 0 or
                   STATE_INTERVAL
  if tickInterval == interval then return end
  tickInterval = interval
  U.RegisterUpdate("swingbar.tick", interval, Tick)
end

local function SetActive(lane, active, now)
  active = active and lane.speed ~= nil and true or false
  if lane.active == active then return end
  lane.active = active
  lane.lastText = nil
  if lane == lanes.ranged and lane.eventClock then
    ClearRangedClock()
  elseif lane.eventClock then
    ClearLaneClock(lane)
  elseif active then
    lane.startedAt = now
  end
  UpdateTickRate()
end

local function RefreshAttackState(now, forceAutoRepeatScan)
  if forceAutoRepeatScan then U.InvalidateRangedAttack() end
  local ranged, _, _, autoShot = U.RangedAttackState()
  local shotDriven = autoShot or U.HasBowOrGun()
  if lanes.ranged.shotDriven ~= shotDriven then
    lanes.ranged.shotDriven = shotDriven
    -- A wand keeps the older speed-driven fallback; only a measured bow/gun
    -- cycle drives the ranged lane from client events.
    lanes.ranged.eventClock = shotDriven
    ClearRangedClock()
  end
  local melee = false
  if type(U.IsAutoAttacking) == "function" then
    local ok, active = pcall(U.IsAutoAttacking)
    melee = ok and active and true or false
  end

  SetActive(lanes.main, melee and not ranged, now)
  SetActive(lanes.off, melee and not ranged, now)
  SetActive(lanes.ranged, ranged, now)
end

local function SetLaneShown(lane, shown)
  if lane.shown == shown then return end
  lane.shown = shown
  if shown then lane.frame:Show() else lane.frame:Hide() end
end

local function Layout()
  if not anchor then return end

  local unlocked = U.IsUnlocked and U.IsUnlocked()
  local enabled = EnsureConfig().enabled
  local mainShown = enabled and
                    ((lanes.main.active and meleeInRange and
                      LaneReady(lanes.main)) or unlocked) and
                    true or false
  local offShown = enabled and lanes.off.speed and
                   ((lanes.off.active and meleeInRange and
                     LaneReady(lanes.off)) or unlocked) and
                   true or false
  local rangedShown = enabled and lanes.ranged.speed and
                      ((lanes.ranged.active and rangedInRange and
                        LaneReady(lanes.ranged)) or unlocked) and
                      true or false
  if mainShown == layoutMainShown and offShown == layoutOffShown and
     rangedShown == layoutRangedShown then return end
  layoutMainShown, layoutOffShown, layoutRangedShown =
    mainShown, offShown, rangedShown

  SetLaneShown(lanes.main, mainShown)
  SetLaneShown(lanes.off, offShown)
  SetLaneShown(lanes.ranged, rangedShown)

  local count, previous, i = 0, nil, nil
  for i = 1, table.getn(laneOrder) do
    local lane = laneOrder[i]
    if lane.shown then
      lane.frame:ClearAllPoints()
      if previous then
        lane.frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -ROW_GAP)
      else
        lane.frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
      end
      previous = lane
      count = count + 1
    end
  end

  anchor:SetHeight(math.max(ROW_HEIGHT,
    count * ROW_HEIGHT + math.max(0, count - 1) * ROW_GAP))
end

local function OnRangedCastEvent(event)
  rangedClock.casting = event == "SPELLCAST_START" or event == "SPELLCAST_CHANNEL_START"
  rangedClock.blockedAt = Now()
  InvalidateRangedPulse()
end

local function OnRangedCooldown()
  if not EnsureConfig().enabled or not lanes.ranged or not lanes.ranged.shotDriven then return end
  local at = Now()
  if rangedClock.casting or rangedClock.blockedAt == at then return end
  local active, _, slot = U.RangedAttackState()
  if not active or not slot then return end
  local generation = rangedClock.generation

  -- The capture contains cooldown events during interruption BEFORE the stop
  -- event clears auto-repeat. Let the event batch finish and reject it if a
  -- stop/cast/equipment/target event invalidates the pending notification.
  U.DeferOnce("swingbar.ranged-shot", function()
    if generation ~= rangedClock.generation or rangedClock.casting or
       not EnsureConfig().enabled then return end
    local stillActive, _, currentSlot = U.RangedAttackState()
    if not stillActive or currentSlot ~= slot or not lanes.ranged.speed then return end
    SetActive(lanes.ranged, true, at)
    AnchorLane(lanes.ranged, at)
    RefreshRange()
    UpdateTickRate()
    Layout()
  end)
end

local function FormatLane(lane, remaining)
  local speed = lane.speed or 0
  local text = string.format("%s %.1f|%.1f", U.L(lane.labelKey), speed,
                             remaining)
  if text == lane.lastText then return end
  lane.lastText = text
  local separator = string.find(text, "|", 1, true)
  if lane.left then lane.left:SetText(string.sub(text, 1, separator - 1)) end
  if lane.right then lane.right:SetText(string.sub(text, separator + 1)) end
end

-- Read-only probe surface. No timer behavior changes: the focused rangedshot
-- capture compares this exact clock with the client's shot/cooldown events.
function U.RangedSwingTiming()
  local lane = lanes.ranged
  if not lane then return Now(), nil, nil, false, false, rangedInRange end
  return Now(), lane.speed, lane.startedAt, lane.active, lane.shown, rangedInRange
end

-- Same read-only shape as the ranged surface above, for the melee half of a
-- capture: shared clock, then both melee lanes. No timer behavior changes.
function U.MeleeSwingTiming()
  local main, off = lanes.main, lanes.off
  if not main then return Now() end
  return Now(), main.speed, main.startedAt, main.active, main.shown,
         off and off.speed, off and off.startedAt, off and off.active,
         off and off.shown, meleeInRange,
         -- Trailing so an existing capture's column order is unaffected: the
         -- cycle each lane is actually drawn at, once enough have been seen,
         -- then the count of reported swings behind the main-hand clock.
         LanePeriod(main), off and LanePeriod(off), main.swings or 0
end

local function DrawLane(lane, now)
  if not lane.shown then return end

  -- The label reports the weapon's speed; the fill runs on the observed cycle.
  local speed = LanePeriod(lane)
  if not speed then
    lane.bar:SetMinMaxValues(0, 1)
    lane.bar:SetValue(0.4)
    FormatLane(lane, 0)
    return
  end

  if (not lane.active or not LaneReady(lane)) and
     U.IsUnlocked and U.IsUnlocked() then
    lane.bar:SetMinMaxValues(0, speed)
    lane.bar:SetValue(speed * 0.4)
    FormatLane(lane, speed)
    return
  end

  if not lane.startedAt then
    if lane.eventClock then return end
    lane.startedAt = now
  end
  local elapsed = now - lane.startedAt
  if elapsed < 0 then elapsed = 0 end

  if lane.eventClock then
    -- Hold ready if movement, range or another action delays the next attack.
    -- Wrapping here would invent an attack and recreate the measured drift.
    elapsed = math.min(elapsed, speed)
  elseif elapsed >= speed then
    elapsed = math.mod(elapsed, speed)
    lane.startedAt = now - elapsed
  end

  lane.bar:SetMinMaxValues(0, speed)
  lane.bar:SetValue(elapsed)
  FormatLane(lane, math.max(0, speed - elapsed))
end

-- The client never says which hand produced a swing, so it is credited to the
-- lane its own clock says is due. The previous revision compared the absolute
-- distance to the due time, which let a lane still 0.3s early outrank one that
-- was already 0.4s late; overdue now always wins. A lane that has never been
-- anchored takes the swing outright, because that is the only way it can start.
local function ClaimMeleeLane(now)
  local best, bestScore
  local i
  for i = 1, 2 do
    local lane = (i == 1) and lanes.main or lanes.off
    if lane.active and lane.speed then
      if not lane.startedAt then return lane end
      local score = now - (lane.startedAt + LanePeriod(lane))
      if not best or score > bestScore then best, bestScore = lane, score end
    end
  end
  return best
end

-- observed is false for the combat-entry anchor, which is a first-swing marker
-- rather than a reported swing.
local function AnchorMeleeLane(lane, now, observed)
  if not lane then return end
  AnchorLane(lane, now)
  if observed then lane.swings = (lane.swings or 0) + 1 end
  UpdateTickRate()
  Layout()
end

-- White melee damage, crits and misses/dodges/parries all mark a completed
-- swing. rangedshot.v1 measured their arrival as regular to within 9ms across
-- four consecutive cycles, which is what makes them usable as the anchor.
local function OnMeleeSwing()
  if not EnsureConfig().enabled then return end
  local now = Now()
  AnchorMeleeLane(ClaimMeleeLane(now), now, true)
end

-- An on-next-swing ability consumes the main-hand swing and reports through the
-- spell channel instead, so without this the lane would sit at ready for a full
-- cycle after every Heroic Strike or Raptor Strike. Their names are class and
-- locale specific and are deliberately not matched: a spell hit only counts as
-- a swing when the main-hand clock is already at or past due, which is where
-- both Raptor Strikes in the capture landed, and which bounds the error of a
-- coincidental unrelated hit to SPECIAL_SWING_GRACE. It can never start the
-- lane -- an unanchored lane still waits for real white damage.
local function OnSpecialSwing()
  if not EnsureConfig().enabled then return end
  local lane = lanes.main
  if not lane.active or not lane.speed or not lane.startedAt then return end
  local now = Now()
  if now - lane.startedAt < LanePeriod(lane) - SPECIAL_SWING_GRACE then return end
  AnchorMeleeLane(lane, now, true)
end

local function BuildLane(name, labelKey, color)
  local frame = U.CreatePanel(anchor, {
    name = name,
    width = WIDTH,
    height = ROW_HEIGHT,
    background = M.color.healthBg,
    border = M.color.border,
  })

  local bar = U.CreateStatusBar(frame, {
    width = WIDTH - 2 * U.BorderSize(),
    height = ROW_HEIGHT - 2 * U.BorderSize(),
    color = color,
    background = { 0, 0, 0, 0 },
    texture = M.unitFrame.statusTexture,
  })
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", U.BorderSize(), -U.BorderSize())
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -U.BorderSize(), U.BorderSize())

  -- Parent the labels to the bar itself. A child frame's textures can draw in
  -- front of regions owned by its parent even when those regions use OVERLAY;
  -- keeping text and fill in the same frame makes OVERLAY reliably win.
  local left = U.CreateLabel(bar, {
    size = TEXT_SIZE,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if left then
    ApplySwingTextSize(left)
    left:SetPoint("LEFT", bar, "LEFT", 4, 0)
  end

  local right = U.CreateLabel(bar, {
    size = TEXT_SIZE,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "RIGHT",
  })
  if right then
    ApplySwingTextSize(right)
    right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  end

  frame:Hide()
  return {
    frame = frame,
    bar = bar,
    left = left,
    right = right,
    labelKey = labelKey,
    color = color,
    active = false,
    shown = false,
  }
end

local function Build()
  anchor = CreateFrame("Frame", "UnrealUISwingBarAnchor", UIParent)
  anchor:SetWidth(WIDTH)
  anchor:SetHeight(ROW_HEIGHT)

  lanes.main = BuildLane("UnrealUISwingBarMain", "SWING_BAR_MAIN", COLOR_MAIN)
  lanes.off = BuildLane("UnrealUISwingBarOff", "SWING_BAR_OFF", COLOR_OFF)
  lanes.ranged = BuildLane("UnrealUISwingBarRanged", "SWING_BAR_RANGED", COLOR_RANGED)
  -- Both melee lanes are always event driven. The ranged lane only becomes one
  -- once RefreshAttackState confirms a bow or gun rather than a wand.
  lanes.main.eventClock = true
  lanes.off.eventClock = true
  laneOrder[1], laneOrder[2], laneOrder[3] =
    lanes.main, lanes.off, lanes.ranged

  U.RegisterMover("swingbar", anchor, {
    label = U.L("MOVER_LABEL_SWING_BAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -185 },
    visible = function() return EnsureConfig().enabled end,
  })
end

Tick = function()
  if not anchor or not EnsureConfig().enabled then
    if anchor then Layout() end
    return
  end
  if U.PerfDisabled and U.PerfDisabled("swingbar") then return end

  local now = Now()
  if now >= nextEquipmentAt then
    nextEquipmentAt = now + EQUIPMENT_INTERVAL
    ReadWeaponSpeeds(now)
  end
  if now >= nextStateAt then
    nextStateAt = now + STATE_INTERVAL
    RefreshAttackState(now, false)
  end
  if now >= nextRangeAt then
    nextRangeAt = now + RANGE_INTERVAL
    RefreshRange()
  end

  Layout()
  DrawLane(lanes.main, now)
  DrawLane(lanes.off, now)
  DrawLane(lanes.ranged, now)
end

function U.ApplySwingBar()
  if not anchor then return end
  local now = Now()
  if EnsureConfig().enabled then
    nextEquipmentAt = 0
    nextStateAt = 0
    nextRangeAt = 0
    ReadWeaponSpeeds(now)
    RefreshAttackState(now, true)
    RefreshRange()
  else
    SetActive(lanes.main, false, now)
    SetActive(lanes.off, false, now)
    SetActive(lanes.ranged, false, now)
  end
  layoutMainShown, layoutOffShown, layoutRangedShown = nil, nil, nil
  Layout()
  UpdateTickRate()
end

function SB:OnInit()
  EnsureConfig()
end

function SB:OnEnable()
  EnsureConfig()
  if not anchor then Build() end

  local refresh = function()
    ClearRangedClock()
    rangedClock.casting = false
    U.InvalidateRangedAttack()
    nextEquipmentAt = 0
    nextStateAt = 0
    nextRangeAt = 0
  end
  local autoRepeatStart = function()
    ClearRangedClock()
    rangedClock.casting = false
    RefreshAttackState(Now(), true)
    nextRangeAt = 0
  end
  local autoRepeatStop = function()
    ClearRangedClock()
    rangedClock.casting = false
    U.InvalidateRangedAttack()
    SetActive(lanes.ranged, false, Now())
    nextRangeAt = 0
  end

  U.RegisterEvent("PLAYER_ENTER_COMBAT", function()
    local now = Now()
    SetActive(lanes.main, true, now)
    SetActive(lanes.off, true, now)
    -- meleeswing.v1 timed this event 10ms before the engagement's first white
    -- swing and 0.28s AFTER the attack toggle, so it marks the swing, not the
    -- toggle; rangedshot.v1 has it sharing a timestamp with an opening Raptor
    -- Strike. It only ever starts an unanchored lane, which is what makes the
    -- bar appear on an opener that an on-next-swing ability consumed.
    if lanes.main.active and lanes.main.speed and not lanes.main.startedAt then
      AnchorMeleeLane(lanes.main, now)
    end
  end)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    local now = Now()
    SetActive(lanes.main, false, now)
    SetActive(lanes.off, false, now)
  end)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS", OnMeleeSwing)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS", OnMeleeSwing)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES", OnMeleeSwing)
  U.RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE", OnSpecialSwing)
  U.RegisterEvent("START_AUTOREPEAT_SPELL", autoRepeatStart)
  U.RegisterEvent("STOP_AUTOREPEAT_SPELL", autoRepeatStop)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    InvalidateRangedPulse()
    nextRangeAt = 0
  end)
  U.RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", OnRangedCooldown)
  U.RegisterEvent("SPELLCAST_START", OnRangedCastEvent)
  U.RegisterEvent("SPELLCAST_STOP", OnRangedCastEvent)
  U.RegisterEvent("SPELLCAST_FAILED", OnRangedCastEvent)
  U.RegisterEvent("SPELLCAST_INTERRUPTED", OnRangedCastEvent)
  U.RegisterEvent("SPELLCAST_CHANNEL_START", OnRangedCastEvent)
  U.RegisterEvent("SPELLCAST_CHANNEL_STOP", OnRangedCastEvent)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", refresh)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", function()
    U.InvalidateRangedAttack()
    nextRangeAt = 0
  end)
  U.RegisterEvent("ACTIONBAR_PAGE_CHANGED", function()
    U.InvalidateRangedAttack()
    nextRangeAt = 0
  end)

  UpdateTickRate()
  U.ApplySwingBar()
end
