#!/usr/bin/env python3
"""Generate a light drag-to-Applications DMG background.

Finder maps background pixels 1:1 to window points (not Retina @2x).
Window content is 600×350 — the PNG must be exactly that size.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow required: python3 -m pip install pillow", file=sys.stderr)
    raise SystemExit(1)


def load_font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    # Must match create_dmg.sh window content size (bounds width×height).
    w, h = 600, 350
    img = Image.new("RGB", (w, h), (246, 248, 252))
    draw = ImageDraw.Draw(img)

    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(248 - 8 * t)
        g = int(250 - 6 * t)
        b = int(254 - 4 * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

    # Icon centers match AppleScript positions: (150,165) and (450,165).
    left = (150, 165)
    right = (450, 165)
    for cx, cy in (left, right):
        draw.ellipse(
            (cx - 58, cy - 58, cx + 58, cy + 58),
            fill=(255, 255, 255),
            outline=(205, 214, 230),
            width=2,
        )

    y = 165
    x0, x1 = 230, 370
    color = (55, 105, 230)
    draw.line([(x0, y), (x1 - 20, y)], fill=color, width=5)
    draw.polygon([(x1 - 24, y - 14), (x1, y), (x1 - 24, y + 14)], fill=color)

    for i, c in enumerate(((56, 190, 240), (90, 120, 240), (160, 90, 230))):
        yy = 210 + i * 5
        pts = [(x, yy + math.sin(((x - 255) / 90) * math.pi) * 6) for x in range(255, 346, 2)]
        if len(pts) >= 2:
            draw.line(pts, fill=c, width=2)

    title = load_font(22)
    caption = load_font(15)
    hint = load_font(11)
    draw.text((w / 2, 36), "Install NotchFlow", fill=(28, 36, 52), font=title, anchor="mm")
    draw.text(
        (w / 2, 280),
        "Drag NotchFlow to Applications",
        fill=(100, 112, 132),
        font=caption,
        anchor="mm",
    )
    draw.text(
        (w / 2, 302),
        "You can eject the disk image afterwards",
        fill=(150, 160, 175),
        font=hint,
        anchor="mm",
    )

    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/dmg-background.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG", optimize=True)
    print(f"Wrote {out} ({w}×{h}, {out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
