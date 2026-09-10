-- unrealUI :: modules/petbar.lua
--
-- Native mode keeps the original pet buttons, adds a mover handle and removes
-- only the two outer decorative textures. Custom mode is explicitly opt-in.
--
-- Why the native bar is the default
--
--   documentation.json / global:Pet:CastPetAction (OFFICIAL_CLIENT_DOCUMENTATION)
--   marks the call this client uses to activate a pet action as *protected*:
--   "addons cannot call this; only the default FrameXML UI can", and
--   documentation.json / reference:Conventions states the failure mode plainly
--   -- "Addons cannot call them; the call errors."
--
--   The unprotected substitutes cover the command and stance slots only:
--   PetAttack (documented as "Same as CastPetAction(1), but not protected"),
--   PetFollow, PetWait, PetAggressiveMode, PetDefensiveMode, PetPassiveMode
--   -- slots 1-3 and 8-10. There is no unprotected route to the *spell* slots
--   4-7, which is where a warlock's Torment / Suffering / Consume Shadows /
--   Sacrifice and a hunter's pet abilities live. A custom pet bar on this
--   client therefore cannot cast them at all, and the previous version of this
--   module made that worse by also suppressing (hide + alpha 0 + neutralised
--   Show + EnableMouse(false)) the native bar that can.
--
--   That is a client capability limit, not a bug with a workaround. The user
--   explicitly requested the old Modern bar as an opt-in experiment; it lives
--   in petbarcustom.lua and warns rather than pretending spell clicks work.
--   Native is the default regardless of theme or legacy petbar.enabled values.
--
-- Native mode
--
--   The native bar and its buttons are never hidden or click-handled. Only
--   the separately captured outer artwork is stripped; icons, cooldowns and
--   autocast/state regions are untouched. An unrealUI-owned anchor frame
--   carries the mover handle, and the native bar is pointed
--   at it only once the player has actually placed it. Until then the anchor
--   follows the native bar and its position is not written at all, so an
--   untouched interface keeps the client's own pet bar position.
--
--   The one structural change is the parent, and only because it has to be:
--   see the parent section below.
--
-- Compatibility notes that shaped this file:
--
--   * The handle lives on an unrealUI frame rather than on PetActionBarFrame
--     directly (the way modules/minimap.lua registers MinimapCluster). The
--     mover handle is SetAllPoints to the frame it is registered on, and this
--     client's root size need not match its visible buttons. The 2026-08-30
--     interface capture measured a 509x43 root and ten 30x30 buttons. An owned
--     frame gives the mover its own footprint without resizing native buttons.
--   * The native bar's own anchor is not UIParent-relative, so it cannot be
--     expressed as a mover `default`. core/mover.lua documents U.OnPositionReset
--     as the route for exactly that case; the anchor read at load is replayed
--     from there so /uui reset really does put the bar back where the client
--     had it.
--   * knowledge.json / frames.getpoint_relative_name_y_inverted: anchors are
--     read through U.GetFramePoint, which hands back values in the shape
--     SetPoint expects. The captured native anchor is replayed with those
--     values unchanged.
--   * UNIT_PET and the PET_BAR_* events have no compact record on this client
--     (query_compat.py returns no match, events.json holds no pet capture), so
--     they are accelerators only. The slow shared updater is the guarantee.

local U = UnrealUI

local PB = U.RegisterModule("petbar")

local NATIVE_NAME = "PetActionBarFrame"
local DEFAULTS = {
  mode = "native",
  perRow = 10,
  size = 24,
  spacing = 2,
  showAutocast = true,
  -- Native-mode button geometry. buttonLayout false leaves the client's own
  -- button size and gap completely untouched, which is the default; the two
  -- values below are only read once it is on, and 0 / -1 there mean "whatever
  -- the client's own row measured".
  buttonLayout = false,
  buttonSize = 0,
  buttonSpacing = -1,
}
local cfg
local activeMode = "native"

local function Config()
  cfg = U.ModuleConfig("petbar", DEFAULTS)
  if cfg.mode ~= "custom" then cfg.mode = "native" end
  return cfg
end

local function ModeLabel(mode)
  return U.L(mode == "custom" and "PETBAR_MODE_CUSTOM" or "PETBAR_MODE_NATIVE")
end

-- Handles /uui petbar size|spacing|reset|status. Defined further down, next to
-- the layout code it drives, so nothing up here has to know how the native
-- buttons are placed.
local ButtonCommand

-- Native suppression is not reversible in-session. Save the preference only;
-- the next reload builds exactly one bar and registers exactly one pet mover.
function U.PetBarCommand(choice)
  if not U.db then U.Print(U.L("PETBAR_UNAVAILABLE")); return end
  local config = Config()
  choice = type(choice) == "string" and string.lower(choice) or ""
  choice = string.gsub(string.gsub(choice, "^%s+", ""), "%s+$", "")

  -- string.match does not exist on this client's Lua (see modules/spellbook.lua),
  -- so the verb is split off with string.find/string.sub.
  local verb, argument = choice, ""
  local space = string.find(choice, " ")
  if space then
    verb = string.sub(choice, 1, space - 1)
    argument = string.gsub(string.sub(choice, space + 1), "^%s+", "")
  end

  -- Geometry only: applied live, no reload, and it never touches the mode.
  if verb == "size" or verb == "spacing" or verb == "reset" then
    if ButtonCommand then
      ButtonCommand(verb, argument)
    else
      U.Print(U.L("PETBAR_UNAVAILABLE"))
    end
    return
  end

  if choice == "native" or choice == "custom" then
    config.mode = choice
    U.Print(U.L("PETBAR_MODE_SELECTED", ModeLabel(choice)))
  else
    U.Print(U.L("PETBAR_MODE_STATUS", ModeLabel(activeMode), ModeLabel(config.mode)))
    if ButtonCommand then ButtonCommand("status", "") end
    U.Print(U.L("CMD_PETBAR"))
    U.Print(U.L("CMD_PETBAR_BUTTONS"))
  end
  if config.mode == "custom" then U.Print(U.L("PETBAR_CUSTOM_WARNING")) end
end

-- Used only until the native bar reports its own size, and as the handle's
-- footprint if it never does: ten stock pet buttons in a row.
local FALLBACK_WIDTH  = 320
local FALLBACK_HEIGHT = 36

-- Anchor offsets below this are treated as "unchanged" rather than drift.
local DRIFT_EPSILON = 0.5

local anchor = nil
local native = nil
local nativeAnchor = nil
local nativeParent = nil
local driving = false
local reparented = false
local driveFailures = 0
local editNativeHidden = false
local editNativeWasShown = false

-- Native button geometry (native mode only).
--
-- knowledge.json / petbar.native_outer_art_separate: the 2026-08-30 interface
-- capture measured PetActionButton1-10 as ten 30x30 CheckButtons on a 509x43
-- root, so the row is narrower than the frame that carries it. The live values
-- are read from the buttons themselves; these are only the fallbacks.
local BUTTON_COUNT = 10
local BUTTON_PREFIX = "PetActionButton"
local NATIVE_BUTTON_SIZE = 30
local NATIVE_BUTTON_GAP = 7
local MIN_BUTTON_SIZE = 12
local MAX_BUTTON_SIZE = 64
local MAX_BUTTON_GAP = 32

local slots = {}          -- index -> unrealUI-owned holder frame
local petButtons = {}     -- index -> native button + its captured stock anchor
local captured = false
local nativeGeometry = nil
local appliedLayout = nil

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Same resolve-by-name-and-pcall shape as modules/actionbar.lua: a missing call
-- costs one behaviour rather than erroring the module.
-- ---------------------------------------------------------------------------
local apiFnCache = {}

local function ResolveApiFn(name)
  local cached = apiFnCache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local fn = U.G(name)
  if type(fn) == "function" then
    apiFnCache[name] = fn
    return fn
  end
  apiFnCache[name] = false
  return nil
end

local function Call(name, a)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, result = pcall(fn, a)
  if not ok then return nil end
  return result
end

local function Number(value)
  value = tonumber(value)
  if not value or value <= 0 then return nil end
  return value
end

-- The 2026-08-30 interface capture identifies exactly these two Texture regions
-- directly on PetActionBarFrame. Do not strip the whole hierarchy or the button
-- faces: the buttons also carry meaningful flash, border and autocast state.
-- Re-resolve on the existing refresh so newly created/re-shown art is covered,
-- without replacing any native Show, update, mouse or click handler.
local function HideNativeBorder()
  local i
  for i = 0, 1 do
    local region = U.G("SlidingActionBarTexture" .. i)
    if region then
      local ok, objectType = pcall(region.GetObjectType, region)
      if ok and objectType == "Texture" then U.HideRegion(region) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- The client's own anchor
--
-- Captured once, before the mover is registered and therefore before anything
-- of ours can have moved the bar. Replayed on /uui reset. U.GetFramePoint
-- already returns the relative frame resolved and Y in the sign SetPoint wants
-- (knowledge.json / frames.getpoint_relative_name_y_inverted), so the capture
-- goes straight back through SetPoint unchanged.
-- ---------------------------------------------------------------------------
local function CaptureNativeAnchor()
  if not native then return nil end

  local point, relative, relativePoint, x, y = U.GetFramePoint(native, 1)
  if type(point) ~= "string" then
    U.Debug("petbar: no readable native anchor to capture")
    return nil
  end

  if not relative then
    local ok, parent = pcall(native.GetParent, native)
    if ok then relative = parent end
  end
  if not relative then relative = UIParent end

  return {
    point = point,
    relative = relative,
    relativePoint = relativePoint or point,
    x = x,
    y = y,
  }
end

local function RestoreNativeAnchor()
  if not native or not nativeAnchor then return false end

  local ok = pcall(function()
    native:ClearAllPoints()
    native:SetPoint(nativeAnchor.point, nativeAnchor.relative,
                    nativeAnchor.relativePoint, nativeAnchor.x, nativeAnchor.y)
  end)

  if ok then
    driving = false
    U.Debug("petbar: native pet bar anchor restored")
  end
  return ok
end

-- ---------------------------------------------------------------------------
-- Placement
--
-- Two modes, decided only by whether the player has ever dropped this mover:
--
--   no stored position -- the anchor follows the native bar and the native bar
--     is never written to. An interface nobody has rearranged keeps the
--     client's pet bar exactly where the client puts it.
--   stored position    -- the mover owns the anchor (UIParent-relative) and the
--     native bar is pointed at it.
--
-- The two are never active at once, so the frames cannot chase each other.
-- ---------------------------------------------------------------------------
local function StoredPosition()
  local ok, position = pcall(U.GetPosition, "petbar")
  if not ok or type(position) ~= "table" then return nil end
  if type(position.point) ~= "string" then return nil end
  return position
end

-- Only written when it actually changes: this runs on the shared tick, and the
-- handle is SetAllPoints to this frame, so a size write is a handle relayout
-- every second for nothing.
local function SetAnchorSize(width, height)
  if not anchor then return end
  if anchor.uuiWidth ~= width then
    anchor:SetWidth(width)
    anchor.uuiWidth = width
  end
  if anchor.uuiHeight ~= height then
    anchor:SetHeight(height)
    anchor.uuiHeight = height
  end
end

-- Used while the client owns the button geometry. Once unrealUI lays the row
-- out, the handle takes the row's own footprint instead, which is narrower
-- than the 509-wide native root.
local function MirrorNativeSize()
  if not anchor or not native then return end

  local okW, w = pcall(native.GetWidth, native)
  local okH, h = pcall(native.GetHeight, native)

  SetAnchorSize((okW and Number(w)) or FALLBACK_WIDTH,
                (okH and Number(h)) or FALLBACK_HEIGHT)
end

-- ---------------------------------------------------------------------------
-- Native button size and spacing
--
-- Two things change on the client's own buttons, and only once the player has
-- asked for it with /uui petbar size|spacing:
--
--   * SetScale, never SetWidth/SetHeight. A pet button's icon, flash, border,
--     autocast overlay and cooldown are separately sized regions of the
--     button; resizing the button alone would leave them at their stock size
--     around a smaller face. Scale carries the whole face with it, which is
--     what modules/microbar.lua already does to the stock micro buttons.
--   * The anchor, onto one unrealUI-owned slot frame per button. The slots are
--     unscaled children of our anchor frame and each button sits at
--     CENTER/CENTER 0,0 on its own slot, so the row arithmetic never has to
--     assume how this client scales SetPoint offsets on a scaled frame
--     (core/mover.lua records that scaled-frame coordinates are mixed here).
--
-- Nothing else about the buttons changes: same parent, so the client still
-- shows and hides them with its bar, same handlers, same art, and the
-- protected CastPetAction path they own is untouched (see the top of the file).
-- ---------------------------------------------------------------------------
local function Edge(frame, method)
  local fn = frame and frame[method]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, frame)
  if not ok then return nil end
  return tonumber(value)
end

-- Captured once, before any layout write, so restoring is exact rather than
-- reconstructed. Same shape as modules/microbar.lua's CaptureOriginal:
-- U.GetFramePoint already normalises this client's inverted GetPoint Y, and
-- feeding that tuple straight back into SetPoint is the round-trip
-- knowledge.json / frames.getpoint_relative_name_y_inverted confirms.
local function CaptureButtons()
  if captured or not native then return end

  local i
  for i = 1, BUTTON_COUNT do
    local button = U.G(BUTTON_PREFIX .. i)
    if button then
      local point, relative, relativePoint, x, y = U.GetFramePoint(button, 1)
      local okScale, scale = pcall(button.GetScale, button)
      petButtons[i] = {
        button = button,
        point = point,
        relative = relative or native,
        relativePoint = relativePoint or point,
        x = x,
        y = y,
        scale = (okScale and Number(scale)) or 1,
      }
    end
  end

  -- Only latched once a button actually resolved: a bar whose buttons the
  -- client has not created yet must be captured on a later tick, not written
  -- off with an empty table.
  if petButtons[1] then captured = true end
end

-- The client can replace a native object outside Lua's lifetime model, so one
-- name lookup per tick decides whether the capture still describes the frames
-- on screen. If the global no longer points at the button we captured, the
-- whole capture is dropped and taken again rather than written to a frame the
-- client has thrown away.
local function RefreshCapture()
  local live = U.G(BUTTON_PREFIX .. 1)
  if captured and live and petButtons[1] and petButtons[1].button ~= live then
    captured = false
    petButtons = {}
    appliedLayout = nil
    nativeGeometry = nil
  end
  CaptureButtons()
end

local function FirstButton()
  return petButtons[1] and petButtons[1].button
end

local function LastButton()
  local i
  for i = BUTTON_COUNT, 1, -1 do
    if petButtons[i] and petButtons[i].button then return petButtons[i].button end
  end
  return nil
end

local function FallbackGeometry()
  return { size = NATIVE_BUTTON_SIZE, gap = NATIVE_BUTTON_GAP, offsetX = 0, offsetY = 0 }
end

-- The client's own row: button size, the gap between two buttons, and where
-- the visible row sits inside the wider native root. Measured once, only while
-- the client still owns the geometry, and only once the buttons have a
-- resolved rect -- during load they have none, and caching a fallback then
-- would make that fallback permanent.
--
-- The offsets keep switching the layout on from shifting an untouched bar: our
-- row is centred on the anchor frame, the native row is not centred on its own
-- root, and the anchor carries the difference while the mover is unplaced.
local function NativeGeometry()
  if nativeGeometry then return nativeGeometry end

  local first = FirstButton()
  if appliedLayout or not first or not native then return FallbackGeometry() end

  local left = Edge(first, "GetLeft")
  local right = Edge(first, "GetRight")
  if not left or not right then return FallbackGeometry() end

  local geometry = FallbackGeometry()
  geometry.size = Number(Edge(first, "GetWidth")) or NATIVE_BUTTON_SIZE

  local second = petButtons[2] and petButtons[2].button
  local secondLeft = second and Edge(second, "GetLeft")
  if secondLeft then
    local gap = (secondLeft - left) - geometry.size
    if gap >= 0 and gap <= MAX_BUTTON_GAP then geometry.gap = gap end
  end

  -- Both frames are unscaled here and the button is a child of the root, so
  -- the two rects share one coordinate space and their difference is
  -- meaningful. Anything wider than the root itself is treated as a bad read.
  local last = LastButton()
  local rowRight = last and Edge(last, "GetRight")
  local nativeLeft, nativeRight = Edge(native, "GetLeft"), Edge(native, "GetRight")
  if rowRight and nativeLeft and nativeRight then
    local dx = (left + rowRight) / 2 - (nativeLeft + nativeRight) / 2
    if math.abs(dx) <= math.abs(nativeRight - nativeLeft) then geometry.offsetX = dx end
  end

  local rowTop, rowBottom = Edge(first, "GetTop"), Edge(first, "GetBottom")
  local nativeTop, nativeBottom = Edge(native, "GetTop"), Edge(native, "GetBottom")
  if rowTop and rowBottom and nativeTop and nativeBottom then
    local dy = (rowTop + rowBottom) / 2 - (nativeTop + nativeBottom) / 2
    if math.abs(dy) <= math.abs(nativeTop - nativeBottom) then geometry.offsetY = dy end
  end

  nativeGeometry = geometry
  return geometry
end

-- The layout the current configuration asks for, or nil while the client still
-- owns the geometry.
local function DesiredLayout()
  local config = cfg or Config()
  if not config.buttonLayout then return nil end
  if not FirstButton() then return nil end

  local geometry = NativeGeometry()

  local size = Number(config.buttonSize) or geometry.size
  if size < MIN_BUTTON_SIZE then size = MIN_BUTTON_SIZE end
  if size > MAX_BUTTON_SIZE then size = MAX_BUTTON_SIZE end

  local spacing = tonumber(config.buttonSpacing)
  if not spacing or spacing < 0 then spacing = geometry.gap end
  if spacing > MAX_BUTTON_GAP then spacing = MAX_BUTTON_GAP end

  return { size = size, spacing = spacing, scale = size / geometry.size }
end

-- Named on purpose: the drift check compares the button's relative frame with
-- its slot, and U.GetFramePoint can only resolve a relative handed back as a
-- string through a global name.
local function Slot(index)
  if slots[index] then return slots[index] end
  local slot = CreateFrame("Frame", "UnrealUIPetBarSlot" .. index, anchor)
  slots[index] = slot
  return slot
end

local function LayoutButtons(want)
  local i
  local width, count = 0, 0

  for i = 1, BUTTON_COUNT do
    local entry = petButtons[i]
    if entry and entry.button then
      local slot = Slot(i)
      slot:SetWidth(want.size)
      slot:SetHeight(want.size)
      slot:ClearAllPoints()
      slot:SetPoint("LEFT", anchor, "LEFT", (i - 1) * (want.size + want.spacing), 0)
      slot:Show()

      pcall(function()
        entry.button:ClearAllPoints()
        entry.button:SetPoint("CENTER", slot, "CENTER", 0, 0)
        entry.button:SetScale(want.scale)
      end)

      count = count + 1
      width = i * want.size + (i - 1) * want.spacing
    end
  end

  if count == 0 then return end

  appliedLayout = {
    size = want.size,
    spacing = want.spacing,
    scale = want.scale,
    width = width,
    height = want.size,
  }
  SetAnchorSize(width, want.size)
end

-- Has the client re-anchored or rescaled the row behind us (a pet summon, a
-- bar page change, a zone-in)? One button answers for the row: they are all
-- written in the same pass.
local function ButtonsDrifted()
  if not appliedLayout then return true end

  local button = FirstButton()
  if not button or not slots[1] then return true end

  local okCount, count = pcall(button.GetNumPoints, button)
  if okCount and tonumber(count) and tonumber(count) ~= 1 then return true end

  local point, relative, relativePoint = U.GetFramePoint(button, 1)
  if relative ~= slots[1] then return true end
  if point ~= "CENTER" or relativePoint ~= "CENTER" then return true end

  local okScale, scale = pcall(button.GetScale, button)
  if okScale and Number(scale) and math.abs(scale - appliedLayout.scale) > 0.01 then
    return true
  end
  return false
end

-- Hands every button back to the anchor and scale it had before unrealUI
-- touched it. Order does not matter: each entry restores against its own
-- captured relative frame, not against the previous button.
local function RestoreButtons()
  local i
  for i = 1, BUTTON_COUNT do
    local entry = petButtons[i]
    if entry and entry.button then
      pcall(function()
        entry.button:ClearAllPoints()
        if entry.point then
          entry.button:SetPoint(entry.point, entry.relative or native,
                                entry.relativePoint or entry.point,
                                entry.x or 0, entry.y or 0)
        end
        entry.button:SetScale(entry.scale or 1)
      end)
    end
    if slots[i] then slots[i]:Hide() end
  end
  appliedLayout = nil
end

local function AnchorDrifted(frame, position)
  local point, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if type(point) ~= "string" then return true end
  if relative and relative ~= UIParent then return true end
  if point ~= position.point then return true end
  if relativePoint ~= (position.relativePoint or position.point) then return true end
  if math.abs(x - (tonumber(position.x) or 0)) > DRIFT_EPSILON then return true end
  if math.abs(y - (tonumber(position.y) or 0)) > DRIFT_EPSILON then return true end
  return false
end

-- Is the native bar still sitting on our anchor, or has the client re-anchored
-- it (a pet summon, a bar page change, a zone-in)?
-- frames.extra_anchor_point_survives_addon_setpoint: the native castbar kept
-- point 1 on its mover while another point displaced it. Use the same guarded
-- count check here; point 1 alone cannot detect that case.
local function NativeDrifted()
  local okCount, count = pcall(native.GetNumPoints, native)
  if okCount and tonumber(count) and tonumber(count) ~= 1 then return true end

  local point, relative, relativePoint, x, y = U.GetFramePoint(native, 1)
  if type(point) ~= "string" then return true end
  if relative ~= anchor then return true end
  if point ~= "CENTER" or relativePoint ~= "CENTER" then return true end
  if math.abs(x) > DRIFT_EPSILON or math.abs(y) > DRIFT_EPSILON then return true end
  return false
end

-- Size-agnostic on purpose: centre-on-centre needs neither frame to know how
-- wide the other is, which matters because the native bar's size is exactly
-- what can differ from the visible button footprint on this client.
local function DriveNative()
  local ok = pcall(function()
    native:ClearAllPoints()
    native:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  end)
  -- This reports whether the placement call succeeded, not visual proof that
  -- the client's buttons followed it. A refused write must not claim success.
  driving = ok
  if not ok then
    driveFailures = driveFailures + 1
    if driveFailures == 1 then
      U.Debug("petbar: re-anchoring " .. NATIVE_NAME .. " was refused")
    end
  end
end

-- While the mover is unplaced the handle shadows the native bar. With our own
-- row layout active it shadows the *row* instead, by carrying the measured
-- offset between the native row and the root that holds it -- otherwise
-- turning the layout on would slide an untouched bar sideways.
local function FollowNative()
  local x, y = 0, 0
  if appliedLayout then
    local geometry = NativeGeometry()
    x, y = geometry.offsetX, geometry.offsetY
  end

  pcall(function()
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", native, "CENTER", x, y)
  end)
end

-- ---------------------------------------------------------------------------
-- The native bar's parent
--
-- Why the bar is moved off it
--
--   modules/actionbar.lua suppresses the whole stock bar hierarchy, and
--   MainMenuBar is the first name in its NATIVE_ROOTS list: the root is
--   hidden, alpha'd, mouse-disabled and (at suppression level 3+) has its Show
--   replaced with a no-op. Vanilla FrameXML parents PetActionBarFrame into
--   that hierarchy, and a hidden parent takes every descendant down with it.
--   The result is exactly what was reported: the mover handle is there and
--   grabbable, the client still shows and updates the bar, PetHasActionBar is
--   true -- and nothing is drawn, because an ancestor is hidden.
--
--   Re-parenting the bar to UIParent is the fix, and it is not a new
--   mechanism: modules/microbar.lua already does the same thing to the stock
--   micro buttons, the other family living inside that suppressed hierarchy,
--   and that bar draws. Nothing else about the bar changes -- it is still the
--   client's own frame, still shown and hidden by the client's own code, and
--   still the only thing on this client that can cast a pet spell (see the
--   CastPetAction note at the top).
--
-- What is checked rather than assumed
--
--   The interface capture establishes the bar's children, not its own parent.
--   The parent is therefore *read* and the move only happens when it is not
--   already UIParent.
--
--   Scale multiplies down the parent chain here
--   (frames.json / frames.parent_effective_scale.v1, SUPPORTED /
--   BEHAVIOR_VERIFIED), so a parent carrying a scale of its own would resize
--   the bar the moment it moved. The effective scale is measured before the
--   move and restored after it.
--
--   SetPoint anchors survive SetParent, but a point stored against the old
--   parent -- including the common "no relative frame, so it means my parent"
--   form -- does not mean the same thing afterwards. The anchor captured above
--   is replayed once the move is done, so the bar lands where it was.
-- ---------------------------------------------------------------------------
local function EffectiveScale(frame)
  if not frame then return nil end
  local ok, scale = pcall(frame.GetEffectiveScale, frame)
  if not ok then return nil end
  return Number(scale)
end

-- Cheap enough for the shared tick: one pcall'd GetParent against a frame the
-- client re-parents essentially never. It is re-checked rather than done once
-- because a native bar re-created or re-homed by the client would otherwise
-- silently vanish again until the next reload.
local function EnsureParent()
  if not native then return end

  local ok, parent = pcall(native.GetParent, native)
  if not ok then return end
  if parent == UIParent then return end

  if nativeParent == nil then nativeParent = parent or false end

  local before = EffectiveScale(native)

  local moved = pcall(native.SetParent, native, UIParent)
  if not moved then
    U.Debug("petbar: could not re-parent " .. NATIVE_NAME)
    return
  end
  reparented = true

  -- before and after are both *effective* scales; the value handed to SetScale
  -- is the factor that reproduces the old effective scale under the new
  -- parent.
  local host = EffectiveScale(UIParent)
  local after = EffectiveScale(native)
  if before and host and after and math.abs(after - before) > 0.01 then
    pcall(native.SetScale, native, before / host)
  end

  -- Put the bar back on the anchor it had before the move: ours if the player
  -- has placed it, the client's own otherwise.
  if driving then DriveNative() else RestoreNativeAnchor() end

  U.Debug("petbar: " .. NATIVE_NAME .. " re-parented to UIParent")
end

local function Apply()
  if U.PerfDisabled and U.PerfDisabled("petbar") then return end
  if not anchor or not native then return end

  -- First: a bar hidden by an ancestor cannot be fixed by anything below.
  EnsureParent()

  -- Native button capture belongs to the opt-in layout, not the default
  -- mover. Zoxi's default profile must not retain/read ten native children
  -- for a feature it never enabled. Keep capture ahead of layout writes,
  -- including the restore of a layout that was enabled earlier this session.
  -- See petbar.disabled_layout_captures_native_children.
  if (cfg and cfg.buttonLayout) or appliedLayout then RefreshCapture() end

  local want = DesiredLayout()
  if want then
    if not appliedLayout or appliedLayout.size ~= want.size
       or appliedLayout.spacing ~= want.spacing or ButtonsDrifted() then
      LayoutButtons(want)
    end
  elseif appliedLayout then
    RestoreButtons()
  end

  -- The handle takes the row's footprint while unrealUI owns the layout, and
  -- the native root's while the client does.
  if not appliedLayout then MirrorNativeSize() end
  HideNativeBorder()

  local position = StoredPosition()
  local unlocked = U.IsUnlocked()

  if not position then
    -- Never placed, or /uui reset: give the bar back to the client once, then
    -- keep the handle shadowing it. Not while the handle is being dragged --
    -- re-anchoring it to the native bar mid-drag would snap it out of the
    -- player's hand.
    if driving then RestoreNativeAnchor() end
    if not unlocked then FollowNative() end
    return
  end

  -- The mover owns the anchor's position between StartMoving and
  -- StopMovingOrSizing, so it is only re-applied while locked. The native bar
  -- is anchored *to* the anchor rather than positioned alongside it, so it
  -- tracks the handle live during the drag with no second write.
  if not unlocked and AnchorDrifted(anchor, position) then
    U.ApplyFramePoint(anchor, position)
  end

  if NativeDrifted() then DriveNative() end
end

-- Whether the client is drawing the bar at all. Resolved by name on every read
-- rather than through the retained root, so a bar the client replaced is not
-- reported from a dead object.
local function NativeBarShown()
  local current = U.G(NATIVE_NAME)
  if not current then return false end
  local ok, shown = pcall(current.IsShown, current)
  if not ok then return false end
  return (shown and shown ~= 0) and true or false
end

-- Geometry for the empty-anchor sample: what the row is laid out at while
-- unrealUI owns it, and the client's own measured 30x30 / 7 row otherwise.
--
-- Deliberately not NativeGeometry(): that measurement retains and reads the
-- ten native buttons, and petbar.disabled_layout_captures_native_children is
-- explicit that a profile which never enabled the layout must not pay for
-- them. A sample is not worth crossing that line for.
local function SampleButtonSize()
  return (appliedLayout and appliedLayout.size) or NATIVE_BUTTON_SIZE
end

local function SampleButtonGap()
  return (appliedLayout and appliedLayout.spacing) or NATIVE_BUTTON_GAP
end

-- The native bar is not parented to the mover anchor, so the shared mover
-- cannot hide its content by hiding the anchor alone. The advanced visibility
-- gate persists after edit mode closes; nil restores the client-owned pet state
-- when the row is checked again.
local function SetEditShown(shown)
  if not native then return end
  if shown == false then
    local ok, wasShown = pcall(native.IsShown, native)
    if ok and wasShown and wasShown ~= 0 then editNativeWasShown = true end
    editNativeHidden = true
    if not ok or (wasShown and wasShown ~= 0) then pcall(native.Hide, native) end
    return
  end

  if not editNativeHidden then return end
  editNativeHidden = false
  local hasPetBar = editNativeWasShown
  local petHasActionBar = U.G("PetHasActionBar")
  if type(petHasActionBar) == "function" then
    local ok, value = pcall(petHasActionBar)
    if ok then hasPetBar = value and value ~= 0 and true or false end
  end
  editNativeWasShown = false
  if hasPetBar then pcall(native.Show, native) else pcall(native.Hide, native) end
end

-- ---------------------------------------------------------------------------
-- Geometry sub-commands
--
-- Dispatched from U.PetBarCommand at the top of the file through the forward
-- declaration there. These apply live: none of them changes the pet bar mode,
-- so unlike native/custom there is no reload involved.
--
-- Setting one of the two values leaves the other on the client's own
-- measurement rather than inventing a number for it.
-- ---------------------------------------------------------------------------
ButtonCommand = function(verb, argument)
  if not U.db then U.Print(U.L("PETBAR_UNAVAILABLE")); return end

  -- Native mode only: these place the client's own buttons. The opt-in custom
  -- bar builds its own from cfg.size / cfg.spacing, and its status line has
  -- already been printed by the caller.
  if activeMode ~= "native" or not native then
    if verb ~= "status" then U.Print(U.L("PETBAR_UNAVAILABLE")) end
    return
  end

  local config = Config()
  local geometry = NativeGeometry()

  if verb == "status" then
    if appliedLayout then
      U.Print(U.L("PETBAR_BUTTONS_APPLIED", appliedLayout.size, appliedLayout.spacing))
    else
      U.Print(U.L("PETBAR_BUTTONS_NATIVE", U.Round(geometry.size), U.Round(geometry.gap)))
    end
    return
  end

  if verb == "reset" then
    config.buttonLayout = false
    config.buttonSize = 0
    config.buttonSpacing = -1
    Apply()
    U.Print(U.L("PETBAR_BUTTONS_RESTORED"))
    return
  end

  local value = tonumber(argument)
  if value then value = U.Round(value) end

  if verb == "size" then
    if not value or value < MIN_BUTTON_SIZE or value > MAX_BUTTON_SIZE then
      U.Print(U.L("PETBAR_BUTTONS_RANGE", MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, 0, MAX_BUTTON_GAP))
      return
    end
    config.buttonSize = value
  else
    if not value or value < 0 or value > MAX_BUTTON_GAP then
      U.Print(U.L("PETBAR_BUTTONS_RANGE", MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, 0, MAX_BUTTON_GAP))
      return
    end
    config.buttonSpacing = value
  end

  if not Number(config.buttonSize) then config.buttonSize = U.Round(geometry.size) end
  if not tonumber(config.buttonSpacing) or config.buttonSpacing < 0 then
    config.buttonSpacing = U.Round(geometry.gap)
  end

  config.buttonLayout = true
  Apply()

  if appliedLayout then
    U.Print(U.L("PETBAR_BUTTONS_APPLIED", appliedLayout.size, appliedLayout.spacing))
  else
    -- No button resolved, so nothing was written: say so rather than report a
    -- size the bar does not have.
    U.Print(U.L("PETBAR_UNAVAILABLE"))
  end
end

-- ---------------------------------------------------------------------------
-- Settings-window API
--
-- The Pet Bar page in the ActionBars group (modules/actionbarconfig.lua) drives
-- exactly the same two values as /uui petbar size|spacing, in the same shape as
-- U.GetActionBarSetting / U.SetActionBarSetting / U.ActionBarLimits so the page
-- can be built beside the real bar pages without a second convention.
--
-- Native mode only. The opt-in custom bar builds its own buttons from
-- cfg.size / cfg.spacing and is not placed by any of this.
-- ---------------------------------------------------------------------------
function U.PetBarButtonsAvailable()
  return (activeMode == "native" and native and U.db) and true or false
end

function U.PetBarButtonLimits(name)
  if name == "Size" then return MIN_BUTTON_SIZE, MAX_BUTTON_SIZE, 1 end
  if name == "Spacing" then return 0, MAX_BUTTON_GAP, 1 end
  return nil
end

-- "Custom" is the same flag the chat commands set: false means the sliders are
-- showing the client's own measured row rather than a stored choice.
function U.GetPetBarSetting(name)
  if not U.PetBarButtonsAvailable() then return nil end
  local config = Config()

  if name == "Custom" then return config.buttonLayout and true or false end

  local geometry = NativeGeometry()
  if name == "Size" then
    if appliedLayout then return appliedLayout.size end
    if config.buttonLayout and Number(config.buttonSize) then
      return U.Round(config.buttonSize)
    end
    return U.Round(geometry.size)
  end
  if name == "Spacing" then
    if appliedLayout then return appliedLayout.spacing end
    local spacing = tonumber(config.buttonSpacing)
    if config.buttonLayout and spacing and spacing >= 0 then return U.Round(spacing) end
    return U.Round(geometry.gap)
  end
  return nil
end

-- Writes one value and re-applies immediately, returning what was stored.
-- Touching either slider turns the layout on, and the value that was not
-- touched is seeded from the client's own row rather than invented -- the
-- same rule ButtonCommand follows.
function U.SetPetBarSetting(name, value)
  if not U.PetBarButtonsAvailable() then return nil end
  local min, max = U.PetBarButtonLimits(name)
  if not min then return nil end

  value = tonumber(value)
  if not value then return nil end
  value = U.Round(value)
  if value < min then value = min end
  if value > max then value = max end

  local config = Config()
  local geometry = NativeGeometry()

  if name == "Size" then
    config.buttonSize = value
  else
    config.buttonSpacing = value
  end

  if not Number(config.buttonSize) then config.buttonSize = U.Round(geometry.size) end
  if not tonumber(config.buttonSpacing) or config.buttonSpacing < 0 then
    config.buttonSpacing = U.Round(geometry.gap)
  end

  config.buttonLayout = true
  Apply()
  return U.GetPetBarSetting(name)
end

-- Hands the row back to the client, exactly as /uui petbar reset does.
function U.ResetPetBarButtons()
  if not U.PetBarButtonsAvailable() then return nil end
  local config = Config()
  config.buttonLayout = false
  config.buttonSize = 0
  config.buttonSpacing = -1
  Apply()
  return true
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
local function CreateAnchor()
  anchor = CreateFrame("Frame", "UnrealUIPetBarAnchor", UIParent)
  anchor:SetWidth(FALLBACK_WIDTH)
  anchor:SetHeight(FALLBACK_HEIGHT)

  -- Carries a mover handle and nothing else: no backdrop, no mouse, no strata
  -- of its own. It must never sit in front of the bar it is placing.
  MirrorNativeSize()
  FollowNative()
  anchor:Show()
end

local function RegisterEvents()
  -- Accelerators only. None of these has a runtime record on this client, so a
  -- pet summon that fires nothing is still corrected by the shared updater
  -- below within its interval.
  local refresh = function() Apply() end
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("UNIT_PET", refresh)
  U.RegisterEvent("PET_BAR_UPDATE", refresh)
end

function PB:OnInit()
  Config()
end

function PB:OnEnable()
  Config()
  if cfg.mode == "custom" then
    if type(U.EnableCustomPetBar) == "function" then
      U.EnableCustomPetBar(cfg)
      activeMode = "custom"
      U.Print(U.L("PETBAR_CUSTOM_WARNING"))
      return
    end
    -- Missing helper: leave the native bar available rather than suppress it.
    U.Print(U.L("PETBAR_UNAVAILABLE"))
  end

  native = U.G(NATIVE_NAME)
  if not native then
    U.Debug("petbar: " .. NATIVE_NAME .. " not found; no pet bar mover")
    return
  end

  -- Before RegisterMover, which is what may apply a stored position, and
  -- before EnsureParent, which replays this capture after the move.
  nativeAnchor = CaptureNativeAnchor()

  -- Before CreateAnchor: the anchor frame mirrors the native bar's size, and
  -- the move can change it if the old parent carried a scale.
  EnsureParent()

  CreateAnchor()

  -- No `default`: the client's own anchor is not UIParent-relative and cannot
  -- be written as one. U.OnPositionReset replays it instead, which is the case
  -- core/mover.lua documents that hook for.
  U.RegisterMover("petbar", anchor, {
    label = U.L("MOVER_LABEL_PET_BAR"),
    setEditShown = SetEditShown,
  })

  -- Without a pet the client hides the whole bar, so the anchor is an empty
  -- 509x43 rectangle whose visible row is narrower than it is. Ten squares in
  -- the row's own geometry show where the buttons will actually land.
  if type(U.RegisterMoverSample) == "function" then
    U.RegisterMoverSample("petbar", {
      isEmpty = function() return not NativeBarShown() end,
      cells = {
        count = BUTTON_COUNT,
        perRow = BUTTON_COUNT,
        size = function() return SampleButtonSize() end,
        spacing = function() return SampleButtonGap() end,
      },
    })
  end
  U.OnPositionReset(function() return RestoreNativeAnchor() end)

  Apply()
  RegisterEvents()

  -- One anchor read per tick against a bar that changes position rarely. The
  -- old module swept ten buttons twice a second; this refresh places the root
  -- and suppresses only its two decorative textures.
  U.RegisterUpdate("petbar.anchor", 1.0, Apply)
end

-- ---------------------------------------------------------------------------
-- Report
--
-- These are here to answer one question from chat without a probe: is the bar
-- invisible because the client is not showing it, or because something above
-- it is not? "shown true, visible false" is the hidden-ancestor case this
-- module's parent section exists for; "shown false" means the client itself
-- has no bar to draw.
-- ---------------------------------------------------------------------------
local function ParentName(frame)
  if frame == nil or frame == false then return nil end
  local ok, name = pcall(frame.GetName, frame)
  if ok and type(name) == "string" then return name end
  return "unnamed"
end

local function CurrentParent()
  if not native then return nil end
  local ok, parent = pcall(native.GetParent, native)
  if not ok then return nil end
  return parent
end

local function Readback(frame, method)
  if not frame then return nil end
  local found, fn = pcall(function() return frame[method] end)
  if not found or type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, frame)
  if not ok then return nil end
  return value and true or false
end

-- Reported by /uui check.
function U.PetBarReport()
  local okCount, count = false, nil
  if native then okCount, count = pcall(native.GetNumPoints, native) end
  return {
    mode = activeMode,
    selectedMode = cfg and cfg.mode or "native",
    native = native and true or false,
    anchor = anchor and true or false,
    hasPetBar = Call("PetHasActionBar") and true or false,
    placed = StoredPosition() and true or false,
    driving = driving,
    driveFailures = driveFailures,
    buttonLayout = appliedLayout and true or false,
    buttonSize = appliedLayout and appliedLayout.size or nil,
    buttonSpacing = appliedLayout and appliedLayout.spacing or nil,
    nativePoints = okCount and tonumber(count) or nil,
    nativeAnchorCaptured = nativeAnchor and true or false,
    reparented = reparented,
    originalParent = ParentName(nativeParent),
    parent = ParentName(CurrentParent()),
    shown = Readback(native, "IsShown"),
    visible = Readback(native, "IsVisible"),
    -- One button, for the case the bar frame draws but its buttons do not.
    buttonVisible = Readback(U.G("PetActionButton1"), "IsVisible"),
  }
end
