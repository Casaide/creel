// ------------------------------------------------------------------ race abilities (abilities.gd, ability_ai.gd)
// One signature ability per race, a kind from a small vocabulary with its numbers in data. The
// ABILITY command: the first of the units (in id order) that has it, is ready and is in range of
// the spot uses it there. web: a slowing patch at the spot that wears off. Slowing: a unit in an
// enemy web, or hit by a sticky shot (slow_on_hit ticks, at SLOW_PCT), moves slower.

let SLOW_PCT = 60
let WEB = 6  // webs, flat: owner, x, y, radius, ends (tick), slow_pct
let AB_WEB = 1

var ab_kind = []::int  // per player: 0 none, AB_WEB
var ab_range = []::int
var ab_radius = []::int
var ab_lasts = []::int
var ab_slow = []::int
var ab_cooldown = []::int
var t_ability = []::int  // per unit type: may use its race's ability
var webs = []::int
var ready_ids = []::int  // ability cooldowns: unit id -> the tick it may act again (ids ascending)
var ready_at = []::int
var slowed_ids = []::int  // sticky hits: unit id -> the tick it wears off
var slowed_until = []::int

def ids_get(ids:[int], vals:[int], id:int, fallback:int) -> int:
    let found, at = binary_search(ids, id)
    return if found: vals[at] else: fallback

def ids_set(ids:[int], vals:[int], id:int, v:int):
    let found, at = binary_search(ids, id)
    if found: vals[at] = v
    else:
        ids.insert(at, id)
        vals.insert(at, v)

def ability_wait(i:int) -> int: return max(0, ids_get(ready_ids, ready_at, u_id[i], 0) - tick)

def cmd_ability(p:int, ids0:[int], x:int, y:int):
    if ab_kind[p] == 0: return
    let ids = copy(ids0)
    sort_ints(ids)
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and t_ability[u_kind[i]] and ability_wait(i) == 0:
            let dx = x - u_x[i]
            let dy = y - u_y[i]
            if dx * dx + dy * dy <= ab_range[p] * ab_range[p]:
                if ab_kind[p] == AB_WEB:
                    for([ p, x, y, ab_radius[p], tick + ab_lasts[p], ab_slow[p] ]) v: webs.push(v)
                ids_set(ready_ids, ready_at, uid, tick + ab_cooldown[p])
                return

def abilities_tick():
    let kept = []::int
    var n = 0
    while n < webs.length:
        if webs[n + 4] > tick:
            for(WEB) f: kept.push(webs[n + f])
        n += WEB
    webs = kept
    slow_ids = []::int
    slow_pcts = []::int
    if kept.length:
        for(u_x.length) i:
            var m = 0
            while m < kept.length:
                if is_foe(kept[m], u_owner[i]):
                    let dx = u_x[i] - kept[m + 1]
                    let dy = u_y[i] - kept[m + 2]
                    let r = kept[m + 3] + u_radius[i]
                    if dx * dx + dy * dy <= r * r:
                        ids_set(slow_ids, slow_pcts, u_id[i], min(ids_get(slow_ids, slow_pcts, u_id[i], 100), kept[m + 5]))
                m += WEB
    var k = 0
    while k < slowed_ids.length:
        if slowed_until[k] <= tick:
            slowed_ids.remove(k)
            slowed_until.remove(k)
        else:
            ids_set(slow_ids, slow_pcts, slowed_ids[k], min(ids_get(slow_ids, slow_pcts, slowed_ids[k], 100), SLOW_PCT))
            k++
    if tick % 200 == 0:  // forget the cooldowns of the dead now and then
        var q = 0
        while q < ready_ids.length:
            if index_of(ready_ids[q]) < 0 or ready_at[q] <= tick:
                ready_ids.remove(q)
                ready_at.remove(q)
            else: q++

// A sticky hit: unit j slowed for `ticks` from now (the longer of two).
def stick(j:int, ticks:int):
    let uid = u_id[j]
    ids_set(slowed_ids, slowed_until, uid, max(ids_get(slowed_ids, slowed_until, uid, 0), tick + ticks))

def abilities_hash(h0:int) -> int:
    var h = h0
    for(webs) v: h = mix(h, v)
    for(ready_ids) id, k: h = mix(mix(h, id), ready_at[k])
    for(slowed_ids) id, k: h = mix(mix(h, id), slowed_until[k])
    return h

// The bot's web (AbilityAi): on the enemy soldier nearest one of our ready users, within its range,
// that we can see; melee foes first.
def ability_think(p:int, army:[int]):
    if ab_kind[p] != AB_WEB: return
    let reach = ab_range[p]
    var best = -1
    var best_score = 1 << 62
    var by = -1
    for(army) i:
        if t_ability[u_kind[i]] and ability_wait(i) == 0:
            for(u_x.length) j:
                let kj = u_kind[j]
                if is_foe(p, u_owner[j]) and not t_worker[kj] and t_animal[kj] == 0 and fog_visible(p, u_x[j], u_y[j]):
                    let d = dist2(u_x[i], u_y[i], u_x[j], u_y[j])
                    if d <= reach * reach:
                        let score = d + (if t_ranged[kj]: reach * reach else: 0)
                        if score < best_score:
                            best_score = score
                            best = j
                            by = i
    if best >= 0: issue_cmd(p, CMD_ABILITY, [ u_id[by] ], u_x[best], u_y[best], 0, 0)
