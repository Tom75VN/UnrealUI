-- unrealUI :: modules/talentsmodernwow.lua
--
-- The Talent window's complete `modern-wow` drawing path: WoW-DragonflightUI's
-- three-panel talent frame (Mixin/Talents.mixin.lua, XML/Talents.xml,
-- Mixin/UI.mixin.lua ChangeTalentsEra) rebuilt on this client. All three trees
-- sit side by side in a 646x468 window, each on its own class background, with
-- addon-owned talent buttons, prerequisite branches and arrows.
--
-- modules/talents.lua chooses this path in its own BuildFrame, before any flat
-- styling, when the theme and the `talents` surface (modules/modernwow.lua) are
-- on.
--
-- Mechanism is WORKING_SOURCE from DF-main, adapted to this client:
--
--  * GetTalentTabInfo returns 4 values, background 4th (knowledge.json /
--    talent.tab_info_background_textures, BEHAVIOR_VERIFIED). DF-main's
--    8-value unpack, preview points, dual spec and the preview checkbox have no
--    counterpart here and are omitted. Role icons come from DF-main's own
--    static PlayerClassRoleTable, drawn without its tooltip.
--  * GetTalentInfo(tab, i) -> name, icon, tier, column, rank, maxRank, nil,
--    meetsPrereq; GetTalentPrereqs returns (tier, column, meetsRank) triples
--    (documentation.json, DOCUMENTED_NOT_RUNTIME_VERIFIED).
--  * The host is the client's own TalentFrame, widened like DF-main widens
--    PlayerTalentFrame, so the native open/close path is unchanged. Its
--    single-tree scroll frame, tabs and point labels are hidden, as DF-main
--    hides PlayerTalentFrameScrollFrame and its tabs.
--  * The atlas-only header art (TalentHeader-*) does not exist on this client;
--    its four cells are drawn from the shipped TalentFrame-Parts atlas instead:
--    parchment cell in the tree's exact DF-main colour and gold rim, with the
--    user-chosen golden-square-border icon frame and portrait-ring points ring
--    (locked by user request; see M.modernWow.talents.header).
--  * Tree colours are keyed by the background file name, not the tab index,
--    because this client orders tabs differently (Mage tab 1 is Fire).
--
-- Nothing here reads or retains a native child beyond named lookups at build
-- and refresh (rules/unreal-ui.md, native widget ownership).
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local tal = {
  THEME = "modern-wow",
  SURFACE = "talents",
  REFRESH_KEY = "talents.modernwow.refresh",
  built = false,
  frame = nil,
  frameName = nil,
  panels = {},
  status = nil,
}

function tal.Token()
  return M.modernWow.talents
end

function tal.Named(suffix)
  if not tal.frameName then return nil end
  return U.G(tal.frameName .. suffix)
end

function tal.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function tal.Level(object)
  if not object or not object.GetFrameLevel then return 1 end
  local ok, level = pcall(object.GetFrameLevel, object)
  return (ok and tonumber(level)) or 1
end

function tal.Texture(parent, layer, path, coords)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  if coords then
    pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
  end
  return texture
end

function tal.Hide(object)
  if object then pcall(object.Hide, object) end
end

-- ---------------------------------------------------------------------------
-- Client data
-- ---------------------------------------------------------------------------
function tal.TabInfo(tab)
  if type(GetTalentTabInfo) ~= "function" then return nil end
  local ok, name, icon, spent, background = pcall(GetTalentTabInfo, tab)
  if not ok then return nil end
  return name, icon, tonumber(spent) or 0, background
end

function tal.NumTalents(tab)
  if type(GetNumTalents) ~= "function" then return 0 end
  local ok, count = pcall(GetNumTalents, tab)
  return (ok and tonumber(count)) or 0
end

function tal.TalentInfo(tab, index)
  if type(GetTalentInfo) ~= "function" then return nil end
  local ok, name, icon, tier, column, rank, maxRank, _, meets =
    pcall(GetTalentInfo, tab, index)
  if not ok or not name then return nil end
  return name, icon, tonumber(tier) or 1, tonumber(column) or 1,
         tonumber(rank) or 0, tonumber(maxRank) or 0, meets
end

function tal.UnspentPoints()
  if type(UnitCharacterPoints) ~= "function" then return 0 end
  local ok, points = pcall(UnitCharacterPoints, "player")
  return (ok and tonumber(points)) or 0
end

function tal.PlayerLevel()
  local ok, level = pcall(UnitLevel, "player")
  return (ok and tonumber(level)) or 0
end

-- Looks a tree up by its background file name in a token table keyed by that
-- name (`treeColor`, `treeRoles`). The name is reduced to its bare, lower-cased
-- form ("Interface\TalentFrame\PaladinCombat-TopLeft.blp" -> "paladincombat")
-- and compared against a lower-cased copy of the table, so a path, suffix or
-- case difference cannot miss a class.
tal.treeKeys = {}
function tal.TreeLookup(field, background)
  local source = tal.Token()[field]
  if not source or type(background) ~= "string" or background == "" then return nil end
  local keys = tal.treeKeys[field]
  if not keys then
    keys = {}
    for key, value in pairs(source) do keys[string.lower(key)] = value end
    tal.treeKeys[field] = keys
  end
  local bare = string.gsub(background, "^.*[/\\]", "")
  bare = string.gsub(bare, "%.%a+$", "")
  bare = string.gsub(bare, "%-%a+$", "")
  return source[background] or keys[string.lower(bare)]
end

-- A tree's DF-main colour; an unmatched name falls back to the by-index default.
function tal.TreeColor(background, index)
  local t = tal.Token()
  return tal.TreeLookup("treeColor", background) or
         t.defaultColor[index] or t.defaultColor[1]
end

-- ---------------------------------------------------------------------------
-- Branches and arrows (DF-main TALENT_BRANCH_ARRAY)
-- ---------------------------------------------------------------------------
function tal.ResetBranches(state)
  local t = tal.Token()
  local i, j
  for i = 1, t.grid.rows do
    for j = 1, t.grid.columns do
      local node = state.nodes[i][j]
      node.id = nil
      node.up = 0
      node.down = 0
      node.left = 0
      node.right = 0
      node.rightArrow = 0
      node.leftArrow = 0
      node.topArrow = 0
    end
  end
  for i = 1, table.getn(state.branches) do tal.Hide(state.branches[i]) end
  for i = 1, table.getn(state.arrows) do tal.Hide(state.arrows[i]) end
  state.branchIndex = 1
  state.arrowIndex = 1
end

function tal.Pooled(state, arrow)
  local t = tal.Token()
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
      texture = tal.Texture(state.arrowFrame, "OVERLAY", t.texture.arrows)
    else
      texture = tal.Texture(state.branchFrame, "ARTWORK", t.texture.branches)
    end
    if not texture then return nil end
    pool[index] = texture
  end
  return texture
end

function tal.SetBranchTexture(state, coords, x, y, width, height)
  local texture = tal.Pooled(state, false)
  if not texture or not coords then return end
  local size = tal.Token().grid.button
  pcall(function()
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    texture:SetWidth(width or size)
    texture:SetHeight(height or size)
    texture:Show()
  end)
end

function tal.SetArrowTexture(state, coords, x, y)
  local texture = tal.Pooled(state, true)
  if not texture or not coords then return end
  local size = tal.Token().grid.button
  pcall(function()
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    texture:SetWidth(size)
    texture:SetHeight(size)
    texture:Show()
  end)
end

-- DF-main DrawLines, unchanged except that its blocked-layout message() calls
-- are dropped: a layout this client cannot draw simply draws no line.
function tal.DrawLines(state, buttonTier, buttonColumn, tier, column, requirementsMet)
  local nodes = state.nodes
  local met = requirementsMet and 1 or -1
  local i

  if not nodes[tier] or not nodes[buttonTier] then return end

  if buttonColumn == column then
    if (buttonTier - tier) > 1 then
      for i = tier + 1, buttonTier - 1 do
        if nodes[i][buttonColumn].id then return end
      end
    end
    for i = tier, buttonTier - 1 do
      nodes[i][buttonColumn].down = met
      if (i + 1) <= (buttonTier - 1) then
        nodes[i + 1][buttonColumn].up = met
      end
    end
    nodes[buttonTier][buttonColumn].topArrow = met
    return
  end

  if buttonTier == tier then
    local left = math.min(buttonColumn, column)
    local right = math.max(buttonColumn, column)
    if (right - left) > 1 then
      for i = left + 1, right - 1 do
        if nodes[tier][i].id then return end
      end
    end
    for i = left, right - 1 do
      nodes[tier][i].right = met
      nodes[tier][i + 1].left = met
    end
    if buttonColumn < column then
      nodes[buttonTier][buttonColumn].rightArrow = met
    else
      nodes[buttonTier][buttonColumn].leftArrow = met
    end
    return
  end

  -- Diagonal prerequisite.
  local left = math.min(buttonColumn, column)
  local right = math.max(buttonColumn, column)
  if left == column then
    left = left + 1
  else
    right = right - 1
  end
  local blocked = nil
  for i = left, right do
    if nodes[tier][i].id then blocked = 1 end
  end
  left = math.min(buttonColumn, column)
  right = math.max(buttonColumn, column)
  if not blocked then
    nodes[tier][buttonColumn].down = met
    nodes[buttonTier][buttonColumn].up = met
    for i = tier, buttonTier - 1 do
      nodes[i][buttonColumn].down = met
      nodes[i + 1][buttonColumn].up = met
    end
    for i = left, right - 1 do
      nodes[tier][i].right = met
      nodes[tier][i + 1].left = met
    end
    nodes[buttonTier][buttonColumn].topArrow = met
    return
  end

  -- Blocked vertically: go across first, then up.
  if left == buttonColumn then
    left = left + 1
  else
    right = right - 1
  end
  for i = left, right do
    if nodes[buttonTier][i].id then return end
  end
  for i = tier, buttonTier - 1 do
    nodes[i][column].up = met
    nodes[i + 1][column].down = met
  end
  if buttonColumn < column then
    nodes[buttonTier][buttonColumn].rightArrow = met
  else
    nodes[buttonTier][buttonColumn].leftArrow = met
  end
end

-- DF-main SetPrereqs. This client returns (tier, column, meetsRank) triples,
-- up to three, and has no preview state.
function tal.SetPrereqs(state, tier, column, forceDesaturated, tierUnlocked, tab, index)
  local requirementsMet = tierUnlocked and not forceDesaturated
  if type(GetTalentPrereqs) ~= "function" then return requirementsMet end

  local ok, t1, c1, m1, t2, c2, m2, t3, c3, m3 = pcall(GetTalentPrereqs, tab, index)
  if not ok then return requirementsMet end

  local prereqs = { { t1, c1, m1 }, { t2, c2, m2 }, { t3, c3, m3 } }
  local i
  for i = 1, 3 do
    local p = prereqs[i]
    local pTier, pColumn = tonumber(p[1]), tonumber(p[2])
    if pTier and pColumn then
      if forceDesaturated or not p[3] then requirementsMet = nil end
      tal.DrawLines(state, tier, column, pTier, pColumn, requirementsMet)
    end
  end
  return requirementsMet
end

function tal.DrawBranches(state)
  local t = tal.Token()
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
        tal.SetBranchTexture(state, branch.down[node.down], x, y - size,
                             size, g.pitch - size)
      end
      if node.right ~= 0 then
        tal.SetBranchTexture(state, branch.right[node.right], x + size, y,
                             g.pitch - size, size)
      end

      if node.id then
        if node.rightArrow ~= 0 then
          tal.SetArrowTexture(state, arrow.right[node.rightArrow], x + size / 2, y)
        end
        if node.leftArrow ~= 0 then
          tal.SetArrowTexture(state, arrow.left[node.leftArrow], x - size / 2, y)
        end
        if node.topArrow ~= 0 then
          tal.SetArrowTexture(state, arrow.top[node.topArrow], x, y + size / 2)
        end
      else
        if node.up ~= 0 and node.left ~= 0 and node.right ~= 0 then
          tal.SetBranchTexture(state, branch.tup[node.up], x, y)
        elseif node.down ~= 0 and node.left ~= 0 and node.right ~= 0 then
          tal.SetBranchTexture(state, branch.tdown[node.down], x, y)
        elseif node.left ~= 0 and node.down ~= 0 then
          tal.SetBranchTexture(state, branch.topright[node.left], x, y)
        elseif node.left ~= 0 and node.up ~= 0 then
          tal.SetBranchTexture(state, branch.bottomright[node.left], x, y)
        elseif node.left ~= 0 and node.right ~= 0 then
          tal.SetBranchTexture(state, branch.right[node.right], x + size, y)
        elseif node.right ~= 0 and node.down ~= 0 then
          tal.SetBranchTexture(state, branch.topleft[node.right], x, y)
        elseif node.right ~= 0 and node.up ~= 0 then
          tal.SetBranchTexture(state, branch.bottomleft[node.right], x, y)
        elseif node.up ~= 0 and node.down ~= 0 then
          tal.SetBranchTexture(state, branch.up[node.up], x, y)
        end
      end
    end
  end

  for i = state.branchIndex, table.getn(state.branches) do
    tal.Hide(state.branches[i])
  end
  for i = state.arrowIndex, table.getn(state.arrows) do
    tal.Hide(state.arrows[i])
  end
end

-- ---------------------------------------------------------------------------
-- Talent buttons (DF-main PlayerTalentButtonTemplate, scaled 30/37)
-- ---------------------------------------------------------------------------
function tal.OnEnter(button, tab, index)
  if not GameTooltip then return end
  pcall(GameTooltip.SetOwner, GameTooltip, button, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetTalent, GameTooltip, tab, index)
  pcall(GameTooltip.Show, GameTooltip)
end

function tal.OnLeave()
  if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

function tal.OnClick(tab, index)
  if type(LearnTalent) == "function" then
    pcall(LearnTalent, tab, index)
  end
  U.DeferOnce(tal.REFRESH_KEY, tal.Refresh)
end

function tal.BuildButton(state, index)
  local t = tal.Token()
  local g = t.grid
  local k = g.button / g.designButton

  local ok, button = pcall(CreateFrame, "Button", nil, state.frame)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, g.button)
  pcall(button.SetHeight, button, g.button)
  pcall(button.SetFrameLevel, button, tal.Level(state.frame) + 2)
  pcall(button.EnableMouse, button, true)

  local slot = tal.Texture(button, "BACKGROUND", t.texture.slot)
  if slot then
    pcall(function()
      slot:SetWidth(t.slot.size * k)
      slot:SetHeight(t.slot.size * k)
      slot:SetPoint("CENTER", button, "CENTER", 0, 0)
    end)
  end

  local icon = tal.Texture(button, "BORDER")
  if icon then pcall(icon.SetAllPoints, icon, button) end

  local rankBorder = tal.Texture(button, "OVERLAY", t.texture.rankBorder)
  if rankBorder then
    pcall(function()
      rankBorder:SetWidth(t.rankBorder.size * k)
      rankBorder:SetHeight(t.rankBorder.size * k)
      rankBorder:SetPoint("CENTER", button, "BOTTOMRIGHT",
                          t.rankBorder.x * k, t.rankBorder.y * k)
    end)
  end

  local rank = U.CreateLabel(button, {
    size = M.fontSize.small,
    color = t.rankColor.normal,
    inherits = "GameFontNormalSmall",
  })
  if rank and rankBorder then
    pcall(rank.SetPoint, rank, "CENTER", rankBorder, "CENTER", 0, 0)
  end

  pcall(button.SetHighlightTexture, button, t.texture.highlight)
  local hlOk, highlight = pcall(button.GetHighlightTexture, button)
  if hlOk and highlight then pcall(highlight.SetBlendMode, highlight, "ADD") end

  local tab = state.id
  button:SetScript("OnClick", function() tal.OnClick(tab, index) end)
  button:SetScript("OnEnter", function() tal.OnEnter(button, tab, index) end)
  button:SetScript("OnLeave", tal.OnLeave)

  button.uuiSlot = slot
  button.uuiIcon = icon
  button.uuiRankBorder = rankBorder
  button.uuiRank = rank
  state.buttons[index] = button
  return button
end

function tal.PaintButton(button, rank, maxRank, learnable)
  local t = tal.Token()
  local c = t.rankColor
  local slot, icon, border, text = button.uuiSlot, button.uuiIcon,
                                   button.uuiRankBorder, button.uuiRank

  if learnable then
    if icon then pcall(icon.SetDesaturated, icon, nil) end
    if icon then pcall(icon.SetVertexColor, icon, 1, 1, 1) end
    local color = (rank < maxRank) and c.available or c.maxed
    if slot then pcall(slot.SetVertexColor, slot, color[1], color[2], color[3]) end
    if text then pcall(text.SetTextColor, text, M.Unpack(color)) end
    if border then
      pcall(border.SetVertexColor, border, 1, 1, 1)
      pcall(border.Show, border)
    end
    if text then pcall(text.Show, text) end
  else
    if icon then
      pcall(icon.SetDesaturated, icon, 1)
      pcall(icon.SetVertexColor, icon, 0.65, 0.65, 0.65)
    end
    if slot then pcall(slot.SetVertexColor, slot, 0.5, 0.5, 0.5) end
    if rank == 0 then
      tal.Hide(border)
      tal.Hide(text)
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
-- Panels (DFPlayerTalentFramePanelTemplate)
-- ---------------------------------------------------------------------------
function tal.BuildPanelBorder(panel)
  local t = tal.Token()
  local spec = t.panel.border
  local paths = t.texture.panelBorder
  if not spec or not paths then return end

  local size = tonumber(spec.size) or 16
  local function Piece(path, width, height)
    local texture = tal.Texture(panel, "BORDER", path)
    if texture then
      pcall(function()
        if width then texture:SetWidth(width) end
        if height then texture:SetHeight(height) end
      end)
    end
    return texture
  end

  -- DF-main gets this from InsetFrameTemplate2. The retail template is absent
  -- here, so its authored ThinBorder pieces form the same eight-slice rim.
  local topLeft = Piece(paths.topLeft, size, size)
  local topRight = Piece(paths.topRight, size, size)
  local bottomLeft = Piece(paths.bottomLeft, size, size)
  local bottomRight = Piece(paths.bottomLeft, size, size)
  if topLeft then topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0) end
  if topRight then topRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0) end
  if bottomLeft then bottomLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0) end
  if bottomRight then
    bottomRight:SetTexCoord(1, 0, 0, 1)
    bottomRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  end

  local top = Piece(paths.top, nil, size)
  if top and topLeft and topRight then
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
  end
  local bottom = Piece(paths.bottom, nil, size)
  if bottom and bottomLeft and bottomRight then
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
  end
  local left = Piece(paths.left, size, nil)
  if left and topLeft and bottomLeft then
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
  end
  local right = Piece(paths.right, size, nil)
  if right and topRight and bottomRight then
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
  end
end

function tal.BuildPanel(host, index)
  local t = tal.Token()
  local p = t.panel

  local panel = CreateFrame("Frame", nil, host)
  panel:SetWidth(p.width)
  panel:SetHeight(p.height)
  pcall(panel.SetFrameLevel, panel, tal.Level(host) + 1)
  pcall(panel.EnableMouse, panel, false)

  local state = {
    id = index,
    frame = panel,
    buttons = {},
    branches = {},
    arrows = {},
    nodes = {},
    branchIndex = 1,
    arrowIndex = 1,
  }
  local i, j
  for i = 1, t.grid.rows do
    state.nodes[i] = {}
    for j = 1, t.grid.columns do
      state.nodes[i][j] = { up = 0, down = 0, left = 0, right = 0,
                            leftArrow = 0, rightArrow = 0, topArrow = 0 }
    end
  end

  local bg = t.background
  state.bgTop = tal.Texture(panel, "BACKGROUND", nil, bg.topTexCoord)
  if state.bgTop then
    pcall(function()
      state.bgTop:SetWidth(bg.width)
      state.bgTop:SetHeight(bg.topHeight)
      state.bgTop:SetPoint("TOPLEFT", panel, "TOPLEFT", bg.x, -bg.y)
    end)
  end
  state.bgBottom = tal.Texture(panel, "BACKGROUND", nil, bg.bottomTexCoord)
  if state.bgBottom and state.bgTop then
    pcall(function()
      state.bgBottom:SetWidth(bg.width)
      state.bgBottom:SetHeight(bg.bottomHeight)
      state.bgBottom:SetPoint("TOPLEFT", state.bgTop, "BOTTOMLEFT", 0, 0)
    end)
  end

  -- Additive copies of both pieces, one layer up, lift the dark client art
  -- (M.modernWow.talents.background.brighten). Skipped when the token is 0
  -- or the client refuses ADD, so the plain art is never replaced.
  state.glow = {}
  if (tonumber(bg.brighten) or 0) > 0 then
    local pieces = { { state.bgTop, bg.topTexCoord }, { state.bgBottom, bg.bottomTexCoord } }
    local n
    for n = 1, 2 do
      local base, coords = pieces[n][1], pieces[n][2]
      local glow = base and tal.Texture(panel, "BORDER", nil, coords)
      if glow and pcall(glow.SetBlendMode, glow, "ADD") then
        pcall(function()
          glow:SetAllPoints(base)
          glow:SetAlpha(bg.brighten)
        end)
        state.glow[n] = glow
      elseif glow then
        tal.Hide(glow)
      end
    end
  end

  -- $parentBgHighlight: the 1-unit light rule along the background's top.
  local rule = tal.Texture(panel, "BORDER", M.texture.plain)
  if rule and state.bgTop then
    pcall(function()
      rule:SetHeight(1)
      rule:SetPoint("TOPLEFT", state.bgTop, "TOPLEFT", 0, 0)
      rule:SetPoint("TOPRIGHT", state.bgTop, "TOPRIGHT", 0, 0)
      rule:SetVertexColor(1, 1, 1, bg.ruleAlpha)
    end)
  end

  -- DF-main's TalentHeader-ParchmentBG: the dark parchment cell, vertex
  -- coloured with the tree colour in RefreshPanel.
  local h = t.header
  local parts = t.texture.talentFrameParts
  state.header = tal.Texture(panel, "BACKGROUND", parts, h.texCoord)
  if state.header then
    pcall(function()
      state.header:SetWidth(h.width)
      state.header:SetHeight(h.height)
      state.header:SetPoint("TOPLEFT", panel, "TOPLEFT", h.x, -h.y)
    end)
  end

  -- TalentHeader-GoldBorder, uncoloured, over the parchment cell.
  local rim = state.header and tal.Texture(panel, "ARTWORK", parts, h.borderTexCoord)
  if rim then
    pcall(function()
      rim:SetWidth(h.width)
      rim:SetHeight(h.height)
      rim:SetPoint("TOPLEFT", state.header, "TOPLEFT", 0, 0)
    end)
  end

  tal.BuildPanelBorder(panel)

  -- The header's contents sit on a child frame so they draw above the talent
  -- art but never take the mouse.
  local top = CreateFrame("Frame", nil, panel)
  top:SetAllPoints(panel)
  pcall(top.SetFrameLevel, top, tal.Level(panel) + 3)
  pcall(top.EnableMouse, top, false)

  state.icon = tal.Texture(top, "BORDER")
  if state.icon and state.header then
    pcall(function()
      state.icon:SetWidth(h.iconSize)
      state.icon:SetHeight(h.iconSize)
      state.icon:SetPoint("TOPLEFT", state.header, "TOPLEFT", h.iconX, -h.iconY)
      state.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
  end

  -- The user-supplied gold square frame, scaled from its measured opening so
  -- the icon fills it edge to edge, then the portrait ring as the spent-points
  -- ring in DF-main's PointCircle-Gold slot (23x23 at icon BOTTOMRIGHT 10, -6).
  local ib = h.iconBorder
  local iconBorder = state.icon and tal.Texture(top, "ARTWORK", t.texture.iconBorder)
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
  pcall(count.SetFrameLevel, count, tal.Level(panel) + 4)
  pcall(count.EnableMouse, count, false)

  local circle = state.icon and tal.Texture(count, "ARTWORK", t.texture.portraitRing,
                                            t.frame.portrait.ringTexCoord)
  if circle then
    pcall(function()
      circle:SetWidth(h.pointsSize)
      circle:SetHeight(h.pointsSize)
      circle:SetPoint("BOTTOMRIGHT", state.icon, "BOTTOMRIGHT", h.pointsX, h.pointsY)
    end)
  end

  -- The unit-frame portrait stone, filling the ring's opening out to the
  -- middle of its gold band (measured in M.modernWow.talents.header.pointsDisc).
  local pd = h.pointsDisc
  local disc = circle and tal.Texture(count, "BORDER", t.texture.pointsBackground)
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

  -- DF-main RoleIcon / RoleIcon2: slot 1 at the header's top-right, slot 2 to
  -- its left. Display only -- no tooltip, since the shared GameTooltip is off
  -- limits (rules/unreal-ui-design.md) -- and never mouse-enabled.
  local r = h.roleIcon
  state.roles = {}
  local slot
  for slot = 1, 2 do
    local icon = state.header and tal.Texture(top, "ARTWORK", t.texture.roleIcons)
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
      tal.Hide(icon)
      state.roles[slot] = icon
    end
  end

  state.branchFrame = CreateFrame("Frame", nil, panel)
  state.branchFrame:SetAllPoints(panel)
  pcall(state.branchFrame.SetFrameLevel, state.branchFrame, tal.Level(panel) + 1)
  pcall(state.branchFrame.EnableMouse, state.branchFrame, false)

  state.arrowFrame = CreateFrame("Frame", nil, panel)
  state.arrowFrame:SetAllPoints(panel)
  pcall(state.arrowFrame.SetFrameLevel, state.arrowFrame, tal.Level(panel) + 3)
  pcall(state.arrowFrame.EnableMouse, state.arrowFrame, false)

  return state
end

function tal.RefreshPanel(state, unspent)
  local t = tal.Token()
  local g = t.grid
  local id = state.id
  local name, icon, spent, background = tal.TabInfo(id)
  if not name then
    tal.Hide(state.frame)
    return
  end
  pcall(state.frame.Show, state.frame)

  if state.name then pcall(state.name.SetText, state.name, name) end
  if state.icon then pcall(state.icon.SetTexture, state.icon, icon) end
  if state.points then pcall(state.points.SetText, state.points, tostring(spent)) end

  -- Exact DF-main colour on the parchment cell, as its
  -- HeaderBackground:SetVertexColor(r, g, b). Locked by user request:
  -- see M.modernWow.talents.header before changing this.
  local color = tal.TreeColor(background, id)
  if state.header then
    pcall(state.header.SetVertexColor, state.header, color[1], color[2], color[3], 1)
  end

  -- DF-main UpdateRoleIcon: with two roles they swap, so the list's last role
  -- takes slot 1 (far right) and its first sits beside it.
  local roles = tal.TreeLookup("treeRoles", background) or {}
  local shown = roles
  if roles[2] then shown = { roles[2], roles[1] } end
  local cells = t.header.roleIcon.cells
  local slot
  for slot = 1, 2 do
    local icon = state.roles and state.roles[slot]
    local cell = icon and shown[slot] and cells[shown[slot]]
    if cell then
      pcall(icon.SetTexCoord, icon, cell[1], cell[2], cell[3], cell[4])
      pcall(icon.Show, icon)
    elseif icon then
      tal.Hide(icon)
    end
  end

  if type(background) == "string" and background ~= "" then
    local base = t.texture.backgroundBase .. background .. "-"
    if state.bgTop then pcall(state.bgTop.SetTexture, state.bgTop, base .. "TopLeft") end
    if state.bgBottom then
      pcall(state.bgBottom.SetTexture, state.bgBottom, base .. "BottomLeft")
    end
    local glow = state.glow or {}
    if glow[1] then pcall(glow[1].SetTexture, glow[1], base .. "TopLeft") end
    if glow[2] then pcall(glow[2].SetTexture, glow[2], base .. "BottomLeft") end
  end

  tal.ResetBranches(state)

  local count = tal.NumTalents(id)
  local i
  for i = 1, count do
    local button = state.buttons[i] or tal.BuildButton(state, i)
    local tName, tIcon, tier, column, rank, maxRank, meets = tal.TalentInfo(id, i)
    if button and tName and state.nodes[tier] and state.nodes[tier][column] then
      if button.uuiRank then pcall(button.uuiRank.SetText, button.uuiRank, tostring(rank)) end
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

      local prereqsSet = tal.SetPrereqs(state, tier, column, forceDesaturated,
                                        tierUnlocked, id, i)
      tal.PaintButton(button, rank, maxRank, prereqsSet and meets)
      pcall(button.Show, button)
    elseif button then
      tal.Hide(button)
    end
  end
  for i = count + 1, table.getn(state.buttons) do
    tal.Hide(state.buttons[i])
  end

  tal.DrawBranches(state)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- DF-main UpdateDFHeaderText: unspent points, else the next level that grants
-- one. This client has no GetNextTalentLevel; the first point comes at level
-- 10 and one more at every level up to the cap.
function tal.RefreshStatus(unspent)
  local label = tal.status
  if not label then return end
  local t = tal.Token()
  local level = tal.PlayerLevel()
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
    tal.Hide(label)
  end
end

-- The native single-tree layout the three panels replace. Re-hidden on every
-- refresh because the client's own update may show it again.
function tal.HideNative()
  tal.Hide(tal.Named("ScrollFrame"))
  tal.Hide(tal.Named("SpentPoints"))
  tal.Hide(tal.Named("TalentPointsText"))
  -- The "Talent Points:" caption beside that value. Name from the stock 1.12
  -- TalentFrame layout, not runtime-verified here; a missing global is nil
  -- and simply skipped.
  tal.Hide(tal.Named("TalentPoints"))
  tal.Hide(tal.Named("CancelButton"))
  local i
  for i = 1, 5 do tal.Hide(tal.Named("Tab" .. i)) end
end

function tal.Refresh()
  if not tal.built or not tal.Shown(tal.frame) then return end
  tal.HideNative()
  local unspent = tal.UnspentPoints()
  local i
  for i = 1, table.getn(tal.panels) do
    local ok, err = pcall(tal.RefreshPanel, tal.panels[i], unspent)
    if not ok then U.Error("talents modern-wow panel " .. i .. ": " .. tostring(err)) end
  end
  tal.RefreshStatus(unspent)
end

function tal.OnEvent()
  if tal.Shown(tal.frame) then U.DeferOnce(tal.REFRESH_KEY, tal.Refresh) end
end

function tal.PlaceWindowControls()
  local t = tal.Token()
  local frame = tal.frame

  -- The native title is a region of the window itself, and every region of a
  -- window draws beneath its children -- here, beneath the chrome. The header
  -- lines are addon labels on tal.textFrame instead (USER_CONFIRMED_INGAME
  -- screenshot, 2026-09-14: neither native title nor status was visible).
  tal.Hide(tal.Named("TitleText"))

  local close = tal.Named("CloseButton")
  if close then
    U.StyleStockCloseButton(close, frame, -t.close.x, -t.close.y)
    pcall(function()
      close:SetWidth(t.close.size)
      close:SetHeight(t.close.size)
    end)
  end
  return close
end

-- DF-main's window chrome, drawn on the addon-owned `chrome` frame one level
-- below the window so every native region and child stays above it. Layers
-- keep DF-main's stacking: rock body, title streak, inset bed, then the metal
-- nine-slice on top of all three.
function tal.BuildChrome(frame, chrome)
  local t = tal.Token()
  local tex = t.texture
  local f = t.frame
  local inset = t.inset

  local function Region(layer, path, coords)
    return tal.Texture(chrome, layer, path, coords)
  end

  local body = Region("BACKGROUND", tex.backgroundRock)
  if body then
    pcall(function()
      body:SetPoint("TOPLEFT", frame, "TOPLEFT", f.body.left, -f.body.top)
      body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -f.body.right, f.body.bottom)
    end)
  end

  local streak = Region("BORDER", tex.topStreak, f.streak.texCoord)
  if streak then
    pcall(function()
      streak:SetHeight(f.streak.height)
      streak:SetPoint("TOPLEFT", frame, "TOPLEFT", f.streak.left, -f.streak.top)
      streak:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -f.streak.right, -f.streak.top)
    end)
  end

  local bed = Region("ARTWORK", M.texture.plain)
  if bed then
    pcall(function()
      bed:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, -inset.top)
      bed:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset.right, inset.bottom)
      bed:SetVertexColor(M.Unpack(t.insetColor))
    end)
  end

  local function Corner(spec, point)
    local piece = Region("OVERLAY", tex.metalCorners, spec.texCoord)
    if piece then
      pcall(function()
        piece:SetWidth(spec.width)
        piece:SetHeight(spec.height)
        piece:SetPoint(point, frame, point, spec.x, spec.y)
      end)
    end
    return piece
  end
  local tl = Corner(f.cornerTopLeft, "TOPLEFT")
  local tr = Corner(f.cornerTopRight, "TOPRIGHT")
  local bl = Corner(f.cornerBottomLeft, "BOTTOMLEFT")
  local br = Corner(f.cornerBottomRight, "BOTTOMRIGHT")

  local top = Region("OVERLAY", tex.metalHorizontal, f.edgeTop.texCoord)
  if top and tl and tr then
    pcall(function()
      top:SetHeight(f.edgeTop.height)
      top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
      top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
    end)
  end
  local bottom = Region("OVERLAY", tex.metalHorizontal, f.edgeBottom.texCoord)
  if bottom and bl and br then
    pcall(function()
      bottom:SetHeight(f.edgeBottom.height)
      bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
      bottom:SetPoint("TOPRIGHT", br, "TOPLEFT", 0, 0)
    end)
  end
  local left = Region("OVERLAY", tex.metalVertical, f.edgeLeft.texCoord)
  if left and tl and bl then
    pcall(function()
      left:SetWidth(f.edgeLeft.width)
      left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
      left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
    end)
  end
  local right = Region("OVERLAY", tex.metalVertical, f.edgeRight.texCoord)
  if right and tr and br then
    pcall(function()
      right:SetWidth(f.edgeRight.width)
      right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
      right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    end)
  end

  -- Portrait: DF-main draws a spec icon; this client has none, so the class
  -- portrait from the theme's own atlas sits in DF-main's ring, as the
  -- Spellbook does. Its own frame, above the window content, never mouse.
  local p = f.portrait
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetWidth(p.ring)
  holder:SetHeight(p.ring)
  pcall(holder.SetFrameLevel, holder, tal.Level(frame) + 5)
  pcall(holder.EnableMouse, holder, false)
  pcall(holder.SetPoint, holder, "CENTER", frame, "TOPLEFT",
        p.x + p.size / 2, p.y - p.size / 2)

  local ok, _, class = pcall(UnitClass, "player")
  local cell = ok and class and M.modernWow.classCell[class]
  if cell then
    local portrait = tal.Texture(holder, "ARTWORK", M.modernWow.texture.classPortraits, cell)
    if portrait then
      pcall(function()
        portrait:SetWidth(p.size)
        portrait:SetHeight(p.size)
        portrait:SetPoint("CENTER", holder, "CENTER", 0, 0)
      end)
    end
  end
  local ring = tal.Texture(holder, "OVERLAY", tex.portraitRing, p.ringTexCoord)
  if ring then pcall(ring.SetAllPoints, ring, holder) end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
function U.ModernWowTalentsWanted()
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= tal.THEME then
    return false
  end
  return type(U.ModernWowSurfaceEnabled) == "function" and
         U.ModernWowSurfaceEnabled(tal.SURFACE) and true or false
end

function U.ModernWowTalentsActive()
  return tal.built
end

-- The same ThinBorder eight-slice rim, for another modern-wow window whose
-- panels stand in for DF-main's InsetFrameTemplate (modules/professions.lua).
-- Theme-gated like every other entry point here.
function U.ModernWowThinBorder(panel)
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= tal.THEME or not panel then
    return false
  end
  tal.BuildPanelBorder(panel)
  return true
end

-- Builds once. Called from modules/talents.lua under pcall, only after
-- U.ModernWowTalentsWanted.
function U.BuildModernWowTalents(frame)
  if tal.built then return true end
  if not frame then error("TalentFrame is unavailable") end

  local nameOk, name = pcall(frame.GetName, frame)
  if not nameOk or type(name) ~= "string" or name == "" then
    error("TalentFrame has no name")
  end
  tal.frame = frame
  tal.frameName = name

  local t = tal.Token()
  local d = t.design

  -- Strip before any addon region exists on this frame (rules/unreal-ui.md,
  -- region walks never match by identity). Every addon region below lives on
  -- an addon-owned child.
  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  pcall(frame.SetWidth, frame, d.width)
  pcall(frame.SetHeight, frame, d.height)
  pcall(frame.SetHitRectInsets, frame, 0, 0, 0, 0)

  -- A generic window-chrome pass that reached this frame first is retired.
  local previous = frame.uuiModernWowWindow
  if type(previous) == "table" and previous.chrome then tal.Hide(previous.chrome) end

  local chrome = CreateFrame("Frame", nil, frame)
  chrome:SetAllPoints(frame)
  local level = tal.Level(frame)
  if level > 1 then pcall(chrome.SetFrameLevel, chrome, level - 1) end
  pcall(chrome.EnableMouse, chrome, false)

  local inset = t.inset
  tal.BuildChrome(frame, chrome)
  frame.uuiModernWowWindow = { chrome = chrome, talents = true }

  tal.HideNative()
  local close = tal.PlaceWindowControls()
  if type(U.ModernWowDressCloseButton) == "function" then
    pcall(U.ModernWowDressCloseButton, name .. "CloseButton")
  end

  -- DF-main's two header lines: the gold title in the top bar and the white
  -- status line under it. A child of chrome, so it draws above the metal.
  local textFrame = CreateFrame("Frame", nil, chrome)
  textFrame:SetAllPoints(frame)
  pcall(textFrame.SetFrameLevel, textFrame, tal.Level(chrome) + 4)
  pcall(textFrame.EnableMouse, textFrame, false)
  tal.textFrame = textFrame

  tal.title = U.CreateLabel(textFrame, {
    size = M.fontSize.normal,
    color = t.titleColor,
    inherits = "GameFontNormal",
    justify = "CENTER",
  })
  if tal.title then
    pcall(function()
      tal.title:SetPoint("TOP", frame, "TOP", 0, -t.title.y)
      tal.title:SetText(U.L("TALENTS_TITLE"))
    end)
  end

  tal.status = U.CreateLabel(textFrame, {
    size = M.fontSize.normal,
    color = t.statusColor,
    inherits = "GameFontHighlight",
  })
  if tal.status then
    pcall(tal.status.SetPoint, tal.status, "TOP", frame, "TOP", 0, -t.status.y)
  end

  local p = t.panel
  local i
  for i = 1, t.trees do
    -- Children of `chrome`, not siblings of it: a sibling panel could end up
    -- at chrome's frame level after the window is raised, and chrome's inset
    -- bed (ARTWORK) then drew over the tree art (BACKGROUND), dimming it
    -- (USER_CONFIRMED_INGAME screenshot, 2026-09-14). A child always draws
    -- above its parent's regions, whatever the levels.
    local state = tal.BuildPanel(chrome, i)
    if i == 1 then
      state.frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
                           inset.left + p.x, inset.bottom + p.y)
    else
      state.frame:SetPoint("TOPLEFT", tal.panels[i - 1].frame, "TOPRIGHT", p.gap, 0)
    end
    tal.panels[i] = state
  end

  local controls = {}
  if close then table.insert(controls, close) end
  U.MakeWindowDraggable("talents", frame, {
    headerHeight = inset.top,
    headerInset = t.dragInset,
    interactiveFrames = controls,
  })

  U.PostHookScript(frame, "OnShow", function()
    tal.PlaceWindowControls()
    tal.Refresh()
  end)
  if type(U.G("TalentFrame_Update")) == "function" then
    U.PostHookGlobal("TalentFrame_Update", function()
      U.DeferOnce(tal.REFRESH_KEY, tal.Refresh)
    end)
  end
  U.RegisterEvent("CHARACTER_POINTS_CHANGED", tal.OnEvent)
  U.RegisterEvent("SPELLS_CHANGED", tal.OnEvent)
  U.RegisterEvent("PLAYER_LEVEL_UP", tal.OnEvent)

  tal.built = true
  tal.Refresh()
  return true
end
