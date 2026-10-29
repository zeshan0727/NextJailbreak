#!/usr/bin/env python3
"""Deterministic 1024px iOS home-screen icon for Next Storage.
No external assets, logos, glyph fonts, or runtime network.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math, json

SIZE=1024
SCALE=2
W=SIZE*SCALE
root=Path(__file__).resolve().parents[1]
folder=root/"Assets.xcassets"/"AppIcon.appiconset"
folder.mkdir(parents=True,exist_ok=True)

# Full bleed for iOS: the system rounds icon corners at display time.
base=Image.new("RGBA",(W,W))
px=base.load()
for y in range(W):
    for x in range(W):
        u=x/W
        v=y/W
        radial=max(0.0,1.0-math.hypot((u-.25)*1.05,(v-.12)*.83))
        px[x,y]=(int(8+17*radial+3*(1-v)),int(19+35*radial+9*(1-u)),int(39+48*radial+18*v),255)

# Subtle upper-left cyan ambient illumination, blurred into the background.
glow=Image.new("RGBA",(W,W),(0,0,0,0))
dg=ImageDraw.Draw(glow)
dg.ellipse((-340,-480,1420,1290),fill=(0,115,255,70))
glow=glow.filter(ImageFilter.GaussianBlur(290))
base=Image.alpha_composite(base,glow)

def box(x): return int(x*SCALE)
def rounded_rect(draw,bounds,r,fill,outline=None,width=1):
    draw.rounded_rectangle(tuple(map(box,bounds)),radius=box(r),fill=fill,
                           outline=outline,width=box(width))
draw=ImageDraw.Draw(base,"RGBA")

# Chrome glass plate / app-storage silhouette.
rounded_rect(draw,(181,196,796,826),157,(11,66,179,200))
rounded_rect(draw,(201,216,776,806),135,(7,83,200,225),
             outline=(69,194,255,160),width=3)

# Translucent top storage disk.
rounded_rect(draw,(291,316,680,414),37,(245,253,255,250))
rounded_rect(draw,(291,448,680,546),37,(149,216,255,242))
rounded_rect(draw,(291,580,680,678),37,(46,142,249,235))

# Dark slots, showing drive activity bars.
for y in (346,478,610):
    rounded_rect(draw,(330,y,523,y+32),14,(12,83,180,215))
    draw.ellipse((box(596),box(y+8),box(614),box(y+26)),fill=(19,106,190,230))

# Magnifying glass over lower-right drive; lifted from the disk.
draw.ellipse((box(566),box(520),box(854),box(808)),fill=(11,62,173,246))
draw.ellipse((box(584),box(538),box(836),box(790)),outline=(247,253,255,255),width=box(31))
draw.line((box(811),box(763),box(905),box(865)),fill=(251,254,255,255),width=box(46),joint="curve")
draw.ellipse((box(873),box(844),box(922),box(893)),fill=(251,254,255,255))

out=base.convert("RGB").resize((SIZE,SIZE),Image.Resampling.LANCZOS)
path=folder/"AppIcon-1024.png"
out.save(path,format="PNG",optimize=True)
manifest={"images":[{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],
          "info":{"author":"xcode","version":1}}
(folder/"Contents.json").write_text(json.dumps(manifest,indent=2)+"\n")
print(f"Generated {path} ({path.stat().st_size} bytes)")
