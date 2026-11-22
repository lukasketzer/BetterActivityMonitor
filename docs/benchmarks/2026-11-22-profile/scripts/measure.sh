#!/bin/zsh
# usage: measure.sh <label> <app> <seconds> [open-args...]   launches a new instance, warms up, measures CPU/footprint, records Time Profiler
set -euo pipefail
label=$1; app=$2; secs=$3; shift 3
out=/tmp/bamprof/runs/$label; mkdir -p $out
before=$(pgrep -f "$app/Contents/MacOS/BetterActivityMonitor" || true)
[[ -n "$before" ]] && { echo "already running: $before"; exit 1; }
open -n -a "$app" "$@"
sleep 12
pid=$(pgrep -f "$app/Contents/MacOS/BetterActivityMonitor")
echo $pid > $out/pid
t0=$(/Users/lukas/Workspace/BetterActivityMonitor-Project/BetterActivityMonitor/scripts/cputime.sh $pid)
sleep $secs
t1=$(/Users/lukas/Workspace/BetterActivityMonitor-Project/BetterActivityMonitor/scripts/cputime.sh $pid)
cpu=$(( (t1-t0)*100.0/secs ))
footprint $pid > $out/footprint.txt 2>/dev/null; fp=$(footprint $pid 2>/dev/null | grep -o 'Footprint: [0-9.]* [KMG]B' | head -1 | cut -d' ' -f2-)
top -l 2 -s 5 -pid $pid -stats pid,cpu,idlew,power 2>/dev/null | tail -1 > $out/top.txt
vis=$(/tmp/bamprof/scripts/visible $pid); vis=${vis:+yes}
printf "%-28s cpu=%6.1f%%  footprint=%s  top=[%s] window=%s\n" $label $cpu "$fp" "$(cat $out/top.txt)" "${vis:-hidden}" | tee $out/summary.txt
if [[ -n "${TRACE:-}" ]]; then
  xctrace record --template 'Time Profiler' --attach $pid --time-limit ${TRACE}s --output $out/tp.trace --no-prompt >/dev/null 2>&1
  xctrace export --input $out/tp.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > $out/tp.xml
  python3 -I /tmp/bamprof/scripts/tp2json.py $out/tp.xml $out/tp.json "$label" | head -4
  rm -f $out/tp.xml
fi
[[ -n "${KEEP:-}" ]] || kill $pid
