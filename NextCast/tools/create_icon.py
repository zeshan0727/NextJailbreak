#!/usr/bin/env python3
"""Generate a 1024px Next Cast app icon with no external image services."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math
SIZE = 1024
image = Image.new("RGBA", (SIZE, SIZE))
p = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        glow = max(0, 1 - math.hypot((x - 700) / 1200, (y - 250) / 950))
        p[x, y] = (int(6 + glow * 7), int(16 + glow * 18), int(37 + glow * 36), 255)

# Construct the main glossy, multicolor play tile.
tile_mask = Image.new("L", (SIZE, SIZE))
tiled = ImageDraw.Draw(tile_mask)
tiled.rounded_rectangle((180, 210, 865, 773), radius=165, fill=255)
color = Image.new("RGBA", (SIZE, SIZE))
px = color.load()
for y in range(210, 774):
    for x in range(180, 866):
        t = max(0, min(1, (x - 180) / 685))
        s = max(0, min(1, (y - 210) / 564))
        r = int((1-t)*255 + t*20)
        g = int((1-t)*max(65, 190 - 170*s) + t*(100 + 55*s))
        b = int((1-t)*(50 + 120*s) + t*255)
        px[x, y] = (r, g, b, 255)
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
glow.paste(color, (0, 0), tile_mask)
halo = glow.filter(ImageFilter.GaussianBlur(45))
halo.putalpha(halo.getchannel("A").point(lambda a: int(a * .65)))
image.alpha_composite(halo)
image.paste(color, (0, 0), tile_mask)
d = ImageDraw.Draw(image)
d.rounded_rectangle((179, 209, 865, 773), radius=165, outline=(190, 245, 255, 225), width=9)
# Modern dark cutout with white-to-cyan play triangle.
d.rounded_rectangle((352, 325, 748, 659), radius=106, fill=(7, 19, 44, 240))
d.polygon(((474, 402), (474, 588), (642, 495)), fill=(242, 250, 255, 255))
# Broadcast arcs, bottom-left. Distinct enough at small sizes.
for radius, width in ((112, 35), (188, 35), (263, 35)):
    bounds = (101-radius, 831-radius, 101+radius, 831+radius)
    d.arc(bounds, start=270, end=360, fill=(30, 226, 255, 255), width=width)
d.ellipse((118, 818, 164, 864), fill=(29, 222, 255, 255))
# Export single-size universal iOS icon.
out = Path(__file__).resolve().parent.parent / "Assets.xcassets" / "AppIcon.appiconset"
out.mkdir(parents=True, exist_ok=True)
image.convert("RGB").save(out / "AppIcon.png", "PNG", optimize=True)
(out / "Contents.json").write_text('''{
  "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
  "info": {"author": "xcode", "version": 1}
}\n''')
print("Created", out / "AppIcon.png")
