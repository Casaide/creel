// ------------------------------------------------------------------ props as voxel grids (#410)
// Trees, rocks and deposits (model/trees.lobster, model/rocks.lobster) built voxel by voxel, about a voxel an art px
// (VG_PX), each voxel a material and a tone. Lit as one whole (the sun, its own shadow, occlusion, a crown's shade, a
// rim), coloured from that light by its material's ramps, and drawn by view/voxel_mesh's vm_draw. Shapes are in design
// units (k voxels each): x and y on the ground, z up, the world origin at (0, 0, 0).

let VG_PX = 1.0  // art px a voxel

let VG_BARK = 1
let VG_LEAF = 2
let VG_ROCK = 3
let VG_GOLD = 4
let VG_WOOD = 5  // a cut end of a trunk
let VG_CUT = 6   // freshly cut stone

class vglook:
    leaf:[float3]  // sun, mid, shade, dry
    bark:[float3]  // dark to light
    rock:[float3]  // dark to light
    strata:bool    // bedding lines
    tree:bool      // a tree's light (a crown's shade inside)
    standing:bool  // bark ridged up the trunk, moss low on its shaded side (not a felled log)

class vgrid:
    look:vglook
    k:float  // voxels a design unit
    lo:int3  // its corner, voxels from the origin
    n:int3
    mat:string
    tone:string  // 0..255 for -1..1
    seed:int

// A value in 0..1 for a voxel, the same every time.
def vg_hash(seed:int, x:int, y:int, z:int) -> float:
    var h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
    h = ((h ^ (h >> 15)) * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 3266489917) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return float(h & 0xFFFFFF) / 16777216.0

// Smooth noise in 0..1: random values on a lattice s voxels apart over the grid, blended between.
class vgfield:
    s:float
    n:int3
    v:[float]

def vg_field(g:vgrid, scale:float, seed:int) -> vgfield:
    let s = max(scale * g.k, 1.0)
    let n = int3 { int(float(g.n.x) / s) + 3, int(float(g.n.y) / s) + 3, int(float(g.n.z) / s) + 3 }
    let rng = grng(seed)
    return vgfield { s, n, map(n.x * n.y * n.z): randf(rng) }

// At a voxel of the grid (its own coordinates).
def vg_at(f:vgfield, x:float, y:float, z:float) -> float:
    let px = x / f.s
    let py = y / f.s
    let pz = z / f.s
    let ix = int(px)
    let iy = int(py)
    let iz = int(pz)
    def ease(t:float) -> float: return t * t * (3.0 - 2.0 * t)
    let fx = ease(px - float(ix))
    let fy = ease(py - float(iy))
    let fz = ease(pz - float(iz))
    def at(a:int, b:int, c:int) -> float: return f.v[((iz + c) * f.n.y + iy + b) * f.n.x + ix + a]
    let x0 = lerpf(lerpf(at(0, 0, 0), at(1, 0, 0), fx), lerpf(at(0, 1, 0), at(1, 1, 0), fx), fy)
    let x1 = lerpf(lerpf(at(0, 0, 1), at(1, 0, 1), fx), lerpf(at(0, 1, 1), at(1, 1, 1), fx), fy)
    return lerpf(x0, x1, fz)

// An empty grid over lo..hi (design units).
def vg_new(look:vglook, lo:float3, hi:float3, k:float, seed:int) -> vgrid:
    let a = int3 { int(floor(lo.x * k)) - 2, int(floor(lo.y * k)) - 2, max(0, int(floor(lo.z * k))) }
    let b = int3 { int(ceiling(hi.x * k)) + 3, int(ceiling(hi.y * k)) + 3, int(ceiling(hi.z * k)) + 3 }
    let n = b - a
    let cells = n.x * n.y * n.z
    return vgrid { look, k, a, n, ensure_size("", cells, 0), ensure_size("", cells, 128), seed }

def vg_index(g:vgrid, x:int, y:int, z:int) -> int: return (z * g.n.y + y) * g.n.x + x

def vg_get(g:vgrid, x:int, y:int, z:int) -> int:
    if x < 0 or y < 0 or z < 0 or x >= g.n.x or y >= g.n.y or z >= g.n.z: return 0
    return g.mat[vg_index(g, x, y, z)]

def vg_set(g:vgrid, i:int, m:int, tone:float):
    write_int8_le(g.mat, i, m)
    write_int8_le(g.tone, i, clamp(int((tone + 1.0) * 127.5), 0, 255))

// Every voxel of the grid in the box lo..hi (design units) through body(i, p): its index, its centre (design units).
def vg_box(g:vgrid, lo:float3, hi:float3, body):
    let a = max(int3_0, int3 { int(floor(lo.x * g.k)), int(floor(lo.y * g.k)), int(floor(lo.z * g.k)) } - g.lo - int3_1)
    let b = min(g.n, int3 { int(ceiling(hi.x * g.k)), int(ceiling(hi.y * g.k)), int(ceiling(hi.z * g.k)) } - g.lo + int3_1 * 2)
    for(b.z - a.z) dz:
        bake_pulse()
        let z = a.z + dz
        for(b.y - a.y) dy:
            let y = a.y + dy
            var i = vg_index(g, a.x, y, z)
            for(b.x - a.x) dx:
                let x = a.x + dx
                body(i, float3 { float(x + g.lo.x) + 0.5, float(y + g.lo.y) + 0.5, float(z + g.lo.z) + 0.5 } / g.k)
                i++

// A tapered rod from a (radius ra) to b (rb), in design units; over: on top of what's there.
def vg_capsule(g:vgrid, a:float3, b:float3, ra:float, rb:float, m:int, over:bool = false, tone:float = 0.0):
    let ab = b - a
    let l2 = max(dot(ab, ab), 0.000001)
    let r = max(ra, rb)
    vg_box(g, min(a, b) - float3_1 * r, max(a, b) + float3_1 * r) i, p:
        if over or g.mat[i] == 0:
            let t = clamp(dot(p - a, ab) / l2, 0.0, 1.0)
            let d = p - a - ab * t
            let rr = ra + (rb - ra) * t
            if dot(d, d) <= rr * rr: vg_set(g, i, m, tone)

// A tapered post from a to b with flat ends (a stump, a log, a cut face).
def vg_cylinder(g:vgrid, a:float3, b:float3, ra:float, rb:float, m:int, over:bool = false, tone:float = 0.0):
    let ab = b - a
    let l2 = max(dot(ab, ab), 0.000001)
    let r = max(ra, rb)
    vg_box(g, min(a, b) - float3_1 * r, max(a, b) + float3_1 * r) i, p:
        if over or g.mat[i] == 0:
            let t = dot(p - a, ab) / l2
            if t >= 0.0 and t <= 1.0:
                let d = p - a - ab * t
                let rr = ra + (rb - ra) * t
                if dot(d, d) <= rr * rr: vg_set(g, i, m, tone)

// A ragged blob round c (radius r, squashed in z by zs), its edge moved by the field f (rough), into the empty
// voxels: thin of them left out at random, and where gaps (above cut) is, none (a crown's holes).
def vg_blob(g:vgrid, c:float3, r:float, zs:float, rough:float, f:vgfield, m:int, tone:float, thin:float, gaps:vgfield?, cut:float):
    let reach = float3 { r, r, r / zs } * (1.0 + rough * 0.5)
    let far = 1.0 + rough * 0.5
    vg_box(g, c - reach, c + reach) i, p:
        guard g.mat[i] == 0
        let d = sqrt((p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) + (p.z - c.z) * (p.z - c.z) * zs * zs) / r
        guard d < far
        let q = p * g.k - float(g.lo)
        guard d + (vg_at(f, q.x, q.y, q.z) - 0.5) * rough < 1.0
        guard vg_hash(g.seed, int(q.x), int(q.y), int(q.z)) >= thin
        let open = if gaps: vg_at(gaps, q.x, q.y, q.z) <= cut else: true
        if open: vg_set(g, i, m, tone)

// Every voxel of the box (design units) set to what matf(its centre) gives (0: left alone).
def vg_solid(g:vgrid, lo:float3, hi:float3, matf):
    vg_box(g, lo, hi) i, p:
        let m = matf(p)
        if m: vg_set(g, i, m, 0.0)

def vg_empty(g:vgrid, lo:float3, hi:float3, gone):
    vg_box(g, lo, hi) i, p:
        if g.mat[i] and gone(p): write_int8_le(g.mat, i, 0)

let VG_DIRS = map([ int3 { 1, 0, 0 }, int3 { -1, 0, 0 }, int3 { 0, 1, 0 }, int3 { 0, -1, 0 }, int3 { 0, 0, 1 }, int3 { 0, 0, -1 },
                    int3 { 1, 1, 0 }, int3 { -1, 1, 0 }, int3 { 1, -1, 0 }, int3 { -1, -1, 0 }, int3 { 1, 0, 1 }, int3 { -1, 0, 1 },
                    int3 { 0, 1, 1 }, int3 { 0, -1, 1 }, int3 { 1, 0, -1 }, int3 { -1, 0, -1 }, int3 { 0, 1, -1 }, int3 { 0, -1, -1 },
                    int3 { 1, 1, 1 }, int3 { -1, 1, 1 }, int3 { 1, -1, 1 }, int3 { -1, -1, 1 }, int3 { 1, 1, -1 }, int3 { -1, 1, -1 },
                    int3 { 1, -1, -1 }, int3 { -1, -1, -1 } ]) d: normalize(float(d))

// How much each voxel's light is jittered before it's banded (1: Age of Anything's speckled, painterly look; near 0: crisp
// bands with hard edges between them), and how many bands a leaf's light has. A game sets them before it bakes.
// A model's own shadow from a picture of it seen from the sun (each voxel is lit only if nothing lies nearer the sun on
// its line), not from a march in steps of the lighting unit, which steps over twigs and thin boughs. Hard-edged and
// exact to a voxel: a crown shades its own boughs and trunk. Off by default (the march is what older bakes were made by).
var vg_sun_shadow = false
var vg_shade = 0.0  // how much of its sky light a voxel in that shadow loses too (0: none, as before)
var vg_dither = 1.0
var vg_leaf_tones = 5.0

// The grid as a sprite in world_bake's frame (as voxel_bake's): RGBA bytes, rows top down, its size, the origin on it.
def vg_sprite(g:vgrid, shadow:bool) -> string, int, int, float2:
    // the voxels that show somewhere: those with an empty side
    let cell = []::int
    let pos = []::int3
    for(g.n.z) z:
        bake_pulse()
        for(g.n.y) y:
            var i = vg_index(g, 0, y, z)
            for(g.n.x) x:
                if g.mat[i] and (vg_get(g, x - 1, y, z) == 0 or vg_get(g, x + 1, y, z) == 0 or vg_get(g, x, y - 1, z) == 0 or
                                 vg_get(g, x, y + 1, z) == 0 or vg_get(g, x, y, z - 1) == 0 or vg_get(g, x, y, z + 1) == 0):
                    cell.push(i)
                    pos.push(int3 { x + g.lo.x, z + g.lo.z, y + g.lo.y })  // (the world's y is up)
                i++
    let sh = vm_shell { VG_PX / WB_PX, int3_0, int3_0, int3_0, [], pos, [], [], [], [] }
    def grid(w:float3) -> float3: return float3 { w.x, w.z, w.y }
    let to_light = grid(-light_along(VM_SUN))
    let to_eye = grid(euler(VM_VIEW).z)
    let half = normalize(to_light + to_eye)
    let k = g.k
    let look = g.look
    let tones = vg_field(g, 4.0, g.seed + 9)
    def solid(p:float3) -> bool: return vg_get(g, int(floor(p.x)), int(floor(p.y)), int(floor(p.z))) != 0
    def leafy(p:float3) -> bool: return vg_get(g, int(floor(p.x)), int(floor(p.y)), int(floor(p.z))) == VG_LEAF
    def share(c:float3, r:float, leaf_only:bool) -> float:  // how much of what's round c (radius r) is filled
        var hit = 0
        for(VG_DIRS) d:
            if (if leaf_only: leafy(c + d * r) else: solid(c + d * r)): hit++
            if (if leaf_only: leafy(c + d * r * 2.0) else: solid(c + d * r * 2.0)): hit++
        return float(hit) / float(VG_DIRS.length * 2)
    // the model seen from the sun: for each line of light, how near the sun its nearest voxel lies
    let lu = normalize(cross(to_light, float3 { 0.0, 0.0, 1.0 }))
    let lw = cross(to_light, lu)
    let far = float(g.n.x + g.n.y + g.n.z)
    let sw = int(far) * 2 + 2
    let sun_depth = if vg_sun_shadow: map(sw * sw): -1000000.0 else: []
    def sun_at(c:float3) -> int: return (int(dot(c, lw) + far) * sw) + int(dot(c, lu) + far)
    if vg_sun_shadow:
        for(cell) i:
            let c = float3 { float(i % g.n.x), float((i / g.n.x) % g.n.y), float(i / (g.n.x * g.n.y)) } + float3_1 * 0.5
            let at = sun_at(c)
            let d = dot(c, to_light)
            if d > sun_depth[at]: sun_depth[at] = d
    return vm_draw(sh, shadow) slot:
        let i = cell[slot]
        let x = i % g.n.x
        let y = (i / g.n.x) % g.n.y
        let z = i / (g.n.x * g.n.y)
        let m = g.mat[i]
        let c = float3 { float(x), float(y), float(z) } + float3_1 * 0.5
        // the normal: away from what's filled round it
        let sr = max(k * (if look.tree: 1.1 else: 0.8), 1.0)
        var nsum = float3_0
        for(VG_DIRS) d:
            if solid(c + d * sr): nsum -= d
            if solid(c + d * sr * 2.0): nsum -= d * 0.6
        let n = if magnitude(nsum) > 0.0: normalize(nsum) else: float3 { 0.0, 0.0, 1.0 }
        // its own shadow: anything between it and the sun
        var dark = 0.0
        if vg_sun_shadow:
            if sun_depth[sun_at(c)] > dot(c, to_light) + 2.5: dark = 1.0
        else:
            var r = c + n * 1.2 * k
            for(40):
                if solid(r): dark = 1.0
                r += to_light * 1.5 * k
        var diff = clamp(dot(n, to_light), 0.0, 1.0) * (1.0 - 0.8 * dark)
        if look.tree: diff *= 1.0 - clamp(share(c, 5.0 * k, true) - 0.25, 0.0, 1.0) * 1.6
        let ao = 1.0 - clamp(share(c, 3.0 * k, false) - 0.35, 0.0, 1.0) * 0.9
        let rim = pow(clamp(1.0 - abs(dot(n, to_eye)), 0.0, 1.0), 3.0) * (if n.z > -0.2: 1.0 else: 0.0)
        let light = ((if look.tree: 0.30 else: 0.42) + 0.12 * ao + 0.10 * rim) * (1.0 - vg_shade * dark) + 0.80 * diff * ao
        let tn = float(g.tone[i]) / 127.5 - 1.0
        let speck = vg_hash(g.seed + 1, x, y, z)
        let jitter = (speck - 0.5) * 0.18 * vg_dither
        let dz = c.z / k + float(g.lo.z) / k  // height, design units
        let shady = n.x * to_light.x + n.y * to_light.y < -0.3 * magnitude(float2 { to_light.x, to_light.y })
        var col = float3_0
        if m == VG_LEAF:
            let lv = clamp(light, 0.0, 1.25) / 1.25
            let q = floor(clamp(lv + jitter, 0.0, 1.0) * vg_leaf_tones + 0.5) / vg_leaf_tones
            let sun = look.leaf[0]
            let mid = look.leaf[1]
            let shade = look.leaf[2]
            col = if q < 0.5: shade + (mid - shade) * (q / 0.5) else: mid + (sun - mid) * ((q - 0.5) / 0.5)
            col = col * (1.0 + 0.10 * tn) + (look.leaf[3] - col) * clamp(tn - 0.4, 0.0, 1.0) * 0.5
        elif m == VG_BARK:
            let w = c / k
            let ridge = if not look.standing: 0.0 else: rsin(w.x * 1.7 + w.y * 1.3 + rsin(w.z * 0.15) * 2.0) * 0.12
            let bq = clamp(int(floor(clamp(light / 1.2 + jitter * 0.6 + ridge, 0.0, 0.999) * 3.99)), 0, 3)
            col = look.bark[bq]
            if look.standing and dz < 10.0 and shady: col = col * 0.5 + float3 { 0.30, 0.38, 0.16 } * 0.5
        elif m == VG_WOOD:
            let w = c / k
            let grain = rsin(magnitude(float2 { w.x, w.y }) * 2.2) * 0.06
            col = float3 { 0.80, 0.66, 0.44 } * (0.55 + 0.45 * clamp(light, 0.0, 1.2) + grain)
        else:
            let rt = vg_at(tones, c.x, c.y, c.z)
            var lq = clamp((light - 0.25) / 1.0 + (rt - 0.5) * 0.25 + (speck - 0.5) * 0.12 * vg_dither, 0.0, 0.999)
            if m == VG_CUT: lq = min(lq + 0.18, 0.999)
            col = look.rock[int(lq * float(look.rock.length))]
            if speck > 0.965: col *= 1.18  // quartz
            if speck < 0.03: col *= 0.7    // mica
            if m == VG_ROCK:
                if n.z > 0.5 and rt > 0.74: col = col * 0.45 + float3 { 0.70, 0.60, 0.30 } * 0.55 * (0.7 + 0.4 * light)  // lichen
                if dz < 8.0 and shady and rt < 0.38: col = col * 0.4 + float3 { 0.26, 0.34, 0.15 } * 0.6                 // moss
            if m == VG_GOLD:
                let gq = clamp((light - 0.3) / 0.9 + pow(clamp(dot(n, half), 0.0, 1.0), 12.0) * 0.8, 0.0, 0.999)
                col = [ float3 { 0.42, 0.28, 0.06 }, float3 { 0.70, 0.50, 0.12 }, float3 { 0.92, 0.74, 0.25 }, float3 { 1.0, 0.93, 0.62 } ][int(gq * 4.0)]
            elif look.strata and rsin(dz * 0.9 + rt * 3.0) > 0.82:
                col *= 0.78
        min(max(col, float3_0), float3_1)

// Voxels a design unit for a prop whose design unit is w world units.
def vg_k(w:float) -> float: return w * WB_PX / VG_PX

// A few of m's voxels left out at random (a crown's ragged edge).
def vg_thin(g:vgrid, m:int, frac:float):
    for(g.mat.length) i:
        if g.mat[i] == m and vg_hash(g.seed + 5, i, 0, 0) < frac: write_int8_le(g.mat, i, 0)

// About normal noise (sd 1), in each axis.
def vg_gauss(rng:Pcg) -> float: return (randf(rng) + randf(rng) + randf(rng) - 1.5) * 2.0
def vg_gauss3(rng:Pcg) -> float3:
    let x = vg_gauss(rng)
    let y = vg_gauss(rng)
    return float3 { x, y, vg_gauss(rng) }
