// ------------------------------------------------------------------ the match pack (art_pack.gd)
// The sheets and index.txt: every frame (sheet, rect, anchor), the units' animations, the building
// looks, the doodad counts, the resource props, the ground colours and the tree cells' species.
// Art pixels throughout: a tile is 96 x 48 (Iso.to_screen * 1.5).

class Frame:
    sheet:int
    x:int
    y:int
    w:int
    h:int
    ox:int  // the anchor inside the frame
    oy:int
    k:float  // world art px a texture px (world art baked at ART_SCALE: 1 / ART_K)

class Look:
    body:string
    stages:[string]  // the four construction stages ("-": none)
    front:string
    arms:[string] = []        // a wall's arm towards each neighbour (Models.LINKS order), "-": none
    arms_front:[string] = []  // their near merlons
    ruins:[string] = []       // broken up (game/ruin.lobster): battered, breaking, collapsed, the ruin it leaves
    towers:[string] = []      // a gate's towers, each its own frame sorted at its own footprint, and the gate without them
    tower_dy:[float] = []     // each tower's place down the screen from the gate's middle (canvas art px)

let sheet_tex = []::resource<texture>
let sheet_dims = []::float2             // each sheet's size in px (the pack's are all sheet_size; a part baked in the game is its own)
let sheet_file = []::string             // a sheet not loaded yet: its PNG, loaded when it's first drawn ("": loaded)
let sheet_formats = []::int             // and the texture formats to load it with
let sheet_none = []::resource<texture>  // (the one stand-in texture for sheets not loaded yet)

// A sheet: its texture now, or its PNG (shipped or cached art) to load when it's first drawn. formats: the texture's
// (-1: not known, then it's never copied into an atlas page).
def add_sheet(tex:resource<texture>, dims:float2, formats:int = -1):
    sheet_tex.push(tex)
    sheet_dims.push(dims)
    sheet_file.push("")
    sheet_formats.push(formats)
    sheet_drawn_from()

def add_sheet_later(file:string, dims:float2, formats:int):
    if not sheet_none.length: sheet_none.push(gl.create_texture([ [ float4_0 ] ], texture_format_nomipmap))
    sheet_tex.push(sheet_none[0])
    sheet_dims.push(dims)
    sheet_file.push(file)
    sheet_formats.push(formats)
    sheet_drawn_from()

def sheet_texture(i:int) -> resource<texture>:
    if sheet_file[i] != "":
        sheet_tex[i] = assert gl.load_texture(sheet_file[i], sheet_formats[i])
        sheet_file[i] = ""
    return sheet_tex[i]
let frames = []::Frame
let frame_at = dictionary<string, int>(32768)
let looks = dictionary<string, Look>(512)
var arch_of = []::string  // per player
let doodads = dictionary<string, int>(64)
var pack_rules = "default"                    // the host rules the pack's races were made with
var pack_mods = []::string                    // the mods they were made with
let prop_of = dictionary<string, string>(64)  // terrain id -> prop kind
let ground_a = []::float4                     // per terrain: its two colours
let ground_b = []::float4
var species = []::string   // per cell: a tree's species, or "-"
let team_rgb = []::float4  // per player
let unit_names = dictionary<int, string>(128)
let unit_blow = dictionary<int, string>(128)  // per unit type: its melee blow's sound, its shot's
let unit_shot = dictionary<int, string>(128)
let unit_shotk = dictionary<int, string>(128)  // the shot each unit type looses (combat_fx.shot_kind)
let building_names = dictionary<int, string>(64)
let research_names = dictionary<int, string>(128)
var pack_map = ""  // the match the art was baked for: its map and races' prompts
let pack_prompts = []::string
var pack_library = false  // the pack is the part library: every race's units, any race
let pack_formats = texture_format_nearest_mag | texture_format_nearest_min | texture_format_nomipmap | texture_format_clamp

// Where a building look's chimney smokes, its lantern and windows glow (canvas units from its anchor;
// fx.txt, from building_fx.gd).
class BFx:
    smoke:float2
    has_smoke:bool
    lights:[float2]  // the lantern first, if it has one

let bfx = dictionary<string, BFx>(256)

def frame_index(name:string) -> int: return frame_at.get(name, -1)

def spaced(s:string) -> string: return concat_string(tokenize(s, "_", ""), " ")

// ArtKit.building_key: the newest age look at or below the age, else a variant (houses), else the base.
def building_key(arch:string, type:string, age:int, pick:int) -> string:
    var a = age
    while a > 1:
        let key = "{arch}:{type}@{a}"
        if looks.get(key): return key
        a--
    let variant = "{arch}:{type}#{pick}"
    return if pick > 0 and looks.get(variant): variant else: "{arch}:{type}"

// ArtKit.staged: a doodad's bake name.
def staged(kind:string, variant:int, stage:int) -> string:
    return if stage == 0: "{kind}{variant}" else: "{kind}{variant}.{stage}"

// ArtKit.resource_stage: whole, started, nearly gone, used up.
def resource_stage(kind:string, left:int, full:int) -> int:
    let staged_kind = kind == "reeds" or kind == "bush" or kind == "quarry" or kind == "gold" or kind == "carcass" or
        kind == "tree_broadleaf" or kind == "tree_pine" or kind == "tree_swamp"
    if not staged_kind: return 0
    if left <= 0: return 3
    if left >= full: return 0
    if kind == "bush": return if left * 2 > full: 1 else: 2
    return if left * 100 > full * 45: 1 else: 2

// ------------------------------------------------------------------ drawing sprites
// Quads gathered into one mesh a sheet change; the sprite shader recolours the team key with the
// vertex colour's rgb and darkens by its alpha (sprite_faded: one fading out).

// A sprite's colour goes to the GPU in bytes with no clamp, so its light (the shader's multiplier, up to 2.8 in a hit's flash)
// travels as light * 91 / 255, which keeps 1.0 exact (the shader multiplies by 255 / 91).
let SPRITE_LIGHT = 91.0 / 255.0

let SPRITE_SHADERS = """
PIXELFUNCTIONS
    // a sprite's texel, the team key recoloured (rgb premultiplied by alpha)
    vec4 sprite_texel(sampler2D tex, ivec2 p, ivec2 hi, vec3 team) {
        vec4 t = texelFetch(tex, clamp(p, ivec2(0), hi), 0);
        vec3 rgb = t.rgb;
        if (min(t.r, t.b) - t.g > 0.22 && abs(t.r - t.b) < 0.3) rgb = team * max(t.r, t.b) * 1.08;
        return vec4(rgb * t.a, t.a);
    }
SHADER sprite
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
        icolor = acolor;
    PIXEL
        INPUTS itc:2 icolor:4
        UNIFORMS tex0
        UNIFORM float gone
        UNIFORM float even
        // (sprite_even: at a zoom between whole numbers, nearest sampling draws an art px two screen px wide, then
        // three, and edges look jagged. Sharp bilinear: each art px is solid, and only the one screen px where two
        // meet is a mix of them, so every art px reads the same size and stays crisp. At a whole zoom it is nearest.)
        // (each texel recoloured before they're mixed, and mixed with their alpha, so a clear texel's colour doesn't
        // darken an edge)
        ivec2 sz = textureSize(tex0, 0);
        vec2 p = itc * vec2(sz) - 0.5;
        vec2 i = floor(p);
        vec2 f = p - i;
        if (even > 0.5) {
            vec2 s = 1.0 / max(fwidth(itc * vec2(sz)), vec2(0.0001));  // screen px an art px
            f = clamp((f - 0.5) * s + 0.5, 0.0, 1.0);
        } else {
            f = step(0.5, f);  // (nearest)
        }
        ivec2 a = ivec2(i);
        ivec2 hi = sz - 1;
        vec4 m = mix(mix(sprite_texel(tex0, a, hi, icolor.rgb), sprite_texel(tex0, a + ivec2(1, 0), hi, icolor.rgb), f.x),
                     mix(sprite_texel(tex0, a + ivec2(0, 1), hi, icolor.rgb), sprite_texel(tex0, a + ivec2(1, 1), hi, icolor.rgb), f.x), f.y);
        if (m.a < 0.02) discard;
        frag_color = vec4(m.rgb / m.a * icolor.a * 2.8021978, m.a * (1.0 - gone));
SHADER sprite_copy
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0
        frag_color = texture(tex0, itc);
SHADER text_premul
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0 col
        vec4 c = texture(tex0, itc) * col;
        frag_color = vec4(c.rgb * c.a, c.a);
SHADER text_page
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0
        frag_color = texture(tex0, itc);
"""

// Fills and lines gathered into one draw (ui_batch, game/ui.lobster draws them): many small ones (a button's bevels, dashes, rings) are a
// draw call each otherwise. Anything else drawn inside a batch calls ui_batch_flush first, so it lands on top.
var ui_batching = false
var ui_bpos = []::float3
var ui_bcol = []::float4
var ui_bidx = []::int

// The fills and lines gathered so far, drawn.
def ui_batch_flush():
    if ui_bpos.length:
        gl.set_shader("color_attr")
        gl.draw_mesh("PC", ui_bpos, ui_bcol, []::float3, []::float2, []::float2, ui_bidx)
        gl.set_shader("color")
    ui_bpos = []
    ui_bcol = []
    ui_bidx = []

// The ui_fills and ui_lines in body drawn together (until something else is drawn).
def ui_batch(body):
    ui_batching = true
    body()
    ui_batch_flush()
    ui_batching = false

// A disc of n sides as gl.circle makes it (its points from 1 radian on, a fan from the first).
def ui_batch_disc(c:float2, r:float, n:int, col:float4):
    let v = ui_bpos.length
    let step = 360.0 / float(n)
    let first = 57.29577951308232  // (1 radian, in degrees)
    for(n) i:
        ui_bpos.push(float3 { c.x + sin(float(i) * step + first) * r, c.y + cos(float(i) * step + first) * r, 0.0 })
        ui_bcol.push(col)
    for(n - 2) i:
        ui_bidx.push(v)
        ui_bidx.push(v + i + 1)
        ui_bidx.push(v + i + 2)

def ui_batch_quad(a:float2, b:float2, c:float2, d:float2, col:float4):
    let v = ui_bpos.length
    ui_bpos.push(float3 { a.x, a.y, 0.0 })
    ui_bpos.push(float3 { b.x, b.y, 0.0 })
    ui_bpos.push(float3 { c.x, c.y, 0.0 })
    ui_bpos.push(float3 { d.x, d.y, 0.0 })
    for(4): ui_bcol.push(col)
    for([ 0, 2, 1, 0, 3, 2 ]) q: ui_bidx.push(v + q)

var b_pos = []::float3
var b_col = []::float4
var b_tc = []::float2
var b_idx = []::int
var b_sheet = -1
var sprite_snap = 1.0  // device px a world art px while the world is drawn: a sprite lands on a whole one (#358)

var sprite_shader = "sprite"  // what flush_sprites draws with (the atmosphere's shade buffer draws the same sprites through its own)
var sprite_even = false       // art px all the same size at a zoom between whole numbers (sharp bilinear; docs/settings.md)

def flush_sprites():
    ui_batch_flush()  // (fills batched before these sprites go under them; and out before a bust's framebuffer)
    if b_pos.length:
        gl.set_shader(sprite_shader)
        if sprite_shader == "sprite": gl.set_uniform("even", if sprite_even: 1.0 else: 0.0)
        gl.set_primitive_texture(0, sheet_texture(b_sheet))
        gl.draw_mesh("PCT", b_pos, b_col, []::float3, b_tc, []::float2, b_idx)
    b_pos = []::float3
    b_col = []::float4
    b_tc = []::float2
    b_idx = []::int

// ---- atlas pages
// Every baked frame is a sheet of its own (a part's facing, a prop, a building's stage), so sprites drawn one after
// another rarely share a texture: a world of 70 sprites took 50 draws a frame. A small sheet, once drawn, is copied
// into a shared page (atlas_pack, at the top of the next frame) and its sprites are drawn from there; its own
// texture stays for whoever reads its pixels (frames keep their sheet).

let ATLAS_SIZE = 2048
let ATLAS_MAX = 512  // px: a sheet wider or taller stays on its own
let ATLAS_GAP = 2    // px of nothing round each (linear filtering would bleed a neighbour in)

class AtlasPage:
    sheet:int  // the page is a sheet too
    tex:resource<texture>
    formats:int
    x:int = 0  // the shelf being filled: its left edge free from here, its top, its height
    y:int = 0
    h:int = 0

let atlas_pages = []::AtlasPage
let sheet_draw = []::int     // per sheet: the sheet its sprites are drawn from (itself, or the page it's on)
let sheet_off = []::float2   // and where on it (px)
let sheet_wanted = []::bool  // drawn on its own, waiting for a page
var atlas_queue = []::int

def sheet_drawn_from():
    sheet_draw.push(sheet_tex.length - 1)
    sheet_off.push(float2_0)
    sheet_wanted.push(false)

def atlas_want(i:int):
    if sheet_wanted[i] or sheet_draw[i] != i or sheet_formats[i] < 0: return
    let d = sheet_dims[i]
    if d.x > float(ATLAS_MAX) or d.y > float(ATLAS_MAX): return
    sheet_wanted[i] = true
    atlas_queue.push(i)

// A place w x h on a page in these formats (a new page when they're full).
def atlas_place(w:int, h:int, formats:int) -> AtlasPage, int2:
    for(atlas_pages) p:
        if p.formats == formats:
            if p.x + w > ATLAS_SIZE:
                p.y += p.h
                p.x = 0
                p.h = 0
            if p.y + h <= ATLAS_SIZE:
                let at = int2 { p.x, p.y }
                p.x += w
                p.h = max(p.h, h)
                return p, at
    let tex = gl.create_blank_texture(int3 { ATLAS_SIZE, ATLAS_SIZE, 0 }, formats)
    add_sheet(tex, float2_1 * float(ATLAS_SIZE))
    let p = AtlasPage { sheet_tex.length - 1, tex, formats }
    atlas_pages.push(p)
    gl.switch_to_framebuffer(tex)
    gl.clear(float4_0)
    gl.switch_to_framebuffer(nil)
    p.x = w
    p.h = h
    return p, int2_0

// The sheets drawn on their own since the last frame, copied onto pages. Outside any transform (a frame's start).
def atlas_pack():
    text_pack()  // (game/text_cache.lobster)
    if not atlas_queue.length: return
    flush_sprites()
    b_sheet = -1
    for(atlas_queue) i:
        let d = int2 { int(sheet_dims[i].x), int(sheet_dims[i].y) }
        let p, at = atlas_place(d.x + ATLAS_GAP * 2, d.y + ATLAS_GAP * 2, sheet_formats[i])
        let o = float(at + int2_1 * ATLAS_GAP)
        let e = o + float(d)
        gl.switch_to_framebuffer(p.tex)
        gl.ortho()
        let was = gl.blend(blend_none)
        gl.set_shader("sprite_copy")
        gl.set_primitive_texture(0, sheet_texture(i))
        // (a framebuffer's rows run bottom up: drawn flipped, the page reads as the sheets do)
        let n = float(ATLAS_SIZE)
        gl.draw_mesh("PT", [ float3 { o.x, n - o.y, 0.0 }, float3 { e.x, n - o.y, 0.0 }, float3 { e.x, n - e.y, 0.0 }, float3 { o.x, n - e.y, 0.0 } ],
                     []::float4, []::float3, [ float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 } ], []::float2,
                     [ 0, 2, 1, 0, 3, 2 ])
        gl.blend(was)
        gl.switch_to_framebuffer(nil)
        gl.ortho()
        sheet_draw[i] = p.sheet
        sheet_off[i] = o
        sheet_wanted[i] = false
    atlas_queue = []

// The sheet frame f is drawn from now (batched with the sprites before it if it's the same), and where on it.
def sprite_sheet(fr:Frame) -> float2:
    let ds = sheet_draw[fr.sheet]
    if ds != b_sheet:
        flush_sprites()
        b_sheet = ds
    if ds == fr.sheet: atlas_want(ds)
    return sheet_off[fr.sheet] + float2 { float(fr.x), float(fr.y) }

// Frame f with its anchor at (x, y) (art px), team colour and shade in col; flip: mirrored.
def sprite(f:int, x:float, y:float, col:float4):
    let fr = frames[f]
    let at = sprite_sheet(fr)
    let x0 = floor(x * sprite_snap) / sprite_snap - float(fr.ox) * fr.k
    let y0 = floor(y * sprite_snap) / sprite_snap - float(fr.oy) * fr.k
    let x1 = x0 + float(fr.w) * fr.k
    let y1 = y0 + float(fr.h) * fr.k
    let s = sheet_dims[b_sheet]
    let u0 = at.x / s.x
    let v0 = at.y / s.y
    let u1 = (at.x + fr.w) / s.x
    let v1 = (at.y + fr.h) / s.y
    let n = b_pos.length
    b_pos.push(float3 { x0, y0, 0.0 })
    b_pos.push(float3 { x1, y0, 0.0 })
    b_pos.push(float3 { x1, y1, 0.0 })
    b_pos.push(float3 { x0, y1, 0.0 })
    b_tc.push(float2 { u0, v0 })
    b_tc.push(float2 { u1, v0 })
    b_tc.push(float2 { u1, v1 })
    b_tc.push(float2 { u0, v1 })
    for(4): b_col.push(float4 { col.x, col.y, col.z, col.w * SPRITE_LIGHT })
    b_idx.push(n)
    b_idx.push(n + 2)
    b_idx.push(n + 1)
    b_idx.push(n)
    b_idx.push(n + 3)
    b_idx.push(n + 2)

// One sprite fading out (a ruin): drawn alone, how far it's gone a uniform (0 by default: the vertex colour is bytes,
// it can't carry it). fade: 1 whole .. 0 gone.
def sprite_faded(f:int, x:float, y:float, col:float4, fade:float):
    flush_sprites()
    gl.set_shader("sprite")
    gl.set_uniform("gone", 1.0 - fade)
    b_sheet = sheet_draw[frames[f].sheet]
    sprite(f, x, y, col)
    flush_sprites()
    gl.set_shader("sprite")
    gl.set_uniform("gone", 0.0)
    b_sheet = -1

// Frame f drawn through an affine transform from its texture px to art px ([xx, xy, yx, yy, ox, oy]:
// a composed unit's part, turned and scaled as its rig says).
def sprite_xf(f:int, xf:[float], col:float4):
    let fr = frames[f]
    let at = sprite_sheet(fr)
    let s = sheet_dims[b_sheet]
    let n = b_pos.length
    for([ float2 { 0.0, 0.0 }, float2 { float(fr.w), 0.0 }, float2 { float(fr.w), float(fr.h) }, float2 { 0.0, float(fr.h) } ]) c:
        b_pos.push(float3 { xf[0] * c.x + xf[2] * c.y + xf[4], xf[1] * c.x + xf[3] * c.y + xf[5], 0.0 })
    b_tc.push(at / s)
    b_tc.push((at + float2 { float(fr.w), 0.0 }) / s)
    b_tc.push((at + float2 { float(fr.w), float(fr.h) }) / s)
    b_tc.push((at + float2 { 0.0, float(fr.h) }) / s)
    for(4): b_col.push(float4 { col.x, col.y, col.z, col.w * SPRITE_LIGHT })
    for([ n, n + 2, n + 1, n, n + 3, n + 2 ]) k: b_idx.push(k)
