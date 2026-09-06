-- unrealUI :: core/unitframestyle.lua
--
-- Unit-frame style registry and persisted selection.
--
-- A theme (core/theme.lua) decides which interface UnrealUI draws at all; a
-- unit-frame style decides how UnrealUI's *own* unit frames look once it draws
-- them. The two are deliberately separate: Classic WoW hands the unit frames
-- to the client, so there is nothing for a style to restyle there, and the
-- selector only applies under the Modern theme.
--
-- Styles are kept apart rather than blended. Each one is a complete
-- implementation of the frames under its own id; nothing reads a style flag to
-- toggle individual details. Modules that need to branch read
-- U.GetActiveUnitFrameStyle() once, so a new style is added by implementing it
-- behind that single seam instead of by threading conditionals through the
-- unit-frame module.
--
-- Selection is reload-bound for the same reason a theme change is: the frames
-- own their textures, sizes and anchors from build time, so switching the
-- stored id alone would leave a half-converted interface on screen.

local U = UnrealUI

local FALLBACK_STYLE = "minimal"

-- The style selector describes UnrealUI's own unit-frame implementation, so it
-- is meaningful only under the theme that actually draws it.
local STYLE_THEME = "modern"

-- The same "unitframes" store the party and colour settings use.
-- U.ModuleConfig only fills in the keys of the defaults table it is handed, so
-- these views never overwrite each other.
local DEFAULTS = { unitFrameStyle = FALLBACK_STYLE }

local styles = {}
local styleOrder = {}

local function Config()
  return U.ModuleConfig("unitframes", DEFAULTS)
end

function U.RegisterUnitFrameStyle(id, definition)
  if type(id) ~= "string" or id == "" or type(definition) ~= "table" then
    U.Error("RegisterUnitFrameStyle requires an id and definition")
    return nil
  end
  if styles[id] then
    U.Error("unit frame style already registered: " .. id)
    return styles[id]
  end

  local style = {
    id = id,
    label = definition.label or id,
    available = definition.available and true or false,
    wip = definition.wip and true or false,
  }
  styles[id] = style
  table.insert(styleOrder, style)
  return style
end

function U.GetUnitFrameStyles()
  return styleOrder
end

function U.GetUnitFrameStyleDefinition(id)
  return styles[id]
end

function U.GetUnitFrameStyleLabel(id)
  local style = styles[id]
  return style and style.label or tostring(id or "")
end

-- The stored preference, which is what the settings selector shows.
function U.GetUnitFrameStyle()
  local stored = Config().unitFrameStyle
  if styles[stored] and styles[stored].available then return stored end
  return FALLBACK_STYLE
end

-- The style the frames on screen were actually built with. Modules branch on
-- this one, never on the preference: the preference can already name the style
-- the player picked for the next session.
function U.GetActiveUnitFrameStyle()
  return U.activeUnitFrameStyle or FALLBACK_STYLE
end

function U.UnitFrameStyleRequiresReload()
  return U.GetUnitFrameStyle() ~= U.GetActiveUnitFrameStyle()
end

-- Whether the loaded theme draws UnrealUI's own unit frames at all. Follows the
-- active theme rather than the stored one, because a theme change is itself
-- reload-bound and the frames on screen still belong to the loaded theme.
function U.ThemeSupportsUnitFrameStyles()
  if type(U.GetActiveThemeStyle) ~= "function" then return false end
  return U.GetActiveThemeStyle() == STYLE_THEME
end

-- Whether the settings selector is worth showing at all. A selector offering
-- one usable entry is dead UI: it states a choice the player cannot make. So
-- the section stays hidden while Enhanced is still work in progress, and comes
-- back on its own the day a second style registers as available -- no flag to
-- remember to clear, and nothing to re-wire.
--
-- Counted rather than hardcoded to two: the rule is "more than one style can
-- actually be selected", whatever the registry ends up holding.
function U.UnitFrameStyleSelectable()
  if not U.ThemeSupportsUnitFrameStyles() then return false end

  local available, i = 0, nil
  for i = 1, table.getn(styleOrder) do
    if styleOrder[i].available then
      available = available + 1
      if available > 1 then return true end
    end
  end
  return false
end

function U.SetUnitFrameStyle(id)
  local style = styles[id]
  if not U.db or not style or not style.available then return false end
  Config().unitFrameStyle = id
  return true
end

-- Resolves the style for this session. Runs from core/init.lua after the config
-- is readable and before any module builds a frame.
function U.LoadUnitFrameStyle()
  local id = U.GetUnitFrameStyle()
  if not styles[id] or not styles[id].available then id = FALLBACK_STYLE end
  if U.db then Config().unitFrameStyle = id end
  U.activeUnitFrameStyle = id
  return id
end

-- ---------------------------------------------------------------------------
-- Styles
--
-- One registration per style, and nothing else. A style that grows an
-- implementation gets its own module rather than a branch inside another one.
-- ---------------------------------------------------------------------------

-- Minimal -- the shipped UnrealUI unit frames: flat, compact, near-black bars
-- with the addon's own outline, as drawn by modules/unitframes.lua today.
U.RegisterUnitFrameStyle("minimal", {
  label = "Minimal",
  available = true,
})

-- Enhanced -- a fuller unit-frame treatment. Registered so the selector states
-- that it is planned, and unavailable until its implementation is complete, on
-- the same terms as the WIP theme entry.
U.RegisterUnitFrameStyle("enhanced", {
  label = "Enhanced",
  available = false,
  wip = true,
})
