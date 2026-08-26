-- unrealUI :: modules/itemprice.lua
--
-- Item value at the bottom of bag and bank item tooltips. See "Hover path"
-- below for why that is the current reach and what it would take to widen it.
--
-- This client has no API that returns a price from an item id. GetItemInfo
-- stops at `texture` and returns nine values with no sellPrice
-- (documentation.json / global:Item:GetItemInfo), and query_compat.py has no
-- record of GetSellValue at all. Every price this client will disclose is
-- situational:
--
--   * GetMerchantItemInfo(i)     buy price, vendor window open
--   * GetBuybackItemInfo(i)      sell price, but no item link to key it by
--   * GetAuctionSellItemInfo()   vendor sell price, auction sell slot only
--   * GameTooltip:SetBagItem     fires OnTooltipAddMoney with the stack sell
--                                price, and only while a merchant is open
--
-- So unrealUI learns prices instead of looking them up: whatever a vendor or a
-- tooltip discloses is written to UnrealUIPriceDB and reused everywhere after.
--
-- Learning alone only covers items the player has already carried past a
-- vendor, so core/pricedata.lua supplies a base price for every stock item id
-- as a fallback (Vanilla data extracted from UnrealPfUI, see that file for the
-- provenance and its accuracy limit). A learned price always wins over it, and
-- the table is never written back into UnrealUIPriceDB, so one vendor visit
-- permanently corrects anything this server has re-priced.
--
-- The first version identified the hovered item by replacing GameTooltip's
-- item setters, the way UnrealPfUI libs/libtooltip.lua does. That does not
-- work on this client and the replacement is documented under "Hover path".

local U = UnrealUI
local IP = U.RegisterModule("itemprice")

local DB_NAME = "UnrealUIPriceDB"
local DB_VERSION = 1

local store              -- { version, sell = {[id] = copper}, buy = {[id] = copper} }
local tracked = {}       -- tooltip frame -> { id, count }

-- Diagnostic state for /uui price. A missing price line has a small number of
-- distinct causes -- the hover hook never ran, the link did not resolve, the
-- item has no row, the vendor suppression fired -- and this records which one
-- happened on the last tooltip build rather than leaving it to be guessed at.
local trace = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function LinkID(link)
  if type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

local function Sane(copper)
  copper = tonumber(copper)
  if not copper or copper <= 0 then return nil end
  return math.floor(copper)
end

-- Every price source below is optional on this client, so nothing is called
-- directly: a missing global leaves the tooltip untouched instead of erroring
-- inside a native tooltip build.
local function Call(name, a1, a2)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end

  local ok, r1, r2, r3, r4 = pcall(fn, a1, a2)
  if not ok then return nil end
  return r1, r2, r3, r4
end

local function MerchantShown()
  local frame = U.G("MerchantFrame")
  if not frame or not frame.IsShown then return false end

  local ok, shown = pcall(frame.IsShown, frame)
  if ok and shown then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Store
--
-- Its own SavedVariable rather than a config key: prices are account-wide
-- learned data, not per-profile settings, and core/config.lua validates a
-- small fixed schema. Only numbers are stored, so knowledge.json /
-- config.savedvariables_backslash_corruption cannot bite.
-- ---------------------------------------------------------------------------
local function Prune(list)
  local key, value
  for key, value in pairs(list) do
    if type(key) ~= "number" or not Sane(value) then list[key] = nil end
  end
end

local function LoadStore()
  local db = U.G(DB_NAME)
  if type(db) ~= "table" then
    U.SetG(DB_NAME, { version = DB_VERSION })
    db = U.G(DB_NAME)
    -- Global write ignored: keep the prices for this session rather than
    -- disabling the readout entirely.
    if type(db) ~= "table" then db = { version = DB_VERSION } end
  end

  db.version = DB_VERSION
  if type(db.sell) ~= "table" then db.sell = {} end
  if type(db.buy) ~= "table" then db.buy = {} end

  -- A corrupted or hand-edited saved file must not reach a tooltip.
  Prune(db.sell)
  Prune(db.buy)

  store = db
  return true
end

-- Sell prices keep the highest unit price seen, because the client reports a
-- durability- and charge-adjusted sell price: hovering a damaged weapon at a
-- vendor quotes less than the repaired item is worth. Buy prices keep the most
-- recent quote instead -- a vendor asking price legitimately varies with the
-- reputation discount, so there is no single true value to converge on.
local function Record(kind, id, copper)
  if not store or not id then return end

  copper = Sane(copper)
  if not copper then return end

  local list = store[kind]
  if kind == "sell" and list[id] and list[id] >= copper then return end
  list[id] = copper
end

-- ---------------------------------------------------------------------------
-- Lookup
--
-- A learned price always wins over core/pricedata.lua: that table is Vanilla
-- data and this server is not Vanilla, so the moment a vendor discloses a real
-- price it replaces the base row for good. Parsed rows are memoised because
-- the packed "sell,buy" string needs a string.find to split, and a tooltip can
-- be rebuilt on every frame while the mouse rests on a slot.
--
-- A zero in either field means unsellable / not stocked, and Sane() turns it
-- into nil, so that half simply gets no line.
-- ---------------------------------------------------------------------------
local baseCache = {}

local function Base(id)
  local row = baseCache[id]
  if row == nil then
    row = false

    local packed = U.priceData and U.priceData[id]
    if type(packed) == "string" then
      local _, _, sell, buy = string.find(packed, "(%d+),(%d+)")
      if sell then row = { sell = Sane(sell), buy = Sane(buy) } end
    end
    baseCache[id] = row
  end

  if not row then return nil end
  return row
end

local function Lookup(kind, id)
  if store and store[kind][id] then return store[kind][id] end

  local row = Base(id)
  if row then return row[kind] end
  return nil
end

-- ---------------------------------------------------------------------------
-- Harvest
-- ---------------------------------------------------------------------------
-- Vendor list: the quoted price is per purchase and one purchase can grant a
-- stack (arrows), so it is normalised to a unit price.
local function ScanMerchant()
  local total = tonumber(Call("GetMerchantNumItems")) or 0

  local i
  for i = 1, total do
    local id = LinkID(Call("GetMerchantItemLink", i))
    if id then
      local _, _, price, quantity = Call("GetMerchantItemInfo", i)
      quantity = tonumber(quantity) or 1
      if quantity < 1 then quantity = 1 end

      price = tonumber(price)
      if price and price > 0 then Record("buy", id, price / quantity) end
    end
  end
end

-- OnTooltipAddMoney carries the stack sell price. Which position the amount
-- arrives in depends on this client handler shape (core/init.lua resolves
-- three of them for events and cannot resolve them for scripts), so the first
-- positive number wins and the legacy `arg1` global is the last resort. A
-- wrong shape therefore records nothing instead of recording nonsense.
local function ResolveAmount(a1, a2, a3, a4)
  local value = tonumber(a1)
  if value and value > 0 then return value end
  value = tonumber(a2)
  if value and value > 0 then return value end
  value = tonumber(a3)
  if value and value > 0 then return value end
  value = tonumber(a4)
  if value and value > 0 then return value end

  value = tonumber(U.G("arg1"))
  if value and value > 0 then return value end
  return nil
end

-- ---------------------------------------------------------------------------
-- Tooltip tracking and readout
-- ---------------------------------------------------------------------------
local function Remember(tip, link, count)
  local rec = tracked[tip]
  if not rec then
    rec = {}
    tracked[tip] = rec
  end

  rec.id = LinkID(link)
  rec.count = tonumber(count) or 1
end

local function Append(tip)
  -- One singleton is shared by all price readouts. Clear the previous owner
  -- before resolving this hover so an unknown or suppressed item cannot leave
  -- the last item's panel visible.
  U.HideMoneyRows()

  local rec = tracked[tip]
  if not rec or not rec.id then
    trace.result = "no item id resolved"
    return
  end

  -- While a vendor is open the client adds its own sell-price money frame to
  -- the tooltip. That frame is anchored under whatever the last line was when
  -- it was added, so appending text after it would draw over it -- and it
  -- already says the same thing. UnrealPfUI suppresses its own line the same
  -- way in modules/sellvalue.lua.
  if MerchantShown() then
    trace.result = "suppressed, merchant open"
    return
  end

  local sell = Lookup("sell", rec.id)
  if not sell then
    trace.result = "no sell price known for item " .. rec.id
    return
  end

  local count = rec.count or 1
  if count < 1 then count = 1 end

  -- Always one row: the displayed sell value belongs to the hovered stack.
  -- A single item naturally remains its unit value because count is one.
  local stackSell = sell * count
  local rows = { { label = U.L("COMMON_SELL"), copper = stackSell } }

  -- This remains a separate owned frame because GameTooltip will not relayout,
  -- but matching its width and sharing the edge makes it one visual surface.
  -- The match is asked for rather than measured here: a width read during this
  -- hover is still the previous tooltip's, which is what made the price cell
  -- render far wider than the tooltip above it. U.ShowMoneyRows carries the
  -- detail and does the tracking.
  local panel = U.ShowMoneyRows(tip, rows, "TOPLEFT", "BOTTOMLEFT", 0, 0, true)
  local shown, height = false, nil
  if panel then
    local shownOk, shownValue = pcall(panel.IsShown, panel)
    if shownOk then shown = shownValue and true or false end

    local heightOk, heightValue = pcall(panel.GetHeight, panel)
    if heightOk then height = heightValue end
  end

  -- Kept so /uui price can report the width the panel settled on after the
  -- client laid the tooltip out, not the one it opened with.
  trace.panelFrame = panel
  trace.result = "panel shown, " .. table.getn(rows) .. " rows"
  trace.sell = stackSell
  trace.panel = "shown=" .. tostring(shown) .. " height=" .. tostring(height)
end

-- ---------------------------------------------------------------------------
-- Hover path
--
-- USER_CONFIRMED_INGAME (2026-08-26, /uui price): replacing a method on
-- GameTooltip does not hold on this client. unrealUI installed a wrapper for
-- all ten item setters and at hover time none of them was the live method, and
-- not one had ever run -- "hooks: 0 live, 10 replaced, 0 never installed" with
-- "last tooltip: none seen". A later hook by someone else would have kept our
-- wrapper in the chain and it would still have run, so the assignment itself
-- is what does not persist. UnrealPfUI libs/libtooltip.lua is built entirely
-- on that assignment: a reminder that WORKING_SOURCE is not evidence that
-- something works here.
--
-- The item is therefore identified from the button being hovered rather than
-- from the tooltip. core/itemslot.lua already post-hooks OnEnter on every bag
-- and bank slot it creates -- a script hook through U.PostHookScript, the
-- mechanism this addon uses everywhere and which demonstrably works -- and it
-- knows the container and slot. It calls in here once the stock template has
-- populated and shown GameTooltip.
--
-- Consequence, stated rather than left to be discovered: the price panel
-- appears on the surfaces unrealUI owns a hover hook for. Bag and bank slots
-- have one.
-- Merchant rows, loot, quest rewards and chat links do not yet, and each needs
-- its own button hook rather than one central tooltip hook.
-- ---------------------------------------------------------------------------
function U.ShowItemPrice(bag, slot)
  U.HideMoneyRows()

  local tooltip = U.G("GameTooltip")
  if not tooltip then return end

  local link = Call("GetContainerItemLink", bag, slot)
  local _, count = Call("GetContainerItemInfo", bag, slot)
  Remember(tooltip, link, count)

  trace.source = "bag " .. tostring(bag) .. " slot " .. tostring(slot)
  trace.link = link
  trace.id = LinkID(link)
  trace.count = count
  trace.sell = nil
  trace.panel = nil
  trace.result = "hover ran, Append did not finish"

  local ok, err = pcall(Append, tooltip)
  if not ok then
    trace.result = "error: " .. tostring(err)
    U.Debug("itemprice hover: " .. tostring(err))
  end
end

function U.HideItemPrice()
  U.HideMoneyRows()
end

-- ---------------------------------------------------------------------------
-- Diagnostic
--
-- /uui price, printed straight to chat. Hover an item, run it, and the last
-- line names which stage stopped: the setter never ran (no hook), no item id
-- (link getter), no price (missing row), suppressed (vendor open), or added.
-- ---------------------------------------------------------------------------
local function CountKeys(list)
  local total, key = 0, nil
  if type(list) ~= "table" then return 0 end
  for key in pairs(list) do total = total + 1 end
  return total
end

function U.PriceDebugDump()
  U.Print("item price:")

  local data = U.priceData
  U.Print("  base table: " .. (type(data) == "table" and
          (CountKeys(data) .. " items, id 25 = " .. tostring(data[25])) or
          "MISSING (core/pricedata.lua did not load)"))

  if store then
    U.Print("  learned: " .. CountKeys(store.sell) .. " sell, " ..
            CountKeys(store.buy) .. " buy")
  else
    U.Print("  learned: store not loaded")
  end

  U.Print("  merchant open: " .. tostring(MerchantShown()))

  if not trace.source then
    U.Print("  last hover: none seen -- core/itemslot.lua never called in")
    return
  end

  U.Print("  last hover: " .. tostring(trace.source) ..
          " link=" .. tostring(trace.link) ..
          " id=" .. tostring(trace.id) ..
          " count=" .. tostring(trace.count))
  U.Print("  result: " .. tostring(trace.result) ..
          " (sell=" .. tostring(trace.sell) .. ")")

  if trace.panel then U.Print("  panel: " .. tostring(trace.panel)) end

  -- Width is read live rather than from the trace: the panel follows the
  -- tooltip for as long as it is shown, so the settled numbers only exist on
  -- the frame itself.
  local frame = trace.panelFrame
  if frame then
    U.Print("  width: content=" .. tostring(frame.contentWidth) ..
            " anchor=" .. tostring(frame.anchorWidth) ..
            " applied=" .. tostring(frame.appliedWidth))
  end
end

-- ---------------------------------------------------------------------------
-- Bootstrap
-- ---------------------------------------------------------------------------
function IP:OnEnable()
  -- Never fails closed: a rejected global write leaves a session-only store,
  -- and the readout still has core/pricedata.lua to fall back on.
  LoadStore()

  local tooltip = U.G("GameTooltip")

  -- The tracked item belongs to one hover. Clearing it when the tooltip hides
  -- keeps a stale id from being credited with the next vendor money line.
  if tooltip then
    U.PostHookScript(tooltip, "OnHide", function()
      U.HideItemPrice()

      local rec = tracked[tooltip]
      if rec then
        rec.id = nil
        rec.count = nil
      end
    end)
  end

  -- The stack sell price handed to the tooltip at a vendor is the only true
  -- sell value this client volunteers for an arbitrary bag item, so it is
  -- captured wherever it appears.
  if tooltip then
    U.PostHookScript(tooltip, "OnTooltipAddMoney", function(a1, a2, a3, a4)
      local rec = tracked[tooltip]
      if not rec or not rec.id then return end

      local amount = ResolveAmount(a1, a2, a3, a4)
      if not amount then return end

      local count = rec.count or 1
      if count < 1 then count = 1 end
      Record("sell", rec.id, amount / count)
    end)
  end

  U.RegisterEvent("MERCHANT_SHOW", ScanMerchant)
  U.RegisterEvent("MERCHANT_UPDATE", ScanMerchant)
end
