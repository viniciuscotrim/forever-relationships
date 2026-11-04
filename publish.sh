#!/bin/sh
# Build TrustAdvisor-<version>.zip and upload it to an EXISTING CurseForge project.
# Usage: ./publish.sh <projectId> [alpha|beta|release]
# The token is read at runtime from "CurseForge API.rtf" and never printed or packaged.
set -e
PROJECT="$1"; TYPE="${2:-alpha}"
[ -n "$PROJECT" ] || { echo "usage: ./publish.sh <projectId> [alpha|beta|release]"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
VERSION=$(sed -n 's/^## Version: //p' TrustAdvisor/TrustAdvisor.toc | tr -d '\r')
TOKEN=$(textutil -convert txt -stdout "CurseForge API.rtf" | grep -oE '[A-Za-z0-9._-]{20,}' | head -1)
[ -n "$TOKEN" ] || { echo "no token found in CurseForge API.rtf"; exit 1; }
FOREVER_VERSION_ID=17053   # CurseForge game version "1.60.1" (WoW: Forever, interface 16001)

./install.sh
mkdir -p dist
ZIP="dist/TrustAdvisor-$VERSION.zip"
rm -f "$ZIP"
zip -qr "$ZIP" TrustAdvisor -x "TrustAdvisor/Tests/*" -x "*/.DS_Store"
echo "Built $ZIP"

META=$(python3 -I - "$VERSION" "$TYPE" "$FOREVER_VERSION_ID" "$HERE/CHANGELOG.md" <<'PY'
import json, sys
v, t, gv, cl = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
print(json.dumps({
  "displayName": "Trust Advisor " + v,
  "releaseType": t,
  "gameVersions": [gv],
  "changelogType": "markdown",
  "changelog": open(cl, encoding="utf-8").read(),
}))
PY
)
RESP=$(curl -s -w "\nHTTP %{http_code}" -H "X-Api-Token: $TOKEN" \
  --form-string "metadata=$META" -F "file=@$ZIP" \
  "https://wow.curseforge.com/api/projects/$PROJECT/upload-file")
echo "$RESP"
