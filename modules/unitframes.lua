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
    -- No values strip: text lives on the health/power bars themselves --
    -- level+health on the health bar, power on the power bar, by request.
    id = "player", unit = "player", name = "Player", label = "Player",
    width = PRIMARY_WIDTH, health = 34, power = 10, gap = 0,
    healthLabels = { left = "level", right = "healthdyn" },
    powerLabels = { right = "powerdyn" },
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOM", x = -75, y = 125 },
  },
  {
    id = "target", unit = "target", name = "Target", label = "Target",
    width = PRIMARY_WIDTH, health = 34, power = 10, gap = 0,
    healthLabels = { left = "healthdyn", right = "unitrev" },
    powerLabels = { left = "powerdyn" },
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

  -- Tagged "target": these are the frames this client actually brings back on
  -- PLAYER_TARGET_CHANGED, so they are the only ones that event needs to sweep.
  U.SuppressNativeFrame(U.NativeFrameParts("TargetFrame",
    { "Texture", "TextureFrame", "Background", "NameBackground", "HealthBar",
      "HealthBarText", "ManaBar", "ManaBarText", "Name", "Level", "Portrait" },
    { { "Buff", 5 }, { "Debuff", 16 } }), "target")
  U.SuppressNativeFrame("TargetPortrait", "target")

  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTarget",
    { "Frame", "Texture", "TextureFrame", "Background", "HealthBar",
      "ManaBar", "Portrait", "Name", "DeadText" }), "target")
  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTargetFrame",
    {}, { { "Debuff", 4 } }), "target")

  local i
  for i = 1, PARTY_COUNT do
    local root = "PartyMemberFrame" .. i
    U.SuppressNativeFrame(U.NativeFrameParts(root,
      { "Texture", "Background", "HealthBar", "HealthBarText", "ManaBar",
        "ManaBarText", "Portrait", "Name", "Status", "Disconnect",
        "LeaderIcon", "MasterIcon", "PVPIcon",
        "PetFrame", "PetFrameTexture", "PetFrameHealthBar",
        "PetFramePortrait", "PetFrameName" },
      { { "Debuff", 4 } }), "party")
    U.SuppressNativeFrame(U.NativeFrameParts(root .. "PetFrame",
      {}, { { "Debuff", 4 } }), "party")
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
-- Classification icon
--
-- The elite/rare dragon drawn beside a unit's health bar. Two things behind it
-- are unverified on this client:
--
--   * query_compat.py has no record for UnitClassification's return values
--     (the only unitframe record, unitframes.core_unit_api_contract_partial,
--     is INCONCLUSIVE and does not cover it), and UnrealPfUI never draws an
--     icon for classification either -- it only appends the "+"/"R+" level
--     suffix LevelString already reproduces -- so there is no WORKING_SOURCE
--     reference for the artwork.
--   * knowledge.json / textures.separate_coin_paths_not_rendered is a
--     confirmed case of stock Blizzard texture paths that exist in Vanilla and
--     simply do not render here; it was only closed by trying paths in game.
--
-- That is why the texture, size and crop are runtime variables rather than
-- literals: /uui elite tex|size|coord answers both questions in one session
-- instead of an edit/reload cycle per candidate. Nothing here is persisted --
-- config.savedvariables_backslash_corruption means paths are never written to
-- SavedVariables, so a candidate that works gets baked into the default below.
--
-- The default path is the nameplate emblem, the one piece of classification art
-- this client is known to draw somewhere: modules/nameplates.lua reads a stock
-- plate texture region whose path contains "Elite"/"Rare".
-- ---------------------------------------------------------------------------
local ELITE_TEXTURE_DEFAULT = "Interface\\Tooltips\\EliteNameplateIcon"

local eliteTexture = ELITE_TEXTURE_DEFAULT
local eliteWidth, eliteHeight = 18, 18
local eliteCoords = nil       -- { left, right, top, bottom }; nil = whole file

-- Every classification but plain "normal" gets the icon, tinted per tier so
-- the same texture still reads as the right one at a glance -- rare gets its
-- own silver-grey rather than rareelite's silver-blue, so the two stay
-- distinguishable even though they share the "silver" family.
local ELITE_TINTS = {
  elite     = { 1.00, 0.82, 0.20 },
  rareelite = { 0.72, 0.82, 1.00 },
  worldboss = { 1.00, 0.45, 0.35 },
  rare      = { 0.80, 0.80, 0.80 },
}

-- /uui elite's test override. Forces the classification every frame reads, so
-- any mob can stand in for an elite instead of hunting one of each tier down.
local classificationOverride = nil

-- ---------------------------------------------------------------------------
-- Unit state
--
-- One reusable table per frame. Combat refreshes are bounded and should not
-- allocate per event; the slower full fallback refreshes static identity data.
-- ---------------------------------------------------------------------------
-- Units whose UnitHealth/UnitHealthMax are real hit points rather than a
-- percentage. Vanilla grants this to yourself, your pet and your party; every
-- other unit is percent-scaled.
local REAL_HEALTH_UNITS = {
  player = true, pet = true,
  party1 = true, party2 = true, party3 = true, party4 = true,
  partypet1 = true, partypet2 = true, partypet3 = true, partypet4 = true,
}

local function ReadIdentity(frame)
  local unit = frame.unit
  local data = frame.data

  data.name = ApiString("UnitName", unit)
  data.level = ApiNumber("UnitLevel", unit)
  data.isPlayer = ApiTruth("UnitIsPlayer", unit)

  -- Classification is an NPC concept: a player-controlled unit is never
  -- elite/rare/worldboss, on any frame (player, party, or a target that
  -- happens to be another player). Reading it as nil here, ahead of both the
  -- level-text "+"/"R+" suffix and the icon, is what keeps the /uui elite
  -- test override -- which forces every frame at once -- from leaking onto a
  -- player-controlled frame through either of those two paths.
  if data.isPlayer then
    data.classification = nil
  else
    data.classification = classificationOverride or
                          ApiString("UnitClassification", unit)
  end
  -- An absent UnitIsConnected must read as connected, not as everyone offline.
  if ResolveApiFn("UnitIsConnected") then
    data.connected = ApiTruth("UnitIsConnected", unit)
  else
    data.connected = true
  end
  data.class = UnitClassToken(unit)
  data.reaction = ApiNumber("UnitReaction", unit, "player")
end

local function ReadHealth(frame)
  local unit = frame.unit
  local data = frame.data

  data.health = ApiNumber("UnitHealth", unit) or 0
  data.healthMax = ApiNumber("UnitHealthMax", unit) or 0
  data.isDead = ApiTruth("UnitIsDead", unit) or ApiTruth("UnitIsGhost", unit)

  if data.healthMax > 0 then
    data.healthPercent = Clamp(data.health / data.healthMax)
  else
    data.healthPercent = 0
  end

  -- This client keeps the Vanilla rule that only units you are grouped with
  -- report real hit points: everything else returns health on a 0-100 scale
  -- with UnitHealthMax fixed at 100. Measured on mouseover world units by the
  -- tooltip probe (behavior.json, probeVersion 1.9.0: 96/100, 97/100, 91/100)
  -- and confirmed in game on the target frame, where "84 - 84%" printed the
  -- same number twice. When health *is* the percentage, the value half of the
  -- dynamic text carries no extra information, so only the percentage is
  -- drawn.
  data.healthIsPercent = data.healthMax == 100 and not REAL_HEALTH_UNITS[unit]
end

local function ReadPower(frame)
  local unit = frame.unit
  local data = frame.data

  data.power = ApiNumber("UnitMana", unit) or 0
  data.powerMax = ApiNumber("UnitManaMax", unit) or 0
  data.powerType = ApiNumber("UnitPowerType", unit)
end

local function ReadUnit(frame)
  ReadIdentity(frame)
  ReadHealth(frame)
  ReadPower(frame)
  frame.data.initialised = true

  return frame.data
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

  if token == "level" then
    local lr, lg, lb = PastelText(DifficultyColor(data.level))
    return Hex(lr, lg, lb) .. LevelString(data)
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
      if data.healthIsPercent then
        return prefix .. math.ceil(data.healthPercent * 100) .. "%"
      end
      return prefix .. Abbreviate(data.health) .. " - " ..
             math.ceil(data.healthPercent * 100) .. "%"
    end
    -- Full health on a percent-scaled unit still reads as a percentage, so it
    -- keeps the "%" rather than printing a bare 100.
    if data.healthIsPercent then return prefix .. "100%" end
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
local dirtyUnits = {}   -- unit token -> health | power | vitals | full

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

local function CreateBarLabel(parent, anchor, target, offset, yOffset)
  local label = U.CreateLabel(parent, {
    size = M.fontSize.normal,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if not label then return nil end

  -- Single-edge anchor, per fonts.stretched_justification_ignored.
  label:SetPoint(anchor, target, anchor, offset, yOffset or 0)
  return label
end

-- Left/right margin for text drawn directly on a health or power bar (player
-- and target, by request -- no separate values strip under those two).
local BAR_LABEL_MARGIN = 4
-- Nudges that text 2px down from dead-center for better vertical alignment
-- against the bar, by request. The power bar's text sits 1px higher than
-- health's (net -1), by a follow-up request.
local BAR_LABEL_Y_OFFSET = -2
local POWER_LABEL_Y_OFFSET = -1

-- Puts up to a left- and a right-anchored label directly on a bar box (health
-- or power), on the same raised-child-layer trick as the targettarget name:
-- the fill is a sibling texture whose width changes every refresh, and text
-- on the same layer can end up behind it.
local function BuildBarLabels(box, labels, yOffset)
  if not labels then return end
  yOffset = yOffset or BAR_LABEL_Y_OFFSET

  box.textLayer = CreateFrame("Frame", nil, box)
  box.textLayer:SetAllPoints(box)
  local levelOk, level = pcall(box.GetFrameLevel, box)
  if levelOk and tonumber(level) then
    pcall(box.textLayer.SetFrameLevel, box.textLayer, level + 10)
  end

  if labels.left then
    box.leftLabel = CreateBarLabel(box.textLayer, "LEFT", box.textLayer,
                                    BAR_LABEL_MARGIN, yOffset)
  end
  if labels.right then
    box.rightLabel = CreateBarLabel(box.textLayer, "RIGHT", box.textLayer,
                                     -BAR_LABEL_MARGIN, yOffset)
  end
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

-- The icon gets its own raised child layer, the same trick the targettarget
-- name and the combo pips use: the bar's fill is a sibling texture whose width
-- changes on every refresh, and art on the same layer can end up behind it.
local function BuildClassificationIcon(frame, health)
  if type(health.CreateTexture) ~= "function" then return end
  -- The player is never an elite, so the player frame never needs the slot at
  -- all. ApplyClassificationIcon still gates on UnitIsPlayer for the frames
  -- that can hold either kind of unit; this is the one that cannot.
  if frame.unit == "player" then return end

  local layer = CreateFrame("Frame", nil, health)
  layer:SetAllPoints(health)
  local levelOk, level = pcall(health.GetFrameLevel, health)
  if levelOk and tonumber(level) then
    pcall(layer.SetFrameLevel, layer, level + 10)
  end

  local icon = layer:CreateTexture(nil, "OVERLAY")
  icon:SetWidth(eliteWidth)
  icon:SetHeight(eliteHeight)
  -- Just outside the bar's right edge rather than over it: the health bar
  -- already carries the combo pips on the player frame and the strip below
  -- carries text, and neither should have artwork laid on top of it.
  icon:SetPoint("LEFT", health, "RIGHT", 3, 0)
  pcall(icon.SetTexture, icon, eliteTexture)
  pcall(icon.Hide, icon)

  frame.classIcon = icon
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
  elseif spec.healthLabels then
    BuildBarLabels(health, spec.healthLabels)
  end

  BuildClassificationIcon(frame, health)

  local previous = health
  local power = nil
  if spec.power then
    power = CreateBarBox(frame, spec.width, spec.power, border,
                         M.power.fallback)
    power:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spec.gap)
    previous = power
    if spec.powerLabels then
      BuildBarLabels(power, spec.powerLabels, POWER_LABEL_Y_OFFSET)
    end
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
  frame.uuiShown = false
  return frame
end

-- ---------------------------------------------------------------------------
-- Rogue combo points
--
-- query_compat.py has no record at all for GetComboPoints or any combo-point
-- event (api/events/behavior/knowledge all came back empty), so this follows
-- UnrealPfUI's demonstrated shape (modules/combopoints.lua) as WORKING_SOURCE
-- evidence, not runtime verification: GetComboPoints("target") plus
-- UNIT_COMBO_POINTS / PLAYER_COMBO_POINTS / PLAYER_TARGET_CHANGED /
-- PLAYER_ENTERING_WORLD. Rogue only, per request -- the pfUI reference also
-- drives a druid combo variant and a separate paladin "reck" tracker that
-- unrealUI does not reproduce here.
--
-- Flat modern design, not pfUI's red/yellow/green tiered pips: five equal
-- segments in a single hue (rogue class colour when filled, the same empty
-- bar tone the health/power bars use when not), overlaid on a raised child
-- layer across the top of the player health bar so the frame's own geometry
-- and mover position are untouched.
-- ---------------------------------------------------------------------------
local COMBO_MAX = 5
local COMBO_GAP = 2
local COMBO_HEIGHT = 4
-- Brighter than M.color.healthBg (the bar's own empty tone) on purpose: an
-- empty pip needs to read as a visible slot against the near-black health
-- bar, not blend into it.
local COMBO_EMPTY = { 0.24, 0.24, 0.24, 1.00 }

local comboPips = nil

local function BuildComboPoints(playerFrame)
  local health = playerFrame and playerFrame.health
  if not health then return end

  local border = U.BorderSize()
  local width = playerFrame.spec.width
  local pipWidth = (width - (COMBO_MAX - 1) * COMBO_GAP) / COMBO_MAX

  -- Same raised-child-layer trick as the targettarget health label: sits above
  -- the bar fill so the fill's width changes can never cover the pips.
  local layer = CreateFrame("Frame", nil, health)
  layer:SetAllPoints(health)
  local levelOk, level = pcall(health.GetFrameLevel, health)
  if levelOk and tonumber(level) then
    pcall(layer.SetFrameLevel, layer, level + 10)
  end

  comboPips = {}
  local i
  for i = 1, COMBO_MAX do
    local pip = CreateFrame("Frame", nil, layer)
    pip:SetWidth(pipWidth)
    pip:SetHeight(COMBO_HEIGHT)
    pip:SetPoint("TOPLEFT", layer, "TOPLEFT",
                border + (i - 1) * (pipWidth + COMBO_GAP), -border)
    U.CreateBackdrop(pip, { border = false, background = COMBO_EMPTY })
    comboPips[i] = pip
  end
end

local function SetComboPoints(count)
  if not comboPips then return end
  count = tonumber(count) or 0

  local i
  for i = 1, COMBO_MAX do
    if i <= count then
      U.SetBackgroundColor(comboPips[i], M.Unpack(M.class.ROGUE))
    else
      U.SetBackgroundColor(comboPips[i], M.Unpack(COMBO_EMPTY))
    end
  end
end

local function RefreshComboPoints()
  if not comboPips then return end
  local get = ResolveApiFn("GetComboPoints")
  if not get then return end
  local ok, value = pcall(get, "target")
  SetComboPoints(ok and value or 0)
end

local COMBO_EVENTS = {
  "UNIT_COMBO_POINTS", "PLAYER_COMBO_POINTS",
  "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
}

local function RegisterComboEvents()
  local i
  for i = 1, table.getn(COMBO_EVENTS) do
    U.RegisterEvent(COMBO_EVENTS[i], RefreshComboPoints)
  end
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function SetBar(bar, value, maximum)
  if not bar then return end
  maximum = tonumber(maximum) or 0
  value = tonumber(value) or 0
  if maximum <= 0 then maximum, value = 1, 0 end

  if bar.uuiMin ~= 0 or bar.uuiMax ~= maximum then
    pcall(bar.SetMinMaxValues, bar, 0, maximum)
  end
  if bar.uuiValue ~= value then
    pcall(bar.SetValue, bar, value)
  end
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

  if frame.healthColorR == r and frame.healthColorG == g and
     frame.healthColorB == b then return end
  frame.healthColorR, frame.healthColorG, frame.healthColorB = r, g, b
  U.SetStatusBarColor(frame.health.bar, r, g, b, 1)
end

local function ApplyPowerColor(frame)
  if not frame.power then return end
  local color = M.power[frame.data.powerType] or M.power.fallback
  local r, g, b, a = M.Unpack(color)
  if frame.powerColorR == r and frame.powerColorG == g and
     frame.powerColorB == b and frame.powerColorA == a then return end
  frame.powerColorR, frame.powerColorG = r, g
  frame.powerColorB, frame.powerColorA = b, a
  U.SetStatusBarColor(frame.power.bar, r, g, b, a)
end

local function TokenNeedsRefresh(token, mode)
  if mode == "full" then return true end
  if token == "healthdyn" then
    return mode == "health" or mode == "vitals"
  end
  if token == "powerdyn" then
    return mode == "power" or mode == "vitals"
  end
  return false
end

local function ApplyBarLabels(frame, box, labels, mode)
  if not box or not labels then return end
  if box.leftLabel and TokenNeedsRefresh(labels.left, mode) then
    SetLabelText(box.leftLabel, StatusText(frame, labels.left))
  end
  if box.rightLabel and TokenNeedsRefresh(labels.right, mode) then
    SetLabelText(box.rightLabel, StatusText(frame, labels.right))
  end
end

local function ApplyTexts(frame, mode)
  if frame.health.label and TokenNeedsRefresh(frame.spec.healthText, mode) then
    SetLabelText(frame.health.label, StatusText(frame, frame.spec.healthText))
  end
  ApplyBarLabels(frame, frame.health, frame.spec.healthLabels, mode)
  ApplyBarLabels(frame, frame.power, frame.spec.powerLabels, mode)

  local tokens = frame.spec.values or {}
  local v = frame.values
  if not v then return end
  if v.left and TokenNeedsRefresh(tokens.left, mode) then
    SetLabelText(v.left, StatusText(frame, tokens.left))
  end
  if v.center and TokenNeedsRefresh(tokens.center, mode) then
    SetLabelText(v.center, StatusText(frame, tokens.center))
  end
  if v.right and TokenNeedsRefresh(tokens.right, mode) then
    SetLabelText(v.right, StatusText(frame, tokens.right))
  end
end

local function ClearTexts(frame)
  SetLabelText(frame.health.label, "")
  SetLabelText(frame.health.leftLabel, "")
  SetLabelText(frame.health.rightLabel, "")
  if frame.power then
    SetLabelText(frame.power.leftLabel, "")
    SetLabelText(frame.power.rightLabel, "")
  end

  local v = frame.values
  if not v then return end
  SetLabelText(v.left, "")
  SetLabelText(v.center, "")
  SetLabelText(v.right, "")
end

-- SetColor caches the tint it applied (core/compat.lua) because this client has
-- no GetVertexColor to read one back with, so /uui elite status can still
-- report what the icon was actually told to be.
local function ApplyClassificationIcon(frame)
  local icon = frame.classIcon
  if not icon then return end

  local class = frame.data.classification or ""
  local tint = ELITE_TINTS[class]
  local state = tint and class or false

  -- Nothing below needs to run again while the classification has not changed.
  if frame.classIconState == state then return end
  frame.classIconState = state

  if not tint then
    pcall(icon.Hide, icon)
    return
  end

  U.SetColor(icon, tint[1], tint[2], tint[3], 1)
  pcall(icon.Show, icon)
end

local function HideClassificationIcon(frame)
  if not frame.classIcon or frame.classIconState == false then return end
  frame.classIconState = false
  pcall(frame.classIcon.Hide, frame.classIcon)
end

local function SetFrameShown(frame, shown)
  if frame.uuiShown == shown then return end
  frame.uuiShown = shown
  if shown then frame:Show() else frame:Hide() end
end

local function ApplyConnectedAlpha(frame)
  local alpha = frame.data.connected and 1 or 0.35
  if frame.uuiAlpha == alpha then return end
  if pcall(frame.SetAlpha, frame, alpha) then frame.uuiAlpha = alpha end
end

local function RefreshFrame(frame, mode)
  local exists = ApiTruth("UnitExists", frame.unit)

  if not exists then
    frame.data.initialised = false
    HideClassificationIcon(frame)
    -- An empty shell stays on screen while the UI is unlocked, otherwise a
    -- frame with no unit could never be dragged into place.
    if U.IsUnlocked() then
      SetFrameShown(frame, true)
      SetBar(frame.health.bar, 0, 1)
      if frame.power then SetBar(frame.power.bar, 0, 1) end
      local r, g, b = M.Unpack(M.color.healthFull)
      if frame.healthColorR ~= r or frame.healthColorG ~= g or
         frame.healthColorB ~= b then
        frame.healthColorR, frame.healthColorG, frame.healthColorB = r, g, b
        U.SetStatusBarColor(frame.health.bar, r, g, b, 1)
      end
      ClearTexts(frame)
    else
      SetFrameShown(frame, false)
    end
    return false
  end

  SetFrameShown(frame, true)

  if not frame.data.initialised then mode = "full" end
  if mode ~= "health" and mode ~= "power" and mode ~= "vitals" then
    mode = "full"
  end

  local healthChanged = (mode == "full")
  local powerChanged = (mode == "full")

  if mode == "full" then
    ReadUnit(frame)
  else
    if mode == "health" or mode == "vitals" then
      local health, maximum, dead = frame.data.health,
                                    frame.data.healthMax, frame.data.isDead
      ReadHealth(frame)
      healthChanged = health ~= frame.data.health or
                      maximum ~= frame.data.healthMax or
                      dead ~= frame.data.isDead
    end
    if mode == "power" or mode == "vitals" then
      local power, maximum, powerType = frame.data.power,
                                        frame.data.powerMax,
                                        frame.data.powerType
      ReadPower(frame)
      powerChanged = power ~= frame.data.power or
                     maximum ~= frame.data.powerMax or
                     powerType ~= frame.data.powerType
    end
  end

  if healthChanged then
    SetBar(frame.health.bar, frame.data.health, frame.data.healthMax)
    ApplyHealthColor(frame)
  end
  if frame.power and powerChanged then
    SetBar(frame.power.bar, frame.data.power, frame.data.powerMax)
    ApplyPowerColor(frame)
  end

  local textMode = nil
  if mode == "full" then
    textMode = "full"
  elseif healthChanged and powerChanged then
    textMode = "vitals"
  elseif healthChanged then
    textMode = "health"
  elseif powerChanged then
    textMode = "power"
  end
  if textMode then ApplyTexts(frame, textMode) end
  if mode == "full" then ApplyClassificationIcon(frame) end

  -- Offline party members are dimmed rather than hidden, matching pfUI's
  -- alpha_offline treatment without importing its alpha config. Unverified on
  -- this client: rendering.parent_alpha_not_propagated says a parent's alpha
  -- does not reliably carry to its children, so this may end up a no-op. It is
  -- cosmetic either way, and the frame's own state stays correct.
  if mode == "full" then ApplyConnectedAlpha(frame) end

  return true
end

local function RefreshAll()
  local i
  for i = 1, table.getn(frameOrder) do
    RefreshFrame(frames[frameOrder[i]], "full")
  end
end

-- Combat can emit several health/power events for the same unit in one render
-- interval. Refreshing synchronously in every handler multiplied the complete
-- ReadUnit + texture-layout path by the number of attackers, which matches the
-- reported party-only FPS collapse. Keep events as accelerators, but collapse
-- each unit's burst to at most one refresh per short update interval.
local function QueueUnitToken(token, mode)
  if type(token) ~= "string" or not frames[token] then return end
  if mode ~= "health" and mode ~= "power" and mode ~= "vitals" then
    mode = "full"
  end

  local current = dirtyUnits[token]
  if current == "full" or current == mode then return end
  if mode == "full" or not current then
    dirtyUnits[token] = mode
  else
    dirtyUnits[token] = "vitals"
  end
end

local function FlushDirtyUnits()
  local i
  for i = 1, table.getn(frameOrder) do
    local id = frameOrder[i]
    local mode = dirtyUnits[id]
    if mode then
      dirtyUnits[id] = nil
      RefreshFrame(frames[id], mode)
    end
  end
end

-- One scheduler owns every recurring unit-frame read. Four cycles use cheap
-- vitals-only party reads plus queued event work; the fifth performs the full
-- identity/roster fallback required by this client's unobserved party event.
-- Keeping these in one callback prevents separate timers from stacking their
-- work on the same render tick once per second.
local refreshCycle = 0
local function RefreshScheduledUnits()
  refreshCycle = refreshCycle + 1
  if refreshCycle >= 5 then
    refreshCycle = 0
    local i
    for i = 1, table.getn(frameOrder) do
      dirtyUnits[frameOrder[i]] = nil
    end
    RefreshAll()
    return
  end

  -- Party events are not load-bearing: sample existence, health and power at
  -- the established 0.2s cadence even when PARTY_MEMBERS_CHANGED never emits.
  local i
  for i = 1, PARTY_COUNT do
    local id = "party" .. i
    local mode = dirtyUnits[id]
    dirtyUnits[id] = nil
    if mode == "full" then
      RefreshFrame(frames[id], "full")
    else
      RefreshFrame(frames[id], "vitals")
    end
  end

  -- Target-of-target has no observed event. It changes independently of the
  -- player's target, so it keeps the same bounded polling cadence.
  dirtyUnits.targettarget = nil
  RefreshFrame(frames.targettarget, "full")
  FlushDirtyUnits()
end

UF.Refresh = RefreshAll

-- Anchor lookup for overlays that ride a unit frame without owning one.
-- modules/auras.lua attaches its debuff row to the top of the player and target
-- frames this way, so it never has to know the generated frame names or
-- duplicate the mover wiring. Returns nil before OnEnable has built the frames.
function U.GetUnitFrame(id)
  if type(id) ~= "string" then return nil end
  return frames[id]
end

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

local HEALTH_EVENTS = {
  UNIT_HEALTH = true, UNIT_MAXHEALTH = true,
}

local POWER_EVENTS = {
  UNIT_MANA = true, UNIT_MAXMANA = true,
  UNIT_RAGE = true, UNIT_MAXRAGE = true,
  UNIT_ENERGY = true, UNIT_MAXENERGY = true,
  UNIT_FOCUS = true, UNIT_MAXFOCUS = true,
  UNIT_DISPLAYPOWER = true,
}

local GROUP_EVENTS = {
  "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED", "RAID_ROSTER_UPDATE",
}

local function RegisterEvents()
  local i
  for i = 1, table.getn(UNIT_EVENTS) do
    U.RegisterEvent(UNIT_EVENTS[i], function(event, unit)
      local mode = "full"
      if HEALTH_EVENTS[event] then
        mode = "health"
      elseif POWER_EVENTS[event] then
        mode = "power"
      end
      QueueUnitToken(unit, mode)
    end)
  end

  for i = 1, table.getn(GROUP_EVENTS) do
    U.RegisterEvent(GROUP_EVENTS[i], function()
      local n
      for n = 1, PARTY_COUNT do
        QueueUnitToken("party" .. n, "full")
      end
    end)
  end

  U.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    QueueUnitToken("target", "full")
    QueueUnitToken("targettarget", "full")
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

  if frames.player and UnitClassToken("player") == "ROGUE" then
    BuildComboPoints(frames.player)
    RegisterComboEvents()
    RefreshComboPoints()
  end

  -- One bounded scheduler coalesces event bursts, polls party vitals and
  -- target-of-target at 0.2s, and performs a full fallback once per second.
  U.RegisterUpdate("unitframes.refresh", 0.2, RefreshScheduledUnits)

  RefreshAll()
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
      line.classification = data.classification or "-"
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


-- ---------------------------------------------------------------------------
-- Elite icon test surface (/uui elite)
--
-- Everything here is transient session state, not config: the override is a
-- test aid, and the texture/size/crop exist to find a path this client renders
-- without an edit/reload cycle per candidate. Nothing is written to
-- SavedVariables.
-- ---------------------------------------------------------------------------
local OVERRIDE_VALUES = {
  elite = true, rareelite = true, worldboss = true, rare = true, normal = true,
}

local function ApplyEliteIconSettings()
  local i
  for i = 1, table.getn(frameOrder) do
    local icon = frames[frameOrder[i]].classIcon
    if icon then
      pcall(icon.SetTexture, icon, eliteTexture)
      pcall(icon.SetWidth, icon, eliteWidth)
      pcall(icon.SetHeight, icon, eliteHeight)
      if eliteCoords then
        pcall(icon.SetTexCoord, icon, eliteCoords[1], eliteCoords[2],
              eliteCoords[3], eliteCoords[4])
      else
        pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
      end
    end
  end
  RefreshAll()
end

-- Returns ok, override. "normal" is a real value rather than an alias for off:
-- it proves the icon *hides* on a unit that has one, which is the other half of
-- the test.
function U.SetUnitClassificationOverride(value)
  if value == nil or value == "" or value == "off" or value == "none" then
    classificationOverride = nil
  elseif OVERRIDE_VALUES[value] then
    classificationOverride = value
  else
    return false, classificationOverride
  end

  RefreshAll()
  return true, classificationOverride
end

function U.SetEliteIconTexture(path)
  if type(path) ~= "string" or path == "" or path == "default" then
    eliteTexture = ELITE_TEXTURE_DEFAULT
  else
    eliteTexture = path
  end
  ApplyEliteIconSettings()
  return eliteTexture
end

function U.SetEliteIconSize(width, height)
  eliteWidth = tonumber(width) or eliteWidth
  eliteHeight = tonumber(height) or eliteWidth
  ApplyEliteIconSettings()
  return eliteWidth, eliteHeight
end

-- Four numbers set a crop, anything else clears it back to the whole file.
function U.SetEliteIconCoords(left, right, top, bottom)
  left, right = tonumber(left), tonumber(right)
  top, bottom = tonumber(top), tonumber(bottom)

  if left and right and top and bottom then
    eliteCoords = { left, right, top, bottom }
  else
    eliteCoords = nil
  end

  ApplyEliteIconSettings()
  return eliteCoords
end

function U.EliteIconReport()
  local report = {
    override = classificationOverride or "off",
    texture = eliteTexture,
    width = eliteWidth,
    height = eliteHeight,
    units = {},
  }

  if eliteCoords then
    report.coords = table.concat({ eliteCoords[1], eliteCoords[2],
                                   eliteCoords[3], eliteCoords[4] }, " ")
  end

  local i
  for i = 1, table.getn(frameOrder) do
    local frame = frames[frameOrder[i]]
    if ApiTruth("UnitExists", frame.unit) then
      local line = { id = frameOrder[i], unit = frame.unit }

      -- The raw API value next to the value the frame actually drew: with an
      -- override active these differ, and without one they must not.
      line.classification = ApiString("UnitClassification", frame.unit) or "nil"
      line.effective = frame.data.classification or "nil"

      local icon = frame.classIcon
      if not icon then
        line.shown = "no icon built"
      else
        local ok, shown = pcall(icon.IsShown, icon)
        if ok then line.shown = shown and true or false else line.shown = "?" end

        -- Readback of what the client kept: a path it rejected outright shows
        -- up here, though a path it accepts but cannot render will not.
        local okPath, path = pcall(icon.GetTexture, icon)
        if okPath and type(path) == "string" then line.path = path end

        local r, g, b = U.GetColor(icon)
        if r then line.tint = string.format("%.2f,%.2f,%.2f", r, g, b) end
      end

      table.insert(report.units, line)
    end
  end

  return report
end
