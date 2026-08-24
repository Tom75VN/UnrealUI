-- unrealUI :: modules/bags.lua
--
-- A single merged bag frame (backpack + the four carried bag slots) replacing
-- the stock container windows, with a keyring row and a bag-slot row that each
-- toggle from the header, and a "Vendor / Delete Grays" action that sells
-- poor-quality items at an open vendor or asks to delete them otherwise.
--
-- knowledge.json / bags.container_api_contract_unverified is INCONCLUSIVE:
-- GetContainerNumSlots, GetContainerItemInfo, GetContainerItemLink and
-- UseContainerItem have no compact behavior record on this client, and
-- query_compat.py has no record at all for PickupContainerItem,
-- DeleteCursorItem, ContainerFrameItemButtonTemplate, BagSlotButtonTemplate,
-- SetItemButton*, ContainerFrame_UpdateCooldown, GetKeyRingSize,
-- ContainerIDToInventoryID, GetItemInfo, EditBox, GetMoney, or the
-- ToggleBackpack/OpenBackpack/OpenAllBags/CloseAllBags globals either. Per the
-- UnrealPfUI evidence-gap fallback, every one of those defaults to what
-- UnrealPfUI/modules/bags.lua and UnrealPfUI/modules/autovendor.lua
-- demonstrably do on this same client -- WORKING_SOURCE only, never runtime
-- verified. Feed anything measured in game back into knowledge.json.
--
-- Only the slot algorithm, the keyring/bag-slot recipe and the grey-item scan
-- are reused from UnrealPfUI; none of its module framework, config schema,
-- disenchant/picklock buttons or panel system are reproduced. The bank is a
-- separate unrealUI window (modules/bank.lua) built on the same shared slot
-- component (core/itemslot.lua).

local U = UnrealUI
local M = U.media

local BG = U.RegisterModule("bags")

-- Global writes go through core/init.lua's U.SetG, which resolves setglobal vs
-- `_G` once. U.PostHookGlobal is the second caller, so the setter now lives
-- with U.G instead of local to this module.
local SetGlobal = U.SetG

local BAG_IDS = { 0, 1, 2, 3, 4 }   -- backpack + the four carried bag slots
local KEYRING_BAG = -2
local BAG_SLOT_COUNT = 4            -- the four swappable equipped bag slots

-- Metrics are the shared container tokens (core/media.lua M.slot) so the bag
-- and bank windows cannot drift apart; only the row length is per-window.
local COLUMNS       = 10
local SLOT_SIZE     = M.slot.size
local SLOT_GAP      = M.slot.gap
local PADDING       = M.slot.padding
local HEADER_HEIGHT = M.slot.header
local ICON_SIZE     = M.slot.icon
local TRAY_SLOT     = M.slot.tray   -- keyring / bag-slot button size

local anchor, frame, grid
local slots = {}        -- slots[bag][slot] = button
local containers = {}   -- containers[bag] = per-bag parent frame, SetID(bag)

local layoutDirty = true
local bagDirty = {}
local cooldownDirty = false
local vendorDirty = false
local keyringDirty = false

local pending    -- { items, index, mode = "sell"|"delete", startGold }

-- ---------------------------------------------------------------------------
-- Grey-item scan, shared by the tooltip, the button state and the action.
-- ---------------------------------------------------------------------------
local function CollectGreyItems()
  local list = {}
  local i

  for i = 1, table.getn(BAG_IDS) do
    local bag = BAG_IDS[i]
    local ok, n = pcall(GetContainerNumSlots, bag)
    n = (ok and tonumber(n)) or 0

    local slot
    for slot = 1, n do
      local infoOk, texture, count, locked, quality =
        pcall(GetContainerItemInfo, bag, slot)
      if infoOk and texture and quality == 0 and not locked then
        table.insert(list, { bag = bag, slot = slot })
      end
    end
  end

  return list
end

local function FormatCopper(amount)
  amount = tonumber(amount) or 0
  if amount < 0 then amount = 0 end
  return math.floor(amount / 10000) .. "g " ..
         math.floor(math.mod(amount, 10000) / 100) .. "s " ..
         math.mod(amount, 100) .. "c"
end

-- ---------------------------------------------------------------------------
-- Sell (at an open vendor) / delete (everywhere else) queue.
--
-- One item per shared-driver tick rather than a tight loop: these calls drive
-- the cursor, and UnrealPfUI's autovendor.lua -- the only working reference for
-- this on this client -- throttles the same way.
-- ---------------------------------------------------------------------------
local function ProcessPending()
  if not pending then
    U.UnregisterUpdate("bags.sellDelete")
    return
  end

  local item = pending.items[pending.index]
  if not item then
    if pending.mode == "sell" then
      local ok, endGold = pcall(GetMoney)
      endGold = (ok and tonumber(endGold)) or pending.startGold
      U.Print("Sold grey items for " ..
              FormatCopper(endGold - pending.startGold) .. ".")
    else
      local count = pending.index - 1
      local plural = (count == 1 and "" or "s")
      U.Print("Deleted " .. count .. " grey item" .. plural .. ".")
    end

    pending = nil
    U.UnregisterUpdate("bags.sellDelete")
    vendorDirty = true
    return
  end

  pending.index = pending.index + 1

  -- Re-validate: bag contents can change while the queue drains.
  local ok, texture, count, locked, quality =
    pcall(GetContainerItemInfo, item.bag, item.slot)
  if ok and texture and quality == 0 and not locked then
    pcall(ClearCursor)
    if pending.mode == "sell" then
      pcall(UseContainerItem, item.bag, item.slot)
    else
      pcall(PickupContainerItem, item.bag, item.slot)
      pcall(DeleteCursorItem)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Delete confirmation
--
-- The shared modal from core/widgets.lua (U.ShowConfirm); this module owned a
-- private copy of it until the bank needed the same dialog.
-- ---------------------------------------------------------------------------
local function ShowDeleteConfirm(items)
  local n = table.getn(items)

  U.ShowConfirm({
    text = "Delete " .. n .. " grey item" .. (n == 1 and "" or "s") .. "?",
    detail = "This cannot be undone.",
    acceptText = "Delete",
    onAccept = function()
      pending = { items = items, index = 1, mode = "delete" }
      U.RegisterUpdate("bags.sellDelete", 0.15, ProcessPending)
    end,
  })
end

local function SellOrDeleteGreys()
  if pending then return end

  local items = CollectGreyItems()
  if table.getn(items) == 0 then
    U.Print("No grey items found.")
    return
  end

  local atVendor = false
  local merchant = U.G("MerchantFrame")
  if merchant then
    local ok, shown = pcall(merchant.IsShown, merchant)
    atVendor = ok and shown and true or false
  end

  if atVendor then
    local goldOk, goldNow = pcall(GetMoney)
    pending = {
      items = items,
      index = 1,
      mode = "sell",
      startGold = (goldOk and tonumber(goldNow)) or 0,
    }
    U.RegisterUpdate("bags.sellDelete", 0.15, ProcessPending)
  else
    ShowDeleteConfirm(items)
  end
end

local function RefreshVendorButton()
  if not frame or not frame.sell or not frame.sell.icon then return end
  local n = table.getn(CollectGreyItems())
  pcall(frame.sell.icon.SetDesaturated, frame.sell.icon, n == 0)
end

-- ---------------------------------------------------------------------------
-- Header icon buttons -- U.CreateIconButton (core/widgets.lua) now owns this;
-- this module used to keep a private copy until modules/bank.lua needed the
-- identical recipe for its purchase control.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Money display
--
-- Number then coin, gold to copper left-to-right, laid out right-to-left so
-- the whole readout keeps its right edge fixed as the amounts change. The
-- coin icon is the single UI-MoneyIcons atlas sliced with texture
-- coordinates -- the same recipe modules/status.lua uses for the status
-- overlay's coin readout, which is USER_CONFIRMED_INGAME to render. The
-- separate per-denomination icon files this used to reference did not.
-- ---------------------------------------------------------------------------
local MONEY_TEXTURE = "Interface\\MoneyFrame\\UI-MoneyIcons"
local COIN_GOLD   = { 0.00, 0.25, 0, 1 }
local COIN_SILVER = { 0.25, 0.50, 0, 1 }
local COIN_COPPER = { 0.50, 0.75, 0, 1 }
local COIN_GAP = 1

local function BuildCoin(parent, texCoords, color)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(14)
  holder:SetWidth(26)

  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(12)
  icon:SetHeight(12)
  -- The coin artwork sits low inside the atlas slice. Raise only the texture
  -- while keeping the number on the common text baseline.
  icon:SetPoint("RIGHT", holder, "RIGHT", 0, 2)
  pcall(icon.SetTexture, icon, MONEY_TEXTURE)
  pcall(icon.SetTexCoord, icon,
        texCoords[1], texCoords[2], texCoords[3], texCoords[4])
  holder.icon = icon

  -- fonts.stretched_justification_ignored: anchored to the one edge it belongs
  -- to rather than stretched between two corners with a justify.
  holder.label = U.CreateLabel(holder, {
    size = M.fontSize.small,
    color = color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then holder.label:SetPoint("RIGHT", icon, "LEFT", -1, -2) end

  return holder
end

local function BuildMoneyDisplay(parent)
  local money = CreateFrame("Frame", "UnrealUIBagMoney", parent)
  money:SetHeight(16)
  money:SetWidth(150)

  money.copper = BuildCoin(money, COIN_COPPER, { 0.80, 0.47, 0.29 })
  money.silver = BuildCoin(money, COIN_SILVER, { 0.75, 0.75, 0.75 })
  money.gold   = BuildCoin(money, COIN_GOLD, { 1.00, 0.82, 0.00 })

  money.copper:SetPoint("RIGHT", money, "RIGHT", 0, 0)
  money.silver:SetPoint("RIGHT", money.copper, "LEFT", -COIN_GAP, 0)
  money.gold:SetPoint("RIGHT", money.silver, "LEFT", -COIN_GAP, 0)

  return money
end

-- Sizes a coin holder to its rendered amount instead of a reserved width --
-- matching modules/status.lua's SetCoinValue -- so the fixed 44-wide frames
-- this used to leave behind an oversized gap in front of each icon.
local function SetCoinValue(coin, value)
  if not coin or not coin.label then return end
  coin.label:SetText(value)

  local ok, textWidth = pcall(coin.label.GetStringWidth, coin.label)
  textWidth = (ok and tonumber(textWidth)) or (string.len(value) * 7)
  coin.contentWidth = math.ceil(textWidth) + 13
  coin:SetWidth(coin.contentWidth)
end

local function RefreshMoney()
  if not frame or not frame.money then return end

  local ok, total = pcall(GetMoney)
  total = (ok and tonumber(total)) or 0

  local money = frame.money
  SetCoinValue(money.gold, tostring(math.floor(total / 10000)))
  SetCoinValue(money.silver, tostring(math.floor(math.mod(total, 10000) / 100)))
  SetCoinValue(money.copper, tostring(math.mod(total, 100)))
end

-- ---------------------------------------------------------------------------
-- Item slots
--
-- WORKING_SOURCE fallback from UnrealPfUI/modules/bags.lua: a plain per-bag
-- Frame carries SetID(bag), each slot button is the stock
-- ContainerFrameItemButtonTemplate with SetID(slot), and the template's own
-- OnClick/OnDrag/OnEnter scripts are left untouched -- click, pickup and
-- tooltip are whatever those do with the (parent bag, own slot) identity.
--
-- The stock art is stripped the way pfUI strips it: the button's own
-- NormalTexture is the white slot ring, so it is cleared through the named
-- region as well as the setter (rendering.native_texture_strip_requires_alpha
-- says a native region can survive Hide() and SetTexture alone).
-- ---------------------------------------------------------------------------
local function EnsureBagRoot(bag, parent)
  if containers[bag] then return containers[bag] end

  local root = CreateFrame("Frame", nil, parent)
  root:SetID(bag)
  root:SetAllPoints(parent)
  containers[bag] = root
  slots[bag] = slots[bag] or {}
  return root
end

local function EnsureSlot(bag, slot, parent)
  slots[bag] = slots[bag] or {}
  if slots[bag][slot] then return slots[bag][slot] end

  local root = EnsureBagRoot(bag, parent)
  local name = "UnrealUIBagSlot" .. (bag < 0 and ("m" .. -bag) or bag) .. "_" .. slot

  local button = U.CreateItemSlot(root, name, bag, slot)
  if not button then return nil end

  slots[bag][slot] = button
  return button
end

local function UpdateCooldown(bag, slot)
  U.UpdateItemSlotCooldown(bag, slots[bag] and slots[bag][slot])
end

local function UpdateSlotAppearance(bag, slot)
  U.UpdateItemSlot(slots[bag] and slots[bag][slot], bag, slot)
end

local function RefreshBag(bag)
  local bagSlots = slots[bag]
  if not bagSlots then return end

  local slot
  for slot = 1, table.getn(bagSlots) do
    if bagSlots[slot] and bagSlots[slot]:IsShown() then
      UpdateSlotAppearance(bag, slot)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Keyring tray
--
-- Bag -2, sized with GetKeyRingSize where the client provides it. Its own
-- panel above the bag frame's top-left corner rather than appended to the main
-- grid, so toggling it never reflows the item layout.
-- ---------------------------------------------------------------------------
local function KeyringSize()
  local ok, n = pcall(GetKeyRingSize)
  if ok and tonumber(n) and n > 0 then return n end

  ok, n = pcall(GetContainerNumSlots, KEYRING_BAG)
  if ok and tonumber(n) then return n end
  return 0
end

local function LayoutKeyring()
  if not frame or not frame.keyring then return end

  local tray = frame.keyring
  local n = KeyringSize()
  local shown = 0
  local slot

  for slot = 1, n do
    local button = EnsureSlot(KEYRING_BAG, slot, tray)
    if button then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", tray, "TOPLEFT",
                      PADDING + shown * (TRAY_SLOT + SLOT_GAP), -PADDING)
      button:SetWidth(TRAY_SLOT)
      button:SetHeight(TRAY_SLOT)
      UpdateSlotAppearance(KEYRING_BAG, slot)
      button:Show()
      shown = shown + 1
    end
  end

  local stale = slots[KEYRING_BAG]
  if stale then
    for slot = n + 1, table.getn(stale) do
      if stale[slot] then stale[slot]:Hide() end
    end
  end

  if shown == 0 then
    tray:SetWidth(TRAY_SLOT + PADDING * 2)
  else
    tray:SetWidth(shown * (TRAY_SLOT + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  end
  tray:SetHeight(TRAY_SLOT + PADDING * 2)
end

-- ---------------------------------------------------------------------------
-- Bag-slot tray
--
-- The four swappable equipped bag slots, so a bag can be dragged in or out
-- without the stock bag bar. WORKING_SOURCE recipe from UnrealPfUI's
-- CreateBagSlots: a CheckButton on BagSlotButtonTemplate, styled the same way
-- as an item slot. Unlike pfUI this also calls SetID with the inventory id the
-- stock template derives its bag from, since pfUI leaves it at the default.
-- ---------------------------------------------------------------------------
local function LayoutBagSlots()
  if not frame or not frame.bagslots then return end

  local tray = frame.bagslots
  if tray.built then return end
  tray.built = true

  local i
  for i = 1, BAG_SLOT_COUNT do
    local name = "UnrealUIBagBagSlot" .. i
    local ok, button = pcall(CreateFrame, "CheckButton", name, tray,
                             "BagSlotButtonTemplate")
    if ok and button then
      -- Container id i maps to the inventory slot the stock template reads.
      local idOk, inventoryId = pcall(ContainerIDToInventoryID, i)
      if idOk and tonumber(inventoryId) then
        pcall(button.SetID, button, inventoryId)
      end
      button.slot = i

      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", tray, "TOPLEFT",
                      PADDING + (i - 1) * (TRAY_SLOT + SLOT_GAP), -PADDING)
      button:SetWidth(TRAY_SLOT)
      button:SetHeight(TRAY_SLOT)
      U.StyleItemSlot(button, name)
      button:Show()
    else
      U.Error("bags: BagSlotButtonTemplate unavailable; bag slot " .. i ..
              " not created")
    end
  end

  tray:SetWidth(BAG_SLOT_COUNT * (TRAY_SLOT + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  tray:SetHeight(TRAY_SLOT + PADDING * 2)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local function LayoutSlots()
  local x, y = 0, 0
  local i

  for i = 1, table.getn(BAG_IDS) do
    local bag = BAG_IDS[i]
    local ok, n = pcall(GetContainerNumSlots, bag)
    n = (ok and tonumber(n)) or 0

    local slot
    for slot = 1, n do
      local button = EnsureSlot(bag, slot, grid)
      if button then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", grid, "TOPLEFT",
                        x * (SLOT_SIZE + SLOT_GAP),
                        -(y * (SLOT_SIZE + SLOT_GAP)))
        button:SetWidth(SLOT_SIZE)
        button:SetHeight(SLOT_SIZE)
        UpdateSlotAppearance(bag, slot)
        button:Show()

        if x >= COLUMNS - 1 then
          x, y = 0, y + 1
        else
          x = x + 1
        end
      end
    end

    -- A bag swapped for a smaller one leaves stale buttons past its new size.
    local bagSlots = slots[bag]
    if bagSlots then
      local stale
      for stale = n + 1, table.getn(bagSlots) do
        if bagSlots[stale] then bagSlots[stale]:Hide() end
      end
    end
  end

  if x > 0 then y = y + 1 end
  if y == 0 then y = 1 end

  -- The anchor owns the rect; the visible frame is stretched over it, so the
  -- mover handle keeps the same bounds whether or not the bag is open.
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  anchor:SetHeight(HEADER_HEIGHT + y * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
                   + PADDING)
end

local function ProcessDirty()
  if U.PerfDisabled and U.PerfDisabled("bags") then return end

  if layoutDirty then
    layoutDirty = false
    LayoutSlots()
    if frame.keyring and frame.keyring:IsShown() then LayoutKeyring() end
  end

  if keyringDirty then
    keyringDirty = false
    if frame.keyring and frame.keyring:IsShown() then LayoutKeyring() end
  end

  local bag
  for bag, _ in pairs(bagDirty) do
    bagDirty[bag] = nil
    RefreshBag(bag)
  end

  if cooldownDirty then
    cooldownDirty = false
    local i
    for i = 1, table.getn(BAG_IDS) do
      local bagId = BAG_IDS[i]
      local bagSlots = slots[bagId]
      if bagSlots then
        local slot
        for slot = 1, table.getn(bagSlots) do UpdateCooldown(bagId, slot) end
      end
    end
  end

  if vendorDirty then
    vendorDirty = false
    RefreshVendorButton()
  end
end

local function MarkAllBagsDirty()
  local i
  for i = 1, table.getn(BAG_IDS) do bagDirty[BAG_IDS[i]] = true end
  keyringDirty = true
end

-- ---------------------------------------------------------------------------
-- Show / hide / toggle
-- ---------------------------------------------------------------------------
local function ShowBags()
  if frame then frame:Show() end
end

local function HideBags()
  if frame then frame:Hide() end
end

local function ToggleBags()
  if not frame then return end
  local ok, shown = pcall(frame.IsShown, frame)
  if ok and shown then HideBags() else ShowBags() end
end

-- Deliberate, one-time override of the stock backpack entry points: opening
-- bags has to land on unrealUI's merged frame instead of the native
-- ContainerFrame windows. Reproduces UnrealPfUI's demonstrated approach
-- (modules/bags.lua) for this client rather than guessing independently.
local function InstallToggleOverrides()
  if U.uuiBagTogglesOverridden then return end
  U.uuiBagTogglesOverridden = true

  SetGlobal("ToggleBackpack", ToggleBags)
  SetGlobal("OpenBackpack", ShowBags)
  SetGlobal("OpenAllBags", ToggleBags)
  SetGlobal("CloseAllBags", HideBags)
  SetGlobal("ToggleAllBags", ToggleBags)
  SetGlobal("ToggleBag", ToggleBags)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildTray(name)
  local tray = U.CreatePanel(frame, {
    name = name,
    width = TRAY_SLOT + PADDING * 2,
    height = TRAY_SLOT + PADDING * 2,
  })
  pcall(tray.EnableMouse, tray, true)
  tray:Hide()
  return tray
end

local function BuildHeader()
  frame.close = U.CreateButton(frame, {
    name = "UnrealUIBagClose",
    text = "X",
    width = ICON_SIZE,
    height = ICON_SIZE,
    size = M.fontSize.small,
    onClick = function() HideBags() end,
  })
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)

  frame.money = BuildMoneyDisplay(frame)
  frame.money:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)

  -- Key / bag / sell-greys sit as a group at the header's left edge, separate
  -- from the money readout and close button on the right.
  frame.keyToggle = U.CreateIconButton(frame, {
    name = "UnrealUIBagKeyToggle",
    texture = "Interface\\Icons\\INV_Misc_Key_03",
    fallback = "K",
    title = "Toggle Keyring",
    detail = function() return "Show the keyring." end,
    onClick = function()
      local tray = frame.keyring
      local ok, shown = pcall(tray.IsShown, tray)
      if ok and shown then
        tray:Hide()
      else
        LayoutKeyring()
        tray:Show()
      end
    end,
  })
  frame.keyToggle:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

  frame.bagsToggle = U.CreateIconButton(frame, {
    name = "UnrealUIBagBagsToggle",
    texture = "Interface\\Icons\\INV_Misc_Bag_08",
    fallback = "B",
    title = "Toggle Bags",
    detail = function() return "Show the equipped bag slots." end,
    onClick = function()
      local tray = frame.bagslots
      local ok, shown = pcall(tray.IsShown, tray)
      if ok and shown then
        tray:Hide()
      else
        LayoutBagSlots()
        tray:Show()
      end
    end,
  })
  frame.bagsToggle:SetPoint("LEFT", frame.keyToggle, "RIGHT", 4, 0)

  frame.sell = U.CreateIconButton(frame, {
    name = "UnrealUIBagSell",
    texture = "Interface\\Icons\\INV_Misc_Coin_02",
    fallback = "$",
    title = "Vendor / Delete Grays",
    onClick = SellOrDeleteGreys,
    detail = function()
      return "Sells grey items at an open vendor; otherwise asks to delete them."
    end,
  })
  frame.sell:SetPoint("LEFT", frame.bagsToggle, "RIGHT", 4, 0)
end

local function Build()
  -- The anchor is the mover target and is never hidden, so edit mode can place
  -- the bag with the bag itself closed. The visible frame is its child and is
  -- stretched over it, which also keeps the drag handle (created at the
  -- anchor's frame level + 10, see core/mover.lua) above the bag's own chrome.
  anchor = CreateFrame("Frame", "UnrealUIBagAnchor", UIParent)
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  anchor:SetHeight(HEADER_HEIGHT + 4 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PADDING)

  frame = U.CreatePanel(anchor, { name = "UnrealUIBagFrame" })
  frame:SetAllPoints(anchor)
  pcall(frame.SetFrameStrata, frame, "MEDIUM")
  pcall(frame.EnableMouse, frame, true)
  frame:Hide()

  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUIBagFrame")
  end

  BuildHeader()

  grid = CreateFrame("Frame", "UnrealUIBagGrid", frame)
  grid:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
  grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)

  -- Trays sit above the frame: keyring on the left, bag slots on the right,
  -- matching the reference layout.
  frame.keyring = BuildTray("UnrealUIBagKeyring")
  frame.keyring:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, SLOT_GAP)

  frame.bagslots = BuildTray("UnrealUIBagSlots")
  frame.bagslots:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, SLOT_GAP)

  frame:SetScript("OnShow", function() layoutDirty = true end)
  -- rendering.parent_alpha_not_propagated: the trays are toggled explicitly
  -- rather than left to follow the frame they hang off.
  frame:SetScript("OnHide", function()
    frame.keyring:Hide()
    frame.bagslots:Hide()
  end)

  U.RegisterMover("bags.main", anchor, {
    label = "Bags",
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
                x = -20, y = 20 },
  })

  -- Nothing on this client should be able to bring the native container
  -- windows back over unrealUI's frame. Uses the shared native-suppression
  -- adapter (core/compat.lua) rather than a new mechanism.
  U.SuppressNativeFrame({
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5",
  })
end

function BG:OnEnable()
  if frame then return end

  InstallToggleOverrides()
  Build()

  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() layoutDirty = true end)

  U.RegisterEvent("BAG_UPDATE", function(event, bag)
    layoutDirty = true
    bag = tonumber(bag)
    if bag then bagDirty[bag] = true end
    if bag == KEYRING_BAG then keyringDirty = true end
    vendorDirty = true
  end)

  U.RegisterEvent("ITEM_LOCK_CHANGED", MarkAllBagsDirty)
  U.RegisterEvent("BAG_UPDATE_COOLDOWN", function() cooldownDirty = true end)
  U.RegisterEvent("PLAYER_MONEY", RefreshMoney)
  U.RegisterEvent("MERCHANT_SHOW", function() vendorDirty = true end)
  U.RegisterEvent("MERCHANT_CLOSED", function() vendorDirty = true end)

  U.RegisterUpdate("bags.refresh", 0.2, ProcessDirty)

  RefreshMoney()
  RefreshVendorButton()
end
