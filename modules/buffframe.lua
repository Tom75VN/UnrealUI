-- unrealUI :: modules/buffframe.lua
--
-- The client's own buff / debuff display beside the minimap, left exactly as
-- the client draws it, with one unrealUI addition: a mover handle so it can be
-- placed like the rest of the interface.
--
-- This is modules/petbar.lua's shape, for the same reason. The native aura
-- display is never hidden, reskinned, re-parented or click-handled; an
-- unrealUI-owned anchor frame carries the handle, and the native frame is only
-- pointed at it once the player has actually dropped that handle. Until then
-- the anchor follows the native frame and nothing is written at all, so an
-- untouched interface keeps the client's own buff position.
--
-- Note this is the *native* row near the minimap, not modules/auras.lua. That
-- module draws unrealUI's own aura icons around the unit frames and does not
-- touch these frames; both can be on screen at once, which is the stock
-- behaviour and is left alone here.
--
-- Compatibility notes that shaped this file:
--
--   * query_compat.py has no record for BuffFrame or TemporaryEnchantFrame at
--     all -- not in frames.json, not in interface.json, and this client ships
--     no FrameXML on disk to read. The one piece of evidence that the two
--     globals exist here is UnrealPfUI's modules/buff.lua, which hides both by
--     name on this same client (WORKING_SOURCE, per .claude/rules/unreal-pfui.md
--     -- not runtime verification). Everything else about them, size, anchor,
--     growth direction, which of the two owns the other, is discovered at
--     runtime below rather than assumed from Vanilla's FrameXML, because this
--     client is a reimplementation and not required to match it.
--   * Nothing here needs the frames to be Vanilla-shaped. The root frame is
--     re-anchored through its *own* captured point name, so whichever corner
--     the client grows the icons from is the corner that lands on the handle.
--   * The handle lives on an unrealUI frame rather than on BuffFrame directly
--     (same reasoning as petbar): U.RegisterMover's handle is SetAllPoints to
--     the frame it is registered on, and a container the client sizes to zero
--     would leave nothing to grab. An owned frame has a size we set.
--   * The native anchor is not UIParent-relative and cannot be expressed as a
--     mover `default`, so it is captured at load and replayed through
--     U.OnPositionReset, which is the case core/mover.lua documents that hook
--     for.
--   * knowledge.json / frames.getpoint_relative_name_y_inverted: anchors are
--     read through U.GetFramePoint, which returns the relative frame resolved
--     and Y in the sign SetPoint wants, so a capture goes back through SetPoint
--     unchanged and two captures can be subtracted directly.
--   * PLAYER_AURAS_CHANGED has no compact record on this client, so it is an
--     accelerator only. The slow shared updater is the guarantee.
--   * The display can also be switched off entirely, which is the one thing
--     that does touch the native frames beyond their anchor. It is a plain
--     Hide() on both containers, re-asserted from the same updater, and
--     deliberately NOT UnrealPfUI's Hide() + UnregisterAllEvents() pair:
--     unregistering the client's own events cannot be undone from an addon,
--     so a checkbox built on it could only be turned back on with a reload.
--     If Hide() alone turns out not to remove the icons on this client --
--     possible, since nothing has measured whether the buff buttons are
--     really children of these two containers here -- the fallback is that
--     pfUI pair plus a stated reload-to-re-enable, not more guessing.

local U = UnrealUI

local BF = U.RegisterModule("buffframe")

-- ---------------------------------------------------------------------------
-- Settings
--
-- Visibility lives here rather than in modules/auras.lua's config table
-- because these are this module's frames: auras.lua's page only reads and
-- writes it through the two accessors below.
-- ---------------------------------------------------------------------------
local CONFIG = "buffframe"

local defaults = {
  nativeShown = true,
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

-- The two native containers, in the order they are preferred as the root.
local BUFF_NAME = "BuffFrame"
local ENCHANT_NAME = "TemporaryEnchantFrame"

-- Used only until the native frame reports its own size, and as the handle's
-- footprint if it never does. Roughly the area two rows of stock buff icons
-- plus the debuff row occupy; it is a grab target, not a claim about layout.
local FALLBACK_WIDTH  = 300
local FALLBACK_HEIGHT = 100

-- Anchor offsets below this are treated as "unchanged" rather than drift.
local DRIFT_EPSILON = 0.5

local anchor = nil
local root = nil          -- the native frame the handle actually drives
local rootName = nil
local rootPoint = "TOPRIGHT"
local second = nil        -- the other native frame, when it is independent
local secondName = nil
local secondPoint = nil
local secondOffsetX, secondOffsetY = 0, 0
local captured = {}       -- frame -> its own anchor as the client had it
local managed = {}        -- both native frames, in the order they were found
local skipped = nil       -- why the second frame is not driven, for the report
local driving = false

local function Number(value)
  value = tonumber(value)
  if not value or value <= 0 then return nil end
  return value
end

-- ---------------------------------------------------------------------------
-- Visibility
--
-- Re-asserted on every Apply rather than written once: the client owns these
-- frames and may re-show them when an aura lands. Reading IsShown first keeps
-- a steady state down to one call per frame per tick with no writes at all.
-- ---------------------------------------------------------------------------
function U.GetNativeAuraFrameShown()
  local value = Config().nativeShown
  if value == nil then return defaults.nativeShown end
  return value and true or false
end

local function IsVisible(frame)
  local ok, shown = pcall(frame.IsShown, frame)
  return (ok and shown and shown ~= 0) and true or false
end

local function EnforceVisibility()
  local shown = U.GetNativeAuraFrameShown()
  local i
  for i = 1, table.getn(managed) do
    local frame = managed[i]
    if IsVisible(frame) ~= shown then
      if shown then pcall(frame.Show, frame) else pcall(frame.Hide, frame) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- The client's own anchors
--
-- Captured once, before the mover is registered and therefore before anything
-- of ours can have moved either frame. Replayed on /uui reset.
-- ---------------------------------------------------------------------------
local function CaptureNativeAnchor(frame, name)
  if not frame then return nil end

  local point, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if type(point) ~= "string" then
    U.Debug("buffframe: no readable native anchor on " .. name)
    return nil
  end

  if not relative then
    local ok, parent = pcall(frame.GetParent, frame)
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

local function RestoreNativeAnchor(frame)
  local saved = frame and captured[frame]
  if not saved then return false end

  return pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, saved.relative, saved.relativePoint,
                   saved.x, saved.y)
  end)
end

local function RestoreNativeAnchors()
  local restored = false
  if RestoreNativeAnchor(root) then restored = true end
  if second and RestoreNativeAnchor(second) then restored = true end

  if restored then
    driving = false
    U.Debug("buffframe: native buff anchors restored")
  end
  return restored
end

-- ---------------------------------------------------------------------------
-- Which frame the handle drives
--
-- Decided from the captured anchors, not from a Vanilla layout assumption:
--
--   * if one of the two is anchored to the other, the one being anchored *to*
--     is the root and the other is left completely alone -- it already follows.
--   * if both hang off the same relative frame from the same point, the second
--     is driven from the anchor at the difference between the two captures, so
--     the gap the client put between them survives the move.
--   * anything else: only the buff container is driven, the other is left where
--     the client had it, and /uui check says so rather than the addon guessing.
-- ---------------------------------------------------------------------------
local function ChooseRoot(buffFrame, enchantFrame)
  local buffAnchor = captured[buffFrame]
  local enchantAnchor = captured[enchantFrame]

  if buffFrame and enchantFrame then
    if buffAnchor and buffAnchor.relative == enchantFrame then
      root, rootName = enchantFrame, ENCHANT_NAME
      skipped = BUFF_NAME .. " already follows it"
      return
    end
    if enchantAnchor and enchantAnchor.relative == buffFrame then
      root, rootName = buffFrame, BUFF_NAME
      skipped = ENCHANT_NAME .. " already follows it"
      return
    end
  end

  root = buffFrame or enchantFrame
  rootName = buffFrame and BUFF_NAME or ENCHANT_NAME

  local other = nil
  if root == buffFrame then other = enchantFrame else other = buffFrame end
  if not other then return end

  local rootAnchor, otherAnchor = captured[root], captured[other]
  if not rootAnchor or not otherAnchor then
    skipped = "no readable native anchor"
    return
  end
  if rootAnchor.relative ~= otherAnchor.relative then
    skipped = "anchored to a different frame"
    return
  end
  if rootAnchor.relativePoint ~= otherAnchor.relativePoint then
    skipped = "anchored from a different point"
    return
  end

  second = other
  if other == buffFrame then secondName = BUFF_NAME else secondName = ENCHANT_NAME end
  secondPoint = otherAnchor.point
  -- Both values already come back in SetPoint's sign, so the difference is
  -- directly usable as an offset from the root's point.
  secondOffsetX = otherAnchor.x - rootAnchor.x
  secondOffsetY = otherAnchor.y - rootAnchor.y
end

-- ---------------------------------------------------------------------------
-- Placement
--
-- Two modes, decided only by whether the player has ever dropped this mover.
-- They are never active at once, so the frames cannot chase each other.
-- ---------------------------------------------------------------------------
local function StoredPosition()
  local ok, position = pcall(U.GetPosition, "buffs")
  if not ok or type(position) ~= "table" then return nil end
  if type(position.point) ~= "string" then return nil end
  return position
end

local function MirrorNativeSize()
  if not anchor or not root then return end

  local okW, w = pcall(root.GetWidth, root)
  local okH, h = pcall(root.GetHeight, root)
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

-- Is the native frame still sitting on our anchor, or has the client
-- re-anchored it (an aura gained or lost, a zone-in)?
local function NativeDrifted(frame, point, offsetX, offsetY)
  local at, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if type(at) ~= "string" then return true end
  if relative ~= anchor then return true end
  if at ~= point or relativePoint ~= rootPoint then return true end
  if math.abs(x - offsetX) > DRIFT_EPSILON then return true end
  if math.abs(y - offsetY) > DRIFT_EPSILON then return true end
  return false
end

-- Corner-on-corner rather than centre-on-centre: the icons grow away from the
-- frame's own anchor point, so mapping that point onto the same point of the
-- handle keeps the row growing in the direction the client chose, whatever the
-- handle's footprint happens to be.
local function DriveNative()
  pcall(function()
    root:ClearAllPoints()
    root:SetPoint(rootPoint, anchor, rootPoint, 0, 0)
  end)

  if second then
    pcall(function()
      second:ClearAllPoints()
      second:SetPoint(secondPoint, anchor, rootPoint,
                      secondOffsetX, secondOffsetY)
    end)
  end

  driving = true
end

local function FollowNative()
  pcall(function()
    anchor:ClearAllPoints()
    anchor:SetPoint(rootPoint, root, rootPoint, 0, 0)
  end)
end

local function Apply()
  EnforceVisibility()
  if not anchor or not root then return end
  -- Nothing to place while it is off, and no anchor writes to fight over the
  -- frames if the client moves them in the meantime; the next Apply after it
  -- is switched back on re-drives from the stored position.
  if not U.GetNativeAuraFrameShown() then return end

  MirrorNativeSize()

  local position = StoredPosition()
  local unlocked = U.IsUnlocked()

  if not position then
    -- Never placed, or /uui reset: give the display back to the client once,
    -- then keep the handle shadowing it. Not while the handle is being dragged
    -- -- re-anchoring it to the native frame mid-drag would snap it out of the
    -- player's hand.
    if driving then RestoreNativeAnchors() end
    -- Only follow once the native frame is genuinely off our anchor again.
    -- RestoreNativeAnchors clears `driving` on success and leaves it set when
    -- there was no readable anchor to put back; following in that state would
    -- point the two frames at each other.
    if not unlocked and not driving then FollowNative() end
    return
  end

  -- The mover owns the anchor's position between StartMoving and
  -- StopMovingOrSizing, so it is only re-applied while locked. The native
  -- frames are anchored *to* the anchor rather than positioned alongside it, so
  -- they track the handle live during the drag with no second write.
  if not unlocked and AnchorDrifted(anchor, position) then
    U.ApplyFramePoint(anchor, position)
  end

  if NativeDrifted(root, rootPoint, 0, 0) then
    DriveNative()
  elseif second and NativeDrifted(second, secondPoint,
                                  secondOffsetX, secondOffsetY) then
    DriveNative()
  end
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
local function CreateAnchor()
  anchor = CreateFrame("Frame", "UnrealUIBuffAnchor", UIParent)
  anchor:SetWidth(FALLBACK_WIDTH)
  anchor:SetHeight(FALLBACK_HEIGHT)

  -- Carries a mover handle and nothing else: no backdrop, no mouse, no strata
  -- of its own. It must never sit in front of the icons it is placing.
  MirrorNativeSize()
  FollowNative()
  anchor:Show()
end

local function RegisterEvents()
  -- Accelerators only; neither has a runtime record on this client, so an aura
  -- change that fires nothing is still corrected by the shared updater below.
  local refresh = function() Apply() end
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", refresh)
  -- Unlike the two above, UNIT_AURA is observed firing on this client
  -- (events.json, and modules/auras.lua runs on it). It is registered here so
  -- a hidden display cannot reappear for a whole updater tick when an aura
  -- lands; it is still only an accelerator for the tick below.
  U.RegisterEvent("UNIT_AURA", function(event, unit)
    if unit == nil or unit == "player" then Apply() end
  end)
end

function BF:OnEnable()
  local buffFrame = U.G(BUFF_NAME)
  local enchantFrame = U.G(ENCHANT_NAME)

  if not buffFrame and not enchantFrame then
    U.Debug("buffframe: no " .. BUFF_NAME .. " or " .. ENCHANT_NAME ..
            " on this client; no buff mover")
    return
  end

  -- Before RegisterMover, which is what may apply a stored position.
  if buffFrame then
    captured[buffFrame] = CaptureNativeAnchor(buffFrame, BUFF_NAME)
    table.insert(managed, buffFrame)
  end
  if enchantFrame then
    captured[enchantFrame] = CaptureNativeAnchor(enchantFrame, ENCHANT_NAME)
    table.insert(managed, enchantFrame)
  end

  ChooseRoot(buffFrame, enchantFrame)
  if not root then return end

  local rootAnchor = captured[root]
  if rootAnchor then rootPoint = rootAnchor.point end

  CreateAnchor()

  -- No `default`: the client's own anchor is not UIParent-relative and cannot
  -- be written as one. U.OnPositionReset replays it instead.
  -- A display that is switched off must not offer a handle to drag.
  U.RegisterMover("buffs", anchor, {
    label = U.L("MOVER_LABEL_BUFFS"),
    visible = function() return U.GetNativeAuraFrameShown() end,
  })
  U.OnPositionReset(function() return RestoreNativeAnchors() end)

  Apply()
  RegisterEvents()

  U.Debug("buffframe mover registered on " .. tostring(rootName))

  -- One anchor read per tick against frames that move rarely.
  U.RegisterUpdate("buffframe.anchor", 1.0, Apply)
end

-- Written by the "Unit Frame Auras" settings page. Applying immediately is the
-- whole effect: EnforceVisibility runs at the top of Apply.
function U.SetNativeAuraFrameShown(value)
  Config().nativeShown = value and true or false
  Apply()
end

-- Reported by /uui check.
function U.BuffFrameReport()
  return {
    root = rootName,
    point = rootPoint,
    second = secondName,
    skipped = skipped,
    anchor = anchor and true or false,
    placed = StoredPosition() and true or false,
    driving = driving,
    nativeShown = U.GetNativeAuraFrameShown(),
    nativeAnchorCaptured = (root and captured[root]) and true or false,
  }
end
