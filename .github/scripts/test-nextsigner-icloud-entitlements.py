#!/usr/bin/env python3
"""No-secret regression checks for iCloud entitlement preparation and final Mach-O inspection."""
import importlib.util
import os
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("nextsigner-icloud-entitlements.py")
spec = importlib.util.spec_from_file_location("icloud_validation", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

TEAM = "T52CDY8W32"
BUNDLE = "com.nextsolution.dailyledger"
CONTAINER = "iCloud.com.nextsolution.dailyledger"
APP_ID = TEAM + "." + BUNDLE


def make_signature_entitlements(entitlements):
    xml = plistlib.dumps(entitlements)
    item = struct.pack(">II", 0xfade7171, len(xml) + 8) + xml
    superblob = struct.pack(">III", 0xfade0cc0, 20 + len(item), 1)
    superblob += struct.pack(">II", 5, 20) + item
    header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x0100000c, 0, 2, 1, 16, 0, 0)
    command = struct.pack("<IIII", 0x1d, 16, len(header) + 16, len(superblob))
    return header + command + superblob


class EntitlementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.profile = root / "profile.mobileprovision"
        self.profile.write_bytes(b"synthetic-profile-only")
        self.expected = root / "explicit.entitlements"
        self.ipa = root / "test.ipa"
        self.env = {
            "PROFILE_PATH": str(self.profile),
            "REQUESTED_BUNDLE_ID": BUNDLE,
            "CUSTOM_ENTITLEMENTS_PATH": "",
            "ICLOUD_DOCUMENTS": "true",
            "ICLOUD_CONTAINER": CONTAINER,
            "SIGNED_ENTITLEMENTS_PATH": str(self.expected),
            "SIGNED_IPA_PATH": str(self.ipa),
        }
        self.profile_data = {
            "TeamIdentifier": [TEAM],
            "Entitlements": {
                "application-identifier": APP_ID,
                "com.apple.developer.team-identifier": TEAM,
                "get-task-allow": False,
                "keychain-access-groups": [TEAM + ".*"],
                "com.apple.developer.icloud-services": ["*"],
                "com.apple.developer.icloud-container-identifiers": [CONTAINER],
                "com.apple.developer.ubiquity-container-identifiers": [CONTAINER],
                "com.apple.developer.ubiquity-kvstore-identifier": TEAM + ".*",
                "aps-environment": "production",
                "com.apple.security.application-groups": ["group.example.ledger"],
            },
        }

    def prepare(self):
        with patch.dict(os.environ, self.env):
            with patch.object(validator, "profile_data", return_value=self.profile_data):
                validator.prepare()
        return plistlib.loads(self.expected.read_bytes())

    def create_ipa(self, entitlements):
        app = "Payload/NextLedger.app/"
        with zipfile.ZipFile(self.ipa, "w") as z:
            z.writestr(app + "Info.plist", plistlib.dumps({
                "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "NextLedger"
            }))
            z.writestr(app + "NextLedger", make_signature_entitlements(entitlements))
            z.writestr(app + "embedded.mobileprovision", self.profile.read_bytes())

    def test_cloud_documents_exact_and_extra_capabilities_preserved(self):
        actual = self.prepare()
        self.assertEqual(actual["application-identifier"], APP_ID)
        self.assertEqual(actual["com.apple.developer.icloud-services"], ["CloudDocuments"])
        self.assertEqual(actual["com.apple.developer.icloud-container-identifiers"], [CONTAINER])
        self.assertEqual(actual["com.apple.developer.ubiquity-container-identifiers"], [CONTAINER])
        self.assertEqual(actual["com.apple.developer.ubiquity-kvstore-identifier"], APP_ID)
        self.assertEqual(actual["aps-environment"], "production")
        self.assertEqual(actual["com.apple.security.application-groups"], ["group.example.ledger"])
        self.assertEqual(actual["keychain-access-groups"], [APP_ID])
        self.assertNotIn("*", str(actual))

    def test_kvstore_profile_wildcard_must_resolve_before_signing(self):
        self.profile_data["Entitlements"]["com.apple.developer.ubiquity-kvstore-identifier"] = "*"
        entitlements = self.prepare()
        self.assertEqual(entitlements["com.apple.developer.ubiquity-kvstore-identifier"], APP_ID)
        self.assertNotIn("*", str(entitlements))

    def test_kvstore_wrong_team_wildcard_must_be_rejected(self):
        self.profile_data["Entitlements"]["com.apple.developer.ubiquity-kvstore-identifier"] = "WRONGTEAM.*"
        with self.assertRaisesRegex(ValueError, "key-value-store"):
            self.prepare()

    def test_explicit_kvstore_share_is_preserved_when_profile_allows_it(self):
        shared = TEAM + ".com.nextsolution.shared.kvstore"
        self.profile_data["Entitlements"]["com.apple.developer.ubiquity-kvstore-identifier"] = shared
        entitlements = self.prepare()
        self.assertEqual(entitlements["com.apple.developer.ubiquity-kvstore-identifier"], shared)

    def test_other_unresolved_wildcards_are_still_rejected(self):
        self.profile_data["Entitlements"]["com.apple.security.application-groups"] = ["group.*"]
        with self.assertRaisesRegex(ValueError, "explicit value"):
            self.prepare()

    def test_final_macho_entitlements_must_match(self):
        expected = self.prepare()
        self.create_ipa(expected)
        with patch.dict(os.environ, self.env):
            validator.verify()
        malformed = dict(expected)
        malformed["com.apple.developer.icloud-services"] = ["*"]
        self.create_ipa(malformed)
        with patch.dict(os.environ, self.env):
            with self.assertRaisesRegex(ValueError, "icloud-services"):
                validator.verify()

    def test_reject_unauthorized_container(self):
        self.profile_data["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = [
            "iCloud.com.other.app"
        ]
        with self.assertRaisesRegex(ValueError, "container"):
            self.prepare()

    def test_reject_wildcard_app_profile(self):
        self.profile_data["Entitlements"]["application-identifier"] = TEAM + ".*"
        with self.assertRaisesRegex(ValueError, "explicit"):
            self.prepare()


if __name__ == "__main__":
    unittest.main(verbosity=2)
