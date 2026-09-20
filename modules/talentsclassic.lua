-- unrealUI :: modules/talentsclassic.lua
--
-- The Talent window's complete `classic-wow` drawing path (user request,
-- 2026-09-21): the same three-tree interface the other two paths draw -- all
-- three talent trees side by side, addon-owned talent buttons, prerequisite
-- branches and arrows, a per-tree header with its icon, name, roles and spent
-- points -- housed in the client's own chrome instead of Dragonflight's.
--
-- modules/talents.lua chooses this path in its own BuildFrame, when classic-wow
-- is active and its Talents Classic -> Modern WoW module is off. With that
-- module on, modules/talentsmodernwow.lua draws the Dragonflight version
-- instead -- the same arrangement the Quest Log already has, where switching
-- the module off hands the window to UnrealUI's classic-styled redraw rather
-- than back to the untouched native frame.
--
-- The per-tree header is the modern-wow header (user request, 2026-09-21):
-- the same TalentFrame-Parts parchment cell vertex coloured with the tree's
-- TALENT_INFO colour, gold rim, golden-square icon frame, portrait-ring
-- spent-points ring over its stone disc, and role icons. That band is the one
-- place this path draws imported theme media, and its measurements live in
-- M.classicWow.talents.header beside the rest. Below it nothing is imported
-- art, and nothing here is flat UnrealUI chrome:
--
--  * The window is Blizzard's DialogBox housing (UI-DialogBox-Background /
--    -Border at a whole 32-unit edge), which is how the client itself frames a
--    window whose size is not one of the authored quadrant sets. Backdrop edge
--    art does draw here -- what fails is a fractional edgeSize
--    (rendering.backdrop_edge_fractional_not_rasterized) -- and the same
--    whole-unit backdrop pattern already ships in Character's stat boxes.
--  * Each tree sits in Blizzard's tooltip-bordered inset, the stock way a
--    window recesses a list or tree.
--  * The tree background, talent slot, rank border, highlight, branch and arrow
--    sheets are all the client's own files, named once in M.talentTree.texture.
--    The tree art is knowledge.json / talent.tab_info_background_textures
--    (BEHAVIOR_VERIFIED); the rest are the files the stock TalentFrame
--    templates name.
--  * The native close button keeps its own art and is only moved: classic-wow
--    never restyles a stock control.
--
-- The grid and background geometry deliberately matches the modern-wow path,
-- because both measure the *client's* tree artwork rather than a theme's.
--
-- Client data and the prerequisite/branch node walk are core/talentgrid.lua's,
-- shared with both other paths; nothing here reads a modern-wow token.
--
-- Nothing here reads or retains a native child beyond named lookups at build
-- and refresh (rules/unreal-ui.md, native widget ownership).
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media
local TG = U.TalentGrid

local tc = {
  THEME = "classic-wow",
  REFRESH_KEY = "talents.classic.refresh",
  built = false,
  frame = nil,
  frameName = nil,
  chrome = nil,
  panels = {},
  title = nil,
  status = nil,
}

function tc.Token()
  return M.classicWow.talents
end

function tc.Named(suffix)
  if not tc.frameName then return nil end
  return U.G(tc.frameName .. suffix)
end

function tc.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function tc.Level(object)
  if not object or not object.GetFrameLevel then return 1 end
  local ok, level = pcall(object.GetFrameLevel, object)
  return (ok and tonumber(level)) or 1
end

function tc.Hide(object)
  if object then pcall(object.Hide, object) end
end

function tc.Texture(parent, layer, path, coords)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  if coords then
    pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
  end
  return texture
end

-- The client's own art paths, shared with every other talent path.
function tc.Art()
  return M.talentTree.texture
end

-- ---------------------------------------------------------------------------
-- Native chrome
--
-- Both housings are ordinary Blizzard backdrops: the window's DialogBox frame
-- and the tooltip inset each tree recesses into. Every size is a whole unit,
-- which is the part this client rasterises reliably.
-- ---------------------------------------------------------------------------
function tc.Backdrop(frame, background, edge, spec, fill, border)
  if not frame or not frame.SetBackdrop then return false end
  if not pcall(frame.SetBackdrop, frame, {
    bgFile = background,
    edgeFile = edge,
    tile = true, tileSize = spec.tileSize, edgeSize = spec.edgeSize,
    insets = { left = spec.inset, right = spec.inset,
               top = spec.inset, bottom = spec.inset },
  }) then
    return false
  end
  pcall(frame.SetBackdropColor, frame, M.Unpack(fill))
  pcall(frame.SetBackdropBorderColor, frame, M.Unpack(border))
  return true
end

function tc.WindowBackdrop(frame)
  local t = tc.Token()
  return tc.Backdrop(frame, t.texture.windowBackground, t.texture.windowBorder,
                     t.window, t.windowFill, t.windowEdge)
end

function tc.InsetBackdrop(frame)
  local t = tc.Token()
  return tc.Backdrop(frame, t.texture.insetBackground, t.texture.insetBorder,
                     t.panelInset, t.insetFill, t.insetEdge)
end

-- ---------------------------------------------------------------------------
-- Branches and arrows
--
-- The node walk and the prerequisite reader are core/talentgrid.lua's; only the
-- drawing is this path's, and it draws Blizzard's own branch and arrow sheets
-- with Blizzard's own cells (M.talentTree.branchCoords / arrowCoords).
-- ---------------------------------------------------------------------------
function tc.ResetBranches(state)
  local g = tc.Token().grid
  local i
  TG.ResetNodes(state.nodes, g.rows, g.columns)
  for i = 1, table.getn(state.branches) do tc.Hide(state.branches[i]) end
  for i = 1, table.getn(state.arrows) do tc.Hide(state.arrows[i]) end
  state.branchIndex = 1
  state.arrowIndex = 1
end

function tc.Pooled(state, arrow)
  local art = tc.Art()
  local pool = arrow and state.arrows or state.branches
  local index = arrow and state.arrowIndex or state.branchIndex
  if arrow then
    state.arrowIndex = index + 1
  else
    state.branchIndex = index + 1
  end

  local texture = pool[index]
  if not texture then
    if arrow then
      texture = tc.Texture(state.arrowFrame, "OVERLAY", art.arrows)
    else
      texture = tc.Texture(state.branchFrame, "ARTWORK", art.branches)
    end
    if not texture then return nil end
    pool[index] = texture
  end
  return texture
end

function tc.SetBranchTexture(state, coords, x, y, width, height)
  local texture = tc.Pooled(state, false)
  if not texture or not coords then return end
  local size = tc.Token().grid.button
  pcall(function()
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    texture:SetWidth(width or size)
    texture:SetHeight(height or size)
    texture:Show()
  end)
end

function tc.SetArrowTexture(state, coords, x, y)
  local texture = tc.Pooled(state, true)
  if not texture or not coords then return end
  local size = tc.Token().grid.button
  pcall(function()
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    texture:SetWidth(size)
    texture:SetHeight(size)
    texture:Show()
  end)
end

function tc.DrawBranches(state)
  local t = tc.Token()
  local g = t.grid
  local branch = t.branchCoords
  local arrow = t.arrowCoords
  local size = g.button
  local i, j

  for i = 1, g.rows do
    for j = 1, g.columns do
      local node = state.nodes[i][j]
      local x = ((j - 1) * g.pitch) + g.left
      local y = -((i - 1) * g.pitch) - g.top

      -- Right and down are always drawn here; left and up belong to the
      -- preceding talent.
      if node.down ~= 0 then
        tc.SetBranchTexture(state, branch.down[node.down], x, y - size,
                            size, g.pitch - size)
      end
      if node.right ~= 0 then
        tc.SetBranchTexture(state, branch.right[node.right], x + size, y,
                            g.pitch - size, size)
      end

      if node.id then
        if node.rightArrow ~= 0 then
          tc.SetArrowTexture(state, arrow.right[node.rightArrow], x + size / 2, y)
        end
        if node.leftArrow ~= 0 then
          tc.SetArrowTexture(state, arrow.left[node.leftArrow], x - size / 2, y)
        end
        if node.topArrow ~= 0 then
          tc.SetArrowTexture(state, arrow.top[node.topArrow], x, y + size / 2)
        end
      else
        if node.up ~= 0 and node.left ~= 0 and node.right ~= 0 then
          tc.SetBranchTexture(state, branch.tup[node.up], x, y)
        elseif node.down ~= 0 and node.left ~= 0 and node.right ~= 0 then
          tc.SetBranchTexture(state, branch.tdown[node.down], x, y)
        elseif node.left ~= 0 and node.down ~= 0 then
          tc.SetBranchTexture(state, branch.topright[node.left], x, y)
        elseif node.left ~= 0 and node.up ~= 0 then
          tc.SetBranchTexture(state, branch.bottomright[node.left], x, y)
        elseif node.left ~= 0 and node.right ~= 0 then
          tc.SetBranchTexture(state, branch.right[node.right], x + size, y)
        elseif node.right ~= 0 and node.down ~= 0 then
          tc.SetBranchTexture(state, branch.topleft[node.right], x, y)
        elseif node.right ~= 0 and node.up ~= 0 then
          tc.SetBranchTexture(state, branch.bottomleft[node.right], x, y)
        elseif node.up ~= 0 and node.down ~= 0 then
          tc.SetBranchTexture(state, branch.up[node.up], x, y)
        end
      end
    end
  end

  for i = state.branchIndex, table.getn(state.branches) do
    tc.Hide(state.branches[i])
  end
  for i = state.arrowIndex, table.getn(state.arrows) do
    tc.Hide(state.arrows[i])
  end
end

-- ---------------------------------------------------------------------------
-- Talent buttons
--
-- The stock TalentButtonTemplate's own pieces: the 64-unit UI-EmptySlot-White
-- ring behind a 30-unit icon, TalentFrame-RankBorder with the rank count in it,
-- and the square button highlight, all at the template's authored proportions.
-- ---------------------------------------------------------------------------
function tc.OnEnter(button, tab, index)
  if not GameTooltip then return end
  pcall(GameTooltip.SetOwner, GameTooltip, button, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetTalent, GameTooltip, tab, index)
  pcall(GameTooltip.Show, GameTooltip)
end

function tc.OnLeave()
  if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

function tc.OnClick(tab, index)
  if type(LearnTalent) == "function" then
    pcall(LearnTalent, tab, index)
  end
  U.DeferOnce(tc.REFRESH_KEY, tc.Refresh)
end

function tc.BuildButton(state, index)
  local t = tc.Token()
  local g = t.grid
  local art = tc.Art()
  local k = g.button / g.designButton

  local ok, button = pcall(CreateFrame, "Button", nil, state.frame)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, g.button)
  pcall(button.SetHeight, button, g.button)
  pcall(button.SetFrameLevel, button, tc.Level(state.frame) + 2)
  pcall(button.EnableMouse, button, true)

  local slot = tc.Texture(button, "BACKGROUND", art.slot)
  if slot then
    pcall(function()
      slot:SetWidth(t.slot.size * k)
      slot:SetHeight(t.slot.size * k)
      slot:SetPoint("CENTER", button, "CENTER", 0, 0)
    end)
  end

  local icon = tc.Texture(button, "BORDER")
  if icon then
    pcall(function()
      icon:SetAllPoints(button)
      icon:SetTexCoord(t.icon.crop[1], t.icon.crop[2], t.icon.crop[3], t.icon.crop[4])
    end)
  end

  -- The rank border and its count live on their own frame, above every advisor
  -- mark (M.talentAdvisor.level): those marks are separate frames, so a region
  -- drawn on the button itself would sit under the next talent's animated
  -- border instead of over it.
  local badge = CreateFrame("Frame", nil, button)
  pcall(badge.SetAllPoints, badge, button)
  pcall(badge.EnableMouse, badge, false)
  pcall(badge.SetFrameLevel, badge,
        tc.Level(button) + M.talentAdvisor.level.badge)

  local rankBorder = tc.Texture(badge, "OVERLAY", art.rankBorder)
  if rankBorder then
    pcall(function()
      rankBorder:SetWidth(t.rankBorder.size * k)
      rankBorder:SetHeight(t.rankBorder.size * k)
      rankBorder:SetPoint("CENTER", button, "BOTTOMRIGHT",
                          t.rankBorder.x * k, t.rankBorder.y * k)
    end)
  end

  local rank = U.CreateLabel(badge, {
    size = M.fontSize.small,
    color = t.rankColor.normal,
    inherits = "GameFontNormalSmall",
  })
  if rank and rankBorder then
    pcall(rank.SetPoint, rank, "CENTER", rankBorder, "CENTER", 0, 0)
  end

  pcall(button.SetHighlightTexture, button, art.highlight)
  local hlOk, highlight = pcall(button.GetHighlightTexture, button)
  if hlOk and highlight then pcall(highlight.SetBlendMode, highlight, "ADD") end

  local tab = state.id
  button:SetScript("OnClick", function() tc.OnClick(tab, index) end)
  button:SetScript("OnEnter", function() tc.OnEnter(button, tab, index) end)
  button:SetScript("OnLeave", tc.OnLeave)

  button.uuiSlot = slot
  button.uuiIcon = icon
  button.uuiRankBadge = badge
  button.uuiRankBorder = rankBorder
  button.uuiRank = rank
  if type(U.TalentAdvisorBind) == "function" then
    U.TalentAdvisorBind(button)
  end
  state.buttons[index] = button
  return button
end

function tc.PaintButton(button, rank, maxRank, learnable)
  local t = tc.Token()
  local c = t.rankColor
  local d = t.disabledIcon
  local slot, icon, border, text = button.uuiSlot, button.uuiIcon,
                                  button.uuiRankBorder, button.uuiRank

  if learnable then
    if icon then
      pcall(icon.SetDesaturated, icon, nil)
      pcall(icon.SetVertexColor, icon, 1, 1, 1)
    end
    local color = (rank < maxRank) and c.available or c.maxed
    if slot then pcall(slot.SetVertexColor, slot, 1, 1, 1) end
    if text then pcall(text.SetTextColor, text, M.Unpack(color)) end
    if border then
      pcall(border.SetVertexColor, border, 1, 1, 1)
      pcall(border.Show, border)
    end
    if text then pcall(text.Show, text) end
  else
    if icon then
      pcall(icon.SetDesaturated, icon, 1)
      pcall(icon.SetVertexColor, icon, d[1], d[2], d[3])
    end
    if slot then pcall(slot.SetVertexColor, slot, 0.5, 0.5, 0.5) end
    if rank == 0 then
      tc.Hide(border)
      tc.Hide(text)
    else
      if border then
        pcall(border.SetVertexColor, border, 0.5, 0.5, 0.5)
        pcall(border.Show, border)
      end
      if text then
        pcall(text.SetTextColor, text, M.Unpack(c.disabled))
        pcall(text.Show, text)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Tree panels
--
-- A panel is a header row on the window's stone, and below it a
-- tooltip-bordered inset holding the client's own tree artwork, its buttons and
-- its branches.
-- ---------------------------------------------------------------------------
function tc.BuildPanel(host, index)
  local t = tc.Token()
  local h = t.header
  local p = t.panel

  -- The panel sits two levels above its host, leaving the level between it and
  -- the host to the recessed bed below. A backdrop draws with the frame that
  -- owns it, so the bed has to be a frame of its own at a strictly lower level
  -- than the artwork it recesses -- a child of the panel would draw its fill
  -- over the panel's own background regions instead.
  local panel = CreateFrame("Frame", nil, host)
  panel:SetWidth(p.width)
  panel:SetHeight(p.height)
  pcall(panel.SetFrameLevel, panel, tc.Level(host) + 2)
  pcall(panel.EnableMouse, panel, false)

  local state = {
    id = index,
    frame = panel,
    buttons = {},
    branches = {},
    arrows = {},
    branchIndex = 1,
    arrowIndex = 1,
  }
  state.nodes = TG.NewNodes(t.grid.rows, t.grid.columns)

  -- Blizzard's tooltip inset, recessing the tree under the header row. A
  -- sibling of the panel one level down, and never mouse-enabled.
  local bed = CreateFrame("Frame", nil, host)
  pcall(function()
    bed:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -h.bedTop)
    bed:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  end)
  pcall(bed.SetFrameLevel, bed, tc.Level(host) + 1)
  pcall(bed.EnableMouse, bed, false)
  tc.InsetBackdrop(bed)
  state.bed = bed

  -- The client's own tree artwork, in two pieces as the stock talent panel
  -- draws it. Both are regions of the panel, so they stay under every button.
  local bg = t.background
  state.bgTop = tc.Texture(panel, "BACKGROUND", nil, bg.topTexCoord)
  if state.bgTop then
    pcall(function()
      state.bgTop:SetWidth(bg.width)
      state.bgTop:SetHeight(bg.topHeight)
      state.bgTop:SetPoint("TOPLEFT", panel, "TOPLEFT", bg.x, -bg.y)
    end)
  end
  state.bgBottom = tc.Texture(panel, "BACKGROUND", nil, bg.bottomTexCoord)
  if state.bgBottom and state.bgTop then
    pcall(function()
      state.bgBottom:SetWidth(bg.width)
      state.bgBottom:SetHeight(bg.bottomHeight)
      state.bgBottom:SetPoint("TOPLEFT", state.bgTop, "BOTTOMLEFT", 0, 0)
    end)
  end

  -- The 1-unit light rule along the artwork's top edge, as the stock panel has.
  local rule = tc.Texture(panel, "BORDER", M.texture.plain)
  if rule and state.bgTop then
    pcall(function()
      rule:SetHeight(1)
      rule:SetPoint("TOPLEFT", state.bgTop, "TOPLEFT", 0, 0)
      rule:SetPoint("TOPRIGHT", state.bgTop, "TOPRIGHT", 0, 0)
      rule:SetVertexColor(1, 1, 1, bg.ruleAlpha)
    end)
  end

  -- The header band: the same header the modern-wow path draws (user request,
  -- 2026-09-21). The dark TalentFrame-Parts parchment cell, vertex coloured
  -- with the tree's own colour in RefreshPanel, under its uncoloured gold rim.
  local parts = t.texture.talentFrameParts
  state.header = tc.Texture(panel, "BACKGROUND", parts, h.texCoord)
  if state.header then
    pcall(function()
      state.header:SetWidth(h.width)
      state.header:SetHeight(h.height)
      state.header:SetPoint("TOPLEFT", panel, "TOPLEFT", h.x, -h.y)
    end)
  end

  local rim = state.header and tc.Texture(panel, "ARTWORK", parts, h.borderTexCoord)
  if rim then
    pcall(function()
      rim:SetWidth(h.width)
      rim:SetHeight(h.height)
      rim:SetPoint("TOPLEFT", state.header, "TOPLEFT", 0, 0)
    end)
  end

  -- Header contents sit on a child frame, so they draw above the artwork and
  -- the inset without ever taking the mouse.
  local top = CreateFrame("Frame", nil, panel)
  top:SetAllPoints(panel)
  pcall(top.SetFrameLevel, top, tc.Level(panel) + 3)
  pcall(top.EnableMouse, top, false)

  state.icon = tc.Texture(top, "BORDER")
  if state.icon and state.header then
    pcall(function()
      state.icon:SetWidth(h.iconSize)
      state.icon:SetHeight(h.iconSize)
      state.icon:SetPoint("TOPLEFT", state.header, "TOPLEFT", h.iconX, -h.iconY)
      state.icon:SetTexCoord(t.icon.crop[1], t.icon.crop[2],
                             t.icon.crop[3], t.icon.crop[4])
    end)
  end

  -- The gold square frame, scaled from its measured opening so the icon fills
  -- it edge to edge.
  local ib = h.iconBorder
  local iconBorder = state.icon and tc.Texture(top, "ARTWORK", t.texture.iconBorder)
  if iconBorder then
    pcall(function()
      local w = h.iconSize * ib.canvas / (ib.right - ib.left)
      local hh = h.iconSize * ib.canvas / (ib.bottom - ib.top)
      iconBorder:SetWidth(w)
      iconBorder:SetHeight(hh)
      iconBorder:SetPoint("TOPLEFT", state.icon, "TOPLEFT",
                          -w * ib.left / ib.canvas, hh * ib.top / ib.canvas)
    end)
  end

  -- The spent-points stack sits on its own frame level above the icon frame,
  -- ordered by draw layer: stone disc (BORDER), ring (ARTWORK), count (OVERLAY).
  local count = CreateFrame("Frame", nil, panel)
  count:SetAllPoints(panel)
  pcall(count.SetFrameLevel, count, tc.Level(panel) + 4)
  pcall(count.EnableMouse, count, false)

  local circle = state.icon and tc.Texture(count, "ARTWORK", t.texture.portraitRing,
                                           h.ringTexCoord)
  if circle then
    pcall(function()
      circle:SetWidth(h.pointsSize)
      circle:SetHeight(h.pointsSize)
      circle:SetPoint("BOTTOMRIGHT", state.icon, "BOTTOMRIGHT", h.pointsX, h.pointsY)
    end)
  end

  -- The stone disc filling the ring's opening out to the middle of its gold
  -- band (measured in M.classicWow.talents.header.pointsDisc).
  local pd = h.pointsDisc
  local disc = circle and tc.Texture(count, "BORDER", t.texture.pointsBackground)
  if disc then
    pcall(function()
      local scale = h.pointsSize / pd.crop
      disc:SetWidth((pd.right - pd.left) * scale)
      disc:SetHeight((pd.bottom - pd.top) * scale)
      disc:SetPoint("TOPLEFT", circle, "TOPLEFT", pd.left * scale, -pd.top * scale)
    end)
  end

  state.points = U.CreateLabel(count, {
    size = M.fontSize.small,
    color = t.pointsColor,
    inherits = "GameFontHighlightSmall",
  })
  if state.points and disc then
    pcall(state.points.SetPoint, state.points, "CENTER", disc, "CENTER", 0, h.pointsTextY)
  elseif state.points and circle then
    pcall(state.points.SetPoint, state.points, "CENTER", circle, "CENTER", 0, h.pointsTextY)
  elseif state.points and state.icon then
    pcall(state.points.SetPoint, state.points, "CENTER", state.icon,
          "BOTTOMRIGHT", h.pointsX, h.pointsY)
  end

  state.name = U.CreateLabel(top, {
    size = M.fontSize.normal,
    color = t.nameColor,
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if state.name and state.header then
    pcall(function()
      state.name:SetPoint("TOPLEFT", state.header, "TOPLEFT", h.nameX, -h.nameY)
      state.name:SetPoint("RIGHT", panel, "RIGHT", -h.nameRight, 0)
    end)
  end

  -- The tree's roles at the header's top right, slot 1 outermost. Display only
  -- -- no tooltip, since the shared GameTooltip is off limits
  -- (rules/unreal-ui-design.md) -- and never mouse-enabled.
  local r = h.roleIcon
  state.roles = {}
  local slot
  for slot = 1, 2 do
    local icon = state.header and tc.Texture(top, "ARTWORK", t.texture.roleIcons)
    if icon then
      pcall(function()
        icon:SetWidth(r.size)
        icon:SetHeight(r.size)
        if slot == 1 then
          icon:SetPoint("TOPRIGHT", state.header, "TOPRIGHT", r.x, r.y)
        else
          icon:SetPoint("RIGHT", state.roles[1], "LEFT", -r.gap, 0)
        end
      end)
      tc.Hide(icon)
      state.roles[slot] = icon
    end
  end

  state.branchFrame = CreateFrame("Frame", nil, panel)
  state.branchFrame:SetAllPoints(panel)
  pcall(state.branchFrame.SetFrameLevel, state.branchFrame, tc.Level(panel) + 1)
  pcall(state.branchFrame.EnableMouse, state.branchFrame, false)

  state.arrowFrame = CreateFrame("Frame", nil, panel)
  state.arrowFrame:SetAllPoints(panel)
  -- Over the advisor's marks, not under them: the buttons sit 2 levels above
  -- this panel, so the arrows take that offset plus the advisor's own arrow
  -- level (M.talentAdvisor.level).
  pcall(state.arrowFrame.SetFrameLevel, state.arrowFrame,
        tc.Level(panel) + 2 + M.talentAdvisor.level.arrow)
  pcall(state.arrowFrame.EnableMouse, state.arrowFrame, false)

  return state
end

function tc.RefreshPanel(state, unspent)
  local t = tc.Token()
  local g = t.grid
  local art = tc.Art()
  local id = state.id
  local name, icon, spent, background = TG.TabInfo(id)
  if not name then
    tc.Hide(state.frame)
    return
  end
  pcall(state.frame.Show, state.frame)
  -- The advisor matches a panel to a catalog tree by this file name, not by tab
  -- index (PaladinRetribution/PaladinCombat and the two Warlock trees do not
  -- agree with the index on this client).
  state.background = background

  if state.name then pcall(state.name.SetText, state.name, name) end
  if state.icon then pcall(state.icon.SetTexture, state.icon, icon) end
  if state.points then pcall(state.points.SetText, state.points, tostring(spent)) end

  -- The tree's exact TALENT_INFO colour on the parchment cell, as the
  -- modern-wow header takes it.
  local color = TG.TreeColor(background, id)
  if state.header then
    pcall(state.header.SetVertexColor, state.header, color[1], color[2], color[3], 1)
  end

  -- With two roles they swap, so the list's last role takes slot 1 (far right)
  -- and its first sits beside it.
  local roles = TG.TreeRoles(background)
  local shown = roles
  if roles[2] then shown = { roles[2], roles[1] } end
  local cells = t.header.roleIcon.cells
  local slot
  for slot = 1, 2 do
    local roleIcon = state.roles and state.roles[slot]
    local cell = roleIcon and shown[slot] and cells[shown[slot]]
    if cell then
      pcall(roleIcon.SetTexCoord, roleIcon, cell[1], cell[2], cell[3], cell[4])
      pcall(roleIcon.Show, roleIcon)
    elseif roleIcon then
      tc.Hide(roleIcon)
    end
  end

  if type(background) == "string" and background ~= "" then
    local base = art.backgroundBase .. background .. "-"
    if state.bgTop then pcall(state.bgTop.SetTexture, state.bgTop, base .. "TopLeft") end
    if state.bgBottom then
      pcall(state.bgBottom.SetTexture, state.bgBottom, base .. "BottomLeft")
    end
  end

  tc.ResetBranches(state)

  local count = TG.NumTalents(id)
  local i
  for i = 1, count do
    local button = state.buttons[i] or tc.BuildButton(state, i)
    local tName, tIcon, tier, column, rank, maxRank, meets = TG.TalentInfo(id, i)
    if button and tName and state.nodes[tier] and state.nodes[tier][column] then
      if button.uuiRank then
        pcall(button.uuiRank.SetText, button.uuiRank, tostring(rank))
      end
      state.nodes[tier][column].id = i

      pcall(function()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", state.frame, "TOPLEFT",
                        ((column - 1) * g.pitch) + g.left,
                        -((tier - 1) * g.pitch) - g.top)
      end)

      local forceDesaturated = (unspent <= 0 and rank == 0) and 1 or nil
      local tierUnlocked = ((tier - 1) * t.pointsPerTier <= spent) and 1 or nil
      if button.uuiIcon then pcall(button.uuiIcon.SetTexture, button.uuiIcon, tIcon) end

      local prereqsSet = TG.SetPrereqs(state.nodes, tier, column, forceDesaturated,
                                       tierUnlocked, id, i)
      tc.PaintButton(button, rank, maxRank, prereqsSet and meets)
      if type(U.TalentAdvisorTalentState) == "function" then
        U.TalentAdvisorTalentState(button, prereqsSet and meets)
      end
      pcall(button.Show, button)
    elseif button then
      tc.Hide(button)
    end
  end
  for i = count + 1, table.getn(state.buttons) do
    tc.Hide(state.buttons[i])
  end

  tc.DrawBranches(state)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- Unspent points, else the next level that grants one. This client has no
-- GetNextTalentLevel; the first point comes at level 10 and one more at every
-- level up to the cap.
function tc.RefreshStatus(unspent)
  local label = tc.status
  if not label then return end
  local t = tc.Token()
  local level = TG.PlayerLevel()
  local text
  if unspent > 0 then
    text = string.format(U.L("TALENTS_UNSPENT_POINTS"), unspent)
  elseif level < t.firstTalentLevel then
    text = string.format(U.L("TALENTS_NEXT_LEVEL"), t.firstTalentLevel)
  elseif level < t.maxLevel then
    text = string.format(U.L("TALENTS_NEXT_LEVEL"), level + 1)
  end
  if text then
    pcall(label.SetText, label, text)
    pcall(label.Show, label)
  else
    tc.Hide(label)
  end
end

-- The native single-tree layout the three panels replace, plus the window's own
-- title region: a region of the window draws beneath its children -- here
-- beneath the chrome -- so this path owns the title. Re-hidden on every refresh
-- because the client's own update may show them again.
function tc.HideNative()
  tc.Hide(tc.Named("ScrollFrame"))
  tc.Hide(tc.Named("SpentPoints"))
  tc.Hide(tc.Named("TalentPointsText"))
  -- The "Talent Points:" caption beside that value. Name from the stock 1.12
  -- TalentFrame layout, not runtime-verified here; a missing global is nil and
  -- simply skipped.
  tc.Hide(tc.Named("TalentPoints"))
  tc.Hide(tc.Named("CancelButton"))
  tc.Hide(tc.Named("TitleText"))
  local i
  for i = 1, 5 do tc.Hide(tc.Named("Tab" .. i)) end
end

function tc.Refresh()
  if not tc.built or not tc.Shown(tc.frame) then return end
  tc.HideNative()
  local unspent = TG.UnspentPoints()
  local i
  for i = 1, table.getn(tc.panels) do
    local ok, err = pcall(tc.RefreshPanel, tc.panels[i], unspent)
    if not ok then U.Error("talents classic panel " .. i .. ": " .. tostring(err)) end
  end
  tc.RefreshStatus(unspent)
  if type(U.RefreshTalentAdvisor) == "function" then
    local ok, err = pcall(U.RefreshTalentAdvisor)
    if not ok then U.Error("talent advisor refresh: " .. tostring(err)) end
  end
end

function tc.OnEvent()
  if tc.Shown(tc.frame) then U.DeferOnce(tc.REFRESH_KEY, tc.Refresh) end
end

-- The client's own close button, moved to the dialog's corner and otherwise
-- untouched. Re-placed on every OnShow, as the other paths re-place theirs.
function tc.PlaceWindowControls()
  local t = tc.Token()
  tc.Hide(tc.Named("TitleText"))

  local close = tc.Named("CloseButton")
  if close then
    pcall(function()
      close:ClearAllPoints()
      close:SetPoint("TOPRIGHT", tc.frame, "TOPRIGHT", t.close.x, t.close.y)
    end)
  end
  return close
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- classic-wow, with its Talents Classic -> Modern WoW module off: with that
-- module on, modules/talentsmodernwow.lua claims the window first.
function U.ClassicTalentsWanted()
  if type(U.GetActiveThemeStyle) ~= "function" then return false end
  if U.GetActiveThemeStyle() ~= tc.THEME then return false end
  if type(U.ModernWowTalentsWanted) == "function" and U.ModernWowTalentsWanted() then
    return false
  end
  return true
end

-- Builds once. Called from modules/talents.lua under pcall, only after
-- U.ClassicTalentsWanted.
function U.BuildClassicTalents(frame)
  if tc.built then return true end
  if not frame then error("TalentFrame is unavailable") end

  local nameOk, name = pcall(frame.GetName, frame)
  if not nameOk or type(name) ~= "string" or name == "" then
    error("TalentFrame has no name")
  end
  tc.frame = frame
  tc.frameName = name

  -- Before any panel or button exists: the advisor binds its highlights as
  -- buttons are created. Its drawer and open/close arrow have no native
  -- counterpart, and by user request (2026-09-21) they draw the Modern WoW
  -- style here too -- the metal housing over its rock bed, the themed rules
  -- and row faces, and the bordered arrow -- so the drawer matches the tree
  -- headers this window already borrows from that path.
  if type(U.TalentAdvisorStyle) == "function" then
    U.TalentAdvisorStyle("modern-wow")
  end

  local t = tc.Token()
  local d = t.design
  local inset = t.inset

  -- Strip before any addon region exists on this frame (rules/unreal-ui.md,
  -- region walks never match by identity). Every addon region below lives on an
  -- addon-owned child.
  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  pcall(frame.SetWidth, frame, d.width)
  pcall(frame.SetHeight, frame, d.height)
  pcall(frame.SetHitRectInsets, frame, 0, 0, 0, 0)

  -- A generic window-chrome pass that reached this frame first is retired.
  local previous = frame.uuiModernWowWindow
  if type(previous) == "table" and previous.chrome then tc.Hide(previous.chrome) end

  -- The housing lives on an addon-owned child one frame level below the window,
  -- so every native region and child of TalentFrame still draws above it.
  local chrome = CreateFrame("Frame", nil, frame)
  chrome:SetAllPoints(frame)
  local level = tc.Level(frame)
  if level > 1 then pcall(chrome.SetFrameLevel, chrome, level - 1) end
  pcall(chrome.EnableMouse, chrome, false)
  tc.WindowBackdrop(chrome)
  tc.chrome = chrome

  tc.HideNative()
  local close = tc.PlaceWindowControls()

  -- The dialog's two header lines: the gold title and the white status line
  -- under it. A child of chrome, so both draw above the housing.
  local textFrame = CreateFrame("Frame", nil, chrome)
  textFrame:SetAllPoints(frame)
  pcall(textFrame.SetFrameLevel, textFrame, tc.Level(chrome) + 4)
  pcall(textFrame.EnableMouse, textFrame, false)
  tc.textFrame = textFrame

  tc.title = U.CreateLabel(textFrame, {
    size = M.fontSize.normal,
    color = t.titleColor,
    inherits = "GameFontNormal",
    justify = "CENTER",
  })
  if tc.title then
    pcall(function()
      tc.title:SetPoint("TOP", frame, "TOP", 0, -t.title.y)
      tc.title:SetText(U.L("TALENTS_TITLE"))
    end)
  end

  tc.status = U.CreateLabel(textFrame, {
    size = M.fontSize.normal,
    color = t.statusColor,
    inherits = "GameFontHighlight",
    justify = "CENTER",
  })
  if tc.status then
    pcall(tc.status.SetPoint, tc.status, "TOP", frame, "TOP", 0, -t.status.y)
  end

  local p = t.panel
  local i
  for i = 1, t.trees do
    -- Children of `chrome`, not siblings of it: a sibling panel could end up at
    -- chrome's own frame level, and the housing's backdrop would then draw over
    -- the tree artwork. A child always draws above its parent's regions,
    -- whatever the levels.
    local state = tc.BuildPanel(chrome, i)
    if i == 1 then
      state.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, -inset.top)
    else
      state.frame:SetPoint("TOPLEFT", tc.panels[i - 1].frame, "TOPRIGHT", p.gap, 0)
    end
    tc.panels[i] = state
  end

  local controls = {}
  if close then table.insert(controls, close) end
  if type(U.BuildTalentAdvisor) == "function" then
    local ok, control = pcall(U.BuildTalentAdvisor, frame, chrome, tc.panels)
    if ok and control then
      table.insert(controls, control)
    elseif not ok then
      U.Error("talent advisor build: " .. tostring(control))
    end
  end
  U.MakeWindowDraggable("talents", frame, {
    headerHeight = inset.top,
    headerInset = t.dragInset,
    interactiveFrames = controls,
  })

  U.PostHookScript(frame, "OnShow", function()
    tc.PlaceWindowControls()
    tc.Refresh()
  end)
  if type(U.G("TalentFrame_Update")) == "function" then
    U.PostHookGlobal("TalentFrame_Update", function()
      U.DeferOnce(tc.REFRESH_KEY, tc.Refresh)
    end)
  end
  U.RegisterEvent("CHARACTER_POINTS_CHANGED", tc.OnEvent)
  U.RegisterEvent("SPELLS_CHANGED", tc.OnEvent)
  U.RegisterEvent("PLAYER_LEVEL_UP", tc.OnEvent)

  tc.built = true
  tc.Refresh()
  return true
end
