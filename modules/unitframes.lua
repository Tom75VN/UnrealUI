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
-- Each frame is a stack of individually bordered boxes: health (large) and,
-- where the unit has one, power (thin). Every frame now carries its text on
-- the bars themselves, so no spec asks for the optional text-only "values"
-- strip the layout still supports. width is the bar width shared by the
-- stack; height is set per box, valuesHeight for the strip.
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
  {
    -- Hunter (or warlock) pet frame: portrait to the left, health/power
    -- stacked to its right. Only built and shown while a pet is actually out
    -- -- RefreshFrame's existing UnitExists gate already hides any frame with
    -- no unit, so this needs no pet-specific visibility logic of its own.
    id = "pet", unit = "pet", name = "Pet", label = "Pet",
    width = 120, health = 20, power = 8, gap = 0,
    healthLabels = { left = "unit", right = "healthdyn" },
    powerLabels = { right = "powerdyn" },
    portrait = true, happiness = true,
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOM", x = -75, y = 90 },
  },
}

local PARTY_COUNT = 4
-- Top-of-frame to top-of-frame, so the visible gap between two members is
-- this minus a member's own height (36 health + 8 power + 4 border = 48 at
-- the default 1px border). 75 left a 27px gap; reduced 80% to 5px by
-- request, hence 53.
local PARTY_SPACING = 53

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
      -- Same treatment as player/target/pet: no separate values strip -- the
      -- text lives on the bars themselves, name+health on the health bar and
      -- power on the power bar. health doubled from 18 to 36, by request.
      width = 164, health = 36, power = 8, gap = 0,
      healthLabels = { left = "unit", right = "healthdyn" },
      powerLabels = { right = "powerdyn" },
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
      "HealthBarText", "ManaBar", "ManaBarText" },
    { { "Buff", 5 }, { "Debuff", 16 } }), "target")

  -- Not $parent-named on this client. "Name", "Level" and "Portrait" were in
  -- the list above, inherited from UnrealPfUI, but TargetFrameName,
  -- TargetFrameLevel and TargetFramePortrait do not exist here: a full
  -- 29,520-entry global enumeration has TargetName, TargetLevelText,
  -- TargetHighLevelTexture and TargetPortrait instead. Those three names
  -- resolved to nil on every sweep, so nothing ever cleared the yellow level
  -- number -- the one piece of stock target art that stayed visible after the
  -- Tab-spam stability fix took Hide() away from this family.
  --
  -- TargetHighLevelTexture is the skull this client draws in place of the
  -- number for a ??-level target, so it belongs with the level rather than
  -- being a separate feature.
  U.SuppressNativeFrame({ "TargetName", "TargetLevelText",
                          "TargetHighLevelTexture", "TargetPortrait" },
                        "target")

  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTarget",
    { "Frame", "Texture", "TextureFrame", "Background", "HealthBar",
      "ManaBar", "Portrait", "Name", "DeadText" }), "target")
  U.SuppressNativeFrame(U.NativeFrameParts("TargetofTargetFrame",
    {}, { { "Debuff", 4 } }), "target")

  -- Standalone player pet frame (as opposed to a party member's nested
  -- PartyMemberFrame%dPetFrame, already covered below). No event re-shows it
  -- on this client, so it stays in the default "static" group and relies on
  -- the periodic sweep alone, same as everything else in that group.
  U.SuppressNativeFrame(U.NativeFrameParts("PetFrame",
    { "Texture", "Background", "HealthBar", "HealthBarText", "ManaBar",
      "ManaBarText", "Portrait", "Name", "Happiness" },
    { { "Debuff", 4 } }))

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

-- Long NPC/pet names (e.g. battle-pet-style "of the ..." titles) can outgrow
-- the name bar and overlap neighbouring text, so unit-frame name text is
-- capped to a fixed character count with a trailing ellipsis.
local NAME_MAX_LENGTH = 20

-- Second return is whether the name was actually cut down, so callers can
-- widen the gap to the level text that follows it.
local function TruncateName(name)
  if not name or string.len(name) <= NAME_MAX_LENGTH then return name, false end
  return string.sub(name, 1, NAME_MAX_LENGTH - 3) .. "...", true
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

-- Shared by StatusText's name/level tokens and the target frame's split
-- name/level labels (BuildBarLabels), so both colour text identically.
local function ColoredName(data)
  local name, truncated = TruncateName(data.name)
  name = name or U.G("UNKNOWN") or "Unknown"
  local nr, ng, nb = PastelText(UnitNameColor(data))
  return Hex(nr, ng, nb) .. name, truncated
end

local function ColoredLevel(data)
  local lr, lg, lb = PastelText(DifficultyColor(data.level))
  return Hex(lr, lg, lb) .. LevelString(data)
end

-- Builds one of the pfUI text tokens this module supports. Only the tokens the
-- layouts above actually use are implemented; pfUI's full token list is config
-- surface unrealUI does not have.
local function StatusText(frame, token)
  local data = frame.data
  if not token or token == "none" then return "" end

  if token == "nameplain" then
    return TruncateName(data.name) or U.G("UNKNOWN") or "Unknown"
  end

  if token == "level" then
    return ColoredLevel(data)
  end

  if token == "unit" or token == "unitrev" or token == "name" then
    local colored = ColoredName(data)

    if token == "name" then return colored end

    local level = ColoredLevel(data)

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

-- Target frame only ("unitrev" token): normal gap between the name and the
-- level that follows it, and the wider gap used once TruncateName has to cut
-- the name down, so the trailing "..." doesn't crowd the level number.
local NAME_LEVEL_GAP = 4
local NAME_LEVEL_GAP_TRUNCATED = NAME_LEVEL_GAP + 3

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

    -- "unitrev" (target frame) draws name+level as two labels instead of one
    -- string, so the gap between them can widen by a real pixel amount when
    -- the name is truncated -- a single FontString can't do that.
    if labels.right == "unitrev" then
      box.rightNameLabel = U.CreateLabel(box.textLayer, {
        size = M.fontSize.normal,
        color = M.color.text,
        inherits = "GameFontNormalSmall",
      })
      if box.rightNameLabel then
        box.rightNameLabel:SetPoint("RIGHT", box.rightLabel, "LEFT",
                                     -NAME_LEVEL_GAP, 0)
      end
    end
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

-- ---------------------------------------------------------------------------
-- Portrait (pet frame only)
--
-- knowledge.json / unitframes.portrait_model_crash (RUNTIME_FAILURE_CONFIRMED):
-- a live 3D PlayerModel portrait crashed this client. The confirmed-working
-- replacement is a 2D Texture painted through SetPortraitTexture(texture,
-- unit) -- no PlayerModel frame is ever created here. Per that record's
-- solution, the call is guarded on existing at all; a client without it drops
-- the portrait rather than guessing at an alternative.
-- ---------------------------------------------------------------------------
local PORTRAIT_GAP = 6

local function BuildPortraitBox(parent, size, border)
  local box = CreateFrame("Frame", nil, parent)
  box:SetWidth(size)
  box:SetHeight(size)
  U.CreateBackdrop(box)

  local icon = box:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", box, "TOPLEFT", border, -border)
  icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -border, border)

  box.icon = icon
  return box
end

local function RefreshPortrait(frame)
  local box = frame.portrait
  if not box or not box.icon then return end

  local setPortrait = ResolveApiFn("SetPortraitTexture")
  if not setPortrait then return end
  pcall(setPortrait, box.icon, frame.unit)
end

-- ---------------------------------------------------------------------------
-- Pet happiness
--
-- Replaces the suppressed stock PetFrameHappiness smiley. The read is
-- GetPetHappiness(), documented for this client as returning the 1/2/3 band
-- (documentation.json / global:Pet:GetPetHappiness,
-- DOCUMENTED_NOT_RUNTIME_VERIFIED) and driven from the same call by
-- UnrealPfUI's own pet happiness icon on this client
-- (api/unitframes.lua:1452, WORKING_SOURCE -- not runtime verification).
-- Non-hunter pets have no happiness and the call returns nothing usable for
-- them, which is the same gate as pfUI's explicit HUNTER check without needing
-- the class read.
--
-- The indicator is unrealUI's own flat swatch rather than the Blizzard face:
-- rules/unreal-ui-design.md removes native state art, and the stock texture is
-- one more Vanilla path this client is not known to draw (see the elite icon
-- notes above). Colour carries the band -- red / amber / green is game state,
-- so it is outside the accent restraint. It rides the portrait's corner, so a
-- client without SetPortraitTexture (portrait_model_crash fallback) has no
-- happiness swatch either rather than one laid over the bar text.
--
-- No event: the pet frame already takes a full refresh on every scheduled
-- sweep (see RefreshScheduledUnits), which is where the band is re-read.
-- ---------------------------------------------------------------------------
local HAPPINESS_SIZE = 10

local HAPPINESS_TINTS = {
  [1] = { 0.80, 0.20, 0.20 },   -- unhappy: losing loyalty, reduced damage
  [2] = { 0.85, 0.65, 0.10 },   -- content
  [3] = { 0.25, 0.75, 0.30 },   -- happy: full damage bonus
}

local function BuildHappinessIndicator(frame, border)
  local box = frame.portrait
  if not box then return end

  local badge = CreateFrame("Frame", nil, box)
  badge:SetWidth(HAPPINESS_SIZE)
  badge:SetHeight(HAPPINESS_SIZE)
  badge:SetPoint("TOPRIGHT", box, "TOPRIGHT", -border, -border)
  -- Same raised-child-layer guard the classification icon and combo pips use:
  -- the portrait texture is a sibling region and art on the same level can end
  -- up behind it.
  local levelOk, level = pcall(box.GetFrameLevel, box)
  if levelOk and tonumber(level) then
    pcall(badge.SetFrameLevel, badge, level + 10)
  end
  U.CreateBackdrop(badge)

  local fill = badge:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(M.texture.plain)
  fill:SetPoint("TOPLEFT", badge, "TOPLEFT", border, -border)
  fill:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", -border, border)
  badge.fill = fill

  pcall(badge.Hide, badge)
  frame.happiness = badge
  frame.happinessState = false
end

local function ApplyHappinessIndicator(frame)
  local badge = frame.happiness
  if not badge then return end

  local band = nil
  local fn = ResolveApiFn("GetPetHappiness")
  if fn then
    local ok, value = pcall(fn)
    if ok then band = tonumber(value) end
  end

  local tint = band and HAPPINESS_TINTS[band]
  local state = tint and band or false
  -- Nothing below needs to run again while the band has not changed.
  if frame.happinessState == state then return end
  frame.happinessState = state

  if not tint then
    pcall(badge.Hide, badge)
    return
  end

  U.SetColor(badge.fill, tint[1], tint[2], tint[3], 1)
  pcall(badge.Show, badge)
end

local function HideHappinessIndicator(frame)
  if not frame.happiness or frame.happinessState == false then return end
  frame.happinessState = false
  pcall(frame.happiness.Hide, frame.happiness)
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

-- ---------------------------------------------------------------------------
-- Rest icon
--
-- First attempt drew UnrealPfUI's native rest icon (top-left quadrant of
-- Interface\CharacterFrame\UI-StateIcon, gated on PLAYER_UPDATE_RESTING) as a
-- WORKING_SOURCE fallback -- query_compat.py had zero evidence for either the
-- texture or the event on this client. User confirmed in game it never drew.
-- Second attempt was unrealUI's own flat accent glyph, no client asset at all.
-- Now replaced by a user-supplied icon (media/rest-icon.tga, native 36x39).
-- TGA rather than PNG: this is a Vanilla-era client and
-- media/chat_resize_grip.tga is this addon's only other shipped custom
-- texture, so TGA is the one raster format already confirmed to render here
-- -- PNG support was never verified. Displayed 60% smaller than native size,
-- by request.
-- IsResting() is unchanged -- that call IS documented for this client
-- (documentation.json / global:Character:IsResting).
-- ---------------------------------------------------------------------------
local REST_ICON_SCALE = 0.4
local REST_ICON_WIDTH = 36 * REST_ICON_SCALE
local REST_ICON_HEIGHT = 39 * REST_ICON_SCALE

-- Same raised-child-layer guard as the classification icon and happiness
-- badge: the health bar's fill is a sibling texture that changes size on every
-- refresh, and art on the same frame level can end up behind it.
local function BuildRestIcon(frame, health)
  if frame.unit ~= "player" then return end
  if type(health.CreateTexture) ~= "function" then return end

  local layer = CreateFrame("Frame", nil, frame)
  layer:SetWidth(REST_ICON_WIDTH)
  layer:SetHeight(REST_ICON_HEIGHT)
  -- Centred on the frame's top-left corner, by request: half the icon (its
  -- top-left quadrant) sits outside the frame, the rest overlaps it.
  layer:SetPoint("CENTER", frame, "TOPLEFT", 0, 0)
  local levelOk, level = pcall(health.GetFrameLevel, health)
  if levelOk and tonumber(level) then
    pcall(layer.SetFrameLevel, layer, level + 10)
  end

  local icon = layer:CreateTexture(nil, "OVERLAY")
  icon:SetAllPoints(layer)
  pcall(icon.SetTexture, icon, M.texture.restIcon)

  pcall(layer.Hide, layer)
  frame.restIcon = layer
  frame.restIconState = false
end

local function BuildFrame(spec, parent)
  local border = U.BorderSize()

  -- A Button, not a Frame: knowledge.json / frames.movable_drag_requires_button
  -- _handle records Button as the widget type this client reliably routes mouse
  -- input to, and the frame needs clicks anyway.
  local frame = CreateFrame("Button", "UnrealUIUnit" .. spec.name, parent or UIParent)
  -- Unit frames are HUD elements, never modal/interface chrome.  Explicitly
  -- keep them below native windows such as the help and GM-assistance panels;
  -- SetFrameStrata also carries this layer to the frame's bar children.
  frame:SetFrameStrata("LOW")

  -- The portrait sits to the left of the bar stack on its own square, sized to
  -- match the stack's full height, and widens the frame by that square plus a
  -- fixed gap. hasPortrait can still be false with spec.portrait set: per
  -- knowledge.json / unitframes.portrait_model_crash, a client without
  -- SetPortraitTexture drops the portrait rather than guessing at a
  -- replacement, and the frame is simply bars-only in that case.
  local portraitSize = FrameHeight(spec)
  local hasPortrait = spec.portrait and ResolveApiFn("SetPortraitTexture") ~= nil
  local barOffsetX = hasPortrait and (portraitSize + PORTRAIT_GAP) or 0

  frame:SetWidth(FrameWidth(spec) + barOffsetX)
  frame:SetHeight(FrameHeight(spec))
  frame.unit = spec.unit
  frame.spec = spec
  frame.data = {}

  if hasPortrait then
    frame.portrait = BuildPortraitBox(frame, portraitSize, border)
    frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    if spec.happiness then BuildHappinessIndicator(frame, border) end
  end

  -- Each bar starts on the colour it will normally carry, so a frame is never
  -- briefly drawn in another bar's colour before the first refresh.
  local health = CreateBarBox(frame, spec.width, spec.health, border,
                              M.color.healthFull)
  health:SetPoint("TOPLEFT", frame, "TOPLEFT", barOffsetX, 0)
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
  BuildRestIcon(frame, health)

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

-- The stock combo display is its own global family, not a TargetFrame child
-- name, so the suppression list above never touched it: ComboFrame plus
-- ComboPoint1..5 and their Highlight/Shine regions (all sixteen names are in
-- this client's global table -- 2026-08-16 probe capture). The target family is
-- suppressed visual-only, alpha 0 with no Hide, and this client does not
-- propagate parent alpha, so the native gems stayed fully drawn at TargetFrame's
-- stock position on top of an otherwise invisible frame -- visible to any rogue
-- who gained a combo point, next to unrealUI's own pips.
--
-- Registered in the default "static" group, i.e. the full teardown: hide,
-- neutralise Show, drop native events. That is what UnrealPfUI's
-- modules/combopoints.lua does on this same client (ComboFrame:Hide() plus
-- ComboFrame:UnregisterAllEvents()) -- WORKING_SOURCE evidence, not runtime
-- verification. Only registered for the class unrealUI actually replaces the
-- display for; a druid keeps the native gems rather than losing combo points
-- to a frame that draws nothing for it.
local function SuppressStockComboFrame()
  local names = { "ComboFrame" }
  local i
  for i = 1, COMBO_MAX do
    table.insert(names, "ComboPoint" .. i)
    table.insert(names, "ComboPoint" .. i .. "Highlight")
    table.insert(names, "ComboPoint" .. i .. "Shine")
  end
  U.SuppressNativeFrame(names)
end

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

-- Health/power bar colours are user-configurable (settings tab below); values
-- persist as flat numeric fields (core/config.lua accepts scalars only) and
-- default to pfUI modern's own colours from core/media.lua.
--
-- Power colours are stored per power type, not as one shared colour. The
-- config is account-wide, so a single "power bar colour" would have meant
-- recolouring a priest's mana also recoloured a rogue's energy.
local POWER_TYPES = {
  { type = 0, key = "powerMana",   label = "Mana" },
  { type = 1, key = "powerRage",   label = "Rage" },
  { type = 2, key = "powerFocus",  label = "Focus" },
  { type = 3, key = "powerEnergy", label = "Energy" },
}

local POWER_KEY_BY_TYPE = {}

-- customColors is the single master switch for every bar colour on this page.
-- Unticked, the health and power bars use core/media.lua's own values and the
-- stored colours are ignored but kept, so re-ticking restores the user's
-- choices rather than starting over.
local COLOR_DEFAULTS = {
  customColors = false,
  healthColorR = M.color.healthFull[1],
  healthColorG = M.color.healthFull[2],
  healthColorB = M.color.healthFull[3],
}

do
  local i
  for i = 1, table.getn(POWER_TYPES) do
    local entry = POWER_TYPES[i]
    local default = M.power[entry.type] or M.power.fallback
    POWER_KEY_BY_TYPE[entry.type] = entry.key
    COLOR_DEFAULTS[entry.key .. "R"] = default[1]
    COLOR_DEFAULTS[entry.key .. "G"] = default[2]
    COLOR_DEFAULTS[entry.key .. "B"] = default[3]
  end
end

local function ColorConfig()
  local cfg = U.ModuleConfig("unitframes", COLOR_DEFAULTS)

  -- Carry-over from the earlier power-only toggle, which this replaced. The
  -- old key is cleared so it does not linger in SavedVariables; it is no
  -- longer in COLOR_DEFAULTS, so nothing puts it back.
  if cfg.customPowerColor ~= nil then
    if cfg.customPowerColor then cfg.customColors = true end
    cfg.customPowerColor = nil
  end

  return cfg
end

-- The two colours every bar resolves through. With the master switch off they
-- return core/media.lua's values, which is what makes unticking restore the
-- default look everywhere at once.
local function HealthBaseColor()
  local cfg = ColorConfig()
  if cfg.customColors then
    return cfg.healthColorR, cfg.healthColorG, cfg.healthColorB
  end
  local c = M.color.healthFull
  return c[1], c[2], c[3]
end

local function PowerBarColor(powerType)
  local cfg = ColorConfig()
  local key = POWER_KEY_BY_TYPE[powerType]
  -- An unrecognised power type has no configured colour of its own, so it
  -- keeps the media fallback even while custom colours are on.
  if cfg.customColors and key then
    return cfg[key .. "R"], cfg[key .. "G"], cfg[key .. "B"], 1
  end
  return M.Unpack(M.power[powerType] or M.power.fallback)
end

-- A checked custom colour always wins over the health gradient. With it off,
-- keep the default full-health colour and fade into the pastel gradient.
local function ApplyHealthColor(frame)
  local perc = frame.data.healthPercent
  local cfg = ColorConfig()
  local cr, cg, cb = HealthBaseColor()

  local r, g, b
  if cfg.customColors or perc >= 1 then
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
  local r, g, b, a = PowerBarColor(frame.data.powerType)
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
    if box.rightNameLabel and labels.right == "unitrev" then
      local name, truncated = ColoredName(frame.data)
      SetLabelText(box.rightNameLabel, name)
      SetLabelText(box.rightLabel, ColoredLevel(frame.data))
      box.rightNameLabel:SetPoint("RIGHT", box.rightLabel, "LEFT",
        -(truncated and NAME_LEVEL_GAP_TRUNCATED or NAME_LEVEL_GAP), 0)
    else
      SetLabelText(box.rightLabel, StatusText(frame, labels.right))
    end
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
  SetLabelText(frame.health.rightNameLabel, "")
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

local function ApplyRestIcon(frame)
  local icon = frame.restIcon
  if not icon then return end

  local resting = ApiTruth("IsResting")
  -- Nothing below needs to run again while the resting state has not changed.
  if frame.restIconState == resting then return end
  frame.restIconState = resting

  if resting then
    pcall(icon.Show, icon)
  else
    pcall(icon.Hide, icon)
  end
end

local function HideRestIcon(frame)
  if not frame.restIcon or frame.restIconState == false then return end
  frame.restIconState = false
  pcall(frame.restIcon.Hide, frame.restIcon)
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

local statFrameRefreshes, statFullRefreshes = 0, 0

function U.UnitFrameStats()
  return {
    frameRefreshes = statFrameRefreshes,
    fullRefreshes = statFullRefreshes,
  }
end

local function RefreshFrame(frame, mode)
  statFrameRefreshes = statFrameRefreshes + 1
  if mode == "full" then statFullRefreshes = statFullRefreshes + 1 end

  local exists = ApiTruth("UnitExists", frame.unit)

  if not exists then
    frame.data.initialised = false
    HideClassificationIcon(frame)
    HideHappinessIndicator(frame)
    HideRestIcon(frame)
    -- An empty shell stays on screen while the UI is unlocked, otherwise a
    -- frame with no unit could never be dragged into place.
    if U.IsUnlocked() then
      SetFrameShown(frame, true)
      SetBar(frame.health.bar, 0, 1)
      if frame.power then SetBar(frame.power.bar, 0, 1) end
      local r, g, b = HealthBaseColor()
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
  if mode == "full" then RefreshPortrait(frame) end
  if mode == "full" then ApplyHappinessIndicator(frame) end
  if mode == "full" then ApplyRestIcon(frame) end

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

-- ---------------------------------------------------------------------------
-- Druid form mana bar
--
-- In bear/cat/travel form the player's power bar carries rage or energy, so a
-- druid's mana disappears from the HUD entirely. This is the extra thin bar
-- that shows it, with its own mover anchor -- registered only when the player
-- is a druid, so no other class gains a handle it can never use. Same bar box,
-- border, label placement and configured mana colour as the player frame's own
-- power bar; none of pfUI's config/module machinery comes with it.
--
-- The mana *source* is NOT VERIFIED on this client:
--   * documentation.json / global:Unit:UnitMana and UnitManaMax document one
--     numeric return each, the *displayed* power -- rage or energy while
--     shifted. No documented API returns a shifted druid's mana, and
--     query_compat.py has no api/behavior/knowledge record for one.
--   * UnrealPfUI's druid mana bar (modules/superwow.lua) reads the second
--     return of UnitMana/UnitManaMax. That is a SuperWoW extension and pfUI
--     gates it on SUPERWOW_VERSION; environment.json records no SuperWoW here,
--     so it is a candidate shape, not a working reference on this client.
--
-- So the source is measured rather than assumed: the second return is read
-- while shifted and accepted only when the pair reads as plausible mana
-- (max > 0 and 0 <= value <= max). Until it qualifies the bar stays hidden and
-- /uui check prints the raw returns -- the readout that turns this gap into
-- evidence. No estimated or simulated mana is invented as a stand-in, and the
-- displayed power is never re-labelled as mana.
-- ---------------------------------------------------------------------------
local DRUID_BAR_HEIGHT = 8

local druidBar = nil                 -- bar box; also the mover target
local druidManaSource = "unresolved" -- unresolved | extra-return | none
local druidRaw = {}                  -- last measured values, for /uui check

local function ReadShiftedMana()
  local manaFn = ResolveApiFn("UnitMana")
  local maxFn = ResolveApiFn("UnitManaMax")
  if not manaFn or not maxFn then return nil end

  local ok, primary, extra = pcall(manaFn, "player")
  if not ok then return nil end
  local okMax, primaryMax, extraMax = pcall(maxFn, "player")
  if not okMax then return nil end

  -- Kept verbatim (nils included) so the self-check reports what the client
  -- actually returned, not only whether it passed the plausibility test.
  druidRaw.returns = tostring(primary) .. "/" .. tostring(primaryMax) ..
                     ", extra " .. tostring(extra) .. "/" .. tostring(extraMax)

  local mana, manaMax = tonumber(extra), tonumber(extraMax)
  if not mana or not manaMax then return nil end
  if manaMax <= 0 or mana < 0 or mana > manaMax then return nil end
  return mana, manaMax
end

local function ShowDruidBar(shown)
  if not druidBar or druidBar.uuiShown == shown then return end
  druidBar.uuiShown = shown
  if shown then druidBar:Show() else druidBar:Hide() end
end

-- Mana keeps its configured colour from the unit-frame colour settings -- the
-- same value the player's power bar uses in caster form, so the two can never
-- disagree about what mana looks like.
local function ApplyDruidManaColor()
  if not druidBar then return end
  local r, g, b, a = PowerBarColor(0)
  if druidBar.colorR == r and druidBar.colorG == g and
     druidBar.colorB == b and druidBar.colorA == a then return end
  druidBar.colorR, druidBar.colorG = r, g
  druidBar.colorB, druidBar.colorA = b, a
  U.SetStatusBarColor(druidBar.bar, r, g, b, a)
end

local function RefreshDruidMana()
  if not druidBar then return end

  local powerType = ApiNumber("UnitPowerType", "player")
  -- Power type 0 is mana: in caster form the player frame's own power bar is
  -- already the mana bar, so this one has nothing to add there.
  local shifted = powerType ~= nil and powerType ~= 0
  druidRaw.powerType = powerType
  druidRaw.shifted = shifted

  local mana, manaMax
  if shifted then mana, manaMax = ReadShiftedMana() end
  druidRaw.mana, druidRaw.manaMax = mana, manaMax

  if mana then
    if druidManaSource ~= "extra-return" then
      druidManaSource = "extra-return"
      U.Debug("druid mana source: second return of UnitMana/UnitManaMax")
    end
  elseif shifted and druidManaSource == "unresolved" then
    druidManaSource = "none"
    U.Debug("druid mana: no readable source while shifted (" ..
            tostring(druidRaw.returns) .. ")")
  end

  if not mana then
    -- An empty shell stays on screen while the UI is unlocked, matching the
    -- unit frames' own edit-mode behaviour: otherwise a druid in caster form
    -- could never drag this anchor into place.
    if U.IsUnlocked() then
      ShowDruidBar(true)
      SetBar(druidBar.bar, 0, 1)
      SetLabelText(druidBar.rightLabel, "")
    else
      ShowDruidBar(false)
    end
    return
  end

  ShowDruidBar(true)
  SetBar(druidBar.bar, mana, manaMax)
  ApplyDruidManaColor()

  -- Same text shape as the power bar's "powerdyn" token: the value, plus a
  -- percentage while not full.
  local pr, pg, pb = PastelText(M.Unpack(M.power[0] or M.power.fallback))
  local text = Hex(pr, pg, pb) .. Abbreviate(mana)
  if mana ~= manaMax then
    text = text .. " - " .. math.ceil(mana / manaMax * 100) .. "%"
  end
  SetLabelText(druidBar.rightLabel, text)
end

-- Built only for druids (see OnEnable), which is also what puts the "Druid
-- Mana" handle in edit mode for that class alone. The default position sits
-- 2px under the player frame's own default, so an untouched layout reads as a
-- third row of the player frame.
local function BuildDruidManaBar()
  local border = U.BorderSize()

  druidBar = CreateBarBox(UIParent, PRIMARY_WIDTH, DRUID_BAR_HEIGHT, border,
                          M.power[0] or M.power.fallback)
  druidBar:SetFrameStrata("LOW")
  BuildBarLabels(druidBar, { right = "druidmana" }, POWER_LABEL_Y_OFFSET)
  druidBar:Hide()
  druidBar.uuiShown = false

  U.RegisterMover("unitframes.druidmana", druidBar, {
    label = "Druid Mana",
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOM", x = -75,
                y = 125 - (DRUID_BAR_HEIGHT + 2 * border) - 2 },
  })
end

-- Events are accelerators only; the shared unit-frame tick refreshes this bar
-- regardless, which is what covers form changes on a client where
-- UNIT_DISPLAYPOWER has no capture in events.json.
local DRUID_EVENTS = {
  "UNIT_MANA", "UNIT_MAXMANA", "UNIT_DISPLAYPOWER", "PLAYER_ENTERING_WORLD",
}

local function RegisterDruidEvents()
  local i
  for i = 1, table.getn(DRUID_EVENTS) do
    U.RegisterEvent(DRUID_EVENTS[i], RefreshDruidMana)
  end
end

-- nil for every class except druid, so /uui check stays silent where the bar
-- does not exist.
function U.DruidManaReport()
  if not druidBar then return nil end

  local shownOk, shown = pcall(druidBar.IsShown, druidBar)
  return {
    source = druidManaSource,
    powerType = druidRaw.powerType,
    shifted = druidRaw.shifted,
    mana = druidRaw.mana,
    manaMax = druidRaw.manaMax,
    returns = druidRaw.returns,
    shown = (shownOk and shown) and true or false,
  }
end

-- Settings-panel entry point: recolours every built frame immediately after a
-- health/power colour change (modules/settings.lua's Apply* pattern).
--
-- Deliberately not RefreshAll: the colour picker calls this on every tick of a
-- drag so the bars track the colour live, and RefreshAll re-runs the whole
-- ReadUnit path for every frame. That is the same repeated full-refresh cost
-- that caused the party-only FPS collapse this module's scheduler exists to
-- avoid. Nothing about the unit has changed here -- only the colour derived
-- from data already in frame.data -- so this recolours and nothing else.
--
-- The cached colour guards in ApplyHealthColor/ApplyPowerColor compare against
-- the last colour applied, so they are cleared first or a config change would
-- be skipped as a no-op.
function U.ApplyUnitFrameColors()
  local i
  for i = 1, table.getn(frameOrder) do
    local frame = frames[frameOrder[i]]
    if frame and frame.data then
      frame.healthColorR, frame.healthColorG, frame.healthColorB = nil, nil, nil
      frame.powerColorR, frame.powerColorG = nil, nil
      frame.powerColorB, frame.powerColorA = nil, nil

      -- A frame with no unit has no percentage to blend against; it keeps the
      -- flat full-health colour the empty edit-mode shell already uses.
      if frame.data.healthPercent then
        ApplyHealthColor(frame)
      else
        local r, g, b = HealthBaseColor()
        U.SetStatusBarColor(frame.health.bar, r, g, b, 1)
      end

      if frame.data.powerType then ApplyPowerColor(frame) end
    end
  end

  -- The druid mana bar carries the same configured mana colour, so it tracks
  -- the picker live like the frames above. Its cached tint is cleared for the
  -- same reason theirs is.
  if druidBar then
    druidBar.colorR, druidBar.colorG = nil, nil
    druidBar.colorB, druidBar.colorA = nil, nil
    ApplyDruidManaColor()
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
  if U.PerfDisabled and U.PerfDisabled("frames") then return end

  refreshCycle = refreshCycle + 1

  -- Two pcall'd reads for druids, nothing at all for every other class: form
  -- changes have no observed event on this client, so the bar's visibility
  -- rides the same tick the frames do.
  RefreshDruidMana()

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

  -- Pet summon/dismiss has no observed event either (query_compat.py has no
  -- events.json record for any pet unit token), so it follows the same
  -- bounded polling cadence rather than waiting on UNIT_HEALTH/UNIT_MANA to
  -- fire for "pet" -- events remain an accelerator on top of this, not the
  -- mechanism the frame depends on.
  dirtyUnits.pet = nil
  RefreshFrame(frames.pet, "full")
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
    if not tooltip then return end

    -- UnrealPfUI's unit-frame OnLeave (api/unitframes.lua) fades rather than
    -- hides instantly; Hide() here made the tooltip vanish the moment the
    -- mouse crossed off the frame instead of the eased dismissal Blizzard's
    -- own tooltip animates elsewhere. Same evidence gap as SetUnit above:
    -- WORKING_SOURCE, not runtime-verified on this client.
    if not pcall(tooltip.FadeOut, tooltip) then
      pcall(tooltip.Hide, tooltip)
    end
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

  -- Unverified event (see the Rest icon section above) -- an accelerator on
  -- top of the existing 1s full-refresh cycle, which still catches the state
  -- change if this client never actually fires it.
  U.RegisterEvent("PLAYER_UPDATE_RESTING", function()
    QueueUnitToken("player", "full")
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
  -- Keep the party block on the same HUD layer as the other unit frames.
  -- SetFrameStrata propagates to child frames on this client, so the anchor
  -- must own LOW before the party members are parented to it.
  anchor:SetFrameStrata("LOW")
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

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- Used by the Unit Frames settings page, which is registered by auras.lua.
-- Keep the controls here because this module owns the colour configuration and
-- the live frame refresh.
local function BuildUnitFrameColorSettings(parent, y)
  y = y or -4
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = "Unit Frame Colors",
    width = 496,
    y = y,
  })
  table.insert(widgets, header)

  local function ColorValue(prefix)
    local cfg = ColorConfig()
    return { r = cfg[prefix .. "R"], g = cfg[prefix .. "G"],
             b = cfg[prefix .. "B"], a = 1 }
  end

  local customToggle = U.CreateCheckbox(parent, {
    name = "UnrealUISettingsCustomColors",
    text = "Use custom bar colors",
    value = ColorConfig().customColors,
    onChange = function(value)
      ColorConfig().customColors = value
      U.ApplyUnitFrameColors()
    end,
  })
  customToggle.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 26)
  table.insert(widgets, customToggle)

  local healthPicker = U.CreateColorPicker(parent, {
    name = "UnrealUISettingsHealthColor",
    text = "Health bar color",
    value = ColorValue("healthColor"),
    hasOpacity = false,
    onChange = function(color)
      local cfg = ColorConfig()
      cfg.healthColorR, cfg.healthColorG, cfg.healthColorB =
        color.r, color.g, color.b
      U.ApplyUnitFrameColors()
    end,
  })
  -- Health shares the custom-colour row; it is only meaningful once that
  -- checkbox is enabled and this keeps the combined Unit Frames page compact.
  healthPicker.SetPoint("TOPLEFT", parent, "TOPLEFT", 260, y - 26)
  table.insert(widgets, healthPicker)

  -- One picker per power type. The stored colour is per type because the
  -- config is account-wide: recolouring a priest's mana must not recolour a
  -- rogue's energy.
  local powerHeader = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if powerHeader then
    powerHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 58)
    powerHeader:SetText("Power bar colors")
    table.insert(widgets, powerHeader)
  end

  -- Laid out across one row rather than stacked, so the four power types read
  -- as a set of swatches. The label width is set explicitly because the
  -- default fills the whole settings column and neighbouring labels would
  -- overlap.
  local COLUMN_WIDTH = 118
  local powerPickers = {}
  local i
  for i = 1, table.getn(POWER_TYPES) do
    local entry = POWER_TYPES[i]
    local picker = U.CreateColorPicker(parent, {
      name = "UnrealUISettingsPowerColor" .. entry.label,
      text = entry.label,
      value = ColorValue(entry.key),
      hasOpacity = false,
      textWidth = COLUMN_WIDTH - 28,
      onChange = function(color)
        local cfg = ColorConfig()
        cfg[entry.key .. "R"] = color.r
        cfg[entry.key .. "G"] = color.g
        cfg[entry.key .. "B"] = color.b
        U.ApplyUnitFrameColors()
      end,
    })
    picker.SetPoint("TOPLEFT", parent, "TOPLEFT",
                    12 + (i - 1) * COLUMN_WIDTH, y - 80)
    table.insert(widgets, picker)
    table.insert(powerPickers, picker)
  end

  local function Refresh()
    local cfg = ColorConfig()
    healthPicker.SetValue(ColorValue("healthColor"))
    customToggle.SetValue(cfg.customColors)

    local n
    for n = 1, table.getn(POWER_TYPES) do
      powerPickers[n].SetValue(ColorValue(POWER_TYPES[n].key))
    end
  end

  return widgets, Refresh
end

U.BuildUnitFrameColorSettings = BuildUnitFrameColorSettings

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
    SuppressStockComboFrame()
    BuildComboPoints(frames.player)
    RegisterComboEvents()
    RefreshComboPoints()
  end

  -- Druid only: this is what puts the "Druid Mana" anchor in edit mode for a
  -- druid and leaves every other class's mover list untouched.
  if UnitClassToken("player") == "DRUID" then
    BuildDruidManaBar()
    RegisterDruidEvents()
    RefreshDruidMana()
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
