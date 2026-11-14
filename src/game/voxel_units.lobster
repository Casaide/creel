// ------------------------------------------------------------------ voxel units
// Every unit type drawn as one procedural voxel body (view/voxel.lobster, from data/voxel/): its body, gear and mount
// read from its recipe, baked into atlases of 8 facings standing, walking, working, attacking and falling dead,
// drawn as whole-unit frames (collect_units). Engines with a crew (siege, the trade cart) are still composed.
//
// A look is what a line step looks like (its body, colours, kit and mount: most of a line's steps share one). The
// start bakes what each player fields in the age it starts in, standing and walking (and working, for workers), in
// their first look; the rest (attacks and falls, the other looks, the later ages' steps, the next age first) queue
// for play, baked a slice of a frame at a time. A step drawn before it's baked asks for it first and is drawn in the
// step before meanwhile. Each bake is kept in the bake cache (a PNG and a manifest), keyed by the look and the
// voxel builder's source and data: the next start loads it.

let VX_IDLE = 0
let VX_WALK = 1
let VX_WORK = 2
let VX_ATTACK = 3
let VX_DIE = 4
let VX_BUILD = 5  // a worker's jobs, each with its tool (Dominic, 2026-11-04: the right tool for the job): hammering,
let VX_MINE = 6   // picking at stone and gold, picking fruit into a basket (VX_WORK: chopping, the axe),
let VX_FORAGE = 7
let VX_CARRY = 8  // and walking a load home, one mode a resource (its look from data: gear.json's loads)
let VX_LOADS = [ "food", "wood", "stone", "gold" ]
let VX_MODES = 12
let VX_STEPS = [ 1, 8, 8, 8, 6, 8, 8, 8, 8, 8, 8, 8 ]                    // steps in each mode (a fall's last step is lying)
let VX_JOB_TOOL = [ "", "", "axe", "", "", "hammer", "pick", "basket" ]  // a work mode's tool
var VX_DRAW_K = 1.1 / vx_RES                                             // world art px a voxel (a body unit is 1.1 world px: the composed units' size)

// A look: a unit def, drawn the same by every type and step that has it.
class vx_lk:
    key:string
    u:vx_unit_def
    worker:bool
    cycle:float              // milli-tiles a walk cycle (the walk steps by the ground covered)
    planned:bool             // its bakes are queued (or loaded)
    pieces:[int]             // its parts' looks, in the body's order (the composer draws them on its hull)
    waited_for:bool = false  // a unit was drawn with it before it was baked: its first bakes go on through a fight

let vx_lks = []::vx_lk
let vx_lk_ids = dictionary<string, int>(256)
let vx_frames = dictionary<int, int>(16384)     // vx_fkey -> frame
let vx_shadow_of = dictionary<int, int>(16384)  // a unit's frame -> its ground shadow's frame
var vx_type_lks = []::[int]                     // type -> its line steps' looks (-1: composed)
var vx_cur = []::int                            // type -> the look it's drawn in now
var vx_source = ""                              // the builder's source's and data's hash (the cache key's code part)

def vx_fkey(lk:int, v:int, m:int, f:int, st:int) -> int: return (((lk * 4 + v) * VX_MODES + m) * 8 + f) * 8 + st

// Is type k drawn now (its look made)?
def vx_drawn(k:int) -> bool: return k < vx_cur.length and vx_cur[k] >= 0

// A palette's colours (palettes.json): its first three, zero where it has none.
def vx_palette(id:string) -> float3, float3, float3:
    let skins = at(lib_palettes, "skins")
    if not has(skins, id): return float3_0, float3_0, float3_0
    let cs = gstrs(skins, id)
    def c(i:int) -> float3: return if i < cs.length: xyz(hex_col(hex_of(cs[i]))) else: float3_0
    return c(0), c(1), c(2)

// The voxel body for a body id (bodies/<id>.json without the "body."; an engine's, siege.<kind>.<style>, its kind's),
// or its creature's, or a human's.
def vx_body_for(body_id:string, creature:string) -> string:
    let id = if starts_with(body_id, "body."): body_id.substring(5, body_id.length - 5) else: body_id
    if vx_bodies.get(id): return id
    let dot = find_string_reverse(id, ".")
    if starts_with(id, "siege.") and dot > 6 and vx_bodies.get(id.substring(0, dot)): return id.substring(0, dot)
    return if vx_bodies.get(creature): creature else: "human"

// Has the voxel kit an engine (or war beast) for this recipe? (Until it has, the composed one is drawn.)
def vx_engine_made(r:JV) -> bool: return not has(r, "crew") or starts_with(vx_body_for(rstr(r, "body"), ""), "siege.")

// An engine's colours in its style (the body's `styles`, by the id's last part; else its first).
def vx_style_of(body:string, body_id:string) -> float3, float3, float3:
    let b = vx_body_of(body)
    let style = if body_id.length > body.length + 1: body_id.substring(body.length + 1, body_id.length - body.length - 1) else: ""
    var k = find(b.style_names) n: n == style
    if k < 0: k = 0
    return b.style_cols[k * 3], b.style_cols[k * 3 + 1], b.style_cols[k * 3 + 2]

// A recipe as a voxel body and gear: its body (bodies/<body id>.json), the race's colours, each part's gear by
// gear.json's rules, its mount (its mount body, in its own colours).
def vx_def_of(r:JV) -> vx_unit_def:
    let cid = gstr(r, "creature", "")
    let fid = gstr(r, "family", "")
    let body = vx_culture_body(vx_body_for(rstr(r, "body"), cid), cid, if has(lib_families, fid): family(fid) else: jobj())
    var skin, pale, mark = vx_palette(gstr(r, "skin", ""))
    var crew:vx_unit_def? = nil
    if has(r, "crew"):  // an engine or a war beast: its frame in its style, its crew in their own colours
        assert vx_body_of(body).style_names.length
        skin, pale, mark = vx_style_of(body, rstr(r, "body"))
        crew = vx_def_of(at(r, "crew"))
    let gear = []::string
    let parts = gobj(r, "parts")
    for(sorted_strs(parts.keys)) slot:
        let id = as_str(at(parts, slot))
        let g = vx_tool_for(vx_body_of(body), vx_gear_for(id, ptags_of(id), slot))
        if g != "" and not (vx_body_of(body).bare and vx_worn_gear(g)): gear.push(g)
    var mount = ""
    var fused = false
    var coat, mane, coat_mark = float3_0, float3_0, float3_0
    if has(r, "mount"):
        let mo = at(r, "mount")
        let mc = rstr(mo, "creature")
        let c = creature(mc)
        fused = gbool(mo, "fused", false)
        mount = vx_body_for(gstr(c, "mount_body", gstr(c, "body", "")), mc)
        coat, mane, coat_mark = vx_palette(rstr(mo, "skin"))
    return vx_unit_def { gstr(r, "name", ""), body, skin, pale, mark, gear, mount, fused, coat, mane, coat_mark, crew }

// The look key of a unit def (what it's drawn as), its crew's too.
def vx_key_of(u:vx_unit_def) -> string:
    let c = u.crew
    let ck = if c: " crew \{" + vx_key_of(c) + "\}" else: ""
    return "{u.body} {u.skin} {u.pale} {u.mark} {u.gear} {u.mount} {u.fused} {u.coat} {u.mane} {u.coat_mark}{ck}"

// The look a recipe is drawn in (made the first time it's asked for; not baked until planned).
def vx_look_for(r:JV) -> int: return vx_look_of(vx_def_of(r), gstr(r, "role", "") == "worker")

def vx_look_of(u:vx_unit_def, worker:bool) -> int:
    let key = vx_key_of(u) + " {worker}"
    let have = vx_lk_ids.get(key, -1)
    if have >= 0: return have
    let lk = vx_lks.length
    let cycle = vx_walk_cycle(u)
    vx_lks.push(vx_lk { key, u, worker, cycle, false, [] })
    vx_lk_ids.set(key, lk)
    for(vx_body_of(u.body).parts) p:
        let pu = copy(u)
        pu.body = p.body
        vx_lks[lk].pieces.push(vx_look_of(pu, false))
    return lk

// ---- the bakes: a job is one look's poses in some modes, into an atlas of its own (its cells cropped to what's
// drawn, packed in rows VX_ATLAS wide), baked a pose at a time: filled (in slices), then drawn in 8 facings

var VX_ATLAS = 2048  // (4096 at a high-DPI density: its frames are larger, #358)
let VX_FORMATS = texture_format_clamp | texture_format_nomipmap | texture_format_nearest_mag | texture_format_nearest_min

class vx_job:
    lk:int
    v:int
    modes:[int]
    stem:string
    poses:[int2]  // (mode, step)
    at:int        // the pose being baked
    facing:int    // its next facing
    filling:vx_filling?
    shape:vx_shape?
    rows:[[float4]]
    pen:int2        // where the next cell goes
    row_h:int       // the tallest cell in the row
    lines:[string]  // the manifest: "f x y w h ox oy" a cell, "m mode facing step frame shadow" a pose's facing
    cells:int
    tex:resource<texture>?

var vx_queue = []::vx_job  // the bakes left for play, the next first
var vx_doing:vx_job? = nil

def vx_new_job(lk:int, v:int, modes:[int]) -> vx_job:
    let l = vx_lks[lk]
    let stem = bake_cache_dir + "/vx_" + sha256_text("{vx_source}|{l.key}|look {v}|modes {modes}|res {vx_RES}").substring(0, 20)
    let poses = []::int2
    // (a body with a gait shifts its weight standing; the rest stand on one frame, and vx_frame falls back to it)
    let stirs = vx_body_of(l.u.body).gait != nil and l.u.mount == ""
    for(modes) m: for(if m == VX_IDLE and stirs: 4 else: VX_STEPS[m]) st: poses.push(int2 { m, st })
    return vx_job { lk, v, modes, stem, poses, 0, 0, nil, nil, []::[float4], int2_0, 0, []::string, 0, nil }

// A cell just drawn (its box in a cell cw wide, the ground at anchor), packed: its index among the job's cells.
def vx_pack_cell(j:vx_job, cell:[float4], box:int4, cw:int, anchor:int2) -> int:
    let w = box.z - box.x + 1
    let h = box.w - box.y + 1
    if j.pen.x + w > VX_ATLAS:
        j.pen = int2 { 0, j.pen.y + j.row_h }
        j.row_h = 0
    while j.rows.length < j.pen.y + h: j.rows.push(map(VX_ATLAS): float4_0)
    for(h) y:
        let row = j.rows[j.pen.y + y]
        let at = (box.y + y) * cw + box.x
        for(w) x: row[j.pen.x + x] = cell[at + x]
    j.lines.push("f {j.pen.x} {j.pen.y} {w} {h} {anchor.x - box.x} {anchor.y - box.y}")
    j.pen.x += w
    j.row_h = max(j.row_h, h)
    j.cells++
    return j.cells - 1

// A job's manifest made frames on the sheet just added (the last), for its look.
def vx_publish(lk:int, v:int, manifest:[string]):
    let f0 = frames.length
    var cells = 0
    for(manifest) row:
        let t = tokenize(row, " ", "")
        if t.length and t[0] == "f":
            frames.push(Frame { sheet_tex.length - 1, string_to_int(t[1]), string_to_int(t[2]), string_to_int(t[3]), string_to_int(t[4]),
                                string_to_int(t[5]), string_to_int(t[6]), VX_DRAW_K })
            cells++
    for(manifest) row:
        let t = tokenize(row, " ", "")
        if t.length and t[0] == "m":
            let fr = f0 + string_to_int(t[4])
            vx_frames.set(vx_fkey(lk, v, string_to_int(t[1]), string_to_int(t[2]), string_to_int(t[3])), fr)
            vx_shadow_of.set(fr, f0 + string_to_int(t[5]))
            set_frame_role(fr, ROLE_UNIT)
            set_frame_role(f0 + string_to_int(t[5]), ROLE_CAST)

// The job's frames from the cache, if they're there.
def vx_load_job(j:vx_job) -> bool:
    let text = read_file(j.stem + ".txt")
    if not text: return false
    let rows = tokenize(text, "\n", "")
    let dims = tokenize(rows[0], " ", "")
    add_sheet_later(j.stem + ".png", float2 { string_to_float(dims[0]), string_to_float(dims[1]) }, VX_FORMATS)
    vx_publish(j.lk, j.v, rows)
    return true

// Bakes on until the clock passes `until`: true when the job is done (its frames published, and kept in the cache).
def vx_job_step(j:vx_job, until:float) -> bool:
    let l = vx_lks[j.lk]
    let u = l.u
    vx_set_look(u, j.v)  // (every slice: a figure baked between them sets its own colours)
    vx_pat_scale = vx_RES * vx_size_of(u)
    while seconds_elapsed() < until:
        let fl = j.filling
        let sh = j.shape
        if sh:
            let pose = j.poses[j.at]
            let fr = vx_pack_cell(j, vx_cell(sh, j.facing), vx_box, vx_CELL.x, vx_ANCHOR)
            let sf = vx_pack_cell(j, vx_ground_shadow(sh, j.facing), vx_sbox, vx_SCELL.x, vx_SANCHOR)
            j.lines.push("m {pose.x} {j.facing} {pose.y} {fr} {sf}")
            j.facing++
            if j.facing == 8:
                j.shape = nil
                j.at++
                if j.at == j.poses.length:
                    vx_finish(j)
                    return true
        elif fl:
            if vx_fill_more(fl, until):
                j.shape = vx_fill_end(fl)
                j.filling = nil
                j.facing = 0
        else:
            let pose = j.poses[j.at]
            let m = pose.x
            let job = m == VX_WORK or m == VX_BUILD or m == VX_MINE or m == VX_FORAGE
            vx_act = if m == VX_ATTACK or job: "attack" else: ""
            let carrying = m >= VX_CARRY
            vx_stand = m != VX_WALK and not carrying
            vx_carried = if carrying: VX_LOADS[m - VX_CARRY] else: ""
            var wu = u
            if job or carrying:  // (work: the job's tool alone, what it wears kept; carrying: the load, or hands free to push)
                let tool = if carrying: vx_load_gear(u.body, vx_carried) else: vx_tool_for(vx_body_of(u.body), VX_JOB_TOOL[m])
                let tools = if tool != "": [ tool ] else: []::string
                for(u.gear) g: if vx_worn_gear(g): tools.push(g)
                wu = vx_unit_def { u.label, u.body, u.skin, u.pale, u.mark, tools, u.mount, u.fused, u.coat, u.mane, u.coat_mark, u.crew }
            let hull = vx_body_of(wu.body).hull
            if hull != "" and m != VX_DIE:  // (its parts are baked apart and stacked on it; it falls whole)
                wu = copy(wu)
                wu.body = hull
            vx_fall_t = if m == VX_DIE: float(pose.y + 1) / float(VX_STEPS[VX_DIE]) else: 0.0
            var parts = vx_unit_prims(wu, if m == VX_DIE: 0.0 else: float(pose.y) * 45.0)
            vx_fall_t = 0.0
            if m == VX_DIE:
                parts = vx_dying(u, parts, float(pose.y + 1) / float(VX_STEPS[VX_DIE]))
            vx_act = ""
            vx_stand = false
            vx_carried = ""
            j.filling = vx_fill_begin(parts, vx_size_of(u), vx_on_zero(u, m == VX_DIE))
    return false

// A job done: its atlas made a sheet and its frames published; kept in the cache by vx_save (in play, a frame of its
// own: writing the PNG is most of a frame's time).
let vx_unsaved = []::vx_job

def vx_finish(j:vx_job):
    let h = j.rows.length
    assert h <= 4096
    let tex = gl.create_texture(j.rows, VX_FORMATS)
    add_sheet(tex, float2 { float(VX_ATLAS), float(h) })
    j.lines.insert(0, "{VX_ATLAS} {h}")
    vx_publish(j.lk, j.v, j.lines)
    j.tex = tex

def vx_save(j:vx_job):
    let tex = j.tex
    if bake_cache_dir != "" and tex:
        if not gl.save_texture(tex, j.stem + ".png", false):  // (the engine's writer; GLES has none: ours, slower)
            let rgba = []::int
            for(j.rows) row: for(row) c: for(4) ch: rgba.push(clamp(int(c[ch] * 255.0 + 0.5), 0, 255))
            write_file(j.stem + ".png", png_bytes(rgba, VX_ATLAS, j.rows.length))
        write_file(j.stem + ".txt", concat_string(j.lines, "\n") + "\n")
    j.rows = []::[float4]
    j.tex = nil

// ---- what to bake, and when

// The modes a look's first bake has (what its units do from the start), and the rest.
def vx_piece(lk:int) -> bool: return vx_body_of(vx_lks[lk].u.body).piece and vx_body_of(vx_lks[lk].u.body).hull == ""  // (a part: only its turning)
def vx_first_modes(lk:int) -> [int]:
    if vx_piece(lk): return [ VX_IDLE ]
    return if vx_lks[lk].worker: [ VX_IDLE, VX_WALK, VX_WORK ] else: [ VX_IDLE, VX_WALK ]
def vx_moving_modes(lk:int) -> [int]: return if vx_lks[lk].worker: [ VX_WALK, VX_WORK ] else: [ VX_WALK ]
def vx_later_modes(lk:int) -> [[int]]:  // (a job a mode: small atlases, short saves; a worker's jobs first)
    if vx_piece(lk): return []
    let ms = [ [ VX_ATTACK ], [ VX_DIE ] ]
    if vx_lks[lk].worker:  // (a job a mode: a mounted worker's jobs together overflow an atlas)
        for([ VX_BUILD, VX_MINE, VX_FORAGE, VX_CARRY, VX_CARRY + 1, VX_CARRY + 2, VX_CARRY + 3 ]) m, at: ms.insert(at, [ m ])
    return ms
def vx_all_modes(lk:int) -> [[int]]:
    if vx_piece(lk): return [ [ VX_IDLE ] ]
    let ms = [ [ VX_IDLE, VX_WALK ], [ VX_ATTACK ], [ VX_DIE ] ]
    if vx_lks[lk].worker:
        for([ VX_WORK, VX_BUILD, VX_MINE, VX_FORAGE, VX_CARRY, VX_CARRY + 1, VX_CARRY + 2, VX_CARRY + 3 ]) m, at: ms.insert(at + 1, [ m ])
    return ms

// A job loaded from the cache, or else queued (at the front, or the back).
def vx_queue_job(j:vx_job, front:bool):
    if vx_load_job(j): return
    if front: vx_queue.insert(0, j)
    else: vx_queue.push(j)

// A look wanted now (a figure on a page, a step aged into): standing first, at the front (one pose: it shows in a
// moment), then walking (and working) and the rest at the back.
def vx_plan(lk:int, front:bool) -> void:
    if vx_lks[lk].planned: return
    vx_lks[lk].planned = true
    for(vx_lks[lk].pieces) plk: vx_plan(plk, front)
    if vx_piece(lk):
        vx_queue_job(vx_new_job(lk, 0, [ VX_IDLE ]), front)
        return
    vx_queue_job(vx_new_job(lk, 0, vx_moving_modes(lk)), front)
    vx_queue_job(vx_new_job(lk, 0, [ VX_IDLE ]), front)  // (in front of its walk)
    for(vx_later_modes(lk)) ms: vx_queue_job(vx_new_job(lk, 0, ms), false)
    for(vx_looks_of(vx_lks[lk].u) - 1) v: for(vx_all_modes(lk)) ms: vx_queue_job(vx_new_job(lk, v + 1, ms), false)

def vx_ready(lk:int) -> bool: return vx_frames.get(vx_fkey(lk, 0, VX_IDLE, 0, 0), -1) >= 0

// A look wanted now: its first bake to the front of the queue.
def vx_want(lk:int):
    vx_lks[lk].waited_for = true
    if not vx_lks[lk].planned:
        vx_plan(lk, true)
        return
    let d = vx_doing
    if d and d.lk == lk and d.v == 0: return
    let i = find(vx_queue) j: j.lk == lk and vx_first_job(j)
    if i > 0:
        let j = vx_queue[i]
        vx_queue.remove(i)
        vx_queue.insert(0, j)

// A unit on the field and its look has no frame at all: standing, baked now (a tenth of a second, once a look), the walk
// to the front of the queue. A moment's hitch beats a health bar over nothing (#170).
def vx_stand_now(lk:int):
    vx_want(lk)
    let first = []::vx_job
    vx_take_first(lk, first)
    let stand = vx_new_job(lk, 0, [ VX_IDLE ])
    for(first) j: if j.modes[0] != VX_IDLE or j.at > 0: vx_queue.insert(0, j)  // (one already under way goes on in turn)
    if (find(first) j: j.modes[0] == VX_IDLE and j.modes.length > 1 and j.at == 0) >= 0: vx_queue.insert(0, vx_new_job(lk, 0, vx_moving_modes(lk)))
    if vx_load_job(stand): return
    while not vx_job_step(stand, seconds_elapsed() + 1.0): pass()
    vx_unsaved.push(stand)

// A mount must name a part its body has, with a muzzle to fire from (a mount with no part is a gun on the hull).
def vx_check_mounts(k:int, lk:int):
    let b = vx_body_of(vx_lks[lk].u.body)
    for(t_mounts[k]) m:
        if m.part != "":
            let p = find(b.parts) q: q.name == m.part
            if p < 0: print "body {b.id}: a mount names part {m.part}, which it doesn\'t have"
            assert p >= 0
            let has_muzzle = has_s(b.parts[p].point_names, "muzzle")
            if not has_muzzle: print "body {b.id}: part {m.part} has a gun and no muzzle point"
            assert has_muzzle

// Every type's looks, at the start (and again when a race changes mid-match): what each player fields in the age
// it's in, baked now in their first look (counted on the match loader); then queued: their attacks and falls,
// their other looks, and the later ages' steps, the next age first.
// The data (the game's and each active mod's data/voxel/) and the cache key's code part, once.
def vx_init():
    if vx_source != "": return
    let dirs = map(lib_packs) p: p.root + "/voxel"  // (a mod's own rules come after the game's)
    vx_load(dirs)
    vx_source = sha256_text((read_file("view/voxel.lobster") or "") + vx_data_text())
    vx_mat_cols[vx_mat_team] = float3 { 0.85, 0.12, 0.85 }  // (the sprite shader's team key)

// A look's first bakes (standing, walking, working) taken out of the queue (and the one being baked), to be finished
// now.
def vx_first_job(j:vx_job) -> bool: return j.v == 0 and (j.modes[0] == VX_IDLE or j.modes[0] == VX_WALK)
def vx_take_first(lk:int, out:[vx_job]) -> void:
    for(vx_lks[lk].pieces) plk: vx_take_first(plk, out)
    let d = vx_doing
    if d and d.lk == lk and vx_first_job(d):
        vx_doing = nil
        out.push(d)
    for(filter(vx_queue) j: j.lk == lk and vx_first_job(j)) j: out.push(j)
    vx_queue = filter(vx_queue) j: not (j.lk == lk and vx_first_job(j))

var vx_all_fielded = false  // every unit is on the field from the start (a staged battle): each type is baked first as it is now
var vx_start_now = false    // the start's first looks in every mode are baked before the match shows, not queued

// The line step a type is drawn in (as retype picks it): the recipe its units look like now.
def type_step(k:int) -> int:
    let p = t_player[k]
    if p < 0 or p >= num_players: return 0
    let line = lines[k]
    var step = 0
    for(line) l, n:
        if l.age <= ages[p] and (l.age == line[0].age or t_worker[k] or t_hero[k] or upgraded_line(p, l)): step = n
    return step

def vx_start():
    let t0 = seconds_elapsed()
    vx_init()
    let by_age = []::[int]  // looks by how many ages ahead they are first fielded
    vx_type_lks = []::[int]
    vx_cur = []::int
    for(t_slot.length) k:
        let line = glist(su_units[k], "line")
        let lks = []::int
        for(max(1, line.length)) s:
            let r = if s < line.length: at(line[s], "look") else: at(su_units[k], "look")
            if not vx_engine_made(r):
                lks.push(-1)
                continue
            let lk = vx_look_for(r)
            vx_check_mounts(k, lk)
            lks.push(lk)
            let age = if line.length: as_int(at(line[s], "age")) else: t_age[k]
            let ahead = if vx_all_fielded and s == type_step(k): 0 else: max(0, age - (if t_player[k] >= 0 and t_player[k] < ages.length: ages[t_player[k]] else: 1))  // (all fielded: each type as it is now)
            while by_age.length <= ahead: by_age.push([])
            if (find(by_age[ahead]) x: x == lk) < 0: by_age[ahead].push(lk)
            for(vx_lks[lk].pieces) plk:
                if (find(by_age[ahead]) x: x == plk) < 0: by_age[ahead].push(plk)
        vx_type_lks.push(lks)
        vx_cur.push(lks[0])
    let now = []::vx_job
    for(by_age) lks, a:
        for(lks) lk:
            if a == 0 and vx_lks[lk].planned: vx_take_first(lk, now)  // (asked for on a lobby page, not all baked yet)
            if not vx_lks[lk].planned:
                vx_lks[lk].planned = true
                let first = vx_new_job(lk, 0, vx_first_modes(lk))
                if not vx_load_job(first): (if a == 0: now else: vx_queue).push(first)
                for(vx_later_modes(lk)) ms: vx_queue_job(vx_new_job(lk, 0, ms), false)
        for(lks) lk: for(vx_looks_of(vx_lks[lk].u) - 1) v: for(vx_all_modes(lk)) ms: vx_queue_job(vx_new_job(lk, v + 1, ms), false)
    if (perf_for > 0.0 and not perf_live) or vx_start_now:  // (perf: measures the drawing, not a new race's one-off bakes; an army: the
        // fight comes at once: the start's first looks in every mode now, the rest left queued)
        let start = if by_age.length: by_age[0] else: []::int
        def ahead_now(j:vx_job) -> bool: return j.v == 0 and (find(start) lk: lk == j.lk) >= 0  // (first looks: the others draw as them)
        for(filter(vx_queue) j: ahead_now(j)) j: now.push(j)
        vx_queue = filter(vx_queue) j: not ahead_now(j)
    bake_total = now.length
    bake_count = 0
    for(now) j:
        while not vx_job_step(j, seconds_elapsed() + 0.05): bake_breath()
        vx_save(j)
        bake_count++
        bake_breath()
    bake_total = 0
    vx_refresh()
    print "voxel units: {vx_lks.length} looks, {now.length} baked now, {vx_queue.length} queued, in {int((seconds_elapsed() - t0) * 1000.0)} ms"

// Each type's look as drawn now: its line step's (type_step), once that's baked (asked for first until then).
var vx_type_gen = -1
def vx_refresh():
    if vx_type_gen != type_gen and vx_type_gen >= 0:  // (a race changed mid-match: its new steps' looks)
        for(t_slot.length) k:
            let line = glist(su_units[k], "line")
            for(max(1, line.length)) s:
                let r = if s < line.length: at(line[s], "look") else: at(su_units[k], "look")
                if s < vx_type_lks[k].length: vx_type_lks[k][s] = if vx_engine_made(r): vx_look_for(r) else: -1
    vx_type_gen = type_gen
    for(vx_cur) cur, k:
        let lks = vx_type_lks[k]
        let lk = lks[min(type_step(k), lks.length - 1)]
        if lk < 0: vx_cur[k] = -1
        elif lk != cur:
            if vx_ready(lk) or cur < 0: vx_cur[k] = lk
            else: vx_want(lk)

// In play: each type's look, then the queue baked on for up to `budget` seconds of this frame.
def vx_tick(budget:float, calm:bool):
    vx_refresh()
    vx_bake_tick(budget, calm)

// The queue baked on for up to `budget` seconds of this frame (in play, and on the lobby's pages). Not calm (a fight, a
// huge match): only a look a unit is waiting for, and no saves: a cell runs to 20 ms, a PNG to 180 ms, and they'd be seen.
def vx_bake_tick(budget:float, calm:bool = true):
    if perf_for > 0.0 and not perf_live: return  // (a perf run measures the drawing alone; perflive, the bakes too)
    if calm and vx_unsaved.length:
        vx_save(vx_unsaved.pop())
        return
    let until = seconds_elapsed() + budget
    while seconds_elapsed() < until:
        var d = vx_doing
        if not d:
            if not vx_queue.length: return
            if not calm and not vx_lks[vx_queue[0].lk].waited_for: return
            d = vx_queue[0]
            vx_queue.remove(0)
            vx_doing = d
        if vx_job_step(d, until):
            vx_doing = nil
            vx_unsaved.push(d)
            return

// ---- drawing

let vx_walked = dictionary<int, float>(1024)  // unit id -> milli-tiles walked
let vx_last = dictionary<int, float2>(1024)   // unit id -> where it was last drawn

def vx_walk_step(id:int, k:int, x:float, y:float) -> int:
    let at = float2 { x, y }
    let was = vx_last.get(id, at)
    vx_last.set(id, at)
    let walked = vx_walked.get(id, 0.0) + magnitude(at - was)
    vx_walked.set(id, walked)
    return int(walked / vx_lks[vx_cur[k]].cycle * 8.0) % 8

// A unit's look (from its id: view only).
def vx_look_v(id:int, lk:int) -> int: return ((id * 2654435761) >> 13 & 1023) % vx_looks_of(vx_lks[lk].u)

// A look's frame in mode m, facing f, at step st, in look v; its first look's (or standing) until that's baked.
def vx_frame(lk:int, v:int, m:int, f:int, st:int) -> int:
    var fr = vx_frames.get(vx_fkey(lk, v, m, f, st), -1)
    if fr < 0: fr = vx_frames.get(vx_fkey(lk, 0, m, f, st), -1)
    if fr < 0 and m >= VX_BUILD: return vx_frame(lk, v, if m >= VX_CARRY: VX_WALK else: VX_WORK, f, st)  // (a job not baked yet)
    if fr < 0 and m != VX_DIE: fr = vx_frames.get(vx_fkey(lk, v, VX_IDLE, f, 0), -1)
    if fr < 0 and m != VX_DIE: fr = vx_frames.get(vx_fkey(lk, 0, VX_IDLE, f, 0), -1)
    return fr

// unit_state's name -> a mode: each worker's job its own (its tool), carrying home the barrow.
def vx_mode_of(state:string) -> int:
    if state == "attack": return VX_ATTACK
    if state == "walk": return VX_WALK
    if find_string(state, "carry_") == 0:  // (a resource with no load of its own: its hands empty, the first)
        let res = state.substring(6, state.length - 6)
        return VX_CARRY + max(0, find(VX_LOADS) l: l == res)
    if state == "work_build": return VX_BUILD
    if state == "work_mine": return VX_MINE
    if state == "work_forage": return VX_FORAGE
    if find_string(state, "work") == 0: return VX_WORK
    return VX_IDLE

// The frame for unit id of type k in state (unit_state's names), moving or facing screen direction d (dir_of's).
def vx_frame_for(id:int, k:int, state:string, d:int, n:int) -> int:
    let lk = vx_cur[k]
    let f = (d + 2) % 8  // (facing 2 faces screen right)
    let m = vx_mode_of(state)
    let st = if m == VX_IDLE: n % 4 elif m == VX_ATTACK: min(n, 7) else: n % 8
    let fr = vx_frame(lk, vx_look_v(id, lk), m, f, st)
    if fr >= 0: return fr
    vx_stand_now(lk)  // (drawn before it's baked: a unit of a later age put down)
    return vx_frame(lk, 0, VX_IDLE, f, 0)

// Does type k hold a gun up to aim? (Its look now.)
def vx_kind_aims(k:int) -> bool: return vx_drawn(k) and vx_aiming(vx_lks[vx_cur[k]].u)

// A part's frame in facing f (asked for if it isn't baked yet), or -1.
def vx_piece_frame(plk:int, f:int) -> int:
    let fr = vx_frames.get(vx_fkey(plk, 0, VX_IDLE, f, 0), -1)
    if fr < 0: vx_want(plk)
    return fr

// A dead unit's frame, t seconds after it fell: its fall, then lying.
def vx_dead_frame(id:int, k:int, d:int, t:float) -> int:
    let lk = vx_cur[k]
    return vx_frame(lk, vx_look_v(id, lk), VX_DIE, (d + 2) % 8, min(int(t * 10.0), VX_STEPS[VX_DIE] - 1))

// A voxel unit's frame's shadow on the ground (drawn under every unit), or -1.
def vx_shadow_for(f:int) -> int: return vx_shadow_of.get(f, -1)

// A recipe's figure (the panel's portraits, the tech tree's), standing facing down and to the right: its frame
// once baked (asked for first until then), or -1.
def vx_figure(recipe:JV) -> int: return vx_figure_facing(recipe, float2_1)

// The same, facing screen direction `to` (a canvas vector: the lobby's armies face each other).
def vx_figure_facing(recipe:JV, to:float2) -> int:
    vx_init()
    if not vx_engine_made(recipe): return -1
    let lk = vx_look_for(recipe)
    if not vx_ready(lk):
        vx_want(lk)
        return -1
    return vx_frame(lk, 0, VX_IDLE, (dir_of(to) + 2) % 8, 0)
