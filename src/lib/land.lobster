// ------------------------------------------------------------------ the land as a bot reads it (src/ai/land.gd, routes.gd)
// Whole-map route searches (a bucket-ring Dijkstra over a price per cell), a few "studies" kept
// fresh one search at a time: our army's way to its target (and a detour round enemy fire over it,
// a flank for amphibians), the enemy's way to us (its crossing is the key crossing a tower may
// guard), roads through thin woods felled by workers, ranged soldiers stepping up onto hills.
// Bridges: one down that would shorten our way a lot (or is the only way) gets rebuilt; a standing one
// whose loss makes their way much longer is broken when we're outnumbered or swim.

let ROUTE_INF = 1 << 30
let ROUTE_STEP = 10
let ROUTE_RING = 1024
let RDX = [ 0, 1, 0, -1, 1, 1, -1, -1 ]  // N, E, S, W, then the diagonals
let RDY = [ -1, 0, 1, 0, -1, 1, 1, -1 ]

// The price per cell for lane ln (0: can't): open ground STEP, slower ground dearer, and with
// `tree` > 0, trees standing on it at that price (felled, they'd open: a road).
def route_prices(ln:int, tree:int) -> [int]:
    let walk = walks[ln]
    let cls = ln % 3
    let speed = speed_pct[cls]
    let tree_t = terrain_named("tree")
    return map(W * H) c:
        if walk[c] == 1: (if deck[c] == 0: ROUTE_STEP * 100 / max(10, speed[c]) else: ROUTE_STEP)
        elif tree > 0 and terrain[c] == tree_t and amount[c] > 0 and occupied[c] == 0 and not (has_heights and cliff[c] == 1): tree
        else: 0

class Search:
    dist:[int]
    prev:[int]
    price:[int]
    open:[int]
    ring:[[int]]
    pending:int
    cost:int
    head:int

def new_search(price:[int], open:[int], src:int) -> Search:
    let dist = map(W * H): ROUTE_INF
    let prev = map(W * H): -1
    let rring = map(ROUTE_RING): []::int
    dist[src] = 0
    rring[0].push(src)
    return Search { dist, prev, price, open, rring, 1, 0, 0 }

// Settle up to `budget` cells; true once the search is done (Routes.Search.step).
def search_step(s:Search, budget0:int) -> bool:
    var budget = budget0
    let steps = [ -W, 1, W, -1, -W + 1, W + 1, W - 1, -W - 1 ]
    let dist = s.dist
    let open = s.open
    let price = s.price
    while s.pending > 0 and budget > 0:
        let bucket = s.ring[s.cost % ROUTE_RING]
        while s.head < bucket.length and budget > 0:
            let c = bucket[s.head]
            s.head++
            s.pending--
            if dist[c] == s.cost:
                budget--
                let cx = c % W
                let cy = c / W
                let up = cy > 0
                let down = cy < H - 1
                let left = cx > 0
                let right = cx < W - 1
                let ok = [ up, right, down, left,
                           up and right and open[c - W] == 1 and open[c + 1] == 1,
                           down and right and open[c + W] == 1 and open[c + 1] == 1,
                           down and left and open[c + W] == 1 and open[c - 1] == 1,
                           up and left and open[c - W] == 1 and open[c - 1] == 1 ]
                for(8) d:
                    if ok[d]:
                        let nc = c + steps[d]
                        let p = price[nc]
                        if p > 0 and not (d >= 4 and open[nc] == 0):
                            let nd = s.cost + (if d >= 4: p * 14 / 10 else: p)
                            if nd < dist[nc]:
                                dist[nc] = nd
                                s.prev[nc] = c
                                s.ring[nd % ROUTE_RING].push(nc)
                                s.pending++
        if s.head >= bucket.length:
            bucket.remove_range(0, bucket.length)
            s.head = 0
            s.cost++
    return s.pending <= 0

def route_path(s:Search, to:int) -> [int]:
    if to < 0 or s.dist[to] >= ROUTE_INF: return []::int
    let out = []::int
    var c = to
    while c >= 0:
        out.push(c)
        c = s.prev[c]
    return reverse_list(out)

def cheapest(s:Search, cells:[int]) -> int:
    var best = -1
    for(cells) c:
        if s.dist[c] < ROUTE_INF and (best < 0 or s.dist[c] < s.dist[best] or (s.dist[c] == s.dist[best] and c < best)): best = c
    return best

def ring_round(open:[int], cx:int, cy:int, r:int) -> [int]:
    let out = []::int
    var y = max(0, cy - r)
    while y < min(H, cy + r + 1):
        var x = max(0, cx - r)
        while x < min(W, cx + r + 1):
            if open[y * W + x] == 1: out.push(y * W + x)
            x++
        y++
    return out

def terrain_named(id:string) -> int:
    for(tr_names) n, k:
        if n == id: return k
    return -1

class Land:
    crossings_kind:[int] = []    // 0 ford, 1 bridge
    crossings_bridge:[int] = []  // a bridge's slot, or -1
    mend:[int] = []              // bridge slots worth rebuilding (studied)
    cut:[int] = []               // bridge slots worth breaking (studied)
    broke:[int] = []             // bridge slots we broke on purpose (never mended for a shortcut)
    breakers:[int] = []          // soldier ids sent at a bridge
    bridge_next = 0
    crossings_centre:[int] = []
    crossings_cells:[[int]] = []
    made = false
    done_names:[string] = []  // study -> the tick it was last made
    done_ticks:[int] = []
    next_study = 0
    target_x = -1  // what our army goes for: routes lead there
    target_y = -1
    our_cost = 1 << 30
    our_path:[int] = []
    our_start_cost = 1 << 30
    their_cost = 1 << 30
    key = -1
    key_side = -1
    detour_x = -1
    detour_y = -1
    flank_x = -1
    flank_y = -1
    road:[int] = []
    roads = 0
    fellers:[int] = []
    hill_ids:[int] = []  // unit id -> no hill order before this tick
    hill_until:[int] = []
    climbing_ids:[int] = []  // unit id -> on its way up a hill till then
    climbing_until:[int] = []
    want:[int] = []
    camp_laid = false
    camp_next = 0
    road_walk:Search? = nil
    job:Search? = nil
    job_key = ""

def land_crossings(l:Land) -> int:
    if l.made: return l.crossings_centre.length
    l.made = true
    let ford = terrain_named("ford")
    let seen = map(W * H): 0
    for(W * H) c:
        if ford >= 0 and terrain[c] == ford and seen[c] == 0:
            let cells = [ c ]
            seen[c] = 1
            var head = 0
            while head < cells.length:
                let at = cells[head]
                head++
                for(8) d:
                    let x = at % W + RDX[d]
                    let y = at / W + RDY[d]
                    if x >= 0 and y >= 0 and x < W and y < H and terrain[y * W + x] == ford and seen[y * W + x] == 0:
                        seen[y * W + x] = 1
                        cells.push(y * W + x)
            l.crossings_kind.push(0)
            l.crossings_bridge.push(-1)
            l.crossings_centre.push(cells_centre(cells))
            l.crossings_cells.push(cells)
    for(br_id.length) k:
        l.crossings_kind.push(1)
        l.crossings_bridge.push(k)
        l.crossings_centre.push(cells_centre(br_cells[k]))
        l.crossings_cells.push(br_cells[k])
    return l.crossings_centre.length

def cells_centre(cells:[int]) -> int:
    var sx = 0
    var sy = 0
    for(cells) c:
        sx += c % W
        sy += c / W
    let x = sx / cells.length
    let y = sy / cells.length
    var best = cells[0]
    for(cells) c:
        if abs(c % W - x) + abs(c / W - y) < abs(best % W - x) + abs(best / W - y): best = c
    return best

def done_at(l:Land, name:string) -> int:
    for(l.done_names) n, k:
        if n == name: return l.done_ticks[k]
    return -1

def mark_done(l:Land, name:string):
    for(l.done_names) n, k:
        if n == name:
            l.done_ticks[k] = tick
            return
    l.done_names.push(name)
    l.done_ticks.push(tick)

def due(l:Land, name:string, every:int) -> bool:
    let t = done_at(l, name)
    return t < 0 or tick - t >= every * 20

// The finished search for study `key`, or nil while it runs: the first call starts it, every call
// settles another search_cells cells. One at a time.
def land_search(l:Land, key:string, open:[int], src:int, prices:[int]) -> Search?:
    if l.job_key != key or not l.job:
        l.job = new_search(prices, open, src)
        l.job_key = key
    let s = l.job
    if not s: return nil
    if not search_step(s, cfg("land.search_cells")): return nil
    l.job = nil
    l.job_key = ""
    return s

def open_near(ln:int, cell:int) -> int:
    let walk = walks[ln]
    let cx = cell % W
    let cy = cell / W
    for(5) r:
        var dy = -r
        while dy <= r:
            var dx = -r
            while dx <= r:
                if max(abs(dx), abs(dy)) == r:
                    let x = cx + dx
                    let y = cy + dy
                    let at = y * W + x  // (in a local: the --mir JIT misreads W in this and-chain, see area_at)
                    if x >= 0 and y >= 0 and x < W and y < H and walk[at] == 1: return at
                dx++
            dy++
    return -1

def open_toward(ln:int, cell:int, tx:int, ty:int) -> int:
    let walk = walks[ln]
    var best = -1
    var best_d = 1 << 30
    var y = max(0, cell / W - 3)
    while y < min(H, cell / W + 4):
        var x = max(0, cell % W - 3)
        while x < min(W, cell % W + 4):
            let d = (x - tx) * (x - tx) + (y - ty) * (y - ty)
            if walk[y * W + x] == 1 and d < best_d:
                best_d = d
                best = y * W + x
            x++
        y++
    return if best >= 0: best else: open_near(ln, cell)

def enemy_lane(p:int) -> int:
    var es = -1
    for(num_players) q:
        if es < 0 and is_enemy(p, q) and defeated[q] == 0: es = q
    if es < 0: return -1
    let k = type_named(es, "spear")
    return lane_base[es] + (if k >= 0: t_mclass[k] else: 0)

def enemy_start(p:int, hx:int, hy:int) -> int, int:
    var bx = -1
    var by = -1
    for(num_players) q:
        if is_enemy(p, q) and defeated[q] == 0 and q < start_x.length:
            if bx < 0 or dist2(hx, hy, start_x[q], start_y[q]) < dist2(hx, hy, bx, by):
                bx = start_x[q]
                by = start_y[q]
    return bx, by

def key_from(l:Land, path:[int]):
    l.key = -1
    l.key_side = -1
    for(path) c, n:
        if l.key < 0:
            for(l.crossings_cells) cells, k:
                if l.key < 0 and contains(cells, c):
                    l.key = k
                    l.key_side = path[max(0, n - 1)]

// Why we may cut their way (Land._may_cut): 2, we swim; 1, they outnumber us; 0, no reason (or no army of theirs).
def may_cut(bot:Bot, army:[int]) -> int:
    var theirs = 0
    for(bot.scout.seen_kind) k: theirs += t_pop[k]
    if theirs < cfg("land.cut_enemy"): return 0
    if bot.aln % 3 == 1: return 2
    return if defending(bot, army): 1 else: 0

def enemies_near(p:int, x:int, y:int, r:int) -> bool:
    for(u_x.length) i:
        if is_foe(p, u_owner[i]) and not t_worker[u_kind[i]] and fog_visible(p, u_x[i], u_y[i]) and dist2(x, y, u_x[i], u_y[i]) <= r * r: return true
    return false

// Mend a bridge worth mending (two workers, if it's quiet there and we can pay), break one worth
// breaking (melee soldiers idle at home). Every few seconds (Land._bridges).
def land_bridges(l:Land, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    if not br_id.length or tick < l.bridge_next: return
    l.bridge_next = tick + 100
    let p = bot.player
    for(br_id) id, k:
        let ax = br_x0[k] + (br_x1[k] - br_x0[k]) / 2
        let ay = br_y0[k] + (br_y1[k] - br_y0[k]) / 2
        if br_up[k] == 0 and contains(l.mend, k) and (br_payer[k] < 0 or br_payer[k] == p) and not enemies_near(p, ax, ay, 8000) and
                (br_payer[k] == p or can_afford(p, br_cost)):
            var on = 0
            for(workers) i:
                if u_task[i] == BUILD and u_target[i] == id: on++
            if on < 2:
                let ids = nearest_workers(bot, workers, ax, ay, 2 - on)
                if ids.length: issue_cmd(p, CMD_HELP_BUILD, ids, id, 0, 0, 0)
        if br_up[k] == 1 and contains(l.cut, k):
            l.breakers = filter(l.breakers) b: index_of(b) >= 0 and u_foe[index_of(b)] == id
            if not (l.breakers.length >= cfg("land.breakers") or bot.assault):
                let keys = []::int
                for(army) i:
                    if not t_ranged[u_kind[i]] and u_foe[i] == 0 and not is_escort(bot.expand, u_id[i]) and dist2(hx, hy, u_x[i], u_y[i]) <= 400 * 1000000:
                        keys.push(i)
                let ds = map(keys) i: dist2(u_x[i], u_y[i], ax, ay)
                let order = map(keys.length) n: n
                insertion_sort(order) a, b: ds[a] < ds[b] or (ds[a] == ds[b] and u_id[keys[a]] < u_id[keys[b]])
                let ids = map(slice(order, 0, max(0, min(cfg("land.breakers") - l.breakers.length, order.length)))) n: u_id[keys[n]]
                if ids.length + l.breakers.length >= cfg("land.breakers") / 2 and ids.length:
                    issue_cmd(p, CMD_ATTACK, ids, id, 0, 0, 0)
                    for(ids) x: l.breakers.push(x)
                    if not contains(l.broke, k): l.broke.push(k)

// Is unit i one of ours at work breaking a bridge (kept out of the waves meanwhile)?
def land_breaking(l:Land, i:int) -> bool:
    return contains(l.breakers, u_id[i]) and u_foe[i] != 0 and bridge_index(u_foe[i]) >= 0

def defending(bot:Bot, army:[int]) -> bool:
    var ours = 0
    for(army) i: ours += t_pop[u_kind[i]]
    var theirs = 0
    for(bot.scout.seen_kind) k: theirs += t_pop[k]
    return theirs * 100 > ours * cfg("land.defend_pct")

// The cell of p furthest (Chebyshev) src every cell of `src`, as a point, if at least min_d.
def furthest(p:[int], src:[int], min_d:int) -> int, int:
    var best = -1
    var best_d = -1
    for(p) c:
        var d = 1 << 20
        for(src) q: d = min(d, max(abs(c % W - q % W), abs(c / W - q / W)))
        if d > best_d:
            best_d = d
            best = c
    if best < 0 or best_d < min_d: return -1, -1
    return best % W * 1000 + 500, best / W * 1000 + 500

// Round enemy fire over our way (Land._detour). (-1, -1): none needed; (-1, -2): still searching.
def detour_point(l:Land, bot:Bot, ln:int, src:int, goal:[int]) -> int, int:
    let extra = map(W * H): 0
    if has_heights:
        for(bot.scout.seen_kind) k, n:
            if t_ranged[k]:
                let c = cell_of(bot.scout.seen_x[n], bot.scout.seen_y[n])
                let lv = level[c] + (if ramp[c] == 1: 1 else: 0)
                if lv > 0:
                    let r = t_reach[k] / 1000 + 2
                    var y = max(0, c / W - r)
                    while y < min(H, c / W + r + 1):
                        var x = max(0, c % W - r)
                        while x < min(W, c % W + r + 1):
                            if level[y * W + x] < lv: extra[y * W + x] = cfg("land.under_fire")
                            x++
                        y++
    let keep = cfg("land.target_tiles")
    for(sorted_seen(bot.player)) s:
        let k = s[1]
        if is_enemy(bot.player, s[2]) and bt_attacks[k] and s[6] != 0:
            let cx = s[3] + s[5] / 2
            let cy = s[4] + s[9] / 2
            if not (abs(cx * 1000 + 500 - l.target_x) <= keep * 1000 and abs(cy * 1000 + 500 - l.target_y) <= keep * 1000):
                let r = bt_range[k] + 1 + max(s[5], s[9]) / 2
                var y = max(0, cy - r)
                while y < min(H, cy + r + 1):
                    var x = max(0, cx - r)
                    while x < min(W, cx + r + 1):
                        if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r: extra[y * W + x] = cfg("land.under_fire")
                        x++
                    y++
    var any_fire = false
    for(l.our_path) c:
        if extra[c] > 0: any_fire = true
    if not any_fire: return -1, -1
    let price = route_prices(ln, 0)
    for(price) p, c:
        if p > 0: price[c] = p + extra[c]
    let s = land_search(l, "detour", walks[ln], src, price)
    if not s: return -1, -2
    let g = cheapest(s, goal)
    if g < 0: return -1, -1
    let p = route_path(s, g)
    var plain = 0
    var n = 1
    while n < p.length:
        plain += if p[n] % W == p[n - 1] % W or p[n] / W == p[n - 1] / W: ROUTE_STEP else: ROUTE_STEP * 14 / 10
        n++
    if plain * 100 > l.our_cost * (100 + cfg("land.detour_pct")): return -1, -1
    return furthest(p, l.our_path, 3)

// A second way to the goal kept `apart` cells off `path` (a flank): its waypoint furthest src it.
def off_route(l:Land, ln:int, src:int, goal:[int], path:[int], apart:int, pct:int) -> int, int:
    let price = route_prices(ln, 0)
    let near = map(W * H): 0
    for(slice(path, path.length / 5, path.length * 4 / 5 - path.length / 5)) c:
        var y = max(0, c / W - apart)
        while y < min(H, c / W + apart + 1):
            var x = max(0, c % W - apart)
            while x < min(W, c % W + apart + 1):
                near[y * W + x] = 1
                x++
            y++
    for(price) p, c:
        if near[c] == 1 and p > 0: price[c] = p + ROUTE_STEP * 4
    let s = land_search(l, "flank", walks[ln], src, price)
    if not s: return -1, -2
    let g = cheapest(s, goal)
    if g < 0: return -1, -1
    let p = route_path(s, g)
    if p.length * 100 > path.length * (100 + pct): return -1, -1
    return furthest(p, path, apart)

def plan_road(l:Land, bot:Bot, hx:int, hy:int):
    let ln = bot.eco.wln
    let src = open_toward(ln, cell_of(hx, hy), W / 2, H / 2)
    if src < 0: return
    if not l.road_walk:
        l.road_walk = land_search(l, "road_walk", walks[ln], src, route_prices(ln, 0))
        return
    let esx, esy = enemy_start(bot.player, hx, hy)
    let tree = cfg("land.road.tree")
    let price = route_prices(ln, tree)
    for(price) p, c:
        if p == tree and walks[ln][c] == 0 and esx >= 0:
            let x = c % W * 1000 + 500
            let y = c / W * 1000 + 500
            if dist2(x, y, hx, hy) * 100 > dist2(x, y, esx, esy) * cfg("land.road.side_pct"): price[c] = 0
    let cut_ = land_search(l, "road_cut", walks[ln], src, price)
    if not cut_: return
    mark_done(l, "road")
    let walk = l.road_walk
    l.road_walk = nil
    if not walk: return
    let far = cfg("land.road.far")
    var best = -1
    var best_save = 0
    for(W * H) g:
        if walks[ln][g] == 1 and abs(g % W - hx / 1000) + abs(g / W - hy / 1000) >= far:
            let a = walk.dist[g]
            let b = cut_.dist[g]
            if not (b >= ROUTE_INF or a >= ROUTE_INF or a <= b):
                let save = a - b
                if save >= cfg("land.road.save") * ROUTE_STEP and save * 100 >= a * cfg("land.road.pct") and save > best_save:
                    var trees = 0
                    for(route_path(cut_, g)) c:
                        if walks[ln][c] == 0: trees++
                    if trees >= 1 and trees <= cfg("land.road.trees"):
                        best_save = save
                        best = g
    if best < 0: return
    l.road = filter(route_path(cut_, best)) c: walks[ln][c] == 0
    l.roads++
    l.camp_laid = false

// One study a time, the first that's due (Land._study).
def land_study(l:Land, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    let ln = bot.aln
    let src = open_near(ln, cell_of(hx, hy))
    if src < 0 or l.target_x < 0: return
    let goal = ring_round(walks[ln], l.target_x / 1000, l.target_y / 1000, 3)
    if due(l, "ours", cfg("land.our_every")):
        let s = land_search(l, "ours", walks[ln], src, route_prices(ln, 0))
        if not s: return
        mark_done(l, "ours")
        let g = cheapest(s, goal)
        l.our_cost = if g >= 0: s.dist[g] else: ROUTE_INF
        l.our_path = route_path(s, g)
        let esx, esy = enemy_start(bot.player, hx, hy)
        let gs = if esx >= 0: cheapest(s, ring_round(walks[ln], esx / 1000, esy / 1000, 3)) else: -1
        l.our_start_cost = if gs >= 0: s.dist[gs] else: ROUTE_INF
        return
    let eln = enemy_lane(bot.player)
    if eln >= 0 and due(l, "theirs", cfg("land.their_every")):
        let efrom = open_near(eln, cell_of(hx, hy))
        let esx, esy = enemy_start(bot.player, hx, hy)
        if efrom < 0 or esx < 0:
            mark_done(l, "theirs")
            return
        let s = land_search(l, "theirs", walks[eln], efrom, route_prices(eln, 0))
        if not s: return
        mark_done(l, "theirs")
        let g = cheapest(s, ring_round(walks[eln], esx / 1000, esy / 1000, 3))
        l.their_cost = if g >= 0: s.dist[g] else: ROUTE_INF
        key_from(l, route_path(s, g))
        return
    // Bridges: one what-if each (a standing one gone, for them; a broken one back, for us).
    for(br_id.length) k:
        let name = "bridge{k}"
        if due(l, name, cfg("land.bridge_every")):
            if br_up[k] == 1:
                let why = may_cut(bot, army)
                if eln < 0 or l.their_cost >= ROUTE_INF or why == 0:
                    l.cut = filter(l.cut) v: v != k
                    mark_done(l, name)
                else:
                    let esx, esy = enemy_start(bot.player, hx, hy)
                    let efrom = open_near(eln, cell_of(hx, hy))
                    let price = route_prices(eln, 0)
                    for(br_cells[k]) c: price[c] = 0
                    let s = land_search(l, name, walks[eln], efrom, price)
                    if not s: return
                    mark_done(l, name)
                    l.cut = filter(l.cut) v: v != k
                    let g = cheapest(s, ring_round(walks[eln], esx / 1000, esy / 1000, 3))
                    let without = if g >= 0: s.dist[g] else: ROUTE_INF
                    if without >= ROUTE_INF or without * 100 >= l.their_cost * (100 + cfg("land.cut_pct")): l.cut.push(k)
                    return
            else:
                let esx, esy = enemy_start(bot.player, hx, hy)
                if (contains(l.broke, k) and l.our_start_cost < ROUTE_INF) or esx < 0:
                    l.mend = filter(l.mend) v: v != k  // (we broke it to cut their way: it stays down while we can get round)
                    mark_done(l, name)
                else:
                    let price = route_prices(ln, 0)
                    for(br_cells[k]) c: price[c] = ROUTE_STEP  // (as if it stood again)
                    let s = land_search(l, name, walks[ln], src, price)
                    if not s: return
                    mark_done(l, name)
                    l.mend = filter(l.mend) v: v != k
                    let g = cheapest(s, ring_round(walks[ln], esx / 1000, esy / 1000, 3))
                    let with = if g >= 0: s.dist[g] else: ROUTE_INF
                    if with < ROUTE_INF and (l.our_start_cost >= ROUTE_INF or with * 100 <= l.our_start_cost * (100 - cfg("land.mend_pct"))): l.mend.push(k)
                    return
            return
    if due(l, "detour", cfg("land.detour_every")) and l.our_path.length:
        let dx, dy = detour_point(l, bot, ln, src, goal)
        if dy == -2: return
        mark_done(l, "detour")
        l.detour_x = dx
        l.detour_y = dy
        return
    if bot.aln % 3 == 1 and due(l, "flank", cfg("land.flank_every")) and l.our_path.length:
        let fx, fy = off_route(l, ln, src, goal, l.our_path, cfg("land.flank_apart"), cfg("land.flank_pct"))
        if fy == -2: return
        mark_done(l, "flank")
        l.flank_x = fx
        l.flank_y = fy
        return
    if l.roads < cfg("land.road.max") and not l.road.length and workers.length >= cfg("land.road.workers") and due(l, "road", cfg("land.road.every")):
        plan_road(l, bot, hx, hy)

// Fell the road: up to road.fellers wood gatherers, each on the nearest standing road tree.
def fell(l:Land, bot:Bot, workers:[int]):
    if not l.road.length: return
    l.road = filter(l.road) c: amount[c] > 0
    l.fellers = filter(l.fellers) id: index_of(id) >= 0
    if not l.road.length:
        for(l.fellers) id: unhold(bot.eco, id)
        l.fellers = []::int
        l.want = []::int
        return
    let want = cfg("land.road.fellers")
    if l.fellers.length < want:
        let keys = []::int
        for(workers) i:
            if u_carry_kind[i] == 2 and u_task[i] == GATHER and not contains(l.fellers, u_id[i]) and held(bot.eco, u_id[i]) <= tick:
                keys.push(dist2(u_x[i], u_y[i], l.road[0] % W * 1000, l.road[0] / W * 1000) * (1 << 20) + u_id[i])
        sort_ints(keys)
        for(slice(keys, 0, min(keys.length, want - l.fellers.length))) k: l.fellers.push(k & ((1 << 20) - 1))
    road_camp(l, bot)
    for(l.fellers) id:
        let i = index_of(id)
        hold_until(bot.eco, id, tick + 60)
        if (u_task[i] == GATHER or u_task[i] == T_RETURN) and contains(l.road, if u_task[i] == GATHER: u_target[i] else: u_home[i]): continue
        if u_task[i] == T_RETURN or u_task[i] == BUILD: continue
        let area = area_of_unit(bot.eco.reach, i)
        var best = -1
        var best_d2 = 1 << 62
        let taken_cells = []::int
        for(l.fellers) other:
            let j = index_of(other)
            if other != id and j >= 0 and u_task[j] == GATHER: taken_cells.push(u_target[j])
        for(l.road) c:
            let d2 = dist2(u_x[i], u_y[i], c % W * 1000 + 500, c / W * 1000 + 500)
            if d2 < best_d2 and not (contains(taken_cells, c) and l.road.length > 1) and reaches_cell(bot.eco.reach, bot.eco.wln, area, c):
                best_d2 = d2
                best = c
        if best >= 0: issue_cmd(bot.player, 3, [ id ], best, 0, 0, 0)

def road_camp(l:Land, bot:Bot):
    if l.camp_laid or not l.fellers.length or not l.road.length: return
    let x = l.road[0] % W
    let y = l.road[0] / W
    let r = cfg("land.road.camp")
    for(b_id.length) b:
        if b_owner[b] == bot.player and bt_drop[b_kind[b]][1] == 1 and abs(b_cx[b] - x) <= r + 1 and abs(b_cy[b] - y) <= r + 1:
            l.camp_laid = true
            l.want = []::int
            return
    let k = camp_for(resource_index("wood"))
    if k < 0:
        l.camp_laid = true
        return
    if not can_afford(bot.player, bm_cost[bot.player][k]):
        l.want = bm_cost[bot.player][k]
        return
    if tick < l.camp_next: return
    l.camp_next = tick + 200
    let sx, sy = spot_near(bot, x, y, bt_size[k], r, l.road)
    if sx < 0:
        l.camp_laid = true
        l.want = []::int
        return
    issue_cmd(bot.player, 4, [ l.fellers[0] ], k, sx, sy, 0)

def is_climbing(l:Land, i:int) -> bool:
    for(l.climbing_ids) id, n:
        if id == u_id[i]: return l.climbing_until[n] > tick
    return false

// The nearest cell (by 4-neighbour steps) of open ground above `here` and no lower than `top`.
def climb_cell(walk:[int], src:int, here:int, top:int, r:int) -> int:
    let x0 = max(0, src % W - r - 2)
    let y0 = max(0, src / W - r - 2)
    let x1 = min(W - 1, src % W + r + 2)
    let y1 = min(H - 1, src / W + r + 2)
    let steps = dictionary<int, int>(251)
    steps.set(src, 0)
    let queue = [ src ]
    var head = 0
    while head < queue.length:
        let c = queue[head]
        head++
        if level[c] > here and level[c] >= top and ramp[c] == 0 and walk[c] == 1: return c
        if steps.get(c, 0) < 2 * r:
            for(4) d:
                let x = c % W + RDX[d]
                let y = c / W + RDY[d]
                let n = y * W + x
                if not (x < x0 or y < y0 or x > x1 or y > y1) and walk[n] != 0 and steps.get(n, -1) < 0:
                    steps.set(n, steps.get(c, 0) + 1)
                    queue.push(n)
    return -1

// Ranged soldiers meeting an army step up onto higher ground near them (Land._hills).
def hills(l:Land, bot:Bot, army:[int]):
    if not has_heights or tick % (cfg("land.hills.every_check") * 20) != bot_phase(bot): return
    var n = l.climbing_ids.length - 1
    while n >= 0:
        if l.climbing_until[n] <= tick:
            l.climbing_ids.remove(n)
            l.climbing_until.remove(n)
        n--
    let foes = []::int
    for(u_x.length) i:
        if is_foe(bot.player, u_owner[i]) and not t_worker[u_kind[i]] and t_animal[u_kind[i]] == 0 and fog_visible(bot.player, u_x[i], u_y[i]): foes.push(i)
    if foes.length < cfg("land.hills.army"): return
    let near = cfg("land.hills.near") * 1000
    let cells = []::int
    let ids = []::[int]
    for(army) i:
        let k = u_kind[i]
        var next_ok = true
        for(l.hill_ids) id, q:
            if id == u_id[i] and l.hill_until[q] > tick: next_ok = false
        if t_ranged[k] and next_ok and not is_escort(bot.expand, u_id[i]):
            var close = 0
            var top = 0
            for(foes) j:
                if dist2(u_x[i], u_y[i], u_x[j], u_y[j]) <= near * near:
                    close++
                    top = max(top, level[cell_of(u_x[j], u_y[j])])
            let here = level[cell_of(u_x[i], u_y[i])]
            if close >= cfg("land.hills.army") and here <= top:
                let best = climb_cell(walks[lane(i)], cell_of(u_x[i], u_y[i]), here, top, cfg("land.hills.tiles"))
                set_pair(l.hill_ids, l.hill_until, u_id[i], tick + cfg("land.hills.every") * 20)
                if best >= 0:
                    set_pair(l.climbing_ids, l.climbing_until, u_id[i], tick + cfg("land.hills.every") * 20)
                    var at = -1
                    for(cells) c, q:
                        if c == best: at = q
                    if at < 0:
                        cells.push(best)
                        ids.push([ u_id[i] ])
                    else:
                        ids[at].push(u_id[i])
    let order = map(cells) c, q: c * (1 << 20) + q
    sort_ints(order)
    for(order) o:
        let c = o >> 20
        issue_cmd(bot.player, 0, ids[o & ((1 << 20) - 1)], c % W * 1000 + 500, c / W * 1000 + 500, 0, 0)

def set_pair(ids:[int], vals:[int], id:int, v:int):
    for(ids) x, n:
        if x == id:
            vals[n] = v
            return
    ids.push(id)
    vals.push(v)

// The spot for a Watchtower guarding the key crossing on our side, or (-1, -1).
def guard_spot(l:Land, bot:Bot) -> int, int:
    if l.key < 0 or l.key_side < 0: return -1, -1
    let x = l.key_side % W
    let y = l.key_side / W
    let tc = town_center(bot.player)
    if tc >= 0 and max(abs(b_cx[tc] + 1 - x), abs(b_cy[tc] + 1 - y)) > cfg("land.guard_range"): return -1, -1
    let r = cfg("land.guard_tiles")
    for(b_id.length) b:
        if b_owner[b] == bot.player and has_role(b_kind[b], ROLE_DEFENCE) and abs(b_cx[b] - x) <= r and abs(b_cy[b] - y) <= r:
            return -1, -1
    return x, y

// Once a second, src the bot's think (Land.think).
def land_think(l:Land, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    land_crossings(l)
    fell(l, bot, workers)
    if l.job or tick >= l.next_study:
        if not l.job: l.next_study = tick + cfg("land.study_every") * 20
        land_study(l, bot, workers, army, hx, hy)
    land_bridges(l, bot, workers, army, hx, hy)
    hills(l, bot, army)
