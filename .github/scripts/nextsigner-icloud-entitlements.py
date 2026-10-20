#!/usr/bin/env python3
"""Next Signer explicit-entitlement preflight and signed IPA verification.
Never prints private signing assets or certificate contents.
"""
import os
import plistlib
import struct
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

CLOUD = (
    "com.apple.developer.icloud-services",
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.ubiquity-container-identifiers",
)


def profile_data(path):
    payload = subprocess.check_output(
        ["openssl", "cms", "-verify", "-inform", "DER", "-noverify", "-in", path],
        stderr=subprocess.DEVNULL,
    )
    return plistlib.loads(payload)


def permitted(actual, allowed):
    if isinstance(allowed, list) and isinstance(actual, list):
        return all(any(permitted(v, a) for a in allowed) for v in actual)
    if isinstance(allowed, str) and isinstance(actual, str):
        return actual == allowed or allowed == "*" or (
            allowed.endswith("*") and actual.startswith(allowed[:-1])
        )
    return type(actual) is type(allowed) and actual == allowed


def has_wildcard(value):
    if isinstance(value, str):
        return "*" in value
    if isinstance(value, (tuple, list)):
        return any(has_wildcard(item) for item in value)
    if isinstance(value, dict):
        return any(has_wildcard(item) for item in value.values())
    return False


def prepare():
    profile_path = os.environ["PROFILE_PATH"]
    bundle_id = os.environ["REQUESTED_BUNDLE_ID"].strip()
    custom_path = os.environ.get("CUSTOM_ENTITLEMENTS_PATH", "")
    cloud_enabled = os.environ.get("ICLOUD_DOCUMENTS", "false") == "true"
    cloud_container = os.environ.get("ICLOUD_CONTAINER", "").strip()
    path_out = Path(os.environ["SIGNED_ENTITLEMENTS_PATH"])
    if not bundle_id or any(x in bundle_id for x in ('/', ' ', '*', '\n', '\r')):
        raise ValueError("Signing requires an explicit, valid bundle identifier.")
    if custom_path and cloud_enabled:
        raise ValueError("Select either iCloud Documents preset or custom entitlements, not both.")
    p = profile_data(profile_path)
    team = p.get("TeamIdentifier", [None])[0]
    ent_allowed = p["Entitlements"]
    profile_app = ent_allowed.get("application-identifier")
    requested_app = f"{team}.{bundle_id}"
    if not team or not profile_app or not permitted(requested_app, profile_app):
        raise ValueError("The selected provisioning profile does not authorize the requested bundle ID.")
    expiry = p.get("ExpirationDate")
    if isinstance(expiry, datetime) and expiry.replace(tzinfo=expiry.tzinfo or timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("The selected provisioning profile has expired.")
    if cloud_enabled:
        if profile_app != requested_app:
            raise ValueError("iCloud Documents needs an explicit, exact App ID. A wildcard profile is not allowed.")
        if not cloud_container.startswith("iCloud.") or len(cloud_container) < 9 or any(c in cloud_container for c in (" ", "/", "*", "\n")):
            raise ValueError("Enter a valid explicit iCloud container identifier.")
        if "CloudDocuments" not in ent_allowed.get(CLOUD[0], []) and "*" not in ent_allowed.get(CLOUD[0], []):
            raise ValueError("Profile does not permit CloudDocuments. Enable iCloud for this App ID.")
        for key in CLOUD[1:]:
            if not permitted([cloud_container], ent_allowed.get(key, [])):
                raise ValueError("Profile does not authorize the requested iCloud container: " + key)

    if not cloud_enabled and not custom_path:
        print("No entitlements override requested; default profile-derived signing.")
        return

    requested = {}
    if cloud_enabled:
        requested[CLOUD[0]] = ["CloudDocuments"]
        requested[CLOUD[1]] = [cloud_container]
        requested[CLOUD[2]] = [cloud_container]
    elif custom_path:
        payload = Path(custom_path).read_bytes()
        if len(payload) > 100_000:
            raise ValueError("Entitlements file must be smaller than 100 KB.")
        requested = plistlib.loads(payload)
        if not isinstance(requested, dict):
            raise ValueError("Custom entitlements must be a plist dictionary.")

    # The explicit -e override replaces the full entitlement set. Preserve
    # concrete capabilities allowed by the selected profile; do not silently
    # remove other requirements such as App Groups or push notifications.
    ent = {}
    for key, value in ent_allowed.items():
        if key in ("application-identifier", "com.apple.application-identifier"):
            ent[key] = requested_app
        elif key == "com.apple.developer.team-identifier":
            ent[key] = team
        elif key == "get-task-allow":
            ent[key] = False
        elif key == "keychain-access-groups":
            if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
                raise ValueError("Unsupported keychain access group format.")
            groups = []
            for group in value:
                if "*" in group:
                    if not permitted(requested_app, group):
                        raise ValueError("Cannot resolve keychain group: " + group)
                    groups.append(requested_app)
                else:
                    groups.append(group)
            ent[key] = groups
        elif key in requested:
            ent[key] = requested[key]
        elif has_wildcard(value):
            if key in CLOUD:
                # A wildcard is a profile permission, not a concrete claim.
                # An exact container must be chosen explicitly to sign it.
                continue
            raise ValueError("Profile capability needs an explicit value: " + key)
        else:
            ent[key] = value

    ent["application-identifier"] = requested_app
    ent["com.apple.developer.team-identifier"] = team
    ent["get-task-allow"] = False
    for key, value in requested.items():
        if key in ("application-identifier", "com.apple.application-identifier",
                   "com.apple.developer.team-identifier", "get-task-allow"):
            if key in ent and ent[key] != value:
                raise ValueError("Custom entitlements conflict with signing identity: " + key)
        ent[key] = value

    for key, value in ent.items():
        if key not in ent_allowed and key != "com.apple.developer.team-identifier":
            raise ValueError("Provisioning profile does not permit entitlement: " + key)
        if has_wildcard(value):
            raise ValueError("Cannot sign unresolved wildcard entitlement: " + key)
        if key in ent_allowed and not permitted(value, ent_allowed[key]):
            raise ValueError("Provisioning profile does not authorize entitlement value: " + key)
    path_out.write_bytes(plistlib.dumps(ent, fmt=plistlib.FMT_XML, sort_keys=True))
    print("Validated explicit signing entitlements for the selected profile, team and bundle ID.")
    print("Active capabilities:", ", ".join(k for k in ent if k not in ("application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups", "get-task-allow")) or "standard")


def mach_o_entitlements(binary):
    if binary[:4] == b"\xcf\xfa\xed\xfe":
        endian, header_len = "<", 32
    elif binary[:4] == b"\xce\xfa\xed\xfe":
        endian, header_len = "<", 28
    elif binary[:4] == b"\xfe\xed\xfa\xcf":
        endian, header_len = ">", 32
    elif binary[:4] == b"\xfe\xed\xfa\xce":
        endian, header_len = ">", 28
    else:
        raise ValueError("Unrecognized main Mach-O executable.")
    ncmds = struct.unpack_from(endian + "I", binary, 16)[0]
    off = header_len
    for _ in range(ncmds):
        cmd, size = struct.unpack_from(endian + "II", binary, off)
        if cmd == 0x1D:
            blob_off, blob_len = struct.unpack_from(endian + "II", binary, off + 8)
            raw = binary[blob_off:blob_off + blob_len]
            if struct.unpack_from(">I", raw)[0] != 0xFADE0CC0:
                raise ValueError("Main executable's CodeDirectory signature is missing.")
            count = struct.unpack_from(">I", raw, 8)[0]
            for j in range(count):
                slot, position = struct.unpack_from(">II", raw, 12 + 8 * j)
                if slot == 5 and struct.unpack_from(">I", raw, position)[0] == 0xFADE7171:
                    length = struct.unpack_from(">I", raw, position + 4)[0]
                    return plistlib.loads(raw[position + 8:position + length])
            raise ValueError("No XML entitlements in main executable's code signature.")
        off += size
    raise ValueError("Main executable was not signed.")


def verify():
    expected = plistlib.loads(Path(os.environ["SIGNED_ENTITLEMENTS_PATH"]).read_bytes())
    with zipfile.ZipFile(os.environ["SIGNED_IPA_PATH"]) as ipa:
        plist_name = next(
            n for n in ipa.namelist()
            if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")
        )
        app_dir = plist_name.rsplit("/", 1)[0]
        info = plistlib.loads(ipa.read(plist_name))
        if info["CFBundleIdentifier"] != os.environ["REQUESTED_BUNDLE_ID"]:
            raise ValueError("Signed IPA bundle ID differs from requested App ID.")
        executable = info.get("CFBundleExecutable")
        actual = mach_o_entitlements(ipa.read(f"{app_dir}/{executable}"))
        for key, val in expected.items():
            if actual.get(key) != val:
                raise ValueError("Signed IPA is missing/mis-states code-signature entitlement: " + key)
        if f"{app_dir}/embedded.mobileprovision" not in ipa.namelist():
            raise ValueError("Signed IPA does not include the required Ad Hoc provisioning profile.")
        provision_bytes = ipa.read(f"{app_dir}/embedded.mobileprovision")
        if provision_bytes != Path(os.environ["PROFILE_PATH"]).read_bytes():
            raise ValueError("Embedded provisioning profile is different from the one validated.")
        print("PASS: final Mach-O signature contains all requested entitlements, exact app ID and selected profile.")


if __name__ == "__main__":
    try:
        {"prepare": prepare, "verify": verify}[sys.argv[1]]()
    except (Exception, KeyError) as exc:
        sys.exit("Next Signer entitlement validation failed: " + str(exc))
