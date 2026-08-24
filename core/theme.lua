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

-- This must use the loaded style, rather than the saved preference: selecting
-- a theme takes effect only after reload, and stock-window adapters need to
-- follow the style that was actually applied during this session.
function U.ThemeStyleUsesNativeChrome()
  local style = styles[U.GetActiveThemeStyle()]
  return style and style.nativeChrome or false
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
