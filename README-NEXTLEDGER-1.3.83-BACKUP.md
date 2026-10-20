# Next Ledger 1.3.83 (Build 92) — Backup file picker and iCloud diagnostics

**Source release:** `release/NextLedger-1.3.83-Backup-Restore-iCloud` in `zeshan0727/NextJailbreak`

**Verified build:** https://github.com/zeshan0727/NextJailbreak/actions/runs/39390371148

**Distribution:** Unsigned `NextLedger-1.3.83-BackupPicker-iCloud-Signing-Ready.ipa` with generated `NextLedger-1.3.83-BackupPicker-iCloud.entitlements` and SHA-256 checksum in the build artifact. **Do not install without certificate signing.**

- Bundle ID: `com.nextsolution.dailyledger`
- iCloud container: `iCloud.com.nextsolution.dailyledger`
- iCloud signing service: `CloudDocuments` (requires matching Apple profile)
- Data format: existing `DailyLedger/ledger.json`; budget and SMS features are preserved.

## Fixes

- **Settings → Import & Export → Save Backup to Files:** native iOS document exporter using a byte-for-byte verified read of on-disk `ledger.json`. The user picks On My iPhone, iCloud Drive, or an installed file provider. Refuses corrupt or empty exports.
- **Settings → Import & Export → Import Data:** native Files picker supporting JSON and CSV from Files, Google Drive or iCloud Drive. Security-scoped file data is read while access is active, then validated and previewed before a confirmed non-destructive merge by transaction/account ID.
- **Settings → Backup & Sync:** separate `Back Up to iCloud Now` and `Save JSON to Files / Drive` buttons; dynamic status and `Check iCloud Connection` distinguish missing account vs missing signed app entitlement / inaccessible cloud container.
- Existing automatic backups on launch and ledger changes remain, preserving 10 rotating local and (when provisioned) iCloud-container snapshots.

## Installation safety

This is the **FULL** app, not an old reduced source. All finance, SMS import, reports, monthly budget and navigation screens are retained. The build was validated using Xcode compilation, bundle/version assertions, binary feature checks, unsigned IPA ZIP integrity and CloudDocuments entitlement template checks.

Sign the unsigned IPA with the Apple Distribution certificate, a matching Ad Hoc provisioning profile for **com.nextsolution.dailyledger** and the correct **CloudDocuments** and `iCloud.com.nextsolution.dailyledger` entitlements. A correct profile does not prove your *signed IPA* preserved its entitlements. Verify the installed app on an iPhone.

**Do not replace a financially populated existing app until a readable backup exists outside its app container.** Changing from TrollStore to certificate-signed installation may not preserve the app container, even with the same bundle identifier. A signed build and iCloud access do not guarantee remote synchronization has completed. 
