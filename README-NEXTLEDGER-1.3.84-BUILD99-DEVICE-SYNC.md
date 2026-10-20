# Next Ledger 1.3.84 Build 99 — CloudDocuments device sync (opt-in)

## Purpose
The existing 10-file rotating iCloud backup is **not** live cross-device sync.
Build 99 adds a separate, opt-in sync between Next Ledger installations
signed for **com.nextsolution.dailyledger** with the explicit
`iCloud.com.nextsolution.dailyledger` CloudDocuments container.

### Safe initial capabilities
- Each device writes a uniquely named
  `Documents/DailyLedger/DeviceSync/device-<UUID>.json` snapshot.
  Another device cannot overwrite its file by publishing its own snapshot.
- iCloud metadata notifications and app-foreground/manual sync discover peer files.
- Adds transactions and accounts that have new UUIDs, retaining the existing
  ledger and its transactions. Repeated imports are idempotent.
- On a truly new device with no transactions and only the built-in legacy main
  account, the first remote merge also seeds preferences and the fixed budget.
- Existing rotating iCloud backup history remains untouched.
- A mismatch for the same transaction/account UUID is reported as a **conflict**.
  Build 99 does **not** overwrite existing edits, propagate deletes, or reconcile
  later independent edits to shared settings/budgets. A future release must
  implement revision/tombstone and conflict UI before doing so safely.

### Acceptance testing (two devices)
1. Confirm a readable off-device backup of the populated primary phone.
2. Install/sign Build 99 on both phones without uninstalling current data.
3. Ensure both use the same iCloud Apple ID, enable iCloud Drive, and are signed
   with the same Team ID/App ID/container; each Ad Hoc profile needs its device UDID.
4. Open Settings → Backup & Sync, enable **Sync Across Devices** on both.
5. Tap **Sync With Other Devices Now** on the existing phone, then on the new one.
   Leave both online while iCloud downloads the snapshots.
6. The new phone should receive the original accounts, transactions, settings
   and fixed budget. Check financial totals and account counts.
7. Add one unique test transaction on device A, open/sync device B, and confirm
   exactly one copy appears. Add one on B and check A similarly.
8. Verify pressing Sync again does not duplicate entries. Verify a fresh
   off-device JSON export before using this on primary financial data.
9. For edited/deleted records, expect a conflict / unchanged local record;
   do not assume edits or deletions automatically synchronize yet.

iCloud Documents transfer is asynchronous and device/background delivery is
not guaranteed to be immediate. A successful unsigned GitHub compile or
local IPA signature is not proof of end-to-end device synchronization.
