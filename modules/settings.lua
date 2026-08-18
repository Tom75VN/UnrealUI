-- unrealUI :: modules/settings.lua
--
-- The settings window behind /uui and the minimap button.
--
-- Layout follows the reference design: the addon name and version across the
-- top, a category list down the left side where a group can be collapsed to
-- hide its pages, and the selected page filling the rest. The accent colour
-- (#f5ae0a, core/media.lua) marks headings, groups and the selected row.
--
-- It is still not a config framework. There is no schema, no profile machinery
-- and no data binding: a module registers a page, builds its own controls with
-- core/widgets.lua, and owns its own values. This file only decides what is on
-- screen.
--
-- knowledge.json / rendering.parent_alpha_not_propagated: nothing here relies
-- on a parent's visibility reaching its children. Every region is toggled by
-- hand, which is what the per-page widget lists are for.

local U = UnrealUI
local M = U.media

local S = U.RegisterModule("settings")

local PANEL_WIDTH = 700
local PANEL_HEIGHT = 520
local SIDEBAR_WIDTH = 168
local ROW_HEIGHT = 18
local ROW_GAP = 1
local HEADER_HEIGHT = 46
local FOOTER_HEIGHT = 46

local panel, sidebar, content
local entries = {}     -- ordered: { kind, id, label, build, parent, expanded, ... }
local rows = {}        -- sidebar row button pool
local activePage       -- entry currently shown in the content area

local RenderSidebar    -- forward declarations; rows and pages call each other
local SelectPage

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------
local function SetShown(region, show)
  if not region then return end

  -- Composite controls from core/widgets.lua are a plain table of parts rather
  -- than a frame, so they are toggled through the list they carry.
  if region.uuiParts then
    local i
    for i = 1, table.getn(region.uuiParts) do
      SetShown(region.uuiParts[i], show)
    end
    return
  end

  if show then region:Show() else region:Hide() end
  if region.label then
    if show then region.label:Show() else region.label:Hide() end
  end
end

local function SetListShown(list, show)
  if type(list) ~= "table" then return end
  local i
  for i = 1, table.getn(list) do SetShown(list[i], show) end
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
local function FindEntry(id)
  local i
  for i = 1, table.getn(entries) do
    if entries[i].id == id then return entries[i], i end
  end
  return nil
end

-- A collapsible heading in the category list. Groups hold pages; they have no
-- content of their own and clicking one expands or collapses it.
function U.RegisterSettingsGroup(id, label)
  if type(id) ~= "string" then
    U.Error("RegisterSettingsGroup requires an id")
    return nil
  end
  if FindEntry(id) then
    U.Error("settings entry already registered: " .. id)
    return nil
  end

  local entry = {
    kind = "group",
    id = id,
    label = label or id,
    expanded = false,
  }
  table.insert(entries, entry)

  if panel then RenderSidebar() end
  return entry
end

-- id       stable key
-- label    row text
-- build    build(content) -> widgets[, refresh]
--          widgets is the array of regions shown with the page; refresh, when
--          returned, runs every time the page is opened.
-- options  { parent = "<group id>" } to nest the page under a group.
function U.RegisterSettingsTab(id, label, build, options)
  if type(id) ~= "string" or type(build) ~= "function" then
    U.Error("RegisterSettingsTab requires an id and a build function")
    return nil
  end
  if FindEntry(id) then
    U.Error("settings entry already registered: " .. id)
    return nil
  end

  options = options or {}

  local entry = {
    kind = "page",
    id = id,
    label = label or id,
    build = build,
    parent = options.parent,
  }
  table.insert(entries, entry)

  if panel then RenderSidebar() end
  return entry
end

-- ---------------------------------------------------------------------------
-- Category list
--
-- Rows are a reused pool: expanding a group re-labels and re-points the rows it
-- needs and hides the rest, so collapsing never leaves an orphan button behind.
-- ---------------------------------------------------------------------------
local function VisibleEntries()
  local visible, i = {}, nil

  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry.kind == "group" then
      table.insert(visible, entry)
    elseif not entry.parent then
      table.insert(visible, entry)
    else
      local parent = FindEntry(entry.parent)
      if parent and parent.expanded then table.insert(visible, entry) end
    end
  end

  return visible
end

local function StyleRow(row, entry, selected)
  local text = entry.label
  local color = M.color.text

  if entry.kind == "group" then
    -- Groups read as headings: accent text plus the expand indicator on the
    -- right, which is the only thing in the list that is not a page.
    color = M.color.accent
    if row.indicator then
      row.indicator:SetText(entry.expanded and "-" or "+")
      row.indicator:Show()
    end
  else
    if row.indicator then row.indicator:Hide() end
    if selected then color = M.color.accent end
  end

  if row.label then
    row.label:SetText(text)
    pcall(row.label.SetTextColor, row.label, M.Unpack(color))
  end

  row.selected = selected and true or false
  if row.selected then
    U.SetBackgroundColor(row, M.Unpack(M.color.accentFill))
  else
    U.SetBackgroundColor(row, 0, 0, 0, 0)
  end
end

local function CreateRow(index)
  local row = U.CreateButton(sidebar, {
    name = "UnrealUISettingsRow" .. index,
    text = "",
    width = SIDEBAR_WIDTH - 12,
    height = ROW_HEIGHT,
    border = false,
  })

  -- The row's own label is left-aligned and indented per level, which
  -- U.CreateButton's centred label cannot do, so it is replaced here.
  if row.label then
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    pcall(row.label.SetWidth, row.label, SIDEBAR_WIDTH - 44)
    pcall(row.label.SetJustifyH, row.label, "LEFT")
  end

  row.indicator = U.CreateLabel(row, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
  })
  if row.indicator then
    row.indicator:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end

  -- A borderless row has no outline to highlight, so hover is carried by the
  -- fill. The selected row keeps its accent fill and ignores hover.
  row:SetScript("OnEnter", function()
    if not row.selected then U.SetBackgroundColor(row, 1, 1, 1, 0.07) end
  end)
  row:SetScript("OnLeave", function()
    if not row.selected then U.SetBackgroundColor(row, 0, 0, 0, 0) end
  end)

  rows[index] = row
  return row
end

RenderSidebar = function()
  if not sidebar then return end

  local visible = VisibleEntries()
  local i

  for i = 1, table.getn(visible) do
    local entry = visible[i]
    local row = rows[i] or CreateRow(i)

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6,
                 -6 - (i - 1) * (ROW_HEIGHT + ROW_GAP))

    -- Pages under a group sit one indent in, so the list reads as a tree
    -- without needing a second column of art.
    if row.label then
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", entry.parent and 18 or 8, 0)
      pcall(row.label.SetWidth, row.label,
            SIDEBAR_WIDTH - (entry.parent and 54 or 44))
    end

    row.entry = entry
    row:SetScript("OnClick", function()
      local target = row.entry
      if not target then return end

      if target.kind == "group" then
        target.expanded = not target.expanded
        RenderSidebar()
      else
        SelectPage(target)
      end
    end)

    StyleRow(row, entry, activePage and activePage.id == entry.id)

    row:Show()
    if row.label then row.label:Show() end
    if row.indicator and entry.kind == "group" then row.indicator:Show() end
  end

  -- Hide the tail of the pool left over from a wider list.
  for i = table.getn(visible) + 1, table.getn(rows) do
    local row = rows[i]
    row.entry = nil
    if row.label then row.label:Hide() end
    if row.indicator then row.indicator:Hide() end
    row:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------
SelectPage = function(entry)
  if not entry or entry.kind ~= "page" then return end

  local i
  for i = 1, table.getn(entries) do
    local other = entries[i]
    if other ~= entry then SetListShown(other.widgets, false) end
  end

  if not entry.widgets then
    local widgets, refresh = entry.build(content)
    entry.widgets = widgets or {}
    entry.refresh = refresh
  end

  SetListShown(entry.widgets, true)
  if type(entry.refresh) == "function" then entry.refresh() end

  activePage = entry
  RenderSidebar()
end

-- Opens a page by id, expanding its group first. Modules use this to send the
-- user straight at their own options.
function U.OpenSettingsPage(id)
  local entry = FindEntry(id)
  if not entry or entry.kind ~= "page" then return false end

  if entry.parent then
    local parent = FindEntry(entry.parent)
    if parent then parent.expanded = true end
  end

  U.OpenSettings(true)
  SelectPage(entry)
  return true
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
local function HideContents()
  if not panel then return end

  SetListShown(panel.chrome, false)

  local i
  for i = 1, table.getn(rows) do
    if rows[i].label then rows[i].label:Hide() end
    if rows[i].indicator then rows[i].indicator:Hide() end
    rows[i]:Hide()
  end
  for i = 1, table.getn(entries) do SetListShown(entries[i].widgets, false) end

  sidebar:Hide()
  content:Hide()
end

local function Hide()
  if not panel then return end

  HideContents()
  panel:Hide()
end

local function Build()
  panel = U.CreatePanel(UIParent, {
    name = "UnrealUISettings",
    width = PANEL_WIDTH,
    height = PANEL_HEIGHT,
  })
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  pcall(panel.SetFrameStrata, panel, "HIGH")

  panel.chrome = {}

  -- WORKING_SOURCE: UnrealPfUI and unrealUI's own bag window use
  -- UISpecialFrames for Escape-to-close. The panel owns child visibility
  -- explicitly, so cover direct client hides as well as the Close button.
  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUISettings")
  end
  panel:SetScript("OnHide", function() HideContents() end)

  panel.title = U.CreateLabel(panel, {
    size = M.fontSize.large,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if panel.title then
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    panel.title:SetText("Unreal")
    table.insert(panel.chrome, panel.title)
  end

  panel.titleUI = U.CreateLabel(panel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if panel.titleUI then
    panel.titleUI:SetPoint("LEFT", panel.title, "RIGHT", 4, 0)
    panel.titleUI:SetText("UI")
    table.insert(panel.chrome, panel.titleUI)
  end

  panel.version = U.CreateLabel(panel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
  })
  if panel.version then
    panel.version:SetPoint("LEFT", panel.titleUI or panel.title, "RIGHT", 8, -1)
    panel.version:SetText("v" .. U.version)
    table.insert(panel.chrome, panel.version)
  end

  local rule = U.CreateRule(panel, { color = M.color.accentDim })
  if rule then
    rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(HEADER_HEIGHT - 12))
    rule:SetWidth(PANEL_WIDTH - 24)
    table.insert(panel.chrome, rule)
  end

  sidebar = U.CreatePanel(panel, {
    name = "UnrealUISettingsSidebar",
    width = SIDEBAR_WIDTH,
    height = PANEL_HEIGHT - HEADER_HEIGHT - FOOTER_HEIGHT,
    background = { 0.03, 0.03, 0.03, 0.90 },
  })
  sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -HEADER_HEIGHT)

  -- The content frame is a positioning anchor. Its children are toggled through
  -- the owning page's widget list, never through this frame.
  content = CreateFrame("Frame", "UnrealUISettingsContent", panel)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
  content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, FOOTER_HEIGHT)

  panel.close = U.CreateButton(panel, {
    name = "UnrealUISettingsClose",
    text = "Close",
    width = 100,
    height = 24,
    onClick = function() Hide() end,
  })
  panel.close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
  table.insert(panel.chrome, panel.close)

  panel:Hide()
  sidebar:Hide()
  content:Hide()
  SetListShown(panel.chrome, false)
end

-- Single entry point: /uui and the minimap button both call this, so they can
-- never diverge (see core/commands.lua). keepOpen skips the toggle, which is
-- what U.OpenSettingsPage needs.
function U.OpenSettings(keepOpen)
  if not panel then Build() end

  local ok, shown = pcall(panel.IsShown, panel)
  if ok and shown then
    if keepOpen then return end
    Hide()
    return
  end

  panel:Show()
  sidebar:Show()
  content:Show()
  SetListShown(panel.chrome, true)

  RenderSidebar()

  -- Open on the last page used, or on the first page in the list.
  if activePage then
    SelectPage(activePage)
  else
    local i
    for i = 1, table.getn(entries) do
      if entries[i].kind == "page" then
        SelectPage(entries[i])
        return
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- General page
--
-- The original panel's contents: edit mode and the position reset. Registered
-- here rather than in core so the window has no special-cased first page.
-- ---------------------------------------------------------------------------
local function BuildGeneralPage(parent)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = "General",
    width = PANEL_WIDTH - SIDEBAR_WIDTH - 36,
    y = -4,
  })
  table.insert(widgets, header)

  local move = U.CreateButton(parent, {
    name = "UnrealUISettingsMove",
    text = "Move UI",
    width = 220,
    height = 26,
    onClick = function()
      -- The window would sit on top of the edit panel and the frames being
      -- placed, so opening edit mode closes it.
      Hide()
      U.UnlockUI()
    end,
  })
  move:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, move)

  local reset = U.CreateButton(parent, {
    name = "UnrealUISettingsReset",
    text = "Reset frame positions",
    width = 220,
    height = 26,
    onClick = function() U.ResetPositions() end,
  })
  reset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -66)
  table.insert(widgets, reset)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if hint then
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -106)
    hint:SetText("Drag frames onto the grid in edit mode. " ..
                 "Hold Shift while dropping for free placement.")
    table.insert(widgets, hint)
  end

  -- The micro bar (modules/microbar.lua) has a single setting, so its toggle
  -- lives here rather than on a dedicated tab of its own.
  local microbar = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMicroBar",
    text = "Enable micro bar",
    value = U.ModuleConfig("microbar", { enabled = true }).enabled,
    onChange = function(value)
      U.ModuleConfig("microbar", { enabled = true }).enabled = value
      if type(U.ApplyMicroBar) == "function" then U.ApplyMicroBar() end
    end,
  })
  microbar.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -140)
  table.insert(widgets, microbar)

  local microbarHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if microbarHint then
    microbarHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -164)
    microbarHint:SetText("Pulls the native character/spellbook/talent/quest " ..
                         "log/social/map/menu/help buttons into one movable " ..
                         "row. Disabling returns them to their stock location.")
    table.insert(widgets, microbarHint)
  end

  -- The reputation bar (modules/xpbar.lua) is the only other single-setting
  -- overlay; the XP bar itself is required scope and has no toggle.
  local reputation = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsReputationBar",
    text = "Show reputation bar",
    value = U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled,
    onChange = function(value)
      U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled = value
      if type(U.ApplyXPBar) == "function" then U.ApplyXPBar() end
    end,
  })
  reputation.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -196)
  table.insert(widgets, reputation)

  local function Refresh()
    microbar.SetValue(U.ModuleConfig("microbar", { enabled = true }).enabled)
    reputation.SetValue(U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled)
  end

  return widgets, Refresh
end

function S:OnInit()
  U.RegisterSettingsTab("general", "General", BuildGeneralPage)
end

function S:OnEnable()
  -- Built lazily on first open; nothing to do here beyond making sure the
  -- module exists in the registry for /uui check.
end
