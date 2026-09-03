-- unrealUI :: core/itemsort.lua
--
-- Container sorting: rearranges the items already in a set of general-purpose
-- containers into the category order core/itemcategory.lua defines. It sits in
-- core/ beside that classifier and takes the container list as an argument, so
-- both windows drive the one engine -- modules/bags.lua passes the player bags
-- and modules/bank.lua passes the main bank pane plus its purchased bank bags.
-- Nothing below is written against either window.
--
-- EVIDENCE -- read this before changing anything here.
--
-- PickupContainerItem is OFFICIAL_CLIENT_DOCUMENTATION but
-- DOCUMENTED_NOT_RUNTIME_VERIFIED on this client: "Picks up the item in
-- bag/slot, or drops/swaps the cursor item into that slot"
-- (documentation.json / global:Container:PickupContainerItem). That is exactly
-- the swap primitive a sort needs, and it is the only one documented.
--
-- There is no working reference implementation to fall back on. UnrealPfUI does
-- not sort bags: modules/thirdparty.lua only draws a button and hands the click
-- to SortBags or MrPlow, so the UnrealPfUI evidence-gap rule supplies nothing
-- for the moving part.
--
-- And there is one adjacent failure on record. behavior.json /
-- bankmove.route_A.container_to_container.v1 is RUNTIME_FAILURE_CONFIRMED: a
-- PickupContainerItem drop did not move an item. That test's destination was
-- the *main bank pane*, which the same probe group found is inventory-addressed
-- rather than container-addressed, so it is not evidence that an ordinary
-- bag-to-bag swap fails -- but it is proof that this client's container drop
-- path is not uniformly reliable, and it is why nothing below trusts a call to
-- have worked.
--
-- The design consequence: every step is verified against the containers
-- themselves, never inferred from the fact that a call did not error. A swap
-- that does not land aborts the run, returns anything left on the cursor, and
-- reports it. That is what makes this safe to run on an unverified API -- it
-- cannot scatter an inventory, because it stops the moment reality stops
-- matching the plan. Feed anything measured in game back into knowledge.json.
--
-- THE BANK is the one container set that is not addressed like the rest. The
-- main pane (-1) reads through the container API but must be written through
-- the inventory API, and it under-reports its own size. Neither quirk is
-- handled here: core/compat.lua's U.PickupContainerSlot and U.ContainerSlotCount
-- absorb both, because the bank *window* needs the identical correction for
-- its drag and drop. That file carries the measured bankmove evidence; this
-- one just uses the two calls everywhere and stays container-shaped.

local U = UnrealUI

-- One table rather than a top-level local per member, per the local-budget rule
-- in .claude/rules/unreal-ui.md.
local IS = {}

IS.UPDATE_ID = "bags.sort"
IS.INTERVAL = 0.15   -- matches the grey-vendor queue in modules/bags.lua
IS.MAX_RETRIES = 3   -- ticks a single swap may fail to land before giving up
IS.PREFIX = "BAGS_SORT"   -- default locale key prefix; see U.SortBags
IS.BANK_CONTAINER = -1

IS.run = nil

-- Locale key for one outcome of a run, so a window can label the same engine
-- in its own words: the bank says "Bank sorted", not "Bags sorted".
function IS.Message(prefix, suffix)
  return U.L((prefix or IS.PREFIX) .. "_" .. suffix)
end

-- ---------------------------------------------------------------------------
-- Which bags may be sorted
-- ---------------------------------------------------------------------------
-- Only a plain Bag accepts any item. Soul bags, herb bags, enchanting and
-- engineering bags, quivers and ammo pouches refuse anything outside their
-- speciality, so an item moved into one would be silently declined and the run
-- would stall with it on the cursor. Those bags are left exactly as they are,
-- and so is any bag whose own item is not in the client's local cache -- an
-- unreadable bag is treated as special, because guessing the other way is the
-- only guess that can lose an item's place.
--
-- The backpack (0) is always general-purpose and has no inventory item at all,
-- and the main bank pane (-1) is the same case: it accepts anything and has no
-- bag item to read. Every other bank container is a purchased bank bag, which
-- is an ordinary equipped bag and goes through the check below like bags 1..4.
--
-- ContainerIDToInventoryID is documented for bank bags 5..10 as well as the
-- worn 1..4 (documentation.json / global:Container:ContainerIDToInventoryID)
-- but is DOCUMENTED_NOT_RUNTIME_VERIFIED, and the one measured data point
-- nearby -- probe bankbagicon.mapping.v1, which found the equipped bank bag at
-- inventory slot 64 rather than Vanilla's 68 -- shows this client does not use
-- Vanilla's inventory numbering. If the call does not resolve for 5..10 here,
-- the conservative branch below excludes those bags and a bank sort quietly
-- rearranges only the main pane. That is the safe failure, not a silent one to
-- ignore: if purchased bank bags visibly do not reorder in game, this is why,
-- and it wants a focused probe rather than a guessed inventory id.
function IS.IsGeneralBag(bag)
  if bag == 0 or bag == IS.BANK_CONTAINER then return true end

  local idOk, inventoryId = pcall(ContainerIDToInventoryID, bag)
  if not idOk or not tonumber(inventoryId) then return false end

  local linkOk, link = pcall(GetInventoryItemLink, "player", inventoryId)
  if not linkOk or type(link) ~= "string" or link == "" then return false end

  local infoOk, _, _, _, _, itemType, subType = pcall(GetItemInfo, link)
  if not infoOk then return false end

  return itemType == "Container" and subType == "Bag"
end

-- ---------------------------------------------------------------------------
-- Ordering
-- ---------------------------------------------------------------------------
-- Category first, then quality high to low, then name, then the link itself.
--
-- The key is built as one string rather than compared field by field so the
-- comparator is a plain `<` on a total order. table.sort raises "invalid order
-- function for sorting" when a comparator is inconsistent, and a hand-written
-- multi-field comparison over values that may each be nil is exactly how that
-- happens.
function IS.SortKey(order, link)
  local index = 99
  local quality, name = 0, ""

  local ok, itemName, _, itemQuality = pcall(GetItemInfo, link)
  if ok then
    if type(itemName) == "string" then name = string.lower(itemName) end
    quality = tonumber(itemQuality) or 0
  end

  local category = U.ItemCategoryFromLink(link)
  if category and order[category] then index = order[category] end

  -- 9 - quality so that Legendary sorts above Poor within a category.
  return string.format("%03d|%02d|", index, 9 - quality) .. name .. "|" .. link
end

function IS.CategoryOrder()
  local order = {}
  local list = U.ItemCategoryOrder()
  local i
  for i = 1, table.getn(list) do order[list[i]] = i end
  return order
end

-- ---------------------------------------------------------------------------
-- Plan
-- ---------------------------------------------------------------------------
-- positions is every sortable slot in bag order; desired[i] is the item link
-- that belongs at positions[i]. Both are a snapshot: if the bags change while
-- the run drains, the desired item stops being findable and the run aborts
-- rather than shuffling against a stale plan.
function IS.Plan(bagIds)
  local order = IS.CategoryOrder()
  local positions, items = {}, {}
  local i

  for i = 1, table.getn(bagIds) do
    local bag = bagIds[i]
    if IS.IsGeneralBag(bag) then
      -- Not GetContainerNumSlots directly: the main bank pane reports zero for
      -- itself, and U.ContainerSlotCount is where that is corrected.
      local n = U.ContainerSlotCount(bag)

      local slot
      for slot = 1, n do
        table.insert(positions, { bag = bag, slot = slot })

        local linkOk, link = pcall(GetContainerItemLink, bag, slot)
        if linkOk and type(link) == "string" and link ~= "" then
          table.insert(items, { link = link, sort = IS.SortKey(order, link) })
        end
      end
    end
  end

  table.sort(items, function(a, b) return a.sort < b.sort end)

  local desired = {}
  for i = 1, table.getn(items) do desired[i] = items[i].link end

  return positions, desired
end

-- ---------------------------------------------------------------------------
-- Reading the world back
-- ---------------------------------------------------------------------------
function IS.LinkAt(position)
  local ok, link = pcall(GetContainerItemLink, position.bag, position.slot)
  if not ok or type(link) ~= "string" or link == "" then return nil end
  return link
end

function IS.Locked(position)
  local _, _, locked = U.ContainerSlotInfo(position.bag, position.slot)
  return locked and true or false
end

-- ---------------------------------------------------------------------------
-- Finishing
-- ---------------------------------------------------------------------------
-- suffix: the outcome half of the locale key ("DONE", "FAILED", ...), or nil
-- to end the run without saying anything -- which is what a window closing
-- under a running sort wants, since the window is its own explanation.
function IS.Finish(suffix)
  local run = IS.run
  IS.run = nil
  U.UnregisterUpdate(IS.UPDATE_ID)

  -- Never end holding something. Whatever is on the cursor came out of the
  -- source slot this tick, so that is where it is put back.
  if U.CursorHasItem() and run and run.holding then
    U.PickupContainerSlot(run.holding.bag, run.holding.slot)
  end
  if U.CursorHasItem() then pcall(ClearCursor) end

  if suffix then U.Print(IS.Message(run and run.prefix, suffix)) end
  if run and type(run.onFinish) == "function" then pcall(run.onFinish) end
end

-- ---------------------------------------------------------------------------
-- One swap
--
-- Documented behaviour: a pickup lifts the slot's item; a second pickup on an
-- occupied slot drops what is held and lifts what was there. So a full swap is
-- lift source, drop into destination, drop the displaced item back into source.
-- Each stage is checked against the cursor rather than assumed.
-- ---------------------------------------------------------------------------
function IS.Swap(run, src, dst)
  if U.CursorHasItem() then return false end

  run.holding = src
  if not U.PickupContainerSlot(src.bag, src.slot) then return false end

  -- The lift itself did nothing: stop here rather than dropping a nil cursor
  -- onto an occupied slot.
  if not U.CursorHasItem() then return false end

  U.PickupContainerSlot(dst.bag, dst.slot)

  -- Destination was occupied, so its item is now held; it belongs in source.
  if U.CursorHasItem() then
    U.PickupContainerSlot(src.bag, src.slot)
  end

  -- Still holding something: leave run.holding set so IS.Finish knows which
  -- slot to put it back into. Clearing it here would strand the item.
  if U.CursorHasItem() then return false end

  run.holding = nil
  return true
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------
function IS.Step()
  local run = IS.run
  if not run then
    U.UnregisterUpdate(IS.UPDATE_ID)
    return
  end

  -- Verify the swap issued last tick actually landed before doing anything
  -- else. This is the whole safety story: an API that quietly does nothing
  -- stops the run here instead of being issued another hundred times.
  if run.pending then
    if IS.LinkAt(run.pending.dst) == run.pending.link then
      run.pending = nil
      run.retries = 0
      run.moves = run.moves + 1
    else
      run.retries = run.retries + 1
      if run.retries > IS.MAX_RETRIES then
        IS.Finish("FAILED")
      end
      return
    end
  end

  local total = table.getn(run.positions)

  while run.index <= total do
    local position = run.positions[run.index]
    local want = run.desired[run.index]
    local have = IS.LinkAt(position)

    -- Past the last item: everything from here on should be empty, and an
    -- occupied slot means the plan no longer matches the bags.
    if not want then
      if have then
        IS.Finish("FAILED")
        return
      end
      run.index = run.index + 1
    elseif have == want then
      run.index = run.index + 1
    else
      -- Find the wanted item further down and bring it here. Identical items
      -- are interchangeable, so the first match is always a correct choice.
      local source
      local j
      for j = run.index + 1, total do
        if IS.LinkAt(run.positions[j]) == want then
          source = run.positions[j]
          break
        end
      end

      if not source then
        -- The plan asked for something that is no longer in the bags: the
        -- contents changed under the run.
        IS.Finish("FAILED")
        return
      end

      -- A slot the server is still settling cannot be moved. Wait for it
      -- rather than issuing a swap that is certain to be refused.
      if IS.Locked(source) or IS.Locked(position) then
        run.retries = run.retries + 1
        if run.retries > IS.MAX_RETRIES then IS.Finish("FAILED") end
        return
      end

      if not IS.Swap(run, source, position) then
        IS.Finish("FAILED")
        return
      end

      run.pending = { dst = position, link = want }
      return
    end
  end

  if run.moves > 0 then
    IS.Finish("DONE")
  else
    IS.Finish("NOTHING")
  end
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------
-- There is one run at a time for the whole addon, because there is one cursor.
-- A window asking whether "its" sort is active is really asking whether the
-- engine is busy, which is also exactly what its button should reflect.
function U.BagSortActive()
  return IS.run and true or false
end

-- bagIds: the containers to sort, in the order they should be filled.
-- options, all optional:
--   onFinish  called however the run ends, so a caller can restore a button's
--             normal state without polling.
--   prefix    locale key prefix for this run's messages, default "BAGS_SORT".
--             The bank passes "BANK_SORT" so the same outcomes are worded for
--             the window the player is looking at.
--   owner     a token identifying the caller, so U.StopSort can end this run
--             and only this run.
function U.SortBags(bagIds, options)
  if type(bagIds) ~= "table" then return false end

  options = options or {}
  local prefix = options.prefix or IS.PREFIX

  if IS.run then
    U.Print(IS.Message(prefix, "BUSY"))
    return false
  end

  -- Sorting drives the cursor. Starting with something already on it would
  -- drop that item into the first slot the run touches.
  if U.CursorHasItem() then
    U.Print(IS.Message(prefix, "CURSOR"))
    return false
  end

  local positions, desired = IS.Plan(bagIds)
  if table.getn(positions) == 0 then
    U.Print(IS.Message(prefix, "NOTHING"))
    return false
  end

  IS.run = {
    positions = positions,
    desired = desired,
    index = 1,
    retries = 0,
    moves = 0,
    onFinish = options.onFinish,
    prefix = prefix,
    owner = options.owner,
  }

  U.RegisterUpdate(IS.UPDATE_ID, IS.INTERVAL, IS.Step)
  return true
end

-- End the caller's own run early and silently, leaving another owner's run
-- alone. The bank calls this when its window hides: the containers a bank run
-- addresses stop being writable the moment the banker session ends, and the
-- cursor is empty between ticks, so stopping here is clean where letting the
-- next tick discover the closed bank is merely survivable.
function U.StopSort(owner)
  if not IS.run then return false end
  if owner ~= nil and IS.run.owner ~= owner then return false end

  IS.Finish(nil)
  return true
end
