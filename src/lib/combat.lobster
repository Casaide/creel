// ------------------------------------------------------------------ combat (combat.gd, shots.gd)
// Targets, chasing, blows, shots in flight and deaths: units against units and buildings, towers
// (and Town Centers with people inside) shooting volleys, heroes' auras on blows and shots, high
// ground. Damage uses armour classes: max(min_damage, sum over the attack's classes the target
// belongs to of max(0, attack - armour)). Hits within a tick land together.
// Left out (none in the scenarios, asserted by the exporter or here): bridges, walls you stand on
// and pouring from them, siege weapons (minimum range, splash, bolts, packing, blasts), bounties,
// sticky hits.

var c_hurt = []::int
var c_hurt_by = []::int
var c_engaged = []::int
var c_inbound = []::int
var c_bhurt = []::int
var c_aura = []::int  // this tick's auras per unit slot (heroes.gd AURA ints), empty with none

let AURA = 3

// Should these two fight on their own (enemies, and neither an animal nobody owns)? (World.is_foe)
def is_foe(a:int, b:int) -> bool: return a != gaia and b != gaia and teams[a] != teams[b]
def is_enemy(a:int, b:int) -> bool: return teams[a] != teams[b]

def combat_clear(i:int):
    u_foe[i] = 0
    u_stance[i] = NONE
    u_patient[i] = 0

// An enemy unit or building of `player`, or an animal to hunt (wild, or its own sheep) (Combat._is_target; no bridges here).
def is_target(id:int, p:int) -> bool:
    let i = index_of(id)
    if i >= 0: return is_enemy(u_owner[i], p) or (u_owner[i] == p and t_animal[u_kind[i]] != 0)
    let b = b_index_of(id)
    if b < 0: return bridge_target(id)  // a map bridge: anyone may break it
    return is_enemy(b_owner[b], p)

// Can a unit of type k touch that unit? Only a weapon that can hit air touches an aircraft.
def can_hit(k:int, j:int) -> bool: return t_air[u_kind[j]] == 0 or t_hits_air[k] != 0
def can_hit_id(k:int, id:int) -> bool:
    let j = index_of(id)
    return j < 0 or can_hit(k, j)

def cmd_attack(p:int, ids:[int], target:int):
    if not is_target(target, p): return
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p:
            let k = u_kind[i]
            if not t_healer[k] and not t_harmless[k] and not (t_buildings_only[k] and index_of(target) >= 0) and can_hit_id(k, target):
                clear_task(i)
                u_foe[i] = target
                u_stance[i] = ORDERED
                u_moving[i] = 0

def damage(atk:[int], arm:[int], cls:[int], min_damage:int) -> int:
    var d = 0
    for(atk) a, k:
        if a > 0 and cls[k] == 1: d += max(0, a - arm[k])
    return max(min_damage, d)

// A building's classes: melee, pierce and building.
def building_cls() -> [int]:
    let cls = map(num_classes): 0
    cls[0] = 1
    cls[1] = 1
    cls[2] = 1
    return cls

// Damage d from attacker slot i (-1: a building) to target slot j (-1: a building) of damage class
// `kind`, with the auras on both, never under `floor` (Heroes.boost).
def boost(i:int, j:int, kind:int, d:int, floor:int) -> int:
    if not c_aura.length: return d
    let add = if i >= 0: c_aura[i * AURA] else: 0
    let arm = if j >= 0: c_aura[j * AURA + (if kind == 0: 1 else: 2)] else: 0
    if add == arm: return d
    return max(floor, d + add - arm)

def engage(i:int, foe:int):
    if u_stance[i] != RETURN:
        u_gx[i] = u_x[i]
        u_gy[i] = u_y[i]
    u_foe[i] = foe
    u_stance[i] = AUTO

def sight_of(i:int) -> int:
    return max(r_sight, t_reach[u_kind[i]] + u_radius[i] + TILE / 2)

def look(i:int) -> int:
    let k = u_kind[i]
    if u_perch[i] != 0: return t_reach[k] + u_radius[i] + TILE / 2 + (if t_ranged[k]: r_high_reach else: TILE)  // up on a wall it never chases
    if u_posture[i] == DEFENSIVE: return max(r_defend_sight, t_reach[k] + u_radius[i] + TILE / 2)
    if u_posture[i] == STAND: return t_reach[k] + u_radius[i] + TILE / 2
    return sight_of(i)

def go_back(i:int):
    u_foe[i] = 0
    if dist2(u_x[i], u_y[i], u_gx[i], u_gy[i]) > TILE * TILE / 4:
        u_stance[i] = RETURN
        order_move(i, u_gx[i], u_gy[i], 0, 0, -1, -1, 0)
    else:
        u_stance[i] = NONE
        u_moving[i] = 0

def lost_foe(i:int):
    u_foe[i] = 0
    if u_stance[i] == AUTO and u_posture[i] == DEFENSIVE:
        go_back(i)
    elif u_stance[i] == ATTACK_MOVE:
        resume_attack_move(i)
    else:
        u_stance[i] = NONE
        u_moving[i] = 0

def height_step_to(i:int, lv:int) -> int:
    if not has_heights: return 0
    let d = level[cell_of(u_x[i], u_y[i])] - lv
    return if d > 0: 1 elif d < 0: -1 else: 0

// High ground: 1 if unit i stands a level above unit j (or building b), -1 if below, 0 on the level.
// A unit up on a wall stands a level above the ground it's on.
def height_step(i:int, j:int, b:int) -> int:
    var at = if u_perch[i] != 0: 1 else: 0
    var to = if j >= 0 and u_perch[j] != 0: 1 else: 0
    if has_heights:
        at += level[cell_of(u_x[i], u_y[i])]
        to += if j >= 0: level[cell_of(u_x[j], u_y[j])] else: level[b_cy[b] * W + b_cx[b]]
    return if at > to: 1 elif at < to: -1 else: 0

def uphill(d:int) -> int: return max(1, d * r_uphill_pct / 100)

// The edge-to-edge gap from unit i to unit j or building b.
def gap(i:int, j:int) -> int:
    return isqrt(dist2(u_x[i], u_y[i], u_x[j], u_y[j])) - u_radius[i] - u_radius[j]

def gap_b(i:int, b:int) -> int:
    if b_diag[b] != 0:  // to the nearest cell of a diagonal gate (Buildings.gap)
        var best = 1 << 30
        for(b_sy[b]) k:
            let gx0 = (b_cx[b] + (if b_diag[b] == 1: k else: b_sx[b] - 1 - k)) * TILE
            let gy0 = (b_cy[b] + k) * TILE
            let dx = max(max(gx0 - u_x[i], 0), u_x[i] - (gx0 + TILE))
            let dy = max(max(gy0 - u_y[i], 0), u_y[i] - (gy0 + TILE))
            best = min(best, isqrt(dx * dx + dy * dy))
        return best - u_radius[i]
    let x0 = b_cx[b] * TILE
    let y0 = b_cy[b] * TILE
    let dx = max(max(x0 - u_x[i], 0), u_x[i] - (x0 + b_sx[b] * TILE))
    let dy = max(max(y0 - u_y[i], 0), u_y[i] - (y0 + b_sy[b] * TILE))
    return isqrt(dx * dx + dy * dy) - u_radius[i]

def gap_to(i:int, j:int, b:int) -> int: return if j >= 0: gap(i, j) else: gap_b(i, b)

// Close in on unit j (re-aimed on re-plan beats) or head for building b once.
def chase(i:int, j:int, b:int):
    if j >= 0:
        if u_moving[i] == 0 or (tick + u_id[i]) % REPLAN_EVERY == 0:
            if clear_line(u_x[i], u_y[i], u_x[j], u_y[j], lane(i)):
                order_direct(i, u_x[j], u_y[j])
            else:
                order_move(i, u_x[j], u_y[j], 0, 0, -1, -1, 0)
    else:
        let key = building_field(b_id[b], false, lane(i))
        if u_moving[i] == 0 or u_fkey[i] != key:
            let x0, y0, x1, y1 = building_rect(b)
            order_reach(i, x0, y0, x1, y1, key)

// Does this player see any tile of building b right now?
def fog_sees_area(p:int, b:int) -> bool:
    let g = fog[p]
    var y = b_cy[b]
    while y < b_cy[b] + b_sy[b]:
        var x = b_cx[b]
        while x < b_cx[b] + b_sx[b]:
            if g[y * W + x] == VISIBLE: return true
            x++
        y++
    return false

// The best enemy unit within `sight` its side can see (nearest, each attacker counting `spread`
// further, a foe it counters counter_pull nearer, lowest id on ties; with `use_inbound`, skipping
// those the shots in the air will kill); then, `buildings_too`, the nearest enemy building it sees.
def nearest_foe(i:int, sight:int, buildings_too:bool, spread:int, use_inbound:bool, near:int, units_too:bool) -> int:
    let me = u_owner[i]
    if me == gaia: return 0  // animals don't go looking for a fight
    var best = 0
    var best_d = 1 << 40
    let r = sight / TILE + 1
    let cx = u_x[i] / TILE
    let cy = u_y[i] / TILE
    let counters = t_counters[u_kind[i]]
    let lvl = if t_ranged[u_kind[i]]: -1 elif u_perch[i] != 0: 1 else: 0  // melee: only foes up on a wall if it is, the ground if not
    let xi = u_x[i]
    let yi = u_y[i]
    if units_too:
        var yy = max(cy - r, 0)
        let y1 = min(cy + r + 1, H)
        while yy < y1:
            var xx = max(cx - r, 0)
            let x1 = min(cx + r + 1, W)
            while xx < x1:
                let cell = yy * W + xx
                var k = sp_start[cell]
                let e = sp_end[cell]
                while k < e:
                    let j = sp_items[k]
                    k++
                    if not is_foe(u_owner[j], me) or t_animal[u_kind[j]] != 0: continue  // a rival's sheep is stolen, not killed
                    if not can_hit(u_kind[i], j): continue
                    if lvl >= 0 and (if u_perch[j] != 0: 1 else: 0) != lvl: continue
                    if use_inbound and c_inbound[j] >= u_hp[j]: continue
                    let d2 = dist2(xi, yi, u_x[j], u_y[j])
                    if d2 > sight * sight or d2 < near * near or not fog_visible(me, u_x[j], u_y[j]): continue
                    var d = isqrt(d2) + c_engaged[j] * spread
                    if r_counter_pull > 0:
                        let cls = t_cls[u_kind[j]]
                        for(counters) c:
                            if cls[c] != 0:
                                d -= r_counter_pull
                                break
                    if d < best_d or (d == best_d and u_id[j] < best):
                        best_d = d
                        best = u_id[j]
                xx++
            yy++
    if best != 0 or not buildings_too: return best
    best_d = sight * sight + 1
    for(b_id.length) b:
        if is_enemy(b_owner[b], me) and fog_sees_area(me, b) and not (near > 0 and gap_b(i, b) < near - u_radius[i]):
            let d = dist2(xi, yi, b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2)
            if d < best_d:
                best_d = d
                best = b_id[b]
    return best

def flight(x0:int, y0:int, x1:int, y1:int, speed:int) -> int:
    return max(1, (isqrt(dist2(x0, y0, x1, y1)) + speed - 1) / speed)

// Loose a shot from (sx, sy) at unit j (or building b): it flies at the spot its target stands on.
def loose(by:int, owner:int, sx:int, sy:int, j:int, b:int, d:int, src:int, up:int, speed:int, mount = 0):
    var to = 0
    var ax = 0
    var ay = 0
    if j >= 0:
        to = u_id[j]
        ax = u_x[j]
        ay = u_y[j]
        if u_moving[j] == 1 and r_shot_lead_pct > 0:
            let vx = u_wx[j] - ax
            let vy = u_wy[j] - ay
            let len = isqrt(vx * vx + vy * vy)
            if len > 0:
                let pace = if u_pace[j] > 0: u_pace[j] else: u_speed[j]
                let ahead = min(len, pace * flight(sx, sy, ax, ay, speed) * r_shot_lead_pct / 100)
                ax += vx * ahead / len
                ay += vy * ahead / len
    else:
        to = b_id[b]
        ax = b_cx[b] * TILE + b_sx[b] * TILE / 2
        ay = b_cy[b] * TILE + b_sy[b] * TILE / 2
    let f = flight(sx, sy, ax, ay, speed)
    for([ tick + f, to, by, owner, d, src, up, ax, ay, sx, sy, mount ]) v: shots.push(v)
    if events_on: events.push(Event { EV_SHOT, by, to, 0, ax, ay })

def take_shots(t:int) -> [int]:
    let out = []::int
    let n = shots.length / SHOT_STRIDE
    var keep = 0
    for(n) k:
        let o = k * SHOT_STRIDE
        if shots[o + SHOT_LAND] <= t:
            for(SHOT_STRIDE) f: out.push(shots[o + f])
        else:
            if keep != k:
                for(SHOT_STRIDE) f: shots[keep * SHOT_STRIDE + f] = shots[o + f]
            keep++
    if keep != n: shots.remove_range(keep * SHOT_STRIDE, (n - keep) * SHOT_STRIDE)
    return out

def stray(owner:int, x:int, y:int, slack:int) -> int:
    let cx = x / TILE
    let cy = y / TILE
    var best = -1
    var best_d = 1 << 40
    var yy = max(cy - 1, 0)
    while yy < min(cy + 2, H):
        var xx = max(cx - 1, 0)
        while xx < min(cx + 2, W):
            let cell = yy * W + xx
            var q = sp_start[cell]
            while q < sp_end[cell]:
                let k = sp_items[q]
                q++
                if not is_foe(u_owner[k], owner) or t_animal[u_kind[k]] != 0 or t_air[u_kind[k]] != 0: continue
                let r = u_radius[k] + slack
                let d = dist2(x, y, u_x[k], u_y[k])
                if d <= r * r and (d < best_d or (d == best_d and k < best)):
                    best_d = d
                    best = k
            xx++
        yy++
    return best

// A stray's damage against unit j: the shooter type's attack (src >= 0) or a tower's (-1 - type).
def shot_damage(src:int, up:int, j:int) -> int:
    let kj = u_kind[j]
    var d = 0
    if src >= 0:
        d = damage(t_atk[src], t_arm[kj], t_cls[kj], max(r_min_damage, t_min_damage[kj]))
    else:
        d = damage(tower_atk(-1 - src), t_arm[kj], t_cls[kj], max(r_min_damage, t_min_damage[kj]))
    return if up < 0: uphill(d) else: d

def tower_atk(k:int) -> [int]:
    let atk = map(num_classes): 0
    atk[bt_atk_class[k]] = bt_atk[k]
    return atk

// The shots landing this tick: on the target if its body still covers the spot (buildings always),
// else (with shot_strays) on another foe whose body does, else in the ground.
def land():
    if not shots.length: return
    let recs = take_shots(tick)
    let slack = r_shot_slack
    var o = 0
    while o < recs.length:
        let to = recs[o + SHOT_TO]
        let by = recs[o + SHOT_BY]
        let ax = recs[o + SHOT_X]
        let ay = recs[o + SHOT_Y]
        var d = recs[o + SHOT_DAMAGE]
        var j = index_of(to)
        let b = if j < 0: b_index_of(to) else: -1
        let src = recs[o + SHOT_SRC]
        if src >= 0 and t_splash[src] > 0:
            splash(o, recs, b)  // a stone lands on its spot, whoever is there
            o += SHOT_STRIDE
            continue
        if src >= 0 and t_pass_len[src] > 0: pass_through(o, recs, j)  // a bolt goes through those in its way
        if b >= 0:
            c_bhurt[b] += d
            if events_on: events.push(Event { EV_HIT, by, to, d, ax, ay })
        else:
            if j >= 0:
                let r = u_radius[j] + slack
                if t_air[u_kind[j]] == 0 and dist2(ax, ay, u_x[j], u_y[j]) > r * r: j = -1  // (a shot at an aircraft follows it: it never stops)
            if j < 0 and r_shot_strays == 1:
                j = stray(recs[o + SHOT_OWNER], ax, ay, slack)
                if j >= 0: d = shot_damage(recs[o + SHOT_SRC], recs[o + SHOT_UP], j)
            if j >= 0:
                c_hurt[j] += hook_on_hit(by, j, d)
                c_hurt_by[j] = by
                if events_on: events.push(Event { EV_HIT, by, u_id[j], d, ax, ay })
            elif events_on: events.push(Event { EV_MISS, by, to, 0, ax, ay })
        o += SHOT_STRIDE

def shots_inbound():
    for(u_x.length) i: c_inbound[i] = 0
    var o = 0
    while o < shots.length:
        let j = index_of(shots[o + SHOT_TO])
        if j >= 0: c_inbound[j] += shots[o + SHOT_DAMAGE]
        o += SHOT_STRIDE

// Finished buildings that attack shoot the nearest enemy units in reach: a volley of their own
// arrows plus one for each unit inside, one at each of the nearest foes in turn (Combat._towers).
def towers():
    for(b_id.length) b:
        let k = b_kind[b]
        if bt_attacks[k] and b_done[b] != 0:
            let arrows = bt_arrows[k] + b_inside[b].length / REC_SIZE
            if arrows > 0:
                if b_cooldown[b] > 0:
                    b_cooldown[b]--
                else:
                    let s = max(b_sx[b], b_sy[b]) * TILE
                    let mx = b_cx[b] * TILE + b_sx[b] * TILE / 2
                    let my = b_cy[b] * TILE + b_sy[b] * TILE / 2
                    let reach = bt_range[k] * TILE + bm_range[b_owner[b]][k] * TILE
                    let far = reach + s / 2 + (if has_heights: r_high_reach else: 0)
                    let limit = far * far + 1
                    let lv = level[b_cy[b] * W + b_cx[b]]
                    let near = []::int  // d * 2^24 + j... sorted: (distance squared, slot)
                    let ups = map(u_x.length): 0
                    let tr = far / TILE + 1
                    let tx = mx / TILE
                    let ty = my / TILE
                    var yy = max(ty - tr, 0)
                    while yy < min(ty + tr + 1, H):
                        var xx = max(tx - tr, 0)
                        while xx < min(tx + tr + 1, W):
                            let cell = yy * W + xx
                            var q = sp_start[cell]
                            while q < sp_end[cell]:
                                let j = sp_items[q]
                                q++
                                if is_foe(u_owner[j], b_owner[b]):
                                    let d = dist2(mx, my, u_x[j], u_y[j])
                                    var ok = true
                                    if has_heights:
                                        let dl = lv - level[cell_of(u_x[j], u_y[j])]
                                        ups[j] = if dl > 0: 1 elif dl < 0: -1 else: 0
                                        let r = reach + s / 2 + ups[j] * r_high_reach
                                        if d > r * r: ok = false
                                    if ok and d < limit: near.push(d * (1 << 20) + j)
                            xx++
                        yy++
                    if near.length:
                        sort_ints(near)
                        let atk = tower_atk(k)
                        for(arrows) a:
                            let e = near[a % near.length]
                            let best = e & ((1 << 20) - 1)
                            let kb = u_kind[best]
                            var dmg = boost(-1, best, bt_atk_class[k], damage(atk, t_arm[kb], t_cls[kb], r_min_damage), r_min_damage)
                            if ups[best] < 0: dmg = uphill(dmg)
                            loose(b_id[b], b_owner[b], mx, my, best, -1, dmg, -1 - k, ups[best], r_shot_speed)
                        b_cooldown[b] = bt_reload[k]

// Melee units closing in on building b each get a place of their own round it (Combat._surround).
let RINGS = 3
let RING_COST = 20000
let KEEP_PLACE = 1000

def surround(b:int, chasers:[int], hitters:[int]):
    let bid = b_id[b]
    let x0r, y0r, x1r, y1r = building_rect(b)
    var redo = (tick + bid) % REPLAN_EVERY == 0
    for(chasers) i:
        if u_reach[i] != 2 or u_fkey[i] != building_field(bid, false, lane(i)): redo = true
    if not redo:
        let slack = SLOT_ARRIVE * ARRIVE_SETTLE
        for(chasers) i:
            if u_moving[i] == 0 and dist2(u_x[i], u_y[i], u_tx[i], u_ty[i]) > slack * slack:
                order_beside(i, u_tx[i], u_ty[i], x0r, y0r, x1r, y1r, u_fkey[i])
        return
    var rmin = 1 << 20
    var rmax = 0
    for(chasers) i:
        rmin = min(rmin, u_radius[i])
        rmax = max(rmax, u_radius[i])
    for(hitters) i:
        rmin = min(rmin, u_radius[i])
        rmax = max(rmax, u_radius[i])
    let reach = r_melee_reach
    let space = 2 * rmax + FORM_GAP
    let x0 = x0r
    let y0 = y0r
    let x1 = x1r + 1
    let y1 = y1r + 1
    let px = []::int
    let py = []::int
    let ring_of = []::int
    for(RINGS) k:
        let o = rmin + reach / 2 + k * space
        let wd = x1 - x0 + 2 * o
        let ht = y1 - y0 + 2 * o
        let perim = 2 * (wd + ht)
        let count = max(perim / space, 4)
        for(count) m:
            var along = m * perim / count + space / 2
            along %= perim
            var qx = 0
            var qy = 0
            if along < wd:
                qx = x0 - o + along
                qy = y0 - o
            elif along < wd + ht:
                qx = x1 + o
                qy = y0 - o + along - wd
            elif along < 2 * wd + ht:
                qx = x1 + o - (along - wd - ht)
                qy = y1 + o
            else:
                qx = x0 - o
                qy = y1 + o - (along - 2 * wd - ht)
            var keep = true
            if k == 0:
                let dx = max(max(x0 - qx, 0), qx - x1)
                let dy = max(max(y0 - qy, 0), qy - y1)
                if isqrt(dx * dx + dy * dy) - rmin > reach: keep = false
            if keep:
                for(hitters) h:
                    let rr = rmax + u_radius[h]
                    if dist2(qx, qy, u_x[h], u_y[h]) < rr * rr * 3 / 4: keep = false
            if keep:
                px.push(qx)
                py.push(qy)
                ring_of.push(k)
    let keys = map(chasers) i: gap_b(i, b) * (1 << 20) + i
    sort_ints(keys)
    let claimed = map(px.length): 0
    for(keys) key:
        let i = key & ((1 << 20) - 1)
        let ln = lane(i)
        let fkey = building_field(bid, false, ln)
        let mine = u_reach[i] == 2 and u_fkey[i] == fkey
        var best = -1
        var best_d = 1 << 62
        for(px.length) k:
            if claimed[k] == 0 and walkable(px[k], py[k], ln):
                var d = isqrt(dist2(u_x[i], u_y[i], px[k], py[k])) + ring_of[k] * RING_COST
                if mine and px[k] == u_tx[i] and py[k] == u_ty[i]: d -= KEEP_PLACE
                if d < best_d:
                    best_d = d
                    best = k
        if best < 0:
            chase(i, -1, b)
        else:
            claimed[best] = 1
            if not mine or px[best] != u_tx[i] or py[best] != u_ty[i] or
                    (u_moving[i] == 0 and dist2(u_x[i], u_y[i], px[best], py[best]) > SLOT_ARRIVE * SLOT_ARRIVE * 16):
                order_beside(i, px[best], py[best], x0r, y0r, x1r, y1r, fkey)

// Land this tick's hits together, then remove the dead units and buildings (by descending slot).
// Units hit while idle (or walking back) turn on the attacker, unless passive.
def apply_hits(n:int):
    for(n) j:
        if c_hurt[j] != 0:
            u_hp[j] -= c_hurt[j]
            let k = u_kind[j]
            if t_animal[k] != 0: animal_hurt(j, c_hurt_by[j])  // a deer bolts, a sheep stands for the knife
            if u_foe[j] == 0 and (u_stance[j] == NONE or u_stance[j] == RETURN) and u_task[j] == T_NONE and not t_worker[k] and not (t_mounts[k].length and u_moving[j] != 0) and can_hit_id(k, c_hurt_by[j]) and
                    not t_harmless[k] and not t_healer[k] and not t_buildings_only[k] and u_posture[j] != PASSIVE:
                engage(j, c_hurt_by[j])
    // Bounties (Combat._bounties): a killer with kill_gold earns it for each enemy unit (not animals)
    // its last blow killed this tick. (Sticky hits: abilities, not ported, asserted by the exporter.)
    let gold = resource_index("gold")
    for(n) jj:
        if c_hurt[jj] > 0 and u_hp[jj] > 0: hook_on_hurt(jj, c_hurt_by[jj])
        if c_hurt[jj] != 0 and u_hp[jj] <= 0 and t_animal[u_kind[jj]] == 0:
            let kk = index_of(c_hurt_by[jj])
            if kk >= 0 and t_kill_gold[u_kind[kk]] != 0 and is_foe(u_owner[kk], u_owner[jj]): stock[gold][u_owner[kk]] += t_kill_gold[u_kind[kk]]
    var j = n - 1
    while j >= 0:
        if u_hp[j] <= 0:
            if events_on: events.push(Event { EV_DIE, u_id[j], 0, 0, u_x[j], u_y[j] })
            hook_on_death(j, c_hurt_by[j])
            if t_animal[u_kind[j]] == 0: lost[u_owner[j]]++
            remove_unit(j)
        j--
    var b = b_id.length - 1
    while b >= 0:
        if c_bhurt[b] != 0:
            b_hp[b] -= c_bhurt[b]
            if b_hp[b] <= 0:
                if events_on: events.push(Event { EV_DIE, b_id[b], 1, b_sx[b], b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2 })
                clear_farm(b)
                pen_gone(b)
                spill(b)
                breach(b)  // a wall piece leaves rubble
                occupy(footprint(b), 0)
                remove_building(b)
        b--

// One tick of fighting (Combat.tick). The spatial buckets must be built from the current positions.
// ---- Weapon mounts: guns that turn on their own, each with its own arc, aim, target and reload, firing on the move.
// A unit type without mounts is one implicit mount, the body: it fires as soon as it's in reach and off cooldown,
// whichever way it's going.

let MOUNT_STRIDE = 3  // a unit's u_mount: per mount, its aim, its target (a unit or building id, or 0) and its cooldown
let MOUNT_AIM = 0
let MOUNT_TARGET = 1
let MOUNT_COOLDOWN = 2
let HULL_STEP = 200                                                                                                                                                                 // milli-tiles a hull moves before its heading is worked out again
let AIR_ORBIT_STEP = 28                                                                                                                                                             // of 256 round a circle, an aircraft's next point
let ATAN_TENTHS = [ 0, 18, 36, 54, 71, 89, 106, 123, 140, 157, 174, 190, 206, 221, 236, 251, 266, 280, 294, 307, 320, 333, 345, 357, 369, 380, 391, 402, 412, 422, 432, 441, 450 ]  // atan(k / 32) in tenths of a degree

// The direction of a vector, tenths of a degree from +x towards +y, 0 to 3599 (integers only: the sim).
def angle_of(dx:int, dy:int) -> int:
    let big, small = max(abs(dx), abs(dy)), min(abs(dx), abs(dy))
    if big == 0: return 0
    let q = small * 32 / big
    var a = ATAN_TENTHS[q]
    if q < 32: a += (ATAN_TENTHS[q + 1] - a) * (small * 32 % big) / big
    if abs(dy) > abs(dx): a = 900 - a
    if dx < 0: a = 1800 - a
    if dy < 0: a = 3600 - a
    return a % 3600

// The shortest way round from angle a to angle b: -1800 to 1799.
def angle_gap(a:int, b:int) -> int: return (b - a + 5400) % 3600 - 1800

// Where a target (a unit or building id) is, and whether it's still there.
def gun_spot(g:int) -> int, int, bool:
    let j = index_of(g)
    if j >= 0: return u_x[j], u_y[j], true
    let b = b_index_of(g)
    if b >= 0: return b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2, true
    return 0, 0, false

// What a blow or a shot from unit i of type k does to unit j, with that attack.
def hit_with(i:int, k:int, atk:[int], j:int, up:int) -> int:
    let kj = u_kind[j]
    let floor = max(r_min_damage, t_min_damage[kj])
    let d = boost(i, j, t_damage[k], damage(atk, t_arm[kj], t_cls[kj], floor), floor)
    return if up < 0: uphill(d) else: d
def hit_on_unit(i:int, k:int, j:int, up:int) -> int: return hit_with(i, k, t_atk[k], j, up)

// A shot at a unit: what it does, what it's owed, and on its way.
def shoot_unit(i:int, k:int, j:int, up:int):
    let d = hit_on_unit(i, k, j, up)
    c_inbound[j] += d
    loose(u_id[i], u_owner[i], u_x[i], u_y[i], j, -1, d, k, up, t_shot_speed[k])

// A mount's weapon: its own, or the unit's.
def mount_reach(k:int, m:Mount) -> int: return if m.range > 0: m.range else: t_reach[k]
def mount_reload(k:int, m:Mount) -> int: return if m.reload > 0: m.reload else: t_reload[k]
def mount_atk(k:int, m:Mount) -> [int]: return if m.atk.length: m.atk else: t_atk[k]

// Where a mount points when it has nothing to shoot at, by the hull's heading.
def mount_rest(i:int, m:Mount) -> int: return (u_hull[i] + m.rest) % 3600

// Is that spot within the mount's arc?
def mount_covers(i:int, m:Mount, x:int, y:int) -> bool:
    if x == u_x[i] and y == u_y[i]: return true
    return m.arc >= 1800 or abs(angle_gap(mount_rest(i, m), angle_of(x - u_x[i], y - u_y[i]))) <= m.arc

// Can this mount shoot at that (a unit or building id)? In reach, not too close, and in its arc.
def mount_can_shoot(i:int, k:int, m:Mount, g:int) -> bool:
    let x, y, real = gun_spot(g)
    if not real: return false
    let j = index_of(g)
    if j >= 0 and not can_hit(k, j): return false
    let b = if j >= 0: -1 else: b_index_of(g)
    let d = gap_to(i, j, b)
    return d >= t_min_range[k] and d <= mount_reach(k, m) + height_step(i, j, b) * r_high_reach and mount_covers(i, m, x, y)

// The nearest foe this mount could shoot, or 0: by distance, then id, so it's the same on every machine.
def mount_pick(i:int, k:int, m:Mount) -> int:
    let me = u_owner[i]
    if me == gaia: return 0
    let reach = mount_reach(k, m) + TILE / 2
    let r = reach / TILE + 1
    let cx, cy = u_x[i] / TILE, u_y[i] / TILE
    var best = 0
    var best_d = 1 << 40
    var yy = max(cy - r, 0)
    let y1 = min(cy + r + 1, H)
    while yy < y1:
        var xx = max(cx - r, 0)
        let x1 = min(cx + r + 1, W)
        while xx < x1:
            let cell = yy * W + xx
            var q = sp_start[cell]
            let e = sp_end[cell]
            while q < e:
                let j = sp_items[q]
                q++
                if not is_foe(u_owner[j], me) or t_animal[u_kind[j]] != 0: continue
                if not fog_visible(me, u_x[j], u_y[j]) or not mount_can_shoot(i, k, m, u_id[j]): continue
                let d = dist2(u_x[i], u_y[i], u_x[j], u_y[j])
                if d < best_d or (d == best_d and u_id[j] < best):
                    best_d = d
                    best = u_id[j]
            xx++
        yy++
    return best

// An aircraft doesn't hover to fire: it flies round what it's shooting at, on to a point a little further round each
// time it gets near the last.
def air_orbit(i:int, k:int, x:int, y:int):
    if u_moving[i] != 0 and dist2(u_x[i], u_y[i], u_tx[i], u_ty[i]) > TILE * TILE: return
    let next = angle_of(u_x[i] - x, u_y[i] - y) * 256 / 3600 + AIR_ORBIT_STEP
    let r = t_reach[k] * 3 / 4
    order_direct(i, clamp(x + cos_a(next) * r / ONE, 0, W * TILE - 1), clamp(y + sin_a(next) * r / ONE, 0, H * TILE - 1))

// A unit's mounts for a tick: the hull's heading from how it moved, then each mount in turn: on the unit's foe if it
// can shoot it, else on what it's on, else on the nearest it can; turning towards that, or back to its rest; firing once
// it's laid on, without stopping the unit.
def mounts_tick(i:int, k:int):
    let mx, my = u_x[i] - u_lx[i], u_y[i] - u_ly[i]
    if mx * mx + my * my >= HULL_STEP * HULL_STEP:
        u_hull[i] = angle_of(mx, my)
        u_lx[i] = u_x[i]
        u_ly[i] = u_y[i]
    let st = u_mount[i]
    for(t_mounts[k]) m, n:
        let o = n * MOUNT_STRIDE
        if st.length <= o:  // (new to these mounts: a unit just made, a save from before them, a line upgraded)
            st.push(mount_rest(i, m))
            st.push(0)
            st.push(0)
        if st[o + MOUNT_COOLDOWN] > 0: st[o + MOUNT_COOLDOWN]--
        if u_foe[i] != 0 and mount_can_shoot(i, k, m, u_foe[i]): st[o + MOUNT_TARGET] = u_foe[i]
        elif st[o + MOUNT_TARGET] != 0 and not mount_can_shoot(i, k, m, st[o + MOUNT_TARGET]): st[o + MOUNT_TARGET] = 0
        if st[o + MOUNT_TARGET] == 0 and u_posture[i] != PASSIVE and (tick + u_id[i] + n) % r_acquire_every == 0:
            st[o + MOUNT_TARGET] = mount_pick(i, k, m)
        let x, y, real = gun_spot(st[o + MOUNT_TARGET])
        let rest = mount_rest(i, m)
        var want = rest
        if real and (x != u_x[i] or y != u_y[i]): want = angle_of(x - u_x[i], y - u_y[i])
        var aim = (st[o + MOUNT_AIM] + clamp(angle_gap(st[o + MOUNT_AIM], want), -m.turn, m.turn) + 3600) % 3600
        if m.arc < 1800: aim = (rest + clamp(angle_gap(rest, aim), -m.arc, m.arc) + 3600) % 3600  // (the hull turned under it)
        st[o + MOUNT_AIM] = aim
        if real and st[o + MOUNT_COOLDOWN] == 0 and abs(angle_gap(aim, want)) <= m.tolerance:
            st[o + MOUNT_COOLDOWN] = mount_reload(k, m)
            mount_fire(i, k, m, n, st[o + MOUNT_TARGET])

// A mount fires at a unit or a building.
def mount_fire(i:int, k:int, m:Mount, n:int, g:int):
    let atk = mount_atk(k, m)
    let j = index_of(g)
    if j >= 0:
        let up = height_step(i, j, -1)
        let d = hit_with(i, k, atk, j, up)
        c_inbound[j] += d
        loose(u_id[i], u_owner[i], u_x[i], u_y[i], j, -1, d, k, up, t_shot_speed[k], n)
    else:
        let b = b_index_of(g)
        let up = height_step(i, -1, b)
        var d = boost(i, -1, t_damage[k], damage(atk, bm_arm[b_owner[b]][b_kind[b]], building_cls(), r_min_damage), r_min_damage)
        if up < 0: d = uphill(d)
        loose(u_id[i], u_owner[i], u_x[i], u_y[i], -1, b, d, k, up, t_shot_speed[k], n)

def combat_tick():
    let brhurt = map(br_id.length): 0  // this tick's damage to each map bridge
    let n = u_x.length
    let nb = b_id.length
    for(n) i:
        c_hurt[i] = 0
        c_hurt_by[i] = 0
        c_engaged[i] = 0
    while c_bhurt.length < nb: c_bhurt.push(0)
    for(c_bhurt.length) b: c_bhurt[b] = 0
    for(n) i:
        if u_foe[i] != 0:
            let j = index_of(u_foe[i])
            if j >= 0: c_engaged[j]++
    for(n) i:
        if u_cooldown[i] > 0: u_cooldown[i]--
    land()
    c_aura = auras()
    shots_inbound()
    let chasers = map(nb): []::int
    let hitters = map(nb): []::int
    for(n) i:
        let k = u_kind[i]
        if u_stance[i] == RETURN and u_moving[i] == 0: u_stance[i] = NONE
        if t_healer[k] or t_harmless[k]: continue
        if t_mounts[k].length: mounts_tick(i, k)
        let stance = u_stance[i]
        let posture = u_posture[i]
        if (tick + u_id[i]) % r_acquire_every == 0:
            let idle = stance == NONE and u_moving[i] == 0 and u_task[i] == T_NONE and not t_worker[k] and posture != PASSIVE
            let free = stance == AUTO or stance == ATTACK_MOVE
            var crowded = false
            if u_foe[i] != 0 and free:
                let cur = index_of(u_foe[i])
                crowded = cur >= 0 and c_engaged[cur] > CROWDED
            if (u_foe[i] == 0 and (idle or stance == ATTACK_MOVE)) or crowded:
                let am = stance == ATTACK_MOVE  // (a block on the march keeps its ranks: only what it can reach; there, all it sees)
                var f = nearest_foe(i, if am and u_block[i] > 0 and fb_state[u_block[i] - 1] != BLOCK_THERE: t_reach[k] + u_radius[i] + BLOCK_LEASH elif am: sight_of(i) else: look(i), am or t_buildings_only[k] != 0, if posture == STAND and not am: 0 else: SPREAD,
                                    false, near_of(i), not t_buildings_only[k])
                if crowded and t_ranged[k] and f != 0 and gap(i, index_of(u_foe[i])) <= t_reach[k]:
                    let fj = index_of(f)
                    if fj < 0 or gap(i, fj) > t_reach[k]: f = 0
                if f != 0 and f != u_foe[i]:
                    let old = if u_foe[i] != 0: index_of(u_foe[i]) else: -1
                    if old >= 0: c_engaged[old]--
                    u_foe[i] = f
                    let nj = index_of(f)
                    if nj >= 0: c_engaged[nj]++
                    if idle: engage(i, f)
        if u_foe[i] == 0: continue
        var j = index_of(u_foe[i])
        let b = if j >= 0: -1 else: b_index_of(u_foe[i])
        let br = if j < 0 and b < 0 and br_id.length > 0: bridge_index(u_foe[i]) else: -1
        if br >= 0 and br_up[br] == 1:  // breaking a bridge: walk up to it and hack away
            if bridge_gap(i, br) <= t_reach[k]:
                u_moving[i] = 0
                if u_cooldown[i] == 0:
                    u_cooldown[i] = t_reload[k]
                    let d = bridge_damage(t_atk[k], r_min_damage)
                    brhurt[br] += d
                    if events_on: events.push(Event { EV_HIT, u_id[i], u_foe[i], d, u_x[i], u_y[i] })
            elif bridge_gap(i, br) <= REACH + TILE:
                order_direct(i, clamp(u_x[i], br_x0[br], br_x1[br]), clamp(u_y[i], br_y0[br], br_y1[br]))
            else:
                let key = building_field(u_foe[i], false, lane(i))
                if u_moving[i] == 0 or u_fkey[i] != key: order_reach(i, br_x0[br], br_y0[br], br_x1[br], br_y1[br], key)
            continue
        if j < 0 and b < 0:
            let next = if u_stance[i] == ATTACK_MOVE: nearest_foe(i, sight_of(i), true, SPREAD, false, near_of(i), not t_buildings_only[k]) else: 0
            if next != 0:
                u_foe[i] = next
                let nj = index_of(next)
                if nj >= 0: c_engaged[nj]++
            else:
                lost_foe(i)
            continue
        if j >= 0 and not can_hit(k, j):
            lost_foe(i)  // it can't touch an aircraft
            continue
        if j >= 0 and not t_ranged[k] and (u_perch[i] != 0) != (u_perch[j] != 0):
            lost_foe(i)  // melee can't reach up onto a wall, nor down off one
            continue
        let g = gap_to(i, j, b)
        var up = if t_ranged[k]: height_step(i, j, b) else: 0
        if t_min_range[k] > 0 and g < t_min_range[k]:
            too_close(i, j, b)  // an engine can't hit what's under its nose
            continue
        if g <= t_reach[k] + up * r_high_reach + (if (t_ranged[k] or b >= 0) and u_moving[i] == 0: HOLD else: 0):
            if t_air[k] != 0:
                let ox, oy, there = gun_spot(u_foe[i])
                if there: air_orbit(i, k, ox, oy)
            else:
                u_moving[i] = 0
            if b >= 0: hitters[b].push(i)
            if t_unpack[k] > 0 and u_ready[i] < t_unpack[k]: continue  // still unpacking: it throws once it's set up
            if u_cooldown[i] == 0 and j >= 0 and t_ranged[k] and c_inbound[j] >= u_hp[j] and u_stance[i] != ORDERED:
                let f = nearest_foe(i, t_reach[k] + u_radius[i] + TILE / 2, false, SPREAD, true, near_of(i), true)
                let fj = if f != 0: index_of(f) else: -1
                if fj < 0 or gap(i, fj) > t_reach[k] + height_step(i, fj, -1) * r_high_reach: continue
                c_engaged[j]--
                c_engaged[fj]++
                u_foe[i] = f
                j = fj
                up = height_step(i, j, -1)
            if t_mounts[k].length: continue  // (its mounts shoot, in mounts_tick)
            if u_cooldown[i] == 0:
                u_cooldown[i] = t_reload[k]
                if j >= 0:
                    if t_ranged[k]:
                        shoot_unit(i, k, j, up)
                    else:
                        let d = hit_on_unit(i, k, j, up)
                        c_hurt[j] += hook_on_hit(u_id[i], j, d)
                        c_hurt_by[j] = u_id[i]
                        if events_on: events.push(Event { EV_HIT, u_id[i], u_id[j], d, u_x[j], u_y[j] })
                else:
                    var d = boost(i, -1, t_damage[k], damage(t_atk[k], bm_arm[b_owner[b]][b_kind[b]], building_cls(), r_min_damage), r_min_damage)
                    if up < 0: d = uphill(d)
                    if t_ranged[k]:
                        loose(u_id[i], u_owner[i], u_x[i], u_y[i], -1, b, d, k, up, t_shot_speed[k])
                    elif t_blast[k] > 0:
                        blast(i, b, d)  // the sapper's charge goes off, and the sapper with it
                    else:
                        c_bhurt[b] += d
                        if events_on: events.push(Event { EV_HIT, u_id[i], b_id[b], d, u_x[i], u_y[i] })
        elif u_perch[i] != 0:
            if j >= 0 and u_perch[j] != 0 and not t_ranged[k] and on_net(dist_from(u_perch[i] - 1), u_perch[j] - 1):
                if u_wgoal[i] != u_perch[j] and u_wtime[i] == 0:
                    wall_walk(i, u_perch[j] - 1)  // along the walkway to the foe up here
                    u_foe[i] = u_id[j]
                    u_stance[i] = AUTO
            else:
                u_foe[i] = 0  // up on a wall: out of reach, let it go (it never chases off the wall)
                u_stance[i] = NONE
        elif u_stance[i] == AUTO and posture == STAND:
            u_foe[i] = 0
            u_stance[i] = NONE
            u_moving[i] = 0
        elif u_stance[i] == AUTO and posture == DEFENSIVE and dist2(u_x[i], u_y[i], u_gx[i], u_gy[i]) > r_leash * r_leash:
            go_back(i)
        elif u_stance[i] == AUTO and (g > r_sight + 2 * TILE or (j >= 0 and u_owner[i] != gaia and not fog_visible(u_owner[i], u_x[j], u_y[j]))):
            lost_foe(i)
        elif b >= 0 and not t_ranged[k]:
            chasers[b].push(i)
        else:
            chase(i, j, b)
    for(nb) b:  // (slots ascending: GDScript sorts the besieged buildings' slots)
        if chasers[b].length: surround(b, chasers[b], hitters[b])
    towers()
    pour()
    apply_hits(n)
    for(brhurt) d, kb:
        if d > 0: bridge_hurt(kb, d)
