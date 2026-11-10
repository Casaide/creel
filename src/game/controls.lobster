// ------------------------------------------------------------------ playing: selection and orders, marks and the HUD, the minimap
// What a click or a key means on the map, the selection's rings and health bars, groups, placing buildings and walls,
// and the minimap. The game draws its own top bar (draw_topbar) and sizes the HUD (hud_s).

// ------------------------------------------------------------------ selection and orders

let groups = dictionary<int, [int]>(10)  // control group (0 for key 1) -> unit ids
var last_group = -1
var last_group_at = -10.0
var panel_hp = -1  // the HP the panel last drew (the self-test reads it)
var drag_from = float2_0
var dragging = false

def selected_units() -> [int]: return filter(selected) id: index_of(id) >= 0
def selected_workers() -> [int]: return filter(selected_units()) id: t_worker[u_kind[index_of(id)]] != 0

def unit_at_screen(m:float2, mine:bool) -> int:
    var best = -1
    var best_d = 24.0 * zoom
    for(u_x.length) i:
        if (teams[u_owner[i]] == teams[ME]) == mine and (mine or visible_to_me(cell_of(u_x[i], u_y[i]))):
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])) - float2 { 0.0, 14.0 + air_lift(u_kind[i]) })
            let d = magnitude(s - m)
            if d < best_d:
                best_d = d
                best = i
    return best

// Can I see building b now? (Remembered in the fog isn't enough: its HP would be live.)
def building_seen(b:int) -> bool:
    if teams[b_owner[b]] == teams[ME]: return true
    for(b_sy[b]) y:
        for(b_sx[b]) x:
            if visible_to_me((b_cy[b] + y) * W + b_cx[b] + x): return true
    return false

// The building drawn under the mouse (the frontmost), mine or one I can see that isn't, else -1.
def building_drawn_at(m:float2, mine:bool) -> int:
    let p = from_screen(m)
    var best = -1
    var best_y = -1000000000.0
    for(bld_hits) h:
        if p.x >= h.lo.x and p.y >= h.lo.y and p.x <= h.hi.x and p.y <= h.hi.y and h.sort_y > best_y:
            let b = b_index_of(h.id)
            if b >= 0 and (if mine: b_owner[b] == ME else: b_owner[b] != ME and building_seen(b)):
                best = b
                best_y = h.sort_y
    return best

def building_at(mm:float2) -> int:
    let x = int(mm.x)
    let y = int(mm.y)
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return -1
    let bid = occupied[cell_of(x, y)]
    return if bid != 0: b_index_of(bid) else: -1

// The wall cell drawn at m (-1: none): a wall is its footprint raised to the height it's drawn at, so a click on its
// face or top finds it, the frontmost first, and not past anything standing in front of it (Dominic, 2026-11-04).
let WALL_REACH = 160.0  // art px, more than a gate tower
def wall_cell_at(m:float2) -> int:
    let p = from_screen(m)
    var t = WALL_REACH
    while t >= 0.0:
        let mm = pick_milli(p + float2 { 0.0, t })
        let b = building_at(mm)
        if b >= 0:
            let c = cell_of(int(mm.x), int(mm.y))
            if (find(bld_hits) h: h.id == b_id[b] and h.lo.y <= p.y) >= 0 and (teams[b_owner[b]] == teams[ME] or fog[ME][c] != 0):
                return if bt_wall[b_kind[b]] != 0 or bt_gate[b_kind[b]] != 0: c else: -1
        t -= 4.0
    return -1

// The ground under m for an order: a wall drawn there, or what's under the mouse.
def order_milli(m:float2) -> float2:
    let c = wall_cell_at(m)
    return if c >= 0: float2 { float((c % W) * TILE + TILE / 2), float((c / W) * TILE + TILE / 2) } else: mouse_milli()

var last_click_at = -10.0  // the last click on one of my units (a second one soon after, near it, is a double click)
var last_click_at_m = float2_0
var last_click_kind = -1

// All my units of a kind on screen (a double click on one of them; shift adds them).
def select_kind_on_screen(kind:int, add:bool):
    let ws = float(gl.window_size())
    if not add: selected = []::int
    for(u_x.length) i:
        if u_owner[i] == ME and u_kind[i] == kind:
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])))
            if s.x >= 0.0 and s.y >= 0.0 and s.x <= ws.x and s.y <= ws.y and not contains(selected, u_id[i]): selected.push(u_id[i])

// Select what's under the mouse (shift: add a unit to the selection, or take it out; a double click: all of its kind on screen).
def click_select(m:float2):
    let add = shift_held() and sel_building == 0
    sel_building = 0
    sel_foreign = 0
    let i = unit_at_screen(m, true)
    if i >= 0 and u_owner[i] == ME:
        let dbl = u_kind[i] == last_click_kind and gl.time() - last_click_at < 0.4 and magnitude(m - last_click_at_m) < 12.0
        last_click_at = if dbl: -10.0 else: gl.time()  // (a third click starts over)
        last_click_at_m = m
        last_click_kind = u_kind[i]
        if dbl: select_kind_on_screen(u_kind[i], add)
        elif not add: selected = [ u_id[i] ]
        elif contains(selected, u_id[i]): selected = filter(selected) id: id != u_id[i]
        else: selected.push(u_id[i])
        say(ME, "select")
        return
    if add: return
    selected = []::int
    let ground = building_at(order_milli(m))
    var b = building_drawn_at(m, true)  // (the frontmost drawn there: a tower's top, over the ground behind it)
    if b < 0 and ground >= 0 and b_owner[ground] == ME: b = ground
    if b < 0:  // nothing of mine: what isn't mine, to look at
        let f = if i >= 0: i else: unit_at_screen(m, false)
        if f >= 0:
            sel_foreign = u_id[f]
            return
        b = building_drawn_at(m, false)
        if b < 0 and ground >= 0 and building_seen(ground): b = ground
    if b >= 0: sel_building = b_id[b]

// What's shown goes when it dies or is back in the fog; a foreign unit also when I select something of mine.
def drop_lost_selection():
    let b = b_index_of(sel_building)
    if b < 0 or not building_seen(b): sel_building = 0
    let i = index_of(sel_foreign)
    if i < 0 or selected.length or sel_building != 0 or not (teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i]))): sel_foreign = 0

def box_select(a:float2, b:float2):
    let lo = float2 { min(a.x, b.x), min(a.y, b.y) }
    let hi = float2 { max(a.x, b.x), max(a.y, b.y) }
    if not shift_held() or sel_building != 0: selected = []::int  // (shift adds to the selection)
    sel_building = 0
    sel_foreign = 0
    for(u_x.length) i:
        if u_owner[i] == ME:
            let s = to_screen(iso(float(u_x[i]), float(u_y[i])))
            if s.x >= lo.x and s.x <= hi.x and s.y >= lo.y and s.y <= hi.y and not contains(selected, u_id[i]): selected.push(u_id[i])
    if selected.length: say(ME, "select")

// The armed order (attack-move or the race's ability) given at m.
def give_armed(m:float2):
    if arming_attack: order(m, true)
    else:
        let mm = mouse_milli()
        issue_cmd(ME, CMD_ABILITY, selected_units(), int(mm.x), int(mm.y), 0, 0)
        say(ME, "ack")
    arming_attack = false
    arming_ability = false

// The map bridge whose deck covers cell c, or -1.
def bridge_on(c:int) -> int:
    for(br_cells) cells, k:
        if contains(cells, c): return k
    return -1

// Does building b take in what unit i carries?
def takes_in(b:int, i:int) -> bool: return u_carry[i] > 0 and u_carry_kind[i] > 0 and bt_drop[b_kind[b]][u_carry_kind[i] - 1] != 0

// The right click (sim_debug.smart_order): what's under the mouse decides the order. Our animals go into our
// pen or walk; the rest attack-move (A held, or armed), attack a foe or hunt, slaughter our sheep (workers),
// attack a foe's building, gather, rebuild a broken bridge, mend, wall up our breach, climb our wall, help
// build, trade at a market, drop off, reseed a fallow farm, go inside our building, or move.
def order(m:float2, attack_move:bool = false):
    let mm = order_milli(m)
    let x = int(mm.x)
    let y = int(mm.y)
    if x < 0 or y < 0 or x >= W * TILE or y >= H * TILE: return
    let q = if gl.button("left shift") >= 1 or pad_lb_held: 1 else: 0  // (shift, or LB held on a pad: queued)
    let rallying = b_index_of(sel_building)
    if rallying >= 0 and b_owner[rallying] == ME and not selected.length:
        issue_cmd(ME, CMD_RALLY, []::int, sel_building, x, y, 0)
        return
    let all = selected_units()
    if not all.length: return
    say(ME, "ack")
    let herd = filter(all) id: is_animal(index_of(id))
    let ids = filter(all) id: not is_animal(index_of(id))
    let workers = selected_workers()
    let c = cell_of(x, y)
    let b = building_at(mm)
    let foe = unit_at_screen(m, false)
    let mine = unit_at_screen(m, true)
    if herd.length:
        if b >= 0 and b_owner[b] == ME and b_done[b] == 1 and is_pen(b): issue_cmd(ME, CMD_PEN, herd, b_id[b], 0, 0, 0)
        else: issue_cmd(ME, CMD_MOVE, herd, x, y, 0, 0, q)  // (our sheep only ever walk)
    if not ids.length: return
    let others = filter(ids) id: not contains(workers, id)
    let bridge = bridge_on(c)
    let am = attack_move or gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1  // (Ctrl: attack-move; A is the camera's)
    if am and bridge >= 0 and br_up[bridge] == 1 and foe < 0:
        issue_cmd(ME, CMD_ATTACK, ids, br_id[bridge], 0, 0, 0, q)  // attack-click a bridge: break it
    elif am:
        issue_cmd(ME, CMD_ATTACK_MOVE, ids, x, y, 0, 0, q)
    elif foe >= 0:
        issue_cmd(ME, CMD_ATTACK, ids, u_id[foe], 0, 0, 0, q)  // a foe, or an animal to hunt
    elif mine >= 0 and u_owner[mine] == ME and is_animal(mine) and workers.length:
        issue_cmd(ME, CMD_ATTACK, ids, u_id[mine], 0, 0, 0, q)  // slaughter one of our sheep for its food
    elif b >= 0 and is_enemy(b_owner[b], ME) and fog[ME][c] != 0:
        issue_cmd(ME, CMD_ATTACK, ids, b_id[b], 0, 0, 0, q)
    elif res_at(c) != 0 and workers.length:
        issue_cmd(ME, CMD_GATHER, workers, c, 0, 0, 0, q)
        if others.length: issue_cmd(ME, CMD_MOVE, others, x, y, 0, 0, q)
    elif bridge >= 0 and br_up[bridge] == 0 and workers.length:
        issue_cmd(ME, CMD_HELP_BUILD, ids, br_id[bridge], 0, 0, 0, q)  // rebuild a broken bridge
    elif mine >= 0 and workers.length and can_mend(ME, u_id[mine]):
        issue_cmd(ME, CMD_REPAIR, ids, u_id[mine], 0, 0, 0, q)  // mend our siege engine
    elif b < 0 and workers.length and rubble.get(c) and rubble.get(c, []::int)[1] == ME and not build_barred(ME, rubble.get(c, []::int)[2]):
        let r = rubble.get(c, []::int)  // wall up our breach again
        issue_cmd(ME, CMD_BUILD, ids, r[2], r[3], r[4], r[5], q)
    elif b >= 0 and workers.length and can_mend(ME, b_id[b]):
        issue_cmd(ME, CMD_REPAIR, ids, b_id[b], 0, 0, 0, q)  // mend our damaged building
    elif b >= 0 and places(c) > 0 and teams[b_owner[b]] == teams[ME] and not workers.length:
        issue_cmd(ME, CMD_MOVE, ids, x, y, 0, 0, q)  // up onto our wall
    elif b >= 0 and b_owner[b] == ME and b_done[b] == 0:
        issue_cmd(ME, CMD_HELP_BUILD, ids, b_id[b], 0, 0, 0, q)
    elif b >= 0 and is_market(b) and not is_enemy(b_owner[b], ME) and (filter(ids) id: t_trader[u_kind[index_of(id)]] != 0).length:
        issue_cmd(ME, CMD_ROUTE, ids, b_id[b], 0, 0, 0)  // trade carts: trade with that market
    elif b >= 0 and b_owner[b] == ME and b_done[b] == 1 and (filter(ids) id: takes_in(b, index_of(id))).length:
        issue_cmd(ME, CMD_DROP_OFF, ids, b_id[b], 0, 0, 0, q)  // take what they carry in
    elif b >= 0 and pool[c] >= 0 and b_owner[b] == ME:
        issue_cmd(ME, CMD_RESEED, ids, b_id[b], 0, 0, 0)  // a fallow farm of ours
    elif b >= 0 and b_owner[b] == ME and room(b) > 0 and (filter(ids) id: can_hold(b, index_of(id))).length:
        issue_cmd(ME, CMD_GARRISON, ids, b_id[b], 0, 0, 0, q)  // inside our Town Center or tower
    else:
        issue_cmd(ME, CMD_MOVE, ids, x, y, 0, 0, q)

// What player 0 may build clock_s: (type) in menu order.
def buildable() -> [int]:
    let out = []::int
    for(bt_name) name, k:
        if not build_barred(ME, k) and not bt_special[k] and name != "wonder": out.push(k)
    return out

def trainable(b:int) -> [int]:
    return bm_trains[ME][b_kind[b]]

let RESEARCH_KEYS = [ "q", "e", "r", "t", "y", "f", "g", "h", "j" ]  // (not W A S D: the camera's)

// The research building b offers player 0 now (not done, not queued, open to its race, its age and
// the one before it reached; affordable or not), in research order.
def offered(b:int) -> [int]:
    let out = []::int
    for(research) item, r:
        if item.building == b_kind[b] and researched[ME][r] == 0 and (item.after < 0 or researched[ME][item.after] != 0) and
            item.line_has[ME] and (item.before[ME] < 0 or researched[ME][item.before[ME]] != 0) and ages[ME] >= item.age and
            item.open[ME] and not tech_queued(ME, r): out.push(r)
    return out

def research_name(r:int) -> string: return research_names.get(r, research[r].id)

def place_at() -> int, int:
    let mm = mouse_milli()
    let s = bt_size[placing]
    return int(mm.x) / TILE - (s - 1) / 2, int(mm.y) / TILE - (s - 1) / 2

def place_cell() -> int2:
    let cx, cy = place_at()
    return int2 { cx, cy }

// Lay the foundation being placed at the mouse with the selected workers (shift: keep placing).
def place_here(more:bool):
    let cx, cy = place_at()
    let ws = selected_workers()
    if ws.length: issue_cmd(ME, CMD_BUILD, ws, placing, cx, cy, 0, if more: 1 else: 0)
    if not more: placing = -1

// The cells of a line from a to b (straight or diagonal: the cells a line through them crosses).
def wall_cells(a:int2, b:int2) -> [int2]:
    let out = []::int2
    let n = max(abs(b.x - a.x), abs(b.y - a.y))
    for(n + 1) k:
        let c = int2 { a.x + int(round(float((b.x - a.x) * k) / float(max(n, 1)))), a.y + int(round(float((b.y - a.y) * k) / float(max(n, 1)))) }
        if not out.length or out[out.length - 1] != c: out.push(c)
    return out

// A wall or gate dragged from a to b: a foundation a cell, built in order by the selected workers (more: keep placing).
def place_wall(a:int2, b:int2, more:bool):
    let ws = selected_workers()
    if ws.length:
        for(wall_cells(a, b)) c, k: issue_cmd(ME, CMD_BUILD, ws, placing, c.x, c.y, 0, if more or k > 0: 1 else: 0)
    wall_from = int2 { -1, -1 }
    if not more: placing = -1

def shift_held(): return gl.button("left shift") >= 1 or gl.button("right shift") >= 1

// Train the building's nth unit (shift: five, as far as the money and the queue go).
def train_slot(n:int):
    let b = b_index_of(sel_building)
    if b >= 0 and b_owner[b] == ME:
        let tr = trainable(b)
        if n < tr.length:
            for(if shift_held(): 5 else: 1): issue_cmd(ME, CMD_TRAIN, []::int, sel_building, tr[n], 1, 0)

def store_group(n:int): groups.set(n, selected_units())

def recall_group(n:int):
    let ids = filter(groups.get(n, [])) id: index_of(id) >= 0
    if not ids.length: return
    selected = ids
    sel_building = 0
    if last_group == n and gl.time() - last_group_at < 0.4:
        let i = index_of(ids[0])
        cam = iso(float(u_x[i]), float(u_y[i]))
    last_group = n
    last_group_at = gl.time()

def keys():
    if gl.button("m") == 1: sound_on = not sound_on
    if gl.button("n") == 1 and not in_net_match:  // a new race, mid-match
        typing_text = true
        gl.start_text_input(int2 { 0, 0 }, int2 { 400, 40 })
        gl.set_text_input("")
        return
    let digit = map(9) n: gl.button("{n + 1}") == 1
    // Control groups (sim_debug._control_group): Ctrl (or Cmd) + a number keeps the selected units;
    // the number brings them back (when no building's panel takes it), twice quickly to look at them.
    let ctrl = gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1 or gl.button("left gui") >= 1 or gl.button("right gui") >= 1
    for(digit) hit, n:
        if hit and ctrl:
            store_group(n)
            return
        let shown = b_index_of(sel_building)
        if hit and not build_menu and (shown < 0 or b_owner[shown] != ME):
            recall_group(n)
            return
    if gl.button("b") == 1 and selected_workers().length: build_menu = not build_menu
    if build_menu:
        let menu = buildable()
        for(digit) hit, n:
            if hit and n < menu.length:
                placing = menu[n]
                build_menu = false
        return
    let b = b_index_of(sel_building)
    if b >= 0 and b_owner[b] == ME:
        for(digit) hit, n:
            if hit: train_slot(n)
        if gl.button("u") == 1: issue_cmd(ME, CMD_AGE_UP, []::int, sel_building, 0, 0, 0)
        let offer = offered(b)
        for(RESEARCH_KEYS) key, n:
            if gl.button(key) == 1 and n < offer.length: issue_cmd(ME, CMD_RESEARCH, []::int, sel_building, offer[n], 0, 0)
        if gl.button("x") == 1 and b_queue[b].length: issue_cmd(ME, CMD_CANCEL, []::int, sel_building, b_queue[b].length - 1, 0, 0)
    if gl.button("x") == 1 and b < 0 and selected.length: issue_cmd(ME, CMD_STOP, selected_units(), 0, 0, 0, 0)
    if b < 0 and selected_soldiers().length:
        if gl.button("r") == 1: arming_attack = true  // R then click: attack-move there
        let hk = ability_hotkey()
        if hk != "" and gl.button(hk) == 1 and ability_users().length: arming_ability = true

// The selected units that fight (not workers, not animals).
def selected_soldiers() -> [int]: return filter(selected_units()) id: t_worker[u_kind[index_of(id)]] == 0 and t_animal[u_kind[index_of(id)]] == 0

// Our race's ability (data: its name, desc, hotkey...), or nil; and the selected units that may use it.
def my_ability() -> JV?:
    let ab = get(su_sides[ME], "ability")
    return if ab and ab.kind == J_OBJ and gstr(ab, "kind", "") != "": ab else: nil
def ability_hotkey() -> string:
    let ab = my_ability()
    return if ab: gstr(ab, "hotkey", "").lowercase() else: ""
def ability_users() -> [int]: return filter(selected_units()) id: t_ability[u_kind[index_of(id)]] != 0

def mouse():
    let m = mouse_px()
    if arming_attack or arming_ability:  // the armed order goes where the next left click is
        if gl.button("mouse1") == 1:
            give_armed(m)
            return
        if gl.button("mouse3") == 1 or gl.button("escape") == 1:
            arming_attack = false
            arming_ability = false
            return
    if placing < 0: wall_from = int2 { -1, -1 }
    if placing >= 0:
        if touch_play: return      // (touch places for itself: game/touch.lobster)
        if bt_line[placing] != 0:  // walls and gates are dragged: press at one end, release at the other
            if gl.button("mouse1") == 1: wall_from = place_cell()
            elif gl.button("mouse1") == 0 and wall_from.x >= 0: place_wall(wall_from, place_cell(), gl.button("left shift") >= 1)
        elif gl.button("mouse1") == 1: place_here(gl.button("left shift") >= 1)
        if gl.button("mouse3") == 1 or gl.button("escape") == 1: placing = -1
        return
    if in_minimap(m):
        if gl.button("mouse1") >= 1: cam = (m - mm_top()) / mm_scale()  // look there
        if gl.button("mouse3") == 1:
            let p = iso_inv((m - mm_top()) / mm_scale())
            let ids = selected_units()
            if ids.length:
                say(ME, "ack")
                issue_cmd(ME, if gl.button("left ctrl") >= 1 or gl.button("right ctrl") >= 1: CMD_ATTACK_MOVE else: CMD_MOVE, ids, int(p.x), int(p.y), 0, 0, if gl.button("left shift") >= 1: 1 else: 0)
        return
    if gl.button("mouse1") == 1 and not touch_play:  // (touch selects for itself; a touch here is on the HUD)
        drag_from = m
        dragging = true
    if dragging and gl.button("mouse1") == 0:
        dragging = false
        if magnitude(m - drag_from) < 6.0: click_select(m)
        else: box_select(drag_from, m)
    if gl.button("mouse3") == 1: order(m)

def scroll():
    let ws = float(gl.window_size())
    let m = mouse_px()
    let sp = 1400.0 * gl.delta_time() / zoom
    var d = float2_0
    if gl.button("left") >= 1 or gl.button("a") >= 1: d.x -= 1.0  // (the arrows or WASD)
    if gl.button("right") >= 1 or gl.button("d") >= 1: d.x += 1.0
    if gl.button("up") >= 1 or gl.button("w") >= 1: d.y -= 1.0
    if gl.button("down") >= 1 or gl.button("s") >= 1: d.y += 1.0
    let inside = m.x > 0.0 and m.y > 0.0 and m.x < ws.x and m.y < ws.y   // (outside the window the mouse reads 0, 0)
    if inside and shot == "" and rec_dir == "" and gl.window_focused():  // (the mouse is free now: not while it works in another app)
        if m.x <= 3.0: d.x -= 1.0
        if m.y <= 3.0: d.y -= 1.0
        if m.x >= ws.x - 4.0: d.x += 1.0
        if m.y >= ws.y - 4.0: d.y += 1.0
    cam += d * sp
    let wheel = gl.mousewheel_delta()
    if wheel > 0: zoom = min(8.0, zoom + 1.0)
    if wheel < 0: zoom = max(1.0, zoom - 1.0)

// ------------------------------------------------------------------ marks and the HUD

// An ellipse on the ground (2:1) round p, about 1.6 px thick at any size: line segments through the UI layer's
// meshes (gl.open_circle goes astray after the sprites' shader, as gl.rect and gl.line do in this build).
def draw_ring(p:float2, r:float, col:float4):
    let n = 48
    ui_batch():
        for(n) k:
            let a0 = 360.0 * float(k) / float(n)
            let a1 = 360.0 * float(k + 1) / float(n)
            ui_line(p + float2 { cos(a0) * r, sin(a0) * r * 0.5 }, p + float2 { cos(a1) * r, sin(a1) * r * 0.5 }, 1.6, col)

// A shot's key in shot_from and shot_mouth, at its place in shots. (Two guns can fire together.)
def shot_key(o:int) -> int: return (shots[o + SHOT_BY] * 65536 + shots[o + SHOT_LAND] % 65536) * 8 + shots[o + SHOT_MOUNT]

// Forget the landed shots. One still flying keeps its start: forgotten, it would fire again and start over (#265).
def forget_landed_shots():
    let was_from, was_mouth = shot_from, shot_mouth
    shot_from = dictionary<int, int>(1024)
    shot_mouth = dictionary<int, float2>(1024)
    for(shots.length / SHOT_STRIDE) k:
        let key = shot_key(k * SHOT_STRIDE)
        if was_from.get(key, -1) >= 0:
            shot_from.set(key, was_from.get(key, -1))
            shot_mouth.set(key, was_mouth.get(key, float2 { 0.0, -12.0 }))

// Shots in flight (shots.gd, combat_fx.gd): each weapon's shot on its arc from the shooter's body to
// where it lands, for the sim's flight, with a speck of shadow under it. Canvas units (under the 1.5 scale).
def draw_shots(alpha:float):
    gl.set_shader("color")
    let n = shots.length / SHOT_STRIDE
    for(n) k:
        let o = k * SHOT_STRIDE
        let land = shots[o + SHOT_LAND]
        let mount = shots[o + SHOT_MOUNT]
        let key = shot_key(o)
        var t_from = shot_from.get(key, -1)
        let firstseen = t_from < 0
        if firstseen:
            t_from = tick - 1
            shot_from.set(key, t_from)
            shot_mouth.set(key, muzzle_of(shots[o + SHOT_BY], mount))
        let flight = float(max(1, land - t_from)) / 20.0
        let ax = shots[o + SHOT_X]
        let ay = shots[o + SHOT_Y]
        let sx = shots[o + SHOT_X0]
        let sy = shots[o + SHOT_Y0]
        if seen_at(ax, ay) or seen_at(sx, sy):
            let src = shots[o + SHOT_SRC]
            let own = if src >= 0 and mount < t_mounts[src].length: t_mounts[src][mount].shot else: ""
            let st = shot_style(if own != "": own elif src >= 0: unit_shotk.get(src, "arrow") else: "arrow")
            let t = shot_drawn_u((float(tick - t_from) + alpha) / 20.0, flight, st.muzzle.flash > 0.0)
            let a = ground_at(sx, sy) + shot_mouth.get(key, float2 { 0.0, -12.0 })
            let to_j = index_of(shots[o + SHOT_TO])
            let b = ground_at(ax, ay) - float2 { 0.0, 10.0 + (if to_j >= 0: air_lift(u_kind[to_j]) / 1.5 else: 0.0) }
            if firstseen and seen_at(sx, sy):  // (a gun firing out of the fog shows only its shell)
                fx_muzzle(st, a, ground_at(sx, sy))
                if st.muzzle.recoil > 0.0: unit_kick.set(shots[o + SHOT_BY] * 16 + mount, float2 { st.muzzle.recoil, clock_s })
            if st.plain():
                if t >= 0.0: draw_bolt(st, a, b, t, 1.0)  // (launched late: it looks faster, and lands on the sim's tick)
            elif firstseen: fx_fire(st, a, b, float(land - t_from) / 20.0, if src >= 0: unit_shot.get(src, "") else: "")
    draw_tracers()
    if tick % 200 == 0: forget_landed_shots()

// Health bars over hurt units you can see, and over the selected.
def draw_bars(alpha:float):
    for(u_x.length) i:
        let k = u_kind[i]
        if u_hp[i] < t_hp[k] and (teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i]))):
            let px, py = prev_pos(i)
            let p = iso(px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha)
            let hpk = float(u_hp[i]) / float(max(1, t_hp[k]))
            ui_fill(p + float2 { -9.0, -38.0 - air_lift(k) }, float2 { 18.0, 3.0 }, float4 { 0.0, 0.0, 0.0, 0.6 })
            ui_fill(p + float2 { -9.0, -38.0 - air_lift(k) }, float2 { 18.0 * hpk, 3.0 }, float4 { 1.0 - hpk, 0.3 + 0.6 * hpk, 0.15, 1.0 })

def ring_of(owner:int) -> float4: return if is_foe(owner, ME): float4 { 0.9, 0.22, 0.16, 1.0 } else: float4 { 0.95, 0.91, 0.79, 1.0 }

// The selection rings, on the ground under the selected units and building (drawn in the sorted world, before
// anything standing: a unit stands in its ring, and what's in front of it covers it).
// Rings on raised ground (raised) are drawn after the hill's tops, which would paint over them.
def draw_rings(alpha:float, raised:bool):
    gl.set_shader("color")
    def ring(m:float2, r:float, col:float4):
        if (lift_at(m.x, m.y) > 0.0) == raised: draw_ring(on_ground(m), r, col)
    for(selected_units()) id:
        let i = index_of(id)
        let px, py = prev_pos(i)
        ring(float2 { px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha }, float(u_radius[i]) * 0.068 + 3.0, float4 { 0.95, 0.91, 0.79, 1.0 })
    let f = index_of(sel_foreign)
    if f >= 0:
        let px, py = prev_pos(f)
        ring(float2 { px + (u_x[f] - px) * alpha, py + (u_y[f] - py) * alpha }, float(u_radius[f]) * 0.068 + 3.0, ring_of(u_owner[f]))
    let b = b_index_of(sel_building)
    if b >= 0:
        ring(float2 { float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500) }, float(b_sx[b]) * 68.0 * 0.75, ring_of(b_owner[b]))

def draw_marks(alpha:float):
    gl.set_shader("color")
    if not rec_clean: draw_bars(alpha)
    for(selected_units()) id:
        let i = index_of(id)
        let px, py = prev_pos(i)
        let p = iso(px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha)
        let hpk = float(u_hp[i]) / float(max(1, t_hp[u_kind[i]]))
        ui_fill(p + float2 { -9.0, -38.0 }, float2 { 18.0, 3.0 }, float4 { 0.0, 0.0, 0.0, 0.6 })
        ui_fill(p + float2 { -9.0, -38.0 }, float2 { 18.0 * hpk, 3.0 }, float4 { 1.0 - hpk, 0.3 + 0.6 * hpk, 0.15, 1.0 })
    if placing >= 0:
        let here = place_cell()
        let s = bt_size[placing]
        for(if bt_line[placing] != 0 and wall_from.x >= 0: wall_cells(wall_from, here) else: [ here ]) g:
            let ok = can_place(ME, placing, g.x, g.y)
            let pts = map([ int2 { 0, 0 }, int2 { s, 0 }, int2 { s, s }, int2 { 0, s } ]) d: iso(float((g.x + d.x) * 1000), float((g.y + d.y) * 1000))
            gl.color(if ok: float4 { 0.3, 0.9, 0.3, 0.35 } else: float4 { 0.9, 0.2, 0.2, 0.35 }):
                gl.polygon(pts)

// ------------------------------------------------------------------ the minimap (src/view/minimap.gd)
// The map as a diamond at the bottom right (MM_SIZE UI px wide, half as tall, times hud_s()): the ground
// mesh again, small, in a frame of the look's metal (lit on its upper edges, in shade below, a stud at each
// point); your buildings as squares and units as dots in team colours (enemies only where you see them,
// animals pale); the camera's view outlined. A click there looks there (only the diamond takes it).

let MM_SIZE = 300.0  // its width in UI px (minimap.gd's SIZE)
let MM_RIM = 12.0    // the frame round the diamond

// The art's density (#358): on a screen where the default view draws a world art px over more than 2 device px (a
// Retina Mac), units, buildings and props bake at that many texture px a world px (2.4 at most), so a baked pixel is
// a device pixel (a voxel unit's voxel exactly: a body unit is 1.1 world px). Other screens keep the base, 2.
def art_density(zoom0:float):
    if zoom0 <= 2.0: return
    let z = min(zoom0, 2.4)  // (at most a Retina Mac's: a 5K screen's 4 would bake 3 times today's pixels)
    ART_SCALE = ART_BASE * z
    ART_K = z
    WB_ART = ART_SCALE
    WB_PX = 32.0 / 0.70710678 * WB_ART
    FX_ART_PX = ART_SCALE
    vx_set_res(1.1 * z)
    VX_DRAW_K = 1.1 / vx_RES
    VX_ATLAS = 4096

// Screen px per canvas unit: the diamond (48 (W + H) canvas units wide) MM_SIZE wide.
def mm_scale() -> float: return MM_SIZE * hud_s() / (48.0 * float(W + H))

// Its box's top left: the panel's margin and the frame from the window's bottom right (sim_debug: offset
// -SIZE - 24, -SIZE / 2 - 20).
def mm_box() -> float2:
    let ws = float(gl.window_size())
    let s = hud_s()
    return float2 { ws.x - (MM_SIZE + 24.0) * s, ws.y - (MM_SIZE * 0.5 + 20.0) * s }

// The map's (0, 0) corner, the diamond's top point, on the screen.
def mm_top() -> float2: return mm_box() + float2 { 48.0 * float(H) * mm_scale(), 0.0 }

def mm_point(p:float2) -> float2: return mm_top() + p * mm_scale()

def in_minimap(m:float2) -> bool:
    let s = hud_s()
    let c = mm_box() + float2 { MM_SIZE * 0.5, MM_SIZE * 0.25 } * s
    return abs(m.x - c.x) / (MM_SIZE * 0.5 * s) + abs(m.y - c.y) / (MM_SIZE * 0.25 * s) <= 1.0

def mm_poly(pts:[float2], cols:[float4]):
    ui_batch_flush()
    gl.set_shader("color_attr")
    gl.draw_mesh("PC", map(pts) p: float3 { p.x, p.y, 0.0 }, cols, []::float3, []::float2, []::float2,
                 if pts.length == 4: [ 0, 1, 2, 0, 2, 3 ] else: [ 0, 1, 2 ])
    gl.set_shader("color")

// The diamond's frame (minimap.gd's _draw_frame).
def mm_frame():
    let s = hud_s()
    let b = mm_box()
    let size = MM_SIZE * s
    let rim = MM_RIM * s
    let c = b + float2 { size * 0.5, size * 0.25 }
    let o = [ float2 { c.x, b.y - rim * 0.6 }, float2 { b.x + size + rim, c.y }, float2 { c.x, b.y + size * 0.5 + rim * 0.6 }, float2 { b.x - rim, c.y } ]
    let i = [ float2 { c.x, b.y - 1.0 }, float2 { b.x + size + 1.5, c.y }, float2 { c.x, b.y + size * 0.5 + 1.0 }, float2 { b.x - 1.5, c.y } ]
    mm_poly(map(o) p: p + float2 { 3.0, 6.0 } * s, map(4): float4 { 0.0, 0.0, 0.0, 0.4 })
    // the frame's material, painted by the UI's shader on the diamond
    ui_batch_flush()
    gl.set_shader("uimat")
    gl.set_uniform("mcol", ui_look.frame)
    gl.set_uniform("kind", 1.0)
    gl.set_uniform("win_h", float(gl.window_size().y))
    gl.set_uniform("px", max(1.0, ui()))
    gl.draw_mesh("P", map(o) p: float3 { p.x, p.y, 0.0 }, []::float4, []::float3, []::float2, []::float2, [ 0, 1, 2, 0, 2, 3 ])
    gl.set_shader("color")
    let light = [ float4 { 1.0, 0.95, 0.85, 0.3 }, float4 { 0.0, 0.0, 0.0, 0.35 }, float4 { 0.0, 0.0, 0.0, 0.5 }, float4 { 1.0, 0.95, 0.85, 0.15 } ]
    for(4) k:
        let l = light[k]
        let none = float4 { l.x, l.y, l.z, 0.0 }
        mm_poly([ o[k], o[(k + 1) % 4], i[(k + 1) % 4], i[k] ], [ l, l, none, none ])
    mm_poly(i, map(4): float4 { 0.07, 0.05, 0.03, 1.0 })
    for(4) k:
        ui_line(o[k], o[(k + 1) % 4], 1.5, float4 { 0.0, 0.0, 0.0, 0.75 })
        ui_line(i[k], i[(k + 1) % 4], 1.5, float4 { 0.0, 0.0, 0.0, 0.7 })

def mm_studs():
    let s = hud_s()
    let b = mm_box()
    let size = MM_SIZE * s
    let rim = MM_RIM * s
    let c = b + float2 { size * 0.5, size * 0.25 }
    for([ float2 { c.x, b.y - rim * 0.6 }, float2 { b.x + size + rim, c.y }, float2 { c.x, b.y + size * 0.5 + rim * 0.6 }, float2 { b.x - rim, c.y } ]) p:
        ui_stud(p, 4.8 * s, ui_look.metal)

def draw_minimap():
    let gm = ground_mesh
    if not gm: return
    let s = hud_s()
    mm_frame()
    ui_batch_flush()
    gl.translate(mm_top()):
        gl.scale(mm_scale()):
            gl.set_shader("color_attr")
            gl.render_mesh(gm)
    gl.set_shader("color")
    let per_tile = MM_SIZE * s / float(W + H) * 2.0  // a tile's width on it
    for(b_id.length) b:
        let cell = b_cy[b] * W + b_cx[b]
        if teams[b_owner[b]] == teams[ME] or fog[ME][cell] != 0:
            let p = mm_point(iso(float(b_cx[b] * 1000 + b_sx[b] * 500), float(b_cy[b] * 1000 + b_sy[b] * 500)))
            let r = max(3.0 * s, float(max(b_sx[b], b_sy[b])) * per_tile * 0.45)
            ui_fill(p - float2 { r, r * 0.6 }, float2 { r * 2.0, r * 1.2 }, team_col(b_owner[b]))
    for(u_x.length) i:
        if teams[u_owner[i]] == teams[ME] or visible_to_me(cell_of(u_x[i], u_y[i])):
            let p = mm_point(iso(float(u_x[i]), float(u_y[i])))
            let tc = team_col(u_owner[i])
            let dot = if u_owner[i] == gaia or t_animal[u_kind[i]] != 0: float4 { 0.85, 0.82, 0.72, 1.0 } else: float4 { tc.x + (1.0 - tc.x) * 0.2, tc.y + (1.0 - tc.y) * 0.2, tc.z + (1.0 - tc.z) * 0.2, 1.0 }
            ui_fill(p - float2_1 * s, float2_1 * 2.0 * s, dot)
    let ws = float(gl.window_size())
    let corners = map([ float2_0, float2 { ws.x, 0.0 }, ws, float2 { 0.0, ws.y } ]) c: mm_point(from_screen(c))
    for(4) k: ui_line(corners[k], corners[(k + 1) % 4], 2.0 * s, float4 { 1.0, 1.0, 1.0, 0.9 })
    mm_studs()

def text_at(p:float2, s:string):
    gl.translate(p): gl.text(s)

def stock_text() -> string:
    var s = ""
    for(resource_names) r, k:
        s += "{r} {stock[k][ME]}   "
    return s + "pop {pop[ME]}/{pop_cap[ME]}   age {ages[ME]}"

def unit_name(k:int) -> string: return unit_names.get(k, t_slot[k])
def bname(k:int) -> string: return building_names.get(k, bt_name[k])

var end_watching = false  // the end screen put away (Keep watching)
def end_screen_up() -> bool: return winner >= 0 and not end_watching and not menu_open

def draw_hud(paused:bool, speed:float):
    gl.set_shader("color")
    let ws = float(gl.window_size())
    let u = ui()
    ui_batch(): draw_topbar(speed, paused)  // (game/topbar.lobster; its fills in as few draws as can be)
    gl.set_shader("color")                  // (placing: the panel's info line says how)
    if winner >= 0 and end_watching:        // (the end screen put away: the result stays up while you watch)
        gl.set_font_size(int(48.0 * u))
        gl.color(float4 { 1.0, 0.85, 0.3, 1.0 }):
            text_at(ws / 2.0 - float2 { 160.0, 40.0 }, if winner == teams[ME]: "Victory!" else: "Defeat")
    ui_batch(): draw_minimap()
    if dragging:
        let m = mouse_px()
        let lo = float2 { min(m.x, drag_from.x), min(m.y, drag_from.y) }
        let hi = float2 { max(m.x, drag_from.x), max(m.y, drag_from.y) }
        gl.color(float4 { 0.95, 0.91, 0.79, 0.8 }):
            for([ [ lo, float2 { hi.x, lo.y } ], [ float2 { hi.x, lo.y }, hi ], [ hi, float2 { lo.x, hi.y } ], [ float2 { lo.x, hi.y }, lo ] ]) e:
                ui_line(e[0], e[1], 1.5, float4 { 0.95, 0.91, 0.79, 0.8 })
