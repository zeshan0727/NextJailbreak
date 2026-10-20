# Next Ledger 1.3.84 (Build 93): JSON restore and iCloud signing correction

Verified full iOS build: https://github.com/zeshan0727/NextJailbreak/actions/runs/39397064050

Unsigned distribution artifact: `NextLedger-1.3.84-RestoreFix-iCloud-Signing-Ready`
(contains unsigned IPA, iCloud entitlement template and SHA-256)

Original functions retained: full ledger, accounts, SMS Console, monthly budget,
5 customizable tabs, reports, and automatic versioned backup.

## Fixed

- Settings → Backup & Sync → **Restore JSON Backup from Files** is now a
  dedicated manual JSON restore control.
- Files picker accepts any extension or iOS file-provider content type (UTType.item),
  then validates JSON or CSV contents. This allows Google Drive and local Files JSON
  copies even if the file provider advertises an unknown type.
- Imported bytes are read under active security-scoped access with
  NSFileCoordinator and an upper bound of 50 MB.
- Picker confirmation is only presented after dismissal, avoiding swallowed
  confirmation sheets on iOS.
- Import displays transaction/account counts and requires explicit consent to merge.
- Accepts ISO8601 dates with or without fractional seconds in older backups.
- Correct iCloud error distinction: missing automatic backup vs unavailable
  signed iCloud container.

## Signing warning

The user's signed Next Ledger 1.3.83 IPA had
`com.apple.developer.icloud-services = "*"` in the *code signature*.
This is the App ID provisioning profile allow-list syntax, not a valid
replacement for an explicit app claim. Apple documentation TN3125:
https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles

The final signed 1.3.84 app must claim:
- `com.apple.developer.icloud-services = ["CloudDocuments"]`
- `com.apple.developer.icloud-container-identifiers = ["iCloud.com.nextsolution.dailyledger"]`
- `com.apple.developer.ubiquity-container-identifiers = ["iCloud.com.nextsolution.dailyledger"]`
- exact App ID `T52CDY8W32.com.nextsolution.dailyledger`

Do not install or overwrite any existing data-bearing app until a verified
readable JSON backup exists outside the app's sandbox. Switching installation
types may reset or alter the app's data container. This release is *unsigned*
and requires Apple Distribution signing with the matching Ad Hoc profile.

After signing, inspect the actual Mach-O code signature's entitlements and
verify the app at runtime. Accessing the iCloud Documents folder does not
guarantee remote upload is complete.
