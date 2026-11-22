// ------------------------------------------------------------------ the network lobby: join before the match starts
// The host opens a room as soon as it hosts: the door (lan.lobster) takes joiners, each takes a side that an AI held
// (an ally or an enemy) and says the words its army is made from, and everyone sees the lobby change as it does. At
// Start the host tells each joiner its side, every person's side and the AIs' levels (room_start), then sends the
// world as a match always went. Messages ride the link's framing (lockstep.lobster):
//   host -> joiner: L the lobby (JSON: map, mode, fixed, sides), A the side you hold, X refused (and the link closes),
//                   W at Start: "<your side>|<people's sides>|<every side's AI level>"
//   joiner -> host: T take a side, P my army: "<reroll>|<words>"

let ROOM_HOST = "host"
let ROOM_AI = "ai"
let ROOM_PLAYER = "player"

class RoomSide:
    who = ROOM_AI
    team = 0
    prompt = ""  // a player's words (the host's and the AIs' are the host's lobby's)
    reroll = 0   // which take of those words (the generator's reroll)
    guest = -1   // which joiner holds it

class Room:
    door:HostDoor
    sides = []::RoomSide
    guests = []::Link
    map_id = ""
    mode = ""
    sent = ""        // the lobby as last sent
    changed = false  // a joiner took a side or typed: the host's lobby reads it
    fixed = false    // the host's sides are set (a match resumed): joiners take a side as it is, their words don't change it

def room_open(port:int, name:string, map_id:string) -> Room:
    let r = Room { door_open(port, name, map_id) }
    r.map_id = map_id
    return r

// The host's sides (the lobby's, each frame): their count and teams, the host's own; a joiner keeps its side while it lasts.
def room_sides(r:Room, side_teams:[int], side_words:[string], side_rerolls:[int]):
    while r.sides.length > side_teams.length:
        let s = r.sides.pop()
        if s.guest >= 0: room_drop(r, s.guest, "the host changed the map: that side is gone")
    while r.sides.length < side_teams.length: r.sides.push(RoomSide {})
    for(r.sides) s, i:
        s.team = side_teams[i]
        if i == 0: s.who = ROOM_HOST
        if s.who != ROOM_PLAYER or r.fixed:
            s.prompt = side_words[i]
            s.reroll = side_rerolls[i]

def room_side_of(r:Room, g:int) -> int:
    for(r.sides) s, i: if s.who == ROOM_PLAYER and s.guest == g: return i
    return -1

def room_free(r:Room, side:int):
    let s = r.sides[side]
    s.who = ROOM_AI
    s.guest = -1
    if not r.fixed:
        s.prompt = ""
        s.reroll = 0
    r.changed = true

def room_drop(r:Room, g:int, why:string):
    let side = room_side_of(r, g)
    if side >= 0: room_free(r, side)
    if why != "": net_send(r.guests[g], 'X', why)
    r.guests[g].closed = true

// A joiner takes a side an AI holds (and lets go of the one it had). False if it isn't free.
def room_take(r:Room, g:int, side:int) -> bool:
    if side < 0 or side >= r.sides.length or r.sides[side].who != ROOM_AI: return false
    let had = room_side_of(r, g)
    let prompt = if had >= 0: r.sides[had].prompt else: ""
    let reroll = if had >= 0: r.sides[had].reroll else: 0
    if had >= 0: room_free(r, had)
    let s = r.sides[side]
    s.who = ROOM_PLAYER
    s.guest = g
    if not r.fixed:  // (a fixed side keeps its army; otherwise the joiner's goes with it)
        s.prompt = prompt
        s.reroll = reroll
    r.changed = true
    net_send(r.guests[g], 'A', string(side))
    return true

// The first side an AI holds, on another team than the host's if there is one.
def room_first_free(r:Room) -> int:
    var first = -1
    for(r.sides) s, i:
        if s.who == ROOM_AI:
            if s.team != r.sides[0].team: return i
            if first < 0: first = i
    return first

def room_json(r:Room) -> string:
    let o = jobj()
    set(o, "map", jstr(r.map_id))
    set(o, "mode", jstr(r.mode))
    set(o, "fixed", jbool(r.fixed))
    let list = []::JV
    for(r.sides) s:
        let so = jobj()
        set(so, "who", jstr(s.who))
        set(so, "team", jint(s.team))
        set(so, "prompt", jstr(s.prompt))
        set(so, "reroll", jint(s.reroll))
        list.push(so)
    set(o, "sides", jarr(list))
    return stringify(o)

// Each frame: let joiners in, hear them, tell them what changed. Joiners who left free their sides.
def room_tick(r:Room):
    let got = door_tick(r.door)
    if got:
        r.guests.push(got)
        let g = r.guests.length - 1
        let side = room_first_free(r)
        if side < 0: room_drop(r, g, "the game is full")
        else: room_take(r, g, side)
        r.sent = ""  // (the newcomer gets the lobby)
    for(r.guests) k, g:
        if not k.closed:
            for(net_poll(k)) f:
                if f[0] == "T": room_take(r, g, string_to_int(f[1]))
                elif f[0] == "P":
                    let side = room_side_of(r, g)
                    let bar = find_string(f[1], "|")
                    if side >= 0 and bar > 0 and not r.fixed:
                        let s = r.sides[side]
                        let words = substring(f[1], bar + 1, f[1].length - bar - 1)
                        let reroll = string_to_int(substring(f[1], 0, bar))
                        if s.prompt != words or s.reroll != reroll:
                            s.prompt = words
                            s.reroll = reroll
                            r.changed = true
            if k.closed: room_drop(r, g, "")
    let now = room_json(r)
    if now != r.sent:
        r.sent = now
        for(r.guests) k: if not k.closed: net_send(k, 'L', now)

def room_players(r:Room) -> int: return (filter(r.sides) s: s.who == ROOM_PLAYER).length

// Start: the people's sides (the host's first), and each joiner's link in the order of its side. Every joiner hears
// its side, the people's sides and the AIs' levels (levels: one per side, "" for a person).
def room_start(r:Room, levels:[string]) -> [int], [Link]:
    let seats = filter(r.sides.length) i: r.sides[i].who != ROOM_AI
    let links = []::Link
    for(seats) i: if i > 0: links.push(r.guests[r.sides[i].guest])
    let people = concat_string(map(seats) i: string(i), ",")
    let lv = concat_string(map(levels) l: if l == "": "-" else: l, ",")  // (a person's: "-")
    for(seats) i: if i > 0: net_send(r.guests[r.sides[i].guest], 'W', "{i}|{people}|{lv}")
    for(r.guests) k, g: if not k.closed and room_side_of(r, g) < 0: room_drop(r, g, "the game started without you")
    return seats, links

// ---- the joiner's side
class Guest:
    link:Link
    side = -1
    lobby = jnull()  // the host's lobby as last heard
    error = ""
    said = false
    prompt = ""      // the words sent last
    reroll = 0       // and their take
    seats = []::int  // at Start: the people's sides
    levels = []::string
    world = ""            // the match, once the host starts
    later = []::[string]  // frames that came with the match (turns: kept for the lockstep)

def guest_new(link:Link) -> Guest: return Guest { link }

def guest_tick(g:Guest):
    if g.error != "" or g.world != "": return
    if g.link.error != "":
        g.error = g.link.error
        return
    if not net_ready(g.link): return
    if not g.said:
        join_hello(g.link)
        g.said = true
    for(net_poll(g.link)) f:
        if g.world != "": g.later.push(f)
        elif f[0] == "L": g.lobby = parse_json(f[1])
        elif f[0] == "A":
            g.side = string_to_int(f[1])
            if g.prompt != "": net_send(g.link, 'P', "{g.reroll}|{g.prompt}")
        elif f[0] == "X": g.error = f[1]
        elif f[0] == "W":
            let w = tokenize(f[1], "|", "")
            g.side = string_to_int(w[0])
            g.seats = map(tokenize(w[1], ",", "")) s: string_to_int(s)
            g.levels = if w.length > 2: map(tokenize(w[2], ",", "")) l: if l == "-": "" else: l else: []
        elif f[0] == "S": g.world = f[1]
    if g.link.closed and g.world == "" and g.error == "": g.error = "the host left"

def guest_take(g:Guest, side:int): if g.said: net_send(g.link, 'T', string(side))

// The joiner's army: its words and which take of them (the generator's reroll).
def guest_prompt(g:Guest, text:string, reroll:int):
    if text == g.prompt and reroll == g.reroll: return
    g.prompt = text
    g.reroll = reroll
    if g.side >= 0: net_send(g.link, 'P', "{reroll}|{text}")
