-- unrealUI :: modules/spellbookclassicglow.lua
--
-- The classic-wow Spellbook's "Not on action bars" mark (user request,
-- 2026-09-17). modules/spellbook.lua still decides which spell is marked and
-- hands the verdict here instead of painting its flat accent outline.
--
-- Regions on the native spell button, all additive and pulsing like the
-- modern-wow book's glow (modules/spellbookmodernwow.lua, book.GlowTick):
--   * the button highlight (border effect) and the dimmer indicator art over
--     the icon, sized to the button;
--   * the Spellbook-Parts streak behind the name and rank. Only that cell of
--     the atlas is used; its burst and slot-frame cells are not drawn.
--
-- The streak is on the button's BACKGROUND layer, so every native region of
-- the button (icon, name, rank) draws above it. Addon regions only, no frame,
-- so nothing here takes the mouse. Geometry is M.classicSpellBookBarGlow.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local glow = {
  THEME = "classic-wow",
  updateId = "classic.spellbook.barglow",
  lit = {},
  count = 0,
  running = false,
  pulseTime = 0,
  phase = 0,
}

function glow.Token()
  return M.classicSpellBookBarGlow
end

function glow.Now()
  local ok, value = pcall(U.G("GetTime"))
  if ok and type(value) == "number" then return value end
  return nil
end

function glow.BookShown()
  local book = U.G("SpellBookFrame")
  if not book or not book.IsShown then return false end
  local ok, shown = pcall(book.IsShown, book)
  return ok and shown and true or false
end

function glow.Stop()
  if not glow.running then return end
  glow.running = false
  glow.lastTick = nil
  U.UnregisterUpdate(glow.updateId)
end

-- `phase` is the eased 0..1 swing; each part maps it into its own range.
function glow.SetAlpha(mark, phase)
  local s = glow.Token().pulse
  local i, h
  for i = 1, table.getn(mark.highlights) do
    h = mark.pulses[i]
    pcall(mark.highlights[i].SetAlpha, mark.highlights[i],
          h.alphaMin + (h.alphaMax - h.alphaMin) * phase)
  end
  pcall(mark.streak.SetAlpha, mark.streak,
        s.alphaMin + (s.alphaMax - s.alphaMin) * phase)
end

function glow.SetShown(mark, shown)
  local method = shown and "Show" or "Hide"
  local i
  for i = 1, table.getn(mark.highlights) do
    pcall(mark.highlights[i][method], mark.highlights[i])
  end
  pcall(mark.streak[method], mark.streak)
end

-- Same breathe as book.GlowTick: alpha ping-pongs through U.EaseInOutCubic,
-- elapsed read from GetTime because OnUpdate passes no delta here
-- (knowledge.json / scripts.onupdate_elapsed_only_via_arg1).
function glow.Tick()
  if glow.count <= 0 or not glow.BookShown() then
    glow.Stop()
    return
  end

  local now = glow.Now()
  if not now then return end
  local elapsed = now - (glow.lastTick or now)
  glow.lastTick = now
  if elapsed < 0 then elapsed = 0 end
  if elapsed > 0.25 then elapsed = 0.25 end

  local cfg = glow.Token().pulse
  glow.pulseTime = math.mod(glow.pulseTime + elapsed, cfg.pulsePeriod)
  local progress = glow.pulseTime / cfg.pulsePeriod
  local swing = progress < 0.5 and progress * 2 or (1 - progress) * 2
  glow.phase = U.EaseInOutCubic(swing)

  local mark
  for mark in pairs(glow.lit) do glow.SetAlpha(mark, glow.phase) end
end

function glow.Texture(button, layer, path)
  local ok, texture = pcall(button.CreateTexture, button, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  pcall(texture.SetBlendMode, texture, "ADD")
  pcall(texture.Hide, texture)
  return texture
end

function glow.Build(button)
  if button.uuiClassicBarGlow then return button.uuiClassicBarGlow end
  if not button.CreateTexture then return nil end

  local t = glow.Token()
  -- Every icon texture, each copy with its own pulse range (stacked additive
  -- copies where one alone read too faint).
  local highlights, pulses = {}, {}
  local i, n
  for i = 1, table.getn(t.icon) do
    local entry = t.icon[i]
    for n = 1, entry.layers do
      local highlight = glow.Texture(button, "OVERLAY", entry.texture)
      if highlight then
        table.insert(highlights, highlight)
        table.insert(pulses, entry.pulse)
      end
    end
  end
  local streak = glow.Texture(button, "BACKGROUND", t.parts)
  if not highlights[1] or not streak then
    glow.SetShown({ highlights = highlights, streak = streak or {} }, false)
    return nil
  end

  local cell, atlas = t.streakCell, t.atlas
  pcall(streak.SetTexCoord, streak, cell.left / atlas, cell.right / atlas,
        cell.top / atlas, cell.bottom / atlas)

  local mark = { highlights = highlights, pulses = pulses, streak = streak }
  button.uuiClassicBarGlow = mark
  return mark
end

-- Sized from the button's live width on every call.
function glow.Place(button, mark)
  local t = glow.Token()
  local width, height = 0, 0
  local ok, value = pcall(button.GetWidth, button)
  if ok and tonumber(value) then width = value end
  ok, value = pcall(button.GetHeight, button)
  if ok and tonumber(value) then height = value end

  local s = t.streak

  pcall(function()
    local i, highlight
    for i = 1, table.getn(mark.highlights) do
      highlight = mark.highlights[i]
      highlight:ClearAllPoints()
      highlight:SetWidth(width + t.iconGrow)
      highlight:SetHeight(height + t.iconGrow)
      highlight:SetPoint("CENTER", button, "CENTER", 0, 0)
    end

    mark.streak:ClearAllPoints()
    mark.streak:SetWidth(s.width)
    mark.streak:SetHeight(s.height)
    mark.streak:SetPoint("LEFT", button, "RIGHT", s.x, s.y)
  end)
end

-- Returns true when this theme drew (or cleared) the mark, so the caller
-- leaves its flat outline clear; false when classic-wow is not active or the
-- mark could not be built, so the flat outline still shows the verdict.
function U.ClassicSpellBookBarGlow(button, wanted)
  if not button or U.GetActiveThemeStyle() ~= glow.THEME then return false end

  if not wanted then
    local mark = button.uuiClassicBarGlow
    if mark and glow.lit[mark] then
      glow.lit[mark] = nil
      glow.count = glow.count - 1
      glow.SetShown(mark, false)
    end
    return true
  end

  local mark = glow.Build(button)
  if not mark then return false end
  glow.Place(button, mark)

  if not glow.lit[mark] then
    glow.lit[mark] = true
    glow.count = glow.count + 1
    -- Joins the running phase so every lit spell breathes together.
    glow.SetAlpha(mark, glow.running and glow.phase or 0)
    glow.SetShown(mark, true)
  end

  if not glow.running then
    glow.running = true
    glow.lastTick = nil
    U.RegisterUpdate(glow.updateId, 0, glow.Tick)
  end
  return true
end
