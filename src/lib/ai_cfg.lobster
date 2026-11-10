// ------------------------------------------------------------------ the bot's config (data/ai.json)
// As export.gd _write_ai writes it: numbers by path ("military.defend_tiles"), string lists by
// path, the build order and waves as rows, the level's fields (Bot.new with level "normal").

class Bot  // (declared ahead: the AI modules refer to each other)
class Land
class Expand

let cfg_nums = dictionary<string, int>(509)
let cfg_strs = dictionary<string, [string]>(127)

class Step:
    building:string
    near:string  // "-": none
    age:int
    workers:int
    count:int  // -1: one more than the steps before it for this building
    builders:int
    away:int
    own_side:int
    guard_step:int
    save:int
    push:int            // -1: economy.build_push
    expand_workers:int  // -1: none

var build_order = []::Step
var wave_at = []::int
var wave_min = []::int
var lv_army_ratio = 0
var lv_wave_pct = 100
var lv_build_up = 0
var lv_age3_workers = 26
var lv_towers = 0
var lv_all_in = 0
var lv_shelter_pop = 0
var lv_guard_crossing = 0
var lv_raids = 0
var lv_raid_from = 0

def cfg(path:string) -> int:
    let v = cfg_nums.get(path, -(1 << 40))
    assert v != -(1 << 40)
    return v

def cfg_or(path:string, fallback:int) -> int: return cfg_nums.get(path, fallback)

def has_cfg(path:string) -> bool: return cfg_nums.get(path, -(1 << 40)) != -(1 << 40)

def cfg_list(path:string) -> [string]: return cfg_strs.get(path) or []::string

// A number given per age (`prefix.1`, `prefix.2`...) or once (`prefix`): the best (most) for
// ages up to `age`, from `floor` (Bot._max_workers, _repeat_min).
def per_age(prefix:string, age:int, floor:int) -> int:
    if has_cfg(prefix): return cfg(prefix)
    var best = floor
    var a = 1
    while a <= age:
        best = max(best, cfg_or("{prefix}.{a}", -(1 << 40)))
        a++
    return best

def load_ai():
    expect("AI")
    let nn = next_int()
    let ns = next_int()
    for(nn):
        let path = tokens[tp]
        tp++
        cfg_nums.set(path, next_int())
    for(ns):
        let path = tokens[tp]
        tp++
        let n = next_int()
        let out = []::string
        for(n):
            out.push(tokens[tp])
            tp++
        cfg_strs.set(path, out)
    expect("BUILD_ORDER")
    for(next_int()):
        let building = tokens[tp]
        let near = tokens[tp + 1]
        tp += 2
        let v = read_ints(10)
        build_order.push(Step { building, near, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9] })
    expect("WAVES")
    for(next_int()):
        wave_at.push(next_int())
        wave_min.push(next_int())
    expect("LEVEL")
    lv_army_ratio = next_int()
    lv_wave_pct = next_int()
    lv_build_up = next_int()
    lv_age3_workers = next_int()
    lv_towers = next_int()
    lv_all_in = next_int()
    lv_shelter_pop = next_int()
    lv_guard_crossing = next_int()
    lv_raids = next_int()
    lv_raid_from = next_int()
