-- unrealUI :: modules/characterstats.lua
--
-- The Character window's stat readout: what the stats side panel
-- (modules/characterstatspanel.lua) lists. Data only -- nothing here draws.
--
-- The list follows ForeverFrameXML's Camelot PAPERDOLL_STATCATEGORIES, cut to
-- what this client can answer (knowledge.json / character.modern_stat_apis_absent,
-- FOCUSED_RUNTIME_PROBE 2026-09-28): none of the 41 post-1.12 stat functions
-- that panel calls exist here. Three kinds of value therefore appear:
--
--   * read   -- a 1.12 getter measured on this client
--               (character.stat_api_1_12_return_shapes): health, power,
--               attributes, damage, speed, attack power, weapon skill, armor,
--               defense, dodge/parry/block, resistances.
--   * parsed -- a number the client prints in a tooltip, read through a
--               private scanner (statsrc probe, 2026-09-28): melee crit from
--               the Attack spell's tooltip, and each weapon's base Speed,
--               which turns the live attack speed into a haste figure.
--   * estimated -- built from equipped items' tooltip text, learned talent
--               ranks and 1.12 class formulas. The panel marks every one with
--               a "?" whose hover says so. Buffs are never included.
--
-- Tooltip text is read only through U.TooltipRegionText: this client leaves a
-- hidden right-hand region holding the previous tooltip's text (statsrc run:
-- a shirt reported "30 yd range", an off-hand the main hand's "Speed 2.00").
-- Line colour is not usable (every line reported white), so an inactive set
-- bonus is recognised by its "(n) Set:" prefix, not by its grey.
--
-- Item and talent wording is matched in English only. On another client
-- language those parts of an estimate read as 0 and the "?" still warns.
--
-- One top-level table (rules/unreal-ui.md, Lua local budget).

local U = UnrealUI

local CS = {
  SCANNER = "UnrealUICharacterStatsScanner",
  MAX_LINES = 30,
  -- Equipment slots whose tooltips can carry a bonus: head .. ranged. The
  -- ammo slot (0) and the tabard (19) never do.
  GEAR_FIRST = 1,
  GEAR_LAST = 18,
  SLOT_OFFHAND = 17,
  SLOT_RANGED = 18,
  MAX_SPELLS = 300,
  -- UnitResistance school ids in the order the panel lists them, with the
  -- locale key of each label.
  -- The third field is the school's GEAR_BONUS key.
  RESISTANCES = {
    { 6, "CHARSTATS_RES_ARCANE", "res_arcane" },
    { 2, "CHARSTATS_RES_FIRE", "res_fire" },
    { 3, "CHARSTATS_RES_NATURE", "res_nature" },
    { 4, "CHARSTATS_RES_FROST", "res_frost" },
    { 5, "CHARSTATS_RES_SHADOW", "res_shadow" },
  },
  ATTRIBUTES = {
    "CHARSTATS_STR", "CHARSTATS_AGI", "CHARSTATS_STA", "CHARSTATS_INT",
    "CHARSTATS_SPI",
  },
  -- GEAR_BONUS keys of the five UnitStat indices.
  ATTRIBUTE_BONUS = { "str", "agi", "sta", "int", "spi" },
  POWER_LABEL = {
    [0] = "CHARSTATS_MANA", [1] = "CHARSTATS_RAGE", [2] = "CHARSTATS_FOCUS",
    [3] = "CHARSTATS_ENERGY",
  },
  -- Spellbook names whose tooltip prints a crit chance. 1.12 prints it on
  -- Attack ("5.00%  chance to crit", statsrc run 2026-09-28, enUS); the
  -- ranged names are the same convention and are not yet verified -- a name
  -- whose tooltip has no percentage simply leaves the row out.
  MELEE_SPELLS = { ["Attack"] = true, ["Attaque"] = true,
                   ["Атака"] = true, ["攻击"] = true },
  RANGED_SPELLS = { ["Auto Shot"] = true, ["Shoot"] = true, ["Throw"] = true,
                    ["Shoot Bow"] = true, ["Shoot Gun"] = true,
                    ["Shoot Crossbow"] = true, ["Tir automatique"] = true,
                    ["Автоматическая стрельба"] = true, ["自动射击"] = true },
  SCHOOLS = { holy = true, fire = true, nature = true, frost = true,
              shadow = true, arcane = true },
  -- 1.12 item wording, lower-cased, most specific first; one match per line.
  -- `both` feeds spell damage and healing, `school` a single school's damage.
  GEAR_PATTERNS = {
    { "increases damage and healing done by magical spells and effects by up to (%d+)", "both" },
    { "increases healing done by spells and effects by up to (%d+)", "healing" },
    { "increases damage done by (%a+) spells and effects by up to (%d+)", "school" },
    { "healing and spell damage %+(%d+)", "both" },
    { "%+(%d+) damage and healing spells", "both" },
    { "%+(%d+) spell damage and healing", "both" },
    { "%+(%d+) healing spells", "healing" },
    { "%+(%d+) (%a+) spell damage", "school" },
    { "improves your chance to hit with spells by (%d+)%%", "spellHit" },
    { "improves your chance to get a critical strike with spells by (%d+)%%", "spellCrit" },
    { "improves your chance to hit by (%d+)%%", "hit" },
    { "restores (%d+) mana per 5 sec", "mp5" },
    { "%+(%d+) mana every 5 sec", "mp5" },
    { "mana regen (%d+) per 5 sec", "mp5" },
    { "decreases the magical resistances of your spell targets by (%d+)", "spellPen" },
  },
  -- Item bonuses that only decide a row's colour (CS.GearColor): a value is
  -- green when an equipped item's own bonus line -- stat suffix, enchant,
  -- Equip: or active Set: line -- raises it, and white otherwise. An item's
  -- base armor or weapon damage is not a bonus. Every pattern is tried on
  -- every line; `skip` drops a conditional bonus, `not` a line that belongs
  -- to another row. A `damage` bonus counts for the hand it sits in.
  GEAR_BONUS = {
    { "%+(%d+) all stats", { "str", "agi", "sta", "int", "spi" } },
    { "%+(%d+) strength", "str" },
    { "%+(%d+) agility", "agi" },
    { "%+(%d+) stamina", "sta" },
    { "%+(%d+) intellect", "int" },
    { "%+(%d+) spirit", "spi" },
    { "%+(%d+) health%.?$", "health" },
    { "%+(%d+) mana%.?$", "mana" },
    { "%+(%d+) ranged attack power", "rangedAp" },
    { "%+(%d+) attack power", "ap", skip = { "when fighting", "forms only" } },
    { "%+(%d+) armor", "armor" },
    { "%+(%d+) defense", "defense" },
    { "increased defense %+(%d+)", "defense" },
    { "chance to dodge an attack by (%d+)%%", "dodge" },
    { "chance to parry an attack by (%d+)%%", "parry" },
    { "chance to block attacks with a shield by (%d+)%%", "block" },
    { "chance to get a critical strike by (%d+)%%", "crit" },
    { "^equip: increased [%a%- ]+ %+(%d+)", "skill", ["not"] = "defense" },
    { "%+(%d+) weapon damage", "damage" },
    { "^%+(%d+) damage%.?$", "damage" },
    { "%+(%d+) all resistances", { "res_arcane", "res_fire", "res_nature",
                                   "res_frost", "res_shadow" } },
    { "%+(%d+) arcane resistance", "res_arcane" },
    { "%+(%d+) fire resistance", "res_fire" },
    { "%+(%d+) nature resistance", "res_nature" },
    { "%+(%d+) frost resistance", "res_frost" },
    { "%+(%d+) shadow resistance", "res_shadow" },
  },
  -- Talent effects per rank, by the talent's English name (GetTalentInfo).
  -- `hit` melee, `rangedHit`, `spellHit` and `spellCrit` apply to every
  -- attack or spell; `spellHitNote` / `spellCritNote` only to some, so they
  -- are listed in the "?" breakdown and not added; `castRegen` is the share of
  -- Spirit regeneration kept while casting. `ranks` overrides `per`.
  TALENTS = {
    ROGUE = {
      { name = "Precision", hit = 1 },
    },
    HUNTER = {
      { name = "Surefooted", hit = 1, rangedHit = 1 },
    },
    SHAMAN = {
      { name = "Nature's Guidance", hit = 1, spellHit = 1 },
      { name = "Call of Thunder", spellCritNote = { 1, 2, 3, 4, 6 } },
      { name = "Tidal Mastery", spellCritNote = 1 },
    },
    MAGE = {
      { name = "Arcane Instability", spellCrit = 1 },
      { name = "Critical Mass", spellCritNote = 2 },
      { name = "Elemental Precision", spellHitNote = 2 },
      { name = "Arcane Focus", spellHitNote = 2 },
      { name = "Arcane Meditation", castRegen = 5 },
    },
    PRIEST = {
      { name = "Holy Specialization", spellCritNote = 1 },
      { name = "Force of Will", spellCritNote = 1 },
      { name = "Shadow Focus", spellHitNote = 2 },
      { name = "Meditation", castRegen = 5 },
    },
    WARLOCK = {
      { name = "Devastation", spellCritNote = 1 },
      { name = "Suppression", spellHitNote = 2 },
    },
    PALADIN = {
      { name = "Holy Power", spellCritNote = 1 },
    },
    DRUID = {
      { name = "Reflection", castRegen = 5 },
    },
  },
  -- 1.12 spell crit: a class base plus one percent per `int` Intellect at
  -- level 60. Below 60 the ratio is scaled with level, which is only an
  -- approximation -- hence an estimate.
  SPELL_CRIT = {
    MAGE = { base = 0.2, int = 59.5 },
    PRIEST = { base = 0.8, int = 59.2 },
    WARLOCK = { base = 1.7, int = 60.6 },
    DRUID = { base = 1.8, int = 60 },
    SHAMAN = { base = 2.3, int = 59.2 },
    PALADIN = { base = 0, int = 54 },
  },
  -- 1.12 Spirit regeneration per 2-second tick: `base` + Spirit / `div`.
  SPIRIT_REGEN = {
    PRIEST = { base = 12.5, div = 4 }, MAGE = { base = 12.5, div = 4 },
    WARLOCK = { base = 15, div = 5 }, DRUID = { base = 15, div = 5 },
    HUNTER = { base = 15, div = 5 }, PALADIN = { base = 15, div = 5 },
    SHAMAN = { base = 17, div = 5 },
  },
  scanner = nil,
  gearKey = nil,
  gear = nil,
  talentKey = nil,
  talents = nil,
  meleeSpell = nil,
  rangedSpell = nil,
}
U.CharacterStats = CS

-- ---------------------------------------------------------------------------
-- Guarded client reads
-- ---------------------------------------------------------------------------
function CS.Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, a, b)
end

function CS.Number(value)
  return tonumber(value) or 0
end

function CS.Scanner()
  if CS.scanner then return CS.scanner end
  CS.scanner = U.CreateScannerTooltip(CS.SCANNER)
  return CS.scanner
end

-- The shown left and right texts of the scanner after `setter` filled it, in
-- core/itemsort.lua's verified order: ClearLines, SetOwner, then the setter.
-- U.ScanWithTooltip arms the scanner and hides it on every exit path.
function CS.ScanLines(setter)
  return U.ScanWithTooltip(CS.Scanner(), CS.ReadLines, setter)
end

function CS.ReadLines(tip, setter)
  if not pcall(setter, tip) then return nil end
  local countOk, count = pcall(tip.NumLines, tip)
  count = countOk and tonumber(count) or 0
  if count > CS.MAX_LINES then count = CS.MAX_LINES end
  local left, right = {}, {}
  local i
  for i = 1, count do
    left[i] = U.TooltipLineText(CS.SCANNER, "Left", i)
    right[i] = U.TooltipLineText(CS.SCANNER, "Right", i)
  end
  return left, right, count
end

-- ---------------------------------------------------------------------------
-- Equipment
-- ---------------------------------------------------------------------------

-- The equipped item id, or nil. An empty slot answers GetInventoryItemLink
-- with a placeholder link to item 0 rather than nil
-- (inventory.empty_slot_link_returns_item_zero), so its icon decides.
function CS.ItemId(slot)
  local okTexture, texture = CS.Call("GetInventoryItemTexture", "player", slot)
  if not okTexture or not texture then return nil end
  local ok, link = CS.Call("GetInventoryItemLink", "player", slot)
  if not ok or type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  id = tonumber(id)
  if not id or id <= 0 then return nil end
  return id, link
end

-- GetItemInfo's eighth return is the INVTYPE_* equip location on this client
-- (statsrc run 2026-09-28).
function CS.EquipLoc(slot)
  local id = CS.ItemId(slot)
  if not id then return nil end
  local ok, _, _, _, _, _, _, _, equipLoc = CS.Call("GetItemInfo", id)
  if not ok or type(equipLoc) ~= "string" then return nil end
  return equipLoc
end

function CS.GearKey()
  local parts = {}
  local slot
  for slot = CS.GEAR_FIRST, CS.GEAR_LAST do
    local id, link = CS.ItemId(slot)
    table.insert(parts, link or "-")
  end
  return table.concat(parts, "|")
end

-- Records the line's GEAR_BONUS matches in totals.bonus.
function CS.AddGearBonus(totals, line, slot)
  local i, j
  for i = 1, table.getn(CS.GEAR_BONUS) do
    local entry = CS.GEAR_BONUS[i]
    local _, _, amount = string.find(line, entry[1])
    amount = amount and CS.Number(amount) or 0
    local skipped = entry["not"] and string.find(line, entry["not"], 1, true)
    if entry.skip then
      for j = 1, table.getn(entry.skip) do
        if string.find(line, entry.skip[j], 1, true) then skipped = true end
      end
    end
    if amount > 0 and not skipped then
      local keys = entry[2]
      if keys == "damage" then
        keys = (slot == CS.SLOT_RANGED) and "rangedDamage" or "meleeDamage"
      end
      if type(keys) ~= "table" then keys = { keys } end
      for j = 1, table.getn(keys) do
        totals.bonus[keys[j]] = (totals.bonus[keys[j]] or 0) + amount
      end
    end
  end
end

function CS.AddGearLine(totals, text, slot)
  local line = string.lower(text)
  -- On-use and proc effects are not standing bonuses, and "(3) Set:" is a
  -- set bonus the player has not completed.
  if string.find(line, "^use:") or string.find(line, "^chance on hit:")
     or string.find(line, "^%(%d+%)") then
    return
  end
  CS.AddGearBonus(totals, line, slot)
  local i
  for i = 1, table.getn(CS.GEAR_PATTERNS) do
    local entry = CS.GEAR_PATTERNS[i]
    local _, _, a, b = string.find(line, entry[1])
    if a then
      local kind = entry[2]
      if kind == "school" then
        -- The two school patterns capture in different orders.
        local school, amount = a, b
        if tonumber(a) then school, amount = b, a end
        if CS.SCHOOLS[school] then
          totals.school[school] = (totals.school[school] or 0) + CS.Number(amount)
        end
      elseif kind == "both" then
        totals.spellDamage = totals.spellDamage + CS.Number(a)
        totals.healing = totals.healing + CS.Number(a)
      else
        totals[kind] = totals[kind] + CS.Number(a)
      end
      return
    end
  end
end

-- Weapon base speed: the one shown right-hand text holding a decimal number
-- ("Speed 2.00", "Vitesse 2,00"). Every other right text on an item is a word.
function CS.WeaponSpeed(right, count)
  local i
  for i = 1, count do
    local text = right[i]
    if text then
      local _, _, whole, frac = string.find(text, "(%d+)[%.,](%d%d)%s*$")
      if whole then return tonumber(whole .. "." .. frac) end
    end
  end
  return nil
end

function CS.ScanGear()
  local key = CS.GearKey()
  if CS.gear and key == CS.gearKey then return CS.gear end
  local totals = { spellDamage = 0, healing = 0, spellHit = 0, spellCrit = 0,
                   hit = 0, mp5 = 0, spellPen = 0, school = {}, speed = {},
                   bonus = {} }
  local slot
  for slot = CS.GEAR_FIRST, CS.GEAR_LAST do
    if CS.ItemId(slot) then
      local left, right, count = CS.ScanLines(function(tip)
        tip:SetInventoryItem("player", slot)
      end)
      if left then
        local i
        for i = 1, count do
          if left[i] then CS.AddGearLine(totals, left[i], slot) end
        end
        totals.speed[slot] = CS.WeaponSpeed(right, count)
      end
    end
  end
  CS.gearKey, CS.gear = key, totals
  return totals
end

-- ---------------------------------------------------------------------------
-- Talents
-- ---------------------------------------------------------------------------
function CS.TalentKey()
  local parts = {}
  local okTabs, tabs = CS.Call("GetNumTalentTabs")
  tabs = okTabs and tonumber(tabs) or 0
  local tab
  for tab = 1, tabs do
    local ok, _, _, spent = CS.Call("GetTalentTabInfo", tab)
    table.insert(parts, ok and tostring(spent) or "?")
  end
  return table.concat(parts, "/")
end

-- name -> learned rank for every talent of the player's class.
function CS.ReadTalents()
  local key = CS.TalentKey()
  if CS.talents and key == CS.talentKey then return CS.talents end
  local ranks = {}
  local okTabs, tabs = CS.Call("GetNumTalentTabs")
  tabs = okTabs and tonumber(tabs) or 0
  local tab, index
  for tab = 1, tabs do
    local okCount, count = CS.Call("GetNumTalents", tab)
    count = okCount and tonumber(count) or 0
    for index = 1, count do
      local ok, name, _, _, _, rank = CS.Call("GetTalentInfo", tab, index)
      if ok and name then ranks[name] = tonumber(rank) or 0 end
    end
  end
  CS.talentKey, CS.talents = key, ranks
  return ranks
end

function CS.TalentValue(effect, rank)
  if type(effect) == "table" then return effect[rank] or 0 end
  return (tonumber(effect) or 0) * rank
end

-- Sums one effect over the class's learned talents. `notes` collects the
-- talent name and value of every contributing talent for the "?" breakdown.
function CS.TalentSum(class, field, notes)
  local list = CS.TALENTS[class]
  if not list then return 0 end
  local ranks = CS.ReadTalents()
  local total = 0
  local i
  for i = 1, table.getn(list) do
    local talent = list[i]
    local rank = ranks[talent.name] or 0
    if talent[field] and rank > 0 then
      local value = CS.TalentValue(talent[field], rank)
      total = total + value
      if notes then table.insert(notes, { talent.name, value }) end
    end
  end
  return total
end

-- ---------------------------------------------------------------------------
-- Spellbook crit
-- ---------------------------------------------------------------------------
function CS.SpellName(index)
  local ok, name = CS.Call("GetSpellName", index, U.G("BOOKTYPE_SPELL") or "spell")
  if ok then return name end
  return nil
end

-- The spellbook slot of the first spell named in `names`, remembered in
-- `cacheKey` and re-found whenever that slot's name no longer matches.
function CS.FindSpell(names, cacheKey)
  local cached = CS[cacheKey]
  if cached and names[CS.SpellName(cached) or ""] then return cached end
  CS[cacheKey] = nil
  local i
  for i = 1, CS.MAX_SPELLS do
    local name = CS.SpellName(i)
    if not name then return nil end
    if names[name] then
      CS[cacheKey] = i
      return i
    end
  end
  return nil
end

-- The first "<number>%" at the start of a tooltip line below the name.
function CS.SpellCrit(names, cacheKey)
  local slot = CS.FindSpell(names, cacheKey)
  if not slot then return nil end
  local bookType = U.G("BOOKTYPE_SPELL") or "spell"
  local left, _, count = CS.ScanLines(function(tip)
    tip:SetSpell(slot, bookType)
  end)
  if not left then return nil end
  local i
  for i = 2, count do
    local text = left[i]
    if text then
      local _, _, whole, frac = string.find(text, "^%s*(%d+)[%.,]?(%d*)%%")
      if whole then
        if frac ~= "" then return tonumber(whole .. "." .. frac) end
        return tonumber(whole)
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Row construction
--
-- A row is { label, value, color?, estimate?, tip? }. `estimate` is the list
-- of breakdown lines the "?" hover shows; `tip` is the row's own hover.
-- ---------------------------------------------------------------------------
CS.GREEN = { 0.13, 1.00, 0.13, 1 }

function CS.Percent(value)
  return string.format("%.2f%%", value or 0)
end

function CS.Signed(value)
  if value >= 0 then return "+" .. value end
  return tostring(value)
end

-- Green when equipped gear raises the value, white (nil) otherwise (user
-- request, 2026-09-28). The client's own positive/negative figures are not
-- used: they mix gear with buffs and debuffs, so the colour changed with
-- whatever was active. Each argument is a GEAR_BONUS key, or a number
-- already summed from gear (hit, spell damage, mp5 ...).
function CS.GearColor(gear, a, b)
  local function amount(key)
    if type(key) == "number" then return key end
    if key and gear and gear.bonus then return gear.bonus[key] or 0 end
    return 0
  end
  if amount(a) > 0 or amount(b) > 0 then return CS.GREEN end
  return nil
end

function CS.Row(rows, label, value, color, estimate, tip)
  table.insert(rows, { label = U.L(label), value = value, color = color,
                       estimate = estimate, tip = tip })
end

function CS.EstimateLine(key, value)
  return U.L(key, value)
end

-- ---------------------------------------------------------------------------
-- Native paper-doll hovers
--
-- The stock sheet explains attributes, armor, attack power, weapon skill,
-- defense and resistances on hover; the panel keeps that detail (user
-- request, 2026-09-28). Each tip is rebuilt the way 1.12 PaperDollFrame.lua
-- builds its tooltip / tooltipSubtext (WORKING_SOURCE: stock 1.12 FrameXML,
-- not read on this client), from the client's own localized strings: every
-- global below is present in this client's 2026-08-16 global dump
-- (ARMOR_TOOLTIP, RESISTANCE_TOOLTIP_SUBTEXT, MELEE/RANGED_ATTACK_POWER_
-- TOOLTIP, ATTACK_TOOLTIP(_SUBTEXT), <CLASS>_/DEFAULT_<STAT>_TOOLTIP, ...).
-- A missing global drops that line; the numbers are the 1.12 getters'
-- (character.stat_api_1_12_return_shapes).
-- ---------------------------------------------------------------------------
CS.STAT_TOOLTIP = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }

function CS.Global(name)
  local value = U.G(name)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

-- "Name 45 (40+5)", as PaperDollFormatStat prints it: white, the buff green
-- and the debuff red, the breakdown only when there is one.
function CS.Breakdown(name, shown, base, positive, negative)
  local text = "|cffffffff" .. name .. " " .. shown
  if positive > 0 or negative < 0 then
    text = text .. " (" .. base
    if positive > 0 then text = text .. "|cff20ff20+" .. positive .. "|cffffffff" end
    if negative < 0 then text = text .. "|cffff2020 " .. negative .. "|cffffffff" end
    text = text .. ")"
  end
  return text .. "|r"
end

-- A tip with the native heading and, if given, its explanation.
function CS.NativeTip(title, subtext)
  local tip = { title = title }
  if subtext then table.insert(tip, { subtext, note = true }) end
  return tip
end

function CS.Format(pattern, a, b, c)
  if not pattern then return nil end
  local ok, text = pcall(string.format, pattern, a, b, c)
  if ok then return text end
  return nil
end

function CS.ClassToken()
  local ok, _, class = CS.Call("UnitClass", "player")
  return ok and class and string.upper(class) or ""
end

function CS.PlayerLevel()
  local ok, level = CS.Call("UnitLevel", "player")
  return ok and CS.Number(level) or 1
end

-- Attack power: PaperDollFormatStat's heading, and the damage per second it
-- adds (effective / ATTACK_POWER_MAGIC_NUMBER, 14 in this client's dump).
function CS.PowerTip(nameKey, subtextKey, base, plus, minus)
  local effective = base + plus + minus
  local magic = tonumber(U.G("ATTACK_POWER_MAGIC_NUMBER")) or 14
  return CS.NativeTip(
    CS.Breakdown(CS.Global(nameKey) or U.L("CHARSTATS_AP"), effective, base, plus, minus),
    CS.Format(CS.Global(subtextKey), math.max(effective, 0) / magic))
end

-- Weapon skill and defense: the rating's name over base + modifier.
function CS.RatingTip(nameKey, subtextKey, base, mod)
  local name = CS.Global(nameKey)
  if not name then return nil end
  return CS.NativeTip(
    CS.Breakdown(name, base + mod, base, math.max(mod, 0), math.min(mod, 0)),
    subtextKey and CS.Global(subtextKey) or nil)
end

-- Armor: the damage reduction against an attacker of the player's level,
-- armor / (85 * level + 400) as a share of itself plus one.
function CS.ArmorTip(base, armor, plus, minus)
  local level = CS.PlayerLevel()
  local reduction = armor / (85 * level + 400)
  reduction = 100 * reduction / (reduction + 1)
  return CS.NativeTip(
    CS.Breakdown(CS.Global("ARMOR") or U.L("CHARSTATS_ARMOR"), armor, base, plus, minus),
    CS.Format(CS.Global("ARMOR_TOOLTIP"), level, reduction))
end

-- A resistance: its rating (Excellent .. None) from the total per level, the
-- level taken as at least 20.
function CS.ResistanceTip(entry, base, total, plus, minus)
  local level = math.max(CS.PlayerLevel(), 20)
  local ratio = total / level
  local rating = "RESISTANCE_NONE"
  if ratio > 5 then rating = "RESISTANCE_EXCELLENT"
  elseif ratio > 3.75 then rating = "RESISTANCE_VERYGOOD"
  elseif ratio > 2.5 then rating = "RESISTANCE_GOOD"
  elseif ratio > 1.25 then rating = "RESISTANCE_FAIR"
  elseif ratio > 0 then rating = "RESISTANCE_POOR" end
  local name = CS.Global("RESISTANCE" .. entry[1] .. "_NAME") or U.L(entry[2])
  local school = CS.Global("RESISTANCE_TYPE" .. entry[1])
  local subtext
  if school and CS.Global(rating) then
    subtext = CS.Format(CS.Global("RESISTANCE_TOOLTIP_SUBTEXT"), school, level,
                        CS.Global(rating))
  end
  return CS.NativeTip(CS.Breakdown(name, total, base, plus, minus), subtext)
end

function CS.General(rows, unit, gear)
  local ok, health = CS.Call("UnitHealthMax", unit)
  CS.Row(rows, "CHARSTATS_HEALTH", tostring(ok and CS.Number(health) or 0),
         CS.GearColor(gear, "health"))
  local okType, powerType = CS.Call("UnitPowerType", unit)
  local okPower, power = CS.Call("UnitManaMax", unit)
  local label = CS.POWER_LABEL[okType and tonumber(powerType) or 0] or "CHARSTATS_MANA"
  CS.Row(rows, label, tostring(okPower and CS.Number(power) or 0),
         label == "CHARSTATS_MANA" and CS.GearColor(gear, "mana") or nil)
end

function CS.Attributes(rows, gear)
  local class = CS.ClassToken()
  local i
  for i = 1, 5 do
    local ok, stat, effective, positive, negative = CS.Call("UnitStat", "player", i)
    if ok then
      stat, effective = CS.Number(stat), CS.Number(effective)
      positive, negative = CS.Number(positive), CS.Number(negative)
      -- PaperDollFrame_SetStat: the base shown is stat - posBuff - negBuff.
      local name = CS.Global("SPELL_STAT" .. (i - 1) .. "_NAME") or U.L(CS.ATTRIBUTES[i])
      local key = CS.STAT_TOOLTIP[i]
      local subtext = CS.Global(class .. "_" .. key .. "_TOOLTIP") or
                      CS.Global("DEFAULT_" .. key .. "_TOOLTIP")
      CS.Row(rows, CS.ATTRIBUTES[i], tostring(effective),
             CS.GearColor(gear, CS.ATTRIBUTE_BONUS[i]), nil,
             CS.NativeTip(CS.Breakdown(name, effective, stat - positive - negative,
                                       positive, negative), subtext))
    end
  end
end

function CS.DamageText(low, high)
  return string.format("%d - %d", math.max(math.floor(low), 1),
                       math.max(math.ceil(high), 1))
end

function CS.Haste(base, current)
  if not base or not current or current <= 0 then return nil end
  local haste = (base / current - 1) * 100
  if math.abs(haste) < 0.05 then haste = 0 end
  return haste
end

function CS.Melee(rows, gear, class)
  local ok, low, high, offLow, offHigh = CS.Call("UnitDamage", "player")
  local okSpeed, speed, offSpeed = CS.Call("UnitAttackSpeed", "player")
  speed = okSpeed and CS.Number(speed) or 0
  local offLoc = CS.EquipLoc(CS.SLOT_OFFHAND)
  -- UnitAttackSpeed reports an off-hand speed with nothing in that hand
  -- (character.stat_api_1_12_return_shapes), so the item decides.
  local dual = offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND"
  -- No hover on damage or DPS (user request, 2026-09-28): everything the
  -- native damage tooltip gave -- each hand's damage, speed and DPS -- is a
  -- row here, the off hand's damage on its own "Off Hand" row and its speed
  -- and DPS after the main hand's on theirs.
  if ok then
    low, high = CS.Number(low), CS.Number(high)
    offLow, offHigh, offSpeed = CS.Number(offLow), CS.Number(offHigh), CS.Number(offSpeed)
    local offHand = dual and offHigh > 0 and offSpeed > 0
    CS.Row(rows, "CHARSTATS_DAMAGE", CS.DamageText(low, high),
           CS.GearColor(gear, "meleeDamage"))
    if offHand then
      CS.Row(rows, "CHARSTATS_OFFHAND", CS.DamageText(offLow, offHigh),
             CS.GearColor(gear, "meleeDamage"))
    end
    if speed > 0 then
      local dps = string.format("%.1f", (low + high) / 2 / speed)
      if offHand then
        dps = dps .. " / " .. string.format("%.1f", (offLow + offHigh) / 2 / offSpeed)
      end
      CS.Row(rows, "CHARSTATS_DPS", dps, CS.GearColor(gear, "meleeDamage"))
    end
  end
  if speed > 0 then
    local text = string.format("%.2f", speed)
    if dual and CS.Number(offSpeed) > 0 then
      text = text .. " / " .. string.format("%.2f", CS.Number(offSpeed))
    end
    CS.Row(rows, "CHARSTATS_SPEED", text)
  end
  local okPower, base, plus, minus = CS.Call("UnitAttackPower", "player")
  if okPower then
    base, plus, minus = CS.Number(base), CS.Number(plus), CS.Number(minus)
    CS.Row(rows, "CHARSTATS_AP", tostring(base + plus + minus),
           CS.GearColor(gear, "ap"), nil,
           CS.PowerTip("ATTACK_POWER_TOOLTIP", "MELEE_ATTACK_POWER_TOOLTIP",
                       base, plus, minus))
  end
  local crit = CS.SpellCrit(CS.MELEE_SPELLS, "meleeSpell")
  if crit then
    CS.Row(rows, "CHARSTATS_CRIT", CS.Percent(crit), CS.GearColor(gear, "crit"))
  end

  local notes = {}
  local talentHit = CS.TalentSum(class, "hit", notes)
  local estimate = { CS.EstimateLine("CHARSTATS_EST_GEAR", CS.Percent(gear.hit)) }
  local i
  for i = 1, table.getn(notes) do
    table.insert(estimate, U.L("CHARSTATS_EST_TALENT", notes[i][1], CS.Percent(notes[i][2])))
  end
  -- Hidden at 0, as Forever's HITCHANCE and HASTE entries are (hideAt = 0).
  if gear.hit + talentHit > 0 then
    CS.Row(rows, "CHARSTATS_HIT", CS.Percent(gear.hit + talentHit),
           CS.GearColor(gear, gear.hit), estimate)
  end

  local haste = CS.Haste(gear.speed[16], speed)
  if haste and haste ~= 0 then CS.Row(rows, "CHARSTATS_HASTE", CS.Percent(haste)) end

  local okSkill, skill, mod = CS.Call("UnitAttackBothHands", "player")
  if okSkill then
    skill, mod = CS.Number(skill), CS.Number(mod)
    CS.Row(rows, "CHARSTATS_SKILL", tostring(skill + mod), CS.GearColor(gear, "skill"),
           nil, CS.RatingTip("ATTACK_TOOLTIP", "ATTACK_TOOLTIP_SUBTEXT", skill, mod))
  end
end

function CS.Ranged(rows, gear, class)
  if not CS.ItemId(CS.SLOT_RANGED) then return false end
  local ok, speed, low, high = CS.Call("UnitRangedDamage", "player")
  speed = ok and CS.Number(speed) or 0
  if speed <= 0 then return false end
  low, high = CS.Number(low), CS.Number(high)
  -- No hover on damage or DPS: the damage tooltip's three figures are the
  -- three rows (user request, 2026-09-28), DPS under the speed.
  CS.Row(rows, "CHARSTATS_DAMAGE", CS.DamageText(low, high),
         CS.GearColor(gear, "rangedDamage"))
  CS.Row(rows, "CHARSTATS_SPEED", string.format("%.2f", speed))
  CS.Row(rows, "CHARSTATS_DPS", string.format("%.1f", (low + high) / 2 / speed),
         CS.GearColor(gear, "rangedDamage"))
  local okPower, base, plus, minus = CS.Call("UnitRangedAttackPower", "player")
  if okPower then
    base, plus, minus = CS.Number(base), CS.Number(plus), CS.Number(minus)
    CS.Row(rows, "CHARSTATS_AP", tostring(base + plus + minus),
           CS.GearColor(gear, "ap", "rangedAp"), nil,
           CS.PowerTip("RANGED_ATTACK_POWER", "RANGED_ATTACK_POWER_TOOLTIP",
                       base, plus, minus))
  end
  local crit = CS.SpellCrit(CS.RANGED_SPELLS, "rangedSpell")
  if crit then
    CS.Row(rows, "CHARSTATS_CRIT", CS.Percent(crit), CS.GearColor(gear, "crit"))
  end

  local notes = {}
  local talentHit = CS.TalentSum(class, "rangedHit", notes)
  local estimate = { CS.EstimateLine("CHARSTATS_EST_GEAR", CS.Percent(gear.hit)) }
  local i
  for i = 1, table.getn(notes) do
    table.insert(estimate, U.L("CHARSTATS_EST_TALENT", notes[i][1], CS.Percent(notes[i][2])))
  end
  -- Hidden at 0, as Forever's HITCHANCE and HASTE entries are (hideAt = 0).
  if gear.hit + talentHit > 0 then
    CS.Row(rows, "CHARSTATS_HIT", CS.Percent(gear.hit + talentHit),
           CS.GearColor(gear, gear.hit), estimate)
  end

  local haste = CS.Haste(gear.speed[CS.SLOT_RANGED], speed)
  if haste and haste ~= 0 then CS.Row(rows, "CHARSTATS_HASTE", CS.Percent(haste)) end

  local okSkill, skill, mod = CS.Call("UnitRangedAttack", "player")
  if okSkill then
    skill, mod = CS.Number(skill), CS.Number(mod)
    CS.Row(rows, "CHARSTATS_SKILL", tostring(skill + mod), CS.GearColor(gear, "skill"),
           nil, CS.RatingTip("RANGED_ATTACK_TOOLTIP", "ATTACK_TOOLTIP_SUBTEXT", skill, mod))
  end
  return true
end

-- Talent lines that only concern some spells, for the "?" breakdown.
function CS.NoteLines(estimate, class, field)
  local notes = {}
  CS.TalentSum(class, field, notes)
  if table.getn(notes) == 0 then return end
  table.insert(estimate, U.L("CHARSTATS_EST_SOME_SPELLS"))
  local i
  for i = 1, table.getn(notes) do
    table.insert(estimate, U.L("CHARSTATS_EST_TALENT", notes[i][1], CS.Percent(notes[i][2])))
  end
end

function CS.Spell(rows, gear, class, level)
  local okType, powerType = CS.Call("UnitPowerType", "player")
  if not okType or tonumber(powerType) ~= 0 then return false end

  local schoolLines = {}
  local school
  for school in pairs(gear.school) do
    table.insert(schoolLines, U.L("CHARSTATS_EST_SCHOOL_" .. string.upper(school),
                                  gear.spellDamage + gear.school[school]))
  end
  table.sort(schoolLines)
  local damageEstimate = { CS.EstimateLine("CHARSTATS_EST_GEAR", tostring(gear.spellDamage)) }
  local i
  for i = 1, table.getn(schoolLines) do table.insert(damageEstimate, schoolLines[i]) end
  if gear.spellDamage > 0 or table.getn(schoolLines) > 0 then
    CS.Row(rows, "CHARSTATS_SPELL_DAMAGE", tostring(gear.spellDamage),
           CS.GearColor(gear, gear.spellDamage, table.getn(schoolLines)), damageEstimate)
  end
  if gear.healing > 0 then
    CS.Row(rows, "CHARSTATS_HEALING", tostring(gear.healing), CS.GearColor(gear, gear.healing),
           { CS.EstimateLine("CHARSTATS_EST_GEAR", tostring(gear.healing)) })
  end

  local notes = {}
  local talentHit = CS.TalentSum(class, "spellHit", notes)
  local hitEstimate = { CS.EstimateLine("CHARSTATS_EST_GEAR", CS.Percent(gear.spellHit)) }
  for i = 1, table.getn(notes) do
    table.insert(hitEstimate, U.L("CHARSTATS_EST_TALENT", notes[i][1], CS.Percent(notes[i][2])))
  end
  CS.NoteLines(hitEstimate, class, "spellHitNote")
  if gear.spellHit + talentHit > 0 or table.getn(hitEstimate) > 1 then
    CS.Row(rows, "CHARSTATS_SPELL_HIT", CS.Percent(gear.spellHit + talentHit),
           CS.GearColor(gear, gear.spellHit), hitEstimate)
  end

  local crit = CS.SPELL_CRIT[class]
  if crit then
    local okInt, _, intellect = CS.Call("UnitStat", "player", 4)
    intellect = okInt and CS.Number(intellect) or 0
    local ratio = crit.int * math.max(1, math.min(level, 60)) / 60
    local fromInt = crit.base + intellect / ratio
    notes = {}
    local talentCrit = CS.TalentSum(class, "spellCrit", notes)
    local critEstimate = {
      CS.EstimateLine("CHARSTATS_EST_BASE", CS.Percent(fromInt)),
      CS.EstimateLine("CHARSTATS_EST_GEAR", CS.Percent(gear.spellCrit)),
    }
    for i = 1, table.getn(notes) do
      table.insert(critEstimate, U.L("CHARSTATS_EST_TALENT", notes[i][1], CS.Percent(notes[i][2])))
    end
    CS.NoteLines(critEstimate, class, "spellCritNote")
    CS.Row(rows, "CHARSTATS_SPELL_CRIT",
           CS.Percent(fromInt + gear.spellCrit + talentCrit),
           CS.GearColor(gear, gear.spellCrit), critEstimate)
  end

  if gear.spellPen > 0 then
    CS.Row(rows, "CHARSTATS_SPELL_PEN", tostring(gear.spellPen), CS.GearColor(gear, gear.spellPen),
           { CS.EstimateLine("CHARSTATS_EST_GEAR", tostring(gear.spellPen)) })
  end

  local regen = CS.SPIRIT_REGEN[class]
  if regen then
    local okSpi, _, spirit = CS.Call("UnitStat", "player", 5)
    spirit = okSpi and CS.Number(spirit) or 0
    local fromSpirit = (regen.base + spirit / regen.div) * 2.5
    CS.Row(rows, "CHARSTATS_REGEN", tostring(math.floor(fromSpirit + gear.mp5 + 0.5)),
           CS.GearColor(gear, gear.mp5), {
      CS.EstimateLine("CHARSTATS_EST_SPIRIT", string.format("%.1f", fromSpirit)),
      CS.EstimateLine("CHARSTATS_EST_GEAR", tostring(gear.mp5)),
    })
    notes = {}
    local kept = CS.TalentSum(class, "castRegen", notes)
    if kept > 0 or gear.mp5 > 0 then
      local casting = { CS.EstimateLine("CHARSTATS_EST_GEAR", tostring(gear.mp5)) }
      for i = 1, table.getn(notes) do
        table.insert(casting, U.L("CHARSTATS_EST_TALENT", notes[i][1], notes[i][2] .. "%"))
      end
      CS.Row(rows, "CHARSTATS_REGEN_CASTING",
             tostring(math.floor(fromSpirit * kept / 100 + gear.mp5 + 0.5)),
             CS.GearColor(gear, gear.mp5), casting)
    end
  end
  return true
end

function CS.Defense(rows, gear)
  local ok, baseArmor, armor, _, plus, minus = CS.Call("UnitArmor", "player")
  if ok then
    armor = CS.Number(armor)
    CS.Row(rows, "CHARSTATS_ARMOR", tostring(armor),
           CS.GearColor(gear, "armor"), nil,
           CS.ArmorTip(CS.Number(baseArmor), armor, CS.Number(plus), CS.Number(minus)))
  end
  local okDef, base, mod = CS.Call("UnitDefense", "player")
  if okDef then
    base, mod = CS.Number(base), CS.Number(mod)
    CS.Row(rows, "CHARSTATS_DEFENSE", tostring(base + mod),
           CS.GearColor(gear, "defense"), nil,
           CS.RatingTip("DEFENSE_TOOLTIP", nil, base, mod))
  end
  local okDodge, dodge = CS.Call("GetDodgeChance")
  if okDodge then
    CS.Row(rows, "CHARSTATS_DODGE", CS.Percent(CS.Number(dodge)), CS.GearColor(gear, "dodge"))
  end
  local okParry, parry = CS.Call("GetParryChance")
  if okParry and CS.Number(parry) > 0 then
    CS.Row(rows, "CHARSTATS_PARRY", CS.Percent(CS.Number(parry)), CS.GearColor(gear, "parry"))
  end
  local okBlock, block = CS.Call("GetBlockChance")
  if okBlock and (CS.Number(block) > 0 or CS.EquipLoc(CS.SLOT_OFFHAND) == "INVTYPE_SHIELD") then
    CS.Row(rows, "CHARSTATS_BLOCK", CS.Percent(CS.Number(block)), CS.GearColor(gear, "block"))
  end
end

function CS.Resistances(rows, gear)
  local i
  for i = 1, table.getn(CS.RESISTANCES) do
    local entry = CS.RESISTANCES[i]
    local ok, base, total, plus, minus = CS.Call("UnitResistance", "player", entry[1])
    if ok then
      total = CS.Number(total)
      CS.Row(rows, entry[2], tostring(total), CS.GearColor(gear, entry[3]), nil,
             CS.ResistanceTip(entry, CS.Number(base), total, CS.Number(plus),
                              CS.Number(minus)))
    end
  end
end

-- The whole readout: a list of { title, rows }. Categories with no rows are
-- left out. Every section is guarded on its own, so one failing read costs
-- that section, not the panel.
function CS.Collect()
  local okClass, _, class = CS.Call("UnitClass", "player")
  class = okClass and class or ""
  local okLevel, level = CS.Call("UnitLevel", "player")
  level = okLevel and CS.Number(level) or 60

  local okGear, gear = pcall(CS.ScanGear)
  if not okGear or type(gear) ~= "table" then
    gear = { spellDamage = 0, healing = 0, spellHit = 0, spellCrit = 0, hit = 0,
             mp5 = 0, spellPen = 0, school = {}, speed = {}, bonus = {} }
  end

  local sections = {
    { "CHARSTATS_CAT_GENERAL", function(rows) CS.General(rows, "player", gear) end },
    { "CHARSTATS_CAT_ATTRIBUTES", function(rows) CS.Attributes(rows, gear) end },
    { "CHARSTATS_CAT_MELEE", function(rows) CS.Melee(rows, gear, class) end },
    { "CHARSTATS_CAT_RANGED", function(rows) CS.Ranged(rows, gear, class) end },
    { "CHARSTATS_CAT_SPELL", function(rows) CS.Spell(rows, gear, class, level) end },
    { "CHARSTATS_CAT_DEFENSE", function(rows) CS.Defense(rows, gear) end },
    { "CHARSTATS_CAT_RESIST", function(rows) CS.Resistances(rows, gear) end },
  }
  local out = {}
  local i
  for i = 1, table.getn(sections) do
    local rows = {}
    local ok, err = pcall(sections[i][2], rows)
    if not ok then U.Debug("characterstats " .. sections[i][1] .. ": " .. tostring(err)) end
    if table.getn(rows) > 0 then
      table.insert(out, { title = U.L(sections[i][1]), rows = rows })
    end
  end
  return out
end

-- Forgets the cached equipment and talent readings, so the next Collect
-- rescans them (the panel calls this whenever it opens).
function CS.Invalidate()
  CS.gearKey, CS.gear = nil, nil
  CS.talentKey, CS.talents = nil, nil
end
