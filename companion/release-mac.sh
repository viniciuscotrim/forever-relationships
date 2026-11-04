#!/bin/sh
# Build a universal (Apple Silicon + Intel) companion, sign it with the Developer ID,
# notarize it with Apple and attach it to the GitHub release companion-v<VERSION>.
# Needs: Xcode, the "Developer ID Application" certificate in the login keychain, and
# notarization credentials stored once with:
#   xcrun notarytool store-credentials trustadvisor --apple-id <email> --team-id U3H5DHZP65
set -e
cd "$(dirname "$0")"
IDENTITY="${IDENTITY:-Developer ID Application: Vinicius Luciano Menezes Cotrim (U3H5DHZP65)}"
PROFILE="${PROFILE:-trustadvisor}"
VERSION=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' ta_companion.py)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 -m unittest discover -s tests 2>&1 | tail -1
python3 -m venv "$WORK/venv" && "$WORK/venv/bin/pip" install -q pyinstaller==6.11.1
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict></dict></plist>\n' > "$WORK/ent.plist"
cp ta_companion.py "$WORK/"
(cd "$WORK" && venv/bin/pyinstaller --onefile --target-arch universal2 --name TrustAdvisorCompanion-macos \
  --codesign-identity "$IDENTITY" --osx-entitlements-file ent.plist --noconfirm --log-level ERROR ta_companion.py)
BIN="$WORK/dist/TrustAdvisorCompanion-macos"
codesign --force --options runtime --timestamp --entitlements "$WORK/ent.plist" --sign "$IDENTITY" "$BIN"
codesign --verify --strict "$BIN"
(cd "$WORK/dist" && ditto -c -k TrustAdvisorCompanion-macos TrustAdvisorCompanion-macos.zip)
xcrun notarytool submit "$WORK/dist/TrustAdvisorCompanion-macos.zip" --keychain-profile "$PROFILE" --wait
spctl --assess --type open --context context:primary-signature -v "$BIN"
"$BIN" --version
gh release upload "companion-v$VERSION" "$BIN" "$WORK/dist/TrustAdvisorCompanion-macos.zip" --clobber
echo "Published signed + notarized macOS companion $VERSION"
