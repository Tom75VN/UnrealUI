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
-- Only the slot algorithm, the keyring/bag-slot recipe, the grey-item scan and
-- the visual placement of a Rogue Pick Lock shortcut are reused from
-- UnrealPfUI; none of its module framework, config schema, disenchant button
-- or panel system are reproduced. The shortcut's activation belongs to
-- modules/rogue.lua because this client protects direct CastSpell calls. The
-- bank is a separate unrealUI window (modules/bank.lua) built on the same
-- shared slot component (core/itemslot.lua).

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

-- Category view metrics (the optional grouped layout, off by default). A
-- category is a titled box holding the same COLUMNS-wide slot rhythm as the
-- flat grid, and the boxes stack downwards, so the window keeps one width and
-- only grows taller as categories appear.
local SECTION_TITLE  = 18   -- heading strip above each category box
local SECTION_TOGGLE = 16   -- the +/- collapse box in that strip
local SECTION_INSET  = 4    -- slot inset inside a category box
local SECTION_GAP    = 6    -- between one category box and the next heading

-- Centres the collapse box in its heading strip.
local SECTION_TOGGLE_Y = math.floor((SECTION_TITLE - SECTION_TOGGLE) / 2)

local anchor, frame, grid
local sections = {}     -- sections[categoryKey] = { box, title, toggle }
local slots = {}        -- slots[bag][slot] = button
local containers = {}   -- containers[bag] = per-bag parent frame, SetID(bag)

local layoutDirty = true
local bagDirty = {}
local cooldownDirty = false
local vendorDirty = false
local keyringDirty = false

local pending    -- { items, index, mode = "sell"|"delete", startGold }

-- Whole-module switch, so somebody running a third-party bag addon can hand the
-- container UI back to the client instead of fighting unrealUI for it. Read
-- once at OnEnable: with it off nothing here is built, the stock
-- ToggleBackpack/OpenAllBags globals are left alone and ContainerFrame1..5 are
-- never registered for native suppression, which is the only way the client
-- keeps its own bag windows. Turning it back on therefore needs a reload as
-- well -- core/compat.lua's suppression is one-way within a session (it
-- replaces Show without keeping the original), so the settings checkbox asks
-- for /reload in both directions rather than pretending either can be undone
-- live.
local config

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local function EnsureConfig()
  -- categories is the optional grouped view. It defaults off: the flat grid
  -- stays the shipped bag, and nothing about the window changes for a player
  -- who never opens the settings page.
  -- collapsed is keyed by category; only the collapsed ones are present, so the
  -- table stays empty until the player actually folds something away.
  if not config then
    config = U.ModuleConfig("bags",
                            { enabled = true, categories = false,
                              collapsed = {} })
  end
  return config
end

function U.BagsEnabled()
  return EnsureConfig().enabled and true or false
end

-- Classic keeps the merged UnrealUI container but paints it from the live
-- native ContainerFrame texture objects before those stock windows are
-- suppressed. No client asset path is guessed or bundled: the running client
-- supplies the exact background, close-button and slot-face textures.
local classicBag = {
  active = false,
  ready = false,
  nativeHeaderHeight = 58,
}

function classicBag.Dimension(region, method)
  local fn = region and region[method]
  if type(fn) ~= "function" then return 0 end
  local ok, value = pcall(fn, region)
  if not ok then return 0 end
  return tonumber(value) or 0
end

function classicBag.Face(regionName, ownerName)
  local region = U.G(regionName)
  if not region or type(region.GetTexture) ~= "function" then return nil end
  local ok, path = pcall(region.GetTexture, region)
  if not ok or type(path) ~= "string" or path == "" then return nil end

  local owner = U.G(ownerName)
  local ownerWidth = classicBag.Dimension(owner, "GetWidth")
  local ownerHeight = classicBag.Dimension(owner, "GetHeight")
  local width = classicBag.Dimension(region, "GetWidth")
  local height = classicBag.Dimension(region, "GetHeight")
  local face = {
    path = path,
    width = width,
    height = height,
    widthRatio = ownerWidth > 0 and width / ownerWidth or 1,
    heightRatio = ownerHeight > 0 and height / ownerHeight or 1,
  }

  -- GetTexture returns the atlas file, not the crop used by FrameXML. Copying
  -- only that path paints every component in the atlas (header, portrait and
  -- baked slot rows) over the unified bag. Preserve the native region's UV
  -- rectangle so every later slice starts from the client's own crop.
  if type(region.GetTexCoord) == "function" then
    local coordOk, a, b, c, d, e, f, g, h =
      pcall(region.GetTexCoord, region)
    if coordOk and type(a) == "number" and type(b) == "number" and
       type(c) == "number" and type(d) == "number" then
      face.cropped = true
      if type(e) == "number" and type(f) == "number" and
         type(g) == "number" and type(h) == "number" then
        face.left = math.min(a, c, e, g)
        face.right = math.max(a, c, e, g)
        face.top = math.min(b, d, f, h)
        face.bottom = math.max(b, d, f, h)
      else
        face.left, face.right, face.top, face.bottom = a, b, c, d
      end
    end
  end
  face.left = face.left or 0
  face.right = face.right or 1
  face.top = face.top or 0
  face.bottom = face.bottom or 1
  return face
end

function classicBag.Capture()
  classicBag.active = type(U.ThemeStyleUsesNativeChrome) == "function" and
                      U.ThemeStyleUsesNativeChrome() or false
  classicBag.ready = false
  if not classicBag.active then return end

  classicBag.backgroundTop = classicBag.Face(
    "ContainerFrame1BackgroundTop", "ContainerFrame1")
  classicBag.backgroundBottom = classicBag.Face(
    "ContainerFrame1BackgroundBottom", "ContainerFrame1")
  classicBag.background = classicBag.backgroundTop or classicBag.backgroundBottom
  classicBag.close = classicBag.Face(
    "ContainerFrame1CloseButtonNormalTexture", "ContainerFrame1CloseButton")
  classicBag.slot = classicBag.Face(
    "ContainerFrame1Item1NormalTexture", "ContainerFrame1Item1")
  classicBag.ready = classicBag.background and true or false

  if not classicBag.ready then
    U.Debug("Classic bag background texture is unavailable")
  end
end

function classicBag.HeaderHeight()
  -- Keep both themes on the shared compact container rhythm. The native bag
  -- art is scaled into this strip instead of making Classic reserve a second
  -- row above the item grid.
  return HEADER_HEIGHT
end

function classicBag.SlotGap()
  -- The native action-button rim extends beyond the clickable slot. Give
  -- Classic two extra pixels so adjacent rims remain visually distinct.
  if classicBag.ready then return SLOT_GAP + 2 end
  return SLOT_GAP
end

function classicBag.CreateFace(parent, face, layer)
  if not parent or not face then return nil end
  local texture = parent:CreateTexture(nil, layer or "OVERLAY")
  if not pcall(texture.SetTexture, texture, face.path) then return nil end
  texture.uuiClassicFace = face
  pcall(texture.SetTexCoord, texture,
        face.left, face.right, face.top, face.bottom)
  return texture
end

function classicBag.SetSlice(texture, x1, x2, y1, y2)
  local face = texture and texture.uuiClassicFace
  if not face then return end
  local left = face.left + (face.right - face.left) * (x1 or 0)
  local right = face.left + (face.right - face.left) * (x2 or 1)
  local top = face.top + (face.bottom - face.top) * (y1 or 0)
  local bottom = face.top + (face.bottom - face.top) * (y2 or 1)
  pcall(texture.SetTexCoord, texture, left, right, top, bottom)
end

function classicBag.SizeFace(texture, owner)
  local face = texture and texture.uuiClassicFace
  if not face or not owner then return end
  local width = classicBag.Dimension(owner, "GetWidth")
  local height = classicBag.Dimension(owner, "GetHeight")
  pcall(texture.ClearAllPoints, texture)
  pcall(texture.SetPoint, texture, "CENTER", owner, "CENTER", 0, 0)
  pcall(texture.SetWidth, texture, width * face.widthRatio)
  pcall(texture.SetHeight, texture, height * face.heightRatio)
end

function classicBag.StylePanel(panel, main)
  if not classicBag.ready or not panel then return end
  -- A unified bag has a variable width and row count, while the native art was
  -- authored for a fixed stock container. Use a flexible leather center and
  -- keep the captured atlas only in a three-piece header. Scale both caps with
  -- the compact header so their ornaments retain their native proportions;
  -- only the quiet middle band stretches with the merged window.
  U.SetBackdropShown(panel, true)
  U.SetBackgroundColor(panel, 0.115, 0.060, 0.018, 0.97)
  U.CreateBorder(panel, 2)
  U.SetBorderColor(panel, 0.48, 0.34, 0.13, 1)
  if not main then return end

  local source = classicBag.backgroundTop or classicBag.background
  -- If this client does not expose GetTexCoord, retain the flexible leather
  -- panel rather than ever falling back to the uncropped atlas again.
  if not source or not source.cropped then return end
  local left = classicBag.CreateFace(panel, source, "BORDER")
  local middle = classicBag.CreateFace(panel, source, "BORDER")
  local right = classicBag.CreateFace(panel, source, "BORDER")
  if not left or not middle or not right then return end
  local headerScale = classicBag.HeaderHeight() / classicBag.nativeHeaderHeight

  classicBag.SetSlice(left, 0, 0.40, 0, 1)
  left:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  left:SetWidth(82 * headerScale)
  left:SetHeight(classicBag.HeaderHeight())

  classicBag.SetSlice(right, 0.73, 1, 0, 1)
  right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  right:SetWidth(56 * headerScale)
  right:SetHeight(classicBag.HeaderHeight())

  classicBag.SetSlice(middle, 0.40, 0.73, 0, 1)
  middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
  middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
  panel.uuiClassicBackground = { left, middle, right }
end

function classicBag.StyleButton(button, face)
  if not classicBag.ready or not button or not face or not face.cropped then
    return
  end
  U.SetBackdropShown(button, false)
  if button.label then button.label:Hide() end
  local texture = classicBag.CreateFace(button, face, "OVERLAY")
  if texture then
    classicBag.SizeFace(texture, button)
    button.uuiClassicFace = texture
  end
end

function classicBag.StyleHeader(window)
  if not classicBag.ready or not window then return end

  local portrait = window:CreateTexture(nil, "OVERLAY")
  portrait:SetWidth(18)
  portrait:SetHeight(18)
  portrait:SetPoint("LEFT", window.sell, "RIGHT", 7, 0)
  local setPortrait = U.G("SetBagPortaitTexture")
  if type(setPortrait) == "function" then pcall(setPortrait, portrait, 0) end
  window.uuiClassicPortrait = portrait

  local title = U.CreateLabel(window, {
    text = U.L("BAGS_TITLE"),
    size = M.fontSize.normal,
    color = { 1.00, 0.82, 0.00, 1.00 },
    inherits = "GameFontNormal",
  })
  if title then
    title:SetPoint("LEFT", portrait, "RIGHT", 5, 0)
    window.uuiClassicTitle = title
  end
end

function classicBag.StyleIconButton(button)
  if not classicBag.ready or not classicBag.slot or
     not classicBag.slot.cropped or not button then return end
  U.SetBackdropShown(button, false)
  -- Below the button's own ARTWORK icon, for the reason CLASSIC_FACE_LAYER in
  -- modules/actionbar.lua records: this client's slot faces are not clear
  -- through the middle, so one painted over an icon dims it.
  local texture = classicBag.CreateFace(button, classicBag.slot, "BACKGROUND")
  if texture then
    classicBag.SizeFace(texture, button)
    button.uuiClassicFace = texture
  end
end

function classicBag.StyleItemSlot(button, size)
  if not classicBag.ready or
     type(U.StyleClassicActionButtonBorder) ~= "function" then return end
  -- No layer argument: the shared helper owns the one that keeps the item icon
  -- above the slot face.
  U.StyleClassicActionButtonBorder(button, size)
end

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
      -- Empty slots report texture "" and quality 0 on this client, which
      -- reads exactly like a grey item through the Vanilla-shaped test. The
      -- shared reader normalises the texture so only real items are queued.
      local texture, count, locked, quality = U.ContainerSlotInfo(bag, slot)
      if texture and quality == 0 and not locked then
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
      U.Print(U.L("BAGS_SOLD_GREYS",
                  FormatCopper(endGold - pending.startGold)))
    else
      local count = pending.index - 1
      U.Print(U.LN("BAGS_DELETED_GREYS", count))
    end

    pending = nil
    U.UnregisterUpdate("bags.sellDelete")
    vendorDirty = true
    return
  end

  pending.index = pending.index + 1

  -- Re-validate: bag contents can change while the queue drains.
  local texture, count, locked, quality =
    U.ContainerSlotInfo(item.bag, item.slot)
  if texture and quality == 0 and not locked then
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
    text = U.LN("BAGS_DELETE_CONFIRM", n),
    detail = U.L("COMMON_CANNOT_BE_UNDONE"),
    acceptText = U.L("COMMON_DELETE"),
    onAccept = function()
      pending = { items = items, index = 1, mode = "delete" }
      U.RegisterUpdate("bags.sellDelete", 0.15, ProcessPending)
    end,
  })
end

-- The run itself, once the item list is final. Split out from the entry point
-- below so the favourite confirmation can sit between the two: whichever list
-- the player settles on -- everything, or everything except their marked items
-- -- arrives here as an ordinary run.
local function RunGreyQueue(items, atVendor)
  if table.getn(items) == 0 then return end

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

local function SellOrDeleteGreys()
  if pending then return end

  local items = CollectGreyItems()
  if table.getn(items) == 0 then
    U.Print(U.L("BAGS_NO_GREYS"))
    return
  end

  local atVendor = false
  local merchant = U.G("MerchantFrame")
  if merchant then
    local ok, shown = pcall(merchant.IsShown, merchant)
    atVendor = ok and shown and true or false
  end

  -- A grey item can still be marked as a favourite, and this sweep is exactly
  -- the "by mistake" the mark exists to stop. modules/bagfavorites.lua asks
  -- once, for the whole run, and hands back the list to actually process; with
  -- nothing marked it hands the list straight back and nothing is asked.
  if type(U.ConfirmBagFavoriteBatch) == "function" then
    U.ConfirmBagFavoriteBatch(items, atVendor and "sell" or "delete",
      function(finalItems) RunGreyQueue(finalItems, atVendor) end)
    return
  end

  RunGreyQueue(items, atVendor)
end

local function RefreshVendorButton()
  if not frame or not frame.sell or not frame.sell.icon then return end
  local n = table.getn(CollectGreyItems())
  pcall(frame.sell.icon.SetDesaturated, frame.sell.icon, n == 0)
end

-- The sort button's disabled look while a run is draining, matching the way the
-- vendor button above reports that it has nothing to do. core/itemsort.lua
-- calls this again when the run ends, so nothing has to poll for it.
local function RefreshSortButton()
  if not frame or not frame.sortBags or not frame.sortBags.icon then return end
  pcall(frame.sortBags.icon.SetDesaturated, frame.sortBags.icon,
        U.BagSortActive())
end

local function SetSortButtonShown(shown)
  if not frame or not frame.sortBags then return end
  if shown then frame.sortBags:Show() else frame.sortBags:Hide() end
  RefreshSortButton()
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

  -- The category view anchors these buttons over category boxes that are
  -- siblings of this root under the same grid, so both would land on the
  -- parent's level + 1 and their draw order would be undefined. Lift the item
  -- roots clear of it once, here, rather than fighting it per box. Harmless in
  -- the flat grid, where nothing is drawn underneath the slots at all.
  local levelOk, level = pcall(parent.GetFrameLevel, parent)
  if levelOk and tonumber(level) then
    pcall(root.SetFrameLevel, root, level + 5)
  end

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

  -- Preserve the stock container handler exactly unless one of unrealUI's own
  -- chords claims the click. Passing the original argument shape through
  -- unchanged keeps both direct and legacy template handlers working.
  --
  -- Order matters: the Rogue poison helper is opt-in and only fires on a
  -- poison, so it is asked first and the favourite mark takes whatever
  -- Shift-click it did not want. Neither claims a click the other handled.
  local rogueClick = bag >= 0 and type(U.IsRogue) == "function" and U.IsRogue() and
                     type(U.TryRoguePoisonClick) == "function"
  local favoriteClick = type(U.TryBagFavoriteClick) == "function" and
                        type(U.BagFavoriteBag) == "function" and
                        U.BagFavoriteBag(bag)

  if rogueClick or favoriteClick then
    local stockClick = button:GetScript("OnClick")
    if type(stockClick) == "function" then
      button:SetScript("OnClick", function(a, b, c)
        if rogueClick and U.TryRoguePoisonClick(bag, slot, a, b) then return end
        if favoriteClick and U.TryBagFavoriteClick(bag, slot, a, b) then return end
        stockClick(a, b, c)
      end)
    end
  end

  -- The shortcut line under the tooltip. core/itemslot.lua already post-hooks
  -- this button for the rarity colour, the price panel and the equipped-item
  -- comparison; this hook is installed after those, so it runs last and the
  -- note can be hung under whatever they left on screen. It lives here rather
  -- than in the shared component because the mark is a carried-bag feature and
  -- the bank uses the same component.
  if favoriteClick then
    U.PostHookScript(button, "OnEnter", function()
      U.ShowBagFavoriteHint(bag, slot)
    end)
    U.PostHookScript(button, "OnLeave", function()
      U.HideBagFavoriteHint()
    end)
  end

  slots[bag][slot] = button
  return button
end

local function UpdateCooldown(bag, slot)
  U.UpdateItemSlotCooldown(bag, slots[bag] and slots[bag][slot])
end

local function UpdateSlotAppearance(bag, slot)
  local button = slots[bag] and slots[bag][slot]
  U.UpdateItemSlot(button, bag, slot)
  -- The single funnel every layout and refresh path already goes through, so
  -- the favourite star follows item movement, sorting and stack changes with
  -- nothing else to keep in step.
  if type(U.RefreshBagSlotFavorite) == "function" then
    U.RefreshBagSlotFavorite(button, bag, slot)
  end
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
  local slotGap = classicBag.SlotGap()
  local slot

  for slot = 1, n do
    local button = EnsureSlot(KEYRING_BAG, slot, tray)
    if button then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", tray, "TOPLEFT",
                      PADDING + shown * (TRAY_SLOT + slotGap), -PADDING)
      button:SetWidth(TRAY_SLOT)
      button:SetHeight(TRAY_SLOT)
      classicBag.StyleItemSlot(button, TRAY_SLOT)
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
    tray:SetWidth(shown * (TRAY_SLOT + slotGap) - slotGap + PADDING * 2)
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
-- The template's bag picture is native button artwork, which StyleItemSlot
-- deliberately removes with the rest of the stock chrome.  Populate its item
-- texture explicitly, just as modules/bank.lua does for equipped bank bags.
-- This also makes a newly equipped bag appear without recreating the tray.
local function HighlightBagSlots(bag, on)
  local bagSlots = bag and slots[bag]
  if not bagSlots then return end

  local slot
  for slot = 1, table.getn(bagSlots) do
    local item = bagSlots[slot]
    if item and item:IsShown() then
      if on then
        U.SetBorderColor(item, M.Unpack(M.color.accent))
      else
        UpdateSlotAppearance(bag, slot)
      end
    end
  end
end

local function RefreshBagSlotButton(button)
  if not button then return end

  local inventoryId = button.uuiInventoryId
  if not inventoryId then return end

  local texture
  local ok, value = pcall(GetInventoryItemTexture, "player", inventoryId)
  if ok then texture = value end

  pcall(SetItemButtonTexture, button, texture)
  U.SetBorderColor(button, M.Unpack(M.color.border))
end

local function RefreshBagSlotButtons()
  local tray = frame and frame.bagslots
  if not tray or not tray.buttons then return end

  local i
  for i = 1, BAG_SLOT_COUNT do RefreshBagSlotButton(tray.buttons[i]) end
end

-- Taking a bag back out of its slot.
--
-- The stock BagSlotButtonTemplate works out its own inventory id inside its
-- OnLoad, from the frame name and the XML id the client's own bag buttons are
-- declared with. A button created through CreateFrame has neither at load time,
-- so whatever that handler resolved was not this slot. The id is corrected with
-- SetID below, but nothing available here can confirm the template's click and
-- drag handlers read it back afterwards rather than something they kept from
-- OnLoad -- query_compat.py has no record of BagSlotButtonTemplate at all, and
-- the client ships no FrameXML to read.
--
-- Rather than guess at native template internals, the stock scripts are kept
-- and wrapped: they run first, and UnrealUI only steps in when the cursor shows
-- they moved nothing at all. PickupBagFromSlot is documented for this client
-- (OFFICIAL_CLIENT_DOCUMENTATION, Container) and takes exactly the inventory
-- slot 20-23 that ContainerIDToInventoryID returns, so the fallback rests on no
-- assumption the template does not already make, and it is inert wherever the
-- native path already does the work.
--
-- The fallback covers taking a bag *out* and nothing else, which is the one
-- direction where an empty cursor before and after is unambiguous proof that
-- nothing happened. Putting a bag in is deliberately left entirely native: a
-- swap into an occupied slot leaves a different bag on the cursor, so "the
-- cursor still holds something" cannot tell a completed swap from a handler
-- that did nothing, and a fallback firing there would undo the swap it just
-- misread.
--
-- Only a left click falls back. The stock right click opens the bag rather than
-- unequipping it, and that path deliberately reaches UnrealUI's own no-op
-- ToggleBag, which leaves the cursor untouched and would otherwise look exactly
-- like a handler that did nothing.
--
-- A bag that still holds items stays put either way: PickupBagFromSlot itself
-- declines an occupied bag, which is the client's rule and not something this
-- wrapper tries to work around.
local function WrapBagSlotPickup(button, script, inventoryId, leftOnly)
  local original = button:GetScript(script)

  button:SetScript(script, function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
    local hadItem = U.CursorHasItem()
    local mouseButton = U.MouseButton(a1, a2)

    if original then
      original(a1, a2, a3, a4, a5, a6, a7, a8, a9)
    end

    if hadItem or U.CursorHasItem() then return end
    if leftOnly and mouseButton and mouseButton ~= "LeftButton" then return end

    local pickup = U.G("PickupBagFromSlot")
    if type(pickup) == "function" then pcall(pickup, inventoryId) end
  end)
end

local function InstallBagSlotHandlers(button, inventoryId)
  if not button or button.uuiBagSlotFallback then return end
  button.uuiBagSlotFallback = true

  WrapBagSlotPickup(button, "OnClick", inventoryId, true)
  WrapBagSlotPickup(button, "OnDragStart", inventoryId, false)
end

local function LayoutBagSlots()
  if not frame or not frame.bagslots then return end

  local tray = frame.bagslots
  if tray.built then
    RefreshBagSlotButtons()
    return
  end
  tray.built = true
  tray.buttons = {}
  local slotGap = classicBag.SlotGap()

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
        button.uuiInventoryId = inventoryId
        InstallBagSlotHandlers(button, inventoryId)
      end
      button.slot = i

      -- The template registers these in its own OnLoad. Repeating them is
      -- idempotent and costs nothing, and it means a button whose OnLoad gave
      -- up early -- on the id it could not resolve for a CreateFrame'd frame --
      -- still receives the clicks and drags the wrappers above depend on.
      pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")
      pcall(button.RegisterForDrag, button, "LeftButton")

      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", tray, "TOPLEFT",
                      PADDING + (i - 1) * (TRAY_SLOT + slotGap), -PADDING)
      button:SetWidth(TRAY_SLOT)
      button:SetHeight(TRAY_SLOT)
      U.StyleItemSlot(button, name)
      U.UseBorderOnlyItemSlotHover(button)
      classicBag.StyleItemSlot(button, TRAY_SLOT)
      tray.buttons[i] = button
      RefreshBagSlotButton(button)
      U.PostHookScript(button, "OnEnter", function()
        U.SetBorderColor(button, M.Unpack(M.color.accentDim))
        HighlightBagSlots(button.slot, true)
      end)
      U.PostHookScript(button, "OnLeave", function()
        RefreshBagSlotButton(button)
        HighlightBagSlots(button.slot, false)
      end)
      button:Show()
    else
      U.Error("bags: BagSlotButtonTemplate unavailable; bag slot " .. i ..
              " not created")
    end
  end

  tray:SetWidth(BAG_SLOT_COUNT * (TRAY_SLOT + slotGap) - slotGap + PADDING * 2)
  tray:SetHeight(TRAY_SLOT + PADDING * 2)
end

-- ---------------------------------------------------------------------------
-- Category view
--
-- Optional stacked-section layout over the very same slot buttons the flat
-- grid uses: nothing is created, destroyed or re-parented when the view is
-- switched, the buttons are only re-anchored. Click, drag, tooltip, price,
-- comparison and cooldown behavior are therefore identical in both views, and
-- switching costs one relayout rather than a rebuild.
--
-- What an item *is* belongs to core/itemcategory.lua; this file only decides
-- where a category goes on screen.
-- ---------------------------------------------------------------------------
-- Forward declaration. The collapse handler is built in EnsureSection, above
-- the layout it has to re-run, and a fold should redraw on the click rather
-- than waiting up to a refresh tick for the dirty flag to be noticed.
local LayoutCategories

local function HideSection(section)
  if not section then return end
  if section.box then section.box:Hide() end
  if section.toggle then section.toggle:Hide() end
  if section.title then section.title:Hide() end
end

local function HideSections()
  local key, section
  for key, section in pairs(sections) do HideSection(section) end
end

local function ToggleSection(key, collapsed)
  -- Only collapsed categories are stored, so folding one back open removes its
  -- entry rather than leaving a false behind in SavedVariables.
  EnsureConfig().collapsed[key] = collapsed or nil
  LayoutCategories()
end

-- Used / total carried slots, shown in the header beside the money readout.
--
-- It belongs to the category view alone. The flat grid draws every free slot as
-- an empty square, so the same information is already on screen there and a
-- second copy of it would just be header noise; the category view draws no
-- empty squares at all, which is exactly why it needs the number.
--
-- Keyring slots are excluded on purpose: BAG_IDS is what the window shows, and
-- a keyring the player has not opened must not change a count that is meant to
-- describe the bags in front of them.
local function RefreshSlotCount(used, total)
  local label = frame and frame.slotCount
  if not label then return end

  if not used or not total then
    label:Hide()
    return
  end

  label:SetText(U.L("BAGS_SLOT_COUNT", used, total))
  label:Show()
end

-- A section is a heading row plus a box of slots. The heading is deliberately
-- *not* part of the box: a collapsed category keeps its title and its +/-
-- control on screen while the box goes away, and a region belonging to a hidden
-- frame cannot stay visible. All three are children of the grid instead.
local function EnsureSection(key, contentWidth)
  local section = sections[key]
  if section then return section end

  section = {}

  section.box = U.CreatePanel(grid, {
    name = "UnrealUIBagCategory_" .. key,
    width = contentWidth + SECTION_INSET * 2,
    height = SLOT_SIZE + SECTION_INSET * 2,
  })
  classicBag.StylePanel(section.box, false)
  -- Purely a backdrop for the slots anchored over it; it must not eat the
  -- clicks and drags those slots depend on.
  pcall(section.box.EnableMouse, section.box, false)

  -- The shared collapse control (U.CreateCollapseButton), not a local variant:
  -- same sharp box, same accent hover, same owned +/- glyph as every other
  -- collapsible header in the addon.
  section.toggle = U.CreateCollapseButton(grid, {
    size = SECTION_TOGGLE,
    collapsed = EnsureConfig().collapsed[key],
    onClick = function(collapsed) ToggleSection(key, collapsed) end,
  })

  section.title = U.CreateLabel(grid, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if section.title then section.title:SetText(U.ItemCategoryLabel(key)) end

  sections[key] = section
  return section
end

-- One pass over every carried slot, bucketed by category. Free slots are only
-- counted: they are not content, so they get no section and no button. The
-- header readout reports them instead, which is why the used and total counts
-- come back alongside the buckets.
local function CollectCategories()
  local buckets = {}
  local used, total = 0, 0
  local i

  -- The favourite section overrides whatever the item would otherwise be
  -- filed under, so a marked item is in one place and only one place. Resolved
  -- once per pass rather than per slot; nil when modules/bagfavorites.lua is
  -- not loaded, and the view then behaves exactly as it did before.
  local favoriteKey = nil
  if type(U.ItemCategoryFavorite) == "function" and
     type(U.IsBagSlotFavorite) == "function" then
    favoriteKey = U.ItemCategoryFavorite()
  end

  for i = 1, table.getn(BAG_IDS) do
    local bag = BAG_IDS[i]
    local ok, n = pcall(GetContainerNumSlots, bag)
    n = (ok and tonumber(n)) or 0

    local slot
    for slot = 1, n do
      total = total + 1

      local key = U.ItemCategoryForSlot(bag, slot)
      -- After the classification, not instead of it: an empty slot is still
      -- empty, and the mark is only ever asked about a slot that holds
      -- something.
      if key ~= "empty" and favoriteKey and U.IsBagSlotFavorite(bag, slot) then
        key = favoriteKey
      end
      if key ~= "empty" then
        used = used + 1
        if not buckets[key] then buckets[key] = {} end
        table.insert(buckets[key], { bag = bag, slot = slot })
      end
    end
  end

  return buckets, used, total
end

-- Assigns the local forward-declared above ToggleSection.
function LayoutCategories()
  local slotGap = classicBag.SlotGap()
  local contentWidth = COLUMNS * (SLOT_SIZE + slotGap) - slotGap
  local buckets, usedSlots, totalSlots = CollectCategories()
  local order = U.ItemCategoryOrder()
  local live = {}    -- every (bag, slot) this pass actually placed
  local drawn = {}   -- every category this pass actually drew
  local y = 0
  local i

  RefreshSlotCount(usedSlots, totalSlots)
  SetSortButtonShown(false)

  for i = 1, table.getn(order) do
    local key = order[i]
    local entries = buckets[key]

    local n = (entries and table.getn(entries)) or 0
    if n > 0 then
      local section = EnsureSection(key, contentWidth)
      local collapsed = EnsureConfig().collapsed[key] and true or false
      drawn[key] = true

      -- Heading row: the +/- control and the category name, on screen whether
      -- or not the box below them is.
      if section.toggle then
        section.toggle:ClearAllPoints()
        section.toggle:SetPoint("TOPLEFT", grid, "TOPLEFT", 0,
                                -(y + SECTION_TOGGLE_Y))
        section.toggle.uuiSetCollapsed(collapsed)
        section.toggle:Show()
      end
      if section.title then
        section.title:ClearAllPoints()
        if section.toggle then
          section.title:SetPoint("LEFT", section.toggle, "RIGHT", 4, 0)
        else
          section.title:SetPoint("TOPLEFT", grid, "TOPLEFT", 2, -y)
        end
        section.title:Show()
      end

      y = y + SECTION_TITLE

      if collapsed then
        -- The slots are simply not placed. Nothing marks them live, so the
        -- sweep at the end of this function is what takes them off screen.
        section.box:Hide()
      else
        local rows = math.ceil(n / COLUMNS)
        local height = SECTION_INSET * 2 + rows * (SLOT_SIZE + slotGap) - slotGap

        section.box:SetWidth(contentWidth + SECTION_INSET * 2)
        section.box:SetHeight(height)
        section.box:ClearAllPoints()
        section.box:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
        section.box:Show()

        local j
        for j = 1, n do
          local entry = entries[j]
          local button = EnsureSlot(entry.bag, entry.slot, grid)
          if button then
            local col = math.mod(j - 1, COLUMNS)
            local row = math.floor((j - 1) / COLUMNS)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", section.box, "TOPLEFT",
                            SECTION_INSET + col * (SLOT_SIZE + slotGap),
                            -(SECTION_INSET + row * (SLOT_SIZE + slotGap)))
            button:SetWidth(SLOT_SIZE)
            button:SetHeight(SLOT_SIZE)
            classicBag.StyleItemSlot(button, SLOT_SIZE)
            UpdateSlotAppearance(entry.bag, entry.slot)
            button:Show()
            live[entry.bag .. ":" .. entry.slot] = true
          end
        end

        y = y + height
      end

      y = y + SECTION_GAP
    end
  end

  if y > 0 then y = y - SECTION_GAP end

  -- Everything this pass did not place: every free slot, which the header
  -- readout accounts for instead, every slot inside a collapsed category, and
  -- any button left over from a bag since swapped for a smaller one.
  for i = 1, table.getn(BAG_IDS) do
    local bag = BAG_IDS[i]
    local bagSlots = slots[bag]
    if bagSlots then
      local slot
      for slot = 1, table.getn(bagSlots) do
        if bagSlots[slot] and not live[bag .. ":" .. slot] then
          bagSlots[slot]:Hide()
        end
      end
    end
  end

  local key, section
  for key, section in pairs(sections) do
    if not drawn[key] then HideSection(section) end
  end

  -- No bags at all (or none readable yet): keep one slot row of window rather
  -- than collapsing the frame onto its header.
  if y <= 0 then y = SLOT_SIZE end

  anchor:SetWidth(contentWidth + SECTION_INSET * 2 + PADDING * 2)
  anchor:SetHeight(classicBag.HeaderHeight() + y + PADDING)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local function LayoutSlots()
  local x, y = 0, 0
  local slotGap = classicBag.SlotGap()
  local i

  -- Switching back out of the category view leaves its boxes and its header
  -- readout behind otherwise; the slot buttons themselves are re-anchored below.
  HideSections()
  RefreshSlotCount(nil, nil)
  SetSortButtonShown(true)

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
                        x * (SLOT_SIZE + slotGap),
                        -(y * (SLOT_SIZE + slotGap)))
        button:SetWidth(SLOT_SIZE)
        button:SetHeight(SLOT_SIZE)
        classicBag.StyleItemSlot(button, SLOT_SIZE)
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
  -- stored placement keeps the same bounds whether or not the bag is open.
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + slotGap) - slotGap + PADDING * 2)
  anchor:SetHeight(classicBag.HeaderHeight() +
                   y * (SLOT_SIZE + slotGap) - slotGap
                   + PADDING)
end

local function ProcessDirty()
  if U.PerfDisabled and U.PerfDisabled("bags") then return end

  if layoutDirty then
    layoutDirty = false
    -- Read the setting per pass rather than latching it: toggling the category
    -- view only has to mark the layout dirty, and the next tick draws the other
    -- view over the same buttons. No reload, and no second code path to keep
    -- in step.
    if EnsureConfig().categories then
      LayoutCategories()
    else
      LayoutSlots()
    end
    if frame.keyring and frame.keyring:IsShown() then LayoutKeyring() end
    -- The bag-slot tray draws the equipped bags themselves, which change
    -- without any container's contents changing. It was only ever refreshed by
    -- reopening the tray, so a bag taken out of a slot went on being drawn in
    -- it. Redraw it whenever it is on screen.
    if frame.bagslots and frame.bagslots:IsShown() then
      RefreshBagSlotButtons()
    end
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

-- The same request from outside the module: modules/bagfavorites.lua marks an
-- item id, and every stack of it already on screen has to redraw. Through the
-- existing dirty flags rather than a direct redraw, so it costs one refresh
-- tick like every other bag change.
--
-- The layout flag as well as the per-bag ones: in the category view a mark
-- moves the item into (or out of) the favourites section, which only a full
-- relayout can do. In the flat grid the extra pass is the same idempotent
-- LayoutSlots the window already runs on any bag change.
function U.MarkBagsDirty()
  MarkAllBagsDirty()
  layoutDirty = true
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

-- The equipped-bag buttons use ToggleBag(container). Their contents are
-- already part of the merged window, so the individual toggle must not close
-- or reopen that window. This matches UnrealPfUI's working behavior on this
-- client while leaving backpack/all-bag controls responsible for the window.
local function IgnoreIndividualBagToggle()
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
  SetGlobal("ToggleBag", IgnoreIndividualBagToggle)
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
  classicBag.StylePanel(tray, false)
  pcall(tray.EnableMouse, tray, true)
  tray:Hide()
  return tray
end

local function RefreshRogueBagButton()
  if not frame or not frame.pickLock then return end

  local available = type(U.RogueHasPickLock) == "function" and
                    U.RogueHasPickLock()
  if available then frame.pickLock:Show() else frame.pickLock:Hide() end

  -- Collapse the header row when the skill has not been learned; hiding a
  -- frame does not move siblings anchored to it on this client.
  if frame.sell and frame.bagsToggle then
    frame.sell:ClearAllPoints()
    if available then
      frame.sell:SetPoint("LEFT", frame.pickLock, "RIGHT", 4, 0)
    else
      frame.sell:SetPoint("LEFT", frame.bagsToggle, "RIGHT", 4, 0)
    end
  end
end

U.RefreshRogueBagButton = RefreshRogueBagButton

local function BuildHeader()
  frame.close = U.CreateButton(frame, {
    name = "UnrealUIBagClose",
    text = "X",
    width = ICON_SIZE,
    height = ICON_SIZE,
    size = M.fontSize.small,
    onClick = function() HideBags() end,
  })
  if classicBag.ready and classicBag.close then
    classicBag.StyleButton(frame.close, classicBag.close)
  end
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)

  frame.money = BuildMoneyDisplay(frame)
  frame.money:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)

  -- Key / bag / sell-greys sit as a group at the header's left edge, separate
  -- from the money readout and close button on the right.
  frame.keyToggle = U.CreateIconButton(frame, {
    name = "UnrealUIBagKeyToggle",
    texture = "Interface\\Icons\\INV_Misc_Key_03",
    fallback = "K",
    title = U.L("BAGS_TOGGLE_KEYRING"),
    detail = function() return U.L("BAGS_KEYRING_HINT") end,
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
  classicBag.StyleIconButton(frame.keyToggle)
  frame.keyToggle:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

  frame.bagsToggle = U.CreateIconButton(frame, {
    name = "UnrealUIBagBagsToggle",
    texture = "Interface\\Icons\\INV_Misc_Bag_08",
    fallback = "B",
    title = U.L("BAGS_TOGGLE_BAGS"),
    detail = function() return U.L("BAGS_BAG_SLOTS_HINT") end,
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
  classicBag.StyleIconButton(frame.bagsToggle)
  frame.bagsToggle:SetPoint("LEFT", frame.keyToggle, "RIGHT", 4, 0)

  if type(U.IsRogue) == "function" and U.IsRogue() then
    frame.pickLock = U.CreateIconButton(frame, {
      name = "UnrealUIBagPickLock",
      texture = "Interface\\Icons\\Spell_Nature_MoonKey",
      fallback = "L",
      title = U.L("BAGS_PICK_LOCK"),
      detail = function()
        if type(U.RoguePickLockActionAvailable) == "function" and
           U.RoguePickLockActionAvailable() then
          return U.L("BAGS_PICK_LOCK_HINT")
        end
        return U.L("BAGS_PICK_LOCK_ACTION_HINT")
      end,
      onClick = function()
        if type(U.ActivateRoguePickLock) == "function" then
          U.ActivateRoguePickLock()
        end
      end,
    })
    classicBag.StyleIconButton(frame.pickLock)
    frame.pickLock:SetPoint("LEFT", frame.bagsToggle, "RIGHT", 4, 0)
  end

  frame.sell = U.CreateIconButton(frame, {
    name = "UnrealUIBagSell",
    texture = "Interface\\Icons\\INV_Misc_Coin_02",
    fallback = "$",
    title = U.L("BAGS_VENDOR_GRAYS"),
    onClick = SellOrDeleteGreys,
    detail = function() return U.L("BAGS_GREYS_HINT") end,
  })
  classicBag.StyleIconButton(frame.sell)
  frame.sell:SetPoint("LEFT", frame.bagsToggle, "RIGHT", 4, 0)

  -- Sort, last in the icon group. It belongs to the flat grid only: the
  -- category view already groups everything by the very order this sorts into,
  -- so rearranging the underlying slots there would move items around for no
  -- visible change. SetSortButtonShown drives that.
  frame.sortBags = U.CreateIconButton(frame, {
    name = "UnrealUIBagSort",
    texture = M.texture.sortIcon,
    fallback = "S",
    title = U.L("BAGS_SORT"),
    detail = function() return U.L("BAGS_SORT_HINT") end,
    -- U.SortBags owns every refusal message (already running, cursor holding
    -- something, nothing to do), so this only has to reflect the new state.
    onClick = function()
      if U.SortBags(BAG_IDS, { onFinish = RefreshSortButton, owner = "bags" })
      then
        RefreshSortButton()
      end
    end,
  })
  classicBag.StyleIconButton(frame.sortBags)
  frame.sortBags:SetPoint("LEFT", frame.sell, "RIGHT", 4, 0)
  frame.sortBags:Hide()

  -- Slot readout, left-aligned after the header icon group. Anchored to the
  -- sell button because that is the last icon in the group either way: the
  -- Rogue Pick Lock shortcut is inserted before it, and RefreshRogueBagButton
  -- re-anchors sell when the skill is missing, so following sell keeps the
  -- readout in place without repeating that rule. Hidden until the category
  -- view asks for it; see RefreshSlotCount.
  frame.slotCount = U.CreateLabel(frame, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if frame.slotCount then
    frame.slotCount:SetPoint("LEFT", frame.sell, "RIGHT", 8, 0)
    frame.slotCount:Hide()
  end

  RefreshRogueBagButton()
end

-- ---------------------------------------------------------------------------
-- Direct drag
--
-- The bag is not part of edit mode. It is placed by dragging its own header,
-- the way the rest of unrealUI's windows are moved -- core/windowdrag.lua for
-- the native ones, modules/bank.lua for the bank -- so it can be moved at any
-- time without unlocking the interface first.
--
-- The drag moves the anchor, the frame that owns the window rect, and saves to
-- "bags.main": the id the retired mover used, so a placement made before this
-- change is still the position the bag opens on.
--
-- Reuses the throwaway StartMoving/StopMovingOrSizing pair before the real
-- StartMoving that core/mover.lua, core/windowdrag.lua and modules/bank.lua
-- all use (knowledge.json / frames.movable_drag_requires_button_handle).
-- ---------------------------------------------------------------------------
local BAG_POSITION_ID = "bags.main"
local BAG_DEFAULT_POSITION = {
  point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -20, y = 20,
}

-- The window's height follows its contents -- a bag swapped for a bigger one
-- in the flat grid, and every category that appears or empties in the category
-- view. U.PinFrameToBottomEdge holds it by its bottom edge whatever corner a
-- drag left it on, so it extends upwards instead of pushing its lower rows off
-- the bottom of the screen. That is what the mover's anchorEdge option did for
-- it before, and it is the same implementation rather than a copy of it.
local function ApplyBagPosition()
  local saved = U.GetPosition(BAG_POSITION_ID)
  if not U.ApplyFramePoint(anchor, saved or BAG_DEFAULT_POSITION) then
    U.Debug("bags: failed to apply position")
    return false
  end
  U.PinFrameToBottomEdge(BAG_POSITION_ID, anchor, BAG_DEFAULT_POSITION)
  return true
end

local function StartBagDrag()
  if not pcall(anchor.SetMovable, anchor, true) then
    U.Error("bags: SetMovable failed; the bag cannot be moved")
    return
  end

  if pcall(anchor.StartMoving, anchor) then
    pcall(anchor.StopMovingOrSizing, anchor)
  end

  if not pcall(anchor.StartMoving, anchor) then
    U.Error("bags: StartMoving failed; the bag will not drag")
  end
end

local function StopBagDrag()
  pcall(anchor.StopMovingOrSizing, anchor)

  local point, _, relativePoint, x, y = U.GetFramePoint(anchor, 1)
  if not point then
    U.Debug("bags: no readable anchor after drag")
    return
  end
  if U.SavePosition(BAG_POSITION_ID, point, relativePoint, x, y) then
    U.PinFrameToBottomEdge(BAG_POSITION_ID, anchor, BAG_DEFAULT_POSITION)
  end
end

-- The grab strip runs from the header icon group to the close button. It is
-- anchored to the live edges of the buttons either side of it rather than to
-- computed offsets, so RefreshRogueBagButton re-anchoring the icon group when
-- the Pick Lock shortcut appears or goes moves the strip with it, without a
-- second copy of that rule. It spans the money readout, which is a plain
-- display frame that never enables mouse input, and stops short of the close
-- button so that click is not swallowed.
local function BuildDragHandle()
  local handle = CreateFrame("Button", "UnrealUIBagDrag", frame)
  handle:SetPoint("TOPLEFT", frame.sortBags, "TOPRIGHT", 4, 0)
  handle:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -4, 0)
  handle:SetHeight(classicBag.HeaderHeight() - PADDING)
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)

  handle:SetScript("OnDragStart", StartBagDrag)
  handle:SetScript("OnDragStop", StopBagDrag)

  frame.dragHandle = handle
  return handle
end

local function Build()
  -- The anchor owns the window rect and is never hidden, so the placement
  -- survives the bag being closed and reopened. The visible frame is its child
  -- and is stretched over it; the header drag strip moves the anchor, not the
  -- panel, so a drag cannot break that relationship.
  local slotGap = classicBag.SlotGap()
  anchor = CreateFrame("Frame", "UnrealUIBagAnchor", UIParent)
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + slotGap) - slotGap + PADDING * 2)
  anchor:SetHeight(classicBag.HeaderHeight() +
                   4 * (SLOT_SIZE + slotGap) - slotGap + PADDING)

  frame = U.CreatePanel(anchor, { name = "UnrealUIBagFrame" })
  frame:SetAllPoints(anchor)
  classicBag.StylePanel(frame, true)
  pcall(frame.SetFrameStrata, frame, "MEDIUM")
  pcall(frame.EnableMouse, frame, true)
  frame:Hide()

  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUIBagFrame")
  end

  BuildHeader()
  classicBag.StyleHeader(frame)
  BuildDragHandle()

  grid = CreateFrame("Frame", "UnrealUIBagGrid", frame)
  grid:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING,
                -classicBag.HeaderHeight())
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

  -- No mover: the bag is dragged directly by its header instead of being
  -- placed in edit mode, so the stored position -- or the default -- is
  -- applied here rather than by U.RegisterMover, and re-applied through the
  -- reset hook once /uui reset has cleared the store.
  pcall(anchor.SetMovable, anchor, true)
  ApplyBagPosition()
  U.OnPositionReset(ApplyBagPosition)

  -- Nothing on this client should be able to bring the native container
  -- windows back over unrealUI's frame. Uses the shared native-suppression
  -- adapter (core/compat.lua) rather than a new mechanism.
  U.SuppressNativeFrame({
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5",
  })
end

-- ---------------------------------------------------------------------------
-- Settings page
--
-- Registered from OnInit rather than OnEnable so the page exists even when the
-- module never enabled itself -- otherwise switching the bags back on would
-- need a hand-edited SavedVariables file.
-- ---------------------------------------------------------------------------
local function BuildSettingsPage(parent)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("BAGS_TITLE"),
    width = 484,
    y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsBagsEnable",
    text = U.L("SETTINGS_BAGS_ENABLE"),
    value = EnsureConfig().enabled,
    onChange = function(value)
      EnsureConfig().enabled = value and true or false
      U.ShowConfirm({
        owner = "bags.enable-reload",
        centered = true,
        text = U.L("SETTINGS_BAGS_CHANGED"),
        detail = value and U.L("SETTINGS_BAGS_RELOAD_ON")
                        or U.L("SETTINGS_BAGS_RELOAD_OFF"),
        acceptText = U.L("COMMON_OK_SHORT"),
        cancelText = U.L("COMMON_CLOSE"),
      })
    end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = 484,
  })
  if hint then
    U.AnchorSettingsDescription(hint, enable.box)
    hint:SetText(U.L("SETTINGS_BAGS_ENABLE_HINT"))
    table.insert(widgets, hint)
  end

  local categories = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsBagsCategories",
    text = U.L("SETTINGS_BAGS_CATEGORIES"),
    value = EnsureConfig().categories,
    onChange = function(value)
      EnsureConfig().categories = value and true or false
      -- Both views run on the same buttons, so the next refresh tick simply
      -- draws the other one. Nothing to reload and nothing to rebuild.
      layoutDirty = true
    end,
  })
  -- Anchored under the description above rather than at a computed offset: that
  -- text wraps to a different number of lines per language, and
  -- unreal-ui-design.md forbids giving it a fixed height to measure.
  if hint then
    categories.SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
  else
    categories.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -78)
  end
  table.insert(widgets, categories)

  local categoriesHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = 484,
  })
  if categoriesHint then
    U.AnchorSettingsDescription(categoriesHint, categories.box)
    categoriesHint:SetText(U.L("SETTINGS_BAGS_CATEGORIES_HINT"))
    table.insert(widgets, categoriesHint)
  end

  local function Refresh()
    enable.SetValue(EnsureConfig().enabled)
    categories.SetValue(EnsureConfig().categories)
  end

  return widgets, Refresh
end

function BG:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("bags", U.L("SETTINGS_PAGE_BAGS"), BuildSettingsPage)
  end
end

function BG:OnEnable()
  if frame then return end
  -- Off: no merged window, no toggle overrides and no ContainerFrame
  -- suppression, so the client's own bag windows keep working for whatever
  -- addon the player installed instead.
  if not EnsureConfig().enabled then return end

  InstallToggleOverrides()
  classicBag.Capture()
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
