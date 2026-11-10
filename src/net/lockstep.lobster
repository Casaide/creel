// ------------------------------------------------------------------ lockstep over TCP (src/net/lockstep.gd, enet.gd)
// Every player runs the same world and only commands travel. A command is stamped with the turn it
// was issued in and runs two turns later (issue_cmd), so at the end of each turn this sends the
// turn's local commands with a mark that the turn is done and the state hashes taken since; a turn
// may only start once every player's turn two before it is in (may_run). A late player holds
// everyone's world still; a hash that differs is a desync. The host sends the whole world first
// (gen/save.lobster's record), so the one who joins starts from exactly the host's set-up match.
// Messages are framed: a kind letter, a 4-byte length (little-endian), a flexbuffer.

let NET_PORT = 47816
let HASH_EVERY = 40  // ticks between the hashes sent

class TurnMsg:
    player:int
    turn:int
    cmds:[Cmd]
    hashes:[int]  // tick, hash, tick, hash...

class Link:
    sock:resource<tcpsocket>? = nil
    listener:resource<tcplistener>? = nil
    connected = false
    out = ""
    inb = ""
    closed = false
    error = ""

class Lockstep:
    link:Link
    me:int
    players:[int]  // seats that send commands (people; a bot seat needs none, it's deterministic)
    done:[int]     // per player: the last turn whose commands are all in
    hashes_out = []::int
    theirs = dictionary<int, int>(64)
    mine = dictionary<int, int>(64)
    desync = ""
    first_seq = 0    // our first command this link carries
    more = []::Link  // a host's other players' links (more than two people: a star round the host)
    relay = false    // the host: every turn that comes in goes on to the others

def net_host(port:int) -> Link:
    let l, err = tcp.listen("0.0.0.0", port)
    let link = Link {}
    link.listener = l
    if err: link.error = err
    return link

def net_join(ip:string, port:int) -> Link:
    let s, err = tcp.connect(ip, port)
    let link = Link {}
    link.sock = s
    if err: link.error = err
    return link

// Make the link go: accept the one who joins, finish connecting. True once it carries data.
def net_ready(link:Link) -> bool:
    if link.connected: return true
    let l = link.listener
    if l and not link.sock:
        let s, err = tcp.accept(l)
        if err: link.error = err
        if s:
            link.sock = s
            link.connected = true
        return link.connected
    let s = link.sock
    if s:
        let ok, err = tcp.connected(s)
        if err: link.error = err
        link.connected = ok
    return link.connected

def net_send(link:Link, kind:int, payload:string):
    let head = ensure_size(unicode_to_string([ kind ]), 5, 0)  // (the kind's an ASCII letter: one byte)
    let h, _ = write_int32_le(head, 1, payload.length)
    link.out += h + payload
    net_flush(link)

// Push out what's waiting, and take in what came; frames are returned whole as [kind, payload].
def net_flush(link:Link):
    let s = link.sock
    if not s or not link.connected: return
    while link.out.length:
        let n, err = tcp.send(s, link.out)
        if err:
            link.closed = true
            link.error = err
            return
        if n <= 0: return
        link.out = link.out.substring(n, link.out.length - n)

// Frames taken but not handled yet go back on the link, in order (a turn that came with the match).
def net_unread(link:Link, frames:[[string]]):
    var back = ""
    for(frames) f:
        let head = ensure_size(f[0], 5, 0)
        let h, _ = write_int32_le(head, 1, f[1].length)
        back += h + f[1]
    link.inb = back + link.inb

def net_poll(link:Link) -> [[string]]:
    net_flush(link)
    let frames = []::[string]
    let s = link.sock
    if not s or not link.connected: return frames
    while true:
        let data, err = tcp.receive(s, 1048576)
        if err:
            link.closed = true
            link.error = err
            break
        if not data: break
        if data == "":  // (an empty read: the other end has closed)
            link.closed = true
            break
        link.inb += data
    while link.inb.length >= 5:
        let len, _ = read_int32_le(link.inb, 1)
        if link.inb.length < 5 + len: break
        frames.push([ unicode_to_string([ link.inb[0] ]), link.inb.substring(5, len) ])
        link.inb = link.inb.substring(5 + len, link.inb.length - 5 - len)
    return frames

def new_lockstep(link:Link, me:int, players:[int]) -> Lockstep:
    let ls = Lockstep { link, me, players, map(num_players): tick / TICKS_PER_TURN - 1 }
    ls.first_seq = next_seq[me]
    return ls

def check_hashes(ls:Lockstep):
    for(ls.theirs.get_keys()) t:
        let m = ls.mine.get(t, -1)
        if m >= 0:
            if m != ls.theirs.get(t, -1) and ls.desync == "": ls.desync = "the state differs at tick {t}"
            ls.theirs.del(t)
            ls.mine.del(t)

// Take what came: the others' commands into the queue, their hashes checked. Other frames
// (not turns) are returned for the caller.
def ls_links(ls:Lockstep) -> [Link]: return append([ ls.link ], ls.more)

def ls_receive(ls:Lockstep) -> [[string]]:
    let rest = []::[string]
    let links = ls_links(ls)
    for(links) src, li:
        for(net_poll(src)) f:
            if f[0] == "T" and ls.relay:  // (the host passes each player's turn on to the others)
                for(links) to, lj:
                    if lj != li: net_send(to, 'T', f[1])
            if f[0] == "T":
                let v, err = flexbuffers_binary_to_value(typeof TurnMsg, f[1])
                let m = v
                if err or not m: ls.desync = "a turn that will not read: {err}"
                else:
                    if m.turn != ls.done[m.player] + 1: ls.desync = "turn {ls.done[m.player] + 1} from player {m.player + 1} missing (got {m.turn})"
                    for(m.cmds) c:
                        pending.push(c)
                        next_seq[c.player] = max(next_seq[c.player], c.seq + 1)
                    ls.done[m.player] = m.turn
                    var k = 0
                    while k + 1 < m.hashes.length:
                        ls.theirs.set(m.hashes[k], m.hashes[k + 1])
                        k += 2
            else: rest.push(f)
    check_hashes(ls)
    return rest

def may_run(ls:Lockstep, turn:int) -> bool:
    if ls.desync != "" or (filter(ls_links(ls)) l: l.closed).length: return false
    for(ls.players) p:
        if ls.done[p] < turn - 2: return false
    return true

def waiting_on(ls:Lockstep, turn:int) -> [int]: return filter(ls.players) p: ls.done[p] < turn - 2

// The turn just ended: its local commands (they run two turns on), the mark, new hashes.
def end_turn(ls:Lockstep, turn:int):
    let run = (turn + 2) * TICKS_PER_TURN
    let mine = filter(pending) c: c.player == ls.me and c.run_tick == run and c.seq >= ls.first_seq
    let msg = TurnMsg { ls.me, turn, mine, ls.hashes_out }
    ls.hashes_out = []
    let bin = flexbuffers_value_to_binary(msg, 1000)
    for(ls_links(ls)) l: net_send(l, 'T', bin)
    ls.done[ls.me] = turn

// After every step: a hash now and then, a finished turn out.
def ls_after_step(ls:Lockstep):
    if tick % HASH_EVERY == 0:
        let h = state_hash()
        ls.hashes_out.push(tick)
        ls.hashes_out.push(h)
        ls.mine.set(tick, h)
    if tick % TICKS_PER_TURN == 0: end_turn(ls, tick / TICKS_PER_TURN - 1)
