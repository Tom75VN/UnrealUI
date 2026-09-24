-- unrealUI :: modules/professionsmodern.lua
--
-- The TradeSkill and Craft windows' complete `modern` drawing path. It keeps
-- the same recipe, reagent, tracking and creation workflow as the modern-wow
-- path, but uses only UnrealUI's flat shared components and M.professions.

local U = UnrealUI
local M = U.media
local PR = U.RegisterModule("professionsmodern")

local pm = {
  enabled = false,
  windows = {},
  eventsInstalled = false,
  polling = false,
  pending = nil,
}

pm.KINDS = {
  {
    id = "trade", host = "TradeSkillFrame", close = "TradeSkillFrameCloseButton",
    update = "TradeSkillFrame_Update", count = "GetNumTradeSkills",
    selected = "GetTradeSkillSelectionIndex", select = "SelectTradeSkill",
    expand = "ExpandTradeSkillSubClass", collapse = "CollapseTradeSkillSubClass",
    icon = "GetTradeSkillIcon", numReagents = "GetTradeSkillNumReagents",
    reagent = "GetTradeSkillReagentInfo", tools = "GetTradeSkillTools",
    cooldown = "GetTradeSkillCooldown", link = "GetTradeSkillItemLink",
    reagentLink = "GetTradeSkillReagentItemLink", made = "GetTradeSkillNumMade",
    tipRecipe = "SetTradeSkillItem", tipReagent = "SetTradeSkillItem",
    create = "DoTradeSkill", repeatable = true,
    wheelFrames = { "TradeSkillListScrollFrame", "TradeSkillDetailScrollFrame" },
  },
  {
    id = "craft", host = "CraftFrame", close = "CraftFrameCloseButton",
    update = "CraftFrame_Update", count = "GetNumCrafts",
    selected = "GetCraftSelectionIndex", select = "SelectCraft",
    expand = "ExpandCraftSkillLine", collapse = "CollapseCraftSkillLine",
    icon = "GetCraftIcon", numReagents = "GetCraftNumReagents",
    reagent = "GetCraftReagentInfo", tools = "GetCraftSpellFocus",
    description = "GetCraftDescription", link = "GetCraftItemLink",
    reagentLink = "GetCraftReagentItemLink", tipRecipe = "SetCraftSpell",
    tipReagent = "SetCraftItem", create = "DoCraft", repeatable = false,
    wheelFrames = { "CraftListScrollFrame", "CraftDetailScrollFrame" },
  },
}

pm.FILTERS = {
  { kind = "trivial", key = "showTrivial", label = "PROFESSIONS_FILTER_GRAY" },
  { kind = "easy", key = "showEasy", label = "PROFESSIONS_FILTER_GREEN" },
  { kind = "medium", key = "showMedium", label = "PROFESSIONS_FILTER_YELLOW" },
  { kind = "optimal", key = "showOptimal", label = "PROFESSIONS_FILTER_ORANGE" },
}

-- This window is drawn inside the native TradeSkill/Craft frame, so the client's
-- own list and detail scroll frames are still alive underneath our list. They
-- are ScrollFrames, which is exactly the widget type that receives the wheel on
-- this client (knowledge.json / scripts.scrollframe_receives_mousewheel), and
-- the professionwheel probe caught TradeSkillDetailScrollFrame taking 56 wheel
-- events while the modern window was on screen. Their FauxScrollFrame handlers
-- run the native TradeSkillFrame_Update, which repaints the stock skill buttons
-- over our rows -- the ghost list seen when scrolling.
--
-- Clearing the wheel flag is an input-only change: no Hide, no script
-- replacement, no unregistered event, and the frames keep working for the
-- native window if this addon ever stops drawing over them.
function pm.MuteNativeWheel(kind)
  local names = kind.wheelFrames
  if not names then return end
  local i
  for i = 1, table.getn(names) do
    local frame = U.G(names[i])
    if frame then pcall(frame.EnableMouseWheel, frame, false) end
  end
end

function pm.Token()
  return M.professions
end

function pm.Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, a, b)
end

function pm.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function pm.Level(object)
  if not object or not object.GetFrameLevel then return 1 end
  local ok, level = pcall(object.GetFrameLevel, object)
  return (ok and tonumber(level)) or 1
end

function pm.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

function pm.Frame(kind, parent, levelOffset, mouse)
  local ok, frame = pcall(CreateFrame, kind or "Frame", nil, parent)
  if not ok or not frame then return nil end
  if levelOffset then
    pcall(frame.SetFrameLevel, frame, pm.Level(parent) + levelOffset)
  end
  pcall(frame.EnableMouse, frame, mouse and true or false)
  return frame
end

function pm.Texture(parent, layer, path)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer or "ARTWORK")
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path or M.texture.plain)
  return texture
end

function pm.Label(parent, size, color, justify, inherits)
  return U.CreateLabel(parent, {
    size = size or M.fontSize.normal,
    color = color or M.color.text,
    inherits = inherits or "GameFontNormal",
    justify = justify or "LEFT",
  })
end

function pm.SetText(label, text)
  if label then pcall(label.SetText, label, text or "") end
end

function pm.SetColor(label, color)
  if label and color then pcall(label.SetTextColor, label, M.Unpack(color)) end
end

function pm.TextWidth(label)
  if not label then return 0 end
  local ok, width = pcall(label.GetStringWidth, label)
  return (ok and tonumber(width)) or 0
end

function pm.Info(win, index)
  if win.kind.id == "trade" then
    local ok, name, kind, available, expanded = pm.Call("GetTradeSkillInfo", index)
    if not ok or type(name) ~= "string" then return nil end
    return name, kind, tonumber(available) or 0, expanded, nil, 0, kind
  end

  local ok, name, sub, kind, available, expanded, points = pm.Call("GetCraftInfo", index)
  if not ok or type(name) ~= "string" then return nil end
  local raw = kind
  if kind == "used" then kind = "trivial"
  elseif kind == "none" then kind = "easy" end
  if sub == "" then sub = nil end
  return name, kind, tonumber(available) or 0, expanded, sub,
         tonumber(points) or 0, raw
end

function pm.Line(win)
  local unknown = U.G("UNKNOWN")
  local ok, name, rank, maxRank
  if win.kind.id == "trade" then
    ok, name, rank, maxRank = pm.Call("GetTradeSkillLine")
  else
    ok, name, rank, maxRank = pm.Call("GetCraftDisplaySkillLine")
    if not ok or type(name) ~= "string" or name == "" or name == unknown then
      local nameOk, craftName = pm.Call("GetCraftName")
      if nameOk and type(craftName) == "string" and craftName ~= unknown then
        name = craftName
      end
    end
  end
  if type(name) ~= "string" or name == unknown then name = "" end
  return name, tonumber(rank) or 0, tonumber(maxRank) or 0
end

function pm.Selected(win)
  local ok, index = pm.Call(win.kind.selected)
  return (ok and tonumber(index)) or 0
end

function pm.Tools(win, index)
  local ok, n1, h1, n2, h2, n3, h3, n4, h4 = pm.Call(win.kind.tools, index)
  if not ok then return nil end
  local list = { { n1, h1 }, { n2, h2 }, { n3, h3 }, { n4, h4 } }
  local text
  local i
  for i = 1, 4 do
    local name = list[i][1]
    if type(name) == "string" and name ~= "" then
      if not list[i][2] then name = "|cffff2020" .. name .. "|r" end
      text = text and (text .. ", " .. name) or name
    end
  end
  return text
end

function pm.LinkColor(link)
  if type(link) ~= "string" then return nil end
  local _, _, r, g, b = string.find(link, "|c%x%x(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255,
           tonumber(b, 16) / 255, 1 }
end

function pm.Tip(owner, method, a, b)
  local tip = U.G("GameTooltip")
  if not tip or type(tip[method]) ~= "function" then return end
  pcall(tip.SetOwner, tip, owner, "ANCHOR_TOPLEFT")
  if b then pcall(tip[method], tip, a, b) else pcall(tip[method], tip, a) end
  pcall(tip.Show, tip)
end

function pm.HideTip()
  if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  local tip = U.G("GameTooltip")
  if tip then pcall(tip.Hide, tip) end
end

function pm.InsertChatLink(link)
  if type(link) ~= "string" or link == "" then return false end
  local shift = U.G("IsShiftKeyDown")
  if type(shift) ~= "function" then return false end
  local shiftOk, down = pcall(shift)
  if not shiftOk or not down then return false end
  local insert = U.G("ChatEdit_InsertLink")
  if type(insert) == "function" and pcall(insert, link) then return true end
  local edit = U.G("ChatFrameEditBox")
  if not edit or type(edit.IsVisible) ~= "function" or type(edit.Insert) ~= "function" then
    return false
  end
  local visibleOk, visible = pcall(edit.IsVisible, edit)
  if not visibleOk or not visible then return false end
  return pcall(edit.Insert, edit, link)
end

function pm.LinkClick(win, reagentIndex)
  local selected = pm.Selected(win)
  if selected <= 0 then return end
  local getter = reagentIndex and win.kind.reagentLink or win.kind.link
  if not getter then return end
  local ok, link = pm.Call(getter, selected, reagentIndex)
  if ok then pm.InsertChatLink(link) end
end

function pm.Queue(win)
  U.DeferOnce(win.key, function() pm.Refresh(win) end)
end

-- Recipe filters, stored per profile. Read on every refresh rather than
-- cached, because a profile switch replaces U.db without a reload.
function pm.FilterConfig()
  return U.ModuleConfig("professions", {
    showTrivial = true,
    showEasy = true,
    showMedium = true,
    showOptimal = true,
    allReagents = false,
  })
end

function pm.SetFilter(win, key, value)
  pm.FilterConfig()[key] = value and true or false
  win.offset = 1
  win.reveal = true
  win.selectionHidden = nil
  pm.Queue(win)
end

function pm.SetQuery(win, text)
  win.query = type(U.SearchFold) == "function" and U.SearchFold(text) or ""
  win.expandForSearch = win.query ~= ""
  win.offset = 1
  win.reveal = true
  win.selectionHidden = nil
  pm.Queue(win)
end

-- A Craft entry whose raw difficulty is "none" (Beast Training) has neither a
-- difficulty nor a reagent count, so no filter applies to it.
function pm.RecipeVisible(config, entry)
  if not entry or entry.kind == "header" then return false end
  if entry.raw == "none" then return true end
  local i
  for i = 1, table.getn(pm.FILTERS) do
    local spec = pm.FILTERS[i]
    if entry.kind == spec.kind and not config[spec.key] then return false end
  end
  if config.allReagents and entry.available <= 0 then return false end
  return true
end

function pm.RecipeMatchesSearch(win, entry)
  local query = win and win.query
  if type(query) ~= "string" or query == "" then return true end
  local name = type(U.SearchFold) == "function" and U.SearchFold(entry.name) or ""
  return string.find(name, query, 1, true) ~= nil
end

function pm.SyncFilters(win, config)
  local controls = win.filterControls
  if not controls then return end
  local i
  for i = 1, table.getn(controls) do
    local control = controls[i]
    if (control.value and true or false) ~= (config[control.filterKey] and true or false) then
      control.SetValue(config[control.filterKey])
    end
  end
end

function pm.AppendEntry(entries, entry)
  local previous = entries[table.getn(entries)]
  if previous then
    previous.groupEnd = previous.kind ~= "header" and entry.kind == "header"
  end
  table.insert(entries, entry)
end

function pm.SetPanelState(frame, color, border)
  U.SetBackgroundColor(frame, M.Unpack(color))
  U.SetBorderColor(frame, M.Unpack(border or { 0, 0, 0, 0 }))
end

function pm.BuildChrome(win)
  local t = pm.Token()
  local panel = U.CreatePanel(win.frame, {
    name = "UnrealUIProfessionsModern" .. win.kind.id,
    background = t.panelColor,
  })
  pcall(panel.SetAllPoints, panel, win.frame)
  pcall(panel.SetFrameLevel, panel, pm.Level(win.frame) + t.levels.cover)
  pcall(panel.EnableMouse, panel, true)
  win.cover = panel

  win.title = pm.Label(panel, M.fontSize.large, M.color.accent, "CENTER")
  if win.title then pcall(win.title.SetPoint, win.title, "TOP", panel, "TOP", 0, -t.title.y) end

  local pi = t.professionIcon
  win.professionSlot = U.CreatePanel(panel, {
    width = pi.size, height = pi.size, background = t.insetColor,
  })
  if win.professionSlot then
    pcall(win.professionSlot.SetPoint, win.professionSlot, "TOPLEFT", panel,
          "TOPLEFT", pi.x, -pi.y)
    win.professionIcon = pm.Texture(win.professionSlot, "ARTWORK", t.texture.missingIcon)
    if win.professionIcon then
      pcall(function()
        win.professionIcon:SetPoint("TOPLEFT", win.professionSlot, "TOPLEFT", 1, -1)
        win.professionIcon:SetPoint("BOTTOMRIGHT", win.professionSlot, "BOTTOMRIGHT", -1, 1)
        win.professionIcon:SetTexCoord(pi.crop[1], pi.crop[2], pi.crop[3], pi.crop[4])
      end)
    end
  end

  local r = t.rank
  win.rankBar = U.CreateStatusBar(panel, {
    width = r.width, height = r.height,
    background = t.rankBackground, color = t.rankFill,
  })
  if win.rankBar then
    pcall(win.rankBar.SetPoint, win.rankBar, "TOP", panel, "TOP", 0, -r.y)
    U.CreateBorder(win.rankBar)
    U.SetBorderColor(win.rankBar, M.Unpack(M.color.border))
  end
  -- Parent the number to the bar, not the window cover. Child frames draw
  -- above regions owned by their parent, so a cover-owned FontString can sit
  -- behind the rank bar even on OVERLAY. As the bar's own OVERLAY it stays on
  -- top of both the empty track and the green fill.
  win.rankText = pm.Label(win.rankBar or panel, M.fontSize.tiny,
                          t.rankTextColor, "CENTER", "GameFontNormalSmall")
  if win.rankText then
    pcall(win.rankText.SetPoint, win.rankText, "TOP", panel, "TOP", 0,
          -t.rankText.y)
  end
end

function pm.SetRank(win, rank, maxRank)
  if win.rankBar then
    pcall(win.rankBar.SetMinMaxValues, win.rankBar, 0, math.max(1, maxRank))
    pcall(win.rankBar.SetValue, win.rankBar, math.max(0, rank))
  end
  pm.SetText(win.rankText, maxRank > 0 and (rank .. "/" .. maxRank) or "")
end

function pm.RowHeight(entry)
  local l = pm.Token().list
  return entry.kind == "header" and l.headerHeight or l.rowHeight
end

function pm.EntryHeight(entry)
  local l = pm.Token().list
  local height = pm.RowHeight(entry)
  if entry.kind == "header" then height = height + l.headerGap end
  if entry.groupEnd then height = height + l.groupGap end
  return height
end

function pm.ListCapacity()
  local t = pm.Token()
  return t.design.height - t.list.y - t.list.bottom - t.list.inset * 2
end

function pm.RowWidth(win)
  local l = pm.Token().list
  local width = l.width - l.inset * 2
  if (win.maxOffset or 1) > 1 then width = width - l.scrollWidth - 3 end
  return width
end

function pm.DifficultyColor(entry)
  local colors = pm.Token().difficultyColor
  return (entry and colors[entry.kind]) or colors.trivial
end

function pm.PaintRow(row)
  if not row or not row.entry then return end
  local t = pm.Token()
  local entry = row.entry
  if entry.kind == "header" then
    pm.SetPanelState(row, row.hovered and t.rowHover or t.headerColor,
                     row.hovered and M.color.accentDim or M.color.border)
    pm.SetColor(row.label, row.hovered and M.color.accent or M.color.text)
    return
  end
  local color = pm.DifficultyColor(entry)
  local fill, border = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  if row.selected then
    fill = { color[1], color[2], color[3], t.rowState.focusFillAlpha }
    border = { color[1], color[2], color[3], t.rowState.focusBorderAlpha }
  elseif row.hovered then
    fill = { color[1], color[2], color[3], t.rowState.hoverFillAlpha }
    border = { color[1], color[2], color[3], t.rowState.hoverBorderAlpha }
  end
  pm.SetPanelState(row, fill, border)
  pm.SetColor(row.label, color)
  pm.SetColor(row.count, color)
end

function pm.OnRowClick(win, row)
  local entry = row.entry
  if not entry then return end
  if entry.kind == "header" then
    if entry.expanded then win.selectionHidden = true end
    local ok = pm.Call(entry.expanded and win.kind.collapse or win.kind.expand,
                       entry.index)
    if not ok then win.selectionHidden = nil end
  else
    win.selectionHidden = nil
    if entry.index ~= pm.Selected(win) then win.count = 1 end
    pm.Call(win.kind.select, entry.index)
  end
  pm.Queue(win)
end

function pm.BuildRow(win, index)
  local t, l = pm.Token(), pm.Token().list
  local di = t.difficultyIcon
  local row = pm.Frame("Button", win.list, 2, true)
  if not row then return nil end
  pcall(row.SetHeight, row, l.rowHeight)
  U.CreateBackdrop(row, { background = { 0, 0, 0, 0 } })

  row.skill = pm.Texture(row, "ARTWORK", di.texture)
  if row.skill then
    pcall(function()
      row.skill:SetWidth(di.width)
      row.skill:SetHeight(di.height)
      row.skill:SetPoint("LEFT", row, "LEFT", di.x, 0)
    end)
  end
  row.label = pm.Label(row, M.fontSize.normal, M.color.text, "LEFT", "GameFontHighlight")
  if row.label then
    pcall(row.label.SetPoint, row.label, "LEFT", row, "LEFT", di.labelX, -2)
  end
  row.count = pm.Label(row, di.countFontSize, M.color.textDim, "RIGHT",
                       "GameFontHighlight")
  if row.count and row.label then
    pcall(row.count.SetPoint, row.count, "LEFT", row.label, "RIGHT",
          di.countGap, -1)
  end
  row.tracked = pm.Texture(row, "OVERLAY")
  if row.tracked then
    pcall(function()
      row.tracked:SetWidth(t.tracked.width)
      row.tracked:SetPoint("TOPRIGHT", row, "TOPRIGHT", -t.tracked.right,
                           -t.tracked.inset)
      row.tracked:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -t.tracked.right,
                           t.tracked.inset)
      row.tracked:SetVertexColor(M.Unpack(M.color.accent))
    end)
  end
  row.collapse = U.CreateCollapseButton(row, {
    size = 16,
    onClick = function() pm.OnRowClick(win, row) end,
  })
  if row.collapse then pcall(row.collapse.SetPoint, row.collapse, "RIGHT", row, "RIGHT", -3, 0) end

  row:SetScript("OnEnter", function() row.hovered = true pm.PaintRow(row) end)
  row:SetScript("OnLeave", function() row.hovered = false pm.PaintRow(row) end)
  row:SetScript("OnClick", function() pm.OnRowClick(win, row) end)
  win.rows[index] = row
  return row
end

function pm.FillRow(win, row, entry, selectedIndex)
  local t, di = pm.Token(), pm.Token().difficultyIcon
  row.entry = entry
  local header = entry.kind == "header"
  row.selected = not header and entry.index == selectedIndex
  pcall(row.SetHeight, row, pm.RowHeight(entry))
  pcall(row.SetWidth, row, pm.RowWidth(win))

  pm.SetText(row.label, entry.name .. ((entry.sub and (" (" .. entry.sub .. ")")) or ""))
  local available = not header and entry.available > 0 and ("[" .. entry.available .. "]") or ""
  pm.SetText(row.count, available)

  if row.collapse then
    row.collapse.uuiSetCollapsed(not entry.expanded)
    pm.SetShown(row.collapse, header)
  end
  local cell = not header and di.cells[entry.kind] or nil
  if row.skill and cell then
    pcall(row.skill.SetTexCoord, row.skill,
          cell.left / di.atlasWidth, cell.right / di.atlasWidth,
          cell.top / di.atlasHeight, cell.bottom / di.atlasHeight)
  end
  pm.SetShown(row.skill, cell ~= nil)
  local tracked = not header and type(U.CraftTrackerIsTracked) == "function" and
                  U.CraftTrackerIsTracked(entry.name)
  pm.SetShown(row.tracked, tracked)
  pm.SetShown(row.count, not header)

  if row.label then
    if header then
      pcall(function()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", di.labelX, -4)
        row.label:SetPoint("RIGHT", row, "RIGHT", -24, -4)
      end)
    else
      local reserve = di.padding
      if tracked then
        reserve = t.tracked.right + t.tracked.width + di.trackedGap
      end
      local room = pm.RowWidth(win) - di.labelX - reserve
      if available ~= "" then
        room = room - pm.TextWidth(row.count) - di.countGap
      end
      room = math.max(1, room)
      pcall(function()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", di.labelX, -2)
      end)
      -- No width is ever set on this label: see U.FitLabelText.
      U.FitLabelText(row.label, entry.name ..
                     ((entry.sub and (" (" .. entry.sub .. ")")) or ""), room)
      if row.count then
        pcall(function()
          row.count:ClearAllPoints()
          row.count:SetPoint("LEFT", row.label, "RIGHT", di.countGap, -1)
        end)
      end
    end
  end
  pm.PaintRow(row)
end

function pm.MaxOffset(win)
  local n = table.getn(win.entries)
  if n == 0 then return 1 end
  local capacity, used = pm.ListCapacity(), 0
  local i
  for i = n, 1, -1 do
    used = used + pm.EntryHeight(win.entries[i])
    if used > capacity then return math.min(n, i + 1) end
  end
  return 1
end

function pm.Reveal(win, index)
  local position, i
  for i = 1, table.getn(win.entries) do
    if win.entries[i].index == index then position = i break end
  end
  if not position then return end
  if position < win.offset then win.offset = position return end
  local used = 0
  for i = win.offset, position do used = used + pm.EntryHeight(win.entries[i]) end
  while used > pm.ListCapacity() and win.offset < position do
    used = used - pm.EntryHeight(win.entries[win.offset])
    win.offset = win.offset + 1
  end
end

function pm.ReadScroll(win)
  local bar = win.scroll and win.scroll.bar
  if not bar or win.syncingScroll then return end
  local ok, value = pcall(bar.GetValue, bar)
  value = ok and tonumber(value) or nil
  if not value then return end
  value = math.max(1, math.min(win.maxOffset, math.floor(value + 0.5)))
  if value == win.offset then return end
  win.offset = value
  pm.Queue(win)
end

-- One row per wheel tick, through the same offset the arrows and the slider
-- drive, so every scroll route stays clamped the same way.
function pm.WheelScroll(win, direction)
  if not win.maxOffset or win.maxOffset <= 1 then return end
  local target = math.max(1, math.min(win.maxOffset, (win.offset or 1) - direction))
  if target == win.offset then return end
  win.offset = target
  pm.LayoutScroll(win)
  pm.Queue(win)
end

function pm.BuildScroll(win)
  local l = pm.Token().list
  -- The template hangs each arrow outside the Slider. Reserve one arrow at
  -- each end so the complete control, not only its track, fits the list pane.
  local paneHeight = pm.Token().design.height - l.y - l.bottom
  local barHeight = math.max(1, paneHeight - (l.scrollArrow + l.scrollPad) * 2)
  local name = "UnrealUIProfessionsModern" .. win.kind.id .. "ScrollBar"
  local ok, bar = pcall(CreateFrame, "Slider", name, win.list, "UIPanelScrollBarTemplate")
  if not ok or not bar then return end
  pcall(bar.SetScript, bar, "OnValueChanged", nil)
  pcall(function()
    bar:SetFrameLevel(pm.Level(win.list) + 3)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(l.scrollWidth)
    bar:SetHeight(barHeight)
    bar:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", -l.scrollRight,
                 -(l.scrollArrow + l.scrollPad))
    bar:SetMinMaxValues(1, 1)
    bar:SetValueStep(1)
    bar:SetValue(1)
  end)
  U.StyleStockScrollbar(bar)
  local up = U.G(name .. "ScrollUpButton")
  local down = U.G(name .. "ScrollDownButton")
  if up then up:SetScript("OnClick", function()
    local valueOk, value = pcall(bar.GetValue, bar)
    if valueOk and tonumber(value) then pcall(bar.SetValue, bar, value - 1) end
  end) end
  if down then down:SetScript("OnClick", function()
    local valueOk, value = pcall(bar.GetValue, bar)
    if valueOk and tonumber(value) then pcall(bar.SetValue, bar, value + 1) end
  end) end
  bar:SetScript("OnValueChanged", function() pm.ReadScroll(win) end)
  win.scroll = { bar = bar, up = up, down = down }
end

function pm.LayoutScroll(win)
  local scroll = win.scroll
  if not scroll then return end
  local scrollable = win.maxOffset > 1
  pm.SetShown(scroll.bar, scrollable)
  win.syncingScroll = true
  pcall(scroll.bar.SetMinMaxValues, scroll.bar, 1, win.maxOffset)
  pcall(scroll.bar.SetValue, scroll.bar, win.offset)
  win.syncingScroll = false
  if scroll.up then
    if win.offset > 1 then pcall(scroll.up.Enable, scroll.up) else pcall(scroll.up.Disable, scroll.up) end
  end
  if scroll.down then
    if win.offset < win.maxOffset then pcall(scroll.down.Enable, scroll.down) else pcall(scroll.down.Disable, scroll.down) end
  end
end

function pm.LayoutList(win, selectedIndex)
  local l = pm.Token().list
  win.maxOffset = pm.MaxOffset(win)
  win.offset = math.max(1, math.min(win.offset, win.maxOffset))
  local y, used, i = 0, 0, win.offset
  while i <= table.getn(win.entries) do
    local entry = win.entries[i]
    local height = pm.EntryHeight(entry)
    if y + height > pm.ListCapacity() then break end
    used = used + 1
    local row = win.rows[used] or pm.BuildRow(win, used)
    if row then
      pcall(function()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.list, "TOPLEFT", l.inset, -(l.inset + y))
      end)
      pm.FillRow(win, row, entry, selectedIndex)
      pcall(row.Show, row)
    end
    y = y + height
    i = i + 1
  end
  for i = used + 1, table.getn(win.rows) do
    win.rows[i].entry = nil
    pcall(win.rows[i].Hide, win.rows[i])
  end
  pm.LayoutScroll(win)
end

function pm.BuildList(win)
  local t, l = pm.Token(), pm.Token().list
  win.list = U.CreatePanel(win.cover, {
    width = l.width, height = t.design.height - l.y - l.bottom,
    background = t.insetColor,
  })
  pcall(function()
    win.list:SetFrameLevel(pm.Level(win.cover) + t.levels.content)
    win.list:SetPoint("TOPLEFT", win.cover, "TOPLEFT", l.x, -l.y)
  end)
  -- Built before the rows so it stays underneath them: the catcher takes the
  -- wheel without ever taking a recipe click.
  win.wheel = U.CreateWheelCatcher(win.list, function(direction)
    pm.WheelScroll(win, direction)
  end)
  pm.BuildScroll(win)
end

-- One filter toggle: the shared checkbox dressed as the game-settings
-- checkbox (user request, 2026-09-23), its label in the given colour.
function pm.BuildFilterBox(win, config, suffix, key, text, color, x, y, width)
  local f = pm.Token().filter
  local control = U.CreateCheckbox(win.filters, {
    name = "UnrealUIProfessionsModernFilter" .. win.kind.id .. suffix,
    text = text, value = config[key],
    size = f.size, rowHover = true, rowWidth = width,
    rowHeight = f.rowHeight, textWidth = width - f.size - 6,
    onChange = function(value) pm.SetFilter(win, key, value) end,
  })
  if not control then return end
  control.filterKey = key
  control.SetPoint("TOPLEFT", win.filters, "TOPLEFT", x, -y)
  local function PaintLabel(c) pm.SetColor(c.label, color) end
  if type(U.StyleGameSettingsCheckbox) ~= "function" or
     not U.StyleGameSettingsCheckbox(control, PaintLabel) then
    local apply = control.Apply
    control.Apply = function() apply() PaintLabel(control) end
    control.Apply()
  end
  table.insert(win.filterControls, control)
end

-- The difficulty dropdown and the reagent filter above the recipe list. The
-- difficulty entries keep their semantic recipe colour in the menu.
function pm.BuildFilters(win)
  local t, f = pm.Token(), pm.Token().filter
  local config = pm.FilterConfig()
  win.filters = U.CreatePanel(win.cover, {
    width = f.width, height = f.height, background = t.insetColor,
  })
  pcall(function()
    win.filters:SetFrameLevel(pm.Level(win.cover) + t.levels.content)
    win.filters:SetPoint("TOPLEFT", win.cover, "TOPLEFT", f.x, -f.y)
  end)
  win.filterControls = {}

  -- The trainer's Filter control as the flat theme styles it
  -- (U.ProfessionsDifficultyDropdown in modules/professions.lua).
  if type(U.ProfessionsDifficultyDropdown) == "function" then
    win.difficulty = U.ProfessionsDifficultyDropdown(win.filters, {
      name = "UnrealUIProfessionsModernDifficulty" .. win.kind.id,
      width = f.dropdown.width,
      height = f.dropdown.height,
      style = { checkboxes = true, textY = f.dropdown.textY },
      filters = pm.FILTERS,
      config = pm.FilterConfig,
      colorOf = function(kind) return pm.DifficultyColor({ kind = kind }) end,
      onToggle = function(key, value) pm.SetFilter(win, key, value) end,
    })
  end
  if win.difficulty then
    pcall(function()
      win.difficulty:SetFrameLevel(pm.Level(win.filters) + 2)
      win.difficulty:ClearAllPoints()
      win.difficulty:SetPoint("TOPLEFT", win.filters, "TOPLEFT", f.dropdown.x,
                              -f.dropdown.y)
    end)
  end
  pm.BuildFilterBox(win, config, "Reagents", "allReagents",
                    U.L("PROFESSIONS_FILTER_ALL_REAGENTS"), M.color.text,
                    f.reagents.x, f.reagentTop, f.reagents.width)
  if type(U.CreateSearchBox) == "function" then
    win.search = U.CreateSearchBox(win.filters, {
      name = "UnrealUIProfessionsModernSearch" .. win.kind.id,
      placeholder = U.L("BAGS_SEARCH"),
      onChange = function(text) pm.SetQuery(win, text) end,
    })
  end
  if win.search then
    pcall(function()
      win.search:ClearAllPoints()
      win.search:SetPoint("TOPLEFT", win.filters, "TOPLEFT", f.search.x, -f.search.y)
      win.search:SetPoint("TOPRIGHT", win.filters, "TOPRIGHT", -f.search.right,
                          -f.search.y)
      U.LevelSearchBox(win.search, pm.Level(win.filters) + 3)
      U.PaintSearchBox(win.search)
    end)
  end
end

function pm.BuildReagent(win, index)
  local d = pm.Token().detail
  local button = pm.Frame("Button", win.detail, 2, true)
  if not button then return nil end
  pcall(button.SetHeight, button, d.reagentRow)
  U.CreateBackdrop(button, { background = { 0, 0, 0, 0 }, border = false })
  button.slot = U.CreatePanel(button, {
    width = d.reagentIcon, height = d.reagentIcon,
    background = pm.Token().insetColor,
  })
  pcall(button.slot.SetPoint, button.slot, "LEFT", button, "LEFT", 0, 0)
  button.icon = pm.Texture(button.slot, "ARTWORK", pm.Token().texture.missingIcon)
  if button.icon then
    pcall(function()
      button.icon:SetPoint("TOPLEFT", button.slot, "TOPLEFT", 1, -1)
      button.icon:SetPoint("BOTTOMRIGHT", button.slot, "BOTTOMRIGHT", -1, 1)
      button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
  end
  button.label = pm.Label(button, M.fontSize.small, M.color.text, "LEFT",
                           "GameFontHighlightSmall")
  if button.label then
    pcall(function()
      button.label:SetPoint("LEFT", button.slot, "RIGHT", d.reagentTextGap, 0)
      button.label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    end)
  end
  button:SetScript("OnEnter", function()
    local selected = pm.Selected(win)
    if selected > 0 then pm.Tip(button, win.kind.tipReagent, selected, index) end
  end)
  button:SetScript("OnLeave", pm.HideTip)
  button:SetScript("OnClick", function() pm.LinkClick(win, index) end)
  win.reagents[index] = button
  return button
end

function pm.RecipeReagents(win, index)
  local list = {}
  local countOk, n = pm.Call(win.kind.numReagents, index)
  n = (countOk and tonumber(n)) or 0
  local i
  for i = 1, n do
    local ok, name, _, need = pm.Call(win.kind.reagent, index, i)
    if ok and type(name) == "string" and name ~= "" then
      table.insert(list, { name = name, need = tonumber(need) or 1 })
    end
  end
  return list
end

function pm.ToggleTrack(win)
  local index = pm.Selected(win)
  local name = index > 0 and pm.Info(win, index)
  local tracked = false
  if name and type(U.CraftTrackerSetTracked) == "function" then
    if U.CraftTrackerIsTracked(name) then
      tracked = U.CraftTrackerSetTracked(name, nil)
    else
      local profession = pm.Line(win)
      tracked = U.CraftTrackerSetTracked(name, pm.RecipeReagents(win, index),
                                         profession, win.kind.id)
    end
  end
  if win.track then win.track.SetValue(tracked) end
  pm.Queue(win)
end

-- ---------------------------------------------------------------------------
-- Equippable product stats
-- ---------------------------------------------------------------------------

pm.SCANNER_NAME = "UnrealUIProfessionsModernScan"

function pm.Scanner()
  if pm.scanner then return pm.scanner end
  local ok, tip = pcall(CreateFrame, "GameTooltip", pm.SCANNER_NAME, nil,
                        "GameTooltipTemplate")
  if ok and tip then pm.scanner = tip end
  return pm.scanner
end

function pm.ScanRegion(name)
  local region = U.G(name)
  if not region or type(region.GetText) ~= "function" then return nil end
  local ok, text = pcall(region.GetText, region)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  if type(region.IsShown) == "function" then
    local shownOk, shown = pcall(region.IsShown, region)
    if shownOk and not shown then return nil end
  end
  local color = { 1, 1, 1, 1 }
  if type(region.GetTextColor) == "function" then
    local colorOk, r, g, b = pcall(region.GetTextColor, region)
    if colorOk and tonumber(r) and tonumber(g) and tonumber(b) then
      color = { r, g, b, 1 }
    end
  end
  return text, color
end

function pm.DurabilityPattern()
  if pm.durabilityPattern ~= nil then return pm.durabilityPattern or nil end
  local template = U.G("DURABILITY_TEMPLATE")
  if type(template) ~= "string" or template == "" then
    pm.durabilityPattern = false
    return nil
  end
  local pattern = string.gsub(template, "%%%d*%$?d", "\001")
  pattern = string.gsub(pattern, "([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
  pattern = string.gsub(pattern, "\001", function() return "%d+" end)
  pm.durabilityPattern = "^" .. pattern .. "$"
  return pm.durabilityPattern
end

function pm.StatLines(win, index)
  local kind = win.kind
  if not kind.link or index <= 0 then return nil end
  local linkOk, link = pm.Call(kind.link, index)
  if not linkOk or type(link) ~= "string" then return nil end

  local infoOk, _, _, _, _, _, _, _, equipLoc = pcall(GetItemInfo, link)
  if not infoOk or type(equipLoc) ~= "string" or equipLoc == "" or
     pm.Token().statsSkipEquipLoc[equipLoc] then
    return nil
  end

  local tip = pm.Scanner()
  if not tip or type(tip[kind.tipRecipe]) ~= "function" then return nil end
  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")
  if not pcall(tip[kind.tipRecipe], tip, index) then return nil end

  local countOk, count = pcall(tip.NumLines, tip)
  count = countOk and tonumber(count) or 0
  local maxLines = pm.Token().stats.maxLines + 1
  if count > maxLines then count = maxLines end

  local durability = pm.DurabilityPattern()
  local durable = durability == nil
  local lines = {}
  local i
  for i = 2, count do
    local left, leftColor = pm.ScanRegion(pm.SCANNER_NAME .. "TextLeft" .. i)
    local right, rightColor = pm.ScanRegion(pm.SCANNER_NAME .. "TextRight" .. i)
    if left or right then
      table.insert(lines, { left = left, leftColor = leftColor,
                            right = right, rightColor = rightColor })
      if left and durability and string.find(left, durability) then durable = true end
    end
  end
  if not durable or table.getn(lines) == 0 then return nil end
  return lines
end

function pm.BuildStats(win)
  local t, st = pm.Token(), pm.Token().stats
  local panel = U.CreatePanel(win.detail, {
    width = st.width, height = 40, background = t.panelColor,
  })
  if not panel then return end
  pcall(function()
    panel:SetFrameLevel(pm.Level(win.detail) + st.level)
    panel:EnableMouse(false)
    panel:SetPoint("TOPRIGHT", win.detail, "TOPRIGHT", -st.right, -st.top)
    panel:Hide()
  end)
  U.SetBorderColor(panel, M.Unpack(M.color.border))
  win.stats = panel
  win.statsLines = {}
end

function pm.StatsLine(win, index)
  local line = win.statsLines[index]
  if line then return line end
  line = {
    left = pm.Label(win.stats, M.fontSize.normal, M.color.text, "LEFT",
                    "GameFontHighlight"),
    right = pm.Label(win.stats, M.fontSize.normal, M.color.text, "RIGHT",
                     "GameFontHighlight"),
  }
  win.statsLines[index] = line
  return line
end

function pm.SetHeaderSpace(win, statsShown)
  local d, st = pm.Token().detail, pm.Token().stats
  local right = statsShown and (st.right + st.width + st.nameGap) or d.inset
  local left = d.inset + d.icon + d.nameGap
  local width = math.max(1, win.detailWidth - left - right)
  if win.name then
    pcall(function()
      win.name:ClearAllPoints()
      win.name:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", d.nameGap, 0)
      win.name:SetPoint("RIGHT", win.detail, "RIGHT", -right, 0)
    end)
  end
  if win.requires then pcall(win.requires.SetWidth, win.requires, width) end
  if win.cooldown then pcall(win.cooldown.SetWidth, win.cooldown, width) end
end

function pm.FillStats(win, entry)
  local panel = win.stats
  if not panel then return end
  local st = pm.Token().stats
  local lines = entry and pm.StatLines(win, entry.index)
  local count = lines and table.getn(lines) or 0
  local i
  for i = count + 1, table.getn(win.statsLines) do
    pm.SetShown(win.statsLines[i].left, false)
    pm.SetShown(win.statsLines[i].right, false)
  end
  pm.SetShown(panel, count > 0)
  pm.SetHeaderSpace(win, count > 0)
  if count == 0 then return end

  -- Native refreshes can reorder child levels. Reassert the explicit overlay
  -- level whenever the selected recipe changes so the stats stay on top.
  pcall(panel.SetFrameLevel, panel, pm.Level(win.detail) + st.level)
  U.SetBorderColor(panel, M.Unpack(M.color.border))

  local inner = st.width - st.padding * 2
  local total, previous = 0, nil
  for i = 1, count do
    local data = lines[i]
    local line = pm.StatsLine(win, i)
    local rightWidth = 0
    pm.SetShown(line.right, data.right ~= nil)
    if data.right then
      pm.SetText(line.right, data.right)
      pm.SetColor(line.right, data.rightColor)
      rightWidth = pm.TextWidth(line.right) + st.columnGap
    end
    pm.SetShown(line.left, true)
    pm.SetText(line.left, data.left or "")
    pm.SetColor(line.left, data.leftColor or M.color.text)
    pcall(function()
      line.left:ClearAllPoints()
      line.left:SetWidth(math.max(1, inner - rightWidth))
      if previous then
        line.left:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -st.lineGap)
      else
        line.left:SetPoint("TOPLEFT", panel, "TOPLEFT", st.padding, -st.padding)
      end
      line.right:ClearAllPoints()
      line.right:SetPoint("TOPRIGHT", line.left, "TOPLEFT", inner, 0)
    end)

    local heightOk, height = pcall(line.left.GetHeight, line.left)
    height = heightOk and tonumber(height) or 0
    if height <= 0 then height = M.fontSize.normal + 2 end
    total = total + height
    if previous then total = total + st.lineGap end
    previous = line.left
  end
  pcall(panel.SetHeight, panel,
        math.min(st.maxHeight, math.max(24, total + st.padding * 2)))
end

function pm.BuildDetail(win)
  local t, d = pm.Token(), pm.Token().detail
  local width = t.design.width - d.x - d.right
  local height = t.design.height - d.y - d.bottom
  win.detail = U.CreatePanel(win.cover, {
    width = width, height = height, background = t.insetColor,
  })
  pcall(function()
    win.detail:SetFrameLevel(pm.Level(win.cover) + t.levels.content)
    win.detail:SetPoint("TOPLEFT", win.cover, "TOPLEFT", d.x, -d.y)
  end)
  win.detailWidth = width

  win.icon = pm.Frame("Button", win.detail, 2, true)
  pcall(function()
    win.icon:SetWidth(d.icon)
    win.icon:SetHeight(d.icon)
    win.icon:SetPoint("TOPLEFT", win.detail, "TOPLEFT", d.inset, -d.inset)
  end)
  U.CreateBackdrop(win.icon, { background = t.panelColor })
  win.icon.texture = pm.Texture(win.icon, "ARTWORK", t.texture.missingIcon)
  if win.icon.texture then
    pcall(function()
      win.icon.texture:SetPoint("TOPLEFT", win.icon, "TOPLEFT", 1, -1)
      win.icon.texture:SetPoint("BOTTOMRIGHT", win.icon, "BOTTOMRIGHT", -1, 1)
      win.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
  end
  win.icon.count = pm.Label(win.icon, M.fontSize.normal, M.color.text, "RIGHT",
                            "NumberFontNormal")
  if win.icon.count then pcall(win.icon.count.SetPoint, win.icon.count, "BOTTOMRIGHT", win.icon, "BOTTOMRIGHT", -3, 3) end
  win.icon:SetScript("OnEnter", function()
    local selected = pm.Selected(win)
    if selected <= 0 then return end
    pm.Tip(win.icon, win.kind.tipRecipe, selected)
    if win.kind.link and type(U.ShowItemCompare) == "function" then
      local ok, link = pm.Call(win.kind.link, selected)
      if ok then U.ShowItemCompare(link) end
    end
  end)
  win.icon:SetScript("OnLeave", pm.HideTip)
  win.icon:SetScript("OnClick", function() pm.LinkClick(win) end)

  win.name = pm.Label(win.detail, M.fontSize.large, M.color.text, "LEFT")
  if win.name then
    pcall(function()
      win.name:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", d.nameGap, 0)
      win.name:SetPoint("RIGHT", win.detail, "RIGHT", -d.inset, 0)
    end)
  end
  win.requires = pm.Label(win.detail, M.fontSize.small, M.color.textDim, "LEFT",
                          "GameFontNormalSmall")
  if win.requires then pcall(win.requires.SetPoint, win.requires, "TOPLEFT", win.name, "BOTTOMLEFT", 0, -d.lineGap) end
  win.cooldown = pm.Label(win.detail, M.fontSize.small, t.cooldownColor, "LEFT",
                          "GameFontNormalSmall")
  if win.cooldown then pcall(win.cooldown.SetPoint, win.cooldown, "TOPLEFT", win.requires, "BOTTOMLEFT", 0, -d.lineGap) end
  win.description = pm.Label(win.detail, M.fontSize.small, M.color.textDim, "LEFT",
                             "GameFontHighlightSmall")
  if win.description then
    pcall(function()
      win.description:SetPoint("TOPLEFT", win.detail, "TOPLEFT", d.inset, -72)
      win.description:SetWidth(width - d.inset * 2)
      win.description:SetHeight(28)
    end)
  end
  win.reagentLabel = pm.Label(win.detail, M.fontSize.normal, M.color.accent, "LEFT")
  if win.reagentLabel then
    pcall(win.reagentLabel.SetPoint, win.reagentLabel, "TOPLEFT", win.detail,
          "TOPLEFT", d.inset, -d.reagentLabelY)
    pm.SetText(win.reagentLabel, U.L("PROFESSIONS_REAGENTS"))
  end
  win.empty = pm.Label(win.detail, M.fontSize.normal, M.color.textDim, "CENTER")
  if win.empty then
    pcall(win.empty.SetPoint, win.empty, "CENTER", win.detail, "CENTER", 0, 0)
    pm.SetText(win.empty, U.L("PROFESSIONS_NO_RECIPES"))
  end

  local columnWidth = math.floor((width - d.inset * 2 - d.reagentGap) / 2)
  local i
  for i = 1, d.maxReagents do
    local button = pm.BuildReagent(win, i)
    if button then
      pcall(button.SetWidth, button, columnWidth)
      local column = i > d.reagentColumn and 2 or 1
      local row = column == 1 and i or (i - d.reagentColumn)
      local x = d.inset + (column - 1) * (columnWidth + d.reagentGap)
      local y = d.reagentTop + (row - 1) * d.reagentRow
      pcall(button.SetPoint, button, "TOPLEFT", win.detail, "TOPLEFT", x, -y)
    end
  end

  win.track = U.CreateCheckbox(win.detail, {
    name = "UnrealUIProfessionsModernTrack" .. win.kind.id,
    text = U.L("PROFESSIONS_TRACK_RECIPE"),
    size = 14, rowHover = true, rowWidth = t.track.width,
    rowHeight = t.track.height, textWidth = t.track.width - 20,
    onChange = function() pm.ToggleTrack(win) end,
  })
  if win.track then
    if win.track.row and win.track.box then
      pcall(function()
        win.track.box:ClearAllPoints()
        win.track.box:SetPoint("RIGHT", win.track.row, "RIGHT", 0, 0)
      end)
    end
    if win.track.label and win.track.box then
      pcall(function()
        win.track.label:ClearAllPoints()
        win.track.label:SetPoint("RIGHT", win.track.box, "LEFT", -6, 0)
        win.track.label:SetWidth(t.track.width - 20)
        win.track.label:SetJustifyH("RIGHT")
      end)
    end
    win.track.SetPoint("TOPRIGHT", win.detail, "TOPRIGHT",
                       -t.track.right, -t.track.top)
  end
  pm.BuildStats(win)
end

function pm.FillTrack(win, entry)
  if not win.track then return end
  local available = entry ~= nil and type(U.CraftTrackerIsTracked) == "function"
  win.track.SetEnabled(available)
  win.track.SetValue(available and U.CraftTrackerIsTracked(entry.name))
end

function pm.FillDetail(win, entry)
  local t, d, kind = pm.Token(), pm.Token().detail, win.kind
  local visible = entry ~= nil
  local parts = { win.icon, win.name, win.requires, win.cooldown,
                  win.description, win.reagentLabel }
  local i
  for i = 1, table.getn(parts) do pm.SetShown(parts[i], visible) end
  pm.SetShown(win.empty, not visible)
  if not visible then
    for i = 1, table.getn(win.reagents) do pm.SetShown(win.reagents[i], false) end
    pm.FillStats(win, nil)
    pm.FillTrack(win, nil)
    return false
  end
  pm.FillTrack(win, entry)

  local iconOk, icon = pm.Call(kind.icon, entry.index)
  pcall(win.icon.texture.SetTexture, win.icon.texture,
        (iconOk and type(icon) == "string" and icon) or t.texture.missingIcon)
  local countText = ""
  if kind.made then
    local madeOk, minMade, maxMade = pm.Call(kind.made, entry.index)
    minMade, maxMade = tonumber(minMade) or 1, tonumber(maxMade) or 1
    if madeOk and maxMade > 1 then
      countText = minMade == maxMade and tostring(minMade) or (minMade .. "-" .. maxMade)
    end
  end
  pm.SetText(win.icon.count, countText)

  local name = entry.name .. ((entry.sub and (" (" .. entry.sub .. ")")) or "")
  pm.SetText(win.name, name)
  local nameColor = M.color.text
  if kind.link then
    local linkOk, link = pm.Call(kind.link, entry.index)
    nameColor = (linkOk and pm.LinkColor(link)) or nameColor
  end
  pm.SetColor(win.name, nameColor)

  local tools = pm.Tools(win, entry.index)
  pm.SetText(win.requires, tools and (U.L("PROFESSIONS_REQUIRES") .. " " .. tools) or "")
  pm.SetShown(win.requires, tools ~= nil)

  local cooldown
  if kind.cooldown then
    local cdOk, seconds = pm.Call(kind.cooldown, entry.index)
    seconds = cdOk and tonumber(seconds)
    if seconds and seconds > 0 then
      local format, text = U.G("SecondsToTime"), nil
      if type(format) == "function" then
        local fOk, value = pcall(format, seconds)
        if fOk and type(value) == "string" then text = value end
      end
      cooldown = U.L("PROFESSIONS_COOLDOWN", text or U.FormatTimeShort(seconds))
    end
  end
  pm.SetText(win.cooldown, cooldown or "")
  pm.SetShown(win.cooldown, cooldown ~= nil)

  local description
  if kind.description then
    local descOk, text = pm.Call(kind.description, entry.index)
    if descOk and type(text) == "string" and text ~= "" then description = text end
  end
  pm.SetText(win.description, description or "")
  pm.SetShown(win.description, description ~= nil)

  local countOk, numReagents = pm.Call(kind.numReagents, entry.index)
  numReagents = (countOk and tonumber(numReagents)) or 0
  pm.SetShown(win.reagentLabel, numReagents > 0)
  local creatable = true
  for i = 1, d.maxReagents do
    local button = win.reagents[i]
    local rName, rIcon, need, have
    if i <= numReagents then
      local reagentOk
      reagentOk, rName, rIcon, need, have = pm.Call(kind.reagent, entry.index, i)
      if not reagentOk then rName = nil end
    end
    if button and type(rName) == "string" then
      need, have = tonumber(need) or 0, tonumber(have) or 0
      local enough = have >= need
      if not enough then creatable = false end
      pcall(button.icon.SetTexture, button.icon,
            type(rIcon) == "string" and rIcon or t.texture.missingIcon)
      pcall(button.icon.SetVertexColor, button.icon,
            enough and 1 or 0.5, enough and 1 or 0.5, enough and 1 or 0.5)
      pm.SetText(button.label, have .. "/" .. need .. " " .. rName)
      pm.SetColor(button.label, enough and M.color.text or t.missingColor)
      pm.SetShown(button, true)
    elseif button then
      pm.SetShown(button, false)
    end
  end
  if entry.raw == "used" then creatable = false end
  pm.FillStats(win, entry)
  return creatable
end

function pm.SetButtonEnabled(button, enabled)
  if not button then return end
  enabled = enabled and true or false
  button.uuiEnabled = enabled
  if enabled then pcall(button.Enable, button) else pcall(button.Disable, button) end
  pm.SetColor(button.label, enabled and M.color.text or M.color.textDim)
  U.SetBorderColor(button, M.Unpack(enabled and M.color.border or M.color.background))
end

function pm.ActionButton(win, parent, text, width, onClick)
  local c = pm.Token().controls
  local button
  button = U.CreateButton(parent, {
    text = text, width = width or c.width, height = c.height,
    onClick = function() if button.uuiEnabled then onClick() end end,
  })
  pcall(button.SetFrameLevel, button, pm.Level(parent) + 2)
  button.uuiEnabled = true
  return button
end

function pm.Create(win, all)
  local selected = pm.Selected(win)
  if selected <= 0 then return end
  local ok, err
  if win.kind.repeatable then
    local count = win.count or 1
    if all then
      local _, _, available = pm.Info(win, selected)
      count = math.max(1, available or 1)
      win.count = math.min(count, pm.Token().controls.maxCount)
    end
    ok, err = pm.Call(win.kind.create, selected, count)
  else
    ok, err = pm.Call(win.kind.create, selected)
  end
  if not ok and err then U.Error("professions modern " .. win.kind.create .. ": " .. tostring(err)) end
  pm.Queue(win)
end

function pm.BuildControls(win)
  local c = pm.Token().controls
  win.create = pm.ActionButton(win, win.cover, U.L("PROFESSIONS_CREATE"), c.width,
                               function() pm.Create(win, false) end)
  pcall(win.create.SetPoint, win.create, "BOTTOMRIGHT", win.cover, "BOTTOMRIGHT",
        -c.right, c.bottom)
  if not win.kind.repeatable then
    win.points = pm.Label(win.cover, M.fontSize.small, M.color.textDim, "RIGHT",
                          "GameFontNormalSmall")
    if win.points then pcall(win.points.SetPoint, win.points, "RIGHT", win.create, "LEFT", -10, 0) end
    return
  end

  win.createAll = pm.ActionButton(win, win.cover, U.L("PROFESSIONS_CREATE_ALL"),
                                  c.width, function() pm.Create(win, true) end)
  pcall(win.createAll.SetPoint, win.createAll, "RIGHT", win.create, "LEFT", -c.gap, 0)

  -- Minus on the left of the count, plus on its right (user request,
  -- 2026-09-20), so the step row reads [-][count][+] before Create All. The
  -- buttons are built right to left because each anchors to the one already
  -- placed beside it.
  win.increment = pm.ActionButton(win, win.cover, "+", c.step, function()
    win.count = math.min(c.maxCount, (win.count or 1) + 1)
    pm.Queue(win)
  end)
  pcall(win.increment.SetPoint, win.increment, "RIGHT", win.createAll, "LEFT", -c.gap, 0)
  win.countBox = U.CreatePanel(win.cover, {
    width = c.count, height = c.height, background = pm.Token().insetColor,
  })
  pcall(win.countBox.SetPoint, win.countBox, "RIGHT", win.increment, "LEFT", -c.gap, 0)
  win.countText = pm.Label(win.countBox, M.fontSize.normal, M.color.text, "CENTER")
  if win.countText then pcall(win.countText.SetPoint, win.countText, "CENTER", win.countBox, "CENTER", 0, -1) end
  win.decrement = pm.ActionButton(win, win.cover, "-", c.step, function()
    win.count = math.max(1, (win.count or 1) - 1)
    pm.Queue(win)
  end)
  pcall(win.decrement.SetPoint, win.decrement, "RIGHT", win.countBox, "LEFT", -c.gap, 0)
end

function pm.FillControls(win, entry, creatable)
  local hasRecipe = entry ~= nil and entry.kind ~= "header"
  pm.SetButtonEnabled(win.create, hasRecipe and creatable)
  if not win.kind.repeatable then
    local token, verb = U.G("GetCraftButtonToken"), nil
    if type(token) == "function" then
      local ok, key = pcall(token)
      if ok and type(key) == "string" and type(U.G(key)) == "string" then verb = U.G(key) end
    end
    pm.SetText(win.create and win.create.label, verb or U.L("PROFESSIONS_CREATE"))
    pm.SetText(win.points, entry and entry.points > 0 and
               U.L("PROFESSIONS_TRAINING_POINTS", entry.points) or "")
    return
  end
  local repeatOk, remaining = pm.Call("GetTradeskillRepeatCount")
  remaining = repeatOk and tonumber(remaining)
  if remaining and remaining > 1 then win.count = remaining end
  win.count = math.max(1, math.min(pm.Token().controls.maxCount, win.count or 1))
  pm.SetText(win.countText, tostring(win.count))
  pm.SetButtonEnabled(win.createAll, hasRecipe and creatable)
  pm.SetButtonEnabled(win.decrement, hasRecipe and win.count > 1)
  pm.SetButtonEnabled(win.increment, hasRecipe and win.count < pm.Token().controls.maxCount)
end

function pm.ApplySize(win)
  local d = pm.Token().design
  local wOk, width = pcall(win.frame.GetWidth, win.frame)
  local hOk, height = pcall(win.frame.GetHeight, win.frame)
  if not (wOk and tonumber(width) == d.width) then pcall(win.frame.SetWidth, win.frame, d.width) end
  if not (hOk and tonumber(height) == d.height) then pcall(win.frame.SetHeight, win.frame, d.height) end
end

function pm.ProfessionIcon(win, name)
  local key
  if type(U.ModernWowProfessionKey) == "function" then key = U.ModernWowProfessionKey(name) end
  if type(U.ModernWowProfessionIcon) == "function" then
    local icon = U.ModernWowProfessionIcon(key)
    if icon then return icon end
  end
  if not key and win.kind.id == "craft" then
    return pm.Token().texture.beastTrainingIcon
  end
  return pm.Token().texture.missingIcon
end

function pm.Refresh(win)
  if not win.built or not pm.Shown(win.frame) then return end
  pm.ApplySize(win)
  local name, rank, maxRank = pm.Line(win)
  pm.SetText(win.title, name)
  pm.SetRank(win, rank, maxRank)
  if win.professionIcon then
    pcall(win.professionIcon.SetTexture, win.professionIcon,
          pm.ProfessionIcon(win, name))
  end

  local pending = pm.pending
  local wantsPending = (not win.query or win.query == "") and pending and
                       (not pending.kind or pending.kind == win.kind.id) and
                       (not pending.profession or pending.profession == name)
  if wantsPending then
    pm.Call(win.kind.expand, 0)
  elseif win.expandForSearch then
    win.expandForSearch = nil
    pm.Call(win.kind.expand, 0)
  end

  local entries, firstRecipe, pendingEntry = {}, nil, nil
  -- An expanded category is listed only once one of its recipes passes the
  -- filters; a collapsed one always is, since its recipes are not reported.
  local openHeader, config = nil, pm.FilterConfig()
  pm.SyncFilters(win, config)
  local countOk, count = pm.Call(win.kind.count)
  count = (countOk and tonumber(count)) or 0
  local selected = pm.Selected(win)
  local selectedEntry
  local i
  for i = 1, count do
    local rName, kind, available, expanded, sub, points, raw = pm.Info(win, i)
    if rName then
      local entry = { index = i, name = rName, kind = kind, available = available,
                      expanded = expanded and true or false, sub = sub,
                      points = points, raw = raw }
      if kind == "header" then
        openHeader = entry.expanded and entry or nil
        if not entry.expanded and (not win.query or win.query == "") then
          pm.AppendEntry(entries, entry)
        end
      else
        local pendingMatch = wantsPending and rName == pending.recipe
        if (pm.RecipeVisible(config, entry) and pm.RecipeMatchesSearch(win, entry)) or
           pendingMatch then
          if openHeader then
            pm.AppendEntry(entries, openHeader)
            openHeader = nil
          end
          pm.AppendEntry(entries, entry)
          if not firstRecipe then firstRecipe = entry end
          if i == selected then selectedEntry = entry end
          if pendingMatch then pendingEntry = entry end
        end
      end
      if kind ~= "header" and type(U.CraftTrackerRememberSource) == "function" and
         U.CraftTrackerIsTracked(rName) then
        U.CraftTrackerRememberSource(rName, name, win.kind.id)
      end
    end
  end
  win.entries = entries

  if pendingEntry then
    selected = pendingEntry.index
    selectedEntry = pendingEntry
    pm.Call(win.kind.select, selected)
    win.count, win.reveal, pm.pending = 1, true, nil
  end
  if selectedEntry then win.selectionHidden = nil end
  if not selectedEntry and firstRecipe and not win.selectionHidden then
    selectedEntry, selected = firstRecipe, firstRecipe.index
    pm.Call(win.kind.select, selected)
    win.count = 1
  end
  if win.reveal and selectedEntry then win.reveal = false pm.Reveal(win, selected) end
  pm.LayoutList(win, selected)
  pm.FillControls(win, selectedEntry, pm.FillDetail(win, selectedEntry))
end

function pm.RefreshAll()
  local i
  for i = 1, table.getn(pm.windows) do
    if pm.Shown(pm.windows[i].frame) then pm.Queue(pm.windows[i]) end
  end
end

function pm.ResetSearch(win)
  win.query = ""
  win.expandForSearch = nil
  if type(U.ResetSearchBox) == "function" then U.ResetSearchBox(win.search) end
end

function pm.Build(kind)
  local frame = U.G(kind.host)
  if not frame then return false end
  local win = {
    kind = kind, frame = frame, key = "professions.modern.refresh." .. kind.id,
    entries = {}, rows = {}, reagents = {}, offset = 1, maxOffset = 1,
    count = 1, reveal = true,
  }
  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  pm.ApplySize(win)
  pcall(frame.SetHitRectInsets, frame, 0, 0, 0, 0)

  pm.MuteNativeWheel(kind)
  pm.BuildChrome(win)
  pm.BuildFilters(win)
  pm.BuildList(win)
  pm.BuildDetail(win)
  pm.BuildControls(win)

  local t = pm.Token()
  local close = U.G(kind.close)
  if close then
    U.StyleStockCloseButton(close, win.cover, t.close.x, t.close.y)
    pcall(close.SetFrameLevel, close, pm.Level(frame) + t.levels.close)
  end
  local nativeTitle = U.G(kind.host .. "TitleText")
  if nativeTitle then pcall(nativeTitle.Hide, nativeTitle) end
  U.MakeWindowDraggable("professions-modern-" .. kind.id, frame, {
    headerHeight = t.drag.headerHeight,
    headerInset = t.drag.inset,
    headerLevelOffset = t.levels.cover + t.levels.handle,
    interactiveFrames = close and { close } or nil,
  })

  U.PostHookScript(frame, "OnShow", function()
    win.reveal = true
    pm.Refresh(win)
    pm.Queue(win)
  end)
  U.PostHookScript(frame, "OnHide", function()
    pm.HideTip()
    pm.ResetSearch(win)
  end)
  if type(U.G(kind.update)) == "function" then
    U.PostHookGlobal(kind.update, function() pm.Queue(win) end)
  end
  -- The same header-selection freeze as the Modern WoW window (see
  -- U.ProfessionsGuardHeaderSelection in modules/professions.lua).
  if type(U.ProfessionsGuardHeaderSelection) == "function" then
    U.ProfessionsGuardHeaderSelection(kind.id, kind.id == "trade" and
      "TradeSkillFrame_SetSelection" or "CraftFrame_SetSelection")
  end
  win.built = true
  table.insert(pm.windows, win)
  frame.uuiModernProfessionWindow = win.cover
  pm.Refresh(win)
  return true
end

function pm.TryBuildAll()
  local pending = false
  local i
  for i = 1, table.getn(pm.KINDS) do
    local kind = pm.KINDS[i]
    if not kind.built then
      if U.G(kind.host) then
        local ok, err = pcall(pm.Build, kind)
        kind.built = true
        if not ok then
          kind.failed = true
          U.Error("professions modern " .. kind.host .. ": " .. tostring(err))
        end
      else
        pending = true
      end
    end
  end
  if not pending and pm.polling then
    pm.polling = false
    U.UnregisterUpdate("professions.modern.build")
    U.UnregisterEvent("ADDON_LOADED", pm.TryBuildAll)
  end
  return pending
end

function U.ModernProfessionsOpenRecipe(recipe, kind, profession)
  if type(recipe) ~= "string" or recipe == "" then return false end
  pm.pending = {
    recipe = recipe,
    kind = type(kind) == "string" and kind or nil,
    profession = type(profession) == "string" and profession ~= "" and profession or nil,
  }
  local i
  for i = 1, table.getn(pm.windows) do
    local win = pm.windows[i]
    if pm.Shown(win.frame) and (not pm.pending.kind or pm.pending.kind == win.kind.id) then
      pm.Refresh(win)
      if not pm.pending then return true end
    end
  end
  return false
end

function U.ModernProfessionsCastBarAnchor()
  local i
  for i = 1, table.getn(pm.windows) do
    local win = pm.windows[i]
    if win.createAll and pm.Shown(win.frame) and pm.Shown(win.createAll) then
      local c = pm.Token().controls
      return win.createAll, c.castBarGap, c.castBarShiftX, c.castBarShiftY
    end
  end
  return nil
end

function U.ModernProfessionsHealthy()
  local i
  for i = 1, table.getn(pm.KINDS) do
    local kind = pm.KINDS[i]
    if kind.failed then return false end
    if U.G(kind.host) and not kind.built and pm.enabled then return false end
  end
  return true
end

function PR:OnEnable()
  if U.GetActiveThemeStyle() ~= "modern" then return end
  pm.enabled = true
  if not pm.eventsInstalled then
    pm.eventsInstalled = true
    U.RegisterEvent("BAG_UPDATE", pm.RefreshAll)
    U.RegisterEvent("SKILL_LINES_CHANGED", pm.RefreshAll)
  end
  if pm.TryBuildAll() then
    pm.polling = true
    U.RegisterEvent("ADDON_LOADED", pm.TryBuildAll)
    U.RegisterUpdate("professions.modern.build", 1, pm.TryBuildAll)
  end
end
