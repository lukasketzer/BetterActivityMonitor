#!/bin/zsh
# Measures the CPU the bundled app uses on each screen with its window frontmost.
#   scripts/measure-screens.sh [seconds] [screen ...]      e.g. scripts/measure-screens.sh 30 overview processes
# Extra environment for the app can be passed via APP_ENV, e.g. APP_ENV="BAM_PLAIN_SIDEBAR=1".
# Screens: overview processes cpu memory disks network sensors energy; network pages as network:<page>
# (network:connections, network:listening, network:log). Only the app's own CPU is counted: the short-lived
# nettop runs behind the connection pages are measured by `swift run -c release sysbench nettop`.
set -euo pipefail
cd "$(dirname "$0")/.."

SECONDS_PER_SCREEN="${1:-30}"
shift || true
SCREENS=("${@:-overview processes cpu memory energy}")
[[ $# -eq 0 ]] && SCREENS=(overview processes cpu memory energy)
APP="build/BetterActivityMonitor.app"
WARMUP=12

[[ -d "$APP" ]] || scripts/bundle.sh >/dev/null

env_args=()
for kv in ${=APP_ENV:-}; do env_args+=(--env "$kv"); done

printf "%-20s %10s\n" "screen" "cpu %"
for screen in $SCREENS; do
  pkill -f "MacOS/BetterActivityMonitor" 2>/dev/null || true
  sleep 1
  section=${screen%%:*}
  page_args=()
  [[ "$screen" == *:* ]] && page_args=(--env "BAM_NETWORK_PAGE=${screen#*:}")
  open -n --env "BAM_START_SECTION=$section" "${page_args[@]}" "${env_args[@]}" "$APP"
  sleep $WARMUP
  pid=$(pgrep -f "MacOS/BetterActivityMonitor")
  t0=$(scripts/cputime.sh "$pid")
  sleep "$SECONDS_PER_SCREEN"
  t1=$(scripts/cputime.sh "$pid")
  printf "%-20s %10.1f\n" "$screen" $(( (t1 - t0) * 100.0 / SECONDS_PER_SCREEN ))
done
pkill -f "MacOS/BetterActivityMonitor" 2>/dev/null || true
