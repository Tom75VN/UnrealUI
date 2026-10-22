-- ---------------------------------------------------------------------------
-- Fake party (screenshot / layout test)
--
-- `/uui fakeparty` makes party1..party4 report a full, varied group through
-- the client's own unit APIs so the real party frames, class skins, auras and
-- theme dressing draw exactly what a live group would. Nothing is drawn here:
-- the frames read these values through U.G like they read the real ones.
--
-- The wrappers are installed at load, before modules\unitframes.lua caches its
-- API functions (ResolveApiFn keeps the first function it resolves). While the
-- test is off they forward every call untouched; only partyN / partypetN
-- tokens are answered locally while it is on. A real group must not be in
-- play: real party members are overridden for the duration.
--
-- Not covered (no API to fake): portraits (SetPortraitTexture is left native,
-- so fake members show a blank or generic portrait), HoT timers, heal
-- prediction, and the 3D model.
-- ---------------------------------------------------------------------------
local U = UnrealUI

local fake = { active = false }
U.FakeParty = fake

local ICON = "Interface\\Icons\\"

-- One entry per party slot. `power` is the UnitPowerType value (0 mana,
-- 1 rage, 3 energy); `buffs` / `debuffs` are { icon, count, dispelType }.
local MEMBERS = {
  { name = "Thorgrim", class = "Warrior", token = "WARRIOR", level = 60,
    hp = 0.87, power = 1, pp = 0.55, leader = true,
    buffs = { { "Spell_Holy_WordFortitude", 1 }, { "Spell_Nature_Regeneration", 1 },
              { "Spell_Holy_PowerWordShield", 1 }, { "Spell_Holy_Renew", 1 } },
    debuffs = { { "Ability_Warrior_Sunder", 3, nil } } },
  { name = "Elunara", class = "Priest", token = "PRIEST", level = 58,
    hp = 1.0, power = 0, pp = 0.34,
    buffs = { { "Spell_Holy_WordFortitude", 1 }, { "Spell_Holy_PowerWordShield", 1 },
              { "Spell_Holy_InnerFire", 1 } },
    debuffs = { { "Spell_Shadow_ShadowWordPain", 1, "Magic" },
                { "Spell_Shadow_CurseOfTounges", 1, "Curse" } } },
  { name = "Vexmage", class = "Mage", token = "MAGE", level = 59,
    hp = 0.34, power = 0, pp = 0.78,
    buffs = { { "Spell_Holy_MagicalSentry", 1 }, { "Spell_Nature_Regeneration", 1 } },
    debuffs = { { "Spell_Nature_CorrosiveBreath", 2, "Poison" },
                { "Spell_Shadow_CallofBone", 1, "Disease" },
                { "Spell_Shadow_ShadowWordPain", 1, "Magic" } } },
  { name = "Shadowstep", class = "Rogue", token = "ROGUE", level = 60,
    hp = 0, power = 3, pp = 0, dead = true, buffs = {}, debuffs = {} },
}

local PETS = {
  { name = "Fang", hp = 0.9, buffs = {}, debuffs = {} },
  nil,
  { name = "Sparky", hp = 0.5, buffs = {}, debuffs = {} },
}

local function Slot(unit)
  if type(unit) ~= "string" then return nil, nil end
  local pet = string.find(unit, "^partypet%d$")
  if pet then return tonumber(string.sub(unit, 9)), true end
  if string.find(unit, "^party%d$") then
    return tonumber(string.sub(unit, 6)), false
  end
  return nil, nil
end

-- The member (or pet) record a fake unit token resolves to, or nil.
local function Record(unit)
  if not fake.active then return nil end
  local slot, pet = Slot(unit)
  if not slot then return nil end
  if pet then return PETS[slot], true end
  return MEMBERS[slot], false
end

local HEALTH_MAX = 4200
local POWER_MAX = { [0] = 3000, [1] = 100, [3] = 100 }

-- name -> function(record, isPet, a, b) returning the fake answer. A nil
-- return from a handler is a valid "no value"; the wrapper still does not fall
-- through to the native call for a fake unit.
local handlers = {
  UnitExists = function() return 1 end,
  UnitName = function(r) return r.name end,
  UnitClass = function(r, pet)
    if pet then return "Hunter Pet", "HUNTER" end
    return r.class, r.token
  end,
  UnitLevel = function(r) return r.level or 58 end,
  UnitHealthMax = function() return HEALTH_MAX end,
  UnitHealth = function(r) return math.floor(HEALTH_MAX * (r.hp or 1)) end,
  UnitPowerType = function(r) return r.power or 0 end,
  UnitManaMax = function(r) return POWER_MAX[r.power or 0] or 100 end,
  UnitMana = function(r)
    return math.floor((POWER_MAX[r.power or 0] or 100) * (r.pp or 1))
  end,
  UnitIsConnected = function() return 1 end,
  UnitIsDead = function(r) return r.dead and 1 or nil end,
  UnitIsGhost = function() return nil end,
  UnitIsPlayer = function(r, pet) if pet then return nil end return 1 end,
  UnitIsVisible = function() return 1 end,
  UnitIsPartyLeader = function(r) return r.leader and 1 or nil end,
  UnitCanAssist = function() return 1 end,
  UnitClassification = function() return "normal" end,
  UnitReaction = function() return 5 end,
}

local function Install(name)
  local original = U.G(name)
  if type(original) ~= "function" then return end
  local answer = handlers[name]
  U.SetG(name, function(a, b)
    local r, pet = Record(a)
    if r then return answer(r, pet, a, b) end
    return original(a, b)
  end)
end

local function InstallAura(name, key)
  local original = U.G(name)
  if type(original) ~= "function" then return end
  U.SetG(name, function(unit, index)
    local r = Record(unit)
    if r then
      local aura = r[key] and r[key][index]
      if not aura then return nil end
      return ICON .. aura[1], aura[2] or 1, aura[3]
    end
    return original(unit, index)
  end)
end

local function InstallRoster()
  local members = U.G("GetNumPartyMembers")
  if type(members) == "function" then
    U.SetG("GetNumPartyMembers", function(a, b)
      if fake.active then return table.getn(MEMBERS) end
      return members(a, b)
    end)
  end
  local slot = U.G("GetPartyMember")
  if type(slot) == "function" then
    U.SetG("GetPartyMember", function(index, b)
      if fake.active then
        if MEMBERS[tonumber(index) or 0] then return 1 end
        return nil
      end
      return slot(index, b)
    end)
  end
end

local name
for name in pairs(handlers) do Install(name) end
InstallAura("UnitBuff", "buffs")
InstallAura("UnitDebuff", "debuffs")
InstallRoster()

function fake.Set(on)
  fake.active = on and true or false
  if U.RelayoutPartyBlock then pcall(U.RelayoutPartyBlock) end
  U.Print(fake.active and
    "Fake party ON: 4 members, auras, low health, a dead member, 2 pets. " ..
    "Take the screenshot, then /uui fakeparty off."
    or "Fake party OFF.")
end
