#!/bin/zsh
M=/tmp/bamprof/scripts/measure.sh
for i in 1 2 3; do
  for b in $( (( i % 2 )) && echo "base after" || echo "after base" ); do
    $M rep-$b-menubar-$i /tmp/bamprof/apps/$b.app 20 --env BAM_START_SECTION=overview --args --hidden; sleep 2
  done
done
