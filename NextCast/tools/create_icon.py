#!/usr/bin/env python3
"""Generate NexaPlay's original high-resolution multicolor play icon."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math
import json

SIZE = 1024
im = Image.new("RGBA", (SIZE, SIZE))
px = im.load()

# Deep navy cinematic base with restrained cyan/orange ambient highlights.
for y in range(SIZE):
    for x in range(SIZE):
        blue = max(0.0, 1.0 - math.hypot((x - 220) / 730, (y - 130) / 680))
        orange = max(0.0, 1.0 - math.hypot((x - 950) / 660, (y - 900) / 620))
        px[x, y] = (
            min(255, int(7 + blue * 12 + orange * 27)),
            min(255, int(12 + blue * 25 + orange * 9)),
            min(255, int(31 + blue * 43 + orange * 17)),
            255
        )

# Mask for the continuous triangular brand ribbon, softened at each corner.
mask = Image.new("L", (SIZE, SIZE), 0)
d = ImageDraw.Draw(mask)
vertices = [(309, 215), (782, 513), (309, 809), (309, 215)]
d.line(vertices, fill=255, width=130, joint="curve")
for x, y in vertices[:-1]:
    d.ellipse((x - 65, y - 65, x + 65, y + 65), fill=255)

# Soft ambient glow behind the crisp play outline.
glow = Image.new("RGBA", (SIZE, SIZE), (40, 116, 255, 0))
glow.putalpha(mask.filter(ImageFilter.GaussianBlur(66)).point(lambda a: int(a * 0.43)))
im.alpha_composite(glow)

# Gradient follows the icon's edges: cyan upper left, blue/purple at the
# lower left, orange/red to the right, like the approved NexaPlay concept.
color = Image.new("RGBA", (SIZE, SIZE))
cp = color.load()
for y in range(SIZE):
    for x in range(SIZE):
        t = max(0.0, min(1.0, (x - 240) / 560))
        vertical = max(0.0, min(1.0, (y - 205) / 600))
        left = (
            int(15 + 113 * vertical),
            int(220 - 151 * vertical),
            int(252 - 6 * vertical)
        )
        right = (
            255,
            int(136 - 75 * vertical),
            int(11 + 49 * vertical)
        )
        cp[x, y] = tuple(int(left[i] * (1 - t) + right[i] * t) for i in range(3)) + (255,)
im.paste(color, (0, 0), mask)

# Inner navy film-shaped cutout creates depth and keeps the play recognisable
# at small Home Screen sizes.
d = ImageDraw.Draw(im)
d.polygon([(373, 348), (643, 514), (373, 677)], fill=(11, 17, 43, 255))
d.polygon([(425, 408), (603, 514), (425, 619)], fill=(241, 251, 255, 255))
# Subtle, non-distracting specular highlight.
shine = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shine)
sd.arc((245, 144, 755, 880), 190, 300, fill=(255, 255, 255, 36), width=19)
im = Image.alpha_composite(im, shine)

out = Path(__file__).resolve().parent.parent / "Assets.xcassets" / "AppIcon.appiconset"
out.mkdir(parents=True, exist_ok=True)
im.convert("RGB").save(out / "AppIcon.png", "PNG", optimize=True)
(out / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal",
                "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2) + "\n")
print("Created NexaPlay icon:", out / "AppIcon.png")
