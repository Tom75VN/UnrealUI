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

local POP_WIDTH = 120
-- One /who request per interval, so the addon never sends more than one
-- SendWho call per POP_REFRESH_INTERVAL.
local POP_REFRESH_INTERVAL = 60

local COLOR_GOOD = { 0.33, 0.93, 0.33, 1.00 }
local COLOR_WARN = { 0.96, 0.68, 0.04, 1.00 }
local COLOR_BAD  = { 1.00, 0.28, 0.20, 1.00 }
local COLOR_GOLD = { 1.00, 0.82, 0.00, 1.00 }
local COLOR_SILVER = { 0.75, 0.75, 0.75, 1.00 }
local COLOR_COPPER = { 0.80, 0.47, 0.29, 1.00 }
local MONEY_TEXTURE = "Interface\\MoneyFrame\\UI-MoneyIcons"
local COIN_GOLD = { 0.00, 0.25, 0, 1 }
local COIN_SILVER = { 0.25, 0.50, 0, 1 }
local COIN_COPPER = { 0.50, 0.75, 0, 1 }

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

local function BuildCoin(parent, texCoords, color, width)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetWidth(width or 40)
  holder:SetHeight(14)

  holder.icon = holder:CreateTexture(nil, "ARTWORK")
  holder.icon:SetWidth(12)
  holder.icon:SetHeight(12)
  -- The coin artwork sits low inside the atlas slice. Raise only the texture
  -- while keeping the number on the common text baseline.
  holder.icon:SetPoint("RIGHT", holder, "RIGHT", 0, 2)
  pcall(holder.icon.SetTexture, holder.icon, MONEY_TEXTURE)
  pcall(holder.icon.SetTexCoord, holder.icon,
        texCoords[1], texCoords[2], texCoords[3], texCoords[4])

  holder.label = U.CreateLabel(holder, {
    size = M.fontSize.small,
    color = color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then holder.label:SetPoint("RIGHT", holder.icon, "LEFT", -1, -2) end
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

local function UpdateOverlayWidth()
  if not anchor or not display then return end

  local width = HORIZONTAL_PADDING
  width = width + LabelWidth(display.fpsCaption) + 2 + LabelWidth(display.fpsValue)
  width = width + MODULE_GAP + LabelWidth(display.latencyCaption) + 2 + LabelWidth(display.latencyValue)
  width = width + MODULE_GAP + LabelWidth(display.durabilityCaption) + 2 + LabelWidth(display.durabilityValue)
  width = width + MODULE_GAP
  width = width + (display.gold.contentWidth or 26) + COIN_GAP
  width = width + (display.silver.contentWidth or 26) + COIN_GAP
  width = width + (display.copper.contentWidth or 26) + HORIZONTAL_PADDING
  anchor:SetWidth(width)
end

local function Build()
  anchor = CreateFrame("Frame", "UnrealUIStatusAnchor", UIParent)
  anchor:SetWidth(WIDTH)
  anchor:SetHeight(HEIGHT)
  U.CreateBackdrop(anchor, {
    background = { 0.035, 0.035, 0.035, 0.20 },
    border = false,
  })

  display = {}
  display.fpsCaption = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.fpsCaption:SetPoint("LEFT", anchor, "LEFT", HORIZONTAL_PADDING, 0)
  display.fpsCaption:SetText(U.L("STATUS_FPS"))

  display.fpsValue = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.fpsValue:SetPoint("LEFT", display.fpsCaption, "RIGHT", 2, 0)

  display.latencyCaption = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.latencyCaption:SetPoint("LEFT", display.fpsValue, "RIGHT", MODULE_GAP, 0)
  display.latencyCaption:SetText(U.L("STATUS_LATENCY"))

  display.latencyValue = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.latencyValue:SetPoint("LEFT", display.latencyCaption, "RIGHT", 2, 0)

  display.durabilityCaption = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  display.durabilityCaption:SetPoint("LEFT", display.latencyValue, "RIGHT", MODULE_GAP, 0)
  display.durabilityCaption:SetText(U.L("STATUS_DURABILITY"))

  display.durabilityValue = U.CreateLabel(anchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = COLOR_GOOD,
  })
  display.durabilityValue:SetPoint("LEFT", display.durabilityCaption, "RIGHT", 2, 0)

  -- Chain the denominations directly after durability. Their widths follow
  -- the rendered values, so short values do not leave empty columns.
  display.gold = BuildCoin(anchor, COIN_GOLD, COLOR_GOLD, 26)
  display.silver = BuildCoin(anchor, COIN_SILVER, COLOR_SILVER, 26)
  display.copper = BuildCoin(anchor, COIN_COPPER, COLOR_COPPER, 26)
  display.gold:SetPoint("LEFT", display.durabilityValue, "RIGHT", MODULE_GAP, 0)
  display.silver:SetPoint("LEFT", display.gold, "RIGHT", COIN_GAP, 0)
  display.copper:SetPoint("LEFT", display.silver, "RIGHT", COIN_GAP, 0)

  U.RegisterMover("status.overlay", anchor, {
    label = U.L("MOVER_LABEL_STATUS"),
    default = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 20, y = 20 },
  })
end

local function UpdatePopulationWidth()
  if not popAnchor or not popDisplay then return end

  local width = HORIZONTAL_PADDING
  width = width + LabelWidth(popDisplay.serverValue)
  width = width + 2 + LabelWidth(popDisplay.serverSuffix)
  width = width + HORIZONTAL_PADDING
  popAnchor:SetWidth(width)
end

local function BuildPopulation()
  popAnchor = CreateFrame("Frame", "UnrealUIPopulationAnchor", UIParent)
  popAnchor:SetWidth(POP_WIDTH)
  popAnchor:SetHeight(HEIGHT)
  U.CreateBackdrop(popAnchor, {
    background = { 0.035, 0.035, 0.035, 0.20 },
    border = false,
  })

  popDisplay = {}
  popDisplay.serverValue = U.CreateLabel(popAnchor, {
    size = M.fontSize.normal, inherits = "GameFontNormal", color = M.color.text,
  })
  popDisplay.serverValue:SetPoint("LEFT", popAnchor, "LEFT", HORIZONTAL_PADDING, 0)
  popDisplay.serverValue:SetText("--")

  popDisplay.serverSuffix = U.CreateLabel(popAnchor, {
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
  if popPending then return end -- previous request never resolved; skip this tick
  RequestWho()
end

local function RefreshPerformance()
  if not display then return end

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

local function RefreshMoney()
  if not display then return end
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
  local world = U.G("WorldFrame") or UIParent
  local ok, tip = pcall(CreateFrame, "GameTooltip", "UnrealUIStatusScanner", nil,
                        "GameTooltipTemplate")
  if not ok or not tip then
    U.Error("status: GameTooltipTemplate unavailable; durability cannot be read")
    return
  end

  scanner = tip
  pcall(scanner.SetOwner, scanner, world, "ANCHOR_NONE")

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
    pcall(scanner.ClearLines, scanner)
    pcall(scanner.SetOwner, scanner, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")

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

  if foundItem then return lowest end
  return nil
end

local function RefreshDurability()
  if not display then return end
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
  U.RegisterEvent("UPDATE_INVENTORY_DURABILITY", RefreshDurability)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", function(event, unit)
    if not unit or unit == "player" then RefreshDurability() end
  end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    RefreshPerformance()
    RefreshMoney()
    RefreshDurability()
  end)

  -- Events above are accepted by this client but not all are observed in the
  -- compact evidence. Polling keeps the overlay useful even when one does not
  -- arrive; the comparatively expensive tooltip scan is limited to five seconds.
  U.RegisterUpdate("status.refresh", 1, function()
    if U.PerfDisabled and U.PerfDisabled("status") then return end
    RefreshPerformance()
    RefreshMoney()
    durabilityAge = durabilityAge + 1
    if durabilityAge >= 5 then
      durabilityAge = 0
      RefreshDurability()
    end
  end)

  RefreshPerformance()
  RefreshMoney()
  RefreshDurability()
end
