// The mouse cursor, drawn by the OS (#222): one cursor per kind (game/cursor_images.lobster), picked each frame in a
// match; the lobby keeps the system's arrow. The mouse stays the OS's: it leaves the window, and shots of the screen see it.
// Pad and touch play hide it.

var os_cursors = []::resource<cursor>
var os_cursor_now = ""  // the kind in use ("": the system's)
var os_cursor_hidden = false

def os_cursors_make():
    if os_cursors.length: return
    for(CURSOR_KINDS) kind:
        let c = gl.cursor_image(cursor_image(kind, 1), cursor_image(kind, 2), cursor_hot(kind))
        assert c
        os_cursors.push(c)

def os_cursor_hide(hide:bool):
    if hide != os_cursor_hidden:
        gl.cursor_visible(not hide)
        os_cursor_hidden = hide

// Once a frame in a match, after the mouse moved.
def os_cursor_tick():
    os_cursor_hide(pad_on or touch_play)
    if os_cursor_hidden: return
    os_cursors_make()
    let kind = cursor_kind(mouse_px())
    if kind != os_cursor_now:
        let at = find(CURSOR_KINDS) k: k == kind
        gl.cursor_set(os_cursors[at])
        os_cursor_now = kind

// Out of a match: the system's arrow again.
def os_cursor_release():
    os_cursor_hide(false)
    gl.cursor_set_default()
    os_cursor_now = ""

// What a right click would do at m (order in game.lobster), as a cursor's name.
def cursor_kind(m:float2) -> string:
    if menu_open or placing >= 0 or tree_open or typing_text or end_screen_up() or panel_click(m) or in_minimap(m): return "pointer"
    if arming_attack or arming_ability: return "attack"
    let all = selected_units()
    if not all.length: return "pointer"
    let ids = filter(all) id: not is_animal(index_of(id))
    if not ids.length: return "move"
    let mm = order_milli(m)
    let x = int(mm.x)
    let y = int(mm.y)
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return "pointer"
    let workers = selected_workers().length > 0
    let c = cell_of(x, y)
    let b = building_at(mm)
    let mine = unit_at_screen(m, true)
    if unit_at_screen(m, false) >= 0: return "attack"
    if mine >= 0 and u_owner[mine] == ME and is_animal(mine) and workers: return "attack"
    if b >= 0 and is_enemy(b_owner[b], ME) and fog[ME][c] != 0: return "attack"
    if workers:
        let bridge = bridge_on(c)
        if res_at(c) != 0: return cursor_of_resource(res_at(c))
        if bridge >= 0 and br_up[bridge] == 0: return "build"
        if mine >= 0 and can_mend(ME, u_id[mine]): return "build"
        if b >= 0:
            if can_mend(ME, b_id[b]): return "build"
            if b_owner[b] == ME:
                if b_done[b] == 0 or pool[c] >= 0: return "build"
                for(ids) id:
                    let i = index_of(id)
                    if takes_in(b, i): return cursor_of_resource(u_carry_kind[i])
    elif b >= 0 and places(c) > 0 and teams[b_owner[b]] == teams[ME]: return "wall"  // (up onto our wall)
    return "move"

def cursor_of_resource(res:int) -> string:
    let name = resource_names[res - 1]
    return if name == "food": "forage" elif name == "wood": "chop" else: "mine"
