-- unrealUI :: modules/crafttracker.lua
--
-- Tracked profession recipes on the HUD (user request, 2026-09-16): each
-- recipe ticked "Track this recipe" in the profession window lists its
-- reagents with the count carried against the count one craft needs, laid out
-- like the native quest tracker. The block is one Move UI mover, and can also
-- be dragged directly with the left mouse button outside Move UI (user
-- request, 2026-09-17); both paths store the one position under MOVER_ID.
--
-- The trade-skill APIs only answer while a profession window is open, so each
-- recipe's reagent names and needs are captured when it is tracked and kept in
-- the module's settings; the carried count is read from the bags. Settings
-- allow one level of nesting of safe scalars (core/config.lua), so recipes are
-- a list of names and the reagents a flat table keyed "recipe::index" and
-- "recipe::index::need". No icon path is stored: every icon path contains a
-- backslash, which the config layer refuses
-- (config.savedvariables_backslash_corruption).
--
-- Bag reads go through core/compat.lua's container wrappers, the same reads
-- the bag window and sort engine use. BAG_UPDATE is only a refresh trigger.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media
local CT = U.RegisterModule("crafttracker")

local ct = {
  MOVER_ID = "crafttracker.frame",
  SEP = "::",
  MAX_RECIPES = 10,
  REFRESH_KEY = "crafttracker.refresh",
  lines = {},
  headers = {},
}

function ct.Config()
  return U.ModuleConfig("crafttracker", {
    recipes = {}, reagents = {}, professions = {}, kinds = {},
  })
end

function ct.Token()
  return ct.token or M.craftTracker
end

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

function ct.IndexOf(recipe)
  local recipes = ct.Config().recipes
  local i
  for i = 1, table.getn(recipes) do
    if recipes[i] == recipe then return i end
  end
  return nil
end

function ct.ClearReagents(recipe)
  local reagents = ct.Config().reagents
  local i = 1
  while reagents[recipe .. ct.SEP .. i] ~= nil do
    reagents[recipe .. ct.SEP .. i] = nil
    reagents[recipe .. ct.SEP .. i .. ct.SEP .. "need"] = nil
    i = i + 1
  end
end

function ct.Reagents(recipe)
  local reagents = ct.Config().reagents
  local list = {}
  local i = 1
  while type(reagents[recipe .. ct.SEP .. i]) == "string" do
    table.insert(list, {
      name = reagents[recipe .. ct.SEP .. i],
      need = tonumber(reagents[recipe .. ct.SEP .. i .. ct.SEP .. "need"]) or 1,
    })
    i = i + 1
  end
  return list
end

function U.CraftTrackerIsTracked(recipe)
  if type(recipe) ~= "string" then return false end
  return ct.IndexOf(recipe) ~= nil
end

-- `reagents` is a list of { name, need }; nil stops tracking the recipe.
-- Returns whether the recipe is tracked afterwards.
function U.CraftTrackerSetTracked(recipe, reagents, profession, kind)
  if type(recipe) ~= "string" or recipe == "" then return false end
  local config = ct.Config()
  local index = ct.IndexOf(recipe)

  if not reagents then
    if index then
      table.remove(config.recipes, index)
      ct.ClearReagents(recipe)
      config.professions[recipe] = nil
      config.kinds[recipe] = nil
    end
  else
    if not index then
      if table.getn(config.recipes) >= ct.MAX_RECIPES then
        U.Print(U.L("CRAFT_TRACKER_FULL", ct.MAX_RECIPES))
        return false
      end
      table.insert(config.recipes, recipe)
    end
    ct.ClearReagents(recipe)
    local i
    for i = 1, table.getn(reagents) do
      local r = reagents[i]
      config.reagents[recipe .. ct.SEP .. i] = r.name
      config.reagents[recipe .. ct.SEP .. i .. ct.SEP .. "need"] = tonumber(r.need) or 1
    end
    if type(profession) == "string" and profession ~= "" then
      config.professions[recipe] = profession
    end
    if kind == "trade" or kind == "craft" then config.kinds[recipe] = kind end
  end

  ct.Queue()
  return ct.IndexOf(recipe) ~= nil
end

function U.CraftTrackerRememberSource(recipe, profession, kind)
  if not ct.IndexOf(recipe) then return end
  local config = ct.Config()
  if type(profession) == "string" and profession ~= "" then
    config.professions[recipe] = profession
  end
  if kind == "trade" or kind == "craft" then config.kinds[recipe] = kind end
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

-- Carried count per item name across the backpack and the four bags.
function ct.BagCounts()
  local counts = {}
  local bag
  for bag = 0, 4 do
    local slots = U.ContainerSlotCount(bag)
    local slot
    for slot = 1, slots do
      local link = U.ContainerSlotLink(bag, slot)
      if link then
        local _, _, name = string.find(link, "%[(.-)%]")
        if name then
          local _, count = U.ContainerSlotInfo(bag, slot)
          counts[name] = (counts[name] or 0) + (tonumber(count) or 1)
        end
      end
    end
  end
  return counts
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

function ct.Line(i)
  local line = ct.lines[i]
  if line then return line end
  line = U.CreateLabel(ct.content, {
    size = M.fontSize.small,
    inherits = "GameFontHighlightSmall",
    justify = "LEFT",
    width = ct.Token().width,
  })
  ct.lines[i] = line
  return line
end

function ct.Header(i)
  local button = ct.headers[i]
  if button then return button end
  button = CreateFrame("Button", nil, ct.frame)
  button:RegisterForClicks("LeftButtonUp")
  local levelOk, level = pcall(ct.handle.GetFrameLevel, ct.handle)
  if levelOk and tonumber(level) then
    pcall(button.SetFrameLevel, button, level + 1)
  end
  button:SetScript("OnEnter", function()
    if button.line then
      pcall(button.line.SetTextColor, button.line,
            M.Unpack(ct.Token().headerHoverColor))
    end
  end)
  button:SetScript("OnLeave", function()
    if button.line then
      pcall(button.line.SetTextColor, button.line,
            M.Unpack(ct.Token().headerColor))
    end
  end)
  button:SetScript("OnMouseDown", function()
    if button.line then
      pcall(button.line.SetTextColor, button.line,
            M.Unpack(ct.Token().headerPressedColor))
    end
  end)
  button:SetScript("OnMouseUp", function()
    if button.line then
      pcall(button.line.SetTextColor, button.line,
            M.Unpack(ct.Token().headerHoverColor))
    end
  end)
  button:SetScript("OnClick", function()
    if button.recipe then ct.OpenRecipe(button.recipe) end
  end)
  ct.headers[i] = button
  return button
end

function ct.Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, a, b)
end

function ct.Truthy(value)
  return value ~= nil and value ~= false and value ~= 0
end

function ct.ActionForSpell(name)
  if type(name) ~= "string" or type(U.ActionSlotSpellName) ~= "function" then
    return nil
  end
  local slot
  for slot = 1, 72 do
    if U.ActionSlotSpellName(slot) == name then return slot end
  end
  return nil
end

function ct.ClearTemporaryAction(slot)
  local ok, occupied = ct.Call("HasAction", slot)
  if ok and ct.Truthy(occupied) then ct.Call("PickupAction", slot) end
  ct.Call("ClearCursor")
  ok, occupied = ct.Call("HasAction", slot)
  return ok and not ct.Truthy(occupied)
end

-- UseAction is the verified unprotected casting route on this client. When a
-- profession is not already on a bar, stage it only in an empty supported slot
-- and remove it immediately after use.
function ct.UseProfessionSpell(spell, book, name)
  local action = ct.ActionForSpell(name)
  if action then return ct.Call("UseAction", action) end

  local _, hasSpell = ct.Call("CursorHasSpell")
  local _, hasItem = ct.Call("CursorHasItem")
  if ct.Truthy(hasSpell) or ct.Truthy(hasItem) then return false end

  local target, slot
  for slot = 72, 1, -1 do
    local ok, occupied = ct.Call("HasAction", slot)
    if ok and not ct.Truthy(occupied) then target = slot break end
  end
  if not target then return false end

  if not ct.Call("PickupSpell", spell, book) then return false end
  local cursorOk, cursorSpell = ct.Call("CursorHasSpell")
  if not cursorOk or not ct.Truthy(cursorSpell) then
    ct.Call("ClearCursor")
    return false
  end
  ct.Call("PlaceAction", target)

  local placedOk, placed = ct.Call("HasAction", target)
  if not placedOk or not ct.Truthy(placed) or
     U.ActionSlotSpellName(target) ~= name then
    ct.ClearTemporaryAction(target)
    return false
  end

  local used = ct.Call("UseAction", target)
  if not ct.ClearTemporaryAction(target) then
    U.Error("crafttracker: temporary profession action was not cleared")
  end
  return used
end

function ct.OpenRecipe(recipe)
  if type(U.ModernWowProfessionsOpenRecipe) ~= "function" then return end
  local config = ct.Config()
  local profession = config.professions[recipe]
  local kind = config.kinds[recipe]
  if U.ModernWowProfessionsOpenRecipe(recipe, kind, profession) then return end
  if not profession or type(U.ModernWowProfessionSpell) ~= "function" then return end

  local spell, book, name = U.ModernWowProfessionSpell(profession)
  if not spell then return end
  if ct.UseProfessionSpell(spell, book, name) then
    U.DeferOnce("crafttracker.open", function()
      U.ModernWowProfessionsOpenRecipe(recipe, kind, profession)
    end)
  end
end

function ct.Queue()
  U.DeferOnce(ct.REFRESH_KEY, ct.Refresh)
end

function ct.Refresh()
  if not ct.frame then return end
  local t = ct.Token()
  local recipes = ct.Config().recipes
  local counts = table.getn(recipes) > 0 and ct.BagCounts() or {}

  local used, headerUsed, height, previous = 0, 0, 0, nil
  local function Add(text, size, color, indent, gap)
    used = used + 1
    local line = ct.Line(used)
    if not line then return end
    U.SetFont(line, size)
    pcall(line.SetTextColor, line, M.Unpack(color))
    pcall(line.SetText, line, text)
    pcall(function()
      line:ClearAllPoints()
      line:SetWidth(t.width - indent)
      if previous then
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent - previous.uuiIndent, -gap)
      else
        line:SetPoint("TOPLEFT", ct.content, "TOPLEFT", indent, 0)
      end
    end)
    line.uuiIndent = indent
    pcall(line.Show, line)

    local ok, h = pcall(line.GetHeight, line)
    h = ok and tonumber(h) or 0
    if h <= 0 then h = size + 2 end
    line.uuiHeight = h
    if previous then height = height + gap end
    height = height + h
    previous = line
  end

  local i, j
  for i = 1, table.getn(recipes) do
    local recipe = recipes[i]
    Add(recipe, M.fontSize.normal, t.headerColor, 0, i > 1 and t.recipeGap or 0)
    headerUsed = headerUsed + 1
    local button = ct.Header(headerUsed)
    button.recipe = recipe
    button.line = previous
    pcall(function()
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, 0)
      button:SetWidth(t.width)
      button:SetHeight(previous.uuiHeight)
      button:Show()
    end)
    local reagents = ct.Reagents(recipe)
    for j = 1, table.getn(reagents) do
      local r = reagents[j]
      local have = counts[r.name] or 0
      Add(string.format("- %s: %d/%d", r.name, have, r.need), M.fontSize.small,
          have >= r.need and t.doneColor or t.pendingColor, t.indent, t.lineGap)
    end
  end

  for i = used + 1, table.getn(ct.lines) do
    pcall(ct.lines[i].Hide, ct.lines[i])
  end
  for i = headerUsed + 1, table.getn(ct.headers) do
    ct.headers[i].recipe = nil
    ct.headers[i].line = nil
    pcall(ct.headers[i].Hide, ct.headers[i])
  end
  pcall(ct.frame.SetHeight, ct.frame, math.max(t.minHeight, height))
  -- An empty tracker draws nothing, so it must not catch clicks either.
  if ct.handle then
    pcall(ct.handle.EnableMouse, ct.handle, used > 0)
  end
end

-- ---------------------------------------------------------------------------
-- Direct drag
--
-- core/windowdrag.lua's verified recipe (knowledge.json /
-- frames.movable_drag_requires_button_handle): a Button parented to the frame
-- it moves, raised by frame level, SetMovable right before each drag and a
-- throwaway StartMoving/StopMovingOrSizing pair before the real one. Move UI
-- keeps its own handle, so a direct drag is refused while it is unlocked.
-- ---------------------------------------------------------------------------

function ct.IsLeftButton(a, b)
  local button
  if type(a) == "string" then
    button = a
  elseif type(b) == "string" then
    button = b
  else
    button = U.G("arg1")
  end
  return button == nil or button == "LeftButton"
end

function ct.StartDrag()
  local frame = ct.frame
  if ct.dragging or not frame or U.IsUnlocked() then return end
  if not pcall(frame.SetMovable, frame, true) then
    U.Error("crafttracker: SetMovable failed")
    return
  end
  if pcall(frame.StartMoving, frame) then
    pcall(frame.StopMovingOrSizing, frame)
  end
  if not pcall(frame.StartMoving, frame) then
    U.Error("crafttracker: StartMoving failed")
    return
  end
  ct.dragging = true
end

-- Stores the drop as a TOPLEFT point so the list keeps growing downwards
-- whatever anchor StopMovingOrSizing left behind. Measured from the frame's
-- edges: GetPoint's Y comes back in SetPoint's own sign on this client, and
-- U.GetFramePoint negates it (U.GetFramePlacement, core/screenguard.lua).
function ct.SaveDrop()
  local frame = ct.frame
  local leftOk, left = pcall(frame.GetLeft, frame)
  local bottomOk, bottom = pcall(frame.GetBottom, frame)
  local hOk, height = pcall(frame.GetHeight, frame)
  left = leftOk and tonumber(left)
  bottom = bottomOk and tonumber(bottom)
  height = hOk and tonumber(height)
  if not left or not bottom or not height then
    U.Debug("crafttracker: no readable position after drag")
    return
  end

  local position = { point = "TOPLEFT", relativePoint = "TOPLEFT",
                     x = left, y = bottom + height - U.UIHeight() }
  U.ApplyFramePoint(frame, position)
  U.SavePosition(ct.MOVER_ID, position.point, position.relativePoint,
                 position.x, position.y)
end

function ct.StopDrag()
  if not ct.dragging then return end
  ct.dragging = false
  pcall(ct.frame.StopMovingOrSizing, ct.frame)
  ct.SaveDrop()
  U.CheckOnScreen(ct.frame)
end

function ct.BuildHandle(frame)
  local handle = CreateFrame("Button", "UnrealUICraftTrackerDrag", frame)
  handle:SetAllPoints(frame)
  handle:RegisterForDrag("LeftButton")
  local levelOk, level = pcall(frame.GetFrameLevel, frame)
  if levelOk and tonumber(level) then
    pcall(handle.SetFrameLevel, handle, level + ct.Token().handleLevel)
  end
  handle:SetScript("OnMouseDown", function(a, b)
    if ct.IsLeftButton(a, b) then ct.StartDrag() end
  end)
  handle:SetScript("OnMouseUp", function(a, b)
    if ct.IsLeftButton(a, b) then ct.StopDrag() end
  end)
  -- Fallback route; both handlers are safe to receive twice.
  handle:SetScript("OnDragStart", function() ct.StartDrag() end)
  handle:SetScript("OnDragStop", function() ct.StopDrag() end)
  pcall(handle.EnableMouse, handle, false)
  ct.handle = handle
end

function CT:OnEnable()
  -- Theme changes require a reload, so select one complete drawing token once
  -- rather than branching per reagent on every bag refresh.
  ct.token = U.GetActiveThemeStyle() == "modern-wow" and
             M.modernWow.craftTracker or M.craftTracker
  local t = ct.Token()
  -- Always shown and empty of art: an untracked HUD draws nothing, but the
  -- mover handle still needs a frame to sit on in Move UI mode.
  local frame = CreateFrame("Frame", "UnrealUICraftTracker", UIParent)
  frame:SetWidth(t.width)
  frame:SetHeight(t.minHeight)
  -- Persistent HUD, below open windows, as the quest tracker is.
  pcall(frame.SetFrameStrata, frame, "LOW")
  pcall(frame.EnableMouse, frame, false)
  frame:Show()
  ct.frame = frame

  local content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints(frame)
  pcall(content.EnableMouse, content, false)
  ct.content = content
  ct.BuildHandle(frame)

  U.RegisterMover(ct.MOVER_ID, frame, {
    label = U.L("MOVER_LABEL_CRAFT_TRACKER"),
    default = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -240, y = -320 },
  })
  -- The list grows downwards as reagents are tracked. Clamp only: a HUD is
  -- never rescaled, and Move UI owns it while unlocked.
  U.GuardOnScreen(frame, {
    id = ct.MOVER_ID,
    fit = false,
    suspended = function() return ct.dragging or U.IsUnlocked() end,
  })

  U.RegisterEvent("BAG_UPDATE", ct.Queue)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", ct.Queue)
  ct.Refresh()
end
