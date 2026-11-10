// ------------------------------------------------------------------ the AI opponent (src/ai/bot.gd)
// The economy through EcoBot, and what a player does with it: a build order from data, soldiers
// counter-picked against what the enemy fields, defence and answers to raids, attack waves, a plan
// for the ages, healers, heroes, scouting, the land, camps and escorts. Like EcoBot it reads the
// state and issues commands. Left out (none in the scenarios, asserted where they'd act): trade and
// trade carts, Wonders, siege engines (_siege), walls (WallsAi), the race's ability (AbilityAi).

let BOT_THINK_EVERY = 20
let BUILD_COOLDOWN = 200
let REINFORCE = 4
let THREAT_TICKS = 200
let RESEND = 100
let TROUBLE_TILES = 8
let FLEE_TILES = 7
let RESPOND_TILES = 30

class Bot:
    player:int
    eco:EcoBot
    scout:Scout = Scout {}
    land:Land = Land {}
    expand:Expand = Expand {}
    wave = 0
    next_wave_tick = 0
    assault = false
    next_build = 0
    threat_ids:[int] = []  // enemy unit or building id -> the tick it last hit ours (in the order first noted)
    threat_ticks:[int] = []
    sent_ids:[int] = []  // our soldier id -> the tick it was sent to trouble
    sent_ticks:[int] = []
    aln = 0
    harea = 0
    rushed = -(1 << 30)
    blocked:[int] = []
    blocked_save = 0
    blocked_push = 0
    tower_x = -1
    tower_y = -1
    sheltering = false
    shelter_until = 0
    shelter_next = 0
    saving_age = false
    aim = 0
    target_x = -1
    target_y = -1
    hero_want:[int] = []
    resting:[int] = []
    on_back_foot = false
    next_trade = 0
    pressing = false  // clearly ahead: massing to finish the match (military.press)
    pushing = false   // pressing, and the massed army is out
    mass_from = -1    // the tick it began massing (-1: not massing)

def new_bot(p:int) -> Bot:
    let eco = EcoBot { p }
    eco.mix_ages = []::int
    eco.mixes = []::[int]
    for([ 1, 2, 3 ]) a:
        if has_mix(a):
            eco.mix_ages.push(a)
            eco.mixes.push(map(resource_names) res: cfg_or("economy.mix.{a}.{res}", 0))
    eco.max_workers = per_age("economy.max_workers", 1, 0)
    eco.age_workers = cfg("economy.age_workers")
    eco.rebalance = cfg_or("economy.rebalance_every", 0) * 20
    eco.plenty = cfg_or("economy.plenty", eco.plenty)
    let bot = Bot { p, eco }
    bot.next_wave_tick = wave_at[0] * 20
    return bot

def has_mix(a:int) -> bool:
    for(resource_names) res:
        if has_cfg("economy.mix.{a}.{res}"): return true
    return false

def bot_phase(bot:Bot) -> int: return (BOT_THINK_EVERY / 2 + bot.player * STAGGER % THINK_EVERY) % BOT_THINK_EVERY

def type_named(p:int, slot:string) -> int:
    for(t_slot) s, k:
        if t_player[k] == p and s == slot: return k
    return -1

def resource_index(res:string) -> int:
    for(resource_names) r, k:
        if r == res: return k
    return -1

def sorted_seen(p:int) -> [[int]]:
    let keys = map(fog_seen[p]) s, n: s[0] * (1 << 20) + n
    sort_ints(keys)
    return map(keys) k: fog_seen[p][k & ((1 << 20) - 1)]

def threat_tick(bot:Bot, id:int) -> int:
    for(bot.threat_ids) x, n:
        if x == id: return bot.threat_ticks[n]
    return -1

// ---- buildings

// The army's floor: no new workers while the soldiers are under pct of the workers (Bot._army_floor).
def army_floor(bot:Bot, army:[int], count:int):
    var pop_ = 0
    for(army) i: pop_ += t_pop[u_kind[i]]
    bot.eco.hold = false
    if not has_cfg("military.army_floor.pct") or count < cfg("military.army_floor.from") or pop_ * 100 >= count * cfg("military.army_floor.pct"): return
    for(b_id.length) b:
        if b_owner[b] == bot.player and b_done[b] == 1 and trains_soldiers_now(bot.player, b_kind[b]):
            bot.eco.hold = true
            return

// Does building type k train a soldier p can train in its age now? (A short roster's barracks may train only a
// line that opens in age 2: holding the economy for it in age 1 would hold it for good.)
def trains_soldiers_now(p:int, k:int) -> bool:
    if trains_workers(p, k): return false
    return exists(bm_trains[p][k]) t: ages[p] >= t_age[t]

def trains_workers(p:int, k:int) -> bool:
    for(bm_trains[p][k]) t:
        if t_worker[t]: return true
    return false

// The building type research turns into type k (a Watchtower for a Bastion), or -1.
def upgrade_of(k:int) -> int:
    for(research) r:
        for(r.effects) fx:
            if fx.kind == 8 and fx.value == k: return fx.stat
    return -1

def has_any(p:int, k:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p and b_kind[b] == k: return true
    return false

def upgraded_tower(k:int) -> bool:
    let was = upgrade_of(k)
    return was >= 0 and has_role(was, ROLE_TOWER)

def towers_up(p:int) -> int:
    var n = 0
    for(b_id.length) b:
        if b_owner[b] == p and (has_role(b_kind[b], ROLE_TOWER) or upgraded_tower(b_kind[b])): n++
    return n

// The nearest free spot for a building within r tiles of (ax, ay) (rings out), off `avoid`.
def spot_near(bot:Bot, ax:int, ay:int, size:int, r:int, avoid:[int]) -> int, int:
    for(r + 1) d:
        var dy = -d
        while dy <= d:
            var dx = -d
            while dx <= d:
                if max(abs(dx), abs(dy)) == d:
                    let x = ax + dx
                    let y = ay + dy
                    var near_avoid = false
                    for(avoid) c:
                        if c % W >= x - 2 and c % W <= x + size + 1 and c / W >= y - 2 and c / W <= y + size + 1: near_avoid = true
                    if not near_avoid and can_build(x, y, size, 0, false, false) and touches_area(bot.eco.reach, bot.eco.wln, bot.eco.home, x, y, size, size) and not seals(bot.eco, x, y, size):
                        return x, y
                dx++
            dy++
    return -1, -1

// Is this cell on our side: nearer `at` than any live enemy's start, by a fifth?
def ours_side(p:int, ax:int, ay:int, c:int) -> bool:
    let x = c % W
    let y = c / W
    let mine = dist2(ax, ay, x, y)
    for(num_players) q:
        if is_enemy(p, q) and defeated[q] == 0 and q < start_x.length:
            let theirs = dist2(start_x[q] / 1000, start_y[q] / 1000, x, y)
            if mine * 144 > theirs * 100: return false
    return true

// The nearest cell of that resource our workers can get to, at least `away` tiles from (ax, ay).
def patch(bot:Bot, ax:int, ay:int, kind:int, away:int, own_side:bool) -> int:
    if away <= 0: return bot_nearest_resource(bot.eco, ax * 1000, ay * 1000, kind, false, -1, false)
    var best = -1
    var best_d2 = 1 << 62
    for(resource_cells) c:
        if amount[c] > 0 and res_at(c) == kind:
            let d2 = dist2(ax, ay, c % W, c / W)
            if not (own_side and not ours_side(bot.player, ax, ay, c)):
                if d2 >= away * away and d2 < best_d2 and reaches_cell(bot.eco.reach, bot.eco.wln, bot.eco.home, c):
                    best_d2 = d2
                    best = c
    return best

def nearest_workers(bot:Bot, workers:[int], x:int, y:int, n:int) -> [int]:
    let keys = []::int
    for(workers) i:
        if held(bot.eco, u_id[i]) <= tick: keys.push(dist2(x, y, u_x[i], u_y[i]) * (1 << 20) + u_id[i])
    sort_ints(keys)
    return map(slice(keys, 0, min(n, keys.length))) k: k & ((1 << 20) - 1)

def build_order_step(bot:Bot, tc:int, workers:[int], count:int):
    if tick < bot.next_build or building_underway(bot.eco, false): return
    let p = bot.player
    bot.blocked = []::int
    let have_kinds = []::int
    let have_n = []::int
    def add_have(kind:int):
        for(have_kinds) h, n:
            if h == kind:
                have_n[n]++
                return
        have_kinds.push(kind)
        have_n.push(1)
    def have(kind:int) -> int:
        for(have_kinds) h, n:
            if h == kind: return have_n[n]
        return 0
    for(b_id.length) b:
        if b_owner[b] == p and (b_done[b] == 1 or reaches_building(bot.eco.reach, bot.eco.wln, bot.eco.home, b)):
            add_have(b_kind[b])
            let was = upgrade_of(b_kind[b])
            if was >= 0: add_have(was)
    let wanted_kinds = []::int
    let wanted_n = []::int
    for(build_order) step:
        let k = btype_named(step.building)    // (the build order names buildings by id: it's data)
        if k < 0 or bm_lacks[p][k]: continue  // (a building the game or a mod doesn't have: its steps are skipped)
        var prev = 0
        var at = -1
        for(wanted_kinds) wk, n:
            if wk == k:
                prev = wanted_n[n]
                at = n
        let want = if step.count >= 0: step.count else: prev + 1
        if at < 0:
            wanted_kinds.push(k)
            wanted_n.push(want)
        else:
            wanted_n[at] = want
        if have(k) >= want: continue
        if ages[p] < step.age: continue
        if step.guard_step == 1 and not (lv_guard_crossing and bot.on_back_foot): continue
        var need = step.workers
        if step.expand_workers >= 0 and wants_town(b_cx[tc] * 1000 + 1500, b_cy[tc] * 1000 + 1500): need = step.expand_workers
        if count < need or not workers.length: return
        if bot.saving_age and not has_role(k, ROLE_HOUSING) and not ages_list[next_age(p)].needs[p].contains(k): return  // (saving for the next age: only houses and what it needs)
        if not can_afford(p, bm_cost[p][k]):
            bot.blocked = bm_cost[p][k]
            bot.blocked_save = step.save
            bot.blocked_push = if step.push >= 0: step.push else: cfg_or("economy.build_push", 30)
            return
        var ax = b_cx[tc] + 1
        var ay = b_cy[tc] + 1
        if step.near != "-":
            let cell = patch(bot, ax, ay, resource_index(step.near) + 1, step.away, step.own_side == 1)
            if cell >= 0:
                ax = cell % W
                ay = cell / W
        var sx, sy = house_spot(bot.eco, ax, ay, bt_size[k])
        if lv_guard_crossing and step.guard_step == 1:
            let gx, gy = guard_spot(bot.land, bot)
            if gx >= 0:
                let bx, by = spot_near(bot, gx, gy, bt_size[k], cfg("land.guard_tiles") - 1, []::int)
                if bx >= 0:
                    sx = bx
                    sy = by
        if sx < 0: return
        let builders = nearest_workers(bot, workers, sx * 1000, sy * 1000, step.builders)
        issue_cmd(p, 4, builders, k, sx, sy, 0)
        bot.next_build = tick + BUILD_COOLDOWN
        return

// What we save for: the next age once we have the workers for it, else the build step waiting on
// resources, else a Watchtower where we were raided (Bot._goal).
def goal_of(bot:Bot, count:int) -> [int]:
    let p = bot.player
    bot.saving_age = false
    let a = next_age(p)
    let at = if ages[p] == 1: cfg("economy.age_workers") else: lv_age3_workers
    if a >= 0 and count >= at and not tech_queued(p, AGE_UP_ENTRY):
        let cost = copy(ages_list[a].cost)
        for(ages_list[a].needs[p]) k:
            if not has_any(p, k):
                for(cost) v, r: cost[r] = v + bm_cost[p][k][r]
        bot.saving_age = true
        return cost
    if bot.blocked.length: return bot.blocked
    if bot.tower_x >= 0 and btype_with(ROLE_TOWER) >= 0 and towers_up(p) < lv_towers: return bm_cost[p][btype_with(ROLE_TOWER)]
    return []::int

def age_three(bot:Bot, tc:int, count:int):
    if ages[bot.player] != 2 or count < lv_age3_workers: return
    if not tech_barred(bot.player, tc, -1): issue_cmd(bot.player, 9, []::int, b_id[tc], 0, 0, 0)

// ---- research

// How many of our soldiers a research's unit effects reach.
def reach_count(r:Research, kinds:[int], counts:[int]) -> int:
    var n = 0
    for(kinds) k, q:
        var hit = false
        for(r.effects) fx:
            if fx.kind <= 4 and reaches(fx, t_tags[k]): hit = true
        if hit: n += counts[q]
    return n

def upgrade_lines(bot:Bot, army:[int]):
    let p = bot.player
    let kinds = []::int
    let counts = []::int
    for(army) i:
        var at = -1
        for(kinds) k, q:
            if k == u_kind[i]: at = q
        if at < 0:
            kinds.push(u_kind[i])
            counts.push(1)
        else:
            counts[at]++
    let keep = map(num_resources) r: if r < bot.eco.goal.length: bot.eco.goal[r] else: 0
    let wanted = []::int  // research index * 2 + old
    let economy_r = cfg_list("research.economy")
    let buildings_r = cfg_list("research.buildings")
    for(research) r, ri:
        var gather = false
        for(r.effects) fx:
            if fx.kind == 7: gather = true
        let line = r.line_age > 0
        let old = line or (lv_build_up and gather)
        let wait = cfg_list("research.wait_for.{r.id}")
        let wk = if wait.length: btype_named(wait[0]) else: -1
        if wk >= 0 and not has_building(p, wk): continue  // (waiting on a building that doesn't exist: no wait)
        var listed = false
        for(economy_r) id:
            if id == r.id: listed = true
        for(buildings_r) id:
            if id == r.id: listed = true
        if old or listed or reach_count(r, kinds, counts) >= cfg("research.army_min"): wanted.push(ri * 2 + (if old: 1 else: 0))
    for(b_id.length) b:
        if b_owner[b] == p:
            var busy = false
            for(b_queue[b]) e:
                if e < 0: busy = true
            if not busy:
                var done = false
                for(wanted) e:
                    if not done:
                        let ri = e / 2
                        let old = e % 2 == 1
                        let r = research[ri]
                        if r.building == b_kind[b] and not tech_barred(p, b, ri):
                            var spare = true
                            for(r.cost) c, k:
                                if stock[k][p] < c * (if lv_build_up or r.line_age > 0: 1 else: 2) + (if old: 0 else: keep[k]): spare = false
                            if spare:
                                issue_cmd(p, 10, []::int, b_id[b], ri, 0, 0)
                                done = true

// ---- soldiers

def fielded(p:int, k:int) -> int:
    var n = 0
    for(u_x.length) i:
        if u_owner[i] == p and u_kind[i] == k: n++
    for(b_id.length) b:
        if b_owner[b] == p:
            for(b_queue[b]) e:
                if e == k: n++
    return n

// A line the bot keeps only a few of (siege engines, war beasts) and has them all.
def enough(p:int, slot:string, k:int) -> bool:
    let most = cfg_or("military.siege.max.{slot}", cfg_or("military.most.{slot}", -1))
    return most >= 0 and fielded(p, k) >= most

def affords(p:int, cost:[int], reserve:[int]) -> bool:
    for(cost) c, r:
        if stock[r][p] < c + reserve[r]: return false
    return true

// How many enemy soldiers we see or remember carry each class, and their bonuses ("bonus:" keyed apart).
def enemy_tags(bot:Bot) -> [int], [int]:
    let tags = map(num_classes): 0
    let bonus = map(num_classes): 0
    for(bot.scout.seen_kind) k:
        for(t_tags[k]) c: tags[c]++
        for(lines_bonus(k)) v, c: bonus[c] += v
    if bot.aim != 0: tags[2] = cfg("military.building_foes")  // "building"
    return tags, bonus

// The bonus vector of a type's current line step (t.eval.bonus).
def lines_bonus(k:int) -> [int]: return t_bonus[k]

// Counter value of one of our types against what the enemy fields (Bot._score).
def score(k:int, tags:[int], bonus:[int]) -> int:
    var s = t_eval_attack[k] + t_hp[k] / 10
    for(t_bonus[k]) v, c: s += v * tags[c]
    for(t_tags[k]) c: s -= bonus[c]
    return s

def pick(bot:Bot, trains:[int], tags:[int], bonus:[int], reserve:[int]) -> int:
    let p = bot.player
    var best = -1
    var best_score = -(1 << 30)
    for(trains) k:
        let slot = t_slot[k]
        if ages[p] < t_age[k] or enough(p, slot, k) or t_trader[k] or bm_lacks_slot(p, slot): continue
        if reserve.length and not affords(p, t_cost[k], reserve): continue
        let s = hook_ai_train_score(p, slot, k, score(k, tags, bonus) + cfg_or("military.pick_bias.{slot}", 0))
        if s > best_score:
            best_score = s
            best = k
    return best

// Engines on the regroup beat, while attacking: rams for the nearest enemy gate, wall or tower they
// can see (any building if none), catapults for a tower within a short walk; idle rams with nothing
// in sight march on the army's target (Bot._siege).
def bot_siege(bot:Bot, army:[int], hx:int, hy:int):
    if not has_cfg("military.siege.towers_within") or not bot.assault or tick % (cfg("military.regroup_every") * 20) != bot_phase(bot): return
    let targets = []::int
    let groups = []::[int]
    let march = []::int
    for(army) i:
        let k = u_kind[i]
        let ram = t_buildings_only[k] != 0
        let thrower = t_splash[k] > 0
        if (ram or thrower) and not (u_foe[i] != 0 and b_index_of(u_foe[i]) >= 0):
            var best = 0
            let tw = cfg("military.siege.towers_within") * 1000
            var best_d = if thrower: tw * tw else: 1 << 60
            var best_rank = 2
            for(b_id.length) b:
                if is_enemy(bot.player, b_owner[b]) and (fog_sees_area(bot.player, b) or (ram and bot.pressing and known(bot.player, b) and has_role(b_kind[b], ROLE_HUB))):
                    let bk = b_kind[b]
                    let defence = bt_attacks[bk] != 0 or bt_gate[bk] != 0 or bt_wall[bk] != 0
                    if not (thrower and bt_attacks[bk] == 0):
                        let hub = ram and bot.pressing and has_role(bk, ROLE_HUB) and reaches_building(bot.eco.reach, bot.aln, bot.harea, b)
                        let rank = if hub: -1 elif defence: 0 else: 1
                        let d = dist2(u_x[i], u_y[i], b_cx[b] * 1000 + b_sx[b] * 500, b_cy[b] * 1000 + b_sy[b] * 500)
                        if rank < best_rank or (rank == best_rank and d < best_d):
                            best = b_id[b]
                            best_d = d
                            best_rank = rank
            if best != 0:
                var at = -1
                for(targets) id, n:
                    if id == best: at = n
                if at < 0:
                    targets.push(best)
                    groups.push([ u_id[i] ])
                else: groups[at].push(u_id[i])
            elif ram and u_foe[i] == 0 and u_moving[i] == 0: march.push(u_id[i])
    let order = map(targets.length) n: n
    insertion_sort(order) a, b: targets[a] < targets[b]
    for(order) n: issue_cmd(bot.player, CMD_ATTACK, groups[n], targets[n], 0, 0, 0)
    var tx, ty = enemy_target(bot, hx, hy)
    if march.length and tx >= 0:
        tx, ty = reachable(bot, tx, ty)
        issue_cmd(bot.player, CMD_ATTACK_MOVE, march, tx, ty, 0, 0)

def bm_lacks_slot(p:int, slot:string) -> bool: return contains(slots_lacked[p], slot_index(slot))

def train_soldiers(bot:Bot, workers:[int], count:int):
    let p = bot.player
    let reserve = map(num_resources): 0
    var guard_pop = 0
    for(u_x.length) i:
        let k = u_kind[i]
        if u_owner[i] == p and not t_worker[k] and not t_healer[k] and t_animal[k] == 0 and not t_trader[k]: guard_pop += t_pop[k]
    if lv_army_ratio > 0 and guard_pop * 100 >= count * lv_army_ratio * ages[p]: return
    let massing = bot.pressing and guard_pop < press_army(bot, count)
    if (bot.saving_age or (((lv_build_up and bot.blocked_save >= 1) or bot.blocked_save >= 2) and equal(bot.eco.goal, bot.blocked))) and
            (guard_pop >= cfg("military.guard") or ages[p] == 1) and not bot.threat_ids.length and not massing:
        for(bot.eco.goal) g, r: reserve[r] = g
    for(bot.expand.want) v, r: reserve[r] += v
    for(bot.land.want) v, r: reserve[r] += v
    for(bot.hero_want) v, r: reserve[r] += v
    let tags, bonus = enemy_tags(bot)
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] != 0 and head_tech(b) == -1:
            let trains = bm_trains[p][b_kind[b]]
            if trains.length and not trains_workers(p, b_kind[b]) and b_queue[b].length < cfg("military.queue"):
                let best = pick(bot, trains, tags, bonus, reserve)
                if best >= 0: issue_cmd(p, 6, []::int, b_id[b], best, 1, 0)

def train_scout(bot:Bot, scouts:int):
    let p = bot.player
    let k = type_named(p, "scout")
    if k < 0 or scouts >= cfg("military.scouts.keep") or ages[p] < t_age[k] or not can_afford(p, t_cost[k]): return
    for(b_id.length) b:
        if b_owner[b] == p and contains(b_queue[b], k): return
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] == 1 and contains(bm_trains[p][b_kind[b]], k) and b_queue[b].length < cfg("military.queue"):
            issue_cmd(p, 6, []::int, b_id[b], k, 1, 0)
            return

def train_healers(bot:Bot, tc:int, army:[int], healers:[int]):
    let p = bot.player
    let k = type_named(p, "healer")
    if not has_cfg("military.healers.per_army") or k < 0 or ages[p] < t_age[k]: return
    var queued = 0
    for(b_queue[tc]) e:
        if e == k: queued++
    let want = min(cfg_or("military.healers.max.{ages[p]}", 0), army.length / max(1, cfg("military.healers.per_army")))
    if queued > 0 or healers.length >= want: return
    let wk = worker_type(p)
    for(num_resources) r:
        if stock[r][p] < t_cost[k][r] + t_cost[wk][r]: return
    issue_cmd(p, 6, []::int, b_id[tc], k, 1, 0)

// The race's heroes: trained once the army is big enough, a hurt one walks home to heal (Bot._hero).
def heroes_think(bot:Bot, tc:int, army:[int], hx:int, hy:int):
    let p = bot.player
    let ks = filter(hero_types) k: t_player[k] == p
    if not has_cfg("military.hero.army") or not ks.length: return
    var out = 0
    for(ks) k:
        let n = hero_slot(k)
        if hero_id[n] != 0 or hero_queued(p, k): out++
    var k = -1
    for(ks) h:
        if k < 0 and not hero_barred(p, h): k = h
    if k < 0: k = ks[0]
    bot.hero_want = []::int
    if not hero_barred(p, k) and ages[p] >= t_age[k] and army.length >= cfg("military.hero.army") + out * cfg("military.hero.more") and
            b_queue[tc].length < cfg("military.queue"):
        let cost = unit_cost(k)
        if affords(p, cost, t_cost[worker_type(p)]):
            issue_cmd(p, 6, []::int, b_id[tc], k, 1, 0)
        elif not bot.threat_ids.length:
            bot.hero_want = cost
    let home_r = cfg("military.defend_tiles") * 1000
    let still = []::int
    for(ks) hk:
        let n = hero_slot(hk)
        let i = if hero_id[n] != 0: index_of(hero_id[n]) else: -1
        if i >= 0:
            let id = u_id[i]
            let pct = u_hp[i] * 100 / max(1, t_hp[hk])
            let resting = contains(bot.resting, id)
            if not resting and pct < cfg("military.hero.retreat_pct") and dist2(hx, hy, u_x[i], u_y[i]) > home_r * home_r / 4:
                still.push(id)
                issue_cmd(p, 0, [ id ], hx, hy, 0, 0)
            elif resting and pct < cfg("military.hero.back_pct"):
                still.push(id)
    bot.resting = still

def hero_queued(p:int, k:int) -> bool:
    for(b_id.length) b:
        if b_owner[b] == p and contains(b_queue[b], k): return true
    return false

// Healers follow the army, `behind` tiles back from the middle of its rear half (Bot._escort).
def escort_healers(bot:Bot, army:[int], healers:[int], hx:int, hy:int):
    if not healers.length or not army.length or tick % (cfg_or("military.healers.every", 3) * 20) != bot_phase(bot): return
    let home_r = cfg("military.defend_tiles") * 1000
    let out = filter(army) i: dist2(hx, hy, u_x[i], u_y[i]) > home_r * home_r
    var mx = hx
    var my = hy
    if out.length >= 2:
        let keys = map(out) i: dist2(hx, hy, u_x[i], u_y[i]) * (1 << 20) + u_id[i]
        sort_ints(keys)
        let rear = slice(keys, 0, (keys.length + 1) / 2)
        var sx = 0
        var sy = 0
        for(rear) key:
            let i = index_of(key & ((1 << 20) - 1))
            sx += u_x[i]
            sy += u_y[i]
        mx = sx / rear.length
        my = sy / rear.length
    let d = isqrt(dist2(mx, my, hx, hy))
    let back = min(cfg("military.healers.behind") * 1000, d)
    let tx = mx + (hx - mx) * back / max(1, d)
    let ty = my + (hy - my) * back / max(1, d)
    let follow = cfg("military.healers.follow") * 1000
    let ids = []::int
    for(healers) i:
        if u_patient[i] == 0 and dist2(u_x[i], u_y[i], tx, ty) > follow * follow: ids.push(u_id[i])
    if ids.length: issue_cmd(bot.player, 1, ids, tx, ty, 0, 0)

// ---- the army

def reachable(bot:Bot, x:int, y:int) -> int, int:
    if bot.harea == 0 or reach_labels(bot.eco.reach, bot.aln)[cell_of(x, y)] == bot.harea: return x, y
    let nx, ny = nearest_in(bot.eco.reach, bot.aln, bot.harea, x, y)
    return if nx >= 0: (nx, ny) else: (x, y)

def defend(bot:Bot, army:[int], hx:int, hy:int):
    let r = cfg("military.defend_tiles") * 1000
    var intruder = -1
    var best_d2 = r * r
    for(u_x.length) i:
        if is_foe(bot.player, u_owner[i]) and t_animal[u_kind[i]] == 0 and fog_visible(bot.player, u_x[i], u_y[i]):  // (a rival's sheep is no intruder)
            let d2 = dist2(hx, hy, u_x[i], u_y[i])
            if d2 < best_d2:
                best_d2 = d2
                intruder = i
    if intruder < 0: return
    let ids = []::int
    for(army) i:
        if u_foe[i] == 0 and dist2(hx, hy, u_x[i], u_y[i]) < 4 * r * r and not is_climbing(bot.land, i) and u_perch[i] == 0 and u_task[i] != T_CLIMB: ids.push(u_id[i])  // (not one on its way up our wall)
    if ids.length:
        let tx, ty = reachable(bot, u_x[intruder], u_y[intruder])
        issue_cmd(bot.player, 1, ids, tx, ty, 0, 0)

// Remember every enemy blow on our buildings and workers (Bot._note_hits).
def note_hits(bot:Bot):
    for(events) e:
        if e.kind == EV_HIT:
            let vi = index_of(e.b)
            var ours = false
            if vi >= 0:
                ours = u_owner[vi] == bot.player and t_worker[u_kind[vi]]
            else:
                let vb = b_index_of(e.b)
                ours = vb >= 0 and b_owner[vb] == bot.player
            if ours:
                let ai = index_of(e.a)
                let ab = if ai < 0: b_index_of(e.a) else: -1
                let by = if ai >= 0: u_owner[ai] elif ab >= 0: b_owner[ab] else: -1
                if by >= 0 and is_foe(bot.player, by): set_pair(bot.threat_ids, bot.threat_ticks, e.a, tick)

def where_is(id:int) -> int, int:
    let i = index_of(id)
    if i >= 0: return u_x[i], u_y[i]
    let b = b_index_of(id)
    if b >= 0: return b_cx[b] * 1000 + b_sx[b] * 500, b_cy[b] * 1000 + b_sy[b] * 500
    return -1, -1

def send_home(bot:Bot, hx:int, hy:int):
    if not bot.sent_ids.length: return
    let ids = copy(bot.sent_ids)
    sort_ints(ids)
    bot.sent_ids = []::int
    bot.sent_ticks = []::int
    if bot.assault: return
    let home_r = 2 * cfg("military.defend_tiles") * 1000
    let back = filter(ids) id:
        let i = index_of(id)
        i >= 0 and u_foe[i] == 0 and u_moving[i] == 0 and dist2(u_x[i], u_y[i], hx, hy) > home_r * home_r
    if back.length: issue_cmd(bot.player, 1, back, hx, hy, 0, 0)

// Answer raids anywhere (Bot._respond).
def respond(bot:Bot, tc:int, army:[int], workers:[int], hx:int, hy:int):
    let p = bot.player
    let ids = copy(bot.threat_ids)
    sort_ints(ids)
    let live = []::int
    for(ids) id:
        let wx, _wy = where_is(id)
        if tick - threat_tick(bot, id) > THREAT_TICKS or wx < 0:
            for(bot.threat_ids) x, n:
                if x == id:
                    bot.threat_ids.remove(n)
                    bot.threat_ticks.remove(n)
                    break
        else:
            live.push(id)
    if not live.length:
        send_home(bot, hx, hy)
        if bot.sheltering:
            issue_cmd(p, 12, []::int, 0, 0, 0, 0)
            bot.sheltering = false
        return
    var focus = live[0]
    for(live) id:
        if threat_tick(bot, id) > threat_tick(bot, focus): focus = id
    let fx, fy = where_is(focus)
    let rx = []::int
    let ry = []::int
    var strength = 0
    for(live) id:
        let ax, ay = where_is(id)
        if dist2(ax, ay, fx, fy) <= TROUBLE_TILES * TROUBLE_TILES * 1000000:
            rx.push(ax)
            ry.push(ay)
            let i = index_of(id)
            strength += if i >= 0: t_pop[u_kind[i]] else: 4
    let trouble = TROUBLE_TILES * TROUBLE_TILES * 1000000
    for(u_x.length) i:
        if is_foe(p, u_owner[i]) and not t_worker[u_kind[i]] and threat_tick(bot, u_id[i]) < 0 and dist2(u_x[i], u_y[i], fx, fy) <= trouble and fog_visible(p, u_x[i], u_y[i]):
            rx.push(u_x[i])
            ry.push(u_y[i])
            strength += t_pop[u_kind[i]]
    let d = isqrt(dist2(fx, fy, hx, hy))
    if has_cfg("military.towers.age") and ages[p] >= cfg("military.towers.age") and d > (FLEE_TILES + 2) * 1000 and d <= cfg("military.towers.within") * 1000:
        bot.tower_x = fx
        bot.tower_y = fy
    if bot.sheltering and tick >= bot.shelter_until:
        issue_cmd(p, 12, []::int, 0, 0, 0, 0)
        bot.sheltering = false
    if lv_shelter_pop > 0 and not bot.sheltering and tick >= bot.shelter_next and strength >= lv_shelter_pop and d <= cfg("military.shelter.tiles") * 1000:
        var home_pop = 0
        let home_r = 2 * cfg("military.defend_tiles") * 1000
        for(army) i:
            if dist2(u_x[i], u_y[i], hx, hy) <= home_r * home_r: home_pop += t_pop[u_kind[i]]
        if home_pop < strength:
            issue_cmd(p, 11, []::int, b_id[tc], 0, 0, 0)
            bot.sheltering = true
            bot.shelter_until = tick + cfg("military.shelter.seconds") * 20
            bot.shelter_next = tick + cfg("military.shelter.every") * 20
    var tx = hx
    var ty = hy
    if d <= (FLEE_TILES + 2) * 1000:
        tx, ty = reachable(bot, clamp(hx + (hx - fx) * 6000 / max(d, 1), 0, W * 1000 - 1), clamp(hy + (hy - fy) * 6000 / max(d, 1), 0, H * 1000 - 1))
    let flee = []::int
    let call = r_call_range * 1000 - 1500
    for(workers) i:
        let uid = u_id[i]
        var near = false
        for(rx) ax, n:
            if dist2(ax, ry[n], u_x[i], u_y[i]) <= FLEE_TILES * FLEE_TILES * 1000000: near = true
        if near:
            if bot.sheltering and (u_task[i] == T_GARRISON or dist2(u_x[i], u_y[i], hx, hy) <= call * call):
                hold_until(bot.eco, uid, tick + THREAT_TICKS)
            else:
                if held(bot.eco, uid) <= tick or u_moving[i] == 0: flee.push(uid)
                hold_until(bot.eco, uid, tick + THREAT_TICKS)
    if flee.length: issue_cmd(p, 0, flee, tx, ty, 0, 0)
    // Massing: no soldiers into a tower's arrows, nor after raiders running home.
    if bot.pressing and not bot.pushing and (index_of(focus) < 0 or not ours_side(p, hx / 1000, hy / 1000, cell_of(fx, fy))): return
    let home_r = 2 * cfg("military.defend_tiles") * 1000
    let keys = []::int
    let pops = dictionary<int, int>(127)
    for(army) i:
        if not ((u_foe[i] != 0 and index_of(u_foe[i]) >= 0) or is_climbing(bot.land, i) or u_perch[i] != 0 or u_task[i] == T_CLIMB):  // (up on our wall, or on its way: it shoots from there)
            let d2 = dist2(u_x[i], u_y[i], fx, fy)
            if not (dist2(u_x[i], u_y[i], hx, hy) > home_r * home_r and d2 > RESPOND_TILES * RESPOND_TILES * 1000000):
                keys.push(d2 * (1 << 20) + u_id[i])
                pops.set(u_id[i], t_pop[u_kind[i]])
    sort_ints(keys)
    let need = 2 * strength + 2
    var got = 0
    let go = []::int
    for(keys) key:
        if got < need:
            let id = key & ((1 << 20) - 1)
            got += pops.get(id, 0)
            var sent_at = -RESEND
            for(bot.sent_ids) x, n:
                if x == id: sent_at = bot.sent_ticks[n]
            if sent_at + RESEND <= tick:
                go.push(id)
                set_pair(bot.sent_ids, bot.sent_ticks, id, tick)
    if go.length:
        let ax, ay = reachable(bot, fx, fy)
        issue_cmd(p, 1, go, ax, ay, 0, 0)

// A Watchtower where we were raided, once it's quiet (Bot._tower).
def tower_after_raid(bot:Bot, workers:[int]):
    let p = bot.player
    if bot.tower_x < 0 or bot.threat_ids.length or tick < bot.next_build: return
    if towers_up(p) >= lv_towers:
        bot.tower_x = -1
        bot.tower_y = -1
        return
    let k = btype_with(ROLE_TOWER)
    if k < 0 or building_underway(bot.eco, true) or not can_afford(p, bm_cost[p][k]) or not workers.length: return
    let sx, sy = house_spot(bot.eco, bot.tower_x / 1000, bot.tower_y / 1000, bt_size[k])
    bot.tower_x = -1
    bot.tower_y = -1
    if sx < 0: return
    issue_cmd(p, 4, nearest_workers(bot, workers, sx * 1000, sy * 1000, 2), k, sx, sy, 0)
    bot.next_build = tick + BUILD_COOLDOWN

// ---- targets

def known(p:int, b:int) -> bool:
    if fog[p][b_cy[b] * W + b_cx[b]] != UNSEEN: return true
    if not has_role(b_kind[b], ROLE_HUB): return false
    for(start_x) sx, q:
        if abs(sx / 1000 - b_cx[b] - 1) <= 2 and abs(start_y[q] / 1000 - b_cy[b] - 1) <= 2: return true
    return false

def known_enemy_town(bot:Bot, hx:int, hy:int) -> int:
    var best = 0
    var best_d2 = 1 << 62
    for(b_id.length) b:
        if has_role(b_kind[b], ROLE_HUB) and is_enemy(bot.player, b_owner[b]) and fog[bot.player][b_cy[b] * W + b_cx[b]] != UNSEEN and
                reaches_building(bot.eco.reach, bot.aln, bot.harea, b):
            let d2 = dist2(hx, hy, b_cx[b] * 1000, b_cy[b] * 1000)
            if d2 < best_d2:
                best_d2 = d2
                best = b_id[b]
    return best

// Where to attack: the nearest enemy Town Center we've seen, else the nearest enemy building we've
// seen but walls, else an enemy's start (Bot._enemy_target); a Wonder we know of before all.
def enemy_target(bot:Bot, hx:int, hy:int) -> int, int:
    var bx = -1
    var by = -1
    var best_d2 = 1 << 62
    var best_rank = -2
    var best_ok = false
    for(b_id.length) b:
        let wonder = has_role(b_kind[b], ROLE_WONDER)
        if is_enemy(bot.player, b_owner[b]) and (known(bot.player, b) or (wonder and knows_wonder(bot, b))):
            let x = b_cx[b] * 1000 + b_sx[b] * 500
            let y = b_cy[b] * 1000 + b_sy[b] * 500
            let rank = if wonder: 2 elif has_role(b_kind[b], ROLE_HUB): 1 elif bt_wall[b_kind[b]] or bt_gate[b_kind[b]]: -1 else: 0
            let ok = reaches_building(bot.eco.reach, bot.aln, bot.harea, b)
            let d2 = dist2(hx, hy, x, y)
            if (ok and not best_ok) or (ok == best_ok and (rank > best_rank or (rank == best_rank and d2 < best_d2))):
                bx = x
                by = y
                best_d2 = d2
                best_rank = rank
                best_ok = ok
                bot.aim = if ok: b_id[b] else: 0
    if best_rank < 0:
        bot.aim = 0
        for(num_players) q:
            if is_enemy(bot.player, q) and defeated[q] == 0 and q < start_x.length: return start_x[q], start_y[q]
    return bx, by

def sides(bot:Bot, b:int, area:int) -> int:
    let lab = reach_labels(bot.eco.reach, bot.aln)
    let cells = footprint(b)
    let counted = []::int
    for(cells) c:
        for([ [ -1, 0 ], [ 1, 0 ], [ 0, -1 ], [ 0, 1 ] ]) dd:
            let x = c % W + dd[0]
            let y = c / W + dd[1]
            let o = y * W + x
            if x >= 0 and y >= 0 and x < W and y < H and lab[o] == area and not contains(cells, o) and not contains(counted, o): counted.push(o)
    return counted.length

def blocker(bot:Bot, hx:int, hy:int, tx:int, ty:int) -> int, int:
    var bx = tx
    var by = ty
    var best_d = 1 << 62
    let tarea = area_at(bot.eco.reach, bot.aln, tx, ty)
    bot.aim = 0
    for(b_id.length) b:
        if is_enemy(bot.player, b_owner[b]) and reaches_building(bot.eco.reach, bot.aln, bot.harea, b):
            let x = b_cx[b] * 1000 + b_sx[b] * 500
            let y = b_cy[b] * 1000 + b_sy[b] * 500
            var d = isqrt(dist2(hx, hy, x, y)) + isqrt(dist2(x, y, tx, ty))
            let sd = sides(bot, b, bot.harea)
            if tarea == 0 or sd == 0 or sides(bot, b, tarea) == 0: d += 1 << 40
            d += b_hp[b] * 1000 / max(sd, 1)
            if d < best_d:
                best_d = d
                bx = x
                by = y
                bot.aim = b_id[b]
    return bx, by

def wave_target(bot:Bot, hx:int, hy:int) -> int, int:
    var tx, ty = enemy_target(bot, hx, hy)
    if tx < 0: return tx, ty
    if bot.harea != 0 and area_at(bot.eco.reach, bot.aln, tx, ty) != bot.harea:
        tx, ty = blocker(bot, hx, hy, tx, ty)
    return reachable(bot, tx, ty)

def repeat_min(bot:Bot) -> int: return per_age("military.repeat_min_army", ages[bot.player], 1)

def pop_of(idx:[int]) -> int:
    var n = 0
    for(idx) i:
        if i >= 0: n += t_pop[u_kind[i]]
    return n

def dominant(bot:Bot, idx:[int]) -> bool:
    var theirs = 0
    for(bot.scout.seen_kind) k: theirs += t_pop[k]
    let ours = pop_of(idx)
    var with = ours
    for(u_x.length) i:
        let k = u_kind[i]
        if u_owner[i] != bot.player and u_owner[i] != gaia and not is_enemy(bot.player, u_owner[i]) and not t_worker[k] and not t_healer[k] and t_animal[k] == 0 and not t_trader[k]: with += t_pop[k]
    return ours >= repeat_min(bot) and with * 100 >= max(1, theirs) * cfg("military.dominant_pct")

def has_siege(idx:[int]) -> bool:
    for(idx) i:
        if i >= 0 and (t_buildings_only[u_kind[i]] or t_splash[u_kind[i]] > 0): return true
    return false

// Where to wait for a bigger army when the target stands under remembered shooting buildings.
def contain_point(bot:Bot, tx:int, ty:int) -> int, int:
    let path = bot.land.our_path
    if not path.length or tx < 0: return -1, -1
    let gap = cfg("military.contain_gap")
    let sxs = []::int
    let sys = []::int
    let srs = []::int
    for(sorted_seen(bot.player)) s:
        let k = s[1]
        if is_enemy(bot.player, s[2]) and bt_attacks[k] and s[6] != 0:
            let x = s[3] + s[5] / 2
            let y = s[4] + s[9] / 2
            let r = bt_range[k] + max(s[5], s[9]) / 2 + gap
            if (x - tx / 1000) * (x - tx / 1000) + (y - ty / 1000) * (y - ty / 1000) <= r * r:
                sxs.push(x)
                sys.push(y)
                srs.push(r)
    if not sxs.length: return -1, -1
    var n = path.length - 1
    while n >= 0:
        let cx = path[n] % W
        let cy = path[n] / W
        var under = false
        for(sxs) x, q:
            if (cx - x) * (cx - x) + (cy - sys[q]) * (cy - sys[q]) <= srs[q] * srs[q]: under = true
        if not under: return cx * 1000 + 500, cy * 1000 + 500
        n--
    return -1, -1

def via(bot:Bot, ids:[int], vx:int, vy:int, tx:int, ty:int):
    if not ids.length: return
    if vx < 0:
        issue_cmd(bot.player, 1, ids, tx, ty, 0, 0)
        return
    issue_cmd(bot.player, 1, ids, vx, vy, 0, 0)
    issue_cmd(bot.player, 1, ids, tx, ty, 0, 0, 1)

// The enemy economy worth raiding, nearest us first (Bot._eco_targets).
def eco_targets(bot:Bot, hx:int, hy:int) -> [int]:
    let p = bot.player
    let kinds = map(cfg_list("military.raid_targets")) id: btype_named(id)
    let safe = cfg("military.raid_safe")
    let seen = sorted_seen(p)
    let sxs = []::int
    let sys = []::int
    let srs = []::int
    for(seen) s:
        if is_enemy(p, s[2]) and bt_attacks[s[1]]:
            sxs.push(s[3] + s[5] / 2)
            sys.push(s[4] + s[9] / 2)
            srs.push(bt_range[s[1]] + safe)
    let keys = []::int
    let pts = []::int
    for(seen) s:
        if is_enemy(p, s[2]) and kinds.contains(s[1]):
            let x = s[3] + s[5] / 2
            let y = s[4] + s[9] / 2
            var under = false
            for(sxs) ex, q:
                if (ex - x) * (ex - x) + (sys[q] - y) * (sys[q] - y) <= srs[q] * srs[q]: under = true
            if not under and touches_area(bot.eco.reach, bot.aln, bot.harea, s[3], s[4], s[5], s[9]):
                keys.push(dist2(hx, hy, x * 1000 + 500, y * 1000 + 500) * (1 << 20) + s[0])
                pts.push(s[0])
                pts.push(x * 1000 + 500)
                pts.push(y * 1000 + 500)
    sort_ints(keys)
    let out = []::int
    for(keys) key:
        let id = key & ((1 << 20) - 1)
        var q = 0
        while q < pts.length:
            if pts[q] == id:
                out.push(pts[q + 1])
                out.push(pts[q + 2])
            q += 3
    return out

def contains_str(xs:[string], s:string) -> bool:
    for(xs) x:
        if x == s: return true
    return false

def raid(bot:Bot, ids:[int], hx:int, hy:int) -> bool:
    let targets = eco_targets(bot, hx, hy)
    if not targets.length or not ids.length: return false
    let groups = clamp(ids.length / max(1, cfg("military.raid_min")), 1, min(lv_raids, targets.length / 2))
    let sorted = copy(ids)
    sort_ints(sorted)
    for(groups) g:
        let part = filter(sorted.length) n: n % groups == g
        issue_cmd(bot.player, 1, map(part) n: sorted[n], targets[g * 2], targets[g * 2 + 1], 0, 0)
    return true

def defenders(bot:Bot, b:int) -> int:
    let x = b_cx[b] * 1000 + b_sx[b] * 500
    let y = b_cy[b] * 1000 + b_sy[b] * 500
    let r = cfg("military.defend_tiles") * 1000
    var n = 0
    for(u_x.length) i:
        let k = u_kind[i]
        if is_foe(bot.player, u_owner[i]) and not t_worker[k] and t_animal[k] == 0 and not t_healer[k] and not t_trader[k] and fog_visible(bot.player, u_x[i], u_y[i]) and dist2(x, y, u_x[i], u_y[i]) < r * r: n++
    return n

def send_wave(bot:Bot, ids:[int], tx0:int, ty0:int, may_raid:bool, hx:int, hy:int):
    let idx = map(ids) id: index_of(id)
    let strong = dominant(bot, idx)
    if lv_raids > 0 and tick >= lv_raid_from and may_raid and not strong and raid(bot, ids, hx, hy): return
    var tx = tx0
    var ty = ty0
    let cx, cy = contain_point(bot, tx, ty)
    if may_raid and cx >= 0 and pop_of(idx) < cfg("military.contain_pop") and not has_siege(idx):
        tx = cx
        ty = cy
    var main = ids
    if bot.land.flank_x >= 0 and ids.length >= cfg("land.flank_min"):
        let n = ids.length * cfg("land.flank_share") / 100
        let flankers = slice(ids, ids.length - n, n)
        main = slice(ids, 0, ids.length - n)
        via(bot, flankers, bot.land.flank_x, bot.land.flank_y, tx, ty)
    via(bot, main, bot.land.detour_x, bot.land.detour_y, tx, ty)

// Whether we know of this enemy Wonder: seen, or finished (everyone hears of that).
def knows_wonder(bot:Bot, b:int) -> bool:
    return contains(wonder_ids, b_id[b]) or fog[bot.player][b_cy[b] * W + b_cx[b]] != UNSEEN

// The id of the nearest enemy Wonder we know of and can get to, finished ones first, or 0.
def known_enemy_wonder(bot:Bot, hx:int, hy:int) -> int:
    var best = 0
    var best_key = 1 << 62
    for(b_id.length) b:
        if has_role(b_kind[b], ROLE_WONDER) and is_enemy(bot.player, b_owner[b]) and knows_wonder(bot, b) and reaches_building(bot.eco.reach, bot.aln, bot.harea, b):
            let key = dist2(hx, hy, b_cx[b] * 1000, b_cy[b] * 1000) / 1000 + (if b_done[b] == 1: 0 else: 1 << 40)
            if key < best_key:
                best_key = key
                best = b_id[b]
    return best

// A Wonder when we're rich: from the age in data, with none of ours up or going up, once every
// stock is spare_pct percent of its cost; laid by the Town Center (Bot._wonder).
def bot_wonder(bot:Bot, tc:int, workers:[int]):
    let p = bot.player
    let k = btype_with(ROLE_WONDER)
    if not has_cfg("wonder.age") or k < 0 or ages[p] < cfg("wonder.age") or tick < bot.next_build: return
    for(b_id.length) b:
        if b_owner[b] == p and b_kind[b] == k: return
    let cost = bm_cost[p][k]
    for(cost) c, r:
        if stock[r][p] < c * cfg("wonder.spare_pct") / 100: return
    let sx, sy = house_spot(bot.eco, b_cx[tc] + 1, b_cy[tc] + 1, bt_size[k])
    if sx < 0 or not workers.length: return
    let builders = map(slice(workers, 0, min(cfg("wonder.builders"), workers.length))) i: u_id[i]
    issue_cmd(p, CMD_BUILD, builders, k, sx, sy, 0)
    bot.next_build = tick + BUILD_COOLDOWN

def waves(bot:Bot, army:[int], count:int, hx:int, hy:int):
    let wonder = known_enemy_wonder(bot, hx, hy)
    let tx = bot.target_x
    let ty = bot.target_y
    if tx < 0: return
    let need = if bot.pressing: press_army(bot, count) elif bot.wave < wave_at.length: wave_min[bot.wave] else: repeat_min(bot)
    var strength = 0
    for(army) i: strength += t_pop[u_kind[i]]
    // A finished enemy Wonder can't wait for the next wave: everyone goes now (again every regroup).
    let urgent = wonder > 0 and contains(wonder_ids, wonder) and tick - bot.rushed >= cfg("military.regroup_every") * 20 and strength > 0
    if urgent: bot.rushed = tick
    let waited = bot.mass_from >= 0 and tick - bot.mass_from >= cfg("military.press.wait") * 20 and strength >= repeat_min(bot)
    let massed = bot.pressing and not bot.pushing and (strength >= need or waited)
    if (tick >= bot.next_wave_tick and strength >= need and not bot.pressing) or massed or urgent:
        let near = cfg("military.defend_tiles") * 2000
        let away = filter(army) i: dist2(hx, hy, u_x[i], u_y[i]) > near * near
        let at_home = filter(army) i: dist2(hx, hy, u_x[i], u_y[i]) <= near * near
        var keep = army.length - max(1, army.length * lv_wave_pct / 100)
        if (lv_all_in > 0 and strength >= lv_all_in) or bot.pressing: keep = 0
        let sent = append(away, slice(at_home, 0, max(0, at_home.length - keep)))
        if sent.length: send_wave(bot, map(sent) i: u_id[i], tx, ty, wonder <= 0 and not bot.pressing, hx, hy)
        bot.assault = true
        bot.pushing = bot.pressing
        bot.wave++
        bot.next_wave_tick = if bot.wave < wave_at.length: wave_at[bot.wave] * 20 else: tick + cfg("military.repeat_every") * 20
        return
    if not bot.assault or tick % (cfg("military.regroup_every") * 20) != bot_phase(bot): return
    let home_r = cfg("military.defend_tiles") * 1000
    let ids = []::int
    let home = filter(army) i: u_foe[i] == 0 and u_moving[i] == 0 and dist2(hx, hy, u_x[i], u_y[i]) <= 4 * home_r * home_r
    if (home.length >= max(REINFORCE, need / 2) and lv_wave_pct >= 100) or (bot.pushing and home.length >= REINFORCE):
        for(home) i: ids.push(u_id[i])
    for(army) i:
        let on_building = u_foe[i] != 0 and b_index_of(u_foe[i]) >= 0
        let free = (u_foe[i] == 0 and u_moving[i] == 0) or on_building
        if free and dist2(hx, hy, u_x[i], u_y[i]) > 4 * home_r * home_r: ids.push(u_id[i])
    if not ids.length: return
    var out_pop = 0
    for(army) i:
        if dist2(hx, hy, u_x[i], u_y[i]) > 4 * home_r * home_r: out_pop += t_pop[u_kind[i]]
    // Pushing: home once the army is down to back_pct of what it massed; massing: all home.
    let left = if bot.pushing: strength else: out_pop
    let back_pct = if bot.pushing: cfg("military.press.back_pct") elif bot.pressing: 101 else: 50
    if left * 100 < need * back_pct and wonder <= 0:
        bot.pushing = false
        let back = filter(ids) id:
            let i = index_of(id)
            dist2(hx, hy, u_x[i], u_y[i]) > 4 * home_r * home_r
        if back.length: issue_cmd(bot.player, 1, back, hx, hy, 0, 0)
        return
    let strong = dominant(bot, army) or bot.pressing
    if lv_raids > 0 and tick >= lv_raid_from and wonder <= 0 and not strong and raid(bot, ids, hx, hy): return
    let cx, cy = contain_point(bot, tx, ty)
    if wonder <= 0 and cx >= 0 and pop_of(army) < cfg("military.contain_pop") and not has_siege(army) and not bot.pressing:
        issue_cmd(bot.player, 1, ids, cx, cy, 0, 0)
        return
    var tc_id = if wonder > 0: wonder else: known_enemy_town(bot, hx, hy)  // (a Wonder first)
    if tc_id <= 0: tc_id = bot.aim
    if tc_id <= 0:
        issue_cmd(bot.player, 1, ids, tx, ty, 0, 0)
        return
    if strong:
        for(army) i:
            let id = u_id[i]
            if not contains(ids, id) and index_of(u_foe[i]) < 0 and dist2(hx, hy, u_x[i], u_y[i]) > 4 * home_r * home_r: ids.push(id)
    let fighters = min(ids.length, 2 * defenders(bot, b_index_of(tc_id)))
    if fighters > 0: issue_cmd(bot.player, 1, slice(ids, 0, fighters), tx, ty, 0, 0)
    if fighters < ids.length: issue_cmd(bot.player, 13, slice(ids, fighters, ids.length - fighters), tc_id, 0, 0, 0)

// Soldiers out on an attack caught on an enemy wall piece: on the target at once (Bot._off_walls).
def off_walls_army(bot:Bot, army:[int], hx:int, hy:int):
    if not bot.assault: return
    var to = known_enemy_town(bot, hx, hy)
    if to <= 0: to = bot.aim
    if to <= 0: return
    let ids = []::int
    for(army) i:
        let k = u_kind[i]
        if not t_buildings_only[k] and t_splash[k] == 0:
            let b = b_index_of(u_foe[i])
            if b >= 0 and u_foe[i] != to and (bt_wall[b_kind[b]] or bt_gate[b_kind[b]]): ids.push(u_id[i])
    if ids.length: issue_cmd(bot.player, 13, ids, to, 0, 0, 0)

// ---- trade (Bot._trade, _trade_carts, _trade_pair, _second_market)

def saving_of(bot:Bot, r:int) -> int: return if r < bot.eco.goal.length: bot.eco.goal[r] else: 0

// Short of food or wood with gold piled up: buy it; with no gold to spare, sell the biggest pile.
def bot_trade(bot:Bot):
    let p = bot.player
    if not has_cfg("economy.trade.every") or tick < bot.next_trade or trade_lacked[p]: return
    var mk = -1
    for(b_id.length) b:
        if mk < 0 and b_owner[b] == p and b_done[b] == 1 and has_role(b_kind[b], ROLE_TRADE): mk = b
    if mk < 0: return
    bot.next_trade = tick + cfg("economy.trade.every") * 20
    let g = resource_index("gold")
    var low = -1
    for(staple_resources) r:
        if stock[r][p] < cfg("economy.trade.below") and (low < 0 or stock[r][p] < stock[low][p]): low = r
    if low >= 0 and stock[g][p] >= cfg("economy.trade.above") + saving_of(bot, g):
        issue_cmd(p, CMD_TRADE, []::int, b_id[mk], low, 1, 0)
        return
    if low < 0: return
    var most = -1
    for(num_resources) r:
        if r != g and stock[r][p] >= cfg("economy.trade.above") + saving_of(bot, r) and (most < 0 or stock[r][p] > stock[most][p]): most = r
    if most >= 0: issue_cmd(p, CMD_TRADE, []::int, b_id[mk], most, 0, 0)

// [our market, the far market]: the farthest pair our carts may trade between, or [].
def trade_pair(p:int) -> [int]:
    var best = []::int
    var best_d = -1
    for(b_id.length) a:
        if b_owner[a] == p and b_done[a] == 1 and has_role(b_kind[a], ROLE_TRADE):
            for(b_id.length) b:
                if b != a and b_done[b] == 1 and has_role(b_kind[b], ROLE_TRADE) and not route_barred(p, a, b):
                    let d = market_tiles(a, b)
                    if d > best_d:
                        best_d = d
                        best = [ a, b ]
    return best

// One market of ours, two Town Centers: a second market by the Town Center farthest from it.
def second_market(bot:Bot, workers:[int]):
    let p = bot.player
    let mk = btype_with(ROLE_TRADE)
    let ours = []::int
    for(b_id.length) b:
        if b_owner[b] == p and has_role(b_kind[b], ROLE_TRADE): ours.push(b)
    if ours.length != 1 or b_done[ours[0]] == 0 or tick < bot.next_build or not can_afford(p, bt_cost[mk]) or bot.saving_age: return
    var far = -1
    var far_d = r_trade_min + 4
    for(b_id.length) b:
        if b_owner[b] == p and b_done[b] == 1 and has_role(b_kind[b], ROLE_HUB):
            let d = market_tiles(ours[0], b)
            if d >= far_d:
                far = b
                far_d = d
    if far < 0: return
    let sx, sy = house_spot(bot.eco, b_cx[far] + 1, b_cy[far] + 1, bt_size[mk])
    if sx < 0: return
    let builders = nearest_workers(bot, workers, sx * 1000, sy * 1000, 2)
    if not builders.length: return
    issue_cmd(p, CMD_BUILD, builders, mk, sx, sy, 0)
    bot.next_build = tick + BUILD_COOLDOWN

def trade_carts(bot:Bot, carts:[int], workers:[int]):
    let p = bot.player
    if not has_cfg("economy.carts.age") or ages[p] < cfg("economy.carts.age") or tick % (cfg("economy.carts.every") * 20) != bot_phase(bot): return
    let k = type_named(p, "trader")
    if k < 0: return
    let pair = trade_pair(p)
    if not pair.length:
        if cfg_or("economy.carts.second_market", 0) == 1: second_market(bot, workers)
        return
    let idle = []::int
    for(carts) i:
        if u_task[i] != T_TRADE: idle.push(u_id[i])
    if idle.length: issue_cmd(p, CMD_ROUTE, idle, b_id[pair[1]], 0, 0, 0)
    let home = pair[0]
    if fielded(p, k) >= cfg("economy.carts.max") or b_queue[home].length or bot.saving_age or bot.threat_ids.length: return
    let reserve = map(num_resources) r: saving_of(bot, r)
    if affords(p, t_cost[k], reserve): issue_cmd(p, CMD_TRAIN, []::int, b_id[home], k, 1, 0)

// ---- pressing a lead (military.press)

// The enemy as we know it: its best age (ages are announced); its workers: those we've seen lately,
// or as many as the buildings we remember but walls, if more (a bot's town keeps about one a worker);
// the soldiers we remember (population).
def known_enemy(bot:Bot) -> int, int, int:
    let p = bot.player
    var age = 0
    for(num_players) q:
        if is_enemy(p, q) and defeated[q] == 0: age = max(age, ages[q])
    var blds = 0
    for(fog_seen[p]) s:
        if is_enemy(p, s[2]) and not bt_wall[s[1]] and not bt_gate[s[1]]: blds++
    var theirs = 0
    for(bot.scout.seen_kind) k: theirs += t_pop[k]
    return age, max(bot.scout.worker_ids.length, blds), theirs

// Clearly ahead: an age up on the enemy or workers_pct of its workers, and army_pct of its army.
// Pressing goes on while the economy stays ahead, at least stay_pct of its workers in no lower age.
def press_think(bot:Bot, count:int, army:[int]):
    let p = bot.player
    if not has_cfg("military.press.from") or tick < cfg("military.press.from") * 20 or count < cfg("military.press.workers"):
        bot.pressing = false
        bot.pushing = false
        bot.mass_from = -1
        bot.eco.headroom = HOUSE_HEADROOM
        return
    let age, workers, theirs = known_enemy(bot)
    let up = ages[p] > age
    if bot.pressing:
        bot.pressing = ages[p] >= age and (up or count * 100 >= workers * cfg("military.press.stay_pct"))
    else:
        bot.pressing = ages[p] >= age and (up or count * 100 >= workers * cfg("military.press.workers_pct")) and
            pop_of(army) * 100 >= theirs * cfg("military.press.army_pct")
    if not bot.pressing: bot.pushing = false
    bot.mass_from = if not bot.pressing or bot.pushing: -1 elif bot.mass_from < 0: tick else: bot.mass_from
    bot.eco.headroom = if bot.pressing: cfg("military.press.headroom") else: HOUSE_HEADROOM

// While massing it saves for the soldiers it lacks, at the prices of those it fields (spears with none),
// and the hero it waits to train.
def mass_goal(bot:Bot, army:[int], short:int) -> [int]:
    let goal = map(num_resources): 0
    var per = pop_of(army)
    for(army) i:
        for(t_cost[u_kind[i]]) c, r: goal[r] += c
    let spear = type_named(bot.player, "spear")
    if not army.length and spear >= 0:
        for(t_cost[spear]) c, r: goal[r] = c
        per = t_pop[spear]
    return map(goal) g, r: g * short / max(1, per) + (if r < bot.hero_want.length: bot.hero_want[r] else: 0)

// The army it masses before it goes: `army`, or over_pct of the enemy army it remembers, within what
// the level keeps (army_ratio, less a tenth).
def press_army(bot:Bot, count:int) -> int:
    let p = bot.player
    let _age, _workers, theirs = known_enemy(bot)
    var n = max(cfg("military.press.army"), theirs * cfg("military.press.over_pct") / 100)
    if lv_army_ratio > 0: n = min(n, count * lv_army_ratio * ages[p] * 9 / 1000)
    return max(n, repeat_min(bot))

// ---- think

def full_bot_think(bot:Bot):
    let p = bot.player
    if defeated[p] != 0 or winner >= 0: return
    note_hits(bot)
    forget_dead(bot.scout)
    bot.eco.max_workers = per_age("economy.max_workers", ages[p], 0)
    bot_think(bot.eco)
    if tick % BOT_THINK_EVERY != bot_phase(bot): return
    let tc = town_center(p)
    if tc < 0:
        besiege(bot)  // no town (the Siege mode's attackers): all on the attack
        return
    let workers = []::int
    let army = []::int
    let healers = []::int
    let carts = []::int
    var scouts = 0
    for(u_x.length) i:
        if u_owner[i] == p:
            let k = u_kind[i]
            if t_worker[k]: workers.push(i)
            elif t_healer[k]: healers.push(i)
            elif t_trader[k]: carts.push(i)
            elif t_animal[k] != 0: pass()  // (our sheep aren't soldiers)
            else:
                army.push(i)
                if t_slot[k] == "scout": scouts++
    let count = workers.length + sheltered(p)
    army_floor(bot, army, count)
    build_order_step(bot, tc, workers, count)
    bot.eco.goal = goal_of(bot, count)
    bot.eco.push = if bot.saving_age: 100 elif bot.blocked.length: bot.blocked_push else: cfg_or("economy.build_push", 30)
    let short = if bot.pressing and not bot.pushing: press_army(bot, count) - pop_of(army) else: 0  // (massing)
    if short > 0:
        bot.saving_age = false
        bot.eco.goal = mass_goal(bot, army, short)
        bot.eco.push = cfg("military.press.push")
    age_three(bot, tc, count)
    bot_wonder(bot, tc, workers)
    upgrade_lines(bot, army)
    train_scout(bot, scouts)
    train_soldiers(bot, workers, count)
    train_healers(bot, tc, army, healers)
    let hx = b_cx[tc] * 1000 + 1500
    let hy = b_cy[tc] * 1000 + 1500
    let spear = type_named(p, "spear")
    bot.aln = if army.length: lane(army[0]) elif spear >= 0: lane_base[p] + t_mclass[spear] else: lane_base[p]
    bot.harea = area_at(bot.eco.reach, bot.aln, hx, hy)
    heroes_think(bot, tc, army, hx, hy)
    let field = filter(army) i: u_id[i] != bot.scout.id and not is_escort(bot.expand, u_id[i]) and not land_breaking(bot.land, i) and not contains(bot.resting, u_id[i])
    let at_work = filter(workers) i: u_id[i] != bot.scout.id
    remember_soldiers(bot.scout, p)
    bot.on_back_foot = bot.on_back_foot or defending(bot, field)
    press_think(bot, count, field)
    scout_think(bot.scout, bot, at_work, field, hx, hy)
    bot.target_x, bot.target_y = wave_target(bot, hx, hy)
    bot.land.target_x = bot.target_x
    bot.land.target_y = bot.target_y
    land_think(bot.land, bot, at_work, field, hx, hy)
    expand_think(bot.expand, bot, at_work, field, hx, hy)
    defend(bot, field, hx, hy)
    man_walls(bot, field, hx, hy)
    // (WallsAi.man: no walls you stand on here)
    respond(bot, tc, filter(army) i: u_id[i] != bot.scout.id and not contains(bot.resting, u_id[i]), at_work, hx, hy)
    tower_after_raid(bot, at_work)
    bot_trade(bot)
    trade_carts(bot, carts, at_work)
    waves(bot, field, count, hx, hy)
    off_walls_army(bot, field, hx, hy)
    bot_siege(bot, field, hx, hy)
    storm_walls(bot, field, bot.target_x, bot.target_y)
    ability_think(p, army)  // the race's ability (spiders' webs)
    escort_healers(bot, field, healers, hx, hy)
