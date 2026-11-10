// ------------------------------------------------------------------ playing by touch (a phone, a tablet)
// Touch plays through the pad's controls (game/pad.lobster): the finger is the reticle. A tap selects (on what's
// already selected it opens the wheel: train, research, age up, build); a double tap is the right click, an order
// for the selection there (move, gather, attack: the pad's X; a building's rally point). Held still, a circle grows
// under the finger and sweeps up your units. One finger dragged pans; two pinch to zoom and pan. While a building is
// being placed (shown first in the middle of the screen) a tap puts it down there and a drag pans; a wall or gate
// is dragged from one end to the other. On the wheel a tap chooses, a tap off it closes it. The phone's back button backs out (the pad's B): placing, the wheel, the selection, then the menu.
// A touch that starts on the panel, the top bar or the minimap is theirs (the mouse's way). Imported by game.lobster
// after the pad, the panel and the top bar; on when the game is given "touch" (the Android build).

let TOUCH_SLOP = 14.0       // screen points a finger may wander and still tap or hold
let TOUCH_HOLD = 0.3        // seconds still before a hold grows the circle
let TOUCH_PINCH_STEP = 1.3  // how far fingers spread (or close) for one zoom step

var touch_down = false   // a finger is on the world now
var touch_hud = false    // this touch began on the panel, top bar or minimap
var touch_at = float2_0  // where it went down
var touch_last = float2_0
var touch_t = 0.0  // how long it's been down
var touch_panned = false
var touch_pinch = 0.0  // the two fingers' distance at the last zoom step (0: one finger)
var touch_mid = float2_0
var touch_wants_menu = false
var touch_placing = -1  // the building type being placed when last seen (a new one starts mid-screen)

// A tap on the world: selects what's there (your units or a building, a foe or a sheep to look at, nothing: the
// selection let go); on what's already selected it opens the wheel. A second tap in the same spot soon after is the
// right click: the selection from before the first tap gets an order there (move, gather, attack, build, garrison).
let TOUCH_DOUBLE = 0.35  // seconds between the two taps of a double tap
var touch_tap_t = -100.0
var touch_tap_at = float2_0
var touch_before = []::int  // the selection before the first tap of a pair
var touch_before_b = 0

def touch_tap(m:float2):
    if placing >= 0:
        place_here(false)
        return
    let now = gl.time()
    if now - touch_tap_t < TOUCH_DOUBLE and magnitude(m - touch_tap_at) < TOUCH_SLOP * 2.0 * ui():
        touch_tap_t = -100.0
        pad_wheel = []
        selected = touch_before
        sel_building = touch_before_b
        let b = b_index_of(sel_building)
        if (filter(selected_units()) id: u_owner[index_of(id)] == ME).length or (b >= 0 and b_owner[b] == ME and not selected.length): order(m)
        return
    touch_tap_t = now
    touch_tap_at = m
    touch_before = selected
    touch_before_b = sel_building
    if is_selected_here(m): wheel_open()
    else: click_select(m)

// A tap on the wheel: its buttons press themselves (they're the panel's, game/panel.lobster: wheel_draw); a tap in
// the ring's middle turns the page, one off the ring closes it.
def touch_wheel_tap(m:float2):
    let items, r = wheel_layout()
    for(items) it:
        if m.x >= it.at.x - it.side * 0.1 and m.y >= it.at.y - it.side * 0.1 and m.x <= it.at.x + it.side * 1.1 and m.y <= it.at.y + it.side * 1.1: return
    if wheel_pages() > 1 and magnitude(m - float(gl.window_size()) / 2.0) < r * 0.6:
        pad_page = (pad_page + 1) % wheel_pages()
        pad_pick = 0
    else: pad_wheel = []

// The back button: what the pad's B does, then the pause menu.
def touch_back():
    if pad_wheel.length: pad_wheel = []
    elif placing >= 0:
        placing = -1
        wall_from = int2 { -1, -1 }
    elif build_menu: build_menu = false
    elif selected.length or sel_building != 0 or sel_foreign != 0:
        selected = []
        sel_building = 0
        sel_foreign = 0
    else: touch_wants_menu = true  // (game.lobster opens the pause menu)

// One frame of touch. True: it took the input (the mouse's way is skipped); false: a touch on the panel, top bar or
// minimap, left to the mouse.
def touch_tick(dt:float) -> bool:
    pad_on = true  // (the pad's drawing: the circle, the wheel)
    if gl.button("ac back") == 1: touch_back()
    let one, one_up = gl.button("mouse1")
    let quick = one < 1 and one_up == 1 and not touch_down and not touch_hud  // (see ui_clicked)
    let two = gl.button("mouse11")
    let m = float(gl.mouse_pos(0))
    if placing != touch_placing:
        touch_placing = placing
        if placing >= 0 and one < 1: fake_mouse = float(gl.window_size()) / 2.0
    let line = placing >= 0 and bt_line[placing] != 0  // (a wall or gate: the finger drags its line, not the view)
    if (one == 1 or quick) and two < 1:                // a finger went down
        touch_hud = in_panel(m) or in_topbar(m) or in_minimap(m) or (in_build_button(m) and placing < 0 and not pad_wheel.length)
        touch_down = not touch_hud
        touch_at = m
        touch_last = m
        touch_t = 0.0
        touch_panned = false
        touch_pinch = 0.0
    if touch_hud:
        if one < 1: touch_hud = false
        fake_mouse = float2 { -1.0, -1.0 }
        return false
    pad_reticle_shown = touch_down
    if not touch_down: return true
    let ws = float(gl.window_size())
    pad_off = m - ws / 2.0  // (the reticle under the finger)
    fake_mouse = m
    if one == 1 and line: wall_from = place_cell()
    if two >= 1:  // two fingers: pinch to zoom, both to pan
        let m2 = float(gl.mouse_pos(1))
        let d = magnitude(m2 - m)
        let mid = (m + m2) / 2.0
        if touch_pinch == 0.0:
            touch_pinch = d
            touch_mid = mid
        else:
            cam -= (mid - touch_mid) / zoom
            touch_mid = mid
            if d > touch_pinch * TOUCH_PINCH_STEP and zoom < 8.0:
                zoom += 1.0
                touch_pinch = d
            elif d < touch_pinch / TOUCH_PINCH_STEP and zoom > 1.0:
                zoom -= 1.0
                touch_pinch = d
        touch_panned = true  // (no tap or hold from this touch)
        pad_circle = 0.0
        touch_last = m
        return true
    if one >= 1:  // held: wander off to pan (or drag what's being placed), keep still to grow the circle
        touch_t += dt
        if magnitude(m - touch_at) > TOUCH_SLOP * ui() and pad_circle == 0.0 and not line: touch_panned = true
        if touch_panned and touch_pinch == 0.0: cam -= (m - touch_last) / zoom
        touch_last = m
        if not touch_panned and touch_t >= TOUCH_HOLD and placing < 0 and not pad_wheel.length:
            if pad_circle == 0.0:
                pad_circle = PAD_CIRCLE_START
                selected = []
                sel_building = 0
            pad_circle = min(pad_circle + PAD_CIRCLE_GROW * dt, min(ws.x, ws.y) * PAD_CIRCLE_MAX)
            for(u_id.length) i:
                if u_owner[i] == ME and t_animal[u_kind[i]] == 0 and not contains(selected, u_id[i]):
                    let s = to_screen(iso(float(u_x[i]), float(u_y[i])))
                    if magnitude((s - m) * float2 { 1.0, 2.0 }) <= pad_circle: selected.push(u_id[i])
        return true
    // lifted
    touch_down = false
    pad_reticle_shown = false
    if pad_circle > 0.0: pad_circle = 0.0
    elif line and wall_from.x >= 0: place_wall(wall_from, place_cell(), false)  // (the wall from where the finger went down)
    elif placing >= 0:
        if not touch_panned and touch_pinch == 0.0: place_here(false)  // (a tap: there)
    elif not touch_panned and touch_pinch == 0.0:
        let second = gl.time() - touch_tap_t < TOUCH_DOUBLE  // (a double tap: even when the first opened the wheel)
        if pad_wheel.length and not second: touch_wheel_tap(touch_last)
        else: touch_tap(touch_last)
    return true
