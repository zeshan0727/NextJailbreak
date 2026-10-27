# Next Accountant Web — Private Staging v0.5

**Production is NOT enabled.** Windows ACCOUNTANTS V6 remains authoritative. The static GitHub Pages demo at https://nextjailbreak.com/accountants/ is unrelated to the private staging database.

## Staging (authenticated only)

Address: https://accounts-stage-api.nextjailbreak.com/web

Log in through the encrypted Windows ZIP using `OPEN_ACCOUNTANT_WEB.bat` on the same Windows profile as the migration. The browser receives a short-lived, read-only session cookie. The powerful migration bearer credential stays protected by Windows DPAPI; it must **never** be committed, shared or entered in the web app.

### Verified migration baseline

- Original V6 SQLite schema v21; 109 business tables; 11,913 records.
- Original R2 source files: 909 of 909, SHA-256 checked; two legitimate zero-byte files preserved.
- Independently verified D1 counts and file index.
- Seven managed companies uniquely resolved and enforced **server-side**, not merely filtered in JavaScript.
- Imported business tables are never modified by web staging UI.

### Available private web functionality

- Company dashboard with source invoice/receipt/voucher summaries.
- Original Windows V6 invoice, customer, payment/receipt voucher, contract project, installment and receipt allocation data in read-only tables.
- Download unchanged archived manager Excel reports from the private R2 backup, where present.
- Company-scoped daily tasks and HR employee directory (read only; payroll amounts not exposed).
- Create **isolated PV/RV staging drafts** and optionally attach a scanned PDF/phone photo (up to 12 MB), with audit trail. These are NOT posted to the original Windows voucher tables or reconciled accounts.
- Session expiration, signed-out session revocation, CSRF origin verification for draft writes, private per-company report access, no anonymous access.

### Next required validation

The v0.4 Windows financial check passed against the exact 2026-10-26 backup: 109 tables, 11,913 rows, 909 indexed files, and six source-table monetary totals. The enhanced v0.5 `VERIFY_FINANCIALS_ONLY.bat` additionally compares each dataset by original company, source period and currency, and verifies manager-report account snapshot debit/credit/balance aggregates. Run it locally on the same Windows user profile; it performs no business writes.

**Do not certify finance cutover based only on matching six sums or source snapshot totals.** Full production approval requires per-company and per-period trial balance/balance-sheet/income-statement reconciliation, exchange-rate correctness, manager-report rendering/export parity, controlled source-to-web voucher posting with audit and rollback tests, full HR module parity, multiuser security, protected storage/backups, and user acceptance testing.

### Security

Only public-safe code is committed to this repository; never store a V6 business ZIP, the D1 database, extracted records, plaintext tokens, or private RSA keys in GitHub. Staging D1/R2 are private and separate from production.

Synthetic tests: `.github/workflows/test-next-accountant-staging-import.yml`

Private staging deployment: `.github/workflows/deploy-next-accountant-staging.yml`
