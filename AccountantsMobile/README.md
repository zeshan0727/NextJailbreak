# AccountantsNext Mobile — 0.4.1 (build 5)

Native SwiftUI iOS 16+ mobile companion for Windows AccountantsNext. Bundle ID \`com.nextsolution.accountantsmobile\` is unchanged to preserve installed app data and receipt drafts.

## Five native tabs
1. **HR** — employee profiles and leave settlements from imported Windows data.
2. **Payments** — payment/receipt vouchers (read-only); locally protected receipt drafts; original PC-created supporting documents when present.
3. **Manager Reporting** — refined native Income Statement and Balance Sheet drill-downs by entity/month/year, Xero TB snapshot provenance, mapping alerts and account-level data.
4. **Company** — entity, registration records and original supporting files, plus Backup & Recovery center.
5. **Agent Zee** — local snapshot search. No remote LLM or PC automation until an authorized agent connection exists.

## Faithful document output policy
The Windows Manager Reporting Excel generation is **not implemented on-device**, because the authoritative Windows .NET report engine, company-specific templates, and formulas have not been imported or verified in this repository. The mobile TB drill-down is NOT represented as the official Windows P&L or Balance Sheet.

To preserve exact desktop output, select **Original Windows Reports** from a restored full backup containing already-generated XLSX/PDF files. iPhone shares the **same unchanged original bytes**, which retain formulas, number formatting, tabs, comparative columns, notes and attachments as saved on PC. User selects file by company, period and filename. If absent, there is no fake mobile export.

The same standard applies to Payments: existing PC-generated receipts can be accessed when packaged in the backup. Mobile-only receipt drafts cannot generate a differently formatted "official" receipt PDF until the real PC generator/templates are integrated.

## Safe Windows full backup restore
- Import \`Accountants5_FULL_*.zip\` or \`AccountantsNext.db\` from Company → Backup & Recovery.
- Check archive extension, compressed size, entry count, uncompressed bytes, ZIP path traversal, file links and expected DB location before decompressing.
- Stage in a separate directory, run SQLite \`PRAGMA quick_check\` and required schema validation, copy attachments, validate again, and only then promote to active snapshot.
- Preserve previous and older recovery points; restore previous from the mobile Recovery screen.
- Detect interrupted promotion on startup; recover previous snapshot if the active folder is absent.
- Active snapshot always opens with GRDB read-only mode.
- Windows PC database/files are never changed. Separately encrypted-by-iOS-protection receipt drafts are preserved during PC snapshot import.
- Set and use an iPhone passcode; device Face ID or passcode is required to enter the app.
- No claim of cloud sync or real-time data. iPhone reports always display import provenance and snapshot date.

**Caution:** the PC recovery ZIP itself is still essential; mobile snapshot copies are not an authoritative desktop restore mechanism. No source data from real companies should be uploaded to the public GitHub repository or NS Transfer.

## Build and QA
- Build using \`.github/workflows/build-accountants-mobile-v030.yml\` or \`bash AccountantsMobile/build.sh\` on macOS.
- iOS minimum: 16.0; output: \`AccountantsMobile-0.3.0.tipa\` / \`.ipa\`.
- Package uses native SwiftUI, GRDB and ZIPFoundation.
- Run \`unzip -t\` and metadata checks in CI.
- Then test on an actual iPhone with a **copy** of a real Windows full backup. Verify entities, May/June period switch, report files/Excel formulas, and rollback. The CI build does not constitute acceptance testing.

## Known limitations / next gate
A verified current Windows Manager Reporting XLSX from at least one entity, an actual backup manifest, and the matching .NET report generation source are needed for native mobile **generation** to be byte/format equivalent, including formula engine and voucher approval formats. Current version exports **original PC files**, not newly built lookalikes.


## 0.4.1 crash and company-selector repair
- Replaces the v0.4.0 VisionKit document-camera controller with iOS 16 UIKit photo capture; photo-library selection is supported as a fallback. Camera is launched only when reported available; scanned pages are downsized before OCR.
- Adds multi-page capture by repeatedly taking a photo, plus **Clear pages**.
- Retains on-device Vision text recognition (no remote upload).
- Company selector is restricted to the **seven operational entities** in Windows 6.1.25 OperationalEntityPolicy.cs: Barjous, Atelier Home, Erada Fitness, North Sports, The Graphitees, Stone Cafe and Levante Bags, including exact source aliases.
- Historical and non-operational rows remain in the imported read-only SQLite database; they are not deleted. A disallowed old selection is reset to the first valid operational company.
- Existing mobile backup, queued PC requests, attached evidence, and receipt drafts are preserved by unchanged bundle ID and storage paths.
- This release does not enable live synchronization or bypass desktop approval.

Testing on device: verify camera permission/launch, take 2 photos, run OCR, save a PC request, reopen app, verify retained capture, photo-library alternative, and the seven-company filter after backup import. An iPhone crash log is still required to definitively identify the original VisionKit crash.
