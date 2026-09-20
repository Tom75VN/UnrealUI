-- unrealUI :: modules/talentadvisor.lua
--
-- Optional talent build drawer, shared by both talent drawing paths. The
-- catalog stores exact rank digits; live client data remains authoritative for
-- tree identity, current ranks, prerequisites, rank caps and whether the next
-- point can be learned.
--
-- The drawer has one layout and two drawing paths: Modern WoW's themed
-- housing, rules, faces and row highlights, and Modern's flat panel, 1-unit
-- rules and outlined surfaces. Both read the same geometry tokens from
-- M.talentAdvisor.styles (core/media.lua), where the flat style is marked
-- `drawer.flat`; advisor.ThemedDrawer is the one check that separates the two
-- paths. The owning window names its style once through U.TalentAdvisorStyle
-- before it builds anything, so nothing below branches on the active theme.
-- Two of the three windows name the themed path: the Modern WoW one, and the
-- classic-wow one by user request (2026-09-21), which draws the same drawer
-- and arrow beside the Modern WoW headers it already borrows. Only Modern's
-- flat window asks for `drawer.flat`.
--
-- The three talent-button marks are not part of that split: both styles draw
-- the same ants, flipbook and pulsing rim (user request, 2026-09-21), so the
-- outline branch below is kept only for a style that asks for it.

local U = UnrealUI
local M = U.media

local advisor = {
  width = 238,
  height = 430,
  -- How far the toggle's centre sits outside the talent window's edge. The
  -- drawer then hangs off the toggle itself, flush with its outer edge and
  -- centred on it, so it clears the arrow at any drawer height without a
  -- clearance being measured (user requests, 2026-09-21).
  toggleEdge = 11,
  -- Negative: the drawer is pulled 3 units back toward the window off the
  -- toggle's outer edge (user request, 2026-09-21), mirrored on the left side
  -- like every other part of this placement.
  toggleGap = -3,
  slide = 0,
  -- The flat open/close control's size; the themed one takes its own from
  -- M.talentAdvisor.styles.
  toggleWidth = 22,
  toggleHeight = 42,
  -- Flat-style row pitch: the row is exactly the flat choice button's own
  -- height, so two listed builds are separated by strictly 3 units of drawer
  -- (user request, 2026-09-21). The themed drawer overrides both from
  -- M.talentAdvisor.styles.
  rowHeight = 23,
  rowGap = 3,
  built = false,
  open = false,
  rows = {},
  contextButtons = {},
  roleButtons = {},
  context = "LEVELING",
  role = nil,
  style = "modern-wow",
  buildId = nil,
  class = nil,
  panels = nil,
  nextButton = nil,
  softButtons = {},
  wrongButtons = {},
  pulseRunning = false,
  softPulseTime = 0,
  wrongPulseTime = 0,
  -- Playhead of the `next` flipbook: which of its two grids is running,
  -- which cell is up and how long that cell has been shown. nil phase means
  -- nothing is playing.
  flipPhase = nil,
  flipCell = 1,
  flipTime = 0,
  -- The ants run on their own clock, and every soft mark shares this one
  -- playhead: they are the same texture at the same rate, so one frame index
  -- keeps the whole build's marks marching in step.
  antsFrame = 1,
  antsTime = 0,
  pulseLastTick = nil,
  pulseUpdateId = "talentadvisor.pulse",
  getTime = U.G("GetTime"),
}

function advisor.Data()
  return U.TalentAdvisorBuilds
end

function advisor.Enabled()
  return M.talentAdvisor.released == true
end

-- The media set for the window that built the drawer. Falls back to the
-- Modern WoW set rather than erroring, so a caller that forgets to name its
-- style still draws something.
function advisor.Cfg()
  local styles = M.talentAdvisor.styles
  return styles[advisor.style] or styles["modern-wow"]
end

function advisor.Class()
  if advisor.class then return advisor.class end
  local ok, _, class = pcall(UnitClass, "player")
  if ok and class then advisor.class = class end
  return advisor.class
end

function advisor.Hide(object)
  if object then pcall(object.Hide, object) end
end

function advisor.Show(object)
  if object then pcall(object.Show, object) end
end

function advisor.SetText(label, text)
  if label then pcall(label.SetText, label, text or "") end
end

function advisor.Texture(parent, layer, path)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  return texture
end

-- Same shape as mw.Dimension in modules/modernwow.lua: a guarded numeric
-- read off a widget, 0 when the method is missing or throws.
function advisor.Number(object, method)
  if not object or not object[method] then return 0 end
  local ok, value = pcall(object[method], object)
  return (ok and tonumber(value)) or 0
end

function advisor.Now()
  if type(advisor.getTime) ~= "function" then return nil end
  local ok, value = pcall(advisor.getTime)
  if ok and type(value) == "number" then return value end
  return nil
end

function advisor.StopPulse()
  if not advisor.pulseRunning then return end
  advisor.pulseRunning = false
  advisor.pulseLastTick = nil
  advisor.wrongPulseTime = 0
  U.UnregisterUpdate(advisor.pulseUpdateId)
  -- One ticker drives both marks, so the flipbook stops here too. Forgetting
  -- the button it was on makes the next mark replay the burst rather than
  -- appearing mid-loop.
  advisor.flipPhase = nil
  advisor.flipCell = 1
  advisor.flipTime = 0
  advisor.antsFrame = 1
  advisor.antsTime = 0
  if advisor.nextEffect then advisor.nextEffect.uuiButton = nil end
  local cfg = advisor.Cfg().soft
  local i
  for i = 1, table.getn(advisor.softButtons) do
    local frame = advisor.softButtons[i].uuiAdvisorSoft
    if frame and frame.uuiGlow then
      pcall(frame.uuiGlow.SetAlpha, frame.uuiGlow, cfg.restAlpha)
    end
  end
  cfg = advisor.Cfg().wrong
  for i = 1, table.getn(advisor.wrongButtons) do
    local frame = advisor.wrongButtons[i].uuiAdvisorWrong
    if frame and frame.uuiGlow then
      pcall(frame.uuiGlow.SetAlpha, frame.uuiGlow, cfg.alpha)
    end
  end
end

function advisor.PulseTick()
  if not advisor.nextButton and table.getn(advisor.wrongButtons) == 0 then
    advisor.StopPulse()
    return
  end
  if advisor.frame and advisor.frame.IsShown then
    local shownOk, shown = pcall(advisor.frame.IsShown, advisor.frame)
    if shownOk and not shown then
      advisor.StopPulse()
      return
    end
  end
  local now = advisor.Now()
  if not now then return end
  local elapsed = now - (advisor.pulseLastTick or now)
  advisor.pulseLastTick = now
  if elapsed < 0 then elapsed = 0 end
  if elapsed > 0.25 then elapsed = 0.25 end

  advisor.FlipTick(elapsed)

  local softCfg = advisor.Cfg().soft
  -- Step the shared ants playhead first; the loop below carries the new cell
  -- to each mark along with its alpha, so the soft buttons are walked once.
  local antsStep = false
  if softCfg.ants then
    local antsInterval = tonumber(softCfg.antsInterval) or 0
    if antsInterval > 0 then
      local frames = M.modernWow.iconAlertAnts.frames
      advisor.antsTime = advisor.antsTime + elapsed
      while advisor.antsTime >= antsInterval do
        advisor.antsTime = advisor.antsTime - antsInterval
        advisor.antsFrame = advisor.antsFrame + 1
        if advisor.antsFrame > frames then advisor.antsFrame = 1 end
        antsStep = true
      end
    end
  end
  local softPeriod = tonumber(softCfg.pulsePeriod) or 2.5
  advisor.softPulseTime = math.mod(advisor.softPulseTime + elapsed,
                                   softPeriod)
  local softProgress = advisor.softPulseTime / softPeriod
  local softSwing = softProgress < 0.5 and softProgress * 2 or
                    (1 - softProgress) * 2
  if type(U.EaseInOutCubic) == "function" then
    softSwing = U.EaseInOutCubic(softSwing)
  end
  local softAlpha = softCfg.pulseMin +
                    (softCfg.pulseMax - softCfg.pulseMin) * softSwing
  local i
  for i = 1, table.getn(advisor.softButtons) do
    local soft = advisor.softButtons[i].uuiAdvisorSoft
    if soft and soft.uuiGlow then
      pcall(soft.uuiGlow.SetAlpha, soft.uuiGlow, softAlpha)
      if antsStep then advisor.AntsCell(soft.uuiGlow, advisor.antsFrame) end
    end
  end

  local wrongCfg = advisor.Cfg().wrong
  local wrongPeriod = tonumber(wrongCfg.pulsePeriod)
  if wrongPeriod and wrongPeriod > 0 then
    advisor.wrongPulseTime = math.mod(advisor.wrongPulseTime + elapsed,
                                     wrongPeriod)
    local wrongProgress = advisor.wrongPulseTime / wrongPeriod
    local wrongSwing = wrongProgress < 0.5 and wrongProgress * 2 or
                       (1 - wrongProgress) * 2
    if type(U.EaseInOutCubic) == "function" then
      wrongSwing = U.EaseInOutCubic(wrongSwing)
    end
    local wrongAlpha = wrongCfg.pulseMin +
                       (wrongCfg.pulseMax - wrongCfg.pulseMin) * wrongSwing
    for i = 1, table.getn(advisor.wrongButtons) do
      local wrong = advisor.wrongButtons[i].uuiAdvisorWrong
      if wrong and wrong.uuiGlow then
        pcall(wrong.uuiGlow.SetAlpha, wrong.uuiGlow, wrongAlpha)
      end
    end
  end
end

function advisor.StartPulse()
  if advisor.pulseRunning then return end
  advisor.pulseRunning = true
  advisor.softPulseTime = 0
  advisor.wrongPulseTime = 0
  advisor.pulseLastTick = advisor.Now()
  local softCfg = advisor.Cfg().soft
  local i
  for i = 1, table.getn(advisor.softButtons) do
    local soft = advisor.softButtons[i].uuiAdvisorSoft
    if soft and soft.uuiGlow then
      pcall(soft.uuiGlow.SetAlpha, soft.uuiGlow, softCfg.pulseMin)
    end
  end
  local wrongCfg = advisor.Cfg().wrong
  if wrongCfg.pulseMin then
    for i = 1, table.getn(advisor.wrongButtons) do
      local wrong = advisor.wrongButtons[i].uuiAdvisorWrong
      if wrong and wrong.uuiGlow then
        pcall(wrong.uuiGlow.SetAlpha, wrong.uuiGlow, wrongCfg.pulseMin)
      end
    end
  end
  U.RegisterUpdate(advisor.pulseUpdateId, softCfg.pulseInterval,
    advisor.PulseTick)
end

-- One cell of a flipbook grid, counting left to right then down. Both grids
-- are cropped to exactly `columns` x `rows` cells (see
-- tools/import_modern_wow_media.py, SHEET_CROPS), so a cell is a plain
-- fraction of the texture and there is no sheet padding to measure.
--
-- `crop` trims that fraction off each side of the cell, which is how the loop
-- grid is drawn thinner than its art: paired with the matching reduction in
-- ShowNextFlipbook it removes band from the ring's outer edge and leaves its
-- opening, and everything inside it, untouched.
function advisor.FlipCell(texture, index, cfg, crop)
  if not texture then return end
  local columns = cfg.columns
  local column = math.mod(index - 1, columns)
  local row = math.floor((index - 1) / columns)
  local u1, u2 = column / columns, (column + 1) / columns
  local v1, v2 = row / cfg.rows, (row + 1) / cfg.rows
  crop = tonumber(crop) or 0
  if crop > 0 then
    local dx, dy = (u2 - u1) * crop, (v2 - v1) * crop
    u1, u2, v1, v2 = u1 + dx, u2 - dx, v1 + dy, v2 - dy
  end
  pcall(texture.SetTexCoord, texture, u1, u2, v1, v2)
end

-- The ants are a flipbook too, but not one of those: their sheet keeps 22 of
-- 25 cells and leaves 16 pixels spare on each axis, so a cell is addressed by
-- Blizzard's own arithmetic (TextureUtil.AnimateTexCoords, row-major and
-- 1-based) rather than by a plain fraction of the texture.
function advisor.AntsCell(texture, frame)
  if not texture then return end
  local g = M.modernWow.iconAlertAnts
  local unit = g.cell / g.sheet
  local left = math.mod(frame - 1, g.columns) * unit
  local bottom = math.ceil(frame / g.columns) * unit
  pcall(texture.SetTexCoord, texture, left, left + unit, bottom - unit, bottom)
end

-- Blizzard plays this effect with a FlipBook animation, which this client has
-- no animation system for at all: query_compat.py has no record of FlipBook,
-- CreateAnimationGroup or SetAtlas. The two grids are stepped by hand off the
-- advisor's own ticker instead, which is the same thing
-- modules/modernwow.lua already does for the resting flipbook.
function advisor.BuildNextFlipbook(parent, cfg)
  local ok, holder = pcall(CreateFrame, "Frame", nil, parent)
  if not ok or not holder then return nil end
  pcall(holder.EnableMouse, holder, false)

  local loop = advisor.Texture(holder, "OVERLAY", cfg.loopTexture)
  local burst = advisor.Texture(holder, "OVERLAY", cfg.startTexture)
  if not loop or not burst then return nil end
  pcall(loop.SetPoint, loop, "CENTER", holder, "CENTER", 0, 0)
  pcall(burst.SetPoint, burst, "CENTER", holder, "CENTER", 0, 0)
  advisor.FlipCell(loop, 1, cfg, cfg.loopCrop)
  advisor.FlipCell(burst, 1, cfg)

  holder.uuiLoop = loop
  holder.uuiBurst = burst
  advisor.Hide(holder)
  advisor.nextEffect = holder
  return holder
end

function advisor.BuildNextEffect(parent)
  if advisor.nextEffect or not parent then return advisor.nextEffect end
  local cfg = advisor.Cfg().next

  if cfg.flipbook then return advisor.BuildNextFlipbook(parent, cfg) end

  -- The flat theme has no model effect to spend: the strongest cue it owns is
  -- the accent outline every focused UnrealUI control already uses, so the
  -- "spend it here" mark is that outline one step wider than the blue one.
  if cfg.outline then
    local frameOk, outline = pcall(CreateFrame, "Frame", nil, parent)
    if not frameOk or not outline then return nil end
    pcall(outline.EnableMouse, outline, false)
    U.CreateBorder(outline)
    U.SetBorderColor(outline, M.Unpack(cfg.color))
    advisor.Hide(outline)
    advisor.nextEffect = outline
    return outline
  end

  local ok, effect = pcall(CreateFrame, "Model", nil, parent)
  if not ok or not effect then return nil end
  pcall(effect.EnableMouse, effect, false)
  pcall(effect.SetModel, effect, cfg.model)
  pcall(effect.SetSequence, effect, 0)
  pcall(effect.SetSequenceTime, effect, 0, 0)
  advisor.Hide(effect)
  advisor.nextEffect = effect
  return effect
end

-- Sized off the button rather than anchored to it: the burst is drawn well
-- outside the talent icon (Blizzard's own template puts a 150-unit burst over
-- a 45-unit button), so both grids are centred and scaled instead.
function advisor.ShowNextFlipbook(effect, button, cfg)
  pcall(effect.SetParent, effect, button)
  pcall(effect.ClearAllPoints, effect)
  pcall(effect.SetPoint, effect, "CENTER", button, "CENTER", 0, 0)
  local level = advisor.Number(button, "GetFrameLevel")
  if level > 0 then
    pcall(effect.SetFrameLevel, effect, level + M.talentAdvisor.level.next)
  end

  local size = advisor.Number(button, "GetWidth")
  if size > 0 then
    -- The loop is drawn down by exactly what its cells were cropped by, so
    -- the art that survives keeps its own scale and its opening its size.
    local crop = tonumber(cfg.loopCrop) or 0
    local loopSize = size * cfg.loopScale * (1 - (crop * 2))
    local burstSize = size * cfg.startScale
    pcall(effect.SetWidth, effect, loopSize)
    pcall(effect.SetHeight, effect, loopSize)
    pcall(effect.uuiLoop.SetWidth, effect.uuiLoop, loopSize)
    pcall(effect.uuiLoop.SetHeight, effect.uuiLoop, loopSize)
    pcall(effect.uuiBurst.SetWidth, effect.uuiBurst, burstSize)
    pcall(effect.uuiBurst.SetHeight, effect.uuiBurst, burstSize)
  end

  -- A refresh that keeps pointing at the same talent must not restart the
  -- burst, or the mark would flash on every talent click elsewhere in the
  -- tree. Only a move to another button replays it.
  if effect.uuiButton ~= button then
    effect.uuiButton = button
    advisor.flipPhase = "start"
    advisor.flipCell = 1
    advisor.flipTime = 0
    advisor.FlipCell(effect.uuiBurst, 1, cfg)
    advisor.FlipCell(effect.uuiLoop, 1, cfg, cfg.loopCrop)
    advisor.Show(effect.uuiBurst)
    advisor.Hide(effect.uuiLoop)
  end

  advisor.Show(effect)
end

-- Steps whichever grid is running. The burst plays once and hands over to the
-- loop, which is what ActionButtonSpellAlertTemplate's ProcStartAnim does in
-- its OnFinished.
function advisor.FlipTick(elapsed)
  local effect = advisor.nextEffect
  local cfg = advisor.Cfg().next
  if not effect or not cfg.flipbook or not advisor.flipPhase then return end

  local burst = advisor.flipPhase == "start"
  local duration = burst and cfg.startDuration or cfg.loopDuration
  local interval = duration / cfg.frames
  if interval <= 0 then return end

  advisor.flipTime = advisor.flipTime + elapsed
  while advisor.flipTime >= interval do
    advisor.flipTime = advisor.flipTime - interval
    advisor.flipCell = advisor.flipCell + 1
    if advisor.flipCell > cfg.frames then
      advisor.flipCell = 1
      if burst then
        advisor.flipPhase = "loop"
        advisor.flipTime = 0
        advisor.Hide(effect.uuiBurst)
        advisor.Show(effect.uuiLoop)
        advisor.FlipCell(effect.uuiLoop, 1, cfg, cfg.loopCrop)
        return
      end
    end
    if burst then
      advisor.FlipCell(effect.uuiBurst, advisor.flipCell, cfg)
    else
      advisor.FlipCell(effect.uuiLoop, advisor.flipCell, cfg, cfg.loopCrop)
    end
  end
end

function advisor.ShowNextEffect(button)
  local effect = advisor.nextEffect
  if not effect or not button then return end
  local cfg = advisor.Cfg().next
  if cfg.flipbook then
    advisor.ShowNextFlipbook(effect, button, cfg)
    return
  end
  local grow = cfg.grow
  pcall(effect.SetParent, effect, button)
  pcall(effect.ClearAllPoints, effect)
  pcall(effect.SetPoint, effect, "TOPLEFT", button, "TOPLEFT", -grow, grow)
  pcall(effect.SetPoint, effect, "BOTTOMRIGHT", button, "BOTTOMRIGHT",
    grow, -grow)
  pcall(effect.SetFrameLevel, effect,
    button:GetFrameLevel() + M.talentAdvisor.level.next)
  advisor.Show(effect)
end

function advisor.BackgroundAlias(background)
  if type(background) ~= "string" then return nil end
  background = string.gsub(background, "^.*[/\\]", "")
  background = string.gsub(background, "%.%a+$", "")
  background = string.gsub(background, "%-%a+$", "")
  local lower = string.lower(background)
  if lower == "paladinretribution" then return "PaladinCombat" end
  if lower == "warlockaffliction" then return "WarlockCurses" end
  if lower == "warlockdemonology" then return "WarlockSummoning" end
  return background
end

function advisor.TreeIndex(background)
  local data = advisor.Data()
  local trees = data and data.trees and data.trees[advisor.Class()]
  background = advisor.BackgroundAlias(background)
  local i
  for i = 1, table.getn(trees or {}) do
    if background and string.lower(trees[i][1]) == string.lower(background) then
      return i, trees[i][2]
    end
  end
  return nil, nil
end

function advisor.Build()
  local data = advisor.Data()
  local class = advisor.Class()
  return data and data.builds and data.builds[class] and
         data.builds[class][advisor.buildId]
end

function advisor.BuildList()
  local data = advisor.Data()
  local class = advisor.Class()
  local catalog = data and data.catalog and data.catalog[class]
  return catalog and catalog[advisor.context] and
         catalog[advisor.context][advisor.role] or {}
end

function advisor.Roles()
  local data = advisor.Data()
  return data and data.classRoles and data.classRoles[advisor.Class()] or {}
end

function advisor.RoleLabel(role)
  return U.L("TA_ROLE_" .. tostring(role))
end

function advisor.ContextLabel(context)
  return U.L("TA_CONTEXT_" .. tostring(context))
end

function advisor.BuildLabel(id)
  local data = advisor.Data()
  local classBuilds = data and data.builds and data.builds[advisor.Class()]
  local build = classBuilds and classBuilds[id]
  if not build then return tostring(id or "") end
  return U.L(build.label) .. "  |cff9f9f9f" .. build.split .. "|r"
end

-- Both styles carry a `drawer` table, but only Modern WoW's carries media.
-- Anything that places a widget reads advisor.Cfg().drawer, so the geometry is
-- shared; anything that draws the theme's artwork reads this instead, so the
-- flat style falls through to the shared components rather than looking for
-- atlases it has no tokens for. One check per drawing path, as the design
-- rules require, instead of a per-detail theme conditional.
function advisor.ThemedDrawer()
  local cfg = advisor.Cfg().drawer
  if cfg and not cfg.flat then return cfg end
  return nil
end

-- Recolours a flat surface built by U.CreateBackdrop, whichever of its two
-- fills the client gave it (the backdrop itself, or the fallback texture
-- U.CreateBackdrop drops in when SetBackdrop is unavailable).
function advisor.FillColor(frame, color)
  if not frame or not color then return end
  if frame.uuiFill then
    U.SetColor(frame.uuiFill, M.Unpack(color))
  elseif frame.SetBackdropColor then
    pcall(frame.SetBackdropColor, frame, M.Unpack(color))
  end
end

-- The status line, with the one case worth marking: while a talent is waiting
-- to be learned it reads in the theme's gold (user request, 2026-09-21), so
-- "Next: ..." is found at a glance among the quieter build messages.
function advisor.SetStatus(text, highlight)
  if not advisor.status then return end
  advisor.SetText(advisor.status, text)
  pcall(advisor.status.SetJustifyH, advisor.status,
    highlight and "CENTER" or "LEFT")
  local cfg = advisor.Cfg().drawer
  local color = M.color.text
  if highlight then
    color = (cfg and cfg.statusColor) or M.color.accent
  end
  pcall(advisor.status.SetTextColor, advisor.status, M.Unpack(color))
end

function advisor.PaintChoice(button, selected)
  if not button then return end
  button.uuiAdvisorSelected = selected and true or false

  -- The settings-atlas face carries its state as a tint, since the sheet
  -- ships one cell of it: a step down at rest, the authored art on hover,
  -- accent when chosen.
  local faceSpec = button.uuiAdvisorFaceSpec
  if faceSpec then
    local tint, label = faceSpec.restColor, faceSpec.labelColor
    if button.uuiAdvisorSelected then
      tint, label = faceSpec.selectedColor, faceSpec.activeLabelColor
    elseif button.uuiAdvisorHovered then
      tint, label = faceSpec.hoverColor, faceSpec.hoverLabelColor
    end
    local pieces = button.uuiAdvisorFace or {}
    local i
    for i = 1, table.getn(pieces) do
      pcall(pieces[i].SetVertexColor, pieces[i], M.Unpack(tint))
    end
    if button.label then
      pcall(button.label.SetTextColor, button.label, M.Unpack(label))
    end
    return
  end

  -- The flat build row: fill, outline and label all move together, so the
  -- row reads as one surface in each of its three states.
  local flatRow = button.uuiAdvisorFlatRow
  if flatRow then
    local fill, edge = flatRow.restFill, flatRow.restEdge
    local label = flatRow.labelColor
    if button.uuiAdvisorSelected then
      fill, edge, label = flatRow.selectedFill, flatRow.selectedEdge,
                          flatRow.activeLabelColor
    elseif button.uuiAdvisorHovered then
      fill, edge, label = flatRow.hoverFill, flatRow.hoverEdge,
                          flatRow.hoverLabelColor
    end
    advisor.FillColor(button, fill)
    U.SetBorderColor(button, M.Unpack(edge))
    if button.label then
      pcall(button.label.SetTextColor, button.label, M.Unpack(label))
    end
    return
  end

  local buildRow = button.uuiAdvisorBuildRow
  if buildRow then
    local active = button.uuiAdvisorSelected or button.uuiAdvisorHovered
    if button.uuiAdvisorBuildHighlight then
      -- The rim is always drawn and only its colour carries the state:
      -- grey at rest, lighter on hover, accent on the chosen build.
      local rim = buildRow.restColor
      if button.uuiAdvisorSelected then
        rim = buildRow.selectedColor
      elseif button.uuiAdvisorHovered then
        rim = buildRow.hoverColor
      end
      pcall(button.uuiAdvisorBuildHighlight.SetVertexColor,
        button.uuiAdvisorBuildHighlight, M.Unpack(rim))
      advisor.Show(button.uuiAdvisorBuildHighlight)
    end
    if button.label then
      local color = active and buildRow.activeLabelColor or buildRow.labelColor
      pcall(button.label.SetTextColor, button.label, M.Unpack(color))
    end
    return
  end

  -- The 128RedButton face has one other state art, its hover, and the chosen
  -- context keeps it (user request, 2026-09-21): the active button reads as
  -- lit whether or not the pointer is on it, and the label still carries the
  -- theme's warm gold over it.
  local drawerCfg = advisor.ThemedDrawer()
  if drawerCfg then
    if button.uuiAdvisorRedFace and
       type(U.ModernWowPaintRedButton) == "function" then
      local lit = button.uuiAdvisorSelected or button.uuiAdvisorHovered
      pcall(U.ModernWowPaintRedButton, button, lit and true or false)
    end
    if button.label then
      local color = selected and drawerCfg.selectedColor or
                    drawerCfg.labelColor
      pcall(button.label.SetTextColor, button.label, M.Unpack(color))
    end
    return
  end

  local border = selected and M.color.accent or M.color.border
  local text = selected and M.color.textAccent or M.color.textDim
  U.SetBorderColor(button, M.Unpack(border))
  if button.label then pcall(button.label.SetTextColor, button.label, M.Unpack(text)) end
end

function advisor.EnsureSelection()
  local roles = advisor.Roles()
  local roleFound = false
  local i
  for i = 1, table.getn(roles) do
    if roles[i] == advisor.role then roleFound = true end
  end
  if not roleFound then advisor.role = roles[1] end

  local list = advisor.BuildList()
  local buildFound = false
  for i = 1, table.getn(list) do
    if list[i] == advisor.buildId then buildFound = true end
  end
  if not buildFound then advisor.buildId = list[1] end
end

function advisor.RefreshChoices()
  advisor.EnsureSelection()
  local data = advisor.Data()
  local i
  for i = 1, table.getn(data and data.contexts or {}) do
    local context = data.contexts[i]
    local button = advisor.contextButtons[i]
    if button then
      advisor.SetText(button.label, advisor.ContextLabel(context))
      advisor.PaintChoice(button, context == advisor.context)
      advisor.Show(button)
    end
  end

  local roles = advisor.Roles()
  local showRoles = table.getn(roles) > 1
  for i = 1, table.getn(advisor.roleButtons) do
    local button = advisor.roleButtons[i]
    local role = roles[i]
    if button and role and showRoles then
      advisor.SetText(button.label, advisor.RoleLabel(role))
      advisor.PaintChoice(button, role == advisor.role)
      advisor.Show(button)
    else
      advisor.Hide(button)
    end
  end

  local list = advisor.BuildList()
  for i = 1, table.getn(advisor.rows) do
    local row = advisor.rows[i]
    local id = list[i]
    if row and id then
      advisor.SetText(row.label, advisor.BuildLabel(id))
      row.uuiBuildId = id
      advisor.PaintChoice(row, id == advisor.buildId)
      advisor.Show(row)
    else
      advisor.Hide(row)
    end
  end

  advisor.FitHeight()
end

function advisor.ClearHighlights()
  advisor.nextButton = nil
  advisor.softButtons = {}
  advisor.wrongButtons = {}
  advisor.Hide(advisor.nextEffect)
  local i, j
  for i = 1, table.getn(advisor.panels or {}) do
    local buttons = advisor.panels[i].buttons or {}
    for j = 1, table.getn(buttons) do
      local button = buttons[j]
      advisor.Hide(button and button.uuiAdvisorSoft)
      advisor.Hide(button and button.uuiAdvisorWrong)
    end
  end
end

function advisor.TargetRank(build, canonicalTree, index)
  local code = build and build.codes and build.codes[canonicalTree] or ""
  if index > string.len(code) then return 0 end
  return tonumber(string.sub(code, index, index)) or 0
end

function advisor.Validate(build)
  local data = advisor.Data()
  local trees = data and data.trees and data.trees[advisor.Class()]
  if not build or not trees or not advisor.panels then return false end

  local found = {}
  local i, j
  for i = 1, table.getn(advisor.panels) do
    local panel = advisor.panels[i]
    local canonical, expected = advisor.TreeIndex(panel.background)
    if canonical then
      found[canonical] = true
      if U.TalentGrid.NumTalents(panel.id) ~= expected then return false end
      local code = build.codes[canonical] or ""
      if string.len(code) > expected then return false end
      for j = 1, string.len(code) do
        local _, _, _, _, _, maxRank = U.TalentGrid.TalentInfo(panel.id, j)
        if not maxRank or (tonumber(string.sub(code, j, j)) or 0) > maxRank then
          return false
        end
      end
    end
  end
  return found[1] and found[2] and found[3]
end

function advisor.SequenceNext(build)
  local counts = {}
  local i, j
  for i = 1, table.getn(build.sequence or {}) do
    local _, _, treeText, indexText =
      string.find(build.sequence[i], "^(%d+):(%d+)$")
    local tree, index = tonumber(treeText), tonumber(indexText)
    local key = tostring(tree) .. ":" .. tostring(index)
    counts[key] = (counts[key] or 0) + 1
    for j = 1, table.getn(advisor.panels or {}) do
      local panel = advisor.panels[j]
      local canonical = advisor.TreeIndex(panel.background)
      if canonical == tree then
        local _, _, _, _, rank = U.TalentGrid.TalentInfo(panel.id, index)
        if (tonumber(rank) or 0) < counts[key] then return tree, index, i end
      end
    end
  end
  return nil, nil, nil
end

function advisor.CandidateScore(build, canonicalTree, tier, index,
                                sequenceTree, sequenceIndex, sequencePosition)
  if canonicalTree == sequenceTree and index == sequenceIndex then
    return -100000 + (sequencePosition or 0)
  end
  local primary = tonumber(build.primary) or 1
  local treeOrder = canonicalTree == primary and 0 or canonicalTree
  return (treeOrder * 10000) + ((tonumber(tier) or 9) * 100) + index
end

function advisor.LayoutFooter(showWarning)
  advisor.warningShown = showWarning and true or false
  local drawerCfg = advisor.Cfg().drawer
  local footer = drawerCfg and drawerCfg.footer
  if footer and advisor.status then
    pcall(advisor.status.ClearAllPoints, advisor.status)
    pcall(advisor.status.SetPoint, advisor.status, "BOTTOMLEFT", advisor.drawer,
      "BOTTOMLEFT", 10,
      advisor.warningShown and footer.statusY or footer.statusYPlain)
  end
  advisor.FitHeight()
end

function advisor.RefreshHighlights()
  advisor.ClearHighlights()
  local build = advisor.Build()
  if not advisor.Validate(build) then
    advisor.SetStatus(U.L("TA_STATUS_UNAVAILABLE"), false)
    advisor.Hide(advisor.warning)
    advisor.LayoutFooter(false)
    return
  end

  local missing, outside = 0, 0
  local nextButton, nextName, nextRank, nextTarget, nextScore
  local sequenceTree, sequenceIndex, sequencePosition = advisor.SequenceNext(build)
  local i, j
  for i = 1, table.getn(advisor.panels or {}) do
    local panel = advisor.panels[i]
    local canonical = advisor.TreeIndex(panel.background)
    for j = 1, U.TalentGrid.NumTalents(panel.id) do
      local button = panel.buttons[j]
      local name, _, tier, _, rank = U.TalentGrid.TalentInfo(panel.id, j)
      local target = advisor.TargetRank(build, canonical, j)
      rank = tonumber(rank) or 0
      if rank < target then
        missing = missing + (target - rank)
        advisor.Show(button and button.uuiAdvisorSoft)
        if button and button.uuiAdvisorSoft then
          table.insert(advisor.softButtons, button)
        end
        local score = advisor.CandidateScore(build, canonical, tier, j,
          sequenceTree, sequenceIndex, sequencePosition)
        if button and button.uuiAdvisorMeets and
           (not nextScore or score < nextScore) then
          nextButton, nextName = button, name
          nextRank, nextTarget, nextScore = rank + 1, target, score
        end
      elseif rank > target then
        outside = outside + (rank - target)
        advisor.Show(button and button.uuiAdvisorWrong)
        if button and button.uuiAdvisorWrong and
           advisor.Cfg().wrong.pulsePeriod then
          table.insert(advisor.wrongButtons, button)
        end
      end
    end
  end

  local unspent = U.TalentGrid.UnspentPoints()
  local level = U.TalentGrid.PlayerLevel()
  local availableByLevel = math.max(0, math.min(51, level - 9))
  if nextButton and unspent > 0 and availableByLevel > 0 then
    advisor.nextButton = nextButton
    advisor.Hide(nextButton.uuiAdvisorSoft)
    advisor.ShowNextEffect(nextButton)
    advisor.SetStatus(
      string.format(U.L("TA_STATUS_NEXT"), nextName or "", nextRank,
                    nextTarget), true)
  elseif missing == 0 then
    advisor.SetStatus(U.L("TA_STATUS_COMPLETE"), false)
  elseif unspent <= 0 then
    advisor.SetStatus(
      string.format(U.L("TA_STATUS_EARN_POINT"), level, missing), false)
  else
    advisor.SetStatus(U.L("TA_STATUS_RESPEC"), false)
  end

  if advisor.nextButton or table.getn(advisor.wrongButtons) > 0 then
    advisor.StartPulse()
  else
    advisor.StopPulse()
  end

  if outside > 0 then
    advisor.SetText(advisor.warning,
      string.format(U.L("TA_STATUS_OUTSIDE"), outside))
    advisor.Show(advisor.warning)
  else
    advisor.Hide(advisor.warning)
  end
  advisor.LayoutFooter(outside > 0)
end

function advisor.Refresh()
  if not advisor.built then return end
  advisor.PlaceDrawer()
  advisor.RefreshChoices()
  advisor.RefreshHighlights()
end

function advisor.SelectContext(context)
  advisor.context = context
  advisor.buildId = nil
  advisor.Refresh()
end

function advisor.SelectRole(role)
  advisor.role = role
  advisor.buildId = nil
  advisor.Refresh()
end

function advisor.SelectBuild(id)
  advisor.buildId = id
  advisor.Refresh()
end

function advisor.PlaceDrawer()
  if not advisor.frame or not advisor.drawer or not advisor.toggle then return end
  local rightOk, right = pcall(advisor.frame.GetRight, advisor.frame)
  local leftOk, left = pcall(advisor.frame.GetLeft, advisor.frame)
  -- The drawer sits beyond the toggle rather than over it, so the room it
  -- needs on a side is its own width plus the part of the button that hangs
  -- outside the window (user report, 2026-09-21).
  local widthOk, toggleWidth = pcall(advisor.toggle.GetWidth, advisor.toggle)
  toggleWidth = (widthOk and tonumber(toggleWidth)) or 26
  local needed = advisor.width + advisor.toggleEdge + (toggleWidth / 2) +
                 advisor.toggleGap

  local useLeft = rightOk and tonumber(right) and
                  right + needed > U.UIWidth() and
                  leftOk and tonumber(left) and left >= needed

  advisor.side = useLeft and "LEFT" or "RIGHT"

  advisor.toggle:ClearAllPoints()
  if useLeft then
    advisor.toggle:SetPoint("LEFT", advisor.frame, "LEFT",
      -advisor.toggleEdge, 0)
  else
    advisor.toggle:SetPoint("RIGHT", advisor.frame, "RIGHT",
      advisor.toggleEdge, 0)
  end
  advisor.AnchorDrawer(advisor.slide)
end

-- The drawer's one anchor point, taken apart from PlaceDrawer so the open and
-- close motion can re-point it per frame. It hangs off the toggle's outer
-- edge and is centred on it, so the drawer stays level with the arrow at any
-- height instead of growing away from it (user requests, 2026-09-21).
-- `shift` moves it along that axis: the open slide comes from behind the
-- toggle, which draws a frame level above the drawer and so stays visible.
function advisor.AnchorDrawer(shift)
  if not advisor.drawer or not advisor.toggle then return end
  local gap = advisor.toggleGap + (tonumber(shift) or 0)
  advisor.drawer:ClearAllPoints()
  if advisor.side == "LEFT" then
    advisor.drawer:SetPoint("RIGHT", advisor.toggle, "LEFT", -gap, 0)
  else
    advisor.drawer:SetPoint("LEFT", advisor.toggle, "RIGHT", gap, 0)
  end
end

-- SetAlpha reaches a widget's own regions only -- it is not inherited by
-- child frames (documentation.json / widget-method:UIObject:SetAlpha) -- so
-- the drawer's own housing fading left every button on it solid (user report,
-- 2026-09-21). The fade is applied to the drawer and to each button it
-- carries; their labels are regions of those buttons and come along. Collected
-- once, after the build, because the set never changes.
function advisor.FadeParts()
  if advisor.fadeParts then return advisor.fadeParts end
  local parts = {}
  local function Add(object)
    if object then table.insert(parts, object) end
  end
  Add(advisor.drawer)
  Add(advisor.divider)
  Add(advisor.listDivider)
  Add(advisor.buildDivider)
  local i
  for i = 1, table.getn(advisor.contextButtons) do
    Add(advisor.contextButtons[i])
  end
  for i = 1, table.getn(advisor.roleButtons) do Add(advisor.roleButtons[i]) end
  for i = 1, table.getn(advisor.rows) do Add(advisor.rows[i]) end
  advisor.fadeParts = parts
  return parts
end

function advisor.FadeDrawer(value)
  local parts = advisor.FadeParts()
  local i
  for i = 1, table.getn(parts) do
    pcall(parts[i].SetAlpha, parts[i], value)
  end
end

-- Open and close as one eased value (user request, 2026-09-21): the fade and
-- the slide both read off it, so a drawer interrupted mid-motion picks the
-- value up in the other direction instead of jumping. Runs on the shared
-- easing helper, which owns the ticker and the GetTime clock.
--
-- The drawer opens by sliding out of the window and closes by sliding back
-- into it (user request, 2026-09-21), which on the left side is the mirror of
-- that, not a literal rightward move: the motion always reads as the drawer
-- coming out from under its own window rather than flying in from the screen
-- edge.
function advisor.AnimateDrawer(open)
  local anim = M.talentAdvisor.drawerAnim
  local drawer = advisor.drawer
  if not drawer then return end

  local shownOk, shown = pcall(drawer.IsShown, drawer)
  shown = shownOk and shown and true or false

  -- Nothing to animate away when the drawer was never on screen: the build
  -- closes the drawer once before it is ever shown.
  if not open and not shown then
    advisor.slide = 0
    advisor.AnchorDrawer(0)
    advisor.FadeDrawer(1)
    return
  end

  local function Settle()
    advisor.slide = 0
    if not open then advisor.Hide(drawer) end
    advisor.AnchorDrawer(0)
    advisor.FadeDrawer(1)
  end

  if not anim or type(U.StartEasing) ~= "function" then
    if open then advisor.Show(drawer) end
    Settle()
    return
  end

  -- Pick up wherever the last motion stopped rather than snapping first.
  local alphaOk, alpha = pcall(drawer.GetAlpha, drawer)
  local from = (open and shown and alphaOk and tonumber(alpha)) or
               (open and 0) or 1

  local function Apply(value)
    advisor.FadeDrawer(value)
    -- Tucked behind the window at 0, resting place at 1.
    advisor.slide = -anim.distance * (1 - value)
    advisor.AnchorDrawer(advisor.slide)
  end

  if open then
    Apply(from)
    advisor.Show(drawer)
  end

  local started = U.StartEasing("talentadvisor.drawer", {
    from = from,
    to = open and 1 or 0,
    duration = open and anim.openDuration or anim.closeDuration,
    ease = open and U.EaseOutCubic or U.EaseInOutCubic,
    onUpdate = Apply,
    onComplete = Settle,
  })
  if not started then
    if open then advisor.Show(drawer) end
    Settle()
  end
end

function advisor.SetOpen(open)
  advisor.open = open and true or false
  advisor.PlaceDrawer()
  advisor.AnimateDrawer(advisor.open)
  local pointsRight
  if advisor.side == "LEFT" then
    pointsRight = advisor.open
  else
    pointsRight = not advisor.open
  end

  local toggleCfg = advisor.Cfg().toggle
  if toggleCfg and advisor.toggle and advisor.toggle.uuiArrow then
    local spec = toggleCfg.arrow
    advisor.ArrowCell(advisor.toggle.uuiArrow,
      pointsRight and spec.right or spec.left, spec.sheet)
    return
  end
  advisor.SetText(advisor.toggle.label, pointsRight and ">" or "<")
end

-- One glyph of the settings atlas, by texel box.
function advisor.ArrowCell(texture, box, sheet)
  if not texture or not box then return end
  pcall(texture.SetTexCoord, texture,
    box[1] / sheet, box[2] / sheet, box[3] / sheet, box[4] / sheet)
end

-- The drawer's open/close control in the flat system (user request,
-- 2026-09-21): the shared button, with its chevron and its 1-unit outline
-- both in the addon accent. It is the one control hanging outside the talent
-- window, so it reads as UnrealUI's own rather than as another panel edge.
--
-- The accent is already the resting state, so hover cannot brighten the
-- outline further: the state lands on the fill instead, which is the same
-- accent fill every selected flat surface here uses.
function advisor.BuildFlatToggle(parent, onClick)
  local rest = { 0.02, 0.018, 0.014, 0.98 }
  local button = U.CreateButton(parent, {
    width = advisor.toggleWidth,
    height = advisor.toggleHeight,
    size = M.fontSize.normal,
    text = ">",
    textColor = M.color.accent,
    background = rest,
    border = M.color.accent,
    hoverBorder = M.color.accent,
    onClick = onClick,
  })
  if not button then return nil end
  button:SetScript("OnEnter", function()
    advisor.FillColor(button, M.color.accentFill)
  end)
  button:SetScript("OnLeave", function()
    advisor.FillColor(button, rest)
  end)
  return button
end

-- The drawer's arrow as a Modern WoW control: dark bed, the theme's own
-- ThinBorder rim, and a settings-atlas arrow over it. Built instead of the
-- shared text button, never on top of it, so no flat chrome is applied first
-- and taken back off.
function advisor.BuildThemedToggle(parent, cfg, onClick)
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, cfg.width)
  pcall(button.SetHeight, button, cfg.height)

  -- Inset, not SetAllPoints: the rim art is mostly clear canvas, so a bed
  -- filling the button's rect reads as a black square around the border.
  local inset = tonumber(cfg.backgroundInset) or 0
  local bed = advisor.Texture(button, "BACKGROUND", M.texture.plain)
  if bed then
    pcall(bed.SetPoint, bed, "TOPLEFT", button, "TOPLEFT", inset, -inset)
    pcall(bed.SetPoint, bed, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset,
      inset)
    pcall(bed.SetVertexColor, bed, M.Unpack(cfg.background))
  end

  -- The rim the profession and loot windows already borrow. It is the
  -- theme's simple border, and it knows its own art: nothing here builds a
  -- second copy of those eight pieces.
  if type(U.ModernWowBuildThinBorder) == "function" then
    pcall(U.ModernWowBuildThinBorder, button, cfg.borderSize,
      cfg.borderBottomRight)
  end

  local spec = cfg.arrow
  local arrow = advisor.Texture(button, "ARTWORK", spec.texture)
  if arrow then
    pcall(arrow.SetWidth, arrow, spec.width)
    pcall(arrow.SetHeight, arrow, spec.height)
    pcall(arrow.SetPoint, arrow, "CENTER", button, "CENTER", 0, 0)
    pcall(arrow.SetAlpha, arrow, spec.alpha)
    advisor.ArrowCell(arrow, spec.right, spec.sheet)
  end
  button.uuiArrow = arrow

  button:SetScript("OnEnter", function()
    if arrow then pcall(arrow.SetAlpha, arrow, spec.hoverAlpha) end
  end)
  button:SetScript("OnLeave", function()
    if arrow then pcall(arrow.SetAlpha, arrow, spec.alpha) end
  end)
  local function Drop(offset)
    if not arrow then return end
    pcall(arrow.ClearAllPoints, arrow)
    pcall(arrow.SetPoint, arrow, "CENTER", button, "CENTER", 0, offset)
  end
  button:SetScript("OnMouseDown", function() Drop(-spec.pressDrop) end)
  button:SetScript("OnMouseUp", function() Drop(0) end)
  if onClick then button:SetScript("OnClick", onClick) end
  return button
end

-- One choice as a Modern WoW action: the measured 128RedButton three-slice
-- face, its own label, and the shared paint for hover. Built instead of the
-- flat button, never over it.
function advisor.BuildRedChoice(parent, width, text, onClick, cfg)
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, cfg.buttonHeight)
  pcall(button.EnableMouse, button, true)
  if onClick then button:SetScript("OnClick", onClick) end

  button.label = U.CreateLabel(button, {
    size = M.fontSize.tiny,
    color = cfg.labelColor,
    inherits = "GameFontNormalSmall",
    width = width - 8,
    justify = "CENTER",
  })
  if button.label then
    pcall(button.label.SetPoint, button.label, "CENTER", button, "CENTER", 0,
      cfg.labelY)
    pcall(button.label.SetText, button.label, text or "")
  end

  if type(U.ModernWowRedButtonFace) == "function" then
    pcall(U.ModernWowRedButtonFace, button, cfg.buttonHeight)
  end
  -- Both states go through the shared paint rather than straight to the face:
  -- a selected button must not fall back to the normal art when the pointer
  -- leaves it.
  button.uuiAdvisorRedFace = true
  button:SetScript("OnEnter", function()
    button.uuiAdvisorHovered = true
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  button:SetScript("OnLeave", function()
    button.uuiAdvisorHovered = false
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  return button
end

-- One role choice as the settings atlas's rounded button (user request,
-- 2026-09-21). Three-sliced exactly like the red face beside it: the two ends
-- keep the cell's own aspect so the corner round cannot smear, and only the
-- flat middle stretches to the width asked for. The sheet has one cell, so
-- the state lives in the face's tint, painted by advisor.PaintChoice.
function advisor.BuildSettingChoice(parent, width, text, onClick, cfg)
  local spec = cfg.roleButton
  if not spec then return nil end
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  local height = cfg.buttonHeight
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, height)
  pcall(button.EnableMouse, button, true)
  if onClick then button:SetScript("OnClick", onClick) end

  local cell = spec.cell
  local sheet = spec.sheet
  local cap = spec.cap * (height / (cell[4] - cell[3]))
  local top, bottom = cell[3] / sheet, cell[4] / sheet
  local face = {}

  local left = advisor.Texture(button, "BORDER", spec.texture)
  if left then
    pcall(left.SetTexCoord, left, cell[1] / sheet, (cell[1] + spec.cap) / sheet,
      top, bottom)
    pcall(left.SetPoint, left, "TOPLEFT", button, "TOPLEFT", 0, 0)
    pcall(left.SetPoint, left, "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    pcall(left.SetWidth, left, cap)
    table.insert(face, left)
  end

  local right = advisor.Texture(button, "BORDER", spec.texture)
  if right then
    pcall(right.SetTexCoord, right, (cell[2] - spec.cap) / sheet,
      cell[2] / sheet, top, bottom)
    pcall(right.SetPoint, right, "TOPRIGHT", button, "TOPRIGHT", 0, 0)
    pcall(right.SetPoint, right, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    pcall(right.SetWidth, right, cap)
    table.insert(face, right)
  end

  local middle = advisor.Texture(button, "BORDER", spec.texture)
  if middle then
    pcall(middle.SetTexCoord, middle, (cell[1] + spec.cap) / sheet,
      (cell[2] - spec.cap) / sheet, top, bottom)
    pcall(middle.SetPoint, middle, "TOPLEFT", button, "TOPLEFT", cap, 0)
    pcall(middle.SetPoint, middle, "BOTTOMRIGHT", button, "BOTTOMRIGHT",
      -cap, 0)
    table.insert(face, middle)
  end

  button.label = U.CreateLabel(button, {
    size = M.fontSize.tiny,
    color = spec.labelColor,
    inherits = "GameFontNormalSmall",
    width = width - (cap * 2) - 4,
    justify = "CENTER",
  })
  if button.label then
    pcall(button.label.SetPoint, button.label, "CENTER", button, "CENTER", 0,
      cfg.labelY)
    pcall(button.label.SetText, button.label, text or "")
  end

  button.uuiAdvisorFaceSpec = spec
  button.uuiAdvisorFace = face
  button:SetScript("OnEnter", function()
    button.uuiAdvisorHovered = true
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  button:SetScript("OnLeave", function()
    button.uuiAdvisorHovered = false
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  advisor.PaintChoice(button, false)
  return button
end

-- The role row's builder: the themed drawer uses the settings-atlas button,
-- and the flat style keeps the shared text button as every other choice does.
function advisor.BuildRoleChoice(parent, width, text, onClick)
  local drawerCfg = advisor.ThemedDrawer()
  if drawerCfg then
    local themed = advisor.BuildSettingChoice(parent, width, text, onClick,
      drawerCfg)
    if themed then return themed end
  end
  return advisor.BuildChoice(parent, width, text, onClick)
end

function advisor.BuildRecipeChoice(parent, width, text, onClick, cfg)
  local rowCfg = cfg.buildRow
  if not rowCfg then return nil end
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, cfg.rowHeight)
  pcall(button.EnableMouse, button, true)
  if onClick then button:SetScript("OnClick", onClick) end

  local highlight = advisor.Texture(button, "BORDER", rowCfg.texture)
  if highlight then
    local cell = rowCfg.cell
    pcall(highlight.SetTexCoord, highlight,
      cell.left / rowCfg.atlasWidth, cell.right / rowCfg.atlasWidth,
      cell.top / rowCfg.atlasHeight, cell.bottom / rowCfg.atlasHeight)
    pcall(highlight.SetPoint, highlight, "LEFT", button, "LEFT", 0, -1)
    pcall(highlight.SetPoint, highlight, "RIGHT", button, "RIGHT", 0, -1)
    pcall(highlight.SetHeight, highlight, rowCfg.height)
    advisor.Hide(highlight)
  end

  button.label = U.CreateLabel(button, {
    size = M.fontSize.tiny,
    color = rowCfg.labelColor,
    inherits = "GameFontNormalSmall",
    width = width - 12,
    justify = "LEFT",
  })
  if button.label then
    pcall(button.label.SetPoint, button.label, "LEFT", button, "LEFT", 8,
      cfg.labelY)
    pcall(button.label.SetText, button.label, text or "")
  end

  button.uuiAdvisorBuildRow = rowCfg
  button.uuiAdvisorBuildHighlight = highlight
  button:SetScript("OnEnter", function()
    button.uuiAdvisorHovered = true
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  button:SetScript("OnLeave", function()
    button.uuiAdvisorHovered = false
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  return button
end

-- One build row in the flat system, and the twin of the themed row above:
-- the same height and pitch, the same left-aligned label, and the same three
-- states -- neutral, hover, chosen -- carried by a flat surface with a single
-- 1-unit outline instead of the profession atlas's highlight.
function advisor.BuildFlatRow(parent, width, text, onClick, cfg)
  -- Only a style that declares the flat row owns these colours; a themed cfg
  -- reaching here means its own builder failed, and it falls through to the
  -- shared button rather than being painted from tokens it does not carry.
  local spec = cfg and cfg.buildRow
  if not spec or not spec.flat then return nil end
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, cfg.rowHeight or advisor.rowHeight)
  pcall(button.EnableMouse, button, true)
  if onClick then button:SetScript("OnClick", onClick) end

  U.CreateBackdrop(button, {
    background = spec.restFill,
    border = spec.restEdge,
  })

  button.label = U.CreateLabel(button, {
    size = M.fontSize.tiny,
    color = spec.labelColor,
    inherits = "GameFontNormalSmall",
    width = width - 12,
    justify = "LEFT",
  })
  if button.label then
    pcall(button.label.SetPoint, button.label, "LEFT", button, "LEFT", 8,
      cfg.labelY or 0)
    pcall(button.label.SetText, button.label, text or "")
  end

  button.uuiAdvisorFlatRow = spec
  button:SetScript("OnEnter", function()
    button.uuiAdvisorHovered = true
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  button:SetScript("OnLeave", function()
    button.uuiAdvisorHovered = false
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  advisor.PaintChoice(button, false)
  return button
end

function advisor.BuildChoice(parent, width, text, onClick)
  local drawerCfg = advisor.ThemedDrawer()
  if drawerCfg then
    local themed = advisor.BuildRedChoice(parent, width, text, onClick,
      drawerCfg)
    if themed then return themed end
  end

  -- The flat choice takes its height from the same token the themed face
  -- uses, so both styles put the context and role rows on the same baseline.
  local cfg = advisor.Cfg().drawer
  local button = U.CreateButton(parent, {
    width = width,
    height = (cfg and cfg.buttonHeight) or 23,
    size = M.fontSize.tiny,
    text = text,
    background = { 0.025, 0.022, 0.018, 0.96 },
    border = M.color.border,
    hoverBorder = M.color.accent,
    onClick = onClick,
  })
  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(M.color.moverEdge))
  end)
  button:SetScript("OnLeave", function()
    advisor.PaintChoice(button, button.uuiAdvisorSelected)
  end)
  return button
end

-- One of the drawer's rules: the theme's Dialog Box divider, laid across the
-- bed at the given distance below the drawer's top edge.
function advisor.BuildDivider(drawer, spec, y)
  if not spec then return nil end

  -- The flat style draws the shared 1-unit rule instead of the theme's bar.
  -- It is placed by the same token, so both drawers put their rules in the
  -- same place in the layout; only the line itself differs.
  if not advisor.ThemedDrawer() then
    local rule = U.CreateRule(drawer, {
      thickness = spec.height or U.BorderSize(),
      color = spec.color or M.color.border,
    })
    if not rule then return nil end
    pcall(rule.SetWidth, rule, advisor.width - (spec.inset * 2))
    pcall(rule.SetPoint, rule, "TOP", drawer, "TOP", 0, y)
    return rule
  end

  if type(U.ModernWowHorizontalBar) ~= "function" then return nil end
  local bar = U.ModernWowHorizontalBar(drawer,
    advisor.width - (spec.inset * 2), spec.height, "OVERLAY")
  if not bar then return nil end
  pcall(bar.SetPoint, bar, "TOP", drawer, "TOP", 0, y)
  return bar
end

-- The drawer's Modern WoW housing: the diamond-metal frame this theme uses
-- for every dock, with a background-rock bed inside it. Called again on a
-- resize so the frame re-lays its corners and edges at the new height.
function advisor.DressDrawer(drawer, cfg)
  -- Flat style: one near-black panel with the shared 1-unit outline. It is
  -- built once -- the backdrop follows the frame, so a resize needs nothing
  -- more -- while the themed housing below re-lays its corners every time.
  if cfg.flat then
    if drawer.uuiAdvisorFlatBed then return end
    U.CreateBackdrop(drawer, {
      background = cfg.background,
      border = M.color.border,
    })
    drawer.uuiAdvisorFlatBed = true
    return
  end

  if type(U.ModernWowMetalFrame) == "function" then
    pcall(U.ModernWowMetalFrame, drawer, advisor.width, advisor.height)
  end
  if drawer.uuiAdvisorRock then return end

  local rock = advisor.Texture(drawer, "ARTWORK",
    M.modernWow.texture.questFooter)
  if not rock then return end
  pcall(function()
    rock:ClearAllPoints()
    rock:SetPoint("TOPLEFT", drawer, "TOPLEFT", cfg.inset, -cfg.inset)
    rock:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -cfg.inset, cfg.inset)
  end)
  U.SetColor(rock, cfg.rockShade, cfg.rockShade, cfg.rockShade,
    cfg.rockAlpha or 1)
  drawer.uuiAdvisorRock = rock
end

-- Sizes the drawer to what it is actually showing, in either style: the rows
-- above the list stay put, the build rows are counted, and the bottom block
-- drops the warning row when no points are outside the selected build.
function advisor.FitHeight()
  local cfg = advisor.Cfg().drawer
  if not cfg or not advisor.drawer then return end

  local shown = 0
  local i
  for i = 1, table.getn(advisor.rows) do
    local row = advisor.rows[i]
    local ok, visible = pcall(row.IsShown, row)
    if ok and visible then shown = shown + 1 end
  end

  local body = 0
  if shown > 0 then
    body = shown * (advisor.rowHeight + advisor.rowGap) - advisor.rowGap
  end
  local dividerSpec = cfg.buildDivider
  if advisor.buildDivider and dividerSpec then
    pcall(advisor.buildDivider.ClearAllPoints, advisor.buildDivider)
    pcall(advisor.buildDivider.SetPoint, advisor.buildDivider, "TOP",
      advisor.drawer, "TOP", 0,
      -((advisor.rowsTop or 0) + body + dividerSpec.gap))
  end
  local bottomBlock = advisor.warningShown and cfg.bottomBlock or
                      (cfg.bottomBlockPlain or cfg.bottomBlock)
  local height = (advisor.rowsTop or 0) + body + cfg.rowsGap + bottomBlock
  local minHeight = advisor.warningShown and cfg.minHeight or
                    (cfg.minHeightPlain or cfg.minHeight)
  if height < minHeight then height = minHeight end
  if height == advisor.height then return end

  advisor.height = height
  pcall(advisor.drawer.SetHeight, advisor.drawer, height)
  advisor.DressDrawer(advisor.drawer, cfg)
end

function advisor.BuildUI(frame, chrome, panels)
  if advisor.built then return advisor.toggle end
  if not frame or not chrome or not advisor.Data() then return nil end
  advisor.frame = frame
  advisor.panels = panels
  advisor.BuildNextEffect(chrome)

  -- The themed drawer carries its own width and row metrics; the flat one
  -- keeps the module defaults.
  local drawerCfg = advisor.Cfg().drawer
  if drawerCfg then
    advisor.width = drawerCfg.width or advisor.width
    advisor.rowHeight = drawerCfg.rowHeight or advisor.rowHeight
    advisor.rowGap = drawerCfg.rowGap or advisor.rowGap
  end

  local drawer = CreateFrame("Frame", nil, chrome)
  drawer:SetWidth(advisor.width)
  drawer:SetHeight(advisor.height)
  pcall(drawer.SetFrameLevel, drawer, frame:GetFrameLevel() + 7)
  advisor.drawer = drawer
  if drawerCfg then
    advisor.DressDrawer(drawer, drawerCfg)
  else
    U.CreateBackdrop(drawer, {
      background = { 0.02, 0.018, 0.014, 0.98 },
      border = M.color.border,
    })
  end

  advisor.title = U.CreateLabel(drawer, {
    size = M.fontSize.normal,
    -- M.color.accent, not M.color.highlight: highlight is the 22%-alpha fill
    -- token for a hover surface, and a heading drawn in it is barely legible.
    color = M.color.accent,
    inherits = "GameFontNormal",
    width = advisor.width - 24,
    justify = "CENTER",
  })
  if advisor.title then
    advisor.title:SetPoint("TOP", drawer, "TOP", 0,
      drawerCfg and drawerCfg.titleY or -12)
    advisor.title:SetText(U.L("TA_TITLE"))
    if drawerCfg then
      pcall(advisor.title.SetTextColor, advisor.title,
        M.Unpack(drawerCfg.titleColor))
    end
  end

  -- The theme's own rule under the heading, between it and the context row.
  local dividerCfg = drawerCfg and drawerCfg.divider
  if dividerCfg then
    advisor.divider = advisor.BuildDivider(drawer, dividerCfg, dividerCfg.y)
  end

  local data = advisor.Data()
  local contextWidth = math.floor((advisor.width - 28) / 3)
  local i
  for i = 1, table.getn(data.contexts) do
    local context = data.contexts[i]
    local button
    button = advisor.BuildChoice(drawer, contextWidth,
      advisor.ContextLabel(context), function()
        advisor.SelectContext(button.uuiAdvisorContext)
      end)
    button.uuiAdvisorContext = context
    button:SetPoint("TOPLEFT", drawer, "TOPLEFT",
                    8 + ((i - 1) * (contextWidth + 2)),
                    (drawerCfg and drawerCfg.contextY) or -37)
    advisor.contextButtons[i] = button
  end

  local roles = advisor.Roles()
  local showRoles = table.getn(roles) > 1
  if showRoles then
    local roleWidth = math.floor((advisor.width - 18 - (table.getn(roles) - 1) * 2) /
                                 table.getn(roles))
    for i = 1, table.getn(roles) do
      local role = roles[i]
      local button
      button = advisor.BuildRoleChoice(drawer, roleWidth,
        advisor.RoleLabel(role), function()
          advisor.SelectRole(button.uuiAdvisorRole)
        end)
      button.uuiAdvisorRole = role
      button:SetPoint("TOPLEFT", drawer, "TOPLEFT",
                      8 + ((i - 1) * (roleWidth + 2)),
                      (drawerCfg and drawerCfg.roleY) or -64)
      advisor.roleButtons[i] = button
    end
  end

  -- And a second one between the choices above and the build list (user
  -- request, 2026-09-21), which sits higher when this class has no role row.
  local listCfg = drawerCfg and drawerCfg.listDivider
  if listCfg then
    advisor.listDivider = advisor.BuildDivider(drawer, listCfg,
      showRoles and listCfg.y or listCfg.yPlain)
  end

  local buildTop
  if showRoles then
    buildTop = (drawerCfg and drawerCfg.buildTop) or -96
  else
    buildTop = (drawerCfg and drawerCfg.buildTopPlain) or -66
  end
  advisor.rowsTop = -buildTop
  for i = 1, 7 do
    local row
    local themed = advisor.ThemedDrawer()
    local function Choose()
      if row.uuiBuildId then advisor.SelectBuild(row.uuiBuildId) end
    end
    row = (themed and advisor.BuildRecipeChoice(drawer, advisor.width - 16,
            "", Choose, themed)) or
          advisor.BuildFlatRow(drawer, advisor.width - 16, "", Choose,
            drawerCfg) or
          advisor.BuildChoice(drawer, advisor.width - 16, "", Choose)
    row:SetPoint("TOPLEFT", drawer, "TOPLEFT", 8,
                 buildTop - ((i - 1) * (advisor.rowHeight + advisor.rowGap)))
    advisor.rows[i] = row
  end

  local buildDividerCfg = drawerCfg and drawerCfg.buildDivider
  if buildDividerCfg then
    advisor.buildDivider = advisor.BuildDivider(drawer, buildDividerCfg, 0)
  end

  local footerCfg = drawerCfg and drawerCfg.footer
  advisor.legend = U.CreateLabel(drawer, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    width = advisor.width - 16,
    height = 18,
    justify = "CENTER",
  })
  -- The colour key is the block's last line (user request, 2026-09-21): the
  -- build's own state reads first, then its warning, and the legend explaining
  -- the talent marks sits under both.
  if advisor.legend then
    advisor.legend:SetPoint("BOTTOM", drawer, "BOTTOM", 0,
      footerCfg and footerCfg.legendY or 9)
    advisor.legend:SetText(U.L("TA_LEGEND"))
  end

  advisor.status = U.CreateLabel(drawer, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    width = advisor.width - 20,
    height = 30,
    justify = "LEFT",
  })
  if advisor.status then
    advisor.status:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 10,
      footerCfg and footerCfg.statusYPlain or 73)
  end

  advisor.warning = U.CreateLabel(drawer, {
    size = M.fontSize.tiny,
    color = M.color.closeGlyph,
    inherits = "GameFontNormalSmall",
    width = advisor.width - 20,
    height = 18,
    justify = "LEFT",
  })
  if advisor.warning then
    advisor.warning:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 10,
      footerCfg and footerCfg.warningY or 51)
  end

  local toggleCfg = advisor.Cfg().toggle
  local function Toggled() advisor.SetOpen(not advisor.open) end
  if toggleCfg then
    advisor.toggle = advisor.BuildThemedToggle(chrome, toggleCfg, Toggled)
  end
  if not advisor.toggle then
    advisor.toggle = advisor.BuildFlatToggle(chrome, Toggled)
  end
  pcall(advisor.toggle.SetFrameLevel, advisor.toggle, frame:GetFrameLevel() + 8)

  advisor.built = true
  advisor.EnsureSelection()
  advisor.SetOpen(false)
  advisor.Refresh()
  return advisor.toggle
end

-- One highlight overlay on one talent button, drawn from whatever the mark's
-- spec asks for: the client's alert art, which is what both styles now use,
-- or the flat system's single 1-unit outline, grown clear of the button's own
-- edge so the two rules stay readable instead of doubling. Either way it
-- returns a frame whose `uuiGlow` is the object the pulse fades, so nothing
-- after this branches on style.
function advisor.Mark(button, level, cfg)
  local ok, frame = pcall(CreateFrame, "Frame", nil, button)
  if not ok or not frame then return nil end
  pcall(frame.SetFrameLevel, frame, button:GetFrameLevel() + level)
  pcall(frame.EnableMouse, frame, false)
  local grow = tonumber(cfg.grow) or 0

  if cfg.outline then
    pcall(frame.SetPoint, frame, "TOPLEFT", button, "TOPLEFT", -grow, grow)
    pcall(frame.SetPoint, frame, "BOTTOMRIGHT", button, "BOTTOMRIGHT",
      grow, -grow)
    U.CreateBorder(frame)
    U.SetBorderColor(frame, M.Unpack(cfg.color))
    frame.uuiGlow = frame
    advisor.Hide(frame)
    return frame
  end

  frame:SetAllPoints(button)
  local glow = advisor.Texture(frame, "OVERLAY", cfg.texture)
  if glow then
    local y = tonumber(cfg.y) or 0
    pcall(glow.SetVertexColor, glow, M.Unpack(cfg.color))
    pcall(glow.SetPoint, glow, "TOPLEFT", frame, "TOPLEFT", -grow, grow + y)
    pcall(glow.SetPoint, glow, "BOTTOMRIGHT", frame, "BOTTOMRIGHT",
      grow, -grow + y)
  end
  frame.uuiGlow = glow
  advisor.Hide(frame)
  return frame
end

-- Names the media set before anything is built. Only one talent path is ever
-- built in a session, so this is module state rather than a per-call argument.
function U.TalentAdvisorStyle(style)
  if type(style) == "string" and M.talentAdvisor.styles[style] then
    advisor.style = style
  end
end

function U.TalentAdvisorBind(button)
  if not advisor.Enabled() then return end
  if not button or button.uuiAdvisorSoft then return end
  local cfg = advisor.Cfg()

  local levels = M.talentAdvisor.level
  local soft = advisor.Mark(button, levels.soft, cfg.soft)
  if soft and soft.uuiGlow then
    pcall(soft.uuiGlow.SetAlpha, soft.uuiGlow, cfg.soft.restAlpha)
    -- A flipbook mark shows its whole sheet until a cell is chosen.
    if cfg.soft.ants then advisor.AntsCell(soft.uuiGlow, 1) end
  end

  local wrong = advisor.Mark(button, levels.wrong, cfg.wrong)
  if wrong and wrong.uuiGlow then
    pcall(wrong.uuiGlow.SetAlpha, wrong.uuiGlow, cfg.wrong.alpha)
  end

  button.uuiAdvisorSoft = soft
  button.uuiAdvisorWrong = wrong
end

function U.TalentAdvisorTalentState(button, meets)
  if button then button.uuiAdvisorMeets = meets and true or false end
end

function U.BuildTalentAdvisor(frame, chrome, panels)
  if not advisor.Enabled() then return nil end
  return advisor.BuildUI(frame, chrome, panels)
end

function U.RefreshTalentAdvisor()
  if not advisor.Enabled() then return end
  advisor.Refresh()
end

function U.TalentAdvisorProbeTarget()
  if not advisor.Enabled() then return nil end
  return advisor.nextButton
end

function U.TalentAdvisorProbeOverlay()
  if not advisor.Enabled() then return nil end
  return advisor.nextEffect
end
