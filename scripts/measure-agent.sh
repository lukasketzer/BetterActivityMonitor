#!/bin/zsh
# Runs the background history agent in the foreground against a throwaway database and reports its CPU
# and what it wrote. Never touches the real history or a registered agent.
#   scripts/measure-agent.sh [seconds]      (default 180: three finished minutes)
set -euo pipefail
cd "$(dirname "$0")/.."

SECONDS_TO_RUN="${1:-180}"
swift build -c release --product BAMHistoryAgent >/dev/null
BIN="$(swift build -c release --show-bin-path)/BAMHistoryAgent"
DIR="$(mktemp -d -t bam-agent)"
DB="$DIR/history.sqlite"

BAM_HISTORY_DB="$DB" "$BIN" &
pid=$!
trap 'kill $pid 2>/dev/null || true; rm -rf "$DIR"' EXIT
sleep "$SECONDS_TO_RUN"
cpu=$(ps -o cputime= -p $pid | tr -d ' ')
rss=$(ps -o rss= -p $pid | tr -d ' ')
kill $pid; wait $pid 2>/dev/null || true

seconds=$(echo "$cpu" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }')
printf "ran %ss  cpu %ss  = %.3f%% of one core  rss %d MB\n" "$SECONDS_TO_RUN" "$seconds" \
  "$(echo "$seconds / $SECONDS_TO_RUN * 100" | bc -l)" "$((rss / 1024))"
echo "minutes written: $(sqlite3 "$DB" 'SELECT COUNT(*) FROM system')"
echo "process rows:    $(sqlite3 "$DB" 'SELECT COUNT(*) FROM process')  (with network: $(sqlite3 "$DB" 'SELECT COUNT(*) FROM process WHERE net IS NOT NULL'))"
sqlite3 -header -column "$DB" "SELECT datetime(ts,'unixepoch','localtime') AS minute, round(cpu*100,1) AS cpu_pct, round(mem_used*100,1) AS mem_pct, round(power,2) AS watts FROM system ORDER BY ts"
