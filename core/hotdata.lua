-- unrealUI :: core/hotdata.lua
--
-- The spells modules/hots.lua tracks on party frames -- the heal-over-time set
-- plus Power Word: Shield -- and the one lookup that turns a spell name into
-- an entry. Data only; the stamping,
-- the icons and the radial live in that module.
--
-- ---------------------------------------------------------------------------
-- Why a table exists at all
-- ---------------------------------------------------------------------------
--
-- knowledge.json / auras.unitbuff_unitdebuff_contract_unverified
-- (RUNTIME_MEASURED): UnitBuff(unit, index) returns exactly (texture, count)
-- on this runtime. No name, no spell id, no duration, no caster. Nothing in
-- that tuple says "this is a heal over time", and nothing says whose it is.
-- knowledge.json / auras.no_native_debuff_expiry_time adds that the
-- GameTooltip:SetUnitBuff scan is exactly two lines -- name and a static
-- description -- so the caster is not recoverable from the tooltip either.
--
-- So a HoT indicator cannot be read off the unit. It has to be reconstructed
-- from the player's own cast, which is what UnrealPfUI's libs/libpredict.lua
-- does on this same client (WORKING_SOURCE per .claude/rules/unreal-pfui.md,
-- not runtime verification). Only the spell set, the localized names and the
-- base durations are taken from it; its HealComm addon channel, its
-- CTRA/HealComm parsers, its heal prediction and its cast hooks are not.
--
-- ---------------------------------------------------------------------------
-- Names, not locales
-- ---------------------------------------------------------------------------
--
-- core/locale.lua's language is a *user preference* and deliberately not the
-- client locale, so it cannot be used to pick a spell name. GetLocale() would
-- work, but every name of every HoT is listed here instead and all of them are
-- matched. modules/hots.lua resolves an entry by walking the player's own
-- spellbook, so exactly one of these names can ever match on a given client
-- and the wrong-locale case simply never resolves. That also means a client
-- whose locale is not in this list still works if its spell names happen to be
-- English, rather than failing closed on a GetLocale() lookup miss.
--
-- Class filtering is free and needs no setting: a spell the player cannot cast
-- is not in their spellbook, so it never resolves and never draws.
--
-- ---------------------------------------------------------------------------
-- Durations
-- ---------------------------------------------------------------------------
--
--   * These are max-rank base durations. Rank is not recoverable for another
--     unit's aura (see core/auradata.lua's note on the same limit), so a
--     low-rank HoT reads long. It is the limit UnrealPfUI carries too.
--   * Vanilla's two duration set bonuses -- Stormrage 8-piece (+3s
--     Rejuvenation) and Transcendence 5-piece (+3s Renew) -- are NOT applied.
--     pfUI detects them by scanning equipped item tooltips for a localized
--     sentence, which is exactly the kind of locale-fragile parsing this addon
--     avoids. modules/hots.lua degrades instead: a HoT still on the unit when
--     its stamp runs out is re-stamped rather than dropped, so a set-bonus HoT
--     shows a restarting radial rather than vanishing three seconds early.

local U = UnrealUI

-- id        stable key, used by modules/hots.lua for its per-unit store
-- duration  seconds at max rank
-- icon      normalized icon key (see U.IconKey), used only when the spellbook
--           lookup cannot produce a texture
-- names     every localized name of the spell; all are matched
local HOTS = {
  {
    id = "rejuvenation",
    duration = 12,
    icon = "spell_nature_rejuvenation",
    names = {
      "Rejuvenation", "Verjungung", "Verj\195\188ngung", "Rejuvenecimiento",
      "R\195\169cup\195\169ration", "\237\154\140\235\179\181",
      "\208\158\208\188\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181",
      "\229\155\158\230\152\165\230\156\175",
    },
  },
  {
    id = "renew",
    duration = 15,
    icon = "spell_holy_renew",
    names = {
      "Renew", "Erneuerung", "Renovar", "R\195\169novation",
      "\236\134\140\236\131\157",
      "\208\158\208\177\208\189\208\190\208\178\208\187\208\181\208\189\208\184\208\181",
      "\230\129\162\229\164\141",
    },
  },
  {
    id = "regrowth",
    duration = 21,
    icon = "spell_nature_resistnature",
    names = {
      "Regrowth", "Nachwachsen", "Recrecimiento", "R\195\169tablissement",
      "\236\158\172\236\131\157",
      "\208\146\208\190\209\129\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\184\208\181",
      "\230\132\136\229\144\136",
    },
  },
  -- Not a heal over time: an absorb shield. Tracked with them by request, and it
  -- fits the same machinery exactly -- the player casts it, the client reports
  -- no caster for it, and it leaves the unit the moment it is spent. That last
  -- part is why no special case is needed: modules/hots.lua confirms every stamp
  -- against the unit's real buffs, so a shield eaten after four seconds clears
  -- its icon four seconds in rather than running the full 30. The radial shows
  -- time, not remaining absorb, which this client does not expose.
  --
  -- Weakened Soul is deliberately not tracked. It is a debuff, it is not what
  -- the player is looking for on a party frame, and UnitDebuff would not say it
  -- was ours either.
  --
  -- frFR puts a non-breaking space before the colon (U+00A0, "\194\160"),
  -- which is a different string from the ASCII-space form. Both are listed --
  -- a name that does not match exactly simply never resolves, and the wrong
  -- guess would silently cost French clients the icon.
  {
    id = "powerwordshield",
    duration = 30,
    icon = "spell_holy_powerwordshield",
    names = {
      "\80\111\119\101\114\32\87\111\114\100\58\32\83\104\105\101\108\100",
      "\77\97\99\104\116\119\111\114\116\58\32\83\99\104\105\108\100",
      "\80\97\108\97\98\114\97\32\100\101\32\112\111\100\101\114\58\32\101\115\99\117\100\111",
      "\77\111\116\32\100\101\32\112\111\117\118\111\105\114\194\160\58\32\66\111\117\99\108\105\101\114",
      "\77\111\116\32\100\101\32\112\111\117\118\111\105\114\32\58\32\66\111\117\99\108\105\101\114",
      "\236\139\160\236\157\152\32\234\182\140\235\138\165\58\32\235\179\180\237\152\184\235\167\137",
      -- Both cases of the final word: string.lower above folds ASCII only,
      -- so a Cyrillic capital and lowercase are two different keys.
      "\208\161\208\187\208\190\208\178\208\190\32\209\129\208\184\208\187\209\139\58\32\208\169\208\184\209\130",
      "\208\161\208\187\208\190\208\178\208\190\32\209\129\208\184\208\187\209\139\58\32\209\137\208\184\209\130",
      "\231\156\159\232\168\128\230\156\175\239\188\154\231\155\190",
    },
  },
}

-- Lowercased name -> entry, built once. string.lower is byte-oriented here and
-- leaves multi-byte UTF-8 alone, which is what makes a Cyrillic or CJK name
-- survive the fold intact (core/locale.lua's encoding note).
local byName = {}
local i, n
for i = 1, table.getn(HOTS) do
  local entry = HOTS[i]
  for n = 1, table.getn(entry.names) do
    byName[string.lower(entry.names[n])] = entry
  end
end

function U.HotSpells()
  return HOTS
end

-- The tracked HoT this spell name is, or nil for anything else the player
-- casts. Callers treat nil as "not a HoT", never as an error.
function U.HotByName(name)
  if type(name) ~= "string" or name == "" then return nil end
  return byName[string.lower(name)]
end
