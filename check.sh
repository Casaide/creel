#!/bin/sh
# Creel's own check: its modules compile with nothing from a game but the hooks in examples/plain.
#   ./check.sh        LOBSTER=<path to the lobster binary> (default ~/Dev/lobster/bin/lobster)
LOBSTER="${LOBSTER:-$HOME/Dev/lobster/bin/lobster}"
cd "$(dirname "$0")/examples/plain/src" || exit 1
bad=0
for prog in sim_only.lobster all_modules.lobster; do
	out="$("$LOBSTER" --compile-only "$prog" 2>&1 | grep 'error:')"
	if [ -n "$out" ]; then
		echo "$prog:"
		echo "$out"
		bad=1
	else
		echo "$prog: compiles"
	fi
done
exit $bad
