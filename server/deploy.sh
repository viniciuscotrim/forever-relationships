#!/bin/sh
# Update the Forever Relationships server on the VPS (isolated deployment).
# Usage: ./deploy.sh root@HOST [ssh-key]
# Layout on the host: /srv/trustadvisor/{app,data,admin.env,blizzard.env}, container "trustadvisor-net"
# bound to 127.0.0.1:10790, nginx site /etc/nginx/sites-available/trustadvisor-net.
set -e
HOST="$1"; KEY="${2:-$HOME/.ssh/id_ed25519}"
[ -n "$HOST" ] || { echo "usage: ./deploy.sh root@HOST [ssh-key]"; exit 1; }
cd "$(dirname "$0")"
VENV="$(pwd)/../.venv-server"   # server tests need `cryptography`
[ -x "$VENV/bin/python" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r requirements.txt; }
LOG=$(mktemp)
if "$VENV/bin/python" -m unittest discover -s tests >"$LOG" 2>&1; then grep -E '^Ran' "$LOG"; rm -f "$LOG"
else cat "$LOG"; rm -f "$LOG"; echo "server tests FAILED: not deploying"; exit 1; fi
VERSION=$(sed -n 's/^## Version: //p' ../TrustAdvisor/TrustAdvisor.toc | tr -d '\r')
COPYFILE_DISABLE=1 tar --exclude __pycache__ --exclude tests -cf - . | \
  ssh -i "$KEY" -o IdentitiesOnly=yes "$HOST" 'rm -rf /srv/trustadvisor/app && mkdir -p /srv/trustadvisor/app && tar -C /srv/trustadvisor/app -xf -'
ssh -i "$KEY" -o IdentitiesOnly=yes "$HOST" "
set -e
docker build -q -t trustadvisor-net:$VERSION /srv/trustadvisor/app >/dev/null
docker rm -f trustadvisor-net >/dev/null 2>&1 || true
docker run -d --name trustadvisor-net --restart unless-stopped -p 127.0.0.1:10790:8080 \
  -v /srv/trustadvisor/data:/data --env-file /srv/trustadvisor/admin.env \
  \$( [ -f /srv/trustadvisor/blizzard.env ] && echo --env-file /srv/trustadvisor/blizzard.env ) \
  --memory 256m --cpus 0.5 --pids-limit 64 --read-only --tmpfs /tmp \
  --security-opt no-new-privileges --cap-drop ALL trustadvisor-net:$VERSION >/dev/null
sleep 2; curl -fs http://127.0.0.1:10790/healthz && echo ' deployed $VERSION'
docker logs trustadvisor-net 2>&1 | grep -i 'battle.net' | tail -1"
