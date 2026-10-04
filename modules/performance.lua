-- unrealUI :: modules/performance.lua
--
-- Settings > Unreal UI > Performance: per-addon CPU and memory, live.
--
-- What this client allows (all measured, 2026-10-04):
--   * No per-addon API: GetAddOnCPUUsage, GetAddOnMemoryUsage and the rest are
--     nil, and no clock advances inside a frame -- GetTime and
--     debugprofilestop stayed put across 63 ms of Lua in one frame
--     (knowledge.json / perf.no_addon_cpu_profiling_or_subframe_clock). So the
--     KLHPerformanceMonitor approach of timing each OnEvent/OnUpdate with
--     GetTime would read 0 ms for every handler here.
--   * The Lua 5.1 debug library is exposed: a count hook fires every N VM
--     instructions in exact proportion to the work, and debug.getinfo names
--     the running function's file (lua.debug_library_count_hook_and_getinfo).
--     One hook that records whose file is running is a sampling profiler with
--     no frame scan and no script wrapping, covering unnamed frames too; its
--     frame cost measured below noise (perf.addon_instruction_share_sampling).
--   * collectgarbage("count") reads the live Lua heap.
--
-- So CPU here is each addon's share of the Lua instructions the client runs,
-- and memory is the Lua heap growth seen between consecutive samples, charged
-- to the addon running at the sample -- KLHPerformanceMonitor's gcinfo-delta
-- idea applied per sample instead of per handler, with its rule that a
-- negative difference (a collection ran) counts as nothing. Its data model is
-- kept as well: 5-second periods, the last six as the "recent" window, and
-- running totals since recording started.
--
-- Neither figure includes drawing. On this client an addon's frame cost
-- tracks the frames and textures it puts on screen more than its Lua
-- (actionbars.frame_cost_scales_with_regions), so the page says so.
--
-- Two client details shape the hook:
--   * type, strlen, strfind, ipairs, wipe, print ... are Lua functions in a
--     client chunk named "_g" (lua.type_is_client_lua_wrapper); type() alone
--     was 16% of idle Lua. A sample landing in such a chunk, or in a C
--     function, is charged to the addon that called it.
--   * An error raised inside a hook surfaces in whatever code was running, so
--     the hook does nothing that can raise.
--
-- One table, few top-level locals (rules/unreal-ui.md, local budget).

local U = UnrealUI
local M = U.media

local PF = U.RegisterModule("performance")

local pf = {
  HOOK_EVERY = 1000,
  BUCKET_SECONDS = 5,
  RECENT_BUCKETS = 6,
  REFRESH_SECONDS = 1,
  -- The page is laid out to the width it can actually show (pf.VisibleWidth):
  -- both 496 and 440 ran past the right edge of the Game Settings page in
  -- game (2026-10-04), and that edge moves with the window and UI scale.
  -- PAGE_WIDTH is only the starting value until the first measurement.
  PAGE_WIDTH = 440,
  MIN_WIDTH = 300,
  MAX_WIDTH = 496,
  EDGE_MARGIN = 10,
  ROW_HEIGHT = 18,
  ROW_GAP = 1,
  -- List columns in order. Fixed columns keep their width; the two "flex"
  -- columns share what is left by weight. Left-aligned cells are trimmed with
  -- an ellipsis (U.FitLabelText) rather than wrapped.
  COLUMNS = {
    { key = "name",    flex = 1,    justify = "LEFT" },
    { key = "cpu",     width = 46,  justify = "RIGHT" },
    { key = "instr",   width = 50,  justify = "RIGHT" },
    { key = "memory",  width = 64,  justify = "RIGHT" },
    { key = "inuse",   width = 62,  justify = "RIGHT" },
    { key = "hottest", flex = 1,    justify = "LEFT" },
  },
  COLUMN_GAP = 4,
  -- Pseudo owners for code that is not in an addon folder.
  CLIENT_UI = "@client-ui",
  CLIENT_OTHER = "@client-other",
  PROFILER = "@profiler",

  recording = false,
  window = "recent",   -- "recent" | "total"
  sortBy = "cpu",      -- "cpu" | "memory" | "inuse"
  status = nil,        -- nil | "busy" | "unsupported"
}

-- ---------------------------------------------------------------------------
-- Attribution
-- ---------------------------------------------------------------------------

-- source -> owner key, or false when the sample should go to the caller.
pf.ownerCache = {}

function pf.Owner(source)
  local owner = pf.ownerCache[source]
  if owner ~= nil then return owner end
  -- performance.lua and performancememory.lua: the measuring tools themselves.
  if string.find(source, "unrealUI/modules/performance", 1, true) then
    owner = pf.PROFILER
  else
    local _, _, addon = string.find(source, "AddOns[/\\]([^/\\]+)[/\\]")
    if addon then
      owner = addon
    elseif string.find(source, "FrameXML", 1, true) or
           string.find(source, "GlobalXML", 1, true) or
           string.find(source, "[On", 1, true) then
      -- FrameXML files and inline XML scripts ("UIParent[OnUpdate](0.40)").
      owner = pf.CLIENT_UI
    else
      -- "=[C]", the "_g" helper chunk, "Script": charge whoever called it.
      owner = false
    end
  end
  pf.ownerCache[source] = owner
  return owner
end

-- Shared with modules/performancememory.lua: which addon folder a function's
-- source belongs to. Returns the folder name, one of the pseudo owners above,
-- or nil for client code with no addon behind it.
function U.PerfSourceOwner(source)
  if type(source) ~= "string" then return nil end
  local owner = pf.Owner(source)
  if owner == false then return nil end
  return owner
end

-- The profiler's own scratch tables, so the memory walk does not count them.
function U.PerfScratchTables()
  return { pf, pf.ownerCache, pf.funcs, pf.names, pf.history, pf.total, pf.cur,
           pf.page }
end

-- The hook. Level 2 is the function running when it fired, level 3 its
-- caller. The heap is read first, so this call's own getinfo tables land in
-- the next sample's difference; pf.selfKb (measured at start) is taken off.
function pf.Hook()
  local cur = pf.cur
  if not cur then return end
  local kb = collectgarbage("count")
  local info = debug.getinfo(2, "Sn")
  if not info then return end

  local source = info.source or "?"
  local line = info.linedefined or 0
  local name = info.name
  local owner = pf.ownerCache[source]
  if owner == nil then owner = pf.Owner(source) end
  if owner == false then
    local caller = debug.getinfo(3, "Sn")
    local callerSource = caller and caller.source
    local callerOwner = callerSource and pf.ownerCache[callerSource]
    if callerSource and callerOwner == nil then callerOwner = pf.Owner(callerSource) end
    if callerOwner then
      owner = callerOwner
      source = callerSource
      line = caller.linedefined or 0
      name = caller.name
    else
      owner = pf.CLIENT_OTHER
    end
  end

  cur.cpu[owner] = (cur.cpu[owner] or 0) + 1
  cur.samples = cur.samples + 1

  local delta = kb - pf.lastKb - pf.selfKb
  pf.lastKb = kb
  if delta > 0 then
    cur.mem[owner] = (cur.mem[owner] or 0) + delta
    cur.memTotal = cur.memTotal + delta
  end

  local byLine = pf.funcs[source]
  if not byLine then
    byLine = {}
    pf.funcs[source] = byLine
    pf.names[source] = {}
  end
  byLine[line] = (byLine[line] or 0) + 1
  if name then
    local names = pf.names[source]
    if not names[line] then names[line] = name end
  end
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

function pf.HasDebug()
  return type(debug) == "table" and type(debug.sethook) == "function" and
         type(debug.gethook) == "function" and type(debug.getinfo) == "function"
end

-- KB one sample's getinfo calls allocate, so the hook can discount itself.
function pf.MeasureSelfKb()
  local before = collectgarbage("count")
  local i
  for i = 1, 200 do
    debug.getinfo(1, "Sn")
  end
  local per = (collectgarbage("count") - before) / 200
  if per < 0 then per = 0 end
  return per
end

function pf.NewBucket(now)
  return { cpu = {}, mem = {}, samples = 0, memTotal = 0, startedAt = now }
end

function pf.Reset()
  local now = GetTime()
  pf.history = {}
  pf.total = { cpu = {}, mem = {}, samples = 0, memTotal = 0, seconds = 0 }
  pf.funcs = {}
  pf.names = {}
  pf.startedAt = now
  pf.cur = pf.recording and pf.NewBucket(now) or nil
  pf.lastKb = collectgarbage("count")
end

function pf.Start()
  if pf.recording then return true end
  if not pf.HasDebug() then
    pf.status = "unsupported"
    return false
  end
  -- Never replace a Lua hook another addon (or a probe) installed.
  local ok, existing = pcall(debug.gethook)
  if ok and type(existing) == "function" and existing ~= pf.Hook then
    pf.status = "busy"
    return false
  end
  -- The client keeps a hook of its own installed from C: gethook returns
  -- "external hook", mask "c", count 0 (in game, 2026-10-04). Lua allows one
  -- hook per thread, so recording replaces it; Stop puts it back through the
  -- client's own SetupHook (a Lua function in its "_g" chunk) and checks.
  pf.clientHook = (ok and existing == "external hook") or pf.hookLost
  pf.status = nil
  pf.selfKb = pf.MeasureSelfKb()
  pf.recording = true
  pf.Reset()
  local installed = pcall(debug.sethook, pf.Hook, "", pf.HOOK_EVERY)
  if not installed then
    pf.recording = false
    pf.cur = nil
    pf.status = "unsupported"
    return false
  end
  U.RegisterUpdate("performance.tick", pf.REFRESH_SECONDS, pf.Tick)
  return true
end

function pf.Stop()
  if pf.HasDebug() then
    local ok, existing = pcall(debug.gethook)
    if ok and existing == pf.Hook then
      pcall(debug.sethook)
      if pf.clientHook then pf.RestoreClientHook() end
    end
  end
  if pf.recording and pf.cur then pf.Roll(GetTime()) end
  pf.recording = false
  pf.cur = nil
  U.UnregisterUpdate("performance.tick")
end

-- Reinstalls the client's own hook and reports whether it is back. Its
-- arguments are not documented, so it is called bare and the result is read
-- from gethook rather than trusted; /reload reinstalls it either way.
function pf.RestoreClientHook()
  pf.clientHook = false
  local setup = U.G("SetupHook")
  if type(setup) == "function" then pcall(setup) end
  local ok, existing = pcall(debug.gethook)
  pf.hookLost = not (ok and existing == "external hook")
end

-- Closes the open period into the history and the running totals.
function pf.Roll(now)
  local cur = pf.cur
  if not cur then return end
  cur.seconds = math.max(0, now - cur.startedAt)
  table.insert(pf.history, cur)
  while table.getn(pf.history) > pf.RECENT_BUCKETS do table.remove(pf.history, 1) end
  local total = pf.total
  local key, n
  for key, n in pairs(cur.cpu) do total.cpu[key] = (total.cpu[key] or 0) + n end
  for key, n in pairs(cur.mem) do total.mem[key] = (total.mem[key] or 0) + n end
  total.samples = total.samples + cur.samples
  total.memTotal = total.memTotal + cur.memTotal
  total.seconds = total.seconds + cur.seconds
  pf.cur = pf.recording and pf.NewBucket(now) or nil
end

function pf.Tick()
  if not pf.recording then return end
  local now = GetTime()
  if pf.cur and now - pf.cur.startedAt >= pf.BUCKET_SECONDS then pf.Roll(now) end
  if pf.page and pf.page.container and pf.page.container:IsVisible() then
    pf.Render()
  end
end

-- The selected window as one bucket: the last six closed periods (or every
-- period since start) plus the open one, so the page moves every second.
function pf.Window()
  local now = GetTime()
  local out = { cpu = {}, mem = {}, samples = 0, memTotal = 0, seconds = 0 }
  local function Add(bucket, seconds)
    local key, n
    for key, n in pairs(bucket.cpu) do out.cpu[key] = (out.cpu[key] or 0) + n end
    for key, n in pairs(bucket.mem) do out.mem[key] = (out.mem[key] or 0) + n end
    out.samples = out.samples + bucket.samples
    out.memTotal = out.memTotal + bucket.memTotal
    out.seconds = out.seconds + seconds
  end
  if pf.window == "total" then
    if pf.total then Add(pf.total, pf.total.seconds) end
  else
    local i
    for i = 1, table.getn(pf.history or {}) do
      Add(pf.history[i], pf.history[i].seconds or 0)
    end
  end
  if pf.cur then Add(pf.cur, math.max(0, now - pf.cur.startedAt)) end
  return out
end

-- Busiest function per owner over the whole recording.
function pf.Hottest()
  local best = {}
  local source, byLine
  for source, byLine in pairs(pf.funcs or {}) do
    local owner = pf.ownerCache[source]
    if owner == nil then owner = pf.Owner(source) end
    if owner == false then owner = pf.CLIENT_OTHER end
    local line, n
    for line, n in pairs(byLine) do
      local current = best[owner]
      if not current or n > current.samples then
        local _, _, file = string.find(source, "([^/\\]+)$")
        best[owner] = {
          samples = n,
          name = pf.names[source] and pf.names[source][line],
          file = file or source,
          line = line,
        }
      end
    end
  end
  return best
end

-- One row per loaded addon, plus any client or profiler owner that has CPU
-- samples or measured memory. `window` may be nil before the first recording;
-- `inUse` is the last memory measurement (owner -> bytes), or nil.
function pf.Rows(window, inUse)
  local rows, byKey = {}, {}
  local cpu = window and window.cpu or {}
  local mem = window and window.mem or {}
  inUse = inUse or {}

  local function Label(owner)
    if owner == pf.CLIENT_UI then return U.L("PERF_ROW_CLIENT") end
    if owner == pf.CLIENT_OTHER then return U.L("PERF_ROW_OTHER") end
    if owner == pf.PROFILER then return U.L("PERF_ROW_PROFILER") end
    return owner
  end
  -- Folder names in the samples can differ in case from GetAddOnInfo's, so
  -- rows are keyed case-insensitively and other spellings kept as aliases.
  local function Row(owner)
    local key = string.lower(owner)
    local row = byKey[key]
    if not row then
      row = { owner = owner, aliases = {}, label = Label(owner),
              samples = 0, memKb = 0, inUseBytes = nil }
      byKey[key] = row
      table.insert(rows, row)
    elseif owner ~= row.owner and not row.aliases[owner] then
      row.aliases[owner] = true
    end
    return row
  end

  if type(GetNumAddOns) == "function" then
    local count = tonumber(GetNumAddOns()) or 0
    local i
    for i = 1, count do
      local name = GetAddOnInfo(i)
      if name and IsAddOnLoaded(i) then Row(name) end
    end
  end
  local owner, value
  for owner, value in pairs(cpu) do
    local row = Row(owner)
    row.samples = row.samples + value
  end
  for owner, value in pairs(mem) do
    local row = Row(owner)
    row.memKb = row.memKb + value
  end
  for owner, value in pairs(inUse) do
    local row = Row(owner)
    row.inUseBytes = (row.inUseBytes or 0) + value
  end

  local sortBy = pf.sortBy
  table.sort(rows, function(a, b)
    local x, y
    if sortBy == "memory" then
      x, y = a.memKb, b.memKb
    elseif sortBy == "inuse" then
      x, y = a.inUseBytes or -1, b.inUseBytes or -1
    else
      x, y = a.samples, b.samples
    end
    if x ~= y then return x > y end
    return string.lower(a.label) < string.lower(b.label)
  end)
  return rows
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

function pf.Rate(value)
  if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
  if value >= 1000 then return string.format("%.0fk", value / 1000) end
  return string.format("%.0f", value)
end

function pf.Memory(kb)
  if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
  return string.format("%.0f KB", kb)
end

function pf.Clock(seconds)
  seconds = math.floor(seconds or 0)
  return string.format("%d:%02d", math.floor(seconds / 60), math.mod(seconds, 60))
end

-- ---------------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------------

function pf.Label(parent, size, color, width, justify)
  return U.CreateSettingsLabel(parent, {
    size = size or M.fontSize.small,
    color = color or M.color.text,
    inherits = "GameFontNormalSmall",
    justify = justify or "LEFT",
    width = width or pf.PAGE_WIDTH,
  })
end

-- Screen-space right edge of whatever clips this page: the Game Settings
-- canvas scroll frame, the standalone settings window, and the screen. The
-- page then fits between its own left edge and that, in its own units.
function pf.VisibleWidth()
  local page = pf.page
  local anchor = page and page.parent
  if not anchor then return nil end
  local function Edge(frame, method)
    if not frame then return nil end
    local okShown, shown = pcall(frame.IsVisible, frame)
    if not okShown or not shown then return nil end
    local ok, value = pcall(frame[method], frame)
    local okScale, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok or not okScale or not tonumber(value) or not tonumber(scale) then
      return nil
    end
    return value * scale
  end
  local left = Edge(anchor, "GetLeft")
  if not left then return nil end
  local right
  local candidates = { U.G("UnrealUIGameSettingsUIScroll"), U.G("UnrealUISettings"),
                       UIParent }
  local i
  for i = 1, table.getn(candidates) do
    local edge = Edge(candidates[i], "GetRight")
    if edge and edge > left and (not right or edge < right) then right = edge end
  end
  if not right then return nil end
  local okScale, scale = pcall(anchor.GetEffectiveScale, anchor)
  if not okScale or not tonumber(scale) or scale <= 0 then return nil end
  return (right - left) / scale
end

-- Column x offsets and widths for a page width.
function pf.ColumnLayout(width)
  local fixed, flex = 0, 0
  local count = table.getn(pf.COLUMNS)
  local i
  for i = 1, count do
    local column = pf.COLUMNS[i]
    if column.flex then flex = flex + column.flex else fixed = fixed + column.width end
  end
  local spare = math.max(60, width - fixed - pf.COLUMN_GAP * (count - 1))
  local layout, x = {}, 0
  for i = 1, count do
    local column = pf.COLUMNS[i]
    local w = column.width or math.floor(spare * column.flex / flex)
    layout[column.key] = { x = x, width = w, justify = column.justify }
    x = x + w + pf.COLUMN_GAP
  end
  return layout
end

function pf.PlaceCell(cell, holder, spec, isHeader)
  if not cell then return end
  pcall(cell.ClearAllPoints, cell)
  if spec.justify == "LEFT" then
    cell:SetPoint(isHeader and "TOPLEFT" or "LEFT", holder,
                  isHeader and "TOPLEFT" or "LEFT", spec.x + 2, 0)
    cell.uuiFitRoom = spec.width - 4
  else
    pcall(cell.SetWidth, cell, spec.width)
    cell:SetPoint(isHeader and "TOPRIGHT" or "RIGHT", holder,
                  isHeader and "TOPLEFT" or "LEFT", spec.x + spec.width, 0)
  end
end

-- Re-lays the whole page to `width` (page units). Cheap; only runs when the
-- measured width actually changes.
function pf.ApplyWidth(width)
  local page = pf.page
  if not page or page.width == width then return end
  page.width = width
  local i
  for i = 1, table.getn(page.texts) do pcall(page.texts[i].SetWidth, page.texts[i], width) end
  page.container:SetWidth(width)
  if page.rule then page.rule:SetWidth(width) end
  page.layout = pf.ColumnLayout(width)
  local key, cell
  for key, cell in pairs(page.headCells) do
    pf.PlaceCell(cell, page.container, page.layout[key], true)
    if cell.uuiFitRoom then U.FitLabelText(cell, cell.uuiText, cell.uuiFitRoom) end
  end
  for i = 1, table.getn(page.rows) do
    local row = page.rows[i]
    row:SetWidth(width)
    for key, cell in pairs(row.cells) do pf.PlaceCell(cell, row, page.layout[key], false) end
  end
end

function pf.Row(index)
  local page = pf.page
  local row = page.rows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, page.container)
  row:SetWidth(page.width)
  row:SetHeight(pf.ROW_HEIGHT)
  row:SetPoint("TOPLEFT", page.container, "TOPLEFT", 0,
               -(index * (pf.ROW_HEIGHT + pf.ROW_GAP)))
  if math.mod(index, 2) == 1 then
    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetTexture(M.texture.plain)
    band:SetAllPoints(row)
    U.SetColor(band, 1, 1, 1, 0.04)
  end
  row.cells = {}
  local i
  for i = 1, table.getn(pf.COLUMNS) do
    local column = pf.COLUMNS[i]
    local cell = pf.Label(row, M.fontSize.small, M.color.text, nil, column.justify)
    if cell then
      pcall(cell.SetHeight, cell, pf.ROW_HEIGHT)
      pf.PlaceCell(cell, row, page.layout[column.key], false)
      row.cells[column.key] = cell
    end
  end
  page.rows[index] = row
  return row
end

function pf.SetCell(row, key, text, color)
  local cell = row.cells[key]
  if not cell then return end
  if cell.uuiFitRoom then
    U.FitLabelText(cell, text or "", cell.uuiFitRoom)
  else
    cell:SetText(text or "")
  end
  pcall(cell.SetTextColor, cell, M.Unpack(color or M.color.text))
end

function pf.Bytes(bytes)
  return pf.Memory((bytes or 0) / 1024)
end

function pf.RecordingStatus()
  if pf.status == "busy" then return U.L("PERF_STATUS_BUSY") end
  if pf.status == "unsupported" then return U.L("PERF_STATUS_UNSUPPORTED") end
  if pf.recording then
    return U.L("PERF_STATUS_RECORDING", pf.Clock(GetTime() - (pf.startedAt or GetTime())))
  end
  if pf.hookLost then return U.L("PERF_STATUS_HOOK_LOST") end
  return U.L("PERF_STATUS_STOPPED")
end

function pf.MemoryStatus(scan)
  if not scan then return U.L("PERF_MEMORY_NONE") end
  if scan.running then
    return U.L("PERF_MEMORY_RUNNING", pf.Rate(scan.objects or 0))
  end
  if scan.failed then return U.L("PERF_MEMORY_FAILED") end
  local ago = pf.Clock(GetTime() - (scan.finishedAt or GetTime()))
  return U.L("PERF_MEMORY_DONE", ago, pf.Bytes(scan.attributed),
             pf.Memory(scan.heapKb or 0))
end

function pf.Render()
  local page = pf.page
  if not page then return end

  local visible = pf.VisibleWidth()
  if visible then
    pf.ApplyWidth(math.floor(math.max(pf.MIN_WIDTH,
      math.min(pf.MAX_WIDTH, visible - pf.EDGE_MARGIN))))
  end

  if page.start and page.start.label then
    page.start.label:SetText(U.L(pf.recording and "PERF_STOP" or "PERF_START"))
  end
  if page.status then page.status:SetText(pf.RecordingStatus()) end

  local scan = U.PerfMemory and U.PerfMemory.state or nil
  if scan and not scan.running and not scan.finishedAt and not scan.failed then scan = nil end
  if page.memStatus then page.memStatus:SetText(pf.MemoryStatus(scan)) end
  if page.measure then
    local running = scan and scan.running
    if page.measure.label then
      page.measure.label:SetText(U.L(running and "PERF_MEASURE_CANCEL" or "PERF_MEASURE"))
    end
  end

  local hasData = pf.total ~= nil
  local window = hasData and pf.Window() or nil
  local seconds = window and window.seconds or 0

  if page.summary then
    local fps = type(GetFramerate) == "function" and (tonumber(GetFramerate()) or 0) or 0
    local heap = collectgarbage("count")
    local allocated = seconds > 0 and window.memTotal / seconds or 0
    local instructions = seconds > 0 and window.samples * pf.HOOK_EVERY / seconds or 0
    page.summary:SetText(U.L("PERF_SUMMARY",
      string.format("%.0f", fps), pf.Memory(heap),
      hasData and pf.Memory(allocated) or "-",
      hasData and pf.Rate(instructions) or "-"))
  end

  local inUse = scan and not scan.running and scan.owners or nil
  local rows = pf.Rows(window, inUse)
  local hottest = hasData and pf.Hottest() or {}
  local anyData = hasData or inUse ~= nil
  if page.empty then
    if anyData then page.empty:Hide() else page.empty:Show() end
  end
  local shown = anyData and table.getn(rows) or 0
  local total = window and window.samples or 0
  local i
  for i = 1, shown do
    local data = rows[i]
    local row = pf.Row(i)
    local share = total > 0 and 100 * data.samples / total or 0
    local idle = data.samples == 0 and data.memKb == 0
    local color = (idle and not data.inUseBytes) and M.color.textDim or M.color.text
    pf.SetCell(row, "name", data.label, color)
    pf.SetCell(row, "cpu", hasData and string.format("%.1f%%", share) or "-", color)
    pf.SetCell(row, "instr", seconds > 0 and pf.Rate(data.samples * pf.HOOK_EVERY / seconds) or "-", color)
    pf.SetCell(row, "memory", seconds > 0 and (pf.Memory(data.memKb / seconds) .. "/s") or "-", color)
    pf.SetCell(row, "inuse", data.inUseBytes and pf.Bytes(data.inUseBytes) or "-", color)
    local hot = hottest[data.owner]
    if not hot then
      local alias
      for alias in pairs(data.aliases) do hot = hot or hottest[alias] end
    end
    local hotText = ""
    if hot and not idle then hotText = hot.name or (hot.file .. ":" .. tostring(hot.line)) end
    pf.SetCell(row, "hottest", hotText, M.color.textDim)
    row:Show()
  end
  for i = shown + 1, table.getn(page.rows) do page.rows[i]:Hide() end

  page.container:SetHeight((math.max(1, shown) + 1) * (pf.ROW_HEIGHT + pf.ROW_GAP))
end

function pf.BuildPage(parent)
  local widgets = {}
  local width = pf.PAGE_WIDTH
  pf.page = { rows = {}, texts = {}, headCells = {}, parent = parent, width = width }
  local page = pf.page
  page.layout = pf.ColumnLayout(width)

  local function Text(color)
    local label = pf.Label(parent, M.fontSize.small, color, width)
    if label then
      table.insert(widgets, label)
      table.insert(page.texts, label)
    end
    return label
  end

  local header = U.CreateSectionHeader(parent, {
    text = U.L("PERF_HEADER"),
    width = width,
    y = -4,
  })
  table.insert(widgets, header)

  local intro = Text(M.color.textDim)
  if intro then
    intro:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -30)
    intro:SetText(U.L("PERF_DESCRIPTION"))
  end

  -- Recording.
  page.start = U.CreateButton(parent, {
    name = "UnrealUIPerformanceStart",
    text = U.L("PERF_START"),
    width = 150,
    height = 22,
    onClick = function()
      if pf.recording then pf.Stop() else pf.Start() end
      pf.Render()
    end,
  })
  if intro then
    page.start:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
  else
    page.start:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -60)
  end
  table.insert(widgets, page.start)

  page.reset = U.CreateButton(parent, {
    name = "UnrealUIPerformanceReset",
    text = U.L("PERF_RESET"),
    width = 90,
    height = 22,
    onClick = function()
      if pf.total then pf.Reset() end
      pf.Render()
    end,
  })
  page.reset:SetPoint("LEFT", page.start, "RIGHT", 4, 0)
  table.insert(widgets, page.reset)

  local hint = Text(M.color.textDim)
  if hint then
    U.AnchorSettingsDescription(hint, page.start)
    hint:SetText(U.L("PERF_RECORDING_HINT"))
  end

  -- Memory in use.
  page.measure = U.CreateButton(parent, {
    name = "UnrealUIPerformanceMeasure",
    text = U.L("PERF_MEASURE"),
    width = 150,
    height = 22,
    onClick = function()
      local memory = U.PerfMemory
      if memory then
        if memory.state and memory.state.running then
          memory.Cancel()
        else
          memory.Start(function() pf.Render() end)
        end
      end
      pf.Render()
    end,
  })
  page.measure:SetPoint("TOPLEFT", hint or page.start, "BOTTOMLEFT", 0, -12)
  table.insert(widgets, page.measure)

  local measureHint = Text(M.color.textDim)
  if measureHint then
    U.AnchorSettingsDescription(measureHint, page.measure)
    measureHint:SetText(U.L("PERF_MEASURE_HINT"))
  end

  -- View options, on one line. The Game Settings skin resizes every owned
  -- dropdown to one control width and hangs a stepper off each end
  -- (gs.StyleOwnedDropdown), so the second dropdown sits past the first's
  -- right stepper and clear of its own left one (gs.DropdownStepperPads).
  page.window = U.CreateDropdown(parent, {
    name = "UnrealUIPerformanceWindow",
    value = pf.window,
    width = 200,
    height = 24,
    rowHeight = 20,
    items = {
      { value = "recent", text = U.L("PERF_WINDOW_RECENT") },
      { value = "total", text = U.L("PERF_WINDOW_TOTAL") },
    },
    onChange = function(value)
      pf.window = value
      pf.Render()
    end,
  })
  page.window.SetPoint("TOPLEFT", measureHint or page.measure, "BOTTOMLEFT", 0, -12)
  table.insert(widgets, page.window)

  page.sort = U.CreateDropdown(parent, {
    name = "UnrealUIPerformanceSort",
    value = pf.sortBy,
    width = 200,
    height = 24,
    rowHeight = 20,
    items = {
      { value = "cpu", text = U.L("PERF_SORT_CPU") },
      { value = "memory", text = U.L("PERF_SORT_MEMORY") },
      { value = "inuse", text = U.L("PERF_SORT_INUSE") },
    },
    onChange = function(value)
      pf.sortBy = value
      pf.Render()
    end,
  })
  local gap = 8
  local gs = U.gameSettings
  if gs and type(gs.DropdownStepperPads) == "function" then
    local left, right = gs.DropdownStepperPads()
    gap = gap + (tonumber(left) or 0) + (tonumber(right) or 0)
  end
  page.sort.SetPoint("LEFT", page.window.button, "RIGHT", gap, 0)
  table.insert(widgets, page.sort)

  -- Status lines and the summary, each a full-width line of its own.
  page.status = Text(M.color.accent)
  if page.status then
    page.status:SetPoint("TOPLEFT", page.window.button, "BOTTOMLEFT", 0, -12)
  end
  page.memStatus = Text(M.color.accent)
  if page.memStatus then
    page.memStatus:SetPoint("TOPLEFT", page.status or page.window.button,
                            "BOTTOMLEFT", 0, -4)
  end
  page.summary = Text(M.color.text)
  if page.summary then
    page.summary:SetPoint("TOPLEFT", page.memStatus or page.window.button,
                          "BOTTOMLEFT", 0, -4)
  end

  -- The list: one plain container on the canvas, so the page's own
  -- show/hide reaches every row and the canvas measures its height.
  page.container = CreateFrame("Frame", "UnrealUIPerformanceList", parent)
  page.container:SetWidth(width)
  page.container:SetHeight(pf.ROW_HEIGHT * 2)
  page.container:SetPoint("TOPLEFT", page.summary or page.window.button,
                          "BOTTOMLEFT", 0, -10)
  pcall(page.container.EnableMouse, page.container, false)
  table.insert(widgets, page.container)

  local headings = {
    name = U.L("PERF_COL_ADDON"),
    cpu = U.L("PERF_COL_CPU"),
    instr = U.L("PERF_COL_INSTR"),
    memory = U.L("PERF_COL_MEMORY"),
    inuse = U.L("PERF_COL_INUSE"),
    hottest = U.L("PERF_COL_HOTTEST"),
  }
  local i
  for i = 1, table.getn(pf.COLUMNS) do
    local column = pf.COLUMNS[i]
    local cell = pf.Label(page.container, M.fontSize.small, M.color.accent, nil,
                          column.justify)
    if cell then
      pcall(cell.SetHeight, cell, pf.ROW_HEIGHT)
      pf.PlaceCell(cell, page.container, page.layout[column.key], true)
      cell.uuiText = headings[column.key]
      if cell.uuiFitRoom then
        U.FitLabelText(cell, cell.uuiText, cell.uuiFitRoom)
      else
        cell:SetText(cell.uuiText)
      end
      page.headCells[column.key] = cell
    end
  end
  page.rule = U.CreateRule(page.container, {})
  if page.rule then
    page.rule:SetPoint("TOPLEFT", page.container, "TOPLEFT", 0, -pf.ROW_HEIGHT)
    page.rule:SetWidth(width)
  end

  page.empty = pf.Label(page.container, M.fontSize.small, M.color.textDim, width)
  if page.empty then
    page.empty:SetPoint("TOPLEFT", page.container, "TOPLEFT", 2,
                        -(pf.ROW_HEIGHT + pf.ROW_GAP + 3))
    page.empty:SetText(U.L("PERF_EMPTY"))
    table.insert(page.texts, page.empty)
  end

  local function Refresh()
    if page.window then page.window.SetValue(pf.window) end
    if page.sort then page.sort.SetValue(pf.sortBy) end
    pf.Render()
    -- The canvas is laid out (and scaled) after this callback, so measure
    -- the visible width again once that has happened.
    U.DeferOnce("performance.layout", pf.Render)
  end

  return widgets, Refresh
end

function PF:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    -- Last in the list, after Profiles (user request, 2026-10-04). A page
    -- registered later with the same `after` (modules/rogue.lua) is inserted
    -- directly behind Profiles, ahead of this one, so this stays at the end.
    U.RegisterSettingsTab("performance", U.L("PERF_PAGE"), pf.BuildPage,
                          { after = "profiles" })
  end
end

function PF:OnEnable()
  -- Never leave the hook installed past the session.
  U.RegisterEvent("PLAYER_LOGOUT", function() pf.Stop() end)
end

-- The memory walk reports progress through here, so the page moves while it
-- runs even when no recording is ticking.
function U.PerfPageChanged()
  if pf.page and pf.page.container and pf.page.container:IsVisible() then
    pf.Render()
  end
end
