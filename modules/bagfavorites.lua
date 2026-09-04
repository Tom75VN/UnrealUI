-- unrealUI :: modules/bagfavorites.lua
--
-- "Favourite" marks on bag items, so an item a player cares about cannot be
-- vendored by a reflex right-click or swept up by the bag window's grey-item
-- run.
--
-- Scope, deliberately narrow: the player's own carried containers (backpack
-- plus the four equipped bags). The keyring and every bank container are left
-- alone -- this is a guard against selling, and neither of those is a surface
-- items are sold from.
--
-- Marks are stored per item id, not per (bag, slot). Bags are reordered by
-- core/itemsort.lua, by the client, and by the player, so a coordinate is not
-- a stable identity for anything; an id is. The visible consequence is that
-- marking one stack marks every stack of that item, which is what "do not sell
-- this" means in practice.
--
-- Every client call in here is a guarded read of an API that has no compact
-- behavior record on this client (see core/itemslot.lua's header for the same
-- statement about the container API), so nothing is called directly and no
-- result is trusted.

local U = UnrealUI
local FAV = U.RegisterModule("bagfavorites")

local DB_NAME = "UnrealUIFavoriteDB"
local DB_VERSION = 1

-- The carried containers this feature covers. Kept here rather than imported
-- from modules/bags.lua so the guard cannot silently widen if that window's
-- own BAG_IDS ever grows to cover a surface that is not a carried bag.
local FAVORITE_BAGS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }

local store        -- { version, items = { [itemId] = true } }

-- ---------------------------------------------------------------------------
-- Store
--
-- Its own SavedVariable, per character, for the same reason modules/
-- itemprice.lua keeps one: this is marked game data with free-form numeric
-- keys, not a setting, and core/config.lua validates a small fixed schema
-- against a profile that several characters may share. A favourite is a
-- decision about one character's bags.
--
-- Only numbers and booleans are persisted, so knowledge.json /
-- config.savedvariables_backslash_corruption cannot reach it.
--
-- Loaded lazily rather than from OnEnable, so nothing depends on this module
-- being enabled before modules/bags.lua draws its first slot.
-- ---------------------------------------------------------------------------
local function EnsureStore()
  if store then return store end

  local db = U.G(DB_NAME)
  if type(db) ~= "table" then
    U.SetG(DB_NAME, { version = DB_VERSION })
    db = U.G(DB_NAME)
    -- A rejected global write leaves a session-only table: marks stop
    -- surviving a reload, but the protection still works this session.
    if type(db) ~= "table" then db = { version = DB_VERSION } end
  end

  db.version = DB_VERSION
  if type(db.items) ~= "table" then db.items = {} end

  -- A corrupted or hand-edited saved file must not be able to put a mark on
  -- something that is not an item id.
  local key, value
  for key, value in pairs(db.items) do
    if type(key) ~= "number" or key <= 0 or value ~= true then
      db.items[key] = nil
    end
  end

  store = db
  return store
end

-- ---------------------------------------------------------------------------
-- Item identity
-- ---------------------------------------------------------------------------
local function LinkID(link)
  if type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

function U.BagFavoriteBag(bag)
  return FAVORITE_BAGS[tonumber(bag) or -99] and true or false
end

-- The item id in a carried bag slot, or nil for an empty slot, an unreadable
-- link, or any container this feature does not cover.
function U.BagSlotItemID(bag, slot)
  if not U.BagFavoriteBag(bag) then return nil end

  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if not ok then return nil end
  return LinkID(link)
end

function U.IsFavoriteItemID(id)
  id = tonumber(id)
  if not id then return false end
  return EnsureStore().items[id] and true or false
end

function U.IsBagSlotFavorite(bag, slot)
  return U.IsFavoriteItemID(U.BagSlotItemID(bag, slot))
end

-- ---------------------------------------------------------------------------
-- Marking
-- ---------------------------------------------------------------------------
local function ItemLink(bag, slot)
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if ok and type(link) == "string" and link ~= "" then return link end
  return nil
end

function U.ToggleBagSlotFavorite(bag, slot)
  local id = U.BagSlotItemID(bag, slot)
  if not id then return false end

  local items = EnsureStore().items
  if items[id] then items[id] = nil else items[id] = true end

  -- Every other stack of the same item has to pick the change up too, so the
  -- redraw is asked for across the window rather than on the clicked button.
  if type(U.MarkBagsDirty) == "function" then U.MarkBagsDirty() end

  -- The tooltip is still open on the item that was just clicked, and its
  -- shortcut line now says the wrong thing.
  U.ShowBagFavoriteHint(bag, slot)
  return true
end

-- Driven from modules/bags.lua's single slot-refresh funnel.
function U.RefreshBagSlotFavorite(button, bag, slot)
  if not button then return end
  U.SetItemSlotFavorite(button, U.IsBagSlotFavorite(bag, slot))
end

-- ---------------------------------------------------------------------------
-- Tooltip shortcut line
--
-- Hung under whatever is currently the bottom of the hover stack: the price
-- panel when modules/itemprice.lua put one up, the tooltip itself when it did
-- not (no known sell price, or a vendor open and the client drawing its own
-- money line). Either way the note ends up directly below the sell price and
-- the pieces read as one column. The Classic theme grows the tooltip itself to
-- hold its price row, so anchoring under the tooltip is still under the price.
-- ---------------------------------------------------------------------------
function U.ShowBagFavoriteHint(bag, slot)
  local id = U.BagSlotItemID(bag, slot)
  if not id then
    U.HideTooltipNote()
    return
  end

  local tooltip = U.G("GameTooltip")
  if not tooltip or type(tooltip.IsShown) ~= "function" then return end

  local shownOk, shown = pcall(tooltip.IsShown, tooltip)
  if not shownOk or not shown then
    U.HideTooltipNote()
    return
  end

  local key = U.IsFavoriteItemID(id) and "BAGS_FAVORITE_HINT_REMOVE"
                                     or "BAGS_FAVORITE_HINT_ADD"
  U.ShowTooltipNote(U.MoneyRowsFrame() or tooltip, U.L(key), tooltip)
end

function U.HideBagFavoriteHint()
  U.HideTooltipNote()
end

-- ---------------------------------------------------------------------------
-- Selling a marked item
-- ---------------------------------------------------------------------------
local function MerchantShown()
  local merchant = U.G("MerchantFrame")
  if not merchant or type(merchant.IsShown) ~= "function" then return false end
  local ok, shown = pcall(merchant.IsShown, merchant)
  return ok and shown and true or false
end

-- UseContainerItem is the client's own right-click action for a bag slot and
-- is what sells it at an open vendor (documentation.json /
-- global:Container:UseContainerItem, DOCUMENTED_NOT_RUNTIME_VERIFIED). The
-- cursor is cleared first, exactly as modules/bags.lua's grey-item queue does
-- before each of its own sales.
local function SellSlot(bag, slot)
  pcall(ClearCursor)
  pcall(UseContainerItem, bag, slot)
end

local function ConfirmSell(bag, slot)
  U.ShowConfirm({
    owner = "bagfavorites",
    text = U.L("BAGS_FAVORITE_SELL_CONFIRM"),
    detail = ItemLink(bag, slot) or "",
    acceptText = U.L("BAGS_FAVORITE_SELL_ACCEPT"),
    onAccept = function()
      -- Re-checked on accept rather than trusted from the click: a dialog can
      -- sit open while the bag changes underneath it, and the slot that was a
      -- favourite may now hold something else entirely.
      if U.IsBagSlotFavorite(bag, slot) and MerchantShown() then
        SellSlot(bag, slot)
      end
    end,
  })
end

-- The bag window's grey-item run reaches the same protection through here, so
-- the sale of a marked item goes through one confirmation path however it was
-- started. `items` is the full run; the caller receives back the list it
-- should actually process.
--
-- Accept includes the marked items, Cancel leaves them in the bags and the run
-- continues with the rest -- so cancelling protects the favourites instead of
-- abandoning the whole sweep.
function U.ConfirmBagFavoriteBatch(items, mode, onReady)
  local plain, marked = {}, {}
  local i

  for i = 1, table.getn(items) do
    local item = items[i]
    if U.IsBagSlotFavorite(item.bag, item.slot) then
      table.insert(marked, item)
    else
      table.insert(plain, item)
    end
  end

  local total = table.getn(marked)
  if total == 0 then
    onReady(items)
    return
  end

  local key = (mode == "sell") and "BAGS_FAVORITE_BATCH_SELL"
                               or "BAGS_FAVORITE_BATCH_DELETE"

  U.ShowConfirm({
    owner = "bagfavorites",
    text = U.LN(key, total),
    detail = U.L("BAGS_FAVORITE_BATCH_DETAIL"),
    acceptText = U.L("BAGS_FAVORITE_BATCH_INCLUDE"),
    cancelText = U.L("BAGS_FAVORITE_BATCH_SKIP"),
    onAccept = function() onReady(items) end,
    onCancel = function()
      if table.getn(plain) == 0 then
        U.Print(U.L("BAGS_FAVORITE_BATCH_NONE_LEFT"))
        return
      end
      onReady(plain)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Click chord
--
-- Called from modules/bags.lua's slot OnClick wrapper before the stock
-- container handler. Returning true claims the click and the stock handler is
-- not run.
--
-- Shift + Left Click toggles the mark. It yields in the two cases where the
-- client's own meaning for that chord must win: an open chat edit box, where
-- Shift-click is how an item is linked into chat, and a loaded cursor, where
-- the click is about to place what is being carried.
--
-- LIMIT, stated rather than left to be found: on a stack of more than one this
-- chord is also the client's stack-split gesture, and the mark takes it over.
-- Splitting a stack by Shift-clicking a bag slot is therefore not available
-- while this is installed.
--
-- Right Click at an open vendor is the sale this whole feature exists to
-- catch, so a marked item routes through the confirmation instead. Away from a
-- vendor the same click uses/equips/opens the item and is left alone.
-- ---------------------------------------------------------------------------
function U.TryBagFavoriteClick(bag, slot, a, b)
  if not U.BagFavoriteBag(bag) then return false end

  local click = U.ClickButtonName(a, b)
  if not click then return false end

  if click == "LeftButton" then
    local shiftOk, shift = pcall(IsShiftKeyDown)
    if not shiftOk or not shift then return false end
    if U.ChatEditBoxActive() or U.CursorBusy() then return false end
    return U.ToggleBagSlotFavorite(bag, slot)
  end

  if click == "RightButton" then
    if U.CursorBusy() or not MerchantShown() then return false end
    if not U.IsBagSlotFavorite(bag, slot) then return false end
    ConfirmSell(bag, slot)
    return true
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Bootstrap
-- ---------------------------------------------------------------------------
function FAV:OnEnable()
  EnsureStore()

  -- The shortcut line belongs to one hover. modules/itemprice.lua takes its
  -- price panel down on the same event; without this the note would outlive
  -- the tooltip whenever it is hidden without the slot's OnLeave running.
  local tooltip = U.G("GameTooltip")
  if tooltip then
    U.PostHookScript(tooltip, "OnHide", function() U.HideTooltipNote() end)
  end
end
