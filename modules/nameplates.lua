-- unrealUI :: modules/nameplates.lua
--
-- Replaces the client's floating nameplate art with unrealUI's own overlay:
--
--   Name .............................. Level
--   [==============  100.0%  ==============]
--
-- Name is anchored to the bar's left edge, level (difficulty coloured) to its
-- right edge, and the health percentage sits centred inside the bar. That is
-- the requested target layout; it is deliberately *not* pfUI's nameplate
-- layout, which centres the name over the plate and puts the level outside the
-- bar's left edge.
--
-- The options follow ShaguPlates' nameplate settings where they fit this
-- client (diagnostics/shaguplates-index; NAMEPLATES_ROADMAP.md tracks what is
-- done and what is not): sizes, hostile/friendly visibility, health text
-- format, per-disposition health-bar hiding, target outline and zoom,
-- reaction outlines, raid icons and name abbreviation. The settings pages are
-- modules/nameplatesettings.lua. Combo points, totem icons, class colours,
-- combat-state colours, click handling and mouselook are not here.
--
-- Compatibility notes that shaped this file:
--
--   * query_compat.py has NO record for nameplates, WorldFrame:GetChildren,
--     GetNumChildren, HookScript, ShowNameplates or the nameplate frame shape on
--     this client. Per the evidence-gap rule the discovery path follows what
--     UnrealPfUI does (modules/nameplates.lua: poll WorldFrame's children, take
--     the plate's regions and StatusBar children, read health from the native
--     bar). That is WORKING_SOURCE evidence, not runtime verification.
--   * UnrealPfUI keys the plate's parts off a fixed region *order*
--     (NAMEPLATE_OBJECTORDER) and a fixed border texture path. This client's
--     stock nameplate does not look like Vanilla's -- the observed plate draws a
--     name and a level and no health bar at all -- so an assumed order would map
--     the wrong region. Parts are therefore classified by what they actually
--     are (FontString vs Texture vs StatusBar child, and the texture's own
--     path), and everything unrecognised is muted. U.NameplateReport() prints
--     what was found so the guess can be replaced with measurement.
--   * A plate with no usable native health bar still gets a name/level row; the
--     bar is simply hidden rather than drawn empty.
--   * knowledge.json / scripts.child_onupdate_unreliable: no frame built here
--     owns an OnUpdate, and no script is hooked onto a native plate. Discovery
--     and refresh both run on the shared U.RegisterUpdate driver.
--   * knowledge.json / statusbar.native_widget_fill_not_laid_out: the bar is
--     U.CreateStatusBar, not the client's StatusBar widget.
--   * knowledge.json / rendering.native_texture_strip_requires_alpha: native
--     plate art is muted with SetTexture(nil) + SetAlpha(0) but deliberately
--     *not* Hide()d -- IsShown() on the native glow and elite icon is still the
--     only signal for mouseover and elite status.
--   * knowledge.json / fonts.stretched_justification_ignored: every label is
--     anchored to the one edge it belongs to, never stretched corner to corner.
--   * knowledge.json / core.getdifficultycolor_missing: level colour is taken
--     from the native level fontstring when it has one, with a local difficulty
--     helper as the fallback. No shim global is installed.

local U = UnrealUI
local M = U.media

local NP = U.RegisterModule("nameplates")
local PLATE_LIFT = 14

-- ---------------------------------------------------------------------------
-- Configuration
--
-- Sizes are in plate units, before the UI scale the overlay inherits below.
-- ---------------------------------------------------------------------------
local defaults = {
  enabled        = true,
  width          = 160,
  healthHeight   = 17,
  -- Modern WoW's bar height, in art units before its `scale`; the art
  -- stretches on each axis (style.LayoutArt), so it defaults to the authored
  -- height and the slider moves it from there.
  artHealthHeight = M.modernWow.nameplate.healthHeight,
  nameSize       = 12,
  levelSize      = 12,
  healthTextSize = 11,
  verticalOffset = 0,
  showHealthText = true,
  showName       = true,   -- the unit's name above the bar
  showAuras      = true,
  attachTargetCast = true,
  fadeOthers     = true,   -- dim plates that are not the current target
  otherAlpha     = 0.75,

  -- The client's own enemy/friendly plate switches, applied on login and on
  -- change (ShowNameplates & co. are documented, not runtime-verified here).
  showHostile    = true,
  showFriendly   = false,

  -- percent | current | curmax | curperc | deficit
  healthFormat   = "curmax",
  healthTextPos  = "CENTER", -- LEFT | CENTER | RIGHT
  abbrevNumbers  = false,    -- 4200 -> 4.2k
  abbrevNames    = false,    -- "Defias Pillager Captain" -> "D. P. Captain"

  -- Health bar hidden per disposition; the name and level row stays.
  hideEnemyNpc       = false,
  hideEnemyPlayer    = false,
  hideNeutralNpc     = false,
  hideFriendlyNpc    = false,
  hideFriendlyPlayer = false,
  keepHealthTarget   = true,  -- exceptions to the above
  keepHealthDamaged  = true,

  -- Target emphasis. The outline is the flat themes' 1-unit edge and Modern
  -- WoW's tinted selected-plate art (style.RefreshOutline). Colours are flat
  -- numbers: U.ModuleConfig copies a default table by reference.
  targetOutline  = false,
  highlightR     = M.color.accent[1],
  highlightG     = M.color.accent[2],
  highlightB     = M.color.accent[3],
  targetZoom     = false,
  targetZoomPercent = 25,

  -- Reaction outlines, drawn in the plate's reaction colour.
  outlineEnemy          = false,
  outlineNeutral        = false,
  outlineFriendlyNpc    = false,
  outlineFriendlyPlayer = false,

  -- Class colours for players named in core/playercache.lua.
  classColorEnemy        = true,
  classColorFriendly     = true,
  classColorFriendlyName = false,
  showGuild              = false,  -- guild line under the bar

  -- Totems (style.TotemIcon): hide their bar, or draw their icon instead.
  hideTotemHealth = true,
  totemIcons      = false,
  totemSize       = 24,
  hideCritterHealth = true,  -- style.IsCritter

  -- Combo points under the target's bar, filled points only.
  comboPoints    = true,
  comboSize      = 8,

  raidIcon       = true,
  raidIconPos    = "LEFT",    -- LEFT | TOP | RIGHT of the health bar
  raidIconSize   = 16,
  raidIconX      = 0,
  raidIconY      = 0,
}

-- Option behaviour (see ShaguPlates' nameplate settings); one table so the
-- file's top-level local budget only pays once for it.
local style = {}

local cfg = defaults
local targetPlateActive = false
local targetOverlay = nil

function U.NameplatesEnabled()
  return U.ModuleConfig("nameplates", defaults).enabled and true or false
end

function U.SetNameplatesEnabled(value)
  value = value and true or false
  local settings = U.ModuleConfig("nameplates", defaults)
  if settings.enabled == value then return value end
  settings.enabled = value

  U.ShowConfirm({
    owner = "nameplates.enable-reload",
    centered = true,
    text = U.L("SETTINGS_NAMEPLATES_CHANGED"),
    detail = value and U.L("SETTINGS_NAMEPLATES_RELOAD_ON")
                   or U.L("SETTINGS_NAMEPLATES_RELOAD_OFF"),
    acceptText = U.L("COMMON_OK_SHORT"),
    cancelText = U.L("COMMON_CLOSE"),
  })
  return value
end

function U.NameplateTargetCastbarActive()
  return cfg.enabled and cfg.attachTargetCast and targetPlateActive
end

-- Read and written by modules/nameplatesettings.lua. A write is coerced to the
-- default's type, then every plate is re-laid-out and redrawn at once so a
-- slider drag shows on the world immediately.
function U.NameplateSetting(key)
  return cfg[key]
end

function U.SetNameplateSetting(key, value)
  local default = defaults[key]
  if default == nil then return end
  if type(default) == "boolean" then
    value = value and true or false
  elseif type(default) == "number" then
    value = tonumber(value) or default
  elseif type(value) ~= type(default) then
    return
  end
  local settings = U.ModuleConfig("nameplates", defaults)
  settings[key] = value
  cfg = settings
  if key == "showHostile" or key == "showFriendly" then
    style.ApplyVisibility()
  end
  style.Invalidate()
end

-- ---------------------------------------------------------------------------
-- Colours
--
-- Chosen by reaction (see "Reaction, remembered by creature name" below) and
-- drawn in unrealUI's muted palette rather than the client's saturated
-- primaries. UnitTypeFromBarColor is UnrealPfUI's tint route; it only feeds
-- /uui np's report, because this client has no GetStatusBarColor.
-- ---------------------------------------------------------------------------
local UNIT_COLOR = {
  ENEMY         = { 0.75, 0.27, 0.32, 1.00 },
  NEUTRAL       = { 0.80, 0.72, 0.26, 1.00 },
  FRIENDLY_NPC  = { 0.35, 0.66, 0.34, 1.00 },
  FRIENDLY_UNIT = { 0.26, 0.50, 0.82, 1.00 },
}

local function UnitTypeFromBarColor(r, g, b)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    return nil
  end
  if r > 0.8 and g < 0.3 and b < 0.3 then return "ENEMY" end
  if r > 0.8 and g > 0.8 and b < 0.3 then return "NEUTRAL" end
  if r < 0.3 and g > 0.8 and b < 0.3 then return "FRIENDLY_NPC" end
  if r < 0.3 and g < 0.3 and b > 0.8 then return "FRIENDLY_UNIT" end
  return nil
end

-- ---------------------------------------------------------------------------
-- API access
--
-- Same contract as modules/unitframes.lua: resolve by name once, pcall the
-- call, coerce the result. Nothing here assumes a Vanilla return shape.
-- ---------------------------------------------------------------------------
local apiFnCache = {}

local function ResolveApiFn(name)
  local cached = apiFnCache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local fn = U.G(name)
  if type(fn) == "function" then
    apiFnCache[name] = fn
    return fn
  end
  apiFnCache[name] = false
  return nil
end

local function ApiNumber(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, value = pcall(fn, a, b)
  if not ok then return nil end
  return tonumber(value)
end

local function ApiString(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, value = pcall(fn, a, b)
  if not ok or type(value) ~= "string" then return nil end
  return value
end

local function ApiTruth(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return false end
  local ok, value = pcall(fn, a, b)
  if not ok then return false end
  if value == nil or value == false or value == 0 or value == "" then
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Reaction, remembered by creature name
--
-- This client has no GetStatusBarColor (documented, and the /uui np dump read
-- nothing back on 2026-10-19), so a plate carries no reaction signal of its
-- own. A unit token does: the target and the mouseover are classified each
-- pass and remembered by name, and every plate with that name takes the same
-- colour. A name never seen keeps the hostile default.
-- ---------------------------------------------------------------------------
-- player: name -> whether the unit seen live under it was a player, for the
-- per-disposition health-bar hiding (style.IsPlayer).
local reaction = { byName = {}, player = {} }

function reaction.Classify(unit)
  if not ApiTruth("UnitExists", unit) then return nil end
  if ApiTruth("UnitIsPlayer", unit) and
     not ApiTruth("UnitCanAttack", "player", unit) then
    return "FRIENDLY_UNIT"
  end
  local value = ApiNumber("UnitReaction", unit, "player")
  if not value then return nil end
  if value <= 3 then return "ENEMY" end
  if value == 4 then return "NEUTRAL" end
  return "FRIENDLY_NPC"
end

function reaction.Learn(unit)
  local unitType = reaction.Classify(unit)
  local name = unitType and ApiString("UnitName", unit)
  if name then
    reaction.byName[name] = unitType
    reaction.player[name] = ApiTruth("UnitIsPlayer", unit)
  end
end

-- A name not yet seen live: its base reaction from Database/unit_reactions.lua
-- (tools/import_unit_reactions.py, VMaNGOS faction templates), found through
-- the bundled creature-name index U.unitNames (name -> id, or a list of ids).
-- Every id sharing the name must agree, else nil. Cached per name, false for
-- a name the tables cannot answer (players, unknown creatures).
reaction.LETTER = { H = "ENEMY", N = "NEUTRAL", F = "FRIENDLY_NPC" }
reaction.fromDb = {}

function reaction.Letter(id)
  local value = U.unitReactions.byId[id] or "H"
  if string.len(value) == 1 then return value end
  -- Eight letters, in UnitRace's numeric order (knowledge:
  -- unit.race_class_return_numeric_id).
  if not reaction.race then
    local fn = ResolveApiFn("UnitRace")
    local ok, _, _, raceId
    if fn then ok, _, _, raceId = pcall(fn, "player") end
    reaction.race = ok and tonumber(raceId) or 0
  end
  if reaction.race < 1 or reaction.race > 8 then return nil end
  return string.sub(value, reaction.race, reaction.race)
end

function reaction.FromDatabase(name)
  local cached = reaction.fromDb[name]
  if cached ~= nil then return cached or nil end
  local result = false
  local names = U.unitNames
  if type(names) == "table" and type(U.unitReactions) == "table" then
    local entry = names[name]
    local letter
    if type(entry) == "number" then
      letter = reaction.Letter(entry)
    elseif type(entry) == "table" then
      local i
      for i = 1, table.getn(entry) do
        local one = reaction.Letter(entry[i])
        if not one or (letter and one ~= letter) then
          letter = nil
          break
        end
        letter = one
      end
    end
    result = letter and reaction.LETTER[letter] or false
  end
  reaction.fromDb[name] = result
  return result or nil
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
-- Reads a method off a widget and calls it with no arguments. Every native
-- plate part is touched through here: the object may not have the method at
-- all on this client, and indexing a widget that is not a table would error
-- before the pcall around the call itself could help.
--
-- Deliberately argument-free. Lua 5.0's implicit `arg` table is not something
-- this runtime is verified to provide, so a vararg forwarder would be its own
-- unverified assumption; nothing here needs one.
--
-- The field read is a named upvalue rather than an anonymous closure: this runs
-- for every part of every plate five times a second, and building a closure per
-- call was the same allocation round 2 of
-- knowledge.json / compat.native_suppression_pcall_burst_stutter hoisted out of
-- core/compat.lua's sweep. The pcall boundary is unchanged -- the read still
-- fails independently of the call.
local readTarget, readMethod, readResult

local function ReadMethod()
  readResult = readTarget[readMethod]
end

local function Call(object, method)
  if not object then return nil end
  readTarget, readMethod, readResult = object, method, nil
  local ok = pcall(ReadMethod)
  local fn = readResult
  readTarget, readResult = nil, nil
  if not ok or type(fn) ~= "function" then return nil end
  local ok2, a, b, c, d = pcall(fn, object)
  if not ok2 then return nil end
  return a, b, c, d
end

local function ObjectType(object)
  local value = Call(object, "GetObjectType")
  if type(value) == "string" then return value end
  return nil
end

local function Clamp(value)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

-- knowledge.json / core.getdifficultycolor_missing. Only used when the native
-- level fontstring has no colour to copy. Bands, colours and the
-- GetQuestGreenRange grey cut-off are kept identical to the unit frames'
-- DifficultyColor (modules/unitframes.lua) so the two never disagree about the
-- same mob; keep them in step if either is changed.
local function DifficultyColor(level)
  level = tonumber(level) or 0
  local playerLevel = ApiNumber("UnitLevel", "player") or 1
  local greenRange = ApiNumber("GetQuestGreenRange")
  if not greenRange or greenRange <= 0 then greenRange = 7 end

  if level <= 0 then return 0.69, 0.69, 0.69 end

  local diff = level - playerLevel
  if diff >= 5 then return 1.00, 0.10, 0.10 end
  if diff >= 3 then return 1.00, 0.50, 0.25 end
  if diff >= -2 then return 1.00, 1.00, 0.00 end
  if -diff <= greenRange then return 0.25, 0.75, 0.25 end
  return 0.50, 0.50, 0.50
end

-- Native plate art is silenced, not removed: IsShown() on the glow and the
-- elite icon stays the only readable signal for mouseover and classification.
-- rendering.native_texture_strip_requires_alpha is why the alpha is zeroed as
-- well as the texture cleared.
local function MuteTexture(region)
  if not region then return end
  pcall(function() region:SetTexture(nil) end)
  pcall(function() region:SetTexCoord(0, 0, 0, 0) end)
  pcall(function() region:SetAlpha(0) end)
end

local function MuteFontString(region)
  if not region then return end
  -- GetText() must keep working: the name and level are read back off these.
  local invisible = M.fontById and M.fontById.invisible
  if invisible then
    local _, size, flags = Call(region, "GetFont")
    pcall(function()
      region:SetFont(invisible.path, tonumber(size) or cfg.levelSize, flags)
    end)
  end
  pcall(function() region:SetAlpha(0) end)
end

-- A native bar frame plus its own regions: parent_alpha_not_propagated means
-- zeroing the frame alone is not enough to stop the fill drawing.
local function MuteBar(bar)
  if not bar then return end
  -- Keep the native widget logically shown. The client owns its lifecycle and
  -- health updates; hiding it can make the owning nameplate disappear.
  -- knowledge.json rendering.statusbar_alpha_does_not_fade_fill: widget alpha
  -- leaves the fill drawn, and so did a nil fill texture and a zero vertex
  -- alpha (user-confirmed 2026-10-19: the stock yellow bar stayed, then a
  -- blinking 1px line once its height was collapsed). A fully transparent fill
  -- texture draws nothing whatever the tint, and the tint itself is left alone:
  -- the plate's unit type is read back from it. Re-applied on every refresh
  -- via MuteNativePlate, since the client may restore its own fill.
  pcall(function() bar:SetStatusBarTexture(M.texture.clear) end)
  pcall(function() bar:SetAlpha(0) end)
  -- Belt and braces: collapse both dimensions, so a fill the client redraws
  -- before the next refresh is a sub-pixel dot rather than a line.
  -- GetValue/GetMinMaxValues do not depend on its size.
  pcall(function() bar:SetHeight(0.01) end)
  pcall(function() bar:SetWidth(0.01) end)

  local ok, regions = pcall(function() return { bar:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return end
  local i
  for i = 1, table.getn(regions) do
    if ObjectType(regions[i]) == "Texture" then MuteTexture(regions[i]) end
  end
end

local function MuteNativePlate(parts, plate, overlay)
  if not parts then return end

  MuteBar(parts.healthbar)
  MuteBar(parts.castbar)

  local i
  for i = 1, table.getn(parts.textures) do
    local region = parts.textures[i]
    if region == parts.raidicon then
      -- Alpha only: its texture cell is what style.RaidIndex reads the mark
      -- from, so clearing it would erase the one signal. Same walk, same
      -- wrapper object, so the identity test holds here.
      pcall(function() region:SetAlpha(0) end)
    else
      MuteTexture(region)
    end
  end
  for i = 1, table.getn(parts.fontstrings) do
    MuteFontString(parts.fontstrings[i])
  end

  -- Native aura buttons may be added after the plate was first classified.
  -- Hide every direct native child while leaving UnrealUI's owned overlay.
  local ok, children = pcall(function() return { plate:GetChildren() } end)
  if not ok or type(children) ~= "table" then return end

  for i = 1, table.getn(children) do
    local child = children[i]
    local childName = Call(child, "GetName")
    local owned = child == overlay or
                  (type(childName) == "string" and
                   string.find(childName, "^UnrealUINamePlate"))
    local nativeBar = child == parts.healthbar or child == parts.castbar
    if not owned and not nativeBar then
      pcall(function() child:Hide() end)
      pcall(function() child:SetAlpha(0) end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Plate discovery
--
-- WORKING_SOURCE (UnrealPfUI modules/nameplates.lua): nameplates are anonymous
-- children of WorldFrame and appear as the child count grows. The *shape* test
-- upstream uses -- first region's texture is Interface\Tooltips\Nameplate-Border
-- -- is not reused, because this client's plate visibly is not Vanilla's.
-- Classification is structural instead.
-- ---------------------------------------------------------------------------
local registry = {}      -- native plate frame -> overlay
local plateOrder = {}    -- stable iteration order for the refresh pass
local scannedChildren = 0
local plateCount = 0

local stats = {
  worldChildren = 0,
  plates = 0,
  rejected = 0,
  withHealthBar = 0,
  detector = "none",
  -- Lowest and highest WorldFrame child count seen this session. This is the
  -- decisive measurement for whether nameplates are Lua frames here at all: if
  -- the count never moves while plates appear and disappear on screen, they are
  -- not WorldFrame children and no overlay approach can reach them.
  minChildren = -1,
  maxChildren = 0,
  -- A recycled plate shown again, and which stock parts the client had
  -- restored by the time WatchPlates saw it, before it is muted again. Tells
  -- a reuse flash (client restores art) from a creation flash (a new plate
  -- drawn once before any Lua runs). Read by UnrealRuntimeProbe npflicker.
  reuse = { shows = 0, font = 0, fontAlpha = 0, texture = 0,
            textureAlpha = 0, barTall = 0, barAlpha = 0 },
}

-- Why a WorldFrame child was not adopted. Measured first-pass result on this
-- client: 28 children, 0 plates, 28 rejected -- so the reason has to be
-- reportable rather than inferred from the layout not changing.
local rejectReasons = {}

-- Build and refresh failures are pcall'd so a broken plate cannot take the
-- world down with it, which also means they never reach the player. /uui np
-- reads them from here instead of from a debug chat line nobody saw.
local failures = { build = 0, refresh = 0 }

-- WorldFrame children that appeared after login, capped (see ScanWorldFrame).
local arrivals = {}
local ARRIVAL_LIMIT = 12

local function Reject(reason)
  rejectReasons[reason] = (rejectReasons[reason] or 0) + 1
  return nil
end

local function IsNumericText(text)
  if type(text) ~= "string" then return false end
  return tonumber(text) ~= nil
end

-- Sorts a plate's regions and children into the parts unrealUI needs. Returns
-- nil when the frame does not look like a nameplate at all.
-- Work counters, same purpose as core/compat.lua's: this client has no
-- intra-frame profiler, so the only way to attribute a spike to a subsystem is
-- to count what it did. classified is the expensive one -- ClassifyPlate walks
-- every region and child of a WorldFrame child, and a *rejected* child is never
-- cached, so it is re-classified in full on every rescan.
local statScans, statRescans, statClassified, statRefreshed = 0, 0, 0, 0

-- FrameXML frames the structural signature matches by accident. Measured here:
-- GroupLootFrame1..4 (roll timer + "Item Name") and ShopFrameScanTooltip
-- (StatusBar child + 60 FontStrings), knowledge.json
-- world.nameplates_are_not_lua_widgets. A denylist, not "reject every named
-- frame": what name, if any, this client gives a real plate is unmeasured.
local function IsNamedFrame(frame)
  local name = Call(frame, "GetName")
  if type(name) ~= "string" then return false end
  return string.find(name, "^GroupLootFrame%d+$") ~= nil or
         name == "ShopFrameScanTooltip"
end

local function ClassifyPlate(frame)
  statClassified = statClassified + 1

  -- Checked before the structural signatures: adopting mutes every child, and
  -- muting GroupLootFrameN hides its roll buttons.
  if IsNamedFrame(frame) then return Reject("named-frame") end
  -- unrealUI's own overlay. Although parented to the plate, it is listed as a
  -- WorldFrame child here and carries the same name/bar shape, so it used to
  -- be adopted one frame after its plate: muted (the visible plate vanished)
  -- and covered by a second overlay 14 units higher (UnrealRuntimeProbe
  -- npflicker v3, 2026-10-19; knowledge nameplates.own_overlay_adopted).
  local ownName = Call(frame, "GetName")
  if type(ownName) == "string" and
     string.find(ownName, "^UnrealUINamePlate%d+$") then
    return Reject("own-overlay")
  end
  -- The object type is recorded, not gated on. Measured: gating on
  -- Button/Frame plus "plates are anonymous" rejected all 28 WorldFrame
  -- children on this client -- and this runtime auto-names objects
  -- (GeneratedLuaUIObject_NNNN appears in frames.getpoint_relative_name_y
  -- _inverted), so a name-based filter cannot distinguish a plate from
  -- anything else here. Structure is the only usable signal.
  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or type(regions) ~= "table" then
    return Reject("no-getregions")
  end

  local parts = { textures = {}, fontstrings = {} }
  local i

  for i = 1, table.getn(regions) do
    local region = regions[i]
    local regionType = ObjectType(region)

    if regionType == "FontString" then
      table.insert(parts.fontstrings, region)
    elseif regionType == "Texture" then
      table.insert(parts.textures, region)

      local texture = Call(region, "GetTexture")
      if type(texture) == "string" then
        if string.find(texture, "Nameplate%-Border") then
          parts.border = region
        elseif string.find(texture, "Nameplate%-Glow") or
               string.find(texture, "Glow") then
          parts.glow = region
        elseif string.find(texture, "Elite") or string.find(texture, "Rare") then
          parts.levelicon = region
        elseif string.find(texture, "RaidTargetingIcon") then
          parts.raidicon = region
        end
      end
    end
  end

  local kidsOk, kids = pcall(function() return { frame:GetChildren() } end)
  if kidsOk and type(kids) == "table" then
    for i = 1, table.getn(kids) do
      local kid = kids[i]
      local kidType = ObjectType(kid)
      -- GetValue is the part that matters; the widget's reported type is not
      -- assumed to be "StatusBar" on this client.
      local hasValue = false
      pcall(function() hasValue = type(kid.GetValue) == "function" end)

      if kidType == "StatusBar" or hasValue then
        if not parts.healthbar then
          parts.healthbar = kid
        elseif not parts.castbar then
          parts.castbar = kid
        end
      end
    end
  end

  -- Accept on any of three independent signatures, so a Vanilla-shaped plate
  -- and this client's own shape both resolve. Which one matched is recorded for
  -- U.NameplateReport().
  --
  -- Each signature still demands a *combination*, never a single generic trait:
  -- adopting a plate mutes its native art for the rest of the session, so a
  -- false positive on some other WorldFrame child is not a cosmetic mistake.
  -- /uui np dumps every child so the threshold can be checked against what is
  -- really there rather than loosened blind.
  local fontCount = table.getn(parts.fontstrings)

  local detector
  if parts.border then
    detector = "border-texture"
  elseif parts.healthbar and fontCount >= 1 then
    detector = "healthbar+name"
  elseif fontCount >= 2 then
    detector = "name+level-fontstrings"
  else
    return Reject("shape " .. tostring(ObjectType(frame)) ..
                  " tex=" .. table.getn(parts.textures) ..
                  " fs=" .. fontCount ..
                  " bar=" .. (parts.healthbar and "y" or "n"))
  end

  parts.detector = detector

  -- The level is whichever fontstring currently reads as a number; the name is
  -- the first one that is not it. Re-checked on refresh, because a plate is
  -- recycled onto a different unit without being rebuilt.
  local first, second = parts.fontstrings[1], parts.fontstrings[2]
  if IsNumericText(Call(first, "GetText")) and second then
    parts.level, parts.name = first, second
  else
    parts.name, parts.level = first, second
  end

  return parts
end

-- ---------------------------------------------------------------------------
-- Options: layout, health text, health-bar hiding, outlines, zoom, raid icon
--
-- Behaviour follows ShaguPlates' options (modules/nameplates.lua HidePlate,
-- GetNameString, OnDataChanged's hp text, OnUpdate's zoom) -- WORKING_SOURCE
-- for intent only; nothing here reuses its code or config schema.
-- ---------------------------------------------------------------------------

-- A name seen live as the target or mouseover is known, then a name the player
-- cache read from a party, raid or guild unit (core/playercache.lua);
-- otherwise a name the bundled creature index does not list is taken for a
-- player. That heuristic also counts player pets and creatures missing from
-- the index as players.
function style.IsPlayer(name)
  if not name then return false end
  local known = reaction.player[name]
  if known ~= nil then return known end
  if type(U.PlayerKnown) == "function" and U.PlayerKnown(name) then
    return true
  end
  if type(U.unitNames) ~= "table" then return false end
  return U.unitNames[name] == nil
end

style.HIDE_KEY = {
  ENEMY         = { npc = "hideEnemyNpc",       player = "hideEnemyPlayer" },
  NEUTRAL       = { npc = "hideNeutralNpc",     player = "hideNeutralNpc" },
  FRIENDLY_NPC  = { npc = "hideFriendlyNpc",    player = "hideFriendlyPlayer" },
  FRIENDLY_UNIT = { npc = "hideFriendlyPlayer", player = "hideFriendlyPlayer" },
}

style.OUTLINE_KEY = {
  ENEMY = "outlineEnemy",
  NEUTRAL = "outlineNeutral",
  FRIENDLY_NPC = "outlineFriendlyNpc",
  FRIENDLY_UNIT = "outlineFriendlyPlayer",
}

-- ---------------------------------------------------------------------------
-- Class colours (core/playercache.lua)
--
-- ShaguPlates' enemyclassc / friendclassc / friendclassnamec, by intent. The
-- cache answers by name; a name seen live as a creature (reaction.player
-- false) is never coloured, so an NPC sharing a player's name keeps its
-- reaction colour.
-- ---------------------------------------------------------------------------

-- A name the cache knows but the reaction cache has never seen live came from
-- the party, raid or guild roster: always the player's own side.
function style.CachedFriend(name)
  if type(U.PlayerKnown) == "function" and U.PlayerKnown(name) and
     reaction.player[name] ~= false then
    return "FRIENDLY_UNIT"
  end
  return nil
end

function style.ClassOf(name)
  if type(U.PlayerInfo) ~= "function" or reaction.player[name] == false then
    return nil
  end
  local token = U.PlayerInfo(name)
  if token and M.ClassColor(token) then return token end
  return nil
end

style.FRIENDLY_TYPE = { FRIENDLY_UNIT = true, FRIENDLY_NPC = true }

-- The bar takes the class colour for an enemy or a friendly player when its
-- option is on, else the reaction colour; a friendly player's name takes it
-- with classColorFriendlyName. Cached per plate on the resolved key.
function style.RefreshColors(overlay, unitType, name)
  local class = name and style.ClassOf(name)
  local friendly = style.FRIENDLY_TYPE[unitType] and true or false
  local barClass = class and ((friendly and cfg.classColorFriendly) or
                              (not friendly and cfg.classColorEnemy)) and
                   class or nil
  local barKey = barClass or unitType
  if barKey ~= overlay.cache.barColor then
    overlay.cache.barColor = barKey
    if barClass then
      U.SetStatusBarColor(overlay.health, M.ClassColor(barClass))
    else
      U.SetStatusBarColor(overlay.health, M.Unpack(UNIT_COLOR[unitType]))
    end
  end

  if not overlay.name then return end
  local nameClass = class and friendly and cfg.classColorFriendlyName and
                    class or nil
  local nameKey = nameClass or "plain"
  if nameKey == overlay.cache.nameColor then return end
  overlay.cache.nameColor = nameKey
  local r, g, b = 1, 1, 1
  if nameClass then r, g, b = M.ClassColor(nameClass) end
  pcall(overlay.name.SetTextColor, overlay.name, r, g, b, 1)
end

-- ---------------------------------------------------------------------------
-- Totems
--
-- ShaguPlates' totems / totemicons, by intent: hide a totem's health bar, or
-- replace its plate with the totem's spell icon. Totems are found by creature
-- id rather than by name: the bundled name tables (Database/unit_names*.lua,
-- U.unitNames) map the client's own enUS, ruRU or zhCN name to the same ids,
-- so this one table needs no translation. A frFR client has no localized name
-- table, so its totems are not recognised. Ids: every rank of each shaman
-- totem in the enUS table; icons: each totem spell's icon (WORKING_SOURCE:
-- the same art names ShaguPlates' enUS table lists, plus Tranquil Air). A
-- literal Interface\Icons path is what modules/bankview.lua's fallback and the
-- /uui npcast preview already draw.
-- ---------------------------------------------------------------------------
style.TOTEM_IDS = {
  Spell_Nature_DiseaseCleansingTotem = { 5924 }, -- Disease Cleansing Totem
  Spell_Nature_StrengthOfEarthTotem02 = { 2630 }, -- Earthbind Totem
  Spell_Fire_SealOfFire = { 5879, 6110, 6111, 7844, 7845 }, -- Fire Nova Totem
  Spell_FireResistanceTotem_01 = { 5927, 7424, 7425 }, -- Fire Resistance Totem
  Spell_Nature_GuardianWard = { 5950, 6012, 7423, 10557 }, -- Flametongue Totem
  Spell_FrostResistanceTotem_01 = { 5926, 7412, 7413 }, -- Frost Resistance Totem
  Spell_Nature_InvisibilityTotem = { 7486, 7487, 15463 }, -- Grace of Air Totem
  Spell_Nature_GroundingTotem = { 5925 }, -- Grounding Totem
  INV_Spear_04 = { 3527, 3906, 3907, 3908, 3909 }, -- Healing Stream Totem
  Spell_Fire_SelfDestruct = { 5929, 7464, 7465, 7466 }, -- Magma Totem
  Spell_Nature_ManaRegenTotem = { 3573, 7414, 7415, 7416 }, -- Mana Spring Totem
  Spell_Frost_SummonWaterElemental = { 10467, 11100, 11101 }, -- Mana Tide Totem
  Spell_Nature_NatureResistanceTotem = { 7467, 7468, 7469 }, -- Nature Resistance Totem
  Spell_Nature_PoisonCleansingTotem = { 5923 }, -- Poison Cleansing Totem
  Spell_Fire_SearingTotem = { 2523, 3902, 3903, 3904, 7400, 7402 }, -- Searing Totem
  Spell_Nature_RemoveCurse = { 3968 }, -- Sentry Totem
  Spell_Nature_StoneClawTotem = { 3579, 3911, 3912, 3913, 7398, 7399 }, -- Stoneclaw Totem
  Spell_Nature_StoneSkinTotem = { 5873, 5919, 5920, 7366, 7367, 7368 }, -- Stoneskin Totem
  Spell_Nature_EarthBindTotem = { 5874, 5921, 5922, 7403, 15464 }, -- Strength of Earth Totem
  Spell_Nature_Brilliance = { 15803 }, -- Tranquil Air Totem
  Spell_Nature_TremorTotem = { 5913 }, -- Tremor Totem
  Spell_Nature_Windfury = { 6112, 7483, 7484 }, -- Windfury Totem
  Spell_Nature_EarthBind = { 9687, 9688, 9689 }, -- Windwall Totem
}
style.totemByName = {}

-- The totem's icon path, or nil. Cached per name (false for "not a totem").
function style.TotemIcon(name)
  if not name then return nil end
  local cached = style.totemByName[name]
  if cached ~= nil then return cached or nil end
  if not style.totemById then
    style.totemById = {}
    local icon, ids, i
    for icon, ids in pairs(style.TOTEM_IDS) do
      for i = 1, table.getn(ids) do
        style.totemById[ids[i]] = "Interface\\Icons\\" .. icon
      end
    end
  end
  local result = false
  local entry = type(U.unitNames) == "table" and U.unitNames[name]
  if type(entry) == "number" then
    result = style.totemById[entry] or false
  elseif type(entry) == "table" then
    local i
    for i = 1, table.getn(entry) do
      if style.totemById[entry[i]] then
        result = style.totemById[entry[i]]
        break
      end
    end
  end
  style.totemByName[name] = result
  return result or nil
end

-- ---------------------------------------------------------------------------
-- Critters
--
-- ShaguPlates' critters option, by intent: hide a critter's health bar. Same
-- id route as the totems above. The ids are every creature_template entry of
-- type 8 (Critter), patch <= 10, in the VMaNGOS database
-- tools/import_unit_reactions.py reads, less six GM, test and trigger
-- entries; all 93 are in the enUS and ruRU name tables, and all but Roach
-- (merged with Cockroach, so left out) in zhCN. A name counts only when every
-- id sharing it is a critter, so a critter name reused by a real creature is
-- never hidden.
-- ---------------------------------------------------------------------------
style.CRITTER_IDS = {
  385, 582, 620, 721, 883, 890, 1262, 1352, 1412, 1420, 1932, 1933, 2098,
  2110, 2442, 2620, 2848, 2914, 3300, 3444, 3681, 3835, 4075, 4076, 4166,
  4953, 5689, 5739, 5740, 5741, 5742, 5743, 5866, 5867, 5868, 5951, 6145,
  6271, 6368, 6653, 6827, 7208, 8881, 8963, 9600, 9699, 9700, 10016, 10017,
  10441, 10461, 10510, 10536, 10582, 10685, 10716, 10779, 10780, 11776,
  12120, 12152, 12296, 12297, 12298, 12299, 12383, 13016, 13017, 13321,
  13338, 14361, 14681, 14801, 14881, 14886, 14892, 15010, 15065, 15066,
  15071, 15072, 15219, 15475, 15476, 16030, 16068, 16369, 16372, 16373,
  16479, 16779, 16998, 18078,
}
style.critterByName = {}

function style.IsCritter(name)
  if not name then return false end
  local cached = style.critterByName[name]
  if cached ~= nil then return cached end
  if not style.critterSet then
    style.critterSet = {}
    local i
    for i = 1, table.getn(style.CRITTER_IDS) do
      style.critterSet[style.CRITTER_IDS[i]] = true
    end
  end
  local result = false
  local entry = type(U.unitNames) == "table" and U.unitNames[name]
  if type(entry) == "number" then
    result = style.critterSet[entry] or false
  elseif type(entry) == "table" and table.getn(entry) > 0 then
    result = true
    local i
    for i = 1, table.getn(entry) do
      if not style.critterSet[entry[i]] then result = false end
    end
  end
  style.critterByName[name] = result
  return result
end

-- Icon mode: the totem's icon in place of the plate. The name, level, health
-- text and bar step aside (style.HideHealth hides the bar); the raid mark,
-- cast bar and combo points keep working.
function style.RefreshTotem(overlay, name)
  local icon = cfg.totemIcons and style.TotemIcon(name) or nil
  overlay.totemShown = icon and true or false

  -- The name: showName (user request, 2026-10-20), and never beside a totem
  -- icon.
  local showName = cfg.showName and not overlay.totemShown
  if overlay.name and showName ~= overlay.cache.nameShown then
    overlay.cache.nameShown = showName
    if showName then overlay.name:Show() else overlay.name:Hide() end
  end

  if (icon or false) == overlay.cache.totem then return end
  overlay.cache.totem = icon or false
  local texture = overlay.totemIcon
  if icon then
    texture:SetTexture(icon)
    texture:Show()
    if overlay.level then overlay.level:Hide() end
  else
    texture:Hide()
    if overlay.level then overlay.level:Show() end
  end
end

function style.HideHealth(overlay, unitType, name, damaged)
  if overlay.totemShown then return true end
  if cfg.keepHealthTarget and overlay.isTarget then return false end
  if cfg.keepHealthDamaged and damaged then return false end
  if cfg.hideTotemHealth and style.TotemIcon(name) then return true end
  if cfg.hideCritterHealth and style.IsCritter(name) then return true end
  local keys = style.HIDE_KEY[unitType]
  if not keys then return false end
  return cfg[style.IsPlayer(name) and keys.player or keys.npc] and true or false
end

function style.Number(value)
  value = math.floor(value + 0.5)
  if cfg.abbrevNumbers then
    if value >= 1000000 then
      return string.format("%.1fm", value / 1000000)
    elseif value >= 1000 then
      return string.format("%.1fk", value / 1000)
    end
  end
  return tostring(value)
end

-- current/total are real hitpoints when core/unitvitals.lua knows them, nil
-- for players and unknown creatures; perc (0..100) always exists.
function style.HealthText(current, total, perc)
  local format = cfg.healthFormat
  local pct = string.format("%d%%", math.floor(perc + 0.5))
  if not current or not total then
    if format == "deficit" then
      if perc >= 99.5 then return "" end
      return string.format("-%d%%", math.floor(100 - perc + 0.5))
    end
    return pct
  end
  if format == "percent" then return pct end
  if format == "current" then return style.Number(current) end
  if format == "curperc" then
    return style.Number(current) .. " (" .. pct .. ")"
  end
  if format == "deficit" then
    if total - current < 0.5 then return "" end
    return "-" .. style.Number(total - current)
  end
  return style.Number(current) .. " / " .. style.Number(total)
end

-- First character, whole: a byte cut would break a Cyrillic or CJK name.
function style.Initial(word)
  local _, last = string.find(word, "^[\1-\127\192-\255][\128-\191]*")
  return string.sub(word, 1, last or 1) .. ". "
end

style.NAME_LIMIT = 20

-- ShaguPlates' GetNameString: shorten the first word, then every word but the
-- last, until the name fits.
function style.Name(name)
  if not cfg.abbrevNames or type(name) ~= "string" or
     string.len(name) <= style.NAME_LIMIT then
    return name
  end
  name = string.gsub(name, "^(%S+) ", style.Initial)
  if string.len(name) > style.NAME_LIMIT then
    name = string.gsub(name, "(%S+) ", style.Initial)
  end
  return name
end

-- Offsets are in the overlay's own scale, so a zoomed plate divides them back
-- out and stays where the unzoomed one was.
function style.Anchor(overlay)
  overlay:ClearAllPoints()
  overlay:SetPoint("TOP", overlay.plate, "TOP", 0,
                   (PLATE_LIFT + cfg.verticalOffset) / (overlay.zoom or 1))
end

-- Modern WoW: the bar's rect is the window inside the frame's rim, so the fill
-- (drawn above the frame, ARTWORK over BACKGROUND) meets the rim on every
-- side. Units per texel on each axis, then the frame's margins around it.
function style.LayoutArt(overlay, plateWidth, healthHeight)
  local art = overlay.art
  local health = overlay.health
  local background = art.background
  local window = art.backgroundWindow
  local sx = plateWidth / (window.right - window.left)
  local sy = healthHeight / (window.bottom - window.top)
  health.uuiBackground:ClearAllPoints()
  health.uuiBackground:SetPoint(
    "TOPLEFT", health, "TOPLEFT",
    -window.left * sx, window.top * sy)
  health.uuiBackground:SetPoint(
    "BOTTOMRIGHT", health, "BOTTOMRIGHT",
    (background[3] - background[1] - window.right) * sx,
    -(background[4] - background[2] - window.bottom) * sy)
end

function style.LayoutRaidIcon(overlay)
  local icon = overlay.raidIcon
  if not icon then return end
  local size, x, y = cfg.raidIconSize, cfg.raidIconX, cfg.raidIconY
  icon:SetWidth(size)
  icon:SetHeight(size)
  icon:ClearAllPoints()
  if cfg.raidIconPos == "TOP" then
    icon:SetPoint("BOTTOM", overlay.health, "TOP", x, y + cfg.nameSize + 4)
  elseif cfg.raidIconPos == "RIGHT" then
    icon:SetPoint("LEFT", overlay.health, "RIGHT", 4 + x, y)
  else
    icon:SetPoint("RIGHT", overlay.health, "LEFT", -4 + x, y)
  end
end

-- Every size and position the options control. Called once when the overlay
-- is built and again by style.Invalidate after any option changes.
function style.Layout(overlay)
  local art = overlay.art
  local artScale = overlay.artScale or 1
  local plateWidth = cfg.width * artScale
  local healthHeight = (art and cfg.artHealthHeight or cfg.healthHeight) *
                       artScale
  local health = overlay.health

  overlay:SetWidth(plateWidth)
  overlay:SetHeight(healthHeight + cfg.nameSize + 4)
  style.Anchor(overlay)

  health:SetWidth(plateWidth)
  health:SetHeight(healthHeight)
  if art then style.LayoutArt(overlay, plateWidth, healthHeight) end

  if overlay.name then
    overlay.name:SetWidth(plateWidth - 28)
    U.SetFont(overlay.name, cfg.nameSize)
  end
  if overlay.level then U.SetFont(overlay.level, cfg.levelSize) end

  local text = overlay.healthText
  if text then
    U.SetFont(text, cfg.healthTextSize)
    text:ClearAllPoints()
    if cfg.healthTextPos == "LEFT" then
      text:SetPoint("LEFT", health, "LEFT", 3, 0)
    elseif cfg.healthTextPos == "RIGHT" then
      text:SetPoint("RIGHT", health, "RIGHT", -3, 0)
    else
      text:SetPoint("CENTER", health, "CENTER", 0, 0)
    end
  end

  overlay.cast:SetWidth(plateWidth)
  if overlay.castName then
    overlay.castName:SetWidth(plateWidth - overlay.castTextX - 30)
  end
  style.LayoutRaidIcon(overlay)
  style.LayoutCombo(overlay)
  if overlay.totemIcon then
    overlay.totemIcon:SetWidth(cfg.totemSize)
    overlay.totemIcon:SetHeight(cfg.totemSize)
  end
end

-- ---------------------------------------------------------------------------
-- Combo points (target plate)
--
-- GetComboPoints("target") is documented, not runtime-verified, and is the
-- same call the unit frames' combo strip already makes (modules/unitframes.lua),
-- so that strip working in game is the evidence for this one. ShaguPlates'
-- intent (nameplates.lua 429-445, 788-792): only the filled points, small
-- squares under the bar, the first at its right edge. Flat themes draw the
-- unit frames' muted red-to-green palette (M.rogueCombo) with a black outline;
-- Modern WoW draws its active combo circle (M.modernWow.combo).
-- ---------------------------------------------------------------------------
style.COMBO_MAX = 5
style.COMBO_GAP = 2

function style.BuildCombo(overlay, modernWow)
  local layer = CreateFrame("Frame", nil, overlay)
  layer:SetWidth(1)
  layer:SetHeight(1)
  layer:Hide()
  local pips = {}
  local i
  for i = 1, style.COMBO_MAX do
    local pip = CreateFrame("Frame", nil, layer)
    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(pip)
    if modernWow then
      local cell = M.modernWow.combo.active
      fill:SetTexture(M.modernWow.texture.comboPoints)
      fill:SetTexCoord(cell[1], cell[2], cell[3], cell[4])
    else
      fill:SetTexture(M.texture.plain)
      U.SetColor(fill, M.Unpack(M.rogueCombo[i]))
      U.CreateBorder(pip, 1)
      U.SetBorderColor(pip, 0, 0, 0, 1)
    end
    pip:Hide()
    pips[i] = pip
  end
  overlay.combo = { layer = layer, pips = pips, modernWow = modernWow }
end

function style.LayoutCombo(overlay)
  local combo = overlay.combo
  if not combo then return end
  local height = cfg.comboSize
  local width = combo.modernWow and height * M.modernWow.combo.aspect or height
  local gap = combo.modernWow and M.modernWow.combo.gap or style.COMBO_GAP
  combo.layer:SetWidth(style.COMBO_MAX * width + (style.COMBO_MAX - 1) * gap)
  combo.layer:SetHeight(height)
  local i
  for i = 1, style.COMBO_MAX do
    local pip = combo.pips[i]
    pip:SetWidth(width)
    pip:SetHeight(height)
    pip:ClearAllPoints()
    pip:SetPoint("TOPRIGHT", combo.layer, "TOPRIGHT", -(i - 1) * (width + gap), 0)
  end
end

-- Rows under the bar stack in a fixed order -- cast bar, guild line, combo
-- points -- each skipped while hidden, so none overlaps another. The distance
-- from the bar's bottom to the top of the next row, given which rows above it
-- show.
function style.BelowOffset(overlay, withGuild)
  local offset = 0
  if overlay.cast:IsShown() then
    offset = offset + overlay.castGap + (overlay.cast:GetHeight() or 0)
  end
  if withGuild and overlay.guild and overlay.guild:IsShown() then
    offset = offset + 2 + (overlay.guild:GetHeight() or 0)
  end
  return offset
end

-- ShaguPlates' showguildname, by intent: the player's guild in brackets,
-- centred under the bar, green for the player's own guild and dim otherwise.
-- From core/playercache.lua; a name seen live as a creature shows none.
function style.RefreshGuild(overlay, name)
  local label = overlay.guild
  if not label then return end
  local guild
  if cfg.showGuild and name and reaction.player[name] ~= false and
     type(U.PlayerInfo) == "function" then
    local _, known = U.PlayerInfo(name)
    guild = known
  end
  local offset = style.BelowOffset(overlay, false)
  local own = guild and type(U.PlayerGuild) == "function" and
              U.PlayerGuild() == guild
  local key = guild and (guild .. "|" .. offset .. (own and "|own" or "")) or
              "none"
  if key == overlay.cache.guild then return end
  overlay.cache.guild = key
  if not guild then
    label:Hide()
    return
  end
  label:SetText("<" .. guild .. ">")
  pcall(label.SetTextColor, label,
        M.Unpack(own and M.color.guildOwn or M.color.textDim))
  label:ClearAllPoints()
  label:SetPoint("TOP", overlay.health, "BOTTOM", 0, -(offset + 2))
  label:Show()
end

-- After the cast bar and the guild line: the points sit under whichever of
-- them show (style.BelowOffset), at the bar's right edge.
function style.RefreshCombo(overlay)
  local combo = overlay.combo
  if not combo then return end
  local count = 0
  if cfg.comboPoints and overlay.isTarget then
    local get = ResolveApiFn("GetComboPoints")
    if get then
      local ok, value = pcall(get, "target")
      count = ok and tonumber(value) or 0
    end
  end
  local offset = style.BelowOffset(overlay, true)
  if count == overlay.cache.combo and offset == overlay.cache.comboOffset then
    return
  end
  overlay.cache.combo = count
  overlay.cache.comboOffset = offset

  combo.layer:ClearAllPoints()
  combo.layer:SetPoint("TOPRIGHT", overlay.health, "BOTTOMRIGHT", 0,
                       -(offset + style.COMBO_GAP))
  local i
  for i = 1, style.COMBO_MAX do
    if i <= count then combo.pips[i]:Show() else combo.pips[i]:Hide() end
  end
  if count > 0 then combo.layer:Show() else combo.layer:Hide() end
end

-- Target zoom: the whole overlay scales, so text and art stay in proportion.
function style.RefreshZoom(overlay)
  local zoom = 1
  if overlay.isTarget and cfg.targetZoom then
    zoom = 1 + cfg.targetZoomPercent / 100
  end
  if zoom == overlay.zoom then return end
  overlay.zoom = zoom
  pcall(function() overlay:SetScale(UIParent:GetScale() * zoom) end)
  style.Anchor(overlay)
end

-- The target plate draws above every overlapping plate: the others sit one
-- strata lower. WORKING_SOURCE (ShaguPlates, nameplates.lua 881-888): BACKGROUND
-- for the rest and LOW for the target, so the target never reaches MEDIUM,
-- where the client's windows draw. SetFrameStrata also sets it on child frames
-- (documented, not runtime-verified here), which carries the bars, cast bar
-- and aura row along; none of them sets a strata of its own.
function style.RefreshStrata(overlay)
  local strata = overlay.isTarget and "LOW" or "BACKGROUND"
  if strata == overlay.cache.strata then return end
  overlay.cache.strata = strata
  pcall(overlay.SetFrameStrata, overlay, strata)
end

-- Every theme: the target outline wins over a reaction outline; with neither
-- nothing is drawn (no resting outline, user request 2026-10-20). The flat
-- themes draw the 1-unit edges; Modern WoW draws its selected-plate art (a
-- white frame) tinted the same colour, and keeps it untinted on the target
-- when no outline applies, as its own target state. All options apply under
-- every theme (user request, 2026-10-20).
function style.RefreshOutline(overlay, unitType)
  local key, r, g, b = "none", 0, 0, 0
  if overlay.isTarget and cfg.targetOutline then
    key, r, g, b = "target", cfg.highlightR, cfg.highlightG, cfg.highlightB
  elseif style.OUTLINE_KEY[unitType] and cfg[style.OUTLINE_KEY[unitType]] then
    key = unitType
    r, g, b = M.Unpack(UNIT_COLOR[unitType])
  elseif overlay.isTarget and overlay.selectedBorder then
    key, r, g, b = "selected", 1, 1, 1
  end
  if key == overlay.cache.border then return end
  overlay.cache.border = key

  if overlay.selectedBorder then
    if key == "none" then
      overlay.selectedBorder:Hide()
    else
      overlay.selectedBorder:SetVertexColor(r, g, b, 1)
      overlay.selectedBorder:Show()
    end
  else
    style.ShowEdges(overlay.health, key ~= "none", r, g, b)
  end
end

-- The edges are shown and hidden outright rather than given a zero alpha:
-- a zero vertex alpha is exactly what failed to hide a fill on this client
-- (knowledge.json statusbar.native_fill_hide_routes).
function style.ShowEdges(frame, shown, r, g, b)
  local edges = frame.uuiEdges
  if not edges then return end
  if shown then U.SetBorderColor(frame, r, g, b, 1) end
  local i
  for i = 1, table.getn(edges) do
    if shown then edges[i]:Show() else edges[i]:Hide() end
  end
end

-- The mark: GetRaidTargetIndex for the target, otherwise the native plate's
-- own raid-icon region, read back through its texture cell. Which cell the
-- client gives that region on this build is unmeasured (WORKING_SOURCE:
-- Vanilla's 4x4 UI-RaidTargetingIcons sheet); a cell outside 1..8 shows none.
function style.RaidIndex(overlay)
  if overlay.isTarget then
    local index = ApiNumber("GetRaidTargetIndex", "target")
    if index and index >= 1 and index <= 8 then return index end
  end
  local region = overlay.parts.raidicon
  if not region or not Call(region, "IsShown") then return nil end
  local left, top = Call(region, "GetTexCoord")
  left, top = tonumber(left), tonumber(top)
  if not left or not top then return nil end
  local index = math.floor(top * 4 + 0.5) * 4 + math.floor(left * 4 + 0.5) + 1
  if index < 1 or index > 8 then return nil end
  return index
end

function style.RefreshRaidIcon(overlay)
  local icon = overlay.raidIcon
  if not icon then return end
  local index = cfg.raidIcon and style.RaidIndex(overlay) or nil
  if index == overlay.cache.raid then return end
  overlay.cache.raid = index
  if not index then
    icon:Hide()
    return
  end
  local col = math.mod(index - 1, 4) * 0.25
  local row = math.floor((index - 1) / 4) * 0.25
  icon:SetTexCoord(col, col + 0.25, row, row + 0.25)
  icon:Show()
end

-- The client's own switches; documented, unverified on this client, so a
-- missing function is skipped rather than assumed.
function style.ApplyVisibility()
  if not cfg.enabled then return end
  local fn = ResolveApiFn(cfg.showHostile and "ShowNameplates" or
                          "HideNameplates")
  if fn then pcall(fn) end
  fn = ResolveApiFn(cfg.showFriendly and "ShowFriendNameplates" or
                    "HideFriendNameplates")
  if fn then pcall(fn) end
end

-- ---------------------------------------------------------------------------
-- Overlay construction
-- ---------------------------------------------------------------------------
local function BuildOverlay(frame, parts)
  plateCount = plateCount + 1

  local overlay = CreateFrame("Frame", "UnrealUINamePlate" .. plateCount, frame)
  local themeStyle = U.GetActiveThemeStyle()
  local modern = themeStyle == "modern"
  local modernWow = themeStyle == "modern-wow"
  -- Classic draws the stock fill, the same native texture its unit frames use.
  local classic = themeStyle == "classic-wow"
  local nativeTexture = classic and M.texture.classicStatusBar or nil
  local nameplateArt = modernWow and M.modernWow.nameplate or nil
  overlay.id = plateCount
  overlay.plate = frame
  overlay.parts = parts
  overlay.cache = {}
  overlay.modernWow = modernWow
  overlay.zoom = 1

  -- Non-target strata until the first refresh says otherwise (style.RefreshStrata).
  pcall(overlay.SetFrameStrata, overlay, "BACKGROUND")

  -- WORKING_SOURCE (UnrealPfUI): a WorldFrame-child overlay is scaled to the UI
  -- scale so plate sizes read in the same units as the rest of the addon.
  pcall(function() overlay:SetScale(UIParent:GetScale()) end)

  local artScale = nameplateArt and nameplateArt.scale or 1
  local plateWidth = cfg.width * artScale
  local healthHeight = (nameplateArt and cfg.artHealthHeight or
                        cfg.healthHeight) * artScale
  overlay.art = nameplateArt
  overlay.artScale = artScale

  -- Size and position come from style.Layout at the end, so the options can
  -- re-run it on a live plate.
  local health = U.CreateStatusBar(overlay, {
    width = plateWidth,
    height = healthHeight,
    color = UNIT_COLOR.ENEMY,
    background = nameplateArt and { 1, 1, 1, 1 } or M.color.healthBg,
    texture = nameplateArt and nameplateArt.texture or
              (modern and M.unitFrame.statusTexture or nativeTexture),
  })
  health:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
  if nameplateArt then
    local sheet = nameplateArt.sheet
    local fill = nameplateArt.fill
    local background = nameplateArt.background
    health.uuiFillTexture:SetTexCoord(
      fill[1] / sheet[1], fill[3] / sheet[1],
      fill[2] / sheet[2], fill[4] / sheet[2])
    health.uuiBackground:SetTexture(nameplateArt.texture)
    health.uuiBackground:SetTexCoord(
      background[1] / sheet[1], background[3] / sheet[1],
      background[2] / sheet[2], background[4] / sheet[2])
    -- Its anchors inside the rim are style.LayoutArt's, run by style.Layout.

    local selected = health:CreateTexture(nil, "OVERLAY")
    selected:SetTexture(nameplateArt.selectedTexture)
    local inset = nameplateArt.selectedInset
    selected:SetPoint("TOPLEFT", health, "TOPLEFT",
                      inset.left * artScale, inset.top * artScale)
    selected:SetPoint(
      "BOTTOMRIGHT", health, "BOTTOMRIGHT",
      inset.right * artScale, inset.bottom * artScale)
    selected:Hide()
    overlay.selectedBorder = selected
  else
    -- No resting outline under `modern` or `classic-wow` (`classic-wow`'s was
    -- removed by user request, 2026-10-20): the edges exist only for the
    -- optional target and reaction outlines and start hidden.
    U.CreateBorder(health)
    style.ShowEdges(health, false)
  end
  overlay.health = health

  -- Its own layer so the fill never covers the percentage. Placed by
  -- style.Layout (healthTextPos).
  overlay.healthText = U.CreateLabel(health, {
    size = cfg.healthTextSize,
    color = M.color.text,
    inherits = "GameFontNormal",
  })

  -- One anchor per label, per fonts.stretched_justification_ignored.
  overlay.name = U.CreateLabel(overlay, {
    size = cfg.nameSize,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
    -- The fixed width below centres the text inside it unless told otherwise.
    justify = "LEFT",
  })
  -- Shown under every theme so the name options apply to all of them (user
  -- request, 2026-10-20); Modern WoW used to hide it.
  if overlay.name then
    overlay.name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 2)
  end

  overlay.level = U.CreateLabel(overlay, {
    size = cfg.levelSize,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
  })
  if overlay.level then
    overlay.level:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 2)
  end

  -- Under `modern-wow` the cast bar is Retail's nameplate cast bar
  -- (M.modernWow.nameplate.cast): the cast background and fill and an
  -- additive spark on the fill's edge. The other themes keep the plain bar.
  -- Every theme gets the spell icon and name inside the bar (below).
  local castArt = nameplateArt and nameplateArt.cast or nil
  local castHeight = castArt and castArt.height * artScale or 12
  local cast = U.CreateStatusBar(overlay, {
    width = plateWidth,
    height = castHeight,
    color = castArt and { 1, 1, 1, 1 } or M.color.cast,
    background = castArt and { 1, 1, 1, 1 } or M.color.healthBg,
    texture = castArt and M.modernWow.texture.castFill or nativeTexture,
  })
  -- Kept for the rows stacked under the cast bar (style.BelowOffset).
  overlay.castGap = castArt and castArt.spacing * artScale or 2
  cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -overlay.castGap)
  local castTextX, castTimeX = 3, -3
  if castArt then
    cast.uuiBackground:SetTexture(M.modernWow.texture.castBackground)

    -- Additive, as the source draws it: with the default blend its black
    -- field is a moving dark square (modules/modernwow.lua, CastFillUpdate),
    -- so the spark is dropped if the blend mode cannot be set.
    local spark = cast:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(M.modernWow.texture.castSpark)
    if spark.SetBlendMode and pcall(spark.SetBlendMode, spark, "ADD") then
      spark:SetWidth(castArt.sparkWidth * artScale)
      spark:SetHeight((castArt.height + castArt.sparkExtra) * artScale)
      spark:Hide()
      overlay.castSpark = spark
    else
      spark:Hide()
    end
    castTimeX = -castArt.timeInset * artScale
  elseif not classic then
    -- The plain bar keeps its outline, except under `classic-wow`, where it
    -- matches its health bar.
    U.CreateBorder(cast)
    U.SetBorderColor(cast, M.Unpack(M.color.border))
  end

  -- The spell icon, every theme (user request, 2026-10-20): a square the
  -- bar's full height at its left edge, cropped like every other spell icon,
  -- with the name beside it.
  local icon = cast:CreateTexture(nil, "OVERLAY")
  icon:SetWidth(castHeight)
  icon:SetHeight(castHeight)
  icon:SetPoint("TOPLEFT", cast, "TOPLEFT", 0, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:Hide()
  overlay.castIcon = icon
  castTextX = castHeight + (castArt and castArt.textGap * artScale or 3)
  overlay.castTextX = castTextX
  cast:Hide()
  overlay.cast = cast

  local castFont = castArt and
                   math.max(M.fontSize.tiny,
                            math.floor(castArt.font * artScale + 0.5)) or
                   M.fontSize.tiny
  overlay.castName = U.CreateLabel(cast, {
    size = castFont,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if overlay.castName then
    overlay.castName:SetPoint("LEFT", cast, "LEFT", castTextX, 0)
  end

  overlay.castTime = U.CreateLabel(cast, {
    size = castFont,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "RIGHT",
  })
  if overlay.castTime then
    overlay.castTime:SetPoint("RIGHT", cast, "RIGHT", castTimeX, 0)
  end

  if type(U.CreateNameplateAuraRows) == "function" then
    local auraArt = modernWow and M.modernWow.nameplateAura or nil
    -- Both clear the name row above the bar.
    local auraOffset = auraArt and
                       (auraArt.size + auraArt.gap -
                        auraArt.overlayInset.bottom + cfg.nameSize + 4) or
                       cfg.nameSize + 30
    overlay.auraRows = U.CreateNameplateAuraRows(
      health, overlay, overlay.id, auraOffset)
  end

  -- Raid mark. On the overlay rather than the bar, so hiding the health bar
  -- (style.HideHealth) keeps the mark; it sits beside the bar, never on it.
  local raid = overlay:CreateTexture(nil, "OVERLAY")
  raid:SetTexture(M.texture.raidTargetIcons)
  raid:Hide()
  overlay.raidIcon = raid

  style.BuildCombo(overlay, modernWow)

  -- Guild line (style.RefreshGuild), placed under the bar on each refresh.
  overlay.guild = U.CreateLabel(overlay, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if overlay.guild then overlay.guild:Hide() end

  -- Totem icon (style.RefreshTotem), centred on the bar's place, cropped like
  -- every other spell icon.
  local totem = overlay:CreateTexture(nil, "ARTWORK")
  totem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  totem:SetPoint("CENTER", health, "CENTER", 0, 0)
  totem:Hide()
  overlay.totemIcon = totem

  style.Layout(overlay)
  overlay:Show()
  return overlay
end

local function RefreshTargetAuras(overlay)
  if type(U.RefreshNameplateAuraRows) ~= "function" then return end

  local active = cfg.showAuras and overlay.isTarget
  if not active then
    if overlay.auraActive then
      overlay.auraActive = false
      U.RefreshNameplateAuraRows(overlay.auraRows, false)
    end
    return
  end

  local now = ApiNumber("GetTime") or 0
  if not overlay.auraActive or now >= (overlay.nextAuraRefresh or 0) then
    overlay.auraActive = true
    overlay.nextAuraRefresh = now + 0.2
    U.RefreshNameplateAuraRows(overlay.auraRows, true)
  end
end

-- /uui npcast: a looping fake cast on every visible plate for SECONDS, so the
-- cast bar can be looked at without a casting mob (user request, 2026-10-20).
-- Drawn through the same path as a real target cast below.
local castPreview = { SECONDS = 20, CAST = 2.5, SPELL = "Shadow Bolt",
                      ICON = "Interface\\Icons\\Spell_Shadow_ShadowBolt" }

function U.NameplateCastPreview()
  castPreview.start = GetTime()
  castPreview.stop = castPreview.start + castPreview.SECONDS
  return castPreview.SECONDS
end

local function RefreshTargetCast(overlay)
  local spell, elapsed, duration, iconTexture
  local now = GetTime()
  if castPreview.stop and now < castPreview.stop then
    spell, duration, iconTexture =
      castPreview.SPELL, castPreview.CAST, castPreview.ICON
    elapsed = math.mod(now - castPreview.start, duration)
  else
    if not cfg.attachTargetCast or not overlay.isTarget or
       type(U.TargetCastInfo) ~= "function" then
      overlay.cast:Hide()
      return
    end
    spell, elapsed, duration, iconTexture = U.TargetCastInfo()
  end
  if not spell or not duration then
    overlay.cast:Hide()
    return
  end

  overlay.cast:SetMinMaxValues(0, duration)
  overlay.cast:SetValue(elapsed)

  -- Modern WoW: the fill art is cropped to the progress rather than squeezed
  -- (the shape is baked into it), and the spark rides the fill's edge, hidden
  -- at both ends as in the source.
  if overlay.castSpark then
    local progress = duration > 0 and elapsed / duration or 0
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    if progress > 0 then
      pcall(overlay.cast.uuiFillTexture.SetTexCoord,
            overlay.cast.uuiFillTexture, 0, progress, 0, 1)
    end
    local spark = overlay.castSpark
    if progress > 0 and progress < 1 then
      spark:ClearAllPoints()
      spark:SetPoint("CENTER", overlay.cast, "LEFT",
                     (tonumber(overlay.cast:GetWidth()) or 0) * progress, 0)
      spark:Show()
    else
      spark:Hide()
    end
  end

  local icon = overlay.castIcon
  if icon then
    if iconTexture and iconTexture ~= overlay.cache.castIcon then
      overlay.cache.castIcon = iconTexture
      pcall(icon.SetTexture, icon, iconTexture)
    end
    if iconTexture then icon:Show() else icon:Hide() end
  end
  if overlay.castName then overlay.castName:SetText(spell) end
  if overlay.castTime then
    overlay.castTime:SetText(string.format("%.1f", duration - elapsed))
  end
  overlay.cast:Show()
end

function U.RefreshNameplateTargetCast()
  if targetOverlay then RefreshTargetCast(targetOverlay) end
end

local function AdoptPlate(frame)
  local parts = ClassifyPlate(frame)
  if not parts then
    stats.rejected = stats.rejected + 1
    return nil
  end

  -- Do not erase the stock plate until its replacement exists. A construction
  -- error must leave the player with the native nameplate, not a blank world.
  local ok, overlay = pcall(BuildOverlay, frame, parts)
  if not ok or not overlay then
    failures.build = failures.build + 1
    failures.lastBuild = tostring(overlay)
    U.Debug("nameplate build: " .. tostring(overlay))
    return nil
  end

  MuteNativePlate(parts, frame, overlay)
  registry[frame] = overlay
  table.insert(plateOrder, overlay)

  stats.plates = stats.plates + 1
  stats.detector = parts.detector
  if parts.healthbar then stats.withHealthBar = stats.withHealthBar + 1 end

  return overlay
end

local function ScanWorldFrame()
  local worldFrame = U.G("WorldFrame")
  if not worldFrame then return end

  local count = tonumber(Call(worldFrame, "GetNumChildren"))
  if not count then return end
  stats.worldChildren = count
  if stats.minChildren < 0 or count < stats.minChildren then
    stats.minChildren = count
  end
  if count > stats.maxChildren then stats.maxChildren = count end

  -- Vanilla never destroys a plate, but a shrinking count would leave the
  -- cursor past the end, so fall back to a full re-scan instead of trusting it.
  if count < scannedChildren then
    scannedChildren = 0
    statRescans = statRescans + 1
  end
  if count == scannedChildren then return end

  statScans = statScans + 1

  local ok, kids = pcall(function() return { worldFrame:GetChildren() } end)
  if not ok or type(kids) ~= "table" then return end

  -- Children that appear after the first scan are the plate candidates: the
  -- login-time set is FrameXML. Recorded whether adopted or not, so /uui np
  -- shows what a real plate looks like here even if the classifier misses it.
  local firstScan = statScans == 1
  local i
  for i = scannedChildren + 1, count do
    local child = kids[i]
    if child and not registry[child] then
      local overlay = AdoptPlate(child)
      if not firstScan and table.getn(arrivals) < ARRIVAL_LIMIT then
        local fontstrings = 0
        local text
        pcall(function()
          local regions = { child:GetRegions() }
          local j
          for j = 1, table.getn(regions) do
            if ObjectType(regions[j]) == "FontString" then
              fontstrings = fontstrings + 1
              text = text or Call(regions[j], "GetText")
            end
          end
        end)
        table.insert(arrivals, {
          index = i,
          name = Call(child, "GetName"),
          otype = ObjectType(child),
          parent = Call(Call(child, "GetParent"), "GetName"),
          fontstrings = fontstrings,
          firstText = text,
          adopted = overlay and true or false,
          at = ApiNumber("GetTime"),
        })
      end
    end
  end

  scannedChildren = count
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

-- Health for one plate. The native bar is the only source that works for a mob
-- that is neither targeted nor moused over, and on this client it may report a
-- 0..100 scale rather than real hitpoints -- which is exactly why the readout
-- is a percentage.
local function ReadHealth(overlay)
  local bar = overlay.parts.healthbar
  if bar then
    local value = tonumber(Call(bar, "GetValue"))
    local minimum, maximum = Call(bar, "GetMinMaxValues")
    minimum, maximum = tonumber(minimum), tonumber(maximum)
    if value and maximum and maximum > 0 then
      return value, (minimum or 0), maximum
    end
  end

  -- No usable native bar: the unit API can still answer for the target.
  if overlay.isTarget then
    local hp = ApiNumber("UnitHealth", "target")
    local hpMax = ApiNumber("UnitHealthMax", "target")
    if hp and hpMax and hpMax > 0 then return hp, 0, hpMax end
  end

  return nil
end

local function RefreshPlate(overlay)
  local parts = overlay.parts
  local plate = overlay.plate

  local visible = Call(plate, "IsVisible")
  local plateAlpha = tonumber(Call(plate, "GetAlpha")) or 1
  if not visible or plateAlpha <= 0 then
    overlay.isTarget = false
    RefreshTargetAuras(overlay)
    if overlay.cache.visible ~= false then
      overlay.cache.visible = false
      pcall(overlay.Hide, overlay)
    end
    return
  end
  if overlay.cache.visible ~= true then
    overlay.cache.visible = true
    pcall(overlay.Show, overlay)
  end

  -- The client can repopulate recycled plates after adoption. Re-assert the
  -- replacement so native art never draws underneath UnrealUI's overlay.
  MuteNativePlate(parts, plate, overlay)

  -- Re-resolve which fontstring is the level: plates are recycled onto new
  -- units, and a name that happens to be numeric is not worth guarding against
  -- once, only every pass.
  local a, b = parts.fontstrings[1], parts.fontstrings[2]
  if b then
    if IsNumericText(Call(a, "GetText")) then
      parts.level, parts.name = a, b
    else
      parts.name, parts.level = a, b
    end
  end

  local name = Call(parts.name, "GetText")
  local levelText = Call(parts.level, "GetText")
  -- WatchPlates compares against this to spot a plate recycled onto a new unit.
  overlay.cache.plateName = name

  -- WORKING_SOURCE (UnrealPfUI): with no per-plate unit token, the current
  -- target's plate is the fully opaque one.
  local hasTarget = ApiTruth("UnitExists", "target")
  local targetName = hasTarget and ApiString("UnitName", "target") or nil
  overlay.isTarget = hasTarget and plateAlpha >= 1 and
                     (not targetName or targetName == name) and true or false
  if overlay.isTarget then
    targetPlateActive = true
    targetOverlay = overlay
  end

  -- Name, shortened when abbrevNames asks for it (style.Name).
  if overlay.name and name ~= overlay.cache.name then
    overlay.cache.name = name
    overlay.name:SetText(style.Name(name) or "")
  end

  -- Level, with the stock elite/rare marker kept as a suffix. A plate that
  -- carries no level fontstring at all gets a blank slot rather than "??" --
  -- the target layout is a name row with nothing else in it, not an error.
  if overlay.level then
    local suffix = ""
    if parts.levelicon and Call(parts.levelicon, "IsShown") then suffix = "+" end

    local text = ""
    if parts.level then text = (levelText or "??") .. suffix end
    if text ~= overlay.cache.level then
      overlay.cache.level = text
      overlay.level:SetText(text)

      local r, g, b2 = Call(parts.level, "GetTextColor")
      if type(r) == "number" and type(g) == "number" and type(b2) == "number" then
        -- UnrealPfUI lifts the stock level colour by .3 so it stays legible
        -- against the world rather than the stock plate's dark backing.
        r, g, b2 = Clamp(r + 0.3), Clamp(g + 0.3), Clamp(b2 + 0.3)
      else
        r, g, b2 = DifficultyColor(levelText)
      end
      pcall(overlay.level.SetTextColor, overlay.level, r, g, b2, 1)
    end
  end

  -- Reaction: live for the target, then whatever the target or mouseover
  -- last taught about this name (RefreshAll learns both first), then the
  -- creature's base reaction from the bundled database. Resolved before the
  -- health bar, whose visibility depends on it (style.HideHealth).
  local unitType = overlay.isTarget and reaction.Classify("target") or nil
  unitType = unitType or (name and (reaction.byName[name] or
                                    style.CachedFriend(name) or
                                    reaction.FromDatabase(name))) or "ENEMY"
  overlay.cache.unitType = unitType
  style.RefreshColors(overlay, unitType, name)

  -- Before the health bar, whose visibility depends on it (style.HideHealth).
  style.RefreshTotem(overlay, name)

  -- Health
  local value, minimum, maximum = ReadHealth(overlay)
  if value and not style.HideHealth(overlay, unitType, name,
                                    value < maximum) then
    overlay.health:Show()
    overlay.health:SetMinMaxValues(minimum, maximum)
    overlay.health:SetValue(value)

    if overlay.modernWow and maximum > minimum then
      local fraction = (value - minimum) / (maximum - minimum)
      if fraction < 0 then fraction = 0 end
      if fraction > 1 then fraction = 1 end
      if fraction ~= overlay.cache.fillFraction then
        overlay.cache.fillFraction = fraction
        local art = M.modernWow.nameplate
        local cell = art.fill
        local u1 = cell[1] / art.sheet[1]
        local u2 = cell[3] / art.sheet[1]
        overlay.health.uuiFillTexture:SetTexCoord(
          u1, u1 + (u2 - u1) * fraction,
          cell[2] / art.sheet[2], cell[4] / art.sheet[2])
      end
    end

    if overlay.healthText then
      -- current / max from core/unitvitals.lua: the client only reports a
      -- creature's health as 0..100 (knowledge.json
      -- unitframes.nongroup_health_is_percent), and the bundled creature table
      -- gives the exact maximum by name and level. The target gets the
      -- combat-refined current value; any other plate scales the percentage.
      -- Players, pets and creatures missing from the table have no real
      -- maximum, so style.HealthText falls back to the percentage.
      local current, total
      if cfg.showHealthText and maximum > minimum and
         type(U.UnitVitalsHealth) == "function" then
        current, total = U.UnitVitalsHealth(
          overlay.isTarget and "target" or "nameplate",
          name, tonumber(levelText), value - minimum, maximum - minimum)
      end
      if cfg.showHealthText and maximum > minimum then
        local perc = (value - minimum) / (maximum - minimum) * 100
        overlay.healthText:SetText(style.HealthText(current, total, perc))
      else
        overlay.healthText:SetText("")
      end
    end
  else
    -- No health data, or hidden by option: the name/level row stands alone.
    overlay.health:Hide()
    if overlay.healthText then overlay.healthText:SetText("") end
  end

  -- Target emphasis: everything else dimmed, the target outlined (or its
  -- Modern WoW selected art) and optionally zoomed.
  local wantAlpha = 1
  if cfg.fadeOthers and hasTarget and not overlay.isTarget then
    wantAlpha = cfg.otherAlpha
  end
  if wantAlpha ~= overlay.cache.alpha then
    overlay.cache.alpha = wantAlpha
    pcall(overlay.SetAlpha, overlay, wantAlpha)
  end

  style.RefreshOutline(overlay, unitType)
  style.RefreshZoom(overlay)
  style.RefreshStrata(overlay)
  style.RefreshRaidIcon(overlay)

  RefreshTargetAuras(overlay)
  RefreshTargetCast(overlay)
  style.RefreshGuild(overlay, name)
  style.RefreshCombo(overlay)
end

local function RefreshAll()
  statRefreshed = statRefreshed + 1
  targetPlateActive = false
  targetOverlay = nil
  reaction.Learn("target")
  reaction.Learn("mouseover")
  if type(U.PlayerCacheLearn) == "function" then
    U.PlayerCacheLearn("target")
    U.PlayerCacheLearn("mouseover")
  end
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay then
      local ok, err = pcall(RefreshPlate, overlay)
      if not ok then
        failures.refresh = failures.refresh + 1
        failures.lastRefresh = tostring(err)
        U.Debug("nameplate refresh: " .. tostring(err))
      end
    end
  end
end

-- An option changed (U.SetNameplateSetting): drop every plate's draw cache so
-- colours, outlines and text are re-applied, re-run the layout, and redraw now
-- rather than on the next 0.1s tick.
function style.Invalidate()
  if not cfg.enabled then return end
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay then
      overlay.cache = {}
      local ok, err = pcall(style.Layout, overlay)
      if not ok then
        failures.refresh = failures.refresh + 1
        failures.lastRefresh = tostring(err)
      end
    end
  end
  RefreshAll()
end

-- Diagnostic only: which stock parts a recycled plate came back with (see
-- stats.reuse). Reads the parts unrealUI already holds; no region walk.
local function NoteReuse(parts)
  local r = stats.reuse
  r.shows = r.shows + 1
  local invisible = M.fontById and M.fontById.invisible and
                    M.fontById.invisible.path
  local font, fontAlpha, texture, textureAlpha = false, false, false, false
  local i
  for i = 1, table.getn(parts.fontstrings) do
    local fs = parts.fontstrings[i]
    if invisible and Call(fs, "GetFont") ~= invisible then font = true end
    if (tonumber(Call(fs, "GetAlpha")) or 0) > 0.01 then fontAlpha = true end
  end
  for i = 1, table.getn(parts.textures) do
    local tex = parts.textures[i]
    if type(Call(tex, "GetTexture")) == "string" then texture = true end
    if (tonumber(Call(tex, "GetAlpha")) or 0) > 0.01 then textureAlpha = true end
  end
  if font then r.font = r.font + 1 end
  if fontAlpha then r.fontAlpha = r.fontAlpha + 1 end
  if texture then r.texture = r.texture + 1 end
  if textureAlpha then r.textureAlpha = r.textureAlpha + 1 end
  local bar = parts.healthbar
  if bar then
    if (tonumber(Call(bar, "GetHeight")) or 0) > 1 then r.barTall = r.barTall + 1 end
    if (tonumber(Call(bar, "GetAlpha")) or 0) > 0.01 then r.barAlpha = r.barAlpha + 1 end
  end
end

-- Every render tick, but only for plates that just changed: one that appeared,
-- vanished, or was recycled onto another unit (its name text changed). Without
-- it the stock plate, or the overlay still hidden from the plate's last use,
-- showed for up to one 0.1s refresh before the finished overlay replaced it
-- (user-reported flicker, 2026-10-19). Health and the rest stay on RefreshAll.
local function WatchPlates()
  ScanWorldFrame()
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay then
      local visible = Call(overlay.plate, "IsVisible") and true or false
      local changed = visible ~= overlay.cache.visible
      if not changed and visible then
        changed = Call(overlay.parts.name, "GetText") ~= overlay.cache.plateName
      end
      if visible and overlay.cache.visible == false then
        pcall(NoteReuse, overlay.parts)
      end
      if changed then
        local ok, err = pcall(RefreshPlate, overlay)
        if not ok then
          failures.refresh = failures.refresh + 1
          failures.lastRefresh = tostring(err)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- The detection path above is WORKING_SOURCE, not measured. This is what turns
-- one in-game run into the evidence that closes the gap.
-- ---------------------------------------------------------------------------
-- Read by core/perf.lua's export alongside U.SuppressionStats.
function U.NameplateStats()
  return {
    scans = statScans,
    rescans = statRescans,
    classified = statClassified,
    refreshPasses = statRefreshed,
    plates = plateCount,
    worldChildren = stats.worldChildren,
    minChildren = stats.minChildren,
    maxChildren = stats.maxChildren,
    adopted = stats.plates,
    -- Flat numbers only: core/perf.lua saves this table as-is.
    reuseShows = stats.reuse.shows,
    reuseFont = stats.reuse.font,
    reuseFontAlpha = stats.reuse.fontAlpha,
    reuseTexture = stats.reuse.texture,
    reuseTextureAlpha = stats.reuse.textureAlpha,
    reuseBarTall = stats.reuse.barTall,
    reuseBarAlpha = stats.reuse.barAlpha,
  }
end

-- Read-only view of the adopted overlays for UnrealRuntimeProbe's npflicker
-- group: it reads the parts unrealUI already holds instead of walking
-- WorldFrame, whose per-frame GetRegions/GetChildren walk crashed the client
-- (nameplates.flicker_probe_walk_crash).
function U.NameplateOverlays()
  return plateOrder
end

function U.NameplateReport()
  local report = {
    enabled = cfg.enabled,
    worldChildren = stats.worldChildren,
    scanned = scannedChildren,
    plates = stats.plates,
    rejected = stats.rejected,
    withHealthBar = stats.withHealthBar,
    detector = stats.detector,
    minChildren = stats.minChildren,
    maxChildren = stats.maxChildren,
  }

  -- First live plate, described part by part.
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay and Call(overlay.plate, "IsVisible") then
      local parts = overlay.parts
      report.sample = {
        frameType = ObjectType(overlay.plate),
        regions = table.getn(parts.textures) + table.getn(parts.fontstrings),
        textures = table.getn(parts.textures),
        fontstrings = table.getn(parts.fontstrings),
        name = Call(parts.name, "GetText"),
        level = Call(parts.level, "GetText"),
        hasHealthBar = parts.healthbar and true or false,
        hasCastBar = parts.castbar and true or false,
        hasBorder = parts.border and true or false,
        hasGlow = parts.glow and true or false,
        isTarget = overlay.isTarget,
      }

      local value, minimum, maximum = ReadHealth(overlay)
      report.sample.health = value
      report.sample.healthMin = minimum
      report.sample.healthMax = maximum

      -- The raw tint is printed when it does not map to a known unit type: an
      -- unrecognised triple is the thing that would silently colour every plate
      -- hostile, so it has to be readable rather than inferred.
      local r, g, b = Call(parts.healthbar, "GetStatusBarColor")
      local mapped = UnitTypeFromBarColor(r, g, b)
      if mapped then
        report.sample.barColor = mapped
      elseif type(r) == "number" and type(g) == "number" and type(b) == "number" then
        report.sample.barColor = string.format("unmapped %.2f,%.2f,%.2f", r, g, b)
      else
        report.sample.barColor = "none"
      end
      break
    end
  end

  report.rejectReasons = rejectReasons
  return report
end

-- Raw description of every WorldFrame child, whether or not it was adopted.
--
-- The first in-game run reported 28 children and 0 plates, which says the
-- signature is wrong but not how. This is the readout that answers it: object
-- type, region and child composition, the texture paths and the fontstring
-- text actually present. It reads only -- nothing here mutes or adopts.
local function DumpWorldChildren()
  local out = {}

  local worldFrame = U.G("WorldFrame")
  if not worldFrame then return out end

  local count = tonumber(Call(worldFrame, "GetNumChildren")) or 0
  local ok, kids = pcall(function() return { worldFrame:GetChildren() } end)
  if not ok or type(kids) ~= "table" then return out end

  local i, j
  for i = 1, count do
    local child = kids[i]
    if child then
      local entry = {
        index = i,
        otype = ObjectType(child) or "?",
        name = Call(child, "GetName"),
        visible = Call(child, "IsVisible") and true or false,
        width = tonumber(Call(child, "GetWidth")),
        height = tonumber(Call(child, "GetHeight")),
        adopted = registry[child] and true or false,
        textures = 0,
        fontstrings = 0,
        children = 0,
        texturePaths = {},
        texts = {},
        childTypes = {},
      }

      local rOk, regions = pcall(function() return { child:GetRegions() } end)
      if rOk and type(regions) == "table" then
        for j = 1, table.getn(regions) do
          local regionType = ObjectType(regions[j])
          if regionType == "Texture" then
            entry.textures = entry.textures + 1
            local path = Call(regions[j], "GetTexture")
            if type(path) == "string" and table.getn(entry.texturePaths) < 4 then
              -- Only the tail is useful and chat lines are short.
              table.insert(entry.texturePaths, string.sub(path, -28))
            end
          elseif regionType == "FontString" then
            entry.fontstrings = entry.fontstrings + 1
            local text = Call(regions[j], "GetText")
            if type(text) == "string" and table.getn(entry.texts) < 3 then
              table.insert(entry.texts, text)
            end
          end
        end
      end

      local cOk, subs = pcall(function() return { child:GetChildren() } end)
      if cOk and type(subs) == "table" then
        entry.children = table.getn(subs)
        for j = 1, entry.children do
          if table.getn(entry.childTypes) < 3 then
            local hasValue = false
            pcall(function() hasValue = type(subs[j].GetValue) == "function" end)
            table.insert(entry.childTypes,
              (ObjectType(subs[j]) or "?") .. (hasValue and "*" or ""))
          end
        end
      end

      table.insert(out, entry)
    end
  end

  return out
end

local function Round(value)
  if type(value) ~= "number" then return value end
  return math.floor(value * 100 + 0.5) / 100
end

local function DescribeFrame(frame)
  if not frame then return nil end
  -- Call() keeps four returns; GetPoint has five.
  local point, relativePoint, x, y
  pcall(function()
    local _
    point, _, relativePoint, x, y = frame:GetPoint(1)
  end)
  return {
    name = Call(frame, "GetName"),
    shown = Call(frame, "IsShown") and true or false,
    visible = Call(frame, "IsVisible") and true or false,
    alpha = Round(tonumber(Call(frame, "GetAlpha"))),
    width = Round(tonumber(Call(frame, "GetWidth"))),
    height = Round(tonumber(Call(frame, "GetHeight"))),
    strata = Call(frame, "GetFrameStrata"),
    point = point and (tostring(point) .. ">" .. tostring(relativePoint) ..
                       " " .. tostring(Round(x)) .. "," .. tostring(Round(y)))
                  or nil,
  }
end

-- Every adopted plate and the overlay drawn over it. "The nameplate
-- disappeared" has four distinct causes and each leaves a different trace:
-- nothing adopted (no plate entries), only FrameXML false positives adopted
-- (every entry suspect), the plate adopted but the overlay hidden or
-- transparent (plate visible, overlay not), or a refresh error (failures).
local function DumpPlates()
  local out = {}
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay then
      local parts = overlay.parts or {}
      local value, minimum, maximum = ReadHealth(overlay)
      local nativeName = Call(parts.name, "GetText")
      table.insert(out, {
        learnedType = nativeName and reaction.byName[nativeName] or "unseen",
        drawnType = overlay.cache and overlay.cache.unitType,
        targetReaction = overlay.isTarget and
                         ApiNumber("UnitReaction", "target", "player") or nil,
        id = overlay.id,
        detector = parts.detector,
        suspect = IsNamedFrame(overlay.plate),
        plate = DescribeFrame(overlay.plate),
        overlay = DescribeFrame(overlay),
        health = DescribeFrame(overlay.health),
        nativeName = Call(parts.name, "GetText"),
        nativeLevel = Call(parts.level, "GetText"),
        drawnName = Call(overlay.name, "GetText"),
        drawnHealthText = Call(overlay.healthText, "GetText"),
        healthValue = value,
        healthMin = minimum,
        healthMax = maximum,
        isTarget = overlay.isTarget and true or false,
        cachedVisible = overlay.cache and overlay.cache.visible,
        modernWow = overlay.modernWow and true or false,
      })
    end
  end
  return out
end

function U.NameplateDump()
  local children = DumpWorldChildren()
  local plates = DumpPlates()

  local summary = {
    enabled = cfg.enabled and true or false,
    showHealthText = cfg.showHealthText and true or false,
    theme = U.GetActiveThemeStyle and U.GetActiveThemeStyle() or nil,
    worldChildren = table.getn(children),
    minChildren = stats.minChildren,
    maxChildren = stats.maxChildren,
    adopted = table.getn(plates),
    suspect = 0,
    real = 0,
    overlaysVisible = 0,
    plateVisibleOverlayHidden = 0,
    unnamedChildren = 0,
    buildFailures = failures.build,
    lastBuildError = failures.lastBuild,
    refreshFailures = failures.refresh,
    lastRefreshError = failures.lastRefresh,
    namedRejected = rejectReasons["named-frame"] or 0,
    -- Vanilla FrameXML's enemy-plate toggle state; nil if this client has none.
    nameplatesOn = U.G("NAMEPLATES_ON"),
    arrivals = table.getn(arrivals),
    suspectNames = {},
  }

  local i
  for i = 1, table.getn(plates) do
    local p = plates[i]
    if p.suspect then
      summary.suspect = summary.suspect + 1
      table.insert(summary.suspectNames, p.plate and p.plate.name or "?")
    else
      summary.real = summary.real + 1
    end
    if p.overlay and p.overlay.visible then
      summary.overlaysVisible = summary.overlaysVisible + 1
    end
    if p.plate and p.plate.visible and
       not (p.overlay and p.overlay.visible and (p.overlay.alpha or 1) > 0) then
      summary.plateVisibleOverlayHidden = summary.plateVisibleOverlayHidden + 1
    end
  end

  for i = 1, table.getn(children) do
    local name = children[i].name
    if type(name) ~= "string" or string.find(name, "^GeneratedLuaUIObject_") then
      summary.unnamedChildren = summary.unnamedChildren + 1
    end
  end

  -- One machine-readable answer, most decisive cause first.
  if not cfg.enabled then
    summary.verdict = "module-disabled"
  elseif summary.refreshFailures > 0 then
    summary.verdict = "refresh-error"
  elseif summary.real == 0 and summary.minChildren == summary.maxChildren then
    -- Plates come and go on screen while WorldFrame's child count never moves:
    -- the plates drawn are the engine's, not Lua widgets.
    summary.verdict = "no-lua-plates"
  elseif summary.real == 0 then
    summary.verdict = "no-real-plate-adopted"
  elseif summary.plateVisibleOverlayHidden > 0 then
    summary.verdict = "overlay-hidden-on-visible-plate"
  elseif summary.overlaysVisible == 0 then
    summary.verdict = "no-plate-visible-now"
  else
    summary.verdict = "overlays-drawing"
  end

  return { summary = summary, plates = plates, arrivals = arrivals,
           children = children }
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------
function NP:OnInit()
  cfg = U.ModuleConfig("nameplates", defaults)
  -- The pages live in modules/nameplatesettings.lua.
  if type(U.RegisterNameplateSettings) == "function" then
    U.RegisterNameplateSettings()
  end
end

function NP:OnEnable()
  if not cfg.enabled then return end

  -- Plates are created natively (UnrealRuntimeProbe npcreate: no Lua
  -- CreateFrame), so a new one draws one stock frame before any Lua runs
  -- (nameplates.new_plate_first_frame_stock). Its text font is the one input
  -- that frame takes from Lua: the client's plate builder reads the
  -- NAMEPLATE_FONT global (the name sits beside FNamePlateFrame's hard-coded
  -- Nameplate-Border / UI-TargetingFrame-BarFill paths in the executable), so
  -- pointing it at the invisible font keeps that frame's name and level
  -- blank. The bar and border art are hard-coded and still show for it.
  -- MuteFontString applies the same font after adoption, and the text stays
  -- readable through GetText.
  local invisible = M.fontById and M.fontById.invisible
  if invisible and type(invisible.path) == "string" and
     type(U.G("NAMEPLATE_FONT")) == "string" then
    NAMEPLATE_FONT = invisible.path
  end

  -- The hostile/friendly switches need a ready world (ShowNameplates is
  -- documented as a no-op before that), and a loading screen may reset them.
  -- OnEnable itself may run on that very event (core/init.lua), so apply once
  -- now as well.
  U.RegisterEvent("PLAYER_ENTERING_WORLD", style.ApplyVisibility)
  style.ApplyVisibility()

  -- Discovery is cheap while the child count is unchanged, so it can share the
  -- refresh tick. A plate that appears or changes unit is caught sooner, on the
  -- next render tick, by WatchPlates.
  U.RegisterUpdate("nameplates.scan", 0.1, function()
    if U.PerfDisabled and U.PerfDisabled("plates") then return end
    ScanWorldFrame()
    RefreshAll()
  end)
  U.RegisterUpdate("nameplates.watch", 0, function()
    if U.PerfDisabled and U.PerfDisabled("plates") then return end
    WatchPlates()
  end)
end
