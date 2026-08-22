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
function U.StyleItemSlot(button, name)
  if not button then return end
  local edge = U.BorderSize()

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

  -- fonts.stretched_justification_ignored: pfUI stretches the count across the
  -- button and justifies it BOTTOMRIGHT, which is exactly the pattern that
  -- record says can be ignored here. Anchored to the one corner instead.
  local count = U.G(name .. "Count")
  if count then
    U.SetFont(count, M.fontSize.small)
    pcall(function()
      count:ClearAllPoints()
      count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    end)
  end

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
      U.Print(template .. " is not available on this client; bank slots fall " ..
              "back to the bag slot template.")
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
  U.StyleItemSlot(button, name)

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

  local color = U.ItemSlotBorderColor(bag, slot, texture, quality)
  U.SetBorderColor(button, color[1], color[2], color[3], color[4] or 1)

  U.UpdateItemSlotCooldown(bag, button)
end
