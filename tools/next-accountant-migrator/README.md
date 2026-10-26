# Next Accountant Staging Migrator 0.2.0

This Windows x64 utility migrates a **verified COPY** of the ACCOUNTANTS V6 business backup. It never opens or changes the live `AccountantsNext.db` and never sends data to the production API.

**Target only:** https://accounts-stage-api.nextjailbreak.com

## Included launchers

- `TEST_BACKUP_ONLY.bat` — read-only validation (safe, no cloud writes)
- `PREPARE_STAGING_KEY.bat` — creates a 3072-bit RSA public/private key pair; Windows DPAPI protects the private key for this Windows account
- `IMPORT_TO_STAGING_ONLY.bat` — real staging import; refuses to run until an encrypted credential has been provided and locally decrypted

## One-time encrypted enrollment

1. Extract this package into a folder on the Windows PC with ACCOUNTANTS.
2. Run `PREPARE_STAGING_KEY.bat`.
3. Share **only** `NEXT_ACCOUNTANT_STAGING_PUBLIC_KEY.pem` with the assistant. A public key contains no authentication secret.
4. The GitHub workflow encrypts a newly generated staging-only token to that RSA public key, provisions it as a Cloudflare Worker Secret, and generates an encrypted credential artifact.
5. Place `NEXT_ACCOUNTANT_STAGING_CREDENTIAL.txt` from that artifact alongside the EXE. No token is entered or exposed as plaintext.
6. Use `IMPORT_TO_STAGING_ONLY.bat` only after the API and imported-record tests are green.

Do not upload, publish, or commit the business backup, Windows private key, secret or plaintext token to GitHub.

## Pre-import checks

- Entire V6 manifest and all SHA-256 entries
- SQLite `PRAGMA integrity_check`
- D1 compatibility, foreign keys and data sizes
- Explicit staging environment identity
- Cloud database must have **no existing business records**

## Import

- Source SQLite identifiers preserved.
- Schema applied to staging D1 in small chunks.
- 20-row import batches for Workers Free query limits.
- File bytes uploaded to *private* staging R2, with SHA-256 checked against V6 manifest.
- Existing R2 objects with different content refuse overwrite.
- Bounded table-count reconciliation before the run is marked technically complete.

An interrupted import may leave **partial staging-only records**. Do not retry without reviewing/resetting staging first. Nothing is changed in production automatically.

**Critical:** Technical count reconciliation does not equal accounting sign-off. Project/contract balances, payment allocations, payroll, financial statements and PDF reports must be separately reconciled before any cutover. Windows ACCOUNTANTS remains the authoritative baseline.
