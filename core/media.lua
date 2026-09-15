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
-- Compact bar text needs more contrast than body text: it sits directly on
-- bright semantic health and power fills. It used to ask for a tighter
-- three-quarter-pixel offset to stay attached to the glyph, but nothing under
-- one screen pixel rasterises (see U.SetTextShadow), so that read as no shadow
-- at all on the unit frames. The separation stays at the shared one pixel and
-- M.color.shadowStrong carries the extra contrast instead.
M.compactTextShadowOffset = { 1, -1 }

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
  -- knowledge.json / castbar.native_frame_hierarchy: measured native castbar
  -- geometry plus the isolated addon-owned visual probe. Candidate A was
  -- user-confirmed visible in game; neither path requires reading a native
  -- CastingBarFrame region at startup.
  classicCastbarBorder = "Interface\\CastingBar\\UI-CastingBar-Border",
  classicCastbarSpark = "Interface\\CastingBar\\UI-CastingBar-Spark",
  chatResizeGrip = "Interface\\AddOns\\unrealUI\\media\\resize",
  restIcon = "Interface\\AddOns\\unrealUI\\media\\rest-icon",
  -- The modern unit frame's resting flipbook. This is an addon-owned copy of
  -- the user-supplied 42-cell sheet used by modern-wow, kept outside that
  -- theme's media tree so the two visual families do not depend on each
  -- other's tokens or paths.
  restingFlipbook = "Interface\\AddOns\\unrealUI\\media\\resting-flipbook",
  -- Party-leader star. unrealUI's own art rather than the stock GroupFrame
  -- leader icon: knowledge.json / textures.separate_coin_paths_not_rendered
  -- is a confirmed case of Vanilla texture paths that simply do not draw on
  -- this client, and the elite icon already cost a session hunting for one
  -- that does. White star on a black rim, so SetVertexColor tints the star
  -- to the accent while the rim stays dark enough to read over a bright
  -- health fill.
  leaderIcon = "Interface\\AddOns\\unrealUI\\media\\leader-star",
  -- Bag favourite marker (modules/bagfavorites.lua). Deliberately the same
  -- star art as the party-leader icon above, as requested: one shape means
  -- "marked" everywhere in this interface, and it is art already proven to
  -- render on this client, which a freshly chosen texture path would not be.
  -- Named separately so a later change to either marker cannot silently move
  -- the other.
  favoriteIcon = "Interface\\AddOns\\unrealUI\\media\\leader-star",
  -- The sort button's icon, shared by the bag and bank windows. Central
  -- because it is the same control twice, and because unlike the icon paths
  -- already proven on screen beside it this one is *chosen*, not verified:
  -- this client ships no readable icon inventory (there is no extracted
  -- Interface Icons tree and the compact DB lists no textures). A path the
  -- client does not have renders blank rather than raising, so
  -- U.CreateIconButton's fallback letter cannot catch it -- swapping this one
  -- line is the whole fix, and doing it here fixes both windows at once.
  sortIcon = "Interface\\Icons\\INV_Misc_Note_01",
  -- The bag and keyring pictures. Central because two surfaces draw them --
  -- the bag window's header toggles (modules/bags.lua) and the HUD bag bar
  -- (modules/bagbar.lua) -- and they have to read as the same control. Chosen
  -- rather than verified, exactly like sortIcon above: a path this client does
  -- not have renders blank, so changing either one line fixes both surfaces.
  bagIcon = "Interface\\Icons\\INV_Misc_Bag_08",
  keyringIcon = "Interface\\Icons\\INV_Misc_Key_03",
  -- unrealUI's own open/close arrow (media/arrow.tga, 25x32, uncompressed
  -- 32-bit): a yellow triangle carrying its own dark outline, so it reads
  -- over the game world with no panel behind it and needs no vertex tint.
  -- Authored pointing right; U.CreateArrowToggle samples it backwards for
  -- the left direction. Extensionless addon path, like the bundled art above.
  arrow = "Interface\\AddOns\\unrealUI\\media\\arrow",
  -- Ornamental target-frame classification artwork (modules/unitframes.lua).
  -- One 350x117 32-bit RLE type-10 TGA per tier, drawn as an eight-slice
  -- border around the target frame 182x47 opening. Extensionless addon
  -- paths, and freshly named rather than reusing an existing one, per
  -- knowledge.json / textures.rle_512_tga_atlas_four_arg_supported -- the
  -- same combination (RLE type-10 TGA at a fresh extensionless path, cells
  -- picked with four-argument SetTexCoord) that is USER_CONFIRMED_INGAME
  -- there. The non-power-of-two size follows media/rest-icon (36x39), which
  -- this client does draw.
  targetSkinRare  = "Interface\\AddOns\\unrealUI\\media\\frame-rare-350",
  targetSkinElite = "Interface\\AddOns\\unrealUI\\media\\frame-elite-350",
  targetSkinBoss  = "Interface\\AddOns\\unrealUI\\media\\frame-boss-350",
}

-- ---------------------------------------------------------------------------
-- Extended Quest Log parchment (Classic WoW theme only)
--
-- Art from Extended QuestLog 3.6.1 (Copyright 2006 Daniel Rehn), read only by
-- modules/questlogextended.lua. See media/Textures/classic-wow/questLog/ATTRIBUTION.md for
-- provenance and LICENSE for the copyright note. No module builds one of these
-- paths for itself, and no other theme reads this table: the `modern` and
-- `modern-wow` Quest Logs are drawn by modules/questlog.lua instead.
--
-- Paths are extensionless, per knowledge.json /
-- textures.addon_tga_paths_require_extensionless (SUPPORTED,
-- USER_CONFIRMED_INGAME). Unlike the modern-wow import below these files were
-- NOT re-encoded: they are byte-identical copies of art UnrealQuest already
-- draws on this client, and textures.uncompressed_512_tga_atlas_corrupts is
-- about the 512 atlas form, not these 256-tall pages.
--
-- `page` is the eight-slice cover, laid out on QuestLogFrame itself in the
-- classic-wow order and geometry: the two 256-wide corners and the 256-wide middle of
-- each half, plus the 128-wide "switch" piece and the 64-wide right edge. The
-- offsets are from the frame corner named by `point`, so the set tiles a
-- 704x512 window exactly. `layout` is that window and the two parchment pages
-- inside it; modules/questlogextended.lua measures its row count against them
-- rather than assuming the source layout's fixed 27.
-- ---------------------------------------------------------------------------
M.classicWow = {}
M.classicWow.path = "Interface\\AddOns\\unrealUI\\media\\Textures\\classic-wow\\questLog\\"

M.classicWow.page = {
  { file = "questLog_TopLeft",        width = 256, height = 256, point = "TOPLEFT",    x =   0, y = 0 },
  { file = "questLog_TopSwitchOn",    width = 128, height = 256, point = "TOPLEFT",    x = 256, y = 0 },
  { file = "questLog_TopMiddle",      width = 256, height = 256, point = "TOPLEFT",    x = 384, y = 0 },
  { file = "questLog_TopRight",       width =  64, height = 256, point = "TOPLEFT",    x = 640, y = 0 },
  { file = "questLog_BottomLeft",     width = 256, height = 256, point = "BOTTOMLEFT", x =   0, y = 0 },
  { file = "questLog_BottomSwitchOn", width = 128, height = 256, point = "BOTTOMLEFT", x = 256, y = 0 },
  { file = "questLog_BottomMiddle",   width = 256, height = 256, point = "BOTTOMLEFT", x = 384, y = 0 },
  { file = "questLog_BottomRight",    width =  64, height = 256, point = "BOTTOMLEFT", x = 640, y = 0 },
}

M.classicWow.layout = {
  width = 704,
  height = 512,
  -- Left page: the quest list.
  listWidth = 300,
  listHeight = 411,
  listTop = 74,
  rowLeft = 19,
  rowTop = 75,
  -- Right page: the stock detail pane.
  detailWidth = 300,
  detailHeight = 413,
  detailLeft = 350,
  detailTop = 72,
  -- The classic-wow page budget, kept as an upper bound only. The count actually
  -- installed is measured against the list page from the live row height.
  maxRows = 27,
  minRows = 6,
  defaultRowHeight = 16,
  minRowHeight = 8,
  maxRowHeight = 48,
}

-- ---------------------------------------------------------------------------
-- modern-wow theme media
--
-- Art imported from DragonflightUI-Reforged for themes/modern-wow.lua only.
-- See media/Textures/modern-wow/ATTRIBUTION.md for per-file provenance and
-- tools/import_modern_wow_media.py for the import itself. No other theme reads
-- this table, and no module builds one of these paths for itself.
--
-- Paths are extensionless, per knowledge.json /
-- textures.addon_tga_paths_require_extensionless (SUPPORTED,
-- USER_CONFIRMED_INGAME). Every file was re-encoded to 32-bit RLE TGA on
-- import because knowledge.json / textures.uncompressed_512_tga_atlas_corrupts
-- is RUNTIME_FAILURE_CONFIRMED for the uncompressed form at full size.
--
-- The rectangles below are measured from the imported files, not estimated.
-- All four classification variants share one bar-housing rectangle and differ
-- only in how far their ornament extends, which is what lets the housing be
-- drawn once and the ornament swapped per tier.
-- ---------------------------------------------------------------------------
M.modernWow = {}
M.modernWow.path = "Interface\\AddOns\\unrealUI\\media\\Textures\\modern-wow\\"

M.modernWow.texture = {
  playerFrame     = M.modernWow.path .. "unitframes\\player-frame-large",
  playerFrameBg   = M.modernWow.path .. "unitframes\\player-frame-bg",
  targetFrame     = M.modernWow.path .. "unitframes\\target-frame-large",
  targetFrameBg   = M.modernWow.path .. "unitframes\\target-frame-bg",
  frameRare       = M.modernWow.path .. "unitframes\\frame-rare",
  frameElite      = M.modernWow.path .. "unitframes\\frame-elite",
  frameRareElite  = M.modernWow.path .. "unitframes\\frame-rare-elite",
  frameBoss       = M.modernWow.path .. "unitframes\\frame-boss",
  partyFrame      = M.modernWow.path .. "unitframes\\party-frame",
  playerStatus    = M.modernWow.path .. "unitframes\\player-status-large",
  restingFlipbook = M.modernWow.path .. "unitframes\\resting-flipbook",
  portraitBackground = M.modernWow.path ..
                       "unitframes\\unit-frame-portrait-background",
  healthFill      = M.modernWow.path .. "unitframes\\health-fill",
  healthFillMinus = M.modernWow.path .. "unitframes\\health-fill-minus",
  powerFill       = M.modernWow.path .. "unitframes\\power-fill-player",
  powerFillTarget = M.modernWow.path .. "unitframes\\power-fill-target",
  totHealthFill   = M.modernWow.path .. "unitframes\\tot-health-fill",
  totPowerFill    = M.modernWow.path .. "unitframes\\tot-power-fill",
  pvpAlliance     = M.modernWow.path .. "unitframes\\pvp-alliance",
  pvpHorde        = M.modernWow.path .. "unitframes\\pvp-horde",

  castFrame       = M.modernWow.path .. "castbar\\frame",
  castBackground  = M.modernWow.path .. "castbar\\background",
  castShadow      = M.modernWow.path .. "castbar\\shadow",
  -- The flash cropped to the bar and shaped by the mask, so the finish glow
  -- stays inside the housing; and the mask itself, for the fill pulse.
  castFlashInner  = M.modernWow.path .. "castbar\\flash-inner",
  castMask        = M.modernWow.path .. "castbar\\mask",
  castSpark       = M.modernWow.path .. "castbar\\spark",
  -- One fill per cast state, each pre-shaped by CastingBarMask
  -- (tools/import_modern_wow_media.py MASKED). Fresh paths on purpose: the
  -- client caches decoded textures across /reload, and `castbar\\fill` was
  -- DragonflightUI's pale Standard3 (textures.resources_cached_across_ui_reload).
  castFill        = M.modernWow.path .. "castbar\\fill-cast",
  castFillChannel = M.modernWow.path .. "castbar\\fill-channel",
  castFillCraft   = M.modernWow.path .. "castbar\\fill-craft",
  castFillInterrupted = M.modernWow.path .. "castbar\\fill-interrupted",

  panelTopLeft     = M.modernWow.path .. "ui\\panel-top-left",
  panelTopRight    = M.modernWow.path .. "ui\\panel-top-right",
  panelBottomLeft  = M.modernWow.path .. "ui\\panel-bottom-left",
  panelBottomRight = M.modernWow.path .. "ui\\panel-bottom-right",
  questlogLeft     = M.modernWow.path .. "ui\\questlog-left-large-v2",
  questlogRight    = M.modernWow.path .. "ui\\questlog-right-large",
  spellBackground  = M.modernWow.path .. "ui\\spell-bg",
  header           = M.modernWow.path .. "ui\\header",
  headerLeft       = M.modernWow.path .. "ui\\header-left",
  headerRight      = M.modernWow.path .. "ui\\header-right",
  button128Red     = M.modernWow.path .. "ui\\128RedButton",
  button128GoldRed = M.modernWow.path .. "ui\\128GoldRedButton",
  redButton        = M.modernWow.path .. "ui\\red-button",
  comboPoints      = M.modernWow.path .. "ui\\combo-points",
  classPortraits   = M.modernWow.path .. "ui\\class-portraits",
  frameTabs        = M.modernWow.path .. "ui\\frame-tabs",
  frameBorder      = M.modernWow.path .. "ui\\frame-border",

  minimapBorder      = M.modernWow.path .. "minimap\\uiminimapborder",
  minimapShadow      = M.modernWow.path .. "minimap\\uiminimapshadow",
  minimapTopPanel    = M.modernWow.path .. "minimap\\uiminimap_toppanel",
  minimapMail        = M.modernWow.path .. "minimap\\mail",
  minimapZoomIn      = M.modernWow.path .. "minimap\\ZoomIn32",
  minimapZoomInOver  = M.modernWow.path .. "minimap\\ZoomIn32-over",
  minimapZoomInPush  = M.modernWow.path .. "minimap\\ZoomIn32-push",
  minimapZoomInOff   = M.modernWow.path .. "minimap\\ZoomIn32-disabled",
  minimapZoomOut     = M.modernWow.path .. "minimap\\ZoomOut32",
  minimapZoomOutOver = M.modernWow.path .. "minimap\\ZoomOut32-over",
  minimapZoomOutPush = M.modernWow.path .. "minimap\\ZoomOut32-push",
  minimapZoomOutOff  = M.modernWow.path .. "minimap\\ZoomOut32-disabled",

  -- Shared media for the action bar and the HUD surfaces below. Their owning
  -- modules choose the drawing path; modules/modernwow.lua only registers and
  -- gates each completed surface.
  actionBar          = M.modernWow.path .. "actionbar\\bar",
  actionButton       = M.modernWow.path .. "actionbar\\button",
  actionButtonBorder = M.modernWow.path .. "actionbar\\button-border",
  actionButtonHover  = M.modernWow.path .. "actionbar\\button-highlight",
  actionIndicator    = M.modernWow.path .. "actionbar\\indicator",
  actionGryphon      = M.modernWow.path .. "actionbar\\gryphon",
  actionWyvern       = M.modernWow.path .. "actionbar\\wyvern",
  pageUpNormal       = M.modernWow.path .. "actionbar\\page-up-normal",
  pageUpPushed       = M.modernWow.path .. "actionbar\\page-up-pushed",
  pageUpHighlight    = M.modernWow.path .. "actionbar\\page-up-highlight",
  pageDownNormal     = M.modernWow.path .. "actionbar\\page-down-normal",
  pageDownPushed     = M.modernWow.path .. "actionbar\\page-down-pushed",
  pageDownHighlight  = M.modernWow.path .. "actionbar\\page-down-highlight",

  bagBackground    = M.modernWow.path .. "bags\\background",
  bagSlotFrame     = M.modernWow.path .. "bags\\slot-frame",
  bagSlot          = M.modernWow.path .. "bags\\slot",
  bagSlotHighlight = M.modernWow.path .. "bags\\slot-highlight",
  bagSlotCutout    = M.modernWow.path .. "bags\\slot-cutout",
  bagHighlight     = M.modernWow.path .. "bags\\highlight",
  bagExpand        = M.modernWow.path .. "bags\\expand",
  bagKeyring       = M.modernWow.path .. "bags\\keyring",

  xpFill   = M.modernWow.path .. "xpbar\\fill",
  xpBorder = M.modernWow.path .. "xpbar\\border",

  chatArrowUp   = M.modernWow.path .. "chat\\arrow-up",
  chatArrowDown = M.modernWow.path .. "chat\\arrow-down",
}

-- Blizzard's Dragonflight MinimalScrollBar art, supplied as the original
-- 64x64 proportional sheet and 64x1024 vertical sheet. The pixel rectangles
-- are the UiTextureAtlasMember bounds for build 10.0.2.46801; the client this
-- addon runs on has no SetAtlas route, so core/stockui.lua applies these cells
-- to the existing Slider and arrow-button state regions with SetTexCoord.
-- Native range, value, scripts, hit areas and thumb movement remain owned by
-- the stock scrollbar.
--
-- MinimalScrollBar (the template DF-main's lists inherit) keeps its steppers
-- inside the bar and starts its Track 19 below the top: an 11-high stepper plus
-- an 8 gap. The legacy Slider is the reverse -- its arrows hang outside it and
-- the thumb travels its whole height -- so the Slider itself is the Track here
-- and each stepper sits `arrow.gap` beyond the Slider's end. The arrow faces
-- and the thumb are addon-owned textures (see U.StyleModernWowScrollbar); the
-- atlas has no disabled stepper cell, so a disabled arrow is its normal cell
-- at `disabledAlpha`.
M.modernWow.scrollbar = {
  proportional = M.modernWow.path .. "ui\\minimal-scrollbar-proportional",
  vertical = M.modernWow.path .. "ui\\minimal-scrollbar-vertical",
  arrow = {
    width = 17,
    height = 11,
    gap = 8,
    disabledAlpha = 0.35,
    up = {
      normal = { 1 / 64, 18 / 64, 1 / 64, 12 / 64 },
      pushed = { 1 / 64, 18 / 64, 14 / 64, 25 / 64 },
      hover  = { 1 / 64, 18 / 64, 27 / 64, 38 / 64 },
    },
    down = {
      normal = { 20 / 64, 37 / 64, 1 / 64, 12 / 64 },
      pushed = { 1 / 64, 18 / 64, 40 / 64, 51 / 64 },
      hover  = { 20 / 64, 37 / 64, 14 / 64, 25 / 64 },
    },
  },
  track = {
    width = 8,
    cap = 8,
    top   = { 39 / 64, 47 / 64, 14 / 64, 22 / 64 },
    middle = { 1 / 64, 9 / 64, 0, 1 / 1024 },
    bottom = { 49 / 64, 57 / 64, 1 / 64, 9 / 64 },
  },
  thumb = {
    width = 8,
    minExtent = 44,
    topExtent = 8,
    bottomExtent = 36,
    normal = {
      top    = { 39 / 64, 47 / 64, 1 / 64, 9 / 64 },
      middle = { 31 / 64, 39 / 64, 1 / 1024, 716 / 1024 },
      bottom = { 40 / 64, 48 / 64, 27 / 64, 63 / 64 },
    },
    hover = {
      top    = { 1 / 64, 9 / 64, 53 / 64, 61 / 64 },
      middle = { 21 / 64, 29 / 64, 1 / 1024, 716 / 1024 },
      bottom = { 20 / 64, 28 / 64, 27 / 64, 63 / 64 },
    },
    pushed = {
      top    = { 49 / 64, 57 / 64, 14 / 64, 22 / 64 },
      middle = { 11 / 64, 19 / 64, 1 / 1024, 716 / 1024 },
      bottom = { 30 / 64, 38 / 64, 27 / 64, 63 / 64 },
    },
  },
}

-- Minimap chrome, measured from the 140-unit round-map layout the imported
-- art was authored around. The panel follows the live map width so the native
-- minimap remains the geometry authority; only its ornamental chrome changes.
M.modernWow.minimap = {
  borderOffset = 10,
  shadowAlpha = 0.3,
  topPanelHeight = 12,
  topPanelGap = 18,
  topPanelRightOverhang = 5,
  -- 30, +7.65 so the taller band keeps its centre (it grows 3 px each way).
  topPanelBottomOverhang = 37.65,
  -- Drawn art height: the original 32 (12 panel + 20 overhang) plus 30%,
  -- then +11 drawn for +6 visible px (the band is 35/64 of the art).
  topPanelArtHeight = 52.6,
  -- Visible band of uiminimap_toppanel.tga: alpha rows 2..36 top-down (end
  -- exclusive 37) of 64 -- the file is bottom-origin. Confirmed by the
  -- 2026-09-14 in-game screenshot; the zone name centres on this band.
  topPanelTexHeight = 64,
  -- Horizontal visible band: alpha columns 1..248 (end exclusive 249) of 256.
  topPanelTexWidth = 256,
  topPanelVisibleLeft = 1,
  topPanelVisibleRight = 249,
  topPanelVisibleTop = 2,
  topPanelVisibleBottom = 37,
  zoneX = 4,
  zoneY = 6,  -- nudge above the band centre (positive = up)
  zoneHeight = 20,
  -- Warm title gold, as the theme's other short headings.
  zoneColor = { 1.00, 0.82, 0.00, 1.00 },
  -- Seconds between zone-name readbacks; zone events are unverified here.
  zoneRefresh = 1,
  zoomScale = 0.64,
  -- In the buttons' scaled units (screen px / 0.64): -5 plus 10 screen px left.
  zoomX = -20.6,
  zoomY = 47.8,  -- 40 plus 5 screen px up
  mailX = -2,
  mailY = -1,
  mailSize = 32,
}

-- Bottom window tabs from ui/frame-tabs.tga (64x256). Cells are measured off
-- the atlas's own alpha: `u1, u2, v1, v2` plus the cell's texel size. Each
-- middle is a flat horizontal run, so it stretches across a tab of any width;
-- the caps carry the rounded corners and the rim and are drawn at a fixed
-- width. Active cells are 42 texels tall and inactive ones 36, both hanging
-- from the same top edge, so the selected tab reads as the longer one.
--
-- `scale` maps texels to UI units, so the art fits UnrealUI's compact tab
-- rather than the source's 32-unit one. `height` is the tab button height the
-- theme sets; `lift` tucks the art's top under the window's bottom rim.
-- `hoverAlpha` is how strongly the active art shows through a hovered
-- inactive tab.
M.modernWow.tab = {
  atlasWidth = 64,
  scale  = 0.75,
  height = 27,
  lift   = 3,
  -- Label centre offset; the shared flat tab uses -1, lifted 3 for this art.
  textY  = 2,
  -- Preferred space each side of a label; the art's end caps are ~28 wide, so
  -- the flat tab's 10 crowds the rim. The strip fit still reduces it to fit.
  padding = 14,
  hoverAlpha = 0.45,
  activeMiddle   = { 0,       1,       0 / 256,  42 / 256, w = 64, h = 42 },
  activeRight    = { 0,      37 / 64, 82 / 256, 124 / 256, w = 37, h = 42 },
  activeLeft     = { 0,      37 / 64, 126 / 256, 168 / 256, w = 37, h = 42 },
  inactiveMiddle = { 0,       1,      44 / 256,  80 / 256, w = 64, h = 36 },
  inactiveRight  = { 0,      37 / 64, 170 / 256, 206 / 256, w = 37, h = 36 },
  inactiveLeft   = { 0,      37 / 64, 208 / 256, 244 / 256, w = 37, h = 36 },
}

-- The gold portrait ring panel-top-left draws in the Character window's corner.
-- Measured off the art's own gold pixels: x 8..71, y 4..67 of the 384x512
-- paperdoll design, which the quadrants draw 1:1 on the stock window. `inset`
-- trims the class icon inside the rim rather than over it.
M.modernWow.characterRing = {
  designWidth = 384,
  designHeight = 512,
  left = 8,
  top = 4,
  size = 64,
  inset = 5,
}

-- Shared placement of the collapse-all control beside a window's authored
-- portrait ring. Character Skills and Quest Log use the same gap.
M.modernWow.collapseAll = {
  ringGap = 6,
  -- Quest Log's normal 676-wide layout has a 507-wide left page; its ring
  -- ends at x=69, so the shared 6px gap puts the control at x=75.
  questLogX = 75,
}

-- Standard NPC dialogs use the same 384x512 paperdoll quadrants as the other
-- compact Modern WoW windows.  Keep their portrait geometry and semantic quest
-- colours separate from Character's class-icon token: the two currently share
-- a ring position, but they are different surfaces and can evolve independently.
M.modernWow.npcDialog = {
  designWidth = 384,
  designHeight = 512,
  portrait = {
    left = 8,
    top = 4,
    size = 64,
    inset = 5,
  },
  -- Available/complete quests use the warm quest gold; an accepted quest that
  -- is not ready to turn in uses the cool grey of ActiveQuestIcon (the grey ?
  -- seen over the NPC).  Hover brightens the label without changing its icon.
  questState = {
    available = { 1.00, 0.82, 0.12, 1.00 },
    active    = { 0.62, 0.65, 0.72, 1.00 },
    complete  = { 1.00, 0.82, 0.12, 1.00 },
    unknown   = { 0.92, 0.88, 0.78, 1.00 },
    hover     = { 1.00, 0.95, 0.72, 1.00 },
  },
  optionText = { 0.92, 0.88, 0.78, 1.00 },
  optionHover = { 1.00, 0.82, 0.12, 1.00 },
  -- The NPC progress panel has no authored scrollbar recess in the generic
  -- quadrant art. Draw this restrained two-layer channel below the native bar
  -- so its gold controls belong to the window instead of floating over it.
  progressBarBackground = {
    padding = 3,
    inset = 1,
    outer = { 0.30, 0.19, 0.055, 0.90 },
    inner = { 0.018, 0.014, 0.010, 0.94 },
  },
}

-- The high-resolution Quest Log art keeps transparent padding on the right
-- and bottom of its two source canvases. Crop that padding and split the live
-- frame at the artwork's measured seam, so the visible chrome fills the same
-- 676x440 window owned by modules/questlog.lua instead of shrinking inside it.
M.modernWow.questLog = {
  split = 896 / (896 + 298),
  leftTexCoord = { 0, 1, 0, 823 / 896 },
  rightTexCoord = { 0, 298 / 448, 0, 823 / 896 },
}

-- The three button beds the Quest Log art draws along the bottom of its left
-- page, measured off that page's own width so they follow the window when the
-- details pane opens or closes and the split is recomputed. `x` and `width`
-- are fractions of the LEFT piece; `bottom` and `height` are fractions of the
-- window, whose height does not change. The third bed is genuinely narrower
-- than the other two -- that is the art, not a measurement slip.
M.modernWow.questLog.buttonCell = {
  { x =  22 / 507, width = 112 / 507 },
  { x = 144 / 507, width = 111 / 507 },
  { x = 265 / 507, width =  71 / 507 },
}
M.modernWow.questLog.buttonBottom = 15 / 440
M.modernWow.questLog.buttonHeight = 14 / 440

-- The gold portrait ring the left page draws in its top-left corner. Measured
-- from questlog-left-large-v2.tga's own gold pixels: the ring's outer bounds are
-- x 8..122, y 4..118 on the 896x896 canvas, and its middle is empty -- the art
-- is a frame for an icon it does not itself draw.
--
-- `left`/`right` are fractions of the LEFT piece's width (u spans 0..1 over
-- the 896-wide canvas); `top`/`bottom` are fractions of the window height,
-- because leftTexCoord maps v 0..823 onto the whole frame. Anything placed
-- against this ring uses U.ModernWowQuestLogRingRect rather than these
-- fractions directly.
-- The recessed scroll channel the right page draws down its outer edge. This
-- is the one scroll gutter in the whole spread -- the left page runs parchment
-- all the way to the seam -- so it belongs to the details pane's bar.
--
-- Measured off questlog-right-large.tga's own luminance: across the page the
-- flat dark run is texels 247..284 (bounded by the bevel ridges at 243 and
-- 286, which are the channel's lit edges, not the channel), and down it the
-- run is rows 161..762 of the 823 visible rows. `left`/`right` are fractions
-- of the RIGHT piece's visible width; `top`/`bottom` are fractions of the
-- window height. Read through U.ModernWowQuestLogScrollRect, not directly.
M.modernWow.questLog.scrollChannel = {
  left   = 247 / 298,
  right  = 285 / 298,
  top    = 161 / 823,
  bottom = 763 / 823,
}

M.modernWow.questLog.portraitRing = {
  left   =   8 / 896,
  right  = 122 / 896,
  top    =   4 / 823,
  bottom = 118 / 823,
}

-- The icon inside that ring: the client's own Quest Log book portrait, the one
-- classic-wow shows natively. A stock path, not imported art -- the client
-- loads it for QuestLogFrame's unnamed 64x64 BACKGROUND region (interface.json
-- snapshot). `inset` is the fraction of the ring rect trimmed from each side so
-- the icon sits inside the gold rim rather than over it. `x`/`y` nudge its
-- centre in pixels (positive x right, negative y down) and `grow` adds pixels
-- to its width and height around that centre.
M.modernWow.questLog.bookIcon = {
  path  = "Interface\\QuestFrame\\UI-QuestLog-BookIcon",
  inset = 0.08,
  x     = 2,
  y     = -2,
  grow  = 4,
}

-- The Quests / Completed count boxes across the top of the list page, laid out
-- as DF-main's DFQuestLogCount. The rim is the theme's ThinBorder pieces
-- (`border`, set after the talents table that owns those paths) at `edge`
-- units per corner, with a see-through dark `fillColor` inset `fillInset`
-- from each side. The stock Common-Input-Border DF-main names draws nothing
-- here (USER_CONFIRMED_INGAME 2026-09-16), and the client's own QuestLogCount
-- pieces do not come back once stripped.
-- `x` starts at the gold ring's right edge, `y` is from the window top.
M.modernWow.questLog.countBox = {
  edge       = 10,
  height     = 24,
  fillInset  = 3,
  fillColor  = { 0.00, 0.00, 0.00, 0.65 },
  -- Frame levels above the Quest Log window, clear of its page-art chrome.
  levelAbove = 2,
  -- The boxes sit on the collapse-all control's row, `collapseGap` right of
  -- it. The control's size is read once at build; the fallback is the
  -- QuestLogCollapseAllButton size in the interface snapshot (40x22).
  collapseGap    = 23,
  -- Lifts the boxes above the control's centre line (positive is up).
  rowOffsetY     = 4,
  collapseWidth  = 40,
  collapseHeight = 22,
  minWidth   = 40,
  padding    = 8,
  gap        = 6,
  y          = -24,
  maxQuests  = 20,
  labelColor = { 1.00, 0.82, 0.00, 1.00 },
}

-- Spellbook window (modules/spellbookmodernwow.lua). The housing is the same
-- 384x512 paperdoll quadrants as the Character window; the book is
-- ui/spellbook/spellbook-page-1 plus its 21-texel right edge, spellbook-page-2,
-- drawn inside the housing's recess.
--
-- The page art is 533x494 and the recess 317x354, so the book cannot sit in
-- the stock 384-wide window at its authored aspect. The window is widened
-- instead, by exactly what the page needs at the recess height, and only the
-- plain housing columns `stretch.left..right` absorb that width. Those 24
-- columns carry no rivet or seam (ticks sit at 121/190/222/290, the quadrant
-- seam at 256-259), so the ring, corners and close-button end keep their
-- authored proportions.
--
-- Housing numbers are measured off the composited quadrants in 384x512
-- design pixels: alpha bounds x 2..354 / y 0..439; the header bar is lit rows
-- 13..36 and the dark band beneath it 38..70; the recess is bounded by the
-- dark lines at x 23/341 and y 72/427. The ring is M.modernWow.characterRing's.
--
-- `grid` and `nav` are in page-art texels (Spellbook-Page-1 space), so the
-- spell rows follow the page: paper runs x ~62 (past the ribbon gutter) to
-- the right edge and y ~10..470.
M.modernWow.spellBook = {
  texture = {
    page1       = M.modernWow.path .. "ui\\spellbook\\spellbook-page-1",
    page2       = M.modernWow.path .. "ui\\spellbook\\spellbook-page-2",
    parts       = M.modernWow.path .. "ui\\spellbook\\spellbook-parts",
    skillTab    = M.modernWow.path .. "ui\\spellbook\\skillline-tab",
    skillTabGlow = M.modernWow.path .. "ui\\spellbook\\skillline-tab-glow",
  },
  design = { width = 384, height = 512 },
  housing = { left = 2, right = 355, bottom = 440 },
  stretch = { left = 262, right = 286 },
  recess = { left = 24, top = 73, right = 341, bottom = 427 },
  headerBar = { left = 72, right = 350, top = 13, bottom = 36 },
  band = { top = 38, bottom = 70 },
  page = { width = 512, edgeWidth = 21, edgeCanvas = 32, height = 494,
           canvas = 512 },

  -- Spell buttons: two columns of six. `textGap` separates the icon from its
  -- name; the name column is what is left of the column pitch.
  -- `buttonScale` shrinks the spell button, and with it the slot frame,
  -- background and name shadow sized from it (user request, 2026-09-13: 30%
  -- smaller than the client's own button).
  grid = { left = 90, top = 36, columnPitch = 200, rowPitch = 64,
           columns = 2, textGap = 11, textInset = 4, nameY = -3,
           -- Rank/subtext (Racial, Passive, Apprentice...) below the name;
           -- 4 units higher than the old -2 (user request, 2026-09-13).
           subY = 2,
           buttonScale = 0.7 },
  -- Page arrows (native 32px art, kept) at the two ends of one line near the
  -- page foot, with the page number centred between them. The arrows carry
  -- their own "Prev"/"Next" labels on their inner sides, which need that
  -- run of page (USER_CONFIRMED_INGAME, 2026-09-13: side by side, the two
  -- labels printed over each other).
  nav = { y = 440, prevX = 110, nextX = 452, textX = 281 },

  -- Spellbook-Parts.tga (256x256) cells in texels: WORKING_SOURCE,
  -- WoW-DragonflightUI Mixin/UI.mixin.lua's own SetTexCoord values for this
  -- atlas, converted from fractions. They were authored around a 37-unit
  -- spell button (`designButton`); sizes and offsets scale with the live one.
  parts = {
    atlas = 256,
    designButton = 37,
    slotFrame      = { left = 1,   top = 113, right = 71,  bottom = 178,
                       width = 70, height = 65, x = 1.5,
                       -- Centrelines of its thin gold square, measured off
                       -- the file (luma peaks x 15-16 / 52, y 127 / 163-164).
                       square = { left = 15.5, right = 52.5,
                                  top = 127, bottom = 163.5 } },
    slotBackground = { left = 203, top = 1,   right = 246, bottom = 44,
                       width = 43, height = 43 },
    nameShadow     = { left = 80,  top = 95,  right = 247, bottom = 134,
                       x = -4, y = 1, height = 39, pad = 8,
                       widthScale = 1.265 },
    -- The gold burst-and-streak glow in the atlas' top-left corner, drawn on a
    -- spell the "Not on action bars" hint marks. Measured off the file (no
    -- source SetTexCoord uses it): lit bounds x 6..196 / y 5..94, stopping
    -- above the name shadow at y 95 and left of the slot background at x 202.
    -- The burst (x 0..79) and the streak (x 80..) are packed edge to edge.
    -- They are drawn as separate regions so each can retain the atlas seam
    -- while using the vertical anchor of the spell element it highlights.
    --
    -- `square` is the centreline of the burst's gold rim (x 33-35 / 73-76,
    -- y 34-35 / 73-76). It is ~40 texels across against the slot frame's ~37,
    -- so drawn at the slot frame's scale it showed a second, larger square
    -- (USER_CONFIRMED_INGAME, 2026-09-13). The glow is scaled and centred so
    -- this rim lands on slotFrame.square instead.
    barGlow        = { left = 0,   top = 0,   right = 200, bottom = 95,
                       square = { left = 34, right = 74.5,
                                  top = 34.5, bottom = 74.5 },
                       -- The burst and the text streak meet at atlas x=80 but
                       -- need different vertical anchors. Keeping them as one
                       -- region puts the streak above the name shadow when the
                       -- burst's square is correctly centred on slotFrame.
                       burst = { left = 0, top = 0, right = 80, bottom = 95 },
                       streak = { left = 80, top = 0, right = 200, bottom = 95,
                                  -- Vertical offset from nameShadow's centre,
                                  -- in design-button units. This aligns their
                                  -- measured light centres.
                                  y = -3.2, widthScale = 0.9 } },
  },

  -- The same breathe as the player frame's rest/combat halo
  -- (M.modernWow.playerFX): additive, alpha ping-pongs through
  -- U.EaseInOutCubic over `pulsePeriod`. `alphaMin` stays above zero so the
  -- mark never vanishes at the bottom of the cycle.
  barGlowPulse = { pulsePeriod = 2.5, alphaMin = 0.25, alphaMax = 0.675 },

  -- Skill-line side tabs: 32-unit native CheckButtons, their 64x64 frame
  -- drawn from (-3, 11) as the source template does. `left` hooks the art's
  -- bracket over the housing's right rim.
  skillTab = { size = 32, art = 64, artX = -3, artY = 11, rim = 4,
               top = 85, pitch = 48 },

  ring = { left = 8, top = 4, size = 64, inset = 5 },
  -- The two book toggles sit in the dark band under the header bar, right of
  -- the ring; the native checkbox is 20 units.
  toggle = { left = 80, top = 44 },
  close = { size = 20, right = 14 },
  bottomTab = { left = 14, top = 440, gap = 3 },
  dragInset = 60,

  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  -- The page number, drawn shadow-free (user request, 2026-09-13).
  pageTextColor = { 1.00, 1.00, 1.00, 1.00 },
  -- Every spell name, passive and racial included: the client dims passive
  -- names, which the user asked to draw like the rest (2026-09-13).
  spellNameColor = { 1.00, 0.82, 0.00, 1.00 },
  -- The hover glow every active spell uses; passives otherwise get their own.
  spellHighlight = "Interface\\Buttons\\ButtonHilight-Square",
}

-- Professions page (modules/spellbookprofessions.lua), drawn in place of the
-- spell pages when the Spellbook's bottom Professions tab is selected.
--
-- professions-book-left/-right share the spell pages' canvas exactly (512x512
-- plus a 32-wide edge; art in rows 0-493, edge columns 0-20), so they are
-- swapped into the same page regions and every number below is in the same
-- page-art texels that M.modernWow.spellBook.grid uses.
--
-- Row geometry is WORKING_SOURCE: WoW-DragonflightUI XML/ProfessionSpellbook.xml
-- places its rows at page texel x 73 with y 42/135 (primary, 81 tall) and
-- 238/295/352/409 (secondary, 46 tall), which match the bands measured off
-- the left page (dark row rules at y ~40, ~133, ~234, ~292, ~349, ~406).
-- The name/rank/bar offsets inside a row are compacted from that template so
-- all three fit the scaled row.
--
-- `parts` cells are that XML's own TexCoords on ProfessionsBook (256x128),
-- converted to texels and checked against the file's alpha: the ring's
-- centre is transparent and its rim opaque, so the profession icon is drawn
-- beneath it at `ring.icon` (at most the ring's inscribed square, 52).
M.modernWow.spellBook.professions = {
  texture = {
    pageLeft  = M.modernWow.path .. "ui\\profession\\professions-book-left",
    pageRight = M.modernWow.path .. "ui\\profession\\professions-book-right",
    parts     = M.modernWow.path .. "ui\\profession\\professions-book",
    fill      = M.modernWow.path .. "ui\\profession\\professions-progress-fill",
    -- The client's own glyph, as modules/character.lua draws it.
    unlearn   = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  },
  parts = {
    width = 256, height = 128,
    ring      = { left = 111, top = 19,  right = 185, bottom = 93 },
    barLeft   = { left = 1,   top = 62,  right = 17,  bottom = 78 },
    barRight  = { left = 1,   top = 80,  right = 17,  bottom = 96 },
    barMiddle = { left = 0,   top = 1,   right = 256, bottom = 17 },
    capLeft   = { left = 1,   top = 112, right = 13,  bottom = 124 },
    capRight  = { left = 1,   top = 98,  right = 13,  bottom = 110 },
    -- DFProfessionButtonTemplate's $parentNameFrame: the soft plate behind
    -- each profession spell's name (alpha bounds fill the whole cell).
    nameFrame = { left = 1,   top = 19,  right = 109, bottom = 60 },
  },

  rowLeft = 73,
  primaryTop = { 42, 135 },
  secondaryTop = { 238, 295, 352, 409 },

  ring = { x = 7, y = 7, size = 72, icon = 50 },
  primary = { nameY = 10, rankY = 32, barX = 114, barY = 54,
              missingX = 100, missingY = 18,
              missingWidth = 250 },
  secondary = { nameY = 4, rankY = 18, barX = 16, barY = 31,
                missingX = 4, missingY = 16,
                missingTextX = 255, missingWidth = 245 },
  -- The bar's end pieces sit outside its 95x16 run, lifted `capLift`.
  -- `textInset` is the skill value's left inset inside the bar; `textDrop`
  -- lowers it from the caps' lift, in window units (user request, 2026-09-15).
  bar = { width = 95, height = 16, cap = 16, capLift = 2, endCap = 12,
          textInset = 5, textDrop = 2 },
  -- Primary-row unlearn button: DragonflightUI's 26-unit glyph at scale .7,
  -- its right edge 30 * .7 left of the bar and lifted 1 (page texels).
  unlearn = { size = 18, gap = 21, lift = 1, alpha = 0.75, hoverAlpha = 1,
              pressShift = 1 },
  -- Native spell buttons. Primary rows put the first spell on the row's
  -- lower slot (`primaryY`, DragonflightUI's SpellButtonBottom at y 43) and a
  -- second one above it at `y`; secondary rows put the second one left of
  -- the first at `leftX`. `textWidth` is the name column right of each button.
  button = { size = 40, x = 361, y = 3, primaryY = 43, leftX = 212,
             textWidth = 100,
             -- `parts.nameFrame` replaces the spell page's name shadow on
             -- these buttons: 108x41 at the template's 40-unit button, its
             -- LEFT `x` right of the icon's RIGHT, drawn at `alpha`.
             nameFrame = { width = 108, height = 41, x = 1, alpha = 0.8 } },

  -- The client's Quest Log book, shown in the window's gold ring while this
  -- page is open (the same verified path M.modernWow.questLog.bookIcon draws).
  portrait = M.modernWow.questLog.bookIcon.path,

  nameColor = { 1.00, 0.82, 0.00, 1.00 },
  -- Rank line (Apprentice...) under each native spell button's name.
  subSpellColor = { 1.00, 1.00, 1.00, 1.00 },
  rankColor = { 1.00, 1.00, 1.00, 1.00 },
  barTextColor = { 1.00, 1.00, 1.00, 1.00 },
  missingHeaderColor = { 0.15, 0.10, 0.10, 1.00 },
  missingTextColor = { 0.10, 0.05, 0.05, 1.00 },
  missingIcon = "Interface\\Icons\\INV_Scroll_04",
  missingIconAlpha = 0.6,
  -- Maximum skill of each training rank, lowest first.
  ranks = { 75, 150, 225, 300 },
}

-- Talent window (modules/talentsmodernwow.lua): WoW-DragonflightUI's
-- three-panel frame. Every number is WORKING_SOURCE from DF-main --
-- Mixin/UI.mixin.lua ChangeTalentsEra (window 646x468, inset 4/60/6/26),
-- XML/Talents.xml DFPlayerTalentFramePanelTemplate (panel 208x376, background
-- pieces, header, icon, name) and Mixin/Talents.mixin.lua Refresh (grid
-- 20/52 with a 46 pitch, 37-unit buttons scaled to 30, branch/arrow cells).
--
-- The tree background is the client's own Interface\TalentFrame art
-- (knowledge.json / talent.tab_info_background_textures, BEHAVIOR_VERIFIED).
-- The branch, arrow, slot and rank-border paths are the stock files DF-main's
-- templates name; they are not runtime-verified here, and a missing texture
-- is invisible rather than an error (textures.gettexture_echoes_missing_path).
M.modernWow.talents = {
  texture = {
    backgroundBase = "Interface\\TalentFrame\\",
    branches   = M.modernWow.path .. "ui\\talents\\talent-branches",
    iconBorder = M.modernWow.path .. "ui\\golden-square-border",
    pointsBackground = M.modernWow.texture.portraitBackground,
    roleIcons  = M.modernWow.path .. "ui\\talents\\role-icons",
    arrows     = M.modernWow.path .. "ui\\talents\\talent-arrows",
    talentFrameParts = M.modernWow.path .. "ui\\talents\\talent-frame-parts",
    slot       = "Interface\\Buttons\\UI-EmptySlot-White",
    rankBorder = "Interface\\TalentFrame\\TalentFrame-RankBorder",
    highlight  = "Interface\\Buttons\\ButtonHilight-Square",
    metalCorners    = M.modernWow.path .. "ui\\frame\\metal-corners",
    metalHorizontal = M.modernWow.path .. "ui\\frame\\metal-horizontal",
    metalVertical   = M.modernWow.path .. "ui\\frame\\metal-vertical",
    backgroundRock  = M.modernWow.path .. "ui\\frame\\background-rock",
    topStreak       = M.modernWow.path .. "ui\\frame\\top-streak",
    portraitRing    = M.modernWow.path .. "ui\\frame\\portrait-ring",
    panelBorder = {
      topLeft    = M.modernWow.path .. "ui\\borders\\thin-border-top-left",
      top        = M.modernWow.path .. "ui\\borders\\thin-border-top",
      topRight   = M.modernWow.path .. "ui\\borders\\thin-border-top-right",
      left       = M.modernWow.path .. "ui\\borders\\thin-border-left",
      right      = M.modernWow.path .. "ui\\borders\\thin-border-right",
      bottomLeft = M.modernWow.path .. "ui\\borders\\thin-border-bottom-left",
      bottom     = M.modernWow.path .. "ui\\borders\\thin-border-bottom",
    },
  },
  design = { width = 646, height = 468 },
  inset = { left = 4, top = 60, right = 6, bottom = 26 },
  insetColor = { 0.02, 0.02, 0.02, 0.85 },
  -- DF-main window chrome, all offsets from the window's own corners:
  -- ButtonFrameTemplateNoPortrait (nine-slice metal), FrameBackgroundSolid
  -- (rock body and title streak) and ChangeTalentsEra (portrait ring).
  -- `x`/`y` follow SetPoint sign (positive y is up).
  frame = {
    body = { left = 3, top = 18, right = 3, bottom = 3 },
    streak = { left = 6, top = 21, right = 2, height = 43,
               texCoord = { 0, 1, 0.0078125, 0.34375 } },
    cornerTopLeft     = { width = 75, height = 74, x = -12, y = 16,
                          texCoord = { 0.00195312, 0.294922, 0.00195312, 0.294922 } },
    cornerTopRight    = { width = 75, height = 74, x = 4, y = 16,
                          texCoord = { 0.298828, 0.591797, 0.00195312, 0.294922 } },
    cornerBottomLeft  = { width = 32, height = 32, x = -12, y = -3,
                          texCoord = { 0.298828, 0.423828, 0.298828, 0.423828 } },
    cornerBottomRight = { width = 32, height = 32, x = 4, y = -3,
                          texCoord = { 0.427734, 0.552734, 0.298828, 0.423828 } },
    edgeTop    = { height = 74, texCoord = { 0, 1, 0.00390625, 0.589844 } },
    edgeBottom = { height = 32, texCoord = { 0, 0.5, 0.597656, 0.847656 } },
    edgeLeft   = { width = 75, texCoord = { 0.00195312, 0.294922, 0, 1 } },
    edgeRight  = { width = 75, texCoord = { 0.298828, 0.591797, 0, 1 } },
    -- 62x62 portrait at (-5, 7) in an 84x84 ring; the ring's 8-argument
    -- SetTexCoord in DF-main is this plain square crop.
    portrait = { size = 62, x = -5, y = 7, ring = 84,
                 ringTexCoord = { 0.0078125, 0.6171875, 0.0078125, 0.6171875 } },
  },
  trees = 3,
  panel = {
    width = 208, height = 376, x = 5, y = 3, gap = 1,
    -- DFPlayerTalentFramePanelTemplate inherits InsetFrameTemplate2. That
    -- retail-only template supplies the textured rim around every tree;
    -- without it the parent inset shows through as a black separator. The
    -- ThinBorder sources are 32px canvases authored to draw at 16 units.
    border = { size = 16 },
  },
  -- BgTopLeft 198x256 and BgBottomLeft 198x75, cropped to the tree art's
  -- painted columns; the TopRight/BottomRight pieces stay unused as in DF-main.
  background = {
    x = 5, y = 40, width = 198, topHeight = 256, bottomHeight = 75,
    topTexCoord = { 0.19921875, 0.97265625, 0, 1 },
    bottomTexCoord = { 0.19921875, 0.97265625, 0, 0.4140625 },
    ruleAlpha = 0.25,
    -- Optional lift: an identical copy of the art drawn over it with ADD
    -- blending at this alpha (0 = off, 1 = double brightness). Off: the dark
    -- look came from the inset bed covering the art, not the art itself, and
    -- the user preferred the plain art (2026-09-14).
    brighten = 0,
  },
  -- Blizzard TalentHeader templates inherited by DF-main. The parchment, rim and
  -- point-circle cells come from the shipped 256x512 TalentFrame-Parts atlas;
  -- DF-main applies the exact TALENT_INFO colour directly to the parchment cell.
  --
  -- LOCKED (user-approved in game, 2026-09-14, matched against a DF-main
  -- screenshot): the band is the dark parchment cell (`texCoord`) vertex
  -- coloured with the tree's exact `treeColor` value at full strength, under
  -- the uncoloured gold rim (`borderTexCoord`) and portrait-ring points ring. There is
  -- deliberately no tint/alpha multiplier. Both a flat fill at full colour and a
  -- flat fill dimmed to 0.45 / 0.9 were rejected as not looking like DF-main.
  -- The icon frame is the user-supplied ui/golden-square-border instead of
  -- DF-main's PrimaryIconBorder cell (user request, 2026-09-14).
  header = {
    x = 5, y = 5, width = 198, height = 33,
    texCoord = { 0.00390625, 0.77734375, 0.546875, 0.61132813 },
    borderTexCoord = { 0.00390625, 0.77734375, 0.61523438, 0.67968750 },
    iconX = 1, iconY = 1, iconSize = 32,
    -- golden-square-border.tga: 256x256 canvas whose transparent opening
    -- (alpha > 128) spans x 32-223, y 30-220. The frame is scaled so that
    -- opening exactly fits the icon, then offset by the scaled ring.
    iconBorder = { canvas = 256, left = 32, top = 30, right = 224, bottom = 221 },
    -- Spent-points ring: ui/frame/portrait-ring (texture.portraitRing) with the
    -- window portrait's measured square crop (frame.portrait.ringTexCoord),
    -- in DF-main's PointCircle-Gold slot, 23x23 at icon BOTTOMRIGHT (10, -6).
    -- Replaces the atlas point circle (user request, 2026-09-14).
    pointsSize = 23, pointsX = 10, pointsY = -6,
    -- Stone disc (texture.pointsBackground) inside that ring, in pixels of the
    -- 156px ring crop. The ring's opaque band runs 14-24 and 128-134 (alpha >
    -- 128); the disc spans band middle to band middle so no gap shows.
    pointsDisc = { crop = 156, left = 19, top = 19, right = 131, bottom = 131 },
    -- Count text offset from the disc centre, SetPoint sign; lowered 2 (user
    -- request, 2026-09-14).
    pointsTextY = -2,
    nameX = 47, nameY = 9, nameRight = 32,
    -- DFPlayerTalentFrameRoleIconTemplate: 16x16, the first at header TOPRIGHT
    -- (-6, -9), the next 1 unit to its left. Cells of ui/talents/role-icons
    -- (64x16 strip: leader, damage, tank, healer).
    roleIcon = {
      size = 16, x = -6, y = -9, gap = 1,
      cells = {
        DAMAGER = { 0.25, 0.5, 0, 1 },
        TANK    = { 0.5, 0.75, 0, 1 },
        HEALER  = { 0.75, 1, 0, 1 },
      },
    },
  },
  grid = { left = 20, top = 52, pitch = 46, button = 30, designButton = 37,
           rows = 11, columns = 4 },
  slot = { size = 64 },
  rankBorder = { size = 32, x = 0, y = 0 },
  pointsPerTier = 5,
  firstTalentLevel = 10,
  maxLevel = 60,
  -- DF-main's -5, lowered 2 to sit centred in the header bar (user request,
  -- 2026-09-14).
  title = { y = 7 },
  status = { y = 36 },
  -- UIPanelCloseButton: 24x24 at TOPRIGHT (1, 0).
  close = { size = 24, x = -1, y = 0 },
  dragInset = 40,

  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  statusColor = { 1.00, 1.00, 1.00, 1.00 },
  nameColor = { 1.00, 0.82, 0.00, 1.00 },
  pointsColor = { 1.00, 1.00, 1.00, 1.00 },
  -- Rank text and slot tint: green while learnable and not maxed, gold at max,
  -- grey when locked (DF-main GREEN/NORMAL/GRAY_FONT_COLOR).
  rankColor = {
    normal    = { 1.00, 0.82, 0.00, 1.00 },
    available = { 0.10, 1.00, 0.10, 1.00 },
    maxed     = { 1.00, 0.82, 0.00, 1.00 },
    disabled  = { 0.50, 0.50, 0.50, 1.00 },
  },

  -- DF-main TALENT_BRANCH_TEXTURECOORDS / TALENT_ARROW_TEXTURECOORDS, keyed
  -- 1 = requirements met, -1 = not met.
  branchCoords = {
    up = { [1] = { 0.12890625, 0.25390625, 0, 0.484375 }, [-1] = { 0.12890625, 0.25390625, 0.515625, 1.0 } },
    down = { [1] = { 0, 0.125, 0, 0.484375 }, [-1] = { 0, 0.125, 0.515625, 1.0 } },
    left = { [1] = { 0.2578125, 0.3828125, 0, 0.5 }, [-1] = { 0.2578125, 0.3828125, 0.5, 1.0 } },
    right = { [1] = { 0.2578125, 0.3828125, 0, 0.5 }, [-1] = { 0.2578125, 0.3828125, 0.5, 1.0 } },
    topright = { [1] = { 0.515625, 0.640625, 0, 0.5 }, [-1] = { 0.515625, 0.640625, 0.5, 1.0 } },
    topleft = { [1] = { 0.640625, 0.515625, 0, 0.5 }, [-1] = { 0.640625, 0.515625, 0.5, 1.0 } },
    bottomright = { [1] = { 0.38671875, 0.51171875, 0, 0.5 }, [-1] = { 0.38671875, 0.51171875, 0.5, 1.0 } },
    bottomleft = { [1] = { 0.51171875, 0.38671875, 0, 0.5 }, [-1] = { 0.51171875, 0.38671875, 0.5, 1.0 } },
    tdown = { [1] = { 0.64453125, 0.76953125, 0, 0.5 }, [-1] = { 0.64453125, 0.76953125, 0.5, 1.0 } },
    tup = { [1] = { 0.7734375, 0.8984375, 0, 0.5 }, [-1] = { 0.7734375, 0.8984375, 0.5, 1.0 } },
  },
  arrowCoords = {
    top = { [1] = { 0, 0.5, 0, 0.5 }, [-1] = { 0, 0.5, 0.5, 1.0 } },
    right = { [1] = { 1.0, 0.5, 0, 0.5 }, [-1] = { 1.0, 0.5, 0.5, 1.0 } },
    left = { [1] = { 0.5, 1.0, 0, 0.5 }, [-1] = { 0.5, 1.0, 0.5, 1.0 } },
  },

  -- DF-main TALENT_INFO colours (Mixin/Talents.mixin.lua), copied verbatim for
  -- every class and tree; keep them identical to that table. Keyed by the
  -- tree's background file because
  -- this client's tab order differs from DF-main's (MageFire is tab 1). Mage
  -- and Priest names are seen in game; the rest are the stock 1.12 file names.
  -- Matching ignores case, any path and any -TopLeft/extension suffix; only a
  -- name matching nothing falls back to `defaultColor` by tab index.
  defaultColor = {
    { 1.0, 0.72, 0.1 },
    { 1.0, 0.0, 0.0 },
    { 0.3, 0.5, 1.0 },
  },
  treeColor = {
    DruidBalance = { 0.8, 0.3, 0.8 },
    DruidFeralCombat = { 1.0, 0.0, 0.0 },
    DruidRestoration = { 0.4, 0.8, 0.2 },
    HunterBeastMastery = { 1.0, 0.0, 0.3 },
    HunterMarksmanship = { 0.3, 0.6, 1.0 },
    HunterSurvival = { 1.0, 0.6, 0.0 },
    MageArcane = { 0.7, 0.2, 1.0 },
    MageFire = { 1.0, 0.5, 0.0 },
    MageFrost = { 0.3, 0.6, 1.0 },
    PaladinHoly = { 1.0, 0.5, 0.0 },
    PaladinProtection = { 0.3, 0.5, 1.0 },
    PaladinCombat = { 1.0, 0.0, 0.0 },
    PriestDiscipline = { 1.0, 0.5, 0.0 },
    PriestHoly = { 0.6, 0.6, 1.0 },
    PriestShadow = { 0.7, 0.4, 0.8 },
    RogueAssassination = { 0.5, 0.8, 0.5 },
    RogueCombat = { 1.0, 0.5, 0.0 },
    RogueSubtlety = { 0.3, 0.5, 1.0 },
    ShamanElementalCombat = { 0.8, 0.2, 0.8 },
    ShamanEnhancement = { 0.3, 0.5, 1.0 },
    ShamanRestoration = { 0.2, 0.8, 0.4 },
    WarlockCurses = { 0.0, 1.0, 0.6 },
    WarlockSummoning = { 1.0, 0.0, 0.0 },
    WarlockDestruction = { 1.0, 0.5, 0.0 },
    WarriorArms = { 1.0, 0.72, 0.1 },
    WarriorFury = { 1.0, 0.0, 0.0 },
    WarriorProtection = { 0.3, 0.5, 1.0 },
    -- The same DF-main colours under the other file names a tree's art is
    -- known by, so a client that renamed a background still resolves to its
    -- own tree colour rather than the by-index default.
    DruidFeral = { 1.0, 0.0, 0.0 },
    PaladinRetribution = { 1.0, 0.0, 0.0 },
    ShamanElemental = { 0.8, 0.2, 0.8 },
    WarlockAffliction = { 0.0, 1.0, 0.6 },
    WarlockDemonology = { 1.0, 0.0, 0.0 },
  },

  -- DF-main PlayerClassRoleTable (Mixin/Talents.mixin.lua), non-SoD values,
  -- keyed by background file like `treeColor` and matched the same way. List
  -- order is DF-main's: with two roles it swaps them, so the first entry is
  -- drawn left of the second (Feral: damage, then tank at the far right).
  treeRoles = {
    DruidBalance = { "DAMAGER" },
    DruidFeralCombat = { "DAMAGER", "TANK" },
    DruidRestoration = { "HEALER" },
    HunterBeastMastery = { "DAMAGER" },
    HunterMarksmanship = { "DAMAGER" },
    HunterSurvival = { "DAMAGER" },
    MageArcane = { "DAMAGER" },
    MageFire = { "DAMAGER" },
    MageFrost = { "DAMAGER" },
    PaladinHoly = { "HEALER" },
    PaladinProtection = { "TANK" },
    PaladinCombat = { "DAMAGER" },
    PriestDiscipline = { "HEALER" },
    PriestHoly = { "HEALER" },
    PriestShadow = { "DAMAGER" },
    RogueAssassination = { "DAMAGER" },
    RogueCombat = { "DAMAGER" },
    RogueSubtlety = { "DAMAGER" },
    ShamanElementalCombat = { "DAMAGER" },
    ShamanEnhancement = { "DAMAGER" },
    ShamanRestoration = { "HEALER" },
    WarlockCurses = { "DAMAGER" },
    WarlockSummoning = { "DAMAGER" },
    WarlockDestruction = { "DAMAGER" },
    WarriorArms = { "DAMAGER" },
    WarriorFury = { "DAMAGER" },
    WarriorProtection = { "TANK" },
    DruidFeral = { "DAMAGER", "TANK" },
    PaladinRetribution = { "DAMAGER" },
    ShamanElemental = { "DAMAGER" },
    WarlockAffliction = { "DAMAGER" },
    WarlockDemonology = { "DAMAGER" },
  },
}

-- Profession window (modules/professions.lua): WoW-DragonflightUI's
-- DFProfessionFrame rebuilt over the client's TradeSkillFrame and CraftFrame.
-- Every number is WORKING_SOURCE from DF-main XML/ProfessionFrame.xml and
-- Mixin/ProfessionFrame.mixin.lua (window 778x525, recipe list 274 wide at
-- (5, -72), schematic form from the list's right edge +2 to (-5, 33), rank
-- frame 453x18 at (280, -40), 80x22 create buttons at (-9, 7)). The window
-- chrome is the talent window's, which is the same DF-main
-- ButtonFrameTemplateNoPortrait.
--
-- `cells` are DF-main's own TexCoords on professions.tga converted to texels
-- ({ left, top, right, bottom } on the 2048x1024 atlas) and checked against a
-- composite of the file; `slot` was measured off its alpha: the silver frame's
-- opaque rim surrounds a transparent opening at `slotOpening`.
-- The Quest Log count boxes share the talent panels' ThinBorder rim.
M.modernWow.questLog.countBox.border = M.modernWow.talents.texture.panelBorder

M.modernWow.professions = {
  texture = {
    atlas = M.modernWow.path .. "ui\\profession\\professions",
    thinBorder = M.modernWow.talents.texture.panelBorder,
    metalCorners = M.modernWow.talents.texture.metalCorners,
    metalHorizontal = M.modernWow.talents.texture.metalHorizontal,
    metalVertical = M.modernWow.talents.texture.metalVertical,
    backgroundRock = M.modernWow.talents.texture.backgroundRock,
    topStreak = M.modernWow.talents.texture.topStreak,
    portraitRing = M.modernWow.talents.texture.portraitRing,
    portraitBackground = M.modernWow.texture.portraitBackground,
    -- Stock UIPanelScrollBarTemplate faces. The Modern WoW design contract
    -- keeps the client's own scrollbar art; these are the 1.12 FrameXML file
    -- names, not runtime-verified here, and a missing file is invisible
    -- rather than an error (textures.gettexture_echoes_missing_path).
    scrollUp = {
      normal   = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up",
      pushed   = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down",
      disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled",
      highlight = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight",
    },
    scrollDown = {
      normal   = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",
      pushed   = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down",
      disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled",
      highlight = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight",
    },
    scrollKnob = "Interface\\Buttons\\UI-ScrollBar-Knob",
    missingIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
    beastTrainingIcon = "Interface\\Icons\\Ability_Hunter_BeastCall02",
  },
  -- Recipe-detail backgrounds and rank-bar fills by profession key (the keys
  -- modules/spellbookprofessions.lua resolves skill-line names to). DF-main's
  -- professionDataTable: First Aid draws the generic art with the alchemy
  -- fill, Poisons the alchemy pair, Beast Training the generic art with the
  -- skinning fill.
  art = {
    default = M.modernWow.path .. "ui\\profession\\background-art",
    alchemy = M.modernWow.path .. "ui\\profession\\background-art-alchemy",
    blacksmithing = M.modernWow.path .. "ui\\profession\\background-art-blacksmithing",
    cooking = M.modernWow.path .. "ui\\profession\\background-art-cooking",
    enchanting = M.modernWow.path .. "ui\\profession\\background-art-enchanting",
    engineering = M.modernWow.path .. "ui\\profession\\background-art-engineering",
    leatherworking = M.modernWow.path .. "ui\\profession\\background-art-leatherworking",
    mining = M.modernWow.path .. "ui\\profession\\background-art-mining",
    tailoring = M.modernWow.path .. "ui\\profession\\background-art-tailoring",
    poisons = M.modernWow.path .. "ui\\profession\\background-art-alchemy",
  },
  fx = {
    default = M.modernWow.path .. "ui\\profession\\fx-alchemy",
    alchemy = M.modernWow.path .. "ui\\profession\\fx-alchemy",
    blacksmithing = M.modernWow.path .. "ui\\profession\\fx-blacksmithing",
    cooking = M.modernWow.path .. "ui\\profession\\fx-cooking",
    enchanting = M.modernWow.path .. "ui\\profession\\fx-enchanting",
    engineering = M.modernWow.path .. "ui\\profession\\fx-engineering",
    leatherworking = M.modernWow.path .. "ui\\profession\\fx-leatherworking",
    mining = M.modernWow.path .. "ui\\profession\\fx-mining",
    tailoring = M.modernWow.path .. "ui\\profession\\fx-tailoring",
    poisons = M.modernWow.path .. "ui\\profession\\fx-alchemy",
    beasttraining = M.modernWow.path .. "ui\\profession\\fx-skinning",
  },
  -- The painted part of each 1024x1024 background (DF-main's TexCoords
  -- 0.000976562-0.660156 x 0.000976562-0.536133). It is cropped, never
  -- squeezed, to the schematic form's aspect, keeping its right edge where
  -- DF-main's art carries the profession emblem.
  artCanvas = 1024,
  artRect = { left = 1, top = 1, right = 676, bottom = 549 },

  atlas = { width = 2048, height = 1024 },
  cells = {
    listBackground = { left = 1,    top = 79,  right = 269,  bottom = 651 },
    rankBackground = { left = 611,  top = 769, right = 1062, bottom = 798 },
    rankBorder     = { left = 1359, top = 133, right = 1810, bottom = 162 },
    headerLeft     = { left = 885,  top = 28,  right = 899,  bottom = 54 },
    headerMiddle   = { left = 709,  top = 43,  right = 710,  bottom = 69 },
    headerRight    = { left = 932,  top = 46,  right = 946,  bottom = 72 },
    collapsed      = { left = 619,  top = 55,  right = 641,  bottom = 71 },
    expanded       = { left = 554,  top = 55,  right = 576,  bottom = 71 },
    skillEasy      = { left = 524,  top = 55,  right = 537,  bottom = 70 },
    skillMedium    = { left = 604,  top = 55,  right = 617,  bottom = 70 },
    skillOptimal   = { left = 539,  top = 55,  right = 552,  bottom = 70 },
    selected       = { left = 1614, top = 39,  right = 1881, bottom = 58 },
    highlight      = { left = 1275, top = 39,  right = 1584, bottom = 60 },
    slot           = { left = 272,  top = 420, right = 370,  bottom = 518 },
  },
  slotOpening = { left = 288, top = 436, right = 356, bottom = 503 },

  design = { width = 778, height = 525 },
  frame = M.modernWow.talents.frame,
  -- Profession icon in DF-main's 62x62 portrait slot. This client has no
  -- circular mask, so a square icon sits inside the ring's opening over the
  -- stone disc, small enough that its corners stay under the gold band.
  portrait = { iconSize = 44, discSize = 56 },
  title = { y = 7 },
  close = { size = 24, x = -1, y = 0 },
  drag = { headerHeight = 60, headerInset = 40 },
  -- Frame levels above the host window: the cover hides every native child
  -- of the host, the rim draws the metal over the panels, and the drag handle
  -- and close button stay above both.
  levels = { cover = 10, panel = 1, rim = 6, handle = 10 },

  rank = { x = 280, y = 40, width = 451, height = 29,
           fillX = 5, fillY = 3, fillWidth = 441, fillHeight = 18 },

  list = { x = 5, y = 72, width = 274, bottom = 5,
           rowLeft = 8, rowTop = 10, rowRight = 20, rowBottom = 8 },
  header = { height = 25, pieceWidth = 14, pieceHeight = 26, lift = 2,
             labelX = 10,
             -- Label offset from the row centre (SetPoint sign). DF-main's +2
             -- lift sat the text on the bar's top edge here (user screenshot,
             -- 2026-09-15), so it is lowered onto the bar.
             labelY = -3, collapseWidth = 11, collapseHeight = 8,
             collapseRight = 10 },
  recipe = { height = 20, iconX = 4, iconWidth = 13, iconHeight = 15,
             labelX = 21, countGap = 2, padding = 10,
             selectedWidth = 267, selectedHeight = 19,
             highlightWidth = 309, highlightHeight = 21, highlightAlpha = 0.5 },
  scroll = { width = 16, button = 16, knobWidth = 18, knobHeight = 24,
             right = 3, trackAlpha = 0.35,
             buttonTexCoord = { 0.25, 0.75, 0.25, 0.75 },
             knobTexCoord = { 0.20, 0.80, 0.125, 0.875 } },

  schematic = { gap = 2, right = 5, bottom = 33, inset = 28,
                icon = 37, nameGap = 14, lineGap = 4, sectionGap = 12,
                reagentTop = 23, reagentPitch = 60, reagentGap = 6,
                reagentWidth = 180, reagentHeight = 50, reagentIcon = 37,
                reagentTextX = 46, reagentTextWidth = 136,
                reagentColumn = 6, maxReagents = 8 },
  -- The ThinBorder rim DF-main's InsetFrameTemplate draws round both panels.
  border = { size = 16 },

  button = { width = 80, height = 22, right = 9, bottom = 7,
             createAllGap = 86, stepWidth = 23, stepGap = 3,
             countWidth = 30, countGap = 4, capWidth = 12,
             glyphWidth = 11, glyphHeight = 8,
             hoverAlpha = 0.5, disabledAlpha = 0.4, maxCount = 99 },

  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  rankTextColor = { 1.00, 1.00, 1.00, 1.00 },
  headerColor = { 1.00, 0.82, 0.00, 1.00 },
  headerHoverColor = { 1.00, 1.00, 1.00, 1.00 },
  -- DF-main PROFESSION_RECIPE_COLOR; hover is HIGHLIGHT_FONT_COLOR.
  recipeColor = { 0.886, 0.863, 0.839, 1.00 },
  recipeHoverColor = { 1.00, 1.00, 1.00, 1.00 },
  nameColor = { 1.00, 0.82, 0.00, 1.00 },
  labelColor = { 1.00, 0.82, 0.00, 1.00 },
  bodyColor = { 1.00, 1.00, 1.00, 1.00 },
  missingColor = { 0.50, 0.50, 0.50, 1.00 },
  cooldownColor = { 1.00, 0.13, 0.13, 1.00 },
  buttonTextColor = { 1.00, 0.82, 0.00, 1.00 },
  buttonDisabledColor = { 0.50, 0.50, 0.50, 1.00 },
}

-- UnrealQuest-measured three-slice action-button cells in ui/128RedButton.tga
-- (512x2048). Each state combines the left bevel from a short 114x125 button
-- with the middle and right bevel from a 291x125 bar. At runtime the caps keep
-- their source aspect and only the middle stretches, exactly like UQ's three
-- Quest Log actions; stretching one full atlas row distorts both bevels.
M.modernWow.button128Red = {
  atlasWidth = 512,
  atlasHeight = 2048,
  cellHeight = 125,
  barWidth = 291,
  cap = 24,
  height = 30,
  lift = 10,
  normal = { barTop = 523, capLeft = 392, capTop = 913 },
  hover  = { barTop = 783, capLeft = 378, capTop = 1043 },
  -- The grey pair, measured off the file's alpha with the same 2 px / 3 px
  -- lead the cells above use: bar opaque at y 655-774, short button at
  -- x 265-375, y 1045-1164.
  disabled = { barTop = 653, capLeft = 262, capTop = 1043 },
}

-- The gold-rimmed sibling, ui/128GoldRedButton.tga (512x1024), with the same
-- bar/cap geometry. Each state's short button sits on the bar's own row, so
-- capTop equals barTop. Normal and hover are UnrealQuest's cells; the grey
-- row between them is opaque at y 653-777 on the file's alpha (> 8).
M.modernWow.button128GoldRed = {
  atlasWidth = 512,
  atlasHeight = 1024,
  cellHeight = 125,
  barWidth = 291,
  cap = 24,
  normal   = { barTop = 523, capLeft = 296, capTop = 523 },
  hover    = { barTop = 783, capLeft = 296, capTop = 783 },
  disabled = { barTop = 653, capLeft = 296, capTop = 653 },
}

-- Cells in ui/red-button, the octagonal button atlas: a 5x3 grid of 34x38
-- cells on a 256x128 canvas, the first at (2,2), stepping 38 across and 40
-- down. Those numbers are measured from the file's own alpha channel (the
-- occupied column runs are 2-35, 40-73, 78-111, 116-149, 154-187 and the row
-- runs 2-39, 42-79, 82-119), not inferred from the source addon.
--
-- Columns are minimize, close, maximize and minus; rows are normal, disabled
-- and pushed. The minus column breaks that pattern -- its top cell is the
-- shared hover glow and its pushed face sits alone in the fifth column -- so
-- the entries below name what each cell actually is instead of deriving it
-- from the grid. The last two cells of column five are empty.
--
-- Only the close column is drawn today (window close buttons). The rest are
-- kept because they describe one imported file, and a partial map of it would
-- make the grid above unreadable.
do
  local function cell(column, row)
    local left = 2 + 38 * column
    local top = 2 + 40 * row
    return { left / 256, (left + 34) / 256, top / 128, (top + 38) / 128 }
  end

  M.modernWow.redButtonCell = {
    minimizeNormal   = cell(0, 0),
    minimizeDisabled = cell(0, 1),
    minimizePushed   = cell(0, 2),
    closeNormal      = cell(1, 0),
    closeDisabled    = cell(1, 1),
    closePushed      = cell(1, 2),
    maximizeNormal   = cell(2, 0),
    maximizeDisabled = cell(2, 1),
    maximizePushed   = cell(2, 2),
    highlight        = cell(3, 0),
    minusNormal      = cell(3, 1),
    minusDisabled    = cell(3, 2),
    minusPushed      = cell(4, 0),
  }
end

-- Cells in bags/slot-frame, which is DragonflightUI's bagslots2x atlas: six
-- 61px cells on a 512x128 canvas. The five the HUD bag bar draws are the empty
-- slot face, the gold rim laid over an equipped bag's icon, the hover/checked
-- ring, and the keyring's own face and rim.
--
-- WORKING_SOURCE: these are DragonflightUI's own coordinates for this exact
-- atlas (modules/bags/bags.lua Setup:SmallBags and Setup:KeyRing), not
-- measurements taken here. They live centrally because a module may not slice
-- shared media itself (rules/unreal-ui.md, shared media placement).
M.modernWow.bagCell = {
  slot      = { 0.576172, 0.695312, 0.5,       0.976562 },
  border    = { 0.576172, 0.695312, 0.0078125, 0.484375 },
  highlight = { 0.699219, 0.818359, 0.0078125, 0.484375 },
  keySlot   = { 0.822266, 0.941406, 0.0078125, 0.484375 },
  keyBorder = { 0.699219, 0.818359, 0.5,       0.976562 },
}

-- The Character window's three stat group boxes, DragonflightUI style: the
-- stock rounded boxes darkened. Drawn with the client's own tooltip edge and
-- a dark fill; `border` is DF's 0.4 darken. `margin` grows the stats rect out
-- to the box edges, `gap` separates boxes, and `split` is where the attribute
-- column ends as a fraction of the stats width. Melee and ranged share the
-- right column half and half.
--
-- `statsRect` is only a fallback for when CharacterAttributesFrame's position
-- cannot be read at build: the stock Vanilla layout (TOPLEFT 67,-291, 230x78),
-- not a measurement on this client.
M.modernWow.statBoxes = {
  background = "Interface\\Tooltips\\UI-Tooltip-Background",
  edge = "Interface\\Tooltips\\UI-Tooltip-Border",
  tileSize = 16,
  edgeSize = 16,
  inset = 4,
  fill = { 0, 0, 0, 0.8 },
  border = { 0.4, 0.4, 0.4, 1 },
  split = 0.5,
  -- Each box's outer edges, in units, fitted so the stock text sits ~5 units
  -- (~9 px at the tested scale) inside every edge. Measured off an in-game
  -- screenshot at ~1.8 px/unit (the 13-unit stat row pitch), not read from
  -- the text itself, so retune here if the stat layout changes.
  --   attributes: left/top from the rect's left/top, right from the column
  --     split, bottom from the rect's bottom.
  --   melee: left from the split, top from the rect's top, right from the
  --     rect's right, bottom from the rect's vertical middle.
  --   ranged: left from the split, top from the middle, right from the rect's
  --     right, bottom from the rect's bottom.
  -- Positive is right / down.
  edges = {
    attributes = { left = -3, top = -5, right = 0, bottom = 10 },
    melee      = { left = 0,  top = -7, right = 4, bottom = 5 },
    ranged     = { left = 0,  top = -1, right = 4, bottom = 9 },
  },
  -- Units the attribute values (Strength..Armor) move from their stock point.
  valueShift = -5,
  statsRect = { left = 67, top = 291, width = 230, height = 78 },
}

-- Attribute value FontStrings (Strength, Agility, Stamina, Intellect, Spirit,
-- Armor) shifted by `valueShift`. The names are the stock FrameXML globals,
-- present in this client's global dump
-- (runtime-reports/UnrealRuntimeProbe-2026-08-16-invalid.lua); their anchors
-- were not recorded there. A missing name is skipped.
M.modernWow.statValues = {
  "CharacterStatFrame1StatText", "CharacterStatFrame2StatText",
  "CharacterStatFrame3StatText", "CharacterStatFrame4StatText",
  "CharacterStatFrame5StatText", "CharacterArmorFrameStatText",
}

-- The Character title dropdown (the "None" selector under the name) moves this
-- far from its stock point; positive is right / up. The global name comes from
-- UnrealPfUI's character skin (WORKING_SOURCE) and is absent from the
-- 2026-08-16 global dump, so a missing frame is skipped.
M.modernWow.titleDropDown = { name = "PlayerTitleDropDown", x = -15, y = -15 }

-- "<class> Level <n>" centred across the Character interface, immediately
-- below the header name. `top` is its distance below the window's top edge;
-- `levelAbove` lifts its holder frame over the window's own content.
M.modernWow.characterLevelLine = {
  top = 46, levelAbove = 10,
}

-- Character gear slots: the four diamond-stud corners of the user-supplied
-- ui/character-create-diamond-metal atlas (512x2048, 8x art), one per slot
-- corner. `corners` is each piece's bar-centreline intersection in atlas
-- pixels, measured off its alpha: vertical bars span x 44-92 / 165-213, and
-- horizontal bars y 681-721 (BL), 939-979 (BR), 1084-1124 (TL), 1342-1382 (TR).
-- Each corner keeps `outer` px beyond the centreline (the stud) and reaches
-- inward to the slot's midpoint, capped at `arm` px (the drawn arm length).
-- `artScale` is units per atlas px on a `designSlot` button, and the
-- centreline sits `lineOffset` units outside the slot edge; both scale with
-- the slot. `hover` is the stock ItemButtonTemplate highlight. The metal is
-- never tinted: rarity draws `glowTexture` (the action-button glow) in the
-- item's quality colour at `glowAlpha`, `glowGrow` units larger than the slot
-- and centred on it, above the metal; hidden for common and empty slots.
M.modernWow.gearSlot = {
  frame = M.modernWow.path .. "ui\\character-create-diamond-metal",
  hover = "Interface\\Buttons\\ButtonHilight-Square",
  glowTexture = M.modernWow.texture.actionButtonHover,
  glowGrow = 0,
  glowAlpha = 0.8,
  atlasWidth = 512,
  atlasHeight = 2048,
  designSlot = 37,
  artScale = 0.11,
  lineOffset = 0,
  outer = 52,
  arm = 184,
  corners = {
    { point = "TOPLEFT",     x = 68,  y = 1104, h = -1, v = 1 },
    { point = "TOPRIGHT",    x = 189, y = 1362, h = 1,  v = 1 },
    { point = "BOTTOMLEFT",  x = 68,  y = 701,  h = -1, v = -1 },
    { point = "BOTTOMRIGHT", x = 189, y = 959,  h = 1,  v = -1 },
  },
  shade = 1,
}

-- Window frame built from the same ui/character-create-diamond-metal atlas,
-- first drawn on the game menu. Measured off the file's alpha and luminance:
--   * `corners` are the four stud pieces' bar-centreline intersections (the
--     same points as gearSlot.corners). Each piece keeps `outer` px past the
--     centreline and `arm` px inward (the drawn arms end 184-185 px in).
--   * `top`/`bottom` are slices of the two full-width bars: bar y 304-356
--     matches the top corners' horizontal arms, bar y 159-211 the bottom
--     ones. Both run the full 512 px; the slice skips their ends.
--   * `left`/`right` are slices of the TL / TR pieces' vertical arms below
--     the joint (x 38-98 and 159-219, arms ending at y 1289 and 1547).
-- Every slice is centred on its bar centreline, so half its thickness is its
-- centre. `scale` is units per atlas px; the centreline sits `inset` units
-- inside the frame edge, and `fill` is the translucent bed drawn inside it.
M.modernWow.metalFrame = {
  path = M.modernWow.gearSlot.frame,
  atlasWidth = 512,
  atlasHeight = 2048,
  scale = 0.12,
  inset = 5,
  outer = 52,
  arm = 120,
  fill = { 0.03, 0.03, 0.03, 0.78 },
  corners = {
    { point = "TOPLEFT",     x = 68,  y = 1104, h = -1, v = 1 },
    { point = "TOPRIGHT",    x = 189, y = 1362, h = 1,  v = 1 },
    { point = "BOTTOMLEFT",  x = 68,  y = 701,  h = -1, v = -1 },
    { point = "BOTTOMRIGHT", x = 189, y = 959,  h = 1,  v = -1 },
  },
  top    = { u1 = 64,  u2 = 448, v1 = 304,  v2 = 356 },
  bottom = { u1 = 64,  u2 = 448, v1 = 159,  v2 = 211 },
  left   = { u1 = 38,  u2 = 98,  v1 = 1190, v2 = 1280 },
  right  = { u1 = 159, u2 = 219, v1 = 1450, v2 = 1540 },
}

-- The Modern WoW game menu window (modules/gamemenu.lua), in units. Rows are
-- `buttonWidth` x `buttonHeight` 128RedButton faces centred in a `width`
-- window; the first starts `top` below the window top, `spacing` separates
-- rows and `groupSpacing` the client's own group breaks. The title sits
-- `titleY` below the top edge in the warm gold the theme allows for short
-- titles; `labelY` nudges row labels onto the face's bevelled centre.
M.modernWow.gameMenu = {
  width = 250,
  buttonWidth = 190,
  buttonHeight = 30,
  top = 42,
  bottom = 22,
  -- Both gaps 3 units tighter by user request (2026-09-13); a negative
  -- spacing lets the faces' transparent padding overlap.
  spacing = -0.5,
  groupSpacing = 5,
  titleY = -17,
  titleColor = { 1, 0.82, 0, 1 },
  labelY = -2,
}

-- Red-button size on the Modern WoW "Resurrect now?" popup, also used by the
-- logout/quit popups so both match (modules/logout.lua).
-- The native popup button is too small for the 128RedButton face; this is the
-- size the owned resurrect dialog used, kept by user request (2026-09-14).
-- A pair of buttons is narrowed to fit: `sideInset` keeps each clear of the
-- metal frame's side, `pairGap` is the client's spacing between the two.
M.modernWow.corpsePopupButton = {
  width = 150,
  height = 30,
  sideInset = 18,
  pairGap = 19,
}

-- The shared confirm dialog's Modern WoW instance (core/widgets.lua,
-- U.ShowConfirm with options.modernWow): metalFrame housing, corpsePopupButton
-- pair. Wider and taller than the flat 280x100 panel so the detail line and
-- the 30-unit red buttons stay inside the metal sides.
-- `width` is 15% over the first 320 (user request, 2026-09-15: the buttons ran
-- past the metal sides); `buttonWidth` keeps the buttons at the size they had.
M.modernWow.confirmDialog = {
  width = 368,
  height = 110,
  buttonWidth = 132,
  buttonBottom = 16,
}

-- DragonflightUI-Reforged's XP/reputation bar recipe. The source uses the
-- same shaded fill and mirrored border-half art for both bars; only their
-- semantic fill colours differ. Geometry is expressed relative to the owning
-- bar so modules/xpbar.lua can keep UnrealUI's configurable dimensions.
-- WORKING_SOURCE: modules/xprep/xprep.lua (Setup:XPBar / Setup:RepBar).
M.modernWow.xpbar = {
  background = { 0.10, 0.10, 0.10, 0.80 },
  xp = { 0.85, 0.40, 0.85, 1.00 },
  rested = { 0.20, 0.50, 0.90, 1.00 },
  borderWidthExtra = 3,
  borderHeightExtra = 9,
  borderOverhang = 2,
  fillTopOverhang = 1,
  barSeparation = 20,
  reputation = {
    [1] = { 0.80, 0.00, 0.00, 1.00 },
    [2] = { 0.80, 0.00, 0.00, 1.00 },
    [3] = { 0.80, 0.30, 0.00, 1.00 },
    [4] = { 1.00, 0.82, 0.00, 1.00 },
    [5] = { 0.00, 0.60, 0.10, 1.00 },
    [6] = { 0.00, 0.70, 0.10, 1.00 },
    [7] = { 0.00, 0.80, 0.10, 1.00 },
    [8] = { 0.00, 0.80, 0.50, 1.00 },
  },
}

-- Micro-bar glyphs, keyed by the UnrealUI button they belong to rather than by
-- the source's glyph names, with one entry per interaction state. Kept as a
-- table because the micro-bar surface will look these up by button id and
-- state, which a flat list of 31 token names cannot serve.
M.modernWow.micro = {}
M.modernWow.microOrder = {
  "menu", "character", "spellbook", "talents", "quest", "log",
  "social", "guild", "pet", "help",
}
do
  local microIndex
  for microIndex = 1, table.getn(M.modernWow.microOrder) do
    local id = M.modernWow.microOrder[microIndex]
    M.modernWow.micro[id] = {
      normal    = M.modernWow.path .. "microbar\\" .. id,
      highlight = M.modernWow.path .. "microbar\\" .. id .. "-highlight",
      faded     = M.modernWow.path .. "microbar\\" .. id .. "-faded",
    }
  end
  -- The one disabled state the source ships.
  M.modernWow.micro.talents.disabled =
    M.modernWow.path .. "microbar\\talents-disabled"
end

-- Class-portrait cells in ui/class-portraits, which is the stock
-- UI-Classes-Circles layout: a 256x256 atlas of 64px cells, four per row,
-- nine classes plus one unused tenth. Kept here rather than relying on a
-- CLASS_ICON_TCOORDS global, which query_compat.py has no record of at all on
-- this client.
--
-- Keyed by the unlocalised token UnitClass returns second
-- (knowledge.json / unit.race_class_return_numeric_id confirms this client
-- returns three values, and modules/unitframes.lua already reads the token).
-- A token with no entry draws no portrait rather than the wrong class.
-- These are the authentic Blizzard CLASS_ICON_TCOORDS values, not clean
-- quarters: the atlas cells are inset a fraction of a pixel to stop the
-- neighbouring icon bleeding in along the seam. DragonflightUI carries the
-- same numbers for the same art (modules/unit/player.lua), which is
-- WORKING_SOURCE confirmation of the spelling rather than runtime evidence.
-- The tenth cell is the Death Knight slot this 1.12-era art still ships.
M.modernWow.classCell = {
  WARRIOR     = { 0.00,       0.25,       0.00, 0.25 },
  MAGE        = { 0.25,       0.49609375, 0.00, 0.25 },
  ROGUE       = { 0.49609375, 0.7421875,  0.00, 0.25 },
  DRUID       = { 0.7421875,  0.98828125, 0.00, 0.25 },
  HUNTER      = { 0.00,       0.25,       0.25, 0.50 },
  SHAMAN      = { 0.25,       0.49609375, 0.25, 0.50 },
  PRIEST      = { 0.49609375, 0.7421875,  0.25, 0.50 },
  WARLOCK     = { 0.7421875,  0.98828125, 0.25, 0.50 },
  PALADIN     = { 0.00,       0.25,       0.50, 0.75 },
  DEATHKNIGHT = { 0.25,       0.50,       0.50, 0.75 },
}

-- The source interface's own unit-frame layout, as fractions of the 256x128
-- frame art. Taken from DragonflightUI's player module, which positions its
-- bars at fixed pixel offsets inside that art rather than stretching them to a
-- frame (modules/unit/player.lua: health 130x30 at TOPLEFT 100,-29; mana
-- 130x12 at 100,-53; portrait 62x62; name at LEFT 80,25). WORKING_SOURCE:
-- it is a working layout on a 1.12-era client, not runtime evidence here.
--
-- Kept as fractions so the same numbers drive any frame size. Nothing reads
-- this yet -- it is what an art-driven modern-wow unit frame needs, as opposed
-- to the current approach of dressing UnrealUI's own bar boxes, which leaves
-- the housing hidden behind fills that span their whole box.
--
-- Note the art is drawn MIRRORED for the player (portrait left), so these x
-- fractions are already in screen order: bars right, ornament left.
-- All values are in source-art pixels on the 256x128 canvas, in SCREEN order
-- (the art is drawn mirrored so the portrait is on the left), so a layout is
-- one multiply away: screen = (artPixel - contentLeft) * scale.
M.modernWow.sourceLayout = {
  artWidth = 256, artHeight = 128,

  -- DragonflightUI's own bar rectangles.
  barX = 100, barWidth = 130,
  healthY = 29, healthHeight = 30,
  powerY = 53, powerHeight = 12,

  -- The visible extent of the art, which is what the frame is sized to. The
  -- canvas is mostly empty: content runs x12..230 and y2..80 of 256x128. The
  -- left edge is 12 rather than the plain ring's 38 so the wider boss and
  -- rare-elite ornaments still fit without moving anything.
  contentLeft = 12, contentRight = 230,
  contentTop = 2, contentBottom = 80,

  -- Fallback portrait circle, used by any art with no entry in M.modernWow.ring
  -- below.
  circleX = 74, circleY = 43,
  portraitSize = 51,

  -- Which side the ART FILE puts the portrait ring on, as opposed to which
  -- side a given frame reads from. The 256x128 housings are authored ring on
  -- the RIGHT, because DragonflightUI hands them to the client's own
  -- TargetFrame and lets the frame XML flip the player's copy; a frame that
  -- reads portrait-left therefore has to flip the texture. The small pet
  -- canvas below is authored the other way round, so the same reading order
  -- needs the opposite flip -- which is why this is a property of the layout
  -- rather than something derived from the frame's own mirroring.
  authoredRight = true,
}

-- ---------------------------------------------------------------------------
-- The SMALL 128x64 canvas (unitframes/party-frame), in its own art pixels.
--
-- DragonflightUI draws its party rows with this file, not with the large
-- housing: modules/unit/mini.lua Setup:PartyFramesSetup gives every
-- PartyMemberFrame a 128x64 "pet" border, a 35px portrait and 69-wide bars,
-- which is why its party block is roughly half the linear size of its player
-- and target frames. Reproducing that is the whole point of this second
-- layout; the frame art's proportions are fixed, so a party row cannot be the
-- large housing at half scale.
--
-- The bar rectangles are DragonflightUI's own numbers, converted from its
-- CENTER-relative offsets into this canvas's top-left space (its border is
-- centred on the frame, so the frame's centre is the canvas's 64,32):
--
--   health  69x18 at CENTER +15,+10   ->  x 44.5..113.5, y 13..31
--   power   69x7  at CENTER +15,+0.5  ->  x 44.5..113.5, y 28..35
--
-- The two overlap by four rows, exactly as the large layout's do, and for the
-- same reason: each bar is wider than its own opening in the art, and the rim
-- drawn over them is what crops both back to the openings measured down the
-- bar column (opaque at y15..17, y27..28 and y34..36, so health shows through
-- y18..26 and power through y29..33).
--
-- The content box is this file's measured alpha extent (x1..118, y2..47 at an
-- alpha threshold of 8), trimmed by a pixel. Unlike the large layout it needs
-- no outward padding: there are no classification ornaments on this canvas.
-- ---------------------------------------------------------------------------
M.modernWow.partyLayout = {
  artWidth = 128, artHeight = 64,

  barX = 44.5, barWidth = 69,
  healthY = 13, healthHeight = 18,
  powerY = 28, powerHeight = 7,

  contentLeft = 2, contentRight = 118,
  contentTop = 2, contentBottom = 47,

  circleX = 23.5, circleY = 23.5,
  portraitSize = 35,

  -- Text, where this canvas needs its own answer rather than the shared
  -- M.modernWow.text token tuned against the large housing.
  --
  -- headerY: the large art draws a translucent name band ACROSS the top of its
  -- health opening, so its row is pulled down into the bar. This canvas has no
  -- such band -- the opaque rim starts at y15 and the name sits above it, at
  -- DragonflightUI's own CENTER +23 (art y9) -- so the row stays just clear of
  -- the bar's top edge instead.
  --
  -- -5 rather than the -1 that "just clear of the rim" works out to: measured
  -- on screen the row read too high above these small rows, so it comes down
  -- four units onto the canvas's own top edge. Downward, like the shared
  -- token -- BuildHousing anchors the labels BOTTOM-to-TOP of the health bar,
  -- where a positive offset lifts them.
  headerY = -5,
  -- The health readout, down two units from where the shared token puts it.
  -- Downward: BuildHousing adds this to modules/unitframes.lua's own
  -- BAR_LABEL_Y_OFFSET of -2, so a negative value sinks the label further into
  -- the bar. The shared token lifts it by 1 instead, which was tuned against
  -- the 30-unit opening; this canvas's is 18.
  --
  -- 0 is a real value here, not "unset": BuildHousing resolves this with
  -- `tonumber(L.barLabelY) or tonumber(M.modernWow.text.barLabelY)`, and 0 is
  -- truthy in Lua, so the shared token's +1 stays overridden.
  barLabelY = 0,
  -- Proportionally less reserved at the level end: the opening is 69 wide
  -- here against the large layout's 130, so the large 26 would take more than
  -- a third of the row away from the name.
  levelReserve = 18,

  -- Name, level and the health readout all take `normal` rather than the
  -- `small` the large housing's row uses -- one step up the verified size
  -- scale in rules/unreal-ui-design.md, not an arbitrary +1. These rows carry
  -- a single readout each, so the extra point costs no room, and they are read
  -- at a glance from the edge of the screen.
  headerSize = M.fontSize.normal,

  -- One readout, the current value, at the outer end -- which is what
  -- DragonflightUI's party rows show: mini.lua creates a single
  -- partyHealthPercentTexts entry per row and no mana text at all. A 69-wide
  -- opening has no room for the large housing's percentage-and-value pair, and
  -- a 7-unit power opening has none for any text.
  healthLabels = { right = "healthval" },
  healthLabelSize = M.fontSize.normal,
  powerText = false,

  -- This canvas is authored with the ring on the LEFT: DragonflightUI hands it
  -- to PetFrame and PartyMemberFrame, which are portrait-left frames, and puts
  -- the portrait at CENTER -40. So a portrait-left frame draws it as authored.
  authoredRight = false,
}

-- Aura rows use the bar opening as their usable span under this theme. The
-- icon multiplier is relative to the shared aura size, so saved/default aura
-- geometry remains authoritative while modern-wow draws it 20% smaller.
M.modernWow.aura = {
  iconScale = 0.80,
  nameGap = 5,
  -- The below-frame position's own two offsets, applied on top of the bar
  -- opening the above-frame position shares. Neither touches a row drawn above
  -- the frame.
  --
  -- powerGap is clearance BELOW the power readout, so it counts DOWNWARD:
  -- raising it pushes the row away from the frame, lowering it pulls the row
  -- up. The row's top edge lands at art y 66.5 + powerGap, and the housing's
  -- visible gold rim ends at art y 67, so 0 is the tightest value that still
  -- clears the art -- the icons start 1.5 units under the rim. A negative
  -- value tucks them over it.
  --
  -- belowX shifts the row right, positive meaning rightward on screen
  -- whichever way the housing is mirrored: it is added after the mirroring
  -- flip, so the sign never depends on which side the portrait is on.
  powerGap = 0,
  belowX = 4,
}

-- Rogue / Cat Form combo-point atlas (ui/combo-points.tga, 128x56). The two
-- 57x56 cells are separated by fourteen fully transparent columns: the left
-- cell is empty and the right cell is active. Each cell includes one half of
-- the short horizontal join. The points use the requested 1px gap. Their
-- height starts from the Modern WoW aura icon height in
-- modules/unitframes.lua, then `scale` reduces the requested combo treatment
-- by 30%. `aspect` preserves the atlas cell's authored proportions.
M.modernWow.combo = {
  scale = 0.70,
  aspect = 57 / 56,
  gap = 1,
  inactive = { 0 / 128, 57 / 128, 0, 1 },
  active   = { 71 / 128, 1,        0, 1 },
}

-- HoT indicators (modules/hots.lua) on a dressed party row.
--
-- This theme draws them BESIDE the frame instead of on the health bar. The
-- small pet canvas's health opening is 18 units tall and 69 wide, so an icon
-- row large enough to read covers the bar it is supposed to annotate, and one
-- small enough to leave the bar alone cannot be read.
--
-- gap is the clearance between the frame's edge and the column. The frame rect
-- is the art's own visible extent (modules/modernwow.lua BuildHousing sizes it
-- to the content box), so anything past that edge is clear of the housing.
M.modernWow.hot = {
  gap = 4,
}

-- Portrait size and centre per frame art, in source-art pixels, with x already
-- mirrored into screen order.
--
-- `size` is DragonflightUI's 62, which is deliberately WIDER than the ring's
-- 51-pixel opening.
--
-- The gold rim measures 7.5 pixels thick in the art -- outer circle 66 against
-- a 51 opening -- and that is true of the source interface too. It only reads
-- as a thin ring there because the portrait overlaps the opening and covers
-- all but about two pixels of it. Fitting the portrait to the opening instead
-- uncovers the whole rim, and the border then reads as a heavy gold donut.
--
-- This only works while the portrait draws ABOVE the housing overlay; see the
-- frame level modules/modernwow.lua gives it. The two go together: the rim is
-- drawn over the bars so the border is visible against them, and the portrait
-- is drawn over the rim so the rim stays as thin as the source's.
--
-- The target ornament's opening measures 49 against the player's 51, so it
-- carries the same 62/51 proportion rather than the player's literal 62.
--
-- The centres ARE measured, from the transparent opening in each file: player
-- and target place their circle a few pixels apart, and a shared value reads
-- as a misaligned portrait.
-- Extra inward shift for the value readouts at the outer end of each bar,
-- on the player and target frames only. The bar rectangles sit inside the
-- art's openings, so a label at UnrealUI's own 4px margin ends up close to the
-- housing's rim; this pulls it clear.
--
-- Applied on top of modules/unitframes.lua's BAR_LABEL_MARGIN rather than
-- replacing it, so the shared margin stays the one number that positions
-- every other frame's labels.
M.modernWow.labelShift = 4

-- Fine placement for the text this theme draws on and above the bars, all in
-- UI units and all relative to what modules/unitframes.lua would do on its own.
--
-- barLabelY lifts the readouts ON the health bar; the power bar's keep the
-- shared offset, so only the one row moves.
--
-- The header's horizontal offsets are NOT here: they are per frame, on the
-- entries in modules/modernwow.lua, because they do not follow one rule. The
-- player and the target mirror each other, so a side-based rule looked right
-- for a while, but their right-hand labels want different amounts.
M.modernWow.text = {
  barLabelY = 1,        -- health bar readouts, upward, on every frame
  -- Name/level row, downward. The row is anchored 2 above the health bar to
  -- start with, so -5 lands it 3 BELOW that edge: the source art's name band
  -- sits lower over the bar than the bare anchor does.
  headerY = -5,
  -- Width kept clear at the level end of the header row, so a long name stops
  -- before it reaches the level rather than running under it. Two or three
  -- digits plus a gap.
  levelReserve = 26,
  -- The power bar's percentage, relative to the value at the other end of that
  -- same row. Nominally they share a Y, but a LEFT/RIGHT anchor pins a
  -- FontString's vertical centre rather than its baseline, so two readouts of
  -- different glyph heights -- a "%" against digits -- do not sit level at the
  -- same offset. This is the correction.
  powerPercentY = -3,
}

-- Ink for text set on parchment art: the Quest Log's details page and the
-- native NPC quest window's titles. Near-white text and the chrome accent are
-- both illegible there.
M.modernWow.parchmentInk = {
  heading = { 0.30, 0.13, 0.02, 1 },
  body = { 0.16, 0.12, 0.08, 1 },
}

M.modernWow.ring = {
  -- 65 and 63: three pixels over DragonflightUI's 62, and the same step for the
  -- target's proportional 60. The portrait draws UNDER the ring overlay, so
  -- what this changes is not the visible circle -- the rim crops that to the
  -- 51-pixel opening either way -- but how much of the portrait image falls
  -- inside it. A larger portrait fills the opening with a slightly closer
  -- crop.
  --
  -- `model` is the side of the experimental 3D portrait (/uui portrait3d).
  -- A Model viewport is a rectangle and this client has no mask for it, so
  -- the model is the largest square whose corners stay under the gold rim:
  -- sqrt(2) x the rim's outer radius, measured at its thinnest point (alpha >
  -- 128, rays from the centre, ornaments excluded) -- player 31.0, target
  -- 30.9, party 19.2. The circular stone portrait background stays drawn
  -- beneath it and fills the crescents between that square and the opening.
  -- backgroundTrim: the 3D portrait's stone background is drawn this many
  -- pixels smaller than the portrait (centred), so it no longer shows under
  -- the player rim's bottom edge; backgroundY then raises it that many pixels
  -- so the bottom clears the rim without cropping the top.
  playerFrame    = { size = 65, x = 74, y = 43.0, model = 43,
                     backgroundTrim = 2, backgroundY = 1 },
  targetFrame    = { size = 63, x = 71, y = 43.5, model = 43 },
  -- The classification tiers share the target's ornament, so they carry the
  -- same numbers. Nothing sizes from them today -- the target entry's art is
  -- "targetFrame" and a tier change only swaps the texture, never the portrait
  -- -- but a stale value here would be a trap the day one does.
  frameRare      = { size = 63, x = 71, y = 43.5, model = 43 },
  frameElite     = { size = 63, x = 71, y = 43.5, model = 43 },
  frameRareElite = { size = 63, x = 71, y = 43.5, model = 43 },
  frameBoss      = { size = 63, x = 71, y = 43.5, model = 43 },

  -- The small canvas, in ITS 128x64 pixels rather than the large layout's.
  -- Measured rim: 3 pixels thick, inner opening x7..40 and y8..39, so the hole
  -- is 34 across and centred on 23.5,23.5. 38 is the same trick the two large
  -- rings use -- a portrait a little wider than the opening, so the rim crops
  -- it instead of leaving a gap at the edge. DragonflightUI's own value is the
  -- opening's 35.
  -- `modelScale` overrides M.modernWow.portraitModelScale for this ring only:
  -- the thin 3-pixel party rim showed the 3D portrait's corners at 1.1.
  partyFrame     = { size = 38, x = 23.5, y = 23.5, model = 27,
                     modelScale = 1.05 },
}

-- Multiplier on every ring's measured `model` side. The measured square is
-- the corner-safe fit. 1.2 was tried in game and its corners showed outside
-- the gold rim; 1.1 is the reduced step between that and the safe fit.
M.modernWow.portraitModelScale = 1.1

-- ---------------------------------------------------------------------------
-- Player combat and rest effects
--
-- Two pieces of player-frame state art, both drawn by modules/modernwow.lua's
-- `playerfx` surface and by nothing else.
--
-- THE GLOW (unitframes/player-status-large) is a user-supplied 512x256 copy of
-- the stock UI-Player-Status halo DragonflightUI pulses red for combat and cyan
-- for resting (modules/unit/player.lua Setup:CombatGlow / Setup:RestingGlow):
-- same silhouette and orientation, twice the resolution. Its shape lives in
-- the alpha over near-white RGB (the 256x128 player-status it replaces kept it
-- in RGB over opaque alpha). It is drawn with SetBlendMode("ADD"), which is
-- alpha-weighted, so the transparent surround contributes nothing and the
-- vertex tint colours the white. Blending mode names are documented for this
-- client (documentation.json / widget-method:Texture:SetBlendMode).
--
-- DragonflightUI positions it by a hardcoded offset from the native
-- PlayerFrame's centre, which describes the client's own frame rather than
-- this theme's art, so the offset is useless here. These numbers are measured
-- instead, and in two different coordinate spaces that must not be mixed up:
--
--   * `glow*` is the halo's visible extent in ITS OWN file, which is authored
--     portrait-left -- the player's screen order -- so the player frame draws
--     it unflipped. (The frame art is the opposite: authored portrait-right
--     and mirrored for the player.) Measured at alpha > 4 on the 512x256
--     file; the old file's luminance bound (1..194, 0..71) doubled agrees to
--     within a texel.
--   * `fit*` is the frame art's visible extent in the SCREEN-order art pixels
--     the rest of M.modernWow.sourceLayout uses. Taken from player-frame's
--     alpha bounding box (21..222, 4..78 in file order) mirrored into screen
--     order. It is NOT sourceLayout's content box, which is padded outward to
--     make room for the wider boss and rare-elite ornaments.
--
-- Mapping one rectangle onto the other lands the halo's peak brightness on the
-- housing's rim. The two axes work out at 1.0415 and 1.0423, so the halo is
-- the same silhouette as the housing at very nearly one uniform scale; they
-- are applied independently anyway, which costs nothing and is exact.
--
-- THE Z ANIMATION (unitframes/resting-flipbook) is a flipbook: 42 cells of
-- 60x60 in a 6-wide, 7-tall grid on a 512x512 sheet, stepped one cell at a
-- time. DragonflightUI carries this animation's script but ships no texture
-- for it, so the file is user-supplied (see the ATTRIBUTION note beside it)
-- and the grid below is measured from that file, not taken from the source
-- addon -- whose own table describes a 36-cell 6x6 grid and would drop the
-- last six frames.
--
-- `icon` places it in screen-order art pixels like everything else here: a
-- centre point, in the same space as M.modernWow.ring, so it scales with the
-- frame art. Centred on the portrait ring's x and floated above the frame's
-- top edge, which is where the classic resting glyph sits.
-- ---------------------------------------------------------------------------
M.modernWow.playerFX = {
  glowLeft = 2, glowRight = 387, glowTop = 0, glowBottom = 141,
  glowWidth = 512, glowHeight = 256,
  -- fitRight is 227, not the art's own visible 235. Fitted to the art exactly,
  -- the halo overhung the frame on the bar end: sourceLayout's content box
  -- stops at 230 but the art keeps drawing to 235, so the frame is five art
  -- pixels narrower than the thing the halo was being matched to -- and an
  -- additive glow's soft tail reads past its own measured bound on top of that.
  -- 227 puts the halo's right edge just inside the frame. Left, top and bottom
  -- stay measured: only the bar end overhung.
  fitLeft = 34, fitRight = 227, fitTop = 4, fitBottom = 78,
  -- Visual nudge after the fit above, in UI units (not art pixels, so it does
  -- not grow with the frame's scale). Positive moves the halo right / up.
  glowOffsetX = 2,
  glowOffsetY = 0,

  -- Combat keeps DragonflightUI's red: it is unit state, and red is what it
  -- means everywhere else in this interface. Resting is the opposite: it says
  -- nothing about the unit, only that UnrealUI has something to point out, so
  -- restColor takes the addon accent rather than the source's cyan. That one
  -- is assigned further down the file instead of here, because M.color does
  -- not exist yet at this point.
  combatColor = { 1, 0, 0 },

  -- One breathe per period, and the same period for both states. The source
  -- ships a 1.0 fade speed, which is a one-second cycle; that reads as a blink
  -- rather than a breathe on a frame this size, so the period is 2.5 here.
  -- alphaMax is the peak of the additive pulse. fadeSpeed is separate and is
  -- deliberately not slowed with it: it is alpha per second on the way OUT
  -- once the state ends, and leaving combat should clear promptly.
  pulsePeriod = 2.5,
  alphaMin = 0,
  alphaMax = 1.0,
  fadeSpeed = 2.0,

  -- How often IsResting and UnitAffectingCombat are re-read. Neither
  -- PLAYER_UPDATE_RESTING nor PLAYER_REGEN_DISABLED has any evidence on this
  -- client (query_compat.py returns nothing for the regen events, and
  -- modules/unitframes.lua already records the resting one as unverified), so
  -- this surface polls instead of trusting an event to arrive.
  pollInterval = 0.1,

  restColumns = 6,
  restRows = 7,
  restCell = 60,
  restSheet = 512,
  restInterval = 0.05,

  icon = { size = 28, x = 74, y = -2 },
}

-- No cast-bar inset table: DragonflightUI draws its background and its frame
-- art across the whole bar rectangle and lets both scale with it
-- (modules/cast/cast.lua uses SetAllPoints for each), so modules/modernwow.lua
-- does the same and has nothing to measure a rim against.

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
-- checkbox fills, slider thumbs and selected edit-mode handles. Bar fills and
-- unit colours stay as they are -- the accent marks unrealUI's own chrome, not
-- game state.
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

  -- The X and the hover outline every unrealUI close button carries, whether
  -- the button is a skinned stock one (U.StyleStockCloseButton) or unrealUI's
  -- own. Restrained semantic red: closing is the one destructive-shaped action
  -- on an otherwise neutral window chrome.
  closeGlyph = { 1.00, 0.25, 0.25, 1.00 },

  health     = { 0.25, 0.75, 0.30, 1.00 },
  healthBg   = { 0.10, 0.10, 0.10, 0.90 },

  -- Experience fill, and the dimmer rested band behind it. Central because two
  -- surfaces draw an XP bar -- the player's own bar (modules/xpbar.lua) and the
  -- pet page's native one (modules/character.lua) -- and they have to read as
  -- the same bar.
  xp         = { 0.55, 0.32, 0.87, 1.00 },
  xpRested   = { 0.30, 0.20, 0.55, 1.00 },

  -- What a full-health bar fades to, and the single most recognisable part of
  -- the modern unit frame look. pfUI modern puts near-black here (profiles.lua,
  -- Modern profile: customcolor "0.1,0.1,0.1,1"), but the fade in
  -- modules/unitframes.lua weights this colour by health percent, so the top of
  -- the range collapsed onto the panel background: at 80% the fill resolved to
  -- roughly 0.17/0.23/0.13 against a 0.06 backdrop. A deep green keeps the flat
  -- dark bar while holding readable contrast across the whole high-health range,
  -- and low health still reads red/orange because the gradient dominates there.
  -- themes/modern.lua re-applies this token on a theme switch; keep both in sync.
  healthFull = { 0.18, 0.50, 0.22, 1.00 },

  -- The two segments modules/healpredict.lua paints past the end of the health
  -- fill for heals that are on their way, chained
  -- [ health ][ yours ][ everyone else's ] with no gap between them.
  --
  -- ElvUI's healPrediction recipe verbatim, by request: mint #00FF80 for your
  -- own cast, pure #00FF00 for other players', both at 25% alpha, and no
  -- overflow past maximum health (ElvUI/Settings/Profile.lua, healPrediction).
  -- The two hues are close on purpose -- they read as one continuous "incoming"
  -- band whose first part is attributable to you -- and the low alpha is what
  -- keeps them from being mistaken for health that already exists.
  --
  -- Deliberately not the accent: an incoming heal is game state, not unrealUI
  -- chrome.
  healPredictionMine   = { 0.00, 1.00, 0.50, 0.25 },
  healPredictionOthers = { 0.00, 1.00, 0.00, 0.25 },

  -- Castbar fill. Distinct from the accent so a cast in progress reads as game
  -- state, not chrome, and distinct from the health/power colours so it never
  -- looks like a third unit-frame bar.
  cast       = { 0.20, 0.55, 0.65, 1.00 },
  -- Time added by spell pushback. Semantic red makes the penalty distinct
  -- from both the normal countdown and the cast fill.
  castPushback = { 1.00, 0.20, 0.20, 1.00 },

  -- Breath is a depletion state, not an UnrealUI accent. Its cool blue stays
  -- separate from casting so the two progress bars remain distinguishable.
  breath     = { 0.22, 0.60, 0.74, 1.00 },

  highlight  = { 0.96, 0.68, 0.04, 0.22 },

  -- Edit-mode anchors stay cool blue until selected. The active anchor then
  -- uses the ordinary accent tokens, so selection reads like every other
  -- focused UnrealUI control without making all of edit mode compete for the
  -- eye at once.
  mover      = { 0.04, 0.36, 0.58, 0.32 },
  moverIdleEdge = { 0.18, 0.68, 0.92, 1.00 },
  moverIdleHover = { 0.36, 0.82, 1.00, 1.00 },
  moverIdleGlow = { 0.10, 0.62, 0.95, 1.00 },
  moverEdge  = { 0.96, 0.68, 0.04, 1.00 },

  -- Placeholder content drawn inside an anchor that is empty while edit mode
  -- is open (core/moversample.lua). Deliberately part of the mover family and
  -- not of the ordinary panel tokens: a sample is edit-mode chrome, and must
  -- never be mistaken for the real element it stands in for.
  moverSample = { 0.02, 0.02, 0.02, 0.55 },
  moverSampleEdge = { 0.18, 0.68, 0.92, 0.55 },

  grid       = { 0.45, 0.45, 0.45, 0.30 },
  gridAxis   = { 0.96, 0.68, 0.04, 0.55 },
  moverGuide = { 1.00, 0.20, 0.20, 0.90 },
}

-- Midway between the warmer #FFD200 and pure #FFFF00: clearly yellow without
-- overpowering the orange-gold frame art when drawn additively.
M.modernWow.playerFX.restColor = { 1.00, 0.909804, 0.00 } -- #FFE800

-- Unit frames have a small theme-owned style surface. Their geometry,
-- generated frame names and aura attachment points are deliberately not part
-- of it: themes may change appearance, never the unit-frame feature contract.
M.unitFrame = {
  -- Grey is reserved for offline slots; distant members keep darker live colours.
  inactiveBackground = { 0.18, 0.18, 0.18, 1.00 },
  inactiveFill = { 0.24, 0.24, 0.24, 1.00 },
  distantBackground = { 0.04, 0.04, 0.04, 1.00 },
  distantBrightness = 0.55,
  usePastelGradient = true,
  statusTexture = M.texture.statusBar,
  background = { 0.06, 0.06, 0.06, 0.85 },

  -- The modern theme uses the same resting-Z timing and atlas layout as
  -- modern-wow, but keeps its existing top-left unit-frame anchor.
  restIconFX = {
    size = 28,
    columns = 6,
    rows = 7,
    cell = 60,
    sheet = 512,
    interval = 0.05,
  },

  -- Shared health/power progress animation for the modern and modern-wow
  -- unit-frame drawing paths. The numbers reproduce DragonflightUI's status
  -- bars, with the client-safe departures recorded beside them.
  barFX = {
    -- Time-based equivalent of the source's frame-rate-dependent 0.1 lerp.
    -- The shared updater derives elapsed from GetTime because this client
    -- passes no arguments to OnUpdate (scripts.onupdate_elapsed_only_via_arg1).
    approach = 8,
    snapBelow = 0.002,

    cutoutDuration = 0.3,
    cutoutColor = { 1.00, 0.15, 0.15 },
    cutoutAlpha = 0.85,
    -- Fixed and reused for the session. Creating one Texture per damage event
    -- is forbidden by compat.target_storm_uobject_exhaustion.
    cutoutPool = 3,

    pulseDuration = 0.3,
    pulseAlpha = 0.30,
  },
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

-- Item-comparison deltas, drawn only in the "Currently Equipped" tooltip's
-- change summary (modules/tooltip.lua). The hovered item's own lines stay the
-- colour the client gave them. This is game state rather than UnrealUI chrome,
-- so it stays clear of the accent and reuses the same green/red the zone-level
-- readout already carries.
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

-- Ordered active-pip colours for the Rogue combo-point strip. These values
-- compensate for normTex2's darkening while forming a clear red-to-green
-- progression through orange, yellow, and yellow-green.
M.rogueCombo = {
  { 0.704, 0.341, 0.341, 1.00 },
  { 0.800, 0.550, 0.340, 1.00 },
  { 0.679, 0.654, 0.389, 1.00 },
  { 0.490, 0.640, 0.320, 1.00 },
  { 0.310, 0.700, 0.310, 1.00 },
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
  quest = { 225 / 255, 67 / 255, 67 / 255, 1.00 }, -- quest item, #e14343
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
