-- unrealUI :: core/statusbarfx.lua
--
-- Shared progress effects for UnrealUI-owned status bars. Bars opt in one at a
-- time, so themes can use the animation without changing the behaviour of
-- every status bar in the addon.
--
-- All active bars ride one on-demand entry in the shared update driver. This
-- client passes no arguments to OnUpdate, so elapsed is derived from GetTime
-- (knowledge.json / scripts.onupdate_elapsed_only_via_arg1,
-- BEHAVIOR_VERIFIED).

local U = UnrealUI
local M = U.media
local fx = {
  bars = {},
  running = false,
  lastTick = nil,
  updateId = "statusbarfx",
  getTime = U.G("GetTime"),
}

function fx.Config()
  return M.unitFrame.barFX
end

function fx.Now()
  if type(fx.getTime) ~= "function" then return nil end
  local ok, value = pcall(fx.getTime)
  if not ok or type(value) ~= "number" then return nil end
  return value
end

function fx.Fraction(bar, value)
  local minimum = tonumber(bar.uuiMin) or 0
  local maximum = tonumber(bar.uuiMax) or 0
  local range = maximum - minimum
  if range <= 0 then return 0 end

  local fraction = ((tonumber(value) or 0) - minimum) / range
  if fraction < 0 then return 0 end
  if fraction > 1 then return 1 end
  return fraction
end

function fx.Dimension(frame, method)
  if not frame or type(frame[method]) ~= "function" then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

function fx.CreateTexture(parent, layer, path)
  if not parent or type(parent.CreateTexture) ~= "function" then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil,
                            layer or "OVERLAY")
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  return texture
end

function fx.PlaceSpan(texture, bar, fromFraction, toFraction)
  local width = fx.Dimension(bar, "GetWidth")
  if width <= 0 or toFraction <= fromFraction then
    pcall(texture.Hide, texture)
    return false
  end

  texture:ClearAllPoints()
  texture:SetPoint("TOPLEFT", bar, "TOPLEFT", width * fromFraction, 0)
  texture:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",
                   -width * (1 - toFraction), 0)
  pcall(texture.Show, texture)
  return true
end

function fx.HideTransient(state)
  local i
  for i = 1, table.getn(state.cutouts) do
    state.cutouts[i].until_ = 0
    pcall(state.cutouts[i].texture.Hide, state.cutouts[i].texture)
  end
  state.pulseUntil = 0
  if state.pulse then pcall(state.pulse.Hide, state.pulse) end
end

function fx.Apply(state, bar, value)
  local ok, err = pcall(state.apply, bar, value)
  if ok then return true end
  U.Error("status-bar effect: " .. tostring(err))
  fx.bars[bar] = nil
  return false
end

function fx.StopIfIdle()
  local bar
  for bar in pairs(fx.bars) do
    if bar then return end
  end
  if not fx.running then return end
  fx.running = false
  fx.lastTick = nil
  U.UnregisterUpdate(fx.updateId)
end

function fx.EnsureRunning()
  if fx.running then return true end
  local now = fx.Now()
  if not now then return false end
  fx.running = true
  fx.lastTick = now
  U.RegisterUpdate(fx.updateId, 0, fx.Tick)
  return true
end

function fx.Tick()
  local cfg = fx.Config()
  local now = fx.Now()

  -- A missing clock degrades to the requested value and clears every overlay;
  -- the bar remains correct even though it cannot animate.
  if not now then
    local bar, state
    for bar, state in pairs(fx.bars) do
      fx.Apply(state, bar, state.target)
      fx.HideTransient(state)
      fx.bars[bar] = nil
    end
    fx.StopIfIdle()
    return
  end

  local elapsed = now - (fx.lastTick or now)
  fx.lastTick = now
  if elapsed < 0 then elapsed = 0 end

  local bar, state
  for bar, state in pairs(fx.bars) do
    local busy = false

    if state.display ~= state.target then
      local step = elapsed * (tonumber(cfg.approach) or 8)
      if step >= 1 then step = 1 end
      state.display = state.display + (state.target - state.display) * step

      local remaining = state.target - state.display
      if remaining < 0 then remaining = -remaining end
      if remaining <= state.span * (tonumber(cfg.snapBelow) or 0) then
        state.display = state.target
      end

      if fx.Apply(state, bar, state.display) then
        busy = state.display ~= state.target
      end
    end

    local i
    for i = 1, table.getn(state.cutouts) do
      local entry = state.cutouts[i]
      if entry.until_ > 0 then
        local left = entry.until_ - now
        if left <= 0 then
          entry.until_ = 0
          pcall(entry.texture.Hide, entry.texture)
        else
          local progress = left / (tonumber(cfg.cutoutDuration) or 0.3)
          U.SetColor(entry.texture, cfg.cutoutColor[1], cfg.cutoutColor[2],
                     cfg.cutoutColor[3],
                     (tonumber(cfg.cutoutAlpha) or 0.85) * progress)
          busy = true
        end
      end
    end

    if state.pulse and state.pulseUntil > 0 then
      local left = state.pulseUntil - now
      if left <= 0 then
        state.pulseUntil = 0
        pcall(state.pulse.Hide, state.pulse)
      else
        local progress = left / (tonumber(cfg.pulseDuration) or 0.3)
        U.SetColor(state.pulse, 1, 1, 1,
                   (tonumber(cfg.pulseAlpha) or 0.3) * progress)
        busy = true
      end
    end

    if not busy then fx.bars[bar] = nil end
  end

  fx.StopIfIdle()
end

function fx.OnValue(bar, value)
  local state = bar.uuiStatusBarFX
  if not state then return end

  value = tonumber(value) or 0
  local minimum = tonumber(bar.uuiMin) or 0
  local maximum = tonumber(bar.uuiMax) or 0
  local rangeChanged = minimum ~= state.minimum or maximum ~= state.maximum
  local fraction = fx.Fraction(bar, value)

  -- A new range represents a new bar contract (most often a new target), so it
  -- snaps instead of animating from stale geometry.
  if rangeChanged then
    state.minimum, state.maximum = minimum, maximum
    state.display, state.target = value, value
    state.targetFraction = fraction
    state.span = maximum - minimum
    if state.span <= 0 then state.span = 1 end
    fx.HideTransient(state)
    fx.bars[bar] = nil
    fx.Apply(state, bar, value)
    fx.StopIfIdle()
    return
  end

  -- Unit-frame refreshes compare against the displayed interpolated value, so
  -- they may offer the same real target again while a slide is still active.
  -- Ignore it here: it is not another change and must not restart the pulse.
  if state.target == value then return end

  local cfg = fx.Config()
  local previous = state.targetFraction
  state.target = value
  state.targetFraction = fraction
  state.span = maximum - minimum
  if state.span <= 0 then state.span = 1 end

  local now = fx.Now()
  if not now then
    state.display = value
    fx.HideTransient(state)
    fx.Apply(state, bar, value)
    return
  end

  if previous and fraction < previous then
    local pool = state.cutouts
    local count = table.getn(pool)
    if count > 0 then
      state.cutoutIndex = math.mod(state.cutoutIndex, count) + 1
      local entry = pool[state.cutoutIndex]
      -- A bar can switch between flat and shaded fills at runtime. Refresh the
      -- recycled texture from the bar's remembered material before each use.
      pcall(entry.texture.SetTexture, entry.texture, bar.uuiTexturePath)
      if fx.PlaceSpan(entry.texture, bar, fraction, previous) then
        entry.until_ = now + (tonumber(cfg.cutoutDuration) or 0.3)
      end
    end
  end

  if state.pulse and fraction > 0 then
    if fx.PlaceSpan(state.pulse, bar, 0, fraction) then
      state.pulseUntil = now + (tonumber(cfg.pulseDuration) or 0.3)
    end
  elseif state.pulse then
    state.pulseUntil = 0
    pcall(state.pulse.Hide, state.pulse)
  end

  fx.bars[bar] = state
  if not fx.EnsureRunning() then
    state.display = value
    fx.HideTransient(state)
    fx.Apply(state, bar, value)
    fx.bars[bar] = nil
  end
end

-- Opts one UnrealUI status bar into the shared effects. Allocation is bounded:
-- the wrapper, one pulse texture and the fixed cutout pool are created once.
function U.AttachStatusBarFX(bar)
  if not bar or bar.uuiStatusBarFX or not bar.uuiFillTexture then return false end
  if type(bar.SetValue) ~= "function" then return false end

  local cfg = fx.Config()
  local current = tonumber(bar.uuiValue) or 0
  local state = {
    apply = bar.SetValue,
    display = current,
    target = current,
    targetFraction = fx.Fraction(bar, current),
    minimum = tonumber(bar.uuiMin) or 0,
    maximum = tonumber(bar.uuiMax) or 0,
    span = (tonumber(bar.uuiMax) or 0) - (tonumber(bar.uuiMin) or 0),
    cutouts = {},
    cutoutIndex = 0,
    pulseUntil = 0,
  }
  if state.span <= 0 then state.span = 1 end

  local i
  for i = 1, (tonumber(cfg.cutoutPool) or 3) do
    local texture = fx.CreateTexture(bar, "OVERLAY", bar.uuiTexturePath)
    if texture then
      pcall(texture.Hide, texture)
      table.insert(state.cutouts, { texture = texture, until_ = 0 })
    end
  end

  state.pulse = fx.CreateTexture(bar, "OVERLAY", M.texture.plain)
  if state.pulse then
    pcall(state.pulse.Hide, state.pulse)
    if type(state.pulse.SetBlendMode) == "function" then
      pcall(state.pulse.SetBlendMode, state.pulse, "ADD")
    end
  end

  bar.uuiStatusBarFX = state
  bar.SetValue = function(self, nextValue)
    fx.OnValue(self, nextValue)
  end
  return true
end

-- Starts a new logical progress sequence at an exact value. Cast bars reuse
-- one widget for consecutive spells, so a new cast must not animate backwards
-- from the previous cast merely because both spells have the same duration.
function U.ResetStatusBarFX(bar, value)
  local state = bar and bar.uuiStatusBarFX
  if not state then return false end

  value = tonumber(value) or tonumber(bar.uuiValue) or 0
  state.minimum = tonumber(bar.uuiMin) or 0
  state.maximum = tonumber(bar.uuiMax) or 0
  state.span = state.maximum - state.minimum
  if state.span <= 0 then state.span = 1 end
  state.display, state.target = value, value
  state.targetFraction = fx.Fraction(bar, value)

  fx.HideTransient(state)
  fx.bars[bar] = nil
  local applied = fx.Apply(state, bar, value)
  fx.StopIfIdle()
  return applied
end
