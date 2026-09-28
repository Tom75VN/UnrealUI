"""Import Retail full-screen warning art in the client-supported TGA form."""

import os
from pathlib import Path

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = Path(os.environ.get(
    "UNREALUI_RETAIL_TEXTURES",
    r"D:\Development\unrealUI_data\retail-ui-textures-live",
))
DEST_ROOT = ADDON_ROOT / "media" / "Textures" / "fullscreen"

IMPORTS = (
    ("FullScreenTextures/LowHealth.PNG", "low-health.tga"),
    ("FullScreenTextures/OutOfControl.PNG", "out-of-control.tga"),
)


def encode(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="TGA", compression="tga_rle")

    header = destination.read_bytes()[:18]
    if (len(header) != 18 or header[2] != 10 or header[16] != 32
            or header[17] != 8):
        raise RuntimeError(f"unexpected TGA encoding: {destination}")

    decoded = Image.open(destination).convert("RGBA")
    if decoded.size != image.size or decoded.tobytes() != image.tobytes():
        raise RuntimeError(f"pixel verification failed: {destination}")


def main() -> None:
    for source_name, destination_name in IMPORTS:
        source = SOURCE_ROOT / source_name
        if not source.is_file():
            raise FileNotFoundError(source)
        destination = DEST_ROOT / destination_name
        encode(source, destination)
        print(f"imported {source} -> {destination}")


if __name__ == "__main__":
    main()
