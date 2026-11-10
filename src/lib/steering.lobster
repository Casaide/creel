// ------------------------------------------------------------------ steering: group moves (#355)

// Every unit walking in a group move is in a formation block. It steers for its place in the block: a velocity that
// turns by at most its acceleration a tick, slows as it nears its place so it stops there instead of overshooting, and
// bends round its neighbours before it reaches them, instead of walking into them and being shoved back (the bounce,
// #328). The relation decides how: its own block and its army's other blocks only once they press into each other (their
// places keep them apart), its own side's other movers sideways (two groups pass through each other, #348), its own side
// standing still right up to them (separate() eases them aside, #262 still holds for everyone else). Enemies and anyone
// else's are bodies to bump: separate() pushes them apart as it always has. It turns by at most TURN_SIN a tick, and stands
// rather than jiggle when pulled every way at once. Ground in the way: by the flow field until its place is in sight.

// A unit steering in its block this tick (not fighting).
def steered(i:int) -> bool:
    return u_block[i] > 0 and u_moving[i] == 1 and u_foe[i] == 0 and u_stuck[i] < STUCK_LIMIT and u_perch[i] == 0

// Is unit i's own target clear of everyone else's body (a stopped unit in a finished block goes back when it is)?
def place_free(i:int) -> bool:
    let tx = u_tx[i]
    let ty = u_ty[i]
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
                        let rr = (u_radius[i] + u_radius[j]) * 3 / 4
                        if j != i and dist2(u_x[j], u_y[j], tx, ty) < rr * rr: return false
    return true

// Unit i at (x, y), hardly getting nearer its place: a groupmate of its block standing right by it whose place is nearer
// to i, and i's nearer to it, takes i's place and i takes its (the ring of a formation that filled before it got there).
def swap_place(i:int, x:int, y:int) -> bool:
    let b = u_block[i]
    let mine = dist2(x, y, u_tx[i], u_ty[i])
    let cx = clamp(x / TILE, 0, W - 1)
    let cy = clamp(y / TILE, 0, H - 1)
    var best = -1
    var gain = 0
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
                        if j != i and u_block[j] == b and u_moving[j] == 0 and u_foe[j] == 0 and u_kind[j] == u_kind[i]:
                            let rr = u_radius[i] + u_radius[j]
                            if dist2(x, y, u_x[j], u_y[j]) < rr * rr:
                                let now = isqrt(mine) + isqrt(dist2(u_x[j], u_y[j], u_tx[j], u_ty[j]))
                                let then = isqrt(dist2(x, y, u_tx[j], u_ty[j])) + isqrt(dist2(u_x[j], u_y[j], u_tx[i], u_ty[i]))
                                if now - then > gain:
                                    gain = now - then
                                    best = j
    if best < 0: return false
    let j = best
    let tx = u_tx[i]
    let ty = u_ty[i]
    let bx = u_bx[i]
    let by = u_by[i]
    u_tx[i] = u_tx[j]
    u_ty[i] = u_ty[j]
    u_bx[i] = u_bx[j]
    u_by[i] = u_by[j]
    u_tx[j] = tx
    u_ty[j] = ty
    u_bx[j] = bx
    u_by[j] = by
    u_moving[j] = 1
    u_stuck[j] = 0
    u_prog[j] = -1
    return true

// Unit i's place in its formation: round the centre (at the end, its own place), and on ground it can stand on. A place
// on a tree or in water moves in towards the centre until it's clear, so a formation squeezes past instead of its units
// each finding their own way round.
def block_place(i:int) -> int, int:
    let b = u_block[i] - 1
    if fb_state[b] == BLOCK_THERE: return u_tx[i], u_ty[i]
    let cx = fb_x[b]
    let cy = fb_y[b]
    let px = cx + u_bx[i]
    let py = cy + u_by[i]
    let ln = lane(i)
    if walkable(px, py, ln): return px, py
    let d = isqrt(u_bx[i] * u_bx[i] + u_by[i] * u_by[i])
    var k = PLACE_STEP
    while k < d:
        if walkable(px - u_bx[i] * k / d, py - u_by[i] * k / d, ln):
            let m = min(d, k + u_radius[i])  // (a body's width clear of the edge)
            return px - u_bx[i] * m / d, py - u_by[i] * m / d
        k += PLACE_STEP
    return cx, cy

// The velocity unit i at (x, y) bends by to keep off its neighbours, at its speed s.
// (ex, ey): the way to its place. Round its own side it keeps to the side it has started to lean to, so it doesn't weave.
def avoid(i:int, x:int, y:int, s:int, ex:int, ey:int, still:bool) -> int, int:
    var ax = 0
    let vx = u_vx[i]
    let vy = u_vy[i]
    let v = isqrt(vx * vx + vy * vy)
    let lean = ex * vy - ey * vx
    let lean_sgn = if abs(lean) * 8 <= isqrt(ex * ex + ey * ey) * v: 0 elif lean > 0: 1 else: -1
    let hx = if v > 0: vx else: ex  // (its heading: where it walks, or standing, where it wants to)
    let hy = if v > 0: vy else: ey
    let h = isqrt(hx * hx + hy * hy)
    var ay = 0
    let ri = u_radius[i]
    let me = u_owner[i]
    let air = t_air[u_kind[i]]
    let ln = lane(i)
    var need_pos = 0  // (after a foe: how far across its heading it must go to pass every standing one on each side)
    var need_neg = 0
    var still_m = 0
    let cx = clamp(x / TILE, 0, W - 1)
    let cy = clamp(y / TILE, 0, H - 1)
    for(3) oy:
        let ny = cy + oy - 1
        if ny < 0 or ny >= H: continue
        for(3) ox:
            let nx = cx + ox - 1
            if nx < 0 or nx >= W: continue
            let c = ny * W + nx
            var k = sp_start[c]
            let e = sp_end[c]
            while k < e:
                let j = sp_items[k]
                k++
                if j == i or u_perch[j] != 0 or t_air[u_kind[j]] != air: continue
                if still and (u_owner[j] != me or u_moving[j] != 0): continue  // (after a foe: only round its own that stand, #391)
                let rr = ri + u_radius[j]
                let look = rr * AVOID_LOOK / 2
                let dx = x - u_x[j]
                let dy = y - u_y[j]
                if dx >= look or dx <= -look or dy >= look or dy <= -look: continue
                let d2 = dx * dx + dy * dy
                if d2 >= look * look: continue
                let d = isqrt(d2)
                var ux = 0
                var uy = 0
                if d == 0:
                    let ang = (u_id[i] * 31 + u_id[j] * 17) & 255
                    ux = cos_a(ang)
                    uy = sin_a(ang)
                else:
                    ux = dx * ONE / d
                    uy = dy * ONE / d
                // (Then: a worker held up on its job slips through a soldier standing about, #395.)
                if u_owner[j] != me: pass()  // (anyone else's, an enemy above all, is a body to bump: separate() pushes them apart)
                elif u_stuck[i] > 0 and u_task[i] != T_NONE and u_moving[j] == 0 and u_task[j] == T_NONE and u_foe[j] == 0 and t_worker[u_kind[j]] == 0 and t_animal[u_kind[j]] == 0: pass()
                else:
                    // Its own side: round them, to the side it's already on, more than away (a standing one hardest; its own
                    // block only once they press into each other, as their places keep them apart).
                    let same = u_block[i] > 0 and u_block[j] == u_block[i]
                    let army = not same and u_block[j] > 0 and u_group[j] == u_group[i]                                                                              // (its army's other blocks: slipped through to its place)
                    let close = if still: look elif same or army or (u_stuck[i] >= 6 and u_group[j] != u_group[i]): rr * 3 / 4 elif u_moving[j] == 0: rr else: look  // (one standing: right up to it, so it eases aside)
                    // (after a foe: only one ahead, in its way)
                    if still and (h == 0 or ux * hx + uy * hy >= 0 or abs(ux * -hy + uy * hx) / h * d / ONE >= rr): continue
                    if d < close:
                        let w = if same: 3 elif u_moving[j] == 0 and not army: 2 else: 1
                        var sx = ux
                        var sy = uy
                        if h > 0:
                            let side = (ux * -hy + uy * hx) / h  // (its offset across its own heading)
                            var sgn = if abs(side) < ONE / 4 and lean_sgn != 0: lean_sgn elif side > 0: 1 elif side < 0: -1 elif u_id[i] < u_id[j]: 1 else: -1
                            if not walkable(x - hy * rr * sgn / h, y + hx * rr * sgn / h, ln): sgn = -sgn  // (not into a wall or the water: the other side)
                            if still:
                                let lj = -side * d / ONE  // (its offset across the heading)
                                need_pos = max(need_pos, lj + rr)
                                need_neg = max(need_neg, rr - lj)
                            sx = -hy * ONE / h * sgn
                            sy = hx * ONE / h * sgn
                            if (ux * hx + uy * hy) / h < 0 or same:  // (already past it, or its own block: off to the side and away)
                                sx = sx + ux
                                sy = sy + uy
                        if still: still_m += s * (close - d) * w / close
                        else:
                            ax += sx * s * (close - d) * w / (close * ONE)
                            ay += sy * s * (close - d) * w / (close * ONE)
    if still and h > 0:  // (round them all by the shorter way: two standing a gap too narrow apart don't cancel out, #391)
        let sgn = if need_pos < need_neg: 1 elif need_neg < need_pos: -1 elif lean_sgn != 0: lean_sgn elif u_id[i] % 2 == 0: 1 else: -1
        ax = -hy * still_m * sgn / h
        ay = hx * still_m * sgn / h
    return ax, ay

// Unit i at (x, y), speed s this tick, in lane mc: one tick's steering for (gx, gy), its turns and speed-ups scaled by `pace`
// (its block's), slowing to stop there if `brake`. Returns how far it was from it.
def steer_to(i:int, x:int, y:int, s:int, mc:int, gx:int, gy:int, pace:int, brake:bool) -> int:
    let acc = max(1, (if pace > 0: min(s, pace) else: s) / ACCEL_DIV)  // (marching: by the block's pace, so a fast unit in a slow block doesn't jink)
    let ex = gx - x
    let ey = gy - y
    let dd = isqrt(ex * ex + ey * ey)
    if u_block[i] == 0 and u_vx[i] * ex + u_vy[i] * ey < 0 and dd > s:  // (on its own, its way back against where it walks, a load dropped or a new order: it turns where it stands, #373)
        u_vx[i] = 0
        u_vy[i] = 0
    // After a foe: straight at it, but round its own side standing in the way (shooting, working: they don't give way, #391);
    // the rest of the crowd round it is bodies, separate()'s.
    let avx, avy = avoid(i, x, y, s, ex, ey, u_foe[i] != 0)
    let v = isqrt(u_vx[i] * u_vx[i] + u_vy[i] * u_vy[i])
    if u_foe[i] != 0 and dd > 0 and v > 0 and avx == 0 and avy == 0:  // (after a foe: it turns to it at once, keeping its pace, #351)
        u_vx[i] = ex * v / dd
        u_vy[i] = ey * v / dd
    if brake and dd <= PLACE_SETTLE and v <= acc and pace == 0:
        u_vx[i] = 0
        u_vy[i] = 0
        return dd
    var dvx = 0
    var dvy = 0
    if dd > 0:
        let want = if brake: min(min(s, isqrt(2 * acc * dd)), dd) else: s  // (slowing to stop there, never past it in a tick; a marching place it trails a little)
        dvx = ex * want / dd
        dvy = ey * want / dd
    dvx += avx
    dvy += avy
    var vx = u_vx[i]
    var vy = u_vy[i]
    var cx = dvx - vx
    var cy = dvy - vy
    let c = isqrt(cx * cx + cy * cy)
    if c > acc:
        cx = cx * acc / c
        cy = cy * acc / c
    vx += cx
    vy += cy
    let vv = isqrt(vx * vx + vy * vy)
    if vv > s:
        vx = vx * s / vv
        vy = vy * s / vv
    let o = isqrt(u_vx[i] * u_vx[i] + u_vy[i] * u_vy[i])
    let m = isqrt(vx * vx + vy * vy)
    // (walking: it turns by at most TURN_SIN a tick; slowed right down, it turns on the spot; and stopping at a place inside its
    // turning circle, dd < 2 (o / TURN_SIN) sin(off), it turns for it at once, or it circles it for ever, #420)
    let inside = brake and pace == 0 and dd * dd * TURN_SIN < 2 * ONE * abs(u_vx[i] * ey - u_vy[i] * ex)
    if o >= TURN_FREE and m >= TURN_FREE and not inside:
        let ox = u_vx[i]
        let oy = u_vy[i]
        let dot = ox * vx + oy * vy
        if dot <= 0 or dot * dot * ONE * ONE < TURN_COS * TURN_COS * (ox * ox + oy * oy) * (vx * vx + vy * vy):  // (exact: small speeds round badly)
            let sgn = if ox * vy - oy * vx >= 0: 1 else: -1
            let mm = if dot < 0: TURN_FREE else: m  // (turning back: slows to a stop first)
            vx = (ox * TURN_COS - sgn * oy * TURN_SIN) / ONE * mm / o
            vy = (oy * TURN_COS + sgn * ox * TURN_SIN) / ONE * mm / o
    if isqrt(vx * vx + vy * vy) * 3 < acc * 2:  // (jammed in a crowd, pulled every way a little: it stands instead of jiggling)
        vx = 0
        vy = 0
    var nx = x + vx
    var ny = y + vy
    let wk = walks[mc]
    def on(px:int, py:int) -> bool: return px >= 0 and py >= 0 and px / TILE < W and py / TILE < H and wk[py / TILE * W + px / TILE] == 1
    if on(nx, ny) and (nx / TILE == x / TILE or ny / TILE == y / TILE or (on(nx, y) and on(x, ny))): pass()
    elif on(nx, y): ny = y  // (along a tree or the water's edge, not stopped by it, #306)
    elif on(x, ny): nx = x
    else:
        nx = x
        ny = y
    let r = u_radius[i]  // (and its body kept off a blocked cell beside it, as separate() would push it back)
    let qx = nx / TILE
    let qy = ny / TILE
    let q = qy * W + qx
    if nx - qx * TILE < r and (qx == 0 or wk[q - 1] == 0): nx = max(nx, min(qx * TILE + r, x))
    elif (qx + 1) * TILE - nx < r and (qx + 1 >= W or wk[q + 1] == 0): nx = min(nx, max((qx + 1) * TILE - r, x))
    if ny - qy * TILE < r and (qy == 0 or wk[q - W] == 0): ny = max(ny, min(qy * TILE + r, y))
    elif (qy + 1) * TILE - ny < r and (qy + 1 >= H or wk[q + W] == 0): ny = min(ny, max((qy + 1) * TILE - r, y))
    u_vx[i] = nx - x
    u_vy[i] = ny - y
    u_x[i] = nx
    u_y[i] = ny
    return dd

// One tick for unit i, in its block: steering for its place. When it isn't getting nearer (a pond, a wood or a crowd in
// the way) it goes by the flow field for a while (stuck 6), steering all the same, and back to its place once the way is
// clear.
def steer_group(i:int, x:int, y:int, s:int, mc:int):
    let b = u_block[i] - 1
    let px, py = block_place(i)
    if u_stuck[i] < 6:
        u_wx[i] = px
        u_wy[i] = py
        steer_to(i, x, y, s, mc, px, py, if fb_state[b] == BLOCK_MARCHING: fb_pace[b] else: 0, true)
    else:
        if (tick + u_id[i]) % REPLAN_EVERY == 0 or dist2(x, y, u_wx[i], u_wy[i]) <= s * s:
            let wx, wy = plan(i, x, y, 0)
            u_wx[i] = if wx >= 0: wx else: u_tx[i]
            u_wy[i] = if wx >= 0: wy else: u_ty[i]
        if fb_state[b] == BLOCK_THERE or (x - px) * fb_dx[b] + (y - py) * fb_dy[b] <= 0:
            steer_to(i, x, y, s, mc, u_wx[i], u_wy[i], 0, u_wx[i] == u_tx[i] and u_wy[i] == u_ty[i])
        else:
            steer_to(i, x, y, s, mc, x, y, 0, true)  // (ahead of its place, the field's way: it waits for the block)
    if (tick + u_id[i]) % PROGRESS_EVERY == 0:
        let dd = isqrt(dist2(x, y, px, py))
        let was = u_prog[i]
        u_prog[i] = dd
        if was < 0: return
        let poor = dd > was - s * PROGRESS_EVERY / 8  // (hardly nearer)
        let clear = clear_path(x, y, px, py, u_radius[i], mc)
        if u_stuck[i] < 6 and poor and not clear:
            u_stuck[i] = 6  // (ground in the way, not a crowd: by the flow field; there, the field to its own place)
            if fb_state[b] == BLOCK_THERE: u_fkey[i] = cell_field(cell_of(u_tx[i], u_ty[i]), false, mc)
        elif poor and swap_place(i, x, y):
            u_prog[i] = -1  // (a groupmate stood between it and its place: they swapped)
        elif fb_state[b] == BLOCK_THERE and dd <= u_arrive[i] * ARRIVE_SETTLE + TILE and poor and not place_free(i):
            u_moving[i] = 0  // (its place in a crowd: it stops as near as it gets)
            u_stuck[i] = 0
        elif fb_state[b] == BLOCK_THERE and u_stuck[i] < 6 and poor and u_vx[i] == 0 and u_vy[i] == 0:
            u_stuck[i]++  // (standing, wedged behind its groupmates with its place clear: a few looks, then where it stands is its place)
            if u_stuck[i] >= STALL_LOOKS:
                u_tx[i] = x
                u_ty[i] = y
                u_moving[i] = 0
                u_stuck[i] = 0
        elif u_stuck[i] >= 6 and clear:
            u_stuck[i] = 0
        elif u_stuck[i] < 6:
            u_stuck[i] = 0
