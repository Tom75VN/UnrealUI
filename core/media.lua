-- unrealUI :: core/media.lua
--
-- Fonts, textures and colours. Pure code constants, deliberately never written
-- to SavedVariables.
--
-- knowledge.json / config.savedvariables_backslash_corruption: this client's
-- SavedVariables writer does not escape backslashes safely, so a stored asset
-- path can come back with lost separators or control characters after a
-- reload. unrealUI persists short media *ids* only (see core/config.lua) and
-- rebuilds every real path from this table at runtime.

local U = UnrealUI

U.media = {}
local M = U.media

-- ---------------------------------------------------------------------------
-- Fonts
--
-- behavior.json / fonts.pfui_path_and_measure.v1 is BROKEN with confidence
-- RUNTIME_FAILURE_CONFIRMED: a request for a bundled addon TTF at size 12
-- OUTLINE read back as GameFontNormal / 12 / NONE. unrealUI therefore ships no
-- font of its own and uses stock client fonts, which core/compat.lua verifies
-- by measurement before trusting.
-- ---------------------------------------------------------------------------
M.fontCandidates = {
  "Fonts\\FRIZQT__.TTF",
  "Fonts\\ARIALN.TTF",
  "Fonts\\MORPHEUS.TTF",
  "Fonts\\SKURRI.TTF",
}

M.fontSize = {
  tiny   = 9,
  small  = 10,
  normal = 11,
  large  = 13,
}

-- ---------------------------------------------------------------------------
-- Textures
--
-- behavior.json / textures.pfui_bar_path.v1 (SUPPORTED, BEHAVIOR_VERIFIED)
-- confirms plain textures are a reliable drawing path on this client. A flat
-- WHITE8X8 fill tinted with SetVertexColor gives the clean pfUI-modern bar and
-- panel look without shipping binary media, and keeps unrealUI off the
-- backdrop-edge path that is known not to rasterise (see core/style.lua).
-- ---------------------------------------------------------------------------
M.texture = {
  plain = "Interface\\BUTTONS\\WHITE8X8",
  chatResizeGrip = "Interface\\AddOns\\unrealUI\\media\\chat_resize_grip",
}

-- ---------------------------------------------------------------------------
-- Colours
--
-- pfUI modern baseline: near-black panels, a single thin dark outline, and
-- desaturated bar fills that let class colour carry the accent.
-- ---------------------------------------------------------------------------
--
-- The addon colour is #f5ae0a, a vibrant orange-yellow. It carries every
-- unrealUI accent: panel headings, the active item in the settings list,
-- checkbox fills, slider thumbs and the edit-mode handles. Bar fills and unit
-- colours stay as they are -- the accent marks unrealUI's own chrome, not game
-- state.
M.color = {
  background = { 0.06, 0.06, 0.06, 0.85 },
  border     = { 0.16, 0.16, 0.16, 1.00 },
  shadow     = { 0.00, 0.00, 0.00, 0.55 },

  -- #f5ae0a and two derived tones: one dimmed for inactive accents, one
  -- translucent for the fill behind a selected row.
  accent     = { 0.96, 0.68, 0.04, 1.00 },
  accentDim  = { 0.55, 0.39, 0.03, 1.00 },
  accentFill = { 0.96, 0.68, 0.04, 0.22 },

  text       = { 0.90, 0.90, 0.90, 1.00 },
  textDim    = { 0.60, 0.60, 0.60, 1.00 },
  textAccent = { 0.96, 0.68, 0.04, 1.00 },

  health     = { 0.25, 0.75, 0.30, 1.00 },
  healthBg   = { 0.10, 0.10, 0.10, 0.90 },

  -- pfUI modern's unitframe "custom" colour (profiles.lua, Modern profile:
  -- customcolor "0.1,0.1,0.1,1"). It is what a full-health bar fades to, which
  -- is the single most recognisable part of the modern unit frame look.
  healthFull = { 0.10, 0.10, 0.10, 1.00 },

  -- Castbar fill. Distinct from the accent so a cast in progress reads as game
  -- state, not chrome, and distinct from the health/power colours so it never
  -- looks like a third unit-frame bar.
  cast       = { 0.20, 0.55, 0.65, 1.00 },

  highlight  = { 0.96, 0.68, 0.04, 0.22 },
  mover      = { 0.55, 0.36, 0.02, 0.45 },
  moverEdge  = { 0.96, 0.68, 0.04, 1.00 },
  grid       = { 0.45, 0.45, 0.45, 0.30 },
  gridAxis   = { 0.96, 0.68, 0.04, 0.55 },
}

-- Power colours keyed by the numeric UnitPowerType index used by Vanilla.
-- The unit API contract is still INCONCLUSIVE in the compact evidence
-- (knowledge.json / unitframes.core_unit_api_contract_partial), so consumers
-- must fall back rather than assume an index is present.
--
-- Values are pfUI modern's, taken from its Modern profile rather than from
-- pfUI's brighter stock defaults: manacolor "0.2,0.2,0.4", ragecolor
-- "0.6,0.2,0.2", energycolor and focuscolor "0.6,0.4,0.2".
M.power = {
  [0] = { 0.20, 0.20, 0.40, 1.00 },   -- mana
  [1] = { 0.60, 0.20, 0.20, 1.00 },   -- rage
  [2] = { 0.60, 0.40, 0.20, 1.00 },   -- focus
  [3] = { 0.60, 0.40, 0.20, 1.00 },   -- energy
  fallback = { 0.40, 0.40, 0.40, 1.00 },
}

-- Vanilla's UnitReactionColor, used to tint a non-player unit's name. The stock
-- global is preferred when the client provides one; see M.ReactionColor.
M.reaction = {
  [1] = { 1.00, 0.00, 0.00 },
  [2] = { 1.00, 0.00, 0.00 },
  [3] = { 1.00, 0.50, 0.00 },
  [4] = { 1.00, 1.00, 0.00 },
  [5] = { 0.00, 1.00, 0.00 },
  [6] = { 0.00, 1.00, 0.00 },
  [7] = { 0.00, 1.00, 0.00 },
  [8] = { 0.00, 1.00, 0.00 },
}

function M.ReactionColor(index)
  index = tonumber(index)
  if not index then return nil end

  local stock = U.G("UnitReactionColor")
  if type(stock) == "table" and type(stock[index]) == "table" then
    local c = stock[index]
    if tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then
      return tonumber(c.r), tonumber(c.g), tonumber(c.b)
    end
  end

  local own = M.reaction[index]
  if own then return own[1], own[2], own[3] end
  return nil
end

-- Vanilla class colours. RAID_CLASS_COLORS is used when the client provides it,
-- but existence is not assumed.
M.class = {
  WARRIOR = { 0.78, 0.61, 0.43 },
  MAGE    = { 0.41, 0.80, 0.94 },
  ROGUE   = { 1.00, 0.96, 0.41 },
  DRUID   = { 1.00, 0.49, 0.04 },
  HUNTER  = { 0.67, 0.83, 0.45 },
  SHAMAN  = { 0.14, 0.35, 1.00 },
  PRIEST  = { 1.00, 1.00, 1.00 },
  WARLOCK = { 0.58, 0.51, 0.79 },
  PALADIN = { 0.96, 0.55, 0.73 },
}

function M.ClassColor(class)
  if type(class) ~= "string" then return nil end
  local key = string.upper(class)

  local stock = U.G("RAID_CLASS_COLORS")
  if type(stock) == "table" and type(stock[key]) == "table" then
    local c = stock[key]
    if tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then
      return tonumber(c.r), tonumber(c.g), tonumber(c.b)
    end
  end

  local own = M.class[key]
  if own then return own[1], own[2], own[3] end
  return nil
end

-- Unpacks a colour table into plain numbers. SetVertexColor does not coerce, so
-- everything that reaches a texture goes through a numeric path.
function M.Unpack(color, fallbackAlpha)
  if type(color) ~= "table" then return 1, 1, 1, 1 end
  return tonumber(color[1]) or 0,
         tonumber(color[2]) or 0,
         tonumber(color[3]) or 0,
         tonumber(color[4]) or fallbackAlpha or 1
end
