// ------------------------------------------------------------------ siege weapons (combat.gd, World._pack)
// Engines with a minimum range step back from a foe under their nose; a stone lands on its spot and
// hurts whoever is there (friends a share, falling off to the rim); a bolt goes through the foes on
// the last stretch of its flight; a sapper's charge blows up a building, everyone near, and itself;
// the great sling unpacks before it throws and packs up before it rolls.

let BASE_RADIUS = 300  // a foot soldier's body, for minimum-range looks
let BACK_OFF = 1500    // how far beyond its minimum range an engine steps back
let MAX_BODY = 500     // the biggest body's radius: how far round a spot to look

var r_splash_friend_pct = 100

// How near (centre to centre) a foe may be for a unit with a minimum range to still hit it.
def near_of(i:int) -> int:
    let k = u_kind[i]
    return if t_min_range[k] > 0: t_min_range[k] + u_radius[i] + BASE_RADIUS else: 0

// Engine i's foe is inside its minimum range: another foe it can hit from here (not an ordered
// target), else it steps back straight away from the foe, re-aimed on its re-plan beat.
def too_close(i:int, j:int, b:int):
    let k = u_kind[i]
    if u_stance[i] != ORDERED:
        let f = nearest_foe(i, t_reach[k] + u_radius[i] + TILE / 2, b >= 0, SPREAD, false, near_of(i), true)
        if f != 0 and f != u_foe[i]:
            let fj = index_of(f)
            if j >= 0: c_engaged[j]--
            if fj >= 0: c_engaged[fj]++
            u_foe[i] = f
            return
    if u_moving[i] == 1 and (tick + u_id[i]) % REPLAN_EVERY != 0: return
    var fx = 0
    var fy = 0
    if j >= 0:
        fx = u_x[j]
        fy = u_y[j]
    else:
        fx = clamp(u_x[i], b_cx[b] * TILE, (b_cx[b] + b_sx[b]) * TILE)
        fy = clamp(u_y[i], b_cy[b] * TILE, (b_cy[b] + b_sy[b]) * TILE)
    var dx = u_x[i] - fx
    let dy = u_y[i] - fy
    var len = isqrt(dx * dx + dy * dy)
    if len == 0:
        dx = 1
        len = 1
    let away = t_min_range[k] + BACK_OFF
    let x = clamp(fx + dx * away / len, 0, W * TILE - 1)
    let y = clamp(fy + dy * away / len, 0, H * TILE - 1)
    order_move(i, x, y, 0, 0, -1, -1, 0)

def is_beast(j:int) -> bool: return u_owner[j] == gaia or t_animal[u_kind[j]] != 0

// A stone lands: every unit whose body is within the splash of the spot takes the shooter's damage
// against its armour, falling off to nothing at the rim; friends a share; the building it was
// thrown at in full, other enemy buildings in the splash by the same falloff.
def splash(o:int, recs:[int], b:int):
    let src = recs[o + SHOT_SRC]
    let by = recs[o + SHOT_BY]
    let owner = recs[o + SHOT_OWNER]
    let x = recs[o + SHOT_X]
    let y = recs[o + SHOT_Y]
    let up = recs[o + SHOT_UP]
    let r = t_splash[src]
    if events_on: events.push(Event { EV_SPLASH, by, 0, r, x, y })
    let reach = (r + MAX_BODY) / TILE + 1
    let cx = x / TILE
    let cy = y / TILE
    var yy = max(cy - reach, 0)
    while yy < min(cy + reach + 1, H):
        var xx = max(cx - reach, 0)
        while xx < min(cx + reach + 1, W):
            let cell = yy * W + xx
            var q = sp_start[cell]
            while q < sp_end[cell]:
                let k = sp_items[q]
                q++
                if u_id[k] != by and not is_beast(k) and t_air[u_kind[k]] == 0:
                    let g = max(0, isqrt(dist2(x, y, u_x[k], u_y[k])) - u_radius[k])
                    if g < r:
                        let kk = u_kind[k]
                        var d = damage(t_atk[src], t_arm[kk], t_cls[kk], max(r_min_damage, t_min_damage[kk]))
                        if up < 0: d = uphill(d)
                        d = d * (r - g) / r
                        if not is_enemy(owner, u_owner[k]): d = d * r_splash_friend_pct / 100
                        if d > 0:
                            c_hurt[k] += hook_on_hit(by, k, d)
                            c_hurt_by[k] = by
                            if events_on: events.push(Event { EV_HIT, by, u_id[k], d, x, y })
            xx++
        yy++
    for(b_id.length) k:
        if k == b or is_enemy(owner, b_owner[k]):
            let gx = max(max(b_cx[k] * TILE - x, 0), x - (b_cx[k] + b_sx[k]) * TILE)
            let gy = max(max(b_cy[k] * TILE - y, 0), y - (b_cy[k] + b_sy[k]) * TILE)
            let g = isqrt(gx * gx + gy * gy)
            if k == b or g < r:
                var d = damage(t_atk[src], bm_arm[b_owner[k]][b_kind[k]], building_cls(), r_min_damage)
                if up < 0: d = uphill(d)
                if k != b: d = d * (r - g) / r
                if d > 0:
                    c_bhurt[k] += d
                    if events_on: events.push(Event { EV_HIT, by, b_id[k], d, x, y })

// A sapper's charge goes off against building b: b takes the blow (a wall or gate at least
// blast_line_pct of its hit points), other buildings and units within the blast less further out,
// friends a share; the sapper itself is spent.
def blast(i:int, b:int, d:int):
    let k0 = u_kind[i]
    let by = u_id[i]
    let owner = u_owner[i]
    let x = u_x[i]
    let y = u_y[i]
    let r = t_blast[k0]
    if events_on: events.push(Event { EV_SPLASH, by, 1, r, x, y })
    for(b_id.length) k:
        let gx = max(max(b_cx[k] * TILE - x, 0), x - (b_cx[k] + b_sx[k]) * TILE)
        let gy = max(max(b_cy[k] * TILE - y, 0), y - (b_cy[k] + b_sy[k]) * TILE)
        let g = isqrt(gx * gx + gy * gy)
        if k == b or g < r:
            let bk = b_kind[k]
            var dk = if k == b: d else: damage(t_atk[k0], bm_arm[b_owner[k]][bk], building_cls(), r_min_damage) * (r - g) / r
            if k == b and (bt_line[bk] or bt_gate[bk]): dk = max(dk, bm_hp[b_owner[k]][bk] * t_blast_line[k0] / 100)
            if not is_enemy(owner, b_owner[k]): dk = dk * r_splash_friend_pct / 100
            if dk > 0:
                c_bhurt[k] += dk
                if events_on: events.push(Event { EV_HIT, by, b_id[k], dk, x, y })
    let reach = (r + MAX_BODY) / TILE + 1
    let cx = x / TILE
    let cy = y / TILE
    var yy = max(cy - reach, 0)
    while yy < min(cy + reach + 1, H):
        var xx = max(cx - reach, 0)
        while xx < min(cx + reach + 1, W):
            let cell = yy * W + xx
            var q = sp_start[cell]
            while q < sp_end[cell]:
                let k = sp_items[q]
                q++
                if k != i and not is_beast(k) and t_air[u_kind[k]] == 0:
                    let g = max(0, isqrt(dist2(x, y, u_x[k], u_y[k])) - u_radius[k])
                    if g < r:
                        let kk = u_kind[k]
                        var dk = damage(t_atk[k0], t_arm[kk], t_cls[kk], max(r_min_damage, t_min_damage[kk])) * (r - g) / r
                        if not is_enemy(owner, u_owner[k]): dk = dk * r_splash_friend_pct / 100
                        if dk > 0:
                            c_hurt[k] += hook_on_hit(by, k, dk)
                            c_hurt_by[k] = by
                            if events_on: events.push(Event { EV_HIT, by, u_id[k], dk, x, y })
            xx++
        yy++
    c_hurt[i] += u_hp[i]
    c_hurt_by[i] = by

// A bolt goes through every foe (not the one aimed at, not animals) on the last `pass` of its flight.
def pass_through(o:int, recs:[int], aimed:int):
    let src = recs[o + SHOT_SRC]
    let by = recs[o + SHOT_BY]
    let owner = recs[o + SHOT_OWNER]
    let x1 = recs[o + SHOT_X]
    let y1 = recs[o + SHOT_Y]
    let dx = x1 - recs[o + SHOT_X0]
    let dy = y1 - recs[o + SHOT_Y0]
    let len = isqrt(dx * dx + dy * dy)
    if len == 0: return
    let run = min(t_pass_len[src], len)
    let x0 = x1 - dx * run / len
    let y0 = y1 - dy * run / len
    let slack = r_shot_slack
    let lox = (min(x0, x1) - MAX_BODY - slack) / TILE
    let loy = (min(y0, y1) - MAX_BODY - slack) / TILE
    let hix = (max(x0, x1) + MAX_BODY + slack) / TILE
    let hiy = (max(y0, y1) + MAX_BODY + slack) / TILE
    var yy = max(loy, 0)
    while yy < min(hiy + 1, H):
        var xx = max(lox, 0)
        while xx < min(hix + 1, W):
            let cell = yy * W + xx
            var q = sp_start[cell]
            while q < sp_end[cell]:
                let k = sp_items[q]
                q++
                if k != aimed and u_id[k] != recs[o + SHOT_TO] and is_foe(u_owner[k], owner) and t_animal[u_kind[k]] == 0:
                    let px = u_x[k] - x0
                    let py = u_y[k] - y0
                    let along = clamp((px * (x1 - x0) + py * (y1 - y0)) / max(1, run), 0, run)
                    let nx = x0 + (x1 - x0) * along / max(1, run)
                    let ny = y0 + (y1 - y0) * along / max(1, run)
                    let rr = u_radius[k] + slack
                    if dist2(nx, ny, u_x[k], u_y[k]) <= rr * rr:
                        let kk = u_kind[k]
                        let d = damage(t_atk[src], t_arm[kk], t_cls[kk], max(r_min_damage, t_min_damage[kk]))
                        c_hurt[k] += hook_on_hit(by, k, d)
                        c_hurt_by[k] = by
                        if events_on: events.push(Event { EV_HIT, by, u_id[k], d, u_x[k], u_y[k] })
            xx++
        yy++

// Engines that pack and unpack (World._pack): standing still it unpacks (ready counts up to its
// unpack); told to move once set up, it packs first (ready -pack counting back to 0, held still).
def pack_tick():
    for(u_x.length) i:
        let k = u_kind[i]
        if t_unpack[k] != 0:
            var r = u_ready[i]
            if r < 0:
                r++
                u_speed[i] = if r < 0: 0 else: t_speed[k]
                u_stuck[i] = 0
                u_prog[i] = -1
            elif u_moving[i] == 1:
                if r >= t_unpack[k] and t_pack[k] > 0:
                    r = -t_pack[k]
                    u_speed[i] = 0
                else:
                    r = 0
            else:
                r = min(r + 1, t_unpack[k])
            u_ready[i] = r
