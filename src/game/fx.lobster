// ------------------------------------------------------------------ combat effects (src/view/combat_fx.gd)
// Played from the sim's events, view side only: sparks where a blow lands, dust (a death's puff, a
// stone or a charge coming down), shots that miss standing in the ground a while, and pale motes
// rising off a healed unit. A building that falls leaves its ruin under a cloud of pixel dust; the
// ruin is only decoration (D-172): it burns out, fades after a while, and goes at once when something
// is built over it (drawn in game/town.lobster). Canvas units (Godot's), drawn under a 1.5 scale.
// Cosmetic, so Lobster's own random numbers.

// A shot's own impact: sparks lines thrown out from the hit, fading.
class HitLook:
    sparks:int
    size:float
    spread:float
    life:float
    col:float4
    sound:string

// What a shot does at the gun, and where it lands (shots.json "muzzle", "impact"). Nothing unless asked for.
class MuzzleLook:
    flash:float
    col:float4
    smoke:int
    ring:float
    dust:int
    recoil:float

class ImpactLook:
    blast:float
    col:float4
    smoke:int
    scorch:float
    debris:int
    shake:float

class ShotStyle:
    arc:float
    len:float
    w:float
    col:float4
    glow = float4_0   // a soft halo round it; alpha 0: none
    shaft = float4_0  // an arrow: a thin shaft, a head and fletching; alpha 0: a plain line
    head = float4_0
    fletch = float4_0
    sticks = true  // a miss stands in the ground (false: a bolt of light)
    beam = false   // a line from muzzle to target, for `hold` seconds
    hold = 0.12
    pulses = 1
    gap = 0.0
    scatter = 1
    spread = 0.0
    wobble = 0.0
    jag = 1
    fade = 0.0
    trail = 0.0  // a fading tail behind a bolt, canvas px
    muzzle = MuzzleLook { 0.0, float4 { 1.0, 0.86, 0.56, 1.0 }, 0, 0.0, 0, 0.0 }
    impact = ImpactLook { 0.0, float4 { 1.0, 0.68, 0.34, 1.0 }, 0, 0.0, 0, 0.0 }
    hit = HitLook { 0, 0.0, 0.0, 0.0, float4_0, "" }  // its own impact (shots.json "hit"); no sparks: the game's

    // One flying shot: the sim's own timing, no timers of the view's.
    def plain() -> bool: return pulses == 1 and scatter == 1 and not beam

def hex_col(h:string) -> float4:
    def byte(i:int) -> float: return float(string_to_int(h.substring(i, 2), 16)) / 255.0
    return float4 { byte(0), byte(2), byte(4), 1.0 }

let SHOT_STYLES = dictionary<string, ShotStyle>(16)

// A look's knobs (data/shots.json with the mods' over it; mod_check_shot has said they're sound).
def shot_style_of(m:JV) -> ShotStyle:
    def num(k:string, f:float) -> float: return if has(m, k): as_float(at(m, k)) else: f
    let s = ShotStyle { num("arc", 0.0), num("len", 0.0), num("w", 1.0), hex_col(substring(rstr(m, "col"), 1, 6)) }
    if has(m, "glow"): s.glow = hex_col(substring(rstr(m, "glow"), 1, 6))
    if has(m, "shaft"):
        s.shaft = hex_col(substring(rstr(m, "shaft"), 1, 6))
        s.head = hex_col(substring(rstr(m, "head"), 1, 6))
        s.fletch = hex_col(substring(rstr(m, "fletch"), 1, 6))
    s.sticks = gbool(m, "sticks", true)
    s.beam = gstr(m, "form", "bolt") == "beam"
    s.hold = num("hold", 0.12)
    let pulses = gobj(m, "pulses")
    s.pulses = gint(pulses, "count", 1)
    s.gap = if has(pulses, "gap"): as_float(at(pulses, "gap")) else: 0.0
    let scatter = gobj(m, "scatter")
    s.scatter = gint(scatter, "count", 1)
    s.spread = if has(scatter, "spread"): as_float(at(scatter, "spread")) else: 0.0
    s.wobble = num("wobble", 0.0)
    s.jag = max(1, gint(m, "jag", 1))
    s.fade = num("fade", 0.0)
    s.trail = num("trail", 0.0)
    let mz = get(m, "muzzle")
    if mz:
        def mnum(k:string, f:float) -> float: return if has(mz, k): as_float(at(mz, k)) else: f
        s.muzzle = MuzzleLook { mnum("flash", 0.0), if has(mz, "col"): hex_col(substring(rstr(mz, "col"), 1, 6)) else: s.muzzle.col, gint(mz, "smoke", 0), mnum("ring", 0.0), gint(mz, "dust", 0), mnum("recoil", 0.0) }
    let im = get(m, "impact")
    if im:
        def inum(k:string, f:float) -> float: return if has(im, k): as_float(at(im, k)) else: f
        s.impact = ImpactLook { inum("blast", 0.0), if has(im, "col"): hex_col(substring(rstr(im, "col"), 1, 6)) else: s.impact.col, gint(im, "smoke", 0), inum("scorch", 0.0), gint(im, "debris", 0), inum("shake", 0.0) }
    let h = get(m, "hit")
    if h:
        def hnum(k:string, f:float) -> float: return if has(h, k): as_float(at(h, k)) else: f
        s.hit = HitLook { as_int(at(h, "sparks")), hnum("size", 3.0), hnum("spread", 10.0), hnum("life", 0.3), hex_col(substring(rstr(h, "col"), 1, 6)), gstr(h, "sound", "") }
    return s

def shot_style(kind:string) -> ShotStyle:
    let s = SHOT_STYLES.get(kind)
    if s: return s
    let m = get(lib_data("shots.json"), kind)
    let made = if m: shot_style_of(m) else: shot_style("arrow")
    SHOT_STYLES.set(kind, made)
    return made

// A flying shot at u (0..1) of its way from a to b, with a speck of shadow under it.
def draw_bolt(st:ShotStyle, a:float2, b:float2, u:float, alpha:float):
    let h = magnitude(b - a) * st.arc
    def at(v:float) -> float2: return a + (b - a) * v - float2 { 0.0, h * 4.0 * v * (1.0 - v) }
    let p = at(u)
    let ahead = at(min(u + 0.03, 1.0))
    let dir = if magnitude(ahead - p) > 0.0001: normalize(ahead - p) else: normalize(b - a + float2 { 0.0001, 0.0 })
    let lift = h * 4.0 * u * (1.0 - u)
    let col = float4 { st.col.x, st.col.y, st.col.z, st.col.w * alpha }
    if st.glow.w > 0.0:  // a bolt of light: a soft halo under its core
        // (and its light on what it passes, view/atmosphere.lobster)
        atmo_glow(atmo_source("shot"), p, st.glow.xyz, alpha, a.x + a.y)
        ui_line(p - dir * st.len * 0.6, p + dir * st.len * 0.6, st.w * 2.2, float4 { st.glow.x, st.glow.y, st.glow.z, 0.35 * alpha })
    if st.trail > 0.0:  // a tail, thinning out behind it, no longer than it has flown
        let tail = min(st.trail, magnitude(p - a))
        for(3) k:
            let t0 = st.len * 0.5 + tail * float(k) / 3.0
            let t1 = st.len * 0.5 + tail * float(k + 1) / 3.0
            ui_line(p - dir * t0, p - dir * t1, st.w * (1.0 - float(k) * 0.25), float4 { col.x, col.y, col.z, col.w * [ 0.6, 0.35, 0.15 ][k] })
    if st.shaft.w > 0.0:
        for(arrow_lines(p + dir * st.len * 0.5, p - dir * st.len * 0.5, st.w, st.shaft, st.head, st.fletch, true)) l:
            ui_line(l.a, l.b, l.w, float4 { l.col.x, l.col.y, l.col.z, alpha })
    elif st.len > 0.0: ui_line(p - dir * st.len * 0.5, p + dir * st.len * 0.5, st.w, col)
    else: fx_circle(p, st.w, col)
    fx_circle(p + float2 { 0.0, lift + 1.0 }, 0.8, float4 { 0.0, 0.0, 0.0, 0.25 * alpha })

// What the view draws for one sim shot beyond a plain flying one: its pulses and pellets, on their own timers.
class Tracer:
    a:float2
    b:float2
    t:float  // seconds since it set off (below 0: still waiting)
    dur:float
    st:ShotStyle
    seed:float
    sound:string

var fx_tracers = []::Tracer

def fx_fire(st:ShotStyle, a:float2, b:float2, flight:float, sound:string):
    let seen_for = shot_drawn_time(flight)  // (launched late: it looks faster, and lands when the sim says)
    for(st.pulses) p:
        for(st.scatter) s:
            let angle = rnd_range(0.0, 360.0)
            let r = if st.scatter > 1: st.spread * sqrt(rnd_float()) else: 0.0
            let to = b + float2 { cos(angle) * r, sin(angle) * r * 0.5 }
            let again = if p > 0 and s == 0: sound else: ""  // (the sim's shot sounds the first)
            fx_tracers.push(Tracer { a, to, -float(p) * st.gap - (if st.beam: 0.0 else: flight - seen_for), if st.beam: st.hold else: seen_for, st, rnd_range(0.0, 360.0), again })

def tracers_tick(dt:float):
    for(fx_tracers) t:
        t.t += dt
        if t.t >= 0.0 and t.sound != "":
            play_sound(t.sound, -4.0)
            t.sound = ""
    fx_tracers = filter(fx_tracers) t: t.t < t.dur

def draw_beam(tr:Tracer, alpha:float):
    let st = tr.st
    let across = normalize(float2 { tr.b.y - tr.a.y, tr.a.x - tr.b.x } + float2 { 0.0001, 0.0 })
    def point(i:int) -> float2:
        let u = float(i) / float(st.jag)
        let shake = if i == 0 or i == st.jag: 0.0 else: st.wobble * sin(tr.seed + float(i) * 137.0 + tr.t * 900.0)
        return tr.a + (tr.b - tr.a) * u + across * shake
    for(st.jag) i:
        if st.glow.w > 0.0: ui_line(point(i), point(i + 1), st.w * 2.6, float4 { st.glow.x, st.glow.y, st.glow.z, 0.4 * alpha })
    for(st.jag) i: ui_line(point(i), point(i + 1), st.w, float4 { st.col.x, st.col.y, st.col.z, alpha })

def draw_tracers():
    for(fx_tracers) tr:
        if tr.t >= 0.0:
            let u = tr.t / tr.dur
            let alpha = if tr.st.fade > 0.0: clamp((1.0 - u) / tr.st.fade, 0.0, 1.0) else: 1.0
            if tr.st.beam: draw_beam(tr, alpha)
            else: draw_bolt(tr.st, tr.a, tr.b, u, alpha)

let RADIUS_PX = 64.0 * 0.5 * 1.41421356 / 1000.0  // canvas px a milli-tile of radius
let STUCK_TIME = 3.0
let HEAL_TIME = 1.0
let HEAL_MOTE = float4 { 0.894, 0.957, 0.753, 1.0 }

class Spark:
    pos:float2
    t:float
    big:bool

class Dust:
    pos:float2
    t:float
    size:float

class Stuck:
    pos:float2
    t:float
    kind:string
    tilt:float

class Heal:
    id:int
    t:float
    motes:[float4]  // offset x, y, rise speed, delay

class Burst:
    pos:float2
    t:float
    look:HitLook
    dirs:[float2]

var fx_sparks = []::Spark
var fx_bursts = []::Burst
var fx_dusts = []::Dust
var fx_stuck = []::Stuck
var fx_heals = []::Heal

// A flash and a ring, short-lived, and the marks left on the ground, canvas units.
class Flash:
    pos:float2
    t:float
    r:float
    life:float
    col:float4
    ring:bool

class Smoke:
    pos:float2
    t:float
    size:float
    drift:float

class Scorch:
    pos:float2
    t:float
    r:float

let SMOKE_TIME = 1.5
let SCORCH_TIME = 9.0
var fx_smokes = []::Smoke
var fx_flashes = []::Flash
var fx_scorches = []::Scorch
var fx_shake = 0.0  // the screen's shake now, canvas px; it dies away

def rnd_range(a:float, b:float) -> float: return a + rnd_float() * (b - a)

def fx_spark(at:float2, heavy:bool):
    fx_sparks.push(Spark { at + float2 { rnd_range(-2.0, 2.0), rnd_range(-2.0, 2.0) }, 0.0, heavy })

def fx_hit(at:float2, look:HitLook):
    let dirs = map(look.sparks):
        let a = rnd_range(0.0, 360.0)
        float2 { cos(a), sin(a) * 0.6 }
    fx_bursts.push(Burst { at, 0.0, look, dirs })

def fx_splash(at:float2, r:float):
    fx_spark(at, true)
    fx_dusts.push(Dust { at, 0.0, r * 0.45 })
    for(7) k:
        let a = 360.0 * float(k) / 7.0 + rnd_range(-17.0, 17.0)
        let d = r * rnd_range(0.4, 0.9)
        fx_dusts.push(Dust { at + float2 { cos(a) * d, sin(a) * d * 0.5 }, -rnd_float() * 0.12, rnd_range(2.5, 4.5) })

def fx_stick(at:float2, kind:string):
    fx_dusts.push(Dust { at, 0.0, 1.5 })
    if shot_style(kind).len > 0.0 and shot_style(kind).sticks:
        fx_stuck.push(Stuck { at + float2 { rnd_range(-1.5, 1.5), rnd_range(-1.0, 1.0) }, 0.0, kind, rnd_range(-0.6, 0.6) })

def fx_heal(id:int):
    for(fx_heals) h:  // one glow at a time
        if h.id == id and h.t < HEAL_TIME * 0.5: return
    fx_heals.push(Heal { id, 0.0, map(3): float4 { rnd_range(-4.0, 4.0), rnd_range(-14.0, -6.0), rnd_range(9.0, 14.0), rnd_range(0.0, 0.25) } })

// A fallen building's ruin (BuildingArt.fall): its last broken-up stage where it stood, burning a while.
class RuinFx:
    frame:string  // the ruin's bake
    body:string   // the building's bake (where its fires are)
    id:int        // the building's (its fires' spots)
    at:float2     // its anchor, art px (lifted)
    sort_y:float
    flat:bool  // (a pen: lies low)
    owner:int
    cells:int4  // its footprint: x, y, w, h (sim cells)
    fires:int   // how many of its fires burn
    t0:float    // when it fell (seconds of play shown, as the dead's)

// A puff of a fallen building's dust: canvas units.
class Puff3:
    pos:float2
    t:float
    r:float
    rise:float
    drift:float

let RUIN_BURN = 8.0    // a ruin's fires burn this long after it falls
let RUIN_STAYS = 45.0  // then it lies there this long...
let RUIN_FADE = 5.0    // ...and fades away
let PUFF_TIME = 2.6
let PUFF_SIZES = [ 3, 4, 5, 7, 9, 12, 15, 19, 24 ]                                                                                 // art pixels: a puff grows through these
let PUFF_DUST = [ float4 { 0.886, 0.839, 0.737, 1.0 }, float4 { 0.725, 0.663, 0.541, 1.0 }, float4 { 0.522, 0.467, 0.380, 1.0 } ]  // lit, mid, shade
var FX_ART_PX = ART_SCALE                                                                                                          // art px a canvas unit: the dust's grid
var fx_ruins = []::RuinFx
var fx_puffs = []::Puff3
let fx_puff_tex = dictionary<int, resource<texture>>(16)

// A fallen building (size: its side in tiles): a cloud of pixel dust over its footprint (its ruin, if it has one,
// is left by the game: fx_ruins).
def fx_collapse(at:float2, size:int):
    for(14 + size * 10):
        let off = float2 { rnd_range(-1.0, 1.0) * 24.0, rnd_range(-1.0, 1.0) * 12.0 - 8.0 } * float(size)
        fx_puffs.push(Puff3 { at + off, -rnd_float() * 0.5, rnd_range(4.0, 8.0) * (1.0 + float(size) * 0.3), rnd_range(6.0, 18.0), rnd_range(-6.0, 6.0) })

// Something stands on these cells (x, y, w, h): a ruin there goes at once.
def fx_clear_ruins(cells:int4):
    def apart(r:RuinFx) -> bool: return r.cells.x >= cells.x + cells.z or cells.x >= r.cells.x + r.cells.z or r.cells.y >= cells.y + cells.w or cells.y >= r.cells.y + r.cells.w
    let near = exists(fx_ruins) r: not apart(r)
    if near: fx_ruins = filter(fx_ruins) r: apart(r)

// A ruin's fade at `now` (1 whole .. 0 gone).
def ruin_fade(r:RuinFx, now:float) -> float: return 1.0 - clamp((now - r.t0 - RUIN_STAYS) / RUIN_FADE, 0.0, 1.0)

// A puff's shape `r` art pixels across: a disc, its edge ragged and dithered, in white (drawn tinted).
def puff_tex(r:int) -> resource<texture>:
    let have = fx_puff_tex.get(r)
    if have: return have
    let rows = map(2 * r + 1) y: map(2 * r + 1) x:
        let f = sqrt(float((x - r) * (x - r) + (y - r) * (y - r))) / float(r)
        let noise = float(((x * 73856093) ^ (y * 19349663) ^ (r * 83492791)) & 1023) / 1023.0
        if f > 1.0 or f + noise * 0.2 > 1.05 or (f > 0.8 and (x + y) % 2 == 0): float4_0 else: float4_1
    let made = gl.create_texture(rows, texture_format_nearest_mag | texture_format_nearest_min | texture_format_nomipmap | texture_format_clamp)
    fx_puff_tex.set(r, made)
    return made

// The fallen buildings' dust as one cloud: every puff in shade, then every puff in the mid tone up and to the left
// of it, then a smaller highlight further up-left (the light from the upper left), so the puffs merge into billows
// lit as one instead of reading as separate balls. On the art grid.
def draw_puffs():
    if not fx_puffs.length: return
    gl.set_shader("textured")
    for(3) band:
        for(fx_puffs) p:
            if p.t >= 0.0:
                let k = p.t / PUFF_TIME
                let want = p.r * FX_ART_PX * (0.6 + 0.8 * k) * [ 1.0, 0.92, 0.55 ][band]
                var r = PUFF_SIZES[0]
                for(PUFF_SIZES) n:
                    if float(n) <= want: r = n
                var at = p.pos + float2 { p.drift * k, -p.rise * k } - float2_1 * p.r * [ 0.0, 0.18, 0.4 ][band]
                at = float(floor(at * FX_ART_PX)) / FX_ART_PX
                let half = float2_1 * float(r) / FX_ART_PX
                let c = PUFF_DUST[2 - band]
                gl.set_primitive_texture(0, puff_tex(r))
                gl.color(float4 { c.x, c.y, c.z, 1.0 - k * k * k }):
                    gl.translate(at - half): gl.rect(half * 2.0 + float2_1 / FX_ART_PX)
    gl.set_shader("color")

// Smoke: soft grey puffs, swelling as they rise and thin out.
def fx_smoke(at:float2, n:int, r:float):
    for(n): fx_smokes.push(Smoke { at + float2 { rnd_range(-r, r), rnd_range(-r, r) * 0.5 }, -rnd_float() * 0.1, rnd_range(1.6, 3.0), rnd_range(-5.0, 5.0) })

// A lick of flame on a wreck.
def fx_flame(at:float2):
    fx_flashes.push(Flash { at + float2 { rnd_range(-5.0, 5.0), rnd_range(-3.0, 3.0) }, 0.0, rnd_range(2.5, 4.5), 0.2, float4 { 1.0, 0.56, 0.14, 0.95 }, false })

// A shot leaves its gun: at the muzzle, with its shooter's feet below.
def fx_muzzle(st:ShotStyle, at:float2, feet:float2):
    let m = st.muzzle
    if m.flash > 0.0: fx_flashes.push(Flash { at, 0.0, m.flash, 0.09, m.col, false })
    if m.ring > 0.0: fx_flashes.push(Flash { at, 0.0, m.ring, 0.25, float4 { 0.92, 0.9, 0.84, 0.7 }, true })
    fx_smoke(at, m.smoke, 1.5)
    for(m.dust): fx_dusts.push(Dust { feet + float2 { rnd_range(-7.0, 7.0), rnd_range(-3.0, 3.0) }, 0.0, rnd_range(2.0, 3.5) })

// A shot comes down, on something or on the ground (only the ground takes a scorch).
def fx_impact(st:ShotStyle, at:float2, on_ground:bool):
    let m = st.impact
    if m.blast > 0.0:
        fx_flashes.push(Flash { at, 0.0, m.blast, 0.14, m.col, false })
        fx_flashes.push(Flash { at, 0.0, m.blast * 1.5, 0.3, float4 { 0.92, 0.9, 0.84, 0.6 }, true })
    fx_smoke(at, m.smoke, m.blast * 0.4)
    if m.scorch > 0.0 and on_ground: fx_scorches.push(Scorch { at, 0.0, m.scorch })
    if m.debris > 0:
        fx_hit(at, HitLook { m.debris, 3.0, m.blast * 2.0 + 8.0, 0.4, float4 { 0.3, 0.26, 0.2, 1.0 }, "" })
    fx_shake = max(fx_shake, m.shake)

// The screen's offset for its shake just now.
def fx_shake_off() -> float2:
    if fx_shake <= 0.05: return float2_0
    return float2 { rnd_range(-1.0, 1.0), rnd_range(-1.0, 1.0) } * fx_shake

def fx_puff(at:float2, tip:float):
    for(4): fx_dusts.push(Dust { at + float2 { tip * 8.0 + rnd_range(-5.0, 5.0), rnd_range(-3.0, 2.0) }, 0.0, rnd_range(3.0, 5.0) })

def fx_clear():
    fx_sparks = []
    fx_bursts = []
    fx_tracers = []
    fx_dusts = []
    fx_stuck = []
    fx_heals = []
    fx_puffs = []
    fx_flashes = []
    fx_scorches = []
    fx_smokes = []
    fx_shake = 0.0
    fx_ruins = []

def fx_tick(dt:float):
    tracers_tick(dt)
    for(fx_flashes) f: f.t += dt
    fx_flashes = filter(fx_flashes) f: f.t < f.life
    for(fx_smokes) s: s.t += dt
    fx_smokes = filter(fx_smokes) s: s.t < SMOKE_TIME
    for(fx_scorches) s: s.t += dt
    fx_scorches = filter(fx_scorches) s: s.t < SCORCH_TIME
    fx_shake = max(0.0, fx_shake - dt * 6.0)
    for(fx_sparks) s: s.t += dt
    fx_sparks = filter(fx_sparks) s: s.t < 0.25
    for(fx_bursts) b: b.t += dt
    fx_bursts = filter(fx_bursts) b: b.t < b.look.life
    for(fx_dusts) d: d.t += dt
    fx_dusts = filter(fx_dusts) d: d.t < 1.6
    for(fx_stuck) s: s.t += dt
    fx_stuck = filter(fx_stuck) s: s.t < STUCK_TIME
    for(fx_heals) h: h.t += dt
    fx_heals = filter(fx_heals) h: h.t < HEAL_TIME
    for(fx_puffs) p: p.t += dt
    fx_puffs = filter(fx_puffs) p: p.t < PUFF_TIME

def fx_circle(at:float2, r:float, col:float4):
    gl.color(col):
        gl.translate(at): gl.circle(r, 12)

// ground_of(id): a live unit's feet on the canvas, or float2 { -1000000000.0, 0 } when it's gone or unseen.
def fx_draw(ground_of):
    gl.set_shader("color")
    for(fx_scorches) s:
        gl.color(float4 { 0.05, 0.04, 0.03, 0.5 * (1.0 - s.t / SCORCH_TIME) }):
            gl.translate(s.pos):
                gl.scale(float2 { 1.0, 0.5 }):
                    gl.circle(s.r, 16)
    for(fx_stuck) s:  // half buried, leaning, fading at the end
        let st = shot_style(s.kind)
        let a = clamp((STUCK_TIME - s.t) / 0.6, 0.0, 1.0)
        let up = float2 { sin(s.tilt * 57.29578), -cos(s.tilt * 57.29578) } * st.len * 0.9
        let arrow = st.shaft.w > 0.0
        let w = st.w
        let sh = s.pos + float2 { 0.6, 0.3 }
        ui_line(sh, sh + float2 { up.x * 1.4, -up.y * 0.35 }, w, float4 { 0.0, 0.0, 0.0, 0.3 * a })
        let parts = if arrow: arrow_lines(s.pos, s.pos + up, w, st.shaft, st.head, st.fletch, false) else: stuck_lines(s.pos, up, w, st.col, a)
        for(parts) l:
            if l.ball: fx_circle(l.b, l.w, l.col)
            else: ui_line(l.a, l.b, l.w, float4 { l.col.x, l.col.y, l.col.z, if arrow: a else: l.col.w })
    for(fx_heals) h:
        let g = ground_of(h.id)
        if g.x > -100000000.0:
            for(h.motes) m:
                let t = h.t - m.w
                if t > 0.0:
                    let a = sin(180.0 * clamp(t / (HEAL_TIME - 0.25), 0.0, 1.0))
                    let p = g + float2 { m.x, m.y } + float2 { sin((t * 5.0 + m.w * 20.0) * 57.29578) * 1.2, -m.z * t }
                    fx_circle(p, 1.6, float4 { HEAL_MOTE.x, HEAL_MOTE.y, HEAL_MOTE.z, 0.25 * a })
                    fx_circle(p, 0.7, float4 { HEAL_MOTE.x, HEAL_MOTE.y, HEAL_MOTE.z, 0.85 * a })
    for(fx_sparks) s:
        let f = 1.0 - s.t / 0.25
        let r = (if s.big: 4.0 else: 2.5) * (0.5 + f)
        gl.color(float4 { 1.0, 0.92, 0.7, f }):
            for(4) k:
                let a = float(k) * 90.0 + 22.9
                ui_line(s.pos, s.pos + float2 { cos(a), sin(a) } * r, 1.0, float4 { 1.0, 0.92, 0.7, f })
    for(fx_bursts) b:
        let f = b.t / b.look.life
        let c = b.look.col
        for(b.dirs) d:
            let p = b.pos + d * b.look.spread * f
            ui_line(p, p + d * b.look.size * (1.0 - f), 1.0, float4 { c.x, c.y, c.z, 1.0 - f })
    for(fx_flashes) f:
        let k = f.t / f.life
        let c = float4 { f.col.x, f.col.y, f.col.z, f.col.w * (1.0 - k) }
        if f.ring:
            let r = f.r * (0.3 + 0.7 * k)
            for(14) n:
                let a0, a1 = 360.0 * float(n) / 14.0, 360.0 * float(n + 1) / 14.0
                ui_line(f.pos + float2 { cos(a0) * r, sin(a0) * r * 0.5 }, f.pos + float2 { cos(a1) * r, sin(a1) * r * 0.5 }, 1.0, c)
        else:
            fx_circle(f.pos, f.r * (1.0 - k * 0.5) * 0.55, c)
            fx_circle(f.pos, f.r * (1.0 - k * 0.5) * 0.28, float4 { 1.0, 1.0, 0.92, c.w })
    for(fx_smokes) s:
        if s.t >= 0.0:
            let k = s.t / SMOKE_TIME
            fx_circle(s.pos + float2 { s.drift * k, -16.0 * k }, s.size * (0.6 + 1.3 * k), float4 { 0.56, 0.55, 0.52, 0.5 * (1.0 - k) })
    draw_puffs()
    for(fx_dusts) d:
        if d.t >= 0.0:
            let f = d.t / 1.6
            fx_circle(d.pos - float2 { 0.0, f * 10.0 }, d.size * (0.6 + f), float4 { 0.62, 0.56, 0.46, 0.5 * (1.0 - f) })
