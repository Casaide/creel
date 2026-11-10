// ------------------------------------------------------------------ the tech tree page (scenes/tech_tree.gd)
// One race's whole tree on one screen, in its culture's look. A title bar (the race, a key to the frames, Close);
// the race panel on the left (its name, creature and culture, the army idling on a strip of grass, its bonuses,
// own research, lacks and how it moves, a count of what's in the game); the tree on the right: the ages as rows
// down a rail (each one's name and what it needs), a column per building (its picture on top, then its units'
// portraits and its research's icons in the rows of their ages, joined by lines), what the race lacks crossed out,
// planned things as blank dashed frames, the race's own research marked in gold. Hover (or tap, or the d-pad) for
// a card: the cost, what it is, what it does. The tree scrolls sideways (the wheel, a drag, the arrows, the left
// stick, its bar); the race panel by the wheel over it or the right stick. In a match it shows the player's
// progress (built and researched lit gold, under way with a bar, not yet dimmed); F1 or the top bar opens it there,
// the banner's Tech tree in the lobby. Esc, B, Start or Close shuts it.
// Drawn in a few draws: the fills and lines batched, every picture (building bakes, portraits, research icons)
// painted once into one page and drawn from it as one mesh, the text through the text cache. The model is
// game/techtree.lobster.

let TT_LANE = 80.0     // one lane of nodes under a building (design px)
let TT_NODE = 50.0     // a unit or research frame
let TT_BNODE = 58.0    // a building frame
let TT_NAME_H = 28.0   // two lines of a node's name
let TT_BNAME_H = 18.0  // one line of a building's name
let TT_BUS = 14.0      // the gap under a building's name where its line branches to its lanes
let TT_COL_PAD = 6.0
let TT_COL_GAP = 12.0
let TT_ROW_PAD = 8.0
let TT_ROW_H = TT_ROW_PAD + TT_BNODE + TT_BNAME_H + TT_BUS + TT_NODE + TT_NAME_H + TT_ROW_PAD
let TT_RAIL = 150.0  // the age rail on the left of the tree
let TT_SIDE = 300.0  // the race panel
let TT_STAGE_H = 118.0
let TT_PAGE = 2048  // the pictures' page (px)

let TT_PANEL = float4 { 0.165, 0.137, 0.106, 1.0 }   // #2a231b
let TT_EDGE = float4 { 0.416, 0.353, 0.251, 1.0 }    // #6a5a40
let TT_BRONZE = float4 { 0.627, 0.533, 0.345, 1.0 }  // #a08858
let TT_GOLD = float4 { 0.949, 0.788, 0.298, 1.0 }    // #f2c94c
let TT_TEXT = float4 { 0.937, 0.894, 0.784, 1.0 }    // #efe4c8
let TT_DIM = float4 { 0.722, 0.678, 0.58, 1.0 }      // #b8ad94
let TT_GREY = float4 { 0.478, 0.443, 0.4, 1.0 }      // #7a7166
let TT_NEED = float4 { 0.91, 0.541, 0.439, 1.0 }     // #e88a70
let TT_GOOD = float4 { 0.659, 0.847, 0.502, 1.0 }    // #a8d880
let TT_GRASS = float4 { 0.306, 0.431, 0.165, 1.0 }   // #4e6e2a

// A node's state: in a match from the player's progress; in the lobby, open, planned or (lacked) locked.
let TT_OPEN = 0
let TT_DONE = 1
let TT_PROGRESS = 2
let TT_LOCKED = 3
let TT_PLANNED = 4

// A line of text placed once for a size of window.
class TtLine:
    at:float2  // design px, from its block's top left
    s:string
    size:float
    col:float4
    font:int

var tt_race = jobj()
var tt_rules = jobj()
var tt_owner = 0  // whose colours (the lobby's side, the match's player)
var tt_match = false
var tt_k = 0.0                  // the scale the layout was made for
var tt_names = [ []::string ]   // per node: its name in lines
var tt_side_lines = []::TtLine  // the race panel, below its stage
var tt_side_top = []::TtLine    // the race panel, above its stage
var tt_side_h = 0.0             // the race panel's content height (design px)
var tt_stage_y = 0.0
var tt_rules_y = []::float  // the race panel's rules (design px)
var tt_rail = []::TtLine
var tt_col_x = []::float2       // per column: its x and width (design px)
var tt_canvas = float2_0        // the tree's size (design px)
var tt_lanes = [ [ []::int ] ]  // per column, per lane: its nodes top to bottom
var tt_joined = []::int         // per node: the node a line joins it to from above (-1: none)
var tt_state = []::int          // per node
var tt_prog = []::float
var tt_state_t = -1.0
var tt_age_bar = -1.0  // an age-up under way: how far (a match)
var tt_sy = 0.0        // the tree scrolled down (screen px; tree_scroll is across)
var tt_ly = 0.0        // the race panel scrolled down
var tt_drag = -1       // 0 the tree, 1 the bar, 2 the race panel; -1 none
var tt_drag_at = float2_0
var tt_focus = -1  // the node the d-pad is on
var tt_pad = false
var tt_res = []::JV  // data/resources.json: names and colours
var tt_arch = ""
var tt_arch_age = 1
var tt_want_buildings = false
let tt_widths = dictionary<string, float>(512)

// The pictures' page: each node's picture painted once at its size on the screen, drawn from here as one mesh.
var tt_page_tex:resource<texture>? = nil
var tt_page_k = 0.0
var tt_shelf = int3_0                         // x, y, height of the shelf being filled
let tt_cells = dictionary<string, int4>(256)  // node key -> x, y, side on the page
let tt_keys = dictionary<string, int>(256)    // a portrait's recipe and owner -> its key in the panel's caches
var tt_next_key = 500000

def tt_measure(s:string, size:int, font:int) -> float:
    let key = "{font}|{size}|{s}"
    let have = tt_widths.get(key, -1.0)
    if have >= 0.0: return have
    let w = ui_text_wf(s, size, font)
    tt_widths.set(key, w)
    return w

// Lines no wider than w (whole words); past `most` lines the last ends in "...".
def tt_wrap(s:string, size:int, font:int, w:float, most:int) -> [string]:
    let out = []::string
    for(tokenize(s, "\n", "")) para:
        var line = ""
        for(tokenize(para, " ", "")) word:
            let next = if line == "": word else: line + " " + word
            if line != "" and tt_measure(next, size, font) > w:
                out.push(line)
                line = word
            else: line = next
        out.push(line)
    if out.length > most:
        var last = out[most - 1]
        while last.length > 1 and tt_measure(last + "...", size, font) > w: last = last.substring(0, last.length - 1)
        out[most - 1] = last + "..."
        return out.slice(0, most)
    return out

def tt_roman(n:int) -> string: return if n < 7: [ "", "I", "II", "III", "IV", "V", "VI" ][n] else: string(n)

def tt_bname(t:TTree, id:string) -> string:
    for(t.columns) c:
        if c.id == id: return c.name
    return id

// ---- opening it

// The page for a player's race in the match.
def open_tree(p:int):
    tt_open(su_races[p], su_sides[p], su_rules, p, true)

// Any race's page (the lobby's banners: side i's race in its colours).
def open_tree_of(race:JV, ident:JV, rules:JV, side:int): tt_open(race, ident, rules, side, false)

def tt_open(race:JV, ident:JV, rules:JV, owner:int, in_match:bool):
    tree_page = build_tree_of(race, ident, rules)
    tree_words = race_words_of(race, ident, rules)
    tree_title = rstr(race, "name")
    tree_lobby = not in_match
    tree_open = true
    tree_scroll = 0.0
    tt_race = race
    tt_rules = rules
    tt_owner = owner
    tt_match = in_match
    tt_k = 0.0
    tt_sy = 0.0
    tt_ly = 0.0
    tt_drag = -1
    tt_focus = -1
    tt_state_t = -1.0
    tt_page_k = 0.0  // (the pictures painted again: another race, another age)
    tt_arch = architecture(race)
    tt_arch_age = if in_match: ages[ME] else: 1
    tt_want_buildings = not in_match  // (the lobby has no buildings baked yet: the shipped bakes are read once it's open)
    if not tt_res.length: tt_res = glist(lib_data("resources.json"), "resources")

// ---- the layout (design px), made again when the window's scale changes

// Design px to the screen: fits the page's look (2016 x 1222) to the window, never under a plain 1:1 on a
// smaller screen (the Deck's 1280 x 800).
def tt_scale() -> float:
    let ws = float(gl.window_size())
    return max(min(ws.x / 2016.0, ws.y / 1222.0), min(1.0, min(ws.x / 1500.0, ws.y / 850.0)))

def tt_layout(t:TTree, words:RaceWords, k:float):
    tt_k = k
    tt_widths.clear()
    def fs(n:float) -> int: return max(8, int(n * k + 0.5))
    // the tree: the columns, each node's name in lines
    tt_col_x = []
    var x = TT_COL_GAP * 0.5
    for(t.columns) c:
        let w = float(c.lanes) * TT_LANE + TT_COL_PAD * 2.0
        tt_col_x.push(float2 { x, w })
        x += w + TT_COL_GAP
    tt_canvas = float2 { x, float(t.ages.length) * TT_ROW_H }
    tt_lanes = map(t.columns) c, ci:
        let lanes = []::[int]
        for(c.lanes) lane:
            let ns = filter(t.nodes.length) i: t.nodes[i].col == ci and t.nodes[i].kind != "building" and t.nodes[i].lane == lane
            insertion_sort(ns) p, q: t.nodes[p].age < t.nodes[q].age
            if ns.length: lanes.push(ns)
        lanes
    tt_joined = map(t.nodes.length): -1
    for(t.joins) j: tt_joined[j.y] = j.x
    tt_names = map(t.nodes) n:
        if n.kind == "building": tt_wrap(n.name, fs(14.0), 0, max(tt_col_x[n.col].y, TT_LANE) * k, 1)
        else: tt_wrap(n.name, fs(12.0), 0, TT_LANE * k - 4.0 * k, 2)
    // the rail: each age's number, name and what it needs
    tt_rail = []
    for(t.ages) a, i:
        let y = float(i) * TT_ROW_H
        tt_rail.push(TtLine { float2 { 14.0, y + 10.0 }, tt_roman(a.age), 30.0, if a.planned: TT_GREY else: TT_GOLD, 2 })
        for(tt_wrap(a.name, fs(17.0), 0, (TT_RAIL - 24.0) * k, 2)) l, j: tt_rail.push(TtLine { float2 { 14.0, y + 52.0 + 20.0 * float(j) }, l, 17.0, if a.planned: TT_GREY else: TT_TEXT, 0 })
        for(tt_wrap(a.needs, fs(12.0), 0, (TT_RAIL - 24.0) * k, 5)) l, j: tt_rail.push(TtLine { float2 { 14.0, y + 76.0 + 15.0 * float(j) }, l, 12.0, if a.planned: TT_GREY else: TT_DIM, 0 })
    // the race panel: name, creature and culture, the stage, the sections, the count
    let w = TT_SIDE - 40.0
    let lk = ui_look
    var y = 10.0
    tt_side_top = []
    for(tt_wrap(rstr(tt_race, "name"), fs(32.0), 2, w * k, 3)) l:
        tt_side_top.push(TtLine { float2 { 0.0, y }, l, 32.0, lk.title, 2 })
        y += 40.0
    y += 4.0
    let cr = creature(rstr(tt_race, "creature"))
    for(tt_wrap("{gstr(cr, "plural", capitalize(rstr(tt_race, "creature")))}  ·  {capitalize(rstr(tt_race, "family"))} culture", fs(17.0), 0, w * k, 2)) l:
        tt_side_top.push(TtLine { float2 { 0.0, y }, l, 17.0, TT_DIM, 0 })
        y += 22.0
    y += 8.0
    tt_stage_y = y
    y += TT_STAGE_H + 8.0
    tt_side_lines = []
    tt_rules_y = []
    def section(title:string, items:[string], empty:string):
        y += 12.0
        tt_side_lines.push(TtLine { float2 { 0.0, y }, title.uppercase(), 14.0, lk.title * float4 { 0.85, 0.85, 0.85, 1.0 }, 1 })
        y += 24.0
        tt_rules_y.push(y)
        y += 14.0
        if not items.length and empty != "":
            tt_side_lines.push(TtLine { float2 { 0.0, y }, empty, 17.0, TT_GREY, 0 })
            y += 24.0
        for(items) item:
            for(tt_wrap("•  " + item, fs(17.0), 0, w * k, 8)) l:
                tt_side_lines.push(TtLine { float2 { 0.0, y }, l, 17.0, TT_TEXT, 0 })
                y += 23.0
            y += 6.0
    section("Bonuses", words.bonuses, "Nothing beyond the usual")
    section("Own research", words.own, "None")
    section("Lacks", words.lacks, "Nothing")
    section("Moves", words.moves, "")
    let planned = (filter(t.nodes) n: n.planned).length
    y += 14.0
    for(tt_wrap("{t.nodes.length - planned} on this tree are in the game; {planned} more are planned (the blank frames).", fs(15.0), 0, w * k, 4)) l:
        tt_side_lines.push(TtLine { float2 { 0.0, y }, l, 15.0, TT_GREY, 0 })
        y += 21.0
    tt_side_h = y + 10.0

// Where a node's box is on the tree (design px): its top left and size.
def tt_box(n:TNode) -> float2, float2:
    let c = tt_col_x[n.col]
    let row = float(n.age - 1) * TT_ROW_H
    if n.kind == "building":
        let w = max(c.y, TT_LANE)
        return float2 { c.x + (c.y - w) * 0.5, row + TT_ROW_PAD }, float2 { w, TT_BNODE + TT_BNAME_H }
    return float2 { c.x + TT_COL_PAD + float(max(0, n.lane)) * TT_LANE, row + TT_ROW_PAD + TT_BNODE + TT_BNAME_H + TT_BUS }, float2 { TT_LANE, TT_NODE + TT_NAME_H }

def tt_box_at(n:TNode) -> float2:
    let c = tt_col_x[n.col]
    let row = float(n.age - 1) * TT_ROW_H
    if n.kind == "building": return float2 { c.x + (c.y - max(c.y, TT_LANE)) * 0.5, row + TT_ROW_PAD }
    return float2 { c.x + TT_COL_PAD + float(max(0, n.lane)) * TT_LANE, row + TT_ROW_PAD + TT_BNODE + TT_BNAME_H + TT_BUS }

def tt_frame_side(n:TNode) -> float: return if n.kind == "building": TT_BNODE else: TT_NODE

// ---- the player's progress (a match)

def tt_research_index(id:string) -> int:
    for(research) r, i:
        if r.id == id: return i
    return -1

def tt_btype(id:string) -> int:
    for(bt_name) nm, i:
        if nm == id: return i
    return -1

// Research r for the player: done, under way (how far), or neither.
def tt_research_state(r:int) -> int, float:
    if researched[ME][r] == 1: return TT_DONE, 0.0
    let e = entry_of(r)
    for(b_id.length) b:
        if b_owner[b] == ME and contains(b_queue[b], e):
            return TT_PROGRESS, if head_tech(b) == r: float(b_train[b]) / float(head_ticks(b)) else: 0.0
    return -1, 0.0

def tt_node_state(n:TNode) -> int, float:
    if n.planned: return TT_PLANNED, 0.0
    if n.lacks: return TT_LOCKED, 0.0
    if not tt_match: return TT_OPEN, 0.0
    let age = ages[ME]
    switch n.kind:
        case "building":
            let k = tt_btype(n.id)
            var best = -1.0
            for(b_id.length) b:
                if b_owner[b] == ME and b_kind[b] == k:
                    if b_done[b] == 1: return TT_DONE, 0.0
                    best = max(best, float(b_progress[b]) / float(max(1, bt_build_ticks[k])))
            if best >= 0.0: return TT_PROGRESS, best
        case "research":
            let r = tt_research_index(n.id)
            if r >= 0:
                let st, f = tt_research_state(r)
                if st >= 0: return st, f
        default:
            if n.first or n.id == "worker":  // a line's first step: the age and a building to train it; workers follow the age
                let k = tt_btype(n.building)
                if age >= n.age and (n.id == "worker" or (k >= 0 and has_building(ME, k))): return TT_DONE, 0.0
            else:
                let r = tt_research_index("line.{n.id}.{n.age}")
                if r >= 0:
                    let st, f = tt_research_state(r)
                    if st >= 0: return st, f
    if age >= n.age: return TT_OPEN, 0.0
    return TT_LOCKED, 0.0

def tt_refresh(t:TTree):
    tt_state = []
    tt_prog = []
    for(t.nodes) n:
        let st, f = tt_node_state(n)
        tt_state.push(st)
        tt_prog.push(f)
    tt_age_bar = -1.0
    if tt_match:
        for(b_id.length) b:
            if b_owner[b] == ME and contains(b_queue[b], AGE_UP_ENTRY):
                tt_age_bar = if head_tech(b) == AGE_UP_ENTRY: float(b_train[b]) / float(head_ticks(b)) else: 0.0

// ---- the pictures

// A portrait's key in the panel's caches (portraits, busts): one per recipe and colours.
def tt_key(recipe:JV) -> int:
    let s = "{tt_owner}|{stringify(recipe)}"
    let have = tt_keys.get(s, -1)
    if have >= 0: return have
    tt_next_key++
    tt_keys.set(s, tt_next_key)
    return tt_next_key

// The figure for a recipe: true once its look is baked (asked for first until then, baked between frames).
def tt_figure_ready(key:int, recipe:JV) -> bool: return vx_figure(recipe) >= 0

// A building's bake for the race's architecture (its age's look in a match).
def tt_building_frame(id:string) -> int:
    let lk = looks.get(building_key(tt_arch, id, tt_arch_age, 0))
    return if lk: frame_index(lk.body) else: -1

class TtTodo:  // a picture to paint: its node, its side (px), its portrait's key
    n:TNode
    side:float
    key:int

// A place on the page for a picture `side` px square.
def tt_place(side:int) -> int2:
    if tt_shelf.x + side + 2 > TT_PAGE: tt_shelf = int3 { 0, tt_shelf.y + tt_shelf.z + 2, 0 }
    let at = int2 { tt_shelf.x, tt_shelf.y }
    tt_shelf = int3 { tt_shelf.x + side + 2, tt_shelf.y, max(tt_shelf.z, side) }
    return at

// The pictures not yet on the page painted onto it (a few portraits a frame: each is drawn and read back once).
// How many are still to come.
def tt_paint(t:TTree, k:float) -> int:
    if tt_page_k != k:
        if not tt_page_tex: tt_page_tex = gl.create_blank_texture(int3 { TT_PAGE, TT_PAGE, 0 }, texture_format_nomipmap | texture_format_nearest_mag | texture_format_nearest_min | texture_format_clamp)
        tt_cells.clear()
        tt_shelf = int3_0
        tt_page_k = k
        gl.switch_to_framebuffer(tt_page_tex)
        gl.clear(float4_0)
        gl.switch_to_framebuffer(nil)
        gl.ortho()
    let page = tt_page_tex
    if not page: return 0
    let todo = []::TtTodo
    var waiting = 0
    var busts_made = 0
    for(t.nodes) n:
        if not n.planned and tt_cells.get(n.key, int4 { 0, 0, 0, -1 }).w < 0:
            let inset = if n.kind == "unit": 3.0 else: 5.0
            let side = floor((tt_frame_side(n) - inset * 2.0) * k)
            if n.kind == "research": todo.push(TtTodo { n, side, -1 })
            elif n.kind == "building":
                if tt_building_frame(n.id) >= 0: todo.push(TtTodo { n, side, -1 })
                elif not tt_want_buildings: tt_cells.set(n.key, int4_0)  // (none baked: an empty frame)
                else: waiting++
            else:
                let r = n.recipe
                if r:
                    let key = tt_key(r)
                    if busts.get(key): todo.push(TtTodo { n, side, key })
                    elif busts_made < 4 and tt_figure_ready(key, r):
                        bust(key, r, tt_owner)  // (drawn into its own texture now, copied onto the page below)
                        busts_made++
                        todo.push(TtTodo { n, side, key })
                    else: waiting++
                else: tt_cells.set(n.key, int4_0)
    if todo.length:
        flush_sprites()
        gl.switch_to_framebuffer(page)
        gl.ortho()
        b_sheet = -1
        for(todo) d:
            let s = int(d.side)
            let at = tt_place(s)
            let fat = float(at)
            if d.n.kind == "research": tb_icon(d.n.icon, fat, d.side, 1.0)
            elif d.n.kind == "building":
                let f = tt_building_frame(d.n.id)
                let fr = frames[f]
                let sc = d.side / float(max(fr.w, fr.h))
                let tc = team_col(tt_owner)
                sprite_xf(f, [ sc, 0.0, 0.0, sc, fat.x + d.side / 2.0 - float(fr.w) / 2.0 * sc, fat.y + d.side / 2.0 - float(fr.h) / 2.0 * sc ], float4 { tc.x, tc.y, tc.z, 1.0 })
                flush_sprites()
            else: draw_bust(d.key, assert d.n.recipe, tt_owner, fat, d.side)
            tt_cells.set(d.n.key, int4 { at.x, at.y, s, 1 })
        flush_sprites()
        gl.switch_to_framebuffer(nil)
        gl.ortho()
    return waiting

// ---- drawing pieces

def tt_dash(a:float2, b:float2, w:float, col:float4, dash:float):
    let d = b - a
    let len = magnitude(d)
    if len <= 0.0: return
    let dir = d / len
    var s = 0.0
    while s < len:
        ui_line(a + dir * s, a + dir * min(len, s + dash), w, col)
        s += dash * 2.0

def tt_diamond(c:float2, r:float, col:float4):
    ui_batch_quad(c - float2 { 0.0, r }, c + float2 { r, 0.0 }, c + float2 { 0.0, r }, c - float2 { r, 0.0 }, col)

// A rule: a thin line in the look's metal with a diamond at its middle (theme.gd's Rule).
def tt_rule(x:float, y:float, w:float, k:float):
    let c = ui_look.metal
    ui_fill(float2 { x, y }, float2 { w, max(1.0, k) }, float4 { c.x, c.y, c.z, 0.7 })
    tt_diamond(float2 { x + w * 0.5, y + 0.5 * k }, 4.0 * k, c)

// A node's frame (a sunk slot with a metal rim, lit on top) in its state; planned: an empty dashed frame.
def tt_frame(f0:float2, side:float, st:int, hover:bool, k:float):
    let planned = st == TT_PLANNED
    var edge = ui_look.frame * float4 { 0.9, 0.9, 0.9, 1.0 }
    var fill = float4 { 0.102, 0.078, 0.055, 1.0 }  // #1a140e
    if st == TT_DONE:
        edge = TT_GOLD
        fill = float4 { 0.227, 0.18, 0.094, 1.0 }
        ui_fill(f0 - float2_1 * 3.0 * k, float2_1 * (side + 6.0 * k), float4 { 1.0, 0.8, 0.3, 0.16 })  // a soft glow
    elif st == TT_PROGRESS: edge = float4 { 0.847, 0.69, 0.314, 1.0 }
    elif st == TT_LOCKED: edge = float4 { 0.29, 0.25, 0.19, 1.0 }
    if hover and not planned: edge = edge + (float4_1 - edge) * float4 { 0.3, 0.3, 0.3, 0.0 }
    let sz = float2_1 * side
    if planned:
        ui_fill(f0, sz, float4 { 0.1, 0.09, 0.07, 0.6 })
        let c = float4 { TT_GREY.x, TT_GREY.y, TT_GREY.z, if hover: 0.9 else: 0.65 }
        let w = 1.5 * k
        let d = 4.0 * k
        tt_dash(f0, f0 + float2 { side, 0.0 }, w, c, d)
        tt_dash(f0 + float2 { side, 0.0 }, f0 + sz, w, c, d)
        tt_dash(f0 + sz, f0 + float2 { 0.0, side }, w, c, d)
        tt_dash(f0 + float2 { 0.0, side }, f0, w, c, d)
        return
    for(3) i: ui_fill(f0 + float2 { 0.0, (2.0 + float(i)) * k }, sz, float4 { 0.0, 0.0, 0.0, 0.15 })  // its shadow
    let bw = (if st == TT_DONE or st == TT_PROGRESS or hover: 2.0 else: 1.0) * k
    ui_fill(f0, sz, edge)
    ui_fill(f0 + float2 { bw, bw + k }, sz - float2 { bw * 2.0, bw * 2.0 + k }, fill)
    ui_fill(f0 + float2 { 3.0 * k, bw + k }, float2 { side - 6.0 * k, 2.0 * k }, float4 { 0.0, 0.0, 0.0, 0.5 })

def tt_line_col(built:bool, lit:bool) -> float4:
    if not built: return float4 { TT_GREY.x, TT_GREY.y, TT_GREY.z, 0.45 }
    return if lit: TT_GOLD else: float4 { TT_BRONZE.x, TT_BRONZE.y, TT_BRONZE.z, 0.85 }

// A swatch for the key: a small frame in a state (or the race's own mark).
def tt_swatch(at:float2, st:int, k:float):
    if st < 0:
        tt_diamond(at + float2_1 * 9.0 * k, 5.0 * k, TT_GOLD)
        return
    tt_frame(at, 18.0 * k, st, false, k)
    if st == TT_PROGRESS:
        ui_fill(at + float2 { 3.0 * k, 11.0 * k }, float2 { 12.0 * k, 4.0 * k }, float4 { 0.0, 0.0, 0.0, 0.7 })
        ui_fill(at + float2 { 3.0 * k, 11.0 * k }, float2 { 6.6 * k, 4.0 * k }, TT_GOLD)

def tt_scissor(at:float2, size:float2):
    ui_batch_flush()
    let f = float(gl.framebuffer_size()) / float(gl.window_size())
    gl.scissor(int2 { int(at.x * f.x), int(at.y * f.y) }, int2 { int(ceiling(size.x * f.x)), int(ceiling(size.y * f.y)) })

def tt_unscissor():
    ui_batch_flush()
    gl.scissor(int2_0, gl.framebuffer_size())

// ---- the hover card (theme.gd's tip_card)

def tt_cost_parts(c:JV?) -> [string], [float4]:
    let words = []::string
    let cols = []::float4
    if c:
        for(tt_res) r:
            let v = gint(c, gstr(r, "id", ""), 0)
            if v > 0:
                words.push("{v} {gstr(r, "name", "")}")
                let rc = hex4(gstr(r, "colour", "#ffffff"))
                cols.push(rc + (float4_1 - rc) * float4 { 0.3, 0.3, 0.3, 0.0 })
    return words, cols

def tt_card(t:TTree, n:TNode, st:int, prog:float, near:float2, k:float):
    let ws = float(gl.window_size())
    let planned = n.planned
    let rows = []::string
    let cols = []::float4
    def add(s:string, c:float4):
        if s != "":
            rows.push(s)
            cols.push(c)
    add(n.desc, TT_TEXT)
    if n.kind == "building":
        let trains = map(filter(t.nodes) m: m.col == n.col and m.kind == "unit" and m.first) m: m.name
        let res = map(filter(t.nodes) m: m.col == n.col and m.kind == "research") m: m.name
        if trains.length: add("Trains: " + concat_string(trains, ", "), TT_TEXT)
        if res.length: add("Research: " + concat_string(res, ", "), TT_TEXT)
        add("Age {n.age}" + (if n.hotkey != "" and not planned: "   Hotkey " + n.hotkey.uppercase() else: ""), TT_DIM)
    elif n.kind == "unit":
        add(n.stats, TT_TEXT)
        let where = tt_bname(t, n.building)
        if n.lacks: add("Not in this race\'s tree (see its notes)", TT_NEED)
        elif n.first:
            add("Trained at the {where} from age {n.age}", TT_DIM)
            if n.early_kit != "": add("Trains first in its age-{n.tier} kit ({n.early_kit}); the line upgrade here gives this one", TT_DIM)
        elif n.id == "worker": add("Workers take this kit on reaching age {n.age}", TT_DIM)
        else: add("Line upgrade at the {where} in age {n.age}", TT_DIM)
    else:
        add(n.effect, TT_GOOD)
        add("At the {tt_bname(t, n.building)}, age {n.age}", TT_DIM)
        if n.only.length:
            let who = concat_string(map(n.only) o: capitalize(o), ", ")
            if n.lacks: add("Only for {who}: not in this race\'s tree", TT_NEED)
            else: add("Only for {who}", TT_GOLD)
    if planned: add("Planned: not in the game yet", TT_GREY + float4 { 0.15, 0.15, 0.15, 0.0 })
    elif tt_match:
        if st == TT_DONE: add(if n.kind == "building": "Built" elif n.kind == "research": "Researched" else: "Yours", TT_GOLD)
        elif st == TT_PROGRESS: add("Under way: {int(prog * 100.0)}%", TT_GOLD)
        elif st == TT_LOCKED and not n.lacks: add("Needs age {n.age}", TT_NEED)
    let fs = int(15.0 * k + 0.5)
    let ts = int(17.0 * k + 0.5)
    let wmax = 380.0 * k
    let wrapped = []::string
    let wcols = []::float4
    for(rows) l, i:
        for(tt_wrap(l, fs, 0, wmax, 8)) wl:
            wrapped.push(wl)
            wcols.push(cols[i])
    let cost_w, cost_c = tt_cost_parts(if planned: nil else: n.costv)
    let sub = if n.kind == "unit" and n.line_name != "" and n.name != n.line_name: "{n.line_name} line" else: ""
    var w = tt_measure(n.name, ts, 1) + (if sub != "": 10.0 * k + tt_measure(sub, fs, 0) else: 0.0)
    for(wrapped) l: w = max(w, tt_measure(l, fs, 0))
    var cw = 0.0
    for(cost_w) c: cw += tt_measure(c, fs, 0) + 14.0 * k
    w = min(max(w, cw), wmax) + 22.0 * k
    let lh = 20.0 * k
    let h = 12.0 * k + 24.0 * k + (if cost_w.length: lh else: 0.0) + lh * float(wrapped.length) + 10.0 * k
    var at = near
    if at.x + w > ws.x - 8.0: at.x = max(8.0, ws.x - 8.0 - w)
    if at.y + h > ws.y - 8.0: at.y = max(8.0, near.y - h - 40.0 * k)
    // (a frame in the look's gold round a dark face, as the game's cards)
    ui_fill(at + float2 { 2.0, 3.0 } * k, float2 { w, h }, float4 { 0.0, 0.0, 0.0, 0.4 })
    ui_fill(at, float2 { w, h }, ui_look.accent * float4 { 0.85, 0.85, 0.85, 1.0 })
    ui_fill(at + float2_1 * 2.0 * k, float2 { w, h } - float2_1 * 4.0 * k, float4 { 0.12, 0.1, 0.075, 0.97 })
    var y = at.y + 10.0 * k
    let x = at.x + 11.0 * k
    ui_text_f(float2 { x, y }, n.name, ts, TT_TEXT, 1, 0.0)
    if sub != "": ui_text(float2 { x + tt_measure(n.name, ts, 1) + 10.0 * k, y + 2.0 * k }, sub, fs, TT_DIM)
    y += 26.0 * k
    if cost_w.length:
        var cx = x
        for(cost_w) c, i:
            ui_text(float2 { cx, y }, c, fs, cost_c[i])
            cx += tt_measure(c, fs, 0) + 14.0 * k
        y += lh
    for(wrapped) l, i:
        ui_text(float2 { x, y }, l, fs, wcols[i])
        y += lh

// ---- the page, a frame of it

// The page over everything; true while it's up.
def tree_tick() -> bool:
    if gl.button("f1") == 1 and not tree_lobby:
        if tree_open: tree_open = false
        else: open_tree(ME)
    if tree_open and (gl.button("escape") == 1 or gl.button("controller_b") == 1 or gl.button("controller_start") == 1 or gl.button("ac back") == 1): tree_open = false
    if not tree_open: return false
    let t = tree_page
    let words = tree_words
    if not t or not words: return false
    let ws = float(gl.window_size())
    let k = tt_scale()
    let was_look = ui_look
    ui_use(ui_look_of(rstr(tt_race, "family")))
    if tt_k != k: tt_layout(t, words, k)
    if tt_state_t < 0.0 or gl.time() - tt_state_t > 0.25:  // (the match goes on: what's built, researched, under way)
        tt_state_t = gl.time()
        tt_refresh(t)
    // the pictures: the lobby's buildings read from their bakes once, the portraits as their looks are baked
    if tt_want_buildings:
        tt_want_buildings = false
        let live = bake_live
        bake_live = false
        bake_buildings_for([ tt_arch ])
        bake_live = live
        gl.ortho()
    vx_bake_tick(0.012)  // (the portraits' voxel looks)
    let waiting = tt_paint(t, k)
    tree_waiting = waiting
    // where things are
    let lk = ui_look
    let m = mouse_px()
    let top = 12.0 * k
    let head_h = 46.0 * k
    let row_top = top + head_h + 26.0 * k
    let bottom = ws.y - 18.0 * k
    let side_at = float2 { 20.0 * k, row_top }
    let side_size = float2 { TT_SIDE * k, bottom - row_top }
    let tree_at = float2 { side_at.x + side_size.x + 14.0 * k, row_top }
    let tree_size = float2 { ws.x - 20.0 * k - tree_at.x, bottom - row_top }
    let inset = 20.0 * k
    let rail_at = tree_at + float2_1 * inset
    let bar_h = 12.0 * k
    let view_at = rail_at + float2 { TT_RAIL * k, 0.0 }
    let view_size = float2 { tree_at.x + tree_size.x - inset - view_at.x, tree_size.y - inset * 2.0 - bar_h - 8.0 * k }
    let side_in = side_at + float2 { inset, inset + 6.0 * k }
    let side_in_size = side_size - float2 { inset * 2.0, inset * 2.0 + 6.0 * k }
    let canvas = tt_canvas * k
    let max_x = max(0.0, canvas.x - view_size.x)
    let max_y = max(0.0, canvas.y - view_size.y)
    let max_ly = max(0.0, tt_side_h * k - side_in_size.y)
    let bar_at = float2 { view_at.x, view_at.y + view_size.y + 8.0 * k }
    let bar_size = float2 { view_size.x, bar_h }
    def over(at:float2, size:float2) -> bool: return m.x >= at.x and m.y >= at.y and m.x < at.x + size.x and m.y < at.y + size.y
    // input: the wheel, a drag, the arrows, the sticks, the d-pad
    let dt = gl.delta_time()
    let wheel = float(gl.mousewheel_delta())
    if over(side_at, side_size): tt_ly -= wheel * 60.0 * k
    else: tree_scroll -= wheel * 120.0 * k
    if gl.button("right") >= 1: tree_scroll += TT_LANE * 12.0 * k * dt
    if gl.button("left") >= 1: tree_scroll -= TT_LANE * 12.0 * k * dt
    if gl.button("home") == 1: tree_scroll = 0.0
    if gl.button("end") == 1: tree_scroll = max_x
    let mb = max(gl.button("mouse1"), gl.button("mouse3"))
    if mb == 1:
        tt_drag_at = m
        tt_drag = if over(bar_at - float2 { 0.0, 4.0 * k }, bar_size + float2 { 0.0, 8.0 * k }) and max_x > 0.0: 1 elif over(view_at, view_size): 0 elif over(side_at, side_size): 2 else: -1
    if mb >= 1 and tt_drag >= 0:
        let d = m - tt_drag_at
        if magnitude(d) > 0.0:
            if tt_drag == 0:
                tree_scroll -= d.x
                tt_sy -= d.y
            elif tt_drag == 1: tree_scroll += d.x * canvas.x / view_size.x
            else: tt_ly -= d.y
            tt_drag_at = m
    if mb < 1: tt_drag = -1
    let ls = float2 { gl.controller_axis(0), gl.controller_axis(1) }
    let rs = float2 { gl.controller_axis(2), gl.controller_axis(3) }
    if magnitude(ls) > 0.2:
        tree_scroll += ls.x * 1400.0 * k * dt
        tt_sy += ls.y * 1400.0 * k * dt
        tt_pad = true
    if magnitude(rs) > 0.2:
        tt_ly += rs.y * 1400.0 * k * dt
        tree_scroll += rs.x * 1400.0 * k * dt
        tt_pad = true
    // the d-pad walks the nodes (its card shown), the tree following
    let dir = float2 { (if gl.button("controller_dpright") == 1: 1.0 else: 0.0) - (if gl.button("controller_dpleft") == 1: 1.0 else: 0.0),
                       (if gl.button("controller_dpdown") == 1: 1.0 else: 0.0) - (if gl.button("controller_dpup") == 1: 1.0 else: 0.0) }
    if magnitude(dir) > 0.0:
        tt_pad = true
        if tt_focus < 0: tt_focus = 0
        else:
            let a0, s0 = tt_box(t.nodes[tt_focus])
            let here = a0 + s0 * 0.5
            var best = -1
            var best_d = 1000000000.0
            for(t.nodes) n, i:
                let a1, s1 = tt_box(n)
                let off = a1 + s1 * 0.5 - here
                let along = dot(off, dir)
                if i != tt_focus and along > 1.0:
                    let score = along + 3.0 * magnitude(off - dir * along)
                    if score < best_d:
                        best_d = score
                        best = i
            if best >= 0: tt_focus = best
        let fa, fsz = tt_box(t.nodes[tt_focus])
        if fa.x * k - tree_scroll < 0.0: tree_scroll = fa.x * k - 20.0 * k
        if (fa.x + fsz.x) * k - tree_scroll > view_size.x: tree_scroll = (fa.x + fsz.x) * k - view_size.x + 20.0 * k
        if fa.y * k - tt_sy < 0.0: tt_sy = fa.y * k
        if (fa.y + fsz.y) * k - tt_sy > view_size.y: tt_sy = (fa.y + fsz.y) * k - view_size.y
    if gl.button("mouse1") == 1 or magnitude(float(gl.mouse_delta(0))) > 2.0:
        tt_pad = false
        tt_focus = -1
    tree_scroll = clamp(tree_scroll, 0.0, max_x)
    tt_sy = clamp(tt_sy, 0.0, max_y)
    tt_ly = clamp(tt_ly, 0.0, max_ly)
    let o = view_at - float2 { tree_scroll, tt_sy }  // the tree's origin on the screen
    var hover = -1
    if over(view_at, view_size) and not tt_pad and tt_drag != 1:
        for(t.nodes) n, i:
            let a, s = tt_box(n)
            if over(o + a * k, s * k): hover = i
    if tt_pad and tt_focus >= 0: hover = tt_focus
    for(t.nodes) n, i:
        if n.key == tree_hover_arg: hover = i
    var closing = false
    // the backdrop, the title bar, the two panels
    ui_batch():
        ui_paint(float2_0, ws, float4 { 0.165, 0.11, 0.07, 1.0 }, "wood")
        ui_fill(float2_0, ws, float4 { 0.0, 0.0, 0.0, 0.45 })
        ui_text_f(float2 { 20.0 * k, top + 2.0 * k }, "Tech tree:  " + tree_title, int(36.0 * k), lk.title, 2, 1.5 * k)
        let cbw = 150.0 * k
        let cb_at = float2 { ws.x - 20.0 * k - cbw, top }
        if ui_button(cb_at, float2 { cbw, head_h }, if tt_pad: "Close (B)" else: "Close (Esc)", false): closing = true
        // the key, right to left from the button
        let legend = if tt_match: [ "Have it", "Under way", "Can get", "Not yet", "Planned", "Race\'s own" ] else: [ "Can get", "Planned", "Race\'s own" ]
        let legend_st = if tt_match: [ TT_DONE, TT_PROGRESS, TT_OPEN, TT_LOCKED, TT_PLANNED, -1 ] else: [ TT_OPEN, TT_PLANNED, -1 ]
        var kx = cb_at.x - 24.0 * k
        var ki = legend.length - 1
        while ki >= 0:
            let label = legend[ki]
            let lw = tt_measure(label, int(16.0 * k), 0)
            kx -= lw
            ui_text(float2 { kx, top + head_h / 2.0 - 10.0 * k }, label, int(16.0 * k), TT_DIM)
            kx -= 26.0 * k
            tt_swatch(float2 { kx, top + head_h / 2.0 - 9.0 * k }, legend_st[ki], k)
            kx -= 16.0 * k
            ki--
        ui_box(side_at, side_size, 1, lk.face, true)
        ui_box(tree_at, tree_size, 1, lk.face, true)
        tb_icon_wide("crest_" + lk.ornament, float2 { side_at.x + side_size.x / 2.0, side_at.y + 2.0 * k }, 34.0 * k)
    ui_flush()
    // the race panel (scrolled under its frame)
    tt_scissor(side_in, side_in_size)
    ui_batch():
        let sx = side_in.x
        let sy = side_in.y - tt_ly
        for(tt_side_top) l: ui_text_f(float2 { sx, sy + l.at.y * k }, l.s, int(l.size * k + 0.5), l.col, l.font, if l.font == 2: 1.5 * k else: 0.0)
        // the stage: the army idling on a strip of grass, sunk in the panel
        let st_at = float2 { sx, sy + tt_stage_y * k }
        let st_size = float2 { side_in_size.x, TT_STAGE_H * k }
        ui_box(st_at, st_size, -1, lk.well, false)
        let in_at = st_at + float2_1 * 4.0 * k
        let in_size = st_size - float2_1 * 8.0 * k
        ui_paint(in_at, in_size, TT_GRASS, "felt")
        ui_fill(in_at, float2 { in_size.x, in_size.y * 0.35 }, float4 { 0.05, 0.08, 0.02, 0.35 })
        ui_radial(in_at, in_size, float2 { 0.5, 0.7 }, float2 { 0.8, 1.1 }, float4 { 1.0, 0.92, 0.7, 0.1 }, float4 { 0.02, 0.03, 0.0, 0.5 })
        for(tt_side_lines) l: ui_text_f(float2 { sx, sy + l.at.y * k }, l.s, int(l.size * k + 0.5), l.col, l.font, 0.0)
        for(tt_rules_y) ry: tt_rule(sx, sy + ry * k, side_in_size.x, k)
        ui_flush()
        tt_scissor(max(in_at, side_in), min(in_at + in_size, side_in + side_in_size) - max(in_at, side_in))
        let units = glist(tt_race, "units")
        let age = if tt_match: ages[ME] else: 1
        let z = 0.7 * k
        b_sheet = -1
        for([ 0, 1 ]) row:
            for(units) u, i:
                if i % 2 == row:
                    var step = glist(u, "line")[0]
                    for(glist(u, "line")) l:
                        if gint(l, "age", 1) <= age: step = l
                    let r = at(step, "recipe")
                    let key = tt_key(r)
                    if tt_figure_ready(key, r):
                        let px = in_size.x * (float(i) + 0.7) / (float(units.length) + 0.4)
                        draw_figure(key, r, tt_owner, in_at + float2 { px, in_size.y * (if row == 0: 0.62 else: 0.86) }, z)
        flush_sprites()
    tt_unscissor()
    // the tree (scrolled under the rail and its frame)
    tt_scissor(view_at, view_size)
    ui_batch():
        let cw = max(canvas.x, view_size.x)
        for(t.ages) a, i:  // the ages as bands
            let y = o.y + float(i) * TT_ROW_H * k
            if a.age % 2 == 0: ui_fill(float2 { view_at.x, y }, float2 { view_size.x, TT_ROW_H * k }, float4 { 1.0, 1.0, 1.0, 0.022 })
            if i > 0: ui_fill(float2 { view_at.x, y }, float2 { cw, max(1.0, k) }, float4 { TT_EDGE.x, TT_EDGE.y, TT_EDGE.z, 0.45 })
        for(t.columns) c, ci:  // each building's column, from its age down
            let cx = tt_col_x[ci]
            let ctop = float(c.age - 1) * TT_ROW_H + 3.0
            let at = o + float2 { cx.x, ctop } * k
            let size = float2 { cx.y, tt_canvas.y - ctop - 3.0 } * k
            if at.x < view_at.x + view_size.x and at.x + size.x > view_at.x:
                ui_fill(at, size, float4 { TT_PANEL.x, TT_PANEL.y, TT_PANEL.z, if c.planned: 0.35 else: 0.75 })
                ui_outline(at, size, max(1.0, k), float4 { TT_EDGE.x, TT_EDGE.y, TT_EDGE.z, if c.planned: 0.3 else: 0.65 })
        // the lines: from each building down to its lanes; between the nodes in a lane
        let lw = 2.0 * k
        for(t.nodes) bn, bi:
            if bn.kind == "building":
                let ba, bs = tt_box(bn)
                if (o.x + ba.x * k) < view_at.x + view_size.x + 200.0 * k and (o.x + (ba.x + bs.x) * k) > view_at.x - 200.0 * k:
                    let bx = o.x + (ba.x + bs.x * 0.5) * k
                    let bus_y = o.y + (ba.y + TT_BNODE + TT_BNAME_H + TT_BUS * 0.5) * k
                    let built = not bn.planned
                    let bus_c = tt_line_col(built, tt_state[bi] == TT_DONE)
                    var x0 = bx
                    var x1 = bx
                    let lanes = tt_lanes[bn.col]
                    for(lanes) ns:
                        let first = t.nodes[ns[0]]
                        let fa = tt_box_at(first)
                        let lx = o.x + (fa.x + TT_LANE * 0.5) * k
                        x0 = min(x0, lx)
                        x1 = max(x1, lx)
                        let on = built and not first.planned and not first.lacks
                        ui_line(float2 { lx, bus_y }, float2 { lx, o.y + fa.y * k + k }, lw, tt_line_col(on, tt_state[ns[0]] == TT_DONE))
                        for(ns.length - 1) j:
                            let b = t.nodes[ns[j + 1]]
                            let from_at = float2 { lx, o.y + (tt_box_at(t.nodes[ns[j]]).y + TT_NODE + 1.0) * k }
                            let to = float2 { lx, o.y + tt_box_at(b).y * k + k }
                            if tt_joined[ns[j + 1]] == ns[j]: ui_line(from_at, to, lw, tt_line_col(not b.planned, tt_state[ns[j + 1]] == TT_DONE))
                            else: tt_dash(from_at, to, max(1.0, k), float4 { TT_EDGE.x, TT_EDGE.y, TT_EDGE.z, 0.45 }, 3.0 * k)
                    if lanes.length:
                        ui_line(float2 { bx, o.y + (ba.y + TT_BNODE + TT_BNAME_H - 2.0) * k }, float2 { bx, bus_y }, lw, bus_c)
                        ui_line(float2 { x0 - lw * 0.5, bus_y }, float2 { x1 + lw * 0.5, bus_y }, lw, bus_c)
        // the frames
        for(t.nodes) n, i:
            let a, s = tt_box(n)
            let at = o + a * k
            if at.x < view_at.x + view_size.x and at.x + s.x * k > view_at.x:
                let side = tt_frame_side(n)
                tt_frame(at + float2 { (s.x - side) * 0.5 * k, 0.0 }, side * k, tt_state[i], hover == i, k)
        ui_batch_flush()
        // the pictures, from the page in one draw
        let page = tt_page_tex
        if page:
            let pos = []::float3
            let cols = []::float4
            let tcs = []::float2
            let idx = []::int
            let pn = float(TT_PAGE)
            for(t.nodes) n, i:
                let cell = tt_cells.get(n.key, int4_0)
                if cell.w > 0:
                    let a, s = tt_box(n)
                    let side = tt_frame_side(n)
                    let pin = if n.kind == "unit": 3.0 else: 5.0
                    let at = float(floor(o + (a + float2 { (s.x - side) * 0.5 + pin, pin }) * k + float2 { 0.0, k * 0.5 }))
                    if at.x < view_at.x + view_size.x and at.x + float(cell.z) > view_at.x:
                        let alpha = if tt_state[i] == TT_LOCKED: 0.38 else: 1.0
                        let e = at + float2_1 * float(cell.z)
                        let u0 = float(cell.x) / pn
                        let u1 = float(cell.x + cell.z) / pn
                        let v0 = 1.0 - float(cell.y) / pn
                        let v1 = 1.0 - float(cell.y + cell.z) / pn
                        let v = pos.length
                        pos.push(float3 { at.x, at.y, 0.0 })
                        pos.push(float3 { e.x, at.y, 0.0 })
                        pos.push(float3 { e.x, e.y, 0.0 })
                        pos.push(float3 { at.x, e.y, 0.0 })
                        tcs.push(float2 { u0, v0 })
                        tcs.push(float2 { u1, v0 })
                        tcs.push(float2 { u1, v1 })
                        tcs.push(float2 { u0, v1 })
                        for(4): cols.push(float4 { alpha, alpha, alpha, alpha })
                        for([ 0, 2, 1, 0, 3, 2 ]) q: idx.push(v + q)
            if pos.length:
                gl.set_shader("textured_color")
                gl.set_primitive_texture(0, page)
                gl.color(float4_1): gl.draw_mesh("PCT", pos, cols, []::float3, tcs, []::float2, idx)
                gl.set_shader("color")
        // over the pictures: bars under way, crosses, the race's own marks, the names
        for(t.nodes) n, i:
            let a, s = tt_box(n)
            let at = o + a * k
            if at.x < view_at.x + view_size.x and at.x + s.x * k > view_at.x:
                let side = tt_frame_side(n) * k
                let f0 = at + float2 { (s.x * k - side) * 0.5, 0.0 }
                if tt_state[i] == TT_PROGRESS:
                    let bar = f0 + float2 { 3.0 * k, side - 8.0 * k }
                    ui_fill(bar, float2 { side - 6.0 * k, 5.0 * k }, float4 { 0.0, 0.0, 0.0, 0.7 })
                    ui_fill(bar, float2 { (side - 6.0 * k) * clamp(tt_prog[i], 0.0, 1.0), 5.0 * k }, TT_GOLD)
                if n.lacks:
                    let c = float4 { TT_NEED.x, TT_NEED.y, TT_NEED.z, 0.85 }
                    ui_line(f0 + float2_1 * 6.0 * k, f0 + float2_1 * (side - 6.0 * k), 2.5 * k, c)
                    ui_line(f0 + float2 { side - 6.0 * k, 6.0 * k }, f0 + float2 { 6.0 * k, side - 6.0 * k }, 2.5 * k, c)
                elif n.race_only: tt_diamond(f0 + float2 { side - 7.0 * k, 7.0 * k }, 5.0 * k, TT_GOLD)
                let st = tt_state[i]
                let nc = if st == TT_PLANNED: float4 { 0.541, 0.506, 0.455, 1.0 } elif st == TT_LOCKED: float4 { TT_DIM.x, TT_DIM.y, TT_DIM.z, 0.6 } elif st == TT_DONE: float4 { 0.965, 0.863, 0.541, 1.0 } else: TT_TEXT
                let nsz = int((if n.kind == "building": 14.0 else: 12.0) * k + 0.5)
                for(tt_names[i]) l, j:
                    ui_text_f(float2 { at.x + s.x * k * 0.5 - tt_measure(l, nsz, 0) / 2.0, at.y + side + 1.0 * k + float(j) * float(nsz) * 1.05 }, l, nsz, nc, 0, 1.2 * k)
    ui_flush()
    tt_unscissor()
    // the rail: each age's number, name and what it needs, fixed while the tree scrolls sideways
    tt_scissor(rail_at, float2 { TT_RAIL * k, view_size.y })
    ui_batch():
        for(t.ages) a, i:
            let y = o.y + float(i) * TT_ROW_H * k
            if a.age % 2 == 0: ui_fill(float2 { rail_at.x, y }, float2 { TT_RAIL * k, TT_ROW_H * k }, float4 { 1.0, 1.0, 1.0, 0.022 })
            if i > 0: ui_fill(float2 { rail_at.x, y }, float2 { TT_RAIL * k, max(1.0, k) }, float4 { TT_EDGE.x, TT_EDGE.y, TT_EDGE.z, 0.45 })
            if tt_match and ages[ME] == a.age: ui_fill(float2 { rail_at.x, y + 6.0 * k }, float2 { 4.0 * k, TT_ROW_H * k - 12.0 * k }, TT_GOLD)  // where you are
            if tt_match and tt_age_bar >= 0.0 and a.age == ages[ME] + 1:                                                                         // an age-up under way
                let bat = float2 { rail_at.x + 14.0 * k, y + (TT_ROW_H - 22.0) * k }
                ui_fill(bat, float2 { (TT_RAIL - 28.0) * k, 6.0 * k }, float4 { 0.0, 0.0, 0.0, 0.5 })
                ui_fill(bat, float2 { (TT_RAIL - 28.0) * k * clamp(tt_age_bar, 0.0, 1.0), 6.0 * k }, TT_GOLD)
        ui_fill(float2 { rail_at.x + TT_RAIL * k - max(1.0, k), rail_at.y }, float2 { max(1.0, k), view_size.y }, float4 { TT_EDGE.x, TT_EDGE.y, TT_EDGE.z, 0.6 })
        for(tt_rail) l: ui_text_f(float2 { rail_at.x + l.at.x * k, o.y + l.at.y * k }, l.s, int(l.size * k + 0.5), l.col, l.font, 0.0)
    ui_flush()
    tt_unscissor()
    ui_batch():
        // the scroll bar
        if max_x > 0.0:
            ui_fill(bar_at, bar_size, float4 { 0.0, 0.0, 0.0, 0.45 })
            let tw = max(30.0 * k, bar_size.x * view_size.x / canvas.x)
            let tx = bar_at.x + (bar_size.x - tw) * tree_scroll / max_x
            let hot = tt_drag == 1 or over(bar_at, bar_size)
            ui_fill(float2 { tx, bar_at.y + 2.0 * k }, float2 { tw, bar_h - 4.0 * k }, if hot: TT_GOLD else: TT_BRONZE * float4 { 1.0, 1.0, 1.0, 0.9 })
        // the loader: the pictures being painted (Godot's forge veil)
        if waiting > 0:
            let total = (filter(t.nodes) n: not n.planned).length
            let f = 1.0 - float(waiting) / float(max(1, total))
            let vc = float2 { tree_at.x + tree_size.x / 2.0, tree_at.y + tree_size.y / 2.0 }
            ui_fill(float2 { vc.x - 260.0 * k, vc.y - 50.0 * k }, float2 { 520.0 * k, 100.0 * k }, float4 { 0.05, 0.03, 0.01, 0.8 })
            ui_text_c(vc.x, vc.y - 38.0 * k, "Painting the portraits...  {int(f * 100.0)}%", int(22.0 * k), lk.accent, 2, 1.5 * k)
            ui_fill(float2 { vc.x - 210.0 * k, vc.y + 10.0 * k }, float2 { 420.0 * k, 16.0 * k }, float4 { 0.0, 0.0, 0.0, 0.6 })
            ui_fill(float2 { vc.x - 207.0 * k, vc.y + 13.0 * k }, float2 { 414.0 * k * f, 10.0 * k }, TT_GOLD * float4 { 0.8, 0.8, 0.8, 1.0 })
        // the card for what's hovered
        if hover >= 0:
            let n = t.nodes[hover]
            let a, s = tt_box(n)
            let near = if tt_pad or tree_hover_arg != "": o + (a + float2 { s.x, tt_frame_side(n) }) * k + float2_1 * 6.0 * k else: m + float2 { 16.0, 20.0 } * k
            tt_card(t, n, tt_state[hover], tt_prog[hover], near, k)
    ui_flush()
    ui_use(was_look)
    if closing: tree_open = false
    return true
