#!/bin/sh
# Creel's own check: its modules compile with nothing from a game but the hooks in examples/plain, and Lua's tests pass.
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
# (and Lua for mods, headless: the language, its refusals and its limits)
out="$("$LOBSTER" test_lua.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_lua: .* 0 failed" || bad=1
exit $bad
