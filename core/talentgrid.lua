-- unrealUI :: core/talentgrid.lua
--
-- The talent window's client data and prerequisite-branch layout, shared by
-- every theme that rebuilds the three talent trees itself: the modern path in
-- modules/talentsmodern.lua and the modern-wow path in
-- modules/talentsmodernwow.lua.
--
-- Nothing here draws. It answers what the client says about a tree and, for a
-- tree's prerequisites, which grid cells a connecting line passes through --
-- both of which are identical whatever the line is finally drawn with. Each
-- theme keeps its own complete drawing path over these results
-- (rules/unreal-ui-design.md, branching rule).
--
-- The node layout is DF-main's TALENT_BRANCH_ARRAY walk (WORKING_SOURCE,
-- Mixin/Talents.mixin.lua), unchanged except that a layout this client cannot
-- draw simply produces no line instead of DF-main's message() calls.
--
-- Client evidence for the data calls:
--
--  * GetTalentTabInfo returns 4 values, background 4th (knowledge.json /
--    talent.tab_info_background_textures, BEHAVIOR_VERIFIED).
--  * GetTalentInfo(tab, i) -> name, icon, tier, column, rank, maxRank, nil,
--    meetsPrereq; GetTalentPrereqs returns up to three (tier, column,
--    meetsRank) triples (documentation.json,
--    DOCUMENTED_NOT_RUNTIME_VERIFIED).
--
-- Every call stays optional and nil-safe, so a client missing one of them
-- draws an empty tree rather than erroring.

local U = UnrealUI
local M = U.media

U.TalentGrid = {}
local TG = U.TalentGrid

-- ---------------------------------------------------------------------------
-- Client data
-- ---------------------------------------------------------------------------
function TG.TabInfo(tab)
  if type(GetTalentTabInfo) ~= "function" then return nil end
  local ok, name, icon, spent, background = pcall(GetTalentTabInfo, tab)
  if not ok then return nil end
  return name, icon, tonumber(spent) or 0, background
end

function TG.NumTalents(tab)
  if type(GetNumTalents) ~= "function" then return 0 end
  local ok, count = pcall(GetNumTalents, tab)
  return (ok and tonumber(count)) or 0
end

function TG.TalentInfo(tab, index)
  if type(GetTalentInfo) ~= "function" then return nil end
  local ok, name, icon, tier, column, rank, maxRank, _, meets =
    pcall(GetTalentInfo, tab, index)
  if not ok or not name then return nil end
  return name, icon, tonumber(tier) or 1, tonumber(column) or 1,
         tonumber(rank) or 0, tonumber(maxRank) or 0, meets
end

function TG.UnspentPoints()
  if type(UnitCharacterPoints) ~= "function" then return 0 end
  local ok, points = pcall(UnitCharacterPoints, "player")
  return (ok and tonumber(points)) or 0
end

function TG.PlayerLevel()
  local ok, level = pcall(UnitLevel, "player")
  return (ok and tonumber(level)) or 0
end

-- ---------------------------------------------------------------------------
-- Tree lookup
--
-- Looks a tree up in a table keyed by its background file name (M.talentTree's
-- `color` and `roles`). The name is reduced to its bare, lower-cased form
-- ("Interface\TalentFrame\PaladinCombat-TopLeft.blp" -> "paladincombat") and
-- compared against a lower-cased copy of the table, so a path, suffix or case
-- difference cannot miss a class.
-- ---------------------------------------------------------------------------
local lowerKeys = {}

function TG.Lookup(source, background)
  if type(source) ~= "table" or type(background) ~= "string" or
     background == "" then
    return nil
  end
  local keys = lowerKeys[source]
  if not keys then
    keys = {}
    local key, value
    for key, value in pairs(source) do keys[string.lower(key)] = value end
    lowerKeys[source] = keys
  end
  local bare = string.gsub(background, "^.*[/\\]", "")
  bare = string.gsub(bare, "%.%a+$", "")
  bare = string.gsub(bare, "%-%a+$", "")
  return source[background] or keys[string.lower(bare)]
end

-- A tree's colour; an unmatched name falls back to the by-index default.
function TG.TreeColor(background, index)
  local t = M.talentTree
  return TG.Lookup(t.color, background) or
         t.defaultColor[index] or t.defaultColor[1]
end

-- A tree's roles, in list order (with two roles the second is the primary one).
function TG.TreeRoles(background)
  return TG.Lookup(M.talentTree.roles, background) or {}
end

-- ---------------------------------------------------------------------------
-- Branch nodes
--
-- One node per grid cell. `id` is the talent occupying it, if any; `up`,
-- `down`, `left` and `right` say whether a line leaves the cell in that
-- direction and the three arrow fields where a prerequisite arrow head lands.
-- All five carry 1 (requirements met), -1 (not met) or 0 (no line).
-- ---------------------------------------------------------------------------
function TG.NewNodes(rows, columns)
  local nodes = {}
  local i, j
  for i = 1, rows do
    nodes[i] = {}
    for j = 1, columns do
      nodes[i][j] = { up = 0, down = 0, left = 0, right = 0,
                      leftArrow = 0, rightArrow = 0, topArrow = 0 }
    end
  end
  return nodes
end

function TG.ResetNodes(nodes, rows, columns)
  local i, j
  for i = 1, rows do
    if nodes[i] then
      for j = 1, columns do
        local node = nodes[i][j]
        if node then
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
    end
  end
end

-- DF-main DrawLines: marks the cells a line from the prerequisite at
-- (tier, column) to the talent at (buttonTier, buttonColumn) runs through.
function TG.DrawLines(nodes, buttonTier, buttonColumn, tier, column, requirementsMet)
  local met = requirementsMet and 1 or -1
  local i

  if not nodes or not nodes[tier] or not nodes[buttonTier] then return end

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
function TG.SetPrereqs(nodes, tier, column, forceDesaturated, tierUnlocked, tab, index)
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
      TG.DrawLines(nodes, tier, column, pTier, pColumn, requirementsMet)
    end
  end
  return requirementsMet
end
