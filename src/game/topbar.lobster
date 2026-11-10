// ------------------------------------------------------------------ the top bar (src/view/top_bar.gd, wonder_clock.gd)
// A beam in the look's frame at the top left: your stock of each resource sunk in a plaque with its icon
// and, under it, how many of your workers are on it; your population against the cap (red when it's
// full); your race's name; the age badge (its icon, number and name, and while ageing up the next age, how
// far and a bar); idle workers (a click, or ".", goes to the next one); the tech tree; the match clock.
// Hovering a plaque says more (the workers by what they do). Under it, centred, the Wonder countdowns.
// Resources come from data, so a new one shows up by itself. The icons are assets/art/icons/*.svg as
// pngs at twice their size (icons/, as icons.gd rasterises them; rsvg-convert -z 2, again after an icon changes).
// Sizes are Godot's (UI px) times hud_s(), its HUD scale (ui_scale.gd), the same for the command panel and the minimap.
// Imported by game.lobster after the panel (the tech tree page, go_to, team_col).

// The HUD's scale: the player's size (hud_size, game/audio.lobster: Ctrl/Cmd + and - in a match) in this window.
def hud_s() -> float: return hud_scale(hud_size, float(gl.window_size()))
let TB_FULL = float4 { 1.0, 0.54, 0.44, 1.0 }   // #ff8a70: the pop at its cap
let TB_WORK = float4 { 0.85, 0.78, 0.63, 1.0 }  // #d8c8a0: the worker counts
let TB_IDLE = float4 { 1.0, 0.69, 0.44, 1.0 }   // #ffb070: idle workers waiting
let TB_GOLD = float4 { 0.96, 0.84, 0.48, 1.0 }  // #f6d77a: ageing up
let TB_DISPLAY = "../assets/fonts/display.ttf"  // the display font (headings), as theme.gd
let TB_BOLD = "data/fonts/Droid_Sans/DroidSans-Bold.ttf"
let TB_TEXT = "data/fonts/Droid_Sans/DroidSans.ttf"  // (game.lobster's font, put back after)

let tb_icons = dictionary<string, resource<texture>>(64)
var tb_rect = float4_0  // where the bar is (x, y, w, h): clicks there aren't the world's
var tb_tip = ""

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
            if t.font == 3:  // a caption (theme.gd's caps_font): a letter at a time, spaced
                for(ui_caps_offsets(t.s, t.size)) x, i:
                    text_label(float2 { t.at.x + x, t.at.y }, t.s.substring(i, 1), t.size, t.col, face, edge, float4 { 0.0, 0.0, 0.0, 0.9 })
            else: text_label(t.at, t.s, t.size, t.col, face, edge, float4 { 0.0, 0.0, 0.0, 0.9 })
    tb_texts = []

// A plaque: a sunk well with a thin frame (theme.gd's well_box: the frame at 0.7, the face at 0.38).
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

// A frame of the look (theme.gd's frame_box at a weight in UI px): the frame's metal round a face, lit from
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

// A button of the look (theme.gd's button_box: a 3 px frame, the button's face; hover lighter with the
// accent's rim, pressed sunk, disabled greyed; accent: a gold rim). True on the frame it's clicked.
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

// Your workers on each resource, by what they do (sim_debug's _gatherers): per resource, [verb, count] pairs.
let TB_VERBS = [ [ "field", "farming" ], [ "paddy", "farming" ], [ "carcass", "hunting" ], [ "bugbush", "foraging" ], [ "reeds", "chopping" ], [ "stone", "mining" ], [ "gold", "mining" ] ]

def tb_gatherers() -> [[string]], [[int]]:
    let verbs = map(num_resources): []::string
    let counts = map(num_resources): []::int
    def add(r:int, verb:string):
        var k = -1
        for(verbs[r]) v, n:
            if v == verb: k = n
        if k >= 0: counts[r][k]++
        else:
            verbs[r].push(verb)
            counts[r].push(1)
    for(u_id.length) i:
        if u_owner[i] == ME and t_worker[u_kind[i]]:
            if (u_task[i] == GATHER or u_task[i] == T_RETURN) and u_carry_kind[i] > 0:
                let cell = if u_home[i] >= 0: u_home[i] else: u_target[i]
                var verb = "gathering"
                if (u_task[i] == GATHER or u_home[i] >= 0) and cell >= 0 and cell < terrain.length:
                    let tn = tr_names[terrain[cell]]
                    for(TB_VERBS) v:
                        if v[0] == tn: verb = v[1]
                add(u_carry_kind[i] - 1, verb)
            elif u_foe[i] != 0:
                let j = index_of(u_foe[i])
                let food = resource_index("food")
                if j >= 0 and u_owner[j] == gaia and food >= 0: add(food, "hunting")
    return verbs, counts

def tb_idle() -> [int]:
    return filter(u_id.length) i: u_owner[i] == ME and t_worker[u_kind[i]] and u_task[i] == T_NONE and u_moving[i] == 0

def tb_next_idle():
    let idle = tb_idle()
    if idle.length:
        let after = if selected.length: (filter(idle) i: u_id[i] > selected[0]) else: []
        go_to(if after.length: after[0] else: idle[0])

def tb_age_name(age:int) -> string:
    for(su_ages) a:
        if gint(a, "age", 0) == age: return gstr(a, "name", "Age {age}")
    return "Age {age}"

def tb_cap(s:string) -> string: return if s.length: s.substring(0, 1).uppercase() + s.substring(1, s.length - 1) else: s

// The bar (draw_hud draws it; clicks on it don't reach the world: panel_click).
def draw_topbar(speed:float, paused:bool):
    // The texts first, then the row laid out to fit the window (game/topbar_fit: the name cut, or the scale, if not).
    let pop_txt = "{pop[ME]}/{pop_cap[ME]}"
    // The age: under way wherever it's queued (0 while it waits its turn).
    var next = ""
    var frac = 0.0
    for(b_id.length) b:
        if b_owner[b] == ME and contains(b_queue[b], AGE_UP_ENTRY) and next_age(ME) >= 0:
            next = tb_age_name(ages_list[next_age(ME)].age)
            frac = if head_tech(b) == AGE_UP_ENTRY: float(b_train[b]) / float(head_ticks(b)) else: 0.0
    let age_txt = if next == "": tb_age_name(ages[ME]) else: "{tb_age_name(ages[ME])}  ->  {next}  {int(frac * 100.0)}%"
    let secs = tick / 20
    let clock_txt = "{secs / 60}:{if secs % 60 < 10: "0" else: ""}{secs % 60}"
    let pace = if paused: "Paused" elif speed != 1.0: "x{speed}" else: ""
    let stocks = map(num_resources) r: string(stock[r][ME])
    // (the name as typed: the display face sets the rest as small capitals, as Godot's)
    let texts = TbTexts { stocks, pop_txt, rstr(su_races[ME], "name"), string(ages[ME]), age_txt, clock_txt, pace }
    let lay = tb_layout(texts, float(gl.window_size().x), hud_s())
    let s = lay.s
    let pad = float2 { 16.0, 9.0 } * s
    let at = float2 { 10.0, 8.0 } * s
    let ph = 48.0 * s  // a plaque's height (a 20 px number over a worker line)
    let sep = 10.0 * s
    let light = ui_look.text
    tb_tip = ""
    let rows = tb_rows(s, next != "")
    let res_w = lay.res_w
    let pop_w = lay.pop_w
    let title = lay.title
    let title_w = lay.title_w
    let age_w = lay.age_w
    let idle = tb_idle()
    let idle_w = lay.idle_w
    let tree_w = lay.tree_w
    let clock_w = lay.clock_w
    let pace_w = lay.pace_w
    let w = lay.w
    let h = ph + pad.y * 2.0
    tb_rect = float4 { at.x, at.y, w, h }
    // The beam: the frame's metal, studs on the corners (theme.gd's Bar: frame_box at weight 6).
    hud_box(at, float2 { w, h }, 6.0, ui_look.face, true, 8.0)
    var x = at.x + pad.x
    let y = at.y + pad.y
    let verbs, counts = tb_gatherers()
    let icons = []::string
    let icon_at = []::float4  // x, y, side, alpha
    def icon(name:string, p:float2, side:float, alpha:float):
        icons.push(name)
        icon_at.push(float4 { p.x, p.y, side, alpha })
    // Each resource: its icon, the stock, a small worker and how many work it.
    for(num_resources) r:
        tb_plaque(float2 { x, y }, float2 { res_w[r], ph })
        icon("res_" + resource_names[r], float2 { x + 8.0 * s, y + (ph - 28.0 * s) / 2.0 }, 28.0 * s, 1.0)
        let nx = x + 42.0 * s
        tb_text(float2 { nx, y + rows.stock }, string(stock[r][ME]), int(20.0 * s), light, 1)
        var total = 0
        for(counts[r]) c: total += c
        let a = if total > 0: 1.0 else: 0.55
        icon("res_pop", float2 { nx, y + rows.work_icon }, 14.0 * s, 0.85 * a)
        tb_text(float2 { nx + 17.0 * s, y + rows.work }, string(total), int(15.0 * s), TB_WORK * float4 { 1.0, 1.0, 1.0, a }, 1)
        if tb_over(float2 { x, y }, float2 { res_w[r], ph }):
            let parts = map(verbs[r]) v, k: "{counts[r][k]} {v}"
            tb_tip = "{tb_cap(resource_names[r])}: " + (if total > 0: concat_string(parts, ", ") else: "nobody on it")
        x += res_w[r] + sep
    // Population over room.
    tb_plaque(float2 { x, y }, float2 { pop_w, ph })
    icon("res_pop", float2 { x + 8.0 * s, y + (ph - 28.0 * s) / 2.0 }, 28.0 * s, 1.0)
    tb_text(float2 { x + 42.0 * s, y + rows.pop }, pop_txt, int(20.0 * s), if pop[ME] >= pop_cap[ME]: TB_FULL else: light, 1)
    if tb_over(float2 { x, y }, float2 { pop_w, ph }): tb_tip = "Population / room (build houses for more)"
    x += pop_w + sep + 8.0 * s + sep
    // The race's name (cut, or gone, where the window has no room for it).
    if title != "":
        tb_text(float2 { x, y + (ph - 22.0 * s) / 2.0 - 3.0 * s }, title, int(22.0 * s), ui_look.title, 2)
        x += title_w + sep
    // The age badge.
    tb_plaque(float2 { x, y }, float2 { age_w, ph })
    let line_y = y + rows.age_icon
    icon("age_up", float2 { x + 8.0 * s, line_y }, 26.0 * s, 1.0)
    let num_x = x + 40.0 * s
    tb_text(float2 { num_x, y + rows.age_num }, string(ages[ME]), int(24.0 * s), ui_look.title, 2)
    tb_text(float2 { num_x + tb_text_w(string(ages[ME]), int(24.0 * s), 2) + 6.0 * s, y + rows.age_txt }, age_txt, int(17.0 * s), if next != "": TB_GOLD else: light, 1)
    if next != "":  // the age-up's progress: a slim bar under the line
        let bx = x + 8.0 * s
        let bw = age_w - 16.0 * s
        let by = y + rows.age_bar
        ui_fill(float2 { bx, by }, float2 { bw, 5.0 * s }, float4 { 0.0, 0.0, 0.0, 0.6 })
        ui_fill(float2 { bx, by }, float2 { bw * frac, 5.0 * s }, ui_look.accent)
        ui_fill(float2 { bx, by }, float2 { bw * frac, 1.5 * s }, float4 { 1.0, 1.0, 1.0, 0.35 })
        ui_outline(float2 { bx, by }, float2 { bw, 5.0 * s }, 1.0, float4 { 0.0, 0.0, 0.0, 0.7 })
    if tb_over(float2 { x, y }, float2 { age_w, ph }): tb_tip = if next != "": "Ageing up to the {next}" else: "Your age: the {tb_age_name(ages[ME])}"
    x += age_w + sep
    // Idle workers: how many; a click (or ".") goes to the next one.
    let bh = 40.0 * s
    let by = y + (ph - bh) / 2.0
    if hud_button(float2 { x, by }, float2 { idle_w, bh }, false, true) or (gl.button(".") == 1 and not typing_text and not tree_open): tb_next_idle()
    let ia = if idle.length: 1.0 else: 0.5
    icon("idle", float2 { x + 8.0 * s, by + 4.0 * s }, bh - 8.0 * s, ia)
    tb_text(float2 { x + 46.0 * s, by + (bh - 18.0 * s) / 2.0 - 2.0 * s }, string(idle.length), int(18.0 * s),
            if idle.length: TB_IDLE else: float4 { 0.94, 0.89, 0.78, 0.5 }, 1)
    if tb_over(float2 { x, by }, float2 { idle_w, bh }): tb_tip = "Idle workers: click (or press .) to go to the next one"
    x += idle_w + sep
    // The tech tree page.
    if hud_button(float2 { x, by }, float2 { tree_w, bh }, false, true):
        open_tree(ME)
    icon("research", float2 { x + 12.0 * s, by + (bh - 22.0 * s) / 2.0 }, 22.0 * s, 1.0)
    tb_text(float2 { x + 40.0 * s, by + (bh - 17.0 * s) / 2.0 - 2.0 * s }, "Tech tree", int(17.0 * s), light, 1)
    if tb_over(float2 { x, by }, float2 { tree_w, bh }): tb_tip = "Your race\'s tech tree and bonuses (F1)"
    x += tree_w + sep
    // The clock, and the game's pace when it isn't the usual.
    tb_plaque(float2 { x, y }, float2 { clock_w, ph })
    tb_text(float2 { x + (clock_w - tb_text_w(clock_txt, int(18.0 * s), 1)) / 2.0, y + rows.clock }, clock_txt, int(18.0 * s), light, 1)
    x += clock_w + sep
    if pace != "":
        tb_plaque(float2 { x, y }, float2 { pace_w, ph })
        tb_text(float2 { x + 8.0 * s, y + rows.pace }, pace, int(16.0 * s), TB_GOLD, 1)
        if tb_over(float2 { x, y }, float2 { pace_w, ph }): tb_tip = if paused: "Paused: space to go on" else: "Game speed: + and - to change it"
    // A hover's card under the bar.
    if tb_tip != "":
        let fs = int(15.0 * s)
        let cw = tb_text_w(tb_tip, fs, 0) + 24.0 * s
        let m = mouse_px()
        let cat = float2 { clamp(m.x - 20.0 * s, 4.0, float(gl.window_size().x) - cw - 4.0), at.y + h + 6.0 * s }
        hud_box(cat, float2 { cw, 34.0 * s }, 3.0, ui_look.face * float4 { 1.08, 1.08, 1.08, 1.0 }, false, 4.0)
        tb_text(cat + float2 { 12.0 * s, (34.0 * s - float(fs)) / 2.0 - 2.0 * s }, tb_tip, fs, float4 { 0.94, 0.89, 0.78, 1.0 }, 0)
    let hint_h = tb_hints(at.y + h + 18.0 * s)
    // The icons over the shapes, then the text.
    for(icons) name, k:
        let ia2 = icon_at[k]
        tb_icon(name, float2 { ia2.x, ia2.y }, ia2.z, ia2.w)
    draw_wonder_clock(at.y + h + hint_h + (if tb_tip != "": 48.0 * s else: 40.0 * s))
    tb_flush()

// The opening tips against the AI (sim_debug.gd's hints): three, one at a time, centred under the bar, each gone once
// it's done (a worker trained, one gathering, a house begun or four minutes gone). Not in a network match, a watched one
// or one loaded from a save. Returns the room it took.
let TB_HINTS = [ "Click your Town Center, then press Q (or its button) to train a worker.",
                 "Select a worker and right-click a bush, reeds or stone to gather.",
                 "Build a House (select a worker, press H) before your population fills up: every unit needs room." ]
let TB_PAD_HINTS = [ "D-pad up: your Town Center. Tap A on it for its commands, point at the worker, A to train.",
                     "D-pad down: an idle worker. Aim at a bush, reeds or stone and press X to gather.",
                     "Build a House (tap A on a selected worker, Build: Civilian, House, A to place) before your population fills up." ]
var tb_hint_step = -1  // the tip showing; -1 not begun, 3 done or none
var tb_hint_units = 0  // your units when they began
var tb_hint_tick = 0   // (a tick lower than the last seen: a new match, the tips again)

def tb_hints(y:float) -> float:
    if tick < tb_hint_tick: tb_hint_step = -1
    tb_hint_tick = tick
    if tb_hint_step < 0:
        tb_hint_step = if in_net_match or watch or tick > 20: 3 else: 0
        tb_hint_units = (filter(u_owner) o: o == ME).length
    if tb_hint_step >= 3 or winner >= 0: return 0.0
    var done = false
    if tb_hint_step == 0: done = (filter(u_owner) o: o == ME).length > tb_hint_units
    elif tb_hint_step == 1:
        for(u_owner) o, i: done = done or (o == ME and u_task[i] == GATHER)
    else:
        done = tick > 20 * 240
        for(b_owner) o, b: done = done or (o == ME and has_role(b_kind[b], ROLE_HOUSING) and not has_role(b_kind[b], ROLE_HUB))
    if done:
        tb_hint_step++
        play_sound("ui_tip", -6.0)
    if tb_hint_step >= 3: return 0.0
    let s = hud_s()
    let line = "Tip {tb_hint_step + 1} of 3:  " + (if pad_on: TB_PAD_HINTS else: TB_HINTS)[tb_hint_step]
    let fs = int(18.0 * s)
    let cw = tb_text_w(line, fs, 0) + 28.0 * s
    let ch = 40.0 * s
    let at = float2 { (float(gl.window_size().x) - cw) / 2.0, y }
    hud_box(at, float2 { cw, ch }, 3.0, ui_look.face * float4 { 1.08, 1.08, 1.08, 1.0 }, false, 4.0)
    ui_outline(at + float2_1 * 3.0 * s, float2 { cw, ch } - float2_1 * 6.0 * s, max(1.0, s), float4 { ui_look.accent.x, ui_look.accent.y, ui_look.accent.z, 0.6 })
    tb_text(at + float2 { 14.0 * s, (ch - float(fs)) / 2.0 - 2.0 * s }, line, fs, float4 { 0.96, 0.92, 0.82, 1.0 }, 0)
    return ch + 8.0 * s

// The Wonder countdowns, centred under the bar, the same for every player: one line per standing finished
// Wonder ("<race>'s Wonder: 7:32") in its owner's team colour, lightened (wonder_clock.gd).
def draw_wonder_clock(top:float):
    if wonder_hold <= 0 or winner >= 0: return
    let s = hud_s()
    let fs = int(24.0 * s)
    for(wonder_ids.length) k:
        let left = (max(0, wonder_hold - (tick - wonder_since[k])) + 19) / 20
        let owner = wonder_owners[k]
        let name = rstr(su_races[owner], "name")
        let line = "{name}{if name.length and name[name.length - 1] == 's': "\'" else: "\'s"} Wonder: {left / 60}:{if left % 60 < 10: "0" else: ""}{left % 60}"
        let tc = team_col(owner)
        let col = float4 { tc.x + (1.0 - tc.x) * 0.25, tc.y + (1.0 - tc.y) * 0.25, tc.z + (1.0 - tc.z) * 0.25, 1.0 }
        tb_texts.push(TbText { float2 { (float(gl.window_size().x) - tb_text_w(line, fs, 1)) / 2.0, top + float(k) * float(fs) * 1.3 }, line, fs, col, 1, true })

def in_topbar(m:float2) -> bool: return m.x >= tb_rect.x and m.y >= tb_rect.y and m.x <= tb_rect.x + tb_rect.z and m.y <= tb_rect.y + tb_rect.w

// The space under the bar (the control groups' row goes there).
def topbar_bottom() -> float: return tb_rect.y + tb_rect.w
