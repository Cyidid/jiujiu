#!/usr/bin/env python3
from __future__ import annotations

from math import pi, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (360, 392)
S = 4

INK = (44, 41, 40, 255)
FUR = (255, 254, 248, 255)
CREAM = (250, 244, 233, 255)
TABBY = (138, 141, 140, 255)
TABBY_DARK = (87, 91, 92, 255)
EAR = (255, 188, 190, 255)
BLUSH = (255, 185, 190, 135)
EYE = (28, 30, 32, 255)
EYE_DARK = (18, 20, 22, 255)
PINK = (238, 105, 132, 255)
WHITE = (255, 255, 255, 255)


def sc(v: float) -> int:
    return round(v * S)


def pt(x: float, y: float) -> tuple[int, int]:
    return sc(x), sc(y)


def oval(d: ImageDraw.ImageDraw, x0, y0, x1, y1, fill, outline=INK, width=3) -> None:
    d.ellipse((sc(x0), sc(y0), sc(x1), sc(y1)), fill=fill, outline=outline, width=sc(width) if outline else 0)


def line(d: ImageDraw.ImageDraw, pts, fill=INK, width=3) -> None:
    d.line([pt(x, y) for x, y in pts], fill=fill, width=sc(width), joint="curve")


def poly(d: ImageDraw.ImageDraw, pts, fill, outline=INK, width=3) -> None:
    d.polygon([pt(x, y) for x, y in pts], fill=fill)
    if outline:
        line(d, pts + [pts[0]], outline, width)


def draw_tail(d: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, pose: str) -> None:
    wag = sin(phase * 2 * pi)
    if pose == "sleep":
        pts = [(cx + 35, cy + 84), (cx + 71, cy + 91), (cx + 82, cy + 62), (cx + 54, cy + 45)]
    else:
        pts = [(cx + 42, cy + 78), (cx + 76, cy + 63 - wag * 6), (cx + 82 + wag * 12, cy + 28), (cx + 55 + wag * 12, cy + 7)]
    line(d, pts, INK, 22)
    line(d, pts, FUR, 15)
    for px, py in pts[1:]:
        line(d, [(px - 8, py - 5), (px + 8, py + 6)], TABBY_DARK, 3)


def draw_body(d: ImageDraw.ImageDraw, cx: float, cy: float, jump: float, pose: str) -> None:
    if pose == "sleep":
        oval(d, cx - 66, cy + 74, cx + 76, cy + 133, FUR, INK, 3)
        oval(d, cx - 32, cy + 89, cx + 37, cy + 126, CREAM, None)
        return
    oval(d, cx - 48, cy + 54 + jump, cx + 48, cy + 135 + jump, FUR, INK, 3)
    oval(d, cx - 27, cy + 83 + jump, cx + 27, cy + 128 + jump, CREAM, None)


def draw_ears(d: ImageDraw.ImageDraw, cx: float, cy: float) -> None:
    poly(d, [(cx - 67, cy - 35), (cx - 51, cy - 82), (cx - 22, cy - 43)], FUR)
    poly(d, [(cx + 67, cy - 35), (cx + 51, cy - 82), (cx + 22, cy - 43)], FUR)
    poly(d, [(cx - 56, cy - 41), (cx - 49, cy - 69), (cx - 31, cy - 45)], EAR, None)
    poly(d, [(cx + 56, cy - 41), (cx + 49, cy - 69), (cx + 31, cy - 45)], EAR, None)


def draw_chi_marks(d: ImageDraw.ImageDraw, cx: float, cy: float) -> None:
    # soft tabby cap and the recognizable kitten forehead rhythm, but kept as original vector drawing.
    d.pieslice((sc(cx - 76), sc(cy - 76), sc(cx + 76), sc(cy + 46)), 190, 350, fill=TABBY)
    line(d, [(cx - 27, cy - 62), (cx - 18, cy - 31), (cx - 7, cy - 60)], TABBY_DARK, 4)
    line(d, [(cx + 27, cy - 62), (cx + 18, cy - 31), (cx + 7, cy - 60)], TABBY_DARK, 4)
    line(d, [(cx - 8, cy - 66), (cx, cy - 34), (cx + 8, cy - 66)], TABBY_DARK, 4)
    line(d, [(cx - 79, cy - 13), (cx - 55, cy - 6)], TABBY_DARK, 3)
    line(d, [(cx + 79, cy - 13), (cx + 55, cy - 6)], TABBY_DARK, 3)


def draw_eye(d: ImageDraw.ImageDraw, cx: float, cy: float, side: int, blink: float) -> None:
    ex = cx + side * 31
    if blink > 0.65:
        line(d, [(ex - 15, cy + 1), (ex - 5, cy + 6), (ex + 6, cy + 6), (ex + 15, cy + 1)], INK, 3)
        return
    oval(d, ex - 23, cy - 25, ex + 23, cy + 25, EYE_DARK, None)
    oval(d, ex - 20, cy - 22, ex + 20, cy + 22, EYE, None)
    oval(d, ex - 13, cy - 17, ex - 2, cy - 6, WHITE, None)


def draw_head(d: ImageDraw.ImageDraw, cx: float, cy: float, blink: float, surprise: bool) -> None:
    draw_ears(d, cx, cy)
    oval(d, cx - 79, cy - 63, cx + 79, cy + 82, FUR, INK, 3)
    draw_chi_marks(d, cx, cy)
    oval(d, cx - 68, cy + 12, cx - 38, cy + 35, BLUSH, None)
    oval(d, cx + 38, cy + 12, cx + 68, cy + 35, BLUSH, None)
    draw_eye(d, cx, cy - 3, -1, blink)
    draw_eye(d, cx, cy - 3, 1, blink)
    if surprise:
        oval(d, cx - 7, cy + 39, cx + 7, cy + 57, (105, 44, 56, 255), INK, 2)
    else:
        poly(d, [(cx - 6, cy + 30), (cx + 6, cy + 30), (cx, cy + 38)], PINK, None)
        line(d, [(cx, cy + 38), (cx - 7, cy + 47)], INK, 2)
        line(d, [(cx, cy + 38), (cx + 7, cy + 47)], INK, 2)
    for side in (-1, 1):
        line(d, [(cx + side * 16, cy + 36), (cx + side * 56, cy + 29)], INK, 1.7)
        line(d, [(cx + side * 18, cy + 44), (cx + side * 58, cy + 47)], INK, 1.7)


def draw_paws(d: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, jump: float, pose: str) -> None:
    step = sin(phase * 2 * pi)
    if pose == "sleep":
        oval(d, cx - 49, cy + 100, cx - 19, cy + 125, FUR, INK, 2)
        return
    if pose == "groom":
        oval(d, cx + 18, cy + 26, cx + 54, cy + 62, FUR, INK, 2)
        oval(d, cx - 31, cy + 121, cx - 5, cy + 143, FUR, INK, 2)
        oval(d, cx + 8, cy + 121, cx + 34, cy + 143, FUR, INK, 2)
        return
    y = cy + 125 + jump
    lift_l = max(0, step) * 16
    lift_r = max(0, -step) * 16
    oval(d, cx - 42 - step * 8, y - lift_l, cx - 14 - step * 8, y + 24 - lift_l, FUR, INK, 2)
    oval(d, cx + 14 + step * 8, y - lift_r, cx + 42 + step * 8, y + 24 - lift_r, FUR, INK, 2)
    oval(d, cx - 66 + step * 5, cy + 132 + jump - lift_r * 0.35, cx - 34 + step * 5, cy + 154 + jump - lift_r * 0.35, FUR, INK, 2)
    oval(d, cx + 34 - step * 5, cy + 132 + jump - lift_l * 0.35, cx + 66 - step * 5, cy + 154 + jump - lift_l * 0.35, FUR, INK, 2)


def make_frame(phase=0.0, pose="idle", blink=0.0, jump=0.0, roll=0.0, surprise=False) -> Image.Image:
    img = Image.new("RGBA", (CANVAS[0] * S, CANVAS[1] * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 180, 152 - jump
    oval(d, cx - 70, 319 - jump * 0.15, cx + 70, 337 - jump * 0.15, (0, 0, 0, 34), None)
    draw_tail(d, cx, cy, phase, pose)
    draw_body(d, cx, cy, jump, pose)
    draw_paws(d, cx, cy, phase, jump, pose)
    draw_head(d, cx, cy, blink, surprise)
    if pose == "sleep":
        d.text(pt(cx + 65, cy - 58), "Z", fill=(105, 126, 166, 210))
    if roll:
        img = img.rotate(roll, resample=Image.Resampling.BICUBIC, center=pt(cx, cy + 46))
    return img.resize(CANVAS, Image.Resampling.LANCZOS).filter(ImageFilter.UnsharpMask(radius=0.45, percent=45, threshold=3))


def save(out: Path, name: str, **kwargs) -> None:
    make_frame(**kwargs).save(out / name)


def main() -> int:
    out = Path("Resources")
    out.mkdir(parents=True, exist_ok=True)
    save(out, "normal.png")
    for i, blink in enumerate([0, 0.75, 1, 0]):
        save(out, f"blink{i}.png", blink=blink)
    for i in range(8):
        phase = i / 8
        save(out, f"hop{i}.png", phase=phase, jump=max(0, sin(phase * pi)) * 22)
    for i in range(7):
        save(out, f"groom{i}.png", phase=i / 7, pose="groom", blink=0.9 if 1 <= i <= 4 else 0)
    for i in range(2):
        save(out, f"sleep{i}.png", phase=i / 2, pose="sleep", blink=1)
    for angle in [45, 90, 135, 180, 225, 270, 315]:
        save(out, f"roll{angle:03d}.png", roll=angle, surprise=True)
    for i in range(5):
        save(out, f"str{i}.png", phase=i / 5, jump=-3 if i in (1, 2) else 0, blink=0.9 if i in (1, 2) else 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
