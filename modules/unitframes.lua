-- unrealUI :: modules/unitframes.lua
--
-- Player, target and party unit frames use three stacked bars: a large health
-- bar, a thinner power bar directly under it, and a third strip underneath
-- showing text values (name, health, power). Target-of-target is deliberately
-- simpler: one health bar with its name centred on top. No
-- portrait -- removed by request; the earlier 2D fallback worked, this is a
-- design choice, not a compatibility failure.
--
-- None of pfUI's unitframe architecture is reproduced: there is no config
-- schema, no module framework, no aura/indicator/glow/click-cast machinery,
-- and no raid support. Auras and pet frames are separate scope. The player
-- castbar lives in modules/castbar.lua.
--
-- Compatibility notes that shaped this file:
--
--   * knowledge.json / unitframes.core_unit_api_contract_partial is
--     INCONCLUSIVE: UNIT_HEALTH, UNIT_MANA and PLAYER_TARGET_CHANGED are
--     observed, but no unit API return contract is verified in the compact DB.
--     query_compat.py has no record at all for UnitHealth's return shape,
--     TargetUnit or GameTooltip:SetUnit, so per the evidence-gap rule these
--     follow UnrealPfUI's demonstrated call shapes -- WORKING_SOURCE evidence,
--     not runtime verification. Every call is still resolved and pcall'd, and
--     every value is coerced, so an unexpected return shape degrades the frame
--     instead of erroring.
--   * events.json: PARTY_MEMBERS_CHANGED was accepted but never observed, and
--     nothing at all reports target-of-target. Both are therefore driven by the
--     shared polling tick, with events as an accelerator rather than the
--     mechanism.
--   * knowledge.json / scripts.child_onupdate_unreliable: no frame built here
--     owns an OnUpdate. Everything refreshes on U.RegisterUpdate.
--   * knowledge.json / fonts.stretched_justification_ignored: bar labels are
--     anchored to the single edge they belong to, never stretched corner to
--     corner with SetJustifyH.
--   * knowledge.json / core.getdifficultycolor_missing: GetDifficultyColor is
--     absent on this client, so level colouring uses a local helper. No global
--     is installed.
--   * knowledge.json / compat.native_suppression_pcall_burst_stutter: the
--     shared suppression sweep this module drives through
--     U.SuppressNativeFrame used to cost a synchronous ~2000-pcall burst once a
--     second; the fix lives in core/compat.lua, not here, but the frame lists
--     below are what made the burst that large in the first place.

local U = UnrealUI
local M = U.media

local UF = U.RegisterModule("unitframes")

-- ---------------------------------------------------------------------------
-- Unit API access
--
-- Nothing in the compact DB pins down what these return on this client, so each
-- call is resolved by name, pcall'd, and coerced. A missing function or an
-- unexpected return is nil here rather than an error six frames deep.
--
-- The name -> function lookup is memoized: these are stock globals that do not
-- change identity mid-session, and resolving one used to cost its own pcall
-- (through U.G) on top of the pcall around the actual call. Caching removes
-- that repeated half of the cost -- see compat.native_suppression_pcall_burst
-- _stutter in core/compat.lua for the sibling fix on the suppression sweep.
-- ---------------------------------------------------------------------------
local apiFnCache = {}

local function ResolveApiFn(name)
  local cached = apiFnCache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local fn = U.G(name)
  if type(fn) == "function" then
    apiFnCache[name] = fn
    return fn
  end
  apiFnCache[name] = false
  return nil
end

local function ApiNumber(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, value = pcall(fn, a, b)
  if not ok then return nil end
  return tonumber(value)
end

local function ApiString(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, value = pcall(fn, a, b)
  if not ok or type(value) ~= "string" then return nil end
  return value
end

-- Vanilla's boolean-ish APIs return 1 or nil, but that is not guaranteed here,
-- so anything other than nil/false/0/"" counts as true.
local function ApiTruth(name, a, b)
  local fn = ResolveApiFn(name)
  if not fn then return false end
  local ok, value = pcall(fn, a, b)
  if not ok then return false end
  if value == nil or value == false or value == 0 or value == "" then
    return false
  end
  return true
end

-- UnitClass's useful half is its second return, the unlocalised token.
local function UnitClassToken(unit)
  local fn = ResolveApiFn("UnitClass")
  if not fn then return nil end
  local ok, _, token = pcall(fn, unit)
  if not ok or type(token) ~= "string" then return nil end
  return token
end

-- ---------------------------------------------------------------------------
-- Layout
--
-- Each frame is three stacked, individually bordered boxes: health (large),
-- power (thin), and a text-only "values" strip. width is the bar width shared
-- by all three; height is set per box, valuesHeight for the strip.
--
-- Default anchors are UIParent-relative, which is what the mover position
-- store requires. A frame with anchorTo instead rides another frame's mover:
-- target-of-target follows the target frame, and party members follow the
-- party anchor, so none of them can drift out of alignment with what they are
-- attached to.
-- ---------------------------------------------------------------------------
-- Target-of-target shares PRIMARY_WIDTH with target rather than carrying its
-- own literal, so the two can never drift apart again.
local PRIMARY_WIDTH = 180

local SPECS = {
  {
    -- health raised from 26 to 34 (+30%) by request.
    id = "player", unit = "player", name = "Player", label = "Player",
    width = PRIMARY_WIDTH, health = 34, power = 10, valuesHeight = 14, gap = 0,
    values = { left = "unit", center = "healthdyn", right = "powerdyn" },
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOM", x = -75, y = 125 },
  },
  {
    id = "target", unit = "target", name = "Target", label = "Target",
    width = PRIMARY_WIDTH, health = 34, power = 10, valuesHeight = 14, gap = 0,
    values = { left = "unit", center = "healthdyn", right = "powerdyn" },
    default = { point = "BOTTOMLEFT", relativePoint = "BOTTOM", x = 75, y = 125 },
  },
  {
    -- width matches target's, by request -- see PRIMARY_WIDTH above.
    id = "targettarget", unit = "targettarget", name = "TargetTarget",
    label = "Target of target",
    -- One health bar only: its fixed-colour name is centred above the fill,
    -- on a raised child layer within the target-of-target frame.
    -- 18px is half the previous 35px height, rounded to an integer pixel.
    width = PRIMARY_WIDTH, health = 18, healthText = "nameplain", gap = 0,
    anchorTo = "target",
    anchorPoint = "TOP", anchorRelativePoint = "BOTTOM",
    anchorOffsetX = 0, anchorOffsetY = 1,
  },
}

local PARTY_COUNT = 4
local PARTY_SPACING = 75

-- The party frames are laid out inside one anchor frame and moved as a block:
-- a party is a single unit of layout, and dragging four frames into alignment
-- by hand is exactly what the grid exists to avoid. Only the anchor gets a
-- mover; the members keep fixed offsets inside it.
local PARTY_ANCHOR = "party"

do
  local i
  for i = 1, PARTY_COUNT do
    table.insert(SPECS, {
      id = "party" .. i,
      unit = "party" .. i,
      name = "Party" .. i,
      label = "Party " .. i,
      width = 164, health = 18, power = 8, valuesHeight = 12, gap = 0,
      values = { left = "unit", right = "healthdyn" },
      anchorTo = PARTY_ANCHOR,
      anchorPoint = "TOPLEFT", anchorRelativePoint = "TOPLEFT",
      anchorOffsetX = 0, anchorOffsetY = -((i - 1) * PARTY_SPACING),
    })
  end
end

-- Stock frames this module replaces. The name lists are the ones UnrealPfUI
-- suppresses, which were built from the names actually present in this client's
-- global table rather than from Vanilla FrameXML.
local function SuppressStockFrames()
  U.SuppressNativeFrame(U.NativeFrameParts("PlayerFrame",
    { "Texture", "Background", "HealthBar", "HealthBarText", "ManaBar",
      "ManaBarText", "GroupIndicator", "GroupIndicatorLeft",
      "GroupIndicatorMiddle", "GroupIndicatorRight", "GroupIndicatorText" }))
  U.SuppressNativeFrame("PlayerPortrait")

  U.SuppressNativeFrame(U.NativeFrameParts("TargetFrame",
    { "Texture", "TextureFrame", "Background", "NameBackground", "HealthBar",
      "HealthBarText", "ManaBar", "ManaBarText", "Name", "Level", "Portrait" },
    { { "Buff", 5 }, { "Debuff", 16 } }))
  U.SuppressNativeFrame("TargetPortrait")

  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTarget",
    { "Frame", "Texture", "TextureFrame", "Background", "HealthBar",
      "ManaBar", "Portrait", "Name", "DeadText" }))
  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTargetFrame",
    {}, { { "Debuff", 4 } }))

  local i
  for i = 1, PARTY_COUNT do
    local root = "PartyMemberFrame" .. i
    U.SuppressNativeFrame(U.NativeFrameParts(root,
      { "Texture", "Background", "HealthBar", "HealthBarText", "ManaBar",
        "ManaBarText", "Portrait", "Name", "Status", "Disconnect",
        "LeaderIcon", "MasterIcon", "PVPIcon",
        "PetFrame", "PetFrameTexture", "PetFrameHealthBar",
        "PetFramePortrait", "PetFrameName" },
      { { "Debuff", 4 } }))
    U.SuppressNativeFrame(U.NativeFrameParts(root .. "PetFrame",
      {}, { { "Debuff", 4 } }))
  end
end

-- ---------------------------------------------------------------------------
-- Colours and formatting
-- ---------------------------------------------------------------------------
local function Clamp(value)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function Hex(r, g, b)
  return string.format("|cff%02x%02x%02x",
    math.floor(Clamp(tonumber(r) or 1) * 255 + 0.5),
    math.floor(Clamp(tonumber(g) or 1) * 255 + 0.5),
    math.floor(Clamp(tonumber(b) or 1) * 255 + 0.5))
end

-- pfUI's health gradient: red at empty, yellow at half, green at full.
local function Gradient(perc)
  perc = Clamp(tonumber(perc) or 0)

  local r1, g1, b1, r2, g2, b2
  if perc <= 0.5 then
    perc = perc * 2
    r1, g1, b1 = 1, 0, 0
    r2, g2, b2 = 1, 1, 0
  else
    perc = perc * 2 - 1
    r1, g1, b1 = 1, 1, 0
    r2, g2, b2 = 0, 1, 0
  end

  return r1 + (r2 - r1) * perc,
         g1 + (g2 - g1) * perc,
         b1 + (b2 - b1) * perc
end

-- pfUI modern runs with pastel enabled, which lifts every derived colour toward
-- white. Bars and text use different strengths upstream, so both are kept.
local function PastelBar(r, g, b)
  return (r + 0.5) * 0.5, (g + 0.5) * 0.5, (b + 0.5) * 0.5
end

local function PastelText(r, g, b)
  return (r + 0.75) * 0.5, (g + 0.75) * 0.5, (b + 0.75) * 0.5
end

-- knowledge.json / core.getdifficultycolor_missing: this client has no
-- GetDifficultyColor. The thresholds are the Vanilla ones; the helper stays
-- local because unrealUI does not install shim globals.
local function DifficultyColor(level)
  level = tonumber(level) or 0
  local playerLevel = ApiNumber("UnitLevel", "player") or 1

  if level <= 0 then return 0.69, 0.69, 0.69 end
  if level >= playerLevel + 5 then return 1, 0.1, 0.1 end
  if level >= playerLevel + 3 then return 1, 0.5, 0.1 end
  if level >= playerLevel - 2 then return 1, 1, 0 end
  if level > playerLevel - 8 then return 0.25, 0.75, 0.25 end
  return 0.5, 0.5, 0.5
end

local function Abbreviate(value)
  value = tonumber(value) or 0
  local absolute = math.abs(value)

  if absolute > 1000000 then
    return string.format("%.2f", value / 1000000) .. "m"
  elseif absolute > 1000 then
    return string.format("%.1f", value / 1000) .. "k"
  end

  return tostring(U.Round(value))
end

-- ---------------------------------------------------------------------------
-- Unit state
--
-- One reusable table per frame; refreshing runs five times a second and should
-- not allocate.
-- ---------------------------------------------------------------------------
local function ReadUnit(frame)
  local unit = frame.unit
  local data = frame.data

  data.name = ApiString("UnitName", unit)
  data.level = ApiNumber("UnitLevel", unit)
  data.classification = ApiString("UnitClassification", unit)
  data.isPlayer = ApiTruth("UnitIsPlayer", unit)
  data.isDead = ApiTruth("UnitIsDead", unit) or ApiTruth("UnitIsGhost", unit)
  -- An absent UnitIsConnected must read as connected, not as everyone offline.
  if ResolveApiFn("UnitIsConnected") then
    data.connected = ApiTruth("UnitIsConnected", unit)
  else
    data.connected = true
  end
  data.class = UnitClassToken(unit)
  data.reaction = ApiNumber("UnitReaction", unit, "player")

  data.health = ApiNumber("UnitHealth", unit) or 0
  data.healthMax = ApiNumber("UnitHealthMax", unit) or 0
  data.power = ApiNumber("UnitMana", unit) or 0
  data.powerMax = ApiNumber("UnitManaMax", unit) or 0
  data.powerType = ApiNumber("UnitPowerType", unit)

  if data.healthMax > 0 then
    data.healthPercent = Clamp(data.health / data.healthMax)
  else
    data.healthPercent = 0
  end

  return data
end

-- The colour a unit's *name* is drawn in: class colour for players, reaction
-- colour for everything else.
local function UnitNameColor(data)
  local r, g, b

  if data.isPlayer and data.class then
    r, g, b = M.ClassColor(data.class)
  elseif data.reaction then
    r, g, b = M.ReactionColor(data.reaction)
  end

  if not r then return 1, 1, 1 end
  return r, g, b
end

local function LevelString(data)
  local level = data.level
  local text
  if not level or level < 0 then text = "??" else text = tostring(level) end

  local class = data.classification
  if class == "worldboss" then
    text = text .. "B"
  elseif class == "rareelite" then
    text = text .. "R+"
  elseif class == "elite" then
    text = text .. "+"
  elseif class == "rare" then
    text = text .. "R"
  end

  return text
end

-- Builds one of the pfUI text tokens this module supports. Only the tokens the
-- layouts above actually use are implemented; pfUI's full token list is config
-- surface unrealUI does not have.
local function StatusText(frame, token)
  local data = frame.data
  if not token or token == "none" then return "" end

  if token == "nameplain" then
    return data.name or U.G("UNKNOWN") or "Unknown"
  end

  if token == "unit" or token == "unitrev" or token == "name" then
    local name = data.name or U.G("UNKNOWN") or "Unknown"
    local nr, ng, nb = PastelText(UnitNameColor(data))
    local colored = Hex(nr, ng, nb) .. name

    if token == "name" then return colored end

    local lr, lg, lb = PastelText(DifficultyColor(data.level))
    local level = Hex(lr, lg, lb) .. LevelString(data)

    if token == "unitrev" then return colored .. "  " .. level end
    return level .. "  " .. colored
  end

  if token == "healthdyn" then
    local hr, hg, hb = PastelText(Gradient(data.healthPercent))
    local prefix = Hex(hr, hg, hb)

    if data.isDead then return prefix .. (U.G("DEAD") or "Dead") end
    if data.health ~= data.healthMax and data.healthMax > 0 then
      return prefix .. Abbreviate(data.health) .. " - " ..
             math.ceil(data.healthPercent * 100) .. "%"
    end
    return prefix .. Abbreviate(data.health)
  end

  if token == "powerdyn" then
    local pr, pg, pb = PastelText(M.Unpack(M.power[data.powerType] or M.power.fallback))
    local prefix = Hex(pr, pg, pb)

    -- Only mana is worth a percentage; rage and energy are already a 0-100
    -- scale, which is exactly what pfUI does here.
    if data.power ~= data.powerMax and data.powerType == 0 and data.powerMax > 0 then
      return prefix .. Abbreviate(data.power) .. " - " ..
             math.ceil(data.power / data.powerMax * 100) .. "%"
    end
    return prefix .. Abbreviate(data.power)
  end

  return ""
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
local frames = {}       -- id -> frame
local frameOrder = {}
local textCache = {}    -- fontstring -> last applied string

local function SetLabelText(label, value)
  if not label then return end
  value = value or ""
  if textCache[label] == value then return end
  textCache[label] = value
  pcall(label.SetText, label, value)
end

local function CreateBarBox(parent, width, height, border, color)
  local box = CreateFrame("Frame", nil, parent)
  box:SetWidth(width + 2 * border)
  box:SetHeight(height + 2 * border)
  U.CreateBackdrop(box)

  -- Explicit size plus a single corner anchor. The bar computes its fill from
  -- its own GetWidth (core/style.lua), so the width has to be a number the
  -- frame really has -- not one that depends on two-corner anchoring resizing
  -- the frame, which nothing in the compact DB establishes on this client.
  local bar = U.CreateStatusBar(box, {
    width = width,
    height = height,
    color = color or M.color.health,
  })
  bar:SetPoint("TOPLEFT", box, "TOPLEFT", border, -border)

  box.bar = bar
  return box
end

local function CreateBarLabel(parent, anchor, target, offset)
  local label = U.CreateLabel(parent, {
    size = M.fontSize.normal,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if not label then return nil end

  -- Single-edge anchor, per fonts.stretched_justification_ignored.
  label:SetPoint(anchor, target, anchor, offset, 0)
  return label
end

-- The third bar: no fill, no value, just a bordered strip carrying up to three
-- text slots. Built the same way as a bar box (backdrop + border) so it reads
-- as a matching third row rather than bare text floating under the power bar.
local function CreateValuesStrip(parent, width, height, border, tokens)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetWidth(width + 2 * border)
  strip:SetHeight(height + 2 * border)
  U.CreateBackdrop(strip)

  local inset = 2 * border
  if tokens.left then
    strip.left = CreateBarLabel(strip, "LEFT", strip, inset)
  end
  if tokens.center then
    strip.center = CreateBarLabel(strip, "CENTER", strip, 0)
  end
  if tokens.right then
    strip.right = CreateBarLabel(strip, "RIGHT", strip, -inset)
  end

  return strip
end

local function FrameHeight(spec)
  local border = U.BorderSize()
  local height = spec.health + 2 * border
  if spec.power then height = height + spec.gap + spec.power + 2 * border end
  if spec.valuesHeight then
    height = height + spec.gap + spec.valuesHeight + 2 * border
  end
  return height
end

local function FrameWidth(spec)
  return spec.width + 2 * U.BorderSize()
end

local function BuildFrame(spec, parent)
  local border = U.BorderSize()

  -- A Button, not a Frame: knowledge.json / frames.movable_drag_requires_button
  -- _handle records Button as the widget type this client reliably routes mouse
  -- input to, and the frame needs clicks anyway.
  local frame = CreateFrame("Button", "UnrealUIUnit" .. spec.name, parent or UIParent)
  frame:SetWidth(FrameWidth(spec))
  frame:SetHeight(FrameHeight(spec))
  frame.unit = spec.unit
  frame.spec = spec
  frame.data = {}

  -- Each bar starts on the colour it will normally carry, so a frame is never
  -- briefly drawn in another bar's colour before the first refresh.
  local health = CreateBarBox(frame, spec.width, spec.health, border,
                              M.color.healthFull)
  health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  if spec.healthText then
    -- The status fill is its own child frame. Put the name on a higher child
    -- layer so the changing fill can never cover it.
    health.textLayer = CreateFrame("Frame", nil, health)
    health.textLayer:SetAllPoints(health)
    local levelOk, level = pcall(health.GetFrameLevel, health)
    if levelOk and tonumber(level) then
      pcall(health.textLayer.SetFrameLevel, health.textLayer, level + 10)
    end
    health.label = CreateBarLabel(health.textLayer, "CENTER", health.textLayer, 0)
  end

  local previous = health
  local power = nil
  if spec.power then
    power = CreateBarBox(frame, spec.width, spec.power, border,
                         M.power.fallback)
    power:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spec.gap)
    previous = power
  end

  local values = nil
  if spec.valuesHeight then
    values = CreateValuesStrip(frame, spec.width, spec.valuesHeight,
                              border, spec.values or {})
    values:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spec.gap)
  end

  frame.health = health
  frame.power = power
  frame.values = values

  frame:Hide()
  return frame
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function SetBar(bar, value, maximum)
  if not bar then return end
  maximum = tonumber(maximum) or 0
  value = tonumber(value) or 0
  if maximum <= 0 then maximum, value = 1, 0 end

  pcall(bar.SetMinMaxValues, bar, 0, maximum)
  pcall(bar.SetValue, bar, value)
end

-- pfUI modern's health colouring: full health sits at the near-black custom
-- colour, and as health drops the bar fades into the pastel red/yellow/green
-- gradient. That is customfullhp + customfade + custom="2" + pastel combined.
local function ApplyHealthColor(frame)
  local perc = frame.data.healthPercent
  local cr, cg, cb = M.Unpack(M.color.healthFull)

  local r, g, b
  if perc >= 1 then
    r, g, b = cr, cg, cb
  else
    r, g, b = PastelBar(Gradient(perc))
    r = cr * perc + r * (1 - perc)
    g = cg * perc + g * (1 - perc)
    b = cb * perc + b * (1 - perc)
  end

  U.SetStatusBarColor(frame.health.bar, r, g, b, 1)
end

local function ApplyPowerColor(frame)
  if not frame.power then return end
  local color = M.power[frame.data.powerType] or M.power.fallback
  U.SetStatusBarColor(frame.power.bar, M.Unpack(color))
end

local function ApplyTexts(frame)
  if frame.health.label then
    SetLabelText(frame.health.label, StatusText(frame, frame.spec.healthText))
  end

  local tokens = frame.spec.values or {}
  local v = frame.values
  if not v then return end
  if v.left then SetLabelText(v.left, StatusText(frame, tokens.left)) end
  if v.center then SetLabelText(v.center, StatusText(frame, tokens.center)) end
  if v.right then SetLabelText(v.right, StatusText(frame, tokens.right)) end
end

local function ClearTexts(frame)
  SetLabelText(frame.health.label, "")

  local v = frame.values
  if not v then return end
  SetLabelText(v.left, "")
  SetLabelText(v.center, "")
  SetLabelText(v.right, "")
end

local function RefreshFrame(frame, force)
  local exists = ApiTruth("UnitExists", frame.unit)

  if not exists then
    -- An empty shell stays on screen while the UI is unlocked, otherwise a
    -- frame with no unit could never be dragged into place.
    if U.IsUnlocked() then
      frame:Show()
      SetBar(frame.health.bar, 0, 1)
      if frame.power then SetBar(frame.power.bar, 0, 1) end
      U.SetStatusBarColor(frame.health.bar, M.Unpack(M.color.healthFull))
      ClearTexts(frame)
    else
      frame:Hide()
    end
    return false
  end

  frame:Show()

  local data = ReadUnit(frame)
  SetBar(frame.health.bar, data.health, data.healthMax)
  if frame.power then SetBar(frame.power.bar, data.power, data.powerMax) end
  ApplyHealthColor(frame)
  ApplyPowerColor(frame)
  ApplyTexts(frame)

  -- Offline party members are dimmed rather than hidden, matching pfUI's
  -- alpha_offline treatment without importing its alpha config. Unverified on
  -- this client: rendering.parent_alpha_not_propagated says a parent's alpha
  -- does not reliably carry to its children, so this may end up a no-op. It is
  -- cosmetic either way, and the frame's own state stays correct.
  if data.connected then
    pcall(frame.SetAlpha, frame, 1)
  else
    pcall(frame.SetAlpha, frame, 0.35)
  end

  return true
end

local function RefreshAll(force)
  local i
  for i = 1, table.getn(frameOrder) do
    RefreshFrame(frames[frameOrder[i]], force)
  end
end

local function RefreshUnitToken(token)
  if type(token) ~= "string" then
    RefreshAll()
    return
  end

  local i
  for i = 1, table.getn(frameOrder) do
    local frame = frames[frameOrder[i]]
    if frame.unit == token then RefreshFrame(frame) end
  end

  -- target-of-target is derived from the target, so a target update is also a
  -- target-of-target update.
  if token == "target" and frames.targettarget then
    RefreshFrame(frames.targettarget)
  end
end

UF.Refresh = RefreshAll

-- ---------------------------------------------------------------------------
-- Mouse
--
-- No compact-DB record covers TargetUnit or GameTooltip:SetUnit, so both follow
-- UnrealPfUI's call shapes (WORKING_SOURCE) and are pcall'd.
--
-- Right-click opens the same native unit popup menu the stock frames use.
-- query_compat.py has no record at all for ToggleDropDownMenu, any *DropDown
-- global, or UnitPopup -- api/frames/events/behavior/pfui-relevant/knowledge
-- all came back empty. Per the evidence-gap rule this follows UnrealPfUI's
-- <=11200 client branch (api/unitframes.lua RightClickAction/ClickAction),
-- which is the same client level unrealUI targets (Interface: 11200):
-- ToggleDropDownMenu(1, nil, <UnitDropDownFrame>, "cursor"), where the
-- dropdown is the native global Blizzard's own FrameXML creates for that frame
-- type. SuppressStockFrames above never names these dropdown globals, only the
-- visible frame and its art/text/bar children, so they should still exist and
-- still be wired to the live target/party roster.
--
-- This is WORKING_SOURCE evidence, not runtime verification -- see
-- knowledge.json / frames.unit_dropdown_menu_unverified.
-- ---------------------------------------------------------------------------
local UNIT_DROPDOWNS = {
  player = "PlayerFrameDropDown",
  target = "TargetFrameDropDown",
  party1 = "PartyMemberFrame1DropDown",
  party2 = "PartyMemberFrame2DropDown",
  party3 = "PartyMemberFrame3DropDown",
  party4 = "PartyMemberFrame4DropDown",
}

local function ShowUnitMenu(frame)
  local dropdownName = UNIT_DROPDOWNS[frame.unit]
  if not dropdownName then return end

  local dropdown = U.G(dropdownName)
  if not dropdown then
    U.Debug("no native dropdown frame found: " .. dropdownName)
    return
  end

  local toggle = U.G("ToggleDropDownMenu")
  if type(toggle) ~= "function" then
    U.Debug("ToggleDropDownMenu is unavailable on this client")
    return
  end

  pcall(toggle, 1, nil, dropdown, "cursor")
end

-- Widget OnClick argument shape is not covered by
-- scripts.handler_arguments_direct (that record is about RegisterEvent
-- handlers), but the same ambiguity applies to SetScript callbacks: try direct
-- arguments first, then the legacy `arg1` global.
local function ResolveClickButton(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  return U.G("arg1")
end

local function EnableMouse(frame)
  pcall(frame.EnableMouse, frame, true)
  pcall(frame.RegisterForClicks, frame, "LeftButtonUp", "RightButtonUp")

  frame:SetScript("OnClick", function(a, b)
    local button = ResolveClickButton(a, b)

    if button == "RightButton" then
      ShowUnitMenu(frame)
      return
    end

    local target = U.G("TargetUnit")
    if type(target) == "function" then pcall(target, frame.unit) end
  end)

  frame:SetScript("OnEnter", function()
    local tooltip = U.G("GameTooltip")
    if not tooltip then return end

    local anchor = U.G("GameTooltip_SetDefaultAnchor")
    if type(anchor) ~= "function" or not pcall(anchor, tooltip, frame) then
      pcall(tooltip.SetOwner, tooltip, frame, "ANCHOR_RIGHT")
    end

    if pcall(tooltip.SetUnit, tooltip, frame.unit) then
      pcall(tooltip.Show, tooltip)
    end
  end)

  frame:SetScript("OnLeave", function()
    local tooltip = U.G("GameTooltip")
    if tooltip then pcall(tooltip.Hide, tooltip) end
  end)
end

-- ---------------------------------------------------------------------------
-- Events
--
-- UNIT_HEALTH and UNIT_MANA are the two verified to fire with a unit token in
-- arg1 (events.json, 22 and 20 captures). The rest are registered because they
-- would each save a poll tick if this client does emit them, and cost nothing
-- if it does not. None of them is load-bearing: the shared tick below refreshes
-- everything regardless.
-- ---------------------------------------------------------------------------
local UNIT_EVENTS = {
  "UNIT_HEALTH", "UNIT_MAXHEALTH",
  "UNIT_MANA", "UNIT_MAXMANA",
  "UNIT_RAGE", "UNIT_MAXRAGE",
  "UNIT_ENERGY", "UNIT_MAXENERGY",
  "UNIT_FOCUS", "UNIT_MAXFOCUS",
  "UNIT_DISPLAYPOWER", "UNIT_LEVEL", "UNIT_FACTION",
  "UNIT_NAME_UPDATE",
}

local GROUP_EVENTS = {
  "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED", "RAID_ROSTER_UPDATE",
}

local function RegisterEvents()
  local i
  for i = 1, table.getn(UNIT_EVENTS) do
    U.RegisterEvent(UNIT_EVENTS[i], function(event, unit)
      RefreshUnitToken(unit)
    end)
  end

  for i = 1, table.getn(GROUP_EVENTS) do
    U.RegisterEvent(GROUP_EVENTS[i], function()
      local n
      for n = 1, PARTY_COUNT do
        RefreshFrame(frames["party" .. n], true)
      end
    end)
  end

  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    RefreshFrame(frames.target, true)
    RefreshFrame(frames.targettarget, true)
  end)
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
-- The party block. An invisible frame sized to hold every member: it carries
-- the mover and the members ride along, so the four frames can never drift out
-- of alignment with each other.
local function BuildPartyAnchor()
  local spec = nil
  local i
  for i = 1, table.getn(SPECS) do
    if SPECS[i].id == "party1" then spec = SPECS[i] end
  end
  if not spec then return nil end

  local anchor = CreateFrame("Frame", "UnrealUIPartyAnchor", UIParent)
  anchor:SetWidth(FrameWidth(spec))
  anchor:SetHeight(((PARTY_COUNT - 1) * PARTY_SPACING) + FrameHeight(spec))

  U.RegisterMover("unitframes.party", anchor, {
    label = "Party",
    default = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 5, y = -5 },
  })

  -- No unit of its own, so nothing ever hides it: the members handle their own
  -- visibility and the anchor stays available to drag even with no party.
  anchor:Show()
  return anchor
end

function UF:OnEnable()
  if table.getn(frameOrder) > 0 then return end

  SuppressStockFrames()

  frames[PARTY_ANCHOR] = BuildPartyAnchor()

  local i
  for i = 1, table.getn(SPECS) do
    local spec = SPECS[i]

    -- Resolved against frames already built this pass: SPECS lists target
    -- before targettarget, and the party anchor is built before the loop
    -- starts, so every anchorTo target exists by the time it is needed.
    local parent = spec.anchorTo and frames[spec.anchorTo] or nil

    local frame = BuildFrame(spec, parent)

    frames[spec.id] = frame
    table.insert(frameOrder, spec.id)

    if parent then
      frame:SetPoint(spec.anchorPoint or "TOPLEFT", parent,
                     spec.anchorRelativePoint or "TOPLEFT",
                     spec.anchorOffsetX or 0, spec.anchorOffsetY or 0)
    else
      U.RegisterMover("unitframes." .. spec.id, frame, {
        label = spec.label,
        default = spec.default,
      })
    end

    EnableMouse(frame)
  end

  RegisterEvents()

  -- The one refresh path everything else only accelerates. 0.2s is pfUI's own
  -- polling tick for units without events (targettarget), and it is the only
  -- thing keeping target-of-target and party membership current on a client
  -- where PARTY_MEMBERS_CHANGED has never been observed firing.
  U.RegisterUpdate("unitframes.refresh", 0.2, function() RefreshAll() end)

  RefreshAll(true)
  U.Debug("unit frames built: " .. table.getn(frameOrder))
end

-- Reports what the client actually did with the unit API, so /uui check can
-- show measured values instead of restating the INCONCLUSIVE record.
function U.UnitFrameReport()
  local report, i = {}, nil

  for i = 1, table.getn(frameOrder) do
    local frame = frames[frameOrder[i]]
    local line = { id = frameOrder[i], unit = frame.unit }

    line.exists = ApiTruth("UnitExists", frame.unit)
    if line.exists then
      local data = ReadUnit(frame)
      line.name = data.name or "?"
      line.health = data.health
      line.healthMax = data.healthMax
      line.power = data.power
      line.powerMax = data.powerMax
      line.powerType = data.powerType
      line.class = data.class or "-"
      line.reaction = data.reaction
    end

    local shownOk, shown = pcall(frame.IsShown, frame)
    if shownOk then line.shown = shown else line.shown = "?" end

    -- Bar geometry readback.
    --
    -- The bars are unrealUI's own (core/style.lua) after the client's StatusBar
    -- widget left the fill unlaid-out on screen. This reports the frame width
    -- the fill extent is computed from, the value range, and the tint that was
    -- actually applied, so a bar that still draws wrong produces numbers rather
    -- than another screenshot guess.
    local bar = frame.health.bar
    local ok, value

    ok, value = pcall(bar.GetWidth, bar)
    line.barWidth = ok and U.Round(value) or "?"
    ok, value = pcall(bar.GetHeight, bar)
    line.barHeight = ok and U.Round(value) or "?"

    line.barValue = bar.uuiValue
    line.barMin, line.barMax = bar.uuiMin, bar.uuiMax

    local fill = bar.uuiFillTexture
    if fill then
      ok, value = pcall(fill.GetWidth, fill)
      line.fillWidth = ok and U.Round(value) or "?"
      ok, value = pcall(fill.GetHeight, fill)
      line.fillHeight = ok and U.Round(value) or "?"
      ok, value = pcall(fill.IsShown, fill)
      line.fillShown = ok and value or "?"

      local r, g, b = U.GetColor(fill)
      if r then
        line.fillColor = string.format("%.2f,%.2f,%.2f", r, g, b)
      else
        line.fillColor = "not cached"
      end
    end

    table.insert(report, line)
  end

  return report
end
