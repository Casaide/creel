// ------------------------------------------------------------------ carriers and the request queue (Casaide/creel#49)
// In a stocked economy (#48) goods move by hand. A building asks for goods (want: b_want), a carrier takes them from
// the nearest store holding them and walks them over. A job reserves the goods at its source (b_resv) and takes the
// want off its destination, so two carriers never chase one log. Matching runs on changes only: a player is looked at
// again when a want, a store's goods or a carrier changes (carry_dirty), at most CARRY_MATCHES jobs a tick, buildings
// and carriers in id order. A job whose carrier is gone or took other orders gives its reservations back.

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

// Where building `to` gets r from: p's nearest workshop that offers it, else p's nearest store that does; never `to`
// itself; -1 if none. (Goods go straight from who makes them to who wants them, and the stores keep the rest: else a
// workshop nobody takes from stands full while the store runs dry, #98.)
def carry_source(p:int, r:int, to:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    var best_store = true
    let x = b_cx[to] * TILE + b_sx[to] * TILE / 2
    let y = b_cy[to] * TILE + b_sy[to] * TILE / 2
    for(b_id.length) b:
        if b != to and gives(b, p, r) and offered(b, r) > 0:
            let d2 = mid_dist2(b, x, y)
            let store = bt_store[b_kind[b]] != 0
            if (best_store and not store) or (store == best_store and d2 < best_d2):
                best_d2 = d2
                best = b
                best_store = store
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
    carry_approach(i, src)

// Is workshop b's out slot for r too full for another round of its recipe? Goods already reserved are as good as
// gone. (A gatherer's hut has no recipe: it is never held up this way, its goods wait their turn.)
def out_full(b:int, r:int) -> bool: return bt_out[b_kind[b]][r] > 0 and hold_room(b, r) + b_resv[b][r] < bt_out[b_kind[b]][r]

// p's building nearest `from` that wants r, never `from` itself; -1 if none.
def wanting(p:int, r:int, fb:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    let x = b_cx[fb] * TILE + b_sx[fb] * TILE / 2
    let y = b_cy[fb] * TILE + b_sy[fb] * TILE / 2
    for(b_id.length) b:
        if b != fb and b_owner[b] == p and b_want[b][r] > 0 and not levelling(b):
            let d2 = mid_dist2(b, x, y)
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

// Pair p's wants with offers and free carriers, then send what workshops offer and nobody asked for to the nearest
// store with room. A workshop standing idle with its out slot full goes first, ahead of every want (its goods to whoever
// wants them, else to a store): else a town busy building leaves its bakery full and its people hungry (#102). Stays
// dirty only if it stopped at the cap.
def carry_match(p:int):
    var jobs = 0
    let nb = b_id.length
    for(nb) k:  // (from a building that turns with the clock, as below)
        let b = (tick + k) % nb
        if b_owner[b] == p and b_done[b] != 0 and bt_store[b_kind[b]] == 0:
            for(num_resources) r:
                while jobs < CARRY_MATCHES and bt_offer[b_kind[b]][r] != 0 and offered(b, r) > 0 and out_full(b, r):
                    var dst = wanting(p, r, b)
                    let wanted = dst >= 0
                    if not wanted: dst = store_near(b, r)
                    if dst < 0: break
                    let i = free_carrier(p, b)
                    if i < 0:
                        carry_dirty[p] = 0
                        return
                    let room = if wanted: b_want[dst][r] else: hold_room(dst, r) - b_coming[dst][r]
                    start_job(i, b, dst, r, min(offered(b, r), min(room, r_carrier_load)), wanted)
                    jobs++
    for(b_id.length) b:
        if b_owner[b] == p and not levelling(b):  // (a site being levelled asks nothing yet, #138)
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
    let n = b_id.length
    for(n) k:  // (from a building that turns with the clock: each workshop's goods get their turn, not the first few's, #98)
        let b = (tick + k) % n
        if b_owner[b] == p and b_done[b] != 0 and bt_store[b_kind[b]] == 0:
            for(num_resources) r:
                // (not a good it's still asking for: it would be sent away as it comes, #144)
                while jobs < CARRY_MATCHES and bt_offer[b_kind[b]][r] != 0 and offered(b, r) > 0 and b_want[b][r] == 0 and b_coming[b][r] == 0:
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

// Unit i, in reach of a building: whether it's still in its visit (another tick of r_inside_ticks, with r_door_step
// stepping in before and out after); false once it's out.
def still_inside(i:int) -> bool:
    if u_work[i] >= r_inside_ticks + 2 * r_door_step:
        u_work[i] = 0
        return false
    u_work[i]++
    return true

// The building unit i is visiting (going in, inside or coming out: u_work counts the visit), or -1.
def visiting(i:int) -> int:
    if r_inside_ticks <= 0 or u_work[i] <= 0: return -1
    if u_task[i] == T_CARRY:
        let j = job_index(u_home[i])
        if j < 0: return -1
        return b_index_of(if jb_phase[j] == CARRY_TO_SOURCE: jb_from[j] else: jb_to[j])
    if u_task[i] == T_RETURN: return b_index_of(u_target[i])
    return -1

// For the view (rules economy "door_step"): how far unit i is through the door of the building it visits, in 1/1000
// (0 when it isn't stepping: outside, or out of sight inside), that building, and whether it's going in.
def door_step_of(i:int) -> int, int, bool:
    if r_door_step <= 0: return 0, -1, false
    let b = visiting(i)
    if b < 0 or not by_door(b): return 0, -1, false
    let w = u_work[i]
    if w <= r_door_step: return w * 1000 / r_door_step, b, true
    if w > r_inside_ticks + r_door_step: return (r_inside_ticks + 2 * r_door_step + 1 - w) * 1000 / r_door_step, b, false
    return 0, -1, false

// Whether unit i is out of sight in a building now: inside, not stepping through its door.
def hidden_inside(i:int, hc:int) -> bool:
    if not is_inside(i, hc): return false
    let ds = door_step_of(i)
    return ds == 0

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
            if events_on: events.push(Event { EV_LOST, u_id[i], 0, r, u_x[i], u_y[i], u_carry[i] })
            u_carry[i] = 0  // (nowhere left to put them: lost)
            carry_done(i, j)
            return
        jb_to[j] = b_id[to]
        jb_want[j] = 0
        b_coming[to][r] += jb_n[j]
        carry_approach(i, to)
    let x0, y0, x1, y1 = carry_rect(to)
    if u_work[i] > 0 or in_reach(i, x0, y0, x1, y1):  // (once inside, it stays till it comes out)
        u_moving[i] = 0
        u_stuck[i] = 0
        if r_inside_ticks > 0 and b_done[to] != 0 and still_inside(i): return  // (at a site, the goods are put down outside)
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
            ev_goods(EV_PICK, u_id[i], to, r, n)
            jb_phase[j] = CARRY_TO_DEST
            u_target[i] = jb_to[j]
            carry_approach(i, if dst >= 0: dst else: to)
        else:
            b_coming[to][r] -= jb_n[j]
            let put = hold_put(to, r, u_carry[i])
            if put > 0: ev_goods(EV_DROP, u_id[i], to, r, put)
            u_carry[i] -= put
            if u_carry[i] > 0:  // no room after all: on to a store
                let s = store_with_room(i, r)
                if s >= 0 and s != to:
                    jb_to[j] = b_id[s]
                    jb_want[j] = 0
                    jb_n[j] = u_carry[i]
                    b_coming[s][r] += u_carry[i]
                    carry_approach(i, s)
                    return
                u_carry[i] = 0  // (lost)
            u_carry_kind[i] = 0
            carry_done(i, j)
    elif u_moving[i] == 0:
        if u_stuck[i] >= GIVE_UP: u_stuck[i] = 0
        carry_approach(i, to)

// ---- standing aside (rules economy "idle_aside", #164)

// The door tiles units go in by, or bring a site's goods to (carry_door).
def door_cells() -> [int]: return map(filter(b_id.length) b: carry_door(b)) b: door_cell(b)

// Is anyone standing (not walking) within half a tile of (x, y), unit i left out?
def anyone_standing(i:int, x:int, y:int) -> bool:
    for(u_x.length) j:
        if j != i and u_moving[j] == 0 and abs(u_x[j] - x) < TILE / 2 and abs(u_y[j] - y) < TILE / 2: return true
    return false

// Is idle unit i standing in the body of an idle one before it by id (a heap of them)?
def in_a_heap(i:int) -> bool:
    for(u_x.length) j:
        if j != i and u_id[j] < u_id[i] and u_moving[j] == 0 and t_carrier[u_kind[j]] != 0 and u_task[j] == T_NONE:
            let rr = (u_radius[i] + u_radius[j]) * 4 / 5
            if dist2(u_x[i], u_y[i], u_x[j], u_y[j]) < rr * rr: return true
    return false

// A road tile to stand on beside c for unit i (as the genre's idle ones wait on the road, not on ground a building may go
// up on): walkable, no building but the road on it, no door, nobody standing there; -1 if none.
def aside_cell(i:int, c:int, doors:[int]) -> int:
    let ln = lane(i)
    for(9) k:
        let x = c % W + k % 3 - 1
        let y = c / W + k / 3 - 1
        if k != 4 and cell_walkable(x, y, ln):
            let n = y * W + x
            let ob = if occupied[n] != 0: b_index_of(occupied[n]) else: -1
            if (ob < 0 or bt_road[b_kind[ob]] >= 0) and not contains(doors, n):
                let cx, cy = centre(n)
                if road.length and road[n] > 0 and not anyone_standing(i, cx, cy): return n
    return -1

// Each idle carrier looks once a second, in a tick of its own: standing in a doorway, or in the body of an idle one before it,
// it walks to a free road tile beside it. So idle ones never block a door or stand in a heap.
def stand_aside_tick():
    var doors = []::int
    var doors_found = false
    for(u_x.length) i:
        if (tick + u_id[i]) % 20 == 0 and t_carrier[u_kind[i]] != 0 and u_task[i] == T_NONE and u_moving[i] == 0 and not u_orders[i].length:
            if not doors_found:
                doors = door_cells()
                doors_found = true
            let c = cell_of(u_x[i], u_y[i])
            if contains(doors, c) or in_a_heap(i):
                let to = aside_cell(i, c, doors)
                if to >= 0:
                    let x, y = centre(to)
                    order_move(i, x, y, SLOT_ARRIVE, 0, -1, -1, 0, true)

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
    if r_idle_aside != 0: stand_aside_tick()
    for(num_players) p:
        if tick % CARRY_BACKSTOP == 0: carry_dirty[p] = 1
        if carry_dirty[p]: carry_match(p)
