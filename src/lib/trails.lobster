// ------------------------------------------------------------------ worn trails (trails.gd)
// Where units walk often the ground wears into a trail, and where nobody walks it grows back: a byte
// per cell; every few ticks each walking unit (not flyers) wears its cell a little, and every so often
// each cell grows back a little (a row at a time). A cell worn to `trail` is a trail (the view draws
// it; behind a rule, speed_pct, walkers on it are faster).

def trails_tick():
    if tick % tr_every == 0:
        for(u_x.length) i:
            if u_moving[i] == 1 and u_mclass[i] != FLYING:
                let c = cell_of(u_x[i], u_y[i])
                wear[c] = min(wear[c] + tr_add, tr_max)
    var y = tick % tr_decay_every
    while y < H:
        for(W) x:
            let c = y * W + x
            if wear[c] > 0: wear[c] = max(wear[c] - tr_decay, 0)
        y += tr_decay_every

// Percent speed for a walker on this cell: 100, or more on a trail (when the rule is on).
def trail_pct(cell:int) -> int:
    if tr_speed_pct == 0 or wear[cell] < tr_trail: return 100
    return 100 + tr_speed_pct

// Into the hash (World.state_hash: the wear, weighted by cell).
def wear_hash(h:int) -> int:
    var worn = 0
    for(wear) v, c: worn += v * (c % 251 + 1)
    return mix(h, worn)
