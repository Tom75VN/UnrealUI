-- unrealUI :: core/perf.lua
--
-- Frame-time recorder and subsystem bisect switches.
--
-- Why this file exists
-- ---------------------------------------------------------------------------
-- knowledge.json / compat.native_suppression_pcall_burst_stutter is still
-- PARTIAL: two rounds of suppression-sweep work were applied against a
-- user-reported micro freeze on target change, and its open probeQuestion is
-- exactly "measure frame time around the OnUpdate driver and around the
-- PLAYER_TARGET_CHANGED handler chain". Static reading has taken that record as
-- far as it goes -- the remaining target-change work in this addon is three
-- handlers and none of them is obviously large -- so the next step has to be
-- measurement, not another edit.
--
-- What this client makes possible
-- ---------------------------------------------------------------------------
--   * documentation.json / global:Helpers:debugprofilestop -- "Always returns
--     1. Does not measure elapsed time. debugprofilestart is a no-op." There is
--     no intra-frame profiler here.
--   * documentation.json / global:System:GetTime -- "Updated each UI draw", so
--     it cannot time anything inside a frame either.
--   * documentation.json / global:System:GetFramerate -- a rolling average,
--     which is the one thing a single-frame spike does not survive.
--
-- So a per-handler millisecond figure is not obtainable on this runtime at all.
-- What is obtainable is the thing the player actually reports: the length of
-- the frame itself. core/init.lua's shared driver already derives that from
-- successive GetTime readings, so this file samples that delta around the event
-- under suspicion and compares it against the same session's baseline. When a
-- spike is confirmed, the switches below turn each recurring subsystem off one
-- at a time so the cost can be bisected in the same session instead of guessed
-- at across reloads.
--
-- Everything is inert until /uui perf turns it on: U.perfActive is a plain
-- boolean, read once per driver tick and once per dispatched event.
-- ---------------------------------------------------------------------------

local U = UnrealUI

-- Frames captured after a marked event. An event can be dispatched either
-- before or after the driver tick belonging to the frame that handles it, and
-- the delta a tick reports describes the frame *before* it, so the cost can
-- land one or two ticks late. Four covers both orderings with room to spare.
local SAMPLE_FRAMES = 4

-- Rolling baseline window. At 60fps this is about five seconds of ordinary
-- frames: long enough that a couple of unrelated hitches cannot move the mean
-- much, short enough to stay inside one zone and one fight.
local BASELINE_WINDOW = 300

-- Marked events keep their individual traces; this is how many are retained.
local KEEP_SAMPLES = 10

-- The event this recorder was built to answer for. Kept as a table so a second
-- suspect can be added without touching the tick path.
local MARK = { PLAYER_TARGET_CHANGED = true }

local active = false
U.perfActive = false

-- ---------------------------------------------------------------------------
-- Bisect switches
--
-- Every recurring cost in this addon, keyed by the subsystem that owns it.
-- true = running normally. These are diagnostics: they are never persisted, so
-- a /reload always brings everything back.
-- ---------------------------------------------------------------------------
local switches = {
  sweep  = true,   -- core/compat.lua        native-frame suppression
  frames = true,   -- modules/unitframes.lua unit frame scheduler
  auras  = true,   -- modules/auras.lua      debuff rows
  plates = true,   -- modules/nameplates.lua WorldFrame scan + plate refresh
  bars   = true,   -- modules/actionbar.lua  slot/state sweeps
}

local SWITCH_ORDER = { "sweep", "frames", "auras", "plates", "bars" }

-- Consulted by the subsystems themselves. Returns true only for a key a player
-- has explicitly switched off, so an unknown key can never disable anything.
function U.PerfDisabled(key)
  return switches[key] == false
end

-- ---------------------------------------------------------------------------
-- Recording state
-- ---------------------------------------------------------------------------
local baselineTotal, baselineCount = 0, 0
local baselineWorst = 0
local baselineRing, baselineCursor = {}, 1

local pending = 0          -- frames still being captured for the current mark
local current = nil        -- the sample being filled
local samples = {}         -- completed marked samples, newest last
local markCount = 0
local frameCount = 0

local function ResetState()
  baselineTotal, baselineCount, baselineWorst = 0, 0, 0
  baselineRing, baselineCursor = {}, 1
  pending, current, samples = 0, nil, {}
  markCount, frameCount = 0, 0
end

local function StoreSample(sample)
  table.insert(samples, sample)
  if table.getn(samples) > KEEP_SAMPLES then table.remove(samples, 1) end
end

-- One completed sample's peak, which is what a micro freeze actually is: the
-- single longest frame the event produced, not the mean of the four after it.
local function SamplePeak(sample)
  local peak, i = 0, nil
  for i = 1, table.getn(sample) do
    if sample[i] > peak then peak = sample[i] end
  end
  return peak
end

-- ---------------------------------------------------------------------------
-- Driver hooks (called from core/init.lua)
-- ---------------------------------------------------------------------------

-- elapsed is the shared driver's own frame delta in seconds. core/init.lua
-- clamps it to [0, 1]; a frame longer than a second is a load stall rather than
-- the sub-100ms hitch this is looking for, so the clamp costs nothing here.
function U.PerfTick(elapsed)
  if not active then return end

  local ms = elapsed * 1000
  frameCount = frameCount + 1

  if pending > 0 and current then
    table.insert(current, ms)
    pending = pending - 1
    if pending == 0 then
      StoreSample(current)
      current = nil
    end
    return
  end

  -- Baseline is deliberately built only from frames no marked event is being
  -- measured across, so the thing being measured cannot inflate the yardstick
  -- it is measured against. A ring keeps it to the recent window rather than
  -- letting a login stall sit in the mean for the whole session.
  local previous = baselineRing[baselineCursor]
  if previous then
    baselineTotal = baselineTotal - previous
    baselineCount = baselineCount - 1
  end
  baselineRing[baselineCursor] = ms
  baselineTotal = baselineTotal + ms
  baselineCount = baselineCount + 1
  baselineCursor = baselineCursor + 1
  if baselineCursor > BASELINE_WINDOW then baselineCursor = 1 end

  if ms > baselineWorst then baselineWorst = ms end
end

-- Called once per dispatched event, before any listener runs.
function U.PerfEvent(event)
  if not active then return end
  if not MARK[event] then return end

  -- A second target change inside an unfinished capture closes the first one
  -- with what it has rather than interleaving two traces.
  if current and table.getn(current) > 0 then StoreSample(current) end

  markCount = markCount + 1
  current = {}
  pending = SAMPLE_FRAMES
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local function Format(ms)
  return string.format("%.1f", ms)
end

local function SwitchLine()
  local off, i = "", nil
  for i = 1, table.getn(SWITCH_ORDER) do
    local key = SWITCH_ORDER[i]
    if switches[key] == false then
      if off == "" then off = key else off = off .. ", " .. key end
    end
  end
  if off == "" then return "all subsystems on" end
  return "|cffff5555off:|r " .. off
end

local function Report()
  U.Print("perf: " .. (active and "|cff55ff55recording|r" or "stopped") ..
          " - " .. tostring(frameCount) .. " frames, " ..
          tostring(markCount) .. " target changes  (" .. SwitchLine() .. ")")

  if baselineCount > 0 then
    U.Print("  baseline frame " .. Format(baselineTotal / baselineCount) ..
            "ms, worst unmarked frame " .. Format(baselineWorst) .. "ms")
  else
    U.Print("  no baseline frames recorded yet")
  end

  local count = table.getn(samples)
  if count == 0 then
    U.Print("  no completed target-change samples yet - change target a few " ..
            "times, then |cffffff00/uui perf|r again")
    return
  end

  local baseline = 0
  if baselineCount > 0 then baseline = baselineTotal / baselineCount end

  local peakTotal, peakWorst, i = 0, 0, nil
  for i = 1, count do
    local peak = SamplePeak(samples[i])
    peakTotal = peakTotal + peak
    if peak > peakWorst then peakWorst = peak end
  end

  U.Print("  target change peak: avg " .. Format(peakTotal / count) ..
          "ms, worst " .. Format(peakWorst) .. "ms  (over baseline: +" ..
          Format((peakTotal / count) - baseline) .. "ms avg, +" ..
          Format(peakWorst - baseline) .. "ms worst)")

  -- The raw traces. Four numbers per target change say whether the cost is one
  -- frame (a synchronous handler) or spread over several (a scheduled refresh
  -- landing a tick or two later), which the averages above cannot distinguish.
  local shown = count
  if shown > 5 then shown = 5 end
  for i = count - shown + 1, count do
    local sample, line, j = samples[i], "", nil
    for j = 1, table.getn(sample) do
      if line == "" then line = Format(sample[j])
      else line = line .. " / " .. Format(sample[j]) end
    end
    U.Print("    #" .. tostring(i) .. ": " .. line .. "ms")
  end
end

-- ---------------------------------------------------------------------------
-- Command surface (dispatched by core/commands.lua)
-- ---------------------------------------------------------------------------
local function ShowUsage()
  U.Print("perf: |cffffff00/uui perf|r - report, |cffffff00/uui perf " ..
          "start|r / |cffffff00stop|r / |cffffff00reset|r")
  U.Print("  bisect (toggle one, change target again, re-read the peak):")
  U.Print("    |cffffff00/uui perf sweep|r  - native frame suppression")
  U.Print("    |cffffff00/uui perf frames|r - unit frame refresh scheduler")
  U.Print("    |cffffff00/uui perf auras|r  - target/player debuff rows")
  U.Print("    |cffffff00/uui perf plates|r - nameplate scan and refresh")
  U.Print("    |cffffff00/uui perf bars|r   - action bar slot/state sweeps")
  U.Print("  switches are never saved; |cffffff00/reload|r restores everything")
end

function U.PerfCommand(rest)
  local argument = string.lower(rest or "")

  if argument == "" then
    Report()
    if not active then
      U.Print("  |cffffff00/uui perf start|r to begin recording")
    end
    return
  end

  if argument == "start" or argument == "on" then
    ResetState()
    active = true
    U.perfActive = true
    U.Print("perf: |cff55ff55recording|r - change target several times, " ..
            "then |cffffff00/uui perf|r")
    return
  end

  if argument == "stop" or argument == "off" then
    active = false
    U.perfActive = false
    Report()
    return
  end

  if argument == "reset" then
    ResetState()
    U.Print("perf: counters cleared")
    return
  end

  if switches[argument] ~= nil then
    switches[argument] = not switches[argument]
    U.Print("perf: " .. argument .. " " ..
            (switches[argument] and "|cff55ff55on|r" or "|cffff5555off|r") ..
            "  (" .. SwitchLine() .. ")")
    return
  end

  ShowUsage()
end
