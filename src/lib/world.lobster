// ------------------------------------------------------------------ the world (World.step, the scenario file)
// The tick in the order World.step runs the systems, the command stream (issue, take), the state
// hash export.gd checks, and the scenario loader. Imported last: it uses every module.

// ------------------------------------------------------------------ the tick

var scenario_mode = ""
var cmds = []::Cmd  // recorded orders, in run order (replaying a scenario's)
var next_cmd = 0
var pending = []::Cmd   // orders the bots issued, waiting for their turn (bots mode)
var next_seq = []::int  // per player

// Issue an order this turn: it runs at the start of turn + 2, after the turn's earlier orders,
// by (player, seq) (Commands.issue and take).
def issue_cmd(p:int, code:int, ids:[int], a:int, b:int, c:int, d:int, queue:int = 0):
    let cmd = Cmd { (tick / TICKS_PER_TURN + 2) * TICKS_PER_TURN, code, p, a, b, c, d, ids, next_seq[p] }
    cmd.queue = queue
    pending.push(cmd)
    next_seq[p]++

// The pending orders that run now, in (player, seq) order (all were issued in one turn).
def take_pending() -> [Cmd]:
    let keys = []::int
    for(pending) c, k:
        if c.run_tick == tick: keys.push((c.player << 40) | (c.seq << 20) | k)
    sort_ints(keys)
    let out = map(keys) key: pending[key & ((1 << 20) - 1)]
    pending = filter(pending): _.run_tick != tick
    return out

// The scratch arrays grow with the units (training adds them).
def grow_scratch():
    let n = u_x.length
    for([ sp_items, sp_cell, slot_x, slot_y, slot_block, slot_bx, slot_by, f_ahead, f_side, s_pushx, s_pushy, s_planted,
          c_hurt, c_hurt_by, c_engaged, c_inbound ]) a:
        while a.length < n: a.push(0)

// World.step, for the systems ported: commands, training, jobs, combat, fog, map changes,
// flow-field solves, moves, separation.
def step():
    events.remove_range(0, events.length)  // (World.step: the last tick's events go)
    if tick % TICKS_PER_TURN == 0:
        while next_cmd < cmds.length and cmds[next_cmd].run_tick == tick:
            run(cmds[next_cmd])
            next_cmd++
        for(take_pending()) c: run(c)
    train()
    grow_scratch()
    tech_tick()
    work()
    trade_tick()
    pack_tick()
    repair_tick()
    garrison_tick()
    walls_tick()
    animals_tick()
    grow_scratch()  // (a lamb born in a pen)
    spatial_build()
    let alive = unit_changes
    heal_tick()
    combat_tick()
    hero_tick()
    if hook_tick_types.length:
        for(u_kind) k, i:
            if contains(hook_tick_types, k): hook_unit_tick(i)
    match_tick()
    fog_tick()
    trails_tick()
    abilities_tick()
    if unit_changes != alive: spatial_build()
    next_orders()
    trace("start")
    sync_map()
    solve_queued()
    move()
    trace("move")
    spatial_build()
    separate()
    trace("separate")
    tick++

var trace_tick = -1

def unit_line(i:int) -> string:
    var s = ""
    for(unit_columns()) col, k:
        if k < UNIT_HASHED:
            if k: s += " "
            s += string(col[i])
    return s

// Every unit's fields at the start of the tick's moves, after them and after separation (export.gd's trace:<tick>).
def trace(what:string):
    if tick != trace_tick: return
    for(u_x.length) i: print "{what} {unit_line(i)}"

// export.gd's state_hash.
def state_hash() -> int:
    var h = FNV_START
    h = mix(h, tick)
    h = mix(h, next_id)
    h = mix(h, next_group)
    for(field_keys) k: h = mix(h, k)
    for(hook_unit_cols) col:
        for(col) v: h = mix(h, v)
    for(hook_player_cols) col:
        for(col) v: h = mix(h, v)
    h = mix(h, -1)
    for(field_queue) k: h = mix(h, k)
    let n = u_x.length
    h = mix(h, n)
    let cols = unit_columns()
    for(n) i:
        for(UNIT_HASHED) k: h = mix(h, cols[k][i])
        h = mix(h, u_orders[i].length)
        for(u_mount[i]) v: h = mix(h, v)
        for(u_orders[i]) o:
            for(order_ints(o)) v: h = mix(h, v)
    let bcols = building_columns()
    h = mix(h, b_id.length)
    for(b_id.length) b:
        for(bcols) col: h = mix(h, col[b])
        h = mix(h, b_queue[b].length)
        for(b_queue[b]) k: h = mix(h, k)
        h = mix(h, b_inside[b].length / REC_SIZE)
        for(b_inside[b]) v: h = mix(h, v)
    for(hero_types.length) hn: h = mix(mix(h, hero_id[hn]), hero_fell[hn])
    h = mix(h, winner)
    for(wonder_ids) id, k: h = mix(mix(h, id), wonder_since[k])
    for(market_price) v: h = mix(h, v)
    h = walls_hash(h)
    for(br_id) id, k:
        for([ id, br_hp[k], br_up[k], br_work[k], br_payer[k] ]) v: h = mix(h, v)
    h = abilities_hash(h)
    h = wear_hash(h)
    h = mix(h, shots.length / SHOT_STRIDE)
    for(shots) v: h = mix(h, v)
    for(num_players) p:
        h = mix(h, lost[p])
        h = mix(h, pop[p])
        h = mix(h, pop_cap[p])
        h = mix(h, ages[p])
        h = mix(h, defeated[p])
        h = mix(h, auto_reseed[p])
        for(researched[p]) v: h = mix(h, v)
        for(num_resources) r:
            h = mix(h, stock[r][p])
            h = mix(h, gathered[r][p])
    for(resource_cells) c:
        h = mix(h, amount[c])
        h = mix(h, terrain[c])
    return h

def dump_state() -> string:
    var s = "tick {tick} next_id {next_id} next_group {next_group} fields {field_keys} queue {field_queue} shots {shots} lost {lost} stock {stock} gathered {gathered} pop {pop} cap {pop_cap}\n"
    s += "pour " + concat_string(map(pour_ids) id: "{id}:{pour_at.get(id, 0)}", " ") + "\n"
    for(u_x.length) i: s += unit_line(i) + "\n"
    for(b_id.length) b:
        s += "b"
        for(building_columns()) col: s += " {col[b]}"
        s += " q {b_queue[b]}\n"
    for(t_hp.length) k:
        let v = [ t_hp[k], t_speed[k], t_reach[k], t_reload[k], t_pop[k], t_train_ticks[k], t_carry_add[k], t_build_pct[k], t_shot_speed[k],
                  t_ranged[k], t_sight_add[k] ]
        for([ t_cost[k], t_atk[k], t_arm[k] ]) xs:
            for(xs) x: v.push(x)
        var line = "type {k}"
        for(v) x: line += " {x}"
        s += line + "\n"
    return s

// ------------------------------------------------------------------ the scenario file

def load(path:string):
    let text = assert read_file(path)
    tokens = filter(tokenize(text, " \n", "")): _.length > 0
    expect("AOWSPIKE")
    assert next_int() == 3
    expect("MODE")
    scenario_mode = next_tok()
    expect("MAP")
    W = next_int()
    H = next_int()
    let lanes = next_int()
    has_heights = next_int()
    for(lanes): walks.push(read_ints(W * H))
    terrain = read_ints(W * H)
    amount = read_ints(W * H)
    pool = read_ints(W * H)
    occupied = read_ints(W * H)
    walk_over = read_ints(W * H)
    cliff = read_ints(W * H)
    ramp = read_ints(W * H)
    level = read_ints(W * H)
    deck = read_ints(W * H)
    high = read_ints(W * H)
    opaque = read_ints(W * H)
    gate = read_ints(W * H)
    resource_cells = read_ints(next_int())
    expect("TERRAIN")
    for(next_int()):
        tr_walk.push(next_int())
        tr_move.push(next_int())
        tr_res.push(next_int())
        tr_amount.push(next_int())
        tr_depleted.push(next_int())
        tr_reseed.push(next_int())
        tr_cleared.push(next_int())
        tr_opaque.push(next_int())
    expect("SPEED")
    for(next_int()): speed_pct.push(read_ints(W * H))
    expect("PLAYERS")
    num_players = next_int()
    num_resources = next_int()
    lane_base = read_ints(num_players)
    teams = read_ints(num_players)
    gather_spots = read_ints(num_resources)
    for(num_resources): resource_names.push(next_tok())
    for(tr_walk.length): tr_names.push(next_tok())
    for(next_int()):
        start_x.push(next_int())
        start_y.push(next_int())
    for(next_int()): slot_names.push(next_tok())
    for(num_players):
        trade_lacked.push(next_int())
        slots_lacked.push(read_ints(next_int()))
    expect("RULES")
    r_min_damage = next_int()
    r_acquire_every = next_int()
    r_defend_sight = next_int()
    r_counter_pull = next_int()
    r_leash = next_int()
    r_sight = next_int()
    r_shot_lead_pct = next_int()
    r_shot_strays = next_int()
    r_shot_slack = next_int()
    r_high_reach = next_int()
    r_uphill_pct = next_int()
    r_high_sight_unit = next_int()
    r_high_sight_building = next_int()
    r_fog_every = next_int()
    r_fog_unit = next_int()
    r_fog_worker = next_int()
    r_fog_building = next_int()
    r_carry = next_int()
    r_queue_max = next_int()
    r_pop_max = next_int()
    r_fog_tower = next_int()
    r_garrison_heal_every = next_int()
    r_call_range = next_int()
    garrison_not = read_ints(next_int())
    r_heal_amount = next_int()
    r_heal_reload = next_int()
    r_heal_range = next_int()
    r_heal_sight = next_int()
    heal_not = read_ints(next_int())
    expect("TYPES")
    let nt = next_int()
    num_classes = next_int()
    for(nt):
        let v = read_ints(22)
        for([ t_speed, t_radius, t_role, t_gap, t_worker, t_harmless, t_healer, t_ranged, t_reach, t_reload, t_shot_speed,
              t_min_damage, t_sight, t_mclass, t_pop, t_train_ticks, t_hp, t_posture, t_carry_add, t_build_pct, t_player, t_age ]) col, k:
            col.push(v[k])
        t_slot.push(next_tok())
        t_trader.push(next_int())
        t_cost.push(read_ints(num_resources))
        t_atk.push(read_ints(num_classes))
        t_arm.push(read_ints(num_classes))
        t_cls.push(read_ints(num_classes))
        t_counters.push(read_ints(next_int()))
    expect("BTYPES")
    let nb = next_int()
    for(num_players):
        bm_hp.push([]::int)
        bm_pop.push([]::int)
        bm_sight.push([]::int)
        bm_food.push([]::int)
        bm_lacks.push([]::int)
        bm_trains.push([]::[int])
        bm_cost.push([]::[int])
    for(nb):
        let v = read_ints(14)
        for([ bt_size, bt_build_ticks, bt_pop, bt_sight, bt_age, bt_more_from_age, bt_water, bt_line, bt_tower, bt_farm, bt_land,
              bt_wet, bt_workers, bt_special ]) col, k:
            col.push(v[k])
        bt_name.push(tokens[tp])
        tp++
        let a = read_ints(10)
        for([ bt_attacks, bt_atk_class, bt_atk, bt_range, bt_reload, bt_arrows, bt_garrison, bt_gate, bt_wall, bt_over_trees ]) col, n:
            col.push(a[n])
        bt_cost.push(read_ints(num_resources))
        bt_drop.push(read_ints(num_resources))
        bt_reseed.push(read_ints(num_resources))
        for(num_players) p:
            bm_hp[p].push(next_int())
            bm_pop[p].push(next_int())
            bm_sight[p].push(next_int())
            bm_food[p].push(next_int())
            bm_lacks[p].push(next_int())
            bm_trains[p].push(read_ints(next_int()))
            bm_cost[p].push(read_ints(num_resources))
    load_tech(nt)
    expect("ECON")
    for(num_resources):
        stock.push(map(num_players): 0)
        gathered.push(map(num_players): 0)
    for(num_players) p:
        ages.push(next_int())
        auto_reseed.push(next_int())
        pop.push(next_int())
        pop_cap.push(next_int())
        lost.push(next_int())
        let gt = []::int
        for(num_resources) r:
            stock[r][p] = next_int()
            gathered[r][p] = next_int()
            gt.push(next_int())
        gather_ticks.push(gt)
    expect("TICK")
    tick = next_int()
    next_id = next_int()
    next_group = next_int()
    expect("UNITS")
    let cols = unit_columns()
    for(next_int()):
        let f = read_ints(cols.length - 5)  // (a scenario has no marching blocks or velocities)
        for(cols) col, k: col.push(if k < f.length: f[k] else: 0)
        u_orders.push([]::Cmd)  // (no queued orders at the start: asserted)
        u_mount.push([]::int)
    expect("BUILDINGS")
    let bcols = building_columns()
    for(next_int()):
        let f = read_ints(bcols.length)
        for(bcols) col, k: col.push(f[k])
        b_queue.push(read_ints(next_int()))
        b_inside.push([]::int)  // (nobody sheltering at the start: asserted)
    expect("SHOTS")
    shots = read_ints(next_int() * SHOT_STRIDE)
    expect("FOG")
    for(num_players):
        fog.push(read_ints(W * H))
        fog_lit.push(read_ints(next_int()))
        fog_seen.push(map(next_int()): read_ints(11))
    fog_memory_setup()
    expect("EXTRA")
    for(next_int()):
        let name = next_tok()
        extras.set(name, read_ints(next_int()))
    load_extras()
    load_ai()
    expect("CMDS")
    for(next_int()):
        let v = read_ints(8)
        let c = Cmd { v[0], v[1], v[2], v[4], v[5], v[6], v[7], read_ints(next_int()), 0 }
        c.queue = v[3]
        cmds.push(c)

// The EXTRA section (export.gd _write_extra): named int lists, for the systems ported after the
// fixed sections.
def extra(name:string) -> [int]:
    let v = extras.get(name)
    assert v
    return v

def load_extras():
    let rp = extra("repair")
    r_repair_speed = rp[0]
    r_repair_cost = rp[1]
    let tr = extra("trade")
    r_trade_min = tr[0]
    r_trade_sq_div = tr[1]
    r_trade_lin_pct = tr[2]
    market_price = extra("market_price")
    t_no_heal = extra("t_no_heal")
    t_animal = extra("t_animal")
    let g = extra("gaia")
    gaia = num_players
    teams.push(-1)  // gaia: everyone's quarry, nobody's ally
    lane_base.push(g[0])
    lost.push(0)
    claim_tiles = g[1]
    t_behave = extra("t_behave")
    t_flee = extra("t_flee")
    t_food = extra("t_food")
    let bc = extra("bridge_cfg")  // hp, ticks, then cost per resource, armour per class
    br_full_hp = bc[0]
    br_ticks = bc[1]
    br_cost = bc.slice(2, num_resources)
    br_arm = bc.slice(2 + num_resources, -1)
    let bv = extra("bridges")  // per bridge: id x0 y0 x1 y1 hp up work payer, its cells
    var o = 0
    while o < bv.length:
        br_id.push(bv[o])
        br_x0.push(bv[o + 1])
        br_y0.push(bv[o + 2])
        br_x1.push(bv[o + 3])
        br_y1.push(bv[o + 4])
        br_hp.push(bv[o + 5])
        br_up.push(bv[o + 6])
        br_work.push(bv[o + 7])
        br_payer.push(bv[o + 8])
        let n = bv[o + 9]
        br_cells.push(bv.slice(o + 10, n))
        o += 10 + n
    r_splash_friend_pct = extra("combat2")[0]
    let m2 = extra("match2")
    wonder_hold = m2[0]
    mode_hold = m2[1]
    let wd = extra("wonders")
    let nw = wd.length / 3
    wonder_ids = wd.slice(0, nw)
    wonder_since = wd.slice(nw, nw)
    wonder_owners = wd.slice(nw * 2, nw)
    let bw = extra("bt_walls")  // per building type: length stairs ladder walkway blocks_flyers, its replaces, its pour
    var o2 = 0
    while o2 < bw.length:
        bt_length.push(bw[o2])
        bt_stairs.push(bw[o2 + 1])
        bt_ladder.push(bw[o2 + 2])
        bt_walkway.push(bw[o2 + 3])
        bt_blocks_flyers.push(bw[o2 + 4])
        let nr = bw[o2 + 5]
        bt_replaces.push(bw.slice(o2 + 6, nr))
        o2 += 6 + nr
        bt_pour.push(if bw[o2] >= 0: bw.slice(o2, 3) else: []::int)
        o2 += 3
    let wc = extra("walk_cfg")
    walk_climb = wc[0]
    walk_fall = wc[1]
    walk_speed_pct = wc[2]
    walk_push = wc[3]
    rubble_terrain = wc[4]
    rubble_repair_pct = wc[5]
    walk_not = wc.slice(7, wc[6])
    rubble_from = wc.slice(8 + wc[6], wc[7 + wc[6]])
    lane_teams = extra("lanes")
    let rb = extra("rubble")
    var o3 = 0
    while o3 < rb.length:
        rubble.set(rb[o3], rb.slice(o3 + 1, 6))
        rubble_cells.push(rb[o3])
        o3 += 7
    t_docks = extra("t_docks")
    let pa = extra("pour_at")
    var o4 = 0
    while o4 < pa.length:
        pour_at.set(pa[o4], pa[o4 + 1])
        pour_ids.push(pa[o4])
        o4 += 2
    let ab = extra("abilities")  // per player: kind range radius lasts slow_pct cooldown
    for(num_players) p:
        ab_kind.push(ab[p * 6])
        ab_range.push(ab[p * 6 + 1])
        ab_radius.push(ab[p * 6 + 2])
        ab_lasts.push(ab[p * 6 + 3])
        ab_slow.push(ab[p * 6 + 4])
        ab_cooldown.push(ab[p * 6 + 5])
    t_ability = extra("t_ability")
    webs = extra("webs")
    let ar = extra("ability_ready")
    for(ar.length / 2) k: ids_set(ready_ids, ready_at, ar[k * 2], ar[k * 2 + 1])
    let sl = extra("slowed")
    for(sl.length / 2) k: ids_set(slowed_ids, slowed_until, sl[k * 2], sl[k * 2 + 1])
    let tc = extra("trails")  // every add max decay_every decay trail speed_pct, then the wear per cell
    tr_every = tc[0]
    tr_add = tc[1]
    tr_max = tc[2]
    tr_decay_every = tc[3]
    tr_decay = tc[4]
    tr_trail = tc[5]
    tr_speed_pct = tc[6]
    wear = tc.slice(7, -1)
    let pens = extra("bt_pen")
    for(pens.length / 4) k:
        bt_pen_animals.push(pens[k * 4])
        bt_pen_food.push(pens[k * 4 + 1])
        bt_pen_food_ticks.push(pens[k * 4 + 2])
        bt_pen_breed_ticks.push(pens[k * 4 + 3])

def read_effect() -> Effect:
    let kind = next_int()
    let stat = next_int()
    let value = next_int()
    let tag = next_int()
    let ands = read_ints(next_int())
    let nots = read_ints(next_int())
    let blds = read_ints(next_int())
    return Effect { kind, stat, value, tag, ands, nots, blds }

def read_effects() -> [Effect]:
    return map(next_int()): read_effect()

// The TECH section (export.gd _write_tech): ages, research, race effects, buildings' base numbers,
// every unit type's line, and what each player has.
def load_tech(nt:int):
    expect("TECH")
    let na = next_int()
    let nr = next_int()
    r_melee_reach = next_int()
    r_melee_reload = next_int()
    r_ranged_reload = next_int()
    r_shot_speed = next_int()
    class_machine = next_int()
    class_mounted = next_int()
    shot_speeds = read_ints(num_classes)
    base_gather_ticks = read_ints(num_resources)
    for(na):
        let age = next_int()
        let building = next_int()
        let ticks = next_int()
        let cost = read_ints(num_resources)
        let needs = map(num_players): read_ints(next_int())
        ages_list.push(Age { age, building, ticks, cost, needs })
    for(nr):
        let id = tokens[tp]
        tp++
        let building = next_int()
        let ticks = next_int()
        let age = next_int()
        let after = next_int()
        let line_age = next_int()
        let cost = read_ints(num_resources)
        let open = []::int
        let line_has = []::int
        let before = []::int
        for(num_players):
            open.push(next_int())
            line_has.push(next_int())
            before.push(next_int())
        research.push(Research { id, building, ticks, age, after, line_age, cost, open, line_has, before, read_effects() })
    for(num_players): race_fx.push(read_effects())
    for(bt_size.length):
        bt_hp_base.push(next_int())
        bt_food_base.push(next_int())
        bt_arm.push(read_ints(num_classes))
    for(nt):
        t_hero.push(next_int())
        let steps = []::LineStep
        for(next_int()):
            let age = next_int()
            let up = next_int()
            let speed = next_int()
            let hp = next_int()
            let pop_ = next_int()
            let train_time = next_int()
            let cost = read_ints(num_resources)
            let damage = next_int()
            let attack = next_int()
            let bonus = read_ints(num_classes)
            let armour = read_ints(num_classes)
            let tags = read_ints(next_int())
            let v = read_ints(12)
            steps.push(LineStep { age, up, speed, hp, pop_, train_time, cost, damage, attack, bonus, armour, tags,
                                  v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], []::Mount, 0, 0, v[10], v[11] })
        lines.push(steps)
    expect("RESEARCHED")
    for(num_players):
        next_int()  // (its age: in ECON)
        researched.push(read_ints(nr))
    for(num_players):
        bm_arm.push(map(bt_size.length): []::int)
        for([ bm_research_time, bm_age_time, bm_research_cost, bm_range, bm_cost_pct, bm_trade_fee ]) col: col.push(map(bt_size.length): 0)
    for([ t_heal_pct, t_kill_gold, t_wade, t_slow_on_hit, t_min_range, t_splash, t_pass_len, t_buildings_only, t_unpack, t_pack,
          t_blast, t_blast_line, t_air, t_hits_air, t_eval_sight, t_sight_add, t_machine, t_mounted, t_damage, t_heal ]) col:
        for(nt): col.push(0)
    for(nt):
        t_tags.push([]::int)
        t_mounts.push([]::Mount)
        t_bonus.push([]::int)
        t_eval_attack.push(0)
    expect("HEROES")
    let nh = next_int()
    r_aura = next_int()
    r_regen = next_int()
    r_revive = next_int()
    r_revive_pct = next_int()
    for(nh):
        hero_types.push(next_int())
        hero_id.push(next_int())
        hero_fell.push(next_int())
        hero_fx.push(read_effects())
    expect("MATCH")
    winner = next_int()
    started_with_town = read_ints(num_players)
    defeated = read_ints(num_players)

def zeros(n:int) -> [int]: return map(n): 0

// Roomy and tight grids per lane (SimMap.roomy_grid), worked out at the start; refresh keeps them.
def make_room():
    room_cw = (W + ROOM_CHUNK - 1) / ROOM_CHUNK
    for(walks.length) k: add_room(k)

// Lane k's roomy and tight grids, from its walk grid as it stands (a lane made later: a gate's).
def add_room(k:int):
    let ch = (H + ROOM_CHUNK - 1) / ROOM_CHUNK
    let g = walks[k]
    let room = zeros(W * H)
    let tg = zeros(room_cw * ch)
    for(W * H) c:
        let cx = c % W
        let cy = c / W
        var ok = cx > 0 and cy > 0 and cx < W - 1 and cy < H - 1
        if ok:
            for(3) dy:
                for(3) dx:
                    if g[(cy - 1 + dy) * W + cx - 1 + dx] == 0: ok = false
        room[c] = if ok: 1 else: 0
        if not ok: tg[(cy / ROOM_CHUNK) * room_cw + cx / ROOM_CHUNK]++
    roomy.push(room)
    tight.push(tg)

// Load a scenario file and set up what the sim works out at the start.
def start_world(path:string):
    load(path)
    let cells = W * H
    for(RING): ring.push([]::int)
    spatial_clear()
    fresh_at = zeros(cells)
    grow_scratch()
    make_room()
    make_chunks()
    for(num_players) p:  // the numbers research and bonuses give, worked out here as the sim does
        retype(p)
        tech_refresh(p)
    next_seq = map(num_players): 0
