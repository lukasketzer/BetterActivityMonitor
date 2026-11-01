#!/bin/zsh
# Renders every screen of the bundled app at several window sizes and audits the layout
# (cards overlapping, content spilling out of its card, cards cut off horizontally).
#   scripts/check-layout.sh [out-dir] [sizes] [sections]
#   e.g. scripts/check-layout.sh build/layout "900x560,1280x820" "overview,sensors"
# APP_ENV="BAM_SNAPSHOT_SIDEBAR_CYCLE=1" (several space-separated VAR=value allowed) collapses and re-expands the sidebar first; APP_ARGS passes launch args.
# Writes <section>-<w>x<h>.png plus layout-report.txt to out-dir; exits 1 if the audit found issues.
# The app opens a window for a while (about 2.5 s per screen and size) and quits by itself.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/layout}"
SIZES="${2:-900x560,1100x700,1400x900}"
SECTIONS="${3:-}"
BIN="build/BetterActivityMonitor.app/Contents/MacOS/BetterActivityMonitor"

[[ -x "$BIN" ]] || scripts/bundle.sh >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"

env ${=APP_ENV:-} BAM_SNAPSHOT_DIR="$OUT" BAM_SNAPSHOT_SIZES="$SIZES" ${SECTIONS:+BAM_SNAPSHOT_SECTIONS="$SECTIONS"} "$BIN" ${=APP_ARGS:-} >/dev/null 2>&1

report="$OUT/layout-report.txt"
[[ -f "$report" ]] || { echo "no report written (did the app crash?)"; exit 2; }
echo "screenshots: $OUT"
cat "$report"
if grep -qv '^#' "$report"; then
  echo "LAYOUT ISSUES FOUND"; exit 1
fi
echo "OK: no layout issues"
