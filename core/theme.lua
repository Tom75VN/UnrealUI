-- unrealUI :: core/theme.lua
--
-- Theme-style registry and persisted selection. Theme files register in TOC
-- order and apply their shared media tokens before modules create their UI.
-- A theme change is intentionally reload-bound: existing frames own tinted
-- textures and font colours, so changing only the token table live would leave
-- a mixed interface. Future themes only need to register an apply callback and
-- opt into availability once their complete visual implementation exists.
-- Apply callbacks must mutate existing media token tables in place rather than
-- replacing them, because modules may retain a reference to an individual
-- shared token table from file-load time.

local U = UnrealUI

local FALLBACK_STYLE = "modern"
local styles = {}
local styleOrder = {}

-- Classic WoW can selectively hand individual surfaces to Modern WoW while
-- keeping every other part of the client-native interface intact. These are
-- profile settings and reload-bound for the same reason as the main theme:
-- each owning module chooses its complete drawing path during startup.
local classicModernModules = {
  { id = "unitframes",   labelKey = "CLASSIC_MODULE_UNIT_FRAMES" },
  { id = "partyframes",  labelKey = "CLASSIC_MODULE_PARTY_FRAMES" },
  { id = "actionbar",    labelKey = "CLASSIC_MODULE_ACTION_BARS" },
  { id = "minimap",      labelKey = "CLASSIC_MODULE_MINIMAP" },
  { id = "character",    labelKey = "CLASSIC_MODULE_CHARACTER" },
  { id = "spellbook",    labelKey = "CLASSIC_MODULE_SPELLBOOK" },
  { id = "talents",      labelKey = "CLASSIC_MODULE_TALENTS" },
  { id = "professions",  labelKey = "CLASSIC_MODULE_CRAFTING" },
  -- The Quest Log's Dragonflight design is its own module
  -- (modules/questlogdesign.lua), so selecting it here runs exactly the code
  -- `modern-wow` runs. On by default, like the bag family: switching it off is
  -- what restores modules/questlogextended.lua's parchment two-page log, which
  -- stands down for the session while this is on.
  { id = "questlog",     labelKey = "CLASSIC_MODULE_QUEST_LOG", default = true },
  -- Bag, bank and saved bank share one design (modules/bagdesign.lua). On by
  -- default: Classic uses it unless the player switches it off.
  { id = "bags",         labelKey = "CLASSIC_MODULE_BAGS", default = true },
  -- The corpse loot window's one design (modules/lootdesign.lua), same
  -- arrangement as the bag family: on by default, off restores the native
  -- window. modules/loot.lua's price and comparison readouts are behaviour and
  -- run either way.
  { id = "loot",         labelKey = "CLASSIC_MODULE_LOOT", default = true },
}
-- Bumped when a module's shipped default changes. U.ModuleConfig writes a
-- registration default into the profile the first time it is read, so a module
-- that shipped off and later became on-by-default would stay off forever for
-- anyone who ran the earlier build. Same trap, and the same one-time fix, as
-- the surface version bumps in modules/modernwow.lua.
local CLASSIC_MODERN_VERSION = 2

local classicModernDefaults = {}
local classicModernKnown = {}
local classicModernIndex
for classicModernIndex = 1, table.getn(classicModernModules) do
  local entry = classicModernModules[classicModernIndex]
  local id = entry.id
  classicModernDefaults[id] = entry.default and true or false
  classicModernKnown[id] = true
end

function U.RegisterThemeStyle(id, definition)
  if type(id) ~= "string" or id == "" or type(definition) ~= "table" then
    U.Error("RegisterThemeStyle requires an id and definition")
    return nil
  end
  if styles[id] then
    U.Error("theme style already registered: " .. id)
    return styles[id]
  end

  local style = {
    id = id,
    label = definition.label or id,
    available = definition.available and true or false,
    wip = definition.wip and true or false,
    -- Native chrome applies only to client-owned windows. UnrealUI modules
    -- still run so their features, movers and behaviour remain available.
    nativeChrome = definition.nativeChrome and true or false,
    apply = definition.apply,
  }
  styles[id] = style
  table.insert(styleOrder, style)
  return style
end

function U.GetThemeStyles()
  return styleOrder
end

function U.GetThemeStyleDefinition(id)
  return styles[id]
end

function U.GetThemeStyleLabel(id)
  local style = styles[id]
  return style and style.label or tostring(id or "")
end

function U.GetThemeStyle()
  if U.db and styles[U.db.themeStyle] and styles[U.db.themeStyle].available then
    return U.db.themeStyle
  end
  return FALLBACK_STYLE
end

function U.GetActiveThemeStyle()
  return U.activeThemeStyle or FALLBACK_STYLE
end

function U.GetClassicModernModules()
  return classicModernModules
end

-- The stored Classic choices, with the pending default migrations applied.
-- Guarded on U.db because U.ModuleConfig hands back the defaults table itself
-- before SavedVariables are readable, and a migration must never write into
-- that shared table.
local function ClassicModernConfig()
  if type(U.ModuleConfig) ~= "function" then return classicModernDefaults end
  local config = U.ModuleConfig("classicwow", classicModernDefaults)
  if U.db and (tonumber(config.version) or 1) < CLASSIC_MODERN_VERSION then
    -- The Quest Log's Dragonflight design shipped opt-in for one build before
    -- becoming the Classic default, so turn it on once for the profiles that
    -- stored that earlier default. A later explicit choice in Settings stands,
    -- because this runs once per profile.
    config.questlog = true
    config.version = CLASSIC_MODERN_VERSION
  end
  return config
end

function U.GetClassicModernModule(id)
  if not classicModernKnown[id] then return false end
  return ClassicModernConfig()[id] and true or false
end

function U.SetClassicModernModule(id, enabled)
  if not classicModernKnown[id] or type(U.ModuleConfig) ~= "function" then
    return false
  end
  ClassicModernConfig()[id] = enabled and true or false
  return true
end

-- Stored Classic choices never leak into another theme. The broader helper is
-- for complete Modern WoW drawing paths that are also valid as Classic module
-- overrides; it deliberately does not replace the per-surface readiness gate.
function U.ClassicModernModuleEnabled(id)
  return U.GetActiveThemeStyle() == "classic-wow" and
         U.GetClassicModernModule(id)
end

function U.ModernWowModuleEnabled(id)
  return U.GetActiveThemeStyle() == "modern-wow" or
         U.ClassicModernModuleEnabled(id)
end

function U.ClassicModernAnyEnabled()
  if U.GetActiveThemeStyle() ~= "classic-wow" then return false end
  local i
  for i = 1, table.getn(classicModernModules) do
    if U.GetClassicModernModule(classicModernModules[i].id) then return true end
  end
  return false
end

-- This must use the loaded style, rather than the saved preference: selecting
-- a theme takes effect only after reload, and stock-window adapters need to
-- follow the style that was actually applied during this session.
function U.ThemeStyleUsesNativeChrome()
  local style = styles[U.GetActiveThemeStyle()]
  return style and style.nativeChrome or false
end

-- Classic keeps the client's complete bottom action-bar assembly as one owned
-- surface: main buttons, page controls, end caps, XP/reputation track, micro
-- menu and bag buttons. Other themes let the individual UnrealUI modules build
-- replacements for those pieces.
function U.ThemeStyleUsesNativeMainMenuBar()
  return U.GetActiveThemeStyle() == "classic-wow"
end

-- Modern WoW deliberately keeps stock interaction windows on the same path
-- as classic-wow. Character, Quest Log and HUD surfaces still use the Modern
-- WoW theme, but NPC/service dialogs and the mailbox retain the client's own
-- complete chrome, controls and layout.
function U.ThemeStyleUsesClassicInteractionChrome()
  return U.ThemeStyleUsesNativeChrome() or
         U.GetActiveThemeStyle() == "modern-wow"
end

function U.ThemeStyleRequiresReload()
  return U.GetThemeStyle() ~= U.GetActiveThemeStyle()
end

function U.SetThemeStyle(id)
  local style = styles[id]
  if not U.db or not style or not style.available then return false end
  U.db.themeStyle = id
  return true
end

function U.LoadThemeStyle()
  local id = U.GetThemeStyle()
  local style = styles[id]

  if not style or not style.available then
    id = FALLBACK_STYLE
    style = styles[id]
  end
  if U.db then U.db.themeStyle = id end

  if not style then
    U.Error("the fallback theme style is not registered")
    U.activeThemeStyle = FALLBACK_STYLE
    return FALLBACK_STYLE
  end

  if type(style.apply) == "function" then
    local ok, err = pcall(style.apply, U.media)
    if not ok then
      U.Error("theme style " .. id .. ": " .. tostring(err))
      id = FALLBACK_STYLE
      style = styles[id]
      if U.db then U.db.themeStyle = id end
      if style and type(style.apply) == "function" then
        local fallbackOk, fallbackErr = pcall(style.apply, U.media)
        if not fallbackOk then
          U.Error("fallback theme style " .. id .. ": " ..
                  tostring(fallbackErr))
        end
      end
    end
  end

  U.activeThemeStyle = id
  return id
end
