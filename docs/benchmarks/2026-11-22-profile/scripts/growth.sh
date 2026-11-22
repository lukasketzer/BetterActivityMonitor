#!/bin/zsh
# usage: growth.sh <label> <app> <minutes> [open args]  -> logs elapsed_s cpu_s footprint_MB every 15 s
label=$1; app=$2; mins=$3; shift 3
out=/tmp/bamprof/runs/$label; mkdir -p $out
open -n -a "$app" "$@"; sleep 5
pid=$(pgrep -f "$app/Contents/MacOS/BetterActivityMonitor"); echo $pid > $out/pid
: > $out/growth.tsv
for i in $(seq 0 $((mins*4))); do
  fp=$(footprint $pid 2>/dev/null | grep -o 'Footprint: [0-9.]* [KMG]B' | head -1 | awk '{v=$2; if($3=="GB")v*=1024; if($3=="KB")v/=1024; print v}')
  cpu=$(/Users/lukas/Workspace/BetterActivityMonitor-Project/BetterActivityMonitor/scripts/cputime.sh $pid)
  echo "$((i*15))\t$cpu\t$fp" >> $out/growth.tsv
  sleep 15
done
heap -s $pid > $out/heap-end.txt 2>&1; vmmap --summary $pid > $out/vmmap-end.txt 2>&1
kill $pid
