# Architecture

## Production topology

Browser / mobile browser
→ accounts.nextjailbreak.com
→ Caddy (TLS, security headers, reverse proxy)
→ NextAccountant.Web (.NET 10)
→ PostgreSQL

Supporting documents:
NextAccountant.Web → private Cloudflare R2 bucket

AI document reading:
NextAccountant.Web → server-side OpenAI API

Backups:
PostgreSQL dump + document manifest → encrypted off-server backup storage

## Application layering

- **NextAccountant.Web**: responsive UI, authentication, authorization, API endpoints.
- **NextAccountant.Core**: accounting/domain rules migrated from the Windows service layer.
- **NextAccountant.Infrastructure**: PostgreSQL persistence, R2 storage, OpenAI integration, PDF/report services.
- **NextAccountant.Migration**: read-only import/reconciliation from a copied Windows SQLite database.

## Non-negotiable rules

1. Never expose PostgreSQL directly to the public internet.
2. Never expose OpenAI/R2/database credentials to the browser.
3. Never import from the live Windows database in place.
4. Preserve transaction audit history.
5. Web cutover occurs only after reconciliation against the Windows system.
