// Procedural voxel units, built from data (data/voxel/: materials, gear, bodies/<id>.json; docs/rendering.md,
// "Voxel units"): a body is named points on a skeleton, two-bone legs that walk, arms that hold, and shapes
// (capsules, balls, discs, boxes, chains, rings) on its points; gear is shapes in a hand's hold or fitted to a body.
// Filled into a voxel grid at a voxel a baked pixel and drawn in the game's 3/4 view in 8 facings: each surface voxel
// splatted with a depth test, banded light and self-shadows, fur flecked by a hash of the voxel, a dark outline, a
// ground shadow of its own. game/voxel_units.lobster bakes a match's units; voxel_proto.lobster draws a sheet.

var vx_ELEV = 30.0                                                      // the camera's elevation, degrees (a setting: see view/facing)
var vx_RES = 2.0                                                        // voxels a body unit (a body unit is about a world pixel; a voxel a baked pixel)
var vx_CELL = int2 { int(100.0 * vx_RES), int(170.0 * vx_RES) }         // a sprite cell (room for a siege tower; each is cropped to what's drawn)
var vx_ANCHOR = int2 { vx_CELL.x / 2, vx_CELL.y - int(40.0 * vx_RES) }  // the ground under the unit, in its cell (room in front: a cart's puller, a trunk)
let vx_VOX_RES = 2.0                                                    // a .vox model's voxels a body unit (the base's: a model is one size on every screen, #358)
let vx_BLEND = 0.8                                                      // how far body parts melt into each other, body units (round 1's 2.2 made muscles)

class vx_prim:
    a:float3
    b:float3
    ra:float
    rb:float
    mat:int
    hard:bool       // gear and fine details: no melting into the body
    disc:bool       // a disc round a, facing along b - a, ra across and rb thick
    box:float3      // not zero: a box round a, these half sizes (across, thick, up), facing along b - a, edges rounded by ra
    model:int = -1  // a .vox model (vx_models): its centre at a, its +y along b - a, its +x mx, its +z mz, ra a voxel
    mx:float3 = float3_0
    mz:float3 = float3_0

def vx_dist(p:float3, s:vx_prim) -> float:
    if s.model >= 0: return vx_model_sd(p, s)
    let ba = s.b - s.a
    if s.box.x > 0.0:
        let n = normalize(ba)
        let x = if abs(n.z) > 0.999: float3 { 1.0, 0.0, 0.0 } else: normalize(cross(n, float3 { 0.0, 0.0, 1.0 }))  // (facing straight up: it still has an across)
        let z = cross(x, n)
        let q = p - s.a
        let d = abs(float3 { dot(q, x), dot(q, n), dot(q, z) }) - s.box
        return magnitude(max(d, float3_0)) + min(max(d.x, max(d.y, d.z)), 0.0) - s.ra
    if s.disc:
        let n = normalize(ba)
        let q = p - s.a
        let h = dot(q, n)
        let w = float2 { magnitude(q - n * h) - s.ra, abs(h) - s.rb }
        return magnitude(max(w, float2_0)) + min(max(w.x, w.y), 0.0)
    let l2 = dot(ba, ba)
    let h = if l2 > 0.0: clamp(dot(p - s.a, ba) / l2, 0.0, 1.0) else: 0.0
    return magnitude(p - s.a - ba * h) - (s.ra + (s.rb - s.ra) * h)

def vx_smin(a:float, b:float, k:float) -> float:
    let h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25

def vx_cap(a:float3, b:float3, ra:float, rb:float, m:int) -> vx_prim: return vx_prim { a, b, ra, rb, m, false, false, float3_0 }
def vx_hard(a:float3, b:float3, ra:float, rb:float, m:int) -> vx_prim: return vx_prim { a, b, ra, rb, m, true, false, float3_0 }
def vx_ball(c:float3, r:float, m:int) -> vx_prim: return vx_prim { c, c, r, r, m, false, false, float3_0 }
def vx_bead(c:float3, r:float, m:int) -> vx_prim: return vx_prim { c, c, r, r, m, true, false, float3_0 }
def vx_disc(c:float3, n:float3, r:float, thick:float, m:int) -> vx_prim: return vx_prim { c, c + n, r, thick, m, true, true, float3_0 }
def vx_box(c:float3, n:float3, half:float3, round:float, m:int) -> vx_prim: return vx_prim { c, c + n, round, round, m, true, false, half }

// Two bones from a towards t (lengths l1, l2), the joint bent towards pole: the joint and where the end lands.
def vx_ik(a:float3, t:float3, l1:float, l2:float, pole:float3) -> float3, float3:
    let d = t - a
    let n = normalize(d)
    let dist = min(magnitude(d), (l1 + l2) * 0.999)
    let x = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
    let h = sqrt(max(l1 * l1 - x * x, 0.0))
    let side = normalize(pole - n * dot(pole, n))
    let joint = a + n * x + side * h
    return joint, joint + normalize(t - joint) * l2

// ---- the data: materials, shapes, bodies, gear (data/voxel/, read once by vx_load)

let vx_mat_names = []::string
let vx_MAT_BASE = []::float3
var vx_mat_cols = []::float3
let vx_MAT_FUR = []::int       // per material: flecked like fur
let vx_MAT_PAT = []::int       // per material: its surface pattern (vx_PATTERNS), 0 none
let vx_MAT_PSIZE = []::float2  // the pattern's size (body units: a block, a plank, a ripple, a tile)
let vx_MAT_PDEPTH = []::float  // how strongly it shades
let vx_MAT_PMIX = []::float    // how much of the second colour (mortar, rust, dirt) it lays on
let vx_MAT_C2 = []::float3     // the second colour
let vx_MAT_PROUND = []::int    // laid round a round wall (centred on vx_pat_centre), not flat across it
var vx_pat_centre = float2_0   // the shape's centre, grid voxels / vx_pat_scale (a round wall's axis)
let vx_MAT_GLOW = []::int      // a light (a lit window, a fire): its own colour unshaded, and a halo round it
let vx_MAT_SHINE = []::float   // how glossy (materials.json's "shine", 0..1; fur 0.25 by default): the specular highlight
var vx_pat_scale = 2.0         // voxels a body unit in the shape being drawn (the patterns are in body units)
let vx_PATTERNS = [ "", "blocks", "planks", "ripples", "tiles", "wear", "mottle" ]
var vx_mat_team = 0  // the team colour's material (the sprite shader's key)
var vx_fur = 0.07    // how strongly fur is flecked (the body's)

// A material scorched: its colour darkened towards soot, in soot patches (a wreck, #332). Made for every material when they're read.
let vx_BURNT_MIX = 0.5
let vx_SOOT = float3 { 0.13, 0.12, 0.11 }
var vx_burnt_of = []::int

def vx_mat(name:string) -> int:
    let m = find(vx_mat_names) n: n == name
    assert m >= 0
    return m

def vx_make_burnt():
    let n = vx_mat_names.length
    let mottle = find(vx_PATTERNS) p: p == "mottle"
    for(n) m:
        vx_burnt_of.push(vx_mat_names.length)
        vx_mat_names.push(vx_mat_names[m] + "#burnt")
        vx_MAT_BASE.push(vx_SOOT + (vx_MAT_BASE[m] - vx_SOOT) * vx_BURNT_MIX)
        vx_MAT_FUR.push(0)
        vx_MAT_PAT.push(mottle)
        vx_MAT_PSIZE.push(float2 { 3.0, 3.0 })
        vx_MAT_PDEPTH.push(0.1)
        vx_MAT_PMIX.push(0.45)
        vx_MAT_C2.push(vx_SOOT)
        vx_MAT_GLOW.push(0)
        vx_MAT_SHINE.push(0.0)
        vx_MAT_PROUND.push(0)

def vx_hex(h:string) -> float3:
    let s = if h.length and h[0] == '#': h.substring(1, h.length - 1) else: h
    def byte(i:int) -> float: return float(string_to_int(s.substring(i, 2), 16)) / 255.0
    return float3 { byte(0), byte(2), byte(4) }

def vx_new_mat(name:string) -> int:  // a material with every setting off, its colour black
    vx_mat_names.push(name)
    vx_MAT_BASE.push(float3_0)
    vx_MAT_FUR.push(0)
    vx_MAT_PAT.push(0)
    vx_MAT_PSIZE.push(float2_1)
    vx_MAT_PDEPTH.push(0.0)
    vx_MAT_PMIX.push(0.0)
    vx_MAT_C2.push(float3_0)
    vx_MAT_GLOW.push(0)
    vx_MAT_SHINE.push(0.0)
    vx_MAT_PROUND.push(0)
    return vx_mat_names.length - 1

// ---- .vox models as a shape (#313): a model is turned into a grid of signed distances to its surface (in its own
// voxels) and the material of the voxel nearest each cell, once at load, and sampled like any other part.
class vx_model:
    size:int3  // the model's own size
    dims:int3  // the grid: the model and vx_MODEL_PAD empty voxels round it
    sd:[float]
    mat:[int]

let vx_MODEL_PAD = 3
let vx_models = []::vx_model
let vx_model_keys = []::string  // per model: its file and material map
var vx_creel = []::int          // the creel.vox palette's colours, index 1 first: each a base material's swatch (vox_palette.lobster)
var vx_creel_mats = []::int
var vx_cur_dir = "../data/voxel"  // the data folder being loaded: a shape's model is in its models/

// A palette index's material: the shape's `mats` names it, else a material of exactly its colour, else a fixed
// material of its own (vox:<file>:<index>), shiny if MagicaVoxel calls it metal, a light if emissive.
def vx_vox_mat(f:vox_file, file:string, index:int, mats:JV) -> int:
    let key = string(index)
    if has(mats, key): return vx_mat(as_str(at(mats, key)))
    let rgb = vox_rgb(f, index)
    let c = float3 { float((rgb >> 16) & 255), float((rgb >> 8) & 255), float(rgb & 255) } / 255.0
    let same = find(vx_MAT_BASE) b: magnitude(b - c) < 0.001
    if same >= 0: return same
    let swatch = find(vx_creel) k: k == rgb  // (a creel.vox swatch a step off its colour, where two materials share one)
    if swatch >= 0: return vx_creel_mats[swatch]
    let name = "vox:{file}:{index}"
    var m = find(vx_mat_names) n: n == name
    if m < 0:
        m = vx_new_mat(name)
        vx_MAT_BASE[m] = c
        if vx_mat_cols.length: vx_mat_cols.push(c)
        let ty = vox_mat_type(f, index)
        if ty == "_metal": vx_MAT_SHINE[m] = 0.3 + 0.6 * vox_mat_float(f, index, "_metal", 0.5) * (1.0 - vox_mat_float(f, index, "_rough", 0.5))
        if ty == "_emit": vx_MAT_GLOW[m] = 1
    return m

def vx_cell_at(dims:int3, i:int) -> int3: return int3 { i % dims.x, (i / dims.x) % dims.y, i / (dims.x * dims.y) }

// Per cell, the nearest of the cells marked (by squared distance, spread from neighbour to neighbour).
def vx_nearest(dims:int3, marked:[bool]) -> [int]:
    let near = map(marked) m, i: if m: i else: -1
    let q = []::int
    for(marked) m, i: if m: q.push(i)
    var h = 0
    while h < q.length:
        let c = q[h]
        h += 1
        let cp = vx_cell_at(dims, c)
        let s = vx_cell_at(dims, near[c])
        for(27) k:
            let v = cp + int3 { k % 3 - 1, k / 3 % 3 - 1, k / 9 - 1 }
            if k != 13 and v.x >= 0 and v.y >= 0 and v.z >= 0 and v.x < dims.x and v.y < dims.y and v.z < dims.z:
                let j = (v.z * dims.y + v.y) * dims.x + v.x
                if near[j] < 0 or vx_sq(v - s) < vx_sq(v - vx_cell_at(dims, near[j])):
                    near[j] = near[c]
                    q.push(j)
    return near

def vx_sq(v:int3) -> int: return v.x * v.x + v.y * v.y + v.z * v.z

// A model shape's model: the first model in data/<folder>/models/<file>, with its palette mapped to materials.
def vx_model_of(file:string, mats:JV) -> int:
    let f = vx_vox_file(file)
    assert f.models.length
    return vx_model_in(f, file, 0, mats)

// A .vox file in the data folder's models/ (a broken one stops the load).
def vx_vox_file(file:string) -> vox_file:
    let bytes = read_file(vx_cur_dir + "/models/" + file)
    if not bytes: vx_vox_stop(file, [ "no such file in {vx_cur_dir}/models" ])
    let f = vox_parse(bytes)
    if f.error != "": vx_vox_stop(file, [ f.error ])
    return f

// A broken .vox stops the load, saying what's wrong with it ("file: why", one line each).
def vx_vox_stop(file:string, why:[string]):
    for(why) w: print "{file}: {w}"
    assert false

// Model n of a .vox file, its palette mapped to materials (loaded once per file, model and map).
def vx_model_in(f:vox_file, file:string, mi:int, mats:JV) -> int:
    var key = "{vx_cur_dir}/models/{file} {mi}"
    for(mats.keys) k, i: key += " {k}={as_str(mats.a[i])}"
    let had = find(vx_model_keys) k: k == key
    if had >= 0: return had
    let md = f.models[mi]
    let pad = int3_1 * vx_MODEL_PAD
    let dims = md.size + pad * 2
    let idx = map(dims.x * dims.y * dims.z): 0
    for(md.xyz) v, i:
        let c = v + pad
        idx[(c.z * dims.y + c.y) * dims.x + c.x] = md.idx[i]
    let mat_of = map(256) i: if i > 0 and (exists(idx) j: j == i): vx_vox_mat(f, file, i, mats) else: 0
    let solid = map(idx) i: i > 0
    let near_solid = vx_nearest(dims, solid)
    let near_air = vx_nearest(dims, map(solid) s: not s)
    let sd = map(idx) n, i:
        let v = vx_cell_at(dims, i)
        if n > 0: -(sqrt(float(vx_sq(v - vx_cell_at(dims, near_air[i])))) - 0.5)
        else: sqrt(float(vx_sq(v - vx_cell_at(dims, near_solid[i])))) - 0.5
    vx_models.push(vx_model { md.size, dims, sd, map(near_solid) j: mat_of[idx[j]] })
    vx_model_keys.push(key)
    return vx_models.length - 1

// A model prim's half size along the world's axes (its box turned).
def vx_model_reach(p:vx_prim) -> float3:
    let h = float(vx_models[p.model].size) * (p.ra * 0.5)
    let y = normalize(p.b - p.a)
    return abs(p.mx) * h.x + abs(y) * h.y + abs(p.mz) * h.z

// Where p is in a model prim's grid, in cells (a cell's centre at its index; outside the grid past its ends).
def vx_model_grid(p:float3, s:vx_prim) -> float3:
    let q = p - s.a
    return float3 { dot(q, s.mx), dot(q, normalize(s.b - s.a)), dot(q, s.mz) } / s.ra + float(vx_models[s.model].dims) * 0.5 - float3_1 * 0.5

// A model prim's distance at p (in p's units).
def vx_model_sd(p:float3, s:vx_prim) -> float:
    let md = vx_models[s.model]
    let dims = md.dims
    let u = vx_model_grid(p, s)
    let g = clamp(u, float3_0, float(dims - int3_1))
    let out = magnitude(u - g)
    let i0 = min(int3 { int(g.x), int(g.y), int(g.z) }, dims - int3 { 2, 2, 2 })
    let f = g - float(i0)
    def sd(x:int, y:int, z:int) -> float: return md.sd[((i0.z + z) * dims.y + i0.y + y) * dims.x + i0.x + x]
    let d = lerp(lerp(lerp(sd(0, 0, 0), sd(1, 0, 0), f.x), lerp(sd(0, 1, 0), sd(1, 1, 0), f.x), f.y),
                 lerp(lerp(sd(0, 0, 1), sd(1, 0, 1), f.x), lerp(sd(0, 1, 1), sd(1, 1, 1), f.x), f.y), f.z)
    // (inside or out as its nearest cell is, so a model scaled up stays square, corners and all; the blend only smooths
    // the distance for the normals)
    let n = int3 { int(g.x + 0.5), int(g.y + 0.5), int(g.z + 0.5) }
    let inside = md.sd[(n.z * dims.y + n.y) * dims.x + n.x] < 0.0 and out == 0.0
    return (if inside: min(d, -0.05) else: max(d, 0.05) + out) * s.ra

// A model prim's material at p: its nearest voxel's.
def vx_model_mat_at(p:float3, s:vx_prim) -> int:
    let md = vx_models[s.model]
    let g = clamp(vx_model_grid(p, s), float3_0, float(md.dims - int3_1))
    let n = int3 { int(g.x + 0.5), int(g.y + 0.5), int(g.z + 0.5) }
    return md.mat[(n.z * md.dims.y + n.y) * md.dims.x + n.x]

enum vx_kind:
    vx_k_cap, vx_k_ball, vx_k_disc, vx_k_box, vx_k_chain, vx_k_ring, vx_k_helm, vx_k_fit, vx_k_model

// A shape as data: on named points with offsets (in the body's frame, or a hold's for held gear).
class vx_spec:
    kind:int
    hard:bool
    mirror:bool
    pa:string
    a:float3
    pb:string
    b:float3
    ra:float
    rb:float
    mat:int
    mat2:int      // a chain's later links
    n:float3      // a disc's or box's facing
    half:float3   // a box's half sizes
    pts:[string]  // a chain's points
    offs:[float3]
    step:float  // a chain's radius: from ra by step a link, down to rb, each link tapering by taper
    taper:float
    need:[string]  // flags that must be there (if) and mustn't (unless)
    avoid:[string]
    model:int = -1        // a model shape's model (vx_models)
    flip:bool = false     // the model drawn mirrored (a left limb's part from the right one's)
    ax:float3 = float3_0  // not zero: the model's own axes in the body (a part placed in a .vox body), else the frame's
    ay:float3 = float3_0
    az:float3 = float3_0
    bone:bool = false  // a limb's part: on the bone from pa to pb, turned from its drawn direction (rest) along it
    rest:float3 = float3_0

def vx_v3(v:JV) -> float3: return float3 { as_float(v.a[0]), as_float(v.a[1]), as_float(v.a[2]) }
def vx_pt(v:JV) -> string, float3: return as_str(v.a[0]), float3 { as_float(v.a[1]), as_float(v.a[2]), as_float(v.a[3]) }

// (hard_by_default: gear's shapes don't melt into the body unless they say so)
def vx_parse_shape(o:JV, hard_by_default:bool) -> vx_spec:
    let s = vx_spec { vx_k_cap, gbool(o, "hard", hard_by_default), gbool(o, "mirror", false), "", float3_0, "", float3_0, 0.0, 0.0,
                      if has(o, "mat"): vx_mat(as_str(at(o, "mat"))) else: 0, 0, float3_0, float3_0, [], [], 0.0, 0.0,
                      gstrs(o, "if"), gstrs(o, "unless") }
    let rr = if has(o, "r"): at(o, "r") else: jnull()
    let r0 = if rr.kind == J_ARR: as_float(rr.a[0]) elif rr.kind != J_NULL: as_float(rr) else: 0.0
    let r1 = if rr.kind == J_ARR: as_float(rr.a[1]) else: r0
    if has(o, "cap"):
        s.pa, s.a = vx_pt(at(o, "cap"))
        s.pb, s.b = vx_pt(at(o, "to"))
        s.ra, s.rb = r0, r1
    elif has(o, "ball") or has(o, "bead"):
        s.kind = vx_k_ball
        s.pa, s.a = vx_pt(at(o, if has(o, "ball"): "ball" else: "bead"))
        s.ra, s.rb = r0, r0
        if has(o, "bead"): s.hard = true
    elif has(o, "disc"):
        s.kind = vx_k_disc
        s.pa, s.a = vx_pt(at(o, "disc"))
        s.n = normalize(vx_v3(at(o, "n")))
        s.ra, s.rb = r0, r1
        s.hard = true
    elif has(o, "box"):
        s.kind = vx_k_box
        s.pa, s.a = vx_pt(at(o, "box"))
        s.n = normalize(vx_v3(at(o, "n")))
        s.half = vx_v3(at(o, "half"))
        s.ra = as_float(at(o, "round"))
        s.hard = true
    elif has(o, "chain"):
        s.kind = vx_k_chain
        for(glist(o, "chain")) p:
            let pn, po = vx_pt(p)
            s.pts.push(pn)
            s.offs.push(po)
        s.ra, s.step, s.rb, s.taper = as_float(rr.a[0]), as_float(rr.a[1]), as_float(rr.a[2]), as_float(rr.a[3])
        let ms = gstrs(o, "mats")
        s.mat, s.mat2 = vx_mat(ms[0]), vx_mat(ms[1])
    elif has(o, "ring"):
        s.kind = vx_k_ring
        s.pa, s.a = vx_pt(at(o, "ring"))
        s.ra, s.rb = r0, r1  // the ring's radius and its tilt
        s.hard = true
    elif has(o, "helm"):
        s.kind = vx_k_helm
        s.ra = as_float(at(o, "helm"))
        s.hard = true
    elif has(o, "fit"):
        s.kind = vx_k_fit
        s.ra = as_float(at(o, "fit"))
        s.hard = true
    elif has(o, "model"):  // a .vox model in the data folder's models/: its centre on `at`, its +y aimed at `to` (if given)
        s.kind = vx_k_model
        s.model = vx_model_of(as_str(at(o, "model")), gobj(o, "mats"))
        s.pa, s.a = vx_pt(at(o, "at"))
        if has(o, "to"): s.pb, s.b = vx_pt(at(o, "to"))
        if has(o, "side"): s.n = vx_v3(at(o, "side"))  // its +x this way (held gear: a gun along the hand, its lock to the side)
        s.ra = gfloat(o, "scale", 1.0) / vx_VOX_RES
        s.hard = gbool(o, "hard", not gbool(o, "soft", false))
    else: assert false
    return s

def vx_parse_shapes(l:[JV]) -> [vx_spec]: return map(l) o: vx_parse_shape(o, false)
def vx_parse_gear_shapes(l:[JV]) -> [vx_spec]: return map(l) o: vx_parse_shape(o, true)

class vx_leg_spec:  // a pair of legs, the one given on the right, mirrored on the left
    pa:string
    a:float3
    foot:float3   // where its foot stands at rest (the right one's)
    stride:float  // how far a foot moves forward and back in a walk
    lift:float    // how high it lifts swinging forward
    phase:float   // degrees ahead in the walk (a back pair 180 from a front)
    l1:float      // the bones
    l2:float
    pole:float3  // where its middle joint bends (the right one's)
    r:[float]    // the thigh's two radii, the shin's
    mats:[int]
    shapes:[vx_spec]  // on hip, knee, ankle

// How a body walks and strikes, when that's more than a foot's sine and an arm's reach (none: it keeps those).
class vx_gait:
    heel:float   // degrees the toes dip leaving the ground
    toe:float    // and rise landing
    toes:float   // the ankle to the toes: a heel up, the ankle rises by this
    arm:float    // a free hand's swing, in reaches, against the leg on its side
    held:float   // a busy hand's
    twist:float  // the shoulders' turn against the walk, in units
    front:float  // a blow's stance: the left foot this far forward
    back:float   // the right foot this far back
    dip:float    // the body's drop into a blow
    turn:float   // the shoulders' turn into a blow, in units

// ---- Running gear: a belt that runs and wheels that turn, by the walk's phase, which goes by the ground covered
// (vx_walk_step). A cycle is one link's pitch, and the belt lies the same a pitch on, so the loop has no seam.

class vx_track:
    x:float      // the belt's middle, either side of the hull
    half:float   // half its width
    thick:float  // a link's half thickness
    bar:float    // the raised bar on each link, half its height (0: none)
    mat:int
    bar_mat:int
    ys:[float]  // the belt's middle line, round the outline of its circles
    zs:[float]
    runs:[float]  // how far round the belt each sample is
    total:float
    links:int
    pitch:float  // the length of a link, so that a whole number go round

class vx_wheel:
    at:float3  // mirrored across the hull unless it's on the middle
    axis:float3
    r:float
    thick:float
    mat:int
    face_r:float  // an inset face, in its own colour (0: none)
    face:int
    hub_r:float
    hub:int
    blades:int  // a prop or rotor: this many blades, turning a blade's angle a cycle
    marks:int   // bolts round its face, turning one bolt's angle a cycle (so the rim goes a pitch)

let VX_BELT_SAMPLES = 720

// The belt's line: the outline round circles [y, z, r], walked from the front, up and over.
def vx_parse_track(o:JV) -> vx_track:
    let circles = map(glist(o, "round")) c: float3 { as_float(c.a[0]), as_float(c.a[1]), as_float(c.a[2]) }
    let ys = []::float
    let zs = []::float
    for(VX_BELT_SAMPLES) i:
        let a = 360.0 * float(i) / float(VX_BELT_SAMPLES)
        var best = -1000000.0
        var y, z = 0.0, 0.0
        for(circles) c:
            let v = c.x * cos(a) + c.y * sin(a) + c.z
            if v > best:
                best = v
                y = c.x + c.z * cos(a)
                z = c.y + c.z * sin(a)
        ys.push(y)
        zs.push(z)
    let runs = []::float
    var total = 0.0
    for(VX_BELT_SAMPLES) i:
        runs.push(total)
        let n = (i + 1) % VX_BELT_SAMPLES
        total += magnitude(float2 { ys[n] - ys[i], zs[n] - zs[i] })
    let want = as_float(at(o, "pitch"))
    let links = max(4, int(total / want + 0.5))
    return vx_track { as_float(at(o, "x")), as_float(at(o, "half")), gfloat(o, "thick", 0.42), gfloat(o, "bar", 0.26), vx_mat(gstr(o, "mat", "pale")),
                      vx_mat(gstr(o, "bar_mat", "frame2")), ys, zs, runs, total, links, total / float(links) }

def vx_parse_wheel(o:JV, pitch:float) -> vx_wheel:
    let r = as_float(at(o, "r"))
    let marks = if has(o, "blades"): 0 elif pitch > 0.0: max(1, int(2.0 * 3.14159265 * r / pitch + 0.5)) else: 0
    return vx_wheel { vx_v3(at(o, "at")), if has(o, "axis"): normalize(vx_v3(at(o, "axis"))) else: float3 { 1.0, 0.0, 0.0 }, r, gfloat(o, "thick", 0.9), vx_mat(gstr(o, "mat", "pale")),
                      gfloat(o, "face_r", 0.0), vx_mat(gstr(o, "face", "mark")), gfloat(o, "hub_r", 0.0), vx_mat(gstr(o, "hub", "frame2")), gint(o, "blades", 0), marks }

// The belt on both sides, at phase ph (degrees; 360 is a pitch on).
def vx_track_prims(out:[vx_prim], t:vx_track, ph:float):
    let shift = t.pitch * ph / 360.0
    for(t.links) l:
        // (going forward the top run goes forward over the hull: against the way the line is walked)
        var s = float(l) * t.pitch - shift
        while s < 0.0: s += t.total
        while s >= t.total: s -= t.total
        var i = 0
        while i + 1 < VX_BELT_SAMPLES and t.runs[i + 1] <= s: i++
        let n = (i + 1) % VX_BELT_SAMPLES
        let seg = max(0.0001, (if n: t.runs[n] else: t.total) - t.runs[i])
        let f = (s - t.runs[i]) / seg
        let y = t.ys[i] + (t.ys[n] - t.ys[i]) * f
        let z = t.zs[i] + (t.zs[n] - t.zs[i]) * f
        let i0, i1 = (i + VX_BELT_SAMPLES - 3) % VX_BELT_SAMPLES, (i + 4) % VX_BELT_SAMPLES
        var dir = normalize(float2 { t.ys[i1] - t.ys[i0], t.zs[i1] - t.zs[i0] })
        if abs(dir.x) < 0.05: dir = normalize(float2 { if dir.x < 0.0: -0.05 else: 0.05, dir.y })  // (a box can't face straight up)
        let out_y, out_z = dir.y, -dir.x
        for([ t.x, -t.x ]) x:
            let tang = float3 { 0.0, dir.x, dir.y }
            out.push(vx_box(float3 { x, y, z }, tang, float3 { t.half, t.pitch * 0.56, t.thick }, 0.05, t.mat))
            if t.bar > 0.0:
                out.push(vx_box(float3 { x, y + out_y * t.thick, z + out_z * t.thick }, tang, float3 { t.half, 0.4, t.bar }, 0.03, t.bar_mat))

// The wheels, props and rotors, at phase ph.
def vx_wheel_prims(out:[vx_prim], ws:[vx_wheel], ph:float):
    for(ws) w:
        let u = if abs(w.axis.z) > 0.9: float3 { 1.0, 0.0, 0.0 } else: normalize(cross(w.axis, float3 { 0.0, 0.0, 1.0 }))
        let v = cross(w.axis, u)
        for(if w.at.x == 0.0: [ 1.0 ] else: [ 1.0, -1.0 ]) side:
            let c = float3 { w.at.x * side, w.at.y, w.at.z }
            let face_at = c + w.axis * side * (w.thick + 0.25)
            if w.blades > 0:
                for(w.blades) k:
                    let a = 360.0 * float(k) / float(w.blades) - ph / float(w.blades)
                    out.push(vx_hard(c, c + (u * cos(a) + v * sin(a)) * w.r, w.thick, w.thick * 0.5, w.mat))
            else:
                out.push(vx_disc(c, w.axis, w.r, w.thick, w.mat))
                if w.face_r > 0.0: out.push(vx_disc(face_at, w.axis, w.face_r, 0.28, w.face))
                if w.hub_r > 0.0: out.push(vx_disc(face_at + w.axis * side * 0.3, w.axis, w.hub_r, 0.22, w.hub))
                for(w.marks) k:
                    let a = 360.0 * float(k) / float(w.marks) - ph / float(w.marks)
                    out.push(vx_bead(face_at + w.axis * side * 0.3 + (u * cos(a) + v * sin(a)) * w.face_r * 0.8, 0.28, w.hub))

class vx_part_spec:
    name:string
    pivot:float3          // where it turns, in the body's frame
    body:string           // its own body: its shapes round the pivot, standing at their own height
    point_names:[string]  // named points on it (a muzzle), in the body's frame
    point_at:[float3]

class vx_body_spec:
    id:string
    size:float
    fur:float
    skin_scale:float
    reach:float
    skin:float3  // its colours when the race gives none
    pale:float3
    mark:float3    // a third: markings, a muzzle (palettes' third colour)
    flies:float    // how high it flies (0: it walks; its points are set at that height)
    pflap:[float]  // per point: how far it flaps up and down (wings) as it moves
    harness:bool   // no hands: what it holds rides in a harness at these points (right, left)
    hr_pt:string
    hr:float3
    hr_dir:float3
    hl_pt:string
    hl:float3
    fused_pt:string  // a mount a rider grows out of (a centaur's horse): where its rider's hip is
    fused:float3
    pnames:[string]
    pat:[float3]
    pbob:[float]
    legs:[vx_leg_spec]
    shapes:[vx_spec]
    arms:bool
    sh_pt:string  // the right shoulder (mirrored on the left)
    sh:float3
    arm:float  // each arm bone
    thick:float
    sleeve:int
    hand:int
    helm_pt:string  // a helmet's centre and radius: the skull's, a little more
    helm:float3
    helm_r:float
    fit_pa:string  // armour's spot: a capsule over the trunk
    fit_a:float3
    fit_pb:string
    fit_b:float3
    fit_r:float2
    seat_z:float  // a rider: its seat's height in its own frame, and its legs astride: thigh, shin, foot
    astride:[int]
    seat:float3  // a mount: where its rider sits, how far out its rider's knees go
    wide:float
    looks:[float]              // per look: the skin shade
    hair:[float3]              // and hair colour
    crew:[float3] = []         // an engine: where its crew stand (on their own legs, walking as it moves)
    seats:[float3] = []        // a war beast: where its crew sit (a howdah), at their seat height
    style_names:[string] = []  // an engine in each culture's style (siege.<kind>.<style>): its skin, pale, mark
    parts:[vx_part_spec] = []  // pieces that turn on their own (a turret): this body is the whole figure (a portrait, a fall)
    hull:string = ""           // with parts: the body without them
    piece:bool = false         // a hull or a part: on the ground as the whole body is, not under its own lowest point
    death:string = ""          // how it dies: "knocked_out", "crash", or falling over
    h:float = 0.0              // sizes.json: its height, bare and standing, in voxels (a rider's mount is sized from it)
    ride:float = 0.0           // sizes.json: a mount: its size under a rider of the human's height
    deck:float2 = float2_0     // sizes.json: a war beast: the half sizes of the deck its crew sit on, body units
    rides_as:float = 0.0       // sizes.json: a squat rider: the height to size its mount from, in voxels (its h if 0)
    crew_k:float = 1.0         // sizes.json: how much bigger or smaller this body sits as a crew member
    crew_seats:int = 0         // sizes.json: 1: it takes a howdah to itself, in the middle
    track:vx_track? = nil
    wheels:[vx_wheel] = []
    style_cols:[float3] = []
    plean:[float] = []   // per point, with a gait: how far forward it leans walking
    psway:[float] = []   // how far it shifts over the planted foot
    pdrive:[float] = []  // how far a blow carries it forward
    gait:vx_gait? = nil
    tool_jobs:[string] = []  // gear it uses in place of the kit's (a robot's laser cutter for the axe and the pick)
    tool_gear:[string] = []
    bare:bool = false     // it wears nothing (a robot: no caps or armour on it)
    leg_r:[vx_spec] = []  // a .vox body's limb parts (thigh, shin; upper_arm, forearm), right and left, on every pair of legs
    leg_l:[vx_spec] = []
    arm_r:[vx_spec] = []
    arm_l:[vx_spec] = []
    vox_bones:[string] = []  // the bones its .vox draws (their capsules aren't drawn)

class vx_hold_spec:
    rest:float3
    dir:float3
    swing:float
    wind:float3
    wind_dir:float3
    hit:float3
    hit_dir:float3
    act:bool      // wind and hit given
    raise:float3  // a bow: raised, and drawn by the other hand
    draw:float3
    draws:bool
    pick:float3  // a basket: where the other hand picks from, and drops into it
    drop:float3
    picks:bool
    aim:float3  // a gun: brought up here to fire, along aim_dir, for the whole cycle
    aim_dir:float3
    aims:bool
    kick:float     // how far the shot throws it back, in arms
    support:float  // how far along it the other hand holds it, body units (0: it doesn't)

// What a worker takes home: gear held, or a cart pushed (barrow or cart) under a heap of its material.
class vx_load_spec:
    gear:string
    push:string
    heap:int

class vx_gear_spec:
    id:string
    hand:int  // 1 right, -1 left, 0 worn
    hold:string
    dir:float3   // a hold's direction for this gear (zero: the hold's)
    face:float3  // a left-hand item's facing
    shapes:[vx_spec]
    fit_ids:[string]
    fits:[[vx_spec]]
    flags:[string]
    legs:[vx_spec]  // worn gear's shapes on each leg (hip, knee, ankle) and arm (shoulder, elbow, hand), the right one
    arms:[vx_spec]  // given, mirrored on the left: power armour's greaves and gauntlets

class vx_rule:
    part:string
    tag:string
    slot:string
    gear:string

let vx_bodies = dictionary<string, vx_body_spec>(64)
let vx_gears = dictionary<string, vx_gear_spec>(128)
let vx_holds = dictionary<string, vx_hold_spec>(32)
let vx_loads = dictionary<string, vx_load_spec>(32)  // "<body or *> <resource>"
var vx_rules = []::vx_rule
var vx_loaded = false
var vx_data_dirs = []::string

def vx_parse_body(id:string, o:JV) -> vx_body_spec:
    let b = vx_body_spec { id, gfloat(o, "size", 1.0), gfloat(o, "fur", 0.0), gfloat(o, "skin_scale", 1.0), gfloat(o, "reach", 4.0),
                           vx_hex(gstr(o, "skin", "#dba880")), vx_hex(gstr(o, "pale", "#ebbf99")), vx_hex(gstr(o, "mark", "#f0ebe0")),
                           gfloat(o, "flies", 0.0), [], false, "", float3_0, float3_0, "", float3_0, "", float3_0,
                           [], [], [], [], [], false, "", float3_0, 0.0, 0.0, 0, 0, "", float3_0, 0.0, "", float3_0, "", float3_0, float2_0,
                           0.0, [], float3_0, 0.0, [ 1.0 ], [ vx_MAT_BASE[vx_mat("hair")] ] }
    let pts = gobj(o, "points")
    for(pts.keys) name, k:
        b.pnames.push(name)
        b.pat.push(vx_v3(at(pts.a[k], "at")))
        b.pbob.push(gfloat(pts.a[k], "bob", 0.0))
        b.pflap.push(gfloat(pts.a[k], "flap", 0.0))
        b.plean.push(gfloat(pts.a[k], "lean", 0.0))
        b.psway.push(gfloat(pts.a[k], "sway", 0.0))
        b.pdrive.push(gfloat(pts.a[k], "drive", 0.0))
    for(glist(o, "legs")) l:
        let pa, a = vx_pt(at(l, "hip"))
        let rs = map(glist(l, "r")) v: as_float(v)
        b.legs.push(vx_leg_spec { pa, a, vx_v3(at(l, "foot")), gfloat(l, "stride", 0.0), gfloat(l, "lift", 0.0), gfloat(l, "phase", 0.0),
                                  as_float(glist(l, "bones")[0]), as_float(glist(l, "bones")[1]), vx_v3(at(l, "pole")), rs,
                                  map(gstrs(l, "mats")) m: vx_mat(m), vx_parse_shapes(glist(l, "shapes")) })
    b.shapes = vx_parse_shapes(glist(o, "shapes"))
    if has(o, "arms"):
        let ar = at(o, "arms")
        b.arms = true
        b.sh_pt, b.sh = vx_pt(at(ar, "shoulder"))
        b.arm, b.thick = as_float(at(ar, "bone")), as_float(at(ar, "thick"))
        b.sleeve, b.hand = vx_mat(gstr(ar, "sleeve", "skin")), vx_mat(gstr(ar, "hand", "skin"))
    if has(o, "harness"):
        let ho = at(o, "harness")
        b.harness = true
        b.hr_pt, b.hr = vx_pt(at(ho, "right"))
        b.hr_dir = vx_v3(at(ho, "dir"))
        b.hl_pt, b.hl = vx_pt(at(ho, "left"))
    if has(o, "fused"): b.fused_pt, b.fused = vx_pt(at(o, "fused"))
    if has(o, "helm"):
        b.helm_pt, b.helm = vx_pt(at(at(o, "helm"), "at"))
        b.helm_r = as_float(at(at(o, "helm"), "r"))
    if has(o, "armour"):
        let fo = at(o, "armour")
        b.fit_pa, b.fit_a = vx_pt(at(fo, "a"))
        b.fit_pb, b.fit_b = vx_pt(at(fo, "b"))
        b.fit_r = float2 { as_float(glist(fo, "r")[0]), as_float(glist(fo, "r")[1]) }
    if has(o, "seat"):
        let so = at(o, "seat")
        b.seat_z = gfloat(so, "z", 0.0)
        b.astride = map(gstrs(so, "astride")) m: vx_mat(m)
        if has(so, "at"): b.seat = vx_v3(at(so, "at"))
        b.wide = gfloat(so, "wide", 0.0)
    if has(o, "looks"):
        b.looks = map(glist(o, "looks")) l: gfloat(l, "skin", 1.0)
        b.hair = map(glist(o, "looks")) l: vx_hex(gstr(l, "hair", "#1f1714"))
    if has(o, "gait"):
        let g = at(o, "gait")
        b.gait = vx_gait { gfloat(g, "heel", 0.0), gfloat(g, "toe", 0.0), gfloat(g, "toes", 0.0), gfloat(g, "arm", 0.0), gfloat(g, "held", 0.0),
                           gfloat(g, "twist", 0.0), gfloat(g, "front", 0.0), gfloat(g, "back", 0.0), gfloat(g, "dip", 0.0), gfloat(g, "turn", 0.0) }
    b.crew = map(glist(o, "crew")) v: vx_v3(v)
    b.seats = map(glist(o, "seats")) v: vx_v3(v)
    let so = gobj(o, "styles")
    for(so.keys) name, k:
        b.style_names.push(name)
        for([ "skin", "pale", "mark" ]) c: b.style_cols.push(vx_hex(gstr(so.a[k], c, "#808080")))
    let to = gobj(o, "tools")
    b.tool_jobs = copy(to.keys)
    b.tool_gear = map(to.a) t: as_str(t)
    b.bare = gbool(o, "bare", false)
    if has(o, "tracks"): b.track = vx_parse_track(at(o, "tracks"))
    let tr = b.track
    b.wheels = map(glist(o, "wheels")) w: vx_parse_wheel(w, if tr: tr.pitch else: 0.0)
    b.death = gstr(o, "death", "")
    vx_parse_parts(b, glist(o, "parts"))
    if has(o, "vox"): vx_vox_body(b, as_str(at(o, "vox")), gobj(o, "mats"))
    return b

// ---- a body from a .vox file (#313): drawn standing, each piece its own object named after what it rides. A limb
// (thigh, shin, upper_arm, forearm; .r, and .l or the .r mirrored) is posed where it sits: its ends give the joints
// (the hip at the thigh's top, the knee where thigh and shin meet ...) and the bones' lengths, and it rides its bone as
// the rig moves. A foot or a hand (foot.r, hand.r) rides the ankle or the hand; anything else rides the body point it's
// named after (head, chest ...). A hidden `points` layer (one voxel each) moves the body's points or adds new ones, and
// places the helmet (helm). Its JSON keeps the behaviour (gait, stride, size, looks).
let vx_VOX_BONES = [ "thigh", "shin", "upper_arm", "forearm" ]
let vx_VOX_ENDS = [ "hip", "knee", "knee", "ankle", "shoulder", "elbow", "elbow", "hand" ]

def vx_vox_axis(r:[int3], k:int) -> float3: return float3 { float(r[0][k]), float(r[1][k]), float(r[2][k]) }

class vx_vox_piece:
    name:string  // its bone or point (thigh, foot, head ...), and side ("r", "l", "")
    side:string
    node:int
    centre:float3  // the middle of its model's box, body units
    lo:float3      // the middle of each end along its longest side
    hi:float3

// A shown object: where it sits, and its two ends.
def vx_vox_piece_of(f:vox_file, nd:vox_node, i:int) -> vx_vox_piece:
    let md = f.models[nd.model]
    let ax = [ vx_vox_axis(nd.r, 0), vx_vox_axis(nd.r, 1), vx_vox_axis(nd.r, 2) ]
    let half = float(md.size - int3_1) * 0.5 - float(md.size / 2)
    let centre = (ax[0] * half.x + ax[1] * half.y + ax[2] * half.z + float(nd.t) + float3_1 * 0.5) / vx_VOX_RES
    let long = if md.size.z >= md.size.x and md.size.z >= md.size.y: 2 elif md.size.y >= md.size.x: 1 else: 0
    let at = map(md.xyz.length) n: (float(vox_world(f, nd, n)) + float3_1 * 0.5) / vx_VOX_RES
    let along = map(at) p: dot(p, ax[long])
    let a0 = fold(along, 1000000.0) m, x: min(m, x)
    let a1 = fold(along, -1000000.0) m, x: max(m, x)
    def end(v:float) -> float3:  // (the middle of the voxels in the end slice)
        var s = float3_0
        var n = 0
        for(at) p, k:
            if abs(along[k] - v) < 0.5 / vx_VOX_RES:
                s += p
                n++
        return s / float(n)
    let dot_at = find(nd.name) c: c == '.'
    let name = if dot_at > 0: substring(nd.name, 0, dot_at) else: nd.name
    let side = if dot_at > 0: substring(nd.name, dot_at + 1, nd.name.length - dot_at - 1) else: ""
    return vx_vox_piece { name, side, i, centre, end(a0), end(a1) }

// What's wrong with a .vox body for body b, or nothing: each shown object a limb piece (thigh, shin, upper_arm,
// forearm, foot, hand; .r or .l, a limb's two pieces together, the .r drawn) or named after one of b's points; mats
// mapping a palette index to one of our materials.
def vx_vox_problems(f:vox_file, b:vx_body_spec, mats:JV) -> [string]:
    let out = []::string
    let shown = []::string
    for(f.nodes) nd:
        if nd.layer != "points" and not nd.hidden:
            shown.push(nd.name)
            let dot_at = find(nd.name) c: c == '.'
            let name = if dot_at > 0: substring(nd.name, 0, dot_at) else: nd.name
            let side = if dot_at > 0: substring(nd.name, dot_at + 1, nd.name.length - dot_at - 1) else: ""
            let limb = (find(vx_VOX_BONES) n: n == name) >= 0 or name == "foot" or name == "hand"
            if nd.name == "": out.push("an object without a name (name it after a body point or a limb piece)")
            elif limb and side != "r" and side != "l": out.push("{nd.name}: a limb piece ends .r or .l")
            elif not limb and (find(b.pnames) n: n == nd.name) < 0:
                let known = concat_string(b.pnames, ", ")
                out.push("{nd.name}: not a body point ({known}) or a limb piece")
    for(2) limb: for([ "r", "l" ]) side:
        let up = "{vx_VOX_BONES[limb * 2]}.{side}"
        let low = "{vx_VOX_BONES[limb * 2 + 1]}.{side}"
        let has_up = (find(shown) n: n == up) >= 0
        let has_low = (find(shown) n: n == low) >= 0
        if has_up != has_low: out.push(if has_up: "{up} without {low}" else: "{low} without {up}")
        if side == "l" and has_up and (find(shown) n: n == "{vx_VOX_BONES[limb * 2]}.r") < 0:
            out.push("{up} without {vx_VOX_BONES[limb * 2]}.r (the right side sets the joints)")
    for(mats.keys) k, i:
        let n = string_to_int(k)
        if n < 1 or n > 255 or string(n) != k: out.push("mats: {k} isn\'t a palette index (1 to 255)")
        if (find(vx_mat_names) m: m == as_str(mats.a[i])) < 0: out.push("mats: {k} names {as_str(mats.a[i])}, not one of our materials")
    return out

def vx_vox_body(b:vx_body_spec, file:string, mats:JV):
    let f = vx_vox_file(file)
    let wrong = vx_vox_problems(f, b, mats)
    if wrong.length: vx_vox_stop(file, wrong)
    def rest(name:string) -> float3:
        let k = find(b.pnames) n: n == name
        assert k >= 0
        return b.pat[k]
    for(f.nodes) nd:
        if nd.layer == "points":
            let at = (float(vox_world(f, nd, 0)) + float3_1 * 0.5) / vx_VOX_RES
            let k = find(b.pnames) n: n == nd.name
            if nd.name == "helm": b.helm = at - rest(b.helm_pt)
            elif k >= 0: b.pat[k] = at
            else:
                b.pnames.push(nd.name)
                b.pat.push(at)
                for([ b.pbob, b.pflap, b.plean, b.psway, b.pdrive ]) l: l.push(0.0)
    let pieces = []::vx_vox_piece
    for(f.nodes) nd, i: if nd.layer != "points" and not nd.hidden: pieces.push(vx_vox_piece_of(f, nd, i))
    def piece(name:string, side:string) -> int: return find(pieces) q: q.name == name and q.side == side
    // the joints of one side, from its limbs' ends (each limb's top: the end nearer the joint before it)
    def joints(side:string, limb:int) -> [float3]:  // limb 0 the leg (hip, knee, ankle), 1 the arm (shoulder, elbow, hand)
        let up = piece(vx_VOX_BONES[limb * 2], side)
        let low = piece(vx_VOX_BONES[limb * 2 + 1], side)
        if up < 0 or low < 0: return []
        var root = if limb == 0: rest(b.legs[0].pa) else: rest(b.sh_pt)
        if side == "l": root *= float3 { -1.0, 1.0, 1.0 }
        let u = pieces[up]
        let l = pieces[low]
        let uf = magnitude(u.lo - root) > magnitude(u.hi - root)
        let u0 = if uf: u.hi else: u.lo
        let u1 = if uf: u.lo else: u.hi
        let lf = magnitude(l.lo - u1) > magnitude(l.hi - u1)
        let l0 = if lf: l.hi else: l.lo
        let l1 = if lf: l.lo else: l.hi
        return [ u0, (u1 + l0) * 0.5, l1 ]
    let leg = joints("r", 0)
    if leg.length:
        let l = b.legs[0]
        l.a = leg[0] - rest(l.pa)
        l.l1, l.l2 = magnitude(leg[1] - leg[0]), magnitude(leg[2] - leg[1])
        l.foot = leg[2]
    let arm = joints("r", 1)
    if arm.length:
        b.sh = arm[0] - rest(b.sh_pt)
        b.arm = (magnitude(arm[1] - arm[0]) + magnitude(arm[2] - arm[1])) * 0.5
    // the parts (body, not gear: soft, so the legs set the ground and the joints blend)
    for(pieces) q:
        let nd = f.nodes[q.node]
        let s = vx_spec { vx_k_model, false, false, "", float3_0, "", float3_0, 1.0 / vx_VOX_RES, 0.0, 0, 0, float3_0, float3_0, [], [], 0.0, 0.0,
                          [], [], model: vx_model_in(f, file, nd.model, mats), ax: vx_vox_axis(nd.r, 0), ay: vx_vox_axis(nd.r, 1),
                          az: vx_vox_axis(nd.r, 2) }
        let bone = find(vx_VOX_BONES) n: n == q.name
        let limb = if bone >= 0: bone / 2 elif q.name == "foot": 0 elif q.name == "hand": 1 else: -1
        if limb >= 0:
            assert q.side == "r" or q.side == "l"
            let js = joints(q.side, limb)
            assert js.length  // (a limb needs both its pieces on its side)
            if bone >= 0:
                let a, z = js[bone % 2], js[bone % 2 + 1]
                s.bone = true
                s.pa, s.pb = vx_VOX_ENDS[bone * 2], vx_VOX_ENDS[bone * 2 + 1]
                s.rest = normalize(z - a)
                s.a = q.centre - (a + z) * 0.5
                if (find(b.vox_bones) n: n == q.name) < 0: b.vox_bones.push(q.name)
            else:
                s.pa = if limb == 0: "ankle" else: "hand"
                s.a = q.centre - js[2]
            (if limb == 0: (if q.side == "r": b.leg_r else: b.leg_l) else: (if q.side == "r": b.arm_r else: b.arm_l)).push(s)
            if q.side == "r" and piece(q.name, "l") < 0: (if limb == 0: b.leg_l else: b.arm_l).push(vx_mirrored(s))
        else:
            s.pa = q.name
            s.a = q.centre - rest(q.name)
            b.shapes.push(s)

// The gear body b uses for gear g (its own in its place, or g).
def vx_tool_for(b:vx_body_spec, tool:string) -> string:
    let k = find(b.tool_jobs) j: j == tool
    return if k >= 0: b.tool_gear[k] else: tool

// How far a body goes in one walk cycle, body units, for one with a belt: a link's pitch; else 0.
def vx_track_cycle(b:vx_body_spec) -> float:
    let t = b.track
    return if t: t.pitch else: 0.0

// A body's `parts` (a turret): `pivot` and `shapes`. Each becomes a body of its own, baked per facing; so does the hull
// without them; the body itself keeps all of it.
def vx_parse_parts(b:vx_body_spec, parts:[JV]):
    if not parts.length: return
    let hull = copy(b)
    hull.id = b.id + "#hull"
    hull.piece = true
    vx_bodies.set(hull.id, hull)
    b.hull = hull.id
    for(parts) o:
        let name = gstr(o, "name", "")
        assert name != ""
        if not has(o, "pivot"): print "body {b.id}: part {name} has no pivot"
        assert has(o, "pivot")
        let pivot = vx_v3(at(o, "pivot"))
        let shapes = vx_parse_shapes(glist(o, "shapes"))
        let piece = copy(b)
        piece.id = b.id + "#" + name
        piece.piece = true
        piece.hull = ""
        piece.parts = []
        piece.track = nil
        piece.wheels = []
        piece.shapes = map(shapes) s: vx_spec_moved(s, float3 { -pivot.x, -pivot.y, 0.0 })
        vx_bodies.set(piece.id, piece)
        let pts = gobj(o, "points")
        b.parts.push(vx_part_spec { name, pivot, piece.id, pts.keys, map(pts.a) v: vx_v3(v) })
        b.shapes = b.shapes.append(shapes)

def vx_spec_moved(s:vx_spec, by:float3) -> vx_spec:
    let c = copy(s)
    c.a = s.a + by
    c.b = s.b + by
    c.offs = map(s.offs) o: o + by
    return c

// Where a spot in a body's frame falls on its picture in that facing, voxels from the ground point (x right, y down).
def vx_spot_px(b:vx_body_spec, v:float3, facing:int) -> float2:
    let yaw = float(facing) * 45.0
    let across = v.x * cos(yaw) + v.y * sin(yaw)  // (as vx_cell: the body turned against the camera)
    let along = v.y * cos(yaw) - v.x * sin(yaw)
    let s = vx_RES * b.size
    return float2 { across * s, -(along * sin(vx_ELEV) + v.z * cos(vx_ELEV)) * s }

// Where a part's pivot falls on the hull's picture in that facing (its height is in the part's own picture).
def vx_pivot_px(b:vx_body_spec, p:vx_part_spec, facing:int) -> float2:
    return vx_spot_px(b, float3 { p.pivot.x, p.pivot.y, 0.0 }, facing)

// A named point on a part, on that part's own picture in its facing.
def vx_part_point_px(b:vx_body_spec, p:vx_part_spec, k:int, part_f:int) -> float2:
    return vx_spot_px(b, p.point_at[k] - float3 { p.pivot.x, p.pivot.y, 0.0 }, part_f)

// A named point on a part (or, with no part, the body or any part that has it), on the stacked figure with the hull and
// that part in these facings, or false if it has none.
def vx_point_px(b:vx_body_spec, name:string, part:string, hull_f:int, part_f:int) -> float2, bool:
    for(b.parts) p:
        let k = if part == "" or part == p.name: find(p.point_names) n: n == name else: -1
        if k >= 0: return vx_pivot_px(b, p, hull_f) + vx_part_point_px(b, p, k, part_f), true
    let k = find(b.pnames) n: n == name
    if k >= 0: return vx_spot_px(b, b.pat[k], hull_f), true
    return float2_0, false

def gfloat(o:JV, k:string, fallback:float) -> float: return if has(o, k): as_float(at(o, k)) else: fallback

def vx_v3_or(o:JV, k:string) -> float3: return if has(o, k): vx_v3(at(o, k)) else: float3_0

// Reads data/voxel/ (and a mod's, which add or replace by id) once.
def vx_load(dirs:[string]):
    if vx_loaded: return
    vx_loaded = true
    vx_data_dirs = dirs
    for(dirs) d:
        let mo = parse_json(read_file(d + "/materials.json") or "\{\}")
        for(mo.keys) name, k:
            if name[0] != '_':
                var m = find(vx_mat_names) n: n == name
                if m < 0: m = vx_new_mat(name)
                vx_MAT_BASE[m] = vx_hex(gstr(mo.a[k], "rgb", "#ff00ff"))
                vx_MAT_FUR[m] = if gbool(mo.a[k], "fur", false): 1 else: 0
                vx_MAT_GLOW[m] = if gbool(mo.a[k], "glow", false): 1 else: 0
                vx_MAT_SHINE[m] = gfloat(mo.a[k], "shine", if vx_MAT_FUR[m] != 0: 0.25 else: 0.0)
                if has(mo.a[k], "pattern"):
                    let po = at(mo.a[k], "pattern")
                    vx_MAT_PAT[m] = find(vx_PATTERNS) n: n == gstr(po, "kind", "")
                    assert vx_MAT_PAT[m] > 0
                    let sz = glist(po, "size")
                    vx_MAT_PSIZE[m] = if sz.length >= 2: float2 { as_float(sz[0]), as_float(sz[1]) } else: float2_1
                    vx_MAT_PDEPTH[m] = gfloat(po, "depth", 0.15)
                    vx_MAT_PMIX[m] = gfloat(po, "mix", 0.0)
                    vx_MAT_C2[m] = vx_hex(gstr(po, "color2", "#000000"))
                    vx_MAT_PROUND[m] = if gbool(po, "round", false): 1 else: 0
    let creel = read_file(dirs[0] + "/creel.vox")
    if creel:
        let cf = vox_parse(creel)
        assert cf.error == ""
        let base = filter(vx_mat_names.length) m: (find(vx_mat_names[m]) c: c == '#') < 0
        vx_creel = map(base.length) i: vox_rgb(cf, i + 1)
        vx_creel_mats = base
    vx_make_burnt()
    vx_mat_cols = copy(vx_MAT_BASE)
    vx_mat_team = vx_mat("team")
    for(dirs) d:
        vx_cur_dir = d
        let go = parse_json(read_file(d + "/gear.json") or "\{\}")
        if has(go, "holds"):
            let ho = at(go, "holds")
            for(ho.keys) name, k:
                let h = ho.a[k]
                vx_holds.set(name, vx_hold_spec { vx_v3(at(h, "rest")), vx_v3_or(h, "dir"), gfloat(h, "swing", 0.0), vx_v3_or(h, "wind"),
                                                  vx_v3_or(h, "wind_dir"), vx_v3_or(h, "hit"), vx_v3_or(h, "hit_dir"), has(h, "hit"),
                                                  vx_v3_or(h, "raise"), vx_v3_or(h, "draw"), has(h, "draw"),
                                                  vx_v3_or(h, "pick"), vx_v3_or(h, "drop"), has(h, "pick"),
                                                  vx_v3_or(h, "aim"), vx_v3_or(h, "aim_dir"), has(h, "aim"), gfloat(h, "kick", 0.0), gfloat(h, "support", 0.0) })
        if has(go, "loads"):
            let lo = at(go, "loads")
            for(lo.keys) who, i:
                let rs = lo.a[i]
                for(rs.keys) res, k:
                    let l = rs.a[k]
                    let heap = gstr(l, "heap", "")
                    vx_loads.set("{who} {res}", vx_load_spec { gstr(l, "gear", ""), gstr(l, "push", ""), if heap != "": vx_mat(heap) else: 0 })
        if has(go, "gear"):
            let gs = at(go, "gear")
            for(gs.keys) name, k:
                let g = gs.a[k]
                let hand = gstr(g, "hand", "")
                let fits = gobj(g, "fits")
                vx_gears.set(name, vx_gear_spec { name, if hand == "right": 1 elif hand == "left": -1 else: 0, gstr(g, "hold", ""),
                                                  vx_v3_or(g, "dir"), normalize(if has(g, "face"): vx_v3(at(g, "face")) else: float3 { 0.0, 1.0, 0.0 }),
                                                  vx_parse_gear_shapes(glist(g, "shapes")), copy(fits.keys), map(fits.a) l: vx_parse_gear_shapes(l.a),
                                                  gstrs(g, "flags"), vx_parse_gear_shapes(glist(g, "legs")),
                                                  vx_parse_gear_shapes(glist(g, "arms")) })
        if has(go, "parts"):  // a mod's rules go first: they're more particular
            let rs = map(glist(go, "parts")) r: vx_rule { gstr(r, "part", ""), gstr(r, "tag", ""), gstr(r, "slot", ""), gstr(r, "gear", "") }
            for(vx_rules) r: rs.push(r)
            vx_rules = rs
        let names = scan_folder(d + "/bodies", false)
        if names:
            for(sorted_strs(names)) n:
                if ends_with(n, ".json"):
                    let id = substring(n, 0, n.length - 5)
                    let o = vx_based(d, parse_json(assert read_file(d + "/bodies/" + n)))
                    let b = vx_parse_body(id, o)
                    vx_bodies.set(id, b)
                    for(gstrs(o, "also")) a: vx_bodies.set(a, b)  // (other body ids drawn the same, their palettes apart)
        vx_load_sizes(parse_json(read_file(d + "/sizes.json") or "\{\}"))

// The size table (docs/rendering.md, size_check.lobster): every body's size and height, and how big a mount is under its rider.
def vx_load_sizes(o:JV):
    let bs = gobj(o, "bodies")
    for(bs.keys) id, k:
        let b = vx_body_of(id)
        b.size = gfloat(bs.a[k], "size", b.size)
        b.h = gfloat(bs.a[k], "h", 0.0)
        b.rides_as = gfloat(bs.a[k], "rides_as", 0.0)
        b.crew_k = gfloat(bs.a[k], "crew_k", 1.0)
        b.crew_seats = int(gfloat(bs.a[k], "crew_seats", 0.0))
        let dk = glist(bs.a[k], "deck")
        if dk.length == 2: b.deck = float2 { as_float(dk[0]), as_float(dk[1]) }
    let ms = gobj(o, "mounts")
    for(ms.keys) id, k: vx_body_of(id).ride = gfloat(ms.a[k], "ride", 0.0)

// A body built on another (its `base`, in the same folder): the base's fields, this one's over them, and its
// `add_shapes` after the base's shapes (a war boar: the boar, bigger, with a howdah and seats).
def vx_based(d:string, o:JV) -> JV:
    if not has(o, "base"): return o
    let b = vx_based(d, parse_json(assert read_file(d + "/bodies/" + gstr(o, "base", "") + ".json")))
    for(o.keys) k, i:
        if k != "base" and k != "add_shapes": set(b, k, o.a[i])
    let ss = glist(b, "shapes")
    for(glist(o, "add_shapes")) x: ss.push(x)
    set(b, "shapes", jarr(ss))
    if has(o, "remap"): vx_remap(b, at(o, "remap"))
    return b

// Every material named in a body (its shapes', its legs'), renamed by `remap` (an engine built on a creature: its
// skin is its crew's, so the creature's skin becomes a hide of its own).
def vx_remap(v:JV, remap:JV) -> void:
    if v.kind == J_ARR:
        for(v.a) x: vx_remap(x, remap)
    elif v.kind == J_OBJ:
        for(v.keys) k, i:
            let x = v.a[i]
            if (k == "mat" or k == "base_mat") and x.kind == J_STR and has(remap, x.s): v.a[i] = at(remap, x.s)
            elif k == "mats" and x.kind == J_ARR:
                for(x.a) m, n: if m.kind == J_STR and has(remap, m.s): x.a[n] = at(remap, m.s)
            elif k != "remap": vx_remap(x, remap)

// The data's text (every file read): part of the bake cache's key, so a change to the data bakes again.
def vx_data_text() -> string:
    var t = ""
    for(vx_data_dirs) d:
        t += (read_file(d + "/materials.json") or "") + (read_file(d + "/gear.json") or "") + (read_file(d + "/sizes.json") or "")
        let names = scan_folder(d + "/bodies", false)
        if names: for(sorted_strs(names)) n: t += read_file(d + "/bodies/" + n) or ""
        let models = scan_folder(d + "/models", false)  // (.vox: a changed model rebakes)
        if models: for(sorted_strs(models)) n: t += n + (read_file(d + "/models/" + n) or "")
    return t

def vx_body_of(id:string) -> vx_body_spec:
    let b = vx_bodies.get(id)
    assert b
    return b

// A culture's own body for a creature (#418): the family's `bodies` (creature -> voxel body, families.json), drawn
// wherever a unit has that creature's own body (not an engine, a role's body or a body part of its own). Only the
// look changes: the recipe, its stats and the race key are the creature's.
def vx_culture_body(body:string, creature:string, fam:JV) -> string:
    if body != creature: return body
    let own = gstr(gobj(fam, "bodies"), creature, "")
    if own == "": return body
    assert vx_bodies.get(own)
    return own

// The gear for a recipe's part in a slot (the rules' first match), or "".
def vx_gear_for(part_id:string, tags:[string], slot:string) -> string:
    for(vx_rules) r:
        let by_part = r.part != "" and (part_id == r.part or starts_with(part_id, r.part + "."))
        let by_tag = r.tag != "" and (find(tags) t: t == r.tag) >= 0
        let by_slot = r.part == "" and r.tag == "" and r.slot != "" and r.slot == slot
        if (by_part or by_tag or by_slot) and (r.slot == "" or r.slot == slot or by_slot): return r.gear
    return ""

// ---- units

class vx_unit_def:
    label:string
    body:string  // bodies/<id>.json
    skin:float3  // the race's colours (palettes.json; zero: the body's)
    pale:float3
    mark:float3
    gear:[string]  // gear.json's
    mount:string   // a mount's body, or ""
    fused:bool     // the rider grows out of its mount (a centaur): at the mount body's `fused` point
    coat:float3    // the mount's colours (zero: its body's)
    mane:float3
    coat_mark:float3
    crew:vx_unit_def?  // an engine's or a war beast's crew (each of its body's crew spots and seats)

var vx_variant = 0          // the look being built
var vx_seated = false       // a rider being built: no legs of its own (shapes with `unless: seated` left off)
var vx_team_wear = "scarf"  // where a creature without a tunic wears the team: scarf or vest (a concept option)
var vx_act = ""             // the pose being drawn: "" (standing or walking) or "attack", at a step through it
var vx_fall_t = 0.0         // how far through falling dead (0: not): the knees go, then the trunk
var vx_carried = ""         // a worker's load carried home (a resource's name): what's pushed takes both hands
var vx_stand = false        // standing (not walking): every foot planted where it rests (idle, a blow, at work)

def vx_looks_of(u:vx_unit_def) -> int: return vx_body_of(u.body).looks.length

// The materials for unit u in look v (its mount's coat too; an engine's frame in its style, its crew's own colours).
def vx_set_look(u:vx_unit_def, v:int) -> void:
    let c = u.crew
    if c:
        vx_set_look(c, v % vx_looks_of(c))
        vx_mat_cols[vx_mat("frame")] = u.skin
        vx_mat_cols[vx_mat("frame2")] = u.pale
        vx_mat_cols[vx_mat("trim")] = u.mark
        return
    let b = vx_body_of(u.body)
    vx_variant = v
    let skin = if u.skin != float3_0: u.skin else: b.skin
    vx_mat_cols[vx_mat("skin")] = vx_lifted(skin, b.skin_scale, b.looks[v])
    vx_mat_cols[vx_mat("pale")] = if u.pale != float3_0: u.pale else: b.pale
    vx_mat_cols[vx_mat("mark")] = if u.mark != float3_0: u.mark else: b.mark
    vx_mat_cols[vx_mat("hair")] = b.hair[v]
    vx_fur = b.fur
    if u.mount != "":
        let mb = vx_body_of(u.mount)
        vx_mat_cols[vx_mat("coat")] = if u.coat != float3_0: u.coat else: mb.skin
        vx_mat_cols[vx_mat("mane")] = if u.mane != float3_0: u.mane else: mb.pale
        vx_mat_cols[vx_mat("coat_mark")] = if u.coat_mark != float3_0: u.coat_mark else: mb.mark

// A skin in a look: a dark palette lifted by up to `lift` for the voxels' darker shading (a light one not at all: a
// light palette times 1.3 came out white, "looks unwell", Dominic, 2026-11-03), shaded by the look, and scaled whole
// (its hue and saturation kept) to stay under VX_SKIN_TOP. voxel_check checks every palette in every look.
let VX_SKIN_TOP = 0.92  // (the lit band, 1.08 of it, stays under white)
def vx_lifted(c:float3, lift:float, look:float) -> float3:
    let lum = c.x * 0.3 + c.y * 0.59 + c.z * 0.11
    let k = clamp(0.45 / max(lum, 0.01), 1.0, lift)
    let s = c * k * look
    let top = max(s.x, max(s.y, s.z))
    return if top > VX_SKIN_TOP: s * (VX_SKIN_TOP / top) else: s

// How far into its blow an attack is at t: a wind-up, a fast strike, a hold, back.
def vx_blow(t:float) -> float:
    return if t < 0.45: 0.0 elif t < 0.6: (t - 0.45) / 0.15 elif t < 0.75: 1.0 else: 1.0 - (t - 0.75) / 0.25

def vx_raise(t:float) -> float:  // raised through the wind-up, held, lowered
    return if t < 0.45: t / 0.45 elif t < 0.75: 1.0 else: 1.0 - (t - 0.75) / 0.25

// A gun's kick, at t through the firing cycle: the shot at 0, back in place by 0.4 (a frame held after that shows no kick).
def vx_kick(t:float) -> float: return max(0.0, 1.0 - t / 0.4)

// Is its right hand's gear a gun brought up to aim?
def vx_aiming(u:vx_unit_def) -> bool:
    let right = vx_held(u, 1)
    if not right: return false
    let h = vx_holds.get(right.hold)
    return h != nil and h.aims

// What a fighter draws between shots, its gun aimed or not (`moving`: it walks); a blank: as anyone.
def vx_between_shots(aims:bool, moving:bool) -> string: return if aims and not moving: "attack" else: ""

// Where a body is in a blow: drawn back through the wind-up (below 0), thrown forward at the hit (1).
def vx_strike(t:float) -> float: return vx_blow(t) - 0.4 * vx_raise(t) * (1.0 - vx_blow(t))

def vx_mix(a:float3, b:float3, k:float) -> float3: return a + (b - a) * k

// What this body takes home of resource res (its own rule, or everyone's; nil: nothing to see).
def vx_load_of(body:string, res:string):
    let own = vx_loads.get("{body} {res}")
    return own or vx_loads.get("* {res}")

// The gear a load is held by ("" when it's pushed or there's none).
def vx_load_gear(body:string, res:string) -> string:
    let l = vx_load_of(body, res)
    return if l: l.gear else: ""

// Points a shape can stand on: named, with where each is now.
class vx_points:
    names:[string]
    at:[float3]

def vx_where(p:vx_points, name:string) -> float3:
    let k = find(p.names) n: n == name
    assert k >= 0
    return p.at[k]

def vx_flagged(flags:[string], s:vx_spec) -> bool:
    for(s.need) f: if (find(flags) g: g == f) < 0: return false
    for(s.avoid) f: if (find(flags) g: g == f) >= 0: return false
    return true

// A shape's prims at the points, its offsets turned by the frame (along, out, side; the body's own: x, y, z unturned).
def vx_emit(out:[vx_prim], s:vx_spec, p:vx_points, fx:float3, fy:float3, fz:float3, flags:[string], body:vx_body_spec?):
    if not vx_flagged(flags, s): return
    for(if s.mirror: 2 else: 1) side:
        let m = if side == 1: float3 { -1.0, 1.0, 1.0 } else: float3_1
        let tr = fn(o:float3) -> float3: fx * (o.x * m.x) + fy * o.y + fz * o.z
        switch s.kind:
            case vx_k_cap: out.push(vx_prim { vx_where(p, s.pa) + tr(s.a), vx_where(p, s.pb) + tr(s.b), s.ra, s.rb, s.mat, s.hard, false, float3_0 })
            case vx_k_ball: out.push(vx_prim { vx_where(p, s.pa) + tr(s.a), vx_where(p, s.pa) + tr(s.a), s.ra, s.ra, s.mat, s.hard, false, float3_0 })
            case vx_k_disc:
                let c = vx_where(p, s.pa) + tr(s.a)
                out.push(vx_disc(c, normalize(tr(s.n)), s.ra, s.rb, s.mat))
            case vx_k_box:
                let c = vx_where(p, s.pa) + tr(s.a)
                out.push(vx_box(c, normalize(tr(s.n)), s.half, s.ra, s.mat))
            case vx_k_chain:
                var r = s.ra
                for(s.pts.length - 1) k:
                    let a = vx_where(p, s.pts[k]) + tr(s.offs[k])
                    let b = vx_where(p, s.pts[k + 1]) + tr(s.offs[k + 1])
                    out.push(vx_prim { a, b, r, r - s.taper, if k == 0: s.mat else: s.mat2, s.hard, false, float3_0 })
                    r = max(s.rb, r + s.step)
            case vx_k_ring:  // a scarf: a ring round a point, tipped down at the front, its knot hanging
                let c = vx_where(p, s.pa) + tr(s.a)
                var last = float3_0
                for(9) k:
                    let a = float(k) * 45.0
                    let q = c + float3 { sin(a) * s.ra, cos(a) * s.ra, -cos(a) * s.rb }
                    if k > 0: out.push(vx_hard(last, q, 0.9, 0.9, s.mat))
                    last = q
                out.push(vx_hard(c + float3 { 0.6, s.ra, -s.rb }, c + float3 { 1.0, s.ra + 0.6, -s.rb - 2.6 }, 0.9, 0.6, s.mat))
            case vx_k_helm:
                let b = body
                if b:
                    let c = vx_where(p, b.helm_pt) + b.helm
                    out.push(vx_hard(c, c + float3 { 0.0, -0.15, 0.15 }, b.helm_r + s.ra, b.helm_r + s.ra, s.mat))
            case vx_k_fit:
                let b = body
                if b: out.push(vx_hard(vx_where(p, b.fit_pa) + b.fit_a, vx_where(p, b.fit_pb) + b.fit_b, b.fit_r.x + s.ra, b.fit_r.y + s.ra, s.mat))
            case vx_k_model:
                if s.bone or s.ax != float3_0: out.push(vx_part_prim(s, p, fx * m.x, fy, fz))
                else:
                    let c = vx_where(p, s.pa) + tr(s.a)
                    var y = fy
                    if s.pb != "": y = normalize(vx_where(p, s.pb) + tr(s.b) - c)
                    if s.n != float3_0:  // (its side given: x that way, z = x cross y, so it can lie along the frame's first axis)
                        let sx = normalize(tr(s.n) - y * dot(tr(s.n), y))
                        out.push(vx_prim { c, c + y, s.ra, s.ra, s.mat, s.hard, false, float3_0, model: s.model, mx: sx, mz: cross(sx, y) })
                    else:
                        let x0 = fx * m.x * (if s.flip: -1.0 else: 1.0)
                        let x = normalize(x0 - y * dot(x0, y))
                        let z = cross(fx, y)  // (from the unmirrored x: a mirrored model keeps its up)
                        out.push(vx_prim { c, c + y, s.ra, s.ra, s.mat, s.hard, false, float3_0, model: s.model, mx: x, mz: normalize(z - y * dot(z, y)) })
            default: assert false

// A .vox body's part: on its point, its own axes turned by the frame; or a limb's, kept where it was drawn against its
// bone's middle and turned from the bone's drawn direction to where the bone is now. (Mirrored, its axes are: a left-handed set draws it flipped.)
def vx_part_prim(s:vx_spec, p:vx_points, fx:float3, fy:float3, fz:float3) -> vx_prim:
    def tr(o:float3) -> float3: return fx * o.x + fy * o.y + fz * o.z
    if not s.bone:
        let c = vx_where(p, s.pa) + tr(s.a)
        return vx_prim { c, c + tr(s.ay), s.ra, s.ra, s.mat, s.hard, false, float3_0, model: s.model, mx: tr(s.ax), mz: tr(s.az) }
    let a = vx_where(p, s.pa)
    let b = vx_where(p, s.pb)
    let d = normalize(b - a)
    def turn(v:float3) -> float3: return vx_turned_to(s.rest, d, v)
    let c = (a + b) * 0.5 + turn(s.a)
    return vx_prim { c, c + turn(s.ay), s.ra, s.ra, s.mat, s.hard, false, float3_0, model: s.model, mx: turn(s.ax), mz: turn(s.az) }

// v turned by the least turn that takes direction a to direction b.
def vx_turned_to(a:float3, b:float3, v:float3) -> float3:
    let ax = cross(a, b)
    let sn = magnitude(ax)
    let cs = dot(a, b)
    if sn < 0.000001:
        return if cs > 0.0: v else: float3 { -v.x, v.y, -v.z }  // (straight back up: half a turn round y)
    let k = ax / sn
    return v * cs + cross(k, v) * sn + k * dot(k, v) * (1.0 - cs)

let vx_X = float3 { 1.0, 0.0, 0.0 }
let vx_Y = float3 { 0.0, 1.0, 0.0 }
let vx_Z = float3 { 0.0, 0.0, 1.0 }

// The flags a unit's shapes check (if / unless): its gear's, its look, seated, how it wears the team.
def vx_flags_of(u:vx_unit_def) -> [string]:
    let f = [ "look:{vx_variant}", "wear:{vx_team_wear}" ]
    if vx_seated: f.push("seated")
    for(u.gear) g:
        let gs = vx_gears.get(g)
        assert gs
        f.push("has:" + g)
        for(gs.flags) x: f.push(x)
    return f

// Where a foot is at walk phase ph, and its pitch (degrees, toes up). A planted foot goes back at the ground's own
// speed (a sine would skate, #422); it swings forward on a sine, lifted. With a gait, its heel rises as it leaves, and
// the swing lifts it early, behind, so the knee bends.
def vx_foot(b:vx_body_spec, l:vx_leg_spec, side:float, ph:float) -> float3, float:
    let rest = l.foot * float3 { side, 1.0, 1.0 }
    let g = b.gait
    if vx_stand:
        if g and vx_act == "attack": return rest + float3 { 0.0, if side > 0.0: -g.back else: g.front, 0.0 }, 0.0
        return rest, 0.0
    let w = ph + l.phase
    let u = if side > 0.0: w else: w + 180.0
    var y, up, pitch = 0.0, 0.0, 0.0
    if cos(u) > 0.0:
        y = sin(u) * l.stride
        up = if g: cos(u) * (1.0 - 0.5 * sin(u)) * l.lift else: cos(u) * l.lift
        if g: pitch = -g.heel + (g.heel + g.toe) * (sin(u) + 1.0) * 0.5
    else:
        var a = u - 90.0
        while a < 0.0: a += 360.0
        while a >= 360.0: a -= 360.0
        let v = a / 180.0
        y = (1.0 - 2.0 * v) * l.stride
        if g: pitch = if v < 0.35: g.toe * (1.0 - v / 0.35) elif v > 0.65: -g.heel * (v - 0.65) / 0.35 else: 0.0
    return rest + float3 { 0.0, y, up + (if g: max(0.0, sin(-pitch)) * g.toes else: 0.0) }, pitch

// A body's points at walk phase ph (its bob), raised by lift.
// A body that would have to stretch a leg past its bones to reach its foot (a long stride on short legs) is lowered
// until every foot is in reach, with a little bend left (the hips dip at full stride, as a walker's do); else the
// leg stays straight and the foot drags short of where it should be.
def vx_body_points(b:vx_body_spec, ph:float, lift:float3) -> vx_points:
    let bob = abs(sin(ph * 2.0))
    let flap = sin(ph * 4.0)
    let wk = if b.gait and not vx_stand and not vx_seated: 1.0 else: 0.0                            // (leaning and shifting only walking)
    let shift = if b.gait and vx_stand and not vx_seated and vx_act == "": sin(ph * 2.0) else: 0.0  // (standing: its weight, slowly side to side)
    let p = vx_points { copy(b.pnames), map(b.pat) a, k: a + float3 { b.psway[k] * (shift - cos(ph) * wk), b.plean[k] * wk, b.pbob[k] * bob + b.pflap[k] * flap } + lift }
    if vx_seated: return p  // (a rider's legs are its seat's)
    var drop = 0.0
    for(b.legs) l:
        for([ 1.0, -1.0 ]) side:
            let m = float3 { side, 1.0, 1.0 }
            let hip = vx_where(p, l.pa) + l.a * m
            let foot = vx_foot(b, l, side, ph)
            let d = hip - foot
            let reach = (l.l1 + l.l2) * (if vx_stand: 0.995 else: 0.97)  // (standing, a leg may be straight)
            let across = d.x * d.x + d.y * d.y
            if across < reach * reach and d.z > 0.0: drop = max(drop, d.z - sqrt(reach * reach - across))
    if drop > 0.0: p.at = map(p.at) a: a - float3 { 0.0, 0.0, drop }
    return p

// The legs, walking at ph: each foot planted where it rests, moved along by sin(ph + its phase) * stride, lifted as
// it swings forward; the knee (or a front leg's elbow) bent towards the pole.
def vx_legs(out:[vx_prim], u:vx_unit_def, b:vx_body_spec, p:vx_points, ph:float, flags:[string]):
    for(b.legs) l:
        for([ 1.0, -1.0 ]) side:
            let m = float3 { side, 1.0, 1.0 }
            let hip = vx_where(p, l.pa) + l.a * m
            let foot, pitch = vx_foot(b, l, side, ph)
            let fy = float3 { 0.0, cos(pitch), sin(pitch) }  // (the foot's shapes, rolled with it)
            let fz = float3 { 0.0, -sin(pitch), cos(pitch) }
            let knee, ankle = vx_ik(hip, foot, l.l1, l.l2, l.pole * m)
            let first = l == b.legs[0]
            if not first or (find(b.vox_bones) n: n == "thigh") < 0: out.push(vx_cap(hip, knee, l.r[0], l.r[1], l.mats[0]))
            if not first or (find(b.vox_bones) n: n == "shin") < 0: out.push(vx_cap(knee, ankle, l.r[2], l.r[3], l.mats[1]))
            let lp = vx_points { [ "hip", "knee", "ankle" ], [ hip, knee, ankle ] }
            if first: for(if side > 0.0: b.leg_r else: b.leg_l) s: vx_emit(out, s, lp, vx_X, fy, fz, flags, nil)  // (a .vox's limbs: the first pair)
            for(l.shapes) s:
                let s2 = s  // (the left one mirrored: its offsets' x turned)
                if side > 0.0: vx_emit(out, s2, lp, vx_X, fy, fz, flags, nil)
                else: vx_emit(out, vx_mirrored(s2), lp, vx_X, fy, fz, flags, nil)
            vx_limb_gear(out, u, true, side, lp, fy, fz, flags)

// Worn gear's shapes on a leg or an arm at its points lp (in the frame x, fy, fz), the left side's mirrored.
def vx_limb_gear(out:[vx_prim], u:vx_unit_def, leg:bool, side:float, lp:vx_points, fy:float3, fz:float3, flags:[string]):
    for(u.gear) g:
        let gs = vx_gears.get(g)
        if gs and gs.hand == 0:
            for(if leg: gs.legs else: gs.arms) s:
                if side > 0.0: vx_emit(out, s, lp, vx_X, fy, fz, flags, nil)
                else: vx_emit(out, vx_mirrored(s), lp, vx_X, fy, fz, flags, nil)

def vx_mirrored(s:vx_spec) -> vx_spec:
    let m = float3 { -1.0, 1.0, 1.0 }
    return vx_spec { s.kind, s.hard, false, s.pa, s.a * m, s.pb, s.b * m, s.ra, s.rb, s.mat, s.mat2, s.n * m, s.half,
                     s.pts, map(s.offs) o: o * m, s.step, s.taper, s.need, s.avoid, model: s.model, flip: not s.flip,
                     ax: s.ax * m, ay: s.ay * m, az: s.az * m, bone: s.bone, rest: s.rest * m }

def vx_worn_gear(g:string) -> bool:
    let gs = vx_gears.get(g)
    return gs and gs.hand == 0

def vx_held(u:vx_unit_def, hand:int) -> vx_gear_spec?:
    for(u.gear) g:
        let gs = vx_gears.get(g)
        if gs and gs.hand == hand: return gs
    return nil

// The arms and what's in the hands, posed by the holds and the act. L: an arm bone's length (the reach is 2L).
def vx_arms(out:[vx_prim], u:vx_unit_def, b:vx_body_spec, p:vx_points, swing:float, t:float, flags:[string]):
    let L = b.arm * 2.0
    let k = vx_blow(t)
    let up = vx_raise(t)
    let attack = vx_act == "attack"
    let g = b.gait
    // with a gait the shoulders turn against the walk (the right one back as the right foot goes forward), and into a blow
    let aiming = attack and vx_aiming(u)
    let turned = if not g: 0.0 elif aiming: -g.turn * 0.25 * vx_kick(t) elif attack: g.turn * vx_strike(t) else: -g.twist * swing
    let sh_r = vx_where(p, b.sh_pt) + b.sh + float3 { 0.0, turned, 0.0 }
    let sh_l = vx_where(p, b.sh_pt) + b.sh * float3 { -1.0, 1.0, 1.0 } - float3 { 0.0, turned, 0.0 }
    let hang = vx_holds.get("hang")
    assert hang
    // hanging, swung (with a gait, against the leg on its side, the elbow bending as it comes forward)
    let fore = if g: -swing * g.arm else: swing * hang.swing
    let raised = if g: max(0.0, fore) * 0.4 else: 0.0
    let lowered = if g: max(0.0, -fore) * 0.3 else: 0.0
    var hr = sh_r + (hang.rest + float3 { 0.0, fore, raised }) * L
    var dr = hang.dir
    var hl = sh_l + (hang.rest * float3 { -1.0, 1.0, 1.0 } + float3 { 0.0, -fore, lowered }) * L
    let carry = if g: float3 { 0.0, -swing * g.held, 0.0 } * L else: float3_0  // a busy hand moves a little too
    var drawn = false
    let right = vx_held(u, 1)
    let left = vx_held(u, -1)
    if right:
        let h = vx_holds.get(right.hold)
        assert h
        hr = sh_r + h.rest * L + carry
        dr = if right.dir != float3_0: right.dir else: h.dir
        if attack and h.act:
            hr = vx_mix(vx_mix(hr, sh_r + h.wind * L, up), sh_r + h.hit * L, k)
            dr = vx_mix(vx_mix(dr, h.wind_dir, up), h.hit_dir, k)
        if aiming:
            let aim_d = normalize(h.aim_dir)
            hr = sh_r + (h.aim - aim_d * h.kick * vx_kick(t)) * L
            dr = h.aim_dir
        if h.support > 0.0: hl = hr + normalize(dr) * h.support + float3 { -0.4, 0.0, 0.0 }
    if left:
        let h = vx_holds.get(left.hold)
        assert h
        hl = sh_l + h.rest * L - carry
        if attack and h.picks and not right:
            hr = vx_mix(vx_mix(hr, sh_r + h.pick * L, up), sh_l + h.drop * L, k)
        if attack and h.draws:
            hl = vx_mix(hl, sh_l + h.raise * L, up)
            hr = vx_mix(hr, sh_r + h.draw * L, up * (1.0 - k))
            drawn = up * (1.0 - k) > 0.5
    let load = if vx_carried != "": vx_load_of(b.id, vx_carried) else: nil
    let pushed = if load: load.push else: ""
    if pushed != "":  // both hands low and forward on the handles
        hr = sh_r + float3 { 0.1, 0.55, -0.62 } * L
        hl = sh_l + float3 { -0.1, 0.55, -0.62 } * L
    for([ 1.0, -1.0 ]) side:
        let sh = if side > 0.0: sh_r else: sh_l
        let target = if side > 0.0: hr else: hl
        let elbow, hand = vx_ik(sh, target, b.arm, b.arm, float3 { side * 0.5, -1.0, -0.4 })
        if (find(b.vox_bones) n: n == "upper_arm") < 0: out.push(vx_cap(sh, elbow, b.thick, b.thick * 0.8, b.sleeve))
        if (find(b.vox_bones) n: n == "forearm") < 0:
            out.push(vx_cap(elbow, hand, b.thick * 0.75, b.thick * 0.6, b.hand))
            out.push(vx_ball(hand, b.thick * 0.8, b.hand))
        let ap = vx_points { [ "shoulder", "elbow", "hand" ], [ sh, elbow, hand ] }
        for(if side > 0.0: b.arm_r else: b.arm_l) s: vx_emit(out, s, ap, vx_X, vx_Y, vx_Z, flags, nil)
        vx_limb_gear(out, u, false, side, ap, vx_Y, vx_Z, flags)
        if side > 0.0: hr = hand
        else: hl = hand
    if pushed != "":
        vx_pushed(out, hr, hl, b.arm, pushed == "cart", if load: load.heap else: 0)
        return
    if right:  // its frame: along the held direction, out of its front, to the right
        let d = normalize(dr)
        let o = cross(vx_X, d)
        let gp = vx_points { [ "hand", "draw" ], [ hr, hr ] }
        let f = copy(flags)
        if attack and k > 0.35: f.push("firing")  // (the blow's moment: a beam, a muzzle's flash)
        for(right.shapes) s: vx_emit(out, s, gp, d, o, vx_X, f, nil)
    if left:  // up, out of its face, to the side
        let o = left.face
        let sd = normalize(cross(o, vx_Z))
        let gp = vx_points { [ "hand", "draw" ], [ hl, if drawn: hr else: hl - o * 0.4 ] }
        for(left.shapes) s: vx_emit(out, s, gp, vx_Z, o, sd, flags, nil)

// A barrow pushed by hands hr and hl (the ground at z 0), sized to the arm (a bone of length a): the handles
// from the hands down to a tub, a wheel in front on the ground, or a cart's wider tub with one each side; a heap on it.
def vx_pushed(out:[vx_prim], hr:float3, hl:float3, arm:float, cart:bool, heap:int):
    let a = max(arm, 5.0)  // (a small body's barrow still holds something)
    let wood = vx_mat("wood")
    let mid = (hr + hl) * 0.5
    let r = a * (if cart: 0.36 else: 0.32)
    let wide = if cart: r * 0.7 else: 0.0
    let y = mid.y + a * 1.15
    let z = max(r + a * 0.25, mid.z * 0.5)
    let wr = max(1.0, a * 0.24)
    out.push(vx_cap(hr, float3 { mid.x + wide + r * 0.5, y - a * 0.6, z }, 0.35, 0.35, wood))
    out.push(vx_cap(hl, float3 { mid.x - wide - r * 0.5, y - a * 0.6, z }, 0.35, 0.35, wood))
    for(if cart: [ -1.0, 1.0 ] else: [ 0.0 ]) sd:  // a tub along the way it goes (a cart's is two side by side)
        let x = mid.x + sd * wide
        out.push(vx_cap(float3 { x, y - a * 0.6, z }, float3 { x, y + a * 0.6, z }, r, r * 0.85, wood))
    let wheels = if cart: [ float3 { mid.x - wide - r - 0.5, y, wr }, float3 { mid.x + wide + r + 0.5, y, wr } ] else: [ float3 { mid.x, y + a * 0.6 + r * 0.5, wr } ]
    for(wheels) w:
        if not cart: out.push(vx_cap(float3 { mid.x, y + a * 0.5, z - r * 0.5 }, w, 0.3, 0.3, wood))
        out.push(vx_disc(w, float3 { 1.0, 0.0, 0.0 }, wr, 0.6, wood))
        out.push(vx_ball(w, 0.4, vx_mat("metal")))
    for([ float3 { -0.5, -0.4, 0.0 }, float3 { 0.5, 0.0, 0.0 }, float3 { -0.2, 0.45, 0.1 }, float3 { 0.1, -0.05, 0.5 } ]) o:  // (a heap above the rim)
        out.push(vx_ball(float3 { mid.x + o.x * (wide + r * 0.4), y + o.y * a, z + r * 0.7 + o.z * r }, r * 0.5, heap))

// What a body with no hands holds, in its harness: the right item along the harness's direction (lowered into a thrust
// in a blow), the left on its side.
def vx_harness(out:[vx_prim], u:vx_unit_def, b:vx_body_spec, p:vx_points, t:float, flags:[string]):
    let right = vx_held(u, 1)
    let left = vx_held(u, -1)
    if right:
        let k = if vx_act == "attack": vx_blow(t) else: 0.0
        let d = normalize(vx_mix(b.hr_dir, float3 { 0.0, 1.0, 0.1 }, k))
        let hr = vx_where(p, b.hr_pt) + b.hr + float3 { 0.0, 3.0 * k, 0.0 }
        let gp = vx_points { [ "hand", "draw" ], [ hr, hr ] }
        for(right.shapes) s: vx_emit(out, s, gp, d, cross(vx_X, d), vx_X, flags, nil)
    if left:
        let hl = vx_where(p, b.hl_pt) + b.hl
        let o = normalize(float3 { -1.0, 0.25, 0.0 })  // (out to the side)
        let gp = vx_points { [ "hand", "draw" ], [ hl, hl - o * 0.4 ] }
        for(left.shapes) s: vx_emit(out, s, gp, vx_Z, o, normalize(cross(o, vx_Z)), flags, nil)

// Is this unit's free hand picking (a basket on the other arm)?
def vx_picking(u:vx_unit_def) -> bool:
    let left = vx_held(u, -1)
    if not left or vx_held(u, 1): return false
    let h = vx_holds.get(left.hold)
    return h and h.picks

// Worn gear on a body (its fit for the body, or for any).
def vx_worn(out:[vx_prim], u:vx_unit_def, b:vx_body_spec, p:vx_points, flags:[string]):
    for(u.gear) g:
        let gs = vx_gears.get(g)
        assert gs
        if gs.hand == 0:
            var k = find(gs.fit_ids) i: i == b.id
            if k < 0: k = find(gs.fit_ids) i: i == "*"
            if k >= 0: for(gs.fits[k]) s: vx_emit(out, s, p, vx_X, vx_Y, vx_Z, flags, b)

// A body going down as it dies: its hips drop and its trunk folds forward over them, so its knees bend (its feet stay), #263.
let vx_SLUMP_HIPS = 0.6
let vx_SLUMP_LEAN = 0.6
let vx_SLUMP_FOLD = 0.3
def vx_slump(b:vx_body_spec, p:vx_points):
    let k = clamp(vx_fall_t / 0.6, 0.0, 1.0)
    let e = k * k * (3.0 - 2.0 * k)
    let hip = vx_where(p, b.legs[0].pa)
    p.at = map(p.at) a:
        let up = max(0.0, a.z - hip.z)
        a + float3 { 0.0, up * vx_SLUMP_LEAN * e, -hip.z * vx_SLUMP_HIPS * e - up * vx_SLUMP_FOLD * e }

// A body with its worn gear and arms (when it has them) at points p.
def vx_whole_body(out:[vx_prim], u:vx_unit_def, b:vx_body_spec, p:vx_points, ph:float, t:float, flags:[string]):
    if vx_fall_t > 0.0 and b.arms and b.legs.length and not vx_seated: vx_slump(b, p)
    let g = b.gait
    if g and vx_act == "attack":  // the body behind the blow (or leaning in to pick)
        let picks = vx_picking(u)
        let s = if picks: vx_raise(t) - vx_blow(t) elif vx_aiming(u): -0.25 * vx_kick(t) else: vx_strike(t)
        p.at = map(p.at) a, k: a + float3 { 0.0, b.pdrive[k] * s, -g.dip * max(0.0, s) }
    if not vx_seated: vx_legs(out, u, b, p, ph, flags)
    for(b.shapes) s: vx_emit(out, s, p, vx_X, vx_Y, vx_Z, flags, b)
    let track = b.track
    if track: vx_track_prims(out, track, ph)
    vx_wheel_prims(out, b.wheels, ph)
    vx_worn(out, u, b, p, flags)
    if b.arms: vx_arms(out, u, b, p, if vx_seated or vx_stand: 0.0 else: sin(ph), t, flags)
    elif b.harness: vx_harness(out, u, b, p, t, flags)

// A whole unit's parts, walking at phase ph0 (degrees) or, when acting, at ph0 / 360 through the act.
def vx_unit_prims(u:vx_unit_def, ph0:float) -> [vx_prim]:
    let out = vx_rider_prims(u, ph0)
    let c = u.crew
    if c: vx_crew_prims(out, u, c, ph0)
    return out

// An engine's or a war beast's crew: one on each crew spot (standing, walking with it, at work when it acts) and seat
// (sat in its howdah), each at its own size.
def vx_crew_prims(out:[vx_prim], u:vx_unit_def, c:vx_unit_def, ph0:float):
    let b = vx_body_of(u.body)
    let cb = vx_body_of(c.body)
    let ms = cb.size / b.size
    let ph = if vx_act == "": ph0 else: 0.0
    let t = ph0 / 360.0
    let ps = []::vx_prim
    for(b.crew) at:
        vx_whole_body(ps, c, cb, vx_body_points(cb, ph, float3_0), ph, t, vx_flags_of(c))
        for(ps) q: out.push(vx_prim { q.a * ms + at, q.b * ms + at, q.ra * ms, q.rb * ms, q.mat, q.hard, q.disc, q.box * ms, model: q.model, mx: q.mx, mz: q.mz })
        while ps.length: ps.pop()
    vx_seated = true
    let sat = ms * cb.crew_k
    let seats = if cb.crew_seats == 1 and b.seats.length > 1: [ fold(b.seats, float3_0) s, x: s + x / float(b.seats.length) ] else: b.seats
    for(seats) at:
        vx_whole_body(ps, c, cb, vx_body_points(cb, 0.0, float3 { 0.0, 0.0, -cb.seat_z }), 0.0, t, vx_flags_of(c))
        for(ps) q: out.push(vx_prim { q.a * sat + at, q.b * sat + at, q.ra * sat, q.rb * sat, q.mat, q.hard, q.disc, q.box * sat, model: q.model, mx: q.mx, mz: q.mz })
        while ps.length: ps.pop()
    vx_seated = false

// A mount's size under this rider: the table's, in proportion to the rider, so a rat on a beetle looks as a human on one does.
def vx_mount_size(b:vx_body_spec, mb:vx_body_spec) -> float:
    let human = vx_bodies.get("human")
    if mb.ride > 0.0 and b.h > 0.0 and human and human.h > 0.0: return mb.ride * (if b.rides_as > 0.0: b.rides_as else: b.h) / human.h
    return mb.size

// A unit and its mount (without a crew).
def vx_rider_prims(u:vx_unit_def, ph0:float) -> [vx_prim]:
    let out = []::vx_prim
    let ph = if vx_act == "": ph0 else: 0.0
    let t = ph0 / 360.0
    let b = vx_body_of(u.body)
    if u.mount == "":
        vx_whole_body(out, u, b, vx_body_points(b, ph, float3_0), ph, t, vx_flags_of(u))
        return out
    // a rider: the mount walks (in its own colours, at its own size), the rider sits astride, legs down its sides;
    // on a fused mount (a centaur) the rider's body grows out of it
    let mb = vx_body_of(u.mount)
    let mount = []::vx_prim
    let mu = vx_unit_def { u.label, u.mount, float3_0, float3_0, float3_0, [], "", false, float3_0, float3_0, float3_0, nil }
    let fused = u.fused
    assert not fused or mb.fused_pt != ""
    let mp = vx_body_points(mb, ph, float3_0)
    vx_whole_body(mount, mu, mb, mp, ph, t, if fused: [ "fused" ] else: [])
    let ms = vx_mount_size(b, mb) / b.size
    let skin = vx_mat("skin")
    let pale = vx_mat("pale")
    let mark = vx_mat("mark")
    for(mount) q:  // (the mount's own colours: its skin is the coat)
        let m = if q.mat == skin: vx_mat("coat") elif q.mat == pale: vx_mat("mane") elif q.mat == mark: vx_mat("coat_mark") else: q.mat
        out.push(vx_prim { q.a * ms, q.b * ms, q.ra * ms, q.rb * ms, m, q.hard, q.disc, q.box * ms, model: q.model, mx: q.mx, mz: q.mz })
    vx_seated = true
    let flags = vx_flags_of(u)
    if fused:
        let hip = (vx_where(mp, mb.fused_pt) + mb.fused) * ms
        vx_whole_body(out, u, b, vx_body_points(b, 0.0, hip - float3 { 0.0, 0.0, b.seat_z }), 0.0, t, flags)
        vx_seated = false
        return out
    let seat = mb.seat * ms
    vx_whole_body(out, u, b, vx_body_points(b, 0.0, seat - float3 { 0.0, 0.0, b.seat_z }), 0.0, t, flags)
    vx_seated = false
    let wide = mb.wide * ms
    for([ -1.0, 1.0 ]) side:
        let hip = seat + float3 { side * 2.0, 0.0, 0.6 }
        let knee = seat + float3 { side * wide, 3.4, -3.6 }
        let ankle = knee + float3 { 0.0, -0.8, -5.0 }
        out.push(vx_cap(hip, knee, 2.0, 1.7, b.astride[0]))
        out.push(vx_cap(knee, ankle, 1.4, 1.1, b.astride[1]))
        out.push(vx_cap(ankle, ankle + float3 { 0.0, 2.0, -0.4 }, 1.1, 1.0, b.astride[2]))
    return out

// A unit falling dead, at t (0 standing .. 1 lying): every part turned onto its right side about the body's long
// axis through its middle (vx_fill sets its lowest point back on the ground), toppling slowly then fast. It stops
// short of flat (84 degrees): a box facing sideways would turn straight up, where it has no across.
let vx_FALL = 84.0
def vx_fallen(parts:[vx_prim], t:float) -> [vx_prim]:
    var lo = 1000.0
    var hi = -1000.0
    for(parts) p:
        if not p.hard:
            let a, b = vx_bounds(p)
            lo = min(lo, a.z)
            hi = max(hi, b.z)
    let mid = (lo + hi) * 0.5
    let a = vx_FALL * t * t
    let c = cos(a)
    let s = sin(a)
    def turn(q:float3) -> float3: return float3 { q.x * c + (q.z - mid) * s, q.y, -q.x * s + (q.z - mid) * c + mid }
    return map(parts) p: vx_prim { turn(p.a), turn(p.b), p.ra, p.rb, p.mat, p.hard, p.disc, p.box, model: p.model, mx: turn(p.a + p.mx) - turn(p.a), mz: turn(p.a + p.mz) - turn(p.a) }

// A flier shot down (a body's "death": "crash", #260), at t (0 flying .. 1 on the ground): burning, nose down, it comes down in one
// piece and lands level. Only its pitch and height change, so its wings stay wings.
let vx_CRASH_PITCH = 28.0
def vx_crashed(parts:[vx_prim], t:float) -> [vx_prim]:
    var low = 1000.0
    for(parts) p: low = min(low, vx_lowest(p))
    let a = vx_CRASH_PITCH * sin(180.0 * t) * t
    let c, s = cos(a), sin(a)
    let drop = low * t * t
    def turn(q:float3) -> float3:
        let z = q.z - low
        return float3 { q.x, q.y * c + z * s, z * c - q.y * s + low - drop }
    return map(parts) p: vx_prim { turn(p.a), turn(p.b), p.ra, p.rb, vx_burnt_mat(p.mat), p.hard, p.disc, p.box, model: p.model, mx: turn(p.a + p.mx) - turn(p.a), mz: turn(p.a + p.mz) - turn(p.a) }

// A unit dying, at t (0 alive .. 1 lying): what its body's `death` says, else it falls over.
def vx_dying(u:vx_unit_def, parts:[vx_prim], t:float) -> [vx_prim]:
    let b = vx_body_of(u.body)
    return if b.death == "knocked_out": vx_knocked_out(u, b) elif b.death == "crash": vx_crashed(parts, t) else: vx_fallen(parts, t)

// A unit's parts, falling dead at t.
def vx_fallen_unit(u:vx_unit_def, t:float) -> [vx_prim]:
    vx_fall_t = t
    let parts = vx_unit_prims(u, 0.0)
    vx_fall_t = 0.0
    return vx_fallen(parts, t)

// Does the unit fly (its body's, or its mount's)? Its ground isn't under its lowest point.
def vx_flies(u:vx_unit_def) -> bool: return vx_body_of(u.body).flies > 0.0 or (u.mount != "" and vx_body_of(u.mount).flies > 0.0)

// Is the unit's ground its body's z 0 (a flier's: not under its lowest point; an engine's or a war beast's: under its
// wheels and feet, not its crew's)? A fall lies on the ground (not a flier's).
// What a material is on a wreck: scorched; team colour burns off to rust, so a wreck is nobody's.
def vx_burnt_mat(m:int) -> int: return if m == vx_mat_team: vx_mat("wreck_rust") else: vx_burnt_of[m]

// A vehicle knocked out (a body's "death": "knocked_out", #186): it stays where it stood, burnt, its parts knocked askew.
def vx_knocked_out(u:vx_unit_def, b:vx_body_spec) -> [vx_prim]:
    let out = []::vx_prim
    def burn(p:vx_prim) -> vx_prim: return vx_prim { p.a, p.b, p.ra, p.rb, vx_burnt_mat(p.mat), p.hard, p.disc, p.box, model: p.model, mx: p.mx, mz: p.mz }
    def body_of(id:string) -> vx_unit_def: return vx_unit_def { u.label, id, u.skin, u.pale, u.mark, [], "", false, u.coat, u.mane, u.coat_mark, nil }
    for(vx_unit_prims(body_of(if b.hull != "": b.hull else: b.id), 0.0)) p: out.push(burn(p))
    for(b.parts) part, k:
        let yaw = 24.0 + 13.0 * float(k)
        def turned(v:float3) -> float3:
            return float3 { v.x * cos(yaw) - v.y * sin(yaw) + part.pivot.x, v.x * sin(yaw) + v.y * cos(yaw) + part.pivot.y, v.z - 0.6 }
        for(vx_unit_prims(body_of(part.body), 0.0)) p:
            let q = burn(p)
            out.push(vx_prim { turned(q.a), turned(q.b), q.ra, q.rb, q.mat, q.hard, q.disc, q.box, model: q.model, mx: turned(q.a + q.mx) - turned(q.a), mz: turned(q.a + q.mz) - turned(q.a) })
    return out

def vx_on_zero(u:vx_unit_def, falling:bool) -> bool: return (vx_flies(u) and (not falling or vx_body_of(u.body).death == "crash")) or u.crew != nil or vx_body_of(u.body).piece

// The unit's size: its body's (a mount is scaled to it).
def vx_size_of(u:vx_unit_def) -> float: return vx_body_of(u.body).size

// How far a unit goes along the ground in one walk cycle, milli-tiles (its 8 walk steps go by the ground covered, #422):
// a belt's link; else four strides of the legs that walk (its mount's, at the size it's ridden): a planted foot goes back
// two strides a half cycle. A body unit is about 1/62 of a tile along the ground at size 1 (1.1 world px).
def vx_walk_cycle(u:vx_unit_def) -> float:
    let b = vx_body_of(u.body)
    let pitch = vx_track_cycle(b)  // (a belt goes by its links, so it doesn't slide on the ground)
    if pitch > 0.0: return pitch * b.size * 1000.0 / 62.0
    let w = if u.mount != "": vx_body_of(u.mount) else: b
    let size = if u.mount != "": vx_mount_size(b, w) else: b.size
    if not w.legs.length: return 4.0 * w.reach * 1000.0 / 62.0  // (a flier's wings, a cart's wheels: their own beat)
    return 4.0 * w.legs[0].stride * size * 1000.0 / 62.0

// ---- the voxel grid

class vx_shape:  // a filled grid's surface: the voxels with air beside them (none of the rest can show)
    pos:[int3]   // voxels from the unit's ground point
    mats:[int]
    normals:[float3]  // the shape's smooth normal (the grid's stairs would speckle the shading)
    occl:[float]      // how hemmed in (0 open to 1 deep in a crease): ambient occlusion
    lo:int3           // the grid (for shadows): its corner, size, and per voxel a material or -1
    dims:int3
    grid:[int]

def vx_scaled(p:vx_prim, s:float, lift:float) -> vx_prim:
    let up = float3 { 0.0, 0.0, lift }
    return vx_prim { (p.a + up) * s, (p.b + up) * s, p.ra * s, p.rb * s, p.mat, p.hard, p.disc, p.box * s, model: p.model, mx: p.mx, mz: p.mz }

def vx_bounds(p:vx_prim) -> float3, float3:
    if p.model >= 0:
        let e = vx_model_reach(p)
        return p.a - e, p.a + e
    let r = max(p.ra, p.rb) + (if p.disc: p.ra else: 0.0) + magnitude(p.box)
    return min(p.a, p.b) - float3_1 * r, max(p.a, p.b) + float3_1 * r

// The shape's distance at p from the parts in `near`, and the material of the part nearest it. (Capsules, most of
// the parts, measured inline: this is the bake's hot loop.)
def vx_field(ps:[vx_prim], near:[int], p:float3, k:float) -> float, int:
    var body = 1000.0
    var gear = 1000.0
    var best = 1000.0
    var m = -1
    for(near) i:
        let s = ps[i]
        var d = 0.0
        var sm = s.mat
        if s.model >= 0:
            d = vx_model_sd(p, s)
            sm = vx_model_mat_at(p, s)
        elif s.disc or s.box.x > 0.0: d = vx_dist(p, s)
        else:
            let ba = s.b - s.a
            let pa = p - s.a
            let l2 = dot(ba, ba)
            let h = if l2 > 0.0: clamp(dot(pa, ba) / l2, 0.0, 1.0) else: 0.0
            d = magnitude(pa - ba * h) - (s.ra + (s.rb - s.ra) * h)
        if s.hard: gear = min(gear, if s.model >= 0: d + 0.5 else: d)  // (a model is drawn as it is: not thickened)
        else:
            let e = max(k - abs(body - d), 0.0) / k
            body = min(body, d) - e * e * k * 0.25
        if d < best:
            best = d
            m = sm
    return min(body, gear - 0.5), m  // (gear thickened half a voxel: a shaft thinner than a voxel would break up)

let vx_AO_TAPS = [ int3 { 2, 0, 0 }, int3 { -2, 0, 0 }, int3 { 0, 2, 0 }, int3 { 0, -2, 0 }, int3 { 0, 0, 2 }, int3 { 0, 0, -2 },
                   int3 { 2, 2, 2 }, int3 { -2, 2, 2 }, int3 { 2, -2, 2 }, int3 { -2, -2, 2 },
                   int3 { 2, 2, -2 }, int3 { -2, 2, -2 }, int3 { 2, -2, -2 }, int3 { -2, -2, -2 } ]

def vx_solid_at(grid:[int], lo:int3, dims:int3, v:int3) -> bool:
    let q = v - lo
    if q.z < 0: return true  // (the ground)
    if q.x < 0 or q.y < 0 or q.x >= dims.x or q.y >= dims.y or q.z >= dims.z: return false
    return grid[(q.z * dims.y + q.y) * dims.x + q.x] >= 0

// The parts filled into a grid at a voxel a baked pixel (the unit's size scaled in). The grid is cut in blocks of 4
// voxels; each part is listed in the blocks its bounds touch, so a voxel only measures the parts near it. A block
// is tested at its centre first: clearly outside is skipped, clearly inside filled whole (none of it shows);
// only blocks the surface crosses are measured voxel by voxel. The blocks are filled a slice at a time
// (vx_fill_more), so a bake in play can spread one over frames.
class vx_filling:
    ps:[vx_prim]
    k:float
    lo:int3
    nb:int3
    dims:int3
    blocks:[[int]]
    mats:[int]
    field:[float]  // the distance where it was measured (air elsewhere, -1 deep inside), for normals
    next:int       // the next block to fill

// How low a shape really goes (vx_bounds is generous, for finding what's near).
def vx_lowest(p:vx_prim) -> float:
    if p.model >= 0: return p.a.z - vx_model_reach(p).z
    if p.box.x > 0.0 or p.disc:
        let n = normalize(p.b - p.a)
        let flat = sqrt(max(0.0, 1.0 - n.z * n.z))
        if p.disc: return p.a.z - p.ra * flat - abs(n.z) * p.rb
        return p.a.z - abs(n.z) * p.box.y - flat * p.box.z - p.ra
    return min(p.a.z - p.ra, p.b.z - p.rb)

def vx_fill_begin(parts:[vx_prim], unit_size:float, flies:bool) -> vx_filling:
    let s = unit_size * vx_RES
    var low = if flies: 0.0 else: 1000.0  // (a flier's ground is the builder's z 0, not under its lowest point)  // the ground: under the body's lowest point (gear reaching lower, a spear's butt, is cut off
    for(parts) p:                         // by it: a frog's spear set it on the ground and lifted the frog off it)
        if not p.hard and not flies:
            let a = vx_bounds(p)  // (its low corner; the high one isn't needed)
            low = min(low, a.z)
    if low == 1000.0:  // (nothing soft: the ground goes under what there is)
        for(parts) p: low = min(low, vx_lowest(p))
    let ps = map(parts) p: vx_scaled(p, s, -low)
    let k = vx_BLEND * s
    var a = float3_1 * 1000.0
    var b = float3_1 * -1000.0
    for(ps) p:
        let pa, pb = vx_bounds(p)
        a = min(a, pa)
        b = max(b, pb)
    let lo = int3 { int(floor(a.x)) - 2, int(floor(a.y)) - 2, 0 }
    let nb = (int3 { int(-floor(-b.x)) + 2, int(-floor(-b.y)) + 2, int(-floor(-b.z)) + 2 } - lo + int3_1 * 3) / 4
    let dims = nb * 4
    let blocks = map(nb.x * nb.y * nb.z): []::int
    let margin = k + 4.0
    for(ps) p, i:
        let pa, pb = vx_bounds(p)
        let qa = max(int3_0, (int3 { int(floor(pa.x - margin)), int(floor(pa.y - margin)), int(floor(pa.z - margin)) } - lo) / 4)
        let qb = min(nb - int3_1, (int3 { int(floor(pb.x + margin)), int(floor(pb.y + margin)), int(floor(pb.z + margin)) } - lo) / 4)
        for(qb.z - qa.z + 1) z: for(qb.y - qa.y + 1) y: for(qb.x - qa.x + 1) x:
            blocks[((qa.z + z) * nb.y + qa.y + y) * nb.x + qa.x + x].push(i)
    let n = dims.x * dims.y * dims.z
    return vx_filling { ps, k, lo, nb, dims, blocks, map(n): -1, map(n): 1.0, 0 }

// Fills blocks until the clock passes `until` (seconds_elapsed): true when they're all filled.
def vx_fill_more(fl:vx_filling, until:float) -> bool:
    let ps = fl.ps
    let k = fl.k
    let nb = fl.nb
    let dims = fl.dims
    let mats = fl.mats
    let field = fl.field
    let base = float(fl.lo) + float3_1 * 0.5
    let reach = 3.5  // a block's half diagonal, voxels
    while fl.next < fl.blocks.length:
        let bi = fl.next
        fl.next++
        let near = fl.blocks[bi]
        if near.length:
            let b0 = int3 { bi % nb.x, (bi / nb.x) % nb.y, bi / (nb.x * nb.y) } * 4
            let pc = base + float(b0) + float3_1 * 1.5
            // the block's centre, and the parts close enough to matter anywhere in it (the bins are loose boxes)
            let close = []::int
            var body = 1000.0
            var gear = 1000.0
            var best = 1000.0
            var mc = -1
            for(near) j:
                let pj = ps[j]
                let d = vx_dist(pc, pj)
                if pj.hard: gear = min(gear, if pj.model >= 0: d + 0.5 else: d)
                else: body = vx_smin(body, d, k)
                if d < best:
                    best = d
                    mc = if pj.model >= 0: vx_model_mat_at(pc, pj) else: pj.mat
                if d < reach + k + 3.0: close.push(j)
            let dc = min(body, gear - 0.5)
            if dc < reach:
                for(4) z: for(4) y: for(4) x:
                    let v = b0 + int3 { x, y, z }
                    let i = (v.z * dims.y + v.y) * dims.x + v.x
                    if dc < -reach:
                        mats[i] = mc
                        field[i] = -1.0
                    else:
                        let d, m = vx_field(ps, close, base + float(v), k)
                        field[i] = d
                        if d <= 0.0: mats[i] = m
            if (bi & 15) == 0 and seconds_elapsed() >= until: return fl.next >= fl.blocks.length
    return true

def vx_fill(parts:[vx_prim], unit_size:float, flies:bool = false) -> vx_shape:
    let fl = vx_fill_begin(parts, unit_size, flies)
    vx_fill_more(fl, 1000000000.0)
    return vx_fill_end(fl)

// The filled grid's surface: each surface voxel, its normal and how hemmed in it is.
def vx_fill_end(fl:vx_filling) -> vx_shape:
    let lo = fl.lo
    let dims = fl.dims
    let mats = fl.mats
    let field = fl.field
    // the surface, each voxel's normal from the distances around it
    let pos = []::int3
    let smat = []::int
    let nrm = []::float3
    let sy = dims.x
    let sz = dims.x * dims.y
    for(dims.z - 2) z0: for(dims.y - 2) y0: for(dims.x - 2) x0:
        let i = ((z0 + 1) * dims.y + y0 + 1) * dims.x + x0 + 1
        let m = mats[i]
        if m >= 0 and (mats[i - 1] < 0 or mats[i + 1] < 0 or mats[i - sy] < 0 or mats[i + sy] < 0 or mats[i - sz] < 0 or mats[i + sz] < 0):
            pos.push(lo + int3 { x0 + 1, y0 + 1, z0 + 1 })
            smat.push(m)
            nrm.push(normalize(float3 { field[i + 1] - field[i - 1], field[i + sy] - field[i - sy], field[i + sz] - field[i - sz] }))
    // ambient occlusion: how many of 14 voxels round it (2 out along the axes and the diagonals) are solid; an open
    // flat surface has about half
    let occl = map(pos) v:
        var hit = 0
        for(vx_AO_TAPS) t: if vx_solid_at(mats, lo, dims, v + t): hit++
        clamp((float(hit) / 14.0 - 0.45) / 0.35, 0.0, 1.0)
    return vx_shape { pos, smat, nrm, occl, lo, dims, mats }

// ---- surface patterns (materials.json's "pattern"): texture in the colour, by the voxel's place on its shape, so
// the same in every facing and every bake

// Value noise at p (smooth, 0..1): a lattice hashed, blended between.
def vx_noise(p:float3) -> float:
    let i = int3 { int(floor(p.x)), int(floor(p.y)), int(floor(p.z)) }
    let f = p - float(i)
    let u = f * f * (float3_1 * 3.0 - f * 2.0)
    def h(d:int3) -> float: return float(vx_hash(i + d)) / 1023.0
    let x00 = h(int3 { 0, 0, 0 }) + (h(int3 { 1, 0, 0 }) - h(int3 { 0, 0, 0 })) * u.x
    let x10 = h(int3 { 0, 1, 0 }) + (h(int3 { 1, 1, 0 }) - h(int3 { 0, 1, 0 })) * u.x
    let x01 = h(int3 { 0, 0, 1 }) + (h(int3 { 1, 0, 1 }) - h(int3 { 0, 0, 1 })) * u.x
    let x11 = h(int3 { 0, 1, 1 }) + (h(int3 { 1, 1, 1 }) - h(int3 { 0, 1, 1 })) * u.x
    let y0 = x00 + (x10 - x00) * u.y
    let y1 = x01 + (x11 - x01) * u.y
    return y0 + (y1 - y0) * u.z

def vx_fract(x:float) -> float: return x - floor(x)
def vx_cell_hash(a:int, b:int, m:int) -> float: return float(vx_hash(int3 { a, b, m })) / 1023.0

// Colour c of material m at voxel centre v (grid units) whose surface faces n, patterned. The pattern lies on the
// face's plane: across and up on a wall, x and y on a roof or a top.
def vx_patterned(m:int, v:float3, n:float3, c:float3) -> float3:
    let p = v / vx_pat_scale
    let an = abs(n)
    let top = an.z > max(an.x, an.y)
    let flat = an.x + an.y < 0.15
    var a = if top: p.x elif an.x > an.y: p.y else: p.x  // across
    var b = if top: p.y else: p.z                        // up (or along, on a top)
    if top and not flat:                                 // a slope: across it and down it, whichever way it faces (tiles and ripples run downhill)
        let down = normalize(float2 { n.x, n.y })
        a = p.x * -down.y + p.y * down.x
        b = p.x * down.x + p.y * down.y
    elif not top and vx_MAT_PROUND[m] != 0:  // a round wall (a tank): across is the way round it
        a = atan2(normalize(float2 { p.x - vx_pat_centre.x, p.y - vx_pat_centre.y })) * magnitude(float2 { p.x - vx_pat_centre.x, p.y - vx_pat_centre.y }) * 0.01745
    let sz = vx_MAT_PSIZE[m]
    let depth = vx_MAT_PDEPTH[m]
    let c2 = vx_MAT_C2[m]
    let mix = vx_MAT_PMIX[m]
    switch vx_MAT_PAT[m]:
        case 1:  // blocks: courses of stone, every other one shifted half a block, mortar between, each its own tone
            let row = int(floor(b / sz.y))
            let a2 = a + (if row % 2 != 0: sz.x * 0.5 else: 0.0)
            let col = int(floor(a2 / sz.x))
            let fa = vx_fract(a2 / sz.x) * sz.x
            let fb = vx_fract(b / sz.y) * sz.y
            if fa < 0.55 or fb < 0.55: return c * (1.0 - mix) + c2 * mix
            let edge = if fa < 1.2 or fb > sz.y - 0.7: 0.9 else: 1.0  // (a bevel: lit on top, dark below the joint)
            return c * (1.0 + depth * (vx_cell_hash(row, col, m) - 0.5) * 2.0) * edge * (0.94 + 0.12 * vx_noise(p * 1.3))
        case 2:  // planks: boards sz.x wide (upright on a wall, along x on a top), a dark seam, a tone each, grain
            let col = int(floor(a / sz.x))
            let fa = vx_fract(a / sz.x) * sz.x
            if fa < 0.45: return c * (1.0 - mix) + c2 * mix
            let grain = vx_noise(float3 { a * 3.0, b * 0.25, float(col) * 7.0 })
            return c * (1.0 + depth * (vx_cell_hash(col, 0, m) - 0.5) * 2.0) * (0.9 + 0.2 * grain)
        case 3:  // ripples: corrugated sheet, ridges every sz.x across (down the slope on a roof: across is x), a seam
            // every sz.y; rust in patches and in streaks running down
            let k = 1.0 + depth * sin(a / sz.x * 360.0)
            let seam = vx_fract(a / sz.y) * sz.y < 0.5
            let patch = vx_noise(p * 0.18 + float3 { 3.1, 7.7, 1.3 })
            let streak = vx_noise(float3 { a * 0.9, b * 0.06, 5.0 })
            let rust = clamp((patch - 0.62) * 5.0, 0.0, 1.0) * 0.8 + clamp((streak - 0.7) * 4.0, 0.0, 1.0) * 0.5
            let cr = c * k * (if seam: 0.78 else: 1.0)
            let r = min(1.0, rust * mix * (0.7 + 0.6 * vx_noise(p * 1.7)))
            return cr * (1.0 - r) + c2 * k * r
        case 4:  // tiles: rounded tiles sz.x wide in courses sz.y deep, each course overlapping the one below (its
            // lower edge dark), a tone each
            let row = int(floor(b / sz.y))
            let a2 = a + (if row % 2 != 0: sz.x * 0.5 else: 0.0)
            let col = int(floor(a2 / sz.x))
            let fa = vx_fract(a2 / sz.x)
            let fb = vx_fract(b / sz.y)
            let round = 0.78 + 0.32 * sin(fa * 180.0)
            let lap = if fb < 0.18: 1.0 - depth * 2.4 else: 1.0  // (the course's lap: as deep as its tones)
            let tone = 1.0 + depth * (vx_cell_hash(row, col, m) - 0.5) * 2.0
            let cc = c * round * lap * tone
            let moss = clamp((vx_noise(p * 0.25) - 0.66) * 4.0, 0.0, 1.0) * mix
            return cc * (1.0 - moss) + c2 * moss
        case 5:  // wear: plaster stained in soft patches, dirt splashed up from the ground
            let stain = vx_noise(p * 0.2) * 0.6 + vx_noise(p * 0.7) * 0.4
            let dirt = clamp(1.0 - p.z / 7.0, 0.0, 1.0) * (0.6 + 0.4 * vx_noise(p * 1.1))
            let k = 1.0 - depth * clamp((stain - 0.45) * 2.5, 0.0, 1.0)
            let d = min(1.0, dirt * mix)
            return c * k * (1.0 - d) + c2 * d
        case 6:  // mottle: a stone's or a bark's tone in soft patches and fine grain
            return c * (1.0 + depth * ((vx_noise(p * 0.45) - 0.5) * 1.4 + (vx_noise(p * 2.1) - 0.5) * 0.6))
        default: return c

// ---- drawing: each surface voxel splatted into the cell over the pixels its cube covers, the nearest kept

def vx_hash(v:int3) -> int:
    var h = v.x * 73856093 ^ v.y * 19349663 ^ v.z * 83492791
    h = (h ^ (h >> 13)) * 1274126177
    return (h ^ (h >> 16)) & 1023

let vx_LIGHT = normalize(float3 { -0.65, 0.1, 0.75 })  // the body's key light, as the camera sees it: high on the sun's side
var vx_shadows = true                                  // shadows on the body (its own, and occlusion in creases), and on the ground
// The light's other layers (Dominic, 2026-11-04: "bears too dark... missing a lighting specular etc"): the key light
// only multiplies a colour, so a dark coat went black in its shade and lost its form. On top of it: a sky fill from
// above (cool) and a bounce from the ground below (warm), both kept out of creases; a rim of sky light round the
// silhouette, most on the shadow side, so a dark body stands off the outline and the ground; a specular glint by each
// material's shine (metal hard and bright, fur a soft sheen). Banded like the key light, so it stays pixel art.
let vx_SKY = float3 { 0.13, 0.15, 0.2 }              // the sky fill at full (a surface facing straight up, open)
let vx_BOUNCE = float3 { 0.07, 0.06, 0.03 }          // the ground's bounce (a surface facing straight down)
let vx_RIM = float3 { 0.62, 0.7, 0.85 }              // the rim's light (the sky behind the unit)
var vx_SUN = normalize(float3 { -0.55, 0.45, 1.0 })  // towards the sun, as the camera sees it: upper left (the world's; a game may lower it)
var vx_depth = []::float                             // the cell being drawn (reused: only the last one's box is cleared)
var vx_cols = []::float3
var vx_mat = []::int
var vx_out = []::float4
var vx_box = int4_0  // the last cell's box, outline included: x0, y0, x1, y1

// One facing of a shape as a sprite cell (alpha 0 around it; drawn in vx_box): the cell is reused by the next call,
// so copy what's wanted first. The team colour's key (magenta) survives the shading, so the game's sprite shader can
// recolour it.
def vx_cell(sh:vx_shape, facing:int) -> [float4]: return vx_cell_in(sh, facing, vx_CELL.x, vx_CELL.y, vx_ANCHOR)

// The same, in a cell cw x ch with the ground point at anchor (buildings and props are bigger than units).
def vx_cell_in(sh:vx_shape, facing:int, cw:int, ch:int, anchor:int2) -> [float4]:
    let yaw = float(facing) * 45.0
    let rot = fn(v:float3) -> float3: float3 { v.x * cos(yaw) - v.y * sin(yaw), v.x * sin(yaw) + v.y * cos(yaw), v.z }
    let ru = rot(float3 { 1.0, 0.0, 0.0 })
    let rv = rot(float3 { 0.0, sin(vx_ELEV), cos(vx_ELEV) })
    let rd = rot(float3 { 0.0, cos(vx_ELEV), -sin(vx_ELEV) })
    let light = rot(vx_LIGHT)
    let view = rd * -1.0                                // towards the camera
    let gloss = normalize(light + view)                 // the specular's half vector
    let hx = 0.5 * (abs(ru.x) + abs(ru.y) + abs(ru.z))  // the cube's half extent on screen
    let hy = 0.5 * (abs(rv.x) + abs(rv.y) + abs(rv.z))
    if vx_depth.length != cw * ch:
        vx_depth = map(cw * ch): 1000000.0
        vx_cols = map(cw * ch): float3_0
        vx_mat = map(cw * ch): -1
        vx_out = map(cw * ch): float4_0
    else:  // the last cell's box cleared
        for(vx_box.w - vx_box.y + 1) yy: for(vx_box.z - vx_box.x + 1) xx:
            let j = (vx_box.y + yy) * cw + vx_box.x + xx
            vx_depth[j] = 1000000.0
            vx_mat[j] = -1
            vx_out[j] = float4_0
    var box = int4 { cw, ch, -1, -1 }
    for(sh.pos) v, i:
        let m = sh.mats[i]
        let p = float(v) + float3_1 * 0.5
        let u = dot(p, ru)
        let w = dot(p, rv)
        let d = dot(p, rd)
        let nv = sh.normals[i]
        var k = dot(nv, light) * 0.5 + 0.5
        var lit = k > 0.42  // in the key light (not shadowed, not turned away)
        if vx_shadows:
            // in its own shadow? a few steps towards the light through the grid
            var q = p + sh.normals[i] * 1.2 + light * 1.0
            for(8):
                if k > 0.42 and vx_solid_at(sh.grid, sh.lo, sh.dims, int3 { int(floor(q.x)), int(floor(q.y)), int(floor(q.z)) }) and q.z > 0.0:
                    k = 0.3
                    lit = false
                q += light * 1.7
            k -= sh.occl[i] * 0.3
        let base = vx_mat_cols[m]
        var c = base * (if k > 0.8: 1.08 elif k > 0.62: 0.94 elif k > 0.45: 0.76 elif k > 0.28: 0.6 else: 0.47)
        if vx_MAT_GLOW[m] == 0:
            let opn = 1.0 - (if vx_shadows: sh.occl[i] else: 0.0) * 0.8
            let up = nv.z
            // the fill: added light, tinted half by the surface's own colour (so it lifts a dark coat, barely moves a
            // pale one); the team's key only scaled (the sprite shader reads its hue)
            let fill = (vx_SKY * max(up, 0.0) + vx_SKY * 0.45 + vx_BOUNCE * max(-up, 0.0)) * opn
            let rimk = 1.0 - max(dot(nv, view), 0.0)
            let rim = (if rimk > 0.82: 0.2 elif rimk > 0.68: 0.09 else: 0.0) * (if lit: 0.55 else: 1.0) * opn
            let sp = dot(nv, gloss)
            let shine = vx_MAT_SHINE[m] * (if not lit: 0.0 elif sp > 0.975: 0.3 elif sp > 0.92: 0.1 else: 0.0)
            // (the darker the surface, the more the fill and rim show: a pale one is lit enough already)
            let dark = 1.0 - clamp((base.x * 0.3 + base.y * 0.59 + base.z * 0.11 - 0.15) / 0.5, 0.0, 0.75)
            if m == vx_mat_team: c *= 1.0 + rim * 1.2 + shine * 1.4
            else: c += (fill + vx_RIM * rim) * (base * 0.5 + float3_1 * 0.5) * dark + vx_mix(float3_1, base, 0.4) * shine
        if vx_MAT_PAT[m] != 0: c = vx_patterned(m, p, sh.normals[i], c)
        if vx_MAT_FUR[m] != 0: c *= 1.0 + vx_fur * (float(vx_hash(v)) / 511.5 - 1.0)
        if vx_MAT_GLOW[m] != 0: c = vx_mat_cols[m]  // (a light: unshaded)
        c = min(c, float3_1)                        // (over 1 wraps round in the game's texture: a bright pink came out cyan)
        let x0 = max(1, int(-floor(-(float(anchor.x) + u - hx - 0.5))))
        let x1 = min(cw - 2, int(floor(float(anchor.x) + u + hx - 0.5)))
        let y0 = max(1, int(-floor(-(float(anchor.y) - w - hy - 0.5))))
        let y1 = min(ch - 2, int(floor(float(anchor.y) - w + hy - 0.5)))
        box = int4 { min(box.x, x0), min(box.y, y0), max(box.z, x1), max(box.w, y1) }
        for(y1 - y0 + 1) yy: for(x1 - x0 + 1) xx:
            let j = (y0 + yy) * cw + x0 + xx
            if d < vx_depth[j]:
                vx_depth[j] = d
                vx_cols[j] = c
                vx_mat[j] = m
    vx_box = int4 { box.x - 1, box.y - 1, box.z + 1, box.w + 1 }  // (the outline round it)
    for(vx_box.w - vx_box.y + 1) yy: for(vx_box.z - vx_box.x + 1) xx:
        let px = vx_box.x + xx
        let py = vx_box.y + yy
        let j = py * cw + px
        if vx_mat[j] >= 0:
            // a softer line where this pixel stands well in front of the one beside it (a limb across the body)
            var c = vx_cols[j]
            for([ 1, -1, cw, -cw ]) dj:
                if vx_mat[j + dj] >= 0 and vx_depth[j + dj] > vx_depth[j] + 5.0: c = vx_cols[j] * 0.72
            vx_out[j] = float4 { c.x, c.y, c.z, 1.0 }
        else:
            for([ 1, -1, cw, -cw ]) dj:
                let q = j + dj
                if q >= 0 and q < cw * ch and vx_mat[q] >= 0:
                    let m = vx_mat[q]
                    let c = if m == vx_mat_team: float3 { 0.22, 0.07, 0.06 } else: vx_mat_cols[m] * 0.3
                    vx_out[j] = float4 { c.x, c.y, c.z, 1.0 }
    vx_halo(cw, ch)
    return vx_out

// A soft halo round every light in the cell (a lit window's glow on the wall round it and the air in front): each pixel
// near a light takes the nearest one's colour, fading with the distance, the strongest kept (not summed).
var vx_glow = []::float
def vx_halo(cw:int, ch:int):
    let lights = []::int
    for(vx_box.w - vx_box.y + 1) yy: for(vx_box.z - vx_box.x + 1) xx:
        let j = (vx_box.y + yy) * cw + vx_box.x + xx
        if vx_mat[j] >= 0 and vx_MAT_GLOW[vx_mat[j]] != 0: lights.push(j)
    if not lights.length: return
    let r = max(3, int(3.5 * vx_pat_scale))
    if vx_glow.length != cw * ch: vx_glow = map(cw * ch): 0.0
    let cols = map(cw * ch): float3_0
    var box = vx_box
    for(lights) j:
        let lx = j % cw
        let ly = j / cw
        let lc = vx_cols[j]
        for(r * 2 + 1) dy: for(r * 2 + 1) dx:
            let x = lx + dx - r
            let y = ly + dy - r
            if x >= 1 and y >= 1 and x < cw - 1 and y < ch - 1:
                let d = sqrt(float((dx - r) * (dx - r) + (dy - r) * (dy - r))) / float(r)
                if d < 1.0:
                    let f = (1.0 - d) * (1.0 - d) * 0.55
                    let q = y * cw + x
                    if f > vx_glow[q]:
                        vx_glow[q] = f
                        cols[q] = lc
                        box = int4 { min(box.x, x), min(box.y, y), max(box.z, x), max(box.w, y) }
    for(box.w - box.y + 1) yy: for(box.z - box.x + 1) xx:
        let q = (box.y + yy) * cw + box.x + xx
        let f = vx_glow[q]
        if f > 0.0:
            vx_glow[q] = 0.0
            if vx_mat[q] < 0 or vx_MAT_GLOW[vx_mat[q]] == 0:
                let o = vx_out[q]
                if o.w > 0.0: vx_out[q] = float4 { min(1.0, o.x + cols[q].x * f), min(1.0, o.y + cols[q].y * f), min(1.0, o.z + cols[q].z * f), 1.0 }
                else: vx_out[q] = float4 { cols[q].x, cols[q].y, cols[q].z, f * 0.8 }
    vx_box = box

// One facing's shadow on the ground (the sun's, as the world's props and buildings cast it): a cell of its own, drawn
// under every unit. vx_SCELL wide and high round vx_SANCHOR; drawn in vx_sbox; reused by the next call.
var vx_SCELL = int2 { vx_CELL.x * 2, vx_CELL.y }
var vx_SANCHOR = int2 { vx_SCELL.x / 2 - int(14.0 * vx_RES), vx_SCELL.y - int(44.0 * vx_RES) }

// The voxels a body unit (the game raises it on a high-DPI screen, #358), and the cells that follow from it.
def vx_set_res(res:float):
    vx_RES = res
    vx_CELL = int2 { int(100.0 * vx_RES), int(170.0 * vx_RES) }
    vx_ANCHOR = int2 { vx_CELL.x / 2, vx_CELL.y - int(40.0 * vx_RES) }
    vx_SCELL = int2 { vx_CELL.x * 2, vx_CELL.y }
    vx_SANCHOR = int2 { vx_SCELL.x / 2 - int(14.0 * vx_RES), vx_SCELL.y - int(44.0 * vx_RES) }

let vx_SHADOW = float4 { 0.05, 0.04, 0.02, 0.5 }
var vx_sout = []::float4
var vx_sbox = int4_0

def vx_ground_shadow(sh:vx_shape, facing:int) -> [float4]: return vx_ground_shadow_in(sh, facing, vx_SCELL.x, vx_SCELL.y, vx_SANCHOR)

def vx_ground_shadow_in(sh:vx_shape, facing:int, cw:int, ch:int, anchor:int2) -> [float4]:
    let yaw = float(facing) * 45.0
    let rot = fn(v:float3) -> float3: float3 { v.x * cos(yaw) - v.y * sin(yaw), v.x * sin(yaw) + v.y * cos(yaw), v.z }
    let ru = rot(float3 { 1.0, 0.0, 0.0 })
    let rv = rot(float3 { 0.0, sin(vx_ELEV), cos(vx_ELEV) })
    let sun = rot(vx_SUN)
    if vx_sout.length != cw * ch: vx_sout = map(cw * ch): float4_0
    else:
        for(vx_sbox.w - vx_sbox.y + 1) yy: for(vx_sbox.z - vx_sbox.x + 1) xx: vx_sout[(vx_sbox.y + yy) * cw + vx_sbox.x + xx] = float4_0
    var box = int4 { cw, ch, -1, -1 }
    for(sh.pos) v:
        let p = float(v) + float3_1 * 0.5
        if p.z < 3.0:  // a contact shadow under what touches the ground, a few px thick: the game draws a baked px
            // at 0.55 world px, nearest sampled, so a sliver under the soles vanished and units read as floating
            let u0 = dot(float3 { p.x, p.y, 0.0 }, ru)
            let w0 = dot(float3 { p.x, p.y, 0.0 }, rv)
            for(7) yy: for(13) xx:
                let dx = float(xx - 6)
                let dy = float(yy - 2)
                if dx * dx / 36.0 + (dy - 1.0) * (dy - 1.0) / 9.0 <= 1.0:
                    let x = int(floor(float(anchor.x) + u0 + dx))
                    let y = int(floor(float(anchor.y) - w0 + dy))
                    if x >= 0 and y >= 0 and x < cw and y < ch:
                        vx_sout[y * cw + x] = vx_SHADOW
                        box = int4 { min(box.x, x), min(box.y, y), max(box.z, x), max(box.w, y) }
        let g = p - sun * (p.z / sun.z)
        let u = dot(g, ru)
        let w = dot(g, rv)
        let x0 = max(0, int(floor(float(anchor.x) + u - 0.7)))
        let y0 = max(0, int(floor(float(anchor.y) - w - 0.7)))
        let x1 = min(cw - 1, x0 + 1)
        let y1 = min(ch - 1, y0 + 1)
        box = int4 { min(box.x, x0), min(box.y, y0), max(box.z, x1), max(box.w, y1) }
        for(y1 - y0 + 1) yy: for(x1 - x0 + 1) xx: vx_sout[(y0 + yy) * cw + x0 + xx] = vx_SHADOW
    vx_sbox = box
    return vx_sout

// A facing drawn into an image at (cx, cy), its ground shadow under it when shadows are on.
// Does the unit stand in its shadow, as the game draws it (a baked px at k world px, nearest sampled, the anchor at a
// sub-pixel offset ph)? A unit over a gap reads as floating (Dominic, 2026-11-01: "they're floating"). Standing (every
// foot planted): at least half its soles (its pixels with nothing under them in its lowest 2 rows) have shadow showing
// straight under them. Walking (a foot may swing free): some sole in its lowest 6 rows does.
def vx_stands(cell:[float4], sc:[float4], k:float, ph:float, standing:bool) -> bool:
    let n = 70  // world px round the anchor each way
    let um = map(n * 2 * n * 2): false
    let sm = map(n * 2 * n * 2): false
    for(n * 2) j: for(n * 2) i:
        let bx = int(floor(float(vx_ANCHOR.x) + (float(i - n) + 0.5 - ph) / k))
        let by = int(floor(float(vx_ANCHOR.y) + (float(j - n) + 0.5 - ph) / k))
        if bx >= 0 and by >= 0 and bx < vx_CELL.x and by < vx_CELL.y: um[j * n * 2 + i] = cell[by * vx_CELL.x + bx].w > 0.0
        let sx = bx - vx_ANCHOR.x + vx_SANCHOR.x
        let sy = by - vx_ANCHOR.y + vx_SANCHOR.y
        if sx >= 0 and sy >= 0 and sx < vx_SCELL.x and sy < vx_SCELL.y: sm[j * n * 2 + i] = sc[sy * vx_SCELL.x + sx].w > 0.0
    var low = -1
    for(n * 2) j: for(n * 2) i: if um[j * n * 2 + i]: low = max(low, j)
    var soles = 0
    var shaded = 0
    for(if standing: 2 else: 6) r: for(n * 2) i:
        let j = low - r
        if j >= 0 and j + 2 < n * 2 and um[j * n * 2 + i] and not um[(j + 1) * n * 2 + i]:
            soles++
            if sm[(j + 1) * n * 2 + i] or (sm[(j + 2) * n * 2 + i] and not um[(j + 2) * n * 2 + i]): shaded++
    return if standing: soles > 0 and shaded * 2 >= soles else: shaded > 0

def vx_draw(sh:vx_shape, facing:int, img:[float3], iw:int, cx:int, cy:int):
    if vx_shadows:
        let sc = vx_ground_shadow(sh, facing)
        let ox = cx + vx_ANCHOR.x - vx_SANCHOR.x
        let oy = cy + vx_ANCHOR.y - vx_SANCHOR.y
        for(vx_sbox.w - vx_sbox.y + 1) yy: for(vx_sbox.z - vx_sbox.x + 1) xx:
            let c = sc[(vx_sbox.y + yy) * vx_SCELL.x + vx_sbox.x + xx]
            let x = ox + vx_sbox.x + xx
            let y = oy + vx_sbox.y + yy
            if c.w > 0.0 and x >= 0 and x < iw and y >= 0 and y * iw < img.length:
                let j = y * iw + x
                img[j] = img[j] * (1.0 - c.w) + xyz(c) * c.w
    let cell = vx_cell(sh, facing)
    for(vx_box.w - vx_box.y + 1) yy: for(vx_box.z - vx_box.x + 1) xx:
        let c = cell[(vx_box.y + yy) * vx_CELL.x + vx_box.x + xx]
        if c.w > 0.0: img[(cy + vx_box.y + yy) * iw + cx + vx_box.x + xx] = xyz(c)
