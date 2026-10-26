# Hosting Plan

## Selected low-cost target

**netcup VPS nano G11.5s**
- 2 vCore x86
- 2 GB RAM
- 60 GB SSD
- traffic included
- Nuremberg location
- target price about EUR 3.69/month including the price currently displayed by netcup

This is the preferred minimum for production. The cheaper 1 GB plan is intentionally avoided because .NET, Docker, deployment builds, backups and the self-hosted runner need additional headroom.

## Initial topology

- Linux VPS
- 2 GB swap in addition to RAM for deployment/build spikes
- Docker Compose
- Caddy
- NextAccountant.Web (.NET 10)
- server-side SQLite
- local private document storage
- automated encrypted off-site backup
- self-hosted GitHub Actions runner

There is no PostgreSQL service in the initial single-user release.

## Capacity policy

The application does not depend on a free-tier request allowance or sleep policy. Capacity is bounded by the VPS CPU/RAM/60 GB disk. Monitoring warns before disk or backup capacity becomes critical.

The database and document layout are upgrade-ready. If usage grows, move to a larger VPS first; migrate to PostgreSQL only if concurrency/data-volume requirements justify it.

## DNS

Production hostname: **accounts.nextjailbreak.com**

After the VPS receives a public IP:
- create an A record for `accounts` pointing to the VPS IPv4
- optionally create an AAAA record for IPv6
- do not change the existing `nextjailbreak.com` GitHub Pages records

Caddy obtains and renews TLS certificates automatically after DNS resolves.

## Deployment timing

Do not start paying for the VPS while core development is still preparation-only. Provision it when the first staging-ready web build and migration test are ready.

## Staging / cutover

Windows ACCOUNTANTS remains the fallback. No live business write activity moves to web until database counts, balances, receipts, project allocations and reports reconcile.
