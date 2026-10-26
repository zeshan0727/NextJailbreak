# Security Baseline

## User model

Single owner/user only. No team accounts, invitations, role matrix or collaboration system is required.

## Repository

Production source must be private. Never commit secrets, business databases, backups or customer/employee documents.

## Deployment

- Use a self-hosted GitHub runner on the VPS for normal build/deploy automation.
- Store deployment credentials only in protected server/GitHub secret storage.
- Deployment runs preflight, backup, migration, health check and rollback logic.
- A failed health check must never be reported as a successful deployment.

## Network

- Public ports: 80/443 only.
- SSH uses key authentication and firewall restrictions.
- The SQLite database and document directories are never web-served.
- Caddy manages HTTPS certificates and renewal automatically.

## Application

- Single-owner secure authentication.
- Strong password hashing.
- MFA-ready owner sign-in.
- Server-side sessions.
- CSRF protection.
- Upload content-type and size validation.
- Audit event logging for creates/edits/deletes/allocations.
- No credentials sent to browser code.

## Data

- SQLite database is server-side only.
- WAL mode/transaction discipline is used where appropriate.
- Supporting files remain in a private server folder.
- Application downloads require authorization.
- Database and documents are backed up automatically.

## Backup

- Run consistent SQLite online backups rather than copying a live database blindly.
- Archive supporting documents independently.
- Encrypt off-site backups.
- Rotate backups to remain within the selected off-site storage allowance.
- Verify backups by automated integrity checks and periodic restore testing.
- Alert before server disk or off-site backup capacity is exhausted.

## Migration

The legacy Windows SQLite database is opened read-only from a verified copy. Migration tooling must never write to the Windows live Data folder.
