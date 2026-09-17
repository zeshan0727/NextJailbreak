#!/usr/bin/env python3
"""Publish exactly one verified original-source article: Cyanide 1.6.0."""
from automation import publish_verified_batch_20260916 as batch

batch.TARGETS = [{
    "name": "Cyanide",
    "version": "1.6.0",
    "package_id": "cyanide",
    "description": "iOS tweak runner built on the DarkSword kernel read/write primitive, applying supported tweaks in memory for the current boot.",
    "urls": [
        "https://github.com/kolbicz/Cyanide/releases/tag/v1.6.0",
        "https://github.com/kolbicz/Cyanide",
        "https://raw.githubusercontent.com/kolbicz/Cyanide/main/RELEASE_NOTES.md",
        "https://raw.githubusercontent.com/kolbicz/Cyanide/main/README.md",
        "https://raw.githubusercontent.com/kolbicz/Cyanide/main/Cyanide/Assets.xcassets/AppIcon.appiconset/icon-ios-1024x1024.png",
    ],
    "github": [("kolbicz", "Cyanide")],
    "scope_note": (
        "SOURCE-SCOPE NOTE: Cover only Cyanide 1.6.0 claims documented by the developer. "
        "Lead with kernel access being handed to launchd so a successful primitive can survive closing Cyanide and be recovered quickly on the next Run. "
        "Also cover read-only controls no longer starting a fresh exploit, OTA Updates becoming a manual Settings tool, the Settings-return flash fix, and the developer's explicit A18/M4 panic warning. "
        "State exact support as iOS/iPadOS 17.0-18.7.1 and 26.0-26.0.1; iPhone 17/A19 and M5 are not supported. "
        "Do not call Cyanide a full jailbreak: the developer describes it as a tweak runner and says tweaks are applied in memory for the current boot."
    ),
}]

if __name__ == "__main__":
    raise SystemExit(batch.main())
