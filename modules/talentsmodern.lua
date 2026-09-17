-- unrealUI :: modules/talentsmodern.lua
--
-- The Talent window's complete `modern` drawing path: the same interface the
-- modern-wow path draws -- all three talent trees side by side, addon-owned
-- talent buttons, prerequisite branches and arrow heads, a per-tree header with
-- its icon, name, role and spent-point count -- rendered in UnrealUI's own
-- visual language instead of DragonflightUI's.
--
-- modules/talents.lua chooses this path in its own BuildFrame, before any other
-- styling, when the active theme is `modern`.
--
-- What differs from modules/talentsmodernwow.lua is only the drawing:
--
--  * No imported art. Every surface is a flat tinted WHITE8X8 fill with one
--    1-unit outline (core/style.lua), every arrow head is an owned text glyph
--    the way UnrealUI's scroll and collapse controls draw theirs, and every
--    branch is a flat 2-unit line -- so corner, T and elbow pieces are simply
--    the halves two neighbouring cells each draw.
--  * The window is UnrealUI-sized (M.talents.design) rather than DF-main's, and
--    the tree header is a compact row closed off by an accent rule instead of a
--    parchment cell in the tree's own colour: the tree colour would be a second
--    colour family on a near-black surface (rules/unreal-ui-design.md), so the
--    header uses the shared accent and names the tree's role in text.
--  * Talent state stays semantic: a learnable talent's rank counts up in green,
--    a maxed one in accent, a locked one dim with a desaturated icon, and the
--    button outline follows the same three states.
--
-- Client data and the prerequisite/branch node walk are core/talentgrid.lua's,
-- shared with the modern-wow path; nothing here reads a modern-wow token.
--
-- Nothing here reads or retains a native child beyond named lookups at build
-- and refresh (rules/unreal-ui.md, native widget ownership).
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media
local TG = U.TalentGrid

local tm = {
  REFRESH_KEY = "talents.modern.refresh",
  built = false,
  frame = nil,
  frameName = nil,
  panel = nil,
  panels = {},
  title = nil,
  status = nil,
}

function tm.Token()
  return M.talents
end

function tm.Named(suffix)
  if not tm.frameName then return nil end
  return U.G(tm.frameName .. suffix)
end

function tm.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function tm.Level(object)
  if not object or not object.GetFrameLevel then return 1 end
  local ok, level = pcall(object.GetFrameLevel, object)
  return (ok and tonumber(level)) or 1
end

function tm.Hide(object)
  if object then pcall(object.Hide, object) end
end

function tm.Texture(parent, layer, path)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path or M.texture.plain)
  return texture
end

-- ---------------------------------------------------------------------------
-- Branches and arrows
--
-- The node walk marks which cells a prerequisite line runs through; this draws
-- those marks as flat lines. A cell holding a talent only needs the connector
-- in the gap beyond it, so `down` and `right` are drawn from every cell and the
-- matching `up` / `left` belong to the neighbour. An empty cell additionally
-- draws the half-segment from its own centre to each marked edge, which is what
-- makes corners, T-junctions and pass-throughs without any corner art.
-- ---------------------------------------------------------------------------
function tm.Pooled(state, arrow)
  local t = tm.Token()
  local pool = arrow and state.arrows or state.branches
  local index = arrow and state.arrowIndex or state.branchIndex
  if arrow then
    state.arrowIndex = index + 1
  else
    state.branchIndex = index + 1
  end

  local object = pool[index]
  if not object then
    if arrow then
      object = U.CreateLabel(state.arrowFrame, {
        size = t.branch.arrowSize,
        color = M.color.accent,
        inherits = "GameFontNormal",
      })
    else
      object = tm.Texture(state.branchFrame, "ARTWORK")
    end
    if not object then return nil end
    pool[index] = object
  end
  return object
end

function tm.Line(state, met, x, y, width, height)
  local texture = tm.Pooled(state, false)
  if not texture then return end
  local color = tm.Token().branchColor[met] or M.color.textDim
  pcall(function()
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    texture:SetWidth(width)
    texture:SetHeight(height)
    texture:SetVertexColor(M.Unpack(color))
    texture:Show()
  end)
end

function tm.Arrow(state, met, glyph, x, y)
  local label = tm.Pooled(state, true)
  if not label then return end
  local color = tm.Token().branchColor[met] or M.color.textDim
  pcall(function()
    label:ClearAllPoints()
    label:SetPoint("CENTER", state.frame, "TOPLEFT", x, y)
    label:SetText(glyph)
    label:SetTextColor(M.Unpack(color))
    label:Show()
  end)
end

function tm.DrawBranches(state)
  local t = tm.Token()
  local g = t.grid
  local size = g.button
  local gap = g.pitch - size
  local th = t.branch.thickness
  local reach = t.branch.arrowGap
  local half = th / 2
  local i, j

  for i = 1, g.rows do
    for j = 1, g.columns do
      local node = state.nodes[i][j]
      -- Cell origin, then the centre lines the connectors run along.
      local x = ((j - 1) * g.pitch) + g.left
      local y = -((i - 1) * g.pitch) - g.top
      local cx = x + size / 2
      local cy = y - size / 2

      if node.down ~= 0 then
        tm.Line(state, node.down, cx - half, y - size, th, gap)
      end
      if node.right ~= 0 then
        tm.Line(state, node.right, x + size, cy + half, gap, th)
      end

      if node.id then
        -- Arrow heads point into the button from the side the line arrives on.
        if node.topArrow ~= 0 then
          tm.Arrow(state, node.topArrow, "v", cx, y + reach)
        end
        if node.rightArrow ~= 0 then
          tm.Arrow(state, node.rightArrow, "<", x + size + reach, cy)
        end
        if node.leftArrow ~= 0 then
          tm.Arrow(state, node.leftArrow, ">", x - reach, cy)
        end
      else
        if node.up ~= 0 then
          tm.Line(state, node.up, cx - half, y, th, size / 2)
        end
        if node.down ~= 0 then
          tm.Line(state, node.down, cx - half, cy, th, size / 2)
        end
        if node.left ~= 0 then
          tm.Line(state, node.left, x, cy + half, size / 2, th)
        end
        if node.right ~= 0 then
          tm.Line(state, node.right, cx, cy + half, size / 2, th)
        end
      end
    end
  end

  for i = state.branchIndex, table.getn(state.branches) do
    tm.Hide(state.branches[i])
  end
  for i = state.arrowIndex, table.getn(state.arrows) do
    tm.Hide(state.arrows[i])
  end
end

function tm.ResetBranches(state)
  local g = tm.Token().grid
  local i
  TG.ResetNodes(state.nodes, g.rows, g.columns)
  for i = 1, table.getn(state.branches) do tm.Hide(state.branches[i]) end
  for i = 1, table.getn(state.arrows) do tm.Hide(state.arrows[i]) end
  state.branchIndex = 1
  state.arrowIndex = 1
end

-- ---------------------------------------------------------------------------
-- Talent buttons
-- ---------------------------------------------------------------------------
function tm.OnEnter(button, tab, index)
  U.SetBorderColor(button, M.Unpack(M.color.accent))
  -- The client's own talent tooltip, not an explanatory addon one.
  if not GameTooltip then return end
  pcall(GameTooltip.SetOwner, GameTooltip, button, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetTalent, GameTooltip, tab, index)
  pcall(GameTooltip.Show, GameTooltip)
end

function tm.OnLeave(button)
  U.SetBorderColor(button, M.Unpack(button.uuiStateBorder or M.color.border))
  if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

function tm.OnClick(tab, index)
  if type(LearnTalent) == "function" then
    pcall(LearnTalent, tab, index)
  end
  U.DeferOnce(tm.REFRESH_KEY, tm.Refresh)
end

function tm.BuildButton(state, index)
  local t = tm.Token()
  local g = t.grid

  local ok, button = pcall(CreateFrame, "Button", nil, state.frame)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, g.button)
  pcall(button.SetHeight, button, g.button)
  pcall(button.SetFrameLevel, button, tm.Level(state.frame) + 2)
  pcall(button.EnableMouse, button, true)
  U.CreateBackdrop(button, { background = t.buttonColor })
  button.uuiStateBorder = t.borderColor.normal

  -- The ability icon is content, inset by the outline rather than covering it.
  local icon = tm.Texture(button, "ARTWORK")
  if icon then
    pcall(function()
      icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
      icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
      icon:SetTexCoord(t.icon.crop[1], t.icon.crop[2], t.icon.crop[3], t.icon.crop[4])
    end)
  end

  -- Rank readout in its own flat box, one level above the button's outline.
  local box = U.CreatePanel(button, {
    width = t.rank.width,
    height = t.rank.height,
    background = t.rankColor,
  })
  pcall(box.SetFrameLevel, box, tm.Level(button) + 1)
  pcall(box.EnableMouse, box, false)
  pcall(box.SetPoint, box, "CENTER", button, "BOTTOMRIGHT", t.rank.x, t.rank.y)

  local rank = U.CreateLabel(box, {
    size = t.rank.size,
    color = t.rankTextColor.available,
    inherits = "GameFontNormalSmall",
    justify = "CENTER",
  })
  if rank then
    pcall(rank.SetPoint, rank, "CENTER", box, "CENTER", 0, 0)
  end

  local tab = state.id
  button:SetScript("OnClick", function() tm.OnClick(tab, index) end)
  button:SetScript("OnEnter", function() tm.OnEnter(button, tab, index) end)
  button:SetScript("OnLeave", function() tm.OnLeave(button) end)

  button.uuiIcon = icon
  button.uuiRankBox = box
  button.uuiRank = rank
  state.buttons[index] = button
  return button
end

function tm.PaintButton(button, rank, maxRank, learnable)
  local t = tm.Token()
  local icon, box, text = button.uuiIcon, button.uuiRankBox, button.uuiRank
  local border, rankColor

  if learnable then
    if icon then
      pcall(icon.SetDesaturated, icon, nil)
      pcall(icon.SetVertexColor, icon, 1, 1, 1)
    end
    if rank >= maxRank and maxRank > 0 then
      border, rankColor = t.borderColor.maxed, t.rankTextColor.maxed
    elseif rank > 0 then
      border, rankColor = t.borderColor.partial, t.rankTextColor.available
    else
      border, rankColor = t.borderColor.normal, t.rankTextColor.available
    end
    if box then pcall(box.Show, box) end
  else
    if icon then
      pcall(icon.SetDesaturated, icon, 1)
      pcall(icon.SetVertexColor, icon, t.disabledIcon[1], t.disabledIcon[2],
            t.disabledIcon[3])
    end
    border, rankColor = t.borderColor.disabled, t.rankTextColor.disabled
    -- An untouched, locked talent says nothing useful with a "0/5" badge.
    if box then
      if rank > 0 then pcall(box.Show, box) else tm.Hide(box) end
    end
  end

  button.uuiStateBorder = border
  U.SetBorderColor(button, M.Unpack(border))
  if text then
    pcall(text.SetTextColor, text, M.Unpack(rankColor))
    pcall(text.SetText, text, rank .. "/" .. maxRank)
  end
end

-- ---------------------------------------------------------------------------
-- Tree panels
-- ---------------------------------------------------------------------------
function tm.BuildPanel(host, index)
  local t = tm.Token()
  local h = t.header

  local panel = U.CreatePanel(host, {
    width = t.panel.width,
    height = t.panel.height,
    background = t.panelColor,
  })
  pcall(panel.SetFrameLevel, panel, tm.Level(host) + 1)
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

  -- Header: the tree's own icon in a flat slot, its name and role beside it,
  -- and the spent-point count at the far end of the row.
  local slot = U.CreatePanel(panel, {
    width = h.iconSize,
    height = h.iconSize,
    background = t.buttonColor,
  })
  pcall(slot.SetFrameLevel, slot, tm.Level(panel) + 1)
  pcall(slot.EnableMouse, slot, false)
  pcall(slot.SetPoint, slot, "TOPLEFT", panel, "TOPLEFT", h.inset, -h.iconY)

  state.icon = tm.Texture(slot, "ARTWORK")
  if state.icon then
    pcall(function()
      state.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
      state.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
      state.icon:SetTexCoord(t.icon.crop[1], t.icon.crop[2],
                             t.icon.crop[3], t.icon.crop[4])
    end)
  end

  local textX = h.inset + h.iconSize + h.nameX
  state.name = U.CreateLabel(panel, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "LEFT",
    width = t.panel.width - textX - h.inset - 24,
  })
  if state.name then
    pcall(state.name.SetPoint, state.name, "TOPLEFT", panel, "TOPLEFT",
          textX, -h.nameY)
  end

  state.role = U.CreateLabel(panel, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = t.panel.width - textX - h.inset - 24,
  })
  if state.role then
    pcall(state.role.SetPoint, state.role, "TOPLEFT", panel, "TOPLEFT",
          textX, -h.roleY)
  end

  state.points = U.CreateLabel(panel, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "RIGHT",
  })
  if state.points then
    pcall(state.points.SetPoint, state.points, "TOPRIGHT", panel, "TOPRIGHT",
          -h.inset, -h.pointsY)
  end

  local rule = U.CreateRule(panel, { color = M.color.accentDim })
  if rule then
    pcall(function()
      rule:SetPoint("TOPLEFT", panel, "TOPLEFT", h.inset, -h.ruleY)
      rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -h.inset, -h.ruleY)
    end)
  end

  -- Branches under the buttons, arrow heads above them; neither takes a click.
  state.branchFrame = CreateFrame("Frame", nil, panel)
  state.branchFrame:SetAllPoints(panel)
  pcall(state.branchFrame.SetFrameLevel, state.branchFrame, tm.Level(panel) + 1)
  pcall(state.branchFrame.EnableMouse, state.branchFrame, false)

  state.arrowFrame = CreateFrame("Frame", nil, panel)
  state.arrowFrame:SetAllPoints(panel)
  pcall(state.arrowFrame.SetFrameLevel, state.arrowFrame, tm.Level(panel) + 3)
  pcall(state.arrowFrame.EnableMouse, state.arrowFrame, false)

  return state
end

function tm.RoleText(background)
  local roles = TG.TreeRoles(background)
  local parts, i = {}, nil
  for i = 1, table.getn(roles) do
    local key = "TALENTS_ROLE_" .. tostring(roles[i])
    local text = U.L(key)
    if text and text ~= key then table.insert(parts, text) end
  end
  if table.getn(parts) == 0 then return "" end
  -- Two roles read in the order the data lists them (Feral: damage, tank).
  return table.concat(parts, " / ")
end

function tm.RefreshPanel(state, unspent)
  local t = tm.Token()
  local g = t.grid
  local id = state.id
  local name, icon, spent, background = TG.TabInfo(id)
  if not name then
    tm.Hide(state.frame)
    return
  end
  pcall(state.frame.Show, state.frame)

  if state.name then pcall(state.name.SetText, state.name, name) end
  if state.icon then pcall(state.icon.SetTexture, state.icon, icon) end
  if state.role then pcall(state.role.SetText, state.role, tm.RoleText(background)) end
  if state.points then pcall(state.points.SetText, state.points, tostring(spent)) end

  tm.ResetBranches(state)

  local count = TG.NumTalents(id)
  local i
  for i = 1, count do
    local button = state.buttons[i] or tm.BuildButton(state, i)
    local tName, tIcon, tier, column, rank, maxRank, meets = TG.TalentInfo(id, i)
    if button and tName and state.nodes[tier] and state.nodes[tier][column] then
      state.nodes[tier][column].id = i

      pcall(function()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", state.frame, "TOPLEFT",
                        ((column - 1) * g.pitch) + g.left,
                        -((tier - 1) * g.pitch) - g.top)
      end)

      local forceDesaturated = (unspent <= 0 and rank == 0) and 1 or nil
      local tierUnlocked = ((tier - 1) * M.talentTree.pointsPerTier <= spent) and 1 or nil
      if button.uuiIcon then pcall(button.uuiIcon.SetTexture, button.uuiIcon, tIcon) end

      local prereqsSet = TG.SetPrereqs(state.nodes, tier, column, forceDesaturated,
                                       tierUnlocked, id, i)
      tm.PaintButton(button, rank, maxRank, prereqsSet and meets)
      pcall(button.Show, button)
    elseif button then
      tm.Hide(button)
    end
  end
  for i = count + 1, table.getn(state.buttons) do
    tm.Hide(state.buttons[i])
  end

  tm.DrawBranches(state)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- Unspent points, else the next level that grants one. This client has no
-- GetNextTalentLevel; the first point comes at level 10 and one more at every
-- level up to the cap (M.talentTree).
function tm.RefreshStatus(unspent)
  local label = tm.status
  if not label then return end
  local rules = M.talentTree
  local level = TG.PlayerLevel()
  local text
  if unspent > 0 then
    text = string.format(U.L("TALENTS_UNSPENT_POINTS"), unspent)
  elseif level < rules.firstTalentLevel then
    text = string.format(U.L("TALENTS_NEXT_LEVEL"), rules.firstTalentLevel)
  elseif level < rules.maxLevel then
    text = string.format(U.L("TALENTS_NEXT_LEVEL"), level + 1)
  end
  if text then
    pcall(label.SetText, label, text)
    pcall(label.Show, label)
  else
    tm.Hide(label)
  end
end

-- The native single-tree layout the three panels replace, plus the window's own
-- title region: it draws beneath the addon panel, so this path owns the title.
-- Re-hidden on every refresh because the client's own update may show it again.
function tm.HideNative()
  tm.Hide(tm.Named("ScrollFrame"))
  tm.Hide(tm.Named("SpentPoints"))
  tm.Hide(tm.Named("TalentPointsText"))
  -- The "Talent Points:" caption beside that value. Name from the stock 1.12
  -- TalentFrame layout, not runtime-verified here; a missing global is nil and
  -- simply skipped.
  tm.Hide(tm.Named("TalentPoints"))
  tm.Hide(tm.Named("CancelButton"))
  tm.Hide(tm.Named("TitleText"))
  local i
  for i = 1, 5 do tm.Hide(tm.Named("Tab" .. i)) end
end

function tm.Refresh()
  if not tm.built or not tm.Shown(tm.frame) then return end
  tm.HideNative()
  if tm.panel then pcall(tm.panel.Show, tm.panel) end
  local unspent = TG.UnspentPoints()
  local i
  for i = 1, table.getn(tm.panels) do
    local ok, err = pcall(tm.RefreshPanel, tm.panels[i], unspent)
    if not ok then U.Error("talents modern panel " .. i .. ": " .. tostring(err)) end
  end
  tm.RefreshStatus(unspent)
end

function tm.OnEvent()
  if tm.Shown(tm.frame) then U.DeferOnce(tm.REFRESH_KEY, tm.Refresh) end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
function U.ModernTalentsWanted()
  return U.GetActiveThemeStyle() == "modern"
end

-- Builds once. Called from modules/talents.lua under pcall, only after
-- U.ModernTalentsWanted.
function U.BuildModernTalents(frame)
  if tm.built then return true end
  if not frame then error("TalentFrame is unavailable") end

  local nameOk, name = pcall(frame.GetName, frame)
  if not nameOk or type(name) ~= "string" or name == "" then
    error("TalentFrame has no name")
  end
  tm.frame = frame
  tm.frameName = name

  local t = tm.Token()
  local inset = t.inset

  -- Strip before any addon region exists on this frame (rules/unreal-ui.md,
  -- region walks never match by identity). Every addon region below lives on
  -- an addon-owned child.
  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  pcall(frame.SetWidth, frame, t.design.width)
  pcall(frame.SetHeight, frame, t.design.height)
  pcall(frame.SetHitRectInsets, frame, 0, 0, 0, 0)

  local panel = U.CreatePanel(frame, { name = "UnrealUITalentModernPanel" })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  pcall(panel.EnableMouse, panel, false)
  local level = tm.Level(frame)
  pcall(panel.SetFrameLevel, panel, level)
  tm.panel = panel

  tm.HideNative()

  tm.title = U.CreateLabel(panel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "CENTER",
  })
  if tm.title then
    pcall(function()
      tm.title:SetPoint("TOP", panel, "TOP", 0, -t.title.y)
      tm.title:SetText(U.L("TALENTS_TITLE"))
    end)
  end

  tm.status = U.CreateLabel(panel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "CENTER",
  })
  if tm.status then
    pcall(tm.status.SetPoint, tm.status, "TOP", panel, "TOP", 0, -t.status.y)
  end

  local close = tm.Named("CloseButton")
  U.StyleStockCloseButton(close, panel, t.close.x, t.close.y)

  local p = t.panel
  local i
  for i = 1, t.trees do
    local state = tm.BuildPanel(panel, i)
    if i == 1 then
      state.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", inset.left, -inset.top)
    else
      state.frame:SetPoint("TOPLEFT", tm.panels[i - 1].frame, "TOPRIGHT", p.gap, 0)
    end
    tm.panels[i] = state
  end

  local controls = {}
  if close then table.insert(controls, close) end
  U.MakeWindowDraggable("talents", frame, {
    headerHeight = inset.top,
    headerInset = t.dragInset,
    interactiveFrames = controls,
  })

  U.PostHookScript(frame, "OnShow", tm.Refresh)
  U.PostHookScript(frame, "OnHide", function()
    if tm.panel then pcall(tm.panel.Hide, tm.panel) end
  end)
  if type(U.G("TalentFrame_Update")) == "function" then
    U.PostHookGlobal("TalentFrame_Update", function()
      U.DeferOnce(tm.REFRESH_KEY, tm.Refresh)
    end)
  end
  U.RegisterEvent("CHARACTER_POINTS_CHANGED", tm.OnEvent)
  U.RegisterEvent("SPELLS_CHANGED", tm.OnEvent)
  U.RegisterEvent("PLAYER_LEVEL_UP", tm.OnEvent)

  tm.built = true
  if tm.Shown(frame) then tm.Refresh() else pcall(panel.Hide, panel) end
  return true
end
