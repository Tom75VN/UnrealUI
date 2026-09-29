-- unrealUI :: modules/characterreputation.lua
--
-- The Character window's Reputation page under the `character` Modern WoW
-- surface (user request, 2026-09-29): Retail's ReputationFrame
-- (Blizzard_UIPanels_Game/Mainline/ReputationFrame.xml/.lua, RetailFrameXML
-- 12.1.0.69933) inside the housing's collapsed Inset -- Options_ListExpand
-- headers, 22-unit faction rows with the line highlight and
-- ReputationBarTemplate -- and ReputationDetailFrame beside the window when a
-- faction is clicked. Tokens: M.modernWow.reputation.
--
-- Entry point only: modules/character.lua's StyleReputationTab calls
-- U.BuildCharacterReputation and keeps its own restyle if this returns false.
--
-- The list and the detail window are addon-owned. The native rows cannot draw
-- this layout, and the native detail frame is filled only while its faction
-- is among the rows on screen, so both read GetFactionInfo themselves:
--   * ReputationBar1..N, ReputationHeader1..N, ReputationListScrollFrame,
--     FactionMouseOver, StandingMouseOver and ReputationDetailFrame are parked
--     undrawn in a hidden frame, by global name, the way the game settings
--     checkbox proxy parks a CheckButton. Nothing is unregistered or walked.
--   * Headers call Expand/CollapseFactionHeader directly
--     (knowledge: character.reputation_native_click_and_border_layer_noop).
--   * The detail checkboxes call FactionToggleAtWar, SetFactionInactive /
--     SetFactionActive and SetWatchedFactionIndex with the faction's row --
--     what the native checkboxes do with GetSelectedFaction(). Documented
--     (OFFICIAL_CLIENT_DOCUMENTATION), not yet runtime verified here.
--   * The selection is the faction's name, re-resolved on every refresh: a
--     collapse or an inactive toggle moves every row index after it.
--     SetSelectedFaction is not used; it cannot clear (index 0 clamps to 1).
-- Retail's row tooltips are GameTooltip and are omitted; the hover shows the
-- bar's progress, as Retail's does.
--
-- One top-level table (rules/unreal-ui.md, Lua local budget).

local U = UnrealUI
local M = U.media

local RP = {
  NAME = "UnrealUICharacterReputation",
  SCROLL = "UnrealUICharacterReputationScrollBar",
  CLOSE = "UnrealUICharacterReputationDetailClose",
  PARKED = { "ReputationListScrollFrame", "ReputationDetailFrame",
             "FactionMouseOver", "StandingMouseOver" },
  LABELS = { "ReputationFrameFactionLabel", "ReputationFrameStandingLabel" },
  frame = nil,
  panel = nil,
  list = nil,
  scroll = nil,
  detail = nil,
  rows = {},
  entries = {},
  offset = 1,
  maxOffset = 1,
  selected = nil,
}
U.CharacterReputation = RP

function RP.Token()
  return M.modernWow.reputation
end

function RP.Dimension(frame, method)
  if not frame or not frame[method] then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

function RP.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

function RP.Texture(parent, layer, path, coords)
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  if coords then pcall(texture.SetTexCoord, texture, M.Unpack(coords)) end
  return texture
end

function RP.Label(parent, size, color, justify, width)
  return U.CreateLabel(parent, {
    size = size, color = color, inherits = "GameFontNormal",
    justify = justify, width = width,
  })
end

function RP.Global(name)
  local value = U.G(name)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

-- ---------------------------------------------------------------------------
-- Faction data
-- ---------------------------------------------------------------------------
function RP.Collect()
  local entries = {}
  local count = U.G("GetNumFactions")
  local info = U.G("GetFactionInfo")
  if type(count) ~= "function" or type(info) ~= "function" then return entries end
  local ok, total = pcall(count)
  total = ok and tonumber(total) or 0
  local i
  for i = 1, total do
    local okInfo, name, description, standing, barMin, barMax, barValue,
          atWar, canWar, isHeader, collapsed, watched = pcall(info, i)
    if okInfo and type(name) == "string" then
      table.insert(entries, {
        index = i, name = name, description = description or "",
        standing = tonumber(standing) or 1,
        barMin = tonumber(barMin) or 0, barMax = tonumber(barMax) or 0,
        barValue = tonumber(barValue) or 0,
        atWar = atWar and true or false, canWar = canWar and true or false,
        header = isHeader and true or false,
        collapsed = collapsed and true or false,
        watched = watched and true or false,
      })
    end
  end
  return entries
end

function RP.Find(name)
  if not name then return nil end
  local i
  for i = 1, table.getn(RP.entries) do
    local entry = RP.entries[i]
    if not entry.header and entry.name == name then return entry end
  end
  return nil
end

function RP.Call(name, a1)
  local fn = U.G(name)
  if type(fn) ~= "function" then
    U.Debug("reputation: " .. name .. " unavailable")
    return false
  end
  local ok, err = pcall(fn, a1)
  if not ok then U.Error("reputation " .. name .. ": " .. tostring(err)) end
  return ok
end

-- Retail's InitializeBarForStandardReputation: the bar spans the standing's
-- own band, and Exalted (MAX_REPUTATION_REACTION) is drawn full with no
-- progress text.
function RP.BarValues(entry)
  local t = RP.Token().bar
  if entry.standing >= t.maxStanding then return 1, 1, nil end
  local range = entry.barMax - entry.barMin
  local value = entry.barValue - entry.barMin
  if range <= 0 then return 1, 1, nil end
  return range, value, string.format("%d / %d", value, range)
end

function RP.StandingText(entry)
  return RP.Global("FACTION_STANDING_LABEL" .. entry.standing) or ""
end

function RP.BarColor(entry)
  local colors = U.G("FACTION_BAR_COLORS")
  local color = type(colors) == "table" and colors[entry.standing]
  if type(color) == "table" and tonumber(color.r) then
    return color.r, color.g, color.b
  end
  color = RP.Token().bar.colors[entry.standing] or RP.Token().bar.colors[1]
  return color[1], color[2], color[3]
end

-- ---------------------------------------------------------------------------
-- Rows
--
-- One pooled Button draws either a header or a faction; the entry it is given
-- decides which pieces show.
-- ---------------------------------------------------------------------------
function RP.BuildHeaderPieces(row)
  local h = RP.Token().header
  local path = RP.Token().texture.listExpand
  row.headerLeft = RP.Texture(row, "ARTWORK", path, h.left)
  row.headerLeft:SetWidth(h.leftWidth)
  row.headerLeft:SetHeight(h.height)
  row.headerLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.headerRight = RP.Texture(row, "ARTWORK", path, h.collapsed)
  row.headerRight:SetWidth(h.rightWidth)
  row.headerRight:SetHeight(h.height)
  row.headerMiddle = RP.Texture(row, "ARTWORK", path, h.middle)
  row.headerMiddle:SetPoint("TOPLEFT", row.headerLeft, "TOPRIGHT", 0, 0)
  row.headerMiddle:SetPoint("BOTTOMRIGHT", row.headerRight, "BOTTOMLEFT", 0, 0)
  row.headerName = RP.Label(row, h.font, h.color, "LEFT")
end

function RP.BuildEntryPieces(row)
  local t = RP.Token()
  local e, b = t.entry, t.bar
  -- BackgroundHighlight: 6-unit sides, the right one mirrored, and the middle.
  local path = t.texture.highlight
  row.lightLeft = RP.Texture(row, "ARTWORK", path, e.side)
  row.lightLeft:SetWidth(e.sideWidth)
  row.lightLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.lightLeft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  row.lightRight = RP.Texture(row, "ARTWORK", path, e.sideFlipped)
  row.lightRight:SetWidth(e.sideWidth)
  row.lightRight:SetHeight(e.height)
  row.lightMiddle = RP.Texture(row, "ARTWORK", path, e.middle)
  row.lightMiddle:SetPoint("TOPLEFT", row.lightLeft, "TOPRIGHT", 0, 0)
  row.lightMiddle:SetPoint("BOTTOMRIGHT", row.lightRight, "BOTTOMLEFT", 0, 0)
  row.lights = { row.lightLeft, row.lightMiddle, row.lightRight }

  row.name = RP.Label(row, e.font, e.color, "LEFT")

  -- ReputationBarTemplate as three stacked frames, never same-layer siblings:
  -- the black Background on its own frame, the fill (ARTWORK) and frame
  -- pieces (OVERLAY) above it, the text above those. No BACKGROUND layer
  -- (rendering.background_layer_child_frame_not_drawn). The fill is sized
  -- from the bar's known width, not GetWidth, which a row built this frame
  -- may not have laid out yet; RP.SetBarFill crops it as a StatusBar does.
  local rowLevel = RP.Dimension(row, "GetFrameLevel")
  local bed = CreateFrame("Frame", nil, row)
  bed:SetWidth(b.width)
  bed:SetHeight(b.height)
  pcall(bed.SetFrameLevel, bed, rowLevel + 1)
  pcall(bed.EnableMouse, bed, false)
  local black = RP.Texture(bed, "ARTWORK", M.texture.plain)
  black:SetWidth(b.width - b.bedInset.x * 2)
  black:SetHeight(b.height - b.bedInset.y * 2)
  black:SetPoint("CENTER", bed, "CENTER", 0, 0)
  U.SetColor(black, M.Unpack(b.background))
  row.barBed = bed

  local bar = CreateFrame("Frame", nil, row)
  bar:SetWidth(b.width)
  bar:SetHeight(b.height)
  pcall(bar.SetFrameLevel, bar, rowLevel + 2)
  pcall(bar.EnableMouse, bar, false)
  bar.fill = RP.Texture(bar, "ARTWORK", t.texture.fill)
  bar.fill:SetHeight(b.height - b.inset.y * 2)
  bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", b.inset.x, -b.inset.y)
  local frame = RP.Texture(bar, "OVERLAY", t.texture.barFrame, b.frame.texCoord)
  frame:SetWidth(b.frame.width)
  frame:SetHeight(b.frame.height)
  frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
  -- The text rides a child frame so it always draws over the frame pieces.
  local holder = CreateFrame("Frame", nil, bar)
  holder:SetWidth(b.width)
  holder:SetHeight(b.height)
  pcall(holder.SetFrameLevel, holder, rowLevel + 3)
  bar.text = RP.Label(holder, b.font, b.textColor, "CENTER")
  if bar.text then bar.text:SetPoint("CENTER", holder, "CENTER", 0, 0) end
  bar.holder = holder
  row.bar = bar
end

-- Regions are placed on the row, from its LEFT edge at offsets computed from
-- the width it is given (`row.width`). The bar's three frames are NOT
-- anchored to the row at all: child frames anchored to a pooled row drew in
-- a column at the wrong place on the page's first layout and only moved into
-- their rows after a click re-laid the list (user screenshots, 2026-09-29),
-- while the row's own text and textures were right. They are anchored to the
-- list, which is sized and placed once at build, at the row's list offset
-- (`row.listX` / `row.listY`, set by RP.Layout). Retail's OnMouseDown /
-- OnMouseUp nudge the content 1 right and 1 down.
function RP.PlaceBar(row, push)
  local t = RP.Token()
  local b = t.bar
  local width = row.width or RP.rowWidth
  local height = row.entry and RP.EntryHeight(row.entry) or t.entry.height
  local x = (row.listX or 0) + width - b.rightInset - b.width + push
  local y = (row.listY or 0) + (height - b.height) / 2 + push
  local frames = { row.barBed, row.bar, row.bar.holder }
  local i
  for i = 1, table.getn(frames) do
    local target = frames[i]
    pcall(function()
      target:ClearAllPoints()
      target:SetPoint("TOPLEFT", RP.list, "TOPLEFT", x, -y)
    end)
  end
end

function RP.PlaceContent(row)
  local t = RP.Token()
  local width = row.width or RP.rowWidth
  local push = row.pressed and t.entry.press or 0
  RP.PlaceBar(row, push)
  pcall(function()
    row.headerRight:ClearAllPoints()
    row.headerRight:SetPoint("TOPLEFT", row, "TOPLEFT",
                             width - t.header.rightWidth, 0)
    row.lightRight:ClearAllPoints()
    row.lightRight:SetPoint("TOPLEFT", row, "TOPLEFT",
                            width - t.entry.sideWidth, 0)
    row.headerName:ClearAllPoints()
    row.headerName:SetPoint("LEFT", row, "LEFT", t.header.textX + push, -push)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", t.entry.nameX + push, -push)
  end)
end

function RP.SetBarFill(bar, fraction, r, g, b)
  local fill = bar and bar.fill
  if not fill then return end
  fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
  if fraction <= 0 then
    pcall(fill.Hide, fill)
    return
  end
  pcall(function()
    local token = RP.Token().bar
    fill:SetWidth((token.width - token.inset.x * 2) * fraction)
    fill:SetTexCoord(0, fraction, 0, 1)
    fill:Show()
  end)
  U.SetColor(fill, r, g, b, 1)
end

function RP.BuildRow(index)
  local ok, row = pcall(CreateFrame, "Button", nil, RP.list)
  if not ok or not row then return nil end
  pcall(row.SetFrameLevel, row, RP.Dimension(RP.list, "GetFrameLevel") + 2)
  pcall(row.EnableMouse, row, true)
  RP.BuildHeaderPieces(row)
  RP.BuildEntryPieces(row)
  RP.PlaceContent(row)

  row:SetScript("OnEnter", function()
    row.hover = true
    RP.PaintRow(row)
  end)
  row:SetScript("OnLeave", function()
    row.hover = false
    row.pressed = false
    RP.PlaceContent(row)
    RP.PaintRow(row)
  end)
  row:SetScript("OnMouseDown", function()
    row.pressed = true
    RP.PlaceContent(row)
  end)
  row:SetScript("OnMouseUp", function()
    row.pressed = false
    RP.PlaceContent(row)
  end)
  row:SetScript("OnClick", function() RP.Click(row) end)
  RP.rows[index] = row
  return row
end

function RP.PaintRow(row)
  local entry = row.entry
  if not entry then return end
  local t = RP.Token()
  if entry.header then
    if row.headerName then
      pcall(row.headerName.SetTextColor, row.headerName,
            M.Unpack(row.hover and t.header.hoverColor or t.header.color))
    end
    return
  end

  -- RefreshBackgroundHighlightOpacity / Color.
  local a = t.entry.highlight
  local selected = RP.selected == entry.name
  local alpha
  if entry.atWar then
    alpha = (selected and a.warSelected) or (row.hover and a.warHover) or a.war
  else
    alpha = (selected and a.selected) or (row.hover and a.hover) or 0
  end
  local color = entry.atWar and t.entry.warColor or t.entry.highlightColor
  local i
  for i = 1, table.getn(row.lights) do
    local light = row.lights[i]
    U.SetColor(light, color[1], color[2], color[3], alpha)
    RP.SetShown(light, alpha > 0)
  end

  -- TryShowBarProgressText on hover, the standing otherwise.
  local text = row.hover and row.progress or row.standing
  if row.bar.text then pcall(row.bar.text.SetText, row.bar.text, text or "") end
end

function RP.FillRow(row, entry)
  local t = RP.Token()
  row.entry = entry
  local header = entry.header
  local height = header and t.header.height or t.entry.height
  local indent = header and 0 or t.entry.indent
  row.width = RP.rowWidth - indent
  pcall(function()
    row:SetWidth(row.width)
    row:SetHeight(height)
  end)
  RP.PlaceContent(row)
  RP.SetShown(row.headerLeft, header)
  RP.SetShown(row.headerMiddle, header)
  RP.SetShown(row.headerRight, header)
  RP.SetShown(row.headerName, header)
  RP.SetShown(row.name, not header)
  RP.SetShown(row.bar, not header)
  RP.SetShown(row.barBed, not header)
  if header then
    local i
    for i = 1, table.getn(row.lights) do RP.SetShown(row.lights[i], false) end
    pcall(row.headerRight.SetTexCoord, row.headerRight,
          M.Unpack(entry.collapsed and t.header.collapsed or t.header.expanded))
    if row.headerName then pcall(row.headerName.SetText, row.headerName, entry.name) end
    RP.PaintRow(row)
    return
  end

  if row.name then pcall(row.name.SetText, row.name, entry.name) end
  local range, value, progress = RP.BarValues(entry)
  local r, g, b = RP.BarColor(entry)
  RP.SetBarFill(row.bar, value / range, r, g, b)
  row.standing = RP.StandingText(entry)
  row.progress = progress or row.standing
  RP.PaintRow(row)
end

function RP.Click(row)
  local entry = row.entry
  if not entry then return end
  if entry.header then
    RP.Call(entry.collapsed and "ExpandFactionHeader" or "CollapseFactionHeader",
            entry.index)
  elseif RP.selected == entry.name then
    RP.selected = nil
  else
    RP.selected = entry.name
  end
  RP.Refresh()
end

-- ---------------------------------------------------------------------------
-- Virtual list: Retail's linear view, `spacing` between rows.
-- ---------------------------------------------------------------------------
function RP.EntryHeight(entry)
  local t = RP.Token()
  return entry.header and t.header.height or t.entry.height
end

-- The last first-entry that still fills the list to its bottom.
function RP.MaxOffset()
  local spacing = RP.Token().scroll.spacing
  local used = 0
  local i
  for i = table.getn(RP.entries), 1, -1 do
    if used > 0 then used = used + spacing end
    used = used + RP.EntryHeight(RP.entries[i])
    if used > RP.capacity then return math.min(i + 1, table.getn(RP.entries)) end
  end
  return 1
end

function RP.Layout()
  local t = RP.Token()
  RP.maxOffset = RP.MaxOffset()
  RP.offset = math.max(1, math.min(RP.offset, RP.maxOffset))
  local y, used, i = 0, 0, RP.offset
  while i <= table.getn(RP.entries) do
    local entry = RP.entries[i]
    local height = RP.EntryHeight(entry)
    if y + height > RP.capacity then break end
    used = used + 1
    local row = RP.rows[used] or RP.BuildRow(used)
    if row then
      local indent = entry.header and 0 or t.entry.indent
      pcall(function()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", RP.list, "TOPLEFT", indent, -y)
      end)
      row.listX, row.listY = indent, y
      RP.FillRow(row, entry)
      pcall(row.Show, row)
    end
    y = y + height + t.scroll.spacing
    i = i + 1
  end
  for i = used + 1, table.getn(RP.rows) do
    RP.rows[i].entry = nil
    RP.rows[i].hover = false
    pcall(RP.rows[i].Hide, RP.rows[i])
  end
  RP.visibleCount = used
  RP.LayoutScroll()
end

function RP.LayoutScroll()
  local scroll = RP.scroll
  if not scroll then return end
  local scrollable = RP.maxOffset > 1
  RP.SetShown(scroll.bar, scrollable)
  RP.syncing = true
  pcall(scroll.bar.SetMinMaxValues, scroll.bar, 1, RP.maxOffset)
  pcall(scroll.bar.SetValue, scroll.bar, RP.offset)
  RP.syncing = false
  if not scrollable then return end
  if scroll.up then
    if RP.offset > 1 then pcall(scroll.up.Enable, scroll.up)
    else pcall(scroll.up.Disable, scroll.up) end
  end
  if scroll.down then
    if RP.offset < RP.maxOffset then pcall(scroll.down.Enable, scroll.down)
    else pcall(scroll.down.Disable, scroll.down) end
  end
  if type(U.SetModernWowScrollbarProportion) == "function" then
    U.SetModernWowScrollbarProportion(scroll.bar, RP.visibleCount or 0,
                                      table.getn(RP.entries))
  end
end

function RP.ReadScroll()
  local bar = RP.scroll and RP.scroll.bar
  if not bar or RP.syncing then return end
  local ok, value = pcall(bar.GetValue, bar)
  value = ok and tonumber(value) or nil
  if not value then return end
  value = math.max(1, math.min(RP.maxOffset, math.floor(value + 0.5)))
  if value == RP.offset then return end
  RP.offset = value
  RP.Layout()
end

function RP.Wheel(direction)
  if RP.maxOffset <= 1 then return end
  local target = math.max(1, math.min(RP.maxOffset, RP.offset - direction))
  if target == RP.offset then return end
  RP.offset = target
  RP.Layout()
end

-- MinimalScrollBar at the ScrollBox's TOPRIGHT +x, -barTop down to its
-- BOTTOMRIGHT +x, +barBottom; the shared bar's steppers take `arrowPad` at
-- each end, as on the stats pane.
function RP.BuildScroll(boxRight, boxTop, boxHeight)
  local s = RP.Token().scroll
  local height = boxHeight - s.barTop - s.barBottom - s.arrowPad * 2
  if height < 1 then return end
  local ok, bar = pcall(CreateFrame, "Slider", RP.SCROLL, RP.panel,
                        "UIPanelScrollBarTemplate")
  if not ok or not bar then return end
  -- The template's OnValueChanged scrolls its parent as a ScrollFrame; this
  -- list's parent is a plain Frame (modules/characterstatspanel.lua).
  pcall(bar.SetScript, bar, "OnValueChanged", nil)
  pcall(function()
    bar:SetFrameLevel(RP.Dimension(RP.list, "GetFrameLevel") + 3)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(s.column)
    bar:SetHeight(height)
    bar:SetPoint("TOP", RP.panel, "TOPLEFT", boxRight + s.x + s.barWidth / 2,
                 -(boxTop + s.barTop + s.arrowPad))
    bar:SetMinMaxValues(1, 1)
    bar:SetValueStep(1)
    bar:SetValue(1)
  end)
  local up = U.G(RP.SCROLL .. "ScrollUpButton")
  local down = U.G(RP.SCROLL .. "ScrollDownButton")
  if up then up:SetScript("OnClick", function() RP.Wheel(1) end) end
  if down then down:SetScript("OnClick", function() RP.Wheel(-1) end) end
  RP.scroll = { bar = bar, up = up, down = down }
  if type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, { onChange = RP.ReadScroll })
  end
  bar:SetScript("OnValueChanged", RP.ReadScroll)
end

-- ---------------------------------------------------------------------------
-- Detail window: ReputationDetailFrame in DialogBorderTemplate.
-- ---------------------------------------------------------------------------
function RP.BuildDialogBorder(detail)
  local t = RP.Token()
  local d, tex = t.dialog, t.texture
  -- Bg on ARTWORK, the parchment on OVERLAY above it: nothing here uses the
  -- BACKGROUND layer (rendering.background_layer_child_frame_not_drawn).
  local bg = RP.Texture(detail, "ARTWORK", tex.dialogBackground)
  bg:SetPoint("TOPLEFT", detail, "TOPLEFT", d.inset, -d.inset)
  bg:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -d.inset, d.inset)

  -- The metal sits over the parchment's edge, as the Border frame does.
  local border = CreateFrame("Frame", nil, detail)
  border:SetAllPoints(detail)
  pcall(border.SetFrameLevel, border, RP.Dimension(detail, "GetFrameLevel") + 1)
  local function Corner(coords, point)
    local piece = RP.Texture(border, "OVERLAY", tex.dialog, coords)
    piece:SetWidth(d.size)
    piece:SetHeight(d.size)
    piece:SetPoint(point, border, point, 0, 0)
    return piece
  end
  local tl = Corner(d.topLeft, "TOPLEFT")
  local tr = Corner(d.topRight, "TOPRIGHT")
  local bl = Corner(d.bottomLeft, "BOTTOMLEFT")
  local br = Corner(d.bottomRight, "BOTTOMRIGHT")
  local edge = RP.Texture(border, "OVERLAY", tex.dialog, d.top)
  edge:SetHeight(d.size)
  edge:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
  edge:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
  edge = RP.Texture(border, "OVERLAY", tex.dialog, d.bottom)
  edge:SetHeight(d.size)
  edge:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
  edge = RP.Texture(border, "OVERLAY", tex.dialogVertical, d.left)
  edge:SetWidth(d.size)
  edge:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
  edge:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
  edge = RP.Texture(border, "OVERLAY", tex.dialogVertical, d.right)
  edge:SetWidth(d.size)
  edge:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
  return border
end

function RP.CheckLabelColor(key, enabled)
  local d = RP.Token().detail
  if not enabled then return d.disabledColor end
  if key == "atWar" then return d.warColor end
  return d.labelColor
end

-- The game settings checkbox (rules/unreal-ui-design.md), centred in the cell
-- Retail's 26-unit CheckButton takes, its label `labelGap` past that cell.
function RP.BuildCheck(detail, key, text, width, onChange)
  local c = RP.Token().detail.check
  local control = U.CreateCheckbox(detail, {
    name = RP.NAME .. key, text = text or "", size = c.size,
    textWidth = width, onChange = onChange,
  })
  if not control then return nil end
  control.key = key
  local level = RP.Dimension(detail, "GetFrameLevel") + 3
  pcall(control.box.SetFrameLevel, control.box, level)
  if control.label then
    pcall(function()
      control.label:ClearAllPoints()
      control.label:SetPoint("LEFT", control.box, "RIGHT",
                             (c.cell - c.size) / 2 + c.labelGap, 0)
    end)
  end
  -- Colour only: the label was created at its size, and a font-object rebind
  -- on a fixed-width label can centre its text (U.FitLineToText, stockui).
  local function PaintLabel(ctl)
    if ctl.label then
      pcall(ctl.label.SetTextColor, ctl.label,
            M.Unpack(RP.CheckLabelColor(key, ctl.enabled)))
    end
  end
  if type(U.StyleGameSettingsCheckbox) ~= "function" or
     not U.StyleGameSettingsCheckbox(control, PaintLabel) then
    local apply = control.Apply
    control.Apply = function() apply() PaintLabel(control) end
    control.Apply()
  end
  return control
end

function RP.PlaceCheck(control, detail, x, y)
  local c = RP.Token().detail.check
  local inset = (c.cell - c.size) / 2
  control.SetPoint("TOPLEFT", detail, "TOPLEFT", x + inset, -(y + inset))
end

function RP.BuildDetail(frame)
  local t = RP.Token()
  local d = t.detail
  local w = M.modernWow.characterWindow
  local detail = CreateFrame("Frame", RP.NAME .. "Detail", frame)
  detail:SetWidth(d.width)
  detail:SetHeight(d.height)
  detail:SetPoint("TOPLEFT", frame, "TOPLEFT", w.left + w.width, -(w.top + d.y))
  pcall(detail.SetFrameLevel, detail, RP.Dimension(frame, "GetFrameLevel") + 10)
  pcall(detail.EnableMouse, detail, true)

  local parchment = RP.Texture(detail, "OVERLAY", t.texture.parchment)
  parchment:SetWidth(d.parchment.width)
  parchment:SetHeight(d.parchment.height)
  parchment:SetPoint("TOPLEFT", detail, "TOPLEFT", d.parchment.x, -d.parchment.y)
  local border = RP.BuildDialogBorder(detail)
  -- On the metal's frame, so it draws over the parchment's lower edge.
  local divider = RP.Texture(border, "OVERLAY", t.texture.divider)
  divider:SetWidth(d.divider.width)
  divider:SetHeight(d.divider.height)
  divider:SetPoint("TOPLEFT", detail, "TOPLEFT", d.divider.x, -d.divider.y)

  local text = CreateFrame("Frame", nil, detail)
  text:SetAllPoints(detail)
  pcall(text.SetFrameLevel, text, RP.Dimension(border, "GetFrameLevel") + 1)
  detail.title = RP.Label(text, d.title.font, d.title.color, "LEFT", d.title.width)
  if detail.title then
    detail.title:SetPoint("TOPLEFT", detail, "TOPLEFT", d.title.x, -d.title.y)
  end
  detail.description = RP.Label(text, d.description.font, d.description.color,
                                "LEFT", d.description.width)
  if detail.description and detail.title then
    detail.description:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0,
                                -d.description.gap)
  end

  local close = U.CreateButton(detail, {
    name = RP.CLOSE, text = "", width = d.close.size, height = d.close.size,
    onClick = function() RP.Select(nil) end,
  })
  if close then
    if close.label then pcall(close.label.Hide, close.label) end
    pcall(close.SetFrameLevel, close, RP.Dimension(text, "GetFrameLevel") + 1)
    close:SetPoint("CENTER", detail, "TOPRIGHT", -d.close.right, -d.close.top)
    if type(U.ModernWowDressCloseButton) == "function" then
      U.ModernWowDressCloseButton(RP.CLOSE)
    end
  end

  local c = d.check
  detail.atWar = RP.BuildCheck(detail, "atWar",
    RP.Global("AT_WAR") or RP.NativeText("ReputationDetailAtWarCheckBoxText"),
    c.atWarWidth, function() RP.ToggleAtWar() end)
  detail.inactive = RP.BuildCheck(detail, "inactive",
    RP.Global("MOVE_TO_INACTIVE") or RP.NativeText("ReputationDetailInactiveCheckBoxText"),
    c.inactiveWidth, function(value) RP.SetInactive(value) end)
  detail.watch = RP.BuildCheck(detail, "watch",
    RP.Global("SHOW_FACTION_ON_MAINSCREEN") or
    RP.NativeText("ReputationDetailMainScreenCheckBoxText"),
    c.watchWidth, function(value) RP.SetWatched(value) end)
  local cellRight = c.x + c.cell + c.labelGap
  if detail.atWar then RP.PlaceCheck(detail.atWar, detail, c.x, c.atWarY) end
  if detail.inactive then
    RP.PlaceCheck(detail.inactive, detail,
                  cellRight + c.atWarWidth + c.inactiveGap, c.atWarY)
  end
  if detail.watch then
    RP.PlaceCheck(detail.watch, detail, c.x, c.atWarY + c.cell - c.rowGap)
  end

  detail:Hide()
  RP.detail = detail
end

function RP.NativeText(name)
  local region = U.G(name)
  if not region or type(region.GetText) ~= "function" then return nil end
  local ok, text = pcall(region.GetText, region)
  return ok and type(text) == "string" and text or nil
end

function RP.RefreshDetail()
  local detail = RP.detail
  if not detail then return end
  local entry = RP.Find(RP.selected)
  if not entry then
    RP.selected = nil
    RP.SetShown(detail, false)
    return
  end
  if detail.title then pcall(detail.title.SetText, detail.title, entry.name) end
  if detail.description then
    pcall(detail.description.SetText, detail.description, entry.description)
  end
  if detail.atWar then
    detail.atWar.SetValue(entry.atWar)
    detail.atWar.SetEnabled(entry.canWar)
  end
  if detail.inactive then
    local inactive = false
    local fn = U.G("IsFactionInactive")
    if type(fn) == "function" then
      local ok, value = pcall(fn, entry.index)
      inactive = ok and value and value ~= 0 and true or false
    end
    detail.inactive.SetValue(inactive)
  end
  if detail.watch then detail.watch.SetValue(entry.watched) end
  RP.SetShown(detail, true)
end

function RP.Select(name)
  RP.selected = name
  RP.Refresh()
end

function RP.ToggleAtWar()
  local entry = RP.Find(RP.selected)
  if entry and entry.canWar then RP.Call("FactionToggleAtWar", entry.index) end
  RP.Refresh()
end

function RP.SetInactive(inactive)
  local entry = RP.Find(RP.selected)
  if entry then
    RP.Call(inactive and "SetFactionInactive" or "SetFactionActive", entry.index)
  end
  RP.Refresh()
end

function RP.SetWatched(watched)
  local entry = RP.Find(RP.selected)
  if entry then
    RP.Call("SetWatchedFactionIndex", watched and entry.index or 0)
    local update = U.G("ReputationWatchBar_Update")
    if type(update) == "function" then pcall(update) end
  end
  RP.Refresh()
end

-- ---------------------------------------------------------------------------
-- Refresh and the page's show / hide
-- ---------------------------------------------------------------------------
function RP.Refresh()
  if not RP.list then return end
  RP.entries = RP.Collect()
  RP.Layout()
  RP.RefreshDetail()
end

function RP.Park()
  if RP.parked then return end
  local ok, vault = pcall(CreateFrame, "Frame", nil, UIParent)
  if not ok or not vault then return end
  pcall(vault.Hide, vault)
  RP.vault = vault
  local names = {}
  local i
  for i = 1, table.getn(RP.PARKED) do table.insert(names, RP.PARKED[i]) end
  local count = tonumber(U.G("NUM_FACTIONS_DISPLAYED")) or 15
  for i = 1, count do
    table.insert(names, "ReputationBar" .. i)
    table.insert(names, "ReputationHeader" .. i)
  end
  for i = 1, table.getn(names) do
    local native = U.G(names[i])
    if native and type(native.SetParent) == "function" then
      pcall(native.SetParent, native, vault)
    end
  end
  for i = 1, table.getn(RP.LABELS) do
    local label = U.G(RP.LABELS[i])
    if label then
      pcall(label.Hide, label)
      pcall(label.SetAlpha, label, 0)
    end
  end
  RP.parked = true
end

function RP.OnShow()
  RP.Park()
  RP.SetShown(RP.panel, true)
  RP.Refresh()
end

-- Retail's detail frame is the page's child and clears the selection when it
-- hides, so the selection ends with the page.
function RP.OnHide()
  RP.SetShown(RP.panel, false)
  RP.SetShown(RP.detail, false)
  RP.selected = nil
  local i
  for i = 1, table.getn(RP.rows) do RP.rows[i].hover = false end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function RP.Build(frame)
  local page = U.G("ReputationFrame")
  if not page then error("ReputationFrame unavailable") end
  local t = RP.Token()
  local s = t.scroll
  local w = M.modernWow.characterWindow
  RP.frame = frame

  -- The housing's collapsed Inset, as offsets from CharacterFrame's top-left.
  local insetLeft = w.left + w.inset.left
  local insetTop = w.top + w.inset.top
  local insetWidth = w.width - w.inset.left - w.inset.right
  local insetHeight = w.height - w.inset.top - w.inset.bottom

  local panel = CreateFrame("Frame", RP.NAME, frame)
  panel:SetWidth(insetWidth)
  panel:SetHeight(insetHeight)
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", insetLeft, -insetTop)
  pcall(panel.SetFrameLevel, panel, RP.Dimension(frame, "GetFrameLevel") + 2)
  pcall(panel.EnableMouse, panel, true)
  RP.panel = panel

  -- ScrollBox and its padded content, in panel coordinates.
  local boxWidth = insetWidth - s.left - s.right
  local boxHeight = insetHeight - s.top - s.bottom
  local list = CreateFrame("Frame", nil, panel)
  list:SetWidth(boxWidth - s.padding * 2)
  list:SetHeight(boxHeight - s.padding * 2)
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", s.left + s.padding, -(s.top + s.padding))
  pcall(list.SetFrameLevel, list, RP.Dimension(panel, "GetFrameLevel") + 1)
  RP.list = list
  RP.capacity = boxHeight - s.padding * 2
  RP.rowWidth = boxWidth - s.padding * 2

  -- Built before the rows so it stays underneath them.
  if type(U.CreateWheelCatcher) == "function" then
    U.CreateWheelCatcher(list, RP.Wheel)
  end
  RP.BuildScroll(s.left + boxWidth, s.top, boxHeight)
  RP.BuildDetail(frame)
  panel:Hide()

  U.PostHookScript(page, "OnShow", RP.OnShow)
  U.PostHookScript(page, "OnHide", RP.OnHide)
  U.RegisterEvent("UPDATE_FACTION", function()
    local ok, shown = pcall(panel.IsShown, panel)
    if ok and shown then RP.Refresh() end
  end)
  local ok, shown = pcall(page.IsShown, page)
  if ok and shown then RP.OnShow() end
  return true
end

function U.BuildCharacterReputation(frame)
  if RP.panel then return true end
  if not frame or not M.modernWow or not M.modernWow.reputation then return false end
  local ok, err = pcall(RP.Build, frame)
  if not ok then
    U.Error("character reputation: " .. tostring(err))
    RP.SetShown(RP.panel, false)
    RP.SetShown(RP.detail, false)
    RP.panel = nil
    RP.list = nil
    return false
  end
  return true
end
