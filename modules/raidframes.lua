-- unrealUI :: modules/raidframes.lua
--
-- Raid frames, ported from pandaUI (user request, 2026-10-31): one cell per
-- raid member, laid out the way WoW Forever 1.60.1.69913 lays out its raid --
-- CompactUnitFrame cells stacked five to a CompactRaidGroup column, one
-- column per used group, each under its "Group N" title. Inside every cell:
-- class-coloured health with incoming-heal prediction, the power strip, the
-- player's own HoTs with their timer, the unit's debuffs bordered by dispel
-- school, the dispel-school icons and Forever's dispel overlay. The same
-- cells also draw the party block when Party Frames > "Raid-style frames" is
-- on (see "Party block" below).
--
-- Reference: ForeverFrameXML-1.60.1.69913, Blizzard_UnitFrame/Shared/
-- CompactUnitFrame.xml/.lua, Shared/CompactRaidGroup.xml/.lua and
-- Blizzard_PrivateAurasUI.lua. Every number and texture cell lives in
-- M.raidFrame; the art is in media/Textures/modern-wow/raid/ (ATTRIBUTION.md).
-- The bars follow Retail's shaded Raid-Bar-* art rather than Forever's flat
-- fill.
--
-- Scope, stated so it is not mistaken for an omission:
--
--   * One design and one rule set under all three themes, as in pandaUI
--     (rules/unreal-ui-design.md, "Raid frames exception"): no theme branch
--     anywhere in this file or its settings page. The party rows
--     (modules/unitframes.lua) hide in a raid while these frames are on.
--   * No role icon, aggro highlight, ready check, absorbs or private auras:
--     1.12 has no roles, no threat API, no absorb API and no private auras.
--   * Buffs: Forever shows only the buffs the player cast. This client cannot
--     name a buff's caster, so the buff slots carry the player's own HoTs,
--     which modules/hots.lua reconstructs from the player's casts
--     (U.HotLiveOn). Their timer is that module's stamp, drawn with the shared
--     radial wipe.
--   * Range: there is no spell-range API for a unit here, so "out of range"
--     is the world-object check the party rows use (U.UnitObjectVisible).
--   * Aura icons are textures, not mouse-enabled frames: a mouse-enabled icon
--     would swallow the click that targets the member.
--
-- Nothing here is runtime-verified on this client yet; pandaUI's version is
-- WORKING_SOURCE from the Octo client.

local U = UnrealUI
local M = U.media

local RF = U.RegisterModule("raidframes")

local R = M.raidFrame

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local CONFIG = "raidframes"

local defaults = {
  enabled = true,
  showPower = true,
  showDebuffs = true,
  showHots = true,
  healPrediction = true,
  -- Retail's grid by default (user request, 2026-10-21): "Group N" titles
  -- kept, Forever's per-group border box off. Both toggle with /uui raid.
  groupTitles = true,
  groupBorder = false,
  -- Cell size, set from the Raid Frames settings page (user request,
  -- 2026-10-21). width is the cell's, so health and power share it; the cell
  -- height is the two bar heights plus the 1-unit inset above and below.
  -- Defaults reproduce the 72x36 cell with the halved power strip.
  width = M.raidFrame.defaultWidth,
  healthHeight = M.raidFrame.defaultHeight - M.raidFrame.inset * 2 -
                 M.raidFrame.powerUsed,
  powerHeight = M.raidFrame.powerUsed,
  -- Debuff filtering (user decisions, 2026-10-21). onlyDispellable is
  -- Forever's raidFramesDisplayOnlyDispellableDebuffs, on by default here;
  -- dispelIndicator is its raidFramesDispelIndicatorType (off | mine | all),
  -- "mine" by default here. See PaintDebuffs.
  onlyDispellable = true,
  dispelIndicator = "mine",
  -- Forever's raid-frame buff options (user request, 2026-10-21): Edit
  -- Mode's Aura Organization (EditModeSettingDisplayInfo.lua:369, default
  -- Legacy) and Buff Icon Size (:409, 50-200 % in steps of 10, default
  -- 100 %). Forever's Display Buffs is showHots above: the buffs this client
  -- can attribute to the player are the player's own HoTs.
  auraOrganization = "legacy",
  -- One size for every icon in the cell -- HoTs, debuffs and dispel-type
  -- icons (user request, 2026-10-26), in percent of their M.raidFrame size.
  -- Cells are children of a scaled mover, so 120 is 20 % larger than the
  -- icon at the current mover scale.
  buffIconSize = 100,
}

-- The Aura Organization choices, in Edit Mode's order.
local ORGANIZATIONS = { "legacy", "buffsTop", "buffsRight" }

function U.RaidFrameOrganizations()
  return ORGANIZATIONS
end

-- Forever's dispel indicator choices (Enum.RaidDispelDisplayType order).
local DISPEL_INDICATORS = { "off", "mine", "all" }

function U.RaidFrameDispelIndicators()
  return DISPEL_INDICATORS
end

-- Shared with the settings page so the slider and the clamp cannot disagree.
local LIMITS = {
  width = { min = 40, max = 200, step = 1 },
  healthHeight = { min = 10, max = 80, step = 1 },
  powerHeight = { min = 1, max = 20, step = 1 },
  buffIconSize = { min = 50, max = 200, step = 10 },
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

function U.GetRaidFrameSetting(key)
  local value = Config()[key]
  if value == nil then value = defaults[key] end
  return value
end

function U.RaidFrameLimits(key)
  return LIMITS[key]
end

-- Defined with the roster code below; a change relays out every cell.
local ApplySettings

function U.SetRaidFrameSetting(key, value)
  local limit = LIMITS[key]
  if limit then
    value = tonumber(value) or defaults[key]
    if value < limit.min then value = limit.min end
    if value > limit.max then value = limit.max end
    value = math.floor(value + 0.5)
  end
  Config()[key] = value
  if ApplySettings then ApplySettings() end
end

local function Enabled()
  return U.GetRaidFrameSetting("enabled") and true or false
end

-- Read by modules/unitframes.lua: the party block steps aside in a raid only
-- while these frames draw it.
function U.RaidFramesEnabled()
  return Enabled()
end

-- ---------------------------------------------------------------------------
-- Client access, resolved once by name and pcall'd like modules/auras.lua.
-- ---------------------------------------------------------------------------
local fnCache = {}

local function Fn(name)
  -- "/uui party test" fake party (modules/partytest.lua); nil in normal play.
  local override = U.gOverride
  if override and override[name] then return override[name] end
  local cached = fnCache[name]
  if cached == nil then
    local value = U.G(name)
    cached = (type(value) == "function") and value or false
    fnCache[name] = cached
  end
  return cached or nil
end

local function Call(name, a, b)
  local fn = Fn(name)
  if not fn then return nil end
  local ok, v1, v2, v3 = pcall(fn, a, b)
  if not ok then return nil end
  return v1, v2, v3
end

local function Now()
  return tonumber(Call("GetTime")) or 0
end

-- The schools each class can remove in 1.12. Forever's default dispel display
-- (Enum.RaidDispelDisplayType.DisplayAll) shows every school; this table only
-- decides which debuff the overlay prefers when a member carries several.
local DISPEL_BY_CLASS = {
  PRIEST  = { Magic = true, Disease = true },
  PALADIN = { Magic = true, Poison = true, Disease = true },
  DRUID   = { Curse = true, Poison = true },
  MAGE    = { Curse = true },
  SHAMAN  = { Poison = true, Disease = true },
}

-- ---------------------------------------------------------------------------
-- State. One table, so the closures below stay well under Lua 5.0's upvalue
-- limit.
-- ---------------------------------------------------------------------------
local MAX_MEMBERS = 40
local GROUP_COUNT = 8
local GROUP_SIZE = 5
local DEBUFF_SLOTS = 16

local rf = {
  root = nil,
  cells = {},          -- index -> cell
  -- The party block drawn with raid cells (Party Frames option, user request
  -- 2026-10-26): its own pool, parented to the party mover's anchor.
  party = { root = nil, cells = {}, count = 0, shape = nil },
  active = {},         -- cells in use, raid first then party: 1..shown
  groups = {},         -- group number -> group frame
  byUnit = {},         -- unit token -> cell currently showing it
  shown = 0,           -- cells in use
  preview = false,
  rosterDirty = true,
  auraCursor = 1,
  playerClass = nil,
  hots = {},           -- scratch for U.HotLiveOn
  debuffs = {},        -- scratch for one debuff walk
  ordered = {},        -- the same entries in display order
  -- Current cell geometry from the settings; stamp moves on every change so
  -- each cell re-sizes once (SizeCell).
  geo = { stamp = 0 },
  partyGeo = { stamp = 0 },  -- the same for the raid-style party column
}

local function Setting(key)
  local value = tonumber(U.GetRaidFrameSetting(key)) or defaults[key]
  local limit = LIMITS[key]
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return value
end

-- One geometry table per cell pool. Both share the cell size and aura
-- layout; their icon scale differs: the raid's own Aura icon size, and for
-- the raid-style party column the Party Frames icon size (modules/auras.lua
-- partyIconSize, user request 2026-10-26), so the party slider sizes the
-- party's icons whichever style draws them.
local function FillGeometry(geo, width, health, power, org, scale)
  if geo.width ~= width or geo.health ~= health or geo.power ~= power or
     geo.org ~= org or geo.scale ~= scale then
    geo.width, geo.health, geo.power = width, health, power
    geo.org, geo.scale = org, scale
    geo.buffSize = R.auraSize * scale
    geo.debuffSize = R.auraSize * scale
    geo.dispelSize = R.dispelIconSize * scale
    geo.layout = R.organization[org]
    geo.height = R.inset * 2 + health +
                 (power > 0 and power + R.powerGap or 0)
    geo.stamp = geo.stamp + 1
  end
end

local PARTY_POWER_SCALE = 1.3

local function PartyIconScale()
  local value = type(U.GetAuraSetting) == "function" and
                tonumber(U.GetAuraSetting("partyIconSize")) or nil
  local limit = LIMITS.buffIconSize
  if not value then return 1 end
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return value / 100
end

local function Geometry()
  local width = Setting("width")
  local health = Setting("healthHeight")
  local power = U.GetRaidFrameSetting("showPower") and Setting("powerHeight")
                or 0
  local org = U.GetRaidFrameSetting("auraOrganization")
  if not R.organization[org] then org = defaults.auraOrganization end
  FillGeometry(rf.geo, width, health, power, org,
               Setting("buffIconSize") / 100)
  -- The party column's power strip is 30 % taller (user request,
  -- 2026-10-26); its cells grow to hold it.
  local partyPower = power > 0 and
                     math.floor(power * PARTY_POWER_SCALE + 0.5) or 0
  FillGeometry(rf.partyGeo, width, health, partyPower, org, PartyIconScale())
  return rf.geo
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
local function SetCoord(texture, coord)
  texture:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
end

local function NewTexture(parent, layer, path, coord)
  local texture = parent:CreateTexture(nil, layer)
  texture:SetTexture(path)
  if coord then SetCoord(texture, coord) end
  return texture
end

-- One aura slot: a frame only so the radial wipe has something to draw on.
-- Never mouse-enabled (see the header).
local function NewAuraSlot(cell, harmful, size)
  local slot = CreateFrame("Frame", nil, cell.over)
  slot:SetWidth(size)
  slot:SetHeight(size)

  slot.icon = NewTexture(slot, "ARTWORK", nil)
  slot.icon:SetAllPoints(slot)
  -- The same inner crop every aura icon in UnrealUI uses, so the client's
  -- baked icon border does not frame the art twice.
  slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  if harmful then
    -- RaidAuraFrameTemplate: the white UI-Debuff-Overlays cell, 1 unit
    -- outside the icon on every side, tinted by dispel school.
    slot.border = NewTexture(slot, "OVERLAY", R.texture.auraBorder,
                             R.coord.auraBorder)
    slot.border:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1)
    slot.border:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
  else
    slot.wipe = U.CreateRadialWipe(slot, { layer = "OVERLAY", size = size })
  end

  slot.count = U.CreateLabel(slot, {
    size = M.fontSize.tiny,
    color = M.color.text,
    justify = "RIGHT",
  })
  if slot.count then
    slot.count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
  end

  slot:Hide()
  return slot
end

local ShowUnitMenu

local function OnCellClick(cell, button)
  local unit = cell.unit
  if not unit then return end

  if Call("SpellIsTargeting") then
    if button == "RightButton" then
      Call("SpellStopTargeting")
    else
      Call("SpellTargetUnit", unit)
    end
    return
  end

  if button == "RightButton" then
    ShowUnitMenu(cell)
    return
  end

  if Call("CursorHasItem") then
    Call("DropItemOnUnit", unit)
    return
  end
  Call("TargetUnit", unit)
end

local function WireMouse(cell)
  pcall(cell.EnableMouse, cell, true)
  pcall(cell.RegisterForClicks, cell, "LeftButtonUp", "RightButtonUp")

  cell:SetScript("OnClick", function(a, b)
    -- Same argument ambiguity modules/unitframes.lua resolves: direct
    -- arguments first, then the legacy global.
    local button = (type(a) == "string" and a) or
                   (type(b) == "string" and b) or U.G("arg1")
    OnCellClick(cell, button)
  end)

  cell:SetScript("OnEnter", function()
    local tooltip = U.G("GameTooltip")
    if not tooltip or not cell.unit then return end
    local anchor = U.G("GameTooltip_SetDefaultAnchor")
    if type(anchor) ~= "function" or not pcall(anchor, tooltip, cell) then
      pcall(tooltip.SetOwner, tooltip, cell, "ANCHOR_RIGHT")
    end
    if pcall(tooltip.SetUnit, tooltip, cell.unit) then
      pcall(tooltip.Show, tooltip)
    end
  end)

  cell:SetScript("OnLeave", function()
    local tooltip = U.G("GameTooltip")
    if not tooltip then return end
    if not pcall(tooltip.FadeOut, tooltip) then
      pcall(tooltip.Hide, tooltip)
    end
  end)
end

-- Created at 1x1; SizeCell gives every piece its size from the settings.
local function BuildBars(cell)
  local inset = R.inset

  cell.health = U.CreateStatusBar(cell, {
    texture = R.texture.barHealth,
    background = { 0, 0, 0, 0 },
    width = 1,
    height = 1,
  })
  cell.health:SetPoint("TOPLEFT", cell, "TOPLEFT", inset, -inset)

  cell.power = U.CreateStatusBar(cell, {
    texture = R.texture.barPower,
    background = { 0, 0, 0, 0 },
    width = 1,
    height = 1,
  })
  cell.power:SetPoint("TOPLEFT", cell.health, "BOTTOMLEFT", 0, -R.powerGap)
  local powerBg = NewTexture(cell.power, "BACKGROUND",
                             R.texture.barPowerBackground, R.coord.barPower)
  powerBg:SetAllPoints(cell.power)
end

-- Applies the current geometry to one cell, once per settings change. Sizes
-- are set explicitly rather than through anchors, and the shared bars are
-- re-measured because a resize alone does not move their fill.
local function SizeCell(cell)
  local geo = cell.geo or rf.geo
  if cell.geoStamp == geo.stamp then return end
  cell.geoStamp = geo.stamp

  local inner = geo.width - R.inset * 2
  cell:SetWidth(geo.width)
  cell:SetHeight(geo.height)
  cell.over:SetWidth(geo.width)
  cell.over:SetHeight(geo.height)

  cell.health:SetWidth(inner)
  cell.health:SetHeight(geo.health)
  U.RefreshStatusBar(cell.health)

  cell.powerShown = geo.power > 0
  if cell.powerShown then
    cell.power:SetWidth(inner)
    cell.power:SetHeight(geo.power)
    U.RefreshStatusBar(cell.power)
    cell.power:Show()
  else
    cell.power:Hide()
  end

  -- The name follows the aura organization's Name template.
  if cell.name then
    local place = geo.layout.name
    cell.name:SetWidth(geo.width - R.nameInset * 2)
    cell.name:ClearAllPoints()
    if place == "CENTER" then
      cell.name:SetPoint("CENTER", cell.over, "CENTER", 0, 0)
      cell.name:SetJustifyH("CENTER")
    elseif place == "TOP" then
      cell.name:SetPoint("TOP", cell.over, "TOP", 0, -R.nameInset)
      cell.name:SetJustifyH("CENTER")
    else
      cell.name:SetPoint("TOPLEFT", cell.over, "TOPLEFT", R.nameInset,
                         -R.nameInset)
      cell.name:SetJustifyH("LEFT")
    end
  end

  -- CompactUnitFrameDispelOverlayMixin:SetOrientation: the vertical gradient
  -- fades down (Legacy) or up (buffs on top), the horizontal one from the left.
  local gradient = geo.layout.gradient
  if gradient == "left" then
    cell.dispelGradient:SetTexture(R.texture.dispelVertical)
    SetCoord(cell.dispelGradient, R.coord.dispelVertical)
  else
    local c = R.coord.dispelGradient
    cell.dispelGradient:SetTexture(R.texture.resource)
    if gradient == "bottom" then
      cell.dispelGradient:SetTexCoord(c[1], c[2], c[4], c[3])
    else
      SetCoord(cell.dispelGradient, c)
    end
  end

  local i
  for i = 1, table.getn(cell.buffs) do
    local slot = cell.buffs[i]
    slot:SetWidth(geo.buffSize)
    slot:SetHeight(geo.buffSize)
    U.SizeRadialWipe(slot.wipe, geo.buffSize)
  end
  for i = 1, table.getn(cell.debuffSlots) do
    cell.debuffSlots[i]:SetWidth(geo.debuffSize)
    cell.debuffSlots[i]:SetHeight(geo.debuffSize)
  end
  for i = 1, table.getn(cell.dispelIcons) do
    cell.dispelIcons[i]:SetWidth(geo.dispelSize)
    cell.dispelIcons[i]:SetHeight(geo.dispelSize)
  end
  if cell.status then
    cell.status:SetWidth(geo.width - 6)
    cell.status:ClearAllPoints()
    cell.status:SetPoint("BOTTOM", cell.over, "BOTTOM", 0, geo.height / 3 - 2)
  end
end

local function BuildOverlay(cell)
  -- Everything drawn over the bars lives on one frame above them, which is
  -- how the template's ARTWORK/OVERLAY layers end up above the bar fill here:
  -- the bars are child frames, not textures of the cell.
  local over = CreateFrame("Frame", nil, cell)
  over:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
  over:SetWidth(1)
  over:SetHeight(1)
  local okLevel, level = pcall(cell.GetFrameLevel, cell)
  if okLevel and tonumber(level) then
    pcall(over.SetFrameLevel, over, level + 3)
  end
  cell.over = over

  -- CompactUnitFrameDispelOverlayTemplate, Legacy orientation
  -- (VerticalTopToBottom): fill at 0.2, the gradient and the highlight rim,
  -- all tinted by the debuff's school.
  cell.dispelFill = NewTexture(over, "BACKGROUND", R.texture.dispelFill)
  cell.dispelFill:SetAllPoints(over)
  cell.dispelGradient = NewTexture(over, "BORDER", R.texture.resource,
                                   R.coord.dispelGradient)
  cell.dispelGradient:SetAllPoints(over)
  cell.dispelBorder = NewTexture(over, "BORDER", R.texture.sheet,
                                 R.coord.dispelHighlight)
  cell.dispelBorder:SetAllPoints(over)
  cell.dispelFill:Hide()
  cell.dispelGradient:Hide()
  cell.dispelBorder:Hide()

  -- RaidFrame-TargetFrame over the whole cell while it is the target.
  cell.selection = NewTexture(over, "OVERLAY", R.texture.sheet, R.coord.target)
  cell.selection:SetAllPoints(over)
  cell.selection:Hide()

  -- GameFontHighlightSmall, one line, Legacy placement.
  cell.name = U.CreateLabel(over, {
    size = M.fontSize.small,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontHighlightSmall",
    justify = "LEFT",
    height = 12,
  })
  if cell.name then
    cell.name:SetPoint("TOPLEFT", over, "TOPLEFT", R.nameInset, -R.nameInset)
  end

  -- GameFontDisable: Offline / Dead, its bottom a third of the way up.
  cell.status = U.CreateLabel(over, {
    size = M.fontSize.small,
    color = { 0.5, 0.5, 0.5, 1 },
    inherits = "GameFontDisable",
    justify = "CENTER",
  })
  if cell.status then cell.status:Hide() end

  cell.buffs, cell.debuffSlots, cell.dispelIcons = {}, {}, {}
  local i
  for i = 1, R.maxDispel do
    local icon = NewTexture(over, "ARTWORK", R.texture.sheet)
    icon:SetWidth(R.dispelIconSize)
    icon:SetHeight(R.dispelIconSize)
    icon:Hide()
    cell.dispelIcons[i] = icon
  end
end

local function BuildCell(index, pool, parent, prefix, geo)
  local cell = CreateFrame("Button", prefix .. index, parent)
  cell.geo = geo
  cell:SetWidth(1)
  cell:SetHeight(1)

  -- Retail's Raid-Bar-Hp-Bg, untinted: the dark that shows behind missing
  -- health and as the 1-unit line round every cell.
  local background = NewTexture(cell, "BACKGROUND", R.texture.barBackground,
                                R.coord.barBackground)
  background:SetAllPoints(cell)

  BuildBars(cell)
  BuildOverlay(cell)
  WireMouse(cell)
  SizeCell(cell)

  cell.index = index
  cell:Hide()
  pool[index] = cell
  return cell
end

local function Cell(index)
  return rf.cells[index] or
         BuildCell(index, rf.cells, rf.root, "UnrealUIRaidCell", rf.geo)
end

local function PartyCell(index)
  local party = rf.party
  return party.cells[index] or
         BuildCell(index, party.cells, party.root, "UnrealUIPartyRaidCell",
                   rf.partyGeo)
end

local function BuildGroup(number)
  local group = CreateFrame("Frame", "UnrealUIRaidGroup" .. number, rf.root)
  group:SetWidth(rf.geo.width or R.width)
  group:SetHeight(R.titleHeight)

  -- CompactRaidGroup's border frame: options_frame_child behind the members.
  group.background = NewTexture(group, "BACKGROUND", R.texture.groupBackground,
                                R.groupBackgroundCoord)

  -- GameFontNormalSmall title, disabled button in the template.
  group.title = U.CreateLabel(group, {
    size = M.fontSize.small,
    color = M.color.gold or { 1, 0.82, 0, 1 },
    inherits = "GameFontNormalSmall",
    justify = "CENTER",
  })
  if group.title then
    group.title:SetPoint("TOP", group, "TOP", 0, -1)
    group.title:SetText(U.L("RAID_GROUP_N", number))
  end

  group:Hide()
  rf.groups[number] = group
  return group
end

local function Group(number)
  return rf.groups[number] or BuildGroup(number)
end

-- ---------------------------------------------------------------------------
-- Unit menu
--
-- 1.12 builds its raid member menu through Blizzard_RaidUI's
-- RaidFrameDropDown_Initialize, which hands UnitPopup_ShowMenu the "RAID"
-- popup. That addon is load-on-demand, so UnrealUI owns one dropdown and does
-- the same call itself (pfUI's pre-secure pattern). UnitPopup_ShowMenu is
-- FrameXML on this client (query_api.py); the menu's own behaviour is
-- WORKING_SOURCE, not runtime-verified.
-- ---------------------------------------------------------------------------
local PREVIEW_RAID_MENU = {
  "UNREALUI_WHISPER", "RAID_LEADER", "RAID_PROMOTE", "RAID_DEMOTE",
  "RAID_REMOVE", "CANCEL",
}

local function PreviewMenuNoop()
end

-- Native RAID buttons depend on a real roster and disappear while solo.
-- Test management actions stay harmless; Whisper opens the fake member tell.
local function ShowPreviewRaidMenu(dropdown)
  local add = Fn("UIDropDownMenu_AddButton")
  local popupClick = Fn("UnitPopup_OnClick")
  local buttons = U.G("UnitPopupButtons")
  if not add or type(buttons) ~= "table" then return end

  pcall(add, { text = dropdown.name or "", isTitle = 1, notCheckable = 1 })
  local i
  for i = 1, table.getn(PREVIEW_RAID_MENU) do
    local key = PREVIEW_RAID_MENU[i]
    local button = buttons[key]
    if button and button.text then
      pcall(add, {
        text = button.text,
        value = key,
        notCheckable = 1,
        func = key == "UNREALUI_WHISPER" and popupClick or PreviewMenuNoop,
      })
    end
  end
  Call("PlaySound", "igMainMenuOpen")
end

local function MenuDropDown()
  if rf.dropdown ~= nil then return rf.dropdown or nil end

  local ok, dropdown = pcall(CreateFrame, "Frame", "UnrealUIRaidDropDown",
                             UIParent, "UIDropDownMenuTemplate")
  local init = Fn("UIDropDownMenu_Initialize")
  if not ok or not dropdown or not init then
    rf.dropdown = false
    return nil
  end

  pcall(init, dropdown, function()
    if dropdown.previewRaid then
      ShowPreviewRaidMenu(dropdown)
      return
    end
    local show = Fn("UnitPopup_ShowMenu")
    if not show or not dropdown.unit then return end
    local which = "RAID"
    if Call("UnitIsUnit", dropdown.unit, "player") then
      which = "SELF"
    elseif string.find(dropdown.unit, "^party%d") then
      -- A party cell gets the menu the party rows open.
      which = "PARTY"
    end
    pcall(show, dropdown, which, dropdown.unit, dropdown.name, dropdown.id)
  end, "MENU")

  rf.dropdown = dropdown
  return dropdown
end

ShowUnitMenu = function(cell)
  -- A real party or player cell opens the menu the party rows open
  -- (modules/unitframes.lua), Whisper entry and styling included.
  if not cell.fake and type(U.ShowUnitFrameMenu) == "function" and
     (cell.unit == "player" or string.find(cell.unit, "^party%d")) then
    U.ShowUnitFrameMenu(cell, cell.unit)
    return
  end
  local dropdown = MenuDropDown()
  local toggle = Fn("ToggleDropDownMenu")
  if not dropdown or not toggle then return end
  dropdown.unit = cell.unit
  dropdown.previewRaid = cell.fake and true or nil
  dropdown.name = cell.fake and cell.fake.name or Call("UnitName", cell.unit)
  dropdown.id = cell.raidIndex
  pcall(toggle, 1, nil, dropdown, "cursor")
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------
-- Incoming heal, the two Forever colours, chained after the fill. Split out
-- so modules/healpredict.lua can push a change to every cell at once
-- (U.ApplyRaidHealPrediction) instead of waiting for the sweep.
local function PaintPrediction(cell)
  local mine, others = 0, 0
  if U.GetRaidFrameSetting("healPrediction") then
    local fake = cell.fake
    if fake then
      if fake.connected and not fake.dead then
        mine, others = fake.mine, fake.others
      end
    elseif type(U.UnitIncomingHeal) == "function" then
      mine, others = U.UnitIncomingHeal(cell.unit)
    end
  end
  U.SetStatusBarPrediction(cell.health, mine, others)
  if cell.health.uuiPredictTexture and not cell.mineTinted then
    cell.mineTinted = true
    U.SetColor(cell.health.uuiPredictTexture, M.Unpack(R.myHeal))
  end
  if cell.health.uuiPredictOtherTexture and not cell.otherTinted then
    cell.otherTinted = true
    U.SetColor(cell.health.uuiPredictOtherTexture, M.Unpack(R.otherHeal))
  end
end

function U.ApplyRaidHealPrediction()
  if not rf.running then return end
  local i
  for i = 1, rf.shown do PaintPrediction(rf.active[i]) end
end

-- What one cell shows, from the client or, in /uui raid test, from the cell's
-- generated record. One scratch table: read and painted immediately.
local vitals = {}

local function ReadVitals(cell)
  local v, fake = vitals, cell.fake
  if fake then
    v.health, v.maximum = fake.health, fake.maximum
    v.connected, v.dead, v.far = fake.connected, fake.dead, fake.far
    v.class, v.name = fake.class, fake.name
    v.power, v.powerMax, v.powerType = fake.power, fake.powerMax, fake.powerType
    return v
  end

  local unit = cell.unit
  v.health = tonumber((Call("UnitHealth", unit))) or 0
  v.maximum = tonumber((Call("UnitHealthMax", unit))) or 0
  v.connected = Call("UnitIsConnected", unit) and true or false
  v.dead = v.connected and Call("UnitIsDeadOrGhost", unit) and true or false
  local _, class = Call("UnitClass", unit)
  v.class = class
  v.name = Call("UnitName", unit)
  v.power = tonumber((Call("UnitMana", unit))) or 0
  v.powerMax = tonumber((Call("UnitManaMax", unit))) or 0
  -- Some builds also return a token string; keep only the number.
  v.powerType = tonumber((Call("UnitPowerType", unit))) or 0
  -- CompactUnitFrame_GetRangeAlpha's 0.5, on the world-object check.
  v.far = v.connected and U.UnitObjectVisible(unit) == false
  return v
end

local function PaintVitals(cell)
  local v = ReadVitals(cell)
  local health, maximum = v.health, v.maximum
  if maximum <= 0 then maximum = 1 end
  local connected, dead = v.connected, v.dead

  cell.health:SetMinMaxValues(0, maximum)
  cell.health:SetValue(dead and 0 or health)

  -- CompactUnitFrame_UpdateHealthColor: grey while offline, class colour
  -- otherwise (useClassColors is on by default).
  local r, g, b
  if not connected then
    r, g, b = M.Unpack(R.offlineColor)
  else
    r, g, b = M.ClassColor(v.class)
    if not r then r, g, b = 0, 1, 0 end
  end
  if cell.healthR ~= r or cell.healthG ~= g or cell.healthB ~= b then
    cell.healthR, cell.healthG, cell.healthB = r, g, b
    U.SetStatusBarColor(cell.health, r, g, b, 1)
  end

  PaintPrediction(cell)

  if cell.powerShown then
    local power, powerMax = v.power, v.powerMax
    if powerMax <= 0 then powerMax = 1 end
    cell.power:SetMinMaxValues(0, powerMax)
    cell.power:SetValue(power)
    local powerType = v.powerType
    local color = R.powerColor[powerType] or M.power[powerType] or
                  M.power.fallback
    if cell.powerType ~= powerType then
      cell.powerType = powerType
      U.SetStatusBarColor(cell.power, M.Unpack(color))
    end
  end

  if cell.name then
    local name = v.name
    if cell.nameText ~= name then
      cell.nameText = name
      cell.name:SetText(name or "")
    end
    if connected and not dead then
      cell.name:SetTextColor(1, 1, 1, 1)
    else
      cell.name:SetTextColor(0.5, 0.5, 0.5, 1)
    end
  end

  if cell.status then
    if not connected then
      cell.status:SetText(U.L("RAID_STATUS_OFFLINE"))
      cell.status:Show()
    elseif dead then
      cell.status:SetText(U.L("RAID_STATUS_DEAD"))
      cell.status:Show()
    else
      cell.status:Hide()
    end
  end

  local alpha = v.far and R.rangeAlpha or 1
  if cell.alpha ~= alpha then
    cell.alpha = alpha
    cell:SetAlpha(alpha)
  end
end

local function PaintSelection(cell)
  local selected
  if cell.fake then
    selected = cell.fake.selected
  else
    selected = Call("UnitIsUnit", cell.unit, "target")
  end
  if selected then
    cell.selection:Show()
  else
    cell.selection:Hide()
  end
end

-- Places the index-th member of one aura group by its organization spec
-- (M.raidFrame.organization): columns grow along dx from the corner,
-- rows away from it -- up for a group on the power strip, down for one that
-- hangs from the top. `inset` is the dispel overlay's extra 2 units, which
-- `fixed` groups ignore.
local function PlaceAura(cell, frame, index, spec, size, inset)
  if spec.fixed then inset = 0 end
  local column = math.mod(index - 1, spec.perRow)
  local row = math.floor((index - 1) / spec.perRow)
  local x = spec.x + spec.dx * (inset + column * size)
  local y
  if spec.bottom then
    y = R.auraBottom + (cell.powerShown and cell.geo.power + R.powerGap or 0) +
        inset + row * size
  else
    y = spec.y - inset - row * size
  end
  frame:ClearAllPoints()
  frame:SetPoint(spec.point, cell.over, spec.point, x, y)
end

local function HideSlots(slots, from)
  local i
  for i = from, table.getn(slots) do slots[i]:Hide() end
end

-- Fills `out` with this unit's debuffs and returns how many. Entry tables are
-- reused across scans: the sweep reads every member each second.
local function ReadDebuffs(unit, out)
  local n, i = 0, nil
  for i = 1, DEBUFF_SLOTS do
    -- Aura slots may be sparse on this client: walk the whole range.
    local texture, count, school = Call("UnitDebuff", unit, i)
    if type(texture) == "string" and texture ~= "" then
      if type(school) ~= "string" or school == "" then school = nil end
      n = n + 1
      local entry = out[n]
      if not entry then
        entry = {}
        out[n] = entry
      end
      entry.texture = texture
      entry.count = tonumber(count) or 0
      entry.school = school
    end
  end
  return n
end

-- The schools the player's class removes, or nil for a class that removes
-- none (warrior, rogue, hunter, warlock).
local function MySchools()
  return rf.playerClass and DISPEL_BY_CLASS[rf.playerClass]
end

-- PrivateAuraAnchorContainerMixin:ShouldDisplayDispelIndicator: off shows
-- nothing, "mine" only the schools the player can remove, "all" every school.
local function Indicated(school, mine, mode)
  if mode == "off" or not school or not R.debuffColor[school] then
    return false
  end
  if mode == "mine" then return mine and mine[school] and true or false end
  return true
end

-- A generated member: /uui raid test (cell.fake) or a "/uui party test" party
-- member shown by the raid-style party column (modules/partytest.lua).
local function TestCell(cell)
  if cell.fake then return true end
  return U.partyTest and type(cell.unit) == "string" and
         string.find(cell.unit, "^party%d") and true or false
end

-- Driven by every debuff on the unit, not only the ones shown as icons, as
-- Forever keeps its dispel list apart from the debuff frames.
local function PaintDispel(cell, debuffs, count)
  local mine = MySchools()
  -- Both tests always show every school (user requests, 2026-10-21 and
  -- 2026-10-26): under "mine" a class would never see the schools it cannot
  -- remove.
  local mode = TestCell(cell) and "all" or
               U.GetRaidFrameSetting("dispelIndicator")
  -- The overlay takes the school the player can remove first, then any.
  local overlay, i
  for i = 1, count do
    local school = debuffs[i].school
    if Indicated(school, mine, mode) then
      if mine and mine[school] then overlay = school break end
      if not overlay then overlay = school end
    end
  end

  if overlay then
    local r, g, b = M.Unpack(R.debuffColor[overlay])
    U.SetColor(cell.dispelFill, r, g, b, 0.2)
    U.SetColor(cell.dispelGradient, r, g, b, 1)
    U.SetColor(cell.dispelBorder, r, g, b, 1)
    cell.dispelFill:Show()
    cell.dispelGradient:Show()
    cell.dispelBorder:Show()
  else
    cell.dispelFill:Hide()
    cell.dispelGradient:Hide()
    cell.dispelBorder:Hide()
  end
  cell.auraOffset = overlay and R.dispelAuraOffset or 0

  -- One icon per school present, placed by the organization's Dispel group.
  -- cell.flagged records which schools got one, so PaintDebuffs can drop
  -- the spell icons they already stand for.
  local flagged = cell.flagged or {}
  cell.flagged = flagged
  local key
  for key in pairs(flagged) do flagged[key] = nil end
  local shown = 0
  for i = 1, count do
    local school = debuffs[i].school
    local seen = false
    local k
    for k = 1, i - 1 do
      if debuffs[k].school == school then seen = true end
    end
    if Indicated(school, mine, mode) and R.coord.dispelIcon[school] and
       not seen and shown < R.maxDispel then
      shown = shown + 1
      flagged[school] = true
      local icon = cell.dispelIcons[shown]
      SetCoord(icon, R.coord.dispelIcon[school])
      PlaceAura(cell, icon, shown, cell.geo.layout.dispel, cell.geo.dispelSize, 0)
      icon:Show()
    end
  end
  for i = shown + 1, R.maxDispel do cell.dispelIcons[i]:Hide() end
end

local function PaintDebuffs(cell)
  local debuffs = rf.debuffs
  local count = 0
  if U.GetRaidFrameSetting("showDebuffs") then
    if cell.fake then
      local i
      for i = 1, table.getn(cell.fake.debuffs) do
        local entry = debuffs[i] or {}
        debuffs[i] = entry
        local source = cell.fake.debuffs[i]
        entry.texture, entry.count = source.texture, source.count
        entry.school = source.school
      end
      count = table.getn(cell.fake.debuffs)
    else
      count = ReadDebuffs(cell.unit, debuffs)
    end
  end

  PaintDispel(cell, debuffs, count)

  -- Icon order (user decision, 2026-10-21): schools the player can remove,
  -- then other schools, then physical, slot order kept inside each rank, so
  -- the slots go to what the player can act on. With onlyDispellable on, only
  -- the first rank is shown (Forever's displayOnlyDispellableDebuffs, minus
  -- the boss debuffs it also keeps: this client cannot tell them apart).
  local mine = MySchools()
  -- A test member shows every debuff it rolled, whatever the player's class.
  local onlyMine = U.GetRaidFrameSetting("onlyDispellable") and
                   not TestCell(cell)
  local ordered = rf.ordered
  local n, i, rank = 0, nil, nil
  for rank = 1, onlyMine and 1 or 3 do
    for i = 1, count do
      local school = debuffs[i].school
      local r = 3
      if school and mine and mine[school] then
        r = 1
      elseif school then
        r = 2
      end
      -- A debuff whose school already has its top-right icon is not drawn
      -- again (user decision, 2026-10-21): the spell icon only stays for
      -- what the type icons cannot show, such as physical debuffs.
      if r == rank and not (school and cell.flagged[school]) then
        n = n + 1
        ordered[n] = debuffs[i]
      end
    end
  end

  local shown = 0
  for i = 1, n do
    if shown >= R.maxDebuffs then break end
    shown = shown + 1
    local data = ordered[i]
    local slot = cell.debuffSlots[shown]
    if not slot then
      slot = NewAuraSlot(cell, true, cell.geo.debuffSize)
      cell.debuffSlots[shown] = slot
    end
    PlaceAura(cell, slot, shown, cell.geo.layout.debuffs, cell.geo.debuffSize,
              cell.auraOffset)
    slot.icon:SetTexture(data.texture)
    U.SetColor(slot.border, M.Unpack(R.debuffColor[data.school] or
                                     R.debuffColor.none))
    if slot.count then
      if data.count > 1 then
        slot.count:SetText(data.count)
        slot.count:Show()
      else
        slot.count:Hide()
      end
    end
    slot:Show()
  end
  HideSlots(cell.debuffSlots, shown + 1)
end

local function PaintHots(cell)
  local live = rf.hots
  local found = 0
  local testHots = nil
  if U.partyTest and type(U.PartyTestHots) == "function" and
     U.GetRaidFrameSetting("showHots") then
    -- "/uui party test" members carry their own HoTs; nil for a real unit.
    testHots = U.PartyTestHots(cell.unit, live)
  end
  if cell.fake then
    if U.GetRaidFrameSetting("showHots") then
      live = cell.fake.hots
      found = table.getn(live)
    end
  elseif testHots then
    found = testHots
  elseif U.GetRaidFrameSetting("showHots") and
         type(U.HotLiveOn) == "function" and
         not (U.PerfDisabled and U.PerfDisabled("hots")) then
    found = U.HotLiveOn(cell.unit, live)
  end

  cell.hotActive = nil
  local shown = 0
  local i
  for i = 1, found do
    if shown >= R.maxBuffs then break end
    shown = shown + 1
    local item = live[i]
    local slot = cell.buffs[shown]
    if not slot then
      slot = NewAuraSlot(cell, false, cell.geo.buffSize)
      cell.buffs[shown] = slot
    end
    PlaceAura(cell, slot, shown, cell.geo.layout.buffs, cell.geo.buffSize,
              cell.auraOffset or 0)
    slot.icon:SetTexture(item.entry.texture)
    if slot.count then
      if item.count > 1 then
        slot.count:SetText(item.count)
        slot.count:Show()
      else
        slot.count:Hide()
      end
    end
    slot.live = item.live
    slot:Show()
    cell.hotActive = true
  end
  HideSlots(cell.buffs, shown + 1)
end

local function PaintAuras(cell)
  PaintDebuffs(cell)
  PaintHots(cell)
end

-- Arithmetic only, like modules/hots.lua's TickWipes.
local function TickWipes()
  local now = Now()
  local index
  for index = 1, rf.shown do
    local cell = rf.active[index]
    if cell and cell.hotActive then
      local i
      for i = 1, table.getn(cell.buffs) do
        local slot = cell.buffs[i]
        if slot.live and slot:IsShown() then
          local progress = (now - slot.live.start) / slot.live.duration
          if progress >= 1 and slot.live.loop then
            slot.live.start = now
            progress = 0
          end
          if progress > 1 then progress = 1 end
          U.SetRadialWipeProgress(slot.wipe, progress)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Roster and layout
-- ---------------------------------------------------------------------------
local function ReadRoster()
  local members = {}
  local g
  for g = 1, GROUP_COUNT do members[g] = {} end

  if rf.preview then
    local i
    for i = 1, MAX_MEMBERS do
      local group = math.floor((i - 1) / GROUP_SIZE) + 1
      table.insert(members[group], { unit = "player", raidIndex = nil,
                                     fake = rf.test and rf.test[i] or nil })
    end
    return members
  end

  local count = tonumber(Call("GetNumRaidMembers")) or 0
  local fn = Fn("GetRaidRosterInfo")
  local i
  for i = 1, count do
    local subgroup = nil
    if fn then
      local ok, _, _, group = pcall(fn, i)
      if ok then subgroup = tonumber(group) end
    end
    if subgroup and members[subgroup] and
       table.getn(members[subgroup]) < GROUP_SIZE then
      table.insert(members[subgroup], { unit = "raid" .. i, raidIndex = i })
    end
  end
  return members
end

-- CompactRaidGroup_UpdateLayout, vertical groups with the border on: a title
-- row, the members flush below it, the border frame 2 out on three sides and
-- 3 below. Used groups flow left to right like CompactRaidFrameContainer's
-- discrete mode; empty groups take no space.
-- With the group border off (the Retail default) the box is hidden and the
-- columns sit flush, columnGap apart; titles are independent of it.
local function GroupMetrics()
  local boxed = U.GetRaidFrameSetting("groupBorder") and true or false
  local titled = U.GetRaidFrameSetting("groupTitles") and true or false
  local border = R.groupBorder
  return {
    boxed = boxed,
    titled = titled,
    title = titled and R.titleHeight or 0,
    left = boxed and border.left or 0,
    right = boxed and border.right or 0,
    bottom = boxed and border.bottom or 0,
    gap = boxed and R.groupGap or R.columnGap,
  }
end

-- Puts one cell in use for one roster entry. A preview entry paints the
-- player and owns no unit token, so events never route to it.
local function Assign(cell, entry, preview)
  cell.unit = entry.unit
  cell.raidIndex = entry.raidIndex
  cell.fake = entry.fake
  cell:Show()
  SizeCell(cell)
  cell.nameText = nil
  if not preview and not entry.preview then rf.byUnit[cell.unit] = cell end
  rf.shown = rf.shown + 1
  rf.active[rf.shown] = cell
end

local function HidePool(pool, from)
  local i
  for i = from, table.getn(pool) do
    pool[i].unit = nil
    pool[i]:Hide()
  end
end

local function Layout(members)
  local x, used, cellIndex = 0, 0, 0
  local metrics = GroupMetrics()
  local geo = Geometry()
  local tallest = 0
  local g

  for g = 1, GROUP_COUNT do
    local list = members[g]
    local count = table.getn(list)
    if count > 0 then
      used = used + 1
      local group = Group(g)
      local height = metrics.title + count * geo.height
      group:ClearAllPoints()
      group:SetPoint("TOPLEFT", rf.root, "TOPLEFT", x + metrics.left, 0)
      group:SetWidth(geo.width)
      if group.title then group.title:SetWidth(geo.width) end
      group:SetHeight(height)

      group.background:ClearAllPoints()
      group.background:SetPoint("TOPLEFT", group, "TOPLEFT",
                                -R.groupBorder.left, R.groupBorder.top)
      group.background:SetPoint("BOTTOMRIGHT", group, "BOTTOMRIGHT",
                                R.groupBorder.right, -R.groupBorder.bottom)
      if metrics.boxed then
        group.background:Show()
      else
        group.background:Hide()
      end
      if group.title then
        if metrics.titled then group.title:Show() else group.title:Hide() end
      end
      group:Show()

      local m
      for m = 1, count do
        cellIndex = cellIndex + 1
        local cell = Cell(cellIndex)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", group, "TOPLEFT", 0,
                      -metrics.title - (m - 1) * geo.height)
        Assign(cell, list[m], rf.preview)
      end

      x = x + metrics.left + geo.width + metrics.right + metrics.gap
      if height + metrics.bottom > tallest then
        tallest = height + metrics.bottom
      end
    elseif rf.groups[g] then
      rf.groups[g]:Hide()
    end
  end

  HidePool(rf.cells, cellIndex + 1)

  -- With nobody to show the root keeps a full 40-member footprint, so the
  -- mover has something to place outside a raid.
  if used == 0 then
    x = GROUP_COUNT * (metrics.left + geo.width + metrics.right + metrics.gap)
    tallest = metrics.title + GROUP_SIZE * geo.height + metrics.bottom
  end
  rf.root:SetWidth(x - metrics.gap > 0 and x - metrics.gap or 1)
  rf.root:SetHeight(tallest > 0 and tallest or 1)
end

-- ---------------------------------------------------------------------------
-- Party block as raid cells (Party Frames option "Raid-style party frames",
-- user request 2026-10-26). The same cells, settings and aura layout as the
-- raid, stacked in one vertical column on the party mover's anchor. The
-- party rows (modules/unitframes.lua) hide while it is on and size the anchor
-- from U.RaidPartyFootprint. Pets are not drawn: raid cells have none.
-- ---------------------------------------------------------------------------
local PARTY_MEMBERS = 4

local function PartyStyle()
  return type(U.PartyRaidStyleActive) == "function" and
         U.PartyRaidStyleActive() and true or false
end

local function Unlocked()
  return type(U.IsUnlocked) == "function" and U.IsUnlocked() and true or false
end

-- Same occupancy test the party rows use: GetPartyMember keeps a member
-- through a zone transition where UnitExists briefly fails.
local function PartyMemberPresent(index)
  if Call("UnitExists", "party" .. index) then return true end
  return Call("GetPartyMember", index) and true or false
end

local function PartyPlayerWanted()
  return type(U.GetUnitFramePartySetting) == "function" and
         U.GetUnitFramePartySetting("partyPlayer") and true or false
end

-- Polled every tick: PARTY_MEMBERS_CHANGED was never observed on this client
-- (modules/unitframes.lua header), so the roster cannot wait for it.
local function PartyShape()
  if type(U.PartyFramesSuppressedByRaid) == "function" and
     U.PartyFramesSuppressedByRaid() then
    return "R"
  end
  local shape = (Unlocked() and "U" or "-") ..
                (PartyPlayerWanted() and "P" or "-")
  local i
  for i = 1, PARTY_MEMBERS do
    shape = shape .. (PartyMemberPresent(i) and "1" or "0")
  end
  return shape
end

-- Player first when the Party Frames option shows yourself, then party1-4.
-- In edit mode an empty slot previews the player, so the column dragged into
-- place is the tallest it can become.
local function ReadPartyRoster()
  local list, grouped, unlocked = {}, false, Unlocked()
  local present = {}
  local i
  for i = 1, PARTY_MEMBERS do
    present[i] = PartyMemberPresent(i)
    if present[i] then grouped = true end
  end
  if PartyPlayerWanted() and (grouped or unlocked) then
    table.insert(list, { unit = "player" })
  end
  for i = 1, PARTY_MEMBERS do
    if present[i] then
      -- raidIndex is the dropdown id; the PARTY popup takes the party index.
      table.insert(list, { unit = "party" .. i, raidIndex = i })
    elseif unlocked then
      table.insert(list, { unit = "player", preview = true })
    end
  end
  return list
end

local function PartyRoot()
  local party = rf.party
  if party.root then return party.root end
  local anchor = type(U.PartyAnchorFrame) == "function" and
                 U.PartyAnchorFrame() or nil
  if not anchor then return nil end
  party.root = CreateFrame("Frame", "UnrealUIPartyRaid", anchor)
  party.root:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  party.root:SetWidth(1)
  party.root:SetHeight(1)
  return party.root
end

local function LayoutParty()
  local party = rf.party
  party.shape = nil
  if not PartyStyle() then
    party.count = 0
    HidePool(party.cells, 1)
    if party.root then party.root:Hide() end
    return
  end

  local root = PartyRoot()
  if not root then
    -- The party anchor is built by modules/unitframes.lua; try next tick.
    rf.rosterDirty = true
    return
  end

  party.shape = PartyShape()
  if party.shape == "R" then
    party.count = 0
    HidePool(party.cells, 1)
    if party.root then party.root:Hide() end
    return
  end
  Geometry()
  local geo = rf.partyGeo
  local list = ReadPartyRoster()
  local count = table.getn(list)
  local m
  for m = 1, count do
    local cell = PartyCell(m)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(m - 1) * geo.height)
    Assign(cell, list[m])
  end
  HidePool(party.cells, count + 1)
  party.count = count
  root:SetWidth(geo.width)
  root:SetHeight((count > 0 and count or 1) * geo.height)
  root:Show()

  if type(U.RelayoutPartyBlock) == "function" then U.RelayoutPartyBlock() end
end

-- The party anchor's size while the raid-style column replaces the rows, in
-- the anchor's own units (the cells are its children). nil when it is off.
function U.RaidPartyFootprint()
  if not rf.running or not rf.party.root or not PartyStyle() then return nil end
  Geometry()
  local geo = rf.partyGeo
  local count = rf.party.count
  if count < 1 then count = PARTY_MEMBERS + 1 end
  return geo.width, count * geo.height
end

local function PaintAll()
  local i
  for i = 1, rf.shown do
    local cell = rf.active[i]
    PaintVitals(cell)
    PaintSelection(cell)
    PaintAuras(cell)
  end
end

local function RefreshRoster()
  rf.rosterDirty = false
  local key
  for key in pairs(rf.byUnit) do rf.byUnit[key] = nil end
  rf.shown = 0

  if Enabled() then
    Layout(ReadRoster())
    rf.root:Show()
  else
    HidePool(rf.cells, 1)
    if rf.root then rf.root:Hide() end
  end
  LayoutParty()

  local i
  for i = table.getn(rf.active), rf.shown + 1, -1 do rf.active[i] = nil end
  PaintAll()
end

-- A settings change (page or /uui raid) relays out and repaints at once;
-- under another theme the module never built its root and there is nothing
-- to redraw.
ApplySettings = function()
  -- The Enable checkbox starts or stops the whole module; anything else is a
  -- relayout of the running frames.
  if rf.applyEnabled then rf.applyEnabled() end
  if rf.running then RefreshRoster() end
end

-- ---------------------------------------------------------------------------
-- Updates
--
-- Events are accelerators, not the mechanism (the same stance as
-- modules/unitframes.lua): a cell named by UNIT_HEALTH / UNIT_AURA repaints
-- on the next tick, and a slow sweep repaints everything anyway. Auras are
-- swept a few cells per tick so a 40-member raid never reads 640 debuff slots
-- in one frame.
-- ---------------------------------------------------------------------------
local AURAS_PER_TICK = 8

local function CellFor(unit)
  if type(unit) ~= "string" then return nil end
  return rf.byUnit[unit]
end

local function Tick()
  if not rf.rosterDirty and PartyStyle() and
     PartyShape() ~= rf.party.shape then
    rf.rosterDirty = true
  end
  if rf.rosterDirty then RefreshRoster() end
  if rf.shown == 0 then return end

  local i
  for i = 1, rf.shown do
    local cell = rf.active[i]
    if cell.vitalsDirty then
      cell.vitalsDirty = nil
      PaintVitals(cell)
    end
    if cell.aurasDirty then
      cell.aurasDirty = nil
      PaintAuras(cell)
    end
  end

  local sweep = AURAS_PER_TICK
  if sweep > rf.shown then sweep = rf.shown end
  for i = 1, sweep do
    if rf.auraCursor > rf.shown then rf.auraCursor = 1 end
    local cell = rf.active[rf.auraCursor]
    rf.auraCursor = rf.auraCursor + 1
    if cell then
      PaintVitals(cell)
      PaintAuras(cell)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Test data (/uui raid test, user request 2026-10-21)
--
-- Forty generated members so every state can be checked outside a raid:
-- the nine 1.12 classes, random health and power with the right power type,
-- a few dead, offline and out-of-range members, debuffs of every school
-- (stacks included) so the borders, dispel icons and overlay all show, the
-- player's three HoTs with running, looping timers, both incoming-heal
-- segments, and one selected cell. Nothing here touches the client: the
-- cells are still "player" for clicks and tooltips, but paint from the
-- record. Icon paths are stock 1.12 Interface\Icons files.
-- ---------------------------------------------------------------------------
local TEST = {
  classes = { "WARRIOR", "MAGE", "ROGUE", "DRUID", "HUNTER", "SHAMAN",
              "PRIEST", "WARLOCK", "PALADIN" },
  names = { "Aldric", "Brenna", "Cael", "Doran", "Elwin", "Fenna", "Garrick",
            "Hesta", "Ilyas", "Jorund", "Kaela", "Lothar", "Mirelle",
            "Nathanos", "Orla", "Perrin", "Quenna", "Rowan", "Sylvara",
            "Thoradin", "Ulric", "Vesna", "Wendel", "Xandra", "Yorick",
            "Zelda", "Bartholomew", "Anastasia" },
  debuffs = {
    { texture = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
      school = "Magic" },
    { texture = "Interface\\Icons\\Spell_Frost_FrostNova",
      school = "Magic" },
    { texture = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
      school = "Curse" },
    { texture = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
      school = "Poison" },
    { texture = "Interface\\Icons\\Spell_Shadow_CallofBone",
      school = "Disease" },
    { texture = "Interface\\Icons\\Ability_Gouge" },
  },
  hots = {
    { texture = "Interface\\Icons\\Spell_Nature_Rejuvenation",
      duration = 12 },
    { texture = "Interface\\Icons\\Spell_Holy_Renew", duration = 15 },
    { texture = "Interface\\Icons\\Spell_Nature_ResistNature",
      duration = 21 },
  },
}

local function Chance(percent)
  return math.random(100) <= percent
end

local function TestMember(now)
  local class = TEST.classes[math.random(table.getn(TEST.classes))]
  local maximum = math.random(20, 60) * 100
  local f = {
    name = TEST.names[math.random(table.getn(TEST.names))],
    class = class,
    maximum = maximum,
    health = math.random(math.floor(maximum / 10), maximum),
    connected = true,
    dead = false,
    mine = 0,
    others = 0,
    debuffs = {},
    hots = {},
  }

  if Chance(5) then
    f.connected = false
  elseif Chance(5) then
    f.dead = true
    f.health = 0
  end
  f.far = f.connected and Chance(10)

  if class == "WARRIOR" then
    f.powerType, f.powerMax = 1, 100
  elseif class == "ROGUE" then
    f.powerType, f.powerMax = 3, 100
  else
    f.powerType, f.powerMax = 0, math.random(20, 50) * 100
  end
  f.power = math.random(0, f.powerMax)

  local alive = f.connected and not f.dead
  if alive and Chance(45) then
    f.mine = math.floor(maximum * math.random(5, 30) / 100)
  end
  if alive and Chance(25) then
    f.others = math.floor(maximum * math.random(5, 20) / 100)
  end

  if alive then
    local n = math.random(0, 4)
    local i
    for i = 1, n do
      local d = TEST.debuffs[math.random(table.getn(TEST.debuffs))]
      table.insert(f.debuffs, { texture = d.texture, school = d.school,
                                count = Chance(20) and math.random(2, 5) or 1 })
    end

    local k
    for k = 1, table.getn(TEST.hots) do
      if Chance(40) then
        local h = TEST.hots[k]
        table.insert(f.hots, {
          entry = { texture = h.texture },
          live = { start = now - math.random(0, h.duration - 1),
                   duration = h.duration, loop = true },
          count = 1,
        })
      end
    end
  end
  return f
end

local TEST_SCHOOLS = { "Magic", "Curse", "Poison", "Disease" }

local function SchoolDebuff(school)
  local i
  for i = 1, table.getn(TEST.debuffs) do
    if TEST.debuffs[i].school == school then
      return { texture = TEST.debuffs[i].texture, school = school, count = 1 }
    end
  end
end

-- Puts a debuff of `school` first on member `index` and keeps it alive and
-- online, so its dispel icon is guaranteed to draw.
local function ForceSchool(list, index, school)
  local f = list[index]
  f.connected, f.dead, f.far = true, false, false
  if f.health <= 0 then f.health = f.maximum end
  table.insert(f.debuffs, 1, SchoolDebuff(school))
end

local function RollTest()
  math.randomseed(math.floor(Now() * 1000))
  local list = {}
  local now = Now()
  local i
  for i = 1, MAX_MEMBERS do list[i] = TestMember(now) end

  -- Every dispel icon on every roll: group 1's first four members carry one
  -- school each, and its fifth carries three, the most a cell shows.
  for i = 1, table.getn(TEST_SCHOOLS) do
    ForceSchool(list, i, TEST_SCHOOLS[i])
  end
  ForceSchool(list, 5, "Poison")
  ForceSchool(list, 5, "Curse")
  ForceSchool(list, 5, "Magic")

  list[math.random(MAX_MEMBERS)].selected = true
  return list
end

-- /uui raid: fills all forty cells with the player so the frames can be
-- checked outside a raid; run again to stop.
-- /uui raid test: forty generated members instead (see TEST); run it again to
-- reroll, /uui raid to stop.
-- /uui raid titles | border: toggles the "Group N" titles or the group box.
local TOGGLES = {
  titles = { key = "groupTitles", on = "RAID_TITLES_ON", off = "RAID_TITLES_OFF" },
  border = { key = "groupBorder", on = "RAID_BORDER_ON", off = "RAID_BORDER_OFF" },
}

function U.RaidFramesCommand(rest)
  if not Enabled() then
    U.Print(U.L("RAID_UNAVAILABLE"))
    return
  end

  local word = type(rest) == "string" and string.lower(rest) or ""
  word = string.gsub(word, "^%s*(%S*).*$", "%1")
  local toggle = TOGGLES[word]
  if toggle then
    local value = not U.GetRaidFrameSetting(toggle.key)
    U.SetRaidFrameSetting(toggle.key, value)
    U.Print(U.L(value and toggle.on or toggle.off))
    if type(U.RefreshRaidFrameSettingsView) == "function" then
      U.RefreshRaidFrameSettingsView()
    end
    return
  end

  if word == "test" then
    rf.preview = true
    rf.test = RollTest()
    U.Print(U.L("RAID_TEST_ON"))
    RefreshRoster()
    return
  end

  rf.preview = not rf.preview
  rf.test = nil
  U.Print(U.L(rf.preview and "RAID_PREVIEW_ON" or "RAID_PREVIEW_OFF"))
  RefreshRoster()
end

-- The Raid Frames settings group lives in modules/raidframesettings.lua.
function RF:OnInit()
  if type(U.RegisterRaidFrameSettings) == "function" then
    U.RegisterRaidFrameSettings()
  end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
--
-- The Enable checkbox is a real off switch (user request, 2026-10-21), so
-- another raid addon or the client's own raid UI can be used instead: with it
-- off nothing is built at login, and turning it off later hides the frames,
-- stops both update tickers and leaves every event handler with no cell to
-- touch. UnrealUI never suppresses any native raid frame, so nothing has to be
-- given back. Events cannot be unregistered through U.RegisterEvent, which is
-- why the handlers below are registered once and check rf.running.
-- ---------------------------------------------------------------------------
local function RegisterEventsOnce()
  if rf.eventsRegistered then return end
  rf.eventsRegistered = true

  local function MarkRoster() rf.rosterDirty = true end
  local roster = { "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED",
                   "PLAYER_ENTERING_WORLD" }
  local i
  for i = 1, table.getn(roster) do U.RegisterEvent(roster[i], MarkRoster) end

  local vitals = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MANA",
                   "UNIT_MAXMANA", "UNIT_RAGE", "UNIT_ENERGY",
                   "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE" }
  for i = 1, table.getn(vitals) do
    U.RegisterEvent(vitals[i], function(event, unit)
      if not rf.running then return end
      local cell = CellFor(unit or U.G("arg1"))
      if cell then cell.vitalsDirty = true end
    end)
  end

  U.RegisterEvent("UNIT_AURA", function(event, unit)
    if not rf.running then return end
    local cell = CellFor(unit or U.G("arg1"))
    if cell then cell.aurasDirty = true end
  end)

  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not rf.running then return end
    local index
    for index = 1, rf.shown do PaintSelection(rf.active[index]) end
  end)
end

local function Start()
  if rf.running then return end
  rf.running = true

  if not rf.root then
    rf.root = CreateFrame("Frame", "UnrealUIRaid", UIParent)
    rf.root:SetWidth(1)
    rf.root:SetHeight(1)
    rf.root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -320)

    U.RegisterMover("raid", rf.root, {
      label = U.L("MOVER_LABEL_RAID"),
      default = { point = "TOPLEFT", relativePoint = "TOPLEFT",
                  x = 20, y = -320 },
      visible = function() return Enabled() end,
      scalable = true,
    })
  end

  RegisterEventsOnce()
  U.RegisterUpdate("raidframes.tick", 0.2, Tick)
  U.RegisterUpdate("raidframes.wipes", 0.1, TickWipes)
  rf.rosterDirty = true
  RefreshRoster()
end

local function Stop()
  if not rf.running then return end
  rf.running = false
  rf.preview = false
  rf.test = nil

  U.UnregisterUpdate("raidframes.tick")
  U.UnregisterUpdate("raidframes.wipes")

  local key
  for key in pairs(rf.byUnit) do rf.byUnit[key] = nil end
  HidePool(rf.cells, 1)
  HidePool(rf.party.cells, 1)
  local i
  for i = table.getn(rf.active), 1, -1 do rf.active[i] = nil end
  rf.shown = 0
  rf.party.count = 0
  rf.party.shape = nil
  if rf.root then rf.root:Hide() end
  if rf.party.root then rf.party.root:Hide() end
end

-- Follows the Enable setting, under every theme, and the Party Frames
-- raid-style option, which needs the same ticker without the raid itself.
local function ApplyEnabled()
  if not rf.ready then return end
  if Enabled() or PartyStyle() then Start() else Stop() end
end

-- Called by modules/unitframes.lua when the raid-style party option changes.
function U.ApplyRaidPartyStyle()
  rf.rosterDirty = true
  ApplyEnabled()
  if rf.running then RefreshRoster() end
end

function RF:OnEnable()
  local _, class = Call("UnitClass", "player")
  rf.playerClass = type(class) == "string" and string.upper(class) or nil

  rf.ready = true
  ApplyEnabled()
end

rf.applyEnabled = ApplyEnabled
