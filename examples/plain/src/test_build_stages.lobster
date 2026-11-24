// A site's stages as data (#193): levelled, then built from wood, then from stone, each stage's goods asked for only
// once it's reached, and never built past what was brought. Headless, by hand. ../../../check.sh runs it.
//   lobster test_build_stages.lobster
import sim_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// Goods: wood, stone. Types: a store, a hall built in three stages (100 build ticks; costs 4 wood, 2 stone).
resource_names = [ "wood", "stone" ]
num_resources = 2
bt_name = [ "store", "hall" ]
bt_build_ticks = [ 100, 100 ]
bt_store = [ 1, 0 ]
bt_hold = [ [ 50, 50 ], [ 0, 0 ] ]
bt_out = [ [ 0, 0 ], [ 0, 0 ] ]
bt_offer = [ [ 0, 0 ], [ 0, 0 ] ]
bt_foundation = [ -1, -1 ]
let hall = parse_json("\{\"stages\": [\{\"pct\": 20\}, \{\"pct\": 40, \"goods\": [\"wood\"]\}, \{\"pct\": 40, \"goods\": [\"stone\"]\}]\}")
bt_stages = [ []::int, stages_of(hall) ]
check(equal(bt_stages[1], [ 20, 0, 0, 40, 1, 0, 40, 0, 1 ]), "the stages from data: {bt_stages[1]}")
b_id = [ 1, 2 ]
b_kind = [ 0, 1 ]
b_owner = [ 0, 0 ]
b_done = [ 1, 0 ]
b_progress = [ 0, 0 ]
b_cx = [ 0, 4 ]
b_cy = [ 0, 0 ]
b_sx = [ 2, 2 ]
b_sy = [ 2, 2 ]
b_hold = [ [ 20, 10 ], [ 0, 0 ] ]
b_resv = [ [ 0, 0 ], [ 0, 0 ] ]
b_want = [ [ 0, 0 ], [ 4, 2 ] ]
b_coming = [ [ 0, 0 ], [ 0, 0 ] ]
b_site = [ []::int, [ 4, 2 ] ]
tick = 0

def asks() -> string: return concat_string(map(filter(market_plan(0, parse_json("\{\}"))) d: d.kind == DL_WANT) d: resource_names[d.r], " ")

check(levelling(1) and site_phase(1) == SP_LEVEL and build_stage(1) == 0, "a new hall is levelled first (stage {build_stage(1)})")
check(asks() == "" and not site_asks(1, 0) and not site_asks(1, 1), "and asks for nothing yet: \"{asks()}\"")
check(build_cap(1) == 20, "it\'s levelled with no goods, no further ({build_cap(1)})")
b_progress[1] = 20
check(build_stage(1) == 1 and asks() == "wood", "levelled, it asks for its wood, not yet its stone: \"{asks()}\"")
check(site_phase(1) == SP_WAIT, "and waits for it")
b_hold[1][0] = 2  // (as a delivery does: in its hold, no longer wanted)
b_want[1][0] = 2
check(build_cap(1) == 40, "half its wood in, it goes up half its wood stage ({build_cap(1)})")
b_hold[1][0] = 4
b_want[1][0] = 0
b_progress[1] = 59
check(build_stage(1) == 1 and not site_asks(1, 1), "its wood all in but its wood stage not yet built, no stone is asked for")
b_progress[1] = 60
check(build_stage(1) == 2 and asks() == "stone" and build_cap(1) == 60, "built through its wood, it asks for its stone ({build_cap(1)}): \"{asks()}\"")
// With rules stages_ahead 1: the next stage's goods come with this one's, still used in order.
r_stages_ahead = 1
b_progress[1] = 20
b_hold[1] = [ 0, 0 ]
b_want[1] = [ 4, 2 ]
check(asks() == "wood stone" and build_cap(1) == 20, "with stages_ahead, its stone is asked for with its wood, but not used first ({build_cap(1)}): \"{asks()}\"")
b_progress[1] = 0
check(asks() == "", "and still nothing while it\'s levelled: \"{asks()}\"")
b_hold[1][1] = 2
b_want[1][1] = 0
check(build_cap(1) == 20, "its stone in before its wood, it waits for the wood ({build_cap(1)})")
r_stages_ahead = 0
b_hold[1] = [ 4, 0 ]
b_want[1] = [ 0, 2 ]
b_progress[1] = 60
// Brought a stone at a time, built as fast as it can: never past what was brought.
var over = 0
for(2) k:
    b_hold[1][1]++
    b_want[1][1]--
    for(30) j:
        b_progress[1] = min(build_cap(1), b_progress[1] + 3)
        if b_progress[1] > 60 + 40 * b_hold[1][1] / 2: over++
check(over == 0 and b_progress[1] == 100, "built up as each stone comes, never past what was brought ({b_progress[1]}, {over} ticks over)")
// A type without stages: as before.
bt_stages[1] = []
b_progress[1] = 0
b_hold[1] = [ 0, 0 ]
b_want[1] = [ 4, 2 ]
check(not staged(1) and site_asks(1, 0) and site_asks(1, 1) and build_stage(1) == 0, "a type without stages asks for all its goods at once, as before")
// From a pack's Lua.
bt_stages[1] = stages_of(hall)
b_progress[1] = 60
l_api_names = LA_NAMES
lua_reset()
lua_api_consts()
lua_rules = su_rules
lua_quiet = true
check(lua_load_pack("t", [ "t.lua" ], [ "function stage_of(b) return build_stage(b) end" ], L_BUDGET_LOAD) == "", "the pack loads")
lua_freeze()
lua_on = true
var got = -1
lua_each("stage_of", [ lv_int(1) ]) rs:
    if rs.length and lv_is_int(rs[0]): got = rs[0] >> 3
check(got == 2, "Lua\'s build_stage reads the same ({got})")
print "test_build_stages: {passes} passed, {fails} failed"
