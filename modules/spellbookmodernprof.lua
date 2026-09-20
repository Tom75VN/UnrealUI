-- unrealUI :: modules/spellbookmodernprof.lua
--
-- Flat-modern host for the Spellbook's shared Professions page. The page's
-- data and behavior stay in modules/spellbookprofessions.lua; this file owns
-- only modern placement, tab chrome and reversible native-button geometry.

local U = UnrealUI
local M = U.media

local modern = {
  built = false,
  frame = nil,
  panel = nil,
  placer = nil,
  buttons = {},
  tabs = nil,
}

function modern.Token()
  return M.spellBook.professions
end

function modern.Number(object, method)
  if not object or not object[method] then return nil end
  local ok, value = pcall(object[method], object)
  return ok and tonumber(value) or nil
end

function modern.SpellCount()
  return tonumber(U.G("SPELLS_PER_PAGE")) or 12
end

function modern.CapturePoints(object)
  local points = {}
  local count = modern.Number(object, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y =
      pcall(object.GetPoint, object, i)
    if ok and point and relative and relative.GetName then
      local nameOk, name = pcall(relative.GetName, relative)
      if nameOk and name then
        table.insert(points, { point, name, relativePoint,
                               tonumber(x) or 0, tonumber(y) or 0 })
      end
    end
  end
  return points
end

function modern.RestorePoints(object, points)
  if not object or not points or not points[1] then return end
  pcall(function()
    object:ClearAllPoints()
    local i
    for i = 1, table.getn(points) do
      local point = points[i]
      local relative = U.G(point[2])
      if relative then
        object:SetPoint(point[1], relative, point[3], point[4], point[5])
      end
    end
  end)
end

function modern.Capture(index)
  local base = "SpellButton" .. index
  local button = U.G(base)
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  return {
    points = modern.CapturePoints(button),
    width = modern.Number(button, "GetWidth"),
    height = modern.Number(button, "GetHeight"),
    level = modern.Number(button, "GetFrameLevel"),
    namePoints = modern.CapturePoints(name),
    nameWidth = modern.Number(name, "GetWidth"),
    subPoints = modern.CapturePoints(sub),
    subWidth = modern.Number(sub, "GetWidth"),
  }
end

function modern.Place(index, placed)
  local base = "SpellButton" .. index
  local button = U.G(base)
  if not button then return end
  local state = modern.buttons[index]
  if not state then
    state = modern.Capture(index)
    modern.buttons[index] = state
  end

  pcall(function()
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", modern.frame, "TOPLEFT", placed.x, -placed.y)
    button:SetWidth(placed.size)
    button:SetHeight(placed.size)
    button:SetFrameLevel((modern.Number(modern.frame, "GetFrameLevel") or 0) + 12)
  end)
  state.placed = placed
  modern.Sync(index)
end

function modern.Restore(index)
  local state = modern.buttons[index]
  if not state or not state.placed then return end
  state.placed = nil

  local base = "SpellButton" .. index
  local button = U.G(base)
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  modern.RestorePoints(button, state.points)
  modern.RestorePoints(name, state.namePoints)
  modern.RestorePoints(sub, state.subPoints)
  if button and state.width and state.height then
    pcall(button.SetWidth, button, state.width)
    pcall(button.SetHeight, button, state.height)
  end
  if button and state.level then pcall(button.SetFrameLevel, button, state.level) end
  if name and state.nameWidth then pcall(name.SetWidth, name, state.nameWidth) end
  if sub and state.subWidth then pcall(sub.SetWidth, sub, state.subWidth) end
  if name then pcall(name.Show, name) end
  if sub then pcall(sub.Show, sub) end
end

function modern.Sync(index)
  local state = modern.buttons[index]
  local placed = state and state.placed
  if not placed or not placed.iconOnly then return end
  local base = "SpellButton" .. index
  local name = U.G(base .. "SpellName")
  local sub = U.G(base .. "SubSpellName")
  if name then pcall(name.Hide, name) end
  if sub then pcall(sub.Hide, sub) end
end

function modern.Redress()
  if not modern.built then return end
  local i
  for i = 1, modern.SpellCount() do
    local placed = modern.placer and modern.placer(i)
    if placed then modern.Place(i, placed) else modern.Restore(i) end
  end
end

function modern.OnSpellButtonUpdate()
  local button = U.G("this")
  if not button then return end
  local i
  for i = 1, modern.SpellCount() do
    if U.G("SpellButton" .. i) == button then
      modern.Sync(i)
      return
    end
  end
end

function modern.ChainTabs()
  if not modern.tabs then return end
  local list = { modern.tabs.spellbook, modern.tabs.professions }
  local i
  for i = 2, 3 do
    local tab = U.G("SpellBookFrameTabButton" .. i)
    if tab then table.insert(list, tab) end
  end

  pcall(function()
    modern.tabs.spellbook:ClearAllPoints()
    modern.tabs.spellbook:SetPoint("TOPLEFT", modern.panel, "BOTTOMLEFT", 1, 1)
  end)
  U.ChainStockTabs(list, modern.Token().tab.gap)
  U.StyleStockTabGroup(list, 1, {
    height = modern.Token().tab.height,
    background = modern.Token().tab.background,
    activeBackground = modern.Token().tab.activeBackground,
    -- Label colours come from the shared tab tokens: accent on the active
    -- tab, grey on the rest; the outline remains neutral in every state.
  })
end

function modern.SyncTabs()
  if not modern.tabs then return end
  local professions = type(U.SpellBookProfessionsShown) == "function" and
                      U.SpellBookProfessionsShown() and true or false
  local spell = U.G("BOOKTYPE_SPELL")
  if type(spell) ~= "string" or spell == "" then spell = "spell" end
  local pet = U.G("BOOKTYPE_PET")
  if type(pet) ~= "string" or pet == "" then pet = "pet" end
  local book = modern.frame and modern.frame.bookType

  if modern.tabs.professions.SetActive then
    modern.tabs.professions.SetActive(professions)
  end
  if modern.tabs.spellbook.SetActive then
    modern.tabs.spellbook.SetActive(not professions and book ~= pet)
  end
  local petTab = U.G("SpellBookFrameTabButton2")
  if petTab and petTab.SetActive then
    petTab.SetActive(not professions and book == pet)
  end
end

function modern.Host()
  return {
    Active = function() return modern.built end,
    Token = modern.Token,
    PagePoint = function(x, y) return x, y end,
    PageScale = function() return 1, 1 end,
    SetPageArt = function() return end,
    Redress = modern.Redress,
    ShowClassPortrait = function() return nil end,
    SetButtonPlacer = function(placer) modern.placer = placer end,
    tab = modern.Token().tab,
    tabGap = modern.Token().tab.gap,
  }
end

function U.BuildModernSpellBookProfessions(frame, panel)
  if modern.built then return true end
  if U.GetActiveThemeStyle() ~= "modern" then return false end
  if not frame or not panel then return false end
  if type(U.ModernSpellBookExtraTabs) ~= "function" then return false end

  modern.frame, modern.panel = frame, panel
  modern.built = true
  local tabs = U.ModernSpellBookExtraTabs(frame, modern.Host())
  if not tabs then
    modern.built = false
    return false
  end
  modern.tabs = tabs
  modern.ChainTabs()
  modern.SyncTabs()

  U.PostHookScript(tabs.professions, "OnClick", modern.SyncTabs)
  U.PostHookScript(tabs.spellbook, "OnClick", modern.SyncTabs)
  U.PostHookScript(frame, "OnShow", modern.SyncTabs)
  U.PostHookGlobal("SpellBookFrame_Update", modern.SyncTabs)
  U.PostHookGlobal("SpellButton_UpdateButton", modern.OnSpellButtonUpdate)
  return true
end
