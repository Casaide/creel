// ------------------------------------------------------------------ the economy bot (src/ai/eco_bot.gd, reach.gd)
// A scripted economy player: keeps the Town Center training workers, splits them between
// resources by a mix (60/40 food/wood in age 1), puts idle workers back to work, builds houses
// before pop runs out, farms as the wild food runs out, a barracks and then the age-up. It reads
// the state and issues commands like a player (issue_cmd: they run two turns later).
// Left out: animals (herding, pens, hunting: the scenarios have none, asserted), the full bot's
// hold, goals and rebalancing (EcoBot's defaults: off), sheltering workers.

let THINK_EVERY = 20
let STAGGER = 2
let MAX_WORKERS = 30
let TRAIN_COOLDOWN = 20
let HOUSE_COOLDOWN = 200
let HOUSE_HEADROOM = 2
let FARM_RADIUS = 10
let WILD_PER_WORKER = 150
let FARM_BELOW = 400
let PLENTY = 1000
let AGE_WORKERS = 16
let SEAL_MARGIN = 5
let MIX_AGE1 = [ 60, 40, 0, 0 ]  // food, wood, stone, gold (EcoBot.MIX for age 1)
let REACH_REFRESH = 100
let REACH_SEARCH = 3
let HUNT_RADIUS = 16
let CLAIM_COOLDOWN = 200
let MEAT_LEFT = 40
let PEN_SHEEP = 3
let BOAR_SOLDIERS = 3
let BOAR_LEAD = 2

// ---- reach.gd: where a bot's units can get to (walkable areas by 4-neighbour steps, per lane)

class Reach:
    labels:[[int]] = []  // per lane, per cell: area label, 0 where blocked ([] until first asked)
    at_tick:[int] = []
    at_version:[int] = []

def reach_labels(r:Reach, ln:int) -> [int]:
    while r.labels.length <= ln:
        r.labels.push([]::int)
        r.at_tick.push(-1)
        r.at_version.push(-1)
    if not r.labels[ln].length or (r.at_version[ln] != map_version and tick >= r.at_tick[ln] + REACH_REFRESH):
        r.labels[ln] = label_areas(ln)
        r.at_tick[ln] = tick
        r.at_version[ln] = map_version
    return r.labels[ln]

def label_areas(ln:int) -> [int]:
    let walk = walks[ln]
    let n = W * H
    let out = map(n): 0
    let queue = map(n): 0
    var next = 1
    for(n) start:
        if walk[start] == 1 and out[start] == 0:
            out[start] = next
            var head = 0
            var tail = 1
            queue[0] = start
            while head < tail:
                let c = queue[head]
                head++
                let x = c % W
                if c >= W and walk[c - W] == 1 and out[c - W] == 0:
                    out[c - W] = next
                    queue[tail] = c - W
                    tail++
                if c + W < n and walk[c + W] == 1 and out[c + W] == 0:
                    out[c + W] = next
                    queue[tail] = c + W
                    tail++
                if x > 0 and walk[c - 1] == 1 and out[c - 1] == 0:
                    out[c - 1] = next
                    queue[tail] = c - 1
                    tail++
                if x < W - 1 and walk[c + 1] == 1 and out[c + 1] == 0:
                    out[c + 1] = next
                    queue[tail] = c + 1
                    tail++
            next++
    return out

// The area of the walkable cell at (or nearest, within REACH_SEARCH) a point; 0 if none.
def area_at(r:Reach, ln:int, x:int, y:int) -> int:
    let lab = reach_labels(r, ln)
    let cx = clamp(x / 1000, 0, W - 1)
    let cy = clamp(y / 1000, 0, H - 1)
    for(REACH_SEARCH + 1) rr:
        var dy = -rr
        while dy <= rr:
            var dx = -rr
            while dx <= rr:
                if max(abs(dx), abs(dy)) == rr:
                    let xx = cx + dx
                    let yy = cy + dy
                    let at = yy * W + xx  // (in a local: Lobster's --mir JIT misreads the global W inside this and-chain, scratchpad repro)
                    if xx >= 0 and yy >= 0 and xx < W and yy < H and lab[at] != 0: return lab[at]
                dx++
            dy++
    return 0

def area_of_unit(r:Reach, i:int) -> int: return area_at(r, lane(i), u_x[i], u_y[i])

// Can a unit in `area` get next to the rect of cells? Area 0 (unknown) says yes.
def touches_area(r:Reach, ln:int, area:int, cx:int, cy:int, sx:int, sy:int) -> bool:
    if area == 0: return true
    let lab = reach_labels(r, ln)
    var y = max(cy - 1, 0)
    while y < min(cy + sy + 1, H):
        var x = max(cx - 1, 0)
        while x < min(cx + sx + 1, W):
            if lab[y * W + x] == area: return true
            x++
        y++
    return false

// The middle of the cell of `area` nearest (x, y) (lowest cell on ties), or (-1, -1) (Reach.nearest_in).
def nearest_in(r:Reach, ln:int, area:int, x:int, y:int) -> int, int:
    let lab = reach_labels(r, ln)
    var best = -1
    var best_d2 = 1 << 62
    for(lab) a, c:
        if a == area:
            let dx = (c % W) * 1000 + 500 - x
            let dy = (c / W) * 1000 + 500 - y
            let d2 = dx * dx + dy * dy
            if d2 < best_d2:
                best_d2 = d2
                best = c
    if best < 0: return -1, -1
    return (best % W) * 1000 + 500, (best / W) * 1000 + 500

def reaches_cell(r:Reach, ln:int, area:int, cell:int) -> bool:
    return touches_area(r, ln, area, cell % W, cell / W, 1, 1)

def reaches_building(r:Reach, ln:int, area:int, b:int) -> bool:
    return touches_area(r, ln, area, b_cx[b], b_cy[b], b_sx[b], b_sy[b])

// ---- the bot

class EcoBot:
    player:int
    next_train = 0
    next_house = 0
    reach:Reach = Reach {}
    wln = 0
    home = 0
    ordered:[int] = []  // unit ids given an order this think
    // What the full bot sets (EcoBot's defaults otherwise):
    mix_ages:[int] = [ 1 ]  // ages with a mix, ascending, and their mixes (shares per resource)
    mixes:[[int]] = [ [ 60, 40, 0, 0 ] ]
    max_workers = 30
    age_workers = 16
    rebalance = 0  // ticks between moving a gatherer (0: never)
    plenty = 1000
    hold = false               // the army is under its floor: no new workers
    goal:[int] = []            // what we save for (the next age, a building); empty: nothing
    push = 100                 // how hard the shares lean to it
    headroom = HOUSE_HEADROOM  // a house goes up once the population comes this near its cap
    held_ids:[int] = []        // workers kept out of the way until a tick (alongside held_until)
    held_until:[int] = []
    next_rebalance = 0
    next_claim = 0

def held(bot:EcoBot, uid:int) -> int:
    for(bot.held_ids) id, n:
        if id == uid: return bot.held_until[n]
    return 0

def hold_until(bot:EcoBot, uid:int, t:int):
    for(bot.held_ids) id, n:
        if id == uid:
            bot.held_until[n] = t
            return
    bot.held_ids.push(uid)
    bot.held_until.push(t)

def unhold(bot:EcoBot, uid:int):
    for(bot.held_ids) id, n:
        if id == uid:
            bot.held_ids.remove(n)
            bot.held_until.remove(n)
            return

def btype_named(id:string) -> int:
    for(bt_name) n, k:
        if n == id: return k
    return -1

def town_center(p:int) -> int:
    for(b_id.length) b:
        if b_owner[b] == p and has_role(b_kind[b], ROLE_HUB) and b_done[b] == 1: return b
    return -1

def has_building(p:int, k:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] == 1 and b_kind[b] == k: return true
    return false

def sum_of(xs:[int]) -> int:
    var t = 0
    for(xs) v: t += v
    return max(1, t)

// This age's mix as a share per resource index (EcoBot._mix).
def mix_of(bot:EcoBot) -> [int]:
    var mix = bot.mixes[0]
    for(bot.mix_ages) a, n:
        if a <= ages[bot.player]: mix = bot.mixes[n]
    return mix

let GOAL_SPARE = 100

// The share of workers wanted per resource: this age's mix, plus for what the goal still lacks
// `push` more split by how much each lacks; with a full push the ones saved up are halved while
// another falls short; none on a stock of plenty (EcoBot.shares).
def shares(bot:EcoBot) -> [int]:
    let p = bot.player
    let base = mix_of(bot)
    let goal = bot.goal
    var lack = 0
    for(goal) g, r: lack += max(0, g - stock[r][p])
    let out = copy(base)
    var some = false
    for(base.length) r:
        let s = stock[r][p]
        if r < goal.length and s < goal[r]:
            out[r] = base[r] + bot.push * (goal[r] - s) / lack
        elif lack > 0 and bot.push >= 100 and (r >= goal.length or s >= goal[r] + GOAL_SPARE):
            out[r] = base[r] / 2
        if s >= bot.plenty and (r >= goal.length or s >= goal[r]): out[r] = 0
        some = some or out[r] > 0
    return if some: out else: base

// Nearest cell with that resource left that workers in `area` can get to (-1: the home area).
// `free` passes over full farms; `first`: the first such cell found, not the nearest.
def bot_nearest_resource(bot:EcoBot, x:int, y:int, kind:int, free:bool, area0:int, first:bool) -> int:
    let area = if area0 < 0: bot.home else: area0
    var best = -1
    var best_d2 = 1 << 62
    for(resource_cells) c:
        if amount[c] > 0 and tr_res[terrain[c]] == kind:
            let dx = (c % W) * 1000 + 500 - x
            let dy = (c / W) * 1000 + 500 - y
            let d2 = dx * dx + dy * dy
            if d2 < best_d2 and not (free and taken(c, -1)) and reaches_cell(bot.reach, bot.wln, area, c):
                best_d2 = d2
                best = c
                if first: return best
    return best

// The resource (kind) furthest below its share that has some left on the map, or 0.
def short_of(bot:EcoBot, n:[int], x:int, y:int, area:int) -> int:
    for([ shares(bot), mix_of(bot) ]) mix:
        let sum = sum_of(mix)
        var total = 1
        for(n) v: total += v
        var best = 0
        var best_gap = -(1 << 62)
        for(num_resources) r:
            if mix[r] > 0:
                let gap = mix[r] * total - n[r] * sum
                if gap > best_gap and bot_nearest_resource(bot, x, y, r + 1, false, area, true) >= 0:
                    best_gap = gap
                    best = r + 1
        if best > 0: return best
    return 0

def is_ordered(bot:EcoBot, uid:int) -> bool: return contains(bot.ordered, uid)

// A drop-off out from town: one that isn't the hub.
def is_camp(k:int) -> bool: return not has_role(k, ROLE_HUB) and exists(bt_drop[k]): _ == 1

// The first camp type taking in resource r, or -1.
def camp_for(r:int) -> int:
    for(bt_drop.length) k:
        if bt_drop[k][r] == 1 and is_camp(k): return k
    return -1

// A foundation of ours waiting to be built that our workers can get to (farms and camps apart;
// houses only with `houses`).
def building_underway(bot:EcoBot, houses:bool = true) -> bool:
    for(b_id.length) b:
        if b_owner[b] == bot.player and b_done[b] != 1 and reaches_building(bot.reach, bot.wln, bot.home, b):
            let k = b_kind[b]
            if not has_role(k, ROLE_WONDER) and bt_farm[k] == 0 and not is_camp(k) and (houses or not has_role(k, ROLE_HOUSING)): return true
    return false

// Our workers sheltering inside buildings (they still count).
def sheltered(p:int) -> int:
    var n = 0
    for(b_id.length) b:
        if b_owner[b] == p:
            var o = 0
            while o < b_inside[b].length:
                if t_worker[b_inside[b][o + REC_KIND]]: n++
                o += REC_SIZE
    return n

// Workers stay where they were sent: every `rebalance` ticks one gatherer moves from the resource
// most over its share to the one most under it (EcoBot._rebalance).
def rebalance_workers(bot:EcoBot, workers:[int], n:[int]):
    if bot.rebalance <= 0 or tick < bot.next_rebalance: return
    bot.next_rebalance = tick + bot.rebalance
    let mix = shares(bot)
    let sum = sum_of(mix)
    var total = 0
    for(n) v: total += v
    var over = -1
    var most = 0
    let unders = []::int  // -(how far under) * 64 + r: most under first, then the lower resource
    for(num_resources) r:
        let gap = n[r] * sum - mix[r] * total
        if gap >= sum and gap > most:
            most = gap
            over = r
        if mix[r] > 0 and -gap >= sum: unders.push(gap * 64 + r)
    sort_ints(unders)
    if over < 0 or not unders.length: return
    let tc = town_center(bot.player)
    var under = -1
    var to = -1
    for(unders) e:
        if to < 0:
            let r = ((e % 64) + 64) % 64
            to = bot_nearest_resource(bot, b_cx[tc] * 1000 + 1500, b_cy[tc] * 1000 + 1500, r + 1, true, -1, false)
            if to >= 0: under = r
    if to < 0: return
    let tx = (to % W) * 1000 + 500
    let ty = (to / W) * 1000 + 500
    var best = -1
    var best_d2 = 1 << 62
    for(workers) i:
        if not is_ordered(bot, u_id[i]) and u_carry_kind[i] == over + 1 and (u_task[i] == GATHER or u_task[i] == T_RETURN):
            let d2 = dist2(u_x[i], u_y[i], tx, ty)
            if d2 < best_d2:
                best_d2 = d2
                best = i
    if best < 0: return
    let cell = bot_nearest_resource(bot, u_x[best], u_y[best], under + 1, true, area_of_unit(bot.reach, best), false)
    if cell >= 0:
        issue_cmd(bot.player, 3, [ u_id[best] ], cell, 0, 0, 0)
        bot.ordered.push(u_id[best])

def farm_underway(p:int, fk:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p and b_kind[b] == fk and b_done[b] == 0: return true
    return false

// A wood gatherer (lowest slot), else any worker.
def pick_builder(bot:EcoBot, workers:[int]) -> int:
    let free = filter(workers): not is_ordered(bot, u_id[_])
    for(free) i:
        if u_task[i] != BUILD and u_carry_kind[i] == 2: return i
    return if free.length: free[0] else: -1

// Don't wall in a resource: keep the margin box clear of resource tiles' neighbours.
def blocks_resource(x0:int, y0:int, n:int) -> bool:
    var y = y0 - 1
    while y < y0 + n + 1:
        var x = x0 - 1
        while x < x0 + n + 1:
            if x >= 0 and y >= 0 and x < W and y < H and amount[y * W + x] > 0: return true
            x++
        y++
    return false

// Would a building here shut a pocket off? (EcoBot._seals)
def seals(bot:EcoBot, cx:int, cy:int, size:int) -> bool:
    let walk = walks[bot.wln]
    let x0 = max(0, cx - SEAL_MARGIN)
    let y0 = max(0, cy - SEAL_MARGIN)
    let x1 = min(W - 1, cx + size - 1 + SEAL_MARGIN)
    let y1 = min(H - 1, cy + size - 1 + SEAL_MARGIN)
    def inside(x:int, y:int) -> bool: return x >= cx and y >= cy and x < cx + size and y < cy + size
    let edge = []::int
    var y = cy - 1
    while y < cy + size + 1:
        var x = cx - 1
        while x < cx + size + 1:
            if not (x < 0 or y < 0 or x >= W or y >= H or inside(x, y)) and
                    not ((x == cx - 1 or x == cx + size) and (y == cy - 1 or y == cy + size)) and walk[y * W + x] == 1:
                edge.push(y * W + x)
            x++
        y++
    if not edge.length: return true
    let seen = dictionary<int, int>(251)
    seen.set(edge[0], 1)
    let queue = [ edge[0] ]
    var out = false
    var head = 0
    while head < queue.length:
        let c = queue[head]
        head++
        let x = c % W
        let yy = c / W
        if x == x0 or yy == y0 or x == x1 or yy == y1: out = true
        for([ 1, -1, 0, 0 ]) ddx, k:
            let ddy = [ 0, 0, 1, -1 ][k]
            let nx = x + ddx
            let ny = yy + ddy
            if not (nx < x0 or ny < y0 or nx > x1 or ny > y1 or inside(nx, ny)):
                let nc = ny * W + nx
                if walk[nc] == 1 and not seen.get(nc, 0):
                    seen.set(nc, 1)
                    queue.push(nc)
    if not out: return true
    for(edge) c:
        if not seen.get(c, 0): return true
    return false

// A free size x size spot with a tile of space round it, spiralling out from (cx, cy).
def house_spot(bot:EcoBot, cx:int, cy:int, size:int) -> int, int:
    for([ true, false ]) strict:
        var r = 3
        while r < (if strict: 14 else: 22):
            var dy = -r
            while dy <= r:
                var dx = -r
                while dx <= r:
                    if max(abs(dx), abs(dy)) == r:
                        let ok = if strict: can_build(cx + dx - 1, cy + dy - 1, size + 2, 0, false, false) else: can_build(cx + dx, cy + dy, size, 0, false, false)
                        if ok and (not strict or not blocks_resource(cx + dx - 1, cy + dy - 1, size + 2)) and
                                touches_area(bot.reach, bot.wln, bot.home, cx + dx, cy + dy, size, size) and not seals(bot, cx + dx, cy + dy, size):
                            return cx + dx, cy + dy
                    dx++
                dy++
            r++
    return -1, -1

// A foundation of ours nobody is building: the nearest free worker goes to finish it.
def finish_foundations(bot:EcoBot, workers:[int]):
    for(b_id.length) b:
        if b_owner[b] == bot.player and b_done[b] != 1:
            let bid = b_id[b]
            var building = false
            for(workers) i:
                if u_task[i] == BUILD and u_target[i] == bid: building = true
            if not building:
                let x = b_cx[b] * 1000 + b_sx[b] * 500
                let y = b_cy[b] * 1000 + b_sy[b] * 500
                var best = -1
                var best_d2 = 1 << 62
                for(workers) i:
                    if not is_ordered(bot, u_id[i]) and u_foe[i] == 0 and u_task[i] != BUILD and
                            reaches_building(bot.reach, bot.wln, area_of_unit(bot.reach, i), b):
                        let d2 = dist2(x, y, u_x[i], u_y[i])
                        if d2 < best_d2:
                            best_d2 = d2
                            best = i
                if best >= 0:
                    issue_cmd(bot.player, 5, [ u_id[best] ], bid, 0, 0, 0)
                    bot.ordered.push(u_id[best])

// Farms: as the wild food near home runs out, a farm for each food worker it no longer feeds.
def farms(bot:EcoBot, tc:int, workers:[int], n:[int]):
    let p = bot.player
    let food = 1
    let fk = find(bt_farm): _ == 1
    if fk < 0: return
    var count = 0
    for(b_id.length) b:
        if b_owner[b] == p and b_kind[b] == fk:
            count++
            if b_done[b] == 1 and left_at(b_cy[b] * W + b_cx[b]) <= 0 and can_afford(p, bt_reseed[fk]):
                issue_cmd(p, 8, []::int, b_id[b], 0, 0, 0)
    let hx = b_cx[tc] * 1000 + 1500
    let hy = b_cy[tc] * 1000 + 1500
    var wild = 0
    for(resource_cells) c:
        if pool[c] < 0 and amount[c] > 0 and tr_res[terrain[c]] == food and
                dist2(hx, hy, (c % W) * 1000 + 500, (c / W) * 1000 + 500) <= FARM_RADIUS * FARM_RADIUS * 1000000:
            wild += amount[c]
    for(u_x.length) i:  // and the meat still walking about near home: our sheep, wild deer and boar
        let k = u_kind[i]
        if t_animal[k] != 0 and (u_owner[i] == p or u_owner[i] == gaia) and dist2(hx, hy, u_x[i], u_y[i]) <= HUNT_RADIUS * HUNT_RADIUS * 1000000:
            wild += t_food[k]
    let mix = shares(bot)
    var total = 0
    for(n) v: total += v
    let want = max(n[food - 1], mix[food - 1] * total / sum_of(mix))
    if count >= want - wild / WILD_PER_WORKER or stock[food - 1][p] >= FARM_BELOW or farm_underway(p, fk) or not can_afford(p, bt_cost[fk]): return
    var builder = -1
    for(workers) i:
        if builder < 0 and u_task[i] == GATHER and u_home[i] < 0 and u_carry_kind[i] == food and not is_ordered(bot, u_id[i]): builder = i
    if builder < 0: builder = pick_builder(bot, workers)
    let sx, sy = house_spot(bot, b_cx[tc] + 1, b_cy[tc] + 1, bt_size[fk])
    if builder >= 0 and sx >= 0: issue_cmd(p, 4, [ u_id[builder] ], fk, sx, sy, 0)

// Up to `count` ids of food gatherers (or idle workers) nearest a point; ties go to the lower id.
def nearest_food_workers(bot:EcoBot, workers:[int], x:int, y:int, count:int) -> [int]:
    let food = resource_index("food") + 1
    let keys = []::int
    for(workers) i:
        let gathering = (u_task[i] == GATHER or u_task[i] == T_RETURN) and u_carry_kind[i] == food
        let idle = u_task[i] == T_NONE and u_foe[i] == 0
        if (gathering or idle) and not is_ordered(bot, u_id[i]): keys.push(i)
    let ds = map(keys) i: dist2(x, y, u_x[i], u_y[i])
    let order = map(keys.length) n: n
    insertion_sort(order) a, b: ds[a] < ds[b] or (ds[a] == ds[b] and u_id[keys[a]] < u_id[keys[b]])
    return map(slice(order, 0, max(0, min(count, order.length)))) n: u_id[keys[n]]

// Sheep nobody owns near home: the nearest food gatherer walks over to claim one.
def herd(bot:EcoBot, tc:int, workers:[int]):
    if tick < bot.next_claim: return
    let hx = b_cx[tc] * 1000 + 1500
    let hy = b_cy[tc] * 1000 + 1500
    var sheep = -1
    var best_d2 = HUNT_RADIUS * HUNT_RADIUS * 1000000
    for(u_x.length) i:
        if u_owner[i] == gaia and t_behave[u_kind[i]] == B_HERD and area_at(bot.reach, bot.wln, u_x[i], u_y[i]) == bot.home:
            let d2 = dist2(hx, hy, u_x[i], u_y[i])
            if d2 < best_d2:
                best_d2 = d2
                sheep = i
    if sheep < 0: return
    let party = nearest_food_workers(bot, workers, u_x[sheep], u_y[sheep], 1)
    if party.length:
        issue_cmd(bot.player, CMD_MOVE, party, u_x[sheep], u_y[sheep], 0, 0)
        bot.ordered.push(party[0])
        bot.next_claim = tick + CLAIM_COOLDOWN

// Sheep for the long run: enough of ours near home in age 1 or 2 and no pen: build one; once it
// stands, our sheep outside it go in (while it has room).
def bot_pen(bot:EcoBot, tc:int, workers:[int]):
    let p = bot.player
    var pen = -1
    for(b_id.length) b:
        if pen < 0 and b_owner[b] == p and is_pen(b): pen = b
    if pen < 0:
        let hx = b_cx[tc] * 1000 + 1500
        let hy = b_cy[tc] * 1000 + 1500
        var near = 0
        for(u_x.length) i:
            if u_owner[i] == p and t_behave[u_kind[i]] == B_HERD and dist2(hx, hy, u_x[i], u_y[i]) <= HUNT_RADIUS * HUNT_RADIUS * 1000000: near++
        let k = pen_type()
        let ageing = bot.push >= 100 and bot.goal.length > 0
        if k >= 0 and ages[p] <= 2 and not ageing and near >= PEN_SHEEP and can_afford(p, bm_cost[p][k]) and not building_underway(bot):
            let builder = pick_builder(bot, workers)
            let sx, sy = house_spot(bot, b_cx[tc] + 1, b_cy[tc] + 1, bt_size[k])
            if builder >= 0 and sx >= 0:
                issue_cmd(p, CMD_BUILD, [ u_id[builder] ], k, sx, sy, 0)
                bot.ordered.push(u_id[builder])
        return
    if b_done[pen] == 0: return
    let heading = pen_animals(pen, false)
    let out = []::int
    for(u_x.length) i:
        if u_owner[i] == p and t_behave[u_kind[i]] == B_HERD and pen_at(i) < 0 and not contains(heading, i): out.push(u_id[i])
    if out.length and pen_room(pen): issue_cmd(p, CMD_PEN, out, b_id[pen], 0, 0, 0)

def has_pen(p:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p and is_pen(b): return true
    return false

// Hunting, one animal at a time: our own sheep first, then deer near home once there are a few
// workers, then boar only with a big party, idle soldiers at home leading. Meat near home that
// nobody gathers gets workers sent to it.
def hunt(bot:EcoBot, tc:int, workers:[int]):
    let p = bot.player
    for(u_x.length) i:
        if u_owner[i] == p and u_foe[i] != 0:
            let j = index_of(u_foe[i])
            if j >= 0 and t_animal[u_kind[j]] != 0: return  // a hunt is on
    let hx = b_cx[tc] * 1000 + 1500
    let hy = b_cy[tc] * 1000 + 1500
    let near = FARM_RADIUS * FARM_RADIUS * 1000000
    let carcass = tr_index("carcass")
    for(resource_cells) c:
        if terrain[c] == carcass and amount[c] > MEAT_LEFT and dist2(hx, hy, (c % W) * 1000 + 500, (c / W) * 1000 + 500) <= near and
                reaches_cell(bot.reach, bot.wln, bot.home, c):
            var busy = false
            for(workers) i:
                if u_home[i] == c and (u_task[i] == GATHER or u_task[i] == T_RETURN): busy = true
            if not busy:
                let cooks = nearest_food_workers(bot, workers, (c % W) * 1000 + 500, (c / W) * 1000 + 500, 8)
                if cooks.length:
                    issue_cmd(p, CMD_GATHER, cooks, c, 0, 0, 0)
                    for(cooks) id: bot.ordered.push(id)
                return
    for(workers) i:
        let h = u_home[i]
        if (u_task[i] == GATHER or u_task[i] == T_RETURN) and h >= 0 and terrain[h] == carcass and amount[h] > MEAT_LEFT and
            dist2(hx, hy, (h % W) * 1000 + 500, (h / W) * 1000 + 500) <= near: return
    let guards = []::int
    for(u_x.length) i:
        let k = u_kind[i]
        if u_owner[i] == p and not t_worker[k] and t_animal[k] == 0 and not t_healer[k] and not t_trader[k] and u_foe[i] == 0 and
            u_moving[i] == 0 and dist2(hx, hy, u_x[i], u_y[i]) <= near: guards.push(u_id[i])
    var target = -1
    let penning = has_pen(p)
    for([ B_HERD, B_FLEE, B_FIGHT ]) want:
        let need = if want == B_HERD: 0 elif want == B_FLEE: 8 else: 12
        if target < 0 and workers.length >= need and not (want == B_HERD and penning) and not (want == B_FIGHT and guards.length < BOAR_LEAD):
            var best_d2 = HUNT_RADIUS * HUNT_RADIUS * 1000000
            for(u_x.length) i:
                let mine = u_owner[i] == p and want == B_HERD
                let wild = u_owner[i] == gaia and want != B_HERD
                if (mine or wild) and t_behave[u_kind[i]] == want and area_at(bot.reach, bot.wln, u_x[i], u_y[i]) == bot.home:
                    let d2 = dist2(hx, hy, u_x[i], u_y[i])
                    if d2 < best_d2:
                        best_d2 = d2
                        target = i
    if target < 0: return
    let want = t_behave[u_kind[target]]
    let party = if want == B_HERD: 3 elif want == B_FLEE: 3 else: 8
    let ids = if want == B_FIGHT: slice(guards, 0, min(BOAR_SOLDIERS, guards.length)) else: []::int
    for(nearest_food_workers(bot, workers, u_x[target], u_y[target], party - ids.length)) id: ids.push(id)
    if ids.length:
        issue_cmd(p, CMD_ATTACK, ids, u_id[target], 0, 0, 0)
        for(ids) id: bot.ordered.push(id)

def bot_think(bot:EcoBot):
    let p = bot.player
    if tick % THINK_EVERY != p * STAGGER % THINK_EVERY: return
    let tc = town_center(p)
    if tc < 0: return
    bot.wln = lane_base[p] + t_mclass[worker_type(p)]
    bot.home = area_at(bot.reach, bot.wln, b_cx[tc] * 1000 + b_sx[tc] * 500, b_cy[tc] * 1000 + b_sy[tc] * 500)
    let workers = []::int
    let n = map(num_resources): 0
    let idle = []::int
    for(u_x.length) i:
        if u_owner[i] == p and is_worker(i):
            workers.push(i)
            let task = u_task[i]
            if task == GATHER or task == T_RETURN:
                if u_carry_kind[i] > 0: n[u_carry_kind[i] - 1]++
            elif task == T_NONE:
                if u_foe[i] != 0: n[0]++  // hunting: food on the hoof
                elif u_moving[i] == 0 and held(bot, u_id[i]) <= tick: idle.push(i)
    let count = workers.length + sheltered(p)  // (workers sheltering from a raid still count)
    // Idle hands: back to work on whatever we're shortest of, that they can get to.
    for(idle) i:
        let area = area_of_unit(bot.reach, i)
        let kind = short_of(bot, n, u_x[i], u_y[i], area)
        if kind > 0:
            issue_cmd(p, 3, [ u_id[i] ], bot_nearest_resource(bot, u_x[i], u_y[i], kind, true, area, false), 0, 0, 0)
            n[kind - 1]++
    // New workers go where we're short.
    let rally_kind = short_of(bot, n, b_cx[tc] * 1000 + 1500, b_cy[tc] * 1000 + 1500, -1)
    let rally = if rally_kind > 0: bot_nearest_resource(bot, b_cx[tc] * 1000 + 1500, b_cy[tc] * 1000 + 1500, rally_kind, true, -1, false) else: -1
    if rally >= 0 and cell_of(b_rally_x[tc], b_rally_y[tc]) != rally:
        issue_cmd(p, 7, []::int, b_id[tc], (rally % W) * 1000 + 500, (rally / W) * 1000 + 500, 0)
    bot.ordered.remove_range(0, bot.ordered.length)
    for(workers) i:
        if held(bot, u_id[i]) > tick: bot.ordered.push(u_id[i])  // pulled from a fight: not a builder or a hunter for now
    herd(bot, tc, workers)
    bot_pen(bot, tc, workers)
    hunt(bot, tc, workers)
    finish_foundations(bot, workers)
    rebalance_workers(bot, workers, n)
    // Age up: with enough workers, a barracks, then save up and click it.
    let saving = ages[p] == 1 and count >= bot.age_workers
    let bk = btype_with(ROLE_BARRACKS)
    if bk >= 0 and saving and not has_building(p, bk) and not building_underway(bot):
        if can_afford(p, bm_cost[p][bk]):
            let sx, sy = house_spot(bot, b_cx[tc] + 1, b_cy[tc] + 1, bt_size[bk])
            let free = filter(workers): not is_ordered(bot, u_id[_])
            let builders = map(slice(free, 0, min(3, free.length))): u_id[_]
            if sx >= 0:
                issue_cmd(p, 4, builders, bk, sx, sy, 0)
                bot.next_house = tick + HOUSE_COOLDOWN
    if saving and not tech_barred(p, tc, -1):
        issue_cmd(p, 9, []::int, b_id[tc], 0, 0, 0)
    // Keep the Town Center busy.
    let wk = worker_type(p)
    let q = b_queue[tc]
    if not saving and not bot.hold and tick >= bot.next_train and q.length < 2 and count + q.length < bot.max_workers and can_afford(p, t_cost[wk]):
        issue_cmd(p, 6, []::int, b_id[tc], wk, 1, 0)  // (no race lacks workers)
        bot.next_train = tick + TRAIN_COOLDOWN
    // A house before we're stuck.
    let hk = btype_with(ROLE_HOUSING)
    var queued_units = 0
    for(q) e:
        if e >= 0: queued_units++
    let queued_pop = queued_units * t_pop[wk]
    if tick >= bot.next_house and pop_cap[p] < r_pop_max and pop[p] + queued_pop + bot.headroom >= pop_cap[p] and
            can_afford(p, bm_cost[p][hk]) and not building_underway(bot):
        let builder = pick_builder(bot, workers)
        let sx, sy = house_spot(bot, b_cx[tc] + 1, b_cy[tc] + 1, bt_size[hk])
        if builder >= 0 and sx >= 0:
            issue_cmd(p, 4, [ u_id[builder] ], hk, sx, sy, 0)
            bot.next_house = tick + HOUSE_COOLDOWN
    farms(bot, tc, workers, n)
