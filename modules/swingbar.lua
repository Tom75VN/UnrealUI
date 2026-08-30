-- unrealUI :: modules/swingbar.lua
--
-- Movable auto-attack timing for the main hand, off hand and ranged weapon.
-- UnitAttackSpeed (including its optional off-hand return), UnitRangedDamage,
-- GetInventoryItemLink and IsAutoRepeatAction are OFFICIAL_CLIENT_DOCUMENTATION
-- on this client. GetTime is measured by api.json / core.time.v1.
--
-- The compact runtime evidence has no focused capture for the classic
-- CHAT_MSG_COMBAT_SELF_* swing events. They are therefore accelerators only:
-- when one arrives it resynchronises the closest melee lane, while the
-- documented attack state and weapon speed keep the display functional when
-- no combat-log event is delivered. The combat events and
-- UNIT_INVENTORY_CHANGED follow targeted UnrealPfUI working-source recipes;
-- START/STOP_AUTOREPEAT_SPELL specifically follows libs/librange.lua. The
-- documented IsAutoRepeatAction scan remains the ranged-state authority.
--
-- A lane is only shown while the target is actually reachable by that attack.
-- The ranged lane can ask the client directly, because IsActionInRange reports
-- 0 for an out-of-range auto-repeat slot. The melee lanes cannot: the same
-- documentation states melee Auto Attack always returns 1 and never measures
-- distance, so they fall back to CheckInteractDistance, which this client
-- applies as one interact range regardless of the passed index. That range is
-- wider than melee reach, so the melee lanes appear slightly before the first
-- swing can land rather than lingering while the player runs in.

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
local MAX_ACTION_SLOT = 120
local STATE_INTERVAL = 0.08
local EQUIPMENT_INTERVAL = 0.5
local AUTOREPEAT_SCAN_INTERVAL = 1
local RANGE_INTERVAL = 0.15
-- documentation.json / global:Inspection:CheckInteractDistance: this client
-- does not apply a different yard range per index, and any index of 4 or more
-- always returns false. The value below only satisfies the signature.
local INTERACT_DISTANCE_INDEX = 1

local COLOR_MAIN = { 1.00, 1.00, 1.00, 1.00 }
local COLOR_OFF = { 1.00, 1.00, 1.00, 1.00 }
local COLOR_RANGED = { 1.00, 1.00, 1.00, 1.00 }

-- These documented globals are stable for the life of the addon. Resolve them
-- once: the periodic auto-repeat fallback scans up to 120 action slots, and
-- repeating the guarded global lookup for every slot would turn it into an
-- avoidable pcall burst.
local getTime = U.G("GetTime")
local getInventoryItemLink = U.G("GetInventoryItemLink")
local unitAttackSpeed = U.G("UnitAttackSpeed")
local unitRangedDamage = U.G("UnitRangedDamage")
local isAutoRepeatAction = U.G("IsAutoRepeatAction")
local checkInteractDistance = U.G("CheckInteractDistance")
local isActionInRange = U.G("IsActionInRange")
local getTimeVerified = false

local config
local anchor
local lanes = {}
local laneOrder = {}
local autoRepeatSlot
local nextStateAt = 0
local nextEquipmentAt = 0
local nextAutoRepeatScanAt = 0
local nextRangeAt = 0
local meleeInRange = true
local rangedInRange = true
local layoutMainShown, layoutOffShown, layoutRangedShown
local tickInterval
local Tick
local UpdateTickRate

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
  if lane.speed and speed and lane.startedAt then
    local progress = (now - lane.startedAt) / lane.speed
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    lane.startedAt = now - progress * speed
  elseif speed then
    lane.startedAt = now
  else
    lane.startedAt = nil
  end

  lane.speed = speed
  lane.lastText = nil
end

local function RangedWeaponEquipped()
  if type(getInventoryItemLink) ~= "function" then return false end
  local ok, link = pcall(getInventoryItemLink, "player", 18)
  return ok and type(link) == "string" and link ~= ""
end

local function ReadWeaponSpeeds(now)
  local mainSpeed, offSpeed
  if type(unitAttackSpeed) == "function" then
    local ok, mainValue, offValue = pcall(unitAttackSpeed, "player")
    if ok then
      mainSpeed = Positive(mainValue)
      offSpeed = Positive(offValue)
    end
  end

  local rangedSpeed
  if RangedWeaponEquipped() then
    if type(unitRangedDamage) == "function" then
      local ok, value = pcall(unitRangedDamage, "player")
      if ok then rangedSpeed = Positive(value) end
    end
  end

  SetLaneSpeed(lanes.main, mainSpeed, now)
  SetLaneSpeed(lanes.off, offSpeed, now)
  SetLaneSpeed(lanes.ranged, rangedSpeed, now)
end

local function IsAutoRepeatSlot(slot)
  if type(isAutoRepeatAction) ~= "function" then return false end
  local ok, result = pcall(isAutoRepeatAction, slot)
  return ok and result ~= nil and result ~= false and result ~= 0 and
         result ~= ""
end

local function ReadAutoRepeat(forceScan, now)
  if autoRepeatSlot then
    if IsAutoRepeatSlot(autoRepeatSlot) then return true end
    autoRepeatSlot = nil
  end

  if not lanes.ranged.speed then return false end
  if not forceScan and now < nextAutoRepeatScanAt then return false end
  nextAutoRepeatScanAt = now + AUTOREPEAT_SCAN_INTERVAL

  local slot
  for slot = 1, MAX_ACTION_SLOT do
    if IsAutoRepeatSlot(slot) then
      autoRepeatSlot = slot
      return true
    end
  end
  return false
end

-- Both checks degrade open: an absent or erroring API leaves the lanes visible
-- rather than hiding a swing timer that is working correctly.
local function MeleeInRange()
  if type(checkInteractDistance) ~= "function" then return true end
  local ok, result = pcall(checkInteractDistance, "target",
                           INTERACT_DISTANCE_INDEX)
  if not ok then return true end
  return result ~= nil and result ~= false and result ~= 0 and result ~= ""
end

local function RangedInRange()
  if not autoRepeatSlot then return true end
  if type(isActionInRange) ~= "function" then return true end
  local ok, result = pcall(isActionInRange, autoRepeatSlot)
  if not ok then return true end
  -- knowledge.json / actionbars.range_calls_runtime_unverified: this client
  -- substitutes booleans for Vanilla's 1/nil while keeping the numeric 0 for
  -- out of range. A nil means "no target", which an auto-repeat attack cannot
  -- be in, so it counts as unreadable rather than as a reason to hide.
  return result ~= 0 and result ~= false
end

local function RefreshRange()
  meleeInRange = MeleeInRange()
  rangedInRange = RangedInRange()
end

local function AnyLaneActive()
  return (lanes.main and lanes.main.active) or
         (lanes.off and lanes.off.active) or
         (lanes.ranged and lanes.ranged.active) or false
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
  if active then lane.startedAt = now end
  UpdateTickRate()
end

local function RefreshAttackState(now, forceAutoRepeatScan)
  local melee = false
  if type(U.IsAutoAttacking) == "function" then
    local ok, active = pcall(U.IsAutoAttacking)
    melee = ok and active and true or false
  end

  SetActive(lanes.main, melee, now)
  SetActive(lanes.off, melee, now)
  SetActive(lanes.ranged, ReadAutoRepeat(forceAutoRepeatScan, now), now)
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
                    ((lanes.main.active and meleeInRange) or unlocked) and
                    true or false
  local offShown = enabled and lanes.off.speed and
                   ((lanes.off.active and meleeInRange) or unlocked) and
                   true or false
  local rangedShown = enabled and lanes.ranged.speed and
                      ((lanes.ranged.active and rangedInRange) or unlocked) and
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

local function DrawLane(lane, now)
  if not lane.shown then return end

  local speed = lane.speed
  if not speed then
    lane.bar:SetMinMaxValues(0, 1)
    lane.bar:SetValue(0.4)
    FormatLane(lane, 0)
    return
  end

  if not lane.active and U.IsUnlocked and U.IsUnlocked() then
    lane.bar:SetMinMaxValues(0, speed)
    lane.bar:SetValue(speed * 0.4)
    FormatLane(lane, speed)
    return
  end

  if not lane.startedAt then lane.startedAt = now end
  local elapsed = now - lane.startedAt
  if elapsed < 0 then elapsed = 0 end

  -- The clock is the guaranteed fallback when no swing combat-log event is
  -- delivered. Carry overshoot so the next cycle stays smooth and stable.
  if elapsed >= speed then
    elapsed = math.mod(elapsed, speed)
    lane.startedAt = now - elapsed
  end

  lane.bar:SetMinMaxValues(0, speed)
  lane.bar:SetValue(elapsed)
  FormatLane(lane, math.max(0, speed - elapsed))
end

local function ResetMeleeSwing()
  if not EnsureConfig().enabled then return end
  local now = Now()
  local main, off = lanes.main, lanes.off
  if not main.active then return end

  local lane = main
  if off.active and off.speed and off.startedAt then
    local mainDue = math.abs(now - ((main.startedAt or now) + (main.speed or 0)))
    local offDue = math.abs(now - (off.startedAt + off.speed))
    if offDue < mainDue then lane = off end
  end
  lane.startedAt = now
  lane.lastText = nil
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
    nextAutoRepeatScanAt = 0
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
    nextEquipmentAt = 0
    nextStateAt = 0
    nextRangeAt = 0
  end
  local autoRepeatStart = function()
    nextAutoRepeatScanAt = 0
    RefreshAttackState(Now(), true)
  end
  local autoRepeatStop = function()
    autoRepeatSlot = nil
    SetActive(lanes.ranged, false, Now())
  end

  U.RegisterEvent("PLAYER_ENTER_COMBAT", function()
    local now = Now()
    SetActive(lanes.main, true, now)
    SetActive(lanes.off, true, now)
  end)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    local now = Now()
    SetActive(lanes.main, false, now)
    SetActive(lanes.off, false, now)
  end)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS", ResetMeleeSwing)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS", ResetMeleeSwing)
  U.RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES", ResetMeleeSwing)
  U.RegisterEvent("START_AUTOREPEAT_SPELL", autoRepeatStart)
  U.RegisterEvent("STOP_AUTOREPEAT_SPELL", autoRepeatStop)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", function() nextRangeAt = 0 end)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", refresh)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", function()
    autoRepeatSlot = nil
    nextAutoRepeatScanAt = 0
  end)
  U.RegisterEvent("ACTIONBAR_PAGE_CHANGED", function()
    autoRepeatSlot = nil
    nextAutoRepeatScanAt = 0
  end)

  UpdateTickRate()
  U.ApplySwingBar()
end
