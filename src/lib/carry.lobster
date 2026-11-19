// ------------------------------------------------------------------ carriers and the request queue (Casaide/creel#49)
// In a stocked economy (#48) goods move by hand. A building asks for goods (want: b_want), a carrier takes them from
// the nearest store holding them and walks them over. A job reserves the goods at its source (b_resv) and takes the
// want off its destination, so two carriers never chase one log. Matching runs on changes only: a player is looked at
// again when a want, a store's goods or a carrier changes (carry_dirty), at most CARRY_MATCHES jobs a tick, buildings
// and carriers in id order. A job whose carrier is gone or took other orders gives its reservations back.

let T_CARRY = 8
let CARRY_TO_SOURCE = 0
let CARRY_TO_DEST = 1
let CARRY_MATCHES = 8   // jobs made per player per tick, at most: keeps the worst tick flat
let CARRY_BACKSTOP = 20  // every this many ticks each player is looked at anyway (a carrier trained, a site placed)

def mark_carry(p:int):
    if p >= 0 and p < carry_dirty.length: carry_dirty[p] = 1

// Building b asks for n more of resource r.
def want(b:int, r:int, n:int):
    b_want[b][r] += n
    mark_carry(b_owner[b])

def offered(b:int, r:int) -> int: return b_hold[b][r] - b_resv[b][r]

// Does building b of player p give r to carriers? A store does, and so does a workshop's out slot (bt_offer).
def gives(b:int, p:int, r:int) -> bool: return b_owner[b] == p and b_done[b] != 0 and (bt_store[b_kind[b]] != 0 or bt_offer[b_kind[b]][r] != 0)

def job_index(jid:int) -> int:
    let found, at = binary_search(jb_id, jid)
    return if found: at else: -1

def is_carrier_free(i:int, p:int) -> bool: return u_owner[i] == p and t_carrier[u_kind[i]] != 0 and u_task[i] == T_NONE

def mid_dist2(b:int, x:int, y:int) -> int: return dist2(x, y, b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2)

// p's finished store nearest building `to` that offers r, not `to` itself; -1 if none.
def carry_source(p:int, r:int, to:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    let x = b_cx[to] * TILE + b_sx[to] * TILE / 2
    let y = b_cy[to] * TILE + b_sy[to] * TILE / 2
    for(b_id.length) b:
        if b != to and gives(b, p, r) and offered(b, r) > 0:
            let d2 = mid_dist2(b, x, y)
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

// p's free carrier nearest building b; -1 if none.
def free_carrier(p:int, b:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    for(u_x.length) i:
        if is_carrier_free(i, p):
            let d2 = mid_dist2(b, u_x[i], u_y[i])
            if d2 < best_d2:
                best_d2 = d2
                best = i
    return best

def start_job(i:int, src:int, dst:int, r:int, n:int, wanted:bool):
    let jid = next_job++
    jb_id.push(jid)
    jb_unit.push(u_id[i])
    jb_from.push(b_id[src])
    jb_to.push(b_id[dst])
    jb_res.push(r)
    jb_n.push(n)
    jb_phase.push(CARRY_TO_SOURCE)
    jb_want.push(if wanted: 1 else: 0)
    b_resv[src][r] += n
    if wanted: b_want[dst][r] -= n
    b_coming[dst][r] += n
    clear_task(i)
    u_task[i] = T_CARRY
    u_home[i] = jid
    u_target[i] = b_id[src]
    approach_building(i, src)

// Pair p's wants with offers and free carriers, then send what workshops offer and nobody asked for to the nearest
// store with room. Stays dirty only if it stopped at the cap.
def carry_match(p:int):
    var jobs = 0
    for(b_id.length) b:
        if b_owner[b] == p:
            for(num_resources) r:
                while jobs < CARRY_MATCHES and b_want[b][r] > 0:
                    let src = carry_source(p, r, b)
                    if src < 0: break
                    let i = free_carrier(p, src)
                    if i < 0:
                        carry_dirty[p] = 0
                        return
                    start_job(i, src, b, r, min(b_want[b][r], min(offered(src, r), r_carrier_load)), true)
                    jobs++
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] != 0 and bt_store[b_kind[b]] == 0:
            for(num_resources) r:
                while jobs < CARRY_MATCHES and bt_offer[b_kind[b]][r] != 0 and offered(b, r) > 0:
                    let dst = store_near(b, r)
                    if dst < 0: break
                    let i = free_carrier(p, b)
                    if i < 0:
                        carry_dirty[p] = 0
                        return
                    start_job(i, b, dst, r, min(offered(b, r), min(hold_room(dst, r) - b_coming[dst][r], r_carrier_load)), false)
                    jobs++
    carry_dirty[p] = if jobs >= CARRY_MATCHES: 1 else: 0

// The owner's finished store nearest building `from` with room for r beyond what is on its way; -1 if none.
def store_near(fb:int, r:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    let x = b_cx[fb] * TILE + b_sx[fb] * TILE / 2
    let y = b_cy[fb] * TILE + b_sy[fb] * TILE / 2
    for(b_id.length) b:
        if is_store(b, b_owner[fb]) and hold_room(b, r) - b_coming[b][r] > 0:
            let d2 = mid_dist2(b, x, y)
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

def end_job(j:int):
    for([ jb_id, jb_unit, jb_from, jb_to, jb_res, jb_n, jb_phase, jb_want ]) col: col.remove(j)

// Give a job's reservations back (its carrier is gone or has other orders); what it carried stays in its hands.
def cancel_job(j:int, p:int):
    let r = jb_res[j]
    let dst = b_index_of(jb_to[j])
    if dst >= 0:
        b_coming[dst][r] -= jb_n[j]
        if jb_want[j]: b_want[dst][r] += jb_n[j]
    if jb_phase[j] == CARRY_TO_SOURCE:
        let src = b_index_of(jb_from[j])
        if src >= 0: b_resv[src][r] -= jb_n[j]
    end_job(j)
    mark_carry(p)

// p's finished store nearest unit i with room for r; -1 if none.
def store_with_room(i:int, r:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    for(b_id.length) b:
        if is_store(b, u_owner[i]) and hold_room(b, r) > 0:
            let d2 = mid_dist2(b, u_x[i], u_y[i])
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

def carry_done(i:int, j:int):
    end_job(j)
    clear_task(i)
    u_moving[i] = 0
    mark_carry(u_owner[i])

def carry_step(i:int):
    let j = job_index(u_home[i])
    if j < 0:
        clear_task(i)
        return
    let r = jb_res[j]
    let phase = jb_phase[j]
    var to = b_index_of(if phase == CARRY_TO_SOURCE: jb_from[j] else: jb_to[j])
    if to < 0:
        if phase == CARRY_TO_SOURCE:  // the source fell: no goods to fetch
            cancel_job(j, u_owner[i])
            clear_task(i)
            return
        to = store_with_room(i, r)  // the destination fell: take the goods to a store
        if to < 0:
            u_carry[i] = 0  // (nowhere left to put them: lost)
            carry_done(i, j)
            return
        jb_to[j] = b_id[to]
        jb_want[j] = 0
        b_coming[to][r] += jb_n[j]
        approach_building(i, to)
    let x0, y0, x1, y1 = building_rect(to)
    if in_reach(i, x0, y0, x1, y1):
        u_moving[i] = 0
        u_stuck[i] = 0
        if phase == CARRY_TO_SOURCE:
            b_resv[to][r] -= jb_n[j]
            let n = hold_take(to, r, jb_n[j])  // (a cost may have taken reserved goods: less comes out)
            let dst = b_index_of(jb_to[j])
            if dst >= 0 and n < jb_n[j]:
                b_coming[dst][r] -= jb_n[j] - n
                if jb_want[j]: b_want[dst][r] += jb_n[j] - n
            jb_n[j] = n
            if n == 0:
                carry_done(i, j)
                return
            u_carry[i] = n
            u_carry_kind[i] = r + 1
            jb_phase[j] = CARRY_TO_DEST
            u_target[i] = jb_to[j]
            approach_building(i, if dst >= 0: dst else: to)
        else:
            b_coming[to][r] -= jb_n[j]
            u_carry[i] -= hold_put(to, r, u_carry[i])
            if u_carry[i] > 0:  // no room after all: on to a store
                let s = store_with_room(i, r)
                if s >= 0 and s != to:
                    jb_to[j] = b_id[s]
                    jb_want[j] = 0
                    jb_n[j] = u_carry[i]
                    b_coming[s][r] += u_carry[i]
                    approach_building(i, s)
                    return
                u_carry[i] = 0  // (lost)
            u_carry_kind[i] = 0
            carry_done(i, j)
    elif u_moving[i] == 0:
        if u_stuck[i] >= GIVE_UP: u_stuck[i] = 0
        approach_building(i, to)

// One tick: drop jobs whose carrier went, move every carrier, then match what changed.
def carry_tick():
    if not r_stocked: return
    var j = 0
    while j < jb_id.length:
        let i = index_of(jb_unit[j])
        if i < 0 or u_task[i] != T_CARRY or u_home[i] != jb_id[j]: cancel_job(j, if i >= 0: u_owner[i] else: -1)
        else: j++
    for(u_x.length) i:
        if u_task[i] == T_CARRY: carry_step(i)
    for(num_players) p:
        if tick % CARRY_BACKSTOP == 0: carry_dirty[p] = 1
        if carry_dirty[p]: carry_match(p)
