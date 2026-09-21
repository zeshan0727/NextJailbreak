# Accountants Mobile 0.1.0 — Local Backup Edition

First iPhone/TrollStore validation build for Accountants 5.0.

## Data source
- Import an `Accountants5_FULL_*.zip` created by the Windows Accountants Cloud Backup module, OR a direct `AccountantsNext.db` snapshot.
- You can also copy the ZIP/DB into the app Documents directory with Files/Filza and use **Scan App Documents**.
- The ZIP is extracted locally. The mobile app opens its copied SQLite snapshot read-only at the UI/workflow level; it never writes to the Windows backup database.

## Included in v0.1.0
- Global Entity / Month / Year workspace.
- Dashboard summary.
- Manager Reporting TB account browser.
- HR employees and leave settlements.
- Payments and Receipt vouchers.
- Audit template lines plus audit/FAR file browser.
- Cost Master.
- Company Information.
- Local file browser with Quick Look.
- ZEE local snapshot search.
- Cloud-provider buttons visible but intentionally disabled until local parity is validated.

## Next phase
After local backup parity is confirmed, enable provider authentication, incremental sync, conflict control, reviewed writes, and managed ZEE tools against the synchronized mobile workspace.
