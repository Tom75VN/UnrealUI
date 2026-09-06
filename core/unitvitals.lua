-- unrealUI :: core/unitvitals.lua
--
-- Absolute hit points and mana for creatures this client only reports as a
-- percentage.
--
-- knowledge.json / unitframes.nongroup_health_is_percent (BEHAVIOR_VERIFIED):
-- UnitHealth/UnitHealthMax return a 0-100 percentage with the maximum pinned
-- at 100 for every unit the player is not grouped with. There is no client API
-- that hands out a hostile creature's real hit points, so the numbers have to
-- come from somewhere else. Database/unit_vitals.lua carries the realm's own
-- creature table, and this file turns it into the two values a unit frame
-- wants: an exact maximum, and the best available current value.
--
-- Maximum health and mana are exact. VMaNGOS computes them itself from the
-- same three inputs the table stores:
--
--   maxHealth = max(1, roundf(rankHpRate[rank] * classLevel[class][level][1]
--                             * healthMultiplier))
--   maxMana   = roundf(classLevel[class][level][2] * manaMultiplier)
--
-- roundf for a positive value is floor(x + 0.5), which is what U.Round does.
--
-- Current health is an estimate that is refined, never a reading. The client
-- percentage places it inside a band one percent of maximum wide; UNIT_COMBAT
-- amounts move the tracked value inside that band between percentage changes.
-- The percentage always wins a disagreement, so a missed event cannot make the
-- readout drift away from what the bar shows.
--
-- Creature identity: the table is keyed by creature id and this client exposes
-- no unit GUID or creature id at all (query_compat.py has no record for
-- UnitGUID, and none of the documented Unit functions returns an entry). The
-- key that is available is the unit's name and level, and that turns out to be
-- enough: joined against the bundled creature-name table, the 10,364 supported
-- templates produce 15,284 distinct (name, level) keys and *zero* of them
-- carry two different maximum-health values. Any candidate id whose level
-- range covers the unit therefore answers for every id sharing its name.

local U = UnrealUI

local V = U.RegisterModule("unitvitals")
U.unitvitals = V

-- Off is a real answer here: the numbers are derived from a bundled table
-- rather than read from the client, and a realm that has retuned its creatures
-- would make them wrong rather than absent.
V.DEFAULTS = { exactVitals = true }

-- Entries walked per scheduler tick while the creature-name index is built.
-- The whole table is ~10k entries; at this size the build costs a handful of
-- ticks and never a visible frame.
V.INDEX_CHUNK = 1200

V.index = nil          -- creature name -> id, or a list of ids sharing it
V.indexNames = nil     -- source table, held only while the build runs
V.indexCursor = nil    -- next() traversal state between chunks
V.indexDone = false

-- name..":"..level -> { health = n, mana = n } or { miss = true }
V.cache = {}
V.cacheCount = 0
V.CACHE_LIMIT = 400

-- The current target's refined health. Only the target is tracked: it is the
-- one unit whose damage this client reports, and the frame the readout is for.
V.track = { key = nil, current = nil, max = 0, sawCombat = false }

function V.Config()
  return U.ModuleConfig("unitvitals", V.DEFAULTS)
end

function V.Enabled()
  return V.Config().exactVitals and true or false
end

-- A guarded one-argument client call. This file runs in the core layer and has
-- no access to modules/unitframes.lua's own Api helpers.
function V.Call(name, arg)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, arg)
  if not ok then return nil end
  return value
end

-- ---------------------------------------------------------------------------
-- Bundled data
-- ---------------------------------------------------------------------------
function V.Data()
  local root = U.G("UnrealQuestData")
  if type(root) ~= "table" then return nil end

  local db = root["unit_vitals"]
  if type(db) ~= "table" then return nil end
  if type(db.units) ~= "table" or type(db.classLevel) ~= "table" then
    return nil
  end
  return db
end

-- Creature names are not part of the vitals table -- storing ten thousand
-- names per language beside it would multiply a 426 KB file by every locale
-- the client ships. They come from unrealQuest's bundled name tables instead,
-- which already exist in nine languages on the same shared global.
--
-- The client locale, not unrealUI's language setting: this is matched against
-- the name UnitName returns, which the client picks, while the addon language
-- is a display preference the player sets independently (core/locale.lua).
function V.NameTable()
  local root = U.G("UnrealQuestData")
  if type(root) ~= "table" then return nil end

  local getLocale = U.G("GetLocale")
  if type(getLocale) == "function" then
    local ok, code = pcall(getLocale)
    if ok and type(code) == "string" and
       type(root["units_" .. code]) == "table" then
      return root["units_" .. code]
    end
  end

  if type(root["units_enUS"]) == "table" then return root["units_enUS"] end
  return nil
end

-- ---------------------------------------------------------------------------
-- Creature-name index
--
-- Built once, in chunks, off the shared scheduler. A name that is shared by
-- several creature ids keeps a list; the measurement above says every id in
-- such a list agrees on maximum health at any given level, so the list only
-- exists to find one whose level range covers the unit.
-- ---------------------------------------------------------------------------
function V.AddIndexEntry(name, id)
  local existing = V.index[name]
  if existing == nil then
    V.index[name] = id
  elseif type(existing) == "table" then
    table.insert(existing, id)
  else
    V.index[name] = { existing, id }
  end
end

function V.BuildIndexChunk()
  if V.indexDone then return true end

  local db = V.Data()
  local names = V.indexNames
  if not db or not names then
    V.indexDone = true
    V.index = nil
    return true
  end

  -- next() resumes the traversal where the previous chunk stopped. The name
  -- table is bundled data that nothing writes to, so the iteration state stays
  -- valid across ticks.
  local walked, id, name = 0, V.indexCursor, nil
  while walked < V.INDEX_CHUNK do
    id, name = next(names, id)
    if id == nil then
      V.indexDone = true
      V.indexCursor = nil
      V.indexNames = nil
      U.Debug("unit vitals: creature name index built")
      return true
    end
    if type(name) == "string" and db.units[id] then
      V.AddIndexEntry(name, id)
    end
    walked = walked + 1
  end

  V.indexCursor = id
  return false
end

function V.StartIndex()
  if V.index or V.indexDone then return end

  local names = V.NameTable()
  if not names or not V.Data() then
    -- Either the vitals table or the name table is absent -- an unrealQuest
    -- install that predates the name tables, or a broken unrealUI install.
    -- The frames keep their percentage readout; nothing else changes.
    V.indexDone = true
    U.Debug("unit vitals: no creature data; exact vitals unavailable")
    return
  end

  V.index = {}
  V.indexNames = names
  V.indexCursor = nil

  U.RegisterUpdate("unitvitals.index", 0, function()
    if V.BuildIndexChunk() then U.UnregisterUpdate("unitvitals.index") end
  end)
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------
-- units[id] = { class, rank, levelMin, levelMax, healthMultiplier,
--               manaMultiplier }
function V.Resolve(name, level)
  if not V.index then return nil end

  local entry = V.index[name]
  if entry == nil then return nil end

  local db = V.Data()
  if not db then return nil end

  if type(entry) ~= "table" then
    local rec = db.units[entry]
    if rec and level >= rec[3] and level <= rec[4] then return rec end
    return nil
  end

  local i
  for i = 1, table.getn(entry) do
    local rec = db.units[entry[i]]
    if rec and level >= rec[3] and level <= rec[4] then return rec end
  end
  return nil
end

-- Returns maxHealth, maxMana. maxMana is nil for a creature that has none.
--
-- Power deliberately covers mana only. VMaNGOS gives a non-caster rage with an
-- internal maximum of 1000 that displays as 100, or energy with a maximum of
-- 100 -- both already are the 0-100 number the client hands over, so the table
-- adds nothing there and could only introduce a scale error.
function V.Compute(name, level)
  local db = V.Data()
  if not db then return nil end

  local rec = V.Resolve(name, level)
  if not rec then return nil end

  local byClass = db.classLevel[rec[1]]
  local stats = byClass and byClass[level]
  if type(stats) ~= "table" then return nil end

  local rate = 1
  if type(db.rankHpRate) == "table" and db.rankHpRate[rec[2]] then
    rate = db.rankHpRate[rec[2]]
  end

  local maxHealth = U.Round(rate * stats[1] * rec[5])
  if maxHealth < 1 then maxHealth = 1 end

  local maxMana = nil
  if stats[2] > 0 then maxMana = U.Round(stats[2] * rec[6]) end

  return maxHealth, maxMana
end

-- Cached form. A unit frame asks five times a second per frame; the answer is
-- static for a (name, level) pair, so the walk above runs once per creature.
function V.Vitals(name, level)
  if type(name) ~= "string" or name == "" then return nil end

  level = tonumber(level)
  -- A "??" target reports -1. Nothing in the table can be selected without a
  -- real level, and guessing one would silently print a wrong maximum.
  if not level or level < 1 then return nil end

  local key = name .. ":" .. level
  local hit = V.cache[key]
  if hit then
    if hit.miss then return nil end
    return hit.health, hit.mana
  end

  local health, mana = V.Compute(name, level)

  -- Bounded: a session that targets thousands of distinct creatures drops the
  -- table rather than growing one entry per creature for the whole session.
  if V.cacheCount >= V.CACHE_LIMIT then
    V.cache = {}
    V.cacheCount = 0
  end
  V.cacheCount = V.cacheCount + 1

  if not health then
    V.cache[key] = { miss = true }
    return nil
  end

  V.cache[key] = { health = health, mana = mana }
  return health, mana
end

-- ---------------------------------------------------------------------------
-- Current health tracking
-- ---------------------------------------------------------------------------
function V.SyncFromPercent()
  local t = V.track
  if not t.key then return end

  local value = tonumber(V.Call("UnitHealth", "target"))
  local maximum = tonumber(V.Call("UnitHealthMax", "target"))
  if not value or not maximum or maximum <= 0 then return end

  t.current = U.Round(t.max * value / maximum)
end

-- force is a real target change reported by the client: the unit behind the
-- frame is new even when it is another creature of the same name and level, so
-- the accumulated value must not survive it. Without it this is the lazy
-- rebind a unit frame performs when its own identity disagrees with the live
-- target, and an unchanged key keeps what it has.
function V.ResetTarget(force)
  local t = V.track

  if not V.Enabled() then
    t.key, t.current, t.max = nil, nil, 0
    return
  end

  local name = V.Call("UnitName", "target")
  local level = tonumber(V.Call("UnitLevel", "target"))
  local maxHealth = nil
  if type(name) == "string" and level then
    maxHealth = V.Vitals(name, level)
  end

  if not maxHealth then
    t.key, t.current, t.max = nil, nil, 0
    return
  end

  -- Same creature as before, and not a real target change: keep the
  -- accumulated value. A unit frame calls this whenever the identity it last
  -- read disagrees with the live target, which happens for the fraction of a
  -- second between a target change and the frame's next full refresh -- long
  -- enough to throw the tracker away several times over if this reseeded on
  -- every call.
  local key = name .. ":" .. level
  if not force and t.key == key and t.current then return end

  t.key = key
  t.max = maxHealth
  t.current = nil
  V.SyncFromPercent()
end

function V.OnHealth(unit)
  if unit ~= "target" then return end

  local t = V.track
  if not t.key then return end
  if not t.current then
    V.SyncFromPercent()
    return
  end

  local value = tonumber(V.Call("UnitHealth", "target"))
  local maximum = tonumber(V.Call("UnitHealthMax", "target"))
  if not value or not maximum or maximum <= 0 then return end

  -- Full and empty carry no quantisation: they are the exact ends of the bar.
  if value >= maximum then t.current = t.max return end
  if value <= 0 then t.current = 0 return end

  -- Otherwise keep the tracked value only while it still agrees with the
  -- percentage, one percent of maximum either way. A value that has drifted
  -- outside that band has missed something the client did not report -- a heal
  -- from a unit out of range, another player's damage, a respawn -- and the
  -- percentage is then the better of the two answers.
  local low = t.max * (value - 1) / maximum
  local high = t.max * (value + 1) / maximum
  if t.current < low or t.current > high then
    t.current = U.Round(t.max * value / maximum)
  end
end

-- UNIT_COMBAT(unit, action, modifier, amount, school).
--
-- query_compat.py returns no match for this event on this client, in either
-- direction. It is carried over from UnrealPfUI's libs/libhealth.lua, which
-- drives its entire mob-health estimator from exactly these arguments on this
-- same client: WORKING_SOURCE, not runtime verification. Everything here is
-- additive, so if the event never arrives the readout is simply the percentage
-- estimate seeded by SyncFromPercent, which is correct to one percent.
function V.OnCombat(unit, action, modifier, amount)
  if unit ~= "target" then return end

  local t = V.track
  if not t.key or not t.current then return end

  amount = tonumber(amount)
  if not amount or amount <= 0 then return end

  if action == "HEAL" then
    t.current = t.current + amount
  elseif action == "WOUND" then
    t.current = t.current - amount
  else
    -- MISS, DODGE, PARRY, BLOCK, RESIST, ABSORB and anything this client adds
    -- carry no health change worth applying.
    return
  end

  if t.current < 0 then t.current = 0 end
  if t.current > t.max then t.current = t.max end
  t.sawCombat = true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
-- Absolute health for a unit whose client reading is a percentage.
--
--   unit      the unit id the frame is drawing
--   name      UnitName(unit)      -- the frame already read both, and reading
--   level     UnitLevel(unit)        them again here would double the cost
--   value     UnitHealth(unit)
--   maximum   UnitHealthMax(unit)
--
-- Returns currentHealth, maxHealth, maxMana, or nil when the creature is not
-- in the bundled table (players, pets, and the twelve templates VMaNGOS itself
-- cannot resolve from creature_classlevelstats).
function U.UnitVitalsHealth(unit, name, level, value, maximum)
  if not V.Enabled() then return nil end

  local maxHealth, maxMana = V.Vitals(name, level)
  if not maxHealth then return nil end

  -- The target's tracked value is the refined one. Rebinding here as well as
  -- on PLAYER_TARGET_CHANGED is what lets the tracker start working for a
  -- target that was already selected when the name index finished building.
  if unit == "target" then
    local key = name .. ":" .. level
    if V.track.key ~= key then V.ResetTarget() end
    if V.track.key == key and V.track.current then
      return V.track.current, maxHealth, maxMana
    end
  end

  if not maximum or maximum <= 0 then return 0, maxHealth, maxMana end
  return U.Round(maxHealth * value / maximum), maxHealth, maxMana
end

-- Absolute mana, on the same contract. powerType is the client's own
-- UnitPowerType: only mana (0) is answered, per the note on V.Compute.
function U.UnitVitalsPower(name, level, powerType, value, maximum)
  if not V.Enabled() then return nil end
  if powerType ~= 0 then return nil end

  local _, maxMana = V.Vitals(name, level)
  if not maxMana or maxMana <= 0 then return nil end

  if not maximum or maximum <= 0 then return 0, maxMana end
  return U.Round(maxMana * value / maximum), maxMana
end

-- /uui check surface: what the feature actually resolved, rather than whether
-- it is switched on.
function U.UnitVitalsReport()
  local report = {
    enabled = V.Enabled(),
    data = V.Data() ~= nil,
    names = V.NameTable() ~= nil,
    indexed = V.indexDone and V.index ~= nil,
    cached = V.cacheCount,
    trackKey = V.track.key,
    trackCurrent = V.track.current,
    trackMax = V.track.max,
    sawCombat = V.track.sawCombat,
  }
  return report
end

function V:OnEnable()
  -- The index is the expensive part and is built only for a session that
  -- wants it; the handlers below are registered either way, so the settings
  -- toggle takes effect without a reload. Each of them leaves immediately
  -- while there is no tracked target, which is the state a disabled feature
  -- keeps them in.
  if V.Enabled() then V.StartIndex() end

  U.RegisterEvent("PLAYER_TARGET_CHANGED", function() V.ResetTarget(true) end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() V.ResetTarget(true) end)
  U.RegisterEvent("UNIT_HEALTH", function(event, a1) V.OnHealth(a1) end)
  U.RegisterEvent("UNIT_COMBAT", function(event, a1, a2, a3, a4)
    V.OnCombat(a1, a2, a3, a4)
  end)
end
