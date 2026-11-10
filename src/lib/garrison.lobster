// ------------------------------------------------------------------ garrisons (garrison.gd)
// Units sheltering inside their own buildings: out of the units arrays altogether, kept on the
// building as a record (REC_*), healed 1 hp every heal_every ticks, an arrow each in its volley.
// Coming out they take their old id and slot back, beside the building. The Town Center's call to
// arms sends the workers near it into the nearest building with room; back to work brings them out.
// GARRISON sends units in by hand, UNGARRISON brings everyone out (toward the rally point).

let T_GARRISON = 4  // economy.gd NONE, GATHER, RETURN, BUILD, GARRISON

def capacity(b:int) -> int:
    return if b_done[b] == 1: bt_garrison[b_kind[b]] else: 0

def can_hold(b:int, i:int) -> bool:
    if capacity(b) <= 0 or b_owner[b] != u_owner[i]: return false
    let k = u_kind[i]
    if t_animal[k] != 0: return false
    if t_worker[k]: return true
    for(garrison_not) c:
        if c >= 0 and contains(t_tags[k], c): return false
    return true

def room(b:int) -> int:
    let bid = b_id[b]
    var coming = 0
    for(u_x.length) i:
        if u_task[i] == T_GARRISON and u_target[i] == bid: coming++
    return capacity(b) - b_inside[b].length / REC_SIZE - coming

// Send unit i into building b (it walks up and goes in); a worker keeps its `home`.
def send_in(i:int, b:int):
    let home = if u_task[i] == GATHER or u_task[i] == T_RETURN: u_home[i] else: -1
    u_foe[i] = 0
    u_stance[i] = 0
    u_patient[i] = 0
    u_task[i] = T_GARRISON
    u_target[i] = b_id[b]
    u_home[i] = home
    u_work[i] = 0
    approach_building(i, b)

def b_centre(b:int) -> int, int:
    return b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2

// The player's workers within call_range of the building each go into the nearest building with room.
def cmd_call_to_arms(p:int, bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p: return
    let r = r_call_range * TILE
    let cx, cy = b_centre(b)
    let left = map(b_id.length) k: if b_owner[k] == p and capacity(k) > 0: room(k) else: 0
    for(u_x.length) i:
        if u_owner[i] == p and is_worker(i) and u_task[i] != T_GARRISON and dist2(u_x[i], u_y[i], cx, cy) <= r * r:
            var best = -1
            var best_d = 1 << 62
            for(b_id.length) k:
                if left[k] > 0 and can_hold(k, i):
                    let kx, ky = b_centre(k)
                    let d = dist2(u_x[i], u_y[i], kx, ky)
                    if d < best_d:
                        best_d = d
                        best = k
            if best >= 0:
                left[best]--
                send_in(i, best)

// A worker back to its job: the resource it was gathering (or the nearest of the same), else idle.
def resume(i:int):
    var home = u_home[i]
    clear_task(i)
    u_moving[i] = 0
    if home < 0: return
    var kind = res_at(home)
    if kind <= 0:
        kind = u_carry_kind[i]
        home = if kind > 0: nearest_resource(u_x[i], u_y[i], kind, i, false, false, true) else: -1
    if home >= 0: start_gather(i, home, kind)

def cmd_back_to_work(p:int):
    for(u_x.length) i:
        if u_owner[i] == p and u_task[i] == T_GARRISON and is_worker(i): resume(i)
    for(b_id.length) b:
        if b_owner[b] == p:
            var k = b_inside[b].length / REC_SIZE - 1
            while k >= 0:
                if t_worker[b_inside[b][k * REC_SIZE + REC_KIND]]: resume(come_out(b, k))
                k--

// Everyone inside building b comes out (it fell).
def spill(b:int):
    while b_inside[b].length: come_out(b, b_inside[b].length / REC_SIZE - 1)

// Record k of building b comes out beside it (nearest its rally point), with its old id, health,
// stance and load. Its slot.
def come_out(b:int, k:int) -> int:
    let o = k * REC_SIZE
    let rec = slice(b_inside[b], o, REC_SIZE)
    b_inside[b].remove_range(o, REC_SIZE)
    let kind = rec[REC_KIND]
    var cell = spawn_cell_loose(b, kind)
    if cell < 0: cell = nearest_walkable(b_cy[b] * W + b_cx[b], lane_base[b_owner[b]] + t_mclass[kind])
    let x, y = clear_point(b_owner[b], kind, (cell % W) * TILE + TILE / 2, (cell / W) * TILE + TILE / 2)  // (not on top of the one out before it, #394)
    let i = insert_unit(rec[REC_ID], b_owner[b], kind, x, y, t_speed[kind], t_radius[kind], rec[REC_HP])
    u_mclass[i] = t_mclass[kind]
    u_posture[i] = rec[REC_POSTURE]
    u_carry_kind[i] = rec[REC_CARRY_KIND]
    u_carry[i] = rec[REC_CARRY]
    u_home[i] = rec[REC_HOME]
    grow_scratch()
    return i

// Unit i goes inside building b: out of the arrays, onto the building's records (by id).
def enter(i:int, b:int):
    let rec = [ u_id[i], u_kind[i], u_hp[i], u_posture[i], u_carry_kind[i], u_carry[i], u_home[i] ]
    let recs = b_inside[b]
    var at = 0
    while at < recs.length and recs[at + REC_ID] < rec[REC_ID]: at += REC_SIZE
    for(rec) v, n: recs.insert(at + n, v)
    remove_unit(i)

// One tick: units on their way in go in once beside their building (or give up); those inside heal.
def garrison_tick():
    var i = u_x.length - 1
    while i >= 0:
        if u_task[i] == T_GARRISON:
            let b = b_index_of(u_target[i])
            if b < 0 or not can_hold(b, i) or b_inside[b].length / REC_SIZE >= capacity(b):
                clear_task(i)
                u_moving[i] = 0
            else:
                let x0, y0, x1, y1 = building_rect(b)
                if in_reach(i, x0, y0, x1, y1):
                    enter(i, b)
                elif u_moving[i] == 0:
                    if u_stuck[i] >= GIVE_UP: clear_task(i)
                    else: approach_building(i, b)
        i--
    if tick % r_garrison_heal_every != 0: return
    for(b_id.length) b:
        let recs = b_inside[b]
        var o = 0
        while o < recs.length:
            if recs[o + REC_HP] < t_hp[recs[o + REC_KIND]]: recs[o + REC_HP]++
            o += REC_SIZE

// Commands.GARRISON {ids, building}: the player's units go inside the player's building, while it has room.
def cmd_garrison(p:int, ids:[int], bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p: return
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and can_hold(b, i) and room(b) > 0: send_in(i, b)

// Commands.UNGARRISON {building}: everyone inside comes out, in id order, and makes for the rally point.
def cmd_ungarrison(p:int, bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p: return
    let out = []::int
    while b_inside[b].length: out.push(u_id[come_out(b, b_inside[b].length / REC_SIZE - 1)])
    qsort_in_place(out) x, y: x < y
    for(out) uid: go_to_rally(b, index_of(uid))
