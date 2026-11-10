// ------------------------------------------------------------------ map bridges (bridges.gd)
// Timber decks over a river, placed by the map, owned by nobody. A standing bridge lays a deck
// ground units walk; anyone breaks one by attacking it (the deck falls, the crossing is gone);
// any player's workers rebuild it, the first to start paying. Ids from the shared id counter.

def bridge_index(id:int) -> int:
    for(br_id) v, k:
        if v == id: return k
    return -1

def bridge_target(id:int) -> bool:
    let k = bridge_index(id)
    return k >= 0 and br_up[k] == 1

def set_deck(cells:[int], on:bool):
    for(cells) c:
        deck[c] = if on: 1 else: 0
        refresh(c)

def bridge_damage(atk:[int], min_damage:int) -> int:
    var d = 0
    for(atk) a, c:
        if a > 0 and c < 3: d += max(0, a - br_arm[c])  // (melee, pierce, building)
    return max(min_damage, d)

def bridge_hurt(k:int, d:int):
    if br_up[k] == 0: return
    br_hp[k] -= d
    if br_hp[k] > 0: return
    br_hp[k] = 0
    br_up[k] = 0
    br_work[k] = 0
    br_payer[k] = -1
    set_deck(br_cells[k], false)
    if events_on: events.push(Event { EV_DIE, br_id[k], 1, 0, br_x0[k] + (br_x1[k] - br_x0[k]) / 2, br_y0[k] + (br_y1[k] - br_y0[k]) / 2 })

def bridge_approach(i:int, k:int):
    order_reach(i, br_x0[k], br_y0[k], br_x1[k], br_y1[k], building_field(br_id[k], true, lane(i)))

// HELP_BUILD on a bridge: the first rebuilder pays, then the workers go and work on it. False if
// `target` isn't a bridge.
def bridge_help(p:int, target:int, workers:[int]) -> bool:
    let k = bridge_index(target)
    if k < 0: return false
    if br_up[k] == 1: return true
    if br_payer[k] < 0:
        if not can_afford(p, br_cost): return true
        pay(p, br_cost)
        br_payer[k] = p
    for(workers) i:
        u_task[i] = BUILD
        u_target[i] = br_id[k]
        u_home[i] = -1
        u_work[i] = 0
        bridge_approach(i, k)
    return true

// A worker at its job on bridge k; false when the job is over.
def bridge_work(i:int, k:int, reached:bool) -> bool:
    if br_up[k] == 1 or br_payer[k] < 0: return false
    if not reached:
        if u_moving[i] == 0:
            if u_stuck[i] >= STUCK_LIMIT: return false
            bridge_approach(i, k)
        return true
    u_moving[i] = 0
    u_stuck[i] = 0
    br_work[k] = min(br_ticks, br_work[k] + 1)
    br_hp[k] = max(1, br_full_hp * br_work[k] / br_ticks)
    if br_work[k] >= br_ticks:
        br_up[k] = 1
        br_hp[k] = br_full_hp
        br_payer[k] = -1
        set_deck(br_cells[k], true)
        return false
    return true

def bridge_gap(i:int, k:int) -> int:
    let dx = max(max(br_x0[k] - u_x[i], 0), u_x[i] - br_x1[k])
    let dy = max(max(br_y0[k] - u_y[i], 0), u_y[i] - br_y1[k])
    return isqrt(dx * dx + dy * dy) - u_radius[i]
