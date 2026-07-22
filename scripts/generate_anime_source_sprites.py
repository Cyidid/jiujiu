#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from math import sin, pi
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

CANVAS = (360, 392)
SOURCE = Path("assets/source/chi-anime-source.png")
OUT = Path("additional/Applications/啾啾.app/Contents/Resources")


def is_border_background(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, _ = pixel
    return abs(r - g) <= 3 and abs(g - b) <= 3 and r >= 222


def make_transparent_source() -> Image.Image:
    source = Image.open(SOURCE).convert("RGBA")
    w, h = source.size
    pix = source.load()
    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if is_border_background(pix[x, y]):
                q.append((x, y))
                seen[y * w + x] = 1
    for y in range(h):
        for x in (0, w - 1):
            if is_border_background(pix[x, y]) and not seen[y * w + x]:
                q.append((x, y))
                seen[y * w + x] = 1

    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            idx = ny * w + nx
            if seen[idx] or not is_border_background(pix[nx, ny]):
                continue
            seen[idx] = 1
            q.append((nx, ny))

    alpha = Image.new("L", (w, h), 255)
    alpha_pix = alpha.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if seen[row + x]:
                alpha_pix[x, y] = 0

    alpha = alpha.filter(ImageFilter.GaussianBlur(0.45))
    source.putalpha(alpha)
    bbox = source.getbbox()
    if bbox:
        source = source.crop(bbox)
    return source


def fit_to_canvas(img: Image.Image, y_offset: int = 2, scale_boost: float = 1.0) -> Image.Image:
    max_w, max_h = 326, 354
    scale = min(max_w / img.width, max_h / img.height) * scale_boost
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - resized.width) // 2
    y = CANVAS[1] - resized.height - 24 + y_offset
    canvas.alpha_composite(resized, (x, y))
    return canvas


def shadow() -> Image.Image:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((88, 343, 282, 370), fill=(0, 0, 0, 34))
    return layer.filter(ImageFilter.GaussianBlur(3.8))


def transform_pose(base: Image.Image, *, angle: float = 0, dx: int = 0, dy: int = 0, squash: float = 1.0) -> Image.Image:
    w, h = CANVAS
    posed = base
    if squash != 1.0:
        posed = posed.resize((w, round(h * squash)), Image.Resampling.BICUBIC)
        tmp = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        tmp.alpha_composite(posed, (0, h - posed.height))
        posed = tmp
    if angle:
        posed = posed.rotate(angle, resample=Image.Resampling.BICUBIC, center=(180, 242))
    if dx or dy:
        shifted = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        shifted.alpha_composite(posed, (dx, dy))
        posed = shifted
    return posed


def draw_blink(frame: Image.Image, amount: float) -> Image.Image:
    if amount <= 0:
        return frame
    out = frame.copy()
    d = ImageDraw.Draw(out)
    ink = (55, 55, 55, 230)
    fur = (247, 248, 246, 235)
    # Coordinates are tuned for the selected anime source after normalization.
    left = [(89, 145), (115, 134), (143, 143), (142, 155), (115, 164), (88, 156)]
    right = [(201, 126), (226, 116), (251, 124), (252, 136), (228, 144), (201, 137)]
    if amount > 0.55:
        d.polygon(left, fill=fur)
        d.polygon(right, fill=fur)
        d.line([(92, 151), (116, 158), (141, 151)], fill=ink, width=4)
        d.line([(204, 132), (228, 138), (250, 131)], fill=ink, width=4)
    return out


def compose(pet: Image.Image) -> Image.Image:
    out = shadow()
    out.alpha_composite(pet)
    return out


def save(name: str, img: Image.Image) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)


def main() -> int:
    source = make_transparent_source()
    base = fit_to_canvas(source)
    save("normal.png", compose(base))

    for i, amount in enumerate([0, 0.8, 1.0, 0]):
        save(f"blink{i}.png", compose(draw_blink(base, amount)))

    for i in range(8):
        phase = i / 8
        bob = round(-sin(phase * pi) * 22)
        angle = sin(phase * 2 * pi) * 3.2
        squash = 0.985 if i in (0, 7) else 1.0
        save(f"hop{i}.png", compose(transform_pose(base, angle=angle, dy=bob, squash=squash)))

    for i in range(7):
        phase = i / 7
        angle = -5.5 + sin(phase * 2 * pi) * 6
        dy = round(sin(phase * pi) * 4)
        frame = transform_pose(base, angle=angle, dx=round(sin(phase * 2 * pi) * 4), dy=dy)
        save(f"groom{i}.png", compose(draw_blink(frame, 0.9 if 2 <= i <= 4 else 0)))

    sleep = transform_pose(base, angle=-92, dx=-8, dy=58, squash=0.96)
    for i in range(2):
        save(f"sleep{i}.png", compose(draw_blink(sleep, 1.0)))

    for angle in [45, 90, 135, 180, 225, 270, 315]:
        save(f"roll{angle:03d}.png", compose(transform_pose(base, angle=angle)))

    for i in range(5):
        phase = i / 5
        frame = transform_pose(base, angle=sin(phase * 2 * pi) * 5, dx=round(sin(phase * 2 * pi) * 8))
        save(f"str{i}.png", compose(draw_blink(frame, 0.8 if i in (1, 2) else 0)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
