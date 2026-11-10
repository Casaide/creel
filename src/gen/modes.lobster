// ------------------------------------------------------------------ game modes' starts (src/sim/modes.gd, fortify.gd)
// The host's rules carry `mode`, an id in data/modes.json (none, or "standard": the usual match).
// Applied once at setup, after the usual start and before the animals and the match's bookkeeping,
// as World.setup does. Fortress: every side the same start (walls, garrison, age, stock). Siege:
// player 0's team defends (`defend`), everyone else attacks (`attack`); its win rules are the sim's
// (lib/match.lobster, mode_hold).

let FORT_SIDES = [ "n", "e", "s", "w" ]

def setup_mode():
    let id = gstr(su_rules, "mode", "")
    if id == "" or id == "standard": return
    let modes = at(lib_data("modes.json"), "modes")
    assert has(modes, id)
    let m = at(modes, id)
    let lift = gstrs(m, "lift_lacks")
    if lift.length:  // every side can build and repair what the mode lists, whatever its race lacks
        su_sides = map(su_sides) ident:
            let own = deep_copy(ident)
            set(own, "lacks", jarr(filter(glist(own, "lacks")) x: not (x.kind == J_STR and has_s(lift, x.s))))
            own
        for(lift) lifted:
            let k = btype_index(lifted)
            if k >= 0:
                for(num_players) p: bm_lacks[p][k] = 0
    mode_hold = if has(m, "defend"): gint(m, "hold_minutes", 0) * 1200 else: -1
    for(num_players) p:
        if p < start_x.length:
            mode_start(p, if not has(m, "defend"): m elif teams[p] == teams[0]: at(m, "defend") else: at(m, "attack"))

def mode_start(p:int, s:JV):
    let cx = start_x[p] / TILE
    let cy = start_y[p] / TILE
    if gint(s, "age", 0) > ages[p]:
        ages[p] = gint(s, "age", 0)
        retype(p)
        tech_refresh(p)
    let st = gobj(s, "stock")
    for(st.keys) r, n:
        let k = str_index(resource_names, r)
        if k >= 0: stock[k][p] = as_int(st.a[n])
    if not gbool(s, "town", true): no_town(p)
    if has(s, "walls"):
        let wl = at(s, "walls")
        fortify_ring(p, cx, cy, as_int(at(wl, "radius")), wl)
    var tc = -1
    for(b_id.length) b:
        if tc < 0 and b_owner[b] == p and has_role(b_kind[b], ROLE_HUB): tc = b
    let worker = type_of_slot(p, "worker")
    for(gint(s, "workers", 0)):
        if tc >= 0:
            let cell = spawn_cell(tc, worker)
            add_unit(p, worker, (cell % W) * TILE + 500, (cell / W) * TILE + 500)
        else: mode_put(p, worker, start_x[p], start_y[p])
    let fx, fy = enemy_start(p)
    let posts = wall_posts(p, fx, fy)
    var k = 0
    let gar = gobj(s, "garrison")
    for(sorted_strs(gar.keys)) slot:
        let t = type_of_slot(p, slot)
        if t >= 0:
            for(as_int(at(gar, slot))):
                let i = mode_put(p, t, start_x[p], start_y[p])
                if k < posts.length and can_climb(i):
                    off_wall_fields(i)
                    u_perch[i] = posts[k] + 1
                    let px, py = cell_centre(posts[k])
                    u_x[i] = px
                    u_y[i] = py
                    u_moving[i] = 0
                    k++
    let army = gobj(s, "army")
    for(sorted_strs(army.keys)) slot:
        let t = type_of_slot(p, slot)
        if t >= 0:
            for(as_int(at(army, slot))): mode_put(p, t, start_x[p], start_y[p])
    update_pop()

// The side's Town Center and starting workers go: it starts with what the mode gives it.
def no_town(p:int):
    var b = b_id.length - 1
    while b >= 0:
        if b_owner[b] == p: demolish(b)
        b--
    var i = u_id.length - 1
    while i >= 0:
        if u_owner[i] == p: remove_unit(i)
        i--

// A unit of type k for p near (x0, y0): jittered like a SPAWN, on open ground in its lane.
def mode_put(p:int, k:int, x0:int, y0:int) -> int:
    var x = x0 + range_int(su_rng, -2500, 2500)
    var y = y0 + range_int(su_rng, -2500, 2500)
    let ln = lane_base[p] + t_mclass[k]
    if not walkable(x, y, ln):
        let cx, cy = centre(nearest_walkable(cell_of(x, y), ln))
        x = cx
        y = cy
    return add_unit(p, k, x, y)

// The nearest enemy start to p's (milli-tiles), or p's own if it has none.
def enemy_start(p:int) -> int, int:
    var bx = start_x[p]
    var by = start_y[p]
    var best = 1 << 62
    for(num_players) q:
        if q < start_x.length and is_enemy(p, q):
            let d = dist2(start_x[p], start_y[p], start_x[q], start_y[q])
            if d < best:
                best = d
                bx = start_x[q]
                by = start_y[q]
    return bx, by

// p's walkway cells, nearest (tx, ty) first, a place each as many as the cell holds: where its
// garrison stands at the start.
def wall_posts(p:int, tx:int, ty:int) -> [int]:
    let cells = []::int
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] == 1 and bt_walkway[b_kind[b]] > 0:
            for(footprint(b)) c: cells.push(c)
    def d(c:int) -> int: return dist2((c % W) * TILE + 500, (c / W) * TILE + 500, tx, ty)
    insertion_sort(cells) a, b: d(a) < d(b) or (d(a) == d(b) and a < b)
    let out = []::int
    for(cells) c:
        for(places(c)): out.push(c)
    return out

// Fortify.ring: a finished square ring for p round cell (cx, cy), r tiles out, with a gate in the
// middle of the sides asked for and towers on the corners and every few tiles; cells that can't be
// built on are left out (the ring follows the land).
def fortify_ring(p:int, cx:int, cy:int, r:int, spec:JV):
    let wk = btype_index(gstr(spec, "wall", ""))
    assert wk >= 0
    let gk = if gstr(spec, "gate", "") != "": btype_index(gstr(spec, "gate", "")) else: -1
    let tk = if gstr(spec, "tower", "") != "": btype_index(gstr(spec, "tower", "")) else: -1
    let every = gint(spec, "tower_every", 0)
    let gates = if gk >= 0: gstrs(spec, "gates") else: []::string
    let lox = cx - r
    let loy = cy - r
    let hix = cx + r
    let hiy = cy + r
    let gate_at = []::int  // the gates' cells, and each one's gate (top-left x, y, along), in the order made
    let gate_of = []::int3
    for(gates) s:
        assert has_s(FORT_SIDES, s)
        let g = if s == "n": int3 { cx - 1, loy, 0 } elif s == "s": int3 { cx - 1, hiy, 0 } elif s == "w": int3 { lox, cy - 1, 1 } else: int3 { hix, cy - 1, 1 }
        for(3) k:
            gate_at.push((g.y + (if g.z == 1: k else: 0)) * W + g.x + (if g.z == 0: k else: 0))
            gate_of.push(g)
    var y = loy
    while y <= hiy:
        var x = lox
        while x <= hix:
            if (x == lox or x == hix or y == loy or y == hiy) and x >= 0 and y >= 0 and x < W and y < H:
                let c = y * W + x
                if not contains(gate_at, c) and can_build(x, y, 1, 0, false, false):
                    let corner = (x == lox or x == hix) and (y == loy or y == hiy)
                    let along = if y == loy or y == hiy: x - lox else: y - loy
                    let tower = tk >= 0 and (corner or (every > 0 and along % every == 0))
                    fort_put(p, if tower: tk else: wk, x, y, 0)
            x++
        y++
    let done = []::int
    for(gate_at.length) n:
        let g = gate_of[n]
        let key = g.y * W + g.x
        if not contains(done, key):
            done.push(key)
            let sx, sy = dims(gk, g.z)
            var ok = true
            for(cells_of(g.x, g.y, sx, sy, 0)) fc:
                if not can_build(fc % W, fc / W, 1, 0, false, false): ok = false
            if ok: fort_put(p, gk, g.x, g.y, g.z)

def fort_put(p:int, k:int, x:int, y:int, along:int):
    let b = place(p, k, x, y, along)
    b_done[b] = 1
    b_progress[b] = bt_build_ticks[k]
    b_hp[b] = bm_hp[p][k]
