-- unrealUI :: core/widgets.lua
--
-- Composite controls for the settings panel: sliders, checkboxes, section
-- headings and sidebar rows.
--
-- These sit on top of core/style.lua rather than inside it: style.lua owns the
-- drawing primitives every module uses (backdrop, border, bar, label, button),
-- and this file owns the handful of assembled controls only the settings panel
-- needs. Nothing here is a config framework -- there is no schema, no registry
-- and no data binding. A caller passes a value and an onChange, and owns the
-- state itself.
--
-- Compatibility notes:
--
--   * knowledge.json / scripts.handler_arguments_direct: handler argument shape
--     is not guaranteed on this client, so no handler here reads its arguments
--     or `this`; drag handlers close over locals instead.
--   * The slider's drag thumb is not a native Slider widget: creating one gave
--     no visible or draggable control in-session, so the thumb is a plain
--     Button dragged with the one recipe verified to work on this client
--     (knowledge.json / frames.movable_drag_requires_button_handle; see
--     core/mover.lua's StartDrag/StopDrag for the same StartMoving /
--     StopMovingOrSizing pairing). The value box is a plain readout, not an
--     EditBox: one crashed the client on click (knowledge.json /
--     widgets.editbox_focus_crash).
--   * knowledge.json / rendering.backdrop_edge_fractional_not_rasterized: every
--     line drawn here is a plain texture (behavior.json / textures.pfui_bar_path
--     .v1), never a backdrop edge.
--   * knowledge.json / rendering.parent_alpha_not_propagated: a composite hands
--     back its parts in `uuiParts` so the caller can show and hide each region
--     explicitly instead of relying on the container.

local U = UnrealUI
local M = U.media

-- Safe width for text starting at the left edge of a settings page. The
-- current content area is 496 wide; the spare 12 pixels remain as a permanent
-- right inset. New settings descriptions should use CreateSettingsLabel so
-- future copy and localization cannot escape the panel.
local SETTINGS_TEXT_WIDTH = 484

-- Collects the regions a composite is made of. The settings panel walks this
-- list, so a control that forgets a part would leave it visible on every tab.
local function Part(control, region)
  if not region then return region end
  if not control.uuiParts then control.uuiParts = {} end
  table.insert(control.uuiParts, region)
  return region
end

-- Settings-only text primitive. Unlike the addon-wide CreateLabel helper, it
-- is bounded by default and also wraps long values that contain no spaces.
function U.CreateSettingsLabel(parent, options)
  options = options or {}
  if not options.width then options.width = SETTINGS_TEXT_WIDTH end
  if options.nonSpaceWrap == nil then options.nonSpaceWrap = true end
  if not options.justify then options.justify = "LEFT" end
  return U.CreateLabel(parent, options)
end

-- Settings descriptions always sit five pixels below the control they explain.
-- Keeping the gap here prevents individual settings pages from drifting apart.
function U.AnchorSettingsDescription(label, parent, offsetX)
  if not label or not parent then return end
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", offsetX or 0, -5)
end

-- ---------------------------------------------------------------------------
-- Rules and headings
-- ---------------------------------------------------------------------------

-- A plain horizontal line. Used for the accent rule under the panel title and
-- for the two lines beside a section heading.
function U.CreateRule(parent, options)
  options = options or {}

  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetTexture(M.texture.plain)
  line:SetHeight(options.thickness or U.BorderSize())
  U.SetColor(line, M.Unpack(options.color or M.color.accentDim))
  return line
end

-- The section heading from the reference layout: a centred accent title with a
-- rule running out to each side.
--
-- Returns a control table (not a frame): a heading has nothing to anchor to, so
-- the caller positions the title and the rules follow it.
function U.CreateSectionHeader(parent, options)
  options = options or {}

  local control = {}

  local title = U.CreateSettingsLabel(parent, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    width = options.width or 400,
    height = (options.height or 18),
    justify = "CENTER",
  })
  Part(control, title)
  control.title = title

  if title then
    title:SetPoint("TOP", parent, "TOPLEFT",
                   (options.width or 400) / 2 + (options.x or 0),
                   options.y or 0)
    title:SetText(options.text or "")
  end

  local width = options.width or 400
  local gap = options.gap or 60

  local left = Part(control, U.CreateRule(parent, {}))
  if left then
    left:SetPoint("LEFT", parent, "TOPLEFT", options.x or 0, (options.y or 0) - 7)
    left:SetWidth(width / 2 - gap)
  end

  local right = Part(control, U.CreateRule(parent, {}))
  if right then
    right:SetPoint("RIGHT", parent, "TOPLEFT",
                   (options.x or 0) + width, (options.y or 0) - 7)
    right:SetWidth(width / 2 - gap)
  end

  control.SetText = function(text)
    if title then title:SetText(text or "") end
  end

  return control
end

-- ---------------------------------------------------------------------------
-- Checkbox
--
-- One shared mark for both unrealUI controls and adapted native CheckButtons.
-- The outer square stays neutral; a smaller accent square carries the checked
-- state.  This keeps native check art out of every skinned surface.
-- ---------------------------------------------------------------------------
-- markInset shrinks the accent square for compact hosts (dropdown list rows are
-- half a settings checkbox); it defaults to the settings-checkbox inset.
function U.SetCheckboxIndicator(button, checked, markInset)
  if not button or not button.CreateTexture then return end
  markInset = tonumber(markInset) or 3

  local mask = button.uuiCheckboxMask
  if not mask then
    -- The stock checked art is wider than the visible mark.  This owned fill
    -- sits above it, leaving only the shared outline visible around the edge.
    mask = button:CreateTexture(nil, "OVERLAY")
    mask:SetTexture(M.texture.plain)
    mask:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.uuiCheckboxMask = mask
  end
  U.SetColor(mask, M.Unpack(M.color.background))
  mask:Show()

  local mark = button.uuiCheckboxMark
  if not mark then
    mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(M.texture.plain)
    mark:SetPoint("TOPLEFT", button, "TOPLEFT", markInset, -markInset)
    mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -markInset, markInset)
    button.uuiCheckboxMark = mark
  end

  U.SetColor(mark, M.Unpack(M.color.accent))
  if checked then mark:Show() else mark:Hide() end
end

function U.CreateCheckbox(parent, options)
  options = options or {}

  local size = options.size or 14
  local control = {}

  local box = U.CreateButton(parent, {
    name = options.name,
    text = "",
    width = size,
    height = size,
    onClick = function()
      control.value = not control.value
      control.Apply()
      if type(options.onChange) == "function" then
        options.onChange(control.value)
      end
    end,
  })
  Part(control, box)
  control.box = box

  local label = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = options.textWidth or
            (SETTINGS_TEXT_WIDTH - size - 6),
    height = options.textHeight or size,
  })
  Part(control, label)
  control.label = label

  if label then
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(options.text or "")
  end

  control.Apply = function()
    U.SetBackgroundColor(box, M.Unpack(M.color.background))
    U.SetCheckboxIndicator(box, control.value)
  end

  control.SetValue = function(value)
    control.value = value and true or false
    control.Apply()
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    box:ClearAllPoints()
    box:SetPoint(point, relative, relativePoint, x, y)
  end

  control.SetValue(options.value)
  return control
end

-- ---------------------------------------------------------------------------
-- Color picker
--
-- A small swatch button plus its own label, in the same shape as
-- CreateCheckbox: caller passes a value ({r,g,b,a}) and an onChange, and owns
-- the state. Clicking the swatch opens unrealUI's own RGB dialog.
--
-- The stock ColorPickerFrame is NOT used. It was tried first, following
-- UnrealPfUI modules/gui.lua's working func/cancelFunc/opacityFunc shape, and
-- confirmed broken in-game on this client (knowledge.json /
-- widgets.colorpickerframe_colorselect_surfaces_missing): the dialog's chrome,
-- title and Okay/Cancel draw normally and the wheel and value *thumbs* appear,
-- but the ColorSelect widget's colour-wheel and value-gradient surfaces neither
-- render nor hit-test, so no colour can be chosen. Strata was ruled out -- the
-- picker is above the settings panel and its own chrome is visible.
--
-- This dialog therefore uses only primitives already verified on this client:
-- U.CreateSlider's drag-Button thumb (frames.movable_drag_requires_button_handle)
-- and plain textures (textures.pfui_bar_path.v1). No native colour widget is
-- involved, so nothing here depends on the missing ColorSelect surfaces.
--
-- The saturation/value square and hue strip are unrealUI's own, drawn as plain
-- textures tinted with SetGradientAlpha and driven by the same drag-Button
-- recipe. SetGradientAlpha and GetCursorPosition have no compact-DB record;
-- UnrealPfUI calls both on this client (modules/afkcam.lua, modules/tooltip.lua,
-- api/ui-widgets.lua), which is WORKING_SOURCE only -- and pfUI's own colour
-- picker turned out to be broken here, so neither is trusted blind:
--
--   * every gradient call is pcall'd, and if the client has no SetGradientAlpha
--     the square and strip are hidden outright rather than left blank;
--   * GetCursorPosition only ever supplies click-to-jump, and a reading outside
--     the target's own bounds is discarded;
--   * the R/G/B(/opacity) sliders remain in the dialog and stay in sync, so the
--     picker is fully usable even if nothing above renders at all.
-- ---------------------------------------------------------------------------

-- Vanilla-era Lua: no `%` operator on numbers here, and math.mod's presence is
-- not worth depending on, so the hue wrap is explicit.
local function WrapHue(h)
  while h < 0 do h = h + 360 end
  while h >= 360 do h = h - 360 end
  return h
end

local function Clamp01(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function HSVtoRGB(h, s, v)
  h, s, v = WrapHue(h), Clamp01(s), Clamp01(v)
  if s <= 0 then return v, v, v end

  local sector = h / 60
  local i = math.floor(sector)
  local f = sector - i
  local p = v * (1 - s)
  local q = v * (1 - s * f)
  local t = v * (1 - s * (1 - f))

  if i == 0 then return v, t, p end
  if i == 1 then return q, v, p end
  if i == 2 then return p, v, t end
  if i == 3 then return p, q, v end
  if i == 4 then return t, p, v end
  return v, p, q
end

local function RGBtoHSV(r, g, b)
  r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
  local max = math.max(r, math.max(g, b))
  local min = math.min(r, math.min(g, b))
  local d = max - min

  local h = 0
  if d > 0 then
    if max == r then
      h = (g - b) / d
      if h < 0 then h = h + 6 end
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h * 60
  end

  local s = 0
  if max > 0 then s = d / max end
  return WrapHue(h), s, max
end

local function SetPartsShown(control, show)
  if not control then return end
  if control.uuiParts then
    local i
    for i = 1, table.getn(control.uuiParts) do
      local region = control.uuiParts[i]
      if region then
        if show then region:Show() else region:Hide() end
      end
    end
    return
  end
  if show then control:Show() else control:Hide() end
end

-- Reads a point inside `area` from the cursor, in 0..1 on each axis. Returns
-- nil unless every call succeeded and the result actually lies inside the
-- area, so a client that reports nothing useful simply disables click-to-jump
-- instead of throwing the marker somewhere arbitrary.
local function CursorFraction(area)
  if type(GetCursorPosition) ~= "function" then return nil end

  local ok, cx, cy = pcall(GetCursorPosition)
  if not ok or not tonumber(cx) or not tonumber(cy) then return nil end

  local scaleOk, scale = pcall(area.GetEffectiveScale, area)
  if not scaleOk or not tonumber(scale) or scale <= 0 then return nil end

  local leftOk, left = pcall(area.GetLeft, area)
  local topOk, top = pcall(area.GetTop, area)
  local wOk, w = pcall(area.GetWidth, area)
  local hOk, h = pcall(area.GetHeight, area)
  if not (leftOk and topOk and wOk and hOk) then return nil end
  if not (tonumber(left) and tonumber(top) and tonumber(w) and tonumber(h)) then
    return nil
  end
  if w <= 0 or h <= 0 then return nil end

  local px = cx / scale - left
  local py = top - cy / scale
  -- Outside the area means the reading is not trustworthy for this frame.
  if px < 0 or px > w or py < 0 or py > h then return nil end

  return px / w, py / h
end

-- The drag recipe verified on this client, shared by the square's marker and
-- the hue strip's thumb: a Button (the only widget type that receives
-- OnDragStart here), SetMovable applied immediately before each drag, and a
-- throwaway StartMoving/StopMovingOrSizing pair to collapse multi-point
-- anchors before the real StartMoving. See U.CreateSlider for the same code
-- and knowledge.json / frames.movable_drag_requires_button_handle.
--
-- onMove(fx, fy) receives the marker's position inside `area` as 0..1
-- fractions. It is called live during the drag and once more when it ends;
-- the marker is only re-anchored after the drag stops, because repositioning
-- it mid-drag breaks the drag outright
-- (knowledge.json / widgets.thumb_reposition_during_drag_breaks_drag).
local function AttachDragMarker(area, marker, ticker, onMove)
  -- No `select` here: this client is Vanilla-era Lua and nothing else in
  -- unrealUI uses it, so each read keeps its own ok/value pair.
  local function Measure(object, method)
    local ok, value = pcall(method, object)
    if not ok then return nil end
    return tonumber(value)
  end

  local function ReadFraction()
    local mLeft = Measure(marker, marker.GetLeft)
    local mTop = Measure(marker, marker.GetTop)
    local mW = Measure(marker, marker.GetWidth)
    local mH = Measure(marker, marker.GetHeight)
    local aLeft = Measure(area, area.GetLeft)
    local aTop = Measure(area, area.GetTop)
    local aW = Measure(area, area.GetWidth)
    local aH = Measure(area, area.GetHeight)

    if not (mLeft and mTop and mW and mH and
            aLeft and aTop and aW and aH) then
      return nil
    end
    if aW <= 0 or aH <= 0 then return nil end

    local fx = ((mLeft + mW / 2) - aLeft) / aW
    local fy = (aTop - (mTop - mH / 2)) / aH
    return Clamp01(fx), Clamp01(fy)
  end

  marker:SetScript("OnDragStart", function()
    if not pcall(marker.SetMovable, marker, true) then return end
    if pcall(marker.StartMoving, marker) then
      pcall(marker.StopMovingOrSizing, marker)
    end
    pcall(marker.StartMoving, marker)
    U.RegisterUpdate(ticker, 0, function()
      local fx, fy = ReadFraction()
      if fx then onMove(fx, fy, true) end
    end)
  end)

  marker:SetScript("OnDragStop", function()
    U.UnregisterUpdate(ticker)
    pcall(marker.StopMovingOrSizing, marker)
    local fx, fy = ReadFraction()
    if fx then onMove(fx, fy, false) end
  end)
end

-- One shared dialog serves every colour picker: only one can be open at a
-- time, and the settings panel is rebuilt page by page, so a per-control
-- dialog would leak a frame for every swatch ever shown.
local dialog

local function EnsureColorDialog()
  if dialog then return dialog end

  -- Two columns: the square and hue strip on the left, the numeric sliders on
  -- the right. Both drive the same colour and stay in sync, so the dialog is
  -- still complete if the gradients turn out not to render on this client.
  local DIALOG_WIDTH = 486
  local SLIDER_WIDTH = 200
  local SLIDER_SPACING = 56
  local SQUARE_W, SQUARE_H = 196, 152
  local STRIP_H = 18
  local LEFT_X = 18
  local RIGHT_X = 254

  dialog = U.CreatePanel(UIParent, {
    name = "UnrealUIColorPicker",
    width = DIALOG_WIDTH,
    height = 366,
  })
  -- Above the settings panel, which sits at HIGH (modules/settings.lua).
  pcall(dialog.SetFrameStrata, dialog, "DIALOG")
  pcall(dialog.EnableMouse, dialog, true)
  dialog:Hide()

  U.MakeWindowDraggable("colorpicker", dialog,
                        { headerHeight = 24, headerInset = 0 })

  dialog.title = U.CreateLabel(dialog, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    width = DIALOG_WIDTH - 20,
    height = 16,
    justify = "CENTER",
  })
  if dialog.title then
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -8)
    dialog.title:SetText("Select colour")
  end

  -- Live preview of the colour every control currently describes.
  local preview = CreateFrame("Frame", "UnrealUIColorPickerPreview", dialog)
  preview:SetWidth(SQUARE_W)
  preview:SetHeight(22)
  preview:SetPoint("TOPLEFT", dialog, "TOPLEFT", LEFT_X, -296)
  U.CreateBackdrop(preview, {})
  local previewFill = preview:CreateTexture(nil, "ARTWORK")
  previewFill:SetTexture(M.texture.plain)
  previewFill:SetPoint("TOPLEFT", preview, "TOPLEFT", 2, -2)
  previewFill:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -2, 2)
  dialog.preview = preview
  dialog.previewFill = previewFill

  -- -------------------------------------------------------------------------
  -- Saturation / value square and hue strip
  -- -------------------------------------------------------------------------

  -- Whether this client draws gradients at all. Checked once: if the method is
  -- missing or the first call fails, the whole left column is dropped and the
  -- sliders carry the dialog on their own.
  local gradients = true

  local function Gradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    if not gradients then return false end
    if type(texture.SetGradientAlpha) ~= "function" then
      gradients = false
      return false
    end
    local ok = pcall(texture.SetGradientAlpha, texture, orientation,
                     r1, g1, b1, a1, r2, g2, b2, a2)
    if not ok then gradients = false end
    return ok
  end

  local square = CreateFrame("Frame", "UnrealUIColorPickerSquare", dialog)
  square:SetWidth(SQUARE_W)
  square:SetHeight(SQUARE_H)
  square:SetPoint("TOPLEFT", dialog, "TOPLEFT", LEFT_X, -34)
  U.CreateBackdrop(square, {})
  pcall(square.EnableMouse, square, true)
  dialog.square = square

  -- Three stacked layers make the standard picker face: the flat hue, white
  -- fading out to the right for saturation, then black fading out upward for
  -- value.
  local hueFill = square:CreateTexture(nil, "BACKGROUND")
  hueFill:SetTexture(M.texture.plain)
  hueFill:SetPoint("TOPLEFT", square, "TOPLEFT", 2, -2)
  hueFill:SetPoint("BOTTOMRIGHT", square, "BOTTOMRIGHT", -2, 2)

  local satFill = square:CreateTexture(nil, "ARTWORK")
  satFill:SetTexture(M.texture.plain)
  satFill:SetAllPoints(hueFill)

  local valFill = square:CreateTexture(nil, "OVERLAY")
  valFill:SetTexture(M.texture.plain)
  valFill:SetAllPoints(hueFill)

  U.SetColor(satFill, 1, 1, 1, 1)
  U.SetColor(valFill, 0, 0, 0, 1)
  -- knowledge.json / rendering.setgradientalpha_vertical_origin_top
  -- (USER_CONFIRMED_INGAME): this client anchors the FIRST colour stop at the
  -- top for "VERTICAL", where Vanilla anchors it at the bottom. Both axes here
  -- therefore run from the top-left. The transparent stop is written first so
  -- the black end lands at the bottom; passing them in Vanilla's order drew the
  -- square upside down (dark at the top).
  Gradient(satFill, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
  Gradient(valFill, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 1)

  dialog.squareLayers = { hueFill, satFill, valFill }

  local marker = CreateFrame("Button", "UnrealUIColorPickerMarker", square)
  marker:SetWidth(10)
  marker:SetHeight(10)
  pcall(marker.EnableMouse, marker, true)
  pcall(marker.RegisterForDrag, marker, "LeftButton")
  U.CreateBackdrop(marker, { background = { 0, 0, 0, 0 },
                             border = { 1, 1, 1, 1 } })
  dialog.marker = marker

  local strip = CreateFrame("Frame", "UnrealUIColorPickerHue", dialog)
  strip:SetWidth(SQUARE_W)
  strip:SetHeight(STRIP_H)
  strip:SetPoint("TOPLEFT", dialog, "TOPLEFT", LEFT_X, -34 - SQUARE_H - 8)
  U.CreateBackdrop(strip, {})
  pcall(strip.EnableMouse, strip, true)
  dialog.strip = strip

  -- Six equal segments, each a gradient between two neighbouring pure hues.
  local HUE_STOPS = {
    { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 },
    { 0, 1, 1 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 },
  }
  local segmentWidth = (SQUARE_W - 4) / 6
  dialog.hueSegments = {}
  local s
  for s = 1, 6 do
    local segment = strip:CreateTexture(nil, "ARTWORK")
    segment:SetTexture(M.texture.plain)
    segment:SetWidth(segmentWidth)
    segment:SetPoint("TOPLEFT", strip, "TOPLEFT", 2 + (s - 1) * segmentWidth, -2)
    segment:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT",
                     2 + (s - 1) * segmentWidth, 2)
    local from, to = HUE_STOPS[s], HUE_STOPS[s + 1]
    U.SetColor(segment, from[1], from[2], from[3], 1)
    Gradient(segment, "HORIZONTAL", from[1], from[2], from[3], 1,
             to[1], to[2], to[3], 1)
    table.insert(dialog.hueSegments, segment)
  end

  local hueThumb = CreateFrame("Button", "UnrealUIColorPickerHueThumb", strip)
  hueThumb:SetWidth(8)
  hueThumb:SetHeight(STRIP_H + 6)
  pcall(hueThumb.EnableMouse, hueThumb, true)
  pcall(hueThumb.RegisterForDrag, hueThumb, "LeftButton")
  U.CreateBackdrop(hueThumb, { background = { 0, 0, 0, 0 },
                               border = { 1, 1, 1, 1 } })
  dialog.hueThumb = hueThumb

  -- -------------------------------------------------------------------------
  -- Shared state
  --
  -- Hue/saturation/value is the dialog's working representation: RGB alone
  -- cannot express "same hue, no saturation", so dragging into a grey corner
  -- and back out would otherwise lose the hue the user had chosen.
  -- -------------------------------------------------------------------------
  dialog.hsv = { h = 0, s = 0, v = 1 }

  local syncing = false

  local function PlaceMarkers()
    local w = SQUARE_W - 4
    local h = SQUARE_H - 4
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", square, "TOPLEFT",
                    2 + dialog.hsv.s * w,
                    -2 - (1 - dialog.hsv.v) * h)

    hueThumb:ClearAllPoints()
    hueThumb:SetPoint("CENTER", strip, "TOPLEFT",
                      2 + (dialog.hsv.h / 360) * (SQUARE_W - 4), -STRIP_H / 2)
  end

  local function PaintSquareHue()
    local r, g, b = HSVtoRGB(dialog.hsv.h, 1, 1)
    U.SetColor(hueFill, r, g, b, 1)
  end

  local function UpdatePreview()
    local v = dialog.current or {}
    U.SetColor(previewFill, v.r or 1, v.g or 1, v.b or 1, v.a or 1)
  end
  dialog.UpdatePreview = UpdatePreview

  -- Pushes the current colour outward: preview, the owning control, and
  -- (unless it was the source of the change) the numeric sliders.
  local function Publish(skipSliders)
    if not dialog.current then return end
    UpdatePreview()
    if dialog.onPreview then dialog.onPreview(dialog.current) end

    if not skipSliders and dialog.sliders then
      syncing = true
      dialog.sliders.r.SetValue(math.floor(dialog.current.r * 255 + 0.5))
      dialog.sliders.g.SetValue(math.floor(dialog.current.g * 255 + 0.5))
      dialog.sliders.b.SetValue(math.floor(dialog.current.b * 255 + 0.5))
      syncing = false
    end
  end

  -- Called by the square and the hue strip: HSV is authoritative, RGB derived.
  local function ApplyHSV(skipMarkers)
    if not dialog.current then return end
    local r, g, b = HSVtoRGB(dialog.hsv.h, dialog.hsv.s, dialog.hsv.v)
    dialog.current.r, dialog.current.g, dialog.current.b = r, g, b
    PaintSquareHue()
    if not skipMarkers then PlaceMarkers() end
    Publish(false)
  end
  dialog.ApplyHSV = ApplyHSV

  -- Called by the sliders: RGB is authoritative, HSV re-derived so the markers
  -- follow. Value/saturation of zero carry no hue, so the previous hue is kept
  -- rather than snapped back to red.
  local function AdoptRGB()
    local h, sat, val = RGBtoHSV(dialog.current.r, dialog.current.g,
                                 dialog.current.b)
    if sat > 0 then dialog.hsv.h = h end
    dialog.hsv.s, dialog.hsv.v = sat, val
    PaintSquareHue()
    PlaceMarkers()
  end
  dialog.AdoptRGB = AdoptRGB

  AttachDragMarker(square, marker, "colorpicker.square",
    function(fx, fy, dragging)
      dialog.hsv.s = Clamp01(fx)
      dialog.hsv.v = Clamp01(1 - fy)
      -- Mid-drag the marker must not be re-anchored, or the drag stops
      -- tracking (widgets.thumb_reposition_during_drag_breaks_drag).
      ApplyHSV(dragging)
    end)

  AttachDragMarker(strip, hueThumb, "colorpicker.hue",
    function(fx, fy, dragging)
      dialog.hsv.h = Clamp01(fx) * 360
      ApplyHSV(dragging)
    end)

  -- Click-to-jump. Only an enhancement: CursorFraction returns nil whenever
  -- the reading cannot be trusted, and then the drag handles remain the way to
  -- choose a colour.
  square:SetScript("OnMouseDown", function()
    local fx, fy = CursorFraction(square)
    if not fx then return end
    dialog.hsv.s, dialog.hsv.v = Clamp01(fx), Clamp01(1 - fy)
    ApplyHSV(false)
  end)

  strip:SetScript("OnMouseDown", function()
    local fx = CursorFraction(strip)
    if not fx then return end
    dialog.hsv.h = Clamp01(fx) * 360
    ApplyHSV(false)
  end)

  -- Channels are 0-255 in the UI and 0-1 in storage: the slider's readout is
  -- the only numeric feedback there is (its value box is display-only), and
  -- 0-255 keeps that readable where 0-1 would need decimals the step cannot
  -- express.
  local CHANNELS = { { "r", "Red" }, { "g", "Green" }, { "b", "Blue" },
                     { "a", "Opacity" } }

  dialog.sliders = {}
  local i
  for i = 1, table.getn(CHANNELS) do
    local key = CHANNELS[i][1]
    local slider = U.CreateSlider(dialog, {
      name = "UnrealUIColorPicker" .. string.upper(key),
      text = CHANNELS[i][2],
      width = SLIDER_WIDTH,
      min = 0,
      max = 255,
      step = 1,
      value = 255,
      onChange = function(value)
        -- Ignore the echo from Publish's own SetValue calls.
        if syncing or not dialog.current then return end
        dialog.current[key] = value / 255
        if key ~= "a" then AdoptRGB() end
        Publish(true)
      end,
    })
    slider.SetPoint("TOPLEFT", dialog, "TOPLEFT", RIGHT_X,
                    -52 - (i - 1) * SLIDER_SPACING)
    dialog.sliders[key] = slider
  end

  -- Decided after every layer has been built, so a client with no gradient
  -- support loses the square and strip instead of showing three flat blocks.
  dialog.gradients = gradients

  -- Two layouts, because the sliders are anchored to the right column and
  -- would fall outside the frame if it were simply narrowed. `channels` is how
  -- many sliders are actually on screen, which sets the height of the
  -- slider-only form.
  dialog.Relayout = function(useGradients, channels)
    local order = { "r", "g", "b", "a" }
    local n

    if useGradients then
      dialog:SetWidth(DIALOG_WIDTH)
      dialog:SetHeight(366)
      preview:ClearAllPoints()
      preview:SetPoint("TOPLEFT", dialog, "TOPLEFT", LEFT_X, -296)
      preview:SetWidth(SQUARE_W)
      for n = 1, 4 do
        dialog.sliders[order[n]].SetPoint("TOPLEFT", dialog, "TOPLEFT",
                                          RIGHT_X, -52 - (n - 1) * SLIDER_SPACING)
      end
      return
    end

    dialog:SetWidth(SLIDER_WIDTH + 52)
    dialog:SetHeight(74 + channels * SLIDER_SPACING + 44)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", dialog, "TOPLEFT", 26, -28)
    preview:SetWidth(SLIDER_WIDTH)
    for n = 1, 4 do
      dialog.sliders[order[n]].SetPoint("TOPLEFT", dialog, "TOPLEFT",
                                        26, -74 - (n - 1) * SLIDER_SPACING)
    end
  end

  local accept = U.CreateButton(dialog, {
    name = "UnrealUIColorPickerOkay",
    text = "Okay",
    width = 100,
    height = 22,
    onClick = function() U.CloseColorPicker(true) end,
  })
  accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -124, 14)
  dialog.accept = accept

  local cancel = U.CreateButton(dialog, {
    name = "UnrealUIColorPickerCancel",
    text = "Cancel",
    width = 100,
    height = 22,
    onClick = function() U.CloseColorPicker(false) end,
  })
  cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
  dialog.cancel = cancel

  dialog.SLIDER_SPACING = SLIDER_SPACING
  return dialog
end

-- Closes the shared dialog. accept=false restores the colour the owning
-- control had when it was opened, so Cancel undoes every live preview.
function U.CloseColorPicker(accept)
  if not dialog or not dialog:IsShown() then return end

  local finish = dialog.onFinish
  local start = dialog.start
  local current = dialog.current

  dialog.onFinish, dialog.onPreview = nil, nil
  dialog.start, dialog.current = nil, nil
  dialog:Hide()

  if type(finish) == "function" then
    if accept then finish(current, true) else finish(start, false) end
  end
end

function U.CreateColorPicker(parent, options)
  options = options or {}

  local size = options.size or 16
  local control = {}

  local swatch = CreateFrame("Button", options.name, parent)
  swatch:SetWidth(size)
  swatch:SetHeight(size)
  pcall(swatch.EnableMouse, swatch, true)
  U.CreateBackdrop(swatch, {})
  Part(control, swatch)
  control.swatch = swatch

  local preview = swatch:CreateTexture(nil, "ARTWORK")
  preview:SetTexture(M.texture.plain)
  preview:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
  preview:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
  control.preview = preview

  local label = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = options.textWidth or (SETTINGS_TEXT_WIDTH - size - 6),
    height = options.textHeight or size,
  })
  Part(control, label)
  control.label = label
  if label then
    label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    label:SetText(options.text or "")
  end

  control.value = { r = 1, g = 1, b = 1, a = 1 }
  control.hasOpacity = options.hasOpacity ~= false

  local function ApplyPreview()
    U.SetColor(preview, control.value.r, control.value.g, control.value.b,
               control.value.a)
  end

  local function Publish(color, notify)
    control.value = {
      r = tonumber(color.r) or 1,
      g = tonumber(color.g) or 1,
      b = tonumber(color.b) or 1,
      a = tonumber(color.a) or 1,
    }
    ApplyPreview()
    if notify and type(options.onChange) == "function" then
      options.onChange(control.value)
    end
  end

  control.SetValue = function(value)
    if type(value) == "table" then
      control.value = {
        r = tonumber(value.r) or 1,
        g = tonumber(value.g) or 1,
        b = tonumber(value.b) or 1,
        a = tonumber(value.a) or 1,
      }
    end
    ApplyPreview()
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    swatch:ClearAllPoints()
    swatch:SetPoint(point, relative, relativePoint, x, y)
  end

  -- Closes over `control`/`options`, never `this`
  -- (scripts.handler_arguments_direct).
  swatch:SetScript("OnClick", function()
    -- Whatever the dialog was previously editing is finished first, so its
    -- callbacks can never outlive the control that installed them.
    U.CloseColorPicker(false)

    local d = EnsureColorDialog()
    local start = control.value

    d.start = { r = start.r, g = start.g, b = start.b, a = start.a }
    d.current = { r = start.r, g = start.g, b = start.b, a = start.a }
    d.onPreview = function(color) Publish(color, true) end
    d.onFinish = function(color) Publish(color, true) end

    if d.title then d.title:SetText(options.text or "Select colour") end

    -- Every region is shown by hand: knowledge.json /
    -- rendering.parent_alpha_not_propagated means a container's visibility
    -- does not reliably reach its children.
    local channels = { "r", "g", "b" }
    local i
    for i = 1, table.getn(channels) do
      local key = channels[i]
      d.sliders[key].SetValue(math.floor((start[key] or 0) * 255 + 0.5))
      SetPartsShown(d.sliders[key], true)
    end

    -- The opacity slider only appears when the caller asked for it.
    if control.hasOpacity then
      d.sliders.a.SetValue(math.floor((start.a or 1) * 255 + 0.5))
      SetPartsShown(d.sliders.a, true)
    else
      SetPartsShown(d.sliders.a, false)
    end

    -- HSV is seeded from the incoming colour so the marker starts where the
    -- current colour actually is.
    d.AdoptRGB()

    if d.gradients then
      d.square:Show()
      d.strip:Show()
      d.marker:Show()
      d.hueThumb:Show()
      for i = 1, table.getn(d.squareLayers) do d.squareLayers[i]:Show() end
      for i = 1, table.getn(d.hueSegments) do d.hueSegments[i]:Show() end
    else
      -- No gradient support: drop the left column entirely rather than show
      -- three flat blocks.
      d.square:Hide()
      d.strip:Hide()
      d.marker:Hide()
      d.hueThumb:Hide()
      for i = 1, table.getn(d.squareLayers) do d.squareLayers[i]:Hide() end
      for i = 1, table.getn(d.hueSegments) do d.hueSegments[i]:Hide() end
    end

    d.Relayout(d.gradients, control.hasOpacity and 4 or 3)

    -- Chrome is shown by hand for the same reason the sliders are.
    if d.title then d.title:Show() end
    d.preview:Show()
    d.previewFill:Show()
    d.accept:Show()
    d.cancel:Show()

    d.UpdatePreview()
    d:ClearAllPoints()
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    d:Show()
  end)

  control.SetValue(options.value)
  return control
end

-- ---------------------------------------------------------------------------
-- Slider
--
-- The horizontal control from the reference layout: a caption above, a track
-- with a draggable Button thumb, the minimum on the left, the maximum on the
-- right and the current value in a readout box between them. The box is
-- display-only -- an editable EditBox crashed this client on click (see the
-- value-box comment below), so the thumb drag is the only way to change the
-- value.
--
-- Shared, addon-wide control: any settings page reuses this exact bar by
-- calling U.CreateSlider(parent, {...}) the same way modules/actionbarconfig.lua
-- does; it owns no state of its own beyond the current display value.
-- ---------------------------------------------------------------------------
function U.CreateSlider(parent, options)
  options = options or {}

  local width = options.width or 200
  local min = tonumber(options.min) or 0
  local max = tonumber(options.max) or 100
  local step = tonumber(options.step) or 1

  local control = { min = min, max = max, step = step }

  -- Caption, in the accent colour, above the track.
  local caption = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    width = width,
    height = 14,
  })
  Part(control, caption)
  control.caption = caption
  if caption then caption:SetText(options.text or "") end

  -- The track is a frame so the thumb has something to sit on that is not the
  -- slider's own (non-rasterising) backdrop edge.
  local track = CreateFrame("Frame", options.name and (options.name .. "Track"),
                            parent)
  track:SetWidth(width)
  track:SetHeight(8)
  U.CreateBackdrop(track, {})
  Part(control, track)
  control.track = track

  local function Clamp(raw)
    raw = tonumber(raw)
    if not raw then return min end
    -- Values are snapped to the step so a drag or a typed number cannot store
    -- 11.3 buttons.
    raw = math.floor((raw - min) / step + 0.5) * step + min
    if raw < min then raw = min end
    if raw > max then raw = max end
    return raw
  end

  -- Drag thumb. A native Slider widget produced no visible or draggable
  -- control in-session, so this reuses core/mover.lua's proven drag recipe
  -- instead: a Button (the only widget type this client delivers OnDragStart
  -- to), RegisterForDrag, SetMovable immediately before each drag, and a
  -- throwaway StartMoving/StopMovingOrSizing pair before the real StartMoving.
  --
  -- The client moves the thumb freely rather than constraining it to the
  -- track, so OnDragStop reads its dropped position back and snaps it onto
  -- the track at the nearest valid value; GetLeft/GetWidth have no compact
  -- record either way, so the readback is pcall'd and a failed read just
  -- snaps the thumb back to the current value instead of leaving it adrift.
  local THUMB_WIDTH, THUMB_HEIGHT = 12, 14

  local thumb = CreateFrame("Button", options.name and (options.name .. "Thumb"),
                            track)
  thumb:SetWidth(THUMB_WIDTH)
  thumb:SetHeight(THUMB_HEIGHT)
  pcall(thumb.EnableMouse, thumb, true)
  pcall(thumb.RegisterForDrag, thumb, "LeftButton")
  U.CreateBackdrop(thumb, { background = M.color.accent, border = M.color.border })
  Part(control, thumb)
  control.thumb = thumb

  thumb:SetScript("OnEnter", function()
    U.SetBorderColor(thumb, M.Unpack(M.color.moverEdge))
  end)
  thumb:SetScript("OnLeave", function()
    U.SetBorderColor(thumb, M.Unpack(M.color.border))
  end)

  local function PlaceThumb(value)
    local usable = width - THUMB_WIDTH
    local offset = 0
    if max > min and usable > 0 then
      offset = (Clamp(value) - min) / (max - min) * usable
    end
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", track, "LEFT", offset, 0)
  end

  -- Minimum / maximum captions, anchored to the single edge each belongs to
  -- (fonts.stretched_justification_ignored).
  local minLabel = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    width = width / 2,
    height = 12,
  })
  Part(control, minLabel)
  if minLabel then
    minLabel:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
    minLabel:SetText(tostring(min))
  end

  local maxLabel = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    width = width / 2,
    height = 12,
    justify = "RIGHT",
  })
  Part(control, maxLabel)
  if maxLabel then
    maxLabel:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)
    maxLabel:SetText(tostring(max))
  end

  -- Value box. A plain readout, not an editable field: an EditBox here
  -- crashed the client on click even stripped down to only the calls
  -- modules/bags.lua's own EditBox search box also used (knowledge.json /
  -- widgets.editbox_focus_crash), so this control does not create one at all.
  -- The thumb drag is the only way to change the value; this box just shows
  -- the current one.
  local boxWidth = options.boxWidth or 74
  local box = CreateFrame("Frame", options.name and (options.name .. "Value"),
                          parent)
  box:SetWidth(boxWidth)
  box:SetHeight(16)
  U.CreateBackdrop(box, {})
  Part(control, box)
  box:SetPoint("TOP", track, "BOTTOM", 0, -2)
  control.box = box
  control.width = width
  control.boxWidth = boxWidth

  local readout = U.CreateSettingsLabel(box, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    width = boxWidth - 6,
    height = 14,
    justify = "CENTER",
  })
  Part(control, readout)
  if readout then readout:SetPoint("CENTER", box, "CENTER", 0, 0) end
  control.readout = readout

  -- Sets the displayed value without touching the thumb's anchor. Split out
  -- from Publish because re-anchoring the thumb (PlaceThumb) while a native
  -- drag is in progress was tried and confirmed to break the drag outright
  -- (knowledge.json / widgets.thumb_reposition_during_drag_breaks_drag) --
  -- calling SetPoint on a frame mid-StartMoving stops the client from
  -- tracking further mouse movement. The live per-tick readout below must
  -- therefore only read the thumb's position, never write it.
  local function UpdateReadout(raw)
    local clamped = Clamp(raw)
    control.current = clamped
    if readout then readout:SetText(tostring(clamped)) end
    return clamped
  end

  local function Publish(raw, silent)
    local clamped = UpdateReadout(raw)
    PlaceThumb(clamped)

    if not silent and type(options.onChange) == "function" then
      options.onChange(clamped)
    end
    return clamped
  end

  -- Converts the thumb's own on-screen position back to a value. GetLeft/
  -- GetWidth have no compact record either way, so every call is pcall'd; a
  -- failed read returns nil and the caller falls back to the last known value
  -- instead of guessing one.
  local function ReadThumbValue()
    local leftOk, thumbLeft = pcall(thumb.GetLeft, thumb)
    local trackOk, trackLeft = pcall(track.GetLeft, track)
    local widthOk, trackWidth = pcall(track.GetWidth, track)
    if not (leftOk and trackOk and widthOk and tonumber(thumbLeft) and
            tonumber(trackLeft) and tonumber(trackWidth)) then
      return nil
    end

    local usable = trackWidth - THUMB_WIDTH
    if usable <= 0 then return nil end

    local offset = thumbLeft - trackLeft
    if offset < 0 then offset = 0 end
    if offset > usable then offset = usable end

    return min + offset / usable * (max - min)
  end

  -- The native drag moves the thumb freely in both axes and there is no
  -- verified cursor-position API to build a constrained drag from scratch, so
  -- the Y axis cannot be locked live -- it can only be corrected once the
  -- drag ends (below). While dragging, this only reads the thumb's position
  -- back and updates the readout so the number tracks the drag live; it never
  -- repositions the thumb. Runs on the shared driver (core/init.lua's
  -- U.RegisterUpdate) instead of an OnUpdate on the thumb itself, per
  -- knowledge.json / scripts.child_onupdate_unreliable.
  local dragTicker = "slider." .. (options.name or tostring(thumb))

  local function LiveReadoutFromDrag()
    local value = ReadThumbValue()
    if value then UpdateReadout(value) end
  end

  thumb:SetScript("OnDragStart", function()
    if not pcall(thumb.SetMovable, thumb, true) then return end
    -- Collapses whatever multi-point anchor the thumb currently has down to
    -- the single point the client will actually move, then starts the real
    -- drag -- the same throwaway pair core/mover.lua's StartDrag uses.
    if pcall(thumb.StartMoving, thumb) then
      pcall(thumb.StopMovingOrSizing, thumb)
    end
    pcall(thumb.StartMoving, thumb)
    U.RegisterUpdate(dragTicker, 0, LiveReadoutFromDrag)
  end)

  thumb:SetScript("OnDragStop", function()
    U.UnregisterUpdate(dragTicker)
    pcall(thumb.StopMovingOrSizing, thumb)

    -- Only now is the thumb's anchor touched: this reads the final dropped
    -- position and snaps the thumb onto the track (clamped X, locked Y),
    -- which is also where the axis lock actually takes effect.
    local value = ReadThumbValue()
    if value then
      Publish(value)
    else
      -- Position could not be read back; snap to the last known value rather
      -- than leave the thumb wherever the client dropped it.
      PlaceThumb(control.current or min)
    end
  end)

  -- Public surface. SetValue is silent: the settings panel calls it while
  -- populating a page and must not fire onChange back into itself.
  control.SetValue = function(raw)
    Publish(raw, true)
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    track:ClearAllPoints()
    track:SetPoint(point, relative, relativePoint, x, y)
    if caption then
      caption:ClearAllPoints()
      caption:SetPoint("BOTTOMLEFT", track, "TOPLEFT", 0, 4)
    end
  end

  control.SetValue(options.value or min)
  return control
end
