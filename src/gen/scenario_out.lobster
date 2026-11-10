// ------------------------------------------------------------------ the scenario, written back (export.gd _write_state)
// The sim's arrays as the tokens of a scenario file (load reads them back), up to the commands.
// What setup_world makes can be compared with what export.gd writes for the same match.

var so_out = []::string

def so(s:string): so_out.push(s)
def soi(v:int): so_out.push(string(v))
def sov(vs:[int]):
    for(vs) v: so_out.push(string(v))
def sol(vs:[int]):  // a count, then the values
    soi(vs.length)
    sov(vs)

def so_effect(fx:Effect):
    sov([ fx.kind, fx.stat, fx.value, fx.tag ])
    sol(fx.ands)
    sol(fx.nots)
    sol(fx.blds)

def so_effects(fxs:[Effect]):
    soi(fxs.length)
    for(fxs) fx: so_effect(fx)

def scenario_tokens() -> [string]:
    so_out = []
    let np = num_players
    so("AOWSPIKE")
    soi(3)
    so("MODE")
    so(scenario_mode)
    so("MAP")
    sov([ W, H, walks.length, has_heights ])
    for(walks) g: sov(g)
    for([ terrain, amount, pool, occupied, walk_over, cliff, ramp, level, deck, high, opaque, gate ]) g: sov(g)
    sol(resource_cells)
    so("TERRAIN")
    soi(tr_walk.length)
    for(tr_walk.length) t: sov([ tr_walk[t], tr_move[t], tr_res[t], tr_amount[t], tr_depleted[t], tr_reseed[t], tr_cleared[t], tr_opaque[t] ])
    so("SPEED")
    soi(speed_pct.length)
    for(speed_pct) g: sov(g)
    so("PLAYERS")
    sov([ np, num_resources ])
    sov(lane_base.slice(0, np))
    sov(teams.slice(0, np))
    sov(gather_spots)
    for(resource_names) s: so(s)
    for(tr_names) s: so(s)
    soi(start_x.length)
    for(start_x) x, n: sov([ x, start_y[n] ])
    soi(slot_names.length)
    for(slot_names) s: so(s)
    for(np) p:
        soi(trade_lacked[p])
        sol(slots_lacked[p])
    so("RULES")
    sov([ r_min_damage, r_acquire_every, r_defend_sight, r_counter_pull, r_leash, r_sight, r_shot_lead_pct, r_shot_strays, r_shot_slack,
          r_high_reach, r_uphill_pct, r_high_sight_unit, r_high_sight_building, r_fog_every, r_fog_unit, r_fog_worker, r_fog_building,
          r_carry, r_queue_max, r_pop_max, r_fog_tower, r_garrison_heal_every, r_call_range ])
    sol(garrison_not)
    sov([ r_heal_amount, r_heal_reload, r_heal_range, r_heal_sight ])
    sol(heal_not)
    so("TYPES")
    sov([ t_slot.length, num_classes ])
    for(t_slot.length) k:
        sov([ t_speed[k], t_radius[k], t_role[k], t_gap[k], t_worker[k], t_harmless[k], t_healer[k], t_ranged[k], t_reach[k], t_reload[k],
              t_shot_speed[k], t_min_damage[k], t_sight[k], t_mclass[k], t_pop[k], t_train_ticks[k], t_hp[k], t_posture[k], t_carry_add[k],
              t_build_pct[k], t_player[k], t_age[k] ])
        so(t_slot[k])
        soi(t_trader[k])
        sov(t_cost[k])
        sov(t_atk[k])
        sov(t_arm[k])
        sov(t_cls[k])
        sol(t_counters[k])
    so("BTYPES")
    soi(bt_size.length)
    for(bt_size.length) k:
        sov([ bt_size[k], bt_build_ticks[k], bt_pop[k], bt_sight[k], bt_age[k], bt_more_from_age[k], bt_water[k], bt_line[k], bt_tower[k],
              bt_farm[k], bt_land[k], bt_wet[k], bt_workers[k], bt_special[k] ])
        so(bt_name[k])
        sov([ bt_attacks[k], bt_atk_class[k], bt_atk[k], bt_range[k], bt_reload[k], bt_arrows[k], bt_garrison[k], bt_gate[k], bt_wall[k], bt_over_trees[k] ])
        sov(bt_cost[k])
        sov(bt_drop[k])
        sov(bt_reseed[k])
        for(np) p:
            sov([ bm_hp[p][k], bm_pop[p][k], bm_sight[p][k], bm_food[p][k], bm_lacks[p][k] ])
            sol(bm_trains[p][k])
            sov(bm_cost[p][k])
    so("TECH")
    sov([ ages_list.length, research.length ])
    sov([ r_melee_reach, r_melee_reload, r_ranged_reload, r_shot_speed, class_machine, class_mounted ])
    sov(shot_speeds)
    sov(base_gather_ticks)
    for(ages_list) a:
        sov([ a.age, a.building, a.ticks ])
        sov(a.cost)
        for(np) p: sol(a.needs[p])
    for(research) r:
        so(r.id)
        sov([ r.building, r.ticks, r.age, r.after, r.line_age ])
        sov(r.cost)
        for(np) p: sov([ r.open[p], r.line_has[p], r.before[p] ])
        so_effects(r.effects)
    for(np) p: so_effects(race_fx[p])
    for(bt_size.length) k:
        sov([ bt_hp_base[k], bt_food_base[k] ])
        sov(bt_arm[k])
    for(lines) line, k:
        sov([ t_hero[k], line.length ])
        for(line) l:
            sov([ l.age, l.up, l.speed, l.hp, l.pop, l.train_time ])
            sov(l.cost)
            sov([ l.damage, l.attack ])
            sov(l.bonus)
            sov(l.armour)
            sol(l.tags)
            sov([ l.range, l.reload, l.min_range, l.splash, l.pass_len, l.buildings_only, l.unpack, l.pack, l.blast, l.blast_line, l.heal, l.sight ])
    so("RESEARCHED")
    for(np) p:
        soi(ages[p])
        sov(researched[p])
    so("HEROES")
    soi(hero_types.length)
    sov([ r_aura, r_regen, r_revive, r_revive_pct ])
    for(hero_types) k, n:
        sov([ k, hero_id[n], hero_fell[n], hero_fx[n].length ])
        for(hero_fx[n]) fx: so_effect(fx)
    so("MATCH")
    soi(winner)
    sov(started_with_town)
    sov(defeated.slice(0, np))
    so("ECON")
    for(np) p:
        sov([ ages[p], auto_reseed[p], pop[p], pop_cap[p], lost[p] ])
        for(num_resources) r: sov([ stock[r][p], gathered[r][p], gather_ticks[p][r] ])
    so("TICK")
    sov([ tick, next_id, next_group ])
    so("UNITS")
    soi(u_id.length)
    let cols = unit_columns().slice(0, unit_columns().length - 5)  // (a scenario has no marching blocks or velocities)
    for(u_id.length) i:
        for(cols) col: soi(col[i])
    so("BUILDINGS")
    soi(b_id.length)
    let bcols = building_columns()
    for(b_id.length) b:
        for(bcols) col: soi(col[b])
        sol(b_queue[b])
    so("SHOTS")
    soi(shots.length / SHOT_STRIDE)
    sov(shots)
    so("FOG")
    for(np) p:
        sov(fog[p])
        sol(fog_lit[p])
        soi(fog_seen[p].length)
        for(fog_seen[p]) s: sov(s)
    so("EXTRA")
    soi(27)
    so_extra("repair", [ r_repair_speed, r_repair_cost ])
    so_extra("trade", [ r_trade_min, r_trade_sq_div, r_trade_lin_pct ])
    so_extra("market_price", market_price)
    so_extra("t_no_heal", t_no_heal)
    so_extra("t_animal", t_animal)
    so_extra("gaia", [ lane_base[gaia], claim_tiles ])
    so_extra("t_behave", t_behave)
    so_extra("t_flee", t_flee)
    so_extra("t_food", t_food)
    let pens = []::int
    for(bt_size.length) k: for([ bt_pen_animals[k], bt_pen_food[k], bt_pen_food_ticks[k], bt_pen_breed_ticks[k] ]) v: pens.push(v)
    so_extra("bt_pen", pens)
    let bw = []::int
    for(bt_size.length) k:
        for([ bt_length[k], bt_stairs[k], bt_ladder[k], bt_walkway[k], bt_blocks_flyers[k], bt_replaces[k].length ]) v: bw.push(v)
        for(bt_replaces[k]) v: bw.push(v)
        for(if bt_pour[k].length: bt_pour[k] else: [ -1, 0, 0 ]) v: bw.push(v)
    so_extra("bt_walls", bw)
    let wc = [ walk_climb, walk_fall, walk_speed_pct, walk_push, rubble_terrain, rubble_repair_pct, walk_not.length ]
    for(walk_not) v: wc.push(v)
    wc.push(rubble_from.length)
    for(rubble_from) v: wc.push(v)
    so_extra("walk_cfg", wc)
    so_extra("lanes", lane_teams)
    let abv = []::int
    for(np) p: for([ ab_kind[p], ab_range[p], ab_radius[p], ab_lasts[p], ab_slow[p], ab_cooldown[p] ]) v: abv.push(v)
    so_extra("abilities", abv)
    so_extra("t_ability", t_ability)
    so_extra("webs", webs)
    let trc = [ tr_every, tr_add, tr_max, tr_decay_every, tr_decay, tr_trail, tr_speed_pct ]
    for(wear) v: trc.push(v)
    so_extra("trails", trc)
    let ar = []::int
    for(ready_ids) id, n: for([ id, ready_at[n] ]) v: ar.push(v)
    so_extra("ability_ready", ar)
    let sl = []::int
    for(slowed_ids) id, n: for([ id, slowed_until[n] ]) v: sl.push(v)
    so_extra("slowed", sl)
    so_extra("t_docks", t_docks)
    let pa = []::int
    for(sorted_ints(pour_ids)) id: for([ id, pour_at.get(id, 0) ]) v: pa.push(v)
    so_extra("pour_at", pa)
    let rb = []::int
    for(sorted_ints(rubble_cells)) c:
        rb.push(c)
        for(rubble.get(c) or []::int) v: rb.push(v)
    so_extra("rubble", rb)
    so_extra("combat2", [ r_splash_friend_pct ])
    so_extra("match2", [ wonder_hold, mode_hold ])
    let wd = copy(wonder_ids)
    for(wonder_since) v: wd.push(v)
    for(wonder_owners) v: wd.push(v)
    so_extra("wonders", wd)
    let bc = [ br_full_hp, br_ticks ]
    for(br_cost) v: bc.push(v)
    for(br_arm) v: bc.push(v)
    so_extra("bridge_cfg", bc)
    let brs = []::int
    for(br_id) id, k:
        for([ id, br_x0[k], br_y0[k], br_x1[k], br_y1[k], br_hp[k], br_up[k], br_work[k], br_payer[k], br_cells[k].length ]) v: brs.push(v)
        for(br_cells[k]) v: brs.push(v)
    so_extra("bridges", brs)
    return so_out

def so_extra(name:string, vs:[int]):
    so(name)
    sol(vs)

def sorted_ints(xs:[int]) -> [int]:
    let out = copy(xs)
    insertion_sort(out) a, b: a < b
    return out
