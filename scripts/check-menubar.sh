#!/bin/zsh
# Renders the menu bar item in every style, coloring and appearance at 0, 50 and 100 % and checks
# that it is 18 pt tall and keeps its width as values change.
#   scripts/check-menubar.sh [out-dir]
# Writes menubar-<style>-<light|dark>.png plus menubar-report.txt to out-dir; exits 1 on issues.
# The app opens no window for this and quits by itself.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/menubar}"
BIN="build/BetterActivityMonitor.app/Contents/MacOS/BetterActivityMonitor"

[[ -x "$BIN" ]] || scripts/bundle.sh >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"

BAM_MENUBAR_SNAPSHOT_DIR="$OUT" "$BIN" >/dev/null 2>&1

report="$OUT/menubar-report.txt"
[[ -f "$report" ]] || { echo "no report written (did the app crash?)"; exit 2; }
echo "images: $OUT"
cat "$report"
if grep -qv '^#' "$report"; then
  echo "MENU BAR ISSUES FOUND"; exit 1
fi
echo "OK: menu bar item keeps its size"
