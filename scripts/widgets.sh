#!/bin/zsh
# Builds the app with its desktop widgets (Xcode project) into build/xcode and opens it, so the widget
# gallery shows the latest widgets. Every build gets a fresh build number: macOS caches an app's widget list
# per version, and an old widget process still running would answer with the old list.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
APP="$PWD/build/xcode/$CONFIG/BetterActivityMonitor.app"

xcodebuild -project BetterActivityMonitor.xcodeproj -target BetterActivityMonitor -configuration "$CONFIG" \
  SYMROOT="$PWD/build/xcode" CURRENT_PROJECT_VERSION="$(date +%s)" build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

pkill -x BetterActivityMonitor || true
pkill -x BAMWidgets || true
# `open` fails while the old copy is still quitting.
while pgrep -x BetterActivityMonitor >/dev/null; do sleep 0.2; done
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"
echo "Built $APP"
