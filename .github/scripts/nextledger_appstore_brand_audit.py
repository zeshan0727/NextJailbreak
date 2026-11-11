#!/usr/bin/env python3
"""Prepare and audit an isolated Next Ledger 1.3.84 (106) App Store build.

Never run against the user's private-install branch in place. GitHub Actions
checks out the feature branch into its disposable runner workspace.
"""
from __future__ import annotations
import argparse
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path.cwd()
APP_BUNDLE_ID = "com.nextsolution.nextledger"
SOURCE_BUNDLE_ID = "com.nextsolution.dailyledger"
ICLOUD_CONTAINER = "iCloud.com.nextsolution.dailyledger"
VERSION = "1.3.84"
BUILD = "106"
TEAM_ID = "T52CDY8W32"

BANNED = (
    b"nextjailbreak", b"next jailbreak", b"next-jailbreak",
    b"nextsolution.cc", b"nextsolution.com", b"files.nextsolution",
    b"next solution", b"trollstore", b"roothide", b"cydia", b"sileo",
)
# The old brand is prohibited in end-user text, but the com.nextsolution.*
# developer identifiers and legacy iCloud container MUST remain unchanged.


def require(cond: bool, message: str) -> None:
    if not cond:
        raise RuntimeError(message)


def update_exact(path: str, old: str, new: str, expected: int = 1) -> None:
    p = ROOT / path
    original = p.read_text(encoding="utf-8")
    count = original.count(old)
    require(count == expected, f"{path}: expected {expected} matches, found {count}: {old[:100]!r}")
    p.write_text(original.replace(old, new), encoding="utf-8")


def prepare() -> None:
    config = (ROOT / "project.yml").read_text(encoding="utf-8")
    require(f'MARKETING_VERSION: "{VERSION}"' in config, "Wrong marketing version")
    require(f'CURRENT_PROJECT_VERSION: "{BUILD}"' in config, "Wrong build")
    update_exact("project.yml",
                 f"PRODUCT_BUNDLE_IDENTIFIER: {SOURCE_BUNDLE_ID}",
                 f"PRODUCT_BUNDLE_IDENTIFIER: {APP_BUNDLE_ID}")
    update_exact("project.yml", "    CODE_SIGN_STYLE: Automatic",
                 f"    CODE_SIGN_STYLE: Automatic\n    DEVELOPMENT_TEAM: {TEAM_ID}")
    old_task = f"{SOURCE_BUNDLE_ID}.backup-refresh"
    new_task = f"{APP_BUNDLE_ID}.backup-refresh"
    for path in ("DailyLedger/Info.plist", "DailyLedger/Services/BackupSyncService.swift"):
        p = ROOT / path
        source = p.read_text(encoding="utf-8")
        require(old_task in source, f"Missing original background task in {path}")
        p.write_text(source.replace(old_task, new_task), encoding="utf-8")

    dashboard = ROOT / "DailyLedger/Views/DashboardView.swift"
    source = dashboard.read_text(encoding="utf-8")
    pattern = r"private struct NextSolutionHeaderLogo: View \{.*?\n\}\n\n(?=struct DashboardView: View \{)"
    replacement = """private struct LedgerHeaderMark: View {
    var body: some View {
        Image(systemName: "chart.bar.xaxis")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(AppTheme.balanceGradient)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .accessibilityLabel("Next Ledger")
    }
}

"""
    source, num = re.subn(pattern, replacement, source, count=1, flags=re.DOTALL)
    require(num == 1 and source.count("NextSolutionHeaderLogo()") == 1,
            "Cannot safely neutralize old dashboard branding")
    source = source.replace("NextSolutionHeaderLogo()", "LedgerHeaderMark()")
    dashboard.write_text(source, encoding="utf-8")

    # This source file embeds the old studio logo image. Excluding it at the
    # source stage also ensures its image bytes are not compiled into the app.
    old_logo = ROOT / "DailyLedger/Assets/NextSolutionLogoAsset.swift"
    require(old_logo.is_file(), "Legacy logo asset expected but missing")
    old_logo.unlink()

    update_exact("DailyLedger/Views/SettingsView.swift",
                 'LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")', "")
    update_exact("DailyLedger/Services/ProfessionalReportExportService.swift",
                 'kCGPDFContextAuthor as String: "Next Solution – Zeeshan Barvi"',
                 'kCGPDFContextAuthor as String: "Next Ledger"')
    svc = ROOT / "DailyLedger/Services/OpenAIService.swift"
    s = svc.read_text(encoding="utf-8")
    s = re.sub(r"        // The protected app store is the reliable source of truth for TrollStore\n"
               r"        // and rootless installs\. If Keychain entitlement behavior differs, the\n"
               r"        // OpenAI key still persists securely inside this device/app container\.\n",
               "        // Store the user-provided API key in protected local storage.\n",
               s, count=1)
    svc.write_text(s, encoding="utf-8")

    p = ROOT / "DailyLedger/DailyLedger.entitlements"
    entitlements = plistlib.loads(p.read_bytes())
    require(ICLOUD_CONTAINER in entitlements.get("com.apple.developer.icloud-container-identifiers", []),
            "Existing iCloud Documents container lost")
    require("CloudDocuments" in entitlements.get("com.apple.developer.icloud-services", []),
            "CloudDocuments entitlement missing")
    info = plistlib.loads((ROOT / "DailyLedger/Info.plist").read_bytes())
    require(ICLOUD_CONTAINER in info.get("NSUbiquitousContainers", {}), "iCloud document scope lost")
    source_audit()
    print("PASS: Build 106 isolated App Store branding preparation; iCloud preserved")


def source_audit() -> None:
    require(not (ROOT / "DailyLedger/Assets/NextSolutionLogoAsset.swift").exists(),
            "Legacy embedded brand image still in source")
    violations = []
    for p in sorted((ROOT / "DailyLedger").rglob("*")):
        if p.suffix.lower() not in (".swift", ".plist", ".entitlements", ".json"):
            continue
        data = p.read_bytes().lower()
        for term in BANNED:
            if term in data:
                violations.append((str(p.relative_to(ROOT)), term.decode()))
    require(not violations, f"Prohibited end-user branding/references in release source: {violations}")
    print("PASS: no jailbreak/site/studio brand strings in App Store release source")


def app_audit(app: pathlib.Path) -> None:
    require(app.is_dir() and app.suffix == ".app", "Expected an extracted .app directory")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == APP_BUNDLE_ID, "Incorrect App Store Bundle ID")
    require(info.get("CFBundleShortVersionString") == VERSION, "Wrong marketing version")
    require(info.get("CFBundleVersion") == BUILD, "Wrong build")
    require(ICLOUD_CONTAINER in info.get("NSUbiquitousContainers", {}), "iCloud document scope lost")
    require(info.get("BGTaskSchedulerPermittedIdentifiers", [None])[0] ==
            f"{APP_BUNDLE_ID}.backup-refresh", "Background task uses old app ID")
    violations = []
    for p in app.rglob("*"):
        if not p.is_file() or p.is_symlink():
            continue
        # Compiled machine code, strings, JSON, asset catalogs, embedded frameworks,
        # and other packaged resources must all pass the same audit.
        data = p.read_bytes().lower()
        for term in BANNED:
            if term in data:
                i = data.find(term)
                sample = data[max(0, i - 90):i + len(term) + 130]
                sample = "".join(chr(c) if 32 <= c < 127 else "." for c in sample)
                violations.append((str(p.relative_to(app)), term.decode(), sample))
    require(not violations, f"Packaged app contains forbidden wording/links: {violations}")
    print(f"PASS: compiled {VERSION} ({BUILD}) App Store app has no prohibited brand or site strings")


def main() -> None:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--source-audit", action="store_true")
    mode.add_argument("--app-audit", metavar="APP_PATH", type=pathlib.Path)
    opts = parser.parse_args()
    if opts.prepare:
        prepare()
    elif opts.source_audit:
        source_audit()
    else:
        app_audit(opts.app_audit)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"APP STORE RELEASE BLOCKED: {exc}", file=sys.stderr)
        sys.exit(1)
