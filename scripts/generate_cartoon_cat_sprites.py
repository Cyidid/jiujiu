#!/usr/bin/env python3
from __future__ import annotations

from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (360, 392)
S = 4

INK = (48, 42, 46, 255)
FUR = (255, 255, 250, 255)
SHADE = (238, 235, 228, 255)
EAR = (255, 184, 193, 255)
BLUSH = (255, 180, 190, 160)
BLUE = (56, 170, 230, 255)
BLUE_DARK = (30, 70, 105, 255)
PINK = (255, 122, 144, 255)
WHITE = (255, 255, 255, 255)


def sc(v: float) -> int:
    return round(v * S)


def pt(x: float, y: float) -> tuple[int, int]:
    return sc(x), sc(y)


def bx(cx: float, cy: float, w: float, h: float) -> tuple[int, int, int, int]:
    return sc(cx - w / 2), sc(cy - h / 2), sc(cx + w / 2), sc(cy + h / 2)


def rr(draw: ImageDraw.ImageDraw, box, r: float, fill, outline=None, width: float = 1) -> None:
    draw.rounded_rectangle(tuple(sc(v) for v in box), radius=sc(r), fill=fill, outline=outline, width=sc(width))


def ellipse(draw: ImageDraw.ImageDraw, box, fill, outline=None, width: float = 1) -> None:
    draw.ellipse(tuple(sc(v) for v in box), fill=fill, outline=outline, width=sc(width))


def line(draw: ImageDraw.ImageDraw, points, fill, width: float) -> None:
    draw.line([pt(x, y) for x, y in points], fill=fill, width=sc(width), joint="curve")


def draw_shadow(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, alpha: int) -> None:
    ellipse(draw, (x - w / 2, y - 10, x + w / 2, y + 10), (0, 0, 0, alpha))


def draw_tail(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, pose: str) -> None:
    wag = sin(phase * 2 * pi)
    if pose == "sleep":
        pts = [(cx + 48, cy + 63), (cx + 88, cy + 70), (cx + 92, cy + 38), (cx + 56, cy + 39)]
    else:
        pts = [
            (cx + 48, cy + 54),
            (cx + 94, cy + 30 - wag * 10),
            (cx + 78 + wag * 22, cy - 34),
            (cx + 34 + wag * 12, cy - 24),
        ]
    line(draw, pts, INK, 28)
    line(draw, pts, FUR, 19)
    line(draw, pts[1:], SHADE, 4)


def draw_body(draw: ImageDraw.ImageDraw, cx: float, cy: float, jump: float, pose: str) -> None:
    if pose == "sleep":
        ellipse(draw, (cx - 70, cy + 36, cx + 83, cy + 122), FUR, INK, 5)
        return
    ellipse(draw, (cx - 62, cy + 18 + jump, cx + 62, cy + 126 + jump), FUR, INK, 5)
    ellipse(draw, (cx - 42, cy + 57 + jump, cx + 42, cy + 111 + jump), (252, 250, 244, 255))


def draw_ears(draw: ImageDraw.ImageDraw, cx: float, cy: float, tilt: float) -> None:
    left = [pt(cx - 72 + tilt, cy - 33), pt(cx - 53 + tilt, cy - 106), pt(cx - 13 + tilt, cy - 52)]
    right = [pt(cx + 72 + tilt, cy - 33), pt(cx + 53 + tilt, cy - 106), pt(cx + 13 + tilt, cy - 52)]
    draw.polygon(left, fill=INK)
    draw.polygon(right, fill=INK)
    draw.polygon([pt(cx - 59 + tilt, cy - 40), pt(cx - 51 + tilt, cy - 83), pt(cx - 24 + tilt, cy - 51)], fill=EAR)
    draw.polygon([pt(cx + 59 + tilt, cy - 40), pt(cx + 51 + tilt, cy - 83), pt(cx + 24 + tilt, cy - 51)], fill=EAR)


def draw_eye(draw: ImageDraw.ImageDraw, cx: float, cy: float, closed: float, side: int) -> None:
    ex = cx + side * 37
    if closed > 0.7:
        line(draw, [(ex - 17, cy), (ex - 7, cy + 6), (ex + 7, cy + 6), (ex + 17, cy)], INK, 4)
        return
    ellipse(draw, (ex - 20, cy - 23, ex + 20, cy + 25), BLUE_DARK, INK, 3)
    ellipse(draw, (ex - 13, cy - 13, ex + 13, cy + 21), BLUE)
    ellipse(draw, (ex - 11, cy - 18, ex + 1, cy - 6), WHITE)
    ellipse(draw, (ex + 6, cy + 2, ex + 13, cy + 9), (170, 230, 255, 230))


def draw_head(draw: ImageDraw.ImageDraw, cx: float, cy: float, blink: float, mood: str, tilt: float) -> None:
    draw_ears(draw, cx, cy, tilt)
    ellipse(draw, (cx - 88 + tilt, cy - 72, cx + 88 + tilt, cy + 82), FUR, INK, 5)
    ellipse(draw, (cx - 75 + tilt, cy + 10, cx - 39 + tilt, cy + 34), BLUSH)
    ellipse(draw, (cx + 39 + tilt, cy + 10, cx + 75 + tilt, cy + 34), BLUSH)
    draw_eye(draw, cx + tilt, cy - 6, blink, -1)
    draw_eye(draw, cx + tilt, cy - 6, blink, 1)
    if mood == "surprise":
        ellipse(draw, (cx - 9 + tilt, cy + 38, cx + 9 + tilt, cy + 57), (120, 44, 62, 255), INK, 2)
    else:
        draw.polygon([pt(cx - 7 + tilt, cy + 30), pt(cx + 7 + tilt, cy + 30), pt(cx + tilt, cy + 40)], fill=PINK)
        line(draw, [(cx + tilt, cy + 40), (cx - 9 + tilt, cy + 49)], INK, 2)
        line(draw, [(cx + tilt, cy + 40), (cx + 9 + tilt, cy + 49)], INK, 2)
    for side in (-1, 1):
        line(draw, [(cx + side * 18 + tilt, cy + 34), (cx + side * 60 + tilt, cy + 27)], INK, 2)
        line(draw, [(cx + side * 20 + tilt, cy + 43), (cx + side * 62 + tilt, cy + 46)], INK, 2)


def draw_paws(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, jump: float, pose: str) -> None:
    step = sin(phase * 2 * pi)
    if pose == "sleep":
        ellipse(draw, (cx - 52, cy + 89, cx - 18, cy + 118), FUR, INK, 4)
        return
    if pose == "groom":
        ellipse(draw, (cx + 22, cy + 13, cx + 62, cy + 53), FUR, INK, 4)
        ellipse(draw, (cx - 45, cy + 104, cx - 12, cy + 131), FUR, INK, 4)
        ellipse(draw, (cx + 12, cy + 104, cx + 45, cy + 131), FUR, INK, 4)
        return
    front_y = cy + 105 + jump
    lift_l = max(0, step) * 22
    lift_r = max(0, -step) * 22
    ellipse(draw, (cx - 48 - step * 10, front_y - lift_l, cx - 14 - step * 10, front_y + 30 - lift_l), FUR, INK, 4)
    ellipse(draw, (cx + 14 + step * 10, front_y - lift_r, cx + 48 + step * 10, front_y + 30 - lift_r), FUR, INK, 4)
    ellipse(draw, (cx - 76 + step * 7, cy + 113 + jump - lift_r * 0.4, cx - 38 + step * 7, cy + 141 + jump - lift_r * 0.4), FUR, INK, 4)
    ellipse(draw, (cx + 38 - step * 7, cy + 113 + jump - lift_l * 0.4, cx + 76 - step * 7, cy + 141 + jump - lift_l * 0.4), FUR, INK, 4)


def frame(phase=0.0, pose="idle", blink=0.0, jump=0.0, roll=0.0, surprise=False) -> Image.Image:
    img = Image.new("RGBA", (CANVAS[0] * S, CANVAS[1] * S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = 180, 176 - jump
    mood = "surprise" if surprise else pose
    draw_shadow(draw, cx, 326, 150 - jump * 0.35, 45)
    draw_tail(draw, cx, cy, phase, pose)
    draw_body(draw, cx, cy, jump, pose)
    draw_paws(draw, cx, cy, phase, jump, pose)
    draw_head(draw, cx, cy, blink, mood, sin(phase * 2 * pi) * 3)
    if pose == "sleep":
        draw.text(pt(cx + 76, cy - 70), "Z", fill=(120, 150, 190, 210))
    if roll:
        img = img.rotate(roll, resample=Image.Resampling.BICUBIC, center=pt(cx, cy + 20))
    return img.resize(CANVAS, Image.Resampling.LANCZOS).filter(ImageFilter.UnsharpMask(radius=0.5, percent=60, threshold=3))


def save(out: Path, name: str, *args, **kwargs) -> None:
    frame(*args, **kwargs).save(out / name)


def main() -> int:
    out = Path("Resources")
    out.mkdir(parents=True, exist_ok=True)
    save(out, "normal.png")
    for i, b in enumerate([0, 0.8, 1.0, 0]):
        save(out, f"blink{i}.png", blink=b)
    for i in range(8):
        phase = i / 8
        save(out, f"hop{i}.png", phase=phase, jump=max(0, sin(phase * pi)) * 28)
    for i in range(7):
        save(out, f"groom{i}.png", phase=i / 7, pose="groom", blink=0.9 if 1 <= i <= 4 else 0)
    for i in range(2):
        save(out, f"sleep{i}.png", phase=i / 2, pose="sleep", blink=1.0)
    for angle in [45, 90, 135, 180, 225, 270, 315]:
        save(out, f"roll{angle:03d}.png", roll=angle, surprise=True)
    for i in range(5):
        save(out, f"str{i}.png", phase=i / 5, jump=-5 if i in (1, 2) else 0, blink=0.9 if i in (1, 2) else 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
