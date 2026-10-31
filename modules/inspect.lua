-- unrealUI :: modules/inspect.lua
--
-- Character's theme-specific design applied to the native Inspect window.
-- The client retains ownership of inspect data, model, tabs and item buttons;
-- UnrealUI replaces only presentation and layers semantic quality borders.

local U = UnrealUI
local M = U.media
local INS = U.RegisterModule("inspect")

local SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
  "ShirtSlot", "TabardSlot", "WristSlot",
  "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
  "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
  "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

local TAB_COUNT = 3
local PANEL_INSET_LEFT = 10
local PANEL_INSET_RIGHT = 30

local GOLD = M.color.textAccent
local WHITE = M.color.text
local DIM = M.color.textDim

local frame, panel, built, keepNativeChrome, modernWowMode
local browser = { previous = nil, next = nil, lastRequest = 0 }

local function G(name)
  return U.G(name)
end

local function SetTextFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function RefreshClassLine()
  local text = G("InspectLevelText")
  local unit = frame and frame.unit
  local unitClass = G("UnitClass")
  local unitLevel = G("UnitLevel")
  if not text or not unit or type(unitClass) ~= "function" or
     type(unitLevel) ~= "function" then return end

  local classOk, className, classToken = pcall(unitClass, unit)
  local levelOk, level = pcall(unitLevel, unit)
  if not classOk or type(className) ~= "string" or
     not levelOk or not tonumber(level) then return end

  local r, g, b = M.ClassColor(classToken)
  if r then
    className = string.format("|cff%02x%02x%02x%s|r",
      math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
      math.floor(b * 255 + 0.5), className)
  end
  pcall(text.SetText, text,
        U.L("CHARACTER_CLASS_LEVEL", className, tonumber(level)))
end

-- GetInventoryItemQuality is documented for arbitrary unit ids but has not
-- been runtime-verified on this client. UnrealPfUI's working Inspect skin uses
-- GetInventoryItemLink + GetItemInfo instead, so that sequence is the guarded
-- fallback when the direct quality call returns nothing.
local function SlotQuality(unit, inventorySlot)
  local getQuality = G("GetInventoryItemQuality")
  if type(getQuality) == "function" then
    local ok, quality = pcall(getQuality, unit, inventorySlot)
    if ok and tonumber(quality) then return tonumber(quality) end
  end

  local getLink = G("GetInventoryItemLink")
  if type(getLink) ~= "function" then return nil end

  local ok, link = pcall(getLink, unit, inventorySlot)
  if not ok or not link then return nil end

  local infoOk, _, _, quality = pcall(GetItemInfo, link)
  return infoOk and tonumber(quality) or nil
end

local function StyleSlot(slotName, nativeChrome)
  local slot = G("Inspect" .. slotName)
  if not slot then return end

  -- Persistent because the Modern WoW quality glow reads the same table after
  -- this refresh. Mutating it also lets hover restore the latest rarity colour
  -- when U.StyleStockButton styled the slot on its first pass.
  local border = slot.uuiInspectBorder
  if not border then
    border = { M.Unpack(M.slotBorder.empty) }
    slot.uuiInspectBorder = border
  end

  local color = M.slotBorder.empty
  local unit = frame and frame.unit
  local idOk, inventorySlot = false, nil
  if unit and slot.GetID then
    idOk, inventorySlot = pcall(slot.GetID, slot)
  end

  local quality = idOk and SlotQuality(unit, inventorySlot) or nil
  if quality then
    if quality > M.qualityLimit then
      -- Match Character: enhanced blue is scoped to Classic and Modern WoW;
      -- the flat Modern theme retains the client's normal rarity colour.
      local themedColor = nativeChrome or modernWowMode
      color = (themedColor and U.ItemQualityBorderColor(quality) or
               U.ItemQualityColor(quality)) or M.slotBorder.plain
    else
      color = M.slotBorder.plain
    end
  elseif slot.hasItem then
    -- The native update can mark the slot occupied before item info is cached.
    color = M.slotBorder.plain
  end

  border[1], border[2], border[3], border[4] = M.Unpack(color)

  if nativeChrome then
    U.SetGearQualityGlow(slot, border)
  else
    U.StyleStockButton(slot, {
      icon = G("Inspect" .. slotName .. "IconTexture"),
      border = border,
    })
  end
  U.SetBorderColor(slot, M.Unpack(border))
end

local function StyleSlots(nativeChrome)
  local i
  for i = 1, table.getn(SLOTS) do StyleSlot(SLOTS[i], nativeChrome) end
end

-- Keep the client's own Inspect pages (Character, Honor) and their native
-- switching logic. UnrealUI only replaces the tab chrome on its owned drawing
-- paths and strips the Honor page's stock art the way Character strips
-- HonorFrame. Page and tab names have no compact-evidence record
-- (query_compat.py: no match for InspectFrameTab/InspectHonorFrame); every
-- read is G()-guarded, so a missing name leaves that piece native.
local function StyleTabs()
  local tabs = {}
  local i
  for i = 1, TAB_COUNT do
    local tab = G("InspectFrameTab" .. i)
    if tab then
      pcall(tab.Show, tab)
      table.insert(tabs, tab)
    end
  end
  if keepNativeChrome or frame.uuiInspectTabsStyled then return end
  frame.uuiInspectTabsStyled = true
  if modernWowMode and type(U.ModernWowDressTab) == "function" then
    for i = 1, table.getn(tabs) do U.ModernWowDressTab(tabs[i]) end
  else
    U.StyleStockTabGroup(tabs, 1)
  end
end

local function StripHonorPage()
  if keepNativeChrome then return end
  local honor = G("InspectHonorFrame")
  if honor then U.StripStockTextures(honor) end
end

-- Previous/next party member. CanInspect is documented to print an error for
-- a unit it rejects, so the candidate list never calls it: it keeps live,
-- connected players inside the shared interact-range approximation
-- (U.MeleeInteractRange), and only the unit a click picks is asked.
-- InspectFrame_Show has no compact-evidence record; it is type-checked and
-- pcall-guarded, and a missing function leaves both arrows doing nothing.
function browser.Units()
  local units = {}
  local exists, isPlayer, same = G("UnitExists"), G("UnitIsPlayer"), G("UnitIsUnit")
  if type(exists) ~= "function" or type(isPlayer) ~= "function" then
    return units
  end
  local connected = G("UnitIsConnected")
  local candidates = { "target", "party1", "party2", "party3", "party4" }
  local i, j
  for i = 1, table.getn(candidates) do
    local unit = candidates[i]
    local existsOk, live = pcall(exists, unit)
    local playerOk, player = pcall(isPlayer, unit)
    local online = true
    if type(connected) == "function" then
      local ok, value = pcall(connected, unit)
      online = ok and value and true or false
    end
    local keep = existsOk and live and playerOk and player and online and
                 U.MeleeInteractRange(unit) ~= false
    -- The target is often also a party member; list that player once.
    if keep and type(same) == "function" then
      for j = 1, table.getn(units) do
        local ok, value = pcall(same, unit, units[j])
        if ok and value then keep = false; break end
      end
    end
    if keep then table.insert(units, unit) end
  end
  return units
end

function browser.Refresh()
  if not browser.previous or not browser.next then return end
  local enabled = type(G("InspectFrame_Show")) == "function" and
                  table.getn(browser.Units()) > 1
  browser.previous.SetEnabled(enabled)
  browser.next.SetEnabled(enabled)
end

function browser.Step(direction)
  local show = G("InspectFrame_Show")
  if type(show) ~= "function" then return end
  local now = GetTime()
  if now - browser.lastRequest < 0.5 then return end

  local units = browser.Units()
  local count = table.getn(units)
  if count < 2 then
    browser.Refresh()
    return
  end
  local current, same = frame and frame.unit, G("UnitIsUnit")
  local index, i
  if current and type(same) == "function" then
    for i = 1, count do
      local ok, value = pcall(same, current, units[i])
      if ok and value then index = i; break end
    end
  end
  index = index or (direction < 0 and 1 or count)
  index = index + (direction < 0 and -1 or 1)
  if index < 1 then index = count end
  if index > count then index = 1 end
  browser.lastRequest = now

  local canInspect = G("CanInspect")
  if type(canInspect) == "function" then
    local ok, allowed = pcall(canInspect, units[index])
    if not ok or not allowed then return end
  end
  pcall(show, units[index])
  browser.Refresh()
end

-- The shared arrow toggle (core/widgets.lua): owned glyph, real hover, press
-- and disabled states, and no backdrop, so it reads the same on the flat panel
-- and on the Modern WoW housing.
function browser.Build()
  if keepNativeChrome or browser.previous then return end
  local parent = panel or frame
  browser.previous = U.CreateArrowToggle(parent, {
    name = "UnrealUIInspectPrevious",
    width = 18,
    height = 18,
    direction = "left",
    onClick = function() browser.Step(-1) end,
  })
  browser.next = U.CreateArrowToggle(parent, {
    name = "UnrealUIInspectNext",
    width = 18,
    height = 18,
    direction = "right",
    onClick = function() browser.Step(1) end,
  })
  browser.previous:SetPoint("TOP", parent, "TOP", -72, -8)
  browser.next:SetPoint("TOP", parent, "TOP", 72, -8)
  browser.Refresh()
end

local function StyleModel()
  U.EnableStockModelDrag(G("InspectModelFrame"), {
    name = "UnrealUIInspectModelRotateCatcher",
    ticker = "inspect.model-rotate",
    leftButton = G("InspectModelRotateLeftButton"),
    rightButton = G("InspectModelRotateRightButton"),
  })
end

local function InspectDragControls()
  local controls = {}
  local close = G("InspectFrameCloseButton")
  if close then table.insert(controls, close) end

  local i
  for i = 1, table.getn(SLOTS) do
    local slot = G("Inspect" .. SLOTS[i])
    if slot then table.insert(controls, slot) end
  end
  if browser.previous then table.insert(controls, browser.previous) end
  if browser.next then table.insert(controls, browser.next) end
  return controls
end

local function Reapply()
  if not frame then return end
  if not keepNativeChrome then
    U.StripStockTextures(frame)
    U.StripStockTextures(G("InspectPaperDollFrame"))
    if panel then pcall(panel.Show, panel) end
    SetTextFont(G("InspectNameText"), M.fontSize.large, GOLD)
    SetTextFont(G("InspectLevelText"), M.fontSize.small, WHITE)
    SetTextFont(G("InspectGuildText"), M.fontSize.small, DIM)
  end
  StyleTabs()
  StripHonorPage()
  browser.Refresh()
  RefreshClassLine()
  StyleSlots(keepNativeChrome)
end

local function BuildFrame()
  if built then return true end

  frame = G("InspectFrame")
  local update = G("InspectPaperDollItemSlotButton_Update")
  if not frame or type(update) ~= "function" or not G("InspectHeadSlot") then
    return false
  end

  keepNativeChrome = U.ThemeStyleUsesNativeChrome() and not modernWowMode

  if not keepNativeChrome then
    U.StripStockTextures(frame)
    panel = U.CreatePanel(frame, {
      name = "UnrealUIInspectPanel",
      width = 100,
      height = 100,
      background = { 0.01, 0.01, 0.01, 0.78 },
    })
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_INSET_LEFT, -10)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANEL_INSET_RIGHT, 72)
    pcall(panel.EnableMouse, panel, false)
    pcall(frame.SetHitRectInsets, frame, 10, 30, 10, 72)

    local levelOk, level = pcall(frame.GetFrameLevel, frame)
    if levelOk and tonumber(level) then pcall(panel.SetFrameLevel, panel, level) end

    local name = G("InspectNameText")
    if name then
      pcall(function()
        name:ClearAllPoints()
        name:SetPoint("TOP", panel, "TOP", 0, -10)
      end)
    end
    local levelText = G("InspectLevelText")
    local guildText = G("InspectGuildText")
    if levelText and guildText then
      pcall(function()
        guildText:ClearAllPoints()
        guildText:SetPoint("TOP", levelText, "BOTTOM", 0, -1)
      end)
    end

    U.StyleStockCloseButton(G("InspectFrameCloseButton"), panel, -6, -6)
    StyleModel()
    U.StripStockTextures(G("InspectPaperDollFrame"))
  end

  StyleTabs()
  StripHonorPage()
  StyleSlots(keepNativeChrome)
  browser.Build()
  U.MakeWindowDraggable("inspect", frame, {
    headerHeight = keepNativeChrome and 40 or 76,
    headerInset = keepNativeChrome and 40 or 54,
    headerLevelOffset = 100,
    interactiveFrames = InspectDragControls(),
  })

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then pcall(panel.Hide, panel) end
  end)

  -- WORKING_SOURCE: UnrealPfUI hooks this fixed-argument updater and receives
  -- the refreshed slot button. Refresh the matching named slot so the shared
  -- border table is ready before Modern WoW repaints its quality glow.
  U.PostHookGlobal("InspectPaperDollItemSlotButton_Update", function(button)
    if not button or not button.GetName then return end
    local ok, name = pcall(button.GetName, button)
    if not ok or type(name) ~= "string" then return end
    local prefix = "Inspect"
    if string.sub(name, 1, string.len(prefix)) ~= prefix then return end
    StyleSlot(string.sub(name, string.len(prefix) + 1), keepNativeChrome)
    U.DeferOnce("inspect.class-line", RefreshClassLine)
    if modernWowMode and type(U.ModernWowDressInspect) == "function" then
      U.DeferOnce("inspect.modernwow-unit", U.ModernWowDressInspect)
    end
  end)

  built = true
  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then
    Reapply()
  elseif panel then
    pcall(panel.Hide, panel)
  end
  if modernWowMode and type(U.ModernWowDressInspect) == "function" then
    U.ModernWowDressInspect()
  end
  return true
end

local function TryBuild()
  if BuildFrame() then U.UnregisterEvent("ADDON_LOADED", TryBuild) end
end

function INS:OnEnable()
  modernWowMode = type(U.ModernWowSurfaceEnabled) == "function" and
                  U.ModernWowSurfaceEnabled("character")
  if BuildFrame() then return end

  -- Blizzard_InspectUI may create the window after unrealUI's module phase.
  U.RegisterEvent("ADDON_LOADED", TryBuild)
end
