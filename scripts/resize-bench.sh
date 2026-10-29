#!/bin/zsh
# Measures how long each window-resize frame takes (layout + display) on every screen of the bundled app.
#   scripts/resize-bench.sh [screens] [frames]      e.g. scripts/resize-bench.sh overview,processes 150
# Prints: screen frames median_ms p95_ms max_ms over_16.7ms. 60 fps needs frames under 16.7 ms.
# APP_ARGS passes launch arguments, e.g. settings overrides to A/B a card:
#   APP_ARGS="-overview.cpu NO" scripts/resize-bench.sh overview
# APP_ENV passes environment, e.g. APP_ENV="BAM_NO_GLASS=1" to compare without Liquid Glass.
# Run it while sampling to find the cost:  scripts/resize-bench.sh overview 600 & sleep 8; scripts/hot-frames.sh 8
set -euo pipefail
cd "$(dirname "$0")/.."
SECTIONS="${1:-}"
FRAMES="${2:-150}"
BIN="build/ActivityManagerReloaded.app/Contents/MacOS/ActivityManagerReloaded"
REPORT="build/resize-bench.txt"
[[ -x "$BIN" ]] || scripts/bundle.sh >/dev/null
rm -f "$REPORT"
env ${APP_ENV:-} BAM_RESIZE_BENCH="$PWD/$REPORT" BAM_RESIZE_FRAMES="$FRAMES" ${SECTIONS:+BAM_SNAPSHOT_SECTIONS="$SECTIONS"} "$BIN" ${=APP_ARGS:-} >/dev/null 2>&1
[[ -f "$REPORT" ]] || { echo "no report written (did the app crash?)"; exit 2; }
column -t "$REPORT"
