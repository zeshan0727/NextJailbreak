# Next Ledger — Official Complete Source Snapshot

## Current verified release: **1.3.81 (build 90)**

This branch is the permanent, easy-to-find source home for the **full-featured Next Ledger** iOS app. Use **this exact release branch** for future Next Ledger updates; do **not** start from `main`, `agent/next-ledger-1.3.76-sms-console-cleanup`, or the stripped 1.3.77/1.3.78 branches.

- **Source:** `release/NextLedger-1.3.81-Full-Source`
- **Bundle ID:** `com.nextsolution.dailyledger`
- **Minimum iOS:** 16.0
- **TrollStore installable file:** `dist/NextLedger-1.3.81-Theme-ProMotion-Tabs.tipa`
- **SHA-256 proof:** `dist/NextLedger-1.3.81-Theme-ProMotion-Tabs.sha256`
- **Original successful build:** [GitHub Actions run 39308278483](https://github.com/zeshan0727/NextJailbreak/actions/runs/39308278483)
- **Main XcodeGen manifest:** `project.yml`

### Why this branch exists

The original 1.3.76 (build 84) contained many features generated from a sequence of code-patching scripts. A direct build of an unprepared GitHub source branch **omits functionality** even though it shares the same bundle ID. The correct initial generation steps were:

```bash
bash scripts/apply_next_ledger_1_3_76.sh
python3 scripts/add_fixed_budget_to_full_1_3_76.py
```

**Important:** Those commands explain how this version was created and should be used only on the *pre-generation base* (e.g., a new checkout of the historical pre-generated source branch). **Do not rerun them on this release branch after its generated Swift sources have been checked in**—the patch commands are not designed to apply twice.

### What's included in the complete source

- Core ledger: accounts, transactions, transfers, reporting, and JSON import/export/backup
- Original RootHide SMS Import Console, latest-15 SMS review, and the corresponding importer configuration and service
- The full original reports and associated screens
- The reference-design Budget dashboard: 26th–25th cycles, fixed incomes and expenses, limited/ongoing recurrence, sliders and saved allocation data
- System / Light / Black appearance, dark-aware Budget view, ProMotion 120 Hz opt-in where supported
- Rearrangeable persistent Home / Budget / Ledger / Reports / Settings tabs
- Ledger workspace with Accounts and Transactions only (AI **tab** removed from that workspace)
- Existing daemon source separately under `RootHideSMSImport/` and related RootHide SMS folders; the iPhone daemon was not changed by this UI update

The source snapshot includes the generated full Swift files under `DailyLedger/`, along with the build manifest. The app's budget data is stored inside the normal Ledger JSON; **there is no separate replacement ledger database**.

### Build from the committed source on macOS

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project DailyLedger.xcodeproj -scheme DailyLedger \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Ad-hoc signing and TIPA packaging require the same workflow as the release, or a compatible TrollStore packaging procedure. Source compilation alone does not make an installable TIPA.

### Safe modification procedure for future versions

1. Create a new version branch **from this release branch**.
2. Make UI/feature changes in the committed, complete `DailyLedger/` source; keep existing modules and persistent formats compatible.
3. Test import/export and upgrade of an existing ledger with accounts and transactions, plus relevant SMS features.
4. Verify iOS build, app identifier, installed version, and source-to-binary contents.
5. Publish a new named source snapshot and corresponding TIPA (and checksum).
6. **Back up the real user's ledger to Files or Drive outside the app before installation. Never uninstall the existing app to update.**

### Recovery warning

Previous updates once appeared to erase the user's financial history after incompatible data handling. This branch includes an additional guard intended to prevent overwriting existing JSON when decoding fails, but it is **not a substitute for backups or a physical-device upgrade test**.

No user bank data, ledger JSON, SMS messages or API keys are intentionally included in this repository snapshot.
