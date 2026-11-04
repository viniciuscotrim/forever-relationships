# Server deployment (production)

**URL:** https://forever.gameplaybr.com.br (default in the companion app since 0.4.0). `https://trustadvisor.gameplaybr.com.br` serves the same server for older installs.

**Status:** live behind Cloudflare since 2026-11-04 (proxied, SSL Full (strict), origin locked to Cloudflare's IP ranges). The legacy `https://trustadvisor.72-62-142-237.sslip.io` remains only as the companion's automatic fallback.

The server runs isolated on a shared VPS that also hosts other services. Do not touch anything outside the paths below.

| Piece | Where |
|---|---|
| Code and Docker build context | `/srv/trustadvisor/app` |
| SQLite database (volume) | `/srv/trustadvisor/data/trustnet.sqlite3` |
| Daily backups (keep 14) | `/srv/trustadvisor/data/backups/`, cron `/etc/cron.d/trustadvisor-backup` (04:17) |
| Account-hash salt (and legacy admin token) | `/srv/trustadvisor/admin.env` (root, 600). **Never change `TA_HASH_SALT`**, or every Battle.net link breaks |
| Battle.net OAuth client | `/srv/trustadvisor/blizzard.env` (root, 600): `TA_BNET_CLIENT_ID`, `TA_BNET_CLIENT_SECRET`, `TA_PUBLIC_URLS`. Redirect URLs registered at develop.battle.net: `https://forever.gameplaybr.com.br/v1/auth/callback`, `https://trustadvisor.gameplaybr.com.br/v1/auth/callback` and the sslip.io one. The server picks the callback that matches the request's host |
| Container | `trustadvisor-net`: `127.0.0.1:10790` only, 256 MB, 0.5 CPU, read-only, no capabilities, uid 65534, restart unless-stopped |
| nginx | its own file `/etc/nginx/sites-available/trustadvisor-net` (HTTP: ACME + redirect; HTTPS: proxy) |
| TLS | Let's Encrypt via webroot `/var/www/trustadvisor-acme`, auto-renew with nginx reload. `--dry-run` cannot be used here: the VPS can't reach LE *staging*, but it does reach production (see BACKLOG TA-2) |

DNS is on Cloudflare (zone `gameplaybr.com.br`). The `forever` and `trustadvisor` records are **proxied**, with SSL mode **Full (strict)**, so the public sees Cloudflare's IPs. The HTTPS server blocks for these names accept connections **only from Cloudflare's IP ranges**, and takes the client IP for rate limiting from `CF-Connecting-IP`. Certificate renewals (HTTP-01) pass through Cloudflare. The local Cloudflare token (`cloudflare.key`, git-ignored) can only edit this zone's DNS and settings.

Legacy `trustadvisor.72-62-142-237.sslip.io` (direct, no Cloudflare) is kept as a fallback for early companion installs. Remove it, and drop it from `FALLBACK_SERVERS` in the companion, once old installs have updated.

Cloudflare's IP ranges are pinned in the nginx `allow` list. If Cloudflare publishes new ranges (https://www.cloudflare.com/ips), update the list.

## Update
```sh
server/deploy.sh root@72.62.142.237 ~/.ssh/<key>
```

## Cockpit and demo data
See `COCKPIT.md`.

## Remove completely
```sh
docker rm -f trustadvisor-net; docker rmi $(docker images -q trustadvisor-net)
rm /etc/nginx/sites-enabled/trustadvisor-net /etc/nginx/sites-available/trustadvisor-net && nginx -t && systemctl reload nginx
certbot delete --cert-name trustadvisor.72-62-142-237.sslip.io; certbot delete --cert-name trustadvisor.gameplaybr.com.br; certbot delete --cert-name forever.gameplaybr.com.br; rm /etc/cron.d/trustadvisor-backup; rm -rf /srv/trustadvisor /var/www/trustadvisor-acme
```
