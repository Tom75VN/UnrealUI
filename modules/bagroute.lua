-- unrealUI :: modules/bagroute.lua
--
-- Automatic specialty-bag routing (user request, 2026-09-27). While the bag
-- category view is on, the view files each equipped specialty bag (herb,
-- enchanting, soul, quiver, ammo pouch...) as its own section. An item that
-- arrives in the carried bags and belongs in one of those bags is moved there
-- from the ordinary bag it landed in.
--
-- "Arrives" means the carried total of that item id went up: looted, bought,
-- taken from the mail, the bank or a trade. A move inside the bags never
-- changes a total, so an item the player deliberately takes out of a
-- specialty bag is left where they put it.
--
-- Which bag takes what is modules/bagcategoryview.lua's rule
-- (U.BagSpecialtyAccepts), shared with its empty-slot proxy. Only empty
-- specialty slots are used; stacks are not merged here (the stack button
-- does that).
--
-- The move is core/itemsort.lua's primitive and discipline: PickupContainerItem
-- twice, one move in flight, and the destination read back before the next
-- one. A drop the client refuses is put back where it came from, and that
-- item is not offered to that kind of bag again this session.

local U = UnrealUI

local BR = U.RegisterModule("bagroute")

-- One table rather than a top-level local per member (local-budget rule).
local R = {
  UPDATE_ID = "bags.route",
  INTERVAL = 0.1,
  MOVE_TIMEOUT = 1.5,   -- seconds a move may take to show in its destination
  -- Seconds after a loading screen during which bag contents are only
  -- recorded: the client refills the containers then, and that must not read
  -- as a bag full of new items.
  SETTLE = 5,
  BAGS = { 0, 1, 2, 3, 4 },
  baseline = nil,       -- [itemId] = carried count at the last complete read
  armAt = 0,
  dirty = true,
  route = {},           -- [itemId] = true: arrived, still to be routed
  -- A just-looted slot can stay locked for a moment, so the queue is kept this
  -- long after the last arrival rather than dropped on the first empty pass.
  ROUTE_WINDOW = 3,
  routeUntil = 0,
  refused = {},         -- [bagLabel .. ":" .. itemId] = true
  pending = nil,        -- { src, dst, id, label, deadline }
}

function R.Now()
  local ok, now = pcall(GetTime)
  return (ok and tonumber(now)) or 0
end

function R.Wanted()
  return type(U.BagsEnabled) == "function" and U.BagsEnabled() and
         type(U.BagsCategoriesEnabled) == "function" and
         U.BagsCategoriesEnabled() and
         type(U.BagSpecialtyAccepts) == "function"
end

function R.Busy()
  if U.CursorHasItem() then return true end
  if type(U.BagSortActive) == "function" and U.BagSortActive() then
    return true
  end
  if type(U.BagStackActive) == "function" and U.BagStackActive() then
    return true
  end
  return false
end

-- Carried count per item id, and one link per id for the compatibility test.
-- A slot whose link the client has not delivered yet is skipped rather than
-- failing the whole read: one unreadable item used to stop every scan, so
-- nothing was ever routed. At worst that item reads as an arrival once its
-- link comes in, and it is only moved if a specialty bag takes it.
function R.Totals()
  local totals, links = {}, {}
  local i
  for i = 1, table.getn(R.BAGS) do
    local bag = R.BAGS[i]
    local n = U.ContainerSlotCount(bag)
    local slot
    for slot = 1, n do
      local texture, count = U.ContainerSlotInfo(bag, slot)
      if texture then
        local link = U.ContainerSlotLink(bag, slot)
        local id = U.ItemLinkId(link)
        if id then
          totals[id] = (totals[id] or 0) + (tonumber(count) or 1)
          links[id] = link
        end
      end
    end
  end
  return totals, links
end

-- Would any equipped specialty bag take this item at all? Asked once per
-- arrival, so ordinary loot never enters the queue.
function R.AnyBagAccepts(special, id, link)
  local category = U.ItemCategoryFromLink(link)
  local k
  for k = 1, table.getn(special) do
    local entry = special[k]
    local accepts = not R.refused[entry.label .. ":" .. id] and
       U.BagSpecialtyAccepts(entry.label, entry.accepted, category, link)
    R.Trace("arrival " .. tostring(link) .. " category=" .. tostring(category) ..
            " bag " .. entry.bag .. " (" .. entry.label .. ") accepts=" ..
            tostring(accepts and true or false) ..
            " free=" .. table.getn(entry.free))
    if accepts then return true end
  end
  return false
end

-- /uui debug output: each routing decision, so a test in game shows which
-- step stops an item.
function R.Trace(message)
  U.Debug("bags route: " .. tostring(message))
end

-- Record the carried totals and queue every item id that went up and has a
-- specialty bag to go to.
function R.Scan()
  local totals, links = R.Totals()
  if not totals then return false end

  local before = R.baseline
  R.baseline = totals
  if not before then return true end
  if R.Now() < R.armAt then
    R.Trace("settling after loading screen; arrivals ignored")
    return true
  end
  if not R.Wanted() then return true end

  local special
  local id, count
  for id, count in pairs(totals) do
    if count > (before[id] or 0) then
      special = special or R.SpecialBags()
      if table.getn(special) == 0 then
        R.Trace("arrival but no equipped specialty bag was recognised")
        return true
      end
      if R.AnyBagAccepts(special, id, links[id]) then
        R.route[id] = true
        R.routeUntil = R.Now() + R.ROUTE_WINDOW
      end
    end
  end
  return true
end

function R.Locked(bag, slot)
  local _, _, locked = U.ContainerSlotInfo(bag, slot)
  return locked and true or false
end

-- Every equipped specialty bag: its label, the categories already inside it
-- (the fail-closed rule for a bag type the client does not list), and its
-- free, unlocked slots.
function R.SpecialBags()
  local list = {}
  local i
  for i = 2, table.getn(R.BAGS) do
    local bag = R.BAGS[i]
    local label = type(U.BagSpecialtyLabel) == "function" and
                  U.BagSpecialtyLabel(bag) or nil
    if label then
      local entry = { bag = bag, label = label, accepted = {}, free = {} }
      local slot
      for slot = 1, U.ContainerSlotCount(bag) do
        local key = U.ItemCategoryForSlot(bag, slot)
        if key == "empty" then
          if not R.Locked(bag, slot) then table.insert(entry.free, slot) end
        else
          entry.accepted[key] = true
        end
      end
      table.insert(list, entry)
    end
  end
  return list
end

-- The next move, or nil when nothing queued can go anywhere.
function R.NextMove()
  if not next(R.route) then return nil end

  local special = R.SpecialBags()
  if table.getn(special) == 0 then return nil end

  local i
  for i = 1, table.getn(R.BAGS) do
    local bag = R.BAGS[i]
    if U.IsGeneralContainer(bag) then
      local slot
      for slot = 1, U.ContainerSlotCount(bag) do
        local link = U.ContainerSlotLink(bag, slot)
        local id = U.ItemLinkId(link)
        if id and R.route[id] and not R.Locked(bag, slot) then
          local category = U.ItemCategoryFromLink(link)
          local k
          for k = 1, table.getn(special) do
            local entry = special[k]
            if table.getn(entry.free) > 0 and
               not R.refused[entry.label .. ":" .. id] and
               U.BagSpecialtyAccepts(entry.label, entry.accepted,
                                     category, link) then
              return {
                src = { bag = bag, slot = slot },
                dst = { bag = entry.bag, slot = entry.free[1] },
                id = id,
                label = entry.label,
              }
            end
          end
        end
      end
    end
  end
  return nil
end

function R.Refuse(move)
  R.refused[move.label .. ":" .. move.id] = true
  U.Debug("bags route: " .. move.label .. " refused item " .. move.id)
end

-- Lift and drop in one tick, so the cursor is never left holding the item
-- between ticks. A refusal the client makes on the spot leaves the item on
-- the cursor; it goes straight back to its own slot.
function R.Issue(move)
  if not U.PickupContainerSlot(move.src.bag, move.src.slot) or
     not U.CursorHasItem() then
    return
  end

  R.Trace("moving " .. move.src.bag .. "/" .. move.src.slot .. " -> " ..
          move.dst.bag .. "/" .. move.dst.slot)
  U.PickupContainerSlot(move.dst.bag, move.dst.slot)
  if U.CursorHasItem() then
    U.PickupContainerSlot(move.src.bag, move.src.slot)
    if U.CursorHasItem() then pcall(ClearCursor) end
    R.Refuse(move)
    return
  end

  move.deadline = R.Now() + R.MOVE_TIMEOUT
  R.pending = move
end

function R.Step()
  if R.pending then
    local move = R.pending
    local landed = U.ItemLinkId(U.ContainerSlotLink(move.dst.bag, move.dst.slot))
    if landed == move.id then
      R.pending = nil
    elseif R.Now() > move.deadline then
      -- The server never put it there; the client returns a refused item to
      -- its source on its own. Do not offer it to that bag again.
      R.pending = nil
      R.Refuse(move)
    else
      return
    end
  end

  if R.Busy() then return end

  if R.dirty then
    if not R.Scan() then return end
    R.dirty = false
  end

  if not R.Wanted() then
    R.route = {}
    return
  end

  local move = R.NextMove()
  if not move and next(R.route) and R.Now() > R.routeUntil then
    R.Trace("queued item found no free matching slot; queue dropped")
  end
  if move then
    R.Issue(move)
  elseif R.Now() > R.routeUntil then
    -- Nothing queued can be placed: the specialty bags are full, or none
    -- takes it. A later arrival of the same item queues it again.
    R.route = {}
  end
end

-- Queue every item already sitting in an ordinary bag that an equipped
-- specialty bag takes. Run when the category view is switched on (user
-- request, 2026-09-27); from then on only arrivals are routed, so an item
-- the player later takes out of a specialty bag stays where they put it.
function R.QueueExisting()
  if not R.Wanted() then return end
  local special = R.SpecialBags()
  if table.getn(special) == 0 then
    R.Trace("category view on: no equipped specialty bag was recognised")
    return
  end

  local checked = {}
  local i
  for i = 1, table.getn(R.BAGS) do
    local bag = R.BAGS[i]
    if U.IsGeneralContainer(bag) then
      local slot
      for slot = 1, U.ContainerSlotCount(bag) do
        local link = U.ContainerSlotLink(bag, slot)
        local id = U.ItemLinkId(link)
        if id and not checked[id] then
          checked[id] = true
          if R.AnyBagAccepts(special, id, link) then
            R.route[id] = true
            R.routeUntil = R.Now() + R.ROUTE_WINDOW
          end
        end
      end
    end
  end
end

function U.BagRouteExisting()
  R.QueueExisting()
end

function R.MarkDirty()
  R.dirty = true
end

function BR:OnEnable()
  if type(U.BagsEnabled) ~= "function" or not U.BagsEnabled() then return end

  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    R.armAt = R.Now() + R.SETTLE
    R.dirty = true
  end)
  U.RegisterEvent("BAG_UPDATE", R.MarkDirty)
  U.RegisterEvent("ITEM_LOCK_CHANGED", R.MarkDirty)

  R.armAt = R.Now() + R.SETTLE
  U.RegisterUpdate(R.UPDATE_ID, R.INTERVAL, R.Step)
end
