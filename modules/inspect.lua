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

-- Inspect is intentionally gear-only. The client documents remote honor APIs,
-- but this interface does not expose Character/Honor navigation by design.
local function HideTabs()
  local i
  for i = 1, TAB_COUNT do
    local tab = G("InspectFrameTab" .. i)
    if tab then pcall(tab.Hide, tab) end
  end
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
  HideTabs()
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

  HideTabs()
  StyleSlots(keepNativeChrome)
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
