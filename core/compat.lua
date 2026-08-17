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

-- Applies a verified font path at the requested size. When no path resizes,
-- the fontstring keeps whatever it inherited rather than being handed a request
-- the client will silently ignore.
--
-- Note the same probe recorded OUTLINE reading back as NONE, so outline flags
-- are requested but not treated as guaranteed.
function U.SetFont(fontstring, size, flags)
  if not fontstring or not fontstring.SetFont then return false end

  local path = U.ResolveFont()
  if not path then return false end

  size = tonumber(size) or M.fontSize.normal
  return pcall(fontstring.SetFont, fontstring, path, size, flags or "OUTLINE")
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
function U.SetColor(texture, r, g, b, a)
  if not texture or not texture.SetVertexColor then return false end

  r = tonumber(r) or 0
  g = tonumber(g) or 0
  b = tonumber(b) or 0
  a = tonumber(a) or 1

  local ok = pcall(texture.SetVertexColor, texture, r, g, b, a)
  if ok then
    -- Frames on this client behave as tables, but texture regions are not
    -- guaranteed to accept an arbitrary field, so the cache write is optional.
    pcall(function() texture.uuiColor = { r, g, b, a } end)
  end
  return ok
end

function U.GetColor(texture)
  if not texture then return nil end
  local ok, cached = pcall(function() return texture.uuiColor end)
  if not ok or type(cached) ~= "table" then return nil end
  return cached[1], cached[2], cached[3], cached[4]
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
-- Show() is replaced only on frames a module explicitly names, and only once
-- per object. Nothing here installs a global or removes a client function
-- unrealUI was not asked to suppress.
-- ---------------------------------------------------------------------------
local suppressedSeen = {}
local suppressedNames = {}
local suppressionArmed = false

-- knowledge.json / compat.native_suppression_pcall_burst_stutter: this sweep
-- used to resolve every name through U.G (its own pcall) and then run the full
-- ~5-pcall teardown on every object, every second, unconditionally. With unit
-- frames registering around 330 names (TargetFrame's buff/debuff series alone
-- is over 300 sub-region names), that was a synchronous burst of roughly 2000
-- pcalls once a second -- reported in game as periodic stuttering that started
-- with the unit frame feature. Two independent fixes below remove it:
-- memoizing the name -> object resolution, and skipping the teardown entirely
-- once an object is confirmed already hidden.
local resolvedNative = {}   -- name -> object | false

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

local function IsAlreadySuppressed(object)
  local ok, value = pcall(function() return object.uuiSuppressed end)
  return ok and value and true or false
end

local function KillNativeObject(object)
  if not object then return end

  local alreadyMarked = IsAlreadySuppressed(object)

  -- Steady-state fast path: once an object is marked, the common case on every
  -- later pass is that it is still exactly where this adapter left it. A
  -- single IsShown readback confirms that and skips the rest of the teardown;
  -- the full pcall sequence only runs again for an object the client actually
  -- brought back, which is the one case this adapter exists to catch.
  if alreadyMarked then
    local shownOk, shown = pcall(object.IsShown, object)
    if shownOk and not shown then return end
  end

  pcall(function()
    if object.UnregisterAllEvents then object:UnregisterAllEvents() end
  end)

  -- Wrapping an already-replaced Show would nest the no-op inside itself on
  -- every re-apply pass, so the swap happens once and is then remembered.
  if not alreadyMarked then
    pcall(function()
      if object.Show then object.Show = function() return end end
    end)
    pcall(function() object.uuiSuppressed = true end)
  end

  pcall(function() if object.Hide then object:Hide() end end)
  pcall(function() if object.SetAlpha then object:SetAlpha(0) end end)
  pcall(function() if object.EnableMouse then object:EnableMouse(false) end end)
end

local function ApplyNativeSuppression()
  local i
  for i = 1, table.getn(suppressedNames) do
    KillNativeObject(ResolveNativeObject(suppressedNames[i]))
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
function U.SuppressNativeFrame(names)
  if type(names) == "string" then names = { names } end
  if type(names) ~= "table" then return end

  local i
  for i = 1, table.getn(names) do
    local name = names[i]
    if type(name) == "string" and not suppressedSeen[name] then
      suppressedSeen[name] = true
      table.insert(suppressedNames, name)
    end
  end

  ApplyNativeSuppression()

  if not suppressionArmed then
    suppressionArmed = true

    -- PLAYER_TARGET_CHANGED is the one of these observed firing on this client
    -- (events.json, 7 captures); the others are registered but unobserved, so
    -- the one-second sweep is the actual guarantee rather than a backstop.
    U.RegisterEvent("PLAYER_ENTERING_WORLD", ApplyNativeSuppression)
    U.RegisterEvent("PLAYER_TARGET_CHANGED", ApplyNativeSuppression)
    U.RegisterEvent("PARTY_MEMBERS_CHANGED", ApplyNativeSuppression)
    U.RegisterUpdate("compat.native-suppression", 1, ApplyNativeSuppression)
  end
end

function U.SuppressedFrameCount()
  return table.getn(suppressedNames)
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
