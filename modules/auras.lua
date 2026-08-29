-- unrealUI :: modules/auras.lua
--
-- Buff and debuff icons around the player, target and party unit frames, each
-- with the radial wipe and countdown number the action bar uses, plus the
-- "Unit Frames" settings page that filters what they show.
--
-- Party members use two compact rows beside the frame: debuffs above buffs so
-- the actionable row always has the stable, more prominent position. Raid
-- auras, weapon enchants, and pfUI's whole buff/debuff module framework are not
-- reproduced here. The player frame carries both rows, laid out exactly like
-- the target frame's: debuffs against the frame edge, buffs stacked outside
-- them, so your own auras are readable without having to target yourself.
-- Hovering an icon shows the shared client GameTooltip (SetUnitBuff /
-- SetUnitDebuff), the same native widget xpbar.lua already owns for the rest
-- tooltip -- not a second private tooltip frame.
--
-- ---------------------------------------------------------------------------
-- The measured contract this file is built on
-- ---------------------------------------------------------------------------
--
-- knowledge.json / auras.unitbuff_unitdebuff_contract_unverified (PARTIAL,
-- RUNTIME_MEASURED, probe auras.* v1.10.0): on this client
--
--     UnitDebuff(unit, index) -> texture, count, debuffType
--
-- and nothing else. Three values, measured with a warlock Immolate live on the
-- target: texture="/Game/Interface/Icons/Spell_Fire_Immolation_TEX", count=1,
-- debuffType="Magic". There is no name, no duration, no timeLeft and no caster
-- return on this runtime -- that is true Vanilla 1.12 shape, not the extended
-- tuple pfUI's own code reads, which comes from its separate libdebuff
-- GameTooltip wrapper rather than from raw UnitDebuff. UnitBuff is the same
-- shape minus the dispel type.
--
-- Two consequences drive the design:
--
--   * Names come from a tooltip, not from the aura call. knowledge.json /
--     auras.no_native_debuff_expiry_time measured a GameTooltip-template
--     scanner armed with SetUnitDebuff("target", 1) returning TextLeft1
--     "Immolate" and TextRight1 "Magic" against a live DoT, so line 1 is the
--     name and the scan is the only way to get one.
--   * Timers come from one of two places, and which one depends entirely on
--     whose aura it is.
--
-- Timers, native path -- the player's own auras (the player row, and the target
-- row whenever the target is the player). GetPlayerBuff + GetPlayerBuffTimeLeft
-- is a real client-reported remaining time, and it is the only one that exists
-- anywhere on this runtime. See ReadPlayerAura for exactly what the probe
-- measured and what it could not.
--
-- Timers, reconstructed path -- everyone else. auras.no_native_debuff_expiry_time
-- is explicit that a target aura's expiry cannot be read here at all: the
-- tooltip has exactly two lines and carries no time. Its solution text said a
-- target timer "would require reproducing pfUI's whole duration-table +
-- combat-log-timestamp reconstruction ... out of scope unless explicitly
-- requested". It was explicitly requested. core/auradata.lua holds the duration
-- table; this file supplies the start stamp by watching the aura appear.
--
-- What the reconstructed path costs, stated plainly so its readout is not
-- mistaken for a client value:
--
--   * An aura already running when it is first seen -- anything on a mob you
--     have just targeted -- is stamped from that moment, so it reads as freshly
--     applied. pfUI has the same behaviour for the same reason.
--   * An aura with no entry in the duration table gets no wipe and no number.
--     The table is debuff-weighted, so a fair number of buffs land here. This
--     is why the native path matters: your own buffs are exactly the ones the
--     table tends to miss, and they no longer depend on it.
--   * Rank is not recoverable for another unit's aura, so the table's max-rank
--     duration is used. pfUI's display path passes rank as nil for the same
--     reason.
--
-- "/uui aura" prints which path each row took and, per aura, whether the name,
-- the table entry or the client time is the thing that came back empty.
--
-- The empty-index shape was measured too: an unused slot returns nil as its
-- first value (with 0 as the second), and the first probe run -- taken with no
-- debuff live -- returned nothing at all across 24 indices, confirming these
-- are read live per call and never latched from the aura event.
--
-- Other compatibility notes that shaped this file:
--
--   * events.json: UNIT_AURA is observed on this client, PLAYER_AURAS_CHANGED
--     was accepted but never seen firing. UNIT_AURA is therefore an
--     accelerator, and the shared polling tick is the mechanism -- the same
--     split modules/unitframes.lua uses for target-of-target.
--   * knowledge.json / scripts.child_onupdate_unreliable: no frame here owns an
--     OnUpdate. Refreshes run on U.RegisterUpdate.
--   * knowledge.json / cooldown.model_swipe_not_rendered (BROKEN): the native
--     Model/CooldownFrameTemplate swipe draws nothing here, which is why the
--     radial is U.CreateRadialWipe from core/style.lua -- the same hand-drawn
--     wipe the action buttons use, per the request that these icons match them.
--   * Icons accept hover only to populate the shared GameTooltip; they have no
--     click handler. Party icons sit wholly outside the unit button, so the
--     existing targeting/menu surface remains unchanged. The scanner below is
--     never shown and never owns the shared GameTooltip; its
--     create/SetOwner/populate/read sequence is the one the probe measured.
--   * knowledge.json / config.savedvariables_backslash_corruption: only
--     numbers and booleans are persisted. Neither icon paths nor aura names nor
--     timer stamps are stored -- every one of them is re-derived at runtime.

local U = UnrealUI
local M = U.media

local A = U.RegisterModule("auras")

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local CONFIG = "auras"

local defaults = {
  -- Where the player's own auras are drawn. showOnPlayerFrame gates this
  -- module's two player rows as a unit, so switching the display off and back
  -- on keeps whatever buff/debuff choice was made below it. The other half of
  -- the pair -- the client's own display near the minimap -- is not this
  -- module's frames and is stored by modules/buffframe.lua instead.
  showOnPlayerFrame = true,
  playerEnabled     = true,
  playerBuffEnabled = true,
  targetEnabled     = true,
  targetBuffEnabled = true,
  partyEnabled      = true,
  partyBuffEnabled  = true,
  showTimers        = true,
  belowFrame        = false,
  size              = 24,
  perRow            = 8,
  maxIcons          = 16,
  -- Buffs get a tighter cap than debuffs: a raid boss can carry a dozen of
  -- them and they would push the debuffs -- the actionable half -- off screen.
  maxBuffs          = 8,
  spacing           = 2,
  -- Filters, keyed by the dispel school the client reports. "other" covers a
  -- nil debuffType, which is what physical effects (Rend, Sunder Armor,
  -- stuns) come back as. Buffs are unfiltered: the client reports no
  -- classification for them at all.
  showMagic         = true,
  showCurse         = true,
  showPoison        = true,
  showDisease       = true,
  showOther         = true,
}

-- U.ModuleConfig only fills a key in when its stored type differs from the
-- default's, so a numeric default that changes value (size 20 -> 24) never
-- reaches an account that already saved the old one. `size` has no settings-
-- page control, so nothing could have set it on purpose; a stale persisted 20
-- is corrected once and the flag stops this from re-running (and from ever
-- fighting an explicit change, if `size` gets a control later).
local function Config()
  local settings = U.ModuleConfig(CONFIG, defaults)
  if not settings.migratedSize24 then
    settings.migratedSize24 = true
    if settings.size == 20 then settings.size = defaults.size end
  end
  return settings
end

function U.GetAuraSetting(key)
  local value = Config()[key]
  if value == nil then return defaults[key] end
  return value
end

-- ---------------------------------------------------------------------------
-- Debuff colours
--
-- The border carries the dispel school, which is the only classification the
-- client actually reports. These are the stock Vanilla DebuffTypeColor values;
-- they are hardcoded rather than read from the global because query_compat.py
-- has no record of DebuffTypeColor existing on this client, and a missing
-- global would leave every icon unbordered.
-- ---------------------------------------------------------------------------
local TYPE_COLOR = {
  Magic   = { 0.20, 0.60, 1.00, 1.00 },
  Curse   = { 0.60, 0.00, 1.00, 1.00 },
  Poison  = { 0.00, 0.60, 0.00, 1.00 },
  Disease = { 0.60, 0.40, 0.00, 1.00 },
}

-- Physical/unclassified effects. Kept distinct from M.color.border so an
-- unfiltered row still reads as "these are debuffs" at a glance.
local OTHER_COLOR = { 0.70, 0.15, 0.15, 1.00 }

-- Buffs carry no dispel school here, so they take the shared chrome outline.
-- That is also what separates the two rows visually: coloured edges are
-- debuffs, neutral edges are buffs.
local BUFF_COLOR = M.color.border

local FILTER_KEY = {
  Magic   = "showMagic",
  Curse   = "showCurse",
  Poison  = "showPoison",
  Disease = "showDisease",
}

local function TypeColor(debuffType)
  return TYPE_COLOR[debuffType] or OTHER_COLOR
end

local function PassesFilter(debuffType)
  local key = FILTER_KEY[debuffType] or "showOther"
  return U.GetAuraSetting(key) and true or false
end

-- ---------------------------------------------------------------------------
-- API access
--
-- Same defensive shape as modules/unitframes.lua: resolved once by name,
-- pcall'd on every call, and every value coerced. An unexpected return degrades
-- to "no aura here" instead of erroring.
--
-- The resolve is memoised because these calls run across both primary and
-- party rows; an uncached U.G per read is one extra pcall per index per pass.
-- ---------------------------------------------------------------------------
local resolved = {}

local function Fn(name)
  local cached = resolved[name]
  if cached == nil then
    local value = U.G(name)
    cached = (type(value) == "function") and value or false
    resolved[name] = cached
  end
  return cached or nil
end

local function Call(name, a, b)
  local fn = Fn(name)
  if not fn then return nil end
  local ok, v1, v2, v3 = pcall(fn, a, b)
  if not ok then return nil end
  return v1, v2, v3
end

local function Now()
  return tonumber(Call("GetTime")) or 0
end

local function ReadDebuff(unit, index)
  local texture, count, debuffType = Call("UnitDebuff", unit, index)
  if type(texture) ~= "string" or texture == "" then return nil end

  return texture, tonumber(count) or 0,
         (type(debuffType) == "string" and debuffType ~= "") and debuffType or nil
end

-- UnitBuff is the same call one classification short: the client reports no
-- dispel school for a helpful aura, so the third value is never read.
local function ReadBuff(unit, index)
  local texture, count = Call("UnitBuff", unit, index)
  if type(texture) ~= "string" or texture == "" then return nil end

  return texture, tonumber(count) or 0, nil
end

local function ReadAura(unit, index, harmful)
  if harmful then return ReadDebuff(unit, index) end
  return ReadBuff(unit, index)
end

-- ---------------------------------------------------------------------------
-- The player's own auras, read natively
--
-- The one thing auras.no_native_debuff_expiry_time left open. Probe
-- auras.player_getplayerbuff_helpful_timers.v1 / _harmful_ (probeVersion
-- 1.12.0) measured, on this client:
--
--   * GetPlayerBuff, GetPlayerBuffTimeLeft, GetPlayerBuffTexture,
--     GetPlayerBuffDispelType and GetPlayerBuffApplications all exist and are
--     of type "function";
--   * GetPlayerBuff(index, filter) returns two numbers, and an empty slot
--     answers -1 -- captured at every index in both runs, which is what a run
--     with no aura on the player is supposed to look like;
--   * PLAYER_BUFF_START_ID is nil here, so the walk is 0-based. The probe used
--     base -1 with a 1-based loop, which is the same 0..n-1 sequence.
--
-- What the probe could NOT confirm is a live remaining time, because nothing
-- was up on the player when it ran. So this path is BEHAVIOR_PARTIALLY_TESTED:
-- every call is guarded, and a nil or zero time simply produces no timer,
-- exactly as an aura missing from the duration table does.
--
-- It matters because it is the only *client-reported* expiry available
-- anywhere on this runtime. Where it applies -- the player row, and the target
-- row whenever the target is the player -- the countdown is the client's own
-- number rather than a reconstruction.
-- ---------------------------------------------------------------------------
local playerBuffBase = nil

local function PlayerBuffBase()
  if playerBuffBase == nil then
    playerBuffBase = tonumber(U.G("PLAYER_BUFF_START_ID")) or 0
  end
  return playerBuffBase
end

-- Returns the same leading tuple as ReadAura, plus the client's remaining time.
local function ReadPlayerAura(index, harmful)
  local get = Fn("GetPlayerBuff")
  if not get then return nil end

  local ok, buffIndex = pcall(get, PlayerBuffBase() + index - 1,
                              harmful and "HARMFUL" or "HELPFUL")
  buffIndex = ok and tonumber(buffIndex) or nil
  if not buffIndex or buffIndex <= -1 then return nil end

  local texture = Call("GetPlayerBuffTexture", buffIndex)
  if type(texture) ~= "string" or texture == "" then return nil end

  local dispel = Call("GetPlayerBuffDispelType", buffIndex)
  local timeLeft = tonumber(Call("GetPlayerBuffTimeLeft", buffIndex)) or 0

  return texture,
         tonumber(Call("GetPlayerBuffApplications", buffIndex)) or 0,
         (type(dispel) == "string" and dispel ~= "") and dispel or nil,
         timeLeft > 0 and timeLeft or nil
end

-- "player" is the player without asking; a target can be too. UnitIsUnit is
-- documented to match on the token string before any object lookup, so the
-- self-target case costs one call per row per tick.
local function IsPlayerUnit(unit)
  if unit == "player" then return true end

  local fn = Fn("UnitIsUnit")
  if not fn then return false end

  local ok, same = pcall(fn, unit, "player")
  return (ok and same and same ~= 0) and true or false
end

-- ---------------------------------------------------------------------------
-- Name scanner
--
-- The only way to learn what an aura is on this client. A private
-- GameTooltip-template frame is armed with SetUnitBuff/SetUnitDebuff and line 1
-- is read back off its own fontstring global -- exactly the sequence probe
-- auras.target_debuff_tooltip_name.v1 measured, including the single SetOwner
-- with ANCHOR_NONE that the probe set once and reused across four reads.
--
-- It is never shown, never anchored to the cursor and never the shared
-- GameTooltip, so nothing here can disturb the game's own tooltip.
-- ---------------------------------------------------------------------------
local SCANNER_NAME = "UnrealUIAuraScanner"

local scanner = nil
local scannerBuilt = false

local function Scanner()
  if scannerBuilt then return scanner end
  scannerBuilt = true

  local ok, frame = pcall(CreateFrame, "GameTooltip", SCANNER_NAME, UIParent,
                          "GameTooltipTemplate")
  if not ok or not frame then
    U.Debug("aura name scanner unavailable; timers will be inactive")
    return nil
  end

  pcall(frame.SetOwner, frame, UIParent, "ANCHOR_NONE")
  scanner = frame
  return scanner
end

local function ScanName(unit, index, harmful)
  local tip = Scanner()
  if not tip then return nil end

  local setter = harmful and tip.SetUnitDebuff or tip.SetUnitBuff
  if type(setter) ~= "function" then return nil end
  if not pcall(setter, tip, unit, index) then return nil end

  -- The probe read this fontstring straight off _G. U.G prefers getglobal, and
  -- nothing has verified the two agree for a region a template created, so the
  -- measured path is tried first and U.G is the fallback.
  local global = SCANNER_NAME .. "TextLeft1"
  local line = nil
  if _G then line = _G[global] end
  if not line then line = U.G(global) end
  if not line or type(line.GetText) ~= "function" then return nil end

  local ok, text = pcall(line.GetText, line)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  return text
end

-- ---------------------------------------------------------------------------
-- Aura tracking
--
-- What the client will not tell us: when an aura started. What it will: whether
-- the aura is there right now. So the start stamp is the first tick that saw
-- it, kept per unit and per aura name.
--
-- The unit key is name plus level, which is pfUI's own key
-- (libdebuff.objects[unit][unitlevel]) and the closest thing to an identity
-- this client offers -- there is no GUID in the Vanilla API shape. Keeping a
-- short history of keys rather than only the current target means switching
-- target and switching back keeps the timers running instead of restarting
-- them.
-- ---------------------------------------------------------------------------
local MAX_UNITS = 16

local units = {}      -- unit key -> { helpful = {}, harmful = {}, touched }
local unitCount = 0
local passCount = 0

local function PruneUnits()
  if unitCount <= MAX_UNITS then return end

  local oldestKey, oldestTouched = nil, nil
  local key, store
  for key, store in pairs(units) do
    if not oldestTouched or store.touched < oldestTouched then
      oldestKey, oldestTouched = key, store.touched
    end
  end

  if oldestKey then
    units[oldestKey] = nil
    unitCount = unitCount - 1
  end
end

local function UnitStore(unit)
  local name = Call("UnitName", unit)
  if type(name) ~= "string" or name == "" then return nil end

  local key = name .. "@" .. (tonumber(Call("UnitLevel", unit)) or 0)
  local store = units[key]
  if not store then
    -- Stamped before PruneUnits runs, not after: the prune compares every
    -- store's stamp and an unstamped one would be a nil in that comparison.
    store = { helpful = {}, harmful = {}, touched = Now() }
    units[key] = store
    unitCount = unitCount + 1
    PruneUnits()
    return units[key]
  end

  store.touched = Now()
  return store
end

-- One aura, seen this pass. Returns the tracked entry, or nil when nothing is
-- known about it -- an unnamed aura, or one the duration table has no answer
-- for, is tracked as present but never gets a timer.
--
-- `key` is the aura name on the reconstructed path and the icon texture on the
-- native one, where no name is needed because the client supplies the time.
-- `timeLeft`, when present, is that client-reported remaining time and takes
-- over completely: the entry is rewritten from it on every scan, so the number
-- cannot drift.
local function TrackAura(bucket, key, count, pass, timeLeft)
  if not bucket or not key then return nil end

  local entry = bucket[key]
  local now = Now()

  if timeLeft then
    if not entry then
      entry = { count = count }
      bucket[key] = entry
    end

    -- The client gives remaining, not total, and the wipe needs a total. The
    -- largest remaining ever seen for this entry is that total: exact once the
    -- aura has been watched from its application, and merely "starts full" for
    -- one that was already running when the row first saw it. A refresh pushes
    -- the remaining back up and the total follows it.
    local duration = entry.duration or 0
    if timeLeft > duration then duration = timeLeft end

    entry.duration = duration
    entry.start = now - (duration - timeLeft)
    entry.count = count
    entry.native = true
    entry.seen = pass
    return entry
  end

  if not entry then
    entry = { start = now, duration = U.AuraDuration(key), count = count }
    bucket[key] = entry
  elseif count > entry.count then
    -- A stack going up is a reapplication. It is the only refresh signal this
    -- client gives, since neither the aura call nor the tooltip changes when a
    -- DoT is recast at the same stack size.
    entry.count = count
    entry.start = now
  elseif entry.duration and entry.start + entry.duration <= now then
    -- Still here after its duration ran out. Either it was recast (the common
    -- case, and invisible to us) or core/auradata.lua's number is wrong for
    -- this server. Restarting is right in the first case and self-correcting
    -- in neither -- so the timer loops rather than freezing at zero, and a
    -- duration that is wrong shows up as a timer that resets early.
    entry.start = now
    entry.count = count
  else
    entry.count = count
  end

  entry.seen = pass
  return entry
end

-- Anything not seen this pass has fallen off. Dropping it is what makes a
-- re-applied aura start from full instead of resuming a stale stamp.
local function PruneAuras(bucket, pass)
  local name, entry
  for name, entry in pairs(bucket) do
    if entry.seen ~= pass then bucket[name] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------
-- How far to walk on a unit, and why the walk no longer stops early.
--
-- These lists are slot-indexed, not compacted. The client documents index as a
-- slot in a fixed range -- UnitDebuff "index is 1-based. Valid range is 1 ... 16"
-- and UnitBuff "1 ... 32" -- and documents an unused slot answering nil/0(/nil)
-- *at that slot*, which is the shape of a list that can carry holes rather than
-- one that ends at the first gap.
--
-- The previous walk stopped after two consecutive empty slots, on the
-- assumption that indices are contiguous. That assumption was never verified
-- (the probe only ever had one debuff live) and it silently dropped every aura
-- sitting behind a two-slot hole: reported in game as a debuff that
-- intermittently never appeared on the target frame at all, while the debuffs
-- ahead of it showed normally. UnrealPfUI, a working implementation on this
-- same client, scans both lists flat and never breaks on an empty slot
-- (api/unitframes.lua: "for i=1,16" for debuffs, "for i=1,32" for buffs) --
-- WORKING_SOURCE evidence per .claude/rules/unreal-pfui.md, not runtime
-- verification, but it is the only evidence either way and it agrees with the
-- documented slot ranges.
--
-- So the walk is flat now, bounded only by the documented slot count. The cost
-- is the empty slots it no longer skips: one pcall'd read each, at most 16 on a
-- debuff row and 32 on a buff row, which the primary rows pay 5 times a second
-- and the party rows once a second. Nothing else got more expensive -- the
-- tooltip name scan, the icon writes and the timer tick all still run only for
-- slots that actually hold an aura, and the party rows still stop as soon as
-- their six visible slots are full.
local MAX_DEBUFF_SLOTS = 16
local MAX_BUFF_SLOTS = 32

local function ScanLimit(harmful)
  return harmful and MAX_DEBUFF_SLOTS or MAX_BUFF_SLOTS
end

-- Party rows stay inside the member frame's 47-unit vertical footprint and
-- extend to its right, matching the requested at-a-glance layout without
-- covering the unit button. Six 18-unit icons plus the established 2-unit
-- spacing is compact enough to keep all four members readable as one block.
local PARTY_COUNT = 4
local PARTY_SIZE = 18
local PARTY_MAX = 6

-- Gap between a row and whatever it sits against, on either side.
local ROW_GAP = 4

-- The countdown re-reads the clock this often. Matches modules/actionbar.lua's
-- CD_TICK so the tenths shown in the last five seconds actually count down;
-- the aura scan itself stays on the slower tick below.
local TIMER_TICK = 0.1

local rows = {}       -- row id -> row frame
local rowOrder = {}   -- stable iteration order for the timer tick

-- Work counters; see core/compat.lua's for why counting substitutes for timing
-- on this client.
local statRows, statScans, statApplied, statTextures, statNames = 0, 0, 0, 0, 0

function U.AuraStats()
  return {
    rowRefreshes = statRows,
    auraReads = statScans,
    iconsApplied = statApplied,
    texturesSet = statTextures,
    nameScans = statNames,
    trackedUnits = unitCount,
    -- Not work done, but the ceiling on how many auras can ever show a timer.
    durationTable = U.AuraDurationCount(),
  }
end

-- The timer font scales off the icon the way the action button's countdown
-- scales off the button, but at a shallower ratio: a 24-unit aura icon carries
-- both a timer and a stack count in its corner, so the timer stays small
-- enough to leave the icon's own art readable underneath it. Capped at 10 by
-- request, one below M.fontSize.tiny's 9-unit floor stated elsewhere for the
-- action bar -- this is a smaller, denser label than that one, so it is
-- allowed to sit under that floor; watch it in game for legibility.
local function TimerFontSize(size)
  local value = math.floor(size * 0.3)
  if value < 8 then value = 8 end
  if value > 10 then value = 10 end
  return value
end

-- Shows the shared client GameTooltip for the aura currently in this icon's
-- slot (row.unit/row.harmful/icon.uuiIndex, kept current by RefreshRow).
--
-- No caster line: probe run targetcast (2026-08-22, behavior.json) measured
-- this client's SetUnitBuff/SetUnitDebuff tooltip at exactly 2 lines (name,
-- static description) with a live Power Word: Shield/Fortitude/Shadow Word:
-- Pain, matching true Vanilla 1.12 -- there is no "Cast By" line to show, on
-- this tooltip or the raw UnitBuff/UnitDebuff return. The only place a caster
-- name appears at all is inside periodic-damage combat-log chat text ("X
-- suffers N damage from your/Name's Spell"), and only for damage-over-time
-- debuffs -- plain buffs and instant debuffs carry no caster text anywhere.
-- Reconstructing that (pfUI libdebuff-style chat parsing) was deliberately
-- not built: partial DoT-only coverage for real parsing fragility, by
-- request.
local function ShowIconTooltip(row, icon)
  local index = icon.uuiIndex
  if not index then return end

  local tooltip = U.G("GameTooltip")
  if not tooltip then return end

  pcall(tooltip.SetOwner, tooltip, icon, "ANCHOR_RIGHT")
  local setter = row.harmful and tooltip.SetUnitDebuff or tooltip.SetUnitBuff
  if type(setter) ~= "function" or not pcall(setter, tooltip, row.unit, index) then
    pcall(tooltip.Hide, tooltip)
    return
  end
  pcall(tooltip.Show, tooltip)
end

local function HideIconTooltip()
  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end
end

local function CreateIcon(row, index)
  local size = U.GetAuraSetting("size")

  local icon = CreateFrame("Frame", "UnrealUIAura" .. row.id .. index, row)
  icon:SetWidth(size)
  icon:SetHeight(size)
  icon.uuiRadialOnly = row.radialOnly
  U.CreateBackdrop(icon, {})

  -- scripts.handler_arguments_direct: handlers close over `row`/`icon` instead
  -- of reading `this`, matching modules/actionbar.lua's button tooltip wiring.
  pcall(icon.EnableMouse, icon, true)
  icon:SetScript("OnEnter", function() ShowIconTooltip(row, icon) end)
  icon:SetScript("OnLeave", function() HideIconTooltip() end)

  local texture = icon:CreateTexture(nil, "ARTWORK")
  texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  -- Trims the stock icon border the same way modules/actionbar.lua does, so the
  -- unrealUI outline is the only edge on screen.
  pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
  icon.texture = texture

  -- A raised child inset one unit, so the wipe covers the artwork but never the
  -- outline. It exists for the same reason modules/actionbar.lua's textLayer
  -- does: regions on the icon's own OVERLAY layer would be drawn underneath a
  -- wipe that has to sit above the artwork, and a higher frame level is the
  -- only ordering this client guarantees between the two.
  local overlay = CreateFrame("Frame", nil, icon)
  overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  local levelOk, level = pcall(icon.GetFrameLevel, icon)
  if levelOk and tonumber(level) then
    pcall(overlay.SetFrameLevel, overlay, level + 5)
  end
  icon.overlay = overlay

  -- The same hand-drawn radial the action buttons use. BACKGROUND within the
  -- raised frame keeps the number and the stack count on top of it.
  icon.wipe = U.CreateRadialWipe(overlay, { size = size - 2 })

  icon.timer = U.CreateLabel(overlay, {
    size = TimerFontSize(size),
    color = M.cooldownText.normal,
    inherits = "GameFontNormal",
  })
  if icon.timer then
    -- Nudged down half a unit by request, off the icon's true centre.
    icon.timer:SetPoint("CENTER", overlay, "CENTER", 0, -0.5)
    icon.timer:Hide()
  end

  -- fonts.stretched_justification_ignored: anchored to the one corner it
  -- belongs in rather than stretched across the icon.
  icon.count = U.CreateLabel(overlay, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if icon.count then
    icon.count:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
  end

  icon:Hide()
  row.icons[index] = icon
  return icon
end

-- Places one icon in the grid. The near row always sits against the frame
-- edge closest to it (top edge when shown above, bottom edge when shown
-- below) and further rows stack away from the frame, so that edge stays put
-- no matter how many auras are up.
local function PlaceIcon(row, icon, slot, size, spacing, perRow, below)
  if row.beside then
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", row, "LEFT", (slot - 1) * (size + spacing), 0)
    return
  end

  local column = math.mod(slot - 1, perRow)
  local line = math.floor((slot - 1) / perRow)

  icon:ClearAllPoints()
  if below then
    icon:SetPoint("TOPLEFT", row, "TOPLEFT",
                  column * (size + spacing),
                  -line * (size + spacing))
  else
    icon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",
                  column * (size + spacing),
                  line * (size + spacing))
  end
end

-- Anchors the row itself to the frame edge matching the current position
-- setting, `offset` units further out. Re-run every refresh (cheap, same
-- pattern as the geometry reads below) so a mid-session setting change takes
-- effect without a reload.
--
-- The offset is how the target's two rows stack: debuffs take the edge, buffs
-- are pushed out past whatever height the debuffs ended up needing. Anchoring
-- the buff row to the debuff row instead would leave it reading a stale height
-- on the pass where the debuff row is empty and hidden.
local function PositionRow(row, below, offset)
  offset = offset or 0
  row:ClearAllPoints()
  if row.beside then
    local rightOffset = tonumber(row.anchor.uuiAuraRightOffset) or 0
    row:SetPoint("LEFT", row.anchor, "RIGHT", ROW_GAP + rightOffset,
                 row.besideY or 0)
    return
  end

  if below then
    -- Target-of-target hangs directly below the target frame. When it is
    -- visible, target auras must clear that frame rather than claiming the
    -- same edge. Rows for every other unit, and target auras without a
    -- target-of-target, retain their usual close-to-frame position.
    local anchor = row.belowAnchor
    if not anchor or not anchor:IsShown() then anchor = row.anchor end
    local bottomOffset = tonumber(anchor.uuiAuraBottomOffset) or 0
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0,
                 -(ROW_GAP + offset + bottomOffset))
  else
    local topOffset = tonumber(row.anchor.uuiAuraTopOffset) or 0
    row:SetPoint("BOTTOMLEFT", row.anchor, "TOPLEFT", 0,
                 ROW_GAP + offset + topOffset)
  end
end

-- ---------------------------------------------------------------------------
-- Timer readout
--
-- Split from the aura scan the way modules/actionbar.lua splits
-- RefreshCooldownText from UpdateCooldown: this runs at TIMER_TICK and touches
-- no client API beyond the clock, while the scan below runs at the slower tick
-- and does all the reading.
-- ---------------------------------------------------------------------------
local function HideTimerText(icon)
  if icon.timer and icon.uuiTimerShown then
    icon.uuiTimerShown = false
    icon.uuiTimerText = nil
    icon.uuiTimerTier = nil
    icon.timer:SetText("")
    icon.timer:Hide()
  end
end

local function HideTimer(icon)
  U.HideRadialWipe(icon.wipe)
  HideTimerText(icon)
end

-- `enabled` is passed in rather than read here: this runs once per shown icon
-- at TIMER_TICK, and U.ModuleConfig walks the whole defaults table on every
-- read, so the one lookup belongs at the top of the sweep.
local function RefreshTimer(icon, now, enabled)
  local entry = icon.uuiEntry
  if not enabled or not entry or not entry.duration then
    HideTimer(icon)
    return
  end

  local elapsed = now - entry.start
  local remaining = entry.duration - elapsed
  if remaining <= 0 then
    -- The scan tick restamps a still-present aura; until it does, drawing an
    -- empty wipe is better than drawing a negative number.
    HideTimer(icon)
    return
  end

  U.SetRadialWipeProgress(icon.wipe, elapsed / entry.duration)

  -- Compact party icons use the radial as their only duration indicator. This
  -- keeps the artwork readable while preserving the useful expiry motion.
  if icon.uuiRadialOnly then
    HideTimerText(icon)
    return
  end

  if not icon.timer then return end

  local text, tier = U.FormatTimeShort(remaining)
  if icon.uuiTimerText ~= text then
    icon.uuiTimerText = text
    icon.timer:SetText(text)
  end
  if icon.uuiTimerTier ~= tier then
    icon.uuiTimerTier = tier
    local color = M.cooldownText[tier] or M.cooldownText.normal
    pcall(icon.timer.SetTextColor, icon.timer, M.Unpack(color))
  end
  if not icon.uuiTimerShown then
    icon.uuiTimerShown = true
    icon.timer:Show()
  end
end

-- Everything in ApplyIcon is written only when the value it writes actually
-- changed. Recurring refreshes re-derive the same tuple from the client, so
-- without these guards a live aura repeatedly re-issued its own icon path to
-- SetTexture for as long as it was up. On this
-- client an icon path is a UAsset reference ("/Game/Interface/Icons/..._TEX",
-- measured in auras.unitbuff_unitdebuff_contract_unverified), not a loose BLP,
-- so how a repeated set is handled is the renderer's business rather than
-- something this addon can assume is free -- and it never had to ask.
--
-- It matters most on target change: only the icons whose aura genuinely
-- differs from the previous target's now touch a texture at all.
local function ApplyIcon(icon, texture, count, borderColor, size, entry, now, timers)
  statApplied = statApplied + 1
  if icon.uuiSize ~= size then
    icon.uuiSize = size
    icon:SetWidth(size)
    icon:SetHeight(size)
    U.SizeRadialWipe(icon.wipe, size - 2)
    if icon.timer then U.SetFont(icon.timer, TimerFontSize(size)) end
  end

  if icon.uuiTexture ~= texture then
    icon.uuiTexture = texture
    statTextures = statTextures + 1
    pcall(icon.texture.SetTexture, icon.texture, texture)
  end

  -- The colour table is the cache key, not the aura type: TypeColor already
  -- collapses every unclassified debuff onto one table and buffs onto another,
  -- so identity is enough and a nil debuffType needs no sentinel of its own.
  if icon.uuiBorder ~= borderColor then
    icon.uuiBorder = borderColor
    U.SetBorderColor(icon, M.Unpack(borderColor))
  end

  -- A stack of 1 is the normal case and the number would just be noise.
  if icon.count then
    local text = (count and count > 1) and tostring(count) or ""
    if icon.uuiCount ~= text then
      icon.uuiCount = text
      icon.count:SetText(text)
      if text == "" then icon.count:Hide() else icon.count:Show() end
    end
  end

  icon.uuiEntry = entry
  RefreshTimer(icon, now, timers)

  if not icon.uuiShown then
    icon.uuiShown = true
    icon:Show()
  end
end

-- Paired with the guard above: a hidden icon must forget it is shown, or the
-- next aura to land in that slot would be left invisible.
local function HideIcon(icon)
  if not icon.uuiShown then return end
  icon.uuiShown = false
  icon.uuiEntry = nil
  icon.uuiIndex = nil
  HideTimer(icon)
  icon:Hide()
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function RowEnabled(row)
  -- The location switch wins over the per-type one, so an off display stays
  -- off whatever the buff/debuff checkboxes under it say.
  if row.master and not U.GetAuraSetting(row.master) then return false end
  return U.GetAuraSetting(row.setting) and true or false
end

local function UnitExists(unit)
  local value = Call("UnitExists", unit)
  return (value and value ~= 0) and true or false
end

-- A party token continues to exist when its character is too far away for the
-- client to provide live unit-object data. Scanning party auras in that state
-- was user-observed to render duplicated icons; the exact raw return tuple was
-- not captured. UnitIsVisible is the documented object-availability check and
-- is also the guard used by UnrealPfUI's same-client unit paths. If the API
-- itself is unavailable or errors, do not hide valid rows on an unverified
-- fallback assumption.
local function UnitVisible(unit)
  local fn = Fn("UnitIsVisible")
  if not fn then return true end

  local ok, value = pcall(fn, unit)
  if not ok then return true end
  return (value and value ~= 0) and true or false
end

-- The name behind one index, cached against the texture that was in that slot
-- when it was last scanned. Without the cache this would arm and read a tooltip
-- for every aura on every unit five times a second; with it, a steady row scans
-- nothing at all.
local function AuraName(row, index, texture)
  local cached = row.names[index]
  if cached and cached.texture == texture then return cached.name end

  statNames = statNames + 1
  local name = ScanName(row.unit, index, row.harmful)
  row.names[index] = { texture = texture, name = name }
  return name
end

-- Draws one row and returns the height it used, which is what the row stacked
-- outside it is offset by. A hidden row returns 0.
local function RefreshRow(row, offset)
  statRows = statRows + 1
  if not row then return 0 end
  if U.PerfDisabled and U.PerfDisabled("auras") then return 0 end

  local i
  if not RowEnabled(row) or not UnitExists(row.unit) or
     (row.beside and not UnitVisible(row.unit)) then
    for i = 1, table.getn(row.icons) do HideIcon(row.icons[i]) end
    row:Hide()
    return 0
  end

  local size = row.size or U.GetAuraSetting("size")
  local spacing = row.spacing or U.GetAuraSetting("spacing")
  local perRow = row.perRow or U.GetAuraSetting("perRow")
  local maxIcons = row.maxIcons or
                   U.GetAuraSetting(row.harmful and "maxIcons" or "maxBuffs")
  local below = not row.beside and U.GetAuraSetting("belowFrame")
  local timers = U.GetAuraSetting("showTimers")

  PositionRow(row, below, offset)

  local store = UnitStore(row.unit)
  local bucket = store and (row.harmful and store.harmful or store.helpful)
  local now = Now()

  -- Resolved once per pass, not per index: which unit this row is pointed at
  -- cannot change halfway through its own scan.
  local native = IsPlayerUnit(row.unit)
  row.native = native

  passCount = passCount + 1
  local pass = passCount

  local shown = 0
  for i = 1, ScanLimit(row.harmful) do
    statScans = statScans + 1
    local texture, count, debuffType, timeLeft
    if native then
      texture, count, debuffType, timeLeft = ReadPlayerAura(i, row.harmful)
    else
      texture, count, debuffType = ReadAura(row.unit, i, row.harmful)
    end

    -- An empty slot is skipped, not an end of list. The drawn row stays
    -- gapless because icons are placed by `shown`, which only advances for an
    -- aura that was actually found.
    if texture then
      -- Tracking runs for every aura on the unit, not only the drawn ones. A
      -- filtered-out debuff that stopped being tracked would be stamped anew
      -- the moment its filter was switched back on, and one past the icon cap
      -- would restart every time the auras ahead of it changed.
      -- The tooltip scan exists only to feed the duration table. On the native
      -- path the client already gave a remaining time, so the aura is keyed by
      -- its texture and no tooltip is armed at all.
      local key = native and texture or AuraName(row, i, texture)
      local entry = TrackAura(bucket, key, count, pass, timeLeft)

      if row.harmful and not PassesFilter(debuffType) then
        -- Tracked, not drawn.
      elseif shown < maxIcons then
        shown = shown + 1
        local icon = row.icons[shown] or CreateIcon(row, shown)
        -- The drawn slot (shown) and the native aura index (i) diverge once a
        -- debuff ahead of this one is filtered out by PassesFilter; the
        -- tooltip must key off the real index or it would show the wrong aura.
        icon.uuiIndex = i
        PlaceIcon(row, icon, shown, size, spacing, perRow, below)
        ApplyIcon(icon, texture, count,
                  row.harmful and TypeColor(debuffType) or BUFF_COLOR,
                  size, entry, now, timers)

        -- Party rows never draw beyond their six visible slots. Stop as soon
        -- as those slots are full instead of scanning and tooltip-naming the
        -- rest of the slot range, which cannot affect the display.
        if row.stopAtCap and shown >= maxIcons then break end
      end
    end
  end

  if bucket then PruneAuras(bucket, pass) end

  for i = shown + 1, table.getn(row.icons) do HideIcon(row.icons[i]) end

  if shown > 0 then
    local lines = math.floor((shown - 1) / perRow) + 1
    local columns = shown < perRow and shown or perRow
    local height = lines * (size + spacing)
    row:SetWidth(columns * (size + spacing))
    row:SetHeight(height)
    row:Show()
    return height
  end

  row:Hide()
  return 0
end

-- Debuffs take the frame edge and buffs stack outside them, so the row a player
-- reads mid-fight never moves because a buff came or went. The player frame is
-- stacked the same way as the target frame so the two read identically; both
-- halves of the player pair come from the native GetPlayerBuff path, so their
-- timers are the client's own number either way.
local function RefreshPlayer()
  local used = RefreshRow(rows.player, 0)
  RefreshRow(rows.playerBuff, used > 0 and used + ROW_GAP or 0)
end

local function RefreshTarget()
  local used = RefreshRow(rows.target, 0)
  RefreshRow(rows.targetBuff, used > 0 and used + ROW_GAP or 0)
end

local function RefreshPrimary()
  RefreshPlayer()
  RefreshTarget()
end

local function RefreshPartyUnit(token, clearNames)
  local debuffs = rows[token]
  local buffs = rows[token .. "Buff"]

  if clearNames then
    if debuffs then debuffs.names = {} end
    if buffs then buffs.names = {} end
  end

  RefreshRow(debuffs, 0)
  RefreshRow(buffs, 0)
end

local function RefreshParty(clearNames)
  local i
  for i = 1, PARTY_COUNT do
    RefreshPartyUnit("party" .. i, clearNames)
  end
end

local function RefreshAll()
  RefreshPrimary()
  RefreshParty(false)
end

-- Only the unit the event carries, when it carries a usable token.
local function RefreshUnitToken(token)
  if token == "target" then
    RefreshTarget()
  elseif token == "player" then
    RefreshPlayer()
  elseif type(token) == "string" and rows[token] and rows[token].beside then
    RefreshPartyUnit(token, false)
  else
    -- UNIT_AURA may carry a token for which this module has no row (pet,
    -- target-of-target, raid). Do not turn that into an eleven-row rescan.
    RefreshPrimary()
  end
end

-- The fast half: clock only, over the icons that are already on screen.
local function RefreshTimers()
  if U.PerfDisabled and U.PerfDisabled("auras") then return end

  local now = Now()
  local timers = U.GetAuraSetting("showTimers")
  local r, i
  for r = 1, table.getn(rowOrder) do
    local row = rowOrder[r]
    for i = 1, table.getn(row.icons) do
      local icon = row.icons[i]
      if icon.uuiShown then RefreshTimer(icon, now, timers) end
    end
  end
end

-- Called by the settings page after any option changes: geometry, filters and
-- the timer toggle all take effect on the next refresh, so this is just an
-- immediate one.
function U.ApplyAuras()
  RefreshAll()
end

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- A missing timer is always one of exactly three things: the scanner gave no
-- name, the duration table has no entry for that name, or the client reported
-- no remaining time. "/uui aura" says which, per row and per index, from the
-- live state -- no reload, no probe run, no guessing between them.
-- ---------------------------------------------------------------------------
-- Icon paths on this client are UAsset references with forward slashes
-- ("/Game/Interface/Icons/Spell_Fire_Immolation_TEX", measured in
-- auras.unitbuff_unitdebuff_contract_unverified), so the leaf is all a chat
-- line needs.
local function ShortTexture(texture)
  if type(texture) ~= "string" then return "-" end
  local tail = string.gsub(texture, ".*/", "")
  if tail == "" then return texture end
  return tail
end

-- Where a row actually sits, and what native art shares that space. Only
-- meaningful under Classic, where the client's own unit frame is drawn over the
-- anchor: it reports the two layers side by side, so "the icons are behind the
-- native frame" can be confirmed or ruled out from one report instead of a
-- probe run. rowLevel > nativeLevel on a shared strata means the row is on top;
-- differing strata means the strata decides and the level is irrelevant.
local function LayerLine(row)
  local native = row.anchor and row.anchor.classicNativeFrame
  if not native then return nil end

  local function Read(object, method)
    local fn = object[method]
    if type(fn) ~= "function" then return "?" end
    local ok, value = pcall(fn, object)
    if not ok or value == nil then return "?" end
    return tostring(value)
  end

  return string.format("    layer: row %s/%s  native %s/%s",
                       Read(row, "GetFrameStrata"), Read(row, "GetFrameLevel"),
                       Read(native, "GetFrameStrata"),
                       Read(native, "GetFrameLevel"))
end

function U.AuraDebugDump()
  U.Print("aura dump - duration table holds " .. U.AuraDurationCount() ..
          " entries  (theme " .. tostring(U.GetActiveThemeStyle()) ..
          ", below frame " .. tostring(U.GetAuraSetting("belowFrame")) .. ")")

  local r
  for r = 1, table.getn(rowOrder) do
    local row = rowOrder[r]
    local native = IsPlayerUnit(row.unit)
    local exists = UnitExists(row.unit)

    U.Print(string.format("|cffffff00%s|r %s on %s - enabled=%s exists=%s via %s",
                          row.id, row.harmful and "debuffs" or "buffs", row.unit,
                          tostring(RowEnabled(row)), tostring(exists),
                          native and "GetPlayerBuff (client time)"
                                 or "tooltip name + duration table"))

    local layer = LayerLine(row)
    if layer then U.Print(layer) end

    if exists then
      local i
      -- Walks every slot the display path walks, so a hole in the list reads
      -- the same here as it draws on the frame.
      for i = 1, ScanLimit(row.harmful) do
        local texture, count, debuffType, timeLeft
        if native then
          texture, count, debuffType, timeLeft = ReadPlayerAura(i, row.harmful)
        else
          texture, count, debuffType = ReadAura(row.unit, i, row.harmful)
        end

        if texture then
          local name = nil
          if not native then name = ScanName(row.unit, i, row.harmful) end

          local seconds = timeLeft
          if not seconds and name then seconds = U.AuraDuration(name) end

          U.Print(string.format("  %d %s name=%s stacks=%s type=%s %s=%s",
                                i, ShortTexture(texture), tostring(name or "-"),
                                tostring(count or 0), tostring(debuffType or "-"),
                                native and "timeLeft" or "duration",
                                seconds and string.format("%.1f", seconds)
                                        or "|cffff4040none|r"))
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
-- Classic draws the client's own unit frame over this row's anchor, so the row
-- shares its screen area with native art that UnrealUI does not own. The anchor
-- is deliberately on the LOW strata (modules/unitframes.lua) so UnrealUI's
-- frames stay under interface windows, and a row left at the anchor's own frame
-- level can be covered by the native frame that sits on top of it.
--
-- The raise is level-only, and only when the two are already on the same
-- strata. That is the case it can fix; it is also the only case where changing
-- anything is safe. Matching the native frame's strata instead would be the
-- complete fix, but it can push a row onto MEDIUM, where UnrealUI's own bag
-- window lives -- trading a Classic-only aura bug for aura icons drawn over the
-- bags for everyone. Do not make that trade without a measurement: what the
-- native frame's strata actually is here has never been read, and /uui aura
-- now prints it precisely so one report can settle it.
local function RaiseAboveNativeFrame(row, anchor)
  local native = anchor and anchor.classicNativeFrame
  if not native then return end

  local rowOk, rowStrata = pcall(row.GetFrameStrata, row)
  local nativeOk, nativeStrata = pcall(native.GetFrameStrata, native)
  if not rowOk or not nativeOk or rowStrata ~= nativeStrata then return end

  local levelOk, level = pcall(native.GetFrameLevel, native)
  if not levelOk or not tonumber(level) then return end
  pcall(row.SetFrameLevel, row, level + 10)
end

local function BuildRow(id, unit, harmful, setting, options)
  local anchor = U.GetUnitFrame(unit)
  if not anchor then
    U.Debug("no unit frame to anchor auras to: " .. id)
    return nil
  end

  -- A plain container that rides the unit frame's mover rather than owning one
  -- of its own, so the icons cannot drift away from the frame they describe.
  -- Only the child icons accept hover, for their native aura tooltip.
  local row = CreateFrame("Frame", "UnrealUIAuraRow" .. id, anchor)
  row.anchor = anchor
  if unit == "target" then row.belowAnchor = U.GetUnitFrame("targettarget") end
  RaiseAboveNativeFrame(row, anchor)
  row:SetWidth(1)
  row:SetHeight(1)
  PositionRow(row, U.GetAuraSetting("belowFrame"), 0)

  row.id = id
  row.unit = unit
  row.harmful = harmful
  row.setting = setting
  if options then
    row.beside = options.beside
    row.besideY = options.besideY
    row.size = options.size
    row.spacing = options.spacing
    row.perRow = options.perRow
    row.maxIcons = options.maxIcons
    row.stopAtCap = options.stopAtCap
    row.radialOnly = options.radialOnly
    row.master = options.master
  end
  row.icons = {}
  row.names = {}
  row:Hide()

  rows[id] = row
  table.insert(rowOrder, row)
  return row
end

-- ---------------------------------------------------------------------------
-- Settings page
--
-- One top-level "Unit Frames" page, per request. It is not a config framework:
-- the checkboxes read and write the module's own settings table directly, the
-- same way modules/actionbarconfig.lua does.
--
-- Icon size/per-row/max-icons/spacing are deliberately not exposed here --
-- there is no user-facing control for them, only the fixed defaults above.
-- ---------------------------------------------------------------------------
local PAGE_WIDTH = 484
local FILTER_COLUMN_X = 160

-- The Unit Frames page opens with the party-frame section, which is owned by
-- modules/unitframes.lua because that module owns the layout it changes. Every
-- offset below is measured from the bottom of that section plus the 8-unit gap
-- the other section headings use, so the aura controls keep their own spacing
-- whatever is stacked above them.
local SECTION_TOP = (U.UnitFramePartySettingsHeight or 0)
if SECTION_TOP > 0 then SECTION_TOP = SECTION_TOP + 8 end

-- Two columns keep the toggles to five compact rows and leave the colour
-- controls inside the fixed-height settings panel.
local TOGGLE_COLUMN_X = 240

-- The client's own display is modules/buffframe.lua's frames, not this
-- module's rows, so this toggle reads and writes through that module rather
-- than through the aura config table. If that module found no native frames to
-- own, the checkbox reads as on and does nothing, which is what an interface
-- with no such display looks like.
local function NativeShown()
  if type(U.GetNativeAuraFrameShown) ~= "function" then return true end
  local ok, value = pcall(U.GetNativeAuraFrameShown)
  if not ok then return true end
  return value and true or false
end

local function SetNativeShown(value)
  if type(U.SetNativeAuraFrameShown) ~= "function" then return end
  pcall(U.SetNativeAuraFrameShown, value)
end

-- Row 0 is where the player's own auras appear -- one switch per location, the
-- unrealUI rows on the player frame and the client's own row by the minimap.
-- The rows under it are which auras each frame draws, so the page reads
-- "where" first and "what" after.
local TOGGLES = {
  { key = "showOnPlayerFrame", textKey = "AURAS_ON_PLAYER_FRAME", column = 0, row = 0 },
  { key = "nativeShown",       textKey = "AURAS_NEAR_MINIMAP",    column = 1, row = 0,
    get = NativeShown, set = SetNativeShown },
  { key = "playerEnabled",     textKey = "AURAS_PLAYER_DEBUFFS",  column = 0, row = 1 },
  { key = "playerBuffEnabled", textKey = "AURAS_PLAYER_BUFFS",    column = 1, row = 1 },
  { key = "targetEnabled",     textKey = "AURAS_TARGET_DEBUFFS",  column = 0, row = 2 },
  { key = "targetBuffEnabled", textKey = "AURAS_TARGET_BUFFS",    column = 1, row = 2 },
  { key = "partyEnabled",      textKey = "AURAS_PARTY_DEBUFFS",   column = 0, row = 3 },
  { key = "partyBuffEnabled",  textKey = "AURAS_PARTY_BUFFS",     column = 1, row = 3 },
  { key = "showTimers",        textKey = "AURAS_SHOW_TIMERS",     column = 0, row = 4 },
  { key = "belowFrame",        textKey = "AURAS_BELOW_FRAME",     column = 1, row = 4 },
}

-- A toggle either lives in this module's config table or, for the native
-- display, behind the two accessors above.
local function ToggleValue(spec)
  if spec.get then return spec.get() end
  return U.GetAuraSetting(spec.key) and true or false
end

local function SetToggleValue(spec, value)
  if spec.set then
    spec.set(value)
    return
  end
  Config()[spec.key] = value
  U.ApplyAuras()
end

-- Three per row rather than two: the toggle grid above needed one more line
-- and the dispel labels are short enough to give it back here, so the hint and
-- the colour section below keep the offsets they already had.
local FILTERS = {
  { key = "showMagic",   textKey = "AURAS_MAGIC",   column = 0, row = 0 },
  { key = "showCurse",   textKey = "AURAS_CURSE",   column = 1, row = 0 },
  { key = "showPoison",  textKey = "AURAS_POISON",  column = 2, row = 0 },
  { key = "showDisease", textKey = "AURAS_DISEASE", column = 0, row = 1 },
  { key = "showOther",   textKey = "AURAS_OTHER",   column = 1, row = 1 },
}

local function BuildSettingsPage(parent)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("AURAS_HEADER"),
    width = PAGE_WIDTH,
    y = -4 - SECTION_TOP,
  })
  table.insert(widgets, header)

  local i
  for i = 1, table.getn(TOGGLES) do
    local spec = TOGGLES[i]
    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIAuraToggle" .. spec.key,
      text = U.L(spec.textKey),
      textWidth = TOGGLE_COLUMN_X - 26,
      value = ToggleValue(spec),
      onChange = function(value) SetToggleValue(spec, value) end,
    })
    check.SetPoint("TOPLEFT", parent, "TOPLEFT",
                   spec.column * TOGGLE_COLUMN_X,
                   -34 - SECTION_TOP - spec.row * 26)
    controls[spec.key] = check
    table.insert(widgets, check)
  end

  local filterHeader = U.CreateSectionHeader(parent, {
    text = U.L("AURAS_DISPEL_HEADER"),
    width = PAGE_WIDTH,
    y = -160 - SECTION_TOP,
  })
  table.insert(widgets, filterHeader)

  for i = 1, table.getn(FILTERS) do
    local spec = FILTERS[i]
    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIAuraFilter" .. spec.key,
      text = U.L(spec.textKey),
      textWidth = FILTER_COLUMN_X - 26,
      value = U.GetAuraSetting(spec.key),
      onChange = function(value)
        Config()[spec.key] = value
        U.ApplyAuras()
      end,
    })
    check.SetPoint("TOPLEFT", parent, "TOPLEFT",
                   spec.column * FILTER_COLUMN_X,
                   -190 - SECTION_TOP - spec.row * 26)
    controls[spec.key] = check
    table.insert(widgets, check)
  end

  -- States plainly where the timers come from, so a missing one reads as a gap
  -- in the duration table rather than as a bug, and a wrong one is not mistaken
  -- for a value the client handed over.
  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
  })
  if hint then
    -- Anchor under the left-most control of the final filter row so the block
    -- starts at the page's left edge instead of under whichever column happens
    -- to hold the last checkbox.
    local anchorKey = FILTERS[1].key
    local f
    for f = 1, table.getn(FILTERS) do
      if FILTERS[f].column == 0 then anchorKey = FILTERS[f].key end
    end
    U.AnchorSettingsDescription(hint, controls[anchorKey].box)
    hint:SetText(U.L("AURAS_HINT"))
    table.insert(widgets, hint)
  end

  local function RefreshAuraControls()
    local n
    for n = 1, table.getn(TOGGLES) do
      local spec = TOGGLES[n]
      if controls[spec.key] then
        controls[spec.key].SetValue(ToggleValue(spec))
      end
    end
    for n = 1, table.getn(FILTERS) do
      local spec = FILTERS[n]
      if controls[spec.key] then
        controls[spec.key].SetValue(U.GetAuraSetting(spec.key))
      end
    end
  end

  local refreshParty
  if type(U.BuildUnitFramePartySettings) == "function" then
    local partyWidgets
    partyWidgets, refreshParty =
      U.BuildUnitFramePartySettings(parent, -4, PAGE_WIDTH)
    local n
    for n = 1, table.getn(partyWidgets) do
      table.insert(widgets, partyWidgets[n])
    end
  end

  local refreshColors
  if type(U.BuildUnitFrameColorSettings) == "function" then
    local colorWidgets
    colorWidgets, refreshColors =
      U.BuildUnitFrameColorSettings(parent, -302 - SECTION_TOP, PAGE_WIDTH)
    local n
    for n = 1, table.getn(colorWidgets) do
      table.insert(widgets, colorWidgets[n])
    end
  end

  local function Refresh()
    RefreshAuraControls()
    if refreshParty then refreshParty() end
    if refreshColors then refreshColors() end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function A:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("unitframes", U.L("UF_PAGE"), BuildSettingsPage)
  end
end

function A:OnEnable()
  BuildRow("player", "player", true, "playerEnabled",
           { master = "showOnPlayerFrame" })
  BuildRow("playerBuff", "player", false, "playerBuffEnabled",
           { master = "showOnPlayerFrame" })
  BuildRow("target", "target", true, "targetEnabled")
  BuildRow("targetBuff", "target", false, "targetBuffEnabled")

  local i
  for i = 1, PARTY_COUNT do
    local unit = "party" .. i
    BuildRow(unit, unit, true, "partyEnabled", {
      beside = true, besideY = 10, size = PARTY_SIZE, spacing = 2,
      perRow = PARTY_MAX, maxIcons = PARTY_MAX, stopAtCap = true,
      radialOnly = true,
    })
    BuildRow(unit .. "Buff", unit, false, "partyBuffEnabled", {
      beside = true, besideY = -10, size = PARTY_SIZE, spacing = 2,
      perRow = PARTY_MAX, maxIcons = PARTY_MAX, stopAtCap = true,
      radialOnly = true,
    })
  end

  if table.getn(rowOrder) == 0 then
    U.Error("aura rows could not be anchored; unit frames are unavailable")
    return
  end

  -- UNIT_AURA is the one aura event observed firing on this client
  -- (events.json); PLAYER_AURAS_CHANGED registered but was never seen, so it is
  -- registered as a free accelerator rather than relied on.
  U.RegisterEvent("UNIT_AURA", function(event, unit) RefreshUnitToken(unit) end)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", function()
    RefreshPlayer()
  end)
  -- round 3: deferred one driver tick, same reasoning as
  -- core/compat.lua's target-group sweep -- this used to scan the whole debuff
  -- slot range and lay out icon geometry synchronously inside the same frame
  -- the client re-shows the native TargetFrame in.
  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    U.DeferOnce("auras.target-refresh", function()
      -- A new target is a new set of indices, so every cached name is stale.
      if rows.target then rows.target.names = {} end
      if rows.targetBuff then rows.targetBuff.names = {} end
      RefreshTarget()
    end)
  end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() RefreshAll() end)

  -- Party roster events are accelerators on this client, just as they are in
  -- modules/unitframes.lua. Clear the per-slot tooltip-name cache when a
  -- different character may now occupy that token.
  local groupEvents = {
    "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED", "RAID_ROSTER_UPDATE",
  }
  for i = 1, table.getn(groupEvents) do
    U.RegisterEvent(groupEvents[i], function()
      U.DeferOnce("auras.party-roster-refresh", function()
        RefreshParty(true)
      end)
    end)
  end

  -- The primary-row mechanism, not an optimisation: with no duration return
  -- there is nothing to expire an icon locally, so an aura that falls off is
  -- only noticed by re-reading. 0.2s matches the unit frame tick; party rows
  -- use their token event plus the slower fallback below.
  U.RegisterUpdate("auras.refresh", 0.2, function() RefreshPrimary() end)
  -- UNIT_AURA normally gives an immediate, token-specific party refresh. A
  -- slower fallback is still required because the compact evidence has only
  -- captured the event for "target", not for party tokens, and party roster
  -- events are accepted but unobserved on this client.
  U.RegisterUpdate("auras.party-refresh", 1.0, function() RefreshParty(false) end)
  U.RegisterUpdate("auras.timers", TIMER_TICK, RefreshTimers)

  RefreshAll()
end
