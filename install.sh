#!/bin/sh
# Run tests, then copy Trust Advisor into the WoW: Forever AddOns folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/World of Warcraft/_forever_/Interface/AddOns/TrustAdvisor"
cd "$HERE/TrustAdvisor"
# Lua suites: one-line summary, stop on any failure
for t in test_scoring test_questie test_ingame_sim; do
  LOG=$(mktemp)
  if luajit "Tests/$t.lua" >"$LOG" 2>&1; then
    tail -1 "$LOG"
  else
    tail -25 "$LOG"; echo "$t FAILED"; rm -f "$LOG"; exit 1
  fi
  rm -f "$LOG"
done
# Python suites: show a one-line summary, but stop on any failure (a pipe would hide it)
for suite in server companion; do
  LOG=$(mktemp)
  if (cd "$HERE/$suite" && python3 -m unittest discover -s tests >"$LOG" 2>&1); then
    echo "$suite: $(grep -E '^Ran' "$LOG") OK"
  else
    cat "$LOG"; echo "$suite tests FAILED"; rm -f "$LOG"; exit 1
  fi
  rm -f "$LOG"
done
python3 "$HERE/tools/sync_docs.py" --check
rsync -a --delete --exclude Tests "$HERE/TrustAdvisor/" "$DEST/"
echo "Installed to $DEST  (type /reload in game)"
