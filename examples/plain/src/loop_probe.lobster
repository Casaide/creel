// Age of Anything in Lobster (docs/milestones/lobster-port.md): the ported sim and bots, the art
// from a match pack (art_pack.gd), a window to play in. You are player 0; the ported bot plays the
// rest ("watch": the bot plays you too).
// Run: lobster game.lobster -- <pack dir> <scenario file, or - to make the start from the pack\'s races> [watch]
//   left click / drag: select;  right click: move, attack, gather, build, rally;  shift: queue
//   Ctrl + right click: attack-move;  X: stop;  B then 1-9: build;  1-9 on a building: train;  U: age up
//   Q E R T Y F G H J on a building: research;  M: sound on / off;  the minimap (bottom right): click to look there
//   WASD / arrows / screen edges: scroll;  wheel: zoom;  space: pause;  + / -: speed;  Ctrl/Cmd + / -: the HUD's size

import from "../../../src"
import std
import vec
import color
import gl
import texture
import dictionary
import .lib.consts
import .lib.fixed
import .lib.tokens
import .lib.state
import .lib.flow
import .lib.spatial
import .lib.orders
import .lib.movement
import .lib.steering
import .lib.fog
import .lib.map
import .lib.economy
import .lib.tech
import .lib.combat
import .lib.siege
import .lib.eco_bot
import .lib.garrison
import .lib.heal
import .lib.heroes
import .lib.match
import .lib.trade
import .lib.animals
import .lib.bridges
import .lib.walls
import .lib.abilities
import .lib.trails
import .lib.commands
import .lib.ai_cfg
import .lib.scout
import .lib.land
import .lib.expand
import .lib.bot
import .lib.walls_ai
import .lib.world
import .gen.json
import .gen.sha256
import .gen.rng
import .gen.datalib
// game: import .gen.identity
// game: import .gen.effect_words
import .gen.mods
// game: import .gen.pricing
// game: import .gen.heroes
// game: import .gen.generator
import .hooks.active
// game: import .hooks.rules
import .gen.setup
// game: import .gen.race_to_types
import .gen.modes
import .gen.start
import .view.facing
import .view.shot_look
import .view.node
import .view.art
import .view.bake_cache
import .view.atmosphere
// game: import .gen.reset
// game: import .gen.balance
// game: import .gen.swap
// game: import .gen.save
import .net.lockstep
import .net.lan
import .game.audio
import .game.pack
import .game.relief
import .game.fog_look
import .game.ground
import .game.doodads
// game: import .game.paths
import .game.fx
import .game.topbar_fit
import .game.ui
import .game.text_cache
import .game.levels
import .game.perf
import .game.pace
import .game.window_mode
import .game.window_switch

let args = command_line_arguments()
// Options after the two paths: watch (the bot plays you too), speed:<x>, shot:<png> with at:<seconds>
// (a screenshot after that much play, then quit), look:<x>,<y> (the camera on that tile).
var watch = false
var follow = false        // the camera follows the fighting (captures)
var look_at_army = false  // a skirmish you play: the camera starts on your army and stays yours
var selftest = false      // play a few orders through the controls, check the sim took them, quit
var airtest = false       // does a click on an aircraft, where it's drawn, take it? Then quit (#185)
var shot = ""
var shot_at = 0.0
var start_speed = 1.0
var look_x = -1
var swap_arg = ""  // swap:<prompt>@<seconds>: become that race then (tests and captures)
var swap_at = -1.0
var rules_arg = ""            // rules:<id>: the host rules (else the pack's)
var mods_arg = ""             // mods:a,b: mods to merge over the data (else the pack's)
var lobby_rerolls = [ 0, 0 ]  // each side's reroll (the generator's other takes on the same prompt)
var rebake_art = false        // rebake: every prop baked in Lobster, even those the pack has
var mesh_dir = ""             // meshes:<dir>: the mesh library (mesh_export.gd library): parts the pack lacks are baked here
var mode_arg = ""             // mode:<id>: the lobby's game mode (data/modes.json)
var map_arg = ""              // map:<id>: the lobby's map (tests and captures)
var races_arg = ""            // races:<A>|<B>: the lobby's prompts, as if typed (then played)
var look_y = -1
var rec_dir = ""  // record:<dir>: from:<seconds> of play on, for:<seconds>, one PNG a frame at 30 fps, then quit (a clip of the game)
var rec_from = 0.0
var rec_for = 10.0
var rec_n = 0
var rec_fps = 30.0         // fps:<n>: frames a second of play
var rec_clean = false      // clean: nothing over the world: no top bar, panel, minimap, groups, health bars or banner (a clip for showing)
var rec_type = []::string  // typein:A|B: (filming the lobby)
var rec_side = 0
var rec_char = 0
var rec_wait = 30
var rec_push = 1.0                    // push:<k>: a record:'s camera closes in, its zoom k times by the end (1.15 is a slow push)
var rec_pan = float2_0                // pan:<x>,<y>: a record:'s camera drifts that many tiles by the end (no follow then)
var window_arg = int2 { 1600, 1000 }  // window:<w>,<h>: the window's size in points (filming: 1280,720 is 16:9, 2560x1440 frames on a Mac)
var fort_gate = int2 { -1, -1 }       // place:fort's gate (captures: army: walks through it)
var place_arg = ""                    // place:<building>: one finished by your Town Center at the start; fort, palisade_fort: a wall line (captures)
var skirmish = false                  // the lobby's Skirmish: both armies on the map at once, marching on each other
var army_n = 0                        // army:<n>: n of each of your soldier types by your Town Center at the start (captures)
var army_snap = false                 // a skirmish's armies start in their blocks, once the first order has made them
let ARMY_GAP = 600                    // milli-tiles between them, in ranks
var zoom_arg = 0.0                    // zoom:<n>: the camera at that zoom at the start, 1 the farthest out (filming)
var density_arg = 0.0                 // density:<z>: prebake at that art density (prebake.sh: the base, then a Retina Mac's 2.4, #358)
var reveal = false                    // reveal: the view shows the whole map, the fog off (view only: filming, and perf: sees every unit)
var hurt_pct = -1                     // hurt:<percent>: your buildings start at that much of their hit points (captures of fire)
var raze_at = -1.0                    // raze:<seconds>: your buildings but the Town Center and walls fall then (captures of ruins)
var page_arg = ""                     // page:<name>: the lobby opened on that page (title, setup, lab, saves, net; boot: the boot screen), captures with shot:
var lab_arg = false                   // lab: the lobby with races:A|B typed in, a picture (shot:) after a second, then quit
var tree_arg = false                  // tree: the tech tree page open from the start (captures)
var tree_hover_arg = ""               // treehover:<node key>: that node hovered on it (captures: "r:fletching", "u:hero.<id>@3")
var padtest = false                   // padtest: a fake pad plays a few seconds, then quit
var net_people = 2                    // people in a network match (host:<n>)
var net_others = []::Link             // a host's joiners after the first
var hosting = false                   // host: a network match, waiting for a player to join (net/lockstep.lobster)
var join_ip = ""                      // join:<ip>: play the second side of the match a host there sets up
var reload_at = -1.0                  // reload:<seconds>: save then, load 5 s later (tests and captures)
var reload_tick = -1
var touch_play = false  // touch: play by touch, through the pad's controls (game/touch.lobster; the Android build)
var atmo_arg = ""       // atmosphere:<mood>: the match in that mood (data/atmosphere.json), atmosphere:off: none (the frame drawn straight)
// A mod can say how it starts (its manifest's `launch`): those options, as if typed after the rest.
for(copy(args)) a:
    if starts_with(a, "mods:"):
        for(mods_launch_args(tokenize(a.substring(5, a.length - 5), ",", ""))) option: args.push(option)
for(args) a, k:
    if k >= 2:
        if a == "watch": watch = true
        if a == "touch":
            touch_play = true
            ui_touch = true
        let key, val = split_string(a, ":")
        if key == "shot": shot = val
        if key == "fsat": window_toggles = map(tokenize(val, ",", " ")) t: string_to_float(t)
        if key == "fsreport": window_report = val
        if key == "at": shot_at = string_to_float(val)
        if key == "record": rec_dir = val
        if key == "typein": rec_type = tokenize(val, "|", " ")
        if key == "from": rec_from = string_to_float(val)
        if key == "for": rec_for = string_to_float(val)
        if key == "fps": rec_fps = string_to_float(val)
        if key == "push": rec_push = string_to_float(val)
        if key == "pan":
            let px, py = split_string(val, ",")
            rec_pan = float2 { string_to_float(px), string_to_float(py) }
        if key == "window":
            let wx, wy = split_string(val, ",")
            window_arg = int2 { string_to_int(wx), string_to_int(wy) }
        if a == "clean": rec_clean = true
        if key == "perf": perf_for = string_to_float(val)  // (game/perf.lobster: the drawing's cost in the window)
        if key == "zoom": zoom_arg = string_to_float(val)
        if key == "density": density_arg = string_to_float(val)
        if a == "reveal": reveal = true
        if a == "perflive": perf_live = true
        if a == "oldtext": text_off = true  // (measuring: text drawn as before game/text_cache.lobster)
        if key == "speed": start_speed = string_to_float(val)
        if a == "selftest": selftest = true
        if a == "airtest": airtest = true
        if a == "follow": follow = true
        if key == "races": races_arg = val
        if key == "map": map_arg = val
        if key == "mode": mode_arg = val
        if key == "reroll": lobby_rerolls = map(tokenize(val, "|", " ")) r: string_to_int(r)
        if key == "rules": rules_arg = val
        if key == "meshes": mesh_dir = val
        if a == "rebake": rebake_art = true
        if key == "mods": mods_arg = val
        if key == "atmosphere": atmo_arg = val
        if key == "reload": reload_at = string_to_float(val)
        if a == "host": hosting = true
        if key == "host":  // host:<n>: n people (more than two: a 2v2 on the four-player map)
            hosting = true
            net_people = max(2, string_to_int(val))
        if a == "padtest": padtest = true
        if a == "skirmish": skirmish = true
        if a == "tree": tree_arg = true
        if key == "treehover":
            tree_arg = true
            tree_hover_arg = val
        if a == "lab": lab_arg = true
        if key == "page": page_arg = val
        if key == "hurt": hurt_pct = string_to_int(val)
        if key == "raze": raze_at = string_to_float(val)
        if key == "army": army_n = string_to_int(val)
        if key == "place": place_arg = val
        if key == "join": join_ip = val
        if key == "swap":
            let sp, sa = split_string(val, "@")
            swap_arg = sp
            swap_at = string_to_float(sa)
        if key == "look":
            let lx, ly = split_string(val, ",")
            look_x = string_to_int(lx)
            look_y = string_to_int(ly)

// Tests and captures are silent (Dominic: no sound from testing); `mute` silences a game too.
if has_s(args, "mute") or shot != "" or rec_dir != "" or selftest or airtest or padtest or has_s(args, "labtest") or reload_at >= 0.0 or perf_for > 0.0:
    sound_on = false
    pace_background = false  // (tests and captures keep their pace with the window in the background, game/pace.lobster)

var ME = 0  // the side you command (1 for the one who joins a network match)
var in_net_match = false
let TEAM_COLS = [ float4 { 0.85, 0.22, 0.18, 1.0 }, float4 { 0.20, 0.42, 0.85, 1.0 }, float4 { 0.85, 0.75, 0.2, 1.0 },
                  float4 { 0.25, 0.7, 0.3, 1.0 } ]
let WHITE = float4 { 1.0, 1.0, 1.0, 1.0 }
let ANIMAL_COL = float4 { 0.54, 0.48, 0.35, 1.0 }  // ArtKit.ANIMAL_TEAM: nobody's

def team_col(p:int) -> float4:
    if p == gaia: return ANIMAL_COL
    return if p < team_rgb.length: team_rgb[p] else: TEAM_COLS[p % TEAM_COLS.length]

// ------------------------------------------------------------------ iso (Iso.to_screen * 1.5: art px)

var cam = float2_0  // art px at the middle of the window
var zoom = 2.0      // screen px per art px

def to_screen(p:float2) -> float2: return (p - cam) * zoom + float(gl.window_size()) / 2.0
def from_screen(p:float2) -> float2: return (p - float(gl.window_size()) / 2.0) / zoom + cam
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

// The line step a type is drawn in (as retype picks it): the recipe its units look like now.
def type_step(k:int) -> int:
    let p = t_player[k]
    if p < 0 or p >= num_players: return 0
    let line = lines[k]
    var step = 0
    for(line) l, n:
        if l.age <= ages[p] and (l.age == line[0].age or t_worker[k] or t_hero[k] or upgraded_line(p, l)): step = n
    return step

def canvas(x:float, y:float) -> float2: return iso(x, y) / 1.5

import .model.kit
import .model.grng
import .model.base
import .model.flat
// game: import .model.props
// game: import .model.town_props
// game: import .model.bridges
// game: import .model.build_mats
import .view.voxel_mesh
import .view.voxel_grid
// game: import .model.trees
// game: import .model.rocks
// game: import .model.buildings
// game: import .model.future
// game: import .model.buildings2
// game: import .game.art_kit
// game: import .game.ruin
// game: import .game.art_kit_buildings
// game: import .game.pack_data
import .view.vox
import .view.voxel
// game: import .game.voxel_units

// game: import .game.town  // (here: it uses the views)
// game: import .game.glows

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

// Each side's paths (sim_debug._refresh_paths): from its biggest finished building's door to its other
// finished buildings and the nearest food and wood; the hub and resource ends picked once. An
// enemy's only run between the buildings you've seen. Re-planned when the finished count changes.
def refresh_paths() -> bool:
    var count = 0
    let owners = []::PathOwner
    for(su_races) race, p:
        let mine = []::int
        for(b_id.length) b:
            if b_owner[b] == p and b_done[b] == 1 and not wall_like(b) and (teams[p] == teams[ME] or fog[ME][b_cy[b] * W + b_cx[b]] != 0):
                mine.push(b)
        count += mine.length
        if mine.length:
            insertion_sort(mine) a, b: b_sx[a] * b_sy[a] > b_sx[b] * b_sy[b] or (b_sx[a] * b_sy[a] == b_sx[b] * b_sy[b] and b_id[a] < b_id[b])
            let st = gobj(family(rstr(race, "family")), "paths")
            if path_anchor_hub.get(p, float2 { -9.0, -9.0 }).x < -8.0:
                let at = door_of(mine[0])
                let res = []::float2
                for([ "food", "wood" ]) kind:
                    let t = nearest_resource_edge(str_index(resource_names, kind) + 1, at)
                    if t.x >= 0.0: res.push(t)
                path_anchor_hub.set(p, at)
                path_anchor_res.set(p, res)
            let hub = path_anchor_hub.get(p, float2_0)
            let targets = []::float2
            for(mine) b:
                if door_of(b) != hub: targets.push(door_of(b))
            for(path_anchor_res.get(p, [])) t: targets.push(t)
            let w = get(st, "width")
            owners.push(PathOwner { gstr(st, "style", "trail"), if w: as_float(w) else: 0.36, hub, targets })
    if count == path_count: return false
    path_count = count
    path_plan(owners)
    paint_paths()
    return true

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
    sprite_snap = 1.0

// ------------------------------------------------------------------ the lobby (type your races; Lobster makes and sets them up)
// Two prompts, each race shown as you type (the generator takes a few milliseconds); Enter starts the
// match at the generator's prices, calibrated offline (src/calibrate.lobster, D-195): no fights at load.
// The units are drawn from the part library (art_pack.gd library).

def rules_id() -> string: return if rules_arg != "": rules_arg else: pack_rules
var lobby_map = "reed_meadow"
let MODE_IDS = [ "standard", "fortress", "siege" ]  // data/modes.json (gen/modes.lobster)
var lobby_mode = "standard"
var lobby_prompts = []::string  // each side's words (the lobby's, or races:A|B)
var lobby_teams = []::int       // each side's team (a team game from the lobby)
var lobby_levels = []::string   // each side's AI level ("" for a person)
var front_shown = false         // the lobby's pages were up (the match loader shows their armies)

// The maps a match can be on (data/maps).
def map_ids() -> [string]:
    let names = scan_folder("../data/maps", false)
    let out = []::string
    if names:
        for(names) n:
            if ends_with(n, ".json"): out.push(substring(n, 0, n.length - 5))
    return sorted_strs(out)

// The map's tree species per cell
// (and every table the pack lacks, from data: game/pack_data.lobster; the species worked out as Godot's LandView
// does, species_check.lobster)
def load_species(map_id:string):
    species = species_from_map(map_id)
    pack_from_data(map_id)
    let atmo = lib_data("atmosphere.json")  // (the mood: the asked one, the map's, else the default; an unknown one stops the game)
    let bad = atmo_set(atmo, atmo_mood_for(atmo, map_id, atmo_arg))
    if bad != "": fatal_exit(bad)

def lobby_text(p:float2, s:string, col:float4): text_label(p, s, gl.get_font_size(), col, TEXT_FACE, 0.0, float4_0)

// A filled box from its top-left corner (gl.rect draws -size..size round its point in this build).
def box(at:float2, size:float2, col:float4): ui_fill(at, size, col)

// The Race Lab's Test: rounds of the round robin in age 2 between its races, each line's win rate and the
// price the fights would give it (gen/balance.lobster), shown as it goes. Returns the report. (A match
// never runs it: prices are calibrated offline, D-195.)
def balance_for_match(races:[JV], rules:JV, rounds:int) -> [string]:
    let report = []::string
    let t0 = seconds_elapsed()
    let stop = false
    auto_balance(races, rules, 2, rounds, 10) round, units, rates, mean, off:
        report.push("round {round + 1}: {off} of {units.length} lines more than 10 points off the mean ({rr_fights} fights, {seconds_elapsed() - t0} s)")
        gl.frame()
        if front_shown:  // (from the lobby's pages: the match loader, game/lobby.lobster)
            fe_loader("Balancing the armies by fighting them: round {round + 1} of {rounds}", 0.05 + 0.45 * float(round + 1) / float(rounds))
        else:
            gl.clear(float4 { 0.07, 0.06, 0.05, 1.0 })
            gl.set_shader("color")
            let u = ui()
            gl.set_font_size(int(26.0 * u))
            lobby_text(float2 { 40.0 * u, 40.0 * u }, "Balancing the armies by fighting them...", float4 { 0.95, 0.85, 0.6, 1.0 })
            gl.set_font_size(int(16.0 * u))
            for(report) line, n: lobby_text(float2 { 40.0 * u, 100.0 * u + float(n) * 24.0 * u }, line, float4 { 0.8, 0.78, 0.72, 1.0 })
            for(units) un, k:
                let pct = rr_price_pct.get(price_key(races, un), 100)
                lobby_text(float2 { 40.0 * u + float(k / 18) * 560.0 * u, 260.0 * u + float(k % 18) * 22.0 * u },
                           "{rates[k]}%  {un.label}" + (if pct != 100: "  price {pct}%" else: ""), float4 { 0.75, 0.72, 0.66, 1.0 })
    return report

// CombatFx.shot_kind: what a unit's shots are, by its weapon's tags.
def shot_kind_of(tags:[string]) -> string:
    for(sorted_strs(mod_shots.keys)) k:  // (a mod's look first, by its tag)
        if has_s(tags, gstr(at(mod_shots, k), "tag", "")): return k
    if has_s(tags, "great_sling"): return "sling_stone"
    if has_s(tags, "catapult"): return "boulder"
    if has_s(tags, "bolt_thrower"): return "siege_bolt"
    if has_s(tags, "javelin"): return "javelin"
    if has_s(tags, "sling"): return "stone"
    if has_s(tags, "poison"): return "dart"
    if has_s(tags, "gun"): return "ball"
    if has_s(tags, "heavy") and has_s(tags, "bow"): return "bolt"
    return "arrow"

// What the pack used to tell per race: names, voices, blow and shot sounds, architectures.
def race_facts(races:[JV]):
    voice_of = map(races) r: rstr(creature(rstr(r, "creature")), "voice")
    arch_of = map(races) r: architecture(r)
    for(t_slot.length) k:
        let r = at(su_units[k], "look")
        unit_names.set(k, gstr(r, "name", t_slot[k]))
        let tags = unit_tags(su_units[k])
        unit_blow.set(k, if has_s(tags, "ram"): "ram_hit" elif has_s(tags, "blade"): "hit_blade" elif has_s(tags, "blunt"): "hit_blunt" else: "hit_pierce")
        let kind = shot_kind_of(tags)
        unit_shotk.set(k, kind)
        unit_shot.set(k, gstr(get(lib_data("shots.json"), kind) or jobj(), "sound", "shoot_arrow"))

// ------------------------------------------------------------------ becoming another race mid-match (gen/swap.lobster)
// N: type a race; Enter: your people become it at its own prices (no fights, D-195), line by line,
// units and all, and your buildings take its style.

var typing_race = false
var banner = ""
var banner_t = -100.0

def become(prompt:string):
    let race = generate(prompt, su_rules, 0)
    let t0 = seconds_elapsed()
    let old = rstr(su_races[ME], "name")
    swap_race(ME, race)
    race_facts(su_races)
    bake_buildings_for(arch_of)  // (and its culture's buildings)
    banner = old + " become " + rstr(race, "name") + " (" + rstr(race, "creature") + ", " + rstr(race, "family") + "), in {int((seconds_elapsed() - t0) * 1000.0)} ms"
    banner_t = seconds_elapsed()
    print banner

def typing_tick():
    let text = gl.text_input_state()
    if gl.button("escape") == 1:
        typing_race = false
        gl.end_text_input()
        return
    if gl.button("return") == 1 and not window_combo():
        typing_race = false
        gl.end_text_input()
        if text != "": become(text)
        return
    let u = ui()
    let ws = float(gl.window_size())
    gl.set_shader("color")
    ui_fill(float2 { ws.x * 0.2, ws.y * 0.4 }, float2 { ws.x * 0.6, 110.0 * u }, float4 { 0.08, 0.06, 0.04, 0.92 })
    gl.set_font_size(int(18.0 * u))
    lobby_text(float2 { ws.x * 0.2 + 20.0 * u, ws.y * 0.4 + 14.0 * u }, "Your people become... (Enter: balance and change; Esc: never mind)", float4 { 0.8, 0.78, 0.7, 1.0 })
    gl.set_font_size(int(26.0 * u))
    let preview = if text != "": rstr(generate(text, su_rules, 0), "name") else: ""
    lobby_text(float2 { ws.x * 0.2 + 20.0 * u, ws.y * 0.4 + 46.0 * u }, text + (if (int(seconds_elapsed() * 2.0) % 2) == 0: "|" else: "") + (if preview != "": "    -> " + preview else: ""), float4 { 1.0, 0.95, 0.85, 1.0 })

def draw_banner():
    if seconds_elapsed() - banner_t > 8.0: return
    let u = ui()
    let ws = float(gl.window_size())
    gl.set_shader("color")
    ui_fill(float2 { 20.0 * u, 50.0 * u }, float2 { ws.x - 40.0 * u, 40.0 * u }, float4 { 0.08, 0.06, 0.04, 0.85 })
    gl.set_font_size(int(20.0 * u))
    lobby_text(float2 { 34.0 * u, 58.0 * u }, banner, float4 { 0.95, 0.85, 0.6, 1.0 })

// ------------------------------------------------------------------ selection and orders

var selected = []::int                   // unit ids
let groups = dictionary<int, [int]>(10)  // control group (0 for key 1) -> unit ids
var last_group = -1
var last_group_at = -10.0
var sel_building = 0  // building id
var sel_foreign = 0   // a unit that isn't mine, shown in the panel: view-only, so never in selected
var panel_hp = -1     // the HP the panel last drew (the self-test reads it)
var drag_from = float2_0
var dragging = false
var build_menu = false
var placing = -1                 // building type being placed
var wall_from = int2 { -1, -1 }  // where a wall's drag began (a cell), while placing walls or gates (bt_line)

def selected_units() -> [int]: return filter(selected) id: index_of(id) >= 0
def selected_workers() -> [int]: return filter(selected_units()) id: t_worker[u_kind[index_of(id)]] != 0

def unit_at_screen(m:float2, mine:bool) -> int:
    var best = -1
    var best_d = 24.0 * zoom
    for(u_x.length) i:
        if (teams[u_owner[i]] == teams[ME]) == mine and (mine or visible_to_me(cell_of(u_x[i], u_y[i]))):
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])) - float2 { 0.0, 14.0 + air_lift(u_kind[i]) })
            let d = magnitude(s - m)
            if d < best_d:
                best_d = d
                best = i
    return best

// Can I see building b now? (Remembered in the fog isn't enough: its HP would be live.)
def building_seen(b:int) -> bool:
    if teams[b_owner[b]] == teams[ME]: return true
    for(b_sy[b]) y:
        for(b_sx[b]) x:
            if visible_to_me((b_cy[b] + y) * W + b_cx[b] + x): return true
    return false

// The building drawn under the mouse (the frontmost), mine or one I can see that isn't, else -1.
def building_drawn_at(m:float2, mine:bool) -> int:
    let p = from_screen(m)
    var best = -1
    var best_y = -1000000000.0
    for(bld_hits) h:
        if p.x >= h.lo.x and p.y >= h.lo.y and p.x <= h.hi.x and p.y <= h.hi.y and h.sort_y > best_y:
            let b = b_index_of(h.id)
            if b >= 0 and (if mine: b_owner[b] == ME else: b_owner[b] != ME and building_seen(b)):
                best = b
                best_y = h.sort_y
    return best

def building_at(mm:float2) -> int:
    let x = int(mm.x)
    let y = int(mm.y)
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return -1
    let bid = occupied[cell_of(x, y)]
    return if bid != 0: b_index_of(bid) else: -1

// The wall cell drawn at m (-1: none): a wall is its footprint raised to the height it's drawn at, so a click on its
// face or top finds it, the frontmost first, and not past anything standing in front of it (Dominic, 2026-11-04).
let WALL_REACH = 160.0  // art px, more than a gate tower
def wall_cell_at(m:float2) -> int:
    let p = from_screen(m)
    var t = WALL_REACH
    while t >= 0.0:
        let mm = pick_milli(p + float2 { 0.0, t })
        let b = building_at(mm)
        if b >= 0:
            let c = cell_of(int(mm.x), int(mm.y))
            if (find(bld_hits) h: h.id == b_id[b] and h.lo.y <= p.y) >= 0 and (teams[b_owner[b]] == teams[ME] or fog[ME][c] != 0):
                return if bt_wall[b_kind[b]] != 0 or bt_gate[b_kind[b]] != 0: c else: -1
        t -= 4.0
    return -1

// The ground under m for an order: a wall drawn there, or what's under the mouse.
def order_milli(m:float2) -> float2:
    let c = wall_cell_at(m)
    return if c >= 0: float2 { float((c % W) * TILE + TILE / 2), float((c / W) * TILE + TILE / 2) } else: mouse_milli()

var last_click_at = -10.0  // the last click on one of my units (a second one soon after, near it, is a double click)
var last_click_at_m = float2_0
var last_click_kind = -1

// All my units of a kind on screen (a double click on one of them; shift adds them).
def select_kind_on_screen(kind:int, add:bool):
    let ws = float(gl.window_size())
    if not add: selected = []::int
    for(u_x.length) i:
        if u_owner[i] == ME and u_kind[i] == kind:
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])))
            if s.x >= 0.0 and s.y >= 0.0 and s.x <= ws.x and s.y <= ws.y and not contains(selected, u_id[i]): selected.push(u_id[i])

// Select what's under the mouse (shift: add a unit to the selection, or take it out; a double click: all of its kind on screen).
def click_select(m:float2):
    let add = shift_held() and sel_building == 0
    sel_building = 0
    sel_foreign = 0
    let i = unit_at_screen(m, true)
    if i >= 0 and u_owner[i] == ME:
        let dbl = u_kind[i] == last_click_kind and gl.time() - last_click_at < 0.4 and magnitude(m - last_click_at_m) < 12.0
        last_click_at = if dbl: -10.0 else: gl.time()  // (a third click starts over)
        last_click_at_m = m
        last_click_kind = u_kind[i]
        if dbl: select_kind_on_screen(u_kind[i], add)
        elif not add: selected = [ u_id[i] ]
        elif contains(selected, u_id[i]): selected = filter(selected) id: id != u_id[i]
        else: selected.push(u_id[i])
        say(ME, "select")
        return
    if add: return
    selected = []::int
    let ground = building_at(order_milli(m))
    var b = building_drawn_at(m, true)  // (the frontmost drawn there: a tower's top, over the ground behind it)
    if b < 0 and ground >= 0 and b_owner[ground] == ME: b = ground
    if b < 0:  // nothing of mine: what isn't mine, to look at
        let f = if i >= 0: i else: unit_at_screen(m, false)
        if f >= 0:
            sel_foreign = u_id[f]
            return
        b = building_drawn_at(m, false)
        if b < 0 and ground >= 0 and building_seen(ground): b = ground
    if b >= 0: sel_building = b_id[b]

// What's shown goes when it dies or is back in the fog; a foreign unit also when I select something of mine.
def drop_lost_selection():
    let b = b_index_of(sel_building)
    if b < 0 or not building_seen(b): sel_building = 0
    let i = index_of(sel_foreign)
    if i < 0 or selected.length or sel_building != 0 or not (teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i]))): sel_foreign = 0

def box_select(a:float2, b:float2):
    let lo = float2 { min(a.x, b.x), min(a.y, b.y) }
    let hi = float2 { max(a.x, b.x), max(a.y, b.y) }
    if not shift_held() or sel_building != 0: selected = []::int  // (shift adds to the selection)
    sel_building = 0
    sel_foreign = 0
    for(u_x.length) i:
        if u_owner[i] == ME:
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])))
            if s.x >= lo.x and s.x <= hi.x and s.y >= lo.y and s.y <= hi.y and not contains(selected, u_id[i]): selected.push(u_id[i])
    if selected.length: say(ME, "select")

var arming_attack = false   // the Attack-move button (or R): the next left click is where
var arming_ability = false  // the race's ability button: the next left click is where
var pad_lb_held = false     // LB held on a pad (game/pad.lobster): orders queue, A adds to the selection

// The armed order (attack-move or the race's ability) given at m.
def give_armed(m:float2):
    if arming_attack: order(m, true)
    else:
        let mm = mouse_milli()
        issue_cmd(ME, CMD_ABILITY, selected_units(), int(mm.x), int(mm.y), 0, 0)
        say(ME, "ack")
    arming_attack = false
    arming_ability = false

// The map bridge whose deck covers cell c, or -1.
def bridge_on(c:int) -> int:
    for(br_cells) cells, k:
        if contains(cells, c): return k
    return -1

// Does building b take in what unit i carries?
def takes_in(b:int, i:int) -> bool: return u_carry[i] > 0 and u_carry_kind[i] > 0 and bt_drop[b_kind[b]][u_carry_kind[i] - 1] != 0

// The right click (sim_debug.smart_order): what's under the mouse decides the order. Our animals go into our
// pen or walk; the rest attack-move (A held, or armed), attack a foe or hunt, slaughter our sheep (workers),
// attack a foe's building, gather, rebuild a broken bridge, mend, wall up our breach, climb our wall, help
// build, trade at a market, drop off, reseed a fallow farm, go inside our building, or move.
def order(m:float2, attack_move:bool = false):
    let mm = order_milli(m)
    let x = int(mm.x)
    let y = int(mm.y)
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return
    let q = if gl.button("left shift") >= 1 or pad_lb_held: 1 else: 0  // (shift, or LB held on a pad: queued)
    let rallying = b_index_of(sel_building)
    if rallying >= 0 and b_owner[rallying] == ME and not selected.length:
        issue_cmd(ME, CMD_RALLY, []::int, sel_building, x, y, 0)
        return
    let all = selected_units()
    if not all.length: return
    say(ME, "ack")
    let herd = filter(all) id: is_animal(index_of(id))
    let ids = filter(all) id: not is_animal(index_of(id))
    let workers = selected_workers()
    let c = cell_of(x, y)
    let b = building_at(mm)
    let foe = unit_at_screen(m, false)
    let mine = unit_at_screen(m, true)
    if herd.length:
        if b >= 0 and b_owner[b] == ME and b_done[b] == 1 and is_pen(b): issue_cmd(ME, CMD_PEN, herd, b_id[b], 0, 0, 0)
        else: issue_cmd(ME, CMD_MOVE, herd, x, y, 0, 0, q)  // (our sheep only ever walk)
    if not ids.length: return
    let others = filter(ids) id: not contains(workers, id)
    let bridge = bridge_on(c)
    let am = attack_move or gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1  // (Ctrl: attack-move; A is the camera's)
    if am and bridge >= 0 and br_up[bridge] == 1 and foe < 0:
        issue_cmd(ME, CMD_ATTACK, ids, br_id[bridge], 0, 0, 0, q)  // attack-click a bridge: break it
    elif am:
        issue_cmd(ME, CMD_ATTACK_MOVE, ids, x, y, 0, 0, q)
    elif foe >= 0:
        issue_cmd(ME, CMD_ATTACK, ids, u_id[foe], 0, 0, 0, q)  // a foe, or an animal to hunt
    elif mine >= 0 and u_owner[mine] == ME and is_animal(mine) and workers.length:
        issue_cmd(ME, CMD_ATTACK, ids, u_id[mine], 0, 0, 0, q)  // slaughter one of our sheep for its food
    elif b >= 0 and is_enemy(b_owner[b], ME) and fog[ME][c] != 0:
        issue_cmd(ME, CMD_ATTACK, ids, b_id[b], 0, 0, 0, q)
    elif res_at(c) != 0 and workers.length:
        issue_cmd(ME, CMD_GATHER, workers, c, 0, 0, 0, q)
        if others.length: issue_cmd(ME, CMD_MOVE, others, x, y, 0, 0, q)
    elif bridge >= 0 and br_up[bridge] == 0 and workers.length:
        issue_cmd(ME, CMD_HELP_BUILD, ids, br_id[bridge], 0, 0, 0, q)  // rebuild a broken bridge
    elif mine >= 0 and workers.length and can_mend(ME, u_id[mine]):
        issue_cmd(ME, CMD_REPAIR, ids, u_id[mine], 0, 0, 0, q)  // mend our siege engine
    elif b < 0 and workers.length and rubble.get(c) and rubble.get(c, []::int)[1] == ME and not build_barred(ME, rubble.get(c, []::int)[2]):
        let r = rubble.get(c, []::int)  // wall up our breach again
        issue_cmd(ME, CMD_BUILD, ids, r[2], r[3], r[4], r[5], q)
    elif b >= 0 and workers.length and can_mend(ME, b_id[b]):
        issue_cmd(ME, CMD_REPAIR, ids, b_id[b], 0, 0, 0, q)  // mend our damaged building
    elif b >= 0 and places(c) > 0 and teams[b_owner[b]] == teams[ME] and not workers.length:
        issue_cmd(ME, CMD_MOVE, ids, x, y, 0, 0, q)  // up onto our wall
    elif b >= 0 and b_owner[b] == ME and b_done[b] == 0:
        issue_cmd(ME, CMD_HELP_BUILD, ids, b_id[b], 0, 0, 0, q)
    elif b >= 0 and is_market(b) and not is_enemy(b_owner[b], ME) and (filter(ids) id: t_trader[u_kind[index_of(id)]] != 0).length:
        issue_cmd(ME, CMD_ROUTE, ids, b_id[b], 0, 0, 0)  // trade carts: trade with that market
    elif b >= 0 and b_owner[b] == ME and b_done[b] == 1 and (filter(ids) id: takes_in(b, index_of(id))).length:
        issue_cmd(ME, CMD_DROP_OFF, ids, b_id[b], 0, 0, 0, q)  // take what they carry in
    elif b >= 0 and pool[c] >= 0 and b_owner[b] == ME:
        issue_cmd(ME, CMD_RESEED, ids, b_id[b], 0, 0, 0)  // a fallow farm of ours
    elif b >= 0 and b_owner[b] == ME and room(b) > 0 and (filter(ids) id: can_hold(b, index_of(id))).length:
        issue_cmd(ME, CMD_GARRISON, ids, b_id[b], 0, 0, 0, q)  // inside our Town Center or tower
    else:
        issue_cmd(ME, CMD_MOVE, ids, x, y, 0, 0, q)

// What player 0 may build clock_s: (type) in menu order.
def buildable() -> [int]:
    let out = []::int
    for(bt_name) name, k:
        if not build_barred(ME, k) and not bt_special[k] and name != "wonder": out.push(k)
    return out

def trainable(b:int) -> [int]:
    return bm_trains[ME][b_kind[b]]

let RESEARCH_KEYS = [ "q", "e", "r", "t", "y", "f", "g", "h", "j" ]  // (not W A S D: the camera's)

// The research building b offers player 0 now (not done, not queued, open to its race, its age and
// the one before it reached; affordable or not), in research order.
def offered(b:int) -> [int]:
    let out = []::int
    for(research) item, r:
        if item.building == b_kind[b] and researched[ME][r] == 0 and (item.after < 0 or researched[ME][item.after] != 0) and
            item.line_has[ME] and (item.before[ME] < 0 or researched[ME][item.before[ME]] != 0) and ages[ME] >= item.age and
            item.open[ME] and not tech_queued(ME, r): out.push(r)
    return out

def research_name(r:int) -> string: return research_names.get(r, research[r].id)

def place_at() -> int, int:
    let mm = mouse_milli()
    let s = bt_size[placing]
    return int(mm.x) / TILE - (s - 1) / 2, int(mm.y) / TILE - (s - 1) / 2

def place_cell() -> int2:
    let cx, cy = place_at()
    return int2 { cx, cy }

// Lay the foundation being placed at the mouse with the selected workers (shift: keep placing).
def place_here(more:bool):
    let cx, cy = place_at()
    let ws = selected_workers()
    if ws.length: issue_cmd(ME, CMD_BUILD, ws, placing, cx, cy, 0, if more: 1 else: 0)
    if not more: placing = -1

// The cells of a line from a to b (straight or diagonal: the cells a line through them crosses).
def wall_cells(a:int2, b:int2) -> [int2]:
    let out = []::int2
    let n = max(abs(b.x - a.x), abs(b.y - a.y))
    for(n + 1) k:
        let c = int2 { a.x + int(round(float((b.x - a.x) * k) / float(max(n, 1)))), a.y + int(round(float((b.y - a.y) * k) / float(max(n, 1)))) }
        if not out.length or out[out.length - 1] != c: out.push(c)
    return out

// A wall or gate dragged from a to b: a foundation a cell, built in order by the selected workers (more: keep placing).
def place_wall(a:int2, b:int2, more:bool):
    let ws = selected_workers()
    if ws.length:
        for(wall_cells(a, b)) c, k: issue_cmd(ME, CMD_BUILD, ws, placing, c.x, c.y, 0, if more or k > 0: 1 else: 0)
    wall_from = int2 { -1, -1 }
    if not more: placing = -1

def shift_held(): return gl.button("left shift") >= 1 or gl.button("right shift") >= 1

// Train the building's nth unit (shift: five, as far as the money and the queue go).
def train_slot(n:int):
    let b = b_index_of(sel_building)
    if b >= 0 and b_owner[b] == ME:
        let tr = trainable(b)
        if n < tr.length:
            for(if shift_held(): 5 else: 1): issue_cmd(ME, CMD_TRAIN, []::int, sel_building, tr[n], 1, 0)

def store_group(n:int): groups.set(n, selected_units())

def recall_group(n:int):
    let ids = filter(groups.get(n, [])) id: index_of(id) >= 0
    if not ids.length: return
    selected = ids
    sel_building = 0
    if last_group == n and gl.time() - last_group_at < 0.4:
        let i = index_of(ids[0])
        cam = iso(float(u_x[i]), float(u_y[i]))
    last_group = n
    last_group_at = gl.time()

def keys():
    if gl.button("m") == 1: sound_on = not sound_on
    if gl.button("n") == 1 and not in_net_match:  // a new race, mid-match
        typing_race = true
        gl.start_text_input(int2 { 0, 0 }, int2 { 400, 40 })
        gl.set_text_input("")
        return
    let digit = map(9) n: gl.button("{n + 1}") == 1
    // Control groups (sim_debug._control_group): Ctrl (or Cmd) + a number keeps the selected units;
    // the number brings them back (when no building's panel takes it), twice quickly to look at them.
    let ctrl = gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1 or gl.button("left gui") >= 1 or gl.button("right gui") >= 1
    for(digit) hit, n:
        if hit and ctrl:
            store_group(n)
            return
        let shown = b_index_of(sel_building)
        if hit and not build_menu and (shown < 0 or b_owner[shown] != ME):
            recall_group(n)
            return
    if gl.button("b") == 1 and selected_workers().length: build_menu = not build_menu
    if build_menu:
        let menu = buildable()
        for(digit) hit, n:
            if hit and n < menu.length:
                placing = menu[n]
                build_menu = false
        return
    let b = b_index_of(sel_building)
    if b >= 0 and b_owner[b] == ME:
        for(digit) hit, n:
            if hit: train_slot(n)
        if gl.button("u") == 1: issue_cmd(ME, CMD_AGE_UP, []::int, sel_building, 0, 0, 0)
        let offer = offered(b)
        for(RESEARCH_KEYS) key, n:
            if gl.button(key) == 1 and n < offer.length: issue_cmd(ME, CMD_RESEARCH, []::int, sel_building, offer[n], 0, 0)
        if gl.button("x") == 1 and b_queue[b].length: issue_cmd(ME, CMD_CANCEL, []::int, sel_building, b_queue[b].length - 1, 0, 0)
    if gl.button("x") == 1 and b < 0 and selected.length: issue_cmd(ME, CMD_STOP, selected_units(), 0, 0, 0, 0)
    if b < 0 and selected_soldiers().length:
        if gl.button("r") == 1: arming_attack = true  // R then click: attack-move there
        let hk = ability_hotkey()
        if hk != "" and gl.button(hk) == 1 and ability_users().length: arming_ability = true

// The selected units that fight (not workers, not animals).
def selected_soldiers() -> [int]: return filter(selected_units()) id: t_worker[u_kind[index_of(id)]] == 0 and t_animal[u_kind[index_of(id)]] == 0

// Our race's ability (data: its name, desc, hotkey...), or nil; and the selected units that may use it.
def my_ability() -> JV?:
    let ab = get(su_sides[ME], "ability")
    return if ab and ab.kind == J_OBJ and gstr(ab, "kind", "") != "": ab else: nil
def ability_hotkey() -> string:
    let ab = my_ability()
    return if ab: gstr(ab, "hotkey", "").lowercase() else: ""
def ability_users() -> [int]: return filter(selected_units()) id: t_ability[u_kind[index_of(id)]] != 0

def mouse():
    let m = mouse_px()
    if arming_attack or arming_ability:  // the armed order goes where the next left click is
        if gl.button("mouse1") == 1:
            give_armed(m)
            return
        if gl.button("mouse3") == 1 or gl.button("escape") == 1:
            arming_attack = false
            arming_ability = false
            return
    if placing < 0: wall_from = int2 { -1, -1 }
    if placing >= 0:
        if touch_play: return      // (touch places for itself: game/touch.lobster)
        if bt_line[placing] != 0:  // walls and gates are dragged: press at one end, release at the other
            if gl.button("mouse1") == 1: wall_from = place_cell()
            elif gl.button("mouse1") == 0 and wall_from.x >= 0: place_wall(wall_from, place_cell(), gl.button("left shift") >= 1)
        elif gl.button("mouse1") == 1: place_here(gl.button("left shift") >= 1)
        if gl.button("mouse3") == 1 or gl.button("escape") == 1: placing = -1
        return
    if in_minimap(m):
        if gl.button("mouse1") >= 1: cam = (m - mm_top()) / mm_scale()  // look there
        if gl.button("mouse3") == 1:
            let p = iso_inv((m - mm_top()) / mm_scale())
            let ids = selected_units()
            if ids.length:
                say(ME, "ack")
                issue_cmd(ME, if gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1: CMD_ATTACK_MOVE else: CMD_MOVE, ids, int(p.x), int(p.y), 0, 0, if gl.button("left shift") >= 1: 1 else: 0)
        return
    if gl.button("mouse1") == 1 and not touch_play:  // (touch selects for itself; a touch here is on the HUD)
        drag_from = m
        dragging = true
    if dragging and gl.button("mouse1") == 0:
        dragging = false
        if magnitude(m - drag_from) < 6.0: click_select(m)
        else: box_select(drag_from, m)
    if gl.button("mouse3") == 1: order(m)

def scroll():
    let ws = float(gl.window_size())
    let m = mouse_px()
    let sp = 1400.0 * gl.delta_time() / zoom
    var d = float2_0
    if gl.button("left") >= 1 or gl.button("a") >= 1: d.x -= 1.0  // (the arrows or WASD)
    if gl.button("right") >= 1 or gl.button("d") >= 1: d.x += 1.0
    if gl.button("up") >= 1 or gl.button("w") >= 1: d.y -= 1.0
    if gl.button("down") >= 1 or gl.button("s") >= 1: d.y += 1.0
    let inside = m.x > 0.0 and m.y > 0.0 and m.x < ws.x and m.y < ws.y   // (outside the window the mouse reads 0, 0)
    if inside and shot == "" and rec_dir == "" and gl.window_focused():  // (the mouse is free now: not while it works in another app)
        if m.x <= 3.0: d.x -= 1.0
        if m.y <= 3.0: d.y -= 1.0
        if m.x >= ws.x - 4.0: d.x += 1.0
        if m.y >= ws.y - 4.0: d.y += 1.0
    cam += d * sp
    let wheel = gl.mousewheel_delta()
    if wheel > 0: zoom = min(8.0, zoom + 1.0)
    if wheel < 0: zoom = max(1.0, zoom - 1.0)

// ------------------------------------------------------------------ marks and the HUD

// An ellipse on the ground (2:1) round p, about 1.6 px thick at any size: line segments through the UI layer's
// meshes (gl.open_circle goes astray after the sprites' shader, as gl.rect and gl.line do in this build).
def draw_ring(p:float2, r:float, col:float4):
    let n = 48
    ui_batch():
        for(n) k:
            let a0 = 360.0 * float(k) / float(n)
            let a1 = 360.0 * float(k + 1) / float(n)
            ui_line(p + float2 { cos(a0) * r, sin(a0) * r * 0.5 }, p + float2 { cos(a1) * r, sin(a1) * r * 0.5 }, 1.6, col)

// A shot's key in shot_from and shot_mouth, at its place in shots. (Two guns can fire together.)
def shot_key(o:int) -> int: return (shots[o + SHOT_BY] * 65536 + shots[o + SHOT_LAND] % 65536) * 8 + shots[o + SHOT_MOUNT]

// Forget the landed shots. One still flying keeps its start: forgotten, it would fire again and start over (#265).
def forget_landed_shots():
    let was_from, was_mouth = shot_from, shot_mouth
    shot_from = dictionary<int, int>(1024)
    shot_mouth = dictionary<int, float2>(1024)
    for(shots.length / SHOT_STRIDE) k:
        let key = shot_key(k * SHOT_STRIDE)
        if was_from.get(key, -1) >= 0:
            shot_from.set(key, was_from.get(key, -1))
            shot_mouth.set(key, was_mouth.get(key, float2 { 0.0, -12.0 }))

// Shots in flight (shots.gd, combat_fx.gd): each weapon's shot on its arc from the shooter's body to
// where it lands, for the sim's flight, with a speck of shadow under it. Canvas units (under the 1.5 scale).
def draw_shots(alpha:float):
    gl.set_shader("color")
    let n = shots.length / SHOT_STRIDE
    for(n) k:
        let o = k * SHOT_STRIDE
        let land = shots[o + SHOT_LAND]
        let mount = shots[o + SHOT_MOUNT]
        let key = shot_key(o)
        var t_from = shot_from.get(key, -1)
        let firstseen = t_from < 0
        if firstseen:
            t_from = tick - 1
            shot_from.set(key, t_from)
            shot_mouth.set(key, muzzle_of(shots[o + SHOT_BY], mount))
        let flight = float(max(1, land - t_from)) / 20.0
        let ax = shots[o + SHOT_X]
        let ay = shots[o + SHOT_Y]
        let sx = shots[o + SHOT_X0]
        let sy = shots[o + SHOT_Y0]
        if seen_at(ax, ay) or seen_at(sx, sy):
            let src = shots[o + SHOT_SRC]
            let own = if src >= 0 and mount < t_mounts[src].length: t_mounts[src][mount].shot else: ""
            let st = shot_style(if own != "": own elif src >= 0: unit_shotk.get(src, "arrow") else: "arrow")
            let t = shot_drawn_u((float(tick - t_from) + alpha) / 20.0, flight, st.muzzle.flash > 0.0)
            let a = ground_at(sx, sy) + shot_mouth.get(key, float2 { 0.0, -12.0 })
            let to_j = index_of(shots[o + SHOT_TO])
            let b = ground_at(ax, ay) - float2 { 0.0, 10.0 + (if to_j >= 0: air_lift(u_kind[to_j]) / 1.5 else: 0.0) }
            if firstseen and seen_at(sx, sy):  // (a gun firing out of the fog shows only its shell)
                fx_muzzle(st, a, ground_at(sx, sy))
                if st.muzzle.recoil > 0.0: unit_kick.set(shots[o + SHOT_BY] * 16 + mount, float2 { st.muzzle.recoil, clock_s })
            if st.plain():
                if t >= 0.0: draw_bolt(st, a, b, t, 1.0)  // (launched late: it looks faster, and lands on the sim's tick)
            elif firstseen: fx_fire(st, a, b, float(land - t_from) / 20.0, if src >= 0: unit_shot.get(src, "") else: "")
    draw_tracers()
    if tick % 200 == 0: forget_landed_shots()

// Health bars over hurt units you can see, and over the selected.
def draw_bars(alpha:float):
    for(u_x.length) i:
        let k = u_kind[i]
        if u_hp[i] < t_hp[k] and (teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i]))):
            let px, py = prev_pos(i)
            let p = iso(px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha)
            let hpk = float(u_hp[i]) / float(max(1, t_hp[k]))
            ui_fill(p + float2 { -9.0, -38.0 - air_lift(k) }, float2 { 18.0, 3.0 }, float4 { 0.0, 0.0, 0.0, 0.6 })
            ui_fill(p + float2 { -9.0, -38.0 - air_lift(k) }, float2 { 18.0 * hpk, 3.0 }, float4 { 1.0 - hpk, 0.3 + 0.6 * hpk, 0.15, 1.0 })

def ring_of(owner:int) -> float4: return if is_foe(owner, ME): float4 { 0.9, 0.22, 0.16, 1.0 } else: float4 { 0.95, 0.91, 0.79, 1.0 }

// The selection rings, on the ground under the selected units and building (drawn in the sorted world, before
// anything standing: a unit stands in its ring, and what's in front of it covers it).
// Rings on raised ground (raised) are drawn after the hill's tops, which would paint over them.
def draw_rings(alpha:float, raised:bool):
    gl.set_shader("color")
    def ring(m:float2, r:float, col:float4):
        if (lift_at(m.x, m.y) > 0.0) == raised: draw_ring(on_ground(m), r, col)
    for(selected_units()) id:
        let i = index_of(id)
        let px, py = prev_pos(i)
        ring(float2 { px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha }, float(u_radius[i]) * 0.068 + 3.0, float4 { 0.95, 0.91, 0.79, 1.0 })
    let f = index_of(sel_foreign)
    if f >= 0:
        let px, py = prev_pos(f)
        ring(float2 { px + (u_x[f] - px) * alpha, py + (u_y[f] - py) * alpha }, float(u_radius[f]) * 0.068 + 3.0, ring_of(u_owner[f]))
    let b = b_index_of(sel_building)
    if b >= 0:
        ring(float2 { float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500) }, float(b_sx[b]) * 68.0 * 0.75, ring_of(b_owner[b]))

def draw_marks(alpha:float):
    gl.set_shader("color")
    if not rec_clean: draw_bars(alpha)
    for(selected_units()) id:
        let i = index_of(id)
        let px, py = prev_pos(i)
        let p = iso(px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha)
        let hpk = float(u_hp[i]) / float(max(1, t_hp[u_kind[i]]))
        ui_fill(p + float2 { -9.0, -38.0 }, float2 { 18.0, 3.0 }, float4 { 0.0, 0.0, 0.0, 0.6 })
        ui_fill(p + float2 { -9.0, -38.0 }, float2 { 18.0 * hpk, 3.0 }, float4 { 1.0 - hpk, 0.3 + 0.6 * hpk, 0.15, 1.0 })
    if placing >= 0:
        let here = place_cell()
        let s = bt_size[placing]
        for(if bt_line[placing] != 0 and wall_from.x >= 0: wall_cells(wall_from, here) else: [ here ]) g:
            let ok = can_place(ME, placing, g.x, g.y)
            let pts = map([ int2 { 0, 0 }, int2 { s, 0 }, int2 { s, s }, int2 { 0, s } ]) d: iso(float((g.x + d.x) * 1000), float((g.y + d.y) * 1000))
            gl.color(if ok: float4 { 0.3, 0.9, 0.3, 0.35 } else: float4 { 0.9, 0.2, 0.2, 0.35 }):
                gl.polygon(pts)

// ------------------------------------------------------------------ the minimap (src/view/minimap.gd)
// The map as a diamond at the bottom right (MM_SIZE UI px wide, half as tall, times hud_s()): the ground
// mesh again, small, in a frame of the look's metal (lit on its upper edges, in shade below, a stud at each
// point); your buildings as squares and units as dots in team colours (enemies only where you see them,
// animals pale); the camera's view outlined. A click there looks there (only the diamond takes it).

let MM_SIZE = 300.0  // its width in UI px (minimap.gd's SIZE)
let MM_RIM = 12.0    // the frame round the diamond

// The art's density (#358): on a screen where the default view draws a world art px over more than 2 device px (a
// Retina Mac), units, buildings and props bake at that many texture px a world px (2.4 at most), so a baked pixel is
// a device pixel (a voxel unit's voxel exactly: a body unit is 1.1 world px). Other screens keep the base, 2.
def art_density(zoom0:float):
    if zoom0 <= 2.0: return
    let z = min(zoom0, 2.4)  // (at most a Retina Mac's: a 5K screen's 4 would bake 3 times today's pixels)
    ART_SCALE = ART_BASE * z
    ART_K = z
    WB_ART = ART_SCALE
    WB_PX = 32.0 / 0.70710678 * WB_ART
    FX_ART_PX = ART_SCALE
    vx_set_res(1.1 * z)
    VX_DRAW_K = 1.1 / vx_RES
    VX_ATLAS = 4096

// Screen px per canvas unit: the diamond (48 (W + H) canvas units wide) MM_SIZE wide.
def mm_scale() -> float: return MM_SIZE * hud_s() / (48.0 * float(W + H))

// Its box's top left: the panel's margin and the frame from the window's bottom right (sim_debug: offset
// -SIZE - 24, -SIZE / 2 - 20).
def mm_box() -> float2:
    let ws = float(gl.window_size())
    let s = hud_s()
    return float2 { ws.x - (MM_SIZE + 24.0) * s, ws.y - (MM_SIZE * 0.5 + 20.0) * s }

// The map's (0, 0) corner, the diamond's top point, on the screen.
def mm_top() -> float2: return mm_box() + float2 { 48.0 * float(H) * mm_scale(), 0.0 }

def mm_point(p:float2) -> float2: return mm_top() + p * mm_scale()

def in_minimap(m:float2) -> bool:
    let s = hud_s()
    let c = mm_box() + float2 { MM_SIZE * 0.5, MM_SIZE * 0.25 } * s
    return abs(m.x - c.x) / (MM_SIZE * 0.5 * s) + abs(m.y - c.y) / (MM_SIZE * 0.25 * s) <= 1.0

def mm_poly(pts:[float2], cols:[float4]):
    ui_batch_flush()
    gl.set_shader("color_attr")
    gl.draw_mesh("PC", map(pts) p: float3 { p.x, p.y, 0.0 }, cols, []::float3, []::float2, []::float2,
                 if pts.length == 4: [ 0, 1, 2, 0, 2, 3 ] else: [ 0, 1, 2 ])
    gl.set_shader("color")

// The diamond's frame (minimap.gd's _draw_frame).
def mm_frame():
    let s = hud_s()
    let b = mm_box()
    let size = MM_SIZE * s
    let rim = MM_RIM * s
    let c = b + float2 { size * 0.5, size * 0.25 }
    let o = [ float2 { c.x, b.y - rim * 0.6 }, float2 { b.x + size + rim, c.y }, float2 { c.x, b.y + size * 0.5 + rim * 0.6 }, float2 { b.x - rim, c.y } ]
    let i = [ float2 { c.x, b.y - 1.0 }, float2 { b.x + size + 1.5, c.y }, float2 { c.x, b.y + size * 0.5 + 1.0 }, float2 { b.x - 1.5, c.y } ]
    mm_poly(map(o) p: p + float2 { 3.0, 6.0 } * s, map(4): float4 { 0.0, 0.0, 0.0, 0.4 })
    // the frame's material, painted by the UI's shader on the diamond
    ui_batch_flush()
    gl.set_shader("uimat")
    gl.set_uniform("mcol", ui_look.frame)
    gl.set_uniform("kind", 1.0)
    gl.set_uniform("win_h", float(gl.window_size().y))
    gl.set_uniform("px", max(1.0, ui()))
    gl.draw_mesh("P", map(o) p: float3 { p.x, p.y, 0.0 }, []::float4, []::float3, []::float2, []::float2, [ 0, 1, 2, 0, 2, 3 ])
    gl.set_shader("color")
    let light = [ float4 { 1.0, 0.95, 0.85, 0.3 }, float4 { 0.0, 0.0, 0.0, 0.35 }, float4 { 0.0, 0.0, 0.0, 0.5 }, float4 { 1.0, 0.95, 0.85, 0.15 } ]
    for(4) k:
        let l = light[k]
        let none = float4 { l.x, l.y, l.z, 0.0 }
        mm_poly([ o[k], o[(k + 1) % 4], i[(k + 1) % 4], i[k] ], [ l, l, none, none ])
    mm_poly(i, map(4): float4 { 0.07, 0.05, 0.03, 1.0 })
    for(4) k:
        ui_line(o[k], o[(k + 1) % 4], 1.5, float4 { 0.0, 0.0, 0.0, 0.75 })
        ui_line(i[k], i[(k + 1) % 4], 1.5, float4 { 0.0, 0.0, 0.0, 0.7 })

def mm_studs():
    let s = hud_s()
    let b = mm_box()
    let size = MM_SIZE * s
    let rim = MM_RIM * s
    let c = b + float2 { size * 0.5, size * 0.25 }
    for([ float2 { c.x, b.y - rim * 0.6 }, float2 { b.x + size + rim, c.y }, float2 { c.x, b.y + size * 0.5 + rim * 0.6 }, float2 { b.x - rim, c.y } ]) p:
        ui_stud(p, 4.8 * s, ui_look.metal)

def draw_minimap():
    let gm = ground_mesh
    if not gm: return
    let s = hud_s()
    mm_frame()
    ui_batch_flush()
    gl.translate(mm_top()):
        gl.scale(mm_scale()):
            gl.set_shader("color_attr")
            gl.render_mesh(gm)
    gl.set_shader("color")
    let per_tile = MM_SIZE * s / float(W + H) * 2.0  // a tile's width on it
    for(b_id.length) b:
        let cell = b_cy[b] * W + b_cx[b]
        if teams[b_owner[b]] == teams[ME] or fog[ME][cell] != 0:
            let p = mm_point(iso(float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500)))
            let r = max(3.0 * s, float(max(b_sx[b], b_sy[b])) * per_tile * 0.45)
            ui_fill(p - float2 { r, r * 0.6 }, float2 { r * 2.0, r * 1.2 }, team_col(b_owner[b]))
    for(u_x.length) i:
        if teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i])):
            let p = mm_point(iso(float(u_x[i]), float(u_y[i])))
            let tc = team_col(u_owner[i])
            let dot = if u_owner[i] == gaia or t_animal[u_kind[i]] != 0: float4 { 0.85, 0.82, 0.72, 1.0 } else: float4 { tc.x + (1.0 - tc.x) * 0.2, tc.y + (1.0 - tc.y) * 0.2, tc.z + (1.0 - tc.z) * 0.2, 1.0 }
            ui_fill(p - float2_1 * s, float2_1 * 2.0 * s, dot)
    let ws = float(gl.window_size())
    let corners = map([ float2_0, float2 { ws.x, 0.0 }, ws, float2 { 0.0, ws.y } ]) c: mm_point(from_screen(c))
    for(4) k: ui_line(corners[k], corners[(k + 1) % 4], 2.0 * s, float4 { 1.0, 1.0, 1.0, 0.9 })
    mm_studs()

def text_at(p:float2, s:string):
    gl.translate(p): gl.text(s)

def stock_text() -> string:
    var s = ""
    for(resource_names) r, k:
        s += "{r} {stock[k][ME]}   "
    return s + "pop {pop[ME]}/{pop_cap[ME]}   age {ages[ME]}"

def unit_name(k:int) -> string: return unit_names.get(k, t_slot[k])
def bname(k:int) -> string: return building_names.get(k, bt_name[k])

var end_watching = false  // the end screen put away (Keep watching)

def draw_hud(paused:bool, speed:float):
    gl.set_shader("color")
    let ws = float(gl.window_size())
    let u = ui()
    ui_batch(): draw_topbar(speed, paused)  // (game/topbar.lobster; its fills in as few draws as can be)
    gl.set_shader("color")                  // (placing: the panel's info line says how)
    if winner >= 0 and end_watching:        // (the end screen put away: the result stays up while you watch)
        gl.set_font_size(int(48.0 * u))
        gl.color(float4 { 1.0, 0.85, 0.3, 1.0 }):
            text_at(ws / 2.0 - float2 { 160.0, 40.0 }, if winner == teams[ME]: "Victory!" else: "Defeat")
    ui_batch(): draw_minimap()
    if dragging:
        let m = mouse_px()
        let lo = float2 { min(m.x, drag_from.x), min(m.y, drag_from.y) }
        let hi = float2 { max(m.x, drag_from.x), max(m.y, drag_from.y) }
        gl.color(float4 { 0.95, 0.91, 0.79, 0.8 }):
            for([ [ lo, float2 { hi.x, lo.y } ], [ float2 { hi.x, lo.y }, hi ], [ hi, float2 { lo.x, hi.y } ], [ float2 { lo.x, hi.y }, lo ] ]) e:
                ui_line(e[0], e[1], 1.5, float4 { 0.95, 0.91, 0.79, 0.8 })

// ------------------------------------------------------------------ the self-test

var test_step = 0
var test_log = ""
var test_foe = 0  // the enemy unit the self-test looks at

def screen_of_cell(c:int) -> float2: return to_screen(iso(float((c % W) * 1000 + 500), float((c / W) * 1000 + 500)))

def expect_ok(ok:bool, what:string):
    test_log += (if ok: "PASS " else: "FAIL ") + what + "\n"

// The nearest cell to (x, y) (tiles) whose test passes, or -1.
def nearest_cell(x:int, y:int, test) -> int:
    var best = -1
    var best_d = 1 << 30
    for(W * H) c:
        if test(c):
            let d = (c % W - x) * (c % W - x) + (c / W - y) * (c / W - y)
            if d < best_d:
                best_d = d
                best = c
    return best

def self_test() -> bool:
    let tc = town_center(ME)
    let tx = b_cx[tc] + 1
    let ty = b_cy[tc] + 1
    let ws = float(gl.window_size())
    if test_step == 0 and clock_s >= 1.0:
        box_select(float2 { 1.0, 1.0 }, ws - 1.0)
        expect_ok(selected.length >= 3, "a drag over the screen selects my {selected.length} units")
        let wood = nearest_cell(tx, ty) c: res_at(c) == resource_index("wood") + 1
        let some = selected.slice(0, 2)
        selected = some
        fake_mouse = screen_of_cell(wood)
        order(fake_mouse)
        test_step++
    elif test_step == 1 and clock_s >= 2.0:
        let pick = selected_units()
        expect_ok((filter(pick) id: u_task[index_of(id)] == GATHER).length == pick.length, "right click on reeds sends the workers gathering")
        let all = filter(u_id) id: u_owner[index_of(id)] == ME and t_worker[u_kind[index_of(id)]]
        selected = [ all[all.length - 1] ]
        placing = btype_named("house")
        let spot = nearest_cell(tx, ty) c: can_place(ME, placing, c % W - 0, c / W - 0) and (c % W - tx) * (c % W - tx) + (c / W - ty) * (c / W - ty) > 9
        fake_mouse = screen_of_cell(spot)
        place_here(false)
        test_step++
    elif test_step == 2 and clock_s >= 3.0:
        expect_ok((filter(b_id.length) b: b_owner[b] == ME and bt_name[b_kind[b]] == "house").length >= 1, "B, a house and a click lays a house down")
        fake_mouse = screen_of_cell(b_cy[tc] * W + b_cx[tc] + 1)
        click_select(fake_mouse)
        expect_ok(sel_building == b_id[tc], "a click on the Town Center selects it")
        train_slot(0)
        test_step++
    elif test_step == 3 and clock_s >= 4.0:
        expect_ok(b_queue[tc].length >= 1 or pop[ME] > 3, "1 on the Town Center trains a worker")
        let army = filter(u_id) id: u_owner[index_of(id)] == ME
        selected = army.slice(0, 2)
        store_group(2)
        selected = []
        recall_group(2)
        expect_ok(selected.length == 2, "Ctrl+3 keeps two units, 3 brings them back")
        selected = army
        fake_mouse = to_screen(iso(float(tx * 1000 + 4000), float(ty * 1000 + 4000)))
        order(fake_mouse)
        test_step++
    elif test_step == 4 and clock_s >= 4.5:
        expect_ok((filter(selected_units()) id: u_moving[index_of(id)] == 1 or u_task[index_of(id)] != T_NONE).length > 0, "right click on open ground moves them")
        // two workers carrying nothing, right-clicked onto the Town Center: they go inside
        let idle = filter(u_id) id: u_owner[index_of(id)] == ME and t_worker[u_kind[index_of(id)]] != 0 and u_carry[index_of(id)] == 0
        selected = idle.slice(0, 2)
        fake_mouse = screen_of_cell(b_cy[tc] * W + b_cx[tc] + 1)
        order(fake_mouse)
        test_step++
    elif test_step == 5 and clock_s >= 9.0:
        expect_ok(b_inside[tc].length > 0, "right click on the Town Center sends workers inside ({b_inside[tc].length / REC_SIZE} in)")
        selected = []
        sel_building = b_id[tc]
        for(panel_buttons()) btn:
            if btn.act == 12: press(btn)
        test_step++
    elif test_step == 6 and clock_s >= 10.0:
        expect_ok(b_inside[tc].length == 0, "Ungarrison brings them out")
        let foe = town_center(1 - ME)
        cam = iso(float(b_cx[foe] * 1000 + b_sx[foe] * 500), float(b_cy[foe] * 1000 + b_sy[foe] * 500))
        test_step++
    elif test_step == 7 and clock_s >= 10.5:
        let foe = town_center(1 - ME)
        click_select(screen_of_cell(b_cy[foe] * W + b_cx[foe]))
        expect_ok(sel_building == 0, "a click on an enemy building in the fog selects nothing")
        reveal = true
        // (a cell of it with no unit in the way)
        let clear = find(b_sx[foe] * b_sy[foe]) n: unit_at_screen(screen_of_cell((b_cy[foe] + n / b_sx[foe]) * W + b_cx[foe] + n % b_sx[foe]), false) < 0
        fake_mouse = screen_of_cell((b_cy[foe] + clear / b_sx[foe]) * W + b_cx[foe] + clear % b_sx[foe])
        click_select(fake_mouse)
        expect_ok(sel_building == b_id[foe], "a click on a visible enemy building selects it")
        test_step++
    elif test_step == 8 and clock_s >= 11.0:
        let foe = town_center(1 - ME)
        expect_ok(panel_hp == b_hp[foe], "the panel shows the enemy building\'s HP ({panel_hp} of {b_hp[foe]})")
        let before = pending.length
        expect_ok(not panel_buttons().length, "an enemy building has no buttons")
        train_slot(0)
        order(fake_mouse)
        expect_ok(pending.length == before, "no orders for an enemy building ({pending.length - before} issued)")
        reveal = false
        test_step++
    elif test_step == 9 and clock_s >= 11.5:
        expect_ok(sel_building == 0, "an enemy building back in the fog lets go of the selection")
        reveal = true
        let foes = filter(u_id.length) i: is_foe(u_owner[i], ME) and t_animal[u_kind[i]] == 0
        let u = foes[0]
        cam = iso(float(u_x[u]), float(u_y[u]))
        test_foe = u_id[u]
        test_step++
    elif test_step == 10 and clock_s >= 12.0:
        let u = index_of(test_foe)
        fake_mouse = to_screen(iso(float(u_x[u]), float(u_y[u])) - float2 { 0.0, 14.0 })
        click_select(fake_mouse)
        expect_ok(sel_foreign == test_foe and not selected.length, "a click on a visible enemy unit shows it, and doesn\'t select it")
        test_step++
    elif test_step == 11 and clock_s >= 12.5:
        let u = index_of(test_foe)
        expect_ok(panel_hp == u_hp[u], "the panel shows the enemy unit\'s HP ({panel_hp} of {u_hp[u]})")
        let before = pending.length
        expect_ok(not panel_buttons().length, "an enemy unit has no buttons")
        order(fake_mouse)
        expect_ok(pending.length == before, "no orders for an enemy unit ({pending.length - before} issued)")
        reveal = false
        test_step++
    elif test_step == 12 and clock_s >= 13.0:
        expect_ok(sel_foreign == 0, "an enemy unit back in the fog lets go of the selection")
        reveal = true
        let wild = filter(u_id.length) i: u_owner[i] == gaia
        let u = wild[wild.length - 1]
        cam = iso(float(u_x[u]), float(u_y[u]))
        test_foe = u_id[u]
        test_step++
    elif test_step == 13 and clock_s >= 13.5:
        let u = index_of(test_foe)
        fake_mouse = to_screen(iso(float(u_x[u]), float(u_y[u])) - float2 { 0.0, 14.0 })
        click_select(fake_mouse)
        expect_ok(sel_foreign == test_foe and not selected.length, "a click on a wild animal shows it, and doesn\'t select it")
        test_step++
    elif test_step == 14 and clock_s >= 14.0:
        expect_ok(panel_hp == u_hp[index_of(test_foe)], "the panel shows the wild animal\'s HP ({panel_hp})")
        print test_log
        return true
    return false

// game: import .game.pad  // (here: it plays through the controls above)
// game: import .game.techtree
// game: import .game.panel
// game: import .game.topbar
// game: import .game.order_marks
// game: import .game.touch          // (here: it plays through the pad, and leaves the panel, top bar and minimap to the mouse)
// game: import .game.techtree_page  // (here: it draws with the panel's portraits and the top bar's icons)
// game: import .game.lobby
// game: import .game.boot

// Control groups shown (Dominic, 2026-10-26: "visible somewhere, at least as a number on the units",
// then "only when you select the group"): a small number by each selected unit that's in a group (its
// lowest), and under the top bar each group's number and how many are in it. Screen space, after the world.
// About the space a short label takes at this font size (gl.text_size doesn't match the drawn text at
// every window scale).
def label_size(s:string, fs:int) -> float2: return float2 { 0.6 * float(fs) * float(s.length), float(fs) }

def outlined_text(p:float2, s:string, col:float4, u:float):
    text_label(p, s, gl.get_font_size(), col, TEXT_FACE, 1.5 * u, float4 { 0.05, 0.04, 0.02, 0.9 })

def draw_groups():
    let keys = sorted_ints_g(groups.get_keys())
    let live = map(keys) n: filter(groups.get(n, [])) id: index_of(id) >= 0
    if not (filter(live) ids: ids.length > 0).length: return
    gl.set_shader("color")
    let u = ui()
    let fs = int(13.0 * u)
    gl.set_font_size(fs)
    let first = dictionary<int, int>(64)
    for(keys) n, k:
        for(live[k]) id:
            if first.get(id, -1) < 0 and contains(selected, id): first.set(id, n)  // (only on what's selected: Dominic)
    let ws = float(gl.window_size())
    for(first.get_keys()) id:
        let i = index_of(id)
        if fog[ME][cell_of(u_x[i], u_y[i])] != 0:
            let at = to_screen(iso(float(u_x[i]), float(u_y[i])) + float2 { -16.0, -40.0 })
            if at.x > 0.0 and at.y > 0.0 and at.x < ws.x and at.y < ws.y:
                let label = string(first.get(id, 0) + 1)
                outlined_text(at - label_size(label, fs) / 2.0, label, float4 { 1.0, 0.88, 0.5, 1.0 }, u)
    var x = 16.0 * u
    let y = topbar_bottom() + 8.0 * u  // under the top bar (game/topbar.lobster)
    let fs2 = int(15.0 * u)
    gl.set_font_size(fs2)
    for(keys) n, k:
        if live[k].length:
            let label = "{n + 1}: {live[k].length}"
            let size = label_size(label, fs2)
            let on = live[k].length == selected.length and (filter(live[k]) id: contains(selected, id)).length == live[k].length
            outlined_text(float2 { x, y }, label, if on: float4 { 1.0, 0.8, 0.3, 1.0 } else: float4 { 0.95, 0.88, 0.65, 1.0 }, u)
            x += size.x + 18.0 * u

// padtest: a fake pad plays a few seconds (tests/pad_check.gd's idea): pan, the circle, the wheel, a house.
var pad_step = 0
var test_pause = false
var pad_paged = false
var pad_spot = float2_0
var pad_houses = 0
def pad_script() -> PadIn:
    let t = clock_s
    let none = PadIn { [ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 ], [] }
    let tc = town_center(ME)
    if pad_step == 0 and t >= 1.0:
        pad_spot = cam
        pad_step++
    if pad_step == 1:
        if t < 1.5: return PadIn { [ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0 ], [] }
        expect_ok(cam.x > pad_spot.x + 50.0, "the left stick pans (camera {pad_spot.x} -> {cam.x})")
        let mine = filter(u_id.length) i: u_owner[i] == ME and t_animal[u_kind[i]] == 0
        cam = iso(float(fold(mine, 0) acc, i: acc + u_x[i]) / float(mine.length), float(fold(mine, 0) acc, i: acc + u_y[i]) / float(mine.length))
        pad_step++
    if pad_step == 2:
        if t < 3.5: return PadIn { none.axes, [ "a" ] }
        pad_step++
        return none
    if pad_step == 3:
        expect_ok(selected_units().length >= 3, "holding A grows a circle that takes {selected_units().length} units")
        store_group(0)
        selected = selected_workers()
        store_group(1)
        let i = index_of(selected[0])
        cam = iso(float(u_x[i]), float(u_y[i]))
        pad_off = float2_0
        test_pause = true  // (the worker stays under the reticle)
        pad_step++
        return none
    if pad_step == 4:
        pad_step++
        return PadIn { none.axes, [ "a" ] }
    if pad_step == 5:
        pad_step++
        return none
    if pad_step == 6 and wheel_pages() > 1 and not pad_paged:  // (more than a page: LB turns it, and back)
        pad_paged = true
        pad_step = 60
        return PadIn { none.axes, [ "leftshoulder" ] }
    if pad_step == 60:
        expect_ok(pad_page == 1, "LB turns the wheel\'s page ({wheel_pages()} pages)")
        pad_step = 61
        return none
    if pad_step == 61:
        pad_step = 62
        return PadIn { none.axes, [ "leftshoulder" ] }
    if pad_step == 62:
        pad_step = 6
        return none
    if pad_step == 6 and has_s(args, "wheelshot") and shot != "": gl.screenshot(shot + ".wheel.png")  // (captures: the wheel as it opened)
    if pad_step == 6 and pad_page == 0:
        expect_ok(pad_wheel.length > 0, "A on a selected worker opens its wheel ({pad_wheel.length} things to build)")
        var house = 0
        let items = wheel_page_items()
        for(items) w, n:
            if w.act == 3 and bt_name[w.arg] == "house": house = n
        let a = float(house) / float(max(1, items.length)) * 360.0 - 90.0
        pad_step++
        return PadIn { [ cos(a), sin(a), 0.0, 0.0, 0.0, 0.0 ], [] }
    if pad_step == 7:
        pad_step++
        return PadIn { none.axes, [ "a" ] }

    if pad_step == 8:
        expect_ok(placing >= 0 and bt_name[placing] == "house", "pointing at the house and A starts placing one")
        pad_houses = (filter(b_id.length) b: b_owner[b] == ME and bt_name[b_kind[b]] == "house").length
        cam = iso(float(b_cx[tc] * 1000 - 3000), float(b_cy[tc] * 1000 + 3000))
        test_pause = false
        pad_step++
        return none
    if pad_step == 9:
        pad_step++
        return PadIn { none.axes, [ "x" ] }
    if pad_step == 10 and t >= 9.0:
        let houses = (filter(b_id.length) b: b_owner[b] == ME and bt_name[b_kind[b]] == "house").length
        expect_ok(houses > pad_houses, "X lays the house down ({pad_houses} -> {houses})")
        pad_step++
        return PadIn { none.axes, [ "b" ] }
    if pad_step == 11:
        expect_ok(not selected.length, "B lets the selection go")
        pad_step++
        return PadIn { none.axes, [ "dpleft" ] }
    if pad_step == 12:
        pad_step++
        return none
    if pad_step == 13:
        expect_ok(selected.length > 0 and selected.length == (filter(groups.get(0, [])) id: index_of(id) >= 0).length, "a tap on d-pad left brings group 1 back ({selected.length})")
        for(t_slot.length) k:  // (a soldier by the workers, so there's more than one kind to cycle)
            if t_player[k] == ME and not t_worker[k] and t_animal[k] == 0 and t_trader[k] == 0 and t_healer[k] == 0 and pad_step == 13:
                mode_put(ME, k, start_x[ME] + 4000, start_y[ME] + 4000)
                pad_step = 69
        selected = map(filter(u_id.length) i: u_owner[i] == ME and t_animal[u_kind[i]] == 0) i: u_id[i]
        pad_step = 70
        return PadIn { none.axes, [ "leftshoulder" ] }
    if pad_step == 70:  // (LB let go: a tap)
        pad_step++
        return none
    if pad_step == 71:
        let kinds = []::int
        for(selected_units()) id:
            if not contains(kinds, u_kind[index_of(id)]): kinds.push(u_kind[index_of(id)])
        expect_ok(kinds.length == 1 and selected.length < pad_cycle_all.length, "a tap on LB keeps one kind of the selection ({selected.length} of {pad_cycle_all.length})")
        selected = filter(pad_cycle_all) id: index_of(id) >= 0
        arming_attack = true
        pad_step++
        return PadIn { none.axes, [ "a" ] }
    if pad_step == 72:
        expect_ok(not arming_attack, "A gives the armed attack-move")
        let mine = filter(u_id.length) i: u_owner[i] == ME and t_animal[u_kind[i]] == 0
        cam = iso(float(fold(mine, 0) acc, i: acc + u_x[i]) / float(mine.length), float(fold(mine, 0) acc, i: acc + u_y[i]) / float(mine.length))
        pad_step = 14
        return PadIn { none.axes, [ "rightshoulder" ] }
    if pad_step == 14:
        pad_step++
        print test_log
    return none

// ------------------------------------------------------------------ main

assert args.length >= 2
var trail = ""
def note(s:string):
    trail += "{seconds_elapsed()}: {s}\n"
    write_file("/tmp/aoa_lobster_trail.txt", trail, 0, 1)

note("start")
// (a capture runs without vsync: with the display asleep or the screen locked, vsync never lets a frame through;
// novsync: the same for a measure, the frame cap still pacing it)
let no_vsync = shot != "" or rec_dir != "" or selftest or padtest or has_s(args, "novsync")
volume_load()
window_fullscreen = starts_fullscreen(args, windowed_setting)
fatal(gl.window("Age of Anything (Lobster)", window_arg.x, window_arg.y, window_flags(no_vsync, window_fullscreen)))
pace(PACE_MATCH)                           // (a 120 Hz display would draw twice as often for nothing: the laptop runs hot)
gl.window_icon("icons/game_icon_mac.png")  // (the Dock's icon on the Mac)
note("window")
fatal(gl.load_materials(SPRITE_SHADERS, true))
fatal(gl.load_materials(TERRAIN_SHADERS, true))
fatal(gl.load_materials(ATMO_SHADERS, true))
check(gl.set_font_name("data/fonts/Droid_Sans/DroidSans.ttf"), "no font")
bake_live = shot == "" and not selftest and not padtest  // (the window kept alive while art bakes; captures and tests bake quietly)

// Something on the screen from the first moment (not a black window): the boot screen (game/boot), until the title.
def startup_frame(what:string, done:float):
    if not bake_live: return
    boot_draw(what, done)
    gl.frame()

fatal(gl.load_materials(UI_SHADERS, true))  // (the boot screen paints the UI's wood)
ui_ready = true
// page:boot shot:<png>: a picture of the boot screen, then quit
if page_arg == "boot":
    for(3):
        boot_draw("Loading the sounds...", 0.35)
        gl.frame()
    boot_draw("Loading the sounds...", 0.35)
    if shot != "": gl.screenshot(shot)
    return from program
startup_frame("Loading...", 0.05)
for(args) a:  // cache:<folder>: the parts kept there instead of bake_cache/ ("cache:" alone: baked afresh, kept nowhere)
    if starts_with(a, "cache:"): bake_cache_dir = a.substring(6, a.length - 6)
zoom = 2.0 * floor(ui() + 0.5)  // two screen points an art pixel, as the game's camera
// Desktops start one zoom step further out, and then a quarter further again (#358); Steam Deck-sized screens (800 px
// tall or less) and touch keep the closer view
if not touch_play and gl.framebuffer_size().y > 800: zoom = max(1.0, (zoom - 1.0) * 0.8)
art_density(if has_s(args, "prebake"): density_arg else: zoom)  // (prebake: the density it's asked for, the base by default)
if zoom_arg > 0.0: zoom = zoom_arg
// The tables come from data (game/pack_data.lobster); units are voxel bodies (game/voxel_units.lobster); buildings and
// props are baked once (src/baked/) or at the start. (A Godot art pack, args[0], is gone with Godot: D-184.)
pack_library = true
startup_frame("Loading the sounds...", 0.2)
startup_frame("Loading the data...", 0.5)
lib_load("../data")
pack_teams()
ui_setup("")
let mods_wanted = if mods_arg != "": tokenize(mods_arg, ",", " ") else: pack_mods
if mods_wanted.length: print "mods: {mods_use(mods_wanted)}"
music_start()  // (after the mods: they can bring their own)
ambience_start()
startup_frame("Loading the parts...", 0.8)
id_load("../data")
// propframes dump:<folder>: every prop baked as PNGs, then quit (art review).
if has_s(args, "propframes"):
    for(args) d: if starts_with(d, "dump:"): ak_dump = d.substring(5, d.length - 5)
    bake_live = false
    bake_cache_dir = ""
    bake_shipped_dir = ""
    ak_rebake = true
    bake_doodads()
    bake_quit = true
// lookframes:<arch>,<type> dump:<folder>: every frame of a look baked as PNGs (its stages, ruins), then quit (art review).
for(args) a:
    if starts_with(a, "lookframes:"):
        let at_ = tokenize(a.substring(11, a.length - 11), ",", " ")
        for(args) d: if starts_with(d, "dump:"): akb_check_dump = d.substring(5, d.length - 5)
        bake_live = false
        let keep_cache = bake_cache_dir
        bake_cache_dir = ""
        ak_rebake = true
        bmat_matte = true
        akb_bake_look(at_[0], at_[1], "", "")
        bake_cache_dir = keep_cache
        bake_quit = true
// vbcheck: the buildings' checks as voxels (game/art_kit_buildings.lobster, akb_check), then quit.
if has_s(args, "vbcheck"):
    bake_live = false
    for(args) a: if starts_with(a, "dump:"): akb_check_dump = a.substring(5, a.length - 5)
    var checked = all_architectures()
    for(args) a:  // shard:<i>/<n>: every n-th architecture from the i-th, for n processes side by side (batch.sh)
        if starts_with(a, "shard:"):
            let shard, shards = split_string(a.substring(6, a.length - 6), "/")
            checked = filter(checked) _a, n: n % string_to_int(shards) == string_to_int(shard)
    if akb_check(checked) > 0: set_exit_code(1)
    bake_quit = true
// prebake: every prop and every architecture's buildings baked into the shipped folder (src/prebake.sh), then quit.
if has_s(args, "prebake"):
    bake_cache_dir = bake_shipped_dir
    bake_shipped_dir = ""
    bake_live = false  // (no progress drawn: the window's frames aren't needed, and a hidden one can stop the bake)
    let t0 = seconds_elapsed()
    print "prebake: {bake_doodads()} prop frames in {int(seconds_elapsed() - t0)} s"
    let archs = all_architectures()
    let t1 = seconds_elapsed()
    print "prebake: {bake_buildings_for(archs)} building frames ({concat_string(archs, ", ")}) in {int(seconds_elapsed() - t1)} s"
    bake_quit = true

// A line in the middle of an empty screen while the link is made (true: the window was closed).
def net_wait_frame(msg:string) -> bool:
    if not gl.frame() or gl.button("escape") == 1: return true
    gl.clear(float4 { 0.05, 0.05, 0.05, 1.0 })
    gl.blend(1)
    let u = ui()
    gl.set_font_size(int(22.0 * u))
    let half = float(gl.text_size(msg).x) * 0.5  // (a refusal can be long: centred, so it stays on screen)
    lobby_text(float(gl.window_size()) * float2 { 0.5, 0.5 } - float2 { half, 0.0 }, msg, float4 { 0.95, 0.85, 0.6, 1.0 })
    return false

var link = Link {}
var joined_bots = []::Bot
var bots = []::Bot
var net_on = false
var lockstep = Lockstep { Link {}, 0, [ 0 ], [] }
var back_to_lobby = false  // the pause menu's Back to the menu (or the match won or lost from the lobby)
var quit_app = false
var next_choice = ""   // the next match without the lobby (the pause menu's Load game)
var front_choice = ""  // what the lobby chose (game/lobby.lobster: play, host, join, fight, load:<path>)

// A saved match from the lobby's Load game: its world and bots, as a joiner takes the host's.
def load_saved(path:string) -> bool:
    let loaded = load_world(path)
    if not loaded.length: return false
    joined_bots = loaded
    map_name_now = gstr(su_map, "id", "reed_meadow")
    load_species(map_name_now)
    if pack_library: race_facts(su_races)
    return true

// The match: joined, loaded, or made here from the lobby's prompts (or the pack's scenario); the bots, the
// network, the captures' extras, the lockstep. False when the window was closed meanwhile.
// ---- the playtest log (milestone 10): one JSON line per finished match in matches.jsonl: the races, who won, how long
// it ran, when each side reached each age (docs/playtest.md)
var log_races = []::string
var log_prompts = []::string
var log_ages = []::int
var log_age_ups = []::JV
var log_done = false

def log_tick():
    if log_ages.length != ages.length: log_ages = copy(ages)
    for(ages) a, p:
        if a > log_ages[p]:
            log_age_ups.push(jarr([ jint(p), jint(a), jint(tick / 20) ]))
            log_ages[p] = a
    if winner >= 0 and not log_done:
        log_done = true
        let o = jobj()
        set(o, "map", jstr(map_name_now))
        set(o, "races", jstrs(log_races))
        set(o, "prompts", jstrs(log_prompts))
        set(o, "winner_team", jint(winner))
        set(o, "you", jint(ME))
        set(o, "seconds", jint(tick / 20))
        set(o, "ages", jarr(map(ages) a: jint(a)))
        set(o, "age_ups", jarr(log_age_ups))
        write_file("matches.jsonl", (read_file("matches.jsonl") or "") + stringify(o) + "\n")
        print "match logged: src/matches.jsonl"

def make_match() -> bool:
    log_done = false
    log_ages = []
    log_age_ups = []
    joined_bots = []
    ai_levels = []
    if starts_with(front_choice, "load:"):
        if not load_saved(front_choice.substring(5, front_choice.length - 5)): return false
    if join_ip != "" and not joined_bots.length:
        link = net_join(join_ip, NET_PORT)
        var msg = "Joining {join_ip}..."
        var said = false
        while not joined_bots.length:
            if net_wait_frame(if link.error != "": "Could not join {join_ip}: {link.error}" else: msg): return false
            if link.error == "" and net_ready(link):
                if not said:
                    join_hello(link)
                    said = true
                msg = "Joined {join_ip}: the host is sending the match..."
                let later = []::[string]
                for(net_poll(link)) f:
                    if f[0] == "W": ME = string_to_int(f[1])  // (our seat)
                    elif f[0] == "S": joined_bots = load_world_bytes(f[1])
                    elif f[0] == "X": link.error = f[1]
                    elif joined_bots.length: later.push(f)  // (a turn that came with the match: kept for the lockstep)
                net_unread(link, later)
        if ME == 0: ME = 1  // (a host that sends no seat: the second one)
        net_people = num_players
        map_name_now = gstr(su_map, "id", "reed_meadow")
        load_species(map_name_now)
        if pack_library: race_facts(su_races)
    elif joined_bots.length: pass()
    elif args[1] == "-" or args[1] == "lobby":  // the races from their prompts and the match start, made here (gen/)
        let rules = load_rules(rules_id())
        set(rules, "animals", jbool(true))
        let prompts = lobby_prompts
        let t_gen = seconds_elapsed()
        // (more than two people: the other seats take the two prompts' further takes, a team each)
        let races = map(max(prompts.length, if hosting: net_people else: 0)) k: generate(prompts[k % prompts.length], rules, if k < lobby_rerolls.length: lobby_rerolls[k] else: k / prompts.length)
        log_races = map(races) r: rstr(r, "name")
        log_prompts = map(races.length) k: prompts[k % prompts.length]
        let t_setup = seconds_elapsed()
        if args[1] == "lobby": reset_world()  // (the lobby's pages may have run a world: the Race Lab's)
        let map_id = if args[1] == "lobby": lobby_map elif pack_map != "": pack_map else: "reed_meadow"
        if args[1] == "lobby": set(rules, "mode", jstr(lobby_mode))                                  // (the match's mode)
        let picked = args[1] == "lobby" and lobby_teams.length == races.length and races.length > 2  // (a team game picked in the lobby: its map and teams)
        let four = races.length > 2 and not picked                                                   // (host:<n> with more people: the 2v2 map)
        let real_map = if four: "reed_meadow_2v2" else: map_id
        setup_match(20261010, real_map, races, rules, if picked: lobby_teams elif four: map(races.length) k: k % 2 else: [])
        load_species(real_map)
        map_name_now = real_map
        if pack_library: race_facts(races)
        print "races in {(t_setup - t_gen) * 1000.0} ms, the start in {(seconds_elapsed() - t_setup) * 1000.0} ms"
    else:
        // a scenario has no recipes: set its races up (as export.gd did) for the units' looks, then load it over a clean world
        let rules = load_rules(rules_id())
        let races = map(if pack_prompts.length >= 2: pack_prompts else: [ "sewer rats with cheese hammers", "angry swamp frogs with reed spears" ]) pr: generate(pr, rules, 0)
        setup_match(20261010, if pack_map != "": pack_map else: "flat_test", races, rules, [])
        let keep_units = su_units
        let keep_btypes = su_btypes
        let keep_races = su_races
        let keep_rules = su_rules
        reset_world()
        start_world(args[1])
        su_units = keep_units
        su_btypes = keep_btypes
        su_races = keep_races
        su_rules = keep_rules
        if pack_library: race_facts(races)
        roles_from_data()  // (a scenario file carries no building roles)
    note("world")
    events_on = true
    if args[1] == "lobby" and lobby_levels.length == num_players and not joined_bots.length: ai_levels_set(lobby_levels)  // (each AI at its level)
    bots = map(num_players) p: new_bot(p)
    if joined_bots.length: bots = joined_bots
    if hosting:
        let door = door_open(NET_PORT, rstr(su_races[0], "name"), map_name_now)
        let joined = []::Link
        let here = my_ipv4()
        while joined.length < net_people - 1:
            if net_wait_frame(if door.error != "": "Could not host: {door.error}" else: "Hosting at {if here != "": here else: "this machine"}: {joined.length} of {net_people - 1} joined, waiting..."): return false
            let got = door_tick(door)
            if got:
                net_send(got, 'W', string(joined.length + 1))
                joined.push(got)
        link = joined[0]
        net_others = joined.slice(1, -1)
        let bytes = world_bytes(bots)
        for(joined) l: net_send(l, 'S', bytes)
    net_on = hosting or join_ip != ""
    if place_arg == "fort" or place_arg == "palisade_fort":  // (captures: every join of a wall line at once)
        // a run of wall along x with a gate in it, a turn down y, a diagonal run, wall towers at the corners
        let stone = place_arg == "fort"
        let fwall = btype_index(if stone: "wall" else: "palisade")
        let fgate = btype_index(if stone: "stone_gate" else: "palisade_gate")
        let ftower = btype_index(if stone: "wall_tower" else: "watchtower")
        let tc = town_center(ME)
        if tc >= 0:
            var done = false
            for([ int2 { 5, -4 }, int2 { -12, 5 }, int2 { 5, 6 }, int2 { -10, -10 }, int2 { 6, 0 }, int2 { 0, 6 }, int2 { -8, 0 }, int2 { 0, -8 } ]) o:
                if not done:
                    let x0 = b_cx[tc] + o.x
                    let y0 = b_cy[tc] + o.y
                    let cells = []::int3  // x, y, kind (-1 wall, -2 gate along x, -3 tower)
                    for(3) i: cells.push(int3 { x0 + i, y0, -1 })
                    cells.push(int3 { x0 + 3, y0, -2 })
                    for(2) i: cells.push(int3 { x0 + 6 + i, y0, -1 })
                    cells.push(int3 { x0 + 8, y0, -3 })
                    for(3) i: cells.push(int3 { x0 + 8, y0 + 1 + i, -1 })
                    for(3) i: cells.push(int3 { x0 + 7 - i, y0 + 4 + i, -1 })
                    cells.push(int3 { x0 - 1, y0, -3 })
                    let fits = (filter(cells) c: can_place(ME, if c.z == -1: fwall elif c.z == -2: fgate else: ftower, c.x, c.y)).length
                    if fits * 10 >= cells.length * 8:  // (most of it: a tree or a rock in the way leaves a gap)
                        for(cells) c:
                            let k = if c.z == -1: fwall elif c.z == -2: fgate else: ftower
                            if can_place(ME, k, c.x, c.y): fort_put(ME, k, c.x, c.y, 0)
                        update_pop()
                        cam = iso(float(x0 * 1000 + 5500), float(y0 * 1000 + 4500))
                        print "fort: {fits} of {cells.length} tiles at {x0},{y0}"
                        fort_gate = int2 { x0 + 3, y0 }
                        done = true
    elif place_arg != "":
        let k = btype_index(place_arg)
        let tc = town_center(ME)
        if k >= 0 and tc >= 0:
            var done = false
            for(12) r:
                for(8) a:
                    if not done:
                        let x = b_cx[tc] + int(cos(float(a) * 45.0) * float(4 + r))
                        let y = b_cy[tc] + int(sin(float(a) * 45.0) * float(4 + r))
                        if can_place(ME, k, x, y):
                            fort_put(ME, k, x, y, 0)
                            update_pop()
                            cam = iso(float(x * 1000 + 1500), float(y * 1000 + 1500))
                            done = true
    if skirmish: army_n = max(army_n, 3)
    if army_n > 0:  // (a skirmish: both sides, marching on each other)
        for(num_players) p:
            if p == ME or skirmish:
                let slots = []::string
                for(t_slot.length) k:
                    if t_player[k] == p and not t_worker[k] and t_animal[k] == 0 and t_trader[k] == 0 and t_healer[k] == 0: push_new(slots, t_slot[k])
                let ids = []::int
                let side = int(ceiling(sqrt(float(slots.length * army_n))))  // (in ranks, not all on one spot)
                for(slots) slot:
                    let kind = type_of_slot(p, slot)
                    for(if has(gobj(su_units[kind], "look"), "crew"): max(1, army_n / 8) else: army_n):  // (engines: a few, not as many as soldiers)
                        let at = ids.length
                        let x = clamp(start_x[p] + 4000 + (at % side - side / 2) * ARMY_GAP, TILE, (W - 1) * TILE)
                        let y = clamp(start_y[p] + 4000 + (at / side - side / 2) * ARMY_GAP, TILE, (H - 1) * TILE)
                        let i = mode_put(p, kind, x, y)
                        ids.push(u_id[i])
                if skirmish:
                    let foe = (p + 1) % num_players
                    issue_cmd(p, CMD_ATTACK_MOVE, ids, start_x[foe], start_y[foe], 0, 0)
                    army_snap = true
        update_pop()
        if fort_gate.x >= 0 and has_s(args, "in_gate"):  // (captures: soldiers standing through the gate's arch, before, in it, past it)
            let gk = find(t_slot.length) j: t_player[j] == ME and t_slot[j] == "infantry"
            let gx = (fort_gate.x + 1) * 1000 + 500
            if gk >= 0:
                for([ -900, -300, 300, 900, 1500 ]) dy: add_unit(ME, gk, gx, fort_gate.y * 1000 + 500 + dy)
                for([ -1, 1 ]) side: for([ -700, 1400 ]) dy: add_unit(ME, gk, gx + side * 1300, fort_gate.y * 1000 + 500 + dy)  // (beside its towers)
        elif fort_gate.x >= 0:                                                                                                  // (through the fort's gate and out the far side)
            let mine = filter(u_id.length) i: u_owner[i] == ME and t_worker[u_kind[i]] == 0
            issue_cmd(ME, CMD_MOVE, map(mine) i: u_id[i], fort_gate.x * 1000 + 500, (fort_gate.y + 4) * 1000, 0, 0, 0)
        if skirmish:
            if watch:
                let mid_x = (start_x[0] + start_x[1]) / 2
                let mid_y = (start_y[0] + start_y[1]) / 2
                cam = iso(float(mid_x), float(mid_y))
                if look_x < 0: follow = true  // (watching: the camera goes where they fight, unless look: says where)
            else: look_at_army = true
    if hurt_pct >= 0:
        for(b_id.length) b:
            if b_owner[b] == ME: b_hp[b] = max(1, bm_hp[ME][b_kind[b]] * hurt_pct / 100)
    in_net_match = net_on
    lockstep = new_lockstep(link, ME, if net_on: map(net_people) k: k else: [ ME ])
    lockstep.more = net_others
    lockstep.relay = hosting
    return true

// Saving and loading (gen/save.lobster): F5 saves the match, F9 brings the save back (the whole world
// and the bots); the view starts over from it: units redrawn, the ground, paths and town read again.
let SAVE_PATH = "quick.sav"
def quick_save(): save_to(SAVE_PATH)

// The pause menu's Save game: a new file in saves/ each time, with a line about it beside it (the lobby's Load game lists them).
def save_game():
    launch_subprocess([ "/bin/mkdir", "-p", "saves" ])
    let stamp = date_time_string_format("%Y-%m-%d_%H-%M-%S")
    let names = concat_string(map(su_races) r: rstr(r, "name"), " vs ")
    let secs = tick / 20
    write_file("saves/{stamp}.txt", "{names}  -  {capitalize(map_name_now)}  -  {secs / 60}:{if secs % 60 < 10: "0" else: ""}{secs % 60}  -  {date_time_string_format("%d %b %H:%M")}\n")
    save_to("saves/{stamp}.sav")

def save_to(path:string):
    let t0 = seconds_elapsed()
    let ok = save_world(path, bots)
    banner = if ok: "Saved ({int((seconds_elapsed() - t0) * 1000.0)} ms)" else: "Could not save"
    banner_t = gl.time()

// What the view keeps about a match, let go (a save loaded over it, or a new match).
def view_reset():
    corpses = []
    fx_clear()
    hit_t0.clear()
    attack_t0.clear()
    shot_from.clear()
    shot_mouth.clear()
    town_last.clear()
    town_idle_since.clear()
    chores.clear()
    piles.clear()
    house_born.clear()
    town_puffs = []
    path_used = []
    path_done.clear()
    path_out = []
    path_painted = 0
    path_raw = []
    path_anchor_hub.clear()
    path_anchor_res.clear()
    path_count = -1
    ground_tick = -1000
    paths_tick = -1000
    mask_version = -1
    mask_tick = -1000
    selected = []
    sel_building = 0
    sel_foreign = 0
    groups.clear()
    placing = -1

def quick_load(): load_from(SAVE_PATH)

def load_from(path:string):
    let t0 = seconds_elapsed()
    let loaded = load_world(path)
    if not loaded.length:
        banner = if save_refused != "": save_refused else: "No save to load"
        banner_t = gl.time()
        return
    bots = loaded
    view_reset()
    refresh_paths()
    clock_s = float(tick) / 20.0
    p_id = copy(u_id)
    p_x = copy(u_x)
    p_y = copy(u_y)
    banner = "Loaded ({int((seconds_elapsed() - t0) * 1000.0)} ms)"
    banner_t = gl.time()
var tc0 = -1
var acc = 0.0
var paused = false
var speed = start_speed
var steps = 0
var frame_no = 0
var step_time = 0.0
var menu_open = false      // the pause menu (Esc)
var menu_saves = false     // ...showing the saved games (Load game)
var menu_settings = false  // ...showing Settings (game/lobby.lobster)
var quit_game = false
var told_end = false  // the match's end was shown (the menu opens once)

def end_screen_up() -> bool: return winner >= 0 and not end_watching and not menu_open

// The match's end: Victory or Defeat over the dimmed world, how long it was played, and the ways out.
def end_screen():
    let ws = float(gl.window_size())
    ui_frame(true)
    let k = hud_s()
    ui_fill(float2_0, ws, float4 { 0.0, 0.0, 0.0, 0.6 })
    let from_lobby = args[1] == "lobby"
    let buttons = filter([ "Back to the menu", "Quit" ]) l: l != "Back to the menu" or from_lobby
    let bw = 380.0
    let size = float2 { bw + 48.0, 250.0 + 54.0 * float(buttons.length) } * k
    let at = ws / 2.0 - size / 2.0
    ui_box(at, size, 1, ui_look.face, true)
    tb_icon_wide("crest_" + hud_crest, float2 { at.x + size.x / 2.0, at.y + 2.0 * k }, 34.0 * k)
    let x = at.x + 24.0 * k
    var y = at.y + 34.0 * k
    ui_text_c(ws.x / 2.0, y, if winner == teams[ME]: "Victory!" else: "Defeat", int(52.0 * k), ui_look.title, 2, 2.0 * k)
    y += 80.0 * k
    let secs = tick / 20
    def two(n:int) -> string: return (if n < 10: "0" else: "") + string(n)
    let played = if secs >= 3600: "{secs / 3600}:{two(secs / 60 % 60)}:{two(secs % 60)}" else: "{secs / 60}:{two(secs % 60)}"
    ui_text_c(ws.x / 2.0, y, "Played for " + played, int(20.0 * k), ui_look.dim, 0, 0.0)
    y += 44.0 * k
    if ui_button(float2 { x, y }, float2 { bw * k, 56.0 * k }, "", true) or gl.button("controller_b") == 1: end_watching = true
    ui_text_c(ws.x / 2.0, y + (56.0 * k - 24.0 * k) / 2.0 - 3.0 * k, "Keep watching", int(24.0 * k), ui_look.title, 2, 1.5 * k)
    y += 68.0 * k
    for(buttons) label:
        let fs = int(19.0 * k)
        if ui_button(float2 { x, y }, float2 { bw * k, 42.0 * k }, "", false):
            if label == "Back to the menu": back_to_lobby = true
            quit_game = true
        ui_text_f(float2 { x + (bw * k - ui_text_wf(label, fs, 1)) / 2.0, y + (42.0 * k - float(fs)) / 2.0 - 2.0 * k }, label, fs, ui_look.text, 1, 1.0 * k)
        y += 54.0 * k
    ui_flush()

// The pause menu (Esc, or Start on the pad): a panel of buttons over the dimmed match. In a network
// match the world goes on (only you stop looking), and Load isn't offered.
def pause_menu():
    let ws = float(gl.window_size())
    ui_frame(true)
    if menu_saves:  // Load game: the saves (game/lobby.lobster)
        fe_fit()
        let picked = fe_saves_card("")
        if picked == "back": menu_saves = false
        elif picked != "":  // (a new match from the save: its map may be another)
            next_choice = "load:" + picked
            back_to_lobby = true
            quit_game = true
        fe_draw_tip()
        ui_flush()
        return
    if menu_settings:  // Settings: the volumes and the UI scale (game/lobby.lobster)
        fe_fit()
        if fe_settings_card() == "back": menu_settings = false
        ui_flush()
        return
    if gl.button("controller_b") == 1: menu_open = false
    // sim_debug.gd's _make_pause_menu: a framed card in your race's look, its crest on top, sized to what's in it: the
    // title, your race and the map, a rule; Resume (the primary), the everyday buttons (Settings among them); then, set apart
    // under a rule, the ones that end the match (in red)
    let k = hud_s()
    ui_fill(float2_0, ws, float4 { 0.0, 0.0, 0.0, 0.5 })
    let from_lobby = args[1] == "lobby"
    let title = if winner >= 0: (if winner == teams[ME]: "Victory!" else: "Defeat") elif net_on: "Menu" else: "Paused"
    let sub = rstr(su_races[ME], "name") + "  ·  " + gstr(su_map, "name", map_name_now) + (if net_on: "  ·  the match goes on" else: "")
    let everyday = filter([ "Save game", "Load game", "Settings", "Tech tree" ]) l: l != "Load game" or not net_on
    let ending = filter([ "Surrender", "Back to the menu", "Quit" ]) l: (l != "Surrender" or (winner < 0 and defeated[ME] == 0)) and (l != "Back to the menu" or from_lobby)
    let bw = 380.0
    let size = float2 { bw + 48.0, 268.0 + 62.0 * float(everyday.length) + 54.0 * float(ending.length) } * k  // (the rows below, top to bottom)
    let at = ws / 2.0 - size / 2.0
    ui_box(at, size, 1, ui_look.face, true)
    tb_icon_wide("crest_" + hud_crest, float2 { at.x + size.x / 2.0, at.y + 2.0 * k }, 34.0 * k)
    let x = at.x + 24.0 * k
    var y = at.y + (22.0 + 8.0) * k
    ui_text_c(ws.x / 2.0, y, title, int(42.0 * k), ui_look.title, 2, 2.0 * k)
    y += 68.0 * k
    ui_text_c(ws.x / 2.0, y, sub, int(17.0 * k), ui_look.dim, 0, 0.0)
    y += 36.0 * k
    def rule():
        let t = max(1.0, k)
        ui_fill(float2 { x + 6.0 * k, y + 6.0 * k + t }, float2 { bw * k - 12.0 * k, t }, float4 { 0.0, 0.0, 0.0, 0.55 })
        ui_fill(float2 { x + 6.0 * k, y + 6.0 * k }, float2 { bw * k - 12.0 * k, t }, float4 { ui_look.metal.x, ui_look.metal.y, ui_look.metal.z, 0.7 })
        let c = float2 { x + bw * k / 2.0, y + 6.0 * k }
        let d = 4.5 * k
        ui_paint_poly([ c + float2 { 0.0, -d }, c + float2 { d, 0.0 }, c + float2 { 0.0, d }, c + float2 { -d, 0.0 } ], [ ui_look.metal, ui_look.metal, ui_look.metal, ui_look.metal ], [ 0, 1, 2, 0, 2, 3 ], ui_material("bronze"))
        y += 24.0 * k
    rule()
    def item(label:string, h:float, col:float4) -> bool:
        let hit = ui_button(float2 { x, y }, float2 { bw * k, h * k }, "", false)
        let fs = int(19.0 * k)
        ui_text_f(float2 { x + (bw * k - ui_text_wf(label, fs, 1)) / 2.0, y + (h * k - float(fs)) / 2.0 - 2.0 * k }, label, fs, col, 1, 1.0 * k)
        y += (h + 12.0) * k
        return hit
    let primary = ui_button(float2 { x, y }, float2 { bw * k, 64.0 * k }, "", true)
    ui_text_c(ws.x / 2.0, y + (64.0 * k - 28.0 * k) / 2.0 - 4.0 * k, "Resume", int(28.0 * k), ui_look.title, 2, 1.5 * k)
    if primary: menu_open = false
    y += 76.0 * k
    for(everyday) label:
        if item(label, 50.0, ui_look.text):
            if label == "Save game":
                save_game()
                menu_open = false
            elif label == "Load game": menu_saves = true
            elif label == "Settings": menu_settings = true
            else:
                menu_open = false
                open_tree(ME)
    rule()
    let danger = float4 { 0.91, 0.54, 0.44, 1.0 }  // #e88a70, as a lacked line
    for(ending) label:
        if item(label, 42.0, danger):
            if label == "Surrender":  // (the match ends as a defeat for your side)
                issue_cmd(ME, CMD_SURRENDER, []::int, 0, 0, 0, 0)
                menu_open = false
            elif label == "Back to the menu":
                back_to_lobby = true
                quit_game = true
            else: quit_game = true
    ui_flush()

import .game.cursor_images
// game: import .game.cursors

// A match from its start: the camera on your Town Center, the clock at 0, played until it's quit (or a capture's done).
def play_match():
    tc0 = town_center(ME)
    if tc0 >= 0: cam = iso(float(b_cx[tc0] * 1000 + 1500), float(b_cy[tc0] * 1000 + 1500))
    if look_at_army:
        let mine = filter(u_id.length) i: u_owner[i] == ME and t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0
        if mine.length: cam = iso(float(fold(mine, 0) a, i: a + u_x[i]) / float(mine.length), float(fold(mine, 0) a, i: a + u_y[i]) / float(mine.length))
    if look_x >= 0: cam = iso(float(look_x * 1000 + 500), float(look_y * 1000 + 500))
    acc = 0.0
    paused = false
    speed = start_speed
    steps = 0
    frame_no = 0
    step_time = 0.0
    menu_open = false
    menu_saves = false
    menu_settings = false
    quit_game = false
    told_end = false
    end_watching = false
    note("loop")
    pace(PACE_MATCH)
    if rec_dir != "":  // (as fast as it goes up to from:)
        gl.set_fixed_delta_time(0.2, 0.0)
        speed = 8.0
    while gl.frame() and not quit_game and not bake_quit:
        ui_click_tick()
        window_tick()
        if perf_for > 0.0:  // (the Town Center selected: its panel and queue drawn, the HUD full)
            perf_begin()
            if tc0 >= 0 and tc0 < b_id.length: sel_building = b_id[tc0]
            perf_finish_house(clock_s, ME)
        drop_lost_selection()
        if gl.button("escape") == 1 and placing < 0 and not build_menu and not typing_race and not tree_open and not pad_wheel.length and not arming_attack and not arming_ability: menu_open = not menu_open
        if gl.button("controller_start") == 1 and not typing_race and not tree_open: menu_open = not menu_open
        if has_s(args, "menu") and frame_no == 2: menu_open = true  // (captures)
        if has_s(args, "orders") and frame_no == 30:                // (captures: your units sent off, and the Town Center's rally set)
            selected = filter(u_id) id: u_owner[index_of(id)] == ME
            let tc = town_center(ME)
            if tc >= 0 and selected.length:
                let gx = b_cx[tc] * TILE + 6000
                let gy = b_cy[tc] * TILE - 4000
                issue_cmd(ME, CMD_MOVE, selected_units(), gx, gy, 0, 0, 0)
                issue_cmd(ME, CMD_MOVE, selected_units(), gx + 3000, gy + 3000, 0, 0, 1)
                issue_cmd(ME, CMD_RALLY, []::int, b_id[tc], gx - 3000, gy + 6000, 0)
        if gl.button("escape") == 1: build_menu = false
        if gl.button("space") == 1 and not net_on: paused = not paused
        let ctrl = gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1 or gl.button("left gui") >= 1 or gl.button("right gui") >= 1
        if ctrl and (gl.button("=") == 1 or gl.button("-") == 1):  // Ctrl/Cmd + and -: the HUD's size (saved)
            hud_size = clamp(hud_size + (if gl.button("=") == 1: 10 else: -10), 70, 200)
            volume_save()
        elif gl.button("=") == 1 and not net_on: speed = min(8.0, speed * 2.0)
        elif gl.button("-") == 1 and not net_on: speed = max(0.25, speed / 2.0)
        let dt = gl.delta_time()
        frame_dt = dt
        fx_tick(dt)
        vx_tick(0.006, u_x.length < 300 and gl.time() - last_battle >= 6.0)  // (the voxel units' later bakes, not in a fight)
        akb_wall_tick()                                                      // (a wall tile with joins not seen before: one a frame)
        town_tick(dt)
        music_tick("age{clamp(ages[ME], 1, 4)}", gl.time() - last_battle < 6.0, dt)
        ambience_tick(town_level(), dt)
        unit_loops_tick(dt)
        frame_no++
        if frame_no == 1:                                                            // (inside a frame: a bake outside one leaves the window drawing nothing)
            if bake_live and fe_sides.length == num_players and front_choice != "":  // (the match loader shows the bake's progress)
                bake_progress = fn(st, f): fe_loader(st, f)
                bake_progress_on = true
            bake_loading = true
            bake_progress_from = 0.5
            bake_progress_to = 0.95
            bake_what = "the armies"
            vx_start()
            let t1 = seconds_elapsed()
            ak_rebake = rebake_art
            bake_progress_from = 0.95
            bake_progress_to = 1.0
            bake_what = "the town"
            let nd = bake_doodads()
            print "baked {nd} props{if rebake_art: "" else: " the pack lacked"}, in {int((seconds_elapsed() - t1) * 1000.0)} ms"
            let t2 = seconds_elapsed()
            let nb = bake_buildings_for(arch_of)
            print "baked {nb} building frames{if rebake_art: "" else: " the pack lacked"}, in {int((seconds_elapsed() - t2) * 1000.0)} ms"
            bake_progress_on = false
            bake_loading = false
        if shot != "" and frame_no < 3: note("frame {frame_no} tc at {if tc0 >= 0: to_screen(iso(float(b_cx[tc0] * 1000 + 2000), float(b_cy[tc0] * 1000 + 2000))) else: float2_0} cam {cam} zoom {zoom} ws {gl.window_size()} fb {gl.framebuffer_size()} tc {tc0} draws {draws.length} W {W} H {H} first {iso(0.0, 0.0)} last {iso(float(W * 1000), float(H * 1000))}")
        if shot != "" and frame_no % 60 == 0: print "frame {frame_no}: {dt * 1000.0} ms, play {clock_s} s"
        if reload_at >= 0.0 and clock_s >= reload_at:
            quick_save()
            reload_tick = tick
            print "saved at tick {tick}: {u_id.length} units, {b_id.length} buildings, hash {state_hash()}"
            reload_at = -1.0
        if reload_tick >= 0 and tick >= reload_tick + 100:
            quick_load()
            print "loaded: tick {tick}, {u_id.length} units, {b_id.length} buildings, hash {state_hash()}"
            reload_tick = -1
        if not typing_race and gl.button("f5") == 1: quick_save()
        if not typing_race and not net_on and gl.button("f9") == 1: quick_load()
        if swap_arg != "" and clock_s >= swap_at:
            become(swap_arg)
            swap_arg = ""
        if not paused and not test_pause and winner < 0 and not typing_race and ((not tree_open and not menu_open) or net_on): acc += dt * speed
        acc = min(acc, 0.5)
        if net_on:
            ls_receive(lockstep)
            if lockstep.desync != "": banner = "Out of step with the other player: {lockstep.desync}"
            elif link.closed: banner = "The other player has left"
            if lockstep.desync != "" or link.closed: banner_t = gl.time()
        while acc >= 0.05:
            if net_on and tick % TICKS_PER_TURN == 0 and not may_run(lockstep, tick / TICKS_PER_TURN):
                acc = min(acc, 0.05)  // (waiting on the other player: don't save up time to rush through after)
                break
            p_id = copy(u_id)
            p_x = copy(u_x)
            p_y = copy(u_y)
            let t0 = seconds_elapsed()
            for(bots) bot, p:
                if not skirmish and (p != ME or watch) and not (net_on and p != ME and contains(lockstep.players, p)):  // (a skirmish: the armies' orders alone)
                    ai_level_for(p)
                    full_bot_think(bot)  // (watch: your own bot plays your side)
            let t1 = seconds_elapsed()
            step()
            if net_on: ls_after_step(lockstep)
            if army_snap and (find(fb_state) s: s != 0) >= 0:
                blocks_snap()
                army_snap = false
            step_time += seconds_elapsed() - t0
            perf_tick(t1 - t0, seconds_elapsed() - t1)
            steps++
            clock_s += 0.05
            after_step()
            acc -= 0.05
        if follow:
            var fx = 0
            var fy = 0
            var nf = 0
            for(u_x.length) i:
                if u_foe[i] != 0:
                    fx += u_x[i]
                    fy += u_y[i]
                    nf++
            if nf == 0:  // (no fighting yet: the armies)
                for(u_x.length) i:
                    if t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0:
                        fx += u_x[i]
                        fy += u_y[i]
                        nf++
            if nf > 0: cam = cam + (iso(float(fx / nf), float(fy / nf)) - cam) * 0.05
        if not typing_race and not tree_open and not menu_open and not end_screen_up():
            let padded = (touch_play and touch_tick(dt)) or pad_tick(if padtest: pad_script() else: read_pad(), dt)
            if touch_wants_menu:
                menu_open = true
                touch_wants_menu = false
            if not padded and not touch_play and not typing_race: scroll()
            keys()
            if not padded and not panel_click(mouse_px()): mouse()
        perf_lap(0)
        if drawing():  // (minimised: the sim plays on, nothing is drawn)
            gl.clear(float4 { 0.05, 0.05, 0.05, 1.0 })
            gl.blend(1)
            let shake = fx_shake_off()
            cam += shake
            draw_world(acc / 0.05)
            if atmo_on:
                collect_glows()
                atmo_end(float2 { floor(cam.x * zoom), floor(cam.y * zoom) } / zoom, zoom, 1.5)
            cam -= shake
            if not rec_clean: ui_batch(): draw_panel()
            perf_lap(6)
            if not rec_clean: draw_hud(paused, speed)
            perf_lap(7)
            if not rec_clean: draw_groups()
            perf_lap(8)
            pad_draw()
            if touch_play: build_button()
            if tree_arg and frame_no == 2:
                open_tree(ME)
            tree_tick()
            if menu_open: pause_menu()
            elif end_screen_up(): end_screen()
            if not rec_clean: draw_banner()
            if typing_race: typing_tick()
            os_cursor_tick()
        perf_lap(9)
        if has_s(args, "savegame") and clock_s >= 3.0:  // (tests: the pause menu's Save game, then quit)
            save_game()
            quit_app = true
            return
        if has_s(args, "lobbyloop") and loop_round == 0 and clock_s >= 2.0:  // (tests: back to the lobby, then a second match)
            loop_round++
            back_to_lobby = true
            quit_game = true
        if airtest and air_test(): break
        if selftest and self_test():
            if shot != "": gl.screenshot(shot)
            quit_app = true
            return
        if padtest and pad_step >= 15 and pad_step < 60:
            if shot != "": gl.screenshot(shot)
            quit_app = true
            return
        if not net_on or ME == 0: log_tick()
        if has_s(args, "tillend") and (winner >= 0 or (shot_at > 0.0 and clock_s >= shot_at)):  // a whole match to its end (tests: with watch)
            if shot != "": gl.screenshot(shot)
            print "match over: {if winner >= 0: "team {winner} won" else: "no winner yet"} at {int(clock_s) / 60}:{int(clock_s) % 60}, tick {tick}"
            quit_app = true
            return
        if shot != "" and clock_s >= shot_at and not selftest and not padtest and not has_s(args, "tillend") and (not tree_arg or (frame_no > 4 and tree_waiting == 0)) and (not has_s(args, "menu") or frame_no > 4):
            gl.screenshot(shot)
            print "shot {shot} at {clock_s} s, tick {tick}; sim {step_time * 1000.0 / max(1, steps)} ms a tick; cam {cam} zoom {zoom} ws {gl.window_size()} fb {gl.framebuffer_size()}"
            quit_app = true
            return
        if rec_dir != "" and winner >= 0 and clock_s < rec_from:  // (the match was over before from:, and play has stopped)
            print "record: match over at {clock_s} s, before from:"
            quit_app = true
            return
        if rec_dir != "" and clock_s >= rec_from:
            if rec_n == 0:
                gl.set_fixed_delta_time(1.0 / rec_fps, 0.0)
                speed = start_speed
                if rec_pan != float2_0: follow = false  // (a pan is the take's own camera move; the follow would pull against it)
            gl.screenshot("{rec_dir}/{100000 + rec_n}.png")
            rec_n++
            let take_frames = rec_for * rec_fps
            if float(rec_n) >= take_frames:
                quit_app = true
                return
            // the camera's move over the take, a frame of it at a time: the push in and the drift (iso: tiles are 1000 art units)
            zoom *= pow(rec_push, 1.0 / take_frames)
            cam += (iso(rec_pan.x * 1000.0, rec_pan.y * 1000.0) - iso(0.0, 0.0)) / take_frames
        if perf_for > 0.0 and perf_end(clock_s, army_n > 0):
            quit_app = true
            return

// Everything the last match left, let go: the world, the view, the network, the captures' extras.
def new_match_reset():
    view_reset()
    reset_world()
    ground_mesh = nil
    ground_quad = nil
    relief_built = false
    relief = []
    relief_faces = []
    relief_tops = []
    relief_rims = []
    occluders = []
    mask_version = -1
    doodad_list = []
    bld_seen.clear()
    busts.clear()
    hud_culture = "?"
    unit_dir.clear()
    last_aim.clear()
    unit_sound_of.clear()
    aim_moved.clear()
    unit_kick.clear()
    last_kind.clear()
    last_owner.clear()
    critters = []
    critter_towns.clear()
    town_tick_seen = -1
    town_parts = []
    town_emit.clear()
    town_builders = []
    path_bytes = []
    typing_race = false
    tree_open = false
    build_menu = false
    arming_attack = false
    arming_ability = false
    pad_wheel = []
    clock_s = 0.0
    p_id = []
    p_x = []
    p_y = []
    if in_net_match: link.closed = true
    hosting = false
    join_ip = ""
    in_net_match = false
    net_on = false
    ME = 0
    skirmish = false
    army_n = 0
    follow = false
    look_at_army = false
    ai_levels = []
    back_to_lobby = false
    ui_setup("")

// ------------------------------------------------------------------ the game: the lobby, a match, back to the lobby
// "lobby" opens the front end (game/lobby.lobster) on its title, or page:<name> (title, setup, lab, saves, net) with
// races:A|B... typed; "lobby races:A|B" (no page) goes straight to the match. After a match from the lobby, back to it.
if args[1] == "lobby":
    if map_arg != "": lobby_map = map_arg
    if mode_arg != "": lobby_mode = mode_arg
    lobby_prompts = if pack_prompts.length >= 2: pack_prompts else: [ "sewer rats with cheese hammers", "angry swamp frogs with reed spears" ]
    if races_arg != "": lobby_prompts = tokenize(races_arg, "|", " ")
var front_first = args[1] == "lobby" and join_ip == "" and not hosting and (races_arg == "" or lab_arg or page_arg != "")
while not quit_app and not bake_quit:
    if next_choice != "":
        front_choice = next_choice
        next_choice = ""
    elif front_first:
        front_choice = run_front(if lab_arg: "lab" elif page_arg != "": page_arg else: "title", if races_arg != "": lobby_prompts else: [])
        if front_choice == "": break
    if not make_match(): break
    play_match()
    os_cursor_release()
    if quit_app or bake_quit or not back_to_lobby: break
    new_match_reset()
    front_first = true
view_reset()
fe_free_views()
