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
--
-- A note on how this list got to twelve, because the reasoning matters more
-- than the list. The original five -- sweep, frames, auras, plates, bars --
-- were briefly removed after a cycle run measured them flat: 6.969, 6.976,
-- 6.992, 6.973, 6.997 and 7.017ms across their six phases, 0.05ms of spread
-- over 29090 frames. That measurement was real but it was taken at a
-- deliberately slow target-change cadence, and the symptom the switches exist
-- to find only reproduces while tab-spamming: user-confirmed 144fps -> 40fps
-- with the addon loaded, stable 144fps without it, on the same wolves. Every
-- "flat" run had measured the scenario the bug is absent from, so the five
-- were cleared on evidence that never applied, and they are back.
--
-- The other seven were added for the opposite reason: 22 of the 27 modules had
-- no guard at all, so every phase -- including the all-off control -- still
-- carried them, and no bisect could ever have located a cost living there.
local switches = {
  sweep   = true,  -- core/compat.lua        native-frame suppression
  frames  = true,  -- modules/unitframes.lua unit frame scheduler
  auras   = true,  -- modules/auras.lua      debuff rows
  plates  = true,  -- modules/nameplates.lua WorldFrame scan + plate refresh
  bars    = true,  -- modules/actionbar.lua  slot/state sweeps
  tooltip = true,  -- modules/tooltip.lua    GameTooltip restyle (OnShow/OnSizeChanged)
  castbar = true,  -- modules/castbar.lua    per-frame tick
  chat    = true,  -- modules/chat.lua       live geometry + lock visibility
  petbar  = true,  -- modules/petbar.lua     slot/cooldown sweeps
  bags    = true,  -- modules/bags.lua       dirty-slot processing
  status  = true,  -- modules/status.lua     performance/money/durability poll
  xpbar   = true,  -- modules/xpbar.lua      xp/reputation poll
}

local SWITCH_ORDER = { "sweep", "frames", "auras", "plates", "bars",
                       "tooltip", "castbar", "chat", "petbar", "bags",
                       "status", "xpbar" }

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

-- Census of every event this client actually dispatched during the recording
-- window. events.json only ever tested 24 event names, so "does this client
-- emit ACTIONBAR_UPDATE_USABLE on target change" has been an open question
-- since round 3 with no way to answer it. Counting here answers it for every
-- event at once, in the same window markCount is measured over, so the ratio
-- of any event to PLAYER_TARGET_CHANGED is directly readable.
local eventCounts = {}

-- ---------------------------------------------------------------------------
-- Automatic subsystem cycle
--
-- Hand bisecting compared runs taken minutes apart, under player behaviour that
-- could not be held constant -- and the decisive variable turned out to be one
-- nobody was controlling: the freeze only appears while MOVING and tab-target
-- spamming, not standing still, which is why several static runs measured a
-- scenario the bug is absent from.
--
-- So the switches are driven automatically instead. Every phase lasts the same
-- wall time, phases rotate continuously, and the player does exactly one thing
-- throughout: move and spam tab. Each subsystem is then measured against the
-- others under behaviour that is at worst noisy, never systematically biased,
-- and repeated rotations average the noise out.
--
-- Exactly one subsystem is enabled per phase (rather than one disabled) so each
-- phase prices that subsystem's own cost against the "none" control, instead of
-- pricing it against the other four still running.
local CYCLE_ORDER = { "none", "sweep", "frames", "auras", "plates", "bars",
                      "tooltip", "castbar", "chat", "petbar", "bags",
                      "status", "xpbar" }
-- Thirteen phases at 8s is about 105s per rotation. The first five were
-- removed after a cycle run measured them flat -- but every one of those runs
-- was taken at a deliberately slow target-change cadence, and the symptom only
-- reproduces while tab-spamming (144fps -> 40fps, user-confirmed). Measuring
-- the scenario the bug is absent from cleared them wrongly, so they are back.
local CYCLE_SECONDS = 8

-- Two cycle modes share one engine. "switches" rotates the subsystem switches
-- above; "levels" rotates core/compat.lua's suppression recipe level 0..4,
-- which is the one that actually found something. Levels are RAISED in place --
-- each level only adds operations, so the session can walk 0->4 without a
-- reload, where the per-level manual test needed five.
local CYCLE_LEVELS = { 0, 1, 2, 3, 4 }
local cycleMode = "switches"

local cycleActive = false
local cycleIndex = 0
local cycleElapsed = 0
local cycleRotations = 0
local currentPhase = "manual"   -- label used when the cycle is not driving

-- phase key -> frame and target-change accumulators. Frame stats come from
-- unmarked frames only (the general "it stutters while I move" symptom); peak
-- stats come from completed target-change samples (the micro freeze).
local phaseStats = {}

local function PhaseEntry(key)
  local entry = phaseStats[key]
  if not entry then
    entry = { frames = 0, totalMs = 0, worstMs = 0,
              marks = 0, peakTotal = 0, peakWorst = 0 }
    phaseStats[key] = entry
  end
  return entry
end

local function ResetState()
  baselineTotal, baselineCount, baselineWorst = 0, 0, 0
  baselineRing, baselineCursor = {}, 1
  pending, current, samples = 0, nil, {}
  markCount, frameCount = 0, 0
  eventCounts = {}
  phaseStats = {}
  cycleElapsed, cycleRotations = 0, 0
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

-- Attributes one completed sample to whichever phase was active when its
-- target change fired, not to whichever is active now: a sample spans four
-- frames and could otherwise be credited to the phase after it.
local function AccountSample(sample)
  local entry = PhaseEntry(sample.phase or currentPhase)
  local peak = SamplePeak(sample)
  entry.marks = entry.marks + 1
  entry.peakTotal = entry.peakTotal + peak
  if peak > entry.peakWorst then entry.peakWorst = peak end
end

local function ApplyPhase(key)
  local i
  for i = 1, table.getn(SWITCH_ORDER) do
    switches[SWITCH_ORDER[i]] = false
  end
  if key ~= "none" then switches[key] = true end
end

local function AdvanceCycle()
  local order = (cycleMode == "levels") and CYCLE_LEVELS or CYCLE_ORDER

  cycleIndex = cycleIndex + 1
  if cycleIndex > table.getn(order) then
    cycleIndex = 1
    cycleRotations = cycleRotations + 1
  end
  cycleElapsed = 0

  if cycleMode == "levels" then
    local level = order[cycleIndex]
    currentPhase = "level" .. tostring(level)
    if U.db then
      U.db.suppressLevel = level
      if level > 0 then U.db.noSuppress = false end
    end
    -- Level 0 is the control: nothing to apply, and nothing applied yet either,
    -- because the run has to start from a reload at level 0.
    if level > 0 and type(U.ReapplyNativeSuppression) == "function" then
      U.ReapplyNativeSuppression()
    end
    U.Print("perf levels |cffffff00" .. tostring(level) .. "|r" ..
            (level == 0 and " |cff888888(control: stock frames intact)|r" or "") ..
            "  |cff888888rotation " .. tostring(cycleRotations + 1) .. "|r")
    return
  end

  currentPhase = order[cycleIndex]
  ApplyPhase(currentPhase)

  U.Print("perf cycle |cffffff00" .. currentPhase .. "|r" ..
          (currentPhase == "none" and " |cff888888(control: everything off)|r"
                                   or " only") ..
          "  |cff888888rotation " .. tostring(cycleRotations + 1) .. "|r")
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

  if cycleActive then
    cycleElapsed = cycleElapsed + elapsed
    if cycleElapsed >= CYCLE_SECONDS then AdvanceCycle() end
  end

  -- Per-phase frame stats, counted for EVERY frame including the ones inside a
  -- target-change capture. They used to skip marked frames, which is correct
  -- when marks are rare but destroys the measurement under tab-spam: at ~9
  -- target changes a second and 4 frames per sample, nearly every frame is
  -- marked, so the phase mean was computed from the handful left over. The
  -- reported symptom is a sustained framerate drop (144 -> 40fps), so the
  -- phase mean has to be the true mean frame time, marks included.
  local phase = PhaseEntry(currentPhase)
  phase.frames = phase.frames + 1
  phase.totalMs = phase.totalMs + ms
  if ms > phase.worstMs then phase.worstMs = ms end

  if pending > 0 and current then
    table.insert(current, ms)
    pending = pending - 1
    if pending == 0 then
      AccountSample(current)
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

  eventCounts[event] = (eventCounts[event] or 0) + 1

  if not MARK[event] then return end

  -- A second target change inside an unfinished capture closes the first one
  -- with what it has rather than interleaving two traces.
  if current and table.getn(current) > 0 then
    AccountSample(current)
    StoreSample(current)
  end

  markCount = markCount + 1
  current = {}
  current.phase = currentPhase
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

-- ---------------------------------------------------------------------------
-- Structured export
--
-- knowledge.json / config.savedvariables_backslash_corruption: this client's
-- SavedVariables writer does not round-trip strings with backslashes safely.
-- Nothing built here is a path or contains one -- every field is a plain
-- number, boolean, or an array of numbers -- so that corruption class cannot
-- reach this table regardless.
--
-- Written on every /uui perf report, independent of chat: a player does not
-- have to screenshot or hand-copy anything. |cffffff00/reload|r after running
-- a report flushes UnrealUIDiagDB.perf to the client's SavedVariables file.
-- See U.SavedVariablesHint(): it is under the Unreal save tree in AppData,
-- not in the game install, and this client has no WTF folder at all.
local function BuildExport()
  local baseline = 0
  if baselineCount > 0 then baseline = baselineTotal / baselineCount end

  local count = table.getn(samples)
  local peakTotal, peakWorst, i = 0, 0, nil
  local exportSamples = {}
  for i = 1, count do
    local peak = SamplePeak(samples[i])
    peakTotal = peakTotal + peak
    if peak > peakWorst then peakWorst = peak end

    local frames, j = {}, nil
    for j = 1, table.getn(samples[i]) do
      frames[j] = samples[i][j]
    end
    exportSamples[i] = frames
  end

  local peakAvg = 0
  if count > 0 then peakAvg = peakTotal / count end

  -- Work counters from core/compat.lua's suppression adapter. Counting the
  -- work is the only attribution available here: this client has no intra-frame
  -- profiler, so "how many objects took the full teardown on the last target
  -- change" substitutes for "how many milliseconds did the sweep cost".
  local function ReadStats(fn)
    if type(fn) ~= "function" then return nil end
    local ok, stats = pcall(fn)
    if ok and type(stats) == "table" then return stats end
    return nil
  end

  local suppression = ReadStats(U.SuppressionStats)

  return {
    active = active,
    frameCount = frameCount,
    markCount = markCount,
    suppression = suppression,
    events = eventCounts,
    cycleSeconds = CYCLE_SECONDS,
    cycleRotations = cycleRotations,
    phases = phaseStats,
    actionbar = ReadStats(U.ActionBarStats),
    nameplates = ReadStats(U.NameplateStats),
    auras = ReadStats(U.AuraStats),
    unitframes = ReadStats(U.UnitFrameStats),
    switches = {
      sweep = switches.sweep, frames = switches.frames,
      auras = switches.auras, plates = switches.plates,
      bars = switches.bars,
    },
    baselineMeanMs = baseline,
    baselineWorstMs = baselineWorst,
    baselineFrameCount = baselineCount,
    sampleCount = count,
    peakAvgMs = peakAvg,
    peakWorstMs = peakWorst,
    overBaselineAvgMs = peakAvg - baseline,
    overBaselineWorstMs = peakWorst - baseline,
    -- One array of frame-time samples per completed target change, in order.
    samples = exportSamples,
  }
end

local function Report()
  local export = BuildExport()
  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("perf", export)
  end
  -- Also kept in an append-only log so an A/B taken in one session survives
  -- both halves; UnrealUIDiagDB.perf stays the latest run for convenience.
  local runIndex = nil
  if type(U.AppendDiagnostic) == "function" then
    runIndex = U.AppendDiagnostic("perfLog", export)
  end

  U.Print("perf: " .. (active and "|cff55ff55recording|r" or "stopped") ..
          " - " .. tostring(frameCount) .. " frames, " ..
          tostring(markCount) .. " target changes  (" .. SwitchLine() .. ")")
  U.Print("  saved to UnrealUIDiagDB.perf" ..
          (runIndex and (" + perfLog[" .. tostring(runIndex) .. "]") or "") ..
          " - |cffffff00/reload|r to write it out")

  -- Per-phase comparison. This is the whole point of a cycle run, so it prints
  -- before the aggregate numbers: the aggregates mix every phase together and
  -- are meaningless while cycling.
  local ran = false
  local i
  for i = 1, table.getn(CYCLE_ORDER) do
    if phaseStats[CYCLE_ORDER[i]] then ran = true end
  end

  if ran then
    U.Print("  |cffffff00per-subsystem|r (" .. tostring(cycleRotations) ..
            " rotations, " .. tostring(CYCLE_SECONDS) .. "s per phase):")

    local control = phaseStats["none"]
    local controlMean = 0
    if control and control.frames > 0 then
      controlMean = control.totalMs / control.frames
    end

    for i = 1, table.getn(CYCLE_ORDER) do
      local key = CYCLE_ORDER[i]
      local e = phaseStats[key]
      if e and e.frames > 0 then
        local mean = e.totalMs / e.frames
        local peakAvg = 0
        if e.marks > 0 then peakAvg = e.peakTotal / e.marks end

        local delta = ""
        if key ~= "none" and controlMean > 0 then
          delta = "  |cffff9900+" .. Format(mean - controlMean) .. "ms|r"
        end

        U.Print("    " .. key .. ": frame " .. Format(mean) .. "ms" .. delta ..
                " (worst " .. Format(e.worstMs) .. "), " ..
                tostring(e.marks) .. " targets peak " .. Format(peakAvg) ..
                "ms (worst " .. Format(e.peakWorst) .. ")")
      end
    end
  end

  -- The work census, printed alongside the timings so a bisect run says both
  -- how long the frame was and how much the suppression adapter actually did.
  if type(U.SuppressionStats) == "function" then
    local okStats, stats = pcall(U.SuppressionStats)
    if okStats and type(stats) == "table" then
      U.Print("  suppression: last target sweep " ..
              tostring(stats.lastTargetTornDown) .. " torn down of " ..
              tostring(stats.lastTargetVisited) .. " visited  (group " ..
              tostring(stats.targetGroupNames) .. " names, " ..
              tostring(stats.registeredNames) .. " registered)")
    end
  end

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
  U.Print("  |cffffff00/uui perf cycle|r - enable one subsystem at a time, " ..
          tostring(CYCLE_SECONDS) .. "s each, and compare them")
  U.Print("  |cffffff00/uui perf levels|r - walk suppression level 0-4 in one " ..
          "run (needs |cffffff00/uui suppress 0|r + reload first)")
  U.Print("  bisect (toggle one, change target again, re-read the peak):")
  local i, line = nil, ""
  for i = 1, table.getn(SWITCH_ORDER) do
    if line == "" then line = SWITCH_ORDER[i]
    else line = line .. ", " .. SWITCH_ORDER[i] end
  end
  U.Print("    |cffffff00/uui perf <name>|r - " .. line)
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

  -- The automatic cycle. One command, then the player just moves and spams tab
  -- while every subsystem takes its turn under identical behaviour.
  -- One reload, every recipe step. Requires starting from level 0 so the walk
  -- upward is possible; refuses rather than silently measuring the wrong thing.
  if argument == "levels" then
    if not U.db then
      U.Print("perf: config not loaded yet")
      return
    end
    local level = tonumber(U.db.suppressLevel) or 4
    if U.db.noSuppress then level = 0 end
    if level ~= 0 then
      U.Print("perf levels: needs to start with suppression off - run " ..
              "|cffffff00/uui suppress 0|r then |cffffff00/reload|r, then this again")
      return
    end

    ResetState()
    active = true
    U.perfActive = true
    cycleMode = "levels"
    cycleActive = true
    cycleIndex = 0
    AdvanceCycle()
    U.Print("perf: |cff55ff55levels|r - |cffffff00move and spam tab|r without " ..
            "stopping. Each suppression level gets " ..
            tostring(CYCLE_SECONDS) .. "s, 0 to 4, then it repeats.")
    U.Print("  you do not need to read anything: |cffffff00/uui perf|r then " ..
            "|cffffff00/reload|r when done and the numbers are in the file")
    return
  end

  if argument == "cycle" then
    ResetState()
    active = true
    U.perfActive = true
    cycleMode = "switches"
    cycleActive = true
    cycleIndex = 0
    AdvanceCycle()          -- enters phase 1 ("none") and applies the switches
    U.Print("perf: |cff55ff55cycling|r - now |cffffff00move around and spam " ..
            "tab|r continuously. Each subsystem gets " ..
            tostring(CYCLE_SECONDS) .. "s in turn; let it run several " ..
            "rotations, then |cffffff00/uui perf|r")
    return
  end

  if argument == "start" or argument == "on" then
    ResetState()
    active = true
    U.perfActive = true
    cycleActive = false
    currentPhase = "manual"
    U.Print("perf: |cff55ff55recording|r - change target several times, " ..
            "then |cffffff00/uui perf|r")
    return
  end

  if argument == "stop" or argument == "off" then
    Report()
    active = false
    U.perfActive = false
    -- A cycle leaves four subsystems switched off; stopping must not strand the
    -- player's UI in a diagnostic state.
    if cycleActive then
      cycleActive = false
      local i
      for i = 1, table.getn(SWITCH_ORDER) do
        switches[SWITCH_ORDER[i]] = true
      end
      if cycleMode == "levels" and U.db then
        -- Leave the addon in its shipped state rather than at whichever level
        -- the rotation happened to stop on.
        U.db.suppressLevel = 4
        U.db.noSuppress = false
        U.Print("perf: levels ended, suppression back to 4 on next |cffffff00/reload|r")
      else
        U.Print("perf: cycle ended, all subsystems restored")
      end
      cycleMode = "switches"
      currentPhase = "manual"
    end
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
