#!/bin/sh
# Read and answer in-game feedback (the only feedback channel).
#   tools/feedback.sh                      # new reports (status "received")
#   tools/feedback.sh all                  # everything
#   tools/feedback.sh reply <id> <status> "message shown to the player in game"
# Statuses: received, planned, fixed, done, wontfix, duplicate.
# Replies reach the player through the companion app on their next sync.
# Works on the server's SQLite file over SSH (the old token API was replaced by the Cockpit).
set -e
HOST="${FR_HOST:-root@72.62.142.237}"
KEY="${FR_KEY:-$HOME/.ssh/craft4d_pocketbase}"
DB=/srv/forever-relationships/data/frnet.sqlite3
run_py() { ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$HOST" "python3 - $*"; }
case "${1:-new}" in
  new|all)
    run_py "$DB ${1:-new}" <<'PY'
import json, sqlite3, sys, time
db, mode = sys.argv[1], sys.argv[2]
c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
c.row_factory = sqlite3.Row
sql = "SELECT id, kind, text, version, diag, received_at, status, reply FROM feedback"
rows = c.execute(sql + ("" if mode == "all" else " WHERE status = 'received'") + " ORDER BY received_at").fetchall()
if not rows:
    print("No feedback.")
for f in rows:
    print("=" * 72)
    print("%s  [%s]  %s  addon %s  %s" % (f["id"], f["kind"].upper(), f["status"], f["version"],
          time.strftime("%Y-%m-%d %H:%M", time.localtime(f["received_at"]))))
    print(f["text"] or "(no text, diagnostics only)")
    if f["diag"]:
        d = json.loads(f["diag"])
        print("  client %s · %s · companion %s · layers %s" % (d.get("build"), d.get("locale"), d.get("companionVersion") or d.get("companion"), d.get("layers")))
        for u in d.get("unavailable") or []:
            print("  unavailable: " + u)
        for e in d.get("errors") or []:
            print("  error: " + e)
    if f["reply"]:
        print("  your reply: " + f["reply"])
PY
    ;;
  reply)
    [ $# -ge 3 ] || { echo "usage: tools/feedback.sh reply <id> <status> [\"message\"]"; exit 1; }
    # arguments travel base64-encoded so any message text survives the remote shell
    ENC=$(python3 -c 'import base64,json,sys; print(base64.b64encode(json.dumps(sys.argv[1:]).encode()).decode())' "$2" "$3" "${4:-}")
    run_py "$DB $ENC" <<'PY'
import base64, json, sqlite3, sys, time
fid, status, reply = json.loads(base64.b64decode(sys.argv[2]))
if status not in ("received", "planned", "fixed", "done", "wontfix", "duplicate"):
    sys.exit("bad status: " + status)
c = sqlite3.connect(sys.argv[1], timeout=10)
n = c.execute("UPDATE feedback SET status = ?, reply = COALESCE(?, reply), updated_at = ? WHERE id = ?",
              (status, reply or None, int(time.time()), fid)).rowcount
c.commit()
print("updated" if n else "no such feedback id: " + fid)
PY
    ;;
  *) sed -n '2,8p' "$0" ;;
esac
