-- unrealUI :: modules/partytest.lua
--
-- "/uui party test": a fake four-member party so the party block can be
-- checked and screenshotted outside a group (ported from pandaUI, user
-- request 2026-10-31). Unlike "/uui fakeparty" (core/fakeparty.lua), which
-- wraps the client's globals at load, this answers only UnrealUI's own reads
-- and also drives HoT timers and incoming heals.
--
-- How it reaches every party feature without touching each one: unrealUI reads
-- the client through U.G (core/init.lua) and the cached resolvers in
-- modules/unitframes.lua and modules/auras.lua, and all three consult
-- U.gOverride first. While the test runs, that table holds wrappers for the
-- unit APIs the party code reads. A wrapper answers from the records below for
-- party1-4 / partypet1-4 and passes every other unit to the real function, so
-- the player, target and raid frames keep reading the client. Other addons and
-- the client never see the fake party: nothing global is replaced.
-- Both raid-frame cell pools (modules/raidframes.lua) read the same way, so
-- the raid-style party column shows the fake party too.
--
-- Two features need more than an API answer and get their own hook:
--   * HoT indicators (modules/hots.lua) come from the player's own cast stamps,
--     so ScanUnit asks U.PartyTestHots for the fake members instead.
--   * Incoming heals (modules/healpredict.lua) come from U.UnitIncomingHeal,
--     which is wrapped here and restored when the test stops.
--
-- Known limits: party buff/debuff icons show without a radial, because their
-- duration comes from a tooltip name scan a fake unit cannot answer; the
-- portrait is the player's own (a fake unit has no model); the Classic theme
-- hands the party to the client's own frames, which read the real roster.
-- Members are rolled at random on every run, like /uui raid test, and use
-- stock 1.12 Interface\Icons paths.

local U = UnrealUI

local PT = {
  active = false,
  states = false,
  members = nil,   -- token -> record
  saved = {},      -- original U functions replaced while active
}

local ICON = "Interface\\Icons\\"

-- Random pools, rolled on every "/uui party test" the way /uui raid test does
-- (modules/raidframes.lua TEST). Buffs: texture. Debuffs: texture, school
-- (nil = no school). HoTs: texture, duration.
local POOL = {
  classes = { "WARRIOR", "MAGE", "ROGUE", "DRUID", "HUNTER", "SHAMAN",
              "PRIEST", "WARLOCK", "PALADIN" },
  classLocal = {
    WARRIOR = "Warrior", MAGE = "Mage", ROGUE = "Rogue", DRUID = "Druid",
    HUNTER = "Hunter", SHAMAN = "Shaman", PRIEST = "Priest",
    WARLOCK = "Warlock", PALADIN = "Paladin",
  },
  names = { "Aldric", "Brenna", "Cael", "Doran", "Elwin", "Fenna", "Garrick",
            "Hesta", "Ilyas", "Jorund", "Kaela", "Lothar", "Mirelle",
            "Nathanos", "Orla", "Perrin", "Quenna", "Rowan", "Sylvara",
            "Thoradin", "Ulric", "Vesna", "Wendel", "Xandra", "Yorick" },
  petNames = { "Fang", "Brutus", "Shadowclaw", "Grimtusk", "Zix", "Kreeg",
               "Mittens", "Razorhide" },
  buffs = {
    ICON .. "Spell_Holy_WordFortitude",
    ICON .. "Spell_Nature_Regeneration",
    ICON .. "Spell_Holy_MagicalSentry",
    ICON .. "Spell_Magic_MageArmor",
    ICON .. "Spell_Holy_FistOfJustice",
    ICON .. "Spell_Holy_DevotionAura",
    ICON .. "Spell_Shadow_AntiShadow",
    ICON .. "Spell_Nature_Thorns",
    ICON .. "Ability_Warrior_BattleShout",
    ICON .. "Spell_Holy_PowerWordShield",
    ICON .. "Ability_TrueShot",
    ICON .. "Spell_Nature_RavenForm",
  },
  debuffs = {
    { ICON .. "Spell_Shadow_ShadowWordPain", "Magic" },
    { ICON .. "Spell_Frost_FrostNova", "Magic" },
    { ICON .. "Spell_Shadow_CurseOfSargeras", "Curse" },
    { ICON .. "Spell_Nature_CorrosiveBreath", "Poison" },
    { ICON .. "Spell_Shadow_CallofBone", "Disease" },
    { ICON .. "Ability_Gouge" },
  },
  hots = {
    { ICON .. "Spell_Nature_Rejuvenation", 12 },
    { ICON .. "Spell_Holy_Renew", 15 },
    { ICON .. "Spell_Nature_ResistNature", 21 },
  },
}

-- Every dispel school on every roll: member i leads with SCHOOLS[i].
local SCHOOLS = { "Magic", "Curse", "Poison", "Disease" }

-- The "states" variant: one member each out of range, dead and offline.
local STATES = {
  party2 = { visible = false },
  party3 = { dead = true },
  party4 = { connected = false },
}

local TOKENS = { "party1", "party2", "party3", "party4",
                 "partypet1", "partypet2", "partypet3", "partypet4" }

local function Now()
  local fn = U.G("GetTime")
  local ok, value = false, nil
  if type(fn) == "function" then ok, value = pcall(fn) end
  return (ok and tonumber(value)) or 0
end

local function Chance(percent)
  return math.random(100) <= percent
end

local function Pick(list)
  return list[math.random(table.getn(list))]
end

-- Health, power and incoming heals for one record.
local function RollVitals(m, powerType, powerMax)
  m.healthMax = math.random(20, 65) * 100
  m.health = math.random(math.floor(m.healthMax / 10), m.healthMax)
  m.powerType, m.powerMax = powerType, powerMax
  m.power = math.random(0, powerMax)
  m.mine = Chance(45) and math.random(5, 30) / 100 or 0
  m.others = Chance(30) and math.random(5, 20) / 100 or 0
end

-- `count` distinct buffs, stacks on a few.
local function RollBuffs(count)
  local buffs, used = {}, {}
  while table.getn(buffs) < count do
    local index = math.random(table.getn(POOL.buffs))
    if not used[index] then
      used[index] = true
      table.insert(buffs, { POOL.buffs[index], 1 })
    end
  end
  return buffs
end

local function RollHots(now)
  local hots = {}
  local k
  for k = 1, table.getn(POOL.hots) do
    if Chance(45) then
      local h = POOL.hots[k]
      table.insert(hots, { entry = { texture = h[1] },
                           live = { start = now - math.random(0, h[2] - 1),
                                    duration = h[2] } })
    end
  end
  return hots
end

local function SchoolDebuff(school)
  local i
  for i = 1, table.getn(POOL.debuffs) do
    if POOL.debuffs[i][2] == school then
      return { POOL.debuffs[i][1], 1, school }
    end
  end
end

local function RollMember(index, now)
  local class = Pick(POOL.classes)
  local m = {
    name = Pick(POOL.names), class = class,
    classLocal = POOL.classLocal[class], level = math.random(55, 60),
    connected = true, dead = false, visible = true,
  }
  if class == "WARRIOR" then
    RollVitals(m, 1, 100)
  elseif class == "ROGUE" then
    RollVitals(m, 3, 100)
  else
    RollVitals(m, 0, math.random(20, 50) * 100)
  end

  m.buffs = RollBuffs(math.random(1, 6))
  m.debuffs = { SchoolDebuff(SCHOOLS[index]) }
  local n = math.random(0, 3)
  local i
  for i = 1, n do
    local d = Pick(POOL.debuffs)
    table.insert(m.debuffs, { d[1], Chance(25) and math.random(2, 5) or 1,
                              d[2] })
  end
  m.hots = RollHots(now)
  return m
end

-- Hunters and warlocks bring a pet (drawn only with party pets turned on).
local function RollPet(owner, now)
  if owner.class ~= "HUNTER" and owner.class ~= "WARLOCK" then return nil end
  local m = {
    name = Pick(POOL.petNames), class = "WARRIOR", classLocal = "Warrior",
    level = owner.level - math.random(0, 2), pet = true,
    connected = true, dead = false, visible = true,
  }
  if owner.class == "HUNTER" then
    RollVitals(m, 2, 100)
  else
    m.class, m.classLocal = "MAGE", "Mage"
    RollVitals(m, 0, math.random(10, 25) * 100)
  end
  m.buffs = RollBuffs(math.random(0, 2))
  m.debuffs = {}
  if Chance(40) then
    local d = Pick(POOL.debuffs)
    table.insert(m.debuffs, { d[1], 1, d[2] })
  end
  m.hots = RollHots(now)
  return m
end

local function Build(states)
  math.randomseed(math.floor(Now() * 1000))
  local now = Now()
  local members = {}
  local i
  for i = 1, 4 do
    local m = RollMember(i, now)
    local change = states and STATES["party" .. i]
    if change then
      if change.visible == false then m.visible = false end
      if change.dead then m.dead, m.health = true, 0 end
      if change.connected == false then m.connected = false end
    end
    members["party" .. i] = m
    members["partypet" .. i] = RollPet(m, now)
  end
  members["party" .. math.random(4)].leader = true
  return members
end

-- ---------------------------------------------------------------------------
-- API wrappers. Each answers for a fake token in either argument and passes
-- anything else to the real client function.
-- ---------------------------------------------------------------------------
local function Real(name)
  local saved = U.gOverride
  U.gOverride = nil
  local fn = U.G(name)
  U.gOverride = saved
  if type(fn) == "function" then return fn end
  return nil
end

local function Truth(value)
  if value then return 1 end
  return nil
end

local function Alive(m)
  return m.connected and not m.dead
end

-- answer(m, a, b) runs when `a` is a fake token.
local function UnitWrap(name, answer)
  local real = Real(name)
  return function(a, b, c)
    local m = PT.members and PT.members[a]
    if m then return answer(m, a, b) end
    if real then return real(a, b, c) end
    return nil
  end
end

local function AuraAnswer(listKey)
  return function(m, a, index)
    if not Alive(m) or not m.visible then return nil end
    local aura = m[listKey][tonumber(index) or 0]
    if not aura then return nil end
    return aura[1], aura[2], aura[3]
  end
end

local function BuildOverrides()
  local o = {}
  local members = PT.members

  o.UnitExists = UnitWrap("UnitExists", function() return 1 end)
  o.UnitName = UnitWrap("UnitName", function(m) return m.name end)
  o.UnitClass = UnitWrap("UnitClass",
    function(m) return m.classLocal, m.class end)
  o.UnitLevel = UnitWrap("UnitLevel", function(m) return m.level end)
  o.UnitClassification = UnitWrap("UnitClassification",
    function() return "normal" end)
  o.UnitIsPlayer = UnitWrap("UnitIsPlayer",
    function(m) return Truth(not m.pet) end)
  o.UnitIsConnected = UnitWrap("UnitIsConnected",
    function(m) return Truth(m.connected) end)
  o.UnitIsDead = UnitWrap("UnitIsDead", function(m) return Truth(m.dead) end)
  o.UnitIsGhost = UnitWrap("UnitIsGhost", function() return nil end)
  o.UnitIsDeadOrGhost = UnitWrap("UnitIsDeadOrGhost",
    function(m) return Truth(m.dead) end)
  o.UnitIsVisible = UnitWrap("UnitIsVisible",
    function(m) return Truth(m.visible) end)
  o.UnitIsPartyLeader = UnitWrap("UnitIsPartyLeader",
    function(m) return Truth(m.leader) end)
  o.UnitHealth = UnitWrap("UnitHealth", function(m) return m.health end)
  o.UnitHealthMax = UnitWrap("UnitHealthMax",
    function(m) return m.healthMax end)
  o.UnitMana = UnitWrap("UnitMana", function(m) return m.power end)
  o.UnitManaMax = UnitWrap("UnitManaMax", function(m) return m.powerMax end)
  o.UnitPowerType = UnitWrap("UnitPowerType",
    function(m) return m.powerType end)
  o.UnitReaction = UnitWrap("UnitReaction", function() return 5 end)
  o.UnitBuff = UnitWrap("UnitBuff", AuraAnswer("buffs"))
  o.UnitDebuff = UnitWrap("UnitDebuff", AuraAnswer("debuffs"))
  o.CheckInteractDistance = UnitWrap("CheckInteractDistance",
    function(m) return Truth(m.visible) end)

  -- Two-unit calls: the fake token can be either argument.
  local realIsUnit = Real("UnitIsUnit")
  o.UnitIsUnit = function(a, b)
    if members[a] or members[b] then return Truth(a == b) end
    if realIsUnit then return realIsUnit(a, b) end
    return nil
  end
  local realAssist = Real("UnitCanAssist")
  o.UnitCanAssist = function(a, b)
    if members[a] or members[b] then return 1 end
    if realAssist then return realAssist(a, b) end
    return nil
  end

  -- Roster size and slot occupancy.
  o.GetNumPartyMembers = function() return 4 end
  o.GetPartyMember = function(index)
    index = tonumber(index)
    if index and index >= 1 and index <= 4 then return 1 end
    return nil
  end

  -- A fake unit has no model: paint the player's portrait instead of nothing.
  local realPortrait = Real("SetPortraitTexture")
  if realPortrait then
    o.SetPortraitTexture = function(texture, unit)
      if members[unit] then unit = "player" end
      return realPortrait(texture, unit)
    end
  end

  return o
end

-- ---------------------------------------------------------------------------
-- Feature hooks read by other modules
-- ---------------------------------------------------------------------------

-- modules/hots.lua ScanUnit: fills `out` for a fake unit and returns the count,
-- or nil for a real unit so the normal stamp path runs.
function U.PartyTestHots(unit, out)
  local m = PT.members and PT.members[unit]
  if not m then return nil end
  -- Fills out[1..n] and returns n; callers never read past n.
  if not Alive(m) or not m.visible then return 0 end
  local now = Now()
  local i
  for i = 1, table.getn(m.hots) do
    local h = m.hots[i]
    -- Loop forever so the radial keeps moving while the screenshot is set up.
    if now - h.live.start >= h.live.duration then h.live.start = now end
    out[i] = { entry = h.entry, live = h.live, count = 1 }
  end
  return table.getn(m.hots)
end

local function HealWrapper(real)
  return function(unit)
    local m = PT.members and PT.members[unit]
    if m then
      if not Alive(m) then return 0, 0 end
      return m.healthMax * m.mine, m.healthMax * m.others
    end
    if real then return real(unit) end
    return 0, 0
  end
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
local UNIT_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_MAXHEALTH", "UNIT_HEALTH",
                      "UNIT_DISPLAYPOWER", "UNIT_MAXMANA", "UNIT_MANA",
                      "UNIT_AURA" }

local function Call(name)
  local fn = U[name]
  if type(fn) == "function" then pcall(fn) end
end

-- Replays the roster and per-unit events to unrealUI's own handlers, then asks
-- each party feature to repaint, so the change shows on this frame rather
-- than on the next scheduler tick.
local function Repaint()
  U.FireListeners("PARTY_MEMBERS_CHANGED")
  U.FireListeners("PARTY_LEADER_CHANGED")
  local i, k
  for i = 1, table.getn(TOKENS) do
    for k = 1, table.getn(UNIT_EVENTS) do
      U.FireListeners(UNIT_EVENTS[k], TOKENS[i])
    end
  end
  Call("RelayoutPartyBlock")
  Call("ApplyAuras")
  Call("ApplyHotIndicators")
  Call("ApplyHealPrediction")
end

local function Start(states)
  PT.members = Build(states)
  PT.states = states and true or false
  U.gOverride = BuildOverrides()
  if not PT.active then
    PT.saved.UnitIncomingHeal = U.UnitIncomingHeal
    U.UnitIncomingHeal = HealWrapper(PT.saved.UnitIncomingHeal)
  end
  PT.active = true
  U.partyTest = true
  Repaint()
end

local function Stop()
  if not PT.active then return false end
  PT.active = false
  U.partyTest = nil
  U.gOverride = nil
  U.UnitIncomingHeal = PT.saved.UnitIncomingHeal
  PT.saved.UnitIncomingHeal = nil
  PT.members = nil
  Repaint()
  return true
end

function U.PartyTestActive()
  return PT.active
end

-- /uui party test          four random members, everyone alive and in range;
--                          run again to reroll
-- /uui party test states   member 2 out of range, 3 dead, 4 offline
-- /uui party [off]         stop
function U.PartyTestCommand(rest)
  local text = type(rest) == "string" and string.lower(rest) or ""
  local _, _, word, option = string.find(text, "^%s*(%S*)%s*(%S*)")
  if word == "test" then
    local states = option == "states"
    Start(states)
    U.Print(U.L(states and "PARTY_TEST_STATES_ON" or "PARTY_TEST_ON"))
    return
  end
  if Stop() then
    U.Print(U.L("PARTY_TEST_OFF"))
  else
    U.Print(U.L("PARTY_TEST_HINT"))
  end
end
