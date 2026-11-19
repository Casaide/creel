#!/bin/sh
# Creel's Lua against the real thing: every program test_lua prints the result of, and 2,000 integer expressions at
# random, run in lua5.4 too. They must print the same, but for the differences we mean (below).
#   ./lua_diff.sh     LOBSTER=<path to the lobster binary> (default ~/Dev/lobster/bin/lobster); needs lua5.4
LOBSTER="${LOBSTER:-$HOME/Dev/lobster/bin/lobster}"
LUA="${LUA:-lua5.4}"
command -v "$LUA" >/dev/null || { echo "lua_diff: no $LUA here"; exit 1; }
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
(cd "$(dirname "$0")/examples/plain/src" && "$LOBSTER" test_lua.lobster -- "diff:$dir" >/dev/null 2>&1)
# What we mean to do differently: a fraction or a number past 2^60 reads as nil (integers only); pairs goes in the
# order keys were set (Lua's own order is its hash's); # of a table with a hole is a border, and Lua picks another.
meant() {
	grep -q -e "tonumber(.1\.5.)" -e "tonumber(.99999999999999999999.)" -e "in pairs(" -e "t\[4\] = .d. print(#t)" "$1"
}
n=0
bad=0
skipped=0
for f in "$dir"/*.lua; do
	want="$(awk 'NR > 1 { printf "|" } { printf "%s", $0 }' "${f%.lua}.want")"
	n=$((n + 1))
	real="$("$LUA" "$f" 2>&1 | awk 'NR > 1 { printf "|" } { printf "%s", $0 }')"
	[ "$real" = "$want" ] && continue
	if meant "$f"; then
		skipped=$((skipped + 1))
		continue
	fi
	bad=$((bad + 1))
	echo "differs: $(head -c 300 "$f")"
	echo "  here: $want"
	echo "  lua:  $real"
done
echo "lua_diff: $n programs, $bad differ ($skipped as meant)"
[ "$bad" -eq 0 ] && [ "$n" -gt 40 ]
