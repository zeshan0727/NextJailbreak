"""Upgrade File Manager v1.2 sources to v1.3 AI document review."""
import base64
import hashlib
import io
import lzma
import re
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent
encoded = (root / "patch_v1_3.b64").read_text("ascii")
bundle = zipfile.ZipFile(io.BytesIO(lzma.decompress(base64.b64decode(encoded))))
patch = root / "_upgrade_v1_3.patch"
parts = re.split(r"(?=^--- a/)", bundle.read("upgrade.patch").decode("utf-8"), flags=re.M)
functional_patch = "".join(part for part in parts if part.startswith("--- a/filemanager/"))
patch.write_bytes(functional_patch.encode("utf-8"))
try:
    subprocess.run(["git", "apply", "--check", str(patch)], cwd=root, check=True)
    subprocess.run(["git", "apply", str(patch)], cwd=root, check=True)
finally:
    patch.unlink(missing_ok=True)

new_tests = root / "tests" / "test_ai_intake.py"
new_tests.parent.mkdir(parents=True, exist_ok=True)
new_tests.write_bytes(bundle.read("tests/test_ai_intake.py"))

expected = {
    "filemanager/core.py": "8dc024c16b5d7878e621429da8c755f8ac172ca8b719298db151c602b86a3538",
    "filemanager/gui.py": "b06cd062025c96455a36583dbedbffa934aad69b57b226aca4de703ba9eb2647",
    "filemanager/ai.py": "636fe731d33179ba569a6a6358634f67e62f9b82a972a4e95de886968ba330b7",
    "tests/test_ai_intake.py": "32f218c0757f46dd5adde3b00ca5c01b241741eb87e1b2ce2c783535a468e01d",
}
for filename, checksum in expected.items():
    actual = hashlib.sha256((root / filename).read_bytes()).hexdigest()
    if actual != checksum:
        raise RuntimeError(f"v1.3 source integrity mismatch: {filename}")

requirements = root / "requirements.txt"
text = requirements.read_text(encoding="utf-8")
for package in ("PyMuPDF>=1.24,<1.28", "Pillow>=11,<13"):
    if package.split(">=")[0].lower() not in text.lower():
        text += "\n" + package
requirements.write_text(text, encoding="utf-8")
print("SUCCESS: File Manager v1.3 automatic AI review sources are verified.")
