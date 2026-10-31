#!/bin/zsh
# Builds the release artifacts: build/BetterActivityMonitor-<version>.dmg and .zip, plus SHA256SUMS.
# The app comes from the Xcode project (scripts/build-app.sh), so the desktop widgets are included.
#   scripts/package.sh                         version from the project (scripts/version.sh)
#   VERSION=0.2.0-nightly.20261031 scripts/package.sh
# Signing: ad-hoc by default. With DEVELOPER_ID="Developer ID Application: Name (TEAMID)" the app and DMG
# are signed with the hardened runtime; with NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD
# (an app-specific password) as well, the DMG is notarized and the ticket stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(scripts/version.sh)}"
export VERSION
NAME="BetterActivityMonitor"
APP="build/xcode/Release/$NAME.app"
DMG="build/$NAME-$VERSION.dmg"
ZIP="build/$NAME-$VERSION.zip"

scripts/build-app.sh Release
codesign --verify --deep --strict "$APP"

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
