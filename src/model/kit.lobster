// ------------------------------------------------------------------ the model kit (step 6d; scenes/art_pixel/unit_models.gd's helpers)
// The 3D parts are built here as Godot builds them: a tree of nodes (position, rotation, scale), each
// with a mesh made as Godot's primitive meshes make theirs (the same vertices, normals, UVs and
// triangles: prim_check.lobster holds them to prim_dump.gd's numbers) and a material (a texture,
// a tint, how it maps). model_tris() (model/flat.lobster) flattens a tree into the baker's triangles.
// Angles are degrees here (Lobster's sin and cos); Godot's radians come in through rad().

import std
import vec
import dictionary

let MPI = 3.141592653589793                        // (Godot's PI to the last digit: a walk step on a boundary falls the same way)
def rad(r:float) -> float: return r * 180.0 / MPI  // radians (Godot's) to the degrees used here

// ------------------------------------------------------------------ bases (3x3, by columns)

class Basis:
    x:float3
    y:float3
    z:float3

let BASIS_ID = Basis { float3 { 1.0, 0.0, 0.0 }, float3 { 0.0, 1.0, 0.0 }, float3 { 0.0, 0.0, 1.0 } }

def bxf(b:Basis, v:float3) -> float3: return b.x * v.x + b.y * v.y + b.z * v.z
def bmul(a:Basis, b:Basis) -> Basis: return Basis { bxf(a, b.x), bxf(a, b.y), bxf(a, b.z) }
def bscaled(b:Basis, s:float3) -> Basis: return Basis { b.x * s.x, b.y * s.y, b.z * s.z }   // b x diag(s) (Godot's scaled_local)
def bscaled_global(b:Basis, s:float3) -> Basis: return Basis { b.x * s, b.y * s, b.z * s }  // Godot's Basis.scaled: diag(s) x b
def btransposed(b:Basis) -> Basis:
    return Basis { float3 { b.x.x, b.y.x, b.z.x }, float3 { b.x.y, b.y.y, b.z.y }, float3 { b.x.z, b.y.z, b.z.z } }
def bdet(b:Basis) -> float: return dot(b.x, cross(b.y, b.z))
def binverse(b:Basis) -> Basis:
    let d = bdet(b)
    // the inverse's rows are the cofactor columns over the determinant
    return btransposed(Basis { cross(b.y, b.z) / d, cross(b.z, b.x) / d, cross(b.x, b.y) / d })

// Godot's Basis.from_euler (YXZ: Ry x Rx x Rz), in degrees.
def euler(r:float3) -> Basis:
    let cx = cos(r.x)
    let sx = sin(r.x)
    let cy = cos(r.y)
    let sy = sin(r.y)
    let cz = cos(r.z)
    let sz = sin(r.z)
    let rx = Basis { float3 { 1.0, 0.0, 0.0 }, float3 { 0.0, cx, sx }, float3 { 0.0, -sx, cx } }
    let ry = Basis { float3 { cy, 0.0, -sy }, float3 { 0.0, 1.0, 0.0 }, float3 { sy, 0.0, cy } }
    let rz = Basis { float3 { cz, sz, 0.0 }, float3 { -sz, cz, 0.0 }, float3 { 0.0, 0.0, 1.0 } }
    return bmul(bmul(ry, rx), rz)

// A turn of `ang` degrees about `axis` (Godot's Basis(axis, angle), in degrees).
def axis_angle(axis:float3, ang:float) -> Basis:
    let a = normalize(axis)
    let c = cos(ang)
    let s = sin(ang)
    let t = 1.0 - c
    return Basis { float3 { t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y },
                   float3 { t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x },
                   float3 { t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c } }

// A quaternion (x, y, z, w) as a basis.
def quat_basis(q:float4) -> Basis:
    let d = dot(q, q)
    let s = 2.0 / d
    let xs = q.x * s
    let ys = q.y * s
    let zs = q.z * s
    let wx = q.w * xs
    let wy = q.w * ys
    let wz = q.w * zs
    let xx = q.x * xs
    let xy = q.x * ys
    let xz = q.x * zs
    let yy = q.y * ys
    let yz = q.y * zs
    let zz = q.z * zs
    // (Godot's Basis::set_quaternion, its rows turned into columns)
    return btransposed(Basis { float3 { 1.0 - (yy + zz), xy - wz, xz + wy },
                               float3 { xy + wz, 1.0 - (xx + zz), yz - wx },
                               float3 { xz - wy, yz + wx, 1.0 - (xx + yy) } })

// Godot's Quaternion(arc_from, arc_to): the shortest turn taking one direction to the other.
def arc(from_:float3, to:float3) -> Basis:
    let c = cross(from_, to)
    let d = dot(from_, to)
    if d < -1.0 + 0.00001: return quat_basis(float4 { 0.0, 1.0, 0.0, 0.0 })
    let s = sqrt((1.0 + d) * 2.0)
    let rs = 1.0 / s
    return quat_basis(float4 { c.x * rs, c.y * rs, c.z * rs, s * 0.5 })

// Godot's Basis.looking_at(target, up): -z towards the target.
def basis_looking_at(target:float3, up:float3) -> Basis:
    let z = normalize(-target)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    return Basis { x, y, z }

// ------------------------------------------------------------------ transforms

class Xform:
    b:Basis
    o:float3

let XF_ID = Xform { BASIS_ID, float3_0 }
def xf(t:Xform, p:float3) -> float3: return bxf(t.b, p) + t.o
def xmul(a:Xform, b:Xform) -> Xform: return Xform { bmul(a.b, b.b), xf(a, b.o) }
def xinverse(t:Xform) -> Xform:
    let bi = binverse(t.b)
    return Xform { bi, -bxf(bi, t.o) }

// ------------------------------------------------------------------ materials

// A StandardMaterial3D as the baker needs it: its colour, its texture (textures/<name>.png, made from
// assets/art/textures/<name>.svg by tex_png.gd) and how it's mapped, and what else it does to the light.
class MMat:
    albedo:float3
    rope = false  // a rope (siege models: tied at both ends, the placement check's C3)
    tex = ""      // texture name; "" for none
    triplanar = false
    uv_scale = float3_1
    uv_offset = float3_0
    scissor = false  // alpha scissor at 0.5 (decals)
    unshaded = false
    emission = float3_0
    vertex_colours = false  // the mesh's own colours multiply the albedo
    two_sided = false
    // the rest of StandardMaterial3D (Godot's defaults), for the buildings' materials (model/build_mats.lobster)
    roughness = 1.0
    metallic = 0.0
    metallic_specular = 0.5
    clearcoat_enabled = false
    clearcoat = 1.0
    normal_enabled = false
    normal_tex = ""  // its normal map (a path as tex is), "" for none
    normal_scale = 1.0
    world_triplanar = false  // triplanar in world space (uv1_world_triplanar)
    triplanar_sharpness = 1.0
    texture_filter = 3  // BaseMaterial3D.TextureFilter: 3 linear with mipmaps, 5 that and anisotropic

// ------------------------------------------------------------------ meshes

// A mesh's vertices and its triangles (indices, three a triangle), as Godot's arrays.
class MMesh:
    p:[float3]
    n:[float3]
    uv:[float2]
    idx:[int]
    c = []::float3  // vertex colours, if any
    prim = 0        // PRIM_: the primitive it was made as (geom.lobster fills those exactly), with
    pp = float4_0   // its numbers: sphere (radius, height, hemisphere 0/1), cylinder (top,
    // bottom, height), box (size), torus (inner, outer)

let PRIM_SPHERE = 1
let PRIM_CYLINDER = 2
let PRIM_BOX = 3
let PRIM_TORUS = 4
let PRIM_FLAT = 5  // a quad or plane: a picture on a surface, no volume

def new_mesh() -> MMesh: return MMesh { [], [], [], [] }

def add_vertex(m:MMesh, p:float3, n:float3, uv:float2):
    m.p.push(p)
    m.n.push(n)
    m.uv.push(uv)

// SphereMesh (radius, height, radial segments, rings; a hemisphere flattens its lower half onto y = 0).
def sphere_mesh(radius:float, height:float, radial:int, rings:int, hemisphere:bool) -> MMesh:
    let m = new_mesh()
    m.prim = PRIM_SPHERE
    m.pp = float4 { radius, height, if hemisphere: 1.0 else: 0.0, 0.0 }
    let scale = height * (if hemisphere: 1.0 else: 0.5)
    var thisrow = 0
    var prevrow = 0
    var point = 0
    for(rings + 2) j:
        let v = float(j) / float(rings + 1)
        let w = sin(180.0 * v)
        let y = scale * cos(180.0 * v)
        for(radial + 1) i:
            let u = float(i) / float(radial)
            let x = sin(u * 360.0)
            let z = cos(u * 360.0)
            if hemisphere and y < 0.0:
                add_vertex(m, float3 { x * radius * w, 0.0, z * radius * w }, float3 { 0.0, -1.0, 0.0 }, float2 { u, v })
            else:
                add_vertex(m, float3 { x * radius * w, y, z * radius * w },
                           normalize(float3 { x * w * scale, radius * (y / scale), z * w * scale }), float2 { u, v })
            point++
            if i > 0 and j > 0:
                append_into(m.idx, [ prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 ])
        prevrow = thisrow
        thisrow = point
    return m

// CylinderMesh (top and bottom radii, height, radial segments, rings, caps).
def cylinder_mesh(top:float, bottom:float, height:float, radial:int, rings:int, cap_top:bool, cap_bottom:bool) -> MMesh:
    let m = new_mesh()
    m.prim = PRIM_CYLINDER
    m.pp = float4 { top, bottom, height, 0.0 }
    var thisrow = 0
    var prevrow = 0
    var point = 0
    let side_y = (bottom - top) / height
    for(rings + 2) j:
        let v = float(j) / float(rings + 1)
        let r = top + (bottom - top) * v
        let y = height * 0.5 - height * v
        for(radial + 1) i:
            let u = float(i) / float(radial)
            let x = sin(u * 360.0)
            let z = cos(u * 360.0)
            add_vertex(m, float3 { x * r, y, z * r }, normalize(float3 { x, side_y, z }), float2 { u, v * 0.5 })
            point++
            if i > 0 and j > 0:
                append_into(m.idx, [ prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 ])
        prevrow = thisrow
        thisrow = point
    if cap_top and top > 0.0:
        let y = height * 0.5
        thisrow = point
        add_vertex(m, float3 { 0.0, y, 0.0 }, float3 { 0.0, 1.0, 0.0 }, float2 { 0.25, 0.75 })
        point++
        for(radial + 1) i:
            let r = float(i) / float(radial)
            let x = sin(r * 360.0)
            let z = cos(r * 360.0)
            add_vertex(m, float3 { x * top, y, z * top }, float3 { 0.0, 1.0, 0.0 }, float2 { (x + 1.0) * 0.25, 0.5 + (z + 1.0) * 0.25 })
            point++
            if i > 0: append_into(m.idx, [ thisrow, point - 1, point - 2 ])
    if cap_bottom and bottom > 0.0:
        let y = height * -0.5
        thisrow = point
        add_vertex(m, float3 { 0.0, y, 0.0 }, float3 { 0.0, -1.0, 0.0 }, float2 { 0.75, 0.75 })
        point++
        for(radial + 1) i:
            let r = float(i) / float(radial)
            let x = sin(r * 360.0)
            let z = cos(r * 360.0)
            add_vertex(m, float3 { x * bottom, y, z * bottom }, float3 { 0.0, -1.0, 0.0 }, float2 { 0.5 + (x + 1.0) * 0.25, 1.0 - (z + 1.0) * 0.25 })
            point++
            if i > 0: append_into(m.idx, [ thisrow, point - 2, point - 1 ])
    return m

// TorusMesh (inner and outer radius, rings round it, segments round the tube).
def torus_mesh(inner:float, outer:float, rings:int, segs:int) -> MMesh:
    let m = new_mesh()
    m.prim = PRIM_TORUS
    m.pp = float4 { inner, outer, 0.0, 0.0 }
    let lo = min(inner, outer)
    let hi = max(inner, outer)
    let radius = (hi - lo) * 0.5
    for(rings + 1) i:
        let prevrow = (i - 1) * (segs + 1)
        let thisrow = i * (segs + 1)
        let inci = float(i) / float(rings)
        let angi = inci * 360.0
        let ni = float2 { -sin(angi), -cos(angi) }
        for(segs + 1) j:
            let incj = float(j) / float(segs)
            let angj = incj * 360.0
            let nj = float2 { -cos(angj), sin(angj) }
            let nk = nj * radius + float2 { lo + radius, 0.0 }
            add_vertex(m, float3 { ni.x * nk.x, nk.y, ni.y * nk.x }, float3 { ni.x * nj.x, nj.y, ni.y * nj.x }, float2 { inci, incj })
            if i > 0 and j > 0:
                append_into(m.idx, [ thisrow + j - 1, prevrow + j, prevrow + j - 1, thisrow + j - 1, thisrow + j, prevrow + j ])
    return m

// BoxMesh (size, subdivisions across, up, deep): each pair of opposite sides built at once, as Godot does.
def box_mesh(size:float3, sw:int, sh:int, sd:int) -> MMesh:
    let m = new_mesh()
    m.prim = PRIM_BOX
    m.pp = float4 { size.x, size.y, size.z, 0.0 }
    let st = size * -0.5
    let third = 1.0 / 3.0
    for(3) pair:  // front + back, right + left, top + bottom
        let cols = if pair == 1: sd + 1 else: sw + 1
        let rows = if pair == 2: sd + 1 else: sh + 1
        var thisrow = m.p.length
        var prevrow = 0
        for(rows + 1) j:
            for(cols + 1) i:
                let u = float(i) / (3.0 * float(cols))
                let v = float(j) / (2.0 * float(rows))
                if pair == 0:
                    let x = st.x + size.x * float(i) / float(cols)
                    let y = st.y + size.y * float(j) / float(rows)
                    add_vertex(m, float3 { x, -y, -st.z }, float3 { 0.0, 0.0, 1.0 }, float2 { u, v })
                    add_vertex(m, float3 { -x, -y, st.z }, float3 { 0.0, 0.0, -1.0 }, float2 { 2.0 * third + u, v })
                elif pair == 1:
                    let z = st.z + size.z * float(i) / float(cols)
                    let y = st.y + size.y * float(j) / float(rows)
                    add_vertex(m, float3 { -st.x, -y, -z }, float3 { 1.0, 0.0, 0.0 }, float2 { third + u, v })
                    add_vertex(m, float3 { st.x, -y, z }, float3 { -1.0, 0.0, 0.0 }, float2 { u, 0.5 + v })
                else:
                    let x = st.x + size.x * float(i) / float(cols)
                    let z = st.z + size.z * float(j) / float(rows)
                    add_vertex(m, float3 { -x, -st.y, -z }, float3 { 0.0, 1.0, 0.0 }, float2 { third + u, 0.5 + v })
                    add_vertex(m, float3 { x, st.y, -z }, float3 { 0.0, -1.0, 0.0 }, float2 { 2.0 * third + u, 0.5 + v })
                if i > 0 and j > 0:
                    let i2 = i * 2
                    append_into(m.idx, [ prevrow + i2 - 2, prevrow + i2, thisrow + i2 - 2, prevrow + i2, thisrow + i2, thisrow + i2 - 2,
                                         prevrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1 ])
            prevrow = thisrow
            thisrow = m.p.length
    return m

let FACE_Y = 1
let FACE_Z = 2
def plane_mesh(size:float2, sw:int, sd:int, face:int, centre:float3) -> MMesh:
    let m = new_mesh()
    m.prim = PRIM_FLAT
    let st = size * -0.5
    var thisrow = 0
    var prevrow = 0
    var point = 0
    var z = st.y
    for(sd + 2) j:
        var x = st.x
        for(sw + 2) i:
            let u = float(i) / float(sw + 1)
            let v = float(j) / float(sd + 1)
            let p = if face == FACE_Y: float3 { -x, 0.0, -z } elif face == FACE_Z: float3 { -x, z, 0.0 } else: float3 { 0.0, z, x }
            let n = if face == FACE_Y: float3 { 0.0, 1.0, 0.0 } elif face == FACE_Z: float3 { 0.0, 0.0, 1.0 } else: float3 { 1.0, 0.0, 0.0 }
            add_vertex(m, p + centre, n, float2 { 1.0 - u, 1.0 - v })
            point++
            if i > 0 and j > 0:
                append_into(m.idx, [ prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 ])
            x += size.x / float(sw + 1)
        z += size.y / float(sd + 1)
        prevrow = thisrow
        thisrow = point
    return m

def quad_mesh(size:float2) -> MMesh: return plane_mesh(size, 0, 0, FACE_Z, float3_0)

// ------------------------------------------------------------------ polygons (Godot's Geometry2D.triangulate_polygon: ear clipping)

def poly_area(c:[float2]) -> float:
    var a = 0.0
    var p = c.length - 1
    for(c.length) q:
        a += c[p].x * c[q].y - c[q].x * c[p].y
        p = q
    return a * 0.5

def inside_tri(a:float2, b:float2, c:float2, p:float2, edges:bool) -> bool:
    let acb = (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x)
    let ccp = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    let bcp = (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x)
    if edges: return acb >= 0.0 and bcp >= 0.0 and ccp >= 0.0
    return acb > 0.0 and bcp > 0.0 and ccp > 0.0

def snip(c:[float2], u:int, v:int, w:int, n:int, vv:[int], relaxed:bool) -> bool:
    let a = c[vv[u]]
    let b = c[vv[v]]
    let cc = c[vv[w]]
    let threshold = if relaxed: -0.00001 else: 0.00001
    if threshold > (b.x - a.x) * (cc.y - a.y) - (b.y - a.y) * (cc.x - a.x): return false
    for(n) p:
        if p != u and p != v and p != w:
            if inside_tri(a, b, cc, c[vv[p]], relaxed): return false
    return true

def triangulate(c:[float2]) -> [int]:
    let out = []::int
    let n = c.length
    if n < 3: return out
    let vv = if poly_area(c) > 0.0: map(n) i: i else: map(n) i: n - 1 - i
    var relaxed = false
    var nv = n
    var count = 2 * nv
    var v = nv - 1
    while nv > 2:
        if 0 >= count:
            if relaxed: return []
            count = 2 * nv
            relaxed = true
        count--
        var u = v
        if nv <= u: u = 0
        v = u + 1
        if nv <= v: v = 0
        var w = v + 1
        if nv <= w: w = 0
        if snip(c, u, v, w, nv, vv, relaxed):
            append_into(out, [ vv[u], vv[v], vv[w] ])
            var s = v
            while s + 1 < nv:
                vv[s] = vv[s + 1]
                s++
            nv--
            count = 2 * nv
    return out

// ------------------------------------------------------------------ nodes

// A Node3D (a MeshInstance3D when it has a mesh): its transform as Godot keeps it (a rotation in
// degrees and a scale, or a basis set outright), its mesh and material, its children.
class MNode:
    pos = float3_0
    rot = float3_0  // Godot's rotation_degrees (YXZ)
    scl = float3_1
    bas:Basis? = nil  // a basis set outright (Godot's `basis =`): used in place of rot
    mesh:MMesh? = nil
    mat:MMat? = nil
    kids = []::MNode
    visible = true
    meta = ""  // what it is, for checks (a decal's name)
    vol = -1   // a .glb mesh's surfaces share this (one volume: geom.lobster fills them together)

def mnode() -> MNode: return MNode {}
def mesh_node(m:MMesh, mat:MMat) -> MNode:
    let n = MNode {}
    n.mesh = m
    n.mat = mat
    return n

def add_child(n:MNode, k:MNode) -> MNode:
    n.kids.push(k)
    return k

def node_basis(n:MNode) -> Basis:
    let b = n.bas
    if b: return bscaled(b, n.scl)
    return bscaled(euler(n.rot), n.scl)

def node_xform(n:MNode) -> Xform: return Xform { node_basis(n), n.pos }

// Godot's `basis = b`: the rotation and scale come from it (scale back to one: the basis holds it).
def set_basis(n:MNode, b:Basis):
    n.bas = b
    n.scl = float3_1

def set_xform(n:MNode, t:Xform):  // transform =
    set_basis(n, t.b)
    n.pos = t.o
