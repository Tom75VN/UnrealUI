-- unrealUI :: modules/actionbar.lua
--
-- Ten action bars in the pfUI modern style: flat near-black square buttons with
-- one thin outline, the icon inset inside it, the keybind top-right, the item
-- count bottom-right and the macro name bottom-left.
--
-- Only the look and the call shapes are taken from pfUI. None of its bar
-- architecture is reproduced: no config schema, no secure/TBC state driver, no
-- hoverbind, no reagent counter, no animations, no stance/pet bars. Stance and
-- pet bars are separate scope; this file owns the ten 12-slot action bars only.
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
--     OnUpdate. Refreshes run on the shared driver.
--   * knowledge.json / rendering.parent_alpha_not_propagated: every child
--     region is shown and hidden explicitly, never via its parent.

local U = UnrealUI
local M = U.media

local AB = U.RegisterModule("actionbar")

-- ---------------------------------------------------------------------------
-- Layout model
--
-- Bar N owns slots (N-1)*12+1 .. N*12, which is Vanilla's flat 120-slot space:
-- bar 3 is MultiBarRight, 4 is MultiBarLeft, 5 is MultiBarBottomRight and 6 is
-- MultiBarBottomLeft. Bar 1 is the paged bar and resolves its slots from the
-- active page instead (see SlotFor).
-- ---------------------------------------------------------------------------
local BAR_COUNT = 10
local SLOTS_PER_BAR = 12

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
  showKeybind = true,
  showMacro   = true,
  showCount   = true,
}

-- Vanilla binding names for the slot ranges the stock UI owns. Bars 2 and 7-10
-- are page-only in Vanilla and have no binding of their own, so their buttons
-- simply show no key.
local BINDING_PREFIX = {
  [1] = "ACTIONBUTTON",
  [3] = "MULTIACTIONBAR3BUTTON",
  [4] = "MULTIACTIONBAR4BUTTON",
  [5] = "MULTIACTIONBAR2BUTTON",
  [6] = "MULTIACTIONBAR1BUTTON",
}

local ICON_INSET = 2

local COLOR = {
  usable    = { 1.00, 1.00, 1.00, 1.00 },
  oom       = { 0.40, 0.40, 1.00, 1.00 },
  unusable  = { 0.35, 0.35, 0.35, 1.00 },
  outOfRange= { 0.90, 0.25, 0.25, 1.00 },
  keybind   = { 0.85, 0.85, 0.85, 1.00 },
  count     = { 1.00, 1.00, 1.00, 1.00 },
  macro     = { 0.70, 0.70, 0.70, 1.00 },
}

local bars = {}         -- bar index -> { frame, buttons, mover }
local cfg               -- module settings table (flat; see BuildDefaults)
local classColor = { 0.5, 0.5, 1.0 }

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
  return (bar - 1) * SLOTS_PER_BAR + index
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
  ["\""] = "3", ["QUOTEDBL"] = "3", ["DOUBLEQUOTE"] = "3",
  ["'"] = "4", ["QUOTE"] = "4", ["APOSTROPHE"] = "4",
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

local function OnButtonClick(button)
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

  -- Cooldown swipe. CreateFrame("Model", ..., "CooldownFrameTemplate") is the
  -- Vanilla shape UnrealPfUI uses on this client (COOLDOWN_FRAME_TYPE in
  -- compat/vanilla.lua), but neither the type nor the template has a compact
  -- record, so a failure here just means the numeric fallback text is used.
  local ok, cooldown = pcall(CreateFrame, "Model", name .. "Cooldown", button,
                             "CooldownFrameTemplate")
  if ok and cooldown and Has("CooldownFrame_SetTimer") then
    pcall(cooldown.SetAllPoints, cooldown, button)
    button.uuiCooldown = cooldown
  end

  button.uuiCooldownText = U.CreateLabel(button, {
    size = M.fontSize.normal, color = { 1.0, 0.85, 0.3, 1.0 },
    inherits = "GameFontNormal",
  })
  if button.uuiCooldownText then
    button.uuiCooldownText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.uuiCooldownText:Hide()
  end

  -- scripts.handler_arguments_direct: handlers close over `button` instead of
  -- reading `this`, because the argument shape is not guaranteed here.
  button:SetScript("OnClick", function() OnButtonClick(button) end)
  button:SetScript("OnDragStart", function() OnButtonDragStart(button) end)
  button:SetScript("OnReceiveDrag", function() OnButtonReceiveDrag(button) end)
  button:SetScript("OnEnter", function()
    button.uuiHover = true
    if not button.uuiActive then
      U.SetBorderColor(button, 0.55, 0.55, 0.55, 1)
    end
    ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    button.uuiHover = false
    if not button.uuiActive then
      U.SetBorderColor(button, M.Unpack(M.color.border))
    end
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
    U.SetFont(button.uuiCooldownText, small + 2)
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
  else
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    button.uuiIcon:Hide()
    button.uuiEmpty = true
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

  -- Range is checked first so an out-of-range spell reads as red rather than as
  -- merely usable. Both range calls are unrecorded here and may be absent.
  if Call("ActionHasRange", slot) then
    local inRange = Call("IsActionInRange", slot)
    if inRange == 0 then color = COLOR.outOfRange end
  end

  if color == COLOR.usable then
    local usable, oom = Call("IsUsableAction", slot)
    if oom and oom ~= 0 then
      color = COLOR.oom
    elseif usable ~= nil and (usable == false or usable == 0) then
      color = COLOR.unusable
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

  if active then
    U.SetBorderColor(button, classColor[1], classColor[2], classColor[3], 1)
  elseif button.uuiHover then
    U.SetBorderColor(button, 0.55, 0.55, 0.55, 1)
  else
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end
end

local function UpdateCooldown(button)
  local slot = ButtonSlot(button)
  local start, duration, enable = Call("GetActionCooldown", slot)

  start = tonumber(start) or 0
  duration = tonumber(duration) or 0

  if button.uuiCooldown then
    local fn = U.G("CooldownFrame_SetTimer")
    if type(fn) == "function" then
      pcall(fn, button.uuiCooldown, start, duration, enable or 1)
      return
    end
  end

  -- Fallback: no usable swipe frame, so show the remaining whole seconds. The
  -- global cooldown is deliberately skipped -- a 1.5s number on every button on
  -- every cast is noise, not information.
  local label = button.uuiCooldownText
  if not label then return end

  if start > 0 and duration > 1.5 then
    local now = tonumber(Call("GetTime")) or 0
    local remaining = start + duration - now
    if remaining > 0 then
      if remaining >= 60 then
        label:SetText(tostring(math.floor(remaining / 60 + 0.5)) .. "m")
      else
        label:SetText(tostring(math.floor(remaining + 0.5)))
      end
      label:Show()
      return
    end
  end

  label:SetText("")
  label:Hide()
end

local function FullUpdate(button)
  UpdateSlot(button)
  UpdateUsable(button)
  UpdateActive(button)
  UpdateCooldown(button)
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
  return {
    point = "BOTTOM",
    relativePoint = "BOTTOM",
    x = 0,
    y = 20 + (bar - 1) * 40,
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
  return BAR_COUNT
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
  if not bar or bar < 1 or bar > BAR_COUNT or not cfg then return nil end
  if name == "Enabled" then return IsEnabled(bar) end
  return Number(bar, name)
end

-- Writes a setting and re-applies that bar immediately. Returns the value that
-- was actually stored after clamping.
function U.SetActionBarSetting(bar, name, value)
  bar = tonumber(bar)
  if not bar or bar < 1 or bar > BAR_COUNT or not cfg then return nil end

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
  "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD", "BAG_UPDATE",
  "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE",
  "ACTIONBAR_UPDATE_COOLDOWN", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
  "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "UNIT_INVENTORY_CHANGED",
}

local function RefreshSlots()
  ForEachVisibleButton(FullUpdate)
end

local function RefreshState()
  ForEachVisibleButton(function(button)
    UpdateUsable(button)
    UpdateActive(button)
    UpdateCooldown(button)
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
end

function AB:OnInit()
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
  RegisterEvents()

  -- Two rates: slot contents change rarely and cost the most calls, while
  -- cooldown/usable/active state is what the eye actually tracks.
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
      enabled = IsEnabled(i),
      created = entry and true or false,
      buttons = Number(i, "Buttons"),
      perRow = Number(i, "PerRow"),
      size = Number(i, "Size"),
      spacing = Number(i, "Spacing"),
      page = (i == 1) and ActivePage() or nil,
      cooldownFrame = (entry and entry.buttons[1] and
                       entry.buttons[1].uuiCooldown) and true or false,
    })
  end
  return report
end
