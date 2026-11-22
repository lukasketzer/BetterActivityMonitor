#!/bin/zsh
# usage: suite.sh <build: base|after>
b=$1; APP=/tmp/bamprof/apps/$b.app; M=/tmp/bamprof/scripts/measure.sh
for s in overview processes cpu memory disks network gpu energy system; do
  $M $b-$s $APP 30 --env BAM_START_SECTION=$s; sleep 2
done
$M $b-menubar $APP 30 --env BAM_START_SECTION=overview --args --hidden; sleep 2
$M $b-overview-100ms $APP 30 --env BAM_START_SECTION=overview --args -refreshInterval 0.1; sleep 2
TRACE=15 $M $b-overview-tp $APP 5 --env BAM_START_SECTION=overview; sleep 2
TRACE=15 $M $b-processes-tp $APP 5 --env BAM_START_SECTION=processes; sleep 2
TRACE=15 $M $b-menubar-tp $APP 5 --env BAM_START_SECTION=overview --args --hidden; sleep 2
TRACE=15 $M $b-overview-100ms-tp $APP 5 --env BAM_START_SECTION=overview --args -refreshInterval 0.1; sleep 2
