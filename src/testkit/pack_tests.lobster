// ------------------------------------------------------------------ a pack's own tests (#190)
// A pack may carry tests/*.lua. Each `function test_<name>()` is a test, run in a fresh world the game makes, with the
// pack's rules and every invariant (testkit/invariants) checked on every tick. A test runs in phases: test_<name>, then
// test_<name>_2, _3 ... Each phase sets up or checks (place, give, spawn, expect, keep and kept, and everything a pack's
// rules may call), then says what to run before the next: wait(n) ticks, or wait_for(kind, max, a, b, c), an event
// (testkit's EV_NAMES). A test fails on an expect() that doesn't hold, an error, a broken invariant (with its tick and
// what broke), or an event that doesn't come in time.
//
//   pack_tests_of(id, make_world, one_tick) -> [string]   a line a test, "ok <name>" or "FAIL <name>: why"; [] if none
//     make_world(): a new world with the pack's rules (the game's new_world); one_tick(): one tick, the game's way
//   pack_tests(id, files, sources, make_world, one_tick)   the same for tests given as sources
//
// The tests' own functions (lua/api's place ... kept) are refused to a pack's rules. Imported by testkit/kit and the MCP.

// The tests in a pack's sources: each `function test_<name>(` that isn't a later phase (_2, _3, ...), in file order.
def pack_test_names(sources:[string]) -> [string]:
    let out = []::string
    for(sources) src:
        var at_ = 0
        while true:
            let k = find_string(src, "function test_", at_)
            if k < 0: break
            var e = k + 9
            while e < src.length and (src[e] == '_' or (src[e] >= 'a' and src[e] <= 'z') or (src[e] >= 'A' and src[e] <= 'Z') or (src[e] >= '0' and src[e] <= '9')): e++
            let name = substring(src, k + 9, e - k - 9)
            if not pack_test_phase(name) and (find(out) o: o == name) < 0: out.push(name)
            at_ = e
    return out

def pack_test_phase(name:string) -> bool:  // (test_x_2, test_x_3 ...)
    let u = find_string_reverse(name, "_")
    if u < 0 or u == name.length - 1: return false
    for(name.length - u - 1) j:
        let c = name[u + 1 + j]
        if c < '0' or c > '9': return false
    return true

def pack_test_match(e:Event) -> bool:
    if e.kind != lt_until: return false
    let abc = [ e.a, e.b, e.c ]
    for(3) f:
        if lt_until_set[f] and abc[f] != lt_until_abc[f]: return false
    return true

// One test: its phases, with the ticks between. "" if it passed, else why not.
def pack_test(name:string, make_world, one_tick) -> string:
    make_world()
    lua_rules = jobj()  // (the packs and their tests load again for this world)
    lt_keep_names = []
    lt_keep_vals = []
    inv_broken = ""
    events_on = true  // (what wait_for waits for)
    if not lua_fresh(): return "no Lua loaded"
    let at_ = find(l_packs) p: p.id == lua_test_id
    if at_ < 0: return "the tests didn\'t load"
    let pk = l_packs[at_]
    if pk.error != "": return pk.error
    var phase = 1
    while true:
        let fname = if phase == 1: name else: "{name}_{phase}"
        let f = lua_hook_fn(pk, fname)
        if f == LV_NIL: return if phase == 1: "no function {name}" else: ""
        lt_wait = 0
        lt_until = -1
        lt_failed = []
        lua_testing = true
        let ran = lua_hook_run(pk, f, [])
        lua_testing = false
        lua_region_end()
        if not ran: return "{fname}: {pk.error}"
        if lt_failed.length: return "{fname}: " + concat_string(lt_failed, "; ")
        for(l_packs) other:
            if other.error != "": return "the pack {other.id} stopped: {other.error}"
        var met = lt_until < 0
        var n = 0
        while n < lt_wait and not (lt_until >= 0 and met):
            inv_before()
            one_tick()
            n++
            let why = inv_after()
            if why != "": return "after {fname}, tick {tick - 1}: {why}"
            if lt_until >= 0:
                for(events) e: if pack_test_match(e): met = true
        if not met: return "after {fname}: no {ev_name(lt_until)} event in {lt_wait} ticks"
        phase++

def pack_tests(id:string, files:[string], sources:[string], make_world, one_tick) -> [string]:
    lua_test_id = id + ":tests"
    lua_test_files = files
    lua_test_sources = sources
    let out = []::string
    for(pack_test_names(sources)) name:
        let why = pack_test(name, make_world, one_tick)
        out.push(if why == "": "ok {name}" else: "FAIL {name}: {why}")
    lua_test_id = ""
    lua_test_files = []
    lua_test_sources = []
    lua_rules = jobj()
    return out

def pack_tests_of(id:string, make_world, one_tick) -> [string]:
    let at_ = find(lib_packs) p: p.id == id
    if at_ < 0: return [ "FAIL {id}: no such pack" ]
    let p = lib_packs[at_]
    pack_lua(p)
    if not p.test_files.length: return []
    return pack_tests(id, map(p.test_files) f: id + "/tests/" + f, p.test_sources): make_world()
    fn: one_tick()
