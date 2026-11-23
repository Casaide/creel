// The delivery market (#191): which deliveries go first, as a pack's rules say, headless. ../../../check.sh runs it.
//   lobster test_market.lobster
import sim_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// Goods: stone, gold. Types: a store, a school (trains, wants gold), a hut site (wants stone), a mint (makes gold).
resource_names = [ "stone", "gold" ]
num_resources = 2
bt_name = [ "store", "school", "hut", "mint" ]
bt_store = [ 1, 0, 0, 0 ]
bt_hold = [ [ 50, 50 ], [ 0, 5 ], [ 3, 0 ], [ 0, 5 ] ]
bt_out = [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 1 ] ]
bt_offer = [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 1 ] ]
b_id = [ 1, 2, 3, 4 ]
b_kind = [ 0, 1, 2, 3 ]
b_owner = [ 0, 0, 0, 0 ]
b_done = [ 1, 1, 0, 1 ]
b_cx = [ 0, 4, 8, 12 ]
b_cy = [ 0, 0, 0, 0 ]
b_sx = [ 2, 2, 2, 2 ]
b_sy = [ 2, 2, 2, 2 ]
b_hold = [ [ 20, 10 ], [ 0, 0 ], [ 1, 0 ], [ 0, 5 ] ]  // (the mint full: it stands idle)
b_resv = [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 0 ] ]
b_want = [ [ 0, 0 ], [ 0, 3 ], [ 2, 0 ], [ 0, 0 ] ]
b_coming = [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 0 ] ]
b_site = [ []::int, []::int, [ 3, 0 ], []::int ]
tick = 0

def plan(rules:string) -> string:
    let dl = parse_json(rules)
    return concat_string(map(market_plan(0, dl)) d: "{[ "want", "full", "store" ][d.kind]}:{bt_name[b_kind[d.b]]}:{resource_names[d.r]}", " ")

// Gold to the school first, then the rest.
let gold_first = plan("\{\"levels\": [\{\"to\": [\"school\"], \"goods\": [\"gold\"], \"level\": 5\}]\}")
check(gold_first == "want:school:gold full:mint:gold want:hut:stone", "gold to the school first, even before a full workshop: {gold_first}")
// Sites first, above a full workshop too.
let sites_first = plan("\{\"levels\": [\{\"site\": true, \"level\": 5\}], \"full_out\": 1\}")
check(sites_first == "want:hut:stone full:mint:gold want:school:gold", "sites first: {sites_first}")
// The same rules, the same order.
check(plan("\{\"levels\": [\{\"site\": true, \"level\": 5\}], \"full_out\": 1\}") == sites_first, "the same rules give the same order")
// Nothing set: full out slots, then wants in building order, then spare goods to a store.
check(plan("\{\}") == "full:mint:gold want:school:gold want:hut:stone", "the default order: {plan("\{\}")}")
// A store a little further off than a workshop: still the workshop with from_store unset; the store once it's cheap.
check(market_source(0, 1, 1, 1 << 40) == 3, "gold from the mint before the store")
check(market_source(0, 1, 1, 0) == 0, "and from the nearer store when stores cost nothing more")
// A pack's Lua delivery_level: stone to sites above all else.
l_api_names = LA_NAMES
lua_reset()
lua_api_consts()
lua_rules = su_rules
lua_quiet = true
check(lua_load_pack("t", [ "t.lua" ], [ "function delivery_level(b, r, level, kind) if kind == 0 and r == resource_index(\"stone\") then return 9 end return level end" ], L_BUDGET_LOAD) == "", "the pack loads")
lua_freeze()
lua_on = true
let by_lua = plan("\{\}")
check(by_lua == "want:hut:stone full:mint:gold want:school:gold", "a pack\'s delivery_level puts stone first: {by_lua}")
print "test_market: {passes} passed, {fails} failed"
