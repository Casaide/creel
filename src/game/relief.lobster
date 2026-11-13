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
var relief_cliffs = 0.0      // tiles, 0 to 1: more than 0 draws cliffs off the grid (Creel #25), each level's drop a curve wandering this far across the unwalkable tile below it
let CLIFF_STEPS = 8          // a cliff tile is drawn as this many strips each way
let CLIFF_FACE = 0.04        // tiles: how far a face runs out from its rim to its foot (a sheer face is drawn steep whatever this is)
let CLIFF_TALUS = 0.22       // levels: how high the scree lies against a face's foot
let CLIFF_TALUS_RUN = 0.35   // tiles: how far the scree runs out from the foot
var cliff_tile = []::int     // per tile: 1 where cliffs are drawn (a change of height within two tiles, and not a ramp)
var cliff_h = []::float      // the ground's height (levels) on a fine lattice, CLIFF_STEPS a tile, ((W * CLIFF_STEPS + 1) * (H * CLIFF_STEPS + 1))

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
    cliff_tile = []
    cliff_h = []
    if relief_cliffs > 0.0:
        build_cliffs()
        return
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

// ---- cliffs off the grid (relief_cliffs, Creel #25)
// The sim's levels stay as they are: a tile beside higher ground is cliff and nothing walks on it. Only how the
// ground is drawn changes. For each level L, the tiles at L or above are a region; the drop down from it is drawn
// where the distance out from that region reaches a threshold of its own, wandering on a noise between the region's
// edge and the far side of the unwalkable tile below. So a rim is a curve at any angle, never a tile's edge; each
// level's drop wanders apart from the next, leaving ledges of varying width, or meets it in one taller face; scree
// lies at the foot. Walkable ground keeps its level all over: every drop lies in the unwalkable tile below it.

// A drop's height (levels, 0 to 1 above its foot) at e tiles out past its rim (negative: on the top).
def cliff_profile(e:float) -> float:
    if e <= 0.0: return 1.0
    if e < CLIFF_FACE: return 1.0 + (CLIFF_TALUS - 1.0) * e / CLIFF_FACE
    let s = clamp((e - CLIFF_FACE) / CLIFF_TALUS_RUN, 0.0, 1.0)
    return CLIFF_TALUS * (1.0 - s) * (1.0 - s)

// How far out from level L's region its drop lies at (px, py) tiles: half a tile, give or take relief_cliffs / 2.
def cliff_reach(px:float, py:float, l:int) -> float:
    let fl = float(l)
    let n = rough_noise(px * 0.75 + fl * 13.1, py * 0.75 - fl * 7.7) * 0.75 + rough_noise(px * 2.6 + 5.0 + fl, py * 2.6 + 9.0 - fl) * 0.25
    return 0.5 + clamp(n, -1.0, 1.0) * clamp(relief_cliffs, 0.0, 1.0) * 0.5

let cliff_d = map(25): 0.0
let cliff_l = map(25): 0

// Which way ramp tile c climbs: 0 toward +x, 1 -x, 2 +y, 3 -y (to the neighbour a level up along it).
def ramp_way(c:int) -> int:
    let x = c % W
    let y = c / W
    let up = level[c] + 1
    if x + 1 < W and level[c + 1] == up: return 0
    if x > 0 and level[c - 1] == up: return 1
    if y + 1 < H and level[c + W] == up: return 2
    if y > 0 and level[c - W] == up: return 3
    return 0

// The ground's height (levels) at (px, py) tiles, with cliffs. A ramp climbs straight, a level over its tile, and
// only drops from above its top cut into it (a wall beside it); elsewhere ramps are left out of the regions, so no
// rim is drawn where a ramp meets the ground at either end.
def cliff_point(px:float, py:float) -> float:
    let tx = clamp(int(floor(px)), 0, W - 1)
    let ty = clamp(int(floor(py)), 0, H - 1)
    let oc = ty * W + tx
    let own = level[oc]
    var base = float(own)
    var first = 0
    if ramp[oc] == 1:
        let fx = clamp(px - float(tx), 0.0, 1.0)
        let fy = clamp(py - float(ty), 0.0, 1.0)
        base += [ fx, 1.0 - fx, fy, 1.0 - fy ][ramp_way(oc)]
        first = own + 2
    var lo = own
    var hi = own
    var n = 0
    var dy = -2
    while dy <= 2:
        var dx = -2
        while dx <= 2:
            let x = tx + dx
            let y = ty + dy
            if x >= 0 and y >= 0 and x < W and y < H and ramp[y * W + x] == 0:
                let ex = max(max(float(x) - px, px - float(x + 1)), 0.0)
                let ey = max(max(float(y) - py, py - float(y + 1)), 0.0)
                cliff_d[n] = sqrt(ex * ex + ey * ey)
                cliff_l[n] = level[y * W + x]
                lo = min(lo, cliff_l[n])
                hi = max(hi, cliff_l[n])
                n++
            dx++
        dy++
    // (each level's drop adds its own 0 to 1, below to above it; a drop never lies further out than the one below
    // it, so the regions stay nested)
    var sum = 0.0
    var e_below = -9.0
    var l = lo + 1
    while l <= hi:
        var d_in = 9.0   // to the nearest tile at l or above
        var d_out = 9.0  // to the nearest tile below l
        for(n) i:
            if cliff_l[i] >= l: d_in = min(d_in, cliff_d[i])
            else: d_out = min(d_out, cliff_d[i])
        let sd = if own >= l and ramp[oc] == 0: -d_out else: d_in
        let e = max(sd - cliff_reach(px, py, l), e_below)
        e_below = e
        // (on a ramp, the first drop that counts is the first above its top, and it falls to the ramp's own height)
        if l == first and first > 0: sum += cliff_profile(e) * (float(l) - base)
        elif l >= first: sum += cliff_profile(e)
        l++
    if ramp[oc] == 0: return float(lo) + sum
    return base + sum

def build_cliffs():
    cliff_tile = map(W * H) c:
        let x = c % W
        let y = c / W
        var diff = ramp[c] == 1
        if not diff:
            var dy = -2
            while dy <= 2:
                var dx = -2
                while dx <= 2:
                    let nx = x + dx
                    let ny = y + dy
                    if nx >= 0 and ny >= 0 and nx < W and ny < H and level[ny * W + nx] != level[c]: diff = true
                    dx++
                dy++
        if diff: 1 else: 0
    let k = CLIFF_STEPS
    let gw = W * k + 1
    cliff_h = map(gw * (H * k + 1)): 0.0
    for(W * H) c:
        if cliff_tile[c] == 1:
            let x = c % W
            let y = c / W
            for(k + 1) j:
                for(k + 1) i:
                    cliff_h[(y * k + j) * gw + x * k + i] = cliff_point(float(x) + float(i) / float(k), float(y) + float(j) / float(k))

// The height at (fx, fy) across cliff tile c, from the lattice (as its triangles are drawn).
def cliff_in(c:int, fx:float, fy:float) -> float:
    let k = CLIFF_STEPS
    let gw = W * k + 1
    let gx = float(c % W * k) + clamp(fx, 0.0, 1.0) * float(k)
    let gy = float(c / W * k) + clamp(fy, 0.0, 1.0) * float(k)
    let ix = min(int(gx), gw - 2)
    let iy = min(int(gy), H * k - 1)
    let u = gx - float(ix)
    let v = gy - float(iy)
    let o = iy * gw + ix
    let h0 = cliff_h[o]
    let h1 = cliff_h[o + 1]
    let h2 = cliff_h[o + gw + 1]
    let h3 = cliff_h[o + gw]
    // (the lattice's cells are cut as cliff_cells draws them: along the diagonal whose ends lie nearest in height)
    if abs(h1 - h3) < abs(h0 - h2) - 0.01:
        if u + v <= 1.0: return h0 + (h1 - h0) * u + (h3 - h0) * v
        return h2 + (h3 - h2) * (1.0 - u) + (h1 - h2) * (1.0 - v)
    if u >= v: return h0 + (h1 - h0) * u + (h2 - h1) * v
    return h0 + (h2 - h3) * u + (h3 - h0) * v

def is_cliff_tile(c:int) -> bool: return cliff_tile.length > 0 and cliff_tile[c] == 1

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
    if is_cliff_tile(c): return cliff_in(c, fx, fy)
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
