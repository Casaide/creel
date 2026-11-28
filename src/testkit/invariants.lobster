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
var inv_stuck_limit = 0   // "stuck": a walker held up this many ticks is a break (0: not checked; the rules' invariants.stuck_limit, or the MCP's)

// The rules' "invariants": {"stuck_limit": ticks} (a pack's rules file sets it: how long a walker may be held up), 0 if unset.
def rules_stuck_limit() -> int: return gint(gobj(su_rules, "invariants"), "stuck_limit", 0)

var inv_px = []::int      // inv_before: each unit's place, by slot, and its id
var inv_py = []::int
var inv_pid = []::int
var inv_pin = []::int     // and 1 if it was inside then

// The engine's invariants by name, in the order they're checked.
let INV_NAMES = [ "columns", "ids", "on_map", "carry", "stock", "holds", "jobs", "solid", "stuck", "pack" ]

def inv_before():
    inv_px = copy(u_x)
    inv_py = copy(u_y)
    inv_pid = copy(u_id)
    let hc = inside_col()
    inv_pin = map(u_id.length) i: if is_inside(i, hc): 1 else: 0

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

// A building holds, wants, has on its way and keeps for carriers never below nothing. (What it keeps for carriers may
// be more than it holds: a cost paid from a store can take goods kept for a carrier, who then takes what's left.)
def inv_holds() -> string:
    for(b_id) bid, b:
        for([ b_hold[b], b_want[b], b_resv[b], b_coming[b], b_site[b] ]) xs, k:
            for(xs) n, r:
                if n < 0: return "building {bid}\'s {[ "hold", "want", "resv", "coming", "site" ][k]} of resource {r} is {n}"
    return ""

// A carrier's job always has its carrier, and what it moves is more than nothing.
def inv_jobs() -> string:
    for(jb_id) jid, j:
        if index_of(jb_unit[j]) < 0: return "job {jid} has no carrier (unit {jb_unit[j]} is gone)"
        if jb_n[j] <= 0: return "job {jid} moves {jb_n[j]}"
    return ""

// Solid bodies (rules economy "solid_bodies"): nobody goes further into another's body. Two whose bodies overlap at the
// tick's end are no nearer than at its start (they may part, or stand as they were: one just out of a door is eased
// clear), except the forced swap of two walkers held up by each other long. One that came out of a building or is new
// this tick has no start to compare. Two walkers each stepping in slot order, by whole milli-tiles, can graze by a few
// thousandths of a tile; deeper than INV_GRAZE is a break.
let INV_GRAZE = 10

def inv_solid() -> string:
    if r_solid == 0: return ""
    let hc = inside_col()
    let head = map(W * H): -1  // (the units by cell, as linked lists: its own, so a check only reads)
    let next = map(u_id.length): -1
    for(u_id.length) i:
        let c = clamp(u_y[i] / TILE, 0, H - 1) * W + clamp(u_x[i] / TILE, 0, W - 1)
        next[i] = head[c]
        head[c] = i
    var span = 1  // (cells to look across: two of the widest bodies)
    for(u_radius) r: span = max(span, 2 * r / TILE + 1)
    let side = 2 * span + 1
    for(u_id) uid, i:
        let k = int_find(inv_pid, uid)
        if k >= 0 and inv_pin[k] == 0 and solid_body(i, hc):
            let cx = clamp(u_x[i] / TILE, 0, W - 1)
            let cy = clamp(u_y[i] / TILE, 0, H - 1)
            for(side * side) n:
                let nx = cx + n % side - span
                let ny = cy + n / side - span
                if nx >= 0 and ny >= 0 and nx < W and ny < H:
                    var j = head[ny * W + nx]
                    while j >= 0:
                        let vid = u_id[j]
                        if vid > uid and solid_body(j, hc):
                            let m = int_find(inv_pid, vid)
                            let rr = u_radius[i] + u_radius[j]
                            let d2 = dist2(u_x[i], u_y[i], u_x[j], u_y[j])
                            if m >= 0 and inv_pin[m] == 0 and d2 < rr * rr:
                                let was2 = dist2(inv_px[k], inv_py[k], inv_px[m], inv_py[m])
                                let swap = u_stuck[i] >= STUCK_LIMIT / 2 and u_stuck[j] >= STUCK_LIMIT / 2 and u_moving[i] != 0 and u_moving[j] != 0
                                let deep = rr - isqrt(d2)
                                if d2 < was2 and deep > INV_GRAZE and not swap:
                                    return "units {uid} (task {u_task[i]}) and {vid} (task {u_task[j]}) went further into each other at {u_x[i]}, {u_y[i]}: {isqrt(was2)} apart, now {isqrt(d2)}, bodies {rr}"
                        j = next[j]
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
