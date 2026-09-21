# Accountants Mobile v0.1.0

Native iPhone companion for Accountants 5.0.

## Data model

The Windows desktop application remains the accounting source. The iPhone app reads the newest `Accountants5_FULL_*.zip` package from the cloud backup folder created by Accountants 5.0 R6I43.

The user signs into Google Drive, Dropbox, OneDrive or MEGA through the provider's iPhone app, enables that provider in Files, and chooses the `Accountants 5.0 Backups` folder once. A security-scoped bookmark is retained by the app.

While the app is open it rechecks the cloud folder every 30 seconds, downloads a changed full-backup snapshot through File Provider, extracts it into the private app sandbox, and opens `Data/AccountantsNext.db` read-only.

## v0.1.0 modules

- Dashboard
- Manager Reporting / TB account browser and mappings
- Audit P&L / BS template browser
- FAR synced files
- HR employees and leave settlements
- Payment vouchers
- Receipt vouchers
- Cost master
- Company documents
- Synced files and reports with Quick Look

v0.1.0 is intentionally read-only. It never edits the desktop database or writes into backup ZIPs. This prevents mobile/desktop write conflicts while the cloud sync protocol is being validated.

## Target

- iPhone
- iOS 16+
- unsigned TrollStore-compatible TIPA
