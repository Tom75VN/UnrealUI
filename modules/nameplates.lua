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
-- None of pfUI's nameplate subsystem is reproduced. There are no combo points,
-- totem icons, raid icons, threat/combat-state colours, click handling,
-- mouselook emulation or visibility filtering here.
-- Those are separate scope.
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
  nameSize       = 12,
  levelSize      = 12,
  healthTextSize = 11,
  verticalOffset = 0,
  showHealthText = true,
  showAuras      = true,
  attachTargetCast = true,
  fadeOthers     = true,   -- dim plates that are not the current target
  otherAlpha     = 0.75,
}

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

local function SetDisplaySetting(key, value)
  local settings = U.ModuleConfig("nameplates", defaults)
  settings[key] = value and true or false
  cfg = settings
end

local function BuildSettingsPage(parent)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("SETTINGS_PAGE_NAMEPLATES"),
    width = 484,
    y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsNameplates",
    text = U.L("SETTINGS_NAMEPLATES"),
    value = U.NameplatesEnabled(),
    onChange = function(value) U.SetNameplatesEnabled(value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local auras = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsNameplateAuras",
    text = U.L("SETTINGS_NAMEPLATE_AURAS"),
    value = cfg.showAuras,
    onChange = function(value) SetDisplaySetting("showAuras", value) end,
  })
  auras.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -66)
  table.insert(widgets, auras)

  local targetCast = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsNameplateTargetCast",
    text = U.L("SETTINGS_NAMEPLATE_CASTBAR"),
    value = cfg.attachTargetCast,
    onChange = function(value) SetDisplaySetting("attachTargetCast", value) end,
  })
  targetCast.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -98)
  table.insert(widgets, targetCast)

  local function Refresh()
    enable.SetValue(U.NameplatesEnabled())
    auras.SetValue(cfg.showAuras)
    targetCast.SetValue(cfg.attachTargetCast)
  end

  return widgets, Refresh
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
local reaction = { byName = {} }

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
  if name then reaction.byName[name] = unitType end
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
    MuteTexture(parts.textures[i])
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

  pcall(overlay.SetFrameStrata, overlay, "LOW")

  -- WORKING_SOURCE (UnrealPfUI): a WorldFrame-child overlay is scaled to the UI
  -- scale so plate sizes read in the same units as the rest of the addon.
  pcall(function() overlay:SetScale(UIParent:GetScale()) end)

  local artScale = nameplateArt and nameplateArt.scale or 1
  local plateWidth = cfg.width * artScale
  local healthHeight = (nameplateArt and nameplateArt.healthHeight or
                        cfg.healthHeight) * artScale

  overlay:SetWidth(plateWidth)
  overlay:SetHeight(healthHeight + cfg.nameSize + 4)
  overlay:SetPoint("TOP", frame, "TOP", 0,
                   PLATE_LIFT + cfg.verticalOffset)

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
    local inset = nameplateArt.backgroundInset
    health.uuiFillTexture:SetTexCoord(
      fill[1] / sheet[1], fill[3] / sheet[1],
      fill[2] / sheet[2], fill[4] / sheet[2])
    health.uuiBackground:SetTexture(nameplateArt.texture)
    health.uuiBackground:SetTexCoord(
      background[1] / sheet[1], background[3] / sheet[1],
      background[2] / sheet[2], background[4] / sheet[2])
    health.uuiBackground:ClearAllPoints()
    health.uuiBackground:SetPoint(
      "TOPLEFT", health, "TOPLEFT",
      inset.left * artScale, inset.top * artScale)
    health.uuiBackground:SetPoint(
      "BOTTOMRIGHT", health, "BOTTOMRIGHT",
      inset.right * artScale, inset.bottom * artScale)

    local selected = health:CreateTexture(nil, "OVERLAY")
    selected:SetTexture(nameplateArt.selectedTexture)
    inset = nameplateArt.selectedInset
    selected:SetPoint("TOPLEFT", health, "TOPLEFT",
                      inset.left * artScale, inset.top * artScale)
    selected:SetPoint(
      "BOTTOMRIGHT", health, "BOTTOMRIGHT",
      inset.right * artScale, inset.bottom * artScale)
    selected:Hide()
    overlay.selectedBorder = selected
  elseif not modern then
    -- Border only: U.CreateStatusBar already owns the bar background.
    U.CreateBorder(health)
    U.SetBorderColor(health, M.Unpack(M.color.border))
  end
  overlay.health = health

  -- Its own layer so the fill never covers the percentage.
  overlay.healthText = U.CreateLabel(health, {
    size = modernWow and 9 or cfg.healthTextSize,
    color = M.color.text,
    inherits = "GameFontNormal",
  })
  if overlay.healthText then
    overlay.healthText:SetPoint("CENTER", health, "CENTER", 0, 0)
  end

  -- One anchor per label, per fonts.stretched_justification_ignored.
  overlay.name = U.CreateLabel(overlay, {
    size = cfg.nameSize,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
    -- The fixed width below centres the text inside it unless told otherwise.
    justify = (modern or classic) and "LEFT" or nil,
  })
  if overlay.name then
    if modernWow then
      overlay.name:Hide()
    else
      overlay.name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 2)
      overlay.name:SetWidth(plateWidth - 28)
    end
  end

  overlay.level = U.CreateLabel(overlay, {
    size = cfg.levelSize,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
  })
  if overlay.level then
    overlay.level:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 2)
  end

  local cast = U.CreateStatusBar(overlay, {
    width = plateWidth,
    height = modernWow and 9 or 12,
    color = M.color.cast,
    background = M.color.healthBg,
    texture = nativeTexture,
  })
  cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
  U.CreateBorder(cast)
  U.SetBorderColor(cast, M.Unpack(M.color.border))
  cast:Hide()
  overlay.cast = cast

  overlay.castName = U.CreateLabel(cast, {
    size = M.fontSize.tiny,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if overlay.castName then
    overlay.castName:SetPoint("LEFT", cast, "LEFT", 3, 0)
    overlay.castName:SetWidth(plateWidth - 42)
  end

  overlay.castTime = U.CreateLabel(cast, {
    size = M.fontSize.tiny,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "RIGHT",
  })
  if overlay.castTime then
    overlay.castTime:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
  end

  if type(U.CreateNameplateAuraRows) == "function" then
    local auraArt = modernWow and M.modernWow.nameplateAura or nil
    local auraOffset = auraArt and
                       (auraArt.size + auraArt.gap -
                        auraArt.overlayInset.bottom) or
                       cfg.nameSize + 30
    overlay.auraRows = U.CreateNameplateAuraRows(
      health, overlay, overlay.id, auraOffset)
  end

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

local function RefreshTargetCast(overlay)
  if not cfg.attachTargetCast or not overlay.isTarget or
     type(U.TargetCastInfo) ~= "function" then
    overlay.cast:Hide()
    return
  end

  local spell, elapsed, duration = U.TargetCastInfo()
  if not spell or not duration then
    overlay.cast:Hide()
    return
  end

  overlay.cast:SetMinMaxValues(0, duration)
  overlay.cast:SetValue(elapsed)
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

  -- Name
  if overlay.name and name ~= overlay.cache.name then
    overlay.cache.name = name
    overlay.name:SetText(name or "")
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

  -- Health
  local value, minimum, maximum = ReadHealth(overlay)
  if value then
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
      local current, total
      if cfg.showHealthText and maximum > minimum and
         type(U.UnitVitalsHealth) == "function" then
        current, total = U.UnitVitalsHealth(
          overlay.isTarget and "target" or "nameplate",
          name, tonumber(levelText), value - minimum, maximum - minimum)
      end
      if current and total then
        overlay.healthText:SetText(string.format("%d / %d",
          math.floor(current + 0.5), math.floor(total + 0.5)))
      elseif cfg.showHealthText and maximum > minimum then
        -- Players, pets and creatures missing from the table: no real
        -- maximum exists, so the percentage stays rather than "68 / 100".
        local perc = (value - minimum) / (maximum - minimum) * 100
        overlay.healthText:SetText(string.format("%.1f%%", perc))
      else
        overlay.healthText:SetText("")
      end
    end
  else
    -- No health data at all: a name/level row on its own beats an empty bar.
    overlay.health:Hide()
    if overlay.healthText then overlay.healthText:SetText("") end
  end

  -- Bar colour by reaction: live for the target, then whatever the target or
  -- mouseover last taught about this name (RefreshAll learns both first), then
  -- the creature's base reaction from the bundled database.
  local unitType = overlay.isTarget and reaction.Classify("target") or nil
  unitType = unitType or (name and (reaction.byName[name] or
                                    reaction.FromDatabase(name))) or "ENEMY"
  if unitType ~= overlay.cache.unitType then
    overlay.cache.unitType = unitType
    U.SetStatusBarColor(overlay.health, M.Unpack(UNIT_COLOR[unitType]))
  end

  -- Target emphasis: the accent border, and everything else dimmed.
  local wantAlpha = 1
  if cfg.fadeOthers and hasTarget and not overlay.isTarget then
    wantAlpha = cfg.otherAlpha
  end
  if wantAlpha ~= overlay.cache.alpha then
    overlay.cache.alpha = wantAlpha
    pcall(overlay.SetAlpha, overlay, wantAlpha)
  end

  local borderKey = overlay.isTarget and "target" or "normal"
  if borderKey ~= overlay.cache.border then
    overlay.cache.border = borderKey
    if overlay.selectedBorder then
      if overlay.isTarget then
        overlay.selectedBorder:Show()
      else
        overlay.selectedBorder:Hide()
      end
    elseif overlay.isTarget then
      U.SetBorderColor(overlay.health, M.Unpack(M.color.accent))
    else
      U.SetBorderColor(overlay.health, M.Unpack(M.color.border))
    end
  end

  RefreshTargetAuras(overlay)
  RefreshTargetCast(overlay)
end

local function RefreshAll()
  statRefreshed = statRefreshed + 1
  targetPlateActive = false
  targetOverlay = nil
  reaction.Learn("target")
  reaction.Learn("mouseover")
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
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("nameplates", U.L("SETTINGS_PAGE_NAMEPLATES"),
                          BuildSettingsPage, { after = "general" })
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
