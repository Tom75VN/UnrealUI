-- unrealUI :: core/mover.lua
--
-- The shared mover system. Modules register the frames they want the user to
-- be able to place; unlocking shows a drag handle over each one.
--
-- Deliberately small. This is not pfUI's mover/config framework: it provides
-- only an alignment grid, nearby-mover magnets and pixel nudging -- no
-- per-frame scale editing or configuration machinery. Only intended unrealUI
-- elements are ever registered. Explicitly requested native widgets use either
-- their native root (modules/minimap.lua) or an unrealUI-owned placement anchor
-- (modules/durabilityframe.lua); their artwork and visibility remain
-- client-owned.

local U = UnrealUI
local M = U.media

local movers = {}       -- id -> entry
local moverOrder = {}
local unlocked = false
local activeMover
-- Snap tracer state. One table rather than a set of loose locals, per
-- rules/unreal-ui.md: a diagnostic has no business spending top-level slots.
local trace = { on = false, samples = {}, max = 400, seq = 0, dropped = 0,
                current = nil, startedAt = nil, reason = nil, before = nil,
                -- Diagnostic logs beside the snap samples: what the mouse is
                -- over, anchors that move on their own, and store writes.
                focus = {}, drift = {}, events = {}, rects = {},
                maxLog = 300, lastFocus = nil, nextDrift = 0,
                lockedAt = nil, afterLock = nil, LOCK_WATCH = 20 }
local grid, editPanel, editKeys, alignmentGuides
local IsEntryAvailable, IsEntryVisible
local UpdateAlignmentGuides, HideAlignmentGuides
local advanced = {
  width = 350,
  height = 260,
  closedWidth = 1,
  duration = 0.22,
  currentWidth = 1,
  open = false,
  rows = {},
  hiddenEntries = {},
  hiddenCount = 0,
  groupLookup = {},
  -- One callback per group key: the module that owns an element registers it
  -- so its own views re-read the switch this drawer just wrote.
  changed = {},
  rowsPerColumn = 11,
  columnWidth = 162,
  groups = {
    { key = "petbar", labelKey = "MOVER_LABEL_PET_BAR",
      movers = { "petbar" } },
    { key = "petunit", labelKey = "MOVER_LABEL_PET_UNIT_FRAME",
      movers = { "unitframes.pet", "castbar.pet" } },
    { key = "buffs", labelKey = "MOVER_LABEL_BUFFS",
      nativeAuras = true, movers = { "buffs" } },
    { key = "swingbar", labelKey = "MOVER_LABEL_SWING_BAR",
      setting = { module = "swingbar", key = "enabled", default = true,
                  apply = "ApplySwingBar" }, movers = { "swingbar" } },
    { key = "targettarget", labelKey = "MOVER_LABEL_TARGET_TARGET",
      movers = { "unitframes.targettarget" } },
    { key = "targetcast", labelKey = "MOVER_LABEL_TARGET_CASTBAR",
      movers = { "castbar.target" } },
    { key = "xpbar", labelKey = "MOVER_LABEL_XP_BAR",
      movers = { "xpbar.xp" } },
    { key = "repbar", labelKey = "MOVER_LABEL_REP_BAR",
      setting = { module = "xpbar", key = "repEnabled", default = true,
                  apply = "ApplyXPBar" }, movers = { "xpbar.reputation" } },
    { key = "status", labelKey = "MOVER_LABEL_STATUS",
      movers = { "status.overlay" } },
    { key = "online", labelKey = "MOVER_LABEL_ONLINE_COUNT",
      movers = { "status.population" } },
    { key = "microbar", labelKey = "MOVER_LABEL_MICRO_BAR",
      setting = { module = "microbar", key = "enabled", default = true,
                  apply = "ApplyMicroBar" }, movers = { "microbar" } },
    { key = "actionbar1", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 1,
      actionBar = 1, movers = { "actionbar.bar1", "actionbar.native1" } },
    { key = "actionbar2", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 2,
      actionBar = 2, movers = { "actionbar.bar2" } },
    { key = "actionbar3", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 3,
      actionBar = 3, movers = { "actionbar.bar3" } },
    { key = "actionbar4", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 4,
      actionBar = 4, movers = { "actionbar.bar4" } },
    { key = "actionbar5", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 5,
      actionBar = 5, movers = { "actionbar.bar5" } },
    { key = "actionbar6", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 6,
      actionBar = 6, movers = { "actionbar.bar6" } },
    { key = "actionbar7", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 7,
      actionBar = 7, movers = { "actionbar.bar7" } },
    { key = "actionbar8", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 8,
      actionBar = 8, movers = { "actionbar.bar8" } },
    { key = "actionbar9", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 9,
      actionBar = 9, movers = { "actionbar.bar9" } },
    { key = "actionbar10", labelKey = "MOVER_LABEL_ACTION_BAR", labelArg = 10,
      actionBar = 10, movers = { "actionbar.bar10" } },
  },
  moverKeys = {
    petbar = "petbar",
    ["unitframes.pet"] = "petunit",
    ["castbar.pet"] = "petunit",
    buffs = "buffs",
    swingbar = "swingbar",
    ["unitframes.targettarget"] = "targettarget",
    ["castbar.target"] = "targetcast",
    ["xpbar.xp"] = "xpbar",
    ["xpbar.reputation"] = "repbar",
    ["status.overlay"] = "status",
    ["status.population"] = "online",
    microbar = "microbar",
    ["actionbar.bar1"] = "actionbar1",
    ["actionbar.native1"] = "actionbar1",
    ["actionbar.bar2"] = "actionbar2",
    ["actionbar.bar3"] = "actionbar3",
    ["actionbar.bar4"] = "actionbar4",
    ["actionbar.bar5"] = "actionbar5",
    ["actionbar.bar6"] = "actionbar6",
    ["actionbar.bar7"] = "actionbar7",
    ["actionbar.bar8"] = "actionbar8",
    ["actionbar.bar9"] = "actionbar9",
    ["actionbar.bar10"] = "actionbar10",
  },
  moverActionBars = {
    ["actionbar.bar1"] = 1, ["actionbar.native1"] = 1,
    ["actionbar.bar2"] = 2,
    ["actionbar.bar3"] = 3, ["actionbar.bar4"] = 4,
    ["actionbar.bar5"] = 5, ["actionbar.bar6"] = 6,
    ["actionbar.bar7"] = 7, ["actionbar.bar8"] = 8,
    ["actionbar.bar9"] = 9, ["actionbar.bar10"] = 10,
  },
}

-- Frames that are drag-placed outside this system still store their position
-- through U.SavePosition, so /uui reset has to be able to put them back. They
-- register a callback rather than a mover entry because their default anchor
-- is not UIParent-relative and cannot be expressed as a mover default -- the
-- minimap settings button sits beside Minimap, not at a screen coordinate.
local resetHooks = {}

-- Edit-mode grid. Sized in UIParent units, which is the only space layout may
-- be driven from (frames.json context: GetScreenWidth and UIParent:GetWidth are
-- not the same unit space on this client).
local DEFAULT_GRID_SIZE = 20
local MIN_GRID_SIZE = 5
local MAX_GRID_SIZE = 50
local MAGNET_DISTANCE = 8
local ALIGNMENT_EPSILON = 0.01

local function MoverConfig()
  return U.ModuleConfig("mover", {
    gridShown = true,
    gridSize = DEFAULT_GRID_SIZE,
    magnet = true,
    -- Anchors that touch travel as one block. Off moves the anchor under the
    -- cursor and nothing else, for placing a single element out of a stack.
    -- Off by default.
    groupTouching = false,
    anchorEnabled = {},
  })
end

local function GridSize()
  local size = tonumber(MoverConfig().gridSize) or DEFAULT_GRID_SIZE
  size = math.floor(size + 0.5)
  if size < MIN_GRID_SIZE then size = MIN_GRID_SIZE end
  if size > MAX_GRID_SIZE then size = MAX_GRID_SIZE end
  return size
end

-- ---------------------------------------------------------------------------
-- Position handling
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted (BEHAVIOR_VERIFIED)
-- is the whole reason this file reads anchors through U.GetFramePoint: GetPoint
-- hands back the relative frame as a name string and inverts Y. That record
-- also lists two failed approaches, both avoided here:
--
--   * persisting the raw GetPoint tuple as if it were Blizzard-compatible
--   * recapturing a point and immediately clearing/re-applying it
--
-- so a drop is captured and stored, and the frame is left exactly where the
-- user released it rather than being re-anchored on the spot.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Bottom-anchored windows
--
-- A window whose height follows its content grows away from the point it is
-- anchored by, so one the client left on a TOP* corner pushes its lower rows
-- off the bottom of the screen as it gets taller. The bag's category view is
-- the first UnrealUI window that changes height this way. anchorEdge =
-- "BOTTOM" pins such a frame by its bottom edge instead, so it can only ever
-- extend upwards, and the converted point is stored so a reload keeps it.
--
-- The conversion is done in screen space rather than by arithmetic over the
-- stored offsets: GetLeft/GetBottom report where the frame actually is, so one
-- expression covers whichever of the eight point names a drag was collapsed
-- onto, with no second Y convention to get wrong. Reading a rect and then
-- applying a stored-shaped point is the direction knowledge.json /
-- frames.getpoint_relative_name_y_inverted confirms works; the failed approach
-- that record warns about -- recapturing through GetPoint and immediately
-- re-applying that same tuple -- is not what happens here.
-- ---------------------------------------------------------------------------
local BOTTOM_POINTS = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function Edge(frame, method)
  local fn = frame and frame[method]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, frame)
  if not ok then return nil end
  return tonumber(value)
end

-- How much bigger than UIParent's scale a mover's frame is drawn.
--
-- DIAGNOSTIC ONLY. Nothing in the placement maths may use it, because this
-- client does NOT work the way retail does. `/uui movesnap`, on the
-- modern-wow cast bar (own scale 0.75, UIParent at 1), measured:
--
--   * SetWidth(230) then GetWidth() -> 172.5. Reported size is the frame's
--     own size ALREADY multiplied by its own scale.
--   * SetPoint(TOPLEFT, UIParent, TOPLEFT, x, y) then GetLeft() -> exactly x,
--     and GetBottom() + GetHeight() -> exactly UIParent's height + y. The
--     offsets are NOT divided by the frame's scale, and the relative point is
--     not converted into the frame's space either.
--
-- So a frame's own scale resizes it about its anchor point and changes nothing
-- else: stored offsets, GetLeft/GetBottom and GetWidth/GetHeight are all in
-- UIParent's units for every mover, scaled or not, and the placement maths in
-- this file needs no conversion at all. An earlier revision assumed retail's
-- model and multiplied the bounds through this ratio; on a 0.75 cast bar that
-- put its rectangle 192 units (UIHeight * 0.25) above the bar the player sees,
-- which made it collide with the party block it was merely near and threw it
-- several grid cells. Do not reintroduce that without new measurements.
local function EntryScale(entry)
  local frame = entry and entry.frame
  if not frame then return 1 end

  local ok, scale = pcall(frame.GetEffectiveScale, frame)
  local uiOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
  scale, uiScale = tonumber(scale), tonumber(uiScale)
  if not ok or not uiOk or not scale or not uiScale or
     scale <= 0 or uiScale <= 0 then return 1 end
  return scale / uiScale
end

local function NormaliseAnchorEdge(entry)
  if not entry or entry.anchorEdge ~= "BOTTOM" then return end

  -- Already growing upwards: a frame held by any bottom point keeps its bottom
  -- edge when it is resized, which is the whole point of the conversion.
  local stored = U.GetPosition(entry.id)
  local active = stored or entry.default
  if active and BOTTOM_POINTS[active.point] then return end

  local left = Edge(entry.frame, "GetLeft")
  local bottom = Edge(entry.frame, "GetBottom")
  if not left or not bottom then
    -- A frame registered during load can have no resolved rect yet, and this
    -- runs from RegisterMover. Failing quietly there would leave the window
    -- top-anchored for the whole session, so retry once on the next
    -- shared-driver tick before giving up.
    if entry.anchorEdgeRetried then
      U.Debug("mover " .. entry.id .. ": no readable rect to bottom-anchor")
      return
    end
    entry.anchorEdgeRetried = true

    local update = "mover.anchorEdge." .. entry.id
    U.RegisterUpdate(update, 0, function()
      U.UnregisterUpdate(update)
      NormaliseAnchorEdge(entry)
    end)
    return
  end

  -- UIParent's origin is subtracted rather than assumed to be (0, 0), so a
  -- client that does not place it flush with the screen corner still converts
  -- to the right offsets. Both sides are in UIParent's units whatever the
  -- frame's own scale is -- see EntryScale for the measurement.
  local x = left - (Edge(UIParent, "GetLeft") or 0)
  local y = bottom - (Edge(UIParent, "GetBottom") or 0)

  if not U.ApplyFramePoint(entry.frame, {
       point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y }) then
    U.Debug("mover " .. entry.id .. ": failed to apply bottom anchor")
    return
  end

  -- Only a position the player actually placed is written back. A frame still
  -- sitting on its default is re-derived from that default on every login, so
  -- persisting one here would invent a saved placement nobody made.
  if stored then
    U.SavePosition(entry.id, "BOTTOMLEFT", "BOTTOMLEFT", x, y)
  end
end

local function ApplyStoredPosition(entry)
  local saved = U.GetPosition(entry.id)
  local position = saved or entry.default
  if not position then return false end
  -- A placement stored on a larger screen or UI scale is pulled back inside
  -- this one (core/screenguard.lua). Applied only, not re-saved: going back to
  -- the larger screen restores the original placement.
  position = U.ClampPositionToScreen(entry.frame, position)

  local applied = U.ApplyFramePoint(entry.frame, position)
  if not applied then
    U.Debug("mover " .. entry.id .. ": failed to apply position")
    return false
  end

  if saved then
    U.Debug("mover " .. entry.id .. ": restored saved position")
  end
  trace.Event("apply", entry, position, { fromSaved = saved and true or false })

  NormaliseAnchorEdge(entry)
  return true
end

-- Snapping
--
-- The live drag path derives its unconstrained position from the cursor delta
-- at the start of the drag, then applies grid and magnet constraints on the
-- shared driver. Keeping that original cursor origin is important: restarting
-- StartMoving after every snap would continually rebase the grab offset and
-- leave a frame stuck on its first grid line.
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted lists "recapturing
-- then immediately clearing/reapplying the same point" as a failed approach,
-- while the same record confirms that applying a *stored* point with SetPoint
-- restores a frame correctly. The final drop is still captured, stored, and
-- re-applied on the next shared-driver tick; live feedback applies a newly
-- calculated cursor-relative point rather than replaying a raw GetPoint tuple.
local pendingSnap

local function SnapValue(value)
  value = tonumber(value) or 0
  local size = GridSize()
  return math.floor(value / size + 0.5) * size
end

-- Magnetic snapping uses the stored UIParent-relative positions and frame
-- dimensions, never GetLeft/GetRight/GetTop/GetBottom. The latter give mixed
-- coordinate spaces for scaled frames on this client, whereas mover positions
-- and dimensions are already in UIParent's layout space.
local function PointFactor(point, low, high)
  if type(point) ~= "string" then return 0.5 end
  if string.find(point, low, 1, true) then return 0 end
  if string.find(point, high, 1, true) then return 1 end
  return 0.5
end

local function MoverBounds(entry, position)
  if not entry or type(position) ~= "table" then return nil end

  local widthOk, width = pcall(entry.frame.GetWidth, entry.frame)
  local heightOk, height = pcall(entry.frame.GetHeight, entry.frame)
  width, height = tonumber(width), tonumber(height)
  if not widthOk or not heightOk or not width or not height or
     width <= 0 or height <= 0 then return nil end

  -- Offsets and dimensions are already in UIParent's units for every mover,
  -- scaled or not (EntryScale records the measurement), so this rectangle is
  -- built from them directly.
  local x = tonumber(position.x) or 0
  local y = tonumber(position.y) or 0
  local relativePoint = position.relativePoint or position.point
  local left = U.UIWidth() * PointFactor(relativePoint, "LEFT", "RIGHT") + x -
               width * PointFactor(position.point, "LEFT", "RIGHT")
  local bottom = U.UIHeight() * PointFactor(relativePoint, "BOTTOM", "TOP") + y -
                 height * PointFactor(position.point, "BOTTOM", "TOP")
  return left, left + width, bottom, bottom + height
end

local function IntervalsNear(aLow, aHigh, bLow, bHigh)
  return aLow <= bHigh + MAGNET_DISTANCE and
         aHigh >= bLow - MAGNET_DISTANCE
end

-- Edges that touch are not an overlap. The tolerance matters: a flush magnet
-- snap reproduces the neighbour's edge through float arithmetic, and a
-- hundredth over read as a collision would push the anchor back out.
local function Overlaps(left, right, bottom, top,
                        otherLeft, otherRight, otherBottom, otherTop)
  return left < otherRight - ALIGNMENT_EPSILON and
         right > otherLeft + ALIGNMENT_EPSILON and
         bottom < otherTop - ALIGNMENT_EPSILON and
         top > otherBottom + ALIGNMENT_EPSILON
end

local function ClosestDelta(candidate, best, bestDistance)
  local distance = math.abs(candidate)
  if distance <= MAGNET_DISTANCE and distance < bestDistance then
    return candidate, distance
  end
  return best, bestDistance
end

-- Where a frame is, as { point, relative, relativePoint, x, y }. Offsets come
-- from its measured edges (U.GetFramePlacement, core/screenguard.lua), never
-- from GetPoint: knowledge.json / frames.getpoint_y_same_sign_as_setpoint
-- (2026-09-17) shows GetPoint keeps SetPoint's Y sign, so U.GetFramePoint's
-- negation mirrored the drag origin -- a TOPLEFT y = -683 bar started its drag
-- at +683 and the screen clamp pinned it to the top edge.
--
-- A frame parented elsewhere but anchored to UIParent is measured by its edges
-- too, when it is drawn at UIParent's scale (so its edges and its offsets share
-- one unit). /uui movesnap 2026-09-17: target-of-target is a child of
-- UnrealUIUnitTarget; after PinToUIParent its BOTTOMLEFT point read back with
-- the negated Y (-244 for a bottom at 244), the screen clamp lifted that to 0,
-- and every drop saved y = 0 -- the frame fell to the bottom of the screen.
-- Only a differently scaled or non-UIParent-anchored frame still falls back to
-- the point read.
local function ReadPlacement(frame)
  local placement = U.GetFramePlacement(frame)
  if placement then
    placement.relative = UIParent
    return placement
  end
  local point, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
  if not point then return nil end
  relativePoint = relativePoint or point

  local frameScale = Edge(frame, "GetEffectiveScale")
  local uiScale = Edge(UIParent, "GetEffectiveScale")
  local left, bottom = Edge(frame, "GetLeft"), Edge(frame, "GetBottom")
  local width, height = Edge(frame, "GetWidth"), Edge(frame, "GetHeight")
  if (not relative or relative == UIParent) and frameScale and uiScale and
     math.abs(frameScale - uiScale) < 0.001 and left and bottom and
     width and height then
    left = left - (Edge(UIParent, "GetLeft") or 0)
    bottom = bottom - (Edge(UIParent, "GetBottom") or 0)
    x = left + width * PointFactor(point, "LEFT", "RIGHT") -
        U.UIWidth() * PointFactor(relativePoint, "LEFT", "RIGHT")
    y = bottom + height * PointFactor(point, "BOTTOM", "TOP") -
        U.UIHeight() * PointFactor(relativePoint, "BOTTOM", "TOP")
  end
  return { point = point, relative = relative,
           relativePoint = relativePoint, x = x, y = y }
end

local function EntryPosition(entry)
  local position = U.GetPosition(entry.id) or entry.default
  if position then return position end

  local placement = ReadPlacement(entry.frame)
  if not placement or (placement.relative and
                       placement.relative ~= UIParent) then return nil end
  return placement
end

-- Bounds of a registered mover in UIParent layout space, as MoverBounds
-- computes them: the same space every other placement decision in this file is
-- made in. Exported so a contextual panel can be placed beside an anchor
-- without repeating the point-factor maths, or reading GetLeft/GetRight, which
-- this client reports in a mixed space for scaled frames.
function U.MoverBounds(id)
  local entry = type(id) == "string" and movers[id] or nil
  if not entry then return nil end
  return MoverBounds(entry, EntryPosition(entry))
end

-- The unrealUI-owned frame a mover is registered on. Exported so
-- core/moversample.lua can draw an empty anchor's placeholder inside it
-- without every module having to hand its own frame over a second time.
function U.MoverFrame(id)
  local entry = type(id) == "string" and movers[id] or nil
  return entry and entry.frame or nil
end

-- ---------------------------------------------------------------------------
-- Snap tracer
--
-- Armed before edit mode opens (`/uui movesnap`) because no slash command can
-- be typed while the overlay is up, and disarmed automatically by U.LockUI, so
-- one gesture is recorded end to end without the player leaving edit mode.
--
-- It answers one question: does the rectangle the snapper reasons about match
-- the one the player sees? Every sample therefore carries both -- the
-- UIParent-space rect MoverBounds computes from the stored offsets, and the
-- rect the client reports for the live frame (GetLeft/GetBottom/GetWidth/
-- GetHeight, converted through the frame's own effective scale). The two agree
-- for every mover drawn at UIParent's scale; where a theme scales a frame they
-- are the whole diagnosis.
--
-- Write-only, capped, and never read back by the addon: UnrealUIDiagDB is the
-- established channel for this (core/commands.lua).
-- ---------------------------------------------------------------------------
local function Rounded(value)
  value = tonumber(value)
  if not value then return nil end
  return math.floor(value * 100 + 0.5) / 100
end

-- The rect the client actually draws, in UIParent units -- which is what
-- GetLeft/GetBottom/GetWidth/GetHeight report for every frame, scaled or not
-- (EntryScale carries the measurement that established this).
local function LiveRect(entry)
  local frame = entry and entry.frame
  if not frame then return nil end

  local left = Edge(frame, "GetLeft")
  local bottom = Edge(frame, "GetBottom")
  local width = Edge(frame, "GetWidth")
  local height = Edge(frame, "GetHeight")
  if not left or not bottom or not width or not height then return nil end

  left = left - (Edge(UIParent, "GetLeft") or 0)
  bottom = bottom - (Edge(UIParent, "GetBottom") or 0)
  return left, left + width, bottom, bottom + height
end

function trace.Name(frame)
  if frame == nil then return "none" end
  if frame == UIParent then return "UIParent" end
  if type(frame) == "string" then return frame end
  if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
    return "?"
  end
  local ok, name = pcall(frame.GetName, frame)
  if ok and type(name) == "string" then return name end
  return "unnamed"
end

-- Layering and hit-test state of one widget: the answer to "why can this
-- handle not be clicked" is in strata, level, visibility, mouse and rect.
function trace.Widget(frame)
  if not frame then return nil end
  local row = { name = trace.Name(frame) }
  local left, bottom = Edge(frame, "GetLeft"), Edge(frame, "GetBottom")
  local width, height = Edge(frame, "GetWidth"), Edge(frame, "GetHeight")
  row.l, row.b = Rounded(left), Rounded(bottom)
  row.w, row.h = Rounded(width), Rounded(height)
  row.level = Edge(frame, "GetFrameLevel")
  row.points = Edge(frame, "GetNumPoints")
  row.effScale = Rounded(Edge(frame, "GetEffectiveScale"))

  local ok, value = pcall(frame.IsShown, frame)
  if ok then row.shown = value and true or false end
  if type(frame.IsVisible) == "function" then
    ok, value = pcall(frame.IsVisible, frame)
    if ok then row.visible = value and true or false end
  end
  if type(frame.GetFrameStrata) == "function" then
    ok, value = pcall(frame.GetFrameStrata, frame)
    if ok then row.strata = value end
  end
  if type(frame.IsMouseEnabled) == "function" then
    ok, value = pcall(frame.IsMouseEnabled, frame)
    if ok then row.mouse = value and true or false end
  end
  if type(frame.GetParent) == "function" then
    ok, value = pcall(frame.GetParent, frame)
    if ok then row.parent = trace.Name(value) end
  end
  return row
end

function trace.Log(list, row)
  if not trace.on or table.getn(list) >= trace.maxLog then return end
  row.t = Rounded(GetTime())
  row.unlocked = unlocked and true or false
  table.insert(list, row)
end

-- A write to or a re-application of a stored position.
function trace.Event(kind, entry, position, extra)
  if not trace.on or not entry then return end
  local row = { kind = kind, id = entry.id }
  if type(position) == "table" then
    row.point = position.point
    row.relativePoint = position.relativePoint
    row.x, row.y = Rounded(position.x), Rounded(position.y)
  end
  if type(extra) == "table" then
    local key, value
    for key, value in pairs(extra) do row[key] = value end
  end
  local left, right, bottom, top = LiveRect(entry)
  row.liveLeft, row.liveBottom = Rounded(left), Rounded(bottom)
  row.liveRight, row.liveTop = Rounded(right), Rounded(top)
  trace.Log(trace.events, row)
end

-- Every registered mover, as the snapper sees it and as the client draws it.
function trace.Snapshot()
  local rows, i = {}, nil
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if entry then
      local position = EntryPosition(entry)
      local left, right, bottom, top = MoverBounds(entry, position)
      local liveLeft, liveRight, liveBottom, liveTop = LiveRect(entry)
      local shownOk, shown = pcall(entry.frame.IsShown, entry.frame)
      table.insert(rows, {
        id = entry.id,
        visible = IsEntryVisible(entry) and true or false,
        shown = shownOk and (shown and true or false) or "?",
        ratio = Rounded(EntryScale(entry)),
        width = Rounded(Edge(entry.frame, "GetWidth")),
        height = Rounded(Edge(entry.frame, "GetHeight")),
        point = position and position.point or "none",
        relativePoint = position and
                        (position.relativePoint or position.point) or "none",
        x = position and Rounded(position.x),
        y = position and Rounded(position.y),
        -- What the snapper works with.
        snapLeft = Rounded(left), snapRight = Rounded(right),
        snapBottom = Rounded(bottom), snapTop = Rounded(top),
        -- What the client draws.
        liveLeft = Rounded(liveLeft), liveRight = Rounded(liveRight),
        liveBottom = Rounded(liveBottom), liveTop = Rounded(liveTop),
        saved = U.GetPosition(entry.id) and true or false,
        enters = entry.enters, dragStarts = entry.dragStarts,
        dragStops = entry.dragStops,
        frame = trace.Widget(entry.frame),
        handle = trace.Widget(entry.handle),
        input = trace.Widget(entry.dragInput),
      })
    end
  end
  return rows
end

function trace.Start()
  trace.on = true
  trace.samples = {}
  trace.seq = 0
  trace.dropped = 0
  trace.current = nil
  trace.reason = nil
  trace.startedAt = type(U.DiagnosticStamp) == "function"
                    and U.DiagnosticStamp() or "?"
  trace.focus, trace.drift, trace.events, trace.rects = {}, {}, {}, {}
  trace.lastFocus, trace.nextDrift = nil, 0
  trace.lockedAt, trace.afterLock = nil, nil
  trace.lastId, trace.lastInX, trace.lastInY = nil, nil, nil
  trace.atUnlock = nil
  trace.before = trace.Snapshot()
  trace.NewReport()
  -- trace.Watch is defined further down; it is looked up when the driver runs.
  U.RegisterUpdate("mover.diag", 0, function() trace.Watch() end)
  return true
end

-- Called by ResolveSnap. Returns the sample the rest of that call fills in, or
-- nil while the tracer is off or full.
function trace.Begin(entry, point, relativePoint, x, y, config)
  trace.current = nil
  if not trace.on then return nil end
  -- A held but motionless cursor re-resolves the same request every frame;
  -- one sample per distinct request keeps the cap for actual movement.
  if trace.lastId == entry.id and trace.lastInX == x and trace.lastInY == y then
    return nil
  end
  trace.lastId, trace.lastInX, trace.lastInY = entry.id, x, y
  if table.getn(trace.samples) >= trace.max then
    trace.dropped = trace.dropped + 1
    return nil
  end

  trace.seq = trace.seq + 1
  local left, right, bottom, top = MoverBounds(entry, {
    point = point, relativePoint = relativePoint, x = x, y = y })
  local liveLeft, liveRight, liveBottom, liveTop = LiveRect(entry)

  local sample = {
    seq = trace.seq,
    id = entry.id,
    dragging = entry.dragging and true or false,
    grid = config.gridShown and true or false,
    gridSize = GridSize(),
    magnet = config.magnet and true or false,
    ratio = Rounded(EntryScale(entry)),
    point = point,
    relativePoint = relativePoint,
    -- The position asked for, before any snapping.
    inX = Rounded(x), inY = Rounded(y),
    fromX = Rounded(entry.snapFromX), fromY = Rounded(entry.snapFromY),
    -- The rect that request describes, both ways.
    snapLeft = Rounded(left), snapRight = Rounded(right),
    snapBottom = Rounded(bottom), snapTop = Rounded(top),
    liveLeft = Rounded(liveLeft), liveRight = Rounded(liveRight),
    liveBottom = Rounded(liveBottom), liveTop = Rounded(liveTop),
    hits = {},
  }
  trace.current = sample
  return sample
end

-- One overlap correction, as SnapToMovers resolved it.
function trace.Hit(other, axis, correction, exact, otherLeft, otherRight,
                   otherBottom, otherTop, left, right, bottom, top)
  local sample = trace.current
  if not sample then return end
  if table.getn(sample.hits) >= 8 then return end

  table.insert(sample.hits, {
    other = other and other.id or "?",
    axis = axis,
    correction = Rounded(correction),
    exact = Rounded(exact),
    entryLeft = Rounded(left), entryRight = Rounded(right),
    entryBottom = Rounded(bottom), entryTop = Rounded(top),
    otherLeft = Rounded(otherLeft), otherRight = Rounded(otherRight),
    otherBottom = Rounded(otherBottom), otherTop = Rounded(otherTop),
  })
end

-- The grid pass and the magnet pass, then the position the caller returns.
function trace.Commit(sample, gridX, gridY, x, y)
  if not sample then return end
  sample.gridX, sample.gridY = Rounded(gridX), Rounded(gridY)
  sample.outX, sample.outY = Rounded(x), Rounded(y)
  table.insert(trace.samples, sample)
  trace.current = nil
end

-- The report is written into UnrealUIDiagDB as soon as the run is armed, and
-- every log below is the live table it references. SavedVariables are
-- flushed only on /reload or logout, and this client has no verified logout
-- event to save from, so a report written only at the end was lost whenever
-- the player reloaded first (2026-09-17: reload 3 s after the last lock, 17 s
-- before the post-lock watch would have saved). Now a reload at any point
-- keeps everything recorded up to it.
function trace.Publish(reason)
  local report = trace.report
  if not report then return end
  local scaleOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
  report.stoppedAt = type(U.DiagnosticStamp) == "function"
                     and U.DiagnosticStamp() or "?"
  report.reason = reason
  report.theme = type(U.GetActiveThemeStyle) == "function"
                 and U.GetActiveThemeStyle() or "?"
  report.uiWidth = Rounded(U.UIWidth())
  report.uiHeight = Rounded(U.UIHeight())
  report.uiScale = scaleOk and Rounded(uiScale) or "?"
  report.gridSize = GridSize()
  report.magnetDistance = MAGNET_DISTANCE
  report.dropped = trace.dropped
  report.before = trace.before
  report.atUnlock = trace.atUnlock
  report.afterLock = trace.afterLock
  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("moveSnap", report)
  end
end

function trace.NewReport()
  trace.report = {
    startedAt = trace.startedAt,
    samples = trace.samples,
    -- GetMouseFocus changes, with the mover part it belongs to.
    focus = trace.focus,
    -- Live rects that changed, sampled every 0.25 s.
    drift = trace.drift,
    -- Store writes and re-applications (save, apply, pin, pendingSnap).
    events = trace.events,
  }
  trace.Publish("running")
end

-- Disarmed after the post-lock watch or by the command, so the recording ends
-- with the gesture rather than needing a command the player cannot type while
-- the overlay is up.
function trace.Stop(reason)
  if not trace.on then return false, 0, 0 end
  trace.on = false
  trace.current = nil
  trace.reason = reason
  U.UnregisterUpdate("mover.diag")

  if trace.report then
    trace.report.after = trace.Snapshot()
    trace.Publish(reason)
  end

  local count = table.getn(trace.samples)
  trace.report = nil
  trace.samples = {}
  trace.before, trace.afterLock, trace.lockedAt = nil, nil, nil
  trace.atUnlock = nil
  trace.focus, trace.drift, trace.events, trace.rects = {}, {}, {}, {}
  return true, count, trace.dropped
end

-- /uui movesnap. Armed before edit mode, disarmed by U.LockUI or by the
-- command again.
function U.MoverSnapTrace(on)
  if on then return trace.Start() end
  return trace.Stop("command")
end

function U.MoverSnapTraceOn()
  return trace.on and true or false
end

-- An anchor travelling with the drag is not a landmark to snap against: it is
-- moving by the same offset, and for a member with a stored position the store
-- still holds where it started, which would pull the dragged frame back there.
local function IsFollower(entry, other)
  if not entry.followerSet or not other then return false end
  return entry.followerSet[other.id] and true or false
end

-- Magnet contact wins over the grid on the axis where two anchors touch.
--
-- With the grid on, this used to skip the proximity pull and round the
-- collision escape up to whole cells, so the grid kept every edge on a drawn
-- line. Against a neighbour whose size is not a whole number of cells that
-- always left a visible gap between the two anchors, which is exactly what
-- enabling the magnet asks not to have. Now:
--
--   * the edge-to-edge pull runs with the grid on too, measured from the
--     cursor's unsnapped position (rawX/rawY) so the grid cell the anchor
--     happens to sit in cannot hold it out of magnet range; a hit on an axis
--     replaces the grid value on that axis only, and the other axis stays on
--     the grid;
--   * centre alignment (screen and neighbour) stays grid-off only, since the
--     grid already provides alignment;
--   * the collision escape is exact, leaving the anchor flush against the
--     edge it approached.
local function SnapToMovers(entry, point, relativePoint, x, y, gridOn,
                            rawX, rawY)
  local fromX, fromY = x, y
  if gridOn then fromX, fromY = rawX or x, rawY or y end
  local moving = { point = point, relativePoint = relativePoint,
                   x = fromX, y = fromY }
  local left, right, bottom, top = MoverBounds(entry, moving)
  if not left then return x, y, false, false end

  local bestX, bestY, bestXDistance, bestYDistance = nil, nil,
    MAGNET_DISTANCE + 1, MAGNET_DISTANCE + 1
  local i
  if not gridOn then
    bestX, bestXDistance = ClosestDelta(
      U.UIWidth() / 2 - (left + right) / 2, bestX, bestXDistance)
    bestY, bestYDistance = ClosestDelta(
      U.UIHeight() / 2 - (bottom + top) / 2, bestY, bestYDistance)
  end
  for i = 1, table.getn(moverOrder) do
    local other = movers[moverOrder[i]]
    if other ~= entry and IsEntryVisible(other) and
       not IsFollower(entry, other) then
      local position = EntryPosition(other)
      local otherLeft, otherRight, otherBottom, otherTop =
        MoverBounds(other, position)
      if otherLeft then
        if IntervalsNear(bottom, top, otherBottom, otherTop) then
          bestX, bestXDistance = ClosestDelta(
            otherLeft - right, bestX, bestXDistance)
          bestX, bestXDistance = ClosestDelta(
            otherRight - left, bestX, bestXDistance)
          if not gridOn then
            bestX, bestXDistance = ClosestDelta(
              ((otherLeft + otherRight) - (left + right)) / 2,
              bestX, bestXDistance)
          end
        end
        if IntervalsNear(left, right, otherLeft, otherRight) then
          bestY, bestYDistance = ClosestDelta(
            otherBottom - top, bestY, bestYDistance)
          bestY, bestYDistance = ClosestDelta(
            otherTop - bottom, bestY, bestYDistance)
          if not gridOn then
            bestY, bestYDistance = ClosestDelta(
              ((otherBottom + otherTop) - (bottom + top)) / 2,
              bestY, bestYDistance)
          end
        end
      end
    end
  end

  if bestX then x = fromX + bestX end
  if bestY then y = fromY + bestY end

  -- A magnet is also a collision barrier. Resolve every overlap after the
  -- proximity snap, backing the anchor out the way it came in. Repeating the
  -- walk handles a correction that would otherwise push the mover into a
  -- second neighbour.
  --
  -- The direction matters: taking the SHORTEST of the four ways out reads as a
  -- barrier only while the neighbour is small. Against a tall, wide one -- the
  -- party block -- the nearest edge flips from one side to another between two
  -- ticks, and the anchor is teleported several grid cells across the block
  -- instead of stopping at it. entry.snapFrom* is the last position this drag
  -- settled on, and the overlap is undone across the edge the anchor was
  -- still clear of there -- the edge it actually crossed -- which leaves it
  -- flush against that edge and free to slide along it. With no recorded
  -- position -- one applied outside a drag -- or one that already overlapped,
  -- the shortest-route choice applies.
  --
  -- Not the direction of travel. /uui movesnap 2026-09-17, bar 3 (30 x 382)
  -- held against the quest tracker's right edge while the cursor went left:
  -- a 2-unit upward wobble made "undo the vertical travel" (115 units down)
  -- smaller than "undo the horizontal travel" (135 right), so the bar was
  -- shoved below the tracker into the status bar, whose own escape threw it
  -- 188 units right and the screen clamp dropped it 13 more -- a jump across
  -- the whole corner of the screen from a slow drag.
  local lastX, lastY = tonumber(entry.snapFromX), tonumber(entry.snapFromY)
  local lastLeft, lastRight, lastBottom, lastTop
  if lastX and lastY then
    lastLeft, lastRight, lastBottom, lastTop = MoverBounds(entry, {
      point = point, relativePoint = relativePoint, x = lastX, y = lastY,
    })
  end
  local pass
  for pass = 1, table.getn(moverOrder) do
    local resolved = false
    left, right, bottom, top = MoverBounds(entry, {
      point = point, relativePoint = relativePoint, x = x, y = y,
    })
    if not left then break end

    for i = 1, table.getn(moverOrder) do
      local other = movers[moverOrder[i]]
      if other ~= entry and IsEntryVisible(other) and
         not IsFollower(entry, other) then
        local otherLeft, otherRight, otherBottom, otherTop =
          MoverBounds(other, EntryPosition(other))
        if otherLeft and Overlaps(left, right, bottom, top,
                                  otherLeft, otherRight,
                                  otherBottom, otherTop) then
          local moveLeft = otherLeft - right
          local moveRight = otherRight - left
          local moveDown = otherBottom - top
          local moveUp = otherTop - bottom
          -- Positive x is rightward and positive y upward, here as in
          -- SetPoint. The side the anchor was on at its last position picks
          -- the escape; only an entry across a corner (clear on both axes)
          -- compares the two, so a held edge is never traded for a far one.
          local correction, axis = nil, nil
          if lastLeft then
            local xFix, yFix = nil, nil
            if lastRight <= otherLeft + ALIGNMENT_EPSILON then
              xFix = moveLeft
            elseif lastLeft >= otherRight - ALIGNMENT_EPSILON then
              xFix = moveRight
            end
            if lastTop <= otherBottom + ALIGNMENT_EPSILON then
              yFix = moveDown
            elseif lastBottom >= otherTop - ALIGNMENT_EPSILON then
              yFix = moveUp
            end
            if xFix and yFix then
              if math.abs(yFix) < math.abs(xFix) then
                correction, axis = yFix, "y"
              else
                correction, axis = xFix, "x"
              end
            elseif xFix then
              correction, axis = xFix, "x"
            elseif yFix then
              correction, axis = yFix, "y"
            end
          end

          if not correction then
            correction, axis = moveLeft, "x"
            if math.abs(moveRight) < math.abs(correction) then
              correction, axis = moveRight, "x"
            end
            if math.abs(moveDown) < math.abs(correction) then
              correction, axis = moveDown, "y"
            end
            if math.abs(moveUp) < math.abs(correction) then
              correction, axis = moveUp, "y"
            end
          end
          trace.Hit(other, axis, correction, correction,
                    otherLeft, otherRight, otherBottom, otherTop,
                    left, right, bottom, top)
          if axis == "x" then
            x = x + correction
            bestX = correction
          else
            y = y + correction
            bestY = correction
          end
          resolved = true
          break
        end
      end
    end
    if not resolved then break end
  end

  return x, y, bestX ~= nil, bestY ~= nil
end

-- Grid snapping moves the anchor's TOP-LEFT edge onto a grid line, not the
-- stored offsets.
--
-- Snapping the offsets themselves cannot align anything: they are measured
-- from whatever the stored point pair names -- after a drag, PinToUIParent
-- makes that BOTTOMLEFT, so the screen's left/bottom edge -- while LayoutGrid
-- draws the lines from UIParent's centre outwards. The two origins only agree
-- when half the screen is a whole number of grid cells, and the edge that
-- landed on a line was the bottom one, not the top.
--
-- knowledge.json / mover.gridalign_top_left_edge_snap (FOCUSED_RUNTIME_PROBE,
-- gridalign.v3) measured all 46 slider sizes against unrealUI's own drawn
-- lines: the shipped offset snap missed by up to 23.17 units, while snapping
-- the top-left edge to the centre-origin grid landed on the measured line
-- centre exactly, 92 placements out of 92, for odd and even grid sizes and odd
-- and even frame dimensions alike. Grid-size parity turned out to be
-- irrelevant, so no even/odd grid variant is needed.
--
-- The correction is applied as a delta to the offsets the caller already has,
-- so it holds for any point/relativePoint pair without repeating the
-- point-factor maths.
local function SnapPosition(entry, point, relativePoint, x, y)
  x = tonumber(x) or 0
  y = tonumber(y) or 0

  local left, _, _, top = MoverBounds(entry, {
    point = point, relativePoint = relativePoint, x = x, y = y,
  })
  if not left or not top then
    -- No readable dimensions: snapping the raw offsets at least keeps movement
    -- stepped rather than continuous.
    return SnapValue(x), SnapValue(y)
  end

  local centerX, centerY = U.UIWidth() / 2, U.UIHeight() / 2
  local snappedLeft = centerX + SnapValue(left - centerX)
  local snappedTop = centerY + SnapValue(top - centerY)
  return x + (snappedLeft - left), y + (snappedTop - top)
end

local function ResolveSnap(entry, point, relative, relativePoint, x, y)
  local config = MoverConfig()
  local snapped = false
  local sample = trace.Begin(entry, point, relativePoint, x, y, config)
  local rawX, rawY = x, y
  if config.gridShown then
    local sx, sy = SnapPosition(entry, point, relativePoint, x, y)
    snapped = sx ~= x or sy ~= y
    x, y = sx, sy
  end
  local gridX, gridY = x, y

  if config.magnet and (not relative or relative == UIParent) then
    local magneticX, magneticY
    x, y, magneticX, magneticY =
      SnapToMovers(entry, point, relativePoint, x, y, config.gridShown,
                   rawX, rawY)
    snapped = snapped or magneticX or magneticY
  end
  trace.Commit(sample, gridX, gridY, x, y)

  -- Last, so neither grid nor magnet can place an element off screen. Counts as
  -- a snap: the drop path then re-applies the stored, corrected point.
  if not relative or relative == UIParent then
    local clamped, moved = U.ClampPositionToScreen(entry.frame, {
      point = point, relativePoint = relativePoint, x = x, y = y,
    })
    if moved then
      x, y, snapped = clamped.x, clamped.y, true
    end
    if sample then sample.clamped = moved and true or false end
  end
  -- Committed above, before the clamp; the sample is still the same table.
  if sample then sample.finalX, sample.finalY = Rounded(x), Rounded(y) end
  return x, y, snapped
end

local function ApplyPendingSnap()
  local entry = pendingSnap
  pendingSnap = nil
  U.UnregisterUpdate("mover.snap")
  if not entry then return end

  local stored = U.GetPosition(entry.id)
  if stored then U.ApplyFramePoint(entry.frame, stored) end
  trace.Event("pendingSnap", entry, stored)
  -- After the snap, not before: converting a pre-snap rect would pin the frame
  -- to the bottom edge it had while it was still off the grid.
  NormaliseAnchorEdge(entry)
end

local function CapturePosition(entry)
  local placement = ReadPlacement(entry.frame)
  if not placement then
    U.Debug("mover " .. entry.id .. ": no readable anchor after drag")
    return false
  end
  local point, relative, relativePoint, x, y = placement.point,
    placement.relative, placement.relativePoint, placement.x, placement.y

  -- Stored positions are always UIParent-relative. If the drag left the frame
  -- anchored to something else, say so rather than silently storing an offset
  -- that will be re-applied against a different origin.
  if relative and relative ~= UIParent then
    U.Debug("mover " .. entry.id ..
            ": anchored to a non-UIParent frame after drag; storing anyway")
  end

  local snapped
  x, y, snapped = ResolveSnap(entry, point, relative, relativePoint, x, y)

  local saved = U.SavePosition(entry.id, point, relativePoint, x, y)
  trace.Event("save", entry, {
    point = point, relativePoint = relativePoint, x = x, y = y,
  }, {
    ok = saved and true or false, snapped = snapped and true or false,
    readRelative = trace.Name(relative),
    -- A non-UIParent parent means ReadPlacement fell back to U.GetFramePoint.
    parent = trace.on and trace.Widget(entry.frame).parent or nil,
  })

  if saved and snapped then
    pendingSnap = entry
    U.RegisterUpdate("mover.snap", 0, ApplyPendingSnap)
  elseif saved then
    -- The snapping path converts from ApplyPendingSnap instead, once the frame
    -- has actually been moved onto the grid.
    NormaliseAnchorEdge(entry)
  end

  return saved
end

-- ---------------------------------------------------------------------------
-- Dragging
--
-- The compact DB has no record at all for RegisterForDrag, StartMoving,
-- SetMovable or frame-level mouse input, so none of it can be assumed. The one
-- implementation of frame dragging demonstrably working on this client is
-- UnrealPfUI's dragger (modules/unlock.lua / CreateDragger), and the parts of
-- its recipe that unrealUI's first attempt did not follow are reproduced here:
--
--   * the handle is a **Button**, not a plain Frame. Buttons take mouse input
--     without EnableMouse, and Button is the only widget type this client is
--     known to deliver OnDragStart to.
--   * the handle is parented to the frame it moves and covers it with
--     SetAllPoints, rather than floating over it as a UIParent child.
--   * it is raised with SetFrameLevel rather than a strata change.
--   * SetMovable is applied immediately before each drag, not once at
--     registration.
--   * the real StartMoving is preceded by a StartMoving/StopMovingOrSizing
--     pair, which collapses a multi-point anchor down to the single point the
--     client will actually move.
--
-- Only the behaviour is reused; none of pfUI's selection, grid, scaling or dock
-- machinery is reproduced.
--
-- Failures here are reported through U.Error, not U.Debug: a mover that cannot
-- be dragged is the whole feature failing, and debug output is off by default.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Dragging a group of anchors
--
-- Anchors that touch travel together: dragging the target frame takes the
-- target-of-target frame and the target castbar sitting under it along, and
-- whatever is touching those in turn. The set is collected once, when the drag
-- starts, and every member is then moved by the same offset as the frame under
-- the cursor.
--
-- Movement has to come from that one offset and from nothing else, so a frame
-- riding a live anchor is converted first. A mover's frame is not always
-- anchored to UIParent: target-of-target rests docked under the target frame,
-- and the buff, quest-tracker and pet-bar anchors shadow the client's own
-- frames, which this client hangs off the minimap and the main bar. Left alone,
-- such a frame would be towed by its anchor whether or not it is part of the
-- group -- twice over for a member, and at all for an anchor across the screen
-- that merely shares a chain.
--
-- The conversion is the one NormaliseAnchorEdge performs -- read the live rect,
-- subtract UIParent's origin, apply a stored-shaped point -- which
-- frames.getpoint_relative_name_y_inverted confirms is the safe direction. The
-- modules that shadow a native frame already stop following it while edit mode
-- is open, so this completes their intent rather than fighting it.
--
-- The pin itself is applied, not saved; only anchors the gesture actually moved
-- are written to the position store, alongside the dragged frame's own drop.
-- ---------------------------------------------------------------------------
local function PinToUIParent(entry)
  if not entry or not entry.frame then return false end

  local point, relative = U.GetFramePoint(entry.frame, 1)
  if not point or relative == UIParent then return false end

  -- A frame held by two points is sized by them, and a single replacement point
  -- would collapse it. Only a frame carried by one anchor is converted. If this
  -- client has no GetNumPoints the check simply does not apply.
  local countOk, count = pcall(entry.frame.GetNumPoints, entry.frame)
  if countOk and tonumber(count) and count > 1 then
    U.Debug("mover " .. entry.id .. ": held by " .. count ..
            " points; left riding its anchor")
    return false
  end

  local left = Edge(entry.frame, "GetLeft")
  local bottom = Edge(entry.frame, "GetBottom")
  if not left or not bottom then
    -- Nothing readable to convert (a frame with no resolved rect yet, or one
    -- hidden with none). Leaving the anchor alone is the safe outcome.
    U.Debug("mover " .. entry.id .. ": no readable rect to pin")
    return false
  end

  local applied = U.ApplyFramePoint(entry.frame, {
    point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
    x = left - (Edge(UIParent, "GetLeft") or 0),
    y = bottom - (Edge(UIParent, "GetBottom") or 0),
  })
  if applied then
    trace.Event("pin", entry, nil, { fromRelative = trace.Name(relative) })
    U.Debug("mover " .. entry.id .. ": pinned to UIParent so it is not towed")
  end
  return applied
end

local function PinPassengers(dragged)
  local i
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if entry and entry ~= dragged and IsEntryVisible(entry) then
      PinToUIParent(entry)
    end
  end
end

-- Two anchors count as touching when their bounds meet, overlap, or leave a gap
-- of no more than two units, on both axes. The tolerance is deliberately far
-- smaller than MAGNET_DISTANCE: the default action-bar stack leaves four units
-- between bars, and those are ten separate anchors, not one block. It is not
-- zero because a flush pair still reads a unit or two apart once each anchor
-- has drawn its own outline.
local TOUCH_TOLERANCE = 3

local function BoundsTouch(a, b)
  return a.left < b.right + TOUCH_TOLERANCE and
         a.right > b.left - TOUCH_TOLERANCE and
         a.bottom < b.top + TOUCH_TOLERANCE and
         a.top > b.bottom - TOUCH_TOLERANCE
end

-- Everything touching the dragged anchor, plus everything touching those, and
-- so on outwards. Each member is recorded with the position it started from, so
-- the drag can keep re-deriving it from one offset instead of accumulating.
local function CollectFollowers(dragged)
  local rects, positions, followers = {}, {}, {}

  local i
  for i = 1, table.getn(moverOrder) do
    local other = movers[moverOrder[i]]
    if other and IsEntryVisible(other) then
      local position = EntryPosition(other)
      local left, right, bottom, top = MoverBounds(other, position)
      if left then
        rects[other.id] = { left = left, right = right,
                            bottom = bottom, top = top }
        positions[other.id] = position
      end
    end
  end

  local frontier = { rects[dragged.id] }
  if not frontier[1] then return followers end

  local taken = { [dragged.id] = true }
  local cursor = 1
  while cursor <= table.getn(frontier) do
    local current = frontier[cursor]
    cursor = cursor + 1
    for i = 1, table.getn(moverOrder) do
      local other = movers[moverOrder[i]]
      local rect = other and rects[other.id]
      if rect and not taken[other.id] and BoundsTouch(current, rect) then
        local position = positions[other.id]
        taken[other.id] = true
        table.insert(frontier, rect)
        table.insert(followers, {
          entry = other,
          point = position.point,
          relativePoint = position.relativePoint or position.point,
          x = tonumber(position.x) or 0,
          y = tonumber(position.y) or 0,
        })
      end
    end
  end

  return followers
end

local function MoveFollowers(entry, deltaX, deltaY)
  entry.followerDeltaX, entry.followerDeltaY = deltaX, deltaY
  local i
  for i = 1, table.getn(entry.followers or {}) do
    local follower = entry.followers[i]
    U.ApplyFramePoint(follower.entry.frame, {
      point = follower.point, relativePoint = follower.relativePoint,
      x = follower.x + deltaX, y = follower.y + deltaY,
    })
  end
end

-- Settles the group on the drop. Each member is computed from the position it
-- started at plus the final offset, never read back from the frame:
-- frames.getpoint_relative_name_y_inverted lists recapturing a freshly applied
-- point as a failed approach, and the arithmetic is exact here anyway.
--
-- The offset is taken from what CapturePosition actually stored for the dragged
-- frame, because that call re-resolves grid and magnet once more on the drop.
-- Reusing the last tick's offset would leave the group a few units behind that
-- correction. It falls back to the tick offset when the point names differ,
-- which is NormaliseAnchorEdge having converted the drop to a bottom anchor --
-- the frame is in the same place, so that offset is still the right one.
local function FinishFollowers(entry, before)
  local deltaX = entry.followerDeltaX or 0
  local deltaY = entry.followerDeltaY or 0

  local after = U.GetPosition(entry.id)
  if before and after and before.point == after.point and
     (before.relativePoint or before.point) ==
     (after.relativePoint or after.point) then
    deltaX = (tonumber(after.x) or 0) - (tonumber(before.x) or 0)
    deltaY = (tonumber(after.y) or 0) - (tonumber(before.y) or 0)
  end

  if deltaX == 0 and deltaY == 0 then return end

  local i
  for i = 1, table.getn(entry.followers or {}) do
    local follower = entry.followers[i]
    local position = {
      point = follower.point, relativePoint = follower.relativePoint,
      x = follower.x + deltaX, y = follower.y + deltaY,
    }
    -- Applied as well as stored: an anchor the gesture moved has to keep its
    -- new place across a reload, and a member that was only ever riding a live
    -- anchor has no stored position of its own to fall back on.
    U.ApplyFramePoint(follower.entry.frame, position)
    U.SavePosition(follower.entry.id, position.point, position.relativePoint,
                   position.x, position.y)
    NormaliseAnchorEdge(follower.entry)
  end
end

local function ClearFollowers(entry)
  entry.followers = nil
  entry.followerSet = nil
  entry.followerDeltaX, entry.followerDeltaY = nil, nil
end

local function ReadDragPosition(frame)
  return ReadPlacement(frame)
end

-- knowledge.json / api.getcursorposition_usable_for_hit_testing
-- (USER_CONFIRMED_INGAME): cursor coordinates divided by effective scale are
-- valid in the frame geometry space used by the placement offsets below.
--
-- UIParent's scale, not the dragged frame's. A mover's offsets are in
-- UIParent's units whatever the frame's own scale is (see EntryScale for the
-- measurement), so dividing by the frame's effective scale made a 0.75 cast
-- bar travel a third further than the cursor and land where the player had not
-- put it -- which is what "the cast bar does not save its position" was.
local function ReadCursorPoint()
  local cursor = U.G("GetCursorPosition")
  if type(cursor) ~= "function" then return nil end

  local cursorOk, x, y = pcall(cursor)
  local scaleOk, scale = pcall(UIParent.GetEffectiveScale, UIParent)
  x, y, scale = tonumber(x), tonumber(y), tonumber(scale)
  if not cursorOk or not scaleOk or not x or not y or
     not scale or scale <= 0 then return nil end
  return x / scale, y / scale
end

local function PositionChanged(before, after)
  if not before or not after then return true end
  return before.point ~= after.point or
         before.relativePoint ~= after.relativePoint or
         before.x ~= after.x or before.y ~= after.y
end

local StopDrag

-- Best effort only, not the safety net: IsMouseButtonDown appears nowhere in
-- this client's documented globals (documentation.json lists GetCursorPosition,
-- GetMouseFocus and the modifier-key queries, and no mouse-button state call),
-- and neither reference addon uses it. Where it is missing this reports "still
-- held" forever, which is why the drag now ends through the input Button's own
-- OnDragStop and OnMouseUp rather than through a poll.
local function LeftButtonStillDown()
  local fn = U.G("IsMouseButtonDown")
  if type(fn) ~= "function" then return true end
  local ok, down = pcall(fn, "LeftButton")
  if not ok then return true end
  return down and down ~= 0 and true or false
end

-- knowledge.json / widgets.thumb_reposition_during_drag_breaks_drag
-- (RUNTIME_FAILURE_CONFIRMED): re-anchoring a frame while this client is moving
-- it with StartMoving makes the client drop the drag, and with it the
-- OnDragStop that would end the gesture. The live feedback below rewrites
-- entry.frame's point on every tick, and the drag input rides that frame's
-- rect while it is idle -- so the moment a drag begins the input is cut loose
-- into UIParent space, given the anchor's current rect once, and never touched
-- again until the drop. Nothing in its hierarchy moves for the rest of the
-- gesture, which is the condition the settings slider's reliable thumb enjoys.
--
-- This is also why the input cannot simply stay parented to the handle: the
-- handle covers the anchor, so every tick of live movement would re-anchor an
-- ancestor of the frame the client is dragging.
local function DetachDragInput(entry)
  local frame, input = entry.frame, entry.dragInput
  if not frame or not input then return false end

  local widthOk, width = pcall(frame.GetWidth, frame)
  local heightOk, height = pcall(frame.GetHeight, frame)
  local centreOk, centreX, centreY = pcall(frame.GetCenter, frame)
  width, height = tonumber(width), tonumber(height)
  centreX, centreY = tonumber(centreX), tonumber(centreY)

  -- Without a usable rect the input keeps the SetAllPoints(handle) stretch it
  -- was created with. That is the weaker arrangement this record warns about,
  -- so it is reported rather than passed over silently.
  if not widthOk or not heightOk or not centreOk or not width or not height or
     not centreX or not centreY or width <= 0 or height <= 0 then
    U.Debug("mover " .. entry.id .. ": drag input keeps its handle anchor")
    return false
  end

  -- GetCenter and GetWidth already report in UIParent's units, whatever the
  -- frame's own scale is (EntryScale), so the rect transfers unchanged to the
  -- input Button living in that same space.
  input:ClearAllPoints()
  input:SetWidth(width)
  input:SetHeight(height)
  input:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centreX, centreY)
  return true
end

-- Returns the input to the handle it covers, so the next press lands on it.
local function ReattachDragInput(entry)
  local input = entry.dragInput
  if not input or not entry.handle then return false end
  input:ClearAllPoints()
  input:SetAllPoints(entry.handle)
  return true
end

local function StartDrag(entry)
  -- Start only after the client recognises its registered drag gesture. The
  -- invisible input Button remains in native StartMoving until OnDragStop, the
  -- same lifecycle used by U.CreateSlider's reliable thumb. The visible anchor
  -- is moved separately from cursor coordinates so snapping cannot interrupt
  -- the input Button's matching release callback.
  if entry.dragging then return true end

  -- Detach everything still riding a live anchor, so what moves is decided by
  -- the group below and by nothing else. The dragged frame is converted too:
  -- until it sits in UIParent space it has no bounds to collect a group with --
  -- EntryPosition rejects a point relative to anything else.
  PinToUIParent(entry)
  PinPassengers(entry)
  -- With grouping off the pins above are the whole of it: every anchor is
  -- independent, and this gesture moves the one under the cursor.
  entry.followers = MoverConfig().groupTouching and CollectFollowers(entry) or {}
  entry.followerSet = {}
  entry.followerDeltaX, entry.followerDeltaY = 0, 0
  local followerIndex
  for followerIndex = 1, table.getn(entry.followers) do
    entry.followerSet[entry.followers[followerIndex].entry.id] = true
  end

  local frame = entry.frame
  local input = entry.dragInput
  if not input then return false end

  DetachDragInput(entry)

  if not pcall(input.SetMovable, input, true) then
    U.Error("mover " .. entry.id .. ": SetMovable failed; drag input is unavailable")
    ReattachDragInput(entry)
    return false
  end

  if pcall(input.StartMoving, input) then
    pcall(input.StopMovingOrSizing, input)
  end

  if not pcall(input.StartMoving, input) then
    U.Error("mover " .. entry.id .. ": StartMoving failed; drag input will not move")
    ReattachDragInput(entry)
    return false
  end

  entry.dragging = true
  -- PinToUIParent above has already reduced the visible anchor to one stable
  -- point. Keep that point independent of the native input Button's movement.
  entry.dragStartPosition = ReadDragPosition(frame)
  entry.dragCursorX, entry.dragCursorY = ReadCursorPoint()
  -- Where the anchor is now. SnapToMovers reads this to know which way it is
  -- travelling when it has to undo an overlap; it is updated below on every
  -- tick that settles on a position, so it always names the last place the
  -- anchor was clear.
  entry.snapFromX = entry.dragStartPosition and entry.dragStartPosition.x
  entry.snapFromY = entry.dragStartPosition and entry.dragStartPosition.y
  U.RegisterUpdate("mover.drag", 0, function()
    if not entry.dragging then
      U.UnregisterUpdate("mover.drag")
      return
    end
    if not LeftButtonStillDown() then
      StopDrag(entry)
      return
    end

    local origin = entry.dragStartPosition
    local cursorX, cursorY = ReadCursorPoint()
    if not origin or not cursorX or not entry.dragCursorX then return end
    local deltaX = cursorX - entry.dragCursorX
    local deltaY = cursorY - entry.dragCursorY
    -- Selecting a mover with an ordinary click must not silently snap it.
    if deltaX == 0 and deltaY == 0 then return end
    local point, relativePoint = origin.point, origin.relativePoint
    local x = (tonumber(origin.x) or 0) + deltaX
    local y = (tonumber(origin.y) or 0) + deltaY
    local snappedX, snappedY = ResolveSnap(
      entry, point, origin.relative, relativePoint, x, y)

    -- The cursor origin above remains stable for the full gesture, so applying
    -- this point every shared-driver tick gives immediate feedback without
    -- accumulating a new grab offset at each grid or magnet boundary.
    U.ApplyFramePoint(frame, {
      point = point, relativePoint = relativePoint,
      x = snappedX, y = snappedY,
    })
    entry.snapFromX, entry.snapFromY = snappedX, snappedY
    -- The offset the frame actually took, snapping included, is the offset the
    -- rest of the group takes.
    MoveFollowers(entry, snappedX - (tonumber(origin.x) or 0),
                  snappedY - (tonumber(origin.y) or 0))
    UpdateAlignmentGuides(entry, point, relativePoint, snappedX, snappedY)
  end)
  return true
end

StopDrag = function(entry)
  if not entry.dragging then return false end
  entry.dragging = false
  U.UnregisterUpdate("mover.drag")

  local input = entry.dragInput
  if input then
    pcall(input.StopMovingOrSizing, input)
    ReattachDragInput(entry)
  end
  local before = entry.dragStartPosition
  entry.dragStartPosition = nil
  entry.dragCursorX, entry.dragCursorY = nil, nil
  HideAlignmentGuides()
  if not PositionChanged(before, ReadDragPosition(entry.frame)) then
    ClearFollowers(entry)
    return true
  end
  local captured = CapturePosition(entry)
  entry.snapFromX, entry.snapFromY = nil, nil
  FinishFollowers(entry, before)
  ClearFollowers(entry)
  -- The panel follows its anchor while the frame is dragged; once the drop is
  -- stored, reconsider which side of the anchor still has room for it.
  if activeMover == entry and type(U.PlaceMoverPanel) == "function" then
    U.PlaceMoverPanel()
  end
  return captured
end

-- ---------------------------------------------------------------------------
-- Drag handle
--
-- Created on first unlock and reused afterwards. knowledge.json /
-- scripts.child_onupdate_unreliable applies here: the handle is populated
-- synchronously at creation and never waits on an OnUpdate tick to become
-- usable.
--
-- The counters exist so /uui check can report whether the client delivered
-- mouse and drag events at all. Without them a handle that never receives
-- OnDragStart is indistinguishable from one whose StartMoving failed.
-- ---------------------------------------------------------------------------
local handleCount = 0
-- Mover handles cover complete interface elements while edit mode is active.
-- A small offset is not enough for elements with raised child frames (action
-- buttons and their cooldown/readout layers are one example): those children
-- can win mouse hit-testing over part of the mover. Keep the offset relative
-- to the moved frame so separate frame ordering is preserved, but leave enough
-- room above its complete child hierarchy for one continuous drag surface.
local HANDLE_LEVEL_OFFSET = 100

-- A one-unit stepped falloff keeps the outer glow visually continuous without
-- introducing a new asset or blend-mode assumption. The total seven-unit
-- footprint and peak opacity match the original three-band treatment, but the
-- smaller alpha changes avoid visible rectangular bands.
local MOVER_GLOW_RINGS = {
  { spread = 1, thickness = 1, idleAlpha = 0.24, activeAlpha = 0.42 },
  { spread = 2, thickness = 1, idleAlpha = 0.20, activeAlpha = 0.35 },
  { spread = 3, thickness = 1, idleAlpha = 0.16, activeAlpha = 0.29 },
  { spread = 4, thickness = 1, idleAlpha = 0.12, activeAlpha = 0.23 },
  { spread = 5, thickness = 1, idleAlpha = 0.09, activeAlpha = 0.17 },
  { spread = 6, thickness = 1, idleAlpha = 0.06, activeAlpha = 0.12 },
  { spread = 7, thickness = 1, idleAlpha = 0.03, activeAlpha = 0.07 },
}

local function CreateHandleGlow(handle)
  local glow, ringIndex = {}, nil

  for ringIndex = 1, table.getn(MOVER_GLOW_RINGS) do
    local ring = MOVER_GLOW_RINGS[ringIndex]
    local spread, thickness = ring.spread, ring.thickness
    local strips, stripIndex = {}, nil

    for stripIndex = 1, 4 do
      local strip = handle:CreateTexture(nil, "ARTWORK")
      strip:SetTexture(M.texture.plain)
      strips[stripIndex] = strip
    end

    strips[1]:SetHeight(thickness)
    strips[1]:SetPoint("TOPLEFT", handle, "TOPLEFT", -spread, spread)
    strips[1]:SetPoint("TOPRIGHT", handle, "TOPRIGHT", spread, spread)

    strips[2]:SetHeight(thickness)
    strips[2]:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", -spread, -spread)
    strips[2]:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", spread, -spread)

    strips[3]:SetWidth(thickness)
    strips[3]:SetPoint("TOPLEFT", handle, "TOPLEFT", -spread, spread)
    strips[3]:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", -spread, -spread)

    strips[4]:SetWidth(thickness)
    strips[4]:SetPoint("TOPRIGHT", handle, "TOPRIGHT", spread, spread)
    strips[4]:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", spread, -spread)

    glow[ringIndex] = strips
  end

  return glow
end

local function SetHandleGlowShown(entry, shown)
  if not entry or not entry.handleGlow then return end
  local ringIndex, stripIndex = nil, nil
  for ringIndex = 1, table.getn(entry.handleGlow) do
    for stripIndex = 1, table.getn(entry.handleGlow[ringIndex]) do
      if shown then
        entry.handleGlow[ringIndex][stripIndex]:Show()
      else
        entry.handleGlow[ringIndex][stripIndex]:Hide()
      end
    end
  end
end

local function ApplyHandleState(entry)
  if not entry or not entry.handle then return end

  local selected = activeMover == entry
  local highlighted = selected or entry.listHovered
  local background = highlighted and M.color.accentFill or M.color.mover
  local edge = highlighted and M.color.accent or
               (entry.hovered and M.color.moverIdleHover or M.color.moverIdleEdge)
  local glowColor = highlighted and M.color.accent or M.color.moverIdleGlow

  U.SetBackgroundColor(entry.handle, M.Unpack(background))
  U.SetBorderColor(entry.handle, M.Unpack(edge))

  local ringIndex, stripIndex = nil, nil
  for ringIndex = 1, table.getn(entry.handleGlow or {}) do
    local ring = MOVER_GLOW_RINGS[ringIndex]
    local alpha = highlighted and ring.activeAlpha or ring.idleAlpha
    for stripIndex = 1, table.getn(entry.handleGlow[ringIndex]) do
      U.SetColor(entry.handleGlow[ringIndex][stripIndex], glowColor[1],
                 glowColor[2], glowColor[3], alpha)
    end
  end

  if entry.handle.label then
    if highlighted then entry.handle.label:Show() else entry.handle.label:Hide() end
  end
end

local function SetActiveMover(entry)
  local previous = activeMover
  activeMover = entry
  ApplyHandleState(previous)
  if entry ~= previous then ApplyHandleState(entry) end

  -- The panel belongs to the anchor, not to the edit window: it is handed the
  -- addon-owned handle so it can sit beside that anchor and carry its label as
  -- the window title. Using the handle rather than entry.frame also keeps the
  -- panel off a client-owned relative when a mover deliberately owns a native
  -- root such as Classic's MainMenuBar.
  --
  -- Which movers have a panel is not decided here: a module registers one for
  -- its own mover id (core/moverpanel.lua), and a mover with no registered
  -- panel simply selects with nothing beside it.
  if entry and type(entry.id) == "string" and
     type(U.ShowMoverPanel) == "function" then
    U.ShowMoverPanel(entry.id, {
      id = entry.id, frame = entry.handle or entry.frame, label = entry.label,
    })
  elseif type(U.HideMoverPanel) == "function" then
    U.HideMoverPanel()
  end
end

-- Deselects whatever handle is selected. The contextual panel's close button
-- calls this rather than hiding itself, so the handle stops being highlighted
-- at the same moment its panel goes away; SetActiveMover(nil) is what takes the
-- panel down. Returns false when nothing was selected, which lets
-- U.CloseMoverPanel fall back to a plain hide.
function U.ClearMoverSelection()
  if not activeMover then return false end
  SetActiveMover(nil)
  return true
end

local function RaiseHandle(entry)
  if not entry or not entry.handle then return false end
  local levelOk, level = pcall(entry.frame.GetFrameLevel, entry.frame)
  if not levelOk or not tonumber(level) then return false end
  local handleLevel = level + HANDLE_LEVEL_OFFSET
  local raised = pcall(entry.handle.SetFrameLevel, entry.handle, handleLevel)
  if entry.dragInput then
    -- The input is a UIParent child, so it does not inherit the moved frame's
    -- strata. Without matching it the handle would win hit-testing and the
    -- drag gesture would never reach the Button that owns it.
    --
    -- Read from the moved frame, not the handle. /uui movesnap 2026-09-17: at
    -- unlock every handle read GetFrameStrata "PARENT" (it inherits), so the
    -- input was set to "PARENT" too and resolved against UIParent -- MEDIUM.
    -- That is above a LOW anchor but BELOW the HIGH cast bars, whose handles
    -- then covered their inputs: 0 OnEnter, 0 drag starts, unselectable.
    -- Most anchors inherit their target's strata. A native root may contain
    -- client buttons above that level, so a caller can raise only the temporary
    -- edit-mode input without changing the actual frame's draw order.
    local strata = entry.inputStrata
    if not strata then
      local strataOk, value = pcall(entry.frame.GetFrameStrata, entry.frame)
      if strataOk and type(value) == "string" and value ~= "PARENT" then
        strata = value
      else
        strataOk, value = pcall(entry.handle.GetFrameStrata, entry.handle)
        if strataOk and type(value) == "string" and value ~= "PARENT" then
          strata = value
        end
      end
    end
    if strata then
      pcall(entry.dragInput.SetFrameStrata, entry.dragInput, strata)
    end
    pcall(entry.dragInput.SetFrameLevel, entry.dragInput, handleLevel + 1)
  end
  return raised
end

local function CreateHandle(entry)
  handleCount = handleCount + 1

  -- Named because an unnamed Button gives the client nothing to report in an
  -- error, and the mover handles are exactly what a drag failure is about.
  local handle = CreateFrame("Button", "UnrealUIMoverHandle" .. handleCount,
                             entry.frame)
  handle:SetAllPoints(entry.frame)
  -- Visual only: every script lives on the input below. A mouse-enabled handle
  -- that ends up above its input swallows the hover and the drag.
  pcall(handle.EnableMouse, handle, false)

  -- Match the settings slider's reliable two-layer drag: this visible handle
  -- never enters native movement. A separate transparent Button owns the
  -- complete OnDragStart -> StartMoving -> OnDragStop gesture while the anchor
  -- below it follows the shared cursor updater.
  --
  -- It is a UIParent child rather than a child of the handle, because the
  -- handle covers the anchor and therefore moves with it: see DetachDragInput
  -- for why nothing in the dragged Button's hierarchy may be re-anchored while
  -- the client is moving it. frames.movable_drag_requires_button_handle rules
  -- out a plain Frame raised by strata, not a Button ordered by frame level,
  -- and U.CreateSlider's thumb is the working precedent for a Button that is
  -- not parented to what it moves. While idle it still covers the handle
  -- exactly, so the press that starts a drag lands on it.
  --
  -- Its shown state deliberately follows ShowHandle/HideHandle, not
  -- handle:IsVisible(). Unit and cast frames are hidden while empty and expose
  -- their edit-mode shells on the next shared refresh after U.UnlockUI. If the
  -- UIParent-owned input inherits that brief hidden state, nothing calls back
  -- into the mover when the shell appears and the visible anchor can never be
  -- hovered. The mover lifetime is the authoritative mouse gate.
  local input = CreateFrame("Button", "UnrealUIMoverDragInput" .. handleCount,
                            UIParent)
  input:SetAllPoints(handle)
  input:RegisterForDrag("LeftButton")
  pcall(input.EnableMouse, input, true)

  U.CreateBackdrop(handle, {
    background = M.color.mover,
    border = M.color.moverIdleEdge,
  })

  entry.handleGlow = CreateHandleGlow(handle)

  -- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
  -- can accept SetText without ever showing a FontString, so the label is a
  -- FontString unrealUI creates and owns rather than the Button's own text.
  local label = U.CreateLabel(handle, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormal",
  })
  if label then
    label:SetPoint("CENTER", handle, "CENTER", 0, 0)
    label:SetText(entry.label)
  end
  handle.label = label

  -- knowledge.json / scripts.handler_arguments_direct: these close over entry
  -- instead of depending on the callback argument shape.
  input:SetScript("OnDragStart", function()
    SetActiveMover(entry)
    entry.dragStarts = entry.dragStarts + 1
    StartDrag(entry)
  end)

  input:SetScript("OnDragStop", function()
    entry.dragStops = entry.dragStops + 1
    StopDrag(entry)
  end)

  -- Second release path. The detached input stays under the cursor for the
  -- whole native move, so a release lands on it even when the client does not
  -- deliver the drag callback; StopDrag is idempotent, so receiving both is
  -- harmless. This matters because this client documents no
  -- IsMouseButtonDown -- see LeftButtonStillDown -- and therefore offers no
  -- way to poll a missed release back out of the shared updater.
  input:SetScript("OnMouseUp", function() StopDrag(entry) end)

  input:SetScript("OnClick", function() SetActiveMover(entry) end)

  -- OnEnter is instrumentation as much as highlight: if the enter count stays
  -- at zero the client is not routing mouse input to the handle at all, which
  -- is a different failure from a drag that starts and does not move.
  input:SetScript("OnEnter", function()
    entry.enters = entry.enters + 1
    entry.hovered = true
    ApplyHandleState(entry)
  end)

  input:SetScript("OnLeave", function()
    entry.hovered = false
    ApplyHandleState(entry)
  end)

  entry.handle = handle
  entry.dragInput = input
  RaiseHandle(entry)
  ApplyHandleState(entry)
  return handle
end

local function HideHandle(entry)
  entry.handleShown = false
  if type(U.SetMoverSampleShown) == "function" then
    pcall(U.SetMoverSampleShown, entry.id, false)
  end
  if not entry.handle then return end
  -- Hiding a Button during a drag does not reliably promise an OnDragStop on
  -- this client. Finish it explicitly so locking the UI or hiding an element
  -- can never leave its frame attached to the cursor.
  if entry.dragging then StopDrag(entry) end
  entry.hovered = false
  entry.listHovered = false
  if entry.handle.label then entry.handle.label:Hide() end
  SetHandleGlowShown(entry, false)
  if entry.dragInput then entry.dragInput:Hide() end
  entry.handle:Hide()
end

-- A module may register a frame that is not always part of the layout -- a
-- disabled action bar keeps its stored position but must not offer a handle to
-- drag. options.visible is that predicate; without one a mover is available.
IsEntryAvailable = function(entry)
  if type(entry.visible) ~= "function" then return true end
  local ok, visible = pcall(entry.visible)
  if not ok then return true end
  return visible and true or false
end

-- Advanced visibility is a second gate over module availability. Keeping the
-- two separate lets the drawer distinguish "the user hid this anchor" from
-- "this feature/bar currently has no anchor to show".
IsEntryVisible = function(entry)
  if not advanced.UserEnabled(entry) then return false end
  return IsEntryAvailable(entry)
end

local function ShowHandle(entry)
  if not IsEntryVisible(entry) then
    HideHandle(entry)
    return
  end

  if not entry.handle then CreateHandle(entry) end
  -- Parent/native frame levels can change while the handle is hidden. Refresh
  -- on every unlock instead of trusting the value captured at construction.
  RaiseHandle(entry)
  entry.handle:Show()
  if entry.dragInput then entry.dragInput:Show() end
  -- rendering.parent_alpha_not_propagated: children are shown and hidden
  -- explicitly rather than relying on the parent's visibility carrying.
  SetHandleGlowShown(entry, true)
  ApplyHandleState(entry)
  entry.handleShown = true

  -- An anchor that is empty right now gets a sample of the content that will
  -- occupy it, so it is not placed blind. Most movers register none and this
  -- is a no-op for them.
  if type(U.SetMoverSampleShown) == "function" then
    pcall(U.SetMoverSampleShown, entry.id, true)
  end
end

-- ---------------------------------------------------------------------------
-- Edit-mode overlay
--
-- The grid is plain textures on one full-screen frame: behavior.json /
-- textures.pfui_bar_path.v1 verifies that path, and it keeps the overlay off
-- backdrop edges, which are not reliably rasterised here.
--
-- Lines are laid out from UIParent's centre outwards so the grid is symmetric
-- and the centre axes land exactly on 0,0 -- the offsets a snapped drop
-- produces are multiples of the selected grid size from that same origin.
-- ---------------------------------------------------------------------------

local function LayoutGridLine(index, vertical, offset, color, length, thickness)
  local line = grid.uuiLines[index]
  if not line then
    line = grid:CreateTexture(nil, "BACKGROUND")
    line:SetTexture(M.texture.plain)
    grid.uuiLines[index] = line
  end
  line:ClearAllPoints()
  U.SetColor(line, M.Unpack(color))

  if vertical then
    line:SetWidth(thickness)
    line:SetHeight(length)
    line:SetPoint("CENTER", UIParent, "CENTER", offset, 0)
  else
    line:SetWidth(length)
    line:SetHeight(thickness)
    line:SetPoint("CENTER", UIParent, "CENTER", 0, offset)
  end

  line:Show()
  return line
end

local function LayoutGrid(previewSize)
  local width, height = U.UIWidth(), U.UIHeight()
  local thickness = U.BorderSize()
  local offset, index = nil, 0
  local size = tonumber(previewSize)
  if size then
    size = math.floor(size + 0.5)
    if size < MIN_GRID_SIZE then size = MIN_GRID_SIZE end
    if size > MAX_GRID_SIZE then size = MAX_GRID_SIZE end
  else
    size = GridSize()
  end

  index = index + 1
  LayoutGridLine(index, true, 0, M.color.gridAxis, height, thickness)
  index = index + 1
  LayoutGridLine(index, false, 0, M.color.gridAxis, width, thickness)

  offset = size
  while offset < width / 2 do
    index = index + 1
    LayoutGridLine(index, true, offset, M.color.grid, height, thickness)
    index = index + 1
    LayoutGridLine(index, true, -offset, M.color.grid, height, thickness)
    offset = offset + size
  end

  offset = size
  while offset < height / 2 do
    index = index + 1
    LayoutGridLine(index, false, offset, M.color.grid, width, thickness)
    index = index + 1
    LayoutGridLine(index, false, -offset, M.color.grid, width, thickness)
    offset = offset + size
  end

  local i
  for i = index + 1, table.getn(grid.uuiLines) do
    grid.uuiLines[i]:Hide()
  end
end

local function CreateGrid()
  grid = CreateFrame("Frame", "UnrealUIGrid", UIParent)
  grid:SetAllPoints(UIParent)
  grid.uuiLines = {}
  pcall(grid.SetFrameStrata, grid, "BACKGROUND")
  -- Keep the decoration above any BACKGROUND-strata shade (quick binding
  -- uses one to swallow world clicks) while remaining below normal UI.
  pcall(grid.SetFrameLevel, grid, 1)
  -- The grid is decoration; it must never eat a click meant for a handle.
  pcall(grid.EnableMouse, grid, false)

  LayoutGrid()
  grid:Hide()
end

-- Live centre guides are independent from the optional grid: hiding the grid
-- makes movement continuous, but a precisely centred anchor still receives
-- the requested red visual confirmation. Full-screen lines keep alignment with
-- both the screen centre and another mover readable across the layout.
local function CreateAlignmentGuides()
  alignmentGuides = CreateFrame("Frame", "UnrealUIAlignmentGuides", UIParent)
  alignmentGuides:SetAllPoints(UIParent)
  pcall(alignmentGuides.SetFrameStrata, alignmentGuides, "HIGH")
  pcall(alignmentGuides.EnableMouse, alignmentGuides, false)

  alignmentGuides.vertical = alignmentGuides:CreateTexture(nil, "OVERLAY")
  alignmentGuides.vertical:SetTexture(M.texture.plain)
  U.SetColor(alignmentGuides.vertical, M.Unpack(M.color.moverGuide))

  alignmentGuides.horizontal = alignmentGuides:CreateTexture(nil, "OVERLAY")
  alignmentGuides.horizontal:SetTexture(M.texture.plain)
  U.SetColor(alignmentGuides.horizontal, M.Unpack(M.color.moverGuide))

  alignmentGuides.vertical:Hide()
  alignmentGuides.horizontal:Hide()
  alignmentGuides:Hide()
end

HideAlignmentGuides = function()
  if not alignmentGuides then return end
  alignmentGuides.vertical:Hide()
  alignmentGuides.horizontal:Hide()
  alignmentGuides:Hide()
end

UpdateAlignmentGuides = function(entry, point, relativePoint, x, y)
  local left, right, bottom, top = MoverBounds(entry, {
    point = point, relativePoint = relativePoint, x = x, y = y,
  })
  if not left then
    HideAlignmentGuides()
    return
  end

  local centerX, centerY = (left + right) / 2, (bottom + top) / 2
  local guideX, guideY
  local screenCenterX, screenCenterY = U.UIWidth() / 2, U.UIHeight() / 2
  if math.abs(centerX - screenCenterX) <= ALIGNMENT_EPSILON then
    guideX = screenCenterX
  end
  if math.abs(centerY - screenCenterY) <= ALIGNMENT_EPSILON then
    guideY = screenCenterY
  end
  local i
  for i = 1, table.getn(moverOrder) do
    local other = movers[moverOrder[i]]
    if other ~= entry and IsEntryVisible(other) then
      local otherLeft, otherRight, otherBottom, otherTop =
        MoverBounds(other, EntryPosition(other))
      if otherLeft then
        local otherCenterX = (otherLeft + otherRight) / 2
        local otherCenterY = (otherBottom + otherTop) / 2
        if not guideX and
           math.abs(centerX - otherCenterX) <= ALIGNMENT_EPSILON then
          guideX = otherCenterX
        end
        if not guideY and
           math.abs(centerY - otherCenterY) <= ALIGNMENT_EPSILON then
          guideY = otherCenterY
        end
      end
    end
  end

  if not guideX and not guideY then
    HideAlignmentGuides()
    return
  end
  if not alignmentGuides then CreateAlignmentGuides() end
  alignmentGuides:Show()

  local thickness = U.BorderSize()
  if guideX then
    alignmentGuides.vertical:ClearAllPoints()
    alignmentGuides.vertical:SetWidth(thickness)
    alignmentGuides.vertical:SetHeight(U.UIHeight())
    alignmentGuides.vertical:SetPoint(
      "CENTER", UIParent, "CENTER", guideX - screenCenterX, 0)
    alignmentGuides.vertical:Show()
  else
    alignmentGuides.vertical:Hide()
  end
  if guideY then
    alignmentGuides.horizontal:ClearAllPoints()
    alignmentGuides.horizontal:SetWidth(U.UIWidth())
    alignmentGuides.horizontal:SetHeight(thickness)
    alignmentGuides.horizontal:SetPoint(
      "CENTER", UIParent, "CENTER", 0, guideY - screenCenterY)
    alignmentGuides.horizontal:Show()
  else
    alignmentGuides.horizontal:Hide()
  end
end

-- The edit panel is the only way out of edit mode that does not need a slash
-- command. It is deliberately not registered as a mover: it belongs to the mode
-- rather than to the layout.
local function CreateEditPanel()
  editPanel = U.CreatePanel(UIParent, {
    name = "UnrealUIEditPanel",
    width = 280,
    height = 237,
  })
  editPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  pcall(editPanel.SetFrameStrata, editPanel, "HIGH")

  local title = U.CreateLabel(editPanel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  if title then
    title:SetPoint("TOP", editPanel, "TOP", 0, -12)
    title:SetText(U.L("MOVER_TITLE"))
  end
  editPanel.title = title

  local hint3 = U.CreateLabel(editPanel, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    width = 252,
  })
  if hint3 then
    hint3:SetPoint("TOP", editPanel, "TOP", 0, -34)
    hint3:SetText(U.L("MOVER_HINT_ARROWS"))
  end
  editPanel.hint3 = hint3

  local config = MoverConfig()
  editPanel.gridToggle = U.CreateCheckbox(editPanel, {
    name = "UnrealUIEditGridToggle",
    text = U.L("MOVER_GRID"),
    textWidth = 220,
    value = config.gridShown,
    onChange = function(value)
      MoverConfig().gridShown = value
      if value then U.ShowAlignmentGrid() else U.HideAlignmentGrid() end
    end,
  })
  editPanel.gridToggle.SetPoint("TOPLEFT", editPanel, "TOPLEFT", 18, -54)

  editPanel.magnetToggle = U.CreateCheckbox(editPanel, {
    name = "UnrealUIEditMagnetToggle",
    text = U.L("MOVER_MAGNET"),
    textWidth = 220,
    value = config.magnet,
    onChange = function(value) MoverConfig().magnet = value end,
  })
  editPanel.magnetToggle.SetPoint("TOPLEFT", editPanel, "TOPLEFT", 18, -76)

  editPanel.groupToggle = U.CreateCheckbox(editPanel, {
    name = "UnrealUIEditGroupToggle",
    text = U.L("MOVER_GROUP"),
    textWidth = 220,
    value = config.groupTouching,
    onChange = function(value) MoverConfig().groupTouching = value end,
  })
  editPanel.groupToggle.SetPoint("TOPLEFT", editPanel, "TOPLEFT", 18, -98)

  editPanel.gridSlider = U.CreateSlider(editPanel, {
    name = "UnrealUIEditGridSize",
    text = U.L("MOVER_GRID_SIZE"),
    width = 220,
    min = MIN_GRID_SIZE,
    max = MAX_GRID_SIZE,
    step = 1,
    value = GridSize(),
    onInput = function(value)
      if grid then LayoutGrid(value) end
    end,
    onChange = function(value)
      MoverConfig().gridSize = value
      if grid then LayoutGrid() end
    end,
  })
  editPanel.gridSlider.SetPoint("TOP", editPanel, "TOP", 0, -135)

  editPanel.save = U.CreateButton(editPanel, {
    name = "UnrealUIEditSave",
    text = U.L("MOVER_SAVE_EXIT"),
    width = 140,
    height = 24,
    onClick = function() U.LockUI() end,
  })
  editPanel.save:SetPoint("BOTTOM", editPanel, "BOTTOM", -38, 12)

  editPanel.reset = U.CreateButton(editPanel, {
    name = "UnrealUIEditReset",
    text = U.L("MOVER_RESET"),
    width = 68,
    height = 24,
    onClick = function()
      U.ShowConfirm({
        owner = "mover.reset",
        centered = true,
        text = U.L("COMMON_ARE_YOU_SURE"),
        detail = U.L("COMMON_CANNOT_BE_UNDONE"),
        acceptText = U.L("MOVER_RESET"),
        onAccept = function() U.ResetPositions() end,
      })
    end,
  })
  editPanel.reset:SetPoint("BOTTOM", editPanel, "BOTTOM", 68, 12)

  -- The edit window uses the same persistent header-drag behavior as the other
  -- UnrealUI windows. Only its title strip is a drag surface, leaving every
  -- option below fully interactive.
  U.MakeWindowDraggable("mover.edit", editPanel, {
    headerHeight = 30,
    headerInset = 0,
    avoidOverlap = false,
  })

  editPanel:Hide()
end

local function SetControlShown(control, shown)
  local parts = control and control.uuiParts
  if type(parts) ~= "table" then return end
  local i
  for i = 1, table.getn(parts) do
    if shown then parts[i]:Show() else parts[i]:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- Advanced anchor drawer
--
-- A row controls edit-mode visibility only. Grouped rows (the pet unit frame)
-- hide and restore all of their mover handles together without touching the
-- underlying interface frames. A row is checked only while at least one of its
-- handles is actually shown by the mover system; unavailable and class-reserved
-- action pages are unchecked and disabled.
-- ---------------------------------------------------------------------------
function advanced.SetContentShown(shown)
  if not shown and advanced.ClearHighlights then advanced.ClearHighlights() end
  if advanced.title then
    if shown then advanced.title:Show() else advanced.title:Hide() end
  end
  local i
  for i = 1, table.getn(advanced.rows) do
    SetControlShown(advanced.rows[i], shown)
  end
end

function advanced.SetArrow(open)
  if not advanced.arrow or not advanced.arrow.label then return end
  local label = U.L("MOVER_ADVANCED_ANCHORS")
  advanced.arrow.label:SetText(open and ("<<  " .. label) or
                                        (label .. "  >>"))
end

function advanced.SetWidth(width)
  width = tonumber(width) or advanced.closedWidth
  if width < advanced.closedWidth then width = advanced.closedWidth end
  if width > advanced.width then width = advanced.width end
  advanced.currentWidth = width
  if advanced.panel then advanced.panel:SetWidth(width) end
end

function advanced.SetOpen(open, immediate)
  if not advanced.panel then return end
  open = open and true or false
  advanced.open = open
  advanced.SetArrow(open)
  advanced.SetContentShown(false)

  local target = open and advanced.width or advanced.closedWidth
  if open then advanced.panel:Show() end

  if immediate then
    U.StopEasing("mover.advanced")
    advanced.SetWidth(target)
    if open then
      advanced.SetContentShown(true)
    else
      advanced.panel:Hide()
    end
    return
  end

  U.StartEasing("mover.advanced", {
    from = advanced.currentWidth,
    to = target,
    duration = advanced.duration,
    ease = open and U.EaseOutCubic or U.EaseInOutCubic,
    onUpdate = advanced.SetWidth,
    onComplete = function()
      if advanced.open then
        advanced.SetContentShown(true)
      else
        advanced.panel:Hide()
      end
    end,
  })
end

function advanced.GroupLocked(group)
  if not group.actionBar then return false end
  if type(U.ActionBarIsNative) == "function" and
     U.ActionBarIsNative(group.actionBar) then return true end
  return type(U.ActionBarReservation) == "function" and
         U.ActionBarReservation(group.actionBar) ~= nil
end

-- Existing module toggles remain the single saved source of truth. nil means a
-- group has no module-level setting and therefore uses mover.anchorEnabled.
function advanced.GroupSettingValue(group)
  if not group then return nil end
  if group.actionBar then
    if type(U.ActionBarIsNative) == "function" and
       U.ActionBarIsNative(group.actionBar) then return true end
    if advanced.GroupLocked(group) or
       type(U.GetActionBarSetting) ~= "function" then return nil end
    return U.GetActionBarSetting(group.actionBar, "Enabled")
  end
  if group.nativeAuras then
    if type(U.GetNativeAuraFrameShown) ~= "function" then return nil end
    return U.GetNativeAuraFrameShown()
  end
  local setting = group.setting
  if not setting then return nil end
  local defaults = {}
  defaults[setting.key] = setting.default
  local config = U.ModuleConfig(setting.module, defaults)
  return config[setting.key] and true or false
end

function advanced.SetGroupSetting(group, value)
  if group.actionBar then
    if advanced.GroupLocked(group) or
       type(U.SetActionBarSetting) ~= "function" then return false, value end
    local stored = U.SetActionBarSetting(group.actionBar, "Enabled", value)
    return stored ~= nil, stored and true or false
  end
  if group.nativeAuras then
    if type(U.SetNativeAuraFrameShown) ~= "function" then return false, value end
    U.SetNativeAuraFrameShown(value)
    return true, U.GetNativeAuraFrameShown()
  end
  local setting = group.setting
  if not setting then return false, value end
  local defaults = {}
  defaults[setting.key] = setting.default
  U.ModuleConfig(setting.module, defaults)[setting.key] = value and true or false
  local apply = U[setting.apply]
  if type(apply) == "function" then apply() end
  return true, value and true or false
end

-- The group for one drawer key, with the lookup filled on first use.
function advanced.Group(key)
  if type(key) ~= "string" then return nil end
  if advanced.groupLookup[key] then return advanced.groupLookup[key] end
  local i
  for i = 1, table.getn(advanced.groups) do
    advanced.groupLookup[advanced.groups[i].key] = advanced.groups[i]
  end
  return advanced.groupLookup[key]
end

-- One place applies a group's visibility, whoever asked for it: the drawer
-- row, the contextual panel beside the anchor, or the element's settings page.
-- The saved preference, the handles, the content gate and the rows are all
-- written from here, so the views of one element cannot drift into several
-- settings. Returns the value that was actually stored.
function advanced.ApplyGroup(group, value)
  if not group then return nil end

  local handled, stored = advanced.SetGroupSetting(group, value)
  if handled then
    -- Older builds kept a second mover-only gate. Once a real module setting
    -- owns this row, discard that stale value so every view reads and writes
    -- exactly one saved preference.
    MoverConfig().anchorEnabled[group.key] = nil
    value = stored
  else
    MoverConfig().anchorEnabled[group.key] = value and true or false
  end

  local i
  for i = 1, table.getn(group.movers) do
    local entry = movers[group.movers[i]]
    if entry then
      if value then
        -- Handles exist only in edit mode; the content gate is persistent, so
        -- it is released whether or not the drawer is on screen. A settings
        -- page can switch an element back on with edit mode closed.
        if unlocked then ShowHandle(entry) end
        advanced.SetEntryContent(entry, true)
      else
        if activeMover == entry then SetActiveMover(nil) end
        HideHandle(entry)
        advanced.SetEntryContent(entry, false)
      end
    end
  end

  advanced.RefreshRows()

  local notify = advanced.changed[group.key]
  if type(notify) == "function" then pcall(notify, value and true or false) end
  return value and true or false
end

-- ---------------------------------------------------------------------------
-- The drawer rows as a public switch
--
-- A drawer row is the addon's show/hide for a whole HUD element. A module that
-- offers the same switch somewhere else -- a contextual mover panel, its page
-- in the settings window -- reads and writes it through these rather than
-- storing a second preference of its own.
-- ---------------------------------------------------------------------------
function U.MoverGroupEnabled(key)
  local group = advanced.Group(key)
  if not group then return nil end
  local setting = advanced.GroupSettingValue(group)
  if setting ~= nil then return setting and true or false end
  local enabled = MoverConfig().anchorEnabled
  return type(enabled) ~= "table" or enabled[key] ~= false
end

function U.SetMoverGroupEnabled(key, value)
  local group = advanced.Group(key)
  if not group then return nil end
  return advanced.ApplyGroup(group, value and true or false)
end

-- fn(enabled) whenever that element's switch is written from anywhere.
function U.OnMoverGroupChanged(key, fn)
  if type(key) ~= "string" or type(fn) ~= "function" then return false end
  advanced.changed[key] = fn
  return true
end

function advanced.GroupAvailable(group)
  if advanced.GroupSettingValue(group) ~= nil then return true end
  local i
  for i = 1, table.getn(group.movers) do
    local entry = movers[group.movers[i]]
    if entry and IsEntryAvailable(entry) then return true end
  end
  return false
end

function advanced.GroupShown(group)
  local settingValue = advanced.GroupSettingValue(group)
  if settingValue ~= nil then return settingValue and true or false end
  local i
  for i = 1, table.getn(group.movers) do
    local entry = movers[group.movers[i]]
    if entry and entry.handleShown then return true end
  end
  return false
end

function advanced.UserEnabled(entry)
  local groupKey = entry and advanced.moverKeys[entry.id]
  if not groupKey then return true end
  local group = advanced.Group(groupKey)
  local settingValue = advanced.GroupSettingValue(group)
  if settingValue ~= nil then return settingValue and true or false end
  local enabled = MoverConfig().anchorEnabled
  local actionBar = advanced.moverActionBars[entry.id]
  local reserved = actionBar and type(U.ActionBarReservation) == "function" and
                   U.ActionBarReservation(actionBar) ~= nil
  return reserved or type(enabled) ~= "table" or enabled[groupKey] ~= false
end

function advanced.EnforceHiddenContent()
  local _, entry, i
  local release = {}
  for _, entry in pairs(advanced.hiddenEntries) do
    if advanced.UserEnabled(entry) then
      table.insert(release, entry)
    else
      advanced.SetEntryContent(entry, false)
    end
  end
  for i = 1, table.getn(release) do
    advanced.SetEntryContent(release[i], true)
  end
end

-- The advanced rows control the whole HUD element, not only its edit handle.
-- Most movers own their content frame, so hiding that frame is sufficient.
-- Native-backed movers provide setEditShown to apply the same persistent gate
-- without changing their module's separate feature configuration.
function advanced.SetEntryContent(entry, shown)
  if not entry then return end

  if shown == nil or shown then
    if not entry.editContentHidden then return end
    if type(entry.setEditShown) == "function" then
      pcall(entry.setEditShown, nil)
    else
      -- Rows can only be re-enabled from edit mode. Show the owned frame
      -- directly so modules whose cached edit-state already says "shown" do
      -- not leave content hidden after the persistent gate is removed.
      pcall(entry.frame.Show, entry.frame)
    end
    entry.editContentHidden = false
    if advanced.hiddenEntries[entry.id] then
      advanced.hiddenEntries[entry.id] = nil
      advanced.hiddenCount = math.max(advanced.hiddenCount - 1, 0)
      if advanced.hiddenCount == 0 then
        U.UnregisterUpdate("mover.advanced.hidden")
      end
    end
    return
  end

  local shownOk, nowShown = pcall(entry.frame.IsShown, entry.frame)
  if not entry.editContentHidden then
    advanced.hiddenEntries[entry.id] = entry
    advanced.hiddenCount = advanced.hiddenCount + 1
    if advanced.hiddenCount == 1 then
      U.RegisterUpdate("mover.advanced.hidden", 0, advanced.EnforceHiddenContent)
    end
  end
  entry.editContentHidden = true
  if type(entry.setEditShown) == "function" then
    pcall(entry.setEditShown, false)
  elseif not shownOk or (nowShown and nowShown ~= 0) then
    pcall(entry.frame.Hide, entry.frame)
  end
end

function advanced.RefreshRow(row)
  local group = row and row.uuiAdvancedGroup
  if not group then return end
  local locked = advanced.GroupLocked(group)
  local available = advanced.GroupAvailable(group)
  local checked = advanced.GroupShown(group)
  if row.value ~= checked then row.SetValue(checked) end
  local enabled = available and not locked
  if row.enabled ~= enabled then row.SetEnabled(enabled) end
end

function advanced.RefreshRows()
  local i
  for i = 1, table.getn(advanced.rows) do
    advanced.RefreshRow(advanced.rows[i])
  end
end

function advanced.SetGroupHighlighted(group, shown)
  local i
  for i = 1, table.getn(group.movers) do
    local entry = movers[group.movers[i]]
    if entry then
      entry.listHovered = shown and entry.handleShown and true or false
      ApplyHandleState(entry)
    end
  end
end

function advanced.ClearHighlights()
  local i
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if entry and entry.listHovered then
      entry.listHovered = false
      ApplyHandleState(entry)
    end
  end
end

-- While edit mode is open, feature settings can still change underneath the
-- drawer. Keep both sides of the contract aligned: a newly available mover is
-- shown when its checkbox permits it, a mover that becomes unavailable is
-- hidden, and the checkbox follows that same result.
function advanced.Sync()
  if not unlocked then return end
  local i
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    local shown = IsEntryVisible(entry)
    if shown and not entry.handleShown then
      ShowHandle(entry)
    elseif not shown and entry.handleShown then
      HideHandle(entry)
      -- An anchor that has left the layout cannot stay selected: its
      -- contextual settings panel would be left beside an element that is no
      -- longer there. Unticking Enable in that very panel is the usual way to
      -- get here, so this is what closes it. The bar is re-enabled from its
      -- page in the settings window.
      if activeMover == entry then SetActiveMover(nil) end
    end
    advanced.SetEntryContent(entry, advanced.UserEnabled(entry))
  end
  advanced.RefreshRows()
end

function advanced.AddRow(group)
  if not advanced.panel or not group then return end

  local index = table.getn(advanced.rows) + 1
  local column = math.floor((index - 1) / advanced.rowsPerColumn)
  local line = (index - 1) - column * advanced.rowsPerColumn
  local row
  row = U.CreateCheckbox(advanced.panel, {
    name = "UnrealUIAdvancedAnchorToggle" .. index,
    text = U.L(group.labelKey, group.labelArg),
    textWidth = 132,
    rowHover = true,
    rowWidth = advanced.columnWidth - 10,
    rowHeight = 18,
    value = true,
    onEnter = function() advanced.SetGroupHighlighted(group, true) end,
    onLeave = function() advanced.SetGroupHighlighted(group, false) end,
    onChange = function(value)
      advanced.ApplyGroup(group, value)
    end,
  })
  row.uuiAdvancedGroup = group
  row.SetPoint("TOPLEFT", advanced.panel, "TOPLEFT",
               28 + column * advanced.columnWidth, -40 - line * 20)
  table.insert(advanced.rows, row)
  advanced.RefreshRow(row)
  SetControlShown(row, advanced.open)
end

function advanced.Build()
  if advanced.panel then return end

  advanced.panel = U.CreatePanel(UIParent, {
    name = "UnrealUIAdvancedMoverPanel",
    width = advanced.closedWidth,
    height = advanced.height,
  })
  advanced.panel:SetPoint("TOPLEFT", editPanel, "TOPRIGHT", -1, 0)
  pcall(advanced.panel.SetFrameStrata, advanced.panel, "HIGH")

  advanced.title = U.CreateLabel(advanced.panel, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    width = advanced.width - 40,
    justify = "LEFT",
  })
  if advanced.title then
    advanced.title:SetPoint("TOPLEFT", advanced.panel, "TOPLEFT", 28, -14)
    advanced.title:SetText(U.L("MOVER_ADVANCED_ANCHORS"))
  end

  -- A full-width, labelled row inside the edit window cannot be lost behind
  -- the drawer or missed as an unlabelled edge glyph. The double chevron keeps
  -- its open/close direction explicit while reusing the localized drawer title.
  advanced.arrow = U.CreateButton(editPanel, {
    name = "UnrealUIAdvancedMoverArrow",
    text = U.L("MOVER_ADVANCED_ANCHORS") .. "  >>",
    width = 244,
    height = 24,
    background = M.color.accentFill,
    border = M.color.accent,
    hoverBorder = M.color.accent,
    textColor = M.color.accent,
    onClick = function() advanced.SetOpen(not advanced.open, false) end,
  })
  advanced.arrow:SetPoint("TOP", editPanel, "TOP", 0, -168)
  pcall(advanced.arrow.SetFrameStrata, advanced.arrow, "HIGH")
  local levelOk, level = pcall(editPanel.GetFrameLevel, editPanel)
  if levelOk and tonumber(level) then
    pcall(advanced.panel.SetFrameLevel, advanced.panel, level + 1)
    pcall(advanced.arrow.SetFrameLevel, advanced.arrow, level + 2)
  end

  local i
  for i = 1, table.getn(advanced.groups) do
    advanced.AddRow(advanced.groups[i])
  end

  advanced.SetContentShown(false)
  advanced.panel:Hide()
  advanced.arrow:Hide()
end

function advanced.Show()
  advanced.Build()
  advanced.RefreshRows()
  -- Several HUD modules refresh every rendered frame while editing. Run after
  -- them on the shared driver so an unchecked entry cannot be re-shown between
  -- slower polling intervals.
  U.RegisterUpdate("mover.advanced.sync", 0, advanced.Sync)
  advanced.arrow:Show()
  advanced.SetOpen(advanced.open, true)
end

function advanced.Hide()
  U.UnregisterUpdate("mover.advanced.sync")
  U.StopEasing("mover.advanced")
  advanced.SetContentShown(false)
  if advanced.panel then advanced.panel:Hide() end
  if advanced.arrow then advanced.arrow:Hide() end
end

-- Keyboard input is deliberately scoped to edit mode. Runtime evidence shows
-- a shown keyboard-enabled Frame captures every key and cannot propagate the
-- rest of the input layer, but that is safe while this modal edit mode is open.
-- It must be a plain Frame and use OnKeyDown; Buttons and OnKeyUp do not work.
local function ResolveKey(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  local legacy = U.G("arg1")
  if type(legacy) == "string" then return legacy end
  return nil
end

local function NudgeActiveMover(x, y)
  local entry = activeMover
  if not entry or entry.dragging or not IsEntryVisible(entry) then return false end

  -- Keyboard nudges deliberately bypass both grid and magnet snapping so each
  -- arrow press moves exactly one pixel. They still preserve drag grouping:
  -- nothing is towed by a live anchor, and touching anchors travel together.
  PinToUIParent(entry)
  PinPassengers(entry)

  local position = U.GetPosition(entry.id) or entry.default
  if not position then
    position = ReadPlacement(entry.frame)
    if not position or position.relative ~= UIParent then
      U.Print(U.L("MOVER_DRAG_FIRST", entry.label))
      return false
    end
  end

  entry.followers = MoverConfig().groupTouching and CollectFollowers(entry) or {}
  entry.followerSet = {}
  local followerIndex
  for followerIndex = 1, table.getn(entry.followers) do
    entry.followerSet[entry.followers[followerIndex].entry.id] = true
  end

  local nextX = (tonumber(position.x) or 0) + x
  local nextY = (tonumber(position.y) or 0) + y

  local saved = U.SavePosition(entry.id, position.point, position.relativePoint,
                               nextX, nextY)
  if saved then
    U.ApplyFramePoint(entry.frame, U.GetPosition(entry.id))
    FinishFollowers(entry, position)
  end
  ClearFollowers(entry)
  return saved
end

local function CreateEditKeys()
  editKeys = CreateFrame("Frame", "UnrealUIMoverKeys", UIParent)
  pcall(editKeys.SetAllPoints, editKeys, UIParent)
  pcall(editKeys.SetFrameStrata, editKeys, "FULLSCREEN_DIALOG")
  pcall(editKeys.EnableKeyboard, editKeys, true)
  pcall(editKeys.EnableMouse, editKeys, false)

  editKeys:SetScript("OnKeyDown", function(a, b)
    local key = ResolveKey(a, b)
    if key == "LEFT" then
      NudgeActiveMover(-1, 0)
    elseif key == "RIGHT" then
      NudgeActiveMover(1, 0)
    elseif key == "UP" then
      NudgeActiveMover(0, 1)
    elseif key == "DOWN" then
      NudgeActiveMover(0, -1)
    elseif key == "ESCAPE" then
      U.LockUI()
    end
  end)
  editKeys:Hide()
end

-- rendering.parent_alpha_not_propagated: children are shown and hidden
-- explicitly rather than relying on the parent's visibility carrying.
local function ShowEditOverlay()
  if not editPanel then CreateEditPanel() end
  if not editKeys then CreateEditKeys() end

  local config = MoverConfig()
  editPanel.gridToggle.SetValue(config.gridShown)
  editPanel.magnetToggle.SetValue(config.magnet)
  editPanel.gridSlider.SetValue(GridSize())
  if config.gridShown then U.ShowAlignmentGrid() else U.HideAlignmentGrid() end
  editPanel:Show()
  editKeys:Show()
  if editPanel.title then editPanel.title:Show() end
  if editPanel.hint3 then editPanel.hint3:Show() end
  SetControlShown(editPanel.gridToggle, true)
  SetControlShown(editPanel.magnetToggle, true)
  SetControlShown(editPanel.groupToggle, true)
  SetControlShown(editPanel.gridSlider, true)
  if editPanel.save then editPanel.save:Show() end
  if editPanel.reset then editPanel.reset:Show() end
  advanced.Show()
end

local function HideEditOverlay()
  U.HideAlignmentGrid()
  HideAlignmentGuides()
  U.HideConfirm("mover.reset")
  if type(U.HideMoverPanel) == "function" then
    U.HideMoverPanel()
  end
  if editKeys then editKeys:Hide() end
  if not editPanel then return end

  if editPanel.title then editPanel.title:Hide() end
  if editPanel.hint3 then editPanel.hint3:Hide() end
  SetControlShown(editPanel.gridToggle, false)
  SetControlShown(editPanel.magnetToggle, false)
  SetControlShown(editPanel.groupToggle, false)
  SetControlShown(editPanel.gridSlider, false)
  if editPanel.save then editPanel.save:Hide() end
  if editPanel.reset then editPanel.reset:Hide() end
  advanced.Hide()
  editPanel:Hide()
end

function U.GridSize()
  return GridSize()
end

-- The alignment grid is shared by edit mode and other full-screen placement
-- modes. Callers own their mode lifetime and must hide it when they close.
function U.ShowAlignmentGrid()
  if not grid then CreateGrid() else LayoutGrid() end
  grid:Show()
  return grid
end

function U.HideAlignmentGrid()
  if grid then grid:Hide() end
end

-- ---------------------------------------------------------------------------
-- Edit-mode diagnostic snapshot
--
-- Anchors that appear on the first unlock and not on the second cannot be
-- diagnosed from chat: CreateEditKeys' keyboard capture means no slash command
-- is reachable while edit mode is open, and the per-mover readout is far past
-- what is worth screenshotting. Every unlock and lock therefore appends one
-- machine-readable snapshot to UnrealUIDiagDB.moverLog, read straight out of
-- SavedVariables after a /reload.
--
-- Write-only, capped by U.AppendDiagnostic, and every client call is pcall'd:
-- the diagnostic must never become the thing that breaks edit mode.
-- ---------------------------------------------------------------------------
local function Probe(object, method)
  if not object then return "-" end
  local fn = object[method]
  if type(fn) ~= "function" then return "?" end
  local ok, value = pcall(fn, object)
  if not ok then return "err" end
  if value == nil then return "nil" end
  return value
end

local function Stamp()
  if type(date) ~= "function" then return "?" end
  local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S")
  if ok and type(formatted) == "string" then return formatted end
  return "?"
end

-- failures is the list built by the Show/HideHandle walks below: a mover whose
-- handle call threw is exactly what a blank edit mode looks like, and it is
-- invisible in any readback taken afterwards.
local function SnapshotMovers(phase, failures, overlayError)
  if type(U.AppendDiagnostic) ~= "function" then return end

  local entries, i = {}, nil
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    local handle = entry and entry.handle
    table.insert(entries, {
      id = entry and entry.id or "?",
      order = i,
      entryVisible = entry and IsEntryVisible(entry) and true or false,
      frameShown = Probe(entry and entry.frame, "IsShown"),
      frameVisible = Probe(entry and entry.frame, "IsVisible"),
      frameLevel = Probe(entry and entry.frame, "GetFrameLevel"),
      frameAlpha = Probe(entry and entry.frame, "GetAlpha"),
      hasHandle = handle and true or false,
      handleShown = Probe(handle, "IsShown"),
      handleVisible = Probe(handle, "IsVisible"),
      handleLevel = Probe(handle, "GetFrameLevel"),
      handleWidth = Probe(handle, "GetWidth"),
      handleHeight = Probe(handle, "GetHeight"),
    })
  end

  U.AppendDiagnostic("moverLog", {
    phase = phase,
    at = Stamp(),
    unlocked = unlocked and true or false,
    moverCount = table.getn(moverOrder),
    overlayError = overlayError,
    failures = failures,
    gridShown = Probe(grid, "IsShown"),
    panelShown = Probe(editPanel, "IsShown"),
    keysShown = Probe(editKeys, "IsShown"),
    entries = entries,
  })
end

-- One mover whose handle call throws must not cost every anchor after it in
-- moverOrder, which an unguarded walk did. Each call is isolated and the
-- failure recorded for the snapshot instead.
local function WalkHandles(action)
  local i, failures = nil, nil
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    local ok, err = pcall(action, entry)
    if not ok then
      failures = failures or {}
      table.insert(failures, {
        id = entry and entry.id or "?",
        order = i,
        err = tostring(err),
      })
      U.Error("mover " .. (entry and entry.id or "?") .. ": " .. tostring(err))
    end
  end
  return failures
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- A window that is dragged directly and never registers a mover still needs
-- the same bottom-edge conversion the anchorEdge option gives a mover: a drag
-- the client collapses onto a TOP point would otherwise make a content-sized
-- window grow downwards, pushing its lower rows off the screen. Takes the same
-- id, frame and default a mover entry carries so both paths run one
-- implementation instead of a module-local copy. modules/bags.lua is the
-- current caller.
function U.PinFrameToBottomEdge(id, frame, default)
  if type(id) ~= "string" or not frame then
    U.Error("PinFrameToBottomEdge requires an id and a frame")
    return false
  end

  NormaliseAnchorEdge({
    id = id,
    frame = frame,
    anchorEdge = "BOTTOM",
    default = default,
  })
  return true
end

-- id       stable string key, also the SavedVariables key
-- frame    the frame the user drags
-- options  { label = "Player", default = { point, relativePoint, x, y },
--            visible = function() return true end,
--            setEditShown = function(falseOrNil) end,
--            inputStrata = "HIGH" }
function U.RegisterMover(id, frame, options)
  if type(id) ~= "string" or not frame then
    U.Error("RegisterMover requires an id and a frame")
    return nil
  end
  if movers[id] then
    U.Error("mover already registered: " .. id)
    return movers[id]
  end

  options = options or {}

  local entry = {
    id = id,
    frame = frame,
    label = options.label or id,
    default = options.default,
    visible = options.visible,
    setEditShown = options.setEditShown,
    -- Optional edit-mode-only input override for a native target whose own
    -- children otherwise sit above the transparent drag/click Button.
    inputStrata = options.inputStrata,
    -- "BOTTOM" for a window that changes height with its content: it is then
    -- always held by its bottom edge and grows upwards. See NormaliseAnchorEdge.
    anchorEdge = options.anchorEdge,
    dragging = false,
    -- Measured drag activity; reported by U.MoverReport.
    enters = 0,
    dragStarts = 0,
    dragStops = 0,
  }

  movers[id] = entry
  table.insert(moverOrder, id)

  pcall(frame.SetMovable, frame, true)
  -- Position is applied immediately, not deferred to a tick.
  ApplyStoredPosition(entry)

  advanced.SetEntryContent(entry, advanced.UserEnabled(entry))
  if unlocked then
    ShowHandle(entry)
  end
  if advanced.panel then advanced.RefreshRows() end
  return entry
end

function U.IsUnlocked()
  return unlocked
end

function U.UnlockUI()
  unlocked = true
  if U.db then U.db.locked = false end

  SetActiveMover(nil)

  -- Isolated for the same reason the handle walk is: the overlay failing must
  -- not stop every anchor from being shown, and the error has to survive into
  -- the snapshot rather than vanishing under error suppression.
  local overlayOk, overlayError = pcall(ShowEditOverlay)
  if not overlayOk then
    U.Error("mover overlay: " .. tostring(overlayError))
  else
    overlayError = nil
  end

  local failures = WalkHandles(ShowHandle)
  if advanced.panel then advanced.Sync() end
  SnapshotMovers("unlock", failures, overlayError and tostring(overlayError))
  -- Handles only exist from the first unlock, so the arm-time snapshot has no
  -- layering to show; this one does.
  if trace.on then
    trace.atUnlock = trace.Snapshot()
    trace.lockedAt = nil
    trace.Publish("unlocked")
  end

  U.Print(U.L("MOVER_ENTERED"))
end

-- Diagnostic driver, every frame while the tracer is armed.
--
--   * focus: GetMouseFocus (documented, pcall-guarded) whenever it changes,
--     named and mapped to the mover part it is, so a handle that cannot be
--     clicked shows what takes the cursor instead.
--   * drift: every mover's live rect every 0.25 s; a change is logged with
--     whether a drag was in progress, so an anchor moved by its own module
--     (after a drop, after lock, on a target change) is caught.
--   * after lock: keeps watching for LOCK_WATCH seconds, then saves.
function trace.Watch()
  if not trace.on then
    U.UnregisterUpdate("mover.diag")
    return
  end
  local now = GetTime()
  local i

  local focusFn = U.G("GetMouseFocus")
  if type(focusFn) == "function" then
    local ok, focus = pcall(focusFn)
    local name = ok and trace.Name(focus) or "error"
    if name ~= trace.lastFocus then
      trace.lastFocus = name
      local part = nil
      if ok and focus then
        for i = 1, table.getn(moverOrder) do
          local entry = movers[moverOrder[i]]
          if entry then
            if focus == entry.handle then part = entry.id .. ":handle"
            elseif focus == entry.dragInput then part = entry.id .. ":input"
            elseif focus == entry.frame then part = entry.id .. ":frame" end
          end
          if part then break end
        end
      end
      local cursorOk, cx, cy = pcall(U.G("GetCursorPosition"))
      local scale = Edge(UIParent, "GetEffectiveScale") or 1
      if scale <= 0 then scale = 1 end
      trace.Log(trace.focus, {
        focus = name, part = part,
        widget = ok and part == nil and focus and trace.Widget(focus) or nil,
        cursorX = cursorOk and Rounded((tonumber(cx) or 0) / scale) or nil,
        cursorY = cursorOk and Rounded((tonumber(cy) or 0) / scale) or nil,
      })
    end
  end

  if now >= trace.nextDrift then
    trace.nextDrift = now + 0.25
    local dragging = nil
    for i = 1, table.getn(moverOrder) do
      local entry = movers[moverOrder[i]]
      if entry and entry.dragging then dragging = entry.id end
    end
    for i = 1, table.getn(moverOrder) do
      local entry = movers[moverOrder[i]]
      if entry then
        local left, right, bottom, top = LiveRect(entry)
        local key = left and (Rounded(left) .. "," .. Rounded(bottom) .. "," ..
                              Rounded(right) .. "," .. Rounded(top)) or "none"
        local last = trace.rects[entry.id]
        if last and last ~= key then
          local stored = U.GetPosition(entry.id)
          trace.Log(trace.drift, {
            id = entry.id, from = last, to = key, dragging = dragging,
            storedX = stored and Rounded(stored.x),
            storedY = stored and Rounded(stored.y),
            storedPoint = stored and stored.point,
            points = Edge(entry.frame, "GetNumPoints"),
            parent = trace.Widget(entry.frame).parent,
          })
        end
        trace.rects[entry.id] = key
      end
    end
  end

  if trace.lockedAt and now - trace.lockedAt >= trace.LOCK_WATCH then
    local _, count, dropped = trace.Stop("lock+" .. trace.LOCK_WATCH .. "s")
    U.Print("mover snap trace: " .. tostring(count) .. " samples" ..
            (dropped > 0 and (", " .. tostring(dropped) .. " dropped") or "") ..
            " saved to UnrealUIDiagDB.moveSnap - |cffffff00/reload|r then " ..
            "open " .. U.SavedVariablesHint() .. " to read it")
  end
end

function U.LockUI()
  -- The tracer is armed before edit mode because no command can be typed while
  -- the overlay is up. Closing the overlay starts a short watch instead of
  -- ending the run, so an anchor its module moves after the drop is recorded.
  if trace.on and not trace.lockedAt then
    trace.afterLock = trace.Snapshot()
    trace.lockedAt = GetTime()
    trace.Publish("locked, watching")
    U.Print("mover snap trace: watching " .. trace.LOCK_WATCH ..
            " s more (change target now), then it saves itself")
  end

  unlocked = false
  if U.db then U.db.locked = true end

  HideEditOverlay()

  local failures = WalkHandles(HideHandle)
  SnapshotMovers("lock", failures)

  U.Print(U.L("MOVER_SAVED"))
end

function U.ToggleUI()
  if unlocked then U.LockUI() else U.UnlockUI() end
end

-- Called after /uui reset has cleared the position store, so a callback can
-- re-anchor its frame from scratch. Return true when a frame was restored, so
-- it is counted in the same total the movers are.
function U.OnPositionReset(callback)
  if type(callback) ~= "function" then
    U.Error("OnPositionReset requires a function")
    return false
  end
  table.insert(resetHooks, callback)
  return true
end

-- Drops every saved position and puts each registered frame back on its
-- module-supplied default.
function U.ResetPositions()
  U.ClearAllPositions()

  local i, restored = nil, 0
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if ApplyStoredPosition(entry) then restored = restored + 1 end
  end

  for i = 1, table.getn(resetHooks) do
    local ok, handled = pcall(resetHooks[i])
    if ok and handled then restored = restored + 1 end
  end

  U.Print(U.LN("MOVER_RESET", restored))
  return restored
end

-- Re-applies the stored (or default) point of the mover that owns `frame`.
-- For a module that changes a registered frame's own scale after
-- RegisterMover already placed it: the moveSnap trace of 2026-09-11 recorded
-- the 0.75 modern-wow cast bar stored at x=831, y=-344 but drawn at left 623.33,
-- top 318 -- the offsets are resolved with the frame's scale at SetPoint time,
-- so a point applied at scale 1 and then rescaled lands somewhere else after
-- every reload.
function U.ReapplyMoverPosition(frame)
  if not frame then return false end
  local i
  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    if entry and entry.frame == frame then
      return ApplyStoredPosition(entry)
    end
  end
  return false
end

function U.MoverCount()
  return table.getn(moverOrder)
end

-- Reports what the client actually did with each mover, so a drag that does not
-- work produces measured detail instead of a shrug. `enters` distinguishes "no
-- mouse input reached the handle" from "input arrived but the move failed", and
-- movable/mouse are read back rather than assumed from the setter succeeding.
function U.MoverReport()
  local report, i = {}, nil

  for i = 1, table.getn(moverOrder) do
    local entry = movers[moverOrder[i]]
    local line = {
      id = entry.id,
      enters = entry.enters,
      dragStarts = entry.dragStarts,
      dragStops = entry.dragStops,
      hasHandle = entry.handle and true or false,
      saved = U.GetPosition(entry.id) and true or false,
    }

    -- A readback of `false` is a real answer and must not be collapsed into the
    -- "call unavailable" case, so ok is tested on its own.
    local ok, value = pcall(entry.frame.IsMovable, entry.frame)
    if ok then line.movable = value else line.movable = "?" end

    line.mouse = "-"
    if entry.handle then
      ok, value = pcall(entry.handle.GetObjectType, entry.handle)
      if ok and value then line.handleType = value else line.handleType = "?" end

      ok, value = pcall(entry.handle.IsMouseEnabled, entry.handle)
      if ok then line.mouse = value else line.mouse = "?" end
    end

    local point, _, _, x, y = U.GetFramePoint(entry.frame, 1)
    line.point = point or "none"
    line.x = x
    line.y = y

    table.insert(report, line)
  end

  return report
end
