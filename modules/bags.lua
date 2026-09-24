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
local HEADER_ICON   = M.slot.headerIcon
local TRAY_SLOT     = M.slot.tray   -- keyring / bag-slot button size

local anchor, frame, grid
local slots = {}        -- slots[bag][slot] = button
local containers = {}   -- containers[bag] = per-bag parent frame, SetID(bag)
-- The category view, shared with the bank (modules/bagcategoryview.lua).
local catView

local layoutDirty = true
local bagDirty = {}
local cooldownDirty = false
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
  -- table stays empty until the player actually folds something away. The
  -- bank window draws the same category view when `categories` is on, with
  -- its own folds in collapsedBank.
  if not config then
    config = U.ModuleConfig("bags",
                            { enabled = true, categories = false,
                              collapsed = {}, collapsedBank = {} })
  end
  return config
end

-- The persisted collapsed-category table of one window: "bank" for the bank,
-- anything else for the carried bags.
function U.BagsCategoryCollapsed(window)
  if window == "bank" then return EnsureConfig().collapsedBank end
  return EnsureConfig().collapsed
end

function U.BagsEnabled()
  return EnsureConfig().enabled and true or false
end

-- The two settings this module owns have two views each: the Bags page in the
-- settings window, and the panel on the bag bar's edit-mode anchor
-- (modules/bagbar.lua). Both go through these, so the reload prompt and the
-- redraw belong to the setting rather than being written out twice.
--
-- Turning the merged bag on or off is genuinely reload-bound: this module
-- overrides the client's bag globals and builds its window once, at enable.
-- The prompt is the setting's own behaviour, not the page's.
function U.SetBagsEnabled(value)
  value = value and true or false
  if EnsureConfig().enabled == value then return value end
  EnsureConfig().enabled = value

  U.ShowConfirm({
    owner = "bags.enable-reload",
    centered = true,
    text = U.L("SETTINGS_BAGS_CHANGED"),
    detail = value and U.L("SETTINGS_BAGS_RELOAD_ON")
                    or U.L("SETTINGS_BAGS_RELOAD_OFF"),
    acceptText = U.L("COMMON_OK_SHORT"),
    cancelText = U.L("COMMON_CLOSE"),
  })
  return value
end

function U.BagsCategoriesEnabled()
  return EnsureConfig().categories and true or false
end

function U.SetBagsCategories(value)
  EnsureConfig().categories = value and true or false
  -- Both views run on the same buttons, so the next refresh tick simply draws
  -- the other one. Nothing to reload and nothing to rebuild. The bank follows
  -- the same setting.
  layoutDirty = true
  if type(U.MarkBankLayoutDirty) == "function" then U.MarkBankLayoutDirty() end
  return U.BagsCategoriesEnabled()
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

local modernBag = {}

function modernBag.Active()
  return U.ModernWowBagFamilyActive()
end

local function BagHeaderHeight()
  return U.ModernWowBagMetric("header", HEADER_HEIGHT)
end

local function BagFooterHeight()
  if modernBag.Active() and M.modernWow and M.modernWow.bags then
    return M.modernWow.bags.footer
  end
  if modernBag.Flat() then return M.slot.footer end
  return 0
end

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
  -- Under classic-wow the shared bag design (modules/bagdesign.lua) replaces
  -- the native bag art when it is on, so none of it is captured.
  classicBag.active = type(U.ThemeStyleUsesNativeChrome) == "function" and
                      U.ThemeStyleUsesNativeChrome() and
                      not modernBag.Active() or false
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
  return U.ModernWowBagMetric("slotGap", SLOT_GAP)
end

-- Space between the header icons (key, bags, sell, sort, stack, bank).
function classicBag.IconGap()
  return U.ModernWowBagMetric("iconGap", 4)
end

-- Horizontal inset from the window edge to the item grid. Modern WoW adds a
-- few units so the grown slot faces clear the metal frame's side rails.
function classicBag.SidePad()
  return U.ModernWowBagMetric("sidePad", PADDING)
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
  local headerScale = BagHeaderHeight() / classicBag.nativeHeaderHeight

  classicBag.SetSlice(left, 0, 0.40, 0, 1)
  left:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  left:SetWidth(82 * headerScale)
  left:SetHeight(BagHeaderHeight())

  classicBag.SetSlice(right, 0.73, 1, 0, 1)
  right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  right:SetWidth(56 * headerScale)
  right:SetHeight(BagHeaderHeight())

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
  portrait:SetPoint("LEFT", window.stackBags or window.sell, "RIGHT", 7, 0)
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
  return U.StyleClassicActionButtonBorder(button, size)
end

function modernBag.StylePanel(panel)
  if not modernBag.Active() or not panel then return false end
  return U.ModernWowBagHousing(panel)
end

function modernBag.ResizePanel(panel)
  if not modernBag.Active() or not panel or
     type(U.ModernWowMetalFrame) ~= "function" then return end
  U.ModernWowMetalFrame(panel)
end

function modernBag.StyleItemSlot(button, size)
  if not modernBag.Active() then return false end
  return U.ModernWowBagSlot(button, size)
end

function modernBag.StyleHeader(window)
  if not modernBag.Active() or not window then return false end
  local token = M.modernWow.bags

  -- No title under Modern WoW (user request): the portrait names the window.
  U.ModernWowBagPortrait(window)
  U.ModernWowBagClose(window, "UnrealUIBagClose")

  if window.money then
    window.money:ClearAllPoints()
    window.money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT",
                          -token.money.right, token.money.bottom)
  end

  if window.keyToggle then
    window.keyToggle:ClearAllPoints()
    window.keyToggle:SetPoint("TOPLEFT", window, "TOPLEFT",
                              token.actions.left, -token.actions.top)
  end

  local controls = {
    window.keyToggle, window.bagsToggle, window.pickLock, window.sell,
    window.sortBags, window.stackBags, window.bankView,
  }
  local i
  for i = 1, table.getn(controls) do
    local control = controls[i]
    if control then U.ModernWowBagHeaderIcon(control, HEADER_ICON) end
  end

  if window.slotCount then
    window.slotCount:ClearAllPoints()
    window.slotCount:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT",
                              token.slotCount.left, token.slotCount.bottom)
  end

  U.ModernWowBagSeparator(window)
  return true
end

-- The `modern` flat window, decided once at Build like the bag design.
function modernBag.Flat()
  return not modernBag.Active() and type(U.GetActiveThemeStyle) == "function" and
         U.GetActiveThemeStyle() == "modern"
end

-- Under `modern` the money readout and the used-slot readout sit in a footer,
-- bottom right and bottom left, where the bag design puts them (user request,
-- 2026-09-24); the header's lane between the last icon and the close button
-- is the search field's. The footer's height is M.slot.footer.
function modernBag.StyleFlatFooter(window)
  if not modernBag.Flat() or not window then return end
  if window.money then
    window.money:ClearAllPoints()
    window.money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT",
                          -PADDING, PADDING)
  end
  if window.slotCount then
    window.slotCount:ClearAllPoints()
    -- On the money row's centre line.
    window.slotCount:SetPoint("LEFT", window, "BOTTOMLEFT", PADDING,
                              PADDING + 8)
  end
end

function U.ModernWowBagsActive()
  return modernBag.built and true or false
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

-- The sort and stack buttons' disabled look while a run is draining. Both
-- engines share the one cursor, so either run greys both buttons.
-- core/itemsort.lua and core/itemstack.lua call this again when the run ends,
-- so nothing has to poll for it.
local function RefreshSortButton()
  if not frame then return end
  local busy = U.BagSortActive() or U.BagStackActive()
  if frame.sortBags and frame.sortBags.icon then
    pcall(frame.sortBags.icon.SetDesaturated, frame.sortBags.icon, busy)
  end
  if frame.stackBags and frame.stackBags.icon then
    pcall(frame.stackBags.icon.SetDesaturated, frame.stackBags.icon, busy)
  end
end

-- The stack button stays in both views: merging frees slots whether or not the
-- grid is sorted. It sits after sort when sort is shown, and takes sort's
-- place when the category view hides it.
local function SetSortButtonShown(shown)
  if not frame or not frame.sortBags then return end
  if shown then frame.sortBags:Show() else frame.sortBags:Hide() end
  if frame.stackBags then
    frame.stackBags:ClearAllPoints()
    frame.stackBags:SetPoint("LEFT", shown and frame.sortBags or frame.sell,
                             "RIGHT", classicBag.IconGap(), 0)
  end
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
-- coin art and its colour come from core/media.lua's M.money: UnrealUI's own
-- per-denomination texture, the same one the status overlay draws, under
-- every theme.
-- ---------------------------------------------------------------------------
local COIN_GAP = 1

local function BuildCoin(parent, denom)
  local spec = M.money[denom]
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(14)
  holder:SetWidth(26)

  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(12)
  icon:SetHeight(12)
  -- The coin fills its own texture, so it centres on the holder and the
  -- number keeps the common text baseline; M.money.iconY lifts the icon only.
  icon:SetPoint("RIGHT", holder, "RIGHT", 0, M.money.iconY or 0)
  pcall(icon.SetTexture, icon, spec.texture)
  holder.icon = icon

  -- fonts.stretched_justification_ignored: anchored to the one edge it belongs
  -- to rather than stretched between two corners with a justify.
  holder.label = U.CreateLabel(holder, {
    size = M.fontSize.small,
    color = spec.color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then holder.label:SetPoint("RIGHT", holder, "RIGHT", -13, 0) end

  return holder
end

local function BuildMoneyDisplay(parent)
  local money = CreateFrame("Frame", "UnrealUIBagMoney", parent)
  money:SetHeight(16)
  money:SetWidth(150)

  money.copper = BuildCoin(money, "copper")
  money.silver = BuildCoin(money, "silver")
  money.gold   = BuildCoin(money, "gold")

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

-- Empty-slot proxy tracing, the same debug channel the shared category view
-- (modules/bagcategoryview.lua) writes its drop routing to.
local function DropTrace(message)
  U.Debug("bags empty-slot: " .. tostring(message))
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
  -- The two chords are distinct -- the Rogue poison helper is Shift-click and
  -- opt-in, the favourite mark is Alt-click -- so neither can claim a click
  -- the other wanted. The poison helper is still asked first, as the narrower
  -- of the two: it only fires on a poison.
  local rogueClick = bag >= 0 and type(U.IsRogue) == "function" and U.IsRogue() and
                     type(U.TryRoguePoisonClick) == "function"
  local favoriteClick = type(U.TryBagFavoriteClick) == "function" and
                        type(U.BagFavoriteBag) == "function" and
                        U.BagFavoriteBag(bag)

  local stockClick = button:GetScript("OnClick")
  if type(stockClick) == "function" then
    button:SetScript("OnClick", function(a1, a2, a3, a4, a5,
                                          a6, a7, a8, a9)
      if rogueClick and U.TryRoguePoisonClick(bag, slot, a1, a2) then return end
      if favoriteClick and U.TryBagFavoriteClick(bag, slot, a1, a2) then return end

      local source = U.BagCategoryDropSource(bag, slot)
      local mouseButton = U.MouseButton(a1, a2)
      if source and (not mouseButton or mouseButton == "LeftButton") then
        U.SetBagCategoryDropSource(source)
      end
      stockClick(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      if source and U.CursorHasItem() then U.SetBagCategoryDropSource(source) end
    end)
  end

  local stockDragStart = button:GetScript("OnDragStart")
  if type(stockDragStart) == "function" then
    button:SetScript("OnDragStart", function(a1, a2, a3, a4, a5,
                                              a6, a7, a8, a9)
      DropTrace("SOURCE OnDragStart fired")
      local source = U.BagCategoryDropSource(bag, slot)
      if source then U.SetBagCategoryDropSource(source) end
      stockDragStart(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local hasItem = U.CursorHasItem()
      DropTrace("CursorHasItem after source pickup=" .. tostring(hasItem))
      if source and hasItem then U.SetBagCategoryDropSource(source) end
    end)
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

-- ---------------------------------------------------------------------------
-- Header search (user request, 2026-09-24): the bag-family search field
-- (U.ModernWowBagSearch, modules/bagdesign.lua), fitted between the last
-- header icon -- the saved-bank button, which follows every show/hide rule of
-- the icons before it -- and the close cell. Under `modern` the same lane on
-- the flat header (U.FlatBagSearch; user requests, 2026-09-24), which the
-- money readout leaves for the footer (modernBag.StyleFlatFooter).
-- ---------------------------------------------------------------------------
local search = {}

function search.Build(window)
  if search.ctl or not window or not window.bankView then return end
  local spec = {
    window = window,
    name = "UnrealUIBagSearch",
    id = "bags.search",
    after = window.bankView,
    -- pairs, not table.getn: the category view builds no button for an empty
    -- slot, so a bag's slot table has holes and a counted walk stops at the
    -- first one, leaving every later item unshaded.
    each = function(paint)
      local bag, bagSlots
      for bag, bagSlots in pairs(slots) do
        local slot, button
        for slot, button in pairs(bagSlots) do
          paint(button, U.ContainerSlotLink(bag, slot))
        end
      end
    end,
  }
  search.ctl = U.ModernWowBagSearch(spec) or U.FlatBagSearch(spec)
  search.field = search.ctl and search.ctl.field
end

function search.Paint(button, link)
  if search.ctl then search.ctl.Paint(button, link) end
end

function search.Start()
  if search.ctl then search.ctl.Start() end
end

function search.Stop()
  if search.ctl then search.ctl.Stop() end
end

local function UpdateCooldown(bag, slot)
  U.UpdateItemSlotCooldown(bag, slots[bag] and slots[bag][slot])
end

-- Per-slot change detection. One item move fires ITEM_LOCK_CHANGED twice and
-- BAG_UPDATE once or twice, and every one of them used to rewrite every slot in
-- the window -- texture, count, quest lookup, border edges, favourite link and
-- cooldown -- which froze the client for a frame on each drag. Two container
-- reads now decide whether the slot can look any different; a pickup or drop
-- that only flips `locked` costs one desaturation write. InvalidateSlotCache
-- drops the cache when something outside the container data (a favourite
-- mark) changes what a slot draws.
local function UpdateSlotAppearance(bag, slot)
  local button = slots[bag] and slots[bag][slot]
  if not button then return end

  local texture, count, locked, quality = U.ContainerSlotInfo(bag, slot)
  local link = texture and U.ContainerSlotLink(bag, slot) or nil
  locked = locked and true or false

  if button.uuiSlotCached and button.uuiSlotLink == link and
     button.uuiSlotTexture == texture and button.uuiSlotCount == count and
     button.uuiSlotQuality == quality then
    if button.uuiSlotLocked ~= locked then
      button.uuiSlotLocked = locked
      pcall(SetItemButtonDesaturated, button, locked, 0.5, 0.5, 0.5)
    end
    return
  end

  U.UpdateItemSlot(button, bag, slot)
  -- The single funnel every layout and refresh path already goes through, so
  -- the favourite star follows item movement, sorting and stack changes with
  -- nothing else to keep in step.
  if type(U.RefreshBagSlotFavorite) == "function" then
    U.RefreshBagSlotFavorite(button, bag, slot)
  end

  button.uuiSlotCached = true
  button.uuiSlotLink, button.uuiSlotTexture = link, texture
  button.uuiSlotCount, button.uuiSlotQuality = count, quality
  button.uuiSlotLocked = locked

  -- A cache hit keeps the same item, so only a changed slot is re-matched.
  search.Paint(button, link)
end

local function InvalidateSlotCache()
  local bag, bagSlots
  for bag, bagSlots in pairs(slots) do
    local slot
    for slot = 1, table.getn(bagSlots) do
      if bagSlots[slot] then bagSlots[slot].uuiSlotCached = nil end
    end
  end
end

-- Anchor, size and slot-face styling only when they actually change. Both
-- layouts run on every bag change, so unchanged theme art is kept in place.
local function PlaceSlot(button, relative, x, y)
  if button.uuiPlacedTo ~= relative or button.uuiPlacedX ~= x or
     button.uuiPlacedY ~= y then
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", relative, "TOPLEFT", x, y)
    button.uuiPlacedTo, button.uuiPlacedX, button.uuiPlacedY = relative, x, y
  end
  if button.uuiPlacedSize ~= SLOT_SIZE then
    button:SetWidth(SLOT_SIZE)
    button:SetHeight(SLOT_SIZE)
    button.uuiPlacedSize = SLOT_SIZE
    button.uuiSlotStyled = nil
  end
  -- Retried until the selected theme face exists.
  if not button.uuiSlotStyled then
    if modernBag.Active() then
      button.uuiSlotStyled = modernBag.StyleItemSlot(button, SLOT_SIZE) and true
    else
      button.uuiSlotStyled = classicBag.StyleItemSlot(button, SLOT_SIZE) and true
                             or not classicBag.ready
    end
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
      modernBag.StyleItemSlot(button, TRAY_SLOT)
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
  modernBag.ResizePanel(tray)
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
        -- The accent border lives outside the per-slot cache, so an unchanged
        -- slot would otherwise short-circuit and keep the highlight.
        item.uuiSlotCached = nil
        UpdateSlotAppearance(bag, slot)
      end
    end
  end
end

local function RefreshBagSlotButton(button)
  if not button or not button.uuiInventoryId then return end
  U.RefreshBagSlotIcon(button)
  U.SetBorderColor(button, M.Unpack(M.color.border))
end

local function RefreshBagSlotButtons()
  local tray = frame and frame.bagslots
  if not tray or not tray.buttons then return end

  local i
  for i = 1, BAG_SLOT_COUNT do RefreshBagSlotButton(tray.buttons[i]) end
end

-- Creation, the corrected inventory id and the PickupBagFromSlot fallback for
-- these buttons all live in core/itemslot.lua (U.CreateBagSlotButton): the HUD
-- bag bar needs the identical button, and the evidence notes that justify the
-- fallback belong with the one implementation rather than with either caller.
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
    local button = U.CreateBagSlotButton(tray, name, i)
    if button then
      local bagClick = button:GetScript("OnClick")
      if type(bagClick) == "function" then
        button:SetScript("OnClick", function(a1, a2, a3, a4, a5,
                                              a6, a7, a8, a9)
          bagClick(a1, a2, a3, a4, a5, a6, a7, a8, a9)
          if U.CursorHasItem() then
            U.SetBagCategoryDropSource({
              category = "container",
              containerBag = button.slot,
            })
          end
        end)
      end

      local bagDragStart = button:GetScript("OnDragStart")
      if type(bagDragStart) == "function" then
        button:SetScript("OnDragStart", function(a1, a2, a3, a4, a5,
                                                  a6, a7, a8, a9)
          DropTrace("SOURCE OnDragStart fired")
          U.SetBagCategoryDropSource({
            category = "container",
            containerBag = button.slot,
          })
          bagDragStart(a1, a2, a3, a4, a5, a6, a7, a8, a9)
          local hasItem = U.CursorHasItem()
          DropTrace("CursorHasItem after source pickup=" ..
                          tostring(hasItem))
          if hasItem then
            U.SetBagCategoryDropSource({
              category = "container",
              containerBag = button.slot,
            })
          end
        end)
      end

      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", tray, "TOPLEFT",
                      PADDING + (i - 1) * (TRAY_SLOT + slotGap), -PADDING)
      button:SetWidth(TRAY_SLOT)
      button:SetHeight(TRAY_SLOT)
      U.StyleItemSlot(button, name)
      U.UseBorderOnlyItemSlotHover(button)
      classicBag.StyleItemSlot(button, TRAY_SLOT)
      modernBag.StyleItemSlot(button, TRAY_SLOT)
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
    end
  end

  tray:SetWidth(BAG_SLOT_COUNT * (TRAY_SLOT + slotGap) - slotGap + PADDING * 2)
  tray:SetHeight(TRAY_SLOT + PADDING * 2)
  modernBag.ResizePanel(tray)
end

-- ---------------------------------------------------------------------------
-- Category view
--
-- Optional stacked-section layout over the very same slot buttons the flat
-- grid uses. The layout, its sections and the empty-slot proxy are
-- modules/bagcategoryview.lua, shared with the bank window; this file keeps
-- only the window's side of it.
-- ---------------------------------------------------------------------------
-- Used / total carried slots, shown in the header beside the money readout.
--
-- It belongs to the category view alone. The flat grid draws every free slot as
-- an empty square, so the same information is already on screen there and a
-- second copy of it would just be header noise; the category view only draws
-- one empty slot as a drop target, which is why it needs the number.
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

-- The view itself is modules/bagcategoryview.lua, shared with the bank; this
-- window hands it its containers and slot buttons (see Build) and sizes
-- itself from the result in onLayout. The sort button goes: the view already
-- shows every category in sorted order.
local function LayoutCategories()
  SetSortButtonShown(false)
  catView.Layout()
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
  if catView then catView.Clear() end
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
        PlaceSlot(button, grid, x * (SLOT_SIZE + slotGap),
                  -(y * (SLOT_SIZE + slotGap)))
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
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + slotGap) - slotGap +
                  classicBag.SidePad() * 2)
  anchor:SetHeight(BagHeaderHeight() + BagFooterHeight() +
                   y * (SLOT_SIZE + slotGap) - slotGap
                   + PADDING)
  modernBag.ResizePanel(frame)
end

local function ProcessDirty()
  if U.PerfDisabled and U.PerfDisabled("bags") then return end
  -- Closed: leave the flags pending. OnShow forces a layout pass, which reads
  -- every slot again, so nothing drawn while hidden would survive anyway.
  if not frame:IsShown() then return end

  if layoutDirty then
    layoutDirty = false
    -- The layout below refreshes every slot it places, so the per-bag pass
    -- queued by the same events would only repeat it.
    local bag
    for bag, _ in pairs(bagDirty) do bagDirty[bag] = nil end
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
  InvalidateSlotCache()
  MarkAllBagsDirty()
  layoutDirty = true
end

local function RefreshAfterBagRun()
  U.MarkBagsDirty()
  RefreshSortButton()
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

-- The keyring tray, for a caller outside this window's own header. The HUD bag
-- bar (modules/bagbar.lua) stays on screen beside this window under
-- `modern-wow`, and its keyring control has no global to reach: this module
-- deliberately leaves ToggleKeyRing native and makes ToggleBag inert, so the
-- stock path would raise the client's KeyRingFrame over the merged bag. This is
-- the same toggle frame.keyToggle runs, exposed rather than duplicated.
function U.ToggleBagKeyring()
  if not frame or not frame.keyring then return false end

  local tray = frame.keyring
  local ok, shown = pcall(tray.IsShown, tray)
  if ok and shown then
    tray:Hide()
  else
    LayoutKeyring()
    tray:Show()
  end
  return true
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
  modernBag.StylePanel(tray)
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
      frame.sell:SetPoint("LEFT", frame.pickLock, "RIGHT", classicBag.IconGap(), 0)
    else
      frame.sell:SetPoint("LEFT", frame.bagsToggle, "RIGHT", classicBag.IconGap(), 0)
    end
  end
end

U.RefreshRogueBagButton = RefreshRogueBagButton

-- Header tooltips open above the bag window (U.ShowWindowTooltip), and above
-- the keyring or bag-slot tray when one is open on top of it.
local function BagTooltipFrames()
  return { frame, frame.keyring, frame.bagslots }
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
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.keyringIcon,
    fallback = "K",
    title = U.L("BAGS_TOGGLE_KEYRING"),
    detail = function() return U.L("BAGS_KEYRING_HINT") end,
    onClick = function() U.ToggleBagKeyring() end,
  })
  classicBag.StyleIconButton(frame.keyToggle)
  frame.keyToggle:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

  frame.bagsToggle = U.CreateIconButton(frame, {
    name = "UnrealUIBagBagsToggle",
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.bagIcon,
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
  frame.bagsToggle:SetPoint("LEFT", frame.keyToggle, "RIGHT", classicBag.IconGap(), 0)

  if type(U.IsRogue) == "function" and U.IsRogue() then
    frame.pickLock = U.CreateIconButton(frame, {
      name = "UnrealUIBagPickLock",
      tooltipFrames = BagTooltipFrames,
      size = HEADER_ICON,
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
    frame.pickLock:SetPoint("LEFT", frame.bagsToggle, "RIGHT", classicBag.IconGap(), 0)
  end

  frame.sell = U.CreateIconButton(frame, {
    name = "UnrealUIBagSell",
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.sellGreysIcon,
    fallback = "$",
    title = U.L("BAGS_VENDOR_GRAYS"),
    onClick = SellOrDeleteGreys,
    detail = function() return U.L("BAGS_GREYS_HINT") end,
  })
  classicBag.StyleIconButton(frame.sell)
  frame.sell:SetPoint("LEFT", frame.bagsToggle, "RIGHT", classicBag.IconGap(), 0)

  -- Sort, last in the icon group. It belongs to the flat grid only: the
  -- category view already groups everything by the very order this sorts into,
  -- so rearranging the underlying slots there would move items around for no
  -- visible change. SetSortButtonShown drives that.
  frame.sortBags = U.CreateIconButton(frame, {
    name = "UnrealUIBagSort",
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.sortIcon,
    fallback = "S",
    title = U.L("BAGS_SORT"),
    detail = function() return U.L("BAGS_SORT_HINT") end,
    -- U.SortBags owns every refusal message (already running, cursor holding
    -- something, nothing to do), so this only has to reflect the new state.
    onClick = function()
      if U.SortBags(BAG_IDS, { onFinish = RefreshAfterBagRun, owner = "bags" })
      then
        RefreshSortButton()
      end
    end,
  })
  classicBag.StyleIconButton(frame.sortBags)
  frame.sortBags:SetPoint("LEFT", frame.sell, "RIGHT", classicBag.IconGap(), 0)
  frame.sortBags:Hide()

  -- Merge partial stacks, carried bags only. SetSortButtonShown keeps it
  -- beside sort, or beside sell when the category view hides sort.
  frame.stackBags = U.CreateIconButton(frame, {
    name = "UnrealUIBagStack",
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.stackIcon,
    fallback = "M",
    title = U.L("BAGS_STACK"),
    detail = function() return U.L("BAGS_STACK_HINT") end,
    -- U.StackBags owns every refusal message, as U.SortBags does.
    onClick = function()
      if U.StackBags(BAG_IDS, { onFinish = RefreshAfterBagRun, owner = "bags" })
      then
        RefreshSortButton()
      end
    end,
  })
  classicBag.StyleIconButton(frame.stackBags)
  frame.stackBags:SetPoint("LEFT", frame.sell, "RIGHT", classicBag.IconGap(), 0)

  -- The saved bank (modules/bankview.lua): a read-only copy of the bank as it
  -- was last seen at a banker. Last in the icon group, after stack, so it
  -- follows stack wherever SetSortButtonShown puts it.
  frame.bankView = U.CreateIconButton(frame, {
    name = "UnrealUIBagBankView",
    tooltipFrames = BagTooltipFrames,
    size = HEADER_ICON,
    texture = M.texture.bankViewIcon,
    fallback = "V",
    title = U.L("BAGS_BANK_VIEW"),
    detail = function() return U.L("BAGS_BANK_VIEW_HINT") end,
    onClick = function()
      if type(U.ToggleBankView) == "function" then U.ToggleBankView() end
    end,
  })
  classicBag.StyleIconButton(frame.bankView)
  frame.bankView:SetPoint("LEFT", frame.stackBags, "RIGHT", classicBag.IconGap(), 0)

  -- Slot readout, left-aligned after the header icon group. Anchored to the
  -- saved-bank button because that is the last icon in the group either way:
  -- the Rogue Pick Lock shortcut is inserted before sell, RefreshRogueBagButton
  -- re-anchors sell when the skill is missing, stack follows sell or sort
  -- (SetSortButtonShown) and the saved-bank button follows stack, so following
  -- it keeps the readout in place without repeating either rule. Hidden until
  -- the category view asks for it; see RefreshSlotCount.
  frame.slotCount = U.CreateLabel(frame, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if frame.slotCount then
    frame.slotCount:SetPoint("LEFT", frame.bankView, "RIGHT", 8, 0)
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
    return
  end
  U.HoldScreenGuard(anchor, true)
end

local function StopBagDrag()
  pcall(anchor.StopMovingOrSizing, anchor)
  U.HoldScreenGuard(anchor, false)

  -- Edge-derived, not GetPoint offsets (U.GetFramePlacement explains the
  -- mirrored-Y readback).
  local p = U.GetFramePlacement(anchor)
  if not p then
    U.Debug("bags: no readable position after drag")
    return
  end
  if U.SavePosition(BAG_POSITION_ID, p.point, p.relativePoint, p.x, p.y) then
    U.PinFrameToBottomEdge(BAG_POSITION_ID, anchor, BAG_DEFAULT_POSITION)
  end
  U.CheckOnScreen(anchor)
end

-- The grab strip occupies header space without covering its controls.
local function BuildDragHandle()
  local handle = CreateFrame("Button", "UnrealUIBagDrag", frame)
  if modernBag.Active() and search.field then
    local token = M.modernWow.bags
    -- The search field fills the icon row between the last icon and the
    -- close button, so the strip is the rim above the row instead: the whole
    -- width up to the close cell, down to the close cell's top edge. The
    -- field (centred on the close cell) is levelled above it, so the edge it
    -- shares with the strip still takes its clicks.
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
                    -(token.close.right + token.close.width + 4), 0)
    handle:SetHeight(token.close.top)
  elseif modernBag.Active() then
    local token = M.modernWow.bags
    -- The icon row now shares the close button's line, so the strip starts
    -- after its last control (bank view) instead of covering the icons.
    handle:SetPoint("TOPLEFT", frame.bankView, "TOPRIGHT", 4, 0)
    handle:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -4, 0)
    handle:SetHeight(token.actions.height)
  else
    handle:SetPoint("TOPLEFT", frame.bankView, "TOPRIGHT", 4, 0)
    handle:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -4, 0)
    handle:SetHeight(HEADER_HEIGHT - PADDING)
  end
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
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + slotGap) - slotGap +
                  classicBag.SidePad() * 2)
  anchor:SetHeight(BagHeaderHeight() + BagFooterHeight() +
                   4 * (SLOT_SIZE + slotGap) - slotGap + PADDING)

  frame = U.CreatePanel(anchor, { name = "UnrealUIBagFrame" })
  frame:SetAllPoints(anchor)
  classicBag.StylePanel(frame, true)
  local modernPanel = modernBag.StylePanel(frame)
  -- Below every interface window (user request, 2026-09-21): LOW strata, and
  -- lifted inside it so the bag still draws over chat and the main bar.
  -- core/style.lua carries the measurement and the trade-off it gives up.
  U.LowerWindowBelowInterface(frame, 100)
  pcall(frame.EnableMouse, frame, true)
  frame:Hide()

  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUIBagFrame")
  end

  BuildHeader()
  classicBag.StyleHeader(frame)
  local modernHeader = modernBag.StyleHeader(frame)
  modernBag.StyleFlatFooter(frame)
  modernBag.built = modernPanel and modernHeader and true or false
  if modernHeader or not modernBag.Active() then search.Build(frame) end
  BuildDragHandle()

  grid = CreateFrame("Frame", "UnrealUIBagGrid", frame)
  grid:SetPoint("TOPLEFT", frame, "TOPLEFT", classicBag.SidePad(),
                -BagHeaderHeight())
  grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -classicBag.SidePad(),
                PADDING + BagFooterHeight())
  -- The shared category view over this window's containers and buttons.
  catView = U.CreateBagCategoryView({
    grid = grid,
    name = "UnrealUIBag",
    columns = COLUMNS,
    slotSize = SLOT_SIZE,
    slotGap = classicBag.SlotGap,
    bags = function() return BAG_IDS end,
    slotCount = function(bag)
      local ok, n = pcall(GetContainerNumSlots, bag)
      return (ok and tonumber(n)) or 0
    end,
    slots = slots,
    ensureSlot = function(bag, slot) return EnsureSlot(bag, slot, grid) end,
    placeSlot = PlaceSlot,
    updateSlot = UpdateSlotAppearance,
    collapsed = function() return EnsureConfig().collapsed end,
    favorites = true,
    styleBox = function(box) classicBag.StylePanel(box, false) end,
    onSlotCount = RefreshSlotCount,
    onDropped = function()
      if type(U.MarkBagsDirty) == "function" then U.MarkBagsDirty() end
    end,
    onLayout = function(width, height)
      anchor:SetWidth(width + classicBag.SidePad() * 2)
      anchor:SetHeight(BagHeaderHeight() + height + PADDING + BagFooterHeight())
      modernBag.ResizePanel(frame)
    end,
  })

  -- Trays sit above the frame: keyring on the left, bag slots on the right,
  -- matching the reference layout.
  frame.keyring = BuildTray("UnrealUIBagKeyring")
  frame.keyring:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, SLOT_GAP)

  frame.bagslots = BuildTray("UnrealUIBagSlots")
  frame.bagslots:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, SLOT_GAP)

  -- Cooldowns are not part of the slot cache, and BAG_UPDATE_COOLDOWN is not
  -- processed while the window is closed.
  frame:SetScript("OnShow", function()
    layoutDirty = true
    cooldownDirty = true
    search.Start()
  end)
  -- rendering.parent_alpha_not_propagated: the trays are toggled explicitly
  -- rather than left to follow the frame they hang off.
  frame:SetScript("OnHide", function()
    frame.keyring:Hide()
    frame.bagslots:Hide()
    search.Stop()
  end)

  -- No mover: the bag is dragged directly by its header instead of being
  -- placed in edit mode, so the stored position -- or the default -- is
  -- applied here rather than by U.RegisterMover, and re-applied through the
  -- reset hook once /uui reset has cleared the store.
  pcall(anchor.SetMovable, anchor, true)
  ApplyBagPosition()
  U.OnPositionReset(ApplyBagPosition)
  -- Its height follows the contents, so a full category view can outgrow the
  -- screen after a drop; core/screenguard.lua fits and clamps it while shown.
  U.GuardOnScreen(anchor, { id = BAG_POSITION_ID })

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
    value = U.BagsEnabled(),
    onChange = function(value) U.SetBagsEnabled(value) end,
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
    value = U.BagsCategoriesEnabled(),
    onChange = function(value) U.SetBagsCategories(value) end,
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

  -- The HUD bag bar (modules/bagbar.lua) stands in for this window while the
  -- module above is off -- and under modern-wow stays beside it while it is on
  -- -- so its one switch belongs on this page rather than on a tab of its own.
  -- It is shown always; the description says which themes and module states it
  -- actually appears in.
  --
  -- Unlike the module switch above it takes effect immediately, with no reload
  -- prompt: the bar builds itself the first time it is wanted and is shown or
  -- hidden after that. The same switch appears on the bar's own edit-mode
  -- anchor, and either view writes it.
  local bar = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsBagsHudBar",
    text = U.L("SETTINGS_BAGBAR_ENABLE"),
    value = U.BagBarEnabled and U.BagBarEnabled(),
    onChange = function(value)
      if type(U.SetBagBarEnabled) ~= "function" then return end
      U.SetBagBarEnabled(value)
    end,
  })
  if categoriesHint then
    bar.SetPoint("TOPLEFT", categoriesHint, "BOTTOMLEFT", 0, -12)
  else
    bar.SetPoint("TOPLEFT", categories.box, "BOTTOMLEFT", 0, -12)
  end
  table.insert(widgets, bar)

  local barHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = 484,
  })
  if barHint then
    U.AnchorSettingsDescription(barHint, bar.box)
    barHint:SetText(U.L("SETTINGS_BAGBAR_ENABLE_HINT"))
    table.insert(widgets, barHint)
  end

  local function Refresh()
    enable.SetValue(U.BagsEnabled())
    categories.SetValue(U.BagsCategoriesEnabled())
    if U.BagBarEnabled then bar.SetValue(U.BagBarEnabled()) end
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
  end)

  U.RegisterEvent("ITEM_LOCK_CHANGED", MarkAllBagsDirty)
  U.RegisterEvent("BAG_UPDATE_COOLDOWN", function() cooldownDirty = true end)
  U.RegisterEvent("PLAYER_MONEY", RefreshMoney)

  U.RegisterUpdate("bags.refresh", 0.2, ProcessDirty)

  RefreshMoney()
end
