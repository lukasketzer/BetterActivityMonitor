#!/bin/zsh
# Prints the total CPU seconds (user + system) a process has used, as a decimal number.
ps -o cputime= -p "$1" | awk -F'[:.]' '{ if (NF == 4) print $1*3600 + $2*60 + $3 + $4/100; else print $1*60 + $2 + $3/100 }'
