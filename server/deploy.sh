#!/bin/sh
# Update the Forever Relationships server on the VPS (isolated deployment).
# Usage: ./deploy.sh root@HOST [ssh-key]
# Layout on the host: /srv/forever-relationships/{app,data,admin.env,blizzard.env}, container "forever-relationships"
# bound to 127.0.0.1:10790, nginx site /etc/nginx/sites-available/forever-relationships.
set -e
HOST="$1"; KEY="${2:-$HOME/.ssh/id_ed25519}"
[ -n "$HOST" ] || { echo "usage: ./deploy.sh root@HOST [ssh-key]"; exit 1; }
cd "$(dirname "$0")"
VENV="$(pwd)/../.venv-server"   # server tests need `cryptography`
[ -x "$VENV/bin/python" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r requirements.txt; }
LOG=$(mktemp)
if "$VENV/bin/python" -m unittest discover -s tests >"$LOG" 2>&1; then grep -E '^Ran' "$LOG"; rm -f "$LOG"
else cat "$LOG"; rm -f "$LOG"; echo "server tests FAILED: not deploying"; exit 1; fi
VERSION=$(sed -n 's/^## Version: //p' ../ForeverRelationships/ForeverRelationships.toc | tr -d '\r')
COPYFILE_DISABLE=1 tar --exclude __pycache__ --exclude tests -cf - . | \
  ssh -i "$KEY" -o IdentitiesOnly=yes "$HOST" 'rm -rf /srv/forever-relationships/app && mkdir -p /srv/forever-relationships/app && tar -C /srv/forever-relationships/app -xf -'
ssh -i "$KEY" -o IdentitiesOnly=yes "$HOST" "
set -e
docker build -q -t forever-relationships:$VERSION /srv/forever-relationships/app >/dev/null
docker rm -f forever-relationships >/dev/null 2>&1 || true
docker run -d --name forever-relationships --restart unless-stopped -p 127.0.0.1:10790:8080 \
  -v /srv/forever-relationships/data:/data --env-file /srv/forever-relationships/admin.env \
  \$( [ -f /srv/forever-relationships/blizzard.env ] && echo --env-file /srv/forever-relationships/blizzard.env ) \
  --memory 256m --cpus 0.5 --pids-limit 64 --read-only --tmpfs /tmp \
  --security-opt no-new-privileges --cap-drop ALL forever-relationships:$VERSION >/dev/null
sleep 2; curl -fs http://127.0.0.1:10790/healthz && echo ' deployed $VERSION'
docker logs forever-relationships 2>&1 | grep -i 'battle.net' | tail -1"
