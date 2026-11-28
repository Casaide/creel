// ------------------------------------------------------------------ a .vox model as kit meshes (#262)
// A MagicaVoxel scene (view/vox's vox_file) as model/kit meshes, for the models baked through view/voxel_mesh (a
// pack's own building or prop): one mesh a palette index, only the faces that show (a voxel's face against an empty
// cell, so a solid model is a closed shell), every shown object of the scene where the scene puts it. Each voxel is
// `size` world units; the whole stands on y 0, centred on x and z; MagicaVoxel's z is up and its front (the -y side,
// where its front view looks from) faces +z. Pure: no materials (a game maps the palette indices to its own).
// Needs (imported before this file): view/vox, model/kit.

// The six faces of a voxel: the neighbour it faces (in .vox axes), and its corners (0/1 per axis, in turn round it).
let VXM_DIRS = [ int3 { 1, 0, 0 }, int3 { -1, 0, 0 }, int3 { 0, 1, 0 }, int3 { 0, -1, 0 }, int3 { 0, 0, 1 }, int3 { 0, 0, -1 } ]
let VXM_CORNERS = [ [ int3 { 1, 0, 0 }, int3 { 1, 1, 0 }, int3 { 1, 1, 1 }, int3 { 1, 0, 1 } ],
                    [ int3 { 0, 0, 0 }, int3 { 0, 0, 1 }, int3 { 0, 1, 1 }, int3 { 0, 1, 0 } ],
                    [ int3 { 0, 1, 0 }, int3 { 0, 1, 1 }, int3 { 1, 1, 1 }, int3 { 1, 1, 0 } ],
                    [ int3 { 0, 0, 0 }, int3 { 1, 0, 0 }, int3 { 1, 0, 1 }, int3 { 0, 0, 1 } ],
                    [ int3 { 0, 0, 1 }, int3 { 1, 0, 1 }, int3 { 1, 1, 1 }, int3 { 0, 1, 1 } ],
                    [ int3 { 0, 0, 0 }, int3 { 0, 1, 0 }, int3 { 1, 1, 0 }, int3 { 1, 0, 0 } ] ]

// A .vox point (its z up, its -y front) in world axes (y up, +z front).
def vxm_world(p:float3) -> float3: return float3 { p.x, p.z, -p.y }

class VoxMeshes:
    index:[int]    // the palette index of each mesh
    meshes:[MMesh]
    lo:float3      // the whole's box, world units
    hi:float3

// Every shown object's voxels of a scene (a file with no scene: its first model), each at its place in the scene, as
// meshes of the faces that show, a voxel `size` world units.
def vox_meshes(f:vox_file, size:float) -> VoxMeshes:
    let at = []::int3  // (the voxels, in .vox axes, and their palette indices)
    let ix = []::int
    if f.nodes.length:
        for(f.nodes) nd:
            if not nd.hidden and nd.model >= 0 and nd.model < f.models.length:
                for(f.models[nd.model].xyz) _, n:
                    at.push(vox_world(f, nd, n))
                    ix.push(f.models[nd.model].idx[n])
    elif f.models.length:
        let md = f.models[0]
        for(md.xyz) v, n:
            at.push(v)
            ix.push(md.idx[n])
    let out = VoxMeshes { [], [], float3_0, float3_0 }
    if not at.length: return out
    var lo = at[0]
    var hi = at[0]
    for(at) p:
        lo = min(lo, p)
        hi = max(hi, p)
    // (a grid a voxel bigger all round, so every neighbour is in it; a later object's voxel over an earlier one's wins)
    let dims = hi - lo + int3_1 * 3
    let grid = map(dims.x * dims.y * dims.z): 0
    def cell(p:int3) -> int: return ((p.z - lo.z + 1) * dims.y + p.y - lo.y + 1) * dims.x + p.x - lo.x + 1
    for(at) p, n: grid[cell(p)] = ix[n]
    // (centred on x and the front-to-back axis, standing on its lowest voxel)
    let mid = float3 { float(lo.x + hi.x + 1) * 0.5, float(lo.y + hi.y + 1) * 0.5, float(lo.z) }
    let by_index = map(256): -1
    for(hi.z - lo.z + 1) z: for(hi.y - lo.y + 1) y: for(hi.x - lo.x + 1) x:
        let p = lo + int3 { x, y, z }
        let i = grid[cell(p)]
        if i > 0:
            if by_index[i] < 0:
                by_index[i] = out.meshes.length
                out.index.push(i)
                out.meshes.push(new_mesh())
            let mesh = out.meshes[by_index[i]]
            for(VXM_DIRS) d, k:
                if grid[cell(p + d)] == 0:
                    let nrm = vxm_world(float(d))
                    let base = mesh.p.length
                    for(VXM_CORNERS[k]) c: add_vertex(mesh, vxm_world(float(p + c) - mid) * size, nrm, float2_0)
                    for([ 0, 1, 2, 0, 2, 3 ]) j: mesh.idx.push(base + j)
    out.lo = vxm_world(float3 { float(lo.x), float(hi.y + 1), float(lo.z) } - mid) * size
    out.hi = vxm_world(float3 { float(hi.x + 1), float(lo.y), float(hi.z + 1) } - mid) * size
    return out
