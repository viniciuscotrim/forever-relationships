# Forever Relationships server

Python 3.8+ standard library + SQLite, plus `cryptography` (admin passkeys). Protocol v2: consent-gated sync, encrypted backups (opaque blobs), public profiles, pseudonymized community sessions, suggestions among opted-in players, in-game feedback, Battle.net linking and the `/me` self-service page. See `../docs/NETWORK.md` and `../docs/GDD-v2.md`.

```sh
python3 -m unittest discover -s tests -v
FR_HASH_SALT=change-me python3 -m frnet.app          # http://localhost:8080
docker build -t forever-relationships . && docker run -p 8080:8080 -v fr-data:/data -e FR_HASH_SALT=... forever-relationships
```

Put it behind HTTPS. Env: `FR_DB`, `FR_PORT`, `FR_HASH_SALT` (keys the pseudonyms; never change it), `FR_ADMIN_ORIGIN`, `FR_PUBLIC_URLS`, `FR_BNET_CLIENT_ID`, `FR_BNET_CLIENT_SECRET`. Production: `../docs/DEPLOY.md`. Admin cockpit: `../docs/COCKPIT.md`.
