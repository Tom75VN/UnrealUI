-- unrealUI :: core/itemstack.lua
--
-- Stack merging: tops partial stacks of the same item up from other partial
-- stacks of it, inside one set of containers. It never sorts and never moves
-- an item to a container outside the set it was given -- modules/bags.lua
-- passes the carried bags, modules/bank.lua the main bank pane plus its
-- purchased bank bags, so a bag merge cannot reach the bank or the reverse.
--
-- It sits beside core/itemsort.lua and follows the same safety model, for the
-- same reason: PickupContainerItem, and the merge a drop onto a partial stack
-- of the same item performs, are DOCUMENTED_NOT_RUNTIME_VERIFIED here
-- (documentation.json / global:Container:PickupContainerItem). Every move is
-- therefore verified against the containers themselves, and the first move
-- that does not land ends the run with the cursor put back.
--
-- Unlike the sort, there is no plan. Each move is chosen from the containers
-- as they are on that tick, so a looted item or a move the player makes during
-- a run changes what is merged next instead of invalidating a snapshot.
--
-- Max stack size is GetItemInfo's seventh return, "stackCount (max stack)"
-- (documentation.json / global:Item:GetItemInfo, documented, not runtime
-- verified). An item the call does not answer for is left alone.
--
-- THE MAIN BANK PANE
--
-- Two measured limits shape everything bank-side:
--
--   * knowledge.json / bank.stack_count_region_not_visible: the pane reports
--     count 0 for every slot, so a pane stack's size cannot be read. The
--     quantities modules/bankcount.lua infers are only used to skip a stack
--     already known to be full; an inferred number never decides a move.
--   * U.ContainerSlotsCanExchange (core/compat.lua): no route moves an item
--     from one pane slot to another. Pane <-> bank bag works both ways.
--
-- So a merge is only ever performed INTO a readable bank-bag slot, where its
-- result can be measured, and the only drop into the pane is into an EMPTY
-- slot, the bank-bag -> main-pane route bankinv measured as working.
-- Partial stacks that exist only in the pane are gathered through one
-- borrowed empty bank-bag slot (the "stage"): one pane stack is moved into it,
-- the others of that item are merged onto it until it is full or none remain,
-- and it goes back into the pane slot it came from. A bank with no free slot
-- in an ordinary bank bag cannot merge pane-only stacks, and says so.

local U = UnrealUI

-- One table rather than a top-level local per member, per the local-budget rule
-- in .claude/rules/unreal-ui.md.
local ST = {}

ST.UPDATE_ID = "bags.stack"
ST.PREFIX = "BAGS_STACK"
ST.BANK_CONTAINER = -1

-- Pace and patience: the same reasoning as core/itemsort.lua's PACE note. At
-- most one move is in flight, and the next is not issued until the previous
-- one is read back, so the interval only bounds the dead time between moves.
ST.INTERVAL = 0.03
ST.MOVE_TIMEOUT = 1.0  -- seconds a move may take to show in the containers
ST.LOCK_TIMEOUT = 3.0  -- seconds a slot may stay locked by the server
ST.MAX_MOVES = 400     -- hard stop; a real bag set needs a small fraction

ST.run = nil

function ST.TickBudget(seconds)
  local ticks = math.floor(seconds / ST.INTERVAL)
  if ticks < 1 then ticks = 1 end
  return ticks
end

function ST.Message(prefix, suffix)
  return U.L((prefix or ST.PREFIX) .. "_" .. suffix)
end

function ST.SlotId(bag, slot)
  return bag .. ":" .. slot
end

-- ---------------------------------------------------------------------------
-- Reading the containers
-- ---------------------------------------------------------------------------
function ST.MaxStack(run, key, link)
  local cached = run.maxStack[key]
  if cached ~= nil then return cached end

  local max = 0
  local ok, _, _, _, _, _, _, stackCount = pcall(GetItemInfo, link)
  if ok then max = tonumber(stackCount) or 0 end

  run.maxStack[key] = max
  return max
end

-- One pass over every slot of the run's containers.
--
--   groups[key]  { max, readable = {entry...}, pane = {entry...} }, only for
--                stackable items, entries in container order
--   keys         the group keys in the order first seen
--   empties      empty slots in ordinary readable containers (stage candidates)
--   locked       true when any occupied slot is locked
--
-- entry: { bag, slot, key, count, locked }. count is nil for a pane slot.
function ST.Snapshot(run)
  local snap = { groups = {}, keys = {}, empties = {}, locked = false }
  local i

  for i = 1, table.getn(run.bagIds) do
    local bag = run.bagIds[i]
    local pane = bag == ST.BANK_CONTAINER
    local n = U.ContainerSlotCount(bag)

    local slot
    for slot = 1, n do
      local link = U.ContainerSlotLink(bag, slot)
      local key = U.ContainerItemKey(link)
      local _, count, locked = U.ContainerSlotInfo(bag, slot)

      if not key then
        if not pane and run.general[bag] and not locked then
          table.insert(snap.empties, { bag = bag, slot = slot })
        end
      else
        if locked then snap.locked = true end

        count = tonumber(count)
        if pane or (count and count <= 0) then count = nil end

        local max = ST.MaxStack(run, key, link)
        -- A readable slot whose count did not answer is left out entirely: a
        -- merge into or out of it could not be measured.
        if max > 1 and (pane or count) then
          local group = snap.groups[key]
          if not group then
            group = { max = max, readable = {}, pane = {} }
            snap.groups[key] = group
            table.insert(snap.keys, key)
          end

          local entry = { bag = bag, slot = slot, key = key, count = count,
                          locked = locked and true or false }
          if pane then
            table.insert(group.pane, entry)
          else
            table.insert(group.readable, entry)
          end
        end
      end
    end
  end

  return snap
end

function ST.Find(snap, bag, slot)
  local k
  for k = 1, table.getn(snap.keys) do
    local group = snap.groups[snap.keys[k]]
    local lists = { group.readable, group.pane }
    local l
    for l = 1, 2 do
      local j
      for j = 1, table.getn(lists[l]) do
        local e = lists[l][j]
        if e.bag == bag and e.slot == slot then return e, group end
      end
    end
  end
  return nil
end

-- A pane slot this run should not try to fill: measured full when it came back
-- from the stage, or inferred full by modules/bankcount.lua.
function ST.PaneFull(run, entry, max)
  if run.full[ST.SlotId(entry.bag, entry.slot)] == entry.key then return true end

  if type(U.BankSlotStackCount) == "function" then
    local ok, known = pcall(U.BankSlotStackCount, entry.bag, entry.slot)
    known = ok and tonumber(known) or nil
    if known and known >= max then return true end
  end

  return false
end

function ST.FirstEmptyPaneSlot(run)
  local n = U.ContainerSlotCount(ST.BANK_CONTAINER)
  local slot
  for slot = 1, n do
    if not U.ContainerSlotLink(ST.BANK_CONTAINER, slot) then
      return { bag = ST.BANK_CONTAINER, slot = slot }
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Choosing the next move
-- ---------------------------------------------------------------------------
-- move: { src, dst, key, kind }
--   kind "merge"   dst is a readable partial stack of key
--   kind "stage"   pane stack -> empty readable slot, which becomes the stage
--   kind "return"  stage -> empty pane slot
function ST.NextMove(run, snap)
  local k

  -- 1  An open stage finishes before anything else is considered.
  if run.stage then
    local stage, group = ST.Find(snap, run.stage.bag, run.stage.slot)
    if not stage or stage.key ~= run.stage.key then
      -- Emptied or replaced from outside the run; nothing left to return.
      run.stage = nil
    else
      if stage.count < group.max then
        local j
        for j = 1, table.getn(group.pane) do
          local m = group.pane[j]
          if not ST.PaneFull(run, m, group.max) then
            return { src = m, dst = stage, key = stage.key, kind = "merge" }
          end
        end
      end

      local target = run.stage.origin
      if U.ContainerSlotLink(target.bag, target.slot) then
        target = ST.FirstEmptyPaneSlot(run)
      end
      if target then
        return { src = stage, dst = target, key = stage.key, kind = "return",
                 full = stage.count >= group.max }
      end
      -- No free pane slot: the stack stays in the bank bag, still in the bank.
      run.stage = nil
    end
  end

  -- 2  Two readable partial stacks: fill the first from the last.
  for k = 1, table.getn(snap.keys) do
    local group = snap.groups[snap.keys[k]]
    local partial = {}
    local j
    for j = 1, table.getn(group.readable) do
      local e = group.readable[j]
      if e.count < group.max then table.insert(partial, e) end
    end
    if table.getn(partial) >= 2 then
      return { src = partial[table.getn(partial)], dst = partial[1],
               key = snap.keys[k], kind = "merge" }
    end
  end

  -- 3  A pane stack onto a readable partial stack of the same item.
  for k = 1, table.getn(snap.keys) do
    local group = snap.groups[snap.keys[k]]
    local dst
    local j
    for j = 1, table.getn(group.readable) do
      if group.readable[j].count < group.max then
        dst = group.readable[j]
        break
      end
    end
    if dst then
      for j = 1, table.getn(group.pane) do
        local m = group.pane[j]
        if not ST.PaneFull(run, m, group.max) then
          return { src = m, dst = dst, key = snap.keys[k], kind = "merge" }
        end
      end
    end
  end

  -- 4  Two or more pane stacks that may be partial: gather them on a stage.
  for k = 1, table.getn(snap.keys) do
    local group = snap.groups[snap.keys[k]]
    local open = {}
    local j
    for j = 1, table.getn(group.pane) do
      local m = group.pane[j]
      if not ST.PaneFull(run, m, group.max) then table.insert(open, m) end
    end
    if table.getn(open) >= 2 then
      local stage = snap.empties[1]
      if not stage then
        run.needsStage = true
      else
        return { src = open[1], dst = stage, key = snap.keys[k],
                 kind = "stage" }
      end
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- Finishing
-- ---------------------------------------------------------------------------
function ST.Finish(suffix)
  local run = ST.run
  ST.run = nil
  U.UnregisterUpdate(ST.UPDATE_ID)

  if U.CursorHasItem() and run and run.holding then
    U.PickupContainerSlot(run.holding.bag, run.holding.slot)
  end
  if U.CursorHasItem() then pcall(ClearCursor) end

  if suffix then U.Print(ST.Message(run and run.prefix, suffix)) end
  if run and type(run.onFinish) == "function" then pcall(run.onFinish) end
end

-- The outcome when no move is left.
function ST.Complete(run)
  if run.needsStage then
    ST.Finish("NOSTAGE")
  elseif run.moves > 0 then
    ST.Finish("DONE")
  else
    ST.Finish("NOTHING")
  end
end

-- ---------------------------------------------------------------------------
-- Issuing and verifying one move
-- ---------------------------------------------------------------------------
-- Lift the source and drop it on the destination. Answers whether the cursor
-- ended empty; a false leaves whatever is held for ST.Finish to put back.
function ST.Issue(run, move)
  if U.CursorHasItem() then return false end

  run.holding = move.src
  if not U.PickupContainerSlot(move.src.bag, move.src.slot) then return false end
  if not U.CursorHasItem() then return false end

  U.PickupContainerSlot(move.dst.bag, move.dst.slot)
  if U.CursorHasItem() then return false end

  run.holding = nil
  return true
end

-- True once the move is visible in the containers. A merge is measured on its
-- readable destination growing; a stage or return on the source emptying and
-- the destination holding the item.
function ST.Landed(pending)
  local move = pending.move
  local dstKey = U.ContainerItemKey(U.ContainerSlotLink(move.dst.bag,
                                                       move.dst.slot))
  if dstKey ~= move.key then return false end

  if move.kind == "merge" then
    local _, count = U.ContainerSlotInfo(move.dst.bag, move.dst.slot)
    count = tonumber(count)
    return count ~= nil and count > pending.dstCount
  end

  return U.ContainerSlotLink(move.src.bag, move.src.slot) == nil
end

function ST.Locked(position)
  local _, _, locked = U.ContainerSlotInfo(position.bag, position.slot)
  return locked and true or false
end

function ST.Settle(run)
  local pending = run.pending
  local move = pending.move

  if ST.Locked(move.src) or ST.Locked(move.dst) then
    run.waits = run.waits + 1
    if run.waits > ST.TickBudget(ST.LOCK_TIMEOUT) then ST.Finish("FAILED") end
    return false
  end
  run.waits = 0

  if not ST.Landed(pending) then
    run.retries = run.retries + 1
    if run.retries > ST.TickBudget(ST.MOVE_TIMEOUT) then ST.Finish("FAILED") end
    return false
  end

  run.pending = nil
  run.retries = 0
  run.moves = run.moves + 1

  if move.kind == "stage" then
    run.stage = { bag = move.dst.bag, slot = move.dst.slot, key = move.key,
                  origin = { bag = move.src.bag, slot = move.src.slot } }
  elseif move.kind == "return" then
    run.stage = nil
    if move.full then
      run.full[ST.SlotId(move.dst.bag, move.dst.slot)] = move.key
    end
  end

  return true
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------
function ST.Step()
  local run = ST.run
  if not run then
    U.UnregisterUpdate(ST.UPDATE_ID)
    return
  end

  if run.pending then
    if not ST.Settle(run) then return end
  end

  if run.moves >= ST.MAX_MOVES then
    ST.Finish("FAILED")
    return
  end

  local snap = ST.Snapshot(run)
  run.needsStage = false
  local move = ST.NextMove(run, snap)
  if not move then
    -- A slot still settling can hide a merge that is about to become
    -- possible; wait for it before calling the run complete.
    if snap.locked then
      run.waits = run.waits + 1
      if run.waits <= ST.TickBudget(ST.LOCK_TIMEOUT) then return end
    end
    ST.Complete(run)
    return
  end

  if move.src.locked or move.dst.locked or ST.Locked(move.src) or
     ST.Locked(move.dst) then
    run.waits = run.waits + 1
    if run.waits > ST.TickBudget(ST.LOCK_TIMEOUT) then ST.Finish("FAILED") end
    return
  end
  run.waits = 0

  local _, dstCount = U.ContainerSlotInfo(move.dst.bag, move.dst.slot)
  local pending = { move = move, dstCount = tonumber(dstCount) or 0 }

  if not ST.Issue(run, move) then
    ST.Finish("FAILED")
    return
  end

  run.pending = pending
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------
function U.BagStackActive()
  return ST.run and true or false
end

-- bagIds: the containers to merge within. Items never leave this set.
-- options, all optional: onFinish, prefix (default "BAGS_STACK"; the bank
-- passes "BANK_STACK") and owner, exactly as U.SortBags takes them.
function U.StackBags(bagIds, options)
  if type(bagIds) ~= "table" then return false end

  options = options or {}
  local prefix = options.prefix or ST.PREFIX

  -- One cursor for the whole addon: a sort and a merge cannot run together.
  if ST.run or U.BagSortActive() then
    U.Print(U.L("ITEMS_BUSY"))
    return false
  end

  if U.CursorHasItem() then
    U.Print(ST.Message(prefix, "CURSOR"))
    return false
  end

  -- Only ordinary bags may lend an empty slot as the stage: a specialty bag
  -- refuses most items. Asked once per run, because the answer is a tooltip
  -- scan and the bag set cannot change while the run holds the cursor.
  local general = {}
  local i
  for i = 1, table.getn(bagIds) do
    local bag = bagIds[i]
    general[bag] = U.IsGeneralContainer(bag) and true or false
  end

  local run = {
    bagIds = bagIds,
    general = general,
    maxStack = {},
    full = {},
    moves = 0,
    retries = 0,
    waits = 0,
    onFinish = options.onFinish,
    prefix = prefix,
    owner = options.owner,
  }

  local snap = ST.Snapshot(run)
  if not ST.NextMove(run, snap) then
    U.Print(ST.Message(prefix, run.needsStage and "NOSTAGE" or "NOTHING"))
    return false
  end

  ST.run = run
  U.RegisterUpdate(ST.UPDATE_ID, ST.INTERVAL, ST.Step)
  return true
end

-- End the caller's own run early and silently. The bank calls this when its
-- window hides, for the reason given at U.StopSort. A stage open at that moment
-- leaves its stack in the bank bag -- still in the bank, never lost.
function U.StopStack(owner)
  if not ST.run then return false end
  if owner ~= nil and ST.run.owner ~= owner then return false end

  ST.Finish(nil)
  return true
end
