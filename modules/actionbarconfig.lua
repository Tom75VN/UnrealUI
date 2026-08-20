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
  { key = "Buttons", text = "Buttons",         column = 0, row = 0 },
  { key = "PerRow",  text = "Buttons Per Row", column = 1, row = 0 },
  { key = "Size",    text = "Button Size",     column = 0, row = 1 },
  { key = "Spacing", text = "Button Spacing",  column = 1, row = 1 },
}

local ROW_Y = { -104, -180 }

-- ---------------------------------------------------------------------------
-- Bar pages
-- ---------------------------------------------------------------------------
local function BuildBarPage(parent, bar)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = "Bar " .. bar,
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUIActionBarConfigEnable" .. bar,
    text = "Enable",
    value = U.GetActionBarSetting(bar, "Enabled"),
    onChange = function(value)
      U.SetActionBarSetting(bar, "Enabled", value)
    end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local hideBackground = U.CreateCheckbox(parent, {
    name = "UnrealUIActionBarConfigHideBackground" .. bar,
    text = "Hide Slot Background",
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
      hint:SetText("Bar 1 follows the action page and the stock bar keybinds.")
    elseif bar >= 2 and bar <= 5 then
      hint:SetText("Uses the stock multi-bar keybinds for these slots.")
    else
      hint:SetText("Page-only bar: this client has no keybind command for it, " ..
                   "so its slots are mouse-only.")
    end
    table.insert(widgets, hint)
  end

  local i
  for i = 1, table.getn(SLIDERS) do
    local spec = SLIDERS[i]
    local min, max, step = U.ActionBarLimits(spec.key)

    local slider = U.CreateSlider(parent, {
      name = "UnrealUIActionBarConfig" .. spec.key .. bar,
      text = spec.text,
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
    text = "Bar " .. bar,
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
    status:SetText("Reserved for " .. reason)
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
    explanation:SetText(
      "This action page is used automatically by Bar 1 while " .. reason ..
      " is active. Showing it as another physical bar would expose the same " ..
      "action slots twice, so its layout controls are locked on this character."
    )
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
    saved:SetText(
      "Account-wide settings for this page are preserved. They remain " ..
      "available on characters whose class does not reserve it."
    )
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
  { key = "showKeybind",  text = "Show keybinds" },
  { key = "showMacro",    text = "Show macro names" },
  { key = "showCount",    text = "Show item counts" },
  { key = "showCooldown", text = "Show cooldown timers" },
}

local function BuildGeneralPage(parent)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = "General Options",
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local i
  for i = 1, table.getn(GLOBALS) do
    local spec = GLOBALS[i]

    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIActionBarConfigGlobal" .. spec.key,
      text = spec.text,
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
    hint:SetText(tostring(U.ActionBarCount()) .. " independent bars are available. " ..
                 "Pages used by this class's forms are shown only on Bar 1.")
    table.insert(widgets, hint)
  end

  -- Quick binding (modules/quickbind.lua) is a mode rather than a setting, so
  -- this is a launcher: the window closes and the mode takes the screen.
  local bindY = -34 - table.getn(GLOBALS) * 26 - 34

  local quickbind = U.CreateButton(parent, {
    name = "UnrealUIActionBarConfigQuickBind",
    text = "Quick Binding",
    width = 220,
    height = 26,
    onClick = function()
      if type(U.OpenQuickBind) == "function" then
        U.OpenQuickBind()
      else
        U.Error("quick binding is not available in this build")
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
    bindHint:SetText("Hover a slot and press a key to bind it. Escape over a " ..
                     "slot clears it. Bars 1-5 are bindable; bars 6-10 have no " ..
                     "key command in this client, so they are shown but cannot " ..
                     "take one.")
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

  U.RegisterSettingsGroup(GROUP, "ActionBars")

  U.RegisterSettingsTab(GROUP .. ".general", "General Options", BuildGeneralPage,
                        { parent = GROUP })

  local total = type(U.ActionBarTotal) == "function" and U.ActionBarTotal() or
                U.ActionBarCount()
  local i
  for i = 1, total do
    local bar = i
    local reservation = type(U.ActionBarReservation) == "function" and
                        U.ActionBarReservation(bar) or nil
    if reservation then
      local tooltip = "Reserved for " .. reservation ..
                      ". Bar 1 uses this page automatically."
      U.RegisterSettingsTab(GROUP .. ".bar" .. bar, "Bar " .. bar,
        function(parent)
          return BuildReservedBarPage(parent, bar, reservation)
        end,
        { parent = GROUP, muted = true, tooltip = tooltip })
    else
      U.RegisterSettingsTab(GROUP .. ".bar" .. bar, "Bar " .. bar,
        function(parent)
          return BuildBarPage(parent, bar)
        end,
        { parent = GROUP })
    end
  end
end
