-- unrealUI :: modules/characterequipment.lua
--
-- The Equipment Manager pane behind the paper doll's third sidebar tab (user
-- request, 2026-09-28): Retail's PaperDollEquipmentManagerPane, its
-- GearSetButtonTemplate rows and GearManagerPopupFrame (Blizzard_UIPanels_Game
-- /Mainline/PaperDollFrame.xml/.lua), in the stats pane's place. What Retail
-- does, and does here:
--   * Equip / Save at the top, both off unless a set is selected and not
--     already worn (PaperDollEquipmentManagerPane_Update); Save asks first.
--   * One row per set: icon, name (red while an item is missing), the check
--     when worn; hovering shows Delete and Edit. A click selects the set and
--     marks the slots it ignores; a double click equips it. The last row,
--     "New Set", opens the popup with the shirt and tabard ignored.
--   * The popup names the set and picks its icon; a name already taken asks
--     to overwrite (new) or is refused (rename).
-- Retail's spec assignment and drag-to-action-bar have no client support and
-- are left out.
--
-- Sets and swaps: modules/equipmentsets.lua. Slot arrows and flyout:
-- modules/characterflyout.lua. Geometry: M.modernWow.equipmentManager.
--
-- Entry point only: modules/characterstatspanel.lua activates it in its
-- pane's place when the sidebar picks the tab. One top-level table.

local U = UnrealUI
local M = U.media

local EP = {
  SCROLL = "UnrealUIEquipmentManagerScrollBar",
  NAME_FIELD = "UnrealUIEquipmentSetName",
  ICON_SCROLL = "UnrealUIEquipmentSetIconScrollBar",
  REFRESH = "characterequipment.refresh",
  HOVER = "characterequipment.hover",
  frame = nil,
  list = nil,
  scroll = nil,
  rows = {},
  entries = {},
  offset = 1,
  maxOffset = 1,
  selected = nil,
  popup = nil,
  active = false,
  flat = false,
  lastSet = nil,
  lastTime = 0,
}
U.CharacterEquipmentPane = EP

function EP.Token()
  if EP.flat then return M.characterModern.equipment end
  return M.modernWow.equipmentManager
end

function EP.StatsToken()
  if EP.flat then return M.characterModern.stats end
  return M.modernWow.characterStats
end

function EP.Sets()
  return U.EquipmentSets
end

function EP.Dimension(frame, method)
  if not frame or not frame[method] then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

function EP.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

function EP.Now()
  local fn = U.G("GetTime")
  if type(fn) ~= "function" then return 0 end
  local ok, now = pcall(fn)
  return (ok and tonumber(now)) or 0
end

function EP.Tooltip(owner, lines)
  if type(U.ShowInfoTooltip) == "function" then U.ShowInfoTooltip(owner, lines) end
end

function EP.HideTooltip()
  if type(U.HideInfoTooltip) == "function" then U.HideInfoTooltip() end
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
-- The 128RedButton face on an owned Button, with its four states; the flat
-- shared button where that art is unavailable.
function EP.Button(parent, text, width, height, onClick)
  local button = CreateFrame("Button", nil, parent)
  pcall(button.EnableMouse, button, true)
  button:SetWidth(width)
  button:SetHeight(height)
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  button:SetScript("OnClick", function()
    if button.enabled ~= false then onClick() end
  end)
  button.enabled = true
  if not EP.flat and type(U.ModernWowRedButtonFace) == "function" and
     U.ModernWowRedButtonFace(button, height) then
    button.red = true
    button:SetScript("OnEnter", function()
      if button.enabled ~= false then U.ModernWowPaintRedButton(button, true) end
    end)
    button:SetScript("OnLeave", function() U.ModernWowPaintRedButton(button, false) end)
    U.ModernWowRedButtonInput(button)
    button.label = U.CreateLabel(button, { size = M.fontSize.normal,
                                           inherits = "GameFontNormal" })
    if button.label then
      U.CenterButtonLabel(button.label, button)
      button.label:SetText(text)
    end
    return button
  end
  button:Hide()
  local flat = U.CreateButton(parent, { text = text, width = width, height = height })
  flat:SetScript("OnEnter", function()
    U.SetBorderColor(flat, M.Unpack(flat.enabled ~= false and
                     M.color.accentDim or M.color.border))
  end)
  flat:SetScript("OnLeave", function()
    U.SetBorderColor(flat, M.Unpack(M.color.border))
  end)
  flat:SetScript("OnClick", function()
    if flat.enabled ~= false then onClick() end
  end)
  flat.enabled = true
  return flat
end

function EP.SetEnabled(button, enabled)
  if not button then return end
  button.enabled = enabled and true or false
  if button.red then
    U.ModernWowSetRedButtonDisabled(button, not enabled)
    U.ModernWowPaintRedButton(button, false)
  end
  if button.label then
    pcall(button.label.SetTextColor, button.label,
          M.Unpack(enabled and M.color.text or M.color.textDim))
  end
  if EP.flat and not enabled then
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end
end

-- GearSetButtonTemplate's DeleteButton / EditButton: the art at half alpha,
-- full on hover, pressed one unit down-right.
function EP.SmallButton(row, art, size, tipKey, onClick)
  local t = EP.Token().row
  if EP.flat then
    local glyph = tipKey == "EQUIPSET_DELETE" and "X" or "E"
    local button = U.CreateButton(row, {
      text = glyph, width = size, height = size,
      size = M.fontSize.tiny,
    })
    button:SetScript("OnEnter", function()
      row.childHover = true
      EP.QueueHover()
      EP.Tooltip(button, { { U.L(tipKey), M.color.text } })
    end)
    button:SetScript("OnLeave", function()
      row.childHover = false
      EP.QueueHover()
      EP.HideTooltip()
    end)
    button:SetScript("OnClick", function()
      if row.entry and row.entry.set then onClick(row.entry.set) end
    end)
    button:Hide()
    return button
  end
  local button = CreateFrame("Button", nil, row)
  pcall(button.EnableMouse, button, true)
  button:SetWidth(size)
  button:SetHeight(size)
  local texture = button:CreateTexture(nil, "ARTWORK")
  texture:SetTexture(art)
  texture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  texture:SetWidth(size)
  texture:SetHeight(size)
  texture:SetAlpha(t.buttonAlpha)
  button.texture = texture
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  button:SetScript("OnEnter", function()
    texture:SetAlpha(1)
    row.childHover = true
    EP.QueueHover()
    EP.Tooltip(button, { { U.L(tipKey), M.color.text } })
  end)
  button:SetScript("OnLeave", function()
    texture:SetAlpha(t.buttonAlpha)
    row.childHover = false
    EP.QueueHover()
    EP.HideTooltip()
  end)
  button:SetScript("OnMouseDown", function()
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  end)
  button:SetScript("OnMouseUp", function()
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  end)
  button:SetScript("OnClick", function()
    if row.entry and row.entry.set then onClick(row.entry.set) end
  end)
  button:Hide()
  return button
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
function EP.Wash(row, layer, color)
  local texture = row:CreateTexture(nil, layer)
  texture:SetTexture(M.texture.plain)
  texture:SetAllPoints(row)
  U.SetColor(texture, M.Unpack(color))
  texture:Hide()
  return texture
end

function EP.BuildRow(index)
  local t = EP.Token()
  local r = t.row
  local row = CreateFrame("Button", nil, EP.list)
  pcall(row.EnableMouse, row, true)
  row:SetWidth(EP.rowWidth)
  row:SetHeight(r.height)
  pcall(row.SetFrameLevel, row, EP.Dimension(EP.list, "GetFrameLevel") + 2)
  pcall(row.RegisterForClicks, row, "LeftButtonUp")

  row.stripe = EP.Wash(row, "BACKGROUND", t.stripe)
  row.selectedWash = EP.Wash(row, "BORDER", t.selected)
  row.hoverWash = EP.Wash(row, "BORDER", t.hover)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.plus = U.CreateLabel(row, {
    size = M.fontSize.large, color = M.color.accent,
    inherits = "GameFontNormal", justify = "CENTER",
  })
  if row.plus then row.plus:SetText("+") row.plus:Hide() end
  row.label = U.CreateLabel(row, {
    size = r.font, inherits = "GameFontNormal", justify = "LEFT",
    width = EP.rowWidth - r.textX - r.textRight, height = r.height - 6,
  })
  if row.label then row.label:SetPoint("LEFT", row, "LEFT", r.textX, 0) end

  if EP.flat then
    row.tick = CreateFrame("Frame", nil, row)
    -- The shared checked square: outline, then the accent mark inside it.
    U.CreateBackdrop(row.tick, {
      background = M.color.background, border = M.color.accent,
    })
    U.SetCheckboxIndicator(row.tick, true)
    pcall(row.tick.EnableMouse, row.tick, false)
    row.tick.missing = false
  else
    row.tick = row:CreateTexture(nil, "ARTWORK")
  end
  row.tick:SetWidth(r.check)
  row.tick:SetHeight(r.check)
  if EP.flat then
    row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -r.checkRight, -r.checkTop)
  else
    row.tick:SetPoint("RIGHT", row, "RIGHT", -r.checkRight, 0)
  end
  if not EP.flat then
    row.tick.missing = type(U.SetGameSettingsTick) ~= "function" or
                       not U.SetGameSettingsTick(row.tick)
  end
  row.tick:Hide()

  row.delete = EP.SmallButton(row, t.texture.delete, r.delete, "EQUIPSET_DELETE",
                              EP.ConfirmDelete)
  row.delete:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -r.deleteInset, r.deleteInset)
  row.edit = EP.SmallButton(row, t.texture.edit, r.edit, "EQUIPSET_EDIT",
                            function(set) EP.ShowPopup("edit", set) end)
  row.edit:SetPoint("RIGHT", row.delete, "LEFT", -r.editGap, 0)
  pcall(row.delete.SetFrameLevel, row.delete, EP.Dimension(row, "GetFrameLevel") + 1)
  pcall(row.edit.SetFrameLevel, row.edit, EP.Dimension(row, "GetFrameLevel") + 1)

  row:SetScript("OnEnter", function()
    row.hovered = true
    EP.QueueHover()
    EP.RowTooltip(row)
  end)
  row:SetScript("OnLeave", function()
    row.hovered = false
    EP.QueueHover()
    EP.HideTooltip()
  end)
  row:SetScript("OnClick", function() EP.RowClick(row) end)
  EP.rows[index] = row
  return row
end

-- PaperDollEquipmentManagerPane_OnUpdate: the wash, Delete and Edit follow
-- the pointer over the row or its two buttons. Painted a tick later, so
-- moving from the row onto a button does not hide the button first.
function EP.PaintHover()
  local i
  for i = 1, table.getn(EP.rows) do
    local row = EP.rows[i]
    local over = (row.hovered or row.childHover) and row.entry ~= nil
    local set = over and row.entry.set
    EP.SetShown(row.hoverWash, over and not (set and set == EP.selected))
    EP.SetShown(row.delete, set and true or false)
    EP.SetShown(row.edit, set and true or false)
  end
end

function EP.QueueHover()
  U.DeferOnce(EP.HOVER, EP.PaintHover)
end

-- GameTooltip:SetEquipmentSet: the name, then how many of its items are
-- worn, in the bags, and missing.
function EP.RowTooltip(row)
  local set = row.entry and row.entry.set
  if not set then return end
  local t = EP.Token()
  local info = EP.Sets().Info(set)
  local lines = { { set.name, M.color.text } }
  if info.equipped > 0 then
    table.insert(lines, { U.L("EQUIPSET_TIP_EQUIPPED", info.equipped), t.nameColor })
  end
  if info.bags > 0 then
    table.insert(lines, { U.L("EQUIPSET_TIP_BAGS", info.bags), t.nameColor })
  end
  if info.missing > 0 then
    table.insert(lines, { U.L("EQUIPSET_TIP_MISSING", info.missing), t.missingColor })
  end
  EP.Tooltip(row, lines)
end

-- PaperDollEquipmentManagerPane_InitButton.
function EP.FillRow(row, entry, index)
  local t = EP.Token()
  local r = t.row
  row.entry = entry
  pcall(row.icon.ClearAllPoints, row.icon)
  if entry.newSet then
    row.icon:SetTexture(EP.flat and nil or t.texture.newSet)
    row.icon:SetWidth(r.plusIcon)
    row.icon:SetHeight(r.plusIcon)
    row.icon:SetPoint("LEFT", row, "LEFT", r.plusX, 0)
    -- The glyph stands in for the art only on the flat path; the Modern WoW
    -- newSet texture already draws its own plus.
    if row.plus then
      row.plus:ClearAllPoints()
      row.plus:SetPoint("CENTER", row.icon, "CENTER", 0, -1)
      EP.SetShown(row.plus, EP.flat and true or false)
    end
    if row.label then
      row.label:SetText(U.L("EQUIPSET_NEW"))
      pcall(row.label.SetTextColor, row.label, M.Unpack(t.newColor))
    end
    EP.SetShown(row.tick, false)
    EP.SetShown(row.selectedWash, false)
    EP.SetShown(row.stripe, false)
    return
  end
  local set = entry.set
  if row.plus then row.plus:Hide() end
  local info = EP.Sets().Info(set)
  row.icon:SetTexture(EP.Sets().SetIcon(set))
  row.icon:SetWidth(r.icon)
  row.icon:SetHeight(r.icon)
  row.icon:SetPoint("LEFT", row, "LEFT", r.iconX, 0)
  if row.label then
    row.label:SetText(set.name)
    pcall(row.label.SetTextColor, row.label,
          M.Unpack(info.missing > 0 and t.missingColor or t.nameColor))
  end
  EP.SetShown(row.tick, info.isEquipped and not row.tick.missing)
  EP.SetShown(row.selectedWash, set == EP.selected)
  EP.SetShown(row.stripe, math.mod(index, 2) == 0)
end

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------
function EP.Layout()
  local total = table.getn(EP.entries)
  EP.maxOffset = math.max(1, total - EP.capacity + 1)
  EP.offset = math.max(1, math.min(EP.offset, EP.maxOffset))
  local height = EP.Token().row.height
  local used, i = 0, nil
  for i = EP.offset, math.min(total, EP.offset + EP.capacity - 1) do
    used = used + 1
    local row = EP.rows[used] or EP.BuildRow(used)
    pcall(function()
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", EP.list, "TOPLEFT", 0, -(used - 1) * height)
    end)
    EP.FillRow(row, EP.entries[i], i)
    row:Show()
  end
  for i = used + 1, table.getn(EP.rows) do
    EP.rows[i].entry = nil
    EP.rows[i]:Hide()
  end
  EP.visibleCount = used
  EP.PaintHover()
  EP.LayoutScroll()
end

-- A scrollbar's range, value, arrows and thumb for a list showing `visible`
-- of `total` entries from `offset`.
function EP.SyncScroll(scroll, offset, maxOffset, visible, total)
  if not scroll then return end
  local scrollable = maxOffset > 1
  EP.SetShown(scroll.bar, scrollable)
  scroll.syncing = true
  pcall(scroll.bar.SetMinMaxValues, scroll.bar, 1, maxOffset)
  pcall(scroll.bar.SetValue, scroll.bar, offset)
  scroll.syncing = false
  if not scrollable then return end
  if scroll.up then
    if offset > 1 then pcall(scroll.up.Enable, scroll.up)
    else pcall(scroll.up.Disable, scroll.up) end
  end
  if scroll.down then
    if offset < maxOffset then pcall(scroll.down.Enable, scroll.down)
    else pcall(scroll.down.Disable, scroll.down) end
  end
  if not EP.flat and type(U.SetModernWowScrollbarProportion) == "function" then
    U.SetModernWowScrollbarProportion(scroll.bar, visible, total)
  end
end

-- The slider's value as a whole offset in 1..maxOffset, or nil while the
-- owner is setting it.
function EP.ScrollValue(scroll, maxOffset)
  local bar = scroll and scroll.bar
  if not bar or scroll.syncing then return nil end
  local ok, value = pcall(bar.GetValue, bar)
  value = ok and tonumber(value) or nil
  if not value then return nil end
  return math.max(1, math.min(maxOffset, math.floor(value + 0.5)))
end

function EP.LayoutScroll()
  EP.SyncScroll(EP.scroll, EP.offset, EP.maxOffset, EP.visibleCount or 0,
                table.getn(EP.entries))
end

function EP.ReadScroll()
  local value = EP.ScrollValue(EP.scroll, EP.maxOffset)
  if not value or value == EP.offset then return end
  EP.offset = value
  EP.Layout()
end

function EP.Wheel(direction)
  local target = math.max(1, math.min(EP.maxOffset, EP.offset - direction))
  if target == EP.offset then return end
  EP.offset = target
  EP.Layout()
end

-- The stats pane's scrollbar (modules/characterstatspanel.lua SP.BuildScroll)
-- on `parent`, `height` tall with its arrows, at its top-right corner offset
-- by `x`. `onStep(direction)` runs for the arrows, `onRead` when the thumb
-- moves.
function EP.MakeScroll(parent, name, height, x, onStep, onRead)
  local s = EP.StatsToken().scroll
  height = height - s.arrowPad * 2
  if height < 1 then return nil end
  local ok, bar = pcall(CreateFrame, "Slider", name, parent,
                        "UIPanelScrollBarTemplate")
  if not ok or not bar then return nil end
  pcall(bar.SetScript, bar, "OnValueChanged", nil)
  pcall(function()
    bar:SetFrameLevel(EP.Dimension(parent, "GetFrameLevel") + 3)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(s.column)
    bar:SetHeight(height)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, -s.arrowPad)
    bar:SetMinMaxValues(1, 1)
    bar:SetValueStep(1)
    bar:SetValue(1)
  end)
  local up = U.G(name .. "ScrollUpButton")
  local down = U.G(name .. "ScrollDownButton")
  if up then up:SetScript("OnClick", function() onStep(1) end) end
  if down then down:SetScript("OnClick", function() onStep(-1) end) end
  if EP.flat and type(U.StyleStockScrollbar) == "function" then
    U.StyleStockScrollbar(bar)
  elseif type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, { onChange = onRead })
  end
  bar:SetScript("OnValueChanged", onRead)
  return { bar = bar, up = up, down = down }
end

function EP.BuildScroll(listHeight)
  EP.scroll = EP.MakeScroll(EP.list, EP.SCROLL, listHeight,
                            EP.StatsToken().scroll.x, EP.Wheel,
                            EP.ReadScroll)
end

-- PaperDollEquipmentManagerPane_Update: the buttons' state, then every set and
-- the New Set row while there is room for another.
function EP.Refresh()
  if not EP.active or not EP.frame then return end
  local ES = EP.Sets()
  if EP.selected and not ES.IndexOf(EP.selected) then
    EP.selected = nil
    ES.ignored = {}
  end
  local canEquip, canSave = false, false
  if EP.selected then
    local info = ES.Info(EP.selected)
    canEquip = not info.isEquipped and not ES.Running()
    canSave = not info.isEquipped
    local i
    for i = 1, table.getn(ES.ORDER) do
      local slot = ES.ORDER[i]
      if (EP.selected.items[slot] == nil) ~= ES.IsIgnored(slot) then canSave = true end
    end
  end
  EP.SetEnabled(EP.equip, canEquip)
  EP.SetEnabled(EP.save, canSave)

  local entries = {}
  local sets = ES.Sets()
  local i
  for i = 1, table.getn(sets) do table.insert(entries, { set = sets[i] }) end
  if table.getn(sets) < ES.MAX_SETS then table.insert(entries, { newSet = true }) end
  EP.entries = entries
  EP.Layout()
end

function EP.QueueRefresh()
  if EP.active then U.DeferOnce(EP.REFRESH, EP.Refresh) end
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
-- GearSetButton_OnClick, and the OnDoubleClick equip.
function EP.RowClick(row)
  local entry = row.entry
  if not entry then return end
  if entry.newSet then return EP.NewSet() end
  local now = EP.Now()
  if EP.lastSet == entry.set and now - EP.lastTime <= EP.Token().row.doubleClick then
    EP.lastSet = nil
    EP.Select(entry.set)
    return EP.Equip()
  end
  EP.lastSet, EP.lastTime = entry.set, now
  EP.Select(entry.set)
end

function EP.Select(set)
  EP.selected = set
  EP.HidePopup()
  U.HideConfirm(EP)
  EP.Sets().IgnoreSlotsForSet(set)
  EP.Refresh()
end

function EP.NewSet()
  local ES = EP.Sets()
  if ES.Count() >= ES.MAX_SETS then
    U.Print(U.L("EQUIPSET_TOO_MANY", ES.MAX_SETS))
    return
  end
  EP.selected = nil
  U.HideConfirm(EP)
  ES.IgnoreDefaults()
  EP.ShowPopup("new")
  EP.Refresh()
end

-- PaperDollEquipmentManagerPaneEquipSet_OnClick. EQUIPMENT_SWAP_FINISHED
-- then selects the set.
function EP.Equip()
  local set = EP.selected
  if not set then return end
  EP.Sets().Equip(set, function()
    if EP.Sets().IndexOf(set) then EP.selected = set end
    EP.QueueRefresh()
  end)
  EP.Refresh()
end

function EP.ConfirmSave()
  local set = EP.selected
  if not set then return end
  U.ShowConfirm({
    owner = EP, modernWow = true,
    text = U.L("EQUIPSET_SAVE_CONFIRM", set.name),
    acceptText = U.L("EQUIPSET_SAVE"),
    onAccept = function()
      EP.Sets().Save(set)
      EP.Refresh()
    end,
  })
end

function EP.ConfirmDelete(set)
  U.ShowConfirm({
    owner = EP, modernWow = true,
    text = U.L("EQUIPSET_DELETE_CONFIRM", set.name),
    acceptText = U.L("EQUIPSET_DELETE"),
    onAccept = function()
      if EP.popup and EP.popup.set == set then EP.HidePopup() end
      EP.Sets().Delete(set)
      EP.Refresh()
    end,
  })
end

-- The flyout offers the ignore-slot buttons while a set is selected or being
-- named (PaperDollFrameItemFlyout_PostGetItems).
function EP.OffersIgnore()
  if not EP.active then return false end
  if EP.selected then return true end
  return EP.popup and EP.popup:IsShown() and true or false
end

-- ---------------------------------------------------------------------------
-- Popup (GearManagerPopupFrame)
-- ---------------------------------------------------------------------------
-- The icon grid: Retail's IconSelector, `rows` x `columns` buttons over a
-- list that scrolls a row at a time (wheel, arrows, thumb). The list is
-- ES.AllIcons: the set's own icon, the equipped items', "?", then the
-- client's macro icon library.
function EP.IconButton(index)
  local p = EP.Token().popup
  local grid = EP.popup.grid
  local button = CreateFrame("Button", nil, grid)
  pcall(button.EnableMouse, button, true)
  button:SetWidth(p.icon)
  button:SetHeight(p.icon)
  pcall(button.SetFrameLevel, button, EP.Dimension(grid, "GetFrameLevel") + 2)
  local column = math.mod(index - 1, p.columns)
  local row = math.floor((index - 1) / p.columns)
  button:SetPoint("TOPLEFT", grid, "TOPLEFT", column * (p.icon + p.iconGap),
                  -row * (p.icon + p.iconGap))
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints(button)
  if EP.flat then
    U.CreateBackdrop(button, {
      background = { 0.03, 0.03, 0.03, 0.82 }, border = M.color.border,
    })
    button:SetScript("OnEnter", function()
      U.SetBorderColor(button, M.Unpack(M.color.accentDim))
    end)
    button:SetScript("OnLeave", function()
      U.SetBorderColor(button, M.Unpack(M.color.border))
    end)
  elseif pcall(button.SetHighlightTexture, button, M.modernWow.gearSlot.hover) then
    local ok, region = pcall(button.GetHighlightTexture, button)
    if ok and region then pcall(region.SetBlendMode, region, "ADD") end
  end
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  button:SetScript("OnClick", function()
    if not button.iconName then return end
    EP.iconChoice = button.iconName
    EP.PaintIcons()
  end)
  EP.popup.icons[index] = button
  return button
end

function EP.IconRows()
  local p = EP.Token().popup
  return math.max(1, math.ceil(table.getn(EP.iconList or {}) / p.columns))
end

function EP.PaintIcons()
  local popup = EP.popup
  local p = EP.Token().popup
  local list = EP.iconList or {}
  EP.iconMaxOffset = math.max(1, EP.IconRows() - p.rows + 1)
  EP.iconOffset = math.max(1, math.min(EP.iconOffset or 1, EP.iconMaxOffset))
  local first = (EP.iconOffset - 1) * p.columns
  local selected, shown = nil, 0
  local i
  for i = 1, p.rows * p.columns do
    local button = popup.icons[i] or EP.IconButton(i)
    local name = list[first + i]
    button.iconName = name
    if name then
      shown = shown + 1
      button.icon:SetTexture(EP.Sets().IconPath(name))
      button:Show()
      if name == EP.iconChoice then selected = button end
    else
      button:Hide()
    end
  end
  local ring = popup.selection
  if selected then
    pcall(function()
      ring:ClearAllPoints()
      ring:SetPoint("CENTER", selected, "CENTER", 0, 0)
      ring:SetFrameLevel(EP.Dimension(selected, "GetFrameLevel") + 1)
    end)
    ring:Show()
  else
    ring:Hide()
  end
  EP.SyncScroll(popup.scroll, EP.iconOffset, EP.iconMaxOffset,
                p.rows, EP.IconRows())
end

function EP.IconWheel(direction)
  local target = math.max(1, math.min(EP.iconMaxOffset or 1,
                                      (EP.iconOffset or 1) - direction))
  if target == EP.iconOffset then return end
  EP.iconOffset = target
  EP.PaintIcons()
end

function EP.ReadIconScroll()
  local popup = EP.popup
  local value = popup and EP.ScrollValue(popup.scroll, EP.iconMaxOffset or 1)
  if not value or value == EP.iconOffset then return end
  EP.iconOffset = value
  EP.PaintIcons()
end

-- Scrolls the grid so the chosen icon's row is in view, near the middle.
function EP.ShowIconChoice()
  local p = EP.Token().popup
  local list = EP.iconList or {}
  local i
  for i = 1, table.getn(list) do
    if list[i] == EP.iconChoice then
      EP.iconOffset = math.ceil(i / p.columns) - math.floor(p.rows / 2)
      return
    end
  end
  EP.iconOffset = 1
end

function EP.LayoutPopup()
  local popup = EP.popup
  local p = EP.Token().popup
  EP.PaintIcons()
  local height = p.inset + EP.Dimension(popup.title, "GetHeight") + p.gap +
                 EP.Dimension(popup.name, "GetHeight") + p.gap * 2 +
                 EP.Dimension(popup.iconLabel, "GetHeight") + p.gap +
                 EP.Dimension(popup.grid, "GetHeight") + p.gap * 2 +
                 p.buttonHeight + p.inset
  popup:SetHeight(height)
  if not EP.flat and type(U.ModernWowMetalFrame) == "function" then
    U.ModernWowMetalFrame(popup, popup.width, height)
  end
end

function EP.PopupChanged(text)
  if EP.popup then
    EP.SetEnabled(EP.popup.okay, EP.Sets().CleanName(text) ~= "")
  end
end

function EP.BuildPopup()
  local t = EP.Token()
  local p = t.popup
  local column = EP.StatsToken().scroll.column
  local gridWidth = p.columns * p.icon + (p.columns - 1) * p.iconGap +
                    p.scrollGap + column
  local gridHeight = p.rows * p.icon + (p.rows - 1) * p.iconGap
  local popup = CreateFrame("Frame", nil, EP.host)
  local width = p.inset * 2 + gridWidth
  popup.width = width
  popup:SetWidth(width)
  popup:SetHeight(200)
  popup:SetPoint("TOPLEFT", EP.host, "TOPRIGHT", p.x, p.y)
  pcall(popup.SetFrameLevel, popup, EP.Dimension(EP.host, "GetFrameLevel") + 20)
  pcall(popup.EnableMouse, popup, true)
  popup.icons = {}
  EP.popup = popup
  if EP.flat then
    U.CreateBackdrop(popup, {
      background = { 0.02, 0.02, 0.02, 0.96 }, border = M.color.border,
    })
  elseif type(U.ModernWowMetalFrame) == "function" then
    U.ModernWowMetalFrame(popup, width, 200)
  end

  popup.title = U.CreateLabel(popup, { size = p.font, inherits = "GameFontNormal",
                                       color = t.nameColor, justify = "LEFT" })
  popup.title:SetPoint("TOPLEFT", popup, "TOPLEFT", p.inset, -p.inset)
  popup.title:SetText(U.L("EQUIPSET_POPUP_NAME"))

  popup.name = U.CreateSearchBox(popup, {
    name = EP.NAME_FIELD,
    placeholder = U.L("EQUIPSET_POPUP_PLACEHOLDER"),
    onChange = EP.PopupChanged,
  })
  if not popup.name then error("set name field unavailable") end
  popup.name:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -p.gap)
  popup.name:SetPoint("RIGHT", popup, "RIGHT", -p.inset, 0)
  U.LevelSearchBox(popup.name, EP.Dimension(popup, "GetFrameLevel") + 2)
  U.PaintSearchBox(popup.name)

  popup.iconLabel = U.CreateLabel(popup, { size = p.font, inherits = "GameFontNormal",
                                           color = t.nameColor, justify = "LEFT" })
  popup.iconLabel:SetPoint("TOPLEFT", popup.name, "BOTTOMLEFT", 0, -p.gap * 2)
  popup.iconLabel:SetText(U.L("EQUIPSET_POPUP_ICON"))

  local grid = CreateFrame("Frame", nil, popup)
  grid:SetWidth(gridWidth)
  grid:SetHeight(gridHeight)
  grid:SetPoint("TOPLEFT", popup.iconLabel, "BOTTOMLEFT", 0, -p.gap)
  pcall(grid.SetFrameLevel, grid, EP.Dimension(popup, "GetFrameLevel") + 1)
  popup.grid = grid
  -- Built before the buttons so it stays underneath them.
  if type(U.CreateWheelCatcher) == "function" then
    U.CreateWheelCatcher(grid, EP.IconWheel)
  end
  popup.scroll = EP.MakeScroll(grid, EP.ICON_SCROLL, gridHeight, 0,
                               EP.IconWheel, EP.ReadIconScroll)

  local ring = CreateFrame("Frame", nil, grid)
  ring:SetWidth(p.icon + p.selectedGrow)
  ring:SetHeight(p.icon + p.selectedGrow)
  pcall(ring.EnableMouse, ring, false)
  if EP.flat then
    U.CreateBackdrop(ring, {
      background = { 0, 0, 0, 0 }, border = M.color.accent,
    })
  else
    local glow = ring:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(t.texture.highlight)
    glow:SetAllPoints(ring)
    pcall(glow.SetTexCoord, glow, t.flyout.highlight.coords[1],
          t.flyout.highlight.coords[2], t.flyout.highlight.coords[3],
          t.flyout.highlight.coords[4])
  end
  ring:Hide()
  popup.selection = ring

  popup.cancel = EP.Button(popup, U.L("COMMON_CANCEL"), p.buttonWidth, p.buttonHeight,
                           EP.HidePopup)
  popup.cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -p.inset, p.inset)
  popup.okay = EP.Button(popup, U.L("EQUIPSET_OKAY"), p.buttonWidth, p.buttonHeight,
                         EP.PopupOkay)
  popup.okay:SetPoint("RIGHT", popup.cancel, "LEFT", -p.gap, 0)
  pcall(popup.cancel.SetFrameLevel, popup.cancel, EP.Dimension(popup, "GetFrameLevel") + 2)
  pcall(popup.okay.SetFrameLevel, popup.okay, EP.Dimension(popup, "GetFrameLevel") + 2)

  popup:Hide()
end

-- GearManagerPopupFrameMixin:OnShow / Update. `mode` "new" or "edit".
function EP.ShowPopup(mode, set)
  if not EP.popup then
    local ok, err = pcall(EP.BuildPopup)
    if not ok then
      U.Error("equipment manager popup: " .. tostring(err))
      if EP.popup then EP.popup:Hide() end
      EP.popup = nil
      return
    end
  end
  local ES = EP.Sets()
  local popup = EP.popup
  popup.mode = mode
  popup.set = mode == "edit" and set or nil
  if mode == "edit" and set then
    EP.selected = set
    ES.IgnoreSlotsForSet(set)
  end
  local current = popup.set and popup.set.icon
  EP.iconList = ES.AllIcons(current)
  EP.iconChoice = current or EP.iconList[1]
  EP.ShowIconChoice()

  U.ResetSearchBox(popup.name)
  if popup.set and type(U.SetSearchBoxText) == "function" then
    U.SetSearchBoxText(popup.name, popup.set.name)
  end
  EP.PopupChanged(U.SearchBoxText(popup.name))
  popup:Show()
  EP.LayoutPopup()
  if type(U.BeginSearchTyping) == "function" then U.BeginSearchTyping(popup.name) end
  EP.Refresh()
end

-- GearManagerPopupFrameMixin:OnHide: a popup closed with no set selected
-- drops the ignored slots it was building.
function EP.HidePopup()
  local popup = EP.popup
  if not popup or not popup:IsShown() then return end
  U.ResetSearchBox(popup.name)
  popup:Hide()
  popup.set = nil
  if not EP.selected then EP.Sets().ClearIgnored() end
  EP.QueueRefresh()
end

-- GearManagerPopupFrameMixin:OkayButton_OnClick.
function EP.PopupOkay()
  local ES = EP.Sets()
  local popup = EP.popup
  local name = ES.CleanName(U.SearchBoxText(popup.name))
  if name == "" then return end
  local icon = EP.iconChoice
  local existing = ES.FindByName(name)
  if existing and existing ~= popup.set then
    if popup.mode == "edit" then
      U.Print(U.L("EQUIPSET_CANT_RENAME"))
      return
    end
    U.ShowConfirm({
      owner = EP, modernWow = true,
      text = U.L("EQUIPSET_OVERWRITE_CONFIRM", existing.name),
      onAccept = function()
        ES.Save(existing, icon)
        EP.selected = existing
        EP.HidePopup()
        ES.IgnoreSlotsForSet(existing)
        EP.Refresh()
      end,
    })
    return
  end
  if popup.mode == "new" then
    if ES.Count() >= ES.MAX_SETS then
      U.Print(U.L("EQUIPSET_TOO_MANY", ES.MAX_SETS))
      return
    end
    EP.selected = ES.Create(name, icon)
  else
    ES.Modify(popup.set, name, icon)
    EP.selected = popup.set
  end
  EP.HidePopup()
  if EP.selected then ES.IgnoreSlotsForSet(EP.selected) end
  EP.Refresh()
end

-- ---------------------------------------------------------------------------
-- Build and activation
-- ---------------------------------------------------------------------------
-- `pane` is the stats pane's own frame, `host` the housing panel it sits in,
-- `window` CharacterFrame.
function EP.Build(pane, host, window)
  EP.flat = type(U.GetActiveThemeStyle) == "function" and
            U.GetActiveThemeStyle() == "modern"
  local t = EP.Token()
  local inset = EP.StatsToken().list
  local width = EP.Dimension(pane, "GetWidth")
  local height = EP.Dimension(pane, "GetHeight")
  if width <= 0 or height <= 0 then error("pane has no size") end
  EP.host = host

  local frame = CreateFrame("Frame", nil, pane)
  frame:SetAllPoints(pane)
  pcall(frame.SetFrameLevel, frame, EP.Dimension(pane, "GetFrameLevel") + 1)
  EP.frame = frame

  local buttonWidth = (width - inset.left - inset.right - t.pane.buttonGap) / 2
  EP.equip = EP.Button(frame, U.L("EQUIPSET_EQUIP"), buttonWidth,
                       t.pane.buttonHeight, EP.Equip)
  EP.equip:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, -inset.top)
  EP.save = EP.Button(frame, U.L("EQUIPSET_SAVE"), buttonWidth,
                      t.pane.buttonHeight, EP.ConfirmSave)
  EP.save:SetPoint("LEFT", EP.equip, "RIGHT", t.pane.buttonGap, 0)
  pcall(EP.equip.SetFrameLevel, EP.equip, EP.Dimension(frame, "GetFrameLevel") + 3)
  pcall(EP.save.SetFrameLevel, EP.save, EP.Dimension(frame, "GetFrameLevel") + 3)

  local top = inset.top + t.pane.buttonHeight + t.pane.listGap
  local listWidth = width - inset.left - inset.right
  local listHeight = height - top - inset.bottom
  local list = CreateFrame("Frame", nil, frame)
  list:SetWidth(listWidth)
  list:SetHeight(listHeight)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, -top)
  pcall(list.SetFrameLevel, list, EP.Dimension(frame, "GetFrameLevel") + 1)
  EP.list = list
  EP.rowWidth = listWidth - EP.StatsToken().scroll.column
  EP.capacity = math.max(1, math.floor(listHeight / t.row.height))

  if type(U.CreateWheelCatcher) == "function" then
    U.CreateWheelCatcher(list, EP.Wheel)
  end
  EP.BuildScroll(listHeight)

  if not U.BuildCharacterFlyout(window) then error("slot flyout unavailable") end
  EP.Sets().OnChange(EP.QueueRefresh)
  U.RegisterEvent("BAG_UPDATE", EP.QueueRefresh)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", EP.QueueRefresh)
  frame:Hide()
end

-- Shown in the stats pane's place. False when it cannot build, so the pane
-- keeps its list.
function EP.Activate(pane, host, window)
  if not U.EquipmentSets then return false end
  if not EP.frame then
    if not pane or not host or not window then return false end
    local ok, err = pcall(EP.Build, pane, host, window)
    if not ok then
      U.Error("equipment manager: " .. tostring(err))
      if EP.frame then EP.frame:Hide() end
      EP.frame = nil
      return false
    end
  end
  local ES = EP.Sets()
  EP.active = true
  EP.frame:Show()
  if EP.selected and not ES.IndexOf(EP.selected) then EP.selected = nil end
  if EP.selected then ES.IgnoreSlotsForSet(EP.selected) else ES.ClearIgnored() end
  if U.CharacterFlyout then U.CharacterFlyout.SetActive(true) end
  EP.Refresh()
  return true
end

-- PaperDollEquipmentManagerPane_OnHide.
function EP.Deactivate()
  if not EP.active then return end
  EP.HidePopup()
  EP.active = false
  if EP.frame then EP.frame:Hide() end
  if U.CharacterFlyout then U.CharacterFlyout.SetActive(false) end
  U.HideConfirm(EP)
  EP.HideTooltip()
  U.EquipmentSets.ClearIgnored()
end
