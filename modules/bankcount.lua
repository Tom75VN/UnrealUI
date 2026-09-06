-- unrealUI :: modules/bankcount.lua
--
-- Stack quantities for the main bank pane, derived rather than read.
--
-- Why this exists: this client never reports a count for container -1.
-- GetContainerItemInfo(-1, slot) returns a correct texture and quality but
-- count 0 for every occupied slot -- including single items that answer 1 in a
-- carried bag -- and GetInventoryItemCount answers 0 for the bank inventory
-- slots the pane is written through. The native bank window shows no quantity
-- either, with no addon loaded. Purchased bank bags 5..10 are ordinary
-- containers and need none of this. See knowledge.json /
-- bank.stack_count_region_not_visible, which carries the measured evidence and
-- both dead read routes.
--
-- So the quantity is inferred from the one place it is readable: the carried
-- bags and bank bags an item passes through. Every container except the main
-- pane reports counts correctly, so a deposit can be attributed by difference
-- -- the countable containers lost twelve Malachite, a pane slot gained
-- Malachite, therefore that pane slot holds twelve. No click hook is involved,
-- so cursor drops, right-click deposits and stack splits are all observed the
-- same way.
--
-- The honest limit, and the reason every branch below prefers to forget:
-- inference only works while unrealUI is watching. A session played without
-- the addon can change a pane slot's quantity while leaving the same item in
-- place, and nothing readable distinguishes that from an untouched slot. A
-- wrong number is worse than none, so an arrival that cannot be attributed
-- clears every pane slot holding that item rather than guessing, and a
-- withdrawal that arrives in a bag with a quantity contradicting the stored
-- one wipes the whole store as proof the inference has drifted.
--
-- Every client call here is a guarded read of a container API with no compact
-- behavior record on this client (see core/itemslot.lua's header), so nothing
-- is called directly and no result is trusted.

local U = UnrealUI
local BC = U.RegisterModule("bankcount")

local DB_NAME = "UnrealUIBankCountDB"
local DB_VERSION = 1

local BANK_CONTAINER = -1

-- The containers a bank item can be attributed from or to. Carried bags and
-- purchased bank bags both report real counts, so both are evidence.
local READABLE_BAGS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }

-- store.ids[slot] / store.counts[slot]: two flat numeric tables rather than one
-- table of records, so validation is a pair of number checks and nothing but
-- numbers is ever persisted (knowledge.json /
-- config.savedvariables_backslash_corruption).
local store

-- Last seen state, in memory only. `readable` is what every countable
-- container held on the previous pass; `paneIds` is the item id the pane held
-- in each slot. A pass compares against these to work out what moved.
local readable
local paneIds

local active = false

-- Set by the container events, cleared by a pass. A reconcile walks every
-- countable container, so it runs only when something actually moved rather
-- than on each of the bank window's five ticks a second.
local dirty = false

-- Diagnostic trace, off unless /uui bankcount turns it on. Every pass appends
-- one row saying what it saw and what it decided, so a store that empties can
-- be read back afterwards instead of guessed at. Written through
-- U.AppendDiagnostic, which caps its own list, and never read by the addon.
local tracing = false
local trace

local function Trace(event, detail)
  if not tracing then return end
  if type(trace) ~= "table" then trace = {} end
  table.insert(trace, { at = event, detail = detail })
  while table.getn(trace) > 60 do table.remove(trace, 1) end
end

local function FlushTrace(reason)
  if not tracing or type(trace) ~= "table" then return end
  if type(U.AppendDiagnostic) ~= "function" then return end
  U.AppendDiagnostic("bankCount", { reason = reason, rows = trace })
  trace = nil
end

-- ---------------------------------------------------------------------------
-- Store
--
-- Its own SavedVariable, per character, for the reason modules/bagfavorites.lua
-- keeps one: this is derived game data with free-form numeric keys, not a
-- setting, and a bank belongs to one character.
-- ---------------------------------------------------------------------------
local function EnsureStore()
  if store then return store end

  local db = U.G(DB_NAME)
  if type(db) ~= "table" then
    U.SetG(DB_NAME, { version = DB_VERSION })
    db = U.G(DB_NAME)
    -- A rejected global write leaves a session-only table: quantities stop
    -- surviving a reload, but they still work for this session.
    if type(db) ~= "table" then db = { version = DB_VERSION } end
  end

  db.version = DB_VERSION
  if type(db.ids) ~= "table" then db.ids = {} end
  if type(db.counts) ~= "table" then db.counts = {} end

  -- A corrupted or hand-edited saved file must not be able to put a quantity
  -- on a slot that does not exist, or a non-number anywhere.
  local slot, value
  for slot, value in pairs(db.ids) do
    if type(slot) ~= "number" or slot <= 0 or
       type(value) ~= "number" or value <= 0 then
      db.ids[slot] = nil
      db.counts[slot] = nil
    end
  end
  for slot, value in pairs(db.counts) do
    if type(slot) ~= "number" or slot <= 0 or
       type(value) ~= "number" or value <= 1 or db.ids[slot] == nil then
      db.counts[slot] = nil
    end
  end

  store = db
  return store
end

-- A quantity of 1 is not stored at all: the display draws nothing for it, so
-- keeping it would only add rows that can go stale.
local function Remember(slot, id, count)
  local db = EnsureStore()
  count = tonumber(count)
  if not id or not count or count <= 1 then
    db.ids[slot] = nil
    db.counts[slot] = nil
    return
  end
  db.ids[slot] = id
  db.counts[slot] = count
end

local function Forget(slot)
  local db = EnsureStore()
  db.ids[slot] = nil
  db.counts[slot] = nil
end

-- Every pane slot holding one item id loses its quantity together. Used
-- whenever that item's arrangement changed in a way this module could not
-- account for: if one stack of it is uncertain, none of them can be trusted.
-- A stack split inside the pane is the ordinary case -- the new slot cannot be
-- attributed, and the slot it came from is now wrong by exactly the amount
-- that left it.
local function ForgetItem(id)
  if not id then return end
  local db = EnsureStore()
  local slot, value
  for slot, value in pairs(db.ids) do
    if value == id then
      db.ids[slot] = nil
      db.counts[slot] = nil
    end
  end
end

local function ForgetAll()
  local db = EnsureStore()
  db.ids = {}
  db.counts = {}
end

-- ---------------------------------------------------------------------------
-- Reading the world
-- ---------------------------------------------------------------------------
local function PaneItemId(slot)
  local ok, link = pcall(GetContainerItemLink, BANK_CONTAINER, slot)
  if not ok then return nil end
  return U.ItemLinkId(link)
end

-- What every countable container holds right now, as one item id -> quantity
-- tally. Deliberately not per slot: the client is free to re-lay-out a bag
-- around a move, and only the totals are evidence about what left or arrived.
local function ReadReadable()
  local totals = {}
  local i

  for i = 1, table.getn(READABLE_BAGS) do
    local bag = READABLE_BAGS[i]
    local size = U.ContainerSlotCount(bag)

    local slot
    for slot = 1, size do
      local texture, count = U.ContainerSlotInfo(bag, slot)
      if texture then
        local ok, link = pcall(GetContainerItemLink, bag, slot)
        local id = ok and U.ItemLinkId(link) or nil
        if id then
          totals[id] = (totals[id] or 0) + (tonumber(count) or 1)
        end
      end
    end
  end

  return totals
end

local function ReadPane()
  local ids = {}
  local size = U.ContainerSlotCount(BANK_CONTAINER)
  local slot
  for slot = 1, size do
    ids[slot] = PaneItemId(slot)
  end
  return ids
end

local function Occupied(ids)
  local n, slot, id = 0
  for slot, id in pairs(ids or {}) do
    if id then n = n + 1 end
  end
  return n
end

local function StoredEntries()
  local db = EnsureStore()
  local n, slot, id = 0
  for slot, id in pairs(db.ids) do
    if id then n = n + 1 end
  end
  return n
end

-- How much of each item id the countable containers lost and gained between
-- two tallies. A deposit shows up as a loss, a withdrawal as a gain. Because
-- both sides are totals across every countable container, a move that never
-- touched the bank -- bag to bag, or bag to bank bag -- nets to zero and
-- cannot be mistaken for one.
local function Delta(before, after)
  local lost, gained = {}, {}
  local id, amount

  for id, amount in pairs(before or {}) do
    local now = (after and after[id]) or 0
    if now < amount then lost[id] = amount - now end
  end

  for id, amount in pairs(after or {}) do
    local was = (before and before[id]) or 0
    if amount > was then gained[id] = amount - was end
  end

  return lost, gained
end

-- ---------------------------------------------------------------------------
-- Reconciliation
--
-- One pass over the pane, comparing it against the previous pass. Called from
-- the bank window's refresh tick, so the previous pass is at most one tick old
-- and a single move is the normal case. Two moves inside one tick simply fail
-- to attribute, and failing to attribute clears.
-- ---------------------------------------------------------------------------
local function Reconcile(seedOnly)
  local db = EnsureStore()

  -- A move in progress is half a transaction: the item has left its slot and
  -- has not arrived anywhere countable, because it is on the cursor. Diffing
  -- that state sees a departure with nothing to explain it and throws the
  -- quantity away one tick before the drop would have confirmed it. Wait for
  -- the cursor to empty and diff the whole move at once. The before-state is
  -- deliberately left untouched so it still describes the world before the
  -- pickup.
  if U.CursorHasItem and U.CursorHasItem() then
    Trace("skip.cursor")
    return
  end

  local nowReadable = ReadReadable()
  local nowPane = ReadPane()
  local size = U.ContainerSlotCount(BANK_CONTAINER)
  local slot, id

  -- The pane can read as completely empty while it is still being filled in:
  -- modules/bank.lua already retries its own layout for exactly this reason,
  -- because BANKFRAME_OPENED can arrive before the client has the container
  -- contents. Acting on that read would forget every quantity at once, which
  -- no single move can legitimately cause. Skip the pass entirely and leave
  -- the before-state alone; the next tick sees the loaded pane.
  Trace("pass", { seed = seedOnly and 1 or 0, size = size,
                  paneNow = Occupied(nowPane),
                  paneWas = paneIds and Occupied(paneIds) or -1,
                  stored = StoredEntries() })

  if Occupied(nowPane) == 0 then
    local believed = (paneIds and Occupied(paneIds)) or StoredEntries()
    if believed > 1 then
      Trace("skip.emptyPane", { believed = believed })
      return
    end
  end

  -- First pass of a banker session: there is no before-state to diff against,
  -- so nothing can be attributed. Drop any stored quantity whose slot no
  -- longer holds the item it was recorded for -- that is the guard against a
  -- session played without unrealUI, or without this module.
  if seedOnly or not paneIds then
    for slot, id in pairs(db.ids) do
      if nowPane[slot] ~= id then
        Trace("seed.forget", { slot = slot, stored = id,
                               now = nowPane[slot] or 0 })
        Forget(slot)
      end
    end
    readable, paneIds = nowReadable, nowPane
    return
  end

  local lost, gained = Delta(readable, nowReadable)

  -- A withdrawal is the one chance to check the inference against reality: the
  -- stack left the pane and arrived somewhere countable. If the arrival
  -- disagrees with what was stored, every stored quantity is suspect, because
  -- whatever drifted this slot could have drifted the others.
  for slot = 1, size do
    local was = paneIds[slot]
    if was and nowPane[slot] ~= was and db.ids[slot] == was then
      local stored = db.counts[slot]
      local arrived = gained[was]
      if stored and arrived and arrived ~= stored then
        Trace("forgetAll.drift", { slot = slot, item = was,
                                   stored = stored, arrived = arrived })
        ForgetAll()
        readable, paneIds = nowReadable, nowPane
        return
      end
    end
  end

  -- Quantities leaving a pane slot, kept before the slot is cleared so a move
  -- inside the pane -- a sort, or a drag from one pane slot to another -- can
  -- carry its quantity across instead of losing it.
  local departed = {}
  local departedItems = {}
  for slot = 1, size do
    local was = paneIds[slot]
    if was and nowPane[slot] ~= was then
      departedItems[was] = true
      if db.ids[slot] == was and db.counts[slot] then
        departed[was] = departed[was] or {}
        table.insert(departed[was], db.counts[slot])
      end
    end
  end

  -- Every slot whose item changed starts from nothing.
  for slot = 1, size do
    if paneIds[slot] ~= nowPane[slot] then Forget(slot) end
  end

  -- Attribute each arrival: first from what the countable containers lost,
  -- then from a quantity that left another pane slot. An arrival that matches
  -- neither -- a split, or two moves inside one tick -- taints its item.
  local unresolved = {}
  for slot = 1, size do
    local now = nowPane[slot]
    if now and now ~= paneIds[slot] then
      local amount = lost[now]
      local list = departed[now]

      if amount and amount > 0 then
        Remember(slot, now, amount)
        lost[now] = nil
      elseif list and table.getn(list) == 1 then
        Remember(slot, now, list[1])
        departed[now] = nil
      else
        unresolved[now] = true
      end
    end
  end

  for id in pairs(unresolved) do
    Trace("forgetItem.unresolved", { item = id })
    ForgetItem(id)
  end

  -- A quantity that arrived in a countable container without any pane slot
  -- giving its item up is unexplained. The case that matters is a partial
  -- split out of a pane stack: the slot still holds the same item, so nothing
  -- above notices, and its stored quantity is now too high by whatever left.
  -- Loot, mail and vendor purchases land here too, which is harmless -- the
  -- response is to drop that one item's pane quantities, not to distrust the
  -- store.
  for id in pairs(gained) do
    if not departedItems[id] then
      Trace("forgetItem.unexplainedGain", { item = id, amount = gained[id] })
      ForgetItem(id)
    end
  end

  readable, paneIds = nowReadable, nowPane
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

-- The quantity to draw on a main-pane slot, or nil when it is unknown. The
-- stored item id must still match what the slot holds: an item swapped in
-- while unrealUI was not running invalidates its predecessor's quantity.
function U.BankSlotStackCount(bag, slot)
  if not active or not store then return nil end
  if tonumber(bag) ~= BANK_CONTAINER then return nil end

  slot = tonumber(slot)
  if not slot then return nil end

  local id = store.ids[slot]
  if not id then return nil end

  if PaneItemId(slot) ~= id then
    Trace("display.forget", { slot = slot, stored = id,
                              now = PaneItemId(slot) or 0 })
    Forget(slot)
    return nil
  end

  return store.counts[slot]
end

-- Called from the bank window's refresh tick while the window is open, and
-- with seed true when the banker session opens.
function U.ReconcileBankStacks(seed)
  if not active then return end

  if seed then
    dirty = false
    Reconcile(true)
    return
  end

  -- An unseeded pass runs whether or not anything moved: the seed itself can
  -- be skipped -- cursor busy, or the pane not filled in yet -- and until it
  -- lands there is no before-state for any later attribution to rest on.
  if not paneIds then
    Reconcile(true)
    return
  end

  if not dirty then return end
  dirty = false
  Reconcile(false)
end

-- The banker session ended: the pane stops being readable, so the next open
-- has to seed again rather than diff against a stale before-state.
function U.ReleaseBankStacks()
  readable, paneIds = nil, nil
  FlushTrace("bank closed")
end

-- /uui bankcount. Off by default: the trace is only useful while a specific
-- disappearance is being reproduced, and it writes on every pass.
function U.SetBankCountTrace(on)
  tracing = on and true or false
  if not tracing then FlushTrace("trace stopped") end
  return tracing
end

function BC:OnEnable()
  EnsureStore()
  active = true

  -- The pass itself is driven by the bank window's refresh tick; these only
  -- say that a pass is worth doing. Both events fire for bank containers as
  -- well as carried ones, and a move shows up in at least one of them.
  U.RegisterEvent("BAG_UPDATE", function() dirty = true end)
  U.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() dirty = true end)
  U.RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function() dirty = true end)
end
