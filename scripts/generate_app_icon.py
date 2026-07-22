#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
SOURCE = RESOURCES / "normal.png"
ICONSET = ROOT / "build/AppIcon.iconset"
OUT_PNG = ROOT / "build/AppIcon-1024.png"


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def gradient_background(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pix = img.load()
    top = (117, 210, 244)
    mid = (250, 254, 255)
    bottom = (255, 220, 214)
    for y in range(size):
        t = y / (size - 1)
        if t < 0.56:
            k = t / 0.56
            a, b = top, mid
        else:
            k = (t - 0.56) / 0.44
            a, b = mid, bottom
        for x in range(size):
            vignette = ((x - size / 2) ** 2 + (y - size / 2) ** 2) ** 0.5 / (size * 0.72)
            shade = max(0.0, min(1.0, vignette)) * 9
            pix[x, y] = tuple(max(0, min(255, round(a[i] * (1 - k) + b[i] * k - shade))) for i in range(3)) + (255,)
    return img


def soft_shape_layer(size: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((116, 674, 908, 1018), fill=(255, 255, 255, 72))
    d.ellipse((96, 710, 928, 990), fill=(78, 93, 99, 34))
    d.rounded_rectangle((86, 84, 938, 938), radius=190, outline=(255, 255, 255, 120), width=10)
    return layer.filter(ImageFilter.GaussianBlur(1.2))


def extract_pet() -> Image.Image:
    pet = Image.open(SOURCE).convert("RGBA")
    bbox = pet.getbbox()
    if bbox:
        pet = pet.crop(bbox)
    return pet


def icon_png() -> Image.Image:
    size = 1024
    base = gradient_background(size)
    base.alpha_composite(soft_shape_layer(size))

    pet = extract_pet()
    scale = min(780 / pet.width, 890 / pet.height)
    pet = pet.resize((round(pet.width * scale), round(pet.height * scale)), Image.Resampling.LANCZOS)
    x = (size - pet.width) // 2 - 8
    y = size - pet.height - 40

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    alpha = pet.getchannel("A").filter(ImageFilter.GaussianBlur(14))
    shadow_piece = Image.new("RGBA", pet.size, (35, 40, 45, 98))
    shadow_piece.putalpha(alpha.point(lambda v: round(v * 0.36)))
    shadow.alpha_composite(shadow_piece, (x + 22, y + 30))
    base.alpha_composite(shadow)
    base.alpha_composite(pet, (x, y))

    d = ImageDraw.Draw(base)
    d.ellipse((690, 112, 804, 226), fill=(255, 248, 160, 210))
    d.ellipse((722, 144, 772, 194), fill=(255, 255, 238, 190))
    d.ellipse((142, 132, 184, 174), fill=(255, 255, 255, 126))
    d.ellipse((198, 110, 226, 138), fill=(255, 255, 255, 106))
    d.ellipse((238, 148, 266, 176), fill=(255, 255, 255, 96))

    mask = rounded_rect_mask(size, 216)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(base)
    out.putalpha(mask)
    return out


def write_iconset(icon: Image.Image) -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for px, name in sizes:
        icon.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / name)


def main() -> int:
    icon = icon_png()
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT_PNG)
    write_iconset(icon)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
