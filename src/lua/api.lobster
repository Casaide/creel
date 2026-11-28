// ------------------------------------------------------------------ the sim, as Lua sees it (#82)
// The functions and constants a pack's Lua has (lua/lua.lobster runs it), and the hook points that call into it. The
// names are the sim's own, with its 0-based slots and ids: u_task(i) is unit slot i's task, b_kind(b) building slot b's
// type, b_hold(b, r) what it holds of resource r. A setter is set_<name>. Each function checks its arguments: a bad one
// is an error in the pack, never a crash. A game calls the lua_<hook> functions from its own hooks (examples/plain).

import lua.lua
import lua.process

// The functions, in id order (lua_api's switch below goes by these ids).
let LA_NAMES = [ "unit_count", "u_id", "u_x", "u_y", "u_kind", "u_owner", "u_task", "u_target", "u_carry", "u_carry_kind",
    "u_moving", "u_stuck", "u_work", "u_orders", "unit_index", "set_u_task", "set_u_target", "set_u_work", "set_u_stuck", "set_u_moving",
    "building_count", "b_id", "b_kind", "b_owner", "b_done", "b_progress", "b_hold", "b_want", "b_coming", "b_is_site",
    "building_index", "building_rect", "mid_dist2", "offered", "site_permille", "bt_road", "bt_line", "bt_ladder", "bt_hold", "bt_store",
    "bt_build_ticks", "building_type", "building_type_count", "t_pop", "t_slot", "t_worker", "unit_type_count", "pop", "pop_cap", "set_pop",
    "worker_type", "road", "occupied", "amount", "res_at", "stocked", "tick", "want", "hold_take", "trained",
    "resource_index", "nearest_resource", "start_gather", "start_build", "approach_building", "clear_task", "in_reach", "unit_column", "building_column", "player_column",
    "unit_get", "unit_set", "building_get", "building_set", "player_get", "player_set", "rules", "player_count", "resource_count", "cell_of",
    "t_animal", "u_hp", "b_hp", "lay_foundation", "fits", "plant", "terrain_at", "terrain_type", "approach_cell", "b_making", "bt_drag", "entry_rect", "hold_put",
    "emit", "event_count", "event_get",
    "place", "give", "spawn", "wait", "wait_for", "expect", "keep", "kept",
    "delivery_count", "delivery_get", "site_phase", "build_stage", "event_kind", "building_type_index", "stock", "stock_take", "stock_put", "hurt",
    "reveal", "hide_cell", "discover_cell", "cell_known", "heal", "freeze", "frozen", "t_tag", "t_ranged", "take_cell", "defeat", "defeated", "is_bot", "build_site", "hurt_building" ]
let LA_TEST_FIRST = 96  // place ... kept: a pack's tests' own (testkit/pack_tests, #190), refused to its rules
let LA_TEST_LAST = 103

// The constants: the engine's task codes and units, and the map's size (set as a match starts).
def lua_api_consts():
    l_consts = [ "TICK_HZ", "TILE", "W", "H", "T_NONE", "GATHER", "T_RETURN", "BUILD", "T_CARRY", "GIVE_UP", "HOOK_ORDER_BASE" ]
    l_const_vals = map([ TICK_HZ, TILE, W, H, T_NONE, GATHER, T_RETURN, BUILD, T_CARRY, GIVE_UP, HOOK_ORDER_BASE ]) v: lv_int(v)

def lx_la_name(id:int) -> string: return LA_NAMES[id]

// Arguments that are slots or types: in range, or an error.
def lx_a_unit(a:[int], j:int, id:int) -> int:
    let i = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (i < 0 or i >= u_x.length): lua_fail("{lx_la_name(id)}: no unit slot {i} (there are {u_x.length})")
    return if not lfail: i else: -1

def lx_a_building(a:[int], j:int, id:int) -> int:
    let b = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (b < 0 or b >= b_id.length): lua_fail("{lx_la_name(id)}: no building slot {b} (there are {b_id.length})")
    return if not lfail: b else: -1

def lx_a_btype(a:[int], j:int, id:int) -> int:
    let k = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (k < 0 or k >= bt_build_ticks.length): lua_fail("{lx_la_name(id)}: no building type {k}")
    return if not lfail: k else: -1

def lx_a_utype(a:[int], j:int, id:int) -> int:
    let k = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (k < 0 or k >= t_pop.length): lua_fail("{lx_la_name(id)}: no unit type {k}")
    return if not lfail: k else: -1

def lx_a_res(a:[int], j:int, id:int) -> int:
    let r = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (r < 0 or r >= resource_names.length): lua_fail("{lx_la_name(id)}: no resource {r}")
    return if not lfail: r else: -1

def lx_a_player(a:[int], j:int, id:int) -> int:
    let p = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (p < 0 or p >= pop.length): lua_fail("{lx_la_name(id)}: no player {p}")
    return if not lfail: p else: -1

def lx_a_cell(a:[int], j:int, id:int) -> int:
    let c = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (c < 0 or c >= W * H): lua_fail("{lx_la_name(id)}: no cell {c}")
    return if not lfail: c else: -1

def lx_a_col(a:[int], j:int, id:int, names:[string]) -> int:
    let c = lx_want_int(a, j, lx_la_name(id))
    if not lfail and (c < 0 or c >= names.length): lua_fail("{lx_la_name(id)}: no column {c}")
    return if not lfail: c else: -1

def lx_a_bool(a:[int], j:int) -> bool: return lv_truthy(lx_arg_of(a, j))

def lx_r_int(n:int): lx_ret(lv_int(n))
def lx_r_bool(b:bool): lx_ret(lv_bool(b))

// A JSON value as Lua's: objects and arrays are tables (keys in file order), a fraction is nil (integers only).
def lua_of_json(v:JV) -> int:
    if v.kind == J_NULL: return LV_NIL
    if v.kind == J_BOOL: return lv_bool(v.i != 0)
    if v.kind == J_INT: return lv_int(v.i)
    if v.kind == J_FLOAT: return if float(int(v.f)) == v.f: lv_int(int(v.f)) else: LV_NIL
    if v.kind == J_STR: return lv_str(v.s)
    let t = lv_table()
    if v.kind == J_ARR:
        for(v.a) x, j: lua_set_raw(t, lv_int(j + 1), lua_of_json(x))
    else:
        for(v.keys) k, j: lua_set_raw(t, lv_str(k), lua_of_json(v.a[j]))
    return t

// The functions that change the sim: not while it's only being read (the view's calls, and can_place).
let LA_WRITE_NAMES = [ "lay_foundation", "plant", "approach_cell", "set_u_task", "set_u_target", "set_u_work", "set_u_stuck", "set_u_moving", "set_pop", "want", "hold_take", "hold_put", "stock_take", "stock_put", "hurt",
    "reveal", "hide_cell", "discover_cell", "heal", "freeze", "take_cell", "defeat", "build_site", "hurt_building", "emit", "trained", "start_gather", "start_build", "approach_building", "clear_task", "unit_set", "building_set", "player_set" ]
let LA_WRITES = map(LA_WRITE_NAMES) n:
    let id = find(LA_NAMES) x: x == n
    assert id >= 0
    id
var lua_read_only = false
var lua_bots = []::int  // per player: 1 when a bot plays it this tick. The harness sets it before each step (match_loop's
                        // sim_run by the rule it runs the bots by); derived, the same on every machine, never saved (#255)

// A pack's tests (testkit/pack_tests): what the phase that's running asked for, read by the runner when it returns.
var lua_testing = false          // a test's phase is running: the test functions answer
var lt_wait = 0                  // ticks to run before the next phase (or at most, waiting for an event)
var lt_until = -1                // the event kind it waits for (-1: none), and its a, b, c (LV_NIL: any)
let lt_until_abc = [ 0, 0, 0 ]
let lt_until_set = [ false, false, false ]
var lt_failed = []::string       // what expect() found wrong
var lt_keep_names = []::string   // keep(name, v): what a test carries from one phase to the next
var lt_keep_vals = []::int
var lt_rets = []::int            // a test function's results (lua_api_call)

def lt_r_int(n:int): lt_rets.push(lv_int(n))

// A test's own functions (place, spawn ...) run the sim, whose hooks run the packs' Lua inside the call: their results
// are theirs, so the test function's own are made apart and are what the call returns.
def lua_api_call(id:int, a:[int]):
    if id < LA_TEST_FIRST or id > LA_TEST_LAST:
        lua_api(id, a)
        return
    if not lua_testing:
        lua_fail("{lx_la_name(id)}: only a pack\'s tests may (tests/*.lua)")
        return
    lua_api(id, a)
    let got = lt_rets
    lt_rets = []
    rets = got

def lua_api(id:int, a:[int]):
    if lua_read_only and contains(LA_WRITES, id):
        lua_fail("{lx_la_name(id)}: this hook only reads (it isn\'t the sim)")
        return
    switch id:
        case 0: lx_r_int(u_x.length)
        case 1:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_id[i])
        case 2:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_x[i])
        case 3:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_y[i])
        case 4:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_kind[i])
        case 5:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_owner[i])
        case 6:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_task[i])
        case 7:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_target[i])
        case 8:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_carry[i])
        case 9:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_carry_kind[i])
        case 10:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_moving[i])
        case 11:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_stuck[i])
        case 12:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_work[i])
        case 13:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_orders[i].length)
        case 14: lx_r_int(index_of(lx_want_int(a, 0, lx_la_name(id))))
        case 15, 16, 17, 18, 19:
            let i = lx_a_unit(a, 0, id)
            let v = lx_want_int(a, 1, lx_la_name(id))
            if i >= 0 and not lfail:
                if id == 15: u_task[i] = v
                elif id == 16: u_target[i] = v
                elif id == 17: u_work[i] = v
                elif id == 18: u_stuck[i] = v
                else: u_moving[i] = v
        case 20: lx_r_int(b_id.length)
        case 21, 22, 23, 24, 25:
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(if id == 21: b_id[b] elif id == 22: b_kind[b] elif id == 23: b_owner[b] elif id == 24: b_done[b] else: b_progress[b])
        case 26, 27, 28, 33:
            let b = lx_a_building(a, 0, id)
            let r = lx_a_res(a, 1, id)
            if b >= 0 and r >= 0:
                if id == 33: lx_r_int(offered(b, r))
                else:
                    let v = (if id == 26: b_hold elif id == 27: b_want else: b_coming)[b]
                    lx_r_int(if r < v.length: v[r] else: 0)
        case 29:
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_bool(b_site[b].length > 0)
        case 30: lx_r_int(b_index_of(lx_want_int(a, 0, lx_la_name(id))))
        case 31:
            let b = lx_a_building(a, 0, id)
            if b >= 0:
                let x0, y0, x1, y1 = building_rect(b)
                lx_r_int(x0)
                lx_r_int(y0)
                lx_r_int(x1)
                lx_r_int(y1)
        case 32:
            let b = lx_a_building(a, 0, id)
            let x = lx_want_int(a, 1, lx_la_name(id))
            let y = lx_want_int(a, 2, lx_la_name(id))
            if b >= 0 and not lfail: lx_r_int(mid_dist2(b, x, y))
        case 34:
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(site_permille(b))
        case 35, 36, 37, 39, 40:
            let k = lx_a_btype(a, 0, id)
            if k >= 0:
                if id == 35: lx_r_int(bt_road[k])
                elif id == 36: lx_r_bool(bt_line[k] != 0)
                elif id == 37: lx_r_bool(bt_ladder[k] != 0)
                elif id == 39: lx_r_bool(bt_store[k] != 0)
                else: lx_r_int(bt_build_ticks[k])
        case 38:
            let k = lx_a_btype(a, 0, id)
            let r = lx_a_res(a, 1, id)
            if k >= 0 and r >= 0: lx_r_int(if r < bt_hold[k].length: bt_hold[k][r] else: 0)
        case 41:
            let k = lx_a_btype(a, 0, id)
            if k >= 0: lx_ret(lua_of_json(su_btypes[k]))
        case 42: lx_r_int(bt_build_ticks.length)
        case 43, 44, 45, 80:
            let k = lx_a_utype(a, 0, id)
            if k >= 0:
                if id == 43: lx_r_int(t_pop[k])
                elif id == 44: lx_ret(lv_str(t_slot[k]))
                elif id == 45: lx_r_bool(t_worker[k] != 0)
                else: lx_r_bool(t_animal[k] != 0)
        case 46: lx_r_int(t_pop.length)
        case 47, 48, 50:
            let p = lx_a_player(a, 0, id)
            if p >= 0: lx_r_int(if id == 47: pop[p] elif id == 48: pop_cap[p] else: worker_type(p))
        case 49:
            let p = lx_a_player(a, 0, id)
            let v = lx_want_int(a, 1, lx_la_name(id))
            if p >= 0 and not lfail: pop[p] = v
        case 51, 52, 53, 54:
            let c = lx_a_cell(a, 0, id)
            if c >= 0:
                if id == 51: lx_r_int(if road.length: road[c] else: 0)
                elif id == 52: lx_r_int(occupied[c])
                elif id == 53: lx_r_int(amount[c])
                else: lx_r_int(res_at(c))
        case 55: lx_r_bool(r_stocked != 0)
        case 56: lx_r_int(tick)
        case 57, 58:
            let b = lx_a_building(a, 0, id)
            let r = lx_a_res(a, 1, id)
            let n = lx_want_int(a, 2, lx_la_name(id))
            if b >= 0 and r >= 0 and not lfail:
                if b_hold[b].length <= r: lua_fail("{lx_la_name(id)}: building {b} holds nothing (the economy isn\'t stocked)")
                elif id == 57: want(b, r, n)
                else:
                    let got = hold_take(b, r, n)
                    if got > 0: ev_goods(EV_TAKEN, 0, b, r, got)
                    lx_r_int(got)
        case 59:
            let b = lx_a_building(a, 0, id)
            let k = lx_a_utype(a, 1, id)
            if b >= 0 and k >= 0: lx_r_int(trained(b, k))
        case 60:
            let name = lx_want_str(a, 0, lx_la_name(id))
            lx_r_int(find(resource_names) n: n == name)
        case 61:
            let x = lx_want_int(a, 0, lx_la_name(id))
            let y = lx_want_int(a, 1, lx_la_name(id))
            let kind = lx_want_int(a, 2, lx_la_name(id))
            let i = lx_a_unit(a, 3, id)
            if i >= 0 and not lfail: lx_r_int(nearest_resource(x, y, kind, i, lx_a_bool(a, 4), lx_a_bool(a, 5), lx_a_bool(a, 6)))
        case 62:
            let i = lx_a_unit(a, 0, id)
            let c = lx_a_cell(a, 1, id)
            let kind = lx_want_int(a, 2, lx_la_name(id))
            if i >= 0 and c >= 0 and not lfail: start_gather(i, c, kind)
        case 63:
            let i = lx_a_unit(a, 0, id)
            let bid = lx_want_int(a, 1, lx_la_name(id))
            if i >= 0 and not lfail:
                if b_index_of(bid) < 0: lua_fail("start_build: no building with id {bid}")
                else: start_build(i, bid)
        case 64:
            let i = lx_a_unit(a, 0, id)
            let b = lx_a_building(a, 1, id)
            if i >= 0 and b >= 0: approach_building(i, b)
        case 65:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: clear_task(i)
        case 66:
            let i = lx_a_unit(a, 0, id)
            let x0 = lx_want_int(a, 1, lx_la_name(id))
            let y0 = lx_want_int(a, 2, lx_la_name(id))
            let x1 = lx_want_int(a, 3, lx_la_name(id))
            let y1 = lx_want_int(a, 4, lx_la_name(id))
            if i >= 0 and not lfail: lx_r_bool(in_reach(i, x0, y0, x1, y1))
        case 67, 68, 69:
            let name = lx_want_str(a, 0, lx_la_name(id))
            if lfail: return
            if l_loaded: lua_fail("{lx_la_name(id)}: columns are declared as the files load, not in a hook")
            else:
                let names = if id == 67: hook_unit_names elif id == 68: hook_building_names else: hook_player_names
                let known = find(names) n: n == name
                if known >= 0: lx_r_int(known)  // (two packs can share a column by its name)
                elif id == 67: lx_r_int(hook_declare_unit(name))
                elif id == 68: lx_r_int(hook_declare_building(name))
                else: lx_r_int(hook_declare_player(name, pop.length))
        case 70, 71:
            let c = lx_a_col(a, 0, id, hook_unit_names)
            let i = lx_a_unit(a, 1, id)
            if c >= 0 and i >= 0:
                if id == 70: lx_r_int(hook_unit_get(c, i))
                else:
                    let v = lx_want_int(a, 2, lx_la_name(id))
                    if not lfail: hook_unit_set(c, i, v)
        case 72, 73:
            let c = lx_a_col(a, 0, id, hook_building_names)
            let b = lx_a_building(a, 1, id)
            if c >= 0 and b >= 0:
                if id == 72: lx_r_int(hook_building_get(c, b))
                else:
                    let v = lx_want_int(a, 2, lx_la_name(id))
                    if not lfail: hook_building_set(c, b, v)
        case 74, 75:
            let c = lx_a_col(a, 0, id, hook_player_names)
            let p = lx_a_player(a, 1, id)
            if c >= 0 and p >= 0:
                if id == 74: lx_r_int(hook_player_cols[c][p])
                else:
                    let v = lx_want_int(a, 2, lx_la_name(id))
                    if not lfail: hook_player_cols[c][p] = v
        case 76: lx_ret(lua_of_json(su_rules))
        case 77: lx_r_int(pop.length)
        case 78: lx_r_int(resource_names.length)
        case 79:
            let x = lx_want_int(a, 0, lx_la_name(id))
            let y = lx_want_int(a, 1, lx_la_name(id))
            if not lfail: lx_r_int(cell_of(x, y))
        case 81:
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(u_hp[i])
        case 82:
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(b_hp[b])
        case 83:  // lay_foundation(p, k, cx, cy): a site where the ground lets it go, the packs' rules aside (#105); its id, or 0
            let p = lx_a_player(a, 0, id)
            let k = lx_a_btype(a, 1, id)
            let cx = lx_want_int(a, 2, lx_la_name(id))
            let cy = lx_want_int(a, 3, lx_la_name(id))
            if not lfail and p >= 0 and k >= 0: lx_r_int(if ground_fits(p, k, cx, cy) and not build_barred(p, k): place_site(p, k, cx, cy, 0) else: 0)
        case 84:  // fits(p, k, cx, cy): whether the ground lets player p lay type k there, the packs' rules aside (#105)
            let p = lx_a_player(a, 0, id)
            let k = lx_a_btype(a, 1, id)
            let cx = lx_want_int(a, 2, lx_la_name(id))
            let cy = lx_want_int(a, 3, lx_la_name(id))
            if not lfail and p >= 0 and k >= 0: lx_r_bool(ground_fits(p, k, cx, cy, 0))
        case 85:  // plant(c, t): terrain type t (one that grows) on cell c, free walkable ground; whether it was (#109)
            let c = lx_a_cell(a, 0, id)
            let t = lx_want_int(a, 1, lx_la_name(id))
            if not lfail and c >= 0: lx_r_bool(plant(c, t))
        case 86:  // terrain_at(c): the cell's terrain type
            let c = lx_a_cell(a, 0, id)
            if not lfail and c >= 0: lx_r_int(terrain[c])
        case 87:  // terrain_type(id): the terrain type of that id (terrain.json), or -1
            let s = lx_want_str(a, 0, lx_la_name(id))
            if not lfail: lx_r_int(str_index(tr_names, s))
        case 88:  // approach_cell(i, c): unit i walks to stand by cell c (its task as it was)
            let i = lx_a_unit(a, 0, id)
            let c = lx_a_cell(a, 1, id)
            if not lfail and i >= 0 and c >= 0: approach_cell(i, c)
        case 89:  // b_making(b): the ticks left in building b's round of its recipe, 0 when none is going (#120)
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(b_make[b])
        case 90:  // bt_drag(k): whether type k is laid by dragging, a plan a cell (a road or a field, #126)
            let k = lx_a_btype(a, 0, id)
            if k >= 0: lx_r_bool(bt_drag[k] != 0)
        case 91:  // entry_rect(b): where a unit stands to reach building b: its door tile with economy "doors", else round it (#133)
            let b = lx_a_building(a, 0, id)
            if b >= 0:
                let x0, y0, x1, y1 = entry_rect(b)
                lx_r_int(x0)
                lx_r_int(y0)
                lx_r_int(x1)
                lx_r_int(y1)
        case 92:  // hold_put(b, r, n): put n of r into building b, as much as it has room for; how many went in (#142)
            let b = lx_a_building(a, 0, id)
            let r = lx_a_res(a, 1, id)
            let n = lx_want_int(a, 2, lx_la_name(id))
            if b >= 0 and r >= 0 and not lfail:
                if b_hold[b].length <= r: lua_fail("hold_put: building {b} holds nothing (the economy isn\'t stocked)")
                else:
                    let put = hold_put(b, r, max(0, n))
                    if put > 0: ev_goods(EV_PUT, 0, b, r, put)
                    lx_r_int(put)
        case 93:  // emit(code, a, b, c, n): the pack's own event, EV_PACK + code (0 to 899), in this tick's events (#187)
            let code = lx_want_int(a, 0, "emit")
            let ea = lx_want_int(a, 1, "emit")
            let eb = lx_want_int(a, 2, "emit")
            let ec = lx_want_int(a, 3, "emit")
            let en = lx_want_int(a, 4, "emit")
            if not lfail:
                if code < 0 or code >= 900: lua_fail("emit: a pack\'s event code is 0 to 899, not {code}")
                elif events_on: events.push(Event { EV_PACK + code, ea, eb, ec, 0, 0, en })
        case 94: lx_r_int(events.length)  // event_count(): this tick's events so far
        case 95:  // event_get(i, field): field 0 kind, 1 a, 2 b, 3 c, 4 n, 5 x, 6 y of this tick's event i (from 0)
            let i = lx_want_int(a, 0, "event_get")
            let f = lx_want_int(a, 1, "event_get")
            if not lfail:
                if i < 0 or i >= events.length or f < 0 or f > 6: lua_fail("event_get: no event {i} field {f} ({events.length} this tick)")
                else:
                    let e = events[i]
                    lx_r_int([ e.kind, e.a, e.b, e.c, e.n, e.x, e.y ][f])
        case 96:  // place(p, type, cx, cy, built): building type `type` (its id) for player p with its corner on cx, cy, where it fits; its id or 0
            let p = lx_a_player(a, 0, id)
            let name = lx_want_str(a, 1, "place")
            let cx = lx_want_int(a, 2, "place")
            let cy = lx_want_int(a, 3, "place")
            let built = lx_a_bool(a, 4)
            if p >= 0 and not lfail:
                let k = btype_index(name)
                if k < 0: lua_fail("place: no building type \"{name}\"")
                elif not can_place(p, k, cx, cy): lt_r_int(0)
                elif built:
                    let b = place(p, k, cx, cy)
                    b_done[b] = 1
                    b_progress[b] = bt_build_ticks[k]
                    b_hp[b] = bm_hp[p][k]
                    update_pop()
                    mark_carry(p)
                    lt_r_int(b_id[b])
                else: lt_r_int(place_site(p, k, cx, cy, 0))
        case 97:  // give(b, r, n): n of r into building slot b, as much as it has room for; how many went in
            let b = lx_a_building(a, 0, id)
            let r = lx_a_res(a, 1, id)
            let n = lx_want_int(a, 2, "give")
            if b >= 0 and r >= 0 and not lfail:
                if b_hold[b].length <= r: lua_fail("give: building {b} holds nothing (the economy isn\'t stocked)")
                else: lt_r_int(hold_put(b, r, max(0, n)))
        case 98:  // spawn(p, slot, x, y): a unit of player p's type in slot `slot` at x, y (sim units); its slot
            let p = lx_a_player(a, 0, id)
            let slot = lx_want_str(a, 1, "spawn")
            let x = lx_want_int(a, 2, "spawn")
            let y = lx_want_int(a, 3, "spawn")
            if p >= 0 and not lfail:
                let k = type_of_slot(p, slot)
                if k < 0: lua_fail("spawn: player {p} has no \"{slot}\"")
                elif x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: lua_fail("spawn: {x}, {y} is off the map")
                else: lt_r_int(add_unit(p, k, x, y))
        case 99:  // wait(n): after this phase, run n ticks, then the next phase
            let n = lx_want_int(a, 0, "wait")
            if not lfail:
                lt_wait = n
                lt_until = -1
        case 100:  // wait_for(kind, max, a, b, c): run until an event of this kind (its name, or a pack's own code as emit takes) and a, b, c where given happens, at most max ticks
            let kv = lx_arg_of(a, 0)
            let k = if lv_is_int(kv): (if (kv >> 3) >= 0 and (kv >> 3) < 900: EV_PACK + (kv >> 3) else: -1) else: ev_kind(lx_want_str(a, 0, "wait_for"))
            let n = lx_want_int(a, 1, "wait_for")
            if not lfail:
                if k < 0: lua_fail("wait_for: no event kind {lua_tostring(kv)} (a name, or a pack\'s own code, 0 to 899)")
                else:
                    lt_wait = n
                    lt_until = k
                    for(3) f:
                        let v = lx_arg_of(a, 2 + f)
                        lt_until_set[f] = lv_is_int(v)
                        lt_until_abc[f] = if lv_is_int(v): v >> 3 else: 0
        case 101:  // expect(ok, what): a test's check; what's said when it doesn't hold
            if not lx_a_bool(a, 0): lt_failed.push(if (lx_arg_of(a, 1) & 7) == LT_STR: lv_text(lx_arg_of(a, 1)) else: "expect() failed")
        case 102:  // keep(name, v): an integer kept for the test's later phases
            let name = lx_want_str(a, 0, "keep")
            let v = lx_want_int(a, 1, "keep")
            if not lfail:
                let at_ = find(lt_keep_names): _ == name
                if at_ >= 0: lt_keep_vals[at_] = v
                else:
                    lt_keep_names.push(name)
                    lt_keep_vals.push(v)
        case 103:  // kept(name): what keep() kept, or nil
            let name = lx_want_str(a, 0, "kept")
            if not lfail:
                let at_ = find(lt_keep_names): _ == name
                if at_ >= 0: lt_r_int(lt_keep_vals[at_])
        case 104: lx_r_int(jb_id.length)  // delivery_count(): the deliveries under way (carriers on a job, #191)
        case 105:  // delivery_get(j, field): field 0 the carrier's id, 1 from (a building id), 2 to, 3 the good, 4 how many, 5 its phase (0 fetching, 1 bringing)
            let j = lx_want_int(a, 0, "delivery_get")
            let f = lx_want_int(a, 1, "delivery_get")
            if not lfail:
                if j < 0 or j >= jb_id.length or f < 0 or f > 5: lua_fail("delivery_get: no delivery {j} field {f} ({jb_id.length} under way)")
                else: lx_r_int([ jb_unit[j], jb_from[j], jb_to[j], jb_res[j], jb_n[j], jb_phase[j] ][f])
        case 106:  // site_phase(b): 0 levelling, 1 waiting for goods, 2 building, 3 standing (#192)
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(site_phase(b))
        case 107:  // build_stage(b): the stage of its type's "stages" site b is at, from 0 (#193)
            let b = lx_a_building(a, 0, id)
            if b >= 0: lx_r_int(build_stage(b))
        case 108:  // event_kind(name): the kind of event `name` (pick, drop, built ...: EV_NAMES), as event_get's field 0 (#194)
            let name = lx_want_str(a, 0, "event_kind")
            if not lfail:
                let k = ev_kind(name)
                if k < 0 or starts_with(name, "pack:"): lua_fail("event_kind: no event kind {name} (a pack\'s own is 100 + its code)")
                else: lx_r_int(k)
        case 109:  // building_type_index(name): the type whose buildings.json key is name, or -1 (#226)
            let name = lx_want_str(a, 0, "building_type_index")
            if not lfail: lx_r_int(find(bt_name): _ == name)
        case 110, 111, 112:  // stock(p, r), stock_take(p, r, n), stock_put(p, r, n): player p's goods of r (#222)
            let p = lx_a_player(a, 0, id)
            let r = lx_a_res(a, 1, id)
            if p >= 0 and r >= 0 and not lfail:
                let have = if r < stock.length and p < stock[r].length: stock[r][p] else: 0
                if id == 110: lx_r_int(have)
                else:
                    let n = lx_want_int(a, 2, lx_la_name(id))
                    if lfail: return
                    if r_stocked != 0: lua_fail("{lx_la_name(id)}: the economy is stocked, its goods are in buildings\' holds (hold_take, hold_put)")
                    elif r >= stock.length or p >= stock[r].length: lua_fail("{lx_la_name(id)}: player {p} keeps no {r}")
                    elif id == 111:
                        let got = clamp(n, 0, have)
                        stock[r][p] -= got
                        if got > 0 and events_on: events.push(Event { EV_STOCK_TAKEN, p, 0, r, 0, 0, got })
                        lx_r_int(got)
                    else:
                        let put = max(0, n)
                        stock[r][p] += put
                        if put > 0 and events_on: events.push(Event { EV_STOCK_PUT, p, 0, r, 0, 0, put })
                        lx_r_int(put)
        case 113:  // hurt(i, n): unit slot i loses n hit points; at none left it dies in the tick's blows, as a blow kills (on_death with no killer: 0)
            let i = lx_a_unit(a, 0, id)
            let n = lx_want_int(a, 1, lx_la_name(id))
            if i >= 0 and not lfail:
                if n < 0: lua_fail("hurt: {n} hit points: a unit is hurt by 0 or more")
                else:
                    u_hp[i] = max(0, u_hp[i] - n)
                    lx_r_int(u_hp[i])
        case 114:  // reveal(p, x, y, r, ticks): player p's team sees r tiles round x, y (sim units) for ticks, as a unit there would (#239)
            let p = lx_a_player(a, 0, id)
            let x = lx_want_int(a, 1, "reveal")
            let y = lx_want_int(a, 2, "reveal")
            let r = lx_want_int(a, 3, "reveal")
            let n = lx_want_int(a, 4, "reveal")
            if p >= 0 and not lfail:
                if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: lua_fail("reveal: {x}, {y} is off the map")
                elif r < 0 or r > 32: lua_fail("reveal: a radius of 0 to 32 tiles, not {r}")
                elif n > 0:
                    for([ p, x, y, r, tick + n ]) v: reveals.push(v)
        case 115, 116:  // hide_cell(c): no player knows cell c until it's found; discover_cell(p, c): player p (and its team) has found it (#239)
            let c = lx_a_cell(a, if id == 115: 0 else: 1, id)
            let p = if id == 116: lx_a_player(a, 0, id) else: 0
            if c >= 0 and p >= 0 and not lfail:
                let found, at = binary_search(secret_cells, c)
                if id == 115:
                    if not found:
                        secret_cells.insert(at, c)
                        secret_known.insert(at, 0)
                    else: secret_known[at] = 0
                elif found: secret_known[at] |= 1 << p
        case 117:  // cell_known(p, c): whether player p (or its team) knows cell c: every cell but a secret not yet found
            let p = lx_a_player(a, 0, id)
            let c = lx_a_cell(a, 1, id)
            if p >= 0 and c >= 0: lx_r_bool(cell_known(p, c))
        case 118:  // heal(i, n): unit slot i regains up to n hit points, never past its type's; its hit points then
            let i = lx_a_unit(a, 0, id)
            let n = lx_want_int(a, 1, "heal")
            if i >= 0 and not lfail:
                if n < 0: lua_fail("heal: {n} hit points: a unit is healed by 0 or more")
                else:
                    if u_hp[i] > 0: u_hp[i] = min(t_hp[u_kind[i]], u_hp[i] + n)
                    lx_r_int(u_hp[i])
        case 119:  // freeze(i, ticks): unit slot i neither moves nor strikes for ticks from now (the longer of two)
            let i = lx_a_unit(a, 0, id)
            let n = lx_want_int(a, 1, "freeze")
            if i >= 0 and not lfail and n > 0: freeze(i, n)
        case 120:  // frozen(i): the ticks unit slot i is still held still (0: it isn't)
            let i = lx_a_unit(a, 0, id)
            if i >= 0: lx_r_int(frozen_left(i))
        case 121:  // t_tag(k, name): whether unit type k's line carries that tag (its row in the race's table)
            let k = lx_a_utype(a, 0, id)
            let name = lx_want_str(a, 1, "t_tag")
            if k >= 0 and not lfail: lx_r_bool(k < su_units.length and (find(gstrs(su_units[k], "tags")): _ == name) >= 0)
        case 122:  // t_ranged(k): whether unit type k shoots (its reach is a range, not a blow)
            let k = lx_a_utype(a, 0, id)
            if k >= 0: lx_r_bool(t_ranged[k] != 0)
        case 123:  // take_cell(c, n): up to n of cell c's resource taken, as gathering takes it (the last turns it to its depleted terrain); how many (#245)
            let c = lx_a_cell(a, 0, id)
            let n = lx_want_int(a, 1, "take_cell")
            if c >= 0 and not lfail:
                if n < 0: lua_fail("take_cell: {n}: a cell gives 0 or more")
                else:
                    let got = min(n, max(0, left_at(c)))
                    for(got): take(c)
                    lx_r_int(got)
        case 124, 125:  // defeat(p): player p is out, as if it had surrendered (an earlier defeat stands); defeated(p): whether it's out (#249)
            let p = lx_a_player(a, 0, id)
            if p >= 0:
                if id == 124:
                    if defeated[p] == 0: defeated[p] = tick + 1
                else: lx_r_bool(defeated[p] != 0)
        case 126:  // is_bot(p): whether a bot plays player p this tick (lua_bots, set by the harness before each step, #255)
            let p = lx_a_player(a, 0, id)
            if p >= 0: lx_r_bool(p < lua_bots.length and lua_bots[p] != 0)
        case 127:  // build_site(b, n): site b moves on by n ticks of building, as a builder's work would, and stands at its time (#257)
            let b = lx_a_building(a, 0, id)
            let n = lx_want_int(a, 1, "build_site")
            if b >= 0 and not lfail:
                if n < 0: lua_fail("build_site: {n} ticks: a site moves on by 0 or more")
                elif b_done[b] == 0 and n > 0: site_work(b, n, -1)
        case 128:  // hurt_building(b, n): building b takes n damage; at none left it falls, as one does to blows (slots after it move: keep ids, #258)
            let b = lx_a_building(a, 0, id)
            let n = lx_want_int(a, 1, "hurt_building")
            if b >= 0 and not lfail:
                if n < 0: lua_fail("hurt_building: {n} damage: a building is hurt by 0 or more")
                else:
                    b_hp[b] = max(0, b_hp[b] - n)
                    lx_r_int(b_hp[b])
                    if b_hp[b] == 0: fall(b)
        default: lua_fail("an unknown API function")

// ------------------------------------------------------------------ the hook points
var hook_view = false  // the view is asking a hook (the placement preview, the panel): it may only read, and a failure
                       // there mustn't change the sim (it runs on one machine). Not the match's state.
var lua_on = false  // a pack has Lua: the hooks below have something to call
var lua_test_id = ""                 // a pack's tests, loaded after the packs while they run (testkit/pack_tests)
var lua_test_files = []::string
var lua_test_sources = []::string
var lua_rules = jobj()  // the rules the packs' Lua last loaded with: a new match or a loaded save loads it again
let L_BUDGET_TICK = 4000000  // a pack's steps in one tick, all its calls together
let L_BUDGET_VIEW = 100000   // a call the view makes (the placement preview, the panel)

// The pack stopped in the sim: noted in the match's state (saved and hashed), so it stays stopped through a save.
def lx_note_stop(pk:LPack):
    if pk.error == "" or (find(hook_stopped) id: id == pk.id) >= 0: return
    hook_stopped.push(pk.id)
    hook_stopped_why.push(pk.error)

// A pack's files or sources with Creel's process library first (lua/process).
def with_process(xs:[string], first:string) -> [string]:
    let out = [ first ]
    for(xs) x: out.push(x)
    return out

// As a match starts (the game's hook_declare): every pack's Lua runs, the game's first, and is then read-only. A pack
// the match's state says stopped stays stopped (a loaded save).
def lua_declare() -> void:
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_on = false
    for(lib_packs) p:
        pack_lua(p)
        if p.lua_files.length:
            lua_on = true
            let files = map(p.lua_files) f: p.id + "/hooks/" + f
            lua_load_pack(p.id, with_process(files, LUA_PROCESS_FILE), with_process(p.lua_sources, LUA_PROCESS))
            let pk = top(l_packs)
            let was = find(hook_stopped) id: id == p.id
            if was >= 0: pk.error = hook_stopped_why[was]
            else: lx_note_stop(pk)
    if lua_test_files.length:  // (a pack's tests, last: testkit/pack_tests)
        lua_on = true
        lua_load_pack(lua_test_id, with_process(lua_test_files, LUA_PROCESS_FILE), with_process(lua_test_sources, LUA_PROCESS))
    if lua_on: events_on = true  // (a pack may read this tick's events: they're there whoever else reads them)
    lua_freeze()

// The packs' Lua for this match: loaded again if the rules aren't the ones it loaded with (a save was loaded). Never
// from the view: it waits for the sim's next call.
def lua_fresh() -> bool:
    if lua_rules != su_rules:
        if hook_view: return false
        lua_declare()
    return lua_on

// The packs that stopped, and why (a load error, a run-time error or the step budget).
def lua_errors() -> [string]:
    let out = []::string
    for(l_packs) pk:
        if pk.error != "": out.push("{pk.id}: {pk.error}")
    return out

// Calls f in pack pk for a hook. From the sim: within its call's and its tick's budget, and a failure stops the pack
// (noted in the match's state). From the view (hook_view: the placement preview, the panel): read-only, a small budget,
// and a failure is only logged: the view runs on one machine, and mustn't change what the sim does on it.
def lua_hook_run(pk:LPack, f:int, args:[int]) -> bool:
    if hook_view:
        let ro = lua_read_only
        lua_read_only = true
        l_view = true
        let ok = lua_run(pk, f, args, L_BUDGET_VIEW)
        l_view = false
        lua_read_only = ro
        return ok
    if ldepth == 0 and pk.at != tick:
        pk.at = tick
        pk.spent = 0
    let ok = lua_run(pk, f, args, min(L_BUDGET_CALL, L_BUDGET_TICK - pk.spent))
    if not ok: lx_note_stop(pk)
    return ok

// Calls each pack's `name` that it defines, in load order; then the region ends.
// (The callback gets each call's results, before they go.)
def lua_each(name:string, args:[int], got):
    for(l_packs) pk:
        let f = lua_hook_fn(pk, name)
        if f != LV_NIL:
            if lua_hook_run(pk, f, args): got(rets)
    lua_region_end()

def lua_tick():
    if not lua_fresh(): return
    lua_each("on_tick", []::int) r:
        pass()

def lua_unit_tick(i:int):
    if not lua_fresh(): return
    lua_each("on_unit_tick", [ lv_int(i) ]) r:
        pass()

// Whether a pack refuses the spot. It only reads, from the sim (lay_foundation, the bots) or the view (the preview).
def lua_can_place(p:int, k:int, cx:int, cy:int, sx:int, sy:int) -> bool:
    if not lua_fresh(): return true
    var ok = true
    let args = map([ p, k, cx, cy, sx, sy ]) v: lv_int(v)
    let ro = lua_read_only
    lua_read_only = true
    lua_each("can_place", args) r:
        if r.length and not lv_truthy(r[0]): ok = false
    lua_read_only = ro
    return ok

// Whether the packs let building slot b start a round of its recipe (lib/recipes: its inputs are in). It only reads.
def lua_can_make(b:int) -> bool:
    if not lua_fresh(): return true
    var ok = true
    let ro = lua_read_only
    lua_read_only = true
    lua_each("can_make", [ lv_int(b) ]) r:
        if r.length and not lv_truthy(r[0]): ok = false
    lua_read_only = ro
    return ok

def lua_on_hit(by:int, target:int, damage:int) -> int:
    if not lua_fresh(): return damage
    var d = damage
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "on_hit")
        if f != LV_NIL and lua_hook_run(pk, f, [ lv_int(by), lv_int(target), lv_int(d) ]):
            if rets.length and lv_is_int(rets[0]): d = rets[0] >> 3
    lua_region_end()
    return d

def lua_on_hurt(target:int, by:int):
    if not lua_fresh(): return
    lua_each("on_hurt", [ lv_int(target), lv_int(by) ]) r:
        pass()

def lua_on_death(i:int, killer:int):
    if not lua_fresh(): return
    lua_each("on_death", [ lv_int(i), lv_int(killer) ]) r:
        pass()

def lua_on_order(code:int, p:int, ids:[int], x:int, y:int):
    if not lua_fresh(): return
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "on_order")
        if f != LV_NIL:
            let list = lua_list(map(ids) v: lv_int(v))
            lua_hook_run(pk, f, [ lv_int(code), lv_int(p), list, lv_int(x), lv_int(y) ])
    lua_region_end()

// The rules' level for a delivery (lib/carry's market, #191), as a pack's delivery_level(dst, r, level, kind) says.
def lua_delivery_level(b:int, r:int, given:int, kind:int) -> int:
    if not lua_fresh(): return given
    var l = given
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "delivery_level")
        if f != LV_NIL and lua_hook_run(pk, f, [ lv_int(b), lv_int(r), lv_int(l), lv_int(kind) ]):
            if rets.length and lv_is_int(rets[0]): l = rets[0] >> 3
    lua_region_end()
    return l

def lua_ai_train_score(p:int, slot:string, k:int, score:int) -> int:
    if not lua_fresh(): return score
    var s = score
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "ai_train_score")
        if f != LV_NIL and lua_hook_run(pk, f, [ lv_int(p), lv_str(slot), lv_int(k), lv_int(s) ]):
            if rets.length and lv_is_int(rets[0]): s = rets[0] >> 3
    lua_region_end()
    return s

// What the panel says unit slot i is doing, when a pack made the task up ("" for the engine's own tasks). The view
// asks: it only reads, and a failure doesn't stop the pack.
def lua_task_name(i:int) -> string:
    let view0 = hook_view
    hook_view = true
    var name = ""
    if lua_fresh():
        lua_each("task_name", [ lv_int(i) ]) r:
            if name == "" and r.length and (r[0] & 7) == LT_STR: name = lv_text(r[0])
    hook_view = view0
    return name

// can_place, asked by the view (the placement preview): a pack's rules may only read, and can't stop over it.
def view_can_place(player:int, k:int, cx:int, cy:int, along:int = 0) -> bool:
    let view0 = hook_view
    hook_view = true
    let ok = can_place(player, k, cx, cy, along)
    hook_view = view0
    return ok
