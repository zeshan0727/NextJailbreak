#!/usr/bin/env python3
"""Preflight for the single Next Ledger App Store candidate (Build 112).

This is intentionally read-only. It does not rewrite the bundle ID, remove
features, sign builds, access financial data or make App Store submissions.
"""
from __future__ import annotations

import json
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_ID = "com.nextsolution.dailyledger"
WIDGET_ID = APP_ID + ".widgets"
ICLOUD = "iCloud.com.nextsolution.dailyledger"
TEAM = "T52CDY8W32"
VERSION = "1.3.84"
BUILD = "112"


def ensure(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError("App Store preflight failed: " + message)


def file(path: str) -> pathlib.Path:
    item = ROOT / path
    ensure(item.exists(), f"Missing {path}")
    return item


def main() -> None:
    project = file("project.yml").read_text(encoding="utf-8")
    for value in (
        "name: NextLedger",
        "  NextLedger:\n",
        f"PRODUCT_BUNDLE_IDENTIFIER: {APP_ID}",
        f"PRODUCT_BUNDLE_IDENTIFIER: {WIDGET_ID}",
        f"DEVELOPMENT_TEAM: {TEAM}",
        f'MARKETING_VERSION: "{VERSION}"',
        f'CURRENT_PROJECT_VERSION: "{BUILD}"',
        'iOS: "16.0"',
        "CODE_SIGN_STYLE: Automatic",
        "- target: DailyLedgerWidgets",
        "PrivacyInfo",
    ):
        if value == "PrivacyInfo":
            continue
        ensure(value in project, f"Project missing {value!r}")
    ensure("PRODUCT_BUNDLE_IDENTIFIER: com.nextsolution.nextledger\n" not in project,
           "Don't change the existing bundle ID before checking App Store Connect")
    ensure(not file("DailyLedger/Assets/NextSolutionLogoAsset.swift").is_file()
           if (ROOT / "DailyLedger/Assets/NextSolutionLogoAsset.swift").exists()
           else True, "Old studio logo still bundled")

    info = plistlib.loads(file("DailyLedger/Info.plist").read_bytes())
    ensure(info.get("CFBundleDisplayName") == "Next Ledger", "Wrong Home Screen name")
    ensure(ICLOUD in info.get("NSUbiquitousContainers", {}), "Original iCloud backup container lost")
    expected_task = APP_ID + ".backup-refresh"
    ensure(expected_task in info.get("BGTaskSchedulerPermittedIdentifiers", []),
           "Wrong background backup refresh identifier")

    for path in ("DailyLedger/DailyLedger.entitlements",
                 "DailyLedgerWidgets/NextLedgerWidgets.entitlements"):
        ent = plistlib.loads(file(path).read_bytes())
        ensure(ICLOUD in ent.get("com.apple.developer.icloud-container-identifiers", []),
               f"{path} lacks iCloud container")
        ensure("CloudDocuments" in ent.get("com.apple.developer.icloud-services", []),
               f"{path} lacks CloudDocuments")

    for path in ("DailyLedger/PrivacyInfo.xcprivacy",
                 "DailyLedgerWidgets/PrivacyInfo.xcprivacy"):
        data = plistlib.loads(file(path).read_bytes())
        types = data.get("NSPrivacyAccessedAPITypes", [])
        ensure(any(
            x.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
            and "CA92.1" in x.get("NSPrivacyAccessedAPITypeReasons", [])
            for x in types
        ), f"Missing application-preferences API reason in {path}")

    icon = json.loads(file("DailyLedger/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text())
    ensure(any(img.get("filename") == "icon-1024.png" for img in icon["images"]),
           "1024x1024 App Store icon missing")
    file("DailyLedger/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    file("DailyLedgerWidgets/UpcomingPaymentsWidget.swift")
    file("Shared/NextLedgerWidgetSnapshot.swift")

    banned = ("next jailbreak", "nextjailbreak", "next-jailbreak",
              "next solution", "trollstore", "roothide", "cydia", "sileo")
    found = []
    for folder in ("DailyLedger", "DailyLedgerWidgets"):
        for item in (ROOT / folder).rglob("*"):
            if item.suffix not in (".swift", ".json", ".plist", ".xcprivacy"):
                continue
            body = item.read_bytes().lower()
            for term in banned:
                if term.encode("utf-8") in body:
                    found.append((str(item.relative_to(ROOT)), term))
    ensure(not found, "Old studio/jailbreak strings: " + str(found[:25]))
    print("PASS: Next Ledger Build 112 App Store identity, iCloud backups, widgets, brand and privacy API declarations")
    print("NOTE: Before submitting, confirm Apple app record bundle ID, public privacy policy URL,")
    print("      App Store privacy answers (including third-party AI), screenshots and reviewer access.")


if __name__ == "__main__":
    main()
