#!/bin/zsh
# When the screen is unlocked and the displays awake: check the shape-drawn charts (memory, CPU, screenshots).
awake() {
  [[ "$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null)" != "true" ]] &&
  ! swift /tmp/bamprof/scripts/disp.swift | grep -q "asleep: true"
}
until awake; do sleep 20; done
sleep 20
S=/tmp/bamprof/scripts
shot() { # label app section
  local out=/tmp/bamprof/runs/$1; mkdir -p $out
  open -n -a $2 --env BAM_START_SECTION=$3; sleep 14
  local pid=$(pgrep -f "$2/Contents/MacOS/BetterActivityMonitor")
  local wid=$($S/visible $pid)
  echo "visible=${wid:-no}" > $out/visible.txt
  [[ -n "$wid" ]] && screencapture -x -o -l $wid $out/window.png
  footprint $pid > $out/footprint.txt 2>/dev/null
  echo "$1 visible=${wid:-no} $(grep -o 'Footprint: [0-9.]* [KMG]B' $out/footprint.txt | head -1) gpu=$(grep 'unmapped) (graphics)' $out/footprint.txt | awk '{print $1,$2}')"
  kill $pid; sleep 2
}
for sec in overview memory network cpu; do shot shapes-$sec /tmp/bamprof/apps/exp.app $sec; done
shot canvas-overview /tmp/bamprof/apps/after.app overview
for i in 1 2; do
  $S/measure.sh cmp-canvas-overview-$i /tmp/bamprof/apps/after.app 20 --env BAM_START_SECTION=overview; sleep 2
  $S/measure.sh cmp-shapes-overview-$i /tmp/bamprof/apps/exp.app 20 --env BAM_START_SECTION=overview; sleep 2
done
