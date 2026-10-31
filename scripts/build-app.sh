#!/bin/zsh
# Builds the app with its desktop widgets from the Xcode project into build/xcode/<config>/BetterActivityMonitor.app.
#   scripts/build-app.sh [Release|Debug]
# VERSION and BUILD_NUMBER override the project's MARKETING_VERSION and the commit-count build number.
# Signing: ad-hoc by default, so it builds anywhere. With DEVELOPER_ID="Developer ID Application: Name (TEAMID)"
# the app and widgets are signed with that identity, the hardened runtime and a secure timestamp, ready to notarize.
# Ad-hoc builds run, but macOS may keep them out of the shared app group, so widget graphs may start empty.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
VERSION="${VERSION:-$(scripts/version.sh)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(scripts/version.sh build)}"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM="${${DEVELOPER_ID##*\(}%\)}"
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

xcodebuild -project BetterActivityMonitor.xcodeproj -target BetterActivityMonitor -configuration "$CONFIG" \
  SYMROOT="$PWD/build/xcode" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${SIGNING[@]}" build | grep -E "error:|warning: .*(sign|entitlement)|BUILD (SUCCEEDED|FAILED)"
[[ ${pipestatus[1]} == 0 ]] || exit 1
echo "Built build/xcode/$CONFIG/BetterActivityMonitor.app ($VERSION, build $BUILD_NUMBER)"
