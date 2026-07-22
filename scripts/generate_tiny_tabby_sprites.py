#!/usr/bin/env python3
from __future__ import annotations

from math import pi, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (360, 392)
S = 4

INK = (55, 49, 48, 255)
FUR = (255, 253, 247, 255)
CREAM = (247, 241, 232, 255)
TABBY = (158, 158, 154, 255)
TABBY_DARK = (106, 106, 104, 255)
EAR = (255, 188, 192, 255)
BLUSH = (255, 178, 184, 145)
EYE = (73, 136, 190, 255)
EYE_DARK = (30, 58, 82, 255)
PINK = (246, 108, 132, 255)
WHITE = (255, 255, 255, 255)


def sc(v: float) -> int:
    return round(v * S)


def pt(x: float, y: float) -> tuple[int, int]:
    return sc(x), sc(y)


def oval(draw: ImageDraw.ImageDraw, x0, y0, x1, y1, fill, outline=INK, width=4) -> None:
    draw.ellipse((sc(x0), sc(y0), sc(x1), sc(y1)), fill=fill, outline=outline, width=sc(width))


def line(draw: ImageDraw.ImageDraw, pts, fill=INK, width=4) -> None:
    draw.line([pt(x, y) for x, y in pts], fill=fill, width=sc(width), joint="curve")


def poly(draw: ImageDraw.ImageDraw, pts, fill, outline=None) -> None:
    draw.polygon([pt(x, y) for x, y in pts], fill=fill)
    if outline:
        draw.line([pt(x, y) for x, y in pts + [pts[0]]], fill=outline, width=sc(4), joint="curve")


def draw_shadow(draw: ImageDraw.ImageDraw, cx: float, cy: float, w: float, jump: float) -> None:
    oval(draw, cx - w / 2, cy - 9, cx + w / 2, cy + 9, (0, 0, 0, max(22, int(48 - jump * 0.6))), outline=None, width=0)


def draw_tail(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, pose: str) -> None:
    wag = sin(phase * 2 * pi)
    if pose == "sleep":
        pts = [(cx + 48, cy + 76), (cx + 88, cy + 78), (cx + 96, cy + 48), (cx + 64, cy + 39)]
    else:
        pts = [
            (cx + 52, cy + 72),
            (cx + 96, cy + 52 - wag * 10),
            (cx + 102 + wag * 18, cy + 5),
            (cx + 70 + wag * 18, cy - 18),
        ]
    line(draw, pts, INK, 25)
    line(draw, pts, FUR, 18)
    for t in (0.35, 0.58, 0.8):
        i = min(len(pts) - 2, int(t * (len(pts) - 1)))
        x = pts[i][0] * (1 - t) + pts[-1][0] * t
        y = pts[i][1] * (1 - t) + pts[-1][1] * t
        line(draw, [(x - 9, y - 6), (x + 8, y + 8)], TABBY_DARK, 3)


def draw_body(draw: ImageDraw.ImageDraw, cx: float, cy: float, jump: float, pose: str) -> None:
    if pose == "sleep":
        oval(draw, cx - 76, cy + 54, cx + 84, cy + 132, FUR, INK, 4)
        oval(draw, cx - 45, cy + 76, cx + 44, cy + 126, CREAM, None, 0)
        return
    oval(draw, cx - 58, cy + 38 + jump, cx + 58, cy + 134 + jump, FUR, INK, 4)
    oval(draw, cx - 36, cy + 70 + jump, cx + 36, cy + 127 + jump, CREAM, None, 0)
    line(draw, [(cx - 43, cy + 64 + jump), (cx - 54, cy + 84 + jump)], TABBY, 3)
    line(draw, [(cx + 43, cy + 64 + jump), (cx + 54, cy + 84 + jump)], TABBY, 3)


def draw_ears(draw: ImageDraw.ImageDraw, cx: float, cy: float, tilt: float) -> None:
    left = [(cx - 72 + tilt, cy - 40), (cx - 49 + tilt, cy - 92), (cx - 18 + tilt, cy - 45)]
    right = [(cx + 72 + tilt, cy - 40), (cx + 49 + tilt, cy - 92), (cx + 18 + tilt, cy - 45)]
    poly(draw, left, FUR, INK)
    poly(draw, right, FUR, INK)
    poly(draw, [(cx - 59 + tilt, cy - 45), (cx - 49 + tilt, cy - 75), (cx - 29 + tilt, cy - 48)], EAR)
    poly(draw, [(cx + 59 + tilt, cy - 45), (cx + 49 + tilt, cy - 75), (cx + 29 + tilt, cy - 48)], EAR)


def draw_tabby_marks(draw: ImageDraw.ImageDraw, cx: float, cy: float, tilt: float) -> None:
    line(draw, [(cx - 20 + tilt, cy - 58), (cx - 13 + tilt, cy - 34), (cx - 5 + tilt, cy - 55)], TABBY_DARK, 3)
    line(draw, [(cx + 20 + tilt, cy - 58), (cx + 13 + tilt, cy - 34), (cx + 5 + tilt, cy - 55)], TABBY_DARK, 3)
    line(draw, [(cx - 6 + tilt, cy - 62), (cx + tilt, cy - 42), (cx + 6 + tilt, cy - 62)], TABBY_DARK, 3)
    line(draw, [(cx - 79 + tilt, cy - 12), (cx - 61 + tilt, cy - 2)], TABBY, 3)
    line(draw, [(cx + 79 + tilt, cy - 12), (cx + 61 + tilt, cy - 2)], TABBY, 3)


def draw_eye(draw: ImageDraw.ImageDraw, cx: float, cy: float, side: int, blink: float) -> None:
    ex = cx + side * 34
    if blink > 0.7:
        line(draw, [(ex - 17, cy + 2), (ex - 6, cy + 7), (ex + 7, cy + 7), (ex + 17, cy + 2)], INK, 4)
        return
    oval(draw, ex - 19, cy - 24, ex + 19, cy + 23, EYE_DARK, INK, 3)
    oval(draw, ex - 12, cy - 12, ex + 12, cy + 19, EYE, None, 0)
    oval(draw, ex - 10, cy - 17, ex + 1, cy - 6, WHITE, None, 0)
    oval(draw, ex + 5, cy + 3, ex + 12, cy + 10, (160, 225, 255, 230), None, 0)


def draw_head(draw: ImageDraw.ImageDraw, cx: float, cy: float, blink: float, surprise: bool, tilt: float) -> None:
    draw_ears(draw, cx, cy, tilt)
    oval(draw, cx - 84 + tilt, cy - 68, cx + 84 + tilt, cy + 82, FUR, INK, 4)
    # soft gray cap
    draw.arc((sc(cx - 72 + tilt), sc(cy - 69), sc(cx + 72 + tilt), sc(cy + 32)), 196, 344, fill=TABBY, width=sc(9))
    draw_tabby_marks(draw, cx, cy, tilt)
    oval(draw, cx - 72 + tilt, cy + 12, cx - 38 + tilt, cy + 36, BLUSH, None, 0)
    oval(draw, cx + 38 + tilt, cy + 12, cx + 72 + tilt, cy + 36, BLUSH, None, 0)
    draw_eye(draw, cx + tilt, cy - 3, -1, blink)
    draw_eye(draw, cx + tilt, cy - 3, 1, blink)
    if surprise:
        oval(draw, cx - 8 + tilt, cy + 39, cx + 8 + tilt, cy + 58, (112, 42, 58, 255), INK, 2)
    else:
        poly(draw, [(cx - 7 + tilt, cy + 30), (cx + 7 + tilt, cy + 30), (cx + tilt, cy + 39)], PINK)
        line(draw, [(cx + tilt, cy + 39), (cx - 8 + tilt, cy + 48)], INK, 2)
        line(draw, [(cx + tilt, cy + 39), (cx + 8 + tilt, cy + 48)], INK, 2)
    for side in (-1, 1):
        line(draw, [(cx + side * 18 + tilt, cy + 35), (cx + side * 59 + tilt, cy + 28)], INK, 2)
        line(draw, [(cx + side * 20 + tilt, cy + 44), (cx + side * 61 + tilt, cy + 48)], INK, 2)


def draw_paws(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, jump: float, pose: str) -> None:
    step = sin(phase * 2 * pi)
    if pose == "sleep":
        oval(draw, cx - 52, cy + 93, cx - 18, cy + 122, FUR, INK, 3)
        return
    if pose == "groom":
        oval(draw, cx + 22, cy + 17, cx + 62, cy + 56, FUR, INK, 3)
        for px in (-34, 18):
            oval(draw, cx + px, cy + 111, cx + px + 34, cy + 139, FUR, INK, 3)
        return
    front_y = cy + 112 + jump
    lift_l = max(0, step) * 18
    lift_r = max(0, -step) * 18
    for x0, lift in [(-43 - step * 9, lift_l), (10 + step * 9, lift_r)]:
        oval(draw, cx + x0, front_y - lift, cx + x0 + 34, front_y + 30 - lift, FUR, INK, 3)
    for x0, lift in [(-75 + step * 7, lift_r * 0.4), (40 - step * 7, lift_l * 0.4)]:
        oval(draw, cx + x0, cy + 122 + jump - lift, cx + x0 + 38, cy + 148 + jump - lift, FUR, INK, 3)


def make_frame(phase=0.0, pose="idle", blink=0.0, jump=0.0, roll=0.0, surprise=False) -> Image.Image:
    img = Image.new("RGBA", (CANVAS[0] * S, CANVAS[1] * S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = 180, 165 - jump
    tilt = sin(phase * 2 * pi) * 2.4
    draw_shadow(draw, cx, 326, 146, jump)
    draw_tail(draw, cx, cy, phase, pose)
    draw_body(draw, cx, cy, jump, pose)
    draw_paws(draw, cx, cy, phase, jump, pose)
    draw_head(draw, cx, cy, blink, surprise, tilt)
    if pose == "sleep":
        draw.text(pt(cx + 72, cy - 67), "Z", fill=(110, 135, 174, 210))
    if roll:
        img = img.rotate(roll, resample=Image.Resampling.BICUBIC, center=pt(cx, cy + 28))
    return img.resize(CANVAS, Image.Resampling.LANCZOS).filter(ImageFilter.UnsharpMask(radius=0.45, percent=50, threshold=3))


def save(out: Path, name: str, **kwargs) -> None:
    make_frame(**kwargs).save(out / name)


def main() -> int:
    out = Path("additional/Applications/啾啾.app/Contents/Resources")
    out.mkdir(parents=True, exist_ok=True)
    save(out, "normal.png")
    for i, blink in enumerate([0, 0.75, 1, 0]):
        save(out, f"blink{i}.png", blink=blink)
    for i in range(8):
        phase = i / 8
        save(out, f"hop{i}.png", phase=phase, jump=max(0, sin(phase * pi)) * 24)
    for i in range(7):
        save(out, f"groom{i}.png", phase=i / 7, pose="groom", blink=0.9 if 1 <= i <= 4 else 0)
    for i in range(2):
        save(out, f"sleep{i}.png", phase=i / 2, pose="sleep", blink=1)
    for angle in [45, 90, 135, 180, 225, 270, 315]:
        save(out, f"roll{angle:03d}.png", roll=angle, surprise=True)
    for i in range(5):
        save(out, f"str{i}.png", phase=i / 5, jump=-4 if i in (1, 2) else 0, blink=0.9 if i in (1, 2) else 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
