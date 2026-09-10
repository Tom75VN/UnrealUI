-- unrealUI :: modules/chat.lua
--
-- Adds one explicit resize grip to the primary native chat window, and an
-- opt-in switch that takes the drop shadow off the chat text. Chat tabs,
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
local DRIFT_EPSILON = 1
local ALPHA_EPSILON = 0.01
-- Consecutive corrections tolerated before the enforcement gives up. At the
-- position interval this is a few seconds of an unbroken fight with another
-- owner, which no legitimate late layout produces.
local ENFORCE_LIMIT = 40

local frame, grip, config
local dragging = false
local startFrameWidth, startFrameHeight, startFrameLeft, startFrameBottom
local startGripLeft, startGripBottom
local lastGripLeft, lastGripBottom
local lastGripShown
local lastSavedWidth, lastSavedHeight, lastSavedLeft, lastSavedBottom
local restorePasses = 0
local positionWasUnlocked = false
local enforceRuns = 0
local enforceStopped = false
local shadowFonts = {}
local shadowTouched = false
local shadowReport = { bound = false, applied = false }
local chatBackground = {
  alpha = 0.25,
  hoverAlpha = 0.5,
  update = "chat.background",
  records = {},
}

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
  if U.PerfDisabled and U.PerfDisabled("chat") then return end

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
  -- A fresh placement is a new target, so an enforcement that had given up
  -- gets to try again.
  enforceRuns = 0
  enforceStopped = false
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

-- The stored geometry clamped to the current screen, or nil while nothing has
-- been placed yet.
local function SavedGeometry()
  if not config or not config.resized then return nil end

  local width = tonumber(config.width)
  local height = tonumber(config.height)
  local left = tonumber(config.left)
  local bottom = tonumber(config.bottom)
  if not (width and height and left and bottom) then return nil end

  width = Clamp(width, MIN_WIDTH, U.UIWidth() - left)
  height = Clamp(height, MIN_HEIGHT, U.UIHeight())
  bottom = Clamp(bottom, 0, U.UIHeight() - height)
  return width, height, left, bottom
end

local function RestoreSavedGeometry()
  local width, height, left, bottom = SavedGeometry()
  if not width then return end
  ApplyGeometry(width, height, left, bottom)
end

-- frames.extra_anchor_point_survives_addon_setpoint (USER_CONFIRMED_INGAME):
-- a native frame this addon re-anchors can end up carrying a second anchor
-- point that actually places it while GetPoint(1) still reads back as ours, so
-- the point count is tested first and any count other than one counts as drift
-- by itself. The rect comparison is what catches the client's own late chat
-- layout writing a different corner or size.
local function GeometryDrifted(width, height, left, bottom)
  local okCount, count = pcall(frame.GetNumPoints, frame)
  if okCount and tonumber(count) and tonumber(count) ~= 1 then return true end

  local currentWidth = ReadNumber(frame, "GetWidth")
  local currentHeight = ReadNumber(frame, "GetHeight")
  local currentLeft = ReadNumber(frame, "GetLeft")
  local currentBottom = ReadNumber(frame, "GetBottom")
  if not (currentWidth and currentHeight and currentLeft and currentBottom) then
    return false
  end

  if math.abs(currentWidth - width) > DRIFT_EPSILON then return true end
  if math.abs(currentHeight - height) > DRIFT_EPSILON then return true end
  if math.abs(currentLeft - left) > DRIFT_EPSILON then return true end
  if math.abs(currentBottom - bottom) > DRIFT_EPSILON then return true end
  return false
end

-- Put the chat back on its saved geometry whenever something else has moved or
-- resized it. This only runs while the chat is locked, where the resize grip is
-- hidden and native tab dragging is unavailable, so any difference from the
-- stored numbers is the client's own layout rather than the player.
local function EnforceSavedGeometry()
  if enforceStopped or not frame then return end

  local width, height, left, bottom = SavedGeometry()
  if not width then return end

  if not GeometryDrifted(width, height, left, bottom) then
    enforceRuns = 0
    return
  end

  ApplyGeometry(width, height, left, bottom)
  enforceRuns = enforceRuns + 1
  if enforceRuns >= ENFORCE_LIMIT then
    -- Another owner is rewriting the chat on every pass. Stand down rather
    -- than flicker the frame between two placements for the whole session.
    enforceStopped = true
    U.Debug("chat position: stopped re-applying the saved geometry; " ..
            "something keeps moving the chat back")
  end
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
  -- The native chat performs late layout work during reload, and it is not
  -- confined to the first second after login: with a single bounded restore
  -- window, any later native placement stood for the rest of the session,
  -- which is why the chat did not keep a custom position across a reload. The
  -- window now only suppresses capturing, so a late default layout cannot
  -- overwrite the correct SavedVariables values in memory; the saved geometry
  -- itself is re-applied for as long as the chat stays locked.
  if restorePasses > 0 then
    restorePasses = restorePasses - 1
    EnforceSavedGeometry()
    positionWasUnlocked = not ChatIsLocked()
    return
  end

  local unlocked = not ChatIsLocked()
  if unlocked and ChatIsVisible() then
    -- While unlocked, native tab dragging owns the frame. Polling only reads
    -- its resulting geometry and stores numbers; it never re-anchors the chat.
    CaptureCurrentGeometry()
  else
    if positionWasUnlocked then
      -- Capture once more on the unlocked -> locked transition so a quick lock
      -- immediately after dropping cannot miss the final position.
      CaptureCurrentGeometry()
    end
    EnforceSavedGeometry()
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
  if U.PerfDisabled and U.PerfDisabled("chat") then return end

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

-- ---------------------------------------------------------------------------
-- Chat text shadow
--
-- chat.native_private_font_removes_shadow: native probe v2 + user screenshot
-- verified SetFont(stock path, measured size), an owned FontString bound to
-- that private Font, SetTextColor(1,1,1), then ChatFrame1:SetFontObject(font).
-- White initialization is essential: a fresh Font otherwise makes new
-- default-color messages dark. Explicit message colors remain intact.
-- The same class/sequence is used on ChatFrame2; its visual result is pending.
-- No shadow setters, native region walks, message hooks or font polling.
-- Native chat has no GetFontObject, so disabling defers restoration to reload.
-- ---------------------------------------------------------------------------

local function BoundFontName(region)
  if not region or type(region.GetFontObject) ~= "function" then return nil end

  local ok, object = pcall(region.GetFontObject, region)
  if not ok or not object or type(object.GetName) ~= "function" then
    return nil
  end

  local nameOk, name = pcall(object.GetName, object)
  if not nameOk or type(name) ~= "string" then return nil end
  return name
end

local function ChatShadowFont(chat, index)
  local cached = shadowFonts[index]
  if cached then return cached.ready and cached.font or nil end
  local ok, _, size = pcall(function() return chat:GetFont() end)
  if not ok or type(size) ~= "number" or size <= 0 then return nil end
  -- Retain only owned objects, never a client-owned message region.
  local record = {}
  shadowFonts[index] = record
  local created = pcall(function()
    local name = "UnrealUIChatNoShadowFont" .. index
    record.font = CreateFont(name)
    record.font:SetFont("Fonts\\FRIZQT__.TTF", size)
    record.holder = CreateFrame("Frame", nil, UIParent)
    record.holder:Hide()
    record.proxy = record.holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    record.proxy:SetFontObject(record.font)
    if BoundFontName(record.proxy) ~= name then return end
    record.proxy:SetTextColor(1, 1, 1)
    record.proxy:SetText("AaBb 123")
    local width = record.proxy:GetStringWidth()
    record.ready = type(width) == "number" and width > 0
  end)
  if not created or not record.ready then return nil end
  return record.font
end

-- Is the cursor inside this chat frame?
--
-- GetMouseFocus reports <none> on this client (core/commands.lua records the
-- 8s hover watch that found it useless), and the chat frames are client-owned,
-- so no OnEnter/OnLeave script may be taken from them. The cursor rectangle
-- test is the same GetCursorPosition/GetEffectiveScale pattern the world map
-- and minimap already rely on. An unreadable rect answers "not hovered", which
-- simply leaves the background at its idle opacity.
local function CursorOverFrame(frame, cursorX, cursorY)
  if not cursorX or not cursorY then return false end

  local scale = ReadNumber(frame, "GetEffectiveScale")
  if not scale or scale <= 0 then return false end

  local left = ReadNumber(frame, "GetLeft")
  local bottom = ReadNumber(frame, "GetBottom")
  local width = ReadNumber(frame, "GetWidth")
  local height = ReadNumber(frame, "GetHeight")
  if not (left and bottom and width and height) then return false end
  if width <= 0 or height <= 0 then return false end

  local x, y = cursorX / scale, cursorY / scale
  return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

local function CursorPoint()
  if type(GetCursorPosition) ~= "function" then return nil end
  local ok, x, y = pcall(GetCursorPosition)
  if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y
end

-- WORKING_SOURCE: UnrealPfUI/modules/chat.lua addresses ChatFrameNBackground
-- directly. No native region discovery or cached native texture references.
-- The background is held at 25% while idle and 50% while the cursor is over
-- that chat frame. Unlike the earlier floor-only treatment this overrides the
-- native hover fade in both directions, so the two states stay the ones
-- configured here. Chat text and frame alpha stay intact.
function chatBackground.Tick()
  if not config or not config.noTextShadow then return end
  local cursorX, cursorY = CursorPoint()
  local i
  for i = 1, 2 do
    local chat = U.G("ChatFrame" .. i)
    if chat then
      pcall(function()
        local record = chatBackground.records[i] or {}
        chatBackground.records[i] = record
        local target = chatBackground.alpha
        if CursorOverFrame(chat, cursorX, cursorY) then
          target = chatBackground.hoverAlpha
        end
        local texture = U.G("ChatFrame" .. i .. "Background")
        if texture and type(texture.SetAlpha) == "function" and type(texture.Show) == "function" then
          if not record.native then
            record.alpha = ReadNumber(texture, "GetAlpha")
            local ok, shown = pcall(texture.IsShown, texture)
            if ok then record.shown = shown and shown ~= 0 and true or false end
            record.native = true
          end
          if record.owned then record.owned:Hide() end
        else
          if not record.owned then
            record.owned = chat:CreateTexture(nil, "BACKGROUND")
            record.owned:SetTexture(M.texture.plain)
            record.owned:SetVertexColor(0, 0, 0, 1)
            record.owned:SetAllPoints(chat)
          end
          texture = record.owned
        end
        -- Compared with a tolerance because the native fade animates: an
        -- exact test would re-set the alpha on every frame of it.
        local alpha = ReadNumber(texture, "GetAlpha")
        if not alpha or alpha > target + ALPHA_EPSILON
            or alpha < target - ALPHA_EPSILON then
          texture:SetAlpha(target)
        end
        local ok, shown = pcall(texture.IsShown, texture)
        if not ok or not shown or shown == 0 then texture:Show() end
      end)
    end
  end
end

function chatBackground.Apply(enabled)
  if enabled then
    chatBackground.Tick()
    U.RegisterUpdate(chatBackground.update, 0, chatBackground.Tick)
    return
  end
  U.UnregisterUpdate(chatBackground.update)
  local index, record
  for index, record in pairs(chatBackground.records) do
    if record.owned then pcall(record.owned.Hide, record.owned) end
    if record.native then
      local texture = U.G("ChatFrame" .. index .. "Background")
      if texture then
        if record.alpha then pcall(texture.SetAlpha, texture, record.alpha) end
        if record.shown == false then pcall(texture.Hide, texture) end
        if record.shown == true then pcall(texture.Show, texture) end
      end
      record.native = nil
    end
  end
end

function U.ApplyChatTextShadow()
  local remove = config and config.noTextShadow and true or false
  chatBackground.Apply(remove)
  if not remove then
    shadowReport.applied = false
    -- Return whether settings must display the reload notice. No guessed
    -- ChatFontNormal restore: the original native font cannot be read back.
    return shadowTouched
  end
  local applied, bound, found = true, true, false
  local index
  for index = 1, 2 do
    local chat = U.G("ChatFrame" .. index)
    if chat then
      found = true
      local font = ChatShadowFont(chat, index)
      if not font then
        bound, applied = false, false
      else
        local ok = pcall(chat.SetFontObject, chat, font)
        if ok then shadowTouched = true else applied = false end
      end
    end
  end
  shadowReport.bound = found and bound
  shadowReport.applied = found and applied
  return false
end

function Chat:OnInit()
  config = U.ModuleConfig("chat", {
    resized = false,
    width = 0,
    height = 0,
    left = 0,
    bottom = 0,
    noTextShadow = false,
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
  U.ApplyChatTextShadow()
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
    enforceRuns = enforceRuns,
    enforceStopped = enforceStopped,
    noTextShadow = config and config.noTextShadow and true or false,
    shadowBound = shadowReport.bound,
    shadowApplied = shadowReport.applied,
    width = frame and ReadNumber(frame, "GetWidth") or nil,
    height = frame and ReadNumber(frame, "GetHeight") or nil,
  }
end
