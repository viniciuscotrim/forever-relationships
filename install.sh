#!/bin/sh
# Run tests, then copy Forever Relationships into the WoW: Forever AddOns folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/World of Warcraft/_forever_/Interface/AddOns/ForeverRelationships"
cd "$HERE/ForeverRelationships"
# Lua suites: one-line summary, stop on any failure
for t in test_relationship test_questie test_ingame_sim; do
  LOG=$(mktemp)
  if luajit "Tests/$t.lua" >"$LOG" 2>&1; then
    tail -1 "$LOG"
  else
    tail -25 "$LOG"; echo "$t FAILED"; rm -f "$LOG"; exit 1
  fi
  rm -f "$LOG"
done
# Python suites: show a one-line summary, but stop on any failure (a pipe would hide it).
# The server needs `cryptography` (passkeys): use a local, git-ignored venv for its tests.
VENV="$HERE/.venv-server"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r "$HERE/server/requirements.txt"
fi
for suite in server companion; do
  LOG=$(mktemp)
  # companion tests start the real server end to end, so both use the venv
  if (cd "$HERE/$suite" && "$VENV/bin/python" -m unittest discover -s tests >"$LOG" 2>&1); then
    echo "$suite: $(grep -E '^Ran' "$LOG") OK"
  else
    cat "$LOG"; echo "$suite tests FAILED"; rm -f "$LOG"; exit 1
  fi
  rm -f "$LOG"
done
python3 "$HERE/tools/sync_docs.py" --check
python3 "$HERE/tools/locale_keys.py" --check   # every language has every text, same placeholders in the same order
rsync -a --delete --exclude Tests "$HERE/ForeverRelationships/" "$DEST/"
# the addon's previous folder name, so both don't load
OLD="$(dirname "$DEST")/Trust""Advisor"
[ -d "$OLD" ] && rm -rf "$OLD" && echo "Removed the previous addon folder"
echo "Installed to $DEST  (type /reload in game)"
