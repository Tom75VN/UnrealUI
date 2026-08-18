-- unrealUI :: modules/actionbar.lua
--
-- Up to ten action bars in the pfUI modern style: flat near-black square buttons with
-- one thin outline, the icon inset inside it, the keybind top-right, the item
-- count bottom-right and the macro name bottom-left.
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
-- The four native multibar commands address bars 3-6 / slots 25-72.
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
  ROGUE = "Rogue Stealth",
  WARRIOR = "Warrior stances",
  DRUID = "Druid forms",
}

local reservedPages = {}
local availableBars = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local playerClass

-- Slot base per bar (SlotFor adds 1..12 on top). Bar 1 is omitted: it is
-- paged and resolved dynamically in SlotFor instead of through this table.
local BAR_SLOT_BASE = {
  [2]  = 12,  -- page 2:                13-24
  [3]  = 24,  -- MultiBarRight:         25-36
  [4]  = 36,  -- MultiBarLeft:          37-48
  [5]  = 48,  -- MultiBarBottomRight:   49-60
  [6]  = 60,  -- MultiBarBottomLeft:    61-72
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
}

-- Native binding names for the slot ranges the stock UI owns. Bar 2 and any
-- class-available pages among 7-10 have no dedicated binding command, so
-- UnrealUI neither displays nor installs a key route for those buttons.
local BINDING_PREFIX = {
  [1] = "ACTIONBUTTON",
  [3] = "MULTIACTIONBAR3BUTTON",
  [4] = "MULTIACTIONBAR4BUTTON",
  [5] = "MULTIACTIONBAR2BUTTON",
  [6] = "MULTIACTIONBAR1BUTTON",
}

local ICON_INSET = 2
local PRESS_FLASH_DURATION = 0.16

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
-- the visual baseline this module follows.
local CD_COLOR = {
  low    = { 1.00, 0.20, 0.20, 1.00 },   -- last five seconds
  normal = { 1.00, 1.00, 1.00, 1.00 },
  minute = { 0.20, 1.00, 1.00, 1.00 },
  hour   = { 0.20, 0.50, 1.00, 1.00 },
  day    = { 0.20, 0.20, 1.00, 1.00 },
}

-- A cooldown shorter than this is the global cooldown, and a 1.5s number on
-- every button on every cast is noise rather than information. 2 is pfUI's own
-- appearance.cd.threshold default; it also absorbs a GCD inflated by latency.
local GCD_THRESHOLD = 2

-- The countdown is re-read from the clock this often. Fast enough that the
-- tenths shown in the last five seconds actually count down.
local CD_TICK = 0.1

local bars = {}         -- bar index -> { frame, buttons, mover }
local pressedButtons = {}
local cfg               -- module settings table (flat; see BuildDefaults)
local classColor = { 0.5, 0.5, 1.0 }
local bindingsDirty = false

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

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Everything below is resolved by name and pcall'd. A missing call degrades one
-- part of a button rather than erroring out of the refresh loop.
-- ---------------------------------------------------------------------------
local function Call(name, a, b, c)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3
end

local function Has(name)
  return type(U.G(name)) == "function"
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
  ["MINUS"] = "-", ["HYPHEN"] = "-", ["NEGATIVE"] = "-", ["UNDERSCORE"] = "_",
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

local function CompactBinding(binding)
  if type(binding) ~= "string" or binding == "" then return "" end

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

  if string.len(text) > 4 then text = string.sub(text, 1, 4) end
  return text
end

local function BindingFor(bar, index)
  local prefix = BINDING_PREFIX[bar]
  if not prefix then return "" end
  return CompactBinding(Call("GetBindingKey", prefix .. index))
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

        local prefix = BINDING_PREFIX[bar]
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

local function ApplyButtonBorder(button)
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
    table.insert(pressedButtons, button)
  end
end

local function ReleaseButtonPress(button)
  if button then button.uuiPressedHeld = nil end
end

local function RefreshPressedButtons()
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
end

-- Build 5875 uses the Vanilla binding-function path. Those commands call the
-- native ActionButtonDown/Up and MultiActionButtonDown/Up globals directly, so
-- a successful action does not imply that UnrealUI's OnClick ran. Post-hook the
-- native functions for visual state only; their original action execution and
-- return values remain untouched inside U.PostHookGlobal.
local NATIVE_BINDING_BAR = {
  MultiBarRight = 3,
  MultiBarLeft = 4,
  MultiBarBottomRight = 5,
  MultiBarBottomLeft = 6,
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

  local down = function(index)
    local button = BoundButton(1, index)
    if button then ShowButtonPress(button, true) end
  end
  local up = function(index)
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

  -- fonts.stretched_justification_ignored: each label is anchored to the one
  -- corner it belongs in rather than stretched across the button.
  button.uuiKeybind = U.CreateLabel(button, {
    size = M.fontSize.tiny, color = COLOR.keybind, inherits = "GameFontNormalSmall",
  })
  button.uuiCount = U.CreateLabel(button, {
    size = M.fontSize.small, color = COLOR.count, inherits = "GameFontNormalSmall",
  })
  button.uuiMacro = U.CreateLabel(button, {
    size = M.fontSize.tiny, color = COLOR.macro, inherits = "GameFontNormalSmall",
  })

  -- Cooldown swipe -- the radial wipe animation, driven natively rather than
  -- drawn by hand. CreateFrame("Model", ..., "CooldownFrameTemplate") is the
  -- Vanilla shape UnrealPfUI uses for it on this client (COOLDOWN_FRAME_TYPE in
  -- compat/vanilla.lua, and the same call shape modules/actionbar.lua,
  -- bags.lua, nameplates.lua, totems.lua and unitframes.lua all use there): in
  -- 1.12-shaped clients the cooldown swipe is itself a Model-type frame, not a
  -- dedicated Cooldown widget, so this is not a synthetic reimplementation --
  -- it is the same primitive Blizzard's own action buttons animate with.
  -- Distinct from unitframes.portrait_model_crash (BROKEN): that record is the
  -- full PlayerModel character-rendering chain (SetModel/SetUnit/
  -- SetModelScale), a different call sequence on the same frame type. Neither
  -- the frame type nor the template has its own compact record here, so
  -- failure is still a real possibility -- if this swipe stays invisible in
  -- game, that means Has("CooldownFrame_SetTimer") read false or the client
  -- rejected the template, and the numeric countdown is the fallback.
  local ok, cooldown = pcall(CreateFrame, "Model", name .. "Cooldown", button,
                             "CooldownFrameTemplate")
  if ok and cooldown and Has("CooldownFrame_SetTimer") then
    pcall(cooldown.SetAllPoints, cooldown, button)
    button.uuiCooldown = cooldown
  end

  -- The swipe above is a Model child of the button, so a fontstring living on
  -- the button's own OVERLAY layer can be drawn underneath it. The countdown
  -- therefore sits on a raised child frame -- the same raised-layer trick the
  -- unit frames use for bar labels, and what UnrealPfUI does for its cooldown
  -- text (modules/cooldown.lua parents it to the button at a higher level).
  -- The layer takes no mouse input, so clicks and drags still reach the button.
  local textLayer = CreateFrame("Frame", nil, button)
  pcall(textLayer.SetAllPoints, textLayer, button)
  local levelOk, level = pcall(button.GetFrameLevel, button)
  if levelOk and tonumber(level) then
    pcall(textLayer.SetFrameLevel, textLayer, level + 10)
  end
  button.uuiCooldownLayer = textLayer

  -- A raised translucent fill stays visible above the icon and cooldown swipe
  -- while leaving the key/count/macro labels readable. It is driven by the
  -- shared updater rather than an unreliable child-frame OnUpdate.
  local pressed = textLayer:CreateTexture(nil, "ARTWORK")
  pcall(pressed.SetAllPoints, pressed, textLayer)
  pcall(pressed.SetTexture, pressed, M.texture.plain)
  U.SetColor(pressed, 1, 1, 1, 0.28)
  pressed:Hide()
  button.uuiPressed = pressed

  button.uuiCooldownText = U.CreateLabel(textLayer, {
    size = M.fontSize.normal, color = CD_COLOR.normal,
    inherits = "GameFontNormal",
  })
  if button.uuiCooldownText then
    button.uuiCooldownText:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    button.uuiCooldownText:Hide()
  end

  -- scripts.handler_arguments_direct: handlers close over `button` instead of
  -- reading `this`, because the argument shape is not guaranteed here.
  button:SetScript("OnClick", function() OnButtonClick(button) end)
  button:SetScript("OnDragStart", function() OnButtonDragStart(button) end)
  button:SetScript("OnReceiveDrag", function() OnButtonReceiveDrag(button) end)
  button:SetScript("OnEnter", function()
    button.uuiHover = true
    ApplyButtonBorder(button)
    ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    button.uuiHover = false
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

  local icon = button.uuiIcon
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", ICON_INSET, -ICON_INSET)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)

  -- Label sizes follow the button so a 60px button does not carry 9px text and
  -- a 15px one is not covered by it.
  local small = math.floor(size / 2.6)
  if small < 7 then small = 7 end
  if small > 14 then small = 14 end

  if button.uuiKeybind then
    button.uuiKeybind:ClearAllPoints()
    button.uuiKeybind:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    U.SetFont(button.uuiKeybind, small)
  end
  if button.uuiCount then
    button.uuiCount:ClearAllPoints()
    button.uuiCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    U.SetFont(button.uuiCount, small)
  end
  if button.uuiMacro then
    button.uuiMacro:ClearAllPoints()
    button.uuiMacro:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    button.uuiMacro:SetWidth(size - 6)
    U.SetFont(button.uuiMacro, small)
  end
  if button.uuiCooldownText then
    -- The countdown is the readout, not a corner label, so it scales off the
    -- button rather than off the small-label size. pfUI's dynamic cooldown font
    -- uses height * .64; half the button is the same idea, one step calmer.
    local cdSize = math.floor(size * 0.5)
    if cdSize < 10 then cdSize = 10 end
    if cdSize > 24 then cdSize = 24 end
    U.SetFont(button.uuiCooldownText, cdSize)
  end
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
  button.uuiCdActive = false
  button.uuiCdShown = false
  if button.uuiCooldown then pcall(button.uuiCooldown.Hide, button.uuiCooldown) end
  button:Hide()
end

-- ---------------------------------------------------------------------------
-- Button state
-- ---------------------------------------------------------------------------
local function UpdateSlot(button)
  local slot = ButtonSlot(button)

  local texture = Call("GetActionTexture", slot)
  if type(texture) == "string" and texture ~= "" then
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    U.SetColor(button.uuiIcon, 1, 1, 1, 1)
    button.uuiIcon:Show()
    button.uuiEmpty = false
    -- The white write above is the tint, so the cache has to agree with it.
    -- Without this the next UpdateUsable sees its own stale colour and skips
    -- the re-apply, which left an out-of-range button white until its state
    -- changed to something else and back.
    button.uuiTint = COLOR.usable
  else
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    button.uuiIcon:Hide()
    button.uuiEmpty = true
    button.uuiTint = nil
  end

  -- Counts: consumables report a stack, everything else reports nothing.
  local count = ""
  if cfg.showCount and Call("IsConsumableAction", slot) then
    local n = tonumber(Call("GetActionCount", slot))
    if n and n > 0 then count = tostring(n) end
  end
  if button.uuiCount then
    button.uuiCount:SetText(count)
    ShowRegion(button.uuiCount, count ~= "")
  end

  local macro = nil
  if cfg.showMacro then macro = Call("GetActionText", slot) end
  if button.uuiMacro then
    if type(macro) == "string" and macro ~= "" then
      button.uuiMacro:SetText(macro)
      button.uuiMacro:Show()
    else
      button.uuiMacro:SetText("")
      button.uuiMacro:Hide()
    end
  end

  local key = ""
  if cfg.showKeybind then key = BindingFor(button.uuiBar, button.uuiIndex) end
  if button.uuiKeybind then
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
    U.SetColor(button.uuiIcon, color[1], color[2], color[3], color[4])
  end
end

local function UpdateActive(button)
  local slot = ButtonSlot(button)
  local active = Call("IsCurrentAction", slot) or Call("IsAutoRepeatAction", slot)
  active = active and active ~= 0 and true or false

  if active == button.uuiActive then return end
  button.uuiActive = active
  ApplyButtonBorder(button)
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
local function Round(value)
  return math.floor(value + 0.5)
end

-- Only needed by the wrap correction below, and only if this client wraps at
-- all. Each source is optional and guarded.
local function EpochSeconds()
  local value = tonumber(Call("time"))
  if value then return value end

  value = tonumber(Call("GetServerTime"))
  if value then return value end

  local fn = U.G("date")
  if type(fn) == "function" then
    local ok, text = pcall(fn, "%s")
    value = ok and tonumber(text) or nil
    if value then return value end
  end
  return nil
end

-- Seconds left on (start, duration), or nil when it cannot be established.
local function CooldownRemaining(start, duration)
  local now = tonumber(Call("GetTime")) or 0

  if start <= now then
    return duration - (now - start)
  end

  -- A start stamped ahead of the current time means the client's 32-bit
  -- millisecond uptime counter wrapped and the stamp belongs to the previous
  -- cycle, so the plain subtraction would read as a cooldown days long.
  -- UnrealPfUI corrects it by rebasing both onto wall-clock seconds
  -- (modules/cooldown.lua); the arithmetic here is that working implementation,
  -- so it is WORKING_SOURCE evidence and not verified on this client. It only
  -- runs in a case the plain path is already wrong in.
  local epoch = EpochSeconds()
  if not epoch then return nil end

  local startupTime = epoch - now
  local cdTime = (2 ^ 32) / 1000 - start
  return (startupTime - cdTime + duration) - epoch
end

-- pfUI-modern's unit switch points: days above 99 hours, hours above 99
-- minutes, minutes above 99 seconds, and tenths over the last five seconds.
local function FormatCooldown(remaining)
  if remaining > 356400 then
    return Round(remaining / 86400) .. "d", CD_COLOR.day
  elseif remaining > 5940 then
    return Round(remaining / 3600) .. "h", CD_COLOR.hour
  elseif remaining > 99 then
    return Round(remaining / 60) .. "m", CD_COLOR.minute
  elseif remaining <= 5 then
    return string.format("%.1f", remaining), CD_COLOR.low
  end
  return tostring(Round(remaining)), CD_COLOR.normal
end

-- Redraws one button's number from its cached pair. Cheap on purpose: this is
-- what runs at CD_TICK, so it re-reads the clock but not the action API.
local function RefreshCooldownText(button)
  local label = button.uuiCooldownText
  if not label then return end

  local remaining = nil
  if button.uuiCdActive and cfg and cfg.showCooldown then
    remaining = CooldownRemaining(button.uuiCdStart, button.uuiCdDuration)
  end

  if not remaining or remaining <= 0 then
    if remaining and remaining <= 0 then button.uuiCdActive = false end
    if button.uuiCdShown then
      button.uuiCdShown = false
      button.uuiCdColor = nil
      label:SetText("")
      label:Hide()
    end
    return
  end

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
end

-- Re-reads the slot's cooldown pair and drives both the swipe and the number.
local function UpdateCooldown(button)
  local slot = ButtonSlot(button)
  local start, duration, enable = Call("GetActionCooldown", slot)

  start = tonumber(start) or 0
  duration = tonumber(duration) or 0
  enable = tonumber(enable)

  if button.uuiCooldown then
    local fn = U.G("CooldownFrame_SetTimer")
    if type(fn) == "function" then
      pcall(fn, button.uuiCooldown, start, duration, enable or 1)
    end
  end

  -- enable == 0 is Vanilla's "this slot has a cooldown but must not display
  -- one" flag; a missing value is read as enabled, the way pfUI reads it.
  button.uuiCdStart = start
  button.uuiCdDuration = duration
  button.uuiCdActive = (start > 0 and duration >= GCD_THRESHOLD
                        and (enable == nil or enable > 0)) and true or false

  RefreshCooldownText(button)
end

local function FullUpdate(button)
  UpdateSlot(button)
  UpdateCooldown(button)
  UpdateUsable(button)
  UpdateActive(button)
end

local function ForEachVisibleButton(callback)
  local bar, i
  for bar = 1, BAR_COUNT do
    local entry = bars[bar]
    if entry and entry.shown then
      for i = 1, table.getn(entry.buttons) do
        local button = entry.buttons[i]
        if button.uuiShown then callback(button) end
      end
    end
  end
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
  frame:SetWidth(100)
  frame:SetHeight(30)

  bars[bar] = { frame = frame, buttons = {}, shown = false }

  local i
  for i = 1, SLOTS_PER_BAR do
    bars[bar].buttons[i] = CreateButton(bar, i)
  end

  U.RegisterMover("actionbar.bar" .. bar, frame, {
    label = "Bar " .. bar,
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
      FullUpdate(button)
    else
      button.uuiShown = false
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
  return CLASS_RESERVED_REASON[playerClass] or "class/form paging"
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
  ApplyAll()
  return cfg[name]
end

function U.GetActionBarSetting(bar, name)
  bar = tonumber(bar)
  if not bar or bar < 1 or bar > BAR_COUNT or reservedPages[bar] or
     not cfg then return nil end
  if name == "Enabled" then return IsEnabled(bar) end
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

local NATIVE_BUTTON_PARTS = {
  "Icon", "NormalTexture", "NormalTexture2", "HotKey", "Count", "Border",
  "Cooldown", "Flash", "Name", "AutoCastable",
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
local SLOT_EVENTS = {
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
  "BAG_UPDATE",
  "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE",
  "ACTIONBAR_UPDATE_COOLDOWN", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
  "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "UNIT_INVENTORY_CHANGED",
}

local function RefreshSlots()
  ForEachVisibleButton(FullUpdate)
end

-- Only the number, from the cached pair. The pair itself is refreshed by the
-- state sweep and by ACTIONBAR_UPDATE_COOLDOWN; this is what makes the digits
-- move between those.
local function RefreshCooldownTimers()
  ForEachVisibleButton(RefreshCooldownText)
end

local function RefreshState()
  ForEachVisibleButton(function(button)
    UpdateCooldown(button)
    UpdateUsable(button)
    UpdateActive(button)
  end)
end

local function RegisterEvents()
  local i
  for i = 1, table.getn(SLOT_EVENTS) do
    U.RegisterEvent(SLOT_EVENTS[i], RefreshSlots)
  end

  U.RegisterEvent("ACTIONBAR_SHOWGRID", function()
    gridActive = true
  end)
  U.RegisterEvent("ACTIONBAR_HIDEGRID", function()
    gridActive = false
  end)

  local function RefreshBindings()
    ApplyOverrideBindings()
    RefreshSlots()
  end
  U.RegisterEvent("UPDATE_BINDINGS", RefreshBindings)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", RefreshBindings)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    if bindingsDirty then ApplyOverrideBindings() end
  end)
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
end

function AB:OnEnable()
  if not cfg then cfg = U.ModuleConfig("actionbar", BuildDefaults()) end

  local _, class = Call("UnitClass", "player")
  local r, g, b = M.ClassColor(class)
  if r then classColor = { r, g, b } end

  SuppressNativeBars()
  ApplyAll()
  ApplyOverrideBindings()
  InstallLegacyMainBindingRoute()
  -- Keep the visual-only hooks for the static multibars too. On the legacy
  -- main route they wrap UnrealUI's replacement, never the hidden stock path.
  HookNativeBindingHighlights()
  RegisterEvents()

  -- Three rates: slot contents change rarely and cost the most calls, usable/
  -- active/cooldown state is what the eye tracks, and the countdown itself only
  -- re-reads the clock, so it can tick fastest for the least work.
  U.RegisterUpdate("actionbar.cooldown", CD_TICK, RefreshCooldownTimers)
  U.RegisterUpdate("actionbar.pressed", 0, RefreshPressedButtons)
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
      cooldownFrame = (entry and entry.buttons[1] and
                       entry.buttons[1].uuiCooldown) and true or false,
      cooldownText = (entry and entry.buttons[1] and
                      entry.buttons[1].uuiCooldownText) and true or false,
    })
  end
  return report
end
