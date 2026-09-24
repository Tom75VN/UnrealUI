-- unrealUI :: core/widgets.lua
--
-- Composite controls for UnrealUI surfaces: startup progress plus the settings
-- panel's sliders, checkboxes, radio groups, dropdowns, headings and rows.
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

-- media/arrow.tga is 25x32, so a requested glyph height picks the width that
-- keeps the authored triangle from stretching.
local ARROW_ASPECT = 25 / 32
-- 13x10 on screen. Calibrated against the buff row's collapse control at 30%
-- below the 18 this started at, which read as a lit icon rather than as a
-- control beside the icons. Central so the next arrow is the same arrow.
local ARROW_GLYPH_HEIGHT = 13
-- Default sits a little under full strength so the arrow reads as chrome next
-- to game content rather than as another lit icon.
local ARROW_ALPHA_DEFAULT = 0.80
local ARROW_ALPHA_HOVER = 1.00
local ARROW_ALPHA_PUSHED = 0.55
local ARROW_ALPHA_DISABLED = 0.35

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
-- Progress indicators
-- ---------------------------------------------------------------------------

-- A compact, non-interactive progress bar shared by any UnrealUI surface that
-- needs to report bounded work. The fill comes from the verified plain-texture
-- status-bar primitive in core/style.lua; this wrapper adds the standard
-- outline and, unless showText is false, an owned centred readout without
-- depending on the native StatusBar widget, whose fill is known not to lay
-- itself out on this client.
function U.CreateProgressIndicator(parent, options)
  options = options or {}

  local bar = U.CreateStatusBar(parent, {
    name = options.name,
    width = options.width or 240,
    height = options.height or 12,
    background = options.background or M.color.healthBg,
    color = options.color or M.color.accent,
  })
  if not bar then return nil end

  U.CreateBorder(bar, options.thickness)
  U.SetBorderColor(bar, M.Unpack(options.border or M.color.border))

  local label
  if options.showText ~= false then
    label = U.CreateLabel(bar, {
      size = options.size or M.fontSize.tiny,
      color = options.textColor or M.color.text,
      inherits = "GameFontNormal",
      width = math.max(1, (options.width or 240) - 8),
      height = math.max(1, (options.height or 12) - 2),
      justify = "CENTER",
    })
  end
  if label then
    label:SetPoint("CENTER", bar, "CENTER", 0, -1)
    label:SetText(options.text or "")
  end
  bar.label = label

  function bar:SetProgress(value, text)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    self:SetValue(value)
    if label and text ~= nil then label:SetText(tostring(text)) end
  end

  bar:SetMinMaxValues(0, 1)
  bar:SetProgress(options.value or 0, options.text or "")
  return bar
end

-- ---------------------------------------------------------------------------
-- Startup loading
-- ---------------------------------------------------------------------------

-- This lives beside the shared progress component rather than in a new TOC
-- file because this client can retain the add-on's file list across /reload.
-- Keeping the login surface in an already-loaded core file means installing an
-- update while the client is open still makes it available on the next reload.
--
-- Native suppression cannot safely run while the client constructs its own
-- interface: measured runtime evidence shows that doing so leaves the session
-- with severe target-change stalls. core/compat.lua owns the measured settle
-- criteria and reports them here; this code draws their progress and sends the
-- explanation to chat without blocking the play area.
local startupLoading = {
  width = 315,
  height = 8,
  progress = 0,
}

function startupLoading.SetRegionShown(region, shown)
  if not region then return end
  if shown then region:Show() else region:Hide() end
end

function startupLoading.SetShown(shown)
  startupLoading.SetRegionShown(startupLoading.bar, shown)
  if startupLoading.bar then
    startupLoading.SetRegionShown(startupLoading.bar.uuiBackground, shown)
    startupLoading.SetRegionShown(startupLoading.bar.uuiFillTexture,
                                  shown and startupLoading.progress > 0)
    startupLoading.SetRegionShown(startupLoading.bar.label, shown)
    local i
    for i = 1, table.getn(startupLoading.bar.uuiEdges or {}) do
      startupLoading.SetRegionShown(startupLoading.bar.uuiEdges[i], shown)
    end
  end
end

function startupLoading.Build()
  if startupLoading.bar then return true end

  local bar = U.CreateProgressIndicator(UIParent, {
    name = "UnrealUIStartupLoading",
    width = startupLoading.width,
    height = startupLoading.height,
    color = M.color.accent,
    showText = false,
  })
  if bar then
    bar:SetPoint("TOP", UIParent, "TOP", 0, -42)
    pcall(bar.SetFrameStrata, bar, "FULLSCREEN_DIALOG")
    pcall(bar.SetFrameLevel, bar, 1000)
    bar:Show()
  end
  startupLoading.bar = bar
  return bar ~= nil
end

function U.ShowStartupLoading()
  if startupLoading.active then return end
  if not startupLoading.Build() then return end

  startupLoading.active = true
  startupLoading.progress = 0
  startupLoading.lastPercent = 0
  startupLoading.SetShown(true)
  startupLoading.bar:SetProgress(0)

  -- Keep the explanation available without covering the play area. The
  -- loading surface itself is now only the slim bar at the top of the screen.
  U.Print(U.L("LOADING_TITLE") .. ": " .. U.L("LOADING_CLIENT_LIMITATION"))
  U.Print(U.L("LOADING_FPS_DEPENDENT"))
end

-- `quiet` is the current run of frames shorter than the compatibility layer's
-- stability threshold. It can reset after a hitch, so the visible bar is
-- monotonic: measured readiness can advance it, never pull it backwards. The
-- hard-cap fraction keeps it moving on a low-FPS client that cannot accumulate
-- enough quiet frames and will therefore finish through the safety deadline.
function U.UpdateStartupLoading(waited, quiet, minimum, maximum, quietNeeded)
  if not startupLoading.active or not startupLoading.bar then return end

  waited = tonumber(waited) or 0
  quiet = tonumber(quiet) or 0
  minimum = tonumber(minimum) or 1
  maximum = tonumber(maximum) or minimum
  quietNeeded = tonumber(quietNeeded) or 1

  local timeReady = waited / minimum
  local frameReady = quiet / quietNeeded
  local readiness = math.min(timeReady, frameReady)
  local deadline = waited / maximum
  local progress = math.max(readiness, deadline)
  if progress > 0.99 then progress = 0.99 end
  if progress < startupLoading.progress then progress = startupLoading.progress end

  startupLoading.progress = progress
  local percent = math.floor(progress * 100)
  if percent <= startupLoading.lastPercent then return end
  startupLoading.lastPercent = percent
  startupLoading.bar:SetProgress(percent / 100)
end

function U.CompleteStartupLoading()
  if not startupLoading.active or not startupLoading.bar then return end

  startupLoading.progress = 1
  startupLoading.lastPercent = 100
  startupLoading.bar:SetProgress(1)

  -- Leave the completed state visible for one rendered frame after native
  -- suppression. The shared driver is the only reliable deferred path on this
  -- client; a child frame created here may never receive its own OnUpdate.
  U.DeferOnce("loading.hide", function()
    startupLoading.SetShown(false)
    startupLoading.active = false
  end)
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

  local control = {
    uuiSectionHeader = true,
    uuiSectionParent = parent,
    uuiSectionX = options.x or 0,
    uuiSectionY = options.y or 0,
    uuiSectionWidth = options.width or 400,
  }

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
  local control = { enabled = options.disabled ~= true, hovered = false }
  local rowHost
  local Toggle

  -- Optional full-row interaction for compact lists. The visible checkbox and
  -- label remain the standard shared component; this host only expands the hit
  -- area and owns the subdued accent hover fill.
  if options.rowHover then
    rowHost = CreateFrame("Button", options.name and (options.name .. "Row"),
                          parent)
    rowHost:SetWidth(options.rowWidth or SETTINGS_TEXT_WIDTH)
    rowHost:SetHeight(options.rowHeight or math.max(size, 18))
    U.CreateBackdrop(rowHost, { background = { 0, 0, 0, 0 }, border = false })
    pcall(rowHost.EnableMouse, rowHost, true)
    Part(control, rowHost)
    control.row = rowHost
  end

  local box = U.CreateButton(rowHost or parent, {
    name = options.name,
    text = "",
    width = size,
    height = size,
    onClick = function()
      if Toggle then Toggle() end
    end,
  })
  Part(control, box)
  control.box = box

  local label = U.CreateSettingsLabel(rowHost or parent, {
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

  if rowHost then
    box:SetPoint("LEFT", rowHost, "LEFT", 0, 0)
    rowHost:SetScript("OnClick", function() if Toggle then Toggle() end end)
    rowHost:SetScript("OnEnter", function()
      if not control.enabled then return end
      control.hovered = true
      control.Apply()
      if type(options.onEnter) == "function" then options.onEnter() end
    end)
    rowHost:SetScript("OnLeave", function()
      control.hovered = false
      control.Apply()
      if type(options.onLeave) == "function" then options.onLeave() end
    end)
  end

  control.Apply = function()
    U.SetBackgroundColor(box, M.Unpack(M.color.background))
    U.SetCheckboxIndicator(box, control.value)
    if box.uuiCheckboxMark and not control.enabled then
      U.SetColor(box.uuiCheckboxMark, M.Unpack(M.color.textDim))
    end
    -- Written on every branch, not just hover/disabled: with rowHover the box's
    -- own OnLeave never fires (its mouse is off), so leaving the accent border
    -- unwritten kept a hovered row accented after the cursor left it.
    U.SetBorderColor(box, M.Unpack(
      (control.enabled and control.hovered) and M.color.accent or M.color.border))
    if label then
      local color = not control.enabled and M.color.textDim or
                    (control.hovered and M.color.accent or M.color.text)
      pcall(label.SetTextColor, label, M.Unpack(color))
    end
    if rowHost then
      U.SetBackgroundColor(rowHost, M.Unpack(
        control.hovered and M.color.accentFill or { 0, 0, 0, 0 }))
      pcall(box.EnableMouse, box, false)
      pcall(rowHost.EnableMouse, rowHost, control.enabled)
    else
      pcall(box.EnableMouse, box, control.enabled)
    end
  end

  Toggle = function()
    if not control.enabled then return end
    control.value = not control.value
    control.Apply()
    if type(options.onChange) == "function" then
      options.onChange(control.value)
    end
  end

  control.SetValue = function(value)
    control.value = value and true or false
    control.Apply()
  end

  control.SetEnabled = function(enabled)
    control.enabled = enabled and true or false
    if not control.enabled and control.hovered then
      control.hovered = false
      if type(options.onLeave) == "function" then options.onLeave() end
    end
    control.Apply()
  end

  control.SetPoint = function(point, relative, relativePoint, x, y)
    local target = rowHost or box
    target:ClearAllPoints()
    target:SetPoint(point, relative, relativePoint, x, y)
  end

  control.SetValue(options.value)
  return control
end

-- ---------------------------------------------------------------------------
-- Collapse control
--
-- The sharp +/- box .claude/rules/unreal-ui-design.md names as an established
-- pattern. The recipe was born inside core/stockui.lua's native-header adapter
-- and lives here now because the bag's category sections need the identical
-- control on a frame unrealUI owns outright; that adapter builds its icon
-- through this function, so there is still exactly one +/- box in the addon.
--
-- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
-- accepts SetText without ever showing a FontString, so the glyph is a
-- FontString this code creates and owns.
--
-- USER_CONFIRMED_INGAME (recorded against the stock adapter): SetHitRectInsets
-- with negative values made the box's left portion unclickable on this client
-- instead of growing the hit area, so the click target is the button's real
-- size and no inset call is made. Callers wanting a roomier target pass size.
--
-- options: size (16 default, 18 for a roomier host), level (frame levels above
-- the parent, default 2), collapsed (initial state), onClick(collapsed) --
-- called with the state the click is asking for, not the current one.
--
-- Created hidden: callers Show it once they have anchored it.
-- ---------------------------------------------------------------------------
local collapseCount = 0

function U.CreateCollapseButton(parent, options)
  if not parent then return nil end
  options = options or {}
  collapseCount = collapseCount + 1

  local created, button = pcall(CreateFrame, "Button",
    "UnrealUICollapseIcon" .. collapseCount, parent)
  if not created or not button then return nil end

  local size = options.size or 16
  button:SetWidth(size)
  button:SetHeight(size)
  U.CreateBackdrop(button, { background = { 0.03, 0.03, 0.03, 0.90 } })
  pcall(button.EnableMouse, button, true)

  local levelOk, level = pcall(parent.GetFrameLevel, parent)
  if levelOk and tonumber(level) then
    pcall(button.SetFrameLevel, button, level + (options.level or 2))
  end

  -- unrealUI's own hover feedback, replacing any native highlight the host may
  -- have: the outline brightens to the addon accent like every other control.
  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(M.color.accent))
  end)
  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end)

  button.text = U.CreateLabel(button, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if button.text then
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
  end

  -- uui-prefixed like every other field unrealUI adds to a frame it did not
  -- define, so it cannot collide with a widget method this client may expose.
  button.uuiSetCollapsed = function(collapsed)
    button.uuiCollapsed = collapsed and true or false
    if button.text then
      button.text:SetText(button.uuiCollapsed and "+" or "-")
    end
  end

  button:SetScript("OnClick", function()
    if type(options.onClick) ~= "function" then return end
    local ok, err = pcall(options.onClick, not button.uuiCollapsed)
    if not ok then U.Error("collapse click: " .. tostring(err)) end
  end)

  button.uuiSetCollapsed(options.collapsed)
  button:Hide()
  return button
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

  -- Reasserted whenever the popup opens. A hosted settings page is recursively
  -- re-levelled after these controls are created, which deliberately flattens
  -- the creation-time +40 and can leave a later slider thumb above the menu.
  -- The popup owns one high block: shell at +40, interactive rows at +41.
  local function RaisePopup()
    local ok, buttonLevel = pcall(button.GetFrameLevel, button)
    buttonLevel = ok and tonumber(buttonLevel) or nil
    if not buttonLevel then return end
    pcall(menu.SetFrameLevel, menu, buttonLevel + 40)
    if menu.uuiDropdownBedMenu then
      pcall(menu.uuiDropdownBedMenu.SetFrameLevel,
            menu.uuiDropdownBedMenu, buttonLevel + 40)
    end
    if menu.uuiDropdownModernWow then
      pcall(menu.uuiDropdownModernWow.SetFrameLevel,
            menu.uuiDropdownModernWow, buttonLevel + 40)
    end
    local i
    for i = 1, table.getn(control.rows) do
      pcall(control.rows[i].SetFrameLevel, control.rows[i], buttonLevel + 41)
    end
  end
  control.RaisePopup = RaisePopup

  local function SetPopupShown(shown)
    control.open = shown and true or false
    if control.open then RaisePopup() end
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

  -- Shared settings skins can add the same previous/next controls used by the
  -- Game Settings dropdown without knowing this widget's private item list.
  -- Disabled entries are skipped just as they are when choosing from the
  -- open menu.
  local function StepTarget(direction)
    direction = tonumber(direction) or 0
    if direction == 0 then return nil end
    direction = direction < 0 and -1 or 1
    local current
    local i
    for i = 1, table.getn(items) do
      if items[i].value == control.value then current = i; break end
    end
    if not current then return nil end
    i = current + direction
    while i >= 1 and i <= table.getn(items) do
      if not items[i].disabled then return i end
      i = i + direction
    end
    return nil
  end

  control.GetStepState = function()
    return StepTarget(-1) ~= nil, StepTarget(1) ~= nil
  end

  control.StepValue = function(direction)
    local target = StepTarget(direction)
    if not target then return false end
    return control.SetValue(items[target].value, true)
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
                        { headerHeight = 24, headerInset = 0,
                          avoidOverlap = false })

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
-- options.onInput(value), when supplied, receives the stepped display value
-- while the thumb is moving. It is a preview hook only; options.onChange still
-- publishes the final value when the drag ends.
-- options.onInputStart/onInputEnd bracket both a thumb drag and a direct track
-- click, so a caller can temporarily pin surrounding UI during live preview.
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
  -- control in-session, so this is still a Button (the only widget type this
  -- client delivers OnDragStart to). Its native movement remains invisible;
  -- the verified GetCursorPosition/GetEffectiveScale pair supplies X to the
  -- separate visible square, permanently locking that square's Y to zero and
  -- clamping the entire shape inside the track.
  local THUMB_WIDTH, THUMB_HEIGHT = 14, 14

  local thumb = CreateFrame("Button", options.name and (options.name .. "Thumb"),
                            track)
  thumb:SetWidth(THUMB_WIDTH)
  thumb:SetHeight(THUMB_HEIGHT)
  pcall(thumb.EnableMouse, thumb, true)
  pcall(thumb.RegisterForDrag, thumb, "LeftButton")
  Part(control, thumb)
  control.thumb = thumb

  -- StartMoving is required on this client for a matching OnDragStop, but the
  -- frame it moves is unconstrained. Keep that Button as an invisible input
  -- handle and draw the square on a separate, mouse-transparent frame whose
  -- anchor remains under this component's control.
  local visual = CreateFrame("Frame", options.name and
                             (options.name .. "ThumbVisual"), track)
  visual:SetWidth(THUMB_WIDTH)
  visual:SetHeight(THUMB_HEIGHT)
  U.CreateBackdrop(visual, {
    background = M.color.accent,
    border = M.color.border,
  })
  Part(control, visual)
  control.thumbVisual = visual

  thumb:SetScript("OnEnter", function()
    U.SetBorderColor(visual, M.Unpack(M.color.moverEdge))
  end)
  thumb:SetScript("OnLeave", function()
    U.SetBorderColor(visual, M.Unpack(M.color.border))
  end)

  local function PlaceThumb(value)
    local usable = width - THUMB_WIDTH
    local offset = 0
    if max > min and usable > 0 then
      offset = (Clamp(value) - min) / (max - min) * usable
    end
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", track, "LEFT", offset, 0)
    visual:ClearAllPoints()
    visual:SetPoint("LEFT", track, "LEFT", offset, 0)
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
  control.minLabel = minLabel

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
  control.maxLabel = maxLabel

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

  -- Sets the displayed value without snapping the thumb to a stepped value.
  -- During a drag the square follows the cursor continuously while the
  -- readout is rounded; Publish performs the final step snap on release.
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

  -- Converts the cursor's X position to a value and a legal thumb offset.
  -- Every geometry read is guarded so a control that has not laid out yet
  -- simply keeps its last valid value instead of jumping.
  local function ReadCursorValue()
    if type(GetCursorPosition) ~= "function" then return nil end

    local cursorOk, cursorX = pcall(GetCursorPosition)
    local scaleOk, scale = pcall(track.GetEffectiveScale, track)
    local trackOk, trackLeft = pcall(track.GetLeft, track)
    local widthOk, trackWidth = pcall(track.GetWidth, track)
    if not (cursorOk and scaleOk and trackOk and widthOk and
            tonumber(cursorX) and tonumber(scale) and scale > 0 and
            tonumber(trackLeft) and tonumber(trackWidth)) then
      return nil
    end

    local usable = trackWidth - THUMB_WIDTH
    if usable <= 0 then return nil end

    -- The cursor owns the thumb centre. Clamping the left-edge offset to the
    -- usable span keeps both circular edges inside their matching track edge.
    local offset = cursorX / scale - trackLeft - THUMB_WIDTH / 2
    if offset < 0 then offset = 0 end
    if offset > usable then offset = usable end

    return min + offset / usable * (max - min), offset
  end

  -- Runs on the shared driver (core/init.lua's U.RegisterUpdate) instead of an
  -- OnUpdate on the thumb itself, per scripts.child_onupdate_unreliable.
  local dragTicker = "slider." .. (options.name or tostring(thumb))
  local dragging = false

  -- OnDragStop is expected after the proven StartMoving recipe below. The
  -- button-state check is a second teardown path for a missed callback, which
  -- otherwise leaves an every-frame cursor follower running indefinitely.
  local function LeftButtonStillDown()
    if type(IsMouseButtonDown) ~= "function" then return true end
    local ok, down = pcall(IsMouseButtonDown, "LeftButton")
    if not ok then return true end
    return down and true or false
  end

  local inputActive = false
  local function BeginInput()
    if inputActive then return end
    inputActive = true
    if type(options.onInputStart) == "function" then options.onInputStart() end
  end

  local function EndInput()
    if not inputActive then return end
    inputActive = false
    if type(options.onInputEnd) == "function" then options.onInputEnd() end
  end

  local function FinishDrag()
    if not dragging then return end
    dragging = false
    U.UnregisterUpdate(dragTicker)
    pcall(thumb.StopMovingOrSizing, thumb)

    local value = ReadCursorValue()
    if value then
      Publish(value)
    else
      PlaceThumb(control.current or min)
    end
    EndInput()
  end

  local function LiveReadoutFromDrag()
    if not LeftButtonStillDown() then
      FinishDrag()
      return
    end

    local value, offset = ReadCursorValue()
    if not value then return end

    visual:ClearAllPoints()
    visual:SetPoint("LEFT", track, "LEFT", offset, 0)
    local stepped = UpdateReadout(value)
    if type(options.onInput) == "function" and
       control.lastInput ~= stepped then
      control.lastInput = stepped
      options.onInput(stepped)
    end
  end

  thumb:SetScript("OnDragStart", function()
    if not pcall(thumb.SetMovable, thumb, true) then return end
    if pcall(thumb.StartMoving, thumb) then
      pcall(thumb.StopMovingOrSizing, thumb)
    end
    if not pcall(thumb.StartMoving, thumb) then return end

    dragging = true
    control.lastInput = nil
    BeginInput()
    U.RegisterUpdate(dragTicker, 0, LiveReadoutFromDrag)
    LiveReadoutFromDrag()
  end)

  thumb:SetScript("OnDragStop", FinishDrag)

  -- The track itself is a direct-position surface: a click publishes the
  -- nearest stepped value and places both the input handle and visible square.
  pcall(track.EnableMouse, track, true)
  track:SetScript("OnMouseDown", function()
    local value = ReadCursorValue()
    if value then
      BeginInput()
      Publish(value)
      EndInput()
    end
  end)

  -- Public surface. SetValue is silent: the settings panel calls it while
  -- populating a page and must not fire onChange back into itself.
  control.SetValue = function(raw)
    Publish(raw, true)
  end

  -- The Forever/Game Settings stepper component calls this public surface so
  -- arrow clicks take the same publish path as a track click or completed
  -- drag, including the page's onChange and live-preview brackets.
  control.GetStepState = function()
    local value = Clamp(control.current or min)
    return value > min, value < max
  end

  control.StepValue = function(direction)
    direction = tonumber(direction) or 0
    if direction == 0 then return false end
    local before = Clamp(control.current or min)
    local after = Clamp(before + (direction < 0 and -step or step))
    if after == before then return false end
    BeginInput()
    Publish(after)
    EndInput()
    return true
  end

  control.SetControlWidth = function(value)
    value = tonumber(value)
    if not value or value < THUMB_WIDTH + 2 then return false end
    width = value
    control.width = width
    pcall(track.SetWidth, track, width)
    if caption then pcall(caption.SetWidth, caption, width) end
    if minLabel then pcall(minLabel.SetWidth, minLabel, width / 2) end
    if maxLabel then pcall(maxLabel.SetWidth, maxLabel, width / 2) end
    PlaceThumb(control.current or min)
    return true
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
-- from three of them, both driven by core/media.lua's M.money so the art and
-- colours cannot drift between callers. Each coin is UnrealUI's own
-- media/icons texture, the same under every theme, so there is no atlas slice
-- to apply here (see the M.money comment in core/media.lua).
-- ---------------------------------------------------------------------------
local function LabelWidth(label)
  if not label then return 0 end
  local ok, width = pcall(label.GetStringWidth, label)
  return ok and math.ceil(tonumber(width) or 0) or 0
end

-- denom: "gold" | "silver" | "copper"
function U.CreateMoneyCoin(parent, denom, size)
  local spec = M.money[denom]
  if not spec or not spec.texture then return nil end

  size = size or 14
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(size)
  holder:SetWidth(size)

  local iconSize = size - 2
  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(iconSize)
  icon:SetHeight(iconSize)
  -- The coin fills its own texture, so it centres on the holder rather than
  -- being raised to compensate for an atlas slice; M.money.iconY lifts it
  -- above the number, which keeps the common text baseline used by bags and
  -- status and so anchors to the holder rather than to the icon.
  icon:SetPoint("RIGHT", holder, "RIGHT", 0, M.money.iconY or 0)
  pcall(icon.SetTexture, icon, spec.texture)
  holder.icon = icon
  holder.iconWidth = iconSize

  holder.label = U.CreateLabel(holder, {
    size = M.fontSize.small,
    color = spec.color,
    inherits = "GameFontNormalSmall",
  })
  if holder.label then
    holder.label:SetPoint("RIGHT", holder, "RIGHT", -(iconSize + 1), 0)
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
function U.CreateMoneyReadout(parent, options)
  options = options or {}
  local gap = tonumber(options.gap) or 3
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(14)

  row.gold   = U.CreateMoneyCoin(row, "gold")
  row.silver = U.CreateMoneyCoin(row, "silver")
  row.copper = U.CreateMoneyCoin(row, "copper")
  row.gold:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.silver:SetPoint("LEFT", row.gold, "RIGHT", 3, 0)
  row.copper:SetPoint("LEFT", row.silver, "RIGHT", 3, 0)

  -- A denomination worth nothing is dropped rather than padded with a zero:
  -- 18 copper reads "18c", and 120 copper reads "1s 20c". Which coins are
  -- visible therefore changes with the value, so the surviving ones are
  -- re-anchored left to right on every call instead of once at creation.
  function row:SetAmount(copper)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end

    local amounts = {
      { coin = row.gold,   value = math.floor(copper / 10000) },
      { coin = row.silver, value = math.floor(math.mod(copper, 10000) / 100) },
      { coin = row.copper, value = math.mod(copper, 100) },
    }

    local previous, width = nil, 0
    for i = 1, 3 do
      local entry = amounts[i]
      if entry.coin then
        -- Copper is the fallback so a free or unknown amount still reads "0c"
        -- instead of collapsing the row to nothing.
        if entry.value > 0 or (i == 3 and not previous) then
          U.SetMoneyCoin(entry.coin, tostring(entry.value))
          entry.coin:ClearAllPoints()
          if previous then
            entry.coin:SetPoint("LEFT", previous, "RIGHT", gap, 0)
            width = width + gap
          else
            entry.coin:SetPoint("LEFT", row, "LEFT", 0, 0)
          end
          width = width + (entry.coin.contentWidth or 0)
          entry.coin:Show()
          previous = entry.coin
        else
          entry.coin:Hide()
        end
      end
    end

    row.contentWidth = width
    if width > 0 then row:SetWidth(width) end
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

-- The panel itself, for a caller that has to stack something under it. Nil
-- while nothing is showing, so a caller can fall back to the tooltip.
function U.MoneyRowsFrame()
  if not moneyPanel then return nil end
  local ok, shown = pcall(moneyPanel.IsShown, moneyPanel)
  if not ok or not shown then return nil end
  return moneyPanel
end

-- ---------------------------------------------------------------------------
-- Tooltip note
--
-- One line of dim explanatory text hung under a tooltip -- currently the bag
-- favourite shortcut (modules/bagfavorites.lua). Its own owned frame for the
-- same reason the money panel above is one: USER_CONFIRMED_INGAME, this client
-- accepts lines appended to a populated GameTooltip and then declines to
-- relayout for them, so nothing an addon wants to add can be a tooltip line.
--
-- Separate from the money panel rather than a row inside it because the two
-- are independent: an item with no known sell price shows no money panel at
-- all, and the shortcut still has to be legible. The caller decides what this
-- hangs under -- the money panel when there is one, the tooltip when there is
-- not -- so the pieces stack in one column either way.
-- ---------------------------------------------------------------------------
local notePanel

local NOTE_PANEL_INSET = 6
local NOTE_ROW_HEIGHT = 14
local NOTE_WIDTH_TICKER = "widgets.note-width"

local function ApplyNotePanelWidth()
  if not notePanel then return end

  local width = notePanel.contentWidth or 0
  local anchorFrame = notePanel.matchFrame

  if anchorFrame then
    local ok, value = pcall(anchorFrame.GetWidth, anchorFrame)
    local anchorWidth = ok and tonumber(value) or nil
    if anchorWidth and anchorWidth > width then width = anchorWidth end
  end

  if width <= 0 or width == notePanel.appliedWidth then return end
  notePanel.appliedWidth = width
  notePanel:SetWidth(width)
end

-- anchorFrame: what the note hangs under. matchFrame: the frame whose width it
-- should grow to, read from the next shared-driver tick onwards for the reason
-- ApplyMoneyPanelWidth documents -- a width read during this call still
-- describes the previous tooltip's contents.
function U.ShowTooltipNote(anchorFrame, text, matchFrame)
  if not anchorFrame or type(text) ~= "string" or text == "" then
    U.HideTooltipNote()
    return nil
  end

  if not notePanel then
    notePanel = U.CreatePanel(UIParent, {
      name = "UnrealUITooltipNote",
      width = 10,
      height = 10,
    })
    pcall(notePanel.SetFrameStrata, notePanel, "TOOLTIP")
    notePanel.label = U.CreateLabel(notePanel, {
      size = M.fontSize.small,
      color = M.color.textDim,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
    })
    if notePanel.label then
      notePanel.label:SetPoint("TOPLEFT", notePanel, "TOPLEFT",
                              NOTE_PANEL_INSET, -NOTE_PANEL_INSET)
    end
    notePanel:Hide()
  end

  if not notePanel.label then return nil end
  notePanel.label:SetText(text)

  notePanel.contentWidth = LabelWidth(notePanel.label) + NOTE_PANEL_INSET * 2
  notePanel.matchFrame = nil
  notePanel.appliedWidth = nil
  ApplyNotePanelWidth()

  notePanel:SetHeight(NOTE_ROW_HEIGHT + NOTE_PANEL_INSET * 2)
  notePanel:ClearAllPoints()
  notePanel:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
  notePanel:Show()
  -- rendering.parent_alpha_not_propagated: the text is shown explicitly.
  notePanel.label:Show()

  notePanel.matchFrame = matchFrame
  if matchFrame then
    U.RegisterUpdate(NOTE_WIDTH_TICKER, 0, ApplyNotePanelWidth)
  else
    U.UnregisterUpdate(NOTE_WIDTH_TICKER)
  end

  return notePanel
end

function U.HideTooltipNote()
  U.UnregisterUpdate(NOTE_WIDTH_TICKER)
  if notePanel then
    notePanel.matchFrame = nil
    notePanel:Hide()
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
-- Arrow toggles
--
-- A texture-only open/close control: unrealUI's own arrow art on no backdrop
-- at all, so it can sit directly on the game world beside a block of content
-- that collapses. Central rather than module-local because the design rules
-- ask for the smallest shared component before a local variant, and "this
-- block opens and closes" is one shape wherever it appears.
--
-- States are carried by the glyph's own alpha rather than by a border colour,
-- since there is no border here to colour: the art is already the accent
-- yellow, and knowledge.json / rendering.parent_alpha_not_propagated means the
-- value has to be written on the texture, not on the button.
--
-- media/arrow.tga is authored pointing right. The left direction is the same
-- rectangle sampled backwards; four-argument SetTexCoord is BEHAVIOR_VERIFIED
-- on this client (knowledge.json /
-- textures.rle_512_tga_atlas_four_arg_supported) but a *reversed* rectangle
-- specifically is not. If a build ever draws both directions identically, the
-- fix is a mirrored TGA at its own path, not a different call.
--
-- options: name, size (glyph height), width/height (hit area), direction,
--          onClick
-- ---------------------------------------------------------------------------
function U.CreateArrowToggle(parent, options)
  options = options or {}

  local glyphHeight = tonumber(options.size) or ARROW_GLYPH_HEIGHT
  local glyphWidth = math.max(1, math.floor(glyphHeight * ARROW_ASPECT + 0.5))

  local button = CreateFrame("Button", options.name, parent or UIParent)
  button:SetWidth(tonumber(options.width) or (glyphWidth + 4))
  button:SetHeight(tonumber(options.height) or glyphHeight)
  pcall(button.EnableMouse, button, true)

  local glyph = button:CreateTexture(nil, "OVERLAY")
  glyph:SetWidth(glyphWidth)
  glyph:SetHeight(glyphHeight)
  glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
  if not pcall(glyph.SetTexture, glyph, M.texture.arrow) then glyph:Hide() end
  button.glyph = glyph
  button.uuiArrowEnabled = true

  local function Refresh()
    local alpha = ARROW_ALPHA_DEFAULT
    if not button.uuiArrowEnabled then
      alpha = ARROW_ALPHA_DISABLED
    elseif button.uuiArrowPushed then
      alpha = ARROW_ALPHA_PUSHED
    elseif button.uuiArrowHover then
      alpha = ARROW_ALPHA_HOVER
    end
    pcall(glyph.SetAlpha, glyph, alpha)
  end

  function button.SetDirection(direction)
    if direction ~= "left" then direction = "right" end
    if button.uuiArrowDirection == direction then return end
    button.uuiArrowDirection = direction
    if direction == "left" then
      pcall(glyph.SetTexCoord, glyph, 1, 0, 0, 1)
    else
      pcall(glyph.SetTexCoord, glyph, 0, 1, 0, 1)
    end
  end

  function button.SetEnabled(enabled)
    enabled = enabled and true or false
    if button.uuiArrowEnabled == enabled then return end
    button.uuiArrowEnabled = enabled
    if enabled then
      pcall(button.Enable, button)
    else
      button.uuiArrowHover, button.uuiArrowPushed = nil, nil
      pcall(button.Disable, button)
    end
    Refresh()
  end

  -- Closures over `button`, never `this`: scripts.handler_arguments_direct.
  button:SetScript("OnEnter", function()
    button.uuiArrowHover = true
    Refresh()
  end)
  button:SetScript("OnLeave", function()
    button.uuiArrowHover = nil
    button.uuiArrowPushed = nil
    Refresh()
  end)
  button:SetScript("OnMouseDown", function()
    button.uuiArrowPushed = true
    Refresh()
  end)
  button:SetScript("OnMouseUp", function()
    button.uuiArrowPushed = nil
    Refresh()
  end)

  if type(options.onClick) == "function" then
    button:SetScript("OnClick", options.onClick)
  end

  button.SetDirection(options.direction)
  Refresh()

  return button
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
--          price (function -> copper amount or nil), onClick,
--          uncropped (true for addon-owned art, which has no stock icon bevel
--          to crop away)
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
    if options.uncropped then
      pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
    else
      pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    end
  else
    icon:Hide()
    if button.label then button.label:SetText(options.fallback or "?") end
  end
  button.icon = icon

  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(M.color.moverEdge))

    local line
    if type(options.detail) == "function" then line = options.detail() end
    U.ShowWindowTooltip(button, options.tooltipFrames or parent,
                        options.title, line)

    if type(options.price) == "function" then
      local copper = options.price()
      if tonumber(copper) then ShowPricePanel(button, copper) end
    end
  end)

  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(M.color.border))
    U.HideWindowTooltip()
    HidePricePanel()
  end)

  return button
end

-- ---------------------------------------------------------------------------
-- Window tooltips
--
-- A window's own controls (the bag and bank headers) show their GameTooltip
-- above the window, centred on the pointer's column, so it never covers the
-- window being used. It only drops down over the window when there is no room
-- above it, and it is always kept on screen.
--
-- Independent of the world tooltip's follow-cursor option: that option only
-- moves the default-anchored world tooltip (modules/tooltip.lua
-- placement.Apply), and this anchor is not one it takes over.
--
-- Evidence:
--   * GetCursorPosition divided by UIParent's effective scale is the verified
--     cursor-to-UI conversion (knowledge.json /
--     api.getcursorposition_usable_for_hit_testing).
--   * Width and height are read, never edge differences, and the tooltip's
--     own scale is folded in (frames.scaled_frame_edge_coordinates_mixed_space).
--     The windows are unscaled children of UIParent, so their GetTop is in
--     UIParent units.
--   * GameTooltip may report its previous size for a frame after being
--     repopulated (see modules/tooltip.lua placement.NoteOverflow), so the
--     placement is re-run on a short tick while the pointer stays on the
--     control rather than measured once.
--   * The tooltip is anchored to an addon-owned 1x1 guide, the pattern
--     modules/tooltip.lua already uses for its cursor mode.
-- ---------------------------------------------------------------------------
local windowTip = {
  GAP = 6,        -- between the window's top edge and the tooltip
  MARGIN = 4,     -- kept clear of every screen edge
  INTERVAL = 0.02,
  UPDATE_ID = "widgets.windowTooltip",
}

-- Highest top edge among the shown frames, in UIParent units.
function windowTip.Top(frames)
  if type(frames) == "function" then frames = frames() end
  if type(frames) ~= "table" or frames.GetTop then frames = { frames } end

  local top
  local i
  for i = 1, table.getn(frames) do
    local f = frames[i]
    if f then
      local shownOk, shown = pcall(f.IsVisible, f)
      local topOk, value = pcall(f.GetTop, f)
      if shownOk and shown and topOk and type(value) == "number" then
        if not top or value > top then top = value end
      end
    end
  end
  return top
end

-- The re-placement tick must never grab a tooltip that now belongs to someone
-- else: a control hidden under the pointer (its window closed) gets no
-- OnLeave, and the next world tooltip would otherwise be dragged onto this
-- guide. Ownership is judged from the anchor rather than from
-- GameTooltip:IsOwned, which has no runtime record here: once placed, a
-- tooltip that is no longer on this guide has been re-anchored by its new
-- owner.
function windowTip.StillOwned(state)
  local tip, owner = state.tip, state.owner
  local tipOk, tipShown = pcall(tip.IsVisible, tip)
  if not tipOk or not tipShown then return false end

  local ownerOk, ownerShown = pcall(owner.IsVisible, owner)
  if not ownerOk or not ownerShown then return false end

  if state.anchored then
    local _, relative = U.GetFramePoint(tip)
    if relative ~= windowTip.guide then return false end
  end
  return true
end

-- initial: the pass made from ShowWindowTooltip itself, before the tooltip is
-- shown. It skips the ownership test, which needs a visible, anchored tooltip:
-- a frame with no anchor yet may not report itself visible.
function windowTip.Place(initial)
  local state = windowTip.state
  local tip = state and state.tip
  if not tip or (not initial and not windowTip.StillOwned(state)) then
    U.UnregisterUpdate(windowTip.UPDATE_ID)
    windowTip.state = nil
    return
  end

  local ok, cx, cy = pcall(GetCursorPosition)
  local uiOk, uiScale, uiLeft, uiBottom, tipScale, width, height =
    pcall(function()
      return UIParent:GetEffectiveScale(), UIParent:GetLeft(),
             UIParent:GetBottom(), tip:GetEffectiveScale(),
             tip:GetWidth(), tip:GetHeight()
    end)
  if not ok or not uiOk or type(cx) ~= "number" or type(cy) ~= "number" or
     type(uiScale) ~= "number" or uiScale <= 0 or
     type(tipScale) ~= "number" or tipScale <= 0 or
     type(width) ~= "number" or type(height) ~= "number" then return end

  local ratio = tipScale / uiScale
  width, height = width * ratio, height * ratio
  cx = cx / uiScale - (tonumber(uiLeft) or 0)
  cy = cy / uiScale - (tonumber(uiBottom) or 0)

  local margin = windowTip.MARGIN
  local screenWidth, screenHeight = U.UIWidth(), U.UIHeight()

  local x = cx - width / 2
  x = math.min(x, screenWidth - margin - width)
  x = math.max(margin, x)

  local y = (windowTip.Top(state.frames) or cy) + windowTip.GAP
  y = math.min(y, screenHeight - margin - height)
  y = math.max(margin, y)

  if x ~= state.x or y ~= state.y then
    if not U.ApplyFramePoint(windowTip.guide, {
      point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y,
    }) then return end
    state.x, state.y = x, y
  end

  if not state.anchored then
    state.anchored = pcall(function()
      tip:ClearAllPoints()
      tip:SetPoint("BOTTOMLEFT", windowTip.guide, "BOTTOMLEFT", 0, 0)
    end)
  end
end

-- owner: the hovered control. frames: the window above which the tooltip
-- goes -- a frame, a list of frames, or a function returning either, so
-- attached trays that are open above the window count as part of it.
function U.ShowWindowTooltip(owner, frames, title, detail)
  local tip = U.G("GameTooltip")
  if not tip then return end

  if not windowTip.guide then
    windowTip.guide = CreateFrame("Frame", "UnrealUIWindowTooltipGuide",
                                  UIParent)
    windowTip.guide:SetWidth(1)
    windowTip.guide:SetHeight(1)
    windowTip.guide:EnableMouse(false)
  end

  pcall(tip.SetOwner, tip, owner, "ANCHOR_NONE")
  pcall(tip.SetText, tip, title)
  if detail then pcall(tip.AddLine, tip, detail, 0.65, 0.65, 0.65, 1) end

  -- Anchored before Show, so the tooltip never appears without a position.
  windowTip.state = { tip = tip, owner = owner, frames = frames }
  windowTip.Place(true)
  pcall(tip.Show, tip)
  -- Re-measured once shown: the size read before Show may be the previous
  -- content's.
  windowTip.Place(true)

  U.RegisterUpdate(windowTip.UPDATE_ID, windowTip.INTERVAL, function()
    windowTip.Place()
  end)
end

function U.HideWindowTooltip()
  U.UnregisterUpdate(windowTip.UPDATE_ID)
  local state = windowTip.state
  windowTip.state = nil
  -- Only hide a tooltip still on this guide, never one another frame has
  -- re-anchored since. Owner visibility is irrelevant here: the pointer has
  -- left the control, and the tooltip it opened goes with it.
  if not state or not state.tip then return end
  local _, relative = U.GetFramePoint(state.tip)
  if relative == windowTip.guide or not state.anchored then
    pcall(state.tip.Hide, state.tip)
  end
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
--
-- Modern WoW callers pass options.modernWow and get a second instance dressed
-- as the Modern WoW logout/resurrect popups are (modules/logout.lua): the
-- diamond-metal housing and the 128RedButton faces. It is a separate frame, so
-- no caller's flat dialog ever has to undo that art; U.ModernWowMetalFrame and
-- U.ModernWowRedButtonFace return false outside the theme, which falls back to
-- the flat instance.
local confirmDialog, confirmDialogWow

local function BuildConfirmDialog(wow)
  local suffix = wow and "ModernWow" or ""
  local dialog = U.CreatePanel(UIParent, {
    name = "UnrealUIConfirm" .. suffix,
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
    name = "UnrealUIConfirm" .. suffix .. "Cancel",
    text = U.L("COMMON_CANCEL"),
    width = 110,
    height = 24,
    onClick = function() dialog:Hide() end,
  })
  dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)

  dialog.accept = U.CreateButton(dialog, {
    name = "UnrealUIConfirm" .. suffix .. "Accept",
    text = U.L("COMMON_ACCEPT"),
    width = 110,
    height = 24,
  })
  dialog.accept:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)

  dialog:Hide()
  return dialog
end

-- Modern WoW face for one confirm button: flat backdrop off, the red
-- three-slice on, hover painted from the button's own enter/leave.
local function DressConfirmWowButton(button, width, height)
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, height)
  if not U.ModernWowRedButtonFace(button, height) then return false end
  U.SetBackdropShown(button, false)

  -- A texture created on a button can stay hidden until shown explicitly
  -- (modules/character.lua, skillunlearn.icon_field.v1).
  local face = button.uuiModernWowAction
  pcall(face.left.Show, face.left)
  pcall(face.middle.Show, face.middle)
  pcall(face.right.Show, face.right)

  U.PostHookScript(button, "OnEnter", function()
    U.ModernWowPaintRedButton(button, true)
  end)
  U.PostHookScript(button, "OnLeave", function()
    U.ModernWowPaintRedButton(button, false)
  end)
  if type(U.ModernWowRedButtonInput) == "function" then
    U.ModernWowRedButtonInput(button)
  end
  if button.label then
    U.SetStockFont(button.label, M.fontSize.normal, M.color.text)
    U.CenterButtonLabel(button.label, button)
  end
  return true
end

-- Returns the dressed dialog, or nil when the theme's art is unavailable.
local function BuildConfirmDialogWow()
  if type(U.ModernWowMetalFrame) ~= "function" or
     type(U.ModernWowRedButtonFace) ~= "function" then
    return nil
  end
  local token = M.modernWow and M.modernWow.confirmDialog
  if not token then return nil end

  local dialog = BuildConfirmDialog(true)
  -- The metal frame follows the dialog's own anchors; its width/height
  -- arguments only size the corner arms, so the panel itself is resized.
  pcall(dialog.SetWidth, dialog, token.width)
  pcall(dialog.SetHeight, dialog, token.height)
  if not U.ModernWowMetalFrame(dialog, token.width, token.height) then
    return nil
  end
  U.SetBackdropShown(dialog, false)
  if dialog.text then
    U.SetStockFont(dialog.text, M.fontSize.normal, M.color.text)
  end

  -- The pair shares the width inside the metal sides, as the logout popups'
  -- buttons do (M.modernWow.corpsePopupButton).
  local button = M.modernWow.corpsePopupButton
  local width = math.min(token.buttonWidth,
    (token.width - 2 * button.sideInset - button.pairGap) / 2)
  if not DressConfirmWowButton(dialog.accept, width, button.height) or
     not DressConfirmWowButton(dialog.cancel, width, button.height) then
    return nil
  end
  dialog.accept:ClearAllPoints()
  dialog.accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -button.pairGap / 2,
                         token.buttonBottom)
  dialog.cancel:ClearAllPoints()
  dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", button.pairGap / 2,
                         token.buttonBottom)
  return dialog
end

-- options: text, detail, acceptText, cancelText, onAccept, onCancel, owner,
-- centered, modernWow, modernWowModule
--
-- `owner` is an opaque tag so a caller can take its own dialog down again
-- (U.HideConfirm(owner)) without cancelling one another window put up.
-- options.moneyCopper (a copper amount) shows the gold/silver/copper price
-- row instead of plain detail text; leave it nil for a normal confirm.
function U.ShowConfirm(options)
  options = options or {}
  local dialog
  local modernWow = options.modernWow and
    (U.GetActiveThemeStyle() == "modern-wow" or
     (type(options.modernWowModule) == "string" and
      type(U.ClassicModernModuleEnabled) == "function" and
      U.ClassicModernModuleEnabled(options.modernWowModule)))
  if modernWow then
    if confirmDialogWow == nil then
      local ok, built = pcall(BuildConfirmDialogWow)
      confirmDialogWow = ok and built or false
    end
    dialog = confirmDialogWow or nil
  end
  if not dialog then
    if not confirmDialog then confirmDialog = BuildConfirmDialog() end
    dialog = confirmDialog
  end
  -- One confirmation at a time, whichever instance put it up.
  if confirmDialog and confirmDialog ~= dialog then confirmDialog:Hide() end
  if confirmDialogWow and confirmDialogWow ~= dialog then
    confirmDialogWow:Hide()
  end
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

  -- Cancel is normally just "put the dialog away", which is why the build
  -- above already wires it. A caller that offers a real second choice --
  -- modules/bags.lua asking whether a bulk run should include the favourite
  -- items in it -- passes onCancel and gets that branch instead. Re-set on
  -- every show so one caller's callback cannot outlive its dialog.
  dialog.cancel:SetScript("OnClick", function()
    dialog:Hide()
    if type(options.onCancel) == "function" then options.onCancel() end
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
  local dialogs = { confirmDialog, confirmDialogWow }
  local i
  for i = 1, 2 do
    local dialog = dialogs[i]
    if dialog and (not owner or dialog.uuiOwner == owner) then dialog:Hide() end
  end
end

-- Mouse-wheel scrolling for an addon-owned list.
--
-- Wheel input is confirmed dead on a plain addon Frame here: it is swallowed by
-- the binding/camera layer before any OnMouseWheel script runs
-- (knowledge.json / scripts.addon_wheel_binding_unavailable). The widget type
-- is what decides it. A focused probe on 2026-09-20
-- (professionwheel.plain_scrollframe_lua.v1, BEHAVIOR_VERIFIED) measured that a
-- ScrollFrame created by this addon -- no template needed -- does receive the
-- wheel through a Lua-set OnMouseWheel, with zero camera zooms while the cursor
-- was over it. professionwheel.template_scrollframe_covered.v1 measured that
-- the delivery survives a mouse-enabled Button drawn on top, so the catcher can
-- sit under a list's own rows without taking their clicks.
--
-- The catcher is therefore a ScrollFrame with a scroll child (the construction
-- the probe verified), never mouse-enabled, kept below the rows. It scrolls
-- nothing itself: it only reports direction, because the list it serves paints
-- rows from an offset rather than moving a scroll child.
--
-- `onDelta` is called with 1 for a wheel-up tick and -1 for wheel-down. This
-- client reports arg1 as a raw delta (-15 was measured, not vanilla's -1), so
-- only its sign is used.
function U.CreateWheelCatcher(parent, onDelta)
  if not parent or type(onDelta) ~= "function" then return nil end
  local ok, frame = pcall(CreateFrame, "ScrollFrame", nil, parent)
  if not ok or not frame then return nil end
  pcall(function()
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel())
  end)
  local childOk, child = pcall(CreateFrame, "Frame", nil, frame)
  if childOk and child then
    pcall(function()
      child:SetWidth(1)
      child:SetHeight(1)
      frame:SetScrollChild(child)
    end)
  end
  pcall(frame.EnableMouseWheel, frame, true)
  pcall(frame.SetScript, frame, "OnMouseWheel", function()
    local delta = tonumber(arg1)
    if not delta or delta == 0 then return end
    pcall(onDelta, delta > 0 and 1 or -1)
  end)
  return frame
end

-- Size a list label to its own text without ever giving it a width.
--
-- FontString:GetStringWidth is CLAMPED by the width currently set on this
-- client, and does not settle until the next frame
-- (knowledge.json / widgets.fontstring_stringwidth_clamped_by_setwidth,
-- BEHAVIOR_VERIFIED 2026-09-20: 108 unconstrained, 39 at width 40; after
-- SetWidth(245) the same string still measured 37).
--
-- The measure-then-shrink idiom -- SetWidth(room), then
-- SetWidth(min(room, GetStringWidth() + 1)) -- therefore latches: a recycled
-- row measures the width its PREVIOUS entry left behind, shrinks to it, and
-- because a set width wraps rather than truncates here (no SetWordWrap,
-- SetMaxLines or GetNumLines exist), the name folds into a one-word-per-line
-- column that spills over neighbouring rows.
--
-- So no width is set at all. An unconstrained FontString auto-sizes to its
-- text (GetWidth 210.49 against a string width of 210, measured), which is
-- exactly what a trailing count or icon needs to anchor against, and it can
-- never wrap. A name genuinely too long for the row is trimmed with an
-- ellipsis instead, measured the only way that reads true here: with no width
-- set.
function U.FitLabelText(label, text, room)
  if not label then return end
  text = text or ""
  pcall(label.SetWidth, label, 0)
  pcall(label.SetText, label, text)
  if type(room) ~= "number" or room < 1 then return end
  local function Width()
    local ok, value = pcall(label.GetStringWidth, label)
    return (ok and tonumber(value)) or 0
  end
  if Width() <= room then return end
  local trimmed = text
  while string.len(trimmed) > 1 do
    trimmed = string.sub(trimmed, 1, string.len(trimmed) - 1)
    pcall(label.SetText, label, trimmed .. "...")
    if Width() <= room then return end
  end
end
