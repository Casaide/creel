// ------------------------------------------------------------------ a built model as the baker's triangles
// Walks a node tree (model/kit.lobster) down to its meshes, each placed by its transforms, its normals
// by their inverse transpose (as Godot's), its colour the material's (times the mesh's own colours
// when the material asks), its material one of the baker's (one per distinct look, its texture from
// textures/<name>.png: tex_png.gd).

let model_tex_dir = "textures"

class BakeTri:
    p:[float3]
    n:[float3]
    c:[float3]
    uv:[float2]
    mat:int

// A material: its texture (or none) and how it's mapped (Godot's uv1 scale and offset, triplanar or not);
// in a library mesh, also the race channel its colour follows (m x the channel + b) or "" (fixed: b).
class BakeMat:
    tex:resource<texture>?
    scale:float2
    offset:float2
    triplanar:bool
    channel = "*"  // "*": the colour is on each triangle (a mesh made for one race)
    m = float3_0
    b = float3_0
    scissor = false  // alpha scissor (decals)
    unshaded = false
    emission = float3_0
    two_sided = false  // (cull disabled: a face seen from behind turns its normal to the camera)

let bake_mats = []::BakeMat

let bake_tex_cache = dictionary<string, resource<texture>>(16)

let model_mat_at = dictionary<string, int>(64)

def mat_index(m:MMat) -> int:
    let key = "{m.tex}|{m.triplanar}|{m.uv_scale}|{m.uv_offset}|{m.scissor}|{m.unshaded}|{m.emission}|{m.two_sided}"
    let known = model_mat_at.get(key, -1)
    if known >= 0: return known
    var tex:resource<texture>? = nil
    if m.tex != "":
        let file = if find_string(m.tex, "/") >= 0: m.tex + ".png" else: model_tex_dir + "/" + m.tex + ".png"
        tex = bake_tex_cache.get(file)
        if not tex:
            let loaded = gl.load_texture(file)
            assert loaded
            bake_tex_cache.set(file, loaded)
            tex = loaded
    let bm = BakeMat { tex, float2 { m.uv_scale.x, m.uv_scale.y }, float2 { m.uv_offset.x, m.uv_offset.y }, m.triplanar }
    bm.scissor = m.scissor
    bm.unshaded = m.unshaded
    bm.emission = m.emission
    bm.two_sided = m.two_sided
    bake_mats.push(bm)
    model_mat_at.set(key, bake_mats.length - 1)
    return bake_mats.length - 1

def flatten(n:MNode, parent:Xform, out:[BakeTri]) -> void:
    if not n.visible: return
    let t = xmul(parent, node_xform(n))
    let mesh = n.mesh
    let mat = n.mat
    if mesh and mat:
        let nb = btransposed(binverse(t.b))
        let mi = mat_index(mat)
        var k = 0
        while k + 2 < mesh.idx.length:
            let tri = BakeTri { [], [], [], [], mi }
            for(3) j:
                let i = mesh.idx[k + j]
                tri.p.push(xf(t, mesh.p[i]))
                tri.n.push(normalize(bxf(nb, mesh.n[i])))
                tri.c.push(if mat.vertex_colours and mesh.c.length > i: mat.albedo * mesh.c[i] else: mat.albedo)
                tri.uv.push(mesh.uv[i])
            out.push(tri)
            k += 3
    for(n.kids) kid: flatten(kid, t, out)

def model_tris(n:MNode) -> [BakeTri]:
    let out = []::BakeTri
    flatten(n, XF_ID, out)
    return out
