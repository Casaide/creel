// ------------------------------------------------------------------ the top bar's layout (#370)
// Each piece's width from its texts, and the bar fitted to the window: the race's name gives up room first (cut,
// with "...", down to nothing), then the bar's scale, until the bar's right edge is inside the window. Pure (no
// window, no match), so run_tests checks it at every size; draw_topbar (game/topbar.lobster) draws what it says.
// Imported by game.lobster before game/ui (which uses ui_caps_gap).

// The HUD's scale for a player's size (hud_size) in a window this big: smaller only where the HUD wouldn't fit
// (HUD_NEEDS: 1480 x 760).
def hud_scale(size:int, ws:float2) -> float:
    return min(float(size) / 100.0, min(ws.x / 1480.0, ws.y / 760.0))  // (the player's size, as far as the window fits it)

def ui_caps_gap(size:int) -> float: return float(size) * 0.14  // a caption's room between letters (Godot's 2 px at 14)

// About the room text takes (gl.text_size doesn't match what's drawn at every scale).
def tb_text_w(s:string, size:int, font:int) -> float:
    let gaps = if font == 3: ui_caps_gap(size) * float(max(0, s.length - 1)) else: 0.0
    return (if font == 2: 0.72 elif font >= 1: 0.58 else: 0.52) * float(size) * float(s.length) + gaps

// What the bar shows (the texts that size it).
class TbTexts:
    stocks:[string]  // each resource's stock
    pop:string       // "pop/cap"
    title:string     // the race's name
    age_num:string   // the age's number
    age:string       // the age's name (and, ageing up, the next and how far)
    clock:string
    pace:string  // "Paused", "x2.0" or ""

// Where it goes: the scale, each piece's width, the name as shown (cut to fit), the bar's width.
class TbLayout:
    s:float
    res_w:[float]
    pop_w:float
    title:string
    title_w:float
    age_w:float
    idle_w:float
    tree_w:float
    clock_w:float
    pace_w:float
    w:float

def tb_widths(t:TbTexts, s:float, title:string) -> TbLayout:
    let sep = 10.0 * s
    let res_w = map(t.stocks) st: 8.0 * s + 28.0 * s + 6.0 * s + max(50.0 * s, tb_text_w(st, int(20.0 * s), 1)) + 8.0 * s
    let pop_w = 8.0 * s + 28.0 * s + 6.0 * s + max(66.0 * s, tb_text_w(t.pop, int(20.0 * s), 1)) + 8.0 * s
    let title_w = tb_text_w(title, int(22.0 * s), 2)
    let age_w = 8.0 * s + 26.0 * s + 6.0 * s + tb_text_w(t.age_num, int(24.0 * s), 2) + 6.0 * s + tb_text_w(t.age, int(17.0 * s), 1) + 8.0 * s
    let idle_w = 74.0 * s
    let tree_w = 12.0 * s + 22.0 * s + 6.0 * s + tb_text_w("Tech tree", int(17.0 * s), 1) + 12.0 * s
    let clock_w = 8.0 * s + max(52.0 * s, tb_text_w(t.clock, int(18.0 * s), 1)) + 8.0 * s
    let pace_w = if t.pace != "": 8.0 * s + tb_text_w(t.pace, int(16.0 * s), 1) + 8.0 * s else: 0.0
    var w = 16.0 * s * 2.0
    for(res_w) rw: w += rw + sep
    w += pop_w + sep + 8.0 * s + sep + (if title != "": title_w + sep else: 0.0) + age_w + sep + idle_w + sep + tree_w + sep + clock_w
    if t.pace != "": w += sep + pace_w
    return TbLayout { s, res_w, pop_w, title, title_w, age_w, idle_w, tree_w, clock_w, pace_w, w }

// The bar starts 10 px (at its scale) in from the left, and keeps as much room on the right.
def tb_fits(l:TbLayout, win_w:float) -> bool: return l.w <= win_w - 20.0 * l.s

// The bar for a window win_w wide at the HUD's scale s.
def tb_layout(t:TbTexts, win_w:float, s:float) -> TbLayout:
    let whole = tb_widths(t, s, t.title)
    if tb_fits(whole, win_w): return whole
    // The name, cut a letter at a time (spaces at the cut go too).
    var n = t.title.length - 1
    while n > 0:
        let cut = tb_widths(t, s, strip_edges(t.title.substring(0, n)) + "...")
        if tb_fits(cut, win_w): return cut
        n--
    // No name, and the scale down until the rest fits.
    var l = tb_widths(t, s, "")
    while not tb_fits(l, win_w): l = tb_widths(t, l.s * 0.95, "")
    return l

// ---- the plaques' lines, top to bottom (#376)
// Lobster draws a line's glyphs in its size's box centred by the font's tallest and deepest glyphs, so the ink isn't
// the box. Where it is, as a share of the size below where the line is drawn (measured in captures of the bar at
// s 0.865 and 1.15: digits and capitals, to a pixel).
let TB_BOLD_INK = float2 { 0.05, 0.78 }
let TB_DISPLAY_INK = float2 { 0.11, 0.86 }

def tb_ink(y:float, size:int, font:int) -> float2:
    let k = if font == 2: TB_DISPLAY_INK else: TB_BOLD_INK
    return float2 { y + k.x * float(size), y + k.y * float(size) }

// Where each line goes, down from its plaque's top (48 px high at s).
class TbRows:
    stock:float  // a resource's stock (20 px, bold)
    work:float   // its workers under it (15 px, bold), the small worker beside them (14 px)
    work_icon:float
    pop:float       // the population (20 px)
    clock:float     // (18 px)
    pace:float      // (16 px)
    age_icon:float  // the age's icon (26 px), its number (24 px, the display face) and name (17 px), the age-up's bar (5 px)
    age_num:float
    age_txt:float
    age_bar:float

// Where a line goes for its ink's middle at mid.
def tb_line_at(mid:float, size:int, font:int) -> float:
    let k = if font == 2: TB_DISPLAY_INK else: TB_BOLD_INK
    return mid - (k.x + k.y) / 2.0 * float(size)

// Every line on the plaque's middle: the stock over its workers as one block, the age's number and name on its
// icon's middle, and the icon with the age-up's bar under it as one block.
def tb_rows(s:float, ageing:bool) -> TbRows:
    let mid = 24.0 * s
    let big = int(20.0 * s)
    let small = int(15.0 * s)
    let big_h = (TB_BOLD_INK.y - TB_BOLD_INK.x) * float(big)
    let small_h = (TB_BOLD_INK.y - TB_BOLD_INK.x) * float(small)
    let top = mid - (big_h + 5.0 * s + small_h) / 2.0
    let work_mid = top + big_h + 5.0 * s + small_h / 2.0
    let icon = mid - (if ageing: 16.0 else: 13.0) * s
    let icon_mid = icon + 13.0 * s
    return TbRows { tb_line_at(top + big_h / 2.0, big, 1), tb_line_at(work_mid, small, 1), work_mid - 7.0 * s,
                    tb_line_at(mid, int(20.0 * s), 1), tb_line_at(mid, int(18.0 * s), 1), tb_line_at(mid, int(16.0 * s), 1), icon,
                    tb_line_at(icon_mid, int(24.0 * s), 2), tb_line_at(icon_mid, int(17.0 * s), 1), icon + 27.0 * s }
