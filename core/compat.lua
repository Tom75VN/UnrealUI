-- unrealUI :: core/compat.lua
--
-- Adapters for behaviours where this client is known to differ from Vanilla.
--
-- Every helper here exists because compact evidence records a real, repeated
-- incompatibility. Nothing in this file exists to imitate a pfUI API, and
-- nothing here installs a fake global or overwrites a client function.

local U = UnrealUI
local M = U.media

-- ---------------------------------------------------------------------------
-- Numeric helpers
-- ---------------------------------------------------------------------------
function U.Round(value)
  value = tonumber(value) or 0
  return math.floor(value + 0.5)
end

-- A remaining time as a short countdown string plus the tier it falls in, so
-- callers can colour it from M.cooldownText without repeating the thresholds.
--
-- The unit switch points are pfUI-modern's: days above 99 hours, hours above 99
-- minutes, minutes above 99 seconds, and tenths over the last five seconds --
-- which keeps the number at most three characters wide at every scale, the
-- reason it fits inside an action button or a 20-unit aura icon at all.
--
-- Shared rather than module-local because both modules/actionbar.lua and
-- modules/auras.lua draw this readout; see M.cooldownText.
function U.FormatTimeShort(remaining)
  remaining = tonumber(remaining) or 0

  if remaining > 356400 then
    return U.Round(remaining / 86400) .. "d", "day"
  elseif remaining > 5940 then
    return U.Round(remaining / 3600) .. "h", "hour"
  elseif remaining > 99 then
    return U.Round(remaining / 60) .. "m", "minute"
  elseif remaining <= 5 then
    return string.format("%.1f", remaining), "low"
  end
  return tostring(U.Round(remaining)), "normal"
end

-- ---------------------------------------------------------------------------
-- Screen metrics
--
-- frames.json context (BEHAVIOR_VERIFIED) records GetScreenWidth() = 1920 while
-- UIParent:GetWidth() = 1365.33, with GetScreenHeight() = 768 matching
-- UIParent:GetHeight(). The two are not in the same unit space on this client,
-- so layout must be driven from UIParent and never from GetScreenWidth.
-- ---------------------------------------------------------------------------
function U.UIWidth()
  local ok, w = pcall(UIParent.GetWidth, UIParent)
  if ok and tonumber(w) and w > 0 then return w end
  return 1024
end

function U.UIHeight()
  local ok, h = pcall(UIParent.GetHeight, UIParent)
  if ok and tonumber(h) and h > 0 then return h end
  return 768
end

-- Physical pixels per UIParent unit. Used only for reporting and for deciding
-- that a sub-unit border is not worth asking for; see core/style.lua.
function U.PixelScale()
  local ok, screen = pcall(GetScreenWidth)
  if not ok or not tonumber(screen) or screen <= 0 then return 1 end
  local width = U.UIWidth()
  if width <= 0 then return 1 end
  local scale = screen / width
  if scale < 0.5 or scale > 8 then return 1 end
  return scale
end

-- ---------------------------------------------------------------------------
-- Fonts
--
-- behavior.json / fonts.pfui_path_and_measure.v1 (BROKEN,
-- RUNTIME_FAILURE_CONFIRMED): SetFont returns cleanly while silently keeping
-- the inherited font object, and GetFont reports the inherited state rather
-- than the request. GetFont therefore cannot verify that a size was applied.
--
-- Detect by measurement instead: render the same sample at two very different
-- sizes and keep the first path whose width actually changes. Resolved once and
-- cached, because the probe frame costs a real font load.
-- ---------------------------------------------------------------------------
local fontSample = "MMMMMMMM"
local fontProbe, resolvedFont
local fontChecked = {}
local styledFonts = {}
local customFontSerial = 0

local FONT_DB_KEYS = {
  default = "defaultFont",
  unitframe = "unitFrameFont",
}

local function NormaliseFontRole(role)
  if role == "unitframe" then return role end
  return "default"
end

-- Returns a validated media id. Both roles default to their inherited native
-- FontObject; bundled faces remain explicit choices for probe work.
function U.GetFontChoice(role)
  role = NormaliseFontRole(role)
  local fallback = role == "unitframe" and M.defaultUnitFrameFontId or
                   M.defaultFontId
  local key = FONT_DB_KEYS[role]
  local value = U.db and U.db[key] or fallback

  if value == "original" then return value end
  if M.fontById[value] then return value end
  return fallback
end

local function RestoreOriginalFont(record)
  local fontstring = record.fontstring
  local original = record.original or U.G("GameFontNormal")
  if not original or not fontstring.SetFontObject then return false end
  return pcall(fontstring.SetFontObject, fontstring, original)
end

local function EnsureCustomFont(record)
  if record.customFont then return record.customFont end

  local createFont = U.G("CreateFont")
  if type(createFont) ~= "function" then return nil end

  customFontSerial = customFontSerial + 1
  local ok, font = pcall(createFont, "UnrealUICustomFont" .. customFontSerial)
  if not ok or not font then return nil end
  record.customFont = font
  return font
end

local function ApplyFontRecord(record)
  local fontstring = record.fontstring
  local choice = U.GetFontChoice(record.role)
  local applied = false

  if choice == "original" then
    applied = RestoreOriginalFont(record)
  else
    local media = M.fontById[choice]
    local font = media and EnsureCustomFont(record)
    if font and font.SetFont and fontstring.SetFontObject then
      local setOk = pcall(font.SetFont, font, media.path, record.size)
      local attachOk = false
      if setOk then
        attachOk = pcall(fontstring.SetFontObject, fontstring, font)
      end
      applied = setOk and attachOk
    end

    -- A missing or rejected font file must never make text disappear.
    if not applied then RestoreOriginalFont(record) end
  end

  return applied
end

function U.ApplyFontChoice(role)
  role = NormaliseFontRole(role)
  local fontstring, record
  for fontstring, record in pairs(styledFonts) do
    if record.role == role then ApplyFontRecord(record) end
  end
end

function U.SetFontChoice(role, value)
  role = NormaliseFontRole(role)
  if type(value) ~= "string" then return false end
  if value ~= "original" and not M.fontById[value] then return false end
  if not U.db then return false end

  U.db[FONT_DB_KEYS[role]] = value
  U.ApplyFontChoice(role)
  return true
end

local function PathResizes(path)
  if fontChecked[path] ~= nil then return fontChecked[path] end

  if not fontProbe then
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    local ok, region = pcall(holder.CreateFontString, holder, nil, "ARTWORK")
    if not ok or not region then
      fontChecked[path] = false
      return false
    end
    fontProbe = region
  end

  local function MeasureAt(size)
    if not pcall(fontProbe.SetFont, fontProbe, path, size, "OUTLINE") then return nil end
    if not pcall(fontProbe.SetText, fontProbe, fontSample) then return nil end
    local ok, width = pcall(fontProbe.GetStringWidth, fontProbe)
    if ok and tonumber(width) then return width end
    return nil
  end

  local small = MeasureAt(6)
  local large = MeasureAt(24)
  local works = false
  if small and large and small > 0 and large > small * 1.5 then works = true end

  fontChecked[path] = works
  return works
end

-- Returns the first stock font path this client demonstrably resizes, or nil.
function U.ResolveFont()
  if resolvedFont ~= nil then
    if resolvedFont == false then return nil end
    return resolvedFont
  end

  local i
  for i = 1, table.getn(M.fontCandidates) do
    local path = M.fontCandidates[i]
    if PathResizes(path) then
      resolvedFont = path
      U.Debug("font resolved: " .. path)
      return path
    end
  end

  resolvedFont = false
  U.Debug("no stock font path resized text; leaving inherited fonts alone")
  return nil
end

-- Applies a physical-pixel shadow to both owned and restyled stock text. The
-- default is the shared one-pixel treatment; compact text can request a closer
-- fractional offset. SetShadowOffset consumes UI units here: at this client's
-- measured 1920 / 1365.33 scale, an unconverted offset of 1 can rasterise
-- nearly two screen pixels away. Convert the shared physical-pixel token back
-- into UI units so the visible separation stays crisp.
--
-- The methods are documented by this client but not runtime-verified, so each
-- call remains guarded and a missing method never prevents the text itself
-- from being styled.
function U.SetTextShadow(fontstring, physicalOffset, shadowColor)
  if not fontstring then return false end

  local color = shadowColor or M.color.shadow
  local offset = physicalOffset or M.textShadowOffset
  local pixelScale = U.PixelScale()
  if pixelScale <= 0 then pixelScale = 1 end
  local colorOk, offsetOk = false, false

  if fontstring.SetShadowColor then
    colorOk = pcall(fontstring.SetShadowColor, fontstring, M.Unpack(color))
  end
  if fontstring.SetShadowOffset then
    offsetOk = pcall(fontstring.SetShadowOffset, fontstring,
                     (tonumber(offset[1]) or 1) / pixelScale,
                     (tonumber(offset[2]) or -1) / pixelScale)
  end

  return colorOk and offsetOk
end

-- A one-pixel offset is a full stroke width at the compact unit-frame font
-- size and reads as a second copy of each glyph. Components that explicitly
-- opt out use a transparent, zero-offset shadow rather than inheriting the
-- stock FontObject's wider treatment.
function U.ClearTextShadow(fontstring)
  if not fontstring then return false end

  local colorOk, offsetOk = false, false
  if fontstring.SetShadowColor then
    colorOk = pcall(fontstring.SetShadowColor, fontstring, 0, 0, 0, 0)
  end
  if fontstring.SetShadowOffset then
    offsetOk = pcall(fontstring.SetShadowOffset, fontstring, 0, 0)
  end
  return colorOk and offsetOk
end

-- Applies the selected font through a private named Font object. Direct
-- FontString:SetFont is intentionally not used: that is the silent-failure
-- path confirmed by fonts.pfui_path_and_measure.v1. Each FontString gets its
-- own Font object so later text-colour changes cannot leak into another label.
-- The original inherited object is retained for the "Original" option and as
-- a safe fallback if the documented custom-font route is unavailable.
function U.SetFont(fontstring, size, flags, role)
  if not fontstring then return false end

  local record = styledFonts[fontstring]
  if not record then
    record = { fontstring = fontstring }
    if fontstring.GetFontObject then
      local ok, original = pcall(fontstring.GetFontObject, fontstring)
      if ok then record.original = original end
    end
    styledFonts[fontstring] = record
  end

  record.size = tonumber(size) or M.fontSize.normal
  record.flags = flags
  record.role = NormaliseFontRole(role)
  local applied = ApplyFontRecord(record)
  U.SetTextShadow(fontstring)
  return applied
end

-- ---------------------------------------------------------------------------
-- Anchors
--
-- knowledge.json / frames.getpoint_relative_name_y_inverted (PARTIAL,
-- BEHAVIOR_VERIFIED): GetPoint returns the relative frame as a *name string*
-- and reports Y with the opposite sign from the SetPoint request. The verified
-- case requested BOTTOMRIGHT -> parent/BOTTOM at x=-75, y=25 and read back
-- relative="GeneratedLuaUIObject_5496", x=-75, y=-25.
--
-- Normalise here so a captured point can be persisted and re-applied through
-- SetPoint unchanged. Callers must not immediately clear and re-apply a
-- freshly captured point, which is a recorded failed approach.
-- ---------------------------------------------------------------------------
function U.GetFramePoint(frame, index)
  if not frame or not frame.GetPoint then return nil end

  local ok, point, relative, relativePoint, x, y =
    pcall(frame.GetPoint, frame, index or 1)
  if not ok or type(point) ~= "string" then return nil end

  if type(relative) == "string" then
    relative = U.G(relative)
  end

  x = tonumber(x) or 0
  y = -(tonumber(y) or 0)

  return point, relative, relativePoint, x, y
end

-- Anchors a frame to UIParent from a stored position table. Kept alongside the
-- reader so the inversion is applied and undone in one place.
function U.ApplyFramePoint(frame, position)
  if not frame or type(position) ~= "table" then return false end
  if type(position.point) ~= "string" then return false end

  local relativePoint = position.relativePoint
  if type(relativePoint) ~= "string" then relativePoint = position.point end

  local ok = pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(position.point, UIParent, relativePoint,
                   tonumber(position.x) or 0, tonumber(position.y) or 0)
  end)
  return ok
end

-- ---------------------------------------------------------------------------
-- Texture colour
--
-- knowledge.json / textures.settexturecolor_alias_missing: SetTextureColor is
-- absent, SetVertexColor is present. knowledge.json /
-- textures.getvertexcolor_readback_missing: there is no GetVertexColor to read
-- a tint back with. And unlike SetBackdropColor, SetVertexColor does not coerce
-- strings, so a non-numeric component silently leaves the texture white.
--
-- Coerce on the way in and cache what was applied so callers have a readback.
-- ---------------------------------------------------------------------------
local textureColors = {}
local function MirrorTextureColor(texture, cached) texture.uuiColor = cached end
local function ReadTextureColor(texture) return texture.uuiColor end

function U.SetColor(texture, r, g, b, a)
  if not texture or not texture.SetVertexColor then return false end

  r = tonumber(r) or 0
  g = tonumber(g) or 0
  b = tonumber(b) or 0
  a = tonumber(a) or 1

  local cached = textureColors[texture]
  if cached and cached[1] == r and cached[2] == g and
     cached[3] == b and cached[4] == a then return true end

  local ok = pcall(texture.SetVertexColor, texture, r, g, b, a)
  if ok then
    if cached then
      cached[1], cached[2], cached[3], cached[4] = r, g, b, a
    else
      cached = { r, g, b, a }
      textureColors[texture] = cached
    end
    -- Frames on this client behave as tables, but texture regions are not
    -- guaranteed to accept an arbitrary field, so this compatibility mirror
    -- is optional. The side table above is the allocation-free primary cache.
    pcall(MirrorTextureColor, texture, cached)
  end
  return ok
end

function U.GetColor(texture)
  if not texture then return nil end
  local cached = textureColors[texture]
  if cached then return cached[1], cached[2], cached[3], cached[4] end
  local ok, fallback = pcall(ReadTextureColor, texture)
  if not ok or type(fallback) ~= "table" then return nil end
  return fallback[1], fallback[2], fallback[3], fallback[4]
end

-- ---------------------------------------------------------------------------
-- Region suppression
--
-- knowledge.json / rendering.native_texture_strip_requires_alpha: native
-- texture regions can survive Hide(), SetTexture(nil) and Set*Texture("").
-- knowledge.json / rendering.parent_alpha_not_propagated: a parent at alpha 0
-- does not reliably hide its child regions.
--
-- So: clear, hide *and* zero the alpha, on the region itself.
-- ---------------------------------------------------------------------------
function U.HideRegion(region)
  if not region then return false end

  pcall(function()
    if region.SetTexture then region:SetTexture(nil) end
  end)
  pcall(function()
    if region.SetAlpha then region:SetAlpha(0) end
  end)
  pcall(function()
    if region.Hide then region:Hide() end
  end)
  return true
end

-- ---------------------------------------------------------------------------
-- Native frame suppression
--
-- knowledge.json / rendering.native_frame_hide_not_persistent: Hide() plus
-- UnregisterAllEvents() does not keep a natively driven stock frame down. This
-- client re-shows TargetFrame the moment a target is acquired, and draws named
-- child regions independently of their parent. The record's failed approaches
-- are Hide() on the root only, Hide() plus UnregisterAllEvents() on the root
-- only, and assuming a hidden parent hides its native children.
--
-- The recipe that does hold: neutralise Show(), hide, zero the alpha as a
-- renderer-independent guard (rendering.parent_alpha_not_propagated), drop
-- mouse input, name the child regions explicitly, and re-apply when the client
-- brings something back. One shared watcher serves every caller, so registering
-- more frames never adds another update.
--
-- UnregisterAllEvents is not part of that recipe at any level, and is not
-- merely redundant: repeated on a live native frame it is the measured cause of
-- the party-only freeze (knowledge.json /
-- compat.unregisterallevents_native_frame_stall). It never held a frame down
-- either, per the failed approaches above, so it bought nothing for its cost.
--
-- Show() is replaced only on frames a module explicitly names, and only once
-- per object. Nothing here installs a global or removes a client function
-- unrealUI was not asked to suppress.
-- ---------------------------------------------------------------------------
local suppressedSeen = {}
local suppressedNames = {}
-- group -> array of names. The full list above still drives the periodic sweep
-- and the count readout; the groups exist so an event that can only resurrect
-- one family of frames does not have to walk all of them. See the sweep-cost
-- note below.
local suppressedGroups = {}
local suppressionArmed = false
local suppressionCursor = 1
local SUPPRESSION_BATCH_SIZE = 60

-- knowledge.json / compat.native_suppression_pcall_burst_stutter: this sweep
-- used to resolve every name through U.G (its own pcall) and then run the full
-- ~5-pcall teardown on every object, every second, unconditionally. With unit
-- frames registering around 330 names (TargetFrame's buff/debuff series alone
-- is over 300 sub-region names), that was a synchronous burst of roughly 2000
-- pcalls once a second -- reported in game as periodic stuttering that started
-- with the unit frame feature. Two independent fixes below remove it:
-- memoizing the name -> object resolution, and skipping the teardown entirely
-- once an object is confirmed already hidden.
--
-- Second round, same record: the sweep was still bound to
-- PLAYER_TARGET_CHANGED as a whole-list re-apply, so changing target walked
-- every registered name -- around 1150 once action bars (809) joined unit
-- frames (340) and bags (5) -- in the same frame the target changed, and did
-- it on top of whatever the one-second sweep had just done. Target change is
-- also the worst case for the fast path: it is exactly when this client brings
-- TargetFrame and its children back, so those ~120 objects fail the IsShown
-- check and take the full teardown. Reported in game as a micro freeze on
-- target change. Two more fixes: bucket the names by group so an event sweeps
-- only what it can actually resurrect, and hoist every per-object pcall body
-- out of an anonymous closure so a sweep stops allocating one closure per
-- object. The pcall boundaries themselves are unchanged -- each step still
-- fails independently.
local resolvedNative = {}   -- name -> object | false
local suppressedObjects = {} -- object -> true; avoids a protected field read
-- Target widgets are owned by native code on this client. Two sustained target
-- storms ended at the 2,162,688-UObject ceiling after the client had fallen to
-- 1 fps. Preserving this family's event/Show lifecycle while only making its
-- named visuals transparent removed the freeze under the same Tab-spam test,
-- USER_CONFIRMED_INGAME. The exact native UObject creator is not exposed to
-- Lua, so retain the lifecycle-preserving recipe; see KillNativeObject.
local visualOnlyNames = {}
local visualOnlyKinds = {}
local visualObjectEpoch = {}
local targetVisualEpoch = 0
-- TargetLevelText is rewritten a few render ticks after the target event on
-- this client. Retry only this text for a short bounded window; keeping the
-- target frame lifecycle intact remains mandatory for the confirmed Tab-spam
-- stability fix.
--
-- The name matters: this retry used to resolve "TargetFrameLevel", which does
-- not exist on this client and therefore made the whole loop a no-op, which is
-- why the yellow level survived every pass. A full 29,520-entry global
-- enumeration (UnrealRuntimeProbe capture, 2026-08-16) has TargetLevelText and
-- TargetName but no TargetFrameLevel/TargetFrameName -- this client keeps
-- Vanilla's Target* naming for those two, while the bars really are
-- TargetFrameHealthBar/TargetFrameManaBar.
local TARGET_LEVEL_RETRY_PASSES = 12
local targetLevelRetryPasses = 0

-- Hoisted pcall bodies. These were anonymous closures built fresh for every
-- object on every sweep; as named upvalues they allocate nothing and keep the
-- one-pcall-per-step failure isolation the closures had.
local function NoOpShow() return end

local function NeutraliseShow(object)
  if object.Show then object.Show = NoOpShow end
end
-- There is deliberately no DropNativeEvents helper here. UnregisterAllEvents on
-- a live native frame is the measured cause of the party freeze; see the note
-- in KillNativeObject below before adding one back.
local function HideObject(object)
  if object.Hide then object:Hide() end
end
local function ZeroAlpha(object)
  if object.SetAlpha then object:SetAlpha(0) end
end
local function DropMouse(object)
  if object.EnableMouse then object:EnableMouse(false) end
end
local function ClearBarPart(part)
  if not part then return end
  -- The native renderer can ignore both widget alpha and its assigned texture,
  -- but it still lays the green fill out from the StatusBar value. Zero that
  -- first, then clear every visual representation the bridge exposes.
  if part.SetValue then part:SetValue(0) end
  if part.SetStatusBarTexture then part:SetStatusBarTexture(nil) end
  if part.SetStatusBarColor then part:SetStatusBarColor(0, 0, 0, 0) end
  if part.SetTexture then part:SetTexture(nil) end
  if part.SetTexCoord then part:SetTexCoord(0, 0, 0, 0) end
  if part.SetAlpha then part:SetAlpha(0) end
end

local function ClearBarVisual(object)
  ClearBarPart(object)

  -- This client may expose the rendered fill as either a region or a child
  -- widget, depending on which native TargetFrame object the global resolves
  -- to. Cover both shapes, bounded to this one known bar and one child level.
  local regions = object.GetRegions and { object:GetRegions() } or {}
  local children = object.GetChildren and { object:GetChildren() } or {}
  local i
  for i = 1, table.getn(regions) do ClearBarPart(regions[i]) end
  for i = 1, table.getn(children) do
    local child = children[i]
    ClearBarPart(child)
    local childRegions = child and child.GetRegions and
                         { child:GetRegions() } or {}
    local j
    for j = 1, table.getn(childRegions) do ClearBarPart(childRegions[j]) end
  end
end
local function ClearTextureVisual(object)
  if object.SetTexture then object:SetTexture(nil) end
end
local function ClearTextVisual(object)
  if object.SetText then object:SetText("") end
end

-- The steady-state readback. This used to be `pcall(object.IsShown, object)`,
-- which *throws* for any object that has no IsShown method: the index yields
-- nil and pcall then calls it, so the sweep built and discarded an error string
-- for exactly the objects it could never fast-path anyway -- once per object,
-- on every pass, forever. Reading the method inside the guarded body makes the
-- absent case a plain nil test.
--
-- shownKnown separates "the client says it is hidden" from "this object cannot
-- answer". Only the first may skip the teardown; an object that cannot answer
-- keeps taking the full re-apply exactly as it did before.
local shownKnown, shownAnswer
local alphaKnown, alphaAnswer

local function ReadShown(object)
  local fn = object.IsShown
  if not fn then return end
  shownAnswer = fn(object) and true or false
  shownKnown = true
end

local function ReadAlpha(object)
  local fn = object.GetAlpha
  if not fn then return end
  alphaAnswer = tonumber(fn(object))
  alphaKnown = alphaAnswer ~= nil
end

local function ResolveNativeObject(name)
  local cached = resolvedNative[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local object = U.G(name)
  resolvedNative[name] = object or false
  return object
end

-- Work counters. Two integer adds per object, always on: without an intra-frame
-- profiler (documentation.json / global:Helpers:debugprofilestop is a no-op
-- here) the only way to attribute the target-change cost is to count the work
-- rather than time it. statTornDown is the decisive number -- it says how many
-- objects the client actually brought back and therefore took the full
-- ~4-native-call teardown, as opposed to being confirmed already hidden.
local statVisited, statTornDown = 0, 0
local lastTargetVisited, lastTargetTornDown = 0, 0
-- ---------------------------------------------------------------------------
-- When the recipe is applied, and why it is not applied at load
--
-- knowledge.json / compat.native_suppression_state_is_the_target_change_freeze:
-- the target-change freeze is not caused by *what* this adapter does to the
-- stock frames, but by *when*. Measured in game, identical recipe and identical
-- ~1275 objects, tab-spamming under the same conditions:
--
--   applied live, ~30s after login : 7.04ms/frame (142fps), mean target-change
--                                    peak 7.8ms, worst 22.6ms
--   applied at OnEnable, at load   : 10.54ms/frame (95fps), mean peak 132.9ms,
--                                    worst 224.9ms -- a 17x worse peak, felt in
--                                    game as a hard freeze down to ~8fps
--
-- Applying the full teardown while the client is still bringing its own UI up
-- leaves something in a state it never recovers from for the rest of the
-- session. The exact native mechanism is NOT established -- no probe can see
-- inside the client's own frame setup -- so this is a measured behaviour with
-- an unproven cause, and the fix is scheduling rather than a changed recipe.
--
-- Two synchronous things were still in the load path after the first attempt,
-- and halving the cost (133ms -> 78ms mean peak) rather than removing it is
-- what showed they mattered: an immediate whole-list Hide() pass, and -- much
-- larger -- a
-- SYNCHRONOUS sweep of every registered name inside U.SuppressNativeFrame, i.e.
-- roughly 1275 objects mutated in a single frame while the client was still
-- starting up. Neither survives now:
--
--   * nothing is applied synchronously at registration at all; at load level 0
--     the bounded 0.05s batch also remains inert until settle;
--   * the batch starts at LOAD_LEVEL and is only allowed past it once the
--     client has actually settled, measured rather than guessed -- a minimum
--     delay AND a run of frames short enough to mean the client is no longer
--     hitching, with a hard cap so it always applies eventually.
--
-- LOAD_LEVEL 1 was tried as a compromise after repeated login crashes were
-- reported with the native UI visible. It removed the crash in one login but
-- USER_CONFIRMED_INGAME brought the target-change freeze back. The same build
-- also removed a recursive UIParent error-dialog scanner that ran throughout
-- the unstable login window, so that scanner -- not level 0 -- remains a viable
-- explanation for the crashes. Keep the only freeze-free configuration here
-- while leaving the failed scanner removed.
-- ---------------------------------------------------------------------------
local LOAD_LEVEL = 0          -- no native-frame mutation until client settle
local SETTLE_MIN_SECONDS = 3  -- never upgrade before this
local SETTLE_MAX_SECONDS = 20 -- ...and never wait longer than this
local SETTLE_QUIET_FRAMES = 90
local SETTLE_QUIET_MS = 20    -- a frame longer than this means "still busy"
local settled = false

-- 0..4; see core/config.lua's suppressLevel. Read once per call rather than
-- cached, so /uui suppress takes effect on the next sweep without a reload for
-- the levels that can be lowered live.
local function SuppressLevel()
  if U.db and U.db.noSuppress then return 0 end
  local level = U.db and tonumber(U.db.suppressLevel)
  if not level then level = 4 end
  if level < 0 then level = 0 end
  if level > 4 then level = 4 end
  -- Before the client has settled, cap the recipe rather than skip it.
  if not settled and level > LOAD_LEVEL then return LOAD_LEVEL end
  return level
end

-- Set for the duration of one deliberate re-apply. The steady-state fast path
-- below skips any object already confirmed hidden, which is right in normal
-- operation but wrong when the recipe itself has just changed: an object hidden
-- at level 1 would never receive level 2's SetAlpha(0).
local forceFullApply = false

local function KillNativeObject(object, visualOnly, visualKind)
  if not object then return end

  local level = SuppressLevel()
  if level <= 0 then return end

  statVisited = statVisited + 1

  local alreadyMarked = suppressedObjects[object] and true or false
  if forceFullApply then alreadyMarked = false end

  -- The target family keeps its native lifecycle intact: it is never hidden,
  -- its Show is left alone, and only its visible content is cleared. Replacing
  -- Show() and repeatedly hiding this family was the difference between the
  -- reproducible 1-fps collapse and a user-confirmed stable run; the native
  -- mechanism behind that difference remains opaque to Lua. (Event stripping
  -- was the third part of that original finding and is now gone from every
  -- path, visual-only or not -- see KillNativeObject's note below.)
  -- Alpha is applied to every named child because this client does not
  -- propagate parent alpha. Mouse input is dropped once, but the widget stays
  -- shown and subscribed so native code can recycle it normally. Some native
  -- StatusBar/FontString/Texture renderers ignore UIObject alpha, so their
  -- content is cleared once per target-change epoch without touching lifecycle.
  if visualOnly then
    local contentCurrent = (not visualKind or
                            visualObjectEpoch[object] == targetVisualEpoch)
    if alreadyMarked then
      alphaKnown, alphaAnswer = false, nil
      pcall(ReadAlpha, object)
      if alphaKnown and alphaAnswer == 0 and contentCurrent then return end
    end

    statTornDown = statTornDown + 1
    suppressedObjects[object] = true
    pcall(ZeroAlpha, object)
    if not alreadyMarked then pcall(DropMouse, object) end
    if visualKind == "bar" then
      pcall(ClearBarVisual, object)
    elseif visualKind == "texture" then
      pcall(ClearTextureVisual, object)
    elseif visualKind == "text" then
      pcall(ClearTextVisual, object)
    end
    if visualKind then visualObjectEpoch[object] = targetVisualEpoch end
    return
  end

  -- Steady-state fast path: once an object is marked, the common case on every
  -- later pass is that it is still exactly where this adapter left it. A
  -- single IsShown readback confirms that and skips the rest of the teardown;
  -- the full pcall sequence only runs again for an object the client actually
  -- brought back, which is the one case this adapter exists to catch.
  if alreadyMarked then
    shownKnown, shownAnswer = false, false
    pcall(ReadShown, object)
    if shownKnown and not shownAnswer then return end
  end

  statTornDown = statTornDown + 1

  -- No UnregisterAllEvents here, at any level. See
  -- knowledge.json / compat.unregisterallevents_native_frame_stall: stripping a
  -- live native frame's event registrations is what the party-only freeze
  -- actually was, and it is measured rather than reasoned. Two runs by the same
  -- reporter, same party, same zone, ~175s each, vsync-locked at 60fps:
  --
  --   level 4 (this call present) : 22.8s of stall above the 60fps floor
  --                                 (12.9% of wall time), worst frame >=1000ms,
  --                                 worst target-change frame 489ms
  --   level 3 (this call absent)  : 6.5s of stall (3.7%), worst frame 52.8ms
  --                                 (and that one is the post-reload settle),
  --                                 worst target-change frame 19.3ms
  --
  -- The decisive part is that the teardown *volume* barely moved between them:
  -- 10485 -> 9157 objects, -11%, while the stall fell 72%. Everything else in
  -- this recipe -- Hide, SetAlpha(0), EnableMouse(false), the Show neutraliser
  -- -- ran at nearly the same rate in the good run. So the cost is not how many
  -- objects are visited, it is this one call: ~59/s at roughly 1.5-4ms each.
  --
  -- It is also not needed. The level 3 run covered ~3 minutes of active play,
  -- 40 target changes and 215 PARTY_MEMBERS_CHANGED, and the reporter confirmed
  -- no stock frame ever became visible. NeutraliseShow below already stops a
  -- Lua-driven re-show, and the bounded periodic batch re-hides anything that
  -- slips past within about a second.
  --
  -- Deliberately deleted rather than moved inside the `alreadyMarked` guard
  -- below: once-per-object still means ~400-500 of these inside the load batch
  -- at several ms each, which trades a steady drip for a burst of ~90ms hitches
  -- right after login. The operation has no home in this recipe.

  -- Wrapping an already-replaced Show would nest the no-op inside itself on
  -- every re-apply pass, so the swap happens once and is then remembered.
  -- One shared no-op serves every object: nothing compares these by identity.
  if not alreadyMarked then
    if level >= 3 then pcall(NeutraliseShow, object) end
    suppressedObjects[object] = true
  end

  pcall(HideObject, object)
  if level >= 2 then pcall(ZeroAlpha, object) end
  if level >= 3 then pcall(DropMouse, object) end
end

local function SweepNames(names)
  if not names then return end
  local i
  for i = 1, table.getn(names) do
    local name = names[i]
    KillNativeObject(ResolveNativeObject(name), visualOnlyNames[name],
                     visualOnlyKinds[name])
  end
end

local function SweepNameRange(names, first, last)
  if not names then return end
  local count = table.getn(names)
  if last > count then last = count end
  local i
  for i = first, last do
    local name = names[i]
    KillNativeObject(ResolveNativeObject(name), visualOnlyNames[name],
                     visualOnlyKinds[name])
  end
end

local function ApplyNativeSuppression()
  SweepNames(suppressedNames)
end

-- The periodic guarantee used to inspect the complete ~1150-name list inside
-- one updater callback. Even its hidden-object fast path needs an IsShown
-- pcall per resolved object, so that retained a large once-per-second burst
-- after the
-- earlier suppression fixes. Walk one bounded slice per tick instead: at 60
-- names every 0.05s the complete list is still covered about once per second,
-- but no render tick inherits the whole scan.
local function ApplyNativeSuppressionBatch()
  if U.PerfDisabled and U.PerfDisabled("sweep") then return end
  if SuppressLevel() <= 0 then return end

  -- PLAYER_TARGET_CHANGED can precede the native level renderer's final write.
  -- One deferred sweep was therefore early enough for the yellow number to
  -- return. Clear just that FontString across a bounded 0.6s window (at the
  -- normal 0.05s cadence), without Hide, event removal, or Show replacement.
  if targetLevelRetryPasses > 0 then
    local levelText = ResolveNativeObject("TargetLevelText")
    if levelText then
      pcall(ZeroAlpha, levelText)
      pcall(ClearTextVisual, levelText)
    end
    targetLevelRetryPasses = targetLevelRetryPasses - 1
  end

  local count = table.getn(suppressedNames)
  if count == 0 then return end

  local limit = SUPPRESSION_BATCH_SIZE
  if count < limit then limit = count end

  local processed = 0
  while processed < limit do
    if suppressionCursor > count then suppressionCursor = 1 end
    local name = suppressedNames[suppressionCursor]
    KillNativeObject(ResolveNativeObject(name), visualOnlyNames[name],
                     visualOnlyKinds[name])
    suppressionCursor = suppressionCursor + 1
    processed = processed + 1
  end
end

-- Returns a handler that sweeps one group only. An event that cannot bring a
-- family of frames back has no reason to walk it; the bounded periodic scan
-- above stays the guarantee for everything, so the worst case for a name in
-- the wrong group is that it is re-hidden after the next complete scan.
local function GroupSweeper(group)
  return function()
    if U.PerfDisabled and U.PerfDisabled("sweep") then return end
    if SuppressLevel() < 4 then return end
    SweepNames(suppressedGroups[group])
  end
end

-- Builds the global names of a stock frame and the children this client draws
-- on its own. Callers pass the names they have actually seen in this client's
-- global table; nothing is inferred from what Vanilla FrameXML would define.
--
-- root    "TargetFrame"
-- parts   { "HealthBar", "Name" }        -> TargetFrameHealthBar, ...
-- series  { { "Buff", 5 } }              -> TargetFrameBuff1..5 plus the
--                                          Icon/Border/Count region of each
function U.NativeFrameParts(root, parts, series)
  local names = { root }
  local i, j

  for i = 1, table.getn(parts or {}) do
    table.insert(names, root .. parts[i])
  end

  for i = 1, table.getn(series or {}) do
    local suffix, count = series[i][1], series[i][2]
    for j = 1, count do
      local base = root .. suffix .. j
      table.insert(names, base)
      table.insert(names, base .. "Icon")
      table.insert(names, base .. "Border")
      table.insert(names, base .. "Count")
    end
  end

  return names
end

-- names may be a single global name or an array of them. A name that does not
-- resolve is simply skipped on every pass, so an absent stock frame costs
-- nothing and never errors.
--
-- group names which event-driven re-apply this family belongs to: "target" for
-- frames this client re-shows when the target changes, "party" for the roster
-- frames, and the default "static" for everything the periodic sweep alone can
-- cover. Passing nothing is always safe -- it only means the frame waits for
-- the bounded periodic scan rather than being re-hidden when an event fires.
function U.SuppressNativeFrame(names, group)
  -- Note the level is NOT checked here. The name lists are always built, even
  -- at level 0 where nothing is applied: KillNativeObject is what honours the
  -- level, and registering regardless is what makes /uui perf levels possible --
  -- raising the level mid-session has to have a list to sweep.
  if type(names) == "string" then names = { names } end
  if type(names) ~= "table" then return end

  if type(group) ~= "string" then group = "static" end
  if not suppressedGroups[group] then suppressedGroups[group] = {} end
  local bucket = suppressedGroups[group]
  local firstNew = table.getn(bucket) + 1

  local i
  for i = 1, table.getn(names) do
    local name = names[i]
    if group == "target" and type(name) == "string" then
      visualOnlyNames[name] = true
      if string.find(name, "HealthBar$") or
         string.find(name, "ManaBar$") then
        visualOnlyKinds[name] = "bar"
      -- "Text$" covers this client's TargetLevelText, and subsumes the
      -- HealthBarText/ManaBarText/DeadText suffixes kept below for clarity.
      -- Without it TargetLevelText would be registered visual-only with no
      -- kind, so it would only get SetAlpha(0) -- which this client's
      -- FontString renderer ignores, the reason ClearTextVisual exists.
      elseif string.find(name, "Text$") or
             string.find(name, "HealthBarText$") or
             string.find(name, "ManaBarText$") or
             string.find(name, "Name$") or
             string.find(name, "Level$") or
             string.find(name, "Count$") then
        visualOnlyKinds[name] = "text"
      elseif string.find(name, "Texture$") or
             string.find(name, "Background$") or
             string.find(name, "Portrait$") or
             string.find(name, "Icon$") or
             string.find(name, "Border$") then
        visualOnlyKinds[name] = "texture"
      end
    end
    if type(name) == "string" and not suppressedSeen[name] then
      suppressedSeen[name] = true
      table.insert(suppressedNames, name)
      table.insert(bucket, name)
    end
  end

  -- Deliberately no sweep here. This used to call
  -- SweepNameRange(bucket, firstNew, ...) so a module's frames were suppressed
  -- the instant it registered them; across every module that is ~1275 objects
  -- mutated during load, which is half the measured freeze. The bounded batch
  -- picks them up within about a second instead.

  if not suppressionArmed then
    suppressionArmed = true

    -- PLAYER_TARGET_CHANGED is the one of these observed firing on this client
    -- (events.json, 7 captures); the others are registered but unobserved, so
    -- the bounded periodic scan is the actual guarantee rather than a backstop.
    --
    -- Because it is the one that fires, it is also the one whose cost is felt:
    -- it gets the "target" bucket only, not the whole list. Once settled,
    -- PLAYER_ENTERING_WORLD keeps the full sweep -- it is rare, and a zone-in
    -- is when the client is most likely to have rebuilt anything.
    U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
      -- At load level 1 the bounded batch is deliberately the only start-up
      -- writer. A full event sweep here would put all ~1275 Hide() calls back
      -- into one frame and defeat the progressive start-up path.
      if not settled then return end
      ApplyNativeSuppression()
    end)

    -- round 3: this used to run GroupSweeper("target") inline, in the same
    -- frame PLAYER_TARGET_CHANGED fires in. That is also the frame this
    -- client re-shows TargetFrame in -- the whole reason the sweep exists --
    -- so the ~122 objects that fail the IsShown fast path and take the full
    -- ~5-pcall teardown were doing it stacked on top of whatever native work
    -- the client's own target-acquisition path does in that same frame.
    -- U.DeferOnce moves the sweep one driver tick later instead, so the two
    -- no longer compete for the same frame; a second target change before the
    -- deferred sweep runs replaces the pending one rather than queuing both,
    -- which is the right outcome for the fast-tabbing case.
    local targetSweep = GroupSweeper("target")
    U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
      targetVisualEpoch = targetVisualEpoch + 1
      targetLevelRetryPasses = TARGET_LEVEL_RETRY_PASSES
      U.DeferOnce("compat.target-sweep", function()
        -- Bracket the sweep so the counters below describe one target-change
        -- sweep specifically, separated from the 0.05s periodic batch that is
        -- also incrementing the same totals.
        local visited, torn = statVisited, statTornDown
        targetSweep()
        lastTargetVisited = statVisited - visited
        lastTargetTornDown = statTornDown - torn
      end)
    end)
    -- Deferred and coalesced for the same reason the target sweep above is,
    -- and more urgently: PARTY_MEMBERS_CHANGED is by far the noisiest event
    -- this client emits while grouped. Measured in the reporter's runs, 130
    -- and 215 occurrences in ~175s -- one every 0.8-1.4s, and 16x the rate of
    -- PLAYER_TARGET_CHANGED. Run inline that is a synchronous ~204-name sweep
    -- landing in the same frame the client does its own party-roster work in.
    --
    -- events.json still records this event as accepted-but-never-observed;
    -- that record is wrong and is corrected in knowledge.json /
    -- compat.party_members_changed_high_frequency.
    --
    -- U.DeferOnce replaces a pending sweep rather than queueing a second, so a
    -- burst of roster events collapses to one sweep on the next driver tick.
    local partySweep = GroupSweeper("party")
    U.RegisterEvent("PARTY_MEMBERS_CHANGED", function()
      U.DeferOnce("compat.party-sweep", partySweep)
    end)
    U.RegisterUpdate("compat.native-suppression", 0.05,
                     ApplyNativeSuppressionBatch)

    -- Waits for the client to actually be idle rather than for a guessed
    -- number of seconds. A fixed 2s delay measurably was not enough, and the
    -- cost fell off with how long we waited, so what matters is that start-up
    -- is genuinely over -- which the frame times themselves report.
    --
    -- Frame delta comes from GetTime, not from the updater's interval: the
    -- interval is what was asked for, not what the frame took, and
    -- knowledge.json / scripts.onupdate_elapsed_only_via_arg1 rules out reading
    -- it from the handler's arguments on this client.
    local settleStart, settleLast, quiet = nil, nil, 0

    U.RegisterUpdate("compat.suppression-settle", 0, function()
      local now
      local ok, value = pcall(GetTime)
      if ok and type(value) == "number" then now = value end
      if not now then
        -- No clock: fall back to upgrading immediately rather than never.
        quiet = SETTLE_QUIET_FRAMES
        settleStart = -SETTLE_MAX_SECONDS
        now = 0
      end

      if not settleStart then settleStart = now end
      local waited = now - settleStart

      if settleLast then
        local ms = (now - settleLast) * 1000
        if ms > 0 and ms < SETTLE_QUIET_MS then
          quiet = quiet + 1
        else
          quiet = 0
        end
      end
      settleLast = now

      local calm = (waited >= SETTLE_MIN_SECONDS and quiet >= SETTLE_QUIET_FRAMES)
      if not calm and waited < SETTLE_MAX_SECONDS then return end

      U.UnregisterUpdate("compat.suppression-settle")
      settled = true
      targetLevelRetryPasses = TARGET_LEVEL_RETRY_PASSES
      if type(U.ReapplyNativeSuppression) == "function" then
        U.ReapplyNativeSuppression()
      end
      U.Debug("native suppression settled after " ..
              string.format("%.1f", waited) .. "s (" .. tostring(quiet) ..
              " quiet frames), level " .. tostring(SuppressLevel()))
    end)
  end
end

-- Re-applies the whole registered list at the CURRENT level, ignoring the
-- steady-state fast path. Used by /uui perf levels, which raises the level in
-- place so the whole recipe can be bisected in one session instead of one
-- reload per step. Raising works live; lowering still needs a reload, because
-- what has been applied to a stock frame cannot be taken back.
function U.ReapplyNativeSuppression()
  forceFullApply = true
  local ok = pcall(ApplyNativeSuppression)
  forceFullApply = false
  return ok
end

function U.SuppressedFrameCount()
  return table.getn(suppressedNames)
end

-- Read by core/perf.lua's export. visited/tornDown are session totals across
-- every sweep; lastTarget* describe only the most recent target-change sweep,
-- which is the one the micro freeze is being attributed to.
--
-- tornDown vs visited is the whole question: if lastTargetTornDown is close to
-- lastTargetVisited then this client really does re-show TargetFrame's entire
-- region tree on every target change and the adapter is paying ~4 native widget
-- mutations for each one, synchronously. If it is near zero, the sweep is not
-- the cost and the search moves elsewhere.
function U.SuppressionStats()
  return {
    visited = statVisited,
    tornDown = statTornDown,
    lastTargetVisited = lastTargetVisited,
    lastTargetTornDown = lastTargetTornDown,
    registeredNames = table.getn(suppressedNames),
    targetGroupNames = table.getn(suppressedGroups["target"] or {}),
  }
end

-- ---------------------------------------------------------------------------
-- Runtime self-check
--
-- Reports what this client actually did, so /uui debug produces measured
-- evidence instead of restating assumptions. Everything here is read-only
-- except for one throwaway hidden frame.
-- ---------------------------------------------------------------------------
function U.RunSelfCheck()
  local report = {}

  report.version = U.version
  report.handlerShape = U.handlerShape
  report.ticks = U.ticks

  local font = U.ResolveFont()
  report.font = font or "none (inherited fonts kept)"

  report.uiWidth = U.UIWidth()
  report.uiHeight = U.UIHeight()
  local ok, screenW = pcall(GetScreenWidth)
  report.screenWidth = (ok and screenW) or "?"
  report.pixelScale = U.PixelScale()

  -- Anchor round-trip: request a known point, then confirm the normalised
  -- reader hands back the values SetPoint was given.
  local probe = CreateFrame("Frame", nil, UIParent)
  probe:Hide()
  probe:SetWidth(50)
  probe:SetHeight(20)

  local requestX, requestY = -75, 25
  local set = pcall(function()
    probe:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", requestX, requestY)
  end)

  if set then
    local rawOk, _, rawRel, _, rawX, rawY = pcall(probe.GetPoint, probe, 1)
    if rawOk then
      report.rawRelativeType = type(rawRel)
      report.rawX = rawX
      report.rawY = rawY
    end

    local _, _, _, normX, normY = U.GetFramePoint(probe, 1)
    report.normX = normX
    report.normY = normY
    report.anchorRoundTrip = (normX == requestX and normY == requestY)
  else
    report.anchorRoundTrip = false
  end

  return report
end
