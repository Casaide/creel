#!/bin/sh
# Creel's own check: its modules compile with nothing from a game but the hooks in examples/plain, edge scrolling's, Lua's, the invariants', the draw probe's, the delivery market's, the .vox meshes' and the MCP's tests pass
# (and agree with lua5.4, if it's installed: lua_diff.sh).
#   ./check.sh        LOBSTER=<path to the lobster binary> (default ~/Dev/lobster/bin/lobster)
LOBSTER="${LOBSTER:-$HOME/Dev/lobster/bin/lobster}"
cd "$(dirname "$0")/examples/plain/src" || exit 1
bad=0
for prog in sim_only.lobster all_modules.lobster mcp_server.lobster; do
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
# (and the per-tick invariants, headless: each one catches a break planted for it)
out="$("$LOBSTER" test_invariants.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_invariants: .* 0 failed" || bad=1
# (and the draw probe, headless: a site's stage from the sim, the probe's JSON)
out="$("$LOBSTER" test_draw_probe.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_draw_probe: .* 0 failed" || bad=1
# (and the delivery market, headless: which deliveries go first as the rules say)
out="$("$LOBSTER" test_market.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_market: .* 0 failed" || bad=1
# (and a site's phases, headless: levelled, waiting for goods, going up)
out="$("$LOBSTER" test_site_phase.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_site_phase: .* 0 failed" || bad=1
# (and a .vox model as kit meshes, headless: only the faces that show, standing on the ground, a mesh a palette index)
out="$("$LOBSTER" test_vox_mesh.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_vox_mesh: .* 0 failed" || bad=1
# (and a site's stages as data, headless: each stage's goods asked for once it's reached)
out="$("$LOBSTER" test_build_stages.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_build_stages: .* 0 failed" || bad=1
# (and edge scrolling, headless)
out="$("$LOBSTER" test_edge_scroll.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_edge_scroll: .* 0 failed" || bad=1
# (and a pack's own events as rings and floating text, headless: what event_fx makes of each)
out="$("$LOBSTER" test_pack_fx.lobster 2>&1)"
echo "$out" | grep -v warning | tail -1
echo "$out" | grep -q "test_pack_fx: .* 0 failed" || bad=1
# (and the MCP, driven as an agent would, where there's a Node: mcp/test/test.js)
if command -v node >/dev/null; then
	out="$(LOBSTER="$LOBSTER" node ../../../mcp/test/test.js 2>&1)"
	echo "$out" | grep -v warning | tail -1
	echo "$out" | grep -q "test_mcp: .* 0 failed" || bad=1
fi
# (and against real Lua, where there is one)
if command -v lua5.4 >/dev/null; then
	LOBSTER="$LOBSTER" ../../../lua_diff.sh | tail -1 || bad=1
fi
exit $bad
