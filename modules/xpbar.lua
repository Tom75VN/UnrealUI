-- unrealUI :: modules/xpbar.lua
--
-- Two thin movable bars: player experience (with a rested overlay) and
-- watched-faction reputation. The reputation bar can be hidden from the
-- General settings page; the XP bar is required scope and always shown.
--
-- Evidence gap: query_compat.py has no runtime record for UnitXP, UnitXPMax,
-- GetXPExhaustion, GetFactionInfo, PLAYER_XP_UPDATE, UPDATE_EXHAUSTION,
-- UPDATE_FACTION or PLAYER_LEVEL_UP on this client. Per the evidence-gap
-- fallback this module defaults to UnrealPfUI's demonstrated recipe
-- (modules/xpbar.lua: UnitXP/UnitXPMax/GetXPExhaustion, a GetFactionInfo scan
-- for the watched faction, and that same event list). This is WORKING_SOURCE
-- evidence from a working implementation on this same client, not runtime
-- verification.

local U = UnrealUI
local M = U.media

local XP = U.RegisterModule("xpbar")

local WIDTH = 300
local HEIGHT = 7
local GAP = 3

local COLOR_XP = { 0.55, 0.32, 0.87, 1.00 }
local COLOR_XP_RESTED = { 0.30, 0.20, 0.55, 1.00 }
local COLOR_REP_FALLBACK = { 0.50, 0.50, 0.50, 1.00 }
local COLOR_REP_EMPTY = { 0.35, 0.35, 0.35, 1.00 }

local config
local xpAnchor, xpBar, xpRestedBar
local repAnchor, repBar

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local function EnsureConfig()
  if not config then config = U.ModuleConfig("xpbar", { repEnabled = true }) end
  return config
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildBar(name, fillColor)
  local anchor = CreateFrame("Frame", name, UIParent)
  anchor:SetWidth(WIDTH)
  anchor:SetHeight(HEIGHT)
  U.CreateBackdrop(anchor, { background = M.color.healthBg })

  local bar = U.CreateStatusBar(anchor, {
    width = WIDTH - 2 * U.BorderSize(),
    height = HEIGHT - 2 * U.BorderSize(),
    color = fillColor,
    background = { 0, 0, 0, 0 },
  })
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", U.BorderSize(), -U.BorderSize())
  bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -U.BorderSize(), U.BorderSize())

  return anchor, bar
end

-- ---------------------------------------------------------------------------
-- Rest XP tooltip (WORKING_SOURCE fallback: UnrealPfUI modules/xpbar.lua
-- OnEnter, since query_compat.py has no runtime record for GetXPExhaustion
-- or IsResting on this client).
-- ---------------------------------------------------------------------------
local function XPTooltipShow()
  local unitXP, unitXPMax = U.G("UnitXP"), U.G("UnitXPMax")
  if type(unitXP) ~= "function" or type(unitXPMax) ~= "function" then return end

  local xpOk, xp = pcall(unitXP, "player")
  local maxOk, xpmax = pcall(unitXPMax, "player")
  xp = (xpOk and tonumber(xp)) or 0
  xpmax = (maxOk and tonumber(xpmax)) or 0
  if xpmax <= 0 then return end

  local rested = 0
  local exhaustion = U.G("GetXPExhaustion")
  if type(exhaustion) == "function" then
    local restOk, value = pcall(exhaustion)
    if restOk then rested = tonumber(value) or 0 end
  end

  local remaining = xpmax - xp

  GameTooltip:SetOwner(xpAnchor, "ANCHOR_CURSOR")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("Experience")
  GameTooltip:AddDoubleLine("XP", xp .. " / " .. xpmax .. " (" .. math.floor(xp / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Remaining", remaining .. " (" .. math.floor(remaining / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 1, 1, 1)

  local isResting = U.G("IsResting")
  if type(isResting) == "function" then
    local restingOk, resting = pcall(isResting)
    if restingOk and resting and resting ~= 0 then
      GameTooltip:AddDoubleLine("Status", "Resting", 1, 1, 1, 0.3, 0.7, 1)
    end
  end

  if rested > 0 then
    GameTooltip:AddDoubleLine("Rested", "+" .. rested .. " (" .. math.floor(rested / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 0.3, 0.3, 1)
  end

  GameTooltip:Show()
end

local function XPTooltipHide()
  GameTooltip:Hide()
end

local function Build()
  xpAnchor, xpBar = BuildBar("UnrealUIXPBarAnchor", COLOR_XP)

  -- The rested portion sits behind the current-xp fill on its own bar, at a
  -- lower frame level, so it reads as an extension rather than covering it.
  xpRestedBar = U.CreateStatusBar(xpAnchor, {
    width = WIDTH - 2 * U.BorderSize(),
    height = HEIGHT - 2 * U.BorderSize(),
    color = COLOR_XP_RESTED,
    background = { 0, 0, 0, 0 },
  })
  xpRestedBar:ClearAllPoints()
  xpRestedBar:SetPoint("TOPLEFT", xpAnchor, "TOPLEFT", U.BorderSize(), -U.BorderSize())
  xpRestedBar:SetPoint("BOTTOMRIGHT", xpAnchor, "BOTTOMRIGHT", -U.BorderSize(), U.BorderSize())
  local restedOk, restedLevel = pcall(xpRestedBar.GetFrameLevel, xpRestedBar)
  local barOk, barLevel = pcall(xpBar.GetFrameLevel, xpBar)
  if restedOk and barOk and tonumber(barLevel) then
    pcall(xpRestedBar.SetFrameLevel, xpRestedBar, barLevel)
    pcall(xpBar.SetFrameLevel, xpBar, barLevel + 1)
  end

  U.RegisterMover("xpbar.xp", xpAnchor, {
    label = "Experience Bar",
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 66 },
  })

  xpAnchor:EnableMouse(true)
  xpAnchor:SetScript("OnEnter", XPTooltipShow)
  xpAnchor:SetScript("OnLeave", XPTooltipHide)

  repAnchor, repBar = BuildBar("UnrealUIReputationBarAnchor", COLOR_REP_FALLBACK)

  U.RegisterMover("xpbar.reputation", repAnchor, {
    label = "Reputation Bar",
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 66 - HEIGHT - GAP },
    -- A disabled bar keeps its stored position but offers no drag handle in
    -- edit mode; see core/mover.lua / modules/microbar.lua.
    visible = function() return config and config.repEnabled end,
  })
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function SetBar(bar, value, maximum)
  if not bar then return end
  maximum = tonumber(maximum) or 0
  value = tonumber(value) or 0
  if maximum <= 0 then maximum, value = 1, 0 end
  pcall(bar.SetMinMaxValues, bar, 0, maximum)
  pcall(bar.SetValue, bar, value)
end

local function RefreshXP()
  if not xpAnchor then return end

  local unitXP = U.G("UnitXP")
  local unitXPMax = U.G("UnitXPMax")
  if type(unitXP) ~= "function" or type(unitXPMax) ~= "function" then
    xpAnchor:Hide()
    return
  end

  local xpOk, xp = pcall(unitXP, "player")
  local maxOk, xpmax = pcall(unitXPMax, "player")
  xp = (xpOk and tonumber(xp)) or 0
  xpmax = (maxOk and tonumber(xpmax)) or 0

  -- UnitXPMax reports 0 once no further experience is tracked (max level).
  if xpmax <= 0 then
    xpAnchor:Hide()
    return
  end
  xpAnchor:Show()

  SetBar(xpBar, xp, xpmax)

  local exhaustion = U.G("GetXPExhaustion")
  local rested = 0
  if type(exhaustion) == "function" then
    local restOk, value = pcall(exhaustion)
    if restOk then rested = tonumber(value) or 0 end
  end

  if rested > 0 then
    SetBar(xpRestedBar, math.min(xp + rested, xpmax), xpmax)
    xpRestedBar:Show()
  else
    xpRestedBar:Hide()
  end
end

local function RefreshReputation()
  if not repAnchor then return end

  if not config or not config.repEnabled then
    repAnchor:Hide()
    return
  end
  repAnchor:Show()

  local getFactionInfo = U.G("GetFactionInfo")
  if type(getFactionInfo) ~= "function" then
    SetBar(repBar, 0, 1)
    U.SetStatusBarColor(repBar, M.Unpack(COLOR_REP_EMPTY))
    return
  end

  local i, name, standingID, barMin, barMax, barValue, isWatched
  local found = false
  for i = 1, 99 do
    local ok, n, _, sID, bMin, bMax, bValue, _, _, _, _, watched =
      pcall(getFactionInfo, i)
    if not ok or n == nil then break end
    name, standingID, barMin, barMax, barValue, isWatched = n, sID, bMin, bMax, bValue, watched
    if isWatched then
      found = true
      break
    end
  end

  if not found then
    SetBar(repBar, 0, 1)
    U.SetStatusBarColor(repBar, M.Unpack(COLOR_REP_EMPTY))
    return
  end

  local maximum = (tonumber(barMax) or 1) - (tonumber(barMin) or 0)
  local value = (tonumber(barValue) or 0) - (tonumber(barMin) or 0)
  SetBar(repBar, value, maximum)

  local colors = U.G("FACTION_BAR_COLORS")
  local color = type(colors) == "table" and colors[standingID]
  if color and color.r then
    U.SetStatusBarColor(repBar, (color.r + 0.3), (color.g + 0.3), (color.b + 0.3), 1)
  else
    U.SetStatusBarColor(repBar, M.Unpack(COLOR_REP_FALLBACK))
  end
end

-- Public so modules/settings.lua's General page can flip the checkbox without
-- reaching into this module's internals.
function U.ApplyXPBar()
  RefreshXP()
  RefreshReputation()
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function XP:OnInit()
  EnsureConfig()
end

function XP:OnEnable()
  EnsureConfig()
  if not xpAnchor then Build() end

  local i, events = nil, {
    "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
  }
  for i = 1, table.getn(events) do U.RegisterEvent(events[i], RefreshXP) end

  local repEvents = { "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_ENTERING_WORLD" }
  for i = 1, table.getn(repEvents) do U.RegisterEvent(repEvents[i], RefreshReputation) end

  -- Neither event list is confirmed in the compact evidence; polling keeps
  -- both bars correct even when one does not arrive.
  U.RegisterUpdate("xpbar.refresh", 2, function()
    if U.PerfDisabled and U.PerfDisabled("xpbar") then return end
    RefreshXP()
    RefreshReputation()
  end)

  RefreshXP()
  RefreshReputation()
end
