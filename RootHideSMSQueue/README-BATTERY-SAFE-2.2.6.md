# Next Ledger SMS RootHide daemon — 2.2.6 compatibility package

## Identity and provenance

Next Ledger application: `com.nextsolution.dailyledger`.
RootHide daemon package: `com.nextsolution.nextledger.smsdaemon` version **2.2.6**.

The 2.2.6 DEB is a controlled repair of the previously working
`NextLedgerSMSDaemon-2.2.5-battery-safe-roothide.deb` supplied in the
original 1.3.76 Battery Safe Complete release package. **The Mach-O daemon
binary is unchanged**: its built-in version is 2.2.4, and its SHA-256 is

`a41e5685f676d5eee5b98311d02f2b27acabe97affcadc1d2d533006e137be0c`.

The 2.2.6 DEB SHA-256 is:

`f3ce6ee66f7c9da3eec5b0e28805af2d9350b75f4db5f94974fe558e84b62d02`.

The `RootHideSMSQueue/Sources/main.m` in this repository's historical
2.2.5 ancestor remains an *older 2.0.0 implementation* and must not be
treated as the source for the installed signed 2.2.4 binary. The 2.2.6
version refers to the **package and installer policy**, not a rebuilt engine.
The retained historical `.debug/sms-schedule-1.3.72/nextledgersmsd-2.2.3.m`
is also not identical to the 2.2.4 binary.

## Installation policy repaired in 2.2.6

- Correctly disable `realtimeCaptureEnabled` in
  `Library/Application Support/DailyLedger/sms-import-config.json`,
  NOT the output-only `sms-import-console.json`.
- Never remove `sms-ai-candidates.json` or pending SMS drafts while installing.
- Preserve stored account mappings, review records, ledger data and scan interval.
- Keep the RootHide launchd identifier `com.nextsolution.nextledgersmsd`.
- Preserve the original 2.2.4 signed executable byte-for-byte.
- Installer writes to `/rootfs/var/mobile/Library/NextLedgerSMSImport/install.log`,
  then copies `sms-import-install.log` to the app container when found.

## Device acceptance test

1. Confirm a readable off-device JSON backup before reinstalling the Next Ledger application.
2. Keep bundle ID `com.nextsolution.dailyledger` unchanged.
3. Install the DEB from a RootHide-compatible package manager, then open
   Next Ledger → Settings → SMS Import Console → Installer Diagnostics.
4. Confirm the current install result and a *fresh* daemon heartbeat.
5. Use **Fetch Latest 15 SMS** and verify progress/completion without adding
   unreviewed financial transactions.
6. If the daemon is missing, inspect the launchd and trustcache errors in the
   installer log. A successful IPA build does not prove daemon execution.

The app's screen changes for Build 97 are source-only view refinements and do
not alter the daemon JSON contracts or backup/import logic.
