#!/usr/bin/env python3
"""Re-sign the existing 8 Ball Pool No Key IPA with the validated 7-day offline Ad Hoc profile.
Only certificate-bound AES-GCM ciphertext is stored in Git; private key stays in GitHub Secrets.
"""
import base64
import gzip
import hashlib
import io
import json
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates

TEAM = "T52CDY8W32"
BUNDLE = "com.nextsolution.8ballpoolmult36"
NAME = "8 Ball Pool Temp"
VERSION = "56.31.0"
BUILD = "5330"
SIGNED_BUILD = "5331"
EXPECTED_EXPIRY = datetime(2026, 11, 12, 15, 54, 41, tzinfo=timezone.utc)
TMP = pathlib.Path(os.environ["RUNNER_TEMP"])
SOURCE = TMP / "8ball-original.ipa"
SIGNED = TMP / "8-ball-pool-temp-7-days-56.31.0-5331.ipa"

def fail_if(condition, message):
    if condition:
        raise RuntimeError(message)

def app_info(archive):
    plist_files = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
    fail_if(len(plist_files) != 1, "Expected exactly one app Info.plist")
    return plist_files[0], plistlib.loads(archive.read(plist_files[0]))

def decode_profile(raw, filename):
    filename.write_bytes(raw)
    return plistlib.loads(subprocess.check_output(
        ["openssl", "cms", "-verify", "-inform", "DER", "-noverify", "-in", str(filename)],
        stderr=subprocess.DEVNULL))

def main():
    fail_if(not SOURCE.is_file(), "Original 8 Ball Pool IPA is missing")
    with zipfile.ZipFile(SOURCE) as z:
        _, info = app_info(z)
        for k, v in [("CFBundleIdentifier", BUNDLE), ("CFBundleShortVersionString", VERSION),
                     ("CFBundleVersion", BUILD)]:
            fail_if(str(info.get(k)) != v, f"Original build has unexpected {k}: {info.get(k)!r}")
    # Change CFBundleVersion BEFORE signing, without zsign -r (which changes
    # CFBundleShortVersionString instead of the internal build number).
    input_for_signing = TMP / "8ball-build5331-input.ipa"
    with zipfile.ZipFile(SOURCE) as zin, zipfile.ZipFile(input_for_signing, "w") as zout:
        plist_entry, _ = app_info(zin)
        for member in zin.infolist():
            content = zin.read(member.filename)
            if member.filename == plist_entry:
                info = plistlib.loads(content)
                info["CFBundleVersion"] = SIGNED_BUILD
                content = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
            zout.writestr(member, content)
    with zipfile.ZipFile(input_for_signing) as verify:
        _, modified = app_info(verify)
        fail_if(str(modified.get("CFBundleShortVersionString")) != VERSION
                or str(modified.get("CFBundleVersion")) != SIGNED_BUILD,
                "Prepared input version is not correct")
    cert_bytes = base64.b64decode(os.environ["P12_B64"], validate=True)
    secret = os.environ["P12_PASSWORD"].encode()
    key, cert, _ = load_key_and_certificates(cert_bytes, secret)
    fail_if(not isinstance(key, rsa.RSAPrivateKey) or cert is None, "Signing P12 does not contain RSA private key + certificate")
    cert_file = TMP / "certificate.p12"
    cert_file.write_bytes(cert_bytes)
    cert_file.chmod(0o600)

    encrypted = "".join(pathlib.Path(f".github/nextapp-offline.enc.part{i}").read_text() for i in range(1, 5))
    envelope = json.loads(encrypted)
    fail_if(envelope["format"] != "next-app-library-offline-profile-v1", "Unrecognized encrypted profile")
    fail_if(envelope["algorithm"] != "RSA-OAEP-SHA256+AES-256-GCM+gzip", "Unsupported encrypted profile format")
    cert_sha = cert.fingerprint(hashes.SHA256()).hex()
    fail_if(cert_sha != envelope["certificate_sha256"], "Existing GitHub signing certificate differs from offline profile")
    wrapped = base64.b64decode(envelope["encrypted_aes_key_b64"])
    aes_key = key.decrypt(wrapped, padding.OAEP(
        mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    encoded = AESGCM(aes_key).decrypt(
        base64.b64decode(envelope["nonce_b64"]),
        base64.b64decode(envelope["encrypted_profile_b64"]),
        base64.b64decode(envelope["aad_b64"]))
    profile_bytes = gzip.decompress(encoded)
    fail_if(hashlib.sha256(profile_bytes).hexdigest() != envelope["profile_sha256"], "Offline profile checksum failed")
    profile_path = TMP / "offline.mobileprovision"
    profile = decode_profile(profile_bytes, profile_path)
    profile_path.chmod(0o600)
    fail_if(profile.get("TimeToLive") != 7, "Profile is not the requested seven-day profile")
    fail_if(profile.get("TeamIdentifier") != [TEAM], "Team ID mismatch")
    fail_if(len(profile.get("ProvisionedDevices", [])) != 1, "Expected one registered iPad UDID")
    fail_if(profile.get("Entitlements", {}).get("application-identifier") != TEAM + ".com.nextsolution.*",
            "Provisioning profile does not permit the app bundle ID")
    end = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    fail_if(end != EXPECTED_EXPIRY or end <= datetime.now(timezone.utc), "Offline profile expiry mismatch or expired")
    prof_certs = [x509.load_der_x509_certificate(b) for b in profile["DeveloperCertificates"]]
    fail_if(not any(c.fingerprint(hashes.SHA256()).hex() == cert_sha for c in prof_certs),
            "Profile does not authorize configured distribution certificate")
    # Signed entitlements must carry concrete identities even when the provisioning
    # profile authorizes a wildcard app identifier.
    entitlements = {
        "application-identifier": f"{TEAM}.{BUNDLE}",
        "com.apple.developer.team-identifier": TEAM,
        "get-task-allow": False,
        "keychain-access-groups": [f"{TEAM}.{BUNDLE}"],
    }
    ent_path = TMP / "effective-entitlements.plist"
    ent_path.write_bytes(plistlib.dumps(entitlements))
    zsign = TMP / "zsign/bin/zsign"
    subprocess.run([
        str(zsign), "-f", "-k", str(cert_file), "-p", os.environ["P12_PASSWORD"],
        "-m", str(profile_path), "-e", str(ent_path), "-E", "-b", BUNDLE, "-n", NAME,
        "-o", str(SIGNED), str(input_for_signing),
    ], check=True)
    fail_if(not SIGNED.is_file(), "Signed IPA not created")
    with zipfile.ZipFile(SIGNED) as z:
        plist_path, info = app_info(z)
        for k, v in [("CFBundleIdentifier", BUNDLE), ("CFBundleShortVersionString", VERSION),
                     ("CFBundleVersion", SIGNED_BUILD), ("CFBundleDisplayName", NAME)]:
            fail_if(str(info.get(k)) != v, f"Signed IPA has unexpected {k}: {info.get(k)!r}")
        embedded = plist_path.rsplit("/", 1)[0] + "/embedded.mobileprovision"
        fail_if(z.read(embedded) != profile_bytes, "Exact offline profile not embedded")
        fail_if(z.testzip() is not None, "Damaged IPA ZIP")
        fail_if(any(".appex/" in n and "/PlugIns/" in n for n in z.namelist()),
                "Optional app extensions still present after -E removal")
    sha = hashlib.sha256(SIGNED.read_bytes()).hexdigest()
    output = TMP / "8ball-offline-build.env"
    output.write_text(f"SIGNED_SHA256={sha}\nSIGNED_SIZE={SIGNED.stat().st_size}\n")
    print("PASS: 8 Ball Pool Temp signed with embedded seven-day offline Ad Hoc profile")
    print(f"App bundle: {BUNDLE}; version: {VERSION} ({SIGNED_BUILD}); removed optional extensions")
    print(f"Profile expires UTC: {end.isoformat()}")
    print(f"IPA bytes: {SIGNED.stat().st_size}, SHA256: {sha}")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
