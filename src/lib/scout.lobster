// ------------------------------------------------------------------ scouting and the bot's memory (src/ai/scout.gd)
// Early on a worker walks a tour (round the enemy's start, the crossings, the middle, home); from
// age 2 the fastest idle soldier at home (a scout first) walks it again now and then. Hit, it runs
// home. The enemy soldiers it sees are remembered for `memory` seconds: the counter-pick reads them.

class Scout:
    id = 0  // the scout out now (unit id), 0: none
    worker = false
    route_x:[int] = []
    route_y:[int] = []
    leg = 0
    until = 0
    hp = 0
    tours = 0
    next_tour = 0
    seen_ids:[int] = []  // enemy soldiers seen, by id: kind, tick, where
    seen_kind:[int] = []
    seen_tick:[int] = []
    seen_x:[int] = []
    seen_y:[int] = []
    worker_ids:[int] = []  // enemy workers seen, by id: the tick last seen (the economy we know of)
    worker_tick:[int] = []

def forget_seen(s:Scout, n:int):
    s.seen_ids.remove(n)
    s.seen_kind.remove(n)
    s.seen_tick.remove(n)
    s.seen_x.remove(n)
    s.seen_y.remove(n)

// Soldiers we remember that died this tick are forgotten.
def forget_dead(s:Scout):
    for(events) e:
        if e.kind == EV_DIE:
            let found, at = binary_search(s.seen_ids, e.a)
            if found: forget_seen(s, at)
            let wfound, wat = binary_search(s.worker_ids, e.a)
            if wfound:
                s.worker_ids.remove(wat)
                s.worker_tick.remove(wat)

// Remember the enemy soldiers and workers in sight now (kept `memory` seconds after last seen).
def remember_soldiers(s:Scout, p:int):
    for(u_x.length) i:
        let k = u_kind[i]
        if t_worker[k] and is_foe(p, u_owner[i]) and fog_visible(p, u_x[i], u_y[i]):
            let found, at = binary_search(s.worker_ids, u_id[i])
            if found: s.worker_tick[at] = tick
            else:
                s.worker_ids.insert(at, u_id[i])
                s.worker_tick.insert(at, tick)
        if is_foe(p, u_owner[i]) and fog_visible(p, u_x[i], u_y[i]) and not t_worker[k] and t_animal[k] == 0 and not t_healer[k] and not t_trader[k]:
            let found, at = binary_search(s.seen_ids, u_id[i])
            if found:
                s.seen_kind[at] = k
                s.seen_tick[at] = tick
                s.seen_x[at] = u_x[i]
                s.seen_y[at] = u_y[i]
            else:
                s.seen_ids.insert(at, u_id[i])
                s.seen_kind.insert(at, k)
                s.seen_tick.insert(at, tick)
                s.seen_x.insert(at, u_x[i])
                s.seen_y.insert(at, u_y[i])
    let keep = cfg_or("scout.memory", 180) * 20
    var n = s.seen_ids.length - 1
    while n >= 0:
        if tick - s.seen_tick[n] > keep: forget_seen(s, n)
        n--
    n = s.worker_ids.length - 1
    while n >= 0:
        if tick - s.worker_tick[n] > keep:
            s.worker_ids.remove(n)
            s.worker_tick.remove(n)
        n--

// A worker for the tour: the nearest to home, not one building or kept for something.
def free_worker(bot:Bot, workers:[int], hx:int, hy:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    for(workers) i:
        if u_task[i] != BUILD and held(bot.eco, u_id[i]) <= tick:
            let d2 = dist2(hx, hy, u_x[i], u_y[i])
            if d2 < best_d2:
                best_d2 = d2
                best = i
    return best

// The points moved onto ground of `area` (the nearest cell of it), ones with none dropped.
def on_ground(r:Reach, ln:int, area:int, xs:[int], ys:[int], out_x:[int], out_y:[int]):
    for(xs) px, k:
        var x = clamp(px, 500, W * 1000 - 500)
        var y = clamp(ys[k], 500, H * 1000 - 500)
        var keep = true
        if area_at(r, ln, x, y) != area:
            let nx, ny = nearest_in(r, ln, area, x, y)
            if nx < 0: keep = false
            else:
                x = nx
                y = ny
        if keep:
            out_x.push(x)
            out_y.push(y)

// The tour: round the enemy starts first, then the crossings and the middle (up to `points`),
// nearest next from where it is; home last.
def tour(s:Scout, bot:Bot, i:int, hx:int, hy:int):
    let r = bot.eco.reach
    let ln = lane(i)
    let area = area_of_unit(r, i)
    let tx = []::int
    let ty = []::int
    let er = cfg("scout.enemy_tiles") * 1000
    for(num_players) p:
        if is_enemy(bot.player, p) and p < start_x.length and defeated[p] == 0:
            let ex = start_x[p]
            let ey = start_y[p]
            let d = max(1, isqrt(dist2(ex, ey, hx, hy)))
            let ux = (hx - ex) * 1000 / d
            let uy = (hy - ey) * 1000 / d
            for([ [ 1000, 0 ], [ 500, 866 ], [ 500, -866 ] ]) turn:
                let vx = (ux * turn[0] - uy * turn[1]) / 1000
                let vy = (ux * turn[1] + uy * turn[0]) / 1000
                tx.push(ex + vx * er / 1000)
                ty.push(ey + vy * er / 1000)
    let rx = []::int
    let ry = []::int
    land_crossings(bot.land)
    for(bot.land.crossings_centre) c:
        rx.push(c % W * 1000 + 500)
        ry.push(c / W * 1000 + 500)
    rx.push(W * 500)
    ry.push(H * 500)
    s.route_x = []::int
    s.route_y = []::int
    var atx = u_x[i]
    var aty = u_y[i]
    for([ [ tx, ty ], [ rx, ry ] ]) pts:
        let px = []::int
        let py = []::int
        on_ground(r, ln, area, pts[0], pts[1], px, py)
        var n = 0
        while px.length and n < cfg("scout.points"):
            var best = 0
            for(px.length) k:
                if dist2(atx, aty, px[k], py[k]) < dist2(atx, aty, px[best], py[best]): best = k
            atx = px[best]
            aty = py[best]
            s.route_x.push(atx)
            s.route_y.push(aty)
            px.remove(best)
            py.remove(best)
            n++
    s.route_x.push(hx)
    s.route_y.push(hy)

def scout_start(s:Scout, bot:Bot, i:int, is_worker:bool, hx:int, hy:int):
    if i < 0: return
    tour(s, bot, i, hx, hy)
    if s.route_x.length < 2:
        s.next_tour = tick + cfg("scout.every") * 20
        return
    s.id = u_id[i]
    s.worker = is_worker
    s.leg = 0
    s.hp = u_hp[i]
    s.until = tick + (if is_worker: cfg("scout.worker_seconds") else: cfg("scout.soldier_seconds")) * 20
    s.tours++
    if s.worker: hold_until(bot.eco, s.id, s.until)
    issue_cmd(bot.player, 0, [ s.id ], s.route_x[0], s.route_y[0], 0, 0)

def scout_end(s:Scout, bot:Bot, back:bool):
    if s.worker and back: unhold(bot.eco, s.id)
    s.id = 0
    s.next_tour = tick + cfg("scout.every") * 20

def drive(s:Scout, bot:Bot, hx:int, hy:int):
    let i = index_of(s.id)
    if i < 0:
        scout_end(s, bot, false)
        return
    let hurt = u_hp[i] < s.hp
    if (hurt or tick >= s.until) and s.leg < s.route_x.length - 1:
        s.leg = s.route_x.length - 1
        issue_cmd(bot.player, 0, [ s.id ], hx, hy, 0, 0)
        if s.worker: hold_until(bot.eco, s.id, tick + 400)
        return
    if u_moving[i] != 0: return
    s.leg++
    if s.leg >= s.route_x.length:
        scout_end(s, bot, true)
        return
    issue_cmd(bot.player, 0, [ s.id ], s.route_x[s.leg], s.route_y[s.leg], 0, 0)

def scout_think(s:Scout, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    if s.id != 0:
        drive(s, bot, hx, hy)
        return
    if tick < s.next_tour: return
    if s.tours == 0:
        if workers.length < cfg("scout.worker_at") or tick > cfg("scout.worker_before") * 20:
            if tick > cfg("scout.worker_before") * 20: s.tours = 1
            return
        scout_start(s, bot, free_worker(bot, workers, hx, hy), true, hx, hy)
        return
    var has_scout = false
    for(army) i:
        if t_slot[u_kind[i]] == "scout": has_scout = true
    if ages[bot.player] < cfg("scout.soldier_age") or bot.threat_ids.length or (army.length < cfg("scout.soldier_army") and not has_scout): return
    var best = -1
    for(army) i:
        let k = u_kind[i]
        if u_foe[i] == 0 and u_moving[i] == 0 and dist2(hx, hy, u_x[i], u_y[i]) <= 400 * 1000000 and t_animal[k] == 0:
            if not (has_scout and t_slot[k] != "scout"):
                if best < 0 or t_speed[k] > t_speed[u_kind[best]]: best = i
    scout_start(s, bot, best, false, hx, hy)
