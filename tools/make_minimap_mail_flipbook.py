"""Repack the user-supplied minimap-mail sprite sheet into unrealUI's flipbook.

The supplied sheet (`media/minimap-mail-flipbook.png`, Blizzard file id
5201351) is 256x512 but is NOT a power-of-two grid: its 32 frames sit on a
52.5 px horizontal and 53 px vertical pitch starting at centre (27, 26), with
about 46 px of empty canvas on the right and 88 px at the bottom. Measured
here, not assumed: every frame's content fits inside a 52x52 window around
those centres, and the alpha immediately outside each window peaks at 11/255,
so nothing is cropped and no frame bleeds into its neighbour.

The frames are re-laid into 64x64 cells with each 52x52 source frame centred.
Pixels are copied 1:1 -- no scaling or recolouring. The production animation
uses the individual files: a focused in-game comparison confirmed that the
same frames travel when selected from the 256x512 atlas with SetTexCoord but
stay fixed when swapped as separate textures.

The clean atlas is written to `media/minimap-mail-flipbook.tga`. The same
64x64 cells are also written individually under
`media/minimap-mail-frames/`; the focused runtime comparison uses those files
to distinguish atlas sampling from motion encoded in the frames.

Output form is the one this client is confirmed to render, the same contract
tools/import_modern_wow_media.py asserts: 32-bit RLE TGA, image type 10,
descriptor 0x08 (knowledge.json / textures.uncompressed_512_tga_atlas_corrupts).
core/media.lua references it without the .tga suffix
(knowledge.json / textures.addon_tga_paths_require_extensionless).

Run from the unrealUI addon folder:

    python -B tools/make_minimap_mail_flipbook.py
"""

import os
import sys

from PIL import Image

SOURCE = os.path.join("media", "minimap-mail-flipbook.png")
DEST = os.path.join("media", "minimap-mail-flipbook.tga")
FRAME_DIR = os.path.join("media", "minimap-mail-frames")

# Measured layout of the supplied sheet.
SRC_CENTRE_X = 27.0
SRC_CENTRE_Y = 26.0
SRC_PITCH_X = 52.5
SRC_PITCH_Y = 53.0
FRAME = 52

# The clean grid written out.
COLUMNS = 4
ROWS = 8
CELL = 64


def write_rle_tga(image, path):
    image = image.convert("RGBA")
    image.save(path, format="TGA", compression="tga_rle")
    with open(path, "rb") as handle:
        header = handle.read(18)
    if (len(header) != 18 or header[2] != 10 or header[16] != 32
            or header[17] != 8):
        raise ValueError(
            "RLE TGA writer did not produce the proven type-10 header: " + path)


def main():
    if not os.path.isfile(SOURCE):
        sys.stderr.write("missing source sheet: %s\n" % SOURCE)
        return 1

    source = Image.open(SOURCE).convert("RGBA")
    atlas = Image.new("RGBA", (COLUMNS * CELL, ROWS * CELL), (0, 0, 0, 0))
    inset = (CELL - FRAME) // 2
    os.makedirs(FRAME_DIR, exist_ok=True)

    for row in range(ROWS):
        for column in range(COLUMNS):
            cx = SRC_CENTRE_X + SRC_PITCH_X * column
            cy = SRC_CENTRE_Y + SRC_PITCH_Y * row
            left = int(round(cx - FRAME / 2.0))
            top = int(round(cy - FRAME / 2.0))
            frame = source.crop((left, top, left + FRAME, top + FRAME))
            cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            cell.paste(frame, (inset, inset))
            atlas.paste(cell, (column * CELL, row * CELL))
            index = row * COLUMNS + column + 1
            write_rle_tga(cell, os.path.join(
                FRAME_DIR, "frame-%02d.tga" % index))

    write_rle_tga(atlas, DEST)
    print("wrote %s (%dx%d) and %d individual frames"
          % (DEST, atlas.size[0], atlas.size[1], COLUMNS * ROWS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
