# Next Accountant Web — Preparation Bootstrap

Target: **https://accounts.nextjailbreak.com**

This folder is the public-safe bootstrap for migrating the Windows ACCOUNTANTS application to a secure web platform.

## Important security boundary

This repository is public. Do **not** commit:
- AccountantsNext.db or any business database
- Company/customer/employee documents
- OpenAI keys, database passwords, R2 credentials or SSH keys
- Production backups
- The proprietary Windows ACCOUNTANTS source snapshot

The production application source must move to a **private GitHub repository** before business logic is ported.

## Target stack

- ASP.NET Core / Blazor Web App on .NET 10 LTS
- PostgreSQL
- Caddy automatic HTTPS
- Docker Compose
- Cloudflare R2 for private supporting documents and encrypted off-server backups
- GitHub Actions for build/test/deploy
- Target hostname: accounts.nextjailbreak.com

## Migration principle

The Windows application remains the authoritative fallback until web parity is proven. Migration always starts from a verified copy of the business database; the live Windows Data folder is never modified by the web migration process.

See ARCHITECTURE.md, MIGRATION.md, HOSTING.md and SECURITY.md.
