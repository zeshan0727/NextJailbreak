# Architecture

## User model

Next Accountant Web is a **single-owner system**. There are no teams, invitations, user roles or collaboration features.

## Production topology

Browser / mobile browser
→ accounts.nextjailbreak.com
→ Caddy (automatic HTTPS + reverse proxy)
→ NextAccountant.Web (.NET 10)
→ server-side SQLite

Supporting documents:
NextAccountant.Web → private local document folder on the VPS

AI document reading:
NextAccountant.Web → server-side OpenAI API

Backups:
SQLite online backup + document archive → automated encrypted off-site backup

GitHub:
Private source repository → self-hosted GitHub runner on the VPS → automatic build/test/deploy

## Why SQLite first

ACCOUNTANTS is single-user. PostgreSQL is unnecessary overhead for the initial production release. Server-side SQLite gives us transactional persistence, keeps the migration close to the existing Windows data model, lowers RAM usage and lets the application run safely on a much cheaper VPS.

The persistence layer remains abstracted so PostgreSQL can replace SQLite later without changing the accounting/domain rules.

## Zero-touch operating target

Normal owner involvement after initial provisioning: **none**.

- Pushes to the production branch build, test and deploy automatically.
- The self-hosted runner avoids depending on GitHub-hosted Actions-minute quotas for normal deployment.
- Docker services restart automatically after failures/reboots.
- Caddy obtains and renews TLS certificates automatically.
- Database/document backups run automatically.
- Health checks run automatically.
- Disk/backup thresholds are checked automatically.
- Failed application health checks stop or roll back deployments.

## Application layering

- **NextAccountant.Web**: responsive single-owner UI, secure authentication and API endpoints.
- **NextAccountant.Core**: accounting/domain rules migrated from the Windows service layer.
- **NextAccountant.Infrastructure**: SQLite persistence, document storage, OpenAI integration and PDF/report services.
- **NextAccountant.Migration**: read-only import/reconciliation from a copied Windows SQLite database.

## Non-negotiable rules

1. Never expose the database file directly to the web.
2. Never expose OpenAI/storage/deployment credentials to browser JavaScript.
3. Never import from the live Windows database in place.
4. Preserve transaction audit history.
5. Web cutover occurs only after reconciliation against the Windows system.
6. Windows ACCOUNTANTS remains the recovery fallback until web parity is proven.
