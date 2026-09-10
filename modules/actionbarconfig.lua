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

-- Mover ids registered by modules/actionbar.lua. Not GROUP: the settings
-- category and the mover id are two different names for the same bars.
local MOVER_ID_PREFIX = "actionbar.bar"

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

-- The contextual panel carries the same controls as a bar page, but it has to
-- fit in the space beside an anchor rather than inside the settings window.
-- The default bottom-centre stack leaves about 440 units either side of bar 1,
-- so this layout stays narrow enough to sit next to it instead of being pushed
-- above it, where it would cover the anchors of the bars stacked there. The
-- two checkboxes are stacked in one column because their labels are much wider
-- in frFR and ruRU than the slider captions above them.
--
-- The window itself, its placement beside the anchor and its show/hide
-- lifecycle belong to core/moverpanel.lua; this file owns only what is in it.
local MOVER_SLIDER_WIDTH = 150
local MOVER_COLUMN_X = MOVER_SLIDER_WIDTH + 18
local MOVER_CONTENT_WIDTH = MOVER_COLUMN_X + MOVER_SLIDER_WIDTH
-- Rows relative to the shared content top, matching the bar page's 76 pitch.
local MOVER_ROW_Y = { -106, -182 }

-- The bar the shared panel is currently pointed at. One spec serves every bar,
-- so the control callbacks read this rather than closing over a bar number.
local moverBar = nil

local function MoverHint(bar)
  if bar == 1 then return U.L("ABC_HINT_BAR1") end
  if bar >= 2 and bar <= 5 then return U.L("ABC_HINT_MULTIBAR") end
  return U.L("ABC_HINT_PAGE_ONLY")
end

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
    hint:SetText(MoverHint(bar))
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

-- ---------------------------------------------------------------------------
-- Contextual edit-mode bar panel
--
-- One reusable set of controls follows the selected action-bar mover. It uses
-- the same getters, setters, limits and labels as BuildBarPage above, so this is
-- a second view of the same saved settings rather than a second configuration.
--
-- core/moverpanel.lua builds this once and retargets it at whichever bar is
-- selected, which is why every callback reads moverBar instead of a captured
-- bar number.
-- ---------------------------------------------------------------------------
local function BuildMoverPanel(frame, contentTop, contentWidth)
  local pad = U.MoverPanelPad()
  local widgets = {}
  local controls = {}

  local function BeginLiveEdit()
    if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
  end

  local enable = U.CreateCheckbox(frame, {
    name = "UnrealUIActionBarMoverEnable",
    text = U.L("COMMON_ENABLE"),
    value = true,
    onChange = function(value)
      U.SetActionBarSetting(moverBar, "Enabled", value)
    end,
  })
  enable.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
  controls.enable = enable
  table.insert(widgets, enable)

  local hideBackground = U.CreateCheckbox(frame, {
    name = "UnrealUIActionBarMoverHideBackground",
    text = U.L("ABC_HIDE_SLOT_BACKGROUND"),
    value = false,
    onChange = function(value)
      U.SetActionBarSetting(moverBar, "HideBackground", value)
    end,
  })
  hideBackground.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop - 22)
  controls.hideBackground = hideBackground
  table.insert(widgets, hideBackground)

  local hint = U.CreateSettingsLabel(frame, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = contentWidth,
  })
  if hint then
    U.AnchorSettingsDescription(hint, hideBackground.box)
    table.insert(widgets, hint)
  end
  controls.hint = hint

  local i
  for i = 1, table.getn(SLIDERS) do
    local spec = SLIDERS[i]
    local key = spec.key
    local min, max, step = U.ActionBarLimits(key)
    local slider = U.CreateSlider(frame, {
      name = "UnrealUIActionBarMover" .. key,
      text = U.L(spec.textKey),
      width = MOVER_SLIDER_WIDTH,
      boxWidth = 60,
      min = min,
      max = max,
      step = step,
      value = min,
      onInputStart = BeginLiveEdit,
      onInput = function(value)
        if type(U.PreviewActionBarSetting) == "function" then
          U.PreviewActionBarSetting(moverBar, key, value)
        end
      end,
      onChange = function(value)
        U.SetActionBarSetting(moverBar, key, value)
      end,
    })
    slider.SetPoint("TOPLEFT", frame, "TOPLEFT",
                    pad + spec.column * MOVER_COLUMN_X,
                    contentTop + MOVER_ROW_Y[spec.row + 1])
    controls[key] = slider
    table.insert(widgets, slider)
  end

  -- id is the mover being shown ("actionbar.barN"); the panel is one set of
  -- controls pointed at that bar.
  local function Refresh(id)
    local _, _, value = string.find(tostring(id), "^actionbar%.bar(%d+)$")
    moverBar = tonumber(value) or moverBar
    local bar = moverBar
    if not bar then return end

    controls.enable.SetValue(U.GetActionBarSetting(bar, "Enabled"))
    controls.hideBackground.SetValue(U.GetActionBarSetting(bar, "HideBackground"))
    if controls.hint then controls.hint:SetText(MoverHint(bar)) end

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

-- One spec, registered for every bar's mover id in OnInit. A bar reserved for a
-- class page has no settings to offer, so it reports itself unavailable and
-- selecting its handle shows nothing.
local moverSpec = {
  name = "UnrealUIActionBarMoverSettings",
  width = MOVER_CONTENT_WIDTH + U.MoverPanelPad() * 2,
  -- Last row: track at -182 below the content top, then the readout box
  -- (8 + 2 + 16) below it.
  height = 280,
  build = BuildMoverPanel,
  -- Only reached if a bar mover ever loses its label; the handle's own label
  -- is what normally titles the panel.
  title = function(id)
    local _, _, value = string.find(tostring(id), "^actionbar%.bar(%d+)$")
    return U.L("ABC_BAR_N", tonumber(value) or 1)
  end,
  available = function(id)
    local _, _, value = string.find(tostring(id), "^actionbar%.bar(%d+)$")
    local bar = tonumber(value)
    return bar ~= nil and (type(U.ActionBarReservation) ~= "function" or
                          not U.ActionBarReservation(bar))
  end,
}

-- Both views of a bar's settings read the same store, so whichever one wrote a
-- value tells the other to re-read it. modules/actionbar.lua calls this only
-- after the value has been clamped and stored. Live slider previews bypass the
-- refresh so they cannot fight the thumb while it is moving.
function U.RefreshActionBarSettingsViews(bar)
  bar = tonumber(bar)
  if not bar then return end
  if type(U.RefreshMoverPanel) == "function" then
    U.RefreshMoverPanel(MOVER_ID_PREFIX .. bar)
  end
  if type(U.RefreshSettingsPage) == "function" then
    U.RefreshSettingsPage(GROUP .. ".bar" .. bar)
  end
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
-- Pet bar page
--
-- The pet bar is the client's own bar with a mover on it, not an unrealUI bar,
-- so it has no button count of its own. The two things unrealUI does place --
-- the size of the native pet buttons and the gap between them -- get the same
-- two sliders as every other bar, driven through U.GetPetBarSetting /
-- U.SetPetBarSetting in modules/petbar.lua. Enable is not a pet bar setting
-- either: it is the mover group's show/hide, shared with edit mode.
--
-- Moving either slider takes ownership of the row; the reset button hands it
-- back to the client. Both are exactly what /uui petbar size|spacing|reset do.
-- ---------------------------------------------------------------------------
local PET_SLIDERS = {
  { key = "Size",    textKey = "ABC_BUTTON_SIZE",    column = 0 },
  { key = "Spacing", textKey = "ABC_BUTTON_SPACING", column = 1 },
}

-- The pet bar's mover and its row in edit mode's Advanced Anchors drawer share
-- this one key (core/mover.lua). Enable on this page, Enable on the contextual
-- panel and that row are three views of it, never three settings: they all go
-- through U.MoverGroupEnabled / U.SetMoverGroupEnabled.
local PET_MOVER_ID = "petbar"

local function PetBarEnabled()
  if type(U.MoverGroupEnabled) ~= "function" then return true end
  local value = U.MoverGroupEnabled(PET_MOVER_ID)
  if value == nil then return true end
  return value and true or false
end

local function SetPetBarEnabled(value)
  if type(U.SetMoverGroupEnabled) ~= "function" then return end
  U.SetMoverGroupEnabled(PET_MOVER_ID, value)
end

local function BuildPetBarPage(parent)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("ABC_PET_BAR"),
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  -- Custom pet bar mode, or no native bar at this point: say so on the page
  -- rather than offer sliders that write nothing.
  if type(U.PetBarButtonsAvailable) ~= "function" or
     not U.PetBarButtonsAvailable() then
    local status = U.CreateSettingsLabel(parent, {
      size = M.fontSize.normal,
      color = M.color.textDim,
      inherits = "GameFontNormal",
      justify = "LEFT",
      height = 22,
    })
    if status then
      status:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -38)
      status:SetText(U.L("ABC_PET_UNAVAILABLE"))
      table.insert(widgets, status)
    end
    return widgets
  end

  -- Show/hide for the whole bar, the same switch as its Advanced Anchors row
  -- in edit mode and the Enable box on its contextual panel.
  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUIActionBarConfigPetEnable",
    text = U.L("COMMON_ENABLE"),
    value = PetBarEnabled(),
    onChange = function(value) SetPetBarEnabled(value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  controls.enable = enable
  table.insert(widgets, enable)

  local enableHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
  })
  if enableHint then
    U.AnchorSettingsDescription(enableHint, enable.box)
    enableHint:SetText(U.L("ABC_PET_ENABLE_HINT"))
    table.insert(widgets, enableHint)
  end

  local i
  for i = 1, table.getn(PET_SLIDERS) do
    local spec = PET_SLIDERS[i]
    local min, max, step = U.PetBarButtonLimits(spec.key)

    local slider = U.CreateSlider(parent, {
      name = "UnrealUIActionBarConfigPet" .. spec.key,
      text = U.L(spec.textKey),
      width = SLIDER_WIDTH,
      min = min,
      max = max,
      step = step,
      value = U.GetPetBarSetting(spec.key),
      onChange = function(value)
        U.SetPetBarSetting(spec.key, value)
      end,
    })
    slider.SetPoint("TOPLEFT", parent, "TOPLEFT", spec.column * COLUMN_X, ROW_Y[1])

    controls[spec.key] = slider
    table.insert(widgets, slider)
  end

  local reset = U.CreateButton(parent, {
    name = "UnrealUIActionBarConfigPetReset",
    text = U.L("ABC_PET_RESET"),
    width = 220,
    height = 26,
    onClick = function()
      U.ResetPetBarButtons()
      local j
      for j = 1, table.getn(PET_SLIDERS) do
        local key = PET_SLIDERS[j].key
        if controls[key] then controls[key].SetValue(U.GetPetBarSetting(key)) end
      end
    end,
  })
  reset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, ROW_Y[2])
  table.insert(widgets, reset)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
  })
  if hint then
    U.AnchorSettingsDescription(hint, reset)
    hint:SetText(U.L("ABC_PET_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    controls.enable.SetValue(PetBarEnabled())

    local j
    for j = 1, table.getn(PET_SLIDERS) do
      local key = PET_SLIDERS[j].key
      if controls[key] then controls[key].SetValue(U.GetPetBarSetting(key)) end
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Contextual edit-mode pet bar panel
--
-- Selecting the pet bar handle puts the same two sliders beside it, on the
-- action bar mover panel's grid so the two contextual windows are one
-- component rather than two lookalikes.
--
-- Enable is the element's show/hide, exactly as it is for an action bar: the
-- one switch behind the Advanced Anchors row, the Enable box on the Pet Bar
-- page and this one. Unticking it here therefore takes the bar out of the
-- layout and closes this panel with it; the page is where it comes back.
-- ---------------------------------------------------------------------------

-- One checkbox row and its hint above a single slider row, which is the action
-- bar panel's second row moved up by the checkbox row it does not have.
local PET_MOVER_ROW_Y = -84

local function BuildPetMoverPanel(frame, contentTop, contentWidth)
  local pad = U.MoverPanelPad()
  local widgets = {}
  local controls = {}

  local function BeginLiveEdit()
    if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
  end

  local enable = U.CreateCheckbox(frame, {
    name = "UnrealUIPetBarMoverEnable",
    text = U.L("COMMON_ENABLE"),
    textWidth = contentWidth - 20,
    value = true,
    -- No refresh of the other views from here: the switch itself reports the
    -- change to whoever shows it (U.OnMoverGroupChanged, registered below).
    onChange = function(value) SetPetBarEnabled(value) end,
  })
  enable.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
  controls.enable = enable
  table.insert(widgets, enable)

  local hint = U.CreateSettingsLabel(frame, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = contentWidth,
  })
  if hint then
    U.AnchorSettingsDescription(hint, enable.box)
    hint:SetText(U.L("ABC_PET_ENABLE_HINT"))
    table.insert(widgets, hint)
  end

  local i
  for i = 1, table.getn(PET_SLIDERS) do
    local spec = PET_SLIDERS[i]
    local key = spec.key
    local min, max, step = U.PetBarButtonLimits(key)

    local slider = U.CreateSlider(frame, {
      name = "UnrealUIPetBarMover" .. key,
      text = U.L(spec.textKey),
      width = MOVER_SLIDER_WIDTH,
      boxWidth = 60,
      min = min,
      max = max,
      step = step,
      value = min,
      onInputStart = BeginLiveEdit,
      -- The setter applies the row immediately and tells no view to re-read,
      -- so it is its own live preview: the thumb cannot be fought while it is
      -- being dragged. The committed value below is what refreshes the page.
      onInput = function(value)
        U.SetPetBarSetting(key, value)
      end,
      onChange = function(value)
        U.SetPetBarSetting(key, value)
        U.RefreshPetBarSettingsViews()
      end,
    })
    slider.SetPoint("TOPLEFT", frame, "TOPLEFT",
                    pad + spec.column * MOVER_COLUMN_X,
                    contentTop + PET_MOVER_ROW_Y)
    controls[key] = slider
    table.insert(widgets, slider)
  end

  local function Refresh()
    controls.enable.SetValue(PetBarEnabled())

    local j
    for j = 1, table.getn(PET_SLIDERS) do
      local key = PET_SLIDERS[j].key
      if controls[key] then controls[key].SetValue(U.GetPetBarSetting(key)) end
    end
  end

  return widgets, Refresh
end

local petMoverSpec = {
  name = "UnrealUIPetBarMoverSettings",
  width = MOVER_CONTENT_WIDTH + U.MoverPanelPad() * 2,
  -- Content top, the checkbox row and its hint, the slider row at -84, then
  -- the readout box (8 + 2 + 16) below its track.
  height = 182,
  build = BuildPetMoverPanel,
  -- Only reached if the pet mover ever loses its label.
  title = function() return U.L("ABC_PET_BAR") end,
  -- Custom pet bar mode, or no native bar: nothing here writes anything, so
  -- the handle stays a plain mover.
  available = function()
    return type(U.PetBarButtonsAvailable) == "function" and
           U.PetBarButtonsAvailable()
  end,
}

-- Both views of the pet row read the same store, so whichever one wrote a
-- value tells the other to re-read it -- the same contract
-- U.RefreshActionBarSettingsViews keeps for a bar.
function U.RefreshPetBarSettingsViews()
  if type(U.RefreshMoverPanel) == "function" then
    U.RefreshMoverPanel(PET_MOVER_ID)
  end
  if type(U.RefreshSettingsPage) == "function" then
    U.RefreshSettingsPage(GROUP .. ".petbar")
  end
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
    width = PAGE_WIDTH,
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

    -- The contextual panel for this bar's mover handle. One spec for every
    -- bar: core/moverpanel.lua builds it once and points it at whichever bar
    -- was selected.
    if type(U.RegisterMoverPanel) == "function" then
      U.RegisterMoverPanel(MOVER_ID_PREFIX .. bar, moverSpec)
    end
  end

  -- Last in the group: it is the client's own bar with unrealUI geometry on
  -- it, not one of unrealUI's bars.
  U.RegisterSettingsTab(GROUP .. ".petbar", U.L("ABC_PET_BAR"), BuildPetBarPage,
                        { parent = GROUP })

  -- ... and the same values beside its handle in edit mode.
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel(PET_MOVER_ID, petMoverSpec)
  end

  -- The third view of Enable is the drawer row in edit mode. It writes the
  -- same switch, so the two views here re-read it when it does.
  if type(U.OnMoverGroupChanged) == "function" then
    U.OnMoverGroupChanged(PET_MOVER_ID, U.RefreshPetBarSettingsViews)
  end
end
