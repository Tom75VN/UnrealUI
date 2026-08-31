-- unrealUI :: core/windowdrag.lua
--
-- Adds a drag handle to native stock window headers so windows with no
-- Vanilla title-bar (Quest Log, Spellbook, Character, World Map, ...) can be
-- repositioned by the user, independent of unrealUI's edit/mover mode.
--
-- Reuses the Button-handle drag recipe verified in core/mover.lua (knowledge.
-- json / frames.movable_drag_requires_button_handle): a Button parented to the
-- frame it moves, SetMovable immediately before each drag, a throwaway
-- StartMoving/StopMovingOrSizing pair before the real StartMoving, and
-- SetFrameLevel to raise the handle above the frame's own content. Unlike
-- mover.lua this handle only spans the header strip -- not the whole frame --
-- so window content and buttons underneath it stay clickable, and it is
-- always active rather than gated behind edit mode.

local U = UnrealUI

-- Twice the former 24px strip: large enough to grab comfortably without
-- covering an excessive amount of the interactive content below the header.
-- Callers can override this per interface when its layout needs another size.
local HEADER_HEIGHT = 48
local HEADER_INSET = 26
local WINDOW_GAP = 10
local SCREEN_MARGIN = 10
-- Keep the drag surface just above the window background while allowing the
-- window's normal child controls to remain above it and receive mouse input.
-- The offset stays relative to the parent so background windows cannot jump
-- ahead merely because their drag handles were created later.
local HANDLE_LEVEL_OFFSET = 1
local dragCount = 0
local windowStates = {}
local frameStates = {}
local CapturePosition

local function IsShown(state)
  if not state or not state.frame or not state.frame.IsShown then return false end
  local ok, shown = pcall(state.frame.IsShown, state.frame)
  return ok and shown and true or false
end

local function PointFactor(point, low, high)
  if type(point) ~= "string" then return 0.5 end
  if string.find(point, low, 1, true) then return 0 end
  if string.find(point, high, 1, true) then return 1 end
  return 0.5
end

-- Window bounds use the same UIParent-relative anchor arithmetic as mover.lua.
-- Do not use GetLeft/GetRight/GetTop/GetBottom here: this client reports mixed
-- coordinate spaces for scaled frames (knowledge.json /
-- frames.scaled_frame_edge_coordinates_mixed_space).
local function CurrentPosition(state)
  local point, relative, relativePoint, x, y = U.GetFramePoint(state.frame, 1)
  if not point then return nil end

  -- A nil relative frame means the parent. Every registered top-level window
  -- is parented to UIParent; an explicit non-UIParent anchor cannot safely be
  -- converted into UIParent coordinates without the broken edge methods.
  if relative and relative ~= UIParent then return nil end
  return {
    point = point,
    relativePoint = relativePoint or point,
    x = x,
    y = y,
  }
end

local function WindowBounds(state, position)
  if not state or type(position) ~= "table" then return nil end

  local widthOk, width = pcall(state.frame.GetWidth, state.frame)
  local heightOk, height = pcall(state.frame.GetHeight, state.frame)
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
  return {
    left = left,
    right = left + width,
    bottom = bottom,
    top = bottom + height,
    width = width,
    height = height,
  }
end

local function Overlaps(a, b)
  return a and b and a.left < b.right and a.right > b.left and
         a.bottom < b.top and a.top > b.bottom
end

local function ClampCandidate(left, bottom, width, height)
  local minLeft, minBottom = SCREEN_MARGIN, SCREEN_MARGIN
  local maxLeft = U.UIWidth() - SCREEN_MARGIN - width
  local maxBottom = U.UIHeight() - SCREEN_MARGIN - height

  if maxLeft < minLeft then
    left = (U.UIWidth() - width) / 2
  else
    left = math.max(minLeft, math.min(maxLeft, left))
  end
  if maxBottom < minBottom then
    bottom = (U.UIHeight() - height) / 2
  else
    bottom = math.max(minBottom, math.min(maxBottom, bottom))
  end
  return left, bottom
end

local function CandidateIsClear(candidate, blockers)
  local i
  for i = 1, table.getn(blockers) do
    if Overlaps(candidate, blockers[i]) then return false end
  end
  return true
end

local function AddCandidate(candidates, original, blockers, left, bottom)
  left, bottom = ClampCandidate(left, bottom, original.width, original.height)
  local candidate = {
    left = left,
    right = left + original.width,
    bottom = bottom,
    top = bottom + original.height,
    width = original.width,
    height = original.height,
  }
  if not CandidateIsClear(candidate, blockers) then return end

  candidate.distance = math.abs(left - original.left) +
                       math.abs(bottom - original.bottom)
  table.insert(candidates, candidate)
end

local function ApplyBottomLeft(state, left, bottom)
  return U.ApplyFramePoint(state.frame, {
    point = "BOTTOMLEFT",
    relativePoint = "BOTTOMLEFT",
    x = left,
    y = bottom,
  })
end

-- If neither side of a centred first window has enough room, moving only the
-- second window cannot solve the collision even when both windows fit on the
-- screen together. Reflow the pair as a unit in that case. This fallback is
-- intentionally limited to one blocker: the requested two-window guarantee is
-- deterministic, while packing an arbitrary number of large stock windows is
-- not always geometrically possible.
local function ReflowPair(state, original, blocker)
  local other = blocker and blocker.state
  if not other then return false end

  local layouts = {}
  local availableWidth = U.UIWidth() - SCREEN_MARGIN * 2
  local availableHeight = U.UIHeight() - SCREEN_MARGIN * 2

  if original.width + WINDOW_GAP + blocker.width <= availableWidth then
    local totalWidth = original.width + WINDOW_GAP + blocker.width
    local maxGroupLeft = U.UIWidth() - SCREEN_MARGIN - totalWidth

    local groupLeft = (original.left +
      (blocker.left - original.width - WINDOW_GAP)) / 2
    groupLeft = math.max(SCREEN_MARGIN, math.min(maxGroupLeft, groupLeft))
    local _, movingBottom = ClampCandidate(groupLeft, original.bottom,
                                            original.width, original.height)
    local _, otherBottom = ClampCandidate(groupLeft + original.width + WINDOW_GAP,
                                           blocker.bottom,
                                           blocker.width, blocker.height)
    table.insert(layouts, {
      movingLeft = groupLeft,
      movingBottom = movingBottom,
      otherLeft = groupLeft + original.width + WINDOW_GAP,
      otherBottom = otherBottom,
    })

    groupLeft = (blocker.left +
      (original.left - blocker.width - WINDOW_GAP)) / 2
    groupLeft = math.max(SCREEN_MARGIN, math.min(maxGroupLeft, groupLeft))
    _, otherBottom = ClampCandidate(groupLeft, blocker.bottom,
                                     blocker.width, blocker.height)
    _, movingBottom = ClampCandidate(groupLeft + blocker.width + WINDOW_GAP,
                                      original.bottom,
                                      original.width, original.height)
    table.insert(layouts, {
      movingLeft = groupLeft + blocker.width + WINDOW_GAP,
      movingBottom = movingBottom,
      otherLeft = groupLeft,
      otherBottom = otherBottom,
    })
  end

  if original.height + WINDOW_GAP + blocker.height <= availableHeight then
    local totalHeight = original.height + WINDOW_GAP + blocker.height
    local maxGroupBottom = U.UIHeight() - SCREEN_MARGIN - totalHeight

    local groupBottom = (original.bottom +
      (blocker.bottom - original.height - WINDOW_GAP)) / 2
    groupBottom = math.max(SCREEN_MARGIN, math.min(maxGroupBottom, groupBottom))
    local movingLeft = ClampCandidate(original.left, groupBottom,
                                      original.width, original.height)
    local otherLeft = ClampCandidate(blocker.left,
                                     groupBottom + original.height + WINDOW_GAP,
                                     blocker.width, blocker.height)
    table.insert(layouts, {
      movingLeft = movingLeft,
      movingBottom = groupBottom,
      otherLeft = otherLeft,
      otherBottom = groupBottom + original.height + WINDOW_GAP,
    })

    groupBottom = (blocker.bottom +
      (original.bottom - blocker.height - WINDOW_GAP)) / 2
    groupBottom = math.max(SCREEN_MARGIN, math.min(maxGroupBottom, groupBottom))
    otherLeft = ClampCandidate(blocker.left, groupBottom,
                               blocker.width, blocker.height)
    movingLeft = ClampCandidate(original.left,
                                groupBottom + blocker.height + WINDOW_GAP,
                                original.width, original.height)
    table.insert(layouts, {
      movingLeft = movingLeft,
      movingBottom = groupBottom + blocker.height + WINDOW_GAP,
      otherLeft = otherLeft,
      otherBottom = groupBottom,
    })
  end

  if table.getn(layouts) == 0 then return false end

  local best, i = nil, nil
  for i = 1, table.getn(layouts) do
    local layout = layouts[i]
    layout.distance = math.abs(layout.movingLeft - original.left) +
                      math.abs(layout.movingBottom - original.bottom) +
                      math.abs(layout.otherLeft - blocker.left) +
                      math.abs(layout.otherBottom - blocker.bottom)
    if not best or layout.distance < best.distance then best = layout end
  end

  local otherApplied = ApplyBottomLeft(other, best.otherLeft, best.otherBottom)
  local movingApplied = ApplyBottomLeft(state, best.movingLeft, best.movingBottom)
  return otherApplied and movingApplied
end

-- Moves only the window that was just opened or dropped. Saved user positions
-- remain the preferred single-window layout; the temporary side-by-side
-- placement is recalculated whenever another registered interface opens.
local function AvoidOverlap(state)
  if not state.avoidOverlap or not IsShown(state) then return false end

  local position = CurrentPosition(state)
  local original = WindowBounds(state, position)
  if not original then return false end

  local blockers = {}
  local overlaps = false
  local i
  for i = 1, table.getn(windowStates) do
    local other = windowStates[i]
    if other ~= state and other.avoidOverlap and IsShown(other) then
      local bounds = WindowBounds(other, CurrentPosition(other))
      if bounds then
        bounds.state = other
        table.insert(blockers, bounds)
        if Overlaps(original, bounds) then overlaps = true end
      end
    end
  end
  if not overlaps then return false end

  local candidates = {}
  for i = 1, table.getn(blockers) do
    local blocker = blockers[i]
    AddCandidate(candidates, original, blockers,
                 blocker.right + WINDOW_GAP, original.bottom)
    AddCandidate(candidates, original, blockers,
                 blocker.left - original.width - WINDOW_GAP, original.bottom)
    AddCandidate(candidates, original, blockers,
                 original.left, blocker.bottom - original.height - WINDOW_GAP)
    AddCandidate(candidates, original, blockers,
                 original.left, blocker.top + WINDOW_GAP)
  end
  if table.getn(candidates) == 0 then
    if table.getn(blockers) == 1 and ReflowPair(state, original, blockers[1]) then
      return true
    end
    U.Debug("windowdrag " .. state.id ..
            ": no non-overlapping screen position is large enough")
    return false
  end

  local best = candidates[1]
  for i = 2, table.getn(candidates) do
    if candidates[i].distance < best.distance then best = candidates[i] end
  end

  return ApplyBottomLeft(state, best.left, best.bottom)
end

local function ScheduleOverlapCheck(state, saveAdjustedPosition)
  if not state.avoidOverlap then return end
  U.DeferOnce("windowdrag.overlap." .. state.id, function()
    if AvoidOverlap(state) and saveAdjustedPosition then
      CapturePosition(state)
    end
  end)
end

-- Re-check a registered window after one of its own controls changes its
-- dimensions. Most stock windows are fixed-size; Quest Log's detail toggle is
-- the current caller.
function U.RefreshWindowOverlap(frame)
  local state = frameStates[frame]
  if not state then return false end
  ScheduleOverlapCheck(state, false)
  return true
end

local function ReadDragPosition(frame)
  local point, _, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if not point then return nil end
  return { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function PositionChanged(before, after)
  if not before or not after then return true end
  return before.point ~= after.point or
         before.relativePoint ~= after.relativePoint or
         before.x ~= after.x or before.y ~= after.y
end

local function StartDrag(state)
  -- Start immediately from OnMouseDown. If the client later delivers its
  -- threshold-based OnDragStart too, do not restart an already active move.
  if state.dragging then return true end

  local frame = state.frame
  if not pcall(frame.SetMovable, frame, true) then
    U.Error("windowdrag " .. state.id .. ": SetMovable failed")
    return false
  end

  if pcall(frame.StartMoving, frame) then
    pcall(frame.StopMovingOrSizing, frame)
  end

  if not pcall(frame.StartMoving, frame) then
    U.Error("windowdrag " .. state.id .. ": StartMoving failed")
    return false
  end

  state.dragging = true
  state.dragStartPosition = ReadDragPosition(frame)
  return true
end

CapturePosition = function(state)
  local point, relative, relativePoint, x, y = U.GetFramePoint(state.frame, 1)
  if not point then
    U.Debug("windowdrag " .. state.id .. ": no readable anchor after drag")
    return false
  end
  return U.SavePosition(state.id, point, relativePoint, x, y)
end

local function StopDrag(state)
  if not state.dragging then return false end
  state.dragging = false
  pcall(state.frame.StopMovingOrSizing, state.frame)
  local before = state.dragStartPosition
  state.dragStartPosition = nil
  if not PositionChanged(before, ReadDragPosition(state.frame)) then
    return true
  end
  local captured = CapturePosition(state)
  ScheduleOverlapCheck(state, true)
  return captured
end

local function ApplyStoredPosition(state)
  local saved = U.GetPosition(state.id)
  if not saved then return false end
  return U.ApplyFramePoint(state.frame, saved)
end

local function RaiseHandle(state)
  if not state or not state.handle then return false end
  local levelOk, level = pcall(state.frame.GetFrameLevel, state.frame)
  if not levelOk or not tonumber(level) then return false end
  local handleLevel = level + state.handleLevelOffset
  if not pcall(state.handle.SetFrameLevel, state.handle, handleLevel) then
    return false
  end

  local controls = state.interactiveFrames
  if type(controls) == "table" then
    local i
    for i = 1, table.getn(controls) do
      local control = controls[i]
      if control and control.SetFrameLevel then
        local offset = state.interactiveFrameOffsets and
                       tonumber(state.interactiveFrameOffsets[control]) or 1
        pcall(control.SetFrameLevel, control, handleLevel + offset)
      end
    end
  end
  return true
end

local function IsLeftMouseButton(a, b)
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

-- id       stable string key; stored under "window."..id so it cannot collide
--          with core/mover.lua's own position ids.
-- frame    the native frame to move.
-- options  { headerHeight, headerInset, headerLevelOffset, interactiveFrames,
--            interactiveFrameOffsets, avoidOverlap } -- headerInset reserves
--          space on the right edge for a close button. interactiveFrames are
--          kept one frame level above the drag handle unless their frame-keyed
--          offset table says otherwise. avoidOverlap defaults to true; modal
--          child windows can opt out explicitly.
function U.MakeWindowDraggable(id, frame, options)
  if type(id) ~= "string" or not frame then
    U.Error("MakeWindowDraggable requires an id and a frame")
    return nil
  end

  options = options or {}
  if frameStates[frame] then return frameStates[frame] end

  local state = {
    id = "window." .. id,
    frame = frame,
    dragging = false,
    avoidOverlap = options.avoidOverlap ~= false,
    handleLevelOffset = tonumber(options.headerLevelOffset) or HANDLE_LEVEL_OFFSET,
    interactiveFrames = options.interactiveFrames,
    interactiveFrameOffsets = options.interactiveFrameOffsets,
  }
  table.insert(windowStates, state)
  frameStates[frame] = state

  dragCount = dragCount + 1
  local handle = CreateFrame("Button", "UnrealUIWindowDrag" .. dragCount, frame)
  handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
                  -(options.headerInset or HEADER_INSET), 0)
  handle:SetHeight(options.headerHeight or HEADER_HEIGHT)
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)

  handle:SetScript("OnMouseDown", function(a, b)
    if IsLeftMouseButton(a, b) then StartDrag(state) end
  end)
  handle:SetScript("OnMouseUp", function(a, b)
    if IsLeftMouseButton(a, b) then StopDrag(state) end
  end)
  -- Keep the native drag route as a fallback for any mouse path that does not
  -- expose press/release scripts. Both handlers are safe to receive twice.
  handle:SetScript("OnDragStart", function() StartDrag(state) end)
  handle:SetScript("OnDragStop", function() StopDrag(state) end)

  state.handle = handle
  RaiseHandle(state)
  pcall(frame.SetMovable, frame, true)
  U.PostHookScript(frame, "OnShow", function()
    -- Native panel management may change the frame level between openings.
    -- Reassert the window's configured handle/control ordering before it
    -- receives the next mouse press.
    RaiseHandle(state)
    ApplyStoredPosition(state)
    -- Some native Show functions keep changing anchors after OnShow returns
    -- (QuestLog_OnShow is one known example). Resolve on the next shared-driver
    -- tick, after that call chain has settled and before the next layout sticks.
    ScheduleOverlapCheck(state, false)
  end)
  U.PostHookScript(frame, "OnHide", function()
    if state.dragging then StopDrag(state) end
  end)
  ApplyStoredPosition(state)
  if IsShown(state) then ScheduleOverlapCheck(state, false) end

  return state
end

-- Some controls are created after their window (Spellbook's feature toggles
-- are current examples). Register them when they become available so they are
-- raised immediately and included in every later OnShow reassertion.
function U.AddWindowDragInteractiveFrame(frame, control, levelOffset)
  local state = frameStates[frame]
  if not state or not control then return false end

  if type(state.interactiveFrames) ~= "table" then
    state.interactiveFrames = {}
  end

  local found = false
  local i
  for i = 1, table.getn(state.interactiveFrames) do
    if state.interactiveFrames[i] == control then
      found = true
      break
    end
  end
  if not found then table.insert(state.interactiveFrames, control) end

  if tonumber(levelOffset) then
    state.interactiveFrameOffsets = state.interactiveFrameOffsets or {}
    state.interactiveFrameOffsets[control] = tonumber(levelOffset)
  end
  return RaiseHandle(state)
end
