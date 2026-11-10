// ------------------------------------------------------------------ commands (World._run, the order queues)
// A command runs for the player's own units. Shift-queued (queue 1): a busy unit keeps it in its own
// queue (units.orders) and takes it when it's done (next_orders); idle ones act now. A plain order
// empties the queues of the units it's for. A group MOVE / ATTACK_MOVE gets its formation first, and
// each queued copy keeps its own slot. Left out: walls you stand on (World._wall_orders).

let QUEUEABLE = [ CMD_MOVE, CMD_GATHER, CMD_BUILD, CMD_HELP_BUILD, CMD_ATTACK, CMD_ATTACK_MOVE, CMD_DROP_OFF, CMD_GARRISON, CMD_REPAIR ]

// Doing something: a job, a move, a fight, or a way along or off a wall (World.busy).
def busy(i:int) -> bool:
    return u_task[i] != T_NONE or u_moving[i] == 1 or u_foe[i] != 0 or u_patient[i] != 0 or wall_busy(i)

let WALL_ORDERS = [ CMD_MOVE, CMD_ATTACK, CMD_ATTACK_MOVE, CMD_GATHER, CMD_BUILD, CMD_HELP_BUILD, CMD_DROP_OFF, CMD_GARRISON, CMD_PEN, CMD_RESEED, CMD_REPAIR ]

// Where an order sends a unit (milli-tiles), for climbing down towards it; -1, -1 if nowhere (World._order_point).
def order_point(c:Cmd) -> int, int:
    switch c.code:
        case CMD_MOVE, CMD_ATTACK_MOVE: return if c.slotted == 1: c.sx else: c.a, if c.slotted == 1: c.sy else: c.b
        case CMD_GATHER: return centre(c.a)
        case CMD_BUILD: return c.b * TILE + TILE / 2, c.c * TILE + TILE / 2
        default:
            let j = index_of(c.a)
            if j >= 0: return u_x[j], u_y[j]
            let b = b_index_of(c.a)
            if b >= 0: return b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2
            return -1, -1

// Walls you stand on, before an order runs (World._wall_orders): a MOVE onto a walkway sends those
// who may climb up; an ATTACK on a foe up on a wall sends melee up to it; a unit up on a wall given
// anything else climbs down first (the order waits in its queue). Returns the order for the rest.
def wall_orders(c:Cmd) -> Cmd:
    let p = c.player
    let now = []::int
    for(c.ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and not (c.queue == 1 and busy(i)): now.push(uid)
    let done = []::int
    if c.code == CMD_MOVE:
        let goal = walkway_at(if c.slotted == 1: c.sx else: c.a, if c.slotted == 1: c.sy else: c.b)
        if goal >= 0:
            for(order_onto(p, now, goal)) uid:
                done.push(uid)
                if c.queue == 0: u_orders[index_of(uid)] = []::Cmd
    let foe = if c.code == CMD_ATTACK: index_of(c.a) else: -1
    if foe >= 0 and u_perch[foe] != 0:
        let climbers = filter(now) uid: u_perch[index_of(uid)] == 0 and not t_ranged[u_kind[index_of(uid)]]
        for(order_onto(p, climbers, u_perch[foe] - 1)) uid:
            done.push(uid)
            let one = Cmd { c.run_tick, CMD_ATTACK, p, c.a, 0, 0, 0, [ uid ], c.seq }
            u_orders[index_of(uid)] = [ one ]
    for(now) uid:
        let i = index_of(uid)
        if not contains(done, uid) and u_perch[i] != 0:
            let shoots_or_reaches = c.code == CMD_ATTACK and (t_ranged[u_kind[i]] or (foe >= 0 and u_perch[foe] != 0 and on_net(dist_from(u_perch[i] - 1), u_perch[foe] - 1)))
            if not shoots_or_reaches:
                done.push(uid)
                let ax, ay = order_point(c)
                if ax >= 0 and wall_leave(i, ax, ay):
                    if c.queue == 0: u_orders[i] = []::Cmd
                    if c.code != CMD_MOVE:  // (a move is where it walks once down)
                        let one = copy_cmd(c, [ uid ])
                        one.queue = 0
                        u_orders[i].insert(0, one)
    if not done.length: return c
    let out = copy_cmd(c, filter(c.ids) uid: not contains(done, uid))
    return out

def copy_cmd(c:Cmd, ids:[int]) -> Cmd:
    let o = Cmd { c.run_tick, c.code, c.player, c.a, c.b, c.c, c.d, ids, c.seq }
    o.queue = c.queue
    o.slotted = c.slotted
    o.sx = c.sx
    o.sy = c.sy
    o.group = c.group
    o.fx = c.fx
    o.fy = c.fy
    o.pace = c.pace
    return o

// The ids that act now (World._queue_or_clear); `formed`: slots just dealt (slot_x / slot_y).
def queue_or_clear(c:Cmd, formed:bool) -> [int]:
    let now = []::int
    for(c.ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == c.player:
            if c.queue == 1 and busy(i):
                let one = copy_cmd(c, [ uid ])
                one.queue = 0
                if formed:
                    one.slotted = 1
                    one.sx = slot_x[i]
                    one.sy = slot_y[i]
                u_orders[i].push(one)
            else:
                if c.queue == 0: u_orders[i] = []::Cmd
                now.push(uid)
    return now

// The building type a BUILD of type k places now (Economy.btype_of, then what research made it).
def build_type(p:int, k:int) -> int: return if k < 0: -1 else: upgraded_type(p, k)

def refund(p:int, cost:[int]):
    for(cost) v, r: stock[r][p] += v

// What a building's queue entry cost: a unit type, or research / the age-up (Tech.entry_cost).
def entry_cost(p:int, e:int) -> [int]:
    if e >= 0: return unit_cost(e)
    let t = tech_of(e)
    return if t == AGE_UP_ENTRY: ages_list[next_age(p)].cost else: research_cost(p, t)

def cmd_cancel(p:int, bid:int, n:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p: return
    let q = b_queue[b]
    if n < 0 or n >= q.length: return
    refund(p, entry_cost(p, q[n]))
    q.remove(n)
    if n == 0: b_train[b] = 0

// Workers take what they carry to that building, then go back to gathering (Economy.cmd_drop_off).
def cmd_drop_off(p:int, ids:[int], bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != p or b_done[b] == 0: return
    let k = b_kind[b]
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p:
            if not (is_worker(i) and u_carry[i] > 0 and u_carry_kind[i] > 0 and bt_drop[k][u_carry_kind[i] - 1] == 1):
                clear_task(i)
                approach_building(i, b)
            else:
                if u_task[i] != GATHER and u_task[i] != T_RETURN: u_home[i] = -1
                u_task[i] = T_RETURN
                u_target[i] = bid
                u_work[i] = 0
                approach_building(i, b)

// Drop everything: no move, no job, no fight, no queued orders.
def cmd_stop(p:int, ids:[int]):
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p:
            clear_task(i)
            combat_clear(i)
            u_orders[i] = []::Cmd
            u_moving[i] = 0
            wall_stop(i)

var cmd_log = false

def run(c0:Cmd):
    var c = c0
    let p = c.player
    if cmd_log:
        var s = "cmd {c.run_tick} {c.code} {c.player} {c.queue} {c.a} {c.b} {c.c} {c.d} {c.ids.length}"
        for(c.ids) id: s += " {id}"
        print s
    if c.code == CMD_BUILD and c.queue == 1:
        // Shift-placed: the foundation goes down now; building it joins each unit's queue.
        let bid = lay_foundation(p, c.ids, build_type(p, c.a), c.b, c.c, c.d)
        if bid == 0: return
        c = Cmd { c.run_tick, CMD_HELP_BUILD, p, bid, 0, 0, 0, c.ids, c.seq }
        c.queue = 1
    if contains(WALL_ORDERS, c.code):
        let a = wall_orders(c)
        if not a.ids.length and c.ids.length: return  // (every unit dealt with there)
        c = a
    var formed = false
    if (c.code == CMD_MOVE or c.code == CMD_ATTACK_MOVE) and c.slotted == 0:
        if c.queue == 0:
            let attack = c.code == CMD_ATTACK_MOVE
            let others = filter(c.ids) uid:
                let i = index_of(uid)
                i < 0 or u_owner[i] != p or not block_same_order(i, attack, c.a, c.b)
            if not others.length: return
            c = copy_cmd(c, others)
        c = copy_cmd(c, c.ids)
        let group, fx, fy, pace = formation(p, c.ids, c.a, c.b)
        c.group = group
        c.fx = fx
        c.fy = fy
        c.pace = pace
        formed = true
    var ids = c.ids
    if contains(QUEUEABLE, c.code):
        ids = queue_or_clear(c, formed)
        if not ids.length: return
    if c.slotted == 1:
        for(ids) uid:
            let i = index_of(uid)
            if i >= 0:
                slot_x[i] = c.sx
                slot_y[i] = c.sy
                slot_block[i] = 0
    switch c.code:
        case CMD_MOVE: run_move(p, ids, c.group, c.fx, c.fy, c.pace)
        case CMD_ATTACK_MOVE: run_attack_move(p, ids, c.group, c.fx, c.fy, c.pace)
        case CMD_STANCE: run_stance(p, ids, c.a)
        case CMD_GATHER: cmd_gather(p, own_units_cleared(p, ids), c.a)
        case CMD_BUILD: cmd_build(p, own_units_cleared(p, ids), build_type(p, c.a), c.b, c.c, c.d)
        case CMD_HELP_BUILD: cmd_help_build(p, own_units_cleared(p, ids), c.a)
        case CMD_TRAIN: cmd_train(p, c.a, c.b, c.c)
        case CMD_RALLY: cmd_rally(p, c.a, c.b, c.c)
        case CMD_RESEED: cmd_reseed(p, ids, c.a)
        case CMD_AGE_UP: cmd_age_up(p, c.a)
        case CMD_RESEARCH: cmd_research(p, c.a, c.b)
        case CMD_CALL_TO_ARMS: cmd_call_to_arms(p, c.a)
        case CMD_BACK_TO_WORK: cmd_back_to_work(p)
        case CMD_ATTACK: cmd_attack(p, filter(ids) uid: index_of(uid) >= 0 and u_owner[index_of(uid)] == p, c.a)
        case CMD_STOP: cmd_stop(p, ids)
        case CMD_CANCEL: cmd_cancel(p, c.a, c.b)
        case CMD_DROP_OFF: cmd_drop_off(p, own_units_cleared(p, ids), c.a)
        case CMD_SURRENDER:
            if defeated[p] == 0: defeated[p] = tick + 1
        case CMD_AUTO_RESEED: auto_reseed[p] = if c.a == 1: 1 else: 0
        case CMD_TRADE: cmd_trade(p, c.a, c.b, c.c == 1)
        case CMD_ROUTE: cmd_route(p, ids, c.a)
        case CMD_REPAIR: cmd_repair(p, own_units_cleared(p, ids), c.a)
        case CMD_PEN: cmd_pen(p, ids, c.a)
        case CMD_ABILITY: cmd_ability(p, ids, c.a, c.b)
        case CMD_RELEASE: cmd_release(p, c.a)
        case CMD_GARRISON: cmd_garrison(p, own_units_cleared(p, ids), c.a)
        case CMD_UNGARRISON: cmd_ungarrison(p, c.a)
        default:
            assert c.code >= HOOK_ORDER_BASE
            hook_on_order(c.code, p, ids, c.a, c.b)

// Units that have finished what they were doing take their next queued order; a queued BUILD whose
// foundation another unit already laid becomes "help build" (World._next_orders).
def next_orders():
    for(u_x.length) i:
        if u_orders[i].length and not busy(i):
            var o = u_orders[i][0]
            u_orders[i].remove(0)
            let p = u_owner[i]
            if o.code == CMD_BUILD:
                let bid = occupied[o.c * W + o.b]
                let b = b_index_of(bid)
                if b >= 0 and b_owner[b] == p and b_done[b] == 0 and o.a >= 0 and b_kind[b] == upgraded_type(p, o.a):
                    o = Cmd { o.run_tick, CMD_HELP_BUILD, p, bid, 0, 0, 0, o.ids, o.seq }
            let r = copy_cmd(o, o.ids)
            r.queue = 1  // run now (the unit's free) without wiping the rest of its queue
            run(r)

// A queued order as the hash sees it (export.gd order_ints).
def order_ints(o:Cmd) -> [int]:
    return [ o.code, o.a, o.b, o.c, o.d, o.slotted, o.sx, o.sy, o.group, o.fx, o.fy, o.pace ]
