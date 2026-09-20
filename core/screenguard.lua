-- unrealUI :: core/screenguard.lua
--
-- Keeps every interface unrealUI places inside the screen, whatever the theme.
--
-- Two jobs, one owner:
--
--   * Fit. A window larger than UIParent (the 704-high settings panel on a
--     660-high UI, the Spellbook on the same screen) is scaled down until it
--     fits. A clamp alone cannot help there: one edge always stays off screen.
--   * Clamp. A frame whose rectangle leaves the screen is shifted back by the
--     overshoot. Its own anchor point is kept, so a bottom-pinned bag still
--     grows upwards and a TOPLEFT list still grows downwards.
--
-- Callers:
--
--   * core/windowdrag.lua registers every draggable window (UnrealUI-built and
--     native stock windows alike) with U.GuardOnScreen, and checks on open and
--     on drop. Registered windows are then re-checked on a slow sweep while
--     shown, which covers content that resizes after opening, a native
--     re-anchor after OnShow, and a resolution or UI-scale change.
--     Flat Modern windows also provide their authored height here, because the
--     native panel manager can resize an already-open window when another
--     interface opens.
--   * The stock client windows in NATIVE_WINDOWS below are guarded by exact
--     name, resolved lazily because several load on demand. They are covered
--     whatever theme or per-module override is active, so a stock window does
--     not depend on some module happening to register a drag handle for it.
--   * The bag, bank and craft tracker windows register with their own position
--     ids.
--   * core/mover.lua clamps the HUD elements it places through
--     U.ClampPositionToScreen, once on apply and on drop. HUD movers are not
--     swept and never scaled: several are native frames (MinimapCluster) and
--     theme code owns their scale.
--
-- Geometry is in UIParent units. knowledge.json /
-- frames.own_scale_resizes_about_anchor_in_parent_space (BEHAVIOR_VERIFIED):
-- GetWidth/GetHeight/GetLeft/GetBottom of a UIParent child already include its
-- own scale, anchor offsets are not divided by it, and SetScale resizes about
-- the anchor point. So no scale conversion is needed below.
--
-- A shown window is measured by its edges, not by its first anchor point:
-- frames.extra_anchor_point_survives_addon_setpoint and
-- ui.microbutton_questlog_second_anchor_point record the client adding a second
-- anchor that wins over point 1, so point-1 arithmetic can call an off-screen
-- stock window on screen. GetNumPoints is BEHAVIOR_VERIFIED there. A window
-- with one UIParent point is shifted by its offsets (its growth direction is
-- kept); any other anchoring is replaced by one TOPLEFT point at the corrected
-- rectangle.
--
-- Frame:GetScale / Frame:SetScale are documented (DOCUMENTED_NOT_RUNTIME_
-- VERIFIED); SetScale is already used on windows here (modules/bank.lua,
-- the World Map probe). Every call is pcall-guarded and a failed read skips the
-- frame rather than guessing.
--
-- Deliberately not covered: the native loot frame (kept untouched), the world
-- map (a fullscreen panel), the stock bank and container frames (modules/bank.lua
-- and modules/bags.lua park and suppress them), static popups (stacked against
-- each other), tooltips and dropdown menus (placed against the cursor or their
-- owner every time they open), and frames not parented to UIParent (their edges
-- are in another frame's space).

local U = UnrealUI

local sg = {
  SWEEP_INTERVAL = 0.25,
  -- Scale changes below this are float noise from GetScale readback.
  SCALE_EPSILON = 0.001,
  -- Offsets closer than this are treated as already on screen.
  OFFSET_EPSILON = 0.5,
  guarded = {},   -- frame -> options
  order = {},     -- frames, registration order
  fits = {},      -- frame -> { base = scale the owner set, set = scale we set }
  holds = {},     -- frame -> true while its owner is dragging it
  -- Stock top-level windows, by exact name. No discovery walk: a name that
  -- does not exist on this client simply never resolves.
  NATIVE_WINDOWS = {
    "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame",
    "QuestLogFrame", "FriendsFrame", "InspectFrame", "DressUpFrame",
    "MerchantFrame", "ClassTrainerFrame", "GossipFrame", "QuestFrame",
    "MailFrame", "OpenMailFrame", "TradeFrame", "TradeSkillFrame", "CraftFrame",
    "AuctionFrame", "TaxiFrame", "PetStableFrame", "TabardFrame",
    "GuildRegistrarFrame", "PetitionFrame", "ItemTextFrame", "BattlefieldFrame",
    "WorldStateScoreFrame", "MacroFrame", "KeyBindingFrame", "GameMenuFrame",
    "OptionsFrame", "SoundOptionsFrame", "UIOptionsFrame", "HelpFrame",
  },
  nativeResolved = {},
  -- Name lookups run on every Nth sweep only; resolved frames are swept always.
  RESOLVE_EVERY = 8,
  sweepCount = 0,
}

local function PointFactor(point, low, high)
  if type(point) ~= "string" then return 0.5 end
  if string.find(point, low, 1, true) then return 0 end
  if string.find(point, high, 1, true) then return 1 end
  return 0.5
end

local function FrameSize(frame)
  local wOk, width = pcall(frame.GetWidth, frame)
  local hOk, height = pcall(frame.GetHeight, frame)
  width, height = wOk and tonumber(width), hOk and tonumber(height)
  if not width or not height or width <= 0 or height <= 0 then return nil end
  return width, height
end

local function FrameScale(frame)
  if not frame or not frame.GetScale then return 1 end
  local ok, scale = pcall(frame.GetScale, frame)
  scale = ok and tonumber(scale) or nil
  return scale and scale > 0 and scale or 1
end

-- Restores a window's authored height before any fit or clamp measurement.
-- GetHeight reports the scaled result on this client, while SetHeight takes
-- the frame's own units, so compare against fixedHeight * current scale.
local function RestoreFixedHeight(frame, options)
  local fixedHeight = options and tonumber(options.fixedHeight)
  if not fixedHeight or fixedHeight <= 0 or not frame.SetHeight then return false end

  local ok, height = pcall(frame.GetHeight, frame)
  local current = ok and tonumber(height) or nil
  if current and math.abs(current - fixedHeight * FrameScale(frame)) <
     sg.OFFSET_EPSILON then
    return false
  end
  return pcall(frame.SetHeight, frame, fixedHeight)
end

local function IsShown(frame)
  if not frame or not frame.IsShown then return false end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown and true or false
end

-- Offsets (dx, dy) that bring a width x height rectangle, whose bottom-left
-- corner is at (left, bottom), inside the screen. A rectangle still wider or
-- taller than the screen keeps its left edge and its top edge visible, which
-- is where every window's title and drag strip are.
local function Overshoot(left, bottom, width, height)
  local screenWidth, screenHeight = U.UIWidth(), U.UIHeight()
  local dx, dy = 0, 0

  if width >= screenWidth or left < 0 then
    dx = -left
  elseif left + width > screenWidth then
    dx = screenWidth - (left + width)
  end

  local top = bottom + height
  if height >= screenHeight or top > screenHeight then
    dy = screenHeight - top
  elseif bottom < 0 then
    dy = -bottom
  end
  return dx, dy
end

-- position  { point, relativePoint, x, y } in UIParent units, as stored.
-- Returns the on-screen version of that position and whether it changed. The
-- frame is read for its size only; nothing is applied.
function U.ClampPositionToScreen(frame, position)
  if not frame or type(position) ~= "table" then return position, false end
  local width, height = FrameSize(frame)
  if not width then return position, false end

  local point = position.point
  local relativePoint = position.relativePoint or point
  local x, y = tonumber(position.x) or 0, tonumber(position.y) or 0
  local left = U.UIWidth() * PointFactor(relativePoint, "LEFT", "RIGHT") + x -
               width * PointFactor(point, "LEFT", "RIGHT")
  local bottom = U.UIHeight() * PointFactor(relativePoint, "BOTTOM", "TOP") + y -
                 height * PointFactor(point, "BOTTOM", "TOP")

  local dx, dy = Overshoot(left, bottom, width, height)
  if math.abs(dx) < sg.OFFSET_EPSILON and math.abs(dy) < sg.OFFSET_EPSILON then
    return position, false
  end
  return {
    point = point,
    relativePoint = relativePoint,
    x = x + dx,
    y = y + dy,
  }, true
end

-- Scales `frame` down just enough to fit the screen, or back up towards the
-- scale its owner gave it once there is room again. The owner's own scale is
-- remembered separately, so a module that sets a scale of its own is
-- multiplied rather than overwritten; if the owner changes it later, that new
-- value becomes the base.
function U.FitFrameToScreen(frame)
  if not frame or not frame.SetScale or not frame.GetScale then return false end
  local width, height = FrameSize(frame)
  if not width then return false end
  local ok, current = pcall(frame.GetScale, frame)
  current = ok and tonumber(current)
  if not current or current <= 0 then return false end

  local fit = sg.fits[frame]
  local base = current
  if fit and math.abs(current - fit.set) < sg.SCALE_EPSILON then
    base = fit.base
  end

  -- Reported size includes the current scale; divide it back to the size the
  -- frame has at its owner's scale.
  local naturalWidth = width * base / current
  local naturalHeight = height * base / current
  local factor = math.min(1, U.UIWidth() / naturalWidth,
                          U.UIHeight() / naturalHeight)
  local target = base * factor

  if math.abs(target - current) < sg.SCALE_EPSILON then return false end
  if not pcall(frame.SetScale, frame, target) then return false end
  if factor < 1 then
    sg.fits[frame] = { base = base, set = target }
  else
    sg.fits[frame] = nil
  end
  return true
end

local function Read(frame, method)
  local fn = frame and frame[method]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, frame)
  return ok and tonumber(value) or nil
end

local function ParentIsUIParent(frame)
  if not frame.GetParent then return false end
  local ok, parent = pcall(frame.GetParent, frame)
  if not ok then return false end
  if type(parent) == "string" then parent = U.G(parent) end
  return parent == UIParent
end

-- The SetPoint offsets that put a width x height rectangle's bottom-left corner
-- at (left, bottom) through the given point pair.
local function OffsetsFor(point, relativePoint, left, bottom, width, height)
  return left + width * PointFactor(point, "LEFT", "RIGHT") -
           U.UIWidth() * PointFactor(relativePoint, "LEFT", "RIGHT"),
         bottom + height * PointFactor(point, "BOTTOM", "TOP") -
           U.UIHeight() * PointFactor(relativePoint, "BOTTOM", "TOP")
end

-- The point pair a frame is re-anchored through: its own when it has exactly
-- one UIParent point (keeps its growth direction), TOPLEFT otherwise. Only the
-- names are used; GetPoint's offsets are never trusted.
function sg.PointNames(frame)
  local point, relative, relativePoint = U.GetFramePoint(frame, 1)
  local count = Read(frame, "GetNumPoints")
  if not point or (relative and relative ~= UIParent) or
     (count and count ~= 1) then
    return "TOPLEFT", "TOPLEFT"
  end
  return point, relativePoint or point
end

-- Where a UIParent child is, as a storable SetPoint position
-- { point, relativePoint, x, y }, derived from its measured edges.
--
-- Use this, not U.GetFramePoint's offsets, to save or compare a window
-- position. /urp probe screenguardpoints (2026-09-17): after SetPoint on every
-- one of the 9 same-name point pairs with y = +40 and -40, GetPoint read Y back
-- with the SAME sign 18 of 18 times, and a frame's anchor after
-- StartMoving/StopMovingOrSizing (TOPLEFT) did too. U.GetFramePoint negates Y
-- (frames.getpoint_relative_name_y_inverted), so a position saved through it
-- comes back mirrored across the anchor -- how the Spellbook was saved at
-- y = 157 and reopened above the screen. Edges are sign-safe either way.
function U.GetFramePlacement(frame)
  if not frame or not ParentIsUIParent(frame) then return nil end
  local width, height = FrameSize(frame)
  local left, bottom = Read(frame, "GetLeft"), Read(frame, "GetBottom")
  if not width or not left or not bottom then return nil end
  local point, relativePoint = sg.PointNames(frame)
  local x, y = OffsetsFor(point, relativePoint, left, bottom, width, height)
  return { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- Drop-in for U.GetFramePoint(frame, 1) wherever the offsets are saved,
-- replayed or compared. A single-point UIParent child anchored to UIParent gets
-- its offsets from its measured edges (U.GetFramePlacement), which is sign-safe
-- (frames.getpoint_y_same_sign_as_setpoint). Any other anchoring -- a relative
-- frame other than UIParent, several points, a non-UIParent parent -- has no
-- verified sign and falls back to U.GetFramePoint unchanged.
function U.ReadFramePoint(frame)
  local point, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if not point or (relative and relative ~= UIParent) then
    return point, relative, relativePoint, x, y
  end
  local count = Read(frame, "GetNumPoints")
  if count and count ~= 1 then
    return point, relative, relativePoint, x, y
  end
  local placement = U.GetFramePlacement(frame)
  if not placement or placement.point ~= point then
    return point, relative, relativePoint, x, y
  end
  return point, relative, relativePoint, placement.x, placement.y
end

local function OnScreen(frame)
  local width, height = FrameSize(frame)
  local left, bottom = Read(frame, "GetLeft"), Read(frame, "GetBottom")
  if not width or not left or not bottom then return false end
  local dx, dy = Overshoot(left, bottom, width, height)
  return math.abs(dx) < sg.OFFSET_EPSILON and math.abs(dy) < sg.OFFSET_EPSILON
end

-- Applies the clamp to a shown frame in place, from where it actually is.
-- Returns the position it applied, or false.
--
-- The new offsets come from the measured edges only, never from GetPoint's
-- offsets. ScreenGuardProbe.lua (2026-09-17, SpellBookFrame, classic-wow):
-- after SetPoint(TOPLEFT, UIParent, TOPLEFT, 1299, -9344) GetPoint read back
-- y = -9344, the SAME sign, while U.GetFramePoint negates Y per
-- frames.getpoint_relative_name_y_inverted. Adding the correction to that
-- negated offset doubled the error on every sweep (18432, -36864, 73472, ...)
-- until the frame hit the integer limit and vanished. GetLeft/GetBottom were
-- correct throughout. Only the point NAMES are taken from GetPoint.
function U.ClampFrameToScreen(frame)
  if not frame or not ParentIsUIParent(frame) then return false end
  local width, height = FrameSize(frame)
  local left, bottom = Read(frame, "GetLeft"), Read(frame, "GetBottom")
  if not width or not left or not bottom then return false end

  local dx, dy = Overshoot(left, bottom, width, height)
  if math.abs(dx) < sg.OFFSET_EPSILON and math.abs(dy) < sg.OFFSET_EPSILON then
    return false
  end

  local point, relativePoint = sg.PointNames(frame)
  local x, y = OffsetsFor(point, relativePoint, left + dx, bottom + dy,
                          width, height)
  local position = { point = point, relativePoint = relativePoint, x = x, y = y }
  if not U.ApplyFramePoint(frame, position) then return false end

  -- A frame that was sized by two anchors keeps the size it had. SetWidth
  -- takes the frame's own units, GetWidth reports them scaled.
  local newWidth, newHeight = FrameSize(frame)
  local scale = Read(frame, "GetScale") or 1
  if scale <= 0 then scale = 1 end
  if not newWidth or math.abs(newWidth - width) > sg.OFFSET_EPSILON then
    pcall(frame.SetWidth, frame, width / scale)
  end
  if not newHeight or math.abs(newHeight - height) > sg.OFFSET_EPSILON then
    pcall(frame.SetHeight, frame, height / scale)
  end

  -- Edge readback is immediate after SetPoint (same probe). A correction that
  -- did not land on screen is undone rather than saved, so a wrong assumption
  -- can never run away across sweeps again.
  if not OnScreen(frame) then
    local ox, oy = OffsetsFor(point, relativePoint, left, bottom, width, height)
    U.ApplyFramePoint(frame, { point = point, relativePoint = relativePoint,
                               x = ox, y = oy })
    local nameOk, name = pcall(frame.GetName, frame)
    U.Debug("screenguard: correction for " .. tostring(nameOk and name or "?") ..
            " did not land on screen; reverted")
    return false
  end
  return position
end

-- Fit, then clamp: scaling resizes about the anchor, so it can push an edge
-- out and must come first. A moved frame with a stored position keeps the
-- correction; one still on its default is re-derived next time instead of
-- inventing a saved placement.
function U.CheckOnScreen(frame)
  local options = sg.guarded[frame]
  if not options or not IsShown(frame) or sg.holds[frame] then return false end
  if type(options.suspended) == "function" and options.suspended() then
    return false
  end

  local restored = RestoreFixedHeight(frame, options)
  local fitted = options.fit ~= false and U.FitFrameToScreen(frame)
  local position = U.ClampFrameToScreen(frame)
  if position and options.id and U.GetPosition(options.id) then
    U.SavePosition(options.id, position.point, position.relativePoint,
                   position.x, position.y)
  end
  if (restored or fitted or position) and type(options.onChanged) == "function" then
    options.onChanged(frame)
  end
  return restored or fitted or position and true or false
end

local function ResolveNativeWindows()
  local i
  for i = 1, table.getn(sg.NATIVE_WINDOWS) do
    local name = sg.NATIVE_WINDOWS[i]
    if not sg.nativeResolved[name] then
      local frame = U.G(name)
      if type(frame) == "table" and frame.IsShown then
        sg.nativeResolved[name] = true
        U.GuardOnScreen(frame, {})
      end
    end
  end
end

local function Sweep()
  sg.sweepCount = sg.sweepCount + 1
  if math.mod(sg.sweepCount, sg.RESOLVE_EVERY) == 1 then
    ResolveNativeWindows()
  end

  local i
  for i = 1, table.getn(sg.order) do
    local frame = sg.order[i]
    if IsShown(frame) then U.CheckOnScreen(frame) end
  end
end

-- frame    a UIParent-anchored window.
-- options  { id = "position store key" (saved when a correction moves it),
--            fit = false to never scale it,
--            fixedHeight = authored height in the frame's own units,
--            suspended = function() return true while it must be left alone end,
--            onChanged = function(frame) end }
-- Registering a frame again merges the new options over the old, so a module
-- drag handle registered after the native-name pass still supplies its id and
-- drag state.
function U.GuardOnScreen(frame, options)
  if not frame then return false end
  local existing = sg.guarded[frame]
  if existing then
    local key, value
    for key, value in pairs(options or {}) do existing[key] = value end
    return true
  end
  sg.guarded[frame] = options or {}
  table.insert(sg.order, frame)
  return true
end

-- Drag code without a `suspended` callback holds its frame for the length of a
-- gesture so it is not pulled back under the cursor mid-drag; the drop path
-- releases it and checks once. Per frame, so a drop that never arrives can only
-- leave that one frame unguarded until its next drop.
function U.HoldScreenGuard(frame, held)
  if not frame then return end
  sg.holds[frame] = held and true or nil
end

U.RegisterUpdate("screenguard.sweep", sg.SWEEP_INTERVAL, Sweep)
