// ------------------------------------------------------------------ walls you stand on (walls.gd)
// A finished building type with a walkway has standing places per cell along its top. Foot units
// ordered onto it walk to a way up (their team's stairs, their side's ladder against the wall, their
// side's siege tower docked beside it), climb, and stand on the walkway: one team's walkway cells
// that touch (8-way) are one network, walked cell to cell. Ordered elsewhere a unit walks to the best
// way down and climbs down. A unit whose cell stops being a walkway falls. Breaches: a wall piece of a
// type in breach.from destroyed leaves rubble its owner can rebuild cheaply (repair_cost).

let T_CLIMB = 6
let DOCK = 1600
let AWAY = 40000
let N9 = [ int2 { 0, 0 }, int2 { 1, 0 }, int2 { 0, 1 }, int2 { -1, 0 }, int2 { 0, -1 }, int2 { 1, 1 }, int2 { -1, 1 }, int2 { -1, -1 }, int2 { 1, -1 } ]
let N8 = [ int2 { 1, 0 }, int2 { 0, 1 }, int2 { -1, 0 }, int2 { 0, -1 }, int2 { 1, 1 }, int2 { -1, 1 }, int2 { -1, -1 }, int2 { 1, -1 } ]

var pour_at = dictionary<int, int>(16)  // a pouring building's id -> the tick it may pour again
var pour_ids = []::int                  // its keys, ascending
var t_docks = []::int                   // per unit type: a siege tower

class WallNet:
    cells:[int]                 // breadth first from the start cell
    steps:dictionary<int, int>  // cell -> steps from it

var net_cache = dictionary<int, WallNet>(64)
var net_cache_tick = -1

// ---- the walkway

def places(c:int) -> int:
    let id = occupied[c]
    if id == 0: return 0
    let b = b_index_of(id)
    if b < 0 or b_done[b] == 0: return 0
    return bt_walkway[b_kind[b]]

def team_at(c:int) -> int: return teams[b_owner[b_index_of(occupied[c])]]

def can_climb(i:int) -> bool:
    let k = u_kind[i]
    if t_animal[k] != 0 or t_worker[k] or t_mclass[k] == FLYING or t_docks[k]: return false
    for(walk_not) c:
        if c >= 0 and contains(t_tags[k], c): return false
    return true

// Steps from cell `src` to every walkway cell of its network, breadth first in N8 order; kept for the tick.
def dist_from(src:int) -> WallNet:
    if net_cache_tick != tick:
        net_cache = dictionary<int, WallNet>(64)
        net_cache_tick = tick
    let had = net_cache.get(src)
    if had: return had
    let net = WallNet { []::int, dictionary<int, int>(64) }
    if places(src) > 0:
        let team = team_at(src)
        net.steps.set(src, 0)
        net.cells.push(src)
        var k = 0
        while k < net.cells.length:
            let c = net.cells[k]
            k++
            for(N8) n:
                let x = c % W + n.x
                let y = c / W + n.y
                if x >= 0 and y >= 0 and x < W and y < H:
                    let nc = y * W + x
                    if net.steps.get(nc, -1) < 0 and places(nc) > 0 and team_at(nc) == team:
                        net.steps.set(nc, net.steps.get(c, 0) + 1)
                        net.cells.push(nc)
    net_cache.set(src, net)
    return net

def on_net(net:WallNet, c:int) -> bool: return net.steps.get(c, -1) >= 0

// Which way cell c's wall runs: 0 along x, 1 along y, 2 along (1, 1), 3 along (1, -1).
def run_of(c:int) -> int:
    let x = c % W
    let y = c / W
    def on(dx:int, dy:int) -> bool:
        let nx = x + dx
        let ny = y + dy
        return nx >= 0 and ny >= 0 and nx < W and ny < H and places(ny * W + nx) > 0
    if on(1, 0) or on(-1, 0): return 0
    if on(0, 1) or on(0, -1): return 1
    if on(1, 1) or on(-1, -1): return 2
    if on(1, -1) or on(-1, 1): return 3
    return 0

// Standing place k of p on cell c: evenly along the wall's run.
def wall_spot(c:int, k:int, p:int) -> int, int:
    let cx = (c % W) * TILE + TILE / 2
    let cy = (c / W) * TILE + TILE / 2
    let off = (2 * k + 1) * TILE / (2 * max(p, 1)) - TILE / 2
    switch run_of(c):
        case 1: return cx, cy + off
        case 2: return cx + off * 707 / 1000, cy + off * 707 / 1000
        case 3: return cx + off * 707 / 1000, cy - off * 707 / 1000
        default: return cx + off, cy

def cell_centre(c:int) -> int, int: return (c % W) * TILE + TILE / 2, (c / W) * TILE + TILE / 2

// ---- ways up and down

// The walkway cell access `acc` leads to for a unit of `team` at (x, y), or -1 (Walls.top_of).
def top_of(acc:int, team:int, x:int, y:int, down:bool) -> int:
    let b = b_index_of(acc)
    if b >= 0:
        let k = b_kind[b]
        if b_done[b] == 0: return -1
        if bt_stairs[k] and bt_walkway[k] > 0 and (down or teams[b_owner[b]] == team):
            var best = -1
            var best_d = 1 << 62
            for(footprint(b)) c:
                let px, py = cell_centre(c)
                let d = dist2(x, y, px, py)
                if d < best_d:
                    best_d = d
                    best = c
            return best
        if bt_ladder[k] and teams[b_owner[b]] == team: return ladder_top(b_cy[b] * W + b_cx[b])
        return -1
    let j = index_of(acc)
    if j >= 0 and teams[u_owner[j]] == team and t_docks[u_kind[j]]: return docked_at(j)
    return -1

def ladder_top(c:int) -> int:
    let x = c % W
    let y = c / W
    for([ int2 { 0, -1 }, int2 { 1, 0 }, int2 { 0, 1 }, int2 { -1, 0 } ]) n:
        let nx = x + n.x
        let ny = y + n.y
        if nx >= 0 and ny >= 0 and nx < W and ny < H and places(ny * W + nx) > 0: return ny * W + nx
    return -1

def docked_at(j:int) -> int:
    if u_moving[j] == 1: return -1
    let cx = u_x[j] / TILE
    let cy = u_y[j] / TILE
    var best = -1
    var best_d = DOCK * DOCK + 1
    for(5) dy0:
        for(5) dx0:
            let x = cx + dx0 - 2
            let y = cy + dy0 - 2
            if x >= 0 and y >= 0 and x < W and y < H:
                let c = y * W + x
                if places(c) > 0:
                    let px, py = cell_centre(c)
                    let d = dist2(u_x[j], u_y[j], px, py)
                    if d < best_d:
                        best_d = d
                        best = c
    return best

// Every way onto the network of walkway cell `goal` for a unit of `team`: [id, top cell] pairs, ids ascending.
def ways_up(team:int, goal:int, down:bool) -> [int]:
    let net = dist_from(goal)
    let out = []::int
    if not net.cells.length: return out
    let ids = []::int
    let tops = []::int
    for(b_id.length) b:
        let k = b_kind[b]
        if (bt_stairs[k] or bt_ladder[k]) and b_done[b] != 0:
            let c = b_cy[b] * W + b_cx[b]
            let top = top_of(b_id[b], team, (c % W) * TILE + 500, (c / W) * TILE + 500, down)
            if top >= 0 and on_net(net, top):
                ids.push(b_id[b])
                tops.push(top)
    for(u_x.length) j:
        if t_docks[u_kind[j]] and teams[u_owner[j]] == team:
            let top = docked_at(j)
            if top >= 0 and on_net(net, top):
                ids.push(u_id[j])
                tops.push(top)
    let order = map(ids.length) n: n
    insertion_sort(order) a, b: ids[a] < ids[b]
    for(order) n:
        out.push(ids[n])
        out.push(tops[n])
    return out

def acc_where(acc:int) -> int, int:
    let b = b_index_of(acc)
    if b >= 0: return b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2
    let j = index_of(acc)
    return u_x[j], u_y[j]

// ---- orders

def walkway_at(x:int, y:int) -> int:
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return -1
    let c = cell_of(x, y)
    return if places(c) > 0: c else: -1

// Units on (or making for) each walkway cell, leaving out the slots in `except` (Walls._held).
def wall_held(except:[int]) -> dictionary<int, int>:
    let held = dictionary<int, int>(64)
    for(u_x.length) i:
        if not contains(except, i):
            var c = -1
            if u_perch[i] != 0 and u_wexit[i] == 0: c = (if u_wgoal[i] != 0: u_wgoal[i] else: u_perch[i]) - 1
            elif u_task[i] == T_CLIMB and u_wgoal[i] != 0: c = u_wgoal[i] - 1
            if c >= 0: held.set(c, held.get(c, 0) + 1)
    return held

// A MOVE onto walkway cell `goal`: each unit that may climb goes to a standing place on the network
// round it, walking along if it's on that network, else to its nearest way up. The ids it took.
def order_onto(p:int, ids:[int], goal:int) -> [int]:
    let team = teams[p]
    let net = dist_from(goal)
    if not net.cells.length: return []::int
    let mine = []::int
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and can_climb(i): mine.push(i)
    if not mine.length: return []::int
    let ups = ways_up(team, goal, false)
    let held = wall_held(mine)
    let order = copy(net.cells)
    insertion_sort(order) a, b: net.steps.get(a, 0) < net.steps.get(b, 0) or (net.steps.get(a, 0) == net.steps.get(b, 0) and a < b)
    let taken = []::int
    var k = 0
    for(mine) i:
        let on = u_perch[i] != 0 and on_net(net, u_perch[i] - 1)
        if not (u_perch[i] != 0 and not on):
            var acc = 0
            if not on: acc = nearest_way(i, ups)
            if on or acc != 0:
                while k < order.length and held.get(order[k], 0) >= places(order[k]): k++
                let cell = if k < order.length: order[k] else: goal
                held.set(cell, held.get(cell, 0) + 1)
                taken.push(u_id[i])
                if on: wall_walk(i, cell)
                else: climb_via(i, acc, cell)
    return taken

def nearest_way(i:int, ups:[int]) -> int:
    var best = 0
    var best_d = 1 << 62
    var n = 0
    while n < ups.length:
        let px, py = acc_where(ups[n])
        let d = dist2(u_x[i], u_y[i], px, py)
        if d < best_d:
            best_d = d
            best = ups[n]
        n += 2
    return best

def off_wall_fields(i:int):
    u_perch[i] = 0
    u_wgoal[i] = 0
    u_wnext[i] = 0
    u_wexit[i] = 0
    u_wtime[i] = 0

def climb_via(i:int, acc:int, cell:int):
    off_wall_fields(i)
    clear_task(i)
    u_foe[i] = 0
    u_stance[i] = 0
    u_patient[i] = 0
    u_task[i] = T_CLIMB
    u_target[i] = acc
    u_wgoal[i] = cell + 1
    climb_approach(i, acc)

def climb_approach(i:int, acc:int):
    let b = b_index_of(acc)
    if b >= 0:
        approach_building(i, b)
        return
    let j = index_of(acc)
    order_move(i, u_x[j], u_y[j], u_radius[j] + REACH, 0, -1, -1, 0)

def at_access(i:int, acc:int) -> bool:
    let b = b_index_of(acc)
    if b >= 0:
        let x0, y0, x1, y1 = building_rect(b)
        return in_reach(i, x0, y0, x1, y1)
    let j = index_of(acc)
    let r = u_radius[i] + u_radius[j] + REACH
    return dist2(u_x[i], u_y[i], u_x[j], u_y[j]) <= r * r

def wall_walk(i:int, cell:int):
    u_wgoal[i] = cell + 1
    u_wnext[i] = 0
    u_wexit[i] = 0
    u_wtime[i] = 0
    u_foe[i] = 0
    u_stance[i] = 0

// Unit i on a wall leaves it for (x, y) by the way down landing nearest there; false if none.
def wall_leave(i:int, x:int, y:int) -> bool:
    let at = u_perch[i] - 1
    let downs = ways_up(teams[u_owner[i]], at, true)
    let net = dist_from(at)
    var best = 0
    var best_top = -1
    var best_d = 1 << 62
    var n = 0
    while n < downs.length:
        let land = landing(i, downs[n], downs[n + 1], x, y)
        if land >= 0:
            let px, py = cell_centre(land)
            var d = isqrt(dist2(px, py, x, y)) + net.steps.get(downs[n + 1], 0) * TILE
            if not clear_line(px, py, x, y, lane(i)): d += AWAY
            if d < best_d:
                best_d = d
                best = downs[n]
                best_top = downs[n + 1]
        n += 2
    if best == 0: return false
    u_wexit[i] = best
    u_wgoal[i] = best_top + 1
    u_wnext[i] = 0
    u_wtime[i] = 0
    u_tx[i] = x
    u_ty[i] = y
    u_foe[i] = 0
    u_stance[i] = 0
    return true

def landing(i:int, acc:int, top:int, x:int, y:int) -> int:
    var cells = []::int
    let b = b_index_of(acc)
    if b >= 0:
        cells = footprint(b)
        if bt_ladder[b_kind[b]]: cells.push(top)
    else:
        let j = index_of(acc)
        cells.push(cell_of(u_x[j], u_y[j]))
    let ln = lane(i)
    var best = -1
    var best_d = 1 << 62
    for(cells) c:
        for(N9) n:
            let cx = c % W + n.x
            let cy = c / W + n.y
            if cx >= 0 and cy >= 0 and cx < W and cy < H:
                let nc = cy * W + cx
                if walks[ln][nc] != 0:
                    let px, py = cell_centre(nc)
                    let d = dist2(px, py, x, y)
                    if d < best_d or (d == best_d and nc < best):
                        best_d = d
                        best = nc
    return best

def wall_busy(i:int) -> bool: return u_perch[i] != 0 and (u_wgoal[i] != 0 or u_wtime[i] != 0)

def wall_stop(i:int):
    if u_perch[i] != 0 and u_wtime[i] == 0:
        u_wgoal[i] = 0
        u_wnext[i] = 0
        u_wexit[i] = 0

// ---- the tick

def walls_tick():
    let n = u_x.length
    var someone = false
    for(n) i:
        if u_perch[i] != 0 or u_task[i] == T_CLIMB: someone = true
    if not someone: return
    for(n) i:
        if u_task[i] == T_CLIMB:
            let acc = u_target[i]
            let top = top_of(acc, teams[u_owner[i]], u_x[i], u_y[i], false)
            if top < 0:
                clear_task(i)
                u_wgoal[i] = 0
                u_moving[i] = 0
            elif u_work[i] > 0:
                u_work[i]++
                if u_work[i] >= walk_climb: climb_up(i, top)
            elif at_access(i, acc):
                u_moving[i] = 0
                u_work[i] = 1
            elif u_moving[i] == 0:
                if u_stuck[i] >= GIVE_UP:
                    clear_task(i)
                    u_wgoal[i] = 0
                else: climb_approach(i, acc)
    push_ladders()
    var held = dictionary<int, int>(1)
    var held_made = false
    let settled = dictionary<int, int>(64)
    for(u_x.length) i:
        if u_perch[i] != 0:
            let c = u_perch[i] - 1
            if places(c) == 0: wall_fall(i)
            elif u_wtime[i] > 0:
                u_wtime[i]--
                if u_wtime[i] == 0: climb_down(i)
            elif u_wgoal[i] != 0: wall_step(i)
            else:
                let p = places(c)
                let k = settled.get(c, 0)
                var moved = false
                if k >= p:  // no room here: the nearest cell with room
                    if not held_made:
                        held = wall_held([]::int)
                        held_made = true
                    let net = dist_from(c)
                    var best = -1
                    var best_d = 1 << 30
                    for(net.cells) nc:
                        let sd = net.steps.get(nc, 0)
                        if held.get(nc, 0) < places(nc) and (sd < best_d or (sd == best_d and nc < best)):
                            best_d = sd
                            best = nc
                    if best >= 0:
                        held.set(best, held.get(best, 0) + 1)
                        held.set(c, held.get(c, 1) - 1)
                        wall_walk(i, best)
                        moved = true
                if not moved:
                    settled.set(c, k + 1)
                    if u_wnext[i] != k + 1:
                        let sx, sy = wall_spot(c, min(k, p - 1), p)
                        if toward(i, sx, sy): u_wnext[i] = k + 1

// Defenders push ladders off: a finished ladder whose walkway cell has a settled defender and no
// attacker loses walkway.push hp a tick per defender; at none it falls.
def push_ladders():
    var b = b_id.length - 1
    while b >= 0:
        if bt_ladder[b_kind[b]] and b_done[b] != 0:
            let top = ladder_top(b_cy[b] * W + b_cx[b])
            if top >= 0:
                let team = teams[b_owner[b]]
                var defenders = 0
                var attackers = 0
                for(u_x.length) i:
                    if u_perch[i] == top + 1:
                        if teams[u_owner[i]] == team: attackers++
                        elif u_wgoal[i] == 0: defenders++
                if defenders > 0 and attackers == 0:
                    b_hp[b] -= walk_push * defenders
                    if b_hp[b] <= 0:
                        if events_on: events.push(Event { EV_DIE, b_id[b], 1, 0, b_cx[b] * TILE + TILE / 2, b_cy[b] * TILE + TILE / 2 })
                        breach(b)
                        occupy(footprint(b), 0)
                        remove_building(b)
        b--

// Units of a building's own team settled on each walkway cell: who mans what.
def manned() -> dictionary<int, int>:
    let out = dictionary<int, int>(64)
    for(u_x.length) i:
        if u_perch[i] != 0 and u_wgoal[i] == 0 and u_wtime[i] == 0:
            let c = u_perch[i] - 1
            if team_at(c) == teams[u_owner[i]]: out.set(c, out.get(c, 0) + 1)
    return out

def climb_up(i:int, top:int):
    let goal = u_wgoal[i]
    clear_task(i)
    u_moving[i] = 0
    u_perch[i] = top + 1
    let px, py = cell_centre(top)
    u_x[i] = px
    u_y[i] = py
    u_wgoal[i] = if goal != 0 and on_net(dist_from(top), goal - 1): goal else: top + 1
    u_wnext[i] = 0
    u_stuck[i] = 0
    u_foe[i] = 0
    u_stance[i] = 0

def wall_step(i:int):
    let c = u_perch[i] - 1
    let goal = u_wgoal[i] - 1
    if c == goal:
        let px, py = cell_centre(c)
        if u_wexit[i] != 0:
            if toward(i, px, py):
                u_wgoal[i] = 0
                u_wtime[i] = walk_climb
            return
        u_wgoal[i] = 0
        u_wnext[i] = 0
        return
    if u_wnext[i] == 0:
        let d = dist_from(goal)
        if not on_net(d, c):
            u_wgoal[i] = 0
            u_wexit[i] = 0
            return
        var nxt = -1
        for(N8) nb:
            if nxt < 0:
                let x = c % W + nb.x
                let y = c / W + nb.y
                let nc = y * W + x
                if x >= 0 and y >= 0 and x < W and y < H and on_net(d, nc) and d.steps.get(nc, 0) == d.steps.get(c, 0) - 1: nxt = nc
        u_wnext[i] = nxt + 1
    let to = u_wnext[i] - 1
    if places(to) == 0:
        u_wnext[i] = 0
        return
    let qx, qy = cell_centre(to)
    let fx, fy = cell_centre(c)
    toward(i, qx, qy)
    if dist2(u_x[i], u_y[i], qx, qy) <= dist2(u_x[i], u_y[i], fx, fy):
        u_perch[i] = to + 1
        u_wnext[i] = 0

def toward(i:int, x:int, y:int) -> bool:
    let dx = x - u_x[i]
    let dy = y - u_y[i]
    let len = isqrt(dx * dx + dy * dy)
    let s = max(1, u_speed[i] * walk_speed_pct / 100)
    if len <= s:
        u_x[i] = x
        u_y[i] = y
        return true
    u_x[i] += dx * s / len
    u_y[i] += dy * s / len
    return false

def climb_down(i:int):
    var land = landing(i, u_wexit[i], u_perch[i] - 1, u_tx[i], u_ty[i])
    if land < 0: land = nearest_walkable(u_perch[i] - 1, lane(i))
    let x = u_tx[i]
    let y = u_ty[i]
    off_wall_fields(i)
    let px, py = cell_centre(land)
    u_x[i] = px
    u_y[i] = py
    if dist2(px, py, x, y) > TILE * TILE / 4: order_move(i, x, y, SLOT_ARRIVE, 0, -1, -1, 0)

def wall_fall(i:int):
    let c = u_perch[i] - 1
    off_wall_fields(i)
    let px, py = centre(nearest_walkable(c, lane(i)))
    u_x[i] = px
    u_y[i] = py
    u_moving[i] = 0
    u_foe[i] = 0
    u_stance[i] = 0
    u_hp[i] = max(1, u_hp[i] - walk_fall)

// ---- breaches

// Wall piece b is falling (destroyed): its cells become rubble, remembering what stood there.
def breach(b:int):
    let k = b_kind[b]
    if bt_ladder[k]: set_walk_over(footprint(b), false)
    if rubble_terrain < 0 or not contains(rubble_from, k) or b_done[b] == 0: return
    var along = 0
    if b_diag[b] != 0: along = b_diag[b] + 1
    elif b_sy[b] > b_sx[b]: along = 1
    for(footprint(b)) c:
        if not rubble.get(c):
            rubble.set(c, [ terrain[c], b_owner[b], k, b_cx[b], b_cy[b], along ])
            let _found, at = binary_search(rubble_cells, c)
            rubble_cells.insert(at, c)
            set_terrain(c, rubble_terrain)

// ---- the pour (Combat._pour): a manned gatehouse or wall tower pours on enemies at its foot.

def pour():
    var crew = dictionary<int, int>(1)
    var looked = false
    for(b_id.length) b:
        let k = b_kind[b]
        if bt_pour[k].length and b_done[b] != 0 and pour_at.get(b_id[b], 0) <= tick:
            if not looked:
                var anyone = false
                for(u_x.length) i:
                    if u_perch[i] != 0: anyone = true
                if not anyone: return
                crew = manned()
                looked = true
            var on = false
            for(footprint(b)) c:
                if crew.get(c, 0) > 0: on = true
            if on:
                let reach = bt_pour[k][0] * TILE
                let x0 = b_cx[b] * TILE - reach
                let y0 = b_cy[b] * TILE - reach
                let x1 = (b_cx[b] + b_sx[b]) * TILE + reach
                let y1 = (b_cy[b] + b_sy[b]) * TILE + reach
                let atk = map(num_classes): 0
                atk[0] = bt_pour[k][2]
                var hit = false
                for(u_x.length) j:
                    if u_x[j] >= x0 and u_x[j] < x1 and u_y[j] >= y0 and u_y[j] < y1 and u_perch[j] == 0 and is_foe(u_owner[j], b_owner[b]) and t_animal[u_kind[j]] == 0:
                        let kj = u_kind[j]
                        let d = damage(atk, t_arm[kj], t_cls[kj], r_min_damage)
                        c_hurt[j] += hook_on_hit(b_id[b], j, d)
                        c_hurt_by[j] = b_id[b]
                        hit = true
                        if events_on: events.push(Event { EV_HIT, b_id[b], u_id[j], d, u_x[j], u_y[j] })
                if hit:
                    if pour_at.get(b_id[b], -1) < 0:
                        let _found, at = binary_search(pour_ids, b_id[b])
                        pour_ids.insert(at, b_id[b])
                    pour_at.set(b_id[b], tick + bt_pour[k][1])

// The walls' part of the hash (Walls.hash_into: units up or climbing, the pours, the rubble).
def walls_hash(h0:int) -> int:
    var h = h0
    for(u_x.length) i:
        if u_perch[i] != 0 or u_wgoal[i] != 0:
            for([ u_id[i], u_perch[i], u_wgoal[i], u_wnext[i], u_wexit[i], u_wtime[i] ]) v: h = mix(h, v)
    for(pour_ids) id: h = mix(mix(h, id), pour_at.get(id, 0))
    for(rubble_cells) c:
        h = mix(h, c)
        for(rubble.get(c) or []::int) v: h = mix(h, v)
    return h
