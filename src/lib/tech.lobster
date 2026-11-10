// ------------------------------------------------------------------ ages and research (tech.gd, World.set_type, Combat.type_vectors)
// A building does one thing at a time from its queue: units (>= 0), the age-up (AGE_UP_ENTRY) or
// research r (RESEARCH_ENTRY - r), each paid when queued. When one finishes, retype brings the
// player's unit types up to date (the line's step for the age, then every effect of its race and
// research, in order) and refresh its buildings' numbers and gathering speed. Effects are data
// (export.gd _effect): kind, stat, value, tag, and tags, not tags, buildings.
// Left out: cancelling (no CANCEL in the scenarios), heroes' revive price, garrisons.

let AGE_UP_ENTRY = -2
let RESEARCH_ENTRY = -3

class Effect:
    kind:int  // 0 eval add (attack hp range speed), 1 armour add, 2 bonus add, 3 extra add (UNIT_EXTRA),
    // 4 unit pct (UNIT_PCT), 5 building add (BUILDING_ADD), 6 building pct (BUILDING_PCT),
    // 7 gather pct, 8 becomes (stat: from, value: to), 9 start (applied at setup)
    stat:int
    value:int
    tag:int  // class index, -1 all, -2 none
    ands:[int]
    nots:[int]
    blds:[int]  // building types, [-1]: all

class LineStep:
    age:int
    up:int  // its line upgrade, a research index, or -1
    speed:int
    hp:int
    pop:int
    train_time:int
    cost:[int]
    damage:int  // the attack's class
    attack:int
    bonus:[int]
    armour:[int]
    tags:[int]  // class indexes, in the eval's order
    range:int
    reload:int
    min_range:int
    splash:int
    pass_len:int
    buildings_only:int
    unpack:int
    pack:int
    blast:int
    blast_line:int
    mounts:[Mount]  // guns that turn on their own (a part's stats.mounts)
    air:int         // an aircraft: only what can hit air can touch it
    hits_air:int    // its weapon: 1 it can hit air, -1 it can't, 0 by its kind (ranged and not an engine)
    heal:int
    sight:int

class Research:
    id:string
    building:int
    ticks:int
    age:int
    after:int
    line_age:int
    cost:[int]
    open:[int]      // per player: open to its race (not another's own, not lacked)
    line_has:[int]  // per player: a line upgrade with new kit that age
    before:[int]    // per player: the line upgrade that must come first, or -1
    effects:[Effect]

class Age:
    age:int
    building:int
    ticks:int
    cost:[int]
    needs:[[int]]  // per player

var ages_list = []::Age
var research = []::Research
var race_fx = []::[Effect]  // per player
var researched = []::[int]  // per player, per research
var lines = []::[LineStep]  // per unit type

var r_melee_reach = 0
var r_melee_reload = 0
var r_ranged_reload = 0
var r_shot_speed = 0
var shot_speeds = []::int  // per class: a weapon tag's own shot speed, or 0
var base_gather_ticks = []::int
var bt_hp_base = []::int
var bt_food_base = []::int
var bt_arm = []::[int]
var bm_arm = []::[[int]]  // [player][type]: armour with research
var bm_research_time = []::[int]
var bm_age_time = []::[int]
var bm_research_cost = []::[int]
var bm_range = []::[int]
var bm_cost_pct = []::[int]
var bm_trade_fee = []::[int]  // [player][type]: points off the market's fee
var class_machine = -2        // the classes rules' combat band_machine and band_mounted name (formation bands), or -2
var class_mounted = -2
// Unit types' research and bonuses (Tech.retype).
var t_heal_pct = []::int
var t_kill_gold = []::int
var t_slow_on_hit = []::int
var t_min_range = []::int
var t_splash = []::int
var t_pass_len = []::int
var t_buildings_only = []::int
var t_unpack = []::int
var t_pack = []::int
var t_blast = []::int
var t_blast_line = []::int
var t_eval_sight = []::int
var t_sight_add = []::int
var t_machine = []::int
var t_mounted = []::int

def effects_of(p:int) -> [Effect]:
    let out = copy(race_fx[p])
    for(research) r, k:
        if researched[p][k] == 1:
            for(r.effects) fx: out.push(fx)
    return out

// Does a unit effect reach a type with these tags (Identity.reaches)?
def reaches(fx:Effect, tags:[int]) -> bool:
    if fx.tag == -2 or not (fx.tag == -1 or contains(tags, fx.tag)): return false
    for(fx.ands) t:
        if not contains(tags, t): return false
    for(fx.nots) t:
        if t >= 0 and contains(tags, t): return false
    return true

def covers(fx:Effect, k:int) -> bool:
    return contains(fx.blds, -1) or contains(fx.blds, k)

// A unit type's numbers from a line step's eval with the effects applied (World.set_type,
// Combat.type_vectors, Tech.retype). Its units keep their share of health and take its speed.
// A shot.s pace, milli-tiles a tick: the fastest of these tags (a shell in a bolt thrower line flies as a shell, in
// whatever order its tags come), else the rule.s.
def shot_speed_of(tags:[int]) -> int:
    var best = 0
    for(tags) c: best = max(best, shot_speeds[c])
    return if best > 0: best else: r_shot_speed

def set_type_from(k:int, l:LineStep, fxs:[Effect]):
    let C = num_classes
    var attack = l.attack
    var hp = l.hp
    var range = l.range
    var speed = l.speed
    let bonus = copy(l.bonus)
    let armour = copy(l.armour)
    let add = map(7): 0  // UNIT_EXTRA: sight carry kill_gold wade reach slow_on_hit form_gap
    let pct = map(7): 0  // UNIT_PCT: speed reload cost train_time build_speed carry heal
    for(fxs) fx:
        if fx.kind <= 4 and reaches(fx, l.tags):
            switch fx.kind:
                case 0:
                    if fx.stat == 0: attack += fx.value
                    elif fx.stat == 1: hp += fx.value
                    elif fx.stat == 2: range += fx.value
                    else: speed += fx.value
                case 1: armour[fx.stat] += fx.value
                case 2: bonus[fx.stat] += fx.value
                case 3: add[fx.stat] += fx.value
                default: pct[fx.stat] += fx.value
    let old_hp = t_hp[k]
    t_speed[k] = speed * 5
    t_hp[k] = hp
    t_pop[k] = l.pop
    t_train_ticks[k] = l.train_time * 20
    t_cost[k] = copy(l.cost)
    // Combat.type_vectors
    let atk = map(C): 0
    atk[l.damage] = attack
    for(C) c: atk[c] += bonus[c]
    t_atk[k] = atk
    t_counters[k] = filter(map(C) c: c) c: c >= 3 and bonus[c] > 0
    t_arm[k] = armour
    let cls = map(C): 0
    cls[0] = 1
    cls[1] = 1
    for(l.tags) c: cls[c] = 1
    t_cls[k] = cls
    let ranged = range > 1
    t_ranged[k] = if ranged: 1 else: 0
    t_reach[k] = if ranged: range * TILE else: r_melee_reach
    t_reload[k] = if ranged: r_ranged_reload else: r_melee_reload
    t_shot_speed[k] = shot_speed_of(l.tags)
    t_machine[k] = if contains(l.tags, class_machine): 1 else: 0
    t_mounted[k] = if contains(l.tags, class_mounted): 1 else: 0
    if l.reload > 0: t_reload[k] = l.reload
    t_min_range[k] = l.min_range * TILE
    t_splash[k] = l.splash
    t_pass_len[k] = l.pass_len
    t_buildings_only[k] = l.buildings_only
    t_unpack[k] = l.unpack
    t_pack[k] = l.pack
    t_blast[k] = l.blast
    t_blast_line[k] = l.blast_line
    t_air[k] = l.air
    t_hits_air[k] = if not ranged or l.hits_air < 0: 0 elif l.hits_air > 0: 1 elif t_machine[k] != 0 or t_min_range[k] > 0: 0 else: 1
    t_mounts[k] = l.mounts
    for(l.mounts) m:
        if m.attack >= 0:
            m.atk = map(C): 0
            m.atk[m.damage] = m.attack
            for(C) c: m.atk[c] += bonus[c]
        if m.range > t_reach[k]: t_reach[k] = m.range  // (it comes as close as its longest gun needs)
    t_eval_sight[k] = l.sight
    t_tags[k] = l.tags
    t_damage[k] = l.damage
    t_heal[k] = l.heal
    t_eval_attack[k] = attack  // (the bots' counter-pick reads the eval with research in it)
    t_bonus[k] = bonus
    // Tech.retype's percents and extras
    t_speed[k] = max(1, t_speed[k] * (100 + pct[0]) / 100)
    t_reload[k] = max(1, t_reload[k] * (100 + pct[1]) / 100)
    t_train_ticks[k] = max(1, t_train_ticks[k] * (100 + pct[3]) / 100)
    for(t_cost[k]) v, r: t_cost[k][r] = v * (100 + pct[2]) / 100
    t_build_pct[k] = pct[4]
    t_sight_add[k] = add[0]
    t_carry_add[k] = add[1] + r_carry * pct[5] / 100
    t_heal_pct[k] = pct[6]
    t_kill_gold[k] = add[2]
    t_wade[k] = add[3]
    t_slow_on_hit[k] = add[5]
    t_gap[k] = add[6]
    if not ranged: t_reach[k] += add[4]
    t_sight[k] = t_eval_sight[k] + t_sight_add[k]
    t_role[k] = if t_healer[k] or t_harmless[k] or t_machine[k]: 2 elif t_mounted[k]: 3 elif ranged: 1 else: 0
    for(u_x.length) i:
        if u_kind[i] == k:
            u_hp[i] = max(1, u_hp[i] * t_hp[k] / max(1, old_hp))
            u_speed[i] = t_speed[k]

def upgraded_line(p:int, l:LineStep) -> bool:
    return l.up >= 0 and researched[p][l.up] == 1

// Bring every one of a player's unit types up to date (Tech.retype).
def retype(p:int):
    let fxs = effects_of(p)
    for(lines) line, k:
        if t_player[k] == p:
            var step = line[0]
            for(line) l:
                if l.age <= ages[p] and (l.age == line[0].age or t_worker[k] or t_hero[k] or upgraded_line(p, l)): step = l
            set_type_from(k, step, fxs)

// A player's gathering speed and its buildings' numbers (Tech.refresh).
def tech_refresh(p:int):
    let fxs = effects_of(p)
    for(num_resources) r:
        var pct = 0
        for(fxs) fx:
            if fx.kind == 7 and fx.stat == r: pct += fx.value
        gather_ticks[p][r] = max(1, base_gather_ticks[r] * (100 - pct) / 100)
    let old_hp = copy(bm_hp[p])
    for(bt_size.length) k:
        let add = map(6): 0  // BUILDING_ADD: sight armour.melee armour.pierce trade_fee range pop
        let pct = map(6): 0  // BUILDING_PCT: hp food research_time cost research_cost age_time
        for(fxs) fx:
            if fx.kind == 5 and covers(fx, k): add[fx.stat] += fx.value
            if fx.kind == 6 and covers(fx, k): pct[fx.stat] += fx.value
        bm_hp[p][k] = max(1, bt_hp_base[k] * (100 + pct[0]) / 100)
        let arm = copy(bt_arm[k])
        arm[0] += add[1]
        arm[1] += add[2]
        bm_arm[p][k] = arm
        bm_sight[p][k] = add[0]
        bm_range[p][k] = add[4]
        bm_trade_fee[p][k] = add[3]
        bm_pop[p][k] = add[5]
        bm_food[p][k] = bt_food_base[k] * (100 + pct[1]) / 100
        bm_research_time[p][k] = pct[2]
        bm_cost_pct[p][k] = pct[3]
        bm_research_cost[p][k] = pct[4]
        bm_age_time[p][k] = pct[5]
        bm_cost[p][k] = if pct[3] == 0: copy(bt_cost[k]) else: map(bt_cost[k]) v: v * (100 + pct[3]) / 100
    for(b_id.length) b:
        if b_owner[b] == p and old_hp[b_kind[b]] != bm_hp[p][b_kind[b]]:
            b_hp[b] = max(1, b_hp[b] * bm_hp[p][b_kind[b]] / old_hp[b_kind[b]])
    for(fxs) fx:  // tower upgrades: buildings of the first type become the second where they stand
        if fx.kind == 8:
            for(b_id.length) b:
                if b_owner[b] == p and b_kind[b] == fx.stat:
                    let to = upgraded_type(p, b_kind[b])
                    b_hp[b] = max(1, b_hp[b] * bm_hp[p][to] / bm_hp[p][b_kind[b]])
                    b_progress[b] = b_progress[b] * bt_build_ticks[to] / max(1, bt_build_ticks[b_kind[b]])
                    b_kind[b] = to

// The building type a player gets ordering type k: k, or what its research turned it into.
def upgraded_type(p:int, k:int) -> int:
    for(effects_of(p)) fx:
        if fx.kind == 8 and fx.stat == k: return upgraded_type(p, fx.value)
    return k

// ---- queues

def tech_of(e:int) -> int:
    if e >= 0: return -1
    return if e == AGE_UP_ENTRY: AGE_UP_ENTRY else: RESEARCH_ENTRY - e

def entry_of(t:int) -> int: return if t == AGE_UP_ENTRY: AGE_UP_ENTRY else: RESEARCH_ENTRY - t

def head_tech(b:int) -> int:
    let q = b_queue[b]
    return if not q.length: -1 else: tech_of(q[0])

def next_age(p:int) -> int:  // index into ages_list, or -1 at the last age
    for(ages_list) a, k:
        if a.age == ages[p] + 1: return k
    return -1

def tech_queued(p:int, t:int) -> bool:
    let e = entry_of(t)
    for(b_id.length) b:
        if b_owner[b] == p and contains(b_queue[b], e): return true
    return false

def research_cost(p:int, r:int) -> [int]:
    let item = research[r]
    let pct = bm_research_cost[p][item.building]
    return if pct == 0: item.cost else: map(item.cost) v: v * (100 + pct) / 100

def head_ticks(b:int) -> int:
    let t = head_tech(b)
    if t == -1: return 0
    let p = b_owner[b]
    var ticks = 0
    if t == AGE_UP_ENTRY:
        ticks = ages_list[next_age(p)].ticks * (100 + bm_age_time[p][b_kind[b]]) / 100
    else:
        ticks = research[t].ticks * (100 + bm_research_time[p][b_kind[b]]) / 100
    return max(1, ticks)

// Why building b can't queue the age-up (r = -1) or research r: false if it can (Tech.why_not).
def tech_barred(p:int, b:int, r:int) -> bool:
    if b < 0 or b_owner[b] != p or b_done[b] == 0: return true
    var cost = []::int
    if r < 0:
        let a = next_age(p)
        if a < 0: return true
        if ages_list[a].building != b_kind[b]: return true
        if tech_queued(p, AGE_UP_ENTRY): return true
        for(ages_list[a].needs[p]) k:
            if not has_building(p, k): return true
        cost = ages_list[a].cost
    else:
        let item = research[r]
        if item.building != b_kind[b]: return true
        if researched[p][r] == 1: return true
        if item.after >= 0 and researched[p][item.after] == 0: return true
        if not item.line_has[p]: return true
        if item.before[p] >= 0 and researched[p][item.before[p]] == 0: return true
        if ages[p] < item.age: return true
        if not item.open[p]: return true
        if tech_queued(p, r): return true
        cost = research_cost(p, r)
    if b_queue[b].length >= r_queue_max: return true
    return not can_afford(p, cost)

def cmd_age_up(p:int, bid:int):
    let b = b_index_of(bid)
    if tech_barred(p, b, -1): return
    pay(p, ages_list[next_age(p)].cost)
    b_queue[b].push(AGE_UP_ENTRY)

def cmd_research(p:int, bid:int, r:int):
    let b = b_index_of(bid)
    if r < 0 or tech_barred(p, b, r): return
    pay(p, research_cost(p, r))
    b_queue[b].push(entry_of(r))

// One tick of every age-up and research at the head of a queue (Tech.tick).
def tech_tick():
    for(b_id.length) b:
        if b_done[b] != 0:
            let t = head_tech(b)
            if t != -1:
                let p = b_owner[b]
                b_train[b]++
                if b_train[b] >= head_ticks(b):
                    b_queue[b].remove(0)
                    b_train[b] = 0
                    if t == AGE_UP_ENTRY: ages[p]++
                    else: researched[p][t] = 1
                    retype(p)
                    tech_refresh(p)
