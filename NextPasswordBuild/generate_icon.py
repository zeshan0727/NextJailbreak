import struct, zlib

W = H = 1024
pixels = bytearray()
for y in range(H):
    pixels.append(0)
    for x in range(W):
        r, g, b = 17, 24, 39
        # blue rounded shield/body
        if 230 < x < 794 and 190 < y < 830:
            r, g, b = 37, 99, 235
        # white keyhole circle
        if (x - 512) ** 2 + (y - 435) ** 2 < 105 ** 2:
            r, g, b = 255, 255, 255
        # white keyhole stem
        if 470 < x < 554 and 500 < y < 690:
            r, g, b = 255, 255, 255
        # cyan key symbol accent
        if (x - 205) ** 2 + (y - 810) ** 2 < 48 ** 2 and (x - 205) ** 2 + (y - 810) ** 2 > 25 ** 2:
            r, g, b = 96, 165, 250
        if 245 < x < 390 and 798 < y < 824:
            r, g, b = 96, 165, 250
        if 326 < x < 352 and 805 < y < 875:
            r, g, b = 96, 165, 250
        pixels.extend((r, g, b))

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(pixels), 9))
png += chunk(b'IEND', b'')
with open('NextPassword/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', 'wb') as f:
    f.write(png)
