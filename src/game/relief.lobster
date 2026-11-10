// ------------------------------------------------------------------ how high the ground lies, and what lies on it
// The hills' corner heights (from the sim's levels) and the screen points of things on the ground: no drawing, so
// the unit tests can check it. Views only: floats, never read by the sim.

let LEVEL_PX = 20.0     // canvas px a level (Iso.LEVEL_PX); art px: x 1.5
let MAX_LEVEL = 9       // the highest ground a map can have (its "heights": 0 to 9, ramps a to i)
var relief = []::float  // per cell: corner heights (levels): top, right, bottom, left

def corner_heights():
    relief = map(W * H * 4): 0.0
    let corners = [ int2 { 0, 0 }, int2 { 1, 0 }, int2 { 1, 1 }, int2 { 0, 1 } ]
    for(H) y:
        for(W) x:
            let c = y * W + x
            let lv = level[c]
            for(4) k:
                var v = float(lv)
                let cx = x + corners[k].x
                let cy = y + corners[k].y
                let around = [ int2 { cx - 1, cy - 1 }, int2 { cx, cy - 1 }, int2 { cx - 1, cy }, int2 { cx, cy } ]
                if ramp[c] == 0 and lv > 0:
                    var below = -1
                    for(around) n:
                        if below != -2 and not (n.x == x and n.y == y) and n.x >= 0 and n.y >= 0 and n.x < W and n.y < H:
                            let o = n.y * W + n.x
                            if level[o] >= lv or ramp[o] == 1: below = -2
                            else: below = max(below, level[o])
                    if below >= 0: v = float(below)
                if ramp[c] == 1:
                    for(around) n:
                        if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and level[n.y * W + n.x] > lv: v = float(lv) + 1.0
                relief[c * 4 + k] = v

// How far the ground at (x, y) milli-tiles is raised, in canvas px (Iso.lift); 0 on a flat map.
def lift_at(x:float, y:float) -> float:
    if not relief.length: return 0.0
    let tx = clamp(int(x / 1000.0), 0, W - 1)
    let ty = clamp(int(y / 1000.0), 0, H - 1)
    let c = (ty * W + tx) * 4
    let fx = clamp(x / 1000.0 - float(tx), 0.0, 1.0)
    let fy = clamp(y / 1000.0 - float(ty), 0.0, 1.0)
    let top = relief[c] + (relief[c + 1] - relief[c]) * fx
    let bottom = relief[c + 3] + (relief[c + 2] - relief[c + 3]) * fx
    return (top + (bottom - top) * fy) * LEVEL_PX

// The sim point under an art-px point, on raised ground (Iso.pick): the highest ground drawn there wins.
def pick_milli(p:float2) -> float2:
    if not relief.length: return iso_inv(p)
    var lv = MAX_LEVEL
    while lv >= 1:
        var m = iso_inv(p + float2 { 0.0, float(lv) * LEVEL_PX * 1.5 })
        let l = lift_at(m.x, m.y)
        if abs(l - float(lv) * LEVEL_PX) < LEVEL_PX * 0.5 and m.x >= 0.0 and m.y >= 0.0:
            for(3): m = iso_inv(p + float2 { 0.0, lift_at(m.x, m.y) * 1.5 })
            return m
        lv--
    var m0 = iso_inv(p)
    for(3): m0 = iso_inv(p + float2 { 0.0, lift_at(m0.x, m0.y) * 1.5 })
    return m0

// The art-px point of a sim point on the ground.
def on_ground(m:float2) -> float2: return iso(m.x, m.y) - float2 { 0.0, lift_at(m.x, m.y) * 1.5 }

// Is the ground at m behind a hill, the hill's top drawn over it?
def ground_hidden(m:float2) -> bool:
    let seen = pick_milli(on_ground(m))
    return lift_at(seen.x, seen.y) > lift_at(m.x, m.y) + LEVEL_PX * 0.5

let GROUND_STEP = 250.0  // milli-tiles a drawn leg bends at: the hills bend at tile edges

// A leg between two sim points as it's drawn, in art px: the runs of it you can see, following the ground over a
// hill and gone behind one.
def ground_path(a:float2, b:float2) -> [[float2]]:
    if not relief.length: return [ [ iso(a.x, a.y), iso(b.x, b.y) ] ]
    let n = max(1, int(ceiling(magnitude(b - a) / GROUND_STEP)))
    let runs = []::[float2]
    var open = false
    for(n + 1) k:
        let m = a + (b - a) * (float(k) / float(n))
        if ground_hidden(m): open = false
        else:
            if not open: runs.push([])
            open = true
            runs[runs.length - 1].push(on_ground(m))
    return runs
