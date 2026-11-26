-- unrealUI :: modules/minimap.lua
--
-- A settings button beside the minimap, and a mover anchor so the minimap
-- cluster can be dragged in unrealUI's edit mode.
--
-- The map surface and its behavior stay native. Under the full Modern WoW
-- theme or Classic's explicit Minimap selection, the stock decorative ring,
-- zone bed and zoom-button faces are replaced with that theme's authored
-- textures, and the close button and clock are removed. `modern` takes the
-- same path without the round border (user request, 2026-09-28). The pending-mail
-- letter is not part of that: it is unrealUI's animated flipbook under every
-- theme (see "The pending-mail letter" below). knowledge.json /
-- minimap.render_pass_under_ordinary_frames says the map surface is drawn in a
-- special pass beneath ordinary frames, which is why the new shadow is alpha-
-- only over the map and the settings button remains outside the ring.
--
-- The mover targets MinimapCluster rather than bare Minimap: behavior.json /
-- minimap.context.frames.MinimapCluster confirms it holds the map's native
-- chrome (zone text, etc.) and defaults to TOPRIGHT UIParent TOPRIGHT 0,0 with
-- no pfUI involvement, so moving the cluster keeps that chrome attached and
-- the registration's own default matches where the client already puts it.
-- The settings button sits on the minimap's rim (user request, 2026-11-26):
-- dragging it slides it around the edge, and only its angle is stored, so it
-- follows the map wherever the cluster is moved or scaled.

local U = UnrealUI
local M = U.media

local MM = U.RegisterModule("minimap")

-- The free position the button used to store before it was tied to the rim.
-- Read only to drop it once; nothing writes it any more.
local LEGACY_POSITION_ID = "minimapbutton"

local modernWowMinimap = { dressed = false }

local function MinimapConfig()
  return U.ModuleConfig("minimap", {
    enabled = true,
    showZone = true,
    showZoom = true,
    shape = "circle",
    buttonAngle = M.minimapButton.defaultAngle,
  })
end

-- Circle or square (user request, 2026-11-26, as PandaUI). Only the dressed
-- Modern / Modern WoW minimap takes the square: the native ring is round.
local function SquareMinimap()
  return modernWowMinimap.dressed and not modernWowMinimap.squareFailed and
         MinimapConfig().shape == "square"
end
U.MinimapIsSquare = SquareMinimap

-- How far a point at `cos`, `sin` of an angle is pushed out so a circle's
-- radius lands on the square's edge instead: 1 on a round map.
local function SquareStretch(cos, sin)
  if not SquareMinimap() then return 1 end
  local edge = math.max(math.abs(cos), math.abs(sin))
  if edge <= 0 then return 1 end
  return 1 / edge
end

local function ModernWow()
  return type(U.ModernWowModuleEnabled) == "function" and
         U.ModernWowModuleEnabled("minimap")
end

-- `modern` draws the same minimap as Modern WoW minus its round border (user
-- request, 2026-09-28): stock ring stripped, shadow, zone panel, zoom buttons
-- and mail placement kept. A sanctioned exception to the `modern` freeze.
local function ModernFlat()
  return U.GetActiveThemeStyle() == "modern"
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
  if modernWowMinimap.dressed then return false end
  local withBorder = ModernWow()
  if not withBorder and not ModernFlat() then return false end

  local minimap = U.G("Minimap")
  local art = M.modernWow and M.modernWow.texture
  local layout = M.modernWow and M.modernWow.minimap
  if not minimap or not art or not layout then return false end

  HideStockChrome()

  local border
  if withBorder then
    border = minimap:CreateTexture(nil, "OVERLAY")
    border:SetTexture(art.minimapBorder)
    border:SetPoint("TOPLEFT", minimap, "TOPLEFT",
      -layout.borderOffset, layout.borderOffset)
    border:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT",
      layout.borderOffset, -layout.borderOffset)
  end

  -- DF-main's square frame, shown instead of the round border on a square
  -- map. Modern draws no border on either shape.
  local squareBorder
  if withBorder and art.minimapSquareFrame then
    squareBorder = minimap:CreateTexture(nil, "ARTWORK")
    squareBorder:SetTexture(art.minimapSquareFrame)
    squareBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT",
      -layout.squareBorderOffset,
      layout.squareBorderOffset + layout.squareBorderYOffset)
    squareBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT",
      layout.squareBorderOffset,
      -layout.squareBorderOffset + layout.squareBorderYOffset)
    squareBorder:Hide()
  end

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
        layout.zoomX, layout.zoomY - 42.6)
    end
    pcall(zoomOut.SetScale, zoomOut, layout.zoomScale)
    DressZoomButton(zoomOut, art.minimapZoomOut, art.minimapZoomOutOver,
      art.minimapZoomOutPush, art.minimapZoomOutOff)
  end

  -- Only where the letter sits. Its art is the shared flipbook every theme
  -- draws (`mail` below), so nothing theme-specific is applied to the icon
  -- itself here.
  local mailFrame = U.G("MiniMapMailFrame")
  if mailFrame then
    pcall(mailFrame.ClearAllPoints, mailFrame)
    pcall(mailFrame.SetPoint, mailFrame, "TOPLEFT", panel, "BOTTOMLEFT",
      layout.mailX, layout.mailY)
  end

  modernWowMinimap.dressed = true
  modernWowMinimap.border = border
  modernWowMinimap.squareBorder = squareBorder
  modernWowMinimap.shadow = shadow
  modernWowMinimap.topPanel = panel
  modernWowMinimap.panelArt = panelArt
  modernWowMinimap.zoomIn = zoomIn
  modernWowMinimap.zoomOut = zoomOut
  U.Debug("modern-wow minimap chrome applied")
  return true
end

-- Only addon-authored chrome is optional. The map surface, tracking, ping and
-- every other native minimap behavior remain owned by the client.
local function ApplyChromeSettings()
  if not modernWowMinimap.dressed then return false end
  local cfg = MinimapConfig()
  local showZone = cfg.showZone and true or false
  local showZoom = cfg.showZoom and true or false

  local panel = modernWowMinimap.topPanel
  local panelArt = modernWowMinimap.panelArt
  local zone = modernWowMinimap.zoneLabel
  if panel then pcall(showZone and panel.Show or panel.Hide, panel) end
  if panelArt then pcall(showZone and panelArt.Show or panelArt.Hide, panelArt) end
  if zone then pcall(showZone and zone.Show or zone.Hide, zone) end

  local button
  for _, button in pairs({ modernWowMinimap.zoomIn,
                           modernWowMinimap.zoomOut }) do
    if button then
      pcall(showZoom and button.Show or button.Hide, button)
      pcall(button.EnableMouse, button, showZoom)
    end
  end
  return true
end
U.ApplyMinimapChromeSettings = ApplyChromeSettings

-- ---------------------------------------------------------------------------
-- Minimap shape (ported from PandaUI)
--
-- Minimap:SetMaskTexture is DOCUMENTED_NOT_RUNTIME_VERIFIED here; the square
-- mask is Retail's SquareMask as PandaUI ships it. A failed call keeps the
-- round map. The client keeps a mask across /reload, so a map that is not
-- square always has the stock round mask set back explicitly.
-- ---------------------------------------------------------------------------
local shape = {}

function shape.SetMask(path)
  local minimap = U.G("Minimap")
  if not minimap or type(minimap.SetMaskTexture) ~= "function" or not path then
    return false
  end
  return pcall(minimap.SetMaskTexture, minimap, path) and true or false
end

function shape.Show(region, visible)
  if not region then return end
  pcall(visible and region.Show or region.Hide, region)
end

-- A round map keeps the zoom buttons on its lower-right rim; a square one
-- groups them side by side under its bottom-right corner.
function shape.PlaceZoom(square)
  local minimap = U.G("Minimap")
  local layout = M.modernWow and M.modernWow.minimap
  local zoomIn, zoomOut = modernWowMinimap.zoomIn, modernWowMinimap.zoomOut
  if not minimap or not layout then return end
  if zoomIn then pcall(zoomIn.ClearAllPoints, zoomIn) end
  if zoomOut then pcall(zoomOut.ClearAllPoints, zoomOut) end

  if square then
    local right = layout.squareZoomRightInset / layout.zoomScale
    local below = layout.squareZoomBottomGap / layout.zoomScale
    local gap = layout.squareZoomGap / layout.zoomScale
    if zoomIn then
      pcall(zoomIn.SetPoint, zoomIn, "TOPRIGHT", minimap, "BOTTOMRIGHT",
        -right, -below)
    end
    if zoomOut and zoomIn then
      pcall(zoomOut.SetPoint, zoomOut, "TOPRIGHT", zoomIn, "TOPLEFT", -gap, 0)
    elseif zoomOut then
      pcall(zoomOut.SetPoint, zoomOut, "TOPRIGHT", minimap, "BOTTOMRIGHT",
        -right, -below)
    end
    return
  end

  if zoomIn then
    pcall(zoomIn.SetPoint, zoomIn, "TOPLEFT", minimap, "BOTTOMRIGHT",
      layout.zoomX, layout.zoomY)
  end
  if zoomOut and zoomIn then
    pcall(zoomOut.SetPoint, zoomOut, "TOPRIGHT", zoomIn, "BOTTOMLEFT", 0, 0)
  elseif zoomOut then
    pcall(zoomOut.SetPoint, zoomOut, "TOPLEFT", minimap, "BOTTOMRIGHT",
      layout.zoomX, layout.zoomY - 42.6)
  end
end

-- Mask, ring art and zoom buttons. The settings button and corpse arrow read
-- SquareMinimap() when they are next placed.
function shape.Apply()
  local art = M.modernWow and M.modernWow.texture
  local square = SquareMinimap()
  if square and not (art and shape.SetMask(art.minimapSquareMask)) then
    U.Debug("minimap: square mask failed; map kept round")
    modernWowMinimap.squareFailed = true
    square = false
  end
  if not square then shape.SetMask(M.minimapRoundMask) end
  if not modernWowMinimap.dressed then return square end

  shape.Show(modernWowMinimap.border, not square)
  shape.Show(modernWowMinimap.shadow, not square)
  shape.Show(modernWowMinimap.squareBorder, square)
  shape.PlaceZoom(square)
  U.Debug("minimap shape: " .. (square and "square" or "circle"))
  return square
end

-- ---------------------------------------------------------------------------
-- The pending-mail letter
--
-- Requested for every theme, not just modern-wow: the native envelope beside
-- the minimap is replaced by unrealUI's animated one (M.minimapMail), so the
-- letter folds itself shut when mail arrives and then keeps sparkling while it
-- is still waiting. MiniMapMailFrame stays the client-owned state and mouse
-- owner; the art is an addon-owned texture.
--
-- The focused minimapmail comparison verified that the 256x512 atlas travels
-- when SetTexCoord changes even on an addon-owned Texture, while the same 32
-- cells animate in place as separate files. Keep the visual parented to
-- UIParent and place it from bounded numeric geometry; a native object is never
-- retained as its relative anchor.
-- ---------------------------------------------------------------------------
local mail = { updateId = "minimap.mail", cell = 1, cellTime = 0 }

function mail.SetCell(index)
  local icon = mail.art
  if not icon then return end
  pcall(icon.SetTexture, icon,
    string.format(M.minimapMail.framePattern, index))
end

function mail.HideNativeArt()
  U.HideRegion(U.G("MiniMapMailIcon"))
  U.HideRegion(U.G("MiniMapMailBorder"))
end

function mail.Place(frame)
  local visual = mail.visual
  if not visual or not frame then return false end

  local leftOk, left = pcall(frame.GetLeft, frame)
  local bottomOk, bottom = pcall(frame.GetBottom, frame)
  local widthOk, width = pcall(frame.GetWidth, frame)
  local heightOk, height = pcall(frame.GetHeight, frame)
  if not leftOk or not bottomOk or not widthOk or not heightOk or
     type(left) ~= "number" or type(bottom) ~= "number" or
     type(width) ~= "number" or type(height) ~= "number" then
    return false
  end

  local cfg = M.minimapMail
  local x = left + (width - cfg.size) / 2
  local y = bottom + (height - cfg.size) / 2
  if x == mail.x and y == mail.y then return true end
  mail.x, mail.y = x, y
  pcall(visual.ClearAllPoints, visual)
  pcall(visual.SetPoint, visual, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  return true
end

-- Run on every hidden -> visible transition: restarts the intro, and re-asserts
-- the two things a native refresh is able to put back.
function mail.Rewind()
  mail.HideNativeArt()
  pcall(mail.visual.Show, mail.visual)
  mail.cell = 1
  mail.cellTime = 0
  mail.lastTick = GetTime()
  mail.SetCell(mail.cell)
end

function mail.Tick()
  local frame = U.G("MiniMapMailFrame")
  if not frame then
    mail.shown = false
    pcall(mail.visual.Hide, mail.visual)
    return
  end

  mail.HideNativeArt()
  local ok, visible = pcall(frame.IsVisible, frame)
  if not ok or not visible then
    mail.shown = false
    pcall(mail.visual.Hide, mail.visual)
    return
  end

  if not mail.Place(frame) then
    pcall(mail.visual.Hide, mail.visual)
    mail.shown = false
    return
  end

  if not mail.shown then
    mail.shown = true
    mail.Rewind()
    return
  end

  -- Stepped off elapsed time rather than one cell per fire, so a frame the
  -- shared driver skips under load costs the animation its timing and not its
  -- position. The clamp keeps a long stall (a loading screen) from fast-
  -- forwarding through several cycles at once.
  local now = GetTime()
  local elapsed = now - (mail.lastTick or now)
  mail.lastTick = now
  if elapsed < 0 then elapsed = 0 end
  if elapsed > 0.25 then elapsed = 0.25 end

  local cfg = M.minimapMail
  mail.cellTime = mail.cellTime + elapsed
  while mail.cellTime >= cfg.interval do
    mail.cellTime = mail.cellTime - cfg.interval
    mail.cell = mail.cell + 1
    -- The intro is played once per arrival; the loop is what repeats.
    if mail.cell > cfg.frames then mail.cell = cfg.intro + 1 end
    mail.SetCell(mail.cell)
  end
end

local function DressMailIcon()
  local frame = U.G("MiniMapMailFrame")
  if not frame then
    U.Debug("minimap: no MiniMapMailFrame; mail letter left native")
    return false
  end

  local cfg = M.minimapMail
  local visual = CreateFrame("Frame", "UnrealUIMinimapMail", UIParent)
  visual:SetWidth(cfg.size)
  visual:SetHeight(cfg.size)
  pcall(visual.EnableMouse, visual, false)

  local art = visual:CreateTexture("UnrealUIMinimapMailArt", "ARTWORK")
  art:SetAllPoints(visual)
  mail.visual = visual
  mail.art = art

  mail.Place(frame)
  mail.HideNativeArt()
  mail.SetCell(mail.cell)
  visual:Hide()

  U.RegisterUpdate(mail.updateId, cfg.interval, mail.Tick)
  U.Debug("minimap: mail letter drawn from separate frame textures")
  return true
end

-- ---------------------------------------------------------------------------
-- The settings button on the minimap rim
--
-- The button's centre is anchored to Minimap's centre, rimOffset units outside
-- the map's edge, at the stored angle. It is parented to MinimapCluster, so the
-- edit-mode move and scale of the minimap carry it along; offsets are converted
-- from minimap units into the button's own through the two effective scales,
-- so a Minimap scaled apart from its cluster still lands on the rim.
--
-- Dragging reads the cursor's angle around the map centre every tick and
-- re-anchors the button there: the same GetCursorPosition / GetCenter /
-- GetEffectiveScale arithmetic the ping correction below relies on
-- (knowledge.json / api.getcursorposition_usable_for_hit_testing), and the
-- same Minimap CENTER anchoring as the corpse arrow (modules/playerarrow.lua).
-- Only the drag input below runs StartMoving; the visible button never does.
-- ---------------------------------------------------------------------------
local rim = { dragging = false, gesture = nil, angle = nil,
              updateId = "minimap.buttonrim", placeId = "minimap.buttonplace" }

-- Same quadrant handling as modules/playerarrow.lua: only math.atan is relied on.
function rim.Atan2(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 then
    if y >= 0 then return math.atan(y / x) + math.pi end
    return math.atan(y / x) - math.pi
  end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

-- Minimap units -> the button's own units.
function rim.Ratio(button, minimap)
  local okMap, mapScale = pcall(minimap.GetEffectiveScale, minimap)
  local okButton, buttonScale = pcall(button.GetEffectiveScale, button)
  if not okMap or not okButton or type(mapScale) ~= "number" or
     type(buttonScale) ~= "number" or buttonScale == 0 then
    return 1
  end
  return mapScale / buttonScale
end

-- Puts the button on the rim at `angle` degrees (counter-clockwise from the
-- right). Returns what it was anchored to, or nil when the map is unreadable.
function rim.Place(button, angle)
  local minimap = U.G("Minimap")
  if not minimap then return nil end
  local ok, width = pcall(minimap.GetWidth, minimap)
  if not ok or type(width) ~= "number" or width <= 0 then return nil end

  local radians = angle * math.pi / 180
  local cos, sin = math.cos(radians), math.sin(radians)
  -- A square map's edge is the square, not the inscribed circle.
  local radius = (width / 2 + M.minimapButton.rimOffset) *
                 SquareStretch(cos, sin) * rim.Ratio(button, minimap)
  pcall(button.ClearAllPoints, button)
  button:SetPoint("CENTER", minimap, "CENTER", cos * radius, sin * radius)
  return "the minimap rim"
end
-- The grouped-icons launcher (modules/minimapgroup.lua) sits on the same rim.
U.MinimapRimPlace = rim.Place

-- The cursor's angle around the map centre in degrees, 0..360, or nil.
function rim.CursorAngle(minimap)
  if type(GetCursorPosition) ~= "function" then return nil end
  local ok, cursorX, cursorY = pcall(GetCursorPosition)
  if not ok or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return nil end

  local scaleOk, scale = pcall(minimap.GetEffectiveScale, minimap)
  if not scaleOk or type(scale) ~= "number" or scale == 0 then return nil end

  local centerOk, centerX, centerY = pcall(minimap.GetCenter, minimap)
  if not centerOk or type(centerX) ~= "number" or type(centerY) ~= "number" then return nil end

  local dx = cursorX / scale - centerX
  local dy = cursorY / scale - centerY
  if dx == 0 and dy == 0 then return nil end
  local degrees = rim.Atan2(dy, dx) * 180 / math.pi
  if degrees < 0 then degrees = degrees + 360 end
  return degrees
end

function rim.Track()
  local button = MM.button
  local minimap = U.G("Minimap")
  if not button or not minimap then return end
  local angle = rim.CursorAngle(minimap)
  if not angle then return end
  rim.angle = angle
  rim.Place(button, angle)
end

-- Places the button at its stored angle. Also runs after /uui reset, which
-- has already put the angle back to its default. Falls back to the map's side,
-- then the cluster, then the screen corner, rather than not existing.
local function AnchorButton(button)
  -- Inside the grouped icons (modules/minimapgroup.lua) the flyout lays it out.
  if rim.grouped then return "the grouped minimap icons" end
  local placed = rim.Place(button, MinimapConfig().buttonAngle)
  if placed then return placed end

  pcall(button.ClearAllPoints, button)
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

  U.RegisterMover("minimap", target, {
    label = U.L("MOVER_LABEL_MINIMAP"),
    default = default,
    scalable = true,
  })
  U.Debug("minimap mover registered on " .. name)
end

-- ---------------------------------------------------------------------------
-- The round settings button and its drag around the rim
--
-- Two layers, the same split edit mode's anchors use (core/mover.lua):
--
-- * `button` is the visible part: the addon logo, which is round with
--   transparent corners, plus an additive copy of it as the hover glow. It
--   takes no mouse. It lives on the rim and is re-anchored every tick while
--   dragged.
-- * `input` is a transparent Button parented to UIParent that covers it and
--   owns click, hover and drag. A frame re-anchored while it is the dragged
--   widget loses its release on this client -- the button kept following the
--   cursor after the click was let go (user report, 2026-11-26; knowledge.json /
--   widgets.thumb_reposition_during_drag_breaks_drag). So the input is cut loose
--   in UIParent space when the drag starts, runs the verified StartMoving
--   recipe (frames.movable_drag_requires_button_handle) and is never touched
--   until the drop, while only `button` follows the cursor. The drop arrives
--   through OnDragStop, with OnMouseUp as the second path because this client
--   documents no IsMouseButtonDown to poll a missed release.
-- ---------------------------------------------------------------------------

-- Re-points the input over the visible button, so the next press lands on it.
function rim.AttachInput(button, input)
  pcall(input.ClearAllPoints, input)
  pcall(input.SetAllPoints, input, button)
end

-- Gives the input the button's current rect in UIParent space, once.
function rim.DetachInput(button, input)
  local widthOk, width = pcall(button.GetWidth, button)
  local centreOk, centreX, centreY = pcall(button.GetCenter, button)
  if not widthOk or not centreOk or type(width) ~= "number" or
     type(centreX) ~= "number" or type(centreY) ~= "number" then
    U.Debug("minimap button: drag input keeps its button anchor")
    return false
  end
  local ratio = rim.Ratio(input, button)  -- button units -> UIParent units
  pcall(input.ClearAllPoints, input)
  input:SetWidth(width * ratio)
  input:SetHeight(width * ratio)
  input:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centreX * ratio, centreY * ratio)
  return true
end

function rim.StartDrag(button, input)
  if rim.dragging then return true end
  -- No rim to slide along while the button sits in the grouped icons.
  if rim.grouped then return false end
  rim.DetachInput(button, input)

  if not pcall(input.SetMovable, input, true) then
    U.Error("minimap button: SetMovable failed; the button cannot be moved")
    rim.AttachInput(button, input)
    return false
  end
  if pcall(input.StartMoving, input) then
    pcall(input.StopMovingOrSizing, input)
  end
  if not pcall(input.StartMoving, input) then
    U.Error("minimap button: StartMoving failed; the button will not drag")
    rim.AttachInput(button, input)
    return false
  end

  rim.dragging = true
  rim.angle = nil
  U.RegisterUpdate(rim.updateId, 0, rim.Track)
  return true
end

-- Idempotent: OnDragStop and OnMouseUp may both arrive.
function rim.StopDrag(button, input)
  if not rim.dragging then return false end
  rim.dragging = false
  U.UnregisterUpdate(rim.updateId)
  pcall(input.StopMovingOrSizing, input)
  rim.Track()
  rim.AttachInput(button, input)

  if not rim.angle then
    U.Debug("minimap button: cursor angle unreadable on drop; angle kept")
    AnchorButton(button)
    return false
  end
  MinimapConfig().buttonAngle = math.floor(rim.angle * 10 + 0.5) / 10
  return true
end

function rim.SetHover(button, on)
  if button.glow then
    if on then button.glow:Show() else button.glow:Hide() end
  end
end

function rim.SetPressed(button, on)
  if button.logo then
    local shade = on and 0.75 or 1
    pcall(button.logo.SetVertexColor, button.logo, shade, shade, shade, 1)
  end
end

function rim.BuildButton(parent)
  local size = M.minimapButton.size
  local button = CreateFrame("Frame", "UnrealUISettingsButton", parent)
  button:SetWidth(size)
  button:SetHeight(size)
  pcall(button.EnableMouse, button, false)

  local logo = button:CreateTexture(nil, "ARTWORK")
  logo:SetAllPoints(button)
  logo:SetTexture(M.texture.addonLogo)
  button.logo = logo

  local glow = button:CreateTexture(nil, "OVERLAY")
  glow:SetAllPoints(button)
  glow:SetTexture(M.texture.addonLogo)
  pcall(glow.SetBlendMode, glow, "ADD")
  pcall(glow.SetAlpha, glow, M.minimapButton.hoverGlow)
  glow:Hide()
  button.glow = glow

  local input = CreateFrame("Button", "UnrealUISettingsButtonInput", UIParent)
  rim.AttachInput(button, input)
  pcall(input.EnableMouse, input, true)
  pcall(input.RegisterForDrag, input, "LeftButton")
  button.input = input

  -- knowledge.json / scripts.handler_arguments_direct: every handler closes
  -- over its frames instead of reading callback arguments.
  input:SetScript("OnEnter", function() rim.SetHover(button, true) end)
  input:SetScript("OnLeave", function()
    if not rim.dragging then rim.SetHover(button, false) end
  end)
  input:SetScript("OnMouseDown", function()
    rim.gesture = nil
    rim.SetPressed(button, true)
  end)
  input:SetScript("OnDragStart", function()
    rim.gesture = true
    rim.StartDrag(button, input)
  end)
  input:SetScript("OnDragStop", function() rim.StopDrag(button, input) end)
  input:SetScript("OnMouseUp", function()
    rim.SetPressed(button, false)
    rim.StopDrag(button, input)
  end)
  input:SetScript("OnClick", function()
    -- Releasing a drag must not also open the window.
    if rim.gesture then
      rim.gesture = nil
      return
    end
    if type(U.OpenSettings) == "function" then U.OpenSettings() end
  end)

  -- The input is a UIParent child, so it follows the visible button's shown
  -- state explicitly: hidden with the minimap cluster, hidden by the option.
  button:SetScript("OnShow", function() input:Show() end)
  button:SetScript("OnHide", function()
    rim.StopDrag(button, input)
    rim.SetHover(button, false)
    input:Hide()
  end)
  return button
end

-- Places the button once the map has a size. Minimap can still read 0 wide
-- when the module enables -- the button then appeared beside the map instead
-- of on it (user report, 2026-11-26) -- so a short retry follows the fallback.
function rim.PlaceWhenReady(button)
  local anchor = AnchorButton(button)
  if anchor == "the minimap rim" then return anchor end

  local tries = 0
  U.RegisterUpdate(rim.placeId, 0.1, function()
    tries = tries + 1
    if rim.dragging or rim.grouped or
       rim.Place(button, MinimapConfig().buttonAngle) or tries >= 100 then
      U.UnregisterUpdate(rim.placeId)
    end
  end)
  return anchor
end

-- The same rim drag for another icon on the rim: the grouped-icons launcher
-- (modules/minimapgroup.lua, user request 2026-11-26). Same two-layer split
-- as the settings button above -- `button` is visible and takes no mouse, the
-- returned input is a UIParent Button that owns click, hover and drag -- with
-- its own state, so the two icons never share a drag.
--
-- opts: name, updateId, getAngle(), setAngle(degrees), onClick(),
-- onHover(on), onPress(on), onDragStart(); all optional but the first three.
function rim.MakeDraggable(button, opts)
  local state = { dragging = false, gesture = nil, angle = nil }
  local input = CreateFrame("Button", opts.name, UIParent)
  rim.AttachInput(button, input)
  pcall(input.EnableMouse, input, true)
  pcall(input.RegisterForDrag, input, "LeftButton")

  local function Call(fn, value)
    if type(fn) == "function" then fn(value) end
  end

  local function Track()
    local minimap = U.G("Minimap")
    if not minimap then return end
    local angle = rim.CursorAngle(minimap)
    if not angle then return end
    state.angle = angle
    rim.Place(button, angle)
  end

  local function Start()
    if state.dragging then return end
    rim.DetachInput(button, input)
    if not pcall(input.SetMovable, input, true) then
      rim.AttachInput(button, input)
      return
    end
    if pcall(input.StartMoving, input) then
      pcall(input.StopMovingOrSizing, input)
    end
    if not pcall(input.StartMoving, input) then
      rim.AttachInput(button, input)
      return
    end
    state.dragging = true
    state.angle = nil
    Call(opts.onDragStart)
    U.RegisterUpdate(opts.updateId, 0, Track)
  end

  -- Idempotent: OnDragStop and OnMouseUp may both arrive.
  local function Stop()
    if not state.dragging then return end
    state.dragging = false
    U.UnregisterUpdate(opts.updateId)
    pcall(input.StopMovingOrSizing, input)
    Track()
    rim.AttachInput(button, input)
    if state.angle then
      opts.setAngle(math.floor(state.angle * 10 + 0.5) / 10)
    else
      rim.Place(button, opts.getAngle())
    end
  end

  input:SetScript("OnEnter", function() Call(opts.onHover, true) end)
  input:SetScript("OnLeave", function()
    if not state.dragging then Call(opts.onHover, false) end
  end)
  input:SetScript("OnMouseDown", function()
    state.gesture = nil
    Call(opts.onPress, true)
  end)
  input:SetScript("OnDragStart", function()
    state.gesture = true
    Start()
  end)
  input:SetScript("OnDragStop", Stop)
  input:SetScript("OnMouseUp", function()
    Call(opts.onPress, false)
    Stop()
  end)
  input:SetScript("OnClick", function()
    -- Releasing a drag must not also click the icon.
    if state.gesture then
      state.gesture = nil
      return
    end
    Call(opts.onClick)
  end)

  -- The input is a UIParent child: it follows the button's visibility.
  button:SetScript("OnShow", function() input:Show() end)
  button:SetScript("OnHide", function()
    Stop()
    Call(opts.onHover, false)
    input:Hide()
  end)
  local visibleOk, visible = pcall(button.IsVisible, button)
  if visibleOk and visible then input:Show() else input:Hide() end

  function state.IsDragging() return state.dragging end
  return input, state
end
U.MinimapRimDraggable = rim.MakeDraggable

-- Called by modules/minimapgroup.lua when the settings button joins or leaves
-- the grouped icons. Its visible frame is reparented there; the input that
-- owns its click follows it through SetAllPoints, but is a UIParent child and
-- would stay under the DIALOG flyout, so it is raised over the flyout while
-- grouped and put back, with the button on the rim, when released.
function rim.SetGrouped(grouped)
  local button = MM.button
  local input = button and button.input
  if grouped then
    if input and rim.dragging then rim.StopDrag(button, input) end
    rim.grouped = true
    if not input then return end
    if not rim.inputStrata then
      local ok, strata = pcall(input.GetFrameStrata, input)
      rim.inputStrata = ok and strata or "MEDIUM"
    end
    pcall(input.SetFrameStrata, input, "DIALOG")
    local parentOk, parent = pcall(button.GetParent, button)
    local level
    if parentOk and parent then
      local levelOk, value = pcall(parent.GetFrameLevel, parent)
      if levelOk and type(value) == "number" then level = value end
    end
    pcall(input.SetFrameLevel, input, (level or 0) + 6)
    rim.AttachInput(button, input)
    return
  end

  rim.grouped = false
  if not button then return end
  if input then
    pcall(input.SetFrameStrata, input, rim.inputStrata or "MEDIUM")
    rim.AttachInput(button, input)
  end
  AnchorButton(button)
end
U.MinimapSettingsButtonGrouped = rim.SetGrouped

local function EnableButtonDrag(button)
  -- /uui reset puts the button back at its default angle.
  U.OnPositionReset(function()
    MinimapConfig().buttonAngle = M.minimapButton.defaultAngle
    return AnchorButton(button) and true
  end)
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
  if SquareMinimap() then
    if math.abs(offsetX) > radius or math.abs(offsetY) > radius then return nil end
  elseif (offsetX * offsetX + offsetY * offsetY) > (radius * radius) then
    return nil
  end
  return offsetX, offsetY
end

-- Runs after the client has placed the ping: Minimap_SetPing(x, y, playSound).
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

  if MinimapConfig().enabled then
    button:Show()
    if button.input and button:IsVisible() then button.input:Show() end
  else
    button:Hide()
    if button.input then button.input:Hide() end
  end
end
U.ApplyMinimapButton = Apply

-- Stores and applies the shape, then re-seats the settings button on the new
-- edge. The corpse arrow reads U.MinimapIsSquare on its next tick. The
-- settings page and the minimap's edit-mode panel both show the shape, so
-- whichever changed it tells the other to re-read it.
local function SetShape(value)
  MinimapConfig().shape = value == "square" and "square" or "circle"
  shape.Apply()
  if MM.button and not rim.dragging then AnchorButton(MM.button) end
  if U.MinimapGroup then U.MinimapGroup.PlaceLauncher() end
  if type(U.RefreshSettingsPage) == "function" then U.RefreshSettingsPage("minimap") end
  if type(U.RefreshMoverPanel) == "function" then U.RefreshMoverPanel("minimap") end
end

function shape.Items()
  return {
    { value = "circle", text = U.L("SETTINGS_MINIMAP_SHAPE_CIRCLE") },
    { value = "square", text = U.L("SETTINGS_MINIMAP_SHAPE_SQUARE") },
  }
end

function shape.Current()
  return MinimapConfig().shape == "square" and "square" or "circle"
end

-- The minimap anchor's edit-mode panel: the shape dropdown where the shape
-- applies (the dressed minimap), then the grouped-icons switch and the icons
-- to keep on the map (modules/minimapgroup.lua), over the shared scale row.
shape.PANEL_WIDTH = 220
-- Caption 16 + dropdown 24 + a 12 gap before the group switch.
shape.SHAPE_HEIGHT = 52

-- Panel height before the scale row: header, content, and the 12 bottom pad.
function shape.PanelHeight()
  local height = 44 + 12
  if modernWowMinimap.dressed then height = height + shape.SHAPE_HEIGHT end
  if U.MinimapGroup then
    height = height + (shape.groupHeight or U.MinimapGroup.ControlsHeight())
  end
  return height
end

function shape.BuildMoverPanel(frame, contentTop)
  local widgets = {}
  local refreshers = {}
  local pad = U.MoverPanelPad()
  local function Refresh()
    local i
    for i = 1, table.getn(refreshers) do refreshers[i]() end
  end

  local groupTop = contentTop
  if modernWowMinimap.dressed then
    shape.BuildShapeRow(frame, contentTop, pad, widgets, refreshers)
    groupTop = contentTop - shape.SHAPE_HEIGHT
  end

  if U.MinimapGroup then
    local groupWidgets, groupRefresh, height = U.MinimapGroup.BuildControls(
      frame, frame, groupTop, shape.PANEL_WIDTH, "UnrealUIMinimapMoverGroup", false)
    shape.groupHeight = height
    local i
    for i = 1, table.getn(groupWidgets) do
      local widget = groupWidgets[i]
      -- BuildControls anchors to the frame's left edge; inset by the pad.
      if i == 1 and widget.SetPoint then
        widget.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, groupTop)
      end
      table.insert(widgets, widget)
    end
    table.insert(refreshers, groupRefresh)
  end

  return widgets, Refresh
end

function shape.BuildShapeRow(frame, contentTop, pad, widgets, refreshers)
  local caption = U.CreateSettingsLabel(frame, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = shape.PANEL_WIDTH,
  })
  if caption then
    caption:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
    caption:SetText(U.L("SETTINGS_MINIMAP_SHAPE"))
    table.insert(widgets, caption)
  end

  local drop = U.CreateDropdown(frame, {
    name = "UnrealUIMinimapMoverShape",
    width = shape.PANEL_WIDTH,
    height = 24,
    rowHeight = 20,
    value = shape.Current(),
    items = shape.Items(),
    onChange = function(value) SetShape(value) end,
  })
  drop.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop - 16)
  table.insert(widgets, drop)
  table.insert(refreshers, function() drop.SetValue(shape.Current(), false) end)
end

local function BuildSettingsPage(parent)
  local widgets = {}
  local cfg = MinimapConfig()
  local header = U.CreateSectionHeader(parent, {
    text = U.L("SETTINGS_PAGE_MINIMAP"),
    width = U.SETTINGS_PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local button = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMinimapButton",
    text = U.L("SETTINGS_MINIMAP_BUTTON"),
    value = cfg.enabled,
    onChange = function(value)
      cfg.enabled = value and true or false
      Apply()
    end,
  })
  button.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, button)

  -- The same range and stored value as the minimap anchor's edit-mode slider.
  local scaleMin, scaleMax, scaleStep = U.MoverScaleRange()
  local scale = U.CreateSlider(parent, {
    name = "UnrealUISettingsMinimapScale",
    text = U.L("SETTINGS_MINIMAP_SCALE"),
    width = 220,
    min = scaleMin,
    max = scaleMax,
    step = scaleStep,
    value = U.GetMoverScale("minimap"),
    onInput = function(value) U.PreviewMoverScale("minimap", value) end,
    onChange = function(value) U.SetMoverScale("minimap", value) end,
  })
  scale.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -94)
  table.insert(widgets, scale)

  local zone = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMinimapZone",
    text = U.L("SETTINGS_MINIMAP_ZONE"),
    value = cfg.showZone,
    onChange = function(value)
      cfg.showZone = value and true or false
      ApplyChromeSettings()
    end,
  })
  zone.SetPoint("TOPLEFT", scale.track, "BOTTOMLEFT", 0, -54)
  zone.SetEnabled(modernWowMinimap.dressed)
  table.insert(widgets, zone)

  local zoom = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMinimapZoom",
    text = U.L("SETTINGS_MINIMAP_ZOOM_BUTTONS"),
    value = cfg.showZoom,
    onChange = function(value)
      cfg.showZoom = value and true or false
      ApplyChromeSettings()
    end,
  })
  zoom.SetPoint("TOPLEFT", zone.box, "BOTTOMLEFT", 0, -18)
  zoom.SetEnabled(modernWowMinimap.dressed)
  table.insert(widgets, zoom)

  -- Circle or square, as PandaUI's Minimap shape dropdown.
  local shapeLabel = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    width = 220,
    height = 14,
    justify = "LEFT",
  })
  if shapeLabel then
    shapeLabel:SetPoint("TOPLEFT", zoom.box, "BOTTOMLEFT", 0, -18)
    shapeLabel:SetText(U.L("SETTINGS_MINIMAP_SHAPE"))
    table.insert(widgets, shapeLabel)
  end

  local shapeDrop = U.CreateDropdown(parent, {
    name = "UnrealUISettingsMinimapShape",
    width = 220,
    height = 24,
    rowHeight = 20,
    value = shape.Current(),
    items = shape.Items(),
    onChange = function(value) SetShape(value) end,
  })
  shapeDrop.SetPoint("TOPLEFT", zoom.box, "BOTTOMLEFT", 0, -36)
  shapeDrop.SetEnabled(modernWowMinimap.dressed)
  table.insert(widgets, shapeDrop)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = U.SETTINGS_PAGE_WIDTH,
  })
  if hint then
    U.AnchorSettingsDescription(hint, shapeDrop.button)
    hint:SetText(U.L("SETTINGS_MINIMAP_CHROME_HINT"))
    table.insert(widgets, hint)
  end

  -- Grouped icons (modules/minimapgroup.lua), under the chrome hint: they
  -- apply on every theme. Anchored to the dropdown, never to the hint.
  local groupRefresh
  if U.MinimapGroup then
    local groupY = -(24 + U.SettingsDescriptionDrop(hint, 24) + 18)
    local groupWidgets
    groupWidgets, groupRefresh = U.MinimapGroup.BuildControls(
      parent, shapeDrop.button, groupY, U.SETTINGS_PAGE_WIDTH,
      "UnrealUISettingsMinimapGroup", true)
    local i
    for i = 1, table.getn(groupWidgets) do table.insert(widgets, groupWidgets[i]) end
  end

  local function Refresh()
    cfg = MinimapConfig()
    button.SetValue(cfg.enabled)
    scale.SetValue(U.GetMoverScale("minimap"))
    zone.SetValue(cfg.showZone)
    zoom.SetValue(cfg.showZoom)
    zone.SetEnabled(modernWowMinimap.dressed)
    zoom.SetEnabled(modernWowMinimap.dressed)
    shapeDrop.SetValue(shape.Current(), false)
    shapeDrop.SetEnabled(modernWowMinimap.dressed)
    if groupRefresh then groupRefresh() end
  end
  return widgets, Refresh
end

function MM:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("minimap", U.L("SETTINGS_PAGE_MINIMAP"),
                          BuildSettingsPage, { after = "general" })
  end
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel("minimap", {
      name = "UnrealUIMinimapMoverSettings",
      width = shape.PANEL_WIDTH + U.MoverPanelPad() * 2,
      height = shape.PanelHeight,
      build = shape.BuildMoverPanel,
      title = function() return U.L("MOVER_LABEL_MINIMAP") end,
    })
  end
end

function MM:OnEnable()
  if self.button then return end

  DressModernWowMinimap()
  ApplyChromeSettings()
  shape.Apply()

  -- The free position from before the button followed the rim is dropped
  -- once; the button now lives on the rim at its stored angle.
  if U.db and type(U.db.positions) == "table" then
    U.db.positions[LEGACY_POSITION_ID] = nil
  end

  -- Parented to the cluster so the minimap's edit-mode move and scale carry
  -- it, and raised over the map's own child frames (zone panel, ring art).
  local minimap = U.G("Minimap")
  local parent = U.G("MinimapCluster") or UIParent
  local button = rim.BuildButton(parent)

  if minimap then
    local ok, level = pcall(minimap.GetFrameLevel, minimap)
    if ok and type(level) == "number" then
      pcall(button.SetFrameLevel, button, level + 10)
    end
  end

  local anchor = rim.PlaceWhenReady(button)
  EnableButtonDrag(button)

  self.button = button
  Apply()
  U.Debug("settings button anchored to " .. anchor)

  RegisterMinimapMover()
  HookPingPlacement()

  -- Grouped icons, in their own pcall so a failure cannot take the rest down.
  if U.MinimapGroup then
    local groupOk, groupErr = pcall(U.MinimapGroup.Enable)
    if not groupOk then U.Error("minimap grouping: " .. tostring(groupErr)) end
  end

  -- Last, and inside its own pcall. RunModulePhase already wraps OnEnable, so
  -- an error raised here would abort the whole method -- and everything above
  -- it, the settings button included, would silently not exist. The mail
  -- letter is decoration; nothing else in this module may depend on it.
  local dressed, err = pcall(DressMailIcon)
  if not dressed then
    U.Error("minimap mail letter: " .. tostring(err))
  end
end
