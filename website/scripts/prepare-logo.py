#!/usr/bin/env python3
"""Prepare NotchFlow logo assets with transparent backgrounds."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "logo-source.png"

WEB = ROOT / "website" / "assets"
APP = ROOT / "Sources" / "NotchFlow" / "Resources"


def remove_black_background(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    width, height = result.size
    pixels = result.load()

    def is_background(r: int, g: int, b: int) -> bool:
        return r < 12 and g < 12 and b < 12

    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        for y in (0, height - 1):
            if is_background(*pixels[x, y][:3]):
                queue.append((x, y))
    for y in range(height):
        for x in (0, width - 1):
            if is_background(*pixels[x, y][:3]):
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited:
            continue
        if x < 0 or x >= width or y < 0 or y >= height:
            continue
        r, g, b, _ = pixels[x, y]
        if not is_background(r, g, b):
            continue
        visited.add((x, y))
        pixels[x, y] = (0, 0, 0, 0)
        queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    return result


def resize(image: Image.Image, height: int) -> Image.Image:
    aspect = image.width / image.height
    width = max(1, int(height * aspect))
    return image.resize((width, height), Image.Resampling.LANCZOS)


def fit_square(image: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scale = min((size * 0.88) / image.width, (size * 0.88) / image.height)
    width = max(1, int(image.width * scale))
    height = max(1, int(image.height * scale))
    resized = image.resize((width, height), Image.Resampling.LANCZOS)
    x = (size - width) // 2
    y = (size - height) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas


def make_og_image(logo: Image.Image, path: Path) -> None:
    canvas = Image.new("RGBA", (1200, 630), (17, 17, 17, 255))
    scale = min(900 / logo.width, 280 / logo.height)
    width = max(1, int(logo.width * scale))
    height = max(1, int(logo.height * scale))
    resized = logo.resize((width, height), Image.Resampling.LANCZOS)
    x = (1200 - width) // 2
    y = (630 - height) // 2 - 40
    canvas.paste(resized, (x, y), resized)
    canvas.convert("RGB").save(path, quality=92)


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source logo: {SOURCE}")

    logo = remove_black_background(Image.open(SOURCE))
    WEB.mkdir(parents=True, exist_ok=True)
    APP.mkdir(parents=True, exist_ok=True)

    logo.save(WEB / "logo.png")
    logo.save(APP / "LogoMark.png")
    resize(logo, 112).save(WEB / "logo-mark.png")
    resize(logo, 200).save(WEB / "logo-large.png")

    fit_square(logo, 32).save(WEB / "favicon.png")
    fit_square(logo, 180).save(WEB / "favicon-180.png")
    fit_square(logo, 512).save(WEB / "favicon-512.png")
    make_og_image(logo, WEB / "og-image.png")

    print("Wrote transparent logo assets")


if __name__ == "__main__":
    main()
