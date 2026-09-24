# forever-wow texture attribution

Art imported for UnrealUI's grouped game-settings window
(`modules/gamesettings.lua`), which reproduces the structure of WoW Forever's
own settings window.

## Source

- Product: `wow_classic_beta`, Blizzard game type `camelot`
- Build: **1.60.1.69913**, Interface `16001`
- Reference bundle: `AddOns/ForeverFrameXML-1.60.1.69913`
- Art catalogue: `ForeverFrameXML-1.60.1.69913/wowdata-art-ui/`, from
  <https://wowdata.app/#art-ui>, catalogued 2026-09-20
- Owning UI code: `Interface/AddOns/Blizzard_Settings_Shared`

These are Blizzard Entertainment UI assets, imported as interoperability
reference for a client-side interface reimplementation. This is not a licence
grant, and nothing here should be treated as one.

## Conversion

Format-level only, matching the encoding UnrealUI already ships:
PNG -> **RLE-compressed 32-bit TGA, origin bottom-left** (`desc=0x08`), via
Pillow `compression="tga_rle"`. No pixel was restyled, recoloured, resized or
cropped — every sheet is imported whole at its authored power-of-two size, and
atlas members are addressed by texture coordinates from `core/media.lua`
(`M.foreverWow`).

Atlas geometry was read from the build's own DB2 tables with
`python query.py atlasmap <name> --exact`, never measured off a screenshot.

## Files

| File | Size | FileDataID | Atlas members used | Notes |
| --- | --- | --- | --- | --- |
| `settings/options.tga` | 1024x1024 | 1318750 | `Options_InnerFrame`, `Options_HorizontalDivider`, `Options_List_Active`, `Options_List_Hover`, `Options_Tab_Left/Middle/Right`, `Options_Tab_Active_Left/Middle/Right` | The settings window's own atlas. Inner recessed plate (886x618), the 630x1 header divider, the two category-row states (187x21 each, no "normal" member — an idle row draws nothing) and both three-slice tab sets. |
| `settings/list-expand.tga` | 128x128 | 4571485 | `Options_ListExpand_Right`, `Options_ListExpand_Right_Expanded`, `Options_ListExpand_Left` (1..13 x 84..110), `_Options_ListExpand_Middle` (0..1 x 28..54) | The category list's collapse chevron, 28x26 per state. Since 2026-09-22 the same sheet also draws `SettingsExpandableSectionTemplate`'s bar on every Key Bindings category: the 12x26 left cap and the 1x26 stretched middle under that chevron. |
| `ui/frame-metal-corners.tga` | 1024x512 | 8069116 | `UI-Frame-Metal-CornerTopLeft/TopRight/BottomLeft/BottomRight` | Four corners of the `ButtonFrameTemplateNoPortrait` nine-slice. The top pair is 190x190, the bottom pair 190x200. |
| `ui/frame-metal-edge-h.tga` | 256x512 | 8069118 | `_UI-Frame-Metal-EdgeTop`, `_UI-Frame-Metal-EdgeBottom` | Top and bottom edges of the same nine-slice, 256 wide, stretched along the frame. |
| `ui/frame-metal-edge-v.tga` | 512x256 | 8069114 | `!UI-Frame-Metal-EdgeLeft`, `!UI-Frame-Metal-EdgeRight` | Left and right edges, 190x256, stretched down the frame. |
| `ui/panel-background.tga` | 64x32 | 4700695 | `uiframebackground-nineslice-cornerbottomleft`, `uiframebackground-nineslice-cornerbottomright` | `FlatPanelBackgroundTemplate`'s two 16x16 bottom corners. Blizzard tints every piece with `PANEL_BACKGROUND_COLOR`, so these carry shape rather than art. |
| `settings/common-dropdown.tga` | 512x512 | 8069110 | `common-dropdown-c-button` (431..509 x 1..79), `-c-button-hover-1/-2`, `-c-button-pressed-1/-2`, `-c-button-pressedhover-1/-2`, `-c-button-open`, `-c-button-disabled`, `-c-button-hover-arrow` (183..207 x 139..149), `common-dropdown-c-bg` (1..181 x 1..181), `common-dropdown-bg`, `common-dropdown-textholder`, `common-dropdown-a-button*` (54x54), `common-dropdown-b-button*` (194x52) | Forever's bronze-rimmed control sheet: the Forever-build variant of `modern-wow/buttons/setting-ui.tga` (5412379, silver), with the same bed layout. Imported and drawn 2026-09-21 by user request; not drawn since 2026-09-22, when by user request the dropdown bed, its steppers and the open menu went back to `modern-wow/buttons/setting-ui.tga` (5412379, the same atlas at the same rectangles except `common-dropdown-c-button-hover-arrow`). |
| `settings/search.tga` | 256x128 | 3281887 | `common-search-border-left` (227..243 x 43..83), `common-search-border-middle` (1..225 x 43..83), `common-search-border-right` (1..17 x 85..125), `common-search-magnifyingglass` (19..43 x 85..109), `common-search-clearbutton` (45..65 x 85..105) | User-selected shared grey `SearchBoxTemplate` sheet. The caps draw 8x20, the middle stretches horizontally, both glyphs draw 10x10, and the clear glyph sits in its 17x17 button. |
| `settings/checkbox-minimal.tga` | 32x32 | 8086474 | `checkbox-minimal` (1..31 x 1..30, 30x29) | `SettingsCheckboxTemplate`'s bed, Forever variant. Imported 2026-09-21; not drawn since the same day -- by user request the box is `checkbox-minimal` on `checkmark-minimal.tga` (4614134) instead. |
| `settings/checkmark-minimal.tga` | 64x64 | 4614134 | `checkbox-minimal` (1..31 x 1..30), `checkmark-minimal` (1..31 x 32..61), `checkmark-minimal-disabled` (33..63 x 1..30) | The only sheet carrying the tick in this build. Drawn since 2026-09-21: the tick, and (by user request) the box too, as `checkbox-minimal` from this sheet. |
| `settings/minimal-slider.tga` | 32x128 | 8086434 | `_Minimal_SliderBar_Middle` (0..1 x 1..18, tiles horizontally), `Minimal_SliderBar_Left` (14..25 x 41..58), `Minimal_SliderBar_Right` (1..12 x 62..79), `Minimal_SliderBar_Button` (1..21 x 20..39), `Minimal_SliderBar_Button_Left` (1..12 x 41..60), `Minimal_SliderBar_Button_Right` (1..10 x 81..99) | `MinimalSliderWithSteppersTemplate`, Forever variant. Drawn 2026-09-21 to 2026-09-22; since then the sliders draw its silver recolour, `modern-wow/buttons/minimal-slider-silver.tga` (user request), which keeps this sheet's layout and is recorded in that folder's ATTRIBUTION.md. Kept as the source of that copy. |
| `ui/minimal-scrollbar.tga` | 128x64 | 8069102 | `minimal-scrollbar-arrow-top/-over` (88..105 / 107..124 x 1..12), `minimal-scrollbarl-arrow-top-down` (50..67 x 14..25, Blizzard's spelling), `minimal-scrollbar-arrow-bottom/-down/-over`, `minimal-scrollbar-track-top` (21..29 x 39..47), `minimal-scrollbar-track-bottom` (11..19 x 49..57), `minimal-scrollbar-thumb-top/-bottom*`, `minimal-scrollbar-arrow-returntobottom*` | `MinimalScrollBar` arrows and track caps, Forever variant of what `modern-wow/ui/minimal-scrollbar-proportional.tga` carries. Drawn 2026-09-21 to 2026-09-22; not drawn since -- by user request the list scrollbar uses the Modern WoW MinimalScrollBar in `modern-wow/ui` (`M.modernWow.scrollbar`). |
| `ui/minimal-scrollbar-small.tga` | 64x64 | 8069100 | `minimal-scrollbar-small-thumb-top/-over/-down` (20..28 / 30..38 x 54..62 / 44..52), `minimal-scrollbar-small-thumb-bottom/-over/-down`, `minimal-scrollbar-small-track-top/-bottom`, `minimal-scrollbar-small-arrow-*` | The small thumb's caps `MinimalScrollBar` draws. Drawn 2026-09-21 to 2026-09-22; not drawn since -- by user request the list scrollbar uses the Modern WoW MinimalScrollBar in `modern-wow/ui` (`M.modernWow.scrollbar`). |
| `ui/minimal-scrollbar-small-middle.tga` | 64x1024 | 8069104 | `minimal-scrollbar-small-thumb-middle/-down/-over` (11..19 / 21..29 / 31..39 x 1..716), `!minimal-scrollbar-small-track-middle` | The small thumb's stretched body. Drawn 2026-09-21 to 2026-09-22; not drawn since -- by user request the list scrollbar uses the Modern WoW MinimalScrollBar in `modern-wow/ui` (`M.modernWow.scrollbar`). |
| `ui/minimal-scrollbar-middle.tga` | 64x1024 | 8086478 | `!minimal-scrollbar-track-middle` (1..9 x 0..1, tiles vertically), `minimal-scrollbar-thumb-middle/-down/-over` | The track's stretched middle `MinimalScrollBar` draws. Drawn 2026-09-21 to 2026-09-22; not drawn since -- by user request the list scrollbar uses the Modern WoW MinimalScrollBar in `modern-wow/ui` (`M.modernWow.scrollbar`). |
| `ui/red-button.tga` | 512x256 | 8107305 | `RedButton-Exit` (67..131 x 1..65), `RedButton-Exit-Disabled` (67..131 x 67..131), `RedButton-exit-pressed` (67..131 x 133..197), `RedButton-Highlight` (199..263 x 1..65), `RedButton-MiniCondense*`, `RedButton-Condense*`, `RedButton-Expand*` | `UIPanelCloseButton` and the minimise/maximise buttons of `ButtonFrameTemplate`, Forever variant. Drawn since 2026-09-21: `RedButton-Exit` / `-exit-pressed` / `-Highlight` as the window's close X (`M.foreverWow.control.close`). |
| `buttons/ui-panel-button-up.tga`, `-down`, `-highlight`, `-disabled`, `-disabled-down` | 128x32 each | client path `Interface\Buttons\UI-Panel-Button-*` | whole files | `UIPanelButtonNoTooltipTemplate`'s Left/Middle/Right faces (one file, three texcoord slices) for Close, Apply and Defaults. From `wowdata-art-ui/interface/buttons/`. Drawn 2026-09-21 to 2026-09-22; not drawn since -- by user request the window's rectangular buttons wear the HD `modern-wow/buttons/128RedButton.tga` face (`M.modernWow.button128Red`), because these 22-row faces drew soft at the window's size. |
| `buttons/ui-silver-button-up.tga`, `-down`, `-highlight`, `-select` | 128x32 each | client path `Interface\Buttons\UI-Silver-Button-*` | whole files | `UIMenuButtonStretchTemplate`'s nine-slice face (four 12x6 corners; the slices cover x 0..80, y 0..26 of the sheet), its ADD highlight, and `KeyBindingFrameBindingButtonTemplate`'s SelectedHighlight. Imported 2026-09-22 by user request: every binding button on the Key Bindings page wears this face, as Forever's own Keybindings page does. From `wowdata-art-ui/interface/buttons/`. The select sheet is imported with the set; no surface draws it yet. |
| `ui/dialog-header-diamond-metal.tga` | 256x512 | 8069124 | Blizzard's `DialogHeaderTemplate` plate from build 1.60.1.69913, FileDataID 8069124 (atlas 3982; the identical sheet is also published as 3058483/atlas 1505), imported whole at its authored 256x512 from `ForeverFrameXML-1.60.1.69913/wowdata-art-ui/interface/UI/8069124.png`. Three members, addressed by texture coordinates: `_UI-Frame-DiamondMetal-Header-Tile` (x 0-128, y 1-157), `UI-Frame-DiamondMetal-Header-CornerLeft` (x 1-129, y 159-315) and `UI-Frame-DiamondMetal-Header-CornerRight` (x 1-129, y 317-473), each 64x78 logical, drawn by the template at 32x39 in a 39-high header. Rectangles read with `python query.py atlasmap <name> --exact`. Moved from `modern-wow/ui/` to this folder 2026-09-23 (user request). |

## Not imported

Deliberately absent, so the folder stays what a shipped surface actually draws:

- **Help plate, tutorial and NewFeature art** — the surfaces that
  would draw them are not implemented.

## Forever control art (2026-09-21)

The rows dated 2026-09-21 were imported by explicit user request and are drawn
by the window's controls: dropdowns, checkboxes, sliders and their steppers,
the page and window buttons, the close X, and the list scrollbar (through the
shared `U.StyleModernWowScrollbar` with `M.foreverWow.scrollbar`). The window
no longer draws from `modern-wow/buttons/setting-ui.tga`. Where an atlas member
exists on several sheets, the Forever-build sheet (FileDataID 8069xxx /
8086xxx / 8107xxx, bronze-rimmed) was chosen over the older 4xxxxxx / 5xxxxxx
one; the checkmark exists only on 4614134. Members on these sheets that no
control draws (`common-dropdown-a/b-*`, the `-2` dropdown states, the large
scrollbar thumb, `RedButton-Condense/Expand/MiniCondense`) come with the
sheets, which are imported whole.

Keep this table accurate on any later import.
