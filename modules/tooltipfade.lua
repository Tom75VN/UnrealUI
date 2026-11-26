-- unrealUI :: modules/tooltipfade.lua
--
-- Fade-out for tooltips that close with a plain Hide() (user request,
-- 2026-11-26). Item, button, unit-frame and comparison tooltips vanished in a
-- single frame; only world units faded, through the client's own fade and
-- modules/tooltip.lua's cursor-mode ramp.
--
-- The native tooltip itself is never held on screen. Replacing a GameTooltip
-- method does not hold on this client (modules/itemprice.lua,
-- USER_CONFIRMED_INGAME 2026-08-26), and a tooltip kept showing stays owned,
-- so a button's OnUpdate would repopulate it. Instead, the moment a tooltip
-- hides, an addon-owned copy is drawn over its exact rect -- body, theme rim,
-- text rows and the unit health bar -- and that copy fades. Only numbers and
-- strings are carried over; the copy keeps no reference to a native region
-- (.claude/rules/unreal-ui.md, native widget ownership boundaries).
--
-- Every region's alpha is written explicitly: parent alpha does not reliably
-- reach child regions here (knowledge.json /
-- rendering.parent_alpha_not_propagated). The 3.3.5a AnimationGroup port is
-- documentation-only on this client, so the ramp is a plain OnUpdate. Rects
-- come from Region:GetRect and sizes go through Region:SetSize, both verified
-- by probe wotlkports.v1.
--
-- Two ways in:
--
--   * Any tooltip closed with Hide() (items, buttons, unit frames, the
--     comparison frames): copied from an OnHide pre-hook and faded at once.
--     Not copied when the tooltip was already fading (the client's own
--     fixed-anchor world fade): that hide ends a fade that already played.
--   * The cursor-follow world tooltip (U.FadeOutWorldTooltip, called by
--     modules/tooltip.lua on mouse-out): copied, and the copy held for the
--     "Tooltip mouse-out delay" before it fades. The real tooltip is never
--     hidden mid-fade -- that breaks the client's world hover (see
--     placement.FadeOutWorld) -- tooltip.lua only keeps it transparent until
--     the client's own fade closes it.
--
-- A copy is cancelled the moment the same tooltip shows again, or (world
-- fade) the moment something new is hovered, so the old and the new text
-- never overlap.
--
-- UnrealQuest's creature tooltip covers GameTooltip with its own panel. It
-- reads the copy's opacity through U.WorldTooltipFadeAlpha and fades with it;
-- under a shown cover the copy itself stays invisible, because two
-- translucent boxes stacked show both texts (UnrealQuest's tooltipdupe v4).
--
-- Everything lives on the `fade` table (one top-level local slot).

local U = UnrealUI
local M = U.media

local TF = U.RegisterModule("tooltipfade")

local fade = {
  SOURCES = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" },
  SIDES = { "Left", "Right" },
  -- Below this the tooltip was already part-way through a fade.
  OPAQUE = 0.99,
  -- The visible ramp, after any hold.
  FADE_OUT = 0.20,
  ghosts = {},
  -- True from a world hand-off until GameTooltip next hides or shows: the
  -- client's own fade is still running on it, and its closing hide must not
  -- be copied a second time.
  worldPending = false,
  -- UnrealQuest's covering panel, registered by U.WorldTooltipFadeAlpha.
  cover = nil,
}

local function Num(value)
  return type(value) == "number" and value or nil
end

function fade.Shown(region)
  if not region or not region.IsShown then return false end
  local ok, shown = pcall(region.IsShown, region)
  return ok and shown and true or false
end

-- left, bottom, width, height in the region's own scale, or nil.
function fade.Rect(region)
  if not region or not region.GetRect then return nil end
  local ok, left, bottom, width, height = pcall(region.GetRect, region)
  if not ok or not Num(left) or not Num(bottom) or not Num(width) or
     not Num(height) or width <= 0 or height <= 0 then
    return nil
  end
  return left, bottom, width, height
end

function fade.ScaleRatio(frame)
  local ok, scale = pcall(frame.GetEffectiveScale, frame)
  local uiOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
  if not ok or not uiOk or not Num(scale) or not Num(uiScale) or
     scale <= 0 or uiScale <= 0 then
    return 1
  end
  return scale / uiScale
end

-- One drawn text region as plain values, positioned from the copy's top-left.
function fade.ReadText(region, left0, top0)
  if not fade.Shown(region) or not region.GetText then return nil end
  local textOk, text = pcall(region.GetText, region)
  if not textOk or type(text) ~= "string" or text == "" then return nil end
  local left, bottom, width, height = fade.Rect(region)
  if not left then return nil end

  local row = {
    text = text,
    x = left - left0,
    y = bottom + height - top0,
    width = width,
    height = height,
    r = 1, g = 1, b = 1,
    justify = "LEFT",
  }
  local fontOk, font, size, flags = pcall(region.GetFont, region)
  if fontOk and type(font) == "string" and Num(size) then
    row.font, row.size, row.flags = font, size, flags
  end
  local colorOk, r, g, b = pcall(region.GetTextColor, region)
  if colorOk and Num(r) and Num(g) and Num(b) then
    row.r, row.g, row.b = r, g, b
  end
  if region.GetJustifyH then
    local justifyOk, justify = pcall(region.GetJustifyH, region)
    if justifyOk and type(justify) == "string" then row.justify = justify end
  end
  return row
end

function fade.CaptureBar(left0, top0)
  local bar = U.G("GameTooltipStatusBar")
  if not fade.Shown(bar) then return nil end
  local left, bottom, width, height = fade.Rect(bar)
  if not left then return nil end

  local pct = 1
  local valueOk, value = pcall(bar.GetValue, bar)
  local rangeOk, minValue, maxValue = pcall(bar.GetMinMaxValues, bar)
  if valueOk and rangeOk and Num(value) and Num(minValue) and Num(maxValue) and
     maxValue > minValue then
    pct = (value - minValue) / (maxValue - minValue)
  end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end

  local r, g, b, label
  if type(U.TooltipHealthSnapshot) == "function" then
    r, g, b, label = U.TooltipHealthSnapshot()
  end
  if not Num(r) or not Num(g) or not Num(b) then
    r, g, b = M.color.health[1], M.color.health[2], M.color.health[3]
  end

  return {
    x = left - left0,
    y = bottom + height - top0,
    width = width,
    height = height,
    pct = pct,
    r = r, g = g, b = b,
    label = fade.ReadText(label, left0, top0),
  }
end

-- Plain-value snapshot of a visible tooltip, or nil. Unless `anyAlpha`, a
-- tooltip already part-way through a fade is refused.
function fade.Capture(name, anyAlpha)
  local tooltip = U.G(name)
  if not tooltip then return nil end

  if not anyAlpha then
    local alphaOk, alpha = pcall(tooltip.GetAlpha, tooltip)
    if alphaOk and Num(alpha) and alpha < fade.OPAQUE then return nil end
  end

  local left, bottom, width, height = fade.Rect(tooltip)
  if not left then return nil end
  local top = bottom + height

  local snap = {
    left = left, bottom = bottom, width = width, height = height,
    scale = fade.ScaleRatio(tooltip),
    rows = {},
  }

  local countOk, count = pcall(tooltip.NumLines, tooltip)
  if not countOk or not Num(count) then count = 0 end
  local i, s
  for i = 1, count do
    for s = 1, 2 do
      local row = fade.ReadText(U.G(name .. "Text" .. fade.SIDES[s] .. i),
                                left, top)
      if row then table.insert(snap.rows, row) end
    end
  end
  if table.getn(snap.rows) == 0 then return nil end

  if name == "GameTooltip" then snap.bar = fade.CaptureBar(left, top) end

  -- The live body encloses the health bar (modules/tooltip.lua, health-bar
  -- well), so the copy's body reaches PAD below it too. The top stays put, so
  -- every row and the bar keep their offsets from it.
  if snap.bar then
    local pad = type(U.TooltipBarWellPad) == "function" and
                U.TooltipBarWellPad() or 0
    local barBottom = top + snap.bar.y - snap.bar.height
    if barBottom - pad < snap.bottom then
      snap.bottom = barBottom - pad
      snap.height = top - snap.bottom
    end
  end
  return snap
end

-- Addon-owned copy -----------------------------------------------------------

function fade.Texture(ghost, layer, file)
  local ok, tex = pcall(ghost.CreateTexture, ghost, nil, layer)
  if not ok or not tex then return nil end
  pcall(tex.SetTexture, tex, file)
  pcall(tex.Hide, tex)
  return tex
end

function fade.Ghost(name)
  local ghost = fade.ghosts[name]
  if ghost ~= nil then return ghost or nil end

  local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent)
  if not ok or not frame then
    fade.ghosts[name] = false
    return nil
  end
  pcall(frame.SetFrameStrata, frame, "TOOLTIP")
  frame:Hide()

  -- Same body as the live tooltip: the theme rim when one is drawn, and the
  -- flat fill kept inside it.
  local inset = U.ApplyTooltipRim(frame) or 0
  U.CreateBackdrop(frame, {
    background = M.color.background,
    border = false,
    inset = inset,
  })

  frame.labels = {}
  frame.barBg = fade.Texture(frame, "BORDER", M.texture.plain)
  frame.barFill = fade.Texture(frame, "ARTWORK", M.texture.plain)
  if frame.barBg then
    U.SetColor(frame.barBg, M.color.healthBg[1], M.color.healthBg[2],
      M.color.healthBg[3], M.color.healthBg[4] or 1)
  end

  frame:SetScript("OnUpdate", function() fade.Step(frame) end)
  fade.ghosts[name] = frame
  return frame
end

function fade.Label(ghost, index)
  local label = ghost.labels[index]
  if label then return label end
  local ok
  ok, label = pcall(ghost.CreateFontString, ghost, nil, "OVERLAY",
                    "GameTooltipText")
  if not ok or not label then
    ok, label = pcall(ghost.CreateFontString, ghost, nil, "OVERLAY")
  end
  if not ok or not label then return nil end
  ghost.labels[index] = label
  return label
end

function fade.PaintText(ghost, label, row)
  if row.font then pcall(label.SetFont, label, row.font, row.size, row.flags) end
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", ghost, "TOPLEFT", row.x, row.y)
  pcall(label.SetSize, label, row.width, row.height)
  pcall(label.SetJustifyH, label, row.justify)
  -- A line is measured when SetText runs, and an unchanged string is not
  -- re-measured (behavior.json / tooltipline), so clear it after resizing.
  pcall(label.SetText, label, "")
  pcall(label.SetText, label, row.text)
  pcall(label.SetTextColor, label, row.r, row.g, row.b)
  U.SetTextShadow(label)
  pcall(label.Show, label)
end

function fade.PaintBar(ghost, bar)
  local bg, fill = ghost.barBg, ghost.barFill
  if not bar then
    if bg then pcall(bg.Hide, bg) end
    if fill then pcall(fill.Hide, fill) end
    return
  end
  if bg then
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", ghost, "TOPLEFT", bar.x, bar.y)
    pcall(bg.SetSize, bg, bar.width, bar.height)
    pcall(bg.Show, bg)
  end
  if fill then
    local width = bar.width * bar.pct
    if width < 0.1 then width = 0.1 end
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", ghost, "TOPLEFT", bar.x, bar.y)
    pcall(fill.SetSize, fill, width, bar.height)
    U.SetColor(fill, bar.r, bar.g, bar.b, 1)
    if bar.pct > 0 then pcall(fill.Show, fill) else pcall(fill.Hide, fill) end
  end
end

function fade.Paint(ghost, snap)
  pcall(ghost.SetScale, ghost, snap.scale)
  ghost:ClearAllPoints()
  ghost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", snap.left, snap.bottom)
  pcall(ghost.SetSize, ghost, snap.width, snap.height)

  local rows = snap.rows
  if snap.bar and snap.bar.label then
    rows = {}
    local i
    for i = 1, table.getn(snap.rows) do rows[i] = snap.rows[i] end
    table.insert(rows, snap.bar.label)
  end

  local used, i = 0, nil
  for i = 1, table.getn(rows) do
    local label = fade.Label(ghost, used + 1)
    if label then
      used = used + 1
      fade.PaintText(ghost, label, rows[i])
    end
  end
  ghost.used = used
  for i = used + 1, table.getn(ghost.labels) do
    pcall(ghost.labels[i].Hide, ghost.labels[i])
  end

  fade.PaintBar(ghost, snap.bar)
end

function fade.CoverShown()
  local cover = fade.cover
  if not cover or not cover.IsShown then return false end
  local ok, shown = pcall(cover.IsShown, cover)
  return ok and shown and true or false
end

-- `alpha` is the fade's own opacity (what a covering panel mirrors); the
-- copy draws at 0 while that panel is shown over it.
function fade.SetAlpha(ghost, alpha)
  ghost.alpha = alpha
  if ghost.covered and fade.CoverShown() then alpha = 0 end
  if ghost.drawn == alpha then return end
  ghost.drawn = alpha
  pcall(ghost.SetAlpha, ghost, alpha)
  local bg = M.color.background
  U.SetBackgroundColor(ghost, bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)

  local i
  for i = 1, ghost.used or 0 do
    pcall(ghost.labels[i].SetAlpha, ghost.labels[i], alpha)
  end
  local rim = ghost.uuiTooltipRim
  if type(rim) == "table" then
    for i = 1, table.getn(rim) do pcall(rim[i].SetAlpha, rim[i], alpha) end
  end
  if ghost.barBg then pcall(ghost.barBg.SetAlpha, ghost.barBg, alpha) end
  if ghost.barFill then pcall(ghost.barFill.SetAlpha, ghost.barFill, alpha) end
end

-- Opacity `elapsed` seconds into a fade: 1 through the hold, then a linear
-- ramp over FADE_OUT. Nil once it is over.
function fade.AlphaAt(elapsed, hold)
  if elapsed < hold then return 1 end
  local alpha = 1 - (elapsed - hold) / fade.FADE_OUT
  if alpha <= 0 then return nil end
  if alpha > 1 then return 1 end
  return alpha
end

function fade.Stop(ghost)
  ghost.running = false
  ghost.alpha = nil
  ghost:Hide()
end

function fade.Step(ghost)
  if not ghost.running then return end
  local alpha = fade.AlphaAt(GetTime() - ghost.fadeStart, ghost.hold)
  if not alpha then
    fade.Stop(ghost)
    return
  end
  fade.SetAlpha(ghost, alpha)
end

function fade.Cancel(name)
  local ghost = fade.ghosts[name]
  if ghost then fade.Stop(ghost) end
end

-- Copies `name` and starts its fade. `hold` (seconds at full opacity) and
-- `startedAt` (GetTime of the mouse-out) are for the world hand-off; a plain
-- Hide() fades at once. Returns true when a copy is on screen.
function fade.Start(name, anyAlpha, hold, startedAt)
  if U.PerfDisabled and U.PerfDisabled("tooltip") then return false end

  local snap = fade.Capture(name, anyAlpha)
  if not snap then
    fade.Cancel(name)
    return false
  end
  local ghost = fade.Ghost(name)
  if not ghost then return false end

  local now = GetTime()
  fade.Paint(ghost, snap)
  ghost.hold = Num(hold) or 0
  ghost.fadeStart = Num(startedAt) or now
  if ghost.fadeStart > now then ghost.fadeStart = now end
  -- Only the world copy can sit under UnrealQuest's panel. A plain Hide()
  -- also drops a stale registration, so an item copy is never held invisible.
  ghost.covered = anyAlpha and true or false
  if not anyAlpha then fade.cover = nil end
  ghost.drawn = nil
  ghost.running = true
  local alpha = fade.AlphaAt(now - ghost.fadeStart, ghost.hold)
  if not alpha then
    fade.Stop(ghost)
    return false
  end
  ghost.name = name
  fade.SetAlpha(ghost, alpha)
  ghost:Show()
  return true
end

-- modules/tooltip.lua, on mouse-out of the cursor-follow world tooltip. On
-- success the copy is on screen and GameTooltip has been hidden; on false
-- nothing was done and the caller hides the tooltip itself.
function U.FadeOutWorldTooltip(hold, startedAt)
  if not U.G("GameTooltip") then return false end
  if not fade.Start("GameTooltip", true, hold, startedAt) then return false end
  -- GameTooltip stays shown (transparent) until the client's own fade hides
  -- it; that hide must not start a second copy.
  fade.worldPending = true
  return true
end

-- modules/tooltip.lua, when something new is hovered while the world fade
-- runs. GameTooltip is still shown then, so its OnShow does not fire.
function U.CancelWorldTooltipFade()
  fade.worldPending = false
  fade.Cancel("GameTooltip")
end

-- Host API for UnrealQuest's creature tooltip. Called every frame while its
-- panel covers a fading GameTooltip: registers the panel, and returns the
-- world fade's opacity (1 through the hold), or nil when no world fade runs,
-- which is the panel's cue to close.
function U.WorldTooltipFadeAlpha(cover)
  fade.cover = cover
  local ghost = fade.ghosts.GameTooltip
  if not ghost or not ghost.running or not ghost.covered then return nil end
  return ghost.alpha
end

-- Runs `callback` before the tooltip's own OnHide chain, while its rows,
-- status bar and alpha are still exactly what was drawn. The callback is
-- isolated so it can never stop the native handler, and the 1.12 `this`
-- global is restored for that handler afterwards.
function fade.PreHookHide(frame, callback)
  if not frame or not frame.GetScript or not frame.SetScript then return false end
  local ok, previous = pcall(frame.GetScript, frame, "OnHide")
  if not ok then return false end
  return pcall(frame.SetScript, frame, "OnHide",
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local saved = this
      pcall(callback)
      this = saved
      if previous then previous(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
    end)
end

-- Frame:HookScript is verified here (wotlkports.v1: runs after the existing
-- handler, keeps `this`); U.PostHookScript is the fallback.
function fade.PostHookShow(frame, callback)
  if frame.HookScript and pcall(frame.HookScript, frame, "OnShow", callback) then
    return true
  end
  return U.PostHookScript(frame, "OnShow", callback)
end

function TF.OnEnable()
  local i
  for i = 1, table.getn(fade.SOURCES) do
    local name = fade.SOURCES[i]
    local tooltip = U.G(name)
    if tooltip then
      if not fade.PreHookHide(tooltip, function()
        -- The client's own fade ending under a running world copy: the copy
        -- carries on to its own end.
        if name == "GameTooltip" and fade.worldPending then
          fade.worldPending = false
          return
        end
        fade.Start(name)
      end) then
        U.Debug("tooltipfade: no OnHide hook on " .. name)
      end
      fade.PostHookShow(tooltip, function()
        if name == "GameTooltip" then fade.worldPending = false end
        fade.Cancel(name)
      end)
    end
  end
end
