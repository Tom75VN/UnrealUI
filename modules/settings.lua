-- unrealUI :: modules/settings.lua
--
-- The settings window behind /uui and the minimap button.
--
-- Layout follows the reference design: the addon name and version across the
-- top, a category list down the left side where a group can be collapsed to
-- hide its pages, and the selected page filling the rest. The accent colour
-- (#f5ae0a, core/media.lua) marks headings, groups and the selected row.
--
-- It is still not a config framework. Profile persistence belongs to
-- core/config.lua, and there is no general schema or data binding: a module
-- registers a page, builds its own controls with
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
-- Content area is PANEL_HEIGHT less the header and footer, and the fullest
-- page in the addon (Unit Frames: party, auras, dispel types and colours) is
-- what sets the floor. Raised from 520 when the party-frame section was added
-- to that page; every other page simply gains bottom margin.
local PANEL_HEIGHT = 580
local SIDEBAR_WIDTH = 168
local ROW_HEIGHT = 18
local ROW_GAP = 1
local HEADER_HEIGHT = 46
local FOOTER_HEIGHT = 46

local panel, sidebar, content
local entries = {}     -- ordered: { kind, id, label, build, parent, expanded, ... }
local rows = {}        -- sidebar row button pool
local activePage       -- entry currently shown in the content area
local focusedId        -- id of the single row (page or expanded group, at any
                        -- depth) currently carrying the accent highlight

local RenderSidebar    -- forward declarations; rows and pages call each other
local SelectPage

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------
local function SetShown(region, show)
  if not region then return end

  if type(region.uuiSetShown) == "function" then
    region.uuiSetShown(show)
    return
  end

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
-- options  { parent = "<group id>", after = "<entry id>", muted = true,
--            tooltip = "..." }.
--          Muted pages remain selectable so they can explain why their normal
--          controls are unavailable; only their sidebar presentation changes.
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
    muted = options.muted and true or false,
    tooltip = options.tooltip,
  }
  local afterIndex
  if options.after then
    local _, index = FindEntry(options.after)
    afterIndex = index
  end
  if afterIndex then
    table.insert(entries, afterIndex + 1, entry)
  else
    table.insert(entries, entry)
  end

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

-- Accordion behaviour: only one group (at any depth) stays expanded at a
-- time. Collapses every group except keepId, which future nested submenus
-- get for free since it only checks entry.kind, not depth or identity.
local function CollapseOtherGroups(keepId)
  local i
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry.kind == "group" and entry.id ~= keepId and entry.expanded then
      entry.expanded = false
      if focusedId == entry.id then focusedId = nil end
    end
  end
end

local function StyleRow(row, entry, selected)
  local text = entry.label
  local color = M.color.text

  if entry.kind == "group" then
    -- Groups read as headings: white text plus the expand indicator on the
    -- right, which is the only thing in the list that is not a page. Like a
    -- selected page, a focused (expanded) group switches to accent text.
    color = selected and M.color.accent or M.color.text
    if row.indicator then
      row.indicator:SetText(entry.expanded and "-" or "+")
      row.indicator:Show()
    end
  else
    if entry.muted then
      color = M.color.textDim
      if row.indicator then
        row.indicator:SetText("x")
        row.indicator:Show()
      end
    else
      if row.indicator then row.indicator:Hide() end
      if selected then color = M.color.accent end
    end
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
    row.label:SetPoint("LEFT", row, "LEFT", 8, -1)
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

    local entry = row.entry
    if not entry or type(entry.tooltip) ~= "string" or entry.tooltip == "" then
      return
    end
    local tooltip = U.G("GameTooltip")
    if not tooltip then return end
    pcall(tooltip.SetOwner, tooltip, row, "ANCHOR_RIGHT")
    pcall(tooltip.SetText, tooltip, entry.tooltip)
    pcall(tooltip.Show, tooltip)
  end)
  row:SetScript("OnLeave", function()
    if not row.selected then U.SetBackgroundColor(row, 0, 0, 0, 0) end
    local tooltip = U.G("GameTooltip")
    if tooltip then pcall(tooltip.Hide, tooltip) end
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
                 -34 - (i - 1) * (ROW_HEIGHT + ROW_GAP))

    -- Pages under a group sit one indent in, so the list reads as a tree
    -- without needing a second column of art.
    if row.label then
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", entry.parent and 18 or 8, -1)
      pcall(row.label.SetWidth, row.label,
            SIDEBAR_WIDTH - (entry.parent and 54 or 44))
    end

    row.entry = entry
    row:SetScript("OnClick", function()
      local target = row.entry
      if not target then return end

      if target.kind == "group" then
        target.expanded = not target.expanded
        if target.expanded then CollapseOtherGroups(target.id) end
        -- Only one row is ever highlighted: expanding a group claims the
        -- highlight, collapsing it releases the highlight (rather than
        -- falling back to whatever page used to hold it), and this holds at
        -- any depth for any future nested submenu.
        focusedId = target.expanded and target.id or nil
        RenderSidebar()
      else
        SelectPage(target)
      end
    end)

    StyleRow(row, entry, focusedId ~= nil and focusedId == entry.id)

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

  -- Picking a page outside the open group (or a top-level page while any
  -- group is open) collapses that group, same as clicking another group.
  CollapseOtherGroups(entry.parent)

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
  focusedId = entry.id
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
-- Language selector
--
-- Four flat badges in the top-right of the header, opposite the addon name.
-- Not a dropdown: there are only four languages, and a player who has just
-- landed in one they cannot read needs the way back to be visible on screen
-- rather than one click inside a closed control.
--
-- Each registered locale uses its flag from M.languageFlag. The ASCII language
-- code remains the fallback for a future locale whose artwork is not available.
--
-- Changing language does not retranslate what is already on screen: every
-- label in this addon is written once when its page is built. The reload
-- prompt is the same one core/theme.lua's theme switch uses.
-- ---------------------------------------------------------------------------
local LANGUAGE_BUTTON_WIDTH = 18
local LANGUAGE_BUTTON_HEIGHT = 14
local LANGUAGE_BUTTON_GAP = 3
local LANGUAGE_BUTTON_RIGHT_INSET = 14
local LANGUAGE_BUTTON_TOP_INSET = 10

local function LanguageSelectorInset()
  local count = table.getn(U.GetLanguages())
  -- The drag handle is raised above normal header children. Reserve the
  -- selector's full width plus its right margin and one gap, otherwise the
  -- handle intercepts every language-button click.
  return LANGUAGE_BUTTON_RIGHT_INSET +
         count * LANGUAGE_BUTTON_WIDTH + count * LANGUAGE_BUTTON_GAP
end

local languageButtons = {}

local function RefreshLanguageButtons()
  local active = U.GetLanguage()
  local i
  for i = 1, table.getn(languageButtons) do
    local button = languageButtons[i]
    local selected = button.uuiLanguage == active

    -- The flags have no added chrome. Selection is communicated only through
    -- opacity: full for the active language and 30% for the other choices.
    -- SetVertexColor alpha goes through U.SetColor because Texture:SetAlpha
    -- darkens instead of compositing reliably on this client.
    if button.uuiFlag then
      U.SetColor(button.uuiFlag, 1, 1, 1, selected and 1 or 0.3)
    end
    if button.label then
      pcall(button.label.SetTextColor, button.label,
            M.Unpack(selected and M.color.accent or M.color.textDim))
    end
    button.uuiSelected = selected
  end
end

local function BuildLanguageSelector(parent)
  local languages = U.GetLanguages()
  local count = table.getn(languages)
  local i

  for i = 1, count do
    local entry = languages[i]

    local button = U.CreateButton(parent, {
      name = "UnrealUISettingsLanguage" .. entry.code,
      -- A flag texture owns the whole face, so the badge text is dropped for
      -- any code that has artwork.
      text = M.languageFlag[entry.code] and "" or entry.short,
      size = M.fontSize.tiny,
      width = LANGUAGE_BUTTON_WIDTH,
      height = LANGUAGE_BUTTON_HEIGHT,
      background = { 0, 0, 0, 0 },
      border = false,
    })
    button.uuiLanguage = entry.code

    -- Right to left from the header's right edge, so the row keeps the 14px
    -- title inset no matter how many languages are registered. The flags use
    -- a compact 18x14 footprint, twenty percent smaller than the previous size.
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT",
                    -LANGUAGE_BUTTON_RIGHT_INSET - (count - i) *
                          (LANGUAGE_BUTTON_WIDTH + LANGUAGE_BUTTON_GAP),
                    -LANGUAGE_BUTTON_TOP_INSET)

    if M.languageFlag[entry.code] and button.CreateTexture then
      local flag = button:CreateTexture(nil, "ARTWORK")
      flag:SetTexture(M.languageFlag[entry.code])
      flag:SetAllPoints(button)
      button.uuiFlag = flag
    end

    -- Inactive flags brighten to 95% while hovered. The selected flag remains
    -- at 100%, so pointing at it never makes the current choice look weaker.
    button:SetScript("OnEnter", function()
      if button.uuiSelected then return end
      if button.uuiFlag then U.SetColor(button.uuiFlag, 1, 1, 1, 0.95) end
    end)
    button:SetScript("OnLeave", function()
      if button.uuiSelected then return end
      if button.uuiFlag then U.SetColor(button.uuiFlag, 1, 1, 1, 0.3) end
    end)

    button:SetScript("OnClick", function()
      if not U.SetLanguage(entry.code) then return end
      RefreshLanguageButtons()
      -- Deliberately confirmed in the language just chosen. If the client's
      -- font has no glyphs for it the dialog comes up blank, which is the
      -- fastest possible signal that this language will not render -- and the
      -- English flag remains one visible click away.
      U.ShowConfirm({
        owner = "settings.language-reload",
        centered = true,
        text = U.L("SETTINGS_LANGUAGE_CHANGED"),
        detail = U.L("SETTINGS_LANGUAGE_RELOAD", entry.label),
        acceptText = U.L("COMMON_OK_SHORT"),
        cancelText = U.L("COMMON_CLOSE"),
      })
    end)

    table.insert(languageButtons, button)
    table.insert(parent.chrome, button)
  end

  RefreshLanguageButtons()
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
local function HideContents()
  if not panel then return end

  -- A colour picker (core/widgets.lua) would otherwise leave its dialog open
  -- over a page that is about to be torn down, with callbacks still pointing
  -- at the hidden control. Closing without accepting also restores whatever
  -- colour was live-previewed, so an abandoned edit does not silently stick.
  if type(U.CloseColorPicker) == "function" then U.CloseColorPicker(false) end

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
  U.MakeWindowDraggable("settings", panel,
                         { headerHeight = HEADER_HEIGHT,
                           headerInset = LanguageSelectorInset() })

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

  BuildLanguageSelector(panel)

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

  -- Edit mode is a primary action rather than a setting, so it remains at the
  -- top of the menu no matter which settings page is selected.
  sidebar.move = U.CreateButton(sidebar, {
    name = "UnrealUISettingsMove",
    text = U.L("SETTINGS_MOVE_UI"),
    width = SIDEBAR_WIDTH - 12,
    height = 22,
    onClick = function()
      -- The window would sit on top of the edit panel and the frames being
      -- placed, so opening edit mode closes it.
      Hide()
      U.UnlockUI()
    end,
  })
  sidebar.move:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -6)
  table.insert(panel.chrome, sidebar.move)

  -- The content frame is a positioning anchor. Its children are toggled through
  -- the owning page's widget list, never through this frame.
  content = CreateFrame("Frame", "UnrealUISettingsContent", panel)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
  content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, FOOTER_HEIGHT)

  panel.close = U.CreateButton(panel, {
    name = "UnrealUISettingsClose",
    text = U.L("COMMON_CLOSE"),
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

-- Closes the window without toggling it back open. A mode that takes over the
-- screen (modules/quickbind.lua) uses this rather than U.OpenSettings, which
-- would reopen an already-closed panel.
function U.CloseSettings()
  Hide()
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
-- Profile page
--
-- Named profiles are account-wide and selectable by every character. The
-- active profile assignment and all storage operations stay in core/config.lua;
-- this page only presents those operations with shared controls.
-- ---------------------------------------------------------------------------
local function BuildProfilePage(parent)
  local widgets = {}
  local pageWidth = PANEL_WIDTH - SIDEBAR_WIDTH - 36

  local function AddLabel(text, x, y, color, width)
    local label = U.CreateSettingsLabel(parent, {
      size = M.fontSize.small,
      color = color or M.color.text,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = width,
    })
    if label then
      label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
      label:SetText(text)
      table.insert(widgets, label)
    end
    return label
  end

  local function AddHint(text, control)
    local hint = U.CreateSettingsLabel(parent, {
      size = M.fontSize.small,
      color = M.color.textDim,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = pageWidth,
    })
    if hint and control then
      U.AnchorSettingsDescription(hint, control)
      hint:SetText(text)
      table.insert(widgets, hint)
    end
    return hint
  end

  local function ProfileItems(excludeCurrent, deleteOnly)
    local result = {}
    local names = deleteOnly and U.GetDeletableProfileNames() or
                  U.GetProfileNames(excludeCurrent)
    local i
    for i = 1, table.getn(names) do
      table.insert(result, { value = names[i], text = names[i] })
    end
    if table.getn(result) == 0 then
      table.insert(result, {
        value = "__none__",
        text = U.L("PROFILE_NONE_OTHER"),
        disabled = true,
      })
    end
    return result
  end

  local function ReloadNotice(message)
    U.CloseSettings()
    U.Print(U.L("PROFILE_RELOAD_NOTICE", message))
  end

  local header = U.CreateSectionHeader(parent, {
    text = U.L("SETTINGS_PAGE_PROFILES"),
    width = pageWidth,
    y = -4,
  })
  table.insert(widgets, header)

  AddLabel(U.L("PROFILE_SELECT"), 0, -32, M.color.accent, 220)
  local selectProfile = U.CreateDropdown(parent, {
    name = "UnrealUISettingsSelectProfile",
    value = U.GetCurrentProfileName(),
    width = 470,
    height = 24,
    rowHeight = 20,
    items = ProfileItems(false, false),
    onChange = function(value)
      if value ~= U.GetCurrentProfileName() and U.SelectProfile(value) then
        ReloadNotice(U.L("PROFILE_SELECTED", value))
      end
    end,
  })
  selectProfile.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -49)
  table.insert(widgets, selectProfile)
  AddHint(U.L("PROFILE_SELECT_HINT"), selectProfile.button)

  local create = U.CreateButton(parent, {
    name = "UnrealUISettingsCreateProfile",
    text = U.L("PROFILE_CREATE_COPY"),
    width = 220,
    height = 24,
    onClick = function()
      local name = U.NextProfileName()
      if not name then
        U.Print(U.L("PROFILE_NO_NAME_FREE"))
        return
      end
      if U.CreateProfile(name) then
        ReloadNotice(U.L("PROFILE_CREATED", name))
      end
    end,
  })
  create:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -105)
  table.insert(widgets, create)
  AddHint(U.L("PROFILE_CREATE_HINT"), create)

  AddLabel(U.L("PROFILE_COPY_FROM"), 0, -164, M.color.accent, 220)
  local copyFrom = U.CreateDropdown(parent, {
    name = "UnrealUISettingsCopyProfile",
    width = 220,
    height = 24,
    rowHeight = 20,
    items = ProfileItems(true, false),
  })
  copyFrom.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -181)
  table.insert(widgets, copyFrom)
  if not copyFrom.GetValue() and copyFrom.button.label then
    copyFrom.button.label:SetText(U.L("PROFILE_NONE_OTHER"))
  end

  local copyButton = U.CreateButton(parent, {
    name = "UnrealUISettingsCopyProfileButton",
    text = U.L("PROFILE_COPY_SETTINGS"),
    width = 220,
    height = 24,
    onClick = function()
      local source = copyFrom.GetValue()
      if source and source ~= "__none__" and U.CopyProfile(source) then
        ReloadNotice(U.L("PROFILE_COPIED", source,
                         U.GetCurrentProfileName()))
      end
    end,
  })
  copyButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 250, -183)
  table.insert(widgets, copyButton)
  AddHint(U.L("PROFILE_COPY_HINT"), copyFrom.button)

  AddLabel(U.L("PROFILE_DELETE_SECTION"), 0, -239, M.color.accent, 220)
  local deleteProfile = U.CreateDropdown(parent, {
    name = "UnrealUISettingsDeleteProfile",
    width = 220,
    height = 24,
    rowHeight = 20,
    items = ProfileItems(true, true),
  })
  deleteProfile.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -256)
  table.insert(widgets, deleteProfile)
  if not deleteProfile.GetValue() and deleteProfile.button.label then
    deleteProfile.button.label:SetText(U.L("PROFILE_NONE_OTHER"))
  end

  local armedDelete
  local deleteButton
  deleteButton = U.CreateButton(parent, {
    name = "UnrealUISettingsDeleteProfileButton",
    text = U.L("PROFILE_DELETE"),
    textColor = { 1, 0.35, 0.35, 1 },
    width = 220,
    height = 24,
    onClick = function()
      local name = deleteProfile.GetValue()
      if not name or name == "__none__" then return end
      if armedDelete ~= name then
        armedDelete = name
        if deleteButton and deleteButton.label then
          deleteButton.label:SetText(U.L("PROFILE_CONFIRM_DELETE"))
        end
        U.Print(U.L("PROFILE_CLICK_CONFIRM_DELETE", name))
        return
      end
      if U.DeleteProfile(name) then
        ReloadNotice(U.L("PROFILE_DELETED", name))
      end
    end,
  })
  deleteButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 250, -258)
  table.insert(widgets, deleteButton)
  AddHint(U.L("PROFILE_DELETE_HINT"), deleteProfile.button)

  AddLabel(U.L("PROFILE_RESET_SECTION"), 0, -314, M.color.accent, 220)
  local resetArmed = false
  local reset
  reset = U.CreateButton(parent, {
    name = "UnrealUISettingsResetProfile",
    text = U.L("PROFILE_RESET"),
    width = 220,
    height = 24,
    onClick = function()
      if not resetArmed then
        resetArmed = true
        if reset.label then reset.label:SetText(U.L("PROFILE_CONFIRM_RESET")) end
        U.Print(U.L("PROFILE_CLICK_CONFIRM_RESET"))
        return
      end
      local name = U.GetCurrentProfileName()
      if U.ResetCurrentProfile() then
        ReloadNotice(U.L("PROFILE_WAS_RESET", name))
      end
    end,
  })
  reset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -331)
  table.insert(widgets, reset)

  local current = AddLabel(U.L("PROFILE_CURRENT", U.GetCurrentProfileName()),
                           250, -334, M.color.text, 220)
  AddHint(U.L("PROFILE_RESET_HINT"), reset)

  local function Refresh()
    selectProfile.SetValue(U.GetCurrentProfileName(), false)
    if current then
      current:SetText(U.L("PROFILE_CURRENT", U.GetCurrentProfileName()))
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- General page
--
-- Shared settings and controls for features too small to need their own page.
-- Registered here rather than in core so the window has no special-cased page.
-- ---------------------------------------------------------------------------
local function BuildGeneralPage(parent)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("SETTINGS_PAGE_GENERAL"),
    width = PANEL_WIDTH - SIDEBAR_WIDTH - 36,
    y = -4,
  })
  table.insert(widgets, header)

  local themeLabel = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if themeLabel then
    themeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -32)
    themeLabel:SetText(U.L("SETTINGS_THEME_STYLE"))
    table.insert(widgets, themeLabel)
  end

  local themeItems = {}
  local themeStyles = U.GetThemeStyles()
  local themeIndex
  for themeIndex = 1, table.getn(themeStyles) do
    local style = themeStyles[themeIndex]
    table.insert(themeItems, {
      value = style.id,
      text = style.label .. (style.wip and U.L("SETTINGS_THEME_WIP") or ""),
      disabled = not style.available,
    })
  end

  local themes = U.CreateRadioGroup(parent, {
    name = "UnrealUISettingsThemeStyle",
    value = U.GetThemeStyle(),
    width = 156,
    columns = 3,
    columnGap = 6,
    items = themeItems,
    onChange = function(value)
      if U.SetThemeStyle(value) and U.ThemeStyleRequiresReload() then
        U.ShowConfirm({
          owner = "settings.theme-reload",
          centered = true,
          text = U.L("SETTINGS_THEME_CHANGED"),
          detail = U.L("SETTINGS_THEME_RELOAD",
                       tostring(U.GetThemeStyleLabel(value))),
          acceptText = U.L("COMMON_OK_SHORT"),
          cancelText = U.L("COMMON_CLOSE"),
        })
      end
    end,
  })
  themes.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -52)
  table.insert(widgets, themes)

  local themeHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if themeHint and themes.firstRow then
    -- The selector uses three columns, but the description spans the whole
    -- settings page. Anchor it below the leftmost row so its width stays
    -- within the content panel instead of starting under the last column.
    U.AnchorSettingsDescription(themeHint, themes.firstRow)
    themeHint:SetText(U.L("SETTINGS_THEME_HINT"))
    table.insert(widgets, themeHint)
  end

  -- Quick binding (modules/quickbind.lua) is a mode, like edit mode above, so
  -- it lives beside it rather than only on the ActionBars page. Registered
  -- lazily, same as everything else this window links out to: if the module
  -- failed to load, the button still shows and says so instead of vanishing.
  local quickbind = U.CreateButton(parent, {
    name = "UnrealUISettingsQuickBind",
    text = U.L("SETTINGS_QUICKBIND"),
    width = 220,
    height = 26,
    onClick = function()
      Hide()
      if type(U.OpenQuickBind) == "function" then
        U.OpenQuickBind()
      else
        U.Error(U.L("QUICKBIND_UNAVAILABLE"))
      end
    end,
  })
  quickbind:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -102)
  table.insert(widgets, quickbind)

  local quickbindHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if quickbindHint then
    U.AnchorSettingsDescription(quickbindHint, quickbind)
    quickbindHint:SetText(U.L("SETTINGS_QUICKBIND_HINT"))
    table.insert(widgets, quickbindHint)
  end

  -- The micro bar (modules/microbar.lua) has a single setting, so its toggle
  -- lives here rather than on a dedicated tab of its own.
  local microbar = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMicroBar",
    text = U.L("SETTINGS_MICROBAR"),
    value = U.ModuleConfig("microbar", { enabled = true }).enabled,
    onChange = function(value)
      U.ModuleConfig("microbar", { enabled = true }).enabled = value
      if type(U.ApplyMicroBar) == "function" then U.ApplyMicroBar() end
    end,
  })
  microbar.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -164)
  table.insert(widgets, microbar)

  local microbarHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if microbarHint then
    U.AnchorSettingsDescription(microbarHint, microbar.box)
    microbarHint:SetText(U.L("SETTINGS_MICROBAR_HINT"))
    table.insert(widgets, microbarHint)
  end

  -- The reputation bar (modules/xpbar.lua) is the only other single-setting
  -- overlay; the XP bar itself is required scope and has no toggle.
  local reputation = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsReputationBar",
    text = U.L("SETTINGS_REPUTATION_BAR"),
    value = U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled,
    onChange = function(value)
      U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled = value
      if type(U.ApplyXPBar) == "function" then U.ApplyXPBar() end
    end,
  })
  reputation.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -220)
  table.insert(widgets, reputation)

  -- The minimap settings button (modules/minimap.lua) is the normal way to
  -- reach this window, so hiding it does not lock the player out: the /uui
  -- slash command still opens settings.
  local minimapButton = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsMinimapButton",
    text = U.L("SETTINGS_MINIMAP_BUTTON"),
    value = U.ModuleConfig("minimap", { enabled = true }).enabled,
    onChange = function(value)
      U.ModuleConfig("minimap", { enabled = true }).enabled = value
      if type(U.ApplyMinimapButton) == "function" then U.ApplyMinimapButton() end
    end,
  })
  minimapButton.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -252)
  table.insert(widgets, minimapButton)

  -- The world map zone level ranges (modules/worldmap.lua) are a single
  -- readout on an otherwise untouched native screen, so like the micro bar and
  -- the reputation bar their toggle lives here instead of on a tab of its own.
  local zoneLevels = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsZoneLevels",
    text = U.L("SETTINGS_ZONE_LEVELS"),
    value = U.ModuleConfig("worldmap", { zoneLevels = true }).zoneLevels,
    onChange = function(value)
      U.ModuleConfig("worldmap", { zoneLevels = true }).zoneLevels = value
      if type(U.ApplyWorldMapZoneLevels) == "function" then
        U.ApplyWorldMapZoneLevels()
      end
    end,
  })
  zoneLevels.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -284)
  table.insert(widgets, zoneLevels)

  local zoneLevelsHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if zoneLevelsHint then
    U.AnchorSettingsDescription(zoneLevelsHint, zoneLevels.box)
    zoneLevelsHint:SetText(U.L("SETTINGS_ZONE_LEVELS_HINT"))
    table.insert(widgets, zoneLevelsHint)
  end

  local function Refresh()
    themes.SetValue(U.GetThemeStyle(), false)
    microbar.SetValue(U.ModuleConfig("microbar", { enabled = true }).enabled)
    reputation.SetValue(U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled)
    minimapButton.SetValue(U.ModuleConfig("minimap", { enabled = true }).enabled)
    zoneLevels.SetValue(U.ModuleConfig("worldmap", { zoneLevels = true }).zoneLevels)
  end

  return widgets, Refresh
end

function S:OnInit()
  U.RegisterSettingsTab("general", U.L("SETTINGS_PAGE_GENERAL"), BuildGeneralPage)
  U.RegisterSettingsTab("profiles", U.L("SETTINGS_PAGE_PROFILES"), BuildProfilePage,
                        { after = "general" })
end

function S:OnEnable()
  -- Built lazily on first open; nothing to do here beyond making sure the
  -- module exists in the registry for /uui check.
end
