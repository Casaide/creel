// ------------------------------------------------------------------ heroes (heroes.gd)
// One of each hero out at a time. Each casts an aura on its team within aura tiles (not itself):
// attack on its blows and shots, armour off what hits it, the strongest of each stat from every
// hero. A hurt hero heals a hit point every regen ticks; one that falls may be revived at the Town
// Center after revive ticks, for revive_pct of its price.

var hero_fx = []::[Effect]  // per hero type (alongside hero_types): its aura's effects

def hero_slot(k:int) -> int:
    for(hero_types) h, n:
        if h == k: return n
    return -1

// Is unit id `uid` sheltering in one of the player's buildings?
def sheltering(p:int, uid:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p:
            var o = 0
            while o < b_inside[b].length:
                if b_inside[b][o + REC_ID] == uid: return true
                o += REC_SIZE
    return false

// Why the player can't train (or revive) hero type k now: false if it can (Heroes.why_not).
def hero_barred(p:int, k:int) -> bool:
    let n = hero_slot(k)
    if n < 0: return true
    if hero_id[n] != 0: return true
    for(b_id.length) b:
        if b_owner[b] == p and contains(b_queue[b], k): return true
    return hero_fell[n] != 0 and hero_fell[n] - 1 + r_revive - tick > 0

// What training type k costs: a hero that has fallen before costs revive_pct of its price.
def unit_cost(k:int) -> [int]:
    let n = hero_slot(k)
    if n < 0 or hero_fell[n] == 0: return t_cost[k]
    return map(t_cost[k]) v: v * r_revive_pct / 100

def hero_spawned(i:int):
    let n = hero_slot(u_kind[i])
    if n >= 0: hero_id[n] = u_id[i]

// After the fighting: a hero gone from the map and every shelter has fallen; a hurt one heals.
def hero_tick():
    for(hero_types) k, n:
        let uid = hero_id[n]
        if uid != 0:
            let p = t_player[k]
            let i = index_of(uid)
            if i < 0:
                if not sheltering(p, uid):
                    hero_id[n] = 0
                    hero_fell[n] = tick + 1
            elif tick % r_regen == 0 and u_hp[i] < t_hp[k]:
                u_hp[i]++

// Each unit's aura this tick (AURA ints a slot), or empty with no hero on the map.
def auras() -> [int]:
    var out = []::int
    let r2 = r_aura * r_aura
    for(hero_types) k, n:
        let h = if hero_id[n] != 0: index_of(hero_id[n]) else: -1
        if h >= 0:
            if not out.length: out = map(u_x.length * AURA): 0
            let team = teams[t_player[k]]
            let hx = u_x[h]
            let hy = u_y[h]
            for(u_x.length) j:
                if j != h and u_owner[j] != gaia and teams[u_owner[j]] == team and dist2(hx, hy, u_x[j], u_y[j]) <= r2:
                    for(hero_fx[n]) e:
                        if reaches(e, t_tags[u_kind[j]]):
                            let stat = if e.kind == 0: 0 elif e.stat == 0: 1 else: 2
                            let at = j * AURA + stat
                            out[at] = max(out[at], e.value)
    return out
