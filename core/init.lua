-- unrealUI :: core/init.lua
--
-- Namespace, module registry, event dispatch and the shared OnUpdate driver.
--
-- This file must stay dependency-free: it is the first entry in the .toc and
-- every other core file assumes UnrealUI already exists when it loads.

UnrealUI = {}
local U = UnrealUI

U.name      = "unrealUI"
U.version   = "0.2.0"
U.modules   = {}       -- name -> module table
U.moduleOrder = {}     -- load/enable order, registration order
U.ready     = false    -- set once PLAYER_LOGIN work has run

-- ---------------------------------------------------------------------------
-- Globals access
--
-- Vanilla exposes getglobal(); newer Lua exposes _G. Resolve once instead of
-- assuming either is present in this runtime.
-- ---------------------------------------------------------------------------
local _getglobal = getglobal
if not _getglobal then
  _getglobal = function(name)
    if _G then return _G[name] end
    return nil
  end
end

function U.G(name)
  if type(name) ~= "string" then return nil end
  local ok, value = pcall(_getglobal, name)
  if ok then return value end
  return nil
end

-- Writing a global has the same ambiguity: `_G` is optional here, so the write
-- goes through setglobal when the client provides it. Callers that depend on
-- the write landing must read it back with U.G rather than trust the pcall,
-- which only reports that the call itself did not error.
local _setglobal = setglobal
if not _setglobal then
  _setglobal = function(name, value)
    if _G then _G[name] = value end
  end
end

function U.SetG(name, value)
  if type(name) ~= "string" then return false end
  return pcall(_setglobal, name, value)
end

-- ---------------------------------------------------------------------------
-- Output / debug
-- ---------------------------------------------------------------------------
local function Output(text)
  local frame = U.G("DEFAULT_CHAT_FRAME")
  if frame and frame.AddMessage then
    pcall(frame.AddMessage, frame, text)
  end
end

function U.Print(msg)
  Output("|cfff5ae0aunreal|cffffffffUI|r: " .. tostring(msg))
end

function U.Error(msg)
  Output("|cfff5ae0aunreal|cffffffffUI|r |cffff5555error|r: " .. tostring(msg))
end

-- Debug output is opt-in and survives config not being loaded yet.
function U.Debug(msg)
  if not U.db or not U.db.debug then return end
  Output("|cfff5ae0aunreal|cffffffffUI|r |cff888888debug|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Module registry
--
-- Modules are plain tables with optional OnInit (ADDON_LOADED, config ready)
-- and OnEnable (PLAYER_LOGIN, world objects ready) methods. Keeping the two
-- phases apart means a module never has to guess whether SavedVariables or the
-- stock UI already exist.
-- ---------------------------------------------------------------------------
function U.RegisterModule(name, module)
  if type(name) ~= "string" then
    U.Error("RegisterModule requires a name")
    return nil
  end
  if U.modules[name] then
    U.Error("module already registered: " .. name)
    return U.modules[name]
  end

  module = module or {}
  module.moduleName = name
  U.modules[name] = module
  table.insert(U.moduleOrder, name)
  return module
end

function U.GetModule(name)
  return U.modules[name]
end

local function RunModulePhase(phase)
  local i
  for i = 1, table.getn(U.moduleOrder) do
    local name = U.moduleOrder[i]
    local module = U.modules[name]
    if module and type(module[phase]) == "function" then
      local ok, err = pcall(module[phase], module)
      if not ok then
        U.Error(name .. "." .. phase .. ": " .. tostring(err))
      else
        U.Debug(name .. "." .. phase .. " ok")
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Event dispatch
--
-- knowledge.json / scripts.handler_arguments_direct: this client does not
-- consistently populate the legacy `this` / `event` / `arg1` globals, and may
-- instead pass handler arguments directly. The shape is not guaranteed, so
-- resolve all three observed forms rather than committing to one:
--
--   handler(event, a1, ...)        -- direct, event first
--   handler(self, event, a1, ...)  -- direct, self first
--   handler()                      -- legacy globals
--
-- Every unrealUI event consumer goes through here so the ambiguity is handled
-- once instead of in each module.
-- ---------------------------------------------------------------------------
local listeners = {}   -- event -> array of callbacks
local dispatcher = CreateFrame("Frame", "UnrealUIDispatcher", UIParent)

-- Records which handler shape actually arrived, so /uui debug can report the
-- measured behaviour instead of restating the assumption.
U.handlerShape = "unknown"

local function ResolveEvent(a, b)
  if type(a) == "string" then
    return a, 1
  end
  if type(b) == "string" then
    return b, 2
  end
  return U.G("event"), 0
end

dispatcher:SetScript("OnEvent", function(a, b, c, d, e, f, g, h, i, j)
  local event, shape = ResolveEvent(a, b)
  if not event then return end

  local a1, a2, a3, a4, a5, a6, a7, a8
  if shape == 1 then
    U.handlerShape = "direct-event-first"
    a1, a2, a3, a4, a5, a6, a7, a8 = b, c, d, e, f, g, h, i
  elseif shape == 2 then
    U.handlerShape = "direct-self-first"
    a1, a2, a3, a4, a5, a6, a7, a8 = c, d, e, f, g, h, i, j
  else
    U.handlerShape = "legacy-globals"
    a1, a2, a3, a4 = U.G("arg1"), U.G("arg2"), U.G("arg3"), U.G("arg4")
    a5, a6, a7, a8 = U.G("arg5"), U.G("arg6"), U.G("arg7"), U.G("arg8")
  end

  -- core/perf.lua's frame-time recorder. Off by default: one boolean read per
  -- dispatched event when nobody is measuring.
  if U.perfActive then U.PerfEvent(event) end

  local list = listeners[event]
  if not list then return end

  -- A handler is allowed to unregister itself, which shrinks `list` while this
  -- loop is still running against the length it started with.
  local n
  for n = 1, table.getn(list) do
    local callback = list[n]
    if callback then
      local ok, err = pcall(callback, event, a1, a2, a3, a4, a5, a6, a7, a8)
      if not ok then
        U.Error(event .. " handler: " .. tostring(err))
      end
    end
  end
end)

-- Registering an event only proves the client accepted the call, never that the
-- event fires or carries the expected arguments. Consumers must tolerate both.
function U.RegisterEvent(event, callback)
  if type(event) ~= "string" or type(callback) ~= "function" then return end

  if not listeners[event] then
    listeners[event] = {}
    local ok, err = pcall(dispatcher.RegisterEvent, dispatcher, event)
    if not ok then
      listeners[event] = nil
      U.Error("RegisterEvent(" .. event .. "): " .. tostring(err))
      return
    end
  end

  table.insert(listeners[event], callback)
end

function U.UnregisterEvent(event, callback)
  local list = listeners[event]
  if not list then return end

  local n
  for n = table.getn(list), 1, -1 do
    if list[n] == callback then table.remove(list, n) end
  end

  if table.getn(list) == 0 then
    listeners[event] = nil
    pcall(dispatcher.UnregisterEvent, dispatcher, event)
  end
end

-- ---------------------------------------------------------------------------
-- Shared OnUpdate driver
--
-- knowledge.json / scripts.child_onupdate_unreliable: freshly created child
-- frames do not reliably receive OnUpdate ticks. unrealUI therefore runs one
-- driver, created with the addon at load time, and gives modules throttled
-- callbacks on it instead of each module attaching its own OnUpdate to a frame
-- it just built. Modules must still initialise visible state synchronously and
-- treat OnUpdate purely as a refresh path.
-- ---------------------------------------------------------------------------
local updaters = {}
U.ticks = 0

-- knowledge.json / scripts.onupdate_elapsed_only_via_arg1: this client passes
-- NO arguments to an OnUpdate handler at all -- a focused probe measured
-- a=nil, b=nil on 804 of 804 consecutive ticks, with the frame delta available
-- only through the legacy global arg1. arg1 is also the shared event-argument
-- global that every OnEvent dispatch overwrites, so resolving elapsed from it
-- couples every throttled refresh in the addon to whatever the last event left
-- behind. A non-numeric arg1 (any CHAT_MSG_* payload is a string) resolves to
-- 0, and because the accumulator only ever advances by that value, a run of
-- those stalls every interval > 0 updater indefinitely -- the action bar range
-- tint, the cooldown countdown and the slot sweep all freeze while interval 0
-- updaters keep running. A stale numeric arg1 is just as wrong in the other
-- direction (ACTIONBAR_SLOT_CHANGED delivered 12 in a probe run).
--
-- GetTime is the client's own monotonic clock (api.json / core.time.v1) and is
-- already what the cooldown maths in modules/actionbar.lua is measured against;
-- the same probe read it 804 times across 6.007s and its deltas summed to the
-- wall time exactly. The driver therefore derives elapsed from successive
-- GetTime readings and does not consult arg1 at all. The argument and arg1
-- paths are kept only as fallbacks for a client that supplies them while
-- lacking GetTime.
local _GetTime = GetTime
local lastTickAt

local function ResolveElapsed(a, b)
  if type(_GetTime) == "function" then
    local ok, now = pcall(_GetTime)
    if ok and type(now) == "number" then
      local delta = 0
      if lastTickAt then delta = now - lastTickAt end
      lastTickAt = now
      -- The clock restarts across a reload and the client can hitch, so a
      -- backwards step contributes nothing and a long stall is capped rather
      -- than dumped into every accumulator at once.
      if delta < 0 then delta = 0 end
      if delta > 1 then delta = 1 end
      return delta
    end
  end
  if type(a) == "number" then return a end
  if type(b) == "number" then return b end
  local legacy = U.G("arg1")
  if type(legacy) == "number" then return legacy end
  return 0
end

dispatcher:SetScript("OnUpdate", function(a, b)
  local elapsed = ResolveElapsed(a, b)
  U.ticks = U.ticks + 1

  -- This delta is the only frame-time measurement this client can produce
  -- (debugprofilestop is a documented no-op here), so the recorder reads it
  -- before any updater has had a chance to add to the next one.
  if U.perfActive then U.PerfTick(elapsed) end

  -- A callback may unregister itself (the enable fallback below does exactly
  -- that), so entries can disappear mid-loop.
  local n
  for n = 1, table.getn(updaters) do
    local entry = updaters[n]
    if entry then
      entry.elapsed = entry.elapsed + elapsed
      if entry.elapsed >= entry.interval then
        -- Carry the overshoot instead of zeroing. Zeroing restarted every
        -- accumulator from the same point each time it fired, which is what
        -- locked the equal-interval consumers together: unitframes.refresh,
        -- auras.refresh and actionbar.state are all 0.2s and were all
        -- registered inside the same OnEnable frame, so their accumulators
        -- crossed the threshold on the same tick and stayed in phase for the
        -- rest of the session. Every fifth of a second one render tick
        -- inherited the complete unit-frame read, both debuff rows and the
        -- whole action bar state sweep while the four ticks around it did
        -- nothing. Subtracting keeps the offsets RegisterUpdate assigns below.
        if entry.interval > 0 then
          entry.elapsed = entry.elapsed - entry.interval
          -- After a load stall the accumulator can be several intervals deep.
          -- Firing once and dropping the backlog is right for every consumer
          -- here -- they all recompute current state rather than integrate --
          -- and it stops a hitch from being followed by a catch-up burst.
          if entry.elapsed >= entry.interval then entry.elapsed = 0 end
        else
          entry.elapsed = 0
        end
        local ok, err = pcall(entry.callback, entry.interval)
        if not ok then
          U.Error("updater " .. tostring(entry.id) .. ": " .. tostring(err))
        end
      end
    end
  end
end)

-- Spreads registrations across their own interval so two consumers asking for
-- the same rate do not land on the same render tick. The multiplier is the
-- fractional golden ratio, which is the standard low-discrepancy choice: any
-- number of registrations stays about as evenly spread as it can be, without
-- needing to know how many there will be. Deterministic, so the layout is the
-- same every session and a measurement stays reproducible.
local registrationCount = 0

local function NextPhase(interval)
  registrationCount = registrationCount + 1
  if interval <= 0 then return 0 end
  return interval * math.mod(registrationCount * 0.6180339887, 1)
end

-- interval is a throttle in seconds; 0 means every tick.
function U.RegisterUpdate(id, interval, callback)
  if type(callback) ~= "function" then return end
  U.UnregisterUpdate(id)
  interval = tonumber(interval) or 0
  table.insert(updaters, {
    id = id,
    interval = interval,
    -- Starting the accumulator part-way through the interval both offsets the
    -- first fire and, because the tick loop now carries the overshoot rather
    -- than zeroing, keeps that offset for every fire after it.
    elapsed = NextPhase(interval),
    callback = callback,
  })
end

function U.UnregisterUpdate(id)
  local n
  for n = table.getn(updaters), 1, -1 do
    if updaters[n].id == id then table.remove(updaters, n) end
  end
end

-- Runs `fn` once on the next shared-driver tick instead of inline, and drops
-- itself again. Post-hooked native handlers run unrealUI's callback
-- synchronously, inside a native call chain that has not necessarily finished
-- mutating the objects the callback reads or touches. Two separate cases need
-- that gap: USER_CONFIRMED_INGAME, the client crashed natively when Remove
-- Friend re-styled the row list from inside FriendsList_Update; and a native
-- handler that updates its own widget state after its script returns is still
-- reporting the pre-click state to an inline hook. A later call with the same
-- id replaces the pending one rather than queueing a second.
function U.DeferOnce(id, fn)
  if type(fn) ~= "function" then return end
  U.RegisterUpdate(id, 0, function()
    U.UnregisterUpdate(id)
    local ok, err = pcall(fn)
    if not ok then U.Error("deferred " .. tostring(id) .. ": " .. tostring(err)) end
  end)
end

-- ---------------------------------------------------------------------------
-- Bootstrap
--
-- ADDON_LOADED, PLAYER_LOGIN and PLAYER_ENTERING_WORLD are all only
-- EXISTENCE_ONLY in the compact evidence (events.json) -- RegisterEvent was
-- accepted, but none of them appear in the observed-event set, so none can be
-- treated as a guaranteed trigger on this client.
--
-- Both phases are therefore idempotent and reachable from any of the events or
-- from the shared OnUpdate driver. Whichever arrives first wins; the rest are
-- no-ops. `initialised` guards the config load specifically, because running it
-- twice would re-validate a table modules already hold references into.
-- ---------------------------------------------------------------------------
local initialised = false

local function Initialise()
  if initialised then return end
  initialised = true

  U.LoadConfig()       -- core/config.lua
  U.LoadThemeStyle()   -- core/theme.lua; must precede module-owned UI creation
  RunModulePhase("OnInit")
  U.Debug("config loaded, modules initialised")
end

local function Enable()
  Initialise()
  if U.ready then return end
  U.ready = true

  RunModulePhase("OnEnable")
  U.Debug("modules enabled (handler shape: " .. U.handlerShape .. ")")
end

-- Folder-name casing is not worth trusting; compare case-insensitively.
U.RegisterEvent("ADDON_LOADED", function(event, addon)
  if type(addon) == "string" and string.lower(addon) == "unrealui" then
    Initialise()
  end
end)

U.RegisterEvent("PLAYER_LOGIN", Enable)
U.RegisterEvent("PLAYER_ENTERING_WORLD", Enable)

U.RegisterUpdate("core.bootstrap-fallback", 1, function()
  Enable()
  U.UnregisterUpdate("core.bootstrap-fallback")
end)
