// ------------------------------------------------------------------ winning and losing (match.gd, modes.gd)
// A player who started with a Town Center is out once it has none left (finished or not); when only
// one team has players left, that team wins. A finished Wonder standing long enough wins (the one up
// longest; with the host's wonder.victory). In the Siege mode an attacker with nothing left is out,
// and every attacker once the hold time runs out. Checked once a second.

let CHECK_EVERY = 20

var wonder_hold = 0         // ticks a Wonder must stand (0: no Wonder victory)
var wonder_ids = []::int    // standing finished Wonders, in id order
var wonder_since = []::int  // the tick each was finished
var wonder_owners = []::int
var mode_hold = -1  // the Siege mode: hold ticks (0: no time limit); -1: no such mode

def towns(p:int) -> int:
    var n = 0
    for(b_id.length) b:
        if b_owner[b] == p and has_role(b_kind[b], ROLE_HUB): n++
    return n

def has_anything(p:int) -> bool:
    for(u_x.length) i:
        if u_owner[i] == p and t_animal[u_kind[i]] == 0: return true
    for(b_id.length) b:
        if b_owner[b] == p: return true
    return false

// Modes.tick: the Siege mode's attackers.
def mode_tick():
    if mode_hold < 0: return
    let over = mode_hold > 0 and tick >= mode_hold
    for(num_players) p:
        if defeated[p] == 0 and teams[p] != teams[0] and (over or not has_anything(p)): defeated[p] = tick + 1

// Match._wonders: true when a Wonder won the match here.
def wonders() -> bool:
    if wonder_hold == 0: return false
    let ids = []::int
    let since = []::int
    for(b_id.length) b:
        if has_role(b_kind[b], ROLE_WONDER) and b_done[b] != 0 and defeated[b_owner[b]] == 0:
            var at = -1
            for(wonder_ids) id, k:
                if id == b_id[b]: at = k
            ids.push(b_id[b])
            since.push(if at >= 0: wonder_since[at] else: tick)
    wonder_owners = map(ids) id: b_owner[b_index_of(id)]
    wonder_ids = ids
    wonder_since = since
    var best = -1
    for(ids.length) k:
        if tick - since[k] >= wonder_hold and (best < 0 or since[k] < since[best]): best = k
    if best < 0: return false
    winner = teams[wonder_owners[best]]
    return true

def match_tick():
    if winner >= 0 or tick % CHECK_EVERY != 0: return
    mode_tick()
    for(num_players) p:
        if defeated[p] == 0 and started_with_town[p] == 1 and towns(p) == 0: defeated[p] = tick + 1
    if wonders(): return
    let left = []::int
    for(num_players) p:
        if defeated[p] == 0 and not contains(left, teams[p]): left.push(teams[p])
    if contains(started_with_town, 1) and left.length == 1: winner = left[0]
