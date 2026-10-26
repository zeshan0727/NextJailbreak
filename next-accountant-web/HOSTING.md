# Hosting Plan

## Recommended first deployment

A small Linux VPS is preferable to GitHub Pages for the production application because the application needs server-side .NET execution, PostgreSQL, authentication and private document handling.

Initial topology:
- 1 small VPS
- Docker Compose
- Caddy
- NextAccountant.Web
- PostgreSQL
- Cloudflare R2 for documents/off-server backups

GitHub remains the source-control and CI/CD system, not the production accounting database.

## DNS

Production hostname: **accounts.nextjailbreak.com**

After the VPS receives a public IP:
- Create an A record for `accounts` pointing to the VPS IPv4.
- Optionally create an AAAA record for IPv6.
- Do not change the existing `nextjailbreak.com` GitHub Pages records.

Caddy obtains and renews TLS certificates automatically after DNS resolves.

## Staging

Before production cutover, use:
- staging-accounts.nextjailbreak.com

No live business write activity should be enabled until reconciliation is complete.
