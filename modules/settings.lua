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
-- page in the addon (Unit Frames: party, power ticks, combo placement, auras,
-- dispel types and colours) is what sets the floor. Every other page simply
-- gains bottom margin.
local PANEL_HEIGHT = 704
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
local OpenStandaloneSettings

-- The unified Game Settings window uses the same registered pages rather than
-- maintaining a second settings schema. It supplies the outer category list;
-- this state owns only the scrollable page canvas inside that window.
local integrated = {
  width = PANEL_WIDTH - SIDEBAR_WIDTH - 24,
  height = PANEL_HEIGHT - HEADER_HEIGHT - FOOTER_HEIGHT,
  offset = 0,
  -- Every UnrealUI and Unreal Quest page sits this far left of the host box,
  -- closer to the category list (user request, 2026-09-22: 10 left). The
  -- scroll frame moves rather than the canvas, so the stepper pad inside the
  -- sheet is not clipped.
  shiftX = -10,
}

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
--
-- options  { after = "<entry id>", defaultPage = "<page id>" }.
--          after places the group like RegisterSettingsTab's option does;
--          defaultPage is opened whenever a click expands the group.
function U.RegisterSettingsGroup(id, label, options)
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
    -- Open by default, and each group opens and closes on its own; no
    -- accordion (user request, 2026-09-23).
    expanded = true,
  }

  options = options or {}
  entry.defaultPage = options.defaultPage

  local afterIndex
  if options.after then
    local _, index = FindEntry(options.after)
    afterIndex = index
  end

  -- Same default placement as RegisterSettingsTab: slot in ahead of profiles
  -- so a group registered after it (e.g. action bar options, whose OnInit
  -- runs later in module order) doesn't end up stranded past its own pages.
  local _, profilesIndex = FindEntry("profiles")
  if afterIndex then
    table.insert(entries, afterIndex + 1, entry)
  elseif profilesIndex then
    table.insert(entries, profilesIndex, entry)
  else
    table.insert(entries, entry)
  end

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
  elseif id ~= "profiles" and id ~= "unrealquest" then
    -- Profiles stays the last built-in page; anything registering without an
    -- explicit "after" slots in ahead of it instead of past it. UnrealQuest's
    -- tab (registered late, via host polling from the sibling addon) is the
    -- one entry meant to land after profiles, so it keeps the plain append.
    local _, profilesIndex = FindEntry("profiles")
    if profilesIndex then
      table.insert(entries, profilesIndex, entry)
    else
      table.insert(entries, entry)
    end
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
        -- A group with a default page opens it on expand; SelectPage claims
        -- the highlight and re-renders the list itself.
        local default = not target.expanded and target.defaultPage
                        and FindEntry(target.defaultPage)
        if default and default.kind == "page" then
          target.expanded = true
          SelectPage(default)
          return
        end
        target.expanded = not target.expanded
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

-- Re-runs the shown page's refresh callback so it cannot keep displaying a
-- value that was changed somewhere else. A page is normally refreshed when it
-- is selected; this is for settings a second surface can write while the window
-- is open, which the edit-mode anchor panel is the first of. Pass the page id to
-- refresh only that page.
function U.RefreshSettingsPage(id)
  if not activePage then return false end
  if id and activePage.id ~= id then return false end
  if type(activePage.refresh) ~= "function" then return false end
  activePage.refresh()
  return true
end

-- Opens a page by id, expanding its group first. Modules use this to send the
-- user straight at their own options.
function U.OpenSettingsPage(id)
  local entry = FindEntry(id)
  if not entry or entry.kind ~= "page" then return false end

  if type(U.OpenGameSettings) == "function" and
     type(U.SelectIntegratedSettingsPage) == "function" then
    local scope = U.SettingsEntryScope(entry)
    U.OpenGameSettings(scope)
    U.SelectIntegratedSettingsPage(id, scope)
    if U.gameSettings then
      local gs = U.gameSettings
      local frame = U.G("UnrealUIGameSettingsUI")
      local level
      if gs.host and type(gs.Number) == "function" then
        level = gs.Number(gs.host, "GetFrameLevel")
      end
      if frame and level and type(gs.Relevel) == "function" then
        gs.Relevel(frame, level + 1, 0)
      end
      if type(gs.RenderList) == "function" then gs.RenderList() end
    end
    return true
  end

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

local function BuildLanguageSelector(parent, topInset, namePrefix)
  local languages = U.GetLanguages()
  local count = table.getn(languages)
  local built = {}
  local i

  for i = 1, count do
    local entry = languages[i]

    local button = U.CreateButton(parent, {
      name = (namePrefix or "UnrealUISettingsLanguage") .. entry.code,
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
                    -(topInset or LANGUAGE_BUTTON_TOP_INSET))

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
    table.insert(built, button)
    if type(parent.chrome) == "table" then table.insert(parent.chrome, button) end
  end

  RefreshLanguageButtons()
  return built
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
  if type(U.CloseGameSettings) == "function" and U.gameSettings and
     U.gameSettings.active and U.gameSettings.active.settings then
    U.CloseGameSettings()
    return
  end
  Hide()
end

-- Single entry point: /uui and the minimap button both call this, so they can
-- never diverge (see core/commands.lua). keepOpen skips the toggle, which is
-- what U.OpenSettingsPage needs.
OpenStandaloneSettings = function(keepOpen)
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

function U.OpenSettings(keepOpen)
  if type(U.OpenGameSettings) ~= "function" then
    OpenStandaloneSettings(keepOpen)
    return
  end

  local gs = U.gameSettings
  if not keepOpen and gs and gs.panel and gs.active and
     gs.active.settings then
    local shown = false
    pcall(function() shown = gs.panel:IsShown() and true or false end)
    if shown then
      U.CloseGameSettings()
      return
    end
  end
  Hide()
  U.OpenGameSettings("unrealui")
end

-- ---------------------------------------------------------------------------
-- Unified Game Settings canvas
-- ---------------------------------------------------------------------------

-- The Game Settings window lists these entries under two categories (user
-- request, 2026-09-22): UnrealQuest's group -- registered by the sibling
-- addon as "unrealquest" -- and its pages are the "Unreal Quest" category;
-- everything else is "Unreal UI". The group itself is not a row there: its
-- category header already names it, so its pages sit directly beneath.
function U.SettingsEntryScope(entry)
  if type(entry) == "string" then entry = FindEntry(entry) end
  if not entry then return nil end
  if entry.id == "unrealquest" or entry.parent == "unrealquest" then
    return "unrealquest"
  end
  return "unrealui"
end

-- Whether any selectable page is registered under a scope; the Unreal Quest
-- category exists only while UnrealQuest is installed and has registered.
function U.HasIntegratedSettingsScope(scope)
  local i
  for i = 1, table.getn(entries) do
    if entries[i].kind == "page" and
       U.SettingsEntryScope(entries[i]) == (scope or "unrealui") then
      return true
    end
  end
  return false
end

local function IntegratedEntry(id, scope)
  local entry = FindEntry(id)
  if entry and entry.kind == "page" and
     (not scope or U.SettingsEntryScope(entry) == scope) then
    return entry
  end
  return nil
end

local function IntegratedDefault(scope)
  scope = scope or "unrealui"
  if activePage and U.SettingsEntryScope(activePage) == scope then
    return activePage
  end
  local i
  for i = 1, table.getn(entries) do
    if entries[i].kind == "page" and U.SettingsEntryScope(entries[i]) == scope then
      return entries[i]
    end
  end
  return nil
end

-- Navigation rows consumed by modules/gamesettings.lua. Group headings expose
-- their expansion state; the pages beneath them remain the selectable rows.
function U.GetIntegratedSettingsTabs(scope)
  scope = scope or "unrealui"
  local tabs = {}
  local i
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if scope == "unrealquest" then
      if entry.kind == "page" and U.SettingsEntryScope(entry) == scope then
        table.insert(tabs, {
          name = entry.id,
          label = entry.label,
          selected = activePage == entry,
          unavailable = false,
          muted = entry.muted and true or false,
          settings = true,
          indent = 0,
        })
      end
    elseif U.SettingsEntryScope(entry) == scope then
      if entry.kind == "group" then
        table.insert(tabs, {
          name = "settings-group:" .. entry.id,
          label = entry.label,
          unavailable = true,
          settingsHeader = true,
          settingsGroup = entry.id,
          collapsed = not entry.expanded,
        })
      elseif entry.kind == "page" then
        local visible = not entry.parent
        if entry.parent then
          local parent = FindEntry(entry.parent)
          visible = parent and parent.expanded
        end
        if visible then
          table.insert(tabs, {
            name = entry.id,
            label = entry.label,
            selected = activePage == entry,
            unavailable = false,
            muted = entry.muted and true or false,
            settings = true,
            indent = entry.parent and 7 or 0,
          })
        end
      end
    end
  end
  return tabs
end

function U.SetIntegratedSettingsGroupExpanded(id, expanded)
  local entry = FindEntry(id)
  if not entry or entry.kind ~= "group" then return false end
  entry.expanded = expanded and true or false
  return true
end

local function IntegratedPaintArrows()
  if not integrated.bar then return end
  local low, high, value = 0, 0, 0
  pcall(function() low, high = integrated.bar:GetMinMaxValues() end)
  pcall(function() value = integrated.bar:GetValue() end)
  local function Set(suffix, enabled)
    local button = U.G("UnrealUIGameSettingsUIBar" .. suffix)
    if not button then return end
    if enabled then pcall(button.Enable, button) else pcall(button.Disable, button) end
  end
  Set("ScrollUpButton", value > low + 0.5)
  Set("ScrollDownButton", value < high - 0.5)
end

local function SetIntegratedOffset(value)
  local maximum = integrated.maximum or 0
  value = math.max(0, math.min(maximum, tonumber(value) or 0))
  integrated.offset = value
  if integrated.scroll and type(integrated.scroll.SetVerticalScroll) == "function" then
    pcall(integrated.scroll.SetVerticalScroll, integrated.scroll, value)
  end
  if integrated.bar then pcall(integrated.bar.SetValue, integrated.bar, value) end
  IntegratedPaintArrows()
end

local function IntegratedLeftPad()
  local gs = U.gameSettings
  if gs and type(gs.DropdownStepperPads) == "function" then
    local left = gs.DropdownStepperPads()
    if tonumber(left) and left > 0 then return left end
  end
  return 30
end

-- The addon's own settings pages share one canvas frame across every category
-- (SelectIntegratedSettingsPage only toggles a page's widgets with
-- SetListShown; the canvas itself is never rebuilt), so integrated.height --
-- a fixed constant sized for the standalone window -- cannot say how tall the
-- CURRENTLY selected page actually is. A short page (Unit Frames > General,
-- user report 2026-09-23) left the range at that constant, so the bar could
-- scroll well past the page's real content into blank space below it.
--
-- Measured the same way gs.Overhang already does for a hosted native panel
-- (modules/gamesettings.lua): only the canvas's DIRECT, currently visible
-- children -- which is exactly what SetListShown toggles -- so a hidden
-- page's widgets are never counted. The delta between the canvas's own top and
-- the lowest visible child's bottom is in on-screen units common to both, so
-- only the canvas's own applied scale (the sheet's, its parent, already
-- applied this pass by the time this runs) needs dividing back out.
local function IntegratedContentHeight(scale)
  local canvas = integrated.canvas
  if not canvas or type(canvas.GetTop) ~= "function" then
    return integrated.height
  end
  local top
  pcall(function() top = canvas:GetTop() end)
  if not top then return integrated.height end

  local count = 0
  pcall(function() count = canvas:GetNumChildren() end)
  if count < 1 or type(canvas.GetChildren) ~= "function" then
    return integrated.height
  end

  local ok, kids = pcall(function() return { canvas:GetChildren() } end)
  if not ok or not kids then return integrated.height end

  local lowest = top
  local i
  for i = 1, table.getn(kids) do
    local kid = kids[i]
    local visible
    pcall(function() visible = kid:IsVisible() end)
    if visible then
      local bottom
      pcall(function() bottom = kid:GetBottom() end)
      if bottom and bottom < lowest then lowest = bottom end
    end
  end

  if not scale or scale <= 0 then scale = 1 end
  return (top - lowest) / scale
end

local function LayoutIntegratedCanvas()
  if not integrated.root or not integrated.canvas or not integrated.sheet then return end
  local width, height
  pcall(function() width = integrated.root:GetWidth() end)
  pcall(function() height = integrated.root:GetHeight() end)
  width, height = tonumber(width) or 0, tonumber(height) or 0
  if width < 1 or height < 1 then return end

  local barWidth = 18
  local viewportWidth = math.max(1, width - barWidth - 4)
  local contentWidth = integrated.width + (integrated.leftPad or 0)
  local scale = math.min(1, viewportWidth / contentWidth)
  integrated.scale = scale
  pcall(integrated.sheet.SetScale, integrated.sheet, scale)

  -- What a page may fill without scrolling, in the page's own units: the
  -- visible box divided back out of the width fit above. The canvas frame is
  -- taller than this, so a page that sizes itself to its parent overflows and
  -- gains a scrollbar -- U.GetIntegratedSettingsPageHeight is what a page that
  -- lays itself out to the space available reads instead.
  integrated.viewport = height / scale
  local contentHeight = IntegratedContentHeight(scale)
  integrated.maximum = math.max(0, contentHeight - height / scale)
  if integrated.bar then
    pcall(integrated.bar.SetMinMaxValues, integrated.bar, 0, integrated.maximum)
    if integrated.maximum > 0 then
      pcall(integrated.bar.Show, integrated.bar)
      local up = U.G("UnrealUIGameSettingsUIBarScrollUpButton")
      local down = U.G("UnrealUIGameSettingsUIBarScrollDownButton")
      if up then pcall(up.Show, up) end
      if down then pcall(down.Show, down) end
      if type(U.SetModernWowScrollbarProportion) == "function" then
        U.SetModernWowScrollbarProportion(integrated.bar,
          height / scale, contentHeight)
      end
    else
      pcall(integrated.bar.Hide, integrated.bar)
      local up = U.G("UnrealUIGameSettingsUIBarScrollUpButton")
      local down = U.G("UnrealUIGameSettingsUIBarScrollDownButton")
      if up then pcall(up.Hide, up) end
      if down then pcall(down.Hide, down) end
    end
  end
  SetIntegratedOffset(integrated.offset)
end

-- The height a page built into this canvas can use before it scrolls. nil
-- until the canvas has been laid out once, which callers read as "no answer
-- yet" rather than as a height.
function U.GetIntegratedSettingsPageHeight()
  return tonumber(integrated.viewport)
end

local function BuildIntegratedCanvas(parent)
  if integrated.root then return end

  integrated.root = CreateFrame("Frame", "UnrealUIGameSettingsUI", parent)
  integrated.root:SetAllPoints(parent)
  pcall(integrated.root.EnableMouse, integrated.root, false)

  integrated.scroll = CreateFrame("ScrollFrame", "UnrealUIGameSettingsUIScroll",
                                  integrated.root)
  integrated.scroll:SetPoint("TOPLEFT", integrated.root, "TOPLEFT",
                             integrated.shiftX, 0)
  integrated.scroll:SetPoint("BOTTOMRIGHT", integrated.root, "BOTTOMRIGHT", -22, 0)
  pcall(integrated.scroll.EnableMouseWheel, integrated.scroll, true)

  integrated.leftPad = IntegratedLeftPad()
  integrated.sheet = CreateFrame("Frame", "UnrealUIGameSettingsUISheet",
                                 integrated.scroll)
  integrated.sheet:SetWidth(integrated.width + integrated.leftPad)
  integrated.sheet:SetHeight(integrated.height)

  integrated.canvas = CreateFrame("Frame", "UnrealUIGameSettingsUICanvas",
                                  integrated.sheet)
  integrated.canvas:SetWidth(integrated.width)
  integrated.canvas:SetHeight(integrated.height)
  integrated.canvas:SetPoint("TOPLEFT", integrated.sheet, "TOPLEFT",
                             integrated.leftPad, 0)
  pcall(integrated.scroll.SetScrollChild, integrated.scroll, integrated.sheet)

  integrated.bar = CreateFrame("Slider", "UnrealUIGameSettingsUIBar",
                               integrated.root)
  pcall(integrated.bar.SetOrientation, integrated.bar, "VERTICAL")
  integrated.bar:SetWidth(16)
  integrated.bar:SetPoint("TOPRIGHT", integrated.root, "TOPRIGHT", 0, -16)
  integrated.bar:SetPoint("BOTTOMRIGHT", integrated.root, "BOTTOMRIGHT", 0, 16)
  pcall(integrated.bar.SetValueStep, integrated.bar, 12)
  integrated.bar:SetScript("OnValueChanged", function()
    local value = 0
    pcall(function() value = integrated.bar:GetValue() end)
    if math.abs((integrated.offset or 0) - value) < 0.5 then return end
    integrated.offset = value
    if integrated.scroll and type(integrated.scroll.SetVerticalScroll) == "function" then
      pcall(integrated.scroll.SetVerticalScroll, integrated.scroll, value)
    end
    IntegratedPaintArrows()
  end)

  local function Arrow(suffix, direction)
    local button = CreateFrame("Button", "UnrealUIGameSettingsUIBar" .. suffix,
                               integrated.bar)
    button:SetScript("OnClick", function()
      SetIntegratedOffset((integrated.offset or 0) + direction * 36)
    end)
  end
  Arrow("ScrollUpButton", -1)
  Arrow("ScrollDownButton", 1)
  if type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(integrated.bar)
  end

  integrated.scroll:SetScript("OnMouseWheel", function()
    local delta = tonumber(arg1)
    if not delta or delta == 0 then return end
    SetIntegratedOffset((integrated.offset or 0) + (delta > 0 and -36 or 36))
  end)

  integrated.root:SetScript("OnShow", function()
    U.DeferOnce("gamesettings:unrealui-layout", LayoutIntegratedCanvas)
  end)
end

function U.SelectIntegratedSettingsPage(id, scope)
  local entry = IntegratedEntry(id, scope) or IntegratedDefault(scope)
  if not entry or not integrated.canvas then return false end

  if entry.parent then
    local parent = FindEntry(entry.parent)
    if parent and parent.kind == "group" then parent.expanded = true end
  end

  local i
  for i = 1, table.getn(entries) do
    if entries[i] ~= entry then SetListShown(entries[i].widgets, false) end
  end

  if not entry.widgets then
    local widgets, refresh = entry.build(integrated.canvas)
    entry.widgets = widgets or {}
    entry.refresh = refresh
  end
  if U.gameSettings and type(U.gameSettings.StyleIntegratedWidgets) == "function" then
    U.gameSettings.StyleIntegratedWidgets(entry.widgets)
  end
  SetListShown(entry.widgets, true)
  if type(entry.refresh) == "function" then entry.refresh() end
  activePage = entry
  focusedId = entry.id
  if U.gameSettings then U.gameSettings.revealSettingsSelection = true end
  -- A full relayout, not just a reset offset: this page's widgets just
  -- changed which are shown, and LayoutIntegratedCanvas is what remeasures
  -- integrated.maximum against the newly visible content (IntegratedContent-
  -- Height only sees IsVisible children, so a page switch has to redo it).
  integrated.offset = 0
  LayoutIntegratedCanvas()
  return true
end

function U.ShowIntegratedSettings(parent, id, scope)
  if not parent then return false end
  BuildIntegratedCanvas(parent)
  pcall(integrated.root.SetParent, integrated.root, parent)
  pcall(integrated.root.ClearAllPoints, integrated.root)
  pcall(integrated.root.SetAllPoints, integrated.root, parent)
  pcall(integrated.root.Show, integrated.root)
  pcall(integrated.scroll.Show, integrated.scroll)
  pcall(integrated.sheet.Show, integrated.sheet)
  pcall(integrated.canvas.Show, integrated.canvas)
  pcall(integrated.bar.Show, integrated.bar)
  local up = U.G("UnrealUIGameSettingsUIBarScrollUpButton")
  local down = U.G("UnrealUIGameSettingsUIBarScrollDownButton")
  if up then pcall(up.Show, up) end
  if down then pcall(down.Show, down) end
  LayoutIntegratedCanvas()
  return U.SelectIntegratedSettingsPage(id, scope)
end

function U.HideIntegratedSettings()
  local i
  for i = 1, table.getn(entries) do SetListShown(entries[i].widgets, false) end
  if integrated.scroll then pcall(integrated.scroll.Hide, integrated.scroll) end
  if integrated.sheet then pcall(integrated.sheet.Hide, integrated.sheet) end
  if integrated.canvas then pcall(integrated.canvas.Hide, integrated.canvas) end
  if integrated.bar then pcall(integrated.bar.Hide, integrated.bar) end
  local up = U.G("UnrealUIGameSettingsUIBarScrollUpButton")
  local down = U.G("UnrealUIGameSettingsUIBarScrollDownButton")
  if up then pcall(up.Hide, up) end
  if down then pcall(down.Hide, down) end
  if integrated.root then pcall(integrated.root.Hide, integrated.root) end
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

  if parent == integrated.canvas then
    local languages = BuildLanguageSelector(parent, 32,
                                            "UnrealUIGameSettingsLanguage")
    local languageIndex
    for languageIndex = 1, table.getn(languages) do
      table.insert(widgets, languages[languageIndex])
    end
  end

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
    width = 144,
    columns = 3,
    columnGap = 2,
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
      U.CloseSettings()
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

  local autoAttack = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsAutoAttack",
    text = U.L("SETTINGS_AUTO_ATTACK"),
    value = U.ModuleConfig("autoattack", { enabled = false }).enabled,
    onChange = function(value)
      U.ModuleConfig("autoattack", { enabled = false }).enabled = value
    end,
  })
  autoAttack.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -164)
  table.insert(widgets, autoAttack)

  local autoAttackHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if autoAttackHint then
    U.AnchorSettingsDescription(autoAttackHint, autoAttack.box)
    autoAttackHint:SetText(U.L("SETTINGS_AUTO_ATTACK_HINT"))
    table.insert(widgets, autoAttackHint)
  end

  local swingBar = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsSwingBar",
    text = U.L("SETTINGS_SWING_BAR"),
    value = U.ModuleConfig("swingbar", { enabled = true }).enabled,
    onChange = function(value)
      U.ModuleConfig("swingbar", { enabled = true }).enabled = value
      if type(U.ApplySwingBar) == "function" then U.ApplySwingBar() end
    end,
  })
  swingBar.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -220)
  table.insert(widgets, swingBar)

  local swingBarHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if swingBarHint then
    U.AnchorSettingsDescription(swingBarHint, swingBar.box)
    swingBarHint:SetText(U.L("SETTINGS_SWING_BAR_HINT"))
    table.insert(widgets, swingBarHint)
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
  microbar.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -276)
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
  reputation.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -332)
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
  minimapButton.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -364)
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
  zoneLevels.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -396)
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

  -- The chat module (modules/chat.lua) otherwise leaves the native windows
  -- alone, so its one appearance switch lives here beside the other
  -- single-setting toggles rather than on a chat tab of its own.
  local chatShadow = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsChatTextShadow",
    text = U.L("SETTINGS_CHAT_SHADOW"),
    value = U.ModuleConfig("chat", { noTextShadow = false }).noTextShadow,
    onChange = function(value)
      U.ModuleConfig("chat", { noTextShadow = false }).noTextShadow = value
      if type(U.ApplyChatTextShadow) == "function" then
        if U.ApplyChatTextShadow() then
          U.ShowConfirm({
            owner = "settings.chat-shadow-reload",
            centered = true,
            text = U.L("SETTINGS_CHAT_SHADOW"),
            detail = U.L("SETTINGS_CHAT_SHADOW_RELOAD"),
            acceptText = U.L("COMMON_OK_SHORT"),
            cancelText = U.L("COMMON_CLOSE"),
          })
        end
      end
    end,
  })
  chatShadow.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -452)
  table.insert(widgets, chatShadow)

  local chatShadowHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if chatShadowHint then
    U.AnchorSettingsDescription(chatShadowHint, chatShadow.box)
    chatShadowHint:SetText(U.L("SETTINGS_CHAT_SHADOW_HINT"))
    table.insert(widgets, chatShadowHint)
  end

  local tooltipFadeHold
  local tooltipConfig = U.ModuleConfig("tooltip", {
    followCursor = false,
    fadeHold = 0.25,
  })
  local tooltipCursor = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsTooltipCursor",
    text = U.L("SETTINGS_TOOLTIP_CURSOR"),
    value = tooltipConfig.followCursor,
    onChange = function(value)
      tooltipConfig.followCursor = value
      SetShown(tooltipFadeHold, value)
      if type(U.ApplyTooltipPosition) == "function" then U.ApplyTooltipPosition() end
    end,
  })
  tooltipCursor.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -508)
  table.insert(widgets, tooltipCursor)

  local tooltipCursorHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if tooltipCursorHint then
    U.AnchorSettingsDescription(tooltipCursorHint, tooltipCursor.box)
    tooltipCursorHint:SetText(U.L("SETTINGS_TOOLTIP_CURSOR_HINT"))
    table.insert(widgets, tooltipCursorHint)
  end

  tooltipFadeHold = U.CreateSlider(parent, {
    name = "UnrealUISettingsTooltipFadeHold",
    text = U.L("SETTINGS_TOOLTIP_FADE_HOLD"),
    width = 220,
    min = 0.25,
    max = 1,
    step = 0.05,
    value = tooltipConfig.fadeHold,
    onChange = function(value)
      tooltipConfig.fadeHold = value
    end,
  })
  tooltipFadeHold.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -572)
  table.insert(widgets, tooltipFadeHold)
  SetShown(tooltipFadeHold, tooltipConfig.followCursor)

  local function Refresh()
    themes.SetValue(U.GetThemeStyle(), false)
    autoAttack.SetValue(U.ModuleConfig("autoattack", { enabled = false }).enabled)
    swingBar.SetValue(U.ModuleConfig("swingbar", { enabled = true }).enabled)
    microbar.SetValue(U.ModuleConfig("microbar", { enabled = true }).enabled)
    reputation.SetValue(U.ModuleConfig("xpbar", { repEnabled = true }).repEnabled)
    minimapButton.SetValue(U.ModuleConfig("minimap", { enabled = true }).enabled)
    zoneLevels.SetValue(U.ModuleConfig("worldmap", { zoneLevels = true }).zoneLevels)
    chatShadow.SetValue(U.ModuleConfig("chat", { noTextShadow = false }).noTextShadow)
    tooltipConfig = U.ModuleConfig("tooltip", {
      followCursor = false,
      fadeHold = 0.25,
    })
    tooltipCursor.SetValue(tooltipConfig.followCursor)
    tooltipFadeHold.SetValue(tooltipConfig.fadeHold)
    SetShown(tooltipFadeHold, tooltipConfig.followCursor)
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Classic WoW module mixing
--
-- Registered only for a loaded Classic session. Each checkbox selects the
-- owning module's complete Modern WoW drawing path; the rest of the interface
-- remains on native Classic chrome. Like a theme switch, changes apply after
-- reload so a window is never left half native and half rebuilt.
-- ---------------------------------------------------------------------------
local function BuildClassicModulesPage(parent)
  local widgets = {}
  local controls = {}
  local pageWidth = PANEL_WIDTH - SIDEBAR_WIDTH - 36
  local columnWidth = math.floor(pageWidth / 2)

  local header = U.CreateSectionHeader(parent, {
    text = U.L("CLASSIC_MODULES_PAGE"),
    width = pageWidth,
    y = -4,
  })
  table.insert(widgets, header)

  local intro = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = pageWidth,
  })
  if intro then
    U.AnchorSettingsDescription(intro, header.title)
    intro:SetText(U.L("CLASSIC_MODULES_INTRO"))
    table.insert(widgets, intro)
  end

  local modules = U.GetClassicModernModules()
  local lastRowAnchor
  local firstBox
  local i
  for i = 1, table.getn(modules) do
    local entry = modules[i]
    local row = math.floor((i - 1) / 2)
    local column = (i - 1) - row * 2
    local control = U.CreateCheckbox(parent, {
      name = "UnrealUIClassicModule" .. entry.id,
      text = U.L(entry.labelKey),
      textWidth = columnWidth - 20,
      value = U.GetClassicModernModule(entry.id),
      onChange = function(value)
        if U.SetClassicModernModule(entry.id, value) then
          U.ShowConfirm({
            owner = "settings.modern-wow-modules-reload",
            centered = true,
            text = U.L("CLASSIC_MODULES_PAGE"),
            detail = U.L("CLASSIC_MODULES_RELOAD"),
            acceptText = U.L("COMMON_OK_SHORT"),
            cancelText = U.L("COMMON_CLOSE"),
          })
        end
      end,
    })
    -- The grid hangs off the intro text rather than a page offset, so the
    -- first row sits directly below it whatever height the text wraps to.
    if i == 1 then
      if intro then
        control.SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -5)
      else
        control.SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -5)
      end
      firstBox = control.box
    else
      control.SetPoint("TOPLEFT", firstBox, "TOPLEFT",
                       column * columnWidth, -row * 22)
    end
    if column == 0 then lastRowAnchor = control.box end
    table.insert(controls, { control = control, id = entry.id })
    table.insert(widgets, control)
  end

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = pageWidth,
  })
  if hint and lastRowAnchor then
    U.AnchorSettingsDescription(hint, lastRowAnchor)
    hint:SetText(U.L("CLASSIC_MODULES_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    local n
    for n = 1, table.getn(controls) do
      controls[n].control.SetValue(U.GetClassicModernModule(controls[n].id))
    end
  end

  return widgets, Refresh
end

function S:OnInit()
  U.RegisterSettingsTab("general", U.L("SETTINGS_PAGE_GENERAL"), BuildGeneralPage)
  local profilesAfter = "general"
  if U.GetActiveThemeStyle() == "classic-wow" then
    U.RegisterSettingsTab("classic-modules", U.L("CLASSIC_MODULES_PAGE"),
                          BuildClassicModulesPage, { after = "general" })
    profilesAfter = "classic-modules"
  end
  U.RegisterSettingsTab("profiles", U.L("SETTINGS_PAGE_PROFILES"), BuildProfilePage,
                        { after = profilesAfter })
end

function S:OnEnable()
  -- Built lazily on first open; nothing to do here beyond making sure the
  -- module exists in the registry for /uui check.
end
