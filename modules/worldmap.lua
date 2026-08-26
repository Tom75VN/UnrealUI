-- unrealUI :: modules/worldmap.lua
--
-- Cursor coordinates and zone level ranges on the world map.
--
-- Hovering a zone on a continent map exposes that zone's name through the map
-- frame (the supplied LevelRange-Turtle source reads WorldMapFrame.areaName)
-- and through the native WorldMapFrameAreaLabel. This module reads the first
-- available name, looks up the zone's level range and draws it beside the
-- native name, coloured against the player's own level.
--
-- The native map is otherwise left completely alone -- no chrome suppression,
-- no reskin, no window layout. rules/unreal-ui.md keeps the map out of scope
-- beyond what is explicitly requested, and this is the requested part only.
--
-- ---------------------------------------------------------------------------
-- Why the native label is extended directly
-- ---------------------------------------------------------------------------
--
-- Runtime traces proved that a bare addon FontString child can report shown,
-- positioned and opaque throughout the first fullscreen-map presentation yet
-- remain visually absent until the map is opened again. unrealQuest's working
-- first-open overlays are not bare text children: they are Button frames with
-- a file-backed texture, with any label attached to that proven surface.
--
-- A hover range does not need a new map surface at all. The stock
-- WorldMapFrameAreaLabel is already in the first draw, and the supplied
-- LevelRange-Turtle implementation extends that native label. This module does
-- the same with an inline colour escape and re-applies only when the client
-- rewrites the label. No stock script is hooked or replaced.
--
-- ---------------------------------------------------------------------------
-- Evidence
-- ---------------------------------------------------------------------------
--
--   * behavior.json / mapwindow.layout_inventory.v1 (SUPPORTED,
--     BEHAVIOR_VERIFIED): WorldMapFrameAreaLabel exists on this client and is
--     a FontString; WorldMapFrame, WorldMapButton and WorldMapDetailFrame are
--     present with it.
--   * LevelRange-Turtle 2.0.3 / LevelRange_WorldMapButton_OnUpdate
--     (WORKING_SOURCE, not runtime verification): reads the hovered name from
--     WorldMapFrame.areaName. This module prefers that field and falls back to
--     the native label, so either stock hover path can supply the name.
--   * documentation.json / global:Mapping:UpdateMapHighlight
--     (DOCUMENTED_NOT_RUNTIME_VERIFIED): the client documents the hover
--     hit-test that returns the area name under the cursor, which is what the
--     stock map feeds into that label.
--   * McMapCoords / McMapCoords.lua (WORKING_SOURCE, not runtime
--     verification): normalises GetCursorPosition against WorldMapButton and
--     displays the result as percentages. CursorMapPosition below uses the
--     same conversion, backed by this client's verified cursor/geometry data.
--   * knowledge.json / map.worldmap_child_render_user_confirmed and
--     behavior.json / questarea.label.visual.v1 (SUPPORTED,
--     BEHAVIOR_VERIFIED): a level-120 Button child of WorldMapButton with one
--     file-backed WHITE8X8 BACKGROUND texture and an attached FontString is
--     visible on this client's fullscreen map. The coordinate readout keeps
--     that proven construction and disables its mouse input.
--   * That the label is actually populated on hover is Vanilla behaviour and
--     is NOT runtime-verified here. Everything below degrades to drawing
--     nothing if it is not: an empty or unrecognised label simply hides the
--     range, so a wrong assumption costs a missing readout, never an error.
--   * environment.json / GetLocale returned "enUS", so the table below is
--     keyed on English zone names. On another locale no key matches and the
--     readout stays hidden rather than showing something wrong.
--
-- The ranges themselves come from the supplied LevelRange-Turtle 2.0.3
-- content table, not from measured creature data. They are content data, not
-- client behaviour, so they belong here rather than in compatibility evidence.

local U = UnrealUI
local M = U.media

local WMAP = U.RegisterModule("worldmap")

-- Zone name -> { minimum level, maximum level }.
--
-- The base ranges and custom-region additions follow LevelRange-Turtle 2.0.3,
-- the content reference supplied for this feature. Cosmic-map continents are
-- deliberately absent: they have no meaningful level range, and no entry
-- means no readout.
local ZONES = {
  -- Eastern Kingdoms
  ["Elwynn Forest"]        = { 1, 10 },
  ["Dun Morogh"]           = { 1, 10 },
  ["Tirisfal Glades"]      = { 1, 10 },
  ["Loch Modan"]           = { 10, 20 },
  ["Westfall"]             = { 10, 20 },
  ["Silverpine Forest"]    = { 10, 20 },
  ["Redridge Mountains"]   = { 15, 25 },
  ["Duskwood"]             = { 18, 30 },
  ["Wetlands"]             = { 20, 30 },
  ["Hillsbrad Foothills"]  = { 20, 30 },
  ["Alterac Mountains"]    = { 30, 40 },
  ["Arathi Highlands"]     = { 30, 40 },
  ["Stranglethorn Vale"]   = { 30, 45 },
  ["Badlands"]             = { 35, 45 },
  ["Swamp of Sorrows"]     = { 35, 45 },
  ["The Hinterlands"]      = { 40, 50 },
  ["Searing Gorge"]        = { 43, 50 },
  ["Blasted Lands"]        = { 45, 55 },
  ["Burning Steppes"]      = { 50, 58 },
  ["Western Plaguelands"]  = { 51, 58 },
  ["Eastern Plaguelands"]  = { 53, 60 },
  ["Deadwind Pass"]        = { 55, 60 },

  -- Emberveil / Turtle custom regions
  ["Thalassian Highlands"] = { 1, 10 },
  ["Gilneas"]              = { 39, 46 },
  ["Scarlet Enclave"]      = { 55, 60 },

  -- Kalimdor
  ["Teldrassil"]           = { 1, 10 },
  ["Durotar"]              = { 1, 10 },
  ["Mulgore"]              = { 1, 10 },
  ["Darkshore"]            = { 10, 20 },
  ["The Barrens"]          = { 10, 25 },
  ["Stonetalon Mountains"] = { 15, 27 },
  ["Ashenvale"]            = { 18, 30 },
  ["Thousand Needles"]     = { 25, 35 },
  ["Desolace"]             = { 30, 40 },
  ["Dustwallow Marsh"]     = { 35, 45 },
  ["Feralas"]              = { 40, 50 },
  ["Tanaris"]              = { 40, 50 },
  ["Azshara"]              = { 45, 55 },
  ["Felwood"]              = { 48, 55 },
  ["Un'Goro Crater"]       = { 48, 55 },
  ["Silithus"]             = { 55, 60 },
  ["Winterspring"]         = { 55, 60 },
  ["Moonglade"]            = { 1, 60 },

  -- Emberveil / Turtle custom regions
  ["Blackstone Island"]    = { 1, 10 },
  ["Gillijim's Isle"]      = { 48, 53 },
  ["Lapidis Isle"]         = { 48, 53 },
  ["Tel'Abim"]             = { 54, 60 },
  ["Hyjal"]                = { 58, 60 },
}

-- The reference addon resolves capital-city overlays to their surrounding
-- outdoor zone. This matters on continent view because the map can report the
-- city name even though the requested readout is the region's level range.
local ZONE_ALIASES = {
  ["Orgrimmar"]      = "Durotar",
  ["Thunder Bluff"]  = "Mulgore",
  ["Undercity"]      = "Tirisfal Glades",
  ["Ironforge"]      = "Dun Morogh",
  ["Stormwind City"] = "Elwynn Forest",
  ["Darnassus"]      = "Teldrassil",
  ["Alah'Thalas"]    = "Thalassian Highlands",
}

-- Counted once at load, so /uui map can answer "does this build even have the
-- table" with a number instead of an assumption.
local ZONE_COUNT = 0
local zoneKey
for zoneKey in pairs(ZONES) do ZONE_COUNT = ZONE_COUNT + 1 end

-- Distance between the native zone name and the range, in UI units.
local state = {
  key = nil,
  appliedText = nil,
  appliedName = nil,
  nativeHooked = false,
  refreshCount = 0,
  lastStage = "load",
  lastName = nil,
  coordinateFrame = nil,
  coordinateLabel = nil,
  coordinateText = nil,
}

local function Enabled()
  local settings = U.ModuleConfig("worldmap", { zoneLevels = true })
  return settings.zoneLevels and true or false
end

local function PlayerLevel()
  local fn = U.G("UnitLevel")
  if type(fn) ~= "function" then return nil end
  local ok, level = pcall(fn, "player")
  if not ok then return nil end
  return tonumber(level)
end

-- Green when the player is above the region, orange while the player's level
-- is inside its range, and red while the region is still above the player.
-- With no player level to compare against, nothing is claimed and the range is
-- drawn in the neutral text colour.
local function RangeColor(min, max, playerLevel)
  if not playerLevel then return M.color.text end
  if playerLevel > max then return M.zoneLevel.ready end
  if playerLevel >= min then return M.zoneLevel.caution end
  return M.zoneLevel.danger
end

local function RangeText(range)
  local min, max = range[1], range[2]
  if min == max then return tostring(min) end
  return min .. "-" .. max
end

local function AreaLabel()
  return U.G("WorldMapFrameAreaLabel")
end

local function RangeForName(name)
  if type(name) ~= "string" then return nil end
  return ZONES[ZONE_ALIASES[name] or name]
end

local function NumberMethod(object, method)
  if not object or not object[method] then return nil end
  local ok, value = pcall(object[method], object)
  if ok then return tonumber(value) end
  return nil
end

-- The cursor as 0..1 coordinates on the native map canvas. GetCursorPosition
-- is in physical UI pixels, while WorldMapButton's edges are in its effective
-- UI scale, so the cursor must be divided by that scale before normalising.
-- Values are returned even when outside the map so diagnostics can still show
-- where the cursor landed; failure is non-nil whenever they are not drawable.
local function CursorMapPosition()
  local button = U.G("WorldMapButton")
  local cursor = U.G("GetCursorPosition")
  if not button or type(cursor) ~= "function" then
    return nil, nil, "<no WorldMapButton>"
  end

  local ok, x, y = pcall(cursor)
  if not ok or not tonumber(x) or not tonumber(y) then
    return nil, nil, "<no cursor>"
  end

  local scale = NumberMethod(button, "GetEffectiveScale") or 1
  if scale == 0 then scale = 1 end
  local left = NumberMethod(button, "GetLeft")
  local top = NumberMethod(button, "GetTop")
  local width = NumberMethod(button, "GetWidth")
  local height = NumberMethod(button, "GetHeight")
  if not left or not top or not width or not height or
     width == 0 or height == 0 then
    return nil, nil, "<no button geometry>"
  end

  local u = (x / scale - left) / width
  local v = (top - y / scale) / height
  if u < 0 or u > 1 or v < 0 or v > 1 then
    return u, v, "<cursor off map>"
  end
  return u, v, nil
end

-- A plain FontString child is not reliable on the first fullscreen-map draw
-- on this client. Use the verified world-map overlay shape instead: a
-- high-level Button with one file-backed BACKGROUND texture and its label.
-- Mouse input is disabled so the native map continues receiving hover/clicks
-- beneath the readout.
local function EnsureCoordinateReadout()
  if state.coordinateFrame then return state.coordinateLabel end

  local canvas = U.G("WorldMapButton")
  if not canvas then return nil end

  local frame = CreateFrame("Button", "UnrealUIWorldMapCursorCoordinates", canvas)
  if not frame then return nil end
  state.coordinateFrame = frame
  frame:SetWidth(124)
  frame:SetHeight(20)
  frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
  frame:SetFrameLevel(math.max((NumberMethod(canvas, "GetFrameLevel") or 0) + 20,
                               120))
  if frame.EnableMouse then frame:EnableMouse(false) end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(M.texture.plain)
  fill:SetAllPoints(frame)
  U.SetColor(fill, M.Unpack(M.color.background))

  local label = U.CreateLabel(frame, {
    inherits = "GameFontNormal",
    size = M.fontSize.normal,
    color = M.color.text,
    justify = "LEFT",
    width = 110,
    height = 18,
  })
  if not label then
    frame:Hide()
    return nil
  end
  label:SetPoint("LEFT", frame, "LEFT", 7, 0)
  label:SetText(U.L("WORLDMAP_CURSOR"))

  state.coordinateLabel = label
  state.coordinateText = "Cursor: --, --"
  return label
end

local function RefreshCursorCoordinates()
  local label = EnsureCoordinateReadout()
  if not label then return end

  local u, v, failure = CursorMapPosition()
  local text
  if not failure then
    text = string.format("Cursor: %.1f, %.1f", u * 100, v * 100)
  elseif u and v then
    text = U.L("WORLDMAP_CURSOR_OFF_MAP")
  else
    text = U.L("WORLDMAP_CURSOR")
  end

  if text ~= state.coordinateText then
    label:SetText(text)
    state.coordinateText = text
  end
end

-- First-open fallback measured by UnrealUIDiagDB.worldmap on 2026-08-26:
-- areaName=nil and the native label still contained its "BLAH!" placeholder,
-- while this exact UpdateMapHighlight call returned "Silverpine Forest".
-- Once the map has opened before, the native sources take over normally.
local function MapHighlightName()
  local highlight = U.G("UpdateMapHighlight")
  if type(highlight) ~= "function" then
    return nil, nil, nil, "<no UpdateMapHighlight>"
  end

  local u, v, failure = CursorMapPosition()
  if failure then return nil, u, v, failure end

  local gotName, name = pcall(highlight, u, v)
  if not gotName then return nil, u, v, "<UpdateMapHighlight errored>" end
  if type(name) ~= "string" or name == "" then
    return nil, u, v, "<no highlight>"
  end
  return name, u, v, nil
end

local function HoveredName(area)
  local frame = U.G("WorldMapFrame")
  local name = frame and frame.areaName
  if RangeForName(name) then return name end

  local label
  if area and area.GetText then
    local ok, value = pcall(area.GetText, area)
    if ok and type(value) == "string" then label = value end
  end
  if label == state.appliedText then label = state.appliedName end
  if RangeForName(label) then return label end

  local highlighted = MapHighlightName()
  if RangeForName(highlighted) then return highlighted end

  return (type(name) == "string" and name ~= "" and name) or
         (type(label) == "string" and label) or
         (type(highlighted) == "string" and highlighted) or ""
end

local function Clamp(value)
  value = tonumber(value) or 1
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function ColorEscape(color)
  return string.format("|cff%02x%02x%02x",
    math.floor(Clamp(color[1]) * 255 + 0.5),
    math.floor(Clamp(color[2]) * 255 + 0.5),
    math.floor(Clamp(color[3]) * 255 + 0.5))
end

local function LabelText(area)
  if not area or not area.GetText then return nil end
  local ok, value = pcall(area.GetText, area)
  if ok and type(value) == "string" then return value end
  return nil
end

local function RestoreAreaLabel(area)
  local current = LabelText(area)
  if state.appliedText and current == state.appliedText and area and area.SetText then
    pcall(area.SetText, area, state.appliedName or "")
  end
  state.appliedText = nil
  state.appliedName = nil
end

local function ApplyAreaLabel(area, name, range, playerLevel)
  if not area or not area.SetText then return false end
  local decorated = name .. " " ..
    ColorEscape(RangeColor(range[1], range[2], playerLevel)) ..
    RangeText(range) .. "|r"

  -- The stock hover updater is allowed to rewrite the label. Reapply only when
  -- its current text differs, avoiding an unconditional SetText at 20 Hz while
  -- still winning the next shared-driver tick after a native rewrite.
  local applied = true
  if LabelText(area) ~= decorated then
    applied = pcall(area.SetText, area, decorated)
  end
  if applied then
    state.appliedText = decorated
    state.appliedName = name
  end
  return applied and true or false
end

-- Diagnostic only. This legacy visibility signal is recorded so the watch can
-- show when it disagrees with the visible fullscreen presentation; it must not
-- control rendering on this client.
local function MapVisibleSignal(area)
  if area and area.IsVisible then
    local ok, visible = pcall(area.IsVisible, area)
    if ok and visible then return true end
  end

  local frame = U.G("WorldMapFrame")
  if not frame or not frame.IsVisible then return false end
  local ok, visible = pcall(frame.IsVisible, frame)
  return (ok and visible) and true or false
end

-- Runs on the shared driver (core/init.lua) rather than on an OnUpdate of its
-- own: knowledge.json / scripts.child_onupdate_unreliable, and hooking the
-- native map's own per-frame handler would put unrealUI inside the client's
-- hover path for no gain. Do not gate this on WorldMapFrame visibility:
-- knowledge.json / map.worldmap_child_render_user_confirmed records that the
-- fullscreen presentation does not track WorldMapFrame:IsShown reliably on
-- this client. The native label can be rewritten by the stock hover updater,
-- so its decorated form is checked and restored on each shared-driver tick.
local function Refresh()
  state.refreshCount = state.refreshCount + 1
  state.lastStage = "tick"
  RefreshCursorCoordinates()
  local area = AreaLabel()

  if not Enabled() then
    state.lastStage = "blocked"
    RestoreAreaLabel(area)
    state.key = nil
    return
  end
  if not area or not area.GetText or not area.SetText then
    state.lastStage = "blocked"
    state.key = nil
    return
  end

  local name = HoveredName(area)
  state.lastName = name
  if name == "" then
    state.lastStage = "no-name"
    RestoreAreaLabel(area)
    state.key = nil
    return
  end

  local level = PlayerLevel()
  local key = name .. "@" .. tostring(level)
  local range = RangeForName(name)
  if not range then
    state.lastStage = "unknown-name"
    state.key = key
    RestoreAreaLabel(area)
    return
  end

  -- The key is committed only once there is something to draw on.
  local changed = key ~= state.key
  state.key = key

  if not ApplyAreaLabel(area, name, range, level) then
    state.lastStage = "set-text-failed"
    return
  end
  state.lastStage = changed and "shown" or "reasserted"
end

-- Public so modules/settings.lua can flip the checkbox without reaching into
-- this module. Turning it off takes effect immediately; turning it on lets the
-- next refresh redraw the range under the cursor.
local function Apply()
  if not Enabled() then RestoreAreaLabel(AreaLabel()) end
  state.key = nil
end
U.ApplyWorldMapZoneLevels = Apply

-- ---------------------------------------------------------------------------
-- /uui map
--
-- The range depends on at least one of the two stock hover-name paths being
-- populated on this client. If nothing appears beside the name there are four
-- candidate causes and they need different fixes, so this measures which one
-- it is rather than inviting a run of blind edits:
--
--   1. the module never loaded         -- /uui map itself is unavailable
--   2. neither name source is populated -- areaName/label are both empty while
--                                          highlight= names the zone
--   3. the name is not a table key      -- a name source shows a string ZONES
--                                          misses
--   4. the native write did not stick   -- applied= differs from label=
--
-- It also samples the documented hit-test (UpdateMapHighlight) driven from the
-- cursor, which is the alternative source for the hovered name if the label
-- turns out not to carry it here.
-- ---------------------------------------------------------------------------

local WATCH_ID = "worldmap.debugwatch"
local WATCH_SECONDS = 30
local WATCH_SAMPLES = 24
local AUTO_WATCH_ID = "worldmap.autowatch"
local AUTO_WATCH_SECONDS = 60

local function Try(object, method, a, b)
  if not object or not object[method] then return nil end
  local ok, value = pcall(object[method], object, a, b)
  if not ok then return nil end
  return value
end

local function Quote(value)
  if type(value) ~= "string" then return tostring(value) end
  return "'" .. value .. "'"
end

-- The cursor as map UV, the same normalisation the stock map's own hit-test
-- takes. knowledge.json / api.getcursorposition_usable_for_hit_testing
-- confirms GetCursorPosition is accurate on this client.
local function CursorHighlight()
  local name, u, v, failure = MapHighlightName()
  if not name then return failure or "<no highlight>" end
  return Quote(name) .. string.format(" uv=%.2f,%.2f", u, v)
end

local function Sample()
  local area = AreaLabel()
  local frame = U.G("WorldMapFrame")
  local resolved = HoveredName(area)

  return "refreshing=" .. tostring(state.refreshCount > 0) ..
         " stage=" .. tostring(state.lastStage) ..
         " key=" .. tostring(state.key) ..
         " resolved=" .. Quote(resolved) ..
         " areaName=" .. Quote(frame and frame.areaName) ..
         " label=" .. Quote(Try(area, "GetText")) ..
         " shown=" .. tostring(Try(area, "IsShown")) ..
         " strw=" .. tostring(Try(area, "GetStringWidth")) ..
         " | highlight=" .. CursorHighlight() ..
         " | applied=" .. Quote(state.appliedText) ..
         " appliedName=" .. Quote(state.appliedName)
end

-- Temporary bounded first-open trace. It observes the production updater from
-- login without requiring /uui map, and saves every distinct state so the
-- user's reload can persist a failure that occurs before chat is available.
local function ArmAutoWatch()
  local samples, seen, elapsed = {}, {}, 0
  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("worldmapAuto", samples)
  end

  U.RegisterUpdate(AUTO_WATCH_ID, 0.1, function(step)
    elapsed = elapsed + (tonumber(step) or 0.1)
    local line = Sample()
    if not seen[line] and table.getn(samples) < WATCH_SAMPLES then
      seen[line] = true
      table.insert(samples, string.format("%.1fs %s", elapsed, line))
      if type(U.SaveDiagnostic) == "function" then
        U.SaveDiagnostic("worldmapAuto", samples)
      end
    end
    if elapsed >= AUTO_WATCH_SECONDS then
      U.UnregisterUpdate(AUTO_WATCH_ID)
    end
  end)
end

function U.WorldMapDebugDump()
  local area = AreaLabel()
  local parent = area and Try(area, "GetParent")

  U.Print("world map zone levels - enabled=" .. tostring(Enabled()) ..
          " nativeHooked=" .. tostring(state.nativeHooked) ..
          " mapVisibleSignal=" .. tostring(MapVisibleSignal(area)) ..
          " label=" .. tostring(area ~= nil) ..
          " parent=" .. tostring(parent and Try(parent, "GetName")))
  -- Zone 0 on a continent is the view the hover overlays exist on; a non-zero
  -- zone means the map is showing a single zone, where there is nothing to
  -- hover and no range is expected.
  local continent, zone
  local getContinent = U.G("GetCurrentMapContinent")
  local getZone = U.G("GetCurrentMapZone")
  if type(getContinent) == "function" then
    local ok, value = pcall(getContinent)
    if ok then continent = value end
  end
  if type(getZone) == "function" then
    local ok, value = pcall(getZone)
    if ok then zone = value end
  end

  U.Print("  readout=" .. tostring(state.appliedText ~= nil) ..
          " zoneName=" .. Quote(HoveredName(area)) ..
          " continent=" .. tostring(continent) ..
          " zone=" .. tostring(zone) ..
          " zonesKnown=" .. tostring(ZONE_COUNT))

  local samples, seen, elapsed = {}, {}, 0

  -- Save the armed state immediately and refresh it after every distinct
  -- sample. A reload before the full watch finishes will still persist the
  -- evidence collected up to that point.
  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("worldmap", samples)
  end

  U.RegisterUpdate(WATCH_ID, 0.1, function(step)
    local delta = tonumber(step) or 0.1
    elapsed = elapsed + delta

    local line = Sample()
    if not seen[line] and table.getn(samples) < WATCH_SAMPLES then
      seen[line] = true
      table.insert(samples, string.format("%.1fs %s", elapsed, line))
      if type(U.SaveDiagnostic) == "function" then
        U.SaveDiagnostic("worldmap", samples)
      end
    end

    if elapsed >= WATCH_SECONDS then
      U.UnregisterUpdate(WATCH_ID)
      if type(U.SaveDiagnostic) == "function" then
        U.SaveDiagnostic("worldmap", samples)
      end

      U.Print("map watch done: " .. table.getn(samples) .. " distinct states")
      local i
      for i = 1, math.min(table.getn(samples), 6) do
        U.Print("|cff888888" .. samples[i] .. "|r")
      end
      U.Print("  saved to UnrealUIDiagDB.worldmap - |cffffff00/reload|r then " ..
              "read " .. U.SavedVariablesHint())
    end
  end)

  U.Print("  watch armed for " .. WATCH_SECONDS .. "s - open the " ..
          "|cffffff00continent map|r now and hover several zones")
end

function WMAP:OnEnable()
  -- Run directly after the stock map's own update, matching the supplied
  -- LevelRange addon's ordering: the native handler writes the zone name first
  -- and this callback appends the range before the frame is drawn. Keep the
  -- shared poll as a capability fallback and for maps whose presentation is
  -- not reflected by the legacy frame visibility flags.
  local button = U.G("WorldMapButton")
  if button and type(U.PostHookScript) == "function" then
    state.nativeHooked = U.PostHookScript(button, "OnUpdate", Refresh) and true or false
  end
  U.RegisterUpdate("worldmap.zonelevel", 0.05, Refresh)
  Refresh()
  ArmAutoWatch()
end
