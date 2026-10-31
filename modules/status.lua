-- unrealUI :: modules/status.lua
--
-- A compact, movable readout for the small pieces of session information that
-- are useful at a glance: frame rate, network latency, money and equipment
-- durability.  Everything sits in one restrained information strip, matching
-- the reference layout without introducing a general panel system.
--
-- The compact runtime DB has no direct records for GetFramerate, GetNetStats,
-- GetMoney, tooltip inventory scanning, or the durability events.  Per the
-- evidence-gap fallback, this uses the demonstrated UnrealPfUI panel recipe:
-- GetFramerate/GetNetStats, GetMoney/PLAYER_MONEY, and an off-screen
-- GameTooltip scanner over equipped inventory slots, respectively. This is
-- WORKING_SOURCE evidence, not runtime verification.
--
-- A second overlay reads total server population from /who. SendWho,
-- SetWhoToUI, and GetNumWhoResults's second return (the server-reported total
-- match count) are OFFICIAL_CLIENT_DOCUMENTATION, DOCUMENTED_NOT_RUNTIME_
-- VERIFIED; the query sequence (SetWhoToUI(1), SendWho, wait for
-- WHO_LIST_UPDATE, restore SetWhoToUI(0), and suppress FriendsFrame_OnEvent
-- while pending so the native Who UI does not react) follows UnrealPfUI's
-- modules/chat.lua ScanWhoName, WORKING_SOURCE evidence, not runtime
-- verification either. /who sends only a single request per
-- POP_REFRESH_INTERVAL, capping the addon at one SendWho call per interval.
--
-- The local clock uses the global date(), documented for this client as Lua
-- 5.1 os.date exposed as a global that formats local OS time unless the
-- pattern starts with '!' (OFFICIAL_CLIENT_DOCUMENTATION,
-- DOCUMENTED_NOT_RUNTIME_VERIFIED). This is the computer's time, not the
-- in-world server clock that GetGameTime reports.
--
-- RUNTIME_FAILURE_CONFIRMED (in-game, 2026-08-21): a per-zone reading taken
-- with SendWho('z-"<GetRealZoneText()>"') came back higher than the
-- unfiltered total-online reading taken a minute earlier (167 vs 165) --
-- impossible for a real zone subset of the server total. This server's /who
-- does not honour the z- zone tag (it silently returns the unfiltered
-- result), so the zone breakdown was removed; only the total online count
-- is queried.

local U = UnrealUI
local M = U.media

local S = U.RegisterModule("status")

local WIDTH = 260
local HEIGHT = 24
local MODULE_GAP = 14
local COIN_GAP = 1
local HORIZONTAL_PADDING = 6
local INVENTORY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
-- Zero-padded 24h, so the rendered clock keeps a constant width and the strip
-- does not reflow every time the hour rolls over into a single digit.
local TIME_FORMAT = "%H:%M"

local POP_WIDTH = 120
-- One /who request per interval, so the addon never sends more than one
-- SendWho call per POP_REFRESH_INTERVAL.
local POP_REFRESH_INTERVAL = 60

local COLOR_GOOD = { 0.33, 0.93, 0.33, 1.00 }
local COLOR_WARN = { 0.96, 0.68, 0.04, 1.00 }
local COLOR_BAD  = { 1.00, 0.28, 0.20, 1.00 }
-- Coin art and colours come from core/media.lua's M.money, so the overlay,
-- the bag total and every shared readout draw the same three UnrealUI coin
-- textures under every theme rather than keeping module-local copies.
local COLOR_GOLD = M.money.gold.color
local COLOR_SILVER = M.money.silver.color
local COLOR_COPPER = M.money.copper.color
local OVERLAY_BACKGROUND = { 0.035, 0.035, 0.035, 0.20 }
-- Width of an overlay with nothing to draw: wide enough that its edit-mode
-- anchor stays easy to find and click, so it can be switched back on.
local EMPTY_WIDTH = 120

-- The status strip's readouts, left to right, with the switch each one has.
local ELEMENTS = { "fps", "latency", "durability", "time", "money" }
local ELEMENT_KEYS = {
  fps = "showFps", latency = "showLatency", durability = "showDurability",
  time = "showTime", money = "showMoney",
}

-- Built once: Config() runs ~30 times per refresh, and a new defaults table
-- each time was the module's garbage. Booleans only, so sharing it is safe.
local CONFIG_DEFAULTS = {
  enabled = true, onlineEnabled = true,
  showFps = true, showLatency = true, showDurability = true,
  showTime = true, showMoney = true,
}

local function Config()
  if not U.db then
    -- Before SavedVariables load ModuleConfig hands back the defaults table
    -- itself; give a copy so an early write cannot change the shared one.
    local copy, key, value = {}, nil, nil
    for key, value in pairs(CONFIG_DEFAULTS) do copy[key] = value end
    return copy
  end
  return U.ModuleConfig("status", CONFIG_DEFAULTS)
end

local function ElementShown(name)
  local config = Config()
  return config.enabled and config[ELEMENT_KEYS[name]] and true or false
end

-- The fill only: the anchor frame itself stays shown, because the edit-mode
-- handle is its child (core/mover.lua CreateHandle) -- the same rule as
-- modules/bagbar.lua bb.HideControls.
local function SetOverlayFill(frame, shown)
  if not frame then return end
  local r, g, b, a = M.Unpack(OVERLAY_BACKGROUND)
  if not shown then a = 0 end
  if frame.uuiFill then U.SetColor(frame.uuiFill, r, g, b, a) end
  if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, r, g, b, a) end
end

local anchor
local display
local scanner
local durabilityPattern
local durabilityAge = 0

local popAnchor
local popDisplay
local popPending -- true while a /who request is in flight
local popOriginalFriendsFrameOnEvent

local function SetLabel(label, text, color)
  if not label then return end
  label:SetText(text)
  if color then pcall(label.SetTextColor, label, M.Unpack(color)) end
end

local function ThresholdColor(value, good, warning, higherIsBetter)
  value = tonumber(value)
  if not value then return M.color.textDim end

  if higherIsBetter then
    if value >= good then return COLOR_GOOD end
    if value >= warning then return COLOR_WARN end
  else
    if value <= good then return COLOR_GOOD end
    if value <= warning then return COLOR_WARN end
  end
  return COLOR_BAD
end

local function BuildCoin(parent, denom, color, width)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetWidth(width or 40)
  holder:SetHeight(14)

  holder.icon = holder:CreateTexture(nil, "ARTWORK")
  holder.icon:SetWidth(12)
  holder.icon:SetHeight(12)
  -- The coin fills its own texture, so it centres on the holder and the
  -- number keeps the common text baseline; M.money.iconY lifts the icon only.
  holder.icon:SetPoint("RIGHT", holder, "RIGHT", 0, M.money.iconY or 0)
  pcall(holder.icon.SetTexture, holder.icon, M.money[denom].texture)

  holder.label = U.CreateLabel(holder, {
    shadow = false, privateFont = true,
    size = M.fontSize.small,
    color = color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then holder.label:SetPoint("RIGHT", holder, "RIGHT", -13, 0) end
  return holder
end

local function SetCoinValue(coin, value, color)
  if not coin then return end
  SetLabel(coin.label, value, color)

  -- Size the holder to the rendered amount rather than reserving the width of
  -- a two-digit value. This removes the visible gap between denominations.
  local ok, textWidth = coin.label and pcall(coin.label.GetStringWidth, coin.label)
  textWidth = ok and tonumber(textWidth) or (string.len(value) * 7)
  coin.contentWidth = math.ceil(textWidth) + 13
  coin:SetWidth(coin.contentWidth)
end

local function LabelWidth(label)
  if not label then return 0 end
  local ok, width = pcall(label.GetStringWidth, label)
  return ok and math.ceil(tonumber(width) or 0) or 0
end

-- One readout of the strip: the region the chain anchors, the region the next
-- readout hangs off, every region it shows, and its rendered width.
local function CaptionPart(caption, value)
  return {
    first = caption, last = value, regions = { caption, value },
    Width = function() return LabelWidth(caption) + 2 + LabelWidth(value) end,
  }
end

-- Chains only the readouts that are switched on, so a hidden one leaves no
-- gap, and sizes the strip to them. Points are rewritten only when the set of
-- shown readouts changes; the width follows the values on every refresh.
local function UpdateOverlayWidth()
  if not anchor or not display then return end

  local key = ""
  local i
  for i = 1, table.getn(ELEMENTS) do
    key = key .. (ElementShown(ELEMENTS[i]) and "1" or "0")
  end

  if key ~= display.layoutKey then
    display.layoutKey = key
    local prev = nil
    for i = 1, table.getn(ELEMENTS) do
      local part = display.parts[ELEMENTS[i]]
      local shown = ElementShown(ELEMENTS[i])
      local n
      for n = 1, table.getn(part.regions) do
        if shown then part.regions[n]:Show() else part.regions[n]:Hide() end
      end
      if shown then
        part.first:ClearAllPoints()
        if prev then
          part.first:SetPoint("LEFT", prev, "RIGHT", MODULE_GAP, 0)
        else
          part.first:SetPoint("LEFT", anchor, "LEFT", HORIZONTAL_PADDING, 0)
        end
        prev = part.last
      end
    end
    SetOverlayFill(anchor, prev ~= nil)
  end

  local width = 0
  for i = 1, table.getn(ELEMENTS) do
    if ElementShown(ELEMENTS[i]) then
      if width > 0 then width = width + MODULE_GAP end
      width = width + display.parts[ELEMENTS[i]].Width()
    end
  end
  if width > 0 then
    width = width + HORIZONTAL_PADDING * 2
  else
    width = EMPTY_WIDTH
  end
  anchor:SetWidth(width)
end

local function Build()
  anchor = CreateFrame("Frame", "UnrealUIStatusAnchor", UIParent)
  -- HUD strata, under the bag windows (U.LowerWindowBelowInterface).
  pcall(anchor.SetFrameStrata, anchor, "LOW")
  anchor:SetWidth(WIDTH)
  anchor:SetHeight(HEIGHT)
  U.CreateBackdrop(anchor, {
    background = OVERLAY_BACKGROUND,
    border = false,
  })

  display = {}
  display.fpsCaption = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.fpsCaption:SetPoint("LEFT", anchor, "LEFT", HORIZONTAL_PADDING, 0)
  display.fpsCaption:SetText(U.L("STATUS_FPS"))

  display.fpsValue = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.fpsValue:SetPoint("LEFT", display.fpsCaption, "RIGHT", 2, 0)

  display.latencyCaption = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.latencyCaption:SetPoint("LEFT", display.fpsValue, "RIGHT", MODULE_GAP, 0)
  display.latencyCaption:SetText(U.L("STATUS_LATENCY"))

  display.latencyValue = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.latencyValue:SetPoint("LEFT", display.latencyCaption, "RIGHT", 2, 0)

  display.durabilityCaption = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.durabilityCaption:SetPoint("LEFT", display.latencyValue, "RIGHT", MODULE_GAP, 0)
  display.durabilityCaption:SetText(U.L("STATUS_DURABILITY"))

  display.durabilityValue = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.durabilityValue:SetPoint("LEFT", display.durabilityCaption, "RIGHT", 2, 0)

  display.timeValue = U.CreateLabel(anchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.timeValue:SetPoint("LEFT", display.durabilityValue, "RIGHT", MODULE_GAP, 0)

  -- Chain the denominations directly after the clock. Their widths follow
  -- the rendered values, so short values do not leave empty columns.
  display.gold = BuildCoin(anchor, "gold", COLOR_GOLD, 26)
  display.silver = BuildCoin(anchor, "silver", COLOR_SILVER, 26)
  display.copper = BuildCoin(anchor, "copper", COLOR_COPPER, 26)
  display.gold:SetPoint("LEFT", display.timeValue, "RIGHT", MODULE_GAP, 0)
  display.silver:SetPoint("LEFT", display.gold, "RIGHT", COIN_GAP, 0)
  display.copper:SetPoint("LEFT", display.silver, "RIGHT", COIN_GAP, 0)

  display.parts = {
    fps = CaptionPart(display.fpsCaption, display.fpsValue),
    latency = CaptionPart(display.latencyCaption, display.latencyValue),
    durability = CaptionPart(display.durabilityCaption, display.durabilityValue),
    time = {
      first = display.timeValue, last = display.timeValue,
      regions = { display.timeValue },
      Width = function() return LabelWidth(display.timeValue) end,
    },
    money = {
      first = display.gold, last = display.copper,
      regions = { display.gold, display.silver, display.copper },
      Width = function()
        return (display.gold.contentWidth or 26) + COIN_GAP +
               (display.silver.contentWidth or 26) + COIN_GAP +
               (display.copper.contentWidth or 26)
      end,
    },
  }

  U.RegisterMover("status.overlay", anchor, {
    label = U.L("MOVER_LABEL_STATUS"),
    default = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 20, y = 20 },
  })
end

local function UpdatePopulationWidth()
  if not popAnchor or not popDisplay then return end

  local shown = Config().onlineEnabled and true or false
  if shown ~= popDisplay.shown then
    popDisplay.shown = shown
    if shown then
      popDisplay.serverValue:Show()
      popDisplay.serverSuffix:Show()
    else
      popDisplay.serverValue:Hide()
      popDisplay.serverSuffix:Hide()
    end
    SetOverlayFill(popAnchor, shown)
  end
  if not shown then
    popAnchor:SetWidth(EMPTY_WIDTH)
    return
  end

  local width = HORIZONTAL_PADDING
  width = width + LabelWidth(popDisplay.serverValue)
  width = width + 2 + LabelWidth(popDisplay.serverSuffix)
  width = width + HORIZONTAL_PADDING
  popAnchor:SetWidth(width)
end

local function BuildPopulation()
  popAnchor = CreateFrame("Frame", "UnrealUIPopulationAnchor", UIParent)
  -- HUD strata, under the bag windows (U.LowerWindowBelowInterface).
  pcall(popAnchor.SetFrameStrata, popAnchor, "LOW")
  popAnchor:SetWidth(POP_WIDTH)
  popAnchor:SetHeight(HEIGHT)
  U.CreateBackdrop(popAnchor, {
    background = OVERLAY_BACKGROUND,
    border = false,
  })

  popDisplay = {}
  popDisplay.serverValue = U.CreateLabel(popAnchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  popDisplay.serverValue:SetPoint("LEFT", popAnchor, "LEFT", HORIZONTAL_PADDING, 0)
  popDisplay.serverValue:SetText("--")

  popDisplay.serverSuffix = U.CreateLabel(popAnchor, {
    shadow = false, privateFont = true,
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  popDisplay.serverSuffix:SetPoint("LEFT", popDisplay.serverValue, "RIGHT", 2, 0)
  popDisplay.serverSuffix:SetText(U.L("STATUS_ONLINE"))

  U.RegisterMover("status.population", popAnchor, {
    label = U.L("MOVER_LABEL_ONLINE_COUNT"),
    default = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 20, y = 20 + HEIGHT + 6 },
  })

  UpdatePopulationWidth()
end

-- Marks a /who request in flight and suppresses the native Friends/Who frame
-- for its duration so a background population poll cannot pop or repaint it
-- (the UnrealPfUI recipe this follows: FriendsFrame_OnEvent is swapped for a
-- no-op while SetWhoToUI(1) targets the Who UI, then restored on completion).
local function RequestWho()
  if popPending then return end

  local setWhoToUI = U.G("SetWhoToUI")
  local sendWho = U.G("SendWho")
  if type(setWhoToUI) ~= "function" or type(sendWho) ~= "function" then return end

  local originalHandler = U.G("FriendsFrame_OnEvent")
  if type(originalHandler) == "function" then
    popOriginalFriendsFrameOnEvent = originalHandler
    U.SetG("FriendsFrame_OnEvent", function() end)
  else
    popOriginalFriendsFrameOnEvent = nil
  end

  popPending = true
  pcall(setWhoToUI, 1)
  pcall(sendWho, "")
end

local function FinishWho()
  if popOriginalFriendsFrameOnEvent then
    U.SetG("FriendsFrame_OnEvent", popOriginalFriendsFrameOnEvent)
    popOriginalFriendsFrameOnEvent = nil
  end
  local setWhoToUI = U.G("SetWhoToUI")
  if type(setWhoToUI) == "function" then pcall(setWhoToUI, 0) end
  popPending = nil
end

local function OnWhoListUpdate()
  if not popPending then return end

  local getNumWhoResults = U.G("GetNumWhoResults")
  local total
  if type(getNumWhoResults) == "function" then
    local ok, _, serverTotal = pcall(getNumWhoResults)
    if ok then total = tonumber(serverTotal) end
  end

  FinishWho()

  if not popDisplay then return end
  SetLabel(popDisplay.serverValue, total and tostring(total) or "--", M.color.text)
  UpdatePopulationWidth()
end

-- Ticks once per POP_REFRESH_INTERVAL; caps the addon at one SendWho call
-- per interval.
local function RefreshPopulation()
  if U.PerfDisabled and U.PerfDisabled("status") then return end
  -- A hidden count sends no /who at all.
  if not Config().onlineEnabled then return end
  if popPending then return end -- previous request never resolved; skip this tick
  RequestWho()
end

local function RefreshPerformance()
  if not display then return end
  if not ElementShown("fps") and not ElementShown("latency") then return end

  local framerate = U.G("GetFramerate")
  local ok, fps = false, nil
  if type(framerate) == "function" then ok, fps = pcall(framerate) end
  fps = ok and tonumber(fps) or nil
  SetLabel(display.fpsValue, fps and tostring(math.floor(fps)) or "--",
           ThresholdColor(fps, 30, 20, true))

  local netStats = U.G("GetNetStats")
  local latency
  if type(netStats) == "function" then
    local netOk, _, _, ping = pcall(netStats)
    if netOk then latency = tonumber(ping) end
  end
  SetLabel(display.latencyValue, latency and tostring(math.floor(latency)) or "--",
           ThresholdColor(latency, 100, 200, false))
  UpdateOverlayWidth()
end

-- Local computer time. date() is the client's os.date global and formats the
-- OS clock for a pattern without a leading '!'.
local function RefreshTime()
  if not display or not ElementShown("time") then return end

  local dateFn = U.G("date")
  local ok, stamp = false, nil
  if type(dateFn) == "function" then ok, stamp = pcall(dateFn, TIME_FORMAT) end
  if not ok or type(stamp) ~= "string" then stamp = nil end

  SetLabel(display.timeValue, stamp or "--", M.color.text)
  UpdateOverlayWidth()
end

local function RefreshMoney()
  if not display or not ElementShown("money") then return end
  local getMoney = U.G("GetMoney")
  local ok, total = false, nil
  if type(getMoney) == "function" then ok, total = pcall(getMoney) end
  total = ok and tonumber(total) or 0

  SetCoinValue(display.gold, tostring(math.floor(total / 10000)), COLOR_GOLD)
  SetCoinValue(display.silver, tostring(math.floor(math.mod(total, 10000) / 100)), COLOR_SILVER)
  SetCoinValue(display.copper, tostring(math.mod(total, 100)), COLOR_COPPER)
  UpdateOverlayWidth()
end

local function BuildScanner()
  local tip = U.CreateScannerTooltip("UnrealUIStatusScanner")
  if not tip then
    U.Error("status: GameTooltipTemplate unavailable; durability cannot be read")
    return
  end

  scanner = tip

  local template = U.G("DURABILITY_TEMPLATE")
  if type(template) == "string" then
    durabilityPattern = string.gsub(template, "%%[^%s]+", "(.+)")
  end
end

local function ScanLowestDurability()
  if not scanner or not durabilityPattern then return nil end

  local lowest = 100
  local foundItem = false
  local setInventoryItem = scanner.SetInventoryItem
  if type(setInventoryItem) ~= "function" then return nil end

  local i
  for i = 1, table.getn(INVENTORY_SLOTS) do
    U.ArmScannerTooltip(scanner)

    local ok, hasItem = pcall(setInventoryItem, scanner, "player", INVENTORY_SLOTS[i])
    if ok and hasItem then
      foundItem = true
      local lineCountOk, lineCount = pcall(scanner.NumLines, scanner)
      lineCount = lineCountOk and tonumber(lineCount) or 0

      local line
      for line = 1, lineCount do
        local textRegion = U.G("UnrealUIStatusScannerTextLeft" .. line)
        local text
        if textRegion and textRegion.GetText then
          local textOk, value = pcall(textRegion.GetText, textRegion)
          if textOk then text = value end
        end

        if type(text) == "string" then
          local _, _, current, maximum = string.find(text, durabilityPattern)
          current, maximum = tonumber(current), tonumber(maximum)
          if current and maximum and maximum > 0 then
            local percent = math.floor(current / maximum * 100)
            if percent < lowest then lowest = percent end
            break
          end
        end
      end
    end
  end
  -- The loop has no early exit, so this one release covers every slot read.
  U.ReleaseScannerTooltip(scanner)

  if foundItem then return lowest end
  return nil
end

local function RefreshDurability()
  -- The tooltip scan is the strip's one costly read: skipped while hidden.
  if not display or not ElementShown("durability") then return end
  local percent = ScanLowestDurability()
  SetLabel(display.durabilityValue, percent and (tostring(percent) .. "%") or "--",
           ThresholdColor(percent, 70, 40, true))
  UpdateOverlayWidth()
end

function S:OnEnable()
  if anchor then return end
  Build()
  BuildScanner()
  BuildPopulation()

  U.RegisterEvent("WHO_LIST_UPDATE", OnWhoListUpdate)
  -- Interval-only: population must not also refresh on PLAYER_ENTERING_WORLD,
  -- which can fire repeatedly during zoning and would burst /who requests.
  U.RegisterUpdate("status.population.refresh", POP_REFRESH_INTERVAL, RefreshPopulation)

  U.RegisterEvent("PLAYER_MONEY", RefreshMoney)
  -- UPDATE_INVENTORY_ALERTS is the 1.12 event; the later one is kept too.
  U.RegisterEvent("UPDATE_INVENTORY_ALERTS", RefreshDurability)
  U.RegisterEvent("UPDATE_INVENTORY_DURABILITY", RefreshDurability)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", function(event, unit)
    if not unit or unit == "player" then RefreshDurability() end
  end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    RefreshPerformance()
    RefreshTime()
    RefreshMoney()
    RefreshDurability()
  end)

  -- Events above are accepted by this client but not all are observed in the
  -- compact evidence. Polling keeps the overlay useful even when one does not
  -- arrive; the comparatively expensive tooltip scan is limited to five seconds.
  U.RegisterUpdate("status.refresh", 1, function()
    if U.PerfDisabled and U.PerfDisabled("status") then return end
    RefreshPerformance()
    RefreshTime()
    RefreshMoney()
    durabilityAge = durabilityAge + 1
    if durabilityAge >= 5 then
      durabilityAge = 0
      RefreshDurability()
    end
  end)

  U.ApplyStatusOverlay()
  U.ApplyOnlineOverlay()
end

-- ---------------------------------------------------------------------------
-- Switches
--
-- Each overlay's on/off switch is the edit-mode drawer row for its anchor
-- (core/mover.lua, group `keepAnchor`), so the drawer, the contextual panel on
-- the anchor and the settings page all write one saved value through
-- U.SetMoverGroupEnabled. A switched-off overlay draws nothing but keeps its
-- anchor in edit mode, which is where it is switched back on.
-- ---------------------------------------------------------------------------
local views = { page = nil }

local function RefreshViews()
  if type(U.RefreshMoverPanel) == "function" then
    U.RefreshMoverPanel("status.overlay")
    U.RefreshMoverPanel("status.population")
  end
  if views.page then pcall(views.page) end
end

local function SetSwitch(groupKey, configKey, apply, value)
  value = value and true or false
  if type(U.SetMoverGroupEnabled) == "function" then
    local stored = U.SetMoverGroupEnabled(groupKey, value)
    if stored ~= nil then return stored end
  end
  Config()[configKey] = value
  apply()
  RefreshViews()
  return value
end

function U.ApplyStatusOverlay()
  if not display then return end
  display.layoutKey = nil
  RefreshPerformance()
  RefreshTime()
  RefreshMoney()
  RefreshDurability()
  UpdateOverlayWidth()
end

function U.ApplyOnlineOverlay()
  UpdatePopulationWidth()
end

function U.StatusOverlayEnabled() return Config().enabled and true or false end
function U.OnlineOverlayEnabled() return Config().onlineEnabled and true or false end

function U.SetStatusOverlayEnabled(value)
  return SetSwitch("status", "enabled", U.ApplyStatusOverlay, value)
end

function U.SetOnlineOverlayEnabled(value)
  return SetSwitch("online", "onlineEnabled", U.ApplyOnlineOverlay, value)
end

function U.StatusOverlayElementShown(name)
  local key = ELEMENT_KEYS[name]
  return key and Config()[key] and true or false
end

function U.SetStatusOverlayElement(name, value)
  local key = ELEMENT_KEYS[name]
  if not key then return nil end
  Config()[key] = value and true or false
  U.ApplyStatusOverlay()
  RefreshViews()
  return Config()[key]
end

-- ---------------------------------------------------------------------------
-- Edit-mode panels: one Enable box beside each selected anchor.
-- ---------------------------------------------------------------------------
local function MoverPanelSpec(name, get, set)
  return {
    name = name,
    width = 200 + U.MoverPanelPad() * 2,
    height = 44 + 22 + 12,
    build = function(frame, contentTop, contentWidth)
      local box = U.CreateCheckbox(frame, {
        name = name .. "Enable",
        text = U.L("COMMON_ENABLE"),
        textWidth = contentWidth,
        value = get(),
        onChange = function(value) set(value) end,
      })
      box.SetPoint("TOPLEFT", frame, "TOPLEFT", U.MoverPanelPad(), contentTop)
      return { box }, function() box.SetValue(get()) end
    end,
  }
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------
local PAGE_ROWS = {
  { element = "fps", text = "STATUS_SHOW_FPS" },
  { element = "latency", text = "STATUS_SHOW_LATENCY" },
  { element = "durability", text = "STATUS_SHOW_DURABILITY" },
  { element = "time", text = "STATUS_SHOW_TIME" },
  { element = "money", text = "STATUS_SHOW_MONEY" },
}

local function BuildSettingsPage(parent)
  local widgets = {}
  local pageWidth = U.SETTINGS_PAGE_WIDTH
  local rows = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("MOVER_LABEL_STATUS"), width = pageWidth, y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUIStatusOverlayEnable",
    text = U.L("STATUS_ENABLE"),
    value = U.StatusOverlayEnabled(),
    onChange = function(value) U.SetStatusOverlayEnabled(value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local i
  for i = 1, table.getn(PAGE_ROWS) do
    local element = PAGE_ROWS[i].element
    local row = U.CreateCheckbox(parent, {
      name = "UnrealUIStatusOverlayShow" .. element,
      text = U.L(PAGE_ROWS[i].text),
      value = U.StatusOverlayElementShown(element),
      onChange = function(value) U.SetStatusOverlayElement(element, value) end,
    })
    row.SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -34 - i * 22)
    table.insert(rows, { control = row, element = element })
    table.insert(widgets, row)
  end

  local onlineY = -34 - (table.getn(PAGE_ROWS) + 1) * 22 - 16
  local onlineHeader = U.CreateSectionHeader(parent, {
    text = U.L("MOVER_LABEL_ONLINE_COUNT"), width = pageWidth, y = onlineY,
  })
  table.insert(widgets, onlineHeader)

  local online = U.CreateCheckbox(parent, {
    name = "UnrealUIOnlineOverlayEnable",
    text = U.L("STATUS_ONLINE_ENABLE"),
    value = U.OnlineOverlayEnabled(),
    onChange = function(value) U.SetOnlineOverlayEnabled(value) end,
  })
  online.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, onlineY - 30)
  table.insert(widgets, online)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = pageWidth,
  })
  if hint then
    U.AnchorSettingsDescription(hint, online.box)
    hint:SetText(U.L("STATUS_PAGE_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    local enabled = U.StatusOverlayEnabled()
    enable.SetValue(enabled)
    local n
    for n = 1, table.getn(rows) do
      rows[n].control.SetValue(U.StatusOverlayElementShown(rows[n].element))
      rows[n].control.SetEnabled(enabled)
    end
    online.SetValue(U.OnlineOverlayEnabled())
  end
  views.page = Refresh
  Refresh()

  return widgets, Refresh
end

function S:OnInit()
  Config()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("status-overlay", U.L("STATUS_PAGE"),
                          BuildSettingsPage, { after = "general" })
  end
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel("status.overlay", MoverPanelSpec(
      "UnrealUIStatusMoverSettings", U.StatusOverlayEnabled,
      U.SetStatusOverlayEnabled))
    U.RegisterMoverPanel("status.population", MoverPanelSpec(
      "UnrealUIOnlineMoverSettings", U.OnlineOverlayEnabled,
      U.SetOnlineOverlayEnabled))
  end
  if type(U.OnMoverGroupChanged) == "function" then
    U.OnMoverGroupChanged("status", RefreshViews)
    U.OnMoverGroupChanged("online", RefreshViews)
  end
end
