"""Import the DragonflightUI-Reforged art the modern-wow theme draws.

Only the files a shipped modern-wow surface actually uses are copied, per
.claude/rules/dragonflight-ui.md. The folder is not mirrored.

Every file is re-encoded into the one TGA form this client is confirmed to
render, rather than copied byte-for-byte:

  * knowledge.json / textures.uncompressed_512_tga_atlas_corrupts is BROKEN
    with RUNTIME_FAILURE_CONFIRMED -- a 512x512 uncompressed type-2 TGA decodes
    correctly offline but draws as diagonal bands in game. DragonflightUI ships
    several textures in exactly that form. The recorded fix, and pfQuest's
    working atlas, is 32-bit RLE image type 10 with descriptor 0x08, so every
    imported file is written that way regardless of its source size.
  * knowledge.json / textures.addon_tga_paths_require_extensionless is
    SUPPORTED with USER_CONFIRMED_INGAME, so core/media.lua references these
    without the .tga suffix. Extensions live on disk only.
  * BLP is not represented in the compatibility evidence at all. Rather than
    ship a format with no record of working here, BLP sources are decoded and
    re-written as TGA, which is confirmed.

Dimensions are left alone. Power-of-two is not required on this client
(media/rest-icon is 36x39 and renders), and the DragonflightUI layouts were
authored against these exact sizes, so rescaling would move every anchor.

Run from the unrealUI addon folder:

    python -B tools/import_modern_wow_media.py
"""

import math
import os
import re
import struct
import sys

from PIL import Image

SOURCE_ADDON = "DragonflightUI-Reforged-1.3.4"
SOURCE_CREDIT = "DragonflightUI-Reforged 1.3.4 -- Guzruul, reforged by Stormhand"

DEST_SUBPATH = os.path.join("media", "Textures", "modern-wow")

# (source path under the DragonflightUI addon, destination name under
# media/Textures/modern-wow). Destination names are this addon's own
# vocabulary, not DragonflightUI's, because core/media.lua is what the modules
# read and a source filename like UI-TargetingFrameDF1 says nothing about which
# frame it draws.
IMPORTS = [
    # -- Unit frames -------------------------------------------------------
    ("media/tex/unitframes/UI-TargetingFrameDF.blp",
     "unitframes/player-frame"),
    ("media/tex/unitframes/UI-TargetingFrameDF-Background.blp",
     "unitframes/player-frame-bg"),
    ("media/tex/unitframes/UI-TargetingFrameDF1.blp",
     "unitframes/target-frame"),
    ("media/tex/unitframes/UI-TargetingFrameDF1-Background.blp",
     "unitframes/target-frame-bg"),
    ("media/tex/unitframes/UI-TargetingFrame-Rare.blp",
     "unitframes/frame-rare"),
    ("media/tex/unitframes/UI-TargetingFrame-Elite.blp",
     "unitframes/frame-elite"),
    ("media/tex/unitframes/UI-TargetingFrame-RareElite.blp",
     "unitframes/frame-rare-elite"),
    ("media/tex/unitframes/UI-TargetingFrame-Boss.blp",
     "unitframes/frame-boss"),
    ("media/tex/unitframes/pet.blp", "unitframes/party-frame"),
    ("media/tex/unitframes/UI-Player-Status.blp", "unitframes/player-status"),
    ("media/tex/unitframes/healthDF2.tga", "unitframes/health-fill"),
    ("media/tex/unitframes/"
     "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-Bar-Health-Status.tga",
     "unitframes/health-fill-minus"),
    ("media/tex/unitframes/"
     "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status.tga",
     "unitframes/power-fill-player"),
    ("media/tex/unitframes/"
     "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Status.blp",
     "unitframes/power-fill-target"),
    ("media/tex/unitframes/"
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health.tga",
     "unitframes/tot-health-fill"),
    ("media/tex/unitframes/"
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana.blp",
     "unitframes/tot-power-fill"),
    ("media/tex/unitframes/UI-PVP-Alliance.blp", "unitframes/pvp-alliance"),
    ("media/tex/unitframes/UI-PVP-Horde.blp", "unitframes/pvp-horde"),

    # -- Cast bar ----------------------------------------------------------
    ("media/tex/castbar/CastingBarFrame.blp", "castbar/frame"),
    ("media/tex/castbar/CastingBarBackground.blp", "castbar/background"),
    ("media/tex/castbar/CastingBarFrameDropShadow.blp", "castbar/shadow"),
    ("media/tex/castbar/CastingBarFrameFlash.tga", "castbar/flash"),
    ("media/tex/castbar/CastingBarSpark.blp", "castbar/spark"),
    # The fill itself is no longer DragonflightUI's CastingBarStandard3: the
    # four per-state fills are user-supplied (see MASKED below).

    # -- Shared window chrome ---------------------------------------------
    ("media/tex/ui/paperdoll_top_left.tga", "ui/panel-top-left"),
    ("media/tex/ui/paperdoll_top_right.tga", "ui/panel-top-right"),
    ("media/tex/ui/paperdoll_bot_left.tga", "ui/panel-bottom-left"),
    ("media/tex/ui/paperdoll_bot_right.tga", "ui/panel-bottom-right"),
    ("media/tex/ui/questlog_left.tga", "ui/questlog-left"),
    ("media/tex/ui/questlog_right.tga", "ui/questlog-right"),
    ("media/tex/ui/spell_bg.tga", "ui/spell-bg"),
    ("media/tex/ui/top_ui_header.tga", "ui/header"),
    ("media/tex/ui/top_ui_header_left.tga", "ui/header-left"),
    ("media/tex/ui/top_ui_header_right.tga", "ui/header-right"),

    # -- Action bars -------------------------------------------------------
    ("media/tex/actionbars/HDActionBar.tga", "actionbar/bar"),
    ("media/tex/actionbars/HDActionBarBtn.tga", "actionbar/button"),
    ("media/tex/actionbars/border.blp", "actionbar/button-border"),
    ("media/tex/actionbars/uiactionbariconframehighlight.tga",
     "actionbar/button-highlight"),
    ("media/tex/actionbars/indicator_.tga", "actionbar/indicator"),
    ("media/tex/actionbars/GryphonNew.tga", "actionbar/gryphon"),
    ("media/tex/actionbars/WyvernNew.tga", "actionbar/wyvern"),
    ("media/tex/actionbars/page_up_normal.tga", "actionbar/page-up-normal"),
    ("media/tex/actionbars/page_up_pushed.tga", "actionbar/page-up-pushed"),
    ("media/tex/actionbars/page_up_highlight.tga",
     "actionbar/page-up-highlight"),
    ("media/tex/actionbars/page_down_normal.tga", "actionbar/page-down-normal"),
    ("media/tex/actionbars/page_down_pushed.tga", "actionbar/page-down-pushed"),
    ("media/tex/actionbars/page_down_highlight.tga",
     "actionbar/page-down-highlight"),

    # -- Micro bar ---------------------------------------------------------
    # None from DragonflightUI: the micro bar draws only Retail's micro-menu
    # atlas (USER_SUPPLIED microbar/micromenu, user request 2026-09-28).

    # -- Bags --------------------------------------------------------------
    # bagslots2x is an atlas, not a single picture: six 61px cells on a
    # 512x128 canvas holding the empty-slot face, its gold rim, the hover
    # ring and the keyring's own two pieces. The cell rectangles live in
    # core/media.lua (M.modernWow.bagCell) rather than here.
    ("media/tex/bags/bagslots2x.blp", "bags/slot-frame"),
    ("media/tex/bags/bagbg2.tga", "bags/background"),
    ("media/tex/bags/bigbag.blp", "bags/slot"),
    ("media/tex/bags/bigbagHighlight.blp", "bags/slot-highlight"),
    ("media/tex/bags/bagslotCutout.blp", "bags/slot-cutout"),
    ("media/tex/bags/baghighlight2.blp", "bags/highlight"),
    ("media/tex/bags/expand.tga", "bags/expand"),
    ("media/tex/bags/KeyRing-Bag-Icon.blp", "bags/keyring"),

    # -- XP / reputation bar ----------------------------------------------
    ("media/tex/xprep/main.tga", "xpbar/fill"),
    ("media/tex/xprep/border_half.tga", "xpbar/border"),

    # -- Chat ---------------------------------------------------------------
    # Only the two scroll arrows. UnrealUI's two-arrow chat control is a scope
    # invariant (rules/unreal-ui.md); the source's extra menu and jump-to-end
    # buttons have no counterpart here and are not imported.
    ("media/tex/chat/chat_up.tga", "chat/arrow-up"),
    ("media/tex/chat/chat_down.tga", "chat/arrow-down"),

    # -- Minimap -----------------------------------------------------------
    ("media/tex/minimap/uiminimapborder.tga", "minimap/uiminimapborder"),
    ("media/tex/minimap/uiminimapshadow.tga", "minimap/uiminimapshadow"),
    ("media/tex/minimap/uiminimap_toppanel.tga", "minimap/uiminimap_toppanel"),
    ("media/tex/minimap/mail.tga", "minimap/mail"),
    ("media/tex/minimap/ZoomIn32.tga", "minimap/ZoomIn32"),
    ("media/tex/minimap/ZoomIn32-over.tga", "minimap/ZoomIn32-over"),
    ("media/tex/minimap/ZoomIn32-push.tga", "minimap/ZoomIn32-push"),
    ("media/tex/minimap/ZoomIn32-disabled.tga", "minimap/ZoomIn32-disabled"),
    ("media/tex/minimap/ZoomOut32.tga", "minimap/ZoomOut32"),
    ("media/tex/minimap/ZoomOut32-over.tga", "minimap/ZoomOut32-over"),
    ("media/tex/minimap/ZoomOut32-push.tga", "minimap/ZoomOut32-push"),
    ("media/tex/minimap/ZoomOut32-disabled.tga", "minimap/ZoomOut32-disabled"),
]


# Textures under media/Textures/modern-wow that did NOT come from
# DragonflightUI-Reforged. Most are supplied directly by the user; explicitly
# sourced Blizzard UI atlases record their origin in the individual note.
#
# These have no source path, so each is re-encoded IN PLACE by default: the
# destination file is its own input. That keeps the run idempotent, keeps them
# under the same RLE-TGA contract as everything else in this folder, and keeps
# their row in ATTRIBUTION.md instead of a regeneration silently dropping it.
#
# A fourth element names a different on-disk input beside the destination, for
# art supplied in a form that is not already the shipped TGA. That input is
# kept rather than deleted, because it -- not the generated TGA -- is what a
# later re-run reads.
#
# (destination name, the filename it was supplied as, note[, on-disk input])
USER_SUPPLIED = [
    ("minimap/uiminimap2x", "uiminimap2x.tga",
     "Blizzard Retail HD minimap atlas, FileDataID 4618666 / atlas 1995, "
     "512x1024. UnrealUI uses `UI-HUD-Minimap-Arrow-Guard` at L=441 R=486 "
     "T=363 B=400 and `UI-HUD-Minimap-Arrow-Player` at L=441 R=486 T=238 "
     "B=283 as the sources for its shared map arrows."),
    ("ui/class-portraits", "ui-classes-circles.png",
     "Blizzard UI-Classes-Circles class-icon atlas at 256x256: 64px "
     "cells, four per row, in CLASS_ICON_TCOORDS order (WARRIOR, MAGE, "
     "ROGUE, DRUID / HUNTER, SHAMAN, PRIEST, WARLOCK / PALADIN, "
     "DEATHKNIGHT, MONK, DEMONHUNTER / EVOKER). Replaces the "
     "DFRL-imported copy of the same atlas; the nine cells UnrealUI "
     "draws keep their authored positions, so `M.modernWow.classCell` "
     "is unchanged.",
     "ui-classes-circles.png"),
    ("ui/golden-square-border", "golden-square-border.png",
     "Gold square icon frame at 256x256 with a transparent opening at "
     "x 32-223, y 30-220. Drawn around each talent tree's header icon in the "
     "modern-wow Talent window; geometry is tokenised in core/media.lua.",
     "golden-square-border.png"),
    ("ui/borders/raidborder-bottomright", "raidborder-bottomright.png",
     "Blizzard's raid-frame border, bottom-right corner, 32x32. Same metal "
     "rim family as the ThinBorder pieces beside it, and the corner they do "
     "not ship: tal.BuildPanelBorder otherwise flips the bottom-left piece, "
     "which reads wrong on a control as small as the talent advisor's drawer "
     "arrow (user report, 2026-09-20).",
     "raidborder-bottomright.png"),
    ("buttons/setting-ui", "5412379.png",
     "Blizzard's dark settings-UI control atlas at 512x512, imported whole: "
     "octagonal panels, sliders, checkboxes, dropdown beds and a set of solid "
     "yellow and grey arrow glyphs. Cells are addressed by texture "
     "coordinates rather than cut out, so one file serves every control that "
     "borrows from it. The talent advisor's drawer arrow draws the yellow "
     "left and right glyphs (M.talentAdvisor.styles, toggle). The Modern WoW "
     "trainer's Filter dropdown draws its `common-dropdown-b-button` state "
     "cells and the `common-dropdown-bg` menu cell, as ForeverFrameXML's "
     "WowStyle1FilterDropdownTemplate and MenuStyle1Mixin do "
     "(M.modernWow.trainer.filter.bed).",
     "5412379.png"),
    ("ui/icon-alert-ants", "iconalertants.png",
     "Blizzard `Interface/SpellActivationOverlay/IconAlertAnts`, the marching "
     "ants that ring an alerted icon, at its own 256x256. It is a flipbook "
     "grid rather than one image: 48x48 cells, 5 per row, of which Blizzard "
     "plays the first 22 (Blizzard_CommentatorSpell.lua calls "
     "TextureUtil.AnimateTexCoords(self.Ants, 256, 256, 48, 48, 22, elapsed, "
     "0.01)). The last 16 pixels of each axis are outside the grid.",
     "iconalertants.png"),
    ("ui/combo-points", "combo-points.png",
     "Rogue and Cat Form combo-point atlas at 128x56: the left 57x56 "
     "circle is inactive and the right 57x56 circle is active. Drawn on "
     "the player or target frame opposite the configured aura position.",
     "combo-points.png"),
    ("ui/swing-bar", "swing-bar.png",
     "Blizzard Forever swing-timer atlas from build 1.60.1.69913, "
     "FileDataID 8344036, at 512x256. UnrealUI reproduces the exact FrameXML "
     "cells for the frame, background, main-hand, off-hand and ranged fills, "
     "title shadow and moving pip under the modern-wow theme.",
     "swing-bar.png"),
    ("microbar/micromenu", "4708813.png",
     "Blizzard Retail micro-menu atlas, FileDataID 4708813, at 1024x512, "
     "imported whole. Its UI-HUD-MicroMenu-* members are addressed by "
     "their UiTextureAtlasMember rectangles (ForeverFrameXML-1.60.1.69913 "
     "`query.py filedata 4708813`, the same Mainline Blizzard_MicroMenu "
     "RetailFrameXML 12.1 ships). It is the micro bar's only art under "
     "modern-wow and modern: every button is rebuilt as "
     "MainMenuBarMicroButton -- its icon's Up/Down/Mouseover/Disabled "
     "cells over the ButtonBG Up/Down plate, the Character button on the "
     "Achievements shield (M.modernWow.microMenu).",
     "4708813.png"),
    ("ui/minimal-scrollbar-proportional", "MinimalScrollbarProportional.PNG",
     "Blizzard MinimalScrollBar proportional atlas at 64x64: up/down arrow "
     "states plus the track and thumb caps. The Modern WoW Skills scrollbar "
     "uses its measured atlas cells without changing their pixels.",
     "MinimalScrollbarProportional.PNG"),
    ("ui/minimal-scrollbar-vertical", "MinimalScrollbarVertical.PNG",
     "Blizzard MinimalScrollBar vertical atlas at 64x1024: the stretchable "
     "track and normal, hover and pushed thumb bodies. The Modern WoW Skills "
     "scrollbar uses its measured atlas cells without changing their pixels.",
     "MinimalScrollbarVertical.PNG"),
    ("ui/questlog-left-large-v2", "questlog-left-large-v2.tga",
     "High-resolution left and centre Quest Log chrome for modern-wow."),
    ("ui/questlog-right-large", "questlog-right-large.tga",
     "High-resolution right Quest Log chrome for modern-wow."),
    ("unitframes/resting-flipbook", "UIUnitFrameRestingFlipbook.tga",
     "Resting `Z` animation, 6x7 grid of 60px cells on a 512x512 canvas. "
     "DragonflightUI has the script for this animation "
     "(modules/unit/player.lua Setup:RestingZZZ) but ships no such texture, "
     "so there was nothing to import."),
    ("buttons/red-button", "redbutton2x.blp",
     "Dragonflight octagonal button atlas: a 5x3 grid of 34x38 cells on a "
     "256x128 canvas -- minimize / close / maximize / minus glyphs across, "
     "normal / disabled / pushed down. The close column is what modern-wow "
     "draws on window close buttons; DragonflightUI ships only that one glyph, "
     "as the separate `close_normal` / `close_pushed` files, and without its "
     "disabled face.",
     "redbutton2x.blp"),
    ("buttons/128RedButton", "128RedButton.tga",
     "Modern rectangular red-button atlas at 512x2048. NPC actions use the "
     "UnrealQuest-measured three-slice normal and hover cells: fixed-aspect "
     "left/right bevels with only the middle stretched. Their geometry is "
     "tokenised in core/media.lua."),
    ("unitframes/player-status-large", "player-status-large.png",
     "Player combat / resting halo at 512x256, the same silhouette and "
     "orientation as `player-status.tga` at twice the resolution. Unlike that "
     "file its shape is in the alpha channel over near-white RGB. Supersedes "
     "`player-status.tga`, which is kept beside it but no longer referenced.",
     "player-status-large.png"),
    ("unitframes/unit-frame-portrait-background",
     "unit-frame-portrait-background.png",
     "Circular stone background shown beneath enabled 3D unit-frame "
     "portraits. Its transparent corners keep the background inside the "
     "Modern WoW portrait ring.",
     "unit-frame-portrait-background.png"),
    ("unitframes/target-reaction", "target-reaction.png",
     "Reaction-colour wash drawn beneath the Modern WoW target name. Its "
     "neutral greyscale is vertex-coloured red for hostile targets, yellow "
     "for neutral targets and green for allies.",
     "target-reaction.png"),
    ("ui/frame-tabs", "uiframetabs.png",
     "Dragonflight bottom window-tab atlas, 64x256: active middle (rows "
     "0-41) and inactive middle (44-79) span the full width; below them the "
     "active right (82-123) and left (126-167) caps, then the inactive right "
     "(170-205) and left (208-243) caps, each 37 texels wide. Drawn on the "
     "Character window tabs; cells are tokenised in core/media.lua.",
     "uiframetabs.png"),
    ("ui/character-create-diamond-metal", "CharacterCreateDiamondMetal8x.PNG",
     "Metal frame atlas at 8x, 512x2048: two plain bars, then four 238px "
     "corner pieces with a diamond stud (bottom-left, bottom-right, "
     "top-left, top-right). modern-wow draws the four corners around each "
     "Character gear slot, and the same atlas is the `M.modernWow.metalFrame` "
     "housing (game menu window and its caption plate, among others); cells "
     "are tokenised in core/media.lua.",
     "CharacterCreateDiamondMetal8x.PNG"),
    # Spellbook book art, supplied as the PNGs WoW-DragonflightUI ships beside
    # its BLPs (Textures/UI). modern-wow draws the Spellbook window from these;
    # measured geometry lives in core/media.lua M.modernWow.spellBook.
    ("ui/spellbook/spellbook-page-1", "Spellbook-Page-1.png",
     "Spellbook left cover, ribbon and page at 512x512; the art occupies rows "
     "0-493. Drawn inside the housing recess at its authored aspect.",
     "Spellbook-Page-1.png"),
    ("ui/spellbook/spellbook-page-2", "Spellbook-Page-2.png",
     "Spellbook right cover edge at 32x512; the art occupies columns 0-20 and "
     "rows 0-493, and joins `spellbook-page-1` at its right edge.",
     "Spellbook-Page-2.png"),
    ("ui/spellbook/spellbook-parts", "Spellbook-Parts.png",
     "Spellbook atlas at 256x256: the slot background and soft name shadow "
     "are drawn on each spell button; its former slot frame remains in the "
     "atlas but is superseded by 8116691. Cells are tokenised in "
     "core/media.lua.",
     "Spellbook-Parts.png"),
    ("ui/spellbook/8116691", "8116691.png",
     "User-supplied Blizzard spell-border atlas at 256x256. The Modern WoW "
     "Spellbook draws its ornate top-left cell around each spell icon; the "
     "cell and half-size geometry are tokenised in core/media.lua.",
     "8116691.png"),
    ("ui/spellbook/skillline-tab", "spellbook-skilllinetab.png",
     "Spellbook skill-line side tab frame at 64x64, drawn 64x64 at (-3, 11) "
     "from its 32px tab button.",
     "spellbook-skilllinetab.png"),
    ("ui/spellbook/skillline-tab-glow", "spellbook-skilllinetab-glow.png",
     "Gold selected / hover face of `skillline-tab`, same canvas and "
     "placement.",
     "spellbook-skilllinetab-glow.png"),
    # Spellbook Professions page, supplied as the PNGs WoW-DragonflightUI ships
    # in Textures/UI. Only the four files that page draws are shipped; measured
    # geometry lives in core/media.lua M.modernWow.spellBook.professions.
    ("ui/profession/professions-book-left", "Professions-Book-Left.png",
     "Professions page at 512x512: cover, ribbon and six profession rows; the "
     "art occupies rows 0-493. Swapped into the spell page's region when the "
     "Spellbook's Professions tab is selected.",
     "Professions-Book-Left.png"),
    ("ui/profession/professions-book-right", "Professions-Book-Right.png",
     "Right cover edge of `professions-book-left` at 32x512; the art occupies "
     "columns 0-20 and rows 0-493.",
     "Professions-Book-Right.png"),
    ("ui/profession/professions-book", "ProfessionsBook.png",
     "Professions atlas at 256x128: profession icon ring and skill bar end "
     "pieces and middle; cells are tokenised in core/media.lua.",
     "ProfessionsBook.png"),
    ("ui/profession/professions-progress-fill", "Professions-Progress-Fill.png",
     "Skill bar fill at 256x16; the fill occupies rows 0-11.",
     "Professions-Progress-Fill.png"),
    # Profession (TradeSkill / Craft) window, supplied as the PNGs
    # WoW-DragonflightUI (DF-main) ships in Textures/UI and draws from
    # Mixin/ProfessionFrame.mixin.lua. Only the backgrounds of professions that
    # open a crafting window on this client are shipped (no Herbalism, Fishing,
    # Skinning, Jewelcrafting or Inscription art); cells live in core/media.lua
    # M.modernWow.professions.
    ("ui/profession/professions", "professions.png",
     "DF-main professions atlas at 2048x1024: recipe-list panel, rank-bar "
     "track and rim, category header pieces, collapse and skill-up glyphs, "
     "recipe selection and hover bars, reagent slot frame. Cells are "
     "tokenised in core/media.lua.",
     "professions.png"),
    ("ui/profession/background-art", "professionbackgroundart.png",
     "DF-main generic recipe-detail background at 1024x1024 (art in 677x550); "
     "First Aid, Beast Training and unknown professions.",
     "professionbackgroundart.png"),
    ("ui/profession/background-art-alchemy", "professionbackgroundartalchemy.png",
     "DF-main Alchemy (and Poisons) recipe-detail background at 1024x1024.",
     "professionbackgroundartalchemy.png"),
    ("ui/profession/background-art-blacksmithing",
     "professionbackgroundartblacksmithing.png",
     "DF-main Blacksmithing recipe-detail background at 1024x1024.",
     "professionbackgroundartblacksmithing.png"),
    ("ui/profession/background-art-cooking", "professionbackgroundartcooking.png",
     "DF-main Cooking recipe-detail background at 1024x1024.",
     "professionbackgroundartcooking.png"),
    ("ui/profession/background-art-enchanting",
     "professionbackgroundartenchanting.png",
     "DF-main Enchanting recipe-detail background at 1024x1024.",
     "professionbackgroundartenchanting.png"),
    ("ui/profession/background-art-engineering",
     "professionbackgroundartengineering.png",
     "DF-main Engineering recipe-detail background at 1024x1024.",
     "professionbackgroundartengineering.png"),
    ("ui/profession/background-art-leatherworking",
     "professionbackgroundartleatherworking.png",
     "DF-main Leatherworking recipe-detail background at 1024x1024.",
     "professionbackgroundartleatherworking.png"),
    ("ui/profession/background-art-mining", "professionbackgroundartmining.png",
     "DF-main Mining (Smelting) recipe-detail background at 1024x1024.",
     "professionbackgroundartmining.png"),
    ("ui/profession/background-art-tailoring",
     "professionbackgroundarttailoring.png",
     "DF-main Tailoring recipe-detail background at 1024x1024.",
     "professionbackgroundarttailoring.png"),
    # Talent window chrome, supplied as the PNGs WoW-DragonflightUI (DF-main)
    # ships in Textures/UI. Drawn exactly as its ButtonFrameTemplateNoPortrait,
    # FrameBackgroundSolid and ChangeTalentsEra do; texcoords and sizes live in
    # core/media.lua M.modernWow.talents.
    ("ui/frame/metal-corners", "uiframemetal2x.png",
     "WoW-DragonflightUI (DF-main) metal frame corner atlas at 512x512: top "
     "corners 75x74, bottom corners 32x32.",
     "uiframemetal2x.png"),
    ("ui/frame/metal-horizontal", "uiframemetalhorizontal2x.png",
     "DF-main metal top and bottom edge strips at 64x256, tiled horizontally "
     "between the corners.",
     "uiframemetalhorizontal2x.png"),
    ("ui/frame/metal-vertical", "uiframemetalvertical2x.png",
     "DF-main metal left and right edge strips at 512x32, stretched "
     "vertically between the corners.",
     "uiframemetalvertical2x.png"),
    ("ui/frame/background-rock", "ui-background-rock.png",
     "DF-main dark rock window background at 1024x1024, stretched over the "
     "window body.",
     "ui-background-rock.png"),
    ("ui/frame/top-streak", "uiframehorizontal.png",
     "DF-main horizontal streak under the window title at 256x128; rows "
     "2-88 are drawn.",
     "uiframehorizontal.png"),
    ("ui/frame/portrait-ring", "UI-Frame-PortraitMetal-CornerTopLeft.png",
     "DF-main metal portrait ring at 256x256, drawn 84x84 around the "
     "window portrait.",
     "UI-Frame-PortraitMetal-CornerTopLeft.png"),
    ("ui/talents/talent-arrows", "UI-TalentArrows.png",
     "DF-main talent prerequisite arrow atlas at 64x64 (lit and unlit rows).",
     "UI-TalentArrows.png"),
    ("ui/talents/talent-branches", "UI-TalentBranches.png",
     "DF-main talent prerequisite branch atlas at 256x64 (lit and unlit rows).",
     "UI-TalentBranches.png"),
    ("ui/talents/talent-frame-parts", "TalentFrame-Parts.PNG",
     "Blizzard TalentFrame-Parts atlas referenced by DF-main's inherited "
     "TalentHeader templates. Sourced from Gethe/wow-ui-textures at "
     "`TALENTFRAME/TalentFrame-Parts.PNG` (SHA-256 "
     "A4E1A68CDD422E45FF21B32968FEE320F51259641AB702EA34410856789FC979). "
     "The Modern WoW talents surface draws its parchment header, gold header "
     "rim, primary icon border and gold point circle cells.",
     "TalentFrame-Parts.PNG"),
    ("ui/talents/role-icons", "lfgrole.png",
     "WoW-DragonflightUI (DF-main) `Textures/lfgrole.png`, its copy of the "
     "LFGRole strip: four 16x16 cells at 64x16 -- leader, damage, tank, "
     "healer. Drawn as the role icons on each Modern WoW talent tree header.",
     "lfgrole.png"),
    ("ui/questbackgroundparchment", "questbackgroundparchment.png",
     "WoW-DragonflightUI (DF-main) `Textures/UI/questbackgroundparchment.png`: "
     "five opaque 300x408 parchment pages on a 1024x1024 canvas. DF-main "
     "draws only the top-left tan page (texels 1-300 x 1-408), for both its "
     "QuestFrame and GossipFrame; the other four are unused material "
     "variants. The Modern WoW quest-giver window draws that same page; its "
     "cell is tokenised in core/media.lua M.modernWow.questDialog.",
     "questbackgroundparchment.png"),
    ("ui/questlog-dualpane-right", "ui-questlogdualpane-right.png",
      "WoW-DragonflightUI (DF-main) `Textures/UI/ui-questlogdualpane-right.png`, "
      "Blizzard's Classic dual-pane Quest Log right page at 256x512. Only its "
     "dark scrollbar channel (texels x 139-163, y 74-407, metal brackets at "
     "y 90 and 391) is drawn, by texture coordinates, beside the parchment of "
     "the Modern WoW quest-giver windows; the parchment half is unused. Cell "
      "tokenised in core/media.lua M.modernWow.questDialog.channel.",
      "ui-questlogdualpane-right.png"),
    ("ui/borders/ui-classtrainer-horizontalbar",
     "ui-classtrainer-horizontalbar.png",
     "Blizzard Class Trainer horizontal separator at 256x64. Its left cap "
     "and long run occupy rows 0-15; its right cap occupies x 68-74, rows "
     "17-34. Retained as an alternate separator texture.",
     "ui-classtrainer-horizontalbar.png"),
    ("ui/borders/ui-dialogbox-divider", "ui-dialogbox-divider.png",
     "Blizzard Dialog Box divider at 256x32, with its 193x16 authored bar in "
     "the top-left of the canvas. UnrealUI draws it as a three-slice bar in "
     "the Modern WoW Social and quest-giver windows; geometry is tokenised "
     "in core/media.lua M.modernWow.horizontalBar.",
     "ui-dialogbox-divider.png"),
    # ThinBorder is the authored modern inset used around the three talent
    # trees. Its 32px source canvases are drawn at 16 units; the opaque rim is
    # roughly 5 units at that scale, matching the panel's content inset.
    ("ui/borders/thin-border-top-left", "ThinBorder-TopLeft.PNG",
     "Top-left corner of the textured thin panel border, drawn at 16x16.",
     "ThinBorder-TopLeft.PNG"),
    ("ui/borders/thin-border-top", "ThinBorder-Top.PNG",
     "Stretchable top edge of the textured thin panel border, drawn 16 high.",
     "ThinBorder-Top.PNG"),
    ("ui/borders/thin-border-top-right", "ThinBorder-TopRight.PNG",
     "Top-right corner of the textured thin panel border, drawn at 16x16.",
     "ThinBorder-TopRight.PNG"),
    ("ui/borders/thin-border-left", "ThinBorder-Left.PNG",
     "Stretchable left edge of the textured thin panel border, drawn 16 wide.",
     "ThinBorder-Left.PNG"),
    ("ui/borders/thin-border-right", "ThinBorder-Right.PNG",
     "Stretchable right edge of the textured thin panel border, drawn 16 wide.",
     "ThinBorder-Right.PNG"),
    ("ui/borders/thin-border-bottom-left", "ThinBorder-BottomLeft.PNG",
     "Bottom-left corner of the textured thin panel border; mirrored for the "
     "bottom-right corner, drawn at 16x16.",
     "ThinBorder-BottomLeft.PNG"),
    ("ui/borders/thin-border-bottom", "ThinBorder-Bottom.PNG",
     "Stretchable bottom edge of the textured thin panel border, drawn 16 high.",
     "ThinBorder-Bottom.PNG"),
    # Blizzard achievement metal border, supplied as PNG. It rims the Modern
    # WoW profession window's item-stat panel; geometry is tokenised under
    # M.modernWow.professions.stats in core/media.lua.
    ("ui/borders/metal-border-joint", "UI-Achievement-MetalBorder-Joint.PNG",
     "Achievement metal border corner at 32x32: a bottom-right joint whose "
     "7-texel bars reach texel 25; mirrored for the other three corners.",
     "UI-Achievement-MetalBorder-Joint.PNG"),
    ("ui/borders/metal-border-left", "UI-Achievement-MetalBorder-Left.PNG",
     "Achievement metal border vertical edge at 16x512: a 9-texel bar at "
     "x 0-8 running to y 453; mirrored for the right edge.",
     "UI-Achievement-MetalBorder-Left.PNG"),
    ("ui/borders/metal-border-top", "UI-Achievement-MetalBorder-Top.PNG",
     "Achievement metal border horizontal edge at 512x16: a 9-texel bar at "
     "y 0-8 running to x 453; mirrored for the bottom edge.",
     "UI-Achievement-MetalBorder-Top.PNG"),
    # Edit Mode selection art, from the client's own Forever build
    # 1.60.1.69913 (Blizzard_EditMode/Shared/EditModeSystemTemplates.xml). The
    # nine-slice EditModeSystemSelectionLayout has two texture kits -- the cyan
    # `editmode-actionbar-highlight` and the gold `editmode-actionbar-selected`
    # -- and UnrealUI's mover anchors draw them instead of a hand-built glow.
    # This is the client's own art, not DragonflightUI chrome, so it is drawn
    # under every theme; cells live in core/media.lua M.modernWow.moveUI.
    ("ui/move-ui/editmodeui", "editmodeui.png",
     "Blizzard Forever Edit Mode nine-slice atlas at 32x256, FileDataID "
     "4554359 (atlas 1960). Top-down: highlight edge bottom (y 1-17) and top "
     "(19-35), selected edge bottom (37-53) and top (55-71), highlight corner "
     "(x 1-17, y 73-89), selected corner (91-107), then the new-layout plus "
     "and stepper glyphs UnrealUI does not draw. Each corner cell is authored "
     "top-left and mirrored for the other three.",
     "editmodeui.png"),
    ("ui/move-ui/editmodeuivertical", "editmodeuivertical.png",
     "Blizzard Forever Edit Mode vertical edge atlas at 128x16, FileDataID "
     "4554389 (atlas 1963): highlight left (x 1-17) and right (19-35), "
     "selected left (37-53) and right (55-71), each 16x16 and constant down "
     "its length.",
     "editmodeuivertical.png"),
    ("ui/move-ui/editmodeuihighlightbackground",
     "editmodeuihighlightbackground.png",
     "Blizzard Forever Edit Mode highlight centre fill at 16x16, FileDataID "
     "4554383 (atlas 1961): one flat colour, RGBA 150/224/255/128.",
     "editmodeuihighlightbackground.png"),
    ("ui/move-ui/editmodeuiselectedbackground",
     "editmodeuiselectedbackground.png",
     "Blizzard Forever Edit Mode selected centre fill at 16x16, FileDataID "
     "4554386 (atlas 1962): one flat colour, RGBA 255/245/105/128.",
     "editmodeuiselectedbackground.png"),
    ("buttons/minimal-slider-silver",
     "minimal-slider-silver.png (256x1024, SHA-256 "
     "8D3139AEDC79ACE5A7900E47BE71540D4AF60D910A36D8C36C6204F862E1458E)",
     "**Derived art, not a Blizzard file.** A silver recolour of Forever's "
     "bronze `MinimalSliderWithSteppers` sheet "
     "(`forever-wow/settings/minimal-slider.tga`, FileDataID 8086434), made "
     "by user request on 2026-09-22 because Blizzard's own grey sheet "
     "(FileDataID 4567914) is in no reachable source. Produced by the user "
     "with an image model from the 8x nearest-neighbour upscale of 8086434, "
     "then reduced here to 32x128 with nearest-neighbour and re-encoded as "
     "RLE TGA. Verified against 8086434: alpha mask identical at every one "
     "of the 4096 pixels, each atlas member's alpha bounds unchanged, mean "
     "saturation 0. This is a deliberate, user-approved exception to the "
     "no-restyle-or-recolour import rule. Drawn by the grouped settings "
     "window's sliders (`M.foreverWow.control.slider`) with 8086434's "
     "member rectangles."),
    ("ui/trainer/trainertextures",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/classtrainerframe/"
     "trainertextures.png (SHA-256 "
     "197EA24F721A503117CB15897F6F60641BDD043CA9BACBE24A8418F394AD211F)",
     "Blizzard Forever `Interface/ClassTrainerFrame/TrainerTextures`, build "
     "1.60.1.69913. RGBA PNG to 32-bit RLE bottom-up TGA, pixels verified "
     "identical. `Blizzard_TrainerUI.xml` (Mainline) addresses it by texture "
     "coordinates: the list parchment and the normal, highlight and selected "
     "service-row cells, all tokenised in core/media.lua M.modernWow.trainer. "
     "Drawn by the Modern WoW trainer window."),
    ("ui/moneyframe/ui-moneyframe-border",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/moneyframe/"
     "ui-moneyframe-border.png (SHA-256 "
     "678D686951C119D73F263BE78F4C830C43CA33AA3FB17C5F3BC1DFA742B79056)",
     "Blizzard Forever `Interface/MoneyFrame/UI-MoneyFrame-Border`, build "
     "1.60.1.69913. RGBA PNG to 32-bit RLE bottom-up TGA, pixels verified "
     "identical. The coin recess `ClassTrainerFrameMoneyBg` draws at 148x34 "
     "in the trainer footer; the Modern WoW trainer window draws it the same "
     "way (M.modernWow.trainer.money)."),
    ("ui/merchant/ui-merchant-labelslots",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/merchantframe/"
     "ui-merchant-labelslots.png (SHA-256 "
     "703DD7D6930C9E4978626CCCD5D9B3AA2ABC96D86C8F99FD8F76CE185E03781A)",
     "Blizzard Forever `Interface/MerchantFrame/UI-Merchant-LabelSlots`, "
     "build 1.60.1.69913. RGBA PNG to 32-bit RLE bottom-up TGA, pixels "
     "verified identical. ForeverFrameXML's Mainline `MerchantItemTemplate` "
     "places this dark name-and-price plate behind each 153x44 merchant row; "
     "the Modern WoW merchant keeps that structure while replacing its item-"
     "slot ring with the theme's metal slot corners."),
    ("ui/merchant/ui-buyback-icon",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/merchantframe/"
     "ui-buyback-icon.png (SHA-256 "
     "CC45372E5C63005D24940221D65666771BA1348DB884631A416B62BE76E3E1BD)",
     "Blizzard Forever `Interface/MerchantFrame/UI-BuyBack-Icon`, build "
     "1.60.1.69913. RGBA PNG to 32-bit RLE bottom-up TGA, pixels verified "
     "identical. ForeverFrameXML swaps the NPC portrait to this icon on the "
     "Buyback tab; the Modern WoW merchant does the same inside the theme's "
     "existing portrait ring."),
    ("ui/merchant/ui-merchant-repair-icons",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/unlisted/"
     "5222222.png (SHA-256 "
     "B56F19F657C06E8B425C7E0BB817CBF75C0BCC356BDC487F717063A5A1498D9A)",
     "Blizzard Forever FileDataID 5222222, build 1.60.1.69913. RGBA PNG to "
     "32-bit RLE bottom-up TGA, pixels verified identical. The Modern WoW "
     "merchant draws the exact `SpellIcon-256x256-SellJunk`, "
     "`SpellIcon-256x256-Repair`, "
     "`SpellIcon-256x256-RepairAll`, and "
     "`SpellIcon-256x256-RepairAllGuild` atlas members recorded by "
     "ForeverFrameXML. Its `UI-Merchant-BotFrame` member replaces UnrealUI's "
     "custom service-panel border and dividers beneath the sell-junk, repair "
     "and buyback controls."),
    ("unitframes/health-fill-tint",
     "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status.tga",
     "WoW-DragonflightUI (DF-main) "
     "`Textures/Unitframe/UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status.tga`, "
     "the neutral grey Status variant of the player health bar, opaque to its "
     "128x32 canvas. 24-bit uncompressed TGA to 32-bit RLE TGA, pixels "
     "unchanged. Drawn instead of the green `health-fill-full` when class "
     "health colours tint a Modern WoW unit frame, so the class colour is not "
     "multiplied into baked-in green.",
     "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status.tga"),
]

# Exact crops from the pinned Forever FrameXML art bundle. These are kept
# separate from USER_SUPPLIED so a full media re-import always re-derives the
# shipped TGA from the authoritative atlas sheet rather than re-encoding an
# older output in place.
FOREVER_ATLAS_CROPS = [
    ("unitframes/health-fill-full",
     "ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/unlisted/4642466.png",
     (1651, 415, 1899, 455),
     "ForeverFrameXML 4642466 / UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
     "Blizzard Forever build 1.60.1.69913 HD atlas member "
     "`UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health`: FileDataID 4642466, "
     "atlas 2074, pixels L=1651 R=1899 T=415 B=455 (248x40). The member is "
     "already coloured dark green to lime and carries its own bevel; "
     "PlayerFrame.xml draws it as the HealthBar BarTexture and sets "
     "lockColor=true, so UnrealUI draws it with a white vertex colour."),
]

# Retained authored TGA files that need attribution but must not be re-encoded
# by this importer. The plus/minus atlas intentionally stays uncompressed.
STATIC_USER_ART = [
    ("buttons/plus-minus-button", "4496242.png",
     "Blizzard's plus / minus tree button (FileDataID 4496242), converted "
     "from the PNG kept beside it: RGBA PNG to 32-bit uncompressed bottom-up "
     "TGA, pixels unchanged. Four 20x22 rounded buttons on a 64x64 sheet -- "
     "plus over minus, normal in the left column (columns 2-21) and pushed "
     "in the right (26-45); row runs 0-21 and 24-45. Drawn on the game-"
     "settings category list's collapse controls; cells are tokenised in "
     "core/media.lua."),
]


# Exact clockwise derivatives of shipped UI artwork. They are generated here
# because this client fragments Texture:SetRotation output on sliced textures.
ROTATED = [
    ("ui/borders/ui-dialogbox-divider-vertical",
     "ui/borders/ui-dialogbox-divider",
     "ui-dialogbox-divider.png",
     "Exact 90-degree clockwise derivative of ui-dialogbox-divider.tga for "
     "the Merchant footer's vertical column separator."),
]


# User-supplied greyscale art whose shape is carried by its RGB luminance
# instead of an alpha channel, because it was supplied as a 24-bit TGA. The
# plain USER_SUPPLIED path would `convert("RGBA")` that into a fully opaque
# rectangle, so the luminance becomes the alpha here and the RGB is flattened
# to the same neutral grey the other vertex-coloured washes use. The peak is
# normalised, because these sources are authored at different intensities and
# the M.modernWow token alphas are written against a full-strength shape.
#
# (destination name, the filename it was supplied as, peak alpha, note)
LUMA_ALPHA = [
    ("unitframes/target-reaction-type",
     "UI-HUD-UnitFrame-Target-PortraitOn-Type.tga",
     248,
     "Blizzard's Dragonflight target name-type strip at 128x16, supplied as a "
     "24-bit TGA: an upward gradient plateauing over rows 8-10, cut flat at "
     "row 11, with the last five rows and the right ~6% of the width empty. "
     "Alternative to `target-reaction.tga` (the same asset at 172x29); "
     "luminance moved into the alpha channel, peak normalised from 159 to "
     "248 and RGB flattened to 203 so both files answer the same "
     "M.modernWow.targetReaction alpha."),
]


# User-supplied cast-bar fills, one per cast state, drawn under a mask.
#
# The Dragonflight fills are square-cornered strips meant to be clipped by
# CastingBarMask. This client has no general texture mask: the only mask call
# in the compatibility evidence is Minimap:SetMaskTexture. So the mask is baked
# in here instead -- each fill's alpha is multiplied by the mask's alpha, which
# is exactly what a mask does at draw time. modules/modernwow.lua crops the
# fill with SetTexCoord in step with its width, so a baked shape stays glued to
# the bar geometry the same way a live mask would.
#
# (destination name, fill input, mask input, note) -- inputs sit beside the
# destination and are kept, because they are what a re-run reads.
MASKED = [
    # Not `castbar/fill`: that path held DragonflightUI's pale Standard3, and
    # the client keeps decoded textures across /reload
    # (knowledge.json / textures.resources_cached_across_ui_reload), so new
    # bytes at the old path kept drawing the old grey art.
    ("castbar/fill-cast", "CastingBarStandard2.png", "CastingBarMask.png",
     "Normal cast fill."),
    ("castbar/fill-channel", "CastingBarChannel.png", "CastingBarMask.png",
     "Channelled cast fill."),
    ("castbar/fill-craft", "CastingBarCrafting2.png", "CastingBarMask.png",
     "Trade-skill / craft cast fill."),
    ("castbar/fill-interrupted", "CastingBarInterrupted2.png",
     "CastingBarMask.png", "Failed / interrupted cast fill."),
    # DF-main's profession rank-bar fills (Textures/UI/professionsfx*.png),
    # which it clips with profbarmask through a MaskTexture. Same bake as the
    # cast fills; modules/professions.lua crops the fill with SetTexCoord in
    # step with its width so the baked rounded ends stay on the bar.
    ("ui/profession/fx-alchemy", "professionsfxalchemy.png", "profbarmask.png",
     "DF-main Alchemy (also First Aid and Poisons) profession rank-bar fill."),
    ("ui/profession/fx-blacksmithing", "professionsfxblacksmithing.png",
     "profbarmask.png", "DF-main Blacksmithing profession rank-bar fill."),
    ("ui/profession/fx-cooking", "professionsfxcooking.png", "profbarmask.png",
     "DF-main Cooking profession rank-bar fill."),
    ("ui/profession/fx-enchanting", "professionsfxenchanting.png",
     "profbarmask.png", "DF-main Enchanting profession rank-bar fill."),
    ("ui/profession/fx-engineering", "professionsfxengineering.png",
     "profbarmask.png", "DF-main Engineering profession rank-bar fill."),
    ("ui/profession/fx-leatherworking", "professionsfxleatherworking.png",
     "profbarmask.png", "DF-main Leatherworking profession rank-bar fill."),
    ("ui/profession/fx-mining", "professionsfxmining.png", "profbarmask.png",
     "DF-main Mining (Smelting) profession rank-bar fill."),
    ("ui/profession/fx-skinning", "professionsfxskinning.png", "profbarmask.png",
     "DF-main Beast Training rank-bar fill (DF-main draws its skinning fill)."),
    ("ui/profession/fx-tailoring", "professionsfxtailoring.png",
     "profbarmask.png", "DF-main Tailoring profession rank-bar fill."),
]


# Art derived from an already-imported DragonflightUI file, shaped by the cast
# bar mask so an effect stays inside the housing instead of spilling past it.
# Run after IMPORTS, whose output they read.
#
# (destination name, imported base, crop box or None, mask input, source path
# in DragonflightUI-Reforged, conversion note)
DERIVED = [
    # CastingBarFrameFlash is a 64-row glow ring drawn 5 units beyond the bar
    # on every side. Rows 16-47 are the part that lies over the bar itself:
    # the ring lands on the bar edge, under the rim, and the soft interior
    # glow covers the fill. Cropped, not resampled, so its pixels are the
    # source's own.
    ("castbar/flash-inner", "castbar/flash", (0, 16, 512, 48),
     "castbar/CastingBarMask.png",
     "media/tex/castbar/CastingBarFrameFlash.tga",
     "rows 16-47 cropped; alpha x CastingBarMask"),
]

# The mask itself as a texture: white where the bar is, clear outside it.
# modules/modernwow.lua draws the shared status-bar pulse with it so that
# effect keeps the bar's shape too.
MASK_TEXTURE = ("castbar/mask", "castbar/CastingBarMask.png")


# User-supplied 9-slice frame, packed into a power-of-two atlas. The supplied
# canvas is 1448x1086, which is not a power of two, and it is drawn at a small
# fraction of that size, so each slice is cut from it, halved, and packed. Cut
# lines were measured off the art's alpha shape: the corner brackets span
# x 0-146 / 1301-1447 and y 0-207 / 860-1085, the centre diamonds x 564-884
# (top) and 571-875 (bottom), and between them the bars are plain. The
# (x0, y0, x1, y1) boxes are source pixels; `at` is the halved cell's
# top-left in the atlas, with 2px transparent gutters. core/media.lua
# M.modernWow.frameBorder repeats the resulting cells.
NINE_SLICE = (
    "ui/frame-border", "frame-border.png", (512, 256),
    "Nine-slice metal frame with a centre diamond on its top and bottom "
    "edges. Supplied at 1448x1086 (not a power of two); cut into ten "
    "slices -- four corners, a top and bottom centre, and a plain sample of "
    "each bar -- halved and packed into a 512x256 atlas.",
    [
        ("topLeft",      (0,    0,   150, 210),  (2,   2)),
        ("top",          (300,  0,   332, 210),  (79,  2)),
        ("topCentre",    (556,  0,   892, 210),  (97,  2)),
        ("topRight",     (1298, 0,   1448, 210), (267, 2)),
        ("left",         (0,    500, 150, 532),  (344, 2)),
        ("right",        (1298, 500, 1448, 532), (421, 2)),
        ("bottomLeft",   (0,    856, 150, 1086), (2,   109)),
        ("bottom",       (300,  856, 332, 1086), (79,  109)),
        ("bottomCentre", (556,  856, 892, 1086), (97,  109)),
        ("bottomRight",  (1298, 856, 1448, 1086), (267, 109)),
    ],
)


# One region cut out of a larger user-supplied sheet, then re-encoded like
# everything else here. A flipbook grid is cropped to exactly columns x cell
# by rows x cell so its cell UVs are plain fractions of the shipped texture,
# with no sheet padding for a module to carry; a single cell is cropped to
# itself so the module needs no texture coordinates at all.
#
# (destination name, source file beside it, crop box, output size or None,
# note)
SHEET_CROPS = [
    ("ui/talents/icon-alert", "iconalert.png", (0, 68, 68, 136), None,
     "The middle, gold alert icon from the user-supplied three-icon strip. "
     "The modern-wow Talent Advisor keeps its authored thickness, tints it "
     "red and pulses it over talents with ranks outside the selected build. "
     "The bag-family search also rings each matching slot with it, untinted "
     "(user request, 2026-09-24)."),
    ("ui/spell-alert-loop", "spell-alert.png", (1277, 0, 1782, 606), None,
     "Blizzard `UI-HUD-ActionBar-Proc-Loop-Flipbook`, the looping gold border "
     "of a proc'd action button, cut from the 2048x2048 spell-alert sheet at "
     "its authored pixels: a 5x6 grid of 101px cells, 30 frames. The modern-"
     "wow Talent window's advisor runs it around the next talent to learn."),
    ("ui/spell-alert-start", "spell-alert.png", (0, 0, 1275, 1530), (640, 768),
     "Blizzard `UI-HUD-ActionBar-Proc-Start-Flipbook`, the one-shot burst that "
     "settles into the loop above, from the same sheet: a 5x6 grid of 255px "
     "cells, 30 frames. Halved to 128px cells (640x768) because it is drawn at "
     "roughly 120 units and no shipped texture here is larger; the grid, its "
     "cell fractions and the art are otherwise unchanged."),
]


# The Retail (12.1.0.69933) target frame, at the 2x resolution Retail draws.
# Geometry and atlas rectangles come from RetailFrameXML (`query.py atlasmap
# <name> --exact`, Blizzard_UnitFrame/Mainline/TargetFrame.xml and .lua); the
# pixels come from the two HD sheets kept beside the destination:
#
#   UIUnitFrame2x.BLP  interface/hud/uiunitframe2x, FileDataID 4642466
#                      (2048x1024 BLP2 raw BGRA, user-supplied from a War
#                      Within client, 2026-09-27)
#   4703662.png        interface/hud/uiunitframeboss2x (512x512)
#
# Every member below sits at its Retail 12.1 rectangle in that sheet (each
# crop's alpha extent fills its member). The Forever copy kept beside it,
# 4642466.png, has pixel-identical housings but packs its bar strip
# differently, so it is not a source here.
RETAIL_HOUSING_SHEET = "UIUnitFrame2x.BLP"
RETAIL_DRAGON_SHEET = "4703662.png"

# Bar and strip members of the same sheet. (destination, atlas name, L, T, R,
# B, canvas size or None for the member's own size, note)
RETAIL_SHEET_MEMBERS = [
    # Rows 4-15 of the 20-row member only (user request, 2026-09-27). The
    # member bakes a bevel into rows 0-3 and 16-19 (red 47-161 against a flat
    # 183-203). The player frame's rim is drawn over its power fill and hides
    # that fill's shaded rows, so only its flat band shows; the Retail target
    # draws its housing under the bars, so the whole bevel showed and the bar
    # read darker at top and bottom. The flat band is what the player shows.
    ("unitframes/power-fill-target-flat-2x",
     "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Status",
     927, 461, 1195, 473, None,
     "The neutral grey mana fill Retail tints by power type, cut to rows "
     "4-15 of the 20-row member (the member is T=457 B=477): its flat band "
     "without the baked top and bottom bevel, stretched over the 134x10 "
     "Retail ManaBar so the target's bar reads like the player's, whose rim "
     "hides the same bevel. Pixels kept are unchanged."),
    ("unitframes/target-reaction-2x",
     "UI-HUD-UnitFrame-Target-PortraitOn-Type",
     891, 415, 1161, 451, (512, 64),
     "The name strip Retail tints by reaction (ReputationColor), at the "
     "top-left of a 512x64 canvas. Alpha unchanged; its flat grey RGB "
     "(159-162) set to 203, the grey every vertex-coloured reaction wash "
     "here is authored at, so it answers the same M.modernWow.targetReaction "
     "alpha."),
    ("unitframes/target-health-fill-2x",
     "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
     1603, 315, 1855, 355, None,
     "Retail's green target health fill at its own 252x40 (the 126x20 "
     "HealthBar). Drawn white on the Retail target, as the player's "
     "Forever member is."),
    ("unitframes/target-health-fill-tint-2x",
     "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Status",
     1603, 357, 1855, 397, None,
     "The neutral grey variant of the member above, for class and custom "
     "health colours on the Retail target."),
    # The party block. Retail's own party frame (`uipartyframe.blp`, FileDataID
    # 4681512) exists at 1x only, and is a different design from the one
    # UnrealUI's party rows wear: those were DragonflightUI's `pet` border,
    # which is Retail's target-of-target housing. Its 2x member differs from
    # the old party-frame.tga by 14.5/255 per channel after a 2:1 reduction
    # (the Retail party member by 40), and every rim and the ring sit within
    # a unit of the old file, so it replaces it in the same 128x64 layout.
    ("unitframes/party-frame-2x",
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
     387, 315, 627, 413, (256, 128),
     "The target-of-target housing at 2x, at the top-left of a 256x128 "
     "canvas: the 2x version of the 128x64 `party-frame` the party rows and "
     "pet rows drew before, with transparent bar openings like it."),
    ("unitframes/party-health-fill-2x",
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
     1857, 315, 1997, 335, None,
     "The green target-of-target health fill at its own 140x20 (70x10 "
     "units), drawn on the party and party-pet rows."),
    ("unitframes/party-health-fill-tint-2x",
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health-Status",
     1857, 357, 1997, 377, None,
     "The neutral grey variant of the member above, for class and custom "
     "health colours on the party rows."),
    ("unitframes/party-power-fill-2x",
     "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana-Status",
     1603, 399, 1751, 413, None,
     "The grey target-of-target mana fill at its own 148x14 (74x7 units), "
     "tinted per power type on the party rows."),
]

# Housing members, each placed at the top-left of a 512x256 canvas so a module
# addresses the canvas in 2-pixel units (256x128) with no texture coordinates.
# (destination, atlas name, L, T, R, B)
RETAIL_HOUSINGS = [
    ("unitframes/target",
     "UI-HUD-UnitFrame-Target-PortraitOn", 1, 451, 385, 585),
    ("unitframes/target-rare",
     "UI-HUD-UnitFrame-Target-Rare-PortraitOn", 1, 587, 385, 721),
]

# The portrait ring of the housings above, in their own pixels: centre and the
# radius that holds the solid rim plus one pixel of antialiasing (measured by
# alpha > 128 along the centre row and column: x 251..373, y 3..122).
RETAIL_RING_CENTRE = (312.0, 62.5)
RETAIL_RING_RADIUS = 62.5

# The bar zone of the housings: pixel rows 45-110 (the top rim line of the
# health opening down to the bottom rim line of the mana opening), from the
# left rim line (x 3) to the portrait ring's solid metal, whose outer radius
# is 59. Inside it the housing is a flat black bed at alpha 102 with black
# rim shadows laid over it -- every non-rim pixel there is (0, 0, 0).
RETAIL_BAR_ROWS = (45, 110)
RETAIL_BAR_LEFT = 3
RETAIL_RING_SOLID = 59.0
RETAIL_BED_ALPHA = 102

# Dragon cells in 4703662 (Retail atlas 2131), for the derived silver-winged
# dragon. The winged cell is the plain gold body shifted 2 rows down plus wings
# (mean RGB difference 17/765 over the shared body at that offset).
RETAIL_DRAGON_GOLD_WINGED = (1, 1, 199, 163)
RETAIL_DRAGON_GOLD = (1, 165, 161, 323)
RETAIL_DRAGON_SILVER = (1, 325, 161, 483)
RETAIL_DRAGON_BODY_OFFSET = (0, 2)


def retail_split(image):
    """Split a housing into the part under the bars and the part over them.

    Retail draws the whole housing under its bars and trims the bar ends with
    masks; this client has no texture mask. The player frame's art instead
    lies OVER its bars, with open bar holes, so its rim lines and their inner
    shadows shade the fill (user request, 2026-09-27: the target must read
    the same). The Retail housing is therefore drawn twice:

    * under -- the housing with only the flat bed left in the bar zone;
    * over  -- the rim lines, the rim shadows with the bed taken out of them,
               and the portrait ring (with its drop shadow on the right).

    The bed and shadows are pure black, so the split is exact: a shadow of
    alpha `a` over the bed of alpha `b` is a black layer of alpha
    (a - b) / (1 - b) over that bed. Where a bar is empty, over-on-under
    recomposes the original pixel; where it is full, the rim and its shadow
    lie on the fill, as on the player frame.
    """
    image = image.convert("RGBA")
    under = image.copy()
    over = Image.new("RGBA", image.size, (0, 0, 0, 0))
    src, up, op = image.load(), under.load(), over.load()
    cx, cy = RETAIL_RING_CENTRE
    top, bottom = RETAIL_BAR_ROWS
    bed = RETAIL_BED_ALPHA
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = src[x, y]
            if not a:
                continue
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            in_bars = (top <= y <= bottom and x >= RETAIL_BAR_LEFT
                       and x < cx and d > RETAIL_RING_SOLID)
            if in_bars:
                if (r, g, b) == (0, 0, 0):
                    if a > bed:
                        shadow = (a - bed) * 255.0 / (255 - bed)
                        op[x, y] = (0, 0, 0, int(round(shadow)))
                        up[x, y] = (0, 0, 0, bed)
                else:
                    op[x, y] = (r, g, b, a)
            else:
                # The ring: moved to the over half rather than copied, so an
                # antialiased edge is not drawn twice.
                keep = 1.0 if x >= cx else max(
                    0.0, min(1.0, (RETAIL_RING_RADIUS + 1.0 - d) / 2.0))
                if keep:
                    op[x, y] = (r, g, b, int(round(a * keep)))
                    up[x, y] = (r, g, b, int(round(a * (1.0 - keep))))
    return under, over


# The target ring's difficulty tint (user request, 2026-09-29): the metal band
# of target-over-2x lies between radius 51 and 61 about RETAIL_RING_CENTRE
# (measured by mean colour per whole radius; inside and outside it the canvas
# is the black inner shadow and drop shadow). A metal pixel's warmth (red
# less blue) is at least RING_TINT_METAL_WARMTH; below that it is part shadow.
# Warmth rather than brightness, so the neutral grey bar rim lines that run
# into the band are left out.
RING_TINT_BAND = (49.0, 63.0)
RING_TINT_METAL_WARMTH = 80.0


def retail_ring_tint(over):
    """Derive the white ring mask the target's level colour is drawn with.

    Vertex coloured and drawn BLEND over the gold ring, it recolours the metal
    as the player's status halo recolours the housing, keeping the ring's own
    shading: each metal pixel's luminance, normalised so the brightest metal
    (99th percentile) is white, over its own alpha scaled by how much of it is
    metal. The black shadows are dropped rather than copied, so they are not
    drawn twice.
    """
    over = over.convert("RGBA")
    src = over.load()
    cx, cy = RETAIL_RING_CENTRE
    inner, outer = RING_TINT_BAND
    samples = []
    for y in range(over.height):
        for x in range(over.width):
            r, g, b, a = src[x, y]
            if not a:
                continue
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if inner <= d <= outer and r - b >= RING_TINT_METAL_WARMTH:
                samples.append(0.299 * r + 0.587 * g + 0.114 * b)
    samples.sort()
    peak = samples[int(len(samples) * 0.99)] if samples else 255.0

    tint = Image.new("RGBA", over.size, (0, 0, 0, 0))
    out = tint.load()
    for y in range(over.height):
        for x in range(over.width):
            r, g, b, a = src[x, y]
            if not a:
                continue
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d < inner or d > outer:
                continue
            metal = min(1.0, (r - b) / RING_TINT_METAL_WARMTH)
            if metal <= 0:
                continue
            luma = (0.299 * r + 0.587 * g + 0.114 * b) / metal
            grey = int(round(min(255.0, luma * 255.0 / peak)))
            out[x, y] = (grey, grey, grey, int(round(a * metal)))
    return tint


def import_target_ring_tint(dest_root):
    """Write unitframes/target-ring-tint-2x from the shipped target-over-2x."""
    source = os.path.join(dest_root, "unitframes", "target-over-2x.tga")
    if not os.path.isfile(source):
        raise IOError("target ring source missing: %s" % source)
    over, _ = open_source(source)
    tint = retail_ring_tint(over)
    over.close()
    dest_name = "unitframes/target-ring-tint-2x"
    dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
    width, height = write_rle_tga(tint, dst)
    row = {
        "dest": dest_name + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "unitframes/target-over-2x.tga",
        "note": "**Derived from `target-over-2x`** (user request, 2026-09-29): "
                "the portrait ring's metal only -- radius %g to %g about "
                "(%g, %g), a pixel's metal share its (red - blue) / %g -- as white "
                "luminance normalised to the brightest metal (99th "
                "percentile), alpha scaled by that share; both black shadows "
                "dropped. Vertex coloured with the target's level difficulty "
                "and drawn BLEND over the gold (or silver) ring, at the same "
                "canvas placement."
                % (RING_TINT_BAND[0], RING_TINT_BAND[1], RETAIL_RING_CENTRE[0],
                   RETAIL_RING_CENTRE[1], RING_TINT_METAL_WARMTH),
    }
    print("%-34s %-9s ring tint" % (dest_name, row["size"]))
    return row


def retail_silver_winged(sheet):
    """Derive the silver-winged dragon Retail does not ship.

    The body is Retail's own silver dragon, untouched. Only the wings are new:
    the gold-winged cell is recoloured through a gold-to-silver table learned
    from the two plain bodies, which share one silhouette pixel for pixel
    (each gold luminance maps to the mean silver colour found at the same
    pixels, smoothed over +-3 levels), and the silver body is then laid over it
    at the offset the gold body occupies in the winged cell.
    """
    winged = sheet.crop(RETAIL_DRAGON_GOLD_WINGED).convert("RGBA")
    gold = sheet.crop(RETAIL_DRAGON_GOLD).convert("RGBA")
    silver = sheet.crop(RETAIL_DRAGON_SILVER).convert("RGBA")

    gp, sp = gold.load(), silver.load()
    bins = [[0, 0, 0, 0] for _ in range(256)]
    for y in range(gold.height):
        for x in range(gold.width):
            g, s = gp[x, y], sp[x, y]
            if g[3] > 200 and s[3] > 200:
                lum = int(0.299 * g[0] + 0.587 * g[1] + 0.114 * g[2])
                acc = bins[lum]
                acc[0] += s[0]
                acc[1] += s[1]
                acc[2] += s[2]
                acc[3] += 1
    known = [i for i in range(256) if bins[i][3]]
    table = []
    for i in range(256):
        j = i if bins[i][3] else min(known, key=lambda k: abs(k - i))
        acc = [0, 0, 0, 0]
        for k in range(max(0, j - 3), min(255, j + 3) + 1):
            for c in range(4):
                acc[c] += bins[k][c]
        table.append(tuple(acc[c] // acc[3] for c in range(3)))

    wp = winged.load()
    for y in range(winged.height):
        for x in range(winged.width):
            r, g, b, a = wp[x, y]
            if a:
                lum = int(0.299 * r + 0.587 * g + 0.114 * b)
                wp[x, y] = table[lum] + (a,)
    winged.alpha_composite(silver, RETAIL_DRAGON_BODY_OFFSET)

    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.paste(winged, (0, 0))
    return canvas


RETAIL_TEXTURE_ROOT = os.environ.get(
    "UNREALUI_RETAIL_TEXTURES",
    r"D:\Development\unrealUI_data\retail-ui-textures-live")


def import_retail_bag_indicator(dest_root):
    """Import Retail Combined Bags' per-bag item-slot highlight."""
    source = os.path.join(RETAIL_TEXTURE_ROOT, "Store",
                          "store-item-highlight.PNG")
    if not os.path.isfile(source):
        raise IOError("Retail bag indicator source missing: %s" % source)

    dest_name = "bags/item-highlight"
    dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    image, _ = open_source(source)
    width, height = write_rle_tga(image.convert("RGBA"), dst)
    image.close()
    row = {
        "dest": dest_name + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "Store/store-item-highlight.PNG",
        "note": "Blizzard Retail `Interface\\Store\\store-item-highlight`, "
                "used by ContainerFrameItemButtonTemplate's `BagIndicator` "
                "and Combined Bags' `OnBagSlotEnter` to mark every item slot "
                "belonging to the hovered bag; pixels unchanged.",
    }
    print("%-34s %-9s Retail bag indicator" % (dest_name, row["size"]))
    return row


def import_retail_junk_coin(dest_root):
    """Import Retail's bags-junkcoin atlas member."""
    source = os.path.join(RETAIL_TEXTURE_ROOT, "ContainerFrame", "Bags.PNG")
    if not os.path.isfile(source):
        raise IOError("Retail bags sheet missing: %s" % source)

    dest_name = "bags/junk-coin"
    dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    image, _ = open_source(source)
    # The available PNG is a 256x256 physical packing of Bags rather than the
    # pinned atlas DB's 512x256 packing. Its same 20x18 coin cell is here.
    member = image.crop((221, 72, 241, 90)).convert("RGBA")
    image.close()
    width, height = write_rle_tga(member, dst)
    member.close()
    row = {
        "dest": dest_name + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "ContainerFrame/Bags.PNG",
        "note": "Blizzard Retail atlas member `bags-junkcoin` (logical "
                "FileDataID 969828). The supplied 256x256 `Bags.PNG` uses a "
                "different physical packing from the pinned 12.1.0.69933 "
                "512x256 atlas metadata; its same 20x18 member is at pixels "
                "L=221 R=241 T=72 B=90. Cropped there, pixels otherwise "
                "unchanged. Retail's "
                "ContainerFrameItemButtonTemplate shows it at TOPLEFT +1,0 "
                "for Poor-quality items while MerchantFrame is shown.",
    }
    print("%-34s %-9s Retail junk coin" % (dest_name, row["size"]))
    return row


def import_retail_target(addons, dest_root):
    """Write the Retail target-frame textures; returns their attribution rows."""
    folder = os.path.join(dest_root, "unitframes")
    rows = []

    def emit(dest_name, image, supplied, note):
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        width, height = write_rle_tga(image, dst)
        rows.append({"dest": dest_name + ".tga",
                     "size": "%dx%d" % (width, height),
                     "supplied": supplied, "note": note})
        print("%-34s %-9s Retail HD" % (dest_name, rows[-1]["size"]))

    sheet_path = os.path.join(folder, RETAIL_HOUSING_SHEET)
    dragon_path = os.path.join(folder, RETAIL_DRAGON_SHEET)
    for path in (sheet_path, dragon_path):
        if not os.path.isfile(path):
            raise IOError("Retail target source missing: %s" % path)

    sheet, _ = open_source(sheet_path)
    sheet = sheet.convert("RGBA")
    for dest_name, atlas, left, top, right, bottom in RETAIL_HOUSINGS:
        member = sheet.crop((left, top, right, bottom))
        canvas = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
        canvas.paste(member, (0, 0))
        where = ("FileDataID 4642466 (`interface/hud/uiunitframe2x`), atlas "
                 "2074, pixels L=%d R=%d T=%d B=%d (%dx%d)"
                 % (left, right, top, bottom, right - left, bottom - top))
        under, over = retail_split(canvas)
        emit(dest_name + "-under-2x", under, RETAIL_HOUSING_SHEET,
             "Blizzard Retail 12.1.0.69933 atlas member `%s`: %s, placed at "
             "the top-left of a 512x256 canvas. **Split with its `-over` twin "
             "(derived).** This half is drawn under the bars: the member "
             "unchanged, except that in the bar zone (pixel rows %d-%d, from "
             "x %d to the ring's solid metal at radius %g about (%g, %g)) "
             "each black rim shadow is cut back to the flat bed it lies on "
             "(alpha %d)."
             % (atlas, where, RETAIL_BAR_ROWS[0], RETAIL_BAR_ROWS[1],
                RETAIL_BAR_LEFT, RETAIL_RING_SOLID, RETAIL_RING_CENTRE[0],
                RETAIL_RING_CENTRE[1], RETAIL_BED_ALPHA))
        emit(dest_name + "-over-2x", over, RETAIL_HOUSING_SHEET,
             "**Derived from `%s`**, drawn over the bars so the target reads "
             "like the player frame, whose art lies over its fills: the rim "
             "lines of the bar zone unchanged, its black shadows with the bed "
             "taken out (alpha (a - %d) / (1 - %d/255), exact because bed and "
             "shadow are both black), and the portrait ring -- everything "
             "right of x %g, and left of it within radius %g, feathered over "
             "one pixel. Over-on-under recomposes the member wherever a bar "
             "is empty."
             % (atlas, RETAIL_BED_ALPHA, RETAIL_BED_ALPHA,
                RETAIL_RING_CENTRE[0], RETAIL_RING_RADIUS))

    for (dest_name, atlas, left, top, right, bottom, canvas_size,
         note) in RETAIL_SHEET_MEMBERS:
        member = sheet.crop((left, top, right, bottom))
        if canvas_size:
            canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
            canvas.paste(member, (0, 0))
            member = canvas
        if dest_name.endswith("-reaction-2x"):
            flat = Image.new("L", member.size, 203)
            member = Image.merge("RGBA",
                                 (flat, flat, flat, member.getchannel("A")))
        emit(dest_name, member, RETAIL_HOUSING_SHEET,
             "Blizzard Retail atlas member `%s`: FileDataID 4642466 "
             "(`interface/hud/uiunitframe2x`), pixels L=%d R=%d T=%d B=%d "
             "(%dx%d). %s"
             % (atlas, left, right, top, bottom, right - left, bottom - top,
                note))
    sheet.close()

    dragons, _ = open_source(dragon_path)
    dragons = dragons.convert("RGBA")
    emit("unitframes/target-dragons-2x", dragons, RETAIL_DRAGON_SHEET,
         "Blizzard Retail 12.1.0.69933 FileDataID 4703662 "
         "(`interface/hud/uiunitframeboss2x`, atlas 2131), the whole 512x512 "
         "sheet, pixels unchanged. The target frame draws its members by "
         "texture coordinates: `Boss-Gold-Winged` L=1 R=199 T=1 B=163, "
         "`Boss-Gold` L=1 R=161 T=165 B=323, `boss-rare-silver` L=1 R=161 "
         "T=325 B=483 (M.modernWow.targetDragon).")
    emit("unitframes/target-dragon-silver-winged-2x",
         retail_silver_winged(dragons), RETAIL_DRAGON_SHEET,
         "**Derived art, not a Blizzard file** (user request, 2026-09-27: "
         "rare elite wears a silver dragon with wings, which Retail does not "
         "ship). Body: Retail `boss-rare-silver` unchanged, laid at (0, 2). "
         "Wings: Retail `Boss-Gold-Winged` recoloured through a gold-to-silver "
         "luminance table learned from the `Boss-Gold` and `boss-rare-silver` "
         "bodies. 198x162 cell at the top-left of a 256x256 canvas, the "
         "winged cell's own size, so it takes the winged anchors.")
    dragons.close()
    return rows


# The Character window's stats side panel (user request, 2026-09-28): Retail's
# CharacterStatsPane art, from the two PaperDollInfo sheets of the Retail
# (The War Within) client's BlizzardInterfaceArt export, kept beside the output
# in ui/character/ the way UIUnitFrame2x.BLP is kept for the Retail target.
# Atlas geometry is the build's own UiTextureAtlasMember rectangle, read with
# ForeverFrameXML's `query.py atlasmap <name> --exact`: sheet 1400895
# (PaperDollInfoPart1, atlas 838, 1024x1024) and 1400896 (PaperDollInfoPart2,
# atlas 839, 1024x512). Every member is cut 1:1; nothing is resampled.
CHARACTER_STATS_FOLDER = "ui/character"
CHARACTER_STATS_SHEETS = {
    "PaperDollInfoPart1.BLP": ("1400895", "atlas 838"),
    "PaperDollInfoPart2.BLP": ("1400896", "atlas 839"),
}
# (destination, sheet, atlas member, L, T, R, B)
CHARACTER_STATS_MEMBERS = [
    ("ui/character/stat-category", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Title", 1, 715, 197, 755),
    ("ui/character/stat-line", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Line-Bounce", 1, 788, 158, 807),
    ("ui/character/class-bg-mage", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Mage-BG", 1, 1, 198, 356),
    ("ui/character/class-bg-paladin", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Paladin-BG", 200, 1, 397, 356),
    ("ui/character/class-bg-priest", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Priest-BG", 200, 358, 397, 713),
    ("ui/character/class-bg-rogue", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Rogue-BG", 399, 1, 596, 356),
    ("ui/character/class-bg-shaman", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Shaman-BG", 399, 358, 596, 713),
    ("ui/character/class-bg-warlock", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Warlock-BG", 598, 1, 795, 356),
    ("ui/character/class-bg-warrior", "PaperDollInfoPart1.BLP",
     "UI-Character-Info-Warrior-BG", 797, 1, 994, 356),
    ("ui/character/class-bg-druid", "PaperDollInfoPart2.BLP",
     "UI-Character-Info-Druid-BG", 399, 1, 596, 356),
    ("ui/character/class-bg-hunter", "PaperDollInfoPart2.BLP",
     "UI-Character-Info-Hunter-BG", 598, 1, 795, 356),
]


def import_character_stats(dest_root):
    """Cut the stats side panel's Retail members; returns attribution rows."""
    folder = os.path.join(dest_root, CHARACTER_STATS_FOLDER.replace("/", os.sep))
    sheets = {}
    for name in CHARACTER_STATS_SHEETS:
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            raise IOError("Character stats source missing: %s" % path)
        image, _ = open_source(path)
        sheets[name] = image.convert("RGBA")
        image.close()

    rows = []
    for dest_name, sheet, member, left, top, right, bottom in \
            CHARACTER_STATS_MEMBERS:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        crop = sheets[sheet].crop((left, top, right, bottom))
        width, height = write_rle_tga(crop, dst)
        crop.close()
        fdid, atlas = CHARACTER_STATS_SHEETS[sheet]
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": sheet,
            "note": "Blizzard Retail (The War Within) atlas member `%s`: "
                    "FileDataID %s (%s), pixels L=%d R=%d T=%d B=%d (%dx%d), "
                    "cut 1:1 from the BLP kept beside it. Drawn by the "
                    "Character window's stats side panel."
                    % (member, fdid, atlas, left, right, top, bottom,
                       right - left, bottom - top),
        })
        print("%-34s %-9s Retail character stats"
              % (dest_name, rows[-1]["size"]))
    for image in sheets.values():
        image.close()
    return rows


# The Character window's Retail housing (user request, 2026-09-28): the
# InsetFrameTemplate border whose two insets split the paper doll from the
# stats pane, and CharacterFrame's own `character-panel-background`, read
# straight from the Retail (The War Within) BlizzardInterfaceArt export the
# user named. The metal nine-slice, rock body and title streak the housing
# also draws are already here and pixel-identical to that export
# (ui/frame/metal-corners = FrameGeneral/UIFrameMetal2x, metal-horizontal =
# UIFrameMetalHorizontal2x, metal-vertical = UIFrameMetalVertical2x,
# background-rock = UI-Background-Rock, top-streak = UIFrameHorizontal, which
# also carries the inset's top and bottom tiles), so only these three are cut.
# Geometry is the build's own UiTextureAtlasMember rectangle, read with
# RetailFrameXML's `query.py atlasmap <name> --exact`. The two border sheets
# are copied whole (their members are addressed by texture coordinate in
# core/media.lua); the background is its one member, cut 1:1.
RETAIL_ART_ROOT = os.environ.get(
    "UNREALUI_RETAIL_ART",
    r"C:\Games\WoW-The-War-Within\The War Within\BlizzardInterfaceArt\Interface")
# (destination, source under RETAIL_ART_ROOT, FileDataID, atlas, crop, note)
CHARACTER_HOUSING_ART = [
    ("ui/frame/inset-corners", "Interface/FrameGeneral/UIFrame.BLP",
     "1723831", "atlas 948", None,
     "whole sheet; its members `UI-Frame-InnerTopLeft` (L=97 T=71), "
     "`UI-Frame-InnerTopRight` (L=105 T=71), `UI-Frame-InnerBotLeftCorner` "
     "(L=81 T=71) and `UI-Frame-InnerBotRight` (L=89 T=71), 6x6 each, are the "
     "InsetFrameTemplate corners"),
    ("ui/frame/inset-vertical", "FrameGeneral/UIFrameVertical.BLP",
     "1723832", "atlas 949", None,
     "whole sheet; its members `!UI-Frame-InnerLeftTile` (L=31 R=34) and "
     "`!UI-Frame-InnerRightTile` (L=36 R=39), 3x256, are the "
     "InsetFrameTemplate side tiles"),
    ("ui/character/panel-background", "COMMON/CurrencyWindow.BLP",
     "5882640", "atlas 2845", (1, 1, 451, 421),
     "atlas member `character-panel-background`, pixels L=1 R=451 T=1 B=421 "
     "(450x420), cut 1:1; CharacterFrame's Background over its Inset"),
]


def import_character_housing(dest_root):
    """Cut the Character housing's Retail inset art; returns attribution rows."""
    rows = []
    for dest_name, source, fdid, atlas, crop, note in CHARACTER_HOUSING_ART:
        src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
        if not os.path.isfile(src):
            raise IOError("Character housing source missing: %s" % src)
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        image = image.convert("RGBA")
        if crop:
            image = image.crop(crop)
        width, height = write_rle_tga(image, dst)
        image.close()
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": source.split("/")[-1],
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/%s`: FileDataID %s (%s), %s. Drawn by the "
                    "Character window's Retail housing."
                    % (source, fdid, atlas, note),
        })
        print("%-34s %-9s Retail character housing"
              % (dest_name, rows[-1]["size"]))
    return rows


# The paper doll's three sidebar tabs over the stats pane (user request,
# 2026-09-28): Retail's PaperDollSidebarTabs frame and PaperDollSidebarTabTemplate
# (Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml:393-539, RetailFrameXML
# 12.1.0.69933) draw every piece -- tab beds, hider, highlight, the Titles and
# Equipment Manager icons and the strip's two end decorations -- from one
# direct-path sheet by texture coordinate, so it is copied whole and
# pixel-unchanged (identical to RetailFrameXML's registered PNG export).
# FileDataID from the RetailFrameXML listfile.
CHARACTER_SIDEBAR_ART = [
    ("ui/character/sidebar-tabs",
     "PaperDollInfoFrame/PaperDollSidebarTabs.blp", "514608"),
]


def import_character_sidebar(dest_root):
    """Copy the paper-doll sidebar tab sheet; returns attribution rows."""
    rows = []
    for dest_name, source, fdid in CHARACTER_SIDEBAR_ART:
        src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
        if not os.path.isfile(src):
            raise IOError("Character sidebar source missing: %s" % src)
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        width, height = write_rle_tga(image.convert("RGBA"), dst)
        image.close()
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": source.split("/")[-1],
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/%s`: FileDataID %s, whole file, pixels "
                    "unchanged; PaperDollSidebarTabTemplate's TabBg (both "
                    "states), Hider and Highlight, PaperDollSidebarTabs' "
                    "DecorLeft/DecorRight and the Titles / Equipment Manager "
                    "icons, addressed by the XML's texture coordinates. Drawn "
                    "by the Character window's sidebar tabs."
                    % (source, fdid),
        })
        print("%-34s %-9s Retail character sidebar"
              % (dest_name, rows[-1]["size"]))
    return rows


# The Character window's Equipment Manager (user request, 2026-09-28):
# Retail's PaperDollEquipmentManagerPane / GearSetButtonTemplate and the
# EquipmentFlyout beside each gear slot (Blizzard_UIPanels_Game/Mainline/
# PaperDollFrame.xml and Blizzard_FrameXML/EquipmentFlyout.xml, Mainline
# source) draw these direct-path files by texture coordinate, so each is
# copied whole and pixel-unchanged. FileDataIDs are not recorded for them.
EQUIPMENT_MANAGER_ART = [
    ("ui/character/gearmanager-flyout-button",
     "PaperDollInfoFrame/UI-GearManager-FlyoutButton.blp",
     "EquipmentFlyoutPopoutButtonTemplate's normal and highlight"),
    # Retail turns the same art sideways for a slot's right-hand arrow with an
    # 8-value (rotated) SetTexCoord, which this client ignores, drawing the
    # first four values as a plain rectangle (in game, 2026-09-28). The copy
    # is turned 90 degrees clockwise instead, so a 4-value crop draws it.
    ("ui/character/gearmanager-flyout-button-side",
     "PaperDollInfoFrame/UI-GearManager-FlyoutButton.blp",
     "EquipmentFlyoutPopoutButtonTemplate's normal and highlight, turned 90 "
     "degrees clockwise (Retail's rotated texture coordinates, which this "
     "client does not draw)", "rotate"),
    ("ui/character/gearmanager-flyout",
     "PaperDollInfoFrame/UI-GEARMANAGER-FLYOUT.BLP",
     "EquipmentFlyoutTexture, the flyout's background"),
    ("ui/character/gearmanager-leave-opaque",
     "PaperDollInfoFrame/UI-GearManager-LeaveItem-Opaque.blp",
     "the flyout's ignore-slot button"),
    ("ui/character/gearmanager-leave-transparent",
     "PaperDollInfoFrame/UI-GearManager-LeaveItem-Transparent.blp",
     "PaperDollItemSlotButtonTemplate's ignoreTexture"),
    ("ui/character/gearmanager-into-bag",
     "PaperDollInfoFrame/UI-GearManager-ItemIntoBag.blp",
     "the flyout's place-in-bags button"),
    ("ui/character/gearmanager-undo",
     "PaperDollInfoFrame/UI-GearManager-Undo.blp",
     "the flyout's unignore-slot button"),
    ("ui/character/gearmanager-highlight",
     "PaperDollInfoFrame/UI-GearManager-ItemButton-Highlight.blp",
     "EquipmentFlyoutFrame's Highlight around the open slot"),
    ("ui/character/character-plus",
     "PaperDollInfoFrame/Character-Plus.blp",
     "the New Set row's icon"),
    ("ui/character/grouploot-pass",
     "Buttons/UI-GroupLoot-Pass-Up.blp",
     "GearSetButtonTemplate's DeleteButton"),
    ("ui/character/gear-grey",
     "WorldMap/Gear_64Grey.blp",
     "GearSetButtonTemplate's EditButton"),
]


def import_equipment_manager(dest_root):
    """Copy the Equipment Manager's Retail art; returns attribution rows."""
    rows = []
    for entry in EQUIPMENT_MANAGER_ART:
        dest_name, source, use = entry[0], entry[1], entry[2]
        rotate = len(entry) > 3 and entry[3] == "rotate"
        src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
        if not os.path.isfile(src):
            raise IOError("Equipment Manager source missing: %s" % src)
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        image = image.convert("RGBA")
        if rotate:
            image = image.transpose(Image.ROTATE_270)
        width, height = write_rle_tga(image, dst)
        image.close()
        form = ("whole file turned 90 degrees clockwise, pixels otherwise "
                "unchanged" if rotate else "whole file, pixels unchanged")
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": source.split("/")[-1],
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/%s`, %s; %s. Drawn by the Character window's "
                    "Equipment Manager." % (source, form, use),
        })
        print("%-34s %-9s Retail equipment manager"
              % (dest_name, rows[-1]["size"]))
    return rows


# The Character window's Reputation page (user request, 2026-09-29): Retail's
# ReputationFrame (Blizzard_UIPanels_Game/Mainline/ReputationFrame.xml/.lua,
# RetailFrameXML 12.1.0.69933) -- ReputationHeaderTemplate's Options_ListExpand
# bar, ReputationEntryTemplate's line highlight and ReputationBarTemplate, and
# ReputationDetailFrame's parchment and DialogBorderTemplate (NineSliceLayouts
# `Dialog`: UI-Frame-DiamondMetal around UI-DialogBox-Background). Atlas
# geometry is RetailFrameXML's `query.py atlasmap <name> --exact`; each atlas
# sheet's physical file was matched by its size and member layout. Whole files
# pixel-unchanged, except the line highlight, whose two atlas members are cut
# 1:1 from the 2048x2048 CharacterCreate sheet into a 16x64 canvas (pixels
# L=2029..2045 T=1..41 at its top-left). The Dialog Box divider is not
# re-imported: ui/borders/ui-dialogbox-divider.tga matches Retail's within
# compression noise (max channel difference 5).
# (destination, source under RETAIL_ART_ROOT, crop or None, note)
CHARACTER_REPUTATION_ART = [
    ("ui/character/reputation-list-expand",
     "Options/OptionsExpandListButton.BLP", None,
     "FileDataID 4571485 (atlas 1974): `Options_ListExpand_Left`, "
     "`_Options_ListExpand_Middle`, `Options_ListExpand_Right` and "
     "`Options_ListExpand_Right_Expanded`, ReputationHeaderTemplate's bar"),
    ("ui/character/reputation-line-highlight",
     "GLUES/CHARACTERCREATE/CharacterCreate.BLP", (2029, 1, 2045, 41),
     "FileDataID 1253496 (atlas 708): "
     "`charactercreate-customize-dropdown-linemouseover-side` (L=2029 R=2041) "
     "and `-middle` (L=2043 R=2044), T=1 B=41, cut 1:1 into a 16x64 canvas; "
     "ReputationEntryTemplate's BackgroundHighlight"),
    ("ui/character/reputation-bar-fill",
     "PaperDollInfoFrame/UI-Character-Skills-Bar.blp", None,
     "ReputationBarTemplate's BarTexture"),
    ("ui/character/reputation-detail-background",
     "PaperDollInfoFrame/UI-Character-Reputation-DetailBackground.blp", None,
     "ReputationDetailFrame's parchment"),
    ("ui/frame/dialog-diamond-metal",
     "FrameGeneral/UIFrameDiamondMetal2x.BLP", None,
     "FileDataID 3056750 (atlas 1502): `UI-Frame-DiamondMetal-Corner*` and "
     "`_UI-Frame-DiamondMetal-EdgeTop/Bottom`, NineSliceLayouts.Dialog"),
    ("ui/frame/dialog-diamond-metal-vertical",
     "FrameGeneral/UIFrameDiamondMetalVertical2x.BLP", None,
     "FileDataID 3056755 (atlas 1503): `!UI-Frame-DiamondMetal-EdgeLeft/"
     "Right`, NineSliceLayouts.Dialog"),
    ("ui/frame/dialog-background",
     "DialogFrame/UI-DialogBox-Background.blp", None,
     "DialogBorderTemplate's Bg"),
]
CHARACTER_REPUTATION_CANVAS = {"ui/character/reputation-line-highlight": (16, 64)}

# ReputationBarTemplate's frame, assembled (user request, 2026-09-29): the
# LeftTexture crop (texture coordinates 0.765625-1 x 0.046875-0.28125, pixels
# L=196 R=256 T=3 B=18) and the RightTexture crop (0-0.15234375 x
# 0.390625-0.625, pixels L=0 R=39 T=25 B=40) side by side, 99x15, at (1, 1) of
# a transparent 128x32 canvas. Two edits, both to texels outside the frame's
# drawn outline: the near-black corner texels past its rounded corners are
# cleared (flood fill from the canvas edge through texels darker than the
# outline, luminance < 30, which the closed outline stops), and the 1-texel
# transparent gutter replaces the neighbouring atlas rows the crop's filtering
# smeared into a dark fringe round the rim. The outline and the inside are
# unchanged.
REPUTATION_BAR_FRAME = "ui/character/reputation-bar-frame"
REPUTATION_BAR_FRAME_PIECES = [((196, 3, 256, 18), (1, 1)),
                               ((0, 25, 39, 40), (61, 1))]
REPUTATION_BAR_FRAME_CANVAS = (128, 32)
REPUTATION_BAR_FRAME_OUTLINE = 30


def build_reputation_bar_frame(dest_root):
    """Assemble ReputationBarTemplate's frame; returns its attribution row."""
    source = "PaperDollInfoFrame/UI-CHARACTER-REPUTATIONBAR.BLP"
    src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
    sheet, _ = open_source(src)
    sheet = sheet.convert("RGBA")
    canvas = Image.new("RGBA", REPUTATION_BAR_FRAME_CANVAS, (0, 0, 0, 0))
    for crop, at in REPUTATION_BAR_FRAME_PIECES:
        canvas.paste(sheet.crop(crop), at)
    sheet.close()

    width, height = canvas.size
    pixels = canvas.load()

    def outside(x, y):
        r, g, b, a = pixels[x, y]
        return a == 0 or (r + g + b) // 3 < REPUTATION_BAR_FRAME_OUTLINE

    seen = set()
    stack = [(x, y) for x in range(width) for y in (0, height - 1)]
    stack += [(x, y) for y in range(height) for x in (0, width - 1)]
    cleared = 0
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < width and 0 <= y < height):
            continue
        seen.add((x, y))
        if not outside(x, y):
            continue
        if pixels[x, y][3] != 0:
            pixels[x, y] = (0, 0, 0, 0)
            cleared += 1
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    dst = os.path.join(dest_root, REPUTATION_BAR_FRAME.replace("/", os.sep) + ".tga")
    size = write_rle_tga(canvas, dst)
    canvas.close()
    print("%-34s %-9s Retail reputation (%d corner texels cleared)"
          % (REPUTATION_BAR_FRAME, "%dx%d" % size, cleared))
    return {
        "dest": REPUTATION_BAR_FRAME + ".tga",
        "size": "%dx%d" % size,
        "supplied": source.split("/")[-1],
        "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                "`Interface/%s`: ReputationBarTemplate's LeftTexture (pixels "
                "L=196 R=256 T=3 B=18) and RightTexture (L=0 R=39 T=25 B=40) "
                "assembled side by side, 99x15 at (1, 1) of a transparent "
                "128x32 canvas; the %d near-black texels outside the frame's "
                "rounded outline cleared (flood fill from the canvas edge, "
                "luminance < %d), so neither they nor the neighbouring atlas "
                "rows show round the rim (user request, 2026-09-29). Outline "
                "and inside unchanged. Drawn by the Character window's "
                "Reputation page." % (source, cleared,
                                      REPUTATION_BAR_FRAME_OUTLINE),
    }


def import_character_reputation(dest_root):
    """Copy the Reputation page's Retail art; returns attribution rows."""
    rows = []
    for dest_name, source, crop, note in CHARACTER_REPUTATION_ART:
        src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
        if not os.path.isfile(src):
            raise IOError("Reputation source missing: %s" % src)
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        image = image.convert("RGBA")
        if crop:
            cut = image.crop(crop)
            image.close()
            image = Image.new("RGBA", CHARACTER_REPUTATION_CANVAS[dest_name],
                              (0, 0, 0, 0))
            image.paste(cut, (0, 0))
        width, height = write_rle_tga(image, dst)
        image.close()
        form = "cut as noted" if crop else "whole file, pixels unchanged"
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": source.split("/")[-1],
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/%s`, %s; %s. Drawn by the Character window's "
                    "Reputation page." % (source, form, note),
        })
        print("%-34s %-9s Retail reputation" % (dest_name, rows[-1]["size"]))
    rows.append(build_reputation_bar_frame(dest_root))
    return rows


# The Character window's 3D preview (user request, 2026-09-28): Retail's
# CharacterModelScene art (Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml
# and CharacterFrame.xml, RetailFrameXML 12.1.0.69933) -- the Char-Inner /
# Char-Corner border (the three Char-Paperdoll sheets, copied whole; their
# members are addressed by the XML's own texture coordinates in
# core/media.lua) and the race background SetPaperDollBackground draws, the
# four DressUpBackground-<race>1..4 pieces of each race this client can play
# (the eight Vanilla races). Whole files; the border is pixel-unchanged and
# the race art is toned (below). FileDataIDs from the RetailFrameXML listfile.
CHARACTER_SCENE_ART = [
    ("ui/character/paperdoll-parts", "CHARACTERFRAME/Char-Paperdoll-Parts.blp",
     "410248", "Char-Corner-UpperLeft/UpperRight/LowerLeft/LowerRight"),
    ("ui/character/paperdoll-horizontal",
     "CHARACTERFRAME/Char-Paperdoll-Horizontal.blp", "410247",
     "Char-Inner-Top and Char-Inner-Bottom"),
    ("ui/character/paperdoll-vertical",
     "CHARACTERFRAME/Char-Paperdoll-Vertical.blp", "410249",
     "Char-Inner-Left and Char-Inner-Right"),
]
# (race file token, destination token, first FileDataID of its four pieces)
CHARACTER_SCENE_RACES = [
    ("Human", "human", 131093), ("Orc", "orc", 131101),
    ("Dwarf", "dwarf", 131089), ("NightElf", "nightelf", 131097),
    ("Scourge", "scourge", 131105), ("Tauren", "tauren", 131109),
    ("Gnome", "gnome", 455998), ("Troll", "troll", 456006),
]
# Race backgrounds are toned so every race reads as bright as Human on screen
# (user request, 2026-09-28: Human in game is right, Scourge near-black, Tauren
# a little dark). Retail darkens each race by its own BackgroundOverlay alpha,
# mirrored here from M.modernWow.characterScene.overlayAlpha -- keep the two
# in step. Human is the reference and stays pixel-unchanged; every other race
# gets one smooth gamma curve over all four pieces, chosen so the median
# luminance of its visible art, after its overlay, equals Human's.
CHARACTER_SCENE_OVERLAY = {"nightelf": 0.6, "scourge": 0.3, "troll": 0.6,
                           "orc": 0.6}
CHARACTER_SCENE_OVERLAY_DEFAULT = 0.7
# M.modernWow.characterScene.overlayScale.
CHARACTER_SCENE_OVERLAY_SCALE = 0.8
CHARACTER_SCENE_REFERENCE = "human"
# The XML's texture coordinates (left, top, right) per piece: the part drawn.
CHARACTER_SCENE_CROP = [(0.171875, 0.0392156862745098, 1),
                        (0, 0.0392156862745098, 0.296875),
                        (0.171875, 0, 1), (0, 0, 0.296875)]


# The four pieces are stitched into ONE power-of-two texture per race (user
# report, 2026-09-29: drawn as four pieces the seams showed a dark line, and
# overlapping them distorted the art). The drawn 231x374 area of the pieces
# sits at the canvas's top-left; core/media.lua's `background` names the
# canvas and the crop.
CHARACTER_SCENE_CANVAS = (256, 512)


def character_scene_source(race, piece):
    return os.path.join(RETAIL_ART_ROOT, "DRESSUPFRAME",
                        "DressUpBackground-%s%d.blp" % (race, piece + 1))


def character_scene_median(race):
    """Median luminance of the drawn, mostly opaque pixels of one race."""
    values = []
    for piece in range(4):
        image, _ = open_source(character_scene_source(race, piece))
        image = image.convert("RGBA")
        width, height = image.size
        left, top, right = CHARACTER_SCENE_CROP[piece]
        box = (int(left * width), int(top * height), int(right * width),
               height)
        luma = list(image.crop(box).convert("L").getdata())
        alpha = list(image.crop(box).getchannel("A").getdata())
        values.extend(l for l, a in zip(luma, alpha) if a >= 128)
        image.close()
    values.sort()
    return values[len(values) // 2]


def character_scene_gammas():
    """{destination token: gamma} for every race, Human 1."""
    shade = {}
    median = {}
    for race, dest, _fdid in CHARACTER_SCENE_RACES:
        shade[dest] = 1 - CHARACTER_SCENE_OVERLAY_SCALE * \
            CHARACTER_SCENE_OVERLAY.get(dest, CHARACTER_SCENE_OVERLAY_DEFAULT)
        median[dest] = character_scene_median(race)
    ref = CHARACTER_SCENE_REFERENCE
    shown = median[ref] * shade[ref]
    gammas = {}
    for dest in median:
        target = min(250.0, shown / shade[dest])
        if dest == ref:
            gammas[dest] = 1.0
        else:
            gammas[dest] = (math.log(target / 255.0)
                            / math.log(max(1, median[dest]) / 255.0))
    return gammas, median


def tone_character_scene(image, gamma):
    """Apply one gamma curve to RGB; alpha is untouched."""
    if gamma == 1.0:
        return image
    table = [int(round(255 * (i / 255.0) ** gamma)) for i in range(256)]
    r, g, b, a = image.split()
    return Image.merge("RGBA", (r.point(table), g.point(table),
                                b.point(table), a))


def stitch_character_scene(race):
    """The drawn part of a race's four pieces as one canvas-sized image."""
    canvas = Image.new("RGBA", CHARACTER_SCENE_CANVAS, (0, 0, 0, 0))
    parts = []
    for piece in range(4):
        image, _ = open_source(character_scene_source(race, piece))
        image = image.convert("RGBA")
        width, height = image.size
        left, top, right = CHARACTER_SCENE_CROP[piece]
        parts.append(image.crop((int(round(left * width)),
                                 int(round(top * height)),
                                 int(round(right * width)), height)))
        image.close()
    # Pieces 1/3 are the left column, 2/4 the right; 1/2 the top row.
    canvas.paste(parts[0], (0, 0))
    canvas.paste(parts[1], (parts[0].size[0], 0))
    canvas.paste(parts[2], (0, parts[0].size[1]))
    canvas.paste(parts[3], (parts[0].size[0], parts[0].size[1]))
    return canvas


def import_character_scene(dest_root):
    """Copy the 3D preview's Retail border and race art; returns rows."""
    rows = []
    gammas, medians = character_scene_gammas()
    for race, dest, fdid in CHARACTER_SCENE_RACES:
        dst = os.path.join(dest_root, "ui", "character", "dressup",
                           dest + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image = tone_character_scene(stitch_character_scene(race),
                                     gammas[dest])
        width, height = write_rle_tga(image, dst)
        tone = ("pixels unchanged" if gammas[dest] == 1.0 else
                "RGB toned by gamma %.3f (race median luminance %d brought "
                "to Human's on-screen brightness), alpha unchanged"
                % (gammas[dest], medians[dest]))
        rows.append({
            "dest": "ui/character/dressup/%s.tga" % dest,
            "size": "%dx%d" % (width, height),
            "supplied": "DressUpBackground-%s1..4.blp" % race,
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/DRESSUPFRAME/DressUpBackground-%s1..4.blp`: "
                    "FileDataIDs %d-%d, the four CharacterModelFrameBackground "
                    "pieces cropped to the texture coordinates "
                    "PaperDollFrame.xml draws and stitched into one image at "
                    "the canvas's top-left (231x374 drawn), %s. Drawn by the "
                    "Character window's 3D preview (CharacterModelScene)."
                    % (race, fdid, fdid + 3, tone),
        })
        print("%-34s %-9s Retail character scene (stitched)"
              % ("ui/character/dressup/" + dest, rows[-1]["size"]))
    for dest_name, source, fdid, members in CHARACTER_SCENE_ART:
        src = os.path.join(RETAIL_ART_ROOT, source.replace("/", os.sep))
        if not os.path.isfile(src):
            raise IOError("Character scene source missing: %s" % src)
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        image = image.convert("RGBA")
        conversion = "whole file, pixels unchanged"
        width, height = write_rle_tga(image, dst)
        image.close()
        rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": source.split("/")[-1],
            "note": "Blizzard Retail (The War Within) BlizzardInterfaceArt "
                    "`Interface/%s`: FileDataID %s, %s; %s. Drawn by the "
                    "Character window's 3D preview (CharacterModelScene)."
                    % (source, fdid, conversion, members),
        })
        print("%-34s %-9s Retail character scene"
              % (dest_name, rows[-1]["size"]))
    return rows


def luma_to_alpha(image, peak, grey=203):
    """Move a greyscale shape out of RGB and into the alpha channel.

    The result is the neutral grey wash form every vertex-coloured modern-wow
    texture uses: flat RGB, shape in alpha, peak scaled to `peak`.
    """
    alpha = image.convert("L")
    top = max(alpha.getdata())
    if peak and top:
        scale = float(peak) / float(top)
        alpha = alpha.point(lambda v: min(255, int(round(v * scale))))
    flat = Image.new("L", image.size, grey)
    return Image.merge("RGBA", (flat, flat, flat, alpha))


def apply_mask(image, mask):
    """Multiply the image's alpha by the mask's alpha; RGB is untouched."""
    image = image.convert("RGBA")
    mask = mask.convert("RGBA")
    if mask.size != image.size:
        raise ValueError("mask size %s does not match fill size %s"
                         % (mask.size, image.size))
    red, green, blue, alpha = image.split()
    shaped = Image.frombytes("L", image.size, bytes(
        (a * m + 127) // 255
        for a, m in zip(alpha.tobytes(), mask.getchannel("A").tobytes())))
    return Image.merge("RGBA", (red, green, blue, shaped))


# BLP2 direct-colour header: magic, type, encoding, alpha depth, alpha
# encoding, mip flag, width, height, then 16 mip offsets and 16 mip sizes.
BLP2_MIP_OFFSETS = 20
BLP2_MIP_SIZES = BLP2_MIP_OFFSETS + 16 * 4

# Encoding 3 is uncompressed BGRA. Pillow decodes BLP2 encodings 1 and 2 (the
# palettised and DXT forms) but raises BLPFormatError("Unknown BLP encoding 3")
# on this one, and 14 of the textures imported here use it -- so the top mip is
# unpacked directly rather than dropping those files or rasterising them by
# hand. Nothing is reinterpreted: the payload is already the exact BGRA bytes.
BLP2_ENCODING_RAW_BGRA = 3


def open_source(path):
    """Open a source texture, falling back to a BLP2 raw-BGRA reader."""
    try:
        image = Image.open(path)
        image.load()
        return image, "BLP" if path.lower().endswith(".blp") else None
    except Exception:
        if not path.lower().endswith(".blp"):
            raise

    with open(path, "rb") as handle:
        data = handle.read()

    if data[:4] != b"BLP2":
        raise ValueError("not a BLP2 file: " + path)
    encoding = data[8]
    if encoding != BLP2_ENCODING_RAW_BGRA:
        raise ValueError("unsupported BLP encoding %d: %s" % (encoding, path))

    width, height = struct.unpack_from("<II", data, 12)
    offset, = struct.unpack_from("<I", data, BLP2_MIP_OFFSETS)
    length, = struct.unpack_from("<I", data, BLP2_MIP_SIZES)
    expected = width * height * 4
    if length < expected:
        raise ValueError("truncated BLP mip 0: " + path)

    payload = data[offset:offset + expected]
    image = Image.frombytes("RGBA", (width, height), payload, "raw", "BGRA")
    return image, "BLP raw-BGRA"


def write_rle_tga(image, path):
    """Write the one form this client is confirmed to render.

    Type 10, 32bpp, descriptor 0x08, bottom-left origin -- the same contract
    unrealQuest/tools/make_navigator_textures.py asserts, taken from pfQuest's
    working 512x512 atlas.
    """
    image = image.convert("RGBA")
    image.save(path, format="TGA", compression="tga_rle")
    with open(path, "rb") as handle:
        header = handle.read(18)
    if (len(header) != 18 or header[2] != 10 or header[16] != 32
            or header[17] != 8):
        raise ValueError(
            "RLE TGA writer did not produce the proven type-10 header: " + path)
    return image.size


PLAYER_ARROW_SOURCE = "minimap/uiminimap2x.tga"
PLAYER_ARROW_DEST = "minimap/uiminimap-player-arrow-frames"
PLAYER_ARROW_BOX = (441, 238, 486, 283)
PLAYER_ARROW_FRAMES = 64
PLAYER_ARROW_COLUMNS = 8
PLAYER_ARROW_CELL = 64

CORPSE_ARROW_DEST = "minimap/uiminimap-corpse-arrow-frames"
# UI-HUD-Minimap-Arrow-Guard, the gold arrow with the blue gem (user request,
# 2026-09-30): the corpse pointer this client showed, in Retail's HD art.
CORPSE_ARROW_BOX = (441, 363, 486, 400)


def import_minimap_player_arrow(dest_root):
    """Bake Retail's player-arrow cell into the client's proven atlas form."""
    source_path = os.path.join(dest_root,
                               PLAYER_ARROW_SOURCE.replace("/", os.sep))
    source, _ = open_source(source_path)
    if source.size != (512, 1024):
        raise ValueError("unexpected uiminimap2x size %dx%d" % source.size)
    arrow = source.convert("RGBA").crop(PLAYER_ARROW_BOX)
    source.close()

    base = Image.new("RGBA", (PLAYER_ARROW_CELL, PLAYER_ARROW_CELL),
                     (0, 0, 0, 0))
    offset = (PLAYER_ARROW_CELL - arrow.size[0] + 1) // 2
    base.paste(arrow, (offset, offset))
    arrow.close()

    rows = PLAYER_ARROW_FRAMES // PLAYER_ARROW_COLUMNS
    atlas = Image.new("RGBA",
                      (PLAYER_ARROW_COLUMNS * PLAYER_ARROW_CELL,
                       rows * PLAYER_ARROW_CELL), (0, 0, 0, 0))
    for frame in range(PLAYER_ARROW_FRAMES):
        angle = 360.0 * frame / PLAYER_ARROW_FRAMES
        rotated = base.rotate(angle, resample=Image.BICUBIC, expand=False)
        column = frame % PLAYER_ARROW_COLUMNS
        row = frame // PLAYER_ARROW_COLUMNS
        atlas.paste(rotated,
                    (column * PLAYER_ARROW_CELL, row * PLAYER_ARROW_CELL))
        rotated.close()
    base.close()

    destination = os.path.join(
        dest_root, PLAYER_ARROW_DEST.replace("/", os.sep) + ".tga")
    width, height = write_rle_tga(atlas, destination)
    atlas.close()
    return {
        "dest": PLAYER_ARROW_DEST + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "minimap/uiminimap2x.tga",
        "note": "64 counter-clockwise directions baked from Blizzard "
                "Retail's exact 45x45 `UI-HUD-Minimap-Arrow-Player` member. "
                "The source is centred unchanged in each 64x64 cell; rotation "
                "is pre-rendered because this client breaks rotated Texture "
                "UVs. Drawn on both maps under every theme.",
    }


def import_minimap_corpse_arrow(dest_root):
    """Bake Retail's gold guide-arrow cell into the client's atlas form."""
    source_path = os.path.join(dest_root,
                               PLAYER_ARROW_SOURCE.replace("/", os.sep))
    source, _ = open_source(source_path)
    if source.size != (512, 1024):
        raise ValueError("unexpected uiminimap2x size %dx%d" % source.size)
    arrow = source.convert("RGBA").crop(CORPSE_ARROW_BOX)
    source.close()

    # The member is 45x37, so centre each axis on its own.
    base = Image.new("RGBA", (PLAYER_ARROW_CELL, PLAYER_ARROW_CELL),
                     (0, 0, 0, 0))
    base.paste(arrow, ((PLAYER_ARROW_CELL - arrow.size[0] + 1) // 2,
                       (PLAYER_ARROW_CELL - arrow.size[1] + 1) // 2))
    arrow.close()

    rows = PLAYER_ARROW_FRAMES // PLAYER_ARROW_COLUMNS
    atlas = Image.new("RGBA",
                      (PLAYER_ARROW_COLUMNS * PLAYER_ARROW_CELL,
                       rows * PLAYER_ARROW_CELL), (0, 0, 0, 0))
    for frame in range(PLAYER_ARROW_FRAMES):
        angle = 360.0 * frame / PLAYER_ARROW_FRAMES
        rotated = base.rotate(angle, resample=Image.BICUBIC, expand=False)
        column = frame % PLAYER_ARROW_COLUMNS
        row = frame // PLAYER_ARROW_COLUMNS
        atlas.paste(rotated,
                    (column * PLAYER_ARROW_CELL, row * PLAYER_ARROW_CELL))
        rotated.close()
    base.close()

    destination = os.path.join(
        dest_root, CORPSE_ARROW_DEST.replace("/", os.sep) + ".tga")
    width, height = write_rle_tga(atlas, destination)
    atlas.close()
    return {
        "dest": CORPSE_ARROW_DEST + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "minimap/uiminimap2x.tga",
        "note": "64 counter-clockwise directions baked from Blizzard "
                "Retail's exact 45x37 `UI-HUD-Minimap-Arrow-Guard` member "
                "(the gold arrow with the blue gem, by user request). "
                "The source is centred unchanged in each 64x64 cell; rotation "
                "is pre-rendered because this client breaks rotated Texture "
                "UVs. Drawn on the minimap under every theme.",
    }


def write_attribution(dest_root, rows, user_rows):
    lines = [
        "# modern-wow texture attribution",
        "",
        "Every texture in this folder originates in **%s**." % SOURCE_CREDIT,
        "It is imported for UnrealUI's `modern-wow` theme only, by explicit",
        "user decision. DragonflightUI-Reforged ships no LICENSE file, and part",
        "of its art derives from Blizzard UI assets; this note is not a licence",
        "grant and must stay with the files.",
        "",
        "Generated by `tools/import_modern_wow_media.py` -- do not hand-edit.",
        "",
        "Each file was decoded and re-encoded as 32-bit RLE TGA (image type 10,",
        "descriptor 0x08), the only addon texture form confirmed to render",
        "correctly on this client at full size",
        "(`knowledge.json / textures.uncompressed_512_tga_atlas_corrupts`).",
        "Pixels, dimensions and colour are otherwise unchanged.",
        "",
        "| unrealUI file | size | source in DragonflightUI-Reforged | source form |",
        "| --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append("| `%s` | %s | `%s` | %s |"
                     % (row["dest"], row["size"], row["source"], row["from"]))
    lines.append("")

    if user_rows:
        lines.extend([
            "## Not from DragonflightUI-Reforged",
            "",
            "The files below are **not imported from DragonflightUI-Reforged**,",
            "and the credit above does not apply to them. They are user-supplied",
            "or explicitly sourced as recorded in each note, then re-encoded",
            "under the same RLE-TGA contract as everything else here.",
            "",
            "| unrealUI file | size | supplied as | note |",
            "| --- | --- | --- | --- |",
        ])
        for row in user_rows:
            lines.append("| `%s` | %s | `%s` | %s |"
                         % (row["dest"], row["size"], row["supplied"],
                            row["note"]))
        lines.append("")

    path = os.path.join(dest_root, "ATTRIBUTION.md")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))


def main():
    addons = os.path.abspath(os.path.join(os.getcwd(), os.pardir))
    source_root = os.path.join(addons, SOURCE_ADDON)
    if not os.path.isdir(source_root):
        sys.stderr.write("DragonflightUI source not found: %s\n" % source_root)
        return 1

    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    rows = []

    for rel_source, dest_name in IMPORTS:
        src = os.path.join(source_root, rel_source.replace("/", os.sep))
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        image, note = open_source(src)
        source_mode = image.mode
        width, height = write_rle_tga(image, dst)
        image.close()

        source_ext = os.path.splitext(src)[1].lstrip(".").upper()
        rows.append({
            "source": rel_source,
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "from": note or "%s %s" % (source_ext, source_mode),
            "bytes": os.path.getsize(dst),
        })
        print("%-34s %-9s %s" % (dest_name, rows[-1]["size"], rows[-1]["from"]))

    for dest_name, base_name, box, mask_name, rel_source, note in DERIVED:
        base = os.path.join(dest_root, base_name.replace("/", os.sep) + ".tga")
        mask_path = os.path.join(dest_root, mask_name.replace("/", os.sep))
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        for path in (base, mask_path):
            if not os.path.isfile(path):
                sys.stderr.write("derived texture input missing: %s\n" % path)
                return 1

        image, _ = open_source(base)
        image = image.convert("RGBA")
        if box:
            image = image.crop(box)
        mask, _ = open_source(mask_path)
        width, height = write_rle_tga(apply_mask(image, mask), dst)
        image.close()
        mask.close()

        rows.append({
            "source": rel_source,
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "from": note,
            "bytes": os.path.getsize(dst),
        })
        print("%-34s %-9s %s" % (dest_name, rows[-1]["size"], note))

    mask_dest, mask_input = MASK_TEXTURE
    mask_path = os.path.join(dest_root, mask_input.replace("/", os.sep))
    if not os.path.isfile(mask_path):
        sys.stderr.write("mask texture input missing: %s\n" % mask_path)
        return 1
    mask, _ = open_source(mask_path)
    mask_size = write_rle_tga(
        mask, os.path.join(dest_root, mask_dest.replace("/", os.sep) + ".tga"))
    mask.close()

    user_rows = []
    for entry in USER_SUPPLIED:
        dest_name, supplied_as, note = entry[0], entry[1], entry[2]
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        src = dst if len(entry) < 4 else os.path.join(os.path.dirname(dst),
                                                      entry[3])
        # A separate input that has since been removed leaves the shipped TGA
        # as the only copy; re-encode that in place rather than abort the run.
        if not os.path.isfile(src) and os.path.isfile(dst):
            src = dst
        if not os.path.isfile(src):
            sys.stderr.write("user-supplied texture missing: %s\n" % src)
            return 1

        # Read fully before the re-encode overwrites it: PIL is lazy, and in
        # the in-place case the destination is also the source.
        source_image, _ = open_source(src)
        image = source_image.convert("RGBA")
        source_image.close()
        width, height = write_rle_tga(image, dst)
        image.close()

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s user-supplied" % (dest_name, user_rows[-1]["size"]))

    for dest_name, supplied_as, note in STATIC_USER_ART:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        if not os.path.isfile(dst):
            sys.stderr.write("static user art missing: %s\n" % dst)
            return 1
        image, _ = open_source(dst)
        width, height = image.size
        image.close()
        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s static user art"
              % (dest_name, user_rows[-1]["size"]))

    for dest_name, rel_source, box, supplied_as, note in FOREVER_ATLAS_CROPS:
        src = os.path.join(addons, rel_source.replace("/", os.sep))
        if not os.path.isfile(src):
            sys.stderr.write("Forever atlas source missing: %s\n" % src)
            return 1

        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        image, _ = open_source(src)
        crop = image.crop(box).convert("RGBA")
        image.close()
        width, height = write_rle_tga(crop, dst)
        crop.close()

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s Forever atlas crop"
              % (dest_name, user_rows[-1]["size"]))

    for dest_name, source_name, supplied_as, note in ROTATED:
        src = os.path.join(dest_root,
                           source_name.replace("/", os.sep) + ".tga")
        dst = os.path.join(dest_root,
                           dest_name.replace("/", os.sep) + ".tga")
        image, _ = open_source(src)
        rotated = image.convert("RGBA").transpose(Image.Transpose.ROTATE_270)
        image.close()
        width, height = write_rle_tga(rotated, dst)
        rotated.close()

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s user-supplied, rotated"
              % (dest_name, user_rows[-1]["size"]))

    for dest_name, supplied_as, peak, note in LUMA_ALPHA:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        src = os.path.join(os.path.dirname(dst), supplied_as)
        if not os.path.isfile(src):
            sys.stderr.write("user-supplied texture missing: %s\n" % src)
            return 1

        image, _ = open_source(src)
        width, height = write_rle_tga(luma_to_alpha(image, peak), dst)
        image.close()

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s user-supplied, luminance to alpha"
              % (dest_name, user_rows[-1]["size"]))

    for dest_name, fill_name, mask_name, note in MASKED:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        folder = os.path.dirname(dst)
        fill_path = os.path.join(folder, fill_name)
        mask_path = os.path.join(folder, mask_name)
        if os.path.isfile(fill_path) and os.path.isfile(mask_path):
            fill, _ = open_source(fill_path)
            mask, _ = open_source(mask_path)
            width, height = write_rle_tga(apply_mask(fill, mask), dst)
            fill.close()
            mask.close()
        elif os.path.isfile(dst):
            image, _ = open_source(dst)
            width, height = image.size
            image.close()
        else:
            sys.stderr.write("user-supplied texture missing: %s\n" % fill_path)
            return 1

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": fill_name,
            "note": note + " Alpha multiplied by `%s` (no texture mask API "
                    "on this client)." % mask_name,
        })
        print("%-34s %-9s user-supplied, masked"
              % (dest_name, user_rows[-1]["size"]))

    dest_name, supplied_as, canvas, note, cells = NINE_SLICE
    dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
    src = os.path.join(os.path.dirname(dst), supplied_as)
    if os.path.isfile(src):
        # Premultiplied while resampling, so transparent pixels' colour does
        # not fringe the metal's edges.
        image, _ = open_source(src)
        image = image.convert("RGBA")
        atlas = Image.new("RGBA", canvas, (0, 0, 0, 0))
        for _, box, at in cells:
            piece = image.crop(box).convert("RGBa")
            piece = piece.resize((piece.width // 2, piece.height // 2),
                                 Image.LANCZOS).convert("RGBA")
            atlas.paste(piece, at)
            print("  %-14s -> %dx%d at %s" % (_, piece.width, piece.height, at))
        image.close()
        size = write_rle_tga(atlas, dst)
    elif os.path.isfile(dst):
        # The PNG is the only input the slices can be cut from; without it the
        # shipped atlas is kept as it is.
        image, _ = open_source(dst)
        size = image.size
        image.close()
    else:
        sys.stderr.write("user-supplied texture missing: %s\n" % src)
        return 1
    user_rows.append({
        "dest": dest_name + ".tga",
        "size": "%dx%d" % size,
        "supplied": supplied_as,
        "note": note,
    })
    print("%-34s %-9s user-supplied, 9-slice" % (dest_name, user_rows[-1]["size"]))

    user_rows.append({
        "dest": mask_dest + ".tga",
        "size": "%dx%d" % mask_size,
        "supplied": os.path.basename(mask_input),
        "note": "The cast-bar mask as a drawable texture, used to shape the "
                "status-bar pulse on the cast bar.",
    })

    for dest_name, supplied_as, box, size, note in SHEET_CROPS:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        src = os.path.join(os.path.dirname(dst), supplied_as)
        if os.path.isfile(src):
            image, _ = open_source(src)
            grid = image.crop(box).convert("RGBA")
            image.close()
            if size:
                # Premultiplied while resampling, so the transparent canvas
                # around each frame's glow cannot fringe it.
                grid = grid.convert("RGBa").resize(size, Image.LANCZOS)
                grid = grid.convert("RGBA")
            width, height = write_rle_tga(grid, dst)
            grid.close()
        elif os.path.isfile(dst):
            # The sheet is the only input this can be cut from; without it the
            # shipped grid is kept as it is.
            image, _ = open_source(dst)
            width, height = image.size
            image.close()
        else:
            sys.stderr.write("user-supplied texture missing: %s\n" % src)
            return 1

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s user-supplied, sheet crop"
              % (dest_name, user_rows[-1]["size"]))

    user_rows.append(import_minimap_player_arrow(dest_root))
    user_rows.append(import_minimap_corpse_arrow(dest_root))
    user_rows.append(import_retail_bag_indicator(dest_root))
    user_rows.append(import_retail_junk_coin(dest_root))
    user_rows.extend(import_retail_target(addons, dest_root))
    user_rows.extend(import_character_stats(dest_root))
    user_rows.extend(import_character_housing(dest_root))
    user_rows.extend(import_character_scene(dest_root))
    user_rows.extend(import_equipment_manager(dest_root))

    write_attribution(dest_root, rows, user_rows)
    print("")
    print("%d textures imported, %d user-supplied, in %s"
          % (len(rows), len(user_rows), DEST_SUBPATH))
    return 0


def main_retail_target():
    """Re-cut only the Retail target textures, leaving every other file alone.

    Prints their ATTRIBUTION.md rows exactly as a full run writes them, for a
    working tree where a full re-import would re-encode unrelated files.
    """
    addons = os.path.abspath(os.path.join(os.getcwd(), os.pardir))
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    for row in import_retail_target(addons, dest_root):
        print("| `%s` | %s | `%s` | %s |"
              % (row["dest"], row["size"], row["supplied"], row["note"]))
    return 0


def main_minimap_player_arrow():
    """Rebuild the Retail-derived map arrows and their attribution."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    player = import_minimap_player_arrow(dest_root)
    corpse = import_minimap_corpse_arrow(dest_root)
    rows = [
        {
            "dest": "minimap/uiminimap2x.tga",
            "size": "512x1024",
            "supplied": "uiminimap2x.tga",
            "note": "Blizzard Retail HD minimap atlas, FileDataID 4618666 / "
                    "atlas 1995. Members `UI-HUD-Minimap-Arrow-Guard`: "
                    "L=441 R=486 T=363 B=400 (45x37), and "
                    "`UI-HUD-Minimap-Arrow-Player`: L=441 R=486 T=238 "
                    "B=283 (45x45).",
        },
        player,
        corpse,
    ]
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    for row in rows:
        rendered = "| `%s` | %s | `%s` | %s |" % (
            row["dest"], row["size"], row["supplied"], row["note"])
        prefix = "| `%s` |" % row["dest"]
        for index, line in enumerate(lines):
            if line.startswith(prefix):
                lines[index] = rendered
                break
        else:
            lines.append(rendered)
        print(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return 0


def main_bag_indicator():
    """Re-copy only Combined Bags' Retail item-slot highlight."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    row = import_retail_bag_indicator(dest_root)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    rendered = "| `%s` | %s | `%s` | %s |" % (
        row["dest"], row["size"], row["supplied"], row["note"])
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    prefix = "| `%s` |" % row["dest"]
    found = False
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = rendered
            found = True
            break
    if not found:
        lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print(rendered)
    return 0


# The Tracked Bars (user request, 2026-09-29): Retail's Cooldown Manager
# sheet `interface/hud/uicooldownmanager2x`, FileDataID 6739577 (atlas 3186),
# the HD member of CooldownViewer.xml's UI-HUD-CoolDownManager-* atlases.
# Blizzard's file, supplied as the copy BigWigs ships in its media folder;
# copied whole and addressed by the atlas rectangles in core/media.lua.
COOLDOWN_MANAGER_SOURCE = os.environ.get(
    "UNREALUI_COOLDOWN_MANAGER_BLP",
    r"D:\Development\unrealUI_data\AishUI_Classic_FREE_v2.7.1\Interface"
    r"\AddOns\BigWigs\Media\Textures\UICooldownManager2x.blp")
COOLDOWN_MANAGER_DEST = "ui/cooldown-manager"


def import_cooldown_manager(dest_root):
    if not os.path.isfile(COOLDOWN_MANAGER_SOURCE):
        raise IOError("Cooldown Manager source missing: %s"
                      % COOLDOWN_MANAGER_SOURCE)
    image, _ = open_source(COOLDOWN_MANAGER_SOURCE)
    image = image.convert("RGBA")
    if image.size != (512, 256):
        raise ValueError("unexpected Cooldown Manager sheet size %dx%d"
                         % image.size)
    dst = os.path.join(dest_root,
                       COOLDOWN_MANAGER_DEST.replace("/", os.sep) + ".tga")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    width, height = write_rle_tga(image, dst)
    image.close()
    return {
        "dest": COOLDOWN_MANAGER_DEST + ".tga",
        "size": "%dx%d" % (width, height),
        "supplied": "UICooldownManager2x.blp",
        "note": "Blizzard Retail 12.1.0.69933 FileDataID 6739577 "
                "(`interface/hud/uicooldownmanager2x`, atlas 3186), the whole "
                "sheet, pixels unchanged (BLP2 raw BGRA to RLE TGA); supplied "
                "as the copy BigWigs ships in its media folder. Members "
                "`UI-HUD-CoolDownManager-Bar` L=175 R=423 T=41 B=61, `-Bar-BG` "
                "L=175 R=439 T=1 B=39, `-Bar-Pip` L=175 R=195 T=63 B=155 and "
                "`-IconOverlay` L=1 R=173 T=1 B=173 (RetailFrameXML "
                "`query.py filedata 6739577`). Drawn by the Tracked Bars "
                "(M.modernWow.trackedBars).",
    }


def main_cooldown_manager():
    """Import only the Cooldown Manager sheet and upsert its attribution row."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    row = import_cooldown_manager(dest_root)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    rendered = "| `%s` | %s | `%s` | %s |" % (
        row["dest"], row["size"], row["supplied"], row["note"])
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    prefix = "| `%s` |" % row["dest"]
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = rendered
            break
    else:
        lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print(rendered)
    return 0


def main_junk_coin():
    """Re-cut only Retail's bags-junkcoin and upsert its attribution row."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    row = import_retail_junk_coin(dest_root)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    rendered = "| `%s` | %s | `%s` | %s |" % (
        row["dest"], row["size"], row["supplied"], row["note"])
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    prefix = "| `%s` |" % row["dest"]
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = rendered
            break
    else:
        lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print(rendered)
    return 0


def main_target_ring_tint():
    """Re-derive only the target ring tint and upsert its attribution row."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    row = import_target_ring_tint(dest_root)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    rendered = "| `%s` | %s | `%s` | %s |" % (
        row["dest"], row["size"], row["supplied"], row["note"])
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    prefix = "| `%s` |" % row["dest"]
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = rendered
            break
    else:
        lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print(rendered)
    return 0


def main_character_stats():
    """Re-cut only the stats side panel textures, as main_retail_target does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    for row in import_character_stats(dest_root):
        print("| `%s` | %s | `%s` | %s |"
              % (row["dest"], row["size"], row["supplied"], row["note"]))
    return 0


def main_character_housing():
    """Re-cut only the Character housing textures, as main_retail_target does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    for row in import_character_housing(dest_root):
        print("| `%s` | %s | `%s` | %s |"
              % (row["dest"], row["size"], row["supplied"], row["note"]))
    return 0


def main_character_sidebar():
    """Re-copy only the sidebar tab sheet, as main_retail_target does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    for row in import_character_sidebar(dest_root):
        print("| `%s` | %s | `%s` | %s |"
              % (row["dest"], row["size"], row["supplied"], row["note"]))
    return 0


def main_character_scene():
    """Re-copy only the 3D preview textures, as main_retail_target does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    # The pre-stitch per-piece rows no longer describe any file.
    lines = [line for line in lines
             if not re.match(r"\| `ui/character/dressup/[a-z]+[1-4]\.tga` \|",
                             line)]
    for row in import_character_scene(dest_root):
        rendered = "| `%s` | %s | `%s` | %s |" % (
            row["dest"], row["size"], row["supplied"], row["note"])
        prefix = "| `%s` |" % row["dest"]
        for index, line in enumerate(lines):
            if line.startswith(prefix):
                lines[index] = rendered
                break
        else:
            lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return 0


def main_equipment_manager():
    """Re-copy only the Equipment Manager art and upsert its attribution rows,
    as main_bag_indicator does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    for row in import_equipment_manager(dest_root):
        rendered = "| `%s` | %s | `%s` | %s |" % (
            row["dest"], row["size"], row["supplied"], row["note"])
        prefix = "| `%s` |" % row["dest"]
        for index, line in enumerate(lines):
            if line.startswith(prefix):
                lines[index] = rendered
                break
        else:
            lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return 0


def main_character_reputation():
    """Re-copy only the Reputation page's art and upsert its attribution rows,
    as main_equipment_manager does."""
    dest_root = os.path.join(os.getcwd(), DEST_SUBPATH)
    attribution = os.path.join(dest_root, "ATTRIBUTION.md")
    with open(attribution, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    for row in import_character_reputation(dest_root):
        rendered = "| `%s` | %s | `%s` | %s |" % (
            row["dest"], row["size"], row["supplied"], row["note"])
        prefix = "| `%s` |" % row["dest"]
        for index, line in enumerate(lines):
            if line.startswith(prefix):
                lines[index] = rendered
                break
        else:
            lines.append(rendered)
    with open(attribution, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    if "--minimap-player-arrow" in sys.argv[1:]:
        sys.exit(main_minimap_player_arrow())
    if "--cooldown-manager" in sys.argv[1:]:
        sys.exit(main_cooldown_manager())
    if "--junk-coin" in sys.argv[1:]:
        sys.exit(main_junk_coin())
    if "--bag-indicator" in sys.argv[1:]:
        sys.exit(main_bag_indicator())
    if "--retail-target" in sys.argv[1:]:
        sys.exit(main_retail_target())
    if "--target-ring-tint" in sys.argv[1:]:
        sys.exit(main_target_ring_tint())
    if "--character-stats" in sys.argv[1:]:
        sys.exit(main_character_stats())
    if "--character-housing" in sys.argv[1:]:
        sys.exit(main_character_housing())
    if "--character-scene" in sys.argv[1:]:
        sys.exit(main_character_scene())
    if "--character-sidebar" in sys.argv[1:]:
        sys.exit(main_character_sidebar())
    if "--equipment-manager" in sys.argv[1:]:
        sys.exit(main_equipment_manager())
    if "--character-reputation" in sys.argv[1:]:
        sys.exit(main_character_reputation())
    sys.exit(main())
