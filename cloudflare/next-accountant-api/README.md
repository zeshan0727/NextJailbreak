# Next Accountant Cloudflare API

Server-side data plane for Next Accountant Web.

- API target: https://accounts-api.nextjailbreak.com
- D1 database: next-accountant
- R2 files: next-accountant-files
- R2 backups: next-accountant-backups

## Security

GitHub contains code only. Never commit AccountantsNext.db, company/customer/employee data, receipts, contracts, supporting documents, API keys, owner tokens or backups.

Protected values belong in Cloudflare Worker Secrets.

## Migration endpoints

Only GET /health is public.

Authenticated administration endpoints:
- POST /api/admin/apply-schema
- POST /api/admin/import-batch
- GET /api/admin/tables
- GET /api/admin/counts
- GET /api/admin/export-table?table=...
- PUT/GET/DELETE /api/files/<object-key>

The live Windows Data folder is never modified by this service. Migration must use a verified copy/export and reconcile counts/totals before cutover.

Deployment token refreshed for R2-enabled deployment verification.
