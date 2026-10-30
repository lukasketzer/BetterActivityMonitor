#!/bin/zsh
# Samples the running app with `sample` and prints the heaviest frames (inclusive sample counts),
# filtered to the app and UI frameworks. Usage: [PID=n] [TOP=n] scripts/hot-frames.sh [seconds] [filter-regex]
set -euo pipefail
SECONDS_TO_SAMPLE="${1:-8}"
FILTER="${2:-BetterActivityMonitor\)|AppKit\)|SwiftUI\)|SwiftUICore\)|QuartzCore\)|AttributeGraph\)|IOKit\)}"
pid="${PID:-$(pgrep -nf "MacOS/BetterActivityMonitor")}"  # newest instance unless PID is given
out="$(mktemp -t bam-sample).txt"
sample "$pid" "$SECONDS_TO_SAMPLE" -file "$out" >/dev/null 2>&1
echo "full report: $out"
grep -E "$FILTER" "$out" \
  | sed -E 's/^[ +!:|]*([0-9]+) (.{0,120}).*/\1 \2/' | sed -E 's/ \+ [0-9]+.*//' \
  | awk '{c=$1; $1=""; if (c>a[$0]) a[$0]=c} END {for (k in a) print a[k], k}' \
  | sort -rn \
  | grep -vE "runApp|App.main|NSApplication|_DPS|main \(in|NSEventThread|nextEvent" \
  | head -${TOP:-40}
