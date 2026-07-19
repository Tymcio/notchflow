#!/usr/bin/env python3
"""Generate a light, readable drag-to-Applications DMG background."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow required: python3 -m pip install pillow", file=sys.stderr)
    raise SystemExit(1)


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    # Finder window content ≈ 600×350 pt → 2× bitmap for Retina.
    w, h = 1200, 700
    img = Image.new("RGB", (w, h), (244, 246, 250))
    draw = ImageDraw.Draw(img)

    # Soft vertical wash so it doesn't look flat-white.
    for y in range(h):
        t = y / (h - 1)
        r = int(244 - 8 * t)
        g = int(246 - 6 * t)
        b = int(250 - 4 * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

    # Icon drop zones — light rings, not dark cards (labels stay dark/readable).
    left_c = (300, 290)
    right_c = (900, 290)
    for cx, cy in (left_c, right_c):
        draw.ellipse((cx - 118, cy - 118, cx + 118, cy + 118), outline=(210, 216, 228), width=3)
        draw.ellipse((cx - 104, cy - 104, cx + 104, cy + 104), outline=(228, 232, 240), width=2)

    # Brand arrow between icons.
    ax0, ax1, ay = 430, 770, 290
    draw.line([(ax0, ay), (ax1 - 48, ay)], fill=(70, 120, 240), width=18)
    draw.polygon(
        [(ax1 - 70, ay - 42), (ax1, ay), (ax1 - 70, ay + 42)],
        fill=(70, 120, 240),
    )
    # Soft wave accent under the arrow.
    for i, color in enumerate([(56, 190, 240), (90, 120, 240), (160, 90, 230)]):
        y = 360 + i * 12
        draw.arc((500, y - 40, 700, y + 40), 200, 340, fill=color, width=5)

    title = load_font(36)
    caption = load_font(28)
    draw.text(
        (w / 2, 88),
        "Install NotchFlow",
        fill=(40, 48, 64),
        font=title,
        anchor="mm",
    )
    draw.text(
        (w / 2, 560),
        "Drag the app onto Applications",
        fill=(110, 120, 140),
        font=caption,
        anchor="mm",
    )

    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/dmg-background.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG", optimize=True)
    print(f"Wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
