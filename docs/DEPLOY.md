# Server deployment (production)

**URL:** https://forever.gameplaybr.com.br (the companion app's default).

**Status:** live behind Cloudflare (proxied, SSL Full (strict), origin locked to Cloudflare's IP ranges).

The server runs isolated on a shared VPS that also hosts other services. Do not touch anything outside the paths below.

| Piece | Where |
|---|---|
| Code and Docker build context | `/srv/forever-relationships/app` |
| SQLite database (volume) | `/srv/forever-relationships/data/frnet.sqlite3` |
| Daily backups (keep 14) | `/srv/forever-relationships/data/backups/`, cron `/etc/cron.d/forever-relationships-backup` (04:17) |
| Account-hash salt (and legacy admin token) | `/srv/forever-relationships/admin.env` (root, 600). **Never change `FR_HASH_SALT`**, or every Battle.net link breaks |
| Battle.net OAuth client | `/srv/forever-relationships/blizzard.env` (root, 600): `FR_BNET_CLIENT_ID`, `FR_BNET_CLIENT_SECRET`, `FR_PUBLIC_URLS`. Redirect URL registered at develop.battle.net: `https://forever.gameplaybr.com.br/v1/auth/callback` |
| Container | `forever-relationships`: `127.0.0.1:10790` only, 256 MB, 0.5 CPU, read-only, no capabilities, uid 65534, restart unless-stopped |
| nginx | its own file `/etc/nginx/sites-available/forever-relationships` (HTTP: ACME + redirect; HTTPS: proxy) |
| TLS | Let's Encrypt via webroot `/var/www/forever-relationships-acme`, auto-renew with nginx reload. `--dry-run` cannot be used here: the VPS can't reach LE *staging*, but it does reach production (see BACKLOG TA-2) |

DNS is on Cloudflare (zone `gameplaybr.com.br`). The `forever` record is **proxied**, with SSL mode **Full (strict)**, so the public sees Cloudflare's IPs. The HTTPS server block accepts connections **only from Cloudflare's IP ranges**, and takes the client IP for rate limiting from `CF-Connecting-IP`. Certificate renewals (HTTP-01) pass through Cloudflare. The local Cloudflare token (`cloudflare.key`, git-ignored) can only edit this zone's DNS and settings.


Cloudflare's IP ranges are pinned in the nginx `allow` list. If Cloudflare publishes new ranges (https://www.cloudflare.com/ips), update the list.

## Update
```sh
server/deploy.sh root@72.62.142.237 ~/.ssh/<key>
```

## Cockpit and demo data
See `COCKPIT.md`.

## Remove completely
```sh
docker rm -f forever-relationships; docker rmi $(docker images -q forever-relationships)
rm /etc/nginx/sites-enabled/forever-relationships /etc/nginx/sites-available/forever-relationships && nginx -t && systemctl reload nginx
certbot delete --cert-name forever.gameplaybr.com.br; rm /etc/cron.d/forever-relationships-backup /etc/nginx/conf.d/forever-relationships-realip.conf; rm -rf /srv/forever-relationships /var/www/forever-relationships-acme
```
