// ------------------------------------------------------------------ the view of a match: what it keeps between frames
// Team colours, the mouse on the map, the ground's mesh, where each unit was last tick and which way it faces, when it
// last struck or was hit, the corpses; after_step() takes a tick's events in. Then the draw list every drawer adds to
// (add, add_xf) and the part of the map in view. A game imports its models and art lists after this file, and
// game/world_draw.lobster after those.

let DAMAGE_FIRE = 0.6  // the damage at which a building starts to burn

let TEAM_COLS = [ float4 { 0.85, 0.22, 0.18, 1.0 }, float4 { 0.20, 0.42, 0.85, 1.0 }, float4 { 0.85, 0.75, 0.2, 1.0 },
                  float4 { 0.25, 0.7, 0.3, 1.0 } ]
let WHITE = float4 { 1.0, 1.0, 1.0, 1.0 }
let ANIMAL_COL = float4 { 0.54, 0.48, 0.35, 1.0 }  // ArtKit.ANIMAL_TEAM: nobody's

def team_col(p:int) -> float4:
    if p == gaia: return ANIMAL_COL
    return if p < team_rgb.length: team_rgb[p] else: TEAM_COLS[p % TEAM_COLS.length]

// ------------------------------------------------------------------ iso (Iso.to_screen * 1.5: art px)

def mouse_milli() -> float2: return pick_milli(from_screen(mouse_px()))  // (on raised ground: the hill under the mouse)

// ------------------------------------------------------------------ the ground

var ground_mesh:resource<mesh>? = nil
var ground_tick = -1000
var paths_tick = -1000  // when the paths were last re-planned (#335: never in a frame that rebuilt the ground)
var relief_built = false
var mask_version = -1
var mask_tick = -1000

def cell_noise(c:int) -> float: return float((c * 2654435761) % 1000) / 1000.0

// Each cell a fan of four triangles: its own colour in the middle, its corners the average of the
// cells round them, so the ground blends from tile to tile.
def build_ground():
    let fg = fog[ME]
    let cols = map(W * H) c:
        let t = terrain[c]
        let k = 0.35 + 0.65 * cell_noise(c)
        let shade = fog_ground_shade(fg[c])
        (ground_a[t] * k + ground_b[t] * (1.0 - k)) * shade
    let corner = map((W + 1) * (H + 1)) v:
        let vx = v % (W + 1)
        let vy = v / (W + 1)
        var sum = float4_0
        var n = 0
        for([ int2 { -1, -1 }, int2 { 0, -1 }, int2 { -1, 0 }, int2 { 0, 0 } ]) d:
            let x = vx + d.x
            let y = vy + d.y
            if x >= 0 and y >= 0 and x < W and y < H:
                sum += cols[y * W + x]
                n++
        sum / float(max(1, n))
    let pos = []::float3
    let col = []::float4
    let idx = []::int
    for(W * H) c:
        let cx = c % W
        let cy = c / W
        let n = pos.length
        let m = iso(float(cx * 1000 + 500), float(cy * 1000 + 500))
        pos.push(float3 { m.x, m.y, 0.0 })
        col.push(float4 { cols[c].x, cols[c].y, cols[c].z, 1.0 })
        for([ int2 { 0, 0 }, int2 { 1, 0 }, int2 { 1, 1 }, int2 { 0, 1 } ]) d:
            let p = iso(float((cx + d.x) * 1000), float((cy + d.y) * 1000))
            let k = corner[(cy + d.y) * (W + 1) + cx + d.x]
            pos.push(float3 { p.x, p.y, 0.0 })
            col.push(float4 { k.x, k.y, k.z, 1.0 })
        for([ 0, 2, 1, 0, 3, 2, 0, 4, 3, 0, 1, 4 ]) v: idx.push(n + v)
    ground_mesh = gl.new_mesh("PC", pos, col, []::float3, []::float2, []::float2, idx)

// ------------------------------------------------------------------ what the view remembers

class Corpse:
    id:int
    kind:int
    owner:int
    x:float
    y:float
    dir:int
    t0:float
    puffed:bool

var clock_s = 0.0   // seconds of play shown
var p_id = []::int  // the last tick's positions, for drawing between ticks
var p_x = []::int
var p_y = []::int
let unit_dir = dictionary<int, int>(1024)
let last_aim = dictionary<int, int>(64)      // a turret's aim last frame (is it turning? for its sound)
let aim_moved = dictionary<int, float>(64)   // when a turret's aim last changed
let unit_kick = dictionary<int, float2>(64)  // a mount just fired (unit id * 16 + mount): how far it kicks back, canvas px, and when (view only)
let attack_t0 = dictionary<int, float>(1024)
var corpses = []::Corpse
let hit_t0 = dictionary<int, float>(1024)       // when a unit was last hit (the flash)
var shot_from = dictionary<int, int>(1024)      // a shot (its by * 65536 + landing tick) -> the tick it was first seen
var shot_mouth = dictionary<int, float2>(1024)  // the same: where it left its shooter, canvas px from the shot's start (fixed once fired)
let last_kind = dictionary<int, int>(1024)
let last_owner = dictionary<int, int>(1024)

def prev_pos(i:int) -> int, int:
    let found, at = binary_search(p_id, u_id[i])
    return if found: p_x[at] else: u_x[i], if found: p_y[at] else: u_y[i]

// Is this milli-tile spot on screen (with a margin)? Sounds only play for what you can see.
def on_screen(x:int, y:int) -> bool:
    let s = to_screen(iso(float(x), float(y)))
    let ws = float(gl.window_size())
    return s.x > -100.0 and s.y > -100.0 and s.x < ws.x + 100.0 and s.y < ws.y + 100.0

var my_units = 0
var my_age = 1
var my_researched = 0
var my_done = []::int  // ids of my finished buildings, last tick

var last_battle = -100.0  // when there was last fighting on screen (the theme's battle layer)

def sounds_after_step():
    for(events) e:
        if e.kind == EV_HIT and on_screen(e.x, e.y): last_battle = gl.time()
        if e.kind == EV_SHOT and on_screen(e.x, e.y) and fog[ME][cell_of(e.x, e.y)] == 2:
            let i = index_of(e.a)
            if i >= 0: play_sound(unit_shot.get(u_kind[i], "shoot_arrow"), -4.0)
        elif e.kind == EV_HIT and on_screen(e.x, e.y) and fog[ME][cell_of(e.x, e.y)] == 2:
            let i = index_of(e.a)
            if i >= 0:
                if t_ranged[u_kind[i]]:
                    let own = shot_style(unit_shotk.get(u_kind[i], "arrow")).hit.sound
                    play_sound(if own != "": own else: "arrow_land", -8.0)
                else: play_sound(unit_blow.get(u_kind[i], "hit_pierce"), 0.0)
        elif e.kind == EV_DIE and on_screen(e.x, e.y) and fog[ME][cell_of(e.x, e.y)] != 0:
            if e.b == 1: play_sound("building_fall", -2.0)
            else:
                play_sound("fall", -3.0)
                if last_owner.get(e.a, -1) == ME: say(ME, "die")
    var n = 0
    for(u_owner) p: n += if p == ME: 1 else: 0
    if n > my_units and tick > 40: play_sound("trained", -6.0)
    my_units = n
    if ages[ME] > my_age: play_sound("age", 0.0)
    my_age = ages[ME]
    var r = 0
    for(researched[ME]) v: r += v
    if r > my_researched: play_sound("research", -4.0)
    my_researched = r
    let done = []::int
    for(b_id.length) b:
        if b_owner[b] == ME and b_done[b] == 1:
            done.push(b_id[b])
            if tick > 40 and not contains(my_done, b_id[b]): play_sound("built", -4.0)
    my_done = done

// raze: (captures) your buildings but the Town Center and walls fall, as Combat's fallen buildings do.
def raze_mine():
    var b = b_id.length - 1
    while b >= 0:
        if b_owner[b] == ME and b_done[b] == 1 and bt_name[b_kind[b]] != "town_center" and not wall_like(b):
            events.push(Event { EV_DIE, b_id[b], 1, b_sx[b], b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2 })
            clear_farm(b)
            pen_gone(b)
            spill(b)
            breach(b)
            occupy(footprint(b), 0)
            remove_building(b)
        b--

def after_step():
    if raze_at >= 0.0 and clock_s >= raze_at:
        raze_at = -1.0
        raze_mine()
    sounds_after_step()
    fx_events()
    for(events) e:
        if e.kind == EV_SHOT: attack_t0.set(e.a, clock_s)
        elif e.kind == EV_HIT:
            hit_t0.set(e.b, clock_s)
            let i = index_of(e.a)
            if i >= 0 and not t_ranged[u_kind[i]]: attack_t0.set(e.a, clock_s)
        elif e.kind == EV_DIE and e.b == 0:
            let found, at = binary_search(p_id, e.a)
            if found:
                let x = float(p_x[at])
                let y = float(p_y[at])
                corpses.push(Corpse { e.a, last_kind.get(e.a, -1), last_owner.get(e.a, 0), x, y, unit_dir.get(e.a, 0), clock_s, false })

// ------------------------------------------------------------------ drawing the world

class Drawable:
    y:float  // sort point (art px)
    seq:int  // then the order added (a unit's parts, in its draw order)
    f:int    // frame
    x:float
    ay:float  // anchor y
    col:float4
    xf:[float]  // a transform (else empty: drawn at its anchor)

var draws = []::Drawable
// The world on the screen this frame (art px): sprites wholly outside it aren't drawn.
var view_lo = float2_0
var view_hi = float2_0
let VIEW_REACH = 512.0  // art px: about the tallest prop over its anchor (props are culled by their cell first)

def set_view_rect():
    let ws = float(gl.window_size())
    view_lo = from_screen(float2_0) - float2_1
    view_hi = from_screen(ws) + float2_1

def in_view(x0:float, y0:float, x1:float, y1:float) -> bool:
    return x0 < view_hi.x and y0 < view_hi.y and x1 > view_lo.x and y1 > view_lo.y

// Whether a prop anchored at p (art px) may reach the screen.
def near_view(p:float2) -> bool: return in_view(p.x - VIEW_REACH, p.y - 64.0, p.x + VIEW_REACH, p.y + VIEW_REACH)

def add(f:int, x:float, y:float, sort_y:float, col:float4):
    if f < 0: return
    let fr = frames[f]
    let x0 = floor(x) - float(fr.ox) * fr.k
    let y0 = floor(y) - float(fr.oy) * fr.k
    if in_view(x0, y0, x0 + float(fr.w) * fr.k, y0 + float(fr.h) * fr.k):
        draws.push(Drawable { sort_y, draws.length, f, x, y, col, [] })

def add_xf(f:int, xf:[float], sort_y:float, col:float4):
    if f < 0: return
    let fr = frames[f]
    let u = float2 { xf[0], xf[1] } * float(fr.w)  // (the frame's edges, turned)
    let v = float2 { xf[2], xf[3] } * float(fr.h)
    let o = float2 { xf[4], xf[5] }
    let lo = o + min(u, float2_0) + min(v, float2_0)
    let hi = o + max(u, float2_0) + max(v, float2_0)
    if in_view(lo.x, lo.y, hi.x, hi.y):
        draws.push(Drawable { sort_y, draws.length, f, 0.0, 0.0, col, xf })

var frame_dt = 1.0 / 60.0

def canvas(x:float, y:float) -> float2: return iso(x, y) / 1.5
