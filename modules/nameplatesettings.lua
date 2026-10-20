-- unrealUI :: modules/nameplatesettings.lua
--
-- The Nameplates settings group: General, Health, Target and Raid Mark pages.
-- State and behaviour stay in modules/nameplates.lua; every control here reads
-- through U.NameplateSetting and writes through U.SetNameplateSetting, which
-- redraws the live plates at once.
--
-- Each page is a list of control specs laid out top to bottom by one builder,
-- so a new option is one spec line plus its locale keys. Option scope follows
-- ShaguPlates' nameplate settings (diagnostics/shaguplates-index), trimmed to
-- what this client and UnrealUI's design rules support; NAMEPLATES_ROADMAP.md
-- records the rest.

local U = UnrealUI
local M = U.media

local nps = {
  GROUP = "nameplates",
  PAGE_WIDTH = 484,
  COL2 = 250,       -- second column, x
  HALF_TEXT = 220,  -- label width of a two-column checkbox
  SLIDER_WIDTH = 200,
  HINT_LINE = 13,   -- reserve per wrapped description line
}

-- Vertical space each control type takes from its own top to the next one's.
nps.ADVANCE = { header = 30, check = 24, color = 24, slider = 64,
                dropdown = 48 }

-- Dropdown item lists.
nps.ITEMS = {
  healthFormat = {
    { value = "percent", key = "NP_FORMAT_PERCENT" },
    { value = "current", key = "NP_FORMAT_CURRENT" },
    { value = "curmax",  key = "NP_FORMAT_CURMAX" },
    { value = "curperc", key = "NP_FORMAT_CURPERC" },
    { value = "deficit", key = "NP_FORMAT_DEFICIT" },
  },
  healthTextPos = {
    { value = "LEFT",   key = "NP_POS_LEFT" },
    { value = "CENTER", key = "NP_POS_CENTER" },
    { value = "RIGHT",  key = "NP_POS_RIGHT" },
  },
  raidIconPos = {
    { value = "LEFT",  key = "NP_POS_LEFT" },
    { value = "TOP",   key = "NP_POS_TOP" },
    { value = "RIGHT", key = "NP_POS_RIGHT" },
  },
}

-- Page specs. type: header | check | slider | dropdown | color | note.
--   key      nameplate setting (U.NameplateSetting); "enabled" is special
--   col = 2  shares the previous control's row, in the second column
--   scale    slider shows setting * scale (a 0..1 alpha as a percentage)
--   flat     only under a theme other than modern-wow
--   art      only under modern-wow
--   hint     locale key of a description anchored 5 below the control
--   disabled slider drawn in its disabled state, no input
nps.PAGES = {
  {
    id = "general", label = "NP_TAB_GENERAL",
    { type = "header", text = "NP_HEADER_DISPLAY" },
    { type = "check", key = "enabled", text = "SETTINGS_NAMEPLATES" },
    { type = "check", key = "showHostile", text = "NP_SHOW_HOSTILE" },
    { type = "check", key = "showFriendly", text = "NP_SHOW_FRIENDLY", col = 2 },
    { type = "note", text = "NP_VISIBILITY_HINT", lines = 2 },
    { type = "check", key = "showAuras", text = "SETTINGS_NAMEPLATE_AURAS" },
    { type = "check", key = "attachTargetCast",
      text = "SETTINGS_NAMEPLATE_CASTBAR" },
    { type = "check", key = "showName", text = "NP_SHOW_NAME" },
    { type = "check", key = "abbrevNames", text = "NP_ABBREV_NAMES", col = 2 },
    { type = "header", text = "NP_HEADER_CLASS" },
    { type = "check", key = "classColorEnemy", text = "NP_CLASS_ENEMY" },
    { type = "check", key = "classColorFriendly", text = "NP_CLASS_FRIENDLY",
      col = 2 },
    { type = "check", key = "classColorFriendlyName",
      text = "NP_CLASS_FRIENDLY_NAME" },
    { type = "check", key = "showGuild", text = "NP_SHOW_GUILD", col = 2 },
    { type = "note", text = "NP_CLASS_HINT", lines = 3 },
    { type = "header", text = "NP_HEADER_SIZE" },
    { type = "slider", key = "width", text = "NP_WIDTH",
      min = 80, max = 240, step = 5 },
    { type = "slider", key = "healthHeight", text = "NP_HEALTH_HEIGHT",
      min = 6, max = 30, step = 1, col = 2, flat = true },
    { type = "slider", key = "artHealthHeight", text = "NP_HEALTH_HEIGHT",
      min = 10, max = 40, step = 1, col = 2, art = true },
    { type = "slider", key = "verticalOffset", text = "NP_VERTICAL_OFFSET",
      min = -40, max = 40, step = 1 },
    -- Disabled: the client does not apply a new size to the level text yet
    -- (user report, 2026-10-20).
    { type = "slider", key = "levelSize", text = "NP_LEVEL_SIZE",
      min = 8, max = 18, step = 1, col = 2, disabled = true },
    { type = "slider", key = "nameSize", text = "NP_NAME_SIZE",
      min = 8, max = 18, step = 1 },
    { type = "slider", key = "healthTextSize", text = "NP_HEALTH_TEXT_SIZE",
      min = 8, max = 16, step = 1, col = 2 },
  },
  {
    id = "health", label = "NP_TAB_HEALTH",
    { type = "header", text = "NP_HEADER_HEALTH_TEXT" },
    { type = "check", key = "showHealthText", text = "NP_SHOW_HEALTH_TEXT" },
    { type = "check", key = "abbrevNumbers", text = "NP_ABBREV_NUMBERS",
      col = 2 },
    { type = "dropdown", key = "healthFormat", text = "NP_HEALTH_FORMAT" },
    { type = "dropdown", key = "healthTextPos", text = "NP_HEALTH_POS",
      col = 2 },
    { type = "header", text = "NP_HEADER_HIDE_HEALTH" },
    { type = "check", key = "hideEnemyNpc", text = "NP_HIDE_ENEMY_NPC" },
    { type = "check", key = "hideEnemyPlayer", text = "NP_HIDE_ENEMY_PLAYER",
      col = 2 },
    { type = "check", key = "hideNeutralNpc", text = "NP_HIDE_NEUTRAL_NPC" },
    { type = "check", key = "hideCritterHealth", text = "NP_HIDE_CRITTER",
      col = 2 },
    { type = "check", key = "hideFriendlyNpc", text = "NP_HIDE_FRIENDLY_NPC" },
    { type = "check", key = "hideFriendlyPlayer",
      text = "NP_HIDE_FRIENDLY_PLAYER", col = 2 },
    { type = "check", key = "keepHealthTarget", text = "NP_KEEP_TARGET" },
    { type = "check", key = "keepHealthDamaged", text = "NP_KEEP_DAMAGED",
      col = 2 },
    { type = "note", text = "NP_HIDE_HINT", lines = 3 },
    { type = "header", text = "NP_HEADER_TOTEMS" },
    { type = "check", key = "hideTotemHealth", text = "NP_HIDE_TOTEM_HEALTH" },
    { type = "check", key = "totemIcons", text = "NP_TOTEM_ICONS", col = 2 },
    { type = "slider", key = "totemSize", text = "NP_TOTEM_SIZE",
      min = 12, max = 48, step = 1 },
    { type = "note", text = "NP_TOTEM_HINT", lines = 2 },
  },
  {
    id = "target", label = "NP_TAB_TARGET",
    { type = "header", text = "NP_HEADER_TARGET" },
    { type = "check", key = "fadeOthers", text = "NP_FADE_OTHERS" },
    { type = "check", key = "targetZoom", text = "NP_TARGET_ZOOM", col = 2 },
    { type = "slider", key = "otherAlpha", text = "NP_OTHER_ALPHA",
      min = 10, max = 100, step = 5, scale = 100 },
    { type = "slider", key = "targetZoomPercent", text = "NP_TARGET_ZOOM_VALUE",
      min = 5, max = 60, step = 5, col = 2 },
    { type = "check", key = "targetOutline", text = "NP_TARGET_OUTLINE" },
    { type = "color", key = "highlight", text = "NP_HIGHLIGHT_COLOR",
      col = 2 },
    { type = "header", text = "NP_HEADER_OUTLINES" },
    { type = "check", key = "outlineEnemy", text = "NP_OUTLINE_ENEMY" },
    { type = "check", key = "outlineNeutral", text = "NP_OUTLINE_NEUTRAL",
      col = 2 },
    { type = "check", key = "outlineFriendlyNpc",
      text = "NP_OUTLINE_FRIENDLY_NPC" },
    { type = "check", key = "outlineFriendlyPlayer",
      text = "NP_OUTLINE_FRIENDLY_PLAYER", col = 2 },
    { type = "header", text = "NP_HEADER_COMBO" },
    { type = "check", key = "comboPoints", text = "NP_COMBO_POINTS" },
    { type = "slider", key = "comboSize", text = "NP_COMBO_SIZE",
      min = 4, max = 20, step = 1 },
  },
  {
    id = "raidicon", label = "NP_TAB_RAIDICON",
    { type = "header", text = "NP_HEADER_RAIDICON" },
    { type = "check", key = "raidIcon", text = "NP_RAID_ICON" },
    { type = "note", text = "NP_RAID_ICON_HINT", lines = 3 },
    { type = "dropdown", key = "raidIconPos", text = "NP_RAID_ICON_POS" },
    { type = "slider", key = "raidIconSize", text = "NP_RAID_ICON_SIZE",
      min = 8, max = 40, step = 1, col = 2 },
    { type = "slider", key = "raidIconX", text = "NP_RAID_ICON_X",
      min = -40, max = 40, step = 1 },
    { type = "slider", key = "raidIconY", text = "NP_RAID_ICON_Y",
      min = -40, max = 40, step = 1, col = 2 },
  },
}

function nps.Get(key)
  if key == "enabled" then return U.NameplatesEnabled() end
  return U.NameplateSetting(key)
end

function nps.Set(key, value)
  if key == "enabled" then
    U.SetNameplatesEnabled(value)
  else
    U.SetNameplateSetting(key, value)
  end
end

function nps.Caption(parent, text, width)
  local label = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = width,
    height = 14,
  })
  if label then label:SetText(text) end
  return label
end

-- One control from its spec at (x, y). Returns the control (or nil) and the
-- function that re-reads its value when the page is shown again.
function nps.Build(parent, spec, x, y, twoColumn)
  local name = "UnrealUISettingsNameplate" .. (spec.key or "")
  local kind = spec.type

  if kind == "check" then
    local control = U.CreateCheckbox(parent, {
      name = name,
      text = U.L(spec.text),
      value = nps.Get(spec.key),
      textWidth = twoColumn and nps.HALF_TEXT or nil,
      onChange = function(value) nps.Set(spec.key, value) end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return control, function() control.SetValue(nps.Get(spec.key)) end
  end

  if kind == "slider" then
    local scale = spec.scale or 1
    local control = U.CreateSlider(parent, {
      name = name,
      text = U.L(spec.text),
      width = nps.SLIDER_WIDTH,
      min = spec.min,
      max = spec.max,
      step = spec.step,
      value = (tonumber(nps.Get(spec.key)) or 0) * scale,
      disabled = spec.disabled,
      onChange = function(value) nps.Set(spec.key, value / scale) end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
    return control, function()
      control.SetValue((tonumber(nps.Get(spec.key)) or 0) * scale)
    end
  end

  if kind == "dropdown" then
    local items = {}
    local i
    for i = 1, table.getn(nps.ITEMS[spec.key]) do
      local item = nps.ITEMS[spec.key][i]
      table.insert(items, { value = item.value, text = U.L(item.key) })
    end
    local caption = nps.Caption(parent, U.L(spec.text), nps.SLIDER_WIDTH)
    local control = U.CreateDropdown(parent, {
      name = name,
      width = nps.SLIDER_WIDTH,
      height = 24,
      rowHeight = 20,
      value = nps.Get(spec.key),
      items = items,
      onChange = function(value) nps.Set(spec.key, value) end,
    })
    if caption then caption:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    control.uuiCaption = caption
    return control, function() control.SetValue(nps.Get(spec.key), false) end
  end

  if kind == "color" then
    local function Value()
      return { r = nps.Get(spec.key .. "R"), g = nps.Get(spec.key .. "G"),
               b = nps.Get(spec.key .. "B"), a = 1 }
    end
    local control = U.CreateColorPicker(parent, {
      name = name,
      text = U.L(spec.text),
      value = Value(),
      hasOpacity = false,
      textWidth = twoColumn and nps.HALF_TEXT or nil,
      onChange = function(color)
        nps.Set(spec.key .. "R", color.r)
        nps.Set(spec.key .. "G", color.g)
        nps.Set(spec.key .. "B", color.b)
      end,
    })
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return control, function() control.SetValue(Value()) end
  end

  return nil
end

-- The control a description is anchored under, per its widget type.
function nps.AnchorOf(control)
  if not control then return nil end
  return control.box or control.button or control.swatch
end

function nps.BuildPage(parent, page)
  local widgets, refreshers = {}, {}
  local modernWow = U.GetActiveThemeStyle and
                    U.GetActiveThemeStyle() == "modern-wow"
  local y, rowY = -4, -4
  -- last: the row's first-column control, which a note describes and a
  -- second-column control shares a row with. Cleared by a header, a note or
  -- a skipped spec, so a second-column control never joins a finished row.
  local last
  local i

  local function Skipped(spec)
    return spec and ((spec.flat and modernWow) or
                     (spec.art and not modernWow)) and true or false
  end

  for i = 1, table.getn(page) do
    local spec = page[i]
    if Skipped(spec) then
      if spec.col ~= 2 then last = nil end
    else
      if spec.type == "header" then
        table.insert(widgets, U.CreateSectionHeader(parent, {
          text = U.L(spec.text),
          width = nps.PAGE_WIDTH,
          y = y,
        }))
        y = y - nps.ADVANCE.header
        last = nil
      elseif spec.type == "note" then
        -- A description of the control just above it, or, after a header, a
        -- plain paragraph at the current row.
        local note = U.CreateSettingsLabel(parent, {
          size = M.fontSize.small,
          color = M.color.textDim,
          inherits = "GameFontNormalSmall",
          justify = "LEFT",
          width = nps.PAGE_WIDTH,
        })
        if note then
          note:SetText(U.L(spec.text))
          local anchor = nps.AnchorOf(last)
          if anchor then
            U.AnchorSettingsDescription(note, anchor)
          else
            note:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
          end
          table.insert(widgets, note)
        end
        y = y - (spec.lines or 1) * nps.HINT_LINE - 12
        last = nil
      else
        local second = spec.col == 2 and last ~= nil
        local x = second and nps.COL2 or 0
        local rowTop = second and rowY or y
        -- A first-column control knows whether a second shares its row.
        local nextSpec = page[i + 1]
        local paired = second or
                       (nextSpec and nextSpec.col == 2 and
                        not Skipped(nextSpec)) and true or false
        local control, refresh = nps.Build(parent, spec, x, rowTop, paired)
        if control then
          table.insert(widgets, control)
          if control.uuiCaption then table.insert(widgets, control.uuiCaption) end
          if refresh then table.insert(refreshers, refresh) end
        end
        if not second then
          rowY = y
          y = y - (nps.ADVANCE[spec.type] or 24)
          last = control
        end
      end
    end
  end

  local function Refresh()
    local n
    for n = 1, table.getn(refreshers) do refreshers[n]() end
  end
  return widgets, Refresh
end

function U.RegisterNameplateSettings()
  if type(U.RegisterSettingsGroup) ~= "function" then return end
  U.RegisterSettingsGroup(nps.GROUP, U.L("SETTINGS_PAGE_NAMEPLATES"),
                          { after = "general",
                            defaultPage = nps.GROUP .. ".general" })
  -- Each page is placed explicitly after the one before it (the first after
  -- the group). Without "after", RegisterSettingsTab appends ahead of
  -- Profiles, which put these pages under the last group in the list.
  local previous = nps.GROUP
  local i
  for i = 1, table.getn(nps.PAGES) do
    local page = nps.PAGES[i]
    local id = nps.GROUP .. "." .. page.id
    U.RegisterSettingsTab(id, U.L(page.label),
                          function(parent) return nps.BuildPage(parent, page) end,
                          { parent = nps.GROUP, after = previous })
    previous = id
  end
end
