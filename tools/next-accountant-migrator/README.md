# Next Accountant Web Migrator

Migration bridge for a verified ACCOUNTANTS 6.x V6 business backup.

It never reads or changes the live AccountantsNext.db directly. It verifies the V6 manifest, every SHA-256 and SQLite integrity before any cloud write.

## Safe preflight

Run:

    NextAccountantMigrator.exe --prepare-only

The migrator automatically searches the normal RecoveryMedia and V6 business-backup folders, or accepts an explicit --backup path.

## Full migration

Full migration requires:

- D1 online
- private R2 file storage online
- protected owner authentication configured

The owner token is read from the NEXT_ACCOUNTANT_OWNER_TOKEN environment variable and must never be committed to GitHub.

The migrator preserves table IDs, imports parent tables before child tables, uploads only files already included by the V6 business-backup rules, and reconciles every table row count after import.

Windows ACCOUNTANTS remains authoritative until module/report reconciliation is complete.
