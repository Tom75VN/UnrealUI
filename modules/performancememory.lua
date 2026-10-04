-- unrealUI :: modules/performancememory.lua
--
-- Estimated Lua memory in use per addon, for Settings > Performance.
--
-- The client has no per-addon memory API (GetAddOnMemoryUsage is nil, and
-- only the whole Lua heap is readable: knowledge.json /
-- perf.no_addon_cpu_profiling_or_subframe_clock). What an addon holds can
-- still be estimated by walking its data and adding up the size each object
-- would occupy in Lua 5.1 (this client reports _VERSION "Lua 5.1" and a
-- 64-bit process), which is what this file does on request:
--
--   * Roots are the globals. A global belongs to the addon whose folder name
--     prefixes its name ("UnrealUIDB" -> unrealUI), or, for a function, the
--     addon file it was written in (debug.getinfo source, via
--     U.PerfSourceOwner), or, for an unnamed table, the file of the first
--     function found inside it. Everything else is the client's and is never
--     entered, so a reference from an addon to UIParent or GameTooltip does
--     not pull the client's tables into that addon.
--   * From each addon root the walk follows table keys and values,
--     metatables, and every function's upvalues (debug.getupvalue), which is
--     where file-local data lives. An object reached twice counts once, for
--     the addon that reached it first.
--   * Sizes are Lua 5.1 64-bit estimates: a table header plus its array and
--     hash parts rounded up to powers of two, strings as their header plus
--     length, closures with their upvalue slots, and each distinct function
--     prototype by its line count. Frames and textures live in the engine,
--     not in Lua, and count as nothing.
--
-- So the figure is an estimate, not an allocator count; the page shows it
-- beside the real heap total so the attributed share is visible. Strings are
-- counted where they are values, not de-duplicated, and not counted as keys,
-- which keeps the walk's own bookkeeping small; keys are covered by the hash
-- slot size.
--
-- The walk runs a fixed number of entries per frame on the shared driver, so
-- a large database (UnrealQuest's) takes a few seconds with a light, steady
-- frame cost instead of one long freeze. Tables that change while it runs are
-- read as they are when reached; a key removed under the iterator ends that
-- table early rather than raising.
--
-- One table, few top-level locals (rules/unreal-ui.md, local budget).

local U = UnrealUI

local mw = {
  ENTRIES_PER_FRAME = 2500,
  -- Lua 5.1, 64-bit (lobject.h): Table 56, TValue 16, Node 40, TString 24
  -- plus the string and its terminator, LClosure 40 plus 8 per upvalue,
  -- CClosure 40. A prototype is estimated per source line.
  SIZE_TABLE = 56,
  SIZE_ARRAY_SLOT = 16,
  SIZE_NODE = 40,
  SIZE_STRING = 25,
  SIZE_CLOSURE = 40,
  SIZE_UPVALUE_SLOT = 8,
  SIZE_C_FUNCTION = 40,
  SIZE_PROTO_BASE = 120,
  SIZE_PROTO_LINE = 48,
  -- How many entries of an unnamed global table are looked at to find an
  -- owning function.
  PROBE_ENTRIES = 32,
}

-- Published for modules/performance.lua: { running, objects, owners
-- (owner -> bytes), attributed, heapKb, finishedAt, failed }.
mw.state = nil

-- type() on this client is a Lua wrapper that reports widgets as "table"
-- (lua.type_is_client_lua_wrapper); a widget then fails pairs/next. next() is
-- the reliable test for a real table.
function mw.IsTable(value)
  if type(value) ~= "table" then return false end
  local ok = pcall(next, value)
  return ok
end

function mw.Pow2(n)
  if n <= 0 then return 0 end
  local p = 1
  while p < n do p = p * 2 end
  return p
end

-- Loaded addon folder names, longest first, lower-cased for prefix tests.
function mw.AddonNames()
  local names = {}
  if type(GetNumAddOns) ~= "function" then return names end
  local count = tonumber(GetNumAddOns()) or 0
  local i
  for i = 1, count do
    local name = GetAddOnInfo(i)
    if name and IsAddOnLoaded(i) then
      table.insert(names, { name = name, lower = string.lower(name) })
    end
  end
  table.sort(names, function(a, b) return string.len(a.lower) > string.len(b.lower) end)
  return names
end

function mw.PrefixOwner(globalName, addons)
  local lower = string.lower(globalName)
  local i
  for i = 1, table.getn(addons) do
    local prefix = addons[i].lower
    if string.sub(lower, 1, string.len(prefix)) == prefix then return addons[i].name end
  end
  return nil
end

function mw.FunctionOwner(fn)
  local ok, info = pcall(debug.getinfo, fn, "S")
  if not ok or type(info) ~= "table" then return nil end
  return U.PerfSourceOwner(info.source)
end

function mw.TableOwner(t)
  local seen, key, value = 0, nil, nil
  while seen < mw.PROBE_ENTRIES do
    local ok
    ok, key, value = pcall(next, t, key)
    if not ok or key == nil then return nil end
    if type(value) == "function" then
      local owner = mw.FunctionOwner(value)
      if owner then return owner end
    end
    seen = seen + 1
  end
  return nil
end

-- Sorts every global into an addon root or a client object (never entered).
function mw.Roots(s)
  local addons = mw.AddonNames()
  local roots = {}
  local name, value
  for name, value in pairs(_G) do
    local kind = type(value)
    if kind == "table" or kind == "function" or kind == "userdata" then
      local owner = type(name) == "string" and mw.PrefixOwner(name, addons) or nil
      if not owner and kind == "function" then owner = mw.FunctionOwner(value) end
      if not owner and kind == "table" and mw.IsTable(value) then owner = mw.TableOwner(value) end
      if owner and not s.skip[value] then
        table.insert(roots, { value = value, owner = owner })
      elseif not owner then
        s.visited[value] = true
      end
    end
  end
  return roots
end

function mw.Add(s, owner, bytes)
  s.owners[owner] = (s.owners[owner] or 0) + bytes
end

-- Queues a value for the walk under `owner`, counting strings in place.
function mw.Push(s, owner, value)
  local kind = type(value)
  if kind == "string" then
    mw.Add(s, owner, mw.SIZE_STRING + string.len(value))
    return
  end
  if kind ~= "table" and kind ~= "function" then return end
  if s.visited[value] then return end
  s.visited[value] = true
  table.insert(s.stack, { value = value, owner = owner, kind = kind })
end

function mw.WalkFunction(s, item)
  local fn = item.value
  local ok, info = pcall(debug.getinfo, fn, "S")
  if ok and type(info) == "table" and info.what == "C" then
    mw.Add(s, item.owner, mw.SIZE_C_FUNCTION)
    return 1
  end
  local upvalues = 0
  local index = 1
  while true do
    local okUp, name, value = pcall(debug.getupvalue, fn, index)
    if not okUp or name == nil then break end
    upvalues = upvalues + 1
    mw.Push(s, item.owner, value)
    index = index + 1
  end
  mw.Add(s, item.owner, mw.SIZE_CLOSURE + mw.SIZE_UPVALUE_SLOT * upvalues)

  -- The prototype is shared by every closure made from it: count it once.
  if ok and type(info) == "table" and info.source then
    local byLine = s.protos[info.source]
    if not byLine then
      byLine = {}
      s.protos[info.source] = byLine
    end
    local first = info.linedefined or 0
    if not byLine[first] then
      byLine[first] = true
      local lines = math.max(1, (info.lastlinedefined or first) - first + 1)
      mw.Add(s, item.owner, mw.SIZE_PROTO_BASE + mw.SIZE_PROTO_LINE * lines)
    end
  end

  if type(getfenv) == "function" then
    local okEnv, env = pcall(getfenv, fn)
    if okEnv and env ~= _G then mw.Push(s, item.owner, env) end
  end
  return index
end

-- Walks up to `budget` entries of one table, resuming where it stopped.
-- Returns the entries used and whether the table is finished.
function mw.WalkTable(s, item, budget)
  local t = item.value
  if not item.started then
    item.started = true
    item.entries = 0
    if not mw.IsTable(t) then
      -- A widget: engine memory, not Lua.
      return 1, true
    end
    local okMeta, meta = pcall(getmetatable, t)
    if okMeta and type(meta) == "table" then mw.Push(s, item.owner, meta) end
  end
  local used = 0
  local key = item.key
  while used < budget do
    local ok, nextKey, value = pcall(next, t, key)
    if not ok or nextKey == nil then
      item.key = nil
      return used, true
    end
    key = nextKey
    item.entries = item.entries + 1
    if type(key) ~= "string" then mw.Push(s, item.owner, key) end
    mw.Push(s, item.owner, value)
    used = used + 1
  end
  item.key = key
  return used, false
end

function mw.FinishTable(s, item)
  local entries = item.entries or 0
  local array = 0
  if entries > 0 then
    local ok, n = pcall(table.getn, item.value)
    if ok and tonumber(n) then array = math.min(n, entries) end
  end
  local hash = entries - array
  mw.Add(s, item.owner, mw.SIZE_TABLE + mw.SIZE_ARRAY_SLOT * mw.Pow2(array) +
                        mw.SIZE_NODE * mw.Pow2(hash))
end

function mw.Step()
  local s = mw.state
  if not s or not s.running then
    U.UnregisterUpdate("performance.memory")
    return
  end
  local budget = mw.ENTRIES_PER_FRAME
  while budget > 0 do
    local count = table.getn(s.stack)
    if count == 0 then
      if s.rootIndex > table.getn(s.roots) then
        mw.Finish()
        return
      end
      local root = s.roots[s.rootIndex]
      s.rootIndex = s.rootIndex + 1
      mw.Push(s, root.owner, root.value)
    else
      local item = s.stack[count]
      if item.kind == "function" then
        table.remove(s.stack)
        budget = budget - mw.WalkFunction(s, item)
        s.objects = s.objects + 1
      else
        local used, done = mw.WalkTable(s, item, budget)
        budget = budget - math.max(1, used)
        if done then
          -- Children pushed while walking sit above this table; it is
          -- finished only once its own iteration has ended, which is now.
          local index
          for index = table.getn(s.stack), 1, -1 do
            if s.stack[index] == item then table.remove(s.stack, index) break end
          end
          mw.FinishTable(s, item)
          s.objects = s.objects + 1
        end
      end
    end
  end
  -- Progress for the page, a few times a second rather than every frame.
  local now = GetTime()
  if U.PerfPageChanged and (not s.paintedAt or now - s.paintedAt >= 0.25) then
    s.paintedAt = now
    U.PerfPageChanged()
  end
end

function mw.Finish()
  local s = mw.state
  U.UnregisterUpdate("performance.memory")
  if not s then return end
  s.running = false
  s.finishedAt = GetTime()
  s.heapKb = collectgarbage("count")
  local attributed, owner, bytes = 0, nil, nil
  for owner, bytes in pairs(s.owners) do attributed = attributed + bytes end
  s.attributed = attributed
  -- Drop the bookkeeping; only the result stays.
  s.visited, s.stack, s.roots, s.protos, s.skip = nil, nil, nil, nil, nil
  if s.onDone then pcall(s.onDone) end
  if U.PerfPageChanged then U.PerfPageChanged() end
end

function mw.Cancel()
  local s = mw.state
  U.UnregisterUpdate("performance.memory")
  if s and s.running then
    mw.state = nil
    if U.PerfPageChanged then U.PerfPageChanged() end
  end
end

function mw.Start(onDone)
  if mw.state and mw.state.running then return false end
  if type(debug) ~= "table" or type(debug.getinfo) ~= "function" or
     type(debug.getupvalue) ~= "function" or type(U.PerfSourceOwner) ~= "function" then
    mw.state = { failed = true }
    return false
  end

  local s = {
    running = true,
    objects = 0,
    owners = {},
    visited = {},
    skip = {},
    stack = {},
    protos = {},
    rootIndex = 1,
    onDone = onDone,
  }
  -- The walk's own bookkeeping and the profiler's scratch data are tools,
  -- not addon state.
  s.visited[s] = true
  s.visited[s.owners] = true
  s.visited[s.visited] = true
  s.visited[s.skip] = true
  s.visited[s.stack] = true
  s.visited[s.protos] = true
  s.visited[mw] = true
  s.visited[_G] = true
  local scratch = type(U.PerfScratchTables) == "function" and U.PerfScratchTables() or {}
  local i
  for i = 1, table.getn(scratch) do
    if scratch[i] then
      s.visited[scratch[i]] = true
      s.skip[scratch[i]] = true
    end
  end

  local ok, roots = pcall(mw.Roots, s)
  if not ok then
    mw.state = { failed = true }
    return false
  end
  s.roots = roots
  mw.state = s
  U.RegisterUpdate("performance.memory", 0, mw.Step)
  return true
end

U.PerfMemory = mw
