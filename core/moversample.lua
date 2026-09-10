-- unrealUI :: core/moversample.lua
--
-- Placeholder content for anchors that are empty while Move UI is open.
--
-- Several unrealUI anchors hold nothing most of the time. The tooltip anchor
-- is a bare owned frame, the pet bar has no buttons without a pet, the armour
-- durability paper doll only appears once equipment is damaged, and an aura
-- row hides itself when the unit carries no auras. Their mover handles are
-- still drawn, but an empty handle does not show what will occupy the space or
-- which way it will grow, so those anchors are placed blind.
--
-- This file draws a sample of the missing content inside such an anchor, and
-- only while edit mode is open. Nothing here is ever part of the live
-- interface: every sample is taken down again by U.LockUI.
--
-- Two kinds of sample:
--
--   cells / lines  the shared flat primitives below, built and owned here. A
--                  module supplies counts, not geometry -- the cells are
--                  fitted to the anchor's own footprint, so a sample can never
--                  disagree with the handle it sits in.
--   apply          the module draws its own placeholder, because the real
--                  content's position is that module's layout code and not
--                  the anchor rectangle (modules/auras.lua stacks its rows
--                  outside the unit frame). This file only says when.
--
-- rules/unreal-ui-design.md: flat tinted WHITE8X8 surfaces with one explicit
-- one-unit outline, no rounded corners, no native art. The colours are the
-- mover family from core/media.lua rather than the ordinary panel tokens --
-- a sample is edit-mode chrome, and must not read as the real element.

local U = UnrealUI
local M = U.media

-- id -> specs. One mover can own several independent samples: the party anchor
-- carries aura rows and HoT icons while the unit-frame module draws its empty
-- member/pet shells. Keeping each module's spec separate lets them share the
-- handle's lifetime without one registration replacing another.
local samples = {}
local sampleOrder = {}

-- Ids whose handle is currently shown. Edit mode can open with a pet out and
-- close without one, so "is this anchor empty" is re-read on a slow tick for
-- as long as any sample is live, and not only at unlock.
local live = {}
local liveCount = 0

local REFRESH_INTERVAL = 0.25
local REFRESH_ID = "mover.sample"

-- Cell geometry. Only the bounds are fixed here: the drawn size is fitted to
-- the anchor, so a ten-slot pet bar sample matches the bar's real footprint
-- without this file knowing anything about pet buttons.
local CELL_INSET = 2
local CELL_SPACING = 2
local CELL_MIN = 4
local CELL_MAX = 44

local LINE_INSET = 6
local LINE_SPACING = 4
local LINE_HEIGHT = 6

local function Number(value, fallback)
  if type(value) == "function" then
    local ok, result = pcall(value)
    if ok then value = result else value = nil end
  end
  return tonumber(value) or fallback
end

-- Measured in UIParent units through the frame's own getters, which is the
-- only space core/mover.lua drives layout from. A frame that reports nothing
-- yet (built this frame, never laid out) simply gets no sample this pass.
local function Size(frame)
  if not frame then return nil, nil end
  local okW, width = pcall(frame.GetWidth, frame)
  local okH, height = pcall(frame.GetHeight, frame)
  width = okW and tonumber(width) or nil
  height = okH and tonumber(height) or nil
  if not width or not height or width <= 0 or height <= 0 then return nil, nil end
  return width, height
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- The frame the sample is drawn in. Defaults to the mover's own frame, which
-- is unrealUI-owned in every case a sample is registered for -- rules/
-- unreal-ui.md forbids anchoring an addon frame to a client-owned child, and
-- a native-backed mover (pet bar, durability) already places its handle on an
-- owned anchor for that reason.
local function Host(spec)
  if spec.host then return spec.host end

  local frame
  if type(spec.frame) == "function" then
    local ok, value = pcall(spec.frame)
    if ok then frame = value end
  elseif spec.frame then
    frame = spec.frame
  elseif type(U.MoverFrame) == "function" then
    frame = U.MoverFrame(spec.id)
  end

  if not frame or type(frame.CreateTexture) ~= "function" then return nil end
  spec.host = frame
  return frame
end

local function Container(spec)
  if spec.container then return spec.container end

  local host = Host(spec)
  if not host then return nil end

  -- No backdrop of its own: the handle already supplies the tinted surface,
  -- and a second fill over it would only darken the anchor. Mouse is off so
  -- the sample can never win hit-testing from the drag handle above it.
  local container = CreateFrame("Frame", nil, host)
  container:SetAllPoints(host)
  pcall(container.EnableMouse, container, false)
  container:Hide()

  spec.container = container
  spec.cellFrames = {}
  spec.lineTextures = {}
  return container
end

-- One placeholder square: the shared primitive for "an icon goes here". Public
-- because a module that lays its own sample out (modules/auras.lua) must still
-- draw the same square as the samples built in this file -- rules/
-- unreal-ui-design.md, "Do not build local variants".
function U.CreateMoverSampleCell(parent)
  if not parent or type(parent.CreateTexture) ~= "function" then return nil end

  local cell = CreateFrame("Frame", nil, parent)
  pcall(cell.EnableMouse, cell, false)
  U.CreateBackdrop(cell, {
    background = M.color.moverSample,
    border = M.color.moverSampleEdge,
  })
  cell:Hide()
  return cell
end

local function Cell(spec, index)
  local cell = spec.cellFrames[index]
  if cell then return cell end

  cell = U.CreateMoverSampleCell(spec.container)
  spec.cellFrames[index] = cell
  return cell
end

local function Line(spec, index)
  local line = spec.lineTextures[index]
  if line then return line end

  line = spec.container:CreateTexture(nil, "ARTWORK")
  line:SetTexture(M.texture.plain)
  U.SetColor(line, M.Unpack(M.color.moverSampleEdge))
  spec.lineTextures[index] = line
  return line
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- A block of square cells, centred in the anchor and sized to fill it. Used
-- for anything whose real content is a row or grid of icons: pet action
-- slots, aura icons, the durability paper doll.
local function LayoutCells(spec, width, height)
  local cells = spec.cells
  local count = math.floor(Number(cells.count, 0))
  if count < 1 then return 0 end

  local perRow = math.floor(Number(cells.perRow, count))
  if perRow < 1 then perRow = count end

  local spacing = Number(cells.spacing, CELL_SPACING)
  local inset = Number(cells.inset, CELL_INSET)
  local columns = count < perRow and count or perRow
  local lines = math.floor((count - 1) / perRow) + 1

  local usableW = width - inset * 2 - spacing * (columns - 1)
  local usableH = height - inset * 2 - spacing * (lines - 1)
  local size = Number(cells.size, nil)
  if not size then
    size = usableW / columns
    local fitH = usableH / lines
    if fitH < size then size = fitH end
    if size > CELL_MAX then size = CELL_MAX end
  end
  if size < CELL_MIN then size = CELL_MIN end

  local blockW = columns * size + spacing * (columns - 1)
  local blockH = lines * size + spacing * (lines - 1)
  local originX = -blockW / 2 + size / 2
  local originY = blockH / 2 - size / 2

  local index
  for index = 1, count do
    -- No `%` and no math.mod: core/widgets.lua records both as
    -- version-specific on this client, and modules/auras.lua lays its own
    -- icon grid out with exactly this arithmetic.
    local line = math.floor((index - 1) / perRow)
    local column = (index - 1) - line * perRow
    local cell = Cell(spec, index)
    -- A container that cannot carry a cell means no sample at all rather than
    -- a half-drawn one: return what was placed so far and let HideExtra take
    -- the rest down.
    if not cell then return index - 1 end
    cell:SetWidth(size)
    cell:SetHeight(size)
    cell:ClearAllPoints()
    cell:SetPoint("CENTER", spec.container, "CENTER",
                  originX + column * (size + spacing),
                  originY - line * (size + spacing))
    cell:Show()
  end
  return count
end

-- Stacked bars standing in for text. Each entry is { width, height }, with
-- width as a fraction of the anchor's usable width, so the sample keeps its
-- shape whatever size the anchor is dragged to.
local function LayoutLines(spec, width, height)
  local lines = spec.lines
  local count = table.getn(lines)
  if count < 1 then return 0 end

  local spacing = Number(lines.spacing, LINE_SPACING)
  local inset = Number(lines.inset, LINE_INSET)
  local usable = width - inset * 2
  if usable < 1 then usable = 1 end

  local index, offset = nil, inset
  for index = 1, count do
    local entry = lines[index]
    local lineHeight = Number(entry.height, LINE_HEIGHT)
    local fraction = Number(entry.width, 1)
    if fraction > 1 then fraction = 1 end
    if fraction < 0.05 then fraction = 0.05 end

    -- A sample that would spill past the bottom edge is simply not drawn:
    -- the anchor is smaller than the content it stands in for, and drawing
    -- outside it would misreport the footprint being placed.
    if offset + lineHeight > height - inset then
      count = index - 1
      break
    end

    local line = Line(spec, index)
    line:SetWidth(usable * fraction)
    line:SetHeight(lineHeight)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", spec.container, "TOPLEFT", inset, -offset)
    line:Show()
    offset = offset + lineHeight + spacing
  end
  return count
end

local function HideExtra(list, from)
  local index
  for index = from, table.getn(list) do
    list[index]:Hide()
  end
end

local function Layout(spec)
  local container = Container(spec)
  if not container then return false end

  local width, height = Size(Host(spec))
  if not width then return false end

  local usedCells, usedLines = 0, 0
  if spec.cells then usedCells = LayoutCells(spec, width, height) end
  if spec.lines then usedLines = LayoutLines(spec, width, height) end

  HideExtra(spec.cellFrames, usedCells + 1)
  HideExtra(spec.lineTextures, usedLines + 1)
  return (usedCells + usedLines) > 0
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- Without a predicate an anchor counts as always empty, which is right for the
-- anchors that hold nothing by construction (the tooltip guide). Anything with
-- real content of its own supplies one.
local function IsEmpty(spec)
  if type(spec.isEmpty) ~= "function" then return true end
  local ok, empty = pcall(spec.isEmpty)
  if not ok then return false end
  return empty and true or false
end

local function SetShown(spec, shown)
  if shown and not spec.available then shown = false end

  if type(spec.apply) == "function" then
    if spec.shown == shown then return end
    spec.shown = shown
    pcall(spec.apply, shown)
    return
  end

  if not shown then
    if spec.container then spec.container:Hide() end
    spec.shown = false
    return
  end

  -- Re-laid out on every show rather than only on the first: an anchor whose
  -- footprint tracks native content (the pet bar mirrors the client's own bar
  -- size) can be a different rectangle each time edit mode opens.
  if not Layout(spec) then
    if spec.container then spec.container:Hide() end
    spec.shown = false
    return
  end

  -- rendering.parent_alpha_not_propagated: the children above are shown
  -- explicitly, and so is the container.
  spec.container:Show()
  spec.shown = true
end

local function Refresh(spec)
  SetShown(spec, live[spec.id] and IsEmpty(spec))
end

local function RefreshAll()
  local index
  for index = 1, table.getn(sampleOrder) do
    Refresh(sampleOrder[index])
  end
end

local function SetTickerRunning(running)
  if running then
    U.RegisterUpdate(REFRESH_ID, REFRESH_INTERVAL, RefreshAll)
  else
    U.UnregisterUpdate(REFRESH_ID)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- id    -- mover id, exactly as registered with U.RegisterMover. Several
--          specs may register for the same id; all are refreshed together.
-- spec  -- { isEmpty, available, frame, cells, lines, apply }
--   isEmpty   optional function() -> boolean; the anchor has nothing in it
--             right now. Omitted means always empty.
--   available optional boolean, defaulting true; false suppresses the sample
--             without unregistering it.
--   frame     optional frame, or function() -> frame, to draw in. Defaults to
--             the frame the mover is registered on. Must be unrealUI-owned.
--   cells     { count, perRow, size, spacing, inset } -- a block of squares.
--             count and perRow may be functions. size is fitted to the anchor
--             when it is not given, which is the usual case.
--   lines     array of { width, height } -- stacked bars standing in for text.
--             width is a fraction of the anchor's usable width. Carries
--             optional .spacing and .inset on the array itself.
--   apply     optional function(shown); the module draws its own placeholder
--             and this file only reports the state. Takes precedence over
--             cells/lines.
function U.RegisterMoverSample(id, spec)
  if type(id) ~= "string" or type(spec) ~= "table" then
    U.Error("RegisterMoverSample requires a mover id and a spec")
    return false
  end
  if not spec.cells and not spec.lines and type(spec.apply) ~= "function" then
    U.Error("RegisterMoverSample needs cells, lines or apply: " .. id)
    return false
  end

  spec.id = id
  if spec.available == nil then spec.available = true end
  spec.shown = false

  if not samples[id] then samples[id] = {} end
  table.insert(samples[id], spec)
  table.insert(sampleOrder, spec)

  if live[id] then Refresh(spec) end
  return true
end

-- Called by core/mover.lua as a handle is shown or hidden. The sample belongs
-- to the handle's lifetime, not to the addon's: an anchor with no registered
-- sample is a no-op here, which is most of them.
function U.SetMoverSampleShown(id, shown)
  if type(id) ~= "string" then return false end

  local wasLive = live[id] and true or false
  shown = shown and true or false
  if wasLive ~= shown then
    live[id] = shown or nil
    liveCount = liveCount + (shown and 1 or -1)
    if liveCount < 0 then liveCount = 0 end
    SetTickerRunning(liveCount > 0)
  end

  local list = samples[id]
  if not list then return false end
  local i
  for i = 1, table.getn(list) do Refresh(list[i]) end
  return true
end

-- Whether a given sample-bearing anchor is live in edit mode right now. This
-- follows the handle, not one spec's transition: when several apply specs share
-- an id, every callback must observe the new state immediately while the list
-- is being turned on or off. Otherwise the first callback during teardown
-- could still see a later spec's stale `shown` flag and leave its sample up.
function U.MoverSampleShown(id)
  if type(id) ~= "string" then return liveCount > 0 end
  return (samples[id] and live[id]) and true or false
end
