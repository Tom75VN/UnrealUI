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
-- RUNTIME_FAILURE_CONFIRMED: assigning a bundled TTF directly to an inherited
-- FontString silently kept GameFontNormal. The client documentation records a
-- named-Font/SetFontObject route, but USER_CONFIRMED_INGAME: selecting a
-- bundled face through that route made UnrealUI text disappear. Keep the
-- inherited native FontObject as the safe default until a focused probe
-- establishes a working custom-font contract. core/compat.lua owns the
-- guarded experimental adapter used only when a bundled face is selected.
-- Only these short ids are persisted; asset paths never enter SavedVariables.
-- ---------------------------------------------------------------------------
M.defaultFontId = "original"
M.defaultUnitFrameFontId = "original"

M.fonts = {
  { id = "action_man",       label = "Action Man",       file = "ActionMan.ttf" },
  { id = "continuum_medium", label = "Continuum Medium", file = "ContinuumMedium.ttf" },
  { id = "die_die_die",      label = "Die Die Die",      file = "DieDieDie.ttf" },
  { id = "expressway",       label = "Expressway",       file = "Expressway.ttf" },
  { id = "homespun",         label = "Homespun",         file = "Homespun.ttf" },
  { id = "invisible",        label = "Invisible",        file = "Invisible.ttf" },
  { id = "pt_sans_narrow",   label = "PT Sans Narrow",   file = "PTSansNarrow.ttf" },
}

M.fontById = {}
local fontIndex
for fontIndex = 1, table.getn(M.fonts) do
  local font = M.fonts[fontIndex]
  font.path = "Interface\\AddOns\\unrealUI\\media\\Fonts\\" .. font.file
  M.fontById[font.id] = font
end

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

-- Desired physical-pixel offset for every UnrealUI-styled FontString. The
-- compatibility layer converts this into UIParent units before applying it,
-- since one UI unit is wider than one screen pixel on this client.
M.textShadowOffset = { 1, -1 }
-- Compact bar text uses a stronger three-quarter-pixel shadow for contrast
-- over bright semantic health and power fills without a detached appearance.
M.compactTextShadowOffset = { 0.75, -0.75 }

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
  statusBar = "Interface\\AddOns\\unrealUI\\media\\Textures\\normTex2",
  -- Official client documentation uses this native TargetingFrame texture as
  -- the StatusBar example; the Classic unit-frame theme reuses it directly.
  classicStatusBar = "Interface\\TargetingFrame\\UI-StatusBar",
  chatResizeGrip = "Interface\\AddOns\\unrealUI\\media\\resize",
  restIcon = "Interface\\AddOns\\unrealUI\\media\\rest-icon",
  -- Party-leader star. unrealUI's own art rather than the stock GroupFrame
  -- leader icon: knowledge.json / textures.separate_coin_paths_not_rendered
  -- is a confirmed case of Vanilla texture paths that simply do not draw on
  -- this client, and the elite icon already cost a session hunting for one
  -- that does. White star on a black rim, so SetVertexColor tints the star
  -- to the accent while the rim stays dark enough to read over a bright
  -- health fill.
  leaderIcon = "Interface\\AddOns\\unrealUI\\media\\leader-star",
}

-- Flag artwork for the settings language selector, keyed by the locale codes
-- core/locale.lua registers. A code without artwork falls back to its ASCII
-- two-letter badge, so the selector remains usable if another locale is added
-- before its flag is available.
--
-- Paths are rebuilt here at runtime and never persisted, per
-- knowledge.json / config.savedvariables_backslash_corruption.
M.languageFlag = {
  ["enUS"] = "Interface\\AddOns\\unrealUI\\media\\Flags\\en",
  ["zhCN"] = "Interface\\AddOns\\unrealUI\\media\\Flags\\cn",
  ["ruRU"] = "Interface\\AddOns\\unrealUI\\media\\Flags\\ru",
  ["frFR"] = "Interface\\AddOns\\unrealUI\\media\\Flags\\fr",
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
  unitFrameBorder = { 0.05, 0.05, 0.05, 1.00 },
  shadow     = { 0.00, 0.00, 0.00, 0.55 },
  shadowStrong = { 0.00, 0.00, 0.00, 0.90 },

  -- #f5ae0a and two derived tones: one dimmed for inactive accents, one
  -- translucent for the fill behind a selected row.
  accent     = { 0.96, 0.68, 0.04, 1.00 },
  accentDim  = { 0.55, 0.39, 0.03, 1.00 },
  accentFill = { 0.96, 0.68, 0.04, 0.22 },

  -- The scrim the cooldown wipe is drawn from. Neutral black rather than an
  -- accent: it is a shade over game content, not unrealUI chrome, and it has to
  -- read the same over a bright icon and a dark one. Alpha is the trade between
  -- the wipe being legible and the icon under it staying recognisable.
  cooldownWipe = { 0.00, 0.00, 0.00, 0.60 },

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

  -- Breath is a depletion state, not an UnrealUI accent. Its cool blue stays
  -- separate from casting so the two progress bars remain distinguishable.
  breath     = { 0.22, 0.60, 0.74, 1.00 },

  highlight  = { 0.96, 0.68, 0.04, 0.22 },
  mover      = { 0.55, 0.36, 0.02, 0.45 },
  moverEdge  = { 0.96, 0.68, 0.04, 1.00 },
  grid       = { 0.45, 0.45, 0.45, 0.30 },
  gridAxis   = { 0.96, 0.68, 0.04, 0.55 },
}

-- Unit frames have a small theme-owned style surface. Their geometry,
-- generated frame names and aura attachment points are deliberately not part
-- of it: themes may change appearance, never the unit-frame feature contract.
M.unitFrame = {
  usePastelGradient = true,
  statusTexture = M.texture.statusBar,
  background = { 0.06, 0.06, 0.06, 0.85 },
}

-- Countdown-number tiers, keyed by the tier U.FormatTimeShort reports. Shared
-- because two surfaces now draw the same readout -- action-button cooldowns
-- (modules/actionbar.lua) and aura timers (modules/auras.lua) -- and a second
-- copy of the palette is exactly the module-local design system
-- rules/unreal-ui-design.md forbids. The last five seconds turn red; the longer
-- tiers cool towards blue so a glance at the colour alone reads the magnitude.
M.cooldownText = {
  low    = { 1.00, 0.20, 0.20, 1.00 },   -- last five seconds
  normal = { 1.00, 1.00, 1.00, 1.00 },
  minute = { 0.20, 1.00, 1.00, 1.00 },
  hour   = { 0.20, 0.50, 1.00, 1.00 },
  day    = { 0.20, 0.20, 1.00, 1.00 },
}

-- How a zone's level range reads against the player's own level, drawn beside
-- the hovered zone name on the world map (modules/worldmap.lua). Game state
-- rather than unrealUI chrome, so these are semantic colours and never the
-- accent; they live here because rules/unreal-ui-design.md keeps shared colour
-- values central even while one surface draws them.
M.zoneLevel = {
  ready   = { 0.25, 0.75, 0.30, 1.00 },   -- player is above the zone range
  caution = { 1.00, 0.50, 0.10, 1.00 },   -- player is inside the zone range
  danger  = { 1.00, 0.20, 0.20, 1.00 },   -- zone is above the player
}

-- Item-comparison deltas, drawn on the hovered item's own stat lines while an
-- equipped counterpart is on screen (modules/tooltip.lua). This is game state
-- rather than UnrealUI chrome, so it stays clear of the accent and reuses the
-- same green/red the zone-level readout already carries.
M.itemCompare = {
  better = { 0.25, 0.75, 0.30, 1.00 },   -- hovered item gives more
  worse  = { 1.00, 0.20, 0.20, 1.00 },   -- hovered item gives less
}

-- Power colours keyed by the numeric UnitPowerType index used by Vanilla.
-- The unit API contract is still INCONCLUSIVE in the compact evidence
-- (knowledge.json / unitframes.core_unit_api_contract_partial), so consumers
-- must fall back rather than assume an index is present.
--
-- The first four indices are documented by this client. Runic Power is kept at
-- its conventional index 6 from the requested palette; the current client
-- documentation does not list it, but the colour is ready if UnitPowerType
-- exposes that value on a supported class.
M.power = {
  [0] = { 0.31, 0.45, 0.63, 1.00 },   -- mana
  [1] = { 0.78, 0.25, 0.25, 1.00 },   -- rage
  [2] = { 0.71, 0.43, 0.27, 1.00 },   -- focus
  [3] = { 0.65, 0.63, 0.35, 1.00 },   -- energy
  [6] = { 0.00, 0.82, 1.00, 1.00 },   -- runic power (undocumented here)
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

-- Authoritative classic class palette shared by every UnrealUI surface. Keep
-- this local rather than consulting RAID_CLASS_COLORS: the client table can
-- carry different values, which would make tooltip and unit-frame health bars
-- vary by runtime instead of using the palette selected for this theme.
M.class = {
  DEATHKNIGHT = { 0.77, 0.12, 0.23 },
  DRUID       = { 1.00, 0.49, 0.04 },
  HUNTER      = { 0.67, 0.83, 0.45 },
  MAGE        = { 0.41, 0.80, 0.94 },
  PALADIN     = { 0.96, 0.55, 0.73 },
  PRIEST      = { 1.00, 1.00, 1.00 },
  ROGUE       = { 1.00, 0.96, 0.41 },
  SHAMAN      = { 0.00, 0.44, 0.87 },
  WARLOCK     = { 0.58, 0.51, 0.79 },
  WARRIOR     = { 0.78, 0.61, 0.43 },
}

function M.ClassColor(class)
  if type(class) ~= "string" then return nil end
  local key = string.upper(class)
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

-- ---------------------------------------------------------------------------
-- Item slots
--
-- Shared by every window that draws container slots (bags, bank). Kept here
-- rather than in a module so the two frames cannot drift apart; see
-- .claude/rules/unreal-ui.md on compatibility/token placement.
--
-- Vanilla ITEM_QUALITY_COLORS values. The stock global is used when the client
-- provides it (see M.ItemQualityColor in core/itemslot.lua) but is not assumed.
-- ---------------------------------------------------------------------------
M.quality = {
  [0] = { 0.62, 0.62, 0.62 },   -- Poor
  [1] = { 1.00, 1.00, 1.00 },   -- Common
  [2] = { 0.12, 1.00, 0.00 },   -- Uncommon
  [3] = { 0.00, 0.44, 0.87 },   -- Rare
  [4] = { 0.64, 0.21, 0.93 },   -- Epic
  [5] = { 1.00, 0.50, 0.00 },   -- Legendary
  [6] = { 0.90, 0.80, 0.50 },   -- Artifact
}

-- Only quality *above* this gets its colour on the slot border. pfUI calls the
-- same threshold `borderlimit` and defaults it to 1: without it every common
-- item outlines itself in pure white, which is the white border the first
-- in-game bag screenshot showed on almost every slot.
M.qualityLimit = 1

M.slotBorder = {
  empty = { 0.16, 0.16, 0.16, 1.00 },   -- empty slot
  plain = { 0.32, 0.32, 0.32, 1.00 },   -- poor / common item
  quest = { 0.85, 0.55, 0.55, 1.00 },   -- quest item, light pale red
}

-- Container-window metrics. Bags and bank share them so the two windows read
-- as one component at one density.
M.slot = {
  size    = 30,   -- item button
  gap     = 3,
  padding = 6,
  header  = 28,
  tray    = 26,   -- keyring / bag-slot button
  icon    = 16,   -- header icon button
}

-- ---------------------------------------------------------------------------
-- Money
--
-- One coin atlas, one set of texture coordinates and one colour per
-- denomination, shared by every readout in the addon (the status overlay and,
-- since it needs the identical look, the bank purchase price). Centralised so
-- a second consumer cannot drift from the first; see
-- .claude/rules/unreal-ui.md on shared media/state placement.
-- ---------------------------------------------------------------------------
-- USER_CONFIRMED_INGAME: UI-MoneyIcons renders when the path uses valid Lua
-- backslashes and the atlas is sliced horizontally. The separate UI-GoldIcon,
-- UI-SilverIcon and UI-CopperIcon paths do not render on this client.
M.moneyTexture = "Interface\\MoneyFrame\\UI-MoneyIcons"
M.money = {
  gold = {
    coords = { 0.00, 0.25, 0, 1 },
    color = { 1.00, 0.82, 0.00, 1.00 },
  },
  silver = {
    coords = { 0.25, 0.50, 0, 1 },
    color = { 0.75, 0.75, 0.75, 1.00 },
  },
  copper = {
    coords = { 0.50, 0.75, 0, 1 },
    color = { 0.80, 0.47, 0.29, 1.00 },
  },
}
