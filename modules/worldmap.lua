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
-- The native map is otherwise left completely alone -- no reskin, no window
-- layout; the only chrome removed is the WorldMapBlackout surround, and the
-- one addition is a minimize toggle beside the native close X (user request,
-- 2026-11-27) that shrinks the whole map with WorldMapFrame:SetScale, the
-- route knowledge.json / map.worldmap_positioning_guide_owns_layout measured
-- (scale propagates to every native child; size does not). rules/unreal-ui.md
-- keeps the map out of scope beyond what is explicitly requested, and this is
-- the requested part only.
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

-- With the unrealMap addon installed, it owns the map window: minimize, drag,
-- resize, HUD handling and zoom run there only (user request, 2026-11-27:
-- one copy runs when both are installed). This module and worldmapzoom.lua
-- then keep the zone level label and cursor readout, and forward the
-- U.WorldMapZoom* API to unrealMap.MapWindow. Read from OnEnable
-- (PLAYER_LOGIN), when every addon's files have loaded.
function U.ExternalMapWindow()
  local addon = U.G("unrealMap")
  local window = type(addon) == "table" and addon.MapWindow
  if type(window) == "table" and type(window.ZoomState) == "function" and
     type(window.Pin) == "function" then
    return window
  end
  return nil
end

-- Assigned with the minimize toggle below; Refresh drives it while dragging.
local UpdateMapDrag

-- Cached only once U.db exists: before that ModuleConfig hands back the
-- defaults table itself, and a minimize toggled into it would not persist.
local function Config()
  if state.config then return state.config end
  local config = U.ModuleConfig("worldmap", {
    zoneLevels = true,
    minimized = false,
    -- The minimized map's CENTER offset from WorldFrame's CENTER, in the
    -- map's own scaled units. The full-size map always sits at 0, 0.
    mapX = 0,
    mapY = 0,
  })
  -- minimizedScale is set by the resize grip and has no default above:
  -- ModuleConfig would copy the media value in once and keep it even if the
  -- token changes. Until the player resizes, M.worldMapWindow's value applies.
  if U.db and config.minimizedScale ~= nil and
     type(config.minimizedScale) ~= "number" then
    config.minimizedScale = nil
  end
  if U.db then state.config = config end
  return config
end

local function Enabled()
  return Config().zoneLevels and true or false
end

local function ReadPlayerLevel()
  local fn = U.G("UnitLevel")
  if type(fn) ~= "function" then return nil end
  local ok, level = pcall(fn, "player")
  if not ok then return nil end
  return tonumber(level)
end

-- Read at most every LEVEL_SECONDS, not on every map frame: the level only
-- changes on a ding. Not the cause of the slow open map (UnrealRuntimeProbe
-- mapfps.v2, 2026-11-27: ~85 ms frames with a zone under the cursor whether
-- this module's update ran or not, cached or live); kept as plain per-frame
-- thrift. probeOff.liveLevel bypasses it.
local LEVEL_SECONDS = 2

local function PlayerLevel()
  if state.probeOff and state.probeOff.liveLevel then return ReadPlayerLevel() end
  local now = U.G("GetTime")
  local ok, t = false, nil
  if type(now) == "function" then ok, t = pcall(now) end
  t = ok and tonumber(t) or nil
  if t and state.levelAt and t - state.levelAt < LEVEL_SECONDS and
     t >= state.levelAt then
    return state.levelValue
  end
  state.levelValue = ReadPlayerLevel()
  state.levelAt = t
  return state.levelValue
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

-- The canvas's top-left relative to WorldMapFrame's centre, in the map's own
-- unscaled units. Captured while the map is at scale 1, where every edge read
-- is consistent; until then the measured layout stands in
-- (mapblackout.scan.v1: WorldMapDetailFrame TOPLEFT at the 1024x768 guide's
-- TOP -502, -69, the guide centred on the root, so top = 384 - 69).
local CANVAS_FALLBACK = { left = -502, top = 315 }

local function CaptureCanvasOffset(map, left, top)
  if state.canvasOffset then return end
  local mapLeft = NumberMethod(map, "GetLeft")
  local mapRight = NumberMethod(map, "GetRight")
  local mapTop = NumberMethod(map, "GetTop")
  local mapBottom = NumberMethod(map, "GetBottom")
  if not mapLeft or not mapRight or not mapTop or not mapBottom then return end
  local offsetLeft = left - (mapLeft + mapRight) / 2
  local offsetTop = top - (mapTop + mapBottom) / 2
  -- A read taken while the map is closed or mid-layout is refused rather than
  -- kept for the whole session: only a refinement of the measured layout is.
  if math.abs(offsetLeft - CANVAS_FALLBACK.left) > 40 or
     math.abs(offsetTop - CANVAS_FALLBACK.top) > 40 then
    return
  end
  state.canvasOffset = { left = offsetLeft, top = offsetTop }
end

-- While minimized the map has a scale below 1, and edge reads on a scaled
-- frame mix spaces here: the extent comes back unscaled while the centre is
-- in the parent's units (knowledge.json /
-- frames.scaled_frame_edge_coordinates_mixed_space, measured on this exact
-- frame at 0.5). So the cursor is taken into parent units, offset from the
-- map's centre, divided by the map's scale and laid against the canvas offset.
-- PARTIAL: derived from that one measurement, confirmed only by the readout
-- matching the stock hover in game.
local function ScaledCursorUV(map, mapScale, x, y, width, height)
  local left = NumberMethod(map, "GetLeft")
  local right = NumberMethod(map, "GetRight")
  local top = NumberMethod(map, "GetTop")
  local bottom = NumberMethod(map, "GetBottom")
  local effective = NumberMethod(map, "GetEffectiveScale")
  if not left or not right or not top or not bottom or
     not effective or effective <= 0 then
    return nil
  end
  local parentScale = effective / mapScale
  local dx = (x / parentScale - (left + right) / 2) / mapScale
  local dy = (y / parentScale - (top + bottom) / 2) / mapScale
  local offset = state.canvasOffset or CANVAS_FALLBACK
  return (dx - offset.left) / width, (offset.top - dy) / height
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

  local width = NumberMethod(button, "GetWidth")
  local height = NumberMethod(button, "GetHeight")
  if not width or not height or width == 0 or height == 0 then
    return nil, nil, "<no button geometry>"
  end

  local u, v
  local map = U.G("WorldMapFrame")
  local mapScale = NumberMethod(map, "GetScale") or 1
  if mapScale > 0 and math.abs(mapScale - 1) > 0.001 then
    u, v = ScaledCursorUV(map, mapScale, x, y, width, height)
    if not u then return nil, nil, "<no map geometry>" end
  else
    -- Once modules/worldmapzoom.lua has moved the canvas into its scaled
    -- frame, the unscaled view holds the canvas's original rectangle.
    local frame = (U.WorldMapZoomView and U.WorldMapZoomView()) or button
    local scale = NumberMethod(frame, "GetEffectiveScale") or 1
    if scale == 0 then scale = 1 end
    local left = NumberMethod(frame, "GetLeft")
    local top = NumberMethod(frame, "GetTop")
    if not left or not top then return nil, nil, "<no button geometry>" end
    CaptureCanvasOffset(map, left, top)
    u = (x / scale - left) / width
    v = (top - y / scale) / height
  end
  if u < 0 or u > 1 or v < 0 or v > 1 then
    return u, v, "<cursor off map>"
  end
  -- The point in the visible window, as a point on the whole (zoomed) canvas.
  if U.WorldMapZoomToCanvas then u, v = U.WorldMapZoomToCanvas(u, v) end
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
  local text, mode, x, y
  if not failure then
    mode = "position"
    x = math.floor(u * 1000 + 0.5)
    y = math.floor(v * 1000 + 0.5)
    if state.coordinateMode == mode and state.coordinateX == x and
       state.coordinateY == y then return end
    text = string.format("Cursor: %.1f, %.1f", x / 10, y / 10)
  elseif u and v then
    mode = "off-map"
    if state.coordinateMode == mode then return end
    text = U.L("WORLDMAP_CURSOR_OFF_MAP")
  else
    mode = "unavailable"
    if state.coordinateMode == mode then return end
    text = U.L("WORLDMAP_CURSOR")
  end

  state.coordinateMode = mode
  state.coordinateX, state.coordinateY = x, y
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
  if state.probeOff and state.probeOff.highlight then
    return nil, nil, nil, "<probe: highlight off>"
  end
  local highlight = U.G("UpdateMapHighlight")
  if type(highlight) ~= "function" then
    return nil, nil, nil, "<no UpdateMapHighlight>"
  end

  local u, v, failure = CursorMapPosition()
  if failure then return nil, u, v, failure end

  state.highlightCalls = (state.highlightCalls or 0) + 1
  local gotName, name = pcall(highlight, u, v)
  if not gotName then return nil, u, v, "<UpdateMapHighlight errored>" end
  if type(name) ~= "string" or name == "" then
    return nil, u, v, "<no highlight>"
  end
  return name, u, v, nil
end

-- True when the map shows a single zone (GetCurrentMapZone non-zero).
local function OnZoneMap()
  local getZone = U.G("GetCurrentMapZone")
  if type(getZone) ~= "function" then return false end
  local ok, zone = pcall(getZone)
  return ok and tonumber(zone) ~= nil and tonumber(zone) > 0
end

local function HoveredName(area)
  local label
  if area and area.GetText then
    local ok, value = pcall(area.GetText, area)
    if ok and type(value) == "string" then label = value end
  end
  if label == state.appliedText then label = state.appliedName end

  -- On a zone map the native label names the hovered region of that zone.
  -- areaName and the UpdateMapHighlight hit-test are continent hover sources:
  -- there they named other zones under the cursor (user report, 2026-11-27,
  -- minimized Dustwallow Marsh map), so only the label is used.
  if OnZoneMap() then
    if type(label) == "string" and label ~= "BLAH!" then return label end
    return ""
  end

  local frame = U.G("WorldMapFrame")
  local name = frame and frame.areaName
  if RangeForName(name) then return name end
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
  state.appliedLevel = nil
end

local function ApplyAreaLabel(area, name, range, playerLevel)
  if not area or not area.SetText then return false end
  local decorated = state.appliedText
  if not decorated or state.appliedName ~= name or
     state.appliedLevel ~= playerLevel then
    decorated = name .. " " ..
      ColorEscape(RangeColor(range[1], range[2], playerLevel)) ..
      RangeText(range) .. "|r"
  end

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
    state.appliedLevel = playerLevel
  end
  return applied and true or false
end

-- ---------------------------------------------------------------------------
-- Zone name on the minimized map
--
-- The client draws WorldMapFrameAreaLabel twice: once in the map, scaled with
-- it, and once more at the full-size map's place on screen, in a plain blue
-- font. Both copies coincide at full size; minimized, the second floats above
-- the map (user report, 2026-11-27). The second copy follows the label's text
-- and alpha -- SetAlpha(0) cleared the names from both, while the range kept
-- its own |cff colour alpha in both -- so it cannot be hidden on its own.
-- While minimized the native label is faded instead, undecorated, and this
-- addon label shows the name and range in the map. It uses the proven map
-- construction (map.worldmap_child_render_user_confirmed): a level-120 Button
-- child of WorldMapButton carrying one file-backed BACKGROUND texture (here
-- fully transparent) with the FontString attached. The full-size map keeps
-- the native label, whose two copies overlap there.
-- ---------------------------------------------------------------------------

-- The native label's text before the client's first hover update.
local PLACEHOLDER_TEXT = "BLAH!"

-- The label's live alpha, when readable; nil otherwise.
local function NativeLabelAlpha(area)
  if not area or not area.GetAlpha then return nil end
  local ok, value = pcall(area.GetAlpha, area)
  if ok then return tonumber(value) end
  return nil
end

-- Compared against the live alpha, not only the last write: the double name
-- came back once (user report, 2026-11-27, map opened ~5 s after /reload)
-- while this module believed the label was already faded, which fits
-- something else restoring its alpha. Uncached when GetAlpha cannot be read.
local function SetNativeLabelAlpha(area, alpha)
  if not area or not area.SetAlpha then return end
  local live = NativeLabelAlpha(area)
  if live then
    if math.abs(live - alpha) < 0.01 then
      state.nativeAlpha = alpha
      return
    end
    if state.nativeAlpha == alpha then
      state.alphaRestored = (state.alphaRestored or 0) + 1
    end
  elseif state.nativeAlpha == alpha then
    return
  end
  state.alphaWrites = (state.alphaWrites or 0) + 1
  if pcall(area.SetAlpha, area, alpha) then state.nativeAlpha = alpha end
end


local function EnsureZoneLabel()
  if state.zoneLabel then return state.zoneLabel end
  if state.zoneLabelFailed then return nil end
  local canvas = U.G("WorldMapButton")
  local layout = M.worldMapWindow
  if not canvas or not layout then return nil end

  local ok, frame = pcall(CreateFrame, "Button", "UnrealUIWorldMapZoneLabel", canvas)
  if not ok or not frame then
    state.zoneLabelFailed = true
    return nil
  end
  frame:SetWidth(layout.zoneLabelWidth)
  frame:SetHeight(layout.zoneLabelHeight)
  frame:SetPoint("TOP", canvas, "TOP", 0, layout.zoneLabelY)
  frame:SetFrameLevel(math.max((NumberMethod(canvas, "GetFrameLevel") or 0) + 20,
                               120))
  if frame.EnableMouse then frame:EnableMouse(false) end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(M.texture.plain)
  fill:SetAllPoints(frame)
  U.SetColor(fill, 0, 0, 0, 0)

  local fontScale = layout.zoneLabelFontScale or 1
  local label = U.CreateLabel(frame, {
    inherits = "GameFontNormalHuge",
    -- Only if the native font below cannot be read.
    size = math.floor(M.fontSize.large * fontScale + 0.5),
    justify = "CENTER",
    width = layout.zoneLabelWidth,
    height = layout.zoneLabelHeight,
  })
  if not label then
    state.zoneLabelFailed = true
    frame:Hide()
    return nil
  end
  label:SetPoint("CENTER", frame, "CENTER", 0, 0)

  -- The native label's face at fontScale of its size. FontString:SetFont
  -- does nothing while a font object is assigned (documentation.json
  -- FontString:SetFont; the label kept its size at 0.8 and 0.6, user
  -- 2026-11-27), so the size goes on a named Font attached with
  -- SetFontObject: the route fonts.named_font_justification_wins records
  -- as drawing at its size. Its forced centring suits this label.
  local area = AreaLabel()
  local path, size, flags
  if area and area.GetFont then
    local gotFont, p, s, f = pcall(area.GetFont, area)
    if gotFont and type(p) == "string" and tonumber(s) then
      path, size, flags = p, tonumber(s), f
    end
  end
  path = path or (U.ResolveFont and U.ResolveFont())
  size = math.floor((size or M.fontSize.large) * fontScale + 0.5)
  state.zoneFontSize = size
  -- The outline the native label shows is its font object's shadow; a fresh
  -- Font has none (user 2026-11-27: smaller but no border), so the native
  -- shadow, or GameFontNormalHuge's 1,-1 black one, goes on the Font itself.
  local sx, sy, sr, sg, sb, sa = 1, -1, 0, 0, 0, 1
  if area and area.GetShadowOffset then
    local got, x, y = pcall(area.GetShadowOffset, area)
    if got and tonumber(x) and tonumber(y) and (x ~= 0 or y ~= 0) then
      sx, sy = x, y
    end
  end
  if area and area.GetShadowColor then
    local got, r, g, b, a = pcall(area.GetShadowColor, area)
    if got and tonumber(r) and tonumber(g) and tonumber(b) and
       (tonumber(a) or 1) > 0 then
      sr, sg, sb, sa = r, g, b, tonumber(a) or 1
    end
  end
  state.zoneFontShadow = sx .. "," .. sy
  local createFont = U.G("CreateFont")
  if path and type(createFont) == "function" and label.SetFontObject then
    state.zoneFontApplied = pcall(function()
      local font = createFont("UnrealUIWorldMapZoneFont")
      font:SetFont(path, size, flags)
      if font.SetShadowColor then pcall(font.SetShadowColor, font, sr, sg, sb, sa) end
      if font.SetShadowOffset then pcall(font.SetShadowOffset, font, sx, sy) end
      label:SetFontObject(font)
      local bound = label:GetFontObject()
      if not bound or bound:GetName() ~= "UnrealUIWorldMapZoneFont" then
        error("font object not bound")
      end
    end)
  end
  if area and area.GetTextColor and label.SetTextColor then
    local gotColor, r, g, b = pcall(area.GetTextColor, area)
    if gotColor and tonumber(r) and tonumber(g) and tonumber(b) then
      pcall(label.SetTextColor, label, r, g, b)
    end
  end
  -- Outline border (user 2026-11-27: "a shadow, not a border"). FontString
  -- owns outline flags; SetFont with the stock path U.ResolveFont verified
  -- is the route swingbar.lua uses for its outlined text. Read back: with
  -- the outline on, the shadow is cleared; otherwise the shadow stays.
  -- The SetFont route drew larger than the font object at the same number
  -- (user 2026-11-27: "too big, it was good before"), so the outlined size
  -- is matched to the font object's rendered width of a sample.
  local SAMPLE = "Ashenvale 18-30"
  local function SampleWidth()
    pcall(label.SetText, label, SAMPLE)
    local got, w = pcall(label.GetStringWidth, label)
    return got and tonumber(w) or nil
  end
  local outlined = false
  local resolved = U.ResolveFont and U.ResolveFont()
  local wanted = SampleWidth()
  -- THICKOUTLINE (user requests, 2026-11-27: thicker, 1px less, then back
  -- to thicker); falls back to OUTLINE when its readback does not keep it.
  local outline = "THICKOUTLINE"
  if type(resolved) == "string" and label.SetFont and
     pcall(label.SetFont, label, resolved, size, outline) then
    local gotThick, _, _, thickFlags = pcall(label.GetFont, label)
    if not (gotThick and type(thickFlags) == "string" and
            string.find(thickFlags, "THICK")) then
      outline = "OUTLINE"
      pcall(label.SetFont, label, resolved, size, outline)
    end
    state.zoneFontOutline = outline
    local drawn = SampleWidth()
    if wanted and drawn and wanted > 0 and drawn > 0 and
       math.abs(drawn - wanted) > wanted * 0.05 then
      local fitted = math.max(6, math.floor(size * wanted / drawn + 0.5))
      pcall(label.SetFont, label, resolved, fitted, outline)
      state.zoneFontFitted = fitted
    end
    state.zoneFontWidths = tostring(wanted) .. "->" .. tostring(drawn) ..
      "->" .. tostring(SampleWidth())
    local got, _, gotSize, gotFlags = pcall(label.GetFont, label)
    outlined = got and type(gotFlags) == "string" and
      string.find(gotFlags, "OUTLINE") ~= nil and true or false
    state.zoneFontReadback = tostring(gotSize) .. "/" .. tostring(gotFlags)
  end
  state.zoneFontOutlined = outlined
  if outlined then
    U.ClearTextShadow(label)
  else
    if label.SetShadowOffset then pcall(label.SetShadowOffset, label, sx, sy) end
    if label.SetShadowColor then pcall(label.SetShadowColor, label, sr, sg, sb, sa) end
  end

  label:SetText("")
  state.zoneLabel = label
  state.zoneLabelText = ""
  return label
end

local function SetZoneLabelText(text)
  local label = state.zoneLabel
  if not label then
    if text == "" then return end
    label = EnsureZoneLabel()
    if not label then return end
  end
  if text ~= state.zoneLabelText then
    state.zoneTextWrites = (state.zoneTextWrites or 0) + 1
    pcall(label.SetText, label, text)
    state.zoneLabelText = text
  end
end

-- Minimized tick: the native label faded and left undecorated, the hovered
-- name (with its range when known and enabled) drawn by the addon label.
-- Returns false when the addon label cannot be built, leaving the native one.
local function RefreshMinimizedLabel(area)
  if not EnsureZoneLabel() then
    SetNativeLabelAlpha(area, 1)
    return false
  end
  RestoreAreaLabel(area)
  SetNativeLabelAlpha(area, 0)

  local name = HoveredName(area)
  state.lastName = name
  if name == "" or name == PLACEHOLDER_TEXT then
    state.lastStage = "minimized-no-name"
    state.key = nil
    SetZoneLabelText("")
    return true
  end

  -- Built once per name and level, not on every map frame.
  local enabled = Enabled()
  local level = PlayerLevel()
  if name ~= state.zoneBuiltName or level ~= state.zoneBuiltLevel or
     enabled ~= state.zoneBuiltEnabled then
    local text = name
    local range = enabled and RangeForName(name)
    if range then
      text = name .. " " ..
        ColorEscape(RangeColor(range[1], range[2], level)) ..
        RangeText(range) .. "|r"
    end
    state.zoneBuiltName, state.zoneBuiltLevel = name, level
    state.zoneBuiltEnabled = enabled
    state.zoneBuiltText = text
  end
  state.lastStage = "minimized"
  state.key = nil
  SetZoneLabelText(state.zoneBuiltText)
  return true
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
  -- The drag rides this per-frame hook too: it is the one tick proven to run
  -- while the fullscreen map is open (UIParent, and its driver, are hidden).
  if (state.drag or state.resize) and UpdateMapDrag then UpdateMapDrag() end
  -- UnrealRuntimeProbe mapfps switches (U.WorldMapProbe below); nil in play.
  local off = state.probeOff
  if off and off.refresh then return end
  state.refreshCount = state.refreshCount + 1
  state.lastStage = "tick"
  if not (off and off.coordinates) then RefreshCursorCoordinates() end
  local area = AreaLabel()

  -- The addon label serves both sizes, so the name is drawn smaller than the
  -- native label (layout.zoneLabelFontScale; user request, 2026-11-27) with
  -- one construction. zoneLabelOff is the mapfps probe's switch
  -- (U.WorldMapProbe below).
  if not state.zoneLabelOff and RefreshMinimizedLabel(area) then
    return
  end
  -- Fallback when the addon label cannot be built: the native label is in
  -- charge (at full size the two copies the client draws of it overlap).
  SetNativeLabelAlpha(area, 1)
  SetZoneLabelText("")

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

-- What takes the mouse around the map: the frame under the cursor (by name;
-- api.getmousefocus_not_identity_comparable), the HUD, and the blackout.
local function InputSample()
  local focus = "none"
  local getFocus = U.G("GetMouseFocus")
  if type(getFocus) == "function" then
    local ok, frame = pcall(getFocus)
    if ok and frame then focus = tostring(Try(frame, "GetName") or "<unnamed>") end
  end
  local blackout = U.G("WorldMapBlackout")
  return "focus=" .. focus ..
         " uiparent=" .. tostring(Try(U.G("UIParent"), "IsShown")) ..
         " hudShows=" .. tostring(state.hudShows or 0) ..
         " blackoutMouse=" .. tostring(Try(blackout, "IsMouseEnabled")) ..
         " firstBlackoutMouse=" .. tostring(state.blackoutMouse)
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
         " appliedName=" .. Quote(state.appliedName) ..
         " | " .. InputSample()
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
          " parent=" .. tostring(parent and Try(parent, "GetName")) ..
          " window=" .. (state.external and "unrealMap" or "unrealUI") ..
          " minimized=" .. tostring(Config().minimized) ..
          " scale=" .. tostring(Try(U.G("WorldMapFrame"), "GetScale")))
  -- Totals since login, for an open-map frame-rate check: note them, open
  -- the map for a few seconds, close it, run /uui map again and compare.
  U.Print("  ticks=" .. tostring(state.refreshCount) ..
          " highlightCalls=" .. tostring(state.highlightCalls or 0) ..
          " zoneTextWrites=" .. tostring(state.zoneTextWrites or 0) ..
          " alphaWrites=" .. tostring(state.alphaWrites or 0) ..
          " alphaRestored=" .. tostring(state.alphaRestored or 0) ..
          " nativeAlpha=" .. tostring(NativeLabelAlpha(AreaLabel())) ..
          " zoneLabelFailed=" .. tostring(state.zoneLabelFailed and true or false) ..
          " " .. InputSample() ..
          " zoneFont=" .. tostring(state.zoneFontSize) ..
          "/" .. tostring(state.zoneFontApplied) ..
          " zoneShadow=" .. tostring(state.zoneFontShadow) ..
          " outline=" .. tostring(state.zoneFontOutlined) ..
          "/" .. tostring(state.zoneFontOutline) ..
          " readback=" .. tostring(state.zoneFontReadback) ..
          " fitted=" .. tostring(state.zoneFontFitted) ..
          " widths=" .. tostring(state.zoneFontWidths) ..
          " zoneLabel=" .. (state.zoneLabelOff and "off" or "on"))
  local grip = state.resizeGrip
  local icon = grip and grip.uuiIcon
  U.Print("  grip=" .. tostring(grip ~= nil) ..
          " shown=" .. tostring(Try(grip, "IsShown")) ..
          " visible=" .. tostring(Try(grip, "IsVisible")) ..
          " level=" .. tostring(Try(grip, "GetFrameLevel")) ..
          " size=" .. tostring(Try(grip, "GetWidth")) ..
          " iconAlpha=" .. tostring(Try(icon, "GetAlpha")) ..
          " iconTexture=" .. tostring(Try(icon, "GetTexture")))
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

-- The dark band either side of the fullscreen map is WorldMapBlackout, a
-- full-screen FULLSCREEN-strata Frame parented to WorldFrame -- not the
-- 1024x768 BlackoutWorld texture behind the map art (knowledge.json /
-- map.worldmap_blackout_frame_draws_surround). Faded, not hidden, so the
-- client's own show/hide of it is untouched (user request, 2026-09-30).
-- The client hides UIParent while the map is open, so the sides show the 3D
-- world, not the HUD. Re-applied on every map show.
--
-- BlackoutWorld, the 1024x768 black texture behind the map art, is faded too
-- (user request, 2026-11-27): the full-size map art hides it, but around a
-- minimized map it showed as a black box. It is a named root region, so it is
-- reached by its global, never by a region walk.
local function HideBlackout()
  local blackout = U.G("WorldMapBlackout")
  if blackout and blackout.SetAlpha then pcall(blackout.SetAlpha, blackout, 0) end
  local backing = U.G("BlackoutWorld")
  if backing and backing.SetAlpha then pcall(backing.SetAlpha, backing, 0) end
end

-- Minimize toggle (user request, 2026-11-27). The whole map shrinks with
-- WorldMapFrame:SetScale, which every native child follows; no native anchor,
-- size or script is touched (knowledge.json /
-- map.worldmap_positioning_guide_owns_layout). The map stays centred on
-- WorldFrame at full size, and at the player's dragged offset while
-- minimized. The client still hides UIParent while the map is open, so the
-- HUD does not return around a minimized map (keeping UIParent shown against
-- the client's fullscreen-map handling is untested).

-- Keeps the whole minimized map on screen. Offsets are in the map's own
-- scaled units, so the free room on WorldFrame is divided by the map scale.
-- GetWidth/GetHeight are the reads that stay consistent on a scaled frame
-- (frames.scaled_frame_edge_coordinates_mixed_space).
local function ClampMapOffset(map, x, y, scale)
  local world = U.G("WorldFrame")
  local worldWidth = NumberMethod(world, "GetWidth")
  local worldHeight = NumberMethod(world, "GetHeight")
  local width = NumberMethod(map, "GetWidth")
  local height = NumberMethod(map, "GetHeight")
  x, y = tonumber(x) or 0, tonumber(y) or 0
  if not worldWidth or not worldHeight or not width or not height or
     scale <= 0 then
    return x, y
  end
  local maxX = math.max(0, (worldWidth - width * scale) / 2 / scale)
  local maxY = math.max(0, (worldHeight - height * scale) / 2 / scale)
  return math.max(-maxX, math.min(maxX, x)), math.max(-maxY, math.min(maxY, y))
end

-- The native anchor is CENTER on WorldFrame's CENTER at 0, 0
-- (mapblackout.scan.v1), so the full-size map is put back exactly there.
local function PlaceMap(map, x, y)
  local world = U.G("WorldFrame")
  if not map or not world then return end
  if state.placedX == x and state.placedY == y then return end
  pcall(map.ClearAllPoints, map)
  if pcall(map.SetPoint, map, "CENTER", world, "CENTER", x, y) then
    state.placedX, state.placedY = x, y
  end
end

-- The player's resized scale, kept inside the grip's range.
local function MinimizedScale()
  local layout = M.worldMapWindow
  local scale = tonumber(Config().minimizedScale) or layout.minimizedScale
  return math.max(layout.minScale, math.min(layout.maxScale, scale))
end

-- Minimized map as an ordinary window (user request, 2026-11-27: the camera
-- could not be moved with the map open, and the HUD should stay).
-- WorldMapBlackout is the only full-screen frame the map adds
-- (mapblackout.scan.v1; WorldMapFrame itself reports IsMouseEnabled false),
-- so it stops taking the mouse while minimized; its first state is put back
-- at full size. UIParent, which the client hides for the map, is shown again
-- from the map's own tick (RefreshOnMap) while minimized and hidden again
-- only if this module showed it. Untested beyond that: whether the client
-- re-hides UIParent or keeps the keyboard.
local function SetBlackoutMouse(minimized)
  local blackout = U.G("WorldMapBlackout")
  if not blackout or not blackout.EnableMouse then return end
  if state.blackoutMouse == nil and blackout.IsMouseEnabled then
    local ok, enabled = pcall(blackout.IsMouseEnabled, blackout)
    if ok then state.blackoutMouse = enabled and true or false end
  end
  local want = (not minimized) and state.blackoutMouse or false
  pcall(blackout.EnableMouse, blackout, want and true or false)
end

local function SetHudForMap(minimized)
  local parent = U.G("UIParent")
  if not parent or not parent.IsShown then return end
  local ok, shown = pcall(parent.IsShown, parent)
  if not ok then return end
  if minimized then
    if not shown and parent.Show and pcall(parent.Show, parent) then
      state.hudForced = true
      state.hudShows = (state.hudShows or 0) + 1
    end
  elseif state.hudForced then
    state.hudForced = nil
    if shown and parent.Hide then pcall(parent.Hide, parent) end
  end
end

-- Full-size map: the client hides UIParent, and the mouse wheel reaches only a
-- UIParent-child catcher (knowledge.json /
-- map.worldmap_zoom_scaled_canvas_unclipped, mapzoom.v2), so the wheel zoom
-- of modules/worldmapzoom.lua had no receiver at full size (user report
-- 2026-11-27: + / - zoomed, the wheel did not). UIParent is shown again under
-- the full-size map at alpha 0 ("veiled"), so the HUD stays unseen, and its
-- alpha is put back once the map closes or is minimized. Showing UIParent with
-- the map open is what the minimized map already does; the alpha-0 UIParent
-- under the full-size map is UNTESTED here.
local function SetHudVeil(on)
  local parent = U.G("UIParent")
  if not parent or type(parent.SetAlpha) ~= "function" or
     type(parent.IsShown) ~= "function" then
    return
  end
  if on then
    if not state.hudVeiled then
      state.hudAlpha = NumberMethod(parent, "GetAlpha") or 1
      -- Faded before it is shown, so the HUD never flashes over the map.
      if not pcall(parent.SetAlpha, parent, 0) then return end
      state.hudVeiled = true
    end
    local ok, shown = pcall(parent.IsShown, parent)
    if ok and not shown and parent.Show then pcall(parent.Show, parent) end
  elseif state.hudVeiled then
    state.hudVeiled = nil
    pcall(parent.SetAlpha, parent, state.hudAlpha or 1)
  end
end

local function ApplyMapScale()
  if state.external then return end
  local config = Config()
  local minimized = config.minimized and true or false
  local map = U.G("WorldMapFrame")
  local layout = M.worldMapWindow
  if map and map.SetScale and layout then
    local scale = minimized and MinimizedScale() or 1
    if NumberMethod(map, "GetScale") ~= scale then
      pcall(map.SetScale, map, scale)
    end
    if minimized then
      PlaceMap(map, ClampMapOffset(map, config.mapX, config.mapY, scale))
    else
      PlaceMap(map, 0, 0)
    end
  end
  -- The glyph names the action: minimize while full size, maximize while small.
  local button = state.minimizeButton
  if button and button.uuiSetGlyph then
    button.uuiSetGlyph(minimized and "maximize" or "minimize")
  end
  -- The full-size map keeps its header exactly as the client has it.
  local handle = state.dragHandle
  if handle and handle.EnableMouse then
    pcall(handle.EnableMouse, handle, minimized)
  end
  local grip = state.resizeGrip
  if grip then
    pcall(grip.EnableMouse, grip, minimized)
    if grip.uuiPaint then grip.uuiPaint() end
  end
  SetBlackoutMouse(minimized)
  -- A shown keyboard-enabled frame takes the whole keyboard here, Enter-to-chat
  -- and movement included (knowledge.json /
  -- scripts.keyboard_frame_captures_all_input; user 2026-11-27: Enter did not
  -- open chat over the minimized map). The stock map is created
  -- keyboard-enabled, and IsKeyboardEnabled does not exist on this client to
  -- read it, so full size restores true. Written only on a change.
  local keyboard = not minimized
  if map and map.EnableKeyboard and state.mapKeyboard ~= keyboard and
     (minimized or state.mapKeyboard ~= nil) then
    if pcall(map.EnableKeyboard, map, keyboard) then
      state.mapKeyboard = keyboard
    end
  end
  -- Leaving minimized puts the client's hidden HUD back; entering it is
  -- handled by the map tick, which knows the map is open.
  -- Minimized, a veiled HUD is simply shown at full alpha again.
  if minimized then
    SetHudVeil(false)
  else
    SetHudForMap(false)
  end
end

local function Now()
  local getTime = U.G("GetTime")
  if type(getTime) ~= "function" then return nil end
  local ok, t = pcall(getTime)
  return ok and tonumber(t) or nil
end

-- WorldMapButton's OnUpdate runs only while the map is open, so this is the
-- one place that can bring the HUD back around a minimized map.
local function RefreshOnMap()
  state.mapTickAt = Now()
  if not state.external then
    if Config().minimized then SetHudForMap(true) else SetHudVeil(true) end
  end
  Refresh()
end

-- The veil goes once the map stops ticking (closed) or is minimized. The
-- fullscreen presentation does not track WorldMapFrame:IsShown reliably, so
-- the map's own tick going stale is the close signal.
local function CheckHudVeil()
  if not state.hudVeiled then return end
  local now = Now()
  local open = now and state.mapTickAt and now - state.mapTickAt <= 0.2
  if Config().minimized or not open then SetHudVeil(false) end
end

-- Showing the HUD only from the map tick left it hidden for the opening frame
-- (user 2026-11-27: the HUD blinked on open). The client's hide is undone in
-- the same frame instead: on the map's OnShow, and in UIParent's OnHide when
-- the map opened this frame (GetTime is a per-frame snapshot) or ticked in
-- the last 0.2 s. A HUD hidden with the map closed (Alt+Z) is left alone.
local function OnHudHidden()
  local now = Now()
  if not now then return end
  local opening = state.mapShownAt == now
  local open = state.mapTickAt and now - state.mapTickAt <= 0.2
  if not opening and not open then return end
  if Config().minimized then SetHudForMap(true) else SetHudVeil(true) end
end

-- ---------------------------------------------------------------------------
-- Dragging the minimized map
--
-- The handle is a Button parented to the map it moves (knowledge.json /
-- frames.movable_drag_requires_button_handle), but the map is not moved with
-- StartMoving: it is a scaled native frame parented to WorldFrame, where edge
-- reads mix spaces, and core/windowdrag.lua's save and screen guard work from
-- those edges in UIParent space. Instead the CENTER offset follows the cursor
-- delta on the map's own per-frame tick, divided by the map's effective scale
-- (GetCursorPosition is in physical pixels; knowledge.json /
-- api.getcursorposition_usable_for_hit_testing), and is saved on release.
-- No StartMoving is involved, so the per-tick SetPoint does not meet
-- widgets.thumb_reposition_during_drag_breaks_drag.
-- ---------------------------------------------------------------------------

local function CursorPixels()
  local cursor = U.G("GetCursorPosition")
  if type(cursor) ~= "function" then return nil end
  local ok, x, y = pcall(cursor)
  if not ok or not tonumber(x) or not tonumber(y) then return nil end
  return tonumber(x), tonumber(y)
end

-- Best effort, as in core/mover.lua: the client documents no mouse-button
-- query, so a missing one reads "still held" and the release scripts end it.
local function LeftButtonStillDown()
  local fn = U.G("IsMouseButtonDown")
  if type(fn) ~= "function" then return true end
  local ok, down = pcall(fn, "LeftButton")
  if not ok then return true end
  return down and down ~= 0 and true or false
end

local function MoveMapToCursor()
  local drag = state.drag
  local map = U.G("WorldMapFrame")
  if not drag or not map then return end
  local x, y = CursorPixels()
  if not x then return end
  local offsetX = drag.startX + (x - drag.cursorX) / drag.effective
  local offsetY = drag.startY + (y - drag.cursorY) / drag.effective
  offsetX, offsetY = ClampMapOffset(map, offsetX, offsetY, drag.scale)
  drag.x, drag.y = offsetX, offsetY
  PlaceMap(map, offsetX, offsetY)
end

local function StopMapDrag()
  local drag = state.drag
  if not drag then return end
  MoveMapToCursor()
  state.drag = nil
  local config = Config()
  config.mapX, config.mapY = drag.x, drag.y
end

local function StartMapDrag()
  if state.drag or state.resize then return end
  local config = Config()
  local map = U.G("WorldMapFrame")
  if not config.minimized or not map then return end
  local x, y = CursorPixels()
  local scale = NumberMethod(map, "GetScale")
  local effective = NumberMethod(map, "GetEffectiveScale")
  if not x or not scale or scale <= 0 or not effective or effective <= 0 then
    return
  end
  local startX, startY = ClampMapOffset(map, config.mapX, config.mapY, scale)
  state.drag = {
    cursorX = x, cursorY = y,
    startX = startX, startY = startY,
    x = startX, y = startY,
    scale = scale, effective = effective,
  }
end

-- ---------------------------------------------------------------------------
-- Resizing the minimized map
--
-- The map's size is fixed by its positioning guide, so the bottom-right grip
-- sets its scale instead. The top-left corner stays where it was: everything
-- is worked in WorldFrame units from WorldFrame's centre, where the map's
-- CENTER sits at offset * scale, and the new offset is that centre divided by
-- the new scale. Same tick, same release handling as the drag above.
-- ---------------------------------------------------------------------------

local function ResizeMapToCursor()
  local resize = state.resize
  local map = U.G("WorldMapFrame")
  local layout = M.worldMapWindow
  if not resize or not map or not layout then return end
  local x, y = CursorPixels()
  if not x then return end

  local dx = (x - resize.cursorX) / resize.parentScale
  local dy = (y - resize.cursorY) / resize.parentScale
  local w, h = resize.width, resize.height
  local scale = math.max((w * resize.scale + dx) / w,
                         (h * resize.scale - dy) / h)
  local maxScale = math.min(layout.maxScale, resize.fitScale)
  scale = math.max(layout.minScale, math.min(maxScale, scale))
  -- Steps of 1/200 keep a still cursor from re-laying the map out each frame.
  scale = math.floor(scale * 200 + 0.5) / 200

  local offsetX = (resize.topLeftX + w / 2 * scale) / scale
  local offsetY = (resize.topLeftY - h / 2 * scale) / scale
  offsetX, offsetY = ClampMapOffset(map, offsetX, offsetY, scale)
  if scale ~= resize.current then
    pcall(map.SetScale, map, scale)
    resize.current = scale
  end
  resize.x, resize.y = offsetX, offsetY
  PlaceMap(map, offsetX, offsetY)
end

local function StopMapResize()
  local resize = state.resize
  if not resize then return end
  ResizeMapToCursor()
  state.resize = nil
  local config = Config()
  config.minimizedScale = resize.current
  config.mapX, config.mapY = resize.x, resize.y
  if state.resizeGrip and state.resizeGrip.uuiPaint then
    state.resizeGrip.uuiPaint()
  end
end

local function StartMapResize()
  if state.resize or state.drag then return end
  local config = Config()
  local map = U.G("WorldMapFrame")
  local world = U.G("WorldFrame")
  if not config.minimized or not map or not world then return end
  local x, y = CursorPixels()
  local scale = NumberMethod(map, "GetScale")
  local effective = NumberMethod(map, "GetEffectiveScale")
  local width = NumberMethod(map, "GetWidth")
  local height = NumberMethod(map, "GetHeight")
  local worldWidth = NumberMethod(world, "GetWidth")
  local worldHeight = NumberMethod(world, "GetHeight")
  if not x or not scale or scale <= 0 or not effective or effective <= 0 or
     not width or width <= 0 or not height or height <= 0 or
     not worldWidth or not worldHeight then
    return
  end
  local offsetX, offsetY = ClampMapOffset(map, config.mapX, config.mapY, scale)
  state.resize = {
    cursorX = x, cursorY = y,
    scale = scale, current = scale,
    parentScale = effective / scale,
    width = width, height = height,
    fitScale = math.min(worldWidth / width, worldHeight / height),
    topLeftX = offsetX * scale - width / 2 * scale,
    topLeftY = offsetY * scale + height / 2 * scale,
    x = offsetX, y = offsetY,
  }
end

UpdateMapDrag = function()
  if not state.drag and not state.resize then return end
  if not LeftButtonStillDown() then
    StopMapDrag()
    StopMapResize()
    return
  end
  if state.drag then MoveMapToCursor() end
  if state.resize then ResizeMapToCursor() end
end

-- The button name may arrive first, second (after the frame) or only in arg1,
-- as core/windowdrag.lua handles it.
local function IsLeftButton(a, b)
  local button
  if type(a) == "string" then
    button = a
  elseif type(b) == "string" then
    button = b
  else
    button = U.G("arg1")
  end
  return button == nil or button == "LeftButton"
end

local function BuildDragHandle()
  if state.dragHandle then return end
  local map = U.G("WorldMapFrame")
  local layout = M.worldMapWindow
  if not map or not layout then return end
  local ok, handle = pcall(CreateFrame, "Button", "UnrealUIWorldMapDragHandle", map)
  if not ok or not handle then return end
  handle:SetPoint("TOPLEFT", map, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", map, "TOPRIGHT", -layout.dragRightInset, 0)
  handle:SetHeight(layout.dragHeight)
  handle:SetFrameLevel((NumberMethod(map, "GetFrameLevel") or 0) + 2)
  pcall(handle.RegisterForDrag, handle, "LeftButton")
  handle:SetScript("OnMouseDown", function(a, b)
    if IsLeftButton(a, b) then StartMapDrag() end
  end)
  handle:SetScript("OnMouseUp", function(a, b)
    if IsLeftButton(a, b) then StopMapDrag() end
  end)
  handle:SetScript("OnDragStop", StopMapDrag)
  handle:SetScript("OnHide", StopMapDrag)
  pcall(handle.EnableMouse, handle, false)
  state.dragHandle = handle
end

-- The bags' corner mark (M.texture.chatResizeGrip) built exactly like the
-- minimize toggle, the one addon control the user has confirmed visible on
-- this map: a level-120 Button child of WorldMapButton whose file-backed
-- ARTWORK texture covers it with SetAllPoints, never hidden. The first build
-- (16-unit OVERLAY mark centred on a 24-unit Button, the Button hidden at
-- build and shown once minimized) stayed invisible in game (user report,
-- 2026-11-27); map children are known to stay blank when their construction
-- drifts from the proven one (knowledge.json /
-- map.worldmap_child_render_user_confirmed). So the full-size map clears it
-- with alpha and mouse instead of Hide. Dim at rest, full hovered or held.
local function BuildResizeGrip()
  if state.resizeGrip then return end
  local canvas = U.G("WorldMapButton")
  local layout = M.worldMapWindow
  if not canvas or not layout then return end
  local ok, grip = pcall(CreateFrame, "Button", "UnrealUIWorldMapResizeGrip", canvas)
  if not ok or not grip then return end
  grip:SetWidth(layout.gripSize)
  grip:SetHeight(layout.gripSize)
  grip:SetPoint("CENTER", canvas, "BOTTOMRIGHT", layout.gripX, layout.gripY)
  grip:SetFrameLevel(math.max((NumberMethod(canvas, "GetFrameLevel") or 0) + 20,
                              120))
  pcall(grip.EnableMouse, grip, true)
  pcall(grip.RegisterForDrag, grip, "LeftButton")

  local icon = grip:CreateTexture(nil, "ARTWORK")
  pcall(icon.SetTexture, icon, M.texture.chatResizeGrip)
  pcall(icon.SetAllPoints, icon, grip)
  grip.uuiIcon = icon

  local over = false
  local function Paint()
    local alpha = 0
    if Config().minimized then
      alpha = (over or state.resize) and 1 or 0.7
    end
    pcall(icon.SetAlpha, icon, alpha)
  end
  grip.uuiPaint = Paint
  grip:SetScript("OnEnter", function() over = true; Paint() end)
  grip:SetScript("OnLeave", function() over = false; Paint() end)
  grip:SetScript("OnMouseDown", function(a, b)
    if IsLeftButton(a, b) then StartMapResize(); Paint() end
  end)
  grip:SetScript("OnMouseUp", function(a, b)
    if IsLeftButton(a, b) then StopMapResize() end
  end)
  grip:SetScript("OnDragStop", StopMapResize)
  grip:SetScript("OnHide", StopMapResize)
  Paint()
  state.resizeGrip = grip
end

local function ToggleMinimized()
  local config = Config()
  config.minimized = not config.minimized
  ApplyMapScale()
end

-- The proven world-map construction (knowledge.json /
-- map.worldmap_child_render_user_confirmed): a level-120 Button child of
-- WorldMapButton with file-backed textures. It hangs above the canvas in the
-- header band, beside the native close X.
local function BuildMinimizeButton()
  if state.minimizeButton then return end
  local canvas = U.G("WorldMapButton")
  local layout = M.worldMapWindow
  if not canvas or not layout or type(U.CreateRedGlyphButton) ~= "function" then
    return
  end
  local button = U.CreateRedGlyphButton(canvas, {
    name = "UnrealUIWorldMapMinimizeButton",
    size = layout.buttonSize,
    glyph = "minimize",
    onClick = ToggleMinimized,
  })
  if not button then return end
  button:SetPoint("CENTER", canvas, "TOPRIGHT", layout.buttonX, layout.buttonY)
  button:SetFrameLevel(math.max((NumberMethod(canvas, "GetFrameLevel") or 0) + 20,
                                120))
  state.minimizeButton = button
end

-- The client may re-anchor its map when it opens, so the placement cache is
-- dropped and the scale and offset are written again on every show.
local function OnMapShow()
  HideBlackout()
  if state.external then return end
  state.mapShownAt = Now()
  state.placedX, state.placedY = nil, nil
  -- The client may re-enable the map's keyboard on open; minimized, write it
  -- again (full size keeps the cache, so a false is still put back to true).
  if Config().minimized then state.mapKeyboard = nil end
  ApplyMapScale()
  if Config().minimized then SetHudForMap(true) else SetHudVeil(true) end
end

-- ---------------------------------------------------------------------------
-- Frame-rate bisect hooks for UnrealRuntimeProbe's mapfps group (user report
-- of 4-6 fps with the map open, 2026-11-27). Nothing calls these in play.
-- Result (mapfps.v1-v4 + user check): the slow map came from opening it soon
-- after a reload, not from this module (knowledge.json /
-- map.open_soon_after_reload_slow).
--   Switch(name, off): name is refresh (the whole per-frame update),
--     coordinates (cursor readout), highlight (UpdateMapHighlight fallback),
--     liveLevel (UnitLevel read every frame, bypassing its cache) or
--     zoneLabel (the minimized map's addon label; the native label returns).
--   NativeAlpha(alpha): the native zone label's alpha, set directly.
--   SetMinimized(on): the minimize toggle without saving a new position.
--   Counters(): per-frame work counted since login.
--   Reset(): every switch back on, the label and scale as configured.
-- ---------------------------------------------------------------------------
U.WorldMapProbe = {}

function U.WorldMapProbe.Switch(name, off)
  if name == "zoneLabel" then
    state.zoneLabelOff = off and true or nil
    if off then
      SetZoneLabelText("")
      SetNativeLabelAlpha(AreaLabel(), 1)
    end
    return
  end
  state.probeOff = state.probeOff or {}
  state.probeOff[name] = off and true or nil
end

function U.WorldMapProbe.NativeAlpha(alpha)
  state.nativeAlpha = nil
  SetNativeLabelAlpha(AreaLabel(), alpha)
end

function U.WorldMapProbe.SetMinimized(on)
  Config().minimized = on and true or false
  ApplyMapScale()
end

function U.WorldMapProbe.Counters()
  return {
    ticks = state.refreshCount,
    highlightCalls = state.highlightCalls or 0,
    zoneTextWrites = state.zoneTextWrites or 0,
    alphaWrites = state.alphaWrites or 0,
    stage = state.lastStage,
    name = state.lastName,
    zoneText = state.zoneLabelText,
    minimized = Config().minimized and true or false,
    hasNativeUpdate = state.nativeButtonUpdate ~= nil,
  }
end

-- WorldMapButton's OnUpdate: "native" is the client's own handler without
-- this module's wrapper, "none" removes hover handling entirely, anything
-- else puts the wrapped handler back.
function U.WorldMapProbe.ButtonUpdate(mode)
  local button = U.G("WorldMapButton")
  if not button or not button.SetScript then return false end
  local handler = state.hookedButtonUpdate
  if mode == "native" then
    handler = state.nativeButtonUpdate
  elseif mode == "none" then
    handler = nil
  end
  return pcall(button.SetScript, button, "OnUpdate", handler)
end

function U.WorldMapProbe.Reset()
  if state.hookedButtonUpdate then U.WorldMapProbe.ButtonUpdate("hooked") end
  state.probeOff = nil
  state.zoneLabelOff = nil
  state.nativeAlpha = nil
  ApplyMapScale()
end

function WMAP:OnEnable()
  state.external = U.ExternalMapWindow()
  if state.external then
    -- unrealMap draws no zone name of its own while this label is in charge.
    pcall(state.external.UseExternalZoneLabel)
  else
    BuildMinimizeButton()
    BuildDragHandle()
    BuildResizeGrip()
  end
  OnMapShow()
  local mapFrame = U.G("WorldMapFrame")
  if mapFrame and type(U.PostHookScript) == "function" then
    U.PostHookScript(mapFrame, "OnShow", OnMapShow)
  end
  local hud = U.G("UIParent")
  if not state.external and hud and type(U.PostHookScript) == "function" then
    U.PostHookScript(hud, "OnHide", OnHudHidden)
  end

  -- Run directly after the stock map's own update, matching the supplied
  -- LevelRange addon's ordering: the native handler writes the zone name first
  -- and this callback appends the range before the frame is drawn. Keep the
  -- shared poll as a capability fallback and for maps whose presentation is
  -- not reflected by the legacy frame visibility flags.
  local button = U.G("WorldMapButton")
  if button and type(U.PostHookScript) == "function" then
    -- Both handlers kept for U.WorldMapProbe.ButtonUpdate (mapfps.v4).
    local gotNative, native = pcall(button.GetScript, button, "OnUpdate")
    if gotNative then state.nativeButtonUpdate = native end
    state.nativeHooked = U.PostHookScript(button, "OnUpdate", RefreshOnMap) and true or false
    local gotHooked, hooked = pcall(button.GetScript, button, "OnUpdate")
    if gotHooked then state.hookedButtonUpdate = hooked end
  end
  U.RegisterUpdate("worldmap.zonelevel", 0.05, Refresh)
  if not state.external then U.RegisterUpdate("worldmap.hudveil", 0.1, CheckHudVeil) end
  Refresh()
end
