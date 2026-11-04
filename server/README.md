# Trust Advisor network server

Python 3.8+ standard library + SQLite. Aggregates witness reports from the companion app and enforces the network fairness rules (see `../docs/NETWORK.md`).

```sh
python3 -m unittest discover -s tests -v      # fairness rules + API
TA_ADMIN_TOKEN=change-me python3 -m trustnet.app   # http://localhost:8080
docker build -t trustadvisor-net . && docker run -p 8080:8080 -v ta-data:/data -e TA_ADMIN_TOKEN=... trustadvisor-net
```

Put it behind HTTPS (Caddy, nginx, or the platform's TLS). Env: `TA_DB`, `TA_PORT`, `TA_ADMIN_TOKEN`.

Dispute review: `GET /v1/admin/disputes` and `POST /v1/admin/disputes/<id>` with `{"status": "upheld"|"rejected"}`, header `X-Admin-Token`.
