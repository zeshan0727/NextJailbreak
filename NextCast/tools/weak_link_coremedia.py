#!/usr/bin/env python3
"""Make the optional Swift CoreMedia overlay weak for iOS 16.

Apple's iOS 16.0 dynamic linker doesn't provide libswiftCoreMedia.dylib.
Some newer Swift toolchains mark this overlay as a mandatory load even
though this app doesn't use it on iOS 16. Reclassify ONLY that precise
LC_LOAD_DYLIB command as LC_LOAD_WEAK_DYLIB, BEFORE code signing.

This is a packaging compatibility workaround, not a replacement dylib.
"""
import pathlib
import struct
import sys

TARGET = b"libswiftCoreMedia.dylib"
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018


def patch_slice(data: bytearray, base: int = 0) -> tuple[int, int]:
    if len(data) < base + 32:
        return (0, 0)
    magic = struct.unpack_from("<I", data, base)[0]
    if magic not in (0xFEEDFACF, 0xFEEDFACE):
        return (0, 0)
    is64 = magic == 0xFEEDFACF
    commands = struct.unpack_from("<I", data, base + 16)[0]
    cursor = base + (32 if is64 else 28)
    patched = 0
    seen = 0
    for _ in range(commands):
        if cursor + 24 > len(data):
            raise ValueError("Truncated Mach-O load command")
        command, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or cursor + size > len(data):
            raise ValueError("Invalid Mach-O command length")
        if command in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            name_offset = struct.unpack_from("<I", data, cursor + 8)[0]
            if 24 <= name_offset < size:
                name = bytes(data[cursor + name_offset:cursor + size]).split(b"\0")[0]
                if TARGET in name:
                    seen += 1
                    if command == LC_LOAD_DYLIB:
                        struct.pack_into("<I", data, cursor, LC_LOAD_WEAK_DYLIB)
                        patched += 1
        cursor += size
    return patched, seen


def patch_file(file: pathlib.Path) -> tuple[int, int]:
    data = bytearray(file.read_bytes())
    if not data:
        return (0, 0)
    patched, seen = patch_slice(data)
    # Fat binary format: big-endian FAT_MAGIC/FAT_MAGIC_64
    if not seen and len(data) >= 8 and data[:4] in (b"\xCA\xFE\xBA\xBE", b"\xCA\xFE\xBA\xBF"):
        is64 = data[:4] == b"\xCA\xFE\xBA\xBF"
        count = struct.unpack_from(">I", data, 4)[0]
        stride = 32 if is64 else 20
        for i in range(count):
            entry = 8 + stride * i
            offset = struct.unpack_from(">Q" if is64 else ">I", data, entry + 8)[0]
            p, n = patch_slice(data, offset)
            patched += p
            seen += n
    if patched:
        file.write_bytes(data)
    return patched, seen


def main(folder: pathlib.Path) -> None:
    executable = folder / "NextCast"
    if not executable.exists():
        raise SystemExit("Missing NextCast executable.")
    scanned = 0
    patched_count = 0
    seen_count = 0
    for f in [executable, *folder.glob("Frameworks/**/*.framework/*"),
              *folder.glob("Frameworks/**/*.dylib")]:
        if not f.is_file() or f.is_symlink():
            continue
        scanned += 1
        patched, seen = patch_file(f)
        patched_count += patched
        seen_count += seen
        if seen:
            print(f"{f}: {patched} required Swift CoreMedia loads changed to weak; {seen} total")
    if not seen_count:
        print("No Swift CoreMedia dependency found; no patch required.")
    print(f"Audited {scanned} files; modified {patched_count} load commands.")
    for f in [executable, *folder.glob("Frameworks/**/*.framework/*"),
              *folder.glob("Frameworks/**/*.dylib")]:
        if f.is_file() and not f.is_symlink():
            data = bytearray(f.read_bytes())
            # Idempotence check: no remaining mandatory CoreMedia imports.
            p, seen = patch_slice(data)
            if p:
                raise SystemExit(f"ERROR: required dylib dependency remains in {f}")
    if seen_count and patched_count:
        print("Weak linking patched. Re-sign the entire application after this step.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: weak_link_coremedia.py NextCast.app")
    main(pathlib.Path(sys.argv[1]))
