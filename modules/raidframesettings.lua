-- unrealUI :: modules/raidframesettings.lua
--
-- The Raid Frames settings group (user request, 2026-10-21): what each cell
-- shows, and its size -- one width shared by the health and power bars, and
-- a height for each. State and drawing stay in modules/raidframes.lua; every
-- control reads U.GetRaidFrameSetting and writes U.SetRaidFrameSetting, which
-- relays out the live frames at once. Built with the same control specs and
-- shared widgets as modules/nameplatesettings.lua.

local U = UnrealUI
local M = U.media

local rfs = {
  GROUP = "raidframes",
  PAGE_WIDTH = U.SETTINGS_PAGE_WIDTH,
  COL2 = U.SETTINGS_COLUMN_X,
  HALF_TEXT = U.SETTINGS_COLUMN_WIDTH - 26,
  SLIDER_WIDTH = 200,
  refresh = nil,     -- the shown page's re-read, for /uui raid toggles
}

rfs.ADVANCE = { header = 30, check = 24, slider = 64, dropdown = 48 }

-- Dropdown labels, keyed by setting value.
rfs.ITEM_TEXT = {
  legacy = "RF_ORG_LEGACY",
  buffsTop = "RF_ORG_BUFFS_TOP",
  buffsRight = "RF_ORG_BUFFS_RIGHT",
  off = "RF_DISPEL_OFF",
  mine = "RF_DISPEL_MINE",
  all = "RF_DISPEL_ALL",
}

-- Each dropdown's values, from modules/raidframes.lua.
rfs.ITEMS = {
  auraOrganization = function() return U.RaidFrameOrganizations() end,
  dispelIndicator = function() return U.RaidFrameDispelIndicators() end,
}

-- type: header | check | slider | dropdown | note. col = 2 shares the previous row; a
-- note describes the control just above it.
-- Enable sits alone at the top (user request, 2026-10-21): it switches the
-- whole module off so another raid addon or the client's own raid UI can be
-- used instead.
rfs.PAGE = {
  { type = "check", key = "enabled", text = "RF_ENABLED" },
  { type = "note", text = "RF_ENABLED_HINT", lines = 2 },
  { type = "header", text = "RF_HEADER_DISPLAY" },
  { type = "check", key = "showPower", text = "RF_SHOW_POWER" },
  { type = "check", key = "showDebuffs", text = "RF_SHOW_DEBUFFS", col = 2 },
  { type = "check", key = "showHots", text = "RF_SHOW_HOTS" },
  { type = "check", key = "healPrediction", text = "RF_HEAL_PREDICTION",
    col = 2 },
  { type = "check", key = "groupTitles", text = "RF_GROUP_TITLES" },
  { type = "check", key = "groupBorder", text = "RF_GROUP_BORDER", col = 2 },
  -- Forever's raid-frame buff options (Edit Mode): Aura Organization and
  -- Buff Icon Size. Its Display Buffs is "Show my heals over time" above.
  { type = "header", text = "RF_HEADER_AURAS" },
  { type = "dropdown", key = "auraOrganization", text = "RF_AURA_ORGANIZATION" },
  { type = "slider", key = "buffIconSize", text = "RF_BUFF_ICON_SIZE",
    col = 2 },
  -- Forever's debuff filter and dispel indicator (user decisions,
  -- 2026-10-21): on and "mine" by default.
  { type = "check", key = "onlyDispellable", text = "RF_ONLY_DISPELLABLE" },
  { type = "note", text = "RF_ONLY_DISPELLABLE_HINT", lines = 2 },
  { type = "dropdown", key = "dispelIndicator", text = "RF_DISPEL_INDICATOR" },
  { type = "header", text = "RF_HEADER_SIZE" },
  { type = "slider", key = "width", text = "RF_WIDTH" },
  { type = "slider", key = "healthHeight", text = "RF_HEALTH_HEIGHT", col = 2 },
  { type = "slider", key = "powerHeight", text = "RF_POWER_HEIGHT" },
}

function rfs.Build(parent, spec, x, y, paired)
  local name = "UnrealUISettingsRaid" .. (spec.key or "")

  if spec.type == "check" then
    local control = U.CreateCheckbox(parent, {
      name = name,
      text = U.L(spec.text),
      value = U.GetRaidFrameSetting(spec.key) and true or false,
      textWidth = paired and rfs.HALF_TEXT or nil,
      onChange = function(value) U.SetRaidFrameSetting(spec.key, value) end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return control, function()
      control.SetValue(U.GetRaidFrameSetting(spec.key) and true or false)
    end
  end

  if spec.type == "slider" then
    local limit = U.RaidFrameLimits(spec.key)
    local control = U.CreateSlider(parent, {
      name = name,
      text = U.L(spec.text),
      width = rfs.SLIDER_WIDTH,
      min = limit.min,
      max = limit.max,
      step = limit.step,
      value = tonumber(U.GetRaidFrameSetting(spec.key)) or limit.min,
      onChange = function(value) U.SetRaidFrameSetting(spec.key, value) end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
    return control, function()
      control.SetValue(tonumber(U.GetRaidFrameSetting(spec.key)) or limit.min)
    end
  end

  if spec.type == "dropdown" then
    local items = {}
    local list = rfs.ITEMS[spec.key]()
    local i
    for i = 1, table.getn(list) do
      table.insert(items, { value = list[i],
                            text = U.L(rfs.ITEM_TEXT[list[i]]) })
    end
    local caption = U.CreateSettingsLabel(parent, {
      size = M.fontSize.small,
      color = M.color.accent,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = rfs.SLIDER_WIDTH,
      height = 14,
    })
    if caption then
      caption:SetText(U.L(spec.text))
      caption:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    local control = U.CreateDropdown(parent, {
      name = name,
      width = rfs.SLIDER_WIDTH,
      height = 24,
      rowHeight = 20,
      value = U.GetRaidFrameSetting(spec.key),
      items = items,
      onChange = function(value) U.SetRaidFrameSetting(spec.key, value) end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    control.uuiCaption = caption
    return control, function()
      control.SetValue(U.GetRaidFrameSetting(spec.key), false)
    end
  end

  return nil
end

function rfs.BuildPage(parent)
  local widgets, refreshers = {}, {}
  local y, rowY = -4, -4
  local last
  local i

  for i = 1, table.getn(rfs.PAGE) do
    local spec = rfs.PAGE[i]
    if spec.type == "note" then
      local note = U.CreateSettingsLabel(parent, {
        size = M.fontSize.small,
        color = M.color.textDim,
        inherits = "GameFontNormalSmall",
        justify = "LEFT",
        width = rfs.PAGE_WIDTH,
      })
      if note then
        note:SetText(U.L(spec.text))
        local anchor = last and (last.box or last.button)
        if anchor then
          U.AnchorSettingsDescription(note, anchor)
        else
          note:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        end
        table.insert(widgets, note)
      end
      y = y - (spec.lines or 1) * 13 - 12
      last = nil
    elseif spec.type == "header" then
      table.insert(widgets, U.CreateSectionHeader(parent, {
        text = U.L(spec.text),
        width = rfs.PAGE_WIDTH,
        y = y,
      }))
      y = y - rfs.ADVANCE.header
      last = nil
    else
      local second = spec.col == 2 and last ~= nil
      local x = second and rfs.COL2 or 0
      local rowTop = second and rowY or y
      local nextSpec = rfs.PAGE[i + 1]
      local paired = second or (nextSpec and nextSpec.col == 2) and true or
                     false
      local control, refresh = rfs.Build(parent, spec, x, rowTop, paired)
      if control then
        table.insert(widgets, control)
        if control.uuiCaption then table.insert(widgets, control.uuiCaption) end
        if refresh then table.insert(refreshers, refresh) end
      end
      if not second then
        rowY = y
        y = y - (rfs.ADVANCE[spec.type] or 24)
        last = control
      end
    end
  end

  local function Refresh()
    local n
    for n = 1, table.getn(refreshers) do refreshers[n]() end
  end
  rfs.refresh = Refresh
  return widgets, Refresh
end

-- Keeps an open page in step with a /uui raid toggle.
function U.RefreshRaidFrameSettingsView()
  if rfs.refresh then rfs.refresh() end
end

function U.RegisterRaidFrameSettings()
  if type(U.RegisterSettingsGroup) ~= "function" then return end
  U.RegisterSettingsGroup(rfs.GROUP, U.L("SETTINGS_PAGE_RAID"),
                          { defaultPage = rfs.GROUP .. ".general" })
  U.RegisterSettingsTab(rfs.GROUP .. ".general", U.L("RF_TAB_GENERAL"),
                        function(parent) return rfs.BuildPage(parent) end,
                        { parent = rfs.GROUP, after = rfs.GROUP })
end
