#!/usr/bin/env python3
"""Export GitRelay AppIcon PNGs from the committed source artwork.

The source must be a 1024×1024 full-bleed square with opaque charcoal to every
edge. Do not bake in a squircle plate or rim — macOS applies its own icon mask.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

SOURCE_PATH = Path("scripts/assets/gitrelay-status-first-01.png")
ASSET_PATH = Path("gitrelay/Assets.xcassets/AppIcon.appiconset")

SIZES = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024),
]


def resize_icon(source: Image.Image, pixels: int) -> Image.Image:
    if source.size != (pixels, pixels):
        return source.resize((pixels, pixels), Image.Resampling.LANCZOS)
    return source


def main() -> None:
    if not SOURCE_PATH.is_file():
        print(f"error: source artwork not found at {SOURCE_PATH}", file=sys.stderr)
        sys.exit(1)

    source = Image.open(SOURCE_PATH).convert("RGBA")
    if source.size != (1024, 1024):
        print(
            f"warning: expected 1024×1024 source, got {source.size[0]}×{source.size[1]}",
            file=sys.stderr,
        )

    ASSET_PATH.mkdir(parents=True, exist_ok=True)
    for filename, px in SIZES:
        out = ASSET_PATH / filename
        resize_icon(source, px).save(out, format="PNG")
        print(f"  {filename:<20} {px}x{px}  {out.stat().st_size:,} bytes")

    print(f"\nWrote {len(SIZES)} icon PNGs to {ASSET_PATH}")


if __name__ == "__main__":
    main()
