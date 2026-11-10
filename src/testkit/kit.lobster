// ------------------------------------------------------------------ the test tools' shared kit
// For the ports of tests/test_ai.gd, test_2v2.gd, race_matches.gd, mass_battle.gd, resource_audit.gd and
// path_audit.gd: a fresh world, World's SPAWN (deferred to its turn like a command), the bots on both
// sides (full bots and eco bots), the bots' config at a level and with a test's changes, what the
// GDScript events told (research, ages, heroes, trade, webs) read off the state, shards, the clock.
// Imported after every sim, bot and setup module.

let KIT_JITTER = 400  // World.SPAWN_JITTER
var kit_dump = -1     // dump:<tick>: the state then (dump_state, as export.gd's), to diff against GDScript's
var kit_trace = 0     // trace:<n> on a tool's command line: the state hash every n ticks ("h <tick> <hash>")

// ---- checks

var checks = 0
var failures = 0

def check(ok:bool, what:string):
    checks++
    if not ok:
        failures++
        print "FAIL: " + what

def clock(t:int) -> string:
    if t < 0: return "-"
    let s = t / 20 % 60
    return "{t / 1200}:" + (if s < 10: "0" else: "") + string(s)

// A float with `places` decimals.
def fixed_str(f:float, places:int) -> string:
    var scale = 1
    for(places): scale *= 10
    let v = int(f * float(scale) + (if f < 0.0: -0.5 else: 0.5))
    let whole = string(abs(v) / scale)
    if places == 0: return (if v < 0: "-" else: "") + whole
    var frac = string(abs(v) % scale)
    while frac.length < places: frac = "0" + frac
    return (if v < 0: "-" else: "") + whole + "." + frac

def pad_right(s:string, n:int) -> string:
    var out = s
    while out.length < n: out += " "
    return out

def pad_left(s:string, n:int) -> string:
    var out = s
    while out.length < n: out = " " + out
    return out

def int_index(xs:[int], v:int) -> int:
    for(xs) x, n:
        if x == v: return n
    return -1

def map_exists(map_id:string) -> bool: return read_file("../data/maps/" + map_id + ".json") != nil

// shard:<i>/<n> among the arguments: (i, n), or (0, 1).
def shard_of(args:[string]) -> int, int:
    for(args) a:
        if starts_with(a, "shard:"):
            let i, n = split_string(a.substring(6, a.length - 6), "/")
            return string_to_int(i), string_to_int(n)
    return 0, 1

def plain_args(args:[string]) -> [string]:
    for(args) a:
        if starts_with(a, "trace:"): kit_trace = string_to_int(a.substring(6, a.length - 6))
        if starts_with(a, "dump:"): kit_dump = string_to_int(a.substring(5, a.length - 5))
    return filter(args) a: not starts_with(a, "shard:") and not starts_with(a, "trace:") and not starts_with(a, "dump:")

// ---- the world

class Spawn:
    run_tick:int
    player:int
    kind:int
    count:int
    x:int
    y:int

var spawns = []::Spawn
var id_owner = []::int  // unit id -> its owner, kept as units appear (a dead unit's owner, for deaths)
var id_kind = []::int

// A fresh world (World.new): the old one's globals reset first; the bots read events.
def new_world(seed_value:int, map_id:string, races:[JV], rules:JV, team_ids:[int]):
    reset_world()
    setup_match(seed_value, map_id, races, rules, team_ids)
    events_on = true
    spawns = []
    id_owner = []
    id_kind = []
    note_ids()

def note_ids():
    for(u_id) uid, i:
        while id_owner.length <= uid:
            id_owner.push(-1)
            id_kind.push(-1)
        if id_owner[uid] < 0:
            id_owner[uid] = u_owner[i]
            id_kind[uid] = u_kind[i]

def owner_of_id(uid:int) -> int: return if uid < id_owner.length: id_owner[uid] else: -1

// World's SPAWN: `count` of p's unit type k round (x, y), at the start of turn + 2 as a command runs.
def spawn_kind(p:int, k:int, count:int, x:int, y:int):
    assert k >= 0
    spawns.push(Spawn { (tick / TICKS_PER_TURN + 2) * TICKS_PER_TURN, p, k, count, x, y })

def spawn(p:int, slot:string, count:int, x:int, y:int): spawn_kind(p, type_of_slot(p, slot), count, x, y)

def run_spawns():
    if not spawns.length: return
    let now = filter(spawns): _.run_tick == tick
    if not now.length: return
    spawns = filter(spawns): _.run_tick != tick
    for(now) s:
        let k = s.kind
        for(s.count):
            var sx = s.x + range_int(su_rng, -KIT_JITTER, KIT_JITTER)
            var sy = s.y + range_int(su_rng, -KIT_JITTER, KIT_JITTER)
            let ln = lane_base[s.player] + t_mclass[k]
            if not walkable(sx, sy, ln):
                sx, sy = centre(nearest_walkable(cell_of(sx, sy), ln))
            let i = add_unit(s.player, k, sx, sy)
            if t_hero[k] and hero_id[hero_slot(k)] == 0: hero_spawned(i)
    grow_scratch()

// One tick: the spawns due, World.step, the ids seen.
def wstep():
    run_spawns()
    step()
    note_ids()
    if kit_trace > 0 and tick % kit_trace == 0: print "h {tick} {state_hash()}"
    if tick == kit_dump: print dump_state()

// A unit type's name as its line stands (the last step its player has researched).
def unit_name(k:int) -> string:
    var at_step = 0
    for(lines[k]) l, n:
        if n > 0 and l.up >= 0 and researched[t_player[k]][l.up] != 0: at_step = n
    let steps = glist(su_units[k], "line")
    return if at_step < steps.length: rstr(at(steps[at_step], "look"), "name") else: rstr(at(su_units[k], "look"), "name")

class LevelCfg:
    wave_at:[int]
    wave_min:[int]
    lv:[int]
    keys:[string]  // the config numbers a level changes (repeat_min_army...)
    vals:[int]

// ---- the sides: a full bot or an eco bot (a passive player)

class Side:
    player:int
    full:Bot?
    eco:EcoBot?
    lv:LevelCfg?  // its level's config, put in place before it thinks (two levels in one match)

def full_side(p:int) -> Side: return Side { p, new_bot(p), nil, nil }
def eco_side(p:int) -> Side: return Side { p, nil, EcoBot { p }, nil }

def think(s:Side):
    let l = s.lv
    if l: apply_level(l)
    let f = s.full
    if f: full_bot_think(f)
    let e = s.eco
    if e: bot_think(e)

def think_all(sides:[Side]):
    for(sides) s: think(s)

// ---- the bots' config: data/ai.json at a level, with a test's changes (Bot.new(p, cfg, level))

// load_ai_config (gen/start.lobster) at any level, after `tweak` has had the raw config (the test's
// changes, made before Bot.new applies the level).
def ai_config(lvl:string, tweak):
    let cfg0 = ai_ints(lib_data("ai.json"))
    tweak(cfg0)
    cfg_nums.clear()
    cfg_strs.clear()
    build_order = []
    wave_at = []
    wave_min = []
    var lv_ratio = 0
    var lv_wave = 100
    var lv_up = 0
    var lv_age3 = gint(at(cfg0, "economy"), "age3_workers", 26)
    var lv_tow = 0
    var lv_shelter = 0
    var lv_all = 0
    var lv_guard = 0
    var lv_raids_ = 0
    var lv_from = 0
    let levels = gobj(cfg0, "levels")
    if has(levels, lvl):
        let l = at(levels, lvl)
        for(glist(at(cfg0, "military"), "waves")) wv:
            set(wv, "at", jint(as_int(at(wv, "at")) + gint(l, "delay", 0)))
            set(wv, "min_army", jint(max(1, as_int(at(wv, "min_army")) * gint(l, "army_pct", 100) / 100)))
        let mil = at(cfg0, "military")
        let rm = at(mil, "repeat_min_army")
        if rm.kind == J_OBJ:
            for(rm.keys.length) n: rm.a[n] = jint(max(1, as_int(rm.a[n]) * gint(l, "army_pct", 100) / 100))
        else: set(mil, "repeat_min_army", jint(max(1, as_int(rm) * gint(l, "army_pct", 100) / 100)))
        if has(l, "max_workers"): set(at(cfg0, "economy"), "max_workers", at(l, "max_workers"))
        level_press(cfg0, l)
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
    ai_walk(cfg0, "", nums, strs)
    let smax = gobj(gobj(at(cfg0, "military"), "siege"), "max")
    strs.push("military.siege.max_order " + string(smax.keys.length) + (if smax.keys.length: " " + concat_string(smax.keys, " ") else: " "))
    let toks = [ "AI", string(nums.length), string(strs.length) ]
    for(nums) x: for(prompt_words(x)) t: toks.push(t)
    for(strs) x: for(prompt_words(x)) t: toks.push(t)
    let order = glist(cfg0, "build_order")
    toks.push("BUILD_ORDER")
    toks.push(string(order.length))
    for(order) st:
        toks.push(rstr(st, "building"))
        toks.push(gstr(st, "near", "-"))
        for([ gint(st, "age", 1), as_int(at(st, "workers")), gint(st, "count", -1), gint(st, "builders", 2), gint(st, "away", 0),
              gint(st, "own_side", 0), gint(st, "guard", 0), gint(st, "save", 0), gint(st, "push", -1), gint(st, "expand_workers", -1) ]) v: toks.push(string(v))
    let wvs = glist(at(cfg0, "military"), "waves")
    toks.push("WAVES")
    toks.push(string(wvs.length))
    for(wvs) wv:
        toks.push(string(as_int(at(wv, "at"))))
        toks.push(string(as_int(at(wv, "min_army"))))
    toks.push("LEVEL")
    for([ lv_ratio, lv_wave, lv_up, lv_age3, lv_tow, lv_all, lv_shelter, lv_guard, lv_raids_, lv_from ]) v: toks.push(string(v))
    tokens = toks
    tp = 0
    load_ai()

def level_config(lvl:string): ai_config(lvl) c: pass()

// The bots' waves never come, nor pressing a lead (D-198): a test of building up alone.
def no_waves(c:JV):
    for(glist(at(c, "military"), "waves")) wv: set(wv, "at", jint(1 << 20))
    set(at(at(c, "military"), "press"), "from", jint(1 << 20))

// What a level changes, as it stands now (to swap between two bots of different levels).
def level_now() -> LevelCfg:
    let keys = []::string
    let vals = []::int
    for(cfg_nums.get_keys()) key:
        if starts_with(key, "military.repeat_min_army") or starts_with(key, "economy.max_workers") or starts_with(key, "military.press"):
            keys.push(key)
            vals.push(cfg(key))
    return LevelCfg { copy(wave_at), copy(wave_min),
                      [ lv_army_ratio, lv_wave_pct, lv_build_up, lv_age3_workers, lv_towers, lv_all_in, lv_shelter_pop, lv_guard_crossing, lv_raids, lv_raid_from ],
                      keys, vals }

def apply_level(l:LevelCfg):
    wave_at = l.wave_at
    wave_min = l.wave_min
    lv_army_ratio = l.lv[0]
    lv_wave_pct = l.lv[1]
    lv_build_up = l.lv[2]
    lv_age3_workers = l.lv[3]
    lv_towers = l.lv[4]
    lv_all_in = l.lv[5]
    lv_shelter_pop = l.lv[6]
    lv_guard_crossing = l.lv[7]
    lv_raids = l.lv[8]
    lv_raid_from = l.lv[9]
    for(l.keys) key, n: cfg_nums.set(key, l.vals[n])

// ---- what GDScript's events said, read off the state

class Watch:
    research_was:[[int]] = []  // per player: researched, last tick
    ages_was:[int] = []
    hero_was:[int] = []  // per hero type: its id last tick
    fell_was:[int] = []
    carry_ids:[int] = []  // trade carts carrying gold, last tick
    carry_amt:[int] = []

class Happened:
    research_p:[int] = []  // research done this tick: player, research index
    research_k:[int] = []
    aged_p:[int] = []     // players that reached a new age this tick
    hero_up_n:[int] = []  // hero slots (hero_types) trained or revived this tick
    hero_revived:[int] = []
    hero_fell_n:[int] = []
    paid_p:[int] = []  // trade carts home: owner and gold
    paid:[int] = []

def new_watch() -> Watch:
    let w = Watch {}
    w.research_was = map(researched) r: copy(r)
    w.ages_was = copy(ages)
    w.hero_was = copy(hero_id)
    w.fell_was = copy(hero_fell)
    return w

// Before the step: the carts' loads.
def watch_before(w:Watch):
    w.carry_ids = []
    w.carry_amt = []
    for(u_id) uid, i:
        if t_trader[u_kind[i]] and u_carry[i] > 0:
            w.carry_ids.push(uid)
            w.carry_amt.push(u_carry[i])

// After the step: what happened.
def watch_after(w:Watch) -> Happened:
    let h = Happened {}
    for(researched) r, p:
        let was = w.research_was[p]
        for(r) v, k:
            if v != 0 and was[k] == 0:
                h.research_p.push(p)
                h.research_k.push(k)
                was[k] = v
    for(ages) a, p:
        if a > w.ages_was[p]:
            h.aged_p.push(p)
            w.ages_was[p] = a
    for(hero_id) hid, n:
        if hid != 0 and w.hero_was[n] == 0:
            h.hero_up_n.push(n)
            h.hero_revived.push(if w.fell_was[n] != 0: 1 else: 0)
        if hero_fell[n] != w.fell_was[n] and hero_fell[n] != 0: h.hero_fell_n.push(n)
        w.hero_was[n] = hid
        w.fell_was[n] = hero_fell[n]
    for(w.carry_ids) uid, n:
        let i = index_of(uid)
        if i >= 0 and u_carry[i] == 0:
            h.paid_p.push(u_owner[i])
            h.paid.push(w.carry_amt[n])
    return h
