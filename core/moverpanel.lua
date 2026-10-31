-- unrealUI :: core/moverpanel.lua
--
-- The contextual settings panel that follows the selected mover in edit mode.
--
-- Selecting a mover handle is the player saying "this element". A module that
-- has settings for that element registers a panel here, and core/mover.lua
-- shows it beside the handle as soon as the handle is selected. Nothing about
-- a bar, a frame or a unit lives in this file: it owns the window, the
-- placement, the title and the show/hide lifecycle, and the module owns what
-- goes inside.
--
-- This was the action bar panel's own machinery (modules/actionbarconfig.lua).
-- It moved here whole when the unit frames needed the same behaviour, so the
-- two are one component rather than two lookalikes -- rules/unreal-ui-design.md
-- "Do not build local variants".
--
-- A spec may be registered for several ids (the action bars register one spec
-- for every bar). The frame is then built once and retargeted on each show,
-- which is why Refresh is handed the id that is being shown.

local U = UnrealUI
local M = U.media

-- Registered specs by mover id. A spec carries its own built frame, so two ids
-- sharing a spec share the frame.
local panels = {}

local active = {
  id = nil, spec = nil, anchor = nil,
  pin = nil, frozen = false,
}

-- Contextual placement. The panel sits beside the anchor it configures, with a
-- small gap, and is kept clear of the screen edges.
local ANCHOR_GAP = 8
local SCREEN_MARGIN = 8

-- Shared interior geometry. A builder lays its controls out from CONTENT_TOP
-- downwards, offset by PAD from the panel's left edge, so every contextual
-- panel keeps the same inset and the same distance below its title.
local PAD = 12
local CONTENT_TOP = -44

-- Close button: the red X at the size and inset edit mode's metal-framed
-- windows share (M.editModeChrome).
local CLOSE_SIZE = M.editModeChrome.close.size
local CLOSE_INSET = M.editModeChrome.close.right
-- The header's rules stop clear of that corner on both sides, which keeps the
-- title centred on the panel instead of shifting it away from the button.
local HEADER_INSET = CLOSE_INSET + CLOSE_SIZE + 4

-- Scale (%) row, added below a panel's own content for a scalable mover
-- (core/mover.lua, `scalable = true`). A scalable mover with no panel of its
-- own gets SCALE_ONLY, one shared frame retargeted on each show.
-- The row's caption sits SCALE_CAPTION above the track's top edge (14 tall,
-- 4 gap; U.CreateSlider), so the track is placed that far below where the row
-- starts -- anchoring the track at the old panel bottom raised the caption
-- into the panel's last row. Panels end 12 below their content, so the row
-- starts 4 above the
-- old bottom: an 8 gap. Added height: caption 18 + track 8 + 2 + value box
-- 16 + PAD, less the 4 the row starts above the old bottom.
local SCALE_CAPTION = 18
local SCALE_ROW = SCALE_CAPTION + 8 + 2 + 16 + PAD - 4
local SCALE_SLIDER_WIDTH = 150
local SCALE_ONLY = {
  name = "UnrealUIMoverScaleSettings",
  width = 200 + PAD * 2,
  -- Header only: the scale row then starts at CONTENT_TOP.
  height = 48,
  build = function() return {}, nil end,
}

function U.MoverPanelPad() return PAD end

-- Edit mode's housing under every theme: the diamond-metal frame in place of the flat backdrop. Recomputed on each show,
-- since a panel's height depends on the mover it is shown for.
local function DrawChrome(frame, width, height)
  if type(U.ModernWowMetalFrame) ~= "function" then return end
  if U.ModernWowMetalFrame(frame, width, height, true) then
    U.SetBackdropShown(frame, false)
  end
end

-- The game settings window's control art on a panel's controls, leaving the
-- layout each module built around the flat controls as it is.
local function StyleControls(widgets)
  if type(U.StyleGameSettingsWidgets) == "function" then
    U.StyleGameSettingsWidgets(widgets, true)
  end
end
function U.MoverPanelContentTop() return CONTENT_TOP end

-- ---------------------------------------------------------------------------
-- Visibility
--
-- Settings widgets are composite controls (uuiParts), not single frames, so
-- showing the panel is not one Show call on the window.
-- ---------------------------------------------------------------------------
-- The same three cases modules/settings.lua walks for a page's widgets: a
-- control that owns its visibility (dropdowns), a composite control that is a
-- table of parts, and a plain region with an optional owned label.
local function SetWidgetShown(widget, shown)
  if not widget then return end

  if type(widget.uuiSetShown) == "function" then
    widget.uuiSetShown(shown)
    return
  end

  if widget.uuiParts then
    local i
    for i = 1, table.getn(widget.uuiParts) do
      SetWidgetShown(widget.uuiParts[i], shown)
    end
    return
  end

  if shown then widget:Show() else widget:Hide() end
  if widget.label then
    if shown then widget.label:Show() else widget.label:Hide() end
  end
end

local function SetSpecShown(spec, shown)
  if not spec or not spec.frame then return end
  SetWidgetShown(spec.frame, shown)
  -- Shown on demand by ShowMoverPanel, only for a scalable mover.
  if not shown and spec.scaleSlider then
    SetWidgetShown(spec.scaleSlider, false)
  end
  local i
  for i = 1, table.getn(spec.widgets or {}) do
    SetWidgetShown(spec.widgets[i], shown)
  end
end

local function PanelHeight(spec)
  local height = spec.height
  if type(height) == "function" then height = height() end
  return tonumber(height) or 200
end

local function Scalable(id)
  return type(U.MoverScalable) == "function" and U.MoverScalable(id)
end

-- The panel's full height for one mover: its own content, plus the scale row.
local function ShownHeight(spec, id)
  local height = PanelHeight(spec)
  if Scalable(id) then height = height + SCALE_ROW end
  return height
end

-- The registered spec when it is available, else the shared scale-only panel
-- for a scalable mover, else nil.
local function SpecFor(id)
  if type(id) ~= "string" then return nil end
  local spec = panels[id]
  if spec and (type(spec.available) ~= "function" or spec.available(id)) then
    return spec
  end
  if Scalable(id) then return SCALE_ONLY end
  return nil
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function BuildSpec(spec)
  if spec.frame then return true end
  if type(spec.build) ~= "function" then return false end

  local frame = U.CreatePanel(UIParent, {
    name = spec.name,
    width = spec.width,
    height = PanelHeight(spec),
  })
  -- The edit window, the advanced drawer and the alignment guides all sit at
  -- HIGH; this panel shares that strata and takes a level above them, since it
  -- is placed by its anchor and may land over any of them.
  pcall(frame.SetFrameStrata, frame, "HIGH")
  pcall(frame.SetFrameLevel, frame, 30)
  -- The panel is placed over the layout it configures, and mover handles take
  -- mouse input wherever they are. Swallow clicks on the panel's own surface so
  -- a press next to a control cannot start dragging the element underneath it.
  -- Same gate the colour picker uses over the settings window (core/widgets.lua).
  pcall(frame.EnableMouse, frame, true)
  spec.frame = frame

  spec.widgets = {}

  local contentWidth = spec.width - PAD * 2
  spec.header = U.CreateSectionHeader(frame, {
    text = "", width = spec.width - HEADER_INSET * 2, x = HEADER_INSET,
    y = -12, gap = 30,
  })
  table.insert(spec.widgets, spec.header)

  -- Closing hides the panel only: the handle stays selected (U.CloseMoverPanel
  -- -> U.DismissMoverPanel) and a plain click on it brings the panel back.
  spec.close = U.CreateRedCloseButton(frame, {
    name = spec.name and (spec.name .. "Close") or nil,
    size = CLOSE_SIZE,
    onClick = function() U.CloseMoverPanel() end,
  })
  if spec.close then
    spec.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CLOSE_INSET,
                        -M.editModeChrome.close.top)
    table.insert(spec.widgets, spec.close)
  end

  local widgets, refresh = spec.build(frame, CONTENT_TOP, contentWidth)
  local i
  for i = 1, table.getn(widgets or {}) do
    table.insert(spec.widgets, widgets[i])
  end
  StyleControls(widgets)
  spec.refresh = refresh

  SetSpecShown(spec, false)
  return true
end

-- Built on the first scalable mover a spec is shown for. It always acts on
-- the mover that is selected now (active.id), so a shared spec needs one row.
local function ShowScaleRow(spec, id)
  if not Scalable(id) then
    if spec.scaleSlider then SetWidgetShown(spec.scaleSlider, false) end
    return
  end

  if not spec.scaleSlider then
    local min, max, step = U.MoverScaleRange()
    spec.scaleSlider = U.CreateSlider(spec.frame, {
      name = spec.name and (spec.name .. "Scale") or nil,
      text = U.L("MOVER_SCALE"),
      width = SCALE_SLIDER_WIDTH,
      boxWidth = 60,
      min = min,
      max = max,
      step = step,
      value = 100,
      -- Rescaling grows the anchor under the panel; hold the panel still.
      onInputStart = function() U.FreezeMoverPanel() end,
      onInput = function(v)
        if active.id then U.PreviewMoverScale(active.id, v) end
      end,
      onChange = function(v)
        if active.id then U.SetMoverScale(active.id, v) end
      end,
    })
    StyleControls({ spec.scaleSlider })
  end

  -- Re-anchored on each show: a spec's own height can depend on the mover.
  spec.scaleSlider.SetPoint("TOPLEFT", spec.frame, "TOPLEFT", PAD,
                            4 - PanelHeight(spec) - SCALE_CAPTION)
  spec.scaleSlider.SetValue(U.GetMoverScale(id))
  SetWidgetShown(spec.scaleSlider, true)
end

-- The window is titled with the anchor's own label, so the panel names the
-- thing the player just clicked rather than a second name for the same element.
local function Title(spec, id, anchor)
  if anchor and type(anchor.label) == "string" and anchor.label ~= "" then
    return anchor.label
  end
  if type(spec.title) == "function" then return spec.title(id) or "" end
  return ""
end

-- ---------------------------------------------------------------------------
-- Placement
--
-- The side is chosen from the anchor's bounds in UIParent layout space
-- (U.MoverBounds), never from GetLeft/GetRight, which core/mover.lua records as
-- a mixed coordinate space for scaled frames on this client. Right is preferred,
-- then left, then above, then below; whichever side is used, the panel is kept
-- inside the screen along the other axis. The final anchor is relative to the
-- mover's own frame -- an unrealUI frame, the one relationship
-- rules/unreal-ui.md allows -- so the panel travels with the anchor as it is
-- dragged, and core/mover.lua calls back here on the drop to reconsider the side.
-- ---------------------------------------------------------------------------
local function Place()
  if active.frozen then return true end
  local spec, anchor = active.spec, active.anchor
  if not spec or not spec.frame or not anchor or not anchor.frame then
    return false
  end
  local frame = spec.frame

  frame:ClearAllPoints()

  local left, right, bottom, top = nil, nil, nil, nil
  if type(U.MoverBounds) == "function" then
    left, right, bottom, top = U.MoverBounds(anchor.id)
  end
  local screenWidth, screenHeight = U.UILayoutWidth(), U.UILayoutHeight()

  -- Nothing measurable to place against: sit against the anchor's right edge
  -- rather than reverting to a screen corner, which is what this panel is not.
  if not left or not screenWidth or screenWidth <= 0 or
     not screenHeight or screenHeight <= 0 then
    active.pin = nil
    frame:SetPoint("TOPLEFT", anchor.frame, "TOPRIGHT", ANCHOR_GAP, 0)
    return true
  end

  local width, height = spec.width, ShownHeight(spec, active.id)
  local roomRight = screenWidth - SCREEN_MARGIN - (right + ANCHOR_GAP)
  local roomLeft = (left - ANCHOR_GAP) - SCREEN_MARGIN
  local roomAbove = screenHeight - SCREEN_MARGIN - (top + ANCHOR_GAP)
  local roomBelow = (bottom - ANCHOR_GAP) - SCREEN_MARGIN

  local side
  if spec.preferVertical then
    -- A width slider inside a side-mounted panel would move its own track as
    -- the selected anchor grows, feeding the preview back into the cursor
    -- reading. Size-editing panels can stay centred over/under their anchor so
    -- horizontal resizing leaves the control itself still.
    if roomAbove >= height then side = "TOP"
    elseif roomBelow >= height then side = "BOTTOM"
    elseif roomRight >= width then side = "RIGHT"
    elseif roomLeft >= width then side = "LEFT"
    elseif roomAbove >= roomBelow then side = "TOP"
    else side = "BOTTOM"
    end
  else
    if roomRight >= width then side = "RIGHT"
    elseif roomLeft >= width then side = "LEFT"
    elseif roomAbove >= height then side = "TOP"
    elseif roomBelow >= height then side = "BOTTOM"
    elseif roomRight >= roomLeft then side = "RIGHT"
    else side = "LEFT"
    end
  end

  if side == "RIGHT" or side == "LEFT" then
    -- Level with the anchor's top edge, pushed back onto the screen if that
    -- would hang the panel off the top or bottom.
    local panelTop = top
    if panelTop > screenHeight - SCREEN_MARGIN then
      panelTop = screenHeight - SCREEN_MARGIN
    end
    if panelTop - height < SCREEN_MARGIN then
      panelTop = SCREEN_MARGIN + height
    end
    local y = panelTop - top
    if side == "RIGHT" then
      frame:SetPoint("TOPLEFT", anchor.frame, "TOPRIGHT", ANCHOR_GAP, y)
      active.pin = { point = "TOPLEFT", x = right + ANCHOR_GAP, y = panelTop }
    else
      frame:SetPoint("TOPRIGHT", anchor.frame, "TOPLEFT", -ANCHOR_GAP, y)
      active.pin = { point = "TOPRIGHT", x = left - ANCHOR_GAP, y = panelTop }
    end
    return true
  end

  -- Centred over or under the anchor, kept clear of the side edges.
  local centre = (left + right) / 2
  if centre - width / 2 < SCREEN_MARGIN then
    centre = SCREEN_MARGIN + width / 2
  end
  if centre + width / 2 > screenWidth - SCREEN_MARGIN then
    centre = screenWidth - SCREEN_MARGIN - width / 2
  end
  local x = centre - (left + right) / 2

  if side == "TOP" then
    frame:SetPoint("BOTTOM", anchor.frame, "TOP", x, ANCHOR_GAP)
    active.pin = { point = "BOTTOM", x = centre, y = top + ANCHOR_GAP }
  else
    frame:SetPoint("TOP", anchor.frame, "BOTTOM", x, -ANCHOR_GAP)
    active.pin = { point = "TOP", x = centre, y = bottom - ANCHOR_GAP }
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- id     -- mover id, exactly as registered with U.RegisterMover.
-- spec   -- { name, width, height, build, title, available, preferVertical }
--   width     panel width, including PAD on both sides.
--   height    number, or a function returning one when the content a class or
--             a client capability leaves out changes it.
--   build     function(frame, contentTop, contentWidth) -> widgets, Refresh.
--             Refresh is called with the id and the anchor on every show, so
--             one spec can serve several movers.
--   title     optional function(id) -> string, used when the mover has no label.
--   available optional function(id) -> boolean; false means no panel for that
--             mover right now (a reserved action bar, for one).
--   preferVertical optional boolean; try above/below before the side positions.
--             Used by live width controls so resizing cannot move their track.
function U.RegisterMoverPanel(id, spec)
  if type(id) ~= "string" or type(spec) ~= "table" or
     type(spec.build) ~= "function" then
    U.Error("RegisterMoverPanel requires a mover id and a spec with a build")
    return false
  end
  spec.width = tonumber(spec.width) or 240
  panels[id] = spec
  return true
end

function U.HasMoverPanel(id)
  return SpecFor(id) ~= nil
end

function U.ActiveMoverPanelId()
  return active.id
end

-- anchor is the selected mover: { id, frame, label }. core/mover.lua owns it.
function U.ShowMoverPanel(id, anchor)
  local spec = SpecFor(id)
  if not spec or type(anchor) ~= "table" or not anchor.frame then
    U.HideMoverPanel()
    return false
  end

  -- Another element's panel is on screen: take it down before this one goes up,
  -- since two specs may be two frames.
  if active.spec and active.spec ~= spec then SetSpecShown(active.spec, false) end

  if not BuildSpec(spec) then
    U.HideMoverPanel()
    return false
  end

  active.id, active.spec, active.anchor = id, spec, anchor
  active.pin, active.frozen = nil, false
  spec.frame:SetHeight(ShownHeight(spec, id))
  DrawChrome(spec.frame, spec.width, ShownHeight(spec, id))
  if spec.header then spec.header.SetText(Title(spec, id, anchor)) end
  if type(spec.refresh) == "function" then spec.refresh(id, anchor) end
  Place()
  SetSpecShown(spec, true)
  ShowScaleRow(spec, id)
  return true
end

-- The close button's action. It hides the panel but keeps the anchor selected
-- in core/mover.lua, so the anchor can be moved without the panel in the way.
-- The direct hide is the fallback for a panel that is somehow up with no
-- selection behind it.
function U.CloseMoverPanel()
  if type(U.DismissMoverPanel) == "function" and U.DismissMoverPanel() then
    return true
  end
  U.HideMoverPanel()
  return true
end

function U.HideMoverPanel()
  if active.spec then SetSpecShown(active.spec, false) end
  active.id, active.spec, active.anchor = nil, nil, nil
  active.pin, active.frozen = nil, false
end

-- Called by core/mover.lua once a drag is stored, to reconsider which side of
-- the anchor still has room for the panel.
function U.PlaceMoverPanel()
  if not active.spec then return false end
  -- An explicit placement request means the mover itself was dropped. Release
  -- any size-preview pin so the panel follows the element to its new home.
  active.frozen = false
  return Place()
end

-- A live size preview must not move the controls being dragged. Place records
-- the panel's current screen-space pin whenever it attaches the window to a
-- mover; freezing swaps to that equivalent UIParent point. It remains there
-- after the size is committed and is released by U.PlaceMoverPanel when the
-- mover itself is dropped, or by the normal hide/show selection lifecycle.
function U.FreezeMoverPanel()
  if active.frozen then return true end
  local frame, pin = active.spec and active.spec.frame, active.pin
  if not frame or not pin then return false end
  frame:ClearAllPoints()
  frame:SetPoint(pin.point, UIParent, "BOTTOMLEFT", pin.x, pin.y)
  active.frozen = true
  return true
end

-- A contextual panel and the settings window are two views of the same stored
-- settings, so whichever one wrote a value tells the other to re-read it.
function U.RefreshMoverPanel(id)
  if not active.spec or (id ~= nil and id ~= active.id) then return false end
  if active.spec.scaleSlider and Scalable(active.id) then
    active.spec.scaleSlider.SetValue(U.GetMoverScale(active.id))
  end
  if type(active.spec.refresh) ~= "function" then return false end
  active.spec.refresh(active.id, active.anchor)
  return true
end
