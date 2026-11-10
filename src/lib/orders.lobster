// ------------------------------------------------------------------ orders (world.gd)

def lane(i:int) -> int: return lane_base[u_owner[i]] + u_mclass[i]

def index_of(uid:int) -> int:
    let found, at = binary_search(u_id, uid)
    return if found: at else: -1

def snap(ax:int, ay:int, ln:int) -> int, int:
    let x = clamp(ax, 0, W * TILE - 1)
    let y = clamp(ay, 0, H * TILE - 1)
    let cell = cell_of(x, y)
    if walks[ln][cell] == 0: return centre(nearest_walkable(cell, ln))
    return x, y

def off_walls(ax:int, ay:int, r:int, ln:int) -> int, int:
    var x = ax
    var y = ay
    let cx = x / TILE
    let cy = y / TILE
    if x - cx * TILE < r and not cell_walkable(cx - 1, cy, ln):
        x = cx * TILE + min(r, TILE / 2)
    elif (cx + 1) * TILE - x < r and not cell_walkable(cx + 1, cy, ln):
        x = (cx + 1) * TILE - min(r, TILE / 2)
    if y - cy * TILE < r and not cell_walkable(cx, cy - 1, ln):
        y = cy * TILE + min(r, TILE / 2)
    elif (cy + 1) * TILE - y < r and not cell_walkable(cx, cy + 1, ln):
        y = (cy + 1) * TILE - min(r, TILE / 2)
    return x, y

let SLOT_STEPS = 8  // a formation slot that isn't open steps in towards the centre in this many steps

def slot_ok(i:int, apx:int, apy:int, x:int, y:int) -> int, int:
    let ln = lane(i)
    let cx, cy = snap(x, y, ln)
    // (the first open point stepping in along the line to the centre: falling straight back to the centre gave two
    // units one spot, and one gave up, the hill crossing)
    for(SLOT_STEPS) k:
        var qx = clamp(apx + (cx - apx) * k / SLOT_STEPS, 0, W * TILE - 1)
        var qy = clamp(apy + (cy - apy) * k / SLOT_STEPS, 0, H * TILE - 1)
        if walkable(qx, qy, ln):
            qx, qy = off_walls(qx, qy, u_radius[i], ln)
            if clear_line(cx, cy, qx, qy, ln): return qx, qy
    return off_walls(cx, cy, u_radius[i], ln)  // (a body's width off the rock, or it can't get there, #347)

// Sorts ints ascending (bottom-up merge sort; the keys are unique, so any sort gives this order).
def sort_ints(xs:[int]):
    let n = xs.length
    var src = xs
    var dst = copy(xs)
    var width = 1
    var into_dst = true
    while width < n:
        var lo = 0
        while lo < n:
            let mid = min(lo + width, n)
            let hi = min(lo + 2 * width, n)
            var a = lo
            var b = mid
            var o = lo
            while o < hi:
                if a < mid and (b >= hi or src[a] <= src[b]):
                    dst[o] = src[a]
                    a++
                else:
                    dst[o] = src[b]
                    b++
                o++
            lo += 2 * width
        let t = src
        src = dst
        dst = t
        into_dst = not into_dst
        width *= 2
    if src != xs:
        for(n) k: xs[k] = src[k]

// Slots in (ahead desc, slot asc) order: World._formation's by_ahead.
def by_ahead(part:[int]) -> [int]:
    let keys = map(part) i: -f_ahead[i] * (1 << KEY_BITS) + i
    sort_ints(keys)
    return map(keys) k: k & ((1 << KEY_BITS) - 1)

// Slots in (side asc, slot asc) order: by_side.
def by_side(part:[int]) -> [int]:
    let keys = map(part) i: f_side[i] * (1 << KEY_BITS) + i
    sort_ints(keys)
    return map(keys) k: k & ((1 << KEY_BITS) - 1)

def form_rmax(part:[int]) -> int:
    var r = 0
    for(part) i: r = max(r, max(u_radius[i], t_form_r[u_kind[i]]))
    return r

def form_space(part:[int]) -> int:
    var g = -(1 << 20)
    for(part) i: g = max(g, t_gap[u_kind[i]])
    return 2 * form_rmax(part) + max(FORM_GAP + g, 0)

// ---- marching blocks (#171)
// A big order is several formations: a block a unit type (BLOCK_MAX at most), in rows by band, foot in front, flankers at
// the ends of the front row. Each block has a centre that forms up where the army stands, then marches to its place at
// the order's pace, and its units keep their places round the centre. On an attack-move a block that's fighting halts,
// and the blocks behind it wait; its units go only for foes near them, and come back to their places.

// A free block (or a new one).
def block_new() -> int:
    let free = find(fb_state) s: s == 0
    if free >= 0: return free
    for([ fb_state, fb_x, fb_y, fb_tx, fb_ty, fb_wx, fb_wy, fb_dx, fb_dy, fb_pace, fb_key, fb_r, fb_owner, fb_army, fb_t, fb_held, fb_gx, fb_gy ]) col: col.push(0)
    return fb_state.length - 1

def block_speed(c:[int]) -> int:
    var s = 1 << 30
    for(c) i: s = min(s, u_speed[i])
    return s

// Every unit's block, its place in it and its slot at the end into slot_block, slot_bx, slot_by, slot_x, slot_y.
def block_formation(army:int, idx:[int], x:int, y:int, cx:int, cy:int, ux:int, uy:int):
    let gap = if idx.length < BLOCK_ARMY: SMALL_GAP else: BLOCK_GAP  // (a small group's blocks stand close: one formation, #347)
    for(idx) i:
        f_ahead[i] = (u_x[i] - cx) * ux + (u_y[i] - cy) * uy
        f_side[i] = (u_y[i] - cy) * ux - (u_x[i] - cx) * uy
    // the blocks, by band (flankers last), then type, then slot
    let keys = map(idx) i: (t_role[u_kind[i]] * (1 << 12) + u_kind[i]) * (1 << KEY_BITS) + i
    sort_ints(keys)
    let chunks = []::[int]
    var kind = -1
    for(keys) key:
        let i = key & ((1 << KEY_BITS) - 1)
        if u_kind[i] != kind or chunks[chunks.length - 1].length == BLOCK_MAX:
            kind = u_kind[i]
            chunks.push([]::int)
        chunks[chunks.length - 1].push(i)
    def wide(c:[int]) -> int: return (min(isqrt(2 * c.length), c.length) - 1) * form_space(c) + 2 * form_rmax(c)
    def deep(c:[int]) -> int: return ((c.length + isqrt(2 * c.length) - 1) / isqrt(2 * c.length) - 1) * form_space(c) + 2 * form_rmax(c)
    // the rows: a row is as wide as the army is big, a band starts a new one
    var area = 0
    for(chunks) c: area += (wide(c) / 100 + 1) * (deep(c) / 100 + 1)
    let row_max = isqrt(area) * 150
    // the march's pace: the middling block's, so the slowest engines fall behind instead of holding everyone up
    let paces = map(chunks) c: block_speed(c)
    sort_ints(paces)
    let spare = if idx.length < BLOCK_ARMY: 19 else: 16   // (twentieths of their walk: a little under it, so whoever falls behind can catch up; a small group
    let army_pace = paces[paces.length / 2] * spare / 20  // starts in its places, so it needs less)
    // whoever can't keep it goes at the back, the slowest last: in front, the blocks behind would walk through it (#253)
    def lags(c:[int]) -> bool: return block_speed(c) * spare / 20 < army_pace
    let late_keys = []::int
    for(chunks) c, n: if lags(c): late_keys.push(((1 << 20) - block_speed(c)) * (1 << KEY_BITS) + n)
    sort_ints(late_keys)
    let in_order = filter(chunks) c: not lags(c)
    for(late_keys) key: in_order.push(chunks[key & ((1 << KEY_BITS) - 1)])
    // flankers go on the wings of an army that has a middle; an army mostly of them forms in rows like any other
    var flankers = 0
    for(idx) i: if t_role[u_kind[i]] == 3: flankers++
    let wings = flankers * 3 <= idx.length
    let rows = []::[[int]]
    var band = -1
    var used = 0
    let flank = []::[int]
    for(in_order) c:
        let role = if lags(c): 4 else: t_role[u_kind[c[0]]]
        if role == 3 and wings and band >= 0:
            flank.push(c)
            continue
        if role != band or used + wide(c) > row_max:
            rows.push([]::[int])
            used = 0
            band = role
        rows[rows.length - 1].push(c)
        used += wide(c) + gap
    if flank.length % 2 == 1 and flank[flank.length - 1].length >= 2:  // (a wing each: the odd block out split in two, #347)
        let c = flank.pop()
        flank.push(c.slice(0, c.length / 2))
        flank.push(c.slice(c.length / 2, c.length - c.length / 2))
    var total = 0
    for(rows) r:
        var h = 0
        for(r) c: h = max(h, deep(c))
        total += h + gap
    // where each block goes: rows front to back, then the flankers in columns at the ends of the rows
    let spot_al = []::int
    let spot_ac = []::int
    let spot_c = []::[int]
    def spot(c:[int], along:int, across:int):
        spot_c.push(c)
        spot_al.push(along)
        spot_ac.push(across)
    var along0 = total / 2
    var half_w = 0
    for(rows) r:
        var h = 0
        var width = -gap
        for(r) c:
            h = max(h, deep(c))
            width += wide(c) + gap
        var across = -width / 2
        for(r) c:
            spot(c, along0 - h / 2, across + wide(c) / 2)
            across += wide(c) + gap
        half_w = max(half_w, width / 2)
        along0 -= h + gap
    let wing = [ -half_w - gap, half_w + gap ]  // each wing's next column, and how far down it's filled
    let wing_at = [ total / 2, total / 2 ]
    var wing_wide = 0
    for(flank) c: wing_wide = max(wing_wide, wide(c))
    for(flank) c, k:
        let s = k % 2
        if wing_at[s] - deep(c) < -total / 2 and wing_at[s] < total / 2:
            wing[s] += (if s == 0: -1 else: 1) * (wing_wide + gap)
            wing_at[s] = total / 2
        spot(c, wing_at[s] - deep(c) / 2, wing[s] + (if s == 0: -1 else: 1) * wing_wide / 2)
        wing_at[s] -= deep(c) + gap
    if flank.length: half_w = max(-wing[0], wing[1]) + wing_wide
    // where the army forms up: from where it stands, on along the way to the first ground that holds it all
    let ln0 = lane(idx[0])
    var samples = 0
    def blocked(ax:int, ay:int) -> int:  // (ground it can't stand on, sampled two tiles apart)
        var n = 0
        samples = 0
        var al = -total / 2 - TILE
        while al <= total / 2 + TILE:
            var ac = -half_w - TILE
            while ac <= half_w + TILE:
                samples++
                if not walkable(ax + (ux * al - uy * ac) / ONE, ay + (uy * al + ux * ac) / ONE, ln0): n++
                ac += 2 * TILE
            al += 2 * TILE
        return n
    var form_x = cx
    var form_y = cy
    var least = if idx.length < BLOCK_ARMY: 0 else: blocked(cx, cy)  // (a small group forms where it stands, on the march)
    let way = isqrt(dist2(cx, cy, x, y))
    var on_way = 2 * TILE
    while on_way <= way / 2 and least > 0:  // (not as far as the enemy's door)
        let ax = cx + ux * on_way / ONE
        let ay = cy + uy * on_way / ONE
        let n = blocked(ax, ay)
        if n < least:
            least = n
            form_x = ax
            form_y = ay
        on_way += 2 * TILE
    var army_farthest = 0
    def place(c:[int], along:int, across:int):
        let bx = (ux * along - uy * across) / ONE
        let by = (uy * along + ux * across) / ONE
        let b = block_new()
        let tx, ty = snap(x + bx, y + by, lane(c[0]))
        fb_state[b] = if idx.length < BLOCK_ARMY: BLOCK_MARCHING else: BLOCK_FORMING
        fb_x[b] = form_x + bx
        fb_y[b] = form_y + by
        fb_tx[b] = tx
        fb_ty[b] = ty
        fb_wx[b] = tx
        fb_wy[b] = ty
        fb_dx[b] = ux
        fb_dy[b] = uy
        fb_pace[b] = min(army_pace, block_speed(c) * spare / 20)
        fb_key[b] = cell_field(cell_of(tx, ty), false, lane(c[0]))
        fb_r[b] = deep(c) / 2
        fb_owner[b] = u_owner[c[0]]
        fb_army[b] = army
        fb_gx[b] = x
        fb_gy[b] = y
        var farthest = 0
        fb_held[b] = 0
        let cols = max(isqrt(2 * c.length), 1)
        let sp = form_space(c)
        let part = by_ahead(c)
        var first = 0
        var top = deep(c) / 2 - form_rmax(c)
        while first < part.length:
            let line = by_side(part.slice(first, min(cols, part.length - first)))
            for(line) i, k:
                let across_k = (2 * k - (line.length - 1)) * sp / 2
                slot_block[i] = b + 1
                slot_bx[i] = (ux * top - uy * across_k) / ONE
                slot_by[i] = (uy * top + ux * across_k) / ONE
                farthest = max(farthest, isqrt(dist2(u_x[i], u_y[i], form_x + bx + slot_bx[i], form_y + by + slot_by[i])) / max(u_speed[i], 1))
                let qx, qy = slot_ok(i, tx + slot_bx[i], ty + slot_by[i], x, y)
                slot_x[i] = qx
                slot_y[i] = qy
            top -= sp
            first += cols
        army_farthest = max(army_farthest, farthest)
    for(spot_c) c, k: place(c, spot_al[k], spot_ac[k])
    for(fb_state) state, b:  // (twice the farthest walk: then they go without the rest)
        if state != 0 and fb_army[b] == army: fb_t[b] = BLOCK_FORM_TICKS - min(BLOCK_FORM_TICKS, 2 * army_farthest + 100)

// Every block's units put straight in their places (a battle set up for filming starts formed).
def blocks_snap():
    for(u_x.length) i:
        let b = u_block[i] - 1
        if b >= 0:
            let x = fb_x[b] + u_bx[i]
            let y = fb_y[b] + u_by[i]
            if walkable(x, y, lane(i)):
                u_x[i] = x
                u_y[i] = y
                u_wx[i] = x
                u_wy[i] = y

// A block's centre, one tick: forming, then marching, unless it or a block just ahead is fighting.
def blocks_tick():
    if not fb_state.length: return
    let alive = map(fb_state.length): 0
    let placed = map(fb_state.length): 0
    let fighting = map(fb_state.length): 0
    for(u_x.length) i:
        let b = u_block[i] - 1
        if b >= 0:
            alive[b]++
            if u_foe[i] != 0: fighting[b]++
            else:
                let px, py = block_place(i)  // (its place off blocked ground, #355)
                if dist2(u_x[i], u_y[i], px, py) <= 40000: placed[b]++
    for(fb_state) state, b:
        if state != 0:
            if alive[b] == 0: fb_state[b] = 0
            else: fb_held[b] = if fighting[b] * 100 >= alive[b] * 30: 1 else: 0
    for(fb_state) state, b:
        if state == BLOCK_FORMING:
            fb_t[b]++
            var ready = fb_t[b] >= BLOCK_FORM_TICKS
            if not ready:
                ready = true
                for(fb_state) other, o:
                    if other == BLOCK_FORMING and fb_army[o] == fb_army[b] and placed[o] < alive[o]: ready = false
            if ready: fb_state[b] = BLOCK_MARCHING
    // A marching block waits for one of its side's just ahead that's fighting, or that's waiting itself (#312): the wait
    // runs back down a column, front to back.
    let waits = map(fb_state.length) b: fb_held[b]
    var changed = true
    while changed:
        changed = false
        for(fb_state) state, b:
            if state == BLOCK_MARCHING and waits[b] == 0:
                for(fb_state) other, o:
                    if waits[b] == 0 and other != 0 and o != b and waits[o] == 1 and fb_owner[o] == fb_owner[b]:
                        let ox = fb_x[o] - fb_x[b]
                        let oy = fb_y[o] - fb_y[b]
                        let reach = fb_r[o] + fb_r[b] + BLOCK_GAP * 2
                        if dist2(0, 0, ox, oy) <= reach * reach and ox * fb_dx[b] + oy * fb_dy[b] > 0:
                            waits[b] = 1
                            changed = true
    for(fb_state) state, b:
        if state == BLOCK_MARCHING and waits[b] == 0: block_march(b)

def block_march(b:int):
    let x = fb_x[b]
    let y = fb_y[b]
    let togo = isqrt(dist2(x, y, fb_tx[b], fb_ty[b]))
    if togo <= fb_pace[b]:
        fb_x[b] = fb_tx[b]
        fb_y[b] = fb_ty[b]
        fb_state[b] = BLOCK_THERE
        return
    if (tick + b) % REPLAN_EVERY == 0 or dist2(x, y, fb_wx[b], fb_wy[b]) <= fb_pace[b] * fb_pace[b]:
        fb_wx[b] = fb_tx[b]
        fb_wy[b] = fb_ty[b]
        let f = field_for(fb_key[b])
        let ln = fb_key[b] % LANES
        if f and x >= 0 and y >= 0 and x / TILE < W and y / TILE < H and not clear_path(x, y, fb_tx[b], fb_ty[b], 100, ln):
            let cell = cell_of(x, y)
            if f.dist[cell] < INF:
                let best = ahead(f, cell, x, y, LOOKAHEAD, 100, ln)
                if best >= 0 and best != cell:  // (in its target's own cell already: straight on)
                    let wx, wy = centre(best)
                    fb_wx[b] = wx
                    fb_wy[b] = wy
    let dx = fb_wx[b] - x
    let dy = fb_wy[b] - y
    let d = isqrt(dx * dx + dy * dy)
    if d > 0:
        fb_dx[b] = dx * ONE / d
        fb_dy[b] = dy * ONE / d
        fb_x[b] = x + dx * min(fb_pace[b], d) / d
        fb_y[b] = y + dy * min(fb_pace[b], d) / d

// An enemy close by: no marching in blocks, there's no time to form up (and a close fight stays as it was priced).
def foe_near(player:int, x:int, y:int) -> bool:
    for(u_x.length) i:
        if u_owner[i] < num_players and is_enemy(player, u_owner[i]) and dist2(u_x[i], u_y[i], x, y) <= BLOCK_FOE_NEAR * BLOCK_FOE_NEAR: return true
    return false

// Where a small group ordered to (x, y) forms: there, or if another of the side's groups is to stand there, the nearest
// free ground beside it across the way (ux, uy) it walks, so two formations don't stand in each other (#347).
def free_spot(player:int, idx:[int], x:int, y:int, ux:int, uy:int) -> int, int:
    let mine = map(u_x.length): 0
    for(idx) i: mine[i] = 1
    let r = (isqrt(2 * idx.length) + 1) * form_space(idx) / 2
    def busy(px:int, py:int) -> bool:
        if not walkable(px, py, lane(idx[0])): return true
        for(u_x.length) j:
            if mine[j] == 0 and u_owner[j] == player and u_group[j] > 0 and u_foe[j] == 0:
                let reach = r + u_radius[j]
                if dist2(u_tx[j], u_ty[j], px, py) < reach * reach: return true
        return false
    if not busy(x, y): return x, y
    for(4) k:
        for(2) side:
            let off = (k + 1) * 2 * r * (if side == 0: 1 else: -1)
            let px = x - uy * off / ONE
            let py = y + ux * off / ONE
            if not busy(px, py): return px, py
    return x, y

// A group move's formation (World._formation): every unit's slot into slot_x / slot_y.
// Returns the group, its centre (fx, fy) and pace.
def formation(player:int, ids:[int], ax:int, ay:int) -> int, int, int, int:
    let idx = []::int
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player: idx.push(i)
    let group = next_group
    next_group++
    let x = clamp(ax, 0, W * TILE - 1)
    let y = clamp(ay, 0, H * TILE - 1)
    if not idx.length: return group, x, y, 0
    let n = idx.length
    var sx = 0
    var sy = 0
    var pace = 1 << 30
    for(idx) i:
        sx += u_x[i]
        sy += u_y[i]
        pace = min(pace, u_speed[i])
    let cx = sx / n
    let cy = sy / n
    let dx = x - cx
    let dy = y - cy
    let d = isqrt(dx * dx + dy * dy)
    var ux = 0
    var uy = ONE
    if d > 0:
        ux = dx * ONE / d
        uy = dy * ONE / d
    if n >= BLOCK_FROM and not foe_near(player, cx, cy):
        let fx, fy = if n < BLOCK_ARMY: free_spot(player, idx, x, y, ux, uy) else: (x, y)
        block_formation(group, idx, fx, fy, cx, cy, ux, uy)
        return group, fx, fy, pace
    let bands = [ []::int, []::int, []::int ]
    var flank = []::int
    for(idx) i:
        let role = t_role[u_kind[i]]
        if role == 3: flank.push(i)
        else: bands[role].push(i)
    if not bands[0].length and not bands[1].length:
        bands[0] = flank
        flank = []::int
    for(idx) i:
        f_ahead[i] = (u_x[i] - cx) * ux + (u_y[i] - cy) * uy
        f_side[i] = (u_y[i] - cy) * ux - (u_x[i] - cx) * uy
    let nc = bands[0].length + bands[1].length + bands[2].length
    let cols = clamp(isqrt(2 * nc), 1, nc)
    var total = 0
    var half = 0
    var deep = 0
    for(bands) part, k:
        if part.length:
            let rows = (part.length + cols - 1) / cols
            let sp = form_space(part)
            total += rows * sp
            half = max(half, (min(cols, part.length) - 1) * sp / 2 + form_rmax(part))
            if k < 2: deep += rows
    def put(i:int, along:int, across:int):
        let px = x + (ux * along - uy * across) / ONE
        let py = y + (uy * along + ux * across) / ONE
        let qx, qy = slot_ok(i, px, py, x, y)
        slot_x[i] = qx
        slot_y[i] = qy
    var top = total / 2
    for(bands) band:
        if band.length:
            let sp = form_space(band)
            let part = by_ahead(band)
            var first = 0
            while first < part.length:
                let line = by_side(part.slice(first, min(cols, part.length - first)))
                let k = line.length
                for(line) i, c: put(i, top - sp / 2, (2 * c - (k - 1)) * sp / 2)
                top -= sp
                first += cols
    if flank.length:
        let fl = by_side(flank)
        let nl = (fl.length + 1) / 2
        let sp = form_space(fl)
        let inner = half + FORM_GAP + form_rmax(fl)
        for([ fl.slice(0, nl), fl.slice(nl, -1) ]) wing0:
            if wing0.length:
                let left = wing0[0] == fl[0]
                let depth = clamp(deep, 1, wing0.length)
                let wc = (wing0.length + depth - 1) / depth
                let wing = by_ahead(wing0)
                var along = total / 2 - sp / 2
                var first = 0
                while first < wing.length:
                    let line = by_side(wing.slice(first, min(wc, wing.length - first)))
                    let k = line.length
                    for(line) i, c:
                        put(i, along, if left: -(inner + (k - 1 - c) * sp) else: inner + c * sp)
                    along -= sp
                    first += wc
    return group, x, y, if n > 1: pace else: 0

def start(i:int):
    u_moving[i] = 1
    u_stuck[i] = 0
    u_prog[i] = -1
    var wx, wy = plan(i, u_x[i], u_y[i], 0)
    if wx == -3: wx, wy = rect_near(i, u_x[i], u_y[i])
    u_wx[i] = if wx >= 0: wx else: u_x[i]
    u_wy[i] = if wx >= 0: wy else: u_y[i]

// Field keys: ((target * 4 + kind) * LANES + lane).
def cell_field(cell:int, near:bool, ln:int) -> int:
    return (cell * 4 + (if near: FIELD_CELL_NEAR else: FIELD_CELL)) * LANES + ln

def building_field(bid:int, near:bool, ln:int) -> int:
    return (bid * 4 + (if near: FIELD_BUILDING_NEAR else: FIELD_BUILDING)) * LANES + ln

// Head for "next to" a rect of milli-tiles (inclusive), following field `key` (World.order_reach).
def order_reach(i:int, x0:int, y0:int, x1:int, y1:int, key:int):
    if u_perch[i] != 0: return  // on a wall: it walks the walkway, never the ground
    u_tx[i] = x0 + (x1 - x0) / 2
    u_ty[i] = y0 + (y1 - y0) / 2
    u_reach[i] = 1
    u_rx0[i] = x0
    u_ry0[i] = y0
    u_rx1[i] = x1
    u_ry1[i] = y1
    u_fkey[i] = key
    u_arrive[i] = 0
    u_group[i] = 0
    start(i)

// Head for a point (snapped to walkable ground) and stop within `arrive` (World.order_move). In a
// group move, its own slot by the field of the group's centre (fx, fy); `near`: a near field.
def order_move(i:int, x:int, y:int, arrive:int, group:int, fx:int, fy:int, pace:int, near:bool = false):
    if u_perch[i] != 0: return
    let ln = lane(i)
    let px, py = snap(x, y, ln)
    var cell = cell_of(px, py)
    if fx >= 0:
        let qx, qy = snap(fx, fy, ln)
        cell = cell_of(qx, qy)
    u_tx[i] = px
    u_ty[i] = py
    u_reach[i] = 0
    u_fkey[i] = cell_field(cell, near, ln)
    u_arrive[i] = arrive
    u_group[i] = group
    u_pace[i] = pace
    start(i)

// Head for a point of its own beside a rect (a place round a building it attacks), following the
// rect's field `key` there and stepping round the rect's corners near it (World.order_beside).
def order_beside(i:int, x:int, y:int, x0:int, y0:int, x1:int, y1:int, key:int):
    if u_perch[i] != 0: return
    u_tx[i] = x
    u_ty[i] = y
    u_reach[i] = 2
    u_rx0[i] = x0
    u_ry0[i] = y0
    u_rx1[i] = x1
    u_ry1[i] = y1
    u_fkey[i] = key
    u_arrive[i] = SLOT_ARRIVE
    u_group[i] = 0
    u_pace[i] = 0
    start(i)

// Head straight for a point with no flow field (World.order_direct).
def order_direct(i:int, x:int, y:int):
    if u_perch[i] != 0: return
    u_tx[i] = x
    u_ty[i] = y
    u_reach[i] = 0
    u_fkey[i] = -1
    u_arrive[i] = 0
    u_group[i] = 0
    start(i)

// Back on an attack-move after a fight: to its own slot, by the group's field (World.resume_attack_move).
def resume_attack_move(i:int):
    var cx = u_amx[i]
    var cy = u_amy[i]
    if u_amc[i] >= 0:
        cx, cy = centre(u_amc[i])
    order_move(i, u_amx[i], u_amy[i], SLOT_ARRIVE, 0, cx, cy, 0)

// Is unit i marching on that order already (a bot gives the same one again and again: it mustn't stop to form up each time)?
def block_same_order(i:int, attack:bool, x:int, y:int) -> bool:
    let b = u_block[i] - 1
    if b < 0 or fb_state[b] == 0 or (attack != (u_stance[i] == ATTACK_MOVE) and not (attack and t_harmless[u_kind[i]])): return false  // (the harmless walk an attack-move)
    return dist2(fb_gx[b], fb_gy[b], x, y) <= 25 * TILE * TILE

// Its formation's block, if it has one: its place there. (It walks at its own speed: the centre sets the pace.)
def block_join(i:int):
    u_block[i] = slot_block[i]
    u_bx[i] = slot_bx[i]
    u_by[i] = slot_by[i]
    if u_block[i] > 0: u_pace[i] = 0
    slot_block[i] = 0

// A MOVE command (World._run, after the formation: for each of the player's units its job and fight
// forgotten (Economy.clear_task, Combat.clear) and order_move to its slot).
def run_move(player:int, ids:[int], group:int, fx:int, fy:int, pace:int):
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player:
            clear_task(i)
            combat_clear(i)
            order_move(i, slot_x[i], slot_y[i], SLOT_ARRIVE, group, fx, fy, pace)
            block_join(i)

// An ATTACK_MOVE command (Combat.cmd_attack_move, after the formation).
def run_attack_move(player:int, ids:[int], group:int, fx:int, fy:int, pace:int):
    let slots = []::int
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player: slots.push(i)
    if not slots.length: return
    let centre_cell = cell_of(fx, fy)
    for(slots) i:
        if t_harmless[u_kind[i]]:
            combat_clear(i)
            clear_task(i)
            order_move(i, slot_x[i], slot_y[i], SLOT_ARRIVE, group, fx, fy, pace)
            block_join(i)
            continue
        clear_task(i)
        u_foe[i] = 0
        u_patient[i] = 0
        u_stance[i] = ATTACK_MOVE
        u_amx[i] = slot_x[i]
        u_amy[i] = slot_y[i]
        u_amc[i] = centre_cell
        order_move(i, slot_x[i], slot_y[i], SLOT_ARRIVE, group, fx, fy, pace)
        block_join(i)

// A STANCE command (Combat.cmd_stance).
def run_stance(player:int, ids:[int], posture:int):
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player and t_animal[u_kind[i]] == 0:  // (animals have no stance)
            u_posture[i] = posture
            if u_stance[i] == AUTO and posture == PASSIVE:
                u_foe[i] = 0
                u_stance[i] = NONE
                u_moving[i] = 0
