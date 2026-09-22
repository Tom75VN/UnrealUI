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
  -- The bag/bank header action icons: user-supplied 64x64 art in media/icons,
  -- drawn with the same edge crop as the stock key and bag toggles, as
  -- uncompressed 32-bit type-2 TGA (the encoding of leader-star and
  -- rest-icon, which draw on this client). Owned files rather than stock Interface\Icons paths, which this
  -- client does not let us inventory and which render blank when absent.
  -- Central because the sort and stack buttons appear in both the bag and
  -- bank windows.
  sellGreysIcon = "Interface\\AddOns\\unrealUI\\media\\icons\\sell-grey-items-64",
  sortIcon = "Interface\\AddOns\\unrealUI\\media\\icons\\sort-bags-64",
  stackIcon = "Interface\\AddOns\\unrealUI\\media\\icons\\bag-auto-stack-64",
  -- The bag and keyring pictures. Central because two surfaces draw them --
  -- the bag window's header toggles (modules/bags.lua) and the HUD bag bar
  -- (modules/bagbar.lua) -- and they have to read as the same control. Chosen
  -- rather than verified, exactly like sortIcon above: a path this client does
  -- not have renders blank, so changing either one line fixes both surfaces.
  bagIcon = "Interface\\Icons\\INV_Misc_Bag_08",
  keyringIcon = "Interface\\Icons\\INV_Misc_Key_03",
  -- The bag window's saved-bank button (modules/bankview.lua). Bundled
  -- 64x64 uncompressed 32-bit TGA, the same encoding as sortIcon/stackIcon.
  bankViewIcon = "Interface\\AddOns\\unrealUI\\media\\icons\\view-bank-64",
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
-- ---------------------------------------------------------------------------
-- Minimap pending-mail animation (modules/minimap.lua)
--
-- User-supplied art (Blizzard file id 5201351), extracted by
-- tools/make_minimap_mail_flipbook.py into 32 separate 64x64 textures. The
-- focused minimapmail comparison confirmed that this client's SetTexCoord
-- sampling makes the 256x512 atlas travel, while the identical separate files
-- animate in place. Keep the per-frame path; this is not a native-HUD issue.
--
-- Frames run left to right then down in the source sheet. It is two movements,
-- not one loop: frames 1..`intro` are
-- the letter folding itself into the envelope, played once each time the mail
-- icon appears, and `intro`+1..`frames` are the two sparkle bursts it settles
-- into, looped for as long as mail is pending. Restarting the intro on every
-- show is deliberate -- new mail should announce itself.
--
-- `size` is the drawn square. The envelope itself is only about 17 of the 64
-- cell pixels wide, the rest being the sparkle halo, so 56 puts a ~15px letter
-- on the map edge: the same reading weight as the 32px modern-wow mail.tga it
-- replaces, with room for the sparks around it.
-- ---------------------------------------------------------------------------
M.minimapMail = {
  size = 56,
  framePattern = "Interface\\AddOns\\unrealUI\\media\\minimap-mail-frames\\frame-%02d",
  frames = 32,
  intro = 11,
  interval = 0.05,
}

M.classicWow = {}
M.classicWow.path = "Interface\\AddOns\\unrealUI\\media\\Textures\\classic-wow\\questLog\\"

-- Compact Classic target-of-target housing (modules/unitframes.lua). This is
-- the player-facing slice of the client's UI-TargetingFrame atlas, not
-- modern-wow art. Geometry is the original 1.12.1 PlayerFrame XML scaled so
-- its 64-unit portrait becomes the stock target-of-target's 35-unit portrait;
-- every bar and label therefore keeps the player frame's authored alignment.
M.classicWow.targetTarget = {
  texture = "Interface\\TargetingFrame\\UI-TargetingFrame",
  texCoord = { 1.0, 0.09375, 0, 0.78125 },
  scale = 35 / 64,
  canvas = { width = 232, height = 100 },
  portrait = { x = 42, y = 12, width = 64, height = 64 },
  health = { x = 106, y = 41, width = 119, height = 12 },
  power = { x = 106, y = 52, width = 119, height = 12 },
  name = { x = 166, y = 31 },
}

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
M.modernWow.unitFrame = {
  -- themes/modern-wow.lua applies the same colour globally. Classic module
  -- mixing cannot mutate that shared token without recolouring native Classic
  -- surfaces, so the dressed unit-frame path reads this scoped copy instead.
  healthFull = { 0.10, 0.80, 0.10, 1.00 },

  -- `texture.healthFill` (DF-main's player health status fill) is opaque from
  -- its canvas top to its canvas bottom, where the DFRL fill this surface
  -- shipped first (`texture.healthFillPadded`) carried its own transparent
  -- padding: measured on that file, its opaque band is rows 5-24 of 32, and
  -- rows 4 and 25-26 are a near-invisible 8/255 shadow. The StatusBar is
  -- therefore inset inside its box by those same fractions, so the drawn fill
  -- keeps the band the authored housing recess was placed around while its
  -- shading ramps to the edge instead of cutting off at an alpha edge. Labels
  -- anchor to the box and not to the bar, so the inset moves no text
  -- (modules/modernwow.lua mw.PlaceBar).
  --
  -- Reverting to the padded fill means pointing `texture.healthFill` back at
  -- `texture.healthFillPadded` and setting both fractions here to 0.
  healthFillInset = { top = 5 / 32, bottom = 7 / 32 },
}
M.modernWow.path = "Interface\\AddOns\\unrealUI\\media\\Textures\\modern-wow\\"

M.modernWow.texture = {
  playerFrame     = M.modernWow.path .. "unitframes\\player-frame-large",
  playerFrameBg   = M.modernWow.path .. "unitframes\\player-frame-bg",
  targetFrame     = M.modernWow.path .. "unitframes\\target-frame-large",
  targetFrameBg   = M.modernWow.path .. "unitframes\\target-frame-bg",
  -- Target name wash. Two cuts of the same Blizzard strip are shipped:
  -- `target-reaction-type` is the 128x16 original (supplied 24-bit, its
  -- shape moved into alpha by tools/import_modern_wow_media.py), and
  -- `target-reaction` is the 172x29 cut kept beside it. Swapping the file
  -- here also means swapping the geometry in M.modernWow.targetReaction,
  -- whose two sets are recorded there.
  targetReaction  = M.modernWow.path .. "unitframes\\target-reaction-type",
  frameRare       = M.modernWow.path .. "unitframes\\frame-rare",
  frameElite      = M.modernWow.path .. "unitframes\\frame-elite",
  frameRareElite  = M.modernWow.path .. "unitframes\\frame-rare-elite",
  frameBoss       = M.modernWow.path .. "unitframes\\frame-boss",
  partyFrame      = M.modernWow.path .. "unitframes\\party-frame",
  playerStatus    = M.modernWow.path .. "unitframes\\player-status-large",
  restingFlipbook = M.modernWow.path .. "unitframes\\resting-flipbook",
  portraitBackground = M.modernWow.path ..
                       "unitframes\\unit-frame-portrait-background",
  -- Both authored health fills are shipped. `healthFill` is the one every
  -- dressed frame draws; `healthFillPadded` is the DFRL fill it replaced,
  -- kept so the choice can be reverted -- see unitFrame.healthFillInset.
  healthFill      = M.modernWow.path .. "unitframes\\health-fill-full",
  healthFillPadded = M.modernWow.path .. "unitframes\\health-fill",
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
  headerLeft      = M.modernWow.path .. "ui\\header-left",
  headerRight      = M.modernWow.path .. "ui\\header-right",
  button128Red     = M.modernWow.path .. "buttons\\128RedButton",
  button128GoldRed = M.modernWow.path .. "buttons\\128GoldRedButton",
  redButton        = M.modernWow.path .. "buttons\\red-button",
  -- Blizzard's plus / minus tree button (FileDataID 4496242), converted from
  -- the PNG beside it (user request, 2026-09-22). Four rounded buttons on a
  -- 64x64 sheet: plus over minus, normal in the left column and pushed in the
  -- right. It is the collapse control in the game-settings category list,
  -- which needs a literal +/- pair the red-button atlas cannot give -- that
  -- one carries a minus but no plus.
  plusMinus        = M.modernWow.path .. "buttons\\plus-minus-button",
  -- Blizzard's settings-UI control atlas, 512x512, imported whole: its
  -- cells are addressed by texture coordinates, never cut out. The talent
  -- advisor draws its yellow arrows (M.talentAdvisor.styles, toggle).
  settingUI        = M.modernWow.path .. "buttons\\setting-ui",
  -- MinimalSliderWithSteppers in silver: a recoloured copy of Forever's
  -- bronze 8086434 made by user request (2026-09-22), NOT Blizzard's own grey
  -- sheet (4567914, which no reachable source carries). Same 32x128 layout,
  -- alpha identical pixel for pixel, so it is addressed by the same cells.
  minimalSliderSilver = M.modernWow.path .. "buttons\\minimal-slider-silver",
  comboPoints      = M.modernWow.path .. "ui\\combo-points",
  classPortraits   = M.modernWow.path .. "ui\\class-portraits",
  frameTabs        = M.modernWow.path .. "ui\\frame-tabs",
  frameBorder      = M.modernWow.path .. "ui\\frame-border",
  swingTimer       = M.modernWow.path .. "ui\\swing-bar",
  questParchment   = M.modernWow.path .. "ui\\questbackgroundparchment",
  questScrollChannel = M.modernWow.path .. "ui\\questlog-dualpane-right",
  horizontalBar    = M.modernWow.path .. "ui\\borders\\ui-dialogbox-divider",
  questFooter      = M.modernWow.path .. "ui\\frame\\background-rock",

  -- Blizzard's action-button proc alert, as two flipbook grids: the one-shot
  -- burst and the loop it settles into. Both are 5 columns x 6 rows of 30
  -- frames, cropped so one cell is a plain fraction of the texture rather
  -- than a rectangle inside a padded sheet. The talent advisor runs them
  -- around the next talent to learn (M.talentAdvisor.styles, next).
  spellAlertStart  = M.modernWow.path .. "ui\\spell-alert-start",
  spellAlertLoop   = M.modernWow.path .. "ui\\spell-alert-loop",
  -- A flipbook, not one image: 256x256 with 48x48 cells, 5 per row, of which
  -- Blizzard plays the first 22 (M.modernWow.iconAlertAnts). The talent
  -- advisor marches them around every talent its build still wants.
  iconAlertAnts    = M.modernWow.path .. "ui\\icon-alert-ants",
  -- Middle cell of the supplied talent alert strip, cropped to its own square.
  -- The advisor keeps its authored thickness, tints it red and pulses it over
  -- ranks spent outside the selected build.
  talentIconAlert  = M.modernWow.path .. "ui\\talents\\icon-alert",

  minimapBorder      = M.modernWow.path .. "minimap\\uiminimapborder",
  minimapShadow      = M.modernWow.path .. "minimap\\uiminimapshadow",
  minimapTopPanel    = M.modernWow.path .. "minimap\\uiminimap_toppanel",
  -- Superseded by the shared animated letter (M.minimapMail), which every
  -- theme draws. Kept shipped and attributed for a revert, as `health-fill`
  -- is; no surface reads this token now.
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

-- Forever 1.60.1.69913 Blizzard_SwingTimer.xml. The source atlas is 512x256;
-- these are the exact UiTextureAtlasMember rectangles for FileDataID 8344036.
M.modernWow.swingTimer = {
  width = 213,
  height = 15,
  -- Every lane is drawn four units shorter than the authored art, which keeps
  -- the pair compact now that they no longer overlap (user requests,
  -- 2026-09-21). height stays the art's own measurement.
  heightTrim = 4,
  bottomPadding = -6,
  -- Blizzard's own -6 stacks the lanes flush, because the authored art carries
  -- transparent margins. That overlap is given back and then some, so stacked
  -- lanes read as clearly separate bars (user requests, 2026-09-21).
  laneGap = 7,
  -- The lane fill sits 2 units inside the framed art on every edge, and the
  -- frame texture redraws above it, so the rim stays visible at full fill.
  fillInset = 2,
  labelInset = 10,
  -- The lane labels sit one unit below centre (user request, 2026-09-21).
  labelDrop = -1,
  -- While the two melee lanes are drawn as a stacked pair each one's text
  -- takes a further offset of its own, away from the seam between them
  -- (user request, 2026-09-21).
  stackedLabelDrop = { main = 0, off = -1 },
  shadowWidth = 171,
  pipWidth = 5,
  pipHeight = 27,
  background = { 1 / 512, 423 / 512, 33 / 256, 59 / 256 },
  frame = { 1 / 512, 427 / 512, 1 / 256, 31 / 256 },
  pip = { 1 / 512, 11 / 512, 156 / 256, 210 / 256 },
  shadow = { 1 / 512, 172 / 512, 133 / 256, 154 / 256 },
  fill = {
    main = { 1 / 512, 419 / 512, 61 / 256, 83 / 256 },
    off = { 1 / 512, 419 / 512, 85 / 256, 107 / 256 },
    ranged = { 1 / 512, 419 / 512, 109 / 256, 131 / 256 },
  },
}

-- The client's own Edit Mode selection nine-slice, from Forever build
-- 1.60.1.69913 (Blizzard_EditMode/Shared/EditModeSystemTemplates.xml). Like
-- the swing bar above this is Blizzard art rather than imported Dragonflight
-- chrome, so core/mover.lua draws it under every theme; it is not a
-- modern-wow surface and has no Classic -> Modern WoW module.
--
-- EditModeSystemSelectionLayout places every piece as a 16-unit cell centred
-- on the frame's own edge -- `straddle` out, `straddle` in -- and covers the
-- frame itself with the centre fill, which therefore meets the border line on
-- every side. The two texture kits are Blizzard's
-- `editmode-actionbar-highlight` (cyan) and `editmode-actionbar-selected`
-- (gold); both live on one sheet, as do all four vertical edges, while each
-- centre is its own flat file. Only the top-left corner is authored, exactly
-- as the layout's mirrorLayout says, so the other three reverse its
-- coordinates.
--
-- The `_`/`!` prefixes on Blizzard's edge atlas names mark tiling, which this
-- client cannot do from an atlas cell. Stretching is identical here: every
-- edge cell is constant along the axis it runs.
M.modernWow.moveUI = {
  texture = M.modernWow.path .. "ui\\move-ui\\editmodeui",
  textureVertical = M.modernWow.path .. "ui\\move-ui\\editmodeuivertical",
  piece = 16,
  straddle = 8,
  -- Every anchor is drawn at once in edit mode, so an idle one is held back
  -- from the full-strength selection Blizzard uses for its single system.
  alpha = { idle = 0.75, hover = 1.00, selected = 1.00 },
  -- The centre fills are authored at alpha 128; these scale that down so the
  -- moved element stays readable under its own anchor.
  fillAlpha = { idle = 0.35, hover = 0.45, selected = 0.55 },
  hover = {
    fill = M.modernWow.path .. "ui\\move-ui\\editmodeuihighlightbackground",
    corner = { 1 / 32, 17 / 32, 73 / 256, 89 / 256 },
    top = { 0, 16 / 32, 19 / 256, 35 / 256 },
    bottom = { 0, 16 / 32, 1 / 256, 17 / 256 },
    left = { 1 / 128, 17 / 128, 0, 1 },
    right = { 19 / 128, 35 / 128, 0, 1 },
  },
  selected = {
    fill = M.modernWow.path .. "ui\\move-ui\\editmodeuiselectedbackground",
    corner = { 1 / 32, 17 / 32, 91 / 256, 107 / 256 },
    top = { 0, 16 / 32, 55 / 256, 71 / 256 },
    bottom = { 0, 16 / 32, 37 / 256, 53 / 256 },
    left = { 37 / 128, 53 / 128, 0, 1 },
    right = { 55 / 128, 71 / 128, 0, 1 },
  },
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
    -- The bottom cap fades in over its first 28 rows (alpha 1 at row 27 to
    -- ~250 at row 54 of the sheet) and is drawn over the body, which runs this
    -- far down under it (core/modernwowscrollbar.lua).
    bottomFade = 28,
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
  -- No mail size here any more: the letter is the shared flipbook
  -- (M.minimapMail), which every theme draws at one size. This theme only
  -- still decides where the native mail frame sits.
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
  -- activeTextColor / inactiveTextColor / hoverTextColor are filled in
  -- beside M.tab, once M.color exists.
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

-- The Social window (FriendsFrame) under the `social` surface (user request,
-- 2026-09-19): the 384x512 paperdoll quadrants, the Character window's
-- archetype. Rectangles are in that 384x512 design space.
--
-- `extend`: the art's visible rim ends 73 units above its bottom edge
-- (alpha rows 0..439 of 512), where Character's panel ends. modules/friends.lua
-- lays the Social content down to 48 above the bottom, and its FauxScrollFrame
-- rows must not be resized (knowledge.json /
-- frames.friendsframe_row_touch_crashes_client), so the art grows instead:
-- the bottom quadrants drop `extend` units and the gap is filled 1:1 with the
-- top quadrants' last `extend` rows. Ring, rims and corners keep their
-- authored aspect; only plain body rows are repeated.
--
-- `portrait`: the stock Friends window's own round portrait, shown natively
-- under classic-wow. WORKING_SOURCE (the 1.12 FrameXML path); no probe has
-- read this client's region, so an absent file leaves the ring empty.
--
-- The title centres on the art's title strip: gold rims at rows 15 and 33,
-- from the portrait ring's right edge (x 72) to the right rim (x 351).
-- The guild player-status view's four columns -- Name, Rank, Note, Last
-- Online -- as `x` from the list's left edge plus a width each, with the last
-- column's value ending `onlineRight` inside the list. Layout, not chrome, so
-- it lives outside M.modernWow and both themes lay that view out the same way
-- (user request, 2026-09-20).
M.guildStatusColumns = { x = 9, width = { 79, 67, 80, 61 }, onlineRight = 4 }

-- Blizzard's Dialog Box divider occupies x 0-192, rows 0-15 of its 256x32
-- canvas. Its end caps keep their aspect and only the long centre stretches.
-- Shared by the Social and quest-giver windows.
M.modernWow.horizontalBar = {
  atlasWidth = 256,
  atlasHeight = 32,
  sourceHeight = 16,
  height = 12,
  left = { u1 = 0, u2 = 12, v1 = 0, v2 = 16, width = 12, height = 16 },
  middle = { u1 = 12, u2 = 181, v1 = 0, v2 = 16, height = 16 },
  right = { u1 = 181, u2 = 193, v1 = 0, v2 = 16, width = 12, height = 16 },
}

M.modernWow.social = {
  extend = 25,
  portrait = "Interface\\FriendsFrame\\FriendsFrameScrollIcon",
  -- Where that portrait draws, in the 384-wide design space from the
  -- window's top-left: larger than the shared 54 (ring 64, inset 5) so the
  -- scroll art fills the gold ring, and nudged up-left because the art sits
  -- low-right in its canvas (user request 2026-09-20).
  portraitRect = { left = 9, top = 5, size = 62 },  -- left +2, down 2 (user, 2026-09-20)
  -- The bottom tab row's x from the window's bottom-left (5, then 3 more
  -- right: user request 2026-09-20).
  tabX = 8,
  -- Guild "Show Player/Guild Status" toggle: the client's own next-page
  -- button art (as the Modern WoW Spellbook keeps). The 32x32 art carries a
  -- transparent margin, so it is drawn at 24 (user request 2026-09-20);
  -- `rightPad` pulls it right by that margin so its visible edge stays where
  -- the 16-unit control's was.
  -- `aspect` is the art's own width:height (the client's
  -- UI-SpellbookIcon-NextPage-*.blp are 32x32, and Blizzard's own page
  -- buttons draw them square), so the state textures are sized from `size`
  -- rather than stretched over the native button's rect -- that rect is
  -- narrower than tall and squeezed the arrow (user report 2026-09-21).
  statusArrow = {
    size = 24,
    aspect = 1,
    rightPad = 4,
    normal = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    pushed = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
    disabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
  },
  titleX = 211,
  titleY = -18,
  -- Warm gold for the short title, column headings and field labels; body
  -- values stay light neutral (rules/unreal-ui-design.md text hierarchy).
  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  headingColor = { 1.00, 0.82, 0.00, 1.00 },
  -- Guild detail / guild info docks sit this far right of the art's rim.
  dockGap = 4,
  -- The guild member detail dock carries a lighter backing than the shared
  -- metal housing: its fill alpha times this (user request, 2026-09-20).
  guildDetailFill = 0.8,
  -- Friends/Ignore toggles: the tab atlas at a smaller scale than the bottom
  -- row (0.75 / 27 high), and started `ringGap` right of the portrait ring's
  -- right edge (x `ringRight`) so the first tab clears the gold rim.
  -- `textY` is the label's centre offset (positive up); the flipped art
  -- would otherwise give -2.
  toggleTab = { scale = 0.6, height = 21, textY = -5 },
  ringRight = 72,
  ringGap = 6,
  -- The toggle run's lift above its list's top edge (the flat design uses 3).
  toggleY = 6,
  -- The Friends list's four footer actions: fixed width (the flat design's
  -- 158 less 6) and the native height plus `heightGrow`. `x`/`y` move the
  -- whole run relative to where the flat design puts it -- positive x right,
  -- negative y down -- by offsetting the two column heads only, since Remove
  -- and Group Invite chain off them.
  -- `pull` closes the gap between the two columns: the left column moves
  -- this far right and the right column the same distance left, so the run
  -- narrows by twice this without either column changing width.
  -- `raise`: the Friends footer buttons alone sit this much higher (user,
  -- 2026-09-20); the footer plate keeps its place.
  footerButton = { width = 152, heightGrow = 4, x = 3, y = -11, pull = 2,
                   raise = 2 },
  -- The Guild tab's three actions, moved as one row (positive x right,
  -- negative y down; user, 2026-09-20).
  -- `motdX`: the message box above them moves this much right on its own.
  -- `motdGrow`: the message box grows this much taller at its bottom.
  -- `motdY`: the message box moves this much (negative is down).
  -- `listGrow`: the roster list grows this much taller at its bottom.
  -- Guild player-status headers (Name, Rank, Note, Last Online): the first
  -- one's x from the list's left edge and each one's width, so each label
  -- starts over its value column. Re-measured off the user's 2026-09-20
  -- screenshot with the headers in place (1.87 px per unit): the values
  -- start at about 9 / 88 / 155 / 235 from the list's left edge.
  -- `onlineRight`: the Last Online values end this far inside the list.
  -- Shared with every theme; see M.guildStatusColumns.
  guildStatusColumns = M.guildStatusColumns,
  guildButtons = { x = 3, y = -20, motdX = 3, motdGrow = 4, motdY = -9,
                   listGrow = 10,
                   -- `barDrop`: the roster's scrollbar sits this much lower.
                   barDrop = 4,
                   -- `totalsY`: "n Guild Members" alone, off the toggle line.
                   totalsY = -2,
                   -- `statusGap`: the status toggle row's bottom above the box.
                   statusGap = 5,
                   -- `leftTextY`: both member-count texts, off that line.
                   leftTextY = -3,
                   -- `rowsDrop`: the 13 roster rows, moved down as a block.
                   rowsDrop = 4,
                   -- `offlineDrop`: "Show Offline Members", moved down.
                   offlineDrop = 6,
                   -- `statusLabelY`: "Show Player Status" alone (positive up).
                   statusLabelY = 3 },
  -- The Who tab's header band (dropdown + column headers): the footer's own
  -- rock wash and metal rule (footerPlate), with the rule on its BOTTOM edge,
  -- between the header and the list (user request 2026-09-19). Its sides and
  -- top are the paperdoll art's inner recess, in the 384x512 design space
  -- from the window's top-left (x 24-340, y 73: inside the left/right dark
  -- rims at x 23/341 and just under the portrait ring -- the same recess
  -- M.modernWow.questDialog measures). The band's bottom is the list's scroll
  -- frame top, where the rule is centred.
  -- `ruleHalf` is the half of the rule that reaches up into the band; the
  -- header labels and the dropdown centre on what is left above it, and the
  -- dropdown keeps `pad` clear of both edges (at most the normal 28 high).
  -- `dropdownGrow` is added on top of that fitted height (user, 2026-09-19).
  headerPlate = { left = 24, right = 340, top = 73, ruleHalf = 3, pad = 3,
                  headerHeight = 24, dropdownGrow = 6,
                  -- Headers and dropdown together, off that centre line
                  -- (negative is down; user, 2026-09-19).
                  contentY = -2 },
  -- The section the four footer actions sit on: a translucent dark wash over
  -- the window art, closed at the top by M.modernWow.horizontalBar, the same
  -- authored Dialog Box divider used between the quest page and footer.
  -- `padX`/`padTop`/`padBottom` are how far the wash reaches past the buttons
  -- it wraps.
  footerPlate = {
    -- DF-main's dark rock window body, the same surface the quest dialog's
    -- footer uses, sampled 1:1 so its grain keeps the authored scale and
    -- shaded to `shade` of its brightness. NOT a tinted WHITE8X8 at partial
    -- alpha: vertex alpha is not honoured for textures on this client
    -- (knowledge.json rendering.texture_setalpha_darkens_not_translucent),
    -- so every "translucent" wash drew as solid black. Lower `shade` is
    -- darker; 1.0 is the rock's own brightness.
    shade = 0.55,
    ruleShade = 0.8,
    atlas = 1024,
    padX = 4,
    padTop = 7,
    padBottom = 0,  -- was 4: covered the window's bottom rim (user, 2026-09-20)
    -- Guild tab only: the rule's lower edge this far above the action row.
    guildGap = 3,
    -- Raid tab: no plate; its Convert to Raid / Raid Info buttons this much
    -- lower instead (user, 2026-09-20).
    raidButtonsDrop = 6,
    -- Who tab only: the plate's top reaches this much higher (user request
    -- 2026-09-19). Friends/Ignore keep `padTop`, clear of their lists.
    whoGrow = 8,
    -- The rule between list and footer is M.modernWow.horizontalBar. On the
    -- Who header's bottom edge it is mirrored vertically so its ornament faces
    -- into the header rather than the list.
  },
  -- Friend rows stack edge to edge, so their hover/selection highlight
  -- (Interface/QuestFrame/UI-QuestTitleHighlight, one CENTER anchor filling
  -- the 298x31 row) reads as one unbroken bar down the list. Lifting its
  -- bottom edge by this much separates consecutive rows. Applied once, off
  -- any list-update path -- see modules/friends.lua.
  rowGap = 1,
  -- The row button is narrower than the list bed it sits in, so a highlight
  -- anchored flush to it leaves bare parchment down the right-hand side.
  -- Positive units push the highlight's right edge past the row.
  rowExtend = 18,
  -- The row's own name/info text, nudged to sit centred on the shortened
  -- highlight bar. Negative units move it down.
  rowTextY = -2,
  -- Same restrained channel as the NPC progress bar: the quadrants have no
  -- authored recess behind a list's native scrollbar.
  -- The channel behind each list's scrollbar. No `outer` rim: these lists
  -- draw the shared MinimalScrollBar, which carries its own track, so the
  -- bronze outline the rim used to add sat around finished art (user
  -- request, 2026-09-19).
  scrollBed = {
    padding = 3,
    -- The Friends list's channel only: shifted this much up (user,
    -- 2026-09-20). The other lists keep their placement.
    friendsBedY = 6,
    -- ...and its top edge alone this much further (negative is down).
    friendsBedTopY = -2,
    -- ...and its bottom edge alone this much further (negative is down).
    friendsBedBottomY = -5,
    -- ...and its up arrow alone this much higher.
    friendsUpY = 2,
    -- Friends thumb range: its top stop / bottom stop this much lower, and
    -- the down arrow this much lower in total (user, 2026-09-20).
    friendsThumbTop = 2,
    friendsThumbBottom = 1,
    friendsDownY = 5,
    -- Friends, Who and Guild channels: drawn at this opacity (40% less, user
    -- 2026-09-20). Frame alpha, not the fill's: texture alpha is unreliable
    -- here (knowledge.json rendering.texture_setalpha_darkens_not_translucent)
    -- while whole-frame alpha is what the loot window's fade relies on.
    listAlpha = 0.6,
    inset = 1,
    inner = { 0.018, 0.014, 0.010, 0.94 },
  },
}

-- The quest-giver window (QuestFrame) under the `questdialog` surface
-- (modules/questdesign.lua): the 384x512 paperdoll quadrants plus DF-main's
-- quest parchment. All rectangles are in that 384x512 design space and are
-- scaled by the live frame size. Measured off the composed quadrants:
--   visible art    x 12-352, y 13-437
--   title strip    y 14-35 (right of the portrait ring, which ends at x 72)
--   inner recess   x 24-340, y 73-426 (its dark rim is x 23 / 341, y 72 / 427)
-- The recess holds, top to bottom (user requests, 2026-09-19): the parchment
-- page with, flush with the recess's right rim, the dark scrollbar channel
-- of Blizzard's Classic dual-pane Quest Log -- both ending where the text
-- area ends -- then the Dialog Box divider, then a darker footer across
-- the full
-- recess width holding the 30-high red action buttons.
M.modernWow.questDialog = {
  designWidth = 384,
  designHeight = 512,
  -- Hit rect and the retained UnrealUI panel (the close button's anchor):
  -- the art's visible bounds, as insets from the frame edges.
  art = { left = 12, top = 13, right = 32, bottom = 75 },
  -- DF-main's page: the top-left cell of questbackgroundparchment (texels
  -- 1-300 x 1-408 of 1024; DF-main ChangeQuestFrame and ChangeGossipFrame both
  -- use only this cell). It is opaque and runs from the recess's left rim to
  -- the channel (300 -> 291 wide); the torn top and bottom `edge` rows keep
  -- their authored height while only the plain middle is compressed.
  parchment = {
    atlas = 1024,
    u1 = 1, u2 = 301, v1 = 1, v2 = 409,
    edge = 24,
    left = 24, top = 73, width = 291, bottom = 388,
  },
  -- The scrollbar channel: texels x 139-163, y 74-407 of DF-main's
  -- ui-questlogdualpane-right (256x512), grey rim on its left, dark interior
  -- from x 142. Drawn 1:1 in width, as tall as the page, flush right. The
  -- `cap` rows at each end hold the metal brackets (texel y 90 and 391) and
  -- keep their height; only the plain middle is compressed (334 -> 315), so
  -- the brackets land at design y 89 and 371.
  channel = {
    width = 256, height = 512,
    u1 = 139, u2 = 164, v1 = 74, v2 = 408,
    cap = 24,
    left = 315, top = 73, bottom = 388,
  },
  -- The footer under page and channel: DF-main's dark rock window body
  -- (ui/frame/background-rock, the texture its FrameBackgroundSolid draws),
  -- sampled 1:1 from its top-left and shaded to about half brightness so it
  -- reads darker than the recess around it (rock mean 48, recess 33).
  footer = {
    atlas = 1024,
    left = 24, top = 388, right = 340, bottom = 426,
    shade = 0.5,
  },
  -- The dedicated Dialog Box divider between page and footer.
  -- M.modernWow.horizontalBar owns its atlas cells and three-slice geometry;
  -- this token owns only its placement across the page, centred on the
  -- footer's top edge.
  divider = {
    -- Across the page only; the channel closes its own bottom square below.
    left = 24, right = 315, y = 388,
  },
  -- The channel's end squares have no outer edge in the source (the
  -- dual-pane window's frame closed them), so each is closed with the
  -- channel-width bracket (texel rows 87-92, x 139-163): its line (texel
  -- row 90) sits at `bottomLine` under the bottom square and, flipped
  -- vertically, at `topLine` over the top square (user request, 2026-09-19).
  channelEnds = {
    v1 = 87, v2 = 93, line = 90,
    topLine = 73, bottomLine = 388,
  },
  -- The native scroll frame over the page, clear of the channel and the
  -- button row, and the Slider of the Modern WoW scrollbar
  -- (U.StyleModernWowScrollbar) centred in the channel's dark interior
  -- (x 318-340; the Slider is 16 wide, nudged 1 left of the measured centre
  -- 329 after an in-game check, 2026-09-19). The channel's two end
  -- compartments -- texel rows 74-89 and 392-407, outside the brackets, drawn
  -- at design y 73-88 and 372-387 -- hold the arrows (user request,
  -- 2026-09-19). The Slider is the track; its 11-high steppers hang
  -- M.modernWow.scrollbar.arrow.gap (8) beyond each end, so these ends centre
  -- them in the compartments (75-86, 374-385) and run the track between the
  -- brackets. The text ends 10 above the page's bottom so the torn edge
  -- stays clear of it.
  scroll = { left = 24, top = 78, width = 288, height = 300 },
  -- Reward / required item slots: the native two-column grid was laid out for
  -- a 300-wide page and the right column ran past this narrower one (user
  -- report, 2026-09-19). Each slot is `width` wide; its name box and name
  -- text shrink by the same amount, the icon keeps its size.
  items = { width = 138 },
  -- downArrowY: the down arrow alone sits 2 lower in its compartment (in-game
  -- check, 2026-09-19); positive is up.
  scrollBar = { left = 320, top = 94, bottom = 366, downArrowY = -2 },
  -- Action buttons in the footer: bottom edge of the 30-high button in design
  -- units (6 clear of the divider above, 2 of the recess rim below, after an
  -- in-game check, 2026-09-19), and the outer edges of the left and right
  -- buttons.
  buttons = { bottom = 424, left = 28, right = 336 },
  -- NPC name, centred in the title strip between the ring and the close
  -- button; close button inset from the art's top-right corner.
  title = { x = 203, y = 24, color = { 1.00, 0.82, 0.00, 1.00 } },
  close = { right = 6, top = 5 },
  -- Greeting-row labels on parchment. The dark-panel questState gold is
  -- illegible here: available and ready-to-turn-in quests take the heading
  -- ink, an accepted unfinished quest a faded ink (ActiveQuestIcon's grey
  -- carries the state), and hover a warmer red-brown.
  row = {
    available = { 0.30, 0.13, 0.02, 1.00 },
    complete  = { 0.30, 0.13, 0.02, 1.00 },
    active    = { 0.36, 0.32, 0.27, 1.00 },
    unknown   = { 0.16, 0.12, 0.08, 1.00 },
    hover     = { 0.62, 0.22, 0.02, 1.00 },
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
-- window, whose height does not change. `buttonWidthGrow` and
-- `buttonHeightGrow` enlarge the live textured control; `buttonOffsetX` and
-- `buttonOffsetY` nudge it from the measured bed. The third bed is genuinely
-- narrower than the other two -- that is the art, not a measurement slip.
M.modernWow.questLog.buttonCell = {
  { x =  22 / 507, width = 112 / 507 },
  { x = 144 / 507, width = 111 / 507 },
  { x = 265 / 507, width =  71 / 507 },
}
M.modernWow.questLog.buttonBottom = 15 / 440
M.modernWow.questLog.buttonHeight = 14 / 440
M.modernWow.questLog.buttonWidthGrow = 4
M.modernWow.questLog.buttonHeightGrow = 4
M.modernWow.questLog.buttonOffsetX = -2
M.modernWow.questLog.buttonOffsetY = -2
-- Clearance between the details page's reward grid and the scroll channel's
-- left edge (modules/questlogdesign.lua design.FitRewardItems).
M.modernWow.questLog.itemPageMargin = 6

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

  -- Spell buttons: two columns of six. `textGap` separates the ornate border
  -- from its name; `placedTextGap` preserves the Professions page's spacing,
  -- where that border is hidden. The name column is what remains.
  -- `buttonScale` shrinks the spell button, and with it the slot frame,
  -- background and name shadow sized from it (user request, 2026-09-13: 30%
  -- smaller than the client's own button).
  grid = { left = 90, top = 36, columnPitch = 200, rowPitch = 64,
           columns = 2, textGap = 1, placedTextGap = 18,
           textInset = 4, nameY = -3,
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
  -- atlas, converted from fractions. The spell border instead uses the
  -- top-left cell of the user-supplied 8116691 atlas, reduced to half its
  -- authored size. They are all measured around a 37-unit spell button
  -- (`designButton`); sizes and offsets scale with the live one.
  parts = {
    atlas = 256,
    designButton = 37,
    slotFrame      = { texture = M.modernWow.path ..
                                 "ui\\spellbook\\8116691",
                       left = 0, top = 0, right = 140, bottom = 136,
                       width = 70, height = 68, x = -6, y = -4,
                       centerX = 35, centerY = 34,
                       -- The transparent icon opening, expressed in the
                       -- half-size drawing space used by width/height.
                       square = { left = 22.5, right = 59.5,
                                  top = 12, bottom = 48.5 } },
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
                       -- The burst and the text streak meet at atlas x=79 but
                       -- need different vertical anchors. Keeping them as one
                       -- region puts the streak above the name shadow when the
                       -- burst's square is correctly centred on slotFrame.
                       --
                       -- The atlas packs the streak hard against the burst at
                       -- that seam: the retail effect is one continuous flame,
                       -- so the burst's own right-hand glow is simply cut off
                       -- there, at full alpha across the square's rows. Any
                       -- crop of the whole cell therefore ends on lit texels
                       -- and draws a bright 1-unit line down the icon's right
                       -- edge (user report, 2026-09-20).
                       --
                       -- Only the half from the cell's faded left edge to the
                       -- square's centre is authored cleanly, so the burst is
                       -- that half drawn twice: once as measured, once with
                       -- its texture coordinates swapped left-for-right (the
                       -- flip idiom used by questdesign's channel ends). The
                       -- two meet on the square's centre line and rebuild a
                       -- symmetric burst whose outer edges carry the authored
                       -- fade on both sides. `right` is that mirror axis, and
                       -- must stay equal to the square's horizontal centre.
                       burst = { left = 0, top = 0, right = 54.25,
                                 bottom = 95 },
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
  --
  -- `streakMax` is the name streak's own peak, 20% under the burst's (user
  -- request, 2026-09-21): the streak is a far larger lit area than the burst,
  -- so at a shared peak it out-read the icon it belongs to. Both halves of
  -- the burst keep `alphaMax`, and the two share `alphaMin` and the phase, so
  -- the mark still breathes as one.
  barGlowPulse = { pulsePeriod = 2.5, alphaMin = 0.25, alphaMax = 0.675,
                   streakMax = 0.54 },

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

-- The classic-wow Spellbook's "Not on action bars" mark
-- (modules/spellbookclassicglow.lua; user request, 2026-09-17), in place of
-- the flat accent outline. Reuses modern-wow art read-only: action-bar art
-- over the icon, sized to the button, and only the Spellbook-Parts streak
-- behind the name -- never the atlas' burst/slot frame. Pulses with the
-- modern-wow book's own timing.
--
-- `streak` places that cell against the native 37-unit SpellButton: its LEFT
-- edge `x` units right of the button's RIGHT, its centre `y` units above the
-- button's centre (y up), `width` x `height` (squashed from the cell's ~89
-- aspect height: it overran the name and rank, user report 2026-09-17).
-- Placement is numeric against the button, never the native name string.
--
-- `icon` lists the textures drawn over the icon, in draw order. Each is drawn
-- `layers` times additively with its own `pulse` alpha range, on the shared
-- phase (user requests, 2026-09-17): the button highlight is the border
-- effect, stacked because one copy read too faint; the indicator sits above
-- it at reduced opacity.
M.classicSpellBookBarGlow = {
  iconGrow = 0,
  icon = {
    { texture = M.modernWow.texture.actionButtonHover, layers = 2,
      pulse = { alphaMin = 0.6, alphaMax = 1.0 } },
    { texture = M.modernWow.texture.actionIndicator, layers = 1,
      pulse = { alphaMin = 0.2, alphaMax = 0.45 } },
  },
  parts = M.modernWow.spellBook.texture.parts,
  atlas = M.modernWow.spellBook.parts.atlas,
  streakCell = M.modernWow.spellBook.parts.barGlow.streak,
  -- 44 then read too thin (user report, 2026-09-17).
  streak = { x = -2, y = 1, width = 112, height = 56 },
  pulse = M.modernWow.spellBook.barGlowPulse,
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

-- The classic-wow native Spellbook's Professions page
-- (modules/spellbookclassicprof.lua; user request, 2026-09-17): the same
-- Dragonflight page as M.modernWow.spellBook.professions, drawn inside the
-- client's own 384x512 window, which cannot widen the way the modern-wow book
-- does.
--
-- `page` is the rect, in window units from SpellBookFrame's TOPLEFT, that the
-- page art (M.modernWow.spellBook.page's canvas) is stretched over. Chosen to
-- cover the native parchment below the header and above the bottom tabs; NOT
-- measured off the client's art, so tune here. Every page texel of the
-- professions token maps through it.
--
-- `text` places each spell button's name and rank beside it, as the modern-wow
-- book does (M.modernWow.spellBook.grid textGap/nameY/subY).
--
-- `tab`: owned tabs are created from the client's own tab template (the one
-- SpellBookFrameTabButton1/2 use in 1.12 FrameXML; WORKING_SOURCE, not
-- runtime-verified). The Spellbook tab takes the native first tab's anchor,
-- read once at install; `gap` is the chain offset used when the native second
-- tab's offset cannot be read, and `fallback` the anchor when the first
-- tab's cannot.
M.classicWow.spellBookProfessions = {
  -- `height` runs the page art down to just above the window's bottom bevel:
  -- 348 left a bare native band over the tabs and 366 ran onto the border
  -- itself (user reports, 2026-09-18).
  -- 4 narrower than 326, kept centred by the same 2 units on `left` (user
  -- request, 2026-09-18).
  page = { left = 21, top = 74, width = 322, height = 357 },
  canvas = M.modernWow.spellBook.page,
  text = { gap = 8, nameY = -3, subY = 2 },
  tab = {
    template = "CharacterFrameTabButtonTemplate",
    gap = -16,
    -- Added between the Spellbook and Professions tabs only (user request,
    -- 2026-09-18).
    extraGap = 4,
    fallback = { point = "CENTER", relativePoint = "BOTTOMLEFT", x = 79, y = 61 },
  },
}

-- Talent-tree classification data. This is game data -- which class tree a
-- background file names, the colour Blizzard/DF-main give that tree and the
-- role it serves -- rather than theme chrome, so it lives outside M.modernWow
-- and every talent drawing path reads it: modules/talentsmodern.lua as well as
-- modules/talentsmodernwow.lua. M.modernWow.talents aliases the three fields
-- under its own names.
M.talentTree = {
  -- Vanilla talent rules: five points open the next tier, the first point is
  -- granted at level 10 and one more at every level to the cap.
  pointsPerTier = 5,
  firstTalentLevel = 10,
  maxLevel = 60,

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
  color = {
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
  roles = {
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

  -- The client's own talent art, named once for every drawing path. The tree
  -- background is knowledge.json / talent.tab_info_background_textures
  -- (BEHAVIOR_VERIFIED); the rest are the files the stock 1.12 TalentFrame
  -- templates name, which DF-main also loads by these exact paths
  -- (WoW-DragonflightUI-main/XML/Talents.xml DFTalentBranchTemplate,
  -- DFTalentArrowTemplate). They are not runtime-verified here, and a missing
  -- texture is invisible rather than an error
  -- (textures.gettexture_echoes_missing_path).
  texture = {
    backgroundBase = "Interface\\TalentFrame\\",
    branches   = "Interface\\TalentFrame\\UI-TalentBranches",
    arrows     = "Interface\\TalentFrame\\UI-TalentArrows",
    slot       = "Interface\\Buttons\\UI-EmptySlot-White",
    rankBorder = "Interface\\TalentFrame\\TalentFrame-RankBorder",
    highlight  = "Interface\\Buttons\\ButtonHilight-Square",
  },

  -- Blizzard TALENT_BRANCH_TEXTURECOORDS / TALENT_ARROW_TEXTURECOORDS, keyed
  -- 1 = requirements met, -1 = not met. Game data on Blizzard's own branch and
  -- arrow sheets, so every talent path that draws those sheets -- or an
  -- imported copy of them -- reads this one table.
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
}

-- Talent window, classic-wow (modules/talentsclassic.lua): the same
-- three-tree interface the other two paths draw, housed in the client's own
-- chrome (user request, 2026-09-21).
--
-- The tree headers are the modern-wow headers (user request, 2026-09-21) and
-- carry that theme's imported art; everything else here is the client's own.
-- The window is Blizzard's DialogBox frame, each
-- tree sits in Blizzard's tooltip-bordered inset, and the tree background,
-- talent slot, rank border, highlight, branch and arrow sheets are the client's
-- own files named once in M.talentTree.texture. Only the drag-band, rule and
-- text colours come from UnrealUI, which is what rules/unreal-ui-design.md
-- asks of a classic-wow addon-owned extra.
--
-- The grid and background numbers are deliberately the same measurements the
-- modern-wow path uses, because both measure the *client's* tree artwork: the
-- 198-wide painted column of <background>-TopLeft/-BottomLeft, a 46-unit node
-- pitch and 30-unit buttons. Only the housing differs.
M.classicWow.talents = {
  texture = {
    -- Blizzard's generic dialog housing (DialogBorderTemplate) and the tooltip
    -- inset every stock window puts a list or tree inside. Backdrop edge art
    -- does draw on this client -- what fails is a fractional edgeSize
    -- (rendering.backdrop_edge_fractional_not_rasterized), so both edges below
    -- are whole units, the way M.modernWow.statBoxes already ships.
    windowBackground = "Interface\\DialogFrame\\UI-DialogBox-Background",
    windowBorder     = "Interface\\DialogFrame\\UI-DialogBox-Border",
    insetBackground  = "Interface\\Tooltips\\UI-Tooltip-Background",
    insetBorder      = "Interface\\Tooltips\\UI-Tooltip-Border",
    -- Header art (user request, 2026-09-21): the tree header is the same
    -- header the modern-wow path draws -- the TalentFrame-Parts parchment cell
    -- vertex coloured with the tree's TALENT_INFO colour under its gold rim,
    -- the golden-square icon frame, the portrait-ring spent-points ring over
    -- the stone disc, and the role icons at the top right. This is the one
    -- place imported theme media enters the classic-wow talent window; the
    -- housing, the tree inset and every sheet below the header stay the
    -- client's own art. Paths are named here, never in the module.
    talentFrameParts = M.modernWow.path .. "ui\\talents\\talent-frame-parts",
    iconBorder       = M.modernWow.path .. "ui\\golden-square-border",
    roleIcons        = M.modernWow.path .. "ui\\talents\\role-icons",
    portraitRing     = M.modernWow.path .. "ui\\frame\\portrait-ring",
    pointsBackground = M.modernWow.texture.portraitBackground,
  },
  -- Three 208-wide panels, 12 units of dialog border each side, 1 between.
  design = { width = 650, height = 448 },
  -- `top` is the dialog's title band above the trees; `left`/`right`/`bottom`
  -- clear the 32-unit DialogBox edge.
  inset = { left = 12, top = 58, right = 12, bottom = 14 },
  window = { tileSize = 32, edgeSize = 32, inset = 11 },
  panelInset = { tileSize = 16, edgeSize = 16, inset = 4 },
  title = { y = 17 },
  status = { y = 38 },
  -- The client's own close button, moved to the dialog's corner and left in its
  -- native art: classic-wow never restyles a stock control.
  close = { x = -8, y = -8 },
  dragInset = 40,

  trees = 3,
  panel = { width = 208, height = 376, gap = 1 },
  -- The tree art, cropped to its painted columns exactly as the modern-wow
  -- path crops the same client files. `y` is where it starts below the header,
  -- which is also where the tree inset's content begins.
  background = {
    x = 5, y = 40, width = 198, topHeight = 256, bottomHeight = 75,
    topTexCoord = { 0.19921875, 0.97265625, 0, 1 },
    bottomTexCoord = { 0.19921875, 0.97265625, 0, 0.4140625 },
    -- The 1-unit light rule along the art's top edge, as the stock talent
    -- panel has.
    ruleAlpha = 0.25,
  },
  -- Header band above each tree inset. Every number below is the one
  -- M.modernWow.talents.header carries, because this is deliberately the same
  -- header (user request, 2026-09-21) measured against the same artwork. See
  -- that table for the provenance of each cell and crop, and keep the two in
  -- step when either is re-measured.
  header = {
    x = 5, y = 5, width = 198, height = 33,
    -- Where the tree inset starts below the header: the band's own bottom.
    bedTop = 38,
    texCoord = { 0.00390625, 0.77734375, 0.546875, 0.61132813 },
    borderTexCoord = { 0.00390625, 0.77734375, 0.61523438, 0.67968750 },
    iconX = 1, iconY = 1, iconSize = 32,
    iconBorder = { canvas = 256, left = 32, top = 30, right = 224, bottom = 221 },
    pointsSize = 23, pointsX = 10, pointsY = -6,
    -- The portrait ring's square crop, as the modern-wow window's own portrait
    -- takes it (M.modernWow.talents.frame.portrait.ringTexCoord); this path has
    -- no themed window portrait to read it from.
    ringTexCoord = { 0.0078125, 0.6171875, 0.0078125, 0.6171875 },
    pointsDisc = { crop = 156, left = 19, top = 19, right = 131, bottom = 131 },
    pointsTextY = -2,
    nameX = 47, nameY = 9, nameRight = 32,
    roleIcon = {
      size = 16, x = -6, y = -9, gap = 1,
      cells = {
        DAMAGER = { 0.25, 0.5, 0, 1 },
        TANK    = { 0.5, 0.75, 0, 1 },
        HEALER  = { 0.75, 1, 0, 1 },
      },
    },
  },
  -- Node capacity matches the other paths; Vanilla fills 7 of the 11 rows.
  grid = { left = 20, top = 52, pitch = 46, button = 30, designButton = 37,
           rows = 11, columns = 4 },
  slot = { size = 64 },
  rankBorder = { size = 32, x = 0, y = 0 },
  icon = { crop = { 0.08, 0.92, 0.08, 0.92 } },

  -- Blizzard's own dialog colours: gold title and headings, white body, and
  -- the dark fills its DialogBox and tooltip insets are drawn over.
  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  statusColor = { 1.00, 1.00, 1.00, 1.00 },
  nameColor = { 1.00, 0.82, 0.00, 1.00 },
  pointsColor = { 1.00, 1.00, 1.00, 1.00 },
  -- The window body reads at 90% (user requests, 2026-09-21: 80, then 90 --
  -- 80 left the world showing through). This is the backdrop's own colour on
  -- the DialogBox background texture, so only the body fades: the border keeps
  -- its own alpha below, and the tree insets draw their own fill over it.
  windowFill = { 1.00, 1.00, 1.00, 0.90 },
  windowEdge = { 1.00, 1.00, 1.00, 1.00 },
  insetFill = { 0.00, 0.00, 0.00, 0.80 },
  insetEdge = { 0.40, 0.40, 0.40, 1.00 },
  -- Rank readout: the game's own talent-state colours, as the stock talent
  -- button uses -- green while learnable and not maxed, gold at max, grey when
  -- locked.
  rankColor = {
    normal    = { 1.00, 0.82, 0.00, 1.00 },
    available = { 0.10, 1.00, 0.10, 1.00 },
    maxed     = { 1.00, 0.82, 0.00, 1.00 },
    disabled  = { 0.50, 0.50, 0.50, 1.00 },
  },
  -- A locked talent's icon is desaturated and dimmed to this tint.
  disabledIcon = { 0.65, 0.65, 0.65 },

  pointsPerTier = M.talentTree.pointsPerTier,
  firstTalentLevel = M.talentTree.firstTalentLevel,
  maxLevel = M.talentTree.maxLevel,
  branchCoords = M.talentTree.branchCoords,
  arrowCoords = M.talentTree.arrowCoords,
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
    -- The client's own talent files come from the one shared table; only the
    -- branch and arrow sheets are the theme's imported copies of them.
    backgroundBase = M.talentTree.texture.backgroundBase,
    slot       = M.talentTree.texture.slot,
    rankBorder = M.talentTree.texture.rankBorder,
    highlight  = M.talentTree.texture.highlight,
    branches   = M.modernWow.path .. "ui\\talents\\talent-branches",
    iconBorder = M.modernWow.path .. "ui\\golden-square-border",
    pointsBackground = M.modernWow.texture.portraitBackground,
    roleIcons  = M.modernWow.path .. "ui\\talents\\role-icons",
    arrows     = M.modernWow.path .. "ui\\talents\\talent-arrows",
    talentFrameParts = M.modernWow.path .. "ui\\talents\\talent-frame-parts",
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
  pointsPerTier = M.talentTree.pointsPerTier,
  firstTalentLevel = M.talentTree.firstTalentLevel,
  maxLevel = M.talentTree.maxLevel,
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
  -- DF-main TALENT_BRANCH_TEXTURECOORDS / TALENT_ARROW_TEXTURECOORDS. Those are
  -- Blizzard's own cells on Blizzard's own sheets, and the theme's imported
  -- copies of those sheets keep their layout, so the one table in M.talentTree
  -- serves this path and the classic one alike.
  branchCoords = M.talentTree.branchCoords,
  arrowCoords = M.talentTree.arrowCoords,

  -- Theme-neutral tree data (M.talentTree) under this table's own field
  -- names, so tal.TreeLookup keeps reading `defaultColor`/`treeColor`/
  -- `treeRoles` unchanged.
  defaultColor = M.talentTree.defaultColor,
  treeColor = M.talentTree.color,
  treeRoles = M.talentTree.roles,
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

-- The Modern WoW dropdown (core/dropdown.lua, user request 2026-09-19): the
-- closed control and its popup list framed with the same ThinBorder
-- eight-slice as the talent panels, over a dark fill. `borderSize` is the
-- drawn corner size: the panels' 16 would overlap on the 28-high control
-- (16 + 16 > 28), so the dropdown draws the square pieces at 12. The value
-- stays light neutral and the owned arrow glyph takes the warm heading gold.
M.modernWow.dropdown = {
  border = M.modernWow.talents.texture.panelBorder,
  borderSize = 12,
  -- The fill stops this far inside the outer edge, so nothing dark shows
  -- past the border's transparent outer pixels and rounded corners.
  fillInset = 3,
  fill = { 0.02, 0.02, 0.02, 0.92 },
  listFill = { 0.02, 0.02, 0.02, 0.97 },
  arrowColor = { 1.00, 0.82, 0.00, 1.00 },
  -- The arrow glyph's offset from the control's right edge (the flat
  -- component uses -4; user asked 3 further left, 2026-09-19).
  arrowX = -7,
}

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
    missingIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
    beastTrainingIcon = "Interface\\Icons\\Ability_Hunter_BeastCall02",
    -- Achievement metal border around the item-stat panel.
    metalJoint = M.modernWow.path .. "ui\\borders\\metal-border-joint",
    metalLeft  = M.modernWow.path .. "ui\\borders\\metal-border-left",
    metalTop   = M.modernWow.path .. "ui\\borders\\metal-border-top",
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
    -- Cropped to its painted area (alpha bbox 1,1-268,20 of DF-main's
    -- 1275,39-1584,60 cell): the 41 transparent columns on its right made the
    -- hover bar draw visibly shorter than the selection bar.
    highlight      = { left = 1276, top = 40,  right = 1543, bottom = 59 },
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
             -- 2026-09-15), so it is lowered onto the bar; then raised 2 (user
             -- request, 2026-09-17), then lowered 1 (same day).
             labelY = -2, collapseWidth = 11, collapseHeight = 8,
             -- Collapse glyph's gap from the header art's right edge.
             collapsePadding = 5,
             -- How far an expanded category's recipes are drawn up towards
             -- its header (user request, 2026-09-17).
             recipePull = 4,
             -- Header art's gap from each list panel edge, equal on both
             -- sides so it stays centred: 6px narrower than the selection
             -- bars' 3px inset (user request, 2026-09-17).
             panelInset = 6,
             -- While the list scrolls, the header art ends this far left of
             -- the scrollbar track's left edge (user request, 2026-09-17).
             scrollGap = 4 },
  recipe = { height = 20, iconX = 4, iconWidth = 13, iconHeight = 15,
             labelX = 21, labelY = -2, countGap = 2, padding = 10,
             -- Selection and hover bars span the list panel (user request,
             -- 2026-09-17): `barInset` is their gap from each panel edge. 3,
             -- not 2: at 2 the art touched the panel border (user report,
             -- 2026-09-17). The category header art uses `header.panelInset`.
             barInset = 3, selectedHeight = 19,
             -- Space under the last recipe of a category, before the next
             -- category header (user request, 2026-09-17).
             groupGap = 6,
             -- Tracked-recipe check at the row's right edge (user request,
             -- 2026-09-17). Its art is read from the "Track this recipe"
             -- CheckButton's own checked texture, so the list shows the same
             -- tick the box does; `checkFallback` is used only if that read
             -- fails.
             -- checkY: SetPoint offset, negative lowers it (user request,
             -- 2026-09-17: 2px down).
             checkSize = 16, checkRight = 2, checkY = -2, checkGap = 2,
             checkFallback = "Interface\\Buttons\\UI-CheckBox-Check" },
  -- Same MinimalScrollBar geometry as Character > Skills. The Slider owns
  -- only the track; U.StyleModernWowScrollbar hangs its 11px arrows 8px past
  -- either end, so the two 19px gaps keep the complete control in the list.
  scroll = { width = 8, right = 7, topGap = 19, bottomGap = 19 },

  schematic = { gap = 2, right = 5, bottom = 33, inset = 28,
                icon = 37, nameGap = 14, lineGap = 4, sectionGap = 12,
                reagentGap = 6,
                -- Reagent icon 20% under DF-main's 37 (user request,
                -- 2026-09-16), then 20% under that again (2026-09-17). The
                -- rows are measured from the silver slot frame round each
                -- icon (pw.ReagentGeometry): `reagentLabelGap` from the
                -- "Reagents" heading to the first frame, `reagentSpacing`
                -- between frames, and the text `reagentTextGap` right of the
                -- icon, taking the rest of `reagentWidth`.
                reagentWidth = 180, reagentIcon = 24,
                reagentLabelGap = 4, reagentSpacing = 3, reagentTextGap = 9,
                -- Extra drop of the "Reagents" heading, and so of every
                -- reagent under it (user request, 2026-09-17: 8, then 10
                -- more).
                reagentHeadingShift = 18,
                reagentColumn = 6, maxReagents = 8 },
  -- "Track this recipe" above the recipe icon: the client's own 20-unit
  -- CheckButton, as the modern-wow Spellbook's toggles use, lifted above the
  -- form's children. Right-aligned (user request, 2026-09-16): `right` is
  -- the box's inset from the schematic's top-right corner, matching the stat
  -- panel's right edge, with the label to its left.
  -- labelGap 6, not 2: the label overlapped the box (user report,
  -- 2026-09-17).
  -- y -9, not -5: lowered 4 (user request, 2026-09-17). The stat panel
  -- hangs from the box (stats.trackGap).
  track = { right = 16, y = -9, size = 20, levelLift = 4, labelGap = 6 },
  -- The ThinBorder rim DF-main's InsetFrameTemplate draws round both panels.
  border = { size = 16 },

  -- Item-stat panel in the schematic's top-right corner for an equippable
  -- product (user request, 2026-09-16): the product tooltip's lines after its
  -- name, in the tooltip's own colours. Offsets are the panel's outer edge
  -- from the schematic's top-right corner; the name label stops `nameGap`
  -- short of it.
  -- `top` clears the right-aligned Track checkbox above the panel.
  -- trackGap: space from the track box's bottom to the panel's top edge
  -- (user request, 2026-09-17).
  stats = { width = 210, right = 16, trackGap = 10, padding = 13, lineGap = 2,
            columnGap = 8, nameGap = 8, maxLines = 30, fillInset = 4,
            fillColor = { 0.00, 0.00, 0.00, 0.55 },
            -- Measured from the achievement border art. The joint is a 32px
            -- bottom-right corner whose 7-texel bars end at texel 25; the edge
            -- strips carry a 9-texel bar on their outer side, painted to
            -- texel 453 of 512. Joints are drawn at 9/7 so both bars match,
            -- and edges start `edgeInset` in, under the joints' straight bars.
            -- borderScale sizes the whole rim: units per edge texel (user
            -- request, 2026-09-16: thinner than the authored 9-unit bar).
            joint = { canvas = 32, extent = 26, thickness = 7 },
            edge = { canvas = 16, length = 512, painted = 454, thickness = 9 },
            edgeInset = 20, borderScale = 0.6 },
  -- Equip locations that are not gear: they carry no stats worth a panel.
  statsSkipEquipLoc = { INVTYPE_BAG = true, INVTYPE_QUIVER = true,
                        INVTYPE_AMMO = true },

  button = { width = 80, height = 22, right = 9, bottom = 7,
             createAllGap = 86, stepWidth = 23, stepGap = 3,
             countWidth = 30, countGap = 4, capWidth = 12,
             glyphWidth = 11, glyphHeight = 8,
             hoverAlpha = 0.5, disabledAlpha = 0.4, maxCount = 99,
             -- Player cast bar docked left of Create All while crafting.
             castBarGap = 6,
             -- Extra nudge of the docked bar, in UI units (user request).
             castBarShiftX = -10, castBarShiftY = 5 },

  titleColor = { 1.00, 0.82, 0.00, 1.00 },
  rankTextColor = { 1.00, 1.00, 1.00, 1.00 },
  -- Category labels are white at rest (user request, 2026-09-17); hover is
  -- still marked by the collapse glyph's additive glow.
  headerColor = { 1.00, 1.00, 1.00, 1.00 },
  headerHoverColor = { 1.00, 1.00, 1.00, 1.00 },
  -- Recipe label before its row is filled; hovered or selected labels are
  -- HIGHLIGHT_FONT_COLOR, every other one takes its difficulty colour.
  recipeColor = { 0.886, 0.863, 0.839, 1.00 },
  recipeHoverColor = { 1.00, 1.00, 1.00, 1.00 },
  -- Recipe label and selection/hover bar tint by difficulty, the native
  -- TradeSkillTypeColor values (user request, 2026-09-16). The bars draw the
  -- white `highlight` cell: the gold `selected` cell cannot be tinted to
  -- orange, green or grey.
  difficultyColor = {
    optimal = { 1.00, 0.50, 0.25, 1.00 },
    medium  = { 1.00, 1.00, 0.00, 1.00 },
    easy    = { 0.25, 0.75, 0.25, 1.00 },
    trivial = { 0.50, 0.50, 0.50, 1.00 },
  },
  nameColor = { 1.00, 0.82, 0.00, 1.00 },
  labelColor = { 1.00, 0.82, 0.00, 1.00 },
  bodyColor = { 1.00, 1.00, 1.00, 1.00 },
  missingColor = { 0.50, 0.50, 0.50, 1.00 },
  cooldownColor = { 1.00, 0.13, 0.13, 1.00 },
  buttonTextColor = { 1.00, 0.82, 0.00, 1.00 },
  buttonDisabledColor = { 0.50, 0.50, 0.50, 1.00 },
}

-- Modern WoW tracked-recipe HUD (modules/crafttracker.lua). Keep the complete
-- token separate from M.craftTracker so this theme's stronger missing-reagent
-- contrast cannot alter the frozen modern or classic-wow drawing paths.
M.modernWow.craftTracker = {
  width = 220, minHeight = 20, indent = 8, lineGap = 2, recipeGap = 8,
  handleLevel = 2,
  headerColor  = { 1.00, 0.82, 0.00, 1.00 },
  headerHoverColor = { 1.00, 1.00, 1.00, 1.00 },
  headerPressedColor = { 1.00, 0.65, 0.00, 1.00 },
  doneColor    = { 1.00, 1.00, 1.00, 1.00 },
  pendingColor = { 0.60, 0.60, 0.60, 1.00 },
}

-- UnrealQuest-measured three-slice action-button cells in buttons/128RedButton.tga
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
  -- The same row under a second name, for a caller whose hover is the glow
  -- below rather than a second face (user request, 2026-09-22: change the
  -- texture on the click). Profiling the sheet's bands shows this row is
  -- DARKER than the resting one -- 64,1,1 against 107,2,1 -- which is a
  -- pressed face, not a lit one; the lit state is the bloom. UnrealQuest
  -- reads it as its hover, so the cells stay where they are and this is an
  -- alias, not a move.
  pressed = { barTop = 783, capLeft = 378, capTop = 1043 },
  -- The grey pair, measured off the file's alpha with the same 2 px / 3 px
  -- lead the cells above use: bar opaque at y 655-774, short button at
  -- x 265-375, y 1045-1164.
  disabled = { barTop = 653, capLeft = 262, capTop = 1043 },
  -- The bar glow, measured off the file's own alpha (2026-09-22): a soft red
  -- bloom at x 15-423, y 424-486, the only band on the sheet that is not a
  -- button face. It is this atlas's counterpart of the close button's
  -- highlight cell, so a hovered button keeps its resting face and takes the
  -- glow over it (user request, 2026-09-22) instead of swapping to the hover
  -- row. `glowMargin` and `glowIntensity` are UnrealUI's numbers, not the
  -- art's. A negative margin insets the bloom inside the face it lights, and
  -- the intensity scales an ADDITIVE texture's contribution through its vertex
  -- colour -- the light it adds, not its opacity, so it is on the RGB rather
  -- than the alpha.
  --
  -- Reported in game 2026-09-22: at 2 and full intensity the hover was too
  -- bright and too large, and at -3 and 0.5 it could not be seen at all. The
  -- bloom is a dark red over an already-red face, so halving what it adds and
  -- cropping its core together leave nothing. These are the values between the
  -- two -- the glow at the face's own rect, a fifth of its light taken off.
  glow = { 15, 424, 418, 490 },
  glowMargin = 0,
  glowIntensity = 0.8,
}

-- Cells in buttons/plus-minus-button, measured off the file's own alpha
-- channel (2026-09-22): the occupied column runs are 2-21 and 26-45, the row
-- runs 0-21 and 24-45, so each button is a 20x22 cell. Left column normal,
-- right column pushed; plus on top, minus below. `size` is the authored cell,
-- which is what the control is drawn at unless a caller scales it.
M.modernWow.plusMinusCell = {
  sheet = 64,
  width = 20,
  height = 22,
  plusNormal   = {  2, 22,  0, 22 },
  plusPushed   = { 26, 46,  0, 22 },
  minusNormal  = {  2, 22, 24, 46 },
  minusPushed  = { 26, 46, 24, 46 },
}

-- The gold-rimmed sibling, buttons/128GoldRedButton.tga (512x1024), with the same
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
  -- The same four states as the red atlas (user request, 2026-09-22), and the
  -- same numbers: profiling this sheet shows the row at 783 is darker than the
  -- resting one -- 64,1,1 against 107,2,1, exactly as in 128RedButton -- so it
  -- is the pressed face, and the bar glow sits at the same x 15-423, y 418-489
  -- on both files. Only the sheet height differs, which the fractions take
  -- care of. The band here also carries a second element at x 443-506 that the
  -- red file does not; it is not the bar's glow and is left alone.
  pressed = { barTop = 783, capLeft = 296, capTop = 783 },
  glow = { 15, 424, 418, 490 },
  glowMargin = 0,
  glowIntensity = 0.8,
}

-- Cells in buttons/red-button, the octagonal button atlas: a 5x3 grid of 34x38
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

-- Combined-bag window. The housing uses the shared Modern WoW metal frame;
-- the portrait is the imported round backpack face. The square container
-- slots reuse the action bar's dark-grey slot face and thin grey rim
-- (actionbar/button, actionbar/button-border), matching the reference
-- combined-bag cells. Both are whole textures; `grow` is how many units each
-- extends past the button so the rim's inner edge (8/128 of the art) meets
-- the icon, the same allowance the action bar uses.
M.modernWow.bags = {
  -- Icon row bottom (actions.top 11 + 22) plus ~10 visible units to the
  -- grid; each slot face overhangs its button by ~1, hence 45 not 43.
  header = 45,
  -- Metal separator between icon row and grid: its centreline, in units
  -- below the window top (midway between icon bottom 33 and grid top 45).
  -- `extend` pushes each end that many units into the side rails.
  headerRule = { y = 39, extend = 1 },
  footer = 22,
  -- Offset out of the frame's top-left corner by half its size (21), then
  -- nudged 2 back in.
  portrait = { size = 42, left = -14, top = -15 },
  title = { top = 8, color = { 1.00, 0.82, 0.00, 1.00 } },
  -- The red-button close cell at the 17x17 every themed window close uses.
  close = { width = 17, height = 17, right = 9, top = 9 },
  -- Extra units on top of the shared slot gap / side padding (M.slot).
  slotGap = 1,
  sidePad = 5,
  -- Extra bottom inset for the bank windows, which have no footer strip.
  bottomPad = 5,
  -- Category-view boxes: the thin-border eight-slice at the talent panels'
  -- 16-unit cell. Its rim art covers cols 0-11 of 32 (~5.5 units), so the
  -- slots are inset 8 to keep their faces (which overhang ~1) off it.
  section = {
    border = M.modernWow.talents.texture.panelBorder,
    edge = 16,
    inset = 8,
    fill = { 0.03, 0.03, 0.03, 0.47 },  -- 0.78 less 40%
    fillInset = 3,
  },
  -- Icon row, left-aligned 3 units right of the portrait (user request,
  -- 2026-09-19): portrait right edge -14 + 42 = 28, + 3, + the slot rim's
  -- half grow (2.5, rounded) so the visible rim, not the button, keeps the
  -- gap. 2 units below the close button's top edge (close.top 9).
  actions = { left = 34, top = 11, gap = 6, height = 22 },
  money = { right = 10, bottom = 5 },
  -- Used-slot readout, bottom left (shown in the category view).
  slotCount = { left = 10, bottom = 7 },
  slot = {
    background = M.modernWow.texture.actionButton,
    frame = M.modernWow.texture.actionButtonBorder,
    grow = 5,
    -- The rim art is mid grey; darken it toward the reference's near-black
    -- outline (vertex colour only, the file is unchanged).
    frameColor = { 0.55, 0.55, 0.55, 1 },
  },
}

-- Corpse loot window (modules/lootdesign.lua). The native LootFrame and its
-- LootButton rows stay the interaction owners -- scripted looting does not
-- work on this client (knowledge.json /
-- loot.native_shift_autoloot_and_scripted_slot_failure) -- so this only
-- redraws around them. Chrome offsets are measured from the live row
-- positions when the window first opens, never hardcoded to stock geometry.
--
-- `card` is the dark rounded row card with a thin light outline in the
-- professions atlas (user-selected, 2026-09-19): alpha bbox 0,834-188,916 of
-- the 2048x1024 canvas, drawn three-sliced with `cap` source columns per end.
-- The icon rim is the combined bag's slot rim (M.modernWow.bags.slot).
M.modernWow.loot = {
  atlas = M.modernWow.professions.texture.atlas,
  atlasSize = { width = 2048, height = 1024 },
  card = { left = 0, top = 834, right = 188, bottom = 916, cap = 12 },
  border = M.modernWow.talents.texture.panelBorder,
  streak = M.modernWow.talents.texture.topStreak,
  streakTexCoord = { 0, 1, 0.0078125, 0.34375 },
  -- Rule under the title band: the thin border's own top edge, cropped to its
  -- painted rows 0-11 of 32 (light line at row 4) and drawn at the rim's 0.5
  -- scale, so it matches the window outline. lineOffset is where the line
  -- falls below the texture's top; inset keeps it inside the side rims.
  headerRule = { texCoord = { 0, 1, 0, 0.375 }, height = 6, lineOffset = 7,
                 inset = 4 },
  slotRim = M.modernWow.bags.slot,
  fill = { 0.10, 0.10, 0.10, 0.88 },
  -- Window padding around the row block, the title band above it and the
  -- row card's extent from the icon's left edge.
  pad = 10,
  header = 28,
  footer = 8,
  cardWidth = 180,
  -- Card height is the icon's less this on each side; it starts at the icon's
  -- centre so its outline tucks behind the icon rim.
  cardInset = 3,
  title = { size = 13, y = -9, color = { 1.00, 0.82, 0.00, 1.00 } },
  -- Rarity label offset from the card's top-right (user-tuned 2026-09-19).
  quality = { size = 9, right = -6, top = 3 },
  close = { size = 20, right = -5, top = -4 },
  -- Item tooltip placed left of the window, `gap` units from its edge.
  tooltip = { gap = 4 },
  -- Drag strip over the title band: `inset` from the rim, stopping
  -- `closeGap` units short of the close button.
  drag = { inset = 3, closeGap = 8 },
  -- Press and hover art on the row button: the flat grey fill the combined
  -- bag's item slots use (core/itemslot.lua), replacing the stock bevelled
  -- squares that drew a second border over the icon rim.
  stateFill = { 0.5, 0.5, 0.5, 0.4 },
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
-- Character/Inspect quality glow shared by Modern WoW's metal gear slots and,
-- by explicit design, Classic's native gear slots. Both paths therefore use
-- the same texture, alpha and rare/common threshold rather than approximating
-- one another with different outlines.
M.gearQualityGlow = {
  texture = M.modernWow.texture.actionButtonHover,
  grow = 4,
  alpha = 0.8,
  blend = "BLEND",
  -- Blue has much lower perceived luminance than green. Reinforce rare gear
  -- with a second pass without changing any other rarity or the Modern theme,
  -- and draw both blue passes fully opaque (other rarities keep `alpha`).
  rareAlpha = 1,
  rareBoost = {
    color = { 0.08, 0.20, 1.00, 1.00 },
    grow = 4,
    blend = "ADD",
  },
}

M.modernWow.gearSlot = {
  frame = M.modernWow.path .. "ui\\character-create-diamond-metal",
  hover = "Interface\\Buttons\\ButtonHilight-Square",
  glowTexture = M.gearQualityGlow.texture,
  glowGrow = M.gearQualityGlow.grow,
  glowAlpha = M.gearQualityGlow.alpha,
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

-- The Game Settings housing keeps Forever's ButtonFrameTemplateNoPortrait
-- structure, but substitutes the Modern WoW metal atlas. Corners retain their
-- authored proportions; only the straight rails stretch between them.
M.modernWow.gameSettingsFrame = {
  corners = M.modernWow.path .. "ui\\frame\\metal-corners",
  horizontal = M.modernWow.path .. "ui\\frame\\metal-horizontal",
  vertical = M.modernWow.path .. "ui\\frame\\metal-vertical",
  -- ButtonFrameTemplateNoPortrait's anchors, from the Forever reference.
  offset = { left = -8, right = 4, top = 16, bottom = -3 },
  topLeft = { width = 75, height = 74,
              texCoord = { 0.00195312, 0.294922, 0.00195312, 0.294922 } },
  topRight = { width = 75, height = 74,
               texCoord = { 0.298828, 0.591797, 0.00195312, 0.294922 } },
  bottomLeft = { width = 32, height = 32,
                 texCoord = { 0.298828, 0.423828, 0.298828, 0.423828 } },
  bottomRight = { width = 32, height = 32,
                  texCoord = { 0.427734, 0.552734, 0.298828, 0.423828 } },
  edgeTop = { height = 74,
              texCoord = { 0, 1, 0.00390625, 0.589844 } },
  edgeBottom = { height = 32,
                 texCoord = { 0, 0.5, 0.597656, 0.847656 } },
  edgeLeft = { width = 75,
               texCoord = { 0.00195312, 0.294922, 0, 1 } },
  edgeRight = { width = 75,
                texCoord = { 0.298828, 0.591797, 0, 1 } },
  -- The body sits inside the rim's visible metal. These values keep the
  -- settings background below the border instead of extending through it.
  body = { left = 3, top = 18, right = 3, bottom = 3 },
  -- Settings-specific layout clearance; the outer rim itself remains at its
  -- authored size.
  content = { side = 9, rail = 28 },
  titleOffsetY = 8,
}

-- The Modern WoW game menu's caption plate (modules/gamemenu.lua): a small
-- diamond-metal box drawn by U.ModernWowMetalFrame from the same
-- ui/character-create-diamond-metal atlas as the menu window itself (user
-- request, 2026-09-23). Its centre sits `centerY` units from the window's top
-- edge, like the flat plate; its width is the caption's width plus
-- `textPadding`, never less than `minWidth`. `textY` centres the caption.
M.modernWow.titlePlate = {
  height = 32,
  minWidth = 112,
  textPadding = 48,
  centerY = -3,
  textY = -1,
}

-- The Modern WoW game menu window (modules/gamemenu.lua), in units. Rows are
-- `buttonWidth` x `buttonHeight` 128RedButton faces centred in a `width`
-- window; the first starts `top` below the window top, `spacing` separates
-- rows and `groupSpacing` the client's own group breaks. `labelY` nudges row
-- labels onto the face's bevelled centre.
M.modernWow.gameMenu = {
  width = 200,
  buttonWidth = 152,
  buttonHeight = 30,
  top = 42,
  bottom = 22,
  -- Both gaps 3 units tighter by user request (2026-09-13); a negative
  -- spacing lets the faces' transparent padding overlap.
  spacing = -0.5,
  groupSpacing = 5,
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

-- User-supplied reaction wash behind the target's name. Placed the way
-- DF-main places its TargetFrame NameBackground (Target.mixin.lua: 135 wide on
-- a 126-wide health bar, bottom edge on the bar's top edge): it spans the whole
-- health opening, left edge to right edge, so it reads as the housing's name
-- strip instead of a short patch. The portrait ring is part of the housing
-- art, which draws BELOW this wash (overlay +20, text layer +21), so the wash
-- stops at the ring's outer edge rather than running under it. Only the width
-- is stretched. left/right are insets from the bar's edges (negative extends
-- outward), y is positive up.
--
-- Height and y belong to the file M.modernWow.texture.targetReaction names,
-- because the two shipped cuts spend different fractions of their canvas on
-- the empty rows below the strip's flat cut. The pair below each place the
-- strip's flat cut 2.2 units below the health bar's top edge; `height` is then
-- trimmed from the top, so the value here draws the strip 4 units shorter than
-- the cut's own proportions (a requested trim, 2026-09-19).
--
--   target-reaction-type  128x16, strip rows 0-11:  height 21,   y -7.5
--   target-reaction       172x29, strip rows 0-25:  height 17.5, y -4
--
-- `left` and `right` place the strip's open end on the bar's left edge and run
-- its notched end 7 units past the bar's right edge (requested, 2026-09-19).
-- The target frame reads portrait-right, and this wash draws above the housing
-- art, so that overhang crosses the portrait ring's outer edge rather than
-- stopping at it. Widening from here grows this same end unless `left` is
-- given a negative value.
M.modernWow.targetReaction = {
  height = 17,
  left = 0,
  right = -7,
  y = -7.5,
  -- Wash opacity: 60% so the housing texture shows through.
  alpha = 0.6,
  -- Peak alpha of the additive red pulse over the wash while the target is
  -- an enemy (modules/modernwow.lua mw.ReactionPulseTick). Timing is shared
  -- with M.modernWow.playerFX; this peak is kept lower so it reads soft.
  pulseMax = 0.5,
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
  -- The player's and target's own name, in the warm gold this theme's titles
  -- use (#eeb901, user request 2026-09-20). Those two frames only: a party row
  -- keeps the shared neutral text, where several names are read side by side
  -- and gold on every one of them carries no hierarchy. The target's reaction
  -- is still shown by the reaction bar's vertex colour, which is unchanged.
  nameColor = { 0.93, 0.73, 0.00, 1.00 },
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
  -- 68 and 65: six pixels over DragonflightUI's player size of 62 and five
  -- over the target's proportional 60. The portrait draws UNDER the ring
  -- overlay, so
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
  playerFrame    = { size = 68, x = 74, y = 43.0, model = 43,
                     backgroundTrim = 2, backgroundY = 1 },
  targetFrame    = { size = 65, x = 71, y = 43.5, model = 43 },
  -- The classification tiers share the target's ornament, so they carry the
  -- same numbers. Nothing sizes from them today -- the target entry's art is
  -- "targetFrame" and a tier change only swaps the texture, never the portrait
  -- -- but a stale value here would be a trap the day one does.
  frameRare      = { size = 65, x = 71, y = 43.5, model = 43 },
  frameElite     = { size = 65, x = 71, y = 43.5, model = 43 },
  frameRareElite = { size = 65, x = 71, y = 43.5, model = 43 },
  frameBoss      = { size = 65, x = 71, y = 43.5, model = 43 },

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
-- Blizzard's IconAlertAnts flipbook. Its own call site is
-- Blizzard_CommentatorSpell.lua:
--
--   TextureUtil.AnimateTexCoords(self.Ants, 256, 256, 48, 48, 22, elapsed, 0.01)
--
-- which walks the grid row-major and 1-based: for frame f,
-- left = mod(f - 1, columns) * cell / sheet and top = the row above
-- ceil(f / columns) * cell / sheet. `interval` is Blizzard's throttle, one
-- frame per hundredth of a second; a surface driving it off a coarser ticker
-- steps by elapsed time instead and simply runs the cycle slower.
--
-- Only 22 of the 25 cells are played, and the sheet's last 16 pixels on each
-- axis are outside the grid, so this cannot be treated as a plain 5x5 sheet.
M.modernWow.iconAlertAnts = {
  sheet = 256,
  cell = 48,
  columns = 5,
  frames = 22,
  interval = 0.01,
}

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

  -- Edit-mode anchors stay cool blue until selected, then turn gold. The
  -- anchor itself no longer carries that as flat colour: it draws the
  -- client's own Edit Mode nine-slice, which is authored in exactly those two
  -- states (M.modernWow.moveUI). This token remains for the hover edge the
  -- shared button style takes from the same family.
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

-- The flat tab strip every `modern` stock window wears through
-- U.StyleStockTabGroup (core/stockui.lua): Character, Social, Spellbook, Mail
-- and Merchant all read their tab face from here rather than passing their own
-- colours, so one window can never drift from the rest.
--
-- `height` is the Spellbook strip's height, adopted for every window on
-- 2026-09-20: the modern Spellbook's Spellbook/Professions row had been the
-- one strip drawn taller than the rest, the user picked it over the shared
-- size, and every other window now matches it. It is deliberately larger than
-- the 22-unit shared control height -- a tab carries a label against a window
-- edge rather than sitting inside a panel, and reads better with the room.
--
-- A tab's state is carried by its LABEL COLOUR and nothing else: the active
-- tab takes the addon accent, every other tab the neutral dim grey at 90%
-- opacity, and a hovered tab plain white. The tab's fill, outline and size do
-- not move between states -- an earlier build faded the whole inactive button
-- to 90% and it read as a greyed-out tab instead (user report, 2026-09-20).
--
-- `modern-wow` overrides these from M.modernWow.tab when it dresses a tab in
-- its own art (mw.DressTab); the greying is this flat family's and must not
-- reach that one.
M.tab = {
  height = 29,
  -- Space each side of a label. A tab is sized to its own text plus this on
  -- the left and the right, which is how the Spellbook's tabs have always
  -- been built (prof.CreateTab); every strip now does the same instead of
  -- keeping whatever width the client's template baked in (user request,
  -- 2026-09-20). U.FitStockTabStrip may still reduce it on a window whose
  -- run would not otherwise fit, as the Character sheet's does with a pet out.
  padding = 10,
  background = { 0.03, 0.03, 0.03, 0.82 },
  activeTextColor = M.color.accent,
  -- textDim with the 10% taken out of the label's own alpha, not the tab's.
  inactiveTextColor = { 0.60, 0.60, 0.60, 0.90 },
  -- Hover is plain white on any tab, and changes nothing else -- no border
  -- move, no accent outline (user request, 2026-09-20). Brighter than
  -- M.color.text on purpose: this is the one tab state that has to read as
  -- "the cursor is here" against both the accent and the grey.
  hoverTextColor = { 1.00, 1.00, 1.00, 1.00 },
}

-- The label face modern-wow keeps once mw.DressTab takes one of those flat
-- tabs over. Named rather than inherited so the Modern strip's dim-grey
-- inactive label and its faded inactive tab cannot reach the DF art, which
-- already carries the inactive state in the texture itself: warm gold on the
-- active tab, light neutral on the rest, no fade. Assigned here because
-- M.modernWow.tab is built well above M.color.
M.modernWow.tab.activeTextColor = M.color.textAccent
M.modernWow.tab.inactiveTextColor = M.color.text
-- No white hover either: this theme's hover is the art wash (hoverAlpha), so
-- the label holds still.
M.modernWow.tab.hoverTextColor = M.color.text

-- The `modern` Spellbook's Professions page. The page reuses the shared
-- profession scan and native spell-button mapping from
-- modules/spellbookprofessions.lua, but all of its chrome is the flat modern
-- system: six compact rows, one outline per surface and semantic green skill
-- progress. Coordinates are window units from SpellBookFrame's TOPLEFT.
M.spellBook = {
  professions = {
    flat = true,
    texture = {
      unlearn = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    },
    rowLeft = 24,
    primaryTop = { 58, 114 },
    secondaryTop = { 170, 226, 282, 338 },
    secondaryGap = 16,
    row = {
      -- SpellBook's flat panel runs from frame x=12 to x=354. Starting rows
      -- at x=24 leaves 12 px on the left; 318 ends them at x=342 and gives
      -- the same 12 px on the right.
      width = 318,
      height = 50,
      icon = 34,
      iconInset = 8,
      primaryTextX = 52,
      secondaryTextX = 8,
      nameY = -8,
      rankY = -27,
      missingY = -10,
      missingDetailY = -29,
      background = { 0.025, 0.025, 0.025, 0.90 },
    },
    bar = {
      x = 120,
      y = -20,
      width = 90,
      height = 10,
      textInset = 5,
      background = { 0.10, 0.10, 0.10, 0.90 },
      fill = { 0.25, 0.75, 0.30, 1.00 },
    },
    unlearn = { size = 18, x = 222, y = -16 },
    button = {
      size = 32,
      -- Keep the right-most profession spell 8 px inside the narrower row.
      x = 302,
      leftX = 264,
      y = 9,
      primaryY = 9,
      textWidth = 1,
      iconOnly = true,
    },
    tab = {
      -- This row is where the shared tab height and padding came from, so it
      -- reads the shared tokens rather than keeping the numbers twice.
      padding = M.tab.padding,
      height = M.tab.height,
      gap = 3,
      background = { 0.07, 0.07, 0.07, 1.00 },
      activeBackground = { 0.03, 0.03, 0.03, 1.00 },
    },
    nameColor = M.color.textAccent,
    subSpellColor = M.color.text,
    rankColor = M.color.textDim,
    barTextColor = M.color.text,
    missingHeaderColor = M.color.textDim,
    missingTextColor = M.color.textDim,
    missingIcon = "Interface\\Icons\\INV_Scroll_04",
    missingIconAlpha = 0.45,
    ranks = { 75, 150, 225, 300 },
  },
}

-- Loot window animation, shared by every theme (modules/lootdesign.lua). These
-- are behaviour numbers, not chrome: the animation moves and fades what the
-- client already draws, so it runs under `modern` -- where the loot window
-- stays native -- exactly as it does under the two themes that redraw it.
-- Kept out of M.modernWow for that reason.
--
-- Opening fade, in seconds: the window's ease-out, then each row's own fade
-- starting `rowDelay` in and `stagger` after the row above it. A looted item's
-- ghost eases `ghostSlide` units right over `ghost` seconds while fading;
-- back-to-back clears (Shift-click looting all) start `ghostStagger` apart.
-- `ghostWidth` is the sliding group's width and `ghostTextGap` the space
-- between its icon and the item name.
M.loot = {
  anim = { window = 0.18, row = 0.22, rowDelay = 0.06, stagger = 0.06,
           ghost = 0.35, ghostSlide = 40, ghostStagger = 0.08 },
  ghostWidth = 180,
  ghostTextGap = 6,
}

-- The `modern` theme's loot window (user request, 2026-09-19). Deliberately the
-- same key names as M.modernWow.loot for everything the window's shared
-- mechanics read -- fit, drag strip, tooltip placement, quality label -- so
-- modules/lootdesign.lua picks a token table once and the layout code is one
-- path. Values follow rules/unreal-ui-design.md: flat WHITE8X8 surfaces, one
-- 1-unit outline, near-black fill, the addon accent on the short title and on
-- the client-driven hover/press states only.
--
-- `cardWidth` is the row's extent from the icon's left edge, matched to the
-- themed window so both designs cover the same row and the looted-item slide
-- reads the same distance.
M.loot.flat = {
  pad = 10,
  header = 22,
  footer = 8,
  cardWidth = 180,
  title = { size = M.fontSize.normal, color = M.color.accent, y = -6 },
  -- Rule between the title band and the rows: 1 unit, inset to the row inset.
  rule = { inset = 8 },
  close = { size = 17, right = -3, top = -3 },
  drag = { inset = 3, closeGap = 8 },
  tooltip = { gap = 4 },
  quality = { size = M.fontSize.tiny, right = -6, top = 3 },
  -- The list row: one flat tinted surface, shorter than the icon on each side
  -- so its edge stays inside the icon's outline rather than doubling it.
  rowFill = { 0.12, 0.12, 0.12, 0.60 },
  rowInset = 3,
  -- Client-driven states on the native row button: subdued accent on hover,
  -- the accent fill on press. Nothing else replaces the stock state squares.
  hoverFill = { M.color.accent[1], M.color.accent[2], M.color.accent[3], 0.16 },
  pressFill = M.color.accentFill,
}

-- Profession window, modern theme (modules/professionsmodern.lua). The data
-- and interaction model matches the modern-wow profession window, while every
-- surface uses UnrealUI's flat design primitives and shared colour tokens.
M.professions = {
  design = { width = 720, height = 500 },
  title = { y = 9 },
  close = { x = -6, y = -6 },
  drag = { headerHeight = 44, inset = 28 },
  levels = { cover = 10, content = 1, handle = 10, close = 22 },

  professionIcon = { x = 10, y = 9, size = 28, crop = { 0.08, 0.92, 0.08, 0.92 } },
  rank = { width = 250, height = 8, y = 31 },
  rankText = { y = 30 },
  -- The skill number sits on the rank bar itself, over both the dark track and
  -- the green fill. White rather than M.color.text (user request, 2026-09-20)
  -- so it stays legible on the fill, matching the modern-wow window's own
  -- rankTextColor.
  rankTextColor = { 1.00, 1.00, 1.00, 1.00 },

  list = {
    x = 10, y = 50, width = 276, bottom = 42,
    inset = 6, rowHeight = 22, headerHeight = 24,
    headerGap = 3, groupGap = 3,
    scrollWidth = 16, scrollArrow = 16, scrollPad = 3, scrollRight = 4,
  },
  -- User-requested exception: recipe difficulty uses the exact Modern WoW
  -- profession-atlas glyphs, while the surrounding list remains flat Modern.
  difficultyIcon = {
    texture = M.modernWow.professions.texture.atlas,
    atlasWidth = M.modernWow.professions.atlas.width,
    atlasHeight = M.modernWow.professions.atlas.height,
    x = 4, width = 13, height = 15, labelX = 21,
    countGap = 4, countFontSize = M.fontSize.normal + 2,
    padding = 7, trackedGap = 4,
    cells = {
      optimal = M.modernWow.professions.cells.skillOptimal,
      medium = M.modernWow.professions.cells.skillMedium,
      easy = M.modernWow.professions.cells.skillEasy,
    },
  },
  tracked = { width = 3, inset = 4, right = 4 },
  detail = {
    x = 292, y = 50, right = 10, bottom = 42, inset = 12,
    icon = 46, nameGap = 10, lineGap = 4, sectionGap = 10,
    reagentIcon = 26, reagentRow = 32, reagentTextGap = 7,
    reagentColumn = 4, reagentGap = 8, maxReagents = 8,
    -- Top of the reagent block inside the detail pane: its heading, then the
    -- first row of reagent buttons. Both were inline literals (108 / 126) and
    -- moved up together (user requests, 2026-09-20: 10, then a further 14), so
    -- they stay one block.
    reagentLabelY = 84, reagentTop = 102,
  },
  track = { right = 10, top = 10, width = 128, height = 18 },
  stats = {
    width = 190, right = 10, top = 36, padding = 8,
    lineGap = 2, columnGap = 8, nameGap = 8,
    maxLines = 28, maxHeight = 362, level = 12,
  },
  statsSkipEquipLoc = { INVTYPE_BAG = true, INVTYPE_QUIVER = true,
                        INVTYPE_AMMO = true },
  controls = {
    right = 10, bottom = 10, width = 96, height = 22,
    gap = 4, step = 22, count = 34, maxCount = 999,
    castBarGap = 6, castBarShiftX = 0, castBarShiftY = 0,
  },

  panelColor = { 0.025, 0.025, 0.025, 0.94 },
  insetColor = { 0.04, 0.04, 0.04, 0.86 },
  headerColor = { 0.08, 0.08, 0.08, 0.96 },
  rowState = {
    hoverFillAlpha = 0.10, hoverBorderAlpha = 0.55,
    focusFillAlpha = 0.22, focusBorderAlpha = 1.00,
  },
  rankBackground = { 0.10, 0.10, 0.10, 0.90 },
  rankFill = { 0.25, 0.75, 0.30, 1.00 },
  missingColor = { 0.90, 0.25, 0.20, 1.00 },
  cooldownColor = { 0.45, 0.75, 1.00, 1.00 },
  difficultyColor = {
    optimal = { 1.00, 0.35, 0.20, 1.00 },
    medium = { 1.00, 0.78, 0.20, 1.00 },
    easy = { 0.30, 0.85, 0.35, 1.00 },
    trivial = M.color.textDim,
    used = M.color.textDim,
  },
  texture = {
    missingIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
    beastTrainingIcon = "Interface\\Icons\\Ability_Hunter_BeastCall02",
  },
}

-- Midway between the warmer #FFD200 and pure #FFFF00: clearly yellow without
-- overpowering the orange-gold frame art when drawn additively.
M.modernWow.playerFX.restColor = { 1.00, 0.909804, 0.00 } -- #FFE800

-- Talent window, modern theme (modules/talentsmodern.lua). The same interface
-- the modern-wow path draws -- all three trees side by side, addon-owned talent
-- buttons, prerequisite branches and arrows -- laid out in this theme's own
-- visual language instead: flat near-black surfaces, one 1-unit outline per
-- surface, owned glyphs and the shared accent. No modern-wow media or token is
-- read from here, and nothing here is read by that theme.
--
-- Geometry: a 4-column grid of 30-unit buttons on a 46 pitch is 168 wide and,
-- at Vanilla's 7 tiers, 306 tall; a 196-wide panel centres it with a 14 margin
-- and closes at 364 high. Three of those panels plus their gaps and the window
-- padding make the 616x422 window.
M.talents = {
  design = { width = 616, height = 422 },
  -- Window padding: `top` is the title band above the trees.
  inset = { left = 10, top = 48, right = 10, bottom = 10 },
  -- Centred header lines, offset down from the window's top edge.
  title = { y = 10 },
  status = { y = 29 },
  close = { x = -6, y = -6 },
  -- Drag handle: the title band, stopping short of the close button.
  dragInset = 26,

  trees = 3,
  panel = { width = 196, height = 364, gap = 4 },
  -- Tree header inside a panel: icon, name, role tag, spent-point count, and
  -- the 1-unit rule that closes it off from the grid.
  header = {
    inset = 8, iconSize = 26, iconY = 8,
    nameX = 8, nameY = 9, roleY = 24,
    pointsY = 9,
    ruleY = 41,
  },
  -- Node capacity matches the modern-wow grid; Vanilla fills 7 of the 11 rows.
  grid = { left = 14, top = 51, pitch = 46, button = 30, rows = 11, columns = 4 },
  -- Rank readout ("2/5"): a flat box hung off the button's bottom-right corner.
  rank = { width = 20, height = 11, x = 4, y = -2, size = M.fontSize.tiny },
  -- Prerequisite branches: a 2-unit flat line down the middle of the gap
  -- between two buttons, ending in an owned arrow glyph whose centre sits
  -- `arrowGap` beyond the button edge it points at.
  branch = { thickness = 2, arrowSize = M.fontSize.normal, arrowGap = 6 },

  icon = { crop = { 0.08, 0.92, 0.08, 0.92 } },
  panelColor = { 0.03, 0.03, 0.03, 0.85 },
  buttonColor = { 0.02, 0.02, 0.02, 0.90 },
  rankColor = { 0.02, 0.02, 0.02, 0.95 },
  -- Button outline by talent state: neutral while learnable, subdued accent
  -- once points are in it, full accent at max rank, and visibly dim when the
  -- tier or a prerequisite locks it.
  borderColor = {
    normal   = M.color.border,
    partial  = M.color.accentDim,
    maxed    = M.color.accent,
    disabled = { 0.13, 0.13, 0.13, 1.00 },
  },
  -- Branch and arrow colour: accent where the prerequisite is met, neutral
  -- grey where it is not.
  branchColor = {
    [1]  = M.color.accent,
    [-1] = { 0.32, 0.32, 0.32, 1.00 },
  },
  -- Rank text keeps the game's own talent-state colours (learnable, maxed,
  -- locked), which are semantic state rather than addon chrome.
  rankTextColor = {
    available = { 0.10, 1.00, 0.10, 1.00 },
    maxed     = M.color.accent,
    disabled  = M.color.textDim,
  },
  -- A locked talent's icon is desaturated and dimmed to this tint.
  disabledIcon = { 0.55, 0.55, 0.55 },
}

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

-- Tracked-recipe HUD (modules/crafttracker.lua), laid out like the native
-- quest tracker it sits beside: gold recipe names (NORMAL_FONT_COLOR), reagent
-- lines white once enough is carried and dimmed until then, as the tracker
-- draws finished and unfinished objectives.
M.craftTracker = {
  width = 220, minHeight = 20, indent = 8, lineGap = 2, recipeGap = 8,
  -- Direct-drag Button above the text frame (modules/crafttracker.lua).
  handleLevel = 2,
  headerColor  = { 1.00, 0.82, 0.00, 1.00 },
  headerHoverColor = { 1.00, 0.78, 0.18, 1.00 },
  headerPressedColor = { 1.00, 1.00, 1.00, 1.00 },
  doneColor    = { 1.00, 1.00, 1.00, 1.00 },
  pendingColor = { 0.80, 0.80, 0.80, 1.00 },
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

-- Border-specific tuning keeps item text on the client's semantic quality
-- colours while giving rare-slot frames a bright, saturated blue that remains
-- legible against dark item icons and the Modern WoW metal frame.
M.qualityBorder = {
  [3] = { 0.12, 0.42, 1.00, 1.00 },   -- Rare
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
  header  = 32,
  tray    = 26,   -- keyring / bag-slot button
  icon    = 16,   -- small header button (close)
  headerIcon = 22, -- header icon group: key, bags, sell, sort, merge
}

-- ---------------------------------------------------------------------------
-- Money
--
-- One coin face and one colour per denomination, shared by every readout in
-- the addon (the status overlay and, since it needs the identical look, the
-- bank purchase price and the bag total). Centralised so a second consumer
-- cannot drift from the first; see .claude/rules/unreal-ui.md on shared
-- media/state placement.
-- ---------------------------------------------------------------------------
-- User request (2026-09-20): the coin faces are UnrealUI's own art under
-- media/icons, one file per denomination, drawn the same way under every
-- theme. The stock Interface\MoneyFrame\UI-MoneyIcons atlas and its
-- horizontal slice coordinates are no longer used, so a coin now fills its
-- own texture and needs no SetTexCoord.
--
-- The knowledge record textures.separate_coin_paths_not_rendered is about the
-- *stock* UI-GoldIcon/UI-SilverIcon/UI-CopperIcon paths, which are blank on
-- this client; it says nothing about addon files. These are 16x16 32-bit RLE
-- TGAs referenced without the extension, which is the addon-texture contract
-- textures.addon_tga_paths_require_extensionless confirms and every other
-- media/icons entry above already uses.
M.money = {
  gold = {
    texture = "Interface\\AddOns\\unrealUI\\media\\icons\\coin-gold",
    color = { 1.00, 0.82, 0.00, 1.00 },
  },
  silver = {
    texture = "Interface\\AddOns\\unrealUI\\media\\icons\\coin-silver",
    color = { 0.75, 0.75, 0.75, 1.00 },
  },
  copper = {
    texture = "Interface\\AddOns\\unrealUI\\media\\icons\\coin-copper",
    color = { 0.80, 0.47, 0.29, 1.00 },
  },
}

-- ---------------------------------------------------------------------------
-- Talent Build Advisor (modules/talentadvisor.lua)
--
-- One component, two styles. Each style owns a `drawer` table with the same
-- token names, so the drawer's layout -- width, header, row pitch, rule
-- placement, footer block -- is one set of measurements written twice rather
-- than two layouts: `modern-wow` draws it in the theme's artwork, `modern`
-- draws the identical geometry with the flat system's own surfaces and rules
-- and carries `flat = true`, the single marker the module branches on.
--
-- The talent-button marks, by contrast, are one set for both styles (user
-- request, 2026-09-21) and are assigned after the table below: marching ants
-- on a talent the build still wants, the spell-alert flipbook on the one to
-- spend the point on now, and a pulsing red rim on a rank spent outside the
-- build. The three states differ by animation rather than by colour, which is
-- what the flat style's three static outlines could not do.
--
-- `released` is the single gate the module reads; both talent drawing paths
-- reach it only through the U.*TalentAdvisor* entry points.
-- ---------------------------------------------------------------------------
M.talentAdvisor = {
  released = true,

  -- The drawer's open/close motion (user request, 2026-09-21). It runs on the
  -- shared easing helper (core/easing.lua), which is this addon's one value
  -- animator: one curve drives both the fade and a short slide out of the
  -- talent window's edge, so the two cannot drift apart. Opening uses the
  -- quick ease-out, closing the softer ease-in/out, as everywhere else here.
  -- `distance` is how far behind the toggle the drawer starts: it slides out
  -- of the window to open and back into it to close (user request,
  -- 2026-09-21). The toggle draws a frame level above the drawer, so the
  -- arrow stays visible and clickable through the whole motion.
  drawerAnim = {
    distance = 26,
    openDuration = 0.20,
    closeDuration = 0.16,
  },

  -- Frame levels the advisor's three marks take above the talent button, and
  -- the level a talent window must give its rank badge to stay readable over
  -- them. The marks are frames of their own, so every region drawn on the
  -- button itself -- the rank border and its count -- is under all of them
  -- until the window lifts the badge out (user report, 2026-09-20: the next
  -- mark's flipbook covered the count).
  level = {
    soft = 10,
    wrong = 11,
    next = 12,
    -- The prerequisite arrow that points at a talent from the rank above it
    -- overlaps that talent's rim, so it needs a level over the next mark's
    -- animated border too (user report, 2026-09-21). Its frame is a sibling
    -- of the talent buttons rather than a child, so a window adds its own
    -- button offset to this number.
    arrow = 13,
    badge = 16,
  },

  styles = {
    ["modern-wow"] = {
      -- Blizzard's marching ants (user request, 2026-09-20): every talent
      -- the build still wants gets them, and the one to spend on now gets the
      -- spell alert instead, so the two marks differ by animation rather than
      -- by colour. The gold square this replaced is no longer shipped.
      --
      -- `ants` makes this a flipbook: the advisor steps one shared playhead
      -- (M.modernWow.iconAlertAnts) and carries the cell to every mark, so
      -- the whole build marches in step. grow 2 is geometry, not padding --
      -- the ring spans 0.875 of its cell, so drawing it at 34 units lays it
      -- on a 30-unit icon's rim.
      soft = {
        texture = M.modernWow.texture.iconAlertAnts,
        ants = true,
        antsInterval = 0.03,
        grow = 2,
        color = { 1.00, 1.00, 1.00, 1.00 },
        -- The ants carry the mark themselves, so this is a light breathe
        -- rather than the state: enough to separate a planned talent from a
        -- learned one, never enough to hide the ants mid-cycle.
        pulseMin = 0.75,
        pulseMax = 1.00,
        pulsePeriod = 2.50,
        -- One ticker drives both the soft pulse and the `next` flipbook, so
        -- this is also the flipbook's sampling rate: 0.03 keeps the 30-frame
        -- one-second loop from dropping frames unevenly the way the 0.04 the
        -- flat style still uses would.
        pulseInterval = 0.03,
        restAlpha = 0.90,
      },
      -- The open drawer itself (user request, 2026-09-20): the diamond-metal
      -- housing every other Modern WoW dock wears and a background-rock bed
      -- inside it. Context and role choices use 128RedButton faces; build
      -- rows use the profession recipe highlight so the list stays quiet.
      -- Absent from the flat style, which keeps its own panel and text
      -- buttons -- the whole themed path is chosen by this table existing.
      --
      -- The rock goes on ARTWORK and is anchored corner to corner, not
      -- SetAllPoints: on BACKGROUND it rendered nothing here, which
      -- modules/modernwow.lua records for the social footer's identical wash.
      --
      -- Height is not a constant. `rowsGap` and the selected bottom block sit
      -- under the build list; advisor.FitHeight adds them to the rows actually
      -- shown and drops the warning row when no points are outside the build.
      drawer = {
        width = 250,
        inset = 6,
        rockShade = 0.42,
        -- The bed reads at 70% (user requests, 2026-09-21). It is vertex
        -- alpha, not the region's own alpha: the open/close fade drives the
        -- drawer's SetAlpha, which copies itself onto this texture and would
        -- take a region alpha straight back off.
        rockAlpha = 0.70,
        titleY = -11,
        -- The title's rule (user request, 2026-09-21): the Dialog Box divider
        -- this theme already lays between a quest page and its footer, drawn
        -- across the drawer under the heading. `M.modernWow.horizontalBar`
        -- owns its atlas cells and three-slice geometry; this token owns only
        -- its placement.
        -- It runs the full width of the bed and meets the housing's rim on
        -- both sides, so its inset is the bed's own (user request,
        -- 2026-09-21), and it draws 20% thinner than the authored bar: height
        -- scales the three-slice, so its caps come down with it.
        divider = { y = -24, inset = 6, height = 8 },
        -- The same rule again between the context/role choices and the build
        -- list (user request, 2026-09-21). `yPlain` is where it lands for a
        -- class whose drawer draws no role row.
        listDivider = { y = -88, yPlain = -61, inset = 6, height = 8 },
        -- The same rule below the last visible build, held the same distance
        -- from the list as the rule above it (user request, 2026-09-21): the
        -- list rule's art ends 5 units over the first row's highlight, so this
        -- one starts 5 units under the last row's, and `gap` carries the 3
        -- units of pitch the body's trailing row does not draw.
        buildDivider = { gap = 6, inset = 6, height = 8 },
        -- The rows under the title, each measured from the drawer's top: the
        -- context row, the role row, and the build list with and without that
        -- role row. They moved down together when the divider was added, so
        -- they are tokens rather than literals in the layout.
        -- The header -- the drawer's top down to the context row -- is 30%
        -- shorter than it first shipped (user request, 2026-09-21): 50 units
        -- became 35, with the title and its rule scaled to match, and every
        -- row below moved up by that same 15.
        contextY = -35,
        roleY = -62,
        buildTop = -100,
        buildTopPlain = -73,
        titleColor = { 1.00, 0.82, 0.00, 1.00 },
        side = 10,
        buttonHeight = 22,
        labelY = -1,
        labelColor = M.color.text,
        selectedColor = { 1.00, 0.82, 0.00, 1.00 },
        -- The status line while a talent is waiting to be learned.
        statusColor = { 1.00, 0.82, 0.00, 1.00 },
        -- Role choices wear the settings atlas's wide rounded button (user
        -- request, 2026-09-21) instead of the red action face the context
        -- row keeps: it is the theme's own quiet toggle, so the two rows read
        -- as choice-then-filter rather than two actions.
        --
        -- Cell measured by alpha on the 512 sheet: the button occupies
        -- 332..417 x 11..69, and its corner round runs 13 texels, so a
        -- 16-texel cap carries the whole round inside a fixed-aspect end and
        -- leaves 54 flat texels to stretch.
        --
        -- The sheet ships one cell for this button, so state is the face's
        -- tint: it rests one step down from the authored art, comes up to it
        -- on hover, and takes the accent when chosen -- which multiplies the
        -- metal rim gold and leaves the near-black bed where it is, the same
        -- selected look the atlas draws for its own square buttons.
        roleButton = {
          texture = M.modernWow.texture.settingUI,
          sheet = 512,
          cell = { 332, 418, 11, 70 },
          cap = 16,
          restColor = { 0.78, 0.78, 0.78, 1.00 },
          hoverColor = { 1.00, 1.00, 1.00, 1.00 },
          selectedColor = M.color.accent,
          labelColor = M.color.text,
          hoverLabelColor = { 1.00, 1.00, 1.00, 1.00 },
          activeLabelColor = { 1.00, 0.82, 0.00, 1.00 },
        },
        -- One build row is exactly as tall as the highlight it draws
        -- (buildRow.height), so the pitch below leaves strictly 3 units of
        -- bed between two listed builds (user request, 2026-09-21) rather
        -- than 3 plus the slack a taller button left above and below its bar.
        rowHeight = 19,
        rowGap = 3,
        -- The band between the build list and the status block: the rule's
        -- 6 above and 8 of art, then one unit below it, so widening the gap
        -- above the rule moves the rule rather than crowding the status.
        rowsGap = 15,
        -- Bottom-anchored status stack with exactly 4 units between each text
        -- region. Without an outside-build warning the status takes that row's
        -- place and the drawer drops the warning's 18 + 4 units.
        footer = {
          legendY = 9,
          warningY = 31,
          statusY = 53,
          statusYPlain = 31,
        },
        bottomBlock = 84,
        bottomBlockPlain = 62,
        minHeight = 184,
        minHeightPlain = 162,
        buildRow = {
          texture = M.modernWow.professions.texture.atlas,
          atlasWidth = M.modernWow.professions.atlas.width,
          atlasHeight = M.modernWow.professions.atlas.height,
          cell = M.modernWow.professions.cells.highlight,
          height = M.modernWow.professions.recipe.selectedHeight,
          -- Row states (user request, 2026-09-21). The highlight is drawn on
          -- every listed build rather than only under the pointer, so each
          -- row reads as a bordered entry: neutral grey at rest, one step
          -- lighter while hovered, and the addon accent on the chosen build.
          -- Selection wins over hover, so pointing at the current build does
          -- not dim it back to grey.
          restColor = { 0.42, 0.42, 0.42, 1.00 },
          hoverColor = { 0.62, 0.62, 0.62, 1.00 },
          selectedColor = M.color.accent,
          labelColor = M.modernWow.professions.recipeColor,
          activeLabelColor = M.modernWow.professions.recipeHoverColor,
        },
      },

      -- The drawer's open/close arrow (user request, 2026-09-20). Modern WoW
      -- draws it as a themed control: a dark bed inside the theme's own
      -- ThinBorder rim, with one of the settings atlas's solid yellow arrows
      -- on top. The flat style keeps the shared text button, so this table is
      -- absent there and advisor.BuildToggle falls back to it.
      --
      -- `left` and `right` are the two glyphs' texels on the 512x512 sheet,
      -- measured by alpha rather than by their yellow alone: the arrows carry
      -- a dark outline, and boxing only the yellow clipped it. Both are taken
      -- at the same 21x34 so the two directions cannot differ in size. Drawn
      -- at 15.6x25.3 -- the box aspect, at a scale that puts the yellow 10%
      -- smaller than the first pass (user request, 2026-09-20).
      --
      -- backgroundInset keeps the bed off the rim: the ThinBorder pieces are
      -- 32px canvases whose art fills only their first rows, so a 10-unit
      -- piece draws a thin line and the rest of it is clear. Filling the
      -- button's whole rect put a black square outside that line.
      --
      -- The inset is where the bed has to stop to touch the rim, and it is
      -- measured off the art the eye actually reads -- alpha over 128 -- not
      -- off the soft falloff around it. That falloff is what an earlier pass
      -- measured, and it left a visible gap between the two (user report,
      -- 2026-09-20): thin-border-top's solid line is only rows 3-6 of its 32,
      -- so at borderSize 12 it ends 2.63 units in, while the falloff runs to
      -- 3.75. 2.5 meets the top line and tucks a fraction under the other
      -- three, which draw above the bed, and stays well inside the line's
      -- outer edge (1.1 units in) so no fill escapes the rim.
      --
      -- Both numbers scale with borderSize: inner edge 0.219 x size, outer
      -- edge 0.094 x size. Move them together.
      toggle = {
        width = 26,
        height = 46,
        background = { 0.04, 0.035, 0.030, 0.80 },
        backgroundInset = 2.5,
        borderSize = 12,
        -- The ThinBorder set has no bottom-right corner and the shared
        -- builder mirrors its bottom-left one into that slot, which at this
        -- size reads as a broken corner (user report, 2026-09-20). Blizzard's
        -- raid-frame corner is the same metal rim and is handed in instead.
        borderBottomRight = M.modernWow.path ..
                            "ui\\borders\\raidborder-bottomright",
        arrow = {
          texture = M.modernWow.texture.settingUI,
          sheet = 512,
          left = { 399, 420, 184, 218 },
          right = { 475, 496, 184, 218 },
          width = 15.6,
          height = 25.3,
          alpha = 0.85,
          hoverAlpha = 1.00,
          -- The whole glyph drops a unit while held, which is this theme's
          -- press everywhere else it has one.
          pressDrop = 1,
        },
      },

      wrong = {
        texture = M.modernWow.texture.talentIconAlert,
        -- Match the 64-unit slot art scaled by this talent path's 30/37
        -- button ratio: 51.9 units around the 30-unit ability icon.
        grow = 11,
        y = 1,
        color = { 1.00, 0.06, 0.03, 1.00 },
        alpha = 0.90,
        pulseMin = 0.35,
        pulseMax = 0.56,
        pulsePeriod = 1.625,
      },
      -- Blizzard's own "you can spend a point here" answer: the action-bar
      -- proc alert, played around the talent button. `start` is the one-shot
      -- burst, `loop` the border it settles into, and both are 5x6 grids of
      -- 30 frames whose cells are plain fractions of their own texture, so a
      -- cell's UVs are (column/columns, row/rows) with nothing to measure.
      --
      -- Durations are Blizzard's FlipBook ones -- 0.7s for the burst, 1s per
      -- loop -- but the two scales are not. ActionButtonSpellAlertTemplate
      -- draws the loop at 1.4x the button, which lands the border ON the
      -- icon's edge; here it has to sit around the icon instead (user
      -- request, 2026-09-20), so both are measured off the art:
      --
      --   loop  cell 101px, clear opening 52px  -> 0.515 of the cell
      --   burst cell 128px, clear opening 25px  -> 0.195 of the cell
      --
      -- loopScale 1.95 puts a 30-unit talent icon inside a 30.1-unit
      -- opening -- the exact fit, 5% down from the 2.05 first tried (user
      -- request, 2026-09-20) -- and keeps the border's outer glow (48.6
      -- units) inside the 52-unit slot frame. startScale holds the burst's
      -- opening at the loop's, 0.515/0.195 = 2.64x loopScale, so the handover
      -- between the two grids does not jump.
      --
      -- No SetBlendMode("ADD") here. The art carries its own alpha and the
      -- FrameXML declares no alphaMode, and additive compositing on this
      -- client is documented-not-verified
      -- (knowledge.json / rendering.setblendmode_add_inert), so the effect
      -- must not depend on it.
      next = {
        flipbook = true,
        startTexture = M.modernWow.texture.spellAlertStart,
        loopTexture = M.modernWow.texture.spellAlertLoop,
        columns = 5,
        rows = 6,
        frames = 30,
        startDuration = 0.70,
        loopDuration = 1.00,
        loopScale = 1.95,
        startScale = 5.15,
        -- The ring draws thinner than the art authored it (user requests,
        -- 2026-09-21: 15%, then another 20% off that). Scaling the whole grid
        -- down would have taken the opening with it and put the border back
        -- on the icon's edge, so the trim is a crop of every loop cell
        -- instead: its outer rows are dropped and the texture drawn exactly
        -- that much smaller, which keeps the remaining art at its own scale
        -- and the 30-unit opening where the icon fit put it.
        --
        -- Cell 101px around a 52px opening is a band 24.5 texels thick. The
        -- first pass left 20.83 of it, and 20% off that is 16.66 -- a trim of
        -- 7.84 texels per side, 0.0776 of the cell. The drawn size follows as
        -- loopScale x (1 - 2 x loopCrop).
        loopCrop = 0.0776,
        grow = 8,
        -- Kept for a revert: the autocast model this replaced.
        model = "Interface\\Buttons\\UI-AutoCastButton.mdx",
      },
    },
    ["modern"] = {
      -- The same drawer as the Modern WoW style above, drawn in UnrealUI's
      -- own flat system (user request, 2026-09-21): identical width, header,
      -- row pitch, footer and rule separations, with no theme media at all.
      -- `flat` is the one marker the module branches on -- it selects the
      -- shared components over the theme's artwork -- and every other token
      -- here is geometry or a shared colour, never a texture.
      drawer = {
        flat = true,
        width = 250,
        titleY = -11,
        -- The bed behind the whole drawer, at 90% (user request,
        -- 2026-09-21). It is the backdrop's own colour, so the open/close
        -- fade still multiplies the frame alpha over it.
        background = { 0.02, 0.018, 0.014, 0.90 },
        -- The drawer's three rules are the flat system's 1-unit line rather
        -- than the theme's Dialog Box bar, so each one is placed by the gap
        -- it has to leave rather than by the band the art filled. The title's
        -- rule is the same neutral grey as the other two (user request,
        -- 2026-09-21) rather than the accent: the heading above it already
        -- carries the accent, and a second accent line under it read as a
        -- divider competing with the title.
        divider = { y = -31, inset = 8, height = 1, color = M.color.border },
        -- The choice rows sit in their own band, with the same 10 units of
        -- drawer above them as below (user request, 2026-09-21), and the
        -- build list keeps 8 units clear of the rule at each end (user
        -- request, 2026-09-21: 3 more than it first shipped).
        listDivider = { y = -101, yPlain = -74, inset = 8, height = 1,
                        color = M.color.border },
        buildDivider = { gap = 8, inset = 8, height = 1,
                         color = M.color.border },
        contextY = -42,
        roleY = -69,
        buildTop = -110,
        buildTopPlain = -83,
        titleColor = M.color.accent,
        buttonHeight = 22,
        labelY = 0,
        statusColor = M.color.accent,
        rowHeight = 19,
        rowGap = 3,
        -- 8 units over the closing rule, its own unit, then 1 below it.
        rowsGap = 11,
        footer = {
          legendY = 9,
          warningY = 31,
          statusY = 53,
          statusYPlain = 31,
        },
        bottomBlock = 84,
        bottomBlockPlain = 62,
        minHeight = 186,
        minHeightPlain = 164,
        -- The flat twin of the themed row's highlight: the same height and
        -- pitch, and the same three states, carried by the shared flat
        -- surface and its single outline instead of the profession atlas.
        -- Neutral at rest, a dim accent edge on hover, the accent fill and
        -- outline on the chosen build; selection still wins over hover.
        buildRow = {
          flat = true,
          restFill = M.color.background,
          restEdge = M.color.border,
          hoverFill = M.color.background,
          hoverEdge = M.color.accentDim,
          selectedFill = M.color.accentFill,
          selectedEdge = M.color.accent,
          labelColor = M.color.textDim,
          hoverLabelColor = M.color.text,
          activeLabelColor = M.color.textAccent,
        },
      },
      -- The three talent marks are not listed here: both styles draw the
      -- same ones, and they are assigned below so the two cannot drift.
    },
  },
}

-- One set of talent marks for every theme (user request, 2026-09-21): the
-- marching ants on a talent the build still wants, the spell-alert flipbook
-- on the one to spend the point on now, and the pulsing red rim on a rank
-- spent outside the build. Modern used to draw three flat outlines instead,
-- which read as three colours of the same static line rather than as three
-- different states.
--
-- This is not theme chrome crossing a line. All three are the client's own
-- art -- Blizzard's SpellActivationOverlay ants and action-bar proc
-- flipbooks -- which happen to be stored under the theme's media folder, the
-- same standing exception the swing bar's Blizzard atlas has
-- (rules/unreal-ui-design.md). Nothing ornamental, and no Dragonflight
-- chrome, enters the flat theme with them.
--
-- The specs are shared by reference rather than copied: both talent windows
-- draw 30-unit talent buttons (M.talents.grid.button and
-- M.modernWow.talents.grid.button), so the measured grow, scale and cell
-- geometry transfer unchanged, and the module only ever reads them.
M.talentAdvisor.styles["modern"].soft  = M.talentAdvisor.styles["modern-wow"].soft
M.talentAdvisor.styles["modern"].wrong = M.talentAdvisor.styles["modern-wow"].wrong
M.talentAdvisor.styles["modern"].next  = M.talentAdvisor.styles["modern-wow"].next

-- ---------------------------------------------------------------------------
-- Forever settings chrome (media/Textures/forever-wow/)
--
-- The art WoW Forever's own settings window is built from, for UnrealUI's
-- grouped game-settings window (modules/gamesettings.lua). Source:
-- ForeverFrameXML-1.60.1.69913, Blizzard_Settings_Shared. Every number below is
-- the exact UiTextureAtlasMember pixel rectangle for build 1.60.1.69913, read
-- with `query.py atlasmap <name> --exact` and divided by its own sheet -- never
-- measured off a screenshot and never invented, which is that reference's
-- standing rule.
--
-- Six backing sheets are shipped whole and addressed by texture coordinates,
-- the same way buttons/setting-ui.tga already serves several controls: an atlas
-- member is a rectangle on a sheet, so cutting it out would only add files and
-- lose the power-of-two sizes the client wants.
--
-- The controls INSIDE a hosted client panel -- checkboxes, dropdowns, sliders
-- -- are not from here. By user request they come from the Modern WoW settings
-- atlas (buttons/setting-ui.tga, M.foreverWow.control below), which is
-- Blizzard's own dark control atlas, FileDataID 5412379, and the same visual
-- family as the window around them.
M.foreverWow = {}
M.foreverWow.path = "Interface\\AddOns\\unrealUI\\media\\Textures\\forever-wow\\"

M.foreverWow.texture = {
  -- FileDataID 1318750, the Options atlas: inner frame, divider, category row
  -- states and both tab sets.
  options    = M.foreverWow.path .. "settings\\options",
  -- FileDataID 4571485: the category list's expand/collapse chevron.
  listExpand = M.foreverWow.path .. "settings\\list-expand",
  -- The ButtonFrameTemplateNoPortrait nine-slice, on three sheets exactly as
  -- Blizzard splits it: corners 8069116, top/bottom edges 8069118, left/right
  -- edges 8069114.
  corners    = M.foreverWow.path .. "ui\\frame-metal-corners",
  edgeH      = M.foreverWow.path .. "ui\\frame-metal-edge-h",
  edgeV      = M.foreverWow.path .. "ui\\frame-metal-edge-v",
  -- FileDataID 4700695, FlatPanelBackgroundTemplate's two bottom corners.
  panelBg    = M.foreverWow.path .. "ui\\panel-background",

  -- Imported 2026-09-21 (user request): the Forever build's own art for the
  -- controls its settings window draws. Member rectangles are in
  -- media/Textures/forever-wow/ATTRIBUTION.md, read with query.py.
  --
  -- FileDataID 8069110: Forever's bronze-rimmed common-dropdown sheet, the
  -- Forever variant of buttons/setting-ui.tga (5412379) that
  -- M.foreverWow.control draws from today. WowStyle2Dropdown's
  -- common-dropdown-c-* beds and the dropdown menu background.
  dropdown   = M.foreverWow.path .. "settings\\common-dropdown",
  -- SearchBoxTemplate's shared grey border, magnifier and clear-button sheet
  -- (3281887), selected by the user for the settings search field.
  search      = M.foreverWow.path .. "settings\\search",
  -- 8086474: checkbox-minimal, the Forever settings checkbox bed.
  checkbox   = M.foreverWow.path .. "settings\\checkbox-minimal",
  -- 4614134: checkmark-minimal / -disabled (the only sheet carrying the tick).
  checkmark  = M.foreverWow.path .. "settings\\checkmark-minimal",
  -- 8086434: MinimalSliderWithSteppers -- bar caps, stretched middle, thumb
  -- and the two stepper arrows.
  slider     = M.foreverWow.path .. "settings\\minimal-slider",
  -- 8107305: RedButton-Exit / MiniCondense / Expand / Highlight, the
  -- ButtonFrameTemplate close and minimise buttons.
  redButton  = M.foreverWow.path .. "ui\\red-button",
  -- UIMenuButtonStretchTemplate's four client files, the face Forever's own
  -- Key Bindings page gives every binding button (user request, 2026-09-22).
  -- Client paths Interface\Buttons\UI-Silver-Button-Up / -Down / -Highlight /
  -- -Select, 128x32 each; see M.foreverWow.control.binding for the slices.
  silverUp        = M.foreverWow.path .. "buttons\\ui-silver-button-up",
  silverDown      = M.foreverWow.path .. "buttons\\ui-silver-button-down",
  silverHighlight = M.foreverWow.path .. "buttons\\ui-silver-button-highlight",
  silverSelect    = M.foreverWow.path .. "buttons\\ui-silver-button-select",
}

-- SettingsPanel's own measurements (Blizzard_SettingsPanel.xml,
-- Blizzard_CategoryList.xml, Blizzard_SettingsList.xml). Forever's window is a
-- fixed 920x724; UnrealUI sizes its window to the client panel it is hosting,
-- so what is kept here are the insets, heights and gaps, not the window size.
M.foreverWow.panel = {
  headerHeight = 64,      -- Options_InnerFrame sits at TOPLEFT 17,-64
  innerInset = { left = 17, top = 64, right = 22, bottom = 46 },
  titleY = -5,            -- NineSlice.Text, TOP 0,-5
  categoryWidth = 199,    -- CategoryList, 199 wide
  categoryInset = { left = 18, top = 76, bottom = 46 },
  containerGap = 16,      -- Container TOPLEFT from CategoryList TOPRIGHT
  containerRight = -22,
  buttonWidth = 96,       -- Apply / Close, UIPanelButtonTemplate 96x22
  buttonHeight = 22,
  buttonInset = { right = 16, bottom = 16 },
  buttonGap = 2,
  listHeaderHeight = 50,  -- SettingsList.Header
  listTitleInset = { x = 7, y = -22 },
  rowHeight = 20,         -- SettingsCategoryListButtonTemplate, 175x20
  rowWidth = 175,
  -- Label anchors TOPLEFT 36,1 / BOTTOMRIGHT 0,1 and justifies LEFT. The 36
  -- leaves room for the expand toggle, which sits at LEFT 9 and is 22x22 --
  -- every row is indented the same whether or not it has one.
  rowLabelInset = 36,
  rowToggleInset = 9,
  rowToggleSize = 22,
  headerRowHeight = 30,   -- SettingsCategoryListHeaderTemplate, 175x30
  spacerHeight = 18,      -- SettingsCategoryListSpacerTemplate
  tabHeight = 37,         -- MinimalTabTemplate
  tabInset = { x = 32, y = -27 },
  tabGap = 5,
}

-- Cells on settings\options (1024x1024).
M.foreverWow.options = {
  sheet = 1024,
  -- The recessed inner plate the category list and the page sit on.
  innerFrame = { 1 / 1024, 887 / 1024, 150 / 1024, 768 / 1024 },
  innerSize = { width = 886, height = 618 },
  -- The plate drawn narrower than its authored width, and with a narrower
  -- category list than the art was authored for (user requests, 2026-09-22:
  -- the window 30% narrower, then the list 30% narrower). Measured off the
  -- sheet the same day by profiling the member's columns: a 2-texel rim at
  -- member x 0..2, the seam that separates the category list from the page at
  -- x 199..201, and the right rim at x 883..885, with the top and bottom rows
  -- rounding off inside x 6 / 882. Between those the field is completely
  -- flat -- nothing else varies along x.
  --
  -- So the plate is a horizontal FIVE-slice, and the two flat fields take
  -- every width change:
  --
  --   0 .. rim                 left rim and the rounded corners, 1:1
  --   rim .. seam              the list field, squeezed to the list's width
  --   seam .. seam + seamKeep  the seam itself and the page's left rim, 1:1
  --   ... .. -keepRight        the page field, squeezed to what is left
  --   -keepRight .. end        right rim and corners, 1:1
  --
  -- Squeezing the whole member instead drags the seam into the list, which is
  -- the same defect that made stretching it for a wider page unacceptable; the
  -- seam is drawn at the category list's own right edge instead, whatever
  -- width the list is given.
  -- `top` / `bottom` do the same for the height (user request, 2026-09-22:
  -- the window 30% shorter). Profiled the same way: a 2-texel rim at member
  -- y 0..1 and a 3-texel rim at y 615..617, nothing else along y, so the rims
  -- and corners are drawn 1:1 and the flat band between them is squeezed. The
  -- plate is therefore a 5x3 grid of pieces.
  innerSlice = { rim = 8, seam = 199, seamKeep = 11, keepRight = 30,
                 top = 8, bottom = 8 },
  -- 630x1: stretched along the frame, never tiled.
  divider = { 1 / 1024, 631 / 1024, 147 / 1024, 148 / 1024 },
  dividerHeight = 1,
  -- Category row states, 187x21 each. There is no "normal" member: an
  -- unselected, unhovered row draws nothing at all.
  rowActive = { 604 / 1024, 791 / 1024, 1 / 1024, 22 / 1024 },
  rowHover  = { 793 / 1024, 980 / 1024, 1 / 1024, 22 / 1024 },
  rowStateSize = { width = 187, height = 21 },
  -- SettingsCategoryListHeaderMixin picks Options_CategoryHeader_<n> per
  -- header. Both are 199x144: a 30-unit header row with a long gradient that
  -- fades down behind the rows under it, which is why the art is far taller
  -- than the row it labels.
  categoryHeader = {
    width = 199,
    height = 144,
    [1] = {   1 / 1024, 200 / 1024, 1 / 1024, 145 / 1024 },
    [2] = { 403 / 1024, 602 / 1024, 1 / 1024, 145 / 1024 },
  },
  -- MinimalTabTemplate's three-slice, both states. The caps are 7 wide and
  -- keep their aspect; only the 1-texel middle stretches. The active set is 3
  -- units taller (26 against 23) and that is the whole state change -- the tab
  -- is not resized, the taller art simply meets the frame.
  tab = {
    capWidth = 7,
    height = 23,
    activeHeight = 26,
    left         = { 607 / 1024, 614 / 1024,  52 / 1024,  75 / 1024 },
    middle       = { 604 / 1024, 605 / 1024,  24 / 1024,  47 / 1024 },
    right        = { 607 / 1024, 614 / 1024, 105 / 1024, 128 / 1024 },
    activeLeft   = { 607 / 1024, 614 / 1024,  24 / 1024,  50 / 1024 },
    activeMiddle = { 604 / 1024, 605 / 1024,  49 / 1024,  75 / 1024 },
    activeRight  = { 607 / 1024, 614 / 1024,  77 / 1024, 103 / 1024 },
  },
}

-- SettingsPanel.SearchBox / SearchBoxTemplate, from
-- Blizzard_SettingsPanel.xml and Shared/InputBox/InputBoxTemplates.xml.
M.foreverWow.search = {
  width = 175,
  height = 22,
  border = {
    texture = M.foreverWow.texture.search,
    sheetWidth = 256,
    sheetHeight = 128,
    height = 20,
    capWidth = 8,
    left = { 227, 243, 43, 83 },
    middle = { 1, 225, 43, 83 },
    right = { 1, 17, 85, 125 },
  },
  icons = {
    texture = M.foreverWow.texture.search,
    sheetWidth = 256,
    sheetHeight = 128,
    search = { 19, 43, 85, 109 },
    clear = { 45, 65, 85, 105 },
    size = 10,
    buttonSize = 17,
  },
  textInset = { left = 16, right = 20 },
}

-- The settings LIST a page is rebuilt into (user request, 2026-09-21), from
-- Forever's own numbers: Blizzard_SettingsList.lua (verticalPad 10, padLeft
-- 25, spacing 9; the ScrollBox 15 left of the header and 20 short of the
-- right edge), Blizzard_SettingControls.xml (section header 45 tall, title at
-- 7,-16; every control row 26 tall) and Blizzard_SettingControls.lua (label
-- LEFT at indent+37 and RIGHT at CENTER-85, indent 15; checkbox and slider
-- LEFT at CENTER-80, the slider 3 up; dropdown LEFT at CENTER-48, 3 up), and
-- Blizzard_SettingsList.xml (DefaultsButton 96x22 at TOPRIGHT -36,-16).
--
-- The slider numbers are MinimalSliderWithSteppersTemplate's at the controls'
-- 0.58 (see M.foreverWow.control): the group sits at CENTER-46 (-80) and its
-- Slider is inset 11 (19) inside it, so the track starts at CENTER-35 and is
-- 122 wide (212); the value is its RightText, 14 (25) right of the track. scrollbarInset leaves MinimalScrollBar's 11-high stepper plus its
-- 8 gap at each end. UnrealUI's own choices: scrollbarWidth and wheelStep.
M.foreverWow.list = {
  -- Every list spacing below is Forever's number at the controls' 0.58 (user
  -- requests, 2026-09-21: smaller controls, then "adapt the gap with these new
  -- sizes"), so the gaps keep Forever's proportions to the controls they
  -- separate. Forever's own value follows each in brackets. The header, the
  -- Defaults button and the window are not scaled.
  padTop = 6,          -- (10)
  padBottom = 6,       -- (10)
  padLeft = 14.5,      -- (25)
  padRight = 11.5,     -- (20)
  -- Every line is one height (user request, 2026-09-22): the tallest drawn
  -- control, the dropdown bed (29.25, its shadow included), with no extra
  -- gap -- the bed's own shadow is the space between two dropdowns, and a
  -- checkbox or slider line sits in the same band so the page reads evenly.
  spacing = 0,         -- (9)
  rowHeight = 29.25,   -- (26)
  sectionHeight = 26,  -- (45)
  sectionTitle = { x = 4, y = -9 },  -- (7, -16)
  indent = 8.7,        -- (15)
  -- Flush with the row (user request, 2026-09-22: "remove the gap on the left
  -- side of the option name"), instead of Forever's 37 -- which leaves room
  -- for a checkbox this list does not draw in the label column. The row's own
  -- inset from the plate is list.padLeft, which stays: the hover band reaches
  -- 7.5 left of the row and would otherwise cross the plate's rim.
  labelInset = 0,      -- (37)
  labelRight = -49,    -- (-85)
  -- The gap a row's label keeps from the leftmost unit its control draws
  -- (user request, 2026-09-22: "reduce the gap between the option name and
  -- the elements to its minimum"). Forever's own 5 at the controls' 0.58, the
  -- same 3 units its label cap already keeps from the checkbox column. The
  -- column is Forever's CENTER-anchored one, but this window's list is far
  -- wider than Forever's, so L.MeasureColumn slides the column LEFT -- never
  -- right -- until the tightest row on the page is this far from its control.
  -- 48, not Forever's scaled 3: 10 more, then 15, then 20 again (user
  -- requests, 2026-09-22), so a label is clearly separated from its control.
  labelGap = 48,       -- (5)
  -- Forever's own control column, kept as the measurement. The list places
  -- the box on the left arrow's edge instead (user request, 2026-09-22), 3
  -- units right of this: Forever's column is the slider GROUP's edge, and its
  -- Back arrow sits 3 inside that.
  checkboxX = -46,     -- (-80)
  -- The slider group starts where the checkbox does; its track is inset 11
  -- (19) inside it.
  sliderX = -31.7,     -- (-61) the group at -46 plus the grown 14.3 inset
  sliderY = 1.5,       -- (3)
  -- Forever's own dropdown column, kept as the measurement. The list no
  -- longer places from it: every dropdown is drawn at the slider's span
  -- instead (user request, 2026-09-22), so L.DropdownSpan derives both its
  -- LEFT and its width from the slider and stepper tokens.
  dropdownX = -28,     -- (-48)
  dropdownY = 1.5,     -- (3)
  -- A nudge of the whole dropdown group -- bed and both steppers -- off the
  -- line L.DropdownSpan puts it on (user request, 2026-09-22: 2 left), so its
  -- left arrow reads level with the checkbox beside it rather than measuring
  -- level with the slider's smaller arrow.
  dropdownShift = -2,
  sliderWidth = 158.6,
  valueGap = 18.2,
  defaultsWidth = 96,
  defaultsHeight = 22,
  defaultsInset = { x = -36, y = -16 },
  actionWidth = 96,
  actionHeight = 22,
  tabGap = 5,
  scrollbarWidth = 12,
  scrollbarInset = { top = 20, bottom = 20, right = 2 },
  -- The bare space between the list's right edge and the scrollbar track.
  -- Read by both the ScrollFrame's anchor and the column measurement, so the
  -- two cannot disagree about where the bar starts -- and by the Key Bindings
  -- page (gs.ListContent), so its listing keeps the same gap as every list.
  -- Widened from Forever's 4 by user request, 2026-09-22.
  scrollbarGap = 14,
  -- How much of the space between the rightmost control on the page and the
  -- scrollbar is taken away (user request, 2026-09-22: that gap reduced by
  -- 70%). L.MeasureColumn pushes the whole control column right by this much
  -- of it, so the tightest row -- normally a slider, whose value sits right of
  -- its Forward arrow -- keeps the remaining 30%. The label gap is then
  -- whatever is left of the row; labelGap above is only its floor, used when a
  -- control overflows the row and the column has to come back left.
  rightGapTrim = 0.7,
  -- Stand-in width for a slider's value while its FontString cannot be
  -- measured (it is written by the client's own OnValueChanged), so the column
  -- is not placed as though the value were absent.
  valueWidth = 30,
  -- One row and its gap, as 35 was at Forever's sizes.
  wheelStep = 29.25,
  -- A value bar the client DRAWS beside a control rather than a setting to
  -- change -- the Sound page's microphone level, beside Test Microphone
  -- (reported in game, 2026-09-22: with no row of its own it stayed anchored
  -- where the client had drawn it on the panel, outside this window, and kept
  -- drawing while the list scrolled under it). The list adopts it like any
  -- other control and dresses it in the Modern WoW XP bar's material
  -- (M.modernWow.texture.xpFill / xpBorder and M.modernWow.xpbar's own
  -- overhangs, user request 2026-09-22) -- the same theme this list already
  -- borrows MinimalScrollBar from. Every number here is UnrealUI's own: the
  -- client's bar has no authored size in this window.
  meter = {
    -- Thinner than a control, as a bar rather than something to click.
    height = 11,
    -- A bar that rides its owner's row draws in that row's label column,
    -- which is empty -- a button carries its own text -- this far in from the
    -- row's label inset and this far short of the control column.
    sidecarInset = 4,
    sidecarGap = 10,
    -- Floor for either placement, so a narrow column still leaves a bar.
    minWidth = 40,
  },
  -- HoverBackgroundTemplate (Blizzard_SettingControls.xml): white at 10%,
  -- across the whole row from 10 left of it to 5 short of its right edge --
  -- at the controls' 0.75. Shown while the row or its control is hovered
  -- (SettingsListElementMixin). Translucency through the vertex colour's
  -- alpha, which this client honours, not Texture:SetAlpha, which darkens
  -- (rendering.texture_setalpha_darkens_not_translucent).
  hover = { color = { 1, 1, 1, 0.1 }, left = -7.5, right = -3.75, interval = 0.05 },
  -- GameFontNormal gold for a row label, GameFontHighlight white for its
  -- value and GameFontHighlightLarge for a section title.
  labelColor = { 1.00, 0.82, 0.00, 1 },
  valueColor = { 1.00, 1.00, 1.00, 1 },
  sectionColor = { 1.00, 1.00, 1.00, 1 },
  -- A client section box handed back on detach. The colour getters are absent
  -- here (rendering.backdrop_color_getters_absent), so these are Vanilla's
  -- OptionFrameBoxTemplate OnLoad values -- WORKING_SOURCE, not read back.
  boxBorderColor = { 0.4, 0.4, 0.4, 1 },
  boxColor = { 0.15, 0.15, 0.15, 1 },
}

-- Cells on settings\list-expand (128x128), 28x26 each.
M.foreverWow.listExpand = {
  sheet = 128,
  width = 28,
  height = 26,
  collapsed = {  1 / 128, 29 / 128, 56 / 128, 82 / 128 },
  expanded  = { 31 / 128, 59 / 128, 56 / 128, 82 / 128 },
  -- The rest of SettingsExpandableSectionTemplate's bar
  -- (Blizzard_SettingControls.xml 191), which the same sheet carries and the
  -- Key Bindings page draws on every binding category (user request,
  -- 2026-09-22). Three pieces: `Options_ListExpand_Left` 12x26 at the bar's
  -- TOPLEFT, `_Options_ListExpand_Middle` 1x26 stretched between the caps,
  -- and the +/- cap above -- `Options_ListExpand_Right` collapsed,
  -- `Options_ListExpand_Right_Expanded` expanded -- at its TOPRIGHT.
  left   = {  1 / 128, 13 / 128, 84 / 128, 110 / 128 },
  middle = {  0,        1 / 128, 28 / 128,  54 / 128 },
  leftWidth = 12,
  -- The template's own: the Button is 30 tall inset 20 from the section's
  -- right edge, and its GameFontNormal title sits at LEFT 21, +2.
  barHeight = 30,
  -- The category bar spans the entire Key Bindings listing.
  barInsetRight = 0,
  -- Keep the bar inside its recycled row: this leaves a visible three-pixel
  -- gap above and below it, so the scroll frame cannot clip its lower edge.
  verticalInset = 3,
  titleInset = { x = 12, y = 0 },
  titleColor = { 1.00, 1.00, 1.00, 1 },
}

-- The Key Bindings page's own two header strings, which the client draws on a
-- plate ABOVE its panel -- outside this window's content frame, where they
-- read as loose text beside the page (reported in game 2026-09-22). They are
-- moved inside the panel; the binding-set line sits to the title's right.
-- These offsets are UnrealUI's because the client's plate is hidden here.
M.foreverWow.keys = {
  titleInset  = { x = 12, y = -8 },
  outputInset = { x = 12, y = -24 },
  titleGap = 6,
  outputGap = 6,
  promptGap = 6,
  commandHeaderNudge = 10,
  keyHeaderNudge = { -10, -18 },
  characterShift = { x = 6, y = 13 },
  characterTextGap = 3,
  characterTextLift = 0,
  -- Unbind and Default keep the page's bottom-left corner once Okay and
  -- Cancel have left it for the window's own. They have to be re-anchored
  -- rather than left alone: this client chains the four (Okay off Cancel,
  -- Unbind off Okay, measured 2026-09-22), so moving Okay would otherwise
  -- carry them to the window corner with it.
  actionInset = { x = 42, y = 20 },
  actionGap = 4,
  -- How far the listing's LEFT edge sits from the column a list page's rows
  -- start on: negative is further left (user request, 2026-09-22, 8 pixels).
  -- Screen pixels, like listDrop. The right edge does not move with it --
  -- gs.AlignBindingList takes the same amount off the width -- so the gap
  -- between the listing and the scrollbar stays the one every page has.
  listNudge = -8,
  -- How far the listing sits below where the client puts it (user request,
  -- 2026-09-22). SCREEN pixels, unlike every other number here, because that
  -- is how it was asked for and how it reads on the page; gs.AlignBindingList
  -- divides it by the rows' own pixels-per-unit. Applied once per attach to
  -- the row that carries the chain, so the rows below it follow.
  listDrop = 6,
}

-- ButtonFrameTemplateNoPortrait (Blizzard_SharedXML NineSliceLayouts.lua). The
-- offsets are Blizzard's own: the corners overhang the frame by 8 left and 4
-- right, 16 above and 3 below, which is what makes the metal rim sit proud of
-- the panel rather than inside it.
M.foreverWow.nineSlice = {
  cornerSize = 190,          -- every corner piece is 190 wide
  cornerTopHeight = 190,
  cornerBottomHeight = 200,  -- the bottom pair is 10 taller
  edgeThickness = 190,
  offset = { left = -8, right = 4, top = 16, bottom = -3 },
  corners = {
    sheet = { width = 1024, height = 512 },
    topLeft     = { 193 / 1024, 383 / 1024,   1 / 512, 191 / 512 },
    topRight    = { 193 / 1024, 383 / 1024, 193 / 512, 383 / 512 },
    bottomLeft  = {   1 / 1024, 191 / 1024,   1 / 512, 201 / 512 },
    bottomRight = {   1 / 1024, 191 / 1024, 203 / 512, 403 / 512 },
  },
  -- The horizontal edges are the full 256 of their sheet and stretch along the
  -- frame; the vertical pair is the full 256 the other way.
  edgeH = {
    sheet = { width = 256, height = 512 },
    top    = { 0, 1, 203 / 512, 393 / 512 },
    bottom = { 0, 1,   1 / 512, 201 / 512 },
  },
  edgeV = {
    sheet = { width = 512, height = 256 },
    left  = {   1 / 512, 191 / 512, 0, 1 },
    right = { 193 / 512, 383 / 512, 0, 1 },
  },
}

-- FlatPanelBackgroundTemplate: two 16x16 bottom corners on a 64x32 sheet, with
-- flat PANEL_BACKGROUND_COLOR everywhere else. Blizzard tints every piece with
-- that one colour, so the corners carry shape rather than art.
M.foreverWow.panelBackground = {
  sheet = { width = 64, height = 32 },
  cornerSize = 16,
  bottomLeft  = {  1 / 64, 17 / 64, 1 / 32, 17 / 32 },
  bottomRight = { 19 / 64, 35 / 64, 1 / 32, 17 / 32 },
  -- PANEL_BACKGROUND_COLOR. Sampled from a Forever Options screenshot the
  -- user supplied, 2026-09-21: rgb(28,39,48), flat across the category pane
  -- and the page. It is a dark blue-grey, not the near-black this addon's
  -- own windows use, and that tint is most of why the reference reads as
  -- Blizzard's settings panel rather than as a black box.
  -- The alpha is UnrealUI's, not Forever's: the window's main background is
  -- drawn at 95% (user requests, 2026-09-22: 70, then 80, then 95). It applies
  -- to THIS surround only -- the recessed plate the category list and the page
  -- sit on stays opaque, by the same request. Carried on the vertex colour
  -- rather than Texture:SetAlpha, which darkens instead of making translucent
  -- on this client (rendering.texture_setalpha_darkens_not_translucent).
  color = { 0.110, 0.153, 0.188, 0.95 },
}

-- Controls drawn inside a hosted client panel, from the Forever build's own
-- art (user request, 2026-09-21), replacing the Modern WoW settings atlas they
-- borrowed before.
--
-- Drawn at 0.58 of Forever's template sizes (user requests, 2026-09-21:
-- smaller dropdowns, sliders and checkboxes -- 0.77, then 25% less again). One factor for all of them, so the
-- controls keep Forever's proportions to each other; the atlas cells are
-- unchanged, only the drawn sizes below. The window itself is not scaled --
-- a reparented client control ignores an ancestor's scale
-- (widgets.reparented_native_widget_ignores_ancestor_scale) -- so each size
-- is set on the control directly. Every rectangle is the build's UiTextureAtlasMember read
-- with `query.py atlasmap <name> --exact` (texels, x0, x1, y0, y1); every size
-- and offset is the template's own (ForeverFrameXML-1.60.1.69913). Where
-- UnrealUI chooses a number instead, the comment says so.
M.foreverWow.control = {
  -- WowStyle2DropdownTemplate (Blizzard_Menu/MenuTemplates.xml): a 25-high
  -- button whose Background, common-dropdown-c-button, is anchored 7 outside
  -- it on every side. The member is a 78x78 square on a 512 sheet authored at
  -- twice the unit size, so it draws 39 tall -- exactly 25 + 2*7. It is
  -- stretched sideways only, as a three-slice: `cap` is the corner, the soft
  -- shadow ramp (14 texels) plus the bevelled rim (8), measured by alpha, and
  -- drawn at half size. The arrow shows only while hovered, BOTTOM y=-5
  -- (WowStyle2DropdownMixin:OnButtonStateChanged). States as
  -- WowStyle2DropdownMixin:GetBackgroundAtlas picks them.
  dropdown = {
    -- The dropdown bed, its steppers' beds and the open menu draw from
    -- modern-wow/buttons/setting-ui.tga (FileDataID 5412379) by user request
    -- (2026-09-22), not from forever-wow/settings/common-dropdown.tga (8069110).
    -- Both are the common-dropdown atlas at 512x512; every member drawn here
    -- sits at the same rectangle on both except the hover arrow, and the
    -- menu cell's rim and shadow measure the same (x 33..146, y 23..136).
    texture = M.modernWow.texture.settingUI,
    sheet = 512,
    -- 30% larger than the 0.58 set (user request, 2026-09-22): 0.75 of
    -- Forever's own sizes from here on, for every control below.
    controlHeight = 18.2,
    height = 29.25,
    overhang = 5.5,
    capLeft = 22,
    capRight = 22,
    normal   = { 431, 509,   1,  79 },
    hover    = { 401, 479,  85, 163 },
    pressed  = {  81, 159, 345, 423 },
    open     = {   1,  79, 425, 503 },
    disabled = { 321, 399,  85, 163 },
    -- common-dropdown-c-button-hover-arrow on 5412379 (8069110 has it at
    -- 183..207 x 139..149).
    arrow = { cell = { 321, 345, 165, 175 }, width = 9, height = 4, y = -4 },
    -- The value's inset from the bed's left cap: the component's 5 plus 5 of
    -- padding (user request, 2026-09-21). It is the text region's left edge;
    -- the region's right edge is the printed arrow in the right cap, which the
    -- component measures off the control.
    textInset = 10,
    -- Centred in that region, as Forever centres its own dropdown text (user
    -- request, 2026-09-22). The region is not quite symmetric -- its right
    -- inset is the arrow reservation, about 1.6 units less than textInset --
    -- so the value sits that much right of the control's true centre.
    textAlign = "CENTER",
    -- GameFontNormal, as the template's Text inherits.
    textColor = { 1.00, 0.82, 0.00, 1 },
    -- Metal2DropdownWithSteppersAndLabelTemplate (the settings dropdown):
    -- DecrementButton RIGHT of the dropdown's LEFT -5, IncrementButton LEFT of
    -- its RIGHT +4 (DropdownWithSteppersMixin:OnLoad), each a
    -- WowStyle2IconButtonTemplate 26x25 whose Background is the same
    -- common-dropdown-c-button at atlas size (39) and whose Icon is
    -- common-dropdown-icon-back / -next at atlas size (34x34 at twice the
    -- unit size, 17). States as WowStyle2IconButtonMixin:GetBackgroundAtlas
    -- picks them, the "-2" set. All at the controls' 0.58. The icons live
    -- only on 5412379, which ships as modern-wow/buttons/setting-ui.tga.
    stepper = {
      width = 19.5,
      height = 18.9,
      bedSize = 29.25,
      iconSize = 13,
      gapLeft = 3.9,
      gapRight = 3,
      normal   = { 431, 509,   1,  79 },
      hover    = {   1,  79, 345, 423 },
      pressed  = {  81, 159, 425, 503 },
      disabled = { 321, 399,  85, 163 },
      iconTexture = M.modernWow.texture.settingUI,
      iconSheet = 512,
      back         = { 393, 427, 183, 217 },
      backDisabled = { 429, 463, 183, 217 },
      next         = { 465, 499, 183, 217 },
      nextDisabled = { 393, 427, 237, 271 },
    },
    -- MenuStyle2Mixin:Generate, the open menu: common-dropdown-c-bg anchored
    -- TOPLEFT -17,12 and BOTTOMRIGHT 17,-22 of the menu, drawn at the art's
    -- own 0.5 unit per texel (the member is 180x180 at twice the unit size).
    -- Measured on the cell (2026-09-22): a 2-texel bronze rim at x 33..146,
    -- y 23..136, a 12-texel chamfer, and a shadow of 33 texels left and
    -- right, 23 on top and 43 below -- which at 0.5 are exactly Forever's
    -- anchor offsets, so the rim lands on the menu's edge. Nine-sliced with
    -- a cut per side (shadow + chamfer: 45 / 35 / 45 / 56) so the corners
    -- keep their chamfer and only the plain rim runs stretch. A first
    -- version cut 45 on every side and drew it at 13 units, which squeezed
    -- the corners and cut the deeper bottom shadow through the rim (reported
    -- in game with a screenshot beside Forever's).
    menu = {
      cell = { 1, 181, 1, 181 },
      cut = { left = 45, right = 45, top = 35, bottom = 56 },
      scale = 0.5,
      inset = { left = 16.5, top = 11.5, right = 16.5, bottom = 21.5 },
    },
  },
  -- SettingsCheckboxTemplate: 30x29, checkbox-minimal as the normal and
  -- pushed bed, checkmark-minimal / -disabled as the checked faces, all three
  -- from the one sheet 4614134 (user request, 2026-09-21: the box and its
  -- tick from checkmark-minimal.tga, rather than the box from 8086474).
  -- Blizzard gives the box no hover art of its own.
  checkbox = {
    texture = M.foreverWow.texture.checkmark,
    sheet = 64,
    -- Drawn at the dropdown's left arrow, not at a scale of Forever's 30x29
    -- (user request, 2026-09-22, with a screenshot: the box and that arrow
    -- read as one control in a column). Assigned under the table, from
    -- dropdown.stepper.bedSize, so the two cannot drift apart. The values
    -- here are the ones they replace, kept as the measurement.
    width = 15.6,
    height = 15,
    -- The tick at the box's own size, over the same area, as
    -- SettingsCheckboxTemplate draws both at atlas size (30x29 each): the
    -- tick's art runs a little past the box's rim within its cell, which is
    -- Forever's slight overshoot (user request, 2026-09-22, matched against a
    -- Forever screenshot; an earlier 0.7 fitted it inside the square). These
    -- follow the box, under the table.
    checkWidth = 15.6,
    checkHeight = 15,
    cell = { 1, 31, 1, 30 },
    checkTexture = M.foreverWow.texture.checkmark,
    checkSheet = 64,
    check = { 1, 31, 32, 61 },
    checkDisabled = { 33, 63, 1, 30 },
  },
  -- MinimalSliderWithSteppersTemplate / MinimalSliderTemplate
  -- (Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml), sheet 8086434,
  -- 32x128, authored at unit size. The group is 250 wide with the Slider
  -- inset 19 each side (so 212), Back 11x19 at the Slider's LEFT -4, Forward
  -- 9x18 at its RIGHT +4; the bar caps are 11x17, the middle tiles, and the
  -- thumb is 20x19.
  slider = {
    -- The silver copy of this sheet (user request, 2026-09-22); the cells
    -- below are the same on both.
    texture = M.modernWow.texture.minimalSliderSilver,
    sheetWidth = 32,
    sheetHeight = 128,
    width = 158.6,
    inset = 14.3,
    barHeight = 13,
    capWidth = 8.3,
    left   = { 14, 25, 41, 58 },
    middle = {  0,  1,  1, 18 },
    right  = {  1, 12, 62, 79 },
    thumb  = {  1, 21, 20, 39 },
    thumbWidth = 15,
    thumbHeight = 14.3,
    back    = { cell = { 1, 12, 41, 60 }, width = 8.3, height = 14.3 },
    forward = { cell = { 1, 10, 81, 99 }, width = 6.9, height = 13.65 },
    stepperGap = 3,
    -- Stepper when the slider reports no value step: a tenth of its range.
    -- UnrealUI's choice; Forever's steppers use the setting's own step.
    fallbackSteps = 10,
  },
  -- The rectangular buttons' labels: GameFontNormal, GameFontHighlight while
  -- hovered, as UIPanelButtonNoTooltipTemplate. Their face is the HD
  -- 128RedButton (M.modernWow.button128Red, user request 2026-09-22), not
  -- the template's old 128x32 UI-Panel-Button files; see gs.DressButton.
  button = {
    textColor = { 1.00, 0.82, 0.00, 1 },
    hoverTextColor = { 1.00, 1.00, 1.00, 1 },
    disabledTextColor = { 0.50, 0.50, 0.50, 1 },
  },
  -- UIPanelCloseButtonNoScripts placement. The Game Settings button uses the
  -- modern-wow red-button atlas through M.modernWow.redButtonCell.
  close = {
    size = 20.4,
    x = -2,
    y = 1,
  },
  -- UIMenuButtonStretchTemplate (Blizzard_SharedXML SharedUIPanelTemplates.xml
  -- 772), the face Forever's Key Bindings page gives every binding button
  -- through KeyBindingFrameBindingButtonTemplate (Blizzard_Keybindings.xml 4).
  -- User request, 2026-09-22: the bindings wear this rather than the settings
  -- dropdown bed they wore before.
  --
  -- A nine-slice of one 128x32 sheet, in the template's own texture
  -- coordinates: the four corners draw 12x6 unstretched, the top and bottom
  -- edges stretch sideways at 6 tall, the left and right edges stretch down at
  -- 12 wide, and the centre stretches both ways. Blizzard's coordinates cover
  -- x 0..80 and y 0..26 of the sheet; the rest is empty.
  binding = {
    up        = M.foreverWow.texture.silverUp,
    down      = M.foreverWow.texture.silverDown,
    highlight = M.foreverWow.texture.silverHighlight,
    -- KeyBindingFrameBindingButtonTemplate's SelectedHighlight, drawn ADD
    -- over the face while that binding is the one listening for a key. It is
    -- the template's own 160x20 at CENTER 0,-3.
    select    = M.foreverWow.texture.silverSelect,
    selectSize = { width = 160, height = 20, y = -3 },
    corner = { width = 12, height = 6 },
    edge = { width = 12, height = 14 },
    -- The template's own TexCoords, as fractions of the 128x32 sheet.
    topLeft      = { 0,        0.09375,  0,      0.1875 },
    topRight     = { 0.53125,  0.625,    0,      0.1875 },
    bottomLeft   = { 0,        0.09375,  0.625,  0.8125 },
    bottomRight  = { 0.53125,  0.625,    0.625,  0.8125 },
    topMiddle    = { 0.09375,  0.53125,  0,      0.1875 },
    bottomMiddle = { 0.09375,  0.53125,  0.625,  0.8125 },
    middleLeft   = { 0,        0.09375,  0.1875, 0.625 },
    middleRight  = { 0.53125,  0.625,    0.1875, 0.625 },
    middleMiddle = { 0.09375,  0.53125,  0.1875, 0.625 },
    -- UI-Silver-Button-Highlight is drawn whole, at the template's crop.
    highlightCoords = { 0, 1, 0.03, 0.7175 },
    -- KeyBindingFrameBindingTemplate: the row is 25 tall and its two buttons
    -- are 160x22, the first at LEFT of the row's CENTER -80 and the second
    -- against its right edge. UnrealUI keeps the client's own row and button
    -- anchors; only `height` is applied, so the face is drawn in Forever's
    -- proportion whatever width the client's button has.
    width = 160,
    height = 22,
    -- GameFontHighlightSmall / GameFontDisableSmall, the template's fonts.
    textColor = { 1.00, 1.00, 1.00, 1 },
    disabledTextColor = { 0.50, 0.50, 0.50, 1 },
  },
}

-- The checkbox is the dropdown's left arrow, at its size and on its line
-- (user request, 2026-09-22, with a screenshot). Width is the stepper's drawn
-- bed; height keeps the box art's own 30x29 aspect rather than being squared
-- off, which leaves it 1 unit shorter than the square bed -- both are centred
-- on the same line, so the column reads straight. The tick follows the box, as
-- SettingsCheckboxTemplate draws both at atlas size.
--
-- Then 9 units off that width, in three steps of 3 (user requests,
-- 2026-09-22), so the box sits inside the arrow rather than matching it.
M.foreverWow.control.checkbox.width = M.foreverWow.control.dropdown.stepper.bedSize - 9
M.foreverWow.control.checkbox.height = M.foreverWow.control.checkbox.width *
  (M.foreverWow.control.checkbox.cell[4] - M.foreverWow.control.checkbox.cell[3]) /
  (M.foreverWow.control.checkbox.cell[2] - M.foreverWow.control.checkbox.cell[1])
M.foreverWow.control.checkbox.checkWidth = M.foreverWow.control.checkbox.width
M.foreverWow.control.checkbox.checkHeight = M.foreverWow.control.checkbox.height
