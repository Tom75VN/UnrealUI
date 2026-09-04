-- unrealUI :: modules/hots.lua
--
-- The player's own heal-over-time spells, drawn as icons on the party unit
-- frames with the addon's radial wipe as their countdown.
--
-- ---------------------------------------------------------------------------
-- Why this is a reconstruction and not a read
-- ---------------------------------------------------------------------------
--
-- Nothing on this client can answer "is there a HoT of mine on party1".
--
--   * knowledge.json / auras.unitbuff_unitdebuff_contract_unverified
--     (RUNTIME_MEASURED): UnitBuff(unit, index) returns (texture, count) and
--     nothing else -- no name, no spell id, no duration, no caster.
--   * knowledge.json / auras.no_native_debuff_expiry_time (BEHAVIOR_VERIFIED,
--     RUNTIME_MEASURED): the GameTooltip:SetUnitBuff scan is exactly two lines,
--     name and a static description, with no timer and no "cast by" text.
--     GetPlayerBuffTimeLeft is indexed by GetPlayerBuff and covers the player's
--     own auras only; there is no party equivalent.
--
-- So the caster and the expiry are reconstructed from the player's own cast,
-- the way UnrealPfUI's libs/libpredict.lua does it on this same client. That is
-- WORKING_SOURCE evidence per .claude/rules/unreal-pfui.md, not runtime
-- verification. What is taken is the idea and the spell data; what is not taken
-- is its HealComm/CTRA addon channel, its heal prediction, its resurrection
-- tracking and its hooksecurefunc-based cast queue -- this client ships no
-- global hooksecurefunc at all (knowledge.json / hooks.no_global_hooksecurefunc)
-- and the addon's own wrapper must not be pointed at vararg natives
-- (knowledge.json / lua.posthook_global_fixed_arity_breaks_vararg_frameXML).
--
-- ---------------------------------------------------------------------------
-- How a cast is identified without hooks
-- ---------------------------------------------------------------------------
--
-- Two sources feed one "pending spell", and SPELLCAST_STOP commits it:
--
--   * SPELLCAST_START(name, castTimeMs) -- observed 34 times (events.json),
--     the player's own cast only, and it carries the name. This is the source
--     for a HoT with a cast time: Regrowth.
--   * An unrealUI action button press -- modules/actionbar.lua calls
--     U.NotifyActionUsed with the slot from OnButtonClick, which every route
--     into a press goes through, and core/init.lua fans that out to every
--     listener (this module and modules/healpredict.lua). The spell name is
--     read from the slot with U.ActionSlotSpellName
--     (modules/spellbook.lua), whose SetAction tooltip
--     scan is BEHAVIOR_VERIFIED in knowledge.json /
--     spellbook.action_slot_spell_identity_tooltip_unverified. This is the
--     source for an instant HoT: Rejuvenation, Renew.
--
-- SPELLCAST_STOP is observed 40 times with an argument count of exactly 0
-- (events.json, events.SPELLCAST_STOP.v1), so it can say "the cast finished"
-- and nothing else. That is why the name has to arrive ahead of it.
--
-- Known gaps, stated rather than papered over:
--
--   * A cast from a macro, from the client's own action bar, or from another
--     addon is not seen. CastSpell/CastSpellByName are documented protected on
--     this client (modules/rogue.lua), and there is no hook to place on them.
--   * A HoT already running at login or after /reload has no stamp, so it does
--     not draw until it is refreshed.
--   * Rank is not recoverable, so a low-rank HoT reads at max-rank duration --
--     the same limit core/auradata.lua carries for target debuffs.
--
-- ---------------------------------------------------------------------------
-- What keeps it honest
-- ---------------------------------------------------------------------------
--
-- A stamp is never trusted on its own. Every refresh confirms it against the
-- unit's real buffs: the spell's icon, folded through U.IconKey, has to still
-- be on the unit or the stamp is dropped. So a dispel, an overwrite by another
-- healer, an early death or a cast that never landed all clear the icon
-- without this module needing an event for any of them.
--
-- The reverse case is handled the other way round, once. If the icon is still on
-- the unit when the stamp runs out -- a Stormrage or Transcendence set bonus,
-- which core/hotdata.lua deliberately does not try to detect -- the stamp
-- restarts rather than dropping a HoT that is visibly still there. Only once,
-- because a second overrun is better explained by another healer's copy of the
-- same spell, and crediting theirs to us indefinitely would be worse than
-- showing nothing.
--
-- ---------------------------------------------------------------------------
-- Scope
-- ---------------------------------------------------------------------------
--
-- Party frames only, per request. The player's own frame is not included: a
-- HoT the player puts on themselves does not draw here.
--
-- The native radial is not an option and is not attempted: knowledge.json /
-- cooldown.model_swipe_not_rendered (BROKEN, RUNTIME_FAILURE_CONFIRMED,
-- USER_CONFIRMED_INGAME) records that CreateFrame("Model", ...,
-- "CooldownFrameTemplate") plus CooldownFrame_SetTimer -- which is exactly what
-- UnrealPfUI's uf:AddIcon builds for these icons -- draws nothing on this
-- client. U.CreateRadialWipe / U.SetRadialWipeProgress (core/style.lua) is the
-- addon's own wipe, already used by the action buttons, the stance bar and the
-- aura icons, and it is what these icons use too.

local U = UnrealUI
local M = U.media

local H = U.RegisterModule("hots")

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local CONFIG = "hots"

local defaults = {
  enabled = true,
  corner  = "TOPLEFT",
  size    = 14,
  spacing = 2,
}

-- Shared with the settings page so the slider and the clamp cannot disagree.
local LIMITS = {
  size    = { min = 10, max = 28, step = 1 },
  spacing = { min = 0,  max = 10, step = 1 },
}

local CORNERS = {
  { value = "TOPLEFT",     textKey = "HOTS_CORNER_TOPLEFT" },
  { value = "TOPRIGHT",    textKey = "HOTS_CORNER_TOPRIGHT" },
  { value = "BOTTOMLEFT",  textKey = "HOTS_CORNER_BOTTOMLEFT" },
  { value = "BOTTOMRIGHT", textKey = "HOTS_CORNER_BOTTOMRIGHT" },
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

function U.GetHotSetting(key)
  local value = Config()[key]
  if value == nil then return defaults[key] end
  return value
end

function U.HotLimits(key)
  local limit = LIMITS[key]
  if not limit then return 0, 0, 1 end
  return limit.min, limit.max, limit.step
end

function U.HotCorners()
  return CORNERS
end

local ApplyIndicators

function U.SetHotSetting(key, value)
  if key == "enabled" then
    Config().enabled = value and true or false
  elseif key == "corner" then
    local i
    for i = 1, table.getn(CORNERS) do
      if CORNERS[i].value == value then Config().corner = value end
    end
  else
    local limit = LIMITS[key]
    local number = tonumber(value)
    if not limit or not number then return end
    if number < limit.min then number = limit.min end
    if number > limit.max then number = limit.max end
    Config()[key] = number
  end

  if ApplyIndicators then ApplyIndicators() end
  -- The party buff row defers to this module, so turning it off has to hand
  -- those icons straight back rather than on the aura module's next sweep.
  if key == "enabled" and type(U.ApplyAuras) == "function" then
    pcall(U.ApplyAuras)
  end
end

-- ---------------------------------------------------------------------------
-- Client access
--
-- Same shape as the helper in modules/auras.lua: a global that is missing or
-- differently shaped on this client returns nil rather than erroring.
-- ---------------------------------------------------------------------------
local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2 = pcall(fn, a, b)
  if not ok then return nil end
  return r1, r2
end

local function Now()
  return tonumber(Call("GetTime")) or 0
end

-- ---------------------------------------------------------------------------
-- Which HoTs this character actually has
--
-- Class filtering falls out of the spellbook: a spell the player cannot cast is
-- not in the book, so it never resolves. U.SpellIconByName (modules/castbar.lua)
-- owns the spellbook walk and its cache, so this costs one lookup per spell per
-- session rather than a second scan of the book.
-- ---------------------------------------------------------------------------
local resolved = {}       -- ordered { id, duration, name, texture, key }
local resolvedById = {}
local resolvedByKey = {}
local resolvedBuilt = false

-- Left unbuilt when it resolves nothing, so the next caller tries again. The
-- spellbook is not guaranteed readable at the moment this first runs, and
-- U.SpellIconByName caches a miss as `false` -- without the retry, one early
-- lookup would leave a healer with no indicators for the whole session. A
-- character who genuinely has no HoT re-checks a handful of cached table reads
-- per scan tick, which is not worth a flag to avoid.
local function BuildResolved()
  resolved = {}
  resolvedById = {}
  resolvedByKey = {}

  local spells = U.HotSpells()
  local i, n
  for i = 1, table.getn(spells) do
    local spell = spells[i]
    local found = nil
    for n = 1, table.getn(spell.names) do
      if not found then
        local name = spell.names[n]
        local texture = nil
        if type(U.SpellIconByName) == "function" then
          texture = U.SpellIconByName(name)
        end
        if texture then
          found = {
            id = spell.id,
            duration = spell.duration,
            name = name,
            texture = texture,
            key = U.IconKey(texture) or spell.icon,
          }
        end
      end
    end
    if found then
      table.insert(resolved, found)
      resolvedById[found.id] = found
      resolvedByKey[found.key] = found
    end
  end

  resolvedBuilt = table.getn(resolved) > 0
end

local function Resolved()
  if not resolvedBuilt then BuildResolved() end
  return resolved
end

local function Tracking()
  if not U.GetHotSetting("enabled") then return false end
  return table.getn(Resolved()) > 0
end

-- Asked by the party buff row in modules/auras.lua before it draws an aura:
-- true means this module already draws that spell inside the frame, so drawing
-- it beside the frame as well would show the player the same buff twice.
--
-- Answered by spell, not by whether an icon happens to be up right now. Keying
-- it to the live indicator would make the buff row shuffle its icons every time
-- a HoT landed or fell off, and would still leave the duplicate on screen for
-- the tick between the aura appearing and the stamp being made.
--
-- The early bail matters: it is called for every buff on every party member, so
-- everyone who is not tracking a HoT pays one boolean rather than a string fold.
function U.HotIndicatorOwnsTexture(texture)
  if not Tracking() then return false end
  local key = U.IconKey(texture)
  return key ~= nil and resolvedByKey[key] ~= nil
end

-- ---------------------------------------------------------------------------
-- Stamps
--
-- Keyed by character name, because a name is the one identity shared between
-- the cast (where only "target" exists) and the display (where only "partyN"
-- exists). This client exposes no unit GUID, so it is the same identity
-- UnrealPfUI's libpredict uses, with the same Vanilla ambiguity when two
-- characters share a name.
-- ---------------------------------------------------------------------------
local stamps = {}
local stampedNames = 0
local MAX_STAMPED_NAMES = 40

local function Stamp(unitName, entry, start)
  if type(unitName) ~= "string" or unitName == "" then return end

  local store = stamps[unitName]
  if not store then
    -- Bounded rather than unbounded: a battleground can put a great many names
    -- through here, and only party members are ever drawn.
    if stampedNames >= MAX_STAMPED_NAMES then
      stamps = {}
      stampedNames = 0
    end
    store = {}
    stamps[unitName] = store
    stampedNames = stampedNames + 1
  end

  store[entry.id] = { start = start or Now(), duration = entry.duration }
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------
local pending = nil

-- Long enough for the slowest tracked HoT's cast plus pushback, short enough
-- that an unrelated later SPELLCAST_STOP cannot commit a stale name.
local PENDING_WINDOW = 5

local slotNames = {}

-- ---------------------------------------------------------------------------
-- The adoption window
--
-- Identifying the cast is the fragile half of this module: an instant spell
-- raises no SPELLCAST_START, SPELLCAST_STOP carries no arguments, and the only
-- remaining identity -- the action slot -- is only visible when the press came
-- through unrealUI's own buttons. A macro, the client's own bar, or a
-- click-cast never reaches U.NotifyActionUsed at all.
--
-- So identity is not required. Any signal that the player just cast *something*
-- opens a short window, and a tracked HoT that appears on a party member inside
-- it, with no stamp of its own, is adopted as ours. Three signals open it,
-- because no single one of them is measured to fire for every case:
-- SPELLCAST_START, SPELLCAST_STOP, and any action press this module is told
-- about.
--
-- What this trades away is exactness under a second healer: their HoT landing
-- on a party member within the window of one of our casts is adopted too. That
-- is the same caster ambiguity the client forces on every part of this module
-- (auras.no_native_debuff_expiry_time), not a new one -- and the precise path
-- above still wins whenever the press is visible, because a stamp it has
-- already made is never adopted over.
-- ---------------------------------------------------------------------------
local lastCast = -1000
local ADOPT_WINDOW = 3

local function OpenAdoptWindow()
  lastCast = Now()
end

-- Counters, not state: "/uui hot" reads them to say which link of the chain a
-- cast stopped at. Cheap enough to leave on -- the alternative is a probe run
-- for a question the module can answer about itself.
local stats = {
  presses = 0, named = 0, armed = 0,
  stopCommits = 0, presenceCommits = 0, adopted = 0, failed = 0,
  lastSlot = "-", lastName = "-", lastArmed = "-", lastTarget = "-",
  lastAdopted = "-",
}

function U.HotStats()
  return stats
end

-- The friendly unit a cast is going to, by pfUI's rule: the current target if
-- it can be assisted, otherwise the player (which is what an enemy target or no
-- target means for a helpful spell).
local function CastTargetName()
  local exists = Call("UnitExists", "target")
  if exists then
    local assist = Call("UnitCanAssist", "player", "target")
    if assist then
      local name = Call("UnitName", "target")
      if type(name) == "string" and name ~= "" then return name end
    end
  end

  local name = Call("UnitName", "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The target is captured here rather than at commit time because that is when
-- it is true: a Vanilla cast lands on whoever was targeted when it started,
-- and the player is free to retarget during Regrowth's cast.
local function SetPending(name)
  -- Through Tracking so the spellbook resolution has happened: SPELLCAST_START
  -- can be the first thing that ever asks about a HoT in a session.
  if not Tracking() then return end

  local entry = U.HotByName(name)
  if not entry then return end
  -- Resolved by id so an entry the player has not learned is ignored: the
  -- name table lists every locale, the spellbook says which one is real.
  local known = resolvedById[entry.id]
  if not known then return end

  local target = CastTargetName()
  if not target then return end

  pending = { entry = known, target = target, at = Now() }
  stats.armed = stats.armed + 1
  stats.lastArmed = known.id
  stats.lastTarget = target
end

-- Called through core/init.lua's action-press fan-out for every press
-- modules/actionbar.lua routes. Cheap for anyone who is not tracking a HoT: it
-- returns before the tooltip scan.
local function OnActionUsed(slot)
  if not Tracking() then return end

  slot = tonumber(slot)
  if not slot then return end

  stats.presses = stats.presses + 1
  stats.lastSlot = slot
  OpenAdoptWindow()

  local name = slotNames[slot]
  if name == nil then
    name = U.ActionSlotSpellName(slot) or false
    slotNames[slot] = name
  end
  if name then
    stats.named = stats.named + 1
    stats.lastName = name
    SetPending(name)
  end
end

U.RegisterActionUsed(OnActionUsed)

local RefreshAll

-- SPELLCAST_STOP path: the cast completed, so the HoT starts now. This is the
-- only signal for a spell with a cast time, and the fast path for an instant.
local function CommitPending()
  if not pending then return end

  local entry = pending
  pending = nil

  if Now() - entry.at > PENDING_WINDOW then return end

  stats.stopCommits = stats.stopCommits + 1
  Stamp(entry.target, entry.entry)
  RefreshAll()
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------
local MAX_BUFF_SLOTS = 32
local PARTY_COUNT = 4

local units = {}          -- unit token -> { anchor, frame, icons }

local function CreateIcon(holder, index)
  local size = U.GetHotSetting("size")

  local icon = CreateFrame("Frame", "UnrealUIHot" .. holder.unit .. index,
                           holder.frame)
  icon:SetWidth(size)
  icon:SetHeight(size)
  U.CreateBackdrop(icon, {})

  local texture = icon:CreateTexture(nil, "ARTWORK")
  texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  -- Same crop modules/auras.lua and modules/actionbar.lua use, so the addon
  -- outline is the only edge on screen.
  pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
  icon.texture = texture

  -- A raised child inset one unit: the wipe has to sit above the artwork, and
  -- a higher frame level is the only ordering this client guarantees between
  -- a texture and a frame (see modules/auras.lua's CreateIcon).
  --
  -- Explicitly sized, with a single corner anchor. modules/unitframes.lua's
  -- CreateBarBox records why: nothing in the compact DB establishes that
  -- two-corner anchoring actually resizes a *frame* on this client, and the
  -- wipe cannot survive that being false. U.SetRadialWipeProgress anchors its
  -- strips to LEFT/CENTER/RIGHT of this frame (core/style.lua, MoveWipeStrips),
  -- so a parent that reports zero width collapses the whole radial onto a
  -- point and draws nothing -- with the icon art underneath still perfectly
  -- visible, which is exactly what that failure looks like. PlaceIcon keeps
  -- both sizes current when the setting changes.
  local overlay = CreateFrame("Frame", nil, icon)
  overlay:SetWidth(size - 2)
  overlay:SetHeight(size - 2)
  overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  local levelOk, level = pcall(icon.GetFrameLevel, icon)
  if levelOk and tonumber(level) then
    pcall(overlay.SetFrameLevel, overlay, level + 5)
  end
  icon.overlay = overlay
  icon.wipe = U.CreateRadialWipe(overlay, { size = size - 2 })

  icon.count = U.CreateLabel(overlay, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if icon.count then
    icon.count:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
  end

  icon:Hide()
  holder.icons[index] = icon
  return icon
end

-- Corner placement. The two right-hand corners grow leftwards so the row always
-- runs into the bar rather than off it.
-- The holder tracks the health bar's real numbers rather than an anchor, so a
-- right-hand corner has a right edge to sit against. Re-read per placement
-- because the bar's width is a frame the module does not own.
local function SizeHolder(holder)
  local okW, width = pcall(holder.bar.GetWidth, holder.bar)
  local okH, height = pcall(holder.bar.GetHeight, holder.bar)
  width, height = okW and tonumber(width), okH and tonumber(height)
  if not width or width <= 0 or not height or height <= 0 then return false end

  if holder.width ~= width then
    holder.width = width
    holder.frame:SetWidth(width)
  end
  if holder.height ~= height then
    holder.height = height
    holder.frame:SetHeight(height)
  end
  return true
end

local function PlaceIcon(holder, icon, slot)
  local corner = U.GetHotSetting("corner")
  local size = U.GetHotSetting("size")
  local spacing = U.GetHotSetting("spacing")
  local step = (slot - 1) * (size + spacing)

  icon:ClearAllPoints()
  icon:SetWidth(size)
  icon:SetHeight(size)
  -- The overlay carries its own size for the reason CreateIcon states, so it
  -- has to be re-sized here rather than following the icon through an anchor.
  icon.overlay:SetWidth(size - 2)
  icon.overlay:SetHeight(size - 2)
  U.SizeRadialWipe(icon.wipe, size - 2)

  if corner == "TOPRIGHT" then
    icon:SetPoint("TOPRIGHT", holder.frame, "TOPRIGHT", -step, 0)
  elseif corner == "BOTTOMLEFT" then
    icon:SetPoint("BOTTOMLEFT", holder.frame, "BOTTOMLEFT", step, 0)
  elseif corner == "BOTTOMRIGHT" then
    icon:SetPoint("BOTTOMRIGHT", holder.frame, "BOTTOMRIGHT", -step, 0)
  else
    icon:SetPoint("TOPLEFT", holder.frame, "TOPLEFT", step, 0)
  end
end

local function Holder(unit)
  local holder = units[unit]
  if holder then return holder end

  local anchor = U.GetUnitFrame(unit)
  if not anchor or not anchor.health or not anchor.health.bar then return nil end

  -- Parented to the health bar itself, not the bar's box, so the icons sit
  -- inside the unit frame outline instead of on top of it.
  local bar = anchor.health.bar
  local frame = CreateFrame("Frame", "UnrealUIHotRow" .. unit, bar)
  local levelOk, level = pcall(bar.GetFrameLevel, bar)
  if levelOk and tonumber(level) then
    pcall(frame.SetFrameLevel, frame, level + 6)
  end
  -- Same caution as the overlay above: sized from the bar's own numbers and
  -- anchored at one corner, rather than trusting SetAllPoints to resize a frame
  -- on this client. The two right-hand corner options anchor against this
  -- frame's right edge, so a frame that reports zero width would stack every
  -- icon on the bar's left edge whatever corner was chosen.
  frame:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

  holder = { unit = unit, anchor = anchor, frame = frame, bar = bar, icons = {} }
  units[unit] = holder
  return holder
end

-- ---------------------------------------------------------------------------
-- Refresh
--
-- Two cadences, split for the same reason modules/auras.lua splits them:
-- reading the client is what costs, and the radial only needs arithmetic.
--
--   * The scan walks the buff slots, decides which icons exist and what they
--     show, and drops a stamp the unit no longer carries. It runs on
--     UNIT_AURA, on a slow fallback tick, and right after a cast is committed.
--   * The wipe tick moves the radials from the values the scan left behind and
--     touches no client API at all.
--
-- Both bail immediately when no party member carries a live stamp, which is the
-- case for everyone who is not currently healing.
-- ---------------------------------------------------------------------------

-- Every buff icon on one unit, folded to an icon key, from a single walk of the
-- slot range rather than one walk per tracked spell. Reused between units: this
-- is per-scan scratch, never state.
local present = {}

local function ReadBuffs(unit)
  local key
  for key in pairs(present) do present[key] = nil end

  local i
  for i = 1, MAX_BUFF_SLOTS do
    -- knowledge.json / auras.unit_aura_slots_may_be_sparse: an occupied slot
    -- can sit behind empty ones, so the whole range is walked rather than
    -- stopping at the first nil.
    local texture, count = Call("UnitBuff", unit, i)
    if texture then
      local iconKey = U.IconKey(texture)
      -- First occurrence wins. Two ranks of the same HoT cannot both be on a
      -- unit, so a second hit would only be a different spell sharing art.
      if iconKey and present[iconKey] == nil then
        present[iconKey] = tonumber(count) or 0
      end
    end
  end
end

local function HideFrom(holder, slot)
  local i
  for i = slot, table.getn(holder.icons) do
    if holder.icons[i] then holder.icons[i]:Hide() end
  end
end

local function ClearUnit(holder)
  holder.active = nil
  HideFrom(holder, 1)
end

-- The stamps this unit's character still has, or nil. Cheap enough to run on
-- every unit of every scan: it is one UnitName plus a few table reads, and it
-- is what keeps the slot walk off units with nothing to draw.
local function LiveStore(unit)
  local name = Call("UnitName", unit)
  if type(name) ~= "string" or name == "" then return nil end

  local store = stamps[name]
  if not store then return nil end

  local list = Resolved()
  local i
  for i = 1, table.getn(list) do
    if store[list[i].id] then return store end
  end
  return nil
end

local function ScanUnit(unit)
  local holder = Holder(unit)
  if not holder then return end

  if not Tracking() or not Call("UnitExists", unit) or
     U.UnitObjectVisible(unit) == false then
    ClearUnit(holder)
    return
  end

  local now = Now()
  -- Inside the window the unit is read even with nothing stamped, because that
  -- read is what finds the HoT to adopt. Outside it the walk is skipped for a
  -- unit carrying none of ours, which is what keeps the idle cost at nothing.
  local adopting = (now - lastCast) <= ADOPT_WINDOW

  local store = LiveStore(unit)
  if not store and not adopting then
    ClearUnit(holder)
    return
  end

  ReadBuffs(unit)

  local list = Resolved()
  local i

  if adopting then
    local name = Call("UnitName", unit)
    for i = 1, table.getn(list) do
      local entry = list[i]
      -- Unstamped and present: this HoT arrived without the precise path
      -- seeing the cast that placed it. Dated from the cast rather than from
      -- this tick, so a HoT found half a second late is not shown half a
      -- second long.
      if present[entry.key] ~= nil and not (store and store[entry.id]) then
        Stamp(name, entry, lastCast)
        stats.adopted = stats.adopted + 1
        stats.lastAdopted = entry.id .. "@" .. tostring(name)
        store = type(name) == "string" and stamps[name] or store
      end
    end
  end

  if not store then
    ClearUnit(holder)
    return
  end

  SizeHolder(holder)

  local active = {}

  for i = 1, table.getn(list) do
    local entry = list[i]
    local live = store[entry.id]
    if live then
      local count = present[entry.key]
      if count == nil then
        -- Dispelled, overwritten, expired or never landed. One rule covers all
        -- four, and none of them needs an event of its own.
        store[entry.id] = nil
      elseif now - live.start >= live.duration and live.extended then
        -- A second overrun is no longer explained by a set bonus. What it looks
        -- like instead is another healer's copy of the same HoT sitting on this
        -- unit under our expired stamp -- and no caster is recoverable to tell
        -- the two apart. Drop it: showing nothing is the honest answer, and an
        -- unbounded restart would credit their HoT to us forever.
        store[entry.id] = nil
      else
        if now - live.start >= live.duration then
          -- Still on the unit past its base duration. The one thing that
          -- explains that for a HoT we really did cast is a duration set bonus
          -- (Stormrage 8-piece, Transcendence 5-piece), which core/hotdata.lua
          -- deliberately does not detect. Restart once rather than drop what is
          -- visibly still there; the branch above bounds it.
          live.start = now
          live.extended = true
        end

        local slot = table.getn(active) + 1
        local icon = holder.icons[slot] or CreateIcon(holder, slot)
        PlaceIcon(holder, icon, slot)
        icon.texture:SetTexture(entry.texture)
        if icon.count then
          if count > 1 then
            icon.count:SetText(count)
            icon.count:Show()
          else
            icon.count:Hide()
          end
        end
        icon:Show()

        table.insert(active, { icon = icon, live = live })
      end
    end
  end

  holder.active = active
  HideFrom(holder, table.getn(active) + 1)
end

-- The party token currently holding this character, or nil.
local function PartyUnitFor(name)
  local i
  for i = 1, PARTY_COUNT do
    local unit = "party" .. i
    if Call("UnitName", unit) == name then return unit end
  end
  return nil
end

-- The fallback commit, and the reason an instant HoT is not at the mercy of one
-- unmeasured event. SPELLCAST_STOP is observed 40 times against SPELLCAST_START's
-- 34 (events.json), which is consistent with instants raising STOP and no START
-- -- but "consistent with" is not measured, and if this client turns out not to
-- raise STOP for an instant cast then Rejuvenation and Renew would never commit
-- at all.
--
-- So presence commits too: if the intended target is now carrying the spell's
-- icon, the cast landed, whatever the client did or did not announce. The stamp
-- is dated from the cast rather than from this check, so a HoT found on the
-- half-second tick is not shown half a second long.
--
-- This cannot invent a stamp for someone else's HoT: it only ever fires inside
-- the few seconds after this player cast that exact spell at that exact
-- character.
local function CommitByPresence()
  if not pending then return end

  if Now() - pending.at > PENDING_WINDOW then
    pending = nil
    return
  end

  local unit = PartyUnitFor(pending.target)
  if not unit then return end

  ReadBuffs(unit)
  if present[pending.entry.key] == nil then return end

  stats.presenceCommits = stats.presenceCommits + 1
  Stamp(pending.target, pending.entry, pending.at)
  pending = nil
end

RefreshAll = function()
  CommitByPresence()

  local i
  for i = 1, PARTY_COUNT do
    ScanUnit("party" .. i)
  end
end

-- Arithmetic only. An icon whose stamp has run out is left at a full wipe until
-- the next scan decides whether the aura is really gone or the duration was
-- simply short (see the set-bonus case above).
local function TickWipes()
  local now = Now()
  local unit, holder

  for unit, holder in pairs(units) do
    local active = holder.active
    if active then
      local i
      for i = 1, table.getn(active) do
        local slot = active[i]
        local progress = (now - slot.live.start) / slot.live.duration
        if progress > 1 then progress = 1 end
        U.SetRadialWipeProgress(slot.icon.wipe, progress)
      end
    end
  end
end

ApplyIndicators = function()
  -- Geometry is re-read on every placement, so re-running the scan is all a
  -- settings change needs.
  RefreshAll()
  TickWipes()
end

function U.ApplyHotIndicators()
  ApplyIndicators()
end
-- ---------------------------------------------------------------------------
-- Diagnostic
--
-- Printed to chat by "/uui hot". Two things in this module are reasoned from
-- the compact evidence rather than measured on this client, and both are
-- visible here rather than needing a probe run:
--
--   * Whether each tracked HoT resolved to a real spellbook texture. A spell
--     the player has that prints "unresolved" means U.SpellIconByName found no
--     name match -- a locale missing from core/hotdata.lua's name list.
--   * Whether the spellbook's icon key and the unit's UnitBuff icon key agree.
--     UnitBuff's UAsset form is measured; GetSpellTexture's is not, and
--     U.IconKey exists to make the comparison survive either. A resolved spell
--     with a live stamp and no matching party buff is that assumption failing.
--
-- Reads only; nothing here changes a stamp or an icon.
-- ---------------------------------------------------------------------------
function U.HotDebugDump()
  U.Print("unrealUI HoT indicators")
  U.Print("  enabled: " .. tostring(U.GetHotSetting("enabled")) ..
          "  corner: " .. tostring(U.GetHotSetting("corner")) ..
          "  size: " .. tostring(U.GetHotSetting("size")) ..
          "  spacing: " .. tostring(U.GetHotSetting("spacing")))

  local spells = U.HotSpells()
  local list = Resolved()
  local i, n

  U.Print("  spellbook:")
  for i = 1, table.getn(spells) do
    local entry = resolvedById[spells[i].id]
    if entry then
      U.Print("    " .. spells[i].id .. ": " .. entry.name .. "  key=" ..
              tostring(entry.key) .. "  " .. tostring(entry.duration) .. "s")
    else
      U.Print("    " .. spells[i].id .. ": unresolved (not in this spellbook)")
    end
  end

  if pending then
    U.Print("  pending: " .. pending.entry.id .. " -> " .. pending.target ..
            "  " .. string.format("%.1f", Now() - pending.at) .. "s ago")
  else
    U.Print("  pending: none")
  end

  -- Which link of the cast chain a press actually reached. presses counts
  -- unrealUI action-button presses this module was told about; named counts
  -- those whose slot the tooltip scan could identify; armed counts those that
  -- were a HoT this character has. Zero presses means the cast is not coming
  -- through modules/actionbar.lua at all.
  U.Print("  casts: presses=" .. stats.presses ..
          " named=" .. stats.named ..
          " armed=" .. stats.armed ..
          " commit(stop)=" .. stats.stopCommits ..
          " commit(seen)=" .. stats.presenceCommits ..
          " adopted=" .. stats.adopted ..
          " failed=" .. stats.failed)
  U.Print("    last: slot=" .. tostring(stats.lastSlot) ..
          " name=" .. tostring(stats.lastName) ..
          " armed=" .. tostring(stats.lastArmed) ..
          " target=" .. tostring(stats.lastTarget) ..
          " adopted=" .. tostring(stats.lastAdopted))
  U.Print("    adopt window: " .. string.format("%.1f", Now() - lastCast) ..
          "s since last cast signal (window " .. ADOPT_WINDOW .. "s)")

  local now = Now()
  for i = 1, PARTY_COUNT do
    local unit = "party" .. i
    local name = Call("UnitName", unit)
    if not Call("UnitExists", unit) then
      U.Print("  " .. unit .. ": absent")
    else
      U.Print("  " .. unit .. ": " .. tostring(name) ..
              "  visible=" .. tostring(U.UnitObjectVisible(unit)))

      local store = type(name) == "string" and stamps[name] or nil
      for n = 1, table.getn(list) do
        local live = store and store[list[n].id]
        if live then
          U.Print("      stamp " .. list[n].id .. ": " ..
                  string.format("%.1f", now - live.start) .. "/" ..
                  tostring(live.duration) .. "s" ..
                  (live.extended and " (extended)" or ""))
        end
      end

      -- The buff side of the comparison. Every key the unit's own UnitBuff walk
      -- produced is printed, not just the tracked ones: an empty line here and
      -- a visibly buffed party member means UnitBuff answers nothing for a
      -- party token on this client, which is a different problem from the
      -- spell simply not being up. The first raw path is printed with it so the
      -- exact string U.IconKey is folding is visible rather than inferred.
      ReadBuffs(unit)

      local keys, count, m = "", 0, nil
      for m in pairs(present) do
        count = count + 1
        if count <= 12 then keys = keys .. " " .. m end
      end
      if count == 0 then keys = " none" end
      U.Print("      buff keys (" .. count .. "):" .. keys)

      local raw = Call("UnitBuff", unit, 1)
      U.Print("      UnitBuff(" .. unit .. ", 1) = " .. tostring(raw))

      -- The geometry the radial depends on. A holder or wipe reporting 0 here
      -- is why an icon would draw with no sweep over it.
      local holder = units[unit]
      if holder then
        local icon = holder.icons[1]
        U.Print("      holder " .. tostring(holder.width) .. "x" ..
                tostring(holder.height) ..
                "  icon1 overlay=" ..
                (icon and tostring(icon.overlay:GetWidth()) or "-") ..
                " wipe=" .. (icon and tostring(icon.wipe.size) or "-"))
      end

      local tracked = ""
      for m = 1, table.getn(list) do
        if present[list[m].key] ~= nil then
          tracked = tracked .. " " .. list[m].key
        end
      end
      if tracked == "" then tracked = " none" end
      U.Print("      tracked:" .. tracked)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Settings section
--
-- Rendered inside the Party Frames sub-page (modules/unitframes.lua) rather
-- than owning a page of its own: these controls describe the party frames, and
-- the settings window's category list is where a page boundary belongs, not a
-- four-control section.
--
-- `y` is where the caller wants this section's heading, so the party page can
-- move it without this file knowing what sits above it.
-- ---------------------------------------------------------------------------
local SETTINGS_COLUMN_X = 258
local SETTINGS_SLIDER_WIDTH = 200

local SLIDERS = {
  { key = "size",    textKey = "HOTS_SIZE",    column = 0 },
  { key = "spacing", textKey = "HOTS_SPACING", column = 1 },
}

function U.BuildHotSettings(parent, y, width)
  y = y or -4
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("HOTS_HEADER"),
    width = width or 484,
    y = y,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsHotEnabled",
    text = U.L("HOTS_ENABLED"),
    textWidth = SETTINGS_COLUMN_X - 26,
    value = U.GetHotSetting("enabled"),
    onChange = function(value) U.SetHotSetting("enabled", value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 30)
  controls.enabled = enable
  table.insert(widgets, enable)

  local cornerLabel = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    width = 240,
    height = 14,
    justify = "LEFT",
  })
  if cornerLabel then
    cornerLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 60)
    cornerLabel:SetText(U.L("HOTS_CORNER"))
    table.insert(widgets, cornerLabel)
  end

  local items = {}
  local corners = U.HotCorners()
  local i
  for i = 1, table.getn(corners) do
    table.insert(items, {
      value = corners[i].value,
      text = U.L(corners[i].textKey),
    })
  end

  local corner = U.CreateDropdown(parent, {
    name = "UnrealUISettingsHotCorner",
    width = 240,
    height = 24,
    rowHeight = 20,
    value = U.GetHotSetting("corner"),
    items = items,
    onChange = function(value) U.SetHotSetting("corner", value) end,
  })
  corner.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 78)
  controls.corner = corner
  table.insert(widgets, corner)

  for i = 1, table.getn(SLIDERS) do
    local spec = SLIDERS[i]
    local min, max, step = U.HotLimits(spec.key)

    local slider = U.CreateSlider(parent, {
      name = "UnrealUISettingsHot" .. spec.key,
      text = U.L(spec.textKey),
      width = SETTINGS_SLIDER_WIDTH,
      min = min,
      max = max,
      step = step,
      value = U.GetHotSetting(spec.key),
      onChange = function(value) U.SetHotSetting(spec.key, value) end,
    })
    slider.SetPoint("TOPLEFT", parent, "TOPLEFT",
                    spec.column * SETTINGS_COLUMN_X, y - 124)
    controls[spec.key] = slider
    table.insert(widgets, slider)
  end

  local function Refresh()
    controls.enabled.SetValue(U.GetHotSetting("enabled"))
    controls.corner.SetValue(U.GetHotSetting("corner"))
    local n
    for n = 1, table.getn(SLIDERS) do
      local key = SLIDERS[n].key
      if controls[key] then controls[key].SetValue(U.GetHotSetting(key)) end
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function H:OnEnable()
  U.RegisterEvent("SPELLCAST_START", function(event, name)
    OpenAdoptWindow()
    SetPending(name)
  end)
  U.RegisterEvent("SPELLCAST_STOP", function()
    OpenAdoptWindow()
    CommitPending()
    -- Straight away rather than on the next tick: for an instant cast the aura
    -- is already on the unit by the time this fires.
    RefreshAll()
  end)

  local cancelled = { "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED" }
  local i
  for i = 1, table.getn(cancelled) do
    U.RegisterEvent(cancelled[i], function()
      if pending then stats.failed = stats.failed + 1 end
      pending = nil
    end)
  end

  -- The spellbook decides which HoTs exist for this character, and an action
  -- slot's spell can change under a cached name. Both caches are cheap to drop.
  local invalidate = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }
  for i = 1, table.getn(invalidate) do
    U.RegisterEvent(invalidate[i], function()
      resolvedBuilt = false
      slotNames = {}
    end)
  end
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", function() slotNames = {} end)

  U.RegisterEvent("UNIT_AURA", function(event, unit)
    if type(unit) == "string" and string.find(unit, "^party%d") then
      ScanUnit(unit)
    end
  end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() RefreshAll() end)

  local roster = { "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }
  for i = 1, table.getn(roster) do
    U.RegisterEvent(roster[i], function()
      U.DeferOnce("hots.roster-refresh", function() RefreshAll() end)
    end)
  end

  -- The slow half. UNIT_AURA normally makes this redundant, but the compact
  -- evidence has only ever captured that event for "target" (events.json,
  -- events.UNIT_AURA.v1), and party roster events are accepted but unobserved
  -- on this client -- the same reason modules/auras.lua keeps a 1s party
  -- fallback beside its own event registration. 0.5s because this is also what
  -- notices a HoT falling off, which nothing else reports.
  U.RegisterUpdate("hots.scan", 0.5, function()
    if Tracking() then RefreshAll() end
  end)

  -- The fast half: no client calls at all, so the radial can move at the same
  -- 0.1s the aura timers and the action buttons use.
  U.RegisterUpdate("hots.wipe", 0.1, function() TickWipes() end)

  RefreshAll()
end
