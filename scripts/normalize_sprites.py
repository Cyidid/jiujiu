#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
import sys

CANVAS = (360, 392)
BOTTOM_PADDING = 18


def normalize_image(src: Path, dst: Path) -> None:
    image = Image.open(src).convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        image.save(dst)
        return

    cropped = image.crop(bbox)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - cropped.width) // 2
    y = CANVAS[1] - cropped.height - BOTTOM_PADDING
    canvas.alpha_composite(cropped, (x, max(0, y)))
    canvas.save(dst)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: normalize_sprites.py <src-dir> <dst-dir>", file=sys.stderr)
        return 2

    src_dir = Path(sys.argv[1])
    dst_dir = Path(sys.argv[2])
    dst_dir.mkdir(parents=True, exist_ok=True)

    for png in sorted(src_dir.glob("*.png")):
        normalize_image(png, dst_dir / png.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
