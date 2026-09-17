-- unrealUI :: modules/durabilityframe.lua
--
-- Gives the native armour-durability paper doll an unrealUI Move UI anchor.
-- The artwork and its show/hide lifecycle remain client-owned; only its
-- placement is attached to an addon-owned frame.

local U = UnrealUI

local DF = U.RegisterModule("durabilityframe")

local FRAME_NAME = "DurabilityFrame"
local WIDTH = 80
local HEIGHT = 70
local FALLBACK_POSITION = {
  point = "LEFT", relativePoint = "RIGHT", x = -120, y = 120,
}

local anchor

local function NativePosition(frame)
  local point, relative, relativePoint, x, y = U.ReadFramePoint(frame)
  if point and relative == UIParent then
    return {
      point = point,
      relativePoint = relativePoint or point,
      x = x,
      y = y,
    }
  end
  return FALLBACK_POSITION
end

-- UnrealPfUI modules/skin.lua is the available WORKING_SOURCE evidence for
-- this otherwise-unrecorded native widget: an 80x70 addon frame parents and
-- sizes DurabilityFrame. Re-resolve the global before binding so a replaced
-- native object is never retained as a cross-widget anchor. Unlike that source,
-- do not replace DurabilityFrame.SetPoint; the native method remains intact.
-- Re-resolved by name on every read rather than kept: rules/unreal-ui.md
-- forbids retaining a native object to poll, and the client may replace this
-- one when it rebuilds the paper doll. Undamaged equipment means the client
-- hides it, which is exactly when the anchor has nothing in it.
local function NativeShown()
  local current = U.G(FRAME_NAME)
  if not current then return false end
  local ok, shown = pcall(current.IsShown, current)
  if not ok then return false end
  return (shown and shown ~= 0) and true or false
end

local function BindNative()
  local current = U.G(FRAME_NAME)
  if not current or not anchor then return false end

  local ok, err = pcall(function()
    current:SetParent(anchor)
    current:ClearAllPoints()
    current:SetAllPoints(anchor)
    current:SetFrameLevel(1)
  end)
  if not ok then
    U.Debug("durability frame anchor: " .. tostring(err))
    return false
  end
  return true
end

function DF:OnEnable()
  local frame = U.G(FRAME_NAME)
  if not frame then
    U.Debug("durability frame: no " .. FRAME_NAME .. " on this client")
    return
  end

  local default = NativePosition(frame)
  anchor = CreateFrame("Frame", "UnrealUIDurabilityAnchor", UIParent)
  anchor:SetWidth(WIDTH)
  anchor:SetHeight(HEIGHT)
  anchor:Show()

  U.RegisterMover("durability", anchor, {
    label = U.L("MOVER_LABEL_DURABILITY"),
    default = default,
  })

  -- The paper doll only appears once something is actually damaged, so the
  -- anchor is empty on most characters most of the time. One square standing
  -- in for the armour figure is enough to place it.
  if type(U.RegisterMoverSample) == "function" then
    U.RegisterMoverSample("durability", {
      isEmpty = function() return not NativeShown() end,
      cells = { count = 1, inset = 8 },
    })
  end

  BindNative()

  -- The client may rebuild the paper doll when equipment durability changes.
  -- This is an accelerator; the low-frequency pass also repairs a replaced or
  -- re-anchored native root without taking over its visibility lifecycle.
  U.RegisterEvent("UPDATE_INVENTORY_DURABILITY", BindNative)
  U.RegisterUpdate("durabilityframe.anchor", 1.0, BindNative)
end
