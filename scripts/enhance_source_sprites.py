#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageFilter
import sys

CANVAS = (360, 392)
BOTTOM_PADDING = 22
SHADOW_OFFSET = (4, 5)


def fit_to_canvas(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return Image.new("RGBA", CANVAS, (0, 0, 0, 0))

    cropped = image.crop(bbox)
    max_w = CANVAS[0] - 28
    max_h = CANVAS[1] - 38
    if cropped.width > max_w or cropped.height > max_h:
        scale = min(max_w / cropped.width, max_h / cropped.height)
        cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)), Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - cropped.width) // 2
    y = CANVAS[1] - cropped.height - BOTTOM_PADDING
    canvas.alpha_composite(cropped, (x, max(0, y)))
    return canvas


def add_depth(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")

    cast = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_alpha = alpha.filter(ImageFilter.GaussianBlur(1.2)).point(lambda p: min(58, int(p * 0.24)))
    shadow = Image.new("RGBA", CANVAS, (34, 30, 30, 0))
    shadow.putalpha(shadow_alpha)
    cast.alpha_composite(shadow, SHADOW_OFFSET)

    rim_alpha = alpha.filter(ImageFilter.GaussianBlur(0.6)).point(lambda p: min(30, int(p * 0.10)))
    rim = Image.new("RGBA", CANVAS, (255, 255, 255, 0))
    rim.putalpha(rim_alpha)
    cast.alpha_composite(rim, (-2, -2))

    cast.alpha_composite(image)
    return cast


def enhance(path: Path) -> None:
    fitted = fit_to_canvas(Image.open(path))
    add_depth(fitted).save(path)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: enhance_source_sprites.py <resource-dir>", file=sys.stderr)
        return 2

    resource_dir = Path(sys.argv[1])
    for png in sorted(resource_dir.glob("*.png")):
        enhance(png)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
