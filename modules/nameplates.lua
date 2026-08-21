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
-- None of pfUI's nameplate subsystem is reproduced. There are no debuff icons,
-- combo points, totem icons, castbars, raid icons, threat/combat-state colours,
-- click handling, mouselook emulation, visibility filtering or config GUI here.
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
  fadeOthers     = true,   -- dim plates that are not the current target
  otherAlpha     = 0.75,
}

local cfg = defaults

-- ---------------------------------------------------------------------------
-- Colours
--
-- Read from the native health bar's own tint, the way UnrealPfUI derives unit
-- type, then mapped onto unrealUI's muted palette rather than the client's
-- saturated primaries.
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

-- knowledge.json / core.getdifficultycolor_missing. Thresholds are Vanilla's;
-- only used when the native level fontstring has no colour to copy.
local function DifficultyColor(level)
  level = tonumber(level) or 0
  local playerLevel = ApiNumber("UnitLevel", "player") or 1

  if level <= 0 then return 0.69, 0.69, 0.69 end
  if level >= playerLevel + 5 then return 1.00, 0.10, 0.10 end
  if level >= playerLevel + 3 then return 1.00, 0.50, 0.10 end
  if level >= playerLevel - 2 then return 1.00, 1.00, 0.00 end
  if level > playerLevel - 8 then return 0.25, 0.75, 0.25 end
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
  pcall(function() region:SetAlpha(0) end)
end

-- A native bar frame plus its own regions: parent_alpha_not_propagated means
-- zeroing the frame alone is not enough to stop the fill drawing.
local function MuteBar(bar)
  if not bar then return end
  pcall(function() bar:SetStatusBarTexture(nil) end)
  pcall(function() bar:SetAlpha(0) end)

  local ok, regions = pcall(function() return { bar:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return end
  local i
  for i = 1, table.getn(regions) do
    if ObjectType(regions[i]) == "Texture" then MuteTexture(regions[i]) end
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
}

-- Why a WorldFrame child was not adopted. Measured first-pass result on this
-- client: 28 children, 0 plates, 28 rejected -- so the reason has to be
-- reportable rather than inferred from the layout not changing.
local rejectReasons = {}

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

local function ClassifyPlate(frame)
  statClassified = statClassified + 1
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
  overlay.plate = frame
  overlay.parts = parts
  overlay.cache = {}

  -- WORKING_SOURCE (UnrealPfUI): a WorldFrame-child overlay is scaled to the UI
  -- scale so plate sizes read in the same units as the rest of the addon.
  pcall(function() overlay:SetScale(UIParent:GetScale()) end)

  overlay:SetWidth(cfg.width)
  overlay:SetHeight(cfg.healthHeight + cfg.nameSize + 4)
  overlay:SetPoint("TOP", frame, "TOP", 0, cfg.verticalOffset)

  local health = U.CreateStatusBar(overlay, {
    width = cfg.width,
    height = cfg.healthHeight,
    color = UNIT_COLOR.ENEMY,
    background = M.color.healthBg,
  })
  health:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
  -- Border only: U.CreateStatusBar already owns the bar's background texture,
  -- so the full backdrop would just paint a second fill behind it.
  U.CreateBorder(health)
  U.SetBorderColor(health, M.Unpack(M.color.border))
  overlay.health = health

  -- Percentage, centred in the bar. Its own layer so the fill never covers it.
  overlay.healthText = U.CreateLabel(health, {
    size = cfg.healthTextSize,
    color = M.color.text,
    inherits = "GameFontNormal",
  })
  if overlay.healthText then
    overlay.healthText:SetPoint("CENTER", health, "CENTER", 0, 0)
  end

  -- Name on the bar's left edge, level on its right: one anchor each, per
  -- fonts.stretched_justification_ignored.
  overlay.name = U.CreateLabel(overlay, {
    size = cfg.nameSize,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
  })
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

  overlay:Show()
  return overlay
end

local function AdoptPlate(frame)
  local parts = ClassifyPlate(frame)
  if not parts then
    stats.rejected = stats.rejected + 1
    return nil
  end

  MuteTexture(parts.border)
  MuteTexture(parts.glow)
  MuteTexture(parts.raidicon)
  MuteFontString(parts.name)
  MuteFontString(parts.level)
  MuteBar(parts.healthbar)
  MuteBar(parts.castbar)

  -- Anything not classified above is stock art unrealUI is replacing. The elite
  -- icon is the one exception: it is muted but still read via IsShown().
  local i
  for i = 1, table.getn(parts.textures) do
    local region = parts.textures[i]
    if region ~= parts.border and region ~= parts.glow and
       region ~= parts.raidicon then
      MuteTexture(region)
    end
  end
  for i = 1, table.getn(parts.fontstrings) do
    MuteFontString(parts.fontstrings[i])
  end

  local overlay = BuildOverlay(frame, parts)
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

  local i
  for i = scannedChildren + 1, count do
    local child = kids[i]
    if child and not registry[child] then AdoptPlate(child) end
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
  if not visible then return end

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

  -- WORKING_SOURCE (UnrealPfUI): with no per-plate unit token, the current
  -- target's plate is the fully opaque one.
  local hasTarget = ApiTruth("UnitExists", "target")
  local plateAlpha = tonumber(Call(plate, "GetAlpha")) or 1
  overlay.isTarget = hasTarget and plateAlpha >= 1 and true or false

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

    if overlay.healthText then
      if cfg.showHealthText and maximum > minimum then
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

  -- Bar colour from the native bar's tint, which is the only unit-type signal
  -- available for a plate that is not the target.
  local r, g, b2 = Call(parts.healthbar, "GetStatusBarColor")
  local unitType = UnitTypeFromBarColor(r, g, b2)

  if not unitType and overlay.isTarget then
    if ApiTruth("UnitIsPlayer", "target") and
       not ApiTruth("UnitCanAttack", "player", "target") then
      unitType = "FRIENDLY_UNIT"
    else
      local reaction = ApiNumber("UnitReaction", "target", "player")
      if reaction then
        if reaction <= 3 then unitType = "ENEMY"
        elseif reaction == 4 then unitType = "NEUTRAL"
        else unitType = "FRIENDLY_NPC" end
      end
    end
  end

  unitType = unitType or "ENEMY"
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
    if overlay.isTarget then
      U.SetBorderColor(overlay.health, M.Unpack(M.color.accent))
    else
      U.SetBorderColor(overlay.health, M.Unpack(M.color.border))
    end
  end
end

local function RefreshAll()
  statRefreshed = statRefreshed + 1
  local i
  for i = 1, table.getn(plateOrder) do
    local overlay = plateOrder[i]
    if overlay then
      local ok, err = pcall(RefreshPlate, overlay)
      if not ok then U.Debug("nameplate refresh: " .. tostring(err)) end
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
  }
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
function U.NameplateDump()
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

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------
function NP:OnInit()
  cfg = U.ModuleConfig("nameplates", defaults)
end

function NP:OnEnable()
  if not cfg.enabled then return end

  -- Discovery is cheap while the child count is unchanged, so it can share the
  -- refresh tick. 0.1s keeps a new plate from lagging visibly behind the stock
  -- one it replaces.
  U.RegisterUpdate("nameplates.scan", 0.1, function()
    if U.PerfDisabled and U.PerfDisabled("plates") then return end
    ScanWorldFrame()
    RefreshAll()
  end)
end
