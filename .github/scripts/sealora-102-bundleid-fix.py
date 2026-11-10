#!/usr/bin/env python3
"""Fix Sealora 1.0.1's false bundle-ID/profile mismatch for numeric suffixes."""
from pathlib import Path
import plistlib
import sys

root = Path(sys.argv[1]).resolve()

def replace_one(path: str, old: str, new: str) -> None:
    file = root / path
    source = file.read_text()
    if source.count(old) != 1:
        raise SystemExit(f"Refusing ambiguous Sealora patch: {path}, match count {source.count(old)}")
    file.write_text(source.replace(old, new))

replace_one(
    "Sealora/Core/Models.swift",
    r'let regex = "^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z][A-Za-z0-9-]*)+$"',
    r'let regex = "^[A-Za-z](?:[A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"'
)
replace_one(
    "Sealora/Features/SigningSheet.swift",
    """    private var matches: Bool {
        guard let profile else { return false }
        return BundleIDs.isValid(bundleID) && Self.accepts(pattern: profile.appIDPattern, id: bundleID)
    }
""",
    """    private var validationMessage: String? {
        guard let profile else { return "Select a provisioning profile to continue." }
        guard BundleIDs.isValid(bundleID) else {
            return "Invalid bundle identifier. Use letters, digits, periods and internal hyphens. Numeric app names such as 3105 are supported."
        }
        guard Self.accepts(pattern: profile.appIDPattern, id: bundleID) else {
            return "The selected provisioning profile does not authorize this bundle ID."
        }
        return nil
    }
    private var matches: Bool { validationMessage == nil }
"""
)
replace_one(
    "Sealora/Features/SigningSheet.swift",
    """                if !matches {
                    Section {
                        Label("The selected profile does not authorize this bundle ID.", systemImage: "exclamationmark.triangle.fill")
""",
    """                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
"""
)
replace_one(
    "Tests/SealoraTests.swift",
    '        XCTAssertTrue(BundleIDs.isValid("com.nextsolution.sealora"))\n',
    """        XCTAssertTrue(BundleIDs.isValid("com.nextsolution.sealora"))
        XCTAssertTrue(BundleIDs.isValid("com.nextsolution.3105"))
        XCTAssertTrue(BundleIDs.isValid("com.nextsolution.3105.copy2"))
        XCTAssertFalse(BundleIDs.isValid("com.nextsolution.-3105"))
        XCTAssertFalse(BundleIDs.isValid("com.nextsolution.3105-"))
"""
)
info = root / "Sealora/Info.plist"
data = plistlib.loads(info.read_bytes())
if data.get("CFBundleShortVersionString") != "1.0.1" or data.get("CFBundleVersion") != "2":
    raise SystemExit("Unexpected version in Sealora Info.plist; refusing patch")
data["CFBundleShortVersionString"] = "1.0.2"
data["CFBundleVersion"] = "3"
info.write_bytes(plistlib.dumps(data))
print("Sealora 1.0.2 validator patch applied; numeric bundle-ID segments allowed, strict profile validation preserved.")
