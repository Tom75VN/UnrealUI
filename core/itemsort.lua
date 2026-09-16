-- unrealUI :: core/itemsort.lua
--
-- Container sorting: rearranges the items already in a set of general-purpose
-- containers into the category order core/itemcategory.lua defines. It sits in
-- core/ beside that classifier and takes the container list as an argument, so
-- both windows drive the one engine -- modules/bags.lua passes the player bags
-- and modules/bank.lua passes the main bank pane plus its purchased bank bags.
-- Nothing below is written against either window.
--
-- The containers are sorted as ONE bag, not one at a time. Every slot of every
-- sortable container is laid end to end and the sorted items are packed into
-- that run from its first slot, so an item moves between bags freely and the
-- free space collects at the end of the last bag. Which containers make up
-- that pool is the one thing this file has to get right -- see the
-- classification boundary under "Which bags may be sorted".
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
-- Bank addressing is centralized in core/compat.lua, and the bank half of this
-- engine is now measured rather than assumed. Probe
-- banksort.actual_sequence.v1 (2026-09-06) wrapped U.PickupContainerSlot and
-- watched a real run: the reads were right all along (the main pane answers
-- GetContainerItemLink correctly, and it was the inventory reader added to
-- "fix" this that was blind), while every drop into the main pane was refused
-- with "The item was not found." A swap this engine cannot make is a swap it
-- must not plan -- see IS.Swap.

local U = UnrealUI

-- One table rather than a top-level local per member, per the local-budget rule
-- in .claude/rules/unreal-ui.md.
local IS = {}

IS.UPDATE_ID = "bags.sort"

-- PACE
--
-- The tick rate does not decide how hard this hits the server. The run holds
-- at most one move in flight -- IS.Step will not issue a swap while run.pending
-- is set, and pending only clears when the destination is read back holding the
-- item -- so moves are issued no faster than the server confirms the previous
-- one, whatever the interval is. The interval decides one thing only: how long
-- an already-finished move sits unnoticed before the next is issued.
--
-- At 0.15s that dead time was the whole cost of a sort. Every move took two
-- ticks, one to issue and one to notice, so a bag set needing sixty moves spent
-- eighteen seconds almost entirely waiting on this timer rather than on the
-- client. The interval is therefore short, and the self-throttling above is
-- what makes that safe rather than a guess about how fast the client will
-- accept moves. It is not the grey-vendor queue in modules/bags.lua, which
-- paces an unverified *server action* with nothing to confirm it against.
IS.INTERVAL = 0.03

-- Budgets are seconds, converted to ticks below. Counting ticks directly ties
-- how patient the run is to how often it looks, so shortening the interval
-- would silently shorten every timeout with it -- at 0.03s the old three-tick
-- allowance for a swap to land would be 0.09s, well inside normal latency, and
-- the run would start dropping bags from the pool over nothing.
IS.SWAP_TIMEOUT = 1.0  -- seconds a swap may take to appear in its destination
IS.LOCK_TIMEOUT = 3.0  -- seconds a slot may stay locked by the server
IS.MAX_REPLANS = 4     -- times the plan may be rebuilt against changed bags

-- Ticks in `seconds`, at least one. A slow frame makes a tick longer than the
-- interval, never shorter, so the real budget can only come out longer than
-- asked for -- the forgiving direction for a client that is already struggling.
function IS.TickBudget(seconds)
  local ticks = math.floor(seconds / IS.INTERVAL)
  if ticks < 1 then ticks = 1 end
  return ticks
end
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
-- The sort pools every container it is given and packs the whole set from the
-- first slot of the first container onwards, so the bags behave as one large
-- bag. A container dropped here is a container the player's items never leave
-- and never enter, so this test decides how much of that pool actually exists.
--
-- Equipped containers are deliberately fail-CLOSED: only a positively
-- identified ordinary bag joins the pool. A specialty container can accept
-- some of the items already inside it, so waiting for a refused drop is too
-- late -- the sort may already have rearranged that quiver, soul bag or
-- profession bag. The user-confirmed French "Carquois" case demonstrated that
-- an English specialty-name deny-list cannot enforce this boundary.
--
-- The bag's type is read from its tooltip, not from its item link. Probe
-- bagtype (1.53.0/1.54.0, 2026-09-15) measured that GetInventoryItemLink
-- returns nothing for equipped bag slots on this client -- weapon slots do
-- answer -- and that GetItemInfo(GetBagName(bag)) returns nothing either. The
-- 0.7.0 link -> GetItemInfo test therefore rejected every bag and left the
-- backpack as the whole pool. A private GameTooltipTemplate scanner armed with
-- SetInventoryItem (the modules/status.lua durability sequence) does carry the
-- CONTAINER_SLOTS line, "6 Slot Bag" / "6 Slot Ammo Pouch" in that run.
--
-- The subtype on that line is localized, so it is compared by position, not
-- by word: it must be subclass 1 of auction class 3 (Container), which the
-- same probe measured as Bag, followed by Soul Bag, Herb Bag and Enchanting
-- Bag, with quivers and ammo pouches under class 7. Any unreadable step leaves
-- that equipped container untouched. Sorting fewer bags is safer than moving
-- items inside a container the sorter cannot prove is general-purpose.
--
-- The backpack (0) is always general-purpose and has no inventory item at all,
-- and the main bank pane (-1) is the same case.
IS.SCANNER_NAME = "UnrealUIBagTypeScanner"
IS.CONTAINER_AUCTION_CLASS = 3
IS.MAX_TOOLTIP_LINES = 12
IS.scanner = nil
-- Inventory slot of an equipped bag's own equipment button.
--
-- ContainerIDToInventoryID is the documented converter, but the client
-- documents the answer it should give independently: PutItemInBag's parameter
-- note names the bag buttons as inventory slots "20-23 or 64-69"
-- (documentation.json / global:Container:PutItemInBag), i.e. 19 + bag for the
-- worn 1..4 and 59 + bag for bank bags 5..10. That contiguous bank range is
-- the numbering probe bankbagicon.inventory_scan.v1 actually measured when it
-- found the equipped bank bag at inventory slot 64 rather than Vanilla's 68,
-- so the documented arithmetic is used as the fallback when the converter
-- does not answer rather than treating the bag as unreadable.
function IS.BagInventoryId(bag)
  local ok, id = pcall(ContainerIDToInventoryID, bag)
  id = ok and tonumber(id) or nil
  if id then return id end

  if bag >= 1 and bag <= 4 then return 19 + bag end
  if bag >= 5 and bag <= 10 then return 59 + bag end
  return nil
end

-- CONTAINER_SLOTS ("%d Slot %s" on enUS) as an anchored Lua pattern. Format
-- tokens become placeholders before the literal text is escaped, so the
-- escaping cannot corrupt them, and a positional %1$d form is accepted too.
function IS.SlotPattern()
  local template = U.G("CONTAINER_SLOTS")
  if type(template) ~= "string" or template == "" then return nil end

  local p = string.gsub(template, "%%%d*%$?d", "\001")
  p = string.gsub(p, "%%%d*%$?s", "\002")
  p = string.gsub(p, "([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
  p = string.gsub(p, "\001", function() return "(%d+)" end)
  p = string.gsub(p, "\002", function() return "(.+)" end)
  return "^" .. p .. "$"
end

-- The localized name of the plain bag subclass: the first subclass of the
-- Container auction class.
function IS.OrdinaryBagSubtype()
  local getSubClasses = U.G("GetAuctionItemSubClasses")
  if type(getSubClasses) ~= "function" then return nil end

  local ok, first = pcall(getSubClasses, IS.CONTAINER_AUCTION_CLASS)
  if not ok or type(first) ~= "string" or first == "" then return nil end
  return first
end

function IS.Scanner()
  if IS.scanner then return IS.scanner end

  local ok, tip = pcall(CreateFrame, "GameTooltip", IS.SCANNER_NAME, nil,
                        "GameTooltipTemplate")
  if ok and tip then IS.scanner = tip end
  return IS.scanner
end

-- The subtype printed on an equipped bag's CONTAINER_SLOTS tooltip line, or
-- nil when any step of the scan does not answer.
function IS.TooltipBagSubtype(inventoryId)
  local pattern = IS.SlotPattern()
  local tip = IS.Scanner()
  if not pattern or not tip then return nil end

  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")
  if not pcall(tip.SetInventoryItem, tip, "player", inventoryId) then
    return nil
  end

  local countOk, count = pcall(tip.NumLines, tip)
  count = countOk and tonumber(count) or 0
  if count > IS.MAX_TOOLTIP_LINES then count = IS.MAX_TOOLTIP_LINES end

  local line
  for line = 1, count do
    local region = U.G(IS.SCANNER_NAME .. "TextLeft" .. line)
    local text
    if region and type(region.GetText) == "function" then
      local textOk, value = pcall(region.GetText, region)
      if textOk then text = value end
    end

    if type(text) == "string" then
      local _, _, a, b = string.find(text, pattern)
      if a and b then
        -- Whichever capture is the number is the slot count, so a locale that
        -- puts the subtype first still reads correctly.
        if tonumber(a) then return b end
        return a
      end
    end
  end

  return nil
end

function IS.IsGeneralBag(bag)
  if bag == 0 or bag == IS.BANK_CONTAINER then return true end

  local inventoryId = IS.BagInventoryId(bag)
  if not inventoryId then return false end

  local ordinary = IS.OrdinaryBagSubtype()
  if not ordinary then return false end

  return IS.TooltipBagSubtype(inventoryId) == ordinary
end

-- ---------------------------------------------------------------------------
-- Ordering
-- ---------------------------------------------------------------------------
-- Category first, then the item's functional family, then its exact template.
-- The family keeps different ranks of the same kind together: healing potions
-- share a normalized "restores # health" tooltip signature, while mana potions
-- share a different one. Type/subtype/equipment slot precede that signature so
-- broad families such as gear still form useful local groups. Exact item id is
-- next, which keeps every stack of one item adjacent. Quality, name and the full
-- link are only deterministic tie-breakers inside those groups.
--
-- The key is built as one string rather than compared field by field so the
-- comparator is a plain `<` on a total order. table.sort raises "invalid order
-- function for sorting" when a comparator is inconsistent, and a hand-written
-- multi-field comparison over values that may each be nil is exactly how that
-- happens.
IS.familyCache = {}

-- Lowercase and erase changing quantities from a tooltip line. Keeping the
-- localized words is intentional: two effects written the same way in any
-- locale receive the same key without an English health/mana keyword table.
function IS.NormaliseSortText(value)
  if type(value) ~= "string" or value == "" then return "" end

  value = string.lower(value)
  value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
  value = string.gsub(value, "|r", "")
  value = string.gsub(value, "%d[%d%.,]*", "#")
  value = string.gsub(value, "%s+", " ")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  value = string.gsub(value, "|", "/")
  return value
end

-- A language-neutral fallback when the private tooltip cannot be populated.
-- Item ranks normally prefix a shared two-word family ("Major Healing Potion",
-- "Minor Healing Potion"), so the suffix still separates healing from mana.
function IS.NameFamily(name)
  name = IS.NormaliseSortText(name)
  local _, _, first, second = string.find(name, "([^%s]+)%s+([^%s]+)$")
  if first and second then return first .. " " .. second end
  return name
end

-- Effect text rather than item name is the useful definition of "same kind".
-- The scanner already exists for ordinary-bag detection; SetHyperlink simply
-- repopulates it between those scans. Results are cached because category view
-- relayouts often while the bag is open. Every operation is fail-closed and the
-- name-family fallback above remains usable if this documented method does not
-- answer on a particular item.
function IS.ItemFamily(link, name)
  if type(link) == "string" and IS.familyCache[link] then
    return IS.familyCache[link]
  end

  local lines = {}
  local tip = IS.Scanner()
  if tip and type(link) == "string" and link ~= "" then
    pcall(tip.ClearLines, tip)
    pcall(tip.SetOwner, tip, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")
    local populated = pcall(tip.SetHyperlink, tip, link)
    local countOk, count = pcall(tip.NumLines, tip)
    count = populated and countOk and tonumber(count) or 0
    if count > IS.MAX_TOOLTIP_LINES then count = IS.MAX_TOOLTIP_LINES end

    local line
    for line = 2, count do
      local region = U.G(IS.SCANNER_NAME .. "TextLeft" .. line)
      local text
      if region and type(region.GetText) == "function" then
        local textOk, value = pcall(region.GetText, region)
        if textOk then text = IS.NormaliseSortText(value) end
      end
      if text and text ~= "" then table.insert(lines, text) end
    end
  end

  local family
  if table.getn(lines) > 0 then
    family = table.concat(lines, " /")
  else
    family = IS.NameFamily(name)
  end

  if type(link) == "string" and link ~= "" then IS.familyCache[link] = family end
  return family
end

function IS.TemplateKey(link)
  if type(link) ~= "string" then return "item:0000000000" end
  local _, _, itemId = string.find(link, "item:(%d+)")
  return string.format("item:%010d", tonumber(itemId) or 0)
end

function IS.SortKey(order, link)
  local index = 99
  local quality, name, itemType, subType, equipLoc = 0, "", "", "", ""

  local ok, itemName, _, itemQuality, _, class, subclass, _, equipment =
    pcall(GetItemInfo, link)
  if ok then
    if type(itemName) == "string" then name = string.lower(itemName) end
    quality = tonumber(itemQuality) or 0
    itemType = IS.NormaliseSortText(class)
    subType = IS.NormaliseSortText(subclass)
    equipLoc = IS.NormaliseSortText(equipment)
  end

  local category = U.ItemCategoryFromLink(link)
  if category and order[category] then index = order[category] end

  local family = IS.ItemFamily(link, name)
  local template = IS.TemplateKey(link)

  -- 9 - quality so that Legendary sorts above Poor once kind and exact item
  -- have already kept related and identical items together.
  return string.format("%03d|", index) .. itemType .. "|" .. subType .. "|" ..
    equipLoc .. "|" .. family .. "|" .. template .. "|" ..
    string.format("%02d|", 9 - quality) .. name .. "|" .. tostring(link or "")
end

function IS.CategoryOrder()
  if IS.categoryOrder then return IS.categoryOrder end

  local order = {}
  local list = U.ItemCategoryOrder()
  local i
  for i = 1, table.getn(list) do order[list[i]] = i end
  IS.categoryOrder = order
  return order
end

-- Category view uses this exact key to arrange its buttons without moving the
-- underlying items. Physical bag and bank sorting call IS.SortKey directly
-- with the same category order, so the two presentations cannot drift.
function U.ItemSortKey(link)
  return IS.SortKey(IS.CategoryOrder(), link)
end

-- ---------------------------------------------------------------------------
-- Plan
-- ---------------------------------------------------------------------------
-- positions is every sortable slot of every sortable container, in the order
-- the containers were given; desired[i] is the item link that belongs at
-- positions[i]. Because positions runs straight through the containers and
-- desired is packed from index 1, the whole set is filled as though it were
-- one bag: the first category lands in the backpack's first slots and the
-- items spill on into the next container.
--
-- Both are a snapshot. If the bags change while the run drains, the plan stops
-- matching what is there; the run rebuilds it through IS.Replan rather than
-- shuffling against a stale one.
--
-- excluded: optional set of container ids to leave out, which is how a
-- container that refused a drop is taken back out of the pool mid-run.
function IS.Plan(bagIds, excluded)
  local order = IS.CategoryOrder()
  local positions, items = {}, {}
  local i

  for i = 1, table.getn(bagIds) do
    local bag = bagIds[i]
    if not (excluded and excluded[bag]) and IS.IsGeneralBag(bag) then
      -- Not GetContainerNumSlots directly: the main bank pane reports zero for
      -- itself, and U.ContainerSlotCount is where that is corrected.
      local n = U.ContainerSlotCount(bag)

      local slot
      for slot = 1, n do
        table.insert(positions, { bag = bag, slot = slot })

        local link = U.ContainerSlotLink(bag, slot)
        local key = IS.ItemKey(link)
        if key then
          table.insert(items, { key = key, sort = IS.SortKey(order, link) })
        end
      end
    end
  end

  table.sort(items, function(a, b) return a.sort < b.sort end)

  local desired = {}
  for i = 1, table.getn(items) do desired[i] = items[i].key end

  return positions, desired
end

-- ---------------------------------------------------------------------------
-- Reading the world back
-- ---------------------------------------------------------------------------
-- Slots are read through core/compat.lua's readers, which are one container
-- call for every container this engine is given, main bank pane included --
-- banksort.actual_sequence.v1 measured that pane answering GetContainerItemLink
-- correctly for every occupied slot.
--
-- Identity is the item string, not the hyperlink. The client's own GetItemInfo
-- documentation notes it returns the raw item:id:enchant:rand:suffix form
-- rather than a coloured link, so more than one shape is in circulation, and
-- comparing item strings means a colour prefix or a display name cannot make a
-- landed swap look like it never happened.
function IS.ItemKey(link)
  if type(link) ~= "string" or link == "" then return nil end

  local _, _, itemString = string.find(link, "(item:%d+:%d*:%d*:%d*)")
  if itemString then return itemString end

  local _, _, itemId = string.find(link, "item:(%d+)")
  if itemId then return "item:" .. itemId end

  return link
end

function IS.KeyAt(position)
  return IS.ItemKey(U.ContainerSlotLink(position.bag, position.slot))
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

-- Put back whatever a failed step left on the cursor, into the slot it came
-- out of. This is the recovery IS.Finish performs, needed separately because a
-- run that recovers and carries on must not reach the next swap holding
-- something. Answers whether the cursor is actually empty afterwards; a run
-- that cannot put an item down has to end rather than continue.
function IS.ReleaseCursor(run)
  if U.CursorHasItem() and run.holding then
    U.PickupContainerSlot(run.holding.bag, run.holding.slot)
  end
  if U.CursorHasItem() then pcall(ClearCursor) end

  run.holding = nil
  return not U.CursorHasItem()
end

-- Rebuild the plan against the containers as they are now, optionally dropping
-- one container from the pool.
--
-- If a drop does not land, its container is removed here and the run finishes
-- with the remaining containers instead of stopping on the refusal. This is a
-- second line of defence after the positive ordinary-bag test above, and also
-- absorbs an ordinary plan going stale -- a looted item, or two partial stacks
-- merging on a drop instead of swapping -- which used to end a run outright.
--
-- Bounded, because a run that cannot make progress must stop rather than
-- rearrange the bags indefinitely. The backpack and the main bank pane are
-- never dropped: they are the containers that take anything, and a pool with
-- neither is not worth continuing.
function IS.Replan(run, dropBag)
  if run.replans >= IS.MAX_REPLANS then
    IS.Finish("FAILED")
    return false
  end
  run.replans = run.replans + 1

  if dropBag and dropBag ~= 0 and dropBag ~= IS.BANK_CONTAINER then
    run.excluded[dropBag] = true
  end

  local positions, desired = IS.Plan(run.bagIds, run.excluded)
  if table.getn(positions) == 0 then
    IS.Finish(run.moves > 0 and "DONE" or "NOTHING")
    return false
  end

  run.positions = positions
  run.desired = desired
  run.index = 1
  run.pending = nil
  -- A staged swap's legs are addressed against the plan that started it; a new
  -- plan means the sequence is abandoned and re-derived from what is there now.
  run.staged = nil
  run.retries = 0
  run.waits = 0
  return true
end

-- ---------------------------------------------------------------------------
-- One swap
--
-- Documented behaviour: a pickup lifts the slot's item; a second pickup on an
-- occupied slot drops what is held and lifts what was there. So a full swap is
-- lift source, drop into destination, drop the displaced item back into source.
-- Each stage is checked against the cursor rather than assumed.
--
-- The second return is the container to suspect when a stage did not work, so
-- the caller can take that container out of the pool. The last branch cannot
-- tell a destination that refused the drop from a source that refused the
-- displaced item back, and names the destination, because the first is by far
-- the likelier of the two -- source had an item taken out of it a moment
-- earlier.
-- ---------------------------------------------------------------------------
function IS.Swap(run, src, dst)
  if U.CursorHasItem() then return false end

  run.holding = src
  if not U.PickupContainerSlot(src.bag, src.slot) then return false, src.bag end

  -- The lift itself did nothing: stop here rather than dropping a nil cursor
  -- onto an occupied slot.
  if not U.CursorHasItem() then return false, src.bag end

  U.PickupContainerSlot(dst.bag, dst.slot)

  -- Destination was occupied, so its item is now held; it belongs in source.
  if U.CursorHasItem() then
    U.PickupContainerSlot(src.bag, src.slot)
  end

  -- Still holding something: leave run.holding set so the recovery above knows
  -- which slot to put it back into. Clearing it here would strand the item.
  if U.CursorHasItem() then return false, dst.bag end

  run.holding = nil
  return true
end

-- ---------------------------------------------------------------------------
-- A swap the client will not make directly
--
-- The main bank pane cannot exchange with itself: every lift/drop pair was
-- measured and all four are refused (U.ContainerSlotsCanExchange carries the
-- routes). Since almost every bank item starts in that pane, that is most of a
-- bank sort, so the engine performs those swaps in three legal legs through
-- one borrowed empty slot -- a purchased bank bag's, in practice:
--
--   1  source -> stage       source is emptied
--   2  stage  -> position    lands the item; position's old item is displaced
--                            onto the cursor and IS.Swap puts it back in stage
--   3  stage  -> source      returns the displaced item, freeing stage again
--
-- Leg 3 does not exist when position was empty, which IS.StagedSwap detects by
-- finding nothing to carry rather than by remembering what it saw earlier.
--
-- Each leg is an ordinary IS.Swap between containers the client accepts, so
-- each is verified against the destination through run.pending exactly like a
-- direct swap. The sequence is therefore as safe as the rest of the engine:
-- if a leg does not land, the run recovers the cursor and replans instead of
-- issuing the next one.
--
-- The stage is borrowed, not consumed -- it is empty again by the end of the
-- sequence -- but it must be free at the start, so a bank with no free slot
-- outside the main pane cannot be sorted at all. That is reported rather than
-- retried, because no amount of replanning creates the slot.
-- ---------------------------------------------------------------------------
function IS.CanExchange(from, to)
  return U.ContainerSlotsCanExchange(from.bag, to.bag) and true or false
end

-- The two ends of the leg the sequence is currently on, or nil when it is done.
function IS.StagedLeg(staged)
  if staged.phase == 1 then return staged.source, staged.stage end
  if staged.phase == 2 then return staged.stage, staged.position end
  if staged.phase == 3 then return staged.stage, staged.source end
  return nil
end

-- An empty slot to borrow: in the pool, not one of the two ends, and one the
-- client will exchange with both of them. Searched fresh for each sequence
-- because the free slots move as the run progresses.
function IS.StagingSlot(run, source, position)
  local total = table.getn(run.positions)
  local i

  for i = 1, total do
    local slot = run.positions[i]
    local isEnd = (slot.bag == source.bag and slot.slot == source.slot)
      or (slot.bag == position.bag and slot.slot == position.slot)

    if not isEnd and IS.CanExchange(source, slot) and
       IS.CanExchange(slot, position) and not IS.KeyAt(slot) and
       not IS.Locked(slot) then
      return slot
    end
  end

  return nil
end

-- Drive the sequence one leg forward. True means the sequence is finished and
-- the caller may carry on with the plan this tick; false means a move is in
-- flight, or the run has ended, and the tick must stop.
function IS.StagedSwap(run)
  local staged = run.staged
  local from, to = IS.StagedLeg(staged)

  if not from then
    run.staged = nil
    return true
  end

  local key = IS.KeyAt(from)
  if not key then
    -- Nothing to carry. On the last leg that is the expected end of a move
    -- into an empty slot; earlier it means the containers changed underneath.
    run.staged = nil
    if staged.phase >= 3 then return true end
    IS.Replan(run)
    return false
  end

  if IS.Locked(from) or IS.Locked(to) then
    run.waits = run.waits + 1
    if run.waits > IS.TickBudget(IS.LOCK_TIMEOUT) then IS.Finish("FAILED") end
    return false
  end
  run.waits = 0

  local swapped, suspect = IS.Swap(run, from, to)
  if not swapped then
    run.staged = nil
    if IS.ReleaseCursor(run) then
      IS.Replan(run, suspect)
    else
      IS.Finish("FAILED")
    end
    return false
  end

  run.pending = { dst = to, key = key }
  staged.phase = staged.phase + 1
  return false
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
    if IS.KeyAt(run.pending.dst) == run.pending.key then
      run.pending = nil
      run.retries = 0
      run.moves = run.moves + 1
    else
      run.retries = run.retries + 1
      if run.retries > IS.TickBudget(IS.SWAP_TIMEOUT) then
        -- The destination never took the item. Suspect that container, drop it
        -- from the pool and sort the rest rather than ending the run here.
        local dst = run.pending.dst
        run.pending = nil
        run.staged = nil
        if IS.ReleaseCursor(run) then
          IS.Replan(run, dst.bag)
        else
          IS.Finish("FAILED")
        end
      end
      return
    end
  end

  -- A staged swap owns the run until its legs are done: its middle legs leave
  -- the containers in a state the plan below would misread as an unrelated
  -- item needing to be moved.
  if run.staged then
    if not IS.StagedSwap(run) then return end
  end

  local total = table.getn(run.positions)

  while run.index <= total do
    local position = run.positions[run.index]
    local want = run.desired[run.index]
    local have = IS.KeyAt(position)

    -- Past the last item: everything from here on should be empty, and an
    -- occupied slot means the plan no longer matches the bags.
    if not want then
      if have then
        -- More items than the plan knew about: the containers changed under
        -- the run, so plan against what is there now.
        IS.Replan(run)
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
        if IS.KeyAt(run.positions[j]) == want then
          source = run.positions[j]
          break
        end
      end

      if not source then
        -- The plan asked for something that is no longer in the bags: the
        -- contents changed under the run.
        IS.Replan(run)
        return
      end

      -- A slot the server is still settling cannot be moved. Wait for it
      -- rather than issuing a swap that is certain to be refused. Waiting has
      -- its own budget, and a longer one than a swap gets: a lock clears when
      -- the server answers, so waiting costs nothing but time, while the swap
      -- budget decides when to suspect a container and drop it from the pool.
      if IS.Locked(source) or IS.Locked(position) then
        run.waits = run.waits + 1
        if run.waits > IS.TickBudget(IS.LOCK_TIMEOUT) then
          IS.Finish("FAILED")
        end
        return
      end
      run.waits = 0

      -- Two main-bank slots cannot exchange on this client, and that is most
      -- of a bank sort. Borrow a free slot and do it in three legal legs.
      if not IS.CanExchange(source, position) then
        local stage = IS.StagingSlot(run, source, position)
        if not stage then
          IS.Finish("NOSTAGE")
          return
        end

        run.staged = {
          source = source,
          position = position,
          stage = stage,
          phase = 1,
        }
        IS.StagedSwap(run)
        return
      end

      local swapped, suspect = IS.Swap(run, source, position)
      if not swapped then
        if IS.ReleaseCursor(run) then
          IS.Replan(run, suspect)
        else
          IS.Finish("FAILED")
        end
        return
      end

      run.pending = { dst = position, key = want }
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

-- Shared with core/itemstack.lua, which has to agree with this engine on what
-- counts as the same item and which bags are ordinary.
U.ContainerItemKey = IS.ItemKey
U.IsGeneralContainer = IS.IsGeneralBag

-- bagIds: the containers to sort, pooled and filled as one bag in this order.
--         Retained by the run, because a container that turns out to refuse a
--         drop is dropped from the pool and the plan rebuilt from this list.
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

  -- A stack merge (core/itemstack.lua) holds the same cursor.
  if type(U.BagStackActive) == "function" and U.BagStackActive() then
    U.Print(U.L("ITEMS_BUSY"))
    return false
  end

  -- Sorting drives the cursor. Starting with something already on it would
  -- drop that item into the first slot the run touches.
  if U.CursorHasItem() then
    U.Print(IS.Message(prefix, "CURSOR"))
    return false
  end

  local excluded = {}
  local positions, desired = IS.Plan(bagIds, excluded)
  if table.getn(positions) == 0 then
    U.Print(IS.Message(prefix, "NOTHING"))
    return false
  end

  IS.run = {
    bagIds = bagIds,
    excluded = excluded,
    positions = positions,
    desired = desired,
    index = 1,
    retries = 0,
    waits = 0,
    replans = 0,
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
