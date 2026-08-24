-- unrealUI :: core/mover.lua
--
-- The shared mover system. Modules register the frames they want the user to
-- be able to place; unlocking shows a drag handle over each one.
--
-- Deliberately small. This is not pfUI's mover/config framework: it provides
-- only an alignment grid, nearby-mover magnets and pixel nudging -- no
-- per-frame scale editing or configuration machinery. Only intended unrealUI
-- elements are ever registered. modules/minimap.lua is the one exception that
-- registers a native frame (MinimapCluster) rather than an unrealUI-owned one:
-- the map itself is still never reskinned or replaced, it is just given a drag
-- handle like everything else here.

local U = UnrealUI
local M = U.media

local movers = {}       -- id -> entry
local moverOrder = {}
local unlocked = false
local activeMover
local grid, editPanel, editKeys
local IsEntryVisible

-- Edit-mode grid. Sized in UIParent units, which is the only space layout may
-- be driven from (frames.json context: GetScreenWidth and UIParent:GetWidth are
-- not the same unit space on this client).
local GRID_SIZE = 20
local MAGNET_DISTANCE = 8

-- ---------------------------------------------------------------------------
-- Position handling
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted (BEHAVIOR_VERIFIED)
-- is the whole reason this file reads anchors through U.GetFramePoint: GetPoint
-- hands back the relative frame as a name string and inverts Y. That record
-- also lists two failed approaches, both avoided here:
--
--   * persisting the raw GetPoint tuple as if it were Blizzard-compatible
--   * recapturing a point and immediately clearing/re-applying it
--
-- so a drop is captured and stored, and the frame is left exactly where the
-- user released it rather than being re-anchored on the spot.
-- ---------------------------------------------------------------------------
local function ApplyStoredPosition(entry)
  local saved = U.GetPosition(entry.id)
  local position = saved or entry.default
  if not position then return false end

  local applied = U.ApplyFramePoint(entry.frame, position)
  if not applied then
    U.Debug("mover " .. entry.id .. ": failed to apply position")
    return false
  end

  if saved then
    U.Debug("mover " .. entry.id .. ": restored saved position")
  end
  return true
end

-- Snapping
--
-- The grid is only usable if a dropped frame is actually pulled onto it, and
-- the drag itself belongs to the client: StartMoving owns the frame's position
-- until StopMovingOrSizing, so the offsets can only be adjusted after the drop.
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted lists "recapturing
-- then immediately clearing/reapplying the same point" as a failed approach,
-- while the same record confirms that applying a *stored* point with SetPoint
-- restores a frame correctly. The snap therefore captures and stores in the
-- drop handler, and re-applies from the store on the next shared-driver tick
-- rather than inside the handler itself.
local pendingSnap

local function ShiftHeld()
  local fn = U.G("IsShiftKeyDown")
  if type(fn) ~= "function" then return false end
  local ok, held = pcall(fn)
  if not ok then return false end
  return held and held ~= 0 and true or false
end

local function SnapValue(value)
  value = tonumber(value) or 0
  return math.floor(value / GRID_SIZE + 0.5) * GRID_SIZE
end

-- Magnetic snapping uses the stored UIParent-relative positions and frame
-- dimensions, never GetLeft/GetRight/GetTop/GetBottom. The latter give mixed
-- coordinate spaces for scaled frames on this client, whereas mover positions
-- and dimensions are already in UIParent's layout space.
local function PointFactor(point, low, high)
  if type(point) ~= "string" then return 0.5 end
  if string.find(point, low, 1, true) then return 0 end
  if string.find(point, high, 1, true) then return 1 end
  return 0.5
end

local function MoverBounds(entry, position)
  if not entry or type(position) ~= "table" then return nil end

  local widthOk, width = pcall(entry.frame.GetWidth, entry.frame)
  local heightOk, height = pcall(entry.frame.GetHeight, entry.frame)
  width, height = tonumber(width), tonumber(height)
  if not widthOk or not heightOk or not width or not height or
     width <= 0 or height <= 0 then return nil end

  local x = tonumber(position.x) or 0
  local y = tonumber(position.y) or 0
  local relativePoint = position.relativePoint or position.point
  local left = U.UIWidth() * PointFactor(relativePoint, "LEFT", "RIGHT") + x -
               width * PointFactor(position.point, "LEFT", "RIGHT")
  local bottom = U.UIHeight() * PointFactor(relativePoint, "BOTTOM", "TOP") + y -
                 height * PointFactor(position.point, "BOTTOM", "TOP")
  return left, left + width, bottom, bottom + height
end

local function ClosestMagnet(aLow, aHigh, bLow, bHigh)
  local best, distance = nil, MAGNET_DISTANCE + 1
  local delta = bHigh - aLow
  if math.abs(delta) < distance then best, distance = delta, math.abs(delta) end
  delta = bLow - aHigh
  if math.abs(delta) < distance then best, distance = delta, math.abs(delta) end
  delta = bLow - aLow
  if math.abs(delta) < distance then best, distance = delta, math.abs(delta) end
  delta = bHigh - aHigh
  if math.abs(delta) < distance then best, distance = delta, math.abs(delta) end
  delta = ((bLow + bHigh) - (aLow + aHigh)) / 2
  if math.abs(delta) < distance then best, distance = delta, math.abs(delta) end
  if distance > MAGNET_DISTANCE then return nil end
  return best
end

local function SnapToMovers(entry, point, relativePoint, x, y)
  local moving = { point = point, relativePoint = relativePoint, x = x, y = y }
  local left, right, bottom, top = MoverBounds(entry, moving)
  if not left then return x, y, false, false end

  local bestX, bestY, bestXDistance, bestYDistance = nil, nil,
    MAGNET_DISTANCE + 1, MAGNET_DISTANCE + 1
  local i
  for i = 1, table.getn(moverOrder) do
    local other = movers[moverOrder[i]]
    if other ~= entry and IsEntryVisible(other) then
      local position = U.GetPosition(other.id) or other.default
      local otherLeft, otherRight, otherBottom, otherTop =
        MoverBounds(other, position)
      if otherLeft then
        local dx = ClosestMagnet(left, right, otherLeft, otherRight)
        if dx and math.abs(dx) < bestXDistance then
          bestX, bestXDistance = dx, math.abs(dx)
        end
        local dy = ClosestMagnet(bottom, top, otherBottom, otherTop)
        if dy and math.abs(dy) < bestYDistance then
          bestY, bestYDistance = dy, math.abs(dy)
        end
      end
    end
  end

  return x + (bestX or 0), y + (bestY or 0), bestX ~= nil, bestY ~= nil
end

local function ApplyPendingSnap()
  local entry = pendingSnap
  pendingSnap = nil
  U.UnregisterUpdate("mover.snap")
  if not entry then return end

  local stored = U.GetPosition(entry.id)
  if stored then U.ApplyFramePoint(entry.frame, stored) end
end

local function CapturePosition(entry)
  local point, relative, relativePoint, x, y = U.GetFramePoint(entry.frame, 1)
  if not point then
    U.Debug("mover " .. entry.id .. ": no readable anchor after drag")
    return false
  end

  -- Stored positions are always UIParent-relative. If the drag left the frame
  -- anchored to something else, say so rather than silently storing an offset
  -- that will be re-applied against a different origin.
  if relative and relative ~= UIParent then
    U.Debug("mover " .. entry.id ..
            ": anchored to a non-UIParent frame after drag; storing anyway")
  end

  -- Shift is the escape hatch for placements the grid or magnets cannot
  -- express. An absent or failing modifier read safely behaves as "not held".
  local snapped = false
  if not ShiftHeld() then
    local magneticX, magneticY
    if relative == UIParent then
      x, y, magneticX, magneticY =
        SnapToMovers(entry, point, relativePoint, x, y)
    else
      magneticX, magneticY = false, false
    end
    if not magneticX then
      local sx = SnapValue(x)
      snapped = snapped or sx ~= x
      x = sx
    end
    if not magneticY then
      local sy = SnapValue(y)
      snapped = snapped or sy ~= y
      y = sy
    end
    snapped = snapped or magneticX or magneticY
  end

  local saved = U.SavePosition(entry.id, point, relativePoint, x, y)

  if saved and snapped then
    pendingSnap = entry
    U.RegisterUpdate("mover.snap", 0, ApplyPendingSnap)
  end

  return saved
end

-- ---------------------------------------------------------------------------
-- Dragging
--
-- The compact DB has no record at all for RegisterForDrag, StartMoving,
-- SetMovable or frame-level mouse input, so none of it can be assumed. The one
-- implementation of frame dragging demonstrably working on this client is
-- UnrealPfUI's dragger (modules/unlock.lua / CreateDragger), and the parts of
-- its recipe that unrealUI's first attempt did not follow are reproduced here:
--
--   * the handle is a **Button**, not a plain Frame. Buttons take mouse input
--     without EnableMouse, and Button is the only widget type this client is
--     known to deliver OnDragStart to.
--   * the handle is parented to the frame it moves and covers it with
--     SetAllPoints, rather than floating over it as a UIParent child.
--   * it is raised with SetFrameLevel rather than a strata change.
--   * SetMovable is applied immediately before each drag, not once at
--     registration.
--   * the real StartMoving is preceded by a StartMoving/StopMovingOrSizing
--     pair, which collapses a multi-point anchor down to the single point the
--     client will actually move.
--
-- Only the behaviour is reused; none of pfUI's selection, grid, scaling or dock
-- machinery is reproduced.
--
-- Failures here are reported through U.Error, not U.Debug: a mover that cannot
-- be dragged is the whole feature failing, and debug output is off by default.
-- ---------------------------------------------------------------------------
local function StartDrag(entry)
  local frame = entry.frame

  if not pcall(frame.SetMovable, frame, true) then
    U.Error("mover " .. entry.id .. ": SetMovable failed; frame cannot be moved")
    return false
  end

  if pcall(frame.StartMoving, frame) then
    pcall(frame.StopMovingOrSizing, frame)
  end

  if not pcall(frame.StartMoving, frame) then
    U.Error("mover " .. entry.id .. ": StartMoving failed; frame will not drag")
    return false
  end

  entry.dragging = true
  return true
end

local function StopDrag(entry)
  if not entry.dragging then return false end
  entry.dragging = false

  pcall(entry.frame.StopMovingOrSizing, entry.frame)
  return CapturePosition(entry)
end

local function SetActiveMover(entry)
  activeMover = entry
end

-- ---------------------------------------------------------------------------
-- Drag handle
--
-- Created on first unlock and reused afterwards. knowledge.json /
-- scripts.child_onupdate_unreliable applies here: the handle is populated
-- synchronously at creation and never waits on an OnUpdate tick to become
-- usable.
--
-- The counters exist so /uui check can report whether the client delivered
-- mouse and drag events at all. Without them a handle that never receives
-- OnDragStart is indistinguishable from one whose StartMoving failed.
-- ---------------------------------------------------------------------------
local handleCount = 0
local HANDLE_LEVEL_OFFSET = 10

local function CreateHandle(entry)
  handleCount = handleCount + 1

  -- Named because an unnamed Button gives the client nothing to report in an
  -- error, and the mover handles are exactly what a drag failure is about.
  local handle = CreateFrame("Button", "UnrealUIMoverHandle" .. handleCount,
                             entry.frame)
  handle:SetAllPoints(entry.frame)
  handle:RegisterForDrag("LeftButton")

  -- A Button is mouse-enabled by default; this is belt and braces, and is
  -- pcall'd because the call is not verified on this client either.
  pcall(handle.EnableMouse, handle, true)

  local levelOk, level = pcall(entry.frame.GetFrameLevel, entry.frame)
  if levelOk and tonumber(level) then
    pcall(handle.SetFrameLevel, handle, level + HANDLE_LEVEL_OFFSET)
  end

  U.CreateBackdrop(handle, {
    background = M.color.mover,
    border = M.color.moverEdge,
  })

  -- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
  -- can accept SetText without ever showing a FontString, so the label is a
  -- FontString unrealUI creates and owns rather than the Button's own text.
  local label = U.CreateLabel(handle, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormal",
  })
  if label then
    label:SetPoint("CENTER", handle, "CENTER", 0, 0)
    label:SetText(entry.label)
  end
  handle.label = label

  -- knowledge.json / scripts.handler_arguments_direct: handler argument shape
  -- is not guaranteed, so these close over `entry` instead of reading `this`.
  handle:SetScript("OnDragStart", function()
    SetActiveMover(entry)
    entry.dragStarts = entry.dragStarts + 1
    StartDrag(entry)
  end)

  handle:SetScript("OnDragStop", function()
    entry.dragStops = entry.dragStops + 1
    StopDrag(entry)
  end)

  handle:SetScript("OnClick", function() SetActiveMover(entry) end)

  -- OnEnter is instrumentation as much as highlight: if the enter count stays
  -- at zero the client is not routing mouse input to the handle at all, which
  -- is a different failure from a drag that starts and does not move.
  handle:SetScript("OnEnter", function()
    entry.enters = entry.enters + 1
    U.SetBorderColor(handle, 0.2, 1.0, 0.8, 1)
  end)

  handle:SetScript("OnLeave", function()
    U.SetBorderColor(handle, M.Unpack(M.color.moverEdge))
  end)

  entry.handle = handle
  return handle
end

local function HideHandle(entry)
  if not entry.handle then return end
  if entry.handle.label then entry.handle.label:Hide() end
  entry.handle:Hide()
end

-- A module may register a frame that is not always part of the layout -- a
-- disabled action bar keeps its stored position but must not offer a handle to
-- drag. options.visible is that predicate; without one a mover is always shown.
IsEntryVisible = function(entry)
  if type(entry.visible) ~= "function" then return true end
  local ok, visible = pcall(entry.visible)
  if not ok then return true end
  return visible and true or false
end

local function ShowHandle(entry)
  if not IsEntryVisible(entry) then
    HideHandle(entry)
    return
  end

  if not entry.handle then CreateHandle(entry) end
  entry.handle:Show()
  -- rendering.parent_alpha_not_propagated: children are shown and hidden
  -- explicitly rather than relying on the parent's visibility carrying.
  if entry.handle.label then entry.handle.label:Show() end
end

-- ---------------------------------------------------------------------------
-- Edit-mode overlay
--
-- The grid is plain textures on one full-screen frame: behavior.json /
-- textures.pfui_bar_path.v1 verifies that path, and it keeps the overlay off
-- backdrop edges, which are not reliably rasterised here.
--
-- Lines are laid out from UIParent's centre outwards so the grid is symmetric
-- and the centre axes land exactly on 0,0 -- the offsets a snapped drop
-- produces are multiples of GRID_SIZE from that same origin.
-- ---------------------------------------------------------------------------

local function CreateGridLine(vertical, offset, color, length, thickness)
  local line = grid:CreateTexture(nil, "BACKGROUND")
  line:SetTexture(M.texture.plain)
  U.SetColor(line, M.Unpack(color))

  if vertical then
    line:SetWidth(thickness)
    line:SetHeight(length)
    line:SetPoint("CENTER", UIParent, "CENTER", offset, 0)
  else
    line:SetWidth(length)
    line:SetHeight(thickness)
    line:SetPoint("CENTER", UIParent, "CENTER", 0, offset)
  end

  return line
end

local function CreateGrid()
  grid = CreateFrame("Frame", "UnrealUIGrid", UIParent)
  grid:SetAllPoints(UIParent)
  pcall(grid.SetFrameStrata, grid, "BACKGROUND")
  -- Keep the decoration above any BACKGROUND-strata shade (quick binding
  -- uses one to swallow world clicks) while remaining below normal UI.
  pcall(grid.SetFrameLevel, grid, 1)
  -- The grid is decoration; it must never eat a click meant for a handle.
  pcall(grid.EnableMouse, grid, false)

  local width, height = U.UIWidth(), U.UIHeight()
  local thickness = U.BorderSize()
  local offset

  CreateGridLine(true, 0, M.color.gridAxis, height, thickness)
  CreateGridLine(false, 0, M.color.gridAxis, width, thickness)

  offset = GRID_SIZE
  while offset < width / 2 do
    CreateGridLine(true, offset, M.color.grid, height, thickness)
    CreateGridLine(true, -offset, M.color.grid, height, thickness)
    offset = offset + GRID_SIZE
  end

  offset = GRID_SIZE
  while offset < height / 2 do
    CreateGridLine(false, offset, M.color.grid, width, thickness)
    CreateGridLine(false, -offset, M.color.grid, width, thickness)
    offset = offset + GRID_SIZE
  end

  grid:Hide()
end

-- The edit panel is the only way out of edit mode that does not need a slash
-- command. It is deliberately not registered as a mover: it belongs to the mode
-- rather than to the layout.
local function CreateEditPanel()
  editPanel = U.CreatePanel(UIParent, {
    name = "UnrealUIEditPanel",
    width = 280,
    height = 128,
  })
  editPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  pcall(editPanel.SetFrameStrata, editPanel, "HIGH")

  local title = U.CreateLabel(editPanel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  if title then
    title:SetPoint("TOP", editPanel, "TOP", 0, -12)
    title:SetText("Edit UI")
  end
  editPanel.title = title

  local hint = U.CreateLabel(editPanel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if hint then
    hint:SetPoint("TOP", editPanel, "TOP", 0, -34)
    hint:SetText("|cfff5ae0aShift + drag|r: free movement")
  end
  editPanel.hint = hint

  local hint2 = U.CreateLabel(editPanel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if hint2 then
    hint2:SetPoint("TOP", editPanel, "TOP", 0, -50)
    hint2:SetText("|cfff5ae0aNear another element|r: magnet")
  end
  editPanel.hint2 = hint2

  local hint3 = U.CreateLabel(editPanel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    width = 252,
  })
  if hint3 then
    hint3:SetPoint("TOP", editPanel, "TOP", 0, -67)
    hint3:SetText("|cfff5ae0aClick a frame|r: keyboard arrows move 1 px")
  end
  editPanel.hint3 = hint3

  editPanel.save = U.CreateButton(editPanel, {
    name = "UnrealUIEditSave",
    text = "Save and exit",
    width = 140,
    height = 24,
    onClick = function() U.LockUI() end,
  })
  editPanel.save:SetPoint("BOTTOM", editPanel, "BOTTOM", -38, 12)

  editPanel.reset = U.CreateButton(editPanel, {
    name = "UnrealUIEditReset",
    text = "Reset",
    width = 68,
    height = 24,
    onClick = function() U.ResetPositions() end,
  })
  editPanel.reset:SetPoint("BOTTOM", editPanel, "BOTTOM", 68, 12)

  editPanel:Hide()
end

-- Keyboard input is deliberately scoped to edit mode. Runtime evidence shows
-- a shown keyboard-enabled Frame captures every key and cannot propagate the
-- rest of the input layer, but that is safe while this modal edit mode is open.
-- It must be a plain Frame and use OnKeyDown; Buttons and OnKeyUp do not work.
local function ResolveKey(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  local legacy = U.G("arg1")
  if type(legacy) == "string" then return legacy end
  return nil
end

local function NudgeActiveMover(x, y)
  local entry = activeMover
  if not entry or entry.dragging then return false end

  local position = U.GetPosition(entry.id) or entry.default
  if not position then
    local point, relative, relativePoint, offsetX, offsetY =
      U.GetFramePoint(entry.frame, 1)
    if not point or relative ~= UIParent then
      U.Print("Drag " .. entry.label .. " once before nudging it.")
      return false
    end
    position = { point = point, relativePoint = relativePoint,
                 x = offsetX, y = offsetY }
  end

  local saved = U.SavePosition(entry.id, position.point, position.relativePoint,
                               (tonumber(position.x) or 0) + x,
                               (tonumber(position.y) or 0) + y)
  if saved then U.ApplyFramePoint(entry.frame, U.GetPosition(entry.id)) end
  return saved
end

local function CreateEditKeys()
  editKeys = CreateFrame("Frame", "UnrealUIMoverKeys", UIParent)
  pcall(editKeys.SetAllPoints, editKeys, UIParent)
  pcall(editKeys.SetFrameStrata, editKeys, "FULLSCREEN_DIALOG")
  pcall(editKeys.EnableKeyboard, editKeys, true)
  pcall(editKeys.EnableMouse, editKeys, false)

  editKeys:SetScript("OnKeyDown", function(a, b)
    local key = ResolveKey(a, b)
    if key == "LEFT" then
      NudgeActiveMover(-1, 0)
    elseif key == "RIGHT" then
      NudgeActiveMover(1, 0)
    elseif key == "UP" then
      NudgeActiveMover(0, 1)
    elseif key == "DOWN" then
      NudgeActiveMover(0, -1)
    elseif key == "ESCAPE" then
      U.LockUI()
    end
  end)
  editKeys:Hide()
end

-- rendering.parent_alpha_not_propagated: children are shown and hidden
-- explicitly rather than relying on the parent's visibility carrying.
local function ShowEditOverlay()
  if not editPanel then CreateEditPanel() end
  if not editKeys then CreateEditKeys() end

  U.ShowAlignmentGrid()
  editPanel:Show()
  editKeys:Show()
  if editPanel.title then editPanel.title:Show() end
  if editPanel.hint then editPanel.hint:Show() end
  if editPanel.hint2 then editPanel.hint2:Show() end
  if editPanel.hint3 then editPanel.hint3:Show() end
  if editPanel.save then editPanel.save:Show() end
  if editPanel.reset then editPanel.reset:Show() end
end

local function HideEditOverlay()
  U.HideAlignmentGrid()
  if editKeys then editKeys:Hide() end
  if not editPanel then return end

  if editPanel.title then editPanel.title:Hide() end
  if editPanel.hint then editPanel.hint:Hide() end
  if editPanel.hint2 then editPanel.hint2:Hide() end
  if editPanel.hint3 then editPanel.hint3:Hide() end
  if editPanel.save then editPanel.save:Hide() end
  if editPanel.reset then editPanel.reset:Hide() end
  editPanel:Hide()
end

function U.GridSize()
  return GRID_SIZE
end

-- The alignment grid is shared by edit mode and other full-screen placement
-- modes. Callers own their mode lifetime and must hide it when they close.
function U.ShowAlignmentGrid()
  if not grid then CreateGrid() end
  grid:Show()
  return grid
end

function U.HideAlignmentGrid()
  if grid then grid:Hide() end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- id       stable string key, also the SavedVariables key
-- frame    the frame the user drags
-- options  { label = "Player", default = { point, relativePoint, x, y },
--            visible = function() return true end }
function U.RegisterMover(id, frame, options)
  if type(id) ~= "string" or not frame then
    U.Error("RegisterMover requires an id and a frame")
    return nil
  end
  if movers[id] then
    U.Error("mover already registered: " .. id)
    return movers[id]
  end

  options = options or {}

  local entry = {
    id = id,
    frame = frame,
    label = options.label or id,
    default = options.default,
    visible = options.visible,
    dragging = false,
    -- Measured drag activity; reported by U.MoverReport.
    enters = 0,
    dragStarts = 0,
    dragStops = 0,
  }

  movers[id] = entry
  table.insert(moverOrder, id)

  pcall(frame.SetMovable, frame, true)
  -- Position is applied immediately, not deferred to a tick.
  ApplyStoredPosition(entry)

  if unlocked then ShowHandle(entry) end
  return entry
end

function U.IsUnlocked()
  return unlocked
end

function U.UnlockUI()
  unlocked = true
  if U.db then U.db.locked = false end

  SetActiveMover(nil)
  ShowEditOverlay()

  local i
  for i = 1, table.getn(moverOrder) do
    ShowHandle(movers[moverOrder[i]])
  end

  U.Print("Edit mode. Drag, snap, or nudge with arrow keys. " ..
          "|cffffff00Save and exit|r when done.")
end

function U.LockUI()
  unlocked = false
  if U.db then U.db.locked = true end

  HideEditOverlay()

  local i
  for i = 1, table.getn(moverOrder) do
    HideHandle(movers[moverOrder[i]])
  end

  U.Print("Layout saved. Edit mode closed.")
end

function U.ToggleUI()
  if unlocked then U.LockUI() else U.UnlockUI() end
end

-- Drops every saved position and puts each registered frame back on its
-- module-supplied default.
function U.ResetPositions()
  U.ClearAllPositions()

  local i, restored = nil, 0
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if ApplyStoredPosition(entry) then restored = restored + 1 end
  end

  U.Print("Reset " .. restored .. " frame position(s) to defaults.")
  return restored
end

function U.MoverCount()
  return table.getn(moverOrder)
end

-- Reports what the client actually did with each mover, so a drag that does not
-- work produces measured detail instead of a shrug. `enters` distinguishes "no
-- mouse input reached the handle" from "input arrived but the move failed", and
-- movable/mouse are read back rather than assumed from the setter succeeding.
function U.MoverReport()
  local report, i = {}, nil

  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    local line = {
      id = entry.id,
      enters = entry.enters,
      dragStarts = entry.dragStarts,
      dragStops = entry.dragStops,
      hasHandle = entry.handle and true or false,
      saved = U.GetPosition(entry.id) and true or false,
    }

    -- A readback of `false` is a real answer and must not be collapsed into the
    -- "call unavailable" case, so ok is tested on its own.
    local ok, value = pcall(entry.frame.IsMovable, entry.frame)
    if ok then line.movable = value else line.movable = "?" end

    line.mouse = "-"
    if entry.handle then
      ok, value = pcall(entry.handle.GetObjectType, entry.handle)
      if ok and value then line.handleType = value else line.handleType = "?" end

      ok, value = pcall(entry.handle.IsMouseEnabled, entry.handle)
      if ok then line.mouse = value else line.mouse = "?" end
    end

    local point, _, _, x, y = U.GetFramePoint(entry.frame, 1)
    line.point = point or "none"
    line.x = x
    line.y = y

    table.insert(report, line)
  end

  return report
end
