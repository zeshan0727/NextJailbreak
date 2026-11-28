#!/usr/bin/env python3
"""Prepare one independently built Module Glass 1.1.20 package variant."""

from pathlib import Path
import plistlib
import re
import sys

from generate_preferences import CATEGORIES, EXPECTED_SLOTS, build_preferences


VERSION = "1.1.20"
RUNTIME_PACKAGE = "com.nextsolution.nextaura.runtime.ccbackgrounds"


if len(sys.argv) != 3:
    raise SystemExit("usage: prepare_release.py PROJECT_DIR iphoneos-arm64|iphoneos-arm64e")

project = Path(sys.argv[1]).resolve()
architecture = sys.argv[2]
if architecture not in {"iphoneos-arm64", "iphoneos-arm64e"}:
    raise SystemExit(f"unsupported architecture: {architecture}")

bundle = project / "layout/Library/PreferenceBundles/ModuleGlassPrefs.bundle"
root_path = bundle / "CCModuleBackgrounds.plist"
info_path = bundle / "Info.plist"
control_path = project / "control"
for required in (info_path, control_path):
    if not required.exists():
        raise SystemExit(f"missing release input: {required}")

# Rebuild the native preference hierarchy so every package receives exactly the
# same category structure, keys, and actions.
build_preferences(bundle)

with root_path.open("rb") as stream:
    root = plistlib.load(stream)

base_items = list(root.get("items", []))
category_links = [item for item in base_items if item.get("cell") == "PSLinkCell"]
expected_links = [
    ("Core Modules", "ModuleGlassCoreModules"),
    ("Quick Controls", "ModuleGlassQuickControls"),
    ("Display & System", "ModuleGlassDisplaySystem"),
    ("Accessories & Apps", "ModuleGlassAccessoriesApps"),
    ("Other & Reset", "ModuleGlassOtherReset"),
]
actual_links = [(item.get("label"), item.get("plist")) for item in category_links]
if actual_links != expected_links:
    raise SystemExit(f"category link mismatch: {actual_links}")
if not base_items or base_items[-1].get("label") != "Respring":
    raise SystemExit("activation must follow the final Respring control")

slots = []
for filename in CATEGORIES:
    path = bundle / filename
    if not path.exists():
        raise SystemExit(f"missing category plist: {filename}")
    with path.open("rb") as stream:
        category = plistlib.load(stream)
    slots.extend(item["moduleSlot"] for item in category["items"] if "moduleSlot" in item)
if len(slots) != len(set(slots)) or set(slots) != EXPECTED_SLOTS:
    raise SystemExit(f"categorized module slot mismatch: {slots}")

activation_items = [
    {
        "cell": "PSGroupCell",
        "label": "ACTIVATION",
        "footerText": "Module Glass requires a $1 USD lifetime license for this generated Next Jailbreak Device ID. Activation and revocation use the live Module Glass license registry.",
    },
    {
        "cell": "PSTitleValueCell",
        "label": "Status",
        "defaults": "com.nextsolution.moduleglass",
        "key": "licenseStatusDisplay",
        "default": "Unactivated",
    },
    {
        "cell": "PSTitleValueCell",
        "label": "Device ID",
        "defaults": "com.nextsolution.moduleglass",
        "key": "licenseDeviceID",
        "default": "Generating…",
    },
    {"cell": "PSButtonCell", "label": "Copy Device ID", "action": "copyLicenseDeviceID"},
    {"cell": "PSButtonCell", "label": "Buy / Activate — $1.00", "action": "buyLicense"},
    {"cell": "PSButtonCell", "label": "Check Activation", "action": "checkActivation"},
]
root["items"] = base_items + activation_items
with root_path.open("wb") as stream:
    plistlib.dump(root, stream, fmt=plistlib.FMT_XML, sort_keys=False)

with info_path.open("rb") as stream:
    info = plistlib.load(stream)
info["CFBundleShortVersionString"] = VERSION
info["CFBundleVersion"] = VERSION
with info_path.open("wb") as stream:
    plistlib.dump(info, stream, fmt=plistlib.FMT_XML, sort_keys=False)

control = control_path.read_text()
replacements = {
    "Version": VERSION,
    "Architecture": architecture,
    "Description": (
        "Premium Control Center styling with independently selected module images, blur, opacity, glow, "
        "and Volume glyph color controls. Version 1.1.20 retains categorized native settings and "
        "Next Jailbreak branding while improving expansion and collapse recovery and live $1 lifetime activation."
    ),
    "Maintainer": "Next Jailbreak",
    "Author": "Next Jailbreak - Zeeshan Barvi",
    "Provides": f"{RUNTIME_PACKAGE} (= {VERSION})",
    "Conflicts": f"{RUNTIME_PACKAGE} (<= 1.1.19), com.nextsolution.unlockvibrate",
    "Breaks": f"{RUNTIME_PACKAGE} (<= 1.1.19)",
    "Replaces": f"{RUNTIME_PACKAGE} (<= 1.1.19)",
}
for field, value in replacements.items():
    pattern = rf"(?m)^{re.escape(field)}:.*$"
    if not re.search(pattern, control):
        raise SystemExit(f"missing control field: {field}")
    control = re.sub(pattern, f"{field}: {value}", control, count=1)
control_path.write_text(control)

# The color picker is rebuilt for each package scheme; never reuse the RootHide binary.
legacy_dir = project / "layout/Library/MobileSubstrate/DynamicLibraries"
for name in ("ModuleGlassStandalonePrefsExtension.dylib", "ModuleGlassStandalonePrefsExtension.plist"):
    path = legacy_dir / name
    if path.exists():
        path.unlink()

labels = [item.get("label") for item in root["items"][-6:]]
expected = ["ACTIVATION", "Status", "Device ID", "Copy Device ID", "Buy / Activate — $1.00", "Check Activation"]
if labels != expected:
    raise SystemExit(f"activation section order mismatch: {labels}")

print(
    f"Prepared Module Glass {VERSION} for {architecture}: "
    f"{len(EXPECTED_SLOTS)} modules in {len(CATEGORIES)} categories, activation last"
)
