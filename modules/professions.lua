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
-- All / count / Create underneath. It runs for the full Modern WoW theme or
-- Classic's explicit `professions` selection; no unselected theme draws this
-- window.
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
--  * The list uses the same addon-owned MinimalScrollBar treatment as
--    Character > Skills. Physical wheel input cannot reach addon frames on
--    this client (knowledge.json / scripts.addon_wheel_binding_unavailable),
--    so the supported controls remain its arrows and draggable thumb.
--  * The rank bar is a plain texture cropped with SetTexCoord (a native
--    StatusBar does not lay out its fill here, statusbar knowledge), and its
--    DF-main mask is baked into the fill by tools/import_modern_wow_media.py.
--  * DF-main's profession tabs, favourites, filter menu, link button and
--    minimize button are omitted: switching profession casts a spell, which
--    is protected here, and the rest need an EditBox or a dropdown menu. Item
--    icons still support the native Shift-click chat-link interaction.
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
    reagentLink = "GetTradeSkillReagentItemLink",
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
    link = "GetCraftItemLink",
    reagentLink = "GetCraftReagentItemLink",
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

-- Insert an item link only for the stock Shift-click gesture. This is the
-- narrow same-client UnrealPfUI pattern: prefer ChatEdit_InsertLink, with the
-- visible edit box as the Vanilla fallback.
function pw.InsertChatLink(link)
  if type(link) ~= "string" or link == "" then return false end
  local shift = U.G("IsShiftKeyDown")
  if type(shift) ~= "function" then return false end
  local shiftOk, down = pcall(shift)
  if not shiftOk or not down then return false end

  local insert = U.G("ChatEdit_InsertLink")
  if type(insert) == "function" then
    local insertOk = pcall(insert, link)
    if insertOk then return true end
  end

  local edit = U.G("ChatFrameEditBox")
  if not edit or type(edit.IsVisible) ~= "function" or
     type(edit.Insert) ~= "function" then
    return false
  end
  local visibleOk, visible = pcall(edit.IsVisible, edit)
  if not visibleOk or not visible then return false end
  return pcall(edit.Insert, edit, link)
end

function pw.LinkClick(win, reagentIndex)
  local selected = pw.Selected(win)
  if selected <= 0 then return end
  local getter = reagentIndex and win.kind.reagentLink or win.kind.link
  if not getter then return end
  local linkOk, link = pw.Call(getter, selected, reagentIndex)
  if linkOk then pw.InsertChatLink(link) end
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
  if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
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

-- The drawn row's height.
function pw.RowHeight(entry)
  local t = pw.Token()
  if entry.kind == "header" then return t.header.height end
  return t.recipe.height
end

-- The list space an entry takes: its row, plus the gap below the last recipe
-- of a category, less the pull that draws an expanded category's first
-- recipe up under its header (user requests, 2026-09-17). Only the list
-- advance changes; each row keeps its own height and content.
function pw.EntryHeight(entry)
  local t = pw.Token()
  local height = pw.RowHeight(entry)
  if entry.groupEnd then height = height + t.recipe.groupGap end
  if entry.groupStart then height = height - t.header.recipePull end
  return height
end

-- A recipe row's difficulty tint, shared by its label and its bars.
function pw.DifficultyColor(entry)
  local colors = pw.Token().difficultyColor
  return (entry and colors[entry.kind]) or colors.trivial
end

-- A recipe label is white while hovered or selected, else its difficulty.
function pw.ApplyRecipeColor(row)
  local color = pw.Token().recipeHoverColor
  if not row.hovered and not row.selected then
    color = pw.DifficultyColor(row.entry)
  end
  pw.SetColor(row.label, color)
  pw.SetColor(row.count, color)
end

function pw.OnRowEnter(win, row)
  local t = pw.Token()
  row.hovered = true
  if row.entry and row.entry.kind == "header" then
    pw.SetColor(row.headerLabel, t.headerHoverColor)
    pw.SetShown(row.collapseHover, true)
  elseif row.entry then
    pw.ApplyRecipeColor(row)
    pw.SetShown(row.highlight, not row.selected)
  end
end

function pw.OnRowLeave(win, row)
  local t = pw.Token()
  row.hovered = false
  pw.SetColor(row.headerLabel, t.headerColor)
  pw.SetShown(row.collapseHover, false)
  if row.entry and row.entry.kind ~= "header" then pw.ApplyRecipeColor(row) end
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

-- A selection/hover bar across the list panel's full width: the row sits
-- rowLeft/rowRight inside the panel, so the bar reaches back out by those.
function pw.PlaceRowBar(bar, row)
  if not bar then return end
  local l, r = pw.Token().list, pw.Token().recipe
  pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", row, "LEFT", r.barInset - l.rowLeft, -1)
    bar:SetPoint("RIGHT", row, "RIGHT", l.rowRight - r.barInset, -1)
    bar:SetHeight(r.selectedHeight)
  end)
end

-- The header art's right cap. While the list scrolls, the art (and the
-- collapse glyph inside the cap) ends clear of the scrollbar instead of
-- running under it (user request, 2026-09-17).
function pw.PlaceHeaderRight(row, scrollable)
  if row.headerScrollable == scrollable then return end
  row.headerScrollable = scrollable
  local t = pw.Token()
  local h, l, s = t.header, t.list, t.scroll
  local inset = h.panelInset
  if scrollable then inset = s.right + s.width + h.scrollGap end
  pw.Place(row.headerRight, row, "RIGHT", l.rowRight - inset, h.lift,
           h.pieceWidth, h.pieceHeight)
end

function pw.BuildRow(win, index)
  local t = pw.Token()
  local h, r = t.header, t.recipe
  local width = pw.RowWidth()

  local row = pw.Frame("Button", win.list, 2, true)
  if not row then return nil end
  pcall(row.SetWidth, row, width)
  pcall(row.SetHeight, row, r.height)

  -- Category header: three atlas pieces, label, collapse glyph. The pieces
  -- span the list panel like the selection bars (pw.PlaceRowBar, user
  -- request, 2026-09-17); the label and glyph keep their row positions, clear
  -- of the scrollbar.
  local l = t.list
  row.headerLeft = pw.Atlas(row, "BACKGROUND", t.cells.headerLeft)
  pw.Place(row.headerLeft, row, "LEFT", h.panelInset - l.rowLeft, h.lift,
           h.pieceWidth, h.pieceHeight)
  row.headerRight = pw.Atlas(row, "BACKGROUND", t.cells.headerRight)
  pw.PlaceHeaderRight(row, false)
  row.headerMiddle = pw.Atlas(row, "BACKGROUND", t.cells.headerMiddle)
  if row.headerMiddle and row.headerLeft and row.headerRight then
    pcall(function()
      row.headerMiddle:SetPoint("TOPLEFT", row.headerLeft, "TOPRIGHT", 0, 0)
      row.headerMiddle:SetPoint("BOTTOMRIGHT", row.headerRight, "BOTTOMLEFT", 0, 0)
    end)
  end
  row.collapse = pw.Atlas(row, "ARTWORK", t.cells.expanded)
  -- Right-aligned inside the header art's right cap (user request,
  -- 2026-09-17); the cap already carries the lift.
  pw.Place(row.collapse, row.headerRight, "RIGHT", -h.collapsePadding, 0,
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
      row.headerLabel:SetPoint("RIGHT", row.collapse, "LEFT", -4, h.labelY - h.lift)
      row.headerLabel:SetHeight(12)
    end)
  end
  row.headerRegions = { row.headerLeft, row.headerMiddle, row.headerRight,
                        row.collapse, row.headerLabel }

  -- Recipe: selection and hover bars, difficulty glyph, label and count.
  -- The white hover cell, tinted per difficulty in pw.FillRow.
  row.selectedBar = pw.Atlas(row, "BORDER", t.cells.highlight)
  pw.PlaceRowBar(row.selectedBar, row)
  -- Hover draws exactly as the selection does, tinted the same way.
  row.highlight = pw.Atlas(row, "BORDER", t.cells.highlight)
  pw.PlaceRowBar(row.highlight, row)
  row.skill = pw.Texture(row, "ARTWORK", t.texture.atlas)
  pw.Place(row.skill, row, "LEFT", r.iconX, 0, r.iconWidth, r.iconHeight)
  row.label = pw.Label(row, M.fontSize.normal, t.recipeColor, "LEFT", "GameFontHighlight")
  if row.label then
    pcall(function()
      row.label:SetPoint("LEFT", row, "LEFT", r.labelX, r.labelY)
      row.label:SetHeight(12)
    end)
  end
  row.count = pw.Label(row, M.fontSize.normal, t.recipeColor, "LEFT", "GameFontHighlight")
  if row.count and row.label then
    pcall(row.count.SetPoint, row.count, "LEFT", row.label, "RIGHT", r.countGap, 0)
  end
  row.recipeRegions = { row.skill, row.label, row.count }
  -- Shown per entry in pw.FillRow, only while the recipe is tracked.
  row.check = pw.Texture(row, "OVERLAY", pw.TrackCheckPath(win))
  pw.Place(row.check, row, "RIGHT", -r.checkRight, r.checkY, r.checkSize, r.checkSize)
  pw.SetShown(row.check, false)

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
  pcall(row.SetHeight, row, pw.RowHeight(entry))

  local tracked = not header and type(U.CraftTrackerIsTracked) == "function" and
                  U.CraftTrackerIsTracked(entry.name)
  pw.SetShown(row.check, tracked)

  if header then
    row.selected = false
    pw.SetShown(row.selectedBar, false)
    pw.SetShown(row.highlight, false)
    pw.PlaceHeaderRight(row, win.scroll ~= nil and (win.maxOffset or 1) > 1)
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
  local tint = pw.DifficultyColor(entry)
  if row.selectedBar then
    pcall(row.selectedBar.SetVertexColor, row.selectedBar, M.Unpack(tint))
  end
  if row.highlight then
    pcall(row.highlight.SetVertexColor, row.highlight, M.Unpack(tint))
  end
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
  if tracked then room = room - r.checkSize - r.checkGap end
  room = math.max(1, room)
  pcall(row.label.SetWidth, row.label, room)
  pw.SetText(row.label, name)
  pcall(row.label.SetWidth, row.label, math.max(1, math.min(room, pw.TextWidth(row.label) + 1)))

  pw.ApplyRecipeColor(row)
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
  win.visibleRows = used
  pw.LayoutScroll(win)
end

-- ---------------------------------------------------------------------------
-- Scroll control: Character > Skills' shared MinimalScrollBar
-- ---------------------------------------------------------------------------
function pw.ReadScroll(win)
  local bar = win.scroll and win.scroll.bar
  if not bar or win.syncingScroll then return end
  local ok, value = pcall(bar.GetValue, bar)
  value = ok and tonumber(value) or nil
  if not value then return end
  value = math.floor(value + 0.5)
  if value < 1 then value = 1 end
  if value > win.maxOffset then value = win.maxOffset end
  if value == win.offset then return end
  win.offset = value
  pw.Queue(win)
end

function pw.BuildScroll(win)
  local t = pw.Token()
  local s, l = t.scroll, t.list
  local capacity = pw.ListCapacity()
  local height = capacity - s.topGap - s.bottomGap
  if height < 1 then return end
  local name = "UnrealUIProfessions" .. win.kind.id .. "ScrollBar"
  local ok, bar = pcall(CreateFrame, "Slider", name, win.list,
                         "UIPanelScrollBarTemplate")
  if not ok or not bar then return end

  -- UIPanelScrollBarTemplate's native OnValueChanged assumes its parent is a
  -- ScrollFrame and calls parent:SetVerticalScroll(value). This custom list's
  -- parent is an ordinary Frame, so remove that handler before the first range
  -- write and install the recipe-offset handler below instead.
  pcall(bar.SetScript, bar, "OnValueChanged", nil)

  pcall(function()
    bar:SetFrameLevel(pw.Level(win.list) + 3)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(s.width)
    bar:SetHeight(height)
    bar:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", -s.right,
                 -(l.rowTop + s.topGap))
    bar:SetMinMaxValues(1, 1)
    bar:SetValueStep(1)
    bar:SetValue(1)
  end)

  local up = U.G(name .. "ScrollUpButton")
  local down = U.G(name .. "ScrollDownButton")
  if up then
    up:SetScript("OnClick", function()
      local valueOk, value = pcall(bar.GetValue, bar)
      if valueOk and tonumber(value) then pcall(bar.SetValue, bar, value - 1) end
    end)
  end
  if down then
    down:SetScript("OnClick", function()
      local valueOk, value = pcall(bar.GetValue, bar)
      if valueOk and tonumber(value) then pcall(bar.SetValue, bar, value + 1) end
    end)
  end

  win.scroll = { bar = bar, up = up, down = down }
  -- Read-only diagnostic handle for UnrealRuntimeProbe's focused profession
  -- scroll capture. Production code never reads it.
  bar.uuiProfessionWindow = win
  if type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, { onChange = function() pw.ReadScroll(win) end })
  end
  bar:SetScript("OnValueChanged", function() pw.ReadScroll(win) end)
end

function pw.LayoutScroll(win)
  local scroll = win.scroll
  if not scroll then return end
  local scrollable = win.maxOffset > 1
  pw.SetShown(scroll.bar, scrollable)
  win.syncingScroll = true
  pcall(scroll.bar.SetMinMaxValues, scroll.bar, 1, win.maxOffset)
  pcall(scroll.bar.SetValue, scroll.bar, win.offset)
  win.syncingScroll = false
  if not scrollable then return end

  if scroll.up then
    if win.offset > 1 then pcall(scroll.up.Enable, scroll.up)
    else pcall(scroll.up.Disable, scroll.up) end
  end
  if scroll.down then
    if win.offset < win.maxOffset then pcall(scroll.down.Enable, scroll.down)
    else pcall(scroll.down.Disable, scroll.down) end
  end
  if type(U.SetModernWowScrollbarProportion) == "function" then
    U.SetModernWowScrollbarProportion(scroll.bar, win.visibleRows,
                                      table.getn(win.entries))
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

-- A reagent button is exactly its icon's slot frame (pw.SlotFrame's scale),
-- so row gaps and the heading gap are measured from the visible frame edge.
-- Returns the frame's width, height and how far it overhangs the icon's
-- left and top edges.
function pw.ReagentGeometry()
  local t = pw.Token()
  local cell, opening = t.cells.slot, t.slotOpening
  local scale = t.schematic.reagentIcon / (opening.right - opening.left)
  return (cell.right - cell.left) * scale, (cell.bottom - cell.top) * scale,
         (opening.left - cell.left) * scale, (opening.top - cell.top) * scale
end

function pw.BuildReagent(win, index)
  local t = pw.Token()
  local s = t.schematic
  local _, frameHeight, overLeft, overTop = pw.ReagentGeometry()
  local button = pw.Frame("Button", win.schematic, 2, true)
  if not button then return nil end
  pcall(button.SetWidth, button, s.reagentWidth)
  pcall(button.SetHeight, button, frameHeight)

  button.icon = pw.Texture(button, "ARTWORK")
  pw.Place(button.icon, button, "TOPLEFT", overLeft, -overTop, s.reagentIcon, s.reagentIcon)
  if button.icon then pcall(button.icon.SetTexCoord, button.icon, 0.08, 0.92, 0.08, 0.92) end
  button.slot = pw.SlotFrame(button, button.icon, s.reagentIcon)

  local textX = overLeft + s.reagentIcon + s.reagentTextGap
  button.label = pw.Label(button, M.fontSize.normal, t.bodyColor, "LEFT", "GameFontHighlight")
  if button.label then
    pcall(function()
      button.label:SetPoint("LEFT", button, "LEFT", textX, 0)
      button.label:SetWidth(s.reagentWidth - textX)
    end)
  end

  button:SetScript("OnEnter", function()
    local selected = pw.Selected(win)
    if selected > 0 then pw.Tip(button, win.kind.tipReagent, selected, index) end
  end)
  button:SetScript("OnLeave", pw.HideTip)
  button:SetScript("OnClick", function() pw.LinkClick(win, index) end)
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
      if selected <= 0 then return end
      pw.Tip(icon, win.kind.tipRecipe, selected)
      -- Gear products compare against what is worn, through the shared
      -- renderer bag slots and quest rewards use (core/itemslot.lua); it
      -- ignores anything that is not equippable. Craft-window enchant links
      -- are not equippable, so the renderer leaves them alone.
      if win.kind.link and type(U.ShowItemCompare) == "function" then
        local linkOk, link = pw.Call(win.kind.link, selected)
        if linkOk then U.ShowItemCompare(link) end
      end
    end)
    icon:SetScript("OnLeave", pw.HideTip)
    icon:SetScript("OnClick", function() pw.LinkClick(win) end)
    win.icon = icon
  end

  local textWidth = width - s.inset * 2
  win.name = pw.Label(form, M.fontSize.large, t.nameColor)
  win.nameWidth = textWidth - s.icon - s.nameGap
  if win.name and icon then
    pcall(function()
      win.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", s.nameGap, 0)
      win.name:SetWidth(win.nameWidth)
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
  pw.BuildStats(win)
  pw.BuildTrack(win)
end

-- ---------------------------------------------------------------------------
-- Track this recipe (modules/crafttracker.lua)
-- ---------------------------------------------------------------------------

function pw.BuildTrack(win)
  local tr = pw.Token().track
  local form = win.schematic
  local name = "UnrealUIProfessionsTrack" .. win.kind.id
  local ok, box = pcall(CreateFrame, "CheckButton", name, form, "UICheckButtonTemplate")
  if not ok or not box then return end

  pcall(function()
    box:SetWidth(tr.size)
    box:SetHeight(tr.size)
    box:SetPoint("TOPRIGHT", form, "TOPRIGHT", -tr.right, tr.y)
    box:SetFrameLevel(pw.Level(form) + tr.levelLift)
  end)
  local label = U.G(name .. "Text")
  if label then
    pcall(function()
      label:SetText(U.L("PROFESSIONS_TRACK_RECIPE"))
      label:ClearAllPoints()
      label:SetPoint("RIGHT", box, "LEFT", -tr.labelGap, 0)
    end)
  end

  box:SetScript("OnClick", function() pw.ToggleTrack(win) end)
  win.track = box
end

-- The selected recipe's reagents and the count one craft needs.
function pw.RecipeReagents(win, index)
  local list = {}
  local countOk, n = pw.Call(win.kind.numReagents, index)
  n = (countOk and tonumber(n)) or 0
  local i
  for i = 1, n do
    local ok, rName, _, need = pw.Call(win.kind.reagent, index, i)
    if ok and type(rName) == "string" and rName ~= "" then
      table.insert(list, { name = rName, need = tonumber(need) or 1 })
    end
  end
  return list
end

function pw.ToggleTrack(win)
  local box = win.track
  local index = pw.Selected(win)
  local rName = index > 0 and pw.Info(win, index)
  local tracked = false
  if rName and type(U.CraftTrackerSetTracked) == "function" then
    if U.CraftTrackerIsTracked(rName) then
      tracked = U.CraftTrackerSetTracked(rName, nil)
    else
      tracked = U.CraftTrackerSetTracked(rName, pw.RecipeReagents(win, index))
    end
  end
  if box then pcall(box.SetChecked, box, tracked and true or nil) end
  -- The list's tracked checks follow the box.
  pw.Queue(win)
end

-- The tick the "Track this recipe" box draws when checked, reused by the
-- list rows. Read once from that addon-created CheckButton (Get*Texture on a
-- button's own state art, not a region walk); the token's fallback covers a
-- window whose box failed to build.
function pw.TrackCheckPath(win)
  if win.checkPath then return win.checkPath end
  local path
  local box = win.track
  if box then
    local ok, texture = pcall(box.GetCheckedTexture, box)
    if ok and texture then
      local pathOk, value = pcall(texture.GetTexture, texture)
      if pathOk and type(value) == "string" and value ~= "" then path = value end
    end
  end
  win.checkPath = path or pw.Token().recipe.checkFallback
  return win.checkPath
end

function pw.FillTrack(win, entry)
  local box = win.track
  if not box then return end
  local available = entry ~= nil and type(U.CraftTrackerIsTracked) == "function"
  pw.SetShown(box, available)
  if available then
    pcall(box.SetChecked, box, U.CraftTrackerIsTracked(entry.name) and true or nil)
  end
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
    pw.FillStats(win, nil)
    pw.FillTrack(win, nil)
    return false
  end
  pw.FillTrack(win, entry)

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
    win.reagentLabel:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", headingX,
                              headingY - s.reagentHeadingShift)
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
      -- fifth and sixth. The column starts under the heading; the icon keeps
      -- its 1-unit indent while its frame overhangs to the left.
      pcall(function()
        button:ClearAllPoints()
        if i <= s.reagentColumn then
          local _, frameHeight, overLeft = pw.ReagentGeometry()
          button:SetPoint("TOPLEFT", win.reagentLabel, "BOTTOMLEFT", 1 - overLeft,
                          -s.reagentLabelGap - (i - 1) * (frameHeight + s.reagentSpacing))
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
  pw.FillStats(win, entry)
  return creatable
end

-- ---------------------------------------------------------------------------
-- Item stats (equippable products)
-- ---------------------------------------------------------------------------

-- A private, never-shown GameTooltipTemplate scanner, the sequence
-- core/itemsort.lua and modules/auras.lua already read TextLeft lines through.
-- SetTradeSkillItem and FontString:GetTextColor are only
-- DOCUMENTED_NOT_RUNTIME_VERIFIED here: a failing call leaves the panel hidden,
-- and an unreadable colour falls back to white.
pw.SCANNER_NAME = "UnrealUIProfessionsScan"

function pw.Scanner()
  if pw.scanner then return pw.scanner end
  local ok, tip = pcall(CreateFrame, "GameTooltip", pw.SCANNER_NAME, nil,
                        "GameTooltipTemplate")
  if ok and tip then pw.scanner = tip end
  return pw.scanner
end

function pw.ScanRegion(name)
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
    local cOk, r, g, b = pcall(region.GetTextColor, region)
    if cOk and tonumber(r) and tonumber(g) and tonumber(b) then
      color = { r, g, b, 1 }
    end
  end
  return text, color
end

-- The product tooltip's lines after its name, or nil when the product is not
-- gear, is not cached yet, or any step of the scan does not answer. Trade
-- skills only: a Craft window's products are enchantments, not items.
function pw.StatLines(win, index)
  local kind = win.kind
  if not kind.link or index <= 0 then return nil end
  local linkOk, link = pw.Call(kind.link, index)
  if not linkOk or type(link) ~= "string" then return nil end

  local infoOk, _, _, _, _, _, _, _, equipLoc = pcall(GetItemInfo, link)
  if not infoOk or type(equipLoc) ~= "string" or equipLoc == "" or
     pw.Token().statsSkipEquipLoc[equipLoc] then
    return nil
  end

  local tip = pw.Scanner()
  if not tip or type(tip[kind.tipRecipe]) ~= "function" then return nil end
  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")
  if not pcall(tip[kind.tipRecipe], tip, index) then return nil end

  local countOk, count = pcall(tip.NumLines, tip)
  count = countOk and tonumber(count) or 0
  local maxLines = pw.Token().stats.maxLines + 1
  if count > maxLines then count = maxLines end

  local durability = pw.DurabilityPattern()
  local durable = durability == nil
  local lines = {}
  local i
  for i = 2, count do
    local left, leftColor = pw.ScanRegion(pw.SCANNER_NAME .. "TextLeft" .. i)
    local right, rightColor = pw.ScanRegion(pw.SCANNER_NAME .. "TextRight" .. i)
    if left or right then
      table.insert(lines, { left = left, leftColor = leftColor,
                            right = right, rightColor = rightColor })
      if left and durability and string.find(left, durability) then durable = true end
    end
  end
  -- Gear without durability (shirts, tabards, jewellery) gets no panel (user
  -- request, 2026-09-16). An unreadable template shows every gear panel.
  if not durable or table.getn(lines) == 0 then return nil end
  return lines
end

-- DURABILITY_TEMPLATE ("Durability %d / %d" on enUS), the global
-- modules/status.lua reads worn durability through, as an anchored pattern.
-- Format tokens become placeholders before the literal text is escaped, as in
-- core/itemsort.lua's CONTAINER_SLOTS pattern.
function pw.DurabilityPattern()
  if pw.durabilityPattern ~= nil then return pw.durabilityPattern or nil end
  local template = U.G("DURABILITY_TEMPLATE")
  if type(template) ~= "string" or template == "" then
    pw.durabilityPattern = false
    return nil
  end
  local p = string.gsub(template, "%%%d*%$?d", "\001")
  p = string.gsub(p, "([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
  p = string.gsub(p, "\001", function() return "%d+" end)
  pw.durabilityPattern = "^" .. p .. "$"
  return pw.durabilityPattern
end

function pw.BuildStats(win)
  local t = pw.Token()
  local st, tex = t.stats, t.texture
  local panel = pw.Frame("Frame", win.schematic, 2, false)
  if not panel then return end
  -- Hangs `trackGap` under the "Track this recipe" box, so it follows the box.
  local tr = t.track
  pw.Place(panel, win.schematic, "TOPRIGHT", -st.right, tr.y - tr.size - st.trackGap,
           st.width, 100)
  win.stats = panel
  win.statsLines = {}

  local fill = pw.Texture(panel, "BACKGROUND", M.texture.plain)
  if fill then
    pcall(function()
      fill:SetPoint("TOPLEFT", panel, "TOPLEFT", st.fillInset, -st.fillInset)
      fill:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -st.fillInset, st.fillInset)
      fill:SetVertexColor(M.Unpack(st.fillColor))
    end)
  end

  local g = pw.StatsBorderGeometry()
  local out, inset = g.out, g.inset

  local border = {}
  border.left = pw.Texture(panel, "BORDER", tex.metalLeft)
  border.right = pw.Texture(panel, "BORDER", tex.metalLeft)
  border.top = pw.Texture(panel, "BORDER", tex.metalTop)
  border.bottom = pw.Texture(panel, "BORDER", tex.metalTop)
  pcall(function()
    border.left:SetWidth(g.edge)
    border.left:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -inset)
    border.left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, inset)
    border.right:SetWidth(g.edge)
    border.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -inset)
    border.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, inset)
    border.top:SetHeight(g.edge)
    border.top:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, 0)
    border.top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, 0)
    border.bottom:SetHeight(g.edge)
    border.bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", inset, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, 0)
  end)

  -- The joint is authored as the bottom-right corner; the rest are mirrors.
  local corners = {
    { "TOPLEFT", -out, out, 1, 0, 1, 0 },
    { "TOPRIGHT", out, out, 0, 1, 1, 0 },
    { "BOTTOMLEFT", -out, -out, 1, 0, 0, 1 },
    { "BOTTOMRIGHT", out, -out, 0, 1, 0, 1 },
  }
  local i
  for i = 1, table.getn(corners) do
    local c = corners[i]
    local joint = pw.Texture(panel, "ARTWORK", tex.metalJoint)
    if joint then
      pcall(function()
        joint:SetWidth(g.joint)
        joint:SetHeight(g.joint)
        joint:SetPoint(c[1], panel, c[1], c[2], c[3])
        joint:SetTexCoord(c[4], c[5], c[6], c[7])
      end)
    end
  end
  win.statsBorder = border
end

-- The metal border's drawn sizes. `borderScale` sizes the whole border: the
-- edges draw at that many units per texel, and the joints at the ratio that
-- makes their bars as thick as the edges'. The edge inset scales with it, so
-- the edges still start under the joints' straight bars.
function pw.StatsBorderGeometry()
  local st = pw.Token().stats
  local e, j = st.edge, st.joint
  local scale = st.borderScale or 1
  local jointScale = e.thickness / j.thickness * scale
  return {
    scale = scale,
    edge = e.canvas * scale,
    joint = j.canvas * jointScale,
    out = (j.canvas - j.extent) * jointScale,
    reach = j.extent * jointScale,
    inset = st.edgeInset * scale,
  }
end

-- Crops each edge strip to its drawn length so the metal is not stretched,
-- up to the painted part of the strip.
function pw.CropStatsBorder(win, width, height)
  local border = win.statsBorder
  if not border then return end
  local e = pw.Token().stats.edge
  local g = pw.StatsBorderGeometry()
  local across = math.min((width - g.inset * 2) / g.scale, e.painted) / e.length
  local down = math.min((height - g.inset * 2) / g.scale, e.painted) / e.length
  if across < 0 then across = 0 end
  if down < 0 then down = 0 end
  pcall(function()
    border.left:SetTexCoord(0, 1, 0, down)
    border.right:SetTexCoord(1, 0, 0, down)
    border.top:SetTexCoord(0, across, 0, 1)
    border.bottom:SetTexCoord(0, across, 1, 0)
  end)
end

function pw.StatsLine(win, i)
  local line = win.statsLines[i]
  if line then return line end
  local t = pw.Token()
  line = {
    left = pw.Label(win.stats, M.fontSize.normal, t.bodyColor, "LEFT", "GameFontHighlight"),
    right = pw.Label(win.stats, M.fontSize.normal, t.bodyColor, "RIGHT", "GameFontHighlight"),
  }
  win.statsLines[i] = line
  return line
end

-- Shows the panel for an equippable product and narrows the name beside it.
function pw.FillStats(win, entry)
  local panel = win.stats
  if not panel then return end
  local st = pw.Token().stats

  local lines = entry and pw.StatLines(win, entry.index)
  local count = lines and table.getn(lines) or 0
  local i
  for i = count + 1, table.getn(win.statsLines) do
    pw.SetShown(win.statsLines[i].left, false)
    pw.SetShown(win.statsLines[i].right, false)
  end
  pw.SetShown(panel, count > 0)

  -- The name runs to the form's right inset; beside the panel it stops
  -- nameGap short of the panel's left edge instead.
  local nameWidth = win.nameWidth or 1
  if count > 0 then
    nameWidth = nameWidth -
      (st.width + st.right + st.nameGap - pw.Token().schematic.inset)
  end
  if win.name then pcall(win.name.SetWidth, win.name, math.max(1, nameWidth)) end
  if count == 0 then return end

  local inner = st.width - st.padding * 2
  local total = 0
  local previous
  for i = 1, count do
    local data = lines[i]
    local line = pw.StatsLine(win, i)
    local rightWidth = 0
    pw.SetShown(line.right, data.right ~= nil)
    if data.right then
      pw.SetText(line.right, data.right)
      pw.SetColor(line.right, data.rightColor)
      rightWidth = pw.TextWidth(line.right) + st.columnGap
    end
    pw.SetShown(line.left, true)
    pw.SetText(line.left, data.left or "")
    if data.leftColor then pw.SetColor(line.left, data.leftColor) end
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

    -- A wrapped line is taller than one row; an unreadable height counts as one.
    local hOk, height = false, 0
    if line.left then hOk, height = pcall(line.left.GetHeight, line.left) end
    height = hOk and tonumber(height) or 0
    if height <= 0 then height = M.fontSize.normal + 2 end
    total = total + height
    if previous then total = total + st.lineGap end
    previous = line.left
  end

  local minimum = pw.StatsBorderGeometry().reach * 2
  local height = math.max(minimum, total + st.padding * 2)
  pcall(panel.SetHeight, panel, height)
  pw.CropStatsBorder(win, st.width, height)
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

-- The host's design size. Set once at build, the host came back at about the
-- stock 512 height while the fixed-height panels kept 525 and ran out of the
-- bottom rim (user screenshot, 2026-09-16); what resizes it natively is not
-- identified, so every refresh -- deferred after OnShow and each native
-- update -- puts the size back.
function pw.ApplySize(win)
  local d = pw.Token().design
  local frame = win.frame
  local wOk, width = pcall(frame.GetWidth, frame)
  local hOk, height = pcall(frame.GetHeight, frame)
  if not (wOk and tonumber(width) == d.width) then
    pcall(frame.SetWidth, frame, d.width)
  end
  if not (hOk and tonumber(height) == d.height) then
    pcall(frame.SetHeight, frame, d.height)
  end
end

function pw.Refresh(win)
  if not win.built or not pw.Shown(win.frame) then return end
  pw.ApplySize(win)

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
  -- A recipe directly followed by a category header ends its category; a
  -- header directly followed by a recipe starts one.
  for i = 1, table.getn(entries) - 1 do
    local header, nextHeader = entries[i].kind == "header", entries[i + 1].kind == "header"
    entries[i].groupEnd = not header and nextHeader
    entries[i].groupStart = header and not nextHeader
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
  pw.ApplySize(win)
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
  return type(U.ModernWowSurfaceEnabled) == "function" and
         U.ModernWowSurfaceEnabled(pw.SURFACE) and true or false
end

-- For modules/castbar.lua's craft dock: the shown window's own addon-owned
-- Create All button and the gap to keep left of it, or nil. The Craft window
-- (Enchanting, Beast Training) has no Create All and offers nothing.
function U.ProfessionsCastBarAnchor()
  local i
  for i = 1, table.getn(pw.windows) do
    local win = pw.windows[i]
    if win.createAll and pw.Shown(win.frame) and pw.Shown(win.createAll) then
      local b = pw.Token().button
      return win.createAll, b.castBarGap, b.castBarShiftX, b.castBarShiftY
    end
  end
  return nil
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
