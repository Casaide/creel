// ------------------------------------------------------------------ reaching out for resources (src/ai/expand.gd)
// Camps follow the workers (a few gatherers far from any drop-off: a camp by them); soldiers posted
// with far gatherers (escorts); a second Town Center earlier on a big map or when home runs thin.

class Expand:
    escort_ids:[int] = []  // soldier id -> its post (in the order they were posted)
    escort_x:[int] = []
    escort_y:[int] = []
    next_camp = 0
    want:[int] = []
    next_post = 0

def is_escort(e:Expand, id:int) -> bool: return contains(e.escort_ids, id)

def drop_offs(p:int, kind:int) -> [int]:
    return filter(b_id.length) b: b_owner[b] == p and bt_drop[b_kind[b]][kind - 1] == 1

// How far (tiles, the larger axis) a cell is from the nearest of `drops`.
def walk_to(drops:[int], cell:int) -> int:
    let x = cell % W
    let y = cell / W
    var best = 1 << 20
    for(drops) b:
        let dx = max(max(b_cx[b] - x, 0), x - (b_cx[b] + b_sx[b] - 1))
        let dy = max(max(b_cy[b] - y, 0), y - (b_cy[b] + b_sy[b] - 1))
        best = min(best, max(dx, dy))
    return best

// A camp by the gatherers walking furthest, per resource, one at a time (Expand._camps).
def camps(e:Expand, bot:Bot, workers:[int]):
    if bot.saving_age:
        e.want = []::int
        return
    if tick < e.next_camp or building_underway(bot.eco, true): return
    e.next_camp = tick + cfg("expand.camp_every") * 20
    e.want = []::int
    let p = bot.player
    let names = copy(resource_names)
    insertion_sort(names) a, b: a < b
    for(names) res:  // (sorted: which camp goes first mustn't depend on the data's order)
        let camp = cfg_list("expand.camps.{res}")
        let kind = resource_index(res) + 1
        let k = if camp.length: btype_named(camp[0]) else: -1
        if kind > 0 and k >= 0 and not build_barred(p, k):
            let drops = drop_offs(p, kind)
            let far_cell = []::int
            let far_i = []::int
            for(workers) i:
                if (u_task[i] == GATHER or u_task[i] == T_RETURN) and u_carry_kind[i] == kind and u_home[i] >= 0 and pool[u_home[i]] < 0 and
                        walk_to(drops, u_home[i]) > cfg("expand.camp_tiles"):
                    far_cell.push(u_home[i])
                    far_i.push(i)
            if far_cell.length >= cfg("expand.camp_workers"):
                var mid = far_cell[0]
                var least = 1 << 62
                for(far_cell) a:
                    var sum = 0
                    for(far_cell) b: sum += dist2(a % W, a / W, b % W, b / W)
                    if sum < least or (sum == least and a < mid):
                        least = sum
                        mid = a
                let sx, sy = house_spot(bot.eco, mid % W, mid / W, bt_size[k])
                if sx >= 0 and walk_to(drops, sy * W + sx) > cfg("expand.camp_tiles") / 2:
                    if not can_afford(p, bm_cost[p][k]):
                        e.want = bm_cost[p][k]
                        e.next_camp = tick + 100
                        return
                    let keys = map(far_cell) c, n: dist2(c % W, c / W, sx, sy) * (1 << 20) + far_i[n]
                    sort_ints(keys)
                    let ids = map(slice(keys, 0, min(keys.length, cfg("expand.camp_builders")))) key: u_id[key & ((1 << 20) - 1)]
                    issue_cmd(p, 4, ids, k, sx, sy, 0)
                    return

// Is an enemy building we remember within r of this spot?
def by_enemy(p:int, x:int, y:int, r:int) -> bool:
    for(fog_seen[p]) s:
        if is_enemy(p, s[2]) and dist2(x, y, s[3] * 1000 + s[5] * 500, s[4] * 1000 + s[9] * 500) <= r * r: return true
    return false

def drop_escort(e:Expand, n:int):
    e.escort_ids.remove(n)
    e.escort_x.remove(n)
    e.escort_y.remove(n)

// Soldiers posted with our far gatherers (Expand._escort).
def escort_posts(e:Expand, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    let p = bot.player
    var n = 0
    while n < e.escort_ids.length:
        let i = index_of(e.escort_ids[n])
        if i < 0 or (u_foe[i] != 0 and b_index_of(u_foe[i]) >= 0): drop_escort(e, n)
        else: n++
    if tick < e.next_post: return
    e.next_post = tick + cfg("expand.post_every") * 20
    let guard_r = cfg("expand.guard_tiles") * 1000
    let out = []::int
    for(workers) i:
        if (u_task[i] == GATHER or u_task[i] == T_RETURN) and u_home[i] >= 0:
            let c = u_home[i]
            if dist2(hx, hy, c % W * 1000 + 500, c / W * 1000 + 500) > guard_r * guard_r: out.push(c)
    let r = cfg("expand.post_tiles") * 1000
    // Posts still worth keeping (sorted by x, then y, as Vector2i keys sort).
    let post_keys = []::int
    for(e.escort_x) x, q:
        let key = x * (1 << 24) + e.escort_y[q]
        if not contains(post_keys, key): post_keys.push(key)
    sort_ints(post_keys)
    let posts = []::int
    for(post_keys) key:
        let px = key >> 24
        let py = key & ((1 << 24) - 1)
        var near = 0
        for(out) c:
            if dist2(px, py, c % W * 1000 + 500, c / W * 1000 + 500) <= r * r: near++
        if near * 2 < cfg("expand.escort_workers"):
            var q = 0
            while q < e.escort_ids.length:
                if e.escort_x[q] == px and e.escort_y[q] == py: drop_escort(e, q)
                else: q++
        else:
            posts.push(key)
    var size = 0
    for(army) i: size += t_pop[u_kind[i]]
    if ages[p] >= cfg("expand.escort_age") and size >= cfg("expand.escort_army") and posts.length < cfg("expand.posts") and not bot.threat_ids.length:
        var best = -1
        var most = 0
        for(out) c:
            let ax = c % W * 1000 + 500
            let ay = c / W * 1000 + 500
            var by_post = false
            for(posts) key:
                if dist2(key >> 24, key & ((1 << 24) - 1), ax, ay) <= 4 * r * r: by_post = true
            if not by_post and not by_enemy(p, ax, ay, r):
                var near = 0
                for(out) d:
                    if dist2(ax, ay, d % W * 1000 + 500, d / W * 1000 + 500) <= r * r: near++
                if near > most or (near == most and c < best):
                    most = near
                    best = c
        if best >= 0 and most >= cfg("expand.escort_workers"):
            let ax = best % W * 1000 + 500
            let ay = best / W * 1000 + 500
            let keys = []::int
            for(army) i:
                let k = u_kind[i]
                if not (u_foe[i] != 0 or is_escort(e, u_id[i]) or dist2(hx, hy, u_x[i], u_y[i]) > 400 * 1000000 or t_buildings_only[k] or t_splash[k] > 0):
                    keys.push(dist2(ax, ay, u_x[i], u_y[i]) * (1 << 20) + u_id[i])
            sort_ints(keys)
            for(slice(keys, 0, min(keys.length, cfg("expand.escort")))) key:
                e.escort_ids.push(key & ((1 << 20) - 1))
                e.escort_x.push(ax)
                e.escort_y.push(ay)
    // Escorts away from their post walk back to it, one order per post (posts in first-posted order).
    let ids = copy(e.escort_ids)
    sort_ints(ids)
    let back_keys = []::int
    let back_ids = []::[int]
    for(ids) id:
        let i = index_of(id)
        var q = 0
        for(e.escort_ids) x, m:
            if x == id: q = m
        let px = e.escort_x[q]
        let py = e.escort_y[q]
        if u_foe[i] == 0 and u_moving[i] == 0 and dist2(px, py, u_x[i], u_y[i]) > 9 * 1000000:
            let key = px * (1 << 24) + py
            var at = -1
            for(back_keys) bk, m:
                if bk == key: at = m
            if at < 0:
                back_keys.push(key)
                back_ids.push([ id ])
            else:
                back_ids[at].push(id)
    for(back_keys) key, m: issue_cmd(p, 1, back_ids[m], key >> 24, key & ((1 << 24) - 1), 0, 0)

def expand_think(e:Expand, bot:Bot, workers:[int], army:[int], hx:int, hy:int):
    camps(e, bot, workers)
    escort_posts(e, bot, workers, army, hx, hy)

// Does the second Town Center come early: a big map, or home thin?
def wants_town(hx:int, hy:int) -> bool:
    if W >= cfg("expand.town.big_map"): return true
    let r = cfg("expand.town.thin.tiles") * 1000
    let left = map(num_resources): 0
    for(resource_cells) c:
        let k = tr_res[terrain[c]]
        if amount[c] > 0 and k > 0 and pool[c] < 0 and dist2(hx, hy, c % W * 1000 + 500, c / W * 1000 + 500) <= r * r:
            left[k - 1] += amount[c]
    for(resource_names) res, k:
        if has_cfg("expand.town.thin.{res}") and left[k] < cfg("expand.town.thin.{res}"): return true
    return false
