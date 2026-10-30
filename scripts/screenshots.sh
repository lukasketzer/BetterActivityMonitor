#!/bin/zsh
# Captures README screenshots of the bundled app: one window shot per screen, with the real Liquid
# Glass and window shadow (screencapture), unlike the BAM_SNAPSHOT_DIR renders of check-layout.sh.
#   scripts/screenshots.sh [out-dir] [sections]
#   e.g. scripts/screenshots.sh docs/screenshots "overview,cpu"
# Needs Screen Recording permission for the terminal. Each screen launches its own app instance with
# its window pinned to SIZE (default 1280x820, overriding the saved/tiled frame) and kills only that
# instance afterwards. Graphs keep 120 samples, so the default SETTLE of 90 s fills most of each chart.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/screenshots}"
SECTIONS=(${(s:,:)${2:-overview,processes,cpu,memory,network,disks,sensors,battery}})
BIN="build/BetterActivityMonitor.app/Contents/MacOS/BetterActivityMonitor"
SETTLE="${SETTLE:-90}"  # seconds each screen runs before the capture
SIZE="${SIZE:-1280x820}"
WIDTH="${WIDTH:-1600}"  # output width in pixels; Retina captures are 2x the window size
# Argument-domain default: read instead of the saved frame, never written back to the app's prefs.
FRAME="200 200 ${SIZE/x/ } 0 0 2560 1440"

[[ -x "$BIN" ]] || scripts/bundle.sh >/dev/null
mkdir -p "$OUT"

window_id() {  # id of the largest on-screen window owned by pid $1
  swift - "$1" <<'EOF' 2>/dev/null
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let largest = mine.max { a, b in
    let w = { (d: [String: Any]) -> Double in let r = d[kCGWindowBounds as String] as? [String: Double] ?? [:]; return (r["Width"] ?? 0) * (r["Height"] ?? 0) }
    return w(a) < w(b)
}
if let id = largest?[kCGWindowNumber as String] as? Int { print(id) }
EOF
}

for section in $SECTIONS; do
  env ${APP_ENV:-} BAM_START_SECTION="$section" "$BIN" -ApplePersistenceIgnoreState YES -"NSWindow Frame main" "$FRAME" >/dev/null 2>&1 &
  pid=$!
  sleep "$SETTLE"
  id="$(window_id $pid)"
  if [[ -z "$id" ]]; then
    echo "$section: no window found"; kill $pid 2>/dev/null || true; continue
  fi
  screencapture -x -l"$id" "$OUT/$section.png"
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
  sips --resampleWidth "$WIDTH" "$OUT/$section.png" >/dev/null
  echo "$OUT/$section.png"
done
