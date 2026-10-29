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
dg.ellipse((-340,-480,1420,1290),fill=(24,229,203,50))
glow=glow.filter(ImageFilter.GaussianBlur(290))
base=Image.alpha_composite(base,glow)

def box(x): return int(x*SCALE)
def rounded_rect(draw,bounds,r,fill,outline=None,width=1):
    draw.rounded_rectangle(tuple(map(box,bounds)),radius=box(r),fill=fill,
                           outline=outline,width=box(width))
draw=ImageDraw.Draw(base,"RGBA")

# Chrome glass plate / app-storage silhouette.
rounded_rect(draw,(181,196,796,826),157,(20,61,81,175))
rounded_rect(draw,(201,216,776,806),135,(15,48,68,190),
             outline=(103,245,222,95),width=3)

# Translucent top storage disk.
rounded_rect(draw,(291,316,680,414),37,(190,255,241,250))
rounded_rect(draw,(291,448,680,546),37,(104,242,214,239))
rounded_rect(draw,(291,580,680,678),37,(33,183,168,230))

# Dark slots, showing drive activity bars.
for y in (346,478,610):
    rounded_rect(draw,(330,y,523,y+32),14,(12,76,89,205))
    draw.ellipse((box(596),box(y+8),box(614),box(y+26)),fill=(13,78,90,230))

# Magnifying glass over lower-right drive; lifted from the disk.
draw.ellipse((box(566),box(520),box(854),box(808)),fill=(6,34,49,242))
draw.ellipse((box(584),box(538),box(836),box(790)),outline=(230,255,251,255),width=box(31))
draw.line((box(811),box(763),box(905),box(865)),fill=(218,255,247,255),width=box(46),joint="curve")
draw.ellipse((box(873),box(844),box(922),box(893)),fill=(218,255,247,255))

out=base.convert("RGB").resize((SIZE,SIZE),Image.Resampling.LANCZOS)
path=folder/"AppIcon-1024.png"
out.save(path,format="PNG",optimize=True)
manifest={"images":[{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],
          "info":{"author":"xcode","version":1}}
(folder/"Contents.json").write_text(json.dumps(manifest,indent=2)+"\n")
print(f"Generated {path} ({path.stat().st_size} bytes)")
