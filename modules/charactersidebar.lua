-- unrealUI :: modules/charactersidebar.lua
--
-- The paper doll's three sidebar tabs over the stats pane under the
-- `character` Modern WoW surface (user request, 2026-09-28): Retail's
-- PaperDollSidebarTabs -- Character Stats, Titles, Equipment Manager -- from
-- Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml:393-539 and
-- PAPERDOLL_SIDEBARS / PaperDollFrame_UpdateSidebarTabs / _SetSidebar in
-- PaperDollFrame.lua (RetailFrameXML 12.1.0.69933). Geometry and art live in
-- M.modernWow.characterSidebar.
--
-- Entry point only: modules/characterstatspanel.lua builds the strip on its
-- panel (U.BuildCharacterSidebar) and tells it when the housing expands, so
-- the tabs show and hide with the stats pane.
--
-- What each tab backs on this client:
--   * Character Stats: the stats list. Always available.
--   * Titles: Retail's TitleManagerPane, drawn in the stats pane's own list
--     (U.CharacterStatsPanel.SetMode). Available only when the client exposes
--     GetNumTitles, IsTitleKnown, GetTitleName, GetCurrentTitle and
--     SetCurrentTitle -- none is recorded in query_compat.py, so every call is
--     guarded -- and at least one title is known, as Retail's IsActive
--     requires. The client's own PlayerTitleDropDown, which UnrealUI had moved
--     into this band (mw.PlaceCharacterTitleDropDown), is hidden while the
--     tabs show: Retail has no dropdown, the Titles tab is its selector.
--   * Equipment Manager: Retail's PaperDollEquipmentManagerPane, rebuilt by
--     modules/characterequipment.lua on UnrealUI's own set store
--     (modules/equipmentsets.lua), since this client has no equipment-set
--     API. Available whenever those modules loaded, as Retail's IsActive
--     (C_EquipmentSet.CanUseEquipmentSets) is for a player.
--
-- A disabled tab is never Button:Disable()d: its hover must still name it and
-- give the reason (Retail's motionScriptsWhileDisabled), which this client's
-- disabled buttons are not recorded to do. The state is kept here instead.
--
-- One top-level table (rules/unreal-ui.md, Lua local budget).

local U = UnrealUI
local M = U.media

local SB = {
  strip = nil,
  tabs = {},
  selected = 1,
  expanded = false,
  api = nil,
  dropHooked = false,
  dropHidden = false,
  flat = false,
}
U.CharacterSidebar = SB

-- Retail's PAPERDOLL_SIDEBARS, reduced to what this client can back. `mode`
-- is the stats pane's list mode; `icon` names a cell of the sheet (tab 1
-- draws the portrait).
SB.sidebars = {
  { name = "CHARSIDEBAR_STATS", mode = "stats" },
  { name = "CHARSIDEBAR_TITLES", mode = "titles", icon = "titlesIcon",
    disabled = "CHARSIDEBAR_NO_TITLES" },
  { name = "CHARSIDEBAR_EQUIPMENT", mode = "equipment", icon = "equipmentIcon",
    disabled = "CHARSIDEBAR_NO_EQUIPMENT" },
}

function SB.Token()
  if SB.flat then return M.characterModern.sidebar end
  return M.modernWow.characterSidebar
end

function SB.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

function SB.Cell(texture, coords)
  pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
end

-- ---------------------------------------------------------------------------
-- Titles
-- ---------------------------------------------------------------------------
-- The five title functions, or nil when any is missing. Read once: globals
-- do not change after login.
function SB.TitleApi()
  if SB.api == nil then
    local api = {
      num = U.G("GetNumTitles"), known = U.G("IsTitleKnown"),
      name = U.G("GetTitleName"), current = U.G("GetCurrentTitle"),
      set = U.G("SetCurrentTitle"),
    }
    SB.api = api
    local key, fn
    for key, fn in pairs(api) do
      if type(fn) ~= "function" then SB.api = false end
    end
  end
  return SB.api or nil
end

function SB.IsKnown(api, id)
  local ok, known = pcall(api.known, id)
  return ok and known and known ~= 0 and true or false
end

-- Retail's GetKnownTitles and PaperDollTitlesPane_Update: every known title,
-- trimmed and sorted by name, and the current one (-1 for none).
function SB.KnownTitles()
  local api = SB.TitleApi()
  local list = {}
  if not api then return list, -1 end
  local ok, count = pcall(api.num)
  count = ok and tonumber(count) or 0
  local i
  for i = 1, count do
    if SB.IsKnown(api, i) then
      local okName, name, playerTitle = pcall(api.name, i)
      if okName and type(name) == "string" and playerTitle ~= false then
        name = (string.gsub(name, "^%s*(.-)%s*$", "%1"))
        if name ~= "" then table.insert(list, { id = i, name = name }) end
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  local okCurrent, current = pcall(api.current)
  current = okCurrent and tonumber(current) or -1
  if current > 0 and current <= count and SB.IsKnown(api, current) then
    return list, current
  end
  return list, -1
end

-- The Titles pane's entries for U.CharacterStatsPanel: "No Title" first, as
-- Retail keeps it, then the known titles; even rows striped.
function SB.TitleEntries()
  local list, selected = SB.KnownTitles()
  local entries = {
    { kind = "title", id = -1, name = U.L("CHARSIDEBAR_TITLE_NONE"),
      selected = selected == -1, stripe = false },
  }
  local i
  for i = 1, table.getn(list) do
    local index = i + 1
    table.insert(entries, { kind = "title", id = list[i].id, name = list[i].name,
                            selected = selected == list[i].id,
                            stripe = math.mod(index, 2) == 0 })
  end
  return entries
end

-- PlayerTitleButton_OnClick.
function SB.SetTitle(id)
  local api = SB.TitleApi()
  if not api or not id then return end
  pcall(api.set, id)
  if U.CharacterStatsPanel then U.CharacterStatsPanel.Refresh() end
end

-- ---------------------------------------------------------------------------
-- The native title dropdown
-- ---------------------------------------------------------------------------
-- Hidden while the tabs show, never unregistered; shown again only if this
-- module hid it. The OnShow hook covers the client re-showing it.
function SB.HideDropDown()
  local name = SB.flat and SB.Token().titleDropDownName or
               M.modernWow.titleDropDown.name
  local drop = U.G(name)
  if not drop then return end
  if not SB.dropHooked then
    SB.dropHooked = true
    U.PostHookScript(drop, "OnShow", function()
      if SB.expanded then SB.HideDropDown() end
    end)
  end
  local ok, shown = pcall(drop.IsShown, drop)
  if ok and shown then
    SB.dropHidden = true
    pcall(drop.Hide, drop)
  end
end

function SB.RestoreDropDown()
  if not SB.dropHidden then return end
  SB.dropHidden = false
  local name = SB.flat and SB.Token().titleDropDownName or
               M.modernWow.titleDropDown.name
  local drop = U.G(name)
  if drop then pcall(drop.Show, drop) end
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
function SB.IsActive(index)
  if index == 1 then return true end
  if index == 2 then
    local list = SB.KnownTitles()
    return table.getn(list) > 0
  end
  if index == 3 then
    return U.EquipmentSets ~= nil and U.CharacterEquipmentPane ~= nil
  end
  return false
end

-- Tab 1's icon: the player's portrait at Tab1's OnLoad crop, or the class
-- circle on a client without SetPortraitTexture. The portrait is a live
-- snapshot that can come back black while the model loads
-- (modules/unitframes.lua), so it is repainted on every expand and a tick
-- later.
function SB.PaintPortrait()
  if SB.flat then return end
  local tab = SB.tabs[1]
  if not tab or not tab.icon then return end
  local set = U.G("SetPortraitTexture")
  if type(set) == "function" and pcall(set, tab.icon, "player") then
    SB.Cell(tab.icon, SB.Token().portrait.texCoord)
    return
  end
  local ok, _, class = pcall(UnitClass, "player")
  local cell = ok and class and M.modernWow.classCell[class]
  if not cell then return end
  pcall(tab.icon.SetTexture, tab.icon, M.modernWow.texture.classPortraits)
  SB.Cell(tab.icon, cell)
end

-- PaperDollFrame_UpdateSidebarTabs, with OnEnable / OnDisable folded in.
function SB.Paint(index)
  local tab = SB.tabs[index]
  if not tab then return end
  local t = SB.Token()
  local selected = SB.selected == index
  local enabled = selected or SB.IsActive(index)
  tab.enabled = enabled
  if SB.flat then
    -- The shared tab group has no disabled state, so a disabled tab keeps its
    -- neutral chrome and takes a dim label that hover does not lift; never a
    -- frame alpha (rules/unreal-ui-design.md).
    local face = tab.uuiTabFace
    if face then
      face.inactiveText = enabled and M.tab.inactiveTextColor or t.disabledTextColor
      face.hoverText = enabled and M.tab.hoverTextColor or t.disabledTextColor
    end
    if type(tab.SetActive) == "function" then tab.SetActive(selected) end
    return
  end
  SB.Cell(tab.bg, selected and t.tabBg.selectedTexCoord or t.tabBg.texCoord)
  SB.SetShown(tab.hider, not selected)
  SB.SetShown(tab.highlight, (not selected) and enabled)
  local alpha = enabled and 1 or t.disabledAlpha
  local regions = { tab.bg, tab.icon, tab.hider, tab.highlight }
  local i
  for i = 1, table.getn(regions) do
    if regions[i] then pcall(regions[i].SetAlpha, regions[i], alpha) end
  end
  if tab.icon then
    pcall(tab.icon.SetDesaturated, tab.icon, (not enabled) and 1 or nil)
  end
end

function SB.PaintAll()
  local i
  for i = 1, table.getn(SB.tabs) do SB.Paint(i) end
end

function SB.ApplyMode()
  local panel = U.CharacterStatsPanel
  if panel and panel.SetMode then
    panel.SetMode(SB.sidebars[SB.selected].mode or "stats")
  end
end

-- PaperDollFrame_SetSidebar.
function SB.Select(index)
  local tab = SB.tabs[index]
  if not tab or not tab.enabled or SB.selected == index then return end
  SB.selected = index
  SB.ApplyMode()
  SB.PaintAll()
end

-- PaperDollFrame_SidebarTab_OnEnter: the tab's name, and a disabled tab's
-- reason as an error line.
function SB.Tooltip(index)
  local tab = SB.tabs[index]
  if not tab or type(U.ShowInfoTooltip) ~= "function" then return end
  local t = SB.Token()
  local sidebar = SB.sidebars[index]
  local lines = { { U.L(sidebar.name), t.nameColor } }
  if not tab.enabled and sidebar.disabled then
    table.insert(lines, { U.L(sidebar.disabled), t.errorColor })
  end
  U.ShowInfoTooltip(tab, lines)
end

function SB.HideTooltip()
  if type(U.HideInfoTooltip) == "function" then U.HideInfoTooltip() end
end

-- `scale` shrinks the piece's height: the tab's own art is drawn at the
-- square tab's height over Retail's (M.modernWow.characterSidebar.tab).
function SB.Piece(parent, layer, spec, scale)
  local texture = parent:CreateTexture(nil, layer)
  texture:SetTexture(SB.Token().texture)
  texture:SetWidth(spec.width)
  texture:SetHeight(spec.height * (scale or 1))
  if spec.texCoord then SB.Cell(texture, spec.texCoord) end
  return texture
end

-- PaperDollSidebarTabTemplate, square: every height and vertical offset of
-- its art at `k`.
function SB.BuildTab(index)
  local t = SB.Token()
  if SB.flat then
    -- An addon-owned text tab with its own label (prof.CreateTab's pattern);
    -- U.StyleStockTabGroup draws and sizes it in SB.Build.
    local tab = CreateFrame("Button", nil, SB.strip)
    local label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tab.uuiTabLabel = label
    tab.GetFontString = function() return label end
    pcall(label.SetText, label, U.L(SB.sidebars[index].name))
    pcall(label.SetPoint, label, "CENTER", tab, "CENTER", 0, 0)
    tab:SetHeight(t.height)
    pcall(tab.SetFrameLevel, tab, (tonumber(SB.strip:GetFrameLevel()) or 0) + 1)
    pcall(tab.RegisterForClicks, tab, "LeftButtonUp")
    tab:SetScript("OnClick", function() SB.Select(index) end)
    SB.tabs[index] = tab
    return tab
  end
  local k = t.tab.height / t.tab.authoredHeight
  local tab = CreateFrame("Button", nil, SB.strip)
  tab:SetWidth(t.tab.width)
  tab:SetHeight(t.tab.height)
  pcall(tab.SetFrameLevel, tab, (tonumber(SB.strip:GetFrameLevel()) or 0) + 1)

  tab.bg = SB.Piece(tab, "BACKGROUND", t.tabBg, k)
  tab.bg:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", t.tabBg.x, t.tabBg.y * k)

  local sidebar = SB.sidebars[index]
  local icon = tab:CreateTexture(nil, "ARTWORK")
  if sidebar.icon then
    icon:SetTexture(t.texture)
    icon:SetWidth(t.icon.width)
    icon:SetHeight(t.icon.height * k)
    icon:SetPoint("BOTTOM", tab, "BOTTOM", t.icon.x, t.icon.y * k)
    SB.Cell(icon, t[sidebar.icon])
  else
    icon:SetWidth(t.portrait.width)
    icon:SetHeight(t.portrait.height * k)
    icon:SetPoint("BOTTOM", tab, "BOTTOM", t.portrait.x, t.portrait.y * k)
  end
  tab.icon = icon

  tab.hider = SB.Piece(tab, "OVERLAY", t.hider, k)
  tab.hider:SetPoint("BOTTOM", tab, "BOTTOM", 0, 0)

  -- HIGHLIGHT: the client shows it only under the pointer; SB.Paint hides it
  -- for the shown tab and a disabled one, as Retail does.
  tab.highlight = SB.Piece(tab, "HIGHLIGHT", t.highlight, k)
  tab.highlight:SetPoint("TOPLEFT", tab, "TOPLEFT", t.highlight.x,
                         t.highlight.y * k)

  tab:SetScript("OnClick", function() SB.Select(index) end)
  tab:SetScript("OnEnter", function() SB.Tooltip(index) end)
  tab:SetScript("OnLeave", SB.HideTooltip)
  SB.tabs[index] = tab
  return tab
end

-- PaperDollSidebarTabs, centred over InsetRight. `left`, `right`: InsetRight's
-- edges and `y` its top, from the panel's top-left, y downwards.
function SB.Build(panel, left, right, y)
  local t = SB.Token()
  SB.flat = type(U.GetActiveThemeStyle) == "function" and
            U.GetActiveThemeStyle() == "modern"
  t = SB.Token()
  local strip = CreateFrame("Frame", nil, panel)
  if SB.flat then
    local width = right - left - t.inset * 2
    strip:SetWidth(width)
    strip:SetHeight(t.height)
    strip:SetPoint("TOPLEFT", panel, "TOPLEFT", left + t.inset,
                   -(y + t.inset))
    pcall(strip.SetFrameLevel, strip,
          (tonumber(panel:GetFrameLevel()) or 0) + 3)
    SB.strip = strip
    local i
    for i = 1, 3 do SB.BuildTab(i) end
    U.StyleStockTabGroup(SB.tabs, 1, { height = t.height })
    -- The group sets OnEnter/OnLeave and marks a clicked tab active; the
    -- tooltip and SB.selected (which refuses a disabled tab) are hooked
    -- after it, so they have the last word.
    for i = 1, 3 do
      local index = i
      local tab = SB.tabs[i]
      U.PostHookScript(tab, "OnClick", SB.PaintAll)
      U.PostHookScript(tab, "OnEnter", function() SB.Tooltip(index) end)
      U.PostHookScript(tab, "OnLeave", SB.HideTooltip)
    end
    -- Sized to their labels, padding reduced only as far as the strip needs.
    U.FitStockTabStrip(SB.tabs, strip, {
      gap = t.gap, left = 0, right = 0, padding = M.tab.padding,
      anchor = { frame = strip, point = "LEFT", relativePoint = "LEFT" },
    })
    U.ChainStockTabs(SB.tabs, t.gap)
    SB.PaintAll()
    return
  end
  strip:SetWidth(t.strip.width)
  strip:SetHeight(t.strip.height)
  strip:SetPoint("BOTTOM", panel, "TOPLEFT", (left + right) / 2,
                 -y + t.strip.y)
  pcall(strip.SetFrameLevel, strip, (tonumber(panel:GetFrameLevel()) or 0) + 3)
  SB.strip = strip

  local left = SB.Piece(strip, "ARTWORK", t.decorLeft)
  left:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
  local right = SB.Piece(strip, "ARTWORK", t.decorRight)
  right:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)

  local third = SB.BuildTab(3)
  third:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -t.tab.right, 0)
  local second = SB.BuildTab(2)
  second:SetPoint("RIGHT", third, "LEFT", -t.tab.gap, 0)
  local first = SB.BuildTab(1)
  first:SetPoint("RIGHT", second, "LEFT", -t.tab.gap, 0)
  SB.PaintAll()
end

-- Driven by U.CharacterStatsPanel with the housing: the paper doll opened in
-- the expanded window (true) or left it (false).
function SB.SetExpanded(expanded)
  if not SB.strip then return end
  SB.expanded = expanded and true or false
  if not SB.expanded then
    SB.HideTooltip()
    SB.RestoreDropDown()
    return
  end
  SB.HideDropDown()
  if not SB.IsActive(SB.selected) then SB.selected = 1 end
  SB.ApplyMode()
  SB.PaintAll()
  SB.PaintPortrait()
  U.DeferOnce("charactersidebar.portrait", SB.PaintPortrait)
end

function U.BuildCharacterSidebar(panel, left, right, y)
  if SB.strip then return true end
  if not panel then return false end
  local ok, err = pcall(SB.Build, panel, left, right, y)
  if not ok then
    U.Error("character sidebar: " .. tostring(err))
    if SB.strip then pcall(SB.strip.Hide, SB.strip) end
    SB.strip = nil
    return false
  end
  return true
end
