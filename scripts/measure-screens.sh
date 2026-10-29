#!/bin/zsh
# Measures the CPU the bundled app uses on each screen with its window frontmost.
#   scripts/measure-screens.sh [seconds] [screen ...]      e.g. scripts/measure-screens.sh 30 overview processes
# Extra environment for the app can be passed via APP_ENV, e.g. APP_ENV="BAM_PLAIN_SIDEBAR=1".
# Screens: overview processes cpu memory disks network sensors battery
set -euo pipefail
cd "$(dirname "$0")/.."

SECONDS_PER_SCREEN="${1:-30}"
shift || true
SCREENS=("${@:-overview processes cpu memory battery}")
[[ $# -eq 0 ]] && SCREENS=(overview processes cpu memory battery)
APP="build/ActivityManagerReloaded.app"
WARMUP=12

[[ -d "$APP" ]] || scripts/bundle.sh >/dev/null

env_args=()
for kv in ${=APP_ENV:-}; do env_args+=(--env "$kv"); done

printf "%-12s %10s\n" "screen" "cpu %"
for screen in $SCREENS; do
  pkill -f "MacOS/ActivityManagerReloaded" 2>/dev/null || true
  sleep 1
  open -n --env "BAM_START_SECTION=$screen" "${env_args[@]}" "$APP"
  sleep $WARMUP
  pid=$(pgrep -f "MacOS/ActivityManagerReloaded")
  t0=$(scripts/cputime.sh "$pid")
  sleep "$SECONDS_PER_SCREEN"
  t1=$(scripts/cputime.sh "$pid")
  printf "%-12s %10.1f\n" "$screen" $(( (t1 - t0) * 100.0 / SECONDS_PER_SCREEN ))
done
pkill -f "MacOS/ActivityManagerReloaded" 2>/dev/null || true
