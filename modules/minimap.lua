-- unrealUI :: modules/minimap.lua
--
-- A settings button beside the native minimap, and a mover anchor so the
-- native minimap cluster can be dragged in unrealUI's edit mode.
--
-- The native minimap is kept as it is: no replacement, no reskin, no chrome
-- suppression. knowledge.json / minimap.render_pass_under_ordinary_frames says
-- the map surface is drawn in a special pass beneath ordinary frames, which is
-- also why the button is placed *outside* the map rather than over it -- an
-- ordinary frame on top of the map would cover it.
--
-- The mover targets MinimapCluster rather than bare Minimap: behavior.json /
-- minimap.context.frames.MinimapCluster confirms it holds the map's native
-- chrome (zone text, etc.) and defaults to TOPRIGHT UIParent TOPRIGHT 0,0 with
-- no pfUI involvement, so moving the cluster keeps that chrome attached and
-- the registration's own default matches where the client already puts it.
-- The settings button stays anchored to Minimap itself, so it keeps tracking
-- correctly without any extra work when the cluster moves -- until the user
-- drags the button somewhere else, after which its own saved position wins.

local U = UnrealUI
local M = U.media

local MM = U.RegisterModule("minimap")

local BUTTON_SIZE = 24
-- Stored through the shared position store (core/config.lua). Not a mover id:
-- the button is dragged directly rather than through edit mode.
local POSITION_ID = "minimapbutton"

-- Anchored to the map's left edge so it never lands on the map surface or on
-- the stock chrome hanging off the right side -- unless the user has dragged
-- the button, in which case the position they dropped it on is used instead.
-- Also runs after /uui reset, so it clears the old anchor first rather than
-- stacking a second point on top of the one already there.
local function AnchorButton(button)
  pcall(button.ClearAllPoints, button)

  local saved = U.GetPosition(POSITION_ID)
  if saved and U.ApplyFramePoint(button, saved) then
    return "its saved position"
  end

  local minimap = U.G("Minimap")
  if minimap then
    button:SetPoint("TOPRIGHT", minimap, "TOPLEFT", -6, 0)
    return "Minimap"
  end

  local cluster = U.G("MinimapCluster")
  if cluster then
    button:SetPoint("TOPRIGHT", cluster, "TOPLEFT", -6, -6)
    return "MinimapCluster"
  end

  -- No minimap to sit beside: park it in the corner rather than not existing.
  button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
  return "UIParent (no minimap found)"
end

-- MinimapCluster is preferred: it is the whole native unit (map plus its
-- attached chrome) and its default anchor is measured. A bare Minimap fallback
-- carries no default -- its own point is only known from a pfUI-influenced
-- snapshot, not trustworthy as this client's un-modded native anchor -- so
-- Reset simply leaves it wherever it already is in that rare case.
local function ResolveMoverTarget()
  local cluster = U.G("MinimapCluster")
  if cluster then
    return cluster, "MinimapCluster",
      { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = 0, y = 0 }
  end

  local minimap = U.G("Minimap")
  if minimap then return minimap, "Minimap", nil end

  return nil
end

local function RegisterMinimapMover()
  local target, name, default = ResolveMoverTarget()
  if not target then
    U.Debug("minimap: no MinimapCluster or Minimap to register as a mover")
    return
  end

  U.RegisterMover("minimap", target, { label = U.L("MOVER_LABEL_MINIMAP"), default = default })
  U.Debug("minimap mover registered on " .. name)
end

-- ---------------------------------------------------------------------------
-- Dragging the settings button
--
-- The button is its own drag handle. knowledge.json /
-- frames.movable_drag_requires_button_handle's verified recipe needs the
-- widget that receives the drag to be a Button, with SetMovable applied
-- immediately before each drag and a throwaway StartMoving/StopMovingOrSizing
-- pair to collapse the anchor down to the single point the client will move.
-- U.CreateButton already builds a real Button, so no separate handle is
-- created: an overlay covering this 24px button would take the mouse away from
-- it and cost both the click and the hover state.
--
-- A drop re-anchors the button to UIParent, so it stops tracking the minimap.
-- That is the point of moving it, and it is recoverable -- /uui reset drops the
-- stored position and puts the button back beside the map.
-- ---------------------------------------------------------------------------
local dragState = { dragging = false, stoppedAt = nil }

local function StartButtonDrag(button)
  if not pcall(button.SetMovable, button, true) then
    U.Error("minimap button: SetMovable failed; the button cannot be moved")
    return false
  end

  if pcall(button.StartMoving, button) then
    pcall(button.StopMovingOrSizing, button)
  end

  if not pcall(button.StartMoving, button) then
    U.Error("minimap button: StartMoving failed; the button will not drag")
    return false
  end

  dragState.dragging = true
  return true
end

-- The dropped anchor is captured and stored, and the button is left exactly
-- where it was released: knowledge.json / frames.getpoint_relative_name_y_
-- inverted lists recapturing and immediately re-applying a point as a failed
-- approach, which is why U.GetFramePoint is used to read it and nothing is
-- re-anchored here.
local function StopButtonDrag(button)
  if not dragState.dragging then return false end
  dragState.dragging = false
  dragState.stoppedAt = GetTime()
  pcall(button.StopMovingOrSizing, button)

  local point, relative, relativePoint, x, y = U.GetFramePoint(button, 1)
  if not point then
    U.Debug("minimap button: no readable anchor after drag")
    return false
  end

  -- Stored positions are re-applied against UIParent. The drag is expected to
  -- leave the button screen-anchored, so this says what happened instead of
  -- silently storing an offset measured from a different origin.
  if relative and relative ~= UIParent then
    U.Debug("minimap button: anchored to a non-UIParent frame after drag; storing anyway")
  end

  return U.SavePosition(POSITION_ID, point, relativePoint, x, y)
end

-- Whether the click that is arriving now is really the end of a drag. GetTime
-- is updated once per UI draw (api.json / core.time.v1), so a click released in
-- the same frame as the drop reads an identical stamp, while the user's next
-- real click is at least one frame later.
local function ClickEndedADrag()
  if dragState.dragging then return true end
  if not dragState.stoppedAt then return false end
  return (GetTime() - dragState.stoppedAt) < 0.02
end

local function EnableButtonDrag(button)
  pcall(button.SetMovable, button, true)
  -- Documented (Frame:SetClampedToScreen) but not runtime-verified here, so it
  -- is a bonus rather than the only thing keeping the button reachable: a
  -- button dragged off-screen is still recoverable through /uui reset.
  pcall(button.SetClampedToScreen, button, true)

  if not pcall(button.RegisterForDrag, button, "LeftButton") then
    U.Error("minimap button: RegisterForDrag failed; the button will not drag")
    return false
  end

  button:SetScript("OnDragStart", function() StartButtonDrag(button) end)
  button:SetScript("OnDragStop", function() StopButtonDrag(button) end)

  U.OnPositionReset(function() return AnchorButton(button) and true end)
  return true
end

-- ---------------------------------------------------------------------------
-- Ping placement
-- ---------------------------------------------------------------------------

-- This client puts the minimap ping a constant distance from where you
-- clicked. Measured with UnrealRuntimeProbe group `minimapping` on 2026-08-26:
-- across five pings at five different spots on a 140x140 minimap, the offset
-- the client recorded was (-7, -9) pixels away from the cursor every single
-- time, with no variance at all -- a fixed constant, not a scale error, which
-- is why it does not grow toward the edges. It reproduces with no addon
-- loaded, so this is client behaviour and not something unrealUI causes.
--
-- The correction deliberately does NOT re-derive the client's own arithmetic.
-- The same probe run showed two things that make that unnecessary: the ping's
-- final position comes from the Lua global Minimap_SetPing, which the client
-- calls repeatedly while the ring animates, and MiniMapPing is an ordinary
-- CENTER-to-CENTER anchored child of Minimap. So the client keeps doing all of
-- its own work -- sound, timer, show, and the network side -- and only the
-- anchor is re-stated afterwards, from the cursor, which knowledge.json /
-- api.getcursorposition_usable_for_hit_testing confirms is accurate here.
-- Nothing depends on the units or the sign the client uses internally. That
-- matters: the probe's readback and its drawn anchor disagreed about the y
-- sign, and this approach is correct either way instead of betting on one.
--
-- Only the local player's own ping is corrected. A party member's ping has no
-- cursor to read, so those pass through untouched rather than being moved on a
-- guess.

local pingState = { lastX = nil, lastY = nil, offsetX = nil, offsetY = nil, hooked = false }

-- The cursor's offset from the minimap centre, or nil when the cursor is not
-- on the map. That nil is also how a group member's ping is told apart from
-- ours: theirs arrives with the mouse somewhere else entirely.
local function CursorOffset(minimap)
  if type(GetCursorPosition) ~= "function" then return nil end
  local ok, cursorX, cursorY = pcall(GetCursorPosition)
  if not ok or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return nil end

  local scaleOk, scale = pcall(minimap.GetEffectiveScale, minimap)
  if not scaleOk or type(scale) ~= "number" or scale == 0 then scale = 1 end

  local centerOk, centerX, centerY = pcall(minimap.GetCenter, minimap)
  if not centerOk or type(centerX) ~= "number" or type(centerY) ~= "number" then return nil end

  local widthOk, width = pcall(minimap.GetWidth, minimap)
  if not widthOk or type(width) ~= "number" or width <= 0 then return nil end

  local offsetX = cursorX / scale - centerX
  local offsetY = cursorY / scale - centerY
  local radius = width / 2
  if (offsetX * offsetX + offsetY * offsetY) > (radius * radius) then return nil end
  return offsetX, offsetY
end

-- Runs after the client has placed the ping. Minimap_SetPing has the fixed
-- (x, y, playSound) signature PostHookGlobal requires -- it is not a vararg
-- native, so the wrapper's fixed arity is safe here.
local function CorrectPingPlacement(x, y)
  local minimap = U.G("Minimap")
  local model = U.G("MiniMapPing")
  if not minimap or not model or type(model.SetPoint) ~= "function" then return end

  -- A new ping arrives with a new pair of coordinates; the frames that follow
  -- repeat that same pair while the ring animates. Recomputing from the cursor
  -- every frame would make the ping trail the mouse around, so the correction
  -- is taken once when the coordinates change and then reused for the rest of
  -- that ping.
  if x ~= pingState.lastX or y ~= pingState.lastY then
    pingState.lastX, pingState.lastY = x, y
    pingState.offsetX, pingState.offsetY = CursorOffset(minimap)
  end

  if pingState.offsetX then
    pcall(model.SetPoint, model, "CENTER", minimap, "CENTER",
      pingState.offsetX, pingState.offsetY)
  end
end

local function HookPingPlacement()
  if pingState.hooked then return end

  -- Both pieces have to be there. Missing either means this client routes
  -- pings somewhere this correction cannot see, and the right answer is to
  -- leave the native ping exactly as it is rather than half-hook it.
  if type(U.G("Minimap_SetPing")) ~= "function" or not U.G("MiniMapPing") then
    U.Debug("minimap: ping placement left alone (Minimap_SetPing or MiniMapPing unavailable)")
    return
  end

  -- The shared wrapper rather than a local one: it calls the original first,
  -- passes its returns through, and reads the global back so an ignored
  -- assignment fails closed instead of silently doing nothing.
  pingState.hooked = U.PostHookGlobal("Minimap_SetPing", CorrectPingPlacement)
  if pingState.hooked then
    U.Debug("minimap: ping placement corrected through Minimap_SetPing")
  else
    U.Debug("minimap: could not hook Minimap_SetPing; native ping left as it is")
  end
end

-- Applies the current enabled state to an already-created button. Public so
-- modules/settings.lua's General page can flip the checkbox without reaching
-- into this module's internals.
local function Apply()
  local button = MM.button
  if not button then return end

  if U.ModuleConfig("minimap", { enabled = true }).enabled then
    button:Show()
    if button.label then button.label:Show() end
  else
    button:Hide()
  end
end
U.ApplyMinimapButton = Apply

function MM:OnEnable()
  if self.button then return end

  local button = U.CreateButton(UIParent, {
    name = "UnrealUISettingsButton",
    width = BUTTON_SIZE,
    height = BUTTON_SIZE,
    text = "",
    onClick = function()
      -- Releasing a drag over the button must not also open the window.
      if ClickEndedADrag() then return end
      if type(U.OpenSettings) == "function" then U.OpenSettings() end
    end,
  })

  local border = U.BorderSize()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", border, -border)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -border, border)

  -- A stock icon path. Nothing in the compact DB covers Interface\ICONS on this
  -- client, so if the call is rejected the button falls back to its own label
  -- rather than showing an empty square.
  local applied = pcall(icon.SetTexture, icon, "Interface\\ICONS\\INV_Misc_Gear_01")
  if applied then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  else
    icon:Hide()
    if button.label then button.label:SetText("UI") end
  end
  button.icon = icon

  local anchor = AnchorButton(button)
  EnableButtonDrag(button)

  self.button = button
  Apply()
  U.Debug("settings button anchored to " .. anchor)

  RegisterMinimapMover()
  HookPingPlacement()
end
