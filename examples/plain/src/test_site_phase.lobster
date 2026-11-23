// A site's phases (#192): a cell job such as a road digs its own share of its build with no goods, waits for them,
// then is laid; a field with no goods goes straight on. Headless, by hand. ../../../check.sh runs it.
//   lobster test_site_phase.lobster
import sim_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// Goods: stone. Types: a road cell (1 stone, half of it dug first), a field (no goods), a house (2 stone, the rules'
// foundation). Each 100 build ticks.
resource_names = [ "stone" ]
num_resources = 1
r_foundation_pct = 20
bt_name = [ "road", "field", "house" ]
bt_build_ticks = [ 100, 100, 100 ]
bt_foundation = [ 50, 30, -1 ]
b_id = [ 1, 2, 3 ]
b_kind = [ 0, 1, 2 ]
b_done = [ 0, 0, 0 ]
b_progress = [ 0, 0, 0 ]
b_hold = [ [ 0 ], [ 0 ], [ 0 ] ]
b_site = [ [ 1 ], []::int, [ 2 ] ]

def phases() -> string: return concat_string(map(3) b: [ "level", "wait", "build", "done" ][site_phase(b)], " ")

check(phases() == "level level level", "all three are levelled first: {phases()}")
check(foundation_of(0) == 50 and foundation_of(2) == 20, "a type\'s own foundation share, else the rules\' ({foundation_of(0)}, {foundation_of(2)})")
for(3) b: b_progress[b] = 25
check(phases() == "level level wait", "a quarter in: the road (half) and the field (30%) are still being levelled, the house with no stone waits past its foundation: {phases()}")
check(build_cap(2) == 20, "the house with no stone goes no further than its foundation ({build_cap(2)})")
for(3) b: b_progress[b] = build_cap(b)
check(phases() == "wait build wait", "dug out, the road waits for its stone; the field goes on; the house waits: {phases()}")
check(build_cap(0) == 50 and build_cap(1) == 100, "the road dug to half, the field all the way ({build_cap(0)}, {build_cap(1)})")
b_hold[0][0] = 1
check(site_phase(0) == SP_BUILD and build_cap(0) == 100, "its stone in, the road is laid ({build_cap(0)})")
b_hold[2][0] = 1
check(site_phase(2) == SP_BUILD and build_cap(2) == 60, "a house with half its stone goes up half way past its foundation ({build_cap(2)})")
b_progress[2] = 60
check(site_phase(2) == SP_WAIT, "and waits there for the rest")
b_done[1] = 1
check(site_phase(1) == SP_DONE, "a finished field stands")
// The same from a pack's Lua.
l_api_names = LA_NAMES
lua_reset()
lua_api_consts()
lua_rules = su_rules
lua_quiet = true
check(lua_load_pack("t", [ "t.lua" ], [ "function phase_of(b) return site_phase(b) end" ], L_BUDGET_LOAD) == "", "the pack loads")
lua_freeze()
lua_on = true
def phase_of(b:int) -> int:
    var got = -1
    lua_each("phase_of", [ lv_int(b) ]) rs:
        if rs.length and lv_is_int(rs[0]): got = rs[0] >> 3
    return got
check(phase_of(0) == SP_BUILD and phase_of(2) == SP_WAIT, "Lua\'s site_phase reads the same ({phase_of(0)}, {phase_of(2)})")
print "test_site_phase: {passes} passed, {fails} failed"
