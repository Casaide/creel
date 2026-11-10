// ------------------------------------------------------------------ a selected unit's orders, in the world (src/view/order_marks.gd)
// What it's doing now, then each shift-queued order in turn, joined by a dashed route from the unit; later legs
// fade. A move ends in a ring and a little flag, an attack-move the same in red, a build or drop-off outlines its
// building, a gather its tile, an attack rings its target in red. A unit in a fight gets a thin red line
// to the foe. A crowd heading for one spot shares one first leg from its middle. A selected building shows
// its rally flag. View only: it reads the sim. Spots and legs are in sim coordinates, put on the ground (relief) as they're drawn: a leg runs over a hill, a flag stands on it.

let OM_RING = float4 { 0.95, 0.91, 0.79, 1.0 }  // #f2e9c9
let OM_FOE = float4 { 0.89, 0.40, 0.29, 1.0 }   // #e2654a
let OM_EDGE = float4 { 0.0, 0.0, 0.0, 0.5 }
let OM_FADE_STEP = 0.16
let OM_FADE_MIN = 0.4
let OM_GROUP_LEGS = 3

// A spot on a route: kind 0 move, 1 attack-move, 2 build, 3 gather, 4 drop-off, 5 attack, 6 a planned building.
class OmSpot:
    kind:int
    at:float2  // (milli-tiles)
    order:int
    cx:int = 0  // a footprint's top cell and size (build, gather, drop, plan); unit >= 0 for a unit target
    cy:int = 0
    sx:int = 0
    sy:int = 0
    unit:int = -1

def om_fade(order:int) -> float: return max(OM_FADE_MIN, 1.0 - OM_FADE_STEP * float(order))

def om_unit_at(i:int, alpha:float) -> float2:
    let px, py = prev_pos(i)
    return float2 { px + (u_x[i] - px) * alpha, py + (u_y[i] - py) * alpha }

def om_foot(kind:int, cx:int, cy:int, sx:int, sy:int, order:int) -> OmSpot:
    return OmSpot { kind: kind, at: float2 { float(cx * TILE + sx * TILE / 2), float(cy * TILE + sy * TILE / 2) }, order: order, cx: cx, cy: cy, sx: sx, sy: sy }

// A spot on a unit or a building by id (a building only where you've seen it, a unit only where you see it); nil if gone.
def om_on(kind:int, id:int, order:int, alpha:float) -> OmSpot?:
    let b = b_index_of(id)
    if b >= 0:
        if b_owner[b] != ME and fog[ME][cell_of(b_cx[b] * TILE, b_cy[b] * TILE)] == 0: return nil
        return om_foot(kind, b_cx[b], b_cy[b], b_sx[b], b_sy[b], order)
    let j = index_of(id)
    if j < 0 or (teams[u_owner[j]] != teams[ME] and not visible_to_me(cell_of(u_x[j], u_y[j]))): return nil
    let s = OmSpot { kind, om_unit_at(j, alpha), order }
    s.unit = j
    return s

def om_cell(kind:int, cell:int, order:int) -> OmSpot: return om_foot(kind, cell % W, cell / W, 1, 1, order)

def om_point(kind:int, x:int, y:int, order:int) -> OmSpot: return OmSpot { kind, float2 { float(x), float(y) }, order }

// A unit's orders, now and queued (OrderMarks.route).
def om_route(i:int, alpha:float) -> [OmSpot]:
    let out = []::OmSpot
    def add(s:OmSpot?):
        if s: out.push(s)
    if u_stance[i] == ATTACK_MOVE:
        if u_foe[i] != 0: add(om_on(5, u_foe[i], 0, alpha))
        out.push(om_point(1, u_amx[i], u_amy[i], 0))
    elif u_foe[i] != 0 and u_stance[i] == ORDERED: add(om_on(5, u_foe[i], 0, alpha))
    elif u_task[i] == BUILD: add(om_on(2, u_target[i], 0, alpha))
    elif u_task[i] == GATHER: out.push(om_cell(3, u_target[i], 0))
    elif u_task[i] == T_RETURN:
        add(om_on(4, u_target[i], 0, alpha))
        if u_home[i] >= 0: out.push(om_cell(3, u_home[i], 0))
    elif u_moving[i] == 1: out.push(om_point(0, u_tx[i], u_ty[i], 0))
    for(u_orders[i]) c:
        switch c.code:
            case CMD_MOVE, CMD_ATTACK_MOVE:
                let x, y = order_point(c)
                out.push(om_point(if c.code == CMD_MOVE: 0 else: 1, x, y, 0))
            case CMD_GATHER: out.push(om_cell(3, c.a, 0))
            case CMD_HELP_BUILD, CMD_REPAIR: add(om_on(2, c.a, 0, alpha))
            case CMD_BUILD:
                let t = build_type(ME, c.a)
                out.push(om_foot(6, c.b, c.c, bt_size[t], bt_size[t], 0))
            case CMD_ATTACK: add(om_on(5, c.a, 0, alpha))
            case CMD_DROP_OFF, CMD_GARRISON: add(om_on(4, c.a, 0, alpha))
            default: pass()
    for(out) s, n: s.order = n
    return out

// A leg's end at a footprint stops at its edge (not across the foundation or the reeds).
def om_edge(s:OmSpot, toward:float2) -> float2:
    if s.sx == 0 or s.unit >= 0: return s.at
    let v = toward - s.at
    let k = max(abs(v.x), abs(v.y)) / (float(TILE * max(s.sx, s.sy)) / 2.0)
    return if k > 1.0: s.at + v / k else: toward

// Dashes along a path's runs, the pattern running on round its bends.
def om_dashed(runs:[[float2]], w:float, col:float4, dash:float):
    var left = dash
    var on = true
    for(runs) path:
        for(path.length - 1) n:
            let a = path[n]
            let l = magnitude(path[n + 1] - a)
            if l >= 0.01:
                let d = (path[n + 1] - a) / l
                var t = 0.0
                while t < l:
                    let piece = min(left, l - t)
                    if on: ui_line(a + d * t, a + d * (t + piece), w, col)
                    t += piece
                    left -= piece
                    if left <= 0.0:
                        left = dash
                        on = not on

def om_solid(runs:[[float2]], w:float, col:float4):
    for(runs) path:
        for(path.length - 1) n: ui_line(path[n], path[n + 1], w, col)

def om_ellipse(at:float2, r:float, col:float4, px:float):
    let n = 24
    for(n) k:
        let a0 = 360.0 * float(k) / float(n)
        let a1 = 360.0 * float(k + 1) / float(n)
        let p0 = at + float2 { cos(a0) * r, sin(a0) * r * 0.5 }
        let p1 = at + float2 { cos(a1) * r, sin(a1) * r * 0.5 }
        ui_line(p0, p1, 3.5 * px, OM_EDGE * float4 { 1.0, 1.0, 1.0, col.w * 1.2 })
        ui_line(p0, p1, 2.0 * px, col)

def om_diamond(s:OmSpot, col:float4, px:float, fill:bool):
    let x0 = float(s.cx * TILE)
    let y0 = float(s.cy * TILE)
    let x1 = float((s.cx + s.sx) * TILE)
    let y1 = float((s.cy + s.sy) * TILE)
    let pts = [ on_ground(float2 { x0, y0 }), on_ground(float2 { x1, y0 }), on_ground(float2 { x1, y1 }), on_ground(float2 { x0, y1 }) ]
    if fill:
        ui_batch_flush()
        gl.color(col * float4 { 1.0, 1.0, 1.0, 0.14 }): gl.polygon(pts)
    for(4) k:
        ui_line(pts[k], pts[(k + 1) % 4], 3.5 * px, OM_EDGE * float4 { 1.0, 1.0, 1.0, col.w * 1.2 })
    for(4) k: ui_line(pts[k], pts[(k + 1) % 4], 2.0 * px, col)

// A little flag on its pole, in the team's colour, at a waypoint or a rally point.
def om_flag(at:float2, team:float4, a:float, px:float):
    let top = at - float2 { 0.0, 16.0 }
    ui_line(at, top, 2.5 * px, float4 { 0.2, 0.15, 0.1, a })
    ui_batch_flush()
    gl.color(float4 { 0.0, 0.0, 0.0, 0.5 * a }): gl.polygon([ top + float2 { 0.5, -0.5 }, top + float2 { 10.5, 3.0 }, top + float2 { 0.5, 6.5 } ])
    gl.color(float4 { team.x, team.y, team.z, a }): gl.polygon([ top, top + float2 { 10.0, 3.0 }, top + float2 { 0.0, 6.0 } ])

def om_spot(s:OmSpot, team:float4, px:float, alpha:float):
    let a = om_fade(s.order)
    let ringc = OM_RING * float4 { 1.0, 1.0, 1.0, a }
    let foe = OM_FOE * float4 { 1.0, 1.0, 1.0, a }
    switch s.kind:
        case 0, 1:
            om_ellipse(on_ground(s.at), 6.0, if s.kind == 1: foe else: ringc, px)
            om_flag(on_ground(s.at), team, a, px)
        case 5:
            if s.unit >= 0: om_ellipse(on_ground(om_unit_at(s.unit, alpha)), float(u_radius[s.unit]) * 0.068 + 2.0, foe, px)
            else: om_diamond(s, foe, px, false)
        case 3: om_diamond(s, ringc * float4 { 1.0, 1.0, 1.0, 0.8 }, px, true)
        default: om_diamond(s, ringc, px, false)

def draw_orders(alpha:float):
    gl.set_shader("color")
    let px = ui() / zoom  // (a UI pixel in the world's units)
    let team = team_col(ME)
    let legs = []::[float2]  // from, to
    let leg_order = []::int
    let leg_foe = []::bool
    let spots = []::OmSpot
    let seen = dictionary<string, int>(32)
    let firsts = dictionary<string, int>(16)  // a first spot -> its index in first_spots
    let first_spots = []::OmSpot
    let first_from = []::[float2]
    for(selected_units()) id:
        let i = index_of(id)
        if u_owner[i] != ME: continue
        let me = om_unit_at(i, alpha)
        var start = me
        let fighting = if u_stance[i] != NONE and u_stance[i] != RETURN: u_foe[i] else: 0
        if fighting != 0:
            let f = om_on(5, fighting, 0, alpha)
            if f:
                let fp = ground_path(me, f.at)
                om_solid(fp, 3.5 * px, OM_EDGE * float4 { 1.0, 1.0, 1.0, 0.9 })
                om_solid(fp, 1.5 * px, OM_FOE * float4 { 1.0, 1.0, 1.0, 0.85 })  // red to the foe (Dominic, 2026-11-04)
                spots.push(f)
        var prev:OmSpot? = nil
        for(om_route(i, alpha)) s:
            let foe = s.kind == 5 or s.kind == 1
            let key = "{s.kind}@{int(s.at.x)},{int(s.at.y)}"
            if s.order == 0 and s.kind == 5 and s.unit >= 0 and u_id[s.unit] == fighting:
                pass()  // (its fight line shows it; the route goes on from the unit)
            else:
                if s.order == 0:
                    var k = firsts.get(key, -1)
                    if k < 0:
                        k = first_spots.length
                        firsts.set(key, k)
                        first_spots.push(s)
                        first_from.push([])
                    first_from[k].push(start)
                else:
                    let lk = "{int(start.x)},{int(start.y)}>{key}"
                    if seen.get(lk, -1) < 0:
                        seen.set(lk, 1)
                        legs.push([ if prev: om_edge(prev, s.at) else: start, om_edge(s, start) ])
                        leg_order.push(s.order)
                        leg_foe.push(foe)
                if seen.get(key, -1) < 0:
                    seen.set(key, 1)
                    spots.push(s)
                start = s.at
                prev = s
    for(first_spots) s, k:  // a few units: a leg each; a crowd: one leg from its middle, not a sheaf
        var starts = first_from[k]
        if starts.length > OM_GROUP_LEGS:
            var mid = float2_0
            for(starts) p: mid += p / float(starts.length)
            starts = [ mid ]
        for(starts) p:
            legs.push([ p, om_edge(s, p) ])
            leg_order.push(0)
            leg_foe.push(s.kind == 5 or s.kind == 1)
    for(legs) l, k:
        let a = om_fade(leg_order[k]) * (if leg_order[k] == 0: 0.8 else: 0.95)
        let col = if leg_foe[k]: OM_FOE else: OM_RING
        let path = ground_path(l[0], l[1])
        om_dashed(path, 4.5 * px, OM_EDGE * float4 { 1.0, 1.0, 1.0, a }, 6.0 * px)
        om_dashed(path, 2.0 * px, col * float4 { 1.0, 1.0, 1.0, a }, 6.0 * px)
    for(spots) s: om_spot(s, team, px, alpha)
    // the selected building's rally point
    let b = b_index_of(sel_building)
    if b >= 0 and b_owner[b] == ME and b_rally_x[b] >= 0:
        let at = float2 { float(b_rally_x[b]), float(b_rally_y[b]) }
        let path = ground_path(om_edge(om_foot(4, b_cx[b], b_cy[b], b_sx[b], b_sy[b], 0), at), at)
        om_dashed(path, 4.5 * px, OM_EDGE * float4 { 1.0, 1.0, 1.0, 0.7 }, 6.0 * px)
        om_dashed(path, 2.0 * px, OM_RING * float4 { 1.0, 1.0, 1.0, 0.8 }, 6.0 * px)
        om_ellipse(on_ground(at), 6.0, OM_RING, px)
        om_flag(on_ground(at), team, 1.0, px)
