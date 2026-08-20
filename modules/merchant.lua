-- unrealUI :: modules/merchant.lua
--
-- pfUI-modern-inspired treatment of the native Merchant window. Native item
-- data, buy/sell/repair logic and tab switching stay intact; unrealUI changes
-- only artwork, typography and layout, matching the Character/Quest Log
-- treatment.
--
-- query_compat.py has no record at all for MerchantFrame or any of its child
-- regions (checked before writing this file). Every field name below is
-- WORKING_SOURCE from UnrealPfUI's skins/blizzard/merchant.lua, not runtime-
-- verified on this client -- every access is G()+pcall guarded so a wrong
-- name simply leaves that element untouched rather than erroring. Confirm in
-- game and fold real names into knowledge.json once checked.

local U = UnrealUI
local M = U.media
local MER = U.RegisterModule("merchant")

local GOLD  = { 0.96, 0.68, 0.04, 1.00 }
local WHITE = { 0.90, 0.90, 0.90, 1.00 }
local DIM   = { 0.60, 0.60, 0.60, 1.00 }

local frame, panel

-- Vanilla's MERCHANT_ITEMS_PER_PAGE is documented as 10, but the number of
-- MerchantItem<n> buttons the stock template actually instantiates has no
-- compact-DB record. Iterating a fixed upper bound and G()-guarding each
-- index (same convention as character.lua's SKILL_ROWS) is safe either way --
-- an index past the real count is simply absent and every loop body already
-- handles that.
local ITEM_ROWS = 12
local TAB_COUNT = 2

local function G(name)
  return U.G(name)
end

local function SetTextFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

-- Tints the flat row background behind an item/buyback slot. WORKING_SOURCE
-- (UnrealPfUI): a thin low-layer white-alpha wash rather than a full
-- CreateBackdrop, so the native item icon and money frame beside it stay the
-- visual focus of the row.
local function TintRow(owner)
  if not owner or owner.uuiRowTint then return end
  local ok, tint = pcall(owner.CreateTexture, owner, nil, "BACKGROUND")
  if not ok or not tint then return end
  pcall(tint.SetTexture, tint, M.texture.plain)
  pcall(tint.SetVertexColor, tint, 1, 1, 1, 0.05)
  pcall(tint.SetAllPoints, tint, owner)
  owner.uuiRowTint = tint
end

-- Native regions this client exposes for a MerchantItem row are unconfirmed
-- beyond pfUI's WORKING_SOURCE names (ItemButton, MoneyFrame). Everything is
-- G()-guarded and no-ops past a missing region.
local function StyleItemRow(i)
  local row = G("MerchantItem" .. i)
  if not row then return end

  U.StripStockTextures(row)
  TintRow(row)

  local itemButton = G("MerchantItem" .. i .. "ItemButton")
  if itemButton then
    local icon = G("MerchantItem" .. i .. "ItemButtonIconTexture")
    U.StyleStockButton(itemButton, { icon = icon })
  end

  local money = G("MerchantItem" .. i .. "MoneyFrame")
  if money and itemButton then
    pcall(function()
      money:ClearAllPoints()
      money:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMRIGHT", 5, 1)
    end)
  end
end

local function StyleItemRows()
  local i
  for i = 1, ITEM_ROWS do
    StyleItemRow(i)
  end
end

local function StyleBuyBackSlot()
  local slot = G("MerchantBuyBackItem")
  if not slot then return end

  U.StripStockTextures(slot)
  TintRow(slot)

  local itemButton = G("MerchantBuyBackItemItemButton")
  if itemButton then
    local icon = G("MerchantBuyBackItemItemButtonIconTexture")
    U.StyleStockButton(itemButton, { icon = icon })
  end
end

local function StyleRepairButtons()
  local repairAll = G("MerchantRepairAllButton")
  if repairAll then
    U.StyleStockButton(repairAll, { icon = G("MerchantRepairAllIcon") })
    local icon = G("MerchantRepairAllIcon")
    -- WORKING_SOURCE (UnrealPfUI): MerchantRepairAllIcon is an atlas region,
    -- not a plain square icon, so the generic 0.08-0.92 slot crop
    -- U.StyleStockButton applies leaves it looking wrong. Recrop to pfUI's
    -- proven coordinates for this specific icon.
    if icon then pcall(icon.SetTexCoord, icon, 0.31, 0.53, 0.06, 0.52) end
  end

  local repairItem = G("MerchantRepairItemButton")
  if repairItem then
    U.StyleStockButton(repairItem)

    -- BUG (reported in game): the repair-item icon came up blank whenever an
    -- NPC could repair. Cause: unlike MerchantRepairAllButton, this button
    -- has no separate icon region -- its icon IS the button's own normal
    -- texture. U.StyleStockButton's ClearButtonFaces unconditionally clears
    -- every button's normal texture (SetNormalTexture(button, "")) on the
    -- assumption that a real icon lives in a separate child region, which
    -- holds for every other stock button skinned so far but not this one.
    -- WORKING_SOURCE (UnrealPfUI skins/blizzard/merchant.lua): it hits the
    -- exact same clear and explicitly restores the icon texture + crop
    -- afterward, which this was missing.
    pcall(repairItem.SetNormalTexture, repairItem,
          "Interface\\MerchantFrame\\UI-Merchant-RepairIcons")
    local iconOk, icon = pcall(repairItem.GetNormalTexture, repairItem)
    if iconOk and icon then
      pcall(icon.SetTexCoord, icon, 0.03, 0.25, 0.07, 0.50)
      pcall(icon.Show, icon)
      pcall(icon.SetAlpha, icon, 1)
    end

    if repairAll then
      pcall(function()
        repairItem:ClearAllPoints()
        repairItem:SetPoint("RIGHT", repairAll, "LEFT", -4, 0)
      end)
    end
  end

  -- TBC+ guild-bank repair button. No compact-DB record either way; this
  -- Vanilla-shaped client likely has no such global, so this simply no-ops
  -- when absent rather than assuming its presence.
  local guildRepair = G("MerchantGuildBankRepairButton")
  if guildRepair then
    U.StyleStockButton(guildRepair, { icon = G("MerchantGuildBankRepairButtonIcon") })
  end
end

local function StylePageControls()
  U.StyleStockArrowButton(G("MerchantPrevPageButton"), "left", 18)
  U.StyleStockArrowButton(G("MerchantNextPageButton"), "right", 18)
  SetTextFont(G("MerchantPageText"), M.fontSize.small, DIM)
end

local function StyleTabs()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("MerchantFrameTab" .. i)
  end
  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)
end

-- The NPC portrait/name header is UNVERIFIED against this client's compact
-- evidence -- no query_compat.py or query_unrealUI.py record covers either
-- global. Guarded so a wrong name just leaves native art/text in place.
local function StyleHeader()
  local name = G("MerchantFrameTitleText") or G("MerchantNameText")
  if name then SetTextFont(name, M.fontSize.large, GOLD) end

  local portrait = G("MerchantFramePortrait")
  if portrait then
    pcall(portrait.SetTexCoord, portrait, 0.08, 0.92, 0.08, 0.92)
  end
end

local function Reapply()
  U.StripStockTextures(frame)
  if panel then panel:Show() end

  StyleHeader()
  StyleItemRows()
  StyleBuyBackSlot()
end

local function BuildFrame()
  frame = G("MerchantFrame")
  if not frame then
    U.Debug("merchant: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  panel = U.CreatePanel(frame, {
    name = "UnrealUIMerchantPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 58)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 10, 30, 10, 58)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  U.StyleStockCloseButton(G("MerchantFrameCloseButton"), panel, -6, -6)
  U.MakeWindowDraggable("merchant", frame, { headerInset = 54 })

  StyleHeader()
  StyleTabs()
  StyleItemRows()
  StylePageControls()
  StyleBuyBackSlot()
  StyleRepairButtons()

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  -- MerchantFrame_UpdateMerchantInfo redraws item icons whenever stock, gold
  -- or the buyback list changes while the window is open; re-running these
  -- keeps unrealUI's border/icon framing in sync with it. StyleStockButton
  -- no-ops its one-time strip/backdrop pass per button but still re-applies
  -- icon show/alpha/crop every call, so this is safe to call repeatedly.
  --
  -- BUG (reported in game): the most recently sold item never appeared in
  -- the buyback slot. StyleBuyBackSlot was only ever called once, at
  -- BuildFrame/OnShow, before anything had been sold -- selling an item
  -- fires MerchantFrame_UpdateMerchantInfo without re-showing the frame, so
  -- the only hook that ran again was StyleItemRows, and the buyback icon's
  -- show/alpha/crop pass never got a chance to re-apply once native code
  -- actually populated it.
  U.PostHookGlobal("MerchantFrame_UpdateMerchantInfo", function()
    StyleItemRows()
    StyleBuyBackSlot()
  end)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

function MER:OnEnable()
  BuildFrame()
end
