#!/bin/sh
# Run tests, then copy Trust Advisor into the WoW: Forever AddOns folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/World of Warcraft/_forever_/Interface/AddOns/TrustAdvisor"
cd "$HERE/TrustAdvisor"
luajit Tests/test_scoring.lua | tail -1
luajit Tests/test_questie.lua
luajit Tests/test_ingame_sim.lua | tail -1
(cd "$HERE/server" && python3 -m unittest discover -s tests 2>&1 | tail -1)
(cd "$HERE/companion" && python3 -m unittest discover -s tests 2>&1 | tail -1)
rsync -a --delete --exclude Tests "$HERE/TrustAdvisor/" "$DEST/"
echo "Installed to $DEST  (type /reload in game)"
