// Reading MagicaVoxel .vox files (#313): the models (a size and its voxels, each a palette index 1..255), the
// palette, the MATL materials, and the scene graph flattened to objects: each a model placed in the scene, with
// the name, layer and hidden flag of the transform above it. Bytes in, a vox_file out; a broken file gives
// vox_file.error, never a crash. Pure: nothing here knows about bodies or materials (view/voxel.lobster maps them).
// The format: github.com/ephtracy/voxel-model (MagicaVoxel-file-format-vox.txt, -extension.txt). Chunks we
// don't use (rOBJ, rCAM, NOTE, IMAP ...) are skipped by their size.

import vec

class vox_model:
    size:int3
    xyz:[int3]
    idx:[int]  // per voxel, its palette index (1..255)

class vox_node:  // an object: a model placed in the scene
    name:string
    layer:string
    hidden:bool
    model:int
    t:int3    // where the model's centre is
    r:[int3]  // and how it's turned: the rows of a matrix

class vox_matl:
    id:int          // the palette index it's for
    props:[string]  // key, value, key, value ...

class vox_file:
    error:string = ""
    models:[vox_model] = []
    palette:[int] = []  // 0xRRGGBB, entry i - 1 for palette index i
    mats:[vox_matl] = []
    nodes:[vox_node] = []

// MagicaVoxel's palette when a file has no RGBA: 215 steps of a 6 x 6 x 6 cube (white first), then ramps of red,
// green, blue and grey, 10 steps each
def vox_default_palette() -> [int]:
    let six = [ 0xff, 0xcc, 0x99, 0x66, 0x33, 0x00 ]
    let ten = [ 0xee, 0xdd, 0xbb, 0xaa, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11 ]
    let p = []
    for(six) r: for(six) g: for(six) b: if p.length < 215: p.push((r << 16) | (g << 8) | b)
    for(ten) v: p.push(v << 16)
    for(ten) v: p.push(v << 8)
    for(ten) v: p.push(v)
    for(ten) v: p.push((v << 16) | (v << 8) | v)
    p.push(0)
    return p

// A rotation byte: bits 0-1 the column of row 0's one, 2-3 row 1's, bits 4, 5, 6 a row negative. [] if not a turn.
def vox_rot(r:int) -> [int3]:
    let c0 = r & 3
    let c1 = (r >> 2) & 3
    if c0 == 3 or c1 == 3 or c0 == c1: return []
    let c2 = 3 - c0 - c1
    let cs = [ c0, c1, c2 ]
    let rows = map(3) i:
        let s = if (r >> (4 + i)) & 1: -1 else: 1
        let c = cs[i]
        int3 { if c == 0: s else: 0, if c == 1: s else: 0, if c == 2: s else: 0 }
    return rows

def vox_rot_mul(a:[int3], b:[int3]) -> [int3]:
    return map(3) i:
        let row = a[i]
        int3 { row.x * b[0].x + row.y * b[1].x + row.z * b[2].x, row.x * b[0].y + row.y * b[1].y + row.z * b[2].y,
               row.x * b[0].z + row.y * b[1].z + row.z * b[2].z }

def vox_idot(a:int3, b:int3) -> int: return a.x * b.x + a.y * b.y + a.z * b.z
def vox_rot_apply(m:[int3], v:int3) -> int3: return int3 { vox_idot(m[0], v), vox_idot(m[1], v), vox_idot(m[2], v) }

let vox_NO_TURN = [ int3 { 1, 0, 0 }, int3 { 0, 1, 0 }, int3 { 0, 0, 1 } ]

// Where a model's voxel n is in the scene: centred on the model (its middle voxel, rounded down), turned, moved
def vox_world(f:vox_file, nd:vox_node, n:int) -> int3:
    let m = f.models[nd.model]
    return vox_rot_apply(nd.r, m.xyz[n] - m.size / 2) + nd.t

def vox_node(f:vox_file, name:string) -> int:
    for(f.nodes) nd, i: if nd.name == name: return i
    return -1

def vox_rgb(f:vox_file, index:int) -> int: return f.palette[index - 1]

def vox_mat_props(f:vox_file, index:int) -> [string]:
    for(f.mats) m: if m.id == index: return m.props
    return []

def vox_prop(kv:[string], key:string) -> string?:
    var i = 0
    while i + 1 < kv.length:
        if kv[i] == key: return kv[i + 1]
        i += 2
    return nil

def vox_mat_type(f:vox_file, index:int) -> string: return vox_prop(vox_mat_props(f, index), "_type") or "_diffuse"

def vox_mat_float(f:vox_file, index:int, key:string, fallback:float) -> float:
    let v = vox_prop(vox_mat_props(f, index), key)
    return if v: string_to_float(v) else: fallback

// ---- reading

class vox_reader:
    s:string
    pos:int
    end:int
    error:string = ""

    def fail(why:string):
        if error == "": error = why + " (at byte {pos})"
        pos = end

    def has(n:int) -> bool:
        if n < 0 or pos + n > end:
            fail("the file ends early")
            return false
        return true

    def i32() -> int:
        if not has(4): return 0
        let v, p = read_int32_le(s, pos)
        pos = p
        return v

    def u8() -> int:
        if not has(1): return 0
        let v, p = read_uint8_le(s, pos)
        pos = p
        return v

    def str() -> string:
        let n = i32()
        if not has(n): return ""
        let v = substring(s, pos, n)
        pos += n
        return v

    def dict() -> [string]:
        let n = i32()
        if n < 0 or n > (end - pos) / 8:
            fail("a dictionary of {n}")
            return []
        let kv = []
        for(n * 2): kv.push(str())
        return kv

class vox_scene_node:  // nTRN, nGRP or nSHP, as read
    kind:int           // 0 transform, 1 group, 2 shape
    attrs:[string]
    children:[int]  // a transform's one child, a group's children, a shape's models
    layer:int
    frame:[string]

def vox_parse(s:string) -> vox_file:
    let f = vox_file {}
    let rd = vox_reader { s, 0, s.length }
    if s.length < 8 or substring(s, 0, 4) != "VOX ":
        f.error = "not a .vox file"
        return f
    rd.pos = 8
    if not rd.has(12) or substring(s, 8, 4) != "MAIN":
        f.error = "no MAIN chunk"
        return f
    rd.pos = 12
    let main_content = rd.i32()
    let main_children = rd.i32()
    rd.pos += max(main_content, 0)
    if rd.error == "" and (main_content < 0 or main_children != s.length - rd.pos):
        rd.fail("MAIN\'s chunks are {main_children} bytes, the file has {s.length - rd.pos}")
    var size = int3_0
    var have_size = false
    var palette = []::int
    let scene = []::vox_scene_node
    let scene_ids = []::int
    let layer_ids = []::int
    let layer_names = []::string
    let layer_hidden = []::bool
    while rd.error == "" and rd.pos < rd.end:
        if not rd.has(12): break
        let id = substring(s, rd.pos, 4)
        rd.pos += 4
        let n = rd.i32()
        let kids = rd.i32()
        if not rd.has(n): break
        let next = rd.pos + n
        let body = vox_reader { s, rd.pos, next }
        switch id:
            case "SIZE":
                size = int3 { body.i32(), body.i32(), body.i32() }
                have_size = true
                if size.x < 1 or size.y < 1 or size.z < 1 or size.x > 256 or size.y > 256 or size.z > 256:
                    body.fail("a model of size {size}")
            case "XYZI":
                if not have_size: body.fail("XYZI without a SIZE")
                let nv = body.i32()
                if nv < 0 or nv * 4 > next - body.pos: body.fail("{nv} voxels in a chunk of {n} bytes")
                let m = vox_model { size, [], [] }
                for(nv):
                    let v = int3 { body.u8(), body.u8(), body.u8() }
                    let c = body.u8()
                    if body.error == "" and (v.x >= size.x or v.y >= size.y or v.z >= size.z):
                        body.fail("a voxel at {v} outside its model of {size}")
                    m.xyz.push(v)
                    m.idx.push(c)
                f.models.push(m)
                have_size = false
            case "RGBA":
                palette = map(256):
                    let r = body.u8()
                    let g = body.u8()
                    let b = body.u8()
                    body.u8()
                    (r << 16) | (g << 8) | b
            case "MATL":
                let mid = body.i32()
                f.mats.push(vox_matl { mid, body.dict() })
            case "LAYR":
                layer_ids.push(body.i32())
                let kv = body.dict()
                layer_names.push(vox_prop(kv, "_name") or "")
                layer_hidden.push((vox_prop(kv, "_hidden") or "0") == "1")
            case "nTRN":
                scene_ids.push(body.i32())
                let attrs = body.dict()
                let child = body.i32()
                body.i32()  // (reserved)
                let layer = body.i32()
                let nframes = body.i32()
                var frame = []::string
                for(nframes) k:
                    let fr = body.dict()
                    if k == 0: frame = fr
                scene.push(vox_scene_node { 0, attrs, [ child ], layer, frame })
            case "nGRP":
                scene_ids.push(body.i32())
                let attrs = body.dict()
                let nk = body.i32()
                if nk < 0 or nk * 4 > next - body.pos: body.fail("a group of {nk}")
                let children = map(nk): body.i32()
                scene.push(vox_scene_node { 1, attrs, children, -1, [] })
            case "nSHP":
                scene_ids.push(body.i32())
                let attrs = body.dict()
                let nm = body.i32()
                if nm < 0 or nm * 8 > next - body.pos: body.fail("a shape of {nm} models")
                let ms = map(nm):
                    let mi = body.i32()
                    body.dict()
                    mi
                scene.push(vox_scene_node { 2, attrs, ms, -1, [] })
            default: pass()
        if body.error != "": rd.fail(id + ": " + body.error)
        rd.pos = next + max(kids, 0)  // (children: only MAIN has any)
        if rd.pos > rd.end: rd.fail("a chunk\'s children run past the end")
    if rd.error != "":
        f.error = rd.error
        return f
    f.palette = if palette.length: palette else: vox_default_palette()
    // The scene graph, flattened: from node 0, moves and turns adding up, each shape an object named by the
    // transform above it (its layer too)
    def node_at(id:int) -> int:
        for(scene_ids) x, i: if x == id: return i
        return -1
    def walk(i:int, t:int3, r:[int3], name:string, layer:string, hidden:bool, depth:int) -> void:
        if f.error != "": return
        if i < 0:
            f.error = "the scene graph names a node that isn\'t there"
            return
        if depth > scene.length:
            f.error = "the scene graph is a loop"
            return
        let nd = scene[i]
        switch nd.kind:
            case 0:
                var t2 = t
                var r2 = r
                let ts = vox_prop(nd.frame, "_t")
                if ts:
                    let xyz = tokenize(ts, " ", " ")
                    if xyz.length == 3:
                        t2 = t + vox_rot_apply(r, int3 { string_to_int(xyz[0]), string_to_int(xyz[1]), string_to_int(xyz[2]) })
                let rs = vox_prop(nd.frame, "_r")
                if rs:
                    let m = vox_rot(string_to_int(rs))
                    if m.length != 3:
                        f.error = "a turn of {rs} isn\'t a rotation"
                        return
                    r2 = vox_rot_mul(r, m)
                var ln = layer
                var lh = hidden
                for(layer_ids) lid, k:
                    if lid == nd.layer:
                        ln = layer_names[k]
                        lh = lh or layer_hidden[k]
                let nm = vox_prop(nd.attrs, "_name") or name
                lh = lh or (vox_prop(nd.attrs, "_hidden") or "0") == "1"
                walk(node_at(nd.children[0]), t2, r2, nm, ln, lh, depth + 1)
            case 1: for(nd.children) c: walk(node_at(c), t, r, name, layer, hidden, depth + 1)
            default:
                for(nd.children) mi:
                    if mi < 0 or mi >= f.models.length:
                        f.error = "a shape names model {mi}, there are {f.models.length}"
                        return
                    f.nodes.push(vox_node { name, layer, hidden, mi, t, r })
    if scene.length:
        walk(node_at(0), int3_0, vox_NO_TURN, "", "", false, 0)
    else:
        for(f.models.length) i: f.nodes.push(vox_node { "", "", false, i, int3_0, vox_NO_TURN })
    if f.error != "":
        f.models = []
        f.nodes = []
    return f
