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
-- A small square whose fill carries the state, plus its own label. The Button's
-- OnEnter/OnLeave own the outline (see U.CreateButton), so state is shown with
-- the fill and never with the border.
-- ---------------------------------------------------------------------------
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
    if control.value then
      U.SetBackgroundColor(box, M.Unpack(M.color.accent))
    else
      U.SetBackgroundColor(box, M.Unpack(M.color.background))
    end
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
  local box = CreateFrame("Frame", options.name and (options.name .. "Value"),
                          parent)
  box:SetWidth(options.boxWidth or 74)
  box:SetHeight(16)
  U.CreateBackdrop(box, {})
  Part(control, box)
  box:SetPoint("TOP", track, "BOTTOM", 0, -2)
  control.box = box

  local readout = U.CreateSettingsLabel(box, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    width = (options.boxWidth or 74) - 6,
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
