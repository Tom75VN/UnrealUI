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

local WIDTH_LIMIT = { min = 160, max = 600, step = 10 }
local HEIGHT_LIMIT = { min = 7, max = 30, step = 1 }
local MOVER_ID = "xpbar.xp"
local MOVER_CONTENT_WIDTH = 318
local MOVER_SLIDER_WIDTH = 150
local MOVER_SLIDER_COLUMN = 168

local COLOR_XP = M.color.xp
local COLOR_XP_RESTED = M.color.xpRested
local COLOR_REP_FALLBACK = { 0.50, 0.50, 0.50, 1.00 }
local COLOR_REP_EMPTY = { 0.35, 0.35, 0.35, 1.00 }

local config
local xpAnchor, xpBar, xpRestedBar, xpText
local repAnchor, repBar

-- Session experience tracking for the tooltip's rate lines. Held on one table
-- rather than as separate top-level locals (see the Lua local budget note in
-- .claude/rules/unreal-ui.md), and never persisted: "this session" means since
-- login or reload, not since the last zone change.
--
-- .elapsed is play time accumulated from the gap between successive samples
-- rather than from one login baseline, and .recent is the tail of the session
-- the rate is measured over.
local session = {
  xp = 0, lastXP = nil, lastXPMax = nil,
  elapsed = 0, lastTick = nil,
  recent = {},
}

-- Two samples further apart than this did not measure play time: the poll runs
-- every 2s, so a larger gap is a loading screen, a stalled client or a clock
-- that jumped, and the interval is dropped instead of counted.
local MAX_SAMPLE_GAP = 10
-- The rate is measured over the last RATE_WINDOW seconds of counted play time,
-- sampled every SAMPLE_EVERY seconds, and nothing shorter than MIN_SAMPLE is
-- extrapolated from.
local RATE_WINDOW = 1800
local SAMPLE_EVERY = 30
local MIN_SAMPLE = 60

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local function EnsureConfig()
  if not config then
    config = U.ModuleConfig("xpbar", {
      repEnabled = true,
      width = WIDTH,
      height = HEIGHT,
      showText = false,
    })
  end
  return config
end

local function ClampWidth(value)
  value = tonumber(value) or WIDTH
  if value < WIDTH_LIMIT.min then value = WIDTH_LIMIT.min end
  if value > WIDTH_LIMIT.max then value = WIDTH_LIMIT.max end
  return math.floor((value - WIDTH_LIMIT.min) / WIDTH_LIMIT.step + 0.5) *
         WIDTH_LIMIT.step + WIDTH_LIMIT.min
end

local function ClampHeight(value)
  value = tonumber(value) or HEIGHT
  if value < HEIGHT_LIMIT.min then value = HEIGHT_LIMIT.min end
  if value > HEIGHT_LIMIT.max then value = HEIGHT_LIMIT.max end
  return math.floor((value - HEIGHT_LIMIT.min) / HEIGHT_LIMIT.step + 0.5) *
         HEIGHT_LIMIT.step + HEIGHT_LIMIT.min
end

function U.GetXPBarSetting(key)
  local cfg = EnsureConfig()
  if key == "width" then return ClampWidth(cfg.width) end
  if key == "height" then return ClampHeight(cfg.height) end
  if key == "showText" then return cfg.showText and true or false end
  return nil
end

function U.XPBarLimits(key)
  if key == "width" then
    return WIDTH_LIMIT.min, WIDTH_LIMIT.max, WIDTH_LIMIT.step
  elseif key == "height" then
    return HEIGHT_LIMIT.min, HEIGHT_LIMIT.max, HEIGHT_LIMIT.step
  end
  return 0, 0, 1
end

local function SetXPBarLayout(width, height)
  if not xpAnchor then return end
  width = ClampWidth(width)
  height = ClampHeight(height)
  xpAnchor:SetWidth(width)
  xpAnchor:SetHeight(height)
  if xpText then xpText:SetWidth(width - 8) end
end

local function ApplyXPBarLayout()
  SetXPBarLayout(U.GetXPBarSetting("width"),
                 U.GetXPBarSetting("height"))
end

-- Used only by the mover sliders' live-input hook. The preview changes frame
-- geometry without writing SavedVariables or refreshing the panel; the normal
-- onChange callback commits the final stepped value when the thumb is released.
local function PreviewXPBarLayout(key, value)
  local width = key == "width" and value or U.GetXPBarSetting("width")
  local height = key == "height" and value or U.GetXPBarSetting("height")
  SetXPBarLayout(width, height)
end

function U.SetXPBarSetting(key, value)
  local cfg = EnsureConfig()
  if key == "width" then
    if not tonumber(value) then return false end
    cfg.width = ClampWidth(value)
  elseif key == "height" then
    if not tonumber(value) then return false end
    cfg.height = ClampHeight(value)
  elseif key == "showText" then
    cfg.showText = value and true or false
  else
    return false
  end

  U.ApplyXPBar()
  if type(U.RefreshMoverPanel) == "function" then
    U.RefreshMoverPanel(MOVER_ID)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildBar(name, fillColor, width, height)
  width = tonumber(width) or WIDTH
  height = tonumber(height) or HEIGHT
  local anchor = CreateFrame("Frame", name, UIParent)
  anchor:SetWidth(width)
  anchor:SetHeight(height)
  U.CreateBackdrop(anchor, { background = M.color.healthBg })

  local bar = U.CreateStatusBar(anchor, {
    width = width - 2 * U.BorderSize(),
    height = height - 2 * U.BorderSize(),
    color = fillColor,
    background = { 0, 0, 0, 0 },
  })
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", U.BorderSize(), -U.BorderSize())
  bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -U.BorderSize(), U.BorderSize())

  return anchor, bar
end

-- ---------------------------------------------------------------------------
-- Session experience
--
-- UnrealPfUI derives its session total from a PLAYER_ENTERING_WORLD baseline
-- and corrects it on PLAYER_LEVEL_UP by subtracting UnitXPMax. Neither event is
-- confirmed on this client (see the module header), so the total is instead
-- accumulated from the values RefreshXP already reads on its 2s poll: a level
-- boundary shows up as a changed UnitXPMax and is credited with the remainder
-- of the old level plus the carry into the new one. Two levels gained inside a
-- single poll interval undercount by one level, which is the accepted cost of
-- not depending on an unverified event. GetTime itself is documented
-- (documentation.json / global:System:GetTime) but not runtime verified, so it
-- is resolved and called defensively like the rest of this module's API use.
-- ---------------------------------------------------------------------------
local function Now()
  local getTime = U.G("GetTime")
  if type(getTime) ~= "function" then return nil end
  local ok, value = pcall(getTime)
  if not ok then return nil end
  return tonumber(value)
end

-- Counted play time, advanced by the gap since the previous sample. Measuring
-- it as a sum of small deltas instead of "now minus a login baseline" means no
-- single bad clock reading can poison the session length: a backwards reading
-- or a large forward jump simply fails the MAX_SAMPLE_GAP test and costs one
-- poll interval. The old baseline form produced the observed "1 xp/hour,
-- 147d remaining" tooltip: its baseline was ~45 days behind the GetTime the
-- tooltip then read, consistent with the first sample being taken before the
-- world clock this GetTime counts from was live. That cause is a hypothesis,
-- not runtime verified; the delta form is correct either way, since it never
-- depends on a single reading.
local function TrackElapsed()
  local now = Now()
  if not now then return end
  local last = session.lastTick
  session.lastTick = now
  if not last then return end
  local delta = now - last
  if delta > 0 and delta <= MAX_SAMPLE_GAP then
    session.elapsed = session.elapsed + delta
  end
end

-- One point of the rate window, recorded at most every SAMPLE_EVERY seconds of
-- counted time. The oldest sample is kept until the one behind it is itself a
-- full window old, so the window never shrinks below RATE_WINDOW while the
-- session is long enough to fill it.
local function TrackSample()
  local count = table.getn(session.recent)
  local head = count > 0 and session.recent[count] or nil
  if not head or (session.elapsed - head.at) >= SAMPLE_EVERY then
    table.insert(session.recent, { at = session.elapsed, xp = session.xp })
    count = count + 1
  end

  while count > 1 and (session.elapsed - session.recent[2].at) >= RATE_WINDOW do
    table.remove(session.recent, 1)
    count = count - 1
  end
end

local function TrackSession(xp, xpmax)
  local last, lastMax = session.lastXP, session.lastXPMax
  if last then
    if lastMax and xpmax ~= lastMax then
      -- Level boundary: finish the old level, then add the new level's total.
      session.xp = session.xp + math.max(lastMax - last, 0) + xp
    elseif xp >= last then
      session.xp = session.xp + (xp - last)
    end
  end

  session.lastXP, session.lastXPMax = xp, xpmax
  TrackElapsed()
  TrackSample()
end

-- Experience per second to extrapolate from: the recent window while it holds
-- a long enough stretch of counted time with a gain in it, so the estimate
-- follows how fast experience is coming in now, and the whole session when it
-- does not, so an idle stretch reads as a slow rate rather than as no answer.
-- nil while neither sample is long enough to mean anything.
local function SessionRate()
  local oldest = session.recent[1]
  if oldest then
    local span, gain = session.elapsed - oldest.at, session.xp - oldest.xp
    if span >= MIN_SAMPLE and gain > 0 then return gain / span end
  end
  if session.elapsed >= MIN_SAMPLE and session.xp > 0 then
    return session.xp / session.elapsed
  end
  return nil
end

local function FormatDuration(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return nil end

  if seconds >= 86400 then
    return math.floor(seconds / 86400) .. U.L("XPTIP_UNIT_DAY") .. " " ..
           math.floor(math.mod(seconds, 86400) / 3600) .. U.L("XPTIP_UNIT_HOUR")
  elseif seconds >= 3600 then
    return math.floor(seconds / 3600) .. U.L("XPTIP_UNIT_HOUR") .. " " ..
           math.floor(math.mod(seconds, 3600) / 60) .. U.L("XPTIP_UNIT_MINUTE")
  elseif seconds >= 60 then
    return math.floor(seconds / 60) .. U.L("XPTIP_UNIT_MINUTE") .. " " ..
           math.floor(math.mod(seconds, 60)) .. U.L("XPTIP_UNIT_SECOND")
  end
  return math.floor(seconds) .. U.L("XPTIP_UNIT_SECOND")
end

-- A short gap above the session block. GameTooltip has no per-line spacing
-- API, so the gap is one empty line whose own font height is shrunk to
-- SPACER_HEIGHT. That line belongs to the shared GameTooltip, so the swap is
-- transient: the line's own font object is captured on the way in and put back
-- when this tooltip hides, before any other tooltip can reuse the row. Held on
-- one table rather than as separate top-level locals.
local SPACER_HEIGHT = 5
local spacer = { font = nil, line = nil, original = nil }

local function SpacerFont()
  if spacer.font then return spacer.font end
  local path = U.ResolveFont()
  if not path then return nil end
  local ok, font = pcall(CreateFont, "UnrealUIXPTipSpacerFont")
  if not ok or not font then return nil end
  if not pcall(font.SetFont, font, path, SPACER_HEIGHT) then return nil end
  spacer.font = font
  return font
end

local function ReleaseSpacer()
  if spacer.line and spacer.original then
    pcall(spacer.line.SetFontObject, spacer.line, spacer.original)
  end
  spacer.line, spacer.original = nil, nil
end

-- Falls through to no gap at all rather than a full-height blank line: an
-- unresolvable font or an unreadable row is a cosmetic loss, while leaving a
-- shrunk font on a shared tooltip row is not.
local function AddSpacer()
  ReleaseSpacer()
  local font = SpacerFont()
  if not font then return end
  if not pcall(GameTooltip.AddLine, GameTooltip, " ") then return end

  local countOk, count = pcall(GameTooltip.NumLines, GameTooltip)
  if not countOk or type(count) ~= "number" or count < 1 then return end
  local line = U.G("GameTooltipTextLeft" .. count)
  if not line or not line.SetFontObject or not line.GetFontObject then return end

  local originalOk, original = pcall(line.GetFontObject, line)
  if not originalOk or not original then return end
  if pcall(line.SetFontObject, line, font) then
    spacer.line, spacer.original = line, original
  end
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
  GameTooltip:AddLine(U.L("XPTIP_TITLE"))
  GameTooltip:AddDoubleLine(U.L("XPTIP_XP"), xp .. " / " .. xpmax .. " (" .. math.floor(xp / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(U.L("XPTIP_REMAINING"), remaining .. " (" .. math.floor(remaining / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 1, 1, 1)

  local isResting = U.G("IsResting")
  if type(isResting) == "function" then
    local restingOk, resting = pcall(isResting)
    if restingOk and resting and resting ~= 0 then
      GameTooltip:AddDoubleLine(U.L("XPTIP_STATUS"), U.L("XPTIP_RESTING"), 1, 1, 1, 0.3, 0.7, 1)
    end
  end

  if rested > 0 then
    GameTooltip:AddDoubleLine(U.L("XPTIP_RESTED"), "+" .. rested .. " (" .. math.floor(rested / xpmax * 100 + 0.5) .. "%)", 1, 1, 1, 0.3, 0.3, 1)
  end

  -- Session, rate and estimate, as UnrealPfUI's xpbar tooltip shows them,
  -- except for where the rate comes from: pfUI divides the whole session's
  -- gain by "GetTime now minus GetTime at PLAYER_ENTERING_WORLD", which both
  -- dilutes the estimate over a long session and cannot recover from a bad
  -- baseline. SessionRate measures counted play time instead. Both derived
  -- lines read "--" until there is enough of it to extrapolate from, rather
  -- than printing a guess from a few seconds.
  local perSecond = SessionRate()

  AddSpacer()
  GameTooltip:AddDoubleLine(U.L("XPTIP_SESSION"), tostring(session.xp), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(U.L("XPTIP_PER_HOUR"),
    perSecond and tostring(math.floor(perSecond * 3600)) or "--", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(U.L("XPTIP_TIME_LEFT"),
    (perSecond and FormatDuration(remaining / perSecond)) or "--", 1, 1, 1, 1, 1, 1)

  GameTooltip:Show()
end

local function XPTooltipHide()
  GameTooltip:Hide()
  ReleaseSpacer()
end

local function Build()
  xpAnchor, xpBar = BuildBar("UnrealUIXPBarAnchor", COLOR_XP,
                            U.GetXPBarSetting("width"),
                            U.GetXPBarSetting("height"))

  -- The rested portion sits behind the current-xp fill on its own bar, at a
  -- lower frame level, so it reads as an extension rather than covering it.
  xpRestedBar = U.CreateStatusBar(xpAnchor, {
    width = U.GetXPBarSetting("width") - 2 * U.BorderSize(),
    height = U.GetXPBarSetting("height") - 2 * U.BorderSize(),
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

  -- A raised owned layer keeps the optional readout above both the current-XP
  -- and rested fills. It is mouse-transparent so the anchor retains its
  -- tooltip and mover interactions.
  local textLayer = CreateFrame("Frame", nil, xpAnchor)
  textLayer:SetAllPoints(xpAnchor)
  pcall(textLayer.EnableMouse, textLayer, false)
  if barOk and tonumber(barLevel) then
    pcall(textLayer.SetFrameLevel, textLayer, barLevel + 5)
  end
  xpText = U.CreateLabel(textLayer, {
    size = M.fontSize.tiny,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    width = U.GetXPBarSetting("width") - 8,
    height = 12,
    justify = "CENTER",
    shadowOffset = M.compactTextShadowOffset,
    shadowColor = M.color.shadowStrong,
  })
  if xpText then
    xpText:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    xpText:Hide()
  end

  U.RegisterMover(MOVER_ID, xpAnchor, {
    label = U.L("MOVER_LABEL_XP_BAR"),
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 66 },
  })

  xpAnchor:EnableMouse(true)
  xpAnchor:SetScript("OnEnter", XPTooltipShow)
  xpAnchor:SetScript("OnLeave", XPTooltipHide)

  repAnchor, repBar = BuildBar("UnrealUIReputationBarAnchor",
                              COLOR_REP_FALLBACK, WIDTH, HEIGHT)

  U.RegisterMover("xpbar.reputation", repAnchor, {
    label = U.L("MOVER_LABEL_REP_BAR"),
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

local function ApplyXPText(xp, xpmax)
  if not xpText then return end
  if not U.GetXPBarSetting("showText") or not tonumber(xpmax) or xpmax <= 0 then
    xpText:Hide()
    return
  end

  xp = tonumber(xp) or 0
  local percent = math.floor(xp / xpmax * 100 + 0.5)
  xpText:SetText(U.L("XPBAR_TEXT_FORMAT", xp, xpmax, percent))
  xpText:Show()
end

local function RefreshXP()
  if not xpAnchor then return end

  local unitXP = U.G("UnitXP")
  local unitXPMax = U.G("UnitXPMax")
  if type(unitXP) ~= "function" or type(unitXPMax) ~= "function" then
    if xpText then xpText:Hide() end
    xpAnchor:Hide()
    return
  end

  local xpOk, xp = pcall(unitXP, "player")
  local maxOk, xpmax = pcall(unitXPMax, "player")
  xp = (xpOk and tonumber(xp)) or 0
  xpmax = (maxOk and tonumber(xpmax)) or 0

  -- UnitXPMax reports 0 once no further experience is tracked (max level).
  if xpmax <= 0 then
    if xpText then xpText:Hide() end
    xpAnchor:Hide()
    return
  end
  xpAnchor:Show()

  TrackSession(xp, xpmax)
  SetBar(xpBar, xp, xpmax)
  ApplyXPText(xp, xpmax)

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
  ApplyXPBarLayout()
  RefreshXP()
  RefreshReputation()
end

-- ---------------------------------------------------------------------------
-- Contextual edit-mode settings
-- ---------------------------------------------------------------------------
local function BuildMoverPanel(frame, contentTop)
  local pad = U.MoverPanelPad()
  local widgets = {}

  local function BeginResize()
    if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
  end

  local showText = U.CreateCheckbox(frame, {
    name = "UnrealUIXPBarMoverShowText",
    text = U.L("XPBAR_SHOW_TEXT"),
    textWidth = MOVER_CONTENT_WIDTH - 20,
    value = U.GetXPBarSetting("showText"),
    onChange = function(value) U.SetXPBarSetting("showText", value) end,
  })
  showText.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
  table.insert(widgets, showText)

  local min, max, step = U.XPBarLimits("width")
  local width = U.CreateSlider(frame, {
    name = "UnrealUIXPBarMoverWidth",
    text = U.L("XPBAR_WIDTH"),
    width = MOVER_SLIDER_WIDTH,
    boxWidth = 60,
    min = min,
    max = max,
    step = step,
    value = U.GetXPBarSetting("width"),
    onInputStart = BeginResize,
    onInput = function(value) PreviewXPBarLayout("width", value) end,
    onChange = function(value) U.SetXPBarSetting("width", value) end,
  })
  width.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop - 58)
  table.insert(widgets, width)

  min, max, step = U.XPBarLimits("height")
  local height = U.CreateSlider(frame, {
    name = "UnrealUIXPBarMoverHeight",
    text = U.L("XPBAR_HEIGHT"),
    width = MOVER_SLIDER_WIDTH,
    boxWidth = 60,
    min = min,
    max = max,
    step = step,
    value = U.GetXPBarSetting("height"),
    onInputStart = BeginResize,
    onInput = function(value) PreviewXPBarLayout("height", value) end,
    onChange = function(value) U.SetXPBarSetting("height", value) end,
  })
  height.SetPoint("TOPLEFT", frame, "TOPLEFT",
                  pad + MOVER_SLIDER_COLUMN, contentTop - 58)
  table.insert(widgets, height)

  local function Refresh()
    showText.SetValue(U.GetXPBarSetting("showText"))
    width.SetValue(U.GetXPBarSetting("width"))
    height.SetValue(U.GetXPBarSetting("height"))
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function XP:OnInit()
  EnsureConfig()
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel(MOVER_ID, {
      name = "UnrealUIXPBarMoverSettings",
      width = MOVER_CONTENT_WIDTH + U.MoverPanelPad() * 2,
      height = 148,
      build = BuildMoverPanel,
      title = function() return U.L("MOVER_LABEL_XP_BAR") end,
      preferVertical = true,
    })
  end
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
