-- unrealUI :: modules/worldmapzoom.lua
--
-- Zoom and drag-pan on the world map, minimized and full size (user request,
-- 2026-11-27, "as in PandaUI / PandaMap"; pandaUI modules/worldmapzoom.lua is
-- the reference, WORKING_SOURCE, not evidence).
--
-- Evidence (knowledge.json / map.worldmap_zoom_scaled_canvas_unclipped,
-- UnrealRuntimeProbe mapzoom.v1-v2, 2026-11-27):
--   * WorldMapDetailFrame and WorldMapButton can be reparented into an addon
--     frame and scaled: every hover/pin/arrow child follows, nothing crashed,
--     and the move restores exactly.
--   * Nothing clips them (a ScrollFrame did not), so the zoom clips by hand:
--     every WorldMapDetailTileN and WorldMapOverlayN is re-anchored, resized
--     and SetTexCoord-cropped (4-value form) to the visible window. Tile
--     cropping is user-confirmed; overlay cropping is not yet. Frames on the
--     canvas (quest pins, the player arrow) are not clipped here.
--   * The wheel reaches only a never-mouse-enabled catcher ScrollFrame
--     parented to UIParent (82 events; a WorldFrame child got 0). The client
--     hides UIParent for the map; modules/worldmap.lua shows it again, around
--     the minimized map and at alpha 0 under the full-size one (a parentless
--     catcher got no wheel at full size, user report 2026-11-27).
--   * Drag-pan works; the drag ends on WorldMapButton's OnMouseUp, whose
--     native handler (the zoom in/out click) is skipped after a drag.
--     Mouse-enabled pins of other addons forward their press and release
--     to those scripts (U.WorldMapZoomDragging).
--
--   WorldMapFrame
--     UnrealUIWorldMapZoomView     (the canvas rectangle, never scaled)
--       UnrealUIWorldMapZoomContent  (scaled by the zoom, anchored -pan)
--         WorldMapDetailFrame, WorldMapButton
--
-- Installed on the first zoom only; at zoom 1 the content sits exactly where
-- the canvases were. The map's own chrome that lives on WorldMapButton (zone
-- label, cursor readout, minimize, resize grip, these buttons) is
-- counter-scaled and anchored to the view so it does not zoom or move.
--
-- With unrealMap installed, its MapZoom.lua (a port of this file) owns the
-- zoom and nothing here is built; the U.WorldMapZoom* functions forward to
-- unrealMap.MapWindow (U.ExternalMapWindow, modules/worldmap.lua).

local U = UnrealUI
local M = U.media

local ZOOM = U.RegisterModule("worldmapzoom")

local MIN_ZOOM, MAX_ZOOM = 1, 4
-- One stop per wheel notch, each about x1.12 so every notch feels the same
-- (user request, 2026-11-27: even steps instead of +0.5).
local ZOOM_STOPS = { 1, 1.12, 1.26, 1.41, 1.59, 1.78, 2, 2.24, 2.52, 2.83, 3.17, 3.56, 4 }
local DRAG_PIXELS = 4
local SWEEP_SECONDS = 0.25 -- re-crop interval while zoomed
local OPEN_TICK_SECONDS = 0.2
-- Inertia, as in PandaMap's MapZoom.lua (user request 2026-11-27; reference,
-- not evidence). The zoom eases toward its target in log space (about 95% of
-- a step in 0.25 s) and snaps exactly onto it; a fast drag release glides
-- with exponential friction. Speeds are in view units per second.
local ZOOM_RATE = 12
local ZOOM_SNAP = 0.002
local MAX_FRAME_TIME = 0.1
local GLIDE_FRICTION = 5
local GLIDE_START_SPEED = 60
local GLIDE_STOP_SPEED = 15
local GLIDE_MAX_SPEED = 4000
local GLIDE_RELEASE_WINDOW = 0.08
-- WorldMapDetailFrame's place on the 1024x768 guide (mapblackout.scan.v1).
local ANCHOR_X, ANCHOR_Y = -502, -69
-- A zone map's art also draws its neighbours; the zoomed window is kept on
-- the zone itself (user request 2026-11-27). Box = the union of the zone's
-- exploration overlays, { left, top, right, bottom } on the 1002x668 canvas,
-- keyed by lowercased GetMapInfo name; continents and battlegrounds have
-- none and pan over the whole canvas. Derived from pfUI's pfMapOverlayData
-- (env/tables.lua, MIT, (c) 2016-2021 Eric Mauser (Shagu)).
local CANVAS_W, CANVAS_H = 1002, 668
local ZONE_BOUNDS = {
  alterac = { 26, 0, 976, 668 }, arathi = { 87, 54, 860, 639 },
  ashenvale = { 19, 28, 1002, 631 }, aszhara = { 35, 0, 938, 668 },
  badlands = { 0, 7, 981, 659 }, barrens = { 306, 0, 681, 668 },
  blastedlands = { 212, 9, 744, 628 }, burningsteppes = { 36, 46, 1002, 589 },
  darkshore = { 229, 0, 705, 668 }, deadwindpass = { 249, 76, 696, 582 },
  desolace = { 167, 0, 910, 668 }, dunmorogh = { 155, 163, 920, 588 },
  durotar = { 244, 0, 749, 667 }, duskwood = { 19, 31, 999, 633 },
  dustwallow = { 230, 0, 860, 621 }, easternplaguelands = { 7, 9, 962, 668 },
  elwynn = { 0, 0, 1002, 668 }, felwood = { 271, 0, 723, 668 },
  feralas = { 192, 0, 976, 668 }, hilsbrad = { 2, 0, 989, 659 },
  hinterlands = { 13, 19, 863, 618 }, lochmodan = { 109, 11, 916, 668 },
  moonglade = { 244, 89, 799, 599 }, mulgore = { 249, 0, 779, 668 },
  redridge = { 0, 0, 949, 634 }, searinggorge = { 77, 8, 882, 668 },
  silithus = { 97, 12, 884, 668 }, silverpine = { 286, 0, 843, 662 },
  stonetalonmountains = { 210, 0, 908, 668 },
  stranglethorn = { 152, 0, 728, 613 }, swampofsorrows = { 0, 0, 1002, 668 },
  tanaris = { 203, 0, 789, 668 }, teldrassil = { 101, 93, 761, 648 },
  thousandneedles = { 0, 0, 930, 665 }, tirisfal = { 227, 104, 994, 596 },
  ungorocrater = { 121, 6, 870, 665 },
  westernplaguelands = { 137, 16, 874, 668 }, westfall = { 204, 0, 811, 657 },
  wetlands = { 13, 21, 961, 590 }, winterspring = { 222, 7, 762, 646 },
}

local state = {
  installed = false,
  failure = nil,
  zoom = 1, panX = 0, panY = 0,
  targetZoom = 1,  -- the zoom eases toward it
  gliding = false, velX = 0, velY = 0, -- pan velocity, canvas units per second
  -- Bumped when the zoom or the visible window settles (a zoom step, the end
  -- of a drag, a reset), not on every drag frame: other addons repaint their
  -- markers when it changes (U.WorldMapZoomState).
  version = 0,
  -- Bumped on every placement (each drag frame too), for owners whose
  -- re-place is cheap enough to follow the drag live.
  moveVersion = 0,
  regions = {},    -- cropped textures: tiles and overlays
  pinned = {},
  -- Last placement of frames placed through U.WorldMapZoomPlace, by frame.
  markers = {},
  sweepAt = 0,
}
ZOOM.state = state

local function Num(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if ok then return tonumber(value) end
  return nil
end

local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function Now()
  local fn = U.G("GetTime")
  if type(fn) ~= "function" then return 0 end
  local ok, t = pcall(fn)
  return ok and tonumber(t) or 0
end

local function Cursor()
  local fn = U.G("GetCursorPosition")
  if type(fn) ~= "function" then return nil end
  local ok, x, y = pcall(fn)
  if ok and tonumber(x) and tonumber(y) then return tonumber(x), tonumber(y) end
  return nil
end

-- Cursor in view units from its TOPLEFT (y down), and whether it is inside.
-- The view is never scaled itself, so its edges are in one space with the
-- cursor divided by its effective scale.
local function CursorInView()
  local view = state.view
  local x, y = Cursor()
  local scale = Num(view, "GetEffectiveScale")
  local left, top = Num(view, "GetLeft"), Num(view, "GetTop")
  if not x or not scale or scale <= 0 or not left or not top then return nil end
  local cx, cy = x / scale - left, top - y / scale
  return cx, cy, cx >= 0 and cy >= 0 and cx <= state.width and cy <= state.height
end

-- The visible window, in canvas (WorldMapDetailFrame) units.
local function Window()
  return state.panX, state.panY,
         state.panX + state.width / state.zoom, state.panY + state.height / state.zoom
end

-- ---------------------------------------------------------------------------
-- Cropping. A region's base (place, size, texcoords) is read only while the
-- canvas is at zoom 1: on the scaled canvas the edge reads drift, and
-- re-reading bases while zoomed corrupted them (user screenshot 2026-11-27:
-- tiles and overlays out of place after zooming back out). Bases are taken
-- on every zoom-in from 1, cropping and restoring use them alone.
-- ---------------------------------------------------------------------------

-- Position of a region inside WorldMapDetailFrame, in its units (y down).
-- Edge reads are in each region's own effective space
-- (frames.scaled_frame_edge_coordinates_mixed_space).
local function RegionBox(region)
  local detail = state.detail
  local dScale = Num(detail, "GetEffectiveScale")
  local rScale = Num(region, "GetEffectiveScale") or dScale
  local dLeft, dTop = Num(detail, "GetLeft"), Num(detail, "GetTop")
  local left, top = Num(region, "GetLeft"), Num(region, "GetTop")
  local w, h = Num(region, "GetWidth"), Num(region, "GetHeight")
  if not dScale or dScale <= 0 or not dLeft or not dTop or not left or
     not top or not w or not h then
    return nil
  end
  return (left * rScale - dLeft * dScale) / dScale,
         (dTop * dScale - top * rScale) / dScale, w, h
end

local function TexCoords(region)
  if type(region.GetTexCoord) ~= "function" then return 0, 1, 0, 1 end
  local ok, a, b, c, d, e = pcall(region.GetTexCoord, region)
  if not ok or not tonumber(a) or not tonumber(e) then return 0, 1, 0, 1 end
  -- 8-value readback (UL, LL, UR, LR): left ULx, right URx, top ULy,
  -- bottom LLy; only the 4-value form draws here
  -- (textures.settexcoord_rotated_8_value_form_ignored).
  return a, e, b, d
end

local function TakeBase(entry)
  local x, y, w, h = RegionBox(entry.region)
  if not x or w <= 0 or h <= 0 then
    entry.base = nil
    return
  end
  local l, r, t, b = TexCoords(entry.region)
  entry.base = { x = x, y = y, w = w, h = h, l = l, r = r, t = t, b = b }
end

-- Only the values that changed since the entry was last placed are written:
-- a drag frame moves only the regions on the window's edges, while interior
-- and out-of-view ones keep their placement. `force` writes everything, for
-- when the client may have rewritten the region itself.
local function Place(entry, x, y, w, h, l, r, t, b, alpha, force)
  local region = entry.region
  if force or entry.pa ~= alpha then
    pcall(region.SetAlpha, region, alpha)
    entry.pa = alpha
  end
  if force or entry.px ~= x or entry.py ~= y then
    pcall(region.ClearAllPoints, region)
    pcall(region.SetPoint, region, "TOPLEFT", state.detail, "TOPLEFT", x, -y)
    entry.px, entry.py = x, y
  end
  if force or entry.pw ~= w then
    pcall(region.SetWidth, region, w)
    entry.pw = w
  end
  if force or entry.ph ~= h then
    pcall(region.SetHeight, region, h)
    entry.ph = h
  end
  if force or entry.pl ~= l or entry.pr ~= r or entry.pt ~= t or entry.pb ~= b then
    pcall(region.SetTexCoord, region, l, r, t, b)
    entry.pl, entry.pr, entry.pt, entry.pb = l, r, t, b
  end
end

local function CropRegion(entry, restore, force)
  local base = entry.base
  if not base then return end
  if restore then
    Place(entry, base.x, base.y, base.w, base.h, base.l, base.r, base.t, base.b, 1, force)
    return
  end
  local vx0, vy0, vx1, vy1 = Window()
  local ix0, iy0 = math.max(base.x, vx0), math.max(base.y, vy0)
  local ix1, iy1 = math.min(base.x + base.w, vx1), math.min(base.y + base.h, vy1)
  if ix1 <= ix0 or iy1 <= iy0 then
    -- Out of view: kept at its base, faded (never hidden, so the client's own
    -- show/hide of overlays stays in charge).
    Place(entry, base.x, base.y, base.w, base.h, base.l, base.r, base.t, base.b, 0, force)
    return
  end
  local du, dv = base.r - base.l, base.b - base.t
  Place(entry, ix0, iy0, ix1 - ix0, iy1 - iy0,
        base.l + (ix0 - base.x) / base.w * du, base.l + (ix1 - base.x) / base.w * du,
        base.t + (iy0 - base.y) / base.h * dv, base.t + (iy1 - base.y) / base.h * dv, 1,
        force)
end

local function CollectRegions()
  local i
  for i = 1, 16 do
    local tile = U.G("WorldMapDetailTile" .. i)
    if tile then table.insert(state.regions, { region = tile, tile = true }) end
  end
  for i = 1, 64 do
    local overlay = U.G("WorldMapOverlay" .. i)
    if overlay then table.insert(state.regions, { region = overlay }) end
  end
end

-- tilesOnly: after a map change the client has just rewritten the overlays
-- for the new map, so only the tiles (whose place never changes) go back;
-- overlays only get their alpha back.
local function CropAll(restore, tilesOnly, force)
  local i
  for i = 1, table.getn(state.regions) do
    local entry = state.regions[i]
    if not tilesOnly or entry.tile then
      CropRegion(entry, restore, force)
    else
      -- The client re-placed this overlay but never resets its alpha: one
      -- faded out of view on the old map would stay invisible (fog). Its
      -- base and placement cache belong to the old map too.
      pcall(entry.region.SetAlpha, entry.region, 1)
      entry.base = nil
      entry.px, entry.py, entry.pw, entry.ph = nil, nil, nil, nil
      entry.pl, entry.pr, entry.pt, entry.pb = nil, nil, nil, nil
      entry.pa = 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- Markers: icons that keep their size and vanish out of view (user report,
-- 2026-11-27: the town icons grew with the zoom and spilled out of the map).
-- A marker at canvas point (x, y) is drawn at scale 1/zoom, so its effective
-- size stays the map's, and anchored with offsets times the zoom, because
-- SetPoint offsets are in the frame's own scaled units. The anchor is on
-- WorldMapDetailFrame, which the pan carries, so a drag changes neither: only
-- what differs from the last placement (kept on `cache`) is written.
-- ---------------------------------------------------------------------------

local function PlaceMarker(frame, x, y, cache, force)
  local zoom = state.zoom
  local vx0, vy0, vx1, vy1 = Window()
  local inside = zoom <= MIN_ZOOM or
                 (x >= vx0 and x <= vx1 and y >= vy0 and y <= vy1)
  local scale, ox, oy = 1 / zoom, x * zoom, -y * zoom
  if force or cache.zoomScale ~= scale then
    pcall(frame.SetScale, frame, scale)
    cache.zoomScale = scale
  end
  if force or cache.zoomX ~= ox or cache.zoomY ~= oy then
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, "CENTER", state.detail, "TOPLEFT", ox, oy)
    cache.zoomX, cache.zoomY = ox, oy
  end
  return inside
end

-- The client's landmark icons (towns, dungeons), WorldMapFramePOIn, found by
-- name -- never by walking WorldMapButton's ~640 children: a per-frame child
-- walk has crashed this client (nameplates.flicker_probe_walk_crash) and
-- walked handles may lack writers (widgets.region_walk_wrapper_lacks_setters).
-- Their centres are read at zoom 1 with the other bases.
local function TakePoiBases()
  state.pois = {}
  local i
  for i = 1, 64 do
    local poi = U.G("WorldMapFramePOI" .. i)
    if not poi then break end
    local x, y, w, h = RegionBox(poi)
    if x then
      table.insert(state.pois, { frame = poi, x = x + w / 2, y = y + h / 2 })
    end
  end
end

-- restore: back to scale 1 at the base. mapChanged: the client has just
-- placed them for a new map, so only the scale and alpha go back.
local function ApplyPois(restore, mapChanged, force)
  local pois = state.pois or {}
  local i
  for i = 1, table.getn(pois) do
    local entry = pois[i]
    local frame = entry.frame
    local alpha = 1
    if mapChanged then
      pcall(frame.SetScale, frame, 1)
      force = true
    elseif restore then
      if force or entry.zoomScale ~= 1 then
        pcall(frame.SetScale, frame, 1)
        entry.zoomScale = 1
      end
      if force or entry.zoomX ~= entry.x or entry.zoomY ~= -entry.y then
        pcall(frame.ClearAllPoints, frame)
        pcall(frame.SetPoint, frame, "CENTER", state.detail, "TOPLEFT", entry.x, -entry.y)
        entry.zoomX, entry.zoomY = entry.x, -entry.y
      end
    elseif not PlaceMarker(frame, entry.x, entry.y, entry, force) then
      alpha = 0
    end
    if force or entry.alpha ~= alpha then
      pcall(frame.SetAlpha, frame, alpha)
      entry.alpha = alpha
    end
  end
  if mapChanged then state.pois = {} end
end

-- Leaving zoom 1 the bases are read again, and what the client may have
-- rewritten since is placed in full on the next Apply.
local function TakeBases()
  local i
  for i = 1, table.getn(state.regions) do TakeBase(state.regions[i]) end
  TakePoiBases()
  state.forcePlace = true
end

-- For marker owners in this addon (the player arrow): place `frame` at canvas
-- fraction (u, v) of WorldMapDetailFrame at the map's own icon size. Returns
-- false when that point is out of the zoomed view, for the caller to hide.
function U.WorldMapZoomPlace(frame, u, v)
  if state.external then return state.external.ZoomPlace(frame, u, v) end
  if not state.installed or not frame then return nil end
  -- The zoom owns the frame's scale and anchor from then on; the cache is
  -- bounded by the callers (the player arrow).
  local cache = state.markers[frame]
  if not cache then
    cache = {}
    state.markers[frame] = cache
  end
  return PlaceMarker(frame, u * state.width, v * state.height, cache)
end

-- Other canvas frames (quest pins of other addons) are left alone; their
-- owners can read the visible window from U.WorldMapZoomWindow.

-- ---------------------------------------------------------------------------
-- Chrome kept fixed: counter-scaled, anchored to the view.
-- ---------------------------------------------------------------------------

-- Built once: the layout is fixed, and this ran on every drag frame.
local pinnedSpecs
local function PinnedSpecs()
  if pinnedSpecs then return pinnedSpecs end
  local layout = M.worldMapWindow or {}
  pinnedSpecs = {
    { name = "UnrealUIWorldMapZoneLabel", point = "TOP", relativePoint = "TOP",
      x = 0, y = layout.zoneLabelY or 0 },
    { name = "UnrealUIWorldMapCursorCoordinates", point = "TOPLEFT",
      relativePoint = "TOPLEFT", x = 8, y = -8 },
    { name = "UnrealUIWorldMapMinimizeButton", point = "CENTER",
      relativePoint = "TOPRIGHT", x = layout.buttonX or 0, y = layout.buttonY or 0 },
    { name = "UnrealUIWorldMapResizeGrip", point = "CENTER",
      relativePoint = "BOTTOMRIGHT", x = layout.gripX or 0, y = layout.gripY or 0 },
    { name = "UnrealUIWorldMapZoomHint", point = "RIGHT",
      relativePoint = "TOPRIGHT", x = layout.zoomHintX or -8,
      y = layout.zoomHintY or 21 },
    { name = "UnrealUIWorldMapZoomIn", point = "BOTTOMLEFT",
      relativePoint = "BOTTOMLEFT", x = layout.zoomButtonX or 8,
      y = layout.zoomButtonY or 8 },
    { name = "UnrealUIWorldMapZoomOut", point = "BOTTOMLEFT",
      relativePoint = "BOTTOMLEFT",
      x = (layout.zoomButtonX or 8) + (layout.zoomButtonGap or 24),
      y = layout.zoomButtonY or 8 },
  }
  return pinnedSpecs
end

-- The view moves with neither the pan nor the zoom, so the chrome is written
-- only when the zoom changed, or on a forced pass.
local function ApplyPinned(force)
  if not force and state.pinnedZoom == state.zoom then return end
  state.pinnedZoom = state.zoom
  local specs = PinnedSpecs()
  local i
  for i = 1, table.getn(specs) do
    local spec = specs[i]
    local frame = U.G(spec.name)
    if frame then
      state.pinned[spec.name] = true
      pcall(frame.SetScale, frame, 1 / state.zoom)
      pcall(frame.ClearAllPoints, frame)
      pcall(frame.SetPoint, frame, spec.point, state.view, spec.relativePoint,
            spec.x, spec.y)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Zoom state
-- ---------------------------------------------------------------------------

-- tilesOnly (map change): see CropAll. A call that changes neither the zoom
-- nor the clamped pan (a drag held against the map's edge) writes nothing and
-- leaves the move counter alone, so marker owners skip that frame too.
-- The current map's zone box in canvas units, or nil; cached per map.
local function ZoneBox()
  if state.boxKey == state.mapKey then return state.box end
  state.boxKey, state.box = state.mapKey, nil
  local fn = U.G("GetMapInfo")
  local ok, name = false, nil
  if type(fn) == "function" then ok, name = pcall(fn) end
  if not ok or type(name) ~= "string" then return nil end
  name = string.lower(name)
  local raw = ZONE_BOUNDS[name] or ZONE_BOUNDS[string.gsub(name, "^the", "")]
  if not raw then return nil end
  local sx, sy = state.width / CANVAS_W, state.height / CANVAS_H
  state.box = { raw[1] * sx, raw[2] * sy, raw[3] * sx, raw[4] * sy }
  return state.box
end

-- A window wider than the zone is centred on it; a narrower one stays inside.
local function ClampAxis(pan, window, total, low, high)
  if window >= high - low then
    pan = (low + high - window) / 2
  else
    pan = Clamp(pan, low, high - window)
  end
  return Clamp(pan, 0, total - window)
end

local function Apply(tilesOnly)
  if not state.installed then return end
  local force = state.forcePlace
  state.forcePlace = false
  local zoom = state.zoom
  local box = ZoneBox()
  local w, h = state.width / zoom, state.height / zoom
  state.panX = ClampAxis(state.panX, w, state.width,
                         box and box[1] or 0, box and box[3] or state.width)
  state.panY = ClampAxis(state.panY, h, state.height,
                         box and box[2] or 0, box and box[4] or state.height)
  local panX, panY = state.panX, state.panY
  local zoomed = force or state.appliedZoom ~= zoom
  if not zoomed and state.appliedX == panX and state.appliedY == panY then return end
  local content = state.content
  if zoomed then pcall(content.SetScale, content, zoom) end
  pcall(content.ClearAllPoints, content)
  pcall(content.SetPoint, content, "TOPLEFT", state.view, "TOPLEFT", -panX, panY)
  state.appliedZoom, state.appliedX, state.appliedY = zoom, panX, panY
  state.moveVersion = state.moveVersion + 1
  -- The zoomed canvas extends past the window, undrawn; its hover and clicks
  -- are kept to the window (insets in the canvas's own units). The method is
  -- not runtime-verified here (GetHitRectInsets reads nil), so it is guarded.
  local button = state.button
  if button and type(button.SetHitRectInsets) == "function" then
    pcall(button.SetHitRectInsets, button, panX,
          state.width - panX - state.width / zoom, panY,
          state.height - panY - state.height / zoom)
  end
  if zoom <= MIN_ZOOM then
    CropAll(true, tilesOnly, force)
    ApplyPois(true, tilesOnly, force)
  else
    CropAll(false, nil, force)
    ApplyPois(false, nil, force)
  end
  ApplyPinned(force)
end

-- The client rewrites overlays and landmarks on its own map updates, which
-- the placement cache cannot see: everything is written again.
local function SweepPlacement()
  CropAll(false, nil, true)
  ApplyPois(false, nil, true)
  ApplyPinned(true)
end

local function Install()
  local map = U.G("WorldMapFrame")
  local guide = U.G("WorldMapPositioningGuide")
  local detail = U.G("WorldMapDetailFrame")
  local button = U.G("WorldMapButton")
  if not map or not guide or not detail or not button then
    return false, "native map frames missing"
  end
  local width, height = Num(detail, "GetWidth"), Num(detail, "GetHeight")
  if not width or not height or width <= 0 or height <= 0 then
    return false, "no WorldMapDetailFrame size"
  end
  local detailLevel = Num(detail, "GetFrameLevel")
  local buttonLevel = Num(button, "GetFrameLevel")
  state.width, state.height = width, height
  state.map, state.detail, state.button = map, detail, button

  local ok, view = pcall(CreateFrame, "Frame", "UnrealUIWorldMapZoomView", map)
  if not ok or not view then return false, "no view frame" end
  local made, content = pcall(CreateFrame, "Frame", "UnrealUIWorldMapZoomContent", view)
  if not made or not content then return false, "no content frame" end
  local built = pcall(function()
    view:SetWidth(width)
    view:SetHeight(height)
    view:SetPoint("TOPLEFT", guide, "TOP", ANCHOR_X, ANCHOR_Y)
    if detailLevel then view:SetFrameLevel(detailLevel) end
    content:SetWidth(width)
    content:SetHeight(height)
    content:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    if detailLevel then content:SetFrameLevel(detailLevel) end
  end)
  if not built then return false, "view setup failed" end
  state.view, state.content = view, content

  -- Bases are measured before the move, at the native placement.
  CollectRegions()
  local i

  detail:SetParent(content)
  detail:ClearAllPoints()
  detail:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  button:SetParent(content)
  if detailLevel then pcall(detail.SetFrameLevel, detail, detailLevel) end
  if buttonLevel then pcall(button.SetFrameLevel, button, buttonLevel) end

  -- The wheel catcher sat on the canvas; the canvas now scales, the view not.
  local catchers = state.catchers or {}
  for i = 1, table.getn(catchers) do
    pcall(catchers[i].ClearAllPoints, catchers[i])
    pcall(catchers[i].SetAllPoints, catchers[i], view)
  end
  local specs = PinnedSpecs()
  for i = 1, table.getn(specs) do state.pinned[specs[i].name] = true end

  state.installed = true
  return true
end

local function EnsureInstalled()
  if state.installed then return true end
  if state.failure then return false end
  local ok, installed, failure = pcall(Install)
  if not ok then
    state.failure = tostring(installed)
  elseif not installed then
    state.failure = failure
  end
  if state.failure then
    U.Debug("world map zoom unavailable: " .. tostring(state.failure))
    return false
  end
  return true
end

-- Keeps the map point under the cursor fixed; outside the map, the centre.
-- One eased frame; the version is bumped once the zoom settles (StepZoom).
local function ZoomTo(zoom)
  zoom = Clamp(zoom, MIN_ZOOM, MAX_ZOOM)
  if zoom == state.zoom then return end
  if not EnsureInstalled() then return end
  local cx, cy, inside = CursorInView()
  if not cx or not inside then cx, cy = state.width / 2, state.height / 2 end
  local mapX, mapY = state.panX + cx / state.zoom, state.panY + cy / state.zoom
  -- Leaving zoom 1: the canvas is unscaled right now, the one state where
  -- the bases read true.
  if state.zoom <= MIN_ZOOM then TakeBases() end
  state.zoom = zoom
  state.panX, state.panY = mapX - cx / zoom, mapY - cy / zoom
  Apply()
end

-- The next stop of `stops` in the notch's direction, held at either end.
local function NextStop(stops, from, steps)
  local n, i = table.getn(stops)
  if steps > 0 then
    for i = 1, n do
      if stops[i] > from + 0.001 then return stops[i] end
    end
    return stops[n]
  end
  for i = n, 1, -1 do
    if stops[i] < from - 0.001 then return stops[i] end
  end
  return stops[1]
end

local function ZoomBy(steps)
  local target = Clamp(NextStop(ZOOM_STOPS, state.targetZoom, steps), MIN_ZOOM, MAX_ZOOM)
  if target == state.targetZoom then return end
  if not EnsureInstalled() then return end
  state.targetZoom = target
  state.gliding = false
end

-- 1 - e^(-rate * dt): the share of the way covered this frame. math.exp and
-- math.log are not runtime-verified on this client; without them the ease
-- falls back to a linear share and a linear zoom.
local HAS_EXP = type(math.exp) == "function" and type(math.log) == "function"

local function Decay(rate, dt)
  if HAS_EXP then return math.exp(-rate * dt) end
  return Clamp(1 - rate * dt, 0, 1)
end

-- Eases in log space so each step feels the same at any zoom.
local function StepZoom(dt)
  local target = state.targetZoom
  if state.zoom == target then return end
  local t = 1 - Decay(ZOOM_RATE, dt)
  local zoom
  if HAS_EXP then
    local from = math.log(state.zoom)
    zoom = math.exp(from + (math.log(target) - from) * t)
  else
    zoom = state.zoom + (target - state.zoom) * t
  end
  if math.abs(zoom - target) < ZOOM_SNAP then zoom = target end
  ZoomTo(zoom)
  if state.zoom == target then state.version = state.version + 1 end
end

local function StopMotion()
  state.gliding, state.velX, state.velY = false, 0, 0
  if state.zoom ~= state.targetZoom then
    ZoomTo(state.targetZoom)
    state.version = state.version + 1
  end
end

local function Reset(mapChanged)
  state.dragging, state.justDragged, state.down = false, false, false
  state.gliding, state.velX, state.velY = false, 0, 0
  state.targetZoom = MIN_ZOOM
  if state.zoom == MIN_ZOOM and state.panX == 0 and state.panY == 0 then return end
  state.zoom, state.panX, state.panY = MIN_ZOOM, 0, 0
  Apply(mapChanged)
  state.version = state.version + 1
end

-- For modules/worldmap.lua's cursor readout and hover fallback: the canvas
-- rectangle as drawn (the view), and a view-space 0..1 point turned into the
-- canvas point under it.
function U.WorldMapZoomView()
  if state.external then return state.external.ZoomView() end
  if state.installed then return state.view end
  return nil
end

function U.WorldMapZoomToCanvas(u, v)
  if state.external then return state.external.ZoomToCanvas(u, v) end
  if not state.installed or state.zoom <= MIN_ZOOM then return u, v end
  return state.panX / state.width + u / state.zoom,
         state.panY / state.height + v / state.zoom
end

-- For other addons' map markers (unrealQuest, unrealConquest): the zoom
-- factor and a counter that changes whenever the zoom or the visible window
-- settles. A marker of fixed size at canvas fraction (u, v) is drawn at
-- SetScale(1 / zoom) with its canvas offsets multiplied by zoom; map-content
-- textures are cropped to U.WorldMapZoomWindow.
-- Third value: the move counter (every placement, drag frames included).
function U.WorldMapZoomState()
  if state.external then return state.external.ZoomState() end
  if not state.installed then return 1, state.version, state.moveVersion end
  return state.zoom, state.version, state.moveVersion
end

-- Whether the world map is being drawn: the zoom driver, a WorldMapFrame
-- child, ticked this frame or the one before. For addons whose own test
-- (WorldMapFrame:IsVisible, or a hidden UIParent) misreads unrealUI's
-- minimized map, around which the HUD stays shown.
function U.WorldMapIsOpen()
  if state.external then return state.external.IsOpen() end
  return state.tickAt ~= nil and Now() - state.tickAt <= OPEN_TICK_SECONDS
end

-- The visible part of the canvas as 0..1 fractions (left, top, right,
-- bottom), for pin owners that want to hide what is out of view.
function U.WorldMapZoomWindow()
  if state.external then return state.external.ZoomWindow() end
  if not state.installed or state.zoom <= MIN_ZOOM then return 0, 0, 1, 1 end
  local x0, y0, x1, y1 = Window()
  return x0 / state.width, y0 / state.height, x1 / state.width, y1 / state.height
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function OnMouseDown(a1, a2)
  local which = a2 or U.G("arg1")
  if type(a1) == "string" then which = a1 end
  state.justDragged = false
  -- A press catches a gliding map.
  if state.gliding then
    state.gliding = false
    state.version = state.version + 1
  end
  if which ~= nil and which ~= "LeftButton" then return end
  if state.zoom <= MIN_ZOOM and state.targetZoom <= MIN_ZOOM then return end
  state.downX, state.downY = Cursor()
  state.lastX, state.lastY = state.downX, state.downY
  state.velX, state.velY = 0, 0
  state.lastMoveAt = Now()
  state.down = state.downX ~= nil
end

-- A release soon after a fast move glides on.
local function StartGlide()
  local speed = math.sqrt(state.velX * state.velX + state.velY * state.velY) *
                state.zoom
  local recent = state.lastMoveAt and Now() - state.lastMoveAt < GLIDE_RELEASE_WINDOW
  if not recent or speed < GLIDE_START_SPEED then
    state.velX, state.velY = 0, 0
    return false
  end
  if speed > GLIDE_MAX_SPEED then
    state.velX = state.velX * GLIDE_MAX_SPEED / speed
    state.velY = state.velY * GLIDE_MAX_SPEED / speed
  end
  state.gliding = true
  return true
end

-- WorldMapButton's native OnMouseUp is the zoom in/out click; it is skipped
-- after a drag. Wrapped once, the original kept.
local function WrapMouseUp(button)
  local ok, previous = pcall(button.GetScript, button, "OnMouseUp")
  if not ok then return end
  pcall(button.SetScript, button, "OnMouseUp", function(a1, a2, a3, a4, a5)
    local dragged = state.dragging
    state.down, state.dragging = false, false
    if dragged then
      state.justDragged = true
      -- A glide bumps the version when it stops.
      if not StartGlide() then state.version = state.version + 1 end
      return
    end
    if previous then previous(a1, a2, a3, a4, a5) end
  end)
end

-- Pans by the cursor's move since the last frame, so a wheel zoom during a
-- drag stays under the cursor, and tracks the release velocity.
local function StepDrag()
  local x, y = Cursor()
  if not x then return end
  if not state.dragging and (math.abs(x - state.downX) > DRAG_PIXELS or
                             math.abs(y - state.downY) > DRAG_PIXELS) then
    state.dragging = true
  end
  if not state.dragging then return end
  local scale = Num(state.view, "GetEffectiveScale")
  if not scale or scale <= 0 then return end
  local dx = (x - state.lastX) / scale / state.zoom
  local dy = (y - state.lastY) / scale / state.zoom
  state.lastX, state.lastY = x, y
  if dx == 0 and dy == 0 then return end
  state.panX = state.panX - dx
  state.panY = state.panY + dy
  -- Over the time since the cursor last moved: it can hold still for frames
  -- between moves at a high frame rate.
  local now = Now()
  local span = now - (state.lastMoveAt or now)
  if span > 0 and span < MAX_FRAME_TIME then
    state.velX = state.velX * 0.5 - dx / span * 0.5
    state.velY = state.velY * 0.5 + dy / span * 0.5
  end
  state.lastMoveAt = now
  Apply()
end

-- For other addons' mouse-enabled canvas pins (unrealQuest's objective
-- areas, user report 2026-11-27: no drag and no right-click zoom-out on
-- them): they take the press before WorldMapButton and forward its
-- OnMouseDown/OnMouseUp scripts. True while a drag runs and from its release
-- to the next press, so the pin's own OnClick (in either order with
-- OnMouseUp) skips the click that ended a drag.
-- The pin asks only on its left release, which it forwards only when this
-- says "dragging" (user report 2026-11-27: the map kept following the cursor
-- after a release on an area). So a move since the last frame is taken first,
-- and a press that never became a drag ends here: the canvas sees no release.
function U.WorldMapZoomDragging()
  if state.external then
    local fn = state.external.ZoomDragging
    if type(fn) == "function" then return fn() end
    return false
  end
  if state.down then
    StepDrag()
    if not state.dragging then state.down = false end
  end
  return (state.dragging or state.justDragged) and true or false
end

-- For marker owners (unrealQuest asks unrealUI first): true while their map
-- markers should be hidden because the map is moving. The option lives in
-- unrealMap's settings ("Hide map markers while moving the map"), so this
-- addon's own zoom never asks for it.
function U.WorldMapZoomMarkersHidden()
  if state.external then
    local fn = state.external.ZoomMarkersHidden
    if type(fn) == "function" then return fn() and true or false end
  end
  return false
end

local function StepGlide(dt)
  local x, y = state.panX + state.velX * dt, state.panY + state.velY * dt
  state.panX, state.panY = x, y
  Apply()
  -- Apply clamps the pan to the map; the axis that hit an edge stops.
  if state.panX ~= x then state.velX = 0 end
  if state.panY ~= y then state.velY = 0 end
  local decay = Decay(GLIDE_FRICTION, dt)
  state.velX, state.velY = state.velX * decay, state.velY * decay
  local speed = math.sqrt(state.velX * state.velX + state.velY * state.velY) *
                state.zoom
  if speed < GLIDE_STOP_SPEED then
    state.gliding, state.velX, state.velY = false, 0, 0
    state.version = state.version + 1
  end
end

local function Drive()
  local now = Now()
  local last = state.tickAt
  state.tickAt = now
  -- The map was closed (the driver does not tick then): motion ends at once
  -- instead of resuming on the next open.
  if not last or now - last > OPEN_TICK_SECONDS then
    -- A press whose release went unseen while the map was closed.
    state.down, state.dragging = false, false
    if state.installed then StopMotion() end
    last = now
  end
  local dt = Clamp(now - last, 0, MAX_FRAME_TIME)
  if state.down then
    StepDrag()
  elseif state.gliding then
    StepGlide(dt)
  end
  if state.installed then StepZoom(dt) end
  -- The client rewrites overlays on its own map updates; they are placed
  -- again in full a few times a second while zoomed, and at once after a
  -- WORLD_MAP_UPDATE that kept the map.
  if state.installed and state.zoom > MIN_ZOOM and
     (state.sweepDue or now - state.sweepAt >= SWEEP_SECONDS) then
    state.sweepAt, state.sweepDue = now, false
    SweepPlacement()
  end
end

-- The zone hover highlight (WorldMapHighlight) is rewritten whole by the
-- map's own OnUpdate on every frame, so on a zoomed map it is drawn again
-- straight after, from the cursor's canvas point: UpdateMapHighlight returns
-- name, fileName, texcoord scale x/y, size x/y and offset x/y as map
-- fractions (documentation.json global:Mapping:UpdateMapHighlight; fileName
-- is nil on a zone map, which has no highlight). It is cropped to the window
-- like the tiles; with the cursor outside the window it is faded.
local function CropHighlight()
  if not state.installed or state.zoom <= MIN_ZOOM then return end
  local highlight = U.G("WorldMapHighlight")
  local hitTest = U.G("UpdateMapHighlight")
  if not highlight or type(hitTest) ~= "function" then return end
  local cx, cy, inside = CursorInView()
  if not cx or not inside then
    pcall(highlight.SetAlpha, highlight, 0)
    return
  end
  local u = (state.panX + cx / state.zoom) / state.width
  local v = (state.panY + cy / state.zoom) / state.height
  local ok, name, file, texX, texY, sizeX, sizeY, offsetX, offsetY = pcall(hitTest, u, v)
  if not ok or not name or type(file) ~= "string" or file == "" or
     not tonumber(sizeX) or not tonumber(sizeY) or sizeX <= 0 or sizeY <= 0 then
    return
  end
  local x, y = (tonumber(offsetX) or 0) * state.width, (tonumber(offsetY) or 0) * state.height
  local w, h = sizeX * state.width, sizeY * state.height
  local vx0, vy0, vx1, vy1 = Window()
  local ix0, iy0 = math.max(x, vx0), math.max(y, vy0)
  local ix1, iy1 = math.min(x + w, vx1), math.min(y + h, vy1)
  if ix1 <= ix0 or iy1 <= iy0 then
    pcall(highlight.SetAlpha, highlight, 0)
    return
  end
  local du, dv = tonumber(texX) or 1, tonumber(texY) or 1
  local path = "Interface\\WorldMap\\" .. file .. "\\" .. file .. "Highlight"
  if state.highlightPath ~= path then
    pcall(highlight.SetTexture, highlight, path)
    state.highlightPath = path
  end
  pcall(highlight.SetTexCoord, highlight, (ix0 - x) / w * du, (ix1 - x) / w * du,
        (iy0 - y) / h * dv, (iy1 - y) / h * dv)
  pcall(highlight.ClearAllPoints, highlight)
  pcall(highlight.SetPoint, highlight, "TOPLEFT", state.detail, "TOPLEFT", ix0, -iy0)
  pcall(highlight.SetWidth, highlight, ix1 - ix0)
  pcall(highlight.SetHeight, highlight, iy1 - iy0)
  pcall(highlight.SetAlpha, highlight, 1)
  pcall(highlight.Show, highlight)
end

-- The wheel. Only a ScrollFrame catches it here, and mapzoom.v2 measured it
-- reaching one parented to UIParent and not one parented to WorldFrame. It
-- serves both map sizes: modules/worldmap.lua keeps UIParent shown while the
-- map is open (at alpha 0 under the full-size map). A parentless catcher got
-- no wheel at full size (user report 2026-11-27) and is gone. The catcher
-- takes the wheel only while the map is drawn and ticking, so the camera
-- keeps the wheel once the map is closed.
local function UiParentShown()
  local parent = U.G("UIParent")
  if not parent or type(parent.IsShown) ~= "function" then return false end
  local ok, shown = pcall(parent.IsShown, parent)
  return ok and shown and true or false
end

local function BuildWheelCatcher(view, parent, wantsHud)
  local ok, catcher = pcall(CreateFrame, "ScrollFrame", nil, parent)
  if not ok or not catcher then return end
  local built = pcall(function()
    local child = CreateFrame("Frame", nil, catcher)
    child:SetWidth(1)
    child:SetHeight(1)
    catcher:SetScrollChild(child)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetFrameLevel(math.max((Num(view, "GetFrameLevel") or 1) + 30, 60))
    catcher:SetAllPoints(view)
    if catcher.EnableMouse then catcher:EnableMouse(false) end
    catcher:EnableMouseWheel(false)
    catcher:SetScript("OnMouseWheel", function()
      local delta = tonumber(U.G("arg1"))
      if not delta or delta == 0 then return end
      ZoomBy(delta > 0 and 1 or -1)
    end)
  end)
  if not built then return end
  local on = false
  catcher:SetScript("OnUpdate", function()
    local shown = state.view or view
    local open = shown.IsVisible and shown:IsVisible() and
                 Now() - (state.tickAt or 0) <= OPEN_TICK_SECONDS and
                 UiParentShown() == wantsHud
    open = open and true or false
    if open ~= on then
      on = open
      pcall(catcher.EnableMouseWheel, catcher, on)
    end
  end)
  state.catchers = state.catchers or {}
  table.insert(state.catchers, catcher)
end

-- + / - on the canvas, built like the minimize toggle (a level-120 Button
-- child of WorldMapButton with a file-backed texture, the construction
-- confirmed to draw on this map), with the plus-minus art.
local function BuildZoomButton(canvas, name, which, onClick)
  local cells = M.modernWow and M.modernWow.plusMinusCell
  local path = M.modernWow and M.modernWow.texture and M.modernWow.texture.plusMinus
  if not cells or not path then return nil end
  local ok, button = pcall(CreateFrame, "Button", name, canvas)
  if not ok or not button then return nil end
  button:SetWidth(cells.width)
  button:SetHeight(cells.height)
  -- +25 over the shared control level: above every map marker (unrealQuest
  -- pins sit at that level plus boosts up to 19), below its giver menu (+30).
  button:SetFrameLevel(math.max((Num(canvas, "GetFrameLevel") or 0) + 20, 120) + 25)
  pcall(button.EnableMouse, button, true)
  local face = button:CreateTexture(nil, "ARTWORK")
  pcall(face.SetTexture, face, path)
  pcall(face.SetAllPoints, face, button)
  local function Paint(down)
    local cell = cells[which .. (down and "Pushed" or "Normal")]
    pcall(face.SetTexCoord, face, cell[1] / cells.sheet, cell[2] / cells.sheet,
          cell[3] / cells.sheet, cell[4] / cells.sheet)
  end
  button:SetScript("OnMouseDown", function() Paint(true) end)
  button:SetScript("OnMouseUp", function() Paint(false) end)
  button:SetScript("OnClick", onClick)
  Paint(false)
  return button
end

-- "Zoom" hint in the header, on the Zoom Out button's line at the right, as
-- in PandaMap's MapZoom.lua (user requests, 2026-11-27; reference, not
-- evidence): the cursor readout's
-- verified overlay shape (modules/worldmap.lua), a level-120 Button child of
-- WorldMapButton with a file-backed fill, here with the wheel icon and a
-- label. Mouse is off so the map below keeps its hover and clicks. Built
-- here also when unrealMap owns the zoom; it is then pinned there.
local function BuildZoomHint(canvas)
  local layout = M.worldMapWindow or {}
  local size = layout.zoomHintIcon or 22
  local ok, frame = pcall(CreateFrame, "Button", "UnrealUIWorldMapZoomHint", canvas)
  if not ok or not frame then return end
  frame:SetHeight(size + 4)
  frame:SetPoint("RIGHT", canvas, "TOPRIGHT", layout.zoomHintX or -8,
                 layout.zoomHintY or 21)
  frame:SetFrameLevel(math.max((Num(canvas, "GetFrameLevel") or 0) + 20, 120))
  if frame.EnableMouse then frame:EnableMouse(false) end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(M.texture.plain)
  fill:SetAllPoints(frame)
  U.SetColor(fill, M.Unpack(M.color.background))

  local icon = frame:CreateTexture(nil, "ARTWORK")
  pcall(icon.SetTexture, icon, M.texture.mapZoomHint)
  icon:SetWidth(size)
  icon:SetHeight(size)
  icon:SetPoint("LEFT", frame, "LEFT", 4, 0)

  local width = 4 + size + 7
  local label = U.CreateLabel(frame, {
    inherits = "GameFontNormal",
    size = M.fontSize.normal,
    color = M.color.text,
    justify = "LEFT",
  })
  if label then
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetText(U.L("WORLDMAP_ZOOM_HINT"))
    local textWidth = Num(label, "GetStringWidth") or 0
    if textWidth <= 0 then textWidth = 40 end
    width = width + 4 + textWidth
  end
  frame:SetWidth(width)
end

-- Diagnostic (user report 2026-11-27: a continent view snapped back to the
-- zone again): every SetMapToCurrentZone made while the map is open is saved
-- with the Lua callers above it to UnrealUIDiagDB.mapRecenter, at most 12,
-- so one reload names the addon doing it.
local RECENTER_KEEP = 12
local function RecordRecenter()
  if not U.WorldMapIsOpen() or type(U.SaveDiagnostic) ~= "function" then return end
  state.recenters = state.recenters or {}
  if table.getn(state.recenters) >= RECENTER_KEEP then return end
  local callers = {}
  local getinfo = type(debug) == "table" and debug.getinfo
  local level
  for level = 2, 9 do
    local ok, info = false, nil
    if type(getinfo) == "function" then ok, info = pcall(getinfo, level, "Sl") end
    if not ok or not info then break end
    table.insert(callers, tostring(info.short_src or info.source) .. ":" ..
                 tostring(info.currentline))
  end
  table.insert(state.recenters, string.format("%.2f %s", Now(),
               table.concat(callers, " < ")))
  U.SaveDiagnostic("mapRecenter", state.recenters)
end

local function MapKey()
  local continent, zone
  local getContinent, getZone = U.G("GetCurrentMapContinent"), U.G("GetCurrentMapZone")
  if type(getContinent) == "function" then
    local ok, value = pcall(getContinent)
    if ok then continent = value end
  end
  if type(getZone) == "function" then
    local ok, value = pcall(getZone)
    if ok then zone = value end
  end
  return tostring(continent) .. ":" .. tostring(zone)
end

-- A new map starts unzoomed; its overlays are taken again on the next crop.
local function OnMapUpdate()
  local key = MapKey()
  if key ~= state.mapKey then
    state.mapKey = key
    Reset(true)
  else
    state.sweepDue = true
  end
end

function ZOOM:OnEnable()
  -- unrealMap installed: its zoom runs instead (U.ExternalMapWindow), and
  -- this addon's own map chrome is pinned in it so it does not zoom.
  local external = U.ExternalMapWindow and U.ExternalMapWindow()
  if external then
    state.external = external
    local hintCanvas = U.G("WorldMapButton")
    if hintCanvas then BuildZoomHint(hintCanvas) end
    local specs = PinnedSpecs()
    local i
    for i = 1, table.getn(specs) do
      local spec = specs[i]
      if spec.name == "UnrealUIWorldMapZoneLabel" or
         spec.name == "UnrealUIWorldMapCursorCoordinates" or
         spec.name == "UnrealUIWorldMapZoomHint" then
        pcall(external.Pin, spec.name, spec.point, spec.relativePoint, spec.x, spec.y)
      end
    end
    return
  end

  local canvas = U.G("WorldMapButton")
  local map = U.G("WorldMapFrame")
  if not canvas or not map then return end

  BuildZoomButton(canvas, "UnrealUIWorldMapZoomIn", "plus", function() ZoomBy(1) end)
  BuildZoomButton(canvas, "UnrealUIWorldMapZoomOut", "minus", function() ZoomBy(-1) end)
  BuildZoomHint(canvas)
  -- Placed on the canvas until the zoom installs and pins them to its view.
  local specs = PinnedSpecs()
  local i
  for i = 1, table.getn(specs) do
    local spec = specs[i]
    local button = string.find(spec.name, "Zoom") and U.G(spec.name)
    if button then
      pcall(button.SetPoint, button, spec.point, canvas, spec.relativePoint,
            spec.x, spec.y)
    end
  end

  -- Ticks only while the map is drawn: a WorldMapFrame child.
  local driver = CreateFrame("Frame", "UnrealUIWorldMapZoomDriver", map)
  driver:SetScript("OnUpdate", Drive)

  if type(U.PostHookScript) == "function" then
    U.PostHookScript(canvas, "OnMouseDown", OnMouseDown)
    -- After the map's own OnUpdate, which redraws the highlight unzoomed.
    U.PostHookScript(canvas, "OnUpdate", CropHighlight)
  end
  WrapMouseUp(canvas)

  -- The catcher covers the canvas rectangle; until the zoom installs its view
  -- it sits over the canvas itself, which is the same rectangle.
  local hud = U.G("UIParent")
  if hud then BuildWheelCatcher(canvas, hud, true) end

  state.mapKey = MapKey()
  U.RegisterEvent("WORLD_MAP_UPDATE", OnMapUpdate)
  if type(U.PostHookGlobal) == "function" then
    U.PostHookGlobal("SetMapToCurrentZone", RecordRecenter)
  end
end
