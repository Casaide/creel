// ------------------------------------------------------------------ buildings and props as voxels (D-203)
// A model (model/kit.lobster's meshes: the buildings, props, trees) rasterized into a shell of voxels, each voxel the
// colour its triangles' material gives there (the material's texture sampled, tinted, triplanar where the material
// is; a lit or unshaded one glows), then drawn as the voxel units are: light in bands, its own shadow, occlusion in the
// creases, an outline, its shadow on the ground. The sprite is in the old baker's frame (its camera, art px a world
// unit, the world origin as its anchor), so the art kits place every frame as they did.

var WB_ART = ART_SCALE                  // art px a canvas unit
var WB_PX = 32.0 / 0.70710678 * WB_ART  // art px a world unit (the old baker's camera: buildings keep their size)

let WB_SHADOW = [ 15, 13, 8, 107 ]  // the ground shadow's colour (0.06, 0.05, 0.03, 0.42), as the old baker's
let WB_CONTACT = [ 15, 13, 8, 61 ]  // the contact shadow's (alpha 0.24)

// ---- the model as wdraws: one per mesh, its MMat whole (the building materials carry more than BakeMat)

class WDraw:
    mat:MMat
    p:[float3]
    n:[float3]
    uv:[float2]
    c:[float3]

def world_draws(n:MNode, parent:Xform, out:[WDraw]) -> void:
    if not n.visible: return
    let t = xmul(parent, node_xform(n))
    let mesh = n.mesh
    let mat = n.mat
    if mesh and mat:
        let nb = btransposed(binverse(t.b))
        let d = WDraw { mat, [], [], [], [] }
        for(mesh.idx) i:
            d.p.push(xf(t, mesh.p[i]))
            d.n.push(normalize(bxf(nb, mesh.n[i])))
            d.uv.push(mesh.uv[i])
            d.c.push(if mat.vertex_colours and mesh.c.length > i: mesh.c[i] else: float3_1)
        out.push(d)
    for(n.kids) kid: world_draws(kid, t, out)

let wb_tex = dictionary<string, resource<texture>>(64)
def wb_texture(name:string) -> resource<texture>?:
    if name == "": return nil
    let file = if find_string(name, "/") >= 0: name + ".png" else: model_tex_dir + "/" + name + ".png"
    let known = wb_tex.get(file)
    if known: return known
    let t = gl.load_texture(file)
    assert t
    wb_tex.set(file, t)
    return t

// Godot's DirectionalLight3D shines along its -z: rotation_degrees -> where the light goes.
// Godot's DirectionalLight3D shines along its -z: rotation_degrees -> where the light goes.
def light_along(r:float3) -> float3: return -euler(r).z

// One model baked: its pixel sprite (RGBA bytes), w, h, and where its anchor (the world origin) is on it.
// shadow: paint its ground shadows; reach: room for them (trees cast long ones: 2).
let VM_PX = 1.5  // art px a voxel (the voxel units are about 1.1: buildings a little chunkier; a TC about 270 across)

class vm_shell:
    v:float  // a voxel's size, world units
    lo:int3  // the grid's corner (voxels) and size
    dims:int3
    nb:int3         // its blocks of 8 x 8 x 8 voxels, each made when a voxel lands in it ([] until then)
    blocks:[[int]]  // per block, per voxel in it: its slot, or -1
    pos:[int3]
    col:[float3]  // summed, then averaged
    nrm:[float3]
    hits:[int]
    glow:[bool]

// A voxel's slot (-1: empty, or outside the grid). (Blocks, not a dictionary: a lookup per sample, shadow step and
// occlusion tap was most of a building's bake.)
def vm_slot(sh:vm_shell, q:int3) -> int:
    let r = q - sh.lo
    if r.x < 0 or r.y < 0 or r.z < 0 or r.x >= sh.dims.x or r.y >= sh.dims.y or r.z >= sh.dims.z: return -1
    let b = sh.blocks[((r.z >> 3) * sh.nb.y + (r.y >> 3)) * sh.nb.x + (r.x >> 3)]
    return if b.length: b[((r.z & 7) * 8 + (r.y & 7)) * 8 + (r.x & 7)] else: -1

def vm_set_slot(sh:vm_shell, q:int3, slot:int):
    let r = q - sh.lo
    let bi = ((r.z >> 3) * sh.nb.y + (r.y >> 3)) * sh.nb.x + (r.x >> 3)
    if not sh.blocks[bi].length: sh.blocks[bi] = map(512): -1
    sh.blocks[bi][((r.z & 7) * 8 + (r.y & 7)) * 8 + (r.x & 7)] = slot

def vm_solid(sh:vm_shell, q:int3) -> bool: return vm_slot(sh, q) >= 0

let VM_SIDES = [ int3 { 1, 0, 0 }, int3 { -1, 0, 0 }, int3 { 0, 1, 0 }, int3 { 0, -1, 0 }, int3 { 0, 0, 1 }, int3 { 0, 0, -1 } ]

// A texture's pixels, read once (RGBA bytes, rows as the texture holds them).
class vm_image:
    px:string
    size:int2
let vm_images = dictionary<string, vm_image>(64)
def vm_image_of(name:string) -> vm_image?:
    if name == "": return nil
    let have = vm_images.get(name)
    if have: return have
    let t = wb_texture(name)
    if not t: return nil
    let img = vm_image { gl.read_texture(t) or "", gl.texture_size(t) }
    vm_images.set(name, img)
    return img

def vm_sample(img:vm_image, uv:float2) -> float4:
    let w = img.size.x
    let h = img.size.y
    if w <= 0 or h <= 0 or img.px.length < w * h * 4: return float4_1
    let x = ((int(floor(uv.x * float(w))) % w) + w) % w
    let y = ((int(floor(uv.y * float(h))) % h) + h) % h
    let o = (y * w + x) * 4
    return float4 { float(img.px[o]) / 255.0, float(img.px[o + 1]) / 255.0, float(img.px[o + 2]) / 255.0, float(img.px[o + 3]) / 255.0 }

// The material's colour at a point of a triangle (its uv, or triplanar from where it is), or alpha 0 where a decal's
// scissor cuts it away.
def vm_colour(m:MMat, img:vm_image?, p:float3, n:float3, uv:float2, vc:float3) -> float4:
    var c = float4 { m.albedo.x * vc.x, m.albedo.y * vc.y, m.albedo.z * vc.z, 1.0 }
    let im = img
    if im:
        var tuv = uv * xy(m.uv_scale) + xy(m.uv_offset)
        if m.triplanar:  // (the axis the face is most along picks the plane it's mapped on)
            let s = p * m.uv_scale + m.uv_offset
            let an = abs(n)
            tuv = if an.y >= an.x and an.y >= an.z: float2 { s.x, s.z } elif an.x >= an.z: float2 { s.z, -s.y } else: float2 { s.x, -s.y }
        let t = vm_sample(im, tuv)
        c = float4 { c.x * t.x, c.y * t.y, c.z * t.z, t.w }
    if m.scissor and c.w < 0.5: return float4_0
    return float4 { c.x, c.y, c.z, 1.0 }

// The model's triangles into a shell of voxels v world units across: each triangle sampled at 0.7 of a voxel (no
// voxel it crosses missed), each sample adding its colour and the face's normal to its voxel.
def vm_fill(model:MNode, v:float) -> vm_shell:
    let ds = []::WDraw
    world_draws(model, XF_ID, ds)
    if not ds.length: return vm_shell { v, int3_0, int3_0, int3_0, [], [], [], [], [], [] }  // (nothing shows: an empty grid)
    var lo = float3_1 * 1000000000.0
    var hi = float3_1 * -1000000000.0
    for(ds) d: for(d.p) p:
        lo = min(lo, p)
        hi = max(hi, p)
    let glo = int3 { int(floor(lo.x / v)) - 2, int(floor(lo.y / v)) - 2, int(floor(lo.z / v)) - 2 }
    let ghi = int3 { int(floor(hi.x / v)) + 3, int(floor(hi.y / v)) + 3, int(floor(hi.z / v)) + 3 }
    let dims = ghi - glo
    let nb = (dims + int3_1 * 7) / 8
    let sh = vm_shell { v, glo, dims, nb, map(nb.x * nb.y * nb.z): []::int, [], [], [], [], [] }
    for(ds) d:
        let m = d.mat
        let img = vm_image_of(m.tex)
        let glow = m.unshaded or m.emission != float3_0
        var k = 0
        while k + 2 < d.p.length:
            bake_pulse()
            let a = d.p[k]
            let e1 = d.p[k + 1] - a
            let e2 = d.p[k + 2] - a
            var fnorm = cross(e1, e2)
            let area = magnitude(fnorm)
            if area > 0.0:
                fnorm = fnorm / area
                if dot(fnorm, d.n[k] + d.n[k + 1] + d.n[k + 2]) < 0.0: fnorm = -fnorm  // (facing as its vertices say)
                let n = int(ceiling(max(magnitude(e1), max(magnitude(e2), magnitude(e2 - e1))) / (v * 0.7))) + 1
                var last_key = -1
                var last_slot = -1
                for(n + 1) i: for(n + 1 - i) j:
                    let bu = float(i) / float(n)
                    let bv = float(j) / float(n)
                    let p = a + e1 * bu + e2 * bv
                    let q = int3 { int(floor(p.x / v)), int(floor(p.y / v)), int(floor(p.z / v)) }
                    let key = ((q.z - glo.z) * dims.y + q.y - glo.y) * dims.x + q.x - glo.x
                    var slot = if key == last_key: last_slot else: vm_slot(sh, q)  // (the next sample is mostly in the same voxel)
                    if slot < 0 or sh.hits[slot] < 2:                              // (a voxel's colour and normal from its first two samples: the rest add nothing)
                        let tuv0 = d.uv[k] + (d.uv[k + 1] - d.uv[k]) * bu + (d.uv[k + 2] - d.uv[k]) * bv
                        let vc = d.c[k] + (d.c[k + 1] - d.c[k]) * bu + (d.c[k + 2] - d.c[k]) * bv
                        let c = vm_colour(m, img, p, fnorm, tuv0, vc)
                        // (the model's smooth normal there, its vertices' blended: the faces' flat ones shaded every
                        // facet of a low-poly stake or column as a hard edge)
                        var sn = d.n[k] + (d.n[k + 1] - d.n[k]) * bu + (d.n[k + 2] - d.n[k]) * bv
                        if dot(sn, fnorm) < 0.0: sn = -sn
                        if c.w > 0.0:
                            if slot < 0:
                                slot = sh.pos.length
                                vm_set_slot(sh, q, slot)
                                sh.pos.push(q)
                                sh.col.push(float3_0)
                                sh.nrm.push(float3_0)
                                sh.hits.push(0)
                                sh.glow.push(false)
                            last_key = key
                            last_slot = slot
                            sh.col[slot] += xyz(c)
                            sh.nrm[slot] += sn
                            sh.hits[slot]++
                            if glow: sh.glow[slot] = true
            k += 3
    // each normal blended with its six neighbours' (the voxel stairs don't speckle the light)
    let raw = copy(sh.nrm)
    for(sh.pos) q, i:
        bake_pulse()
        var n = raw[i] * 2.0
        for(VM_SIDES) o:
            let j = vm_slot(sh, q + o)
            if j >= 0 and dot(raw[j], raw[i]) > 0.0: n += raw[j]
        sh.nrm[i] = n
    for(sh.pos.length) i:
        sh.col[i] = sh.col[i] / float(sh.hits[i])
        let nm = magnitude(sh.nrm[i])
        sh.nrm[i] = if nm > 0.0: sh.nrm[i] / nm else: float3 { 0.0, 1.0, 0.0 }
    return sh

let VM_AO_TAPS = [ int3 { 2, 0, 0 }, int3 { -2, 0, 0 }, int3 { 0, 2, 0 }, int3 { 0, -2, 0 }, int3 { 0, 0, 2 }, int3 { 0, 0, -2 },
                   int3 { 2, 2, 2 }, int3 { -2, 2, 2 }, int3 { 2, -2, 2 }, int3 { -2, -2, 2 },
                   int3 { 2, 2, -2 }, int3 { -2, 2, -2 }, int3 { 2, -2, -2 }, int3 { -2, -2, -2 } ]

let VM_SPLAT = [ int2 { 0, 0 }, int2 { 1, 0 }, int2 { 0, 1 }, int2 { 1, 1 } ]
let VM_VIEW = float3 { -30.0, 45.0, 0.0 }  // the camera's turn
var VM_SUN = float3 { -48.0, -58.0, 0.0 }  // the light's (a game may lower it before it bakes: a low sun casts long shadows)

// A model as a voxel sprite in world_bake's frame: RGBA bytes, rows top down, its size, the world origin on it.
def voxel_bake(model:MNode, shadow:bool) -> string, int, int, float2:
    let sh = vm_fill(model, VM_PX / WB_PX)
    let sun = light_along(VM_SUN)
    let to_light = -sun
    // the light: in bands by the sun, its own shadow (a few steps towards the light through the shell), occlusion in
    // the creases
    return vm_draw(sh, shadow) i:
        let q = sh.pos[i]
        var k = 1.0
        if not sh.glow[i]:
            let n = sh.nrm[i]
            k = dot(n, to_light) * 0.5 + 0.5
            var r = float(q) + float3_1 * 0.5 + n * 1.2 + to_light * 1.0
            for(10):
                if k > 0.42 and vm_solid(sh, int3 { int(floor(r.x)), int(floor(r.y)), int(floor(r.z)) }): k = 0.3
                r += to_light * 1.7
            var hit = 0
            for(VM_AO_TAPS) t: if vm_solid(sh, q + t): hit++
            k -= clamp((float(hit) / 14.0 - 0.45) / 0.35, 0.0, 1.0) * 0.3
            k = 0.52 + 0.54 * smoothstep(0.15, 0.95, k)  // (a smooth ramp: hard bands read as inked comic art, Dominic)
        min(sh.col[i] * k, float3_1)

// A shell drawn as a sprite in world_bake's frame: each voxel that shows in the colour shadef(its slot) gives, an
// outline, and (shadow) its shadows on the ground. RGBA bytes, rows top down, its size, the world origin on it.
def vm_draw(sh:vm_shell, shadow:bool, shadef) -> string, int, int, float2:
    let px = WB_PX
    let v = sh.v
    let view = euler(VM_VIEW)
    let cx = view.x
    let cy = view.y
    let cz = view.z
    let sun = light_along(VM_SUN)  // (where the light goes)
    def screen(p:float3) -> float2: return float2 { dot(p, cx), -dot(p, cy) } * px
    // the frame: the voxels and their shadows on the ground
    var lo = float2_1 * 1000000000.0
    var hi = float2_1 * -1000000000.0
    for(sh.pos) q:
        bake_pulse()
        let p = (float(q) + float3_1 * 0.5) * v
        let s = screen(p)
        lo = min(lo, s)
        hi = max(hi, s)
        if shadow and p.y > 0.0:
            let g = screen(p + sun * (p.y / -sun.y))
            lo = min(lo, g)
            hi = max(hi, g)
    if not sh.pos.length: return "", 0, 0, float2_0
    lo -= float2_1 * 4.0
    hi += float2_1 * 4.0
    let w = int(ceiling(hi.x - lo.x))
    let h = int(ceiling(hi.y - lo.y))
    let depth = map(w * h): -1000000000.0
    let win = map(w * h): -1  // the voxel each pixel shows
    let hx = 0.5 * v * px * (abs(cx.x) + abs(cx.y) + abs(cx.z))
    let hy = 0.5 * v * px * (abs(cy.x) + abs(cy.y) + abs(cy.z))
    for(sh.pos) q, i:
        bake_pulse()
        let p = (float(q) + float3_1 * 0.5) * v
        let s = screen(p) - lo
        let d = dot(p, cz)  // (nearer: more)
        let x0 = max(0, int(ceiling(s.x - hx - 0.5)))
        let x1 = min(w - 1, int(floor(s.x + hx - 0.5)))
        let y0 = max(0, int(ceiling(s.y - hy - 0.5)))
        let y1 = min(h - 1, int(floor(s.y + hy - 0.5)))
        for(y1 - y0 + 1) yy: for(x1 - x0 + 1) xx:
            let j = (y0 + yy) * w + x0 + xx
            if d > depth[j]:
                depth[j] = d
                win[j] = i
    // each voxel that shows in its colour, worked out once
    let lit = map(sh.pos.length): float3_0
    let done = map(sh.pos.length): false
    let cols = map(w * h): float4_0
    for(win) i, j:
        if i >= 0:
            if not done[i]:
                bake_pulse()
                lit[i] = shadef(i)
                done[i] = true
            let c = lit[i]
            cols[j] = float4 { c.x, c.y, c.z, 1.0 }
    let out = ensure_size("", w * h * 4, 0)
    // the outline: only round the whole silhouette's outside (not every gap between stakes or posts), soft: the colour
    // beside it darkened a little, half seen (Dominic: "a lot of hard edges... we should soften")
    for(h) y: for(w) x:
        if x == 0: bake_pulse()
        let j = y * w + x
        var c = cols[j]
        if c.w == 0.0:
            for([ int2 { 1, 0 }, int2 { -1, 0 }, int2 { 0, 1 }, int2 { 0, -1 } ]) o:
                let xx = x + o.x
                let yy = y + o.y
                if c.w == 0.0 and xx >= 0 and yy >= 0 and xx < w and yy < h and cols[yy * w + xx].w > 0.0:
                    let b = cols[yy * w + xx]
                    c = float4 { b.x * 0.55, b.y * 0.55, b.z * 0.55, 0.55 }
        if c.w > 0.0:
            for(4) ch: write_int8_le(out, j * 4 + ch, clamp(int(c[ch] * 255.0 + 0.5), 0, 255))
    // the shadow on the ground, where nothing is drawn: the sun's, and a contact shadow round what stands on the ground
    // (the old baker's contact band: without it a rock or a barrel at the door floated, Dominic)
    if shadow:
        let rx = int(ceiling(hx)) + 1
        for(sh.pos) q:
            bake_pulse()
            let p = (float(q) + float3_1 * 0.5) * v
            if p.y < v * 3.0:
                let g = screen(float3 { p.x, 0.0, p.z }) - lo
                for(5) oy: for(rx * 2 + 1) ox:
                    let xx = int(floor(g.x)) + ox - rx
                    let yy = int(floor(g.y)) + oy - 1
                    if xx >= 0 and yy >= 0 and xx < w and yy < h and out[(yy * w + xx) * 4 + 3] == 0:
                        for(4) ch: write_int8_le(out, (yy * w + xx) * 4 + ch, WB_CONTACT[ch])
        for(sh.pos) q:
            bake_pulse()
            let p = (float(q) + float3_1 * 0.5) * v
            if p.y > v * 0.5:
                let g = screen(p + sun * (p.y / -sun.y)) - lo
                // (a low sun stretches each voxel's shadow along the way it falls: a run of dabs down to the shadow of
                // the voxel under it, so a long shadow has no gaps between its rows)
                let g2 = screen(p - float3 { 0.0, v, 0.0 } + sun * ((p.y - v) / -sun.y)) - lo
                let steps = max(1, int(ceiling(magnitude(g2 - g))))
                for(steps) st:
                    let gg = g + (g2 - g) * (float(st) / float(steps))
                    let x = int(floor(gg.x))
                    let y = int(floor(gg.y))
                    for(VM_SPLAT) o:
                        let xx = x + o.x
                        let yy = y + o.y
                        if xx >= 0 and yy >= 0 and xx < w and yy < h and out[(yy * w + xx) * 4 + 3] == 0:
                            for(4) ch: write_int8_le(out, (yy * w + xx) * 4 + ch, WB_SHADOW[ch])
    return out, w, h, -lo

// A sprite's ground shadows (its see-through pixels in the shadows' colour) apart from the rest: the art, the shadows.
def vm_split_shadow(sprite:string, w:int, h:int) -> string, string:
    let art = ensure_size("", w * h * 4, 0)
    let shade = ensure_size("", w * h * 4, 0)
    for(w * h) p:
        let o = p * 4
        let is_shadow = sprite[o + 3] > 0 and sprite[o + 3] < 255 and sprite[o] == WB_SHADOW[0] and sprite[o + 1] == WB_SHADOW[1] and sprite[o + 2] == WB_SHADOW[2]
        let into = if is_shadow: shade else: art
        for(4) k: write_int8_le(into, o + k, sprite[o + k])
    return art, shade
