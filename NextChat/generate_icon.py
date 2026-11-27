from pathlib import Path
from PIL import Image, ImageDraw
import json
root=Path(__file__).parent/'Assets.xcassets'
root.mkdir(exist_ok=True)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
out=root/'AppIcon.appiconset'
out.mkdir(exist_ok=True)
im=Image.new('RGB',(1024,1024))
d=ImageDraw.Draw(im)
for y in range(1024):
    t=y/1023
    d.line((0,y,1024,y), fill=(int(15+12*t),int(28+31*t),int(46+43*t)))
d.rounded_rectangle((192,230,832,725),radius=135,fill=(239,246,255))
d.polygon([(272,695),(272,831),(430,708)],fill=(239,246,255))
d.line((341,595,341,360,675,595,675,360),fill=(27,65,103),width=62,joint='curve')
im.save(out/'AppIcon.png')
(out/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
