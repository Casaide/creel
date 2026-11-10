// ------------------------------------------------------------------ text from atlas pages
// gl.text is a draw a call, an edged label six. Each distinct label (its face, size, colour, edge, string and where
// it falls inside a pixel) is drawn once into a page the frame after it's first asked for (text_pack, from
// atlas_pack), premultiplied, so its layers composite as they did on the screen; then it's a quad, a batch's labels
// one draw a page. Until it's on a page a label is drawn the old way; a frame packs at most TEXT_NEW (numbers that
// change every frame stay drawn the old way). When the pages are full the least recently used one is emptied.
// Dominic (2026-11-03): "We definitely can't have text slowing down the game."

let TEXT_PAGE = 1024
let TEXT_PAGES = 4
let TEXT_NEW = 24                                      // labels packed a frame
let TEXT_FACE = "data/fonts/Droid_Sans/DroidSans.ttf"  // (the game's font, put back after)
let TEXT_EDGES = [ float2 { -1.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 0.0, -1.0 }, float2 { 0.0, 1.0 }, float2 { 1.0, 1.0 } ]

class TextLabel:
    s:string
    face:string
    size:int
    col:float4
    edge:float  // the dark edge's thickness (0: none)
    edgecol:float4
    frac:int2      // where it falls inside a pixel (64ths)
    page:int = -1  // where it's drawn from (-1: not yet, -2: never, too big for a page)
    at:int2 = int2_0
    dims:int2 = int2_0
    pad:int2 = int2_0

class TextPage:
    tex:resource<texture>
    labels:[TextLabel] = []
    used:int = 0  // the frame it was last drawn from
    x:int = 0     // the shelf being filled
    y:int = 0
    h:int = 0

let text_labels = dictionary<string, [TextLabel]>(1024)  // by their string
let text_pages = []::TextPage
var text_queue = []::TextLabel
var text_frame = 0
var text_batching = false
var text_pos = []::float3
var text_tc = []::float2
var text_idx = []::int
var text_page = -1    // the page the gathered quads are on
var text_off = false  // (measuring: every label the old way)
var text_time = 0.0   // seconds spent in text_batch (perf: guards it)

def text_same(t:TextLabel, face:string, size:int, col:float4, edge:float, edgecol:float4, frac:int2) -> bool:
    return t.size == size and t.edge == edge and t.face == face and t.col == col and t.edgecol == edgecol and t.frac == frac

def text_forget(t:TextLabel):
    let ts = text_labels.get(t.s, [])
    ts.remove_obj(t)
    if not ts.length: text_labels.del(t.s)

// The label drawn with gl.text at at (its edge first), in the current shader; the game's font put back after.
def text_direct(at:float2, t:TextLabel):
    gl.set_font_name(t.face)
    gl.set_font_size(t.size)
    if t.edge > 0.0:
        for(TEXT_EDGES) d: gl.color(t.edgecol): gl.translate(at + d * t.edge): gl.text(t.s)
    gl.color(t.col): gl.translate(at): gl.text(t.s)
    if t.face != TEXT_FACE: gl.set_font_name(TEXT_FACE)

// The quads gathered so far, drawn.
def text_flush():
    if text_pos.length:
        let was = gl.blend(blend_pre_multiplied_alpha)
        gl.set_shader("text_page")
        gl.set_primitive_texture(0, text_pages[text_page].tex)
        gl.draw_mesh("PT", text_pos, []::float4, []::float3, text_tc, []::float2, text_idx)
        gl.blend(was)
        gl.set_shader("color")
    text_pos = []
    text_tc = []
    text_idx = []

// The labels drawn in body gathered into a draw a page (nothing else may be drawn inside).
def text_batch(body):
    let t0 = seconds_elapsed()
    text_batching = true
    body()
    text_flush()
    text_batching = false
    text_time += seconds_elapsed() - t0

def text_quad(t:TextLabel, at:int2):
    if t.page != text_page:
        text_flush()
        text_page = t.page
    text_pages[t.page].used = text_frame
    let o = float(at - t.pad)
    let e = o + float(t.dims)
    let n = float(TEXT_PAGE)
    let u0 = float(t.at.x) / n
    let u1 = float(t.at.x + t.dims.x) / n
    let v0 = 1.0 - float(t.at.y) / n  // (a framebuffer's rows run bottom up)
    let v1 = 1.0 - float(t.at.y + t.dims.y) / n
    let k = text_pos.length
    text_pos.push(float3 { o.x, o.y, 0.0 })
    text_pos.push(float3 { e.x, o.y, 0.0 })
    text_pos.push(float3 { e.x, e.y, 0.0 })
    text_pos.push(float3 { o.x, e.y, 0.0 })
    text_tc.push(float2 { u0, v0 })
    text_tc.push(float2 { u1, v0 })
    text_tc.push(float2 { u1, v1 })
    text_tc.push(float2 { u0, v1 })
    for([ 0, 2, 1, 0, 3, 2 ]) q: text_idx.push(k + q)

// A label at at (px in the current transform, which must only move it by whole pixels): s in the face (a font
// file) at size px, coloured col; edge > 0: a dark edge that thick in edgecol under it.
def text_label(at:float2, s:string, size:int, col:float4, face:string, edge:float, edgecol:float4):
    if not s.length: return
    let q = int2 { int(floor(at.x * 64.0 + 0.5)), int(floor(at.y * 64.0 + 0.5)) }
    let fr = int2 { q.x & 63, q.y & 63 }
    let ts = text_labels.get(s, [])
    let k = find(ts) l: text_same(l, face, size, col, edge, edgecol, fr)
    var t = if k >= 0: ts[k] else: nil
    if not t and not text_off and text_queue.length < TEXT_NEW:
        let nt = TextLabel { s, face, size, col, edge, edgecol, fr }
        if not ts.length: text_labels.set(s, ts)
        ts.push(nt)
        text_queue.push(nt)
        t = nt
    if t and t.page >= 0:
        ui_batch_flush()
        text_quad(t, (q - fr) / 64)
        if not text_batching: text_flush()
        return
    ui_batch_flush()
    text_flush()
    text_direct(at, t or TextLabel { s, face, size, col, edge, edgecol, int2_0 })

// A place w x h on a page (the least recently used page emptied when they're full); -1 when every page was drawn
// from last frame, -2 when it's bigger than a page.
def text_place(w:int, h:int) -> int, int2:
    if w > TEXT_PAGE or h > TEXT_PAGE: return -2, int2_0
    for(text_pages) p, i:
        if p.x + w > TEXT_PAGE:
            p.y += p.h
            p.x = 0
            p.h = 0
        if p.y + h <= TEXT_PAGE:
            let at = int2 { p.x, p.y }
            p.x += w
            p.h = max(p.h, h)
            return i, at
    var i = text_pages.length
    if i < TEXT_PAGES:
        text_pages.push(TextPage { gl.create_blank_texture(int3 { TEXT_PAGE, TEXT_PAGE, 0 }, texture_format_clamp | texture_format_nomipmap) })
    else:
        i = find_best<int>(text_pages) p: -p.used
        if text_pages[i].used >= text_frame - 1: return -1, int2_0  // (all in use: drawn the old way)
        for(text_pages[i].labels) l: text_forget(l)
    let p = text_pages[i]
    p.labels = []
    p.x = w
    p.y = 0
    p.h = h
    gl.switch_to_framebuffer(p.tex)
    gl.clear(float4_0)
    gl.switch_to_framebuffer(nil)
    return i, int2_0

// The labels asked for since the last frame, drawn onto pages. Outside any transform (a frame's start).
def text_pack():
    text_frame++
    if not text_queue.length: return
    text_flush()
    let size = gl.get_font_size()
    let q = text_queue
    text_queue = []
    for(q) t:
        gl.set_font_name(t.face)
        gl.set_font_size(t.size)
        let e = int(t.edge + 0.999)
        t.pad = int2 { e + 3, e + 3 + t.size / 3 }
        t.dims = int2 { gl.text_size(t.s).x, t.size } + t.pad * 2
        let i, at = text_place(t.dims.x, t.dims.y)
        if i == -1:
            text_forget(t)
        elif i == -2:
            t.page = -2
        else:
            t.page = i
            t.at = at
            text_pages[i].labels.push(t)
            gl.switch_to_framebuffer(text_pages[i].tex)
            gl.ortho()
            let was = gl.blend(blend_pre_multiplied_alpha)
            gl.use_default_font_shader(false)
            gl.set_shader("text_premul")
            text_direct(float(at + t.pad) + float(t.frac) / 64.0, t)
            gl.use_default_font_shader(true)
            gl.blend(was)
            gl.switch_to_framebuffer(nil)
            gl.ortho()
    gl.set_font_name(TEXT_FACE)
    if size > 0: gl.set_font_size(size)
    gl.set_shader("color")
