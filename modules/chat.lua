-- unrealUI :: modules/chat.lua
--
-- Adds one explicit resize grip to the primary native chat window. Chat tabs,
-- channels, message handling and drawing remain owned by the client.

local U = UnrealUI
local M = U.media

local Chat = U.RegisterModule("chat")

local GRIP_SIZE = 20
local MIN_WIDTH = 180
local MIN_HEIGHT = 70
local LIVE_UPDATE_ID = "chat.resize.live"
local LOCK_UPDATE_ID = "chat.resize.lock"
local POSITION_UPDATE_ID = "chat.position.sync"
local POSITION_INTERVAL = 0.15
local RESTORE_PASSES = 8

local frame, grip, config
local dragging = false
local startFrameWidth, startFrameHeight, startFrameLeft, startFrameBottom
local startGripLeft, startGripBottom
local lastGripLeft, lastGripBottom
local lastGripShown
local lastSavedWidth, lastSavedHeight, lastSavedLeft, lastSavedBottom
local restorePasses = 0
local positionWasUnlocked = false

local function ReadNumber(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if ok and type(value) == "number" then return value end
  return nil
end

local function Clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function AnchorGrip()
  if not grip or not frame then return end
  grip:ClearAllPoints()
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

-- chat.lock_state_detection.v1 (SUPPORTED, BEHAVIOR_VERIFIED): the native
-- field is numeric 1 while General is locked and nil while it is unlocked.
-- ChatFrame1.locked stayed nil in both states and FCF_IsLocked was unavailable,
-- so neither is used as a fallback.
local function ChatIsLocked()
  if not frame then return true end
  local ok, value = pcall(function() return frame.isLocked end)
  return not ok or value == 1
end

local function ChatIsVisible()
  if not frame or type(frame.IsVisible) ~= "function" then return true end
  local ok, visible = pcall(frame.IsVisible, frame)
  if not ok then return true end
  return visible and true or false
end

local function SetGripShown(show)
  if not grip then return end
  show = show and true or false
  if show == lastGripShown then return end
  lastGripShown = show

  -- rendering.parent_alpha_not_propagated: toggle the texture explicitly with
  -- its Button instead of trusting child visibility to follow the parent.
  if show then
    grip:Show()
    if grip.icon then grip.icon:Show() end
  else
    if grip.icon then grip.icon:Hide() end
    grip:Hide()
  end
end

local function UpdateLockVisibility()
  -- A menu cannot normally change the lock during a drag. If it somehow does,
  -- finish the current interaction first rather than hiding its active Button.
  if dragging then return end
  SetGripShown(not ChatIsLocked() and ChatIsVisible())
end

local function SaveGeometry(width, height, left, bottom)
  if not config then return end
  width = U.Round(width)
  height = U.Round(height)
  left = U.Round(left)
  bottom = U.Round(bottom)

  if config.resized and width == lastSavedWidth and
     height == lastSavedHeight and left == lastSavedLeft and
     bottom == lastSavedBottom then
    return
  end

  config.resized = true
  config.width = width
  config.height = height
  config.left = left
  config.bottom = bottom
  lastSavedWidth, lastSavedHeight = width, height
  lastSavedLeft, lastSavedBottom = left, bottom
end

local function ApplyFrameGeometry(width, height, left, bottom)
  if not frame then return false end

  return pcall(function()
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
  end)
end

local function ApplyGeometry(width, height, left, bottom)
  local ok = ApplyFrameGeometry(width, height, left, bottom)
  -- Re-anchoring a frame during StartMoving breaks the native drag on this
  -- client. The live path therefore updates only the chat; the grip is put
  -- back into its corner after StopMovingOrSizing.
  if ok and not dragging then AnchorGrip() end
  return ok
end

local function RestoreSavedGeometry()
  if not config or not config.resized then return end

  local width = tonumber(config.width)
  local height = tonumber(config.height)
  local left = tonumber(config.left)
  local bottom = tonumber(config.bottom)
  if not (width and height and left and bottom) then return end

  width = Clamp(width, MIN_WIDTH, U.UIWidth() - left)
  height = Clamp(height, MIN_HEIGHT, U.UIHeight())
  bottom = Clamp(bottom, 0, U.UIHeight() - height)
  ApplyGeometry(width, height, left, bottom)
end

local function CaptureCurrentGeometry()
  if dragging or not frame then return false end

  local width = ReadNumber(frame, "GetWidth")
  local height = ReadNumber(frame, "GetHeight")
  local left = ReadNumber(frame, "GetLeft")
  local bottom = ReadNumber(frame, "GetBottom")
  if not (width and height and left and bottom) then return false end

  SaveGeometry(width, height, left, bottom)
  return true
end

local function UpdatePositionPersistence()
  -- The native chat performs late layout work during reload. Reapply the saved
  -- geometry for a short bounded window before accepting any native position
  -- as a new user placement; otherwise a late default layout would overwrite
  -- the correct SavedVariables values in memory.
  if restorePasses > 0 then
    RestoreSavedGeometry()
    restorePasses = restorePasses - 1
    positionWasUnlocked = not ChatIsLocked()
    return
  end

  local unlocked = not ChatIsLocked()
  if unlocked and ChatIsVisible() then
    -- While unlocked, native tab dragging owns the frame. Polling only reads
    -- its resulting geometry and stores numbers; it never re-anchors the chat.
    CaptureCurrentGeometry()
  elseif positionWasUnlocked then
    -- Capture once more on the unlocked -> locked transition so a quick lock
    -- immediately after dropping cannot miss the final position.
    CaptureCurrentGeometry()
  end
  positionWasUnlocked = unlocked
end

local function ResetGripAfterFailure(message)
  U.UnregisterUpdate(LIVE_UPDATE_ID)
  dragging = false
  pcall(grip.StopMovingOrSizing, grip)
  AnchorGrip()
  U.Error("chat resize: " .. message)
end

local function GeometryAtGrip(gripLeft, gripBottom)
  local deltaX = gripLeft - startGripLeft
  local deltaY = gripBottom - startGripBottom
  local fixedTop = startFrameBottom + startFrameHeight

  local maxWidth = U.UIWidth() - startFrameLeft
  local maxHeight = fixedTop
  if maxWidth < MIN_WIDTH then maxWidth = MIN_WIDTH end
  if maxHeight < MIN_HEIGHT then maxHeight = MIN_HEIGHT end

  local width = Clamp(startFrameWidth + deltaX, MIN_WIDTH, maxWidth)
  -- The grip is on the lower edge, so dragging downward increases height while
  -- the chat's top-left corner stays fixed.
  local height = Clamp(startFrameHeight - deltaY, MIN_HEIGHT, maxHeight)
  local bottom = fixedTop - height
  return width, height, startFrameLeft, bottom
end

local function UpdateLiveGeometry()
  if not dragging then return end

  local gripLeft = ReadNumber(grip, "GetLeft")
  local gripBottom = ReadNumber(grip, "GetBottom")
  if not (gripLeft and gripBottom) then return end
  if gripLeft == lastGripLeft and gripBottom == lastGripBottom then return end

  lastGripLeft, lastGripBottom = gripLeft, gripBottom
  local width, height, left, bottom = GeometryAtGrip(gripLeft, gripBottom)
  if not ApplyFrameGeometry(width, height, left, bottom) then
    ResetGripAfterFailure("the native chat frame rejected live resizing")
  end
end

local function StartResize()
  startFrameWidth = ReadNumber(frame, "GetWidth")
  startFrameHeight = ReadNumber(frame, "GetHeight")
  startFrameLeft = ReadNumber(frame, "GetLeft")
  startFrameBottom = ReadNumber(frame, "GetBottom")
  if not (startFrameWidth and startFrameHeight and startFrameLeft and
          startFrameBottom) then
    ResetGripAfterFailure("could not read the chat geometry")
    return
  end

  if not pcall(grip.SetMovable, grip, true) then
    ResetGripAfterFailure("the corner grip could not be made draggable")
    return
  end

  -- frames.movable_drag_requires_button_handle: this client needs the same
  -- throwaway move/stop pair used by unrealUI's mover before a real drag.
  if pcall(grip.StartMoving, grip) then
    pcall(grip.StopMovingOrSizing, grip)
  end

  startGripLeft = ReadNumber(grip, "GetLeft")
  startGripBottom = ReadNumber(grip, "GetBottom")
  if not (startGripLeft and startGripBottom) then
    ResetGripAfterFailure("could not read the corner grip position")
    return
  end

  if not pcall(grip.StartMoving, grip) then
    ResetGripAfterFailure("the corner grip did not start dragging")
    return
  end

  dragging = true
  lastGripLeft, lastGripBottom = startGripLeft, startGripBottom
  U.RegisterUpdate(LIVE_UPDATE_ID, 0, UpdateLiveGeometry)
end

local function StopResize()
  U.UnregisterUpdate(LIVE_UPDATE_ID)
  if not dragging then
    AnchorGrip()
    return
  end
  dragging = false

  pcall(grip.StopMovingOrSizing, grip)

  local finalLeft = ReadNumber(grip, "GetLeft")
  local finalBottom = ReadNumber(grip, "GetBottom")
  if not (finalLeft and finalBottom) then
    ResetGripAfterFailure("could not read the dropped corner position")
    return
  end

  local width, height, left, bottom = GeometryAtGrip(finalLeft, finalBottom)

  -- chat.chatframe1_resize.v1 (SUPPORTED, BEHAVIOR_VERIFIED) measured this
  -- exact native frame accepting SetWidth/SetHeight and reading both values
  -- back, then restoring its original dimensions.
  if not ApplyGeometry(width, height, left, bottom) then
    ResetGripAfterFailure("the native chat frame rejected its new size")
    return
  end

  SaveGeometry(width, height, left, bottom)
end

local function CreateGrip()
  grip = CreateFrame("Button", "UnrealUIChatResizeGrip", frame)
  grip:Hide()
  grip:SetWidth(GRIP_SIZE)
  grip:SetHeight(GRIP_SIZE)
  grip:RegisterForDrag("LeftButton")
  pcall(grip.EnableMouse, grip, true)

  local level = ReadNumber(frame, "GetFrameLevel")
  if level then pcall(grip.SetFrameLevel, grip, level + 10) end

  local icon = grip:CreateTexture(nil, "ARTWORK")
  local textureOk = pcall(icon.SetTexture, icon, M.texture.chatResizeGrip)
  icon:SetAllPoints(grip)
  grip.icon = icon
  icon:Hide()
  if not textureOk then
    U.Error("chat resize: the bundled grip texture could not be loaded")
  end

  grip:SetScript("OnDragStart", StartResize)
  grip:SetScript("OnDragStop", StopResize)

  AnchorGrip()
end

function Chat:OnInit()
  config = U.ModuleConfig("chat", {
    resized = false,
    width = 0,
    height = 0,
    left = 0,
    bottom = 0,
  })
  if config and config.resized then
    lastSavedWidth = tonumber(config.width)
    lastSavedHeight = tonumber(config.height)
    lastSavedLeft = tonumber(config.left)
    lastSavedBottom = tonumber(config.bottom)
  end
end

function Chat:OnEnable()
  frame = U.G("ChatFrame1")
  if not frame then
    U.Error("chat resize: ChatFrame1 is unavailable")
    return
  end

  CreateGrip()
  RestoreSavedGeometry()
  restorePasses = config and config.resized and RESTORE_PASSES or 0
  positionWasUnlocked = not ChatIsLocked()
  lastGripShown = nil
  UpdateLockVisibility()
  U.RegisterUpdate(LOCK_UPDATE_ID, 0.10, UpdateLockVisibility)
  U.RegisterUpdate(POSITION_UPDATE_ID, POSITION_INTERVAL,
                   UpdatePositionPersistence)
end

function U.ChatResizeReport()
  local gripShown = false
  if grip and type(grip.IsShown) == "function" then
    local ok, shown = pcall(grip.IsShown, grip)
    if ok then gripShown = shown and true or false end
  end
  return {
    frame = frame and true or false,
    grip = grip and true or false,
    dragging = dragging,
    saved = config and config.resized and true or false,
    locked = ChatIsLocked(),
    shown = gripShown,
    left = frame and ReadNumber(frame, "GetLeft") or nil,
    bottom = frame and ReadNumber(frame, "GetBottom") or nil,
    savedLeft = config and config.left or nil,
    savedBottom = config and config.bottom or nil,
    width = frame and ReadNumber(frame, "GetWidth") or nil,
    height = frame and ReadNumber(frame, "GetHeight") or nil,
  }
end
