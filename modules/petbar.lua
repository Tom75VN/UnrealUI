-- unrealUI :: modules/petbar.lua
--
-- The native pet action bar, left exactly as the client draws it, with one
-- unrealUI addition: a mover handle so it can be placed like the rest of the
-- interface.
--
-- Why there is no unrealUI pet bar any more
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
--   That is a client capability limit, not a bug with a workaround, so the
--   feature is gone rather than emulated. Per .claude/rules/unreal-ui.md: a
--   pfUI behaviour with no reliable Unreal equivalent is omitted, not faked.
--
-- What is left
--
--   The native bar is never hidden, reskinned or click-handled. An unrealUI-
--   owned anchor frame carries the mover handle, and the native bar is pointed
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
--     client's pet bar reports no dependable size for that to cover -- there
--     is no runtime record for PetActionBarFrame at all (frames.json and
--     interface.json contain no pet capture). An owned frame has a size we
--     set, so the handle is always there to grab.
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

local function MirrorNativeSize()
  if not anchor or not native then return end

  local okW, w = pcall(native.GetWidth, native)
  local okH, h = pcall(native.GetHeight, native)
  local width = (okW and Number(w)) or FALLBACK_WIDTH
  local height = (okH and Number(h)) or FALLBACK_HEIGHT

  -- Only written when it actually changes: this runs on the shared tick, and
  -- the handle is SetAllPoints to this frame, so a size write is a handle
  -- relayout every second for nothing.
  if anchor.uuiWidth ~= width then
    anchor:SetWidth(width)
    anchor.uuiWidth = width
  end
  if anchor.uuiHeight ~= height then
    anchor:SetHeight(height)
    anchor.uuiHeight = height
  end
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
local function NativeDrifted()
  local point, relative, relativePoint, x, y = U.GetFramePoint(native, 1)
  if type(point) ~= "string" then return true end
  if relative ~= anchor then return true end
  if point ~= "CENTER" or relativePoint ~= "CENTER" then return true end
  if math.abs(x) > DRIFT_EPSILON or math.abs(y) > DRIFT_EPSILON then return true end
  return false
end

-- Size-agnostic on purpose: centre-on-centre needs neither frame to know how
-- wide the other is, which matters because the native bar's size is exactly
-- what this client has no record for.
local function DriveNative()
  pcall(function()
    native:ClearAllPoints()
    native:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  end)
  driving = true
end

local function FollowNative()
  pcall(function()
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", native, "CENTER", 0, 0)
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
--   This client has no runtime record of the pet bar at all (frames.json and
--   interface.json hold no pet capture), so the parent is *read* and the move
--   only happens when it is not already UIParent. A client that parents its
--   pet bar somewhere safe is left completely alone.
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
  MirrorNativeSize()

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

function PB:OnEnable()
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
  U.RegisterMover("petbar", anchor, { label = U.L("MOVER_LABEL_PET_BAR") })
  U.OnPositionReset(function() return RestoreNativeAnchor() end)

  Apply()
  RegisterEvents()

  -- One anchor read per tick against a bar that changes position rarely. The
  -- old module swept ten buttons twice a second; this is the whole cost of the
  -- feature now.
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
  return {
    native = native and true or false,
    anchor = anchor and true or false,
    hasPetBar = Call("PetHasActionBar") and true or false,
    placed = StoredPosition() and true or false,
    driving = driving,
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
