-- unrealUI :: modules/characterflyout.lua
--
-- The arrows beside the paper doll's gear slots and the item flyout they open
-- (user request, 2026-09-28): Retail's EquipmentFlyoutPopoutButtonTemplate
-- and EquipmentFlyoutFrame (Blizzard_FrameXML/EquipmentFlyout.xml/.lua) with
-- the paper doll's own settings (PaperDollFrame.lua: flyoutSettings,
-- PaperDollFrameItemFlyout_PostGetItems, PaperDollFrameItemFlyoutButton
-- _OnClick). As in Retail the arrows show only while the Equipment Manager
-- pane does (EquipmentFlyoutPopoutButton_ShowAll / _HideAll); a click locks
-- the flyout open beside its slot, listing:
--   * "Place in bags" when the slot holds an item;
--   * "Ignore this slot" / its undo while a set is selected or being named;
--   * every carried item that fits the slot (modules/equipmentsets.lua).
-- The ignored-slot mark (PaperDollItemSlotButtonTemplate's ignoreTexture) is
-- drawn here too. Geometry: M.modernWow.equipmentManager.
--
-- No addon frame is anchored to a client slot button (rules/unreal-ui.md,
-- native widget ownership): each slot gets an addon-owned holder placed on
-- CharacterFrame from bounded numbers read off the slot once, as
-- modules/characterstatspanel.lua fits the 3D model.
--
-- Entry point only: modules/characterequipment.lua builds it and turns it on
-- and off with its pane. One top-level table.

local U = UnrealUI
local M = U.media

local FL = {
  overlay = nil,
  holders = {},
  flyout = nil,
  open = nil,
  locked = false,
  page = 1,
  entries = {},
  active = false,
  flat = false,
  measured = false,
  REFRESH = "characterflyout.refresh",
  -- Paper-doll slot id -> the client's slot button, without "Character".
  SLOTS = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot",
    [5] = "ChestSlot", [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot",
    [9] = "WristSlot", [10] = "HandsSlot", [11] = "Finger0Slot",
    [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot",
    [18] = "RangedSlot", [19] = "TabardSlot",
  },
  VERTICAL = { [16] = true, [17] = true, [18] = true },
  -- PLACEINBAGS / IGNORESLOT / UNIGNORESLOT locations.
  SPECIAL = { intoBags = "intoBags", ignore = "ignore", unignore = "unignore" },
}
U.CharacterFlyout = FL

function FL.Token()
  if FL.flat then return M.characterModern.equipment end
  return M.modernWow.equipmentManager
end

function FL.Dimension(frame, method)
  if not frame or not frame[method] then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

function FL.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

-- 4-value crops only: the documented rotated 8-value form is ignored here
-- (M.modernWow.equipmentManager.popout).
function FL.Coords(texture, coords)
  if not texture or not coords then return end
  pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
end

function FL.InCombat()
  local fn = U.G("UnitAffectingCombat")
  if type(fn) ~= "function" then return false end
  local ok, combat = pcall(fn, "player")
  return ok and combat and combat ~= 0 and true or false
end

-- ---------------------------------------------------------------------------
-- Slot holders
-- ---------------------------------------------------------------------------
-- Reads each slot's rect once, as offsets from CharacterFrame's top-left.
-- Returns false while any edge is unreadable, so the next show retries.
function FL.Measure()
  if FL.measured then return true end
  local frame = FL.frame
  local frameLeft = FL.Dimension(frame, "GetLeft")
  local frameTop = FL.Dimension(frame, "GetTop")
  if frameLeft <= 0 or frameTop <= 0 then return false end
  local rects, level = {}, 0
  local id, name
  for id, name in pairs(FL.SLOTS) do
    local slot = U.G("Character" .. name)
    local left = FL.Dimension(slot, "GetLeft")
    local top = FL.Dimension(slot, "GetTop")
    local width = FL.Dimension(slot, "GetWidth")
    local height = FL.Dimension(slot, "GetHeight")
    if left <= 0 or top <= 0 or width <= 0 or height <= 0 then return false end
    rects[id] = { x = left - frameLeft, y = frameTop - top, w = width, h = height }
    local slotLevel = FL.Dimension(slot, "GetFrameLevel")
    if slotLevel > level then level = slotLevel end
  end
  pcall(FL.overlay.SetFrameLevel, FL.overlay, level + 1)
  local rect
  for id, rect in pairs(rects) do
    local holder = FL.holders[id]
    pcall(function()
      holder:ClearAllPoints()
      holder:SetPoint("TOPLEFT", frame, "TOPLEFT", rect.x, -rect.y)
      holder:SetWidth(rect.w)
      holder:SetHeight(rect.h)
      holder:SetFrameLevel(level + 2)
      holder.popout:SetFrameLevel(level + 3)
    end)
  end
  FL.measured = true
  return true
end

function FL.PaintPopout(holder)
  local t = FL.Token().popout
  if FL.flat then
    local opened = FL.open == holder.slot and FL.locked
    if holder.popout.label then
      holder.popout.label:SetText(FL.VERTICAL[holder.slot] and
                                  (opened and "^" or "v") or
                                  (opened and "<" or ">"))
      pcall(holder.popout.label.SetTextColor, holder.popout.label,
            M.Unpack(opened and M.color.accent or M.color.text))
    end
    U.SetBorderColor(holder.popout,
      M.Unpack(opened and M.color.accent or M.color.border))
    return
  end
  local set = FL.VERTICAL[holder.slot] and t.vertical or t.horizontal
  local opened = FL.open == holder.slot and FL.locked
  FL.Coords(holder.popout.normal, opened and set.openNormal or set.normal)
  FL.Coords(holder.popout.highlight, opened and set.openHighlight or set.highlight)
end

function FL.BuildHolder(id)
  local t = FL.Token()
  local holder = CreateFrame("Frame", nil, FL.overlay)
  holder:SetWidth(1)
  holder:SetHeight(1)
  pcall(holder.EnableMouse, holder, false)
  holder.slot = id

  local mark
  if FL.flat then
    mark = U.CreateLabel(holder, {
      size = M.fontSize.large, color = M.color.closeGlyph,
      inherits = "GameFontNormal", justify = "CENTER",
    })
    mark:SetText("X")
  else
    mark = holder:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(t.texture.ignoredMark)
  end
  mark:SetWidth(t.ignoredMark)
  mark:SetHeight(t.ignoredMark)
  mark:SetPoint("CENTER", holder, "CENTER", 0, 0)
  mark:Hide()
  holder.mark = mark

  local popout
  if FL.flat then
    popout = U.CreateButton(FL.overlay, {
      text = FL.VERTICAL[id] and "v" or ">", width = t.popout.short,
      height = t.popout.short, size = M.fontSize.tiny,
    })
  else
    popout = CreateFrame("Button", nil, FL.overlay)
  end

  pcall(popout.EnableMouse, popout, true)
  if not FL.flat then
    local art = FL.VERTICAL[id] and t.texture.popout or t.texture.popoutSide
    popout.normal = popout:CreateTexture(nil, "ARTWORK")
    popout.normal:SetTexture(art)
    popout.normal:SetAllPoints(popout)
    popout.highlight = popout:CreateTexture(nil, "HIGHLIGHT")
    popout.highlight:SetTexture(art)
    popout.highlight:SetAllPoints(popout)
  end
  if FL.VERTICAL[id] then
    popout:SetWidth(t.popout.long)
    popout:SetHeight(t.popout.short)
    popout:SetPoint("TOP", holder, "BOTTOM", 0, t.popout.verticalOverlap)
  else
    popout:SetWidth(t.popout.short)
    popout:SetHeight(t.popout.long)
    popout:SetPoint("LEFT", holder, "RIGHT", -t.popout.overlap, 0)
  end
  pcall(popout.RegisterForClicks, popout, "LeftButtonUp")
  popout:SetScript("OnClick", function() FL.Toggle(id) end)
  if FL.flat then
    -- U.CreateButton's own leave resets the outline to neutral, which would
    -- drop the open arrow's accent; hover is subdued accent, leave repaints
    -- the arrow's real state.
    popout:SetScript("OnEnter", function()
      if not (FL.open == id and FL.locked) then
        U.SetBorderColor(popout, M.Unpack(M.color.accentDim))
      end
    end)
    popout:SetScript("OnLeave", function() FL.PaintPopout(holder) end)
  end
  holder.popout = popout
  FL.holders[id] = holder
  FL.PaintPopout(holder)
  return holder
end

-- PaperDollItemSlotButton_Update's ignoreTexture, for every slot.
function FL.PaintMarks()
  local ES = U.EquipmentSets
  local id, holder
  for id, holder in pairs(FL.holders) do
    FL.SetShown(holder.mark, FL.active and ES and ES.IsIgnored(id))
  end
end

-- ---------------------------------------------------------------------------
-- Flyout
-- ---------------------------------------------------------------------------
function FL.Background(index)
  local frame = FL.flyout.buttons
  local bg = frame.bgs[index]
  if not bg then
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(FL.Token().texture.flyout)
    frame.bgs[index] = bg
  end
  return bg
end

function FL.PlaceBackground(index, spec, width, height, previous, below)
  local bg = FL.Background(index)
  local t = FL.Token().flyout
  pcall(function()
    bg:ClearAllPoints()
    bg:SetWidth(width)
    bg:SetHeight(height)
    bg:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4])
    if not previous then
      bg:SetPoint("TOPLEFT", FL.flyout.buttons, "TOPLEFT", t.bgX, t.bgY)
    elseif below then
      bg:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0)
    else
      bg:SetPoint("TOPLEFT", previous, "TOPRIGHT", 0, 0)
    end
    bg:Show()
  end)
  return bg
end

-- EquipmentFlyout_UpdateItems' background: one slot, one row, or rows.
function FL.LayoutBackground(count)
  local t = FL.Token().flyout
  if FL.flat then
    local frame = FL.flyout.buttons
    if not frame.uuiFlatPanel then
      U.CreateBackdrop(frame, {
        background = { 0.02, 0.02, 0.02, 0.96 }, border = M.color.border,
      })
      frame.uuiFlatPanel = true
    end
    return
  end
  local used = 0
  local last
  local function Put(spec, width, height, below)
    used = used + 1
    last = FL.PlaceBackground(used, spec, width, height, last, below)
  end
  if count == 1 then
    Put(t.oneSlot.left, t.oneSlot.left.width, t.oneSlot.height)
    Put(t.oneSlot.right, t.oneSlot.right.width, t.oneSlot.height)
  elseif count <= t.perRow then
    Put(t.oneRow.left, t.oneRow.left.width, t.oneRow.height)
    local i
    for i = 2, count - 1 do
      Put(t.oneRow.center, t.oneRow.center.width, t.oneRow.height)
    end
    Put(t.oneRow.right, t.oneRow.right.width, t.oneRow.height)
  else
    local rows = math.ceil(count / t.perRow)
    local w = t.multiRow.width
    Put(t.multiRow.top, w, t.multiRow.top.height)
    local i
    for i = 2, rows - 1 do Put(t.multiRow.middle, w, t.multiRow.middle.height, true) end
    Put(t.multiRow.bottom, w, t.multiRow.bottom.height, true)
  end
  local frame = FL.flyout.buttons
  local i
  for i = used + 1, table.getn(frame.bgs) do frame.bgs[i]:Hide() end
end

function FL.ItemTooltip(button)
  local entry = button.entry
  if not entry then return end
  if entry.special then
    if type(U.ShowInfoTooltip) == "function" then
      U.ShowInfoTooltip(button, { { U.L("EQUIPFLYOUT_" .. string.upper(entry.special)),
                                    M.color.text } })
    end
    return
  end
  local tip = U.G("GameTooltip")
  if not tip then return end
  pcall(tip.SetOwner, tip, button, "ANCHOR_RIGHT")
  if pcall(tip.SetBagItem, tip, entry.bag, entry.slot) then
    pcall(tip.Show, tip)
    if type(U.ShowItemCompare) == "function" then U.ShowItemCompare(entry.link) end
  end
end

function FL.HideTooltip()
  local tip = U.G("GameTooltip")
  if tip then pcall(tip.Hide, tip) end
  if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  if type(U.HideInfoTooltip) == "function" then U.HideInfoTooltip() end
end

function FL.BuildButton(index)
  local t = FL.Token()
  local f = t.flyout
  local frame = FL.flyout.buttons
  local button = CreateFrame("Button", nil, frame)
  pcall(button.EnableMouse, button, true)
  button:SetWidth(f.item)
  button:SetHeight(f.item)
  pcall(button.SetFrameLevel, button, FL.Dimension(frame, "GetFrameLevel") + 1)
  local row = math.floor((index - 1) / f.perRow)
  if math.mod(index - 1, f.perRow) == 0 then
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", f.border, -f.border - f.rowStep * row)
  else
    button:SetPoint("TOPLEFT", frame.items[index - 1], "TOPRIGHT", f.xGap, 0)
  end
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints(button)
  if FL.flat then
    U.CreateBackdrop(button, {
      background = { 0.03, 0.03, 0.03, 0.82 }, border = M.color.border,
    })
    button.glyph = U.CreateLabel(button, {
      size = M.fontSize.large, color = M.color.text,
      inherits = "GameFontNormal", justify = "CENTER",
    })
    if button.glyph then button.glyph:SetPoint("CENTER", button, "CENTER", 0, -1) end
  elseif pcall(button.SetHighlightTexture, button, M.modernWow.gearSlot.hover) then
    local ok, region = pcall(button.GetHighlightTexture, button)
    if ok and region then pcall(region.SetBlendMode, region, "ADD") end
  end
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  button:SetScript("OnClick", function() FL.Click(button) end)
  button:SetScript("OnEnter", function()
    if FL.flat then U.SetBorderColor(button, M.Unpack(M.color.accentDim)) end
    FL.ItemTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    if FL.flat then
      U.SetBorderColor(button, M.Unpack(button.flatBorder or M.color.border))
    end
    FL.HideTooltip()
  end)
  frame.items[index] = button
  return button
end

function FL.PageButton(parent, art, point, x, onClick)
  local t = FL.Token()
  local nav = t.flyout.nav
  local button
  if FL.flat then
    button = U.CreateButton(parent, {
      text = point == "LEFT" and "<" or ">", width = nav.button,
      height = nav.button, size = M.fontSize.small,
    })
    local enable, disable = button.Enable, button.Disable
    button.Enable = function(self)
      if enable then pcall(enable, self) end
      if self.label then
        pcall(self.label.SetTextColor, self.label, M.Unpack(M.color.text))
      end
    end
    button.Disable = function(self)
      if disable then pcall(disable, self) end
      if self.label then
        pcall(self.label.SetTextColor, self.label, M.Unpack(M.color.textDim))
      end
      U.SetBorderColor(self, M.Unpack(M.color.border))
    end
  else
    button = CreateFrame("Button", nil, parent)
  end
  pcall(button.EnableMouse, button, true)
  button:SetWidth(nav.button)
  button:SetHeight(nav.button)
  button:SetPoint(point, parent, point, x, nav.y)
  if not FL.flat then
    pcall(button.SetNormalTexture, button, art.normal)
    pcall(button.SetPushedTexture, button, art.pushed)
    pcall(button.SetDisabledTexture, button, art.disabled)
  end
  if not FL.flat and pcall(button.SetHighlightTexture, button, t.texture.pageHighlight) then
    local ok, region = pcall(button.GetHighlightTexture, button)
    if ok and region then pcall(region.SetBlendMode, region, "ADD") end
  end
  button:SetScript("OnClick", onClick)
  return button
end

function FL.BuildFlyout()
  local t = FL.Token()
  local f = t.flyout
  local flyout = CreateFrame("Frame", nil, FL.overlay)
  pcall(flyout.SetFrameStrata, flyout, "HIGH")
  flyout:SetAllPoints(FL.overlay)
  pcall(flyout.EnableMouse, flyout, false)

  local highlight
  if FL.flat then
    highlight = CreateFrame("Frame", nil, flyout)
    U.CreateBackdrop(highlight, {
      background = { 0, 0, 0, 0 }, border = M.color.accent,
    })
  else
    highlight = flyout:CreateTexture(nil, "OVERLAY")
    highlight:SetTexture(t.texture.highlight)
  end
  highlight:SetWidth(f.highlight.size)
  highlight:SetHeight(f.highlight.size)
  if not FL.flat then
    pcall(highlight.SetTexCoord, highlight, f.highlight.coords[1],
          f.highlight.coords[2], f.highlight.coords[3], f.highlight.coords[4])
  end
  flyout.highlight = highlight

  local buttons = CreateFrame("Frame", nil, flyout)
  pcall(buttons.SetFrameStrata, buttons, "HIGH")
  pcall(buttons.EnableMouse, buttons, true)
  pcall(buttons.SetClampedToScreen, buttons, true)
  buttons.bgs = {}
  buttons.items = {}
  flyout.buttons = buttons

  local nav = CreateFrame("Frame", nil, flyout)
  pcall(nav.SetFrameStrata, nav, "HIGH")
  pcall(nav.EnableMouse, nav, true)
  nav:SetWidth(f.nav.width)
  nav:SetHeight(f.nav.height)
  nav:SetPoint("TOPLEFT", buttons, "BOTTOMLEFT", f.nav.x, 0)
  if FL.flat then
    U.CreateBackdrop(nav, {
      background = { 0.02, 0.02, 0.02, 0.96 }, border = M.color.border,
    })
  else
    local navBg = nav:CreateTexture(nil, "BACKGROUND")
    navBg:SetTexture(t.texture.flyout)
    navBg:SetAllPoints(nav)
    pcall(navBg.SetTexCoord, navBg, f.nav.coords[1], f.nav.coords[2],
          f.nav.coords[3], f.nav.coords[4])
  end
  nav.prev = FL.PageButton(nav, t.texture.prevPage, "LEFT", f.nav.prevX,
                           function() FL.ChangePage(-1) end)
  nav.next = FL.PageButton(nav, t.texture.nextPage, "RIGHT", f.nav.nextX,
                           function() FL.ChangePage(1) end)
  nav.prevText = U.CreateLabel(nav, { size = M.fontSize.small,
                                      inherits = "GameFontHighlightSmall" })
  if nav.prevText then
    nav.prevText:SetPoint("LEFT", nav, "LEFT", f.nav.textX, f.nav.y)
    nav.prevText:SetText(U.L("EQUIPFLYOUT_PREVIOUS"))
  end
  nav.nextText = U.CreateLabel(nav, { size = M.fontSize.small,
                                      inherits = "GameFontHighlightSmall" })
  if nav.nextText then
    nav.nextText:SetPoint("RIGHT", nav, "RIGHT", f.nav.nextTextX, f.nav.y)
    nav.nextText:SetText(U.L("EQUIPFLYOUT_NEXT"))
  end
  flyout.nav = nav

  flyout:Hide()
  FL.flyout = flyout
end

-- PaperDollFrameItemFlyout_GetItems + _PostGetItems.
function FL.Entries(slot)
  local ES = U.EquipmentSets
  local list = {}
  if ES.Equipped(slot) then table.insert(list, { special = FL.SPECIAL.intoBags }) end
  local pane = U.CharacterEquipmentPane
  if pane and pane.OffersIgnore and pane.OffersIgnore() then
    if ES.IsIgnored(slot) then
      table.insert(list, 1, { special = FL.SPECIAL.unignore })
    else
      table.insert(list, 1, { special = FL.SPECIAL.ignore })
    end
  end
  local items = ES.ItemsForSlot(slot)
  local i
  for i = 1, table.getn(items) do table.insert(list, items[i]) end
  return list
end

function FL.PaintButton(button, entry)
  local t = FL.Token()
  button.entry = entry
  if entry.special then
    if FL.flat then
      -- The glyph sits on the button's own flat fill; the icon is hidden
      -- rather than tinted, so a later item on this pooled button is not
      -- drawn through a dark vertex colour.
      pcall(button.icon.Hide, button.icon)
      if button.glyph then
        button.glyph:SetText(entry.special == FL.SPECIAL.intoBags and "B" or
                             entry.special == FL.SPECIAL.ignore and "X" or "+")
        button.glyph:Show()
      end
    else
      local art = entry.special == FL.SPECIAL.intoBags and t.texture.intoBags or
                  entry.special == FL.SPECIAL.ignore and t.texture.ignoreSlot or
                  t.texture.unignore
      button.icon:SetTexture(art)
    end
    if FL.flat then
      button.flatBorder = M.color.border
      U.SetBorderColor(button, M.Unpack(M.color.border))
    else
      U.SetItemQualityGlow(button, nil)
    end
  else
    local texture, _, _, quality = U.ContainerSlotInfo(entry.bag, entry.slot)
    button.icon:SetTexture(texture or U.EquipmentSets.IconPath(nil))
    pcall(button.icon.Show, button.icon)
    if button.glyph then button.glyph:Hide() end
    if FL.flat then
      button.flatBorder = U.ItemQualityColor(quality) or M.color.border
      U.SetBorderColor(button, M.Unpack(button.flatBorder))
    else
      U.SetItemQualityGlow(button, quality)
    end
  end
  button:Show()
end

-- EquipmentFlyout_Show / _UpdateItems for the open slot.
function FL.Update()
  local slot = FL.open
  local holder = slot and FL.holders[slot]
  if not holder or not FL.flyout then return end
  local t = FL.Token()
  local f = t.flyout
  FL.entries = FL.Entries(slot)
  local total = table.getn(FL.entries)
  if total == 0 then return FL.Close() end

  local perPage = f.perRow * f.maxRows
  local maxPage = math.ceil(total / perPage)
  FL.page = math.max(1, math.min(FL.page, maxPage))
  local offset = (FL.page - 1) * perPage
  local shown = math.min(perPage, total - offset)
  -- Past the first page the frame keeps a full page, for the navigation bar.
  local count = FL.page == 1 and shown or perPage

  local buttons = FL.flyout.buttons
  local i
  for i = 1, math.max(shown, table.getn(buttons.items)) do
    if i <= shown then
      local button = buttons.items[i] or FL.BuildButton(i)
      FL.PaintButton(button, FL.entries[offset + i])
    elseif buttons.items[i] then
      buttons.items[i].entry = nil
      buttons.items[i]:Hide()
    end
  end

  local nav = FL.flyout.nav
  FL.SetShown(nav, maxPage > 1)
  if maxPage > 1 then
    if FL.page > 1 then nav.prev:Enable() else nav.prev:Disable() end
    if FL.page < maxPage then nav.next:Enable() else nav.next:Disable() end
  end

  local across = math.min(count, f.perRow)
  pcall(function()
    buttons:ClearAllPoints()
    if FL.VERTICAL[slot] then
      buttons:SetPoint("TOPLEFT", holder.popout, "BOTTOMLEFT", 0, 0)
    else
      buttons:SetPoint("TOPLEFT", holder.popout, "TOPRIGHT", 0, f.anchorY)
    end
    -- Retail's art carries its own right cap; the flat panel needs the
    -- border on both sides so the last item is not flush with its outline.
    buttons:SetWidth(across * f.item + (across - 1) * f.xGap +
                     f.border * (FL.flat and 2 or 1))
    buttons:SetHeight(f.height + math.floor((count - 1) / f.perRow) * f.rowStep)
    FL.flyout.highlight:ClearAllPoints()
    FL.flyout.highlight:SetPoint("LEFT", holder, "LEFT", f.highlight.x, 0)
  end)
  pcall(FL.flyout.SetFrameLevel, FL.flyout, FL.Dimension(holder.popout, "GetFrameLevel") + 1)
  pcall(buttons.SetFrameLevel, buttons, FL.Dimension(FL.flyout, "GetFrameLevel") + 1)
  pcall(nav.SetFrameLevel, nav, FL.Dimension(FL.flyout, "GetFrameLevel") + 1)
  for i = 1, shown do
    pcall(buttons.items[i].SetFrameLevel, buttons.items[i],
          FL.Dimension(buttons, "GetFrameLevel") + 1)
  end
  FL.LayoutBackground(count)
  FL.flyout:Show()
  buttons:Show()
end

function FL.ChangePage(delta)
  FL.page = FL.page + delta
  FL.Update()
end

function FL.Close()
  local was = FL.open
  FL.open = nil
  FL.locked = false
  FL.page = 1
  if FL.flyout then FL.flyout:Hide() end
  FL.HideTooltip()
  if was and FL.holders[was] then FL.PaintPopout(FL.holders[was]) end
end

-- EquipmentFlyoutPopoutButton_OnClick.
function FL.Toggle(slot)
  if FL.open == slot and FL.locked then return FL.Close() end
  local previous = FL.open
  FL.open = slot
  FL.locked = true
  FL.page = 1
  if previous and FL.holders[previous] then FL.PaintPopout(FL.holders[previous]) end
  FL.PaintPopout(FL.holders[slot])
  FL.Update()
end

-- PaperDollFrameItemFlyoutButton_OnClick, then EquipmentFlyoutButton_OnClick's
-- hide for a locked flyout.
function FL.Click(button)
  local entry = button.entry
  local slot = FL.open
  local ES = U.EquipmentSets
  if not entry or not slot then return end
  if entry.special == FL.SPECIAL.ignore or entry.special == FL.SPECIAL.unignore then
    ES.IgnoreSlot(slot, entry.special == FL.SPECIAL.ignore)
    FL.Update()
    return
  end
  if FL.InCombat() and not ES.COMBAT[slot] then
    U.Print(U.L("EQUIPSET_COMBAT_SLOT"))
    return
  end
  if entry.special == FL.SPECIAL.intoBags then ES.Unequip(slot)
  else ES.EquipFrom(slot, entry) end
  FL.Close()
end

function FL.QueueRefresh()
  if FL.open then U.DeferOnce(FL.REFRESH, FL.Update) end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
-- The pane shows (true) or hides (false): the arrows and ignored marks follow
-- it, and the flyout closes with it.
function FL.SetActive(active)
  if not FL.overlay then return end
  FL.active = active and true or false
  if not FL.active then
    FL.Close()
    FL.overlay:Hide()
    return
  end
  if not FL.Measure() then
    FL.overlay:Hide()
    return
  end
  FL.overlay:Show()
  FL.PaintMarks()
end

function FL.Build(frame)
  FL.flat = type(U.GetActiveThemeStyle) == "function" and
            U.GetActiveThemeStyle() == "modern"
  FL.frame = frame
  local overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(frame)
  pcall(overlay.EnableMouse, overlay, false)
  FL.overlay = overlay
  local id
  for id in pairs(FL.SLOTS) do FL.BuildHolder(id) end
  FL.BuildFlyout()
  overlay:Hide()

  U.EquipmentSets.OnChange(function()
    FL.PaintMarks()
    FL.QueueRefresh()
  end)
  U.RegisterEvent("BAG_UPDATE", FL.QueueRefresh)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", FL.QueueRefresh)
end

function U.BuildCharacterFlyout(frame)
  if FL.overlay then return true end
  if not frame or not U.EquipmentSets then return false end
  local ok, err = pcall(FL.Build, frame)
  if not ok then
    U.Error("character flyout: " .. tostring(err))
    if FL.overlay then pcall(FL.overlay.Hide, FL.overlay) end
    FL.overlay = nil
    return false
  end
  return true
end
