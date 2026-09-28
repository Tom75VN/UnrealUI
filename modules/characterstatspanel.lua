-- unrealUI :: modules/characterstatspanel.lua
--
-- The Character window's integrated stats pane under the `character` Modern
-- WoW surface (user request, 2026-09-28): every stat modules/characterstats.lua
-- can read, listed down the right the way Retail's CharacterStatsPane does.
--
-- Entry point only. modules/modernwow.lua's mw.BuildCharacter calls
-- U.BuildCharacterStatsPanel once it has dressed the window, and falls back to
-- its stat boxes if this returns false, so a failure here leaves the old
-- layout rather than none.
--
-- Chrome: while the paper doll shows, the window is Retail's own expanded
-- CharacterFrame (U.ModernWowCharacterHousing, M.modernWow.characterWindow):
-- one metal border, title bar and streak across both halves, the paper doll
-- in its Inset and this pane in its InsetRight, the two inset borders being
-- the only divider. The pane itself is Retail's CharacterStatsPane: the class
-- emblem backdrop at its authored 197x355 (drawn by the housing), the
-- category bar and the row band (M.modernWow.characterStats). The list
-- scrolls like Forever's own stats ScrollBox: a virtual list of pooled rows
-- moved by the shared MinimalScrollBar (U.StyleModernWowScrollbar) and a
-- wheel catcher (U.CreateWheelCatcher), the recipe list's arrangement in
-- modules/professions.lua.
--
-- The list has two modes (SP.SetMode), chosen by the sidebar tabs above the
-- pane (modules/charactersidebar.lua): "stats", and "titles", Retail's
-- TitleManagerPane drawn in the same list with the same scrollbar and wheel.
-- The third tab, "equipment", hides the list for the Equipment Manager
-- (modules/characterequipment.lua), which draws its own in this pane.
--
-- An estimated value carries a "?" (user request): hovering it explains that
-- the client has no API for that stat and lists what the estimate is built
-- from. Both hovers are UnrealUI's own flat info tooltip (U.ShowInfoTooltip,
-- core/widgets.lua), not GameTooltip.
--
-- Native frames touched, all by global name and never walked:
--   * CharacterAttributesFrame is hidden while the paper doll shows -- its
--     stats are the ones this panel replaces. Nothing is unregistered.
--   * CharacterResistanceFrame is hidden the same way; the list has the
--     schools.
--   * CharacterModelFrame is fitted between the slot columns, from bounded
--     numbers read off CharacterHeadSlot, CharacterHandsSlot and
--     CharacterMainHandSlot (rules/unreal-ui.md: no addon frame anchors to a
--     native one). Its drag catcher is SetAllPoints on it and follows.
--
-- One top-level table (rules/unreal-ui.md, Lua local budget).

local U = UnrealUI
local M = U.media

local SP = {
  NAME = "UnrealUICharacterStatsPanel",
  SCROLL = "UnrealUICharacterStatsScrollBar",
  UPDATE = "characterstats.refresh",
  panel = nil,
  list = nil,
  scroll = nil,
  rows = {},
  entries = {},
  offset = 1,
  maxOffset = 1,
  modelSized = false,
  frame = nil,
  mode = "stats",
  flat = false,
}
U.CharacterStatsPanel = SP

function SP.Token()
  if SP.flat then return M.characterModern.stats end
  return M.modernWow.characterStats
end

function SP.Window()
  if SP.flat then return M.characterModern.window end
  return M.modernWow.characterWindow
end

function SP.SidebarToken()
  if SP.flat then return M.characterModern.sidebar end
  return M.modernWow.characterSidebar
end

function SP.Housing(expanded)
  if SP.flat and type(U.ModernCharacterHousing) == "function" then
    return U.ModernCharacterHousing(SP.frame, expanded)
  end
  if type(U.ModernWowCharacterHousing) == "function" then
    return U.ModernWowCharacterHousing(SP.frame, expanded)
  end
  return false
end

function SP.Dimension(frame, method)
  if not frame or not frame[method] then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

function SP.Font(parent, size, color, justify)
  local ok, text = pcall(parent.CreateFontString, parent, nil, "OVERLAY")
  if not ok or not text then return nil end
  U.SetStockFont(text, size, color)
  if justify then pcall(text.SetJustifyH, text, justify) end
  return text
end

function SP.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------
-- Both hovers are UnrealUI's own flat info tooltip (U.ShowInfoTooltip), never
-- GameTooltip (user request, 2026-09-28); it wraps long text itself.
--
-- A row's `tip` (modules/characterstats.lua): `tip.title` replaces the label
-- as the heading (the native sheet's "Strength 45 (40+5)"), then each entry
-- is { left, right } as a gold/white pair, { text, note = true } as the
-- native sheet's gold explanation, or { text } as a white line.
function SP.RowTooltip(row)
  local data = row.data
  if not data or not data.tip or type(U.ShowInfoTooltip) ~= "function" then return end
  local t = SP.Token()
  local lines = { { data.tip.title or data.label, t.titleColor } }
  local i
  for i = 1, table.getn(data.tip) do
    local line = data.tip[i]
    if line[2] then
      table.insert(lines, { line[1], t.labelColor, right = line[2],
                            rightColor = M.color.text })
    elseif line.note then
      table.insert(lines, { line[1], t.labelColor })
    else
      table.insert(lines, { line[1], M.color.text })
    end
  end
  U.ShowInfoTooltip(row, lines)
end

function SP.EstimateTooltip(mark)
  local data = mark.row and mark.row.data
  if not data or not data.estimate or type(U.ShowInfoTooltip) ~= "function" then
    return
  end
  local lines = { { U.L("CHARSTATS_EST_TITLE"), SP.Token().labelColor } }
  table.insert(lines, { U.L("CHARSTATS_EST_BODY"), M.color.textDim })
  local i
  for i = 1, table.getn(data.estimate) do
    table.insert(lines, { data.estimate[i], M.color.text })
  end
  U.ShowInfoTooltip(mark, lines)
end

function SP.HideTooltip()
  if type(U.HideInfoTooltip) == "function" then U.HideInfoTooltip() end
end

-- ---------------------------------------------------------------------------
-- Rows
--
-- One pooled frame draws either a category bar or a stat row; the entry it is
-- given decides which pieces show.
-- ---------------------------------------------------------------------------
function SP.BuildRow(index)
  local t = SP.Token()
  local ok, row = pcall(CreateFrame, "Frame", nil, SP.list)
  if not ok or not row then return nil end
  pcall(row.SetWidth, row, SP.rowWidth)
  pcall(row.SetHeight, row, t.rowHeight)
  pcall(row.SetFrameLevel, row, SP.Dimension(SP.list, "GetFrameLevel") + 2)
  pcall(row.EnableMouse, row, true)

  -- The row band runs from the pane's left border line (user requests,
  -- 2026-09-28): back over the list's left inset, then towards the right
  -- border, stopping `line.rightInset` short of it so it ends before the
  -- scrollbar. ARTWORK for the same reason as the category bar below, which
  -- never shows with it.
  local band = row:CreateTexture(nil, "ARTWORK")
  band:SetTexture(SP.flat and M.texture.plain or t.texture.line)
  band:SetWidth(SP.rowWidth + t.list.left + t.scroll.column + t.list.right -
                t.line.rightInset)
  band:SetHeight(t.line.height)
  band:SetPoint("LEFT", row, "LEFT", -t.list.left + t.line.x, 0)
  pcall(band.SetAlpha, band, t.line.alpha)
  if SP.flat then U.SetColor(band, 1, 1, 1, t.line.alpha) end
  row.band = band

  -- The category bar reaches back over the list's left inset to the pane's
  -- edge, the inner line of the stats inset's border (user request,
  -- 2026-09-28), and on the right up to the scrollbar's left edge, which
  -- sits `scroll.x` past the row's; its height is unchanged, so the art
  -- widens by `list.left` + `scroll.x`. ARTWORK, not BACKGROUND: it draws
  -- outside its row, and the housing's BACKGROUND rock was cut at its frame's
  -- edge in game while ARTWORK past the edge drew (mw.SizeHousingChrome). The
  -- title is OVERLAY, still above it, and bar and band never show together.
  -- `category.right` then carries it further right (user request, same day).
  local bar = row:CreateTexture(nil, "ARTWORK")
  bar:SetTexture(SP.flat and M.texture.plain or t.texture.category)
  bar:SetWidth(SP.rowWidth + t.list.left + t.scroll.x + t.category.right)
  bar:SetHeight(SP.flat and t.categoryHeight or
                SP.rowWidth * t.category.height / t.category.width)
  bar:SetPoint("RIGHT", row, "RIGHT", t.scroll.x + t.category.right, 0)
  if SP.flat then U.SetColor(bar, M.Unpack(t.categoryColor)) end
  row.bar = bar

  row.title = SP.Font(row, t.font.title, t.categoryTextColor or t.titleColor,
                      "CENTER")
  if row.title then row.title:SetPoint("CENTER", bar, "CENTER", 0, t.titleY) end
  row.label = SP.Font(row, t.font.label, t.labelColor, "LEFT")
  if row.label then row.label:SetPoint("LEFT", row, "LEFT", t.labelX, t.textY) end
  row.value = SP.Font(row, t.font.value, M.color.text, "RIGHT")

  local okMark, mark = pcall(CreateFrame, "Button", nil, row)
  if okMark and mark then
    pcall(mark.SetWidth, mark, t.mark.hit)
    pcall(mark.SetHeight, mark, t.rowHeight)
    pcall(mark.SetPoint, mark, "RIGHT", row, "RIGHT", t.valueX + (t.mark.hit - t.mark.width) / 2, 0)
    pcall(mark.SetFrameLevel, mark, SP.Dimension(row, "GetFrameLevel") + 1)
    pcall(mark.EnableMouse, mark, true)
    mark.text = SP.Font(mark, t.font.mark, t.markColor, "CENTER")
    if mark.text then
      mark.text:SetText("?")
      mark.text:SetPoint("CENTER", mark, "CENTER", 0, t.valueY)
    end
    mark.row = row
    mark:SetScript("OnEnter", function()
      if mark.text then pcall(mark.text.SetTextColor, mark.text, M.Unpack(t.markHoverColor)) end
      SP.EstimateTooltip(mark)
    end)
    mark:SetScript("OnLeave", function()
      if mark.text then pcall(mark.text.SetTextColor, mark.text, M.Unpack(t.markColor)) end
      SP.HideTooltip()
    end)
    row.mark = mark
  end

  -- The Titles pane's pieces (M.modernWow.characterSidebar.titles): Retail's
  -- even-row stripe, a hover wash, and the check on the current title --
  -- the game settings tick, or no mark when it is unavailable.
  local s = SP.SidebarToken().titles
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetTexture(M.texture.plain)
  row.stripe:SetAllPoints(row)
  U.SetColor(row.stripe, M.Unpack(s.stripe))
  row.hover = row:CreateTexture(nil, "BORDER")
  row.hover:SetTexture(M.texture.plain)
  row.hover:SetAllPoints(row)
  U.SetColor(row.hover, M.Unpack(s.hover))
  row.hover:Hide()
  if SP.flat then
    row.tick = CreateFrame("Frame", nil, row)
    U.CreateBackdrop(row.tick, {
      background = M.color.background, border = M.color.accent,
    })
    U.SetCheckboxIndicator(row.tick, true)
    pcall(row.tick.EnableMouse, row.tick, false)
    row.tick.missing = false
  else
    row.tick = row:CreateTexture(nil, "ARTWORK")
  end
  row.tick:SetWidth(s.check)
  row.tick:SetHeight(s.check)
  row.tick:SetPoint("LEFT", row, "LEFT", s.checkX, 0)
  if not SP.flat then
    row.tick.missing = type(U.SetGameSettingsTick) ~= "function" or
                       not U.SetGameSettingsTick(row.tick)
  end
  row.tick:Hide()

  row:SetScript("OnEnter", function()
    if row.titleId then SP.SetShown(row.hover, true) else SP.RowTooltip(row) end
  end)
  row:SetScript("OnLeave", function()
    SP.SetShown(row.hover, false)
    SP.HideTooltip()
  end)
  row:SetScript("OnMouseUp", function()
    if row.titleId and U.CharacterSidebar then
      U.CharacterSidebar.SetTitle(row.titleId)
    end
  end)
  SP.rows[index] = row
  return row
end

-- A stat row's label sits `labelX` in with no right edge; a title's runs from
-- past the check to `textRight` short of the row, in Retail's smaller font.
-- Re-anchored only when a pooled row changes kind.
function SP.StyleLabel(row, title)
  local kind = title and "title" or "stat"
  if not row.label or row.labelKind == kind then return end
  row.labelKind = kind
  local t = SP.Token()
  local s = SP.SidebarToken().titles
  pcall(function()
    row.label:ClearAllPoints()
    if title then
      U.SetStockFont(row.label, s.font, s.color)
      row.label:SetPoint("LEFT", row, "LEFT", s.checkX + s.check + s.textGap, 0)
      row.label:SetPoint("RIGHT", row, "RIGHT", -s.textRight, 0)
    else
      U.SetStockFont(row.label, t.font.label, t.labelColor)
      row.label:SetPoint("LEFT", row, "LEFT", t.labelX, t.textY)
    end
  end)
end

function SP.FillTitle(row, entry)
  row.data = nil
  pcall(row.SetHeight, row, SP.SidebarToken().titles.rowHeight)
  SP.SetShown(row.bar, false)
  SP.SetShown(row.title, false)
  SP.SetShown(row.value, false)
  SP.SetShown(row.band, false)
  SP.SetShown(row.mark, false)
  SP.SetShown(row.label, true)
  if row.label then pcall(row.label.SetText, row.label, entry.name) end
end

function SP.FillRow(row, entry)
  local t = SP.Token()
  local titleRow = entry.kind == "title"
  row.titleId = titleRow and entry.id or nil
  SP.SetShown(row.stripe, titleRow and entry.stripe)
  SP.SetShown(row.tick, titleRow and entry.selected and not row.tick.missing)
  if not titleRow then SP.SetShown(row.hover, false) end
  SP.StyleLabel(row, titleRow)
  if titleRow then
    SP.FillTitle(row, entry)
    return
  end

  local category = entry.kind == "category"
  row.data = (not category) and entry.row or nil
  pcall(row.SetHeight, row, category and t.categoryHeight or t.rowHeight)
  SP.SetShown(row.bar, category)
  SP.SetShown(row.title, category)
  SP.SetShown(row.label, not category)
  SP.SetShown(row.value, not category)
  SP.SetShown(row.band, (not category) and entry.band)
  if category then
    -- Re-asserted on every fill: rows are pooled, and a category title is
    -- always white (user request, 2026-09-28), whatever the row showed before.
    if row.title then
      pcall(row.title.SetText, row.title, entry.title)
      pcall(row.title.SetTextColor, row.title,
            M.Unpack(t.categoryTextColor or t.titleColor))
    end
    SP.SetShown(row.mark, false)
    return
  end

  local data = entry.row
  local estimated = data.estimate and true or false
  if row.label then
    pcall(row.label.SetText, row.label, data.label)
    pcall(row.label.SetTextColor, row.label, M.Unpack(t.labelColor))
  end
  if row.value then
    pcall(row.value.SetText, row.value, data.value)
    pcall(row.value.SetTextColor, row.value, M.Unpack(data.color or M.color.text))
    local right = t.valueX
    if estimated then right = right - t.mark.width - t.mark.gap end
    pcall(function()
      row.value:ClearAllPoints()
      row.value:SetPoint("RIGHT", row, "RIGHT", right, t.valueY)
    end)
  end
  SP.SetShown(row.mark, estimated)
end

-- ---------------------------------------------------------------------------
-- Virtual list
-- ---------------------------------------------------------------------------
function SP.EntryHeight(entry)
  local t = SP.Token()
  if entry.kind == "category" then return t.categoryHeight end
  if entry.kind == "title" then
    return SP.SidebarToken().titles.rowHeight
  end
  return t.rowHeight
end

-- The last first-entry that still fills the list to its bottom.
function SP.MaxOffset()
  local used = 0
  local i
  for i = table.getn(SP.entries), 1, -1 do
    used = used + SP.EntryHeight(SP.entries[i])
    if used > SP.capacity then return math.min(i + 1, table.getn(SP.entries)) end
  end
  return 1
end

function SP.Layout()
  SP.maxOffset = SP.MaxOffset()
  SP.offset = math.max(1, math.min(SP.offset, SP.maxOffset))
  local y, used, i = 0, 0, SP.offset
  while i <= table.getn(SP.entries) do
    local entry = SP.entries[i]
    local height = SP.EntryHeight(entry)
    if y + height > SP.capacity then break end
    used = used + 1
    local row = SP.rows[used] or SP.BuildRow(used)
    if row then
      pcall(function()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SP.list, "TOPLEFT", 0, -y)
      end)
      SP.FillRow(row, entry)
      pcall(row.Show, row)
    end
    y = y + height
    i = i + 1
  end
  for i = used + 1, table.getn(SP.rows) do
    SP.rows[i].data = nil
    pcall(SP.rows[i].Hide, SP.rows[i])
  end
  SP.visibleCount = used
  SP.LayoutScroll()
end

function SP.LayoutScroll()
  local scroll = SP.scroll
  if not scroll then return end
  local scrollable = SP.maxOffset > 1
  SP.SetShown(scroll.bar, scrollable)
  SP.syncing = true
  pcall(scroll.bar.SetMinMaxValues, scroll.bar, 1, SP.maxOffset)
  pcall(scroll.bar.SetValue, scroll.bar, SP.offset)
  SP.syncing = false
  if not scrollable then return end
  if scroll.up then
    if SP.offset > 1 then pcall(scroll.up.Enable, scroll.up)
    else pcall(scroll.up.Disable, scroll.up) end
  end
  if scroll.down then
    if SP.offset < SP.maxOffset then pcall(scroll.down.Enable, scroll.down)
    else pcall(scroll.down.Disable, scroll.down) end
  end
  if not SP.flat and type(U.SetModernWowScrollbarProportion) == "function" then
    U.SetModernWowScrollbarProportion(scroll.bar, SP.visibleCount or 0,
                                      table.getn(SP.entries))
  end
end

function SP.ReadScroll()
  local bar = SP.scroll and SP.scroll.bar
  if not bar or SP.syncing then return end
  local ok, value = pcall(bar.GetValue, bar)
  value = ok and tonumber(value) or nil
  if not value then return end
  value = math.max(1, math.min(SP.maxOffset, math.floor(value + 0.5)))
  if value == SP.offset then return end
  SP.offset = value
  SP.Layout()
end

function SP.Wheel(direction)
  if SP.maxOffset <= 1 then return end
  local target = math.max(1, math.min(SP.maxOffset, SP.offset - direction))
  if target == SP.offset then return end
  SP.offset = target
  SP.Layout()
end

function SP.BuildScroll(listHeight)
  local t = SP.Token()
  local height = listHeight - t.scroll.arrowPad * 2
  if height < 1 then return end
  local ok, bar = pcall(CreateFrame, "Slider", SP.SCROLL, SP.list,
                        "UIPanelScrollBarTemplate")
  if not ok or not bar then return end
  -- The template's own OnValueChanged scrolls its parent as a ScrollFrame;
  -- this list's parent is a plain Frame (modules/professions.lua does the same).
  pcall(bar.SetScript, bar, "OnValueChanged", nil)
  pcall(function()
    bar:SetFrameLevel(SP.Dimension(SP.list, "GetFrameLevel") + 3)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(t.scroll.column)
    bar:SetHeight(height)
    bar:SetPoint("TOPRIGHT", SP.list, "TOPRIGHT", t.scroll.x, -t.scroll.arrowPad)
    bar:SetMinMaxValues(1, 1)
    bar:SetValueStep(1)
    bar:SetValue(1)
  end)
  local up = U.G(SP.SCROLL .. "ScrollUpButton")
  local down = U.G(SP.SCROLL .. "ScrollDownButton")
  if up then up:SetScript("OnClick", function() SP.Wheel(1) end) end
  if down then down:SetScript("OnClick", function() SP.Wheel(-1) end) end
  SP.scroll = { bar = bar, up = up, down = down }
  if SP.flat and type(U.StyleStockScrollbar) == "function" then
    U.StyleStockScrollbar(bar)
  elseif type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, { onChange = SP.ReadScroll })
  end
  bar:SetScript("OnValueChanged", SP.ReadScroll)
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function SP.Refresh()
  if not SP.list or SP.mode == "equipment" then return end
  if SP.mode == "titles" then
    local sidebar = U.CharacterSidebar
    SP.entries = sidebar and sidebar.TitleEntries() or {}
    SP.Layout()
    return
  end
  local stats = U.CharacterStats
  if not stats then return end
  local ok, sections = pcall(stats.Collect)
  if not ok or type(sections) ~= "table" then
    U.Debug("characterstats panel: " .. tostring(sections))
    return
  end
  local entries = {}
  local i, j
  for i = 1, table.getn(sections) do
    table.insert(entries, { kind = "category", title = sections[i].title })
    for j = 1, table.getn(sections[i].rows) do
      table.insert(entries, { kind = "row", row = sections[i].rows[j],
                              band = math.mod(j, 2) == 0 })
    end
  end
  SP.entries = entries
  SP.Layout()
end

-- The timed refresh holds while GameTooltip is up. Every refresh re-reads the
-- melee and ranged crit through modules/characterstats.lua's private
-- GameTooltipTemplate scanner, and populating a second template tooltip while
-- the player hovers a gear slot made that slot's tooltip blink between the
-- client's stock chrome and UnrealUI's flat one (user report, 2026-09-28;
-- knowledge: tooltip.addon_replacement_cannot_use_gametooltiptemplate). The
-- panel keeps its last values and catches up on the first tick after the
-- tooltip hides. OnShow still refreshes unconditionally.
function SP.Tick()
  local tip = SP.mode == "stats" and U.G("GameTooltip")
  if tip then
    local ok, shown = pcall(tip.IsShown, tip)
    if ok and shown then return end
  end
  SP.Refresh()
end

function SP.OnShow()
  if U.CharacterStats then U.CharacterStats.Invalidate() end
  SP.Refresh()
  U.RegisterUpdate(SP.UPDATE, SP.Token().refresh, SP.Tick)
end

function SP.OnHide()
  U.UnregisterUpdate(SP.UPDATE)
  SP.HideTooltip()
end

-- The list's mode, from the sidebar tab shown: "stats", "titles" or
-- "equipment". The title list re-reads on the same timed refresh, so a title
-- set by a click shows its check once the client reports it. "equipment"
-- hides the list and shows the Equipment Manager in its place
-- (modules/characterequipment.lua); re-applied on every call, since the
-- sidebar calls it again each time the paper doll opens.
function SP.SetMode(mode)
  if SP.mode ~= mode then
    SP.mode = mode
    SP.offset = 1
    SP.HideTooltip()
  end
  local manager = U.CharacterEquipmentPane
  local equipment = mode == "equipment" and manager and
                    manager.Activate(SP.pane, SP.panel, SP.frame)
  if manager and not equipment then manager.Deactivate() end
  SP.SetShown(SP.list, not equipment)
  SP.Refresh()
end

-- The housing moves the header's name, close button, title dropdown and
-- level line with it (modules/modernwow.lua); the sidebar tabs pick the
-- list's mode before the panel shows.
function SP.SetExpanded(expanded)
  if not SP.frame or not SP.panel then return end
  local placed = SP.Housing(expanded)
  if U.CharacterSidebar then U.CharacterSidebar.SetExpanded(placed and expanded) end
  if not (placed and expanded) and U.CharacterEquipmentPane then
    U.CharacterEquipmentPane.Deactivate()
  end
  SP.SetShown(SP.panel, placed and expanded)
end

-- CharacterStatsPane inside the housing's InsetRight, as offsets from
-- CharacterFrame's top-left (y downwards) and a size: 197x355, the backdrop's
-- own, with Retail's numbers.
function SP.PaneRect()
  local w = SP.Window()
  if SP.flat then
    local box = w.pane
    local left = w.left + w.width + w.gap
    local top = w.top + box.top
    local right = w.left + w.expandedWidth - box.right
    local bottom = w.top + w.height - box.bottom
    return left, top, right - left, bottom - top
  end
  local p = SP.Token().pane
  local left = w.left + w.width - w.inset.right + w.insetRight.gap + p.left
  local top = w.top + w.inset.top + p.top
  local right = w.left + w.expandedWidth - w.insetRight.right - p.right
  local bottom = w.top + w.height - w.insetRight.bottom - p.bottom
  return left, top, right - left, bottom - top
end

-- ---------------------------------------------------------------------------
-- The paper doll underneath
-- ---------------------------------------------------------------------------
-- The 3D preview fills the paper doll's inner space (user request,
-- 2026-09-28): between the left and right slot columns, from the head slot's
-- top down to the weapon row, `gap` short of each. Measured as offsets from
-- CharacterFrame's top-left while the page shows, and kept once a measurement
-- succeeds; the model is re-anchored to CharacterFrame, never to a slot.
-- Unreadable edges only grow the height to `fallbackHeight`, in place.
function SP.FitModel()
  if SP.modelSized then return end
  local t = SP.Token().model
  local model = U.G("CharacterModelFrame")
  if not model or not SP.frame then return end
  local frameLeft = SP.Dimension(SP.frame, "GetLeft")
  local frameTop = SP.Dimension(SP.frame, "GetTop")
  local head = U.G("CharacterHeadSlot")
  local left = SP.Dimension(head, "GetRight")
  local top = SP.Dimension(head, "GetTop")
  local right = SP.Dimension(U.G("CharacterHandsSlot"), "GetLeft")
  local bottom = SP.Dimension(U.G("CharacterMainHandSlot"), "GetTop")
  local width = right - left - 2 * t.gap
  local height = top - bottom - t.gap
  if frameLeft <= 0 or frameTop <= 0 or left <= 0 or top <= 0 or
     right <= 0 or bottom <= 0 or width <= 0 or height <= 0 then
    if t.fallbackHeight > SP.Dimension(model, "GetHeight") then
      pcall(model.SetHeight, model, t.fallbackHeight)
    end
    return
  end
  -- The bottom edge moves down `y`, which lowers the render (user requests,
  -- 2026-09-28). The top stays at the head slot's: the render is clipped at
  -- the frame's top edge, and moving it down cut off the head (user
  -- screenshot, same day). Only the addon's drag catcher is pulled back up
  -- by `y` at the bottom, so it never covers the weapon slots.
  -- `shift` then moves the whole frame down at that height (user request,
  -- same day); the catcher's bottom is pulled up by it too. `grow` raises
  -- only the top edge, leaving the bottom -- and so the render -- in place.
  pcall(function()
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", SP.frame, "TOPLEFT",
                   left - frameLeft + t.gap, top - frameTop - t.shift + t.grow)
    model:SetWidth(width)
    model:SetHeight(height + t.y + t.grow)
  end)
  local catcher = model.uuiModelRotateCatcher
  if catcher then
    pcall(function()
      catcher:ClearAllPoints()
      catcher:SetPoint("TOPLEFT", model, "TOPLEFT", 0, 0)
      catcher:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT", 0, t.y + t.shift)
    end)
  end
  SP.modelSized = true
end

-- The character inside the preview is drawn at `scale` (user request,
-- 2026-09-28: 80% larger): resizing the frame alone left it the same size on
-- this client, where a Model draws independently of its frame's bounds
-- (knowledge: rendering.model_m2_spell_fx_in_ui). Model:SetModelScale is
-- DOCUMENTED_NOT_RUNTIME_VERIFIED here, and was one call in the original
-- portrait sequence that crashed (unitframes.portrait_model_crash, failing
-- call not isolated), so it is its only use. Re-applied a tick after the page
-- shows and after UNIT_MODEL_CHANGED, since the client's own SetUnit /
-- RefreshUnit may reset it.
-- Model:SetPosition is not used: SetPosition(0, 0, -0.4) drew an opaque
-- white cell behind the character and did not lower it (user screenshot,
-- 2026-09-28). The head is kept clear of the header by `scale` alone.
function SP.ScaleModel()
  local model = U.G("CharacterModelFrame")
  if not model or type(model.SetModelScale) ~= "function" then return end
  pcall(model.SetModelScale, model, SP.Token().model.scale)
end

function SP.QueueScaleModel()
  U.DeferOnce("characterstats.model-scale", SP.ScaleModel)
end

-- The resistance column over the model's right edge goes too (user request,
-- 2026-09-28): the list carries every school. Hidden, never unregistered.
function SP.ApplyPaperDoll()
  local attributes = U.G("CharacterAttributesFrame")
  if attributes then pcall(attributes.Hide, attributes) end
  local resistances = U.G("CharacterResistanceFrame")
  if resistances then pcall(resistances.Hide, resistances) end
  SP.FitModel()
  SP.QueueScaleModel()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function SP.Build(frame)
  SP.flat = type(U.GetActiveThemeStyle) == "function" and
            U.GetActiveThemeStyle() == "modern"
  local t = SP.Token()
  local w = SP.Window()
  -- Builds the Retail housing now, hidden, so a failure falls back to the
  -- stat boxes before anything is hidden.
  SP.frame = frame
  if not SP.Housing(false) then
    error(SP.flat and "flat Character housing unavailable" or
          "Retail Character housing unavailable")
  end
  local paneLeft, paneTop, paneWidth, paneHeight = SP.PaneRect()

  -- Takes the mouse over the housing past the native window's own hit rect,
  -- from the paper doll's inset edge, so a click there does not fall through
  -- to the world. At the window's own level: every native child of the
  -- window (the close button, the title dropdown) stays above it.
  local catchLeft = SP.flat and (w.left + w.width) or
                    (w.left + w.width - w.inset.right)
  local panel = CreateFrame("Frame", SP.NAME, frame)
  panel:SetWidth(w.left + w.expandedWidth - catchLeft)
  panel:SetHeight(w.height)
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", catchLeft, -w.top)
  pcall(panel.SetFrameLevel, panel, SP.Dimension(frame, "GetFrameLevel"))
  pcall(panel.EnableMouse, panel, true)

  local pane = CreateFrame("Frame", nil, panel)
  pane:SetWidth(paneWidth)
  pane:SetHeight(paneHeight)
  pane:SetPoint("TOPLEFT", panel, "TOPLEFT", paneLeft - catchLeft,
                -(paneTop - w.top))
  pcall(pane.SetFrameLevel, pane, SP.Dimension(panel, "GetFrameLevel") + 1)
  if SP.flat then
    U.CreateBackdrop(pane, {
      background = { 0.025, 0.025, 0.025, 0.92 },
      border = M.color.border,
    })
  end
  SP.pane = pane
  -- The class background under the list is the housing's (it draws on the
  -- window's chrome, below every frame of this pane).

  local listWidth = paneWidth - t.list.left - t.list.right
  local listHeight = paneHeight - t.list.top - t.list.bottom
  local list = CreateFrame("Frame", nil, pane)
  list:SetWidth(listWidth)
  list:SetHeight(listHeight)
  list:SetPoint("TOPLEFT", pane, "TOPLEFT", t.list.left, -t.list.top)
  pcall(list.SetFrameLevel, list, SP.Dimension(pane, "GetFrameLevel") + 1)
  SP.list = list
  SP.capacity = listHeight
  SP.rowWidth = listWidth - t.scroll.column

  -- Built before the rows so it stays underneath them.
  if type(U.CreateWheelCatcher) == "function" then
    U.CreateWheelCatcher(list, SP.Wheel)
  end
  SP.BuildScroll(listHeight)

  panel:SetScript("OnShow", SP.OnShow)
  panel:SetScript("OnHide", SP.OnHide)
  panel:Hide()
  SP.panel = panel
  SP.frame = frame

  -- Retail's sidebar tabs over InsetRight, whose edges and top are given from
  -- the panel's top-left (which is the housing's top). A failure leaves the
  -- pane on its stats and the title dropdown where it was.
  if type(U.BuildCharacterSidebar) == "function" then
    if SP.flat then
      U.BuildCharacterSidebar(panel, paneLeft - catchLeft,
                              paneLeft - catchLeft + paneWidth,
                              paneTop - w.top)
    else
      U.BuildCharacterSidebar(panel, w.insetRight.gap,
                              w.left + w.expandedWidth - w.insetRight.right -
                              catchLeft, w.inset.top)
    end
  end

  -- The stats belong to the paper doll page, as the stat boxes did: the panel
  -- follows PaperDollFrame's show and hide.
  local paperDoll = U.G("PaperDollFrame")
  if not paperDoll then error("PaperDollFrame unavailable") end
  U.PostHookScript(paperDoll, "OnShow", function()
    SP.ApplyPaperDoll()
    SP.SetExpanded(true)
  end)
  U.PostHookScript(paperDoll, "OnHide", function() SP.SetExpanded(false) end)
  U.RegisterEvent("UNIT_MODEL_CHANGED", function()
    local visible, open = pcall(paperDoll.IsShown, paperDoll)
    if visible and open then SP.QueueScaleModel() end
  end)
  local ok, shown = pcall(paperDoll.IsShown, paperDoll)
  if ok and shown then
    SP.ApplyPaperDoll()
    SP.SetExpanded(true)
  else
    SP.SetExpanded(false)
  end
  return true
end

function U.BuildCharacterStatsPanel(frame)
  if SP.panel then return true end
  if not frame or not U.CharacterStats then return false end
  local ok, err = pcall(SP.Build, frame)
  if not ok then
    U.Error("character stats panel: " .. tostring(err))
    if SP.panel then pcall(SP.panel.Hide, SP.panel) end
    SP.panel = nil
    return false
  end
  return true
end
