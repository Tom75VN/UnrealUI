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

local HEADER_HEIGHT = 24
local HEADER_INSET = 26
local dragCount = 0

local function StartDrag(state)
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
  return true
end

local function CapturePosition(state)
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
  return CapturePosition(state)
end

local function ApplyStoredPosition(state)
  local saved = U.GetPosition(state.id)
  if not saved then return false end
  return U.ApplyFramePoint(state.frame, saved)
end

-- id       stable string key; stored under "window."..id so it cannot collide
--          with core/mover.lua's own position ids.
-- frame    the native frame to move.
-- options  { headerHeight, headerInset } -- headerInset reserves space on the
--          right edge of the strip for a close button anchored there.
function U.MakeWindowDraggable(id, frame, options)
  if type(id) ~= "string" or not frame then
    U.Error("MakeWindowDraggable requires an id and a frame")
    return nil
  end

  options = options or {}
  local state = { id = "window." .. id, frame = frame, dragging = false }

  dragCount = dragCount + 1
  local handle = CreateFrame("Button", "UnrealUIWindowDrag" .. dragCount, frame)
  handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
                  -(options.headerInset or HEADER_INSET), 0)
  handle:SetHeight(options.headerHeight or HEADER_HEIGHT)
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)

  local levelOk, level = pcall(frame.GetFrameLevel, frame)
  if levelOk and tonumber(level) then
    pcall(handle.SetFrameLevel, handle, level + 10)
  end

  handle:SetScript("OnDragStart", function() StartDrag(state) end)
  handle:SetScript("OnDragStop", function() StopDrag(state) end)

  pcall(frame.SetMovable, frame, true)
  U.PostHookScript(frame, "OnShow", function() ApplyStoredPosition(state) end)
  ApplyStoredPosition(state)

  state.handle = handle
  return state
end
