import math
import struct
import zlib
from pathlib import Path

size = 1024
target = Path("Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
target.parent.mkdir(parents=True, exist_ok=True)

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        r = math.hypot(x - 512, y - 515)
        if 230 < x < 794 and 180 < y < 844:
            red, green, blue = (25, 28, 37)
        else:
            red, green, blue = (13, 17, 27)
        if r < 354 and not (230 < x < 794 and 180 < y < 844):
            red, green, blue = (255, 137, 16)
        if 305 < x < 720 and 262 < y < 412:
            red, green, blue = (11, 16, 23)
        if 494 < x < 657 and (319 < y < 333 or 365 < y < 379):
            red, green, blue = (245, 247, 255)
        for cy in (522, 699):
            for cx in (355, 513, 672):
                if (x - cx) ** 2 + (y - cy) ** 2 < 4900:
                    red, green, blue = (255, 148, 38) if cx == 672 else (72, 77, 88)
        if (325 < x < 386 and 518 < y < 530) or (350 < x < 362 and 495 < y < 555):
            red, green, blue = (255, 255, 255)
        if (479 < x < 547 and 518 < y < 532) or (479 < x < 547 and 696 < y < 709):
            red, green, blue = (255, 255, 255)
        rows.extend((red, green, blue, 255))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows), level=7))
png += chunk(b"IEND", b"")
target.write_bytes(png)
print("Generated", target, target.stat().st_size, "bytes")
