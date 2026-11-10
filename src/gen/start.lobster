// ------------------------------------------------------------------ the match start, put together (World._init's order)

def rules_part(name:string) -> JV: return gobj(su_rules, name)

def setup_world(seed_value:int, map_id:string, sides:[JV], rules:JV, team_ids:[int]):
    su_sides = sides
    su_rules = rules
    su_rng = new_rng(seed_value)
    scenario_mode = "match"
    next_id = 1
    next_group = 1
    tick = 0
    let np = sides.length
    num_players = np
    resource_names = []
    let rd = at(lib_data("resources.json"), "resources")
    for(rd.a) r:
        resource_names.push(rstr(r, "id"))
        let sp = get(r, "spots")
        gather_spots.push(if sp and sp.kind == J_STR and sp.s == "sides": 2 elif sp and sp.kind == J_BOOL and sp.i != 0: 1 else: 0)
    num_resources = resource_names.length
    staples_from_data()
    load_map(map_id)
    for(np) p: teams.push(if p < team_ids.length: team_ids[p] else: p)
    gaia = np
    teams.push(-1)
    for(np + 1): lane_base.push(0)
    for(np + 1): lost.push(0)
    let c = rules_part("combat")
    r_min_damage = as_int(at(c, "min_damage"))
    r_acquire_every = as_int(at(c, "acquire_every"))
    r_defend_sight = as_int(at(c, "defend_sight"))
    r_counter_pull = as_int(at(c, "counter_pull"))
    r_leash = as_int(at(c, "leash"))
    r_sight = as_int(at(c, "sight"))
    r_shot_lead_pct = as_int(at(c, "shot_lead_pct"))
    r_shot_strays = as_int(at(c, "shot_strays"))
    r_shot_slack = as_int(at(c, "shot_slack"))
    r_melee_reach = as_int(at(c, "melee_reach"))
    r_melee_reload = as_int(at(c, "melee_reload"))
    r_ranged_reload = as_int(at(c, "ranged_reload"))
    r_shot_speed = as_int(at(c, "shot_speed"))
    r_heal_amount = as_int(at(c, "heal_amount"))
    r_heal_reload = as_int(at(c, "heal_reload"))
    r_heal_range = as_int(at(c, "heal_range"))
    r_heal_sight = as_int(at(c, "heal_sight"))
    r_splash_friend_pct = gint(c, "splash_friend_pct", 100)
    let hg = rules_part("high_ground")
    r_high_reach = gint(hg, "reach", 1000)
    r_uphill_pct = gint(hg, "uphill_damage_pct", 75)
    r_high_sight_unit = gint(hg, "sight_unit", 1)
    r_high_sight_building = gint(hg, "sight_building", 2)
    let fc = rules_part("fog")
    r_fog_every = gint(fc, "every", 4)
    r_fog_unit = gint(fc, "unit", 6)
    r_fog_worker = gint(fc, "worker", 4)
    r_fog_building = gint(fc, "building", 4)
    r_fog_tower = gint(fc, "tower", 8)
    let ec = rules_part("economy")
    r_carry = as_int(at(ec, "carry"))
    r_queue_max = as_int(at(ec, "queue_max"))
    r_pop_max = as_int(at(ec, "pop_max"))
    let trc = at(ec, "trade")
    r_trade_min = as_int(at(trc, "min_tiles"))
    r_trade_sq_div = as_int(at(trc, "sq_div"))
    r_trade_lin_pct = as_int(at(trc, "lin_pct"))
    base_gather_ticks = map(resource_names) r: as_int(at(at(ec, "gather_ticks"), r))
    let ts = gobj(rules_part("movement"), "terrain_speed")
    for(CLASS_NAMES) cn:
        let row = map(tr_names) t: gint(gobj(ts, cn), t, 100)
        speed_row.push(row)
        speed_pct.push(map(W * H) cell: row[terrain[cell]])
    load_btypes()
    load_tech_data()
    for(sides) side, p:
        for(glist(side, "units")) u: add_type(p, u)
    add_animal_types(lib_data("animals.json"))
    setup_classes()
    num_classes = su_classes.length
    for(t_slot.length) k: type_vectors(k)
    setup_btypes()
    setup_identities()
    setup_tech()
    setup_rest()
    // what start_world works out once the arrays stand
    let cells = W * H
    for(RING): ring.push([]::int)
    sp_start = zeros(cells)
    sp_end = zeros(cells)
    sp_cursor = zeros(cells)
    fresh_at = zeros(cells)
    grow_scratch()
    make_room()
    make_chunks()
    for(np) p:
        retype(p)
        tech_refresh(p)
    setup_starts()
    mode_hold = -1
    setup_mode()  // (gen/modes.lobster: Fortress, Siege)
    if gbool(rules, "animals", false): place_animals()
    for(np) p:
        defeated.push(0)
        var towns = 0
        for(b_id.length) b:
            if b_owner[b] == p and has_role(b_kind[b], ROLE_HUB): towns++
        started_with_town.push(if towns > 0: 1 else: 0)
    setup_bridges()
    for(np):
        fog.push(zeros(cells))
        fog_lit.push([]::int)
        fog_seen.push([]::[int])
    fog_memory_setup()
    for(fog_teams()) team: fog_update_team(team)
    for(fresh) cell: fresh_at[cell] = 0
    fresh = []
    fresh_was = []
    load_ai_config()
    next_seq = map(np): 0
    hook_declare()

// The attack and armour classes (Combat.setup): the base three, then every other name sorted.
def setup_classes():
    let names = []::string
    for(su_units) u:
        for(glist(u, "line")) e:
            for(at(e, "armour").keys) k: push_new(names, k)
            for(at(e, "bonus").keys) k: push_new(names, k)
            for(unit_tags(e)) k: push_new(names, k)
    for(su_btypes) b:
        for(gobj(b, "armour").keys) k: push_new(names, k)
    su_classes = copy(BASE_CLASSES)
    for(sorted_strs(filter(names) n: not has_s(BASE_CLASSES, n))) n: su_classes.push(n)

// Every type's roles from buildings.json by its id: for a save from before roles (D-141, D-192) and
// a scenario file, which carry none.
def roles_from_data():
    if bt_roles.length == bt_name.length: return
    let d = at(lib_data("buildings.json"), "buildings")
    bt_roles = map(bt_name) id: role_bits(gstrs(at(d, id), "roles"))

def setup_btypes():
    let terrain_ids = tr_names
    for(su_btypes) b, k:
        let at_ = gobj(b, "attack")
        let size = as_int(at(b, "size"))
        let becomes = gobj(b, "becomes")
        let farm = becomes.keys.length > 0
        let arrows = gint(at_, "arrows", 1)
        let gate_ = gbool(b, "gate", false)
        let ladder = gbool(b, "ladder", false)
        let walkway = gint(b, "walkway", 0)
        let bflyers = gbool(b, "blocks_flyers", false)
        bt_size.push(size)
        bt_build_ticks.push(as_int(at(b, "build_time")) * 20)
        bt_pop.push(as_int(at(b, "pop")))
        bt_sight.push(gint(b, "sight", 0))
        bt_age.push(as_int(at(b, "age")))
        bt_more_from_age.push(gint(b, "more_from_age", 0))
        bt_water.push(if gbool(b, "water", false): 1 else: 0)
        bt_line.push(if gbool(b, "line", false): 1 else: 0)
        bt_tower.push(if at_.keys.length and arrows > 0: 1 else: 0)
        bt_farm.push(if farm: 1 else: 0)
        bt_land.push(if farm: str_index(terrain_ids, gstr(becomes, "land", "")) else: -1)
        bt_wet.push(if farm: str_index(terrain_ids, gstr(becomes, "water", "")) else: -1)
        bt_workers.push(gint(b, "workers", 0))
        bt_special.push(if gate_ or ladder or walkway > 0 or bflyers: 1 else: 0)
        bt_name.push(su_btype_ids[k])
        bt_roles.push(role_bits(gstrs(b, "roles")))
        bt_attacks.push(if at_.keys.length: 1 else: 0)
        bt_atk_class.push(class_index(gstr(at_, "damage", "pierce")))
        bt_atk.push(gint(at_, "attack", 0))
        bt_range.push(gint(at_, "range", 0))
        bt_reload.push(gint(at_, "reload", 0))
        bt_arrows.push(arrows)
        bt_garrison.push(gint(b, "garrison", 0))
        bt_gate.push(if gate_: 1 else: 0)
        bt_wall.push(if gbool(b, "line", false): 1 else: 0)
        bt_over_trees.push(0)  // (load_btypes keeps no sees_over_trees)
        bt_cost.push(cost_vec(at(b, "cost")))
        let drop_off = gstrs(b, "drop_off")
        bt_drop.push(map(resource_names) r: if has_s(drop_off, r): 1 else: 0)
        bt_reseed.push(cost_vec(gobj(b, "reseed")))
        bt_hp_base.push(as_int(at(b, "hp")))
        bt_food_base.push(gint(b, "food", 0))
        bt_arm.push(class_vec(gobj(b, "armour")))
        bt_length.push(gint(b, "length", size))
        bt_stairs.push(if gbool(b, "stairs", false): 1 else: 0)
        bt_ladder.push(if ladder: 1 else: 0)
        bt_walkway.push(walkway)
        bt_blocks_flyers.push(if bflyers: 1 else: 0)
        bt_replaces.push(filter(map(gstrs(b, "replaces")) id: btype_index(id)) k_: k_ >= 0)
        let pour = gobj(b, "pour")
        bt_pour.push(if pour.keys.length: [ gint(pour, "reach", 0), gint(pour, "reload", 0), gint(pour, "damage", 0) ] else: []::int)
        let pen = gobj(b, "pen")
        bt_pen_animals.push(if pen.keys.length: as_int(at(pen, "animals")) else: 0)
        bt_pen_food.push(if pen.keys.length: as_int(at(pen, "food")) else: 0)
        bt_pen_food_ticks.push(if pen.keys.length: as_int(at(pen, "food_every")) * 20 else: 1)
        bt_pen_breed_ticks.push(if pen.keys.length: as_int(at(pen, "breed_every")) * 20 else: 1)

// Each race's identity (Tech.setup): its effects for the sim, its allies' team bonuses too.
def setup_identities():
    let np = num_players
    let fxs = []::[JV]
    for(su_sides) side: fxs.push(copy(glist(side, "effects")))
    for(np) p:
        for(np) q:
            if q != p and teams[q] == teams[p]:
                for(glist(su_sides[q], "team_effects")) fx: fxs[p].push(fx)
    for(fxs) fx: race_fx.push(map(fx) x: encode_effect(x))
    su_fx = fxs
    slot_names = []
    for(t_slot) s: push_new(slot_names, s)
    for(np) p:
        trade_lacked.push(if ident_lacks(p, "trade"): 1 else: 0)
        slots_lacked.push(filter(map(slot_names.length) s: s) s: ident_lacks(p, slot_names[s]))

def setup_tech():
    let np = num_players
    class_machine = tag_or_none(rstr(rules_part("combat"), "band_machine"))
    class_mounted = tag_or_none(rstr(rules_part("combat"), "band_mounted"))
    shot_speeds = map(su_classes.length): 0
    let ssd = gobj(rules_part("combat"), "shot_speeds")
    for(ssd.keys) tag, n:
        let k = str_index(su_classes, tag)
        if k >= 0: shot_speeds[k] = as_int(ssd.a[n])
    for(su_ages) a:
        let needs = map(np) p: filter(map(requires_for(p, a)) id: btype_index(id)) k: k >= 0
        ages_list.push(Age { as_int(at(a, "age")), btype_index(rstr(a, "building")), as_int(at(a, "time")) * 20, cost_vec(at(a, "cost")), needs })
    for(su_research) item:
        let after = if rstr(item, "after") != "": research_index(rstr(item, "after")) else: -1
        let open = []::int
        let line_has = []::int
        let before = []::int
        for(np) p:
            let only = gstrs(item, "only")
            let o = (not only.length or gbool(su_rules, "full_tech_tree", false) or any_in(gstrs(su_sides[p], "owners"), only)) and
                not ident_lacks(p, rstr(item, "id"))
            open.push(if o: 1 else: 0)
            let lh = if has(item, "line"): line_has_kit(p, rstr(item, "line"), as_int(at(item, "line_age"))) else: true
            line_has.push(if lh: 1 else: 0)
            before.push(if has(item, "line"): line_before_of(p, item) else: -1)
        research.push(Research { rstr(item, "id"), btype_index(rstr(item, "building")), as_int(at(item, "time")) * 20, as_int(at(item, "age")),
                                 after, gint(item, "line_age", 0), cost_vec(at(item, "cost")), open, line_has, before,
                                 map(glist(item, "effects")) fx: encode_effect(fx) })
    for(t_slot.length) k: lines.push(map(glist(su_units[k], "line")) l: line_step_of(t_slot[k], l))
    for(np):
        ages.push(1)
        researched.push(zeros(research.length))
        gather_ticks.push(zeros(num_resources))
    let nb = bt_size.length
    for(np) p:
        for([ bm_hp, bm_pop, bm_sight, bm_food, bm_lacks, bm_research_time, bm_age_time, bm_research_cost, bm_range, bm_cost_pct, bm_trade_fee ]) col: col.push(zeros(nb))
        bm_cost.push(map(nb) k: copy(bt_cost[k]))
        bm_arm.push(map(nb): []::int)
        bm_trains.push(map(su_btypes) b: filter(map(gstrs(b, "trains")) slot: type_of_slot(p, slot)) tk: tk >= 0)
        for(su_btype_ids) id, k: bm_lacks[p][k] = if ident_lacks(p, id): 1 else: 0
    let nt = t_slot.length
    for([ t_heal_pct, t_kill_gold, t_wade, t_slow_on_hit, t_min_range, t_splash, t_pass_len, t_buildings_only, t_unpack, t_pack,
          t_blast, t_blast_line, t_air, t_hits_air, t_eval_sight, t_sight_add, t_machine, t_mounted, t_damage, t_heal ]) col:
        for(nt): col.push(0)
    for(nt):
        t_tags.push([]::int)
        t_mounts.push([]::Mount)
        t_bonus.push([]::int)
        t_eval_attack.push(0)
    let hr = at(lib_heroes, "rules")
    r_aura = as_int(at(hr, "aura_tiles")) * 1000
    r_regen = as_int(at(hr, "regen_every"))
    r_revive = as_int(at(hr, "revive_ticks"))
    r_revive_pct = as_int(at(hr, "revive_pct"))
    for(nt) k:
        if t_hero[k]:
            hero_types.push(k)
            hero_id.push(0)
            hero_fell.push(0)
            hero_fx.push(map(glist(su_units[k], "hero_aura")) fx: encode_effect(fx))

// The buildings an age needs first, for this player (Tech.requires): a lacked one gives way to its requires_else.
def requires_for(p:int, a:JV) -> [string]:
    return map(gstrs(a, "requires")) need: if ident_lacks(p, need): rstr(at(a, "requires_else"), need) else: need

// The rest of the systems' numbers (Garrison, Walls, Repair, Market, Trails, Abilities, Bridges, Match).
def setup_rest():
    let bd = lib_data("buildings.json")
    let g = gobj(bd, "garrison")
    r_garrison_heal_every = gint(g, "heal_every", 20)
    r_call_range = gint(g, "call_range", 16)
    garrison_not = map(gstrs(g, "not")) t: tag_or_none(t)
    heal_not = map(gstrs(rules_part("combat"), "heal_not")) t: tag_or_none(t)
    let wk = gobj(bd, "walkway")
    let br = gobj(bd, "breach")
    walk_climb = gint(wk, "climb", 2) * TICK_HZ
    walk_fall = gint(wk, "fall_damage", 10)
    walk_speed_pct = gint(wk, "speed_pct", 80)
    walk_push = gint(wk, "push", 2)
    walk_not = map(gstrs(wk, "not")) t: tag_or_none(t)
    rubble_terrain = str_index(tr_names, gstr(br, "terrain", ""))
    rubble_from = map(gstrs(br, "from")) id: btype_index(id)
    rubble_repair_pct = gint(br, "repair_pct", 100)
    let rp = gobj(bd, "repair")
    r_repair_speed = gint(rp, "speed_pct", 50)
    r_repair_cost = gint(rp, "cost_pct", 50)
    market_price = map(resource_names) r: if r == "gold": 0 else: 100
    let tc = rules_part("trails")
    tr_every = gint(tc, "every", 10)
    tr_add = gint(tc, "add", 1)
    tr_max = min(gint(tc, "max", 120), 255)
    tr_decay_every = gint(tc, "decay_every", 100)
    tr_decay = gint(tc, "decay", 1)
    tr_trail = gint(tc, "trail", 30)
    tr_speed_pct = gint(tc, "speed_pct", 0)
    wear = zeros(W * H)
    for(su_sides) ident:
        let ab = gobj(ident, "ability")
        let on = ab.keys.length > 0
        ab_kind.push(if on: 1 else: 0)
        ab_range.push(if on: as_int(at(ab, "range")) else: 0)
        ab_radius.push(if on: as_int(at(ab, "radius")) else: 0)
        ab_lasts.push(if on: as_int(at(ab, "lasts")) else: 0)
        ab_slow.push(if on: as_int(at(ab, "slow_pct")) else: 0)
        ab_cooldown.push(if on: as_int(at(ab, "cooldown")) else: 0)
    for(t_slot.length) k:
        var can = false
        if not t_animal[k]:
            let ab = gobj(su_sides[t_player[k]], "ability")
            can = ab.keys.length > 0 and has(ab, "tag") and reaches(ab, unit_tags(su_units[k]))
        t_ability.push(if can: 1 else: 0)
    let wr = rules_part("wonder")
    wonder_hold = if gbool(wr, "victory", false): as_int(at(wr, "hold_seconds")) * 20 else: 0
    let bc = lib_data("bridges.json")
    br_full_hp = as_int(at(bc, "hp"))
    br_ticks = as_int(at(at(bc, "rebuild"), "time")) * TICK_HZ
    br_cost = map(resource_names) r: gint(at(at(bc, "rebuild"), "cost"), r, 0)
    br_arm = map(su_classes.length): 0
    let ba = at(bc, "armour")
    for(ba.keys) k, n: br_arm[str_index(su_classes, k)] = as_int(ba.a[n])

// Starting stocks, a finished Town Center on each start, its workers (Economy.setup).
def setup_starts():
    let start = at(rules_part("economy"), "start")
    let np = num_players
    for(resource_names) r:
        stock.push(map(np): gint(start, r, 0))
        gathered.push(zeros(np))
    for(np) p:
        for(su_fx[p]) fx:
            if has(fx, "start"): stock[str_index(resource_names, rstr(fx, "start"))][p] += as_int(at(fx, "add"))
    for(np):
        pop.push(0)
        pop_cap.push(0)
        auto_reseed.push(1)
    let bids = gstrs(start, "buildings")
    for(np) p:
        if bids.length or as_int(at(start, "workers")) != 0:
            for(bids) bid:
                let k = btype_index(bid)
                assert k >= 0
                let size = bt_size[k]
                let b = place(p, k, start_x[p] / TILE - size / 2, start_y[p] / TILE - size / 2)
                b_done[b] = 1
                b_hp[b] = bm_hp[p][k]
            let worker = type_of_slot(p, "worker")
            if b_id.length and worker >= 0:
                let tc = b_id.length - 1
                for(as_int(at(start, "workers"))):
                    let cell = spawn_cell(tc, worker)
                    add_unit(p, worker, (cell % W) * TILE + 500, (cell / W) * TILE + 500)
    update_pop()

// ---- animals (Animals.place): sheep and boar round each start, deer herds on the open map, seeded

def animal_type(id:string) -> int: return str_index(su_type_animal, id)

def animal_open(c:int, taken:[int]) -> bool:
    return walks[0][c] == 1 and occupied[c] == 0 and amount[c] == 0 and not taken[c]

def free_cell(cx:int, cy:int, lo:int, hi:int, taken:[int]) -> int:
    for(40):
        let x = cx + range_int(su_rng, -hi, hi)
        let y = cy + range_int(su_rng, -hi, hi)
        if not (max(abs(x - cx), abs(y - cy)) < lo or x < 1 or y < 1 or x >= W - 1 or y >= H - 1):
            let c = y * W + x
            if animal_open(c, taken):
                taken[c] = 1
                return c
    return -1

def add_animal(k:int, c:int):
    let i = add_unit(gaia, k, (c % W) * TILE + 500, (c / W) * TILE + 500)
    u_posture[i] = 0  // (Units.add's default: animals keep it)

def place_animals():
    var spawn = at(lib_data("animals.json"), "spawn")
    let ma = gobj(su_map, "animals")
    if ma.keys.length: spawn = ma
    let symmetry = gstr(su_map, "symmetry", "")
    let ns = start_x.length
    let mirror = symmetry == "rotate" and ns % 2 == 0
    let taken = zeros(W * H)
    for(glist(spawn, "fixed")) entry:
        let k = animal_type(rstr(entry, "kind"))
        for(glist(entry, "cells")) xy:
            let c = as_int(xy.a[1]) * W + as_int(xy.a[0])
            for(if symmetry == "rotate": [ c, W * H - 1 - c ] else: [ c ]) at_:
                if animal_open(at_, taken):
                    taken[at_] = 1
                    add_animal(k, at_)
    var placed_k = []::int
    var placed_c = []::int
    for(min(num_players, ns)) p:
        if mirror and p % 2 == 1:
            for(placed_k) k, n:
                let c = W * H - 1 - placed_c[n]
                if animal_open(c, taken):
                    taken[c] = 1
                    add_animal(k, c)
        else:
            placed_k = []
            placed_c = []
            for(glist(spawn, "near_start")) entry:
                let k = animal_type(rstr(entry, "kind"))
                let herd = gint(entry, "size", 1)
                for(as_int(at(entry, "count"))):
                    let c = free_cell(start_x[p] / TILE, start_y[p] / TILE, as_int(at(entry, "min")), as_int(at(entry, "max")), taken)
                    if c >= 0:
                        add_animal(k, c)
                        placed_k.push(k)
                        placed_c.push(c)
                        for(herd - 1):
                            let b = free_cell(c % W, c / W, 0, 1, taken)
                            if b >= 0:
                                add_animal(k, b)
                                placed_k.push(k)
                                placed_c.push(b)
    for(glist(spawn, "wild")) entry:
        let k = animal_type(rstr(entry, "kind"))
        for(as_int(at(entry, "herds"))):
            var centre = -1
            for(60):
                if centre < 0:
                    let x = range_int(su_rng, 2, W - 3)
                    let y = range_int(su_rng, 2, H - 3)
                    var far = true
                    for(min(num_players, ns)) p:
                        if abs(x - start_x[p] / TILE) + abs(y - start_y[p] / TILE) < as_int(at(entry, "away")): far = false
                    if far and animal_open(y * W + x, taken): centre = y * W + x
            if centre >= 0:
                for(as_int(at(entry, "size"))):
                    let c = free_cell(centre % W, centre / W, 0, 2, taken)
                    if c >= 0:
                        add_animal(k, c)
                        let twin = W * H - 1 - c
                        if mirror and animal_open(twin, taken):
                            taken[twin] = 1
                            add_animal(k, twin)

// The map's bridges (Bridges.setup), standing, nobody's.
def setup_bridges():
    for(su_bridge_rects) r:
        let cells = []::int
        var y = r[1]
        while y <= r[3]:
            var x = r[0]
            while x <= r[2]:
                cells.push(y * W + x)
                x++
            y++
        br_id.push(next_id)
        next_id++
        br_cells.push(cells)
        br_x0.push(r[0] * TILE)
        br_y0.push(r[1] * TILE)
        br_x1.push(r[0] * TILE + (r[2] - r[0] + 1) * TILE - 1)
        br_y1.push(r[1] * TILE + (r[3] - r[1] + 1) * TILE - 1)
        br_hp.push(br_full_hp)
        br_up.push(1)
        br_work.push(0)
        br_payer.push(-1)
        set_deck(cells, true)

// ---- the bots' config (data/ai.json with the normal level, as Bot.new leaves it; export.gd _write_ai)

def ai_ints(v:JV) -> JV:
    if v.kind == J_FLOAT:
        return jint(int(v.f))
    if v.kind == J_ARR: return jarr(map(v.a) x: ai_ints(x))
    if v.kind == J_OBJ:
        let o = jobj()
        for(v.keys) k, n: set(o, k, ai_ints(v.a[n]))
        return o
    return v

// A level's `press` over military.press, key by key.
def level_press(cfg:JV, l:JV):
    if not has(l, "press") or not has(at(cfg, "military"), "press"): return
    let to = at(at(cfg, "military"), "press")
    let by = at(l, "press")
    for(by.keys) k, n: set(to, k, by.a[n])

// The resources bots buy when short of them (resources.json "staple"); a save from an older build has none.
def staples_from_data():
    if staple_resources.length: return
    for(glist(lib_data("resources.json"), "resources")) r, k:
        let st = get(r, "staple")
        if st and st.i != 0: staple_resources.push(k)

def load_ai_config(lvl:string = "normal"):  // (the lobby's AI levels: easy, normal, hard)
    let cfg = ai_ints(lib_data("ai.json"))
    var lv_ratio = 0
    var lv_wave = 100
    var lv_up = 0
    var lv_age3 = gint(at(cfg, "economy"), "age3_workers", 26)
    var lv_tow = 0
    var lv_shelter = 0
    var lv_all = 0
    var lv_guard = 0
    var lv_raids_ = 0
    var lv_from = 0
    let levels = gobj(cfg, "levels")
    if has(levels, lvl):
        let l = at(levels, lvl)
        for(glist(at(cfg, "military"), "waves")) w:
            set(w, "at", jint(as_int(at(w, "at")) + gint(l, "delay", 0)))
            set(w, "min_army", jint(max(1, as_int(at(w, "min_army")) * gint(l, "army_pct", 100) / 100)))
        let mil = at(cfg, "military")
        let rm = at(mil, "repeat_min_army")
        if rm.kind == J_OBJ:
            for(rm.keys.length) n: rm.a[n] = jint(max(1, as_int(rm.a[n]) * gint(l, "army_pct", 100) / 100))
        else: set(mil, "repeat_min_army", jint(max(1, as_int(rm) * gint(l, "army_pct", 100) / 100)))
        if has(l, "max_workers"): set(at(cfg, "economy"), "max_workers", at(l, "max_workers"))
        level_press(cfg, l)
        lv_ratio = gint(l, "army_ratio", 0)
        lv_wave = gint(l, "wave_pct", 100)
        lv_up = if gint(l, "build_up", 0) == 1: 1 else: 0
        lv_age3 = gint(l, "age3_workers", lv_age3)
        lv_tow = gint(l, "towers", 0)
        lv_shelter = gint(l, "shelter_pop", 0)
        lv_all = gint(l, "all_in", 0)
        lv_guard = if gint(l, "guard_crossing", 0) == 1: 1 else: 0
        lv_raids_ = gint(l, "raids", 0)
        lv_from = gint(l, "raid_from", 0) * 20
    let nums = []::string
    let strs = []::string
    ai_walk(cfg, "", nums, strs)
    let smax = gobj(gobj(at(cfg, "military"), "siege"), "max")
    strs.push("military.siege.max_order " + string(smax.keys.length) + (if smax.keys.length: " " + concat_string(smax.keys, " ") else: " "))
    let toks = [ "AI", string(nums.length), string(strs.length) ]
    for(nums) x: for(prompt_words(x)) t: toks.push(t)
    for(strs) x: for(prompt_words(x)) t: toks.push(t)
    let order = glist(cfg, "build_order")
    toks.push("BUILD_ORDER")
    toks.push(string(order.length))
    for(order) s:
        toks.push(rstr(s, "building"))
        toks.push(gstr(s, "near", "-"))
        for([ gint(s, "age", 1), as_int(at(s, "workers")), gint(s, "count", -1), gint(s, "builders", 2), gint(s, "away", 0),
              gint(s, "own_side", 0), gint(s, "guard", 0), gint(s, "save", 0), gint(s, "push", -1), gint(s, "expand_workers", -1) ]) v: toks.push(string(v))
    let waves = glist(at(cfg, "military"), "waves")
    toks.push("WAVES")
    toks.push(string(waves.length))
    for(waves) w:
        toks.push(string(as_int(at(w, "at"))))
        toks.push(string(as_int(at(w, "min_army"))))
    toks.push("LEVEL")
    for([ lv_ratio, lv_wave, lv_up, lv_age3, lv_tow, lv_all, lv_shelter, lv_guard, lv_raids_, lv_from ]) v: toks.push(string(v))
    ai_tokens = toks
    tokens = toks
    tp = 0
    load_ai()

def jv_plain(v:JV) -> string:  // str() of a value in a list (export.gd: " ".join(v.map(str)))
    if v.kind == J_STR: return v.s
    if v.kind == J_BOOL: return if v.i != 0: "true" else: "false"
    return stringify(v)

def ai_walk(v:JV, path:string, nums:[string], strs:[string]) -> void:
    if ends_with(path, "note") or find_string(path, "_doc") >= 0 or path == "build_order" or path == "military.waves" or path == "levels": return
    switch v.kind:
        case J_OBJ:
            for(sorted_strs(v.keys)) k: ai_walk(at(v, k), if path == "": k else: path + "." + k, nums, strs)
        case J_ARR: strs.push(path + " " + string(v.a.length) + " " + concat_string(map(v.a) x: jv_plain(x), " "))
        case J_INT, J_FLOAT, J_BOOL: nums.push(path + " " + string(as_int(v)))
        case J_STR: strs.push(path + " 1 " + v.s)
        default: pass()
