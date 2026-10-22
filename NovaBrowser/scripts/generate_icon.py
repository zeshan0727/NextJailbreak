#!/usr/bin/env python3
"""Reproducible opaque NovaBrowser icon generator (Pillow only)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "NovaBrowser/Resources/Assets.xcassets/AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)
S = 1024
im = Image.new("RGB", (S, S))
pixel = im.load()
for y in range(S):
    for x in range(S):
        b = (x+y)/(2*S)
        v = (0.56*x+0.44*(S-y))/S
        pixel[x,y] = (int(8+20*v), int(27+78*b), int(83+116*v))
# softly glowing circular globe, drawn on opaque background
light = Image.new("RGBA", (S,S), (0,0,0,0))
ld = ImageDraw.Draw(light)
ld.ellipse((125,125,899,899), fill=(68,213,234,85))
light = light.filter(ImageFilter.GaussianBlur(95))
im = Image.alpha_composite(im.convert("RGBA"),light)
d = ImageDraw.Draw(im)
d.ellipse((166,166,858,858), fill=(18,70,121,255), outline=(114,243,249,255), width=24)
# Globe meridians and parallels
for inset in (100,205):
    d.ellipse((166+inset,166,858-inset,858), outline=(92,221,238,175), width=10)
for y in (350,512,674):
    h = (1 - ((y-512)/346)**2)**0.5*346
    d.arc((512-h, y-0.2*h,512+h,y+0.2*h), 0, 180, fill=(92,221,238,200), width=8)
d.line((167,512,857,512), fill=(92,221,238,165), width=8)
# Compass needle, luminous rim and white central axis
d.polygon([(512,228),(573,515),(512,481),(454,515)], fill=(242,249,255,255))
d.polygon([(512,799),(573,515),(512,544),(454,515)], fill=(19,229,218,255))
d.ellipse((484,484,540,540), fill=(255,255,255,255))
im = im.convert("RGB")
outputs = [
    ('iphone','20x20',2,40),('iphone','20x20',3,60),
    ('iphone','29x29',2,58),('iphone','29x29',3,87),
    ('iphone','40x40',2,80),('iphone','40x40',3,120),
    ('iphone','60x60',2,120),('iphone','60x60',3,180),
    ('ipad','20x20',1,20),('ipad','20x20',2,40),
    ('ipad','29x29',1,29),('ipad','29x29',2,58),
    ('ipad','40x40',1,40),('ipad','40x40',2,80),
    ('ipad','76x76',1,76),('ipad','76x76',2,152),
    ('ipad','83.5x83.5',2,167),
]
assets=[]
for device,size,scale,pixels in outputs:
    fname=f"icon-{device}-{size.replace('.','_')}-{scale}x.png"
    im.resize((pixels,pixels),Image.Resampling.LANCZOS).save(OUT/fname, optimize=True)
    assets.append(dict(idiom=device, size=size, scale=f'{scale}x', filename=fname))
im.save(OUT/'icon-marketing-1024.png', optimize=True)
assets.append(dict(idiom='ios-marketing',size='1024x1024',scale='1x',filename='icon-marketing-1024.png'))
(OUT/'Contents.json').write_text(json.dumps({'images':assets,'info':{'author':'xcode','version':1}},indent=2)+'\n')
print(f'Generated {len(assets)} opaque icon sizes in {OUT}')
