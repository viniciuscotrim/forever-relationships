# Forever Relationships server

Python 3.8+ standard library + SQLite, plus `cryptography` (admin passkeys). Protocol v2: consent-gated sync, encrypted backups (opaque blobs), public profiles, pseudonymized community sessions, suggestions among opted-in players, in-game feedback, Battle.net linking and the `/me` self-service page. See `../docs/NETWORK.md` and `../docs/GDD-v2.md`.

```sh
python3 -m unittest discover -s tests -v
TA_HASH_SALT=change-me python3 -m trustnet.app          # http://localhost:8080
docker build -t trustadvisor-net . && docker run -p 8080:8080 -v ta-data:/data -e TA_HASH_SALT=... trustadvisor-net
```

Put it behind HTTPS. Env: `TA_DB`, `TA_PORT`, `TA_HASH_SALT` (keys the pseudonyms; never change it), `TA_ADMIN_ORIGIN`, `TA_PUBLIC_URLS`, `TA_BNET_CLIENT_ID`, `TA_BNET_CLIENT_SECRET`. Production: `../docs/DEPLOY.md`. Admin cockpit: `../docs/COCKPIT.md`.
