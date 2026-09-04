-- unrealUI :: core/style.lua
--
-- Shared visual primitives: backdrops, borders, status bars and labels.
-- pfUI modern is the visual baseline -- near-black panels, one thin dark
-- outline, flat bar fills -- but none of pfUI's structure is reproduced here.

local U = UnrealUI
local M = U.media

-- ---------------------------------------------------------------------------
-- Borders
--
-- knowledge.json / rendering.backdrop_edge_fractional_not_rasterized: the
-- backdrop edgeFile is retained but a fractional edgeSize is not reliably
-- rasterised, so pfUI's thin outlines simply disappear on this client. The
-- background fill is unaffected.
--
-- unrealUI therefore keeps SetBackdrop for the fill only and draws every
-- outline from four plain textures, which behavior.json /
-- textures.pfui_bar_path.v1 verifies as a working drawing path. An outline is
-- never asked to be thinner than one full draw unit, because the sub-unit
-- request is exactly what fails to appear.
--
-- At the recorded 1920-wide display UIParent measures 1365.33 units, so one
-- physical pixel is ~0.71 units. Rounding up to 1 is the deliberate trade:
-- a slightly heavier border that renders beats a hairline that does not.
-- ---------------------------------------------------------------------------
local EDGES = {
  { "TOPLEFT",    "TOPRIGHT",    "horizontal" },
  { "BOTTOMLEFT", "BOTTOMRIGHT", "horizontal" },
  { "TOPLEFT",    "BOTTOMLEFT",  "vertical"   },
  { "TOPRIGHT",   "BOTTOMRIGHT", "vertical"   },
}

function U.BorderSize()
  return 1
end

-- Builds (or resizes) the four outline textures on a frame.
function U.CreateBorder(frame, thickness)
  if not frame or not frame.CreateTexture then return nil end

  thickness = tonumber(thickness) or U.BorderSize()
  if thickness < 1 then thickness = 1 end

  if not frame.uuiEdges then
    local edges, i = {}, nil
    for i = 1, table.getn(EDGES) do
      local anchor = EDGES[i]
      local edge = frame:CreateTexture(nil, "OVERLAY")
      edge:SetTexture(M.texture.plain)
      -- Start dark rather than at the texture's own white, so a frame is never
      -- outlined in white even for the one frame before it is tinted.
      U.SetColor(edge, M.Unpack(M.color.border))
      edge:SetPoint(anchor[1], frame, anchor[1], 0, 0)
      edge:SetPoint(anchor[2], frame, anchor[2], 0, 0)
      edges[i] = edge
    end
    frame.uuiEdges = edges
  end

  local i
  for i = 1, table.getn(EDGES) do
    if EDGES[i][3] == "horizontal" then
      frame.uuiEdges[i]:SetHeight(thickness)
    else
      frame.uuiEdges[i]:SetWidth(thickness)
    end
  end

  return frame.uuiEdges
end

function U.SetBorderColor(frame, r, g, b, a)
  if not frame or not frame.uuiEdges then return end
  local i
  for i = 1, table.getn(frame.uuiEdges) do
    U.SetColor(frame.uuiEdges[i], r, g, b, a)
  end
end

-- ---------------------------------------------------------------------------
-- Backdrops
-- ---------------------------------------------------------------------------

-- Applies the unrealUI panel look to an existing frame: flat fill plus the
-- explicit outline. Returns the frame for chaining.
function U.CreateBackdrop(frame, options)
  if not frame then return frame end
  options = options or {}

  local background = options.background or M.color.background
  local border = options.border or M.color.border

  if frame.SetBackdrop then
    -- Only the fill is taken from the backdrop; edgeFile is deliberately
    -- omitted rather than requested and left invisible.
    local ok = pcall(frame.SetBackdrop, frame, {
      bgFile = M.texture.plain,
      tile = false,
      tileSize = 0,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if ok then
      pcall(frame.SetBackdropColor, frame, M.Unpack(background))
      -- knowledge.json / rendering.setbackdrop_keeps_native_edge_art
      -- (BEHAVIOR_VERIFIED, USER_CONFIRMED_INGAME): a backdrop table that
      -- omits edgeFile replaces the fill but leaves the frame's stock edge
      -- art drawing on top. It is not an enumerable region, so it survives
      -- StripTextures too; only SetBackdropBorderColor removes it.
      pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
    else
      -- No usable backdrop: fall back to a plain fill texture so the panel is
      -- still opaque rather than transparent.
      if not frame.uuiFill and frame.CreateTexture then
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetTexture(M.texture.plain)
        fill:SetAllPoints(frame)
        frame.uuiFill = fill
      end
      U.SetColor(frame.uuiFill, M.Unpack(background))
    end
  end

  if options.border ~= false then
    U.CreateBorder(frame, options.thickness)
    U.SetBorderColor(frame, M.Unpack(border))
  end

  return frame
end

-- Toggles a backdrop built by U.CreateBackdrop between its normal fill/outline
-- and fully invisible, without discarding the regions -- so a caller that
-- wants slots to disappear completely (no fill, no outline) can flip it back
-- on later at the same colors instead of recreating the backdrop.
function U.SetBackdropShown(frame, shown)
  if not frame then return end

  if frame.SetBackdrop and frame.uuiFill == nil then
    if shown then
      pcall(frame.SetBackdropColor, frame, M.Unpack(M.color.background))
    else
      pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
    end
  elseif frame.uuiFill then
    if shown then
      U.SetColor(frame.uuiFill, M.Unpack(M.color.background))
    else
      U.SetColor(frame.uuiFill, 0, 0, 0, 0)
    end
  end

  local i
  for i = 1, table.getn(frame.uuiEdges or {}) do
    if shown then frame.uuiEdges[i]:Show() else frame.uuiEdges[i]:Hide() end
  end
end

function U.SetBackgroundColor(frame, r, g, b, a)
  if not frame then return end
  if frame.uuiFill then
    U.SetColor(frame.uuiFill, r, g, b, a)
    return
  end
  if frame.SetBackdropColor then
    pcall(frame.SetBackdropColor, frame,
          tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 1)
  end
end

-- Creates a new styled panel.
function U.CreatePanel(parent, options)
  local frame = CreateFrame("Frame", (options and options.name) or nil,
                            parent or UIParent)
  frame:SetWidth((options and options.width) or 100)
  frame:SetHeight((options and options.height) or 20)
  return U.CreateBackdrop(frame, options)
end

-- ---------------------------------------------------------------------------
-- Status bars
--
-- Not the client's StatusBar widget. unrealUI's first unit frames built one,
-- created the fill as a texture object and handed it to SetStatusBarTexture,
-- and the result on screen was a fixed green block hanging outside the frame's
-- bounds instead of a bar: the fill kept its creation tint and was not laid out
-- from the bar's value at all.
--
-- UnrealPfUI does not use the widget either. api/ui-widgets.lua builds every
-- bar from a plain frame plus two textures and computes the fill extent itself
-- by re-anchoring the fill's far corner (CreateStatusBar / DisplayValue). That
-- is a working implementation on this client, so unrealUI matches it -- and it
-- only needs plain textures, which behavior.json / textures.pfui_bar_path.v1
-- verifies.
--
-- The object keeps the Vanilla method names (SetMinMaxValues / SetValue /
-- GetValue / GetMinMaxValues / SetOrientation) so callers read like normal bar
-- code. They are unrealUI's own functions on a plain Frame, not overrides of a
-- client widget: a Frame has none of these to begin with.
--
-- knowledge.json / statusbar.native_widget_fill_not_laid_out.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Prediction segments
--
-- Extra fills chained onto the end of the real one, in ElvUI's arrangement:
--
--   horizontal   [ CURRENT HEALTH ][ YOUR HEAL ][ OTHER HEALS ]
--   vertical     the same stack, built upward from the bottom
--
-- Each segment is measured against the bar's own 0 -> max range, exactly as
-- ElvUI's prediction StatusBars are, so a heal worth 20% of maximum health
-- occupies 20% of the bar. The first starts precisely at the right edge of the
-- health fill and the second precisely at the right edge of the first: no gap,
-- no overlap, and no overflow past the bar's end (ElvUI's maxOverflow default
-- of 0, which is also all this bar could draw).
--
-- This is a shared status-bar capability rather than a unit-frame texture
-- because it is pure bar arithmetic -- the same code answers "incoming heal"
-- for a health bar and would answer any other pending-value question -- and
-- because it has to be recomputed by exactly the same paths that move the fill
-- (SetValue, SetMinMaxValues, SetOrientation).
--
-- Nothing is created until a caller asks for a non-zero prediction, so a bar
-- that never predicts costs one nil check per fill update.
-- ---------------------------------------------------------------------------

-- Lays one segment between two extents along the bar, or hides it. Sub-pixel
-- segments are dropped rather than drawn: a heal worth less than a pixel would
-- otherwise flicker a hairline on and off with every tick.
local function PlaceStatusBarSegment(bar, segment, size, from, to)
  if not segment then return end

  if to - from < 1 then
    segment:Hide()
    return
  end

  segment:ClearAllPoints()
  if bar.uuiVertical then
    segment:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(size - to))
    segment:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, from)
  else
    segment:SetPoint("TOPLEFT", bar, "TOPLEFT", from, 0)
    segment:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(size - to), 0)
  end
  segment:Show()
end

local function UpdateStatusBarPrediction(bar)
  local mineSegment = bar.uuiPredictTexture
  local otherSegment = bar.uuiPredictOtherTexture
  if not mineSegment and not otherSegment then return end

  local size
  if bar.uuiVertical then
    size = tonumber(bar:GetHeight())
  else
    size = tonumber(bar:GetWidth())
  end
  size = size or 0

  local range = (bar.uuiMax or 0) - (bar.uuiMin or 0)
  local mine = bar.uuiPredict or 0
  local others = bar.uuiPredictOther or 0

  if range <= 0 or size <= 0 or (mine <= 0 and others <= 0) then
    if mineSegment then mineSegment:Hide() end
    if otherSegment then otherSegment:Hide() end
    return
  end

  local scale = size / range
  local from = scale * ((bar.uuiValue or 0) - (bar.uuiMin or 0))
  if from < 0 then from = 0 end
  if from > size then from = size end

  -- Chained, and both clamped at the bar's end: your heal is drawn first
  -- because it is the one you can still decide not to cast, so an overheal
  -- that is yours is the one that gets squeezed out at the boundary.
  local mineEnd = from + scale * mine
  if mineEnd > size then mineEnd = size end

  local otherEnd = mineEnd + scale * others
  if otherEnd > size then otherEnd = size end

  PlaceStatusBarSegment(bar, mineSegment, size, from, mineEnd)
  PlaceStatusBarSegment(bar, otherSegment, size, mineEnd, otherEnd)
end

local function UpdateStatusBarFill(bar)
  UpdateStatusBarPrediction(bar)

  local fill = bar.uuiFillTexture
  if not fill then return end

  local size
  if bar.uuiVertical then
    size = tonumber(bar:GetHeight())
  else
    size = tonumber(bar:GetWidth())
  end
  size = size or 0

  local range = (bar.uuiMax or 0) - (bar.uuiMin or 0)
  local extent = 0
  if range > 0 and size > 0 then
    extent = size / range * ((bar.uuiValue or 0) - (bar.uuiMin or 0))
  end

  if extent < 0 then extent = 0 end
  if extent > size then extent = size end

  -- A zero-extent texture is hidden rather than left at zero size: a texture
  -- asked for no width is exactly the case that rendered as a stray block.
  if extent <= 0 then
    fill:Hide()
    return
  end

  fill:ClearAllPoints()
  if bar.uuiVertical then
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(size - extent))
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  else
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(size - extent), 0)
  end
  fill:Show()
end

local function BarSetMinMaxValues(self, minimum, maximum)
  minimum = tonumber(minimum) or 0
  maximum = tonumber(maximum) or 0
  if self.uuiMin == minimum and self.uuiMax == maximum then return end
  self.uuiMin = minimum
  self.uuiMax = maximum
  UpdateStatusBarFill(self)
end

local function BarGetMinMaxValues(self)
  return self.uuiMin, self.uuiMax
end

local function BarSetValue(self, value)
  value = tonumber(value) or 0
  if self.uuiValue == value then return end
  self.uuiValue = value
  UpdateStatusBarFill(self)
end

local function BarGetValue(self)
  return self.uuiValue
end

local function BarSetOrientation(self, mode)
  local vertical = (type(mode) == "string" and string.upper(mode) == "VERTICAL")
  if self.uuiVertical == vertical then return end
  self.uuiVertical = vertical
  UpdateStatusBarFill(self)
end

function U.CreateStatusBar(parent, options)
  options = options or {}

  local bar = CreateFrame("Frame", options.name, parent or UIParent)
  bar:SetWidth(options.width or 100)
  bar:SetHeight(options.height or 12)

  -- Background sits behind the fill and shows the depleted portion.
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(M.texture.plain)
  bg:SetAllPoints(bar)
  U.SetColor(bg, M.Unpack(options.background or M.color.healthBg))
  bar.uuiBackground = bg

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(options.texture or M.texture.plain)
  U.SetColor(fill, M.Unpack(options.color or M.color.health))
  bar.uuiFillTexture = fill

  -- Remembered rather than read back off the texture when a prediction segment
  -- needs it: GetTexture is not verified to return the path that was set on
  -- this client, and a segment must never guess its own material.
  bar.uuiTexturePath = options.texture or M.texture.plain

  bar.uuiMin, bar.uuiMax, bar.uuiValue = 0, 1, 1
  bar.uuiVertical = (options.orientation == "VERTICAL")

  bar.SetMinMaxValues = BarSetMinMaxValues
  bar.GetMinMaxValues = BarGetMinMaxValues
  bar.SetValue = BarSetValue
  bar.GetValue = BarGetValue
  bar.SetOrientation = BarSetOrientation

  UpdateStatusBarFill(bar)
  return bar
end

function U.SetStatusBarColor(bar, r, g, b, a)
  if not bar or not bar.uuiFillTexture then return end
  U.SetColor(bar.uuiFillTexture, r, g, b, a)
end

-- The prediction segments follow the fill. A health bar switches material at
-- runtime -- normTex2 for target, party and class colouring, flat otherwise
-- (modules/unitframes.lua, ApplyHealthColor) -- and an incoming-heal band left
-- on the old one would sit flat beside a shaded fill.
function U.SetStatusBarTexture(bar, texture)
  if not bar or not bar.uuiFillTexture then return end

  texture = texture or M.texture.plain
  if bar.uuiTexturePath == texture then return end
  bar.uuiTexturePath = texture

  bar.uuiFillTexture:SetTexture(texture)
  if bar.uuiPredictTexture then
    bar.uuiPredictTexture:SetTexture(texture)
  end
  if bar.uuiPredictOtherTexture then
    bar.uuiPredictOtherTexture:SetTexture(texture)
  end
end

-- OVERLAY, not ARTWORK: the segments never overlap the fill, but a bar whose
-- fill carries a gradient texture must not be able to draw over it if a future
-- caller ever does overlap them.
--
-- The segment is built on the bar's own texture rather than a flat one, which
-- is how ElvUI does it -- its prediction StatusBars take the health bar's
-- statusbar texture, so the incoming band is the same material as the health
-- beside it at a different tint, and the seam between them is a colour change
-- and nothing else. U.SetStatusBarTexture keeps existing segments in step when
-- the bar changes material later.
local function CreateStatusBarSegment(bar, color)
  local segment = bar:CreateTexture(nil, "OVERLAY")
  segment:SetTexture(bar.uuiTexturePath or M.texture.plain)
  U.SetColor(segment, M.Unpack(color))
  segment:Hide()
  return segment
end

-- How far past the current value the bar should show pending change, in the
-- bar's own units: `mine` is drawn first, `others` chained onto its end. Zero
-- (or nil) clears either one. Each segment is created on the first non-zero
-- call and reused after that, so a bar that is asked for zero before it ever
-- predicts stays exactly as cheap as one that has no prediction at all -- and a
-- client that can only ever answer for the player never builds the second
-- texture at all.
function U.SetStatusBarPrediction(bar, mine, others)
  if not bar then return end

  mine = tonumber(mine) or 0
  others = tonumber(others) or 0
  if mine < 0 then mine = 0 end
  if others < 0 then others = 0 end

  local wanted = (mine > 0 or bar.uuiPredictTexture) and true or false
  local wantedOther = (others > 0 or bar.uuiPredictOtherTexture) and true or false
  if not wanted and not wantedOther then return end
  if bar.uuiPredict == mine and bar.uuiPredictOther == others then return end

  bar.uuiPredict = mine
  bar.uuiPredictOther = others

  if mine > 0 and not bar.uuiPredictTexture then
    bar.uuiPredictTexture =
      CreateStatusBarSegment(bar, M.color.healPredictionMine)
  end
  if others > 0 and not bar.uuiPredictOtherTexture then
    bar.uuiPredictOtherTexture =
      CreateStatusBarSegment(bar, M.color.healPredictionOthers)
  end

  UpdateStatusBarPrediction(bar)
end

-- ---------------------------------------------------------------------------
-- Radial wipe
--
-- The clock wipe: a dark quarter that starts covering the whole square and is
-- eaten away clockwise from twelve, clearing exactly at 100%. It is the shared
-- primitive behind the action bar's global-cooldown feedback.
--
-- It is drawn by hand because this client renders nothing from the native
-- shape. knowledge.json / cooldown.model_swipe_not_rendered: CreateFrame(
-- "Model", name, button, "CooldownFrameTemplate") driven by
-- CooldownFrame_SetTimer -- UnrealPfUI's vanilla branch, COOLDOWN_FRAME_TYPE in
-- compat/vanilla.lua -- produces a frame but no wipe, USER_CONFIRMED_INGAME on
-- a live spell cooldown. The client's own action bar does wipe, so it draws
-- that internally rather than through a widget an addon can create.
--
-- The shape: at any moment at most one quadrant is being crossed. The quadrants
-- the sweep has already passed are clear, the ones ahead of it are one flat
-- quad each, and only the quadrant under the leading edge needs detail. That
-- one is filled with a stack of horizontal strips whose widths follow the
-- boundary ray -- the standard way to raise a triangle out of axis-aligned
-- quads, which is all this client gives us: no Cooldown widget, and a wedge
-- needs either a triangular mark or a rotated quad.
--
-- Strips are sized against the quadrant, not the whole square, one unit per
-- step: fine enough that the staircase reads as a straight edge even on a
-- 24-unit aura icon, where the whole quadrant is only 12 units tall and the
-- previous 1.5-unit step (8 strips) was coarse enough to show. The cap is
-- raised alongside it so a full-size action button still gets to use the
-- finer step instead of hitting the old ceiling early.
-- ---------------------------------------------------------------------------
local WIPE_STRIP_MAX = 20
local WIPE_STRIP_UNITS = 1.0
local WIPE_RADIANS = math.pi / 180

-- Work census for the wipe, read by core/perf.lua. A redraw's real cost is the
-- number of texture writes it makes, not the number of calls: the row loop is
-- WIPE_STRIP_MAX long every time, but the width/alpha caches mean most rows
-- write nothing on most ticks, and only a measurement can say how many do.
-- Counting is gated on U.perfActive so an ordinary session pays one boolean
-- read per redraw and nothing else.
local wipeWork = { applies = 0, rows = 0, writes = 0, gradients = 0 }

function U.RadialWipeStats()
  return {
    applies = wipeWork.applies,
    rows = wipeWork.rows,
    writes = wipeWork.writes,
    gradients = wipeWork.gradients,
  }
end

function U.ResetRadialWipeStats()
  wipeWork.applies, wipeWork.rows = 0, 0
  wipeWork.writes, wipeWork.gradients = 0, 0
end

-- The staircase is inherent to drawing a diagonal out of axis-aligned strips,
-- and more rows only shrink the steps, never remove them -- at a 24-unit icon
-- the quadrant is 12 units tall, so 12 strips (one per unit) is already the
-- finest whole-unit row count available, and going finer hits the Borders
-- note above: this client drops fractional sizes rather than rendering them,
-- so a sub-unit strip height would not draw smoother, it would not draw.
--
-- What actually softens a staircase without more rows is antialiasing the
-- edge, and Texture:SetGradientAlpha is a real, BEHAVIOR_VERIFIED primitive
-- here (rendering.setgradientalpha_vertical_origin_top, confirmed in game on
-- the colour picker's saturation/value square). Each strip's free edge -- the
-- one that moves, the actual diagonal boundary -- gets a second texture beyond
-- it that fades from the strip's own colour down to fully transparent. The
-- strip itself stays flat; only this sliver blends, so the fill keeps the
-- flat, no-gloss look rules/unreal-ui-design.md requires.
--
-- The feather's WIDTH and its two end alphas are the whole trick, and a fixed
-- feather is wrong at every angle but one. Within a single row the true edge
-- is not at a point -- it sweeps horizontally by stripHeight * slope between
-- the row's top and bottom. That sweep is the row's partial-coverage band: at
-- its leading end the edge covers none of the row, at its trailing end all of
-- it, and in between the covered fraction rises linearly. A linear alpha ramp
-- spanning exactly that band is therefore not an approximation of
-- antialiasing -- for a straight edge it IS the exact coverage integral, which
-- is what an antialiased edge is.
--
-- Two things follow, and both matter:
--
--   * The band is derived per row from where the edge actually crosses that
--     row, not from a clamped midpoint. A row the edge has already left
--     entirely draws nothing, and a row it has not reached is solid. Clamping
--     a midpoint instead makes every row past the edge draw a phantom band.
--   * Where the band runs off the quadrant, the ramp is cut short, so its
--     stops carry the true coverage at the cut rather than a flat 1 and 0.
--     Without that a near-horizontal edge starts its ramp at solid and the
--     first row reads far too dark.
--
-- WIPE_FEATHER_MIN keeps a near-vertical edge from collapsing to a hard line,
-- matching the sub-unit softness such an edge really has.
local WIPE_FEATHER_MIN = 1

-- Which side of each strip is that free edge, derived from the strip's own
-- anchor corner (WIPE_QUADS column 2, below): an anchor that pins the RIGHT
-- edge leaves the LEFT edge to move, and the other way round.
local WIPE_FREE_SIDE = { "LEFT", "RIGHT", "RIGHT", "LEFT" }

-- Clockwise from twelve. Per quadrant: the corner its flat fill sits in, the
-- strip's own anchor corner, the frame point the strip stack hangs off, and the
-- sign and index shift of that stack's vertical offsets.
--
-- Quadrants 2 and 4 are the mirrored pair. In those the leading edge travels
-- away from the centre, so a strip's dark run is measured from the centre line
-- outwards and its local angle counts down; in 1 and 3 the edge travels towards
-- the centre and both are the other way round. That single flag is the only
-- difference between the four cases.
local WIPE_QUADS = {
  { "TOPRIGHT",    "TOPRIGHT", "RIGHT",   1, 0 },
  { "BOTTOMRIGHT", "TOPLEFT",  "CENTER", -1, 1 },
  { "BOTTOMLEFT",  "TOPLEFT",  "LEFT",   -1, 1 },
  { "TOPLEFT",     "TOPRIGHT", "CENTER",  1, 0 },
}

local function WipeMirrored(quadrant)
  return quadrant == 2 or quadrant == 4
end

-- Re-anchors the strip stack into the quadrant now being crossed. Runs four
-- times per wipe, not once per redraw: within a quadrant the strips keep their
-- rows and only their widths move.
local function MoveWipeStrips(wipe, quadrant)
  if wipe.quadrant == quadrant then return end
  wipe.quadrant = quadrant
  wipe.freeSide = WIPE_FREE_SIDE[quadrant]

  local shape = WIPE_QUADS[quadrant]
  local i
  for i = 1, wipe.stripCount do
    local strip = wipe.strips[i]
    strip:ClearAllPoints()
    strip:SetPoint(shape[2], wipe.frame, shape[3], 0,
                   shape[4] * (i - shape[5]) * wipe.stripHeight)
    wipe.drawn[i] = nil

    -- Anchored to the strip itself, not to the frame: a relative point tracks
    -- the strip's free edge automatically as its width changes every tick, so
    -- no position here is recomputed outside a quadrant change.
    local feather = wipe.feathers[i]
    if feather then
      feather:ClearAllPoints()
      if wipe.freeSide == "LEFT" then
        feather:SetPoint("TOPRIGHT", strip, "TOPLEFT", 0, 0)
      else
        feather:SetPoint("TOPLEFT", strip, "TOPRIGHT", 0, 0)
      end
      wipe.featherDrawn[i] = nil
      wipe.featherAlpha[i] = nil
    end
  end
end

-- The ramp's stops carry the true coverage at each end. Quantised and cached,
-- because only the row or two actually under the leading edge changes its
-- stops on a given tick: this costs a call or two per redraw, not one per row.
local function SetFeatherAlpha(wipe, index, near, far)
  local key = math.floor(near * 64) * 128 + math.floor(far * 64)
  if wipe.featherAlpha[index] == key then return end
  wipe.featherAlpha[index] = key
  if U.perfActive then wipeWork.gradients = wipeWork.gradients + 1 end

  local feather = wipe.feathers[index]
  local r, g, b, a = M.Unpack(wipe.color)
  if wipe.freeSide == "LEFT" then
    -- Outer (transparent) end on the left, the end against the strip on the right.
    pcall(feather.SetGradientAlpha, feather, "HORIZONTAL",
          r, g, b, a * far, r, g, b, a * near)
  else
    pcall(feather.SetGradientAlpha, feather, "HORIZONTAL",
          r, g, b, a * near, r, g, b, a * far)
  end
end

-- Builds and re-sizes the regions for the current geometry. Only ever reached
-- through BuildRadialWipe, i.e. only for a wipe that has actually been asked
-- to draw something.
local function ApplyWipeGeometry(wipe)
  local count = wipe.stripCount
  local half = wipe.half

  local i
  for i = 1, 4 do
    wipe.quads[i]:SetWidth(half)
    wipe.quads[i]:SetHeight(half)
  end

  for i = 1, count do
    if not wipe.strips[i] then
      local strip = wipe.frame:CreateTexture(nil, wipe.layer)
      strip:SetTexture(M.texture.plain)
      U.SetColor(strip, M.Unpack(wipe.color))
      strip:Hide()
      wipe.strips[i] = strip
    end
    wipe.strips[i]:SetHeight(wipe.stripHeight)
    wipe.drawn[i] = nil

    if not wipe.feathers[i] then
      local feather = wipe.frame:CreateTexture(nil, wipe.layer)
      feather:SetTexture(M.texture.plain)
      feather:Hide()
      wipe.feathers[i] = feather
    end
    wipe.feathers[i]:SetHeight(wipe.stripHeight)
    wipe.featherDrawn[i] = nil
    wipe.featherAlpha[i] = nil
  end
  -- A strip left over from a larger size must not keep drawing at the new one.
  for i = count + 1, table.getn(wipe.strips) do
    wipe.strips[i]:Hide()
    wipe.shown[i] = nil
    if wipe.feathers[i] then
      wipe.feathers[i]:Hide()
      wipe.featherShown[i] = nil
    end
  end

  -- Force the next redraw to re-anchor: the rows moved with the size.
  wipe.quadrant = nil
end

-- ---------------------------------------------------------------------------
-- Deferred construction
--
-- A 30-unit wipe is 4 quads + 15 strips + 15 feathers = 34 texture regions,
-- and it used to create all of them the moment its owner was created. On the
-- action bar that is the dominant term in the whole interface's object graph:
-- ten enabled bars are 120 buttons and ~4000 wipe regions, against roughly ten
-- more regions for everything else the button draws.
--
-- Measured, /uui perf bars, 2026-08-31, 26970 frames over 180s: frame time rose
-- from 4.464ms at 0 bars to 11.656ms at 10 in a straight line, ~0.72ms per bar
-- (~0.060ms per visible button), while the Lua actually executed did not scale
-- with it at all -- the GCD sweep touched about 11 buttons per tick at ten bars
-- against 5 at one, because it skips empty slots. The cost tracks the number of
-- regions that exist, not the number the code touches, which is the renderer
-- walking them rather than this file's arithmetic.
--
-- So nothing is created until a wipe is first asked to draw. An empty action
-- slot never sweeps -- ApplyGCDSweep returns on button.uuiEmpty -- so it never
-- builds, and the regions that exist are the ones a player actually put a
-- spell on rather than one per slot on every enabled bar.
local function BuildRadialWipe(wipe)
  if wipe.built then return true end
  if wipe.size <= 0 then return false end

  local i
  for i = 1, 4 do
    local quad = wipe.frame:CreateTexture(nil, wipe.layer)
    quad:SetTexture(M.texture.plain)
    U.SetColor(quad, M.Unpack(wipe.color))
    quad:SetPoint(WIPE_QUADS[i][1], wipe.frame, WIPE_QUADS[i][1], 0, 0)
    quad:Hide()
    wipe.quads[i] = quad
  end

  wipe.built = true
  ApplyWipeGeometry(wipe)
  return true
end

-- Records the geometry for a square of `size`. For a wipe that has never drawn
-- this is arithmetic and nothing else; one that is already built is re-laid out
-- immediately, because its regions are on screen.
function U.SizeRadialWipe(wipe, size)
  if not wipe then return end

  size = tonumber(size) or 0
  if size <= 0 then return end

  local half = size / 2
  local count = U.Round(half / WIPE_STRIP_UNITS)
  if count < 4 then count = 4 end
  if count > WIPE_STRIP_MAX then count = WIPE_STRIP_MAX end

  wipe.size, wipe.half = size, half
  wipe.stripCount = count
  wipe.stripHeight = half / count

  if wipe.built then ApplyWipeGeometry(wipe) end
end

function U.CreateRadialWipe(frame, options)
  if not frame or not frame.CreateTexture then return nil end
  options = options or {}

  local wipe = {
    frame = frame,
    layer = options.layer or "BACKGROUND",
    color = options.color or M.color.cooldownWipe,
    quads = {}, strips = {}, drawn = {}, shown = {}, quadShown = {},
    feathers = {}, featherDrawn = {}, featherShown = {}, featherAlpha = {},
    stripCount = 0, stripHeight = 0, size = 0, half = 0,
    built = false,
  }

  -- Geometry only: see BuildRadialWipe. Creating a wipe is now free, so a
  -- caller may hand one to every button it owns without that being a decision
  -- about how many texture regions the interface carries.
  local okWidth, width = pcall(frame.GetWidth, frame)
  U.SizeRadialWipe(wipe, okWidth and width or options.size)
  return wipe
end

function U.HideRadialWipe(wipe)
  if not wipe or not wipe.built then return end
  local i
  for i = 1, 4 do
    if wipe.quadShown[i] then
      wipe.quads[i]:Hide()
      wipe.quadShown[i] = nil
    end
  end
  for i = 1, table.getn(wipe.strips) do
    if wipe.shown[i] then
      wipe.strips[i]:Hide()
      wipe.shown[i] = nil
    end
    if wipe.featherShown[i] then
      wipe.feathers[i]:Hide()
      wipe.featherShown[i] = nil
    end
  end
end

function U.SetRadialWipeColor(wipe, r, g, b, a)
  if not wipe then return end

  -- Stored first: an unbuilt wipe has no regions to recolour, and the stored
  -- colour is what BuildRadialWipe hands its quads and strips when it runs.
  wipe.color = { r, g, b, a }
  if not wipe.built then return end

  local i
  for i = 1, 4 do U.SetColor(wipe.quads[i], r, g, b, a) end
  for i = 1, table.getn(wipe.strips) do U.SetColor(wipe.strips[i], r, g, b, a) end
  -- The ramps are rebuilt from the new colour on the next redraw rather than
  -- here, so a recolour never has to know which row is under the edge.
  for i = 1, table.getn(wipe.feathers) do wipe.featherAlpha[i] = nil end
end

local function ShowWipeQuad(wipe, index, show)
  if show then
    if not wipe.quadShown[index] then
      wipe.quads[index]:Show()
      wipe.quadShown[index] = true
    end
  elseif wipe.quadShown[index] then
    wipe.quads[index]:Hide()
    wipe.quadShown[index] = nil
  end
end

-- progress is 0..1 of the way through the cooldown, so the dark area is what is
-- left: 0 covers the square, 1 clears it. Widths are rounded to whole draw units
-- and cached -- the sub-unit request that makes fractional borders vanish (see
-- the Borders note at the top of this file) would make the edge flicker, and the
-- cache means a strip the boundary has already left writes nothing at all.
function U.SetRadialWipeProgress(wipe, progress)
  if not wipe or wipe.size <= 0 then return end

  progress = tonumber(progress) or 0
  if progress >= 1 then U.HideRadialWipe(wipe) return end
  if progress < 0 then progress = 0 end

  -- First draw builds the regions. Everything above this line is reachable
  -- without paying for them, which is the point.
  if not BuildRadialWipe(wipe) then return end

  local degrees = progress * 360
  local quadrant = math.floor(degrees / 90) + 1
  if quadrant > 4 then quadrant = 4 end

  local i
  for i = 1, 4 do
    -- Passed quadrants are clear, later ones are solid, and the one under the
    -- leading edge is left to the strips.
    ShowWipeQuad(wipe, i, i > quadrant)
  end

  MoveWipeStrips(wipe, quadrant)

  local mirrored = WipeMirrored(quadrant)
  local phase = degrees - (quadrant - 1) * 90
  if mirrored then phase = 90 - phase end
  local slope = math.tan(phase * WIPE_RADIANS)

  if U.perfActive then
    wipeWork.applies = wipeWork.applies + 1
    wipeWork.rows = wipeWork.rows + wipe.stripCount
  end

  local half = wipe.half
  local limit = math.floor(half)
  local rowHeight = wipe.stripHeight

  -- How far the true edge travels horizontally across one row's height: the
  -- width of that row's partial-coverage band. Zero when the edge is exactly
  -- along the quadrant's own edge, in which case every row is solid or clear.
  local band = rowHeight * slope

  for i = 1, wipe.stripCount do
    -- Distance from the strip's anchored side out to the true edge, taken at
    -- the row's two horizontal boundaries. `near` is where the edge is when it
    -- enters the row and `far` where it leaves, so the row is solid up to
    -- `near`, clear past `far`, and ramps between them.
    local near, far
    if mirrored then
      near = (i - 1) * rowHeight * slope
      far = i * rowHeight * slope
    else
      near = half - i * rowHeight * slope
      far = half - (i - 1) * rowHeight * slope
    end

    local width, feather = 0, 0
    if far > 0 then
      local lo = near < 0 and 0 or near
      if lo > half then lo = half end
      local hi = far > half and half or far

      -- Both ends are rounded to the nearest unit, deliberately, and not
      -- floored/ceiled outward. Widening the ramp past the real transition
      -- forces one straight gradient to stand in for a curve that is flat,
      -- then sloped, then flat -- measurably worse than letting the ramp sit
      -- on the transition itself, where its endpoint alphas make it exact.
      width = math.floor(lo + 0.5)
      feather = math.floor(hi + 0.5) - width

      -- A near-vertical edge crosses well under one unit; keep a single unit
      -- of ramp rather than letting it round away into a hard line.
      if feather < WIPE_FEATHER_MIN and hi < half then
        feather = WIPE_FEATHER_MIN
      end

      -- The feather hangs off the strip's free edge, so it needs a strip to
      -- hang from. A row whose solid part rounds away keeps one unit of it.
      if feather >= 1 and width < 1 then
        width = 1
        feather = feather - 1
      end

      -- Nothing may spill past the frame's own edge: these are plain textures
      -- on the frame and this client offers no clipping to fall back on.
      if width > limit then width = limit end
      if width + feather > limit then feather = limit - width end
      if feather < 0 then feather = 0 end
    end

    if width < 1 then
      if wipe.shown[i] then
        wipe.strips[i]:Hide()
        wipe.shown[i] = nil
      end
      if wipe.featherShown[i] then
        wipe.feathers[i]:Hide()
        wipe.featherShown[i] = nil
      end
    else
      if wipe.drawn[i] ~= width then
        wipe.drawn[i] = width
        wipe.strips[i]:SetWidth(width)
        if U.perfActive then wipeWork.writes = wipeWork.writes + 1 end
      end
      if not wipe.shown[i] then
        wipe.strips[i]:Show()
        wipe.shown[i] = true
      end

      if feather < 1 then
        if wipe.featherShown[i] then
          wipe.feathers[i]:Hide()
          wipe.featherShown[i] = nil
        end
      else
        -- Coverage at the ramp's two ends, read off the same edge geometry
        -- rather than assumed to be a full 1 and 0 -- which they are not when
        -- the quadrant boundary cut the band short.
        local aNear, aFar = 1, 0
        if band > 0 then
          aNear = (far - width) / band
          aFar = (far - width - feather) / band
          if aNear > 1 then aNear = 1 elseif aNear < 0 then aNear = 0 end
          if aFar > 1 then aFar = 1 elseif aFar < 0 then aFar = 0 end
        end
        SetFeatherAlpha(wipe, i, aNear, aFar)

        if wipe.featherDrawn[i] ~= feather then
          wipe.featherDrawn[i] = feather
          wipe.feathers[i]:SetWidth(feather)
          if U.perfActive then wipeWork.writes = wipeWork.writes + 1 end
        end
        if not wipe.featherShown[i] then
          wipe.feathers[i]:Show()
          wipe.featherShown[i] = true
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Text
--
-- knowledge.json / fonts.stretched_justification_ignored: horizontal
-- justification can be ignored on a region stretched between two corners.
-- Labels are therefore anchored to the single edge they belong to; callers
-- should place them with one SetPoint, not two.
-- ---------------------------------------------------------------------------
-- options.inherits names a stock font object to inherit from. It matters when
-- U.ResolveFont finds no path this client will resize: a fontstring created
-- with no template and no working SetFont has no font at all, and inheriting a
-- stock object is the only thing guaranteeing the text appears. The template
-- form is attempted first and dropped if this client rejects the extra
-- argument, since neither shape is verified in the compact DB.
function U.CreateLabel(parent, options)
  if not parent or not parent.CreateFontString then return nil end
  options = options or {}

  local layer = options.layer or "OVERLAY"
  local ok, label = false, nil

  if options.inherits then
    ok, label = pcall(parent.CreateFontString, parent, options.name, layer,
                      options.inherits)
  end

  if not ok or not label then
    ok, label = pcall(parent.CreateFontString, parent, options.name, layer)
  end
  if not ok or not label then return nil end

  U.SetFont(label, options.size or M.fontSize.normal, options.flags,
            options.fontRole)
  if options.shadow == false then
    U.ClearTextShadow(label)
  elseif options.shadowOffset or options.shadowColor then
    U.SetTextShadow(label, options.shadowOffset, options.shadowColor)
  end

  local color = options.color or M.color.text
  pcall(label.SetTextColor, label, M.Unpack(color))

  if options.justify then
    pcall(label.SetJustifyH, label, options.justify)
  end

  -- A FontString with no explicit width grows to the full text width and can
  -- draw beyond its owning panel. Settings widgets pass their available width
  -- through this shared option so both normal words and long, unbroken values
  -- stay inside the interface. UnrealPfUI uses SetNonSpaceWrap on this client;
  -- keep the call guarded because the compact runtime DB has no direct record.
  if options.width then
    pcall(label.SetWidth, label, options.width)
  end
  if options.height then
    pcall(label.SetHeight, label, options.height)
  end
  if options.nonSpaceWrap ~= nil and label.SetNonSpaceWrap then
    pcall(label.SetNonSpaceWrap, label, options.nonSpaceWrap and true or false)
  end

  return label
end

-- ---------------------------------------------------------------------------
-- Buttons
--
-- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
-- accepts SetText without ever showing a FontString, so the label is a region
-- unrealUI creates and owns rather than the Button's own text.
--
-- Button is also the widget type this client is known to route mouse input to
-- (frames.movable_drag_requires_button_handle), so it is used even where a
-- clickable Frame would do in Vanilla.
-- ---------------------------------------------------------------------------
-- This client vertically centres a FontString's glyphs within its own
-- height rather than its cap-height, which sits the text a couple of pixels
-- above true visual centre inside a button. Every button label -- whether
-- unrealUI creates the FontString (U.CreateButton) or reuses a native one
-- (U.StyleStockButton) -- goes through this single offset, so correcting it
-- here re-centres every button label in every UnrealUI interface at once.
U.BUTTON_LABEL_OFFSET_Y = -2

function U.CenterButtonLabel(label, button)
  if not label or not button then return end
  pcall(label.ClearAllPoints, label)
  pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0, U.BUTTON_LABEL_OFFSET_Y)
end

function U.CreateButton(parent, options)
  options = options or {}

  local width = options.width or 100
  local height = options.height or 22

  local button = CreateFrame("Button", options.name, parent or UIParent)
  button:SetWidth(width)
  button:SetHeight(height)
  pcall(button.EnableMouse, button, true)

  U.CreateBackdrop(button, options)

  local label = U.CreateLabel(button, {
    size = options.size or M.fontSize.normal,
    color = options.textColor or M.color.text,
    inherits = "GameFontNormal",
    width = math.max(1, width - 8),
    height = math.max(1, height - 4),
    nonSpaceWrap = true,
  })
  if label then
    U.CenterButtonLabel(label, button)
    label:SetText(options.text or "")
  end
  button.label = label

  -- Closures over `button`, never `this`: scripts.handler_arguments_direct
  -- means the handler argument shape is not guaranteed.
  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(options.hoverBorder or M.color.moverEdge))
  end)
  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(options.border or M.color.border))
  end)

  if type(options.onClick) == "function" then
    button:SetScript("OnClick", options.onClick)
  end

  return button
end

-- ---------------------------------------------------------------------------
-- Stripping stock art
--
-- knowledge.json / rendering.native_texture_strip_requires_alpha and
-- frames.stock_singletons_structure_nonvanilla: stock windows do not reliably
-- expose the regions upstream skins assume, and a texture can survive Hide().
-- Enumerate what is actually there and use the clear + hide + alpha-0 path.
--
-- This is a primitive only. Each stock window still needs its own
-- capability-checked skin; see the native-interface work, not this file.
-- ---------------------------------------------------------------------------
function U.StripTextures(frame, keep)
  if not frame or not frame.GetRegions then return 0 end

  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return 0 end

  local stripped, i = 0, nil
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local isTexture = false
    if region and region.GetObjectType then
      local typeOk, objectType = pcall(region.GetObjectType, region)
      isTexture = typeOk and objectType == "Texture"
    end

    if isTexture and not (keep and keep[region]) then
      U.HideRegion(region)
      stripped = stripped + 1
    end
  end

  return stripped
end
