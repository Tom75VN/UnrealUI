-- unrealUI :: modules/actionbarconfig.lua
--
-- The "ActionBars" group in the settings window: a collapsible entry in the
-- category list holding General Options and one page per bar.
--
-- Each bar page carries the controls from the reference layout: an Enable
-- checkbox and horizontal sliders for the number of buttons, the buttons per
-- row, the button size and the button spacing.
--
-- This file owns no state. Every value is read from and written back through
-- U.GetActionBarSetting / U.SetActionBarSetting in modules/actionbar.lua, which
-- clamps it, stores it and re-applies the bar immediately.

local U = UnrealUI
local M = U.media

local ABC = U.RegisterModule("actionbarconfig")

local GROUP = "actionbars"

-- Content geometry. The settings window is 700 wide with a 168 sidebar, so a
-- page has a little under 490 to work with: two slider columns and a gutter.
local PAGE_WIDTH = 484
local COLUMN_X = 258
local SLIDER_WIDTH = 200

local SLIDERS = {
  { key = "Buttons", textKey = "ABC_BUTTONS",         column = 0, row = 0 },
  { key = "PerRow",  textKey = "ABC_BUTTONS_PER_ROW", column = 1, row = 0 },
  { key = "Size",    textKey = "ABC_BUTTON_SIZE",     column = 0, row = 1 },
  { key = "Spacing", textKey = "ABC_BUTTON_SPACING",  column = 1, row = 1 },
}

local ROW_Y = { -104, -180 }

-- ---------------------------------------------------------------------------
-- Bar pages
-- ---------------------------------------------------------------------------
local function BuildBarPage(parent, bar)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("ABC_BAR_N", bar),
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUIActionBarConfigEnable" .. bar,
    text = U.L("COMMON_ENABLE"),
    value = U.GetActionBarSetting(bar, "Enabled"),
    onChange = function(value)
      U.SetActionBarSetting(bar, "Enabled", value)
    end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local hideBackground = U.CreateCheckbox(parent, {
    name = "UnrealUIActionBarConfigHideBackground" .. bar,
    text = U.L("ABC_HIDE_SLOT_BACKGROUND"),
    value = U.GetActionBarSetting(bar, "HideBackground"),
    onChange = function(value)
      U.SetActionBarSetting(bar, "HideBackground", value)
    end,
  })
  hideBackground.SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_X, -34)
  table.insert(widgets, hideBackground)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if hint then
    U.AnchorSettingsDescription(hint, enable.box)
    if bar == 1 then
      hint:SetText(U.L("ABC_HINT_BAR1"))
    elseif bar >= 2 and bar <= 5 then
      hint:SetText(U.L("ABC_HINT_MULTIBAR"))
    else
      hint:SetText(U.L("ABC_HINT_PAGE_ONLY"))
    end
    table.insert(widgets, hint)
  end

  local i
  for i = 1, table.getn(SLIDERS) do
    local spec = SLIDERS[i]
    local min, max, step = U.ActionBarLimits(spec.key)

    local slider = U.CreateSlider(parent, {
      name = "UnrealUIActionBarConfig" .. spec.key .. bar,
      text = U.L(spec.textKey),
      width = SLIDER_WIDTH,
      min = min,
      max = max,
      step = step,
      value = U.GetActionBarSetting(bar, spec.key),
      onChange = function(value)
        U.SetActionBarSetting(bar, spec.key, value)
      end,
    })
    slider.SetPoint("TOPLEFT", parent, "TOPLEFT",
                    spec.column * COLUMN_X, ROW_Y[spec.row + 1])

    controls[spec.key] = slider
    table.insert(widgets, slider)
  end

  local function Refresh()
    enable.SetValue(U.GetActionBarSetting(bar, "Enabled"))
    hideBackground.SetValue(U.GetActionBarSetting(bar, "HideBackground"))

    local j
    for j = 1, table.getn(SLIDERS) do
      local key = SLIDERS[j].key
      if controls[key] then
        controls[key].SetValue(U.GetActionBarSetting(bar, key))
      end
    end
  end

  return widgets, Refresh
end

local function BuildReservedBarPage(parent, bar, reason)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("ABC_BAR_N", bar),
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local status = U.CreateSettingsLabel(parent, {
    size = M.fontSize.normal,
    color = M.color.textDim,
    inherits = "GameFontNormal",
    justify = "LEFT",
    height = 22,
  })
  if status then
    status:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -38)
    status:SetText(U.L("ABC_RESERVED_FOR", reason))
    table.insert(widgets, status)
  end

  local explanation = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if explanation then
    U.AnchorSettingsDescription(explanation, status)
    explanation:SetText(U.L("ABC_RESERVED_EXPLANATION", reason))
    table.insert(widgets, explanation)
  end

  local saved = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if saved then
    U.AnchorSettingsDescription(saved, explanation)
    saved:SetText(U.L("ABC_RESERVED_SAVED"))
    table.insert(widgets, saved)
  end

  return widgets
end

-- ---------------------------------------------------------------------------
-- General options
--
-- The label toggles apply to every bar at once, which is what makes them
-- general rather than per-bar. Nothing else in this file is global, and no
-- option is listed here that unrealUI does not actually implement.
-- ---------------------------------------------------------------------------
local GLOBALS = {
  { key = "showKeybind",  textKey = "ABC_SHOW_KEYBIND" },
  { key = "showMacro",    textKey = "ABC_SHOW_MACRO" },
  { key = "showCount",    textKey = "ABC_SHOW_COUNT" },
  { key = "showCooldown", textKey = "ABC_SHOW_COOLDOWN" },
  { key = "showGCD",      textKey = "ABC_SHOW_GCD" },
}

local function BuildGeneralPage(parent)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("ABC_GENERAL"),
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local i
  for i = 1, table.getn(GLOBALS) do
    local spec = GLOBALS[i]

    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIActionBarConfigGlobal" .. spec.key,
      text = U.L(spec.textKey),
      value = U.GetActionBarGlobal(spec.key),
      onChange = function(value)
        U.SetActionBarGlobal(spec.key, value)
      end,
    })
    check.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34 - (i - 1) * 26)

    controls[spec.key] = check
    table.insert(widgets, check)
  end

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if hint then
    U.AnchorSettingsDescription(hint, controls[GLOBALS[table.getn(GLOBALS)].key].box)
    hint:SetText(U.L("ABC_GENERAL_HINT", U.ActionBarCount()))
    table.insert(widgets, hint)
  end

  -- Quick binding (modules/quickbind.lua) is a mode rather than a setting, so
  -- this is a launcher: the window closes and the mode takes the screen.
  local bindY = -34 - table.getn(GLOBALS) * 26 - 34

  local quickbind = U.CreateButton(parent, {
    name = "UnrealUIActionBarConfigQuickBind",
    text = U.L("SETTINGS_QUICKBIND"),
    width = 220,
    height = 26,
    onClick = function()
      if type(U.OpenQuickBind) == "function" then
        U.OpenQuickBind()
      else
        U.Error(U.L("QUICKBIND_UNAVAILABLE"))
      end
    end,
  })
  quickbind:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, bindY)
  table.insert(widgets, quickbind)

  local bindHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if bindHint then
    U.AnchorSettingsDescription(bindHint, quickbind)
    bindHint:SetText(U.L("ABC_BIND_HINT"))
    table.insert(widgets, bindHint)
  end

  local function Refresh()
    local j
    for j = 1, table.getn(GLOBALS) do
      local key = GLOBALS[j].key
      if controls[key] then controls[key].SetValue(U.GetActionBarGlobal(key)) end
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function ABC:OnInit()
  -- Registered in OnInit so modules/settings.lua has defined the category API
  -- regardless of .toc order, and so General stays the first page in the list.
  if type(U.RegisterSettingsGroup) ~= "function" then
    U.Error("settings window has no category API; action bar options unavailable")
    return
  end

  U.RegisterSettingsGroup(GROUP, U.L("ABC_GROUP"))

  U.RegisterSettingsTab(GROUP .. ".general", U.L("ABC_GENERAL"), BuildGeneralPage,
                        { parent = GROUP })

  local total = type(U.ActionBarTotal) == "function" and U.ActionBarTotal() or
                U.ActionBarCount()
  local i
  for i = 1, total do
    local bar = i
    local reservation = type(U.ActionBarReservation) == "function" and
                        U.ActionBarReservation(bar) or nil
    if reservation then
      local tooltip = U.L("ABC_RESERVED_TOOLTIP", reservation)
      U.RegisterSettingsTab(GROUP .. ".bar" .. bar, U.L("ABC_BAR_N", bar),
        function(parent)
          return BuildReservedBarPage(parent, bar, reservation)
        end,
        { parent = GROUP, muted = true, tooltip = tooltip })
    else
      U.RegisterSettingsTab(GROUP .. ".bar" .. bar, U.L("ABC_BAR_N", bar),
        function(parent)
          return BuildBarPage(parent, bar)
        end,
        { parent = GROUP })
    end
  end
end
