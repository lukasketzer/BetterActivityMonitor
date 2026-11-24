#!/bin/zsh
# usage: bench.sh <label> <seconds> <pgrep -f pattern for the tool under test>
# Prints per-process CPU% (cputime delta / wall), RSS, and top's idle wakeups/s over the window.
label=$1; secs=$2; pat=$3
snap() { ps -axo pid=,cputime=,rss=,command= | awk -v pats="$1" '
  BEGIN{n=split(pats,P,"|")}
  { cmd=$0; if (index(cmd,"awk -v pats")||index(cmd,"bench.sh")) next; for(i=1;i<=n;i++) if ((P[i] ~ /^pid:/) ? ($1==substr(P[i],5)) : index(cmd,P[i])) {
      t=$2; m=split(t,a,":"); s=(m==2)? a[1]*60+a[2] : a[1]*3600+a[2]*60+a[3];
      printf "%s %.2f %d %s\n",$1,s,$3,P[i]; break } }'; }
PATS="MacOS/BetterActivityMonitor|BAMWidgets.appex|chronod|pid:$pat"
snap "$PATS" > before.$label
# wakeups/power from top for the BAM app + tool pid (average across window)
for p in $(pgrep -f "MacOS/BetterActivityMonitor" | head -1) $(pgrep -f "BAMWidgets.appex" | head -1); do
  top -l 2 -s $secs -pid $p -stats pid,command,cpu,idlew,power,mem 2>/dev/null | tail -2 | head -1 >> top.$label &
done
sleep $secs
snap "$PATS" > after.$label
wait
echo "=== $label (${secs}s) ==="
join <(sort before.$label) <(sort after.$label) | awk -v s=$secs '{printf "%-8s %-30s cpu=%6.2f%%  rss=%6.1f MB\n",$1,$4,($5-$2)/s*100,$6/1024}' | sed 's/ $//'
cat top.$label 2>/dev/null
