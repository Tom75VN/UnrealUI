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

local CONFIG_VERSION = 4
local PROFILE_STORE_VERSION = 1
local MAX_PROFILE_NAME = 64

-- Anchor points are the only persisted strings that are passed to SetPoint.
-- Whitelisting them means a corrupted value is rejected before it reaches the
-- frame API. Other stored strings are short identifiers validated by their
-- owning subsystem (for example core/theme.lua).
local VALID_POINTS = {
  TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local defaults = {
  version   = CONFIG_VERSION,
  debug     = false,
  themeStyle = "modern",
  -- Stable media ids only. core/media.lua reconstructs the bundled paths so
  -- the client's unsafe SavedVariables backslash handling never sees them.
  defaultFont = U.media.defaultFontId,
  unitFrameFont = U.media.defaultUnitFrameFontId,
  -- Diagnostic only, set by /uui nosuppress. core/compat.lua's native-frame
  -- suppression is applied once at OnEnable and is irreversible within a
  -- session -- Show is replaced by a no-op whose original is not kept, and
  -- UnregisterAllEvents cannot be undone -- so the only way to measure
  -- unrealUI *without* it is to skip it at load. Persisted because the skip
  -- has to survive the /reload that applies it.
  noSuppress = false,
  -- Diagnostic bisect of the suppression *recipe*, not just on/off. Measured:
  -- the recipe's permanent state costs +2.66ms/frame (142 -> 103fps) and turns
  -- a 9ms target-change peak into 159ms, while its periodic sweep only costs a
  -- further +1.55ms. So the expensive part is what is done to the ~1275 stock
  -- objects, and this picks how much of it to do:
  --   0  nothing (same as noSuppress)
  --   1  Hide() only
  --   2  + SetAlpha(0)
  --   3  + EnableMouse(false) and the Show() neutraliser
  --   4  + UnregisterAllEvents and the periodic/event re-apply  (shipped behaviour)
  -- A number, not a string: knowledge.json / config.savedvariables_backslash
  -- _corruption means only numbers and booleans are safe to persist here.
  suppressLevel = 4,
  locked    = true,     -- mover mode state; see core/mover.lua
  positions = {},       -- mover id -> { point, relativePoint, x, y }
  modules   = {},       -- module name -> { enabled = true }
}

-- Profiles live account-wide so any character can select them. Only the
-- active profile name is character-scoped (UnrealUIProfileDB in the TOC).
-- UnrealUIDB remains declared account-wide as a read-only migration source
-- for installations that predate profiles; new settings are written only to
-- UnrealUIProfiles.profiles[activeName].
local profiles
local assignments
local characterKey

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

local function IsSafeProfileName(value)
  if not IsSafeString(value) or value == "" then return false end
  if string.len(value) > MAX_PROFILE_NAME then return false end
  -- Profile names are rendered in labels and chat. Keep colour escapes and
  -- punctuation with UI meaning out of that path while allowing the names,
  -- spaces, hyphens and underscores used by character/realm identifiers.
  if string.find(value, "[^%w%s%-%_]") then return false end
  return true
end

-- A stored language is only ever one of the codes core/locale.lua registered.
-- U.IsValidLanguage is the authority; the IsSafeString check in front of it
-- keeps a mangled value from being compared at all.
local function IsSafeLanguage(value)
  if not IsSafeString(value) then return false end
  if type(U.IsValidLanguage) ~= "function" then return false end
  return U.IsValidLanguage(value) and true or false
end

local function CopyTable(source, seen)
  if type(source) ~= "table" then return source end
  seen = seen or {}
  if seen[source] then return seen[source] end

  local copy = {}
  seen[source] = copy
  local key, value
  for key, value in pairs(source) do
    copy[CopyTable(key, seen)] = CopyTable(value, seen)
  end
  return copy
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

local function SanitizeScalar(target, key, value)
  local t = type(value)
  if t == "number" or t == "boolean" then
    target[key] = value
    return true
  elseif t == "string" and IsSafeString(value) then
    target[key] = value
    return true
  end
  return false
end

-- One level of nesting inside a module's settings.
--
-- Module settings used to be scalars only, and every nested table was dropped
-- silently on load. That is what made the Quest Log's remembered tracked-quest
-- titles (questlog.trackedQuests) reset on every /reload: the module wrote them,
-- the writer stored them, and this sanitizer deleted them on the way back in.
--
-- Nested keys are validated, not just values: unlike a module's own scalar keys,
-- which are identifiers written in unrealUI source, these keys are game data
-- (quest titles) and so are exactly the sort of string
-- config.savedvariables_backslash_corruption warns about. Entries are capped so
-- a module cannot grow the saved file without bound, and nesting stops at one
-- level so this stays a set/lookup store rather than an arbitrary object graph.
local MAX_MODULE_TABLE_ENTRIES = 200

local function SanitizeModuleTable(source)
  local clean, count, key, value = {}, 0, nil, nil
  for key, value in pairs(source) do
    if count >= MAX_MODULE_TABLE_ENTRIES then break end
    local keyOk = type(key) == "number" or
                  (type(key) == "string" and IsSafeString(key))
    if keyOk and SanitizeScalar(clean, key, value) then
      count = count + 1
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
        if type(value) == "table" then
          entry[key] = SanitizeModuleTable(value)
        else
          SanitizeScalar(entry, key, value)
        end
      end
      clean[name] = entry
    end
  end
  return clean
end

local function PrepareConfig(stored)
  local storedVersion = type(stored) == "table" and
                        tonumber(stored.version) or 0
  local db = ApplyDefaults(stored, defaults)
  db.positions = SanitizePositions(db.positions)
  db.modules = SanitizeModules(db.modules)

  -- Version 2 introduced bundled-font selection with PT Sans Narrow as the
  -- automatic default. USER_CONFIRMED_INGAME: that made all UnrealUI text
  -- disappear. Force every existing profile back to the inherited native font
  -- once; custom faces remain explicit choices for the focused probe work.
  if storedVersion < 3 then db.defaultFont = U.media.defaultFontId end
  -- Version 3 still selected Homespun automatically for unit/party frames.
  -- Keep those native too until the same probe establishes a safe path.
  if storedVersion < 4 then db.unitFrameFont = U.media.defaultUnitFrameFontId end

  if db.version ~= CONFIG_VERSION then
    U.Debug("config version " .. tostring(db.version) ..
            " -> " .. tostring(CONFIG_VERSION))
    db.version = CONFIG_VERSION
  end
  return db
end

local function CharacterProfileName()
  -- UnitName/GetRealmName are documented by this client and used by the
  -- installed UnrealPfUI build. Keep the calls protected because LoadConfig
  -- can also be reached by the bootstrap fallback before PLAYER_LOGIN.
  local name, realm
  if type(UnitName) == "function" then
    local ok, value = pcall(UnitName, "player")
    if ok and type(value) == "string" and value ~= "" then name = value end
  end
  if type(GetRealmName) == "function" then
    local ok, value = pcall(GetRealmName)
    if ok and type(value) == "string" and value ~= "" then realm = value end
  end

  local candidate
  if name and realm then
    candidate = name .. " - " .. realm
  elseif name then
    candidate = name
  else
    candidate = "Character Profile"
  end
  if IsSafeProfileName(candidate) then return candidate end
  return "Character Profile"
end

local function SortedProfileNames(exclude)
  local names, name = {}, nil
  if type(profiles) ~= "table" then return names end
  for name in pairs(profiles) do
    if name ~= exclude then table.insert(names, name) end
  end
  table.sort(names)
  return names
end

local function SetActiveProfile(name)
  if type(profiles) ~= "table" or not IsSafeProfileName(name) or
     type(profiles[name]) ~= "table" then
    return false
  end
  UnrealUIProfileDB.active = name
  if type(assignments) == "table" and IsSafeProfileName(characterKey) then
    assignments[characterKey] = name
  end
  U.profileDB = UnrealUIProfileDB
  U.db = profiles[name]
  return true
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
function U.LoadConfig()
  if type(UnrealUIDB) ~= "table" then UnrealUIDB = {} end
  if type(UnrealUIProfiles) ~= "table" then UnrealUIProfiles = {} end
  if type(UnrealUIProfileDB) ~= "table" then UnrealUIProfileDB = {} end

  local storedProfiles = UnrealUIProfiles.profiles
  if type(storedProfiles) ~= "table" then storedProfiles = {} end
  local storedAssignments = UnrealUIProfiles.assignments
  if type(storedAssignments) ~= "table" then storedAssignments = {} end

  profiles = {}
  local name, stored
  for name, stored in pairs(storedProfiles) do
    if IsSafeProfileName(name) and type(stored) == "table" then
      profiles[name] = PrepareConfig(CopyTable(stored))
    end
  end

  assignments = {}
  local assignedProfile
  for name, assignedProfile in pairs(storedAssignments) do
    if IsSafeProfileName(name) and IsSafeProfileName(assignedProfile) and
       type(profiles[assignedProfile]) == "table" then
      assignments[name] = assignedProfile
    end
  end

  characterKey = CharacterProfileName()
  local active = UnrealUIProfileDB.active
  if not IsSafeProfileName(active) or type(profiles[active]) ~= "table" then
    active = characterKey
    if type(profiles[active]) ~= "table" then
      -- Each character receives an independent copy of the old shared config
      -- on first load. The old UnrealUIDB is kept untouched as a migration
      -- backup and is no longer the live settings table.
      profiles[active] = PrepareConfig(CopyTable(UnrealUIDB))
    end
  end

  -- The language is account-wide, not part of a profile: switching profile is
  -- a layout decision and must not change what language the interface is in.
  -- It therefore has to survive this wholesale rebuild of the store.
  local storedLanguage = UnrealUIProfiles.language

  UnrealUIProfiles = {
    version = PROFILE_STORE_VERSION,
    profiles = profiles,
    assignments = assignments,
    language = IsSafeLanguage(storedLanguage) and storedLanguage or nil,
  }
  SetActiveProfile(active)
  return U.db
end

-- ---------------------------------------------------------------------------
-- Language
--
-- core/locale.lua owns the lookup; this owns where the choice is kept. Only
-- the four-letter code is persisted, and it is checked against the registered
-- languages on the way in and on the way out, so a corrupted or hand-edited
-- value falls back to English instead of reaching a lookup as a bad key
-- (knowledge.json / config.savedvariables_backslash_corruption).
-- ---------------------------------------------------------------------------
function U.StoredLanguage()
  if type(UnrealUIProfiles) ~= "table" then return nil end
  local code = UnrealUIProfiles.language
  if IsSafeLanguage(code) then return code end
  return nil
end

function U.StoreLanguage(code)
  if not IsSafeLanguage(code) then return false end
  if type(UnrealUIProfiles) ~= "table" then UnrealUIProfiles = {} end
  UnrealUIProfiles.language = code
  return true
end

-- ---------------------------------------------------------------------------
-- Shared profiles
-- ---------------------------------------------------------------------------

function U.GetCurrentProfileName()
  return U.profileDB and U.profileDB.active or ""
end

function U.GetProfileNames(excludeCurrent)
  return SortedProfileNames(excludeCurrent and U.GetCurrentProfileName() or nil)
end

function U.GetDeletableProfileNames()
  local names, result = SortedProfileNames(U.GetCurrentProfileName()), {}
  local i, key, used
  for i = 1, table.getn(names) do
    used = false
    for key in pairs(assignments or {}) do
      if assignments[key] == names[i] then used = true end
    end
    if not used then table.insert(result, names[i]) end
  end
  return result
end

function U.SelectProfile(name)
  return SetActiveProfile(name)
end

function U.CopyProfile(sourceName)
  local current = U.GetCurrentProfileName()
  if not IsSafeProfileName(current) or type(profiles[sourceName]) ~= "table" then
    return false
  end
  profiles[current] = PrepareConfig(CopyTable(profiles[sourceName]))
  return SetActiveProfile(current)
end

function U.ResetCurrentProfile()
  local current = U.GetCurrentProfileName()
  if not IsSafeProfileName(current) then return false end
  profiles[current] = PrepareConfig({})
  return SetActiveProfile(current)
end

function U.DeleteProfile(name)
  if not IsSafeProfileName(name) or name == U.GetCurrentProfileName() then
    return false
  end
  if type(profiles[name]) ~= "table" then return false end
  local key
  for key in pairs(assignments or {}) do
    if assignments[key] == name then return false end
  end
  profiles[name] = nil
  return true
end

function U.CreateProfile(name)
  if not IsSafeProfileName(name) then return false, "invalid" end
  if type(profiles[name]) == "table" then return false, "exists" end
  profiles[name] = PrepareConfig(CopyTable(U.db or {}))
  SetActiveProfile(name)
  return true
end

function U.NextProfileName()
  local base = U.GetCurrentProfileName()
  if not IsSafeProfileName(base) then base = "New Profile" end
  base = base .. " Copy"
  if type(profiles[base]) ~= "table" and string.len(base) <= MAX_PROFILE_NAME then
    return base
  end

  local index = 2
  while index < 100 do
    local suffix = " " .. tostring(index)
    local shortBase = string.sub(base, 1, MAX_PROFILE_NAME - string.len(suffix))
    local candidate = shortBase .. suffix
    if type(profiles[candidate]) ~= "table" then return candidate end
    index = index + 1
  end
  return nil
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
