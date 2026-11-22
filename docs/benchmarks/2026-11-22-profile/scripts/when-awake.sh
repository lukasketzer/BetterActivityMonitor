#!/bin/zsh
# Waits until the screen is unlocked and the displays are awake, then measures the final build with its window visible.
awake() {
  [[ "$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null)" != "true" ]] &&
  ! swift /tmp/bamprof/scripts/disp.swift | grep -q "asleep: true"
}
until awake; do sleep 20; done
sleep 30
awake || exit 3
M=/tmp/bamprof/scripts/measure.sh; A=/tmp/bamprof/apps/after.app
$M final-overview $A 30 --env BAM_START_SECTION=overview; sleep 2
$M final-overview-nomenubar $A 30 --env BAM_START_SECTION=overview --args -showMenuBarExtra NO; sleep 2
$M final-overview-2 $A 30 --env BAM_START_SECTION=overview; sleep 2
$M final-processes $A 30 --env BAM_START_SECTION=processes; sleep 2
$M final-menubar $A 30 --env BAM_START_SECTION=overview --args --hidden; sleep 2
TRACE=15 $M final-overview-tp $A 5 --env BAM_START_SECTION=overview; sleep 2
TRACE=15 $M final-menubar-tp $A 5 --env BAM_START_SECTION=overview --args --hidden
swift /tmp/bamprof/scripts/disp.swift
