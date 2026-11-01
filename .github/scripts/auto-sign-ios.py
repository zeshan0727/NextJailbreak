#!/usr/bin/env python3
"""Fail-closed metadata and entitlement checks for Next automatic iOS signing.

Only called on artifacts produced by trusted main-branch app-build workflows.
Never prints private certificate/profile material.
"""
import hashlib
import os
import plistlib
import re
import sys
import zipfile
from pathlib import Path


def fail(message):
    raise SystemExit("Next Auto Sign: " + message)


def emit(**values):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
        for key, value in values.items():
            print(f"{key}={value}", file=stream)


def clean(value):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", str(value)).strip(".-") or "unknown"


def inspect():
    root = Path(os.environ["ARTIFACT_DIRECTORY"])
    ipas = sorted(root.rglob("*.ipa"))
    tipas = sorted(root.rglob("*.tipa"))
    # .ipa takes precedence if the artifact contains both identical formats.
    files = ipas if ipas else tipas
    if len(files) != 1:
        fail(f"Expected exactly one IPA (or one TIPA), found {len(files)}.")
    package = files[0]
    if not package.is_file() or package.stat().st_size < 1024:
        fail("Package missing or unreasonably small.")
    with zipfile.ZipFile(package) as z:
        if z.testzip() is not None:
            fail("IPA archive checksum validation failed.")
        names = z.namelist()
        if len(names) != len(set(names)):
            fail("IPA has duplicate ZIP entries.")
        info_paths = [
            path for path in names
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", path)
        ]
        if len(info_paths) != 1:
            fail("Expected one main app Info.plist in Payload.")
        info = plistlib.loads(z.read(info_paths[0]))
        if any("/PlugIns/" in n and ".appex/" in n for n in names):
            fail("App extensions need separate App ID/profile mapping; not automatically signed.")
        bundle = info.get("CFBundleIdentifier")
        version = str(info.get("CFBundleShortVersionString") or "")
        build = str(info.get("CFBundleVersion") or "")
        name = str(info.get("CFBundleDisplayName") or info.get("CFBundleName") or bundle)
        if not bundle or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
            fail("Invalid app bundle identifier.")
        if os.environ.get("EXPECTED_BUNDLE_ID") and bundle != os.environ["EXPECTED_BUNDLE_ID"]:
            fail(f"Bundle ID mismatch: expected {os.environ['EXPECTED_BUNDLE_ID']}, got {bundle}.")
        if not version or not build:
            fail("Missing version or build metadata.")
        if any(path.endswith("/embedded.mobileprovision") for path in names):
            print("Note: package already contains a profile; it will be replaced by the selected signing profile.")
        cloud_info = bool(info.get("NSUbiquitousContainers"))
        cloud_info = cloud_info or bool(info.get("NSUbiquitousContainerIdentifiers"))

    checksum_files = list(root.rglob("*.sha256"))
    expected_hashes = []
    for checksum in checksum_files:
        for line in checksum.read_text(errors="replace").splitlines():
            parts = line.strip().split()
            if len(parts) >= 2 and parts[1].lstrip("*").split("/")[-1] == package.name:
                expected_hashes.append(parts[0].lower())
    actual = hashlib.file_digest(package.open("rb"), "sha256").hexdigest()
    if expected_hashes and any(h != actual for h in expected_hashes):
        fail("Original package SHA-256 did not match the artifact manifest.")

    entitlement_files = sorted(root.rglob("*.entitlements"))
    if len(entitlement_files) > 1:
        fail("Multiple entitlement files: choose one signing-capability source.")
    entitlement_dest = Path(os.environ["RUNNER_TEMP"]) / "auto-sign-entitlements.plist"
    if entitlement_files:
        requested = plistlib.loads(entitlement_files[0].read_bytes())
        if not isinstance(requested, dict):
            fail("Entitlements must be a plist dictionary.")
        if any(k.startswith("com.apple.private.") or k == "platform-application" for k in requested):
            fail("Private/jailbreak-only entitlements cannot be signed by an ordinary Apple profile.")
        entitlement_dest.write_bytes(plistlib.dumps(requested))
    elif cloud_info:
        fail("iCloud app has no exported .entitlements file; refusing to remove iCloud capability.")
    else:
        # A custom empty plist forces existing Next Signer to derive and validate
        # the full concrete entitlement set from the selected provisioning profile.
        entitlement_dest.write_bytes(plistlib.dumps({}))

    source_dest = Path(os.environ["RUNNER_TEMP"]) / "auto-sign-input.ipa"
    source_dest.write_bytes(package.read_bytes())
    emit(
        REQUESTED_BUNDLE_ID=bundle,
        APP_NAME=name.replace("\n", " ").replace("\r", " "),
        APP_VERSION=version,
        APP_BUILD=build,
        APP_SLUG=clean(bundle.lower()),
        APP_VERSION_SLUG=clean(version),
        APP_BUILD_SLUG=clean(build),
        CUSTOM_ENTITLEMENTS_PATH=str(entitlement_dest),
        ORIGINAL_SHA256=actual,
    )
    print(f"Validated unsigned app {bundle}, version {version}, build {build}, input sha256 {actual}.")


def verify():
    original = os.environ["REQUESTED_BUNDLE_ID"]
    ipa_path = os.environ["SIGNED_IPA_PATH"]
    with zipfile.ZipFile(ipa_path) as z:
        if z.testzip() is not None:
            fail("Signed IPA is corrupt.")
        infos = [n for n in z.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(infos) != 1:
            fail("Signed IPA missing main bundle.")
        info = plistlib.loads(z.read(infos[0]))
        if info.get("CFBundleIdentifier") != original:
            fail("Signer changed the original bundle ID.")
        if str(info.get("CFBundleVersion")) != os.environ["APP_BUILD"]:
            fail("Signer changed the original build number.")
        if str(info.get("CFBundleShortVersionString")) != os.environ["APP_VERSION"]:
            fail("Signer changed the original marketing version.")
        provision = infos[0].rsplit("/", 1)[0] + "/embedded.mobileprovision"
        if provision not in z.namelist():
            fail("Signed app missing embedded provisioning profile.")
        if z.read(provision) != Path(os.environ["PROFILE_PATH"]).read_bytes():
            fail("Embedded profile differs from the validated signing profile.")
    size = Path(ipa_path).stat().st_size
    digest = hashlib.file_digest(open(ipa_path, "rb"), "sha256").hexdigest()
    emit(SIGNED_SHA256=digest, SIGNED_SIZE=str(size))
    print(f"Signed app verified: bundle {original}, sha256 {digest}, {size} bytes.")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("inspect", "verify"):
        fail("Usage: auto-sign-ios.py inspect|verify")
    {"inspect": inspect, "verify": verify}[sys.argv[1]]()
