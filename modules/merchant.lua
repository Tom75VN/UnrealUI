-- unrealUI :: modules/merchant.lua
--
-- The flat theme follows UnrealPfUI's merchant treatment. Modern WoW adapts
-- ForeverFrameXML's Mainline merchant structure to the theme's existing NPC
-- housing and media. Native item, buy/sell/repair and tab behavior stays intact.
--
-- query_compat.py has no record at all for MerchantFrame or any of its child
-- regions (checked before writing this file). Runtime globals are WORKING_SOURCE
-- from UnrealPfUI and the pinned Forever FrameXML, not runtime-verified on this
-- client; every access is G()+pcall guarded so a wrong name leaves that element
-- untouched rather than erroring.

local U = UnrealUI
local M = U.media
local MER = U.RegisterModule("merchant")

local GOLD  = { 0.96, 0.68, 0.04, 1.00 }
local WHITE = { 0.90, 0.90, 0.90, 1.00 }
local DIM   = { 0.60, 0.60, 0.60, 1.00 }

local frame, panel
local useModernWow = false
local chromeStripped = false

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
local moneyFrameHooked = false
local buybackQualityByName = {}
local BUYBACK_EDGE_SIZE = 2

local function G(name)
  return U.G(name)
end

local function ResolveItemButtonIcon(button, legacyName)
  local icon = legacyName and G(legacyName) or nil
  if icon or not button then return icon end
  local fields = { "Icon", "icon", "IconTexture" }
  local i
  for i = 1, table.getn(fields) do
    local candidate = button[fields[i]]
    if candidate and type(candidate.SetTexture) == "function" then
      return candidate
    end
  end
  return nil
end

local function SetTextFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function ModernToken()
  return useModernWow and M.modernWow and M.modernWow.merchant or nil
end

local function RaiseAboveModernChrome(object, offset)
  if not useModernWow or not object or not frame then return end
  local ok, level = pcall(frame.GetFrameLevel, frame)
  level = ok and tonumber(level) or nil
  if level then pcall(object.SetFrameLevel, object, level + (offset or 3)) end
end

local function PlaceModernRow(row, position, compact)
  local token = ModernToken()
  local layout = token and token.row
  if not row or not layout or not frame then return end
  local column = math.mod(position - 1, 2)
  local line = math.floor((position - 1) / 2)
  local x = layout.left + column * (layout.width + layout.columnGap)
  local gap = compact and layout.buybackGap or layout.rowGap
  local y = layout.top + line * (layout.height + gap)
  pcall(function()
    row:ClearAllPoints()
    row:SetWidth(layout.width)
    row:SetHeight(layout.height)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  end)
end

local function PrepareModernItemButton(button, icon)
  if not button then return end
  if not button.uuiModernWowMerchantPrepared then
    local setters = {
      "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture",
    }
    local i
    for i = 1, table.getn(setters) do
      local setter = button[setters[i]]
      if type(setter) == "function" then
        if not pcall(setter, button, "") then pcall(setter, button, nil) end
      end
    end
    pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 0)
    button.uuiModernWowMerchantPrepared = true
  end
  U.RestoreContentIcon(icon)
end

local function StyleModernMerchantSlot(button, icon, iconTexCoord)
  if not button then return end
  local token = ModernToken()
  local borderSize = token and token.slot and token.slot.borderSize
  if icon then
    PrepareModernItemButton(button, icon)
    local coord = iconTexCoord or { 0, 1, 0, 1 }
    pcall(function()
      icon:ClearAllPoints()
      icon:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
      icon:SetDrawLayer("BACKGROUND")
    end)
    if type(U.ModernWowThinBorderFill) == "function" then
      U.ModernWowThinBorderFill(icon, button, borderSize)
    else
      pcall(icon.SetAllPoints, icon, button)
    end
  end
  if not button.uuiModernWowMerchantThinBorder and
     type(U.ModernWowBuildThinBorder) == "function" then
    U.ModernWowBuildThinBorder(button, borderSize)
    button.uuiModernWowMerchantThinBorder = true
  end
end

local function MerchantItemNameColor(i, itemButton)
  local fallback = GOLD
  local normal = G("NORMAL_FONT_COLOR")
  if type(normal) == "table" and tonumber(normal.r) and
     tonumber(normal.g) and tonumber(normal.b) then
    fallback = { normal.r, normal.g, normal.b, normal.a or 1 }
  end

  local merchant = frame or G("MerchantFrame")
  if merchant and tonumber(merchant.selectedTab) == 2 then return fallback end

  local index = i
  if itemButton and type(itemButton.GetID) == "function" then
    local idOk, id = pcall(itemButton.GetID, itemButton)
    if idOk and tonumber(id) then index = id end
  end

  local getLink = G("GetMerchantItemLink")
  if type(getLink) ~= "function" then return fallback end
  local linkOk, link = pcall(getLink, index)
  if not linkOk or not link then return fallback end
  return U.ItemLinkQualityColor(link) or fallback
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
local function ScaleMoneyCoins(money, prefix, scale, offsetY)
  if not money or not prefix or not scale then return end
  local keys = { "GoldButton", "SilverButton", "CopperButton" }
  local i
  for i = 1, table.getn(keys) do
    local key = keys[i]
    local button = money[key] or G(prefix .. key)
    local texture
    if button and type(button.GetNormalTexture) == "function" then
      local ok, value = pcall(button.GetNormalTexture, button)
      if ok then texture = value end
    end
    if texture and not texture.uuiMerchantCostCoinScaled then
      local widthOk, width = pcall(texture.GetWidth, texture)
      local heightOk, height = pcall(texture.GetHeight, texture)
      width = widthOk and tonumber(width) or nil
      height = heightOk and tonumber(height) or nil
      if width and height and width > 0 and height > 0 then
        pcall(texture.SetWidth, texture, width * scale)
        pcall(texture.SetHeight, texture, height * scale)
        pcall(texture.ClearAllPoints, texture)
        pcall(texture.SetPoint, texture, "RIGHT", button, "RIGHT", 0,
              offsetY or 0)
        texture.uuiMerchantCostCoinScaled = true
      end
    end
  end
end

local function RefreshModernRowPlate(row, i)
  local state = row and row.uuiModernWowMerchantRow
  local label = state and state.label
  if not label or tonumber(frame and frame.selectedTab) == 2 then return end

  local getCount = G("GetMerchantNumItems")
  if type(getCount) ~= "function" then return end
  local countOk, count = pcall(getCount)
  count = countOk and tonumber(count) or nil
  local token = ModernToken()
  local perPage = token and token.row and token.row.count
  local page = tonumber(frame and frame.page) or 1
  if not count or not perPage then return end

  local index = (page - 1) * perPage + i
  if index <= count then
    pcall(label.SetTexture, label, M.modernWow.texture.merchantLabel)
    pcall(label.SetAlpha, label, 1)
    pcall(label.Show, label)
  else
    pcall(label.SetTexture, label, nil)
    pcall(label.Hide, label)
  end
end

local function StyleItemRow(i)
  local row = G("MerchantItem" .. i)
  if not row then return end

  if useModernWow then
    local token = ModernToken()
    local layout = token and token.row
    if not layout then return end

    if not row.uuiModernWowMerchantRow then
      U.StripStockTextures(row)
      local ok, label = pcall(row.CreateTexture, row, nil, "BACKGROUND")
      if ok and label then
        pcall(function()
          label:SetTexture(M.modernWow.texture.merchantLabel)
          label:SetWidth(layout.label.width)
          label:SetHeight(layout.label.height)
          label:SetPoint("TOPLEFT", row, "TOPLEFT",
                         layout.label.left, -layout.label.top)
        end)
      end
      row.uuiModernWowMerchantRow = { label = label }
    end

    PlaceModernRow(row, i)
    RaiseAboveModernChrome(row, 3)
    local itemButton = G("MerchantItem" .. i .. "ItemButton")
    RefreshModernRowPlate(row, i)
    local icon = ResolveItemButtonIcon(
      itemButton, "MerchantItem" .. i .. "ItemButtonIconTexture")
    StyleModernMerchantSlot(itemButton, icon)
    RaiseAboveModernChrome(itemButton, 4)
    local name = G("MerchantItem" .. i .. "Name")
    local nameColor = MerchantItemNameColor(i, itemButton)
    SetTextFont(name, M.fontSize.small, nameColor)
    if name then
      local state = row.uuiModernWowMerchantRow
      local anchor = state and state.nameAnchor
      if state and type(anchor) ~= "table" and type(name.GetPoint) == "function" then
        local anchorOk, point, relativeTo, relativePoint, x, y =
          pcall(name.GetPoint, name, 1)
        if anchorOk and point then
          anchor = {
            point = point, relativeTo = relativeTo, relativePoint = relativePoint,
            x = x or 0, y = y or 0,
          }
          state.nameAnchor = anchor
        end
      end
      if type(anchor) == "table" then
        pcall(function()
          name:ClearAllPoints()
          name:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint,
                        anchor.x + (layout.nameOffsetX or 0), anchor.y)
        end)
      end
      pcall(name.SetDrawLayer, name, "OVERLAY", 7)
      name.uuiBuybackBaseColor = nameColor
    end

    local money = G("MerchantItem" .. i .. "MoneyFrame")
    if money and itemButton then
      ScaleMoneyCoins(money, "MerchantItem" .. i .. "MoneyFrame",
                      layout.costCoinScale, layout.costCoinOffsetY)
      pcall(function()
        money:ClearAllPoints()
        money:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMRIGHT", 5, 1)
      end)
    end
    return
  end

  U.StripStockTextures(row)
  TintRow(row)

  local itemButton = G("MerchantItem" .. i .. "ItemButton")
  if itemButton then
    local icon = ResolveItemButtonIcon(
      itemButton, "MerchantItem" .. i .. "ItemButtonIconTexture")
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
  if itemButton and itemButton.uuiGearQualityGlow then
    U.SetGearQualityGlow(itemButton, M.slotBorder.plain)
  end
  local edges = itemButton and itemButton.uuiBuybackEdges
  if not edges then return end
  local i
  for i = 1, table.getn(edges) do pcall(edges[i].Hide, edges[i]) end
end

-- Classic and Modern WoW keep the native merchant buttons, so their buyback
-- rarity uses the Character window's gear-slot glow (same texture, border
-- colour and uncommon-or-better threshold) instead of the flat outline. The
-- flat Modern theme keeps the 1-unit edges of its own design system.
local function ShowBuybackRarity(itemButton, quality, color)
  if not U.ThemeStyleUsesClassicInteractionChrome() then
    ShowBuybackEdges(itemButton, color)
    return
  end
  HideBuybackEdges(itemButton)
  local border = M.slotBorder.plain
  if tonumber(quality) and quality > M.qualityLimit then
    border = U.ItemQualityBorderColor(quality) or color
  end
  U.SetGearQualityGlow(itemButton, border)
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
--
-- MerchantItem1 itself is never moved: the first occupied row is pinned to its
-- native position instead, so the vendor grid can be rebuilt from it without
-- reading GetPoint (whose Y sign is contested in knowledge.json).
local function LayoutBuybackRows(occupied)
  local first = G("MerchantItem1")
  local i
  for i = 1, ITEM_ROWS do
    local row = G("MerchantItem" .. i)
    if row then pcall(row.Hide, row) end
  end

  for i = 1, table.getn(occupied) do
    local row = occupied[i]
    if useModernWow then
      PlaceModernRow(row, i, true)
      row.uuiBuybackMoved = true
      pcall(row.Show, row)
    else
      if row ~= first then
        pcall(row.ClearAllPoints, row)
        row.uuiBuybackMoved = true
      end
      if i == 1 then
        if row ~= first and first then
          pcall(row.SetPoint, row, "TOPLEFT", first, "TOPLEFT", 0, 0)
        end
      elseif math.mod(i, 2) == 0 then
        pcall(row.SetPoint, row, "TOPLEFT", occupied[i - 1], "TOPRIGHT", 12, 0)
      else
        pcall(row.SetPoint, row, "TOPLEFT", occupied[i - 2], "BOTTOMLEFT", 0, -15)
      end
      pcall(row.Show, row)
    end
  end
end

-- Buyback and vendor pages reuse the same MerchantItem<n> frames. The native
-- vendor refresh repopulates their contents but assumes the frames stayed
-- shown, so rows hidden by LayoutBuybackRows remained invisible after changing
-- back to tab 1. Restore only rows whose current button id resolves to a real
-- vendor item; this avoids bringing back empty tinted placeholders.
--
-- BUG (reported in game, modern theme): sell -> Buyback tab -> Merchant tab
-- left vendor rows overlapping. The native vendor refresh re-points only the
-- odd rows, so even rows kept their compacted buyback chain. Rebuild the
-- native two-column vendor grid (12 across, 8 down) for every row the buyback
-- layout moved. Rows past the vendor page size stay hidden, as natively.
local VENDOR_ROWS = 10

local function RestoreMerchantAnchor(i, row)
  if useModernWow then
    PlaceModernRow(row, i)
    row.uuiBuybackMoved = nil
    return
  end
  if not row.uuiBuybackMoved then return end
  row.uuiBuybackMoved = nil
  pcall(row.ClearAllPoints, row)
  if math.mod(i, 2) == 0 then
    local left = G("MerchantItem" .. (i - 1))
    if left then pcall(row.SetPoint, row, "TOPLEFT", left, "TOPRIGHT", 12, 0) end
  else
    local above = G("MerchantItem" .. (i - 2))
    if above then pcall(row.SetPoint, row, "TOPLEFT", above, "BOTTOMLEFT", 0, -8) end
  end
end

local function RestoreMerchantRow(row, itemButton, fallbackIndex)
  if not row then return end
  RestoreMerchantAnchor(fallbackIndex, row)
  if fallbackIndex > VENDOR_ROWS then
    pcall(row.Hide, row)
    return
  end

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
  if useModernWow and isBuyback then
    local portrait = G("MerchantFramePortrait")
    if portrait then
      pcall(portrait.SetTexture, portrait, M.modernWow.texture.merchantBuyback)
    end
  end
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

      local icon = ResolveItemButtonIcon(
        itemButton, "MerchantItem" .. i .. "ItemButtonIconTexture")
      local itemName, color = BuybackRowQuality(i, itemButton, icon)
      if itemName then table.insert(occupied, row) end
      if color then
        pcall(nameRegion.SetTextColor, nameRegion,
              color[1], color[2], color[3], color[4] or 1)
        ShowBuybackRarity(itemButton, itemButton.uuiBuybackQuality, color)
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

local function StyleBuyBackSlot()
  local slot = G("MerchantBuyBackItem")
  if not slot then return end

  if useModernWow then
    local token = ModernToken()
    local layout = token and token.buyback
    if not layout then return end
    if not slot.uuiModernWowMerchantRow then
      U.StripStockTextures(slot)
      slot.uuiModernWowMerchantRow = true
    end
    pcall(function()
      slot:ClearAllPoints()
      slot:SetWidth(layout.width)
      slot:SetHeight(layout.height)
      slot:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.left, -layout.top)
    end)

    local itemButton = G("MerchantBuyBackItemItemButton")
    local icon = ResolveItemButtonIcon(
      itemButton, "MerchantBuyBackItemItemButtonIconTexture")
    StyleModernMerchantSlot(itemButton, icon)
    RaiseAboveModernChrome(slot, 3)
    RaiseAboveModernChrome(itemButton, 4)
    return
  end

  U.StripStockTextures(slot)
  TintRow(slot)

  local itemButton = G("MerchantBuyBackItemItemButton")
  if itemButton then
    local icon = ResolveItemButtonIcon(
      itemButton, "MerchantBuyBackItemItemButtonIconTexture")
    U.StyleStockButton(itemButton, { icon = icon })
  end
end

local function RefreshLastBuybackSlot()
  local getCount = G("GetNumBuybackItems")
  local getInfo = G("GetBuybackItemInfo")
  if type(getCount) ~= "function" or type(getInfo) ~= "function" then
    return false
  end

  local countOk, count = pcall(getCount)
  count = countOk and tonumber(count) or 0
  if count < 1 then return false end

  local infoOk, name, texture, price, quantity, available = pcall(getInfo, count)
  if not infoOk or type(name) ~= "string" or name == "" then return false end

  local slot = G("MerchantBuyBackItem")
  local itemButton = G("MerchantBuyBackItemItemButton")
  local icon = ResolveItemButtonIcon(
    itemButton, "MerchantBuyBackItemItemButtonIconTexture")
  if not slot or not itemButton then return false end

  local nameRegion = G("MerchantBuyBackItemName")
  if nameRegion then pcall(nameRegion.SetText, nameRegion, name) end

  local setTexture = G("SetItemButtonTexture")
  if type(setTexture) == "function" then
    pcall(setTexture, itemButton, texture)
  elseif icon then
    pcall(icon.SetTexture, icon, texture)
  end
  if icon then
    pcall(icon.SetTexture, icon, texture)
    U.RestoreContentIcon(icon)
  end

  local setCount = G("SetItemButtonCount")
  if type(setCount) == "function" then
    pcall(setCount, itemButton, tonumber(quantity) or 0)
  end
  local setStock = G("SetItemButtonStock")
  if type(setStock) == "function" then
    pcall(setStock, itemButton, tonumber(available) or 0)
  end

  local money = G("MerchantBuyBackItemMoneyFrame")
  local updateMoney = G("MoneyFrame_Update")
  if money and type(updateMoney) == "function" then
    local moneyNameOk, moneyName = pcall(money.GetName, money)
    pcall(updateMoney,
          moneyNameOk and moneyName or "MerchantBuyBackItemMoneyFrame",
          tonumber(price) or 0)
    pcall(money.Show, money)
  end

  itemButton.hasItem = true
  itemButton.name = name
  itemButton.texture = texture
  pcall(slot.Show, slot)
  pcall(itemButton.Show, itemButton)
  StyleBuyBackSlot()
  return true
end

local function ScheduleLastBuybackRefresh()
  if type(U.DeferOnce) ~= "function" then
    RefreshLastBuybackSlot()
    RefreshBuybackRarity()
    return
  end
  U.DeferOnce("merchant.last-buyback", function()
    RefreshLastBuybackSlot()
    RefreshBuybackRarity()
  end)
end

local function MerchantInventoryUpdated()
  RememberBagItemQualities()
  ScheduleLastBuybackRefresh()
end

local function StyleModernRepairButton(button, nativeIcon, cell, layout)
  local iconSpec = layout and layout.icon
  if not button or not cell or not iconSpec then return end

  PrepareModernItemButton(button, nativeIcon)

  local state = button.uuiModernWowRepairArt
  if type(state) ~= "table" then
    local ownedIcon
    if not nativeIcon then
      local iconOk
      iconOk, ownedIcon = pcall(button.CreateTexture, button, nil, "BORDER")
      if not iconOk then ownedIcon = nil end
    end
    state = { icon = ownedIcon }
    button.uuiModernWowRepairArt = state
  end

  local icon = nativeIcon or state.icon
  if not icon then return end

  pcall(function()
    icon:ClearAllPoints()
    icon:SetTexture(iconSpec.texture)
    icon:SetTexCoord(cell[1] / iconSpec.sheetWidth,
                     cell[2] / iconSpec.sheetWidth,
                     cell[3] / iconSpec.sheetHeight,
                     cell[4] / iconSpec.sheetHeight)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    icon:SetDrawLayer("BORDER")
    icon:SetVertexColor(1, 1, 1, 1)
    icon:SetAlpha(1)
    icon:Show()
  end)
end

local function StyleRepairButtons()
  local repairAll = G("MerchantRepairAllButton")
  if useModernWow then
    local token = ModernToken()
    local layout = token and token.repairs
    if not layout then return end
    local repairItem = G("MerchantRepairItemButton")
    local guildRepair = G("MerchantGuildBankRepairButton")
    local buttons = {
      { repairAll, G("MerchantRepairAllIcon") or
        (repairAll and repairAll.Icon),
        layout.icon.repairAll },
      { repairItem, repairItem and repairItem.Icon, layout.icon.repair },
      { guildRepair, G("MerchantGuildBankRepairButtonIcon") or
        (guildRepair and guildRepair.Icon),
        layout.icon.repairAllGuild },
    }
    local visible = 0
    local i
    for i = 1, table.getn(buttons) do
      local button, icon = buttons[i][1], buttons[i][2]
      if button then
        pcall(function()
          button:ClearAllPoints()
          button:SetWidth(layout.size)
          button:SetHeight(layout.size)
          button:SetPoint("TOPLEFT", frame, "TOPLEFT",
                          layout.right - layout.size -
                          visible * (layout.size + layout.gap),
                          -layout.top)
        end)
        StyleModernRepairButton(button, icon, buttons[i][3], layout)
        RaiseAboveModernChrome(button, 4)
        visible = visible + 1
      end
    end
    return
  end

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

local function RefreshPageText()
  if not useModernWow or not frame then return end
  local pageText = G("MerchantPageText")
  local getNumItems = G("GetMerchantNumItems")
  local token = ModernToken()
  local page = token and token.page
  if not page or type(getNumItems) ~= "function" then return end

  if pageText then pcall(pageText.Hide, pageText) end
  local state = frame.uuiModernWowMerchantPageText
  if not state then
    local layer = CreateFrame("Frame", nil, frame)
    layer:SetAllPoints(frame)
    pcall(layer.EnableMouse, layer, false)
    local label = U.CreateLabel(layer, {
      size = M.fontSize.small,
      color = DIM,
      inherits = "GameFontNormal",
      justify = "CENTER",
    })
    if label then
      label:SetPoint("CENTER", layer, "TOPLEFT", token.width / 2, -page.top)
      pcall(label.SetDrawLayer, label, "OVERLAY", 7)
    end
    state = { layer = layer, label = label }
    frame.uuiModernWowMerchantPageText = state
  end
  RaiseAboveModernChrome(state.layer, 5)
  if not state.label then return end

  local ok, itemCount = pcall(getNumItems)
  itemCount = ok and tonumber(itemCount) or nil
  local perPage = tonumber(G("MERCHANT_ITEMS_PER_PAGE")) or
                  (token and token.row and token.row.count)
  local currentPage = tonumber(frame.page) or 1
  local totalPages = itemCount and perPage and perPage > 0 and
                     math.max(1, math.ceil(itemCount / perPage)) or nil

  if tonumber(frame.selectedTab) == 2 or not totalPages or totalPages <= 1 then
    pcall(state.label.Hide, state.label)
    return
  end

  currentPage = math.max(1, math.min(currentPage, totalPages))
  pcall(state.label.SetText, state.label,
        U.L("MERCHANT_PAGE_COUNT", currentPage, totalPages))
  pcall(state.label.Show, state.label)
end

local function StyleModernPageButton(button, left)
  local token = ModernToken()
  local page = token and token.page
  local spec = page and page.icon
  local atlas = spec and spec.atlas
  if not button or not atlas then return end

  local function SetCell(texture)
    if not texture then return end
    local cell = atlas.next
    local u1, u2 = cell[1] / atlas.sheet, cell[2] / atlas.sheet
    local v1, v2 = cell[3] / atlas.sheet, cell[4] / atlas.sheet
    if left then
      pcall(texture.SetTexCoord, texture, u2, u1, v2, v1)
    else
      pcall(texture.SetTexCoord, texture, u1, u2, v1, v2)
    end
  end

  local state = button.uuiModernWowMerchantPageIcon
  if type(state) ~= "table" then
    local label
    if type(button.GetRegions) == "function" then
      local regionsOk, regions = pcall(function() return { button:GetRegions() } end)
      if regionsOk and type(regions) == "table" then
        local i
        for i = 1, table.getn(regions) do
          local region = regions[i]
          if region and type(region.SetTextColor) == "function" then
            label = region
            break
          end
        end
      end
    end
    U.StripStockTextures(button)
    pcall(button.SetNormalTexture, button, "")
    pcall(button.SetPushedTexture, button, "")
    pcall(button.SetDisabledTexture, button, "")
    pcall(button.SetHighlightTexture, button, "")

    local faceOk, face = pcall(button.CreateTexture, button, nil, "ARTWORK")
    if not faceOk or not face then return end
    pcall(face.SetTexture, face, atlas.texture)
    pcall(face.SetAllPoints, face, button)

    local glowOk, glow = pcall(button.CreateTexture, button, nil, "OVERLAY")
    if glowOk and glow then
      pcall(glow.SetTexture, glow, atlas.texture)
      pcall(glow.SetAllPoints, glow, button)
      pcall(glow.SetBlendMode, glow, "ADD")
      pcall(glow.SetAlpha, glow, spec.hoverAlpha or 0.45)
      pcall(glow.Hide, glow)
    else
      glow = nil
    end

    state = { face = face, glow = glow, label = label, over = false, down = false }
    button.uuiModernWowMerchantPageIcon = state
    U.PostHookScript(button, "OnEnter", function()
      state.over = true
      StyleModernPageButton(button, left)
    end)
    U.PostHookScript(button, "OnLeave", function()
      state.over = false
      state.down = false
      StyleModernPageButton(button, left)
    end)
    U.PostHookScript(button, "OnMouseDown", function()
      state.down = true
      StyleModernPageButton(button, left)
    end)
    U.PostHookScript(button, "OnMouseUp", function()
      state.down = false
      StyleModernPageButton(button, left)
    end)
    U.PostHookScript(button, "OnEnable", function()
      StyleModernPageButton(button, left)
    end)
    U.PostHookScript(button, "OnDisable", function()
      StyleModernPageButton(button, left)
    end)
  end

  pcall(button.SetWidth, button, spec.size)
  pcall(button.SetHeight, button, spec.size)
  local hit = spec.hitPadding or 0
  pcall(button.SetHitRectInsets, button, -hit, -hit, -hit, -hit)

  SetCell(state.face)
  SetCell(state.glow)
  local enabled = true
  if type(button.IsEnabled) == "function" then
    local enabledOk, value = pcall(button.IsEnabled, button)
    if enabledOk then enabled = value and value ~= 0 end
  end
  if not enabled then state.down = false end
  local shade = not enabled and (spec.disabledShade or 0.45) or
                (state.down and (spec.pressShade or 1) or 1)
  pcall(state.face.SetDesaturated, state.face, not enabled)
  pcall(state.face.SetBlendMode, state.face, enabled and "BLEND" or "ADD")
  pcall(state.face.SetVertexColor, state.face, shade, shade, shade, 1)
  pcall(state.face.Show, state.face)
  local textColor = enabled and page.textColor or page.disabledTextColor
  if textColor then
    local function PaintLabel(label)
      if not label or type(label.SetTextColor) ~= "function" then return end
      pcall(label.SetTextColor, label,
            textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    end
    PaintLabel(state.label)
    if type(button.GetRegions) == "function" then
      local regionsOk, regions = pcall(function() return { button:GetRegions() } end)
      if regionsOk and type(regions) == "table" then
        local i
        for i = 1, table.getn(regions) do
          local region = regions[i]
          if region and type(region.SetTextColor) == "function" then
            if not state.label then state.label = region end
            PaintLabel(region)
          end
        end
      end
    end
  end
  if state.glow then
    if enabled and state.over and not state.down then
      pcall(state.glow.Show, state.glow)
    else
      pcall(state.glow.Hide, state.glow)
    end
  end
end

local function StylePageControls()
  -- Modern WoW uses the settings atlas's stepper glyph; flat themes keep
  -- UnrealUI's shared arrow component.
  if not useModernWow then
    U.StyleStockArrowButton(G("MerchantPrevPageButton"), "left", 18)
    U.StyleStockArrowButton(G("MerchantNextPageButton"), "right", 18)
  else
    local token = ModernToken()
    local page = token and token.page
    local previous = G("MerchantPrevPageButton")
    local nextButton = G("MerchantNextPageButton")
    if page and previous and nextButton then
      StyleModernPageButton(previous, true)
      StyleModernPageButton(nextButton, false)
      pcall(function()
        previous:ClearAllPoints()
        previous:SetPoint("CENTER", frame, "TOPLEFT", page.left, -page.top)
        nextButton:ClearAllPoints()
        nextButton:SetPoint("CENTER", frame, "TOPLEFT", page.right, -page.top)
      end)
      RaiseAboveModernChrome(previous, 4)
      RaiseAboveModernChrome(nextButton, 4)
    end
  end
  local pageText = G("MerchantPageText")
  if not useModernWow then SetTextFont(pageText, M.fontSize.small, DIM) end
  RefreshPageText()
end

local function StyleMoneyFooter()
  if not useModernWow then return end
  local token = ModernToken()
  local money = token and token.money
  if not money then return end

  local decorations = {
    G("MerchantExtraCurrencyInset"), G("MerchantExtraCurrencyBg"),
    G("MerchantMoneyInset"), G("MerchantMoneyBg"),
  }
  local i
  for i = 1, table.getn(decorations) do
    local decoration = decorations[i]
    if decoration and not decoration.uuiModernWowMerchantStripped then
      U.StripStockTextures(decoration)
      decoration.uuiModernWowMerchantStripped = true
    end
  end

  local readout = G("MerchantMoneyFrame")
  if readout then
    pcall(function()
      readout:ClearAllPoints()
      readout:SetPoint("RIGHT", frame, "TOPLEFT",
                       money.left + money.width + money.contentRight,
                       -(money.top + money.height / 2) +
                       (money.readoutOffsetY or 0))
    end)

    local state = readout.uuiModernWowMerchantMoneyOffsets
    if type(state) ~= "table" then
      state = {}
      readout.uuiModernWowMerchantMoneyOffsets = state
    end
    local function OffsetRegion(region, key, offset)
      if not region or type(region.GetPoint) ~= "function" then return end
      local base = state[key]
      if type(base) ~= "table" or base.region ~= region then
        local ok, point, relativeTo, relativePoint, x, y =
          pcall(region.GetPoint, region, 1)
        if not ok or not point then return end
        base = {
          region = region, point = point, relativeTo = relativeTo,
          relativePoint = relativePoint, x = x or 0, y = y or 0,
        }
        state[key] = base
      end
      pcall(function()
        region:ClearAllPoints()
        region:SetPoint(base.point, base.relativeTo, base.relativePoint,
                        base.x, base.y + offset)
      end)
    end

    local denominations = {
      { readout.GoldButton, "gold" },
      { readout.SilverButton, "silver" },
      { readout.CopperButton, "copper" },
    }
    local j
    for j = 1, table.getn(denominations) do
      local button, key = denominations[j][1], denominations[j][2]
      if button then
        local iconOk, icon = false, nil
        if type(button.GetNormalTexture) == "function" then
          iconOk, icon = pcall(button.GetNormalTexture, button)
        end
        if iconOk then OffsetRegion(icon, key .. "Icon", money.coinOffsetY or 0) end
        local label = button.Text
        if not label and type(button.GetFontString) == "function" then
          local labelOk, value = pcall(button.GetFontString, button)
          if labelOk then label = value end
        end
        OffsetRegion(label, key .. "Text", money.textOffsetY or 0)
      end
    end

    if not moneyFrameHooked then
      moneyFrameHooked = U.PostHookGlobal("MoneyFrame_Update", function(updated)
        if updated == readout then StyleMoneyFooter() end
      end)
    end
    RaiseAboveModernChrome(readout, 4)
  end
end

local function StyleTabs()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("MerchantFrameTab" .. i)
  end
  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)
  if useModernWow and type(U.ModernWowDressTab) == "function" then
    for i = 1, TAB_COUNT do U.ModernWowDressTab(tabs[i]) end
    local token = ModernToken()
    local layout = token and token.tabs
    if layout and tabs[1] then
      U.FitStockTabStrip(tabs, frame, {
        gap = layout.gap,
        left = layout.left,
        right = layout.left,
        padding = M.modernWow.tab.padding,
        minPadding = 4,
        anchor = {
          frame = frame,
          point = "TOPLEFT",
          relativePoint = "TOPLEFT",
          x = layout.left,
          y = -layout.top,
        },
      })
    end
    for i = 1, TAB_COUNT do RaiseAboveModernChrome(tabs[i], 4) end
  end
end

-- Stock merchant title globals vary by client; Modern WoW owns the visible
-- label and reads the current NPC directly.
local function StyleHeader()
  local name = G("MerchantFrameTitleText") or G("MerchantNameText")
  if name then SetTextFont(name, M.fontSize.large, GOLD) end
  if useModernWow then
    local token = ModernToken()
    local title = token and token.title
    if title then
      local state = frame.uuiModernWowMerchantTitle
      if not state then
        local layer = CreateFrame("Frame", nil, frame)
        layer:SetAllPoints(frame)
        pcall(layer.EnableMouse, layer, false)
        local label = U.CreateLabel(layer, {
          size = M.fontSize.large,
          color = title.color,
          inherits = "GameFontNormal",
          justify = "CENTER",
        })
        if label then
          label:SetPoint("CENTER", layer, "TOPLEFT", title.x,
                         -(title.y + (token.titleOffsetY or 0)))
          pcall(label.SetDrawLayer, label, "OVERLAY", 7)
        end
        state = { layer = layer, label = label }
        frame.uuiModernWowMerchantTitle = state
      end

      RaiseAboveModernChrome(state.layer, 6)
      local unitOk, text = pcall(UnitName, "npc")
      if not unitOk or type(text) ~= "string" or text == "" then
        local textOk
        textOk, text = name and pcall(name.GetText, name)
        if not textOk then text = nil end
      end
      if state.label then
        pcall(state.label.SetText, state.label, text or "")
        pcall(state.label.SetTextColor, state.label,
              title.color[1], title.color[2], title.color[3],
              title.color[4] or 1)
        pcall(state.label.Show, state.label)
      end
      if name and state.label then
        pcall(name.SetAlpha, name, 0)
        pcall(name.Hide, name)
      end
    end
  end

  local portrait = G("MerchantFramePortrait")
  if portrait then
    pcall(portrait.SetTexCoord, portrait, 0.08, 0.92, 0.08, 0.92)
  end
end

local function StripFrameChrome()
  if useModernWow and chromeStripped then return end
  local portrait = G("MerchantFramePortrait")
  if portrait then
    U.StripStockTextures(frame, { keep = { [portrait] = true } })
  else
    U.StripStockTextures(frame)
  end
  if useModernWow then chromeStripped = true end
end

local function ApplyModernWowDialog()
  if useModernWow and type(U.ModernWowMerchantChrome) == "function" then
    U.ModernWowMerchantChrome(frame, panel, G("MerchantFramePortrait"),
                              "MerchantFrameCloseButton")
    local token = ModernToken()
    local close = G("MerchantFrameCloseButton")
    if token and close then
      pcall(function()
        close:ClearAllPoints()
        close:SetWidth(token.close.size)
        close:SetHeight(token.close.size)
        close:SetHitRectInsets(0, 0, 0, 0)
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                       -token.close.right, -token.close.top)
      end)
      RaiseAboveModernChrome(close, 5)
    end
  end
end

local function Reapply()
  StripFrameChrome()
  if panel then panel:Show() end

  StyleHeader()
  StyleItemRows()
  StylePageControls()
  StyleMoneyFooter()
  StyleBuyBackSlot()
  RefreshLastBuybackSlot()
  StyleRepairButtons()
  BindBuybackRarity()
  ApplyModernWowDialog()
end

local function BuildFrame()
  frame = G("MerchantFrame")
  if not frame then
    U.Debug("merchant: native frame unavailable")
    return false
  end

  if useModernWow then
    local token = ModernToken()
    if not token then return false end
    pcall(function()
      frame:SetWidth(token.width)
      frame:SetHeight(token.height)
    end)
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
  if useModernWow then
    local art = ModernToken().art
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", art.left, -art.top)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -art.right, art.bottom)
  else
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 58)
  end
  pcall(panel.EnableMouse, panel, false)

  if useModernWow then
    local art = ModernToken().art
    pcall(frame.SetHitRectInsets, frame, art.left, art.right,
          art.top, art.bottom)
  else
    pcall(frame.SetHitRectInsets, frame, 10, 30, 10, 58)
  end

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  if not useModernWow then
    U.StyleStockCloseButton(G("MerchantFrameCloseButton"), panel, -6, -6)
  end
  U.MakeWindowDraggable("merchant", frame, { headerInset = 54 })

  StyleHeader()
  StyleTabs()
  StyleItemRows()
  StylePageControls()
  StyleMoneyFooter()
  StyleBuyBackSlot()
  StyleRepairButtons()
  BindBuybackRarity()
  ApplyModernWowDialog()

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  -- Mainline exposes the buyback icon as ItemButton.Icon rather than the
  -- legacy global. Repopulate the newest sale from GetBuybackItemInfo after
  -- native refresh, then repeat on the next driver tick so a later event
  -- handler cannot leave that content texture hidden again.
  U.PostHookGlobal("MerchantFrame_UpdateMerchantInfo", function()
    StyleItemRows()
    StylePageControls()
    RefreshLastBuybackSlot()
    ScheduleLastBuybackRefresh()
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
  -- callbacks remain active for every theme, including Classic's untouched
  -- NPC/service-window chrome.
  U.RegisterEvent("MERCHANT_SHOW", MerchantShown)
  U.RegisterEvent("MERCHANT_UPDATE", MerchantInventoryUpdated)
  U.RegisterEvent("BAG_UPDATE", RememberBagItemQualities)

  useModernWow = type(U.GetActiveThemeStyle) == "function" and
                 U.GetActiveThemeStyle() == "modern-wow"
  if U.ThemeStyleUsesNativeChrome() then return end
  if useModernWow and
     (type(U.ModernWowSurfaceEnabled) ~= "function" or
      not U.ModernWowSurfaceEnabled("merchant")) then
    return
  end
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("MERCHANT_SHOW", TryBuild)
end

function U.ModernWowMerchantActive()
  return useModernWow and frame and frame.uuiModernWowMerchant and true or false
end
