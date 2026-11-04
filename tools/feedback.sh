#!/bin/sh
# Read and answer in-game feedback (the only feedback channel).
#   tools/feedback.sh                      # new reports (status "received")
#   tools/feedback.sh all                  # everything
#   tools/feedback.sh reply <id> <status> "message shown to the player in game"
# Statuses: received, planned, fixed, done, wontfix, duplicate.
# Replies reach the player through the companion app on their next sync.
set -e
HOST="${FR_HOST:-root@72.62.142.237}"
KEY="${FR_KEY:-$HOME/.ssh/craft4d_pocketbase}"
run() { ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$HOST" "$1"; }
API='. /srv/forever-relationships/admin.env; curl -s -H "X-Admin-Token: $FR_ADMIN_TOKEN" http://127.0.0.1:10790'
case "${1:-new}" in
  new|all)
    Q=$([ "${1:-new}" = all ] && echo "" || echo "?status=received")
    run "$API/v1/admin/feedback$Q" | python3 -c '
import json, sys, time
items = json.load(sys.stdin)["feedback"]
if not items:
    print("No feedback.")
for f in items:
    print("=" * 72)
    print("%s  [%s]  %s  addon %s  %s" % (f["id"], f["kind"].upper(), f["status"], f["version"],
          time.strftime("%Y-%m-%d %H:%M", time.localtime(f["received_at"]))))
    print(f["text"] or "(no text, diagnostics only)")
    if f.get("diag"):
        d = json.loads(f["diag"])
        print("  client %s · %s · companion %s · network %s" % (d.get("build"), d.get("locale"), d.get("companion"), d.get("network")))
        for u in d.get("unavailable") or []:
            print("  unavailable: " + u)
        for e in d.get("errors") or []:
            print("  error: " + e)
    if f.get("reply"):
        print("  your reply: " + f["reply"])'
    ;;
  reply)
    [ $# -ge 3 ] || { echo "usage: tools/feedback.sh reply <id> <status> [\"message\"]"; exit 1; }
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"status": sys.argv[1], "reply": sys.argv[2] if len(sys.argv) > 2 else None}))' "$3" "$4")
    printf '%s' "$BODY" | run "$API/v1/admin/feedback/$2 -X POST -H 'Content-Type: application/json' --data-binary @-"; echo
    ;;
  *) sed -n '2,8p' "$0" ;;
esac
