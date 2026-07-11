#!/usr/bin/env python3
"""Composite NotchFlow screenshot into Apple MacBook hero asset."""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MACBOOK_SRC = ROOT / "website" / "assets" / "source" / "apple-macbookpro14-front.png"
SCREENSHOT = ROOT / "website" / "assets" / "screenshots" / "01-music.png"
OUTPUT = ROOT / "website" / "assets" / "hero-macbook.png"

# Inner display rect (measured from Apple asset at 1024×665).
SCREEN_LEFT = 106
SCREEN_TOP = 86
SCREEN_RIGHT = 917
SCREEN_BOTTOM = 595

OUTPUT_WIDTH = 900


def is_outer_black(r: int, g: int, b: int, a: int) -> bool:
    return a > 0 and r < 6 and g < 6 and b < 6


def make_wallpaper(size: tuple[int, int], screenshot: Image.Image) -> Image.Image:
    """Vertical blue gradient sampled from the screenshot wallpaper."""
    width, height = size
    top = screenshot.getpixel((width // 2, 0))[:3]
    mid = screenshot.getpixel((width // 2, min(120, screenshot.height - 1)))[:3]
    bottom = screenshot.getpixel((width // 2, min(280, screenshot.height - 1)))[:3]

    wallpaper = Image.new("RGB", size)
    px = wallpaper.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        if t < 0.45:
            blend = t / 0.45
            r = int(top[0] * (1 - blend) + mid[0] * blend)
            g = int(top[1] * (1 - blend) + mid[1] * blend)
            b = int(top[2] * (1 - blend) + mid[2] * blend)
        else:
            blend = (t - 0.45) / 0.55
            r = int(mid[0] * (1 - blend) + bottom[0] * blend)
            g = int(mid[1] * (1 - blend) + bottom[1] * blend)
            b = int(mid[2] * (1 - blend) + bottom[2] * blend)
        for x in range(width):
            px[x, y] = (r, g, b)
    return wallpaper


def build_screen_content(screenshot: Image.Image, screen_size: tuple[int, int]) -> Image.Image:
    screen_w, screen_h = screen_size
    wallpaper = make_wallpaper(screen_size, screenshot)

    scale = screen_w / screenshot.width
    scaled_h = int(screenshot.height * scale)
    scaled = screenshot.resize((screen_w, scaled_h), Image.Resampling.LANCZOS)

    content = wallpaper.convert("RGBA")
    content.paste(scaled, (0, 0))
    return content


def remove_outer_black_background(image: Image.Image) -> Image.Image:
    w, h = image.size
    px = image.load()
    visited = [[False] * w for _ in range(h)]
    queue: deque[tuple[int, int]] = deque()

    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if is_outer_black(*px[x, y]):
            queue.append((x, y))
            visited[y][x] = True

    while queue:
        x, y = queue.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                if is_outer_black(*px[nx, ny]):
                    visited[ny][nx] = True
                    queue.append((nx, ny))

    return image


def composite(macbook: Image.Image, screen_content: Image.Image) -> Image.Image:
    result = macbook.copy()
    mac_px = result.load()
    screen_px = screen_content.load()

    for y in range(SCREEN_TOP, SCREEN_BOTTOM + 1):
        for x in range(SCREEN_LEFT, SCREEN_RIGHT + 1):
            r, g, b, a = mac_px[x, y]
            if a == 0 or r > 12 or g > 12 or b > 12:
                continue
            sx = x - SCREEN_LEFT
            sy = y - SCREEN_TOP
            mac_px[x, y] = screen_px[sx, sy]

    return remove_outer_black_background(result)


def main() -> int:
    if not MACBOOK_SRC.exists():
        print(f"Missing MacBook asset: {MACBOOK_SRC}", file=sys.stderr)
        return 1
    if not SCREENSHOT.exists():
        print(f"Missing screenshot: {SCREENSHOT}", file=sys.stderr)
        return 1

    macbook = Image.open(MACBOOK_SRC).convert("RGBA")
    screenshot = Image.open(SCREENSHOT).convert("RGBA")

    screen_w = SCREEN_RIGHT - SCREEN_LEFT + 1
    screen_h = SCREEN_BOTTOM - SCREEN_TOP + 1
    screen_content = build_screen_content(screenshot, (screen_w, screen_h))
    result = composite(macbook, screen_content)

    scale = OUTPUT_WIDTH / result.width
    output_h = int(result.height * scale)
    result = result.resize((OUTPUT_WIDTH, output_h), Image.Resampling.LANCZOS)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    result.save(OUTPUT, format="PNG", optimize=True)

    size_kb = OUTPUT.stat().st_size / 1024
    print(f"Wrote {OUTPUT} ({OUTPUT_WIDTH}×{output_h}, {size_kb:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
