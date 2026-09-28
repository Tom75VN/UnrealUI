-- unrealUI :: modules/buffframe.lua
--
-- The client's own buff / debuff display beside the minimap, left exactly as
-- the client draws it, with a mover handle and Rogue poison charge counts.
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
--   * The collapse arrow beside the row rides that same Hide() path rather
--     than adding a second way of hiding these frames: it only moves the
--     answer EnforceVisibility already computes. It is an unrealUI-owned
--     button parented to our own anchor and anchored *outside* the icon block
--     on the row's right edge, so it never sits in front of an icon and never
--     needs a native child as a relative frame (.claude/rules/unreal-ui.md,
--     native widget ownership boundaries). It is lined up with the row from
--     the anchor's own captured corner and a nominal row height, not by
--     reading a buff button.

local U = UnrealUI
local M = U.media

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
  -- The arrow's state, kept apart from nativeShown: that one is the settings
  -- page switching the whole display off, arrow and all, while this one is the
  -- player folding the icons away and leaving the arrow behind to unfold them.
  collapsed = false,
  -- Icon sizes in UI units, one per row; 0 is the client's own 30
  -- (auraLayout.IconSize). `iconSize` is the buff row's.
  iconSize = 0,
  debuffIconSize = 0,
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

-- The two native containers, in the order they are preferred as the root.
local BUFF_NAME = "BuffFrame"
local ENCHANT_NAME = "TemporaryEnchantFrame"


-- Anchor offsets below this are treated as "unchanged" rather than drift.
local DRIFT_EPSILON = 0.5

-- The collapse arrow. Nominal stock buff icon size: the control's hit area is
-- one icon tall with the glyph centred in it, so it lines up with the first
-- row without reading a native buff button, which this module is not allowed
-- to keep hold of. An icon that is not this size on some build leaves the
-- arrow a couple of units off centre, which is the deliberate trade against
-- that read.
local NATIVE_ICON_SIZE = 30
-- Requested gap between the first icon and the arrow.
local TOGGLE_GAP = 5

-- The stock aura layout both handles are sized to, and the edit-mode
-- placeholders are drawn in: eight icons to a row with the 5-unit gap the
-- aurarow probe measured between two icons (30 + 5 + 30 = 65), and room under
-- each row for the native duration text. Vanilla 1.12 shows 16 buffs in two
-- rows and 8 debuffs in one. The handles are grab targets built from these
-- numbers, not measurements of the client's rows (knowledge.json /
-- frames.native_aura_row_rect_narrower_than_icons: BuffFrame's own rect does
-- not bound its icons, so the buff handle no longer mirrors it).
--
-- `kind` is "buffs" or "debuffs" throughout: each row has its own size (user
-- request, 2026-09-29).
local auraLayout = {
  PER_ROW = 8,
  GAP = 5,
  ROW_GAP = 15,
  ROWS = { buffs = 2, debuffs = 1 },
  CONFIG_KEY = { buffs = "iconSize", debuffs = "debuffIconSize" },
  SIZE = { min = 16, max = 48, step = 1 },
  -- The native buttons each row's size is written to, resolved by exact stock
  -- name on every write and never kept. Vanilla 1.12's FrameXML names them
  -- (WORKING_SOURCE): BuffButton0-15 are buffs, BuffButton16-23 debuffs, and
  -- the weapon-enchant buttons sit with the buffs.
  BUTTONS = { buffs = {}, debuffs = {} },
  written = {},    -- kind -> the size last written to its buttons
  border = {},     -- button name -> its border's stock { w, h }, read once
}

do
  local i
  for i = 0, 15 do table.insert(auraLayout.BUTTONS.buffs, "BuffButton" .. i) end
  table.insert(auraLayout.BUTTONS.buffs, "TempEnchant1")
  table.insert(auraLayout.BUTTONS.buffs, "TempEnchant2")
  for i = 16, 23 do table.insert(auraLayout.BUTTONS.debuffs, "BuffButton" .. i) end
end

-- The chosen icon size (user request, 2026-09-29), from the size slider on
-- that row's handle panel. `value` previews a size without storing it.
function auraLayout.IconSize(kind, value)
  value = tonumber(value) or
          tonumber(Config()[auraLayout.CONFIG_KEY[kind] or "iconSize"]) or 0
  if value <= 0 then return NATIVE_ICON_SIZE end
  local limit = auraLayout.SIZE
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return math.floor(value / limit.step + 0.5) * limit.step
end

-- The icons grow; the client's gaps between them stay the stock 5 and 15,
-- since only the buttons are resized (auraLayout.Apply).
function auraLayout.Width(kind, value)
  return auraLayout.PER_ROW * auraLayout.IconSize(kind, value) +
         (auraLayout.PER_ROW - 1) * auraLayout.GAP
end

function auraLayout.Height(kind, value)
  local rows = auraLayout.ROWS[kind] or 1
  return rows * auraLayout.IconSize(kind, value) +
         (rows - 1) * auraLayout.ROW_GAP
end

-- The corner a row grows from, as a full two-part point name. Both rows use
-- the buff row's (user request, 2026-09-29).
function auraLayout.Corner(point)
  point = point or "TOPRIGHT"
  local vertical = string.find(point, "BOTTOM") and "BOTTOM" or "TOP"
  local horizontal = string.find(point, "LEFT") and "LEFT" or "RIGHT"
  return vertical .. horizontal
end

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
local editShown = nil      -- advanced visibility gate; nil follows config
local toggle = nil         -- the collapse arrow beside the row
local toggleOffsetX = nil  -- last x offset written for it, to avoid rewrites
local chargeOverlays = {}
-- Forward declaration: SetEditShown below refreshes the arrow, which cannot be
-- built until the anchor exists further down the file.
local UpdateToggle

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

-- The arrow's own state. Its own accessors rather than a second meaning for
-- nativeShown, so the settings checkbox and the arrow cannot overwrite each
-- other's intent.
function U.GetNativeAuraCollapsed()
  local value = Config().collapsed
  if value == nil then return defaults.collapsed end
  return value and true or false
end

-- The single answer the native frames are driven from.
local function IconsShown()
  return U.GetNativeAuraFrameShown() and not U.GetNativeAuraCollapsed()
end

local function IsVisible(frame)
  local ok, shown = pcall(frame.IsShown, frame)
  return (ok and shown and shown ~= 0) and true or false
end

-- Resolved by exact stock name each pass; no native child is retained or used
-- as a persistent anchor.
local TEMP_ENCHANT_BUTTONS = { "TempEnchant1", "TempEnchant2" }

local function HideChargeOverlays()
  local i
  for i = 1, table.getn(chargeOverlays) do
    chargeOverlays[i]:Hide()
  end
end

local function ChargeOverlay(index)
  local overlay = chargeOverlays[index]
  if overlay then return overlay end

  overlay = CreateFrame("Frame", nil, anchor)
  overlay:SetWidth(NATIVE_ICON_SIZE)
  overlay:SetHeight(NATIVE_ICON_SIZE)
  overlay.label = U.CreateLabel(overlay, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if overlay.label then
    overlay.label:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
  end
  overlay:Hide()
  chargeOverlays[index] = overlay
  return overlay
end

local function FrameRect(frame)
  if not frame then return nil end

  local okLeft, left = pcall(frame.GetLeft, frame)
  local okBottom, bottom = pcall(frame.GetBottom, frame)
  local okWidth, width = pcall(frame.GetWidth, frame)
  local okHeight, height = pcall(frame.GetHeight, frame)
  left = okLeft and tonumber(left) or nil
  bottom = okBottom and tonumber(bottom) or nil
  width = okWidth and Number(width) or nil
  height = okHeight and Number(height) or nil
  if not left or not bottom or not width or not height then return nil end
  return left, bottom, width, height
end

local function PlaceChargeOverlay(index, count)
  local button = U.G(TEMP_ENCHANT_BUTTONS[index])
  if not count or count < 1 or not button or not IsVisible(button) then
    local overlay = chargeOverlays[index]
    if overlay then overlay:Hide() end
    return
  end

  local left, bottom, width, height = FrameRect(button)
  local anchorLeft, anchorBottom = FrameRect(anchor)
  if not left or not anchorLeft then
    local overlay = chargeOverlays[index]
    if overlay then overlay:Hide() end
    return
  end

  local overlay = ChargeOverlay(index)
  local x, y = left - anchorLeft, bottom - anchorBottom
  if overlay.uuiX ~= x or overlay.uuiY ~= y or
     overlay.uuiWidth ~= width or overlay.uuiHeight ~= height then
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, y)
    overlay:SetWidth(width)
    overlay:SetHeight(height)
    overlay.uuiX, overlay.uuiY = x, y
    overlay.uuiWidth, overlay.uuiHeight = width, height
  end

  local okLevel, level = pcall(button.GetFrameLevel, button)
  level = okLevel and tonumber(level) or nil
  if level and overlay.uuiLevel ~= level then
    pcall(overlay.SetFrameLevel, overlay, level + 5)
    overlay.uuiLevel = level
  end

  local text = tostring(math.floor(count))
  if overlay.uuiText ~= text then
    overlay.uuiText = text
    if overlay.label then overlay.label:SetText(text) end
  end
  if overlay.label then overlay:Show() end
end

local function UpdatePoisonCharges()
  local shown = editShown
  if shown == nil then shown = IconsShown() end
  if not shown or not anchor or type(U.IsRogue) ~= "function" or
     not U.IsRogue() then
    HideChargeOverlays()
    return
  end

  local get = U.G("GetWeaponEnchantInfo")
  if type(get) ~= "function" then
    HideChargeOverlays()
    return
  end

  local ok, main, mainTime, mainCharges, off, offTime, offCharges = pcall(get)
  if not ok then
    HideChargeOverlays()
    return
  end

  PlaceChargeOverlay(1, main and tonumber(mainCharges) or nil)
  PlaceChargeOverlay(2, off and tonumber(offCharges) or nil)
end

local function EnforceVisibility()
  local shown = editShown
  if shown == nil then shown = IconsShown() end
  local i
  for i = 1, table.getn(managed) do
    local frame = managed[i]
    if IsVisible(frame) ~= shown then
      if shown then pcall(frame.Show, frame) else pcall(frame.Hide, frame) end
    end
  end
end

local function SetEditShown(shown)
  editShown = shown
  EnforceVisibility()
  UpdateToggle()
end

-- ---------------------------------------------------------------------------
-- The client's own anchors
--
-- Captured once, before the mover is registered and therefore before anything
-- of ours can have moved either frame. Replayed on /uui reset.
-- ---------------------------------------------------------------------------
local function CaptureNativeAnchor(frame, name)
  if not frame then return nil end

  local point, relative, relativePoint, x, y = U.ReadFramePoint(frame)
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

-- Both handles are the same kind of footprint (user request, 2026-09-29): the
-- row's stock icon block at its own size, laid corner-on-corner with the row.
local function SizeAnchor(frame, kind, value)
  if not frame then return end

  local width = auraLayout.Width(kind, value)
  local height = auraLayout.Height(kind, value)

  -- Only written when it actually changes: the handle is SetAllPoints to this
  -- frame, so a size write is a handle relayout.
  if frame.uuiWidth ~= width then
    frame:SetWidth(width)
    frame.uuiWidth = width
  end
  if frame.uuiHeight ~= height then
    frame:SetHeight(height)
    frame.uuiHeight = height
  end
end

-- The client's gap between the two containers is room for the enchant icons,
-- so it grows with the buff size.
local function SecondOffset()
  local ratio = auraLayout.IconSize("buffs") / NATIVE_ICON_SIZE
  return secondOffsetX * ratio, secondOffsetY * ratio
end

local function AnchorDrifted(frame, position)
  local point, relative, relativePoint, x, y = U.ReadFramePoint(frame)
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
    local x, y = SecondOffset()
    pcall(function()
      second:ClearAllPoints()
      second:SetPoint(secondPoint, anchor, rootPoint, x, y)
    end)
  end

  driving = true
  -- The handle is on its stored position now; ShadowCorner must write again
  -- once the row is handed back.
  anchor.uuiFollowX, anchor.uuiFollowY = nil, nil
end

-- ---------------------------------------------------------------------------
-- The handles' origin corner (user request, 2026-09-29)
--
-- Both handles are held by their row's origin corner -- TOPRIGHT on the stock
-- layout, auraLayout.Corner -- as a single UIParent point, so a bigger icon
-- size grows the handle left and down, away from that corner. The mover stores
-- a dropped handle by the point it is held by (core/screenguard.lua,
-- sg.PointNames), but only when that is its one UIParent point: the buff handle
-- used to be anchored to BuffFrame itself, which the mover stored as TOPLEFT,
-- so the handle grew right instead.
-- ---------------------------------------------------------------------------

-- Holds `frame` on `native`'s origin corner, copied as a UIParent coordinate
-- off its rect rather than anchored to it (.claude/rules/unreal-ui.md, native
-- widget ownership). Written only when the corner has moved.
local function ShadowCorner(frame, native, point)
  local left, bottom, width, height = FrameRect(native)
  if not frame or not left then return end

  local x, y = left + width / 2, bottom + height / 2
  if string.find(point, "LEFT") then x = left
  elseif string.find(point, "RIGHT") then x = left + width end
  if string.find(point, "BOTTOM") then y = bottom
  elseif string.find(point, "TOP") then y = bottom + height end

  if frame.uuiFollowX and math.abs(x - frame.uuiFollowX) <= DRIFT_EPSILON and
     math.abs(y - frame.uuiFollowY) <= DRIFT_EPSILON then
    return
  end
  frame.uuiFollowX, frame.uuiFollowY = x, y
  pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
  end)
end

-- A stored position held by another point (every buff placement made before
-- this change) is re-expressed once by the origin corner at the same place, and
-- written back so the drift check and the next drag both see the corner.
local function HoldStoredCorner(frame, id, position, point)
  if not frame or position.point == point then return position end
  if not U.ApplyFramePoint(frame, position) then return position end

  local left, bottom, width, height = FrameRect(frame)
  if not left then return position end
  local originLeft, originBottom = FrameRect(UIParent)
  left, bottom = left - (originLeft or 0), bottom - (originBottom or 0)

  local x = string.find(point, "LEFT") and left or left + width
  local y = string.find(point, "BOTTOM") and bottom or bottom + height
  if not U.SavePosition(id, point, "BOTTOMLEFT", x, y) then return position end
  frame.uuiFollowX, frame.uuiFollowY = nil, nil
  return U.GetPosition(id) or position
end

local function FollowNative()
  ShadowCorner(anchor, root, auraLayout.Corner(rootPoint))
end

-- ---------------------------------------------------------------------------
-- The debuff row, on its own handle (user request, 2026-09-29)
--
-- WORKING_SOURCE, not runtime evidence: query_compat.py has no record of this
-- client's debuff buttons. Vanilla 1.12's FrameXML makes BuffButton16 the
-- first debuff button, each later one anchored to the one before it, and
-- DragonflightUI-Reforged moves the whole row on a 1.12-era client by
-- re-anchoring exactly that button. So it is the row's root here. If the name
-- does not resolve, no debuff handle is registered and the row stays with the
-- buffs, as before.
--
-- The same two modes as the buff row. Until the player drops this handle the
-- button stays where the client put it and the anchor shadows it -- by copying
-- the button's corner as a UIParent coordinate, never by anchoring to it
-- (.claude/rules/unreal-ui.md, native widget ownership). Once dropped, the
-- button is pointed at the anchor corner-on-corner. The button is resolved by
-- name on every pass rather than kept.
-- ---------------------------------------------------------------------------
local debuffs = {
  MOVER_ID = "debuffs",
  ROOT_NAME = "BuffButton16",
  anchor = nil,
  point = "TOPRIGHT",
  capture = nil,    -- the button's own anchor as the client had it
  driving = false,
}

function debuffs.Root()
  return U.G(debuffs.ROOT_NAME)
end

function debuffs.StoredPosition()
  local ok, position = pcall(U.GetPosition, debuffs.MOVER_ID)
  if not ok or type(position) ~= "table" then return nil end
  if type(position.point) ~= "string" then return nil end
  return position
end

-- Replayed on /uui reset, and when the stored position goes away.
function debuffs.Restore()
  local saved, button = debuffs.capture, debuffs.Root()
  if not saved or not button then return false end
  local ok = pcall(function()
    button:ClearAllPoints()
    button:SetPoint(saved.point, saved.relative, saved.relativePoint,
                    saved.x, saved.y)
  end)
  if ok then
    debuffs.driving = false
    debuffs.anchor.uuiFollowX, debuffs.anchor.uuiFollowY = nil, nil
  end
  return ok
end

-- The button's origin corner, read as a bounded number off its rect.
function debuffs.Follow()
  ShadowCorner(debuffs.anchor, debuffs.Root(), debuffs.point)
end

function debuffs.Drive()
  local button = debuffs.Root()
  if not button then return end

  local point = debuffs.point
  local at, relative, relativePoint, x, y = U.GetFramePoint(button, 1)
  if at == point and relative == debuffs.anchor and
     relativePoint == point and math.abs((x or 0)) <= DRIFT_EPSILON and
     math.abs((y or 0)) <= DRIFT_EPSILON then
    return
  end

  pcall(function()
    button:ClearAllPoints()
    button:SetPoint(point, debuffs.anchor, point, 0, 0)
  end)
  debuffs.driving = true
  debuffs.anchor.uuiFollowX, debuffs.anchor.uuiFollowY = nil, nil
end

function debuffs.Apply(unlocked)
  if not debuffs.anchor then return end

  local position = debuffs.StoredPosition()
  if not position then
    if debuffs.driving then debuffs.Restore() end
    if not unlocked and not debuffs.driving then debuffs.Follow() end
    return
  end

  if not unlocked then
    position = HoldStoredCorner(debuffs.anchor, debuffs.MOVER_ID, position,
                                debuffs.point)
  end
  if not unlocked and AnchorDrifted(debuffs.anchor, position) then
    U.ApplyFramePoint(debuffs.anchor, position)
  end
  debuffs.Drive()
end

function debuffs.Setup()
  local button = debuffs.Root()
  if not button then
    U.Debug("buffframe: no " .. debuffs.ROOT_NAME ..
            "; debuffs stay on the buff handle")
    return
  end

  -- Before RegisterMover, which is what may apply a stored position.
  debuffs.capture = CaptureNativeAnchor(button, debuffs.ROOT_NAME)
  -- The buff row's origin corner, not the button's own anchor point (user
  -- request, 2026-09-29): both handles hold their row by the same corner, so
  -- both rows grow the same way from them. DragonflightUI-Reforged pins this
  -- button by TOPRIGHT too (WORKING_SOURCE).
  debuffs.point = auraLayout.Corner(rootPoint)

  local frame = CreateFrame("Frame", "UnrealUIDebuffAnchor", UIParent)
  -- A grab target, not a layout claim: one row of eight icons.
  SizeAnchor(frame, "debuffs")
  -- Only until the button's corner can be read: below the buff anchor, an
  -- addon frame, rather than off the native button.
  frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -TOGGLE_GAP)
  frame:Show()
  debuffs.anchor = frame
  debuffs.Follow()

  U.RegisterMover(debuffs.MOVER_ID, frame, {
    label = U.L("MOVER_LABEL_DEBUFFS"),
    visible = function() return U.GetNativeAuraFrameShown() end,
    setEditShown = SetEditShown,
  })
  U.OnPositionReset(function() return debuffs.Restore() end)
end

-- ---------------------------------------------------------------------------
-- Edit-mode placeholders (user requests, 2026-09-29)
--
-- While a handle is shown in Move UI it carries a placeholder for every icon
-- its row can hold -- 16 buffs, 8 debuffs -- laid out from the corner the
-- native row grows from, so the player sees where the row will land without
-- being buffed. They are the unit frames' aura placeholders: the shared
-- U.CreateMoverSampleCell square, shown through core/moversample.lua's
-- lifecycle as an `apply` sample, since the row's geometry is this file's.
-- ---------------------------------------------------------------------------
local preview = { sets = {} }

function preview.Layout(set, value)
  local size = auraLayout.IconSize(set.kind, value)
  local gap, rowGap = auraLayout.GAP, auraLayout.ROW_GAP
  local corner = auraLayout.Corner(rootPoint)
  local stepX = string.find(corner, "LEFT") and 1 or -1
  local stepY = string.find(corner, "TOP") and -1 or 1
  local count = auraLayout.PER_ROW * (auraLayout.ROWS[set.kind] or 1)
  local i
  for i = 1, count do
    local cell = set.cells[i]
    if not cell then
      cell = U.CreateMoverSampleCell(set.host)
      if not cell then return end
      set.cells[i] = cell
    end
    -- No math.mod: core/moversample.lua records it as version-specific here.
    local row = math.floor((i - 1) / auraLayout.PER_ROW)
    local column = (i - 1) - row * auraLayout.PER_ROW
    cell:SetWidth(size)
    cell:SetHeight(size)
    cell:ClearAllPoints()
    cell:SetPoint(corner, set.host, corner,
                  stepX * column * (size + gap), stepY * row * (size + rowGap))
  end
end

function preview.Show(set, value)
  local shown = set.live and editShown ~= false
  local i
  if shown then preview.Layout(set, value) end
  for i = 1, table.getn(set.cells) do
    if shown then set.cells[i]:Show() else set.cells[i]:Hide() end
  end
end

function preview.Register(kind, host)
  if not host or type(U.RegisterMoverSample) ~= "function" or
     type(U.CreateMoverSampleCell) ~= "function" then
    return
  end
  local set = { kind = kind, host = host, cells = {}, live = false }
  preview.sets[kind] = set
  U.RegisterMoverSample(kind, {
    apply = function(shown)
      set.live = shown and true or false
      preview.Show(set)
    end,
  })
end

-- Re-lays one row's set, for a size change while Move UI is open.
function preview.Refresh(kind, value)
  local set = preview.sets[kind]
  if set and set.live then preview.Show(set, value) end
end

-- ---------------------------------------------------------------------------
-- Icon size (user requests, 2026-09-29)
--
-- One size per row, written to the row's native buttons as dimensions:
-- SetWidth/SetHeight on the button and its icon, and its border resized in
-- proportion from the size it had before anything was written. Not SetScale,
-- which would tie the rows together -- the debuff buttons are children of
-- BuffFrame in Vanilla's FrameXML (WORKING_SOURCE) -- and which a Button does
-- not honour on this client anyway (knowledge.json /
-- frames.microbar_button_own_setscale_not_applied; the micro bar is sized the
-- same way). The client's own gaps and anchors between the buttons are left
-- alone, so the rows keep their stock 5-unit spacing. At the stock size nothing
-- is written until a size has been, so an untouched interface keeps the
-- client's own buttons.
-- ---------------------------------------------------------------------------
function auraLayout.SizeButton(name, size)
  local button = U.G(name)
  if not button then return end

  local border = U.G(name .. "Border")
  if border and not auraLayout.border[name] then
    local okW, w = pcall(border.GetWidth, border)
    local okH, h = pcall(border.GetHeight, border)
    w, h = okW and Number(w), okH and Number(h)
    if w and h then auraLayout.border[name] = { w = w, h = h } end
  end

  pcall(button.SetWidth, button, size)
  pcall(button.SetHeight, button, size)
  local icon = U.G(name .. "Icon")
  if icon then
    pcall(icon.SetWidth, icon, size)
    pcall(icon.SetHeight, icon, size)
  end
  local base = auraLayout.border[name]
  if border and base then
    pcall(border.SetWidth, border, base.w * size / NATIVE_ICON_SIZE)
    pcall(border.SetHeight, border, base.h * size / NATIVE_ICON_SIZE)
  end
end

function auraLayout.Apply(kind, value)
  local size = auraLayout.IconSize(kind, value)
  local written = auraLayout.written[kind]
  if size ~= written and (written or size ~= NATIVE_ICON_SIZE) then
    local names, i = auraLayout.BUTTONS[kind]
    for i = 1, table.getn(names) do auraLayout.SizeButton(names[i], size) end
    auraLayout.written[kind] = size
  end

  if kind == "buffs" then
    SizeAnchor(anchor, kind, value)
    -- The enchant gap grows with the buffs: re-drive a placed row now.
    if driving and root then DriveNative() end
    -- The arrow stays one buff icon tall, centred on the first row.
    if toggle then pcall(toggle.SetHeight, toggle, size) end
  else
    SizeAnchor(debuffs.anchor, kind, value)
  end
  preview.Refresh(kind, value)
end

function U.GetNativeAuraIconSize(kind)
  return auraLayout.IconSize(kind)
end

-- Live while the slider thumb is held; nothing is stored until it is released.
function U.PreviewNativeAuraIconSize(kind, value)
  auraLayout.Apply(kind, value)
end

function U.SetNativeAuraIconSize(kind, value)
  if not auraLayout.CONFIG_KEY[kind] then return nil end
  if not tonumber(value) then return auraLayout.IconSize(kind) end
  local size = auraLayout.IconSize(kind, value)
  -- The stock size is stored as 0, so it keeps meaning "the client's own".
  Config()[auraLayout.CONFIG_KEY[kind]] = (size == NATIVE_ICON_SIZE) and 0 or size
  auraLayout.Apply(kind)
  return size
end

-- The contextual panel beside each handle, one per row since each row has its
-- own size (core/moverpanel.lua builds each spec once).
local sizePanel = { CONTENT_WIDTH = 200, SLIDER_WIDTH = 150 }

function sizePanel.Spec(kind, sliderName, panelName)
  local spec = {
    name = panelName,
    width = sizePanel.CONTENT_WIDTH + U.MoverPanelPad() * 2,
    height = 104,
    preferVertical = true,
  }
  function spec.build(frame, contentTop)
    local limit = auraLayout.SIZE
    local slider = U.CreateSlider(frame, {
      name = sliderName,
      text = U.L("AURA_ICON_SIZE"),
      width = sizePanel.SLIDER_WIDTH,
      boxWidth = 60,
      min = limit.min,
      max = limit.max,
      step = limit.step,
      value = auraLayout.IconSize(kind),
      onInputStart = function()
        if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
      end,
      onInput = function(v) U.PreviewNativeAuraIconSize(kind, v) end,
      onChange = function(v) U.SetNativeAuraIconSize(kind, v) end,
    })
    slider.SetPoint("TOPLEFT", frame, "TOPLEFT", U.MoverPanelPad(), contentTop)
    return { slider }, function() slider.SetValue(auraLayout.IconSize(kind)) end
  end
  return spec
end

function sizePanel.Register()
  if type(U.RegisterMoverPanel) ~= "function" then return end
  U.RegisterMoverPanel("buffs", sizePanel.Spec("buffs",
    "UnrealUIBuffIconSize", "UnrealUIBuffMoverSettings"))
  if debuffs.anchor then
    U.RegisterMoverPanel(debuffs.MOVER_ID, sizePanel.Spec("debuffs",
      "UnrealUIDebuffIconSize", "UnrealUIDebuffMoverSettings"))
  end
end

local function Apply()
  EnforceVisibility()
  UpdatePoisonCharges()
  if not anchor or not root then return end

  UpdateToggle()
  -- Nothing to place while it is off, and no anchor writes to fight over the
  -- frames if the client moves them in the meantime; the next Apply after it
  -- is switched back on re-drives from the stored position.
  if not U.GetNativeAuraFrameShown() then return end


  local position = StoredPosition()
  local unlocked = U.IsUnlocked()

  -- Before the buff row's early return below: the two handles are independent.
  debuffs.Apply(unlocked)

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
  if not unlocked then
    position = HoldStoredCorner(anchor, "buffs", position,
                                auraLayout.Corner(rootPoint))
  end
  if not unlocked and AnchorDrifted(anchor, position) then
    U.ApplyFramePoint(anchor, position)
  end

  if NativeDrifted(root, rootPoint, 0, 0) then
    DriveNative()
  elseif second then
    local x, y = SecondOffset()
    if NativeDrifted(second, secondPoint, x, y) then DriveNative() end
  end
end

-- ---------------------------------------------------------------------------
-- The collapse arrow
--
-- The arrow hangs one gap off the right edge of the row. The vertical edge is
-- derived from the root frame's own captured anchor point -- the same value
-- DriveNative uses -- so the control sits level with the first row of icons.
--
-- The x offset is MEASURED, and that is the whole point of this section.
-- FOCUSED_RUNTIME_PROBE, UnrealRuntimeProbe group `aurarow`, 2026-09-10:
--
--   BuffFrame              1590..1640   50 wide, TOPRIGHT
--   TemporaryEnchantFrame  1604..1640   36 wide, TOPRIGHT +30
--   the two visible icons  1575..1640   BuffButton0 is 1610..1640
--   UnrealUIBuffAnchor     1560..1610   50 wide, mirrors BuffFrame's size
--
-- So the anchor's right edge is 30 units SHORT of the row's right edge, and an
-- arrow placed one gap off the anchor lands on top of BuffButton0 -- which is
-- exactly the reported symptom, and why changing the gap from 3 to 5 looked
-- like nothing had moved. Both containers' right edge measured exactly on the
-- last icon's right edge (1640), so the containers bound the row and no buff
-- button needs to be read to find it.
--
-- The 30 is not a constant here: it is the offset the client currently keeps
-- between the two containers, which DriveNative replays from its own capture,
-- and it goes to zero when there is no temporary enchant. So the overhang is
-- re-measured on the tick that already reads the root frame's width, and the
-- offset is only written when it actually changes.
--
-- This is a bounded numeric read of the two frames this module already manages
-- -- no native child is discovered, and nothing native is retained as a
-- relative frame (.claude/rules/unreal-ui.md, native widget ownership
-- boundaries). The arrow stays anchored to the addon-owned anchor.
-- ---------------------------------------------------------------------------
local function RightEdge(frame)
  if not frame then return nil end
  local ok, value = pcall(frame.GetRight, frame)
  if not ok then return nil end
  return tonumber(value)
end

-- How far the native row reaches past our own anchor's right edge, never less
-- than zero: a row that sits inside the anchor still gets the plain gap.
local function RowOverhang()
  local base = RightEdge(anchor)
  if not base then return 0 end

  local furthest = base
  local i
  for i = 1, table.getn(managed) do
    local right = RightEdge(managed[i])
    if right and right > furthest then furthest = right end
  end
  return furthest - base
end

local function TogglePoints()
  local vertical = ""
  if string.find(rootPoint, "TOP") then
    vertical = "TOP"
  elseif string.find(rootPoint, "BOTTOM") then
    vertical = "BOTTOM"
  end
  -- "" gives the plain LEFT/RIGHT pair, which is what a centre-anchored row
  -- wants anyway.
  return vertical .. "LEFT", vertical .. "RIGHT"
end

local function PlaceToggle()
  if not toggle or not anchor then return end

  -- Frozen while the row is folded away: hidden frames keep their rect on this
  -- client, but a build that dropped it would otherwise snap the arrow 30
  -- units left out from under the cursor that just clicked it.
  if U.GetNativeAuraCollapsed() and toggleOffsetX then return end

  local offsetX = RowOverhang() + TOGGLE_GAP
  if toggleOffsetX and math.abs(offsetX - toggleOffsetX) <= DRIFT_EPSILON then
    return
  end
  toggleOffsetX = offsetX

  local own, edge = TogglePoints()
  pcall(function()
    toggle:ClearAllPoints()
    toggle:SetPoint(own, anchor, edge, offsetX, 0)
  end)
end

-- Assigns the forward-declared local above.
function UpdateToggle()
  if not toggle then return end

  PlaceToggle()

  -- Hidden with the whole display, hidden by an advanced edit-mode row, and
  -- hidden while the UI is unlocked: the mover handle owns the anchor then,
  -- and a live toggle beside it would compete for the same drag.
  local visible = U.GetNativeAuraFrameShown() and editShown ~= false
                  and not U.IsUnlocked()
  if visible then toggle:Show() else toggle:Hide() end

  -- Pointing the way the icons go: right while they are out and can be pushed
  -- away, left while they are folded up and can be pulled back.
  toggle.SetDirection(U.GetNativeAuraCollapsed() and "left" or "right")
end

local function CreateToggle()
  if not anchor then return end

  toggle = U.CreateArrowToggle(anchor, {
    name = "UnrealUIBuffToggle",
    height = NATIVE_ICON_SIZE,
    onClick = function()
      U.SetNativeAuraCollapsed(not U.GetNativeAuraCollapsed())
    end,
  })

  -- Above the anchor it is parented to. The anchor carries no art and the
  -- arrow sits outside the icon block, so nothing of the client's is covered.
  local ok, level = pcall(anchor.GetFrameLevel, anchor)
  if ok and tonumber(level) then
    pcall(toggle.SetFrameLevel, toggle, level + 2)
  end

  UpdateToggle()
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
local function CreateAnchor()
  anchor = CreateFrame("Frame", "UnrealUIBuffAnchor", UIParent)

  -- Carries a mover handle and the edit-mode placeholders, nothing else: no
  -- backdrop, no mouse, no strata of its own. It must never sit in front of
  -- the icons it is placing.
  SizeAnchor(anchor, "buffs")
  FollowNative()
  -- The row has no readable rect yet: hold the corner on the screen's until the
  -- next Apply can read it, rather than leave the handle unanchored.
  if not anchor.uuiFollowX then
    local corner = auraLayout.Corner(rootPoint)
    anchor:SetPoint(corner, UIParent, corner, 0, 0)
  end
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
  -- WORKING_SOURCE in UnrealPfUI; the one-second updater remains the guarantee.
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", function(event, unit)
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
  -- Named for the buffs alone once the debuff row has a handle of its own.
  U.RegisterMover("buffs", anchor, {
    label = debuffs.Root() and U.L("MOVER_LABEL_BUFF_ROW") or
            U.L("MOVER_LABEL_BUFFS"),
    visible = function() return U.GetNativeAuraFrameShown() end,
    setEditShown = SetEditShown,
  })
  U.OnPositionReset(function() return RestoreNativeAnchors() end)

  debuffs.Setup()
  CreateToggle()

  -- Each kind is also its row's mover id.
  preview.Register("buffs", anchor)
  if debuffs.anchor then preview.Register(debuffs.MOVER_ID, debuffs.anchor) end
  -- After debuffs.Setup, which reads the debuff button's stock anchor.
  auraLayout.Apply("buffs")
  auraLayout.Apply("debuffs")
  sizePanel.Register()

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

-- Written by the arrow. Persisted, so a folded row stays folded across a
-- reload; Apply does the rest, hiding the frames and turning the glyph round.
function U.SetNativeAuraCollapsed(value)
  Config().collapsed = value and true or false
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
    collapsed = U.GetNativeAuraCollapsed(),
    toggle = toggle and true or false,
    toggleOffsetX = toggleOffsetX,
    rowOverhang = anchor and RowOverhang() or nil,
    nativeAnchorCaptured = (root and captured[root]) and true or false,
    -- Whether BuffButton16 resolved, and what the debuff handle is doing.
    debuffAnchor = debuffs.anchor and true or false,
    debuffPoint = debuffs.capture and debuffs.point or nil,
    debuffPlaced = debuffs.StoredPosition() and true or false,
    debuffDriving = debuffs.driving,
    buffIconSize = auraLayout.IconSize("buffs"),
    debuffIconSize = auraLayout.IconSize("debuffs"),
  }
end
