# Security Baseline

## Repository
Production source must be private. Never commit secrets, business databases, backups or customer/employee documents.

## Network
- Public ports: 80/443 only.
- SSH restricted by key authentication and firewall.
- PostgreSQL bound to the private Docker network only.

## Application
- Strong password hashing.
- MFA-ready authentication.
- Per-user and per-entity authorization.
- Server-side session controls.
- CSRF protection.
- Upload content-type and size validation.
- Audit event logging for creates/edits/deletes/allocations.
- No credentials sent to the browser.

## Storage
- Supporting files stored in a private bucket.
- Randomized object keys; original filenames kept as metadata only.
- Signed/authorized downloads.
- Database and document backups tested by restore, not merely created.

## Migration
Legacy SQLite is opened read-only from a copy. The migration tool must never write to the Windows live Data folder.
