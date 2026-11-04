#!/bin/sh
# Build the macOS companion, sign it with the Developer ID, notarize it with Apple,
# staple the ticket and attach it to the GitHub release companion-v<VERSION>.
#   "Trust Advisor Companion.app" (double-click: installs the background service,
#   offers the Battle.net link) -> TrustAdvisorCompanion-macos-app.zip
# Terminal users can run the same binary: "Trust Advisor Companion.app/Contents/MacOS/Trust Advisor Companion" --help
# (a loose CLI binary is not shipped: Gatekeeper rejects those when opened from Finder, even notarized)
# Needs Xcode, the "Developer ID Application" certificate, and notarization credentials:
#   xcrun notarytool store-credentials trustadvisor --apple-id <email> --team-id U3H5DHZP65
# SKIP_UPLOAD=1 builds and verifies without publishing.
set -e
cd "$(dirname "$0")"
IDENTITY="${IDENTITY:-Developer ID Application: Vinicius Luciano Menezes Cotrim (U3H5DHZP65)}"
PROFILE="${PROFILE:-trustadvisor}"
APP="Trust Advisor Companion"
VERSION=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' ta_companion.py)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT="${OUT:-$(pwd)/../dist/companion-$VERSION}"
mkdir -p "$OUT"

python3 -m unittest discover -s tests 2>&1 | tail -1
python3 -m venv "$WORK/venv" && "$WORK/venv/bin/pip" install -q pyinstaller==6.11.1
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict></dict></plist>\n' > "$WORK/ent.plist"
cp ta_companion.py "$WORK/"

# App icon from the Trust Advisor logo
ICONSET="$WORK/icon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s ../branding/logo-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) ../branding/logo-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/icon.icns"

cd "$WORK"
# 1) the .app
venv/bin/pyinstaller --windowed --target-arch universal2 --name "$APP" --icon icon.icns \
  --osx-bundle-identifier com.trustadvisor.companion --codesign-identity "$IDENTITY" \
  --osx-entitlements-file ent.plist --noconfirm --log-level ERROR ta_companion.py
for key in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Set :$key $VERSION" "dist/$APP.app/Contents/Info.plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key string $VERSION" "dist/$APP.app/Contents/Info.plist"
done
codesign --force --options runtime --timestamp --entitlements ent.plist --sign "$IDENTITY" "dist/$APP.app"
codesign --verify --deep --strict "dist/$APP.app"
# notarize, staple the ticket into the app, verify the Finder (execute) assessment
(cd dist && ditto -c -k --keepParent "$APP.app" ../submit.zip)
xcrun notarytool submit submit.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "dist/$APP.app"
spctl --assess --type execute -vv "dist/$APP.app"
"dist/$APP.app/Contents/MacOS/$APP" --version

(cd dist && ditto -c -k --sequesterRsrc --keepParent "$APP.app" "$OUT/TrustAdvisorCompanion-macos-app.zip")
echo "Built in $OUT"
if [ -z "$SKIP_UPLOAD" ]; then
  gh release upload "companion-v$VERSION" "$OUT/TrustAdvisorCompanion-macos-app.zip" --clobber
  echo "Published signed + notarized macOS companion $VERSION"
fi
