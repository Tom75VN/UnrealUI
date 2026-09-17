-- unrealUI :: modules/castbar.lua
--
-- The player's cast bar: the spell icon flush against the left edge, and the
-- progress bar filling the rest of the width to the right edge, carrying the
-- spell name, remaining time, and any accumulated spell-pushback penalty drawn
-- directly on top of the fill.
--
-- knowledge.json / castbar.player_events_partial (RUNTIME_PLUS_WORKING_SOURCE):
-- SPELLCAST_START and SPELLCAST_STOP are the two cast events observed firing on
-- this client (events.json, 6 captures each). The captured SPELLCAST_START
-- argument shape is *not* Vanilla's own (spell, rank, castTime) tuple: it
-- arrived as arg1="Fireball" (string, spell name), arg2=1500 (number,
-- milliseconds) -- no rank argument at all. This module reads exactly that
-- shape and nothing more. It does not call UnitCastingInfo or UnitChannelInfo,
-- which are confirmed missing on this client. Target casts use the independent
-- combat-text reconstruction described below.
--
-- Channelled casts (fishing among them) are handled the same way, but on
-- WORKING_SOURCE evidence rather than a runtime capture: query_compat.py has
-- no record at all of SPELLCAST_CHANNEL_START firing on this client (an
-- evidence gap, not a contradiction), so per .claude/rules/unreal-pfui.md this
-- defaults to what UnrealPfUI's libs/libcast.lua demonstrably does with it
-- (libcast.lua:219) -- arg1=castTimeMs, arg2=name, the reverse order from
-- SPELLCAST_START. That reversal lines up with this client's already-confirmed
-- non-standard SPELLCAST_START shape, which is why it's taken as the default
-- rather than the vanilla (duration-only, no name) contract. Unconfirmed until
-- tested against an actual channelled cast (e.g. fishing) in game.
--
-- Two pieces of this bar rest on WORKING_SOURCE evidence, not on measured
-- runtime evidence, because query_compat.py returns no match at all for either
-- (api.json only covers the `core` and `actionbars` groups):
--
--   * The spell icon. SPELLCAST_START carries a name and a duration and no
--     texture, so the name is resolved to an icon by walking the spellbook with
--     GetNumSpellTabs / GetSpellTabInfo / GetSpellName / GetSpellTexture --
--     the same four calls UnrealPfUI's libs/libspell.lua uses on this same
--     client (GetSpellMaxRank / GetSpellIndex / GetSpellInfo). Every call goes
--     through Call() so a missing or differently-shaped API degrades to the
--     question-mark placeholder instead of erroring. See knowledge.json /
--     castbar.spell_icon_spellbook_lookup_unverified.
--   * Cast pushback. Getting hit mid-cast is reported by SPELLCAST_DELAYED in
--     Vanilla, and UnrealPfUI's libs/libcast.lua handles it as
--     `start = start + arg1/1000` -- i.e. the cast's start is pushed forward,
--     which rolls the fill backwards and grows the remaining time, exactly the
--     native behaviour. This module does the same. The event has *no* capture
--     in events.json, so whether this client emits it is unconfirmed; if it
--     never fires, the bar simply runs to its original duration as before. The
--     /uui check readout counts the delays actually received so this can be
--     settled from a real fight. See knowledge.json /
--     castbar.pushback_delay_event_unconfirmed.
--
-- Themes with native chrome (themes/classic-wow.lua) do not get the modern
-- widget: the player bar is built from the Classic static skin in
-- modules/castbarclassic.lua instead, so it stays in the client's own style
-- rather than mixing one modern bar into an otherwise native interface. It is
-- an unrealUI frame either way, driven by this module's per-frame tick --
-- the client's own CastingBarFrame advanced its fill in visible steps, and
-- that step was the reason the player bar moved to addon ownership here.
-- SuppressNativeCastbar then runs in that mode as well.
--
-- Only when that narrowly scoped Classic builder is unavailable does the client
-- keep drawing the player bar, and only then is the native mover below used at
-- all. In that fallback the native bar is placed the way modules/petbar.lua
-- places the native pet bar, for the same reasons and with the same two modes:
-- an unrealUI-owned anchor frame carries the handle, and until the player has
-- actually dropped that handle the anchor follows the native bar and nothing is
-- written to it at all, so an untouched interface keeps the client's own
-- castbar position. The client's anchor is captured before the mover is
-- registered and replayed from U.OnPositionReset, because it need not be
-- UIParent-relative and so cannot be expressed as a mover `default`.
--
-- Two things differ from the pet bar. The native castbar is hidden whenever
-- there is no cast, so the anchor frame is the thing that stays shown and
-- carries the handle -- a bar that only exists mid-cast could never be dragged
-- into place. And the anchor is given a floor height, because the stock bar is
-- too thin to be a comfortable grab target; placement is unaffected, since the
-- native bar is anchored CENTER-to-CENTER and neither frame needs to know how
-- large the other is.
--
-- Classic adds one reconstructed target bar using the separately verified
-- stock border/status/spark paths. It is entirely addon-owned and never reads
-- or retains CastingBarFrame regions; the unsafe discovery experiment remains
-- quarantined below for comparison with the focused runtime evidence.
--
-- The pet bar is the one reconstruction left out under native chrome. It owns
-- no mover and is parented to the pet unit frame, which in this mode is an
-- invisible anchor sitting under the client's own pet art at whatever size
-- that art happens to be, so a bar hung off its bottom edge has no reliable
-- relationship to what the player sees. It stays a modern-mode feature until
-- there is a measured anchor to hang it from.
--
-- Target casts use the client path verified by TargetedProbes 1.37.0. Native
-- UnitCastingInfo("target") and UnitChannelInfo("target") were both nil on all
-- 221 samples, so the bar never polls them. The same probe observed
-- CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE carrying the localized combat
-- text "Defias Cutpurse begins to perform Backstab.". This module parses the
-- client's SPELLCASTOTHERSTART / SPELLPERFORMOTHERSTART templates, matches the
-- caster to UnitName("target"), and times recognized spells from the compact
-- Vanilla spell table below. Unknown spells are deliberately omitted rather
-- than shown with an invented duration. Name matching has the usual Vanilla
-- ambiguity when several nearby creatures share one name; no unit GUID exists
-- in the captured event payload to distinguish them.
--
-- The pet castbar is the same reconstruction pointed at UnitName("pet"), drawn
-- under the pet unit frame at that frame's width. There is no pet cast API to
-- use instead: this client has no PetCastingBarFrame and no UnitCastingInfo,
-- and SPELLCAST_START is the player's own cast only. Two limits follow from
-- the source, and neither is a bug to chase:
--   * Only spells with a known cast time are drawn. Nearly every Vanilla pet
--     ability is instant, so in practice this is the Imp's Firebolt; channels
--     (Seduction, Consume Shadows) are left out rather than shown with a
--     duration that cannot be cut short when the channel breaks early.
--   * No captured evidence says which CHAT_MSG_SPELL event carries a friendly
--     pet's cast text on this client, so the bar listens to the same measured
--     family the target bar uses and no pet-only event is guessed at.
--     U.CastbarReport's pet.starts / pet.lastEvent are what settle it -- if a
--     pet cast never registers a start there, the routing event is outside
--     that family and the gap is then a probe, not a rewrite.

local U = UnrealUI
local M = U.media

local CB = U.RegisterModule("castbar")

-- Cell layout: the icon is flush against the bar cell (no gap between them),
-- and the bar cell takes the rest of WIDTH up to the right edge -- there is no
-- separate cell for the timer, which is drawn on top of the bar instead.
local HEIGHT = 24
local WIDTH = 230
-- The target frame is a 153px status bar plus its 1px outline on each side
-- (PRIMARY_WIDTH in modules/unitframes.lua). Keep the target castbar's complete
-- icon-and-progress footprint aligned to that outer width, rather than merely
-- matching the progress cell.
local TARGET_WIDTH = 153 + 2 * U.BorderSize()
local ICON_SIZE = HEIGHT
local BAR_WIDTH = WIDTH - ICON_SIZE
local PUSHBACK_WIDTH = 35

-- The pet castbar is a readout of the pet unit frame rather than a bar of its
-- own: it takes that frame's width at build time and a shorter row height that
-- sits with the frame's compact health/power bars instead of towering over
-- them.
local PET_HEIGHT = 16
-- Only reached if the pet frame cannot report its width: the bars-only pet
-- footprint from modules/unitframes.lua (120 plus its outline).
local PET_FALLBACK_WIDTH = 120 + 2 * U.BorderSize()
-- The pet book is walked until its first empty slot. The cap only bounds the
-- loop if this client ever keeps returning names past the end of the book.
local PET_BOOK_LIMIT = 30

-- Shown whenever the spellbook lookup cannot produce a real icon, so the left
-- cell is never an empty hole.
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Registered defensively: none of these has ever been observed firing
-- (events.json has no capture for any of them), so they cost nothing if this
-- client never sends one and end the cast cleanly if it does.
local STOP_EVENTS = {
  "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
  "SPELLCAST_CHANNEL_STOP",
}

-- Environmental cast text can be routed to different chat events according
-- to the caster and recipient. This is the same narrow event family used by
-- UnrealPfUI's working Vanilla libcast; the creature-vs-creature damage member
-- is additionally measured on this runtime (behavior.json / targetcast).
local TARGET_COMBAT_EVENTS = {
  "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PARTY_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
}

-- Combat text supplies no duration or icon. These base cast times and icon
-- names are the common combat subset of UnrealPfUI's enUS Vanilla spell data,
-- used here as WORKING_SOURCE evidence. Player casts teach additional names
-- for the current session from their measured SPELLCAST_START duration.
-- Keeping this table local avoids creating a second addon-wide data system for
-- information consumed only by the target castbar.
local TARGET_CASTS = {
  ["Aimed Shot"] = { ms = 3000, icon = "INV_Spear_07" },
  ["Ancestral Spirit"] = { ms = 10000, icon = "Spell_Nature_Regenerate" },
  ["Arcane Explosion"] = { ms = 1500, icon = "Spell_Nature_WispSplode" },
  ["Banish"] = { ms = 1500, icon = "Spell_Shadow_Cripple" },
  ["Blizzard"] = { ms = 2000, icon = "Spell_Frost_IceStorm" },
  ["Chain Heal"] = { ms = 2500, icon = "Spell_Nature_HealingWaveGreater" },
  ["Chain Lightning"] = { ms = 2500, icon = "Spell_Nature_ChainLightning" },
  ["Corruption"] = { ms = 2000, icon = "Spell_Shadow_AbominationExplosion" },
  ["Curse of the Deadwood"] = { ms = 2000, icon = "Spell_Shadow_GatherShadows" },
  ["Dark Mending"] = { ms = 3500, icon = "Spell_Shadow_ChillTouch" },
  ["Dominate Mind"] = { ms = 2000, icon = "Spell_Shadow_ShadowWordDominate" },
  ["Entangling Roots"] = { ms = 1500, icon = "Spell_Nature_StrangleVines" },
  ["Fear"] = { ms = 1500, icon = "Spell_Shadow_Possession" },
  ["Fireball"] = { ms = 3500, icon = "Spell_Fire_FlameBolt" },
  -- The Imp's Firebolt is the one Vanilla pet spell with a real cast time, so
  -- it is what the pet bar normally draws. The same entry also covers an enemy
  -- imp caught by the target bar.
  ["Firebolt"] = { ms = 2000, icon = "Spell_Fire_FireBolt02" },
  ["Flamestrike"] = { ms = 3000, icon = "Spell_Fire_SelfDestruct" },
  ["Flash Heal"] = { ms = 1500, icon = "Spell_Holy_FlashHeal" },
  ["Flash of Light"] = { ms = 1500, icon = "Spell_Holy_FlashHeal" },
  ["Frostbolt"] = { ms = 3000, icon = "Spell_Frost_FrostBolt02" },
  ["Greater Heal"] = { ms = 3000, icon = "Spell_Holy_GreaterHeal" },
  ["Heal"] = { ms = 3000, icon = "Spell_Holy_Heal02" },
  ["Healing Touch"] = { ms = 3500, icon = "Spell_Nature_HealingTouch" },
  ["Healing Wave"] = { ms = 3000, icon = "Spell_Nature_MagicImmunity" },
  ["Hex"] = { ms = 2000, icon = "Spell_Nature_Polymorph" },
  ["Hibernate"] = { ms = 1500, icon = "Spell_Nature_Sleep" },
  ["Holy Fire"] = { ms = 3500, icon = "Spell_Holy_SearingLight" },
  ["Holy Light"] = { ms = 2500, icon = "Spell_Holy_HolyBolt" },
  ["Holy Smite"] = { ms = 2500, icon = "Spell_Holy_HolySmite" },
  ["Immolate"] = { ms = 2000, icon = "Spell_Fire_Immolation" },
  ["Lesser Heal"] = { ms = 2500, icon = "Spell_Holy_LesserHeal" },
  ["Lesser Healing Wave"] = { ms = 1500, icon = "Spell_Nature_HealingWaveLesser" },
  ["Lightning Bolt"] = { ms = 3000, icon = "Spell_Nature_Lightning" },
  ["Mana Burn"] = { ms = 3000, icon = "Spell_Shadow_ManaBurn" },
  ["Mind Control"] = { ms = 3000, icon = "Spell_Shadow_ShadowWordDominate" },
  ["Polymorph"] = { ms = 1500, icon = "Spell_Nature_Polymorph" },
  ["Pyroblast"] = { ms = 6000, icon = "Spell_Fire_Fireball02" },
  ["Rain of Fire"] = { ms = 3000, icon = "Spell_Shadow_RainOfFire" },
  ["Rebirth"] = { ms = 2000, icon = "Spell_Nature_Reincarnation" },
  ["Redemption"] = { ms = 10000, icon = "Spell_Holy_Resurrection" },
  ["Regrowth"] = { ms = 2000, icon = "Spell_Nature_ResistNature" },
  ["Renew"] = { ms = 2000, icon = "Spell_Holy_Renew" },
  ["Resurrection"] = { ms = 10000, icon = "Spell_Holy_Resurrection" },
  ["Scorch"] = { ms = 1500, icon = "Spell_Fire_SoulBurn" },
  ["Searing Pain"] = { ms = 1500, icon = "Spell_Fire_SoulBurn" },
  ["Shadow Bolt"] = { ms = 3000, icon = "Spell_Shadow_ShadowBolt" },
  ["Silence"] = { ms = 1500, icon = "Spell_Holy_Silence" },
  ["Sleep"] = { ms = 1500, icon = "Spell_Nature_Sleep" },
  ["Smite"] = { ms = 2500, icon = "Spell_Holy_HolySmite" },
  ["Soul Fire"] = { ms = 6000, icon = "Spell_Fire_Fireball02" },
  ["Starfire"] = { ms = 3500, icon = "Spell_Arcane_StarFire" },
  ["Summon"] = { ms = 1000, icon = "Spell_Arcane_Blink" },
  ["Summon Felhunter"] = { ms = 10000, icon = "Spell_Shadow_SummonFelHunter" },
  ["Summon Imp"] = { ms = 10000, icon = "Spell_Shadow_SummonImp" },
  ["Summon Succubus"] = { ms = 10000, icon = "Spell_Shadow_SummonSuccubus" },
  ["Summon Voidwalker"] = { ms = 10000, icon = "Spell_Shadow_SummonVoidWalker" },
  ["Volley"] = { ms = 3000, icon = "Ability_TheBlackArrow" },
  ["War Stomp"] = { ms = 500, icon = "Ability_WarStomp" },
  ["Wrath"] = { ms = 2000, icon = "Spell_Nature_AbolishMagic" },
}

local bar
local casting = false
local startTime, duration
local lastTimeText
local tickInterval
local Tick
local UpdateTickRate

-- Combat-log casts are reconstructed identically for every non-player unit:
-- the caster name parsed out of the chat text has to equal that unit's current
-- name (knowledge.json / castbar.target_chatlog_fallback_unverified). One
-- tracker per unit therefore puts the target bar and the pet bar on the same
-- code path instead of keeping a second copy of it.
local trackers = {}       -- id -> tracker
local trackerOrder = {}   -- iteration order for the tick and the chat handler

local function NewTracker(id, unit, labelKey)
  local tracker = {
    id = id,
    unit = unit,
    labelKey = labelKey,
    bar = nil,
    casting = false,
    caster = nil,
    spell = nil,
    startTime = nil,
    duration = nil,
    lastTimeText = nil,
    starts = 0,
    unknown = 0,
    lastUnknown = nil,
    lastEvent = nil,
    iconSource = "none",
  }
  trackers[id] = tracker
  table.insert(trackerOrder, tracker)
  return tracker
end

local targetStartPatterns = {}

-- knowledge.json / castbar.native_frame_suppression_unverified: both
-- UnrealPfUI and PotatoUI suppress this client's stock player castbar through
-- the global CastingBarFrame. This is WORKING_SOURCE evidence rather than a
-- focused runtime result, so every operation is guarded and a missing or
-- differently shaped native frame leaves the UnrealUI castbar functional.
local nativeCastbarSuppressed = false

-- Set in OnEnable: true when the active theme draws stock client chrome, in
-- which case this module stands down entirely (see the header note).
local nativeChrome = false

local function SuppressNativeCastbar()
  local native = U.G("CastingBarFrame")
  if not native then return end

  if type(native.UnregisterAllEvents) == "function" then
    pcall(native.UnregisterAllEvents, native)
  end

  if type(native.SetScript) == "function" then
    pcall(native.SetScript, native, "OnShow", function()
      if type(native.Hide) == "function" then
        pcall(native.Hide, native)
      end
    end)
  end

  if type(native.Hide) == "function" then
    nativeCastbarSuppressed = pcall(native.Hide, native)
  end
end

-- Pushback bookkeeping, reported by /uui check: how many SPELLCAST_DELAYED
-- events this client actually delivered, and how much time they added.
local delayCount = 0
local delaySeconds = 0
local lastIconSource = "none"
-- The argument shape SPELLCAST_CHANNEL_START actually arrived with, reported
-- by /uui check: this client has no capture for that event at all.
local lastChannelShape = "none"
-- What the player's running cast is: "cast", "channel" or "craft". Only a
-- skin that installs uuiCastKind draws the difference (see ApplyCastKind).
local castKind = "cast"

-- Same shape as modules/actionbar.lua's helper: a global that is missing or
-- differently shaped here returns nil rather than erroring.
local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2 = pcall(fn, a, b)
  if not ok then return nil end
  return r1, r2
end

-- ---------------------------------------------------------------------------
-- The action the player just pressed
--
-- A cast can reach this module with no spell name in it. SPELLCAST_START's
-- shape is measured (name, ms), but SPELLCAST_CHANNEL_START has no capture at
-- all on this client (knowledge.json / castbar.player_events_partial), and a
-- channel that arrives as a duration with no name leaves the bar unnamed and
-- its icon cell hidden -- which is exactly what an Arcane Missiles channel
-- looked like. The same gap exists for a cast the spellbook cannot resolve at
-- all, such as an item or a trinket proc.
--
-- UnrealPfUI's libs/libcast.lua fills that gap with a `lastcasttex` remembered
-- from hooked CastSpell / UseContainerItem calls and used whenever its own
-- spell data has no icon (WORKING_SOURCE). The hook route it uses does not
-- exist here -- knowledge.json / hooks.no_global_hooksecurefunc -- but
-- UnrealUI's own action-press fan-out does, and it is already how
-- modules/hots.lua and modules/healpredict.lua identify an instant cast.
--
-- Only the slot and the time are kept. Resolving the slot costs a tooltip scan
-- (U.ActionSlotSpellName), so it is done on demand, in the one case that needs
-- it, rather than on every button press. The window keeps a press from being
-- credited to a cast that starts seconds later.
-- ---------------------------------------------------------------------------
local PRESS_WINDOW = 1.5
local pressedSlot, pressedAt = nil, 0

local function RememberPress(slot)
  pressedSlot = tonumber(slot)
  pressedAt = GetTime()
end

-- The spell name and the action art of that press, or nothing once the window
-- has passed. A macro slot deliberately answers no name (U.ActionSlotSpellName
-- refuses one) but still answers its art, which is the icon the client itself
-- draws on the button.
local function PressedCast()
  if not pressedSlot or (GetTime() - pressedAt) > PRESS_WINDOW then
    return nil, nil
  end

  local name = nil
  if type(U.ActionSlotSpellName) == "function" then
    name = U.ActionSlotSpellName(pressedSlot)
  end
  if type(name) ~= "string" or name == "" then name = nil end

  local art = Call("GetActionTexture", pressedSlot)
  if type(art) ~= "string" or art == "" then art = nil end

  return name, art
end

-- ---------------------------------------------------------------------------
-- Spell name -> icon and rank
--
-- SPELLCAST_START gives a name only, so the name is matched against the
-- spellbook once per spell and cached. `false` is cached for a miss too, so a
-- spell that is not in the book (an item or a trinket proc) is not re-scanned
-- on every cast.
--
-- The rank is read on the same walk for core/auradata.lua's benefit rather
-- than this module's: a duration table keyed by name alone reads a rank-1 Rend
-- as its 21-second max-rank value. Reading it here costs nothing -- the book
-- is already being walked and the answer is already being cached -- and keeps
-- a second scan of the same book out of the data layer.
-- ---------------------------------------------------------------------------
--
-- Cached per lowercased name: { texture = <path or false>, rank = <number or
-- false> }, or `false` for a name the spellbook does not have at all.
local iconCache = {}

-- Icon and highest known rank, or nil for a name that is not in the book.
--
-- The walk no longer stops at the first match. Every rank of a spell is its own
-- spellbook entry, and knowledge.json /
-- spellbook.spell_ranks_not_always_ascending_in_slot_order
-- (USER_CONFIRMED_INGAME) measured this client storing some of those runs
-- highest-rank-first -- so neither the first match nor the last one is the
-- highest, and the book has to be walked to the end with the rank numbers
-- compared. U.SpellRankNumber (core/compat.lua) is the locale-free read of
-- GetSpellName's rank subtext that modules/spellbook.lua uses for the same
-- reason. The icon is still taken from the first match, since all ranks of a
-- spell share one.
local function ScanSpellbook(lowerName)
  local bookType = U.G("BOOKTYPE_SPELL") or "spell"

  local tabs = tonumber(Call("GetNumSpellTabs"))
  if not tabs then return nil end

  local texture, rank, found = nil, nil, false

  local tab
  for tab = 1, tabs do
    -- GetSpellTabInfo returns name, texture, offset, numSpells in Vanilla;
    -- only the last two are used, and Call hands back the first two returns,
    -- so the tab info is read through a direct pcall instead.
    local fn = U.G("GetSpellTabInfo")
    if type(fn) ~= "function" then break end

    local ok, _, _, offset, count = pcall(fn, tab)
    offset, count = tonumber(offset), tonumber(count)

    if ok and offset and count then
      local id
      for id = offset + 1, offset + count do
        local spellName, spellRank = Call("GetSpellName", id, bookType)
        if type(spellName) == "string" and
           string.lower(spellName) == lowerName then
          found = true

          if not texture then
            local art = Call("GetSpellTexture", id, bookType)
            if type(art) == "string" and art ~= "" then texture = art end
          end

          local number = U.SpellRankNumber(spellRank)
          if number and (not rank or number > rank) then rank = number end
        end
      end
    end
  end

  if not found then return nil end
  return texture, rank
end

local function SpellEntry(name)
  if type(name) ~= "string" or name == "" then return nil end

  local key = string.lower(name)
  local cached = iconCache[key]
  if cached ~= nil then
    return cached or nil
  end

  local texture, rank = ScanSpellbook(key)
  if texture or rank then
    cached = { texture = texture or false, rank = rank or false }
  else
    -- Not in the book, or in it with neither art nor a numbered rank: nothing
    -- either caller can use, and cached as a miss so it is not re-scanned.
    cached = false
  end

  iconCache[key] = cached
  return cached or nil
end

local function SpellIcon(name)
  local entry = SpellEntry(name)
  if not entry then return nil end
  return entry.texture or nil
end

-- The same lookup, shared. modules/hots.lua needs a spell's icon for exactly
-- the reason this module does -- the client hands it a spell name and no art --
-- and duplicating the spellbook walk there would mean a second cache warming
-- itself on the same casts. Exported rather than moved: this module owns the
-- cache, its invalidation and the pet book beside it.
function U.SpellIconByName(name)
  return SpellIcon(name)
end

-- The highest rank of this spell the player knows, or nil when the spellbook
-- does not have it or does not number its ranks. core/auradata.lua uses it to
-- pick a rank-dependent duration; see the note above that table.
--
-- Player book only. The pet book below has its own cache and its own lifetime,
-- and the one rank-dependent pet spell in the duration table (Spell Lock) is
-- not worth walking it for -- an unresolved rank keeps the max-rank value,
-- which is what that spell already had.
function U.SpellRankByName(name)
  local entry = SpellEntry(name)
  if not entry then return nil end
  return entry.rank or nil
end

-- The pet book is a separate flat index -- documentation.json /
-- global:Spell:GetSpellName records that bookType "pet" selects it -- so it is
-- walked directly instead of through GetSpellTabInfo. Its contents change with
-- the pet, hence a separate cache, cleared on UNIT_PET.
local petIconCache = {}

local function PetSpellIcon(name)
  if type(name) ~= "string" or name == "" then return nil end

  local key = string.lower(name)
  local cached = petIconCache[key]
  if cached ~= nil then
    return cached or nil
  end

  local texture, id = nil, 1
  while id <= PET_BOOK_LIMIT do
    local spellName = Call("GetSpellName", id, "pet")
    if type(spellName) ~= "string" or spellName == "" then break end
    if string.lower(spellName) == key then
      local found = Call("GetSpellTexture", id, "pet")
      if type(found) == "string" and found ~= "" then texture = found end
      break
    end
    id = id + 1
  end

  petIconCache[key] = texture or false
  return texture
end

-- A spellbook miss (Hearthstone, a quest item, any other non-spell cast) used
-- to fall back to the question-mark placeholder texture; that read as a wrong
-- icon rather than an honest "no icon available", so a miss now hides the
-- whole icon cell instead (via widget.showIcon, see SetWidgetCellsShown) --
-- not just the texture, so its flat background/border don't hang around as an
-- empty box either. FALLBACK_ICON is still used for the idle placeholder
-- (ApplyIdlePlaceholder), which is a different case -- there's no cast at all
-- to have an icon for.
local function ApplyIcon(name)
  if not bar.icon then return end

  local texture = SpellIcon(name)
  lastIconSource = texture and "spellbook" or "none"

  -- Nothing in the book: an item, a trinket proc, or a cast whose event
  -- carried no name to look up. The action just pressed carries the art the
  -- client itself draws for it -- pfUI's `lastcasttex` fallback, through
  -- UnrealUI's own press notification.
  if not texture then
    local _, art = PressedCast()
    if art then
      texture = art
      lastIconSource = "action"
    end
  end

  if not texture then
    bar.showIcon = false
    return
  end

  if pcall(bar.icon.SetTexture, bar.icon, texture) then
    bar.showIcon = true
  else
    lastIconSource = "failed"
    bar.showIcon = false
  end
end

local function RememberTargetSpell(name, castTimeMs)
  if type(name) ~= "string" or name == "" or TARGET_CASTS[name] then return end

  local ms = tonumber(castTimeMs)
  if not ms or ms <= 0 then return end

  TARGET_CASTS[name] = {
    ms = ms,
    texture = SpellIcon(name),
  }
end

-- `preferred` is a texture the caller already resolved for this exact unit --
-- the pet tracker reads the real icon out of the pet spellbook -- and wins over
-- the shared static table, which only knows one icon per spell name.
local function ApplyUnitIcon(tracker, info, preferred)
  local widget = tracker.bar
  if not widget or not widget.icon then return end

  local texture, source = preferred, "spellbook"
  if not texture and info and info.texture then
    texture, source = info.texture, "learned"
  end
  if not texture and info and type(info.icon) == "string" and
     info.icon ~= "" and info.icon ~= "Temp" then
    texture, source = "Interface\\Icons\\" .. info.icon, "static"
  end

  tracker.iconSource = texture and source or "none"
  if not texture then
    widget.showIcon = false
    return
  end

  if pcall(widget.icon.SetTexture, widget.icon, texture) then
    widget.showIcon = true
  else
    tracker.iconSource = "failed"
    widget.showIcon = false
  end
end

-- Convert the client's localized printf templates (for example
-- "%s begins to cast %s.") into Lua capture patterns. Numbered placeholders
-- are retained as a swap flag so locales that write spell before caster still
-- return caster, spell to the caller. Only the two-string start templates are
-- accepted; a different runtime shape safely produces no target casts.
local function CompileTargetPattern(template)
  if type(template) ~= "string" or template == "" then return nil end

  local _, firstEnd, firstNumber = string.find(template, "%%(%d+)%$s")
  local secondNumber
  if firstEnd then
    local _, _, found = string.find(template, "%%(%d+)%$s", firstEnd + 1)
    secondNumber = found
  end

  local pattern = string.gsub(template,
                              "([%.%+%-%*%(%)%?%[%]%^])", "%%%1")
  pattern = string.gsub(pattern, "%%%d+%$s", "(.+)")
  pattern = string.gsub(pattern, "%%s", "(.+)")

  local captures = 0
  string.gsub(pattern, "%(%.[%+%-%*]%)", function()
    captures = captures + 1
  end)
  if captures ~= 2 then return nil end

  return {
    pattern = "^" .. pattern .. "$",
    swap = tonumber(firstNumber) == 2 and tonumber(secondNumber) == 1,
  }
end

local function BuildTargetPatterns()
  targetStartPatterns = {}

  local globals = { "SPELLCASTOTHERSTART", "SPELLPERFORMOTHERSTART" }
  local i
  for i = 1, table.getn(globals) do
    local compiled = CompileTargetPattern(U.G(globals[i]))
    if compiled then table.insert(targetStartPatterns, compiled) end
  end
end

local function CaptureTargetStart(message)
  if type(message) ~= "string" then return nil end

  local i
  for i = 1, table.getn(targetStartPatterns) do
    local entry = targetStartPatterns[i]
    local _, _, first, second = string.find(message, entry.pattern)
    if first and second then
      if entry.swap then return second, first end
      return first, second
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- Bar state
-- ---------------------------------------------------------------------------

local function ApplyTimer(remaining)
  if not bar.time then return end
  local text = string.format("%.1f", remaining)
  if text == lastTimeText then return end
  lastTimeText = text
  bar.time:SetText(text)
end

-- The normal layout gives the spell name all space up to the countdown. Once
-- pushback occurs, reserve a compact slot at the right for its cumulative
-- penalty and move the countdown left. Hiding the slot again restores the
-- original layout, so unaffected casts lose no name space.
local function ApplyPushback(seconds)
  if not bar.pushback then return end

  local shown = tonumber(seconds) and tonumber(seconds) > 0
  local text = shown and string.format("+ %.1f", seconds) or ""
  if bar.pushbackShown == shown and bar.pushbackText == text then return end

  bar.pushbackShown = shown
  bar.pushbackText = text
  bar.pushback:SetText(text)

  if shown then
    bar.pushback:Show()
  else
    bar.pushback:Hide()
  end

  if bar.time then
    bar.time:ClearAllPoints()
    if shown then
      bar.time:SetPoint("RIGHT", bar.pushback, "LEFT", -1, 0)
    else
      bar.time:SetPoint("RIGHT", bar.bar, "RIGHT", -3, bar.uuiTimeY or 0)
    end
  end

  if bar.name then
    pcall(bar.name.SetWidth, bar.name,
          BAR_WIDTH - 34 - (shown and PUSHBACK_WIDTH or 0))
  end
end

-- Every fill write on a unit bar goes through here: the Classic static widget
-- carries a stock spark which has to travel with the fill edge. The Modern
-- widget has no spark and leaves the hook nil.
local function SetUnitBarValue(widget, value)
  if not widget or not widget.bar then return end
  pcall(widget.bar.SetValue, widget.bar, value)
  if widget.uuiUpdateSpark then widget.uuiUpdateSpark(widget) end
end

-- The Modern widget is tinted with the addon's cast colour. The Classic widget
-- uses the gold tint proven by the isolated addon-owned preview and keeps it;
-- there is no GetVertexColor on this client from which to copy a live tint.
local function ApplyUnitBarTint(widget)
  if not widget or not widget.bar or widget.uuiKeepNativeTint then return end
  U.SetStatusBarColor(widget.bar, M.Unpack(M.color.cast))
end

-- Optional skin hook: uuiCastKind(widget, kind) with "cast", "channel" or
-- "craft", before the first fill write of a cast. modules/modernwow.lua uses
-- it to swap the fill art; `modern` and `classic-wow` install nothing.
local function ApplyCastKind(widget, kind)
  if not widget or type(widget.uuiCastKind) ~= "function" then return end
  pcall(widget.uuiCastKind, widget, kind)
end

local function ApplyUnitTimer(tracker, remaining)
  local widget = tracker.bar
  if not widget or not widget.time then return end
  local text = string.format("%.1f", remaining)
  if text == tracker.lastTimeText then return end
  tracker.lastTimeText = text
  widget.time:SetText(text)
end

-- knowledge.json / rendering.parent_alpha_not_propagated: the cells are shown
-- and hidden explicitly rather than left to the container, on the same
-- reasoning the rest of unrealUI uses for composite frames.
--
-- The icon cell is additionally gated by widget.showIcon: when a cast has no
-- resolved icon (see ApplyIcon), the whole cell -- its flat background and
-- border, not just the texture -- is hidden instead of leaving an empty box
-- with nothing in it.
local function SetWidgetCellsShown(widget, shown)
  local i
  for i = 1, table.getn(widget.uuiCells) do
    local cell = widget.uuiCells[i]
    local cellShown = shown
    if cell == widget.iconCell and not widget.showIcon then
      cellShown = false
    end
    if cellShown then
      if not cell:IsShown() then cell:Show() end
    else
      if cell:IsShown() then cell:Hide() end
    end
  end
  if widget.uuiSetDynamicShown then
    widget.uuiSetDynamicShown(widget, shown)
  end
end

local function SetCellsShown(shown)
  SetWidgetCellsShown(bar, shown)
end

-- ---------------------------------------------------------------------------
-- Themed finish animation
--
-- What the end of a cast looks like belongs to the skin, not to this module.
-- A widget may install three optional hooks:
--
--   uuiFinish(widget, kind)  -- "stop", "failed" or "interrupted"; returns how
--                               many seconds the bar wants to stay on screen
--   uuiFinishTick(widget)    -- once per tick while that time runs
--   uuiFinishEnd(widget)     -- when it expires, to put the widget back
--
-- A widget that installs none of them behaves exactly as before: the bar is
-- hidden the moment the cast ends, which is what `modern` and `classic-wow`
-- do. modules/modernwow.lua installs all three, to reproduce
-- DragonflightUI's fill-to-full, flash and fade under `modern-wow`.
--
-- The kind is the finishing event, which is why StopCast now takes it: only
-- SPELLCAST_INTERRUPTED has a runtime capture on this client
-- (knowledge.json / combat.ranged_autorepeat_interrupted_stop_is_not_a_player_stop),
-- so an unrecognised or absent event still finishes the bar as a plain stop
-- rather than leaving it up.
-- ---------------------------------------------------------------------------
local FINISH_KIND = {
  SPELLCAST_STOP = "stop",
  SPELLCAST_CHANNEL_STOP = "stop",
  SPELLCAST_FAILED = "failed",
  SPELLCAST_INTERRUPTED = "interrupted",
}

local function Finishing(widget)
  if not widget or not widget.uuiFinishUntil then return false end
  return GetTime() < widget.uuiFinishUntil
end

local function CancelFinish(widget)
  if not widget or not widget.uuiFinishUntil then return end
  widget.uuiFinishUntil = nil
  if type(widget.uuiFinishEnd) == "function" then
    pcall(widget.uuiFinishEnd, widget)
  end
  -- The tick runs per frame while anything is finishing; put it back on the
  -- idle cadence as soon as the last animation is over.
  if UpdateTickRate then UpdateTickRate() end
end

local function BeginFinish(widget, kind)
  if not widget or not kind then return end
  if type(widget.uuiFinish) ~= "function" then return end
  local ok, hold = pcall(widget.uuiFinish, widget, kind)
  hold = (ok and tonumber(hold)) or 0
  if hold <= 0 then return end
  widget.uuiFinishUntil = GetTime() + hold
end

-- True while the widget is still animating, so the caller leaves it alone.
-- The expiry is handled here, once, on the tick that reaches it.
local function FinishTick(widget)
  if not widget or not widget.uuiFinishUntil then return false end
  if GetTime() < widget.uuiFinishUntil then
    if type(widget.uuiFinishTick) == "function" then
      pcall(widget.uuiFinishTick, widget)
    end
    return true
  end
  CancelFinish(widget)
  return false
end

local function UpdateUnitVisibility(tracker)
  local widget = tracker.bar
  if not widget then return end
  local shown = tracker.casting or U.IsUnlocked() or Finishing(widget)
  if shown then
    if not widget:IsShown() then widget:Show() end
  else
    if widget:IsShown() then widget:Hide() end
  end
  SetWidgetCellsShown(widget, shown)
end

local function ApplyUnitIdlePlaceholder(tracker)
  local widget = tracker.bar
  if not widget then return end

  ApplyCastKind(widget, "cast")
  ApplyUnitBarTint(widget)
  pcall(widget.bar.SetMinMaxValues, widget.bar, 0, 1)
  SetUnitBarValue(widget, 0.4)
  if widget.name then
    widget.name:SetText(U.L(tracker.labelKey))
  end
  if widget.icon then
    pcall(widget.icon.SetTexture, widget.icon, FALLBACK_ICON)
  end
  widget.showIcon = true
  SetWidgetCellsShown(widget, true)
  tracker.lastTimeText = nil
  if widget.time then widget.time:SetText("0.0") end
end

local function AnyCastActive()
  if casting or Finishing(bar) then return true end
  local i
  for i = 1, table.getn(trackerOrder) do
    local tracker = trackerOrder[i]
    if tracker.casting or Finishing(tracker.bar) then return true end
  end
  return false
end

UpdateTickRate = function()
  if not Tick then return end
  -- Not `if not bar`: under a native-chrome theme the player bar does not
  -- exist and the target tracker is the only thing on the tick.
  if not bar and table.getn(trackerOrder) == 0 then return end
  -- Active fills keep the exact render-frame cadence they had before. While
  -- every bar is idle, a 0.1s visibility pass is enough to expose edit-mode
  -- placeholders without paying three IsShown/visibility walks every frame.
  local interval = AnyCastActive() and 0 or 0.1
  if tickInterval == interval then return end
  tickInterval = interval
  U.RegisterUpdate("castbar.tick", interval, Tick)
end

-- `kind` is nil for a stop that is not the end of a cast -- the unit changed,
-- or a new cast superseded this one -- and no finish animation is run for it.
local function StopUnitCast(tracker, kind)
  if not tracker or not tracker.casting then return end
  tracker.casting = false
  tracker.caster = nil
  tracker.spell = nil
  tracker.startTime = nil
  tracker.duration = nil
  BeginFinish(tracker.bar, kind)
  UpdateUnitVisibility(tracker)
  UpdateTickRate()
end

local function StartUnitCast(tracker, eventName, caster, spell)
  if not tracker.bar or type(caster) ~= "string" or
     type(spell) ~= "string" then return end

  -- The unit name is the whole identity check this event contract can offer:
  -- the chat text names a caster and nothing else.
  local unitName = Call("UnitName", tracker.unit)
  if type(unitName) ~= "string" or unitName == "" or
     caster ~= unitName then return end

  -- A new start supersedes any earlier timer from the same named unit, even
  -- when the new spell is unknown and therefore cannot be drawn accurately.
  if tracker.casting then StopUnitCast(tracker) end
  CancelFinish(tracker.bar)
  tracker.lastEvent = eventName

  -- The pet book is the accurate icon source for a pet cast; the shared table
  -- below only ever holds one icon per spell name.
  local preferred
  if tracker.unit == "pet" then preferred = PetSpellIcon(spell) end

  local info = TARGET_CASTS[spell]
  if not info or not tonumber(info.ms) or tonumber(info.ms) <= 0 then
    tracker.unknown = tracker.unknown + 1
    tracker.lastUnknown = spell
    return
  end

  tracker.casting = true
  tracker.caster = caster
  tracker.spell = spell
  tracker.startTime = GetTime()
  tracker.duration = tonumber(info.ms) / 1000
  tracker.lastTimeText = nil
  tracker.starts = tracker.starts + 1

  -- Reconstructed from combat text, which names a spell and nothing about
  -- whether it channels, so a unit cast is always drawn as a plain cast.
  ApplyCastKind(tracker.bar, "cast")
  ApplyUnitBarTint(tracker.bar)
  pcall(tracker.bar.bar.SetMinMaxValues, tracker.bar.bar, 0,
        tracker.duration)
  SetUnitBarValue(tracker.bar, 0)
  if tracker.bar.name then tracker.bar.name:SetText(spell) end
  ApplyUnitIcon(tracker, info, preferred)
  ApplyUnitTimer(tracker, tracker.duration)
  UpdateUnitVisibility(tracker)
  UpdateTickRate()
end

-- One parse, then every tracker gets a look at it: the same message is the
-- target cast while the target is casting and the pet cast while the pet is,
-- and a player targeting their own pet legitimately matches both.
local function OnUnitCombatMessage(eventName, message)
  local caster, spell = CaptureTargetStart(message)
  if not caster or not spell then return end

  local i
  for i = 1, table.getn(trackerOrder) do
    StartUnitCast(trackerOrder[i], eventName, caster, spell)
  end
end

-- Kept shown and given a placeholder fill while the UI is unlocked, on the
-- same reasoning as the unit frames' empty-unit shell: a frame that only
-- exists while it has something to show could never be dragged into place.
local function ApplyIdlePlaceholder()
  castKind = "cast"
  ApplyCastKind(bar, "cast")
  ApplyUnitBarTint(bar)
  pcall(bar.bar.SetMinMaxValues, bar.bar, 0, 1)
  if type(U.ResetStatusBarFX) == "function" then
    U.ResetStatusBarFX(bar.bar, 0.4)
  end
  SetUnitBarValue(bar, 0.4)
  if bar.name then bar.name:SetText(U.L("MOVER_LABEL_CASTBAR")) end
  if bar.icon then pcall(bar.icon.SetTexture, bar.icon, FALLBACK_ICON) end
  bar.showIcon = true
  -- Applied immediately rather than waiting for the next Tick's
  -- UpdateVisibility: a cast that just ended with no icon left the cell
  -- hidden, and it would otherwise stay hidden for one extra frame.
  SetCellsShown(true)
  lastTimeText = nil
  if bar.time then bar.time:SetText("0.0") end
  ApplyPushback(0)
end

-- Craft dock. While a profession window is open, a craft cast moves the player
-- bar to the left of that window's Create All button (user request,
-- 2026-09-16); it returns to its mover position when the window closes, a
-- non-craft cast starts, or edit mode opens. The anchor is the addon-owned
-- button modules/professions.lua hands out, never a native child
-- (rules/unreal-ui.md, native widget ownership). No stored position is
-- touched: undocking re-applies the mover's own saved or default point.
local craftDock = { docked = false, anchor = nil }

function craftDock.Anchor()
  if type(U.ProfessionsCastBarAnchor) ~= "function" then return nil end
  local ok, anchor, gap, shiftX, shiftY = pcall(U.ProfessionsCastBarAnchor)
  if not ok or not anchor then return nil end
  return anchor, tonumber(gap) or 0, tonumber(shiftX) or 0, tonumber(shiftY) or 0
end

function craftDock.Undock()
  if not craftDock.docked then return end
  craftDock.docked = false
  craftDock.anchor = nil
  if bar then U.ReapplyMoverPosition(bar) end
end

function craftDock.Dock()
  if not bar or U.IsUnlocked() then return false end
  local anchor, gap, shiftX, shiftY = craftDock.Anchor()
  if not anchor then return false end
  if craftDock.docked and craftDock.anchor == anchor then return true end

  -- SetPoint offsets are in the bar's own units; the modern-wow bar is scaled,
  -- so the nudge is divided back out to move the requested UI units.
  local scaleOk, scale = pcall(bar.GetScale, bar)
  scale = scaleOk and tonumber(scale) or 1
  if scale <= 0 then scale = 1 end

  local ok = pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", anchor, "LEFT",
                 -gap + shiftX / scale, shiftY / scale)
  end)
  craftDock.docked = true
  craftDock.anchor = anchor
  if not ok then
    craftDock.Undock()
    return false
  end
  return true
end

-- Per tick: the window closed or edit mode opened since the bar docked.
function craftDock.Check()
  if not craftDock.docked then return end
  if U.IsUnlocked() or craftDock.Anchor() ~= craftDock.anchor then
    craftDock.Undock()
  end
end

local function UpdateVisibility()
  -- No player bar under a native-chrome theme; the client draws that one.
  if not bar then return end
  craftDock.Check()
  local shown = casting or U.IsUnlocked() or Finishing(bar)
  if shown then
    if not bar:IsShown() then bar:Show() end
  else
    if bar:IsShown() then bar:Hide() end
  end
  SetCellsShown(shown)
end

-- Trade-skill casts. SPELLCAST_START names the recipe and nothing marks it as
-- a craft, so the name is matched against the trade-skill and craft lists.
-- GetNumTradeSkills / GetTradeSkillInfo / GetNumCrafts / GetCraftInfo are only
-- DOCUMENTED_NOT_RUNTIME_VERIFIED in query_compat.py; Call() turns a missing or
-- failing one into nil, so an unconfirmed API only ever degrades a craft to
-- the plain cast art. A closed window lists nothing and matches nothing.
local CRAFT_LISTS = {
  { count = "GetNumTradeSkills", info = "GetTradeSkillInfo" },
  { count = "GetNumCrafts", info = "GetCraftInfo" },
}

local function IsCraftCast(name)
  if type(name) ~= "string" or name == "" then return false end
  local i, j
  for i = 1, table.getn(CRAFT_LISTS) do
    local list = CRAFT_LISTS[i]
    local count = tonumber(Call(list.count)) or 0
    for j = 1, count do
      local recipe, rowType = Call(list.info, j)
      if recipe == name and rowType ~= "header" then return true end
    end
  end
  return false
end

-- Every player fill write. A skin that sets uuiDrainChannel draws a channel
-- running down from full, as the Dragonflight channel bar does; everything
-- else fills forward exactly as before. The drain is written as a reset, not
-- a SetValue: core/statusbarfx.lua reads every falling value as damage and
-- would spawn a cutout on each tick of a channel.
local function ApplyPlayerProgress(elapsed)
  if castKind ~= "channel" or not bar.uuiDrainChannel then
    SetUnitBarValue(bar, elapsed)
    return
  end
  local remaining = duration - elapsed
  if remaining < 0 then remaining = 0 end
  if type(U.ResetStatusBarFX) ~= "function" or
     not U.ResetStatusBarFX(bar.bar, remaining) then
    pcall(bar.bar.SetValue, bar.bar, remaining)
  end
  if bar.uuiUpdateSpark then bar.uuiUpdateSpark(bar) end
end

-- `kind` is "channel" from SPELLCAST_CHANNEL_START and nil otherwise; a nil
-- kind is a craft when the name is a known recipe, else a plain cast.
local function StartCast(name, castTimeMs, kind)
  CancelFinish(bar)

  -- A channel can arrive with a duration and no name (see the press note
  -- above). The action the player just used is the only other thing that
  -- knows which spell this is.
  if type(name) ~= "string" or name == "" then
    name = PressedCast()
  end

  casting = true
  startTime = GetTime()
  duration = (tonumber(castTimeMs) or 0) / 1000
  -- A zero or missing duration would divide-by-zero the fill computation in
  -- core/style.lua; treat it as an effectively-instant cast instead.
  if duration <= 0 then duration = 0.01 end

  delayCount, delaySeconds = 0, 0
  ApplyPushback(0)

  castKind = kind or (IsCraftCast(name) and "craft") or "cast"
  if not (castKind == "craft" and craftDock.Dock()) then craftDock.Undock() end
  ApplyCastKind(bar, castKind)
  ApplyUnitBarTint(bar)
  pcall(bar.bar.SetMinMaxValues, bar.bar, 0, duration)
  if type(U.ResetStatusBarFX) == "function" then
    U.ResetStatusBarFX(bar.bar, 0)
  end
  ApplyPlayerProgress(0)
  if bar.name then bar.name:SetText(tostring(name or "")) end
  ApplyIcon(name)
  lastTimeText = nil
  ApplyTimer(duration)

  UpdateVisibility()
  UpdateTickRate()
end

-- Cast pushback. UnrealPfUI's libs/libcast.lua does exactly this on
-- SPELLCAST_DELAYED (`start = start + arg1/1000`): the start moves forward, so
-- the elapsed time this module derives from it shrinks and the fill rolls
-- backwards while the remaining time grows -- the native castbar's behaviour.
-- The total duration is deliberately untouched; only the end point moves.
local function DelayCast(delayMs)
  if not casting then return end

  local delay = (tonumber(delayMs) or 0) / 1000
  if delay <= 0 then return end

  startTime = startTime + delay
  delayCount = delayCount + 1
  delaySeconds = delaySeconds + delay
  ApplyPushback(delaySeconds)

  -- Redraw immediately rather than waiting up to a tick: a pushback that only
  -- showed on the next 0.1s tick would read as a stutter, not a rollback.
  local elapsed = GetTime() - startTime
  if elapsed < 0 then elapsed = 0 end
  ApplyPlayerProgress(elapsed)
  ApplyTimer(duration - elapsed)
end

-- Receives the event name from U.RegisterEvent; the tick's own duration
-- expiry calls it with none, which finishes the bar as a plain stop.
local function StopCast(eventName)
  if not casting then return end
  casting = false
  BeginFinish(bar, FINISH_KIND[eventName] or "stop")
  UpdateVisibility()
  UpdateTickRate()
end

Tick = function()
  if U.PerfDisabled and U.PerfDisabled("castbar") then return end

  UpdateVisibility()

  local i
  for i = 1, table.getn(trackerOrder) do
    local tracker = trackerOrder[i]
    UpdateUnitVisibility(tracker)

    if tracker.casting then
      -- UnitName is the strongest identity available in this event contract.
      -- Changing or clearing the unit must not leave the previous one cast
      -- visible at the new unit position.
      local currentName = Call("UnitName", tracker.unit)
      if currentName ~= tracker.caster then
        StopUnitCast(tracker)
      else
        local unitElapsed = GetTime() - tracker.startTime
        if unitElapsed >= tracker.duration then
          StopUnitCast(tracker, "stop")
        else
          if unitElapsed < 0 then unitElapsed = 0 end
          SetUnitBarValue(tracker.bar, unitElapsed)
          ApplyUnitTimer(tracker, tracker.duration - unitElapsed)
        end
      end
    elseif not FinishTick(tracker.bar) and tracker.bar and
           tracker.bar:IsShown() then
      ApplyUnitIdlePlaceholder(tracker)
    end
  end

  if not casting then
    if FinishTick(bar) then return end
    if bar and bar:IsShown() then ApplyIdlePlaceholder() end
    return
  end

  local elapsed = GetTime() - startTime
  if elapsed >= duration then
    -- No stop event arrived before the computed duration ran out. Treat the
    -- cast as finished rather than leaving a full bar on screen indefinitely.
    StopCast()
    return
  end

  -- A pushback can move the start ahead of now for a frame; clamp rather than
  -- hand the fill a negative value.
  if elapsed < 0 then elapsed = 0 end

  ApplyPlayerProgress(elapsed)
  ApplyTimer(duration - elapsed)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- Every addon-owned castbar draws in HIGH strata. UIParent children default to
-- MEDIUM, the same strata as the stock UI panels (TradeSkill, Craft, ...), so a
-- cast started from an open crafting window was hidden behind it. Children --
-- the theme skins and the mover handle -- follow the bar's strata.
local function RaiseCastbarStrata(widget)
  if widget then pcall(widget.SetFrameStrata, widget, "HIGH") end
end

-- Shared cell layout for both the player bar and the target anchor: the
-- icon flush left, the progress bar filling the rest of the width, name and
-- timer drawn on top of the fill. `frameName` distinguishes the created
-- widget names so registering both bars does not collide.
local function BuildBarWidget(frameName, width, height, parent)
  -- The optional height keeps the pet bar compact; all current widgets are
  -- free-standing mover targets parented to UIParent.
  height = height or HEIGHT
  local iconSize = height
  local barWidth = width - iconSize
  local widget = CreateFrame("Frame", frameName, parent or UIParent)
  RaiseCastbarStrata(widget)
  widget:SetWidth(width)
  widget:SetHeight(height)

  local border = U.BorderSize()

  -- Left cell: the spell icon.
  local iconCell = U.CreatePanel(widget, {
    name = frameName .. "Icon",
    width = iconSize,
    height = height,
  })
  iconCell:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)

  local icon = iconCell:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", iconCell, "TOPLEFT", border, -border)
  icon:SetPoint("BOTTOMRIGHT", iconCell, "BOTTOMRIGHT", -border, border)
  -- Trimmed the way modules/actionbar.lua trims its icons, so the stock icon
  -- border does not show inside the cell.
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  pcall(icon.SetTexture, icon, FALLBACK_ICON)
  widget.icon = icon
  widget.iconCell = iconCell
  widget.showIcon = true

  -- Right cell: the progress bar, flush against the icon and filling the rest
  -- of the width to the right edge, with the spell name and the timer both
  -- drawn on top of it.
  local barCell = U.CreatePanel(widget, {
    name = frameName .. "Progress",
    width = barWidth,
    height = height,
  })
  barCell:SetPoint("TOPLEFT", iconCell, "TOPRIGHT", 0, 0)

  widget.bar = U.CreateStatusBar(barCell, {
    width = barWidth - 2 * border,
    height = height - 2 * border,
    color = M.color.cast,
    background = M.color.healthBg,
  })
  widget.bar:SetPoint("TOPLEFT", barCell, "TOPLEFT", border, -border)

  -- knowledge.json / fonts.stretched_justification_ignored: anchored to the
  -- one edge it belongs to, with an explicit width so a long spell name stops
  -- before the timer instead of running under it.
  widget.name = U.CreateLabel(widget.bar, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if widget.name then
    widget.name:SetPoint("LEFT", widget.bar, "LEFT", 3, 0)
    pcall(widget.name.SetWidth, widget.name, barWidth - 34)
  end

  -- The timer. A FontString's OVERLAY draw layer sits above the fill
  -- texture's ARTWORK layer, so parenting it directly to the bar draws it on
  -- top of the progress fill rather than in a separate cell.
  widget.time = U.CreateLabel(widget.bar, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if widget.time then widget.time:SetPoint("RIGHT", widget.bar, "RIGHT", -3, 0) end

  -- Player-only state in practice, but part of the shared widget so its
  -- geometry remains consistent. Target casts never call ApplyPushback and
  -- therefore keep this label hidden.
  widget.pushback = U.CreateLabel(widget.bar, {
    size = M.fontSize.small,
    color = M.color.castPushback,
    inherits = "GameFontNormalSmall",
    justify = "RIGHT",
  })
  if widget.pushback then
    widget.pushback:SetPoint("RIGHT", widget.bar, "RIGHT", -3, 0)
    pcall(widget.pushback.SetWidth, widget.pushback, PUSHBACK_WIDTH)
    widget.pushback:SetText("")
    widget.pushback:Hide()
  end

  widget.uuiCells = { iconCell, barCell }

  return widget
end

-- The pet castbar uses the pet unit frame only to inherit its compact width.
-- Its own mover lets it be positioned independently and remains available in
-- edit mode even when no pet is summoned.
local function BuildPetBar()
  local anchor = type(U.GetUnitFrame) == "function" and U.GetUnitFrame("pet")
  if not anchor then
    U.Debug("castbar: no pet unit frame; pet castbar not built")
    return
  end

  local okWidth, width = pcall(anchor.GetWidth, anchor)
  width = okWidth and tonumber(width) or nil
  -- A width that cannot hold the icon square would give the progress cell a
  -- negative width, so fall back rather than build a broken row.
  if not width or width <= PET_HEIGHT then width = PET_FALLBACK_WIDTH end

  local pet = NewTracker("pet", "pet", "MOVER_LABEL_PET_CASTBAR")
  pet.bar = BuildBarWidget("UnrealUICastBarPet", width, PET_HEIGHT)
  ApplyUnitIdlePlaceholder(pet)
  pet.bar:Hide()
  SetWidgetCellsShown(pet.bar, false)

  -- Matches the original position directly beneath the default pet frame,
  -- including the one-unit border overlap the attached version used.
  U.RegisterMover("castbar.pet", pet.bar, {
    label = U.L("MOVER_LABEL_PET_CASTBAR"),
    default = {
      point = "TOPRIGHT", relativePoint = "BOTTOM",
      x = -75, y = 90 + U.BorderSize(),
    },
  })
end

local nativeTargetStyle = nil

-- Live target castbar. Modern uses the shared flat widget; Classic uses the
-- static addon-owned native skin from castbarclassic.lua. Classic never falls
-- back to Modern chrome: if that narrowly scoped builder is unavailable, the
-- target castbar stays absent instead of mixing interface styles.
-- While idle it is shown only in mover mode; recognized combat-log starts
-- show it while locked until their known duration expires.
local function BuildTargetBar()
  local classic = type(U.GetActiveThemeStyle) == "function" and
                  U.GetActiveThemeStyle() == "classic-wow"
  local widget
  if classic then
    if type(U.CreateClassicCastbar) == "function" then
      widget = U.CreateClassicCastbar("UnrealUICastBarTarget")
    end
    if not widget then
      nativeTargetStyle = "unavailable (no Modern fallback)"
      U.Debug("castbar: Classic target builder unavailable; target bar omitted")
      return
    end
    RaiseCastbarStrata(widget)
    nativeTargetStyle = "native static (verified border A)"
  else
    widget = BuildBarWidget("UnrealUICastBarTarget", TARGET_WIDTH)
  end

  local target = NewTracker("target", "target", "MOVER_LABEL_TARGET_CASTBAR")
  target.bar = widget
  ApplyUnitIdlePlaceholder(target)
  target.bar:Hide()
  SetWidgetCellsShown(target.bar, false)

  U.RegisterMover("castbar.target", target.bar, {
    label = U.L("MOVER_LABEL_TARGET_CASTBAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -250 },
  })
end

-- Classic player castbar.
--
-- The client's own CastingBarFrame advanced its fill in visible steps, so under
-- the Classic theme the player bar is rebuilt from the same addon-owned static
-- skin the Classic target bar uses and driven by this module's per-frame tick --
-- the same fill path that already reads smoothly on the target bar. The stock
-- frame is then suppressed through the established SuppressNativeCastbar path
-- rather than left drawing a second bar.
--
-- Returns false when the narrowly scoped Classic builder is unavailable, in
-- which case the caller keeps the previous behaviour: native bar untouched,
-- placed by its own mover handle.
local function BuildClassicPlayerBar()
  if type(U.CreateClassicCastbar) ~= "function" then return false end

  local widget = U.CreateClassicCastbar("UnrealUICastBar")
  if not widget then return false end
  RaiseCastbarStrata(widget)

  bar = widget
  bar:Hide()
  SetCellsShown(false)

  U.RegisterMover("castbar.player", bar, {
    label = U.L("MOVER_LABEL_CASTBAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -220 },
  })

  return true
end

-- Player cast events. Shared by both themes: the Classic bar is the same
-- widget contract and the same timing state, only a different skin.
local function RegisterPlayerCastEvents()
  U.RegisterEvent("SPELLCAST_START", function(event, name, castTimeMs)
    StartCast(name, castTimeMs)
    RememberTargetSpell(name, castTimeMs)
  end)

  -- Reversed argument order from SPELLCAST_START -- see the header note on
  -- the channelled-cast evidence gap (castTimeMs first, name second, per
  -- UnrealPfUI's libcast.lua:219). Since that order is WORKING_SOURCE and not
  -- measured here, the two are told apart by type instead of by position: the
  -- number is the duration and the string is the name, whichever way round
  -- this client sends them, and a payload carrying only a duration leaves the
  -- name to the action press above. The shape actually received is recorded
  -- for /uui check, so the gap can be closed from a real channel.
  U.RegisterEvent("SPELLCAST_CHANNEL_START", function(event, a, b)
    lastChannelShape = type(a) .. "/" .. type(b)

    local castTimeMs, name
    if tonumber(a) then castTimeMs, name = a, b else name, castTimeMs = a, b end
    if type(name) ~= "string" then name = nil end

    StartCast(name, castTimeMs, "channel")
  end)

  U.RegisterEvent("SPELLCAST_DELAYED", function(event, delayMs)
    DelayCast(delayMs)
  end)

  local i
  for i = 1, table.getn(STOP_EVENTS) do
    U.RegisterEvent(STOP_EVENTS[i], StopCast)
  end
end

local function Build()
  -- The container carries no art of its own: it is the mover target and the
  -- anchor the two cells hang off, so each cell keeps its own outline the way
  -- the reference layout shows them.
  bar = BuildBarWidget("UnrealUICastBar", WIDTH)
  if type(U.GetActiveThemeStyle) == "function" and
     U.GetActiveThemeStyle() == "modern" and
     type(U.AttachStatusBarFX) == "function" then
    U.AttachStatusBarFX(bar.bar)
  end
  bar:Hide()
  SetCellsShown(false)

  U.RegisterMover("castbar.player", bar, {
    label = U.L("MOVER_LABEL_CASTBAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -220 },
  })

  BuildTargetBar()
  BuildPetBar()
end

-- ---------------------------------------------------------------------------
-- Native castbar mover
--
-- Only used under a native-chrome theme, where the client draws the castbar and
-- this module draws nothing. Same shape as modules/petbar.lua: the native frame
-- is never hidden, reskinned, re-parented or click-handled -- it is only
-- re-anchored, and only once the player has placed the handle.
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted: anchors are read
-- through U.GetFramePoint, which hands back values in the shape SetPoint wants,
-- so a capture goes straight back through SetPoint unchanged.
-- ---------------------------------------------------------------------------

local NATIVE_NAME = "CastingBarFrame"

-- Used until the native frame reports its own size, and as the footprint if it
-- never does. The floor height is a grab target, not a claim about the bar.
local NATIVE_FALLBACK_WIDTH = 195
local NATIVE_FALLBACK_HEIGHT = 13
local HANDLE_MIN_HEIGHT = 20

-- Anchor offsets below this are treated as unchanged rather than drift.
local DRIFT_EPSILON = 0.5

local nativeFrame
local nativeMoverAnchor
local capturedNativeAnchor
local nativeDriving = false

-- Counts SetPoint calls on the native frame that did not go through. Reported
-- by /uui cb: a bar sitting in the wrong place with a non-zero count here is a
-- refused anchor, not a client that re-anchored its own frame.
local driveFailures = 0

local function CaptureNativeAnchor()
  if not nativeFrame then return nil end

  local point, relative, relativePoint, x, y = U.ReadFramePoint(nativeFrame)
  if type(point) ~= "string" then
    U.Debug("castbar: no readable native anchor to capture")
    return nil
  end

  if not relative then
    local ok, parent = pcall(nativeFrame.GetParent, nativeFrame)
    if ok then relative = parent end
  end
  if not relative then relative = UIParent end

  return {
    point = point,
    relative = relative,
    relativePoint = relativePoint or point,
    x = x,
    y = y,
  }
end

local function RestoreNativeAnchor()
  if not nativeFrame or not capturedNativeAnchor then return false end

  local ok = pcall(function()
    nativeFrame:ClearAllPoints()
    nativeFrame:SetPoint(capturedNativeAnchor.point,
                         capturedNativeAnchor.relative,
                         capturedNativeAnchor.relativePoint,
                         capturedNativeAnchor.x, capturedNativeAnchor.y)
  end)

  if ok then
    nativeDriving = false
    U.Debug("castbar: native castbar anchor restored")
  end
  return ok
end

local function NativeStoredPosition()
  local ok, position = pcall(U.GetPosition, "castbar.player")
  if not ok or type(position) ~= "table" then return nil end
  if type(position.point) ~= "string" then return nil end
  return position
end

-- Written only when it actually changes: this runs on a shared tick and the
-- handle is SetAllPoints to this frame, so a size write is a handle relayout
-- for nothing.
local function MirrorNativeSize()
  if not nativeMoverAnchor or not nativeFrame then return end

  local okW, w = pcall(nativeFrame.GetWidth, nativeFrame)
  local okH, h = pcall(nativeFrame.GetHeight, nativeFrame)

  w = okW and tonumber(w) or nil
  h = okH and tonumber(h) or nil

  local width = (w and w > 0 and w) or NATIVE_FALLBACK_WIDTH
  local height = (h and h > 0 and h) or NATIVE_FALLBACK_HEIGHT
  if height < HANDLE_MIN_HEIGHT then height = HANDLE_MIN_HEIGHT end

  if nativeMoverAnchor.uuiWidth ~= width then
    nativeMoverAnchor:SetWidth(width)
    nativeMoverAnchor.uuiWidth = width
  end
  if nativeMoverAnchor.uuiHeight ~= height then
    nativeMoverAnchor:SetHeight(height)
    nativeMoverAnchor.uuiHeight = height
  end
end

local function AnchorDrifted(position)
  local point, relative, relativePoint, x, y =
    U.ReadFramePoint(nativeMoverAnchor)
  if type(point) ~= "string" then return true end
  if relative and relative ~= UIParent then return true end
  if point ~= position.point then return true end
  if relativePoint ~= (position.relativePoint or position.point) then return true end
  if math.abs(x - (tonumber(position.x) or 0)) > DRIFT_EPSILON then return true end
  if math.abs(y - (tonumber(position.y) or 0)) > DRIFT_EPSILON then return true end
  return false
end

-- Has the client re-anchored its own bar out from under us?
--
-- The point count is checked first, and deliberately. A frame keeps every
-- anchor set on it and is positioned by all of them at once, but GetPoint(1)
-- reports only the first -- so a second point added after DriveNative's
-- ClearAllPoints moves the bar while leaving point 1 still reading as ours.
-- Testing point 1 alone cannot see that, and reports no drift for a bar that
-- has visibly moved.
local function NativeDrifted()
  local okCount, count = pcall(nativeFrame.GetNumPoints, nativeFrame)
  if okCount and tonumber(count) and tonumber(count) ~= 1 then return true end

  local point, relative, relativePoint, x, y = U.GetFramePoint(nativeFrame, 1)
  if type(point) ~= "string" then return true end
  if relative ~= nativeMoverAnchor then return true end
  if point ~= "CENTER" or relativePoint ~= "CENTER" then return true end
  if math.abs(x) > DRIFT_EPSILON or math.abs(y) > DRIFT_EPSILON then return true end
  return false
end

-- Centre-on-centre needs neither frame to know how wide the other is, which is
-- what lets the handle carry a floor height without shifting the bar.
-- nativeDriving is set from the pcall result, not unconditionally. Claiming the
-- drive succeeded when the SetPoint was refused would leave ApplyNativeAnchor
-- believing it owned an anchor it had never written, and would hide exactly the
-- failure /uui cb exists to find.
local function DriveNative()
  local ok = pcall(function()
    nativeFrame:ClearAllPoints()
    nativeFrame:SetPoint("CENTER", nativeMoverAnchor, "CENTER", 0, 0)
  end)

  if ok then
    nativeDriving = true
  else
    driveFailures = driveFailures + 1
    if driveFailures == 1 then
      U.Debug("castbar: re-anchoring " .. NATIVE_NAME .. " was refused")
    end
  end
end

local function FollowNative()
  pcall(function()
    nativeMoverAnchor:ClearAllPoints()
    nativeMoverAnchor:SetPoint("CENTER", nativeFrame, "CENTER", 0, 0)
  end)
end

local function ApplyNativeAnchor()
  if U.PerfDisabled and U.PerfDisabled("castbar") then return end
  if not nativeMoverAnchor or not nativeFrame then return end

  MirrorNativeSize()

  local position = NativeStoredPosition()
  local unlocked = U.IsUnlocked()

  if not position then
    -- Never placed, or /uui reset: hand the bar back to the client once, then
    -- keep the handle shadowing it. Not mid-drag -- re-anchoring the handle to
    -- the native bar then would snap it out of the player's hand.
    if nativeDriving then RestoreNativeAnchor() end
    if not unlocked then FollowNative() end
    return
  end

  -- The mover owns the anchor between StartMoving and StopMovingOrSizing, so
  -- the stored position is only re-applied while locked. The native bar is
  -- anchored *to* the anchor, so it tracks the handle live during a drag with
  -- no second write.
  if not unlocked and AnchorDrifted(position) then
    U.ApplyFramePoint(nativeMoverAnchor, position)
  end

  if NativeDrifted() then DriveNative() end
end

local function SetupNativeMover()
  nativeFrame = U.G(NATIVE_NAME)
  if not nativeFrame then
    U.Debug("castbar: " .. NATIVE_NAME .. " not found; no castbar mover")
    return
  end

  -- Before RegisterMover, which is what may apply a stored position.
  capturedNativeAnchor = CaptureNativeAnchor()

  -- Carries a mover handle and nothing else: no backdrop, no mouse, no strata
  -- of its own. It must never sit in front of the bar it is placing.
  nativeMoverAnchor = CreateFrame("Frame", "UnrealUICastBarAnchor", UIParent)
  nativeMoverAnchor:SetWidth(NATIVE_FALLBACK_WIDTH)
  nativeMoverAnchor:SetHeight(HANDLE_MIN_HEIGHT)
  MirrorNativeSize()
  FollowNative()
  -- Stays shown even though the bar it places does not: the native castbar
  -- only exists mid-cast, and a handle that only appeared mid-cast could not
  -- be dragged.
  nativeMoverAnchor:Show()

  -- Same id as the modern bar's mover, so a position placed under one theme is
  -- the position used under the other. No `default`: the client's own anchor
  -- need not be UIParent-relative and cannot be written as one, which is the
  -- case core/mover.lua documents U.OnPositionReset for.
  U.RegisterMover("castbar.player", nativeMoverAnchor, {
    label = U.L("MOVER_LABEL_CASTBAR"),
  })
  U.OnPositionReset(function() return RestoreNativeAnchor() end)

  ApplyNativeAnchor()

  -- Accelerators, so a cast that starts right after the client re-anchors its
  -- bar is not drawn in the old place for up to one tick. The tick below is
  -- the guarantee; these only make it prompt.
  local refresh = function() ApplyNativeAnchor() end
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("SPELLCAST_START", refresh)
  U.RegisterEvent("SPELLCAST_CHANNEL_START", refresh)

  -- One anchor read twice a second against a frame that rarely moves. The
  -- modern bar's per-frame tick is not registered in this mode at all.
  U.RegisterUpdate("castbar.anchor", 0.5, ApplyNativeAnchor)
end

-- ---------------------------------------------------------------------------
-- Quarantined native-styled target castbar experiment
--
-- CastingBarFrame, so the target's bar should look like that bar rather than
-- introducing the modern one into an otherwise native interface. There is no
-- native target castbar to reuse (see the header), so the look is rebuilt: the
-- live CastingBarFrame is read back and whatever it is drawing is cloned onto
-- an UnrealUI frame.
-- This builder is intentionally not invoked. It is preserved only to make the
-- failed experiment and the pending focused-probe comparison reviewable; see
-- frames.native_widget_reference_crash_risk. The long-comment quarantine keeps
-- the experiment out of Lua bytecode and prevents helper/table construction.
--
-- Nothing here hardcodes an asset path or a Vanilla layout. Every piece is what
-- the live frame reports -- texture file, draw layer, size, anchors -- so a
-- client that dresses its castbar differently gets a matching target bar, and a
-- client that will not answer these reads gets nil and the modern widget. The
-- native frame itself is only read: never hidden, re-parented, re-anchored or
-- scripted by this code.
--
-- Three client facts shape it, all from compact evidence rather than from
-- Vanilla habit:
--
--   * There is no GetStatusBarTexture on this client (documentation.json,
--     widget-method:StatusBar:SetStatusBarTexture). The fill is therefore
--     found among the bar's own regions instead of being asked for.
--   * There is no GetVertexColor either (knowledge.json /
--     textures.getvertexcolor_readback_missing), so no tint can be copied.
--     None is imposed either: the clone draws in the colours its art was
--     authored with, and ApplyUnitBarTint leaves this widget alone.
--   * The fill is an UnrealUI status bar, not CreateFrame("StatusBar"):
--     knowledge.json / statusbar.native_widget_fill_not_laid_out is a
--     confirmed runtime failure of the real widget's fill here. That bar
--     squashes its fill texture rather than clipping it, which is the one
--     visible departure from how the client draws its own.
--
-- Anchors are read through U.GetFramePoint for the Y inversion recorded in
-- knowledge.json / frames.getpoint_relative_name_y_inverted, so a captured
-- point goes back through SetPoint unchanged.
-- ---------------------------------------------------------------------------

--[=[

local NATIVE_STATUS_NAME = "CastingBarFrameStatusBar"

-- Untinted art on an invisible backdrop: the client's own castbar art carries
-- its own colours and its own bar bed.
local NATIVE_STYLE_TINT = { 1, 1, 1, 1 }
local NATIVE_STYLE_BACKDROP = { 0, 0, 0, 0 }

local function NativeDimension(frame, method, fallback)
  if not frame then return fallback end
  local ok, value = pcall(frame[method], frame)
  value = ok and tonumber(value) or nil
  if not value or value <= 0 then return fallback end
  return value
end

-- The client names its own castbar pieces -- in the region name, in the asset
-- file name, or both -- so both are searched. Anything unrecognised is treated
-- as static chrome, which is the safe default: a driven piece put in the wrong
-- place would be visibly wrong, while an unclassified static texture simply
-- travels with the rest of the art.
local function RegionRole(region)
  local label = ""
  local okName, name = pcall(region.GetName, region)
  if okName and type(name) == "string" then label = string.lower(name) end

  local okTexture, path = pcall(region.GetTexture, region)
  if not okTexture or type(path) ~= "string" or path == "" then
    return nil, nil
  end
  label = label .. " " .. string.lower(path)

  if string.find(label, "spark", 1, true) then return "spark", path end
  if string.find(label, "flash", 1, true) then return "flash", path end
  if string.find(label, "fill", 1, true) then return "fill", path end
  return "chrome", path
end

-- Every texture and font string the frame will hand over, as a flat list.
-- GetRegions returns them as multiple values, and a frame that refuses the
-- call costs its own regions rather than the whole bar.
local function NativeRegions(frame)
  if not frame or type(frame.GetRegions) ~= "function" then return {} end
  local ok, list = pcall(function() return { frame:GetRegions() } end)
  if not ok or type(list) ~= "table" then return {} end
  return list
end

-- Copies one native object's anchors onto ours, translating each relative
-- frame through `map` (native frame -> ours). A point that hangs off something
-- outside the castbar cannot be translated and is dropped; `owner` is what a
-- point with no relative frame of its own means. Returns how many landed, so
-- the caller can place a piece that got none.
--
-- U.GetFramePoint, not GetPoint: knowledge.json /
-- frames.getpoint_relative_name_y_inverted.
local function CopyPoints(source, target, map, owner)
  local copied = 0
  local okCount, count = pcall(source.GetNumPoints, source)
  count = okCount and tonumber(count) or 0

  local i
  for i = 1, count do
    local point, relative, relativePoint, x, y = U.GetFramePoint(source, i)
    if not relative then relative = owner end
    local anchor = point and relative and map[relative]
    if anchor and pcall(target.SetPoint, target, point, anchor,
                        relativePoint or point, x, y) then
      copied = copied + 1
    end
  end

  return copied
end

-- One native texture region copied onto one of our frames: same file, same
-- draw layer, same blend, same size, and the same anchors wherever they
-- pointed at a frame we have a counterpart for.
local function CloneRegion(region, path, parent, map, owner)
  local layer = "ARTWORK"
  local okLayer, reported = pcall(region.GetDrawLayer, region)
  if okLayer and type(reported) == "string" and reported ~= "" then
    layer = reported
  end

  local okCreate, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not okCreate or not texture then return nil end
  if not pcall(texture.SetTexture, texture, path) then return nil end

  local okBlend, blend = pcall(region.GetBlendMode, region)
  if okBlend and type(blend) == "string" and blend ~= "" then
    pcall(texture.SetBlendMode, texture, blend)
  end

  local width = NativeDimension(region, "GetWidth", nil)
  local height = NativeDimension(region, "GetHeight", nil)
  if width then pcall(texture.SetWidth, texture, width) end
  if height then pcall(texture.SetHeight, texture, height) end

  -- Anchored to something outside the castbar: it cannot be placed
  -- meaningfully on a copy, so centre it rather than stack it at the origin.
  if CopyPoints(region, texture, map, owner) == 0 then
    pcall(texture.SetPoint, texture, "CENTER", parent, "CENTER", 0, 0)
  end

  return texture
end

-- The client's own castbar font object, so the spell name is set in the type
-- the client sets it in. Its name is what CreateFontString wants; U.CreateLabel
-- takes the same string through `inherits`.
local function NativeFontName(regions)
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local okType, objectType = pcall(region.GetObjectType, region)
    if okType and objectType == "FontString" then
      local okFont, font = pcall(region.GetFontObject, region)
      if okFont and font then
        local okName, name = pcall(font.GetName, font)
        if okName and type(name) == "string" and name ~= "" then return name end
      end
    end
  end
  return nil
end

-- A font string in the client's own castbar font, falling back to the shared
-- label the modern bar uses when this client will not inherit that object.
local function NativeStyleLabel(parent, fontName, justify)
  local label
  if fontName then
    local ok, created = pcall(parent.CreateFontString, parent, nil, "OVERLAY",
                              fontName)
    if ok then label = created end
  end
  if not label then
    return U.CreateLabel(parent, {
      size = M.fontSize.small,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
      justify = justify,
    })
  end
  if justify then pcall(label.SetJustifyH, label, justify) end
  return label
end

NativeStyleTargetWidget = function(frameName)
  local native = U.G(NATIVE_NAME)
  if not native then
    nativeTargetStyle = "modern (no " .. NATIVE_NAME .. ")"
    return nil
  end

  -- The fill may live on the frame itself or on a named status-bar child; both
  -- shapes are searched.
  local statusFrame = U.G(NATIVE_STATUS_NAME)
  if statusFrame == native then statusFrame = nil end

  local coreRegions = NativeRegions(native)
  local statusRegions = NativeRegions(statusFrame)

  local chrome, fillPath, sparkRegion, sparkPath = {}, nil, nil, nil

  local Scan = function(regions, owner)
    local i
    for i = 1, table.getn(regions) do
      local region = regions[i]
      local role, path = RegionRole(region)
      if role == "fill" then
        if not fillPath then fillPath = path end
      elseif role == "spark" then
        if not sparkRegion then sparkRegion, sparkPath = region, path end
      elseif role == "chrome" then
        table.insert(chrome, { region = region, path = path, owner = owner })
      end
      -- "flash" is deliberately dropped: it is the client's cast-finished
      -- animation, driven by scripts this module does not reproduce.
    end
  end

  Scan(coreRegions, native)
  Scan(statusRegions, statusFrame)

  -- A single unclassified texture on the status child is the fill in any layout
  -- where the bar texture is unnamed: a status bar's one region is what it
  -- fills with.
  if not fillPath and statusFrame and table.getn(statusRegions) == 1 then
    local _, only = RegionRole(statusRegions[1])
    fillPath = only
  end

  -- The two pieces that make this a castbar rather than a stray texture. Half a
  -- clone is worse than the modern bar, so a miss falls back instead.
  if not fillPath then
    nativeTargetStyle = "modern (no fill texture)"
    return nil
  end
  if table.getn(chrome) == 0 then
    nativeTargetStyle = "modern (no border art)"
    return nil
  end

  local coreWidth = NativeDimension(native, "GetWidth", NATIVE_FALLBACK_WIDTH)
  local coreHeight = NativeDimension(native, "GetHeight", NATIVE_FALLBACK_HEIGHT)
  local fillWidth = NativeDimension(statusFrame, "GetWidth", coreWidth)
  local fillHeight = NativeDimension(statusFrame, "GetHeight", coreHeight)

  -- Three frames: the container is the mover target and is given the same grab
  -- floor the player handle uses, since a 13-unit bar is not a comfortable one;
  -- the core stands in for the native frame, so cloned anchors carry over
  -- unchanged; the fill is the bar itself.
  --
  -- Its own global name, not the modern widget's: the two checks below can
  -- still fall back after the frames exist, and two frames answering to one
  -- name would leave the dump reading the wrong one.
  frameName = frameName .. "Native"

  local container = CreateFrame("Frame", frameName, UIParent)
  RaiseCastbarStrata(container)
  container:SetWidth(coreWidth)
  container:SetHeight(math.max(coreHeight, HANDLE_MIN_HEIGHT))

  local core = CreateFrame("Frame", nil, container)
  core:SetWidth(coreWidth)
  core:SetHeight(coreHeight)
  core:SetPoint("CENTER", container, "CENTER", 0, 0)

  local fill = U.CreateStatusBar(core, {
    name = frameName .. "Fill",
    width = fillWidth,
    height = fillHeight,
    texture = fillPath,
    color = NATIVE_STYLE_TINT,
    background = NATIVE_STYLE_BACKDROP,
  })
  if not fill then
    container:Hide()
    nativeTargetStyle = "modern (status bar not created)"
    return nil
  end
  -- A region anchored to the native status child maps onto our fill, and one
  -- anchored to the native frame maps onto the core.
  local map = { [native] = core }
  if statusFrame then map[statusFrame] = fill end

  -- The fill sits where the client's own bar sits inside its frame. Centring is
  -- only the fallback: a bar inset into its border art would otherwise be drawn
  -- in the middle of it.
  if not statusFrame or CopyPoints(statusFrame, fill, map, native) == 0 then
    fill:SetPoint("CENTER", core, "CENTER", 0, 0)
  end

  local cloned = 0
  local i
  for i = 1, table.getn(chrome) do
    local piece = chrome[i]
    local parent = core
    if piece.owner == statusFrame then parent = fill end
    if CloneRegion(piece.region, piece.path, parent, map, piece.owner) then
      cloned = cloned + 1
    end
  end

  if cloned == 0 then
    -- The frames exist by now, but an empty shell is worse than the modern
    -- bar: hide it and let the caller build that one instead.
    container:Hide()
    nativeTargetStyle = "modern (border art would not clone)"
    return nil
  end

  local fontName = NativeFontName(coreRegions)
  if not fontName then fontName = NativeFontName(statusRegions) end

  -- The client centres the spell name on its castbar. The countdown is an
  -- UnrealUI addition the native bar reserves no room for, so the name is given
  -- an explicit width and shifted left of it rather than left to run under it.
  local name = NativeStyleLabel(core, fontName, "CENTER")
  if name then
    name:SetPoint("CENTER", fill, "CENTER", -14, 0)
    pcall(name.SetWidth, name, math.max(20, fillWidth - 40))
  end

  local time = NativeStyleLabel(core, fontName, "RIGHT")
  if time then time:SetPoint("RIGHT", fill, "RIGHT", -3, 0) end

  local spark
  if sparkRegion then
    spark = CloneRegion(sparkRegion, sparkPath, core, map, native)
    if spark then
      -- Re-anchored on every fill write, so the cloned anchors are dropped.
      pcall(spark.ClearAllPoints, spark)
      pcall(spark.Hide, spark)
    end
  end

  container.bar = fill
  container.name = name
  container.time = time
  -- No icon: the client's castbar carries none, and the tracker code skips the
  -- icon entirely when the widget has no texture for it.
  container.icon = nil
  container.showIcon = false
  container.uuiCells = {}
  container.uuiKeepNativeTint = true

  if spark then
    container.uuiUpdateSpark = function()
      local size = tonumber(fill:GetWidth()) or 0
      local minimum, maximum = fill:GetMinMaxValues()
      minimum = tonumber(minimum) or 0
      local range = (tonumber(maximum) or 0) - minimum
      local extent = 0
      if range > 0 and size > 0 then
        extent = size / range * ((tonumber(fill:GetValue()) or 0) - minimum)
      end
      if extent < 0 then extent = 0 end
      if extent > size then extent = size end

      if extent <= 0 then
        if spark:IsShown() then spark:Hide() end
        return
      end

      spark:ClearAllPoints()
      spark:SetPoint("CENTER", fill, "LEFT", extent, 0)
      if not spark:IsShown() then spark:Show() end
    end
  end

  nativeTargetStyle = "native (" .. cloned .. " chrome" ..
                      (spark and " + spark" or "") ..
                      (fontName and (", font " .. fontName) or ", addon font") ..
                      ")"
  return container
end

]=] -- quarantined native-style experiment

-- ---------------------------------------------------------------------------
-- /uui cb -- native castbar placement dump
--
-- Armed rather than immediate, the way /uui map arms its hover watch: the
-- native castbar only exists mid-cast, so there is nothing to measure at the
-- moment the command is typed.
--
-- It samples twice -- the frame as soon as it is shown, and again a moment
-- later -- because the open questions have different signatures, and one
-- sample cannot tell them apart:
--
--   * the anchor still reads CENTER -> UnrealUICastBarAnchor in both samples,
--     but the visible bar is somewhere else -- a child carries its own anchor,
--     and moving the parent moves nothing;
--   * the anchor reads ours in the first sample and something else in the
--     second -- the client re-anchors its own bar when it shows, and the fix
--     has to re-drive from that moment rather than from a tick;
--   * the anchor never reads ours at all -- the SetPoint in DriveNative is
--     failing, or the frame drawing the bar is not this one.
--
-- Children are listed with their own rects because documentation.json names
-- CastingBarFrameStatusBar as a frame that exists on this client, which is
-- exactly the shape the first case would take.
-- ---------------------------------------------------------------------------

local DUMP_SECOND_SAMPLE = 0.3
local DUMP_TIMEOUT = 30

-- Timed off GetTime rather than the tick argument: the shared updater hands a
-- callback its registered *interval*, which is 0 for a per-tick consumer like
-- this one and would never accumulate.
local dumpArmed = false
local dumpArmedAt = 0
local dumpShownAt = nil
local dumpFirst = nil

local function Num(value)
  value = tonumber(value)
  if not value then return "?" end
  return string.format("%.0f", value)
end

local function FrameName(frame)
  if not frame then return "nil" end
  local ok, name = pcall(frame.GetName, frame)
  if ok and type(name) == "string" and name ~= "" then return name end
  return "<unnamed>"
end

-- One frame's placement as a list of printable lines. Everything is read
-- through pcall so a frame that does not answer a method costs one line of the
-- dump rather than the whole command.
local function DescribeFrame(frame, label, lines)
  if not frame then
    table.insert(lines, label .. ": missing")
    return
  end

  local okShown, shown = pcall(frame.IsShown, frame)
  local okParent, parent = pcall(frame.GetParent, frame)
  table.insert(lines, label .. ": shown " ..
               tostring(okShown and shown and true or false) ..
               ", parent " .. FrameName(okParent and parent or nil))

  -- Every point, not just the first. A frame carrying a second anchor is
  -- positioned by both, while GetPoint(1) keeps reporting only the first --
  -- which is how a bar can report an anchor it is visibly not sitting on.
  -- Read raw rather than through U.GetFramePoint, because that helper inverts
  -- Y for round-tripping through SetPoint and this needs the client's own
  -- numbers.
  local okCount, count = pcall(frame.GetNumPoints, frame)
  count = okCount and tonumber(count) or nil

  if not count then
    table.insert(lines, "  points: GetNumPoints unavailable")
  else
    table.insert(lines, "  points: " .. count)
    local i
    for i = 1, count do
      local ok, point, relative, relativePoint, x, y =
        pcall(frame.GetPoint, frame, i)
      if ok and type(point) == "string" then
        if type(relative) == "string" then relative = U.G(relative) end
        table.insert(lines, "   [" .. i .. "] " .. point .. " -> " ..
                     FrameName(relative) .. "." .. tostring(relativePoint) ..
                     "  " .. Num(x) .. "," .. Num(y) .. " (raw)")
      else
        table.insert(lines, "   [" .. i .. "] unreadable")
      end
    end
  end

  local okL, left = pcall(frame.GetLeft, frame)
  local okB, bottom = pcall(frame.GetBottom, frame)
  local okW, width = pcall(frame.GetWidth, frame)
  local okH, height = pcall(frame.GetHeight, frame)
  table.insert(lines, "  rect " .. Num(okL and left) .. "," ..
               Num(okB and bottom) .. "  " .. Num(okW and width) .. "x" ..
               Num(okH and height))
end

-- The child list is the whole point of the first hypothesis: a child anchored
-- to something other than its parent stays put when the parent moves.
local function DescribeChildren(frame, lines)
  if not frame or type(frame.GetChildren) ~= "function" then
    table.insert(lines, "  children unavailable")
    return
  end

  local ok, c1, c2, c3, c4, c5, c6 = pcall(frame.GetChildren, frame)
  if not ok then
    table.insert(lines, "  children unreadable")
    return
  end

  local kids = { c1, c2, c3, c4, c5, c6 }
  local i, found = nil, 0
  for i = 1, 6 do
    if kids[i] then
      found = found + 1
      DescribeFrame(kids[i], "  child " .. i .. " " .. FrameName(kids[i]),
                    lines)
    end
  end
  if found == 0 then table.insert(lines, "  no child frames") end
end

local function Sample(label)
  local lines = {}
  table.insert(lines, "-- " .. label .. " --")
  DescribeFrame(nativeFrame, NATIVE_NAME, lines)
  DescribeChildren(nativeFrame, lines)
  DescribeFrame(nativeMoverAnchor, "UnrealUICastBarAnchor", lines)
  return lines
end

local function PrintLines(lines)
  local i
  for i = 1, table.getn(lines) do
    U.Print(lines[i])
  end
end

local function DumpTick()
  if not dumpArmed then return end

  local now = GetTime()

  if not dumpShownAt then
    if now - dumpArmedAt > DUMP_TIMEOUT then
      dumpArmed = false
      U.UnregisterUpdate("castbar.dump")
      U.Print("castbar dump: no cast started within " ..
              DUMP_TIMEOUT .. "s; disarmed")
      return
    end

    local ok, shown = pcall(nativeFrame.IsShown, nativeFrame)
    if not (ok and shown) then return end

    dumpShownAt = now
    dumpFirst = Sample("at show")
    return
  end

  if now - dumpShownAt < DUMP_SECOND_SAMPLE then return end

  local second = Sample("+" .. DUMP_SECOND_SAMPLE .. "s")

  dumpArmed = false
  U.UnregisterUpdate("castbar.dump")

  U.Print("castbar dump: placed " ..
          tostring(NativeStoredPosition() and true or false) ..
          ", driving " .. tostring(nativeDriving) ..
          ", drive errors " .. tostring(driveFailures))
  PrintLines(dumpFirst)
  PrintLines(second)
end

-- Reached from /uui cb.
function U.CastbarNativeDump()
  if not nativeChrome then
    U.Print("castbar dump: only applies under a native-chrome theme; " ..
            "the active theme is " .. tostring(U.GetActiveThemeStyle()))
    return
  end
  if not nativeFrame then
    U.Print("castbar dump: " .. NATIVE_NAME .. " was not found at load")
    return
  end

  dumpArmed = true
  dumpArmedAt = GetTime()
  dumpShownAt = nil
  dumpFirst = nil
  U.RegisterUpdate("castbar.dump", 0, DumpTick)
  U.Print("castbar dump armed: cast something, or open a quest object")
end

-- The combat-log reconstruction's events. Registered in both castbar modes,
-- because the target bar exists in both; the pet tracker, when it was built,
-- rides the same messages.
local function RegisterUnitCastEvents()
  local i
  for i = 1, table.getn(TARGET_COMBAT_EVENTS) do
    U.RegisterEvent(TARGET_COMBAT_EVENTS[i], OnUnitCombatMessage)
  end

  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    StopUnitCast(trackers.target)
  end)
end

function CB:OnEnable()
  -- The modern path creates all three addon bars. Native-chrome mode builds
  -- the addon-owned Classic player and target bars; no pet reconstruction is
  -- introduced in that mode.
  if bar or trackers.target then return end

  -- Before any bar is built: the theme decides which player widget is made.
  -- Both Classic bars use static verified paths and never inspect the native
  -- frame; the only native call in that mode is SuppressNativeCastbar.
  nativeChrome = type(U.ThemeStyleUsesNativeChrome) == "function" and
                 U.ThemeStyleUsesNativeChrome() or false
  if nativeChrome then
    -- The Classic skin can carry the player bar itself, which is the only way
    -- to give it the per-frame fill the target bar already has. Only if that
    -- builder is unavailable does the client keep drawing its own bar.
    if BuildClassicPlayerBar() then
      SuppressNativeCastbar()
      RegisterPlayerCastEvents()
    else
      U.Debug("castbar: no Classic player bar; leaving CastingBarFrame alone")
      SetupNativeMover()
    end
    BuildTargetBar()
    BuildTargetPatterns()
    RegisterUnitCastEvents()
    UpdateTickRate()
    return
  end

  Build()
  SuppressNativeCastbar()
  BuildTargetPatterns()
  RegisterPlayerCastEvents()
  RegisterUnitCastEvents()

  -- modules/actionbar.lua announces every press just before it hands the slot
  -- to UseAction; that is what lets a nameless channel still be identified.
  if type(U.RegisterActionUsed) == "function" then
    U.RegisterActionUsed(RememberPress)
  end

  -- A new pet has a different name and a different spellbook, so the running
  -- bar and the cached pet icons both belong to the old one. The tick's own
  -- name check would catch the cast a frame later; this is just immediate.
  U.RegisterEvent("UNIT_PET", function()
    petIconCache = {}
    StopUnitCast(trackers.pet)
  end)

  -- Same invalidation UnrealPfUI's libspell uses: a newly learned rank changes
  -- which spellbook index a name resolves to -- and, since the walk now
  -- records it, the cached rank itself, which is a duration on a target's
  -- debuff timer and not just an icon.
  -- SPELLS_CHANGED as well as LEARNED_SPELL_IN_TAB: a miss is cached as `false`
  -- and never re-scanned, so a lookup that ran before the spellbook was
  -- readable would otherwise keep a spell iconless for the whole session.
  U.RegisterEvent("SPELLS_CHANGED", function() iconCache = {} end)
  U.RegisterEvent("LEARNED_SPELL_IN_TAB", function()
    iconCache = {}
  end)

  UpdateTickRate()
end

-- Whether a combat-log tracker ever saw a start, and on which event, is the
-- open question for both reconstructed bars: the pet family in particular has
-- no captured evidence saying which CHAT_MSG_SPELL event carries a pet's cast
-- text on this client, so `starts` and `lastEvent` are how that gets answered.
local function TrackerReport(tracker)
  if not tracker then return nil end

  return {
    casting = tracker.casting,
    caster = tracker.caster,
    spell = tracker.spell,
    duration = tracker.duration,
    remaining = tracker.casting and
                (tracker.duration - (GetTime() - tracker.startTime)) or nil,
    starts = tracker.starts,
    unknown = tracker.unknown,
    lastUnknown = tracker.lastUnknown,
    lastEvent = tracker.lastEvent,
    iconSource = tracker.iconSource,
    patterns = table.getn(targetStartPatterns),
    built = tracker.bar and true or false,
  }
end

-- Measured state for /uui check: what the client actually sent, not another
-- assumption about the SPELLCAST_START tuple. iconSource and delays are the
-- two fields that settle the WORKING_SOURCE gaps in this module's header --
-- whether the spellbook lookup resolves a real texture, and whether this
-- client emits SPELLCAST_DELAYED at all.
function U.CastbarReport()
  -- `not bar` as well as nativeChrome: with the Classic player bar built, the
  -- native mover is never set up and this branch would report a stored
  -- castbar.player position as if the client's frame were being driven by it.
  if nativeChrome and not bar then
    return {
      native = true,
      nativeSuppressed = false,
      nativeFound = nativeFrame and true or false,
      anchor = nativeMoverAnchor and true or false,
      placed = NativeStoredPosition() and true or false,
      driving = nativeDriving,
      driveFailures = driveFailures,
      nativeAnchorCaptured = capturedNativeAnchor and true or false,
      target = TrackerReport(trackers.target),
      targetStyle = nativeTargetStyle,
    }
  end
  if not bar then return nil end

  local shownOk, shown = pcall(bar.IsShown, bar)
  return {
    casting = casting,
    shown = shownOk and shown or "?",
    duration = duration,
    remaining = casting and (duration - (GetTime() - startTime)) or nil,
    iconSource = lastIconSource,
    channelShape = lastChannelShape,
    delays = delayCount,
    delaySeconds = delaySeconds,
    nativeSuppressed = nativeCastbarSuppressed,
    target = TrackerReport(trackers.target),
    targetStyle = nativeTargetStyle,
    pet = TrackerReport(trackers.pet),
  }
end
