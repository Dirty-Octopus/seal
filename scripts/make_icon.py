#!/usr/bin/env python3
"""Render Seal's AYMDevKitUI utility mark on the shared 16 × 16 pixel grid."""
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / 'Resources'
ROWS = [0, 0, 0, 0x0ff0, 0x1ff8, 0x1800, 0x1800, 0x1ff0, 0x0ff8, 0x0018, 0x0018, 0x1ff8, 0x0ff0, 0, 0, 0]

def main():
    master = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(master)
    draw.rounded_rectangle((80, 80, 944, 944), radius=184, fill='#164BFF')
    for y, row in enumerate(ROWS):
        for x in range(16):
            if row & (1 << (15 - x)):
                draw.rectangle((128 + x * 48, 128 + y * 48, 175 + x * 48, 175 + y * 48), fill='white')
    RESOURCES.mkdir(exist_ok=True)
    iconset = RESOURCES / 'AppIcon.iconset'
    iconset.mkdir(exist_ok=True)
    master.save(RESOURCES / 'AppIcon-1024.png')
    (ROOT / 'docs').mkdir(exist_ok=True)
    master.resize((256, 256), Image.Resampling.LANCZOS).save(ROOT / 'docs/icon.png')
    for size in (16, 32, 128, 256, 512):
        master.resize((size, size), Image.Resampling.LANCZOS).save(iconset / f'icon_{size}x{size}.png')
        master.resize((size * 2, size * 2), Image.Resampling.LANCZOS).save(iconset / f'icon_{size}x{size}@2x.png')
    subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(iconset), '-o', str(RESOURCES / 'AppIcon.icns')], check=True)
    print(RESOURCES / 'AppIcon.icns')

if __name__ == '__main__':
    main()
