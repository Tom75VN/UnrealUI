-- unrealUI :: modules/professions.lua
--
-- The profession (crafting) window's complete `modern-wow` drawing path:
-- WoW-DragonflightUI's DFProfessionFrame (XML/ProfessionFrame.xml,
-- Mixin/ProfessionFrame.mixin.lua) rebuilt on this client for both the
-- TradeSkill window and the Craft window (Enchanting, Beast Training). A
-- metal-framed 778x525 window with the profession icon in the portrait ring,
-- the profession rank bar, a recipe list with collapsible category headers on
-- the left and the selected recipe's schematic -- icon, requirements and
-- reagents over the profession's background art -- on the right, with Create
-- All / count / Create underneath. Nothing here runs under any other theme,
-- and no other theme draws this window at all.
--
-- Mechanism is WORKING_SOURCE from DF-main, adapted to this client:
--
--  * DF-main overlays its own frame on TradeSkillFrame. Here the host is the
--    client's own TradeSkillFrame / CraftFrame, widened like
--    modules/talentsmodernwow.lua widens TalentFrame, so the native open,
--    close, Escape and panel placement are unchanged. Its stock art is
--    stripped once, before any addon region exists on it.
--  * The native list rows are never touched: a Lua touch of a native list row
--    has crashed this client (knowledge.json /
--    frames.friendsframe_row_touch_crashes_client). Everything the native
--    window draws inside the frame is covered instead, by one addon-owned
--    frame several levels above its children that takes the mouse, and every
--    row, button and label on it is addon-owned.
--  * All data comes from the TradeSkill and Crafting APIs
--    (documentation.json, DOCUMENTED_NOT_RUNTIME_VERIFIED): GetTradeSkillInfo
--    returns name, type, numAvailable, isExpanded; GetCraftInfo name,
--    subtext, type, numAvailable, isExpanded, training points. Every call is
--    guarded, so a missing one degrades rather than throws.
--  * The count box is a readout between two step buttons rather than
--    DF-main's EditBox: native text input is off limits
--    (rules/unreal-ui-design.md). There is no search box for the same reason.
--  * There is no mouse wheel for addon frames on this client
--    (knowledge.json / scripts.addon_wheel_binding_unavailable), so the list
--    scrolls with its arrow buttons and a click on its track.
--  * The rank bar is a plain texture cropped with SetTexCoord (a native
--    StatusBar does not lay out its fill here, statusbar knowledge), and its
--    DF-main mask is baked into the fill by tools/import_modern_wow_media.py.
--  * DF-main's profession tabs, favourites, filter menu, link button and
--    minimize button are omitted: switching profession casts a spell, which
--    is protected here, and the rest need an EditBox, a dropdown menu or chat
--    link insertion with no record on this client.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media
local PR = U.RegisterModule("professions")

local pw = {
  THEME = "modern-wow",
  SURFACE = "professions",
  enabled = false,
  windows = {},
  eventsInstalled = false,
  polling = false,
}

pw.KINDS = {
  {
    id = "trade",
    host = "TradeSkillFrame",
    close = "TradeSkillFrameCloseButton",
    update = "TradeSkillFrame_Update",
    count = "GetNumTradeSkills",
    selected = "GetTradeSkillSelectionIndex",
    select = "SelectTradeSkill",
    expand = "ExpandTradeSkillSubClass",
    collapse = "CollapseTradeSkillSubClass",
    icon = "GetTradeSkillIcon",
    numReagents = "GetTradeSkillNumReagents",
    reagent = "GetTradeSkillReagentInfo",
    tools = "GetTradeSkillTools",
    cooldown = "GetTradeSkillCooldown",
    link = "GetTradeSkillItemLink",
    made = "GetTradeSkillNumMade",
    tipRecipe = "SetTradeSkillItem",
    tipReagent = "SetTradeSkillItem",
    create = "DoTradeSkill",
    repeatable = true,
  },
  {
    id = "craft",
    host = "CraftFrame",
    close = "CraftFrameCloseButton",
    update = "CraftFrame_Update",
    count = "GetNumCrafts",
    selected = "GetCraftSelectionIndex",
    select = "SelectCraft",
    expand = "ExpandCraftSkillLine",
    collapse = "CollapseCraftSkillLine",
    icon = "GetCraftIcon",
    numReagents = "GetCraftNumReagents",
    reagent = "GetCraftReagentInfo",
    tools = "GetCraftSpellFocus",
    description = "GetCraftDescription",
    tipRecipe = "SetCraftSpell",
    tipReagent = "SetCraftItem",
    create = "DoCraft",
    repeatable = false,
  },
}

function pw.Token()
  return M.modernWow.professions
end

-- pcall on a client global; returns ok followed by its results.
function pw.Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, a, b)
end

function pw.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function pw.Level(object)
  if not object or not object.GetFrameLevel then return 1 end
  local ok, level = pcall(object.GetFrameLevel, object)
  return (ok and tonumber(level)) or 1
end

function pw.SetShown(object, shown)
  if not object then return end
  if shown then pcall(object.Show, object) else pcall(object.Hide, object) end
end

function pw.Frame(kind, parent, levelOffset, mouse)
  local ok, frame = pcall(CreateFrame, kind or "Frame", nil, parent)
  if not ok or not frame then return nil end
  if levelOffset then
    pcall(frame.SetFrameLevel, frame, pw.Level(parent) + levelOffset)
  end
  pcall(frame.EnableMouse, frame, mouse and true or false)
  return frame
end

function pw.Texture(parent, layer, path)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer or "ARTWORK")
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  return texture
end

-- One cell of the professions atlas, in texels.
function pw.AtlasCoords(texture, cell)
  local a = pw.Token().atlas
  if not texture or not cell then return end
  pcall(texture.SetTexCoord, texture, cell.left / a.width, cell.right / a.width,
        cell.top / a.height, cell.bottom / a.height)
end

function pw.Atlas(parent, layer, cell)
  local texture = pw.Texture(parent, layer, pw.Token().texture.atlas)
  pw.AtlasCoords(texture, cell)
  return texture
end

function pw.Place(region, relative, point, x, y, width, height)
  if not region then return end
  pcall(function()
    region:ClearAllPoints()
    if width then region:SetWidth(width) end
    if height then region:SetHeight(height) end
    region:SetPoint(point, relative, point, x, y)
  end)
end

function pw.Label(parent, size, color, justify, inherits)
  local label = U.CreateLabel(parent, {
    size = size or M.fontSize.normal,
    color = color,
    inherits = inherits or "GameFontNormal",
    justify = justify or "LEFT",
  })
  return label
end

function pw.SetText(label, text)
  if label then pcall(label.SetText, label, text or "") end
end

function pw.SetColor(label, color)
  if label then pcall(label.SetTextColor, label, M.Unpack(color)) end
end

function pw.TextWidth(label)
  if not label then return 0 end
  local ok, width = pcall(label.GetStringWidth, label)
  return (ok and tonumber(width)) or 0
end

-- ---------------------------------------------------------------------------
-- Client data
-- ---------------------------------------------------------------------------

-- One list row as name, type, numAvailable, isExpanded, subtext, training
-- points, and the raw type (the craft "used" type is not creatable). Craft
-- types are folded onto the TradeSkill set DF-main's difficulty icons use.
function pw.Info(win, index)
  if win.kind.id == "trade" then
    local ok, name, kind, available, expanded = pw.Call("GetTradeSkillInfo", index)
    if not ok or type(name) ~= "string" then return nil end
    return name, kind, tonumber(available) or 0, expanded, nil, 0, kind
  end

  local ok, name, sub, kind, available, expanded, points =
    pw.Call("GetCraftInfo", index)
  if not ok or type(name) ~= "string" then return nil end
  local raw = kind
  if kind == "used" then
    kind = "trivial"
  elseif kind == "none" then
    kind = "easy"
  end
  if sub == "" then sub = nil end
  return name, kind, tonumber(available) or 0, expanded, sub,
         tonumber(points) or 0, raw
end

-- Profession name, rank and maximum rank of the open window.
function pw.Line(win)
  local unknown = U.G("UNKNOWN")
  local ok, name, rank, maxRank
  if win.kind.id == "trade" then
    ok, name, rank, maxRank = pw.Call("GetTradeSkillLine")
  else
    ok, name, rank, maxRank = pw.Call("GetCraftDisplaySkillLine")
    if not ok or type(name) ~= "string" or name == "" or name == unknown then
      local nameOk, craftName = pw.Call("GetCraftName")
      if nameOk and type(craftName) == "string" and craftName ~= unknown then
        name = craftName
      end
    end
  end
  if type(name) ~= "string" or name == unknown then name = "" end
  return name, tonumber(rank) or 0, tonumber(maxRank) or 0
end

function pw.Selected(win)
  local ok, index = pw.Call(win.kind.selected)
  return (ok and tonumber(index)) or 0
end

-- Tools as DF-main's BuildColoredListString: red for a tool not carried.
-- Up to four name, hasItem pairs; Vanilla-era Lua has no select().
function pw.Tools(win, index)
  local ok, n1, h1, n2, h2, n3, h3, n4, h4 = pw.Call(win.kind.tools, index)
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

-- The colour of an item link, "|cAARRGGBB|H...".
function pw.LinkColor(link)
  if type(link) ~= "string" then return nil end
  local _, _, r, g, b = string.find(link, "|c%x%x(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, 1 }
end

function pw.Tip(owner, method, a, b)
  local tip = U.G("GameTooltip")
  if not tip or type(tip[method]) ~= "function" then return end
  pcall(tip.SetOwner, tip, owner, "ANCHOR_TOPLEFT")
  if b then
    pcall(tip[method], tip, a, b)
  else
    pcall(tip[method], tip, a)
  end
  pcall(tip.Show, tip)
end

function pw.HideTip()
  local tip = U.G("GameTooltip")
  if tip then pcall(tip.Hide, tip) end
end

-- ---------------------------------------------------------------------------
-- Window chrome (DF-main ButtonFrameTemplateNoPortrait + FrameBackgroundSolid)
-- ---------------------------------------------------------------------------
function pw.BuildChrome(win)
  local t = pw.Token()
  local tex = t.texture
  local f = t.frame
  local frame, cover, rim = win.frame, win.cover, win.rim

  local body = pw.Texture(cover, "BACKGROUND", tex.backgroundRock)
  if body then
    pcall(function()
      body:SetPoint("TOPLEFT", frame, "TOPLEFT", f.body.left, -f.body.top)
      body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -f.body.right, f.body.bottom)
    end)
  end

  local streak = pw.Texture(cover, "BORDER", tex.topStreak)
  if streak then
    pcall(function()
      local c = f.streak.texCoord
      streak:SetTexCoord(c[1], c[2], c[3], c[4])
      streak:SetHeight(f.streak.height)
      streak:SetPoint("TOPLEFT", frame, "TOPLEFT", f.streak.left, -f.streak.top)
      streak:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -f.streak.right, -f.streak.top)
    end)
  end

  -- The metal sits on the rim frame, above both panels, as DF-main's
  -- NineSlice sits above its RecipeList and SchematicForm.
  local function Piece(path, spec)
    local piece = pw.Texture(rim, "OVERLAY", path)
    if piece and spec.texCoord then
      local c = spec.texCoord
      pcall(piece.SetTexCoord, piece, c[1], c[2], c[3], c[4])
    end
    return piece
  end
  local function Corner(spec, point)
    local piece = Piece(tex.metalCorners, spec)
    pw.Place(piece, frame, point, spec.x, spec.y, spec.width, spec.height)
    return piece
  end
  local tl = Corner(f.cornerTopLeft, "TOPLEFT")
  local tr = Corner(f.cornerTopRight, "TOPRIGHT")
  local bl = Corner(f.cornerBottomLeft, "BOTTOMLEFT")
  local br = Corner(f.cornerBottomRight, "BOTTOMRIGHT")

  pcall(function()
    local top = Piece(tex.metalHorizontal, f.edgeTop)
    top:SetHeight(f.edgeTop.height)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)

    local bottom = Piece(tex.metalHorizontal, f.edgeBottom)
    bottom:SetHeight(f.edgeBottom.height)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    bottom:SetPoint("TOPRIGHT", br, "TOPLEFT", 0, 0)

    local left = Piece(tex.metalVertical, f.edgeLeft)
    left:SetWidth(f.edgeLeft.width)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)

    local right = Piece(tex.metalVertical, f.edgeRight)
    right:SetWidth(f.edgeRight.width)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
  end)

  -- Portrait: the profession icon over the stone disc, in DF-main's ring.
  local p = f.portrait
  local holder = pw.Frame("Frame", rim, 1, false)
  if holder then
    pcall(function()
      holder:SetWidth(p.ring)
      holder:SetHeight(p.ring)
      holder:SetPoint("CENTER", frame, "TOPLEFT", p.x + p.size / 2, p.y - p.size / 2)
    end)
    local disc = pw.Texture(holder, "BACKGROUND", tex.portraitBackground)
    pw.Place(disc, holder, "CENTER", 0, 0, t.portrait.discSize, t.portrait.discSize)
    win.portrait = pw.Texture(holder, "ARTWORK")
    pw.Place(win.portrait, holder, "CENTER", 0, 0,
             t.portrait.iconSize, t.portrait.iconSize)
    if win.portrait then
      pcall(win.portrait.SetTexCoord, win.portrait, 0.08, 0.92, 0.08, 0.92)
    end
    local ring = pw.Texture(holder, "OVERLAY", tex.portraitRing)
    if ring then
      local c = p.ringTexCoord
      pcall(ring.SetTexCoord, ring, c[1], c[2], c[3], c[4])
      pcall(ring.SetAllPoints, ring, holder)
    end
  end

  win.title = pw.Label(rim, M.fontSize.normal, t.titleColor, "CENTER")
  if win.title then
    pcall(win.title.SetPoint, win.title, "TOP", frame, "TOP", 0, -t.title.y)
  end
end

-- DF-main's RankFrame: dark track, fill, rim and the value centred on it.
function pw.BuildRank(win)
  local t = pw.Token()
  local r = t.rank
  local bar = pw.Frame("Frame", win.cover, t.levels.panel, false)
  if not bar then return end
  pw.Place(bar, win.frame, "TOPLEFT", r.x, -r.y, r.width, r.height)

  local track = pw.Atlas(bar, "BACKGROUND", t.cells.rankBackground)
  if track then pcall(track.SetAllPoints, track, bar) end

  win.rankFill = pw.Texture(bar, "ARTWORK")
  pw.Place(win.rankFill, bar, "TOPLEFT", r.fillX, -r.fillY, r.fillWidth, r.fillHeight)

  local border = pw.Atlas(bar, "OVERLAY", t.cells.rankBorder)
  if border then pcall(border.SetAllPoints, border, bar) end

  local textFrame = pw.Frame("Frame", bar, 1, false)
  if textFrame then
    pcall(textFrame.SetAllPoints, textFrame, bar)
    win.rankText = pw.Label(textFrame, M.fontSize.small, t.rankTextColor,
                            "CENTER", "GameFontHighlightSmall")
    if win.rankText and win.rankFill then
      pcall(win.rankText.SetPoint, win.rankText, "CENTER", win.rankFill, "CENTER", 0, 0)
    end
  end
  win.rankBar = bar
end

function pw.SetRank(win, rank, maxRank)
  local t = pw.Token()
  local fill = win.rankFill
  if not fill then return end
  local fraction = 0
  if maxRank > 0 then fraction = math.min(1, math.max(0, rank / maxRank)) end
  if fraction <= 0 then
    pcall(fill.Hide, fill)
  else
    pcall(function()
      fill:SetWidth(t.rank.fillWidth * fraction)
      fill:SetTexCoord(0, fraction, 0, 1)
      fill:Show()
    end)
  end
  pw.SetText(win.rankText, maxRank > 0 and (rank .. "/" .. maxRank) or "")
end

-- ---------------------------------------------------------------------------
-- Recipe list (DFProfessionFrameRecipeListTemplate)
-- ---------------------------------------------------------------------------
function pw.ListCapacity()
  local l = pw.Token().list
  local height = pw.Token().design.height - l.y - l.bottom
  return height - l.rowTop - l.rowBottom
end

function pw.RowWidth()
  local l = pw.Token().list
  return l.width - l.rowLeft - l.rowRight
end

function pw.EntryHeight(entry)
  local t = pw.Token()
  if entry.kind == "header" then return t.header.height end
  return t.recipe.height
end

function pw.OnRowEnter(win, row)
  local t = pw.Token()
  row.hovered = true
  if row.entry and row.entry.kind == "header" then
    pw.SetColor(row.headerLabel, t.headerHoverColor)
    pw.SetShown(row.collapseHover, true)
  elseif row.entry then
    pw.SetColor(row.label, t.recipeHoverColor)
    pw.SetColor(row.count, t.recipeHoverColor)
    pw.SetShown(row.highlight, not row.selected)
  end
end

function pw.OnRowLeave(win, row)
  local t = pw.Token()
  row.hovered = false
  pw.SetColor(row.headerLabel, t.headerColor)
  pw.SetShown(row.collapseHover, false)
  pw.SetColor(row.label, t.recipeColor)
  pw.SetColor(row.count, t.recipeColor)
  pw.SetShown(row.highlight, false)
end

function pw.OnRowClick(win, row)
  local entry = row.entry
  if not entry then return end
  if entry.kind == "header" then
    local method = entry.expanded and win.kind.collapse or win.kind.expand
    local ok, err = pw.Call(method, entry.index)
    if not ok and err then U.Error("professions " .. method .. ": " .. tostring(err)) end
  else
    if entry.index ~= pw.Selected(win) then win.count = 1 end
    local ok, err = pw.Call(win.kind.select, entry.index)
    if not ok and err then U.Error("professions select: " .. tostring(err)) end
  end
  pw.Queue(win)
end

function pw.BuildRow(win, index)
  local t = pw.Token()
  local h, r = t.header, t.recipe
  local width = pw.RowWidth()

  local row = pw.Frame("Button", win.list, 2, true)
  if not row then return nil end
  pcall(row.SetWidth, row, width)
  pcall(row.SetHeight, row, r.height)

  -- Category header: three atlas pieces, label, collapse glyph.
  row.headerLeft = pw.Atlas(row, "BACKGROUND", t.cells.headerLeft)
  pw.Place(row.headerLeft, row, "LEFT", 0, h.lift, h.pieceWidth, h.pieceHeight)
  row.headerRight = pw.Atlas(row, "BACKGROUND", t.cells.headerRight)
  pw.Place(row.headerRight, row, "RIGHT", 0, h.lift, h.pieceWidth, h.pieceHeight)
  row.headerMiddle = pw.Atlas(row, "BACKGROUND", t.cells.headerMiddle)
  if row.headerMiddle and row.headerLeft and row.headerRight then
    pcall(function()
      row.headerMiddle:SetPoint("TOPLEFT", row.headerLeft, "TOPRIGHT", 0, 0)
      row.headerMiddle:SetPoint("BOTTOMRIGHT", row.headerRight, "BOTTOMLEFT", 0, 0)
    end)
  end
  row.collapse = pw.Atlas(row, "ARTWORK", t.cells.expanded)
  pw.Place(row.collapse, row, "RIGHT", -h.collapseRight, h.lift,
           h.collapseWidth, h.collapseHeight)
  row.collapseHover = pw.Atlas(row, "OVERLAY", t.cells.expanded)
  if row.collapseHover and row.collapse then
    pcall(function()
      row.collapseHover:SetAllPoints(row.collapse)
      row.collapseHover:SetBlendMode("ADD")
      row.collapseHover:Hide()
    end)
  end
  row.headerLabel = pw.Label(row, M.fontSize.normal, t.headerColor)
  if row.headerLabel then
    pcall(function()
      row.headerLabel:SetPoint("LEFT", row, "LEFT", h.labelX, h.labelY)
      row.headerLabel:SetPoint("RIGHT", row, "RIGHT",
                               -(h.collapseRight + h.collapseWidth + 4), h.labelY)
      row.headerLabel:SetHeight(12)
    end)
  end
  row.headerRegions = { row.headerLeft, row.headerMiddle, row.headerRight,
                        row.collapse, row.headerLabel }

  -- Recipe: selection and hover bars, difficulty glyph, label and count.
  row.selectedBar = pw.Atlas(row, "BORDER", t.cells.selected)
  pw.Place(row.selectedBar, row, "CENTER", 0, -1, r.selectedWidth, r.selectedHeight)
  row.highlight = pw.Atlas(row, "BORDER", t.cells.highlight)
  pw.Place(row.highlight, row, "CENTER", 0, -1, r.highlightWidth, r.highlightHeight)
  if row.highlight then pcall(row.highlight.SetAlpha, row.highlight, r.highlightAlpha) end
  row.skill = pw.Texture(row, "ARTWORK", t.texture.atlas)
  pw.Place(row.skill, row, "LEFT", r.iconX, 0, r.iconWidth, r.iconHeight)
  row.label = pw.Label(row, M.fontSize.normal, t.recipeColor, "LEFT", "GameFontHighlight")
  if row.label then
    pcall(function()
      row.label:SetPoint("LEFT", row, "LEFT", r.labelX, 0)
      row.label:SetHeight(12)
    end)
  end
  row.count = pw.Label(row, M.fontSize.normal, t.recipeColor, "LEFT", "GameFontHighlight")
  if row.count and row.label then
    pcall(row.count.SetPoint, row.count, "LEFT", row.label, "RIGHT", r.countGap, 0)
  end
  row.recipeRegions = { row.skill, row.label, row.count }

  row:SetScript("OnEnter", function() pw.OnRowEnter(win, row) end)
  row:SetScript("OnLeave", function() pw.OnRowLeave(win, row) end)
  row:SetScript("OnClick", function() pw.OnRowClick(win, row) end)

  win.rows[index] = row
  return row
end

function pw.FillRow(win, row, entry, selectedIndex)
  local t = pw.Token()
  row.entry = entry
  local header = entry.kind == "header"
  local i
  for i = 1, table.getn(row.headerRegions) do
    pw.SetShown(row.headerRegions[i], header)
  end
  for i = 1, table.getn(row.recipeRegions) do
    pw.SetShown(row.recipeRegions[i], not header)
  end
  pcall(row.SetHeight, row, pw.EntryHeight(entry))

  if header then
    row.selected = false
    pw.SetShown(row.selectedBar, false)
    pw.SetShown(row.highlight, false)
    pw.SetText(row.headerLabel, entry.name)
    local cell = entry.expanded and t.cells.expanded or t.cells.collapsed
    pw.AtlasCoords(row.collapse, cell)
    pw.AtlasCoords(row.collapseHover, cell)
    pw.SetShown(row.collapseHover, row.hovered)
    pw.SetColor(row.headerLabel, row.hovered and t.headerHoverColor or t.headerColor)
    return
  end

  row.selected = entry.index == selectedIndex
  pw.SetShown(row.selectedBar, row.selected)
  pw.SetShown(row.highlight, row.hovered and not row.selected)

  local cell
  if entry.kind == "optimal" then
    cell = t.cells.skillOptimal
  elseif entry.kind == "medium" then
    cell = t.cells.skillMedium
  elseif entry.kind == "easy" then
    cell = t.cells.skillEasy
  end
  if cell then pw.AtlasCoords(row.skill, cell) end
  pw.SetShown(row.skill, cell and true or false)

  local name = entry.name
  if entry.sub then name = name .. " (" .. entry.sub .. ")" end
  local count = ""
  if entry.available > 0 then count = "[" .. entry.available .. "]" end
  pw.SetText(row.count, count)

  -- DF-main's label width: the text's own width, capped so the count still
  -- fits inside the row.
  local r = t.recipe
  local room = pw.RowWidth() - r.labelX - r.padding
  if count ~= "" then room = room - pw.TextWidth(row.count) - r.countGap end
  room = math.max(1, room)
  pcall(row.label.SetWidth, row.label, room)
  pw.SetText(row.label, name)
  pcall(row.label.SetWidth, row.label, math.max(1, math.min(room, pw.TextWidth(row.label) + 1)))

  local color = row.hovered and t.recipeHoverColor or t.recipeColor
  pw.SetColor(row.label, color)
  pw.SetColor(row.count, color)
end

function pw.MaxOffset(win)
  local n = table.getn(win.entries)
  if n == 0 then return 1 end
  local capacity = pw.ListCapacity()
  local used = 0
  local i
  for i = n, 1, -1 do
    used = used + pw.EntryHeight(win.entries[i])
    if used > capacity then return math.min(n, i + 1) end
  end
  return 1
end

-- The offset that brings list row `index` into view, or the current one.
function pw.Reveal(win, index)
  local position
  local i
  for i = 1, table.getn(win.entries) do
    if win.entries[i].index == index then position = i break end
  end
  if not position then return end
  if position < win.offset then
    win.offset = position
    return
  end
  local capacity = pw.ListCapacity()
  local used = 0
  for i = win.offset, position do
    used = used + pw.EntryHeight(win.entries[i])
  end
  while used > capacity and win.offset < position do
    used = used - pw.EntryHeight(win.entries[win.offset])
    win.offset = win.offset + 1
  end
end

function pw.LayoutList(win, selectedIndex)
  local t = pw.Token()
  local l = t.list
  local capacity = pw.ListCapacity()
  local n = table.getn(win.entries)

  win.maxOffset = pw.MaxOffset(win)
  if win.offset > win.maxOffset then win.offset = win.maxOffset end
  if win.offset < 1 then win.offset = 1 end

  local y = 0
  local used = 0
  local i = win.offset
  while i <= n do
    local entry = win.entries[i]
    local height = pw.EntryHeight(entry)
    if y + height > capacity then break end
    used = used + 1
    local row = win.rows[used] or pw.BuildRow(win, used)
    if row then
      pw.Place(row, win.list, "TOPLEFT", l.rowLeft, -(l.rowTop + y))
      pw.FillRow(win, row, entry, selectedIndex)
      pcall(row.Show, row)
    end
    y = y + height
    i = i + 1
  end
  for i = used + 1, table.getn(win.rows) do
    win.rows[i].entry = nil
    pcall(win.rows[i].Hide, win.rows[i])
  end
  pw.LayoutScroll(win)
end

-- ---------------------------------------------------------------------------
-- Scroll control: the client's scrollbar faces on addon-owned buttons
-- ---------------------------------------------------------------------------
function pw.ScrollFace(button, faces)
  local c = pw.Token().scroll.buttonTexCoord
  local slots = {
    { "SetNormalTexture", "GetNormalTexture", faces.normal },
    { "SetPushedTexture", "GetPushedTexture", faces.pushed },
    { "SetDisabledTexture", "GetDisabledTexture", faces.disabled },
    { "SetHighlightTexture", "GetHighlightTexture", faces.highlight },
  }
  local i
  for i = 1, table.getn(slots) do
    local slot = slots[i]
    if pcall(button[slot[1]], button, slot[3]) then
      local ok, texture = pcall(button[slot[2]], button)
      if ok and texture then
        pcall(texture.SetTexCoord, texture, c[1], c[2], c[3], c[4])
        if i == 4 then pcall(texture.SetBlendMode, texture, "ADD") end
      end
    end
  end
end

function pw.Scroll(win, delta)
  win.offset = win.offset + delta
  pw.Queue(win)
end

function pw.BuildScroll(win)
  local t = pw.Token()
  local s, l = t.scroll, t.list
  local tex = t.texture
  local capacity = pw.ListCapacity()

  local bar = pw.Frame("Frame", win.list, 3, false)
  if not bar then return end
  pw.Place(bar, win.list, "TOPRIGHT", -s.right, -l.rowTop, s.width, capacity)

  local up = pw.Frame("Button", bar, 1, true)
  local down = pw.Frame("Button", bar, 1, true)
  local track = pw.Frame("Button", bar, 0, true)
  if not up or not down or not track then return end
  pw.Place(up, bar, "TOP", 0, 0, s.button, s.button)
  pw.Place(down, bar, "BOTTOM", 0, 0, s.button, s.button)
  pcall(function()
    track:SetWidth(s.width)
    track:SetPoint("TOP", up, "BOTTOM", 0, 0)
    track:SetPoint("BOTTOM", down, "TOP", 0, 0)
  end)
  pw.ScrollFace(up, tex.scrollUp)
  pw.ScrollFace(down, tex.scrollDown)

  local bed = pw.Texture(track, "BACKGROUND", M.texture.plain)
  if bed then
    pcall(function()
      bed:SetPoint("TOPLEFT", track, "TOPLEFT", 3, 0)
      bed:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -3, 0)
      bed:SetVertexColor(0, 0, 0, s.trackAlpha)
    end)
  end

  local knob = pw.Texture(track, "ARTWORK", tex.scrollKnob)
  if knob then
    local c = s.knobTexCoord
    pcall(knob.SetTexCoord, knob, c[1], c[2], c[3], c[4])
    pcall(knob.SetWidth, knob, s.knobWidth)
    pcall(knob.SetHeight, knob, s.knobHeight)
  end

  up:SetScript("OnClick", function() pw.Scroll(win, -1) end)
  down:SetScript("OnClick", function() pw.Scroll(win, 1) end)
  -- A click on the track jumps there; GetCursorPosition is in UI pixels from
  -- the bottom-left (documentation.json), the same read core/widgets.lua uses.
  track:SetScript("OnClick", function()
    if win.maxOffset <= 1 then return end
    local ok, _, cy = pcall(GetCursorPosition)
    local scaleOk, scale = pcall(track.GetEffectiveScale, track)
    local topOk, top = pcall(track.GetTop, track)
    local heightOk, height = pcall(track.GetHeight, track)
    if not (ok and scaleOk and topOk and heightOk) then return end
    cy, scale, top, height = tonumber(cy), tonumber(scale), tonumber(top), tonumber(height)
    if not cy or not scale or scale <= 0 or not top or not height or height <= 0 then
      return
    end
    local fraction = math.min(1, math.max(0, (top - cy / scale) / height))
    win.offset = math.floor(fraction * (win.maxOffset - 1) + 0.5) + 1
    pw.Queue(win)
  end)

  win.scroll = { bar = bar, up = up, down = down, track = track, knob = knob }
end

function pw.LayoutScroll(win)
  local scroll = win.scroll
  if not scroll then return end
  local s = pw.Token().scroll
  local scrollable = win.maxOffset > 1
  pw.SetShown(scroll.bar, scrollable)
  if not scrollable then return end

  pcall(scroll.up.SetButtonState, scroll.up, "NORMAL")
  if win.offset > 1 then pcall(scroll.up.Enable, scroll.up) else pcall(scroll.up.Disable, scroll.up) end
  if win.offset < win.maxOffset then
    pcall(scroll.down.Enable, scroll.down)
  else
    pcall(scroll.down.Disable, scroll.down)
  end

  local knob = scroll.knob
  if knob then
    local travel = pw.ListCapacity() - 2 * s.button - s.knobHeight
    local fraction = (win.offset - 1) / (win.maxOffset - 1)
    pcall(function()
      knob:ClearAllPoints()
      knob:SetPoint("TOP", scroll.track, "TOP", 0, -math.max(0, travel) * fraction)
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Schematic form (ProfessionsRecipeSchematicFormTemplate + SetupSchematics)
-- ---------------------------------------------------------------------------

-- The silver slot frame, scaled so its measured opening fits `size`.
function pw.SlotFrame(parent, anchor, size)
  local t = pw.Token()
  local cell, opening = t.cells.slot, t.slotOpening
  local frame = pw.Atlas(parent, "OVERLAY", cell)
  if not frame then return nil end
  local scale = size / (opening.right - opening.left)
  pcall(function()
    frame:SetWidth((cell.right - cell.left) * scale)
    frame:SetHeight((cell.bottom - cell.top) * scale)
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT",
                   -(opening.left - cell.left) * scale,
                   (opening.top - cell.top) * scale)
  end)
  return frame
end

function pw.SchematicSize()
  local t = pw.Token()
  local l, s = t.list, t.schematic
  local width = t.design.width - (l.x + l.width + s.gap) - s.right
  local height = t.design.height - l.y - s.bottom
  return width, height
end

-- The background art, cropped to the form's aspect and kept right-aligned.
function pw.PlaceArt(win)
  local t = pw.Token()
  local art = win.art
  if not art then return end
  local width, height = pw.SchematicSize()
  local rect, canvas = t.artRect, t.artCanvas
  local left, top, right, bottom = rect.left, rect.top, rect.right, rect.bottom
  local sourceWidth, sourceHeight = right - left, bottom - top
  if sourceWidth / sourceHeight > width / height then
    left = right - sourceHeight * width / height
  else
    bottom = top + sourceWidth * height / width
  end
  pcall(art.SetTexCoord, art, left / canvas, right / canvas, top / canvas, bottom / canvas)
end

function pw.BuildReagent(win, index)
  local t = pw.Token()
  local s = t.schematic
  local button = pw.Frame("Button", win.schematic, 2, true)
  if not button then return nil end
  pcall(button.SetWidth, button, s.reagentWidth)
  pcall(button.SetHeight, button, s.reagentHeight)

  button.icon = pw.Texture(button, "ARTWORK")
  pw.Place(button.icon, button, "LEFT", 0, 0, s.reagentIcon, s.reagentIcon)
  if button.icon then pcall(button.icon.SetTexCoord, button.icon, 0.08, 0.92, 0.08, 0.92) end
  button.slot = pw.SlotFrame(button, button.icon, s.reagentIcon)

  button.label = pw.Label(button, M.fontSize.normal, t.bodyColor, "LEFT", "GameFontHighlight")
  if button.label then
    pcall(function()
      button.label:SetPoint("LEFT", button, "LEFT", s.reagentTextX, 0)
      button.label:SetWidth(s.reagentTextWidth)
    end)
  end

  button:SetScript("OnEnter", function()
    local selected = pw.Selected(win)
    if selected > 0 then pw.Tip(button, win.kind.tipReagent, selected, index) end
  end)
  button:SetScript("OnLeave", pw.HideTip)
  win.reagents[index] = button
  return button
end

function pw.BuildSchematic(win)
  local t = pw.Token()
  local l, s = t.list, t.schematic
  local width, height = pw.SchematicSize()

  local form = pw.Frame("Frame", win.cover, t.levels.panel, true)
  if not form then return end
  pw.Place(form, win.frame, "TOPLEFT", l.x + l.width + s.gap, -l.y, width, height)
  win.schematic = form

  win.art = pw.Texture(form, "BACKGROUND")
  if win.art then pcall(win.art.SetAllPoints, win.art, form) end
  pw.PlaceArt(win)
  if type(U.ModernWowThinBorder) == "function" then pcall(U.ModernWowThinBorder, form) end

  local icon = pw.Frame("Button", form, 2, true)
  if icon then
    pw.Place(icon, form, "TOPLEFT", s.inset, -s.inset, s.icon, s.icon)
    icon.texture = pw.Texture(icon, "ARTWORK")
    if icon.texture then
      pcall(icon.texture.SetAllPoints, icon.texture, icon)
      pcall(icon.texture.SetTexCoord, icon.texture, 0.08, 0.92, 0.08, 0.92)
    end
    icon.slot = pw.SlotFrame(icon, icon, s.icon)
    local countFrame = pw.Frame("Frame", icon, 1, false)
    if countFrame then
      pcall(countFrame.SetAllPoints, countFrame, icon)
      icon.count = pw.Label(countFrame, M.fontSize.normal, t.bodyColor, "RIGHT",
                            "NumberFontNormal")
      if icon.count then
        pcall(icon.count.SetPoint, icon.count, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
      end
    end
    icon:SetScript("OnEnter", function()
      local selected = pw.Selected(win)
      if selected > 0 then pw.Tip(icon, win.kind.tipRecipe, selected) end
    end)
    icon:SetScript("OnLeave", pw.HideTip)
    win.icon = icon
  end

  local textWidth = width - s.inset * 2
  win.name = pw.Label(form, M.fontSize.large, t.nameColor)
  if win.name and icon then
    pcall(function()
      win.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", s.nameGap, 0)
      win.name:SetWidth(textWidth - s.icon - s.nameGap)
    end)
  end
  win.requiresLabel = pw.Label(form, M.fontSize.small, t.labelColor, "LEFT",
                               "GameFontNormalSmall")
  pw.SetText(win.requiresLabel, U.L("PROFESSIONS_REQUIRES"))
  win.requiresText = pw.Label(form, M.fontSize.small, t.bodyColor, "LEFT",
                              "GameFontHighlightSmall")
  if win.requiresText and win.requiresLabel then
    pcall(function()
      win.requiresText:SetPoint("TOPLEFT", win.requiresLabel, "TOPRIGHT", s.lineGap, 0)
      win.requiresText:SetWidth(textWidth - s.icon - s.nameGap - 60)
    end)
  end
  win.cooldown = pw.Label(form, M.fontSize.small, t.cooldownColor, "LEFT",
                          "GameFontHighlightSmall")
  win.description = pw.Label(form, M.fontSize.small, t.bodyColor, "LEFT",
                             "GameFontHighlightSmall")
  if win.description then pcall(win.description.SetWidth, win.description, textWidth) end
  win.reagentLabel = pw.Label(form, M.fontSize.small, t.labelColor, "LEFT",
                              "GameFontNormalSmall")
  pw.SetText(win.reagentLabel, U.L("PROFESSIONS_REAGENTS"))

  win.empty = pw.Label(form, M.fontSize.normal, t.labelColor, "CENTER")
  if win.empty then
    pcall(win.empty.SetPoint, win.empty, "TOP", form, "TOP", 0, -60)
    pw.SetText(win.empty, U.L("PROFESSIONS_NO_RECIPES"))
  end

  local i
  for i = 1, s.maxReagents do pw.BuildReagent(win, i) end
end

function pw.FillSchematic(win, entry)
  local t = pw.Token()
  local s = t.schematic
  local kind = win.kind
  local index = entry and entry.index or 0
  local visible = entry ~= nil

  local parts = { win.icon, win.name, win.requiresLabel, win.requiresText,
                  win.cooldown, win.description, win.reagentLabel }
  local i
  for i = 1, table.getn(parts) do pw.SetShown(parts[i], visible) end
  pw.SetShown(win.empty, not visible)
  if not visible then
    for i = 1, table.getn(win.reagents) do pw.SetShown(win.reagents[i], false) end
    return false
  end

  -- Icon, produced count and the name in the product's quality colour.
  local iconOk, iconPath = pw.Call(kind.icon, index)
  if win.icon and win.icon.texture then
    pcall(win.icon.texture.SetTexture, win.icon.texture,
          (iconOk and type(iconPath) == "string" and iconPath) or t.texture.missingIcon)
  end
  local countText = ""
  if kind.made then
    local madeOk, minMade, maxMade = pw.Call(kind.made, index)
    minMade, maxMade = tonumber(minMade) or 1, tonumber(maxMade) or 1
    if madeOk and maxMade > 1 then
      countText = (minMade == maxMade) and tostring(minMade) or (minMade .. "-" .. maxMade)
    end
  end
  pw.SetText(win.icon and win.icon.count, countText)

  local name = entry.name
  if entry.sub then name = name .. " (" .. entry.sub .. ")" end
  pw.SetText(win.name, name)
  local color = t.nameColor
  if kind.link then
    local linkOk, link = pw.Call(kind.link, index)
    color = (linkOk and pw.LinkColor(link)) or color
  end
  pw.SetColor(win.name, color)

  -- Requirement and cooldown lines under the name.
  local below = win.name
  local tools = pw.Tools(win, index)
  pw.SetShown(win.requiresLabel, tools ~= nil)
  pw.SetShown(win.requiresText, tools ~= nil)
  if tools then
    pw.SetText(win.requiresText, tools)
    pcall(function()
      win.requiresLabel:ClearAllPoints()
      win.requiresLabel:SetPoint("TOPLEFT", win.name, "BOTTOMLEFT", 0, -s.lineGap)
    end)
    below = win.requiresLabel
  end
  local cooldown
  if kind.cooldown then
    local cdOk, seconds = pw.Call(kind.cooldown, index)
    seconds = cdOk and tonumber(seconds)
    if seconds and seconds > 0 then
      local format = U.G("SecondsToTime")
      local text
      if type(format) == "function" then
        local fOk, value = pcall(format, seconds)
        if fOk and type(value) == "string" then text = value end
      end
      cooldown = U.L("PROFESSIONS_COOLDOWN", text or U.FormatTimeShort(seconds))
    end
  end
  pw.SetShown(win.cooldown, cooldown ~= nil)
  if cooldown then
    pw.SetText(win.cooldown, cooldown)
    pcall(function()
      win.cooldown:ClearAllPoints()
      win.cooldown:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -s.lineGap)
    end)
  end

  -- Craft description, then the reagent heading.
  local description
  if kind.description then
    local dOk, text = pw.Call(kind.description, index)
    if dOk and type(text) == "string" and text ~= "" then description = text end
  end
  pw.SetShown(win.description, description ~= nil)
  local heading = win.icon
  local headingX, headingY = -1, -s.sectionGap
  if description then
    pw.SetText(win.description, description)
    pcall(function()
      win.description:ClearAllPoints()
      win.description:SetPoint("TOPLEFT", win.icon, "BOTTOMLEFT", -1, -s.sectionGap)
    end)
    heading, headingX, headingY = win.description, 0, -s.sectionGap
  end

  local countOk, numReagents = pw.Call(kind.numReagents, index)
  numReagents = (countOk and tonumber(numReagents)) or 0
  pw.SetShown(win.reagentLabel, numReagents > 0)
  pcall(function()
    win.reagentLabel:ClearAllPoints()
    win.reagentLabel:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", headingX, headingY)
  end)

  local creatable = true
  for i = 1, s.maxReagents do
    local button = win.reagents[i]
    local rName, rIcon, need, have
    if i <= numReagents then
      local rOk
      rOk, rName, rIcon, need, have = pw.Call(kind.reagent, index, i)
      if not rOk then rName = nil end
    end
    if button and type(rName) == "string" then
      need, have = tonumber(need) or 0, tonumber(have) or 0
      local enough = have >= need
      if not enough then creatable = false end
      pcall(button.icon.SetTexture, button.icon,
            type(rIcon) == "string" and rIcon or t.texture.missingIcon)
      pcall(button.icon.SetVertexColor, button.icon,
            enough and 1 or 0.5, enough and 1 or 0.5, enough and 1 or 0.5)
      pw.SetText(button.label, have .. "/" .. need .. " " .. rName)
      pw.SetColor(button.label, enough and t.bodyColor or t.missingColor)

      -- DF-main's layout: one column of six, the seventh and eighth beside the
      -- fifth and sixth.
      pcall(function()
        button:ClearAllPoints()
        if i <= s.reagentColumn then
          button:SetPoint("TOPLEFT", win.reagentLabel, "TOPLEFT", 1,
                          -s.reagentTop - (i - 1) * s.reagentPitch)
        else
          button:SetPoint("TOPLEFT", win.reagents[i - 2], "TOPRIGHT", s.reagentGap, 0)
        end
      end)
      pcall(button.Show, button)
    elseif button then
      pcall(button.Hide, button)
    end
  end
  if entry.raw == "used" then creatable = false end
  return creatable
end

-- ---------------------------------------------------------------------------
-- Create controls
-- ---------------------------------------------------------------------------
function pw.RedButton(win, parent, text, onClick)
  local t = pw.Token()
  local b = t.button
  local button = pw.Frame("Button", parent, t.levels.panel, true)
  if not button then return nil end
  pcall(button.SetWidth, button, b.width)
  pcall(button.SetHeight, button, b.height)
  if type(U.ModernWowRedButtonFace) == "function" then
    pcall(U.ModernWowRedButtonFace, button, b.height)
  end
  button.label = pw.Label(button, M.fontSize.normal, t.buttonTextColor, "CENTER")
  if button.label then
    U.CenterButtonLabel(button.label, button)
    pw.SetText(button.label, text)
  end
  button.enabled = true
  button:SetScript("OnEnter", function()
    if type(U.ModernWowPaintRedButton) == "function" then
      U.ModernWowPaintRedButton(button, button.enabled)
    end
  end)
  button:SetScript("OnLeave", function()
    if type(U.ModernWowPaintRedButton) == "function" then
      U.ModernWowPaintRedButton(button, false)
    end
  end)
  button:SetScript("OnClick", function()
    if button.enabled then onClick() end
  end)
  return button
end

function pw.SetButtonEnabled(button, enabled)
  if not button then return end
  local t = pw.Token()
  enabled = enabled and true or false
  if button.enabled == enabled then return end
  button.enabled = enabled
  if enabled then pcall(button.Enable, button) else pcall(button.Disable, button) end
  if type(U.ModernWowSetRedButtonDisabled) == "function" then
    U.ModernWowSetRedButtonDisabled(button, not enabled)
  end
  pw.SetColor(button.label, enabled and t.buttonTextColor or t.buttonDisabledColor)
end

-- A step button: DF-main's minus / plus glyph cells on an addon-owned button,
-- with an additive copy for hover and a dimmed face while disabled.
function pw.StepButton(win, parent, cell, delta)
  local t = pw.Token()
  local b = t.button
  local button = pw.Frame("Button", parent, t.levels.panel, true)
  if not button then return nil end
  pcall(button.SetWidth, button, b.stepWidth)
  pcall(button.SetHeight, button, b.height)
  button.glyph = pw.Atlas(button, "ARTWORK", cell)
  pw.Place(button.glyph, button, "CENTER", 0, 0, b.glyphWidth * 2, b.glyphHeight * 2)
  button.hover = pw.Atlas(button, "OVERLAY", cell)
  if button.hover and button.glyph then
    pcall(function()
      button.hover:SetAllPoints(button.glyph)
      button.hover:SetBlendMode("ADD")
      button.hover:SetAlpha(b.hoverAlpha)
      button.hover:Hide()
    end)
  end
  button.enabled = true
  button:SetScript("OnEnter", function() pw.SetShown(button.hover, button.enabled) end)
  button:SetScript("OnLeave", function() pw.SetShown(button.hover, false) end)
  button:SetScript("OnClick", function()
    if not button.enabled then return end
    win.count = math.max(1, math.min(b.maxCount, (win.count or 1) + delta))
    pw.Queue(win)
  end)
  return button
end

function pw.SetStepEnabled(button, enabled)
  if not button then return end
  button.enabled = enabled and true or false
  if button.glyph then
    pcall(button.glyph.SetAlpha, button.glyph, enabled and 1 or pw.Token().button.disabledAlpha)
  end
  if not enabled then pw.SetShown(button.hover, false) end
end

function pw.Create(win, all)
  local selected = pw.Selected(win)
  if selected <= 0 then return end
  local ok, err
  if win.kind.repeatable then
    local count = win.count or 1
    if all then
      local _, _, available = pw.Info(win, selected)
      count = math.max(1, available or 1)
      win.count = math.min(count, pw.Token().button.maxCount)
    end
    ok, err = pw.Call(win.kind.create, selected, count)
  else
    ok, err = pw.Call(win.kind.create, selected)
  end
  if not ok and err then U.Error("professions " .. win.kind.create .. ": " .. tostring(err)) end
  pw.Queue(win)
end

function pw.BuildControls(win)
  local t = pw.Token()
  local b = t.button
  local frame, cover = win.frame, win.cover

  win.create = pw.RedButton(win, cover, U.L("PROFESSIONS_CREATE"),
                            function() pw.Create(win, false) end)
  pw.Place(win.create, frame, "BOTTOMRIGHT", -b.right, b.bottom)
  if not win.kind.repeatable then
    win.points = pw.Label(cover, M.fontSize.small, t.labelColor, "RIGHT",
                          "GameFontNormalSmall")
    if win.points and win.create then
      pcall(win.points.SetPoint, win.points, "RIGHT", win.create, "LEFT", -12, 0)
    end
    return
  end

  win.createAll = pw.RedButton(win, cover, U.L("PROFESSIONS_CREATE_ALL"),
                               function() pw.Create(win, true) end)
  if win.createAll and win.create then
    pcall(win.createAll.SetPoint, win.createAll, "RIGHT", win.create, "LEFT", -b.createAllGap, 0)
  end
  win.decrement = pw.StepButton(win, cover, t.cells.expanded, -1)
  if win.decrement and win.createAll then
    pcall(win.decrement.SetPoint, win.decrement, "LEFT", win.createAll, "RIGHT", b.stepGap, 0)
  end
  win.increment = pw.StepButton(win, cover, t.cells.collapsed, 1)
  if win.increment and win.create then
    pcall(win.increment.SetPoint, win.increment, "RIGHT", win.create, "LEFT", -b.stepGap, 0)
  end

  -- The count readout in the category-header bar pieces.
  local box = pw.Frame("Frame", cover, t.levels.panel, false)
  if box and win.decrement then
    pcall(function()
      box:SetWidth(b.countWidth)
      box:SetHeight(b.height)
      box:SetPoint("LEFT", win.decrement, "RIGHT", b.countGap, 0)
    end)
    local left = pw.Atlas(box, "BACKGROUND", t.cells.headerLeft)
    local right = pw.Atlas(box, "BACKGROUND", t.cells.headerRight)
    local middle = pw.Atlas(box, "BACKGROUND", t.cells.headerMiddle)
    pw.Place(left, box, "LEFT", 0, 0, b.capWidth, b.height)
    pw.Place(right, box, "RIGHT", 0, 0, b.capWidth, b.height)
    if middle and left and right then
      pcall(function()
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
      end)
    end
    win.countText = pw.Label(box, M.fontSize.normal, t.bodyColor, "CENTER", "GameFontHighlight")
    if win.countText then
      pcall(win.countText.SetPoint, win.countText, "CENTER", box, "CENTER", 0, 0)
    end
  end
end

function pw.FillControls(win, entry, creatable)
  local t = pw.Token()
  local hasRecipe = entry ~= nil and entry.kind ~= "header"
  pw.SetButtonEnabled(win.create, hasRecipe and creatable)

  if not win.kind.repeatable then
    local token = U.G("GetCraftButtonToken")
    local verb
    if type(token) == "function" then
      local ok, key = pcall(token)
      if ok and type(key) == "string" and type(U.G(key)) == "string" then
        verb = U.G(key)
      end
    end
    pw.SetText(win.create and win.create.label, verb or U.L("PROFESSIONS_CREATE"))
    local points = entry and entry.points or 0
    pw.SetText(win.points, points > 0 and U.L("PROFESSIONS_TRAINING_POINTS", points) or "")
    return
  end

  -- While a repeat queue runs, the readout follows it (DF-main
  -- GetTradeskillRepeatCount); otherwise it keeps the chosen count.
  local repeatOk, remaining = pw.Call("GetTradeskillRepeatCount")
  remaining = repeatOk and tonumber(remaining)
  if remaining and remaining > 1 then win.count = remaining end
  local b = t.button
  win.count = math.max(1, math.min(b.maxCount, win.count or 1))
  pw.SetText(win.countText, tostring(win.count))

  pw.SetButtonEnabled(win.createAll, hasRecipe and creatable)
  pw.SetStepEnabled(win.decrement, hasRecipe and win.count > 1)
  pw.SetStepEnabled(win.increment, hasRecipe and win.count < b.maxCount)
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function pw.Queue(win)
  U.DeferOnce(win.key, function() pw.Refresh(win) end)
end

function pw.Profession(win, name)
  local t = pw.Token()
  local key
  if type(U.ModernWowProfessionKey) == "function" then key = U.ModernWowProfessionKey(name) end

  local icon = type(U.ModernWowProfessionIcon) == "function" and U.ModernWowProfessionIcon(key)
  local fx = t.fx[key or ""] or t.fx.default
  -- A craft window that is not a profession skill line is Beast Training.
  if not key and win.kind.id == "craft" then
    icon = icon or t.texture.beastTrainingIcon
    fx = t.fx.beasttraining
  end
  return t.art[key or ""] or t.art.default, fx, icon or t.texture.missingIcon
end

function pw.Refresh(win)
  if not win.built or not pw.Shown(win.frame) then return end

  local name, rank, maxRank = pw.Line(win)
  pw.SetText(win.title, name)
  pw.SetRank(win, rank, maxRank)
  local art, fx, icon = pw.Profession(win, name)
  if win.artPath ~= art and win.art then
    win.artPath = art
    pcall(win.art.SetTexture, win.art, art)
  end
  if win.fxPath ~= fx and win.rankFill then
    win.fxPath = fx
    pcall(win.rankFill.SetTexture, win.rankFill, fx)
  end
  if win.iconPath ~= icon and win.portrait then
    win.iconPath = icon
    pcall(win.portrait.SetTexture, win.portrait, icon)
  end

  -- The visible list as the client reports it: headers and the recipes of
  -- expanded headers, in order.
  local entries = {}
  local countOk, count = pw.Call(win.kind.count)
  count = (countOk and tonumber(count)) or 0
  local firstRecipe
  local i
  for i = 1, count do
    local rName, kind, available, expanded, sub, points, raw = pw.Info(win, i)
    if rName then
      local entry = { index = i, name = rName, kind = kind, available = available,
                      expanded = expanded and true or false, sub = sub,
                      points = points, raw = raw }
      table.insert(entries, entry)
      if kind ~= "header" and not firstRecipe then firstRecipe = entry end
    end
  end
  win.entries = entries

  local selected = pw.Selected(win)
  local selectedEntry
  for i = 1, table.getn(entries) do
    if entries[i].index == selected and entries[i].kind ~= "header" then
      selectedEntry = entries[i]
      break
    end
  end
  if not selectedEntry and firstRecipe then
    selectedEntry = firstRecipe
    selected = firstRecipe.index
    pw.Call(win.kind.select, selected)
    win.count = 1
  end
  if win.reveal and selectedEntry then
    win.reveal = false
    pw.Reveal(win, selected)
  end

  pw.LayoutList(win, selected)
  local creatable = pw.FillSchematic(win, selectedEntry)
  pw.FillControls(win, selectedEntry, creatable)
end

function pw.RefreshAll()
  local i
  for i = 1, table.getn(pw.windows) do
    local win = pw.windows[i]
    if pw.Shown(win.frame) then pw.Queue(win) end
  end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function pw.Build(kind)
  local frame = U.G(kind.host)
  if not frame then return false end
  local t = pw.Token()
  local d = t.design

  local win = {
    kind = kind,
    frame = frame,
    key = "professions.refresh." .. kind.id,
    entries = {},
    rows = {},
    reagents = {},
    offset = 1,
    maxOffset = 1,
    count = 1,
    reveal = true,
  }

  -- Strip before any addon region exists on this frame (rules/unreal-ui.md,
  -- region walks never match by identity). Every addon region lives on an
  -- addon-owned child.
  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  pcall(frame.SetWidth, frame, d.width)
  pcall(frame.SetHeight, frame, d.height)
  pcall(frame.SetHitRectInsets, frame, 0, 0, 0, 0)

  -- The cover takes the mouse so nothing of the native window beneath it can
  -- be clicked; the rim never does.
  win.cover = pw.Frame("Frame", frame, t.levels.cover, true)
  if not win.cover then error(kind.host .. ": cover frame could not be created") end
  pcall(win.cover.SetAllPoints, win.cover, frame)
  win.rim = pw.Frame("Frame", win.cover, t.levels.rim, false)
  if not win.rim then error(kind.host .. ": rim frame could not be created") end
  pcall(win.rim.SetAllPoints, win.rim, frame)

  pw.BuildChrome(win)
  pw.BuildRank(win)

  local l = t.list
  win.list = pw.Frame("Frame", win.cover, t.levels.panel, true)
  pw.Place(win.list, frame, "TOPLEFT", l.x, -l.y, l.width, d.height - l.y - l.bottom)
  local listBackground = pw.Atlas(win.list, "BACKGROUND", t.cells.listBackground)
  if listBackground then pcall(listBackground.SetAllPoints, listBackground, win.list) end
  if type(U.ModernWowThinBorder) == "function" then pcall(U.ModernWowThinBorder, win.list) end
  pw.BuildScroll(win)

  pw.BuildSchematic(win)
  pw.BuildControls(win)

  local close = U.G(kind.close)
  if close then
    U.StyleStockCloseButton(close, frame, -t.close.x, -t.close.y)
    pcall(function()
      close:SetWidth(t.close.size)
      close:SetHeight(t.close.size)
    end)
    if type(U.ModernWowDressCloseButton) == "function" then
      pcall(U.ModernWowDressCloseButton, kind.close)
    end
  end
  local title = U.G(kind.host .. "TitleText")
  if title then pcall(title.Hide, title) end

  U.MakeWindowDraggable("professions-" .. kind.id, frame, {
    headerHeight = t.drag.headerHeight,
    headerInset = t.drag.headerInset,
    headerLevelOffset = t.levels.cover + t.levels.handle,
    interactiveFrames = close and { close } or nil,
  })

  -- Levels are set once, relative to the host, and never reasserted: every
  -- addon frame here descends from the host exactly as the native children
  -- do, the arrangement the Talent window's chrome uses.
  U.PostHookScript(frame, "OnShow", function()
    win.reveal = true
    pw.Refresh(win)
    pw.Queue(win)
  end)
  U.PostHookScript(frame, "OnHide", pw.HideTip)
  -- Fixed-signature native update: safe for U.PostHookGlobal
  -- (knowledge.json / lua.posthook_global_fixed_arity_breaks_vararg_frameXML).
  -- Deferred, never inline, so nothing runs inside the native update chain.
  if type(U.G(kind.update)) == "function" then
    U.PostHookGlobal(kind.update, function() pw.Queue(win) end)
  end

  win.built = true
  table.insert(pw.windows, win)
  frame.uuiModernWowWindow = { chrome = win.cover, professions = true }
  pw.Refresh(win)
  return true
end

function pw.TryBuildAll()
  local pending = false
  local i
  for i = 1, table.getn(pw.KINDS) do
    local kind = pw.KINDS[i]
    if not kind.built then
      if U.G(kind.host) then
        local ok, err = pcall(pw.Build, kind)
        kind.built = true
        if not ok then
          kind.failed = true
          U.Error("professions modern-wow " .. kind.host .. ": " .. tostring(err))
        end
      else
        pending = true
      end
    end
  end

  if not pending and pw.polling then
    pw.polling = false
    U.UnregisterUpdate("professions.build")
    U.UnregisterEvent("ADDON_LOADED", pw.TryBuildAll)
  end
  return pending
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
function U.ModernWowProfessionsWanted()
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= pw.THEME then
    return false
  end
  return type(U.ModernWowSurfaceEnabled) == "function" and
         U.ModernWowSurfaceEnabled(pw.SURFACE) and true or false
end

-- For modules/modernwow.lua's surface check: false only when a host window
-- exists but its drawing path did not build.
function U.ModernWowProfessionsHealthy()
  local i
  for i = 1, table.getn(pw.KINDS) do
    local kind = pw.KINDS[i]
    if kind.failed then return false end
    if U.G(kind.host) and not kind.built and pw.enabled then return false end
  end
  return true
end

function PR:OnEnable()
  if not U.ModernWowProfessionsWanted() then return end
  pw.enabled = true

  if not pw.eventsInstalled then
    pw.eventsInstalled = true
    U.RegisterEvent("BAG_UPDATE", pw.RefreshAll)
    U.RegisterEvent("SKILL_LINES_CHANGED", pw.RefreshAll)
  end

  -- Blizzard_TradeSkillUI and Blizzard_CraftUI may load on demand after this
  -- module. ADDON_LOADED is only EXISTENCE_ONLY evidence here, so a one-second
  -- lookup backs it up until both windows are built.
  if pw.TryBuildAll() then
    pw.polling = true
    U.RegisterEvent("ADDON_LOADED", pw.TryBuildAll)
    U.RegisterUpdate("professions.build", 1, pw.TryBuildAll)
  end
end
