-- unrealUI :: core/itemslot.lua
--
-- The shared container item-slot component: one styled button that draws a
-- (bag, slot) pair, used by modules/bags.lua and modules/bank.lua. The bag
-- frame owned this code first; it moved here the moment a second window needed
-- the same slot, per .claude/rules/unreal-ui-design.md ("add the smallest
-- central reusable component first").
--
-- knowledge.json / bags.container_api_contract_unverified is INCONCLUSIVE:
-- GetContainerNumSlots, GetContainerItemInfo, GetContainerItemLink,
-- ContainerFrameItemButtonTemplate, SetItemButton*, ContainerFrame_UpdateCooldown
-- and GetItemInfo have no compact behavior record on this client. Per the
-- UnrealPfUI evidence-gap fallback every one of them defaults to what
-- UnrealPfUI/modules/bags.lua demonstrably does on this same client --
-- WORKING_SOURCE only, never runtime verified. Every call stays inside pcall
-- and every result is treated as optional.

local U = UnrealUI
local M = U.media

-- ---------------------------------------------------------------------------
-- Quality colour
-- ---------------------------------------------------------------------------
function U.ItemQualityColor(quality)
  quality = tonumber(quality)
  if not quality then return nil end

  local stock = U.G("ITEM_QUALITY_COLORS")
  if type(stock) == "table" and type(stock[quality]) == "table" then
    local c = stock[quality]
    if tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then
      return { c.r, c.g, c.b }
    end
  end

  return M.quality[quality]
end

-- No compact runtime record establishes GetItemInfo's full Vanilla tuple shape
-- on this client; this mirrors UnrealPfUI's working itemType == "Quest" check
-- (UnrealPfUI/modules/bags.lua:460) as WORKING_SOURCE evidence only.
local function IsQuestItem(bag, slot)
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if not ok or not link then return false end

  local infoOk, _, _, _, _, _, _, itemType = pcall(GetItemInfo, link)
  return infoOk and itemType == "Quest"
end

-- The border rule that removes the white outline: only quality above the limit
-- earns its colour, everything else gets a dim neutral edge.
function U.ItemSlotBorderColor(bag, slot, texture, quality)
  if not texture then return M.slotBorder.empty end
  if IsQuestItem(bag, slot) then return M.slotBorder.quest end
  if tonumber(quality) and quality > M.qualityLimit then
    return U.ItemQualityColor(quality) or M.slotBorder.plain
  end
  return M.slotBorder.plain
end

-- ---------------------------------------------------------------------------
-- Styling
--
-- The stock art is stripped the way pfUI strips it: the button's own
-- NormalTexture is the white slot ring, so it is cleared through the named
-- region as well as the setter (rendering.native_texture_strip_requires_alpha
-- says a native region can survive Hide() and SetTexture alone).
-- ---------------------------------------------------------------------------
-- The count region this component drives.
--
-- The player-bag template's stock Count region draws correctly, so retain it.
-- The bank template's region does not produce a visible count on this client
-- (confirmed visually in-game). Bank counts are therefore placed on a raised
-- child frame, using the same proven text-layer pattern as action-bar cooldown
-- text and unit-frame labels. Keeping the bank button template itself preserves
-- its native click, drag and tooltip logic.
local function EnsureSlotCount(button, name, restyle, raised)
  local region = U.G(name .. "Count")

  if raised then
    U.HideRegion(region)

    local layer = CreateFrame("Frame", nil, button)
    pcall(layer.SetAllPoints, layer, button)
    pcall(layer.EnableMouse, layer, false)
    local levelOk, level = pcall(button.GetFrameLevel, button)
    if levelOk and tonumber(level) then
      pcall(layer.SetFrameLevel, layer, level + 10)
    end

    button.uuiCountLayer = layer
    button.uuiCount = U.CreateLabel(layer, {
      size = M.fontSize.small,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
    })
    if button.uuiCount then
      pcall(function()
        button.uuiCount:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -3, 3)
      end)
    end
  elseif region then
    button.uuiCount = region
    if restyle then
      -- A previous style pass may have taken the region out of the render.
      pcall(region.SetAlpha, region, 1)
      U.SetFont(region, M.fontSize.small)
      pcall(region.SetTextColor, region, M.Unpack(M.color.text))
      -- fonts.stretched_justification_ignored: the stock region is stretched
      -- across the button and justified into its corner, which is the pattern
      -- that record says can be ignored here. Anchor it to the one corner.
      pcall(function()
        region:ClearAllPoints()
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
      end)
      pcall(region.SetJustifyH, region, "RIGHT")
    end
  else
    button.uuiCount = U.CreateLabel(button, {
      size = M.fontSize.small,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
    })
    if button.uuiCount then
      pcall(function()
        button.uuiCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
      end)
    end
  end

  if button.uuiCount then pcall(button.uuiCount.Hide, button.uuiCount) end
end

function U.StyleItemSlot(button, name, raisedCount)
  if not button then return end
  local edge = U.BorderSize()

  local classic = type(U.ThemeStyleUsesNativeChrome) == "function" and
                  U.ThemeStyleUsesNativeChrome()
  button.uuiClassicItemSlot = classic and true or false

  if classic then
    -- The button was created from the client's real container/bag-slot
    -- template. Its NormalTexture keeps the stock button's original 32px
    -- geometry, which becomes a second small square inside UnrealUI's larger
    -- unified slot. Remove only that redundant layer; highlight, pushed, icon,
    -- count, click/drag and tooltip behavior remain owned by the template.
    pcall(button.SetNormalTexture, button, "")
    U.HideRegion(U.G(name .. "NormalTexture"))
    -- The Classic slot face is painted at BACKGROUND (CLASSIC_FACE_LAYER in
    -- modules/actionbar.lua) because this client's face art is not clear
    -- through the middle and dims an icon it covers. Pin the item icon to
    -- BORDER rather than trusting the container template to declare it there:
    -- BORDER is above the face and still below the template's ARTWORK count,
    -- so the stack number stays readable. Vanilla's own ItemButtonTemplate
    -- already uses BORDER, so this is a no-op wherever that holds here.
    local slotIcon = U.G(name .. "IconTexture")
    if slotIcon then pcall(slotIcon.SetDrawLayer, slotIcon, "BORDER") end
    -- Classic keeps the template's own count exactly where the client puts
    -- it; only its value is driven, from U.UpdateItemSlot.
    EnsureSlotCount(button, name, false, raisedCount)
    U.CreateBackdrop(button, {
      background = { 0, 0, 0, 0 },
      border = M.slotBorder.plain,
    })
    return
  end

  pcall(button.SetNormalTexture, button, "")
  U.HideRegion(U.G(name .. "NormalTexture"))

  U.CreateBackdrop(button, {
    background = { 0.10, 0.10, 0.10, 0.60 },
    border = M.color.border,
  })

  local icon = U.G(name .. "IconTexture")
  if icon then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    pcall(function()
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
      icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)
    end)
  end

  EnsureSlotCount(button, name, true, raisedCount)

  local hlOk, highlight = pcall(button.GetHighlightTexture, button)
  if hlOk and highlight then
    pcall(highlight.SetTexture, highlight, 0.5, 0.5, 0.5, 0.4)
  end

  local pushOk, pushed = pcall(button.GetPushedTexture, button)
  if pushOk and pushed then
    pcall(pushed.SetTexture, pushed, 0.5, 0.5, 0.5, 0.4)
  end
end

-- ---------------------------------------------------------------------------
-- Creation
--
-- WORKING_SOURCE recipe from UnrealPfUI/modules/bags.lua: the parent frame
-- carries SetID(bag), the button is a stock item-button template with
-- SetID(slot), and the template's own OnClick/OnDrag/OnEnter scripts are left
-- untouched -- click, pickup and tooltip are whatever those do with the
-- (parent bag, own slot) identity. Bank container -1 uses the bank template,
-- which is the same distinction pfUI makes (its bags.lua:379).
-- ---------------------------------------------------------------------------
function U.ItemSlotTemplate(bag)
  if tonumber(bag) == -1 then return "BankItemButtonGenericTemplate" end
  return "ContainerFrameItemButtonTemplate"
end

-- Whether the bank template was found missing once already, so the fallback is
-- reported to the player one time instead of once per slot.
local bankTemplateReported = false

-- GetItemInfo's documented eighth result is its INVTYPE_* token. Each token
-- maps to its documented paper-doll slot name, which GetInventorySlotInfo
-- resolves for this client. Rings and trinkets intentionally return both
-- candidates so the two native shopping tooltips can show both worn items.
local COMPARE_SLOTS = {
  INVTYPE_HEAD = { "HeadSlot" },
  INVTYPE_NECK = { "NeckSlot" },
  INVTYPE_SHOULDER = { "ShoulderSlot" },
  INVTYPE_BODY = { "ShirtSlot" },
  INVTYPE_CHEST = { "ChestSlot" },
  INVTYPE_ROBE = { "ChestSlot" },
  INVTYPE_WAIST = { "WaistSlot" },
  INVTYPE_LEGS = { "LegsSlot" },
  INVTYPE_FEET = { "FeetSlot" },
  INVTYPE_WRIST = { "WristSlot" },
  INVTYPE_HAND = { "HandsSlot" },
  INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
  INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
  INVTYPE_CLOAK = { "BackSlot" },
  INVTYPE_WEAPON = { "MainHandSlot" },
  INVTYPE_2HWEAPON = { "MainHandSlot" },
  INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
  INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
  INVTYPE_SHIELD = { "SecondaryHandSlot" },
  INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
  INVTYPE_RANGED = { "RangedSlot" },
  INVTYPE_RANGEDRIGHT = { "RangedSlot" },
  INVTYPE_THROWN = { "RangedSlot" },
  INVTYPE_RELIC = { "RangedSlot" },
  INVTYPE_TABARD = { "TabardSlot" },
  INVTYPE_AMMO = { "AmmoSlot" },
}

local COMPARE_TEXT_SIDES = { "Left", "Right" }

-- SetInventoryItem builds the equipped item's normal tooltip and therefore
-- does not prepend the semantic header used by SetMerchantCompareItem. Shift
-- its populated lines down once and add the same localized stock heading.
-- This is the narrow AddHeader pattern used by UnrealPfUI's working compare
-- module on this client (WORKING_SOURCE, modules/eqcompare.lua).
local function AddItemCompareHeader(tooltip, name)
  if not tooltip or type(name) ~= "string" then return end

  local header = U.G("CURRENTLY_EQUIPPED")
  if type(header) ~= "string" or header == "" then
    header = "Currently Equipped"
  end

  local first = U.G(name .. "TextLeft1")
  if not first then return end
  if first:GetText() == header then return end

  local lineCount = tooltip:NumLines()
  local lineIndex, sideIndex
  for lineIndex = lineCount, 1, -1 do
    for sideIndex = 1, table.getn(COMPARE_TEXT_SIDES) do
      local side = COMPARE_TEXT_SIDES[sideIndex]
      local current = U.G(name .. "Text" .. side .. lineIndex)
      local below = U.G(name .. "Text" .. side .. (lineIndex + 1))
      if current and below and current:IsShown() then
        local text = current:GetText()
        if type(text) == "string" and text ~= "" then
          local r, g, b = current:GetTextColor()
          if tooltip:NumLines() < lineIndex + 1 then
            tooltip:AddLine(text, r, g, b, true)
          else
            below:SetText(text)
            below:SetTextColor(r, g, b)
            below:Show()
            current:Hide()
          end
        end
      end
    end
  end

  first:SetText(header)
  first:SetTextColor(M.Unpack(M.color.textDim))
  first:Show()
  tooltip:Show()
end

local function HideItemCompare()
  local i
  for i = 1, 2 do
    local tooltip = U.G("ShoppingTooltip" .. i)
    if tooltip then pcall(tooltip.Hide, tooltip) end
  end
end

local function ShowItemCompare(bag, slot)
  HideItemCompare()

  local linkOk, link = pcall(GetContainerItemLink, bag, slot)
  if not linkOk or type(link) ~= "string" then return end

  local infoOk, _, _, _, _, _, _, _, equipLoc = pcall(GetItemInfo, link)
  if not infoOk or type(equipLoc) ~= "string" then return end

  local slots = COMPARE_SLOTS[equipLoc]
  if not slots then return end

  local anchor = U.G("GameTooltip")
  local inventoryLink = U.G("GetInventoryItemLink")
  local inventorySlotInfo = U.G("GetInventorySlotInfo")
  if not anchor or type(inventoryLink) ~= "function" or
     type(inventorySlotInfo) ~= "function" then return end

  local previous = anchor
  local i
  for i = 1, table.getn(slots) do
    local slotOk, inventorySlot = pcall(inventorySlotInfo, slots[i])
    local hasItem, wornLink = false, nil
    if slotOk and inventorySlot then
      hasItem, wornLink = pcall(inventoryLink, "player", inventorySlot)
    end
    if hasItem and wornLink then
      local name = "ShoppingTooltip" .. i
      local tooltip = U.G(name)
      if tooltip and type(tooltip.SetInventoryItem) == "function" then
        pcall(tooltip.SetOwner, tooltip, anchor, "ANCHOR_NONE")
        pcall(tooltip.ClearAllPoints, tooltip)
        pcall(tooltip.SetPoint, tooltip, "BOTTOMRIGHT", previous,
              "BOTTOMLEFT", -3, 0)

        local setOk, populated = pcall(tooltip.SetInventoryItem, tooltip,
                                       "player", inventorySlot)
        if setOk and populated then
          pcall(AddItemCompareHeader, tooltip, name)
          -- modules/tooltip.lua owns ShoppingTooltip styling for every native
          -- and addon-driven comparison path.
          pcall(tooltip.Show, tooltip)
          previous = tooltip
        end
      end
    end
  end
end

function U.CreateItemSlot(parent, name, bag, slot)
  local template = U.ItemSlotTemplate(bag)

  local ok, button = pcall(CreateFrame, "Button", name, parent, template)

  -- The bank template has no compact record on this client at all (see
  -- knowledge.json / bank.api_contract_unverified). If it is not there, the
  -- container template is: it is what every bag slot in this addon already
  -- runs on, and Vanilla's container API addresses the bank as container -1
  -- like any other bag. Degrading to it keeps the window usable instead of
  -- drawing an empty grid.
  if (not ok or not button) and template ~= "ContainerFrameItemButtonTemplate" then
    if not bankTemplateReported then
      bankTemplateReported = true
      U.Print(U.L("BANK_SLOT_TEMPLATE_FALLBACK", template))
    end
    template = "ContainerFrameItemButtonTemplate"
    ok, button = pcall(CreateFrame, "Button", name, parent, template)
  end

  if not ok or not button then
    U.Error("itemslot: " .. template .. " unavailable; slot " ..
            bag .. "/" .. slot .. " not created")
    return nil
  end

  button:SetID(slot)
  U.StyleItemSlot(button, name,
                  template == "BankItemButtonGenericTemplate")

  -- The stock template owns the primary item tooltip. These post-hooks run
  -- after it has populated GameTooltip, then place the equipped counterpart(s)
  -- to its left. They preserve the template's click, pickup and drag behavior.
  -- modules/itemprice.lua places its owned price panel after the stock tooltip
  -- is populated. It identifies the item from this button rather than from the
  -- tooltip because replacing a GameTooltip method does not persist on this
  -- client (see that file).
  U.PostHookScript(button, "OnEnter", function()
    if type(U.ShowItemPrice) == "function" then U.ShowItemPrice(bag, slot) end
    ShowItemCompare(bag, slot)
  end)
  U.PostHookScript(button, "OnLeave", function()
    if type(U.HideItemPrice) == "function" then U.HideItemPrice() end
    HideItemCompare()
  end)

  -- ContainerFrame_UpdateCooldown resolves the cooldown by frame name. The
  -- container template ships one; the bank template does not, so it gets the
  -- same child under the name that function looks for (pfUI does the same).
  if template == "BankItemButtonGenericTemplate" and
     not U.G(name .. "Cooldown") then
    pcall(function()
      local cd = CreateFrame("Model", name .. "Cooldown", button,
                             "CooldownFrameTemplate")
      cd:SetAllPoints(button)
    end)
  end

  return button
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function U.UpdateItemSlotCooldown(bag, button)
  if not button then return end
  local fn = U.G("ContainerFrame_UpdateCooldown")
  if type(fn) == "function" then pcall(fn, bag, button) end
end

function U.UpdateItemSlot(button, bag, slot)
  if not button then return end

  local ok, texture, count, locked, quality =
    pcall(GetContainerItemInfo, bag, slot)
  if not ok then texture, count, locked, quality = nil, nil, nil, nil end

  pcall(SetItemButtonTexture, button, texture)
  pcall(SetItemButtonCount, button, count)
  pcall(SetItemButtonDesaturated, button, locked, 0.5, 0.5, 0.5)

  -- The quantity is then written to the region directly rather than being left
  -- to SetItemButtonCount: that helper resolves the region by frame name and
  -- has no compact record on this client, while the region itself is the one
  -- UnrealPfUI demonstrably drives here. The helper call above still runs
  -- first so button.count keeps the value stock stack-split code reads.
  -- Vanilla shows a quantity only for a real stack, so a single item stays
  -- bare.
  if button.uuiCount then
    local n = tonumber(count)
    local text = (n and n > 1) and tostring(n) or ""
    pcall(button.uuiCount.SetText, button.uuiCount, text)
    if text == "" then
      pcall(button.uuiCount.Hide, button.uuiCount)
    else
      -- Set the final display state after the stock helper so the bank and
      -- player-bag templates receive the same visible stack-count treatment.
      pcall(button.uuiCount.SetAlpha, button.uuiCount, 1)
      pcall(button.uuiCount.Show, button.uuiCount)
    end
  end

  local color = U.ItemSlotBorderColor(bag, slot, texture, quality)
  U.SetBorderColor(button, color[1], color[2], color[3], color[4] or 1)

  U.UpdateItemSlotCooldown(bag, button)
end
