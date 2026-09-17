-- unrealUI :: modules/spellbookclassicprof.lua
--
-- The classic-wow native Spellbook's Spellbook / Professions tabs and the
-- host for the Professions page (user request, 2026-09-17).
--
-- modules/spellbookprofessions.lua owns the page -- rows, bars, unlearn,
-- skill scan and the SpellBook_GetSpellID slot mapping -- and draws it
-- exactly as under modern-wow. This file only supplies what the modern-wow
-- book supplies there (prof.host): where page texels land in the client's own
-- 384x512 window, the Dragonflight page art over the native parchment, the
-- placement of the native SpellButton1-12 in the page's rows, and the two
-- owned tabs, built from the client's own tab template so they match the
-- native Pet tab.
--
-- Everything stays on the client's widgets. Spell buttons are only moved and
-- resized while the page is open, and their native anchors are put back from
-- names and numbers captured the first time, never from retained native
-- objects (rules/unreal-ui.md, native widget ownership). Page art is drawn as
-- SpellBookFrame's own regions, beneath every child widget, so it never takes
-- the mouse.
--
-- Built only under classic-wow's native chrome path, from
-- modules/spellbook.lua's OnEnable. The modern-wow book (full theme or
-- Classic's Spellbook selection) keeps its own path.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local cp = {
  THEME = "classic-wow",
  built = false,
  frame = nil,
  placer = nil,
  buttons = {},
  tabs = nil,
  gap = nil,
}

function cp.Token()
  return M.classicWow.spellBookProfessions
end

function cp.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function cp.Number(object, method)
  if not object or not object[method] then return nil end
  local ok, value = pcall(object[method], object)
  return ok and tonumber(value) or nil
end

function cp.SpellCount()
  return tonumber(U.G("SPELLS_PER_PAGE")) or 12
end

-- ---------------------------------------------------------------------------
-- Page geometry and art
-- ---------------------------------------------------------------------------
function cp.Scale()
  local t = cp.Token()
  local canvas = t.canvas
  return t.page.width / (canvas.width + canvas.edgeWidth),
         t.page.height / canvas.height
end

function cp.PagePoint(x, y)
  if not cp.built then return nil end
  local page = cp.Token().page
  local kx, ky = cp.Scale()
  return page.left + x * kx, page.top + y * ky
end

function cp.PageScale()
  if not cp.built then return nil end
  return cp.Scale()
end

-- OVERLAY on the window itself: above the client's page quadrants, below
-- every child (spell buttons, tabs, the page's own rows).
function cp.PageTexture(u2)
  local ok, texture = pcall(cp.frame.CreateTexture, cp.frame, nil, "OVERLAY")
  if not ok or not texture then return nil end
  local canvas = cp.Token().canvas
  pcall(texture.SetTexCoord, texture, 0, u2, 0, canvas.height / canvas.canvas)
  pcall(texture.Hide, texture)
  return texture
end

function cp.SetPageArt(left, right)
  if not cp.built then return end
  local t = cp.Token()
  local canvas, page = t.canvas, t.page
  local kx = cp.Scale()

  if not cp.page1 then
    cp.page1 = cp.PageTexture(1)
    cp.page2 = cp.PageTexture(canvas.edgeWidth / canvas.edgeCanvas)
    local width1 = canvas.width * kx
    pcall(function()
      cp.page1:SetWidth(width1)
      cp.page1:SetHeight(page.height)
      cp.page1:SetPoint("TOPLEFT", cp.frame, "TOPLEFT", page.left, -page.top)
      cp.page2:SetWidth(canvas.edgeWidth * kx)
      cp.page2:SetHeight(page.height)
      cp.page2:SetPoint("TOPLEFT", cp.frame, "TOPLEFT", page.left + width1,
                        -page.top)
    end)
  end

  local pages = { { cp.page1, left }, { cp.page2, right } }
  local i
  for i = 1, 2 do
    local region, path = pages[i][1], pages[i][2]
    if region then
      if path then
        pcall(region.SetTexture, region, path)
        pcall(region.Show, region)
      else
        pcall(region.Hide, region)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Spell buttons
-- ---------------------------------------------------------------------------

-- An object's anchors as names and numbers. GetPoint's Y has the sign
-- SetPoint was given (knowledge.json / frames.getpoint_y_same_sign_as_setpoint),
-- so a captured point is re-applied as read. An anchor whose relative frame
-- has no name cannot be restored and is left out.
function cp.CapturePoints(object)
  local points = {}
  local count = cp.Number(object, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y =
      pcall(object.GetPoint, object, i)
    if ok and point then
      local relName
      if relative and relative.GetName then
        local nameOk, value = pcall(relative.GetName, relative)
        if nameOk then relName = value end
      end
      if relName then
        table.insert(points, { point, relName, relativePoint,
                               tonumber(x) or 0, tonumber(y) or 0 })
      end
    end
  end
  return points
end

function cp.RestorePoints(object, points)
  if not object or not points or not points[1] then return end
  pcall(function()
    object:ClearAllPoints()
    local i
    for i = 1, table.getn(points) do
      local p = points[i]
      local relative = U.G(p[2])
      if relative then object:SetPoint(p[1], relative, p[3], p[4], p[5]) end
    end
  end)
end

function cp.Capture(index)
  local base = "SpellButton" .. index
  local button = U.G(base)
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  return {
    points = cp.CapturePoints(button),
    width = cp.Number(button, "GetWidth"),
    height = cp.Number(button, "GetHeight"),
    namePoints = cp.CapturePoints(name),
    nameWidth = cp.Number(name, "GetWidth"),
    subPoints = cp.CapturePoints(sub),
    subWidth = cp.Number(sub, "GetWidth"),
  }
end

-- The slot's own backing and quick-slot face, which the page does not draw
-- (placed.plainSlot: the icon's edge is the border, as under modern-wow).
-- Hidden and shown rather than cleared, so leaving the page restores them.
function cp.SetNativeSlot(index, shown)
  local base = "SpellButton" .. index
  local backing = U.G(base .. "Background")
  if backing then
    pcall(shown and backing.Show or backing.Hide, backing)
  end
  local button = U.G(base)
  if button and button.GetNormalTexture then
    local ok, normal = pcall(button.GetNormalTexture, button)
    if ok and normal then pcall(normal.SetAlpha, normal, shown and 1 or 0) end
  end
end

function cp.Plate(button, state, plate)
  if not state.plate then
    local ok, texture = pcall(button.CreateTexture, button, nil, "BACKGROUND")
    if not ok or not texture then return nil end
    pcall(texture.SetTexture, texture, plate.path)
    pcall(texture.SetTexCoord, texture, plate.u1, plate.u2, plate.v1, plate.v2)
    pcall(texture.Hide, texture)
    state.plate = texture
  end
  return state.plate
end

function cp.Place(index, placed)
  local base = "SpellButton" .. index
  local button = U.G(base)
  if not button then return end
  local state = cp.buttons[index]
  if not state then
    state = cp.Capture(index)
    cp.buttons[index] = state
  end

  local text = cp.Token().text
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  pcall(function()
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", cp.frame, "TOPLEFT", placed.x, -placed.y)
    button:SetWidth(placed.size)
    button:SetHeight(placed.size)
  end)
  if name then
    pcall(function()
      name:ClearAllPoints()
      name:SetPoint("TOPLEFT", button, "TOPRIGHT", text.gap, text.nameY)
      name:SetWidth(placed.textWidth)
    end)
  end
  if sub and name then
    pcall(function()
      sub:ClearAllPoints()
      sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, text.subY)
      sub:SetWidth(placed.textWidth)
    end)
  end

  local frame = placed.nameFrame
  local plate = frame and cp.Plate(button, state, frame)
  if plate then
    pcall(function()
      plate:ClearAllPoints()
      plate:SetWidth(frame.width)
      plate:SetHeight(frame.height)
      plate:SetPoint("LEFT", button, "RIGHT", frame.x, 0)
      plate:SetAlpha(frame.alpha)
    end)
  end

  state.placed = placed
  cp.Sync(index)
end

function cp.Restore(index)
  local state = cp.buttons[index]
  if not state or not state.placed then return end
  state.placed = nil

  local base = "SpellButton" .. index
  local button = U.G(base)
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  cp.RestorePoints(button, state.points)
  if button and state.width and state.height then
    pcall(button.SetWidth, button, state.width)
    pcall(button.SetHeight, button, state.height)
  end
  cp.RestorePoints(name, state.namePoints)
  if name and state.nameWidth then pcall(name.SetWidth, name, state.nameWidth) end
  cp.RestorePoints(sub, state.subPoints)
  if sub and state.subWidth then pcall(sub.SetWidth, sub, state.subWidth) end

  if state.plate then pcall(state.plate.Hide, state.plate) end
  cp.SetNativeSlot(index, true)
end

-- Re-asserted after every client repaint of a placed button: the rank colour,
-- the hidden slot art, and the plate only behind a filled slot.
function cp.Sync(index)
  local state = cp.buttons[index]
  local placed = state and state.placed
  if not placed then return end
  local base = "SpellButton" .. index

  if placed.plainSlot then cp.SetNativeSlot(index, false) end
  local sub = U.G(base .. "SubSpellName")
  if sub and placed.subColor then
    pcall(sub.SetTextColor, sub, M.Unpack(placed.subColor))
  end
  if state.plate then
    local filled = cp.Shown(U.G(base .. "IconTexture"))
    pcall(filled and state.plate.Show or state.plate.Hide, state.plate)
  end
end

function cp.Redress()
  if not cp.built then return end
  local i
  for i = 1, cp.SpellCount() do
    local placed = cp.placer and cp.placer(i)
    if placed then cp.Place(i, placed) else cp.Restore(i) end
  end
end

function cp.OnSpellButtonUpdate()
  local button = U.G("this")
  if not button then return end
  local i
  for i = 1, cp.SpellCount() do
    if U.G("SpellButton" .. i) == button then
      cp.Sync(i)
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

-- An owned tab from the client's own tab template, so it wears the same art
-- and selected state as the native Pet tab. Nil when the template did not
-- apply (its named Left piece is missing), so the window keeps its own tabs.
function cp.CreateTab(frame, name, text, onClick)
  local template = cp.Token().tab.template
  local ok, tab = pcall(CreateFrame, "Button", name, frame, template)
  if not ok or not tab then return nil end
  if not U.G(name .. "Left") then
    pcall(tab.Hide, tab)
    return nil
  end

  pcall(tab.SetText, tab, text)
  local resize = U.G("PanelTemplates_TabResize")
  if type(resize) == "function" then pcall(resize, 0, tab) end
  pcall(tab.RegisterForClicks, tab, "LeftButtonUp")
  tab:SetScript("OnClick", onClick)
  tab.SetActive = function(active) cp.SetTabActive(tab, active) end
  return tab
end

function cp.SetTabActive(tab, active)
  if not tab then return end
  local fn = U.G(active and "PanelTemplates_SelectTab" or
                 "PanelTemplates_DeselectTab")
  if type(fn) == "function" and pcall(fn, tab) then return end
  pcall(active and tab.Disable or tab.Enable, tab)
end

-- The native first tab's anchor, read once as numbers against the window.
function cp.SpellTabAnchor()
  local fallback = cp.Token().tab.fallback
  local native = U.G("SpellBookFrameTabButton1")
  if native and native.GetPoint then
    local ok, point, relative, relativePoint, x, y = pcall(native.GetPoint, native, 1)
    -- Compared by name: a returned widget need not be the same Lua wrapper.
    local relName
    if ok and relative and relative.GetName then
      local nameOk, value = pcall(relative.GetName, relative)
      if nameOk then relName = value end
    end
    if ok and point and relName == "SpellBookFrame" then
      return point, relativePoint, tonumber(x) or 0, tonumber(y) or 0
    end
  end
  return fallback.point, fallback.relativePoint, fallback.x, fallback.y
end

-- The native Pet tab's offset from the first tab, read once.
function cp.TabGap()
  local native = U.G("SpellBookFrameTabButton2")
  if native and native.GetPoint then
    local ok, point, _, relativePoint, x = pcall(native.GetPoint, native, 1)
    if ok and point == "LEFT" and relativePoint == "RIGHT" and tonumber(x) then
      return tonumber(x)
    end
  end
  return cp.Token().tab.gap
end

function cp.ChainTabs()
  if not cp.tabs then return end
  U.ChainStockTabs({ cp.tabs.spellbook, cp.tabs.professions,
                     U.G("SpellBookFrameTabButton2") }, cp.gap)
  -- Spellbook and Professions sit `extraGap` further apart than the native
  -- overlap; the Pet tab follows Professions and keeps the native offset.
  pcall(function()
    cp.tabs.professions:ClearAllPoints()
    cp.tabs.professions:SetPoint("LEFT", cp.tabs.spellbook, "RIGHT",
                                 cp.gap + cp.Token().tab.extraGap, 0)
  end)
end

-- Selected state follows the page and the book shown; the Pet tab is the
-- client's own and keeps its native state.
function cp.SyncTabs()
  if not cp.tabs then return end
  local onPage = type(U.SpellBookProfessionsShown) == "function" and
                 U.SpellBookProfessionsShown() and true or false
  local spell = U.G("BOOKTYPE_SPELL")
  if type(spell) ~= "string" or spell == "" then spell = "spell" end
  local onSpells = not onPage and cp.frame.bookType == spell

  cp.SetTabActive(cp.tabs.professions, onPage)
  cp.SetTabActive(cp.tabs.spellbook, onSpells)
  cp.ChainTabs()
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------
function cp.Host()
  return {
    Active = function() return cp.built end,
    PagePoint = cp.PagePoint,
    PageScale = cp.PageScale,
    SetPageArt = cp.SetPageArt,
    Redress = cp.Redress,
    ShowClassPortrait = function() return nil end,
    SetButtonPlacer = function(placer) cp.placer = placer end,
    CreateTab = cp.CreateTab,
    tabGap = cp.gap,
  }
end

-- Builds once, under classic-wow only. Called from modules/spellbook.lua's
-- OnEnable under pcall, before that module installs its book-tab hooks (the
-- same order the modern-wow book uses).
function U.BuildClassicSpellBookProfessions()
  if cp.built then return true end
  if U.GetActiveThemeStyle() ~= cp.THEME then return false end
  if type(U.ClassicSpellBookExtraTabs) ~= "function" then return false end

  local frame = U.G("SpellBookFrame")
  if not frame then error("SpellBookFrame is unavailable") end
  cp.frame = frame
  cp.gap = cp.TabGap()
  local point, relativePoint, x, y = cp.SpellTabAnchor()

  -- Active before the tabs exist: installing hands the page this host.
  cp.built = true
  local tabs = U.ClassicSpellBookExtraTabs(frame, cp.Host())
  if not tabs then
    cp.built = false
    return false
  end
  cp.tabs = tabs

  pcall(function()
    tabs.spellbook:ClearAllPoints()
    tabs.spellbook:SetPoint(point, frame, relativePoint, x, y)
  end)
  cp.SyncTabs()

  U.PostHookScript(tabs.professions, "OnClick", cp.SyncTabs)
  U.PostHookScript(tabs.spellbook, "OnClick", cp.SyncTabs)
  U.PostHookScript(frame, "OnShow", cp.SyncTabs)
  U.PostHookGlobal("SpellBookFrame_Update", cp.SyncTabs)
  U.PostHookGlobal("SpellButton_UpdateButton", cp.OnSpellButtonUpdate)
  return true
end
