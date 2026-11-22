// ------------------------------------------------------------------ per-tick invariants (#186)
// Named, read-only checks over the whole sim state, run after a tick. The engine's hold for every game on Creel; a pack
// adds its own in Lua (a global `invariants()` that returns nil while its rules hold, or a string saying which broke and
// where), on the view's small budget, and can't turn the engine's off. The first that breaks is the run's answer: its
// tick, its name and the unit or building.
//
//   inv_before()           before a tick (what the checks compare against: where everyone was)
//   inv_after() -> string  after it: "" while every invariant holds, else "<name>: <what, which id>"
//
// The testkit runs them every tick when asked (kit's `invariants` arg, inv_on), and so can the MCP (creel_step's
// invariants). They only read: nothing here writes the sim's state. Imported after every sim module and Lua's.

var inv_on = false        // the testkit checks every tick (wstep)
var inv_broken = ""       // the first that broke, with its tick: "" while none has
var inv_ticks = 0         // the ticks checked
var inv_stuck_limit = 0   // "stuck": a walker held up this many ticks is a break (0: not checked; a pack's rules set it)

var inv_px = []::int      // inv_before: each unit's place, by slot, and its id
var inv_py = []::int
var inv_pid = []::int

// The engine's invariants by name, in the order they're checked.
let INV_NAMES = [ "columns", "ids", "on_map", "carry", "stock", "holds", "jobs", "solid", "stuck", "pack" ]

def inv_before():
    inv_px = copy(u_x)
    inv_py = copy(u_y)
    inv_pid = copy(u_id)

def inv_sorted(xs:[int]) -> int:  // (the slot of the first id out of order, or -1: index_of's binary search needs them rising)
    for(xs.length - 1) k:
        if xs[k] >= xs[k + 1]: return k + 1
    return -1

// Every unit's and building's columns the same length.
def inv_columns() -> string:
    let n = u_id.length
    for(unit_columns()) col, k:
        if col.length != n: return "unit column {k} has {col.length} rows, u_id {n}"
    if u_orders.length != n or u_mount.length != n or u_inside.length != n: return "a unit\'s lists are {u_orders.length}, {u_mount.length}, {u_inside.length} rows, u_id {n}"
    let m = b_id.length
    for(building_columns()) col, k:
        if col.length != m: return "building column {k} has {col.length} rows, b_id {m}"
    if b_make.length != m: return "b_make has {b_make.length} rows, b_id {m}"
    for([ b_queue, b_inside, b_hold, b_want, b_resv, b_coming, b_site ]) col, k:
        if col.length != m: return "building list {k} has {col.length} rows, b_id {m}"
    let jn = jb_id.length
    for([ jb_unit, jb_from, jb_to, jb_res, jb_n, jb_phase, jb_want ]) col, k:
        if col.length != jn: return "job column {k} has {col.length} rows, jb_id {jn}"
    return ""

// Ids rising (looked up by binary search) and so never twice.
def inv_ids() -> string:
    let i = inv_sorted(u_id)
    if i >= 0: return "unit {u_id[i]} out of order after {u_id[i - 1]}"
    let b = inv_sorted(b_id)
    if b >= 0: return "building {b_id[b]} out of order after {b_id[b - 1]}"
    let j = inv_sorted(jb_id)
    if j >= 0: return "job {jb_id[j]} out of order after {jb_id[j - 1]}"
    return ""

def inv_on_map() -> string:
    for(u_id) uid, i:
        if u_x[i] < 0 or u_y[i] < 0 or u_x[i] >= W * TILE or u_y[i] >= H * TILE: return "unit {uid} at {u_x[i]}, {u_y[i]}, off a {W} x {H} map"
    for(b_id) bid, b:
        if b_cx[b] < 0 or b_cy[b] < 0 or b_cx[b] + b_sx[b] > W or b_cy[b] + b_sy[b] > H: return "building {bid} at {b_cx[b]}, {b_cy[b]}, off the map"
    return ""

// What a unit carries: never below nothing, and always of a resource.
def inv_carry() -> string:
    for(u_id) uid, i:
        if u_carry[i] < 0: return "unit {uid} carries {u_carry[i]}"
        if u_carry_kind[i] < 0 or u_carry_kind[i] > resource_names.length: return "unit {uid} carries resource {u_carry_kind[i] - 1}"
        if u_carry[i] > 0 and u_carry_kind[i] == 0: return "unit {uid} carries {u_carry[i]} of nothing"
    return ""

def inv_stock() -> string:
    for(stock) per, r:
        for(per) n, p:
            if n < 0: return "player {p} has {n} {if r < resource_names.length: resource_names[r] else: string(r)}"
    return ""

// A building holds, wants, has on its way and keeps for carriers never below nothing; kept for carriers, never above what it holds.
def inv_holds() -> string:
    for(b_id) bid, b:
        for([ b_hold[b], b_want[b], b_resv[b], b_coming[b], b_site[b] ]) xs, k:
            for(xs) n, r:
                if n < 0: return "building {bid}\'s {[ "hold", "want", "resv", "coming", "site" ][k]} of resource {r} is {n}"
        for(b_resv[b]) n, r:
            if n > (if r < b_hold[b].length: b_hold[b][r] else: 0): return "building {bid} keeps {n} of resource {r} for carriers, more than it holds"
    return ""

// A carrier's job always has its carrier, and what it moves is more than nothing.
def inv_jobs() -> string:
    for(jb_id) jid, j:
        if index_of(jb_unit[j]) < 0: return "job {jid} has no carrier (unit {jb_unit[j]} is gone)"
        if jb_n[j] <= 0: return "job {jid} moves {jb_n[j]}"
    return ""

// Solid bodies (rules economy "solid_bodies"): nobody stepped into another's body this tick, as movement allows it
// (a step that ends no further from them than it started, the forced swap of two held up long excepted).
def inv_solid() -> string:
    if r_solid == 0: return ""
    let hc = inside_col()
    for(u_id) uid, i:
        let k = int_find(inv_pid, uid)
        if k >= 0 and (u_x[i] != inv_px[k] or u_y[i] != inv_py[k]) and solid_body(i, hc):
            let j = pressed(i, u_x[i], u_y[i], inv_px[k], inv_py[k], hc)
            if j >= 0 and not (u_stuck[i] >= STUCK_LIMIT / 2 and u_moving[j] != 0 and u_stuck[j] >= STUCK_LIMIT / 2):
                return "unit {uid} stepped into unit {u_id[j]} at {u_x[i]}, {u_y[i]}"
    return ""

def int_find(xs:[int], v:int) -> int:  // (xs rising)
    let found, at = binary_search(xs, v)
    return if found: at else: -1

def inv_stuck() -> string:
    if inv_stuck_limit <= 0: return ""
    for(u_id) uid, i:
        if u_moving[i] != 0 and u_stuck[i] > inv_stuck_limit: return "unit {uid} held up {u_stuck[i]} ticks at {u_x[i]}, {u_y[i]}"
    return ""

// The packs' own: each pack's `invariants()`, asked as the view asks (read-only, its small budget).
def inv_pack() -> string:
    if not lua_fresh(): return ""
    let view0 = hook_view
    hook_view = true
    var why = ""
    for(l_packs) pk: pk.view_error = ""  // (the view's own note of a failure, not the sim's: so this call's shows)
    lua_each("invariants", []) r:
        if why == "" and r.length and (r[0] & 7) == LT_STR: why = lv_text(r[0])
    hook_view = view0
    for(l_packs) pk:
        if why == "" and pk.view_error != "": why = "{pk.id}\'s invariants failed: {pk.view_error}"
    return why

def inv_check(name:string) -> string:
    switch name:
        case "columns": return inv_columns()
        case "ids": return inv_ids()
        case "on_map": return inv_on_map()
        case "carry": return inv_carry()
        case "stock": return inv_stock()
        case "holds": return inv_holds()
        case "jobs": return inv_jobs()
        case "solid": return inv_solid()
        case "stuck": return inv_stuck()
        case "pack": return inv_pack()
        default: return "no invariant {name}"

// After a tick: the first broken, "<name>: <what>", or "". (Columns first: the rest index by slot.)
def inv_after() -> string:
    inv_ticks++
    for(INV_NAMES) name:
        let why = inv_check(name)
        if why != "": return name + ": " + why
    return ""
