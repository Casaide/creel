// ------------------------------------------------------------------ a little scene graph (Godot's Node2D, as UnitView uses it)
// Nodes with a position, rotation, scale, a layer ("z" meta: children are ordered by it, not drawn
// by z_index), visibility and an alpha; a node may be a part (PartShape): a bake drawn at its origin.
// Godot's 2D maths in radians, and its RandomNumberGenerator (PCG32), for the cosmetic animation.

let TAU = 6.28318530717958647692
let RAD = 57.29577951308232  // degrees a radian (Lobster's trig takes degrees)

def rsin(a:float) -> float: return sin(a * RAD)
def rcos(a:float) -> float: return cos(a * RAD)
def vlen(v:float2) -> float: return sqrt(v.x * v.x + v.y * v.y)
def vdot(a:float2, b:float2) -> float: return a.x * b.x + a.y * b.y
def lerpf(a:float, b:float, w:float) -> float: return a + (b - a) * w
def clampf(x:float, lo:float, hi:float) -> float: return if x < lo: lo elif x > hi: hi else: x
def smoothstep(a:float, b:float, x:float) -> float:
    if a == b: return if x < a: 0.0 else: 1.0
    let s = clampf((x - a) / (b - a), 0.0, 1.0)
    return s * s * (3.0 - 2.0 * s)
def fmodf(x:float, y:float) -> float:  // C's fmod: the sign of x
    let q = x / y
    let t = if q < 0.0: ceiling(q) else: floor(q)
    return x - t * y
def move_toward(f:float, to:float, d:float) -> float:
    if abs(to - f) <= d: return to
    return f + (if to > f: d else: -d)
def signf(x:float) -> float: return if x > 0.0: 1.0 elif x < 0.0: -1.0 else: 0.0
def roundf(x:float) -> float: return if x >= 0.0: floor(x + 0.5) else: -floor(-x + 0.5)

// ---- Godot's RandomNumberGenerator (PCG32; randf: the exponent from one draw, the significand from the next)

class Pcg:
    state = 0
    inc = 0
    seed = 0

let M32 = 0xFFFFFFFF
def shr64(x:int, n:int) -> int: return (x >> n) & ((1 << (64 - n)) - 1)

def pcg_next(r:Pcg) -> int:
    let old = r.state
    r.state = old * 6364136223846793005 + r.inc
    let xorshifted = shr64(shr64(old, 18) ^ old, 27) & M32
    let rot = shr64(old, 59)
    return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & M32

def pcg_seed(s:int) -> Pcg:
    let r = Pcg {}
    r.seed = s
    r.inc = (1442695040888963407 << 1) | 1
    pcg_next(r)
    r.state += s
    pcg_next(r)
    return r

def clz32(x:int) -> int:
    var n = 0
    var b = 31
    while b >= 0 and ((x >> b) & 1) == 0:
        n++
        b--
    return n

def f32_of(m:int) -> float:  // an int in [2^31, 2^32) rounded to a float32's 24 bits (to nearest, ties even)
    let low = m & 255
    var top = m >> 8
    if low > 128 or (low == 128 and (top & 1) == 1): top++
    return float(top) * 256.0

def randf(r:Pcg) -> float:
    let e = pcg_next(r)
    if e == 0: return 0.0
    return f32_of(pcg_next(r) | 0x80000001) * pow(2.0, float(-32 - clz32(e)))

let f32_buf = ensure_size("", 4, 0)
def f32(x:float) -> float:  // rounded to a 32-bit float (Godot's real_t)
    write_float32_le(f32_buf, 0, x)
    let v, _n = read_float32_le(f32_buf, 0)
    return v

def randf_range(r:Pcg, a:float, b:float) -> float: return f32(randf(r) * f32(b - a) + a)
def randi(r:Pcg) -> int: return pcg_next(r)

// ---- nodes

// Colours by channel (team-neutral hex for the bake key) and the team colour it's tinted with.
class Colours:
    hex:dictionary<string, string>
    team:float3

class VNode:
    pos = float2_0
    rot = 0.0
    scl = float2_1
    z = 0.0
    visible = true
    alpha = 1.0  // modulate.a (children inherit it)
    kids:[VNode] = []
    parent:VNode? = nil
    // a part (PartShape)
    part = false
    part_id = ""
    pshapes:[JV] = []  // its shapes (they name the colour channels its bake key holds)
    cols:Colours? = nil
    facing = 0
    front = false
    size = 100   // the percent of the art scale its unit is drawn at: baked at that size (D-180)
    shade = 1.0  // self_modulate.a (the far leg in shadow)
    // metas
    rest = 0.0  // a back part's resting turn and scale (wings)
    rest_scale = 1.0
    buzz = false  // a wing blur
    has_tool_z = false
    tool_z = 0.0
    has_seat_rest = false
    seat_rest = float2_0

def add_child(p:VNode, c:VNode):
    c.parent = p
    p.kids.push(c)
