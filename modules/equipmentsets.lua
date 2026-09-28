-- unrealUI :: modules/equipmentsets.lua
--
-- Equipment sets for the Character window's Equipment Manager (user request,
-- 2026-09-28). Retail keeps them in the client (C_EquipmentSet, used by
-- Blizzard_FrameXML/Mainline/EquipmentManager.lua); this client has no
-- equipment-set API at all (query_compat.py: C_EquipmentSet, GetEquipmentSet*,
-- EquipItemByName -- no matches), so the store and the swap are built here on
-- the primitives Retail's own EquipmentManager.lua runs underneath:
-- PickupContainerItem / PickupInventoryItem, CursorHasItem, CursorCanGoInSlot,
-- IsInventoryItemLocked and ClearCursor. All are OFFICIAL_CLIENT_DOCUMENTATION,
-- DOCUMENTED_NOT_RUNTIME_VERIFIED, so, as in core/itemsort.lua, no move is
-- trusted: one move is in flight at a time, each is read back from the slot,
-- and a refused or late move puts the cursor back and is reported.
--
-- GetInventoryItemLink returns an item-0 placeholder for an empty slot
-- (knowledge: inventory.empty_slot_link_returns_item_zero); ES.ItemString
-- reads that as empty.
--
-- Store: its own per-character SavedVariable, UnrealUIEquipmentSetDB, as
-- modules/bagfavorites.lua keeps one. Only item strings, icon file names
-- without their folder and set names stripped of "\" and "|" are persisted
-- (knowledge: config.savedvariables_backslash_corruption). A set's
-- items[slot] is the item string, "" for a slot saved empty (equipping the
-- set empties it, as Retail does), and absent for an ignored slot.
--
-- Data and behaviour only; modules/characterequipment.lua and
-- modules/characterflyout.lua draw it. One top-level table (rules/unreal-ui.md,
-- Lua local budget).

local U = UnrealUI

local ES = {
  DB_NAME = "UnrealUIEquipmentSetDB",
  DB_VERSION = 1,
  UPDATE = "equipmentsets.run",
  INTERVAL = 0.03,
  -- Seconds a move may take to show in its slot, and a slot may stay locked.
  LAND_TIMEOUT = 1.5,
  LOCK_TIMEOUT = 3.0,
  -- MAX_EQUIPMENT_SETS_PER_PLAYER, and the popup's name limit.
  MAX_SETS = 10,
  MAX_NAME = 16,
  BAGS = { 0, 1, 2, 3, 4 },
  -- Weapons first: a two-hander pushes the off hand out itself, and a
  -- one-hander must be in before an off-hand item can go in.
  ORDER = { 16, 17, 18, 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14 },
  -- INVSLOTS_EQUIPABLE_IN_COMBAT.
  COMBAT = { [16] = true, [17] = true, [18] = true },
  -- New sets ignore the shirt and tabard (GearSetButton_OnClick).
  DEFAULT_IGNORED = { 4, 19 },
  -- equipLoc -> the slots an item of it can go in.
  EQUIP_LOCS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
  },
  -- A one-hand weapon goes in the off hand only for a class that can dual
  -- wield; this client has no IsDualWielding (character.modern_stat_apis_absent).
  DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true },
  db = nil,
  run = nil,
  ignored = {},
  listeners = {},
}
U.EquipmentSets = ES

ES.IS_SLOT = {}
do
  local i
  for i = 1, table.getn(ES.ORDER) do ES.IS_SLOT[ES.ORDER[i]] = true end
end

function ES.Call(name, a, b, c)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3, r4 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3, r4
end

-- ---------------------------------------------------------------------------
-- Change notification
-- ---------------------------------------------------------------------------
function ES.OnChange(fn)
  if type(fn) == "function" then table.insert(ES.listeners, fn) end
end

function ES.Changed()
  local i
  for i = 1, table.getn(ES.listeners) do
    local ok, err = pcall(ES.listeners[i])
    if not ok then U.Debug("equipmentsets listener: " .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------
function ES.CleanName(name)
  if type(name) ~= "string" then return "" end
  name = string.gsub(name, "[\\|]", "")
  name = string.gsub(name, "^%s*(.-)%s*$", "%1")
  return string.sub(name, 1, ES.MAX_NAME)
end

function ES.CleanSet(set)
  if type(set) ~= "table" then return nil end
  set.name = ES.CleanName(set.name)
  if set.name == "" or type(set.items) ~= "table" then return nil end
  local items, slot, value = {}, nil, nil
  for slot, value in pairs(set.items) do
    if type(slot) == "number" and ES.IS_SLOT[slot] and type(value) == "string" and
       (value == "" or string.find(value, "^item:[%-%d:]+$")) then
      items[slot] = value
    end
  end
  set.items = items
  if type(set.icon) ~= "string" or string.find(set.icon, "[\\|/]") then
    set.icon = nil
  end
  return set
end

function ES.Store()
  if ES.db then return ES.db end
  local db = U.G(ES.DB_NAME)
  if type(db) ~= "table" then
    U.SetG(ES.DB_NAME, { version = ES.DB_VERSION })
    db = U.G(ES.DB_NAME)
    -- A rejected global write leaves a session-only table.
    if type(db) ~= "table" then db = { version = ES.DB_VERSION } end
  end
  db.version = ES.DB_VERSION
  local sets = {}
  if type(db.sets) == "table" then
    local i
    for i = 1, table.getn(db.sets) do
      local set = ES.CleanSet(db.sets[i])
      if set then table.insert(sets, set) end
    end
  end
  db.sets = sets
  ES.db = db
  return db
end

function ES.Sets()
  return ES.Store().sets
end

function ES.Count()
  return table.getn(ES.Sets())
end

function ES.IndexOf(set)
  local sets = ES.Sets()
  local i
  for i = 1, table.getn(sets) do
    if sets[i] == set then return i end
  end
  return nil
end

function ES.FindByName(name)
  name = string.lower(ES.CleanName(name))
  local sets = ES.Sets()
  local i
  for i = 1, table.getn(sets) do
    if string.lower(sets[i].name) == name then return sets[i] end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------
-- "item:id:enchant:suffix:unique" from a link, or nil for no item.
function ES.ItemString(link)
  if type(link) ~= "string" then return nil end
  local _, _, item = string.find(link, "(item:[%-%d:]+)")
  if not item then return nil end
  local _, _, id = string.find(item, "^item:(%d+)")
  id = tonumber(id)
  if not id or id == 0 then return nil end
  return item
end

function ES.Parts(item)
  local _, _, id, enchant, suffix =
    string.find(item or "", "^item:(%d+):?(%-?%d*):?(%-?%d*)")
  return tonumber(id), tonumber(enchant) or 0, tonumber(suffix) or 0
end

-- How well `have` stands in for `want`: 3 the same item, 2 the same item and
-- random suffix (an enchant or a new instance since the save), 1 the same
-- item id only, 0 none.
function ES.Score(want, have)
  if not want or want == "" or not have then return 0 end
  if want == have then return 3 end
  local wantId, _, wantSuffix = ES.Parts(want)
  local haveId, _, haveSuffix = ES.Parts(have)
  if not wantId or wantId ~= haveId then return 0 end
  if wantSuffix == haveSuffix then return 2 end
  return 1
end

function ES.EquippedLink(slot)
  local link = ES.Call("GetInventoryItemLink", "player", slot)
  if ES.ItemString(link) then return link end
  return nil
end

function ES.Equipped(slot)
  return ES.ItemString(ES.Call("GetInventoryItemLink", "player", slot))
end

function ES.InventoryLocked(slot)
  local locked = ES.Call("IsInventoryItemLocked", slot)
  return locked and locked ~= 0 and true or false
end

function ES.BagLocked(bag, slot)
  local _, _, locked = U.ContainerSlotInfo(bag, slot)
  return locked and locked ~= 0 and true or false
end

-- Every item in the carried bags: { bag, slot, item, link }. Read once per
-- driver tick: a pane refresh asks for it once per visible set.
function ES.BagItems()
  if ES.bagCache and ES.bagCacheTick == U.ticks then return ES.bagCache end
  local list = {}
  local i, slot
  for i = 1, table.getn(ES.BAGS) do
    local bag = ES.BAGS[i]
    for slot = 1, U.ContainerSlotCount(bag) do
      local link = U.ContainerSlotLink(bag, slot)
      local item = ES.ItemString(link)
      if item then
        table.insert(list, { bag = bag, slot = slot, item = item, link = link })
      end
    end
  end
  ES.bagCache, ES.bagCacheTick = list, U.ticks
  return list
end

function ES.SlotsFor(link)
  local ok, _, _, _, _, _, _, _, equipLoc = pcall(GetItemInfo, link)
  if not ok or type(equipLoc) ~= "string" then return nil end
  return ES.EQUIP_LOCS[equipLoc], equipLoc
end

function ES.CanGoIn(link, slot)
  local slots, equipLoc = ES.SlotsFor(link)
  if not slots then return false end
  if slot == 17 and equipLoc == "INVTYPE_WEAPON" then
    local class = type(U.PlayerClassToken) == "function" and U.PlayerClassToken()
    if not ES.DUAL_WIELD[class or ""] then return false end
  end
  local i
  for i = 1, table.getn(slots) do
    if slots[i] == slot then return true end
  end
  return false
end

-- GetInventoryItemsForSlot for the flyout: the carried items that fit `slot`,
-- in bag order.
function ES.ItemsForSlot(slot)
  local list = {}
  local items = ES.BagItems()
  local i
  for i = 1, table.getn(items) do
    if ES.CanGoIn(items[i].link, slot) then table.insert(list, items[i]) end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------
function ES.IconName(path)
  if type(path) ~= "string" or path == "" then return nil end
  local _, _, name = string.find(path, "([^\\/]+)$")
  if not name or string.find(name, "|") then return nil end
  return name
end

function ES.IconPath(name)
  local t = U.media.modernWow.equipmentManager.texture
  return t.iconFolder .. (name or t.unknownIcon)
end

-- The equipped items' icons, the popup's choices (Retail's
-- IconDataProviderExtraType.Equipment puts them first).
function ES.EquipmentIcons()
  local list, seen = {}, {}
  local i
  for i = 1, table.getn(ES.ORDER) do
    local name = ES.IconName(ES.Call("GetInventoryItemTexture", "player", ES.ORDER[i]))
    if name and not seen[string.lower(name)] then
      seen[string.lower(name)] = true
      table.insert(list, name)
    end
  end
  return list
end

-- The popup's whole choice: the set's own icon, the equipped items', then
-- the client's macro icon library. This client cannot render the "?" fallback,
-- so it is deliberately omitted.
-- (GetNumMacroIcons / GetMacroIconInfo, OFFICIAL_CLIENT_DOCUMENTATION, not
-- runtime-verified; without them the list stops before it). Only icons from
-- the Icons folder are kept, since a set stores the file name alone.
function ES.AllIcons(current)
  local list, seen = {}, {}
  local unknown = string.lower(U.media.modernWow.equipmentManager.texture.unknownIcon)
  local function Add(name)
    name = ES.IconName(name)
    if not name or string.lower(name) == unknown or seen[string.lower(name)] then return end
    seen[string.lower(name)] = true
    table.insert(list, name)
  end
  Add(current)
  local equipped = ES.EquipmentIcons()
  local i
  for i = 1, table.getn(equipped) do Add(equipped[i]) end
  local count = tonumber(ES.Call("GetNumMacroIcons")) or 0
  for i = 1, count do
    local path = ES.Call("GetMacroIconInfo", i)
    if type(path) == "string" and string.find(string.lower(path), "icons[\\/]") then
      Add(ES.IconName(path))
    end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- Ignored slots for the next save (C_EquipmentSet.IgnoreSlotForSave)
-- ---------------------------------------------------------------------------
function ES.ClearIgnored()
  ES.ignored = {}
  ES.Changed()
end

function ES.IgnoreSlot(slot, ignored)
  ES.ignored[slot] = ignored and true or nil
  ES.Changed()
end

function ES.IsIgnored(slot)
  return ES.ignored[slot] and true or false
end

function ES.IgnoreDefaults()
  ES.ignored = {}
  local i
  for i = 1, table.getn(ES.DEFAULT_IGNORED) do
    ES.ignored[ES.DEFAULT_IGNORED[i]] = true
  end
  ES.Changed()
end

-- PaperDollFrame_IgnoreSlotsForSet.
function ES.IgnoreSlotsForSet(set)
  ES.ignored = {}
  if set then
    local i
    for i = 1, table.getn(ES.ORDER) do
      if set.items[ES.ORDER[i]] == nil then ES.ignored[ES.ORDER[i]] = true end
    end
  end
  ES.Changed()
end

-- ---------------------------------------------------------------------------
-- Editing sets
-- ---------------------------------------------------------------------------
function ES.Snapshot()
  local items = {}
  local i
  for i = 1, table.getn(ES.ORDER) do
    local slot = ES.ORDER[i]
    if not ES.ignored[slot] then items[slot] = ES.Equipped(slot) or "" end
  end
  return items
end

function ES.Create(name, icon)
  name = ES.CleanName(name)
  if name == "" or ES.Count() >= ES.MAX_SETS or ES.FindByName(name) then
    return nil
  end
  local set = { name = name, icon = ES.IconName(icon), items = ES.Snapshot() }
  table.insert(ES.Sets(), set)
  ES.Changed()
  return set
end

-- C_EquipmentSet.SaveEquipmentSet: the current gear, minus ignored slots.
function ES.Save(set, icon)
  if not ES.IndexOf(set) then return false end
  set.items = ES.Snapshot()
  if icon then set.icon = ES.IconName(icon) or set.icon end
  ES.Changed()
  return true
end

function ES.Modify(set, name, icon)
  if not ES.IndexOf(set) then return false end
  name = ES.CleanName(name)
  if name ~= "" then set.name = name end
  set.icon = ES.IconName(icon) or set.icon
  ES.Changed()
  return true
end

function ES.Delete(set)
  local index = ES.IndexOf(set)
  if not index then return false end
  table.remove(ES.Sets(), index)
  ES.Changed()
  return true
end

-- ---------------------------------------------------------------------------
-- State of a set
-- ---------------------------------------------------------------------------
-- Counts for the set's tooltip and name colour: `equipped`, `bags`,
-- `missing` among its non-empty slots, and whether every managed slot already
-- holds what the set wants (Retail's isEquipped).
function ES.Info(set)
  local info = { equipped = 0, bags = 0, missing = 0, isEquipped = true }
  if not set then return info end
  local bagItems = ES.BagItems()
  local used = {}
  local i, j
  for i = 1, table.getn(ES.ORDER) do
    local slot = ES.ORDER[i]
    local want = set.items[slot]
    if want ~= nil then
      local have = ES.Equipped(slot)
      if want == "" then
        if have then info.isEquipped = false end
      elseif ES.Score(want, have) >= 2 then
        info.equipped = info.equipped + 1
      else
        info.isEquipped = false
        local found = false
        for j = 1, table.getn(bagItems) do
          if not used[j] and ES.Score(want, bagItems[j].item) >= 1 then
            used[j] = true
            found = true
            break
          end
        end
        if not found then
          for j = 1, table.getn(ES.ORDER) do
            local other = ES.ORDER[j]
            if other ~= slot and ES.Score(want, ES.Equipped(other)) >= 1 then
              found = true
              break
            end
          end
        end
        if found then info.bags = info.bags + 1
        else info.missing = info.missing + 1 end
      end
    end
  end
  return info
end

-- The set's icon path: its saved icon, else its first item's, else "?".
function ES.SetIcon(set)
  if set and set.icon then return ES.IconPath(set.icon) end
  return ES.IconPath(nil)
end

-- ---------------------------------------------------------------------------
-- The swap run
--
-- A run walks ES.ORDER once. Each slot either already holds what it wants,
-- or gets one move: a pickup from its source, a drop on the slot, and a wait
-- until the slot reads back the new item and is unlocked. EquipmentManager
-- _EquipContainerItem / _EquipInventoryItem / _UnequipItemInSlot, one at a
-- time. A drop the client refuses leaves the item on the cursor; it is put
-- back on its source and the slot is counted as failed.
-- ---------------------------------------------------------------------------
function ES.Ticks(seconds)
  local ticks = math.floor(seconds / ES.INTERVAL)
  if ticks < 1 then ticks = 1 end
  return ticks
end

function ES.Running()
  return ES.run ~= nil
end

function ES.PutBack(source)
  if not U.CursorHasItem() then return end
  if source then
    if source.bag then U.PickupContainerSlot(source.bag, source.slot)
    elseif source.inv then ES.Call("PickupInventoryItem", source.inv) end
  end
  if U.CursorHasItem() then ES.Call("ClearCursor") end
end

function ES.CursorFits(slot)
  local fn = U.G("CursorCanGoInSlot")
  if type(fn) ~= "function" then return true end
  local ok, fits = pcall(fn, slot)
  if not ok then return true end
  return fits and fits ~= 0 and true or false
end

-- Where the item `want` is now, for `slot`: another equipped slot of this run
-- that does not want what it holds, or a carried bag; the best ES.Score wins.
function ES.FindSource(run, slot, want)
  local best, bestScore = nil, 0
  local i
  for i = 1, table.getn(ES.ORDER) do
    local other = ES.ORDER[i]
    if other ~= slot then
      local have = ES.Equipped(other)
      local wanted = run.items[other]
      if have and wanted ~= nil and ES.Score(wanted, have) < 2 then
        local score = ES.Score(want, have)
        if score > bestScore then
          best, bestScore = { inv = other, item = have }, score
        end
      end
    end
  end
  local items = ES.BagItems()
  for i = 1, table.getn(items) do
    local score = ES.Score(want, items[i].item)
    if score > bestScore then best, bestScore = items[i], score end
  end
  return best
end

function ES.FreeBagSlot()
  local i, slot
  for i = 1, table.getn(ES.BAGS) do
    local bag = ES.BAGS[i]
    local general = bag == 0 or type(U.BagSpecialtyLabel) ~= "function" or
                    not U.BagSpecialtyLabel(bag)
    if general then
      for slot = 1, U.ContainerSlotCount(bag) do
        if not U.ContainerSlotHasItem(bag, slot) and not ES.BagLocked(bag, slot) then
          return { bag = bag, slot = slot }
        end
      end
    end
  end
  return nil
end

function ES.Fail(run, slot, reason)
  run.failed = run.failed + 1
  U.Debug("equipmentsets: slot " .. tostring(slot) .. " " .. tostring(reason))
end

function ES.MoveIn(run, slot, want, source)
  source = source or ES.FindSource(run, slot, want)
  if not source then
    run.missing = run.missing + 1
    return
  end
  if source.bag then U.PickupContainerSlot(source.bag, source.slot)
  else ES.Call("PickupInventoryItem", source.inv) end
  if not U.CursorHasItem() then return ES.Fail(run, slot, "pickup") end
  if not ES.CursorFits(slot) then
    ES.PutBack(source)
    return ES.Fail(run, slot, "does not fit")
  end
  ES.Call("PickupInventoryItem", slot)
  -- Refused, or the old item came back on the cursor: its source slot is the
  -- one the new item left, so either way it goes back there.
  ES.PutBack(source)
  run.pending = { slot = slot, expect = source.item, ticks = 0 }
end

function ES.MoveOut(run, slot)
  local dest = ES.FreeBagSlot()
  if not dest then
    run.bagsFull = true
    return ES.Fail(run, slot, "bags full")
  end
  ES.Call("PickupInventoryItem", slot)
  if not U.CursorHasItem() then return ES.Fail(run, slot, "pickup") end
  U.PickupContainerSlot(dest.bag, dest.slot)
  if U.CursorHasItem() then
    ES.PutBack({ inv = slot })
    return ES.Fail(run, slot, "drop refused")
  end
  run.pending = { slot = slot, expect = "", ticks = 0 }
end

function ES.Landed(pending)
  if ES.InventoryLocked(pending.slot) then return false end
  local have = ES.Equipped(pending.slot)
  if pending.expect == "" then return have == nil end
  return ES.Score(pending.expect, have) >= 2
end

function ES.Step()
  local run = ES.run
  if not run then
    U.UnregisterUpdate(ES.UPDATE)
    return
  end

  local pending = run.pending
  if pending then
    pending.ticks = pending.ticks + 1
    if ES.Landed(pending) then
      run.pending = nil
      run.moved = run.moved + 1
    elseif pending.ticks > ES.Ticks(ES.LAND_TIMEOUT) then
      if U.CursorHasItem() then ES.Call("ClearCursor") end
      run.pending = nil
      ES.Fail(run, pending.slot, "did not land")
    end
    return
  end

  if U.CursorHasItem() then
    ES.Call("ClearCursor")
    return ES.Finish()
  end

  local slot = run.queue[run.index]
  if not slot then return ES.Finish() end
  local want = run.items[slot]
  if want == nil then
    run.index = run.index + 1
    return
  end
  if run.combat and not ES.COMBAT[slot] then
    run.skipped = run.skipped + 1
    run.index = run.index + 1
    return
  end

  local have = ES.Equipped(slot)
  local done = (want == "" and not have) or
               (want ~= "" and not run.sources[slot] and ES.Score(want, have) >= 2)
  if done then
    run.index = run.index + 1
    return
  end

  -- Wait out a server lock on the slot rather than drop onto it.
  if ES.InventoryLocked(slot) then
    run.lockTicks = run.lockTicks + 1
    if run.lockTicks <= ES.Ticks(ES.LOCK_TIMEOUT) then return end
    run.lockTicks = 0
    run.index = run.index + 1
    return ES.Fail(run, slot, "locked")
  end
  run.lockTicks = 0
  run.index = run.index + 1

  if want == "" then ES.MoveOut(run, slot)
  else ES.MoveIn(run, slot, want, run.sources[slot]) end
end

function ES.Finish()
  local run = ES.run
  ES.run = nil
  U.UnregisterUpdate(ES.UPDATE)
  if not run then return end
  if run.set then
    local name = run.set.name
    if run.missing > 0 then U.Print(U.L("EQUIPSET_MISSING", name, run.missing)) end
    if run.failed > 0 then U.Print(U.L("EQUIPSET_FAILED", name, run.failed)) end
  elseif run.failed > 0 then
    U.Print(U.L("EQUIPSET_SWAP_FAILED"))
  end
  if run.bagsFull then U.Print(U.L("EQUIPSET_BAGS_FULL")) end
  if run.skipped > 0 then U.Print(U.L("EQUIPSET_COMBAT")) end
  ES.Changed()
  if type(run.onDone) == "function" then pcall(run.onDone, run) end
end

-- `items`: slot -> item string or "" (the whole run); `sources`: slot -> the
-- exact source a flyout click picked.
function ES.Start(items, set, sources, onDone)
  if ES.run then return false end
  if U.CursorHasItem() then
    U.Print(U.L("EQUIPSET_CURSOR_BUSY"))
    return false
  end
  local combat = ES.Call("UnitAffectingCombat", "player")
  ES.run = {
    items = items, set = set, sources = sources or {}, onDone = onDone,
    queue = ES.ORDER, index = 1, lockTicks = 0,
    moved = 0, failed = 0, missing = 0, skipped = 0,
    combat = combat and combat ~= 0 and true or false,
  }
  U.RegisterUpdate(ES.UPDATE, ES.INTERVAL, ES.Step)
  return true
end

-- EquipmentManager_EquipSet.
function ES.Equip(set, onDone)
  if not set or not ES.IndexOf(set) then return false end
  return ES.Start(set.items, set, nil, onDone)
end

-- The flyout: one item from a bag slot (EquipmentManager_EquipItemByLocation).
function ES.EquipFrom(slot, source)
  if not source or not source.item then return false end
  local items, sources = {}, {}
  items[slot] = source.item
  sources[slot] = source
  return ES.Start(items, nil, sources)
end

-- The flyout's place-in-bags button (EquipmentManager_UnequipItemInSlot).
function ES.Unequip(slot)
  if not ES.Equipped(slot) then return false end
  local items = {}
  items[slot] = ""
  return ES.Start(items)
end
