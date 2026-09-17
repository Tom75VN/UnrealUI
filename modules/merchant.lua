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
local useModernWow = false

-- Vanilla's MERCHANT_ITEMS_PER_PAGE is documented as 10, but the number of
-- MerchantItem<n> buttons the stock template actually instantiates has no
-- compact-DB record. Iterating a fixed upper bound and G()-guarding each
-- index (same convention as character.lua's SKILL_ROWS) is safe either way --
-- an index past the real count is simply absent and every loop body already
-- handles that.
local ITEM_ROWS = 12
local TAB_COUNT = 2

-- merchant.buyback_rarity_pipeline.v1 measured GetBuybackItemInfo returning
-- name, texture, price, quantity, availability and buyability -- but no link or
-- quality. modules/itemprice.lua supplies a fallback that resolves that
-- name/texture pair against item ids for which UnrealUI has price data, then
-- GetItemInfo supplies the quality.
-- The live bag snapshot below covers server/custom items before they are sold;
-- unresolved leftovers fail closed and keep their native appearance.
local merchantInfoHooked = false
local buybackInfoHooked = false
local buybackQualityByName = {}
local BUYBACK_EDGE_SIZE = 2

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

local function MerchantIsOnBuybackTab()
  local merchant = frame or G("MerchantFrame")
  return merchant and tonumber(merchant.selectedTab) == 2
end

local function ItemTexturePath(texture)
  if not texture or type(texture.GetTexture) ~= "function" then return nil end
  local ok, path = pcall(texture.GetTexture, texture)
  if ok and type(path) == "string" and path ~= "" then return path end
  return nil
end

local function BuybackNameRegion(i, row)
  local region = G("MerchantItem" .. i .. "Name")
  if region then return region end
  if not row or type(row.GetFontString) ~= "function" then return nil end
  local ok, fontString = pcall(row.GetFontString, row)
  if ok then return fontString end
  return nil
end

-- Dedicated quality edges deliberately do not reuse button.uuiEdges. The
-- flat themes' stock-button hover handler owns those edges, while Classic and
-- Modern WoW keep their native merchant buttons. Four overlay textures on the
-- native button give every theme the same semantic rarity outline without
-- replacing or anchoring new frames to client-owned widgets.
local function BuybackEdges(itemButton)
  if not itemButton or not itemButton.CreateTexture then return nil end
  if itemButton.uuiBuybackEdges then return itemButton.uuiBuybackEdges end

  local edges = {}
  local anchors = {
    { "TOPLEFT", "TOPRIGHT", true },
    { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false },
    { "TOPRIGHT", "BOTTOMRIGHT", false },
  }
  local i
  for i = 1, table.getn(anchors) do
    local ok, edge = pcall(itemButton.CreateTexture, itemButton, nil, "OVERLAY")
    if not ok or not edge then return nil end
    pcall(edge.SetTexture, edge, M.texture.plain)
    pcall(edge.SetPoint, edge, anchors[i][1], itemButton, anchors[i][1], 0, 0)
    pcall(edge.SetPoint, edge, anchors[i][2], itemButton, anchors[i][2], 0, 0)
    if anchors[i][3] then
      pcall(edge.SetHeight, edge, BUYBACK_EDGE_SIZE)
    else
      pcall(edge.SetWidth, edge, BUYBACK_EDGE_SIZE)
    end
    pcall(edge.Hide, edge)
    edges[i] = edge
  end

  itemButton.uuiBuybackEdges = edges
  return edges
end

local function ShowBuybackEdges(itemButton, color)
  local edges = BuybackEdges(itemButton)
  if not edges then return end
  local i
  for i = 1, table.getn(edges) do
    U.SetColor(edges[i], color[1], color[2], color[3], color[4] or 1)
    pcall(edges[i].SetAlpha, edges[i], color[4] or 1)
    pcall(edges[i].Show, edges[i])
  end
end

local function HideBuybackEdges(itemButton)
  local edges = itemButton and itemButton.uuiBuybackEdges
  if not edges then return end
  local i
  for i = 1, table.getn(edges) do pcall(edges[i].Hide, edges[i]) end
end

local function RestoreBuybackName(region)
  local color = region and region.uuiBuybackBaseColor
  if not color then return end
  pcall(region.SetTextColor, region,
        color[1], color[2], color[3], color[4] or 1)
end

local function RememberItemQuality(link)
  if type(link) ~= "string" and type(link) ~= "number" then return end

  local ok, name, _, quality, _, _, _, _, _, texture = pcall(GetItemInfo, link)
  quality = ok and tonumber(quality) or nil
  if type(name) ~= "string" or name == "" or not quality then return end

  buybackQualityByName[name] = {
    quality = quality,
    texture = type(texture) == "string" and texture or nil,
  }
end

-- Snapshot carried items while the merchant is open, before a right-click can
-- remove one from its bag. This covers server/custom items that do not exist in
-- the bundled Vanilla price table: their direct bag link still carries the
-- exact quality that GetBuybackItemInfo omits after the sale.
local function RememberBagItemQualities()
  local merchant = frame or G("MerchantFrame")
  if not merchant then return end

  local shown = true
  if type(merchant.IsShown) == "function" then
    local shownOk, value = pcall(merchant.IsShown, merchant)
    shown = shownOk and value and true or false
  end
  if not shown then return end

  local bag
  for bag = 0, 4 do
    local countOk, count = pcall(GetContainerNumSlots, bag)
    count = countOk and tonumber(count) or 0
    local slot
    for slot = 1, count do
      local linkOk, link = pcall(GetContainerItemLink, bag, slot)
      if linkOk and link then RememberItemQuality(link) end
    end
  end
end

local function QualityFromTooltip(name)
  local label = G("GameTooltipTextLeft1")
  if not label or type(label.GetText) ~= "function" or
     type(label.GetTextColor) ~= "function" then
    return nil
  end

  local textOk, text = pcall(label.GetText, label)
  if not textOk or text ~= name then return nil end

  local colorOk, r, g, b = pcall(label.GetTextColor, label)
  if not colorOk or not tonumber(r) or not tonumber(g) or not tonumber(b) then
    return nil
  end

  -- Accept only an actual stock rarity colour. This prevents the merchant's
  -- ordinary gold label colour from being mistaken for legendary quality.
  local quality
  for quality = 0, 6 do
    local color = U.ItemQualityColor(quality)
    if color and math.abs(r - color[1]) < 0.03 and
       math.abs(g - color[2]) < 0.03 and
       math.abs(b - color[3]) < 0.03 then
      buybackQualityByName[name] = { quality = quality }
      return quality
    end
  end
  return nil
end

local function BuybackRowQuality(i, itemButton, icon)
  local getInfo = G("GetBuybackItemInfo")
  if type(getInfo) ~= "function" then return nil, nil end

  local ok, name, buybackTexture = pcall(getInfo, i)
  if not ok or type(name) ~= "string" or name == "" then return nil, nil end

  local cached = buybackQualityByName[name]
  if cached and tonumber(cached.quality) then
    local color = U.ItemQualityColor(cached.quality)
    if color then
      itemButton.uuiBuybackQuality = cached.quality
      return name, color
    end
  end

  local linkByInfo = U.PricedItemLinkByInfo
  if type(linkByInfo) ~= "function" then return name, nil end
  local texture = type(buybackTexture) == "string" and buybackTexture
                  or ItemTexturePath(icon)
  local link = linkByInfo(name, texture)
  if not link then return name, nil end

  local infoOk, _, _, quality = pcall(GetItemInfo, link)
  quality = infoOk and tonumber(quality) or nil
  if not quality then return name, nil end

  itemButton.uuiBuybackQuality = quality
  return name, U.ItemQualityColor(quality)
end

-- merchant.buyback_transition.v1 measured that this client does not compact
-- buyback indexes after an item is repurchased: indexes 1-4 were empty while
-- the first occupied item remained at index 5, and later sales filled 6/7.
-- Keep those real button ids (the click contract) but compact their native row
-- frames visually. The geometry below is the exact two-column chain measured
-- from the live Buyback tab; empty rows are hidden so TintRow cannot leave a
-- phantom slot behind.
local function LayoutBuybackRows(occupied)
  local i
  for i = 1, ITEM_ROWS do
    local row = G("MerchantItem" .. i)
    if row then pcall(row.Hide, row) end
  end

  for i = 1, table.getn(occupied) do
    local row = occupied[i]
    pcall(row.ClearAllPoints, row)
    if i == 1 then
      pcall(row.SetPoint, row, "TOPLEFT", frame, "TOPLEFT", 24, -80)
    elseif math.mod(i, 2) == 0 then
      pcall(row.SetPoint, row, "TOPLEFT", occupied[i - 1], "TOPRIGHT", 12, 0)
    else
      pcall(row.SetPoint, row, "TOPLEFT", occupied[i - 2], "BOTTOMLEFT", 0, -15)
    end
    pcall(row.Show, row)
  end
end

-- Buyback and vendor pages reuse the same MerchantItem<n> frames. The native
-- vendor refresh repopulates their contents but assumes the frames stayed
-- shown, so rows hidden by LayoutBuybackRows remained invisible after changing
-- back to tab 1. Restore only rows whose current button id resolves to a real
-- vendor item; this avoids bringing back empty tinted placeholders.
local function RestoreMerchantRow(row, itemButton, fallbackIndex)
  if not row then return end

  local index = fallbackIndex
  if itemButton and type(itemButton.GetID) == "function" then
    local idOk, id = pcall(itemButton.GetID, itemButton)
    if idOk and tonumber(id) then index = id end
  end

  local getInfo = G("GetMerchantItemInfo")
  local infoOk, name = false, nil
  if type(getInfo) == "function" and tonumber(index) then
    infoOk, name = pcall(getInfo, index)
  end

  if infoOk and type(name) == "string" and name ~= "" then
    pcall(row.Show, row)
  else
    pcall(row.Hide, row)
  end
end

local function RefreshBuybackRarity()
  local isBuyback = MerchantIsOnBuybackTab()
  local occupied = {}
  local i
  for i = 1, ITEM_ROWS do
    local row = G("MerchantItem" .. i)
    local itemButton = G("MerchantItem" .. i .. "ItemButton")
    local nameRegion = BuybackNameRegion(i, row)

    if not isBuyback then
      HideBuybackEdges(itemButton)
      RestoreBuybackName(nameRegion)
      if itemButton then itemButton.uuiBuybackQuality = nil end
      RestoreMerchantRow(row, itemButton, i)
    elseif itemButton and nameRegion then
      if not nameRegion.uuiBuybackBaseColor and
         type(nameRegion.GetTextColor) == "function" then
        local colorOk, r, g, b, a = pcall(nameRegion.GetTextColor, nameRegion)
        if colorOk then nameRegion.uuiBuybackBaseColor = { r, g, b, a } end
      end

      local icon = G("MerchantItem" .. i .. "ItemButtonIconTexture")
      local itemName, color = BuybackRowQuality(i, itemButton, icon)
      if itemName then table.insert(occupied, row) end
      if color then
        pcall(nameRegion.SetTextColor, nameRegion,
              color[1], color[2], color[3], color[4] or 1)
        ShowBuybackEdges(itemButton, color)
      else
        HideBuybackEdges(itemButton)
        RestoreBuybackName(nameRegion)
        itemButton.uuiBuybackQuality = nil
      end
    end
  end
  if isBuyback then LayoutBuybackRows(occupied) end
end

-- Rarity colour on a merchant tooltip's name line.
--
-- Behavior only -- no texture, font or anchor -- so it is installed in every
-- theme, unlike the skinning above. Vendor rows use their direct link; buyback
-- rows reuse the quality resolved for their visible name and outline.
local function HookItemTooltip(itemButton)
  if not itemButton or itemButton.uuiMerchantTooltipHook then return end
  itemButton.uuiMerchantTooltipHook = true

  U.PostHookScript(itemButton, "OnEnter", function()
    if type(U.ColorTooltipItemName) ~= "function" then return end

    local idOk, index = pcall(itemButton.GetID, itemButton)
    if not idOk or not tonumber(index) then return end

    if MerchantIsOnBuybackTab() then
      local getInfo = G("GetBuybackItemInfo")
      if type(getInfo) ~= "function" then return end
      local infoOk, name = pcall(getInfo, index)
      if not infoOk or type(name) ~= "string" then return end

      local quality = itemButton.uuiBuybackQuality or QualityFromTooltip(name)
      if quality then
        itemButton.uuiBuybackQuality = quality
        RefreshBuybackRarity()
      end
      U.ColorTooltipItemName(nil, quality, name)
      return
    end

    local getLink = G("GetMerchantItemLink")
    local getInfo = G("GetMerchantItemInfo")
    if type(getLink) ~= "function" or type(getInfo) ~= "function" then return end

    local linkOk, link = pcall(getLink, index)
    local infoOk, name = pcall(getInfo, index)
    if not linkOk or not infoOk or type(name) ~= "string" then return end

    U.ColorTooltipItemName(link, nil, name)
  end)

  U.PostHookScript(itemButton, "OnLeave", function()
    if type(U.ClearTooltipItemName) == "function" then
      U.ClearTooltipItemName()
    end
  end)
end

local function HookItemTooltips()
  local i
  for i = 1, ITEM_ROWS do
    HookItemTooltip(G("MerchantItem" .. i .. "ItemButton"))
  end
end

local function BindBuybackRarity()
  frame = frame or G("MerchantFrame")
  if not frame then return false end

  HookItemTooltips()
  if not merchantInfoHooked then
    merchantInfoHooked = U.PostHookGlobal(
      "MerchantFrame_UpdateMerchantInfo", RefreshBuybackRarity)
  end
  -- Measured present by merchant.buyback_transition.v1. This is the missing
  -- tab-switch path: selecting Buyback calls it without firing MERCHANT_UPDATE,
  -- which is why rarity previously appeared only after a later hover/click.
  if not buybackInfoHooked then
    buybackInfoHooked = U.PostHookGlobal(
      "MerchantFrame_UpdateBuybackInfo", RefreshBuybackRarity)
  end
  RefreshBuybackRarity()
  return true
end

local function MerchantShown()
  frame = frame or G("MerchantFrame")
  RememberBagItemQualities()
  BindBuybackRarity()
end

local function MerchantInventoryUpdated()
  RememberBagItemQualities()
  RefreshBuybackRarity()
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
  -- The Modern WoW media set has no authored left/right utility cells in
  -- either red-button atlas. Preserve the native stateful arrow art there;
  -- flat themes continue to use UnrealUI's shared arrow component.
  if not useModernWow then
    U.StyleStockArrowButton(G("MerchantPrevPageButton"), "left", 18)
    U.StyleStockArrowButton(G("MerchantNextPageButton"), "right", 18)
  end
  SetTextFont(G("MerchantPageText"), M.fontSize.small, DIM)
end

local function StyleTabs()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("MerchantFrameTab" .. i)
  end
  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)
  if useModernWow and type(U.ModernWowNpcTab) == "function" then
    for i = 1, TAB_COUNT do U.ModernWowNpcTab(tabs[i]) end
  end
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

local function StripFrameChrome()
  local portrait = G("MerchantFramePortrait")
  if portrait then
    U.StripStockTextures(frame, { keep = { [portrait] = true } })
  else
    U.StripStockTextures(frame)
  end
end

local function ApplyModernWowDialog()
  if useModernWow and type(U.ModernWowNpcDialog) == "function" then
    U.ModernWowNpcDialog(frame, panel, G("MerchantFramePortrait"),
                         "MerchantFrameCloseButton")
  end
end

local function Reapply()
  StripFrameChrome()
  if panel then panel:Show() end

  StyleHeader()
  StyleItemRows()
  StyleBuyBackSlot()
  BindBuybackRarity()
  ApplyModernWowDialog()
end

local function BuildFrame()
  frame = G("MerchantFrame")
  if not frame then
    U.Debug("merchant: native frame unavailable")
    return false
  end

  -- Also run here for a load-on-demand MerchantFrame. OnEnable's early
  -- behavior-only pass cannot see item buttons that do not exist yet; the
  -- per-button guard makes this harmless when the frame was already loaded.
  HookItemTooltips()

  StripFrameChrome()

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
  BindBuybackRarity()
  ApplyModernWowDialog()

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

-- MerchantFrame is commonly load-on-demand. UnrealPfUI's working source
-- confirms MERCHANT_SHOW on this client family; ADDON_LOADED catches the
-- corresponding UI package first when one exists. Stop listening as soon as
-- the guarded frame lookup succeeds.
local pendingEvents = { "ADDON_LOADED", "MERCHANT_SHOW" }

local function TryBuild()
  if BuildFrame() then
    local i
    for i = 1, table.getn(pendingEvents) do
      U.UnregisterEvent(pendingEvents[i], TryBuild)
    end
    return true
  end
  return false
end

function MER:OnEnable()
  -- Ahead of the theme gate: the tooltip hooks change no artwork, so Classic
  -- gets them on its untouched vendor window too.
  HookItemTooltips()
  RememberBagItemQualities()
  BindBuybackRarity()

  -- MerchantFrame is load-on-demand on some installs. These behavior-only
  -- callbacks remain active for every theme, including the two themes that
  -- deliberately keep native NPC/service-window chrome.
  U.RegisterEvent("MERCHANT_SHOW", MerchantShown)
  U.RegisterEvent("MERCHANT_UPDATE", MerchantInventoryUpdated)
  U.RegisterEvent("BAG_UPDATE", RememberBagItemQualities)

  useModernWow = type(U.GetActiveThemeStyle) == "function" and
                 U.GetActiveThemeStyle() == "modern-wow"
  if U.ThemeStyleUsesClassicInteractionChrome() then return end
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("MERCHANT_SHOW", TryBuild)
end
