# Extended QuestLog parchment artwork

Two-page parchment art for the Classic WoW theme's extended Quest Log
(`modules/questlogextended.lua`, paths built only from `M.classicWow` in
`core/media.lua`).

| File | Source | Origin |
| --- | --- | --- |
| `questLog_TopLeft.tga` | `Interface/AddOns/unrealQuest/media/QuestLog/EQL3_TopLeft.tga` | Extended QuestLog 3.6.1 |
| `questLog_TopSwitchOn.tga` | `.../EQL3_TopSwitchOn.tga` | Extended QuestLog 3.6.1 |
| `questLog_TopMiddle.tga` | `.../EQL3_TopMiddle.tga` | Extended QuestLog 3.6.1 |
| `questLog_TopRight.tga` | `.../EQL3_TopRight.tga` | Extended QuestLog 3.6.1 |
| `questLog_BottomLeft.tga` | `.../EQL3_BottomLeft.tga` | Extended QuestLog 3.6.1 |
| `questLog_BottomSwitchOn.tga` | `.../EQL3_BottomSwitchOn.tga` | Extended QuestLog 3.6.1 |
| `questLog_BottomMiddle.tga` | `.../EQL3_BottomMiddle.tga` | Extended QuestLog 3.6.1 |
| `questLog_BottomRight.tga` | `.../EQL3_BottomRight.tga` | Extended QuestLog 3.6.1 |

Origin: Extended QuestLog 3.6.1, Copyright (c) 2006 Daniel Rehn. The supplied
EQL3 package carried no separate licence text; these files keep their original
copyright and are not original unrealUI artwork. See `LICENSE`.

Conversion: none. Each file is a byte-identical copy of the file UnrealQuest
already ships and this client already draws (uncompressed 32-bit TGA, 256x256 /
128x256 / 64x256). Do not re-encode, recolour or crop them -- the classic-wow page
geometry in `core/media.lua` is measured against exactly these canvases.

unrealUI keeps its own copy rather than reading UnrealQuest's, because the
extended Quest Log has to work in a standalone unrealUI session.
