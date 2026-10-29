#!/usr/bin/env python3
"""Generate the Seal app icon (Material 3 Expressive-inspired seal mark)."""
from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
DOCS = ROOT / "docs"
ICONSET = RESOURCES / "AppIcon.iconset"
S = 2048  # supersampled master


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = image.load()
    c0, c1, c2 = (63, 45, 196), (112, 62, 245), (255, 107, 101)

    for y in range(size):
        for x in range(size):
            t = x / size * 0.55 + y / size * 0.45
            color = lerp(c0, c1, min(1, t / 0.58)) if t < 0.58 else lerp(c1, c2, (t - 0.58) / 0.42)
            dx = (x - size * 0.18) / size
            dy = (y - size * 0.10) / size
            glow = max(0.0, 1.0 - math.hypot(dx, dy) * 2.1) * 22
            px[x, y] = (
                min(255, color[0] + int(glow)),
                min(255, color[1] + int(glow)),
                min(255, color[2] + int(glow)),
                255,
            )

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((128, 128, size - 128, size - 128), radius=430, fill=255)
    image.putalpha(mask)

    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        (-size * 0.50, -size * 0.62, size * 0.90, size * 0.30),
        fill=(255, 255, 255, 24),
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(130))
    return Image.alpha_composite(
        image,
        Image.composite(sheen, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask),
    )


def rosette(cx, cy, outer, inner, lobes, phase=0.0, samples=1440):
    points = []
    for i in range(samples):
        angle = i / samples * math.tau
        wave = 0.5 + 0.5 * math.cos((angle - phase) * lobes)
        radius = inner + (outer - inner) * (wave ** 1.1)
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def make_icon() -> Image.Image:
    base = make_background(S)
    cx = cy = S / 2
    lobes = 10
    phase = math.pi / lobes

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(
        rosette(cx, cy + 32, S * 0.345, S * 0.302, lobes, phase),
        fill=(28, 10, 64, 100),
    )
    base = Image.alpha_composite(base, shadow.filter(ImageFilter.GaussianBlur(50)))

    seal = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(seal).polygon(
        rosette(cx, cy, S * 0.345, S * 0.302, lobes, phase),
        fill=(255, 249, 243, 255),
    )
    base = Image.alpha_composite(base, seal)

    radius = int(S * 0.218)
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(disc)
    d0, d1, d2 = (24, 16, 52), (61, 35, 120), (124, 61, 160)
    for i in range(140, 0, -1):
        t = i / 140
        color = lerp(d0, d1, min(1, t / 0.6)) if t < 0.6 else lerp(d1, d2, (t - 0.6) / 0.4)
        r = radius * t
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*color, 255))

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (cx - radius * 0.95, cy - radius * 1.05, cx + radius * 0.3, cy + radius * 0.3),
        fill=(110, 80, 255, 55),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(45))
    disc_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(disc_mask).ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius), fill=255
    )
    disc = Image.alpha_composite(
        disc,
        Image.composite(glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), disc_mask),
    )
    base = Image.alpha_composite(base, disc)

    check_width = int(radius * 0.145)
    check = [
        (cx - radius * 0.45, cy + radius * 0.02),
        (cx - radius * 0.10, cy + radius * 0.37),
        (cx + radius * 0.52, cy - radius * 0.34),
    ]

    check_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(check_shadow)
    shadow_check = [(x, y + 12) for x, y in check]
    shadow_draw.line(shadow_check, fill=(10, 4, 30, 110), width=check_width, joint="curve")
    for point in (shadow_check[0], shadow_check[-1]):
        shadow_draw.ellipse(
            (point[0] - check_width / 2, point[1] - check_width / 2,
             point[0] + check_width / 2, point[1] + check_width / 2),
            fill=(10, 4, 30, 110),
        )
    base = Image.alpha_composite(base, check_shadow.filter(ImageFilter.GaussianBlur(13)))

    check_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    check_draw = ImageDraw.Draw(check_layer)
    check_draw.line(check, fill=(255, 250, 245, 255), width=check_width, joint="curve")
    for point in (check[0], check[-1]):
        check_draw.ellipse(
            (point[0] - check_width / 2, point[1] - check_width / 2,
             point[0] + check_width / 2, point[1] + check_width / 2),
            fill=(255, 250, 245, 255),
        )
    base = Image.alpha_composite(base, check_layer)
    return base.resize((1024, 1024), Image.LANCZOS)


def main():
    RESOURCES.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir()

    master = make_icon()
    master.save(RESOURCES / "AppIcon-1024.png")
    master.resize((256, 256), Image.LANCZOS).save(DOCS / "icon.png")

    for size in (16, 32, 128, 256, 512):
        master.resize((size, size), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}.png")
        master.resize((size * 2, size * 2), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}@2x.png")
    (ICONSET / "icon_512x512@2x.png").unlink(missing_ok=True)
    master.save(ICONSET / "icon_512x512@2x.png")

    subprocess.run(
        ["/usr/bin/iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")],
        check=True,
    )
    print(f"wrote {RESOURCES / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
