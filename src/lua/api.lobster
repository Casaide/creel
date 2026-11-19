// ------------------------------------------------------------------ the sim, as Lua sees it (#82)
// The functions and constants a pack's Lua has (lua/lua.lobster runs it), and the hook points that call into it. The
// names are the sim's own, with its 0-based slots and ids: u_task(i) is unit slot i's task, b_kind(b) building slot b's
// type, b_hold(b, r) what it holds of resource r. A setter is set_<name>. Each function checks its arguments: a bad one
// is an error in the pack, never a crash. A game calls the lua_<hook> functions from its own hooks (examples/plain).

import lua.lua

// The functions, in id order (lua_api's switch below goes by these ids).
let LA_NAMES = [ "unit_count", "u_id", "u_x", "u_y", "u_kind", "u_owner", "u_task", "u_target", "u_carry", "u_carry_kind",
    "u_moving", "u_stuck", "u_work", "u_orders", "unit_index", "set_u_task", "set_u_target", "set_u_work", "set_u_stuck", "set_u_moving",
    "building_count", "b_id", "b_kind", "b_owner", "b_done", "b_progress", "b_hold", "b_want", "b_coming", "b_is_site",
    "building_index", "building_rect", "mid_dist2", "offered", "site_permille", "bt_road", "bt_line", "bt_ladder", "bt_hold", "bt_store",
    "bt_build_ticks", "building_type", "building_type_count", "t_pop", "t_slot", "t_worker", "unit_type_count", "pop", "pop_cap", "set_pop",
    "worker_type", "road", "occupied", "amount", "res_at", "stocked", "tick", "want", "hold_take", "trained",
    "resource_index", "nearest_resource", "start_gather", "start_build", "approach_building", "clear_task", "in_reach", "unit_column", "building_column", "player_column",
    "unit_get", "unit_set", "building_get", "building_set", "player_get", "player_set", "rules", "player_count", "resource_count", "cell_of",
    "t_animal", "u_hp", "b_hp" ]

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

// The functions that change the sim: not while it's only being read (lua_task_name, for the panel).
let LA_WRITES = [ 15, 16, 17, 18, 19, 49, 57, 58, 59, 62, 63, 64, 65, 71, 73, 75 ]
var lua_read_only = false

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
                else: lx_r_int(hold_take(b, r, n))
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
        default: lua_fail("an unknown API function")

// ------------------------------------------------------------------ the hook points
// The Lua files of a pack: <its data>/hooks/*.lua, by name.
def lua_pack_files(p:Pack) -> [string]:
    let names, sizes = scan_folder(p.root + "/hooks", true)
    if not names or not sizes: return []
    let out = []::string
    for(names) n, k:
        if sizes[k] >= 0 and ends_with(n, ".lua"): out.push(n)
    return sorted_strs(out)

var lua_on = false  // a pack has Lua: the hooks below have something to call
var lua_rules = jobj()  // the rules the packs' Lua last loaded with: a new match or a loaded save loads it again

// As a match starts (the game's hook_declare): every pack's Lua runs, the game's first, and is then read-only.
def lua_declare():
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_on = false
    for(lib_packs) p:
        let files = lua_pack_files(p)
        if files.length:
            lua_on = true
            let sources = map(files) f:
                let text = read_file(p.root + "/hooks/" + f)
                if text: text else: ""
            lua_load_pack(p.id, map(files) f: p.id + "/hooks/" + f, sources)
    lua_freeze()

// The packs' Lua for this match: loaded again if the rules aren't the ones it loaded with (a save was loaded).
def lua_fresh() -> bool:
    if lua_rules != su_rules: lua_declare()
    return lua_on

// The packs that stopped, and why (a load error, a run-time error or the step budget).
def lua_errors() -> [string]:
    let out = []::string
    for(l_packs) pk:
        if pk.error != "": out.push("{pk.id}: {pk.error}")
    return out

def lua_tick():
    if not lua_fresh(): return
    lua_each("on_tick", []::int) r:
        pass()

def lua_unit_tick(i:int):
    if not lua_fresh(): return
    lua_each("on_unit_tick", [ lv_int(i) ]) r:
        pass()

def lua_can_place(p:int, k:int, cx:int, cy:int, sx:int, sy:int) -> bool:
    if not lua_fresh(): return true
    var ok = true
    let args = map([ p, k, cx, cy, sx, sy ]) v: lv_int(v)
    lua_each("can_place", args) r:
        if r.length and not lv_truthy(r[0]): ok = false
    return ok

def lua_on_hit(by:int, target:int, damage:int) -> int:
    if not lua_fresh(): return damage
    var d = damage
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "on_hit")
        if f != LV_NIL and lua_run(pk, f, [ lv_int(by), lv_int(target), lv_int(d) ], L_BUDGET_CALL):
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
            lua_run(pk, f, [ lv_int(code), lv_int(p), list, lv_int(x), lv_int(y) ], L_BUDGET_CALL)
    lua_region_end()

def lua_ai_train_score(p:int, slot:string, k:int, score:int) -> int:
    if not lua_fresh(): return score
    var s = score
    for(l_packs) pk:
        let f = lua_hook_fn(pk, "ai_train_score")
        if f != LV_NIL and lua_run(pk, f, [ lv_int(p), lv_str(slot), lv_int(k), lv_int(s) ], L_BUDGET_CALL):
            if rets.length and lv_is_int(rets[0]): s = rets[0] >> 3
    lua_region_end()
    return s

// What the panel says unit slot i is doing, when a pack made the task up ("" for the engine's own tasks). It only
// reads: the panel isn't the sim.
def lua_task_name(i:int) -> string:
    if not lua_fresh(): return ""
    var name = ""
    lua_read_only = true
    lua_each("task_name", [ lv_int(i) ]) r:
        if name == "" and r.length and (r[0] & 7) == LT_STR: name = lv_text(r[0])
    lua_read_only = false
    return name
