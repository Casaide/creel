// ------------------------------------------------------------------ the UI's look and widgets (src/view/ui/theme.gd, ui_box.gd, ui_materials.gd)
// One small layer every screen draws through, so the Lobster quirks are dealt with once: the
// look from data/ui.json (the "timber" direction: carved wood faces in bronze frames, lit from the
// top left, studs on the corners) and a culture's `ui` block over it; boxes (raised, flat, sunk),
// buttons (hover, pressed, focus, the primary one), and text queued and drawn last (a shape drawn
// after text comes out wrong in this build). Immediate mode: a screen calls ui_button(...) each
// frame and gets true on the frame it's pressed (a click, or A on the pad's focus). The pad moves
// the focus between the buttons drawn this frame with the d-pad or the left stick (nearest in
// that direction). Materials are painted by a shader from the pixel position, so they stay crisp
// and seamless at any size.

// The UI's size: its numbers are for a window 1000 px high (a retina screen has twice the pixels).
def ui() -> float: return max(1.0, float(gl.window_size().y) / 1000.0)

var fake_mouse = float2 { -1.0, -1.0 }  // a mouse that isn't the OS's (screen px), when set: a self-test's, the pad's reticle
def mouse_px() -> float2: return if fake_mouse.x >= 0.0: fake_mouse else: float(gl.mouse_pos(0))

let UI_SHADERS = """
PIXELFUNCTIONS
    float uihash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    vec2 uihash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
    float uinoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(uihash(i), uihash(i + vec2(1.0, 0.0)), u.x), mix(uihash(i + vec2(0.0, 1.0)), uihash(i + vec2(1.0, 1.0)), u.x), u.y);
    }
    float uifbm(vec2 p) { return uinoise(p) * 0.55 + uinoise(p * 2.1 + 7.0) * 0.3 + uinoise(p * 4.3 + 3.0) * 0.15; }
    // cellular: the distance to the nearest feature point (x) and the next nearest (y)
    vec2 uicell(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        float d1 = 8.0;
        float d2 = 8.0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 g = vec2(float(x), float(y));
                float d = length(g + uihash2(i + g) - f);
                if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
            }
        }
        return vec2(d1, d2);
    }
    // UiMaterials._tone: v about 0.8 is the colour itself; lower darkens, higher lightens towards a warm white
    vec3 uitone(vec3 c, float v) {
        float k = v / 0.8;
        if (k <= 1.0) return c * k;
        return mix(c, vec3(1.0, 0.97, 0.9), clamp((k - 1.0) * 0.9, 0.0, 1.0));
    }
    // hammered metal (bronze, gold, iron): soft dimples lit from the top left, scratches running across, blotches
    float uimetal(vec2 p, float rough, float seed) {
        vec2 q = p * 0.045 + seed;
        float d = uicell(q).x;
        float dl = uicell(q - vec2(0.09, 0.09)).x;
        return 0.78 + (d - dl) * 0.75 + 0.12 * (uifbm(p * 0.012 + seed) - 0.5) + rough * 0.25 * (uinoise(vec2(p.x * 0.025, p.y * 0.4) + seed) - 0.5);
    }
    // dressed stone: blocks in staggered courses, each a touch different, speckled, dark joints with a lit lip
    float uistone(vec2 p) {
        float row = floor(p.y / 64.0);
        float sx = p.x + (mod(row, 2.0) > 0.5 ? 64.0 : 0.0);
        float bx = mod(sx, 128.0);
        float by = mod(p.y, 64.0);
        float v = 0.78 + 0.18 * (uifbm(p * 0.02 + 41.0) - 0.5) + 0.12 * (uinoise(p * 0.5 + 42.0) - 0.5);
        v *= 0.94 + 0.06 * sin((row * 3.0 + floor(sx / 128.0)) * 1.7);
        if (bx < 2.0 || by < 2.0) v *= 0.45;
        else if (bx < 3.0 || by < 3.0) v *= 1.12;
        return v;
    }
    float uiparchment(vec2 p) {
        float m = uifbm(p * 0.015 + 51.0);
        return 0.94 + 0.12 * (m - 0.5) - 0.18 * clamp((m - 0.68) * 3.0, 0.0, 1.0) + 0.05 * (uinoise(vec2(p.x * 0.3, p.y * 0.04) + 52.0) - 0.5);
    }

    // the materials at a little over half the strength they were painted with (Dominic: the pause menu's texture was
    // a bit much): the grain stays, behind the words rather than over them
    float uiflat(float v) { return 0.8 + (v - 0.8) * 0.55; }
    // the painted materials of src/view/ui/ui_materials.gd, by kind: 0 wood, 1 bronze, 2 gold, 3 iron, 4 marble,
    // 5 stone, 6 sandstone, 7 parchment, 8 felt, 9 leather, 10 reed, 11 lacquer, 12 bone
    vec3 uipaint(vec3 c, int k, vec2 p) {
        float v = 0.8;
        if (k == 0) {   // wood: long grain, rings, planks with dark seams and a lit lip
            float g = uifbm(vec2(p.x * 0.012, p.y * 0.09));
            v = 0.62 + 0.22 * (0.5 + 0.5 * sin(g * 38.0)) + 0.16 * (uinoise(p * 0.5) - 0.5);
            float py = mod(p.y, 64.0);
            if (py < 2.0) v *= 0.42;
            else if (py < 3.0) v *= 1.18;
            v *= 0.92 + 0.08 * sin(floor(p.y / 64.0) * 2.1);
        } else if (k == 1) {
            v = uimetal(p, 0.4, 21.0);
        } else if (k == 2) {
            v = uimetal(p, 0.2, 23.0);
        } else if (k == 3) {   // iron: hammered and darker, rust blooming in patches
            v = uimetal(p, 0.9, 25.0);
            float r = clamp((uifbm(p * 0.02 + 26.0) - 0.6) * 2.5, 0.0, 0.35);
            return mix(uitone(c, uiflat(v)), vec3(0.478, 0.243, 0.11), r * 0.55);
        } else if (k == 4) {   // marble: pale clouds, thin dark veins on a warped sine
            float w = uifbm(p * 0.008 + 31.0);
            float vein = abs(sin((p.x + p.y) * 6.2832 / 256.0 + w * 14.0));
            v = 0.8 + 0.08 * (uifbm(p * 0.02 + 32.0) - 0.5) - 0.22 * pow(1.0 - vein, 10.0);
        } else if (k == 5) {
            v = uistone(p);
        } else if (k == 6) {   // sandstone: stone's courses, softer, with fine layered bands
            v = uistone(p) * (0.96 + 0.08 * uinoise(vec2(p.x * 0.003, p.y * 0.05) + 43.0));
        } else if (k == 7) {
            v = uiparchment(p);
        } else if (k == 8) {   // felt: dense fuzz, gentle lumps
            v = 0.84 + 0.1 * (uinoise(p * 0.6 + 61.0) - 0.5) + 0.14 * (uifbm(p * 0.03 + 62.0) - 0.5);
        } else if (k == 9) {   // leather: fine pebbled grain, darker creases
            vec2 cd = uicell(p * 0.12 + 71.0);
            v = 0.8 + 0.12 * (uifbm(p * 0.02 + 72.0) - 0.5) - 0.16 * (1.0 - clamp((cd.y - cd.x) * 4.0, 0.0, 1.0));
        } else if (k == 10) {   // woven reed: upright stalks, each rounded by its light, bound across now and then
            float sx = mod(p.x, 16.0) / 16.0;
            float kk = floor(p.x / 16.0);
            v = 0.5 + 0.42 * sin(sx * 3.14159) + 0.1 * (uinoise(vec2(p.x * 0.006, p.y * 0.05) + 81.0) - 0.5) + 0.04 * sin(kk * 2.3);
            float by = mod(p.y + mod(kk, 2.0) * 6.0, 128.0);
            if (by < 10.0) v = 0.45 + 0.4 * sin(by / 10.0 * 3.14159);
            if (mod(p.y + kk * 37.0, 96.0) < 1.0) v *= 0.6;
        } else if (k == 11) {   // lacquer: deep, smooth, a slow gloss, the faintest brush lines
            v = 0.86 + 0.16 * (uifbm(p * 0.01 + 91.0) - 0.5) + 0.04 * (uinoise(vec2(p.x * 0.2, p.y * 0.0125) + 92.0) - 0.5);
        } else {   // bone: parchment, porous
            v = uiparchment(p);
            if (uinoise(p * 0.45 + 95.0) > 0.78) v *= 0.75;
        }
        return uitone(c, uiflat(v));
    }

SHADER uimat
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORM vec4 mcol
        UNIFORM float kind
        UNIFORM float win_h
        UNIFORM float px
        vec2 p = vec2(gl_FragCoord.x, win_h - gl_FragCoord.y) / px;
        frag_color = vec4(uipaint(mcol.rgb, int(kind + 0.5), p), mcol.a);

// any shape, its colour per vertex (the banners' cloth, the stages' turf fading at its edges)
SHADER uimatv
    VERTEX
        INPUTS apos:4 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        icol = acolor;
    PIXEL
        INPUTS icol:4
        UNIFORM float kind
        UNIFORM float win_h
        UNIFORM float px
        vec2 p = vec2(gl_FragCoord.x, win_h - gl_FragCoord.y) / px;
        frag_color = vec4(uipaint(icol.rgb, int(kind + 0.5), p), icol.a);
"""

let UI_MATERIALS = [ "wood", "bronze", "gold", "iron", "marble", "stone", "sandstone", "parchment", "felt", "leather", "reed", "lacquer", "bone" ]
def ui_material(name:string) -> int:
    for(UI_MATERIALS) m, k:
        if m == name: return k
    return 0

class UiLook:
    frame:float4
    face:float4
    button:float4
    primary:float4
    well:float4
    accent:float4
    text:float4
    dim:float4
    title:float4
    metal:float4
    frame_mat = 1  // each role's painted material (UI_MATERIALS): the frames, the panels' faces, the buttons
    panel_mat = 0
    button_mat = 0
    primary_mat = 11
    ornament = "sun"        // the crest (icons/crest_<ornament>.png)
    banner = "swallowtail"  // the cut of a race's banner (src/view/ui/ui_banner.gd)
    cloth = float4_1        // the banner's cloth (the culture's first cloth colour)

var ui_look = UiLook { float4_1, float4_1, float4_1, float4_1, float4_1, float4_1, float4_1, float4_1, float4_1, float4_1 }
var ui_ready = false
var ui_warned = false

def hex4(h:string) -> float4:
    let s = if h.length and h[0] == '#': h.substring(1, h.length - 1) else: h
    def byte(i:int) -> float: return float(string_to_int(s.substring(i, 2), 16)) / 255.0
    return float4 { byte(0), byte(2), byte(4), 1.0 }

// The look: the direction in data/ui.json, a culture's `ui` block over it (families.json) if given.
// Each culture's look is made once (ui_look_of); ui_use puts one in place for what's drawn next.
let ui_looks = dictionary<string, UiLook>(32)

def ui_look_of(culture:string) -> UiLook:
    let had = ui_looks.get(culture)
    if had: return had
    let d = lib_data("ui.json")
    var dir = at(at(d, "directions"), gstr(d, "direction", "timber"))
    let fam = if culture != "" and has(lib_families, culture): family(culture) else: jobj()
    if culture != "":
        let cu = gobj(fam, "ui")
        if cu.keys.length: dir = mod_merge(dir, cu)
    def c(k:string, f:string) -> float4: return hex4(gstr(dir, k, f))
    let lk = UiLook { c("frame_colour", "#9a7438"), c("colour", "#4a3220"), c("button_colour", "#6a4a2c"), c("primary_colour", "#7a2a18"),
                      c("well", "#17110b"), c("accent", "#f2c94c"), c("text", "#f4e9cf"), c("dim", "#c4b493"), c("title", "#f6d77a"), c("metal", "#c09048") }
    lk.frame_mat = ui_material(gstr(dir, "frame", "bronze"))
    lk.panel_mat = ui_material(gstr(dir, "panel", "wood"))
    lk.button_mat = ui_material(gstr(dir, "button", "wood"))
    lk.primary_mat = ui_material(gstr(dir, "primary", "lacquer"))
    lk.ornament = gstr(dir, "ornament", "sun")
    lk.banner = gstr(dir, "banner", "swallowtail")
    let cloth = glist(fam, "cloth")
    lk.cloth = if cloth.length: hex4(as_str(cloth[0])) else: lk.face * float4 { 1.15, 1.15, 1.15, 1.0 } + float4 { 0.06, 0.06, 0.06, 0.0 }
    ui_looks.set(culture, lk)
    return lk

def ui_use(lk:UiLook): ui_look = lk

def ui_setup(culture:string):
    ui_look = ui_look_of(culture)
    if not ui_ready:
        fatal(gl.load_materials(UI_SHADERS, true))
        ui_ready = true

// ---- drawing: shapes now, text queued

class UiText:
    at:float2
    s:string
    size:int
    col:float4
    font:int    // 0 the text face, 1 bold, 2 the display face (titles, names), 3 captions (bold, spaced: theme.gd's caps_font)
    edge:float  // a dark outline this thick (0: none)

var ui_texts = []::UiText
var ui_badge_box = float4_0  // the pad's focused button this frame (at, size; none at 0 wide): ui_flush puts its A badge on it, over the rest
let UI_FONTS = [ "data/fonts/Droid_Sans/DroidSans.ttf", "data/fonts/Droid_Sans/DroidSans-Bold.ttf", "../assets/fonts/display.ttf", "data/fonts/Droid_Sans/DroidSans-Bold.ttf" ]

// A caption's letters' x from its start, measured once by size and words (each measure switches the font: per frame
// it cost more than all the other text, perf:).
let ui_caps_xs = dictionary<string, [float]>(64)
def ui_caps_offsets(s:string, size:int) -> [float]:
    let key = "{size} {s}"
    let have = ui_caps_xs.get(key, []::float)
    if have.length == s.length: return have
    var x = 0.0
    let xs = map(s.length) i:
        let at = x
        x += ui_text_wf(s.substring(i, 1), size, 3) + ui_caps_gap(size)
        at
    ui_caps_xs.set(key, xs)
    return xs

def ui_text(at:float2, s:string, size:int, col:float4): ui_texts.push(UiText { at, s, size, col, 0, 0.0 })

// Text in a face, with a dark edge (titles over pictures).
def ui_text_f(at:float2, s:string, size:int, col:float4, font:int, edge:float): ui_texts.push(UiText { at, s, size, col, font, edge })

// About the room a line of text takes (gl.text_size doesn't match what's drawn at every scale).
def ui_text_w(s:string, size:int) -> float: return 0.52 * float(size) * float(s.length)
// (measured once by face, size and words, then kept: each measure switches the font, and per frame that cost more
// than drawing the text; perf:)
let ui_text_ws = dictionary<string, float>(256)
def ui_text_wf(s:string, size:int, font:int) -> float:
    let key = "{font} {size} {s}"
    let have = ui_text_ws.get(key, -1.0)
    if have >= 0.0: return have
    gl.set_font_name(UI_FONTS[font])
    let was = gl.get_font_size()
    gl.set_font_size(size)
    var w = float(gl.text_size(s).x)
    if font == 3: w += ui_caps_gap(size) * float(max(0, s.length - 1))
    gl.set_font_size(was)
    if font != 0: gl.set_font_name(UI_FONTS[0])
    ui_text_ws.set(key, w)
    return w

// Text centred on x.
def ui_text_c(x:float, y:float, s:string, size:int, col:float4, font:int, edge:float):
    ui_text_f(float2 { x - ui_text_wf(s, size, font) / 2.0, y }, s, size, col, font, edge)

def ui_flush():
    ui_batch_flush()
    let b = ui_badge_box  // (the pad's A badge last, over the words and the widgets beside its button)
    ui_badge_box = float4_0
    let spot = if b.z > 0.0: ui_pad_badge_at(b.xy, b.zw) else: float3_0  // (clear of the words queued in it)
    ui_flush_texts()
    if spot.z > 0.0:
        ui_pad_badge(spot.xy, spot.z, "A")
        ui_batch_flush()
        ui_flush_texts()

def ui_flush_texts():
    text_batch():
        for(ui_texts) t:
            if t.font == 3:  // a caption: a letter at a time, spaced
                for(ui_caps_offsets(t.s, t.size)) x, i:
                    text_label(float2 { t.at.x + x, t.at.y }, t.s.substring(i, 1), t.size, t.col, UI_FONTS[3], t.edge, float4 { 0.0, 0.0, 0.0, 0.85 * t.col.w })
            else: text_label(t.at, t.s, t.size, t.col, UI_FONTS[t.font], t.edge, float4 { 0.0, 0.0, 0.0, 0.85 * t.col.w })
    ui_texts = []

// A flat fill from its top-left corner (meshes in screen coordinates: gl.rect draws -size..size round its
// point in this build, and goes astray once a custom shader has been used).
// A quad in the current transform's coordinates, coloured per vertex (a raw mesh render doesn't pass
// gl.color's colour to the colour shader, so fills use color_attr).
def ui_quad(at:float2, size:float2, col:float4 = float4_1):
    ui_batch_flush()
    gl.draw_mesh("PC", [ float3 { at.x, at.y, 0.0 }, float3 { at.x + size.x, at.y, 0.0 }, float3 { at.x + size.x, at.y + size.y, 0.0 }, float3 { at.x, at.y + size.y, 0.0 } ],
                 [ col, col, col, col ], []::float3, []::float2, []::float2, [ 0, 2, 1, 0, 3, 2 ])

def ui_fill(at:float2, size:float2, col:float4):
    if size.x <= 0.0 or size.y <= 0.0: return
    if ui_batching:
        ui_batch_quad(at, float2 { at.x + size.x, at.y }, at + size, float2 { at.x, at.y + size.y }, col)
        return
    gl.set_shader("color_attr")
    ui_quad(at, size, col)
    gl.set_shader("color")  // (what the callers' own shapes expect next)

// A line as a quad (gl.line draws nothing once a custom shader has been used, in this build).
def ui_line(a:float2, b:float2, w:float, col:float4):
    let d = b - a
    let l = magnitude(d)
    if l <= 0.0001: return
    let n = float2 { -d.y, d.x } / l * (w * 0.5)
    if ui_batching:
        ui_batch_quad(a + n, b + n, b - n, a - n, col)
        return
    gl.set_shader("color_attr")
    gl.draw_mesh("PC", [ float3 { a.x + n.x, a.y + n.y, 0.0 }, float3 { b.x + n.x, b.y + n.y, 0.0 }, float3 { b.x - n.x, b.y - n.y, 0.0 }, float3 { a.x - n.x, a.y - n.y, 0.0 } ],
                 [ col, col, col, col ], []::float3, []::float2, []::float2, [ 0, 2, 1, 0, 3, 2 ])
    gl.set_shader("color")

// Faces, frames and buttons have their material at its own fine scale: Godot's tiles (ui_materials.gd) were painted at
// twice the UI's pixel size and drawn at half, so a material's grain and dimples came out small and quiet.
let UI_MAT_PX = 0.4

// A painted rect; `role` picks the look's material: 0 a panel's face, 1 a frame, 2 a button.
def ui_mat(at:float2, size:float2, col:float4, role:int):
    if size.x <= 0.0 or size.y <= 0.0: return
    ui_batch_flush()
    let kind = if role == 1: ui_look.frame_mat elif role == 2: ui_look.button_mat else: ui_look.panel_mat
    gl.set_shader("uimat")
    let ok = gl.set_uniform("mcol", col) and gl.set_uniform("kind", float(kind)) and gl.set_uniform("win_h", float(gl.window_size().y)) and gl.set_uniform("px", UI_MAT_PX * ui())
    if not ok and not ui_warned:
        print "ui: a uniform did not set"
        ui_warned = true
    // (a mesh in screen coordinates: gl.rect with this shader doesn't land where asked)
    gl.draw_mesh("P", [ float3 { at.x, at.y, 0.0 }, float3 { at.x + size.x, at.y, 0.0 }, float3 { at.x + size.x, at.y + size.y, 0.0 }, float3 { at.x, at.y + size.y, 0.0 } ],
                 []::float4, []::float3, []::float2, []::float2, [ 0, 2, 1, 0, 3, 2 ])
    gl.set_shader("color")

// A rect painted in a material by name (felt turf, a lacquered medallion...), whatever the look's roles are.
def ui_paint(at:float2, size:float2, col:float4, material:string):
    ui_paint_poly([ at, float2 { at.x + size.x, at.y }, at + size, float2 { at.x, at.y + size.y } ], [ col, col, col, col ], [ 0, 2, 1, 0, 3, 2 ], ui_material(material))

// Any shape painted in a material (UI_MATERIALS index), its colour and alpha per vertex.
def ui_paint_poly(pts:[float2], cols:[float4], idx:[int], kind:int):
    ui_batch_flush()
    gl.set_shader("uimatv")
    gl.set_uniform("kind", float(kind))
    gl.set_uniform("win_h", float(gl.window_size().y))
    gl.set_uniform("px", max(1.0, ui()))
    gl.draw_mesh("PC", map(pts) p: float3 { p.x, p.y, 0.0 }, cols, []::float3, []::float2, []::float2, idx)
    gl.set_shader("color")

// A rect shaded by a grid of colours: f(u, v) gives the colour at each point (0..1 across and down).
def ui_shade(at:float2, size:float2, nx:int, ny:int, f) -> void:
    ui_batch_flush()
    let pos = []::float3
    let cols = []::float4
    let idx = []::int
    for(ny + 1) j:
        for(nx + 1) i:
            let u = float(i) / float(nx)
            let v = float(j) / float(ny)
            pos.push(float3 { at.x + size.x * u, at.y + size.y * v, 0.0 })
            cols.push(f(u, v))
    for(ny) j:
        for(nx) i:
            let a = j * (nx + 1) + i
            for([ a, a + nx + 2, a + 1, a, a + nx + 1, a + nx + 2 ]) q: idx.push(q)
    gl.set_shader("color_attr")
    gl.draw_mesh("PC", pos, cols, []::float3, []::float2, []::float2, idx)
    gl.set_shader("color")

// A radial gradient over a rect (a vignette, a pool of light): c0 at `centre` (0..1), c1 at `reach` and beyond.
def ui_radial(at:float2, size:float2, centre:float2, reach:float2, c0:float4, c1:float4):
    ui_shade(at, size, 16, 12) u, v:
        let d = (float2 { u, v } - centre) / reach
        let t = clamp(magnitude(d), 0.0, 1.0)
        c0 + (c1 - c0) * t

// A bevel round the inside of a rect: lit top and left, shadowed bottom and right.
def ui_bevel(at:float2, size:float2, w:float, lit:float, dark:float):
    ui_fill(at, float2 { size.x, w }, float4 { 1.0, 1.0, 1.0, lit })
    ui_fill(at, float2 { w, size.y }, float4 { 1.0, 1.0, 1.0, lit * 0.7 })
    ui_fill(at + float2 { 0.0, size.y - w }, float2 { size.x, w }, float4 { 0.0, 0.0, 0.0, dark })
    ui_fill(at + float2 { size.x - w, 0.0 }, float2 { w, size.y }, float4 { 0.0, 0.0, 0.0, dark * 0.8 })

def ui_outline(at:float2, size:float2, w:float, col:float4):
    ui_fill(at, float2 { size.x, w }, col)
    ui_fill(at + float2 { 0.0, size.y - w }, float2 { size.x, w }, col)
    ui_fill(at, float2 { w, size.y }, col)
    ui_fill(at + float2 { size.x - w, 0.0 }, float2 { w, size.y }, col)

def ui_stud(c:float2, r:float, col:float4):
    if ui_batching:
        ui_batch_disc(c + float2 { 0.6, 0.8 } * r * 0.4, r, 12, float4 { 0.0, 0.0, 0.0, 0.5 })
        ui_batch_disc(c, r, 12, col * float4 { 0.7, 0.7, 0.7, 1.0 })
        ui_batch_disc(c - float2_1 * r * 0.15, r * 0.75, 12, col)
        ui_batch_disc(c - float2_1 * r * 0.35, r * 0.25, 8, float4 { 1.0, 1.0, 1.0, 0.55 })
        return
    gl.set_shader("color")
    gl.color(float4 { 0.0, 0.0, 0.0, 0.5 }): gl.translate(c + float2 { 0.6, 0.8 } * r * 0.4): gl.circle(r, 12)
    gl.color(col * float4 { 0.7, 0.7, 0.7, 1.0 }): gl.translate(c): gl.circle(r, 12)
    gl.color(col): gl.translate(c - float2_1 * r * 0.15): gl.circle(r * 0.75, 12)
    gl.color(float4 { 1.0, 1.0, 1.0, 0.55 }): gl.translate(c - float2_1 * r * 0.35): gl.circle(r * 0.25, 8)

// A box of the look: a bronze frame round a wood face (depth 1 raised, 0 flat, -1 sunk: a well).
def ui_box(at:float2, size:float2, depth:int, face:float4, studs:bool):
    let u = ui()
    let fw = max(3.0, 6.0 * u)
    if depth > 0:
        for(4) k: ui_fill(at + float2 { -1.0, 2.0 } * float(k + 1) * u, size, float4 { 0.0, 0.0, 0.0, 0.08 })  // a soft drop shadow
    ui_mat(at, size, ui_look.frame, 1)
    ui_bevel(at, size, max(1.0, 1.5 * u), 0.32, 0.5)
    let inner = at + float2_1 * fw
    let isz = size - float2_1 * fw * 2.0
    if depth < 0:
        ui_fill(inner, isz, ui_look.well)
        let d = clamp(isz.y * 0.25, 3.0, 12.0 * u)
        for(3) k: ui_fill(inner, float2 { isz.x, d * float(3 - k) / 3.0 }, float4 { 0.0, 0.0, 0.0, 0.25 })
    else:
        ui_mat(inner, isz, face, 0)
        if depth > 0:
            ui_fill(inner + float2 { 0.0, isz.y * 0.5 }, float2 { isz.x, isz.y * 0.5 }, float4 { 0.0, 0.0, 0.0, 0.12 })
            ui_bevel(inner, isz, clamp(min(isz.x, isz.y) * 0.08, 1.5, 4.0 * u), 0.22, 0.42)
    ui_outline(inner, isz, 1.0, float4 { 0.0, 0.0, 0.0, 0.65 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.8 })
    if studs:
        let m = fw * 0.5
        for([ at + float2_1 * m, float2 { at.x + size.x - m, at.y + m }, at + size - float2_1 * m, float2 { at.x + m, at.y + size.y - m } ]) c:
            ui_stud(c, max(2.5, fw * 0.8), ui_look.metal)

// ---- buttons, with the pad's focus

class UiHit:
    at:float2
    size:float2

var ui_label_px = 0      // a button's label size, when a page sets one (the lobby: its type at its scale); 0: by the window
var ui_hits = []::UiHit  // the buttons drawn this frame, in order (for the pad's focus)
var ui_hits_last = []::UiHit
var ui_focus = -1  // index into last frame's buttons; -1: the mouse has it
var ui_pad_a = false
var ui_stick_ready = true

// Called once a frame before any button: the pad's d-pad / stick moves the focus and A presses (pad:
// false in a match, where the pad plays the battlefield and its own wheel does the panel's work).
def ui_frame(pad:bool):
    ui_hits_last = ui_hits
    ui_hits = []
    ui_badge_box = float4_0
    ui_pad_a = pad and gl.button("controller_a") == 1
    if not pad:
        ui_focus = -1
        return
    let d = float2 { (if gl.button("controller_dpright") == 1: 1.0 else: 0.0) - (if gl.button("controller_dpleft") == 1: 1.0 else: 0.0),
                     (if gl.button("controller_dpdown") == 1: 1.0 else: 0.0) - (if gl.button("controller_dpup") == 1: 1.0 else: 0.0) }
    var dir = d
    let stick = float2 { gl.controller_axis(0), gl.controller_axis(1) }
    if magnitude(stick) > 0.6:
        if ui_stick_ready: dir = normalize(stick)
        ui_stick_ready = false
    elif magnitude(stick) < 0.3: ui_stick_ready = true
    if magnitude(dir) > 0.0 and ui_hits_last.length:
        if ui_focus < 0 or ui_focus >= ui_hits_last.length: ui_focus = 0
        else:
            let here = ui_hits_last[ui_focus].at + ui_hits_last[ui_focus].size / 2.0
            var best = -1
            var best_d = 1000000000.0
            for(ui_hits_last) h, k:
                let off = h.at + h.size / 2.0 - here
                let along = dot(off, normalize(dir))
                if k != ui_focus and along > 1.0:
                    let score = along + 2.0 * magnitude(off - normalize(dir) * along)
                    if score < best_d:
                        best_d = score
                        best = k
            if best >= 0: ui_focus = best
    if gl.button("mouse1") == 1 or magnitude(float(gl.mouse_delta(0))) > 2.0:
        if not (magnitude(dir) > 0.0): ui_focus = -1

// A button (primary: the lacquered one). True on the frame it's pressed.
// A click this frame. On touch a press and lift within one frame only shows as the lift, since Lobster
// gives touch the last frame's state (for gl.hit), so that counts as one too.
var ui_touch = false
var ui_was_down = false
var ui_click = false
def ui_click_tick():
    let down, up = gl.button("mouse1")
    ui_click = down == 1 or (ui_touch and down < 1 and up == 1 and not ui_was_down)
    ui_was_down = down >= 1
def ui_clicked(): return ui_click

def ui_button(at:float2, size:float2, label:string, primary:bool) -> bool:
    let u = ui()
    let k = ui_hits.length
    ui_hits.push(UiHit { at, size })
    let m = mouse_px()
    let over = m.x >= at.x and m.y >= at.y and m.x <= at.x + size.x and m.y <= at.y + size.y
    let focused = ui_focus == k
    let down = over and gl.button("mouse1") >= 1
    let face = if primary: ui_look.primary else: ui_look.button
    let lift = if down: float2 { 0.0, 1.5 * u } else: float2_0
    ui_box(at + lift, size, if down: 0 else: 1, if over or focused: face * float4 { 1.18, 1.18, 1.18, 1.0 } else: face, false)
    if over or focused or primary:
        let a = if primary and not (over or focused): 0.45 else: 1.0
        ui_outline(at + lift + float2_1 * 4.0 * u, size - float2_1 * 8.0 * u, 2.0 * u, float4 { ui_look.accent.x, ui_look.accent.y, ui_look.accent.z, a })
    if label != "":  // (bold, as theme.gd's buttons)
        let fs = if ui_label_px > 0: ui_label_px else: int(min(18.0 * u, size.y * 0.45))
        ui_text_f(at + lift + float2 { (size.x - ui_text_wf(label, fs, 1)) / 2.0, (size.y - float(fs)) / 2.0 - 2.0 * u }, label, fs, ui_look.text, 1, 0.0)
    if focused: ui_badge_box = float4 { at.x + lift.x, at.y + lift.y, size.x, size.y }
    return (over and ui_clicked()) or (focused and ui_pad_a)

// Where the pad's A badge goes on the focused button, so it's clear what's picked and how to press it (the console
// way; Godot's pad_mode.gd): inside the button's right end when that's clear of the words queued over it (its label,
// or a caption its page drew), else just past its right edge, or its left one at the screen's edge. Sized to the
// button. Its centre and radius.
def ui_pad_badge_at(at:float2, size:float2) -> float3:
    let u = ui()
    let r = clamp(size.y * 0.55, 22.0 * u, 40.0 * u) / 2.0
    var words = at.x  // (the right end of the words on it)
    for(ui_texts) t:
        let mid = t.at.y + float(t.size) / 2.0
        if t.s.length and mid > at.y and mid < at.y + size.y and t.at.x < at.x + size.x and t.at.x >= at.x - 1.0:
            let w = if t.font == 3: ui_caps_offsets(t.s, t.size).top() + ui_text_wf(t.s.substring(t.s.length - 1, 1), t.size, 3) else: ui_text_wf(t.s, t.size, t.font)
            words = max(words, t.at.x + w)
    var x = at.x + size.x - 1.9 * r
    if size.x < 8.0 * r or words > x - 1.5 * r:  // (a small button, or the words reach the end: beside it, over its rim a little)
        x = at.x + size.x + 0.6 * r
        if x + r > float(gl.window_size().x) - 4.0 * u: x = at.x - 0.6 * r
    return float3 { x, at.y + size.y / 2.0, r }

// A pad button's badge: a light disc with a dark rim and its letter (plain and neutral, like the Deck's own buttons).
def ui_pad_badge(c:float2, r:float, letter:string):
    let rim = float4 { 0.0, 0.0, 0.0, 0.55 }
    let fill = float4 { 0.925, 0.886, 0.784, 1.0 }   // #ece2c8
    let ink = float4 { 0.165, 0.133, 0.098, 1.0 }    // #2a2219
    let inset = max(1.5, r * 0.1)
    if ui_batching:
        ui_batch_disc(c, r, 20, rim)
        ui_batch_disc(c, r - inset, 20, fill)
    else:
        gl.set_shader("color")
        gl.color(rim): gl.translate(c): gl.circle(r, 20)
        gl.color(fill): gl.translate(c): gl.circle(r - inset, 20)
    let fs = int(r * 1.15)
    ui_text_f(c - float2 { ui_text_wf(letter, fs, 1) / 2.0, float(fs) / 2.0 + r * 0.08 }, letter, fs, ink, 1, 0.0)

// A titled panel: a raised box with a caption in the title colour.
def ui_panel(at:float2, size:float2, title:string):
    ui_box(at, size, 1, ui_look.face, true)
    if title != "":
        let u = ui()
        ui_text(at + float2 { 22.0 * u, 14.0 * u }, title, int(24.0 * u), ui_look.title)
