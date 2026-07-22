#!/usr/bin/env python3
from __future__ import annotations

from math import cos, pi, sin
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (360, 392)
SCALE = 3

FUR = (252, 252, 248, 255)
FUR_SHADE = (235, 232, 224, 255)
OUTLINE = (42, 39, 38, 255)
PINK = (248, 183, 186, 255)
BLUE = (116, 196, 232, 255)
BLUE_DARK = (34, 68, 95, 255)
BLACK = (21, 22, 25, 255)
WHITE = (255, 255, 255, 255)


def s(value: float) -> int:
    return round(value * SCALE)


def point(x: float, y: float) -> tuple[int, int]:
    return (s(x), s(y))


def box(cx: float, cy: float, w: float, h: float) -> tuple[int, int, int, int]:
    return (s(cx - w / 2), s(cy - h / 2), s(cx + w / 2), s(cy + h / 2))


def draw_line(draw: ImageDraw.ImageDraw, pts: Iterable[tuple[float, float]], fill, width: float) -> None:
    draw.line([point(x, y) for x, y in pts], fill=fill, width=s(width), joint="curve")


def draw_tail(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, lift: float) -> None:
    base = (cx + 88, cy + 53)
    wave = sin(phase * 2 * pi)
    pts = [
        base,
        (cx + 124, cy + 34 - lift * 0.4),
        (cx + 138 + wave * 12, cy - 4 - lift),
        (cx + 105 + wave * 22, cy - 35 - lift * 0.6),
    ]
    draw_line(draw, pts, OUTLINE, 24)
    draw_line(draw, pts, FUR, 16)
    draw_line(draw, pts[1:], FUR_SHADE, 3)


def draw_body(draw: ImageDraw.ImageDraw, cx: float, cy: float, squash: float, stretch: float) -> None:
    draw.ellipse(box(cx, cy + 50, 172 + stretch, 142 - squash), fill=OUTLINE)
    draw.ellipse(box(cx, cy + 48, 158 + stretch, 128 - squash), fill=FUR)
    draw.arc(box(cx - 2, cy + 54, 96, 68), 0, 180, fill=FUR_SHADE, width=s(3))


def draw_head(draw: ImageDraw.ImageDraw, cx: float, cy: float, blink: float, tilt: float) -> None:
    ear_l = [point(cx - 86 + tilt, cy - 36), point(cx - 54, cy - 112), point(cx - 24, cy - 34)]
    ear_r = [point(cx + 86 + tilt, cy - 36), point(cx + 54, cy - 112), point(cx + 24, cy - 34)]
    draw.polygon(ear_l, fill=OUTLINE)
    draw.polygon(ear_r, fill=OUTLINE)
    draw.polygon([point(cx - 70 + tilt, cy - 43), point(cx - 53, cy - 92), point(cx - 31, cy - 40)], fill=PINK)
    draw.polygon([point(cx + 70 + tilt, cy - 43), point(cx + 53, cy - 92), point(cx + 31, cy - 40)], fill=PINK)

    draw.ellipse(box(cx + tilt, cy - 8, 182, 150), fill=OUTLINE)
    draw.ellipse(box(cx + tilt, cy - 9, 166, 136), fill=FUR)

    draw.ellipse(box(cx - 42 + tilt, cy - 12, 36, 44), fill=BLUE_DARK)
    draw.ellipse(box(cx + 42 + tilt, cy - 12, 36, 44), fill=BLUE_DARK)
    if blink > 0.65:
        draw.rounded_rectangle((s(cx - 63 + tilt), s(cy - 16), s(cx - 22 + tilt), s(cy - 8)), radius=s(4), fill=OUTLINE)
        draw.rounded_rectangle((s(cx + 22 + tilt), s(cy - 16), s(cx + 63 + tilt), s(cy - 8)), radius=s(4), fill=OUTLINE)
    else:
        eye_h = 44 * (1 - blink * 0.75)
        draw.ellipse(box(cx - 42 + tilt, cy - 12, 32, eye_h), fill=BLACK)
        draw.ellipse(box(cx + 42 + tilt, cy - 12, 32, eye_h), fill=BLACK)
        draw.ellipse(box(cx - 49 + tilt, cy - 23, 8, 10), fill=WHITE)
        draw.ellipse(box(cx + 35 + tilt, cy - 23, 8, 10), fill=WHITE)
        draw.ellipse(box(cx - 42 + tilt, cy + 14, 24, 10), fill=BLUE)
        draw.ellipse(box(cx + 42 + tilt, cy + 14, 24, 10), fill=BLUE)

    draw.polygon([point(cx - 7 + tilt, cy + 27), point(cx + 7 + tilt, cy + 27), point(cx + tilt, cy + 37)], fill=PINK)
    draw.arc(box(cx - 9 + tilt, cy + 38, 18, 13), 10, 170, fill=OUTLINE, width=s(2))
    draw.arc(box(cx + 9 + tilt, cy + 38, 18, 13), 10, 170, fill=OUTLINE, width=s(2))

    for side in (-1, 1):
        draw_line(draw, [(cx + side * 20 + tilt, cy + 33), (cx + side * 55 + tilt, cy + 24)], OUTLINE, 2)
        draw_line(draw, [(cx + side * 20 + tilt, cy + 41), (cx + side * 56 + tilt, cy + 43)], OUTLINE, 2)


def draw_paws(draw: ImageDraw.ImageDraw, cx: float, cy: float, phase: float, mood: str) -> None:
    step = sin(phase * 2 * pi)
    lift = max(0, step)
    other = max(0, -step)
    front_y = cy + 108
    back_y = cy + 119

    if mood == "sleep":
        front_y += 16
        back_y += 8
        lift = other = 0
    if mood == "groom":
        lift = 1

    paws = [
        (cx - 54 - step * 6, front_y - lift * 22, 34, 30),
        (cx + 54 + step * 6, front_y - other * 22, 34, 30),
        (cx - 82 + step * 4, back_y - other * 12, 42, 28),
        (cx + 82 - step * 4, back_y - lift * 12, 42, 28),
    ]
    if mood == "groom":
        paws[1] = (cx + 64, cy + 42, 34, 28)
    for px, py, pw, ph in paws:
        draw.ellipse(box(px, py, pw + 8, ph + 8), fill=OUTLINE)
        draw.ellipse(box(px, py, pw, ph), fill=FUR)
        draw.arc(box(px, py + 4, pw * 0.66, ph * 0.45), 0, 180, fill=FUR_SHADE, width=s(2))


def draw_shadow(draw: ImageDraw.ImageDraw, cx: float, cy: float, width: float, alpha: int) -> None:
    draw.ellipse(box(cx, cy + 146, width, 24), fill=(0, 0, 0, alpha))


def make_frame(phase: float = 0.0, mood: str = "idle", blink: float = 0.0, jump: float = 0.0, tilt: float = 0.0, roll: float = 0.0) -> Image.Image:
    large = Image.new("RGBA", (CANVAS[0] * SCALE, CANVAS[1] * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(large)
    cx = 180
    cy = 178 - jump
    squash = 8 * max(0, -sin(phase * 2 * pi)) if mood == "hop" else 0
    stretch = 8 * max(0, sin(phase * 2 * pi)) if mood == "hop" else 0

    draw_shadow(draw, cx, 178, 172 - jump * 0.28, 44)
    draw_tail(draw, cx, cy, phase, jump)
    draw_body(draw, cx, cy, squash, stretch)
    draw_paws(draw, cx, cy, phase, mood)
    draw_head(draw, cx, cy, blink, tilt)

    if mood == "sleep":
        draw.text(point(cx + 74, cy - 78), "Z", fill=(88, 118, 160, 230))
    if mood == "roll":
        large = large.rotate(roll, resample=Image.Resampling.BICUBIC, center=point(cx, cy + 20))

    small = large.resize(CANVAS, Image.Resampling.LANCZOS)
    return small.filter(ImageFilter.UnsharpMask(radius=0.6, percent=80, threshold=4))


def save_sequence(out: Path, names: list[str], mood: str) -> None:
    total = len(names)
    for idx, name in enumerate(names):
        phase = idx / max(1, total)
        blink = 0.0
        jump = 0.0
        tilt = sin(phase * 2 * pi) * 4
        roll = 0.0

        if mood == "blink":
            blink = [0.0, 0.75, 1.0, 0.0][idx]
        elif mood == "hop":
            jump = max(0, sin(phase * pi)) * 30
        elif mood == "groom":
            blink = 0.2 if idx in (2, 3) else 0.0
            tilt = 7
        elif mood == "sleep":
            blink = 1.0
        elif mood == "roll":
            roll = [45, 90, 135, 180, 225, 270, 315, 0][idx]
        elif mood == "stretch":
            jump = -8 * sin(phase * pi)
            tilt = -8 + idx * 4

        make_frame(phase=phase, mood=mood, blink=blink, jump=jump, tilt=tilt, roll=roll).save(out / name)


def main() -> int:
    out = Path("additional/Applications/啾啾.app/Contents/Resources")
    out.mkdir(parents=True, exist_ok=True)
    make_frame().save(out / "normal.png")
    save_sequence(out, [f"blink{i}.png" for i in range(4)], "blink")
    save_sequence(out, [f"hop{i}.png" for i in range(8)], "hop")
    save_sequence(out, [f"groom{i}.png" for i in range(7)], "groom")
    save_sequence(out, [f"sleep{i}.png" for i in range(2)], "sleep")
    save_sequence(out, ["roll045.png", "roll090.png", "roll135.png", "roll180.png", "roll225.png", "roll270.png", "roll315.png"], "roll")
    save_sequence(out, [f"str{i}.png" for i in range(5)], "stretch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
