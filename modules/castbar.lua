-- unrealUI :: modules/castbar.lua
--
-- The player's cast bar: the spell icon flush against the left edge, and the
-- progress bar filling the rest of the width to the right edge, carrying the
-- spell name and the remaining time drawn directly on top of the fill.
--
-- knowledge.json / castbar.player_events_partial (RUNTIME_PLUS_WORKING_SOURCE):
-- SPELLCAST_START and SPELLCAST_STOP are the two cast events observed firing on
-- this client (events.json, 6 captures each). The captured SPELLCAST_START
-- argument shape is *not* Vanilla's own (spell, rank, castTime) tuple: it
-- arrived as arg1="Fireball" (string, spell name), arg2=1500 (number,
-- milliseconds) -- no rank argument at all. This module reads exactly that
-- shape and nothing more. It does not call UnitCastingInfo or UnitChannelInfo,
-- which the same record explicitly says not to assume a tuple contract for on
-- this client (knowledge.json / castbar.target_polling_contract_unverified is
-- the sibling record covering why a target castbar built the same way pfUI
-- builds one is not attempted here).
--
-- Channelled casts (fishing among them) are handled the same way, but on
-- WORKING_SOURCE evidence rather than a runtime capture: query_compat.py has
-- no record at all of SPELLCAST_CHANNEL_START firing on this client (an
-- evidence gap, not a contradiction), so per .claude/rules/unreal-pfui.md this
-- defaults to what UnrealPfUI's libs/libcast.lua demonstrably does with it
-- (libcast.lua:219) -- arg1=castTimeMs, arg2=name, the reverse order from
-- SPELLCAST_START. That reversal lines up with this client's already-confirmed
-- non-standard SPELLCAST_START shape, which is why it's taken as the default
-- rather than the vanilla (duration-only, no name) contract. Unconfirmed until
-- tested against an actual channelled cast (e.g. fishing) in game.
--
-- Two pieces of this bar rest on WORKING_SOURCE evidence, not on measured
-- runtime evidence, because query_compat.py returns no match at all for either
-- (api.json only covers the `core` and `actionbars` groups):
--
--   * The spell icon. SPELLCAST_START carries a name and a duration and no
--     texture, so the name is resolved to an icon by walking the spellbook with
--     GetNumSpellTabs / GetSpellTabInfo / GetSpellName / GetSpellTexture --
--     the same four calls UnrealPfUI's libs/libspell.lua uses on this same
--     client (GetSpellMaxRank / GetSpellIndex / GetSpellInfo). Every call goes
--     through Call() so a missing or differently-shaped API degrades to the
--     question-mark placeholder instead of erroring. See knowledge.json /
--     castbar.spell_icon_spellbook_lookup_unverified.
--   * Cast pushback. Getting hit mid-cast is reported by SPELLCAST_DELAYED in
--     Vanilla, and UnrealPfUI's libs/libcast.lua handles it as
--     `start = start + arg1/1000` -- i.e. the cast's start is pushed forward,
--     which rolls the fill backwards and grows the remaining time, exactly the
--     native behaviour. This module does the same. The event has *no* capture
--     in events.json, so whether this client emits it is unconfirmed; if it
--     never fires, the bar simply runs to its original duration as before. The
--     /uui check readout counts the delays actually received so this can be
--     settled from a real fight. See knowledge.json /
--     castbar.pushback_delay_event_unconfirmed.
--
-- Themes with native chrome (themes/classic-wow.lua) keep the client's own
-- CastingBarFrame instead of this one: every cast the client draws a bar for --
-- a spell, a channel, a quest-object loot channel -- stays in the client's own
-- style rather than mixing one modern bar into an otherwise native interface.
-- None of the unrealUI bar is built and, more importantly,
-- SuppressNativeCastbar is not called, so the stock frame keeps the events and
-- scripts the client gave it and needs no API assumption from us.
--
-- It still gets a mover. The native bar is placed the way modules/petbar.lua
-- places the native pet bar, for the same reasons and with the same two modes:
-- an unrealUI-owned anchor frame carries the handle, and until the player has
-- actually dropped that handle the anchor follows the native bar and nothing is
-- written to it at all, so an untouched interface keeps the client's own
-- castbar position. The client's anchor is captured before the mover is
-- registered and replayed from U.OnPositionReset, because it need not be
-- UIParent-relative and so cannot be expressed as a mover `default`.
--
-- Two things differ from the pet bar. The native castbar is hidden whenever
-- there is no cast, so the anchor frame is the thing that stays shown and
-- carries the handle -- a bar that only exists mid-cast could never be dragged
-- into place. And the anchor is given a floor height, because the stock bar is
-- too thin to be a comfortable grab target; placement is unaffected, since the
-- native bar is anchored CENTER-to-CENTER and neither frame needs to know how
-- large the other is. There is no target castbar mover in this mode: this
-- client has no native target castbar to place, and the unrealUI one is an
-- empty placeholder (see the scope note below).
--
-- Scope this module still does not cover, and why:
--   * A target castbar. The only known implementation strategy (pfUI's) polls
--     UnitCastingInfo/UnitChannelInfo per unit, and that contract is
--     INCONCLUSIVE on this client. Left out until it is confirmed.
--
--     UnrealPfUI's libs/libcast.lua does not actually call a native
--     UnitCastingInfo/UnitChannelInfo -- on a Vanilla-shaped client neither
--     exists for non-player units, so libcast *defines* those two globals
--     itself. Its own cast data comes from two sources, neither of them a cast
--     API: player casts from the same SPELLCAST_* events this module already
--     reads, and non-player casts from regex-matching combat-log text (e.g.
--     "%s begins to cast %s.") off CHAT_MSG_SPELL_* events, looked up against
--     a static per-spell-name cast-time table (L["spells"]). query_compat.py
--     has no record at all for CHAT_MSG_SPELL or that combat-log phrasing, so
--     this fallback is exactly as unverified on this client as the native
--     tuple it would replace -- it is not a usable evidence-gap default here,
--     only a second thing that would need its own probe. A target castbar
--     mover anchor is registered below (castbar.target) so the frame can be
--     placed now; it carries no live cast data until one of these two paths
--     is confirmed.

local U = UnrealUI
local M = U.media

local CB = U.RegisterModule("castbar")

-- Cell layout: the icon is flush against the bar cell (no gap between them),
-- and the bar cell takes the rest of WIDTH up to the right edge -- there is no
-- separate cell for the timer, which is drawn on top of the bar instead.
local HEIGHT = 24
local WIDTH = 230
local ICON_SIZE = HEIGHT
local BAR_WIDTH = WIDTH - ICON_SIZE

-- Shown whenever the spellbook lookup cannot produce a real icon, so the left
-- cell is never an empty hole.
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Registered defensively: none of these has ever been observed firing
-- (events.json has no capture for any of them), so they cost nothing if this
-- client never sends one and end the cast cleanly if it does.
local STOP_EVENTS = {
  "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
  "SPELLCAST_CHANNEL_STOP",
}

local bar
local casting = false
local startTime, duration
local lastTimeText

-- Anchor-only: mover target for a future target castbar. No cast events feed
-- it yet (see the header note on castbar.target_polling_contract_unverified
-- and the CHAT_MSG_SPELL evidence gap), so it only ever shows the idle
-- placeholder, and only while the UI is unlocked -- there is no live state to
-- show it for otherwise.
local targetBar

-- knowledge.json / castbar.native_frame_suppression_unverified: both
-- UnrealPfUI and PotatoUI suppress this client's stock player castbar through
-- the global CastingBarFrame. This is WORKING_SOURCE evidence rather than a
-- focused runtime result, so every operation is guarded and a missing or
-- differently shaped native frame leaves the UnrealUI castbar functional.
local nativeCastbarSuppressed = false

-- Set in OnEnable: true when the active theme draws stock client chrome, in
-- which case this module stands down entirely (see the header note).
local nativeChrome = false

local function SuppressNativeCastbar()
  local native = U.G("CastingBarFrame")
  if not native then return end

  if type(native.UnregisterAllEvents) == "function" then
    pcall(native.UnregisterAllEvents, native)
  end

  if type(native.SetScript) == "function" then
    pcall(native.SetScript, native, "OnShow", function()
      if type(native.Hide) == "function" then
        pcall(native.Hide, native)
      end
    end)
  end

  if type(native.Hide) == "function" then
    nativeCastbarSuppressed = pcall(native.Hide, native)
  end
end

-- Pushback bookkeeping, reported by /uui check: how many SPELLCAST_DELAYED
-- events this client actually delivered, and how much time they added.
local delayCount = 0
local delaySeconds = 0
local lastIconSource = "none"

-- Same shape as modules/actionbar.lua's helper: a global that is missing or
-- differently shaped here returns nil rather than erroring.
local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2 = pcall(fn, a, b)
  if not ok then return nil end
  return r1, r2
end

-- ---------------------------------------------------------------------------
-- Spell name -> icon
--
-- SPELLCAST_START gives a name only, so the name is matched against the
-- spellbook once per spell and cached. `false` is cached for a miss too, so a
-- spell that is not in the book (an item or a trinket proc) is not re-scanned
-- on every cast.
-- ---------------------------------------------------------------------------
local iconCache = {}

local function ScanSpellbook(lowerName)
  local bookType = U.G("BOOKTYPE_SPELL") or "spell"

  local tabs = tonumber(Call("GetNumSpellTabs"))
  if not tabs then return nil end

  local tab
  for tab = 1, tabs do
    -- GetSpellTabInfo returns name, texture, offset, numSpells in Vanilla;
    -- only the last two are used, and Call hands back the first two returns,
    -- so the tab info is read through a direct pcall instead.
    local fn = U.G("GetSpellTabInfo")
    if type(fn) ~= "function" then return nil end

    local ok, _, _, offset, count = pcall(fn, tab)
    offset, count = tonumber(offset), tonumber(count)

    if ok and offset and count then
      local id
      for id = offset + 1, offset + count do
        local spellName = Call("GetSpellName", id, bookType)
        if type(spellName) == "string" and
           string.lower(spellName) == lowerName then
          local texture = Call("GetSpellTexture", id, bookType)
          if type(texture) == "string" and texture ~= "" then
            return texture
          end
          return nil
        end
      end
    end
  end

  return nil
end

local function SpellIcon(name)
  if type(name) ~= "string" or name == "" then return nil end

  local key = string.lower(name)
  local cached = iconCache[key]
  if cached ~= nil then
    return cached or nil
  end

  local texture = ScanSpellbook(key)
  iconCache[key] = texture or false
  return texture
end

-- A spellbook miss (Hearthstone, a quest item, any other non-spell cast) used
-- to fall back to the question-mark placeholder texture; that read as a wrong
-- icon rather than an honest "no icon available", so a miss now hides the
-- whole icon cell instead (via widget.showIcon, see SetWidgetCellsShown) --
-- not just the texture, so its flat background/border don't hang around as an
-- empty box either. FALLBACK_ICON is still used for the idle placeholder
-- (ApplyIdlePlaceholder), which is a different case -- there's no cast at all
-- to have an icon for.
local function ApplyIcon(name)
  if not bar.icon then return end

  local texture = SpellIcon(name)
  lastIconSource = texture and "spellbook" or "none"

  if not texture then
    bar.showIcon = false
    return
  end

  if pcall(bar.icon.SetTexture, bar.icon, texture) then
    bar.showIcon = true
  else
    lastIconSource = "failed"
    bar.showIcon = false
  end
end

-- ---------------------------------------------------------------------------
-- Bar state
-- ---------------------------------------------------------------------------

local function ApplyTimer(remaining)
  if not bar.time then return end
  local text = string.format("%.1f", remaining)
  if text == lastTimeText then return end
  lastTimeText = text
  bar.time:SetText(text)
end

-- knowledge.json / rendering.parent_alpha_not_propagated: the cells are shown
-- and hidden explicitly rather than left to the container, on the same
-- reasoning the rest of unrealUI uses for composite frames.
--
-- The icon cell is additionally gated by widget.showIcon: when a cast has no
-- resolved icon (see ApplyIcon), the whole cell -- its flat background and
-- border, not just the texture -- is hidden instead of leaving an empty box
-- with nothing in it.
local function SetWidgetCellsShown(widget, shown)
  local i
  for i = 1, table.getn(widget.uuiCells) do
    local cell = widget.uuiCells[i]
    local cellShown = shown
    if cell == widget.iconCell and not widget.showIcon then
      cellShown = false
    end
    if cellShown then
      if not cell:IsShown() then cell:Show() end
    else
      if cell:IsShown() then cell:Hide() end
    end
  end
end

local function SetCellsShown(shown)
  SetWidgetCellsShown(bar, shown)
end

-- The target anchor carries no live cast state (see the header note), so its
-- only visibility rule is the edit lock: shown, with its idle placeholder,
-- while the UI is unlocked, and hidden otherwise.
local function UpdateTargetVisibility()
  if not targetBar then return end
  local shown = U.IsUnlocked()
  if shown then
    if not targetBar:IsShown() then targetBar:Show() end
  else
    if targetBar:IsShown() then targetBar:Hide() end
  end
  SetWidgetCellsShown(targetBar, shown)
end

-- Kept shown and given a placeholder fill while the UI is unlocked, on the
-- same reasoning as the unit frames' empty-unit shell: a frame that only
-- exists while it has something to show could never be dragged into place.
local function ApplyIdlePlaceholder()
  U.SetStatusBarColor(bar.bar, M.Unpack(M.color.cast))
  pcall(bar.bar.SetMinMaxValues, bar.bar, 0, 1)
  pcall(bar.bar.SetValue, bar.bar, 0.4)
  if bar.name then bar.name:SetText(U.L("MOVER_LABEL_CASTBAR")) end
  if bar.icon then pcall(bar.icon.SetTexture, bar.icon, FALLBACK_ICON) end
  bar.showIcon = true
  -- Applied immediately rather than waiting for the next Tick's
  -- UpdateVisibility: a cast that just ended with no icon left the cell
  -- hidden, and it would otherwise stay hidden for one extra frame.
  SetCellsShown(true)
  lastTimeText = nil
  if bar.time then bar.time:SetText("0.0") end
end

local function UpdateVisibility()
  local shown = casting or U.IsUnlocked()
  if shown then
    if not bar:IsShown() then bar:Show() end
  else
    if bar:IsShown() then bar:Hide() end
  end
  SetCellsShown(shown)
end

local function StartCast(name, castTimeMs)
  casting = true
  startTime = GetTime()
  duration = (tonumber(castTimeMs) or 0) / 1000
  -- A zero or missing duration would divide-by-zero the fill computation in
  -- core/style.lua; treat it as an effectively-instant cast instead.
  if duration <= 0 then duration = 0.01 end

  delayCount, delaySeconds = 0, 0

  U.SetStatusBarColor(bar.bar, M.Unpack(M.color.cast))
  pcall(bar.bar.SetMinMaxValues, bar.bar, 0, duration)
  pcall(bar.bar.SetValue, bar.bar, 0)
  if bar.name then bar.name:SetText(tostring(name or "")) end
  ApplyIcon(name)
  lastTimeText = nil
  ApplyTimer(duration)

  UpdateVisibility()
end

-- Cast pushback. UnrealPfUI's libs/libcast.lua does exactly this on
-- SPELLCAST_DELAYED (`start = start + arg1/1000`): the start moves forward, so
-- the elapsed time this module derives from it shrinks and the fill rolls
-- backwards while the remaining time grows -- the native castbar's behaviour.
-- The total duration is deliberately untouched; only the end point moves.
local function DelayCast(delayMs)
  if not casting then return end

  local delay = (tonumber(delayMs) or 0) / 1000
  if delay <= 0 then return end

  startTime = startTime + delay
  delayCount = delayCount + 1
  delaySeconds = delaySeconds + delay

  -- Redraw immediately rather than waiting up to a tick: a pushback that only
  -- showed on the next 0.1s tick would read as a stutter, not a rollback.
  local elapsed = GetTime() - startTime
  if elapsed < 0 then elapsed = 0 end
  pcall(bar.bar.SetValue, bar.bar, elapsed)
  ApplyTimer(duration - elapsed)
end

local function StopCast()
  if not casting then return end
  casting = false
  UpdateVisibility()
end

local function Tick()
  if U.PerfDisabled and U.PerfDisabled("castbar") then return end

  UpdateVisibility()
  UpdateTargetVisibility()

  if not casting then
    if bar:IsShown() then ApplyIdlePlaceholder() end
    return
  end

  local elapsed = GetTime() - startTime
  if elapsed >= duration then
    -- No stop event arrived before the computed duration ran out. Treat the
    -- cast as finished rather than leaving a full bar on screen indefinitely.
    StopCast()
    return
  end

  -- A pushback can move the start ahead of now for a frame; clamp rather than
  -- hand the fill a negative value.
  if elapsed < 0 then elapsed = 0 end

  pcall(bar.bar.SetValue, bar.bar, elapsed)
  ApplyTimer(duration - elapsed)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- Shared cell layout for both the player bar and the target anchor: the
-- icon flush left, the progress bar filling the rest of the width, name and
-- timer drawn on top of the fill. `frameName` distinguishes the created
-- widget names so registering both bars does not collide.
local function BuildBarWidget(frameName)
  local widget = CreateFrame("Frame", frameName, UIParent)
  widget:SetWidth(WIDTH)
  widget:SetHeight(HEIGHT)

  local border = U.BorderSize()

  -- Left cell: the spell icon.
  local iconCell = U.CreatePanel(widget, {
    name = frameName .. "Icon",
    width = ICON_SIZE,
    height = HEIGHT,
  })
  iconCell:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)

  local icon = iconCell:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", iconCell, "TOPLEFT", border, -border)
  icon:SetPoint("BOTTOMRIGHT", iconCell, "BOTTOMRIGHT", -border, border)
  -- Trimmed the way modules/actionbar.lua trims its icons, so the stock icon
  -- border does not show inside the cell.
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  pcall(icon.SetTexture, icon, FALLBACK_ICON)
  widget.icon = icon
  widget.iconCell = iconCell
  widget.showIcon = true

  -- Right cell: the progress bar, flush against the icon and filling the rest
  -- of the width to the right edge, with the spell name and the timer both
  -- drawn on top of it.
  local barCell = U.CreatePanel(widget, {
    name = frameName .. "Progress",
    width = BAR_WIDTH,
    height = HEIGHT,
  })
  barCell:SetPoint("TOPLEFT", iconCell, "TOPRIGHT", 0, 0)

  widget.bar = U.CreateStatusBar(barCell, {
    width = BAR_WIDTH - 2 * border,
    height = HEIGHT - 2 * border,
    color = M.color.cast,
    background = M.color.healthBg,
  })
  widget.bar:SetPoint("TOPLEFT", barCell, "TOPLEFT", border, -border)

  -- knowledge.json / fonts.stretched_justification_ignored: anchored to the
  -- one edge it belongs to, with an explicit width so a long spell name stops
  -- before the timer instead of running under it.
  widget.name = U.CreateLabel(widget.bar, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if widget.name then
    widget.name:SetPoint("LEFT", widget.bar, "LEFT", 3, 0)
    pcall(widget.name.SetWidth, widget.name, BAR_WIDTH - 34)
  end

  -- The timer. A FontString's OVERLAY draw layer sits above the fill
  -- texture's ARTWORK layer, so parenting it directly to the bar draws it on
  -- top of the progress fill rather than in a separate cell.
  widget.time = U.CreateLabel(widget.bar, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if widget.time then widget.time:SetPoint("RIGHT", widget.bar, "RIGHT", -3, 0) end

  widget.uuiCells = { iconCell, barCell }

  return widget
end

local function Build()
  -- The container carries no art of its own: it is the mover target and the
  -- anchor the two cells hang off, so each cell keeps its own outline the way
  -- the reference layout shows them.
  bar = BuildBarWidget("UnrealUICastBar")
  bar:Hide()
  SetCellsShown(false)

  U.RegisterMover("castbar.player", bar, {
    label = U.L("MOVER_LABEL_CASTBAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -220 },
  })

  -- Anchor-only target castbar (see the header note): built the same way as
  -- the player bar so its placeholder matches, but nothing ever calls
  -- StartCast/StopCast on it. It is shown only while the UI is unlocked, on
  -- the same reasoning as the player bar's idle placeholder -- a frame that
  -- only exists once it has data could never be dragged into place.
  targetBar = BuildBarWidget("UnrealUICastBarTarget")
  U.SetStatusBarColor(targetBar.bar, M.Unpack(M.color.cast))
  pcall(targetBar.bar.SetMinMaxValues, targetBar.bar, 0, 1)
  pcall(targetBar.bar.SetValue, targetBar.bar, 0.4)
  if targetBar.name then targetBar.name:SetText(U.L("MOVER_LABEL_TARGET_CASTBAR")) end
  if targetBar.time then targetBar.time:SetText("0.0") end
  targetBar:Hide()

  U.RegisterMover("castbar.target", targetBar, {
    label = U.L("MOVER_LABEL_TARGET_CASTBAR"),
    default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -250 },
  })
end

-- ---------------------------------------------------------------------------
-- Native castbar mover
--
-- Only used under a native-chrome theme, where the client draws the castbar and
-- this module draws nothing. Same shape as modules/petbar.lua: the native frame
-- is never hidden, reskinned, re-parented or click-handled -- it is only
-- re-anchored, and only once the player has placed the handle.
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted: anchors are read
-- through U.GetFramePoint, which hands back values in the shape SetPoint wants,
-- so a capture goes straight back through SetPoint unchanged.
-- ---------------------------------------------------------------------------

local NATIVE_NAME = "CastingBarFrame"

-- Used until the native frame reports its own size, and as the footprint if it
-- never does. The floor height is a grab target, not a claim about the bar.
local NATIVE_FALLBACK_WIDTH = 195
local NATIVE_FALLBACK_HEIGHT = 13
local HANDLE_MIN_HEIGHT = 20

-- Anchor offsets below this are treated as unchanged rather than drift.
local DRIFT_EPSILON = 0.5

local nativeFrame
local nativeMoverAnchor
local capturedNativeAnchor
local nativeDriving = false

-- Counts SetPoint calls on the native frame that did not go through. Reported
-- by /uui cb: a bar sitting in the wrong place with a non-zero count here is a
-- refused anchor, not a client that re-anchored its own frame.
local driveFailures = 0

local function CaptureNativeAnchor()
  if not nativeFrame then return nil end

  local point, relative, relativePoint, x, y = U.GetFramePoint(nativeFrame, 1)
  if type(point) ~= "string" then
    U.Debug("castbar: no readable native anchor to capture")
    return nil
  end

  if not relative then
    local ok, parent = pcall(nativeFrame.GetParent, nativeFrame)
    if ok then relative = parent end
  end
  if not relative then relative = UIParent end

  return {
    point = point,
    relative = relative,
    relativePoint = relativePoint or point,
    x = x,
    y = y,
  }
end

local function RestoreNativeAnchor()
  if not nativeFrame or not capturedNativeAnchor then return false end

  local ok = pcall(function()
    nativeFrame:ClearAllPoints()
    nativeFrame:SetPoint(capturedNativeAnchor.point,
                         capturedNativeAnchor.relative,
                         capturedNativeAnchor.relativePoint,
                         capturedNativeAnchor.x, capturedNativeAnchor.y)
  end)

  if ok then
    nativeDriving = false
    U.Debug("castbar: native castbar anchor restored")
  end
  return ok
end

local function NativeStoredPosition()
  local ok, position = pcall(U.GetPosition, "castbar.player")
  if not ok or type(position) ~= "table" then return nil end
  if type(position.point) ~= "string" then return nil end
  return position
end

-- Written only when it actually changes: this runs on a shared tick and the
-- handle is SetAllPoints to this frame, so a size write is a handle relayout
-- for nothing.
local function MirrorNativeSize()
  if not nativeMoverAnchor or not nativeFrame then return end

  local okW, w = pcall(nativeFrame.GetWidth, nativeFrame)
  local okH, h = pcall(nativeFrame.GetHeight, nativeFrame)

  w = okW and tonumber(w) or nil
  h = okH and tonumber(h) or nil

  local width = (w and w > 0 and w) or NATIVE_FALLBACK_WIDTH
  local height = (h and h > 0 and h) or NATIVE_FALLBACK_HEIGHT
  if height < HANDLE_MIN_HEIGHT then height = HANDLE_MIN_HEIGHT end

  if nativeMoverAnchor.uuiWidth ~= width then
    nativeMoverAnchor:SetWidth(width)
    nativeMoverAnchor.uuiWidth = width
  end
  if nativeMoverAnchor.uuiHeight ~= height then
    nativeMoverAnchor:SetHeight(height)
    nativeMoverAnchor.uuiHeight = height
  end
end

local function AnchorDrifted(position)
  local point, relative, relativePoint, x, y =
    U.GetFramePoint(nativeMoverAnchor, 1)
  if type(point) ~= "string" then return true end
  if relative and relative ~= UIParent then return true end
  if point ~= position.point then return true end
  if relativePoint ~= (position.relativePoint or position.point) then return true end
  if math.abs(x - (tonumber(position.x) or 0)) > DRIFT_EPSILON then return true end
  if math.abs(y - (tonumber(position.y) or 0)) > DRIFT_EPSILON then return true end
  return false
end

-- Has the client re-anchored its own bar out from under us?
--
-- The point count is checked first, and deliberately. A frame keeps every
-- anchor set on it and is positioned by all of them at once, but GetPoint(1)
-- reports only the first -- so a second point added after DriveNative's
-- ClearAllPoints moves the bar while leaving point 1 still reading as ours.
-- Testing point 1 alone cannot see that, and reports no drift for a bar that
-- has visibly moved.
local function NativeDrifted()
  local okCount, count = pcall(nativeFrame.GetNumPoints, nativeFrame)
  if okCount and tonumber(count) and tonumber(count) ~= 1 then return true end

  local point, relative, relativePoint, x, y = U.GetFramePoint(nativeFrame, 1)
  if type(point) ~= "string" then return true end
  if relative ~= nativeMoverAnchor then return true end
  if point ~= "CENTER" or relativePoint ~= "CENTER" then return true end
  if math.abs(x) > DRIFT_EPSILON or math.abs(y) > DRIFT_EPSILON then return true end
  return false
end

-- Centre-on-centre needs neither frame to know how wide the other is, which is
-- what lets the handle carry a floor height without shifting the bar.
-- nativeDriving is set from the pcall result, not unconditionally. Claiming the
-- drive succeeded when the SetPoint was refused would leave ApplyNativeAnchor
-- believing it owned an anchor it had never written, and would hide exactly the
-- failure /uui cb exists to find.
local function DriveNative()
  local ok = pcall(function()
    nativeFrame:ClearAllPoints()
    nativeFrame:SetPoint("CENTER", nativeMoverAnchor, "CENTER", 0, 0)
  end)

  if ok then
    nativeDriving = true
  else
    driveFailures = driveFailures + 1
    if driveFailures == 1 then
      U.Debug("castbar: re-anchoring " .. NATIVE_NAME .. " was refused")
    end
  end
end

local function FollowNative()
  pcall(function()
    nativeMoverAnchor:ClearAllPoints()
    nativeMoverAnchor:SetPoint("CENTER", nativeFrame, "CENTER", 0, 0)
  end)
end

local function ApplyNativeAnchor()
  if U.PerfDisabled and U.PerfDisabled("castbar") then return end
  if not nativeMoverAnchor or not nativeFrame then return end

  MirrorNativeSize()

  local position = NativeStoredPosition()
  local unlocked = U.IsUnlocked()

  if not position then
    -- Never placed, or /uui reset: hand the bar back to the client once, then
    -- keep the handle shadowing it. Not mid-drag -- re-anchoring the handle to
    -- the native bar then would snap it out of the player's hand.
    if nativeDriving then RestoreNativeAnchor() end
    if not unlocked then FollowNative() end
    return
  end

  -- The mover owns the anchor between StartMoving and StopMovingOrSizing, so
  -- the stored position is only re-applied while locked. The native bar is
  -- anchored *to* the anchor, so it tracks the handle live during a drag with
  -- no second write.
  if not unlocked and AnchorDrifted(position) then
    U.ApplyFramePoint(nativeMoverAnchor, position)
  end

  if NativeDrifted() then DriveNative() end
end

local function SetupNativeMover()
  nativeFrame = U.G(NATIVE_NAME)
  if not nativeFrame then
    U.Debug("castbar: " .. NATIVE_NAME .. " not found; no castbar mover")
    return
  end

  -- Before RegisterMover, which is what may apply a stored position.
  capturedNativeAnchor = CaptureNativeAnchor()

  -- Carries a mover handle and nothing else: no backdrop, no mouse, no strata
  -- of its own. It must never sit in front of the bar it is placing.
  nativeMoverAnchor = CreateFrame("Frame", "UnrealUICastBarAnchor", UIParent)
  nativeMoverAnchor:SetWidth(NATIVE_FALLBACK_WIDTH)
  nativeMoverAnchor:SetHeight(HANDLE_MIN_HEIGHT)
  MirrorNativeSize()
  FollowNative()
  -- Stays shown even though the bar it places does not: the native castbar
  -- only exists mid-cast, and a handle that only appeared mid-cast could not
  -- be dragged.
  nativeMoverAnchor:Show()

  -- Same id as the modern bar's mover, so a position placed under one theme is
  -- the position used under the other. No `default`: the client's own anchor
  -- need not be UIParent-relative and cannot be written as one, which is the
  -- case core/mover.lua documents U.OnPositionReset for.
  U.RegisterMover("castbar.player", nativeMoverAnchor, {
    label = U.L("MOVER_LABEL_CASTBAR"),
  })
  U.OnPositionReset(function() return RestoreNativeAnchor() end)

  ApplyNativeAnchor()

  -- Accelerators, so a cast that starts right after the client re-anchors its
  -- bar is not drawn in the old place for up to one tick. The tick below is
  -- the guarantee; these only make it prompt.
  local refresh = function() ApplyNativeAnchor() end
  U.RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
  U.RegisterEvent("SPELLCAST_START", refresh)
  U.RegisterEvent("SPELLCAST_CHANNEL_START", refresh)

  -- One anchor read twice a second against a frame that rarely moves. The
  -- modern bar's per-frame tick is not registered in this mode at all.
  U.RegisterUpdate("castbar.anchor", 0.5, ApplyNativeAnchor)
end

-- ---------------------------------------------------------------------------
-- /uui cb -- native castbar placement dump
--
-- Armed rather than immediate, the way /uui map arms its hover watch: the
-- native castbar only exists mid-cast, so there is nothing to measure at the
-- moment the command is typed.
--
-- It samples twice -- the frame as soon as it is shown, and again a moment
-- later -- because the open questions have different signatures, and one
-- sample cannot tell them apart:
--
--   * the anchor still reads CENTER -> UnrealUICastBarAnchor in both samples,
--     but the visible bar is somewhere else -- a child carries its own anchor,
--     and moving the parent moves nothing;
--   * the anchor reads ours in the first sample and something else in the
--     second -- the client re-anchors its own bar when it shows, and the fix
--     has to re-drive from that moment rather than from a tick;
--   * the anchor never reads ours at all -- the SetPoint in DriveNative is
--     failing, or the frame drawing the bar is not this one.
--
-- Children are listed with their own rects because documentation.json names
-- CastingBarFrameStatusBar as a frame that exists on this client, which is
-- exactly the shape the first case would take.
-- ---------------------------------------------------------------------------

local DUMP_SECOND_SAMPLE = 0.3
local DUMP_TIMEOUT = 30

-- Timed off GetTime rather than the tick argument: the shared updater hands a
-- callback its registered *interval*, which is 0 for a per-tick consumer like
-- this one and would never accumulate.
local dumpArmed = false
local dumpArmedAt = 0
local dumpShownAt = nil
local dumpFirst = nil

local function Num(value)
  value = tonumber(value)
  if not value then return "?" end
  return string.format("%.0f", value)
end

local function FrameName(frame)
  if not frame then return "nil" end
  local ok, name = pcall(frame.GetName, frame)
  if ok and type(name) == "string" and name ~= "" then return name end
  return "<unnamed>"
end

-- One frame's placement as a list of printable lines. Everything is read
-- through pcall so a frame that does not answer a method costs one line of the
-- dump rather than the whole command.
local function DescribeFrame(frame, label, lines)
  if not frame then
    table.insert(lines, label .. ": missing")
    return
  end

  local okShown, shown = pcall(frame.IsShown, frame)
  local okParent, parent = pcall(frame.GetParent, frame)
  table.insert(lines, label .. ": shown " ..
               tostring(okShown and shown and true or false) ..
               ", parent " .. FrameName(okParent and parent or nil))

  -- Every point, not just the first. A frame carrying a second anchor is
  -- positioned by both, while GetPoint(1) keeps reporting only the first --
  -- which is how a bar can report an anchor it is visibly not sitting on.
  -- Read raw rather than through U.GetFramePoint, because that helper inverts
  -- Y for round-tripping through SetPoint and this needs the client's own
  -- numbers.
  local okCount, count = pcall(frame.GetNumPoints, frame)
  count = okCount and tonumber(count) or nil

  if not count then
    table.insert(lines, "  points: GetNumPoints unavailable")
  else
    table.insert(lines, "  points: " .. count)
    local i
    for i = 1, count do
      local ok, point, relative, relativePoint, x, y =
        pcall(frame.GetPoint, frame, i)
      if ok and type(point) == "string" then
        if type(relative) == "string" then relative = U.G(relative) end
        table.insert(lines, "   [" .. i .. "] " .. point .. " -> " ..
                     FrameName(relative) .. "." .. tostring(relativePoint) ..
                     "  " .. Num(x) .. "," .. Num(y) .. " (raw)")
      else
        table.insert(lines, "   [" .. i .. "] unreadable")
      end
    end
  end

  local okL, left = pcall(frame.GetLeft, frame)
  local okB, bottom = pcall(frame.GetBottom, frame)
  local okW, width = pcall(frame.GetWidth, frame)
  local okH, height = pcall(frame.GetHeight, frame)
  table.insert(lines, "  rect " .. Num(okL and left) .. "," ..
               Num(okB and bottom) .. "  " .. Num(okW and width) .. "x" ..
               Num(okH and height))
end

-- The child list is the whole point of the first hypothesis: a child anchored
-- to something other than its parent stays put when the parent moves.
local function DescribeChildren(frame, lines)
  if not frame or type(frame.GetChildren) ~= "function" then
    table.insert(lines, "  children unavailable")
    return
  end

  local ok, c1, c2, c3, c4, c5, c6 = pcall(frame.GetChildren, frame)
  if not ok then
    table.insert(lines, "  children unreadable")
    return
  end

  local kids = { c1, c2, c3, c4, c5, c6 }
  local i, found = nil, 0
  for i = 1, 6 do
    if kids[i] then
      found = found + 1
      DescribeFrame(kids[i], "  child " .. i .. " " .. FrameName(kids[i]),
                    lines)
    end
  end
  if found == 0 then table.insert(lines, "  no child frames") end
end

local function Sample(label)
  local lines = {}
  table.insert(lines, "-- " .. label .. " --")
  DescribeFrame(nativeFrame, NATIVE_NAME, lines)
  DescribeChildren(nativeFrame, lines)
  DescribeFrame(nativeMoverAnchor, "UnrealUICastBarAnchor", lines)
  return lines
end

local function PrintLines(lines)
  local i
  for i = 1, table.getn(lines) do
    U.Print(lines[i])
  end
end

local function DumpTick()
  if not dumpArmed then return end

  local now = GetTime()

  if not dumpShownAt then
    if now - dumpArmedAt > DUMP_TIMEOUT then
      dumpArmed = false
      U.UnregisterUpdate("castbar.dump")
      U.Print("castbar dump: no cast started within " ..
              DUMP_TIMEOUT .. "s; disarmed")
      return
    end

    local ok, shown = pcall(nativeFrame.IsShown, nativeFrame)
    if not (ok and shown) then return end

    dumpShownAt = now
    dumpFirst = Sample("at show")
    return
  end

  if now - dumpShownAt < DUMP_SECOND_SAMPLE then return end

  local second = Sample("+" .. DUMP_SECOND_SAMPLE .. "s")

  dumpArmed = false
  U.UnregisterUpdate("castbar.dump")

  U.Print("castbar dump: placed " ..
          tostring(NativeStoredPosition() and true or false) ..
          ", driving " .. tostring(nativeDriving) ..
          ", drive errors " .. tostring(driveFailures))
  PrintLines(dumpFirst)
  PrintLines(second)
end

-- Reached from /uui cb.
function U.CastbarNativeDump()
  if not nativeChrome then
    U.Print("castbar dump: only applies under a native-chrome theme; " ..
            "the active theme is " .. tostring(U.GetActiveThemeStyle()))
    return
  end
  if not nativeFrame then
    U.Print("castbar dump: " .. NATIVE_NAME .. " was not found at load")
    return
  end

  dumpArmed = true
  dumpArmedAt = GetTime()
  dumpShownAt = nil
  dumpFirst = nil
  U.RegisterUpdate("castbar.dump", 0, DumpTick)
  U.Print("castbar dump armed: cast something, or open a quest object")
end

function CB:OnEnable()
  if bar then return end

  -- Before Build() and before SuppressNativeCastbar(): under a native-chrome
  -- theme the client's own castbar is the castbar, so this module creates
  -- nothing, hides nothing and registers nothing at all.
  nativeChrome = type(U.ThemeStyleUsesNativeChrome) == "function" and
                 U.ThemeStyleUsesNativeChrome() or false
  if nativeChrome then
    U.Debug("castbar: native chrome theme; leaving CastingBarFrame alone")
    SetupNativeMover()
    return
  end

  Build()
  SuppressNativeCastbar()

  U.RegisterEvent("SPELLCAST_START", function(event, name, castTimeMs)
    StartCast(name, castTimeMs)
  end)

  -- Reversed argument order from SPELLCAST_START -- see the header note on
  -- the channelled-cast evidence gap (castTimeMs first, name second, per
  -- UnrealPfUI's libcast.lua:219).
  U.RegisterEvent("SPELLCAST_CHANNEL_START", function(event, castTimeMs, name)
    StartCast(name, castTimeMs)
  end)

  U.RegisterEvent("SPELLCAST_DELAYED", function(event, delayMs)
    DelayCast(delayMs)
  end)

  local i
  for i = 1, table.getn(STOP_EVENTS) do
    U.RegisterEvent(STOP_EVENTS[i], StopCast)
  end

  -- Same invalidation UnrealPfUI's libspell uses: a newly learned rank changes
  -- which spellbook index a name resolves to.
  U.RegisterEvent("LEARNED_SPELL_IN_TAB", function()
    iconCache = {}
  end)

  -- 0 runs every frame, the same convention core/widgets.lua's slider drag
  -- ticker uses for per-frame motion: at 0.1s the fill visibly stepped
  -- instead of sliding, since ApplyTimer's own text-change check already
  -- throttles the one part of Tick that doesn't need to run every frame.
  U.RegisterUpdate("castbar.tick", 0, Tick)
end

-- Measured state for /uui check: what the client actually sent, not another
-- assumption about the SPELLCAST_START tuple. iconSource and delays are the
-- two fields that settle the WORKING_SOURCE gaps in this module's header --
-- whether the spellbook lookup resolves a real texture, and whether this
-- client emits SPELLCAST_DELAYED at all.
function U.CastbarReport()
  if nativeChrome then
    return {
      native = true,
      nativeSuppressed = false,
      nativeFound = nativeFrame and true or false,
      anchor = nativeMoverAnchor and true or false,
      placed = NativeStoredPosition() and true or false,
      driving = nativeDriving,
      driveFailures = driveFailures,
      nativeAnchorCaptured = capturedNativeAnchor and true or false,
    }
  end
  if not bar then return nil end

  local shownOk, shown = pcall(bar.IsShown, bar)
  return {
    casting = casting,
    shown = shownOk and shown or "?",
    duration = duration,
    remaining = casting and (duration - (GetTime() - startTime)) or nil,
    iconSource = lastIconSource,
    delays = delayCount,
    delaySeconds = delaySeconds,
    nativeSuppressed = nativeCastbarSuppressed,
  }
end
