#!/bin/zsh
# Builds the release artifacts: build/BetterActivityMonitor-<version>.dmg and .zip, plus SHA256SUMS.
#   VERSION=0.1.0 scripts/package.sh
# Signing: ad-hoc by default. With DEVELOPER_ID="Developer ID Application: Name (TEAMID)" the app and DMG
# are signed with the hardened runtime; with NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD
# (an app-specific password) as well, the DMG is notarized and the ticket stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}"
export VERSION
NAME="BetterActivityMonitor"
APP="build/$NAME.app"
DMG="build/$NAME-$VERSION.dmg"
ZIP="build/$NAME-$VERSION.zip"

scripts/bundle.sh release

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "Signing with $DEVELOPER_ID"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --strict "$APP"

rm -f "$DMG" "$ZIP" build/SHA256SUMS
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "Notarizing $DMG"
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
  fi
fi

# The zip is made after stapling so the app inside carries the notarization ticket.
ditto -c -k --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "${DMG:t}" "${ZIP:t}" > SHA256SUMS)
echo "Packaged $DMG and $ZIP"
cat build/SHA256SUMS
