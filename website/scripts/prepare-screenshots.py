#!/usr/bin/env python3
"""Replace harsh desktop blue in NotchFlow screenshots with a soft macOS-style gradient."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SCREENSHOTS_DIR = Path(__file__).resolve().parents[1] / "assets" / "screenshots"

GRADIENT_TOP = (178, 216, 241)
GRADIENT_BOTTOM = (118, 176, 218)
BOTTOM_PAD = 48
CORNER_RADIUS = 22


def gradient_color(y: int, height: int) -> tuple[int, int, int]:
    t = y / max(height - 1, 1)
    return tuple(
        int(GRADIENT_TOP[i] + (GRADIENT_BOTTOM[i] - GRADIENT_TOP[i]) * t)
        for i in range(3)
    )


def wallpaper_weight(r: int, g: int, b: int) -> float:
    """0 = UI pixel, 1 = wallpaper pixel (with soft edges)."""
    if r < 42 and g < 42 and b < 55:
        return 0.0

    blue_excess = b - max(r, g)
    if blue_excess < 25:
        return 0.0

    if r < 115 and g > 95 and b > 155 and blue_excess > 40:
        return min(1.0, blue_excess / 110.0)

    return 0.0


def replace_wallpaper(image: Image.Image) -> Image.Image:
    src = image.convert("RGB")
    width, height = src.size
    out = Image.new("RGB", (width, height))
    src_px = src.load()
    out_px = out.load()

    for y in range(height):
        bg = gradient_color(y, height + BOTTOM_PAD)
        for x in range(width):
            r, g, b = src_px[x, y]
            weight = wallpaper_weight(r, g, b)
            if weight <= 0:
                out_px[x, y] = (r, g, b)
            elif weight >= 1:
                out_px[x, y] = bg
            else:
                out_px[x, y] = tuple(
                    int(r + (bg[i] - r) * weight) for i in range(3)
                )

    return out


def content_bottom(image: Image.Image) -> int:
    px = image.load()
    width, height = image.size
    for y in range(height - 1, -1, -1):
        for x in range(0, width, 6):
            r, g, b = px[x, y]
            if r < 55 and g < 55 and b < 70:
                return y
    return height - 1


def round_corners(image: Image.Image, radius: int) -> Image.Image:
    w, h = image.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    result = Image.new("RGB", (w, h), GRADIENT_TOP)
    result.paste(image, (0, 0), mask)
    return result


def process(path: Path) -> None:
    image = Image.open(path)
    painted = replace_wallpaper(image)

    bottom = content_bottom(painted)
    cropped = painted.crop((0, 0, painted.width, bottom + 18))

    final_h = cropped.height + BOTTOM_PAD
    canvas = Image.new("RGB", (cropped.width, final_h))
    draw = ImageDraw.Draw(canvas)
    for y in range(final_h):
        draw.line([(0, y), (cropped.width, y)], fill=gradient_color(y, final_h))

    canvas.paste(cropped, (0, 0))
    finished = round_corners(canvas, CORNER_RADIUS)
    finished.save(path, optimize=True)
    print(f"processed {path.name} -> {finished.size[0]}x{finished.size[1]}")


def main() -> None:
    for path in sorted(SCREENSHOTS_DIR.glob("*.png")):
        process(path)


if __name__ == "__main__":
    main()
