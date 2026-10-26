# Windows → Web Migration Plan

Baseline: current ACCOUNTANTS 6.1.x Windows line, retained as the authoritative recovery/fallback during migration.

## Phase 0 — Preparation (no paid server yet)

- Keep public-safe bootstrap only in the current public repository.
- Keep proprietary ACCOUNTANTS source/data out of the public repository.
- Build the single-user web domain/UI architecture.
- Inventory the Windows SQLite schema and document paths from verified copies.
- Map the existing SQLite model to the new server-side SQLite persistence layer.
- Define backup, reconciliation and rollback rules.

## Phase 1 — Read-only migration tooling

- Work only from a copied AccountantsNext.db.
- Inventory schema and document paths.
- Import entities and master data first.
- Import transactions second.
- Preserve source IDs/references for traceability.
- Import document metadata and copy binary supporting files separately.
- Never mutate the source copy during migration.

## Phase 2 — Production infrastructure

Only when the application is staging-ready:
- provision the low-cost netcup Nano VPS
- configure accounts.nextjailbreak.com
- install Docker/Caddy/self-hosted GitHub runner
- create private application data/document directories
- configure server-side OpenAI credentials
- configure automatic backups and restore testing

## Phase 3 — Reconciliation

For every migrated module compare:
- record counts
- transaction totals
- customer/project balances
- receipt/payment totals
- contract payment-plan allocations
- payroll totals where applicable
- report totals and cutoff-date behavior

Any mismatch blocks cutover.

## Phase 4 — Module sequence

1. Dashboard and entity context
2. Project Management
3. Payments / receipts
4. Manager reporting
5. Task tracker
6. HR / payroll
7. Remaining modules

## Phase 5 — Parallel validation

The single owner validates the web system against Windows. Windows remains operational as fallback.

## Phase 6 — Controlled cutover

Only after reconciliation, backup verification and restore testing is the web database treated as primary.
