from pathlib import Path

ROOT = Path("lara-src")

# The pinned LARA tree contains a few optional iOS 19/26 visual calls. They are
# unrelated to AppsDump and cannot be parsed by the Xcode 16.4 runner SDK.
# Removing only the glassEffect modifier leaves the normal SwiftUI fallback
# layout intact and does not touch DarkSword, sandbox escape or decrypt code.
for path in ROOT.rglob("*.swift"):
    text = path.read_text()
    if ".glassEffect(" not in text:
        continue
    lines = text.splitlines()
    filtered = [line for line in lines if ".glassEffect(" not in line]
    path.write_text("\n".join(filtered) + "\n")
    print(f"removed SDK-new glassEffect from {path}")

# Xcode 16.4 also diagnoses an unrelated MobileGestalt helper because its
# validation function calls a @MainActor alert object from a nonisolated
# function. AppsDump never uses this helper, so keep its validation behavior
# but remove the UI alerts from that one standalone function.
gestalt = ROOT / "lara" / "views" / "tweaks" / "mobilegestalt" / "GestaltView.swift"
text = gestalt.read_text()
marker = "func verifyPlist(_ plist: Any, targetPath: String) throws -> Data {"
if marker in text:
    prefix = text.split(marker, 1)[0]
    replacement = r'''func verifyPlist(_ plist: Any, targetPath: String) throws -> Data {
    let fm = FileManager.default

    if fm.fileExists(atPath: targetPath) {
        let attrs = try fm.attributesOfItem(atPath: targetPath)
        if let current = attrs[.size] as? NSNumber, current.intValue == 0 {
            throw "Current MobileGestalt file is 0 bytes."
        }
    }

    guard PropertyListSerialization.propertyList(plist, isValidFor: .binary) else {
        throw "Invalid plist structure."
    }

    let data = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .binary,
        options: 0
    )
    guard !data.isEmpty else {
        throw "Serialized plist data is empty."
    }

    _ = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    )
    return data
}
'''
    gestalt.write_text(prefix + replacement)
    print("patched unrelated Gestalt validation for Xcode 16.4")
else:
    raise SystemExit("Expected Gestalt verifyPlist helper was not found")
