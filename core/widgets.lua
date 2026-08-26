-- unrealUI :: core/widgets.lua
--
-- Composite controls for the settings panel: sliders, checkboxes, radio
-- groups, dropdowns, section headings and sidebar rows.
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
-- Radio group
--
-- A compact mutually-exclusive selector built from the same flat primitives
-- as the settings checkbox. Disabled entries remain visible with dim text but
-- do not receive mouse input; this is used for choices that explain planned
-- functionality without pretending it is available.
--
-- options: name, value, width, rowHeight, gap, columns, columnGap, rowGap,
--          items = { { value, text, disabled }, ... }, onChange(value)
-- ---------------------------------------------------------------------------
function U.CreateRadioGroup(parent, options)
  options = options or {}

  local control = { rows = {}, uuiParts = {} }
  local items = options.items or {}
  local width = options.width or 220
  local rowHeight = options.rowHeight or 18
  local gap = options.gap or 3
  local columns = math.floor(tonumber(options.columns) or 1)
  if columns < 1 then columns = 1 end
  local columnGap = options.columnGap or gap
  local rowGap = options.rowGap or gap
  local indicatorSize = options.indicatorSize or 14

  local function ApplyRow(row)
    local selected = row.item.value == control.value
    local disabled = row.item.disabled and true or false

    if selected then
      U.SetBackgroundColor(row, M.Unpack(M.color.accentFill))
      U.SetBorderColor(row.indicator, M.Unpack(M.color.accent))
      row.mark:Show()
    else
      U.SetBackgroundColor(row, 0, 0, 0, 0)
      U.SetBorderColor(row.indicator, M.Unpack(M.color.border))
      row.mark:Hide()
    end

    if row.label then
      local color = disabled and M.color.textDim or
                    (selected and M.color.accent or M.color.text)
      pcall(row.label.SetTextColor, row.label, M.Unpack(color))
    end

    -- Button:EnableMouse is the verified input gate used throughout unrealUI;
    -- the disabled path therefore cannot reach its click closure at all.
    pcall(row.EnableMouse, row, not disabled)
  end

  control.Apply = function()
    local i
    for i = 1, table.getn(control.rows) do ApplyRow(control.rows[i]) end
  end

  control.SetValue = function(value, notify)
    local selected
    local i
    for i = 1, table.getn(items) do
      if items[i].value == value and not items[i].disabled then
        selected = value
        break
      end
    end
    if selected == nil then return false end

    local changed = control.value ~= selected
    control.value = selected
    control.Apply()
    if changed and notify and type(options.onChange) == "function" then
      options.onChange(selected)
    end
    return true
  end

  control.GetValue = function()
    return control.value
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    local first = control.rows[1]
    if not first then return end
    first:ClearAllPoints()
    first:SetPoint(point, relative, relativePoint, x, y)
  end

  local i
  for i = 1, table.getn(items) do
    local item = items[i]
    local row = U.CreateButton(parent, {
      name = options.name and (options.name .. i) or nil,
      text = item.text or tostring(item.value or ""),
      width = width,
      height = rowHeight,
      border = false,
    })
    row.item = item
    table.insert(control.rows, row)
    table.insert(control.uuiParts, row)

    -- The row itself is the hit target; this inset frame only draws the common
    -- square selection mark and owns no interaction state.
    local indicator = U.CreatePanel(row, {
      width = indicatorSize,
      height = indicatorSize,
      background = M.color.background,
    })
    indicator:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.indicator = indicator

    local mark = indicator:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(M.texture.plain)
    mark:SetPoint("TOPLEFT", indicator, "TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", -4, 4)
    U.SetColor(mark, M.Unpack(M.color.accent))
    row.mark = mark

    if row.label then
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", indicator, "RIGHT", 6, -1)
      pcall(row.label.SetWidth, row.label, width - indicatorSize - 6)
      pcall(row.label.SetJustifyH, row.label, "LEFT")
    end

    -- A radio row has no outer box; hover and selection are carried by its
    -- subdued fill while the inset square keeps the visible outline.
    U.SetBorderColor(row, 0, 0, 0, 0)
    row:SetScript("OnEnter", function()
      if row.item.value ~= control.value then
        U.SetBackgroundColor(row, 1, 1, 1, 0.07)
      end
    end)
    row:SetScript("OnLeave", function()
      ApplyRow(row)
    end)
    row:SetScript("OnClick", function()
      control.SetValue(row.item.value, true)
    end)

    if i > 1 then
      -- Derive the column from the row so this shared component does not add a
      -- dependency on either Lua's version-specific `%` operator or math.mod.
      local gridRow = math.floor((i - 1) / columns)
      local column = (i - 1) - gridRow * columns
      if column > 0 then
        row:SetPoint("TOPLEFT", control.rows[i - 1], "TOPRIGHT", columnGap, 0)
      else
        row:SetPoint("TOPLEFT", control.rows[i - columns], "BOTTOMLEFT", 0,
                     -rowGap)
      end
    end
  end

  control.firstRow = control.rows[1]
  control.lastRow = control.rows[table.getn(control.rows)]

  if not control.SetValue(options.value, false) then
    for i = 1, table.getn(items) do
      if not items[i].disabled then
        control.SetValue(items[i].value, false)
        break
      end
    end
  end

  return control
end

-- ---------------------------------------------------------------------------
-- Dropdown
--
-- An owned dropdown for addon settings. Native dropdowns continue to use the
-- adapter in core/dropdown.lua; new UnrealUI controls use this flat component
-- so no stock template art or shared native popup state can leak into them.
-- ---------------------------------------------------------------------------
local activeDropdown

local function SetDropdownPartShown(region, shown)
  if not region then return end
  if shown then region:Show() else region:Hide() end
  U.SetBackdropShown(region, shown)
  if region.label then
    if shown then region.label:Show() else region.label:Hide() end
  end
end

function U.CreateDropdown(parent, options)
  options = options or {}

  local control = { rows = {}, uuiParts = {} }
  local items = options.items or {}
  local width = options.width or 220
  local height = options.height or 28
  local rowHeight = options.rowHeight or 22

  local button = U.CreateButton(parent, {
    name = options.name,
    text = "",
    width = width,
    height = height,
  })
  control.button = button

  if button.label then
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 8, U.BUTTON_LABEL_OFFSET_Y)
    pcall(button.label.SetWidth, button.label, width - 30)
    pcall(button.label.SetJustifyH, button.label, "LEFT")
  end

  local arrow = U.CreateLabel(button, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    width = 14,
    height = height - 4,
    justify = "CENTER",
  })
  if arrow then
    arrow:SetPoint("RIGHT", button, "RIGHT", -5, U.BUTTON_LABEL_OFFSET_Y)
    arrow:SetText("v")
  end
  control.arrow = arrow

  local menuHeight = table.getn(items) * rowHeight + 2
  local menuBackground = { 0.03, 0.03, 0.03, 0.98 }
  local menu = U.CreatePanel(parent, {
    width = width,
    height = menuHeight,
    background = menuBackground,
  })
  menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
  local levelOk, level = pcall(button.GetFrameLevel, button)
  if levelOk and tonumber(level) then
    pcall(menu.SetFrameLevel, menu, level + 40)
  end
  control.menu = menu

  local function SetPopupShown(shown)
    control.open = shown and true or false
    SetDropdownPartShown(menu, control.open)
    if control.open then U.SetBackgroundColor(menu, M.Unpack(menuBackground)) end
    local i
    for i = 1, table.getn(control.rows) do
      SetDropdownPartShown(control.rows[i], control.open)
    end
    if not control.open and activeDropdown == control then
      activeDropdown = nil
    end
  end

  local function ApplySelection()
    local selected
    local i
    for i = 1, table.getn(items) do
      if items[i].value == control.value then selected = items[i] end
    end
    if button.label then
      button.label:SetText(selected and selected.text or "")
    end

    for i = 1, table.getn(control.rows) do
      local row = control.rows[i]
      local active = row.item.value == control.value
      local disabled = row.item.disabled and true or false
      U.SetBackgroundColor(row, M.Unpack(active and M.color.accentFill or
                                         M.color.background))
      U.SetBorderColor(row, M.Unpack(active and M.color.accent or M.color.border))
      if row.label then
        pcall(row.label.SetTextColor, row.label,
              M.Unpack(disabled and M.color.textDim or
                       (active and M.color.accent or M.color.text)))
      end
    end
  end

  control.SetOpen = function(open)
    open = open and true or false
    if open and activeDropdown and activeDropdown ~= control then
      activeDropdown.SetOpen(false)
    end
    if open then activeDropdown = control end
    SetPopupShown(open)
    if open then ApplySelection() end
  end

  control.SetValue = function(value, notify)
    local valid = false
    local i
    for i = 1, table.getn(items) do
      if items[i].value == value and not items[i].disabled then
        valid = true
        break
      end
    end
    if not valid then return false end

    local changed = control.value ~= value
    control.value = value
    ApplySelection()
    if changed and notify and type(options.onChange) == "function" then
      options.onChange(value)
    end
    return true
  end

  control.GetValue = function()
    return control.value
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    button:ClearAllPoints()
    button:SetPoint(point, relative, relativePoint, x, y)
  end

  control.uuiSetShown = function(shown)
    SetDropdownPartShown(button, shown)
    if arrow then
      if shown then arrow:Show() else arrow:Hide() end
    end
    if not shown then
      control.SetOpen(false)
    else
      SetPopupShown(control.open)
    end
  end

  button:SetScript("OnClick", function()
    control.SetOpen(not control.open)
  end)

  local i
  for i = 1, table.getn(items) do
    local item = items[i]
    local row = U.CreateButton(menu, {
      name = options.name and (options.name .. "Item" .. i) or nil,
      text = item.text or tostring(item.value or ""),
      width = width - 2,
      height = rowHeight,
    })
    row.item = item
    pcall(row.EnableMouse, row, not item.disabled)
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1 - (i - 1) * rowHeight)
    if row.label then
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", 7, U.BUTTON_LABEL_OFFSET_Y)
      pcall(row.label.SetWidth, row.label, width - 16)
      pcall(row.label.SetJustifyH, row.label, "LEFT")
    end
    if levelOk and tonumber(level) then
      pcall(row.SetFrameLevel, row, level + 41)
    end
    row:SetScript("OnEnter", function()
      U.SetBorderColor(row, M.Unpack(M.color.accentDim))
      if row.item.value ~= control.value then
        U.SetBackgroundColor(row, 1, 1, 1, 0.07)
      end
    end)
    row:SetScript("OnLeave", function()
      ApplySelection()
    end)
    row:SetScript("OnClick", function()
      control.SetValue(row.item.value, true)
      control.SetOpen(false)
    end)
    table.insert(control.rows, row)
  end

  if not control.SetValue(options.value, false) then
    for i = 1, table.getn(items) do
      if not items[i].disabled then
        control.SetValue(items[i].value, false)
        break
      end
    end
  end
  control.SetOpen(false)
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
    dialog.title:SetText(U.L("COMMON_SELECT_COLOUR"))
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
    text = U.L("COMMON_OK"),
    width = 100,
    height = 22,
    onClick = function() U.CloseColorPicker(true) end,
  })
  accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -124, 14)
  dialog.accept = accept

  local cancel = U.CreateButton(dialog, {
    name = "UnrealUIColorPickerCancel",
    text = U.L("COMMON_CANCEL"),
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

    if d.title then d.title:SetText(options.text or U.L("COMMON_SELECT_COLOUR")) end

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

-- ---------------------------------------------------------------------------
-- Money readout
--
-- One denomination (number plus coin icon) and a gold/silver/copper row built
-- from three of them, both driven by core/media.lua's M.money so colours cannot
-- drift between callers. The confirmed rendering path is one UI-MoneyIcons
-- atlas sliced horizontally; the separate per-denomination texture paths were
-- the paths that failed, not the atlas (knowledge.json /
-- textures.separate_coin_paths_not_rendered).
-- ---------------------------------------------------------------------------
local function LabelWidth(label)
  if not label then return 0 end
  local ok, width = pcall(label.GetStringWidth, label)
  return ok and math.ceil(tonumber(width) or 0) or 0
end

-- denom: "gold" | "silver" | "copper"
function U.CreateMoneyCoin(parent, denom, size)
  local spec = M.money[denom]
  local coords = spec and spec.coords
  if not spec or not coords then return nil end

  size = size or 14
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(size)
  holder:SetWidth(size)

  local iconSize = size - 2
  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(iconSize)
  icon:SetHeight(iconSize)
  -- The artwork sits low inside each atlas slice; raise the texture while the
  -- number remains on the common text baseline used by bags and status.
  icon:SetPoint("RIGHT", holder, "RIGHT", 0, 2)
  pcall(icon.SetTexture, icon, M.moneyTexture)
  pcall(icon.SetTexCoord, icon,
        coords[1], coords[2], coords[3], coords[4])
  holder.icon = icon
  holder.iconWidth = iconSize

  holder.label = U.CreateLabel(holder, {
    size = M.fontSize.small,
    color = spec.color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then
    holder.label:SetPoint("RIGHT", icon, "LEFT", -1, -2)
  end

  return holder
end

function U.SetMoneyCoin(coin, value)
  if not coin or not coin.label then return end
  coin.label:SetText(tostring(value))

  -- Sized to the rendered amount rather than a reserved width, so adjacent
  -- denominations sit with a small, constant gap between them.
  local width = LabelWidth(coin.label)
  if width == 0 then width = string.len(tostring(value)) * 7 end
  coin.contentWidth = math.ceil(width) + 1 + (coin.iconWidth or 0)
  coin:SetWidth(coin.contentWidth)
end

-- A gold/silver/copper row with a single :SetAmount(copper) entry point.
-- row.contentWidth is kept current after every call, so a caller can centre
-- or resize around it without re-measuring the three coins itself.
function U.CreateMoneyReadout(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(14)

  row.gold   = U.CreateMoneyCoin(row, "gold")
  row.silver = U.CreateMoneyCoin(row, "silver")
  row.copper = U.CreateMoneyCoin(row, "copper")
  row.gold:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.silver:SetPoint("LEFT", row.gold, "RIGHT", 3, 0)
  row.copper:SetPoint("LEFT", row.silver, "RIGHT", 3, 0)

  function row:SetAmount(copper)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end

    U.SetMoneyCoin(row.gold, tostring(math.floor(copper / 10000)))
    U.SetMoneyCoin(row.silver, tostring(math.floor(math.mod(copper, 10000) / 100)))
    U.SetMoneyCoin(row.copper, tostring(math.mod(copper, 100)))

    row.contentWidth = (row.gold.contentWidth or 0) + 3 +
                        (row.silver.contentWidth or 0) + 3 +
                        (row.copper.contentWidth or 0)
    row:SetWidth(row.contentWidth)
  end

  return row
end

-- ---------------------------------------------------------------------------
-- Price panel
--
-- A small owned panel that shows a money readout under whatever button is
-- being hovered. Kept separate from GameTooltip rather than injected into it:
-- GameTooltip's own line/texture pool has no compact record on this client,
-- so the price readout is a normal frame this addon fully owns instead of a
-- guess at undocumented tooltip internals. One instance is reused by every
-- caller, the same singleton pattern as the confirm dialog below.
-- ---------------------------------------------------------------------------
-- USER_CONFIRMED_INGAME (2026-08-26): the note above is not just caution, it
-- is measured. Lines appended to a populated GameTooltip from Lua are accepted
-- and counted -- NumLines went 1 -> 3, and both GameTooltipTextLeft3 and
-- TextRight3 read back the intended text with IsShown true -- yet the tooltip
-- kept rendering a single line, before and after an unconditional Show(). The
-- client lays a tooltip out inside its own item builders and does not relayout
-- for a Lua caller. Anything this addon wants to add to a tooltip therefore
-- belongs in an owned frame like this one, never in a tooltip line.
-- USER_CONFIRMED_INGAME (2026-08-26): this owned panel renders with real item
-- values. Item tooltips request the stock tooltip's width and share
-- its bottom edge so the two frames read as one continuous surface.
local moneyPanel

local MONEY_ROW_HEIGHT = 14
local MONEY_PANEL_INSET = 6
local MONEY_COLUMN_GAP = 10

local function BuildMoneyPanel()
  local panel = U.CreatePanel(UIParent, {
    name = "UnrealUIMoneyPanel",
    width = 10,
    height = 10,
  })
  pcall(panel.SetFrameStrata, panel, "TOOLTIP")

  panel.rows = {}
  panel:Hide()
  return panel
end

local function MoneyPanelRow(panel, index)
  local row = panel.rows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, panel)
  row:SetHeight(MONEY_ROW_HEIGHT)

  row.label = U.CreateLabel(row, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if row.label then row.label:SetPoint("LEFT", row, "LEFT", 0, 0) end

  row.readout = U.CreateMoneyReadout(row)
  panel.rows[index] = row
  return row
end

-- Width sync
--
-- matchAnchor callers want the panel to span the frame it hangs under so the
-- two read as one surface. That width cannot be taken once while the panel is
-- being placed: an item tooltip is laid out by the client after the OnEnter
-- chain that places this panel has returned, so a width read there still
-- describes the *previous* tooltip. That is what produced an oversized price
-- cell -- a short item name inheriting the width of whatever wider tooltip was
-- hovered before it.
--
-- The panel therefore opens at its own content width, which is always right,
-- and follows the anchor from the next shared-driver tick onwards. A frame
-- that never reports a usable width just keeps the content width. The ticker
-- runs only while the panel is shown, which is only while an item is hovered,
-- and the applied numbers stay on the frame for /uui price to read back.
local MONEY_WIDTH_TICKER = "widgets.money-width"

local function ApplyMoneyPanelWidth()
  if not moneyPanel then return end

  local width = moneyPanel.contentWidth or 0
  local anchor = moneyPanel.matchFrame
  local anchorWidth = nil

  if anchor then
    local ok, value = pcall(anchor.GetWidth, anchor)
    if ok then anchorWidth = tonumber(value) end
    if anchorWidth and anchorWidth > width then width = anchorWidth end
  end

  moneyPanel.anchorWidth = anchorWidth
  if width <= 0 or width == moneyPanel.appliedWidth then return end

  moneyPanel.appliedWidth = width
  moneyPanel:SetWidth(width)
end

-- One owned panel of labelled money rows, anchored under whatever frame is
-- being described -- a hovered button, or GameTooltip itself. rows is an array
-- of { label = string, copper = number }; the money column is aligned across
-- every row. The anchor defaults to sitting flush under the frame's left edge;
-- callers that want it centred pass their own points. matchAnchor makes an
-- attached section track a wider anchor without changing compact button-price
-- panels.
function U.ShowMoneyRows(anchorFrame, rows, point, relativePoint, x, y,
                         matchAnchor)
  if not anchorFrame or type(rows) ~= "table" then
    U.HideMoneyRows()
    return
  end

  local total = table.getn(rows)
  if total == 0 then
    U.HideMoneyRows()
    return
  end

  if not moneyPanel then moneyPanel = BuildMoneyPanel() end

  local widest, i = 0, nil
  for i = 1, total do
    local row = MoneyPanelRow(moneyPanel, i)
    if row.label then row.label:SetText(rows[i].label or "") end
    row.readout:SetAmount(rows[i].copper)

    local labelWidth = LabelWidth(row.label)
    if labelWidth > widest then widest = labelWidth end
    row:Show()
  end

  for i = total + 1, table.getn(moneyPanel.rows) do
    moneyPanel.rows[i]:Hide()
  end

  -- Second pass: the money column starts past the widest label, so the amounts
  -- line up instead of stepping with the text beside them.
  local content = 0
  for i = 1, total do
    local row = moneyPanel.rows[i]
    row.readout:ClearAllPoints()
    row.readout:SetPoint("LEFT", row, "LEFT", widest + MONEY_COLUMN_GAP, 0)

    local rowWidth = widest + MONEY_COLUMN_GAP + (row.readout.contentWidth or 0)
    if rowWidth > content then content = rowWidth end

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", moneyPanel, "TOPLEFT", MONEY_PANEL_INSET,
                 -(MONEY_PANEL_INSET + (i - 1) * (MONEY_ROW_HEIGHT + 1)))
  end

  for i = 1, total do
    moneyPanel.rows[i]:SetWidth(content)
  end

  -- Opened at the content width with no anchor consulted: whatever the anchor
  -- reports during this call belongs to its previous contents.
  moneyPanel.contentWidth = content + MONEY_PANEL_INSET * 2
  moneyPanel.matchFrame = nil
  ApplyMoneyPanelWidth()

  moneyPanel:SetHeight(total * MONEY_ROW_HEIGHT + (total - 1) +
                       MONEY_PANEL_INSET * 2)
  moneyPanel:ClearAllPoints()
  moneyPanel:SetPoint(point or "TOPLEFT", anchorFrame,
                      relativePoint or "BOTTOMLEFT", x or 0, y or -3)
  moneyPanel:Show()

  if matchAnchor then
    moneyPanel.matchFrame = anchorFrame
    U.RegisterUpdate(MONEY_WIDTH_TICKER, 0, ApplyMoneyPanelWidth)
  else
    U.UnregisterUpdate(MONEY_WIDTH_TICKER)
  end

  return moneyPanel
end

function U.HideMoneyRows()
  U.UnregisterUpdate(MONEY_WIDTH_TICKER)
  if moneyPanel then
    moneyPanel.matchFrame = nil
    moneyPanel:Hide()
  end
end

-- The bank purchase hover is one row of the same panel. It keeps its own
-- centred anchor so the confirmed placement under that button does not move.
local function ShowPricePanel(anchorFrame, copper)
  U.ShowMoneyRows(anchorFrame, { { label = U.L("COMMON_COST"), copper = copper } },
                  "TOP", "BOTTOM", 0, -4)
end

local function HidePricePanel()
  U.HideMoneyRows()
end

-- ---------------------------------------------------------------------------
-- Icon buttons
--
-- A small square button with a stock icon inset inside the unrealUI border,
-- plus a tooltip and an optional price readout underneath it. Promoted here
-- from a module-local copy in modules/bags.lua (header toggles for the
-- keyring, bag slots and vendor action) once modules/bank.lua needed the
-- identical recipe for its purchase control.
--
-- options: name, texture, fallback, title, detail (function -> string or nil),
--          price (function -> copper amount or nil), onClick
-- ---------------------------------------------------------------------------
function U.CreateIconButton(parent, options)
  options = options or {}

  local button = U.CreateButton(parent, {
    name = options.name,
    text = "",
    width = options.size or M.slot.icon,
    height = options.size or M.slot.icon,
    onClick = options.onClick,
  })

  local edge = U.BorderSize()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)

  if pcall(icon.SetTexture, icon, options.texture) then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  else
    icon:Hide()
    if button.label then button.label:SetText(options.fallback or "?") end
  end
  button.icon = icon

  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(M.color.moverEdge))

    local tip = U.G("GameTooltip")
    if tip then
      pcall(tip.SetOwner, tip, button, "ANCHOR_BOTTOM")
      pcall(tip.SetText, tip, options.title)
      if type(options.detail) == "function" then
        local line = options.detail()
        if line then pcall(tip.AddLine, tip, line, 0.65, 0.65, 0.65, 1) end
      end
      pcall(tip.Show, tip)
    end

    if type(options.price) == "function" then
      local copper = options.price()
      if tonumber(copper) then ShowPricePanel(button, copper) end
    end
  end)

  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(M.color.border))
    local tip = U.G("GameTooltip")
    if tip then pcall(tip.Hide, tip) end
    HidePricePanel()
  end)

  return button
end

-- ---------------------------------------------------------------------------
-- Confirmation dialog
--
-- One shared modal for "are you sure" actions (delete greys, buy a bank slot).
-- An owned panel rather than StaticPopup: query_compat.py has no record of
-- StaticPopupDialogs/StaticPopup_Show on this client at all, and this needs
-- only a line of text, an optional detail line and two buttons, all of which
-- core/style.lua already provides.
--
-- It replaced a module-local copy that lived in modules/bags.lua; the design
-- rules list "modal dialogs" as a missing shared component, so the second
-- caller (modules/bank.lua) added it centrally instead of copying it again.
-- ---------------------------------------------------------------------------
local confirmDialog

local function BuildConfirmDialog()
  local dialog = U.CreatePanel(UIParent, {
    name = "UnrealUIConfirm",
    width = 280,
    height = 100,
  })
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  pcall(dialog.SetFrameStrata, dialog, "DIALOG")
  pcall(dialog.EnableMouse, dialog, true)

  dialog.text = U.CreateLabel(dialog, {
    size = M.fontSize.normal,
    color = M.color.text,
    inherits = "GameFontNormal",
  })
  if dialog.text then
    dialog.text:SetPoint("TOP", dialog, "TOP", 0, -16)
  end

  dialog.detail = U.CreateLabel(dialog, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if dialog.detail then
    dialog.detail:SetPoint("TOP", dialog, "TOP", 0, -38)
  end

  -- Optional price row: "Cost:" plus the shared gold/silver/copper readout,
  -- shown instead of the plain detail text when a caller passes
  -- options.moneyCopper (modules/bank.lua's purchase confirmation).
  dialog.priceRow = CreateFrame("Frame", nil, dialog)
  dialog.priceRow:SetHeight(14)

  dialog.priceCaption = U.CreateLabel(dialog.priceRow, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if dialog.priceCaption then
    dialog.priceCaption:SetText(U.L("COMMON_COST"))
    dialog.priceCaption:SetPoint("LEFT", dialog.priceRow, "LEFT", 0, 0)
  end

  dialog.priceReadout = U.CreateMoneyReadout(dialog.priceRow)
  if dialog.priceCaption then
    dialog.priceReadout:SetPoint("LEFT", dialog.priceCaption, "RIGHT", 4, 0)
  else
    dialog.priceReadout:SetPoint("LEFT", dialog.priceRow, "LEFT", 0, 0)
  end

  dialog.priceRow:Hide()

  dialog.cancel = U.CreateButton(dialog, {
    name = "UnrealUIConfirmCancel",
    text = U.L("COMMON_CANCEL"),
    width = 110,
    height = 24,
    onClick = function() dialog:Hide() end,
  })
  dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)

  dialog.accept = U.CreateButton(dialog, {
    name = "UnrealUIConfirmAccept",
    text = U.L("COMMON_ACCEPT"),
    width = 110,
    height = 24,
  })
  dialog.accept:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)

  dialog:Hide()
  return dialog
end

-- options: text, detail, acceptText, cancelText, onAccept, owner, centered
--
-- `owner` is an opaque tag so a caller can take its own dialog down again
-- (U.HideConfirm(owner)) without cancelling one another window put up.
-- options.moneyCopper (a copper amount) shows the gold/silver/copper price
-- row instead of plain detail text; leave it nil for a normal confirm.
function U.ShowConfirm(options)
  options = options or {}
  if not confirmDialog then confirmDialog = BuildConfirmDialog() end

  local dialog = confirmDialog
  dialog.uuiOwner = options.owner
  dialog:ClearAllPoints()
  if options.centered then
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  else
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  if dialog.text then dialog.text:SetText(options.text or U.L("COMMON_ARE_YOU_SURE")) end

  local money = tonumber(options.moneyCopper)
  if dialog.detail then dialog.detail:SetText(options.detail or "") end

  if dialog.accept.label then
    dialog.accept.label:SetText(options.acceptText or U.L("COMMON_ACCEPT"))
  end
  if dialog.cancel.label then
    dialog.cancel.label:SetText(options.cancelText or U.L("COMMON_CANCEL"))
  end

  dialog.accept:SetScript("OnClick", function()
    dialog:Hide()
    if type(options.onAccept) == "function" then options.onAccept() end
  end)

  -- rendering.parent_alpha_not_propagated: every part is shown explicitly
  -- rather than left to follow the panel it hangs off.
  dialog:Show()
  if dialog.text then dialog.text:Show() end
  dialog.accept:Show()
  dialog.cancel:Show()

  if money then
    dialog.priceReadout:SetAmount(money)

    local capWidth = 0
    if dialog.priceCaption then
      local ok, w = pcall(dialog.priceCaption.GetStringWidth, dialog.priceCaption)
      capWidth = (ok and math.ceil(tonumber(w) or 0)) or 0
    end

    dialog.priceRow:SetWidth(capWidth + 4 + (dialog.priceReadout.contentWidth or 0))
    dialog.priceRow:ClearAllPoints()
    dialog.priceRow:SetPoint("TOP", dialog, "TOP", 0, -40)
    dialog.priceRow:Show()
    if dialog.priceCaption then dialog.priceCaption:Show() end
    if dialog.detail then dialog.detail:Hide() end
  else
    dialog.priceRow:Hide()
    if dialog.detail then dialog.detail:Show() end
  end

  return dialog
end

function U.HideConfirm(owner)
  if not confirmDialog then return end
  if owner and confirmDialog.uuiOwner ~= owner then return end
  confirmDialog:Hide()
end
