-- unrealUI :: modules/unitframeconfig.lua
--
-- The contextual settings panels for the player, target and party unit frame
-- movers.
--
-- Selecting one of those handles in edit mode puts its own settings beside it,
-- the way selecting an action bar does (modules/actionbarconfig.lua). Only the
-- settings that are about the frame just clicked are on its panel: the player
-- gets the power tick that rides its power bar, the incoming-heal fill on its
-- health bar and the aura rows it carries; the target gets the exact creature
-- health its readout prints, the same incoming-heal fill on its own bar, and
-- its own aura rows. Both carry the combo-point anchor, because that setting is
-- the choice of which of the two frames draws the points. Everything else about
-- those frames stays on the Unit Frames pages. The party panel carries its two
-- layout switches and the HoT controls drawn on its member rows. Every panel is
-- a second view of the settings page, never a second configuration -- they read
-- and write through the same accessors.
--
-- The window, its placement beside the handle and its lifecycle belong to
-- core/moverpanel.lua. This file is in its own module rather than inside
-- modules/unitframes.lua because that file is close to Lua's 200 top-level
-- local limit (rules/unreal-ui.md, "Lua local budget").

local U = UnrealUI
local M = U.media

local UFC = U.RegisterModule("unitframeconfig")

-- The movers modules/unitframes.lua registers for these frames. The values
-- shown here are also on the Unit Frames pages; U.RefreshUnitFrameSettingsViews
-- (modules/unitframes.lua) keeps the views in step.
local PLAYER_MOVER_ID = "unitframes.player"
local TARGET_MOVER_ID = "unitframes.target"
local PARTY_MOVER_ID = "unitframes.party"

-- Two columns, the same shape the settings pages use, kept narrow enough to sit
-- beside the frame at its default position instead of being pushed above it.
-- Every label here is a short one for that reason: the long descriptive wording
-- stays on the settings page, where there is room for it in every locale.
-- LABEL_WIDTH leaves the checkbox square and its 6-unit gap inside the column,
-- so the widest translation of a caption cannot run into the column beside it.
local COLUMN_X = 164
local CONTENT_WIDTH = COLUMN_X * 2
local ROW_PITCH = 22
local LABEL_WIDTH = COLUMN_X - 20
-- The combo dropdown sits in the left column only; it needs no second column
-- and a full-width selector would read as the panel's own control rather than
-- the section's.
local DROPDOWN_WIDTH = 200

-- The party panel carries the two layout switches and the complete HoT section
-- from the Party Frames page. Its slider columns reuse the action-bar mover
-- panel's compact proportions so the window remains narrow enough to sit next
-- to the party block at its default left-edge position.
local PARTY_LAYOUT = {
  hotCaption = 58,
  hotEnabled = 80,
  cornerLabel = 110,
  corner = 126,
  sliders = 182,
  sliderWidth = 150,
  sliderColumn = 168,
  height = 270,
}

local PARTY_HOT_SLIDERS = {
  { key = "size", textKey = "HOTS_SIZE", column = 0 },
  { key = "spacing", textKey = "HOTS_SPACING", column = 1 },
}

-- A caption sits 30 below the last row of the group above it and 22 above its
-- own first row, which is the spacing the settings pages use between a heading
-- and its controls.
local CAPTION_GAP = 30
local CAPTION_TO_ROW = 22

-- Combo points are drawn for the two classes that have them. The player's class
-- cannot change inside a session, so the section is built or left out once,
-- rather than being shown and hidden on every refresh.
local function ComboClass()
  local class = type(U.PlayerClassToken) == "function" and U.PlayerClassToken()
  return class == "DRUID" or class == "ROGUE"
end

-- How many rows a group fills, taken from the rows its own specs claim.
local function RowCount(specs)
  local rows, i = 0, nil
  for i = 1, table.getn(specs) do
    if specs[i].row + 1 > rows then rows = specs[i].row + 1 end
  end
  return rows
end

-- Rows below the shared content top, for one panel. The groups stay separate
-- blocks: what the frame itself draws first, then the aura rows it carries
-- under their own caption, then the combo section for the classes that have
-- one. Each value is the top of the row it names, so a group's own last row is
-- what the caption below it measures from.
local function Layout(def)
  if def.layout then return def.layout end
  local layout = {}
  layout.frameBottom = (RowCount(def.toggles) - 1) * ROW_PITCH
  layout.auraCaption = layout.frameBottom + CAPTION_GAP
  layout.auraRow = layout.auraCaption + CAPTION_TO_ROW
  layout.auraBottom = layout.auraRow + (RowCount(def.auras) - 1) * ROW_PITCH
  layout.comboCaption = layout.auraBottom + CAPTION_GAP
  layout.comboRow = layout.comboCaption + CAPTION_TO_ROW
  def.layout = layout
  return layout
end

-- How far the content reaches below the content top, plus the panel's own
-- inset: the last checkbox is 14 high, the combo dropdown 24.
local function PanelHeight(def)
  local layout = Layout(def)
  local bottom = layout.auraBottom + 14
  if ComboClass() then bottom = layout.comboRow + 24 end
  return -U.MoverPanelContentTop() + bottom + 12
end

-- Places one checkbox in the two-column grid: column 0 or 1, row counted from
-- the group's own first row.
local function PlaceToggle(toggle, frame, pad, contentTop, groupY, column, row)
  toggle.SetPoint("TOPLEFT", frame, "TOPLEFT", pad + column * COLUMN_X,
                  contentTop - groupY - row * ROW_PITCH)
end

-- The short accent caption a group in this panel gets instead of a ruled
-- section header: a heading with rules leaves no room for the longer
-- translations at this width. Same treatment the colour page gives its
-- power-bar swatches.
local function AddCaption(frame, widgets, pad, y, text, width)
  local caption = U.CreateSettingsLabel(frame, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = width,
  })
  if not caption then return nil end
  caption:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, y)
  caption:SetText(text)
  table.insert(widgets, caption)
  return caption
end

-- The player frame's own group, filling its columns left to right. A spec
-- carries its own accessors because the values come from three modules: the
-- power tick and combo anchor from modules/unitframes.lua, the incoming-heal
-- fill from modules/healpredict.lua and the aura rows from modules/auras.lua.
-- Every one of them is the same accessor the settings pages write through.
local PLAYER_TOGGLES = {
  { key = "manaTick", textKey = "UF_MANA_TICK", column = 0, row = 0,
    get = function() return U.GetUnitFramePowerTick("manaTick") end,
    set = function(value) U.SetUnitFramePowerTick("manaTick", value) end },
  { key = "energyTick", textKey = "UF_ENERGY_TICK", column = 1, row = 0,
    get = function() return U.GetUnitFramePowerTick("energyTick") end,
    set = function(value) U.SetUnitFramePowerTick("energyTick", value) end },
  { key = "healPredict", textKey = "UF_MOVER_INCOMING_HEALS", column = 0, row = 1,
    get = function()
      return type(U.GetHealPredictSetting) == "function" and
             U.GetHealPredictSetting("enabled")
    end,
    set = function(value)
      if type(U.SetHealPredictSetting) == "function" then
        U.SetHealPredictSetting("enabled", value)
      end
    end },
}

-- The target frame's own group. Exact creature health is the setting that is
-- only about this frame: this client reports a non-group unit's health as a
-- percentage, and the readout that replaces it is drawn here
-- (core/unitvitals.lua). The incoming-heal fill is one shared toggle that
-- paints the target's health bar as well, which is why it is on both panels.
local TARGET_TOGGLES = {
  { key = "exactVitals", textKey = "UF_MOVER_EXACT_VITALS", column = 0, row = 0,
    get = function()
      return type(U.GetExactVitals) == "function" and U.GetExactVitals()
    end,
    set = function(value)
      if type(U.SetExactVitals) == "function" then U.SetExactVitals(value) end
    end },
  { key = "healPredict", textKey = "UF_MOVER_INCOMING_HEALS", column = 1, row = 0,
    get = function()
      return type(U.GetHealPredictSetting) == "function" and
             U.GetHealPredictSetting("enabled")
    end,
    set = function(value)
      if type(U.SetHealPredictSetting) == "function" then
        U.SetHealPredictSetting("enabled", value)
      end
    end },
}

-- Kept as their own block rather than filling the gaps in the group above: the
-- aura rows are a separate feature with a separate settings page, and reading
-- them as one section is what says which caption they belong to. A spec with no
-- getter of its own is one of modules/auras.lua's keys.
--
-- showOnPlayerFrame is the one that is only about the player frame; the timers
-- and the above/below side are the module's shared settings, and the Auras page
-- keeps the longer wording that says so. The target's group below is the same
-- three toggles with its own location switch in front.
local PLAYER_AURA_TOGGLES = {
  { key = "showOnPlayerFrame", textKey = "UF_MOVER_AURAS_ENABLED",
    column = 0, row = 0 },
  { key = "showTimers", textKey = "UF_MOVER_AURAS_TIMERS",
    column = 1, row = 0 },
  { key = "belowFrame", textKey = "UF_MOVER_AURAS_BELOW",
    column = 0, row = 1 },
}

-- The same three, one frame over: showOnTargetFrame is the target's own
-- location switch, and it gates that frame's debuff and buff rows as a unit the
-- way showOnPlayerFrame gates the player's. Which of the two rows is drawn
-- stays on the Auras page, where each has its own checkbox under this switch --
-- the panel carries the one simple option, not the pair.
local TARGET_AURA_TOGGLES = {
  { key = "showOnTargetFrame", textKey = "UF_MOVER_AURAS_ENABLED",
    column = 0, row = 0 },
  { key = "showTimers", textKey = "UF_MOVER_AURAS_TIMERS",
    column = 1, row = 0 },
  { key = "belowFrame", textKey = "UF_MOVER_AURAS_BELOW",
    column = 0, row = 1 },
}

local function AuraValue(key)
  return type(U.GetAuraSetting) == "function" and
         U.GetAuraSetting(key) and true or false
end

local function SetAuraValue(key, value)
  if type(U.SetAuraSetting) == "function" then
    U.SetAuraSetting(key, value and true or false)
  end
end

-- A spec either brings its own getter or is one of the aura keys. Written as a
-- branch rather than an `or` chain so a spec whose own getter answers false is
-- not asked the aura store for a key it does not own.
local function SpecValue(spec)
  if spec.get then return spec.get() and true or false end
  return AuraValue(spec.key)
end

-- Builds one group into the shared column grid. get/set come from the spec for
-- a frame group; an aura group shares one pair of accessors keyed by name. The
-- widget name carries the panel's own prefix, since the two panels hold toggles
-- for the same key and a widget name is global.
local function BuildGroup(frame, pad, contentTop, groupY, specs, widgets,
                          controls, namePrefix)
  local i
  for i = 1, table.getn(specs) do
    local spec = specs[i]
    local key = spec.key
    local toggle = U.CreateCheckbox(frame, {
      name = namePrefix .. key,
      text = U.L(spec.textKey),
      textWidth = LABEL_WIDTH,
      value = SpecValue(spec),
      onChange = function(value)
        if spec.set then spec.set(value) else SetAuraValue(key, value) end
      end,
    })
    PlaceToggle(toggle, frame, pad, contentTop, groupY, spec.column, spec.row)
    controls[key] = toggle
    table.insert(widgets, toggle)
  end
end

local function RefreshGroup(specs, controls)
  local i
  for i = 1, table.getn(specs) do
    local spec = specs[i]
    local control = controls[spec.key]
    if control then control.SetValue(SpecValue(spec)) end
  end
end

-- One panel's builder, in the shape core/moverpanel.lua asks for. def is a
-- panel definition below; the two panels differ only in the specs they carry
-- and what their widgets are named.
local function BuildPanel(def, frame, contentTop, contentWidth)
  local pad = U.MoverPanelPad()
  local layout = Layout(def)
  local widgets = {}
  local controls = {}

  BuildGroup(frame, pad, contentTop, 0, def.toggles, widgets, controls,
             def.namePrefix)

  -- The aura rows this frame carries (modules/auras.lua).
  AddCaption(frame, widgets, pad, contentTop - layout.auraCaption,
             U.L("UF_TAB_AURAS"), contentWidth)
  BuildGroup(frame, pad, contentTop, layout.auraRow, def.auras, widgets,
             controls, def.namePrefix)

  -- Which of the two frames draws the points. It is one stored value, so both
  -- panels show it and either one may write it.
  if ComboClass() then
    AddCaption(frame, widgets, pad, contentTop - layout.comboCaption,
               U.L("UF_COMBO_POINTS_HEADER"), contentWidth)

    local anchor = U.CreateDropdown(frame, {
      name = def.namePrefix .. "ComboAnchor",
      width = DROPDOWN_WIDTH,
      height = 24,
      rowHeight = 20,
      value = U.GetComboPointAnchor(),
      items = {
        { value = "player", text = U.L("UF_COMBO_POINTS_PLAYER_FRAME") },
        { value = "target", text = U.L("UF_COMBO_POINTS_TARGET_FRAME") },
      },
      onChange = function(value)
        U.SetComboPointAnchor(value)
      end,
    })
    anchor.SetPoint("TOPLEFT", frame, "TOPLEFT", pad,
                    contentTop - layout.comboRow)
    controls.comboAnchor = anchor
    table.insert(widgets, anchor)
  end

  -- Called on every show, and again whenever a settings page or the other panel
  -- writes one of these values while this one is up.
  local function Refresh()
    RefreshGroup(def.toggles, controls)
    RefreshGroup(def.auras, controls)
    if controls.comboAnchor then
      controls.comboAnchor.SetValue(U.GetComboPointAnchor())
    end
  end

  return widgets, Refresh
end

-- The party block's own contextual panel. The title already names the selected
-- Party mover, so the two frame-layout switches begin immediately below it;
-- the HoT controls keep their own accent caption because they are a distinct
-- feature drawn on those frames. Every callback uses the same accessors as the
-- Party Frames settings page.
local function BuildPartyPanel(frame, contentTop, contentWidth)
  local pad = U.MoverPanelPad()
  local widgets = {}
  local controls = {}

  local function BeginLiveEdit()
    if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
  end

  local player = U.CreateCheckbox(frame, {
    name = "UnrealUIPartyFrameMoverPlayer",
    text = U.L("UF_PARTY_PLAYER"),
    textWidth = contentWidth - 20,
    value = U.GetUnitFramePartySetting("partyPlayer"),
    onChange = function(value)
      U.SetUnitFramePartySetting("partyPlayer", value)
    end,
  })
  player.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)
  controls.partyPlayer = player
  table.insert(widgets, player)

  local pets = U.CreateCheckbox(frame, {
    name = "UnrealUIPartyFrameMoverPets",
    text = U.L("UF_PARTY_PETS"),
    textWidth = contentWidth - 20,
    value = U.GetUnitFramePartySetting("partyPets"),
    onChange = function(value)
      U.SetUnitFramePartySetting("partyPets", value)
    end,
  })
  pets.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop - ROW_PITCH)
  controls.partyPets = pets
  table.insert(widgets, pets)

  AddCaption(frame, widgets, pad, contentTop - PARTY_LAYOUT.hotCaption,
             U.L("HOTS_HEADER"), contentWidth)

  local enabled = U.CreateCheckbox(frame, {
    name = "UnrealUIPartyFrameMoverHotsEnabled",
    text = U.L("HOTS_ENABLED"),
    textWidth = contentWidth - 20,
    value = U.GetHotSetting("enabled"),
    onChange = function(value) U.SetHotSetting("enabled", value) end,
  })
  enabled.SetPoint("TOPLEFT", frame, "TOPLEFT", pad,
                   contentTop - PARTY_LAYOUT.hotEnabled)
  controls.enabled = enabled
  table.insert(widgets, enabled)

  local cornerLabel = U.CreateSettingsLabel(frame, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = DROPDOWN_WIDTH,
    height = 14,
  })
  if cornerLabel then
    cornerLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", pad,
                         contentTop - PARTY_LAYOUT.cornerLabel)
    cornerLabel:SetText(U.L("HOTS_CORNER"))
    table.insert(widgets, cornerLabel)
  end

  local items = {}
  local corners = U.HotCorners()
  local i
  for i = 1, table.getn(corners) do
    table.insert(items, {
      value = corners[i].value,
      text = U.L(corners[i].textKey),
    })
  end

  local corner = U.CreateDropdown(frame, {
    name = "UnrealUIPartyFrameMoverHotsCorner",
    width = DROPDOWN_WIDTH,
    height = 24,
    rowHeight = 20,
    value = U.GetHotSetting("corner"),
    items = items,
    onChange = function(value) U.SetHotSetting("corner", value) end,
  })
  corner.SetPoint("TOPLEFT", frame, "TOPLEFT", pad,
                  contentTop - PARTY_LAYOUT.corner)
  controls.corner = corner
  table.insert(widgets, corner)

  for i = 1, table.getn(PARTY_HOT_SLIDERS) do
    local spec = PARTY_HOT_SLIDERS[i]
    local min, max, step = U.HotLimits(spec.key)
    local slider = U.CreateSlider(frame, {
      name = "UnrealUIPartyFrameMoverHots" .. spec.key,
      text = U.L(spec.textKey),
      width = PARTY_LAYOUT.sliderWidth,
      boxWidth = 60,
      min = min,
      max = max,
      step = step,
      value = U.GetHotSetting(spec.key),
      onInputStart = BeginLiveEdit,
      onInput = function(value)
        if type(U.PreviewHotSetting) == "function" then
          U.PreviewHotSetting(spec.key, value)
        end
      end,
      onInputEnd = function()
        if type(U.EndHotSettingPreview) == "function" then
          U.EndHotSettingPreview(spec.key)
        end
      end,
      onChange = function(value) U.SetHotSetting(spec.key, value) end,
    })
    slider.SetPoint("TOPLEFT", frame, "TOPLEFT",
                    pad + spec.column * PARTY_LAYOUT.sliderColumn,
                    contentTop - PARTY_LAYOUT.sliders)
    controls[spec.key] = slider
    table.insert(widgets, slider)
  end

  local function Refresh()
    controls.partyPlayer.SetValue(U.GetUnitFramePartySetting("partyPlayer"))
    controls.partyPets.SetValue(U.GetUnitFramePartySetting("partyPets"))
    controls.enabled.SetValue(U.GetHotSetting("enabled"))
    controls.corner.SetValue(U.GetHotSetting("corner"))
    local n
    for n = 1, table.getn(PARTY_HOT_SLIDERS) do
      local key = PARTY_HOT_SLIDERS[n].key
      controls[key].SetValue(U.GetHotSetting(key))
    end
  end

  return widgets, Refresh
end

-- The two panels. Each is registered against its own mover id and gets its own
-- frame; they share this file's grid, captions and accessors rather than being
-- two lookalikes (rules/unreal-ui-design.md, "Do not build local variants").
local PANELS = {
  { moverId = PLAYER_MOVER_ID,
    name = "UnrealUIUnitFrameMoverSettings",
    namePrefix = "UnrealUIUnitFrameMover",
    titleKey = "MOVER_LABEL_PLAYER",
    toggles = PLAYER_TOGGLES,
    auras = PLAYER_AURA_TOGGLES },
  { moverId = TARGET_MOVER_ID,
    name = "UnrealUITargetFrameMoverSettings",
    namePrefix = "UnrealUITargetFrameMover",
    titleKey = "MOVER_LABEL_TARGET",
    toggles = TARGET_TOGGLES,
    auras = TARGET_AURA_TOGGLES },
}

function UFC:OnInit()
  if type(U.RegisterMoverPanel) ~= "function" then return end

  local i
  for i = 1, table.getn(PANELS) do
    local def = PANELS[i]
    U.RegisterMoverPanel(def.moverId, {
      name = def.name,
      width = CONTENT_WIDTH + U.MoverPanelPad() * 2,
      height = function() return PanelHeight(def) end,
      build = function(frame, contentTop, contentWidth)
        return BuildPanel(def, frame, contentTop, contentWidth)
      end,
      title = function() return U.L(def.titleKey) end,
      -- Nothing to configure while the module that owns these settings is not
      -- there to apply them.
      available = function()
        return type(U.GetUnitFramePowerTick) == "function"
      end,
    })
  end

  U.RegisterMoverPanel(PARTY_MOVER_ID, {
    name = "UnrealUIPartyFrameMoverSettings",
    width = CONTENT_WIDTH + U.MoverPanelPad() * 2,
    height = PARTY_LAYOUT.height,
    build = BuildPartyPanel,
    title = function() return U.L("MOVER_LABEL_PARTY") end,
    available = function()
      return type(U.GetUnitFramePartySetting) == "function" and
             type(U.GetHotSetting) == "function"
    end,
  })
end
