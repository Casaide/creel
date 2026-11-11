// ------------------------------------------------------------------ how high the ground lies, and what lies on it
// The hills' corner heights (from the sim's levels) and the screen points of things on the ground: no drawing, so
// the unit tests can check it. Views only: floats, never read by the sim.

var LEVEL_PX = 20.0     // canvas px a level (Iso.LEVEL_PX); art px: x 1.5 (a setting with the camera's angle: see view/facing)
let MAX_LEVEL = 9       // the highest ground a map can have (its "heights": 0 to 9, ramps a to i)
var relief = []::float  // per cell: corner heights (levels): top, right, bottom, left
var relief_sharp = false  // true: raised ground keeps its corners (sheer cliffs that jog square); false: an outer corner is cut down to the ground below (a hill's rounded shoulder)
var relief_rough = 0.0       // levels: raised ground by a change of height rises and falls by up to this much, so a rim wanders and is never ruled straight (0: off)
var relief_rough_size = 1.5  // tiles: the size of the rough's broad swells (a finer ripple a third the size rides on them)
let ROUGH_STEPS = 4          // a rough tile is drawn as this many strips each way, so its rims can bend
var rough_w = []::float      // per tile corner ((W + 1) * (H + 1)): 1 where the height changes about it (the rough is felt there), else 0

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
                if ramp[c] == 0 and lv > 0 and not relief_sharp:
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
    rough_w = []
    if relief_rough > 0.0:
        rough_w = map((W + 1) * (H + 1)) v:
            let vx = v % (W + 1)
            let vy = v / (W + 1)
            var lo = MAX_LEVEL * 2
            var hi = -1
            var dy = -2
            while dy <= 1:
                var dx = -2
                while dx <= 1:
                    let x = clamp(vx + dx, 0, W - 1)
                    let y = clamp(vy + dy, 0, H - 1)
                    let o = y * W + x
                    lo = min(lo, level[o] * 2 + ramp[o])
                    hi = max(hi, level[o] * 2 + ramp[o])
                    dx++
                dy++
            if hi > lo: 1.0 else: 0.0

// A lattice's value noise, smooth, -1 to 1.
def rough_hash(x:int, y:int) -> float:
    var h = x * 374761393 + y * 668265263
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return float(h & 0xFFFF) / 32767.5 - 1.0

def rough_noise(x:float, y:float) -> float:
    let ix = int(floor(x))
    let iy = int(floor(y))
    var fx = x - float(ix)
    var fy = y - float(iy)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    let a = rough_hash(ix, iy) + (rough_hash(ix + 1, iy) - rough_hash(ix, iy)) * fx
    let b = rough_hash(ix, iy + 1) + (rough_hash(ix + 1, iy + 1) - rough_hash(ix, iy + 1)) * fx
    return a + (b - a) * fy

// Is tile c rough (any corner where the height changes)? Only rough tiles are cut into strips.
def tile_rough(c:int) -> bool:
    if not rough_w.length: return false
    let x = c % W
    let y = c / W
    let v = y * (W + 1) + x
    return rough_w[v] + rough_w[v + 1] + rough_w[v + W + 1] + rough_w[v + W + 2] > 0.0

// The height in levels at (fx, fy) across tile c (0 to 1 each way): its corners blended, and the rough on top. The
// rough fades out toward flat ground (level 0, which is drawn flat) and where the height is the same all about.
def height_in(c:int, fx:float, fy:float) -> float:
    let k = c * 4
    let top = relief[k] + (relief[k + 1] - relief[k]) * fx
    let bottom = relief[k + 3] + (relief[k + 2] - relief[k + 3]) * fx
    let h = top + (bottom - top) * fy
    if not rough_w.length: return h
    let x = c % W
    let y = c / W
    let v = y * (W + 1) + x
    let wt = rough_w[v] + (rough_w[v + 1] - rough_w[v]) * fx
    let wb = rough_w[v + W + 1] + (rough_w[v + W + 2] - rough_w[v + W + 1]) * fx
    let w = wt + (wb - wt) * fy
    if w <= 0.0: return h
    let px = (float(x) + fx) / relief_rough_size
    let py = (float(y) + fy) / relief_rough_size
    let n = rough_noise(px, py) * 0.7 + rough_noise(px * 3.0 + 17.0, py * 3.0 + 5.0) * 0.3
    return h + n * relief_rough * w * clamp(h, 0.0, 1.0)

// How far the ground at (x, y) milli-tiles is raised, in canvas px (Iso.lift); 0 on a flat map.
def lift_at(x:float, y:float) -> float:
    if not relief.length: return 0.0
    let tx = clamp(int(x / 1000.0), 0, W - 1)
    let ty = clamp(int(y / 1000.0), 0, H - 1)
    let fx = clamp(x / 1000.0 - float(tx), 0.0, 1.0)
    let fy = clamp(y / 1000.0 - float(ty), 0.0, 1.0)
    return height_in(ty * W + tx, fx, fy) * LEVEL_PX

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
