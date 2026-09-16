-- unrealUI :: modules/minimap.lua
--
-- A settings button beside the minimap, and a mover anchor so the minimap
-- cluster can be dragged in unrealUI's edit mode.
--
-- The map surface and its behavior stay native. Under the full Modern WoW
-- theme or Classic's explicit Minimap selection, the stock decorative ring,
-- zone bed, zoom-button faces and mail art are replaced with that theme's
-- authored textures, and the close button and clock are removed. knowledge.json /
-- minimap.render_pass_under_ordinary_frames says the map surface is drawn in a
-- special pass beneath ordinary frames, which is why the new shadow is alpha-
-- only over the map and the settings button remains outside the ring.
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

local modernWowMinimap = { dressed = false }

local function ModernWow()
  return type(U.ModernWowModuleEnabled) == "function" and
         U.ModernWowModuleEnabled("minimap")
end

-- The stock minimap ring on this client is not one dependable region:
-- knowledge.json / minimap.native_chrome_requires_targeted_suppression and the
-- working UnrealPfUI path both identify an oversized MinimapBackdrop plus the
-- two named border regions. Strip only those exact decorative objects, before
-- any addon art is attached; all native map behavior and status widgets stay.
local BUTTON_ART = { "Normal", "Pushed", "Highlight", "Disabled" }

-- Clears a native button's own state textures by direct getter/setter, never
-- by a region walk (rules: region walks cannot match by identity here), then
-- hides the button and drops its mouse input.
local function ClearButtonArt(button)
  if not button then return end
  local i
  for i = 1, table.getn(BUTTON_ART) do
    local getter = button["Get" .. BUTTON_ART[i] .. "Texture"]
    if type(getter) == "function" then
      local ok, texture = pcall(getter, button)
      if ok and texture then U.HideRegion(texture) end
    end
    local setter = button["Set" .. BUTTON_ART[i] .. "Texture"]
    if type(setter) == "function" then pcall(setter, button, "") end
  end
  pcall(button.EnableMouse, button, false)
  U.HideRegion(button)
end

local function HideStockChrome()
  local backdrop = U.G("MinimapBackdrop")
  if backdrop then U.StripTextures(backdrop) end
  U.HideRegion(U.G("MinimapBorder"))
  U.HideRegion(U.G("MinimapBorderTop"))

  -- The close "X", the day/night clock and the native zone label. All four
  -- globals were confirmed present on 2026-09-14 (user /script readback;
  -- MinimapToggleButton and GameTimeFrame are MinimapCluster children). Hiding
  -- the frames alone left both icons drawn: UnrealPfUI records that child
  -- regions draw independently of their parent on this client, so each
  -- button's own state art is cleared directly as well.
  ClearButtonArt(U.G("MinimapToggleButton"))
  ClearButtonArt(U.G("GameTimeFrame"))
  U.HideRegion(U.G("GameTimeTexture"))
  U.HideRegion(U.G("MinimapZoneText"))

  -- knowledge.json / minimap.native_chrome_requires_targeted_suppression
  -- (WORKING_SOURCE): a single Hide() does not keep this chrome off screen, so
  -- the shared periodic suppression keeps them hidden afterwards.
  U.SuppressNativeFrame({
    "MinimapBorderTop",
    "MinimapToggleButton",
    "GameTimeFrame", "GameTimeTexture",
    "MinimapZoneTextButton", "MinimapZoneText",
  })
end

local function SetButtonTexture(button, methodName, path)
  if not button or not path then return false end
  local method = button[methodName]
  if type(method) ~= "function" then return false end
  return pcall(method, button, path)
end

local function DressZoomButton(button, normal, over, pushed, disabled)
  if not button then return false end
  SetButtonTexture(button, "SetNormalTexture", normal)
  SetButtonTexture(button, "SetHighlightTexture", over)
  SetButtonTexture(button, "SetPushedTexture", pushed)
  SetButtonTexture(button, "SetDisabledTexture", disabled)
  return true
end

-- Complete modern-wow drawing path. The imported layout is working-source
-- evidence from DragonflightUI-Reforged; every client-owned object remains
-- capability-checked because only MinimapZoomIn is named in official client
-- documentation and the other exact globals are not runtime-verified here.
local function DressModernWowMinimap()
  if modernWowMinimap.dressed or not ModernWow() then return false end

  local minimap = U.G("Minimap")
  local art = M.modernWow and M.modernWow.texture
  local layout = M.modernWow and M.modernWow.minimap
  if not minimap or not art or not layout then return false end

  HideStockChrome()

  local border = minimap:CreateTexture(nil, "OVERLAY")
  border:SetTexture(art.minimapBorder)
  border:SetPoint("TOPLEFT", minimap, "TOPLEFT",
    -layout.borderOffset, layout.borderOffset)
  border:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT",
    layout.borderOffset, -layout.borderOffset)

  local shadow = minimap:CreateTexture(nil, "BORDER")
  shadow:SetTexture(art.minimapShadow)
  shadow:SetPoint("TOPLEFT", minimap, "TOPLEFT",
    -layout.borderOffset, layout.borderOffset)
  shadow:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT",
    layout.borderOffset, -layout.borderOffset)
  shadow:SetAlpha(layout.shadowAlpha)

  local panel = CreateFrame("Frame", "UnrealUIModernWowMinimapTopPanel", minimap)
  local width = 140
  local ok, liveWidth = pcall(minimap.GetWidth, minimap)
  if ok and type(liveWidth) == "number" and liveWidth > 0 then width = liveWidth end
  panel:SetWidth(width)
  panel:SetHeight(layout.topPanelHeight)
  panel:SetPoint("BOTTOM", minimap, "TOP", 0, layout.topPanelGap)

  local panelArt = panel:CreateTexture(nil, "BACKGROUND")
  panelArt:SetTexture(art.minimapTopPanel)
  -- One anchor plus explicit size: the stretched two-point form did not
  -- visibly change the height in game (2026-09-14).
  panelArt:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT",
    0, -layout.topPanelBottomOverhang)
  panelArt:SetWidth(width + layout.topPanelRightOverhang)
  panelArt:SetHeight(layout.topPanelArtHeight)

  -- The zone name is an addon-owned label on the panel art. Reparenting the
  -- native MinimapZoneTextButton did not take on this client (2026-09-14: it
  -- was still a MinimapCluster child afterwards), so the native label is
  -- suppressed in HideStockChrome and this one reads GetMinimapZoneText
  -- (DOCUMENTED_NOT_RUNTIME_VERIFIED) -- the same source UnrealPfUI's working
  -- zone panel uses. No zone event is verified here, so a throttled refresh
  -- is the guarantee and the events are only a faster path.
  local zoneLabel = U.CreateLabel(panel, {
    name = "UnrealUIModernWowMinimapZoneText",
    inherits = "GameFontNormal",
    size = M.fontSize.normal,
    color = layout.zoneColor,
    justify = "CENTER",
    width = width - layout.zoneX * 2,
  })
  if zoneLabel then
    -- Vertically centre on the art's visible band, derived from the measured
    -- texel rows and the art's drawn height.
    local artHeight = layout.topPanelArtHeight
    local bandCentreFromBottom = artHeight * (1 -
      (layout.topPanelVisibleTop + layout.topPanelVisibleBottom) /
      (2 * layout.topPanelTexHeight))
    local artWidth = width + layout.topPanelRightOverhang
    local bandCentreX = artWidth *
      (layout.topPanelVisibleLeft + layout.topPanelVisibleRight) /
      (2 * layout.topPanelTexWidth)
    pcall(zoneLabel.SetPoint, zoneLabel, "CENTER", panel, "BOTTOMLEFT",
      bandCentreX,
      bandCentreFromBottom - layout.topPanelBottomOverhang + layout.zoneY)

    local lastZone
    local function RefreshZone()
      if type(GetMinimapZoneText) ~= "function" then return end
      local ok, zone = pcall(GetMinimapZoneText)
      if not ok or type(zone) ~= "string" or zone == lastZone then return end
      lastZone = zone
      pcall(zoneLabel.SetText, zoneLabel, zone)
    end
    RefreshZone()
    U.RegisterEvent("PLAYER_ENTERING_WORLD", RefreshZone)
    U.RegisterEvent("ZONE_CHANGED", RefreshZone)
    U.RegisterEvent("ZONE_CHANGED_INDOORS", RefreshZone)
    U.RegisterEvent("ZONE_CHANGED_NEW_AREA", RefreshZone)
    U.RegisterUpdate("minimap.modernwow.zone", layout.zoneRefresh, RefreshZone)
    modernWowMinimap.zoneLabel = zoneLabel
  end

  local zoomIn = U.G("MinimapZoomIn")
  if zoomIn then
    pcall(zoomIn.SetParent, zoomIn, minimap)
    pcall(zoomIn.ClearAllPoints, zoomIn)
    pcall(zoomIn.SetPoint, zoomIn, "TOPLEFT", minimap, "BOTTOMRIGHT",
      layout.zoomX, layout.zoomY)
    pcall(zoomIn.SetScale, zoomIn, layout.zoomScale)
    DressZoomButton(zoomIn, art.minimapZoomIn, art.minimapZoomInOver,
      art.minimapZoomInPush, art.minimapZoomInOff)
  end

  local zoomOut = U.G("MinimapZoomOut")
  if zoomOut then
    pcall(zoomOut.SetParent, zoomOut, minimap)
    pcall(zoomOut.ClearAllPoints, zoomOut)
    if zoomIn then
      pcall(zoomOut.SetPoint, zoomOut, "TOPRIGHT", zoomIn, "BOTTOMLEFT", 0, 0)
    else
      pcall(zoomOut.SetPoint, zoomOut, "TOPLEFT", minimap, "BOTTOMRIGHT",
        layout.zoomX, layout.zoomY - 29)
    end
    pcall(zoomOut.SetScale, zoomOut, layout.zoomScale)
    DressZoomButton(zoomOut, art.minimapZoomOut, art.minimapZoomOutOver,
      art.minimapZoomOutPush, art.minimapZoomOutOff)
  end

  local mailFrame = U.G("MiniMapMailFrame")
  local mailIcon = U.G("MiniMapMailIcon")
  if mailFrame and mailIcon then
    pcall(mailFrame.ClearAllPoints, mailFrame)
    pcall(mailFrame.SetPoint, mailFrame, "TOPLEFT", panel, "BOTTOMLEFT",
      layout.mailX, layout.mailY)
    pcall(mailIcon.SetTexture, mailIcon, art.minimapMail)
    pcall(mailIcon.SetWidth, mailIcon, layout.mailSize)
    pcall(mailIcon.SetHeight, mailIcon, layout.mailSize)
    U.HideRegion(U.G("MiniMapMailBorder"))
  end

  modernWowMinimap.dressed = true
  modernWowMinimap.border = border
  modernWowMinimap.shadow = shadow
  modernWowMinimap.topPanel = panel
  U.Debug("modern-wow minimap chrome applied")
  return true
end

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
    local gap = 6
    if modernWowMinimap.dressed then
      gap = gap + M.modernWow.minimap.borderOffset
    end
    button:SetPoint("TOPRIGHT", minimap, "TOPLEFT", -gap, 0)
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

  DressModernWowMinimap()

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
