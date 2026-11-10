// ------------------------------------------------------------------ fog (fog.gd)
// What each side sees: per player a byte per cell, restamped from its units' sight circles, one
// team per tick of the rules.fog.every cycle. Only the visible grid is ported: combat reads it (no
// going for foes in the fog). The remembered ground and buildings (fog_ground, fog_seen) are for
// the AI and the view. No buildings here, and no hills (the exporter asserts it).

import dictionary

var opaque_chunks = []::int  // sight-blocking cells per CHUNK x CHUNK block
var level_chunks = []::int   // the highest level per block
var chunk_w = 0

def make_chunks():
    chunk_w = (W + CHUNK - 1) / CHUNK
    let ch = (H + CHUNK - 1) / CHUNK
    opaque_chunks = map(chunk_w * ch): 0
    level_chunks = map(chunk_w * ch): 0
    for(W * H) c:
        let b = (c / W / CHUNK) * chunk_w + (c % W) / CHUNK
        opaque_chunks[b] += opaque[c]
        level_chunks[b] = max(level_chunks[b], level[c])

def fog_visible(p:int, x:int, y:int) -> bool:
    return fog[p][cell_of(x, y)] == VISIBLE

// The players of each team, teams in order of their first player.
def fog_teams() -> [[int]]:
    let out = []::[int]
    let team_of = []::int
    for(num_players) p:
        var at = -1
        for(team_of) t, k:
            if t == teams[p]: at = k
        if at < 0:
            at = out.length
            team_of.push(teams[p])
            out.push([]::int)
        out[at].push(p)
    return out

def fog_tick():
    let ts = fog_teams()
    for(ts) team, k:
        if tick % r_fog_every == k * r_fog_every / ts.length:
            fog_update_team(team)

def fog_update_team(team:[int]):
    let p = team[0]
    let g = fog[p]
    for(fog_lit[p]) c: g[c] = EXPLORED
    let lit = []::int
    let stamped = dictionary<int, int>(1009)  // units standing together see the same circle once
    let team_p = teams[p]
    for(u_x.length) i:
        if teams[u_owner[i]] == team_p:
            let k = u_kind[i]
            var r = (if t_worker[k]: r_fog_worker else: r_fog_unit) + t_sight[k]
            if has_heights: r += level[cell_of(u_x[i], u_y[i])] * r_high_sight_unit  // high ground sees further
            if u_perch[i] != 0: r += r_high_sight_unit                               // so does a unit up on a wall
            let high = t_mclass[k] == 2
            let key = ((u_y[i] / 1000 * W + u_x[i] / 1000) * 64 + r) * 2 + (if high: 1 else: 0)
            if stamped.get(key, 0): continue
            stamped.set(key, 1)
            stamp(g, lit, u_x[i] / 1000, u_y[i] / 1000, r, high)
    for(b_id.length) b:
        if teams[b_owner[b]] == team_p and b_done[b] == 1:  // a foundation sees nothing
            let k = b_kind[b]
            // the data's own sight, else a tower's (it shoots) or a building's
            var r = (if bt_sight[k] > 0: bt_sight[k] elif bt_attacks[k] and bt_arrows[k] > 0: r_fog_tower else: r_fog_building) + bm_sight[b_owner[b]][k]
            if has_heights: r += level[b_cy[b] * W + b_cx[b]] * r_high_sight_building
            stamp(g, lit, b_cx[b] + b_sx[b] / 2, b_cy[b] + b_sy[b] / 2, r + max(b_sx[b], b_sy[b]) / 2, bt_over_trees[k] != 0)
    fog[p] = g
    fog_lit[p] = lit
    remember(p)
    var k = 1
    while k < team.length:
        fog[team[k]] = copy(g)
        fog_lit[team[k]] = lit
        fog_seen[team[k]] = map(fog_seen[p]) s: copy(s)
        fog_ground[team[k]] = copy(fog_ground[p])
        fog_left[team[k]] = copy(fog_left[p])
        k++

// What a player remembers of enemy buildings it has seen (fog_seen): per player, in the order first
// seen, [id, kind, owner, cx, cy, sx, done, progress, age, sy, diag] as last seen; one whose spot is
// seen empty is forgotten (Fog._remember; the remembered ground isn't ported: no bot reads it).

def sees_rect(p:int, cx:int, cy:int, sx:int, sy:int) -> bool:
    let g = fog[p]
    var y = cy
    while y < cy + sy:
        var x = cx
        while x < cx + sx:
            if g[y * W + x] == VISIBLE: return true
            x++
        y++
    return false

def remember(p:int):
    remember_ground(p)
    let seen = fog_seen[p]
    for(b_id.length) b:
        if teams[b_owner[b]] != teams[p] and sees_rect(p, b_cx[b], b_cy[b], b_sx[b], b_sy[b]):
            let rec = [ b_id[b], b_kind[b], b_owner[b], b_cx[b], b_cy[b], b_sx[b], b_done[b], b_progress[b], ages[b_owner[b]], b_sy[b], 0 ]
            var at = -1
            for(seen) s, n:
                if s[0] == b_id[b]: at = n
            if at >= 0: seen[at] = rec
            else: seen.push(rec)
    fog_seen[p] = filter(seen) s: not (b_index_of(s[0]) < 0 and sees_rect(p, s[3], s[4], s[5], s[9]))

// Sight circles with trees in them, per centre, radius and over_trees, until a tree is felled.
let sight_cache = dictionary<int, [int]>(4001)
var sight_cache_version = 0  // bumped when a cell starts or stops blocking sight (map.lobster refresh)
var sight_cache_for = 0

def stamp(g:[int], lit:[int], cx:int, cy:int, r:int, over_trees:bool):
    let v = level[cy * W + cx]
    if blocked_near(cx, cy, r, v, over_trees):
        if sight_cache_for != sight_cache_version:
            sight_cache.clear()
            sight_cache_for = sight_cache_version
        let key = ((cy * W + cx) * 64 + r) * 2 + (if over_trees: 1 else: 0)
        var cells = sight_cache.get(key)
        if not cells:
            let fresh = sight_los(cx, cy, r, v, over_trees)
            sight_cache.set(key, fresh)
            cells = fresh
        for(cells) c:
            if g[c] != VISIBLE:
                g[c] = VISIBLE
                lit.push(c)
        return
    let sp = spans(r)
    var k = 0
    while k < sp.length:
        let y = cy + sp[k]
        if y >= 0 and y < H:
            let row = y * W
            var c = row + max(cx + sp[k + 1], 0)
            let e = row + min(cx + sp[k + 2], W - 1)
            while c <= e:
                if g[c] != VISIBLE:
                    g[c] = VISIBLE
                    lit.push(c)
                c++
        k += 3

def blocked_near(cx:int, cy:int, r:int, v:int, over_trees:bool) -> bool:
    let cw = chunk_w
    let ch = (H + CHUNK - 1) / CHUNK
    var y = max(cy - r, 0) / CHUNK
    let y1 = min((cy + r) / CHUNK, ch - 1)
    while y <= y1:
        var x = max(cx - r, 0) / CHUNK
        let x1 = min((cx + r) / CHUNK, cw - 1)
        while x <= x1:
            if (opaque_chunks[y * cw + x] > 0 and not over_trees) or level_chunks[y * cw + x] > v: return true
            x++
        y++
    return false

// The circle with line of sight: a cell is seen if the one before it on the line from the centre
// was seen and doesn't block. The cells seen, nearest ring first.
def sight_los(cx:int, cy:int, r:int, v:int, over_trees:bool) -> [int]:
    let offs, par = ray_table(r)
    let n = par.length
    let out = []::int
    let seen = map(n): 0
    for(n) k:
        let x = cx + offs[k * 2]
        let y = cy + offs[k * 2 + 1]
        if x < 0 or y < 0 or x >= W or y >= H: continue
        if k > 0 and seen[par[k]] != 2: continue
        let c = y * W + x
        out.push(c)
        seen[k] = if ((opaque[c] == 1 and not over_trees) or level[c] > v) and k > 0: 1 else: 2
    return out

let ray_offs = dictionary<int, [int]>(67)
let ray_par = dictionary<int, [int]>(67)

def round_div(a:int, b:int) -> int:
    return (a * 2 + (if a >= 0: b else: -b)) / (2 * b)

// Offsets of the sight circle ring by ring (Chebyshev distance, then dy, then dx), each with the
// index of the offset one step nearer the centre on the line to it.
def ray_table(r:int) -> [int], [int]:
    let have = ray_offs.get(r)
    if have:
        return have, assert ray_par.get(r)
    let offs = circle(r)
    let keys = []::int
    var k = 0
    while k < offs.length:
        let dx = offs[k]
        let dy = offs[k + 1]
        keys.push((max(abs(dx), abs(dy)) << 16) | ((dy + 128) << 8) | (dx + 128))
        k += 2
    sort_ints(keys)
    let side = 2 * r + 1
    let index = map(side * side): -1
    let sorted = []::int
    for(keys) key, n:
        let dx = (key & 255) - 128
        let dy = ((key >> 8) & 255) - 128
        index[(dy + r) * side + dx + r] = n
        sorted.push(dx)
        sorted.push(dy)
    let par = []::int
    for(keys.length) n:
        let dx = sorted[n * 2]
        let dy = sorted[n * 2 + 1]
        let steps = max(abs(dx), abs(dy))
        if steps == 0:
            par.push(0)
        else:
            let px = round_div(dx * (steps - 1), steps)
            let py = round_div(dy * (steps - 1), steps)
            par.push(index[(py + r) * side + px + r])
    ray_offs.set(r, sorted)
    ray_par.set(r, par)
    return sorted, par

// The sight circle as rows: (dy, first dx, last dx) per row, top row first.
def spans(r:int) -> [int]:
    let out = []::int
    var dy = -r
    while dy <= r:
        var first = 1 << 30
        var last = -(1 << 30)
        var dx = -r
        while dx <= r:
            if dx * dx + dy * dy <= r * r + r:
                first = min(first, dx)
                last = max(last, dx)
            dx++
        if first <= last:
            out.push(dy)
            out.push(first)
            out.push(last)
        dy++
    return out

def circle(r:int) -> [int]:
    let offs = []::int
    var dy = -r
    while dy <= r:
        var dx = -r
        while dx <= r:
            if dx * dx + dy * dy <= r * r + r:
                offs.push(dx)
                offs.push(dy)
            dx++
        dy++
    return offs
