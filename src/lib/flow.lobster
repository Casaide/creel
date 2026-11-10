// ------------------------------------------------------------------ flow fields (flow.gd)

class Flow:
    sources:[int]
    max_cost:int
    pops:int
    dist:[int]
    next:[int]

var field_keys = []::int   // World.field_order: cached field keys, oldest first
var field_vals = []::Flow  // alongside
var field_queue = []::int
var ring = []::[int]

def centre(cell:int) -> int, int:
    return (cell % W) * TILE + TILE / 2, (cell / W) * TILE + TILE / 2

def cell_of(x:int, y:int) -> int:
    return clamp(y / TILE, 0, H - 1) * W + clamp(x / TILE, 0, W - 1)

def walkable(x:int, y:int, k:int) -> bool:
    if x < 0 or y < 0: return false
    let tx = x / TILE
    let ty = y / TILE
    if tx >= W or ty >= H: return false
    return walks[k][ty * W + tx] == 1

def cell_walkable(cx:int, cy:int, k:int) -> bool:
    return cx >= 0 and cy >= 0 and cx < W and cy < H and walks[k][cy * W + cx] == 1

def solve(srcs:[int], cutoff:int, k:int) -> Flow:
    let w = W
    let h = H
    let n = w * h
    let walk = walks[k]
    let dist = []::int
    let next = []::int
    dist.vector_capacity(n)
    next.vector_capacity(n)
    for(n):
        dist.push(INF)
        next.push(-1)
    var pending = 0
    for(srcs) src:
        dist[src] = 0
        ring[0].push(src)
        pending++
    var pops = 0
    var cost = 0
    while pending > 0 and cost <= cutoff:
        let bucket = ring[cost % RING]
        var bi = 0
        while bi < bucket.length:
            let c = bucket[bi]
            bi++
            pending--
            if dist[c] != cost: continue
            pops++
            let cx = c % w
            let cy = c / w
            let up = cy > 0 and walk[c - w] == 1
            let down = cy < h - 1 and walk[c + w] == 1
            let left = cx > 0 and walk[c - 1] == 1
            let right = cx < w - 1 and walk[c + 1] == 1
            let from_blocked = walk[c] == 0
            let ne = (up and right) or (from_blocked and cy > 0 and cx < w - 1)
            let se = (down and right) or (from_blocked and cy < h - 1 and cx < w - 1)
            let sw = (down and left) or (from_blocked and cy < h - 1 and cx > 0)
            let nw = (up and left) or (from_blocked and cy > 0 and cx > 0)
            let s = cost + STRAIGHT
            let d = cost + DIAGONAL
            let bs = ring[s % RING]
            let bd = ring[d % RING]
            let n_ = c - w
            let e_ = c + 1
            let s_ = c + w
            let w_ = c - 1
            if up and s < dist[n_]:
                dist[n_] = s
                next[n_] = c
                bs.push(n_)
                pending++
            if right and s < dist[e_]:
                dist[e_] = s
                next[e_] = c
                bs.push(e_)
                pending++
            if down and s < dist[s_]:
                dist[s_] = s
                next[s_] = c
                bs.push(s_)
                pending++
            if left and s < dist[w_]:
                dist[w_] = s
                next[w_] = c
                bs.push(w_)
                pending++
            if ne and walk[n_ + 1] == 1 and d < dist[n_ + 1]:
                dist[n_ + 1] = d
                next[n_ + 1] = c
                bd.push(n_ + 1)
                pending++
            if se and walk[s_ + 1] == 1 and d < dist[s_ + 1]:
                dist[s_ + 1] = d
                next[s_ + 1] = c
                bd.push(s_ + 1)
                pending++
            if sw and walk[s_ - 1] == 1 and d < dist[s_ - 1]:
                dist[s_ - 1] = d
                next[s_ - 1] = c
                bd.push(s_ - 1)
                pending++
            if nw and walk[n_ - 1] == 1 and d < dist[n_ - 1]:
                dist[n_ - 1] = d
                next[n_ - 1] = c
                bd.push(n_ - 1)
                pending++
        bucket.remove_range(0, bucket.length)
        cost++
    for(ring) b: b.remove_range(0, b.length)  // (a cutoff can leave some queued)
    return Flow { srcs, cutoff, pops, dist, next }

// The walkable cell closest to `cell` (itself if walkable). Ties go to the lower index.
def nearest_walkable(cell:int, k:int) -> int:
    if walks[k][cell] == 1: return cell
    let cx = cell % W
    let cy = cell / W
    var r = 1
    while r < max(W, H):
        var best = -1
        var best_d2 = INF
        var y = cy - r
        while y <= cy + r:
            var x = cx - r
            while x <= cx + r:
                if max(abs(x - cx), abs(y - cy)) == r and cell_walkable(x, y, k):
                    let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                    if d2 < best_d2:
                        best_d2 = d2
                        best = y * W + x
                x++
            y++
        if best >= 0: return best
        r++
    assert false
    return -1

def clear_line(ax:int, ay:int, bx:int, by:int, k:int) -> bool:
    let dx = bx - ax
    let dy = by - ay
    let steps = max(abs(dx), abs(dy)) / LINE_STEP + 1
    var px = ax
    var py = ay
    var i = 1
    while i <= steps:
        let x = ax + dx * i / steps
        let y = ay + dy * i / steps
        if not walkable(x, y, k): return false
        if x / TILE != px / TILE and y / TILE != py / TILE and not (walkable(x, py, k) and walkable(px, y, k)):
            return false
        px = x
        py = y
        i++
    return true

def open_box(tg:[int], cw:int, cx0:int, cy0:int, cx1:int, cy1:int) -> bool:
    let xb0 = cx0 / ROOM_CHUNK
    let xb1 = cx1 / ROOM_CHUNK
    var yb = cy0 / ROOM_CHUNK
    let yb1 = cy1 / ROOM_CHUNK
    while yb <= yb1:
        let row = yb * cw
        var xb = xb0
        while xb <= xb1:
            if tg[row + xb] != 0: return false
            xb++
        yb++
    return true

def blocked(walk:[int], w:int, h:int, x:int, y:int) -> bool:
    if x < 0 or y < 0: return true
    let cx = x / TILE
    let cy = y / TILE
    return cx >= w or cy >= h or walk[cy * w + cx] == 0

def clear_walk(walk:[int], room:[int], w:int, h:int, ax:int, ay:int, bx:int, by:int, r:int) -> bool:
    let dx = bx - ax
    let dy = by - ay
    let len = max(1, isqrt(dx * dx + dy * dy))
    let ox = -dy * r / len
    let oy = dx * r / len
    let steps = max(abs(dx), abs(dy)) / LINE_STEP + 1
    var px = ax
    var py = ay
    var i = 1
    while i <= steps:
        let x = ax + dx * i / steps
        let y = ay + dy * i / steps
        i++
        var cx = x / TILE
        var cy = y / TILE
        if x < 0 or y < 0 or cx >= w or cy >= h or walk[cy * w + cx] == 0: return false
        if room[cy * w + cx] == 1:
            px = x
            py = y
            continue
        var sx = x + ox
        var sy = y + oy
        cx = sx / TILE
        cy = sy / TILE
        if sx < 0 or sy < 0 or cx >= w or cy >= h or walk[cy * w + cx] == 0: return false
        sx = x - ox
        sy = y - oy
        cx = sx / TILE
        cy = sy / TILE
        if sx < 0 or sy < 0 or cx >= w or cy >= h or walk[cy * w + cx] == 0: return false
        if x / TILE != px / TILE and y / TILE != py / TILE and (blocked(walk, w, h, x, py) or blocked(walk, w, h, px, y)):
            return false
        px = x
        py = y
    return true

def clear_path(ax:int, ay:int, bx:int, by:int, r:int, k:int) -> bool:
    let w = W
    let h = H
    if ax >= 0 and ay >= 0 and bx >= 0 and by >= 0 and ax < w * TILE and bx < w * TILE and ay < h * TILE and by < h * TILE and open_box(tight[k], room_cw, min(ax, bx) / TILE, min(ay, by) / TILE, max(ax, bx) / TILE, max(ay, by) / TILE):
        return true
    return clear_walk(walks[k], roomy[k], w, h, ax, ay, bx, by, r)

// The furthest of the next n cells down field f from `cell` a body of radius r at (x, y) walks to
// in a straight line; -2 - the last clear cell if the walk reached a source.
def ahead(f:Flow, cell:int, x:int, y:int, n:int, r:int, k:int) -> int:
    let room = roomy[k]
    let walk = walks[k]
    let tg = tight[k]
    let cw = room_cw
    let w = W
    let h = H
    let dist = f.dist
    let nxt = f.next
    let inside = x >= 0 and y >= 0 and x < w * TILE and y < h * TILE
    var cx0 = x / TILE
    var cy0 = y / TILE
    var cx1 = cx0
    var cy1 = cy0
    var best = cell
    var c = nxt[cell]
    for(n):
        if c < 0: break
        if dist[c] == 0: return -2 - best
        let gx = c % w
        let gy = c / w
        cx0 = min(cx0, gx)
        cy0 = min(cy0, gy)
        cx1 = max(cx1, gx)
        cy1 = max(cy1, gy)
        var clear = inside and open_box(tg, cw, cx0, cy0, cx1, cy1)
        if not clear and inside:
            clear = open_box(tg, cw, min(x / TILE, gx), min(y / TILE, gy), max(x / TILE, gx), max(y / TILE, gy))
        if not clear and not clear_walk(walk, room, w, h, x, y, gx * TILE + TILE / 2, gy * TILE + TILE / 2, r):
            break
        best = c
        c = nxt[c]
    return best

def field_index(key:int) -> int:
    for(field_keys) k, n:
        if k == key: return n
    return -1

// The flow field for a key, or nil (and queued) if it isn't solved yet (World.field_for).
def field_for(key:int) -> Flow?:
    let n = field_index(key)
    if n >= 0: return field_vals[n]
    var queued = false
    for(field_queue) k:
        if k == key: queued = true
    if not queued: field_queue.push(key)
    return nil

def solve_queued():
    var spent = 0
    while field_queue.length > 0 and (spent == 0 or spent < SOLVE_BUDGET):
        let key = field_queue.remove(0)
        if field_index(key) >= 0: continue
        let mc = key % LANES
        let target = key / (LANES * 4)
        let kind = (key / LANES) % 4
        var sources = []::int
        if kind == FIELD_CELL or kind == FIELD_CELL_NEAR:
            sources.push(target)
        else:
            let b = b_index_of(target)
            if b >= 0: sources = footprint(b)
            else:
                for(br_id) v, k:
                    if v == target: sources = br_cells[k]
        let near = kind == FIELD_CELL_NEAR or kind == FIELD_BUILDING_NEAR
        let f = solve(sources, if near: NEAR_CUTOFF else: INF, mc)
        spent += max(f.pops, 1)
        field_keys.push(key)
        field_vals.push(f)
        if field_keys.length > max(24, FIELD_CACHE * num_players):
            field_keys.remove(0)
            field_vals.remove(0)

// ------------------------------------------------------------------ patching fields (flow.gd)
// The map changed under a cached field: lower or raise just the costs the change touches. The costs
// come out as a fresh solve's; where two ways cost the same, `next` may pick the other one.

var bad_mark = []::int  // patch_closed's set of cells, by generation
var bad_gen = 0

// The cost of the field spreading from c to its neighbour n (n walkable): straight 10, diagonal 14
// if both cells beside the corner are open, or always from a blocked source; 0 if not allowed.
def step_cost(f:Flow, walk:[int], c:int, n:int) -> int:
    let dx = n % W - c % W
    let dy = n / W - c / W
    if dx == 0 or dy == 0: return STRAIGHT
    if walk[c] == 0 and f.dist[c] == 0: return DIAGONAL
    if walk[c + dx] == 1 and walk[c + dy * W] == 1: return DIAGONAL
    return 0

// Give cell s the best cost its neighbours offer (within the cutoff); true if that lowered it.
def relax_from_neighbours(f:Flow, walk:[int], s:int) -> bool:
    let dist = f.dist
    let sx = s % W
    let sy = s / W
    var lowered = false
    var ny = max(sy - 1, 0)
    while ny < min(sy + 2, H):
        var nx = max(sx - 1, 0)
        while nx < min(sx + 2, W):
            let n = ny * W + nx
            if n != s and dist[n] < INF and dist[n] <= f.max_cost:
                let st = step_cost(f, walk, n, s)
                if st > 0 and dist[n] + st < dist[s]:
                    dist[s] = dist[n] + st
                    f.next[s] = n
                    lowered = true
            nx++
        ny++
    return lowered

// Spread lowered costs from the seeds outwards, cheapest first, each cell expanded once at its final
// cost, within the cutoff. The cells expanded, or -1 past `limit`.
def spread(f:Flow, walk:[int], seeds:[int], limit:int) -> int:
    let dist = f.dist
    let next = f.next
    let order = []::int
    for(seeds) c:
        if dist[c] <= f.max_cost: order.push(dist[c] * (1 << 20) + c)
    if not order.length: return 0
    sort_ints(order)
    let w = W
    let h = H
    var pending = 0
    var fed = 0
    var done = 0
    var cost = order[0] >> 20
    while true:
        while fed < order.length and (order[fed] >> 20) == cost:
            ring[cost % RING].push(order[fed] & ((1 << 20) - 1))
            pending++
            fed++
        if pending == 0:
            if fed >= order.length: break
            cost = order[fed] >> 20
            continue
        let bucket = ring[cost % RING]
        var bi = 0
        while bi < bucket.length:
            let c = bucket[bi]
            bi++
            pending--
            if dist[c] != cost: continue
            done++
            if done > limit:
                for(ring) b: b.remove_range(0, b.length)
                return -1
            let cx = c % w
            let cy = c / w
            let up = cy > 0 and walk[c - w] == 1
            let down = cy < h - 1 and walk[c + w] == 1
            let left = cx > 0 and walk[c - 1] == 1
            let right = cx < w - 1 and walk[c + 1] == 1
            let s = cost + STRAIGHT
            let d = cost + DIAGONAL
            let more_s = s <= f.max_cost
            let more_d = d <= f.max_cost
            let bs = ring[s % RING]
            let bd = ring[d % RING]
            let n_ = c - w
            let e_ = c + 1
            let s_ = c + w
            let w_ = c - 1
            if up and s < dist[n_]:
                dist[n_] = s
                next[n_] = c
                if more_s:
                    bs.push(n_)
                    pending++
            if right and s < dist[e_]:
                dist[e_] = s
                next[e_] = c
                if more_s:
                    bs.push(e_)
                    pending++
            if down and s < dist[s_]:
                dist[s_] = s
                next[s_] = c
                if more_s:
                    bs.push(s_)
                    pending++
            if left and s < dist[w_]:
                dist[w_] = s
                next[w_] = c
                if more_s:
                    bs.push(w_)
                    pending++
            if up and right and walk[n_ + 1] == 1 and d < dist[n_ + 1]:
                dist[n_ + 1] = d
                next[n_ + 1] = c
                if more_d:
                    bd.push(n_ + 1)
                    pending++
            if down and right and walk[s_ + 1] == 1 and d < dist[s_ + 1]:
                dist[s_ + 1] = d
                next[s_ + 1] = c
                if more_d:
                    bd.push(s_ + 1)
                    pending++
            if down and left and walk[s_ - 1] == 1 and d < dist[s_ - 1]:
                dist[s_ - 1] = d
                next[s_ - 1] = c
                if more_d:
                    bd.push(s_ - 1)
                    pending++
            if up and left and walk[n_ - 1] == 1 and d < dist[n_ - 1]:
                dist[n_ - 1] = d
                next[n_ - 1] = c
                if more_d:
                    bd.push(n_ - 1)
                    pending++
        bucket.remove_range(0, bucket.length)
        cost++
    f.pops += done
    return done

// Cells opened (walkable now in lane k; none a source): lower the costs they shorten.
def patch_opened(f:Flow, cells:[int], k:int, limit:int) -> int:
    let walk = walks[k]
    let seeds = []::int
    for(cells) cell:
        let cx = cell % W
        let cy = cell / W
        var y = max(cy - 1, 0)
        while y < min(cy + 2, H):
            var x = max(cx - 1, 0)
            while x < min(cx + 2, W):
                let s = y * W + x
                if walk[s] == 1 and f.dist[s] != 0 and relax_from_neighbours(f, walk, s): seeds.push(s)
                x++
            y++
    return spread(f, walk, seeds, limit)

// Cells closed (blocked now in lane k; none a source): every cell whose way ran through one loses its
// cost, then takes the best its neighbours still offer. The cells reset and settled, or -1 past `limit`.
def patch_closed(f:Flow, cells:[int], k:int, limit:int) -> int:
    let walk = walks[k]
    let dist = f.dist
    let next = f.next
    if bad_mark.length != W * H: bad_mark = map(W * H): 0
    bad_gen++
    let queue = []::int
    for(cells) cell:
        if bad_mark[cell] != bad_gen and dist[cell] < INF:
            bad_mark[cell] = bad_gen
            queue.push(cell)
        let cx = cell % W
        let cy = cell / W
        var y = max(cy - 1, 0)
        while y < min(cy + 2, H):
            var x = max(cx - 1, 0)
            while x < min(cx + 2, W):
                let s = y * W + x
                x++
                if bad_mark[s] == bad_gen or next[s] < 0: continue
                let t = next[s]
                if (walk[t] == 0 and dist[t] != 0) or walk[s] == 0 or step_cost(f, walk, t, s) == 0:
                    bad_mark[s] = bad_gen
                    queue.push(s)
            y++
    var head = 0
    while head < queue.length:
        if queue.length > limit: return -1
        let c = queue[head]
        head++
        let x0 = c % W
        let y0 = c / W
        var ny = max(y0 - 1, 0)
        while ny < min(y0 + 2, H):
            var nx = max(x0 - 1, 0)
            while nx < min(x0 + 2, W):
                let n = ny * W + nx
                if next[n] == c and bad_mark[n] != bad_gen:
                    bad_mark[n] = bad_gen
                    queue.push(n)
                nx++
            ny++
    for(queue) c:
        dist[c] = INF
        next[c] = -1
    let seeds = []::int
    for(queue) c:
        if walk[c] == 1 and relax_from_neighbours(f, walk, c): seeds.push(c)
    let sp = spread(f, walk, seeds, limit - queue.length)
    return if sp < 0: -1 else: queue.length + sp

// Does a change at `cell` possibly alter this field? Only if the solve reached it or a neighbour.
def touches(f:Flow, cell:int) -> bool:
    let cx = cell % W
    let cy = cell / W
    var y = max(cy - 1, 0)
    while y < min(cy + 2, H):
        var x = max(cx - 1, 0)
        while x < min(cx + 2, W):
            if f.dist[y * W + x] < INF: return true
            x++
        y++
    return false
