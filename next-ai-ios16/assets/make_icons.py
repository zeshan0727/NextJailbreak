"""Render the original Next AI copper/teal vector-style mark at all iOS sizes."""
from PIL import Image, ImageDraw
from pathlib import Path
import math,sys
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent
root.mkdir(parents=True,exist_ok=True)
S=1536
im=Image.new('RGB',(S,S));px=im.load()
for y in range(S):
 for x in range(S):
  u=x/S;v=y/S
  teal=math.exp(-((u-.88)**2+(v-.1)**2)/.20)
  copper=math.exp(-((u-.05)**2+(v-.9)**2)/.23)
  px[x,y]=(int(10+19*copper+2*teal),int(17+23*teal+2*copper),int(24+24*teal))
d=ImageDraw.Draw(im)
def box(b):return tuple(round(v*S/1024) for v in b)
def line(points,fill,w):d.line([box(p) for p in points],fill=fill,width=round(w*S/1024),joint='curve')
d.ellipse(box((130,130,894,894)),outline='#263944',width=round(2*S/1024))
d.arc(box((160,160,864,864)),start=136,end=276,fill='#ed9556',width=round(15*S/1024))
d.arc(box((160,160,864,864)),start=316,end=456,fill='#43dbd0',width=round(15*S/1024))
# Strong N monogram with a copper diagonal and off-white uprights.
d.rounded_rectangle(box((302,336,376,686)),radius=round(28*S/1024),fill='#f7f1e8')
d.rounded_rectangle(box((646,336,720,686)),radius=round(28*S/1024),fill='#f7f1e8')
d.polygon([box(p) for p in [(370,342),(653,580),(653,682),(370,444)]],fill='#e88b50')
# Four-point intelligence spark, integrated into the orbit.
d.polygon([box(p) for p in [(777,191),(796,244),(850,264),(796,283),(777,337),(758,283),(704,264),(758,244)]],fill='#55e3d5')
d.ellipse(box((236,747,256,767)),fill='#eb9252')
for name,size in {'AppIcon60@2x.png':120,'AppIcon60@3x.png':180,'AppIcon76.png':76,'AppIcon76@2x.png':152,'AppIcon83.5@2x.png':167,'AppIcon40@2x.png':80,'AppIcon40@3x.png':120,'AppIcon20@2x.png':40,'AppIcon20@3x.png':60,'AppIcon29@2x.png':58,'AppIcon29@3x.png':87,'NextAI-Icon.png':1024}.items():im.resize((size,size),Image.Resampling.LANCZOS).save(root/name)
print('Rendered opaque RGB app icons.')
