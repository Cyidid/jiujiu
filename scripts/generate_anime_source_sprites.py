#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (360, 392)
OUT = Path("Resources")
SOURCES = {
    "front": Path("assets/source/multiview/sit-front.png"),
    "round": Path("assets/source/multiview/sit-round.png"),
    "side": Path("assets/source/multiview/vhv-side.png"),
    "walk": Path("assets/source/multiview/pngwing-turn.png"),
    "play": Path("assets/source/multiview/play-lie.png"),
    "cute": Path("assets/source/multiview/sit-cute.png"),
}


def is_checker_background(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    if a < 245:
        return True
    return abs(r - g) <= 4 and abs(g - b) <= 4 and r >= 220


def transparent_crop(path: Path) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    w, h = source.size
    pix = source.load()
    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if is_checker_background(pix[x, y]):
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            idx = y * w + x
            if not seen[idx] and is_checker_background(pix[x, y]):
                seen[idx] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            idx = ny * w + nx
            if seen[idx] or not is_checker_background(pix[nx, ny]):
                continue
            seen[idx] = 1
            q.append((nx, ny))

    alpha = Image.new("L", source.size, 255)
    apix = alpha.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if seen[row + x]:
                apix[x, y] = 0
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.45))
    source.putalpha(alpha)
    bbox = source.getbbox()
    return source.crop(bbox) if bbox else source


def fit(img: Image.Image, max_w: int, max_h: int, bottom: int, x_offset: int = 0) -> Image.Image:
    scale = min(max_w / img.width, max_h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - img.width) // 2 + x_offset
    y = CANVAS[1] - img.height - bottom
    canvas.alpha_composite(img, (x, y))
    return canvas


def affine(img: Image.Image, *, angle: float = 0, dx: int = 0, dy: int = 0,
           sx: float = 1.0, sy: float = 1.0) -> Image.Image:
    base = img
    if sx != 1.0 or sy != 1.0:
        resized = base.resize((round(CANVAS[0] * sx), round(CANVAS[1] * sy)), Image.Resampling.BICUBIC)
        tmp = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        tmp.alpha_composite(resized, ((CANVAS[0] - resized.width) // 2, CANVAS[1] - resized.height))
        base = tmp
    if angle:
        base = base.rotate(angle, resample=Image.Resampling.BICUBIC, center=(180, 246))
    if dx or dy:
        tmp = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        tmp.alpha_composite(base, (dx, dy))
        base = tmp
    return base


def cast_shadow(width: int, height: int, y: int, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0 = (CANVAS[0] - width) // 2
    d.ellipse((x0, y, x0 + width, y + height), fill=(27, 26, 23, alpha))
    return layer.filter(ImageFilter.GaussianBlur(4.5))


def depth_rim(img: Image.Image) -> Image.Image:
    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(1.2))
    rim = Image.new("RGBA", CANVAS, (45, 42, 36, 30))
    rim.putalpha(alpha.point(lambda v: min(44, round(v * 0.18))))
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(rim, (3, 5))
    out.alpha_composite(img)
    return out


def compose(pet: Image.Image, lift: float = 0.0, side: bool = False) -> Image.Image:
    shadow_w = 176 if not side else 224
    shadow_h = 26 if not side else 23
    shadow_y = round(348 + lift * 0.23)
    shadow_alpha = max(20, round(42 - abs(lift) * 0.65))
    out = cast_shadow(shadow_w, shadow_h, shadow_y, shadow_alpha)
    out.alpha_composite(depth_rim(pet))
    return out


def draw_blink(frame: Image.Image, amount: float) -> Image.Image:
    if amount <= 0:
        return frame
    out = frame.copy()
    d = ImageDraw.Draw(out)
    fur = (246, 247, 245, 238)
    ink = (48, 48, 48, 230)
    left = [(89, 145), (115, 134), (143, 143), (142, 155), (115, 164), (88, 156)]
    right = [(201, 126), (226, 116), (251, 124), (252, 136), (228, 144), (201, 137)]
    if amount > 0.55:
        d.polygon(left, fill=fur)
        d.polygon(right, fill=fur)
        d.line([(92, 151), (116, 158), (141, 151)], fill=ink, width=4)
        d.line([(204, 132), (228, 138), (250, 131)], fill=ink, width=4)
    return out


def save(name: str, img: Image.Image) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)


def main() -> int:
    src = {key: transparent_crop(path) for key, path in SOURCES.items()}
    front = fit(src["front"], 322, 350, 24)
    round_pose = fit(src["round"], 286, 328, 26)
    side = fit(src["side"], 326, 238, 44)
    walk = fit(src["walk"], 326, 250, 42)
    play = fit(src["play"], 238, 240, 62)
    cute = fit(src["cute"], 260, 318, 28)

    save("normal.png", compose(front))
    for i, amount in enumerate([0, 0.75, 1.0, 0]):
        save(f"blink{i}.png", compose(draw_blink(front, amount)))

    for i in range(8):
        phase = i / 8
        lift = -sin(phase * pi) * 28
        lean = sin(phase * 2 * pi) * 4.5
        dx = round(cos(phase * 2 * pi) * 10)
        pose = walk if i not in (0, 4) else round_pose
        save(f"hop{i}.png", compose(affine(pose, angle=lean, dx=dx, dy=round(lift), sx=1.0 + sin(phase * pi) * 0.025), lift, side=i not in (0, 4)))

    for i in range(7):
        phase = i / 7
        lift = -sin(phase * pi) * 7
        angle = sin(phase * 2 * pi) * 6
        pose = cute if i in (0, 6) else play
        save(f"groom{i}.png", compose(affine(pose, angle=angle, dy=round(lift), sx=1.0 + 0.025 * sin(phase * pi))))

    for i in range(2):
        breathe = 1.0 + (0.018 if i == 1 else 0)
        save(f"sleep{i}.png", compose(affine(play, sy=breathe, dx=-6, dy=34), side=True))

    for n, angle in enumerate([45, 90, 135, 180, 225, 270, 315]):
        pose = side if n % 2 == 0 else play
        save(f"roll{angle:03d}.png", compose(affine(pose, angle=angle, dx=round(sin(n) * 8), dy=round(cos(n) * 7)), side=True))

    for i in range(5):
        phase = i / 5
        pose = walk if i in (1, 2, 3) else front
        save(f"str{i}.png", compose(affine(pose, angle=sin(phase * 2 * pi) * 5, dx=round(sin(phase * 2 * pi) * 12), sy=1.0 + 0.018 * sin(phase * pi)), side=i in (1, 2, 3)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
