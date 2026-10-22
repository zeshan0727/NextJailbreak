#!/usr/bin/env python3
"""Reproduce all NovaBrowser icons. Build dependency: Pillow 11.3.0 or newer."""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "NovaBrowser/Resources/Assets.xcassets/AppIcon.appiconset"

def make_icon():
    size = 1024
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            glow = max(0, 1 - math.hypot(x - 190, y - 130) / 920) ** 2
            violet = max(0, 1 - math.hypot(x - 930, y - 1000) / 750) ** 2
            pixels[x, y] = (int(13 + 15*t + 11*glow + 42*violet), int(25 + 36*t + 98*glow), int(65 + 70*t + 93*glow + 28*violet))
    shadow = Image.new("RGBA", image.size)
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((173, 189, 851, 867), fill=(0, 0, 20, 105))
    image = Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(30)))
    overlay = Image.new("RGBA", image.size)
    d = ImageDraw.Draw(overlay)
    d.ellipse((172, 172, 852, 852), fill=(240, 255, 255, 12), outline=(220, 255, 255, 240), width=15)
    d.ellipse((199, 199, 825, 825), outline=(177, 243, 255, 75), width=3)
    # Longitude and latitude lines suggest a globe underneath the compass.
    d.ellipse((340, 191, 684, 833), outline=(143, 234, 246, 90), width=7)
    d.ellipse((191, 351, 833, 673), outline=(143, 234, 246, 90), width=7)
    d.line((191, 512, 833, 512), fill=(143, 234, 246, 65), width=5)
    d.line((512, 191, 512, 833), fill=(143, 234, 246, 65), width=5)
    for index in range(48):
        theta = index * math.tau / 48
        radius = 306 if index % 4 == 0 else 315
        p1 = (512 + radius*math.sin(theta), 512 - radius*math.cos(theta))
        p2 = (512 + 327*math.sin(theta), 512 - 327*math.cos(theta))
        d.line((p1, p2), fill=(239, 255, 255, 210 if index % 4 == 0 else 100), width=5 if index % 4 == 0 else 3)
    # Four crisp faces; no rounded corners or transparent border are baked in.
    d.polygon([(724, 300), (577, 577), (512, 512)], fill=(255, 255, 255, 255))
    d.polygon([(724, 300), (447, 447), (512, 512)], fill=(186, 255, 245, 255))
    d.polygon([(300, 724), (447, 447), (512, 512)], fill=(8, 216, 207, 255))
    d.polygon([(300, 724), (577, 577), (512, 512)], fill=(7, 149, 184, 255))
    d.ellipse((493, 493, 531, 531), fill=(243, 255, 255, 255))
    return Image.alpha_composite(image, overlay).convert("RGB")

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    master = make_icon()
    entries = []
    specs = {"iphone": [(20, [2, 3]), (29, [2, 3]), (40, [2, 3]), (60, [2, 3])],
             "ipad": [(20, [1, 2]), (29, [1, 2]), (40, [1, 2]), (76, [1, 2]), (83.5, [2])],
             "ios-marketing": [(1024, [1])]}
    for idiom, sizes in specs.items():
        for points, scales in sizes:
            for scale in scales:
                pixels = round(points * scale)
                filename = f"Icon-{pixels}.png"
                master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(DEST / filename, optimize=True)
                entries.append({"size": f"{points}x{points}", "idiom": idiom, "filename": filename, "scale": f"{scale}x"})
    (DEST / "Contents.json").write_text(json.dumps({"images": entries, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    (DEST.parent / "Contents.json").write_text('{"info":{"version":1,"author":"xcode"}}\n')
    print(f"Generated {len(entries)} icon slots; opaque 1024×1024 master included.")

if __name__ == "__main__":
    main()
