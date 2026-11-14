// ------------------------------------------------------------------ drawing the world
// Units (voxel bodies and their parts), wrecks and corpses, buildings with their walls, gates and ruins, doodads and
// props, into the draw list, sorted and drawn by draw_world(alpha) with the fog and the effects.
// What the game adds comes through functions it defines (examples/plain/src/hooks/view.lobster lists them, doing
// nothing): its building looks' tile names, its paths, its town life, cracks on damaged buildings.

// Where something stands on the canvas (Iso.to_ground: raised ground lifts it).
def ground_at(x:int, y:int) -> float2: return canvas(float(x), float(y)) - float2 { 0.0, lift_at(float(x), float(y)) }

def seen_at(x:int, y:int) -> bool: return reveal or fog[ME][cell_of(x, y)] == 2

// Combat's effects: a spark where a blow lands, a miss standing in the ground, a healed unit's glow, a stone's
// splash, a fallen building's dust (game/fx.lobster).
def fx_events():
    for(events) e:
        if e.kind == EV_HIT and seen_at(e.x, e.y):
            let i = index_of(e.a)
            if i >= 0:
                let look = shot_style(unit_shotk.get(u_kind[i], "arrow")).hit
                let j = index_of(e.b)
                let to = if j >= 0: ground_at(u_x[j], u_y[j]) - float2 { 0.0, 10.0 + air_lift(u_kind[j]) / 1.5 } else: ground_at(e.x, e.y) - float2 { 0.0, 20.0 }
                if not t_ranged[u_kind[i]]: fx_spark(to, e.c >= 8)
                elif look.sparks > 0: fx_hit(to, look)
                if t_ranged[u_kind[i]]: fx_impact(shot_style(unit_shotk.get(u_kind[i], "arrow")), to, false)
        elif e.kind == EV_MISS:
            if seen_at(e.x, e.y):
                let i = index_of(e.a)
                fx_stick(ground_at(e.x, e.y), if i >= 0: unit_shotk.get(u_kind[i], "arrow") else: "arrow")
                if i >= 0:
                    let look = shot_style(unit_shotk.get(u_kind[i], "arrow")).hit
                    if look.sparks > 0: fx_hit(ground_at(e.x, e.y), look)
                    fx_impact(shot_style(unit_shotk.get(u_kind[i], "arrow")), ground_at(e.x, e.y), true)
        elif e.kind == EV_HEAL:
            if index_of(e.b) >= 0: fx_heal(e.b)
        elif e.kind == EV_SPLASH:
            if seen_at(e.x, e.y): fx_splash(ground_at(e.x, e.y), float(e.c) * RADIUS_PX)
        elif e.kind == EV_DIE and e.b == 1:
            if fog[ME][cell_of(e.x, e.y)] != 0: building_fell(e)

let AIM_HOLD_S = 1.0  // how long after its next shot was due a gun stays up

def unit_state(i:int, moving:bool) -> string, int:
    let k = u_kind[i]
    let t0 = attack_t0.get(u_id[i], -10.0)
    if clock_s - t0 < 0.5 and not (t_mounts[k].length and moving): return "attack", int((clock_s - t0) * 16.0)                              // (a turret fires as it drives: its tracks run on)
    if clock_s - t0 < float(t_reload[k]) / 20.0 + AIM_HOLD_S and vx_between_shots(vx_kind_aims(k), moving) == "attack": return "attack", 7  // (a gun stays up between shots, #261)
    let res = if u_carry_kind[i] > 0: resource_names[u_carry_kind[i] - 1] else: ""
    let phase = int(clock_s * 8.0) + u_id[i]
    if moving:
        if t_worker[k] and u_task[i] == T_RETURN and u_carry[i] > 0: return "carry_" + res, phase % 16
        return "walk", phase % 16
    if u_task[i] == GATHER and t_worker[k]:
        let job = if res == "wood": "chop" elif res == "stone" or res == "gold": "mine" else: "forage"
        return "work_" + job, phase % 8
    if u_task[i] == BUILD and t_worker[k]: return "work_build", phase % 8
    return "idle", phase / 6  // (a slow shift of weight, each unit in its own time)

def visible_to_me(c:int) -> bool: return reveal or fog[ME][c] == 2

// How far up a unit type is drawn off the ground, world px: an aircraft's flying height; else 0.
def air_lift(k:int) -> float:
    if t_air[k] == 0 or not vx_drawn(k): return 0.0
    let b = vx_body_of(vx_lks[vx_cur[k]].u.body)
    return b.flies * cos(vx_ELEV) * vx_RES * b.size * VX_DRAW_K

// A click on an aircraft where it's drawn must take it, and one on the ground under it must not. (One standing clear:
// an army starts packed, and a click can fairly land on a neighbour.)
def air_test() -> bool:
    if tick < 40: return false
    let planes = filter(u_x.length) n: u_owner[n] == ME and t_air[u_kind[n]] != 0
    assert planes.length
    var i = -1
    for(planes) p:
        let at = iso(float(u_x[p]), float(u_y[p]))
        if unit_at_screen(to_screen(at - float2 { 0.0, air_lift(u_kind[p]) + 14.0 }), true) == p and unit_at_screen(to_screen(at), true) != p: i = p
    if i < 0: print "airtest: no plane of {planes.length} takes the click"
    assert i >= 0
    let ground = iso(float(u_x[i]), float(u_y[i]))
    let lift = air_lift(u_kind[i])
    let drawn = unit_at_screen(to_screen(ground - float2 { 0.0, lift + 14.0 }), true)
    let under = unit_at_screen(to_screen(ground), true)
    print "airtest: lift {lift} px; a click on the plane takes {drawn} (the plane is {i}), a click under it takes {under}"
    assert drawn == i
    assert under != i
    print "airtest: ok"
    return true

// What the units on screen sound like this frame (game/audio.lobster): a count for each sound.
def unit_loops_tick(dt:float):
    let counts = dictionary<string, int>(8)
    def hear(name:string):
        if name != "": counts.set(name, counts.get(name, 0) + 1)
    for(u_x.length) i:
        let k = u_kind[i]
        if vx_drawn(k) and on_screen(u_x[i], u_y[i]) and visible_to_me(cell_of(u_x[i], u_y[i])):
            let body = vx_lks[vx_cur[k]].u.body
            hear(unit_sound(body, if u_moving[i] != 0: 1 else: 0))
            if t_mounts[k].length:
                var aims = 0  // (any gun turning)
                for(u_mount[i]) v, n:
                    if n % MOUNT_STRIDE == MOUNT_AIM: aims = aims * 3601 + v
                if last_aim.get(u_id[i], aims) != aims: aim_moved.set(u_id[i], clock_s)  // (it changes by the tick; this runs by the frame)
                last_aim.set(u_id[i], aims)
                if clock_s - aim_moved.get(u_id[i], -10.0) < 0.2: hear(unit_sound(body, 2))
    for(counts.get_keys()) name: unit_loop_hear(name, counts.get(name, 0))
    unit_loops_fade(dt)

// Where an effect on unit id rises from (a heal's motes, which have their own heights): its feet on the ground
// (canvas units); far off when it's gone or unseen.
def unit_anchor(id:int) -> float2:
    let i = index_of(id)
    if i < 0 or not on_screen(u_x[i], u_y[i]): return float2 { -1000000000.0, 0.0 }
    let x = float(u_x[i])
    let y = float(u_y[i])
    return canvas(x, y) - float2 { 0.0, lift_at(x, y) }

// The facing of a unit's part: a mount's turret its own aim, anything else the hull's.
def part_facing(i:int, name:string, hull_f:int) -> int:
    for(t_mounts[u_kind[i]]) m, n:
        if m.part == name and u_mount[i].length > n * MOUNT_STRIDE:
            let aim = float(u_mount[i][n * MOUNT_STRIDE + MOUNT_AIM]) / 10.0
            let d = dir_of(iso(cos(aim), sin(aim)))
            return if d >= 0: (d + 2) % 8 else: hull_f
    return hull_f

// Where a shot leaves a unit: canvas px up from its ground point to its body's muzzle, as it stands now; else a little up
// from its feet.
def muzzle_of(by:int, mount:int) -> float2:
    let i = index_of(by)
    if i >= 0 and vx_drawn(u_kind[i]):
        let b = vx_body_of(vx_lks[vx_cur[u_kind[i]]].u.body)
        let hull_f = (unit_dir.get(by, 2) + 2) % 8
        let ms = t_mounts[u_kind[i]]
        let part = if mount < ms.length: ms[mount].part else: ""
        let o, found = vx_point_px(b, "muzzle", part, hull_f, part_facing(i, part, hull_f))
        if found: return o * VX_DRAW_K / 1.5
    return float2 { 0.0, -12.0 }

// How far a part is kicked back from a shot just fired, drawn px along its facing.
def kick_of(key:int, b:vx_body_spec, f:int) -> float2:
    let k = unit_kick.get(key, float2_0)
    let age = clock_s - k.y
    if k.x <= 0.0 or age >= 0.25: return float2_0
    return -normalize(vx_spot_px(b, float3 { 0.0, 1.0, 0.0 }, f)) * k.x * 1.5 * (1.0 - age / 0.25)

// A unit's parts on its hull (a turret, at its gun's aim; anything else over the hull), each sorted just above it. The
// offset is whole pixels from the hull's own, so the two never shimmer apart as it moves.
def add_parts(i:int, hull_f:int, x:float, y:float, sort_y:float, col:float4):
    let k = u_kind[i]
    let lk = vx_cur[k]
    let pieces = vx_lks[lk].pieces
    if not pieces.length: return
    let b = vx_body_of(vx_lks[lk].u.body)
    for(pieces) plk, n:
        let f = part_facing(i, b.parts[n].name, hull_f)
        let pf = vx_piece_frame(plk, f)
        let o = vx_pivot_px(b, b.parts[n], hull_f) * VX_DRAW_K
        let mount = find(t_mounts[k]) m: m.part == b.parts[n].name
        let kick = if mount >= 0: kick_of(u_id[i] * 16 + mount, b, f) else: float2_0
        let px, py = floor(x) + floor(o.x + kick.x + 0.5), floor(y) + floor(o.y + kick.y + 0.5)
        add(pf, px, py, sort_y + 0.01 * float(n + 1), col)
        if pf >= 0:
            let sf = vx_shadow_for(pf)
            if sf >= 0: add(sf, px, py, sort_y - 0.5, float4 { 1.0, 1.0, 1.0, 1.0 })

def collect_units(alpha:float):
    perf_unseen = 0
    for(u_x.length) i:
        let px, py = prev_pos(i)
        let x = px + (u_x[i] - px) * alpha
        let y = py + (u_y[i] - py) * alpha
        let mine = teams[u_owner[i]] == teams[ME]
        if (mine or visible_to_me(cell_of(u_x[i], u_y[i]))) and vx_drawn(u_kind[i]):
            let moving, walking_d = unit_walk(i, unit_dir.get(u_id[i], 2), px, py)
            var d = walking_d
            if moving: pass()
            elif u_foe[i] != 0 and not t_mounts[u_kind[i]].length:  // (a mounted hull doesn't turn to its foe: its guns do)
                let j = index_of(u_foe[i])
                var tx = -1.0
                var ty = -1.0
                if j >= 0:
                    tx = float(u_x[j])
                    ty = float(u_y[j])
                else:
                    let b = b_index_of(u_foe[i])
                    if b >= 0:
                        tx = float(b_cx[b] * 1000 + b_sx[b] * 500)
                        ty = float(b_cy[b] * 1000 + b_sy[b] * 500)
                if tx >= 0.0:
                    let nd = dir_of(iso(tx - x, ty - y))
                    if nd >= 0: d = nd
            elif (u_task[i] == GATHER or u_task[i] == BUILD) and u_target[i] >= 0:
                var tx = 0.0
                var ty = 0.0
                if u_task[i] == GATHER:
                    tx = float((u_target[i] % W) * 1000 + 500)
                    ty = float((u_target[i] / W) * 1000 + 500)
                else:
                    let b = b_index_of(u_target[i])
                    if b >= 0:
                        tx = float(b_cx[b] * 1000 + b_sx[b] * 500)
                        ty = float(b_cy[b] * 1000 + b_sy[b] * 500)
                let nd = dir_of(iso(tx - x, ty - y))
                if nd >= 0: d = nd
            unit_dir.set(u_id[i], d)
            last_kind.set(u_id[i], u_kind[i])
            last_owner.set(u_id[i], u_owner[i])
            let state, n0 = unit_state(i, moving)
            // (voxel units step by the ground they cover, so the planted foot doesn't slide)
            let n = if state == "walk" or find_string(state, "carry") == 0: vx_walk_step(u_id[i], u_kind[i], x, y) else: n0
            let f = vx_frame_for(u_id[i], u_kind[i], state, d, n)
            if f < 0: perf_unseen++
            let p = iso(x, y)
            let tc = team_col(u_owner[i])
            let since = clock_s - hit_t0.get(u_id[i], -10.0)
            let flash = if since < 0.12: 1.0 + 1.8 * (1.0 - since / 0.12) else: 1.0
            let up = lift_at(x, y) * 1.5  // standing on the hill (canvas px; iso is 1.5x), as the views do
            add(f, p.x, p.y - up, p.y, float4 { tc.x, tc.y, tc.z, flash })
            if f >= 0:                     // its shadow on the ground, sorted just under it: in the ground layer a hill's
                let sf = vx_shadow_for(f)  // near edge (draw_occluder) was painted over it under the feet, and it floated
                if sf >= 0: add(sf, p.x, p.y - up, p.y - 0.5, float4 { 1.0, 1.0, 1.0, 1.0 })
                add_parts(i, (d + 2) % 8, p.x, p.y - up, p.y, float4 { tc.x, tc.y, tc.z, flash })

// Is this the wreck of a vehicle that stays where it stood (a body's "death": "knocked_out")?
def is_wreck(c:Corpse) -> bool: return c.kind >= 0 and vx_drawn(c.kind) and vx_body_of(vx_lks[vx_cur[c.kind]].u.body).death == "knocked_out"

let WRECK_BURNS = 5.0   // a wreck burns this long...
let WRECK_STAYS = 16.0  // ...lies there this long in all...
let WRECK_FADE = 4.0    // ...and fades away

// A wreck: where it stood, burning then smoking, then fading.
def collect_wreck(c:Corpse):
    let t = clock_s - c.t0
    let p = iso(c.x, c.y)
    let up = lift_at(c.x, c.y) * 1.5
    let fade = clamp(1.0 - (t - WRECK_STAYS) / WRECK_FADE, 0.0, 1.0)
    let f = vx_dead_frame(c.id, c.kind, c.dir, t)
    let tc = team_col(c.owner)
    add(f, p.x, p.y - up, p.y - 2.0, float4 { tc.x, tc.y, tc.z, fade })
    if f >= 0: add(vx_shadow_for(f), p.x, p.y - up, p.y - 2.5, float4 { 1.0, 1.0, 1.0, fade })
    let at = canvas(c.x, c.y) - float2 { 0.0, lift_at(c.x, c.y) + 18.0 }
    if t < WRECK_BURNS and rnd_float() < 0.2: fx_flame(at)
    if t < WRECK_STAYS and rnd_float() < (if t < WRECK_BURNS: 0.18 else: 0.06): fx_smoke(at, 1, 3.0)

def collect_corpses():
    corpses = filter(corpses) c: clock_s - c.t0 < (if is_wreck(c): WRECK_STAYS + WRECK_FADE else: 4.0)
    for(corpses) c:
        if is_wreck(c):
            collect_wreck(c)
            continue
        if c.kind >= 0 and vx_drawn(c.kind):  // (a unit falls, lies, goes in a puff of dust and fades)
            let t = clock_s - c.t0
            let f = vx_dead_frame(c.id, c.kind, c.dir, t)
            let p = iso(c.x, c.y)
            let up = lift_at(c.x, c.y) * 1.5
            if t >= 1.9 and not c.puffed:
                c.puffed = true
                fx_puff(canvas(c.x, c.y) - float2 { 0.0, lift_at(c.x, c.y) }, 0.0)
            let fade = clamp(1.0 - (t - 2.2) / 1.8, 0.0, 1.0)
            let tc = team_col(c.owner)
            add(f, p.x, p.y - up, p.y - 2.0, float4 { tc.x, tc.y, tc.z, 0.35 + 0.65 * fade })
            if f >= 0: add(vx_shadow_for(f), p.x, p.y - up, p.y - 2.5, float4 { 1.0, 1.0, 1.0, fade })

// Models.LINKS: a wall tile's eight neighbours, in its arms' order.
let LINKS = [ int2 { 1, 0 }, int2 { 1, 1 }, int2 { 0, 1 }, int2 { -1, 1 }, int2 { -1, 0 }, int2 { -1, -1 }, int2 { 0, -1 }, int2 { 1, -1 } ]

let GATE_DEPTH_PX = 40.0  // art px: half an open gate's depth on the screen (a unit within it is in the archway)

// Is one of a gate's team's units on it or about to pass it (within a tile and a half of its middle)?
def gate_used(b:int) -> bool:
    let cx = b_cx[b] * 1000 + b_sx[b] * 500
    let cy = b_cy[b] * 1000 + b_sy[b] * 500
    let reach = 1500 + max(b_sx[b], b_sy[b]) * 500
    for(u_x.length) i:
        if teams[u_owner[i]] == teams[b_owner[b]] and abs(u_x[i] - cx) < reach and abs(u_y[i] - cy) < reach: return true
    return false

def wall_like(b:int) -> bool:
    let k = b_kind[b]
    return bt_line[k] != 0 or bt_gate[k] != 0 or (k < su_btypes.length and gbool(su_btypes[k], "joins", false))

// Which neighbours a finished wall tile's arms reach (BuildingArt.links_of): every finished wall,
// gate or tower beside it, and corner to corner only where no wall beside both closes the corner.
def wall_links(b:int) -> int:
    def on(d:int2) -> bool:
        let x = b_cx[b] + d.x
        let y = b_cy[b] + d.y
        if x < 0 or y < 0 or x >= W or y >= H: return false
        let o = b_index_of(occupied[y * W + x])
        return o >= 0 and o != b and b_done[o] == 1 and wall_like(o)
    var out = 0
    for(LINKS) d, k:
        if on(d) and not (d.x != 0 and d.y != 0 and (on(int2 { d.x, 0 }) or on(int2 { 0, d.y }))): out |= 1 << k
    return out

// Each building as last drawn, by id: what it leaves when it falls (its ruin, game/fx.lobster), as BuildingArt
// still has it when the sim's building is gone.
class BldSeen:
    look:Look
    at:float2
    sort_y:float
    flat:bool
    owner:int
    cells:int4
    damage:float

var bld_seen = dictionary<int, BldSeen>(256)
let RUIN_AT = [ 0.3, 0.55, 0.8 ]  // damage at which a building shows its battered, breaking and collapsed stages (D-171)

// A finished building's damage (0 whole .. 1 nearly down).
def damage_of(b:int) -> float:
    let full = bm_hp[b_owner[b]][b_kind[b]]
    return if full > 0: 1.0 - float(b_hp[b]) / float(full) else: 0.0

// A fallen building: its ruin where it stood, if it has one baked (walls and gates just go), and its dust.
def building_fell(e:Event):
    let s = bld_seen.get(e.a)
    if s and s.look.ruins.length >= 4:
        let burning = if s.damage >= DAMAGE_FIRE: min(3, 1 + int((s.damage - DAMAGE_FIRE) / (1.0 - DAMAGE_FIRE) * 3.0)) else: 0
        fx_ruins.push(RuinFx { s.look.ruins[3], s.look.body, e.a, s.at, s.sort_y, s.flat, s.owner, s.cells, burning, clock_s })
    fx_collapse(ground_at(e.x, e.y), max(1, e.c))

// Where each building seen this frame stands drawn (its body's frame, in world px): a click anywhere on a tall
// building (a tower's top) picks it, not just on its footprint.
class BldHit:
    id:int
    lo:float2
    hi:float2
    sort_y:float

var bld_hits = []::BldHit

def collect_buildings():
    let seen = dictionary<int, BldSeen>(256)
    bld_hits = []
    for(b_id.length) b:
        let k = b_kind[b]
        let p = b_owner[b]
        let cell = b_cy[b] * W + b_cx[b]
        if fx_ruins.length: fx_clear_ruins(int4 { b_cx[b], b_cy[b], b_sx[b], b_sy[b] })  // built over a ruin (D-172)
        if teams[p] == teams[ME] or fog[ME][cell] != 0:
            let pick = (b_id[b] * 7 + b_cx[b] * 3 + b_cy[b]) % 4
            let key = building_key(arch_of[p], bt_name[k], ages[p], pick)
            let look = looks.get(key)
            if look:
                var name = look.body
                if b_done[b] == 0:
                    let st = clamp(b_progress[b] * 4 / max(1, bt_build_ticks[k]), 0, 3)
                    if look.stages[st] != "-": name = look.stages[st]
                else:  // broken up as it's damaged (BuildingArt._broken)
                    let damage = damage_of(b)
                    for(RUIN_AT) at_least, n:
                        if damage >= at_least and n < look.ruins.length: name = look.ruins[n]
                let at = iso(float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500))
                let up = lift_at(float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500)) * 1.5
                let shade = if fog[ME][cell] == 2 or teams[p] == teams[ME]: 1.0 else: 0.6
                let tc = team_col(p)
                let flat = walk_over[cell] == 1
                if b_done[b] == 1: seen.set(b_id[b], BldSeen { look, float2 { at.x, at.y - up }, at.y, flat, p, int4 { b_cx[b], b_cy[b], b_sx[b], b_sy[b] }, damage_of(b) })
                let col = float4 { tc.x, tc.y, tc.z, shade }
                // its hit box: every piece drawn for it (the body, its front, a gate's towers), so a click on a
                // tower's top picks it too (Dominic, 2026-11-04)
                var hlo = float2 { 1000000000.0, 1000000000.0 }
                var hhi = -hlo
                for(append([ name, look.front, name + ":open" ], look.towers)) piece:
                    let hf = if piece == "-": -1 else: frame_index(piece)
                    if hf >= 0:
                        let fr = frames[hf]
                        let lo = float2 { floor(at.x) - float(fr.ox) * fr.k, floor(at.y - up) - float(fr.oy) * fr.k }
                        hlo = min(hlo, lo)
                        hhi = max(hhi, lo + float2 { float(fr.w), float(fr.h) } * fr.k)
                if hhi.x > hlo.x: bld_hits.push(BldHit { b_id[b], hlo, hhi, at.y })
                if look.arms.length and b_done[b] == 1:  // a wall: the tile whole with the joins it has, its shadow on the ground
                    let links = wall_links(b)
                    let tile = akb_wall_tile(name, links)
                    if tile >= 0:
                        let tkey = akb_tile_name(name, links)
                        add(frame_index(tkey + "~shadow"), at.x, at.y - up, -100000.0 + at.y, col)
                        add(tile, at.x, at.y - up, at.y, col)
                        add(frame_index(tkey + ":front"), at.x, at.y - up, at.y + 2.0, col)
                    else:
                        // (joined corner to corner: its post turned along the run, and shrunk inside its arms)
                        let post = if (links & 0xAA) != 0 and frame_index(name + ":diag") >= 0: name + ":diag" else: name
                        // its pieces' shadows on the ground, under every wall piece (kept apart from them: drawn with a
                        // piece, a shadow fell on the neighbour's face)
                        let ground = -100000.0 + at.y
                        add(frame_index(post + "~shadow"), at.x, at.y - up, ground, col)
                        for(LINKS.length) n:
                            if (links >> n) & 1 and look.arms[n] != "-": add(frame_index(look.arms[n] + "~shadow"), at.x, at.y - up, ground, col)
                        for(2) pass:
                            if pass == 1: add(frame_index(post), at.x, at.y - up, at.y, col)
                            for(LINKS) d, n:
                                if (links >> n) & 1 and (d.x + d.y <= 0) == (pass == 0) and look.arms[n] != "-":
                                    add(frame_index(look.arms[n]), at.x, at.y - up, at.y, col)
                        if look.front != "-": add(frame_index(look.front), at.x, at.y - up, at.y + 2.0, col)
                        for(LINKS.length) n:
                            if (links >> n) & 1 and n < look.arms_front.length and look.arms_front[n] != "-":
                                add(frame_index(look.arms_front[n]), at.x, at.y - up, at.y + 2.0, col)
                else:
                    // a gate stands open while one of its team's units is at it (the sim lets them through; its open
                    // look was baked but never drawn since the port)
                    let open = bt_gate[b_kind[b]] != 0 and b_done[b] == 1 and frame_index(name + ":open") >= 0 and gate_used(b)
                    if look.towers.length and frame_index(name + ":shut:mid") >= 0 and b_done[b] == 1:
                        // a gate: its middle (its doors, or the open passage) behind a unit in its archway, each tower at
                        // its own footprint, the arch over the passage in front
                        let half = GATE_DEPTH_PX
                        let mid = name + (if open: ":open:mid" else: ":shut:mid")
                        add(frame_index(mid), at.x, at.y - up, at.y - (if open: half else: 0.0), col)
                        add(frame_index(mid + "~shadow"), at.x, at.y - up, -100000.0 + at.y, col)
                        for(look.towers) tw, n:
                            add(frame_index(tw), at.x, at.y - up, at.y + look.tower_dy[n], col)
                            add(frame_index(tw + "~shadow"), at.x, at.y - up, -100000.0 + at.y, col)
                        if open: add(frame_index(name + ":open:mid:front"), at.x, at.y - up, at.y + half + 2.0, col)
                    else:
                        add(frame_index(if open: name + ":open" else: name), at.x, at.y - up, if flat: -100000.0 + at.y else: at.y, col)
                        if look.front != "-": add(frame_index(look.front), at.x, at.y - up, at.y + 2.0, col)
    bld_seen = seen
    fx_ruins = filter(fx_ruins) r: clock_s - r.t0 < RUIN_STAYS + RUIN_FADE  // (they burn out, lie there, fade)
    for(fx_ruins) r:                                                        // the fallen buildings' ruins, fading at the end
        let f = frame_index(r.frame)
        let shade = if fog[ME][r.cells.y * W + r.cells.x] == 2 or teams[r.owner] == teams[ME]: 1.0 else: 0.6
        let tc = team_col(r.owner)
        let col = float4 { tc.x, tc.y, tc.z, shade }
        let sort_y = if r.flat: -100000.0 + r.sort_y else: r.sort_y
        let fade = ruin_fade(r, clock_s)
        if fade >= 1.0: add(f, r.at.x, r.at.y, sort_y, col)
        elif f >= 0: draws.push(Drawable { sort_y, draws.length, -5, r.at.x, r.at.y, col, [ fade, float(f) ] })  // (fading: drawn alone)

var map_name_now = "reed_meadow"

// No stones, flowers or shore reeds by resources, buildings, bridges or the starts (sim_debug._keep_clear).
def keep_clear(t:float2) -> bool:
    var y = int(t.y) - 1
    while y < int(t.y) + 2:
        var x = int(t.x) - 1
        while x < int(t.x) + 2:
            if x >= 0 and y >= 0 and x < W and y < H:
                let c = y * W + x
                if amount[c] > 0 or occupied[c] != 0: return true
                for(br_cells) cells:
                    if contains(cells, c): return true
            x++
        y++
    for(start_x) sx, n:
        let dx = t.x - float(sx) / 1000.0
        let dy = t.y - float(start_y[n]) / 1000.0
        if sqrt(dx * dx + dy * dy) < 4.0: return true
    return false

def collect_doodads():
    for(doodad_list) d:
        let c = clamp(int(d.t.y), 0, H - 1) * W + clamp(int(d.t.x), 0, W - 1)
        if fog_shows_land(fog[ME][c]) and near_view(iso(d.t.x * 1000.0, d.t.y * 1000.0)):
            let f = frame_index(d.name)
            if f >= 0:
                let at = iso(d.t.x * 1000.0, d.t.y * 1000.0)
                let ay = at.y - lift_at(d.t.x * 1000.0, d.t.y * 1000.0) * 1.5
                let shade = fog_prop_shade(fog[ME][c])
                if d.scale == 1.0: add(f, at.x, ay, at.y, float4 { 1.0, 1.0, 1.0, shade })
                else:
                    let fr = frames[f]
                    add_xf(f, [ d.scale * fr.k, 0.0, 0.0, d.scale * fr.k, at.x - d.scale * fr.k * float(fr.ox), ay - d.scale * fr.k * float(fr.oy) ], at.y, float4 { 1.0, 1.0, 1.0, shade })

def collect_props():
    collect_doodads()
    for(W * H) c:
        // (under the fog, the ground as you last saw it: a farm sown in the dark stays grass until you look, Fog's memory)
        let now = fog[ME][c] == 2 or fog_ground.length <= ME
        let tt = if now: terrain[c] else: fog_ground[ME][c]
        // (the land is no secret, #334: trees, gold, stone and bushes show where never explored, as the map was made)
        if fog_shows_land(fog[ME][c]) and (tr_res[tt] != 0 or species[c] != "-") and near_view(iso(float((c % W) * 1000 + 500), float((c / W) * 1000 + 500))):
            let tname = tr_names[tt]
            var kind = prop_of.get(tname, "")
            if kind == "tree": kind = species[c]
            elif tname == "stump" and species[c] != "-": kind = species[c]
            if kind != "" and kind != "-" and doodads.get(kind, 0) > 0:
                let left = if now: amount[anchor(c)] else: fog_left[ME][c]
                let full = max(left, tr_amount[tt])
                let pick = c * 7 + c / W
                let stage = if tname == "stump": 3 else: resource_stage(kind, left, full)
                let name = staged(kind, pick % doodads.get(kind, 1), stage)
                let at = iso(float((c % W) * 1000 + 500), float((c / W) * 1000 + 500))
                let up = lift_at(float((c % W) * 1000 + 500), float((c / W) * 1000 + 500)) * 1.5
                let shade = fog_prop_shade(fog[ME][c])
                let flat = pool[c] >= 0
                add(frame_index(name), at.x, at.y - up, if flat: -100000.0 + at.y else: at.y, float4 { 1.0, 1.0, 1.0, shade })
                let sh = frame_index(name + "~shadow")
                if sh >= 0: add(sh, at.x, at.y - up, -200000.0 + at.y, float4 { 1.0, 1.0, 1.0, shade })

let SHADE_FOOT_BACK = 3.0  // art px: a unit reads the ground's shade this far behind its feet, toward the sun (its own shadow falls the other way)

// The shade buffer (view/atmosphere.lobster), when the mood shades: the ground's shadows go into it, joining into one
// shade instead of piling up black on the world; then, back to front, what stands up out of it (props, buildings: lit
// by their own bake) and the units, each taking the shade of the ground at its feet. What lies flat on the ground
// (sorted under everything) is shaded as the ground is. After the world, its draw list sorted.
def draw_shade(cam_px:float2, ws:float2):
    flush_sprites()
    let was = gl.blend(blend_none)
    atmo_shade_begin()
    sprite_shader = "atmo_shade_cast"
    gl.translate(ws / 2.0):
        gl.scale(zoom):
            gl.translate(-cam_px):
                b_sheet = -1
                for(draws) d:
                    if d.f >= 0 and frame_role_of(d.f) == ROLE_CAST: sprite(d.f, d.x, d.ay, float4_1)
                flush_sprites()
    atmo_shade_standing()
    let s = normalize(atmo_sun_dir)
    let back = float2 { s.x, -s.y } * SHADE_FOOT_BACK * zoom  // (screen px, y down)
    gl.translate(ws / 2.0):
        gl.scale(zoom):
            gl.translate(-cam_px):
                b_sheet = -1
                for(draws) d:
                    if d.f >= 0 and d.y > -50000.0:
                        let role = frame_role_of(d.f)
                        if role != ROLE_CAST:
                            let shader = if role == ROLE_UNIT: "atmo_shade_stand" else: "atmo_shade_clear"
                            if shader != sprite_shader:
                                flush_sprites()
                                sprite_shader = shader
                                gl.blend(if role == ROLE_UNIT: blend_none else: blend_alpha)
                            let col = if role == ROLE_UNIT: atmo_stand_colour((float2 { d.x, d.ay } - cam_px) * zoom + ws / 2.0 + back) else: float4_1
                            if d.xf.length: sprite_xf(d.f, d.xf, col)
                            else: sprite(d.f, d.x, d.ay, col)
                flush_sprites()
    sprite_shader = "sprite"
    b_sheet = -1
    gl.blend(was)
    atmo_rebind()

def draw_world(alpha:float):
    atlas_pack()
    let ground_now = tick - ground_tick >= 10 or not ground_mesh
    if ground_now:
        build_ground()
        build_fog(ME)
        build_wear()
        ground_tick = tick
    let masks_now = not ground_quad or (map_version != mask_version and tick - mask_tick >= 50)
    if masks_now:
        build_masks()
        perf_masks_now = true
        if not relief_built:
            build_relief()
            relief_built = true
            refresh_paths()  // (doodads keep off the paths, so they must be there first)
            build_doodads(map_name_now, doodads) t: keep_clear(t) or on_path(t)
        mask_version = map_version
        mask_tick = tick
    // (a frame that rebuilt the ground or the masks leaves the paths to the next: one heavy job a frame, #335)
    if relief_built and tick - paths_tick >= 20 and not ground_now and not masks_now:
        paths_tick = tick
        if refresh_paths(): perf_built_now = true
    let ws = float(gl.window_size())
    let cam_px = float2 { floor(cam.x * zoom), floor(cam.y * zoom) } / zoom  // (on a whole device px, as the sprites: #358)
    sprite_snap = zoom
    let atmo_drawn = atmo_begin(float4 { 0.05, 0.05, 0.05, 1.0 })  // (the world into the atmosphere's texture, view/atmosphere.lobster)
    let shading = atmo_drawn and atmo_shading()
    let ground_stale_was = ground_stale
    let ground_step_was = ground_tex_step
    draw_ground_cached(gl.window_size(), cam_px, zoom, zoom / ART_K)  // (screen px an art px: finer art, D-173)
    // (the still ground remade its picture, and left for the screen: back into the world's texture, and the picture again)
    if atmo_drawn and ((ground_stale_was and not ground_stale) or ground_tex_step != ground_step_was):
        atmo_rebind()
        draw_ground_cached(gl.window_size(), cam_px, zoom, zoom / ART_K)
    gl.translate(ws / 2.0):
        gl.scale(zoom):
            gl.translate(-cam_px):
                if not reveal: draw_fog()
                perf_lap(1)
                set_view_rect()
                draws = []::Drawable
                collect_props()
                collect_buildings()
                collect_town()
                collect_units(alpha)
                collect_corpses()
                for(occluders) o, k: draws.push(Drawable { o.sort_y, draws.length, -2, float(k), 0.0, float4_1, [] })                                          // a hill's near-edge tops: what's behind it hides
                draws.push(Drawable { -50000.0, draws.length, -4, 0.0, 0.0, float4_1, [] })                                                                    // the selection rings: on the ground, over its flat props and shadows, under everything standing
                draws.push(Drawable { if occluders.length: occluders[occluders.length - 1].sort_y else: -50000.0, draws.length, -6, 0.0, 0.0, float4_1, [] })  // the orders, and rings on a hill: on the ground, after the last hill top that would paint over them
                perf_lap(2)
                qsort_in_place(draws) a, b: a.y < b.y or (a.y == b.y and a.seq < b.seq)
                perf_lap(3)
                b_sheet = -1
                for(draws) d:
                    if d.f == -2:
                        flush_sprites()
                        draw_occluder(occluders[int(d.x)], zoom / ART_K)
                        b_sheet = -1
                    elif d.f == -4:
                        flush_sprites()
                        draw_rings(alpha, false)
                        b_sheet = -1
                    elif d.f == -6:
                        flush_sprites()
                        draw_rings(alpha, true)
                        ui_batch(): draw_orders(alpha)  // (its dashes and rings in one draw)
                        b_sheet = -1
                    elif d.f == -3:  // a damaged building's cracks, sorted with it (game/town.lobster)
                        flush_sprites()
                        gl.scale(1.5): draw_cracks_of(int(d.x))
                        b_sheet = -1
                    elif shading and d.f >= 0 and frame_role_of(d.f) == ROLE_CAST: pass()  // (into the shade buffer instead: draw_shade)
                    elif d.f == -5: sprite_faded(int(d.xf[1]), d.x, d.ay, d.col, d.xf[0])  // a ruin fading out
                    elif d.xf.length: sprite_xf(d.f, d.xf, d.col)
                    else: sprite(d.f, d.x, d.ay, d.col)
                flush_sprites()
                perf_lap(4)
                gl.scale(1.5):
                    draw_town()
                    draw_shots(alpha)
                    fx_draw() id: unit_anchor(id)
                if not rec_clean: draw_marks(alpha)
                perf_lap(5)
    if shading: draw_shade(cam_px, ws)
    sprite_snap = 1.0
