#!/usr/bin/env python3
"""Generate Tapp app icon PNGs (vertical sticks + diagonal slash on top)."""

from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw

# Center-to-center gap between vertical sticks (was stick_w * 1.55; +50% spacing).
GAP_RATIO = 1.55 * 1.5


def render_tally(size: int, *, bg: str) -> Image.Image:
    if bg == "black":
        img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    else:
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    cx = cy = size // 2
    stick_h = int(size * 0.52)
    stick_w = max(28, int(size * 0.048))
    gap = int(stick_w * GAP_RATIO)
    r = stick_w // 2
    xs = [-1.5 * gap, -0.5 * gap, 0.5 * gap, 1.5 * gap]
    white = (255, 255, 255, 255)

    verticals = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vd = ImageDraw.Draw(verticals)
    for x in xs:
        left = cx + x - stick_w // 2
        top = cy - stick_h // 2
        vd.rounded_rectangle((left, top, left + stick_w, top + stick_h), radius=r, fill=white)

    p1 = (cx + xs[0] - stick_w // 2, cy + stick_h // 2)
    p2 = (cx + xs[3] + stick_w // 2, cy - stick_h // 2)

    slash = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(slash)
    sd.line([p1, p2], fill=white, width=stick_w, joint="curve")

    out = Image.alpha_composite(img, verticals)
    return Image.alpha_composite(out, slash)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon_dir = os.path.join(root, "Tapp", "Assets.xcassets", "AppIcon.appiconset")
    assets_dir = os.path.join(root, "assets")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(assets_dir, exist_ok=True)

    for name, bg in [
        ("AppIcon.png", "black"),
        ("AppIcon-dark.png", "black"),
        ("AppIcon-tinted.png", "transparent"),
    ]:
        path = os.path.join(icon_dir, name)
        render_tally(1024, bg=bg).save(path)
        print("wrote", path)

    logo = os.path.join(assets_dir, "tapp-logo-stick-five-symmetric.png")
    render_tally(1024, bg="black").convert("RGB").save(logo)
    print("wrote", logo)


if __name__ == "__main__":
    main()
