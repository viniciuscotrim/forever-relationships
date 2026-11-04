# Network server deployment (production)

**URL:** https://trustadvisor.gameplaybr.com.br (default in the companion app)

The server runs isolated on a shared VPS that also hosts other services. Do not touch anything outside the paths below.

| Piece | Where |
|---|---|
| Code and Docker build context | `/srv/trustadvisor/app` |
| SQLite database (volume) | `/srv/trustadvisor/data/trustnet.sqlite3` |
| Daily backups (keep 14) | `/srv/trustadvisor/data/backups/`, cron `/etc/cron.d/trustadvisor-backup` (04:17) |
| Admin token + account-hash salt | `/srv/trustadvisor/admin.env` (root, 600). **Never change `TA_HASH_SALT`**, or every Battle.net link breaks |
| Battle.net OAuth client | `/srv/trustadvisor/blizzard.env` (root, 600): `TA_BNET_CLIENT_ID`, `TA_BNET_CLIENT_SECRET`, `TA_PUBLIC_URLS`. Redirect URLs registered at develop.battle.net: `https://trustadvisor.gameplaybr.com.br/v1/auth/callback` and the sslip.io one |
| Container | `trustadvisor-net`: `127.0.0.1:10790` only, 256 MB, 0.5 CPU, read-only, no capabilities, uid 65534, restart unless-stopped |
| nginx | its own file `/etc/nginx/sites-available/trustadvisor-net` (HTTP: ACME + redirect; HTTPS: proxy) |
| TLS | Let's Encrypt via webroot `/var/www/trustadvisor-acme`, auto-renew with nginx reload |

DNS is on Cloudflare (zone `gameplaybr.com.br`). The `trustadvisor` record is **proxied**, with SSL mode **Full (strict)**, so the public sees Cloudflare's IPs. The HTTPS server block for this name accepts connections **only from Cloudflare's IP ranges**, and takes the client IP for rate limiting from `CF-Connecting-IP`. Certificate renewals (HTTP-01) pass through Cloudflare. The local Cloudflare token (`cloudflare.key`, git-ignored) can only edit this zone's DNS and settings.

Legacy `trustadvisor.72-62-142-237.sslip.io` (direct, no Cloudflare) is kept temporarily for early companion installs. Remove it once they have updated.

## Update
```sh
server/deploy.sh root@72.62.142.237 ~/.ssh/<key>
```

## Review disputes
```sh
ssh root@VPS 'source /srv/trustadvisor/admin.env; curl -s -H "X-Admin-Token: $TA_ADMIN_TOKEN" http://127.0.0.1:10790/v1/admin/disputes'
ssh root@VPS 'source /srv/trustadvisor/admin.env; curl -s -X POST -H "X-Admin-Token: $TA_ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"status\":\"upheld\"}" http://127.0.0.1:10790/v1/admin/disputes/<id>'
```

## Remove completely
```sh
docker rm -f trustadvisor-net; docker rmi trustadvisor-net:0.2.0
rm /etc/nginx/sites-enabled/trustadvisor-net /etc/nginx/sites-available/trustadvisor-net && nginx -t && systemctl reload nginx
certbot delete --cert-name trustadvisor.72-62-142-237.sslip.io; certbot delete --cert-name trustadvisor.gameplaybr.com.br; rm /etc/cron.d/trustadvisor-backup; rm -rf /srv/trustadvisor /var/www/trustadvisor-acme
```
