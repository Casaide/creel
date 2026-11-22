// ------------------------------------------------------------------ movement (world.gd)

// Unit i's next waypoint from (x, y) (World._plan). Point moves aim at the target if the way is
// clear; reach moves aim at a free spot round their rect once beside it; otherwise the furthest
// clear cell a few steps down the flow field. (-1, -1): unreachable. (-2, -2): outside a near
// field's cutoff. (-3, -3): every spot round its rect has a worker at work in it.
// `stuck` is its stuck count as GDScript reads it (units.stuck: live during the tick's moves).
def plan(i:int, x:int, y:int, stuck:int) -> int, int:
    let tx = u_tx[i]
    let ty = u_ty[i]
    if u_fkey[i] < 0: return tx, ty
    let f = field_for(u_fkey[i])
    if not f: return tx, ty
    let cell = cell_of(x, y)
    let cost = f.dist[cell]
    // (how near it is, in a field's cost: a road's tiles cost less to cross than they are long, so near by cost isn't near, #129)
    let gx = if u_reach[i] == 1: clamp(x, u_rx0[i], u_rx1[i]) else: tx
    let gy = if u_reach[i] == 1: clamp(y, u_ry0[i], u_ry1[i]) else: ty
    let near = if road.length and cost < INF: max(cost, isqrt(dist2(x, y, gx, gy)) * STRAIGHT / TILE) else: cost
    if cost >= INF:
        let kind = (u_fkey[i] / LANES) % 4
        if kind == FIELD_CELL_NEAR or kind == FIELD_BUILDING_NEAR: return -2, -2
        return -1, -1
    if u_reach[i] == 1:
        if near <= 2 * DIAGONAL:  // within two cells: make for a free spot before meeting the crowd
            let sx, sy = if u_task[i] == T_RETURN and u_gspot[i] >= 0: drop_spot(i, x, y) else: spot(i, x, y)
            // (with roads, the spot only once the way to it is clear: a road round a field to a door, not across it, #129)
            if not road.length or sx < 0 or clear_path(x, y, sx, sy, u_radius[i], lane(i)): return sx, sy
    elif cost == 0 or (near <= DIRECT_COST and not on_middle(cell) and (not road.length or isqrt(dist2(x, y, tx, ty)) * STRAIGHT / TILE <= cost + STRAIGHT) and stuck < STUCK_LIMIT / 2 and clear_path(x, y, tx, ty, u_radius[i], lane(i))):
        return tx, ty
    elif u_reach[i] == 2 and near <= 4 * STRAIGHT:
        let cx, cy = round_corner(i, x, y, tx, ty)  // its place is round the far side of the building
        if cx >= 0: return cx, cy
    var best = ahead(f, cell, x, y, if stuck >= STUCK_LIMIT / 2: 1 else: LOOKAHEAD, u_radius[i], lane(i))
    if best < 0:
        if u_reach[i] == 0: return tx, ty
        best = -2 - best
    return centre(best)

// The nearest free spot round unit i's rect (a body's width from it, clear of every stopped unit
// there); the same spot while it stays free; one only an idle body stands in after free ones.
// (-3, -3) when every spot has a worker at work in it (World._spot).
def spot(i:int, x:int, y:int) -> int, int:
    let r = u_radius[i]
    let ln = lane(i)
    let x0 = u_rx0[i]
    let y0 = u_ry0[i]
    let x1 = u_rx1[i] + 1
    let y1 = u_ry1[i] + 1
    let o = r + SPOT_GAP
    let near = []::int
    var cy = max((y0 - o) / TILE - 1, 0)
    while cy < min((y1 + o) / TILE + 2, H):
        var cx = max((x0 - o) / TILE - 1, 0)
        while cx < min((x1 + o) / TILE + 2, W):
            let c = cy * W + cx
            var k = sp_start[c]
            while k < sp_end[c]:
                let j = sp_items[k]
                k++
                if j != i and j < u_x.length and u_moving[j] == 0 and not (j < s_inside.length and s_inside[j] != 0): near.push(j)  // (one inside the building takes no room by it, #133)
            cx++
        cy++
    let space = 2 * r + SPOT_GAP / 2
    let wd = x1 - x0 + 2 * o
    let ht = y1 - y0 + 2 * o
    let perim = 2 * (wd + ht)
    let count = max(perim / space, 4)
    var bx = -1
    var by = -1
    var best_d = 1 << 62
    let rr0 = r + REACH - SPOT_GAP / 2
    for(count) k:
        let along = k * perim / count
        var px = 0
        var py = 0
        if along < wd:
            px = x0 - o + along
            py = y0 - o
        elif along < wd + ht:
            px = x1 + o
            py = y0 - o + along - wd
        elif along < 2 * wd + ht:
            px = x1 + o - (along - wd - ht)
            py = y1 + o
        else:
            px = x0 - o
            py = y1 + o - (along - 2 * wd - ht)
        let ex = max(max(x0 - px, 0), px - x1)
        let ey = max(max(y0 - py, 0), py - y1)
        if ex * ex + ey * ey > rr0 * rr0 or not walkable(px, py, ln): continue
        px, py = off_walls(px, py, r, ln)
        var lv = 0
        for(near) j:
            let rr = r + u_radius[j] - SPOT_GAP / 2
            if dist2(px, py, u_x[j], u_y[j]) < rr * rr:
                if u_task[j] == GATHER or u_task[j] == BUILD:
                    lv = 2
                    break
                lv = 1
        if lv == 2: continue
        var d = dist2(x, y, px, py) + lv * (1 << 40)
        if px == u_wx[i] and py == u_wy[i]: d -= 1 << 39
        if d < best_d:
            best_d = d
            bx = px
            by = py
    if bx < 0: return -3, -3
    if clear_path(x, y, bx, by, r, ln): return bx, by
    return rect_near(i, x, y)

// Where a worker carrying home makes for round its drop-off: the point of the ring a body's width
// out nearest what it gathers, moved round the ring by a lane of its own (World._drop_spot).
def drop_spot(i:int, x:int, y:int) -> int, int:
    let r = u_radius[i]
    let o = r + SPOT_GAP
    let x0 = u_rx0[i] - o
    let y0 = u_ry0[i] - o
    let x1 = u_rx1[i] + o
    let y1 = u_ry1[i] + o
    var ax = x
    var ay = y
    if u_home[i] >= 0:
        ax = (u_home[i] % W) * TILE + TILE / 2
        ay = (u_home[i] / W) * TILE + TILE / 2
    var px = clamp(ax, x0, x1)
    var py = clamp(ay, y0, y1)
    if px > x0 and px < x1 and py > y0 and py < y1:
        let d = min(min(px - x0, x1 - px), min(py - y0, y1 - py))
        if d == px - x0: px = x0
        elif d == x1 - px: px = x1
        elif d == py - y0: py = y0
        else: py = y1
    let wd = x1 - x0
    let ht = y1 - y0
    let perim = 2 * (wd + ht)
    var along = 0
    if py == y0: along = px - x0
    elif px == x1: along = wd + py - y0
    elif py == y1: along = wd + ht + x1 - px
    else: along = 2 * wd + ht + y1 - py
    along = along + (u_id[i] * 7 % 5 - 2) * r / 2
    along = ((along % perim) + perim) % perim
    var qx = 0
    var qy = 0
    if along < wd:
        qx = x0 + along
        qy = y0
    elif along < wd + ht:
        qx = x1
        qy = y0 + along - wd
    elif along < 2 * wd + ht:
        qx = x1 - (along - wd - ht)
        qy = y1
    else:
        qx = x0
        qy = y1 - (along - 2 * wd - ht)
    let c = (r + REACH - 50) * 707 / 1000
    if (qx < u_rx0[i] or qx > u_rx1[i]) and (qy < u_ry0[i] or qy > u_ry1[i]):
        qx = clamp(qx, u_rx0[i] - c, u_rx1[i] + c)
        qy = clamp(qy, u_ry0[i] - c, u_ry1[i] + c)
    let ln = lane(i)
    if not walkable(qx, qy, ln) or not clear_path(x, y, qx, qy, r, ln): return spot(i, x, y)
    return qx, qy

// A corner of unit i's rect, stood off by a body and a row, to walk round it towards (tx, ty): of
// the corners it can walk straight to (not the one it's at), the shortest way on. (-1, -1) if none.
def round_corner(i:int, x:int, y:int, tx:int, ty:int) -> int, int:
    let e = 3 * u_radius[i] + FORM_GAP
    let ln = lane(i)
    var bx = -1
    var by = -1
    var best_d = 1 << 62
    let cxs = [ u_rx0[i] - e, u_rx1[i] + e, u_rx1[i] + e, u_rx0[i] - e ]
    let cys = [ u_ry0[i] - e, u_ry0[i] - e, u_ry1[i] + e, u_ry1[i] + e ]
    for(4) k:
        let cx = cxs[k]
        let cy = cys[k]
        let d0 = dist2(x, y, cx, cy)
        if d0 >= 200 * 200 and walkable(cx, cy, ln) and clear_path(x, y, cx, cy, u_radius[i], ln):
            let d = isqrt(d0) + isqrt(dist2(cx, cy, tx, ty))
            if d < best_d:
                best_d = d
                bx = cx
                by = cy
    return bx, by

// The nearest point of unit i's rect.
def rect_near(i:int, x:int, y:int) -> int, int:
    return clamp(x, u_rx0[i], u_rx1[i]), clamp(y, u_ry0[i], u_ry1[i])

// How far unit i still has to go, and how much nearer it should be by the next check (World._progress).
def progress(i:int, x:int, y:int) -> int, int:
    if u_fkey[i] >= 0:
        let n = field_index(u_fkey[i])
        if n >= 0:
            let cell = cell_of(x, y)
            let d = field_vals[n].dist[cell]
            if d < INF and d > DIAGONAL and not (d <= DIRECT_COST and u_arrive[i] == SLOT_ARRIVE and u_reach[i] != 1):
                return d, if road.length: max(STRAIGHT_PER_CHECK * step_s[cell] / STRAIGHT, 1) else: STRAIGHT_PER_CHECK  // (a road's tiles cost less: less to gain on one, #129)
    return isqrt(dist2(x, y, u_tx[i], u_ty[i])), u_speed[i] * PROGRESS_EVERY / 4

def queued(i:int, x:int, y:int) -> bool:
    let ux = o_wx[i] - x
    let uy = o_wy[i] - y
    let near = u_arrive[i] * ARRIVE_SETTLE + RETURN_SLACK
    if (ux == 0 and uy == 0) or dist2(x, y, u_tx[i], u_ty[i]) <= near * near: return false
    let cx = x / TILE
    let cy = y / TILE
    let oi = u_owner[i]
    let ri = u_radius[i]
    var yy = max(cy - 1, 0)
    let y1 = min(cy + 2, H)
    while yy < y1:
        var xx = max(cx - 1, 0)
        let x1 = min(cx + 2, W)
        while xx < x1:
            let c = yy * W + xx
            var k = sp_start[c]
            let e = sp_end[c]
            while k < e:
                let j = sp_items[k]
                k++
                if j == i or o_moving[j] == 0 or u_owner[j] != oi or (u_tx[j] == u_tx[i] and u_ty[j] == u_ty[i]): continue
                let rx = o_x[j] - x
                let ry = o_y[j] - y
                let reach = ri + u_radius[j] + QUEUE_GAP
                if rx * ux + ry * uy <= 0 or rx * rx + ry * ry > reach * reach: continue
                if o_stuck[j] == 0 and (o_wx[j] - o_x[j]) * ux + (o_wy[j] - o_y[j]) * uy > 0: return true
            xx++
        yy++
    return false

// Unit i at (x, y), nearly at its target: one of its own side standing on that point already (sent there first)?
def spot_taken(i:int, x:int, y:int) -> bool:
    let tx = u_tx[i]
    let ty = u_ty[i]
    let near = u_radius[i] * 8  // (before it walks into the ring round it, so the free place there is ahead or beside, not behind)
    if dist2(x, y, tx, ty) > near * near: return false
    let cx = clamp(tx / TILE, 0, W - 1)
    let cy = clamp(ty / TILE, 0, H - 1)
    for(3) oy:
        let ny = cy + oy - 1
        if ny >= 0 and ny < H:
            for(3) ox:
                let nx = cx + ox - 1
                if nx >= 0 and nx < W:
                    let c = ny * W + nx
                    var k = sp_start[c]
                    while k < sp_end[c]:
                        let j = sp_items[k]
                        k++
                        let rr = (u_radius[i] + u_radius[j]) / 2
                        if j != i and u_moving[j] == 0 and u_owner[j] == u_owner[i] and t_air[u_kind[j]] == t_air[u_kind[i]] and dist2(u_x[j], u_y[j], tx, ty) < rr * rr: return true
    return false

// Room for unit i to stand at (x, y): nobody pressed into it more than a quarter of their bodies (separate() eases that).
def room_here(i:int, x:int, y:int) -> bool:
    let cx = clamp(x / TILE, 0, W - 1)
    let cy = clamp(y / TILE, 0, H - 1)
    for(3) oy:
        let ny = cy + oy - 1
        if ny >= 0 and ny < H:
            for(3) ox:
                let nx = cx + ox - 1
                if nx >= 0 and nx < W:
                    let c = ny * W + nx
                    var k = sp_start[c]
                    while k < sp_end[c]:
                        let j = sp_items[k]
                        k++
                        let rr = (u_radius[i] + u_radius[j]) * 3 / 4
                        if j != i and t_air[u_kind[j]] == t_air[u_kind[i]] and dist2(u_x[j], u_y[j], x, y) < rr * rr: return false
    return true

// A herd animal driven somewhere with its flock all round it going too (#398): held up among them, not stuck, it's as
// patient as a group (on its own it gave up for good in the jostle at a wall's gap, its flock gone on).
def in_flock(i:int, x:int, y:int) -> bool:
    if t_behave[u_kind[i]] != B_HERD: return false
    let cx = x / TILE
    let cy = y / TILE
    let reach = u_radius[i] * 3
    for(3) oy:
        let ny = cy + oy - 1
        if ny >= 0 and ny < H:
            for(3) ox:
                let nx = cx + ox - 1
                if nx >= 0 and nx < W:
                    let c = ny * W + nx
                    var k = sp_start[c]
                    while k < sp_end[c]:
                        let j = sp_items[k]
                        k++
                        if j != i and o_moving[j] == 1 and u_owner[j] == u_owner[i] and t_behave[u_kind[j]] == B_HERD and dist2(o_x[j], o_y[j], x, y) <= reach * reach: return true
    return false

def passed(i:int, x:int, y:int) -> bool:
    if u_arrive[i] != SLOT_ARRIVE or dist2(x, y, u_tx[i], u_ty[i]) > RETURN_YIELD * RETURN_YIELD: return false
    let cx = x / TILE
    let cy = y / TILE
    let oi = u_owner[i]
    let gi = u_group[i]
    let ri = u_radius[i]
    var yy = max(cy - 1, 0)
    let y1 = min(cy + 2, H)
    while yy < y1:
        var xx = max(cx - 1, 0)
        let x1 = min(cx + 2, W)
        while xx < x1:
            let c = yy * W + xx
            var k = sp_start[c]
            let e = sp_end[c]
            while k < e:
                let j = sp_items[k]
                k++
                if j == i or o_moving[j] == 0 or u_owner[j] != oi or u_group[j] == gi or u_group[j] == 0: continue
                let reach = ri + u_radius[j] + QUEUE_GAP
                if dist2(u_tx[j], u_ty[j], u_tx[i], u_ty[i]) <= reach * reach: continue  // (sent to the same spot: neither is passing, each would excuse the other for ever, #396)
                if dist2(o_x[j], o_y[j], x, y) <= reach * reach: return true
            xx++
        yy++
    return false

def move():
    let n = u_x.length
    // World._move means these as the tick's start, but Godot's packed arrays are shared, not copied
    // on write: its _ox, _om, _ost, _owx are the live arrays. The port follows what GDScript does.
    blocks_tick()
    o_x = u_x
    o_y = u_y
    o_moving = u_moving
    o_stuck = u_stuck
    o_wx = u_wx
    o_wy = u_wy
    let xs = u_x
    let ys = u_y
    let mv = u_moving
    let st = u_stuck
    let wxs = u_wx
    let wys = u_wy
    for(n) i:
        if mv[i] == 0:
            u_vx[i] = 0
            u_vy[i] = 0
            if u_group[i] == 0 or u_foe[i] != 0 or (tick + u_id[i]) % REPLAN_EVERY != 0: continue
            let back = if u_block[i] > 0 and not place_free(i): u_arrive[i] * ARRIVE_SETTLE + TILE else: u_arrive[i] * ARRIVE_SETTLE + (if u_arrive[i] == SLOT_ARRIVE: SLOT_SLACK else: RETURN_SLACK)  // (in a block: back to its place once it's clear, #347)
            if dist2(xs[i], ys[i], u_tx[i], u_ty[i]) <= back * back:
                st[i] = 0
                continue
            if st[i] >= STUCK_LIMIT: continue
            mv[i] = 1
        let x = xs[i]
        let y = ys[i]
        if u_reach[i] == 1:
            let ex = max(max(u_rx0[i] - x, 0), x - u_rx1[i])
            let ey = max(max(u_ry0[i] - y, 0), y - u_ry1[i])
            let reach = u_radius[i] + REACH
            if ex * ex + ey * ey <= reach * reach:
                mv[i] = 0
                st[i] = 0
                continue
        else:
            let gx = u_tx[i] - x
            let gy = u_ty[i] - y
            if gx * gx + gy * gy <= u_arrive[i] * u_arrive[i]:
                mv[i] = 0
                st[i] = 0
                continue
        var s = if u_pace[i] == 0: u_speed[i] else: min(u_speed[i], u_pace[i])
        let mci = u_mclass[i]
        let mc = lane_base[u_owner[i]] + mci
        let here = cell_of(x, y)
        var pct = speed_pct[mci][here]
        if pct < 100 and t_wade[u_kind[i]] > 0: pct = 100  // the swamp folk's bonus: no terrain slows them
        if slow_ids.length:
            let found, at = binary_search(slow_ids, u_id[i])
            if found: pct = pct * slow_pcts[at] / 100  // in an enemy web, or hit by sticky silk
        if pct != 100: s = s * pct / 100
        if tr_speed_pct != 0 and mci != 2: s = s * trail_pct(here) / 100  // quicker on a worn trail (a rule, off by default)
        if u_block[i] == 0 and u_reach[i] == 0 and u_foe[i] == 0 and t_animal[u_kind[i]] == 0 and (tick + u_id[i]) % REPLAN_EVERY == 0 and spot_taken(i, x, y):
            var fx, fy = clear_point(u_owner[i], u_kind[i], u_tx[i], u_ty[i], i)
            if room_here(i, x, y) and dist2(x, y, u_tx[i], u_ty[i]) <= dist2(fx, fy, u_tx[i], u_ty[i]):  // (already as near, with room where it is: it stops there, not walking back)
                fx = x
                fy = y
            u_tx[i] = fx  // (one of its own already standing on the spot it was sent to: it takes the nearest one free beside it, #396)
            u_ty[i] = fy
            wxs[i] = fx
            wys[i] = fy
        if steered(i):  // in a formation block: steering for its place (lib/steering.lobster, #355)
            steer_group(i, x, y, s, mc)
            continue
        if (tick + u_id[i]) % PROGRESS_EVERY == 0 and u_foe[i] == 0:
            let px, py = progress(i, x, y)
            if u_prog[i] >= 0 and px > u_prog[i] - py and u_reach[i] == 0 and (queued(i, x, y) or (u_group[i] > 0 and passed(i, x, y))):  // (held up behind its own side going its way: not stuck, #382)
                pass()
            elif u_prog[i] >= 0 and px > u_prog[i] - py:
                st[i] += STUCK_LIMIT / (if (u_group[i] > 0 or in_flock(i, x, y)) and u_reach[i] == 0: 6 else: 2)
                if st[i] >= STUCK_LIMIT:
                    let near = u_arrive[i] * ARRIVE_SETTLE + RETURN_SLACK
                    if u_reach[i] != 1 and dist2(x, y, u_tx[i], u_ty[i]) <= near * near: st[i] = 0
                    mv[i] = 0
                    continue
            else:
                st[i] = 0
            u_prog[i] = px
        if (tick + u_id[i]) % REPLAN_EVERY == 0 or dist2(x, y, wxs[i], wys[i]) <= s * s:
            var wx, wy = plan(i, x, y, st[i])
            if wx == -2:
                // Past a near field's edge: switch to the full field, straight on meanwhile.
                let key = u_fkey[i]
                var base = key / LANES
                base = base - base % 4 + (if base % 4 == FIELD_CELL_NEAR: FIELD_CELL else: FIELD_BUILDING)
                u_fkey[i] = base * LANES + key % LANES
                wx = u_tx[i]
                wy = u_ty[i]
            elif wx == -3:
                // Nowhere free round its rect: a few looks like that and it gives the place up.
                st[i] += STUCK_LIMIT / SPOT_BUSY
                if st[i] >= STUCK_LIMIT:
                    mv[i] = 0
                    continue
                wx, wy = rect_near(i, x, y)
            elif wx < 0:
                mv[i] = 0
                st[i] = STUCK_LIMIT
                continue
            wxs[i] = wx
            wys[i] = wy
        // Every walker steers for its waypoint, like everyone in a block; one chasing a foe too (#351).
        steer_to(i, x, y, s, mc, wxs[i], wys[i], 0, wxs[i] == u_tx[i] and wys[i] == u_ty[i])
        if u_foe[i] == 0 and xs[i] == x and ys[i] == y and u_reach[i] == 0:  // (held right by its target: it has arrived; anywhere else the progress checks above decide)
            let near = u_arrive[i] * ARRIVE_SETTLE
            if dist2(x, y, u_tx[i], u_ty[i]) <= near * near:
                mv[i] = 0
                st[i] = 0

// The nearest walkable point for a centre on blocked ground (World._step_out).
def step_out(x:int, y:int, mc:int) -> int, int:
    let cx = x / TILE
    let cy = y / TILE
    var bx = -1
    var by = -1
    var best_d = 1 << 30
    def try(ncx:int, ncy:int, px:int, py:int):
        if cell_walkable(ncx, ncy, mc):
            let d = abs(px - x) + abs(py - y)
            if d < best_d:
                best_d = d
                bx = px
                by = py
    try(cx - 1, cy, cx * TILE - 1, y)
    try(cx + 1, cy, (cx + 1) * TILE, y)
    try(cx, cy - 1, x, cy * TILE - 1)
    try(cx, cy + 1, x, (cy + 1) * TILE)
    if bx >= 0: return bx, by
    return centre(nearest_walkable(cy * W + cx, mc))

let GUN_SHOT_SPEED = 800  // milli-tiles a tick: a shot this fast is a gun's

// Push overlapping pairs apart (World._separate; nobody is at a job or fighting here).
// Is unit i (walking) coming back to its own place in its group, nearly there?
def homing(i:int) -> bool:
    return u_group[i] > 0 and u_arrive[i] == SLOT_ARRIVE and u_reach[i] == 0 and u_foe[i] == 0 and dist2(u_x[i], u_y[i], u_tx[i], u_ty[i]) <= RETURN_YIELD * RETURN_YIELD

def separate():
    let n = u_x.length
    let xs = u_x
    let ys = u_y
    let rs = u_radius
    let ids = u_id
    let mv = u_moving
    let grp = u_group
    let owners = u_owner
    let w = W
    let h = H
    for(n) i:
        s_pushx[i] = 0
        s_pushy[i] = 0
        // Workers standing at their job are planted: nobody moves them. (Hitting a building, too: none here.)
        s_planted[i] = if mv[i] == 0 and (u_task[i] == GATHER or u_task[i] == BUILD): 1 else: 0
        if mv[i] == 0 and s_planted[i] == 0 and u_foe[i] != 0:
            // So is a unit hitting a building: the crowd round a wall walks round it.
            let b = b_index_of(u_foe[i])
            if b >= 0 and gap_b(i, b) <= t_reach[u_kind[i]] + HOLD: s_planted[i] = 1
            // A gun standing to fire: its own side goes round it (#262). A foe still shoves it, and so do bows, whose crush is what's balanced.
            if s_planted[i] == 0 and t_ranged[u_kind[i]] != 0 and t_shot_speed[u_kind[i]] >= GUN_SHOT_SPEED: s_planted[i] = 2
    let hc = inside_col()
    for(n) u:
        s_inside[u] = if is_inside(u, hc): 1 else: 0
    for(n) u:
        if u_perch[u] == 0 and s_inside[u] == 0:  // units on walls stand apart from the crowd below, and those inside a building (#120) aren't in it
            let cx = sp_cell[u] % w
            let cy = sp_cell[u] / w
            let xu = xs[u]
            let yu = ys[u]
            let ru = rs[u]
            for(5) q:
                let nx = cx + SEP_DX[q]
                let ny = cy + SEP_DY[q]
                if nx < 0 or nx >= w or ny >= h: continue
                let c = ny * w + nx
                var k = sp_start[c]
                let e = sp_end[c]
                while k < e:
                    let v = sp_items[k]
                    k++
                    if (q == 0 and v <= u) or u_perch[v] != 0 or s_inside[v] != 0 or t_air[u_kind[u]] != t_air[u_kind[v]]: continue  // (aircraft pass over)
                    let rr = ru + rs[v]
                    var dx = xs[v] - xu
                    var dy = ys[v] - yu
                    if dx >= rr or dx <= -rr or dy >= rr or dy <= -rr: continue
                    let d2 = dx * dx + dy * dy
                    if d2 >= rr * rr: continue
                    if r_solid == 0 and (mv[u] == 1 or mv[v] == 1) and owners[u] == owners[v] and on_middle(sp_cell[u]) and on_middle(sp_cell[v]): continue  // (one of a side walking down a road's middle passes another there, walking or standing, as the genre's do, trading places, not shoving off it: #129)
                    var i = u
                    var j = v
                    if v < u:
                        i = v
                        j = u
                        dx = -dx
                        dy = -dy
                    let d = isqrt(d2)
                    var ux = 0
                    var uy = 0
                    if d == 0:
                        let ang = (ids[i] * 31 + ids[j] * 17) & 255
                        ux = cos_a(ang)
                        uy = sin_a(ang)
                    else:
                        ux = dx * ONE / d
                        uy = dy * ONE / d
                    let si = steered(i)
                    let sj = steered(j)
                    if u_block[i] > 0 and u_block[j] > 0 and grp[i] == grp[j] and d > rr / 4 and not (si != sj and mv[if si: j else: i] == 0 and u_block[i] == u_block[j] and u_stuck[if si: i else: j] >= 6): continue  // (an army's blocks: their places keep them apart, and a unit crossing to its place isn't shoved back)
                    if si and sj and owners[i] == owners[j] and grp[i] == grp[j]: continue                                                                                                                               // (two of a side's steering units keep off each other themselves, #355)
                    let ji = mv[i] == 1 and u_task[i] != T_NONE and mv[j] == 0 and u_task[j] == T_NONE and u_foe[j] == 0 and t_worker[u_kind[j]] == 0 and t_animal[u_kind[j]] == 0                                       // (a worker on its job by a soldier standing about, #395)
                    let jj = mv[j] == 1 and u_task[j] != T_NONE and mv[i] == 0 and u_task[i] == T_NONE and u_foe[i] == 0 and t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0
                    if (si != sj or ji or jj) and owners[i] == owners[j]:
                        // One of the side's own steering (or on a job) through another standing about: the standing one is eased
                        // aside, the walker steers round it (#355); a worker on its job is eased off a soldier instead and goes round,
                        // or held up, slips through it: it no longer shoves the soldier along its way (#395). One at work or set to fire
                        // stays put.
                        let o = if si or ji: j else: i
                        if (ji or jj) and u_stuck[if ji: i else: j] > 0: continue  // (held up by it all the same: it slips through, a friend's body soft, and the soldier stays put)
                        if ji or jj:
                            let wk = if ji: i else: j
                            let ow = if o == i: -1 else: 1
                            s_pushx[wk] -= ow * ux * ((rr - d) / SEPARATION_DIV + 1) / ONE  // (it holds its ground; the worker is the one eased off it and goes round)
                            s_pushy[wk] -= ow * uy * ((rr - d) / SEPARATION_DIV + 1) / ONE
                            continue
                        if mv[o] == 0 and u_foe[o] == 0 and s_planted[o] == 0:
                            let ease = (rr - d) / (SEPARATION_DIV * 2) + 1
                            let sg = if o == i: -1 else: 1
                            let wk = if si or ji: i else: j
                            let wv = isqrt(u_vx[wk] * u_vx[wk] + u_vy[wk] * u_vy[wk])
                            var ex = sg * ux
                            var ey = sg * uy
                            if wv > 0:  // (aside: off the walker's line, never shoved along ahead of it)
                                let px = -u_vy[wk] * ONE / wv
                                let py = u_vx[wk] * ONE / wv
                                let across = (ex * px + ey * py) / ONE
                                ex = px * (if across >= 0: 1 else: -1)
                                ey = py * (if across >= 0: 1 else: -1)
                            s_pushx[o] += ex * ease / ONE
                            s_pushy[o] += ey * ease / ONE
                            continue
                    // Of a side's own: one standing in its place isn't shoved by its group walking by, nor by one coming home to its own
                    // place nearby; a soldier standing idle holds its ground (#262) but makes way for one on a job; one steering in its
                    // block goes before the rest; one at work or set to fire stays put. Anyone else's is a body, shoved apart evenly (#351).
                    let own = owners[i] == owners[j]
                    let placed_i = grp[i] > 0 and u_arrive[i] == SLOT_ARRIVE and u_reach[i] == 0 and mv[i] == 0
                    let placed_j = grp[j] > 0 and u_arrive[j] == SLOT_ARRIVE and u_reach[j] == 0 and mv[j] == 0
                    if placed_i and placed_j: continue
                    if (placed_i and mv[j] == 1 and (grp[j] == grp[i] or (own and homing(j)))) or (placed_j and mv[i] == 1 and (grp[i] == grp[j] or (own and homing(i)))): continue
                    let idle_i = own and mv[i] == 0 and u_task[i] == T_NONE and u_foe[i] == 0 and not placed_i and mv[j] == 1 and u_task[j] == T_NONE and t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0
                    let idle_j = own and mv[j] == 0 and u_task[j] == T_NONE and u_foe[j] == 0 and not placed_j and mv[i] == 1 and u_task[i] == T_NONE and t_worker[u_kind[j]] == 0 and t_animal[u_kind[j]] == 0
                    let job_i = own and mv[i] == 1 and u_task[i] != T_NONE and mv[j] == 0 and u_task[j] == T_NONE and u_foe[j] == 0 and not placed_j
                    let job_j = own and mv[j] == 1 and u_task[j] != T_NONE and mv[i] == 0 and u_task[i] == T_NONE and u_foe[i] == 0 and not placed_i
                    let hi = idle_i or job_i or (si and own and not sj and u_foe[j] == 0) or s_planted[i] == 1 or (own and s_planted[i] == 2) or (u_block[i] > 0 and t_animal[u_kind[j]] != 0) or (own and mv[i] == 1 and grp[i] > 0 and grp[i] != grp[j] and (placed_j or (mv[j] == 1 and homing(j))))
                    let hj = idle_j or job_j or (sj and own and not si and u_foe[i] == 0) or s_planted[j] == 1 or (own and s_planted[j] == 2) or (u_block[j] > 0 and t_animal[u_kind[i]] != 0) or (own and mv[j] == 1 and grp[j] > 0 and grp[j] != grp[i] and (placed_i or (mv[i] == 1 and homing(i))))
                    let hit_i = u_foe[j] == ids[i] and u_foe[i] == 0  // (one attacked and not fighting, a sheep for the knife, holds its ground: the one hitting it gives way, #414)
                    let hit_j = u_foe[i] == ids[j] and u_foe[j] == 0
                    if (hit_i and not hj) or (hit_j and not hi):
                        let push = (rr - d) / SEPARATION_DIV + 1
                        let sg = if hit_i: 1 else: -1
                        s_pushx[if hit_i: j else: i] += sg * ux * push * 2 / ONE
                        s_pushy[if hit_i: j else: i] += sg * uy * push * 2 / ONE
                        continue
                    if hi and hj: continue
                    let stand_i = mv[i] == 0 and u_task[i] == T_NONE and u_foe[i] == 0 and t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0 and t_animal[u_kind[j]] != 0
                    let stand_j = mv[j] == 0 and u_task[j] == T_NONE and u_foe[j] == 0 and t_worker[u_kind[j]] == 0 and t_animal[u_kind[j]] == 0 and t_animal[u_kind[i]] != 0
                    if (stand_i and not hj) or (stand_j and not hi):  // (a soldier standing about isn't shoved by a sheep, nor by the workers driving one into it: the sheep gives way, #395)
                        let push = (rr - d) / SEPARATION_DIV + 1
                        let sg = if stand_i: 1 else: -1
                        s_pushx[if stand_i: j else: i] += sg * ux * push * 2 / ONE
                        s_pushy[if stand_i: j else: i] += sg * uy * push * 2 / ONE
                        continue
                    let push = (rr - d) / SEPARATION_DIV + 1
                    let px = ux * push / ONE
                    let py = uy * push / ONE
                    if not hi:
                        s_pushx[i] -= px * (if hj: 2 else: 1)
                        s_pushy[i] -= py * (if hj: 2 else: 1)
                    if not hj:
                        s_pushx[j] += px * (if hi: 2 else: 1)
                        s_pushy[j] += py * (if hi: 2 else: 1)
    let t = TILE
    let mw = W
    let mh = H
    for(n) i:
        if u_perch[i] == 0:  // (up on a wall: the walkway places it)
            let mc = lane_base[owners[i]] + u_mclass[i]
            let wk = walks[mc]
            let x0 = xs[i]
            let y0 = ys[i]
            if x0 < 0 or y0 < 0 or x0 / t >= mw or y0 / t >= mh or wk[y0 / t * mw + x0 / t] == 0:
                let px, py = step_out(xs[i], ys[i], mc)
                xs[i] = px
                ys[i] = py
                continue
            if s_pushx[i] != 0:
                let nx = x0 + s_pushx[i]
                if nx >= 0 and nx / t < mw and wk[y0 / t * mw + nx / t] == 1: xs[i] = nx
            if s_pushy[i] != 0:
                let ny = y0 + s_pushy[i]
                if ny >= 0 and ny / t < mh and wk[ny / t * mw + xs[i] / t] == 1: ys[i] = ny
            let cx = xs[i] / t
            let cy = ys[i] / t
            let r = rs[i]
            let c = cy * mw + cx
            if xs[i] - cx * t < r and (cx == 0 or wk[c - 1] == 0):
                xs[i] = min(cx * t + r, xs[i] + CORRECT_MAX)
            elif (cx + 1) * t - xs[i] < r and (cx + 1 >= mw or wk[c + 1] == 0):
                xs[i] = max((cx + 1) * t - r, xs[i] - CORRECT_MAX)
            if ys[i] - cy * t < r and (cy == 0 or wk[c - mw] == 0):
                ys[i] = min(cy * t + r, ys[i] + CORRECT_MAX)
            elif (cy + 1) * t - ys[i] < r and (cy + 1 >= mh or wk[c + mw] == 0):
                ys[i] = max((cy + 1) * t - r, ys[i] - CORRECT_MAX)
            let pen = pen_holding(i)  // (a pen is walked over: its fence is only here)
            if pen >= 0:
                let hx, hy = pen_inside(pen, i, xs[i], ys[i])
                xs[i] += clamp(hx - xs[i], -CORRECT_MAX, CORRECT_MAX)
                ys[i] += clamp(hy - ys[i], -CORRECT_MAX, CORRECT_MAX)

// ---- solid bodies (rules economy "solid_bodies", #165): nobody walks through anybody. A step that would press into
// another's body, no further from it than before, is taken to the walker's right instead (so two meeting head on both
// keep right and pass side by side), else to its left, else round the edge of the one in the way, else not at all: it
// waits, and someone idle in its way is eased aside. Never through anyone standing; two walkers held up by each other
// long (head on in a gap too narrow to pass) slip past, the genre's forced swap.

var solid_px = []::int  // each unit's place at the tick's start (solid_before)
var solid_py = []::int

def solid_before():
    if r_solid == 0: return
    solid_px = copy(u_x)
    solid_py = copy(u_y)

def solid_body(i:int, hc:int) -> bool: return u_perch[i] == 0 and t_air[u_kind[i]] == 0 and not is_inside(i, hc)

// Would unit i at (x, y) press into another's body, no further from it than from (ox, oy)? The one it would press into, or -1.
def pressed(i:int, x:int, y:int, ox:int, oy:int, hc:int) -> int:
    let cx = clamp(x / TILE, 0, W - 1)
    let cy = clamp(y / TILE, 0, H - 1)
    for(3) dy:
        for(3) dx:
            let nx = cx + dx - 1
            let ny = cy + dy - 1
            if nx >= 0 and ny >= 0 and nx < W and ny < H:
                let c = ny * W + nx
                var k = sp_start[c]
                while k < sp_end[c]:
                    let j = sp_items[k]
                    k++
                    if j != i and solid_body(j, hc):
                        let rr = u_radius[i] + u_radius[j]
                        let d2 = dist2(x, y, u_x[j], u_y[j])
                        if d2 < rr * rr and d2 <= dist2(ox, oy, u_x[j], u_y[j]): return j  // (in its body and no further off)
    return -1

def presses(i:int, x:int, y:int, ox:int, oy:int, hc:int) -> bool: return pressed(i, x, y, ox, oy, hc) >= 0

let ASIDE = 600  // how far an idle unit steps off a walker's line, milli-tiles

// Unit j, standing about with nothing to do, in walker i's way (going by vx, vy): it steps off i's line, to a side or on
// ahead, wherever there's room, as a walker pushes an idle one aside in the genre, rather than i going through it.
def push_aside(i:int, j:int, vx:int, vy:int, hc:int):
    if u_task[j] != T_NONE or u_moving[j] != 0 or u_foe[j] != 0 or u_orders[j].length or u_perch[j] != 0: return
    let v = max(1, isqrt(vx * vx + vy * vy))
    let side = if (u_x[j] - u_x[i]) * vy - (u_y[j] - u_y[i]) * vx > 0: -1 else: 1  // (the side of i's line it stands on)
    for(6) k:
        let sg = if k % 2 == 0: side else: -side
        let ahead = [ 0, 0, 1, 1, 2, 2 ][k]  // (straight aside, then aside and on, then further on)
        let tx = u_x[j] + (-sg * vy * ASIDE + ahead * vx * ASIDE) / v
        let ty = u_y[j] + (sg * vx * ASIDE + ahead * vy * ASIDE) / v
        if walkable(tx, ty, lane(j)) and clear_path(u_x[j], u_y[j], tx, ty, u_radius[j], lane(j)) and not presses(j, tx, ty, u_x[j], u_y[j], hc):
            order_move(j, tx, ty, SLOT_ARRIVE, 0, -1, -1, 0, true)
            return

let PUSH_GAP = 100  // how near ahead of a held-up walker someone idle is pushed aside, milli-tiles past touching
let SOLID_EASE = 30  // how far one of two standing in each other steps clear a tick, milli-tiles

// After move (its buckets built): each walker's step checked against the others' bodies, in slot order.
def solid_tick():
    if r_solid == 0 or solid_px.length != u_x.length: return
    let hc = inside_col()
    for(u_x.length) i:
        let ox = solid_px[i]
        let oy = solid_py[i]
        let x = u_x[i]
        let y = u_y[i]
        var pj = if (x != ox or y != oy) and solid_body(i, hc): pressed(i, x, y, ox, oy, hc) else: -1
        if pj >= 0 and u_stuck[i] >= STUCK_LIMIT / 2 and u_moving[pj] != 0 and u_stuck[pj] >= STUCK_LIMIT / 2: pj = -1  // (two walkers held up by each other long: they slip past, the genre's forced swap)
        if pj >= 0:
            let vx = x - ox
            let vy = y - oy
            let ln = lane(i)
            var bx = ox
            var by = oy
            for(4) k:  // (ahead and to its right, straight to its right, then the same to its left: round whoever is in the way)
                if bx == ox and by == oy:
                    let ahead = if k % 2 == 0: 1 else: 0
                    let side = if k < 2: 1 else: -1
                    let f = if ahead == 1: 7 else: 10
                    let sx = ox + (ahead * vx - side * vy) * f / 10
                    let sy = oy + (ahead * vy + side * vx) * f / 10
                    if walkable(sx, sy, ln) and not presses(i, sx, sy, ox, oy, hc):
                        bx = sx
                        by = sy
            if bx == ox and by == oy:  // (round the one in its way: along its edge, the way it's going first)
                let ax = -(u_y[pj] - oy)
                let ay = u_x[pj] - ox
                let a = max(1, isqrt(ax * ax + ay * ay))
                let v = isqrt(vx * vx + vy * vy)
                let first = if ax * vx + ay * vy >= 0: 1 else: -1
                for(2) k:
                    if bx == ox and by == oy:
                        let sg = if k == 0: first else: -first
                        let sx = ox + sg * ax * v / a
                        let sy = oy + sg * ay * v / a
                        if walkable(sx, sy, ln) and not presses(i, sx, sy, ox, oy, hc):
                            bx = sx
                            by = sy
            if bx == ox and by == oy: push_aside(i, pj, vx, vy, hc)  // (no way round: an idle one in the way is pushed aside)
            u_x[i] = bx
            u_y[i] = by
    // A walker held up (no headway at its last look) and standing still for someone idle in its way (its steering holds it
    // short of them): they're pushed aside.
    for(u_x.length) i:
        if u_moving[i] != 0 and u_stuck[i] > 0 and u_x[i] == solid_px[i] and u_y[i] == solid_py[i] and solid_body(i, hc):
            let gx = u_wx[i] - u_x[i]
            let gy = u_wy[i] - u_y[i]
            for(u_x.length) j:
                if j != i and u_moving[j] == 0 and u_task[j] == T_NONE and solid_body(j, hc):
                    let dx = u_x[j] - u_x[i]
                    let dy = u_y[j] - u_y[i]
                    let rr = u_radius[i] + u_radius[j] + PUSH_GAP
                    if dx * dx + dy * dy < rr * rr and dx * gx + dy * gy > 0: push_aside(i, j, gx, gy, hc)
    // Two standing with their bodies in each other (one just out of a building, say): the later by id steps clear.
    for(u_x.length) i:
        if u_moving[i] == 0 and solid_body(i, hc):
            let j = pressed(i, u_x[i], u_y[i], u_x[i], u_y[i], hc)
            if j >= 0 and u_moving[j] == 0 and u_id[j] < u_id[i]:
                let rr = u_radius[i] + u_radius[j]
                let dx = u_x[i] - u_x[j]
                let dy = u_y[i] - u_y[j]
                let d = isqrt(dx * dx + dy * dy)
                let ux = if d > 0: dx * 1000 / d else: 1000
                let uy = if d > 0: dy * 1000 / d else: 0
                let nx = u_x[j] + ux * rr / 1000
                let ny = u_y[j] + uy * rr / 1000
                let step = min(rr - d, SOLID_EASE)
                let sx = u_x[i] + (nx - u_x[i]) * step / max(1, rr - d)
                let sy = u_y[i] + (ny - u_y[i]) * step / max(1, rr - d)
                if walkable(sx, sy, lane(i)) and not presses(i, sx, sy, u_x[i], u_y[i], hc):
                    u_x[i] = sx
                    u_y[i] = sy
    solid_settle(hc)

// Last, a pass over every pair (#201): steps were each checked against the others in slot order, so one held back to
// where it started may now stand in another's new step. Two bodies that overlap are never nearer than at the start of
// these moves: of such a pair the one that moved (the later in slot order if both did) is set out along the line between
// them to how far apart they were, so it still slides past; a second time, or onto ground it can't stand on, it goes
// back to where it started. Until none is left (each goes back once at most, and where everyone started holds). Two
// walkers in the forced swap are let be.
def solid_settle(hc:int):
    let back = map(u_x.length): 0
    var again = true
    while again:
        again = false
        spatial_build()
        for(u_x.length) i:
            if solid_body(i, hc):
                let cx = clamp(u_x[i] / TILE, 0, W - 1)
                let cy = clamp(u_y[i] / TILE, 0, H - 1)
                for(9) n:
                    let nx = cx + n % 3 - 1
                    let ny = cy + n / 3 - 1
                    if nx >= 0 and ny >= 0 and nx < W and ny < H:
                        let c = ny * W + nx
                        var k = sp_start[c]
                        while k < sp_end[c]:
                            let j = sp_items[k]
                            k++
                            if j > i and solid_body(j, hc):
                                let rr = u_radius[i] + u_radius[j]
                                let d2 = dist2(u_x[i], u_y[i], u_x[j], u_y[j])
                                if d2 < rr * rr and d2 < dist2(solid_px[i], solid_py[i], solid_px[j], solid_py[j]):
                                    let swap = u_moving[i] != 0 and u_moving[j] != 0 and u_stuck[i] >= STUCK_LIMIT / 2 and u_stuck[j] >= STUCK_LIMIT / 2
                                    let jm = u_x[j] != solid_px[j] or u_y[j] != solid_py[j]
                                    let im = u_x[i] != solid_px[i] or u_y[i] != solid_py[i]
                                    let who = if jm and back[j] < 2: j else: if im and back[i] < 2: i else: -1
                                    if not swap and who >= 0:
                                        let other = if who == j: i else: j
                                        let was = min(rr, isqrt(dist2(solid_px[i], solid_py[i], solid_px[j], solid_py[j])) + 2)
                                        let d = max(1, isqrt(d2))
                                        let sx = u_x[other] + (u_x[who] - u_x[other]) * was / d
                                        let sy = u_y[other] + (u_y[who] - u_y[other]) * was / d
                                        if back[who] == 0 and isqrt(d2) > 0 and walkable(sx, sy, lane(who)):
                                            u_x[who] = sx
                                            u_y[who] = sy
                                            back[who] = 1
                                        else:
                                            u_x[who] = solid_px[who]
                                            u_y[who] = solid_py[who]
                                            back[who] = 2
                                        again = true
