-- unrealUI :: core/config.lua
--
-- Defaults, SavedVariables load/validate, and the shared position store used by
-- the mover system.
--
-- knowledge.json / config.savedvariables_backslash_corruption: this client's
-- SavedVariables writer does not escape backslashes safely. A stored path can
-- return with lost separators, and a backslash sequence can come back as a
-- control character. unrealUI's answer is to never persist a path at all:
-- config holds numbers, booleans, short identifiers and anchor names only, and
-- every real media path is rebuilt from core/media.lua at runtime.
--
-- The load path still validates defensively, because a corrupted or
-- hand-edited saved file must not be able to break the addon's bootstrap.

local U = UnrealUI

local CONFIG_VERSION = 1

-- Anchor points are the only strings unrealUI persists. Whitelisting them means
-- a corrupted value is rejected rather than fed to SetPoint.
local VALID_POINTS = {
  TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local defaults = {
  version   = CONFIG_VERSION,
  debug     = false,
  locked    = true,     -- mover mode state; see core/mover.lua
  positions = {},       -- mover id -> { point, relativePoint, x, y }
  modules   = {},       -- module name -> { enabled = true }
}

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

-- Rejects any string that could have been mangled by the SavedVariables
-- writer. unrealUI has no legitimate reason to persist one.
local function IsSafeString(value)
  if type(value) ~= "string" then return false end
  if string.find(value, "\\", 1, true) then return false end
  if string.find(value, "%c") then return false end
  return true
end

local function IsValidPosition(pos)
  if type(pos) ~= "table" then return false end
  if not VALID_POINTS[pos.point] then return false end
  if pos.relativePoint ~= nil and not VALID_POINTS[pos.relativePoint] then
    return false
  end
  if type(pos.x) ~= "number" or type(pos.y) ~= "number" then return false end
  -- A position far outside any plausible screen is treated as corrupt so the
  -- frame falls back to its default instead of vanishing off-screen.
  if math.abs(pos.x) > 10000 or math.abs(pos.y) > 10000 then return false end
  return true
end

-- Fills in anything missing and replaces anything whose type does not match the
-- default. Free-form subtables (positions, modules) are validated by their own
-- rules below rather than against a fixed shape.
local function ApplyDefaults(stored, template)
  if type(stored) ~= "table" then stored = {} end

  local key, value
  for key, value in pairs(template) do
    if type(value) == "table" then
      stored[key] = ApplyDefaults(stored[key], value)
    elseif type(stored[key]) ~= type(value) then
      stored[key] = value
    elseif type(stored[key]) == "string" and not IsSafeString(stored[key]) then
      stored[key] = value
    end
  end

  return stored
end

local function SanitizePositions(positions)
  if type(positions) ~= "table" then return {} end

  local clean = {}
  local id, pos
  for id, pos in pairs(positions) do
    if IsSafeString(id) and IsValidPosition(pos) then
      clean[id] = {
        point = pos.point,
        relativePoint = pos.relativePoint or pos.point,
        x = pos.x,
        y = pos.y,
      }
    else
      U.Debug("dropped invalid stored position: " .. tostring(id))
    end
  end
  return clean
end

local function SanitizeModules(modules)
  if type(modules) ~= "table" then return {} end

  local clean = {}
  local name, settings
  for name, settings in pairs(modules) do
    if IsSafeString(name) and type(settings) == "table" then
      local entry, key, value = {}, nil, nil
      for key, value in pairs(settings) do
        local t = type(value)
        if t == "number" or t == "boolean" then
          entry[key] = value
        elseif t == "string" and IsSafeString(value) then
          entry[key] = value
        end
      end
      clean[name] = entry
    end
  end
  return clean
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
function U.LoadConfig()
  if type(UnrealUIDB) ~= "table" then UnrealUIDB = {} end

  local db = ApplyDefaults(UnrealUIDB, defaults)
  db.positions = SanitizePositions(db.positions)
  db.modules = SanitizeModules(db.modules)

  if db.version ~= CONFIG_VERSION then
    -- No migrations exist yet; 0.0.1 is the first stored shape. Record the
    -- version so a future migration has a real starting point.
    U.Debug("config version " .. tostring(db.version) ..
            " -> " .. tostring(CONFIG_VERSION))
    db.version = CONFIG_VERSION
  end

  UnrealUIDB = db
  U.db = db
  return db
end

-- ---------------------------------------------------------------------------
-- Module settings
-- ---------------------------------------------------------------------------

-- Returns the module's settings table, creating it from the supplied defaults
-- on first use. Modules own their own defaults so core does not accumulate a
-- central schema for every feature.
function U.ModuleConfig(name, moduleDefaults)
  if not U.db then return moduleDefaults or {} end

  if type(U.db.modules[name]) ~= "table" then
    U.db.modules[name] = {}
  end

  local settings = U.db.modules[name]
  if type(moduleDefaults) == "table" then
    local key, value
    for key, value in pairs(moduleDefaults) do
      if type(settings[key]) ~= type(value) then
        settings[key] = value
      end
    end
  end

  return settings
end

-- ---------------------------------------------------------------------------
-- Position store
--
-- Positions are always relative to UIParent, so nothing here has to persist a
-- frame reference or a generated frame name.
-- ---------------------------------------------------------------------------
function U.SavePosition(id, point, relativePoint, x, y)
  if not U.db or not IsSafeString(id) then return false end

  local pos = {
    point = point,
    relativePoint = relativePoint or point,
    x = U.Round(x),
    y = U.Round(y),
  }

  if not IsValidPosition(pos) then
    U.Debug("refused to save invalid position for " .. tostring(id))
    return false
  end

  U.db.positions[id] = pos
  return true
end

function U.GetPosition(id)
  if not U.db or type(id) ~= "string" then return nil end
  return U.db.positions[id]
end

function U.ClearAllPositions()
  if not U.db then return end
  U.db.positions = {}
end
