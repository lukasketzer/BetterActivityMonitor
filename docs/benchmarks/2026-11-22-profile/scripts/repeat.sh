#!/bin/zsh
# Interleaved before/after runs to control for drifting system conditions. 3 pairs per scenario, alternating order.
M=/tmp/bamprof/scripts/measure.sh
run() { # build scenario i
  local b=$1 s=$2 i=$3 APP=/tmp/bamprof/apps/$1.app
  case $s in
    menubar) $M rep-$b-$s-$i $APP 20 --env BAM_START_SECTION=overview --args --hidden ;;
    *) $M rep-$b-$s-$i $APP 20 --env BAM_START_SECTION=$s ;;
  esac
  sleep 2
}
for s in overview menubar processes cpu; do
  for i in 1 2 3; do
    if (( i % 2 )); then run base $s $i; run after $s $i; else run after $s $i; run base $s $i; fi
  done
done
