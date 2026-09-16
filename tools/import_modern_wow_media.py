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

import os
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
    ("media/tex/ui/UI-Classes-Circles.tga", "ui/class-portraits"),

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
    # Three states per icon (regular / highlight / faded) plus the one
    # talents-disabled state the source ships. The names are the source's own
    # glyph vocabulary because that is what identifies which button each is.
    ("media/tex/micromenu/color_micro/wow-regular.tga", "microbar/menu"),
    ("media/tex/micromenu/color_micro/wow-highlight.tga",
     "microbar/menu-highlight"),
    ("media/tex/micromenu/color_micro/wow-faded.tga", "microbar/menu-faded"),
    ("media/tex/micromenu/color_micro/shield-regular.tga",
     "microbar/character"),
    ("media/tex/micromenu/color_micro/shield-highlight.tga",
     "microbar/character-highlight"),
    ("media/tex/micromenu/color_micro/shield-faded.tga",
     "microbar/character-faded"),
    ("media/tex/micromenu/color_micro/spellbook-regular.tga",
     "microbar/spellbook"),
    ("media/tex/micromenu/color_micro/spellbook-highlight.tga",
     "microbar/spellbook-highlight"),
    ("media/tex/micromenu/color_micro/spellbook-faded.tga",
     "microbar/spellbook-faded"),
    ("media/tex/micromenu/color_micro/talents-regular.tga", "microbar/talents"),
    ("media/tex/micromenu/color_micro/talents-highlight.tga",
     "microbar/talents-highlight"),
    ("media/tex/micromenu/color_micro/talents-faded.tga",
     "microbar/talents-faded"),
    ("media/tex/micromenu/color_micro/talents-disabled.tga",
     "microbar/talents-disabled"),
    ("media/tex/micromenu/color_micro/quest-regular.tga", "microbar/quest"),
    ("media/tex/micromenu/color_micro/quest-highlight.tga",
     "microbar/quest-highlight"),
    ("media/tex/micromenu/color_micro/quest-faded.tga", "microbar/quest-faded"),
    ("media/tex/micromenu/color_micro/book-regular.tga", "microbar/log"),
    ("media/tex/micromenu/color_micro/book-highlight.tga",
     "microbar/log-highlight"),
    ("media/tex/micromenu/color_micro/book-faded.tga", "microbar/log-faded"),
    ("media/tex/micromenu/color_micro/eye-regular.tga", "microbar/social"),
    ("media/tex/micromenu/color_micro/eye-highlight.tga",
     "microbar/social-highlight"),
    ("media/tex/micromenu/color_micro/eye-faded.tga", "microbar/social-faded"),
    ("media/tex/micromenu/color_micro/tabard-regular.tga", "microbar/guild"),
    ("media/tex/micromenu/color_micro/tabard-highlight.tga",
     "microbar/guild-highlight"),
    ("media/tex/micromenu/color_micro/tabard-faded.tga",
     "microbar/guild-faded"),
    ("media/tex/micromenu/color_micro/horseshoe-regular.tga", "microbar/pet"),
    ("media/tex/micromenu/color_micro/horseshoe-highlight.tga",
     "microbar/pet-highlight"),
    ("media/tex/micromenu/color_micro/horseshoe-faded.tga",
     "microbar/pet-faded"),
    ("media/tex/micromenu/color_micro/question-regular.tga", "microbar/help"),
    ("media/tex/micromenu/color_micro/question-highlight.tga",
     "microbar/help-highlight"),
    ("media/tex/micromenu/color_micro/question-faded.tga",
     "microbar/help-faded"),

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
    ("ui/golden-square-border", "golden-square-border.png",
     "Gold square icon frame at 256x256 with a transparent opening at "
     "x 32-223, y 30-220. Drawn around each talent tree's header icon in the "
     "modern-wow Talent window; geometry is tokenised in core/media.lua.",
     "golden-square-border.png"),
    ("ui/combo-points", "combo-points.png",
     "Rogue and Cat Form combo-point atlas at 128x56: the left 57x56 "
     "circle is inactive and the right 57x56 circle is active. Drawn on "
     "the player or target frame opposite the configured aura position.",
     "combo-points.png"),
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
    ("ui/red-button", "redbutton2x.blp",
     "Dragonflight octagonal button atlas: a 5x3 grid of 34x38 cells on a "
     "256x128 canvas -- minimize / close / maximize / minus glyphs across, "
     "normal / disabled / pushed down. The close column is what modern-wow "
     "draws on window close buttons; DragonflightUI ships only that one glyph, "
     "as the separate `close_normal` / `close_pushed` files, and without its "
     "disabled face.",
     "redbutton2x.blp"),
    ("ui/128RedButton", "128RedButton.tga",
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
     "Character gear slot; cells are tokenised in core/media.lua.",
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
     "Spellbook atlas at 256x256: spell slot frame, slot background and the "
     "soft name shadow are drawn on each spell button; cells are tokenised in "
     "core/media.lua.",
     "Spellbook-Parts.png"),
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
        image, _ = open_source(src)
        image = image.convert("RGBA")
        width, height = write_rle_tga(image, dst)
        image.close()

        user_rows.append({
            "dest": dest_name + ".tga",
            "size": "%dx%d" % (width, height),
            "supplied": supplied_as,
            "note": note,
        })
        print("%-34s %-9s user-supplied" % (dest_name, user_rows[-1]["size"]))

    for dest_name, fill_name, mask_name, note in MASKED:
        dst = os.path.join(dest_root, dest_name.replace("/", os.sep) + ".tga")
        folder = os.path.dirname(dst)
        fill_path = os.path.join(folder, fill_name)
        mask_path = os.path.join(folder, mask_name)
        for path in (fill_path, mask_path):
            if not os.path.isfile(path):
                sys.stderr.write("user-supplied texture missing: %s\n" % path)
                return 1

        fill, _ = open_source(fill_path)
        mask, _ = open_source(mask_path)
        width, height = write_rle_tga(apply_mask(fill, mask), dst)
        fill.close()
        mask.close()

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

    write_attribution(dest_root, rows, user_rows)
    print("")
    print("%d textures imported, %d user-supplied, in %s"
          % (len(rows), len(user_rows), DEST_SUBPATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
