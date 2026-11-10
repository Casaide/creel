// ------------------------------------------------------------------ animals and pens (animals.gd, pens.gd)
// Deer to hunt (they bolt when hurt), boar (they turn on whoever hurts them) and sheep to herd (the
// first player whose unit comes close owns them; a claimed one walks into its owner's pen with room,
// else to a spot by their Town Center). Nobody owns them at first: gaia, one past the last player,
// on a team of its own. A dead animal leaves a carcass, food, and its hunters gather it. A finished
// pen is walked into; its owner's sheep standing inside feed the owner now and then, and breed.

let CLAIM_EVERY = 10
let PEN_GAP = 850
let HERD_PEN = 3
let PEN_FENCE = 150  // a pen's fence inside its footprint's edge, and a little air (the walk grids can't see it)

def is_animal(i:int) -> bool: return t_animal[u_kind[i]] != 0
def is_herd(i:int) -> bool: return t_behave[u_kind[i]] == B_HERD

// ---- the map's part (SimMap.set_walk_over, set_terrain)

def set_walk_over(cells:[int], on:bool):
    for(cells) c:
        walk_over[c] = if on: 1 else: 0
        refresh(c)

def set_terrain(cell:int, k:int):
    set_cell_terrain(cell, k)
    amount[cell] = tr_amount[k]
    if amount[cell] > 0:
        let found, at = binary_search(resource_cells, cell)
        if not found: resource_cells.insert(at, cell)
    refresh(cell)

// ---- pens

def is_pen(b:int) -> bool: return bt_pen_animals[b_kind[b]] > 0

// The first pen type (buildings.json "pen"), or -1.
def pen_type() -> int: return find(bt_pen_animals): _ > 0

def pen_opened(b:int): set_walk_over(footprint(b), true)

def pen_gone(b:int):
    if is_pen(b) and b_done[b] == 1: set_walk_over(footprint(b), false)

def in_rect(b:int, x:int, y:int) -> bool:
    return x >= b_cx[b] * TILE and y >= b_cy[b] * TILE and x < (b_cx[b] + b_sx[b]) * TILE and y < (b_cy[b] + b_sy[b]) * TILE

def pen_at(i:int) -> int:
    for(b_id.length) b:
        if b_owner[b] == u_owner[i] and b_done[b] == 1 and is_pen(b) and in_rect(b, u_x[i], u_y[i]): return b
    return -1

def pen_animals(b:int, standing_only:bool) -> [int]:
    let out = []::int
    for(u_x.length) i:
        if u_owner[i] == b_owner[b] and is_herd(i):
            let there = in_rect(b, u_x[i], u_y[i]) and u_moving[i] == 0
            if there or (not standing_only and u_moving[i] == 1 and in_rect(b, u_tx[i], u_ty[i])): out.push(i)
    return out

def pen_room(b:int) -> bool: return b_done[b] == 1 and pen_animals(b, false).length < bt_pen_animals[b_kind[b]]

def nearest_pen_with_room(p:int, x:int, y:int) -> int:
    var best = -1
    var best_d = 1 << 62
    for(b_id.length) b:
        if b_owner[b] == p and is_pen(b) and pen_room(b):
            let cx, cy = b_centre(b)
            let d = abs(cx - x) + abs(cy - y)
            if d < best_d:
                best_d = d
                best = b
    return best

// (x, y) kept inside pen b's fence by herd animal i's radius.
def pen_inside(b:int, i:int, x:int, y:int) -> int, int:
    let m = u_radius[i] + PEN_FENCE
    return clamp(x, b_cx[b] * TILE + m, (b_cx[b] + b_sx[b]) * TILE - m), clamp(y, b_cy[b] * TILE + m, (b_cy[b] + b_sy[b]) * TILE - m)

// The pen herd animal i stands in, or heads for a place in, while it's there: its fence holds it
// (separate's correction), or -1. One walking out of it (released) isn't held.
def pen_holding(i:int) -> int:
    if not is_herd(i) or u_owner[i] == gaia: return -1
    let b = pen_at(i)
    if b < 0 or (u_moving[i] == 1 and not in_rect(b, u_tx[i], u_ty[i])): return -1
    return b

// Where herd animal i stands round `at`: the first of a 3 x 3 grid of places (then round again,
// offset) no other herd animal of its owner is heading for or standing at. In pen b, kept inside its fence.
def herd_slot(ax:int, ay:int, i:int, pen:int = -1) -> int, int:
    let taken = dictionary<int, int>(64)
    for(u_x.length) j:
        if j != i and u_owner[j] == u_owner[i] and is_herd(j): taken.set(u_tx[j] * 1000003 + u_ty[j], 1)
    var fx = -1
    var fy = -1
    for(18) n:
        let k = n % 9
        var px = ax + (k % 3 - 1) * PEN_GAP + (n / 9) * PEN_GAP / 2
        var py = ay + (k / 3 - 1) * PEN_GAP + (n / 9) * PEN_GAP / 2
        if pen >= 0: px, py = pen_inside(pen, i, px, py)
        if fx < 0:
            fx = px
            fy = py
        if taken.get(px * 1000003 + py, 0) == 0: return px, py
    return fx, fy

def pen_send(i:int, b:int):
    u_orders[i] = []::Cmd
    let cx, cy = b_centre(b)
    let px, py = herd_slot(cx, cy, i, b)
    order_move(i, px, py, 200, 0, -1, -1, 0)

def cmd_pen(p:int, ids:[int], bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p or not is_pen(b): return
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and is_herd(i) and pen_room(b) and not (in_rect(b, u_x[i], u_y[i]) and u_moving[i] == 0):
            pen_send(i, b)

def cmd_release(p:int, bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p or not is_pen(b): return
    let cx, cy = b_centre(b)
    let oy = cy + (b_sy[b] / 2 + 2) * TILE
    for(pen_animals(b, false)) i:
        u_orders[i] = []::Cmd
        let px, py = herd_slot(cx, oy, i)
        order_move(i, px, py, 200, 0, -1, -1, 0)

def pens_tick():
    let food = 0
    for(b_id.length) b:
        if b_done[b] == 1 and is_pen(b):
            let k = b_kind[b]
            let feed = tick % bt_pen_food_ticks[k] == 0
            let breed = tick % bt_pen_breed_ticks[k] == 0
            if feed or breed:
                let herd = pen_animals(b, true)
                let n = min(herd.length, bt_pen_animals[k])
                if feed and n > 0:
                    stock[food][b_owner[b]] += n * bt_pen_food[k]
                    gathered[food][b_owner[b]] += n * bt_pen_food[k]
                if breed and n >= 2 and pen_animals(b, false).length < bt_pen_animals[k]:
                    let parent = herd[0]
                    let cx, cy = b_centre(b)
                    let s = add_unit(u_owner[parent], u_kind[parent], cx, cy)
                    u_posture[s] = 0  // (Units.add: a newborn's posture is the arrays' default)
                    let px, py = herd_slot(cx, cy, s, b)
                    order_move(s, px, py, 200, 0, -1, -1, 0)

// ---- claiming, hurting, dying

def nearest_town_center(i:int) -> int:
    var best = -1
    var best_d = 1 << 62
    for(b_id.length) b:
        if b_owner[b] == u_owner[i] and b_done[b] == 1 and has_role(b_kind[b], ROLE_HUB):
            let bx, by = b_centre(b)
            let d = abs(bx - u_x[i]) + abs(by - u_y[i])
            if d < best_d:
                best_d = d
                best = b
    return best

let HERD_DIRS = [ int2 { 1, 1 }, int2 { 1, 0 }, int2 { 0, 1 }, int2 { -1, 1 }, int2 { 1, -1 }, int2 { -1, 0 }, int2 { 0, -1 }, int2 { -1, -1 } ]

def herd_spot(b:int) -> [int]:
    let id = b_id[b]
    let had = herd_spots.get(id)
    if had: return had
    let tx = b_cx[b] + b_sx[b] / 2
    let ty = b_cy[b] + b_sy[b] / 2
    let off = b_sx[b] / 2 + 2 + HERD_PEN / 2
    let mx = W / 2
    let my = H / 2
    var best = []::int
    var best_score = -1
    for(HERD_DIRS) d:
        let px = tx + d.x * off
        let py = ty + d.y * off
        var open = 0
        for(HERD_PEN) dy0:
            for(HERD_PEN) dx0:
                let x = px + dx0 - HERD_PEN / 2
                let y = py + dy0 - HERD_PEN / 2
                if x >= 0 and y >= 0 and x < W and y < H:
                    let c = y * W + x
                    if walks[0][c] == 1 and occupied[c] == 0 and amount[c] == 0: open++
        let away = abs(px - mx) + abs(py - my)
        let score = open * 10000 + away
        if score > best_score:
            best_score = score
            best = [ px * TILE + TILE / 2, py * TILE + TILE / 2 ]
    herd_spots.set(id, best)
    return best

def claim(i:int, p:int):
    u_owner[i] = p
    u_foe[i] = 0
    u_stance[i] = 0
    u_patient[i] = 0
    clear_task(i)
    u_orders[i] = []::Cmd
    u_moving[i] = 0
    for(u_x.length) j:
        if u_foe[j] == u_id[i] and u_owner[j] == p: return
    let pen = nearest_pen_with_room(p, u_x[i], u_y[i])
    if pen >= 0:
        pen_send(i, pen)
        return
    let b = nearest_town_center(i)
    if b < 0: return
    let spot = herd_spot(b)
    let px, py = herd_slot(spot[0], spot[1], i)
    order_move(i, px, py, 200, 0, -1, -1, 0)

def animals_tick():
    pens_tick()
    if tick % CLAIM_EVERY != 0: return
    let reach = claim_tiles * TILE
    for(u_x.length) i:
        if is_herd(i):
            let owner = u_owner[i]
            var best = -1
            var best_d = reach * reach + 1
            var guarded = false
            let pen = if owner != gaia: pen_at(i) else: -1
            for(u_x.length) j:
                let o = u_owner[j]
                if not guarded and o != gaia and not is_animal(j) and not (pen >= 0 and o != owner and not in_rect(pen, u_x[j], u_y[j])):
                    let dx = u_x[j] - u_x[i]
                    let dy = u_y[j] - u_y[i]
                    let d = dx * dx + dy * dy
                    if d <= reach * reach:
                        if o == owner: guarded = true
                        elif d < best_d or (d == best_d and o < best):
                            best_d = d
                            best = o
            if best >= 0 and not guarded: claim(i, best)

// Hurt this tick by `by`: a deer bolts away from it; a sheep stands still.
def animal_hurt(i:int, by:int):
    let k = u_kind[i]
    if t_behave[k] == B_HERD:
        u_moving[i] = 0
        u_orders[i] = []::Cmd
        return
    if t_behave[k] != B_FLEE: return
    let a = index_of(by)
    if a < 0: return
    let dx = u_x[i] - u_x[a]
    let dy = u_y[i] - u_y[a]
    let len = max(1, abs(dx) + abs(dy))
    order_move(i, u_x[i] + dx * t_flee[k] / len, u_y[i] + dy * t_flee[k] / len, 300, 0, -1, -1, 0)

def tr_index(name:string) -> int:
    for(tr_names) n, k:
        if n == name: return k
    return -1
