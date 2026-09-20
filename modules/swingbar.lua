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

-- Thirty percent narrower than the previous 180-unit lane.
local FLAT_WIDTH = 126
local FLAT_TEXT_SIZE = 6
-- Twenty percent thinner than the previous 8-unit lane. The compact text is
-- taller than the bar, so stacked lanes retain enough separation for their
-- labels not to collide.
local FLAT_ROW_HEIGHT = 6.4
local FLAT_ROW_GAP = 3
-- Lane width is the one thing edit mode changes about this bar (user request,
-- 2026-09-21). A stored 0 means "the width this theme's lane art was authored
-- at", so the default stays right when the theme changes under a saved profile.
local WIDTH_LIMIT = { min = 100, max = 400, step = 1 }
-- Lane height runs from the height the theme's art is drawn at up to double
-- it (user request, 2026-09-21), so its limits are derived rather than fixed.
local HEIGHT_STEP = 1
-- With a weapon in each hand the main-hand and off-hand lanes stack, and the
-- authored lane height leaves the lower label clipped by the lane above it.
-- Both lanes gain two units while an off-hand lane exists (user request,
-- 2026-09-21); a single lane keeps the height its art was authored at.
local DUAL_WIELD_HEIGHT_BONUS = 2
local MOVER_ID = "swingbar"
local MOVER_CONTENT_WIDTH = 200
local MOVER_SLIDER_WIDTH = 150
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
local foreverStyle = false
local laneWidth = FLAT_WIDTH
local rowHeight = FLAT_ROW_HEIGHT
local laneHeight = FLAT_ROW_HEIGHT
local rowGap = FLAT_ROW_GAP
local textSize = FLAT_TEXT_SIZE

local function ApplyAtlasCell(texture, cell)
  if not texture or not cell then return end
  texture:SetTexture(M.modernWow.texture.swingTimer)
  texture:SetTexCoord(cell[1], cell[2], cell[3], cell[4])
end

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
  if not config then config = U.ModuleConfig("swingbar",
      { enabled = true, width = 0, height = 0 }) end
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
  return pcall(label.SetFont, label, path, FLAT_TEXT_SIZE, "OUTLINE")
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

-- The drawn lane height, which is rowHeight plus the dual-wield bonus. Kept
-- apart from rowHeight so the theme's authored height stays the baseline.
local function ApplyLaneHeight(height)
  if laneHeight == height then return end
  laneHeight = height
  local i
  for i = 1, table.getn(laneOrder) do
    local lane = laneOrder[i]
    if lane and lane.frame then lane.frame:SetHeight(height) end
  end
end

-- Both of a lane's labels move together, so one offset per lane is enough.
-- extra is added to the theme's own labelDrop rather than replacing it.
local function ApplyLabelDrop(lane, extra)
  if not lane or lane.labelDrop == extra then return end
  lane.labelDrop = extra

  local style = foreverStyle and M.modernWow.swingTimer or nil
  local inset = style and style.labelInset or 4
  local y = (style and style.labelDrop or 0) + extra
  if lane.left then
    lane.left:ClearAllPoints()
    lane.left:SetPoint("LEFT", lane.bar, "LEFT", inset, y)
  end
  if lane.right then
    lane.right:ClearAllPoints()
    lane.right:SetPoint("RIGHT", lane.bar, "RIGHT", -inset, y)
  end
end

local function Layout()
  if not anchor then return end

  -- An off-hand speed is only ever set when U.HasOffhandWeapon confirms a real
  -- melee weapon in slot 17, so it is this module's dual-wield test.
  local stacked = lanes.off.speed and true or false
  ApplyLaneHeight(rowHeight + (stacked and DUAL_WIELD_HEIGHT_BONUS or 0))

  -- The stacked pair's text offsets are theme media, so the flat modern lanes
  -- keep their own centred labels.
  local drop = foreverStyle and M.modernWow.swingTimer.stackedLabelDrop or nil
  ApplyLabelDrop(lanes.main, (stacked and drop and drop.main) or 0)
  ApplyLabelDrop(lanes.off, (stacked and drop and drop.off) or 0)
  ApplyLabelDrop(lanes.ranged, 0)

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
        lane.frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -rowGap)
      else
        lane.frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
      end
      previous = lane
      count = count + 1
    end
  end

  anchor:SetHeight(math.max(laneHeight,
    count * laneHeight + math.max(0, count - 1) * rowGap))
end

-- 0 or anything unreadable falls back to the authored lane width of whichever
-- lane art the active theme draws.
local function ClampWidth(value)
  value = tonumber(value) or 0
  if value <= 0 then
    return foreverStyle and M.modernWow.swingTimer.width or FLAT_WIDTH
  end
  if value < WIDTH_LIMIT.min then value = WIDTH_LIMIT.min end
  if value > WIDTH_LIMIT.max then value = WIDTH_LIMIT.max end
  return math.floor(value / WIDTH_LIMIT.step + 0.5) * WIDTH_LIMIT.step
end

-- The height the active theme's lane art is drawn at, which is also the
-- smallest height offered: the slider only ever makes a lane taller.
local function LaneBaseHeight()
  if foreverStyle then
    local style = M.modernWow.swingTimer
    return style.height - style.heightTrim
  end
  return FLAT_ROW_HEIGHT
end

local function ClampHeight(value)
  local base = LaneBaseHeight()
  value = tonumber(value) or 0
  if value <= base then return base end
  if value > base * 2 then return base * 2 end
  return math.floor((value - base) / HEIGHT_STEP + 0.5) * HEIGHT_STEP + base
end

-- Every lane is one frame wide; the bar, its labels and the pip are anchored
-- to it, so only the frames, the mover anchor and the label shadow carry a
-- width of their own.
local function ApplyLaneWidth(value)
  laneWidth = ClampWidth(value)
  if not anchor then return end
  anchor:SetWidth(laneWidth)

  local style = foreverStyle and M.modernWow.swingTimer or nil
  local i
  for i = 1, table.getn(laneOrder) do
    local lane = laneOrder[i]
    if lane and lane.frame then lane.frame:SetWidth(laneWidth) end
    -- The label shadow is a fixed slice of the authored lane rather than a
    -- baked 171 units, so it keeps its share of a resized one.
    if lane and lane.titleShadow and style then
      lane.titleShadow:SetWidth(style.shadowWidth * laneWidth / style.width)
    end
  end
end

function U.SwingBarWidthLimits()
  return WIDTH_LIMIT.min, WIDTH_LIMIT.max, WIDTH_LIMIT.step
end

function U.GetSwingBarWidth()
  return ClampWidth(EnsureConfig().width)
end

-- Live preview while the slider thumb is held. Nothing is stored until the
-- drag is released and the panel calls U.SetSwingBarWidth.
function U.PreviewSwingBarWidth(value)
  ApplyLaneWidth(value)
end

function U.SetSwingBarWidth(value)
  local cfg = EnsureConfig()
  if not tonumber(value) then return cfg.width end
  cfg.width = ClampWidth(value)
  ApplyLaneWidth(cfg.width)
  return cfg.width
end

function U.SwingBarHeightLimits()
  local base = LaneBaseHeight()
  return base, base * 2, HEIGHT_STEP
end

function U.GetSwingBarHeight()
  return ClampHeight(EnsureConfig().height)
end

-- rowHeight is the baseline Layout adds the dual-wield bonus to, so a height
-- change is applied by clearing the cached layout state and running Layout,
-- which re-heights the lanes and resizes the mover anchor in one pass.
local function ApplyLaneBaseHeight(value)
  rowHeight = ClampHeight(value)
  layoutMainShown, layoutOffShown, layoutRangedShown = nil, nil, nil
  Layout()
end

function U.PreviewSwingBarHeight(value)
  ApplyLaneBaseHeight(value)
end

function U.SetSwingBarHeight(value)
  local cfg = EnsureConfig()
  if not tonumber(value) then return cfg.height end
  cfg.height = ClampHeight(value)
  ApplyLaneBaseHeight(cfg.height)
  return cfg.height
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

local function SetLaneValue(lane, value)
  lane.bar:SetValue(value)
  if not lane.fillCell then return end

  -- Forever's native StatusBar reveals this atlas cell. Crop the UV by the
  -- same fraction as the region width so its pattern never stretches.
  local minimum, maximum = lane.bar:GetMinMaxValues()
  local range = maximum - minimum
  local progress = range > 0 and (value - minimum) / range or 0
  if progress < 0 then progress = 0 end
  if progress > 1 then progress = 1 end

  local cell = lane.fillCell
  lane.bar.uuiFillTexture:SetTexCoord(
    cell[1], cell[1] + (cell[2] - cell[1]) * progress,
    cell[3], cell[4])

  if lane.pip then lane.pip:Show() end
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
    SetLaneValue(lane, 0.4)
    FormatLane(lane, 0)
    return
  end

  if (not lane.active or not LaneReady(lane)) and
     U.IsUnlocked and U.IsUnlocked() then
    lane.bar:SetMinMaxValues(0, speed)
    SetLaneValue(lane, speed * 0.4)
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
  SetLaneValue(lane, elapsed)
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

local function BuildLane(name, labelKey, color, fillKey)
  local style = foreverStyle and M.modernWow.swingTimer or nil
  local frame, rim
  if style then
    frame = CreateFrame("Frame", name, anchor)
    frame:SetWidth(laneWidth)
    frame:SetHeight(rowHeight)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    ApplyAtlasCell(background, style.background)
    background:SetAllPoints(frame)
  else
    frame = U.CreatePanel(anchor, {
      name = name,
      width = laneWidth,
      height = rowHeight,
      background = M.color.healthBg,
      border = M.color.border,
    })
  end

  local bar = U.CreateStatusBar(frame, {
    width = laneWidth,
    height = rowHeight,
    color = color,
    background = { 0, 0, 0, 0 },
    texture = style and M.modernWow.texture.swingTimer or M.unitFrame.statusTexture,
  })
  bar:ClearAllPoints()
  if style then
    -- The fill sits just inside the framed lane (user request, 2026-09-21).
    -- The frame texture itself is drawn afterwards, on a frame above the bar,
    -- because the bar is a child frame and would otherwise cover a rim owned
    -- by its parent whatever layer that rim used.
    local inset = style.fillInset
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    ApplyAtlasCell(bar.uuiFillTexture, style.fill[fillKey])

    rim = CreateFrame("Frame", nil, frame)
    rim:SetAllPoints(frame)
    rim:SetFrameLevel(bar:GetFrameLevel() + 1)
    rim:EnableMouse(false)
    local border = rim:CreateTexture(nil, "ARTWORK")
    ApplyAtlasCell(border, style.frame)
    border:SetAllPoints(rim)
  else
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", U.BorderSize(), -U.BorderSize())
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
                 -U.BorderSize(), U.BorderSize())
  end

  local pip, titleShadow
  local fillCell
  if style then
    fillCell = style.fill[fillKey]
    -- The pip stands taller than the lane and reads as part of the frame art,
    -- so it belongs on the rim rather than under it.
    pip = rim:CreateTexture(nil, "OVERLAY")
    ApplyAtlasCell(pip, style.pip)
    pip:SetWidth(style.pipWidth)
    pip:SetHeight(style.pipHeight)
    pip:SetPoint("RIGHT", bar.uuiFillTexture, "RIGHT", 0, 0)
    pip:Hide()

    titleShadow = bar:CreateTexture(nil, "OVERLAY")
    ApplyAtlasCell(titleShadow, style.shadow)
    titleShadow:SetWidth(style.shadowWidth)
    titleShadow:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    titleShadow:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  end

  -- Parent the labels to the bar itself. A child frame's textures can draw in
  -- front of regions owned by its parent even when those regions use OVERLAY;
  -- keeping text and fill in the same frame makes OVERLAY reliably win.
  local left = U.CreateLabel(bar, {
    size = textSize,
    color = M.color.text,
    inherits = style and "GameFontHighlightSmall" or "GameFontNormalSmall",
    justify = "LEFT",
  })
  if left then
    if not style then ApplySwingTextSize(left) end
    left:SetPoint("LEFT", bar, "LEFT", style and style.labelInset or 4,
                  style and style.labelDrop or 0)
  end

  local right = U.CreateLabel(bar, {
    size = textSize,
    color = M.color.text,
    inherits = style and "GameFontHighlightSmall" or "GameFontNormalSmall",
    justify = "RIGHT",
  })
  if right then
    if not style then ApplySwingTextSize(right) end
    right:SetPoint("RIGHT", bar, "RIGHT",
                   style and -style.labelInset or -4,
                   style and style.labelDrop or 0)
  end

  frame:Hide()
  return {
    frame = frame,
    bar = bar,
    left = left,
    right = right,
    pip = pip,
    titleShadow = titleShadow,
    fillCell = fillCell,
    labelKey = labelKey,
    color = color,
    active = false,
    shown = false,
  }
end

local function Build()
  -- The swing-timer atlas is the client's own Forever art (FileDataID
  -- 8344036), not imported Dragonflight chrome, so classic-wow draws the same
  -- three-lane bar as modern-wow (user request, 2026-09-21). Only the flat
  -- modern theme keeps the plain panel lanes.
  local activeStyle = U.GetActiveThemeStyle()
  foreverStyle = activeStyle == "modern-wow" or activeStyle == "classic-wow"
  if foreverStyle then
    local style = M.modernWow.swingTimer
    laneWidth = style.width
    rowHeight = style.height - style.heightTrim
    rowGap = style.bottomPadding + style.laneGap
    textSize = M.fontSize.small
  end
  laneWidth = ClampWidth(EnsureConfig().width)
  rowHeight = ClampHeight(EnsureConfig().height)
  laneHeight = rowHeight

  anchor = CreateFrame("Frame", "UnrealUISwingBarAnchor", UIParent)
  anchor:SetWidth(laneWidth)
  anchor:SetHeight(rowHeight)

  lanes.main = BuildLane("UnrealUISwingBarMain", "SWING_BAR_MAIN", COLOR_MAIN,
                         "main")
  lanes.off = BuildLane("UnrealUISwingBarOff", "SWING_BAR_OFF", COLOR_OFF,
                        "off")
  lanes.ranged = BuildLane("UnrealUISwingBarRanged", "SWING_BAR_RANGED",
                           COLOR_RANGED, "ranged")
  -- Both melee lanes are always event driven. The ranged lane only becomes one
  -- once RefreshAttackState confirms a bow or gun rather than a wand.
  lanes.main.eventClock = true
  lanes.off.eventClock = true
  laneOrder[1], laneOrder[2], laneOrder[3] =
    lanes.main, lanes.off, lanes.ranged

  U.RegisterMover(MOVER_ID, anchor, {
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

-- The contextual panel the mover shows when this bar's handle is selected
-- (core/moverpanel.lua). One control: how wide a lane is drawn.
local function BuildMoverPanel(frame, contentTop)
  local pad = U.MoverPanelPad()
  local widgets = {}

  local min, max, step = U.SwingBarWidthLimits()
  local width = U.CreateSlider(frame, {
    name = "UnrealUISwingBarMoverWidth",
    text = U.L("SWING_BAR_WIDTH"),
    width = MOVER_SLIDER_WIDTH,
    boxWidth = 60,
    min = min,
    max = max,
    step = step,
    value = U.GetSwingBarWidth(),
    onInputStart = function()
      if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
    end,
    onInput = function(value) U.PreviewSwingBarWidth(value) end,
    onChange = function(value) U.SetSwingBarWidth(value) end,
  })
  width.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
  table.insert(widgets, width)

  min, max, step = U.SwingBarHeightLimits()
  local height = U.CreateSlider(frame, {
    name = "UnrealUISwingBarMoverHeight",
    text = U.L("SWING_BAR_HEIGHT"),
    width = MOVER_SLIDER_WIDTH,
    boxWidth = 60,
    min = min,
    max = max,
    step = step,
    value = U.GetSwingBarHeight(),
    onInputStart = function()
      if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
    end,
    onInput = function(value) U.PreviewSwingBarHeight(value) end,
    onChange = function(value) U.SetSwingBarHeight(value) end,
  })
  height.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop - 58)
  table.insert(widgets, height)

  local function Refresh()
    width.SetValue(U.GetSwingBarWidth())
    height.SetValue(U.GetSwingBarHeight())
  end

  return widgets, Refresh
end

function SB:OnInit()
  EnsureConfig()
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel(MOVER_ID, {
      name = "UnrealUISwingBarMoverSettings",
      width = MOVER_CONTENT_WIDTH + U.MoverPanelPad() * 2,
      height = 162,
      build = BuildMoverPanel,
      title = function() return U.L("MOVER_LABEL_SWING_BAR") end,
      preferVertical = true,
    })
  end
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
