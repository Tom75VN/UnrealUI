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

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if hint then
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -58)
    if bar == 1 then
      hint:SetText("Bar 1 follows the action page and the stock bar keybinds.")
    elseif bar >= 3 and bar <= 6 then
      hint:SetText("Uses the stock multi-bar keybinds for these slots.")
    else
      hint:SetText("Page-only bar: it has no keybinds of its own in this client.")
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

-- ---------------------------------------------------------------------------
-- General options
--
-- The three label toggles apply to every bar at once, which is what makes them
-- general rather than per-bar. Nothing else in this file is global, and no
-- option is listed here that unrealUI does not actually implement.
-- ---------------------------------------------------------------------------
local GLOBALS = {
  { key = "showKeybind", text = "Show keybinds" },
  { key = "showMacro",   text = "Show macro names" },
  { key = "showCount",   text = "Show item counts" },
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
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34 - table.getn(GLOBALS) * 26 - 8)
    hint:SetText("Pick a bar on the left to enable it and set its layout. " ..
                 "Bars are placed with Move UI.")
    table.insert(widgets, hint)
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

  local i
  for i = 1, U.ActionBarCount() do
    local bar = i
    U.RegisterSettingsTab(GROUP .. ".bar" .. i, "Bar " .. i, function(parent)
      return BuildBarPage(parent, bar)
    end, { parent = GROUP })
  end
end
