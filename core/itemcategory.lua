-- unrealUI :: core/itemcategory.lua
--
-- The shared item classifier behind the bag's optional category view
-- (modules/bags.lua). One (bag, slot) pair in, one stable category key out.
-- It lives in core/ rather than in the bag module because the bank window
-- (modules/bank.lua) runs on the same core/itemslot.lua component and would
-- need exactly this table if it ever grows the same view.
--
-- Evidence: every classification signal comes from GetItemInfo, whose tuple is
-- documented for this client as
--   name, link, quality, minLevel, type, subType, stackCount, equipLoc, texture
-- (documentation.json / global:Item:GetItemInfo, OFFICIAL_CLIENT_DOCUMENTATION,
-- DOCUMENTED_NOT_RUNTIME_VERIFIED). The same entry states it "returns no values
-- if the item is not in the local cache", so a miss falls through to the
-- "unknown" bucket instead of to a wrong one. Nothing here is runtime verified;
-- knowledge.json / bags.container_api_contract_unverified still covers the
-- container reads this builds on, and every call stays inside pcall.
--
-- Signal order is deliberate, strongest first:
--   1. no item in the slot            -> empty
--   2. GetItemInfo gave nothing       -> unknown
--   3. quality 0                      -> junk  (the bag's own grey-vendor rule)
--   4. equipLoc is an INVTYPE_* token -> gear  (locale independent)
--   5. class-scoped subclass name     -> the fine buckets
--   6. class name                     -> the coarse buckets
--
-- Steps 5 and 6 compare the client's *display* names for the item class and
-- subclass, which are localized strings. That is the same assumption
-- core/itemslot.lua's quest-item test already makes on this client
-- (itemType == "Quest"), so it is not a new dependency -- but it is why the
-- two locale-independent signals are tested first and why an unrecognised name
-- degrades to misc/unknown rather than to a guess. If a non-English client
-- ever needs this, add its class names as extra keys in the tables below; do
-- not reorder the checks.

local U = UnrealUI

-- One table instead of a top-level local per member, per the local-budget rule
-- in .claude/rules/unreal-ui.md.
local IC = {}

-- Display order of the sections in the bag window. Sections with no items are
-- skipped at layout time, so a long list costs nothing when it is not used.
--
-- "empty" is not in this list and has no label: a free slot is not content, so
-- the bag window reports free slots as a used/total readout in its header
-- rather than drawing a section for them. U.ItemCategoryForSlot still returns
-- the key, because counting those slots is what the readout is made of.
IC.order = {
  "gear",
  "quest",
  "consumable",
  "food",
  "potion",
  "buff",
  "bandage",
  "explosive",
  "reagent",
  "tradegoods",
  "recipe",
  "ammo",
  "container",
  "key",
  "junk",
  "misc",
  "unknown",
}

-- Locale key per category; the strings themselves live in locales/.
IC.label = {
  gear        = "ITEM_CATEGORY_GEAR",
  quest       = "ITEM_CATEGORY_QUEST",
  consumable  = "ITEM_CATEGORY_CONSUMABLE",
  food        = "ITEM_CATEGORY_FOOD",
  potion      = "ITEM_CATEGORY_POTION",
  buff        = "ITEM_CATEGORY_BUFF",
  bandage     = "ITEM_CATEGORY_BANDAGE",
  explosive   = "ITEM_CATEGORY_EXPLOSIVE",
  reagent     = "ITEM_CATEGORY_REAGENT",
  tradegoods  = "ITEM_CATEGORY_TRADEGOODS",
  recipe      = "ITEM_CATEGORY_RECIPE",
  ammo        = "ITEM_CATEGORY_AMMO",
  container   = "ITEM_CATEGORY_CONTAINER",
  key         = "ITEM_CATEGORY_KEY",
  junk        = "ITEM_CATEGORY_JUNK",
  misc        = "ITEM_CATEGORY_MISC",
  unknown     = "ITEM_CATEGORY_UNKNOWN",
}

-- Item class -> coarse bucket. Keys are lowercased so the lookup does not care
-- about the client's capitalisation.
IC.class = {
  ["weapon"]        = "gear",
  ["armor"]         = "gear",
  ["container"]     = "container",
  ["quiver"]        = "container",
  ["consumable"]    = "consumable",
  ["trade goods"]   = "tradegoods",
  ["tradegoods"]    = "tradegoods",
  ["projectile"]    = "ammo",
  ["recipe"]        = "recipe",
  ["reagent"]       = "reagent",
  ["quest"]         = "quest",
  ["key"]           = "key",
  ["miscellaneous"] = "misc",
  ["misc"]          = "misc",
}

-- Subclass -> fine bucket, scoped by its class. The scoping is not decoration:
-- "Cloth" is a subclass of both Armor and Trade Goods, and "Reagent" is both a
-- class of its own and a Miscellaneous subclass. A flat table would collide.
IC.subclass = {
  ["consumable"] = {
    ["food & drink"]     = "food",
    ["food and drink"]   = "food",
    ["potion"]           = "potion",
    ["elixir"]           = "buff",
    ["flask"]            = "buff",
    ["scroll"]           = "buff",
    ["item enhancement"] = "buff",
    ["bandage"]          = "bandage",
  },
  ["trade goods"] = {
    ["explosives"] = "explosive",
    ["devices"]    = "explosive",
  },
  ["tradegoods"] = {
    ["explosives"] = "explosive",
    ["devices"]    = "explosive",
  },
  ["miscellaneous"] = {
    ["junk"]    = "junk",
    ["reagent"] = "reagent",
  },
  ["key"] = {
    ["lockpick"] = "key",
  },
}

-- An equippable item carries an INVTYPE_* token here. Three of those tokens do
-- not mean "gear" in this taxonomy: a bag or quiver belongs with the
-- containers, ammunition belongs with the ammunition, and the explicit
-- non-equip token means the field is filled in but carries no slot. A `false`
-- value says "not gear, keep looking"; a string says "this category".
IC.notGear = {
  INVTYPE_BAG       = "container",
  INVTYPE_QUIVER    = "container",
  INVTYPE_AMMO      = "ammo",
  INVTYPE_NON_EQUIP = false,
}

-- Category per item link. Links are stable strings that already encode the
-- item id, and an item's class never changes, so one lookup per distinct link
-- is enough no matter how often the bag relays out.
IC.cache = {}

local function Normalise(value)
  if type(value) ~= "string" or value == "" then return nil end
  return string.lower(value)
end

function IC.FromLink(link)
  local cached = IC.cache[link]
  if cached then return cached end

  local ok, _, _, quality, _, itemType, subType, _, equipLoc =
    pcall(GetItemInfo, link)
  if not ok then return "unknown" end

  local key

  if tonumber(quality) == 0 then key = "junk" end

  if not key and type(equipLoc) == "string" and equipLoc ~= "" then
    local override = IC.notGear[equipLoc]
    if override then
      key = override
    elseif override == nil and string.find(equipLoc, "^INVTYPE_") then
      key = "gear"
    end
  end

  local class = Normalise(itemType)

  if not key then
    local scoped = class and IC.subclass[class]
    local sub = Normalise(subType)
    if scoped and sub then key = scoped[sub] end
  end

  if not key and class then key = IC.class[class] end

  -- A cached-but-unrecognised item is still a real item: only a GetItemInfo
  -- miss should read as "unknown", so anything that answered with a class name
  -- this table has no bucket for lands in misc. An item with no class name at
  -- all was not in the local cache, and is left uncached so the next relayout
  -- can classify it properly once the client has filled it in.
  if not key then
    if not class then return "unknown" end
    key = "misc"
  end

  IC.cache[link] = key
  return key
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

-- The section order, as a fresh list so a caller cannot mutate the shared one.
function U.ItemCategoryOrder()
  local list = {}
  local i
  for i = 1, table.getn(IC.order) do list[i] = IC.order[i] end
  return list
end

function U.ItemCategoryLabel(key)
  local locale = IC.label[key]
  if not locale then return key or "" end
  return U.L(locale)
end

-- Diagnostic snapshot behind /uui bagcat (core/commands.lua). Write-only, and
-- every client call is pcall'd.
--
-- It exists because steps 5 and 6 above compare the client's *display* names for
-- the item class and subclass, and nothing in the compact DB records what those
-- names actually are on this client. If food and potions land in one bucket, it
-- is because both answer with the same subType, or with names these tables do
-- not carry -- and this is what says which.
--
-- The auction class list is captured alongside the items because it is the one
-- documented route to a locale-independent classification:
-- GetAuctionItemClasses returns "the localized names of item classes ... in a
-- fixed internal order" (documentation.json / global:Auction). If it answers
-- outside an auction house, class and subclass can be matched by index instead
-- of by English name. If it answers with nothing, that route is closed and the
-- name tables are the only option.
IC.dumpBags = { 0, 1, 2, 3, 4 }

-- Takes a packed `{ pcall(fn, ...) }` and returns the results after the ok
-- flag. The table constructor is used rather than a vararg function reading
-- `arg`, which is the deprecated Lua 5.0 form and not worth depending on here
-- when `{ f() }` collects every return in both versions.
function IC.Tail(packed)
  local list = {}
  if not packed[1] then return list end

  local i
  for i = 2, table.getn(packed) do table.insert(list, packed[i]) end
  return list
end

function U.ItemCategoryDump()
  local dump = { items = {}, classes = {}, subclasses = {} }

  dump.classes = IC.Tail({ pcall(GetAuctionItemClasses) })

  local i
  for i = 1, table.getn(dump.classes) do
    table.insert(dump.subclasses, {
      index = i,
      name = dump.classes[i],
      entries = IC.Tail({ pcall(GetAuctionItemSubClasses, i) }),
    })
  end

  for i = 1, table.getn(IC.dumpBags) do
    local bag = IC.dumpBags[i]
    local ok, n = pcall(GetContainerNumSlots, bag)
    n = (ok and tonumber(n)) or 0

    local slot
    for slot = 1, n do
      local linkOk, link = pcall(GetContainerItemLink, bag, slot)
      if linkOk and type(link) == "string" and link ~= "" then
        local infoOk, name, _, quality, _, itemType, subType, _, equipLoc =
          pcall(GetItemInfo, link)
        table.insert(dump.items, {
          bag = bag,
          slot = slot,
          link = link,
          resolved = infoOk and true or false,
          name = name,
          quality = quality,
          itemType = itemType,
          subType = subType,
          equipLoc = equipLoc,
          category = IC.FromLink(link),
        })
      end
    end
  end

  return dump
end

-- The category of an item named by its link, for callers that already hold one
-- and have no container coordinates to offer -- core/itemsort.lua works from a
-- snapshot of links, because the slot an item sits in is the thing it is busy
-- changing.
function U.ItemCategoryFromLink(link)
  if type(link) ~= "string" or link == "" then return "unknown" end
  return IC.FromLink(link)
end

-- The category of one container slot. "empty" for a free slot, "unknown" when
-- the item is not in the client's local cache yet -- both are real sections
-- rather than error states, so a bag opened before the cache fills still draws
-- every slot exactly once.
function U.ItemCategoryForSlot(bag, slot)
  if not U.ContainerSlotHasItem(bag, slot) then return "empty" end

  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if not ok or type(link) ~= "string" or link == "" then return "unknown" end

  return IC.FromLink(link)
end
