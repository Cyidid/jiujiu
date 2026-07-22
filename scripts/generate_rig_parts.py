#!/usr/bin/env python3
"""Split the neutral cat artwork into overlapping layers for skeletal animation."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "normal.png"
OUTPUT = ROOT / "Resources"
SCALE = 4


PARTS = {
    "rig_tail": [
        (48, 378), (52, 341), (68, 315), (101, 296), (137, 280),
        (173, 276), (183, 299), (165, 325), (130, 340), (98, 351),
        (78, 380),
    ],
    "rig_body": [
        (128, 225), (151, 203), (188, 198), (228, 205), (273, 207),
        (300, 240), (310, 304), (302, 348), (279, 368), (142, 368),
        (127, 337),
    ],
    "rig_haunches": [
        (123, 298), (151, 282), (188, 291), (214, 307), (245, 287),
        (289, 295), (309, 325), (302, 372), (126, 372),
    ],
    "rig_paw_left": [
        (174, 246), (207, 246), (213, 327), (211, 360), (198, 374),
        (177, 372), (166, 357), (169, 326),
    ],
    "rig_paw_right": [
        (216, 246), (252, 246), (258, 322), (282, 341), (285, 360),
        (272, 373), (240, 371), (222, 356), (217, 323),
    ],
    "rig_head": [
        (42, 137), (56, 102), (121, 104), (159, 18), (202, 31),
        (227, 65), (270, 84), (301, 117), (312, 167), (295, 214),
        (267, 245), (226, 273), (170, 270), (119, 246), (78, 211),
        (57, 178),
    ],
}


def polygon_mask(size: tuple[int, int], points: list[tuple[int, int]]) -> Image.Image:
    large = Image.new("L", (size[0] * SCALE, size[1] * SCALE), 0)
    draw = ImageDraw.Draw(large)
    draw.polygon([(x * SCALE, y * SCALE) for x, y in points], fill=255)
    mask = large.resize(size, Image.Resampling.LANCZOS)
    return mask.filter(ImageFilter.GaussianBlur(0.35))


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    source_alpha = source.getchannel("A")
    masks = {name: polygon_mask(source.size, points) for name, points in PARTS.items()}

    moving_parts = ImageChops.lighter(masks["rig_paw_left"], masks["rig_paw_right"])
    masks["rig_body"] = ImageChops.subtract(masks["rig_body"], moving_parts)
    masks["rig_body"] = ImageChops.subtract(masks["rig_body"], masks["rig_head"])
    masks["rig_body"] = ImageChops.subtract(masks["rig_body"], masks["rig_tail"])
    masks["rig_haunches"] = ImageChops.subtract(masks["rig_haunches"], moving_parts)
    masks["rig_haunches"] = ImageChops.subtract(masks["rig_haunches"], masks["rig_tail"])

    for name, mask in masks.items():
        mask = Image.composite(source_alpha, Image.new("L", source.size, 0), mask)
        part = source.copy()
        part.putalpha(mask)
        if name == "rig_body":
            # A small underlay hides joint gaps when either front paw swings away.
            draw = ImageDraw.Draw(part)
            draw.polygon([(166, 252), (251, 252), (268, 337), (160, 337)],
                         fill=(252, 252, 250, 255))
        part.save(OUTPUT / f"{name}.png", optimize=True)

    print(f"Generated {len(PARTS)} articulated layers in {OUTPUT}")


if __name__ == "__main__":
    main()
