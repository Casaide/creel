// ------------------------------------------------------------------ healers (heal.gd)
// Each healer heals the most wounded unit of its own team (not itself, not animals, not machines)
// within heal_sight, walking up to heal_range (edge to edge) when idle or on an attack-move:
// heal_amount x its heal stat (more with research) every heal_reload ticks. Heals land together.

var r_heal_amount = 0
var r_heal_reload = 0
var r_heal_range = 0
var r_heal_sight = 0
var heal_not = []::int  // classes nobody heals (machines)
var h_heals = []::int
var h_tending = []::int

def no_heal(k:int) -> bool:
    for(heal_not) c:
        if c >= 0 and contains(t_tags[k], c): return true
    return false

// Can healer i heal unit j: someone else on its team, not a machine, and hurt?
def wounded(i:int, j:int) -> bool:
    return j != i and t_animal[u_kind[j]] == 0 and not no_heal(u_kind[j]) and u_owner[j] != gaia and not is_enemy(u_owner[i], u_owner[j]) and u_hp[j] < t_hp[u_kind[j]]

// The most wounded friend within `sight`: the most hit points missing less what the healers on it
// will give, then the nearest, then the lowest id.
def most_wounded(i:int, sight:int) -> int:
    var best = -1
    var best_need = 0
    var best_d = 0
    let r = sight / TILE + 1
    let cx = u_x[i] / TILE
    let cy = u_y[i] / TILE
    var yy = max(cy - r, 0)
    while yy < min(cy + r + 1, H):
        var xx = max(cx - r, 0)
        while xx < min(cx + r + 1, W):
            let cell = yy * W + xx
            var k = sp_start[cell]
            while k < sp_end[cell]:
                let j = sp_items[k]
                k++
                if wounded(i, j):
                    let d = dist2(u_x[i], u_y[i], u_x[j], u_y[j])
                    if d <= sight * sight:
                        let need = t_hp[u_kind[j]] - u_hp[j] - h_tending[j] * r_heal_amount
                        if best < 0 or need > best_need or (need == best_need and (d < best_d or (d == best_d and u_id[j] < u_id[best]))):
                            best = j
                            best_need = need
                            best_d = d
            xx++
        yy++
    return best

def heal_done(i:int):
    u_patient[i] = 0
    if u_stance[i] == AUTO:
        u_stance[i] = NONE
        u_moving[i] = 0
    elif u_stance[i] == ATTACK_MOVE:
        resume_attack_move(i)

def heal_tick():
    let n = u_x.length
    while h_heals.length < n:
        h_heals.push(0)
        h_tending.push(0)
    var any_healer = false
    for(n) i:
        h_heals[i] = 0
        h_tending[i] = 0
    for(n) i:
        if u_patient[i] != 0:
            let j = index_of(u_patient[i])
            if j >= 0: h_tending[j]++
        any_healer = any_healer or t_healer[u_kind[i]] != 0
    if not any_healer: return
    for(n) i:
        let k = u_kind[i]
        if t_healer[k]:
            var j = if u_patient[i] != 0: index_of(u_patient[i]) else: -1
            if u_patient[i] != 0 and (j < 0 or not wounded(i, j)):
                if j >= 0: h_tending[j]--
                heal_done(i)
                j = -1
            let free = u_moving[i] == 0 or u_stance[i] == AUTO or u_stance[i] == ATTACK_MOVE
            if j < 0 and (tick + u_id[i]) % r_acquire_every == 0 and u_task[i] == T_NONE and free:
                let reach = r_heal_range + u_radius[i] + TILE / 2
                j = most_wounded(i, if u_posture[i] == STAND: reach else: r_heal_sight)
                if j >= 0:
                    u_patient[i] = u_id[j]
                    h_tending[j]++
            if j >= 0:
                let g = isqrt(dist2(u_x[i], u_y[i], u_x[j], u_y[j])) - u_radius[i] - u_radius[j]
                if g <= r_heal_range:
                    if u_stance[i] == AUTO or u_stance[i] == ATTACK_MOVE: u_moving[i] = 0
                    if u_stance[i] == AUTO: u_stance[i] = NONE
                    if u_moving[i] != 0:
                        u_cooldown[i] = max(u_cooldown[i], r_heal_reload)
                    elif u_cooldown[i] == 0:
                        u_cooldown[i] = r_heal_reload
                        h_heals[j] += r_heal_amount * t_heal[k] * (100 + t_heal_pct[k]) / 100
                        if events_on: events.push(Event { EV_HEAL, u_id[i], u_id[j], 0, u_x[j], u_y[j] })
                elif u_posture[i] == STAND or g > r_heal_sight + 2 * TILE:
                    h_tending[j]--
                    heal_done(i)
                elif free:
                    u_cooldown[i] = max(u_cooldown[i], r_heal_reload)
                    if u_moving[i] == 0 or (tick + u_id[i]) % REPLAN_EVERY == 0:
                        if clear_line(u_x[i], u_y[i], u_x[j], u_y[j], lane(i)):
                            order_direct(i, u_x[j], u_y[j])
                        else:
                            order_move(i, u_x[j], u_y[j], 0, 0, -1, -1, 0)
                        if u_stance[i] != ATTACK_MOVE: u_stance[i] = AUTO
    for(n) j:
        if h_heals[j] > 0: u_hp[j] = min(u_hp[j] + h_heals[j], t_hp[u_kind[j]])
