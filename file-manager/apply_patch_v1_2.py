"""Apply the exact reviewed File Manager v1.2 update to the v1.1 build source.
This file is used only in the isolated Windows build pipeline.
"""
import base64
import hashlib
import json
import lzma
from pathlib import Path

root = Path(__file__).resolve().parent
delta = json.loads(lzma.decompress(base64.b64decode((root / "patch_v1_2.b64").read_text("ascii"))))
expected = {
    "filemanager/core.py": "0190fb2ea8e21d5e48edd1faed2a959b847a2e9e56de856f6444e2fdd85cdaf3",
    "filemanager/gui.py": "da6d8d78744882a55ba6e34bfa0a47efaa7d02fb2e96475a26c6b2280d7e3303",
    "filemanager/ai.py": "7a5a5e43d68d2cb3a12f8e0af2131a4f484cac51fdfda6b0aa99902086fae636",
    "tests/test_core.py": "1336a6b7529928cd0770456e0cac38bcda570ea3da631f38ba25194b7c9e7912",
}
for name, edits in delta.items():
    file = root / name
    lines = file.read_bytes().decode("utf-8").splitlines(keepends=True)
    for start, end, replacement in reversed(edits):
        lines[start:end] = replacement.splitlines(keepends=True)
    content = "".join(lines).encode("utf-8")
    if name in expected and hashlib.sha256(content).hexdigest() != expected[name]:
        raise RuntimeError("Patch checksum mismatch for " + name)
    file.write_bytes(content)
    print("Updated", name, len(content), "bytes")
print("File Manager v1.2 verified patch applied.")
