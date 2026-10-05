#!/usr/bin/env python3
"""Build a lightweight 1200x630 JPEG social card for WhatsApp/Open Graph crawlers."""

from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "brand" / "next-jailbreak-social-card.png"
TARGET = ROOT / "assets" / "brand" / "next-jailbreak-social-card-whatsapp.jpg"
TARGET_SIZE = (1200, 630)
MAX_BYTES = 220 * 1024


def render_bytes(image: Image.Image, quality: int) -> bytes:
    from io import BytesIO

    buf = BytesIO()
    image.save(
        buf,
        format="JPEG",
        quality=quality,
        optimize=True,
        progressive=True,
        subsampling="4:2:0",
    )
    return buf.getvalue()


def main() -> int:
    if not SOURCE.is_file():
        raise SystemExit(f"missing source social card: {SOURCE}")

    with Image.open(SOURCE) as src:
        rgb = src.convert("RGB")
        if rgb.size != TARGET_SIZE:
            rgb = ImageOps.fit(rgb, TARGET_SIZE, method=Image.Resampling.LANCZOS)

        payload = b""
        used_quality = 76
        for quality in (76, 72, 68, 64, 60, 56, 52, 48, 44):
            payload = render_bytes(rgb, quality)
            used_quality = quality
            if len(payload) <= MAX_BYTES:
                break

    if len(payload) > MAX_BYTES:
        raise SystemExit(f"optimized card is still too large: {len(payload)} bytes")

    if TARGET.exists() and TARGET.read_bytes() == payload:
        print(f"social card already optimized ({len(payload)} bytes, q={used_quality})")
        return 0

    TARGET.write_bytes(payload)
    print(f"wrote {TARGET.relative_to(ROOT)} ({len(payload)} bytes, q={used_quality})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
