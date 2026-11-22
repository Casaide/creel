// ------------------------------------------------------------------ the MCP's sim side (#196)
// One headless sim, driven one request at a time from mcp/creel-mcp.js, which speaks MCP to an agent. A request is a line
// of JSON on stdin ({"id": n, "cmd": "...", ...}); a long one comes as lines starting with "+", the last without. Each
// reply is one line on stdout starting with MCP_PREFIX, so the compiler's and the game's own prints pass by it.
//
// What any game on Creel can be asked is here: step, order, the state and its hash. How a match starts, how one tick
// runs and how a save is made are the game's, through these hooks, which a game defines before importing this:
//   mcp_start(args:JV) -> string   a fresh match from the agent's args; "" or why not
//   mcp_step()                     one tick, the game's way (bots, the sim's step, anything else a tick runs)
//   mcp_save(path:string) -> string, mcp_load(path:string) -> string   "" or why not
// examples/plain/src/mcp_server.lobster is the smallest game side.
//
// Imported after every sim module. Nothing here writes the sim's state except through issue_cmd, as a player's order.

import testkit.invariants
import testkit.pack_tests

let MCP_PREFIX = "@mcp "
let MCP_MAX_STEP = 72000  // one hour of ticks a request at most

// The command codes by name, in their order in lib/consts (CMD_MOVE is 0).
let MCP_CMD_NAMES = [ "move", "attack_move", "stance", "gather", "build", "help_build", "train", "rally", "reseed", "age_up",
    "research", "call_to_arms", "back_to_work", "attack", "stop", "cancel", "drop_off", "surrender", "auto_reseed", "garrison",
    "ungarrison", "repair", "trade", "route", "pen", "release", "ability", "demolish" ]

var mcp_started = false
let MCP_EVENTS_KEPT = 20000  // the events kept for creel_events, newest (older ones are dropped and counted)
var mcp_events = []::Event
var mcp_event_ticks = []::int
var mcp_events_dropped = 0

def mcp_ev_name(k:int) -> string: return ev_name(k)

def mcp_ev_kind(v:JV) -> int:  // (a name or a code)
    if v.kind == J_STR:
        return ev_kind(v.s)
    return as_int(v)

// One tick the game's way, its events kept.
def mcp_tick():
    mcp_step()
    for(events) e:
        mcp_events.push(e)
        mcp_event_ticks.push(tick - 1)
    if mcp_events.length > MCP_EVENTS_KEPT:
        let n = mcp_events.length - MCP_EVENTS_KEPT
        mcp_events.remove_range(0, n)
        mcp_event_ticks.remove_range(0, n)
        mcp_events_dropped += n

def mcp_ev_matches(q:JV, e:Event) -> bool:
    let kinds = glist(q, "kinds")
    if kinds.length:
        let wanted = exists(kinds) kv: mcp_ev_kind(kv) == e.kind
        if not wanted: return false
    if has(q, "a") and gint(q, "a", 0) != e.a: return false
    if has(q, "b") and gint(q, "b", 0) != e.b: return false
    if has(q, "c") and gint(q, "c", 0) != e.c: return false
    return true

def mcp_event(e:Event, t:int) -> JV:
    let o = jobj()
    o.set("tick", jint(t))
    o.set("kind", jstr(mcp_ev_name(e.kind)))
    o.set("a", jint(e.a))
    o.set("b", jint(e.b))
    o.set("c", jint(e.c))
    o.set("n", jint(e.n))
    o.set("x", jint(e.x))
    o.set("y", jint(e.y))
    return o

// The events kept since the last start, filtered by kinds (names or codes), a, b, c and since (a tick), at most limit.
def mcp_events_of(q:JV) -> JV:
    let out = []::JV
    let since = gint(q, "since", 0)
    let limit = gint(q, "limit", 200)
    var total = 0
    for(mcp_events) e, k:
        if mcp_event_ticks[k] >= since and mcp_ev_matches(q, e):
            total++
            if out.length < limit: out.push(mcp_event(e, mcp_event_ticks[k]))
    let o = jobj()
    o.set("total", jint(total))
    o.set("dropped", jint(mcp_events_dropped))
    o.set("events", jarr(out))
    return o

def mcp_reply(id:int, ok:bool, v:JV):
    let o = jobj()
    o.set("id", jint(id))
    o.set("ok", jbool(ok))
    o.set(if ok: "result" else: "error", v)
    print MCP_PREFIX + stringify(o)
    flush_output()

def mcp_ints(xs:[int]) -> JV: return jarr(map(xs) x: jint(x))

// One request: its lines joined. "" at the end of input.
def mcp_read() -> string:
    var s = ""
    while true:
        let line = get_line("")
        if not line.length: return ""
        if line[0] == '+':
            s += substring(line, 1, line.length - 1)
        else:
            return s + line

def mcp_in_rect(o:JV, x:int, y:int) -> bool:
    let r = glist(o, "rect")  // [x0, y0, x1, y1] in sim units (TILE a tile)
    if r.length != 4: return true
    return x >= as_int(r[0]) and y >= as_int(r[1]) and x <= as_int(r[2]) and y <= as_int(r[3])

def mcp_wanted(o:JV, key:string, v:int) -> bool:
    let xs = glist(o, key)
    if not xs.length: return true
    return exists(xs): as_int(_) == v

def mcp_state() -> JV:
    let o = jobj()
    o.set("tick", jint(tick))
    o.set("hash", jint(state_hash()))
    o.set("started", jbool(mcp_started))
    return o

def mcp_unit(i:int) -> JV:
    let o = jobj()
    o.set("id", jint(u_id[i]))
    o.set("kind", jint(u_kind[i]))
    o.set("type", jstr(if u_kind[i] < t_slot.length: t_slot[u_kind[i]] else: ""))
    o.set("owner", jint(u_owner[i]))
    o.set("x", jint(u_x[i]))
    o.set("y", jint(u_y[i]))
    o.set("hp", jint(u_hp[i]))
    o.set("task", jint(u_task[i]))
    o.set("target", jint(u_target[i]))
    o.set("carry", jint(u_carry[i]))
    o.set("carry_kind", jint(u_carry_kind[i]))
    o.set("moving", jint(u_moving[i]))
    o.set("stuck", jint(u_stuck[i]))
    o.set("work", jint(u_work[i]))
    o.set("orders", jint(u_orders[i].length))
    return o

def mcp_building(b:int) -> JV:
    let o = jobj()
    o.set("id", jint(b_id[b]))
    o.set("kind", jint(b_kind[b]))
    o.set("type", jstr(if b_kind[b] < bt_name.length: bt_name[b_kind[b]] else: ""))
    o.set("owner", jint(b_owner[b]))
    o.set("cx", jint(b_cx[b]))
    o.set("cy", jint(b_cy[b]))
    o.set("hp", jint(b_hp[b]))
    o.set("done", jint(b_done[b]))
    o.set("progress", jint(b_progress[b]))
    o.set("site", jbool(b_site[b].length > 0))
    if b_hold[b].length: o.set("hold", mcp_ints(b_hold[b]))
    if b_want[b].length: o.set("want", mcp_ints(b_want[b]))
    if b_coming[b].length: o.set("coming", mcp_ints(b_coming[b]))
    if b_site[b].length: o.set("site_needs", mcp_ints(b_site[b]))
    return o

// Units or buildings, filtered by ids, owner, kind and a rect, at most limit (200 by default).
def mcp_units(q:JV) -> JV:
    let out = []::JV
    let limit = gint(q, "limit", 200)
    var total = 0
    for(u_id) uid, i:
        if mcp_wanted(q, "ids", uid) and mcp_wanted(q, "owner", u_owner[i]) and mcp_wanted(q, "kind", u_kind[i]) and
           mcp_in_rect(q, u_x[i], u_y[i]):
            total++
            if out.length < limit: out.push(mcp_unit(i))
    let o = jobj()
    o.set("total", jint(total))
    o.set("units", jarr(out))
    return o

def mcp_buildings(q:JV) -> JV:
    let out = []::JV
    let limit = gint(q, "limit", 200)
    var total = 0
    for(b_id) bid, b:
        if mcp_wanted(q, "ids", bid) and mcp_wanted(q, "owner", b_owner[b]) and mcp_wanted(q, "kind", b_kind[b]) and
           mcp_in_rect(q, b_cx[b] * TILE, b_cy[b] * TILE):
            total++
            if out.length < limit: out.push(mcp_building(b))
    let o = jobj()
    o.set("total", jint(total))
    o.set("buildings", jarr(out))
    return o

def mcp_players() -> JV:
    let out = []::JV
    for(pop) n, p:
        let o = jobj()
        o.set("player", jint(p))
        o.set("pop", jint(n))
        o.set("pop_cap", jint(if p < pop_cap.length: pop_cap[p] else: 0))
        let st = jobj()
        for(resource_names) r, k:
            if k < stock.length and p < stock[k].length: st.set(r, jint(stock[k][p]))
        o.set("stock", st)
        out.push(o)
    return jarr(out)

def mcp_cell(q:JV) -> string, JV:
    let cx = gint(q, "cx", -1)
    let cy = gint(q, "cy", -1)
    if cx < 0 or cy < 0 or cx >= W or cy >= H: return "no cell {cx}, {cy} on a {W} x {H} map", jnull()
    let c = cy * W + cx
    let o = jobj()
    o.set("cx", jint(cx))
    o.set("cy", jint(cy))
    o.set("road", jint(if road.length: road[c] else: 0))
    o.set("occupied", jint(if c < occupied.length: occupied[c] else: 0))
    o.set("amount", jint(if c < amount.length: amount[c] else: 0))
    o.set("resource", jint(if c < amount.length: res_at(c) else: -1))
    return "", o

def mcp_names() -> JV:
    let o = jobj()
    o.set("unit_types", jstrs(t_slot))
    o.set("building_types", jstrs(bt_name))
    o.set("resources", jstrs(resource_names))
    o.set("commands", jstrs(MCP_CMD_NAMES))
    o.set("tile", jint(TILE))
    o.set("ticks_per_turn", jint(TICKS_PER_TURN))
    o.set("map", mcp_ints([ W, H ]))
    o.set("events", jstrs(EV_NAMES))
    return o

// A player's order, run at the start of turn + 2 like every order.
def mcp_order(q:JV) -> string, JV:
    let p = gint(q, "player", 0)
    if p < 0 or p >= next_seq.length: return "no player {p}", jnull()
    var code = -1
    let cv = q.get("command")
    if cv:
        if cv.kind == J_STR: code = find(MCP_CMD_NAMES): _ == cv.s
        else: code = as_int(cv)
    if code < 0 or (code >= MCP_CMD_NAMES.length and code < HOOK_ORDER_BASE):
        return "no command {if cv: stringify(cv) else: "(none)"}; the names are in creel_names", jnull()
    let ids = map(glist(q, "ids")) v: as_int(v)
    issue_cmd(p, code, ids, gint(q, "a", 0), gint(q, "b", 0), gint(q, "c", 0), gint(q, "d", 0), gint(q, "queue", 0))
    let o = jobj()
    o.set("runs_at", jint((tick / TICKS_PER_TURN + 2) * TICKS_PER_TURN))
    o.set("command", jint(code))
    return "", o

def mcp_handle(q:JV) -> string, JV:
    let cmd = gstr(q, "cmd", "")
    if cmd == "start":
        let err = mcp_start(gobj(q, "args"))
        if err.length: return err, jnull()
        mcp_started = true
        events_on = true
        mcp_events = []
        mcp_event_ticks = []
        mcp_events_dropped = 0
        return "", mcp_state()
    if cmd == "pack_tests":  // (#190: a pack's tests/*.lua, each in a fresh match from args; the last one's is left running)
        let id = gstr(q, "pack", "")
        if (find(lib_packs) p: p.id == id) < 0: return "no pack \"{id}\" (packs: {concat_string(map(lib_packs) p: p.id, ", ")})", jnull()
        var why = ""
        let ran = pack_tests_of(id):
            let err = mcp_start(gobj(q, "args"))
            if why == "": why = err
        fn: mcp_step()
        if why != "": return why, jnull()
        if not ran.length: return "the pack {id} has no tests (data/tests/*.lua)", jnull()
        mcp_started = true
        events_on = true
        let o = mcp_state()
        o.set("tests", jstrs(ran))
        o.set("failed", jint((filter(ran) l: starts_with(l, "FAIL")).length))
        return "", o
    if cmd == "state": return "", mcp_state()
    if cmd == "names": return "", mcp_names()
    if not mcp_started: return "no match yet: start one first", jnull()
    switch cmd:
        case "step":
            let n = gint(q, "ticks", 1)
            if n < 1 or n > MCP_MAX_STEP: return "ticks must be 1 to {MCP_MAX_STEP}", jnull()
            let checked = gbool(q, "invariants", false)
            inv_stuck_limit = gint(q, "stuck_limit", inv_stuck_limit)
            let until = gobj(q, "until")  // (an event to stop on: kinds, a, b, c as creel_events filters)
            let stopping = has(q, "until")
            var broken = ""
            var met = jnull()
            for(n):
                if broken == "" and met.kind == J_NULL:
                    if checked: inv_before()
                    mcp_tick()
                    if checked: broken = inv_after()
                    if stopping:
                        for(events) e: if met.kind == J_NULL and mcp_ev_matches(until, e): met = mcp_event(e, tick - 1)
            let o = mcp_state()
            if checked: o.set("broken", jstr(broken))  // (the first invariant broken, on the tick the state gives: the run stops there)
            if stopping: o.set("event", met)  // (the event it stopped on, or null if none came)
            return "", o
        case "events": return "", mcp_events_of(q)
        case "invariants":
            inv_before()  // (no tick: nobody moved, so "solid" has nothing to compare)
            let o = mcp_state()
            o.set("names", jstrs(INV_NAMES))
            o.set("broken", jstr(inv_after()))
            return "", o
        case "order": return mcp_order(q)
        case "units": return "", mcp_units(q)
        case "buildings": return "", mcp_buildings(q)
        case "players": return "", mcp_players()
        case "cell": return mcp_cell(q)
        case "save", "load":
            let path = gstr(q, "path", "")
            if not path.length: return "no path", jnull()
            let err = if cmd == "save": mcp_save(path) else: mcp_load(path)
            if err.length: return err, jnull()
            return "", mcp_state()
        default: return "no command \"{cmd}\"", jnull()

// Serve until stdin ends or a "quit" comes.
def mcp_serve():
    print MCP_PREFIX + "\{\"ready\":true\}"
    flush_output()
    while true:
        let line = mcp_read()
        if not line.length: return
        let q = parse_json(line)
        let id = gint(q, "id", 0)
        if gstr(q, "cmd", "") == "quit":
            mcp_reply(id, true, jnull())
            return
        let err, v = mcp_handle(q)
        mcp_reply(id, not err.length, if err.length: jstr(err) else: v)
