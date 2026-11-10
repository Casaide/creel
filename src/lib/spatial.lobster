// ------------------------------------------------------------------ spatial.gd

// Units into buckets by cell, touching only the cells that hold units (the last build's emptied first): a
// fight's few units on a big map cost what they hold, not the map. A bucket's units stay in slot order.
def spatial_build():
    for(sp_used) c:
        sp_start[c] = 0
        sp_end[c] = 0
    sp_used.remove_range(0, sp_used.length)
    for(u_x.length) i:
        let c = clamp(u_y[i] / TILE, 0, H - 1) * W + clamp(u_x[i] / TILE, 0, W - 1)
        sp_cell[i] = c
        if sp_cursor[c] == 0: sp_used.push(c)
        sp_cursor[c]++
    var acc = 0
    for(sp_used) c:
        sp_start[c] = acc
        acc += sp_cursor[c]
        sp_end[c] = acc
        sp_cursor[c] = sp_start[c]
    for(u_x.length) i:
        let c = sp_cell[i]
        sp_items[sp_cursor[c]] = i
        sp_cursor[c]++
    for(sp_used) c: sp_cursor[c] = 0

// The buckets emptied over the whole map (a fresh map, or a match loaded from a save, whose cells may hold an older
// build's ranges).
def spatial_clear():
    let cells = W * H
    sp_start = zeros(cells)
    sp_end = zeros(cells)
    sp_cursor = zeros(cells)
    sp_used.remove_range(0, sp_used.length)
