-- unrealUI :: modules/bagcustomcategories.lua
--
-- The player's own bag categories (user request, 2026-10-31), reproducing
-- pandaUI's editor of the same name, itself after Bagshui's category editor
-- (Components/Categories.lua, Categories.Ui.lua, Config/RuleFunctions.lua): a
-- name, a priority, rules and an item list. An item in the list, or one that
-- passes the rules, is filed under the category instead of its built-in one,
-- and the highest priority number is tried first. The bag and live bank
-- category views read it through U.CustomItemCategory
-- (modules/bagcategoryview.lua).
--
-- Bagshui types each rule as Lua and compiles it with loadstring. UnrealUI has
-- no safe text box on this client (unreal-ui-design.md, "Text/search input is
-- excluded"; core/searchbox.lua types plain key names only, so no parentheses
-- or quotes), so a rule here is picked from menus -- a test, its value and an
-- optional "not" -- and the rules combine with "all" or "any".
--
-- Stored in its own account-wide SavedVariable rather than the profile:
-- core/config.lua's module sanitizer keeps one level of nesting, and a
-- category (list -> category -> rules -> rule) is three, so it would be dropped
-- on every load. Text never keeps a backslash or a pipe, so no SavedVariables
-- or chat escape can be stored (knowledge.json /
-- config.savedvariables_backslash_corruption).

local U = UnrealUI
local M = U.media

local CC = {
  DB_NAME = "UnrealUICategoryDB",
  DB_VERSION = 2,
  MAX_RULES = 8,
  MAX_CATEGORIES = 30,
  MAX_ITEMS = 64,
  MAX_TIP_LINES = 30,
  ICON = 24,
  ICON_GAP = 3,
  KEY = "custom",
  SCANNER = "UnrealUICustomCategoryScanner",
  version = 0,
  info = {},     -- item string -> parsed GetItemInfo
  lines = {},    -- bag -> slot -> { link, text = folded tooltip lines }
  ctx = {},
  ui = { rows = {}, icons = {}, styled = {} },
}

CC.kinds = {
  { id = "name",      label = "CUSTOMCAT_RULE_NAME",      value = "text" },
  { id = "nameexact", label = "CUSTOMCAT_RULE_NAMEEXACT", value = "text" },
  { id = "id",        label = "CUSTOMCAT_RULE_ID",        value = "number" },
  { id = "type",      label = "CUSTOMCAT_RULE_TYPE",      value = "type" },
  { id = "subtype",   label = "CUSTOMCAT_RULE_SUBTYPE",   value = "subtype" },
  { id = "quality",   label = "CUSTOMCAT_RULE_QUALITY",   value = "quality" },
  { id = "equip",     label = "CUSTOMCAT_RULE_EQUIP",     value = "equip" },
  { id = "minlevel",  label = "CUSTOMCAT_RULE_MINLEVEL",  value = "number" },
  { id = "stacks",    label = "CUSTOMCAT_RULE_STACKS" },
  { id = "soulbound", label = "CUSTOMCAT_RULE_SOULBOUND", scan = true },
  { id = "boe",       label = "CUSTOMCAT_RULE_BOE",       scan = true },
  { id = "tooltip",   label = "CUSTOMCAT_RULE_TOOLTIP",   value = "text", scan = true },
  { id = "bag",       label = "CUSTOMCAT_RULE_BAG",       value = "bag" },
  { id = "class",     label = "CUSTOMCAT_RULE_CLASS",     value = "class" },
  { id = "builtin",   label = "CUSTOMCAT_RULE_BUILTIN",   value = "builtin" },
}
CC.kindById = {}
do
  local i
  for i = 1, table.getn(CC.kinds) do CC.kindById[CC.kinds[i].id] = CC.kinds[i] end
end

-- Used only when GetAuctionItemClasses answers with nothing.
CC.FALLBACK_TYPES = {
  "Weapon", "Armor", "Container", "Consumable", "Trade Goods", "Projectile",
  "Quiver", "Recipe", "Reagent", "Miscellaneous", "Quest", "Key",
}

CC.EQUIP = {
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
  "INVTYPE_CHEST", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST",
  "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
  "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON",
  "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
  "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_THROWN", "INVTYPE_RELIC",
  "INVTYPE_AMMO", "INVTYPE_BAG",
}
-- Slots whose client label repeats another one's.
CC.EQUIP_ALIAS = { INVTYPE_ROBE = "INVTYPE_CHEST", INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED" }

CC.CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE",
  "WARLOCK", "DRUID",
}

CC.BAGS = { 0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10 }

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------

function CC.CleanText(text)
  text = string.gsub(tostring(text or ""), "[\\|]", "")
  return string.sub(text, 1, 40)
end

-- The first build of this feature kept only names, with assignments in a
-- separate item -> category map. Those become each category's item list.
function CC.Migrate(db)
  if type(db.items) ~= "table" then return end
  local itemId, categoryId
  for itemId, categoryId in pairs(db.items) do
    local i
    for i = 1, table.getn(db.list) do
      local cat = db.list[i]
      if type(cat) == "table" and cat.id == categoryId and tonumber(itemId) then
        if type(cat.items) ~= "table" then cat.items = {} end
        table.insert(cat.items, tonumber(itemId))
      end
    end
  end
  db.items = nil
end

-- Read once per bag slot during a layout, so the ready table is returned.
function CC.Store()
  if CC.store then return CC.store end
  local db = U.G(CC.DB_NAME)
  if type(db) ~= "table" then
    U.SetG(CC.DB_NAME, {})
    db = U.G(CC.DB_NAME)
    -- A rejected global write leaves a session-only table: categories stop
    -- surviving a reload, but they still work this session.
    if type(db) ~= "table" then db = {} end
  end
  if type(db.list) ~= "table" then db.list = {} end
  db.nextId = math.max(1, math.floor(tonumber(db.nextId) or 1))
  CC.Migrate(db)
  db.version = CC.DB_VERSION
  CC.store = db
  return db
end

function CC.Fold(text)
  if type(text) ~= "string" then return "" end
  if type(U.SearchFold) == "function" then return U.SearchFold(text) end
  return string.lower(text)
end

-- Repairs one stored category in place; false drops it.
function CC.Normalise(cat)
  if type(cat) ~= "table" or type(cat.id) ~= "number" then return false end
  cat.name = type(cat.name) == "string" and CC.CleanText(cat.name) or ""
  cat.priority = math.max(1, math.min(100, math.floor(tonumber(cat.priority) or 50)))
  if cat.mode ~= "any" then cat.mode = "all" end
  if type(cat.rules) ~= "table" then cat.rules = {} end
  if type(cat.items) ~= "table" then cat.items = {} end

  local rules, items, seen = {}, {}, {}
  local i
  for i = 1, table.getn(cat.rules) do
    local rule = cat.rules[i]
    if type(rule) == "table" and CC.kindById[rule.kind] and
       table.getn(rules) < CC.MAX_RULES then
      rule.text = type(rule.text) == "string" and CC.CleanText(rule.text) or ""
      if type(rule.value) == "string" then rule.value = CC.CleanText(rule.value) end
      if type(rule.value2) == "string" then rule.value2 = CC.CleanText(rule.value2) end
      rule.negate = rule.negate and true or false
      table.insert(rules, rule)
    end
  end
  for i = 1, table.getn(cat.items) do
    local id = tonumber(cat.items[i])
    if id and id > 0 and not seen[id] and table.getn(items) < CC.MAX_ITEMS then
      seen[id] = true
      table.insert(items, id)
    end
  end
  cat.rules = rules
  cat.items = items
  return true
end

function CC.Find(id)
  local list = CC.Store().list
  local i
  for i = 1, table.getn(list) do
    if type(list[i]) == "table" and list[i].id == id then return list[i], i end
  end
  return nil
end

function CC.DisplayName(cat)
  if cat.name ~= "" then return cat.name end
  return U.L("CUSTOMCAT_DEFAULT_NAME", cat.id)
end

-- Every edit ends here: the compiled list is rebuilt on its next read and the
-- category views redraw.
function CC.Changed()
  CC.version = CC.version + 1
  if type(U.RefreshBagCategoryViews) == "function" then U.RefreshBagCategoryViews() end
end

-- ---------------------------------------------------------------------------
-- Compiled rules
-- ---------------------------------------------------------------------------

-- A text or number rule with nothing in it is left out, so a fresh rule never
-- catches every item.
function CC.Prepare(rule)
  local kind = CC.kindById[rule.kind]
  local p = { kind = rule.kind, negate = rule.negate, test = CC.test[rule.kind],
              scan = kind.scan }
  if kind.value == "text" then
    p.needle = CC.Fold(rule.text)
    if p.needle == "" then return nil end
  elseif kind.value == "number" then
    p.number = tonumber(rule.text)
    if not p.number then return nil end
  elseif kind.value then
    if rule.value == nil or rule.value == "" then return nil end
    p.value = rule.value
    -- Item type names and class tokens compare case-blind; equip tokens and
    -- built-in keys are compared as stored.
    if type(rule.value) == "string" and (kind.value == "type" or
       kind.value == "subtype" or kind.value == "class") then
      p.value = string.lower(rule.value)
    end
    p.number = tonumber(rule.value)
    if kind.value == "subtype" then
      if type(rule.value2) ~= "string" or rule.value2 == "" then return nil end
      p.value2 = string.lower(rule.value2)
    end
  end
  return p
end

function CC.Compiled()
  local store = CC.Store()
  if CC.compiled and CC.compiledVersion == CC.version then
    return CC.compiled
  end

  local list, byKey, seen = {}, {}, {}
  local i, k
  for i = 1, table.getn(store.list) do
    local cat = store.list[i]
    if CC.Normalise(cat) and not seen[cat.id] then
      seen[cat.id] = true
      local entry = { key = CC.KEY .. cat.id, cat = cat, items = {}, rules = {},
                      any = cat.mode == "any" }
      for k = 1, table.getn(cat.items) do entry.items[cat.items[k]] = true end
      for k = 1, table.getn(cat.rules) do
        local p = CC.Prepare(cat.rules[k])
        if p then table.insert(entry.rules, p) end
      end
      table.insert(list, entry)
      byKey[entry.key] = entry
    end
  end
  table.sort(list, function(a, b)
    if a.cat.priority ~= b.cat.priority then return a.cat.priority > b.cat.priority end
    return a.cat.id < b.cat.id
  end)

  CC.compiled = list
  CC.byKey = byKey
  CC.compiledVersion = CC.version
  return list
end

-- ---------------------------------------------------------------------------
-- Item facts
-- ---------------------------------------------------------------------------

-- GetItemInfo's tuple on this client: name, link, quality, minLevel, type,
-- subType, stackCount, equipLoc, texture (documentation.json /
-- global:Item:GetItemInfo, DOCUMENTED_NOT_RUNTIME_VERIFIED). It is handed the
-- link as core/itemcategory.lua hands it, and cached by the item string inside
-- it. A cache miss is not stored, so the next layout tries again.
function CC.Info(link)
  if type(link) ~= "string" then return nil end
  local _, _, key = string.find(link, "(item:[%-%d:]+)")
  key = key or link
  local info = CC.info[key]
  if info then return info end
  local ok, name, _, quality, minLevel, itemType, subType, stack, equipLoc,
        texture = pcall(GetItemInfo, link)
  if not ok or type(name) ~= "string" then return nil end
  equipLoc = type(equipLoc) == "string" and equipLoc or ""
  info = {
    fold = CC.Fold(name),
    quality = tonumber(quality),
    minLevel = tonumber(minLevel) or 0,
    typeName = type(itemType) == "string" and itemType or "",
    subTypeName = type(subType) == "string" and subType or "",
    stack = tonumber(stack) or 1,
    equip = CC.EQUIP_ALIAS[equipLoc] or equipLoc,
    texture = texture,
    name = name,
  }
  info.type = string.lower(info.typeName)
  info.subType = string.lower(info.subTypeName)
  CC.info[key] = info
  return info
end

-- The shared scanner helpers (core/compat.lua) arm and hide the tooltip; the
-- same SetBagItem read modules/characterflyout.lua already does. The bank's
-- main slots are inventory slots (BankButtonIDToInvSlotID, as core/compat.lua
-- maps them for pickups).
function CC.ReadLines(tip, bag, slot)
  local okSet
  if bag == -1 then
    local okSlot, invSlot = pcall(BankButtonIDToInvSlotID, slot)
    okSet = okSlot and invSlot and pcall(tip.SetInventoryItem, tip, "player", invSlot)
  else
    okSet = pcall(tip.SetBagItem, tip, bag, slot)
  end
  if not okSet then return {} end
  local countOk, count = pcall(tip.NumLines, tip)
  count = math.min(countOk and tonumber(count) or 0, CC.MAX_TIP_LINES)
  local out = {}
  local i
  for i = 1, count do
    local text = U.TooltipRegionText(U.G(CC.SCANNER .. "TextLeft" .. i))
    if text then table.insert(out, CC.Fold(text)) end
  end
  return out
end

-- Folded tooltip lines of the slot being tested. Cached per slot until that
-- bag changes.
function CC.Lines(ctx)
  if ctx.lines then return ctx.lines end
  ctx.lines = {}
  if not ctx.scan then return ctx.lines end
  local bagCache = CC.lines[ctx.bag]
  if not bagCache then
    bagCache = {}
    CC.lines[ctx.bag] = bagCache
  end
  local cached = bagCache[ctx.slot]
  if cached and cached.link == ctx.link then
    ctx.lines = cached.text
    return ctx.lines
  end
  if not CC.scanner then CC.scanner = U.CreateScannerTooltip(CC.SCANNER, UIParent) end
  local text = U.ScanWithTooltip(CC.scanner, CC.ReadLines, ctx.bag, ctx.slot)
  if type(text) ~= "table" then text = {} end
  bagCache[ctx.slot] = { link = ctx.link, text = text }
  ctx.lines = text
  return text
end

function CC.TooltipHas(ctx, needle)
  if not needle or needle == "" then return false end
  local lines = CC.Lines(ctx)
  local i
  for i = 1, table.getn(lines) do
    if string.find(lines[i], needle, 1, true) then return true end
  end
  return false
end

function CC.PlayerClass()
  if not CC.playerClass then
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then CC.playerClass = token end
  end
  return CC.playerClass
end

CC.test = {}
function CC.test.name(p, ctx) return string.find(ctx.info.fold, p.needle, 1, true) ~= nil end
function CC.test.nameexact(p, ctx) return ctx.info.fold == p.needle end
function CC.test.id(p, ctx) return ctx.id == p.number end
function CC.test.type(p, ctx) return ctx.info.type == p.value end
function CC.test.subtype(p, ctx)
  return ctx.info.type == p.value and ctx.info.subType == p.value2
end
function CC.test.quality(p, ctx) return ctx.info.quality == p.number end
function CC.test.equip(p, ctx) return ctx.info.equip == p.value end
function CC.test.minlevel(p, ctx) return ctx.info.minLevel >= p.number end
function CC.test.stacks(p, ctx) return ctx.info.stack > 1 end
function CC.test.soulbound(p, ctx)
  return CC.TooltipHas(ctx, CC.Fold(U.G("ITEM_SOULBOUND") or "Soulbound"))
end
function CC.test.boe(p, ctx)
  return CC.TooltipHas(ctx, CC.Fold(U.G("ITEM_BIND_ON_EQUIP") or "Binds when equipped"))
end
function CC.test.tooltip(p, ctx) return CC.TooltipHas(ctx, p.needle) end
function CC.test.bag(p, ctx) return ctx.bag == p.number end
function CC.test.class(p, ctx)
  local token = CC.PlayerClass()
  return token ~= nil and string.lower(token) == p.value
end
function CC.test.builtin(p, ctx)
  if not ctx.builtin then
    if ctx.scan then
      ctx.builtin = U.ItemCategoryForSlot(ctx.bag, ctx.slot)
    else
      ctx.builtin = U.ItemCategoryFromLink(ctx.link)
    end
  end
  return ctx.builtin == p.value
end

function CC.Matches(entry, ctx)
  if ctx.id and entry.items[ctx.id] then return true end
  local n = table.getn(entry.rules)
  if n == 0 or not ctx.info then return false end
  local i
  for i = 1, n do
    local p = entry.rules[i]
    local ok, hit = pcall(p.test, p, ctx)
    hit = (ok and hit) and true or false
    if p.negate then hit = not hit end
    if entry.any then
      if hit then return true end
    elseif not hit then
      return false
    end
  end
  return not entry.any
end

-- ---------------------------------------------------------------------------
-- Public surface (modules/bagcategoryview.lua, core/itemcategory.lua)
-- ---------------------------------------------------------------------------

function U.HasCustomCategories()
  return table.getn(CC.Compiled()) > 0
end

-- The category key for one item, or nil. `scan` says the slot is live, so its
-- tooltip can be read.
function U.CustomItemCategory(link, bag, slot, scan)
  if type(link) ~= "string" then return nil end
  local list = CC.Compiled()
  if table.getn(list) == 0 then return nil end
  local ctx = CC.ctx
  ctx.link = link
  ctx.bag = bag
  ctx.slot = slot
  ctx.scan = (scan and bag and slot) and true or false
  ctx.info = CC.Info(link)
  ctx.id = U.ItemLinkId(link)
  ctx.builtin = nil
  ctx.lines = nil
  local i
  for i = 1, table.getn(list) do
    if CC.Matches(list[i], ctx) then return list[i].key end
  end
  return nil
end

function U.CustomCategoryOrder()
  local list = CC.Compiled()
  local keys = {}
  local i
  for i = 1, table.getn(list) do keys[i] = list[i].key end
  return keys
end

function U.CustomCategoryLabel(key)
  if type(key) ~= "string" or string.sub(key, 1, 6) ~= CC.KEY then return nil end
  CC.Compiled()
  local entry = CC.byKey and CC.byKey[key]
  if not entry then return nil end
  return CC.DisplayName(entry.cat)
end

-- ---------------------------------------------------------------------------
-- Value lists for the editor's menus
-- ---------------------------------------------------------------------------

function CC.Packed(fn, a1)
  if type(fn) ~= "function" then return {} end
  local packed = { pcall(fn, a1) }
  local out = {}
  if not packed[1] then return out end
  local i
  for i = 2, table.getn(packed) do
    if type(packed[i]) == "string" and packed[i] ~= "" then table.insert(out, packed[i]) end
  end
  return out
end

-- Calls add(typeName, subTypeName) for every item in the carried bags, so a
-- type the auction list lacks (Quest, Key) can still be picked.
function CC.EachCarriedType(add)
  local bag, slot
  for bag = 0, 4 do
    for slot = 1, U.ContainerSlotCount(bag) do
      local link = U.ContainerSlotLink(bag, slot)
      local info = link and CC.Info(link)
      if info and info.typeName ~= "" then add(info.typeName, info.subTypeName) end
    end
  end
end

function CC.AddUnique(list, seen, text)
  if type(text) ~= "string" or text == "" then return end
  local key = string.lower(text)
  if seen[key] then return end
  seen[key] = true
  table.insert(list, { text = text, value = text })
end

function CC.TypeItems(current)
  local list, seen = {}, {}
  local classes = CC.Packed(U.G("GetAuctionItemClasses"))
  if table.getn(classes) == 0 then classes = CC.FALLBACK_TYPES end
  local i
  for i = 1, table.getn(classes) do CC.AddUnique(list, seen, classes[i]) end
  CC.EachCarriedType(function(typeName) CC.AddUnique(list, seen, typeName) end)
  CC.AddUnique(list, seen, current)
  return list
end

function CC.SubtypeItems(typeName, current)
  local list, seen = {}, {}
  if type(typeName) == "string" and typeName ~= "" then
    local lowered = string.lower(typeName)
    local classes = CC.Packed(U.G("GetAuctionItemClasses"))
    local i
    for i = 1, table.getn(classes) do
      if string.lower(classes[i]) == lowered then
        local subs = CC.Packed(U.G("GetAuctionItemSubClasses"), i)
        local k
        for k = 1, table.getn(subs) do CC.AddUnique(list, seen, subs[k]) end
      end
    end
    CC.EachCarriedType(function(t, sub)
      if string.lower(t) == lowered then CC.AddUnique(list, seen, sub) end
    end)
  end
  CC.AddUnique(list, seen, current)
  return list
end

function CC.ValueItems(kind)
  local list = {}
  local i
  if kind == "quality" then
    for i = 0, 6 do table.insert(list, { text = U.L("LOOT_QUALITY_" .. i), value = i }) end
  elseif kind == "equip" then
    for i = 1, table.getn(CC.EQUIP) do
      local token = CC.EQUIP[i]
      local label = U.G(token)
      if type(label) ~= "string" or label == "" then label = token end
      table.insert(list, { text = label, value = token })
    end
  elseif kind == "bag" then
    for i = 1, table.getn(CC.BAGS) do
      local bag = CC.BAGS[i]
      local text
      if bag == 0 then
        text = U.L("CUSTOMCAT_BAG_BACKPACK")
      elseif bag == -1 then
        text = U.L("CUSTOMCAT_BAG_BANK")
      elseif bag <= 4 then
        text = U.L("CUSTOMCAT_BAG_N", bag)
      else
        text = U.L("CUSTOMCAT_BAG_BANKBAG", bag - 4)
      end
      table.insert(list, { text = text, value = bag })
    end
  elseif kind == "class" then
    for i = 1, table.getn(CC.CLASSES) do
      table.insert(list, { text = U.L("CUSTOMCAT_CLASS_" .. CC.CLASSES[i]),
                           value = CC.CLASSES[i] })
    end
  elseif kind == "builtin" then
    local order = U.ItemCategoryOrder()
    for i = 1, table.getn(order) do
      if order[i] ~= U.ItemCategoryFavorite() then
        table.insert(list, { text = U.ItemCategoryLabel(order[i]), value = order[i] })
      end
    end
  end
  return list
end

function CC.DefaultRule(kindId)
  local rule = { kind = kindId, text = "", negate = false }
  local kind = CC.kindById[kindId]
  if kind.value == "type" or kind.value == "subtype" then
    local types = CC.TypeItems()
    rule.value = types[1] and types[1].value or nil
    if kind.value == "subtype" then
      local subs = CC.SubtypeItems(rule.value)
      rule.value2 = subs[1] and subs[1].value or nil
    end
  elseif kind.value and kind.value ~= "text" and kind.value ~= "number" then
    local items = CC.ValueItems(kind.value)
    rule.value = items[1] and items[1].value or nil
    if kind.value == "class" then rule.value = CC.PlayerClass() or rule.value end
  end
  return rule
end

-- ---------------------------------------------------------------------------
-- Editor actions
-- ---------------------------------------------------------------------------

function CC.Selected()
  if not CC.ui.selected then return nil end
  return CC.Find(CC.ui.selected)
end

function CC.NextId(store)
  local id = math.max(1, math.floor(tonumber(store.nextId) or 1))
  while CC.Find(id) do id = id + 1 end
  store.nextId = id + 1
  return id
end

function CC.New()
  local store = CC.Store()
  if table.getn(store.list) >= CC.MAX_CATEGORIES then return end
  local id = CC.NextId(store)
  local cat = { id = id, name = "", priority = 50, mode = "all", rules = {}, items = {} }
  cat.name = CC.CleanText(U.L("CUSTOMCAT_DEFAULT_NAME", id))
  table.insert(store.list, cat)
  CC.ui.selected = id
  CC.Changed()
  CC.Refresh()
end

function CC.Copy()
  local source = CC.Selected()
  local store = CC.Store()
  if not source or table.getn(store.list) >= CC.MAX_CATEGORIES then return end
  local id = CC.NextId(store)
  local cat = {
    id = id, priority = source.priority, mode = source.mode, rules = {}, items = {},
    name = CC.CleanText(U.L("CUSTOMCAT_COPY_NAME", CC.DisplayName(source))),
  }
  local i
  for i = 1, table.getn(source.rules) do
    local r = source.rules[i]
    table.insert(cat.rules, { kind = r.kind, value = r.value, value2 = r.value2,
                              text = r.text, negate = r.negate })
  end
  for i = 1, table.getn(source.items) do cat.items[i] = source.items[i] end
  table.insert(store.list, cat)
  CC.ui.selected = id
  CC.Changed()
  CC.Refresh()
end

function CC.Delete()
  local cat = CC.Selected()
  if not cat then return end
  local id = cat.id
  U.ShowConfirm({
    owner = "bags.customcat-delete",
    centered = true,
    text = U.L("CUSTOMCAT_DELETE_CONFIRM", CC.DisplayName(cat)),
    onAccept = function()
      local _, index = CC.Find(id)
      if index then table.remove(CC.Store().list, index) end
      if CC.ui.selected == id then CC.ui.selected = nil end
      CC.Changed()
      CC.Refresh()
    end,
  })
end

function CC.Edit(fn)
  local cat = CC.Selected()
  if not cat then return end
  fn(cat)
  CC.Changed()
end

-- The item on the cursor joins the list and goes back to its slot. The record
-- is the last UnrealUI pickup; it is only trusted while that slot is still
-- locked and still holds the same item.
function CC.DropCursorItem()
  if not U.CursorHasItem() then return false end
  local source = type(U.BagCategoryCursorSource) == "function" and
                 U.BagCategoryCursorSource()
  local id = source and U.ItemLinkId(source.link)
  if id then
    local _, _, locked = U.ContainerSlotInfo(source.bagNum, source.slotNum)
    if not locked or
       U.ContainerSlotLink(source.bagNum, source.slotNum) ~= source.link then
      id = nil
    end
  end
  if not id then
    U.Print(U.L("CUSTOMCAT_DROP_UNKNOWN"))
    return true
  end
  pcall(ClearCursor)
  CC.AddItem(id)
  return true
end

function CC.AddItem(id)
  id = tonumber(id)
  if not id or id <= 0 then return end
  CC.Edit(function(cat)
    local i
    for i = 1, table.getn(cat.items) do
      if cat.items[i] == id then return end
    end
    if table.getn(cat.items) < CC.MAX_ITEMS then table.insert(cat.items, id) end
  end)
  CC.Refresh()
end

function CC.RemoveItem(index)
  CC.Edit(function(cat) table.remove(cat.items, index) end)
  U.HideInfoTooltip()
  CC.Refresh()
end

-- ---------------------------------------------------------------------------
-- Editor UI (the Bags settings page)
-- ---------------------------------------------------------------------------

function CC.SetShown(control, shown)
  if not control then return end
  if type(control.uuiSetShown) == "function" then
    control.uuiSetShown(shown)
  elseif control.uuiParts then
    local i
    for i = 1, table.getn(control.uuiParts) do
      local part = control.uuiParts[i]
      if shown then part:Show() else part:Hide() end
    end
  elseif shown then
    control:Show()
  else
    control:Hide()
  end
end

function CC.Label(parent, key, color)
  local label = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = color or M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = 86,
  })
  if label then label:SetText(U.L(key)) end
  return label
end

-- A "?" beside a label whose hover explains the setting, on the shared info
-- tooltip (core/widgets.lua). The locale string is one tooltip line per "\n":
-- the tooltip does not wrap, so lines stay short.
function CC.HelpMark(parent, titleKey, tipKey)
  local mark = CreateFrame("Button", nil, parent)
  mark:SetWidth(14)
  mark:SetHeight(16)
  pcall(mark.EnableMouse, mark, true)
  mark.text = U.CreateLabel(mark, {
    size = M.fontSize.small, color = M.color.textDim,
    inherits = "GameFontNormalSmall", justify = "CENTER",
  })
  if mark.text then
    mark.text:SetPoint("CENTER", mark, "CENTER", 0, 0)
    mark.text:SetText("?")
  end
  mark:SetScript("OnEnter", function()
    if mark.text then pcall(mark.text.SetTextColor, mark.text, M.Unpack(M.color.accent)) end
    if type(U.ShowInfoTooltip) ~= "function" then return end
    local lines = { { U.L(titleKey), M.color.accent } }
    local rest = U.L(tipKey)
    while rest and rest ~= "" do
      local cut = string.find(rest, "\n", 1, true)
      local line = cut and string.sub(rest, 1, cut - 1) or rest
      rest = cut and string.sub(rest, cut + 1) or nil
      table.insert(lines, { line, M.color.text })
    end
    U.ShowInfoTooltip(mark, lines)
  end)
  mark:SetScript("OnLeave", function()
    if mark.text then pcall(mark.text.SetTextColor, mark.text, M.Unpack(M.color.textDim)) end
    U.HideInfoTooltip()
  end)
  return mark
end

function CC.Button(parent, key, width, onClick)
  local button = U.CreateButton(parent, {
    text = U.L(key), width = width, height = 22, size = M.fontSize.small,
    onClick = onClick,
  })
  table.insert(CC.ui.styled, button)
  return button
end

function CC.Dropdown(parent, width, onChange, name)
  local control = U.CreateDropdown(parent, {
    name = name, width = width, height = 24, rowHeight = 18,
    items = { { text = "", value = 0 } },
    onChange = onChange,
  })
  table.insert(CC.ui.styled, control)
  return control
end

function CC.TextBox(parent, width, placeholder, onChange)
  local box = U.CreateSearchBox(parent, {
    placeholder = U.L(placeholder), onChange = onChange, noIcon = true,
  })
  if box then
    box:SetWidth(width)
    U.PaintSearchBox(box)
  end
  return box
end

function CC.BuildRuleRow(body, index)
  local row = { index = index }
  local function Rule()
    local cat = CC.Selected()
    return cat and cat.rules[index]
  end

  row.negate = U.CreateCheckbox(body, {
    text = U.L("CUSTOMCAT_NOT"), textWidth = 30,
    onChange = function(value)
      CC.Edit(function(cat)
        if cat.rules[index] then cat.rules[index].negate = value and true or false end
      end)
    end,
  })
  table.insert(CC.ui.styled, row.negate)

  local kinds = {}
  local i
  for i = 1, table.getn(CC.kinds) do
    kinds[i] = { text = U.L(CC.kinds[i].label), value = CC.kinds[i].id }
  end
  row.kind = CC.Dropdown(body, 150, function(value)
    CC.Edit(function(cat)
      local old = cat.rules[index]
      local rule = CC.DefaultRule(value)
      if old then rule.negate = old.negate end
      cat.rules[index] = rule
    end)
    CC.Refresh()
  end)
  row.kind.SetItems(kinds)

  row.value = CC.Dropdown(body, 170, function(value)
    CC.Edit(function(cat)
      local rule = cat.rules[index]
      if not rule then return end
      rule.value = value
      if CC.kindById[rule.kind].value == "subtype" then
        local subs = CC.SubtypeItems(value)
        rule.value2 = subs[1] and subs[1].value or nil
      end
    end)
    CC.Refresh()
  end)
  row.value2 = CC.Dropdown(body, 110, function(value)
    CC.Edit(function(cat)
      if cat.rules[index] then cat.rules[index].value2 = value end
    end)
  end)
  row.text = CC.TextBox(body, 170, "CUSTOMCAT_VALUE", function(text)
    local clean = CC.CleanText(text)
    CC.Edit(function(cat)
      if cat.rules[index] then cat.rules[index].text = clean end
    end)
  end)
  row.remove = CC.Button(body, "CUSTOMCAT_REMOVE", 24, function()
    CC.Edit(function(cat) table.remove(cat.rules, index) end)
    CC.Refresh()
  end)
  row.Rule = Rule
  return row
end

function CC.LayoutRuleRow(row, y)
  local ui = CC.ui
  local rule = row.Rule()
  local shown = rule ~= nil
  CC.SetShown(row.negate, shown)
  CC.SetShown(row.kind, shown)
  CC.SetShown(row.remove, shown)
  local kind = rule and CC.kindById[rule.kind]
  local valueKind = kind and kind.value
  local isText = valueKind == "text" or valueKind == "number"
  local isMenu = valueKind and not isText
  CC.SetShown(row.value, isMenu)
  CC.SetShown(row.value2, valueKind == "subtype")
  if row.text then CC.SetShown(row.text, isText) end
  if not shown then return end

  row.negate.SetPoint("LEFT", ui.body, "TOPLEFT", 0, y - 12)
  row.negate.SetValue(rule.negate)
  row.kind.SetPoint("TOPLEFT", ui.body, "TOPLEFT", 48, y)
  row.kind.SetValue(rule.kind, false)
  row.remove:ClearAllPoints()
  row.remove:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 434, y - 1)

  if isMenu then
    local items
    if valueKind == "type" or valueKind == "subtype" then
      items = CC.TypeItems(rule.value)
    else
      items = CC.ValueItems(valueKind)
    end
    row.value.SetItems(items, rule.value)
    pcall(row.value.button.SetWidth, row.value.button,
          valueKind == "subtype" and 110 or 170)
    row.value.SetPoint("TOPLEFT", ui.body, "TOPLEFT", 204, y)
    if valueKind == "subtype" then
      row.value2.SetItems(CC.SubtypeItems(rule.value, rule.value2), rule.value2)
      row.value2.SetPoint("TOPLEFT", ui.body, "TOPLEFT", 318, y)
    end
  elseif isText and row.text then
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 204, y - 1)
    U.SetSearchBoxText(row.text, rule.text)
    U.LevelSearchBox(row.text, (tonumber(ui.body:GetFrameLevel()) or 0) + 2)
  end
end

function CC.ItemIcon(index)
  local ui = CC.ui
  local icon = ui.icons[index]
  if icon then return icon end
  icon = CreateFrame("Button", nil, ui.zone)
  icon:SetWidth(CC.ICON)
  icon:SetHeight(CC.ICON)
  U.CreateBackdrop(icon, {})
  pcall(icon.EnableMouse, icon, true)
  icon.art = icon:CreateTexture(nil, "ARTWORK")
  icon.art:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  icon.art:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  pcall(icon.art.SetTexCoord, icon.art, 0.07, 0.93, 0.07, 0.93)
  pcall(icon.RegisterForClicks, icon, "LeftButtonUp", "RightButtonUp")
  icon:SetScript("OnClick", function()
    if CC.DropCursorItem() then return end
    CC.RemoveItem(icon.index)
  end)
  icon:SetScript("OnReceiveDrag", function() CC.DropCursorItem() end)
  icon:SetScript("OnEnter", function()
    U.SetBorderColor(icon, M.Unpack(M.color.accentDim))
    U.ShowInfoTooltip(icon, {
      { icon.itemName or ("#" .. tostring(icon.itemId)), M.color.text },
      { U.L("CUSTOMCAT_REMOVE_ITEM"), M.color.textDim },
    })
  end)
  icon:SetScript("OnLeave", function()
    U.SetBorderColor(icon, M.Unpack(M.color.border))
    U.HideInfoTooltip()
  end)
  ui.icons[index] = icon
  return icon
end

-- Lays the item list out and returns the zone's height.
function CC.LayoutItems(cat)
  local ui = CC.ui
  local perRow = math.floor((U.SETTINGS_PAGE_WIDTH - 8 + CC.ICON_GAP) /
                            (CC.ICON + CC.ICON_GAP))
  local count = table.getn(cat.items)
  local i
  for i = 1, count do
    local icon = CC.ItemIcon(i)
    local id = cat.items[i]
    local info = CC.Info("item:" .. id .. ":0:0:0")
    icon.index = i
    icon.itemId = id
    icon.itemName = info and info.name or nil
    icon.art:SetTexture((info and info.texture) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local column = math.mod(i - 1, perRow)
    local line = math.floor((i - 1) / perRow)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", ui.zone, "TOPLEFT", 4 + column * (CC.ICON + CC.ICON_GAP),
                  -4 - line * (CC.ICON + CC.ICON_GAP))
    icon:Show()
  end
  for i = count + 1, table.getn(ui.icons) do ui.icons[i]:Hide() end
  if ui.zoneHint then
    if count == 0 then ui.zoneHint:Show() else ui.zoneHint:Hide() end
  end
  local lines = math.max(1, math.ceil(count / perRow))
  return 8 + lines * CC.ICON + (lines - 1) * CC.ICON_GAP
end

function CC.BuildBody(parent)
  local ui = CC.ui
  local body = CreateFrame("Frame", "UnrealUISettingsCustomCatBody", parent)
  body:SetWidth(U.SETTINGS_PAGE_WIDTH)
  body:SetHeight(1)
  ui.body = body

  ui.nameLabel = CC.Label(body, "CUSTOMCAT_NAME")
  ui.name = CC.TextBox(body, 200, "CUSTOMCAT_NAME", function(text)
    local clean = CC.CleanText(text)
    CC.Edit(function(cat) cat.name = clean end)
    CC.RefreshPicker()
  end)

  ui.priorityLabel = CC.Label(body, "CUSTOMCAT_PRIORITY")
  ui.priorityHelp = CC.HelpMark(body, "CUSTOMCAT_PRIORITY", "CUSTOMCAT_PRIORITY_TIP")
  ui.priority = U.CreateSlider(body, {
    text = "", width = 200, min = 1, max = 100, step = 1, value = 50,
    onChange = function(value)
      if ui.loading then return end
      CC.Edit(function(cat) cat.priority = math.floor(tonumber(value) or 50) end)
    end,
  })
  table.insert(ui.styled, ui.priority)

  ui.matchLabel = CC.Label(body, "CUSTOMCAT_MATCH")
  ui.matchHelp = CC.HelpMark(body, "CUSTOMCAT_MATCH", "CUSTOMCAT_MATCH_TIP")
  ui.match = CC.Dropdown(body, 200, function(value)
    CC.Edit(function(cat) cat.mode = value end)
  end, "UnrealUISettingsCustomCatMatch")
  ui.match.SetItems({
    { text = U.L("CUSTOMCAT_MATCH_ALL"), value = "all" },
    { text = U.L("CUSTOMCAT_MATCH_ANY"), value = "any" },
  })

  ui.rulesLabel = CC.Label(body, "CUSTOMCAT_RULES", M.color.accent)
  ui.rulesHelp = CC.HelpMark(body, "CUSTOMCAT_RULES", "CUSTOMCAT_RULES_TIP")
  local i
  for i = 1, CC.MAX_RULES do ui.rows[i] = CC.BuildRuleRow(body, i) end
  ui.addRule = CC.Button(body, "CUSTOMCAT_ADD_RULE", 110, function()
    CC.Edit(function(cat)
      if table.getn(cat.rules) < CC.MAX_RULES then
        table.insert(cat.rules, CC.DefaultRule("name"))
      end
    end)
    CC.Refresh()
  end)

  ui.itemsLabel = CC.Label(body, "CUSTOMCAT_ITEMS", M.color.accent)
  ui.itemsHint = U.CreateSettingsLabel(body, {
    size = M.fontSize.small, color = M.color.textDim,
    inherits = "GameFontNormalSmall", justify = "LEFT",
    width = U.SETTINGS_PAGE_WIDTH,
  })
  if ui.itemsHint then ui.itemsHint:SetText(U.L("CUSTOMCAT_ITEMS_HINT")) end

  local zone = CreateFrame("Button", "UnrealUISettingsCustomCatItems", body)
  zone:SetWidth(U.SETTINGS_PAGE_WIDTH)
  zone:SetHeight(32)
  U.CreateBackdrop(zone, {})
  pcall(zone.EnableMouse, zone, true)
  pcall(zone.RegisterForClicks, zone, "LeftButtonUp")
  zone:SetScript("OnClick", function() CC.DropCursorItem() end)
  zone:SetScript("OnReceiveDrag", function() CC.DropCursorItem() end)
  ui.zone = zone
  ui.zoneHint = U.CreateLabel(zone, {
    size = M.fontSize.small, color = M.color.textDim,
    inherits = "GameFontDisableSmall", justify = "CENTER",
  })
  if ui.zoneHint then
    ui.zoneHint:SetPoint("CENTER", zone, "CENTER", 0, 0)
    ui.zoneHint:SetText(U.L("CUSTOMCAT_ITEMS_DROP"))
  end

  ui.idBox = CC.TextBox(body, 120, "CUSTOMCAT_ITEM_ID", nil)
  ui.addId = CC.Button(body, "CUSTOMCAT_ADD_ID", 80, function()
    local id = tonumber(U.SearchBoxText(ui.idBox))
    if ui.idBox then U.ResetSearchBox(ui.idBox) end
    if id then CC.AddItem(id) end
  end)
end

-- Sits right after the label's text, inside the label's 86 px column.
function CC.PlaceHelp(mark, label, y)
  if not mark then return end
  local x = 70
  if label then
    local ok, width = pcall(label.GetStringWidth, label)
    width = ok and tonumber(width) or nil
    if width and width > 0 then x = math.min(width + 1, 72) end
  end
  mark:ClearAllPoints()
  mark:SetPoint("LEFT", CC.ui.body, "TOPLEFT", x, y)
end

-- Places every body control from the top down; returns the body's height.
function CC.LayoutBody(cat)
  local ui = CC.ui
  local body = ui.body
  local y = 0
  local function Row(label, offset)
    if label then
      label:ClearAllPoints()
      label:SetPoint("LEFT", body, "TOPLEFT", 0, y - (offset or 12))
    end
  end

  Row(ui.nameLabel)
  if ui.name then
    ui.name:ClearAllPoints()
    ui.name:SetPoint("LEFT", body, "TOPLEFT", 90, y - 12)
    U.SetSearchBoxText(ui.name, cat.name)
    U.LevelSearchBox(ui.name, (tonumber(body:GetFrameLevel()) or 0) + 2)
  end
  y = y - 34

  Row(ui.priorityLabel, 6)
  CC.PlaceHelp(ui.priorityHelp, ui.priorityLabel, y - 6)
  ui.priority.SetPoint("LEFT", body, "TOPLEFT", 90, y - 6)
  ui.loading = true
  ui.priority.SetValue(cat.priority)
  ui.loading = false
  y = y - 40

  Row(ui.matchLabel)
  CC.PlaceHelp(ui.matchHelp, ui.matchLabel, y - 12)
  ui.match.SetPoint("LEFT", body, "TOPLEFT", 90, y - 12)
  ui.match.SetValue(cat.mode, false)
  y = y - 36

  Row(ui.rulesLabel, 8)
  CC.PlaceHelp(ui.rulesHelp, ui.rulesLabel, y - 8)
  y = y - 20
  local i
  for i = 1, CC.MAX_RULES do
    CC.LayoutRuleRow(ui.rows[i], y)
    if cat.rules[i] then y = y - 30 end
  end
  ui.addRule:ClearAllPoints()
  ui.addRule:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y - 2)
  if table.getn(cat.rules) >= CC.MAX_RULES then ui.addRule:Disable() else ui.addRule:Enable() end
  y = y - 40

  Row(ui.itemsLabel, 8)
  y = y - 18
  if ui.itemsHint then
    ui.itemsHint:ClearAllPoints()
    ui.itemsHint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    -- The hint wraps per language; one or two lines are reserved.
    local height = tonumber(ui.itemsHint:GetHeight()) or 12
    y = y - math.max(26, math.min(40, height)) - 6
  end
  ui.zone:ClearAllPoints()
  ui.zone:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
  local zoneHeight = CC.LayoutItems(cat)
  ui.zone:SetHeight(math.max(32, zoneHeight))
  y = y - math.max(32, zoneHeight) - 8

  if ui.idBox then
    ui.idBox:ClearAllPoints()
    ui.idBox:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    U.LevelSearchBox(ui.idBox, (tonumber(body:GetFrameLevel()) or 0) + 2)
  end
  ui.addId:ClearAllPoints()
  ui.addId:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y)
  y = y - 30

  return -y
end

function CC.RefreshPicker()
  local ui = CC.ui
  if not ui.pick then return end
  local list = CC.Store().list
  local items = {}
  local i
  for i = 1, table.getn(list) do
    local cat = list[i]
    if CC.Normalise(cat) then
      table.insert(items, { text = CC.DisplayName(cat), value = cat.id })
    end
  end
  if not CC.Find(ui.selected or -1) then
    ui.selected = items[1] and items[1].value or nil
  end
  if table.getn(items) == 0 then
    items = { { text = U.L("CUSTOMCAT_NONE"), value = 0 } }
  end
  ui.pick.SetItems(items, ui.selected or 0)
  local full = table.getn(list) >= CC.MAX_CATEGORIES
  if full then ui.new:Disable() else ui.new:Enable() end
  if ui.selected and not full then ui.copy:Enable() else ui.copy:Disable() end
  if ui.selected then ui.delete:Enable() else ui.delete:Disable() end
end

-- The picker bar hangs on the host, past the header title and the hint, not
-- on the hint itself: everything in this editor sits below the bar, and a
-- FontString in that chain is re-measured for each of them on every move of
-- the page (U.SettingsDescriptionDrop, core/widgets.lua). The title is the
-- section header's fixed-height label.
function CC.PlaceBar()
  local ui = CC.ui
  if not ui.bar or not ui.host then return end
  local title = ui.header and ui.header.title
  local titleHeight = 18
  if title then
    local ok, height = pcall(title.GetHeight, title)
    if ok and tonumber(height) and height > 0 then titleHeight = height end
  end
  ui.bar:ClearAllPoints()
  ui.bar:SetPoint("TOPLEFT", ui.host, "TOPLEFT", 0,
                  -(titleHeight + U.SettingsDescriptionDrop(ui.hint) + 12))
end

function CC.Refresh()
  local ui = CC.ui
  if not ui.body then return end
  CC.PlaceBar()
  CC.RefreshPicker()
  local cat = CC.Selected()
  if cat then
    CC.Normalise(cat)
    ui.body:Show()
    ui.body:SetHeight(math.max(1, CC.LayoutBody(cat)))
  else
    ui.body:Hide()
  end
  if type(U.RelayoutIntegratedSettings) == "function" then
    U.RelayoutIntegratedSettings()
  end
end

-- Builds the editor under `anchor` on the Bags settings page. Returns the
-- page widgets (each a direct child of `parent`, so the page measures and
-- toggles them) and the page refresh.
function U.BuildBagCustomCategoryEditor(parent, anchor)
  local ui = CC.ui
  if ui.handle then return ui.handle end
  if not parent or not anchor then return nil end

  local host = CreateFrame("Frame", "UnrealUISettingsCustomCats", parent)
  host:SetWidth(U.SETTINGS_PAGE_WIDTH)
  host:SetHeight(20)
  host:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
  ui.host = host

  ui.header = U.CreateSectionHeader(host, {
    text = U.L("SETTINGS_CUSTOMCAT_TITLE"),
    width = U.SETTINGS_PAGE_WIDTH,
    y = 0,
  })
  ui.hint = U.CreateSettingsLabel(host, {
    size = M.fontSize.small, color = M.color.textDim,
    inherits = "GameFontNormalSmall", justify = "LEFT",
    width = U.SETTINGS_PAGE_WIDTH,
  })
  local hintAnchor = ui.header.title or host
  if ui.hint then
    U.AnchorSettingsDescription(ui.hint, hintAnchor)
    ui.hint:SetText(U.L("SETTINGS_CUSTOMCAT_HINT"))
  end

  local bar = CreateFrame("Frame", "UnrealUISettingsCustomCatBar", parent)
  bar:SetWidth(U.SETTINGS_PAGE_WIDTH)
  bar:SetHeight(28)
  ui.bar = bar
  CC.PlaceBar()

  ui.pick = CC.Dropdown(bar, 200, function(value)
    ui.selected = value ~= 0 and value or nil
    CC.Refresh()
  end, "UnrealUISettingsCustomCatPick")
  ui.pick.SetPoint("LEFT", bar, "LEFT", 0, 0)
  ui.new = CC.Button(bar, "CUSTOMCAT_NEW", 70, CC.New)
  ui.new:SetPoint("LEFT", bar, "LEFT", 208, 0)
  ui.copy = CC.Button(bar, "CUSTOMCAT_COPY", 70, CC.Copy)
  ui.copy:SetPoint("LEFT", ui.new, "RIGHT", 4, 0)
  ui.delete = CC.Button(bar, "CUSTOMCAT_DELETE", 70, CC.Delete)
  ui.delete:SetPoint("LEFT", ui.copy, "RIGHT", 4, 0)

  CC.BuildBody(parent)
  ui.body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)

  -- Art only: these controls are laid out at their own compact widths.
  if type(U.StyleGameSettingsWidgets) == "function" then
    U.StyleGameSettingsWidgets(ui.styled, true)
  end

  ui.handle = {
    widgets = { host, ui.header, ui.hint, bar, ui.body },
    Refresh = CC.Refresh,
    -- The page places the editor on one of its controls (a frame), offset
    -- past that control's description.
    Place = function(anchor, y)
      if not anchor then return end
      host:ClearAllPoints()
      host:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, tonumber(y) or -24)
    end,
  }
  return ui.handle
end

-- A changed bag can hold a different item, or the same one newly bound.
U.RegisterEvent("BAG_UPDATE", function(_, bag)
  bag = tonumber(bag)
  if bag then CC.lines[bag] = nil end
end)
U.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
  CC.lines[-1] = nil
end)
