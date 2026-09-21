from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
modern_ui = modern_ui_path.read_text()

s = s.replace(
    "Next Agent 0.7.8 is ready with SpringBoard-native OCR and enforced split workspace for interactive app tasks.",
    "Next Agent 0.7.9 is ready with a generation-locked SpringBoard OCR bridge and enforced split workspace."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.8-sbocr-split2"',
    'private static let currentToolSchemaVersion = "0.7.9-sbocr-split3"'
)
s = s.replace('"client_version": "0.7.8"', '"client_version": "0.7.9"')

old_direct = '''            results.append([
                "tool": "direct_screen_bridge",
                "success": (directBridge["success"] as? Bool) == true,
                "output": String(describing: directBridge)
            ])
'''
new_direct = '''            let transportVersion = directBridge["transport_version"] as? String ?? ""
            results.append([
                "tool": "direct_screen_bridge",
                "success": (directBridge["success"] as? Bool) == true
                    && transportVersion == "0.7.9-cfmessageport1",
                "output": String(describing: directBridge)
            ])
'''
if old_direct not in router:
    raise SystemExit("v0.7.9 direct bridge self-test marker missing")
router = router.replace(old_direct, new_direct, 1)

old_ocr = '''        let ocrCount = (ocrRaw["count"] as? NSNumber)?.intValue ?? 0
        results.append([
            "tool": "direct_ocr_bridge",
            "success": (ocrRaw["success"] as? Bool) == true && ocrCount > 0,
            "output": String(describing: ocrRaw)
        ])
'''
new_ocr = '''        let ocrCount = (ocrRaw["count"] as? NSNumber)?.intValue ?? 0
        let ocrTransportVersion = ocrRaw["transport_version"] as? String ?? ""
        results.append([
            "tool": "direct_ocr_bridge",
            "success": (ocrRaw["success"] as? Bool) == true
                && ocrCount > 0
                && ocrTransportVersion == "0.7.9-springboard-vision1",
            "output": String(describing: ocrRaw)
        ])
'''
if old_ocr not in router:
    raise SystemExit("v0.7.9 OCR self-test marker missing")
router = router.replace(old_ocr, new_ocr, 1)

old_split = '''        results.append([
            "tool": "split_workspace_capability",
            "success": (splitCapabilityRaw["success"] as? Bool) == true,
            "output": String(describing: splitCapabilityRaw)
        ])
'''
new_split = '''        let splitBridgeVersion = splitCapabilityRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "split_workspace_capability",
            "success": (splitCapabilityRaw["success"] as? Bool) == true
                && splitBridgeVersion == "0.7.9",
            "output": String(describing: splitCapabilityRaw)
        ])
'''
if old_split not in router:
    raise SystemExit("v0.7.9 split self-test marker missing")
router = router.replace(old_split, new_split, 1)

router = router.replace(
    '"router_version": "0.7.8-sbocr-split2"',
    '"router_version": "0.7.9-sbocr-split3"'
)

modern_ui = modern_ui.replace(
    "0.7.8 • RootHide • SpringBoard OCR • Enforced Split",
    "0.7.9 • RootHide • Locked Bridge • SpringBoard OCR"
)

swift_path.write_text(s)
router_path.write_text(router)
modern_ui_path.write_text(modern_ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.8", "MARKETING_VERSION: 0.7.9")
y = y.replace("CURRENT_PROJECT_VERSION: 16", "CURRENT_PROJECT_VERSION: 17")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.9"
d["CFBundleVersion"] = "17"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.9-sbocr-split3"' in swift_path.read_text()
assert 'transportVersion == "0.7.9-cfmessageport1"' in router_path.read_text()
assert 'ocrTransportVersion == "0.7.9-springboard-vision1"' in router_path.read_text()
assert 'splitBridgeVersion == "0.7.9"' in router_path.read_text()
assert "MARKETING_VERSION: 0.7.9" in project.read_text()
