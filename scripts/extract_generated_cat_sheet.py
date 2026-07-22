#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image
import sys

CANVAS = (360, 392)
GREEN_THRESHOLD = 72
BOTTOM_PADDING = 16


def subject_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pixels[x, y]
            green_delta = g - max(r, b)
            is_green = g > 120 and green_delta > 26
            if is_green and (g > 150 or green_delta > GREEN_THRESHOLD):
                pixels[x, y] = (r, g, b, 0)
            elif is_green:
                pixels[x, y] = (min(255, r + 12), min(g, max(r, b) + 10), min(255, b + 12), max(0, a - 90))
    return rgba


def remove_small_islands(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    mask = alpha.load()
    w, h = rgba.size
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []

    for y in range(h):
        for x in range(w):
            if mask[x, y] <= 18 or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            comp: list[tuple[int, int]] = []
            while stack:
                px, py = stack.pop()
                comp.append((px, py))
                for nx, ny in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and mask[nx, ny] > 18:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            components.append(comp)

    if not components:
        return rgba

    largest = max(len(c) for c in components)
    keep: set[tuple[int, int]] = set()
    for comp in components:
        if len(comp) >= max(90, largest * 0.018):
            keep.update(comp)

    pixels = rgba.load()
    for y in range(h):
        for x in range(w):
            if mask[x, y] > 0 and (x, y) not in keep:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba


def fit_pose(pose: Image.Image) -> Image.Image:
    pose = remove_small_islands(pose)
    bbox = pose.getchannel("A").getbbox()
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    if bbox is None:
        return canvas
    cropped = pose.crop(bbox)
    max_w = CANVAS[0] - 28
    max_h = CANVAS[1] - 30
    scale = min(max_w / cropped.width, max_h / cropped.height, 1.0)
    if scale < 1.0:
        cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)), Image.Resampling.LANCZOS)
    x = (CANVAS[0] - cropped.width) // 2
    y = CANVAS[1] - cropped.height - BOTTOM_PADDING
    canvas.alpha_composite(cropped, (x, max(0, y)))
    return canvas


def extract_poses(sheet_path: Path) -> list[Image.Image]:
    sheet = subject_alpha(Image.open(sheet_path))
    cols, rows = 4, 3
    cell_w = sheet.width // cols
    cell_h = sheet.height // rows
    poses: list[Image.Image] = []
    for row in range(rows):
        for col in range(cols):
            cell = sheet.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
            poses.append(fit_pose(cell))
    return poses


def save_sequence(out: Path, names: list[str], pose_indices: list[int], poses: list[Image.Image]) -> None:
    for name, pose_idx in zip(names, pose_indices):
        poses[pose_idx].save(out / name)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_generated_cat_sheet.py <sheet.png> <resource-dir>", file=sys.stderr)
        return 2
    poses = extract_poses(Path(sys.argv[1]))
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    poses[0].save(out / "normal.png")
    save_sequence(out, [f"blink{i}.png" for i in range(4)], [0, 1, 1, 0], poses)
    save_sequence(out, [f"hop{i}.png" for i in range(8)], [0, 3, 2, 4, 2, 3, 4, 0], poses)
    save_sequence(out, [f"groom{i}.png" for i in range(7)], [0, 5, 5, 5, 5, 1, 0], poses)
    save_sequence(out, [f"sleep{i}.png" for i in range(2)], [6, 6], poses)
    save_sequence(out, [f"str{i}.png" for i in range(5)], [8, 9, 9, 10, 8], poses)

    roll = poses[11]
    angles = [45, 90, 135, 180, 225, 270, 315]
    for angle in angles:
        rotated = roll.rotate(angle, resample=Image.Resampling.BICUBIC)
        fit_pose(rotated).save(out / f"roll{angle:03d}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
