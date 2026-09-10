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

-- The second suspect. knowledge.json /
-- events.party_members_changed_high_frequency_while_grouped measured
-- PARTY_MEMBERS_CHANGED as the noisiest event this client emits while grouped
-- (~1Hz standing still), and knowledge.json /
-- compat.unregisterallevents_native_frame_stall is a party-only freeze that
-- was found by bracketing that event's handler chain rather than a target
-- change. So a party run marks the roster events instead: same capture
-- machinery, different trigger, and the peak column then reads "cost of a
-- roster event" instead of "cost of a target change".
--
-- RAID_ROSTER_UPDATE is included because a five-man on this client can emit it
-- alongside the party event; an event this client never sends simply never
-- marks anything, so listing it costs nothing.
local PARTY_MARK = {
  PARTY_MEMBERS_CHANGED = true,
  RAID_ROSTER_UPDATE = true,
}

-- Both at once, for the default scan. A scan is not testing a hypothesis about
-- one event, it is describing a session, and the two triggers are separated
-- again in the export by markStats below -- so nothing is lost by marking both
-- and a run no longer has to be repeated to cover the other one.
local BOTH_MARK = {
  PLAYER_TARGET_CHANGED = true,
  PARTY_MEMBERS_CHANGED = true,
  RAID_ROSTER_UPDATE = true,
}

-- Which of the three above is live. Chosen by the start command, so markCount
-- always means one thing within a single run.
local markSet = MARK
local markLabel = "target change"

-- Per-trigger peaks, keyed by event name: how many marks produced a COMPLETED
-- four-frame capture (markCount counts triggers seen, so the two differ when
-- two triggers land in one frame), and what the frame cost when they did. Whichever set is live, this is what keeps
-- "a roster event costs 40ms" and "a target change costs 9ms" apart in the
-- same run.
local markStats = {}

-- Identity of the run currently being recorded, and how it is labelled in the
-- log. Assigned by ResetState -- that is, once per start -- so every report of
-- the same run updates one entry instead of appending another. Nil until the
-- first run of the session begins.
local runId = nil
local runLabel = "manual"
local runSequence = 0

-- Frame population at the moment this run started, for the leak indicator in
-- the export below. Nil when the client has no GetNumFrames, which is the
-- state every build before 2026-09-09 was in and which the export handles by
-- omitting the fields entirely.
local runFrameCount = nil

-- knowledge.json / frames.getnumframes_added (FOCUSED_RUNTIME_PROBE,
-- BEHAVIOR_VERIFIED 2026-09-09): GetNumFrames() takes no arguments and returns
-- one number that matches a full EnumerateFrames walk exactly, and tracks the
-- live population rather than a fixed total -- 4486 in one session, 4609 in a
-- later one with more addon frames loaded. Cheap, unlike the walk itself
-- (about 1889 ms, frames.enumerateframes_added: do not use it).
--
-- Sampled twice per run at most: once when the run is identified and once each
-- time its export is built, which is the stop path plus one checkpoint every
-- CHECKPOINT_SECONDS. Never per frame. The count sits beside a table copy of
-- every recorded sample in BuildExport, so it adds no measurement perturbation
-- the checkpoint was not already causing.
local function ReadFrameCount()
  local fn = U.G("GetNumFrames")
  if type(fn) ~= "function" then return nil end
  local ok, count = pcall(fn)
  if not ok or type(count) ~= "number" then return nil end
  return count
end

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
  auras   = true,  -- modules/auras.lua      aura rows + timers
  plates  = true,  -- modules/nameplates.lua WorldFrame scan + plate refresh
  bars    = true,  -- modules/actionbar.lua  slot/state sweeps
  tooltip = true,  -- modules/tooltip.lua    GameTooltip restyle (OnShow/OnSizeChanged)
  castbar = true,  -- modules/castbar.lua    per-frame tick
  chat    = true,  -- modules/chat.lua       live geometry + lock visibility
  petbar  = true,  -- modules/petbar.lua     slot/cooldown sweeps
  bags    = true,  -- modules/bags.lua       dirty-slot processing
  status  = true,  -- modules/status.lua     performance/money/durability poll
  xpbar   = true,  -- modules/xpbar.lua      xp/reputation poll

  -- The party-scaling subsystems. Separate from the twelve above because they
  -- are not whole modules: each is the part of a module whose work is
  -- multiplied by the number of group members, which is the variable a
  -- party-only freeze is a function of. `frames` off takes the party rows with
  -- it; `partyrows` off leaves the player/target/pet frames running and
  -- removes only the five member rows and their five pet rows, which is the
  -- difference the bisect needs.
  partyrows = true, -- modules/unitframes.lua  member + member-pet row refresh
  partyaura = true, -- modules/auras.lua       the 1s party aura rescan
  hots      = true, -- modules/hots.lua        HoT indicators over party rows
  heal      = true, -- modules/healpredict.lua incoming-heal amounts per unit
}

local SWITCH_ORDER = { "sweep", "frames", "auras", "plates", "bars",
                       "tooltip", "castbar", "chat", "petbar", "bags",
                       "status", "xpbar" }

-- Kept out of SWITCH_ORDER on purpose. That list is what the subsystem cycle
-- switches OFF between phases, and adding these to it would silently remove
-- the party work from every phase of an established instrument. They are
-- restored, printed and listed alongside it instead.
local PARTY_SWITCHES = { "partyrows", "partyaura", "hots", "heal" }

-- Everything back on, both lists. Stopping a run must never leave a subsystem
-- switched off, whichever mode turned it off.
local function AllSwitchesOn()
  local i
  for i = 1, table.getn(SWITCH_ORDER) do switches[SWITCH_ORDER[i]] = true end
  for i = 1, table.getn(PARTY_SWITCHES) do switches[PARTY_SWITCHES[i]] = true end
end

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

-- The party half of the same census: how many of those events arrived carrying
-- a party unit token. UNIT_HEALTH is one name in eventCounts whether it fires
-- for the player or for five people, and "five times the unit events" is
-- exactly the shape a party-only cost has, so the token is counted separately.
-- Keyed by event name; partyEventTotal is the sum.
local partyEvents = {}
local partyEventTotal = 0

-- ---------------------------------------------------------------------------
-- Spike census and frame attribution
--
-- The recorder above only looks at frames around a marked event, which is what
-- it was built for and what a *periodic* stutter escapes: a hitch arriving
-- every second or two, with no target change anywhere near it, leaves no trace
-- in the baseline, the mean or the samples. A player reporting constant
-- stuttering was describing something this file could not show.
--
-- So every frame is classified against the same rolling baseline. A spike is a
-- frame at least FACTOR times the recent mean and at least FLOOR_MS above it,
-- the floor being there so a 7ms baseline cannot turn a harmless 15ms frame
-- into a "spike". The gap between consecutive spikes is recorded with them,
-- because a periodic cost is identified by its period: ~2s of gaps points at a
-- two-second poller, ~5s at a five-second one, and unrelated gaps say the cost
-- is not on a timer at all.
--
-- Attribution then works the only way it can here. debugprofilestop is a
-- documented no-op on this client, so nothing inside a frame can be timed. But
-- the shared driver reports each updater as it fires, the delta the next tick
-- reports describes the frame those updaters ran in, and the same holds for
-- events dispatched in that frame. Counting fires and spike-fires per id turns
-- "which frame was long" into "what ran in the long frames", which is what a
-- bisect answers slowly and this answers in one run. It also reaches the two
-- modules the cycle structurally cannot bisect, swingbar and petbarcustom,
-- because it keys on the updater id rather than on a subsystem switch.
--
-- One table rather than eighteen file-level locals, per the module-segmentation
-- rule: this file's Report and PerfTick already close over most of the module,
-- and Lua caps upvalues per function (32 on 5.0, 60 on 5.1) well below its
-- 200-local limit.
--
-- The symptom to recognise if this file ever stops working: /uui perf answers
-- "perf recorder is unavailable in this build", which is core/commands.lua
-- finding U.PerfCommand undefined because core/perf.lua never loaded at all.
-- Any load failure in this file looks exactly like that, with no error shown.
-- Check it with a real Lua 5.1 -- lupa ships lupa.lua51 alongside its default
-- 5.5, which accepts syntax this client rejects -- and test loadstring's
-- RETURN value: it reports failure by returning nil plus a message rather than
-- raising, so a checker that ignores the return passes a file that never
-- compiled. Both mistakes together hid a dropped `return {` in BuildExport.
-- ---------------------------------------------------------------------------
-- Forward declaration: spike.Reset builds its histogram through scan.NewHist,
-- and a local declared further down the file would not be visible inside a
-- function defined here.
local scan

local spike = {
  FACTOR = 2.0,        -- a frame this many times the rolling mean is a spike
  FLOOR_MS = 6,        -- ...and at least this many ms above it
  HARD = 4.0,          -- the subset severe enough to read as a freeze
  KEEP = 30,           -- spikes retained with their timestamps and gaps

  count = 0, hard = 0, worstMs = 0,
  log = {}, lastAt = nil, clock = 0,

  -- What ran inside the frame now ending. The arrays keep their slots, so a
  -- steady state allocates nothing; only the counts reset per frame.
  firedIds = {}, firedCount = 0,
  firedEvents = {}, firedEventCount = 0,

  updaterFires = {}, updaterSpikes = {}, eventSpikes = {},

  -- Heap census. A spike train this regular is usually not code running on a
  -- timer at all -- it is the collector, which fires on allocation rather than
  -- on the clock and therefore lands at a fixed period whenever the
  -- allocation rate is steady. gcinfo is the only heap reading available:
  -- UnrealPfUI's modules/panel.lua calls it on this client and reads back
  -- (used KB, threshold KB), which is WORKING_SOURCE for its presence here,
  -- not runtime verification -- so every use below degrades to nil safely.
  --
  -- Readings are integer KB, so a single small allocation does not resolve.
  -- Summed over thousands of fires the ranking still holds, which is all this
  -- needs to do: name the updater feeding the collector.
  -- Frame-time distribution over the whole run, and the latency reading in
  -- force when each spike happened. Both exist for the client-side reader:
  -- see the `scan` table below.
  hist = nil,          -- built by spike.Reset once `scan` exists
  lagAtSpike = nil,

  gcFn = nil, gcSafe = nil,
  kb = nil, gcFrame = false,
  collections = 0, freedKb = 0, allocKb = 0,
  gcAt = nil, gcGapTotal = 0, gcGapCount = 0, gcSpikes = 0,
  openId = nil, openKb = nil,
  allocById = {}, gcById = {},
}

-- gcinfo, resolved once and then called directly. The first call is protected;
-- after it answers, the same memoisation the suppression sweep uses applies,
-- because this runs twice per updater fire and a pcall per read would price
-- the measurement into what it is measuring.
function spike.ReadKb()
  if spike.gcSafe then return spike.gcFn() end

  local fn = spike.gcFn
  if fn == nil then
    fn = false
    if type(U.G) == "function" then
      local candidate = U.G("gcinfo")
      if type(candidate) == "function" then fn = candidate end
    end
    spike.gcFn = fn
  end
  if not fn then return nil end

  local ok, kb = pcall(fn)
  if not ok or type(kb) ~= "number" then
    spike.gcFn = false
    return nil
  end
  spike.gcSafe = true
  return kb
end

-- Reads the heap once per frame and decides whether the frame that just ended
-- contained a collection: gcinfo going down can only mean the collector ran.
function spike.Heap()
  local kb = spike.ReadKb()
  spike.gcFrame = false
  if not kb then return end

  if spike.kb then
    if kb < spike.kb then
      spike.gcFrame = true
      spike.collections = spike.collections + 1
      spike.freedKb = spike.freedKb + (spike.kb - kb)
      if spike.gcAt then
        spike.gcGapTotal = spike.gcGapTotal + (spike.clock - spike.gcAt)
        spike.gcGapCount = spike.gcGapCount + 1
      end
      spike.gcAt = spike.clock
    elseif kb > spike.kb then
      spike.allocKb = spike.allocKb + (kb - spike.kb)
    end
  end

  spike.kb = kb
end

function spike.Reset()
  spike.count, spike.hard, spike.worstMs = 0, 0, 0
  spike.log, spike.lastAt, spike.clock = {}, nil, 0
  spike.hist, spike.lagAtSpike = scan.NewHist(), nil
  spike.firedIds, spike.firedCount = {}, 0
  spike.firedEvents, spike.firedEventCount = {}, 0
  spike.updaterFires, spike.updaterSpikes, spike.eventSpikes = {}, {}, {}
  spike.kb, spike.gcFrame, spike.gcAt = nil, false, nil
  spike.collections, spike.freedKb, spike.allocKb = 0, 0, 0
  spike.gcGapTotal, spike.gcGapCount, spike.gcSpikes = 0, 0, 0
  spike.openId, spike.openKb = nil, nil
  spike.allocById, spike.gcById = {}, {}
end

-- Charges everything that ran in the frame just ended, then clears the frame.
-- Takes the same ms the baseline sees, so the yardstick and the verdict cannot
-- disagree.
-- Returns the frame's verdict (spike, and the harder subset that reads as a
-- freeze) so the group-size census can charge the same judgement rather than
-- re-deriving it from a baseline that has moved on by then.
function spike.Settle(ms, baselineMean)
  local hit, hard = false, false
  if baselineMean > 0 and ms >= baselineMean * spike.FACTOR and
     ms >= baselineMean + spike.FLOOR_MS then
    hit = true
    spike.count = spike.count + 1
    if ms >= baselineMean * spike.HARD then
      hard = true
      spike.hard = spike.hard + 1
    end
    if ms > spike.worstMs then spike.worstMs = ms end

    local gap = -1
    if spike.lastAt then gap = spike.clock - spike.lastAt end
    spike.lastAt = spike.clock
    if spike.gcFrame then spike.gcSpikes = spike.gcSpikes + 1 end
    table.insert(spike.log, {
      ms = ms, at = spike.clock, gap = gap,
      gc = spike.gcFrame and 1 or 0,
      -- Latency in force when the frame broke. A column of ordinary values
      -- next to a column of long frames says the stall was local; the two
      -- moving together says it was not.
      lag = spike.lagAtSpike or -1,
    })
    if table.getn(spike.log) > spike.KEEP then table.remove(spike.log, 1) end
  end

  local i
  if hit then
    for i = 1, spike.firedCount do
      local id = spike.firedIds[i]
      spike.updaterSpikes[id] = (spike.updaterSpikes[id] or 0) + 1
    end
    for i = 1, spike.firedEventCount do
      local name = spike.firedEvents[i]
      spike.eventSpikes[name] = (spike.eventSpikes[name] or 0) + 1
    end
  end

  spike.firedCount, spike.firedEventCount = 0, 0
  return hit, hard
end

-- Mean gap between the retained spikes, which is the number that names a
-- period. Returns nil when there is nothing to average.
function spike.Gaps()
  local total, count, low, high = 0, 0, nil, 0
  local i
  for i = 1, table.getn(spike.log) do
    local gap = spike.log[i].gap
    if gap and gap >= 0 then
      total = total + gap
      count = count + 1
      if not low or gap < low then low = gap end
      if gap > high then high = gap end
    end
  end
  if count == 0 then return nil end
  return total / count, low or 0, high
end

-- The two updater ids present in the largest share of spike frames. An updater
-- running every frame scores 100% by definition and means nothing, so the
-- caller prints its total fire count beside the share.
function spike.Worst()
  local bestId, bestHits, nextId, nextHits = nil, 0, nil, 0
  local id, hits
  for id, hits in pairs(spike.updaterSpikes) do
    if hits > bestHits then
      nextId, nextHits = bestId, bestHits
      bestId, bestHits = id, hits
    elseif hits > nextHits then
      nextId, nextHits = id, hits
    end
  end
  return bestId, bestHits, nextId, nextHits
end

-- ---------------------------------------------------------------------------
-- Group-size census
--
-- The one dimension the cycle modes above cannot control. A player can be told
-- to spam tab, to keep casting, or to let the switches rotate; nobody can be
-- told to be in a four-man for eight seconds and a solo for the next eight. So
-- group size is not driven, it is *classified*: every frame is charged to the
-- group size it was rendered at, and the run reads out as a slope across
-- sizes -- solo, +1, +2, +3, +4 -- assembled from whatever the session
-- happened to contain.
--
-- That is what makes this usable for the reported symptom. The player does not
-- run a special test: they leave the recorder on across an invite, a member
-- leaving, or a zone in and out of a group, and the table says whether the
-- frame time tracks the roster. A cost that is flat across sizes is not the
-- party cost however bad the party felt, and a cost that doubles from 0 to 4
-- is, without needing the freeze to reproduce on command.
--
-- Precedent for reading it this way: knowledge.json /
-- compat.unregisterallevents_native_frame_stall was isolated by a party-state
-- A/B ("fine solo, 1-5fps grouped"), which is exactly this table with two rows
-- and no instrument to record them.
--
-- One table, per the module-segmentation note on `spike` above.
local group = {
  POLL = 1.0,          -- seconds between reads when no roster event arrives
  MAX = 4,             -- party members other than the player

  fn = nil, safe = nil,
  size = 0, poll = 0, changes = 0,
  stats = {},
}

-- documentation.json / global:Group:GetNumPartyMembers is
-- DOCUMENTED_NOT_RUNTIME_VERIFIED on this client -- modules/unitframes.lua
-- says the same at PartyPlayerShown and keeps UnitExists("partyN") as its
-- fallback, so this does too rather than assuming the count exists. Resolved
-- once and kept protected, unlike spike.ReadKb: that one is called twice per
-- updater fire and cannot afford a pcall, this one runs about once a second
-- and cannot afford to be the thing that throws inside the driver tick.
function group.Read()
  if group.safe then
    local ok, count = pcall(group.fn)
    if ok and type(count) == "number" then return count end
    group.safe, group.fn = nil, false
  end

  if group.fn == nil then
    local fn = false
    if type(U.G) == "function" then
      local candidate = U.G("GetNumPartyMembers")
      if type(candidate) == "function" then fn = candidate end
    end
    group.fn = fn
    if fn then
      local ok, count = pcall(fn)
      if ok and type(count) == "number" then
        group.safe = true
        return count
      end
      group.fn = false
    end
  end

  -- Fallback: count the tokens directly. Four pcalls a second is affordable at
  -- this cadence, and it is the same read the unit frames already poll.
  local exists = nil
  if type(U.G) == "function" then exists = U.G("UnitExists") end
  if type(exists) ~= "function" then return 0 end

  local count, i = 0, nil
  for i = 1, group.MAX do
    local ok, value = pcall(exists, "party" .. i)
    if ok and value and value ~= 0 then count = count + 1 end
  end
  return count
end

function group.Refresh()
  local size = group.Read()
  if type(size) ~= "number" then size = 0 end
  if size < 0 then size = 0 end
  if size > group.MAX then size = group.MAX end
  if size ~= group.size then
    group.changes = group.changes + 1
    group.size = size
  end
  group.poll = 0
end

function group.Entry(size)
  local entry = group.stats[size]
  if not entry then
    entry = { frames = 0, totalMs = 0, worstMs = 0, seconds = 0,
              spikes = 0, hard = 0,
              marks = 0, peakTotal = 0, peakWorst = 0 }
    group.stats[size] = entry
  end
  return entry
end

-- Charged from the same tick, with the same ms and the same spike verdict the
-- baseline and the phase table see, so the three cannot disagree about which
-- frame was long.
function group.Frame(ms, elapsed, hit, hard)
  local entry = group.Entry(group.size)
  entry.frames = entry.frames + 1
  entry.totalMs = entry.totalMs + ms
  entry.seconds = entry.seconds + elapsed
  if ms > entry.worstMs then entry.worstMs = ms end
  if hit then
    entry.spikes = entry.spikes + 1
    if hard then entry.hard = entry.hard + 1 end
  end
end

-- A marked sample is charged to the size it was captured at, not the size now,
-- for the same reason AccountSample charges the phase it was captured in.
function group.Mark(size, peak)
  local entry = group.Entry(size or group.size)
  entry.marks = entry.marks + 1
  entry.peakTotal = entry.peakTotal + peak
  if peak > entry.peakWorst then entry.peakWorst = peak end
end

function group.Reset()
  group.stats, group.changes, group.poll = {}, 0, 0
  group.size = group.Read() or 0
  if type(group.size) ~= "number" then group.size = 0 end
end

-- ---------------------------------------------------------------------------
-- Client-facing scan data
--
-- Everything above answers "which part of this addon costs what", which is the
-- question an addon author has. A stutter report handed to the people who own
-- the CLIENT needs different things, because the first thing they have to rule
-- out is the addon itself, and the second is that the stall is not in the
-- renderer at all:
--
--   * a distribution, not a mean. "9ms average" describes a session nobody
--     complained about; the complaint lives in the tail, so frame times go
--     into buckets and the report quotes p95/p99 instead of an average.
--   * an addon-off control taken in the SAME session, minutes apart at most,
--     under the same play. A stutter that survives every unrealUI subsystem
--     being switched off is a client-side finding and can be handed over as
--     one; a stutter that disappears is ours. Nothing else in this file
--     produces that statement.
--   * the network, because a party-only stall is as likely to be the world
--     session as it is to be Lua. GetNetStats is sampled beside the frame
--     times and each spike carries the latency at the moment it happened, so
--     "the client froze while the connection was fine" is separable from
--     "the client froze while nothing was arriving".
--   * the build and the place, so a report can be reproduced.
--
-- Evidence note for whoever reads this next: GetBuildInfo is runtime-probed on
-- this client (environment.json / calls.GetBuildInfo, seven returns).
-- GetNetStats, GetFramerate, GetZoneText and IsInInstance are
-- DOCUMENTED_NOT_RUNTIME_VERIFIED here -- documentation.json says GetNetStats
-- returns three numbers on this client rather than Vanilla's four -- so every
-- one of them is resolved through pcall and simply absent from the export when
-- the client does not answer. None of them is inferred.
scan = {
  -- Upper edge of each bucket in ms; the last bucket is everything above.
  -- Chosen around the frame budgets that matter: 8.3 (120fps), 11.1 (90),
  -- 16.7 (60), 33.3 (30), then the range a human calls a hitch, then the
  -- range a human calls a freeze.
  EDGES = { 8.3, 11.1, 16.7, 25, 33.3, 50, 100, 200, 500 },
  LABELS = { "<8.3", "<11.1", "<16.7", "<25", "<33.3", "<50", "<100",
             "<200", "<500", "500+" },

  netFn = nil, framerateFn = nil,
  netPoll = 0,
  lag = nil, lagMin = nil, lagMax = 0, lagTotal = 0, lagCount = 0,
  inKb = 0, outKb = 0, netSamples = 0,
  lagSpikes = 0,

  checkpoint = 0,
  context = nil,
}

-- SavedVariables on this client does not round-trip backslashes safely
-- (knowledge.json / config.savedvariables_backslash_corruption). Every string
-- written into the export goes through here first: zone and build strings have
-- no reason to contain one, and "no reason to" is not a guarantee.
function scan.Clean(text)
  if type(text) ~= "string" then return nil end
  text = string.gsub(text, "\\", "/")
  text = string.gsub(text, "%c", " ")
  if string.len(text) > 64 then text = string.sub(text, 1, 64) end
  return text
end

local function CallGlobal(name, a)
  if type(U.G) ~= "function" then return nil end
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3, r4, r5, r6 = pcall(fn, a)
  if not ok then return nil end
  return r1, r2, r3, r4, r5, r6
end

-- Where and on what. Taken at the start of a run and again at the end, so a
-- report that crossed a zone or left a group says so instead of describing
-- itself with whichever state it happened to finish in.
function scan.Context()
  local context = {}

  local build, _, version, buildNumber, built = CallGlobal("GetBuildInfo")
  context.build = scan.Clean(build)
  context.version = scan.Clean(version)
  context.buildNumber = tonumber(buildNumber)
  context.builtAt = scan.Clean(built)

  context.locale = scan.Clean(CallGlobal("GetLocale"))
  context.zone = scan.Clean(CallGlobal("GetRealZoneText")) or
                 scan.Clean(CallGlobal("GetZoneText"))
  context.subzone = scan.Clean(CallGlobal("GetSubZoneText"))

  local inInstance, instanceKind = CallGlobal("IsInInstance")
  if inInstance ~= nil then
    context.inInstance = inInstance and true or false
    context.instanceKind = scan.Clean(instanceKind)
  end

  context.raidSize = tonumber(CallGlobal("GetNumRaidMembers"))
  context.partySize = group.size
  context.framerate = tonumber(CallGlobal("GetFramerate"))
  context.inCombat = CallGlobal("UnitAffectingCombat", "player") and true or false
  context.addonVersion = scan.Clean(U.version)
  context.savedAt = (type(U.DiagnosticStamp) == "function")
                    and U.DiagnosticStamp() or nil
  return context
end

-- documentation.json / global:System:GetNetStats: three numbers on this client
-- -- inbound KB/s, outbound KB/s, latency ms -- and 0 rather than nil when the
-- session has no data yet. Sampled once a second: it is a world-session
-- statistic, not a per-frame one, and reading it every frame would measure the
-- reader.
function scan.Net(elapsed)
  scan.netPoll = scan.netPoll + elapsed
  if scan.netPoll < 1 then return end
  scan.netPoll = 0

  local inKb, outKb, lag = CallGlobal("GetNetStats")
  lag = tonumber(lag)
  if not lag then return end

  scan.lag = lag
  scan.netSamples = scan.netSamples + 1
  scan.inKb = scan.inKb + (tonumber(inKb) or 0)
  scan.outKb = scan.outKb + (tonumber(outKb) or 0)
  scan.lagTotal = scan.lagTotal + lag
  scan.lagCount = scan.lagCount + 1
  if lag > scan.lagMax then scan.lagMax = lag end
  if not scan.lagMin or lag < scan.lagMin then scan.lagMin = lag end
end

-- Which bucket a frame time falls in. Linear over ten edges: cheaper than the
-- arithmetic to compute an index, and it runs once per frame.
function scan.Bucket(ms)
  local i
  for i = 1, table.getn(scan.EDGES) do
    if ms < scan.EDGES[i] then return i end
  end
  return table.getn(scan.EDGES) + 1
end

-- A histogram with every slot present. A sparse Lua table would write holes
-- into SavedVariables and hand a reader an array with gaps in it, which is a
-- worse artefact than a row of zeroes.
function scan.NewHist()
  local hist, i = {}, nil
  for i = 1, table.getn(scan.LABELS) do hist[i] = 0 end
  return hist
end

function scan.Charge(hist, ms)
  local slot = scan.Bucket(ms)
  hist[slot] = (hist[slot] or 0) + 1
end

-- The frame time at or below which the given share of frames landed, quoted as
-- a bucket edge. A histogram cannot give an exact percentile and pretending
-- otherwise would be worse than the honest "<= 33.3ms" this returns.
function scan.Percentile(hist, total, share)
  if not hist or total <= 0 then return nil end
  local target = total * share
  local seen, i = 0, nil
  for i = 1, table.getn(scan.LABELS) do
    seen = seen + (hist[i] or 0)
    if seen >= target then return scan.LABELS[i] end
  end
  return scan.LABELS[table.getn(scan.LABELS)]
end

function scan.Reset()
  scan.netPoll, scan.checkpoint = 0, 0
  scan.lag, scan.lagMin, scan.lagMax = nil, nil, 0
  scan.lagTotal, scan.lagCount = 0, 0
  scan.inKb, scan.outKb, scan.netSamples = 0, 0, 0
  scan.lagSpikes = 0
  scan.context = nil
end

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

-- The default scan's window, and its checkpoint interval. Ten seconds because
-- this one alternates between "everything running" and "nothing running" while
-- the player just plays: long enough for the difference to be felt and
-- measured, short enough that the UI never appears broken for long.
local SCAN_WINDOW = 10

-- How often a run in progress is written into its own log slot. Nothing here
-- hooks PLAYER_LOGOUT on purpose -- knowledge.json /
-- compat.totom_logout_crash_20260907 has an unresolved intermittent logout
-- crash on this client, and adding work to that path to save a diagnostic
-- would risk destroying the session it is trying to describe. A periodic
-- checkpoint gets the same result without touching logout: a forgotten stop,
-- an alt-F4 or a crash costs at most the last 30 seconds.
local CHECKPOINT_SECONDS = 30

-- Dead time at the start of every phase, charged to nothing.
--
-- A phase change is not free: the bars mode re-lays out up to ten bars and the
-- levels mode re-applies a suppression recipe, both of which land as one large
-- frame in whichever phase is entered next. Charging that to the new phase
-- biases the measurement in the exact direction the bars run is testing --
-- more bars means a bigger transition -- so it would manufacture the slope it
-- is supposed to measure. Three quarters of a second is well past the
-- transition frame and its immediate aftermath while still leaving most of the
-- 8s window as steady state.
local CYCLE_SETTLE = 0.75
local cycleSettled = false

-- Two cycle modes share one engine. "switches" rotates the subsystem switches
-- above; "levels" rotates core/compat.lua's suppression recipe level 0..4,
-- which is the one that actually found something. Levels are RAISED in place --
-- each level only adds operations, so the session can walk 0->4 without a
-- reload, where the per-level manual test needed five.
local CYCLE_LEVELS = { 0, 1, 2, 3, 4 }

-- Third cycle mode: how many action bars are enabled. The other two ask which
-- subsystem costs what; this one asks whether one subsystem's cost is
-- proportional to a number the player controls, which is a different question
-- and the one behind "every extra bar drops the framerate".
--
-- The counts are not 1..10. A per-bar cost is a slope, and a slope is read
-- from its ends far more reliably than from ten adjacent points that differ by
-- less than the frame-time noise: 0 is the control (the module loaded, every
-- bar hidden, its updaters still registered), and 10 is the loudest case. The
-- points between are there to say whether the slope is straight -- a straight
-- line means per-button work, a knee means a threshold was crossed.
local CYCLE_BARS = { 0, 1, 2, 4, 6, 8, 10 }

-- Fourth cycle mode: the party bisect, and the only one that removes a
-- subsystem instead of enabling one.
--
-- The one-on shape above is right when the question is "what does this cost",
-- because a control with everything off is the only honest zero. It is the
-- wrong shape here for two reasons. A party subsystem enabled alone has
-- nothing to be multiplied by -- the party rows do not refresh while the unit
-- frame scheduler that drives them is switched off -- and the symptom being
-- chased is a freeze the player can feel, so the phase that matters is the one
-- where the framerate visibly comes back. Leave-one-out gives both: "all" is
-- the reproduction, and each later phase asks whether removing exactly one
-- subsystem ends it.
--
-- `sweep` and `frames` are in the list even though they are not party-only:
-- knowledge.json / compat.unregisterallevents_native_frame_stall was a
-- party-only freeze living inside the suppression adapter, not inside any
-- party feature, so a party bisect that could not point at the sweep would
-- have missed the last one.
local CYCLE_PARTY = { "all", "partyrows", "partyaura", "hots", "heal",
                      "sweep", "frames" }

-- Restored verbatim when the run stops. A bar-count run writes real config --
-- the same table the settings panel writes -- so leaving it unrestored would
-- persist a diagnostic layout on the next logout.
local barsRestore = nil

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
    entry = { frames = 0, totalMs = 0, worstMs = 0, seconds = 0,
              spikes = 0, hard = 0, hist = scan.NewHist(),
              marks = 0, peakTotal = 0, peakWorst = 0 }
    phaseStats[key] = entry
  end
  return entry
end

local function ReadStatsTable(fn)
  if type(fn) ~= "function" then return nil end
  local ok, stats = pcall(fn)
  if ok and type(stats) == "table" then return stats end
  return nil
end

-- Adds one snapshot's counts into the phase they were produced in, then clears
-- the module counters so the next phase starts from zero. Accumulating rather
-- than overwriting is what lets several rotations of the same phase be read as
-- one measurement.
local function AddWork(entry, stats, keys)
  if not stats then return end
  entry.work = entry.work or {}
  local i
  for i = 1, table.getn(keys) do
    local key = keys[i]
    local value = tonumber(stats[key])
    if value then entry.work[key] = (entry.work[key] or 0) + value end
  end
end

local BAR_WORK_KEYS = { "buttonVisits", "slotSweeps", "stateSweeps",
                        "gcdSweeps", "gcdVisits", "cooldownSweeps",
                        "cooldownVisits" }
local WIPE_WORK_KEYS = { "applies", "rows", "writes", "gradients" }

-- Called on every phase change and once when the run stops, so the last phase
-- is not lost. Visible bars/buttons are recorded as the phase's own figure
-- rather than summed: they are a state, not an amount of work.
local function ResetPhaseWork()
  if type(U.ResetActionBarStats) == "function" then pcall(U.ResetActionBarStats) end
  if type(U.ResetRadialWipeStats) == "function" then pcall(U.ResetRadialWipeStats) end
end

local function CollectPhaseWork(key)
  local entry = PhaseEntry(key)
  local bars = ReadStatsTable(U.ActionBarStats)
  if bars then
    entry.enabledBars = bars.enabledBars
    entry.visibleButtons = bars.visibleButtons
    entry.builtWipes = bars.builtWipes
    AddWork(entry, bars, BAR_WORK_KEYS)
  end
  AddWork(entry, ReadStatsTable(U.RadialWipeStats), WIPE_WORK_KEYS)
  ResetPhaseWork()
end

-- A new run, and with it a new slot in the log. The id has to be unique across
-- reloads as well as within a session, because UnrealUIDiagDB.perfLog is
-- persisted: the wall clock supplies that where the client has date(), and the
-- sequence number keeps two runs started inside the same second apart. Where
-- date() is missing the sequence alone still separates runs within a session,
-- which is where an A/B is taken.
local function NewRunId(label)
  runSequence = runSequence + 1
  local stamp = "?"
  if type(U.DiagnosticStamp) == "function" then stamp = U.DiagnosticStamp() end
  runLabel = label or "manual"
  runId = runLabel .. " " .. stamp .. " #" .. tostring(runSequence)
  runFrameCount = ReadFrameCount()
  return runId
end

local function ResetState()
  baselineTotal, baselineCount, baselineWorst = 0, 0, 0
  baselineRing, baselineCursor = {}, 1
  pending, current, samples = 0, nil, {}
  markCount, frameCount = 0, 0
  eventCounts = {}
  markStats = {}
  partyEvents, partyEventTotal = {}, 0
  phaseStats = {}
  cycleElapsed, cycleRotations = 0, 0
  spike.Reset()
  group.Reset()
  scan.Reset()
  scan.context = scan.Context()
end

-- Called by core/init.lua's shared driver as each updater fires. Recorded
-- against the frame in progress and settled by the next tick, which is the one
-- that knows how long that frame was.
function U.PerfUpdater(id)
  if not active or type(id) ~= "string" then return end
  spike.updaterFires[id] = (spike.updaterFires[id] or 0) + 1
  spike.firedCount = spike.firedCount + 1
  spike.firedIds[spike.firedCount] = id
  spike.openId = id
  spike.openKb = spike.ReadKb()
end

-- Closes the bracket the driver opened. A negative delta means the collector
-- ran inside that callback, which is charged separately: the updater that
-- happens to cross the threshold is not necessarily the one that filled it,
-- and the allocation totals are the honest answer to who did.
function U.PerfUpdaterEnd()
  if not active or not spike.openId then return end

  local id = spike.openId
  local before = spike.openKb
  spike.openId, spike.openKb = nil, nil
  if not before then return end

  local kb = spike.ReadKb()
  if not kb then return end

  if kb > before then
    spike.allocById[id] = (spike.allocById[id] or 0) + (kb - before)
  elseif kb < before then
    spike.gcById[id] = (spike.gcById[id] or 0) + 1
  end
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
  group.Mark(sample.group, peak)

  local event = sample.event
  if event then
    local stat = markStats[event]
    if not stat then
      stat = { count = 0, peakTotal = 0, peakWorst = 0 }
      markStats[event] = stat
    end
    stat.count = stat.count + 1
    stat.peakTotal = stat.peakTotal + peak
    if peak > stat.peakWorst then stat.peakWorst = peak end
  end
end

local function ApplyPhase(key)
  local i
  for i = 1, table.getn(SWITCH_ORDER) do
    switches[SWITCH_ORDER[i]] = false
  end
  if key ~= "none" then switches[key] = true end
end

-- The party cycle's phase application: everything on, then one subsystem off.
-- See CYCLE_PARTY for why this is the opposite shape to ApplyPhase.
local function ApplyPartyPhase(key)
  AllSwitchesOn()
  if key ~= "all" then switches[key] = false end
end

-- The default scan's two phases: every subsystem running, then none of them.
-- This is the addon-off control, and it is the reason the scan can hand a
-- client-side reader a statement rather than a suspicion.
local ALL_OFF = { "on", "off" }

local function ApplyScanPhase(key)
  if key == "off" then
    local i
    for i = 1, table.getn(SWITCH_ORDER) do switches[SWITCH_ORDER[i]] = false end
    for i = 1, table.getn(PARTY_SWITCHES) do switches[PARTY_SWITCHES[i]] = false end
    return
  end
  AllSwitchesOn()
end

-- The bars this character can actually own. Class-reserved stance pages are
-- not in the list, so "6 bars" means six real bars on every class rather than
-- six indices of which one silently does nothing.
local function BarIds()
  local ids = ReadStatsTable(U.ActionBarIDs)
  if ids and table.getn(ids) > 0 then return ids end
  return nil
end

-- Enables exactly the first `count` available bars and disables the rest.
-- Every bar keeps its own size/rows/spacing: the run measures bar count, so
-- nothing else may move between phases.
local function ApplyBarCount(count)
  local ids = BarIds()
  if not ids or type(U.SetActionBarSetting) ~= "function" then return end
  local i
  for i = 1, table.getn(ids) do
    U.SetActionBarSetting(ids[i], "Enabled", i <= count)
  end
end

-- Captures what the player actually had, so the run can hand it back.
local function CaptureBarState()
  local ids = BarIds()
  if not ids or type(U.GetActionBarSetting) ~= "function" then return nil end
  local saved, i = {}, nil
  for i = 1, table.getn(ids) do
    saved[ids[i]] = U.GetActionBarSetting(ids[i], "Enabled") and true or false
  end
  return saved
end

local function RestoreBarState()
  if not barsRestore or type(U.SetActionBarSetting) ~= "function" then return end
  local bar, enabled
  for bar, enabled in pairs(barsRestore) do
    U.SetActionBarSetting(bar, "Enabled", enabled)
  end
  barsRestore = nil
end

-- The scan alternates on a longer window than the bisect cycles: it is not
-- pricing twelve subsystems against each other, it is giving a player time to
-- feel the difference between two states.
local function PhaseSeconds()
  if cycleMode == "scan" then return SCAN_WINDOW end
  return CYCLE_SECONDS
end

local function AdvanceCycle()
  local order = CYCLE_ORDER
  if cycleMode == "levels" then order = CYCLE_LEVELS
  elseif cycleMode == "bars" then order = CYCLE_BARS
  elseif cycleMode == "party" then order = CYCLE_PARTY
  elseif cycleMode == "scan" then order = ALL_OFF end

  -- Charge the work just done to the phase that did it, before the phase key
  -- moves. Skipped on the very first entry, where there is nothing to charge.
  if cycleMode == "bars" and cycleIndex > 0 then CollectPhaseWork(currentPhase) end

  cycleIndex = cycleIndex + 1
  if cycleIndex > table.getn(order) then
    cycleIndex = 1
    cycleRotations = cycleRotations + 1
  end
  cycleElapsed = 0
  cycleSettled = false

  if cycleMode == "bars" then
    -- Clamped to what this class actually has: a Warrior owns seven bars, not
    -- ten, and a phase labelled "10" that could only show seven would report a
    -- per-bar slope over three bars that were never there. Two clamped phases
    -- collapse onto the same key and simply merge into one longer sample.
    local ids = BarIds()
    local count = order[cycleIndex]
    local maximum = ids and table.getn(ids) or 0
    if count > maximum then count = maximum end
    currentPhase = "bars" .. tostring(count)
    ApplyBarCount(count)
    U.Print("perf bars |cffffff00" .. tostring(count) .. "|r bar" ..
            (count == 1 and "" or "s") ..
            (count == 0 and " |cff888888(control: module loaded, nothing shown)|r"
                         or "") ..
            "  |cff888888rotation " .. tostring(cycleRotations + 1) .. "|r")
    return
  end

  if cycleMode == "scan" then
    local key = order[cycleIndex]
    currentPhase = key
    ApplyScanPhase(key)
    U.Print("perf scan: unrealUI |cffffff00" ..
            (key == "on" and "running" or "SILENT") .. "|r for " ..
            tostring(SCAN_WINDOW) .. "s  |cff888888(keep playing exactly the " ..
            "same way)|r")
    return
  end

  if cycleMode == "party" then
    local key = order[cycleIndex]
    currentPhase = (key == "all") and "all" or ("no-" .. key)
    ApplyPartyPhase(key)
    U.Print("perf party |cffffff00" .. currentPhase .. "|r" ..
            (key == "all" and " |cff888888(reproduction: everything on)|r"
                           or " |cff888888(" .. key .. " removed)|r") ..
            "  |cff888888group " .. tostring(group.size) ..
            ", rotation " .. tostring(cycleRotations + 1) .. "|r")
    return
  end

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
  spike.clock = spike.clock + elapsed

  -- Settle the frame that just ended before anything else touches the
  -- baseline: this delta describes the frame the previous tick's updaters and
  -- events ran in, so it is judged against the window that closed before it.
  local mean = 0
  if baselineCount > 0 then mean = baselineTotal / baselineCount end
  spike.Heap()
  scan.Net(elapsed)
  spike.lagAtSpike = scan.lag
  local spiked, hardSpike = spike.Settle(ms, mean)

  -- Group size, then the frame charged to it. Polled rather than read every
  -- frame: PARTY_MEMBERS_CHANGED refreshes it the moment the roster moves
  -- (see U.PerfEvent), so this poll only covers the case where the client
  -- sends nothing at all -- a member going offline, a zone change, a build
  -- where the event is missing.
  group.poll = group.poll + elapsed
  if group.poll >= group.POLL then group.Refresh() end
  group.Frame(ms, elapsed, spiked, hardSpike)

  -- The client-facing half: the distribution every frame belongs to, and the
  -- world session it was rendered under.
  scan.Charge(spike.hist, ms)

  if cycleActive then
    cycleElapsed = cycleElapsed + elapsed
    if cycleElapsed >= PhaseSeconds() then
      AdvanceCycle()
    elseif not cycleSettled and cycleElapsed >= CYCLE_SETTLE then
      -- Steady state reached. The counters hold the transition's own work at
      -- this point, so clearing them here is what keeps the work census and
      -- the frame times describing the same window.
      cycleSettled = true
      ResetPhaseWork()
    end
  end

  -- Per-phase frame stats, counted for EVERY frame including the ones inside a
  -- target-change capture. They used to skip marked frames, which is correct
  -- when marks are rare but destroys the measurement under tab-spam: at ~9
  -- target changes a second and 4 frames per sample, nearly every frame is
  -- marked, so the phase mean was computed from the handful left over. The
  -- reported symptom is a sustained framerate drop (144 -> 40fps), so the
  -- phase mean has to be the true mean frame time, marks included.
  -- Not charged while a phase is still settling: see CYCLE_SETTLE.
  if not cycleActive or cycleSettled then
    local phase = PhaseEntry(currentPhase)
    phase.frames = phase.frames + 1
    phase.totalMs = phase.totalMs + ms
    if ms > phase.worstMs then phase.worstMs = ms end
    if spiked then
      phase.spikes = (phase.spikes or 0) + 1
      if hardSpike then phase.hard = (phase.hard or 0) + 1 end
    end
    phase.seconds = (phase.seconds or 0) + elapsed
    -- Per-phase distribution, so the addon-on and addon-off windows can be
    -- compared at the tail rather than at the average.
    scan.Charge(phase.hist, ms)
  end

  -- Checkpoint. Writes the run into its own log slot every CHECKPOINT_SECONDS
  -- so that a forgotten /uui perf stop, a disconnect or a client crash still
  -- leaves the run in SavedVariables. Costs one table build per interval.
  scan.checkpoint = scan.checkpoint + elapsed
  if scan.checkpoint >= CHECKPOINT_SECONDS then
    scan.checkpoint = 0
    if type(U.PerfCheckpoint) == "function" then U.PerfCheckpoint() end
  end

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
-- `unit` is the event's first payload argument, passed by core/init.lua's
-- dispatcher. It is only a unit token for the UNIT_* family; for every other
-- event it is whatever that event's arg1 happens to be, which is why the test
-- below is a literal "party" prefix and nothing more.
function U.PerfEvent(event, unit)
  if not active then return end

  eventCounts[event] = (eventCounts[event] or 0) + 1

  if type(unit) == "string" and string.sub(unit, 1, 5) == "party" then
    partyEvents[event] = (partyEvents[event] or 0) + 1
    partyEventTotal = partyEventTotal + 1
  end

  -- The roster events move the census the moment they arrive rather than at
  -- the next poll, so the frames right after an invite are charged to the size
  -- they were actually rendered at. PARTY_MEMBERS_CHANGED is measured at ~1Hz
  -- while grouped on this client (knowledge.json /
  -- events.party_members_changed_high_frequency_while_grouped), so in practice
  -- this is what keeps the size current and the poll never fires.
  if PARTY_MARK[event] then group.Refresh() end

  -- Events are dispatched outside the driver loop but inside the same frame,
  -- so they are charged to it exactly as updaters are. The cap only stops a
  -- pathological burst from growing the per-frame array without bound; the
  -- census in eventCounts is unaffected by it.
  if spike.firedEventCount < 60 then
    spike.firedEventCount = spike.firedEventCount + 1
    spike.firedEvents[spike.firedEventCount] = event
  end

  if not markSet[event] then return end

  -- A second target change inside an unfinished capture closes the first one
  -- with what it has rather than interleaving two traces.
  if current and table.getn(current) > 0 then
    AccountSample(current)
    StoreSample(current)
  end

  markCount = markCount + 1
  current = {}
  current.phase = currentPhase
  current.group = group.size
  current.event = event
  pending = SAMPLE_FRAMES
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local function Format(ms)
  return string.format("%.1f", ms)
end

local function SwitchLine()
  local off = ""
  local function Collect(list)
    local n
    for n = 1, table.getn(list) do
      local key = list[n]
      if switches[key] == false then
        if off == "" then off = key else off = off .. ", " .. key end
      end
    end
  end
  Collect(SWITCH_ORDER)
  Collect(PARTY_SWITCHES)
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

  -- Second and last read of the count for this export. Both ends must be
  -- present for the pair to mean anything: a start without an end, or an end
  -- without a start, is not a delta and is dropped rather than half-reported.
  local frameCountStart, frameCountEnd, frameCountDelta = runFrameCount, nil, nil
  frameCountEnd = ReadFrameCount()
  if type(frameCountStart) ~= "number" or type(frameCountEnd) ~= "number" then
    frameCountStart, frameCountEnd = nil, nil
  else
    frameCountDelta = frameCountEnd - frameCountStart
  end

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

  -- The spike log as three parallel plain-number arrays. This client's
  -- SavedVariables writer is only trusted with numbers, booleans and arrays of
  -- them (knowledge.json / config.savedvariables_backslash_corruption), and
  -- three arrays read as well as a list of records once they are lined up.
  local spikeMs, spikeAt, spikeGap, spikeGc, spikeLag = {}, {}, {}, {}, {}
  local n
  for n = 1, table.getn(spike.log) do
    spikeMs[n] = spike.log[n].ms
    spikeAt[n] = spike.log[n].at
    spikeGap[n] = spike.log[n].gap
    spikeGc[n] = spike.log[n].gc
    spikeLag[n] = spike.log[n].lag
  end

  local gcGap = 0
  if spike.gcGapCount > 0 then gcGap = spike.gcGapTotal / spike.gcGapCount end
  local allocRate = 0
  if spike.clock > 0 then allocRate = spike.allocKb / spike.clock end

  local spikeRate = 0
  if spike.clock > 0 then spikeRate = spike.count / spike.clock end

  -- The group-size census, flattened into parallel arrays indexed by size+1,
  -- so size 0 (solo) has a slot and the table reads as a slope down the
  -- column. Plain numbers only, per the SavedVariables note above.
  local groupFrames, groupMeanMs, groupWorstMs = {}, {}, {}
  local groupSpikes, groupHard, groupSpikeRate = {}, {}, {}
  local groupMarks, groupPeakMs, groupSeconds = {}, {}, {}
  local size
  for size = 0, group.MAX do
    local e = group.stats[size]
    local slot = size + 1
    groupFrames[slot] = e and e.frames or 0
    groupSeconds[slot] = e and e.seconds or 0
    groupMeanMs[slot] = (e and e.frames > 0) and (e.totalMs / e.frames) or 0
    groupWorstMs[slot] = e and e.worstMs or 0
    groupSpikes[slot] = e and e.spikes or 0
    groupHard[slot] = e and e.hard or 0
    groupSpikeRate[slot] = (e and e.seconds > 0) and (e.spikes / e.seconds) or 0
    groupMarks[slot] = e and e.marks or 0
    groupPeakMs[slot] = (e and e.marks > 0) and (e.peakTotal / e.marks) or 0
  end

  -- Per-phase distributions, flattened next to the phase table so a reader
  -- does not have to walk a nested structure to compare two windows.
  local phaseHist = {}
  local phaseKey, phaseValue
  for phaseKey, phaseValue in pairs(phaseStats) do
    if phaseValue.hist then phaseHist[phaseKey] = phaseValue.hist end
  end

  local lagMean = 0
  if scan.lagCount > 0 then lagMean = scan.lagTotal / scan.lagCount end
  local inKb, outKb = 0, 0
  if scan.netSamples > 0 then
    inKb = scan.inKb / scan.netSamples
    outKb = scan.outKb / scan.netSamples
  end

  local onPhase, offPhase = phaseStats["on"], phaseStats["off"]
  local function PhaseRate(entry)
    if not entry or not entry.seconds or entry.seconds <= 0 then return 0 end
    return (entry.spikes or 0) / entry.seconds
  end

  return {
    -- Header, for whoever opens this file without having read this module.
    -- Every duration is milliseconds, every rate is per second, and the
    -- client's own limits are stated because they explain the shape of
    -- everything below: documentation.json says debugprofilestop always
    -- returns 1 and debugprofilestart is a no-op here, so there is no
    -- intra-frame profiler and nothing in this file times a function. Frame
    -- length is measured from successive GetTime readings in the addon's
    -- shared OnUpdate driver, and attribution is by counting what ran in the
    -- frames that were long.
    schema = 3,
    units = "ms; rates per second; heap in KB",
    measurement = "frame delta from GetTime in the addon OnUpdate driver; " ..
                  "no intra-frame profiler exists on this client",
    context = scan.context,
    contextAtEnd = scan.Context(),

    active = active,
    frameCount = frameCount,
    markCount = markCount,
    markEvent = markLabel,
    markStats = markStats,
    suppression = suppression,
    events = eventCounts,

    -- Party dimension. groupMeanMs is the whole report in one array: if it
    -- rises from slot 1 (solo) to slot 5 (full party) the cost is a function
    -- of the roster, and groupSpikeRate says whether that shows up as a
    -- steady tax or as freezes. partyEvents names the traffic behind it.
    groupSize = group.size,
    groupChanges = group.changes,
    groupFrames = groupFrames,
    groupSeconds = groupSeconds,
    groupMeanMs = groupMeanMs,
    groupWorstMs = groupWorstMs,
    groupSpikes = groupSpikes,
    groupHardSpikes = groupHard,
    groupSpikeRate = groupSpikeRate,
    groupMarks = groupMarks,
    groupPeakMs = groupPeakMs,
    partyEvents = partyEvents,
    partyEventTotal = partyEventTotal,

    cycleSeconds = CYCLE_SECONDS,
    cycleRotations = cycleRotations,
    phases = phaseStats,
    actionbar = ReadStats(U.ActionBarStats),
    radialwipe = ReadStats(U.RadialWipeStats),
    nameplates = ReadStats(U.NameplateStats),
    auras = ReadStats(U.AuraStats),
    unitframes = ReadStats(U.UnitFrameStats),
    switches = {
      sweep = switches.sweep, frames = switches.frames,
      auras = switches.auras, plates = switches.plates,
      bars = switches.bars,
      partyrows = switches.partyrows, partyaura = switches.partyaura,
      hots = switches.hots, heal = switches.heal,
    },
    -- The periodic-stutter half of the report. spikeUpdaters/spikeEvents are
    -- keyed by id: compare each against updaterFires for the same id, because
    -- an updater that fires every frame is in every spike frame by definition
    -- and only its share means anything.
    spikeCount = spike.count,
    spikeHardCount = spike.hard,
    spikeWorstMs = spike.worstMs,
    spikePerSecond = spikeRate,
    spikeFactor = spike.FACTOR,
    spikeFloorMs = spike.FLOOR_MS,
    spikeMs = spikeMs,
    spikeAt = spikeAt,
    spikeGap = spikeGap,
    spikeGc = spikeGc,
    spikeLag = spikeLag,

    -- Frame-time distribution. histogram[i] counts frames whose length fell
    -- under histogramEdges[i]; the last slot is everything above the last
    -- edge. This is the part a client-side reader should look at first: the
    -- mean describes the session nobody complained about, the last three
    -- buckets describe the complaint.
    histogram = spike.hist,
    histogramEdges = scan.EDGES,
    histogramLabels = scan.LABELS,
    p50Ms = scan.Percentile(spike.hist, frameCount, 0.50),
    p95Ms = scan.Percentile(spike.hist, frameCount, 0.95),
    p99Ms = scan.Percentile(spike.hist, frameCount, 0.99),
    phaseHistogram = phaseHist,

    -- The addon-off control, present only in a default scan. If
    -- addonOffSpikeRate is close to addonOnSpikeRate the stutter survived
    -- every unrealUI subsystem being switched off, which makes it a
    -- client-side finding rather than an addon one.
    addonOnSpikeRate = PhaseRate(onPhase),
    addonOffSpikeRate = PhaseRate(offPhase),
    addonOnMeanMs = (onPhase and onPhase.frames > 0)
                    and (onPhase.totalMs / onPhase.frames) or nil,
    addonOffMeanMs = (offPhase and offPhase.frames > 0)
                     and (offPhase.totalMs / offPhase.frames) or nil,
    addonOnSeconds = onPhase and onPhase.seconds or nil,
    addonOffSeconds = offPhase and offPhase.seconds or nil,

    -- World session, sampled once a second (documentation.json /
    -- global:System:GetNetStats -- three returns on this client, and 0 rather
    -- than nil before the session has data). spikeLag above carries the
    -- reading in force at each individual spike.
    netSamples = scan.netSamples,
    latencyMeanMs = lagMean,
    latencyMinMs = scan.lagMin,
    latencyMaxMs = scan.lagMax,
    inboundKbPerSecond = inKb,
    outboundKbPerSecond = outKb,

    -- Heap census. gcSpikeCount against spikeCount is the whole verdict: if
    -- nearly every spike frame also contained a collection, the stutter is the
    -- collector and allocKbPerSecond/allocByUpdater say what feeds it.
    gcCollections = spike.collections,
    gcSpikeCount = spike.gcSpikes,
    gcMeanGapSeconds = gcGap,
    gcFreedKb = spike.freedKb,
    gcHeapKb = spike.kb,
    allocKbTotal = spike.allocKb,
    allocKbPerSecond = allocRate,
    allocByUpdater = spike.allocById,
    gcInsideUpdater = spike.gcById,
    -- Frame-population leak indicator. frameCountStart is the count when the
    -- run was identified, frameCountEnd the count as this export was built,
    -- and frameCountDelta the growth between them. A run that ends with many
    -- more frames than it started with is creating widgets it never reuses --
    -- the one thing a frame-time histogram cannot show, because the cost of a
    -- leak lands on the client rather than inside any updater.
    --
    -- All three are absent together on a client without GetNumFrames, which is
    -- how a reader tells "no leak" from "not measured". A delta of 0 is a real
    -- reading; nil is not one.
    frameCountStart = frameCountStart,
    frameCountEnd = frameCountEnd,
    frameCountDelta = frameCountDelta,
    recordedSeconds = spike.clock,
    updaterFires = spike.updaterFires,
    spikeUpdaters = spike.updaterSpikes,
    spikeEvents = spike.eventSpikes,
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

-- Builds the run's current state and writes it into its own slot. Shared by
-- the report, the periodic checkpoint and the stop path, so all three store
-- exactly the same thing and a checkpointed run that is never stopped is still
-- a complete record of everything up to that moment.
local function SaveRun()
  -- A report before any start still belongs to a run, so that repeated peeks
  -- at an idle recorder reuse one slot instead of filling the log with empty
  -- entries and evicting real ones.
  if not runId then NewRunId(runLabel) end

  local export = BuildExport()

  -- Run identity travels with the data. UnrealUIDiagDB.perfLog is keyed on
  -- `id`, so a reader can tell three reports of one run from three separate
  -- runs, and UpsertDiagnostic can find this run's own slot again.
  export.id = runId
  export.run = runLabel
  export.mode = cycleActive and cycleMode or "manual"
  export.stopped = not active
  if type(U.DiagnosticStamp) == "function" then
    export.savedAt = U.DiagnosticStamp()
  end

  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("perf", export)
  end

  -- The log is what makes several scans possible: UnrealUIDiagDB.perf is a
  -- single slot and is only ever the latest run, so an A/B would lose its
  -- first half the moment the second was reported. perfLog keeps both --
  -- one entry per run, updated in place however many times that run is
  -- printed, oldest evicted only when the cap is genuinely reached.
  local runIndex, stored, evicted = nil, nil, false
  if runId and type(U.UpsertDiagnostic) == "function" then
    runIndex, stored, evicted = U.UpsertDiagnostic("perfLog", runId, export)
  elseif type(U.AppendDiagnostic) == "function" then
    runIndex = U.AppendDiagnostic("perfLog", export)
  end

  return export, runIndex, stored, evicted
end

-- Called from the driver every CHECKPOINT_SECONDS while a run is recording.
-- Silent by design: it exists so that nothing is lost, not so that the player
-- is told about it every half minute.
function U.PerfCheckpoint()
  if not active then return end
  SaveRun()
end

-- The hand-off block. Short, plain, and about the client rather than about
-- this addon: what was measured, on which build, how bad the tail was, whether
-- it survived the addon being silenced, and whether the network was moving at
-- the time. This is the part a player pastes into a bug report.
local function PrintHandoff(export)
  local context = export.context or {}

  U.Print("|cffffff00---- paste this to the client team ----|r")
  U.Print("build " .. tostring(context.version or "?") .. " " ..
          tostring(context.buildNumber or "?") .. " (" ..
          tostring(context.builtAt or "?") .. "), unrealUI " ..
          tostring(context.addonVersion or "?"))
  U.Print("zone " .. tostring(context.zone or "?") ..
          ", group +" .. tostring(export.groupSize or 0) ..
          ", " .. string.format("%.0f", export.recordedSeconds or 0) .. "s, " ..
          tostring(export.frameCount or 0) .. " frames")
  U.Print("frame time: mean " .. Format(export.baselineMeanMs or 0) ..
          "ms, p95 " .. tostring(export.p95Ms or "?") ..
          "ms, p99 " .. tostring(export.p99Ms or "?") ..
          "ms, worst " .. Format(export.spikeWorstMs or 0) .. "ms")
  U.Print("stutter: " .. tostring(export.spikeCount or 0) .. " spikes (" ..
          string.format("%.2f", export.spikePerSecond or 0) .. "/s), " ..
          tostring(export.spikeHardCount or 0) .. " read as freezes")

  -- The line that decides who owns the bug.
  if export.addonOffSeconds and export.addonOffSeconds > 0 then
    U.Print("with unrealUI silenced: " ..
            string.format("%.2f", export.addonOffSpikeRate or 0) ..
            " spikes/s vs " ..
            string.format("%.2f", export.addonOnSpikeRate or 0) ..
            " running  |cff888888(" ..
            string.format("%.0f", export.addonOffSeconds) .. "s off / " ..
            string.format("%.0f", export.addonOnSeconds or 0) .. "s on)|r")
  end

  if (export.netSamples or 0) > 0 then
    U.Print("latency " .. string.format("%.0f", export.latencyMeanMs or 0) ..
            "ms mean, " .. string.format("%.0f", export.latencyMaxMs or 0) ..
            "ms peak; inbound " ..
            string.format("%.1f", export.inboundKbPerSecond or 0) .. " KB/s")
  end

  if (export.gcCollections or 0) > 0 then
    U.Print("lua heap: " .. tostring(export.gcCollections) ..
            " collections, " .. tostring(export.gcSpikeCount or 0) .. " of " ..
            tostring(export.spikeCount or 0) ..
            " spikes were collection frames, " ..
            string.format("%.0f", export.allocKbPerSecond or 0) .. " KB/s")
  end

  U.Print("full data: " .. U.SavedVariablesHint() ..
          " -> UnrealUIDiagDB.perfLog")
  U.Print("|cffffff00---------------------------------------|r")
end

local function Report(handoff)
  local export, runIndex, stored, evicted = SaveRun()

  U.Print("perf: " .. (active and "|cff55ff55recording|r" or "stopped") ..
          " - " .. tostring(frameCount) .. " frames, " ..
          tostring(markCount) .. " " .. markLabel .. "s  (" ..
          SwitchLine() .. ")")

  local limit = 0
  if type(U.DiagnosticLogSize) == "function" then
    local _, cap = U.DiagnosticLogSize("perfLog")
    limit = cap or 0
  end
  U.Print("  saved as |cffffff00" .. tostring(runLabel) .. "|r" ..
          (runIndex and (" - perfLog[" .. tostring(runIndex) .. "]") or "") ..
          (stored and ("  |cff888888" .. tostring(stored) .. " of " ..
                       tostring(limit) .. " runs kept|r") or "") ..
          " - |cffffff00/reload|r to write it out")
  if evicted then
    U.Print("  |cffff5555the oldest stored run was dropped|r - the log holds " ..
            tostring(limit) .. "; |cffffff00/uui perf runs|r lists what is left")
  end

  -- The group-size table, printed first whenever the session saw more than one
  -- roster size: it is the only comparison here that does not need a cycle to
  -- have been run, and for a party-only symptom it is the answer.
  local sizesSeen, size = 0, nil
  for size = 0, group.MAX do
    if group.stats[size] and group.stats[size].frames > 0 then
      sizesSeen = sizesSeen + 1
    end
  end

  if sizesSeen > 0 then
    U.Print("  |cffffff00per group size|r (" .. tostring(group.changes) ..
            " roster changes, now " .. tostring(group.size) .. "):")

    local solo = group.stats[0]
    local soloMean = 0
    if solo and solo.frames > 0 then soloMean = solo.totalMs / solo.frames end

    for size = 0, group.MAX do
      local e = group.stats[size]
      if e and e.frames > 0 then
        local mean = e.totalMs / e.frames

        -- Against solo, which is the A/B the reporter actually performed:
        -- "fine alone, unplayable grouped" is this column being large.
        local delta = ""
        if size > 0 and soloMean > 0 then
          delta = "  |cffff9900+" .. Format(mean - soloMean) .. "ms|r"
        end

        local rate = 0
        if e.seconds > 0 then rate = e.spikes / e.seconds end

        U.Print("    +" .. tostring(size) .. ": frame " .. Format(mean) ..
                "ms" .. delta .. " (worst " .. Format(e.worstMs) .. "), " ..
                string.format("%.2f", rate) .. " spikes/s, " ..
                tostring(e.hard) .. " freeze  |cff888888" ..
                string.format("%.0f", e.seconds) .. "s|r")
      end
    end

    if sizesSeen < 2 then
      U.Print("    |cff888888one group size only - leave this recording " ..
              "across an invite or a member leaving for the comparison|r")
    end
  end

  -- The party bisect. Same shape as the per-subsystem table below, but read
  -- the other way round: every phase removes one subsystem from the
  -- reproduction, so the phase that is FASTER than "all" is the answer.
  if phaseStats["all"] then
    U.Print("  |cffffff00party bisect|r (" .. tostring(cycleRotations) ..
            " rotations, " .. tostring(CYCLE_SECONDS) .. "s per phase):")

    local reference = phaseStats["all"]
    local referenceMean = 0
    if reference.frames > 0 then
      referenceMean = reference.totalMs / reference.frames
    end

    local i
    for i = 1, table.getn(CYCLE_PARTY) do
      local key = CYCLE_PARTY[i]
      local label = (key == "all") and "all" or ("no-" .. key)
      local e = phaseStats[label]
      if e and e.frames > 0 then
        local mean = e.totalMs / e.frames
        local delta = ""
        if key ~= "all" and referenceMean > 0 then
          -- Negative is the interesting direction here: removing that
          -- subsystem made the frame shorter.
          delta = "  |cff55ff55" .. Format(mean - referenceMean) .. "ms|r"
          if mean >= referenceMean then
            delta = "  |cff888888+" .. Format(mean - referenceMean) .. "ms|r"
          end
        end
        U.Print("    " .. label .. ": frame " .. Format(mean) .. "ms" ..
                delta .. " (worst " .. Format(e.worstMs) .. "), " ..
                tostring(e.marks) .. " marks peak " ..
                Format(e.marks > 0 and (e.peakTotal / e.marks) or 0) .. "ms")
      end
    end
  end

  -- What each marked trigger actually cost. Printed whenever more than one
  -- trigger was marked, which is the default scan: one line per event beats a
  -- single averaged "peak" that silently mixes a 9ms target change with a
  -- 40ms roster event.
  local markNames, markName, markStat = {}, nil, nil
  for markName in pairs(markStats) do table.insert(markNames, markName) end
  table.sort(markNames)
  if table.getn(markNames) > 1 then
    U.Print("  |cffffff00per trigger|r:")
    local m
    for m = 1, table.getn(markNames) do
      markStat = markStats[markNames[m]]
      U.Print("    " .. markNames[m] .. ": " .. tostring(markStat.count) ..
              " marks, peak avg " ..
              Format(markStat.count > 0 and
                     (markStat.peakTotal / markStat.count) or 0) ..
              "ms, worst " .. Format(markStat.peakWorst) .. "ms")
    end
  end

  -- The addon-on / addon-off control, which is the default scan's headline.
  local onPhase, offPhase = phaseStats["on"], phaseStats["off"]
  if onPhase and offPhase and onPhase.frames > 0 and offPhase.frames > 0 then
    local onRate, offRate = 0, 0
    if onPhase.seconds > 0 then onRate = onPhase.spikes / onPhase.seconds end
    if offPhase.seconds > 0 then offRate = offPhase.spikes / offPhase.seconds end

    U.Print("  |cffffff00addon on vs off|r:")
    U.Print("    running: frame " .. Format(onPhase.totalMs / onPhase.frames) ..
            "ms, " .. string.format("%.2f", onRate) .. " spikes/s, worst " ..
            Format(onPhase.worstMs) .. "ms")
    U.Print("    silent:  frame " ..
            Format(offPhase.totalMs / offPhase.frames) .. "ms, " ..
            string.format("%.2f", offRate) .. " spikes/s, worst " ..
            Format(offPhase.worstMs) .. "ms")
    if offRate > 0 and offRate >= onRate * 0.7 then
      U.Print("    |cffff5555the stutter survives unrealUI being silenced|r " ..
              "- this is client-side evidence, not addon evidence")
    end
  end

  -- Party event traffic. The census counts every event by name; this is the
  -- share of it that arrived carrying a party unit token, which is the part
  -- that multiplies with the roster.
  if partyEventTotal > 0 then
    local top, topCount, name, count = nil, 0, nil, nil
    for name, count in pairs(partyEvents) do
      if count > topCount then top, topCount = name, count end
    end
    local perSecond = 0
    if spike.clock > 0 then perSecond = partyEventTotal / spike.clock end
    U.Print("  |cffffff00party events|r: " .. tostring(partyEventTotal) ..
            " on party tokens (" .. string.format("%.1f", perSecond) ..
            "/s)" .. (top and ("  top " .. top .. " " ..
                               tostring(topCount)) or ""))
  end

  -- The bar-count comparison, printed first when there is one: it answers a
  -- single question and the subsystem table below cannot.
  -- Collected from the recorded phases rather than from CYCLE_BARS, because a
  -- class with fewer than ten bars clamps two of those steps onto a key that
  -- is not in the list. Sorted numerically so the slope reads down the column.
  local barCounts, i = {}, nil
  for i = 1, table.getn(CYCLE_BARS) do
    local key = "bars" .. tostring(CYCLE_BARS[i])
    if phaseStats[key] then table.insert(barCounts, CYCLE_BARS[i]) end
  end
  local phaseKey, phaseEntry
  for phaseKey, phaseEntry in pairs(phaseStats) do
    local _, _, digits = string.find(phaseKey, "^bars(%d+)$")
    if digits then
      local value, seen, j = tonumber(digits), false, nil
      for j = 1, table.getn(barCounts) do
        if barCounts[j] == value then seen = true end
      end
      if not seen then table.insert(barCounts, value) end
    end
  end
  table.sort(barCounts)

  if table.getn(barCounts) > 0 then
    U.Print("  |cffffff00per bar count|r (" .. tostring(cycleRotations) ..
            " rotations, " .. tostring(CYCLE_SECONDS) .. "s per phase):")

    -- The shared Format is one decimal, which is right for a target-change
    -- peak and useless for a slope: one bar's marginal cost is expected to be
    -- a fraction of a millisecond, and rounded to 0.1ms an honest measurement
    -- reads as a column of zeroes.
    local function Fine(ms) return string.format("%.3f", ms) end

    local zero = phaseStats["bars0"]
    local zeroMean = 0
    if zero and zero.frames > 0 then zeroMean = zero.totalMs / zero.frames end

    local lastMean, lastCount = nil, nil
    for i = 1, table.getn(barCounts) do
      local count = barCounts[i]
      local e = phaseStats["bars" .. tostring(count)]
      if e and e.frames > 0 then
        local mean = e.totalMs / e.frames

        -- Cost against the control, and the marginal cost of the bars added
        -- since the previous point. The second number is the one the report
        -- exists for: a flat per-bar figure across the row means the cost is
        -- linear in buttons, which is a per-button loop; a rising one means
        -- something else grows with it.
        local total = ""
        if count > 0 and zeroMean > 0 then
          total = "  |cffff9900+" .. Fine(mean - zeroMean) .. "ms|r"
        end

        local marginal = ""
        if lastMean and count > lastCount then
          marginal = "  |cff888888" ..
                     Fine((mean - lastMean) / (count - lastCount)) ..
                     "ms/bar|r"
        end

        U.Print("    " .. tostring(count) .. " bars: frame " .. Fine(mean) ..
                "ms" .. total .. marginal .. " (worst " ..
                Format(e.worstMs) .. ")")

        -- The work census for the same phase. Frame time says how bad it is;
        -- these say what was actually executed to make it that bad, and the
        -- ratio between the two rows is what an optimisation has to move.
        local w = e.work
        if w then
          U.Print("      " .. tostring(e.visibleButtons or 0) ..
                  " buttons, gcd " .. tostring(w.gcdSweeps or 0) ..
                  " sweeps / " .. tostring(w.gcdVisits or 0) ..
                  " visits, wipe rows " .. tostring(w.rows or 0) ..
                  " -> writes " .. tostring(w.writes or 0))
          U.Print("      state+slot visits " .. tostring(w.buttonVisits or 0) ..
                  ", wipes built " .. tostring(e.builtWipes or 0) ..
                  " of " .. tostring(e.visibleButtons or 0))
        end

        lastMean, lastCount = mean, count
      end
    end
  end

  -- Per-phase comparison. This is the whole point of a cycle run, so it prints
  -- before the aggregate numbers: the aggregates mix every phase together and
  -- are meaningless while cycling.
  local ran = false
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
                tostring(e.marks) .. " marks peak " .. Format(peakAvg) ..
                "ms (worst " .. Format(e.peakWorst) .. ")")
      end
    end
  end

  -- The periodic-stutter summary, printed before the work census because it is
  -- the part a player can act on: how often the frame actually broke, how far
  -- apart the breaks were, and what was running when they happened.
  if spike.count > 0 then
    local rate = 0
    if spike.clock > 0 then rate = spike.count / spike.clock end
    U.Print("  |cffffff00spikes|r: " .. tostring(spike.count) ..
            " frames over " .. Format(spike.FACTOR) .. "x baseline (" ..
            tostring(spike.hard) .. " over " .. Format(spike.HARD) ..
            "x), worst " .. Format(spike.worstMs) .. "ms, " ..
            string.format("%.2f", rate) .. "/s")

    local mean, low, high = spike.Gaps()
    if mean then
      U.Print("    gap between spikes: mean " ..
              string.format("%.2f", mean) .. "s (min " ..
              string.format("%.2f", low) .. "s, max " ..
              string.format("%.2f", high) .. "s)")
    end

    -- The verdict line. A collection pause is not something any single
    -- updater is "in", so this is printed before the per-updater shares: those
    -- shares are dominated by whatever runs every frame and mean little once
    -- the collector is the answer.
    if spike.collections > 0 then
      U.Print("    |cffffff00heap|r: " .. tostring(spike.collections) ..
              " collections, " .. tostring(spike.gcSpikes) .. " of " ..
              tostring(spike.count) .. " spikes were collection frames" ..
              (spike.gcGapCount > 0 and ("  (every " ..
               string.format("%.2f", spike.gcGapTotal / spike.gcGapCount) ..
               "s)") or ""))
      local rate = 0
      if spike.clock > 0 then rate = spike.allocKb / spike.clock end
      U.Print("    allocation " .. string.format("%.0f", rate) ..
              " KB/s, heap now " .. tostring(spike.kb or 0) .. " KB")
    end

    local bestId, bestHits, nextId, nextHits = spike.Worst()
    if bestId then
      U.Print("    in spikes: " .. bestId .. " " ..
              tostring(math.floor(bestHits / spike.count * 100 + 0.5)) .. "% (" ..
              tostring(bestHits) .. " of " .. tostring(spike.count) ..
              ", fired " .. tostring(spike.updaterFires[bestId] or 0) ..
              "x total)")
    end
    if nextId then
      U.Print("               " .. nextId .. " " ..
              tostring(math.floor(nextHits / spike.count * 100 + 0.5)) .. "% (" ..
              tostring(nextHits) .. " of " .. tostring(spike.count) ..
              ", fired " .. tostring(spike.updaterFires[nextId] or 0) ..
              "x total)")
    end
    U.Print("    full per-updater table is in the file; |cffffff00/reload|r " ..
            "to write it out")
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
      -- The stock aura slots specifically: how many are watched, and how often
      -- the client had written an icon back into one this adapter had already
      -- cleared. A non-zero re-clear count is the native aura block being
      -- caught mid-session rather than only on a target change.
      U.Print("  stock aura slots: " .. tostring(stats.auraNames) ..
              " watched, " .. tostring(stats.auraRecleared) ..
              " re-cleared this session")
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
    U.Print("  no completed " .. markLabel .. " samples yet - produce a few, " ..
            "then |cffffff00/uui perf|r again")
    if handoff then PrintHandoff(export) end
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

  U.Print("  " .. markLabel .. " peak: avg " .. Format(peakTotal / count) ..
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

  if handoff then PrintHandoff(export) end
end

-- ---------------------------------------------------------------------------
-- The stored runs
--
-- Reading the log back in game rather than only out of the file: a player
-- taking an A/B needs to know that both halves are still there BEFORE the
-- reload that writes them, and the cap is only reached silently if nothing
-- ever prints it.
-- ---------------------------------------------------------------------------
local function ListRuns()
  local list = nil
  if type(UnrealUIDiagDB) == "table" then list = UnrealUIDiagDB.perfLog end
  if type(list) ~= "table" or table.getn(list) == 0 then
    U.Print("perf: no stored runs yet")
    return
  end

  local limit = 0
  if type(U.DiagnosticLogSize) == "function" then
    local _, cap = U.DiagnosticLogSize("perfLog")
    limit = cap or 0
  end

  U.Print("perf: |cffffff00" .. tostring(table.getn(list)) .. "|r stored run" ..
          (table.getn(list) == 1 and "" or "s") .. " of " .. tostring(limit) ..
          "  (UnrealUIDiagDB.perfLog)")

  local i
  for i = 1, table.getn(list) do
    local entry = list[i]
    if type(entry) == "table" then
      local frames = tonumber(entry.frameCount) or 0
      local seconds = tonumber(entry.recordedSeconds) or 0
      local mean = tonumber(entry.baselineMeanMs) or 0
      local spikes = tonumber(entry.spikeCount) or 0

      U.Print("  [" .. tostring(i) .. "] " ..
              tostring(entry.run or entry.mode or "?") ..
              "  |cff888888" .. tostring(entry.savedAt or "?") .. "|r" ..
              (entry.stopped and "" or "  |cffff5555(unfinished)|r"))
      U.Print("      " .. tostring(frames) .. " frames / " ..
              string.format("%.0f", seconds) .. "s, baseline " ..
              Format(mean) .. "ms, " .. tostring(spikes) .. " spikes, " ..
              tostring(tonumber(entry.markCount) or 0) .. " " ..
              tostring(entry.markEvent or "mark") .. "s" ..
              (entry.groupSize and ("  group " .. tostring(entry.groupSize))
                                or ""))
    end
  end

  U.Print("  |cffffff00/reload|r writes them out; " ..
          "|cffffff00/uui perf clear|r empties the log")
end

-- Deliberate and explicit: nothing else in this file ever removes a stored
-- run, so the only way to lose one is the cap or this command.
local function ClearRuns()
  local count = 0
  if type(UnrealUIDiagDB) == "table" and type(UnrealUIDiagDB.perfLog) == "table" then
    count = table.getn(UnrealUIDiagDB.perfLog)
    UnrealUIDiagDB.perfLog = {}
  end
  -- The current run has no slot any more, so its next report starts a new one
  -- rather than writing into an index that no longer means anything.
  if runId then NewRunId(runLabel) end
  U.Print("perf: cleared |cffffff00" .. tostring(count) ..
          "|r stored run" .. (count == 1 and "" or "s") ..
          " - |cffffff00/reload|r to write that out")
end

-- ---------------------------------------------------------------------------
-- Command surface (dispatched by core/commands.lua)
-- ---------------------------------------------------------------------------
local function ShowUsage()
  U.Print("perf: |cffffff00/uui perf start|r ... play ... " ..
          "|cffffff00/uui perf stop|r, then |cffffff00/reload|r. That is the " ..
          "whole scan.")
  U.Print("  |cffffff00/uui perf|r - report so far, " ..
          "|cffffff00reset|r - restart the counters, " ..
          "|cffffff00manual|r - record without the on/off control")
  U.Print("  |cffffff00/uui perf cycle|r - enable one subsystem at a time, " ..
          tostring(CYCLE_SECONDS) .. "s each, and compare them")
  U.Print("  |cffffff00/uui perf levels|r - walk suppression level 0-4 in one " ..
          "run (needs |cffffff00/uui suppress 0|r + reload first)")
  U.Print("  |cffffff00/uui perf bars|r - walk 0-10 action bars in one run; " ..
          "stay in combat and keep casting")
  U.Print("  |cffffff00/uui perf party|r - party bisect: marks roster events, " ..
          "removes one party subsystem at a time")
  U.Print("  |cffffff00/uui perf group|r - group-size census only, no " ..
          "switching; leave it on across an invite")
  U.Print("  bisect (toggle one, change target again, re-read the peak):")
  local i, line = nil, ""
  for i = 1, table.getn(SWITCH_ORDER) do
    if line == "" then line = SWITCH_ORDER[i]
    else line = line .. ", " .. SWITCH_ORDER[i] end
  end
  U.Print("    |cffffff00/uui perf <name>|r - " .. line)
  U.Print("  |cffffff00/uui perf runs|r - list the stored runs, " ..
          "|cffffff00clear|r - empty the log")
  U.Print("  every run keeps its own slot in UnrealUIDiagDB.perfLog; " ..
          "reporting the same run twice never costs a second one")
  U.Print("  switches are never saved; |cffffff00/reload|r restores everything")
end

-- Every start goes through this, so no run can inherit the previous run's
-- trigger: markCount and the peak column always describe the event named in
-- the same report.
local function SetMarks(party)
  if party == nil then
    markSet, markLabel = BOTH_MARK, "marked event"
  elseif party then
    markSet, markLabel = PARTY_MARK, "roster event"
  else
    markSet, markLabel = MARK, "target change"
  end
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
  -- The party bisect. Roster events instead of target changes, leave-one-out
  -- instead of one-on, and the group-size census running underneath it the
  -- whole time (that one needs no mode at all -- it records on every run).
  if argument == "party" then
    ResetState()
    NewRunId("party")
    SetMarks(true)
    active = true
    U.perfActive = true
    cycleMode = "party"
    cycleActive = true
    cycleIndex = 0
    AdvanceCycle()
    U.Print("perf: |cff55ff55party bisect|r - |cffffff00stay in the group and " ..
            "play normally|r (move, fight, heal). Each phase removes one " ..
            "subsystem for " .. tostring(CYCLE_SECONDS) .. "s.")
    U.Print("  the phase where the freeze stops is the answer; then " ..
            "|cffffff00/uui perf stop|r and |cffffff00/reload|r")
    if group.size == 0 then
      U.Print("  |cffff5555you are not in a group|r - this run measures " ..
              "nothing until you are")
    end
    return
  end

  -- Census only: no switching, no subsystem removed, nothing to restore. This
  -- is the one to leave running across an invite or a disband, because the
  -- comparison it produces is between roster sizes rather than between
  -- phases, and a cycle rotating underneath it would mix the two.
  if argument == "group" then
    ResetState()
    NewRunId("group")
    SetMarks(true)
    AllSwitchesOn()
    active = true
    U.perfActive = true
    cycleActive = false
    cycleMode = "switches"
    currentPhase = "manual"
    U.Print("perf: |cff55ff55group census|r - play normally, solo and grouped. " ..
            "Frame time is charged to the roster size it was rendered at.")
    U.Print("  |cffffff00/uui perf|r for the table, then |cffffff00/reload|r " ..
            "to write it out")
    return
  end

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
    NewRunId("levels")
    SetMarks(false)
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

  -- The bar-count run. Every bar is constructed once up front: a bar enabled
  -- for the first time builds twelve buttons, and that one-off construction
  -- landing inside a timed phase would be charged to that bar count as if it
  -- were a recurring cost.
  if argument == "bars" then
    if type(U.SetActionBarSetting) ~= "function" then
      U.Print("perf bars: action bar module not loaded")
      return
    end

    ResetState()
    NewRunId("bars")
    SetMarks(false)
    barsRestore = CaptureBarState()
    if not barsRestore then
      U.Print("perf bars: no available bars to cycle")
      return
    end

    ApplyBarCount(table.getn(BarIds()))
    ResetPhaseWork()

    active = true
    U.perfActive = true
    cycleMode = "bars"
    cycleActive = true
    cycleIndex = 0
    AdvanceCycle()
    U.Print("perf: |cff55ff55bar count|r - |cffffff00stay in combat and keep " ..
            "casting|r so the global-cooldown sweep is actually running; " ..
            "each count gets " .. tostring(CYCLE_SECONDS) .. "s.")
    U.Print("  let it run several rotations, then |cffffff00/uui perf stop|r " ..
            "and |cffffff00/reload|r - your own bars come back at stop")
    return
  end

  if argument == "cycle" then
    ResetState()
    NewRunId("cycle")
    SetMarks(false)
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

  -- The whole workflow, in one command. Everything the other modes do
  -- separately that does not need the player to behave in a particular way
  -- happens here at once: the group-size census, the frame-time distribution,
  -- the world-session sampling, roster and target marks together, and an
  -- alternating addon-on / addon-off control so the run can say whether the
  -- stutter is ours at all. The player starts it, plays normally, and stops it.
  if argument == "start" or argument == "on" then
    ResetState()
    NewRunId("scan")
    SetMarks(nil)
    active = true
    U.perfActive = true
    cycleMode = "scan"
    cycleActive = true
    cycleIndex = 0
    AdvanceCycle()
    U.Print("perf: |cff55ff55scanning|r - |cffffff00just play normally|r " ..
            "(move, fight, group up). Everything is recorded automatically.")
    U.Print("  unrealUI alternates " .. tostring(SCAN_WINDOW) ..
            "s running / " .. tostring(SCAN_WINDOW) ..
            "s silent so the run can prove whether the stutter is the addon " ..
            "or the client - the UI going quiet is meant to happen")
    U.Print("  |cffffff00/uui perf stop|r when done, then " ..
            "|cffffff00/reload|r. Runs are kept, not overwritten.")
    return
  end

  -- The old plain recorder, kept for a targeted measurement: no switching, no
  -- control window, target-change marks only.
  if argument == "manual" then
    ResetState()
    NewRunId("manual")
    SetMarks(false)
    active = true
    U.perfActive = true
    cycleActive = false
    currentPhase = "manual"
    U.Print("perf: |cff55ff55recording|r (manual, nothing switched) - " ..
            "change target several times, then |cffffff00/uui perf|r")
    return
  end

  if argument == "stop" or argument == "off" then
    -- The phase in progress has not been charged yet -- AdvanceCycle does that
    -- on the way out of a phase, and stopping never reaches one.
    if cycleActive and cycleMode == "bars" then CollectPhaseWork(currentPhase) end
    -- Cleared before the report, not after: the report is what writes the run
    -- into the log, and a finished run stored as unfinished would tell a
    -- reader the data was cut off when it was not.
    active = false
    U.perfActive = false
    Report(true)
    -- A cycle leaves four subsystems switched off; stopping must not strand the
    -- player's UI in a diagnostic state.
    if cycleActive then
      cycleActive = false
      AllSwitchesOn()
      if cycleMode == "bars" then
        RestoreBarState()
        U.Print("perf: bar run ended, your own bars restored")
      elseif cycleMode == "scan" then
        U.Print("perf: scan ended, unrealUI running normally again")
      elseif cycleMode == "party" then
        U.Print("perf: party bisect ended, all subsystems restored")
      elseif cycleMode == "levels" and U.db then
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

  if argument == "runs" or argument == "log" then
    ListRuns()
    return
  end

  if argument == "clear" then
    ClearRuns()
    return
  end

  if argument == "reset" then
    -- A cleared recorder is a different run: it must not keep writing over the
    -- slot whose numbers it just discarded.
    ResetState()
    NewRunId(runLabel)
    U.Print("perf: counters cleared, now recording as |cffffff00" ..
            tostring(runLabel) .. "|r")
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
