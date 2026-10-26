# Windows → Web Migration Plan

Baseline for preparation: ACCOUNTANTS 6.1.x Windows line, with the Windows application retained as recovery/fallback.

## Phase 0 — Preparation
- Establish private GitHub repository for production source.
- Provision staging server.
- Configure accounts.nextjailbreak.com.
- Create PostgreSQL staging database.
- Configure private object storage.
- Establish automated backups and restore test.

## Phase 1 — Read-only migration tooling
- Work only from a copied AccountantsNext.db.
- Inventory SQLite schema and document paths.
- Translate schema additively to PostgreSQL.
- Import entities and master data first.
- Import transactions second.
- Import document metadata; copy binary files separately.
- Record source-row identifiers for traceability.

## Phase 2 — Reconciliation
For each module compare:
- record counts
- transaction totals
- customer/project balances
- payroll totals where applicable
- receipt/payment totals
- report totals and cutoff-date behavior

Any mismatch blocks cutover.

## Phase 3 — Web modules
Suggested sequence:
1. Dashboard and entity context
2. Project Management
3. Receipts / payments
4. Manager reporting
5. Task tracker
6. HR / payroll
7. Remaining modules

## Phase 4 — Parallel run
Windows remains operational while selected users validate the web platform.

## Phase 5 — Controlled cutover
Only after signed reconciliation and restore testing is the web database treated as primary.
