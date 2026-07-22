#!/usr/bin/env python3
"""Split the neutral cat artwork into overlapping layers for skeletal animation."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from generate_anime_source_sprites import fit, transparent_crop


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "normal.png"
OUTPUT = ROOT / "Resources"
WALK_SOURCE = ROOT / "assets" / "source" / "multiview" / "pngwing-turn.png"
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

WALK_PARTS = {
    "walk_tail": [(27, 115), (70, 116), (82, 199), (103, 247), (78, 281), (42, 259), (31, 210)],
    "walk_body": [(48, 204), (103, 188), (166, 198), (220, 225), (250, 266), (232, 302),
                  (185, 315), (122, 309), (72, 292), (49, 268)],
    "walk_rear_leg": [(24, 269), (93, 264), (151, 282), (158, 302), (119, 319), (82, 350),
                      (46, 358), (28, 343)],
    "walk_hind_leg": [(119, 265), (171, 264), (193, 283), (190, 316), (177, 339), (157, 334),
                      (146, 311), (139, 290)],
    "walk_front_down_leg": [(178, 258), (226, 253), (244, 279), (240, 331), (226, 359),
                            (204, 356), (192, 326), (188, 291)],
    "walk_front_leg": [(207, 222), (276, 215), (338, 232), (346, 260), (329, 279), (282, 277),
                       (249, 289), (225, 282), (216, 260)],
    "walk_head": [(102, 168), (119, 129), (171, 116), (195, 92), (228, 127), (274, 141),
                  (313, 181), (320, 226), (289, 269), (245, 287), (188, 276), (140, 250), (112, 219)],
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
        if name == "rig_body":
            # Restore only source-backed chest pixels beneath the moving paw roots.
            underlay = polygon_mask(source.size, [(166, 252), (251, 252), (258, 320), (164, 320)])
            underlay = Image.composite(source_alpha, Image.new("L", source.size, 0), underlay)
            mask = ImageChops.lighter(mask, underlay)
        part = source.copy()
        part.putalpha(mask)
        part.save(OUTPUT / f"{name}.png", optimize=True)

    walk_source = fit(transparent_crop(WALK_SOURCE), 326, 250, 42)
    walk_alpha = walk_source.getchannel("A")
    walk_masks = {name: polygon_mask(walk_source.size, points) for name, points in WALK_PARTS.items()}
    for name, mask in walk_masks.items():
        mask = Image.composite(walk_alpha, Image.new("L", walk_source.size, 0), mask)
        masked_source = walk_source.copy()
        masked_source.putalpha(mask)
        part = masked_source
        if name == "walk_head":
            part = part.rotate(-12, Image.Resampling.BICUBIC, center=(202, 259))
        part.save(OUTPUT / f"{name}.png", optimize=True)

    print(f"Generated {len(PARTS) + len(WALK_PARTS)} articulated layers in {OUTPUT}")


if __name__ == "__main__":
    main()
