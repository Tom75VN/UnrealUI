-- unrealUI :: modules/healpredict.lua
--
-- Incoming-heal prediction: while a heal of yours is in the air, the part of
-- the target's health bar it is about to fill is painted ahead of it, so an
-- overheal is visible before it is wasted. Drawn by modules/unitframes.lua on
-- every unit frame it owns -- player, target, target-of-target, pet and the
-- party rows -- through the shared bar segments in core/style.lua.
--
-- ---------------------------------------------------------------------------
-- What it looks like
-- ---------------------------------------------------------------------------
--
-- ElvUI's healPrediction arrangement, by request:
--
--   [ CURRENT HEALTH ][ YOUR HEAL ][ OTHER HEALS ]
--
-- Two translucent segments chained onto the right edge of the health fill with
-- no gap -- mint #00FF80 at 25% for your own cast, pure #00FF00 at 25% for
-- other players' -- each measured against the bar's own 0 -> maxHealth range,
-- so a heal worth a fifth of maximum health takes a fifth of the bar. Nothing
-- overflows past 100% (ElvUI's maxOverflow default of 0). A vertical bar stacks
-- the same order upward. The colours are M.color.healPredictionMine and
-- healPredictionOthers; the geometry is U.SetStatusBarPrediction.
--
-- A segment is drawn on the health bar's own statusbar texture, not a flat
-- one, and follows the bar when it changes material -- a target or party bar
-- runs on normTex2 and a class-coloured bar switches to it at runtime, so a
-- fixed flat band would read as a different surface glued to the fill. ElvUI
-- builds its prediction bars on the health texture for the same reason.
--
-- Only the first segment can ever have a value here -- see U.UnitIncomingHeal
-- below for why the split is kept anyway.
--
-- ---------------------------------------------------------------------------
-- Why this is reconstructed
-- ---------------------------------------------------------------------------
--
-- There is no UnitGetIncomingHeals on this client: query_compat.py returns no
-- match at all for it, or for any incoming-heal API, across api/frames/events/
-- behavior/knowledge/documentation. The number has to be built here.
--
-- UnrealPfUI does exactly that in libs/libpredict.lua on this same client, and
-- this module follows its two-part shape -- learn each spell's real heal from
-- the combat log, then open a prediction when that spell starts casting. That
-- is WORKING_SOURCE evidence per .claude/rules/unreal-pfui.md, not runtime
-- verification, and the parts of it that depend on APIs this client does not
-- have are deliberately left out (see "What is not taken" below).
--
-- ---------------------------------------------------------------------------
-- Where the amount comes from
-- ---------------------------------------------------------------------------
--
-- From the player's own heals as they land. The four self-heal templates exist
-- on this client with Vanilla's exact wording -- a globals capture from this
-- runtime (runtime-reports/UnrealRuntimeProbe-2026-08-16-invalid.lua) records
-- HEALEDSELFOTHER "Your %s heals %s for %d.", HEALEDSELFSELF, and both
-- critical variants -- and the CHAT_MSG_SPELL family is already a working
-- combat-text source here (knowledge.json /
-- castbar.target_chatlog_fallback_unverified). Every template is still read
-- through U.G and compiled defensively: a missing or reworded one drops that
-- one pattern instead of erroring, and a client that never emits the message
-- simply never learns an amount and never predicts.
--
-- A tooltip read was the alternative and is worse: a Vanilla spell tooltip
-- states the base heal without the player's +healing gear or talents, so it
-- would under-predict for exactly the geared healer this feature is for.
-- Learning from the log costs one cast per rank and is then correct.
--
-- Amounts are keyed by spell *and rank* and persist in the module's own
-- settings table (one level of nesting, string keys, number values -- the shape
-- knowledge.json / config.module_settings_dropped_nested_tables establishes as
-- the supported one). They are flagged stale, not deleted, when gear or talents
-- change: the next observed heal of that rank replaces the old figure rather
-- than the bar going blank while the player re-learns their whole spellbook.
--
-- ---------------------------------------------------------------------------
-- Where the target comes from
-- ---------------------------------------------------------------------------
--
-- SPELLCAST_START carries the spell name and the cast time in milliseconds
-- (knowledge.json / castbar.player_events_partial) and nothing else, so the
-- target is resolved the way modules/hots.lua resolves it and the way pfUI
-- does: the current target if it can be assisted, otherwise the player. The
-- rank comes from the action slot that was pressed, through core/init.lua's
-- action-press fan-out and U.ActionSlotSpellName -- this client has no
-- GetActionInfo and no global hooksecurefunc to place on CastSpell, so a cast
-- that does not come from an unrealUI action button has no rank and is keyed on
-- its name alone.
--
-- ---------------------------------------------------------------------------
-- What is not taken from pfUI, and why
-- ---------------------------------------------------------------------------
--
--   * The HealComm/CTRA addon channel, in both directions. Other healers'
--     incoming heals would need CHAT_MSG_ADDON, which has no capture in
--     events.json and no entry in the client documentation, and SendAddonMessage
--     is DOCUMENTED_NOT_RUNTIME_VERIFIED. Rather than ship a network protocol
--     against an unverified transport, this predicts the player's own heals
--     only -- which is the case that decides whether *this* cast overheals --
--     and the settings hint says so plainly.
--   * Resurrection tracking. It is a separate indicator, not health prediction.
--   * The Prayer of Healing fan-out. It needs the spell's localized name to
--     recognise it; a group heal here predicts on the resolved target only,
--     which under-reports rather than mispredicting.
--   * Its cast hooks. There is no global hooksecurefunc on this client
--     (knowledge.json / hooks.no_global_hooksecurefunc).
--
-- ---------------------------------------------------------------------------

local U = UnrealUI
local M = U.media

local HP = U.RegisterModule("healpredict")

local CONFIG = "healpredict"

local defaults = {
  enabled = true,
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

-- The learned store: "spell@rank" -> heal in hit points. A nested table on
-- purpose; core/config.lua sanitizes exactly one level and caps it at 200
-- entries, which this module stays inside deliberately.
--
-- Deliberately NOT seeded through `defaults`. U.ModuleConfig copies a default
-- value into the profile by reference, so a table listed there would be the
-- *same* table in every profile that ever asked for it -- one character's
-- learned heals would appear under another's profile and the module's own
-- defaults table would accumulate them for the session. Created here instead,
-- so each profile gets its own.
local function Amounts()
  local cfg = Config()
  if type(cfg.amounts) ~= "table" then cfg.amounts = {} end
  return cfg.amounts
end

function U.GetHealPredictSetting(key)
  local value = Config()[key]
  if value == nil then return defaults[key] end
  return value
end

local Apply

function U.SetHealPredictSetting(key, value)
  if key == "enabled" then
    Config().enabled = value and true or false
    if Apply then Apply() end
  end
end

local function Enabled()
  return U.GetHealPredictSetting("enabled") and true or false
end

-- ---------------------------------------------------------------------------
-- Client access
--
-- Same shape as modules/hots.lua: a global that is missing or differently
-- shaped on this client returns nil rather than erroring.
-- ---------------------------------------------------------------------------
local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end

  local ok, value = pcall(fn, a, b)
  if not ok then return nil end
  return value
end

local function Now()
  local time = U.G("GetTime")
  if type(time) ~= "function" then return 0 end
  local ok, value = pcall(time)
  if ok and tonumber(value) then return value end
  return 0
end

-- ---------------------------------------------------------------------------
-- Combat-text templates
--
-- Compiled once, from whichever of the four globals this client actually has.
-- The crit templates are compiled first and matched first: "Your %s critically
-- heals %s for %d." also satisfies the non-crit pattern, with "Foo critically"
-- captured as the spell, so a first-match-wins walk has to see the longer form
-- first or every crit would poison the cache under a wrong key.
-- ---------------------------------------------------------------------------
local TEMPLATES = {
  { global = "HEALEDCRITSELFOTHER", roles = { "spell", "target", "amount" },
    crit = true },
  { global = "HEALEDCRITSELFSELF",  roles = { "spell", "amount" },
    crit = true },
  { global = "HEALEDSELFOTHER",     roles = { "spell", "target", "amount" } },
  { global = "HEALEDSELFSELF",      roles = { "spell", "amount" } },
}

local patterns = nil

local function EscapeLiteral(text)
  local escaped = string.gsub(text, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return escaped
end

-- Turns one format template into a Lua pattern plus the meaning of each of its
-- captures. Positional forms ("%2$s") are honoured: the capture stays in the
-- order the sentence reads, but its *role* comes from the argument number, so a
-- locale that puts the target before the spell still resolves correctly.
local function CompileTemplate(template, roles)
  if type(template) ~= "string" or template == "" then return nil end

  local pattern, slots = "", {}
  local index, argCount = 1, 0
  local length = string.len(template)

  while index <= length do
    local from, to, digits, kind =
      string.find(template, "%%(%d*)%$?([sd])", index)
    if not from then break end

    pattern = pattern .. EscapeLiteral(string.sub(template, index, from - 1))

    argCount = argCount + 1
    local role = roles[tonumber(digits) or argCount]
    if not role then return nil end
    table.insert(slots, role)

    if kind == "d" then
      pattern = pattern .. "(%d+)"
    else
      pattern = pattern .. "(.+)"
    end

    index = to + 1
  end

  -- A template that lost a specifier would match far too much; two captures is
  -- the minimum any of the four heal sentences can honestly have.
  if table.getn(slots) < 2 then return nil end

  pattern = pattern .. EscapeLiteral(string.sub(template, index))
  return { pattern = "^" .. pattern .. "$", slots = slots }
end

local function BuildPatterns()
  patterns = {}

  local i
  for i = 1, table.getn(TEMPLATES) do
    local spec = TEMPLATES[i]
    local compiled = CompileTemplate(U.G(spec.global), spec.roles)
    if compiled then
      compiled.crit = spec.crit and true or false
      compiled.source = spec.global
      table.insert(patterns, compiled)
    end
  end
end

-- Returns spell, target, amount, crit for a message that is one of the player's
-- own heals, or nil for anything else. Target is nil for the "heals you" forms;
-- the caller substitutes the player.
local function MatchHeal(message)
  if type(message) ~= "string" then return nil end
  if not patterns then BuildPatterns() end

  local i
  for i = 1, table.getn(patterns) do
    local entry = patterns[i]
    local _, _, c1, c2, c3 = string.find(message, entry.pattern)
    if c1 then
      local captures = { c1, c2, c3 }
      local spell, target, amount = nil, nil, nil

      local n
      for n = 1, table.getn(entry.slots) do
        local role = entry.slots[n]
        if role == "spell" then
          spell = captures[n]
        elseif role == "target" then
          target = captures[n]
        elseif role == "amount" then
          amount = tonumber(captures[n])
        end
      end

      if spell and amount then return spell, target, amount, entry.crit end
      return nil
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- Learned amounts
-- ---------------------------------------------------------------------------

-- Session-only. Staleness says "the next real observation wins outright"; it is
-- worthless after a reload, when the gear and talents it was reacting to have
-- already been read fresh.
local stale = {}

-- Under core/config.lua's 200-entry cap for a nested settings table, with room
-- left so a long session cannot push the store to the point where the sanitizer
-- starts discarding entries arbitrarily on the next load.
local MAX_AMOUNTS = 180

local function CountAmounts()
  local count, key = 0, nil
  for key in pairs(Amounts()) do count = count + 1 end
  return count
end

-- A crit is worth 1.5x in Vanilla, so it is recorded at two thirds and left
-- flagged: it is an estimate standing in until a normal heal of that rank is
-- seen. Otherwise the best non-crit heal observed wins, which is what tracks a
-- +healing upgrade upwards without waiting for a stale flag.
local function Learn(key, amount, crit)
  if type(key) ~= "string" or key == "" then return end
  amount = tonumber(amount)
  if not amount or amount <= 0 then return end

  local store = Amounts()
  local current = tonumber(store[key])

  if current == nil then
    if CountAmounts() >= MAX_AMOUNTS then return end
    store[key] = crit and math.floor(amount * 2 / 3) or amount
    stale[key] = crit and true or nil
  elseif stale[key] then
    store[key] = crit and math.floor(amount * 2 / 3) or amount
    stale[key] = crit and true or nil
  elseif not crit and current < amount then
    store[key] = amount
    stale[key] = nil
  end
end

local function FlagStale()
  local key, value
  for key, value in pairs(Amounts()) do
    if type(value) == "number" then stale[key] = true end
  end
end

-- ---------------------------------------------------------------------------
-- Prediction store
--
-- One caster only -- the player -- so a target carries at most one pending
-- heal and the whole store is cleared whenever that cast ends. `active` keeps
-- the read path free for everyone who is not currently healing.
-- ---------------------------------------------------------------------------
local heals = {}
local active = 0

-- ---------------------------------------------------------------------------
-- Preview
--
-- "/uui heal test" paints a synthetic prediction on every unit frame for a few
-- seconds. It exists because the real thing cannot be summoned on demand: the
-- first segment needs a heal of that rank to have already been observed landing
-- once, and the second has no source on this client at all, so without this
-- there is no way to look at the finished appearance -- or to tell "the segments
-- are not drawing" apart from "no heal is in flight".
--
-- Fractions of maximum health, in ElvUI's own proportions: a mid-sized heal of
-- yours followed by a smaller one from someone else.
-- ---------------------------------------------------------------------------
local preview = nil        -- expiry timestamp, or nil
local PREVIEW_MINE = 0.15
local PREVIEW_OTHERS = 0.10

-- Nothing can be drawn past a full bar -- that is ElvUI's maxOverflow of 0 and
-- the correct behaviour -- but a party standing around at full health is
-- exactly when someone wants to look at the segments, and there they would
-- correctly draw nothing at all. So the preview also holds every bar at a
-- wounded value, and modules/unitframes.lua puts the real one back when it ends.
local PREVIEW_FILL = 0.55

function U.HealPredictPreviewFill()
  if preview and preview > Now() then return PREVIEW_FILL end
  return nil
end

local function ClearHeals()
  if active == 0 then return false end
  local name
  for name in pairs(heals) do heals[name] = nil end
  active = 0
  return true
end

local function OpenHeal(target, amount, seconds)
  if type(target) ~= "string" or target == "" then return false end
  amount = tonumber(amount)
  seconds = tonumber(seconds)
  if not amount or amount <= 0 then return false end
  if not seconds or seconds <= 0 then return false end

  if not heals[target] then active = active + 1 end
  heals[target] = { amount = amount, expires = Now() + seconds }
  return true
end

-- The safety net for a cast whose end this module never sees. SPELLCAST_STOP is
-- the normal path and fires well before this, but the compact evidence has no
-- capture for SPELLCAST_FAILED or SPELLCAST_INTERRUPTED on this client, so a
-- prediction must be able to time itself out rather than sticking to a bar.
local function ExpireHeals()
  if active == 0 then return false end

  local now, changed, name, entry = Now(), false, nil, nil
  for name, entry in pairs(heals) do
    if entry.expires <= now then
      heals[name] = nil
      active = active - 1
      changed = true
    end
  end
  return changed
end

-- The numbers modules/unitframes.lua paints, in hit points: the player's own
-- incoming heal and everyone else's, split the way ElvUI splits them --
--
--   myIncomingHeal    = UnitGetIncomingHeals(unit, UnitName("player"))
--   otherIncomingHeal = UnitGetIncomingHeals(unit) - myIncomingHeal
--
-- because they are drawn as two chained segments in two colours and the split
-- is what makes the first one actionable: it is the part you can still decide
-- not to cast.
--
-- The second return is always zero on this client and the split is structural,
-- not measured. There is no UnitGetIncomingHeals to subtract from
-- (healpredict.no_incoming_heal_api), and the one channel that would carry
-- another healer's pending cast is unverified here
-- (healpredict.healcomm_channel_unverified) -- the combat log announces another
-- player's cast start but never who it is aimed at, which is the whole reason
-- HealComm exists. Keeping the shape means the second segment lights up the day
-- that channel is confirmed, without the renderer or the unit frames changing.
--
-- Both are zero for a unit with nothing incoming, for a dead unit (a heal
-- cannot land on a corpse, and pfUI suppresses it the same way) and for
-- everyone when the feature is off.
function U.UnitIncomingHeal(unit)
  if not Enabled() then return 0, 0 end

  -- Preview overrides the real store while it runs. Fractions of maximum
  -- health rather than fixed numbers, so the two segments occupy the same share
  -- of every bar whatever the unit's health pool is.
  if preview and preview > Now() then
    if not Call("UnitExists", unit) then return 0, 0 end
    if Call("UnitIsDeadOrGhost", unit) then return 0, 0 end
    local maximum = tonumber(Call("UnitHealthMax", unit)) or 0
    if maximum <= 0 then return 0, 0 end
    return maximum * PREVIEW_MINE, maximum * PREVIEW_OTHERS
  end

  if active == 0 then return 0, 0 end

  local name = Call("UnitName", unit)
  if type(name) ~= "string" then return 0, 0 end

  local entry = heals[name]
  if not entry then return 0, 0 end
  if entry.expires <= Now() then return 0, 0 end
  if Call("UnitIsDeadOrGhost", unit) then return 0, 0 end

  return entry.amount, 0
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------

-- The last action slot pressed, kept only long enough for the SPELLCAST_START
-- that follows it. Its rank is the only rank this client will give up.
local pressed = nil
local slotSpells = {}

-- The last spell this module saw start, kept until the next one. The combat
-- text arrives after the cast has already ended, so the key it credits cannot
-- come from a pending cast -- this is pfUI's spell_queue, narrowed to what is
-- actually needed.
local lastCast = nil

local function CastTargetName()
  if Call("UnitExists", "target") then
    if Call("UnitCanAssist", "player", "target") then
      local name = Call("UnitName", "target")
      if type(name) == "string" and name ~= "" then return name end
    end
  end

  local name = Call("UnitName", "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local function SpellKey(name, rank)
  if type(rank) ~= "string" then rank = "" end
  -- "@" rather than "|": the key is a settings-table key, and a pipe is the
  -- client's colour-escape character in anything that ever reaches a label.
  return name .. "@" .. rank
end

-- Called through core/init.lua's action-press fan-out, before UseAction runs.
local function OnActionUsed(slot)
  if not Enabled() then return end

  slot = tonumber(slot)
  if not slot then return end

  local entry = slotSpells[slot]
  if entry == nil then
    local name, rank = U.ActionSlotSpellName(slot)
    if type(name) == "string" and name ~= "" then
      entry = { name = name, rank = type(rank) == "string" and rank or "" }
    else
      entry = false
    end
    slotSpells[slot] = entry
  end

  if entry then pressed = { name = entry.name, rank = entry.rank } end
end

-- SPELLCAST_START(name, castTimeMs). An instant heal never reaches here and
-- never needs to: it lands in the same frame it is cast, so there is no flight
-- time to draw. Only a cast with real duration opens a prediction.
local function OnCastStart(name, castTime)
  if not Enabled() then return end
  if type(name) ~= "string" or name == "" then return end

  local rank = ""
  if pressed and pressed.name == name then rank = pressed.rank end
  pressed = nil

  local key = SpellKey(name, rank)
  lastCast = { name = name, key = key }

  local amount = tonumber(Amounts()[key])
  -- A rank this client never told us about falls back to the same spell learned
  -- without a rank, and vice versa, so a cast from the spellbook still predicts
  -- once the action bar has taught the amount.
  if not amount and rank ~= "" then
    amount = tonumber(Amounts()[SpellKey(name, "")])
  end
  if not amount then return end

  local seconds = tonumber(castTime)
  if not seconds or seconds <= 0 then return end
  seconds = seconds / 1000

  local target = CastTargetName()
  if not target then return end

  if OpenHeal(target, amount, seconds) then Apply() end
end

local function OnCastEnd()
  if ClearHeals() then Apply() end
end

-- SPELLCAST_DELAYED(pushbackMs). knowledge.json /
-- castbar.pushback_delay_event_unconfirmed: this event has never been captured
-- on this client, so it is registered and handled exactly as modules/castbar.lua
-- does -- if it never fires, the prediction simply ends at its original time.
local function OnCastDelayed(delay)
  if active == 0 then return end

  delay = tonumber(delay)
  if not delay or delay <= 0 then return end
  delay = delay / 1000

  local name, entry
  for name, entry in pairs(heals) do
    entry.expires = entry.expires + delay
  end
end

local function OnHealMessage(message)
  local spell, target, amount, crit = MatchHeal(message)
  if not spell then return end

  -- Only the spell this module watched start is credited. Anything else in the
  -- self-buff channel -- a trinket proc, a bandage, a heal the player did not
  -- cast through a tracked path -- would otherwise be filed under whatever key
  -- happened to be last.
  if lastCast and lastCast.name == spell then
    Learn(lastCast.key, amount, crit)
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
--
-- modules/unitframes.lua owns the frames and does the painting; this only tells
-- it that the numbers moved. Optional by design: the module is useful to
-- diagnostics even on a build where the unit frames did not load.
-- ---------------------------------------------------------------------------
function Apply()
  if type(U.ApplyHealPrediction) == "function" then
    pcall(U.ApplyHealPrediction)
  end
end

-- Starts (or restarts) the preview. Returns the seconds it will run for so the
-- command can say so.
function U.HealPredictTest(seconds)
  seconds = tonumber(seconds) or 10
  if seconds < 1 then seconds = 1 end
  if seconds > 60 then seconds = 60 end

  preview = Now() + seconds
  Apply()
  return seconds
end

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- The one thing the compact evidence cannot answer is whether this client emits
-- the self-heal combat text at all. This says so directly: which templates
-- compiled, and what has actually been learned from them. Templates present but
-- nothing learned after a few heals means the message is not arriving, which no
-- amount of reading this file would have shown.
-- ---------------------------------------------------------------------------
local function ColorText(color)
  if type(color) ~= "table" then return "missing" end
  return string.format("r=%.2f g=%.2f b=%.2f a=%.2f",
                       tonumber(color[1]) or 0, tonumber(color[2]) or 0,
                       tonumber(color[3]) or 0, tonumber(color[4]) or 0)
end

function U.HealPredictDebugDump()
  U.Print("unrealUI incoming heals")
  U.Print("  enabled: " .. tostring(Enabled()))

  -- What is actually loaded, not what the source says: a stale core/media.lua
  -- or a theme that re-tinted the token is otherwise indistinguishable from the
  -- segments not drawing at all.
  U.Print("  colours: mine   " .. ColorText(M.color.healPredictionMine))
  U.Print("           others " .. ColorText(M.color.healPredictionOthers))
  if preview then
    U.Print("  preview: running for " ..
            string.format("%.1f", preview - Now()) .. "s")
  end

  if not patterns then BuildPatterns() end
  local i
  U.Print("  templates:")
  for i = 1, table.getn(TEMPLATES) do
    local spec = TEMPLATES[i]
    local raw = U.G(spec.global)
    local ok = false
    local n
    for n = 1, table.getn(patterns) do
      if patterns[n].source == spec.global then ok = true end
    end
    U.Print("    " .. spec.global .. ": " ..
            (type(raw) == "string" and "\"" .. raw .. "\"" or "missing") ..
            (ok and "  compiled" or "  not compiled"))
  end

  local store, key, value = Amounts(), nil, nil
  local count = 0
  U.Print("  learned amounts:")
  for key, value in pairs(store) do
    count = count + 1
    U.Print("    " .. tostring(key) .. " = " .. tostring(value) ..
            (stale[key] and "  (stale)" or ""))
  end
  if count == 0 then
    U.Print("    none yet - cast a heal, then run this again")
  end

  if lastCast then
    U.Print("  last cast: " .. lastCast.name .. "  key=" .. lastCast.key)
  else
    U.Print("  last cast: none")
  end

  local now = Now()
  U.Print("  live predictions (yours): " .. tostring(active))
  local name, entry
  for name, entry in pairs(heals) do
    U.Print("    " .. tostring(name) .. ": " .. tostring(entry.amount) ..
            " for " .. string.format("%.1f", entry.expires - now) .. "s")
  end
  -- Named so the second, darker green segment never reads as broken: it has no
  -- source on this client, it is not failing to find one.
  U.Print("  live predictions (other players): none - no channel on this " ..
          "client, see healpredict.healcomm_channel_unverified")
end

-- ---------------------------------------------------------------------------
-- Settings
--
-- One checkbox. There is nothing else to configure that is not a lie: the
-- colour is a shared media token, the amount is measured rather than chosen,
-- and pfUI's overheal-overshoot option has no meaning on a bar that cannot draw
-- past its own end.
--
-- `y` is where the caller wants this section's heading, so the page above it can
-- move without this file knowing what sits there.
-- ---------------------------------------------------------------------------
function U.BuildHealPredictSettings(parent, y, width)
  y = y or -4
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("HEALPREDICT_HEADER"),
    width = width or 484,
    y = y,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsHealPredictEnabled",
    text = U.L("HEALPREDICT_ENABLED"),
    textWidth = 232,
    value = U.GetHealPredictSetting("enabled"),
    onChange = function(value) U.SetHealPredictSetting("enabled", value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 30)
  table.insert(widgets, enable)

  -- Says outright that this is your own casts and that a spell has to be seen
  -- land once, so a bar that stays empty reads as a known limit rather than a
  -- bug -- the same contract the HoT and aura hints keep.
  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = width or 484,
  })
  if hint then
    U.AnchorSettingsDescription(hint, enable.box)
    hint:SetText(U.L("HEALPREDICT_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    enable.SetValue(U.GetHealPredictSetting("enabled"))
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function HP:OnEnable()
  BuildPatterns()

  U.RegisterActionUsed(OnActionUsed)

  U.RegisterEvent("SPELLCAST_START", function(event, name, castTime)
    OnCastStart(name, castTime)
  end)
  U.RegisterEvent("SPELLCAST_STOP", function() OnCastEnd() end)
  U.RegisterEvent("SPELLCAST_DELAYED", function(event, delay)
    OnCastDelayed(delay)
  end)

  local cancelled = { "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED" }
  local i
  for i = 1, table.getn(cancelled) do
    U.RegisterEvent(cancelled[i], function() OnCastEnd() end)
  end

  -- Where "Your X heals Y for N." arrives. Both self channels are registered
  -- because only the direct-heal one is documented for this text in Vanilla and
  -- neither has a capture here; the pattern match is what decides whether a
  -- message counts, so registering the periodic channel too costs nothing and
  -- covers a client that routes it differently.
  local channels = {
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
  }
  for i = 1, table.getn(channels) do
    U.RegisterEvent(channels[i], function(event, message)
      OnHealMessage(message)
    end)
  end

  -- A learned amount is only true for the gear and talents it was measured
  -- with. These do not clear it -- that would blank the bar for a whole
  -- re-learning period after every trinket swap -- they mark it replaceable.
  local invalidate = {
    "UNIT_INVENTORY_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "SPELLS_CHANGED",
  }
  for i = 1, table.getn(invalidate) do
    U.RegisterEvent(invalidate[i], function() FlagStale() end)
  end

  -- An action slot's spell can change under a cached name.
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", function() slotSpells = {} end)

  -- The templates are read once the client has finished loading its strings,
  -- and a zone change is a cheap place to notice a store this profile has never
  -- had.
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    BuildPatterns()
    Apply()
  end)

  -- Only the timeout net; every normal end of a cast is an event. Nothing here
  -- touches a client API while no heal is in flight and no preview is running.
  U.RegisterUpdate("healpredict.expire", 0.1, function()
    local changed = ExpireHeals()
    if preview then
      if preview <= Now() then
        preview = nil
      end
      -- Held every tick while it runs, not just at its end: a real health event
      -- in the middle would otherwise refresh the bar back to its true value
      -- and the demo would vanish part way through.
      changed = true
    end
    if changed then Apply() end
  end)
end
