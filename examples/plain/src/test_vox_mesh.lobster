// A .vox model as kit meshes (#262): only the faces that show, normals out, standing on y 0 centred on x and z, its
// front (the .vox's -y) towards +z, a mesh a palette index, objects placed where the scene puts them. Headless, by
// hand. ../../../check.sh runs it.
//   lobster test_vox_mesh.lobster
import from "../../../src"
import std
import vec
import dictionary
import model.kit
import view.vox
import model.vox_mesh

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

def model_of(xyz:[int3], idx:[int]) -> vox_file:
    var size = int3_1
    for(xyz) v: size = max(size, v + int3_1)
    let f = vox_file {}
    f.models.push(vox_model { size, xyz, idx })
    return f

def faces(m:VoxMeshes) -> int:
    var n = 0
    for(m.meshes) mesh: n += mesh.idx.length / 6
    return n

// One voxel: a cube of 6 faces, 12 triangles, a voxel wide, on the ground, centred.
let one = vox_meshes(model_of([ int3_0 ], [ 3 ]), 0.5)
check(one.meshes.length == 1 and one.index[0] == 3, "one voxel: one mesh, of its palette index ({one.index})")
check(faces(one) == 6 and one.meshes[0].idx.length == 36, "one voxel: 6 faces, 12 triangles ({faces(one)})")
check(one.lo == float3 { -0.25, 0.0, -0.25 } and one.hi == float3 { 0.25, 0.5, 0.25 }, "one voxel stands on y 0, centred ({one.lo} {one.hi})")
for(one.meshes[0].p) p: check(p.y >= 0.0 and p.y <= 0.5 and abs(p.x) <= 0.25 and abs(p.z) <= 0.25, "one voxel\'s corner {p} in its box")

// Two side by side hide the faces they share; every normal points out of the model.
let two = vox_meshes(model_of([ int3_0, int3 { 1, 0, 0 } ], [ 1, 1 ]), 1.0)
check(faces(two) == 10, "two voxels side by side: 10 faces ({faces(two)})")
for(two.meshes) mesh:
    for(mesh.idx) i, k:
        if k % 6 == 0:
            var c = float3_0
            for(6) j: c += mesh.p[mesh.idx[k + j]]
            c /= 6.0
            check(dot(c - float3 { 0.0, 0.5, 0.0 }, mesh.n[i]) > 0.0, "a face at {c} faces out ({mesh.n[i]})")
check(two.lo.x == -1.0 and two.hi.x == 1.0, "two voxels centred on x ({two.lo} {two.hi})")

// Up and front: the .vox's z is up (y), its -y side faces +z; palette indices each their own mesh.
let tall = vox_meshes(model_of([ int3_0, int3 { 0, 0, 1 }, int3 { 0, 1, 0 } ], [ 1, 2, 5 ]), 1.0)
check(tall.meshes.length == 3, "three palette indices, three meshes ({tall.index})")
check(tall.hi.y == 2.0 and tall.lo.y == 0.0, "the .vox\'s z is up ({tall.lo} {tall.hi})")
let top = tall.meshes[find(tall.index) i: i == 2]
var top_y = 0.0
for(top.p) p: top_y = max(top_y, p.y)
check(top_y == 2.0, "index 2 (at .vox z 1) is the top voxel ({top_y})")
let back = tall.meshes[find(tall.index) i: i == 5]
var back_z = 1.0
for(back.p) p: back_z = min(back_z, p.z)
check(back_z == -1.0, "index 5 (at .vox y 1) is at the back, -z ({back_z})")

// A scene: a hidden object is left out, a shown one is placed where the scene puts it.
let scene = model_of([ int3_0 ], [ 1 ])
scene.models.push(vox_model { int3_1, [ int3_0 ], [ 2 ] })
scene.nodes.push(vox_node { "a", "", false, 0, int3_0, vox_NO_TURN })
scene.nodes.push(vox_node { "b", "", false, 1, int3 { 4, 0, 0 }, vox_NO_TURN })
scene.nodes.push(vox_node { "c", "", true, 1, int3 { 0, 0, 6 }, vox_NO_TURN })
let placed = vox_meshes(scene, 1.0)
check(faces(placed) == 12 and placed.hi.y == 1.0, "a hidden object is left out ({faces(placed)} faces, top {placed.hi.y})")
check(placed.hi.x - placed.lo.x == 5.0, "a shown object at its place in the scene ({placed.lo} {placed.hi})")
check(vox_meshes(vox_file {}, 1.0).meshes.length == 0, "an empty file: no meshes")

print "test_vox_mesh: {passes} passed, {fails} failed"
if fails: set_exit_code(1)
