// ------------------------------------------------------------------ state
// The World's arrays (world.gd, units.gd, sim_map.gd), as globals. Units are parallel int columns
// in slot order (ascending id); unit_columns() lists them for removal.

// A command (commands.gd): the tick it runs, its code (CMD_* in consts), the player, four ints and the
// unit ids. Shift-queued copies in a unit's queue (units.orders) keep their formation slot.
class Cmd:
    run_tick:int
    code:int
    player:int
    a:int
    b:int
    c:int
    d:int
    ids:[int]
    seq:int
    queue = 0    // 1: shift-queued
    slotted = 0  // 1: a queued MOVE / ATTACK_MOVE's copy, with its own slot and the group's
    sx = 0
    sy = 0
    group = 0
    fx = 0
    fy = 0
    pace = 0

var extras = dictionary<string, [int]>(64)  // the scenario's EXTRA section

// Map (sim_map.gd): walk grids per lane, terrain speed percent per movement class and cell.
var W = 0
var H = 0
var walks = []::[int]
var roomy = []::[int]  // per lane: 1 where the cell and its 8 neighbours are on the map and walkable
var tight = []::[int]  // per lane: cells not roomy per ROOM_CHUNK block
var room_cw = 0
var speed_pct = []::[int]
var speed_row = []::[int]  // per movement class: its speed (per cent) on each terrain (rules movement.terrain_speed)
var opaque = []::int       // 1 where a cell blocks sight (trees)
var level = []::int        // ground level per cell
var num_players = 0
var lane_base = []::int  // per player
var teams = []::int      // per player
var lost = []::int       // per player: units killed so far

// Host rules the port reads (rules.combat, rules.high_ground, rules.fog).
var r_min_damage = 0
var r_acquire_every = 0
var r_defend_sight = 0
var r_counter_pull = 0
var r_leash = 0
var r_sight = 0
var r_shot_lead_pct = 0
var r_shot_strays = 0
var r_shot_slack = 0
var r_high_reach = 0
var r_uphill_pct = 0
var r_high_sight_unit = 0  // rules.high_ground.sight_unit: tiles more sight a level up
var has_heights = 0        // the map has hills
var r_fog_every = 0
var r_fog_unit = 0
var r_fog_worker = 0

// Unit types (World._make_type, Combat.type_vectors). Vectors are per armour class.
var num_classes = 0
var t_speed = []::int
var t_radius = []::int
var t_role = []::int    // formation band (World._form_role)
var t_gap = []::int     // form_gap
var t_form_r = []::int  // half its footprint with its crew, for its slot in a formation; 0: its radius (#253)
var t_worker = []::int
var t_harmless = []::int
var t_healer = []::int
var t_ranged = []::int
var t_reach = []::int
var t_reload = []::int
var t_shot_speed = []::int
var t_min_damage = []::int
var t_sight = []::int  // the line's own sight plus research
var t_mclass = []::int
var t_air = []::int       // per unit type: 1 for an aircraft (winged creatures aren't: melee can reach them)
var t_hits_air = []::int  // per unit type: 1 if its weapon can hit an aircraft
// A gun on a unit that turns on its own (a part's stats.mounts): tenths of a degree, ticks, milli-tiles. Its weapon falls
// back on the unit's where it says nothing.
class Mount:
    part:string             // the voxel part it turns, or "" for a gun fixed to the hull
    rest:int                // its rest facing, off the hull
    arc:int                 // how far it goes either side of that (1800: all the way round)
    turn:int                // a tick
    tolerance:int           // how far off its target it can fire
    range:int               // 0: the unit's
    reload:int              // 0: the unit's
    attack:int              // -1: the unit's
    damage:int              // its attack's class
    shot:string             // its look in shots.json, or "" for the unit's
    atk:[int]               // the attack by class, with the unit's bonuses; empty: the unit's
var t_mounts = []::[Mount]  // per unit type: its mounts; none: the body is its one weapon
var t_atk = []::[int]
var t_arm = []::[int]
var t_cls = []::[int]
var t_counters = []::[int]  // classes past the base three it has a bonus against

// Units (units.gd), slots sorted by id. reach, task, perch, patient, gspot are constant here.
var unit_changes = 0  // bumped on every unit added, put back or removed (units.changes)
var u_id = []::int
var u_owner = []::int
var u_kind = []::int
var u_x = []::int
var u_y = []::int
var u_tx = []::int
var u_ty = []::int
var u_moving = []::int
var u_arrive = []::int
var u_wx = []::int
var u_wy = []::int
var u_group = []::int
var u_stuck = []::int
var u_prog = []::int
var u_fkey = []::int
var u_speed = []::int
var u_radius = []::int
var u_mclass = []::int
var u_pace = []::int
var u_block = []::int  // the marching block it keeps its place in (+1; 0: none), and that place from the block's centre
var u_bx = []::int
var u_by = []::int
var u_vx = []::int  // its velocity: milli-tiles a tick (#346)
var u_vy = []::int
var u_hp = []::int
var u_foe = []::int
var u_cooldown = []::int
var u_stance = []::int   // Combat NONE / ORDERED / AUTO / ATTACK_MOVE / RETURN
var u_posture = []::int  // Combat AGGRESSIVE / DEFENSIVE / STAND / PASSIVE
var u_gx = []::int
var u_gy = []::int
var u_amx = []::int
var u_amy = []::int
var u_amc = []::int
var u_task = []::int        // Economy NONE / GATHER / RETURN / BUILD
var u_target = []::int      // resource cell (GATHER) or building id (RETURN, BUILD)
var u_home = []::int        // resource cell to go back to after a drop-off, or -1
var u_gspot = []::int       // its standing spot round `home`, or -1
var u_carry_kind = []::int  // resource index + 1, or 0
var u_carry = []::int
var u_work = []::int   // ticks into the current gather (or build, or wait)
var u_reach = []::int  // 0: arrive at (tx, ty); 1: next to the rect below; 2: (tx, ty), its place beside the rect
var u_rx0 = []::int
var u_ry0 = []::int
var u_rx1 = []::int
var u_ry1 = []::int
var u_patient = []::int  // healers: the unit id being healed (or walked to), or 0
var u_route = []::int    // trade carts: the home market's id (target: the far one), or 0
var u_ready = []::int    // packing engines: ticks stood unpacking, or below 0 while packing up (World._pack)
var u_perch = []::int    // walls you stand on (walls.gd), cells + 1: the walkway cell it stands on (0: the ground)
var u_wgoal = []::int    // on a wall: the cell it walks to + 1; climbing: where it goes once up
var u_wnext = []::int    // on a wall: the next cell on its way + 1
var u_wexit = []::int    // on a wall: the way down it is leaving by (a building or siege tower id), or 0
var u_wtime = []::int    // on a wall: ticks left climbing down, or 0
var u_hull = []::int     // a turret: the way its hull last moved (tenths of a degree)
var u_lx = []::int       // a turret: where the hull was when that was worked out
var u_ly = []::int
var u_mount = []::[int]   // per unit: its mounts' aim, target and cooldown, in threes (combat.lobster)
var u_orders = []::[Cmd]  // per unit: shift-queued orders, oldest first (units.orders)

// The columns in unit_fields order (the hash, the scenario file), then the rest.
def unit_columns() -> [[int]]:
    return [ u_id, u_x, u_y, u_tx, u_ty, u_moving, u_arrive, u_wx, u_wy, u_group, u_stuck, u_prog, u_fkey, u_pace,
             u_hp, u_foe, u_cooldown, u_stance, u_posture, u_gx, u_gy, u_amx, u_amy, u_amc,
             u_task, u_target, u_home, u_gspot, u_carry_kind, u_carry, u_work, u_reach, u_rx0, u_ry0, u_rx1, u_ry1, u_patient,
             u_route, u_ready, u_perch, u_wgoal, u_wnext, u_wexit, u_wtime, u_hull, u_lx, u_ly,
             u_owner, u_kind, u_speed, u_radius, u_mclass, u_block, u_bx, u_by, u_vx, u_vy ]

// What hooks keep (hooks/active.lobster's hook_declare): saved and hashed like the sim's own. A column per name; a unit's
// by its id, so it stays with the unit through a garrison and needn't change when units come and go.
var hook_unit_names = []::string
var hook_unit_cols = []::[int]
var hook_player_names = []::string
var hook_player_cols = []::[int]
var hook_tick_types = []::int  // the unit types that asked for hook_unit_tick

def hook_declare_unit(name:string) -> int:
    hook_unit_names.push(name)
    hook_unit_cols.push([]::int)
    return hook_unit_names.length - 1

def hook_unit_get(col:int, i:int) -> int:
    let id = u_id[i]
    return if id < hook_unit_cols[col].length: hook_unit_cols[col][id] else: 0

def hook_unit_set(col:int, i:int, v:int):
    let id = u_id[i]
    while hook_unit_cols[col].length <= id: hook_unit_cols[col].push(0)
    hook_unit_cols[col][id] = v

def hook_declare_player(name:string, players:int) -> int:
    hook_player_names.push(name)
    hook_player_cols.push(map(players): 0)
    return hook_player_names.length - 1

let UNIT_HASHED = 47    // the columns hashed (unit_fields)
var t_tags = []::[int]  // per unit type: its eval's tags (class indexes), as its line stands
var t_damage = []::int  // per unit type: its attack's class (0 melee, 1 pierce, ...)

// This tick's events (World.events), for the bots: hits, deaths, shots. Not state.
let EV_HIT = 0     // a: by, b: to, c: damage
let EV_DIE = 1     // a: id, b: 1 for a building
let EV_SHOT = 2    // a: by, b: to
let EV_MISS = 3    // a: by (a shot in the ground at x, y); the view's (the bots don't read these three)
let EV_HEAL = 4    // a: by, b: to
let EV_SPLASH = 5  // c: radius (a stone or a charge comes down at x, y)
class Event:
    kind:int
    a:int
    b:int
    c:int
    x:int
    y:int
var events = []::Event
var events_on = false  // only the bots read them

let REC_ID = 0  // a sheltering unit's record (garrison.gd)
let REC_KIND = 1
let REC_HP = 2
let REC_POSTURE = 3
let REC_CARRY_KIND = 4
let REC_CARRY = 5
let REC_HOME = 6
let REC_SIZE = 7

// Unit types' economy (World._make_type): pop, train time, cost vector, research and bonuses.
var t_pop = []::int
var t_train_ticks = []::int
var t_hp = []::int
var t_posture = []::int
var t_carry_add = []::int
var t_build_pct = []::int
var t_player = []::int
var t_age = []::int
var t_cost = []::[int]

// Buildings (buildings.gd), slots sorted by id; ids shared with units.
var b_id = []::int
var b_owner = []::int
var b_kind = []::int
var b_cx = []::int
var b_cy = []::int
var b_sx = []::int
var b_sy = []::int
var b_hp = []::int
var b_progress = []::int
var b_done = []::int
var b_train = []::int
var b_rally_x = []::int
var b_rally_y = []::int
var b_cooldown = []::int  // shooting buildings: ticks until the next volley
var b_diag = []::int      // 0: the whole rect; 1 or 2: a diagonal gate, the cells on one diagonal of its square
var b_queue = []::[int]   // unit type indexes, head first
var b_inside = []::[int]  // units sheltering inside (garrison.gd): REC_SIZE ints each, by id

// Saves outlive builds (D-141): a per-unit or per-building variable added since a save was made comes back from it
// empty (flexbuffers give a missing field its empty value), so it's padded here with 0 for every unit and building.
// Anything else whose empty value is wrong mid-match needs its own fix after loading.
def pad_saved_columns():
    while t_form_r.length < t_gap.length: t_form_r.push(0)
    while u_mount.length < u_id.length: u_mount.push([])
    for(unit_columns()) col:
        while col.length < u_id.length: col.push(0)
    for(building_columns()) col:
        while col.length < b_id.length: col.push(0)

def building_columns() -> [[int]]:
    return [ b_id, b_owner, b_kind, b_cx, b_cy, b_sx, b_sy, b_hp, b_progress, b_done, b_train, b_rally_x, b_rally_y, b_cooldown, b_diag ]

// Shooting buildings and garrisons, per building type (buildings.json attack, garrison).
var bt_attacks = []::int  // 1 if it has an attack
var bt_atk_class = []::int
var bt_atk = []::int
var bt_range = []::int  // tiles
var bt_reload = []::int
var bt_arrows = []::int    // its own arrows (one more per unit inside)
var bt_garrison = []::int  // how many it holds
var bt_gate = []::int
var bt_wall = []::int        // a wall piece (`line`)
var bt_over_trees = []::int  // sees over trees (fog)
var r_fog_tower = 0
var r_garrison_heal_every = 0
var r_call_range = 0
var garrison_not = []::int  // tags (classes) that don't fit in a building (workers always do)

// Heroes (heroes.gd) and the match (match.gd).
var hero_types = []::int  // the unit types that are heroes, in order
var hero_id = []::int     // per hero type (alongside hero_types): its living hero's id, 0 with none
var hero_fell = []::int   // ... the tick + 1 it last fell, 0 if never
var r_aura = 0            // milli-tiles
var r_regen = 0
var r_revive = 0
var r_revive_pct = 0
var winner = -1
var defeated = []::int
var started_with_town = []::int

// Building types (Economy.load_btypes), and per player what research and the race make of them.
var bt_size = []::int
var bt_build_ticks = []::int
var bt_pop = []::int
var bt_sight = []::int
var bt_age = []::int
var bt_more_from_age = []::int
var bt_water = []::int
var bt_line = []::int
var bt_tower = []::int
var bt_farm = []::int
var bt_land = []::int  // a farm: the terrain it becomes on land, in water
var bt_wet = []::int
var bt_workers = []::int  // a farm: how many work it at once
var bt_special = []::int  // pens, gates, ladders, walls you stand on: not in the spike
var bt_drop = []::[int]   // per resource: 1 if it takes it in
var bt_reseed = []::[int]
var bm_hp = []::[int]  // [player][type]
var bm_pop = []::[int]
var bm_sight = []::[int]
var bm_food = []::[int]  // a farm's food when sown (Economy.farm_food)
var bm_lacks = []::[int]
var bm_trains = []::[[int]]  // [player][type]: the unit types it trains
var bm_cost = []::[[int]]    // [player][type]: Economy.bcost

var bt_name = []::string
var bt_cost = []::[int]  // the price as listed (the bots check it for farms)
var bt_roles = []::int   // per type: a bit per ROLE_NAMES entry it plays (buildings.json "roles", D-192)

// Building roles: what the sim and the bots look a building type up by, never its id. A farm, a pen
// and a drop-off are known by their own fields (becomes, pen, drop_off) and need no role.
let ROLE_NAMES = [ "hub", "housing", "trade", "barracks", "tower", "defence", "wonder" ]
let ROLE_HUB = 1       // the town's heart: a player without one is out; herds and the bots' home
let ROLE_HOUSING = 2   // what the bots build for room
let ROLE_TRADE = 4     // a market: buying, selling and trade carts
let ROLE_BARRACKS = 8  // the bots' first army building, before the first age
let ROLE_TOWER = 16    // the tower the bots put up where they were raided
let ROLE_DEFENCE = 32  // a strong point guarding a crossing
let ROLE_WONDER = 64   // stood long enough, it wins

def role_bits(names:[string]) -> int:
    var bits = 0
    for(names) name:
        let n = find(ROLE_NAMES): _ == name
        assert n >= 0
        bits |= 1 << n
    return bits

def has_role(k:int, role:int) -> bool: return (bt_roles[k] & role) != 0

// The first building type with that role, or -1.
def btype_with(role:int) -> int: return find(bt_roles): (_ & role) != 0
var map_version = 0  // bumped on every cell change (SimMap.version; the bots' reach relabels)

// Players' economy.
var num_resources = 0
var gather_spots = []::int  // per resource: 1 spots all round, 2 the four sides, 0 anywhere in reach
var ages = []::int
var auto_reseed = []::int
var pop = []::int
var pop_cap = []::int
var stock = []::[int]  // [resource][player]
var gathered = []::[int]
var gather_ticks = []::[int]  // [player][resource]
var next_id = 0
var r_carry = 0
var r_queue_max = 0
var r_pop_max = 0
var r_fog_building = 0
var r_high_sight_building = 0

def remove_unit(i:int):
    unit_changes++
    for(unit_columns()) col: col.remove(i)
    u_orders.remove(i)
    u_mount.remove(i)

var tick = 0
var next_group = 1

// Shots in flight (shots.gd): SHOT_STRIDE ints a shot, in loosing order.
var shots = []::int

// Fog (fog.gd): per player, a byte per cell (0 unseen, 1 explored, 2 visible), and the cells lit
// at its last update.
var fog = []::[int]
var fog_lit = []::[int]

// The tick's start, for _sidestep / _queued / _passed (World._move's _ox ...: in GDScript the live arrays).
var o_x = []::int
var o_y = []::int
var o_moving = []::int
var o_stuck = []::int
var o_wx = []::int
var o_wy = []::int

// Spatial buckets (spatial.gd): bucket c holds sp_items[sp_start[c] .. sp_end[c] - 1], slots ascending.
var sp_start = []::int
var sp_end = []::int
var sp_items = []::int
var sp_cell = []::int
var sp_cursor = []::int
var sp_used = []::int  // the cells that hold units since the last build (spatial_build empties only these)

// Formation scratch: each unit's slot, how far ahead / aside it stands.
var slot_x = []::int
var slot_block = []::int  // a formation's block for each unit (+1), and its place in it
var slot_bx = []::int
var slot_by = []::int

// Marching blocks (lib/orders.lobster): a big order's blocks, each a moving centre its units keep their places round.
var fb_state = []::int  // 0 free, then BLOCK_FORMING, BLOCK_MARCHING, BLOCK_THERE
var fb_x = []::int      // the centre, milli-tiles
var fb_y = []::int
var fb_gx = []::int  // the order's target: told the same again, it marches on
var fb_gy = []::int
var fb_tx = []::int  // where it's making for
var fb_ty = []::int
var fb_wx = []::int  // its next waypoint
var fb_wy = []::int
var fb_dx = []::int  // its heading (the units face it)
var fb_dy = []::int
var fb_pace = []::int
var fb_key = []::int  // the flow field it follows
var fb_r = []::int    // half its depth
var fb_owner = []::int
var fb_army = []::int  // the order it's of: an army's blocks march together, once all are formed
var fb_t = []::int     // ticks forming
var fb_held = []::int  // 1: it's fighting, the blocks behind wait
var slot_y = []::int
var f_ahead = []::int
var f_side = []::int

// Separation scratch.
var s_pushx = []::int
var s_pushy = []::int
var s_planted = []::int
def remove_building(b:int):
    for(building_columns()) col: col.remove(b)
    b_queue.remove(b)
    b_inside.remove(b)

// A unit back in the arrays under an id it had before (out of a building), in its place by id
// (Units.insert, with units.gd _put's defaults). Its slot.
def insert_unit(uid:int, owner:int, k:int, x:int, y:int, speed:int, radius:int, hp:int) -> int:
    let found, at = binary_search(u_id, uid)
    assert not found
    let v = [ uid, x, y, x, y, 0, 0, x, y, 0, 0, -1, -1, 0,
              hp, 0, 0, 0, 0, x, y, 0, 0, -1,
              0, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, x, y,
              owner, k, speed, radius, 0, 0, 0, 0, 0, 0 ]
    unit_changes++
    for(unit_columns()) col, n: col.insert(at, v[n])
    u_orders.insert(at, [])
    u_mount.insert(at, [])
    return at

var t_hero = []::int         // per unit type: 1 for a hero
var t_heal = []::int         // per unit type: its eval's heal (0: not a healer's)
var fog_seen = []::[[int]]   // per player: enemy buildings remembered as last seen (fog.lobster remember)
var fog_ground = []::[int]   // per player: the terrain per cell as they last saw it (Fog's fog_ground: the view draws it)
var fog_left = []::[int]     // per player: what was left per cell as they last saw it
var fog_watch = []::int      // 1 where a cell held a resource at the start or has changed since: only those can differ
var t_eval_attack = []::int  // per unit type: its eval attack with research (the counter-pick)
var t_bonus = []::[int]      // per unit type: its eval bonus vector with research
var t_slot = []::string      // per unit type: its roster slot
var t_trader = []::int
var resource_names = []::string
var staple_resources = []::int  // the resources bots buy when short (resources.json "staple")
var tr_names = []::string
var start_x = []::int  // the map starts, milli-tiles
var start_y = []::int
var slot_names = []::string
var slots_lacked = []::[int]  // per player: slot indexes (slot_names) its race lacks
var trade_lacked = []::int

def slot_index(slot:string) -> int:
    for(slot_names) s, k:
        if s == slot: return k
    return -1

// Animals (animals.gd) and the rest of the types' flags, declared here: combat reads them.
let B_NONE = 0
let B_FLEE = 1
let B_FIGHT = 2
let B_HERD = 3
var gaia = -1
var claim_tiles = 4
var t_behave = []::int        // per unit type: B_NONE / FLEE / FIGHT / HERD
var t_flee = []::int          // per unit type: milli-tiles it bolts
var t_food = []::int          // per unit type: the carcass's food
var bt_pen_animals = []::int  // per building type (0: not a pen)
var bt_pen_food = []::int
var bt_pen_food_ticks = []::int
var bt_pen_breed_ticks = []::int
var herd_spots = dictionary<int, [int]>(16)  // Town Center id -> [x, y], chosen once
var t_no_heal = []::int
var t_animal = []::int

// Map bridges (bridges.gd): per bridge its id, deck cells, rect (milli-tiles, inclusive), state.
var br_id = []::int
var br_cells = []::[int]
var br_x0 = []::int
var br_y0 = []::int
var br_x1 = []::int
var br_y1 = []::int
var br_hp = []::int
var br_up = []::int
var br_work = []::int
var br_payer = []::int
var br_full_hp = 0
var br_ticks = 1
var br_cost = []::int
var br_arm = []::int

// Walls you stand on, gates, ladders (walls.gd, buildings.json), per building type.
var bt_length = []::int
var bt_stairs = []::int
var bt_ladder = []::int
var bt_walkway = []::int  // standing places a cell on its top (0: none)
var bt_blocks_flyers = []::int
var bt_replaces = []::[int]  // building types it may be laid over (a gate into a wall)
var bt_pour = []::[int]      // a walkway tower's pour: reach, reload, damage (empty: none)
var walk_climb = 40
var walk_fall = 10
var walk_speed_pct = 80
var walk_push = 2
var walk_not = []::int  // classes that can't climb
var rubble_terrain = -1
var rubble_from = []::int  // building types that leave rubble
var rubble_repair_pct = 100
var rubble = dictionary<int, [int]>(64)  // cell -> [terrain it was, owner, kind, cx, cy, along]
var rubble_cells = []::int               // its keys, ascending

// Slowing this tick (abilities.gd slow_now), read by the moves.
var slow_ids = []::int  // this tick: unit id -> its speed pct (webs, sticky hits)
var slow_pcts = []::int
var t_wade = []::int  // per unit type: the swamp folk's bonus (no terrain slows it)

// Worn trails (trails.gd), read by the moves.
var wear = []::int
var tr_every = 10
var tr_add = 1
var tr_max = 120
var tr_decay_every = 100
var tr_decay = 1
var tr_trail = 30
var tr_speed_pct = 0
