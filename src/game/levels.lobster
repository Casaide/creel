// ------------------------------------------------------------------ the AIs' levels (data/ai.json "levels": the lobby's Easy, Normal, Hard)
// The bots' config is one set of globals (lib/ai_cfg.lobster), loaded at a level by load_ai_config (gen/start.lobster).
// What a level changes (the waves, the armies they wait for, the workers, the level's switches) is kept per player
// and put in place before that player's bot thinks, as the test kit does with two levels in one match.

class AiLevel:
    wave_at:[int]
    wave_min:[int]
    lv:[int]
    keys:[string]  // the config numbers a level changes (repeat_min_army..., max_workers...)
    vals:[int]

var ai_levels = []::AiLevel  // per player (empty: every bot at the config as loaded)

def ai_level_now() -> AiLevel:
    let keys = []::string
    let vals = []::int
    for(cfg_nums.get_keys()) key:
        if starts_with(key, "military.repeat_min_army") or starts_with(key, "economy.max_workers"):
            keys.push(key)
            vals.push(cfg(key))
    return AiLevel { copy(wave_at), copy(wave_min),
                     [ lv_army_ratio, lv_wave_pct, lv_build_up, lv_age3_workers, lv_towers, lv_all_in, lv_shelter_pop, lv_guard_crossing, lv_raids, lv_raid_from ],
                     keys, vals }

def ai_level_put(l:AiLevel):
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

// Each player's level ("" for a person: normal, unused); the config is left at the last one loaded.
def ai_levels_set(levels:[string]):
    ai_levels = map(levels) lvl:
        cfg_nums.clear()
        cfg_strs.clear()
        build_order = []
        wave_at = []
        wave_min = []
        load_ai_config(if lvl == "": "normal" else: lvl)
        ai_level_now()

// Before a bot thinks: its level in place.
def ai_level_for(p:int):
    if p < ai_levels.length: ai_level_put(ai_levels[p])
