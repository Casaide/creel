// ------------------------------------------------------------------ the HUD kit
// What a game's panels are drawn with, in the look ui.json gives (game/ui.lobster): the HUD's scale, icons by name,
// queued text in three fonts, plaques and wells, frames, buttons, grooves, bars, word wrap, a cost row and a tooltip
// card. A game builds its own top bar and panels from these; Creel has none of its own.

// The HUD's scale: the player's size (hud_size, game/audio.lobster: Ctrl/Cmd + and - in a match) in this window.
def hud_s() -> float: return hud_scale(hud_size, float(gl.window_size()))
let TB_DISPLAY = "../assets/fonts/display.ttf"  // the display font (headings)
let TB_BOLD = "data/fonts/Droid_Sans/DroidSans-Bold.ttf"
let TB_TEXT = "data/fonts/Droid_Sans/DroidSans.ttf"  // (the plain font)

let tb_icons = dictionary<string, resource<texture>>(64)

// An icon by name (icons/<name>.png), the generic research scroll for one there isn't.
def tb_icon_tex(name:string) -> resource<texture>?:
    let t = tb_icons.get(name)
    if t: return t
    let made = gl.load_texture("icons/" + name + ".png", texture_format_clamp)
    if made:
        tb_icons.set(name, made)
        return made
    return if name != "research": tb_icon_tex("research") else: nil

// An icon in a square (top-left corner), kept to its aspect.
def tb_icon(name:string, at:float2, side:float, alpha:float):
    let t = tb_icon_tex(name)
    if not t: return
    let sz = float(gl.texture_size(t))
    let s = side / max(sz.x, sz.y)
    let w = sz * s
    let o = at + (float2_1 * side - w) / 2.0
    let c = float4 { 1.0, 1.0, 1.0, alpha }
    ui_batch_flush()
    gl.set_shader("textured_color")
    gl.set_primitive_texture(0, t)
    gl.color(float4_1):
        gl.draw_mesh("PCT", [ float3 { o.x, o.y, 0.0 }, float3 { o.x + w.x, o.y, 0.0 }, float3 { o.x + w.x, o.y + w.y, 0.0 }, float3 { o.x, o.y + w.y, 0.0 } ],
                     [ c, c, c, c ], []::float3, [ float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 } ], []::float2, [ 0, 2, 1, 0, 3, 2 ])
    gl.set_shader("color")

// An icon of any shape, h high, centred on c (the culture's crest).
def tb_icon_wide(name:string, c:float2, h:float):
    let t = tb_icon_tex(name)
    if not t: return
    let sz = float(gl.texture_size(t))
    let w = sz.x * h / sz.y
    tb_icon(name, c - float2_1 * max(w, h) * 0.5, max(w, h), 1.0)

// Text with its font (0 text, 1 bold, 2 display, 3 a caption: bold and spaced), queued: drawn by tb_flush after every shape.
class TbText:
    at:float2
    s:string
    size:int
    col:float4
    font:int
    outline:bool

var tb_texts = []::TbText

def tb_text(at:float2, s:string, size:int, col:float4, font:int):
    tb_texts.push(TbText { at, s, size, col, font, false })

def tb_text_edged(at:float2, s:string, size:int, col:float4, font:int):
    tb_texts.push(TbText { at, s, size, col, font, true })

def tb_flush():
    ui_batch_flush()
    text_batch():
        for(tb_texts) t:
            let face = if t.font == 2: TB_DISPLAY elif t.font >= 1: TB_BOLD else: TB_TEXT
            let edge = if t.outline: max(1.0, float(t.size) / 12.0) else: 0.0
            if t.font == 3:  // a caption: a letter at a time, spaced
                for(ui_caps_offsets(t.s, t.size)) x, i:
                    text_label(float2 { t.at.x + x, t.at.y }, t.s.substring(i, 1), t.size, t.col, face, edge, float4 { 0.0, 0.0, 0.0, 0.9 })
            else: text_label(t.at, t.s, t.size, t.col, face, edge, float4 { 0.0, 0.0, 0.0, 0.9 })
    tb_texts = []

// A plaque: a sunk well with a thin frame.
def tb_plaque(at:float2, size:float2):
    let s = hud_s()
    let fw = max(1.0, 2.0 * s)
    ui_mat(at, size, ui_look.frame * float4 { 0.7, 0.7, 0.7, 1.0 }, 1)
    let inner = at + float2_1 * fw
    let isz = size - float2_1 * fw * 2.0
    ui_mat(inner, isz, ui_look.face * float4 { 0.38, 0.38, 0.38, 1.0 }, 0)
    ui_fill(inner, isz, ui_look.well * float4 { 1.0, 1.0, 1.0, 0.55 })
    let d = min(isz.y * 0.3, 8.0 * s)
    for(3) k: ui_fill(inner, float2 { isz.x, d * float(3 - k) / 3.0 }, float4 { 0.0, 0.0, 0.0, 0.22 })  // its lip's shadow
    ui_fill(inner, float2 { fw * 0.8, isz.y }, float4 { 0.0, 0.0, 0.0, 0.25 })
    ui_fill(inner + float2 { 0.0, isz.y - 1.0 }, float2 { isz.x, 1.0 }, float4 { 1.0, 1.0, 1.0, 0.1 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.75 })

// A frame of the look: the frame's metal round a face, lit from
// the top left, a soft drop shadow (shadow px), studs on the corners.
def hud_box(at:float2, size:float2, weight:float, face:float4, studs:bool, shadow:float):
    let s = hud_s()
    let fw = max(2.0, weight * s)
    for(4) k: ui_fill(at + float2 { 0.25, 0.5 } * shadow * s * float(k + 1) / 4.0, size, float4 { 0.0, 0.0, 0.0, 0.1 })
    ui_mat(at, size, ui_look.frame, 1)
    ui_bevel(at, size, max(1.0, 1.5 * s), 0.32, 0.5)
    let inner = at + float2_1 * fw
    let isz = size - float2_1 * fw * 2.0
    ui_mat(inner, isz, face, 0)
    ui_bevel(inner, isz, max(1.0, 2.0 * s), 0.12, 0.3)
    ui_outline(inner, isz, 1.0, float4 { 0.0, 0.0, 0.0, 0.65 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.8 })
    if studs:
        let m = fw * 0.5
        for([ at + float2_1 * m, float2 { at.x + size.x - m, at.y + m }, at + size - float2_1 * m, float2 { at.x + m, at.y + size.y - m } ]) c:
            ui_stud(c, max(2.0, fw * 0.6), ui_look.metal)

// A button of the look. True on the frame it's clicked.
def hud_button(at:float2, size:float2, accent:bool, enabled:bool) -> bool:
    let s = hud_s()
    let m = mouse_px()
    let over = m.x >= at.x and m.y >= at.y and m.x <= at.x + size.x and m.y <= at.y + size.y
    let down = over and enabled and gl.button("mouse1") >= 1
    let tint = if not enabled: 0.5 elif down: 0.8 elif over: 1.22 else: 1.0
    if not down and enabled:
        for(2) k: ui_fill(at + float2 { 0.5, 1.5 } * s * float(k + 1), size, float4 { 0.0, 0.0, 0.0, 0.12 })
    let fw = max(2.0, 3.0 * s)
    ui_mat(at, size, ui_look.frame * (if enabled: float4_1 else: float4 { 0.6, 0.6, 0.6, 1.0 }), 1)
    ui_bevel(at, size, max(1.0, 1.0 * s), 0.3, 0.45)
    let inner = at + float2_1 * fw
    let isz = size - float2_1 * fw * 2.0
    ui_mat(inner, isz, ui_look.button * float4 { tint, tint, tint, 1.0 }, 2)
    if down: for(3) k: ui_fill(inner, float2 { isz.x, 6.0 * s * float(3 - k) / 3.0 }, float4 { 0.0, 0.0, 0.0, 0.25 })
    else: ui_bevel(inner, isz, max(1.0, 2.0 * s), 0.2, 0.35)
    ui_outline(inner, isz, 1.0, float4 { 0.0, 0.0, 0.0, 0.6 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.8 })
    let rim = if over and enabled: 0.85 elif down: 0.6 elif accent: 0.7 else: 0.0
    if rim > 0.0: ui_outline(inner, isz, max(1.5, 2.0 * s), float4 { ui_look.accent.x, ui_look.accent.y, ui_look.accent.z, rim })
    return over and enabled and ui_clicked()

def tb_over(at:float2, size:float2) -> bool:
    let m = mouse_px()  // (the self-tests' fake mouse too)
    return m.x >= at.x and m.y >= at.y and m.x <= at.x + size.x and m.y <= at.y + size.y

let PANEL_SHORT = float4 { 0.88, 0.44, 0.38, 1.0 }  // #e07060: a cost you can\'t pay

// A well, as the top bar's plaques.
def hud_well(at:float2, size:float2): tb_plaque(at, size)

// A carved groove down the panel: a dark cut with a light lip; a major one runs
// the height with a bronze diamond at its middle, a minor one starts under the captions and is fainter.
def groove(x:float, top:float, bottom:float, major:bool):
    let s = hud_s()
    let a = if major: 1.0 else: 0.55
    let y0 = top + (if major: 2.0 else: 22.0) * s
    let y1 = bottom - 2.0 * s
    let gx = floor(x + 5.0 * s)
    ui_fill(float2 { gx, y0 }, float2 { max(1.0, s), y1 - y0 }, float4 { 0.0, 0.0, 0.0, 0.6 * a })
    ui_fill(float2 { gx + max(1.0, s), y0 }, float2 { max(1.0, s), y1 - y0 }, float4 { 0.54, 0.45, 0.31, 0.5 * a })
    if major:
        let m = float2 { gx + 0.5 * s, floor((y0 + y1) * 0.5) }
        let d = 4.0 * s
        ui_batch_flush()
        gl.set_shader("color_attr")
        let c = float4 { 0.63, 0.53, 0.35, 1.0 }
        gl.draw_mesh("PC", [ float3 { m.x, m.y - d, 0.0 }, float3 { m.x + d, m.y, 0.0 }, float3 { m.x, m.y + d, 0.0 }, float3 { m.x - d, m.y, 0.0 } ],
                     [ c, c, c, c ], []::float3, []::float2, []::float2, [ 0, 1, 2, 0, 2, 3 ])
        gl.set_shader("color")

// A slim bar: a dark sunk track, the fill raised.
def hud_bar(at:float2, size:float2, frac:float, col:float4):
    ui_fill(at, size, float4 { 0.0, 0.0, 0.0, 0.6 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.7 })
    let w = size.x * clamp(frac, 0.0, 1.0)
    if w > 0.0:
        ui_fill(at, float2 { w, size.y }, col)
        ui_fill(at, float2 { w, max(1.0, size.y * 0.3) }, float4 { 1.0, 1.0, 1.0, 0.3 })
        ui_fill(at + float2 { 0.0, size.y - max(1.0, size.y * 0.25) }, float2 { w, max(1.0, size.y * 0.25) }, float4 { 0.0, 0.0, 0.0, 0.3 })

// Text with a dark edge (queued).
def edged_text(at:float2, s:string, size:int, col:float4, font:int): tb_text_edged(at, s, size, col, font)

// Lines of text no wider than w (word wrap, by the text's estimated width).
def wrap(s:string, size:int, font:int, w:float) -> [string]:
    let out = []::string
    for(tokenize(s, "\n", "")) para:
        var line = ""
        for(tokenize(para, " ", "")) word:
            let next = if line == "": word else: line + " " + word
            if line != "" and tb_text_w(next, size, font) > w:
                out.push(line)
                line = word
            else: line = next
        out.push(line)
    return out

// The cost along a button's foot: each part a number and the resource's icon, shrunk to fit; red when short.
def cost_row(c:[int], at:float2, w:float):
    let s = hud_s()
    let parts = filter(c.length) n: c[n] > 0
    if not parts.length: return
    var fs = 13.0 * s
    def row_w(f:float) -> float:
        var t = 0.0
        for(parts) n: t += tb_text_w(string(c[n]), int(f), 1) + f * 1.15 + 2.0 * s
        return t
    while row_w(fs) > w - 6.0 * s and fs > 7.0 * s: fs -= 1.0
    var x = at.x + (w - row_w(fs)) / 2.0
    for(parts) n:
        let txt = string(c[n])
        let tw = tb_text_w(txt, int(fs), 1)
        edged_text(float2 { x, at.y }, txt, int(fs), if stock[n][ME] < c[n]: PANEL_SHORT else: float4_1, 1)
        tb_icon("res_" + resource_names[n], float2 { x + tw + 1.0 * s, at.y + 1.0 * s }, fs * 1.15, 1.0)
        x += tw + fs * 1.15 + 2.0 * s

// A tooltip card: the name in bold, the cost (each part a number and its icon, red when
// short), then the tip's lines, wrapped. A line can start with a mark: "!" red (what stops it), "+" green (what it
// gives), "~" dim (an aside). A disabled button's plain tip, with no marks at all, shows red. Drawn after everything
// queued under it, so the panel's own words don't show through.
let TIP_GOOD = float4 { 0.56, 0.82, 0.45, 1.0 }
let TIP_TEXT = float4 { 0.94, 0.89, 0.78, 1.0 }

def tip_line_marked(l:string) -> bool:
    if l == "": return false
    let mark = l.substring(0, 1)
    return mark == "!" or mark == "+" or mark == "~"

def tip_card(m:float2, name:string, costv:[int], tip:string, ok:bool):
    tb_flush()
    ui_flush()
    let s = hud_s()
    let fs = int(14.0 * s)
    let lh = 19.0 * s
    let maxw = 360.0 * s
    let rows = []::string
    let cols = []::float4
    let tiplines = tokenize(tip, "\n", "")
    let has_marks = exists(tiplines): tip_line_marked(_)
    for(tiplines) raw:
        if raw == "": continue
        let mark = raw.substring(0, 1)
        let col = if mark == "!": PANEL_SHORT elif mark == "+": TIP_GOOD elif mark == "~": ui_look.dim elif not ok and not has_marks: PANEL_SHORT else: TIP_TEXT
        let body = if tip_line_marked(raw): raw.substring(1, raw.length - 1) else: raw
        for(wrap(body, fs, 0, maxw)) l:
            rows.push(l)
            cols.push(col)
    let parts = filter(costv.length) r: costv[r] > 0
    let ifs = 14.0 * s
    var cost_w = 0.0
    for(parts) r: cost_w += tb_text_w(string(costv[r]), int(ifs), 1) + ifs * 1.2 + 10.0 * s
    var w = tb_text_w(name, int(16.0 * s), 1)
    w = max(w, cost_w)
    for(rows) l: w = max(w, tb_text_w(l, fs, 0))
    w += 28.0 * s
    let cost_h = if parts.length: lh + 2.0 * s else: 0.0
    let h = 16.0 * s + 22.0 * s + cost_h + float(rows.length) * lh + 8.0 * s
    let at = float2 { clamp(m.x - w * 0.3, 4.0, float(gl.window_size().x) - w - 4.0), max(4.0, m.y - h - 14.0 * s) }
    hud_box(at, float2 { w, h }, 3.0, ui_look.face * float4 { 1.08, 1.08, 1.08, 1.0 }, false, 4.0)
    tb_text(at + float2 { 14.0 * s, 9.0 * s }, name, int(16.0 * s), ui_look.title, 1)
    var y = at.y + 9.0 * s + 22.0 * s
    if parts.length:
        var x = at.x + 14.0 * s
        for(parts) r:
            let txt = string(costv[r])
            let tw = tb_text_w(txt, int(ifs), 1)
            edged_text(float2 { x, y }, txt, int(ifs), if stock[r][ME] < costv[r]: PANEL_SHORT else: float4_1, 1)
            tb_icon("res_" + resource_names[r], float2 { x + tw + 2.0 * s, y + 1.0 * s }, ifs * 1.15, 1.0)
            x += tw + ifs * 1.2 + 10.0 * s
        y += cost_h
    for(rows) l, n: tb_text(float2 { at.x + 14.0 * s, y + float(n) * lh }, l, fs, cols[n], 0)
    tb_flush()
    ui_flush()
