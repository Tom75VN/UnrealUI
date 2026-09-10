-- unrealUI :: core/easing.lua
--
-- Small shared value animations for UnrealUI-owned surfaces. The cubic curves
-- match UnrealQuest's map-marker emphasis: expansion uses a quick ease-out,
-- while contraction uses the softer ease-in/out curve.
--
-- Animations run through UnrealUI's single shared updater. This client does
-- not pass a reliable elapsed value to OnUpdate callbacks, so progress is
-- measured against GetTime (knowledge.json /
-- scripts.onupdate_elapsed_only_via_arg1, BEHAVIOR_VERIFIED).

local U = UnrealUI
local active = {}
local getTime = U.G("GetTime")

local function Now()
  if type(getTime) ~= "function" then return nil end
  local ok, value = pcall(getTime)
  if not ok or type(value) ~= "number" then return nil end
  return value
end

function U.ClampUnit(value)
  value = tonumber(value) or 0
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

function U.EaseOutCubic(progress)
  local inverse = 1 - U.ClampUnit(progress)
  return 1 - inverse * inverse * inverse
end

function U.EaseInOutCubic(progress)
  progress = U.ClampUnit(progress)
  if progress < 0.5 then
    return 4 * progress * progress * progress
  end
  local inverse = -2 * progress + 2
  return 1 - inverse * inverse * inverse / 2
end

function U.StopEasing(id)
  if type(id) ~= "string" then return false end
  active[id] = nil
  U.UnregisterUpdate("easing." .. id)
  return true
end

-- options: from, to, duration, ease(progress), onUpdate(value), onComplete()
function U.StartEasing(id, options)
  if type(id) ~= "string" or type(options) ~= "table" or
     type(options.onUpdate) ~= "function" then return false end

  U.StopEasing(id)

  local from = tonumber(options.from) or 0
  local target = tonumber(options.to) or 0
  local duration = tonumber(options.duration) or 0
  local ease = type(options.ease) == "function" and
               options.ease or U.EaseInOutCubic
  local startedAt = Now()

  local function Apply(value)
    local ok, err = pcall(options.onUpdate, value)
    if ok then return true end
    U.Error("easing " .. id .. ": " .. tostring(err))
    U.StopEasing(id)
    return false
  end

  local function Complete()
    U.StopEasing(id)
    if type(options.onComplete) ~= "function" then return end
    local ok, err = pcall(options.onComplete)
    if not ok then U.Error("easing completion " .. id .. ": " .. tostring(err)) end
  end

  if duration <= 0 or from == target or not startedAt then
    if Apply(target) then Complete() end
    return true
  end

  active[id] = { startedAt = startedAt }
  if not Apply(from) then return false end

  U.RegisterUpdate("easing." .. id, 0, function()
    local state = active[id]
    if not state then
      U.UnregisterUpdate("easing." .. id)
      return
    end

    local now = Now()
    if not now then
      if Apply(target) then Complete() end
      return
    end

    local progress = U.ClampUnit((now - state.startedAt) / duration)
    local value = from + (target - from) * ease(progress)
    if not Apply(value) then return end
    if progress >= 1 then Complete() end
  end)
  return true
end
