-- unrealUI :: modules/actionbar.lua
--
-- Up to ten action bars. Modern uses UnrealUI's flat button treatment; Classic
-- copies the live client's own action-button faces onto the same UnrealUI
-- buttons. Layout, paging, movers, bindings, cooldowns and interaction remain
-- owned by this module in both themes.
--
-- Only the look and the call shapes are taken from pfUI. None of its bar
-- architecture is reproduced: no config schema, no secure/TBC state driver, no
-- hoverbind, no reagent counter, no animations, no stance/pet bars. A page
-- owned by this character's class/stance is reached only by paging Bar 1 and
-- is omitted from the independent static bars.
--
-- Compatibility notes that shaped this file:
--
--   * api.json / actionbars.*: HasAction, GetActionTexture, GetActionCount,
--     GetActionText, GetActionCooldown and GetBindingKey are
--     BEHAVIOR_PARTIALLY_TESTED here and returned Vanilla-shaped values for
--     slot 1. Everything else this file calls has no compact record, so it is
--     resolved through U.G, pcall'd, and its result coerced.
--   * knowledge.json / actionbars.binding_text_engine_key_names: GetBindingKey
--     can hand back engine key identifiers -- the recorded probe read
--     "AMPERSAND" for ACTIONBUTTON1 -- so labels are normalised before display.
--   * knowledge.json / actionbars.dragdrop_use_runtime_unverified
--     (INCONCLUSIVE): UseAction / PickupAction / PlaceAction are WORKING_SOURCE
--     evidence from UnrealPfUI, not runtime-verified. Their call shapes here
--     match that working implementation rather than a fresh guess.
--   * knowledge.json / actionbars.native_stock_children_suppression: the stock
--     bar parents, every stock button and its visual children have to be
--     suppressed explicitly and re-applied; U.SuppressNativeFrame does exactly
--     that and owns the re-apply sweep.
--   * knowledge.json / scripts.child_onupdate_unreliable: no button owns an
--     OnUpdate. Refreshes run on the shared driver -- including the cooldown
--     countdown, which is why there is no per-button cooldown OnUpdate here
--     even though UnrealPfUI's own cooldown module uses one.
--   * knowledge.json / cooldown.model_swipe_not_rendered: the native
--     Model/CooldownFrameTemplate swipe draws nothing on this client, so no
--     button creates one. The countdown number, the red icon tint and the
--     hand-drawn global-cooldown wipe are the whole cooldown display.
--   * knowledge.json / actionbars.frame_cost_scales_with_regions: this
--     module's frame cost tracks how many texture regions exist, not how much
--     Lua runs over them, so per-button regions are created on demand.
--   * knowledge.json / rendering.parent_alpha_not_propagated: every child
--     region is shown and hidden explicitly, never via its parent.

local U = UnrealUI
local M = U.media

local AB = U.RegisterModule("actionbar")

-- ---------------------------------------------------------------------------
-- Layout model
--
-- Bar 1 is paged and may temporarily resolve to a class-owned stance page (see
-- ActivePage/SlotFor). That exact page must not also be exposed as a static
-- bar or editing a stance action necessarily edits the duplicate. Other pages
-- remain available; for a Rogue page 7 is reserved, leaving Bars 1-6 and 8-10.
--
-- Bars are numbered so the bindable ones sort first: bar 1 (paged) plus bars
-- 2-5 (the four native multibar commands, slots 25-72) are bindable; bar 6
-- (the main bar's page 2, slots 13-24) and bars 7-10 (the class/bonus pages)
-- have no binding command on this client and sort last.
-- ---------------------------------------------------------------------------
local BAR_COUNT = 10
local SLOTS_PER_BAR = 12

-- Measured on this client: Rogue Stealth uses bonus offset 1 / page 7. The
-- Warrior and Druid sets follow UnrealPfUI's working Vanilla path and the
-- client-standard bonus offsets; they remain WORKING_SOURCE until captured on
-- those classes. Unknown classes own no bonus page in the 1-10 range.
local CLASS_RESERVED_PAGES = {
  ROGUE   = { [7] = true },
  WARRIOR = { [7] = true, [8] = true, [9] = true },
  DRUID   = { [7] = true, [9] = true, [10] = true },
}

local CLASS_RESERVED_REASON = {
  ROGUE = "ABC_RESERVED_ROGUE",
  WARRIOR = "ABC_RESERVED_WARRIOR",
  DRUID = "ABC_RESERVED_DRUID",
}

local reservedPages = {}
local availableBars = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local playerClass

-- Slot base per bar (SlotFor adds 1..12 on top). Bar 1 is omitted: it is
-- paged and resolved dynamically in SlotFor instead of through this table.
local BAR_SLOT_BASE = {
  [2]  = 24,  -- MultiBarRight:         25-36
  [3]  = 36,  -- MultiBarLeft:          37-48
  [4]  = 48,  -- MultiBarBottomRight:   49-60
  [5]  = 60,  -- MultiBarBottomLeft:    61-72
  [6]  = 12,  -- page 2:                13-24
  [7]  = 72,  -- bonus/stance page 1:   73-84
  [8]  = 84,  -- bonus/stance page 2:   85-96
  [9]  = 96,  -- bonus/stance page 3:   97-108
  [10] = 108, -- bonus/stance page 4:   109-120
}

-- Keyed by the same names the settings tab and the config keys use, so one
-- string identifies a setting everywhere: bar3Size, LIMITS.Size, "Size".
local LIMITS = {
  Buttons = { min = 1,  max = 12, step = 1 },
  PerRow  = { min = 1,  max = 12, step = 1 },
  Size    = { min = 15, max = 60, step = 1 },
  -- Negative spacing is deliberate: pfUI allows it so neighbouring outlines can
  -- overlap into a single line, and the reference layout offers -3 as well.
  Spacing = { min = -3, max = 20, step = 1 },
}

-- Label toggles that apply to every bar at once. Kept flat and separate from
-- the per-bar keys so the General Options page has something real to drive.
local GLOBAL_DEFAULTS = {
  showKeybind  = true,
  showMacro    = true,
  showCount    = true,
  showCooldown = true,
  showGCD      = true,
}

-- Native binding names for the slot ranges the stock UI owns. Bar 6 and any
-- class-available pages among 7-10 have no dedicated binding command, so
-- UnrealUI neither displays nor installs a key route for those buttons.
local BINDING_PREFIX = {
  [1] = "ACTIONBUTTON",
  [2] = "MULTIACTIONBAR3BUTTON",
  [3] = "MULTIACTIONBAR4BUTTON",
  [4] = "MULTIACTIONBAR2BUTTON",
  [5] = "MULTIACTIONBAR1BUTTON",
}

-- The commands unrealUI declares for itself in Bindings.xml, covering the pages
-- the client has no command for: bar 6 (the main bar's page 2, slots 13-24) and
-- the class/bonus pages 7-10. They are ordinary client bindings once the file is
-- loaded -- GetBindingKey reads them, SetBinding writes them, SaveBindings
-- persists them, and they appear in the stock Key Bindings window -- so the rest
-- of this file treats them exactly like the native ones.
--
-- This is UnrealPfUI's path for the same case on this same client (its
-- Bindings.xml declares PFPAGING/PFSTANCE*). WORKING_SOURCE, not runtime
-- verified, which is what DeclaredBindingsRegistered is for: the client reads
-- Bindings.xml at start-up on its own, so an addon update that adds the file
-- has no effect until the client is restarted, and a client that ignores it
-- must degrade visibly rather than hand out keys that never fire.
local DECLARED_PREFIX = {
  [6]  = "UNREALUIBAR6BUTTON",
  [7]  = "UNREALUIBAR7BUTTON",
  [8]  = "UNREALUIBAR8BUTTON",
  [9]  = "UNREALUIBAR9BUTTON",
  [10] = "UNREALUIBAR10BUTTON",
}

local ICON_INSET = 2
local PRESS_FLASH_DURATION = 0.16
-- Classic installs the captured native highlight directly on the action button
-- so it cannot interfere with spell drops. Hover is intentionally brighter
-- than the persistent active-action glow, making the pointed-at slot obvious.
local CLASSIC_HIGHLIGHT_ALPHA = 0.55
local CLASSIC_ACTIVE_HIGHLIGHT_ALPHA = 0.35
local CLASSIC_HOVER_BRIGHTEN = 1
local CLASSIC_REST_DIM = 1
-- Draw layer of every Classic slot face. This client's action-button normal
-- texture is not clear through its centre the way stock Vanilla's is: painted
-- over an icon it reads as a dark wash, which is what made Classic action and
-- bag icons look dimmed. The face therefore sits below the icon -- under this
-- module's ARTWORK icon and under the container template's BORDER one -- so
-- only the rim outside the icon is left showing, which is where the stock
-- button's visible slot edge is anyway.
local CLASSIC_FACE_LAYER = "BACKGROUND"

local COLOR = {
  usable    = { 1.00, 1.00, 1.00, 1.00 },
  oom       = { 0.40, 0.40, 1.00, 1.00 },
  unusable  = { 0.35, 0.35, 0.35, 1.00 },
  outOfRange= { 1.00, 0.10, 0.10, 1.00 },
  cooldown  = { 1.00, 0.20, 0.20, 1.00 },
  keybind   = { 0.85, 0.85, 0.85, 1.00 },
  count     = { 1.00, 1.00, 1.00, 1.00 },
  macro     = { 0.70, 0.70, 0.70, 1.00 },
}

-- Cooldown countdown colours and unit thresholds. Both are pfUI-modern's own
-- cd defaults (appearance.cd lowcolor/normalcolor/minutecolor/hourcolor/
-- daycolor and the unit switch points in its GetColoredTimeString), which is
-- the visual baseline this module follows. Both now live centrally --
-- M.cooldownText and U.FormatTimeShort -- because modules/auras.lua draws the
-- same readout over its aura icons.
local CD_COLOR = M.cooldownText

-- A cooldown shorter than this is the global cooldown, and a 1.5s number on
-- every button on every cast is noise rather than information. 2 is pfUI's own
-- appearance.cd.threshold default; it also absorbs a GCD inflated by latency.
local GCD_THRESHOLD = 2

-- The countdown is re-read from the clock this often. Fast enough that the
-- tenths shown in the last five seconds actually count down.
local CD_TICK = 0.1

-- ---------------------------------------------------------------------------
-- Global cooldown readout
--
-- Two shapes, and the difference between them is measured rather than a
-- preference. The clock wipe is core/style.lua's hand-drawn radial: at a 30px
-- button that is 34 texture regions and, because the leading edge moves every
-- tick, about 13 texture width-writes per button on each of the 25 ticks a
-- second it runs at. With eleven filled slots that is roughly 3700 texture
-- writes a second for the whole 1.5s of every cast -- user-reported as a ~40fps
-- drop while casting, on top of a client where frame cost already tracks region
-- count (knowledge.json / actionbars.frame_cost_scales_with_regions).
--
-- The client's own cooldown frames draw the readout wherever they exist (see
-- the Native cooldown frames note below), which is bars 1-5. That is not a
-- choice a player makes any more: it is free, it is the client's own art, and
-- it also covers real spell cooldowns, so it is simply what this module uses.
--
-- Bars 6-10 have no native counterpart at all and still need to show a global
-- cooldown, so they fall back to a shade unrealUI draws itself: one full-height
-- dark panel over the icon, receding to the right as the lockout runs out. One
-- texture region and one SetWidth per button per tick.
--
-- M.color.cooldownWipe is deliberately the shared token rather than a new one:
-- it is already defined as the shade this addon lays over game content during a
-- cooldown, which is exactly what this is.
--
-- core/style.lua's hand-drawn radial wipe is no longer used here. It remains
-- the right primitive for modules/auras.lua, stancebar.lua and petbarcustom.lua,
-- where each icon shows a genuinely different progress and there is no native
-- frame to borrow.
local GCD_SHADE_COLOR = M.color.cooldownWipe

-- ---------------------------------------------------------------------------
-- Native cooldown frames ("native" style)
--
-- The client draws a proper radial cooldown on its own action buttons, and
-- knowledge.json / cooldown.native_model_borrowable_but_undrivable records what
-- can and cannot be done with that: an addon-CREATED Model never renders, a
-- borrowed native one does, and driving it from Lua gives a position that is
-- not reproducible. What was left untested there was leaving it entirely alone,
-- and CooldownBorrowProbe's client_driven run answered it -- reparent a native
-- cooldown onto an unrealUI button, show its stock button so the client's own
-- update path stays alive, touch nothing else, and the client draws and
-- advances it correctly. USER_CONFIRMED_INGAME 2026-09-01.
--
-- Two consequences shape this:
--
--   * It costs nothing per tick. The client animates it in C; unrealUI never
--     writes to it after the borrow. That makes it cheaper than the shade,
--     which is one SetWidth per button per tick.
--   * It covers only bars 1-5. Those are the five families the client owns --
--     unrealUI bar 1 is paged in step with the client's own ActionButton page,
--     and bars 2-5 sit on the four MultiBar families in BAR_SLOT_BASE order.
--     Bar 6 (page 2) and the class pages 7-10 have no native counterpart at
--     all, so they fall back to the shade and say so in the settings text.
--
-- It also brings back something the other two styles cannot: a swipe on real
-- spell cooldowns, not just the global one, because the client drives the frame
-- for every cooldown that slot has.
local NATIVE_CD_FAMILY = {
  [1] = "ActionButton",
  [2] = "MultiBarRightButton",
  [3] = "MultiBarLeftButton",
  [4] = "MultiBarBottomRightButton",
  [5] = "MultiBarBottomLeftButton",
}

-- Stock buttons this module has already shown. The client's cooldown update
-- runs off the stock button, so it has to stay shown; its own art does not come
-- back, because its parent (MainMenuBarArtFrame and friends) is still
-- suppressed -- measured as shown=true / visible=false in the same probe run.
local nativeStockShown = {}

-- ---------------------------------------------------------------------------
-- Work census
--
-- One table rather than one local per counter: this file is already carrying
-- ~150 top-level locals and the 200-slot chunk limit fails silently (see
-- CLAUDE.md / lua.top_level_local_limit_silent_file_failure).
--
-- These are counters, not timers -- this client has no intra-frame profiler
-- (debugprofilestop is a documented no-op), so "how many per-button operations
-- did each recurring loop run" is the attribution available. Read by
-- U.ActionBarStats and exported by core/perf.lua, whose per-phase frame mean
-- supplies the milliseconds these counts have to be divided into.
--
-- gcdVisits is the figure to watch when a bar is added: the GCD sweep is the
-- only recurring loop here that ticks at render cadence (0.04s), and each
-- visit runs a full radial-wipe redraw. The 2026-08-31 run showed it does not
-- scale with bar count at all -- it skips empty slots, so it touched ~11
-- buttons per tick at ten bars against ~5 at one -- which is what moved the
-- investigation off this module's Lua and onto how many regions exist
-- (knowledge.json / actionbars.frame_cost_scales_with_regions).
local work = {
  slotSweeps = 0, stateSweeps = 0, buttonVisits = 0,
  gcdSweeps = 0, gcdVisits = 0,
  cdSweeps = 0, cdVisits = 0,
}

local bars = {}         -- bar index -> { frame, buttons, mover }
local pressedButtons = {}
local cfg               -- module settings table (flat; see BuildDefaults)
local classColor = { 0.5, 0.5, 1.0 }
local bindingsDirty = false

-- The client exposes only five independent native action-button families while
-- UnrealUI can show ten independently arranged bars. Reusing the actual stock
-- buttons would therefore discard bars and their features. Classic instead
-- reads the native ActionButton1 texture objects before suppression and uses
-- their exact client texture paths and size ratios as the visual template for
-- every UnrealUI button, including bars that have no stock counterpart.
local classicAction = {
  active = false,
  ready = false,
}

function classicAction.Dimension(region, method)
  local fn = region and region[method]
  if type(fn) ~= "function" then return 0 end
  local ok, value = pcall(fn, region)
  if not ok then return 0 end
  return tonumber(value) or 0
end

function classicAction.TexturePath(region)
  if not region or type(region.GetTexture) ~= "function" then return nil end
  local ok, path = pcall(region.GetTexture, region)
  if not ok or type(path) ~= "string" or path == "" then return nil end
  return path
end

function classicAction.Face(source, getter, fallback)
  local region = nil
  local fn = source and source[getter]
  if type(fn) == "function" then
    local ok, value = pcall(fn, source)
    if ok then region = value end
  end
  if not region and fallback then region = U.G(fallback) end

  local path = classicAction.TexturePath(region)
  if not path then return nil end

  local sourceWidth = classicAction.Dimension(source, "GetWidth")
  local sourceHeight = classicAction.Dimension(source, "GetHeight")
  local width = classicAction.Dimension(region, "GetWidth")
  local height = classicAction.Dimension(region, "GetHeight")
  return {
    path = path,
    widthRatio = sourceWidth > 0 and width / sourceWidth or 1,
    heightRatio = sourceHeight > 0 and height / sourceHeight or 1,
  }
end

function classicAction.Capture()
  classicAction.active = type(U.ThemeStyleUsesNativeChrome) == "function" and
                         U.ThemeStyleUsesNativeChrome() or false
  classicAction.ready = false
  if not classicAction.active then return end

  local source = U.G("ActionButton1")
  if not source then
    U.Debug("Classic action-button template is unavailable")
    return
  end

  classicAction.normal = classicAction.Face(
    source, "GetNormalTexture", "ActionButton1NormalTexture")
  classicAction.pushed = classicAction.Face(
    source, "GetPushedTexture", nil)
  classicAction.highlight = classicAction.Face(
    source, "GetHighlightTexture", "ActionButton1HighlightTexture")

  local nativeIcon = U.G("ActionButton1Icon")
  local sourceWidth = classicAction.Dimension(source, "GetWidth")
  local sourceHeight = classicAction.Dimension(source, "GetHeight")
  local iconWidth = classicAction.Dimension(nativeIcon, "GetWidth")
  local iconHeight = classicAction.Dimension(nativeIcon, "GetHeight")
  classicAction.iconWidthRatio = sourceWidth > 0 and iconWidth / sourceWidth or nil
  classicAction.iconHeightRatio = sourceHeight > 0 and iconHeight / sourceHeight or nil
  classicAction.ready = classicAction.normal and true or false

  if not classicAction.ready then
    U.Debug("Classic action-button normal texture is unavailable")
  end
end


-- No additive option: this client ignores SetBlendMode("ADD")
-- (rendering.setblendmode_add_inert), so a face needing it has to be dimmed
-- with alpha by its caller instead.
function classicAction.CreateFace(parent, face, layer)
  if not face then return nil end
  local texture = parent:CreateTexture(nil, layer or "OVERLAY")
  if not pcall(texture.SetTexture, texture, face.path) then return nil end
  texture.uuiClassicFace = face
  texture.uuiClassicParent = parent
  return texture
end

function classicAction.SizeFace(texture, size)
  local face = texture and texture.uuiClassicFace
  if not face then return end
  pcall(texture.ClearAllPoints, texture)
  pcall(texture.SetPoint, texture, "CENTER", texture.uuiClassicParent,
        "CENTER", 0, 0)
  pcall(texture.SetWidth, texture, size * face.widthRatio)
  pcall(texture.SetHeight, texture, size * face.heightRatio)
end

-- Shared by Classic surfaces that need the exact same live action-button rim.
-- The face is still captured and owned here; consumers only ask this module to
-- apply or resize it, so the action bar and bag slots cannot drift apart.
function U.StyleClassicActionButtonBorder(button, size, layer)
  if not classicAction.ready or not button then return nil end

  local texture = button.uuiClassicActionBorder
  if not texture then
    texture = classicAction.CreateFace(
      button, classicAction.normal, layer or CLASSIC_FACE_LAYER)
    button.uuiClassicActionBorder = texture
  end
  if not texture then return nil end

  U.SetBackdropShown(button, false)
  classicAction.SizeFace(
    texture, tonumber(size) or classicAction.Dimension(button, "GetWidth"))
  return texture
end

-- Hover and active-action glow are handed to the client's own highlight slot
-- rather than rebuilt as regions of ours, so the client keeps ownership of the
-- mouseover show/hide and the sizing exactly as it has them for a stock action
-- button.
--
-- The stock look cannot be reproduced faithfully, because this client ignores
-- SetBlendMode("ADD") -- see rendering.setblendmode_add_inert, established by a
-- four-way in-game A/B where an owned texture asking for ADD still drew as an
-- opaque white square. ButtonHilight-Square at full opacity is that square, so
-- it is dimmed with alpha instead: the same texture the client uses, composited
-- the only way this build allows.
function classicAction.ApplyNativeHighlight(button)
  local face = classicAction.highlight
  if not face or type(button.SetHighlightTexture) ~= "function" then return false end
  if not pcall(button.SetHighlightTexture, button, face.path) then return false end

  local ok, texture = pcall(button.GetHighlightTexture, button)
  if ok and texture then
    -- U.SetColor, not SetAlpha. Through SetAlpha this texture got darker as the
    -- value dropped -- white at 1.0, grey at 0.3, darker still at 0.22 -- which
    -- is a colour scale toward black, not transparency, and is why the hovered
    -- slot read darker than an unhovered one at every value tried. U.SetColor
    -- goes through SetVertexColor's alpha component, which is how this module's
    -- own press flash already draws a working translucent white fill.
    U.SetColor(texture, 1, 1, 1, CLASSIC_HIGHLIGHT_ALPHA)
    -- The stock template's highlight covers the button exactly, unlike the
    -- normal face, which overflows it; SizeButton therefore leaves this alone.
    pcall(texture.ClearAllPoints, texture)
    pcall(texture.SetAllPoints, texture, button)
  end
  return true
end

function classicAction.SetHighlightAlpha(button, alpha)
  local ok, texture = pcall(button.GetHighlightTexture, button)
  if ok and texture then U.SetColor(texture, 1, 1, 1, alpha) end
end

-- Hover and held state for any Classic slot. The outline is never tinted in
-- Classic -- ApplyButtonBorder returns early for one -- so the client's own
-- highlight carries both, hover deliberately brighter than a held state.
-- Shared, because modules/stancebar.lua needs the same two states on buttons
-- that own no action and therefore have no uuiHover/uuiActive contract with
-- this module.
function U.SetClassicActionButtonHighlight(button, hover, active)
  if not button or not button.uuiClassicHighlight then return end
  if hover or active then
    classicAction.SetHighlightAlpha(
      button, hover and CLASSIC_HIGHLIGHT_ALPHA or
              CLASSIC_ACTIVE_HIGHLIGHT_ALPHA)
    pcall(button.LockHighlight, button)
  else
    pcall(button.UnlockHighlight, button)
  end
end

function classicAction.RefreshHighlight(button)
  if not button then return end
  U.SetClassicActionButtonHighlight(button, button.uuiHover, button.uuiActive)
end

-- ---------------------------------------------------------------------------
-- Classic chrome for icon buttons that are not action slots
--
-- modules/stancebar.lua draws a spell icon in an action-button-shaped slot
-- while owning no action, so it needs this module's captured client face, its
-- icon geometry and its highlight without any of the slot, drag, paging or
-- keybind machinery. The capture stays here -- one live read of ActionButton1
-- before the suppression pass -- so every Classic surface borrowing the look
-- cannot drift away from the bars. modules/actionbar.lua is enabled ahead of
-- modules/stancebar.lua (TOC order), so the faces exist by the time the stance
-- bar builds its buttons.
-- ---------------------------------------------------------------------------
function U.ClassicActionChromeReady()
  return classicAction.ready and true or false
end

-- One-time styling for such a button. Returns false when the client faces were
-- unavailable, so the caller can keep its own flat rendering rather than draw a
-- half-Classic button.
function U.StyleClassicActionIconButton(button, icon, size)
  if not classicAction.ready or not button then return false end
  size = tonumber(size) or classicAction.Dimension(button, "GetWidth")

  -- Uncropped and centred at the client's own icon-to-button ratio, the way
  -- classicAction.SizeButton does it for an action slot: the normal face
  -- supplies the ornamental edge around the icon and overflows the button on
  -- every side, which is what makes the slot read as a stock one.
  if icon then
    pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
    if classicAction.iconWidthRatio and classicAction.iconHeightRatio then
      pcall(icon.ClearAllPoints, icon)
      pcall(icon.SetPoint, icon, "CENTER", button, "CENTER", 0, 0)
      pcall(icon.SetWidth, icon, size * classicAction.iconWidthRatio)
      pcall(icon.SetHeight, icon, size * classicAction.iconHeightRatio)
    end
  end

  button.uuiClassicNormal = U.StyleClassicActionButtonBorder(button, size)
  button.uuiClassicHighlight = classicAction.ApplyNativeHighlight(button)
  return button.uuiClassicNormal and true or false
end

function classicAction.StyleButton(button, textLayer)
  if not classicAction.ready then return end
  button.uuiClassic = true

  -- Native action icons are not cropped; the client normal texture supplies
  -- the ornamental slot edge around the icon, which overflows the button on
  -- every side and so stays visible with the icon drawn on top of it.
  pcall(button.uuiIcon.SetTexCoord, button.uuiIcon, 0, 1, 0, 1)
  U.SetBackdropShown(button, false)

  button.uuiClassicNormal = U.StyleClassicActionButtonBorder(
    button, classicAction.Dimension(button, "GetWidth"))
  -- The action button itself must remain the sole mouse and drop target. A
  -- ContainerFrameItemButtonTemplate child can intercept spell drops on this
  -- client even when asked to be mouse-transparent, so Classic installs the
  -- captured native highlight directly on the owning action button.
  button.uuiClassicHighlight = classicAction.ApplyNativeHighlight(button)

  -- The press flash keeps its owned region, because it is driven by keybind
  -- timing rather than by a real mouse press (see ShowButtonPress). It does not
  -- fall back to the highlight face: that one is only legible additively
  -- (rendering.setblendmode_add_inert), so without a native pushed face the
  -- flash stays the modern translucent fill rather than becoming a white square.
  local pushedFace = classicAction.pushed
  if pushedFace and button.uuiPressed then
    pcall(button.uuiPressed.SetTexture, button.uuiPressed,
          pushedFace.path)
    U.SetColor(button.uuiPressed, 1, 1, 1, 1)
    button.uuiPressed.uuiClassicFace = pushedFace
    button.uuiPressed.uuiClassicParent = textLayer
  end
end

function classicAction.SizeButton(button, size)
  if not button.uuiClassic then return end
  if classicAction.iconWidthRatio and classicAction.iconHeightRatio then
    pcall(button.uuiIcon.ClearAllPoints, button.uuiIcon)
    pcall(button.uuiIcon.SetPoint, button.uuiIcon, "CENTER", button,
          "CENTER", 0, 0)
    pcall(button.uuiIcon.SetWidth, button.uuiIcon,
          size * classicAction.iconWidthRatio)
    pcall(button.uuiIcon.SetHeight, button.uuiIcon,
          size * classicAction.iconHeightRatio)
  end
  classicAction.SizeFace(button.uuiClassicNormal, size)
  classicAction.SizeFace(button.uuiPressed, size)
end

-- The global cooldown currently running, shared by every button. See NoteGCD.
local gcdStart, gcdDuration, gcdProgress
local gcdTimerRunning = false
local RefreshGCDSweep
local cooldownTimerRunning = false
local RefreshCooldownTimers

-- ---------------------------------------------------------------------------
-- Config
--
-- core/config.lua only persists scalars inside a module's settings table
-- (SanitizeModules drops nested tables), so per-bar settings are flat keys:
-- bar3Enabled, bar3Buttons, bar3PerRow, bar3Size, bar3Spacing.
-- ---------------------------------------------------------------------------
local function Key(bar, name)
  return "bar" .. bar .. name
end

local function BuildDefaults()
  local defaults, i = {}, nil

  local key, value
  for key, value in pairs(GLOBAL_DEFAULTS) do defaults[key] = value end

  for i = 1, BAR_COUNT do
    -- Only the main bar is on by default. The rest are one click away in the
    -- settings panel; enabling ten bars nobody asked for is not a default.
    defaults[Key(i, "Enabled")] = (i == 1)
    defaults[Key(i, "HideBackground")] = false
    defaults[Key(i, "Buttons")] = 12
    defaults[Key(i, "PerRow")]  = 12
    defaults[Key(i, "Size")]    = 30
    defaults[Key(i, "Spacing")] = 2
  end
  return defaults
end

local function Clamp(name, value)
  local limit = LIMITS[name]
  value = tonumber(value)
  if not limit then return value end
  if not value then return limit.min end
  value = U.Round(value)
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return value
end

local function Get(bar, name)
  if not cfg then return nil end
  return cfg[Key(bar, name)]
end

local function Number(bar, name)
  return Clamp(name, Get(bar, name))
end

local function IsEnabled(bar)
  if reservedPages[bar] then return false end
  return Get(bar, "Enabled") and true or false
end

local function HidesBackground(bar)
  return Get(bar, "HideBackground") and true or false
end

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Everything below is resolved by name and pcall'd. A missing call degrades one
-- part of a button rather than erroring out of the refresh loop.
-- ---------------------------------------------------------------------------
-- The name -> function lookup is memoized, for the same reason
-- knowledge.json / compat.native_suppression_pcall_burst_stutter memoized
-- core/compat.lua's and modules/unitframes.lua's: U.G is itself a pcall, so an
-- unmemoized resolve doubled the pcall count of every read. Round 1 of that fix
-- covered unit frames and the suppression sweep and left this file -- the
-- addon's largest recurring loop by a wide margin -- resolving every name
-- again on every button on every tick.
--
-- Every name reached through Call/Has is a stock client query or action global
-- (see the list at the call sites): none of them is replaced by this addon.
-- The two globals unrealUI *does* post-hook, ActionButtonDown/Up, are read
-- through U.G directly further down and deliberately stay uncached.
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

local function Call(name, a, b, c)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3
end

local function Has(name)
  return ResolveApiFn(name) and true or false
end

local function ConfigureBarOwnership()
  local _, class = Call("UnitClass", "player")
  playerClass = class
  local classPages = CLASS_RESERVED_PAGES[class] or {}
  reservedPages = {}
  availableBars = {}

  local bar
  for bar = 1, BAR_COUNT do
    if classPages[bar] then
      reservedPages[bar] = true
    else
      table.insert(availableBars, bar)
    end
  end
end

-- Bar 1 follows the client's page and bonus bar. GetActiveBar in UnrealPfUI's
-- working implementation reads exactly these three globals.
local function ActivePage()
  local page = tonumber(U.G("CURRENT_ACTIONBAR_PAGE")) or 1
  local pages = tonumber(U.G("NUM_ACTIONBAR_PAGES")) or 6
  local offset = tonumber(Call("GetBonusBarOffset")) or 0

  if page == 1 and offset ~= 0 then return pages + offset end
  if page < 1 then return 1 end
  return page
end

local function SlotFor(bar, index)
  if bar == 1 then
    return (ActivePage() - 1) * SLOTS_PER_BAR + index
  end
  return (BAR_SLOT_BASE[bar] or (bar - 1) * SLOTS_PER_BAR) + index
end

-- knowledge.json / actionbars.binding_text_engine_key_names: this client can
-- return engine key identifiers from GetBindingKey. The subset below is the one
-- UnrealPfUI normalises; anything unknown is passed through and truncated so a
-- long identifier cannot sprawl across the neighbouring button.
local KEY_LABEL = {
  ["AMPERSAND"] = "&", ["ASTERISK"] = "*", ["CARET"] = "^", ["COLON"] = ":",
  ["DOLLAR"] = "$", ["EXCLAMATION"] = "!", ["EXCLAMATIONMARK"] = "!",
  ["LEFTPARENTHESIS"] = "(", ["RIGHTPARENTHESIS"] = ")",
  ["QUOTE"] = "'", ["APOSTROPHE"] = "'", ["QUOTEDBL"] = "\"",
  ["MINUS"] = "-", ["HYPHEN"] = "-", ["NEGATIVE"] = "-", ["SUBTRACT"] = "-",
  ["UNDERSCORE"] = "_",
  ["PLUS"] = "+", ["EQUALS"] = "=", ["GRAVE"] = "`", ["TILDE"] = "~",
  ["COMMA"] = ",", ["PERIOD"] = ".", ["SLASH"] = "/",
  ["SEMICOLON"] = ";", ["LEFTBRACKET"] = "[", ["RIGHTBRACKET"] = "]",
  ["SPACE"] = "Sp", ["BACKSPACE"] = "Bk", ["DELETE"] = "Del",
  ["INSERT"] = "Ins", ["PAGEUP"] = "PgU", ["PAGEDOWN"] = "PgD",
  ["MOUSEWHEELUP"] = "MWU", ["MOUSEWHEELDOWN"] = "MWD",
  ["BUTTON3"] = "M3", ["BUTTON4"] = "M4", ["BUTTON5"] = "M5",
}

-- French AZERTY reports the physical 1..0 row as its unshifted symbols. Keep
-- the binding itself untouched, but render those ten keys as the digits printed
-- on the same physical keys. Both raw characters and observed/likely engine
-- identifiers are accepted because the client can expose either form.
local AZERTY_NUMBER_LABEL = {
  ["&"] = "1", ["AMPERSAND"] = "1",
  ["é"] = "2", ["E_ACUTE"] = "2", ["EACUTE"] = "2", ["E_ACCENTAIGU"] = "2",
  -- knowledge.json / actionbars.quote_identifier_swapped: on this client
  -- "QUOTE" is the engine name for the double-quote key (button 3), not the
  -- apostrophe -- the raw apostrophe key comes back as the literal character.
  ["\""] = "3", ["QUOTEDBL"] = "3", ["DOUBLEQUOTE"] = "3", ["QUOTE"] = "3",
  ["'"] = "4", ["APOSTROPHE"] = "4",
  ["("] = "5", ["LEFTPARENTHESIS"] = "5", ["LEFTPARENTHESES"] = "5",
  ["LEFTPARANTHESES"] = "5",
  ["-"] = "6", ["MINUS"] = "6", ["HYPHEN"] = "6", ["NEGATIVE"] = "6",
  ["è"] = "7", ["E_GRAVE"] = "7", ["EGRAVE"] = "7", ["E_ACCENTGRAVE"] = "7",
  ["_"] = "8", ["UNDERSCORE"] = "8", ["§"] = "8", ["SECTION"] = "8",
  ["ç"] = "9", ["C_CEDILLA"] = "9", ["CCEDILLA"] = "9", ["C_CEDILLE"] = "9",
  ["à"] = "0", ["A_GRAVE"] = "0", ["AGRAVE"] = "0", ["A_ACCENTGRAVE"] = "0",
}

-- The client stores AZERTY's main minus key under an engine identifier rather
-- than the printed symbol. This is display-only: the original binding remains
-- intact, including any modifier information the client needs to execute it.
local AZERTY_BINDING_LABEL = {
  ["SHIFT-LEFTCOMMAND"] = "-",
}

-- `full` keeps the normalised key readable at its natural length. The corner
-- label on a 15px button cannot show more than four characters, but the
-- quick-binding readout in the middle of a slot and its tooltip can.
local function CompactBinding(binding, full)
  if type(binding) ~= "string" or binding == "" then return "" end

  local direct = AZERTY_BINDING_LABEL[binding]
  if direct then return direct end

  local text = binding
  local _, _, modifiers, key = string.find(text, "^(.*%-)([^%-]+)$")
  if key and (AZERTY_NUMBER_LABEL[key] or KEY_LABEL[key]) then
    text = modifiers .. (AZERTY_NUMBER_LABEL[key] or KEY_LABEL[key])
  else
    text = AZERTY_NUMBER_LABEL[text] or KEY_LABEL[text] or text
  end

  text = string.gsub(text, "CTRL%-", "C-")
  text = string.gsub(text, "SHIFT%-", "S-")
  text = string.gsub(text, "ALT%-", "A-")

  if not full and string.len(text) > 4 then text = string.sub(text, 1, 4) end
  return text
end

-- ---------------------------------------------------------------------------
-- Bars with no key route
--
-- Bar 6 (the main bar's page 2) and the class pages 7-10 are real action pages
-- that this client gives no binding command: ACTIONBUTTON follows whichever
-- page bar 1 shows and the four MULTIACTIONBAR commands cover slots 25-72 only.
-- Three routes were tried and all three are closed on this client, each
-- confirmed in game on 2026-08-19:
--
--   * SetOverrideBindingClick -- absent on this build (/uui check).
--   * Bindings.xml declarations -- unrealUI's 60 commands were absent from a
--     225-entry binding table (/uui bindscan). The file is still shipped and
--     BindingPrefix picks the commands up automatically if a client ever
--     registers them, but nothing here depends on that.
--   * An addon-owned key dispatcher on a permanent keyboard Frame --
--     knowledge.json / scripts.keyboard_frame_captures_all_input: such a frame
--     takes the entire keyboard away from the client, killing movement and even
--     Enter-to-chat. Unusable at any price.
--
-- So these bars carry no key. They stay visible and editable by mouse, and the
-- quick-binding mode shows them as unbindable rather than pretending.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Declared binding commands
--
-- Bindings.xml is read by the client at start-up, never by the .toc and never
-- on /reload, so its commands cannot be assumed to exist. GetNumBindings /
-- GetBinding enumerate what the client actually registered, which is a direct
-- answer rather than an inference from an empty GetBindingKey (unbound and
-- unknown look identical there).
--
-- The answer is cached once the enumeration returns anything at all; a zero
-- count means it was asked too early, not that the commands are missing.
-- ---------------------------------------------------------------------------
local declaredRegistered
local firstDeclaredCommand = "UNREALUIBAR2BUTTON1"

local function DeclaredBindingsRegistered()
  if declaredRegistered ~= nil then return declaredRegistered end

  -- With no way to enumerate, trust the shipped declaration rather than hide a
  -- bar that probably works: a command the client never registered still fails
  -- visibly at SetBinding, whereas a false negative here would remove the only
  -- key route those bars have.
  if not Has("GetNumBindings") or not Has("GetBinding") then
    declaredRegistered = true
    return true
  end

  local count = tonumber(Call("GetNumBindings")) or 0
  if count < 1 then return false end

  local found, i = false, nil
  for i = 1, count do
    local command = Call("GetBinding", i)
    if command == firstDeclaredCommand then
      found = true
      break
    end
  end

  declaredRegistered = found
  return found
end

-- The binding command for a slot, native or unrealUI-declared. nil means this
-- slot has no key route at all, which on this client can only happen when the
-- declared commands are not registered.
local function BindingPrefix(bar)
  local prefix = BINDING_PREFIX[bar]
  if prefix then return prefix end

  prefix = DECLARED_PREFIX[bar]
  if prefix and DeclaredBindingsRegistered() then return prefix end
  return nil
end

-- modules/quickbind.lua takes the slot keys off the client while its mode is
-- open, so the client has nothing to report until it closes. U.SlotBindingKey
-- answers with what the player has staged in that window and with the client's
-- own key at every other time.
--
-- Deliberately uncached. A label cache was built here and measured on
-- 2026-08-31: it removed the string work but moved nothing. Across four
-- /uui perf bars runs, including one from a cold client start, the slot
-- sweep's allocation went 26.3 -> 25.0 KB per fire and the per-bar frame cost
-- did not change at all (0.463 / 0.467 / 0.441 normalised to each run's own
-- control, a spread wider than the effect). The sweep's allocation is the ~360
-- protected client calls it makes over 120 buttons, not these strings. Caching
-- them bought about 1KB/s and cost an invalidation contract plus a staleness
-- window on a client whose UPDATE_BINDINGS is accepted but never observed, so
-- it was reverted. See knowledge.json /
-- actionbars.frame_cost_scales_with_regions.
local function BindingFor(bar, index)
  local prefix = BindingPrefix(bar)
  if not prefix then return "" end

  local command = prefix .. index
  if type(U.SlotBindingKey) == "function" then
    return CompactBinding(U.SlotBindingKey(command))
  end
  return CompactBinding(Call("GetBindingKey", command))
end

-- Make the executable key route match the label route exactly. Suppressing the
-- stock buttons only hides them; it does not remove their native binding
-- commands. Each rebuild first clears this addon's old overrides, then installs
-- only the keys currently returned for that exact button command. A removed or
-- unassigned key therefore cannot remain attached to a stale UnrealUI slot.
--
-- SetOverrideBindingClick has no compact runtime record, so this mirrors the
-- narrow working UnrealPfUI path. The corrected sequential slot table remains a
-- safe native-binding fallback if either override call is unavailable/rejected.
local function ApplyOverrideBindings()
  local clear = U.G("ClearOverrideBindings")
  local bind = U.G("SetOverrideBindingClick")
  local bar, index

  -- Never create overrides that cannot later be cleared. With either half of
  -- the API absent, the corrected native slot mapping is the complete fallback.
  if type(clear) ~= "function" or type(bind) ~= "function" then
    bindingsDirty = false
    return false
  end

  local clean = true

  for bar = 1, BAR_COUNT do
    local entry = bars[bar]
    if entry then
      for index = 1, table.getn(entry.buttons) do
        local button = entry.buttons[index]
        local cleared = pcall(clear, button)

        local prefix = BindingPrefix(bar)
        if not cleared then
          -- Protected binding calls may be rejected during combat. Do not layer
          -- new keys over an override set that could not first be made clean.
          clean = false
        elseif prefix then
          local key1, key2 = Call("GetBindingKey", prefix .. index)
          if type(key1) == "string" and key1 ~= "" then
            if not pcall(bind, button, false, key1, button.uuiName, "LeftButton") then
              clean = false
            end
          end
          if type(key2) == "string" and key2 ~= "" and key2 ~= key1 then
            if not pcall(bind, button, false, key2, button.uuiName, "LeftButton") then
              clean = false
            end
          end
        end
      end
    end
  end

  bindingsDirty = not clean
  return clean
end

-- ---------------------------------------------------------------------------
-- Cursor state
--
-- ACTIONBAR_SHOWGRID / ACTIONBAR_HIDEGRID have no compact record here, so the
-- flag they maintain is only an accelerator: CursorHasItem / CursorHasSpell are
-- asked as well, and a click falls back to using the slot when neither answers.
-- ---------------------------------------------------------------------------
local gridActive = false

local function CursorHoldsAction()
  if gridActive then return true end
  if Call("CursorHasItem") then return true end
  if Call("CursorHasSpell") then return true end
  if Call("CursorHasMacro") then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
local function ShowRegion(region, show)
  if not region then return end
  if show then region:Show() else region:Hide() end
end

local function ButtonSlot(button)
  return SlotFor(button.uuiBar, button.uuiIndex)
end

-- The icon's colour is its state tint (COLOR.*) scaled by the classic hover
-- brighten. Every writer goes through here for two reasons: a hover applied
-- directly to the icon would be stomped within a second by the slot sweep's
-- unconditional white write, and button.uuiTint has to keep caching the pure
-- state colour, because UpdateUsable compares against it to decide whether a
-- re-apply is needed at all.
--
-- Whether scaling above 1 actually brightens is a client question, not a
-- settled one: this client documents SetVertexColor components as 0-1, so the
-- scale may simply clamp. /uui abhl <alpha> <brighten> tunes both live to
-- answer it in game rather than across reloads.
local function ApplyIconTint(button)
  local color = button.uuiTint
  if not color then return end
  local scale = 1
  if button.uuiClassic then
    scale = button.uuiHover and CLASSIC_HOVER_BRIGHTEN or CLASSIC_REST_DIM
  end
  U.SetColor(button.uuiIcon, color[1] * scale, color[2] * scale,
             color[3] * scale, color[4])
end

local function ApplyButtonBorder(button)
  if button.uuiClassic then return end
  if button.uuiPressedShown then
    U.SetBorderColor(button, 1, 1, 1, 1)
  elseif button.uuiActive then
    U.SetBorderColor(button, classColor[1], classColor[2], classColor[3], 1)
  elseif button.uuiHover then
    U.SetBorderColor(button, 0.55, 0.55, 0.55, 1)
  else
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end
end

-- SetOverrideBindingClick targets the named UnrealUI button, so keyboard and
-- mouse activation both arrive through OnButtonClick. Flash that exact button;
-- this is also a visible confirmation that a key was routed to the right slot.
local RefreshPressedButtons

local function ShowButtonPress(button, held)
  if not button.uuiPressed then return end

  local now = tonumber(Call("GetTime"))
  button.uuiPressedUntil = now and (now + PRESS_FLASH_DURATION) or nil
  button.uuiPressedHeld = held and true or nil
  button.uuiPressedShown = true
  button.uuiPressed:Show()
  ApplyButtonBorder(button)

  if not button.uuiPressedTracked then
    button.uuiPressedTracked = true
    local wasEmpty = table.getn(pressedButtons) == 0
    table.insert(pressedButtons, button)
    -- The highlight needs render-frame cadence only while a key or mouse press
    -- is actually being timed. Keeping an empty callback registered all the
    -- time made every idle frame pay a protected call for no visual work.
    if wasEmpty then
      U.RegisterUpdate("actionbar.pressed", 0, RefreshPressedButtons)
    end
  end
end

local function ReleaseButtonPress(button)
  if button then button.uuiPressedHeld = nil end
end

RefreshPressedButtons = function()
  if table.getn(pressedButtons) == 0 then return end

  local now = tonumber(Call("GetTime"))
  local i
  for i = table.getn(pressedButtons), 1, -1 do
    local button = pressedButtons[i]
    if not button.uuiPressedHeld and
       (not now or not button.uuiPressedUntil or now >= button.uuiPressedUntil) then
      if button.uuiPressed then button.uuiPressed:Hide() end
      button.uuiPressedUntil = nil
      button.uuiPressedTracked = nil
      button.uuiPressedShown = nil
      ApplyButtonBorder(button)
      table.remove(pressedButtons, i)
    end
  end

  if table.getn(pressedButtons) == 0 then
    U.UnregisterUpdate("actionbar.pressed")
  end
end

-- Build 5875 uses the Vanilla binding-function path. Those commands call the
-- native ActionButtonDown/Up and MultiActionButtonDown/Up globals directly, so
-- a successful action does not imply that UnrealUI's OnClick ran. Post-hook the
-- native functions for visual state only; their original action execution and
-- return values remain untouched inside U.PostHookGlobal.
local NATIVE_BINDING_BAR = {
  MultiBarRight = 2,
  MultiBarLeft = 3,
  MultiBarBottomRight = 4,
  MultiBarBottomLeft = 5,
}
local nativeBindingHooksInstalled = false
local legacyMainBindingInstalled = false
local OnButtonClick

local function BoundButton(bar, index)
  bar = tonumber(bar)
  index = tonumber(index)
  if not bar or not index or index < 1 then return nil end

  local row = math.floor((index - 1) / SLOTS_PER_BAR)
  index = index - row * SLOTS_PER_BAR
  local entry = bars[bar]
  return entry and entry.buttons[index] or nil
end

local function HookNativeBindingHighlights()
  if nativeBindingHooksInstalled or type(U.PostHookGlobal) ~= "function" then return end

  local installed = false
  local mainHasUp = U.PostHookGlobal("ActionButtonUp", function(index)
    ReleaseButtonPress(BoundButton(1, index))
  end)
  local multiHasUp = U.PostHookGlobal("MultiActionButtonUp", function(name, index)
    ReleaseButtonPress(BoundButton(NATIVE_BINDING_BAR[name], index))
  end)
  if mainHasUp or multiHasUp then installed = true end

  if U.PostHookGlobal("ActionButtonDown", function(index)
    local button = BoundButton(1, index)
    if button then ShowButtonPress(button, mainHasUp) end
  end) then installed = true end
  if U.PostHookGlobal("MultiActionButtonDown", function(name, index)
    local button = BoundButton(NATIVE_BINDING_BAR[name], index)
    if button then ShowButtonPress(button, multiHasUp) end
  end) then installed = true end

  nativeBindingHooksInstalled = installed
end

-- Native text-entry frames whose visibility means typed keys are text, not an
-- action. This client has no keyboard-focus query API (no compat evidence for
-- GetCurrentKeyBoardFocus/HasFocus), so shown-ness is the only safe signal
-- available; unlike ChatFrameEditBox, the Auction and Mail text inputs stay
-- shown with their parent windows, so those windows suppress action-bar keys
-- for the whole session, not just while actively typing.
local TEXT_INPUT_OWNER_FRAMES = {
  "ChatFrameEditBox", "AuctionFrame", "MailFrame",
}

local function TextInputBlocksActionKey()
  local i
  for i = 1, #TEXT_INPUT_OWNER_FRAMES do
    local frame = U.G(TEXT_INPUT_OWNER_FRAMES[i])
    if frame and frame.IsShown then
      local ok, shown = pcall(frame.IsShown, frame)
      if ok and shown then return true end
    end
  end
  return false
end

-- Vanilla binding commands call the stock ActionButtonDown/Up globals instead
-- of clicking a named button. When the later override-binding API is absent,
-- letting those globals continue into the hidden stock ActionButton would bind
-- the key to that frame's fixed/native action rather than to UnrealUI's
-- currently paged main-bar button. Route only that legacy main-bar path to the
-- visible physical button: Down owns pressed state, Up clicks the button and
-- therefore resolves ButtonSlot at the current page/stance at activation time.
--
-- UnrealPfUI uses this route through build 11200; compact environment evidence
-- identifies this client as build 5875. API existence alone is not accepted as
-- proof of later override behavior, so the measured build wins when available.
-- An unknown/later build retains its native globals when both override calls
-- exist and uses the named-button route above.
local function InstallLegacyMainBindingRoute()
  if legacyMainBindingInstalled then return true end
  local _, build = Call("GetBuildInfo")
  build = tonumber(build)
  if (not build or build > 11200) and
     Has("ClearOverrideBindings") and Has("SetOverrideBindingClick") then
    return false
  end

  local originalDown = U.G("ActionButtonDown")
  local originalUp = U.G("ActionButtonUp")
  if type(originalDown) ~= "function" or type(originalUp) ~= "function" then
    return false
  end

  -- This build calls ActionButtonDown/Up off the raw physical key, not the
  -- exact modifier chord: a plain key bound to ACTIONBUTTON<index> still
  -- fires here while a modifier is held, even when that exact chord (e.g.
  -- ALT-C) is separately bound to an unrelated command (e.g. the character
  -- panel). Stock Blizzard's own ActionButtonDown/Up apparently absorbs this
  -- at the Lua layer before it reaches UseAction; replacing those globals
  -- drops that guard, so it is rebuilt here. Same modifier-prefix order as
  -- quickbind.lua's Prefix().
  local function StolenByModifiedChord(index)
    local prefix = ""
    if Call("IsAltKeyDown") then prefix = prefix .. "ALT-" end
    if Call("IsControlKeyDown") then prefix = prefix .. "CTRL-" end
    if Call("IsShiftKeyDown") then prefix = prefix .. "SHIFT-" end
    if prefix == "" then return false end

    local command = "ACTIONBUTTON" .. index
    local key1, key2 = Call("GetBindingKey", command)
    local keys = { key1, key2 }
    local i
    for i = 1, 2 do
      local key = keys[i]
      -- A bare key (no modifier already baked in) is the one this build's
      -- native dispatch will fire regardless of the held modifier.
      if type(key) == "string" and key ~= "" and not string.find(key, "-", 1, true) then
        local action = Call("GetBindingAction", prefix .. key)
        if type(action) == "string" and action ~= "" and action ~= command then
          return true
        end
      end
    end
    return false
  end

  -- The legacy binding globals are invoked even while a native text-entry
  -- frame owns keyboard input. Match the declared-binding path below: typed
  -- keys must never produce an action-bar press or activation.
  local down = function(index)
    if TextInputBlocksActionKey() then return end
    if StolenByModifiedChord(index) then return end
    local button = BoundButton(1, index)
    if button then ShowButtonPress(button, true) end
  end
  local up = function(index)
    if TextInputBlocksActionKey() then return end
    if StolenByModifiedChord(index) then return end
    local button = BoundButton(1, index)
    if button then OnButtonClick(button) end
  end

  U.SetG("ActionButtonDown", down)
  if U.G("ActionButtonDown") ~= down then return false end

  U.SetG("ActionButtonUp", up)
  if U.G("ActionButtonUp") ~= up then
    U.SetG("ActionButtonDown", originalDown)
    return false
  end

  legacyMainBindingInstalled = true
  return true
end

-- The body of every command in Bindings.xml. The client compiles a binding body
-- as its own chunk with no upvalues, so the entry point has to be a global; the
-- XML guards the call so a press before this runs is silently ignored rather
-- than throwing.
--
-- Routing through OnButtonClick rather than UseAction directly is what keeps a
-- declared key identical to a click on the same slot: cursor pickup, the press
-- flash and slot resolution all stay in one place.
local function InstallDeclaredBindingHandler()
  local handler = function(bar, index)
    bar, index = tonumber(bar), tonumber(index)
    if not bar or not index then return end

    -- UnrealPfUI's guard on the same path, extended past chat: while a native
    -- text-entry frame is open the key is text, not an action.
    if TextInputBlocksActionKey() then return end

    local entry = bars[bar]
    local button = entry and entry.buttons[index]
    if button and button.uuiShown then OnButtonClick(button) end
  end

  U.SetG("UnrealUIActionButton", handler)
  return U.G("UnrealUIActionButton") == handler
end

-- Readable text for the stock Key Bindings window. Without these the client
-- lists the raw command names.
local function InstallDeclaredBindingNames()
  local bar, prefix
  for bar, prefix in pairs(DECLARED_PREFIX) do
    U.SetG("BINDING_HEADER_UNREALUIBAR" .. bar, "unrealUI Bar " .. bar)
    local i
    for i = 1, SLOTS_PER_BAR do
      U.SetG("BINDING_NAME_" .. prefix .. i, "Bar " .. bar .. " Button " .. i)
    end
  end
end

OnButtonClick = function(button)
  ShowButtonPress(button, false)

  -- UnrealPfUI's working path: while the cursor carries an action, a click
  -- swaps it with the slot instead of using it.
  if CursorHoldsAction() then
    Call("PickupAction", ButtonSlot(button))
    return
  end
  Call("UseAction", ButtonSlot(button))
end

local function OnButtonDragStart(button)
  local locked = U.G("LOCK_ACTIONBAR")
  if locked == "1" or locked == 1 then
    local shift = Call("IsShiftKeyDown")
    if not shift or shift == 0 then return end
  end
  Call("PickupAction", ButtonSlot(button))
end

local function OnButtonReceiveDrag(button)
  Call("PlaceAction", ButtonSlot(button))
end

local function ShowTooltip(button)
  local tooltip = U.G("GameTooltip")
  if not tooltip or type(tooltip.SetAction) ~= "function" then return end
  pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
  if not pcall(tooltip.SetAction, tooltip, ButtonSlot(button)) then
    pcall(tooltip.Hide, tooltip)
  end
end

local function HideTooltip()
  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end
end

-- ---------------------------------------------------------------------------
-- Button labels, built on demand
--
-- Four of the regions a button carries are text: the keybind, the stack count,
-- the macro name and the cooldown countdown. Most action slots need none of
-- them at any given moment -- an empty slot needs none at all, and a slot
-- holding a plain spell with no key bound needs none either -- yet every button
-- used to create all four at construction time.
--
-- On this client that is the wrong default: frame cost tracks how many regions
-- exist rather than how much code touches them (knowledge.json /
-- actionbars.frame_cost_scales_with_regions), so a region that is created and
-- never shown is not free. Each is therefore created the first time it actually
-- has something to display, and a button that never displays one never has it.
--
-- Layout is shared with SizeButton rather than duplicated: a label built long
-- after its button was sized still has to land in the right corner at the right
-- font, and a resize still has to move whichever labels exist.
-- ---------------------------------------------------------------------------
local function LayoutButtonLabel(button, key)
  local label = button[key]
  local size = button.uuiSize
  if not label or not size then return end

  if key == "uuiCooldownText" then
    -- The countdown is the readout, not a corner label, so it scales off the
    -- button rather than off the small-label size. pfUI's dynamic cooldown font
    -- uses height * .64; half the button is the same idea, one step calmer.
    local cdSize = math.floor(size * 0.5)
    if cdSize < 10 then cdSize = 10 end
    if cdSize > 24 then cdSize = 24 end
    label:ClearAllPoints()
    label:SetPoint("CENTER", button.uuiCooldownLayer, "CENTER", 0, 0)
    U.SetFont(label, cdSize)
    return
  end

  -- Label sizes follow the button so a 60px button does not carry 9px text and
  -- a 15px one is not covered by it.
  local small = math.floor(size / 2.6)
  if small < 7 then small = 7 end
  if small > 14 then small = 14 end

  -- fonts.stretched_justification_ignored: each label is anchored to the one
  -- corner it belongs in rather than stretched across the button.
  label:ClearAllPoints()
  if key == "uuiKeybind" then
    label:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
  elseif key == "uuiCount" then
    label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  else
    label:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    label:SetWidth(size - 6)
  end
  U.SetFont(label, small)
end

local LABEL_COLOR = {
  uuiKeybind = COLOR.keybind,
  uuiCount = COLOR.count,
  uuiMacro = COLOR.macro,
}

-- Returns nil once and for good if this client refuses the fontstring, rather
-- than retrying the failed creation on every sweep.
local function EnsureButtonLabel(button, key)
  local existing = button[key]
  if existing ~= nil then return existing or nil end

  local label
  if key == "uuiCooldownText" then
    label = U.CreateLabel(button.uuiCooldownLayer, {
      size = M.fontSize.normal, color = CD_COLOR.normal,
      inherits = "GameFontNormal",
    })
  else
    label = U.CreateLabel(button, {
      size = M.fontSize.tiny, color = LABEL_COLOR[key],
      inherits = "GameFontNormalSmall",
    })
  end

  if not label then
    button[key] = false
    return nil
  end

  button[key] = label
  label:Hide()
  LayoutButtonLabel(button, key)
  return label
end

local function CreateButton(bar, index)
  local name = "UnrealUIActionBar" .. bar .. "Button" .. index
  local button = CreateFrame("Button", name, bars[bar].frame)

  button.uuiBar = bar
  button.uuiIndex = index
  button.uuiName = name

  U.CreateBackdrop(button, {})
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")
  pcall(button.RegisterForDrag, button, "LeftButton", "RightButton")

  local icon = button:CreateTexture(nil, "ARTWORK")
  -- The icon is inset so the outline stays visible, and trimmed the way pfUI
  -- trims it so the stock icon border does not show inside the button.
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  button.uuiIcon = icon

  -- No native cooldown swipe is created here.
  --
  -- knowledge.json / cooldown.model_swipe_not_rendered (BROKEN,
  -- RUNTIME_FAILURE_CONFIRMED): CreateFrame("Model", name, button,
  -- "CooldownFrameTemplate") driven by CooldownFrame_SetTimer is the Vanilla
  -- shape UnrealPfUI uses, and on this client it produces a frame that draws
  -- nothing. It was kept anyway on the chance the record was wrong about some
  -- slot or state; the /uui perf bars run of 2026-08-31 priced what that
  -- chance cost -- one Model frame per button, 120 of them across ten enabled
  -- bars, plus a protected CooldownFrame_SetTimer on each one five times a
  -- second -- against a frame time already rising 0.72ms per bar. A frame that
  -- has been confirmed to render nothing is not worth one render object per
  -- action slot.
  --
  -- The cooldown readout is therefore the numeric countdown (uuiCooldownText)
  -- and the red COLOR.cooldown icon tint, both of which were already carrying
  -- the whole display. The hand-drawn radial wipe in core/style.lua remains
  -- the global-cooldown feedback.

  -- The countdown sits on a raised child frame rather than the button's own
  -- OVERLAY layer -- the same raised-layer trick the unit frames use for bar
  -- labels, and what UnrealPfUI does for its cooldown text
  -- (modules/cooldown.lua parents it to the button at a higher level).
  -- The layer takes no mouse input, so clicks and drags still reach the button.
  local textLayer = CreateFrame("Frame", nil, button)
  pcall(textLayer.SetAllPoints, textLayer, button)
  local levelOk, level = pcall(button.GetFrameLevel, button)
  if levelOk and tonumber(level) then
    pcall(textLayer.SetFrameLevel, textLayer, level + 10)
  end
  button.uuiCooldownLayer = textLayer

  -- A raised translucent fill stays visible above the icon and the GCD wipe
  -- while leaving the key/count/macro labels readable. It is driven by the
  -- shared updater rather than an unreliable child-frame OnUpdate.
  local pressed = textLayer:CreateTexture(nil, "ARTWORK")
  pcall(pressed.SetAllPoints, pressed, textLayer)
  pcall(pressed.SetTexture, pressed, M.texture.plain)
  U.SetColor(pressed, 1, 1, 1, 0.28)
  pressed:Hide()
  button.uuiPressed = pressed

  classicAction.StyleButton(button, textLayer)

  -- scripts.handler_arguments_direct: handlers close over `button` instead of
  -- reading `this`, because the argument shape is not guaranteed here.
  button:SetScript("OnClick", function() OnButtonClick(button) end)
  button:SetScript("OnDragStart", function() OnButtonDragStart(button) end)
  button:SetScript("OnReceiveDrag", function() OnButtonReceiveDrag(button) end)
  -- Classic drives its native highlight explicitly; Modern continues to use
  -- the owned outline.
  button:SetScript("OnEnter", function()
    button.uuiHover = true
    classicAction.RefreshHighlight(button)
    ApplyIconTint(button)
    ApplyButtonBorder(button)
    ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    button.uuiHover = false
    classicAction.RefreshHighlight(button)
    ApplyIconTint(button)
    ApplyButtonBorder(button)
    HideTooltip()
  end)

  return button
end

-- Applies size-dependent geometry. Called on creation and whenever the bar's
-- button size changes.
local function SizeButton(button, size)
  button:SetWidth(size)
  button:SetHeight(size)
  -- Read back by the GCD bar, which is sized from the button rather than from
  -- its own geometry so it can be built long after this ran.
  button.uuiSize = size

  local icon = button.uuiIcon
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", ICON_INSET, -ICON_INSET)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)

  -- Whichever of the four exist; LayoutButtonLabel is a no-op for the rest.
  LayoutButtonLabel(button, "uuiKeybind")
  LayoutButtonLabel(button, "uuiCount")
  LayoutButtonLabel(button, "uuiMacro")
  LayoutButtonLabel(button, "uuiCooldownText")

  -- The shade spans the slot through its own corner anchors, so a resize only
  -- has to drop the cached width; its height follows the button by itself.
  if button.uuiGcdShade then button.uuiGcdShadeWidth = nil end

  classicAction.SizeButton(button, size)
end

local function HideButton(button)
  -- rendering.parent_alpha_not_propagated: hiding the button is not assumed to
  -- carry to its regions.
  ShowRegion(button.uuiIcon, false)
  ShowRegion(button.uuiKeybind, false)
  ShowRegion(button.uuiCount, false)
  ShowRegion(button.uuiMacro, false)
  ShowRegion(button.uuiCooldownText, false)
  ShowRegion(button.uuiPressed, false)
  ShowRegion(button.uuiClassicNormal, false)
  -- A locked highlight would otherwise still be held when this button is
  -- recycled into a slot whose action is not active. Clearing the cached flag
  -- with it keeps UpdateActive from short-circuiting and leaving a button that
  -- is still active after the recycle without its lock.
  if button.uuiClassicHighlight then
    pcall(button.UnlockHighlight, button)
  end
  button.uuiHover = false
  button.uuiActive = nil
  button.uuiEmpty = nil
  button.uuiSlotTexture = nil
  button.uuiCountText = nil
  button.uuiMacroText = nil
  button.uuiKeybindText = nil
  button.uuiTint = nil
  button.uuiCdActive = false
  button.uuiCdShown = false
  if button.uuiGcdShade then
    button.uuiGcdShadeShown = false
    button.uuiGcdShadeWidth = nil
    button.uuiGcdShade:Hide()
  end
  button:Hide()
end

-- ---------------------------------------------------------------------------
-- Button state
-- ---------------------------------------------------------------------------
local function UpdateSlot(button)
  local slot = ButtonSlot(button)

  local texture = Call("GetActionTexture", slot)
  if type(texture) == "string" and texture ~= "" then
    if button.uuiSlotTexture ~= texture then
      button.uuiSlotTexture = texture
      pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    end
    if button.uuiEmpty ~= false then button.uuiIcon:Show() end
    button.uuiEmpty = false
    -- The cache has to agree with what is actually written below. Without this
    -- the next UpdateUsable sees its own stale colour and skips the re-apply,
    -- which left an out-of-range button white until its state changed to
    -- something else and back.
    if not button.uuiTint then
      button.uuiTint = COLOR.usable
      ApplyIconTint(button)
    end
  else
    if button.uuiSlotTexture ~= false then
      button.uuiSlotTexture = false
      pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    end
    if button.uuiEmpty ~= true then button.uuiIcon:Hide() end
    button.uuiEmpty = true
    button.uuiTint = nil
  end

  -- GetActionCount is zero for spells, macros and empty slots, so it is the
  -- authoritative item check as well as the quantity.  IsConsumableAction
  -- excludes valid stackable items such as bandages, which left their action
  -- buttons without a count.
  local count = ""
  if cfg.showCount then
    local n = tonumber(Call("GetActionCount", slot))
    if n and n > 0 then count = tostring(n) end
  end
  -- Built only when non-empty. A slot that never carries a stack count never
  -- creates the fontstring; one that already has it still clears it correctly,
  -- because the second branch runs whenever the label exists.
  if count ~= "" then EnsureButtonLabel(button, "uuiCount") end
  if button.uuiCount and button.uuiCountText ~= count then
    button.uuiCountText = count
    button.uuiCount:SetText(count)
    ShowRegion(button.uuiCount, count ~= "")
  end

  local macro = ""
  if cfg.showMacro then macro = Call("GetActionText", slot) end
  if type(macro) ~= "string" then macro = "" end
  if macro ~= "" then EnsureButtonLabel(button, "uuiMacro") end
  if button.uuiMacro and button.uuiMacroText ~= macro then
    button.uuiMacroText = macro
    button.uuiMacro:SetText(macro)
    ShowRegion(button.uuiMacro, macro ~= "")
  end

  local key = ""
  if cfg.showKeybind then key = BindingFor(button.uuiBar, button.uuiIndex) end
  if type(key) ~= "string" then key = "" end
  if key ~= "" then EnsureButtonLabel(button, "uuiKeybind") end
  if button.uuiKeybind and button.uuiKeybindText ~= key then
    button.uuiKeybindText = key
    button.uuiKeybind:SetText(key)
    ShowRegion(button.uuiKeybind, key ~= "")
  end
end

local function UpdateUsable(button)
  local slot = ButtonSlot(button)
  if button.uuiEmpty then return end

  local color = COLOR.usable

  -- On cooldown outranks everything else here: it is the state that actually
  -- gates the button, so range/oom/unusable would just be noise under it.
  -- Reads button.uuiCdActive, which UpdateCooldown must therefore set before
  -- this runs -- see the call order in FullUpdate/RefreshState below. GCD-only
  -- cooldowns are excluded the same way the countdown number excludes them
  -- (button.uuiCdActive is false for those), so the icon does not flash red on
  -- every global-cooldown press.
  if button.uuiCdActive then
    color = COLOR.cooldown
  else
    -- Range is checked first so an out-of-range spell reads as red rather than
    -- as merely usable. Neither call has a compact record; the call shape
    -- follows UnrealPfUI's working implementation (WORKING_SOURCE, not
    -- runtime-verified).
    --
    -- ActionHasRange is only a gate there, so it is applied only when this
    -- client actually provides it -- IsActionInRange answers on its own,
    -- reporting 0 solely for a slot that has a range and is out of it, and nil
    -- for one that has no range or no target. A booleanised false is read the
    -- same way as 0.
    local hasRange = true
    if Has("ActionHasRange") then
      hasRange = Call("ActionHasRange", slot) and true or false
    end
    if hasRange then
      local inRange = Call("IsActionInRange", slot)
      if tonumber(inRange) == 0 or inRange == false then
        color = COLOR.outOfRange
      end
    end

    if color == COLOR.usable then
      local usable, oom = Call("IsUsableAction", slot)
      if oom and oom ~= 0 then
        color = COLOR.oom
      elseif usable ~= nil and (usable == false or usable == 0) then
        color = COLOR.unusable
      end
    end
  end

  if button.uuiTint ~= color then
    button.uuiTint = color
    ApplyIconTint(button)
  end
end

local function UpdateActive(button)
  local slot = ButtonSlot(button)
  local active = Call("IsCurrentAction", slot) or Call("IsAutoRepeatAction", slot)
  active = active and active ~= 0 and true or false

  if active == button.uuiActive then return end
  button.uuiActive = active
  if button.uuiClassic then
    classicAction.RefreshHighlight(button)
  else
    ApplyButtonBorder(button)
  end
end

-- ---------------------------------------------------------------------------
-- Cooldown countdown
--
-- The swipe only darkens the icon, so the number is what actually tells the
-- player when the spell is back. It is measured, never estimated: the timer is
-- always the client's own (start, duration) pair re-evaluated against the
-- client's own clock on every tick, so it stays right across a reload, a
-- /reload mid-cooldown, a cooldown started before login and a cooldown reset
-- early by the server -- all of which move the pair and none of which a
-- locally counted-down number would follow.
--
-- Evidence behind the two calls:
--   * api.json / actionbars.action_cooldown_1.v1: GetActionCooldown(slot)
--     returned exactly three numbers here (0, 0, 1 for an idle slot 1), which
--     is Vanilla's (start, duration, enable) shape. BEHAVIOR_PARTIALLY_TESTED
--     -- the idle triple is measured, a running cooldown is not, so every
--     component is coerced and the display is gated on start > 0.
--   * api.json / core.time.v1: GetTime() returned a plain rising number of
--     seconds (852.623). Same clock GetActionCooldown stamps start with.
-- ---------------------------------------------------------------------------
-- The (start, duration) pair is turned into seconds remaining by the shared
-- U.CooldownRemaining (core/compat.lua), which also owns this client's 32-bit
-- uptime wrap correction. modules/stancebar.lua draws the same readout from
-- the same helper.

-- The string and its tier come from the shared U.FormatTimeShort; this only
-- maps the tier onto the palette.
local function FormatCooldown(remaining)
  local text, tier = U.FormatTimeShort(remaining)
  return text, CD_COLOR[tier] or CD_COLOR.normal
end

local function WakeCooldownTimers()
  if cooldownTimerRunning then return end
  cooldownTimerRunning = true
  U.RegisterUpdate("actionbar.cooldown", CD_TICK, RefreshCooldownTimers)
end

-- Redraws one button's number from its cached pair. Cheap on purpose: this is
-- what runs at CD_TICK, so it re-reads the clock but not the action API.
local function RefreshCooldownText(button)
  -- The decision comes before the fontstring: a slot with nothing to count down
  -- must not create one, and most slots are in that state most of the time.
  local remaining = nil
  if button.uuiCdActive and cfg and cfg.showCooldown then
    remaining = U.CooldownRemaining(button.uuiCdStart, button.uuiCdDuration)
  end

  if not remaining or remaining <= 0 then
    if remaining and remaining <= 0 then button.uuiCdActive = false end
    local existing = button.uuiCooldownText
    if existing and button.uuiCdShown then
      button.uuiCdShown = false
      button.uuiCdColor = nil
      existing:SetText("")
      existing:Hide()
    end
    return
  end

  local label = EnsureButtonLabel(button, "uuiCooldownText")
  if not label then return end

  local text, color = FormatCooldown(remaining)
  label:SetText(text)

  if button.uuiCdColor ~= color then
    button.uuiCdColor = color
    pcall(label.SetTextColor, label, color[1], color[2], color[3], color[4])
  end
  if not button.uuiCdShown then
    button.uuiCdShown = true
    label:Show()
  end
  return true
end

local activeCooldownSeen = false
local function RefreshActiveCooldown(button)
  work.cdVisits = work.cdVisits + 1
  if RefreshCooldownText(button) then activeCooldownSeen = true end
end

local function WakeGCDSweep()
  if gcdTimerRunning then return end
  gcdTimerRunning = true
  U.RegisterUpdate("actionbar.gcd", 0.04, RefreshGCDSweep)
end

-- The global cooldown is never reported as a value of its own. It arrives as an
-- ordinary sub-threshold cooldown pair on every slot that is not already on a
-- longer cooldown of its own, which is why GCD_THRESHOLD exists in the first
-- place -- the countdown text uses it to *reject* these pairs. The same test
-- read the other way round is the detector: the first sub-threshold pair seen
-- during a sweep is this cast's global cooldown. Consumable items can report
-- the same short pair for their own use delay (notably food and drink), so
-- they must not be allowed to seed the bar-wide global sweep.
--
-- One pair is then shared by every button rather than each button reading its
-- own, so a slot sitting on a 30s cooldown still sweeps with the rest of the
-- bar instead of showing nothing -- the global cooldown is a player state, not
-- a per-slot one, and that is what the feedback is for.
local function NoteGCD(slot, start, duration)
  if not (cfg and cfg.showGCD) then return end
  if start <= 0 or duration <= 0 or duration >= GCD_THRESHOLD then return end
  if Call("IsConsumableAction", slot) then return end
  if gcdStart == start and gcdDuration == duration then return end

  local now = tonumber(Call("GetTime"))
  if not now then return end
  -- A stamp ahead of the clock is the 32-bit uptime wrap U.CooldownRemaining
  -- rebases for. Rebasing is not worth it across a 1.5s sweep: skip that one
  -- global cooldown rather than draw it from a stamp days out.
  if start > now then return end
  if start + duration <= now then return end

  gcdStart, gcdDuration = start, duration
  WakeGCDSweep()
end

-- Re-reads the slot's cooldown pair and drives the countdown and the icon
-- tint. There is no native swipe to drive: see CreateButton.
local function UpdateCooldown(button)
  local slot = ButtonSlot(button)
  local start, duration, enable = Call("GetActionCooldown", slot)

  start = tonumber(start) or 0
  duration = tonumber(duration) or 0
  enable = tonumber(enable)

  -- enable == 0 is Vanilla's "this slot has a cooldown but must not display
  -- one" flag; a missing value is read as enabled, the way pfUI reads it.
  if enable == nil or enable > 0 then NoteGCD(slot, start, duration) end

  button.uuiCdStart = start
  button.uuiCdDuration = duration
  button.uuiCdActive = (start > 0 and duration >= GCD_THRESHOLD
                        and (enable == nil or enable > 0)) and true or false

  if button.uuiCdActive and cfg and cfg.showCooldown then
    WakeCooldownTimers()
  end

  RefreshCooldownText(button)
end

-- Empty-slot backgrounds are optional per bar (actionbarconfig.lua's "Hide
-- Slot Background" checkbox): when hidden, only slots carrying an icon show
-- any fill/outline at all, so an empty bar reads as bare icons with nothing
-- behind them rather than a grid of boxes.
-- ACTIONBAR_SHOWGRID/HIDEGRID (Cursor state, above) fires while a spell/item/
-- macro is on the cursor, which is exactly when a player needs to see every
-- empty slot to know where a drop will land -- so the hidden background is
-- suspended for the duration of the pickup, the same way the native grid
-- would show, and restored once gridActive drops.
local function ApplyButtonBackground(button)
  local shown = gridActive or not (HidesBackground(button.uuiBar) and button.uuiEmpty)
  if button.uuiClassic then
    U.SetBackdropShown(button, false)
    ShowRegion(button.uuiClassicNormal, shown)
    if button.uuiKeybind then
      ShowRegion(button.uuiKeybind,
                 shown and button.uuiKeybindText ~= "")
    end
    return
  end
  U.SetBackdropShown(button, shown)
  -- A keybind label floating over a background-less slot is the same "empty
  -- box" the setting is meant to remove, so it goes with the background.
  if button.uuiKeybind then
    ShowRegion(button.uuiKeybind,
               shown and button.uuiKeybindText ~= "")
  end
end

local function FullUpdate(button)
  UpdateSlot(button)
  ApplyButtonBackground(button)
  UpdateCooldown(button)
  UpdateUsable(button)
  UpdateActive(button)
end

-- buttonVisits is the scale figure: every recurring action bar read funnels
-- through ForEachVisibleButton, so it counts every per-button callback the
-- module ran. slotSweeps vs stateSweeps says which of the two costs is being
-- paid -- a slot sweep is the full rebuild, a state sweep is the cheap one.
--
-- enabledBars/visibleButtons are read live rather than counted, because they
-- are the divisor: a per-bar cost is only visible as work-per-button, and the
-- bar-count cycle in core/perf.lua changes this number between phases.
function U.ActionBarStats()
  local shownBars, shownButtons = 0, 0
  local bar, i = nil, nil
  for bar = 1, BAR_COUNT do
    local entry = bars[bar]
    if entry then
      if entry.shown then shownBars = shownBars + 1 end
      for i = 1, table.getn(entry.buttons) do
        local button = entry.buttons[i]
        if entry.shown and button.uuiShown then
          shownButtons = shownButtons + 1
        end
      end
    end
  end

  return {
    enabledBars = shownBars,
    visibleButtons = shownButtons,
    slotSweeps = work.slotSweeps,
    stateSweeps = work.stateSweeps,
    buttonVisits = work.buttonVisits,
    gcdSweeps = work.gcdSweeps,
    gcdVisits = work.gcdVisits,
    cooldownSweeps = work.cdSweeps,
    cooldownVisits = work.cdVisits,
  }
end

-- Cleared between phases of a bar-count run so each phase's counts describe
-- that phase only. Never called by the addon itself.
function U.ResetActionBarStats()
  work.slotSweeps, work.stateSweeps, work.buttonVisits = 0, 0, 0
  work.gcdSweeps, work.gcdVisits = 0, 0
  work.cdSweeps, work.cdVisits = 0, 0
end

local function ForEachVisibleButton(callback)
  if U.PerfDisabled and U.PerfDisabled("bars") then return end

  local bar, i
  for bar = 1, BAR_COUNT do
    local entry = bars[bar]
    if entry and entry.shown then
      for i = 1, table.getn(entry.buttons) do
        local button = entry.buttons[i]
        if button.uuiShown then
          work.buttonVisits = work.buttonVisits + 1
          callback(button)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Global cooldown sweep
-- ---------------------------------------------------------------------------
-- Whether this button can carry a borrowed native cooldown at all.
local function NativeCooldownFrame(button)
  local family = NATIVE_CD_FAMILY[button.uuiBar]
  if not family then return nil end
  return U.G(family .. button.uuiIndex .. "Cooldown"), family
end

-- Borrows once and keeps it. Nothing writes to the frame afterwards: the client
-- owns its animation, which is the entire point of this style.
local function BorrowNativeCooldown(button)
  if button.uuiNativeCd then return button.uuiNativeCd end

  local frame, family = NativeCooldownFrame(button)
  if not frame then return nil end

  -- The client's cooldown update runs off the stock button, so that button has
  -- to be shown for the frame to be driven at all. Its mouse goes away with it:
  -- unrealUI has replaced it, and a shown stock button would otherwise be a
  -- second, invisible click target sitting under the real interface.
  local stockName = family .. button.uuiIndex
  if not nativeStockShown[stockName] then
    local stock = U.G(stockName)
    if stock then
      pcall(stock.Show, stock)
      pcall(stock.EnableMouse, stock, false)
      nativeStockShown[stockName] = true
    end
  end

  if not pcall(frame.SetParent, frame, button.uuiCooldownLayer) then return nil end
  pcall(frame.ClearAllPoints, frame)
  pcall(frame.SetAllPoints, frame, button)
  local ok, level = pcall(button.uuiCooldownLayer.GetFrameLevel, button.uuiCooldownLayer)
  if ok and tonumber(level) then
    pcall(frame.SetFrameLevel, frame, level - 1)
  end
  pcall(frame.SetAlpha, frame, 1)
  pcall(frame.Hide, frame)

  button.uuiNativeCd = frame
  return frame
end

-- Hidden rather than handed back: its original parent is a suppressed stock
-- button, so there is nowhere useful to return it to, and a hidden frame on a
-- hidden parent draws nothing either way.
local function ReleaseNativeCooldown(button)
  if not button.uuiNativeCd then return end
  pcall(button.uuiNativeCd.Hide, button.uuiNativeCd)
  button.uuiNativeCd = nil
end

-- Both shapes are hidden, not just the active one: this is also the path a
-- style change takes (SetActionBarGlobal clears the readout before re-applying),
-- so whichever shape was on screen has to come off it.
local function HideGCDSweep(button)
  if button.uuiGcdShadeShown then
    button.uuiGcdShadeShown = false
    button.uuiGcdShade:Hide()
  end
end

-- One texture, built on first use for the same reason the wipe is: a slot that
-- never sweeps never pays for it.
--
-- BACKGROUND on the raised layer, exactly where the radial wipe sits: over the
-- icon, but under the press flash (ARTWORK) and the countdown number (OVERLAY),
-- so the two styles stack identically and neither covers the readout. Anchored
-- down both left corners rather than given a height, so it spans the slot at
-- any button size and needs no resize handling of its own.
local function EnsureGCDShade(button)
  local shade = button.uuiGcdShade
  if shade then return shade end

  shade = button.uuiCooldownLayer:CreateTexture(nil, "BACKGROUND")
  pcall(shade.SetTexture, shade, M.texture.plain)
  U.SetColor(shade, M.Unpack(GCD_SHADE_COLOR))
  shade:Hide()
  shade:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  shade:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  button.uuiGcdShade = shade
  button.uuiGcdShadeWidth = nil
  return shade
end

local function ApplyGCDShade(button)
  local shade = EnsureGCDShade(button)

  -- Whole draw units only: this client drops fractional sizes rather than
  -- rendering them (see the Borders note in core/style.lua), and rounding here
  -- also means a tick that has not visibly moved the edge writes nothing.
  local width = math.floor((button.uuiSize or 0) * (1 - gcdProgress) + 0.5)
  if width < 1 then
    if button.uuiGcdShadeShown then
      button.uuiGcdShadeShown = false
      shade:Hide()
    end
    return
  end

  if button.uuiGcdShadeWidth ~= width then
    button.uuiGcdShadeWidth = width
    shade:SetWidth(width)
  end
  if not button.uuiGcdShadeShown then
    button.uuiGcdShadeShown = true
    shade:Show()
  end
end

local function ApplyGCDSweep(button)
  -- An empty slot has nothing to become ready, so it stays quiet. Everything
  -- else on screen sweeps together, which is the whole point of the readout.
  if button.uuiEmpty then return end

  -- A borrowed native cooldown is driven by the client. Writing to it is what
  -- made it unreproducible in the first place, so this returns before the
  -- work counter: these buttons genuinely cost nothing per tick.
  if button.uuiNativeCd then return end

  work.gcdVisits = work.gcdVisits + 1
  ApplyGCDShade(button)
end

local function ClearGCD()
  gcdStart, gcdDuration, gcdProgress = nil, nil, nil
  ForEachVisibleButton(HideGCDSweep)
  if gcdTimerRunning then
    gcdTimerRunning = false
    U.UnregisterUpdate("actionbar.gcd")
  end
end

-- One clock read for the whole action bar, then at most one size write per
-- button. Outside a global cooldown the cost is the nil check on the first
-- line, which is why this can tick faster than the state sweep: a 1.5s sweep
-- redrawn five times a second would step rather than travel.
RefreshGCDSweep = function()
  if not gcdStart then
    if gcdTimerRunning then
      gcdTimerRunning = false
      U.UnregisterUpdate("actionbar.gcd")
    end
    return
  end
  if not (cfg and cfg.showGCD) then ClearGCD() return end

  local now = tonumber(Call("GetTime"))
  if not now then ClearGCD() return end

  local elapsed = now - gcdStart
  if elapsed < 0 or elapsed >= gcdDuration then ClearGCD() return end

  gcdProgress = elapsed / gcdDuration
  work.gcdSweeps = work.gcdSweeps + 1
  ForEachVisibleButton(ApplyGCDSweep)
end

-- ---------------------------------------------------------------------------
-- Bars
-- ---------------------------------------------------------------------------
local function DefaultPosition(bar)
  -- Bars stack upward from the bottom centre. Only the first placement is ours;
  -- after that the mover store owns the position.
  local rank = bar
  local i
  for i = 1, table.getn(availableBars) do
    if availableBars[i] == bar then
      rank = i
      break
    end
  end
  return {
    point = "BOTTOM",
    relativePoint = "BOTTOM",
    x = 0,
    y = 20 + (rank - 1) * 40,
  }
end

local function CreateBar(bar)
  local frame = CreateFrame("Frame", "UnrealUIActionBar" .. bar, UIParent)
  -- Action bars are part of the persistent HUD.  Keep them below native
  -- interface windows (character, bags, spellbook, etc.) when those windows
  -- overlap the HUD.
  pcall(frame.SetFrameStrata, frame, "LOW")
  frame:SetWidth(100)
  frame:SetHeight(30)

  bars[bar] = { frame = frame, buttons = {}, shown = false }

  local i
  for i = 1, SLOTS_PER_BAR do
    bars[bar].buttons[i] = CreateButton(bar, i)
  end

  U.RegisterMover("actionbar.bar" .. bar, frame, {
    label = U.L("MOVER_LABEL_ACTION_BAR", bar),
    default = DefaultPosition(bar),
    -- Disabled bars keep their stored position but must not offer a drag
    -- handle in edit mode; see core/mover.lua.
    visible = function() return IsEnabled(bar) end,
  })

  return bars[bar]
end

local function LayoutBar(bar)
  local entry = bars[bar]
  if not entry then return end

  local enabled = IsEnabled(bar)
  local count = Number(bar, "Buttons")
  local perRow = Number(bar, "PerRow")
  local size = Number(bar, "Size")
  local spacing = Number(bar, "Spacing")

  if perRow > count then perRow = count end

  local columns = perRow
  local rows = math.ceil(count / perRow)

  entry.frame:SetWidth(columns * size + (columns - 1) * spacing)
  entry.frame:SetHeight(rows * size + (rows - 1) * spacing)

  local i
  for i = 1, SLOTS_PER_BAR do
    local button = entry.buttons[i]
    if enabled and i <= count then
      -- math.mod / the % operator are both Lua-version dependent and neither is
      -- recorded for this runtime, so the column is derived from the row.
      local row = math.floor((i - 1) / perRow)
      local column = (i - 1) - row * perRow

      SizeButton(button, size)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", entry.frame, "TOPLEFT",
                      column * (size + spacing), -row * (size + spacing))
      button:Show()
      button.uuiShown = true
      button.uuiTint = nil
      button.uuiActive = nil

      -- Borrowed here rather than on demand: the client drives the frame
      -- whether or not a cooldown is running, so there is no first-use moment
      -- to hang it off, and a bar is laid out rarely.
      -- Borrowed hidden, and left hidden. A shown Model animates on its own
      -- internal loop whether or not a cooldown is running -- the same
      -- self-animation that made SetSequenceTime unreproducible -- so showing
      -- it here produced a permanent sweep with nothing cast.
      -- CooldownFrame_SetTimer is what shows and hides one in Vanilla, so the
      -- client showing this frame IS the signal that it is driving it.
      if cfg and cfg.showGCD then
        BorrowNativeCooldown(button)
      else
        ReleaseNativeCooldown(button)
      end

      FullUpdate(button)
    else
      button.uuiShown = false
      ReleaseNativeCooldown(button)
      HideButton(button)
    end
  end

  entry.shown = enabled
  if enabled then entry.frame:Show() else entry.frame:Hide() end
end

-- Creates the bar on first use, so a bar nobody enables costs nothing.
local function ApplyBar(bar)
  if not bars[bar] then
    if not IsEnabled(bar) then return end
    CreateBar(bar)
  end
  LayoutBar(bar)
end

local function ApplyAll()
  local i
  for i = 1, BAR_COUNT do ApplyBar(i) end
end

-- ---------------------------------------------------------------------------
-- Public API
--
-- The settings tab (modules/actionbarconfig.lua) drives the bars through these
-- four functions and holds no state of its own.
-- ---------------------------------------------------------------------------
function U.ActionBarCount()
  return table.getn(availableBars)
end

function U.ActionBarTotal()
  return BAR_COUNT
end

function U.ActionBarReservation(bar)
  bar = tonumber(bar)
  if not bar or not reservedPages[bar] then return nil end
  return U.L(CLASS_RESERVED_REASON[playerClass] or "ABC_RESERVED_GENERIC")
end

function U.ActionBarIDs()
  local result, i = {}, nil
  for i = 1, table.getn(availableBars) do
    result[i] = availableBars[i]
  end
  return result
end

function U.ActionBarLimits(name)
  local limit = LIMITS[name]
  if not limit then return nil end
  return limit.min, limit.max, limit.step
end

-- The label toggles from the General Options page. They apply to every bar, so
-- a change re-lays out all of them.
function U.GetActionBarGlobal(name)
  if not cfg or GLOBAL_DEFAULTS[name] == nil then return nil end
  return cfg[name] and true or false
end

function U.SetActionBarGlobal(name, value)
  if not cfg or GLOBAL_DEFAULTS[name] == nil then return nil end
  cfg[name] = value and true or false
  -- Turning the readout off has to take whatever is on screen off with it: the
  -- shade is only redrawn by the sweep, and the sweep is about to stop running.
  if name == "showGCD" then ClearGCD() end
  ApplyAll()
  return U.GetActionBarGlobal(name)
end

function U.GetActionBarSetting(bar, name)
  bar = tonumber(bar)
  if not bar or bar < 1 or bar > BAR_COUNT or reservedPages[bar] or
     not cfg then return nil end
  if name == "Enabled" then return IsEnabled(bar) end
  if name == "HideBackground" then return HidesBackground(bar) end
  return Number(bar, name)
end

-- Writes a setting and re-applies that bar immediately. Returns the value that
-- was actually stored after clamping.
function U.SetActionBarSetting(bar, name, value)
  bar = tonumber(bar)
  if not bar or bar < 1 or bar > BAR_COUNT or reservedPages[bar] or
     not cfg then return nil end

  if name == "Enabled" then
    cfg[Key(bar, "Enabled")] = value and true or false
  elseif name == "HideBackground" then
    cfg[Key(bar, "HideBackground")] = value and true or false
  else
    if not LIMITS[name] then return nil end
    cfg[Key(bar, name)] = Clamp(name, value)
  end

  ApplyBar(bar)
  return U.GetActionBarSetting(bar, name)
end

-- ---------------------------------------------------------------------------
-- Native bars
--
-- knowledge.json / actionbars.native_stock_children_suppression: the stock
-- parents, every stock button prefix and the visual children this client draws
-- independently all have to be named. U.SuppressNativeFrame owns the re-apply
-- sweep, so this list is handed over once.
-- ---------------------------------------------------------------------------
local NATIVE_ROOTS = {
  "MainMenuBar", "MainMenuBarArtFrame", "BonusActionBarFrame",
  "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
}

local NATIVE_ART = {
  "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2",
  "MainMenuBarTexture3", "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MainMenuBarOverlayFrame", "MainMenuBarPageNumber",
  "ActionBarUpButton", "ActionBarDownButton",
}

local NATIVE_BUTTON_PREFIXES = {
  "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton", "MultiBarLeftButton", "MultiBarRightButton",
}

-- "Cooldown" is deliberately absent. The native style borrows those frames, and
-- a name registered with U.SuppressNativeFrame is hidden again on every sweep
-- -- measured at about once a second, which is what the probe's keeper was
-- fighting. Leaving them unregistered is safe for the other two styles: an
-- unborrowed cooldown's parent is the stock button, which IS suppressed, so it
-- cannot draw anywhere.
local NATIVE_BUTTON_PARTS = {
  "Icon", "NormalTexture", "NormalTexture2", "HotKey", "Count", "Border",
  "Flash", "Name", "AutoCastable",
}

local function SuppressNativeBars()
  local names, i, j, k = {}, nil, nil, nil

  for i = 1, table.getn(NATIVE_ROOTS) do
    table.insert(names, NATIVE_ROOTS[i])
  end
  for i = 1, table.getn(NATIVE_ART) do
    table.insert(names, NATIVE_ART[i])
  end

  for i = 1, table.getn(NATIVE_BUTTON_PREFIXES) do
    for j = 1, SLOTS_PER_BAR do
      local base = NATIVE_BUTTON_PREFIXES[i] .. j
      table.insert(names, base)
      for k = 1, table.getn(NATIVE_BUTTON_PARTS) do
        table.insert(names, base .. NATIVE_BUTTON_PARTS[k])
      end
    end
  end

  U.SuppressNativeFrame(names)
end

-- ---------------------------------------------------------------------------
-- Events and refresh
--
-- events.json: ACTIONBAR_SLOT_CHANGED is the only one of these observed on this
-- client. The rest are registered as accelerators, and the shared driver is
-- what actually guarantees a refresh.
-- ---------------------------------------------------------------------------
-- Events that change *what is in a slot*. Only these need the full per-button
-- rebuild, which re-reads the texture, the stack count, the macro name and the
-- binding label and writes four regions per button.
local SLOT_EVENTS = {
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
  "BAG_UPDATE", "UNIT_INVENTORY_CHANGED",
}

-- Events that change only *how an existing slot reads* -- usable/out of range/
-- out of mana, active, on cooldown. The slot contents cannot have moved, so a
-- full rebuild would re-read and rewrite the icon, count, macro and keybind of
-- every button to arrive at the same values it already had.
--
-- This split matters well beyond its own cost. ACTIONBAR_UPDATE_USABLE and
-- ACTIONBAR_UPDATE_STATE are the highest-frequency events in this family in
-- Vanilla -- target change, power change and aura change all emit them -- and
-- every one of them was running FullUpdate over every visible button
-- synchronously inside the firing frame. Neither event has any record in
-- events.json (they were never registered by a probe), so whether this client
-- emits them on target change is NOT VERIFIED; routing them correctly is right
-- either way, and /uui perf bars prices what is left.
local STATE_EVENTS = {
  "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE",
  "ACTIONBAR_UPDATE_COOLDOWN", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
  "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
}

local function RefreshSlots()
  work.slotSweeps = work.slotSweeps + 1
  ForEachVisibleButton(FullUpdate)
end

-- Only the number, from the cached pair. The pair itself is refreshed by the
-- state sweep and by ACTIONBAR_UPDATE_COOLDOWN; this is what makes the digits
-- move between those.
RefreshCooldownTimers = function()
  work.cdSweeps = work.cdSweeps + 1
  activeCooldownSeen = false
  ForEachVisibleButton(RefreshActiveCooldown)
  if not activeCooldownSeen then
    cooldownTimerRunning = false
    U.UnregisterUpdate("actionbar.cooldown")
  end
end

-- Hoisted out of RefreshState, which used to build it fresh on every sweep --
-- the same allocation the round-2 suppression fix removed from core/compat.lua.
local function UpdateButtonState(button)
  UpdateCooldown(button)
  UpdateUsable(button)
  UpdateActive(button)
end

local function RefreshState()
  work.stateSweeps = work.stateSweeps + 1
  ForEachVisibleButton(UpdateButtonState)
end

-- ---------------------------------------------------------------------------
-- Event coalescing
--
-- A single game action commonly emits several of these at once (a spell cast
-- lands ACTIONBAR_UPDATE_STATE, _USABLE and _COOLDOWN together), and each one
-- used to run its own complete walk of every visible button inside the same
-- frame. Collapse a frame's worth of events into one sweep on the next shared
-- driver tick, the way modules/unitframes.lua's QueueUnitToken collapses a
-- burst of unit events. "slots" outranks "state": the full rebuild already
-- does everything the state sweep does.
-- ---------------------------------------------------------------------------
local pendingRefresh = nil
local FlushPendingRefresh

local function QueueRefresh(mode)
  if pendingRefresh == "slots" then return end
  local wasEmpty = pendingRefresh == nil
  pendingRefresh = mode
  if wasEmpty then
    U.DeferOnce("actionbar.flush", FlushPendingRefresh)
  end
end

FlushPendingRefresh = function()
  local mode = pendingRefresh
  if not mode then return end
  pendingRefresh = nil
  if mode == "slots" then RefreshSlots() else RefreshState() end
end

local function QueueSlots() QueueRefresh("slots") end
local function QueueState() QueueRefresh("state") end

local function RegisterEvents()
  local i
  for i = 1, table.getn(SLOT_EVENTS) do
    U.RegisterEvent(SLOT_EVENTS[i], QueueSlots)
  end
  for i = 1, table.getn(STATE_EVENTS) do
    U.RegisterEvent(STATE_EVENTS[i], QueueState)
  end

  -- The grid flag has to be set in the firing frame -- CursorHoldsAction reads
  -- it -- but the repaint it implies can ride the same next-tick flush.
  U.RegisterEvent("ACTIONBAR_SHOWGRID", function()
    gridActive = true
    QueueSlots()
  end)
  U.RegisterEvent("ACTIONBAR_HIDEGRID", function()
    gridActive = false
    QueueSlots()
  end)

  local function RefreshBindings()
    ApplyOverrideBindings()
    QueueSlots()
  end
  U.RegisterEvent("UPDATE_BINDINGS", RefreshBindings)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", RefreshBindings)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    if bindingsDirty then ApplyOverrideBindings() end
  end)
end

-- ---------------------------------------------------------------------------
-- Binding surface
--
-- modules/quickbind.lua drives the hover-to-bind mode through these three
-- calls and keeps no bar state of its own. It asks which buttons are on screen
-- and which native binding command each one answers to, then hands the refresh
-- back here after a SetBinding so the override routes and the corner labels are
-- rebuilt in the one place that already owns them.
--
-- A bar with no entry in BINDING_PREFIX has no binding command in this client
-- (bar 6 and the class pages 7-10), so its buttons are reported with a nil
-- command and cannot be bound (see "Bars with no key route" above).
-- ---------------------------------------------------------------------------
function U.ActionBindingCommand(bar, index)
  bar, index = tonumber(bar), tonumber(index)
  if not bar or not index then return nil end
  local prefix = BindingPrefix(bar)
  if not prefix then return nil end
  return prefix .. index
end

function U.ActionBindingLabel(binding, full)
  return CompactBinding(binding, full)
end

-- modules/stancebar.lua draws the same corner key label on its own buttons and
-- follows this setting rather than owning a second copy of it. True before the
-- config is read, which matches the default.
function U.ActionBarShowsKeybinds()
  if not cfg then return true end
  return cfg.showKeybind and true or false
end

-- `declared` marks the slots whose command comes from unrealUI's own
-- Bindings.xml rather than from the client, which is worth telling the player:
-- the key is real and saved, but it is listed under an unrealUI header in the
-- Key Bindings window and only works while the addon is loaded.
function U.ActionBarBindTargets()
  local targets = {}
  ForEachVisibleButton(function(button)
    local bar = button.uuiBar
    table.insert(targets, {
      button = button,
      bar = bar,
      index = button.uuiIndex,
      command = U.ActionBindingCommand(bar, button.uuiIndex),
      declared = DECLARED_PREFIX[bar] and true or false,
    })
  end)
  return targets
end

-- Whether the client registered unrealUI's own binding commands. False means
-- Bindings.xml has not been read yet -- the client only reads it at start-up --
-- so bars 6-10 have no key route this session.
function U.ActionDeclaredBindingsRegistered()
  return DeclaredBindingsRegistered()
end

-- Kept as a capability readout for /uui check. This client (build 5875) is not
-- expected to have the pair; the native binding-function route is what carries
-- keys here (see InstallLegacyMainBindingRoute).
function U.ActionOverrideBindingsAvailable()
  return type(U.G("ClearOverrideBindings")) == "function" and
         type(U.G("SetOverrideBindingClick")) == "function"
end

-- Re-installs the override key routes and repaints every slot. UPDATE_BINDINGS
-- is expected to do this by itself, but that event is only EXISTENCE_ONLY here,
-- so the caller that changed a binding asks for the refresh directly.
function U.RefreshActionBarBindings()
  ApplyOverrideBindings()
  RefreshSlots()
end

-- bar2..bar6 identity swap when the bindable bars were resorted to the front:
-- old bar 2 (page 2, no key) moved to slot 6, and old bars 3-6 (the bindable
-- multibars) each shifted down one to close the gap. old->new is a single
-- 5-cycle (2->6->5->4->3->2), so every value has to be read before any of them
-- are written -- writing in numbering order would overwrite a slot this same
-- pass still needs to read from.
local BAR_RENUMBER_2026_08 = { [2] = 6, [3] = 2, [4] = 3, [5] = 4, [6] = 5 }
local BAR_RENUMBER_KEYS = { "Enabled", "Buttons", "PerRow", "Size", "Spacing" }

local function MigrateBarNumbering()
  local saved, bar, k = {}, nil, nil

  for bar = 2, 6 do
    saved[bar] = {}
    for k = 1, table.getn(BAR_RENUMBER_KEYS) do
      local name = BAR_RENUMBER_KEYS[k]
      saved[bar][name] = cfg[Key(bar, name)]
    end
    if U.db then saved[bar].position = U.db.positions["actionbar.bar" .. bar] end
  end

  for bar = 2, 6 do
    local newBar = BAR_RENUMBER_2026_08[bar]
    for k = 1, table.getn(BAR_RENUMBER_KEYS) do
      local name = BAR_RENUMBER_KEYS[k]
      cfg[Key(newBar, name)] = saved[bar][name]
    end
    if U.db then
      U.db.positions["actionbar.bar" .. newBar] = saved[bar].position
    end
  end
end

function AB:OnInit()
  ConfigureBarOwnership()
  cfg = U.ModuleConfig("actionbar", BuildDefaults())

  -- The shipped button spacing changed from 4 to 2. A database written by the
  -- first build still holds 4, and U.ModuleConfig only fills in keys that are
  -- missing, so the stored value is migrated once instead of silently
  -- disagreeing with the default. `layout` is this module's own scalar; it is
  -- not the addon-wide config version in core/config.lua.
  if (tonumber(cfg.layout) or 1) < 2 then
    local i
    for i = 1, BAR_COUNT do cfg[Key(i, "Spacing")] = 2 end
    cfg.layout = 2
  end

  -- Bindable bars were resorted to the front (1-5) and the rest to the back
  -- (6-10) on 2026-08-19. Run once per saved database.
  if (tonumber(cfg.layout) or 1) < 3 then
    MigrateBarNumbering()
    cfg.layout = 3
  end
end

function AB:OnEnable()
  if not cfg then cfg = U.ModuleConfig("actionbar", BuildDefaults()) end

  local _, class = Call("UnitClass", "player")
  local r, g, b = M.ClassColor(class)
  if r then classColor = { r, g, b } end

  -- Read the client's own button faces before the suppression pass makes the
  -- stock action bars invisible. Modern records no template and follows its
  -- existing flat rendering path.
  classicAction.Capture()
  SuppressNativeBars()
  ApplyAll()

  -- Before the first binding refresh: BindingFor and ApplyOverrideBindings both
  -- ask BindingPrefix, which only reports a declared command once the client has
  -- registered it, and the handler has to exist before any of those keys fire.
  InstallDeclaredBindingNames()
  InstallDeclaredBindingHandler()

  ApplyOverrideBindings()
  InstallLegacyMainBindingRoute()
  -- Keep the visual-only hooks for the static multibars too. On the legacy
  -- main route they wrap UnrealUI's replacement, never the hidden stock path.
  HookNativeBindingHighlights()
  RegisterEvents()

  -- Slot contents change rarely and cost the most calls; usable/active state
  -- is what the eye tracks. Cooldown digits and the GCD sweep register their
  -- faster timers only while at least one countdown is actually moving.
  U.RegisterUpdate("actionbar.state", 0.2, RefreshState)
  U.RegisterUpdate("actionbar.slots", 1, RefreshSlots)
end

-- Reported by /uui check.
function U.ActionBarReport()
  local report, i = {}, nil
  for i = 1, BAR_COUNT do
    local entry = bars[i]
    table.insert(report, {
      bar = i,
      reserved = reservedPages[i] and true or false,
      enabled = IsEnabled(i),
      created = entry and true or false,
      buttons = Number(i, "Buttons"),
      perRow = Number(i, "PerRow"),
      size = Number(i, "Size"),
      spacing = Number(i, "Spacing"),
      page = (i == 1) and ActivePage() or nil,
      cooldownText = (entry and entry.buttons[1] and
                      entry.buttons[1].uuiCooldownText) and true or false,
      nativeCooldown = (entry and entry.buttons[1] and
                        entry.buttons[1].uuiNativeCd) and true or false,
    })
  end
  return report
end

-- Applied by /uui abhl <alpha> [brighten].
--
-- The hover treatment is a judgement call the client forces on us: with no
-- additive blend available (rendering.setblendmode_add_inert) there is no
-- single correct pair of numbers, only the pair that reads closest to the stock
-- glow. Tuning both live beats another reload-and-look cycle, and it doubles as
-- the test for whether scaling a vertex colour above 1 brightens at all on this
-- client -- `/uui abhl 0 2` removes the wash entirely, so if hovering still
-- lights the icon, overbright works.
--
-- Values are not persisted: whatever reads right gets baked into the constants.
function U.ActionBarHighlightTune(alpha, brighten, rest)
  if alpha then CLASSIC_HIGHLIGHT_ALPHA = alpha end
  if brighten then CLASSIC_HOVER_BRIGHTEN = brighten end
  if rest then CLASSIC_REST_DIM = rest end

  ForEachVisibleButton(function(button)
    if not button.uuiClassic then return end
    classicAction.SetHighlightAlpha(
      button, button.uuiHover and CLASSIC_HIGHLIGHT_ALPHA or
              CLASSIC_ACTIVE_HIGHLIGHT_ALPHA)
    ApplyIconTint(button)
  end)

  U.Print("classic hover: alpha=" .. tostring(CLASSIC_HIGHLIGHT_ALPHA) ..
          " hover=" .. tostring(CLASSIC_HOVER_BRIGHTEN) ..
          " rest=" .. tostring(CLASSIC_REST_DIM))
end

-- Reported by /uui abhl.
--
-- USER_CONFIRMED_INGAME under the classic theme: hovering an action button
-- covers the icon with an opaque white square. Removing both owned highlight
-- regions did not change it, so the region responsible is not the one the hover
-- code was written against and guessing at further candidates is not warranted.
--
-- The first run of this dump reported tex=nil for every region including ones
-- that are shown and clearly textured, while GetDrawLayer and GetObjectType
-- answered normally through the same accessor -- so the GetTexture roundtrip
-- check below leads, being what classicAction.Capture stakes every face on.
-- Hover state is then reported as a before/after diff of the shown flags so the
-- raised layer's ~45 radial-wipe strips cannot bury the one region that moved.
function U.ActionBarHighlightDump()
  local function Ask(object, method)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object)
    if not ok then return nil end
    return value
  end

  local function Collect(into, label, frame, own)
    if not frame or type(frame.GetRegions) ~= "function" then return end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if not ok then return end
    local i
    for i = 1, table.getn(regions) do
      table.insert(into, { label = label .. i, region = regions[i], own = own })
    end
  end

  local function Describe(entry)
    return entry.label ..
           " " .. tostring(Ask(entry.region, "GetObjectType")) ..
           " layer=" .. tostring(Ask(entry.region, "GetDrawLayer")) ..
           " shown=" .. tostring(Ask(entry.region, "IsShown")) ..
           " r=" .. tostring(Ask(entry.region, "GetVertexColor")) ..
           " tex=" .. tostring(Ask(entry.region, "GetTexture"))
  end

  -- Does GetTexture report a path back at all on this client? Every classic
  -- face is read through it, so a nil answer here disables the whole template
  -- silently and no amount of highlight work downstream can matter.
  local parent = U.G("UIParent")
  if parent and type(parent.CreateTexture) == "function" then
    local madeOk, probe = pcall(parent.CreateTexture, parent, nil, "BACKGROUND")
    if madeOk and probe then
      pcall(probe.SetTexture, probe, "Interface\\Buttons\\ButtonHilight-Square")
      U.Print("GetTexture roundtrip=" .. tostring(Ask(probe, "GetTexture")))
      pcall(probe.Hide, probe)
    end
  end

  local source = U.G("ActionButton1")
  U.Print("ActionButton1=" .. tostring(source ~= nil) ..
          " normal=" .. tostring(Ask(Ask(source, "GetNormalTexture"), "GetTexture")) ..
          " highlight=" .. tostring(Ask(Ask(source, "GetHighlightTexture"), "GetTexture")))

  U.Print("classic active=" .. tostring(classicAction.active) ..
          " ready=" .. tostring(classicAction.ready) ..
          " normal=" .. tostring(classicAction.normal and classicAction.normal.path) ..
          " highlight=" .. tostring(classicAction.highlight and classicAction.highlight.path))

  local button = bars[1] and bars[1].buttons[1]
  if not button then
    U.Print("bar 1 button 1 does not exist")
    return
  end
  U.Print("button uuiClassic=" .. tostring(button.uuiClassic) ..
          " uuiClassicHighlight=" .. tostring(button.uuiClassicHighlight) ..
          " empty=" .. tostring(button.uuiEmpty))

  local entries, i = {}, nil
  Collect(entries, "btn", button, true)
  Collect(entries, "layer", button.uuiCooldownLayer, false)

  local before = {}
  for i = 1, table.getn(entries) do
    before[i] = Ask(entries[i].region, "IsShown") and true or false
  end

  local enter, leave = nil, nil
  if type(button.GetScript) == "function" then
    local ok, value = pcall(button.GetScript, button, "OnEnter")
    if ok then enter = value end
    ok, value = pcall(button.GetScript, button, "OnLeave")
    if ok then leave = value end
  end
  if type(enter) ~= "function" then
    U.Print("no OnEnter handler to fire")
    return
  end

  local fired, err = pcall(enter, button)
  if not fired then U.Print("OnEnter error: " .. tostring(err)) end

  -- Only what hover actually changed, so the 45 radial-wipe strips on the
  -- raised layer cannot bury the one region that matters.
  U.Print("-- changed by hover --")
  local changed = 0
  for i = 1, table.getn(entries) do
    local now = Ask(entries[i].region, "IsShown") and true or false
    if now ~= before[i] then
      changed = changed + 1
      U.Print("  " .. tostring(before[i]) .. "->" .. tostring(now) ..
              " " .. Describe(entries[i]))
    end
  end
  if changed == 0 then U.Print("  nothing changed shown state") end

  if type(leave) == "function" then pcall(leave, button) end

  U.Print("-- button's own regions --")
  for i = 1, table.getn(entries) do
    if entries[i].own then U.Print("  " .. Describe(entries[i])) end
  end
end

-- ---------------------------------------------------------------------------
-- Countdown dump (/uui abcd)
--
-- The cooldown number has four independent ways to end up invisible and the
-- symptom is identical for every one of them: the client never reports the
-- pair (GetActionCooldown), the state gate rejects it (uuiCdActive, which also
-- drives the red icon tint), the FontString was never created (U.CreateLabel
-- returned nil), or the label is shown and carries text but draws nothing --
-- no font object, zero alpha, or a raised layer that is not visible. Nothing
-- in this module distinguishes them from the outside, so print all four in one
-- pass rather than trying successive blind fixes across reloads.
-- ---------------------------------------------------------------------------
function U.ActionBarCooldownDump()
  local function Ask(object, method)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object)
    if not ok then return nil end
    return value
  end

  U.Print("classic active=" .. tostring(classicAction.active) ..
          " ready=" .. tostring(classicAction.ready) ..
          ", showCooldown=" .. tostring(cfg and cfg.showCooldown) ..
          ", font=" .. tostring(U.GetFontChoice and U.GetFontChoice("default")))

  -- A slot already counting down answers every question below with live
  -- values; an empty or ready slot answers all of them with a zero and proves
  -- nothing. Prefer the first one this module believes is on cooldown, and
  -- fall back to any slot carrying an action so the command still reports the
  -- label and layer state when nothing is running.
  local entry = bars[1]
  local button, fallback, i = nil, nil, nil
  if entry then
    for i = 1, table.getn(entry.buttons) do
      local candidate = entry.buttons[i]
      if candidate.uuiShown and not candidate.uuiEmpty then
        if not fallback then fallback = candidate end
        if candidate.uuiCdActive and not button then button = candidate end
      end
    end
  end
  button = button or fallback
  if not button then
    U.Print("bar 1 has no visible slot carrying an action")
    return
  end

  local slot = ButtonSlot(button)
  local start, duration, enable = Call("GetActionCooldown", slot)
  U.Print("slot " .. tostring(slot) ..
          " GetActionCooldown start=" .. tostring(start) ..
          " duration=" .. tostring(duration) ..
          " enable=" .. tostring(enable) ..
          " now=" .. tostring(Call("GetTime")))
  U.Print("  cached start=" .. tostring(button.uuiCdStart) ..
          " duration=" .. tostring(button.uuiCdDuration) ..
          " active=" .. tostring(button.uuiCdActive) ..
          " shown=" .. tostring(button.uuiCdShown) ..
          " remaining=" .. tostring(button.uuiCdActive and
            U.CooldownRemaining(button.uuiCdStart, button.uuiCdDuration)))

  local layer = button.uuiCooldownLayer
  U.Print("  button level=" .. tostring(Ask(button, "GetFrameLevel")) ..
          " shown=" .. tostring(Ask(button, "IsShown")) ..
          ", raised layer level=" .. tostring(Ask(layer, "GetFrameLevel")) ..
          " shown=" .. tostring(Ask(layer, "IsShown")) ..
          " visible=" .. tostring(Ask(layer, "IsVisible")) ..
          " alpha=" .. tostring(Ask(layer, "GetAlpha")))

  local label = button.uuiCooldownText
  if label == nil then
    U.Print("  no countdown FontString yet - this slot has not counted down " ..
            "since login, so EnsureButtonLabel has not built one")
    return
  end
  if not label then
    U.Print("  no countdown FontString - U.CreateLabel returned nil")
    return
  end
  U.Print("  label text=" .. tostring(Ask(label, "GetText")) ..
          " shown=" .. tostring(Ask(label, "IsShown")) ..
          " visible=" .. tostring(Ask(label, "IsVisible")) ..
          " drawLayer=" .. tostring(Ask(label, "GetDrawLayer")) ..
          " w=" .. tostring(Ask(label, "GetWidth")) ..
          " h=" .. tostring(Ask(label, "GetHeight")))
  U.Print("  label font=" .. tostring(Ask(label, "GetFont")) ..
          " object=" .. tostring(Ask(label, "GetFontObject")) ..
          " colour=" .. tostring(Ask(label, "GetTextColor")) ..
          " alpha=" .. tostring(Ask(label, "GetAlpha")))
end
