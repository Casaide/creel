// ------------------------------------------------------------------ the economy (economy.gd, buildings.gd)
// Buildings, worker jobs (gather -> carry -> drop off -> back), construction, farms, training and
// pop, and the GATHER / BUILD / HELP_BUILD / TRAIN / RALLY commands. Resource kinds are indexes + 1
// (0: none), as units.carry_kind. Left out (none in the scenarios, asserted by the exporter or
// here): gates and walls, pens, bridges, research and ageing up, heroes, shift-queued orders.

// ---- buildings (buildings.gd)

def b_index_of(bid:int) -> int:
    let found, at = binary_search(b_id, bid)
    return if found: at else: -1

// The cells under building b, row by row (a diagonal gate's: its diagonal).
def footprint(b:int) -> [int]: return cells_of(b_cx[b], b_cy[b], b_sx[b], b_sy[b], b_diag[b])

def add_building(bid:int, owner:int, k:int, cx:int, cy:int, sx:int, sy:int, diag:int) -> int:
    for(building_columns()) col, n:
        col.push([ bid, owner, k, cx, cy, sx, sy, 1, 0, 0, 0, -1, -1, 0, diag ][n])
    b_queue.push([]::int)
    b_inside.push([]::int)
    return b_id.length - 1

// A footprint's size laid `along` (Economy.dims): gates turn, diagonals take a square.
def dims(k:int, along:int) -> int, int:
    if along >= 2: return bt_length[k], bt_length[k]
    return if along == 0: bt_length[k] else: bt_size[k], if along == 0: bt_size[k] else: bt_length[k]

def diag_of(along:int) -> int: return if along >= 2: along - 1 else: 0

def along_for(k:int, along:int) -> int: return if bt_gate[k] and along >= 0 and along <= 3: along else: 0

// The cells of a footprint with its top-left on (x0, y0), row by row: the rect, or a diagonal's (Buildings.cells).
def cells_of(x0:int, y0:int, w:int, h:int, d:int) -> [int]:
    let out = []::int
    for(h) dy:
        let y = y0 + dy
        if d != 0: out.push(y * W + (if d == 1: x0 + dy else: x0 + w - 1 - dy))
        else:
            for(w) dx: out.push(y * W + x0 + dx)
    return out

// Put a building (unbuilt) on the map and return its slot (Economy.place).
def place(player:int, k:int, cx:int, cy:int, along:int = 0) -> int:
    let sx, sy = dims(k, along)
    let b = add_building(next_id, player, k, cx, cy, sx, sy, diag_of(along))
    next_id++
    clear_rubble(footprint(b))  // built over a breach: the rubble goes
    occupy(footprint(b), b_id[b], if bt_gate[k]: teams[player] else: -1, bt_blocks_flyers[k] != 0)
    if bt_ladder[k]: set_walk_over(footprint(b), true)  // walked over at the wall's foot
    if bt_gate[k]: refresh_lanes()                      // the team's first gate gives it lanes of its own
    return b

// Each player's (and gaia's) first lane: its team's own group once it has a gate (World.refresh_lanes).
def refresh_lanes():
    for(lane_base.length) p: lane_base[p] = lane_group(teams[p]) * NUM_CLASSES
    assert walks.length <= LANES

// A building goes up over these cells: any rubble there is cleared (Walls.clear_rubble).
def clear_rubble(cells:[int]):
    if not rubble_cells.length: return
    for(cells) c:
        let rec = rubble.get(c)
        if rec:
            rubble.del(c)
            rubble_cells = filter(rubble_cells) v: v != c
            set_terrain(c, rec[0])

// Can a gate (or anything with `replaces`) take this cell's place: the player's own building of a type it replaces?
def replaceable(player:int, k:int, c:int) -> bool:
    let id = occupied[c]
    if id == 0 or not bt_replaces[k].length: return false
    let b = b_index_of(id)
    return b >= 0 and b_owner[b] == player and contains(bt_replaces[k], b_kind[b])

// Is cell c beside (N E S W) a finished walkway cell of an enemy of `player` (a ladder's place)?
def against_enemy_wall(player:int, c:int) -> bool:
    for([ int2 { 0, -1 }, int2 { 1, 0 }, int2 { 0, 1 }, int2 { -1, 0 } ]) n:
        let x = c % W + n.x
        let y = c / W + n.y
        if x >= 0 and y >= 0 and x < W and y < H:
            let b = b_index_of(occupied[y * W + x])
            if b >= 0 and b_done[b] == 1 and bt_walkway[b_kind[b]] > 0 and is_enemy(b_owner[b], player): return true
    return false

// Take a building away without a fight (a wall tile a gate replaces). (Economy.demolish)
def demolish(b:int):
    pen_gone(b)
    occupy(footprint(b), 0)
    remove_building(b)

// What a building of type k costs over these cells: its cost, or rebuilt over its own breach, repair_pct of it.
def repair_cost(player:int, k:int, cells:[int]) -> [int]:
    let cost = bm_cost[player][k]
    if not rubble_cells.length or not cells.length: return cost
    for(cells) c:
        let rec = rubble.get(c)
        if not rec or rec[1] != player: return cost
    return map(cost) v: v * rubble_repair_pct / 100

// ---- units

def add_unit(owner:int, k:int, x:int, y:int) -> int:
    // units.gd _put's defaults, in unit_columns order
    let v = [ next_id, x, y, x, y, 0, 0, x, y, 0, 0, -1, -1, 0,
              t_hp[k], 0, 0, 0, t_posture[k], x, y, 0, 0, -1,
              T_NONE, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, x, y,
              owner, k, t_speed[k], t_radius[k], t_mclass[k], 0, 0, 0, 0, 0 ]
    unit_changes++
    for(unit_columns()) col, n: col.push(v[n])
    u_orders.push([])
    u_mount.push([])
    next_id++
    return u_id.length - 1

def is_worker(i:int) -> bool: return t_worker[u_kind[i]] != 0

def own_workers(player:int, ids:[int]) -> [int]:
    let out = []::int
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player and is_worker(i): out.push(i)
    return out

// A plain MOVE ends whatever the unit was doing (it keeps what it carries).
def clear_task(i:int):
    u_block[i] = 0
    u_task[i] = T_NONE
    u_target[i] = -1
    u_home[i] = -1
    u_gspot[i] = -1
    u_work[i] = 0

// The player's worker type (Economy.builder_class: its movement class is where they may build).
def worker_type(player:int) -> int:
    for(t_worker) w, k:
        if w and t_player[k] == player: return k
    return -1

def can_afford(player:int, cost:[int]) -> bool:
    for(cost) c, r:
        if stock[r][player] < c: return false
    return true

def pay(player:int, cost:[int]):
    for(cost) c, r: stock[r][player] -= c

// ---- rects

def cell_rect(cell:int) -> int, int, int, int:
    let x = (cell % W) * TILE
    let y = (cell / W) * TILE
    return x, y, x + TILE - 1, y + TILE - 1

def building_rect(b:int) -> int, int, int, int:
    if b_diag[b] != 0: return cell_rect((b_cy[b] + b_sy[b] / 2) * W + b_cx[b] + b_sx[b] / 2)
    let x = b_cx[b] * TILE
    let y = b_cy[b] * TILE
    return x, y, x + b_sx[b] * TILE - 1, y + b_sy[b] * TILE - 1

// Is unit i's body within REACH of the rect?
def in_reach(i:int, x0:int, y0:int, x1:int, y1:int) -> bool:
    let dx = max(max(x0 - u_x[i], 0), u_x[i] - x1)
    let dy = max(max(y0 - u_y[i], 0), u_y[i] - y1)
    let reach = u_radius[i] + REACH
    return dx * dx + dy * dy <= reach * reach

def approach_building(i:int, b:int):
    let x0, y0, x1, y1 = building_rect(b)
    order_reach(i, x0, y0, x1, y1, building_field(b_id[b], true, lane(i)))

// ---- gather spots

// Do gatherers at this tile stand at spots round it? Not on a farm; otherwise as its resource says.
def spotted(cell:int) -> bool:
    if pool[cell] >= 0: return false
    let k = res_at(cell)
    return k > 0 and gather_spots[k - 1] != 0

def sides_only(cell:int) -> bool:
    let k = res_at(cell)
    return k > 0 and gather_spots[k - 1] == SIDES

// Is there open ground to stand on beside this spotted tile in unit i's lane (lane 0 without one)?
def open_beside(cell:int, i:int) -> bool:
    let ln = if i >= 0: lane(i) else: 0
    let x = cell % W
    let y = cell / W
    let step = if sides_only(cell): 2 else: 1
    var k = 0
    while k < SPOTS:
        if cell_walkable(x + SPOT_DX[k], y + SPOT_DY[k], ln): return true
        k += step
    return false

// Where worker i stands at spot k round resource tile `cell`; (-1, -1) if that ground is blocked.
def spot_at(i:int, cell:int, k:int) -> int, int:
    let r = u_radius[i]
    let dx = SPOT_DX[k]
    let dy = SPOT_DY[k]
    var off = r + SPOT_GAP
    if dx != 0 and dy != 0: off = (r + REACH - 60) * 707 / 1000
    let x0 = (cell % W) * TILE
    let y0 = (cell / W) * TILE
    let x = if dx == 0: x0 + TILE / 2 elif dx < 0: x0 - off else: x0 + TILE - 1 + off
    let y = if dy == 0: y0 + TILE / 2 elif dy < 0: y0 - off else: y0 + TILE - 1 + off
    let ln = lane(i)
    if not walkable(x, y, ln): return -1, -1
    let px, py = off_walls(x, y, r, ln)
    let ex = max(max(x0 - px, 0), px - (x0 + TILE - 1))
    let ey = max(max(y0 - py, 0), py - (y0 + TILE - 1))
    if ex * ex + ey * ey > (r + REACH - 20) * (r + REACH - 20): return -1, -1
    return px, py

// The spots held round tiles within two of `cell` by gatherers other than i, and where builders
// at work stand near it: x, y, radius each (flat).
def held_near(cell:int, i:int) -> [int]:
    let out = []::int
    for(u_x.length) j:
        if j != i:
            let h = u_home[j]
            if h >= 0 and u_gspot[j] >= 0 and (u_task[j] == GATHER or u_task[j] == T_RETURN):
                if abs(h % W - cell % W) <= 2 and abs(h / W - cell / W) <= 2:
                    let qx, qy = spot_at(j, h, u_gspot[j])
                    out.push(qx)
                    out.push(qy)
                    out.push(u_radius[j])
            elif u_task[j] == BUILD and u_moving[j] == 0:
                let c = cell_of(u_x[j], u_y[j])
                if abs(c % W - cell % W) <= 2 and abs(c / W - cell / W) <= 2:
                    out.push(u_x[j])
                    out.push(u_y[j])
                    out.push(u_radius[j])
    return out

// Would a body of unit i at (px, py) stand in a held spot?
def crowded(i:int, px:int, py:int, held:[int]) -> bool:
    let r = u_radius[i]
    var q = 0
    while q < held.length:
        let rr = r + held[q + 2] - SPOT_GAP
        if dist2(px, py, held[q], held[q + 1]) < rr * rr: return true
        q += 3
    return false

def spot_held(cell:int, k:int, i:int) -> bool:
    let px, py = spot_at(i, cell, k)
    return px < 0 or crowded(i, px, py, held_near(cell, i))

// The free spot round `cell` nearest worker i (lowest k on ties), or -1.
def free_spot(i:int, cell:int) -> int:
    if not spotted(cell): return -1
    let held = held_near(cell, i)
    var best = -1
    var best_d = 1 << 62
    var k = 0
    let step = if sides_only(cell): 2 else: 1
    while k < SPOTS:
        let px, py = spot_at(i, cell, k)
        if px >= 0 and not crowded(i, px, py, held):
            let d = dist2(u_x[i], u_y[i], px, py)
            if d < best_d:
                best_d = d
                best = k
        k += step
    return best

// Walk up to a resource tile: to the worker's own spot round it while it gathers there, else
// anywhere in reach (a farm, or no room).
def approach_cell(i:int, cell:int):
    if u_home[i] == cell and spotted(cell):
        if u_gspot[i] < 0 or spot_held(cell, u_gspot[i], i):
            u_gspot[i] = free_spot(i, cell)
        if u_gspot[i] >= 0:
            let px, py = spot_at(i, cell, u_gspot[i])
            order_move(i, px, py, SLOT_ARRIVE, 0, -1, -1, 0, true)
            return
    let x0, y0, x1, y1 = cell_rect(cell)
    order_reach(i, x0, y0, x1, y1, cell_field(cell, true, lane(i)))

// ---- picking where to work

// Is this cell's ground (a farm's pool) worked by as many workers as it takes, not counting unit i?
def taken(cell:int, i:int) -> bool:
    if cell < 0 or pool[cell] < 0: return false
    let b = b_index_of(occupied[cell])
    if b >= 0 and i >= 0 and b_owner[b] != u_owner[i]: return true
    let limit = if b >= 0: bt_workers[b_kind[b]] else: 0
    if limit <= 0: return false
    var n = 0
    for(u_x.length) j:
        if j != i and u_home[j] >= 0 and pool[u_home[j]] == pool[cell] and (u_task[j] == GATHER or u_task[j] == T_RETURN): n++
    return n >= limit

def explored(player:int, c:int) -> bool:
    return player >= fog.length or fog[player][c] != 0

// The tile of this resource near `cell` with the fewest gatherers, nearer ones first, ties to the lower cell.
def least_busy(cell:int, kind:int, except:int, i:int) -> int:
    let cx = cell % W
    let cy = cell / W
    var best = cell
    var best_score = 1 << 62
    let busy = dictionary<int, int>(251)
    for(u_x.length) j:
        if u_home[j] >= 0 and (u_task[j] == GATHER or u_task[j] == T_RETURN):
            busy.set(u_home[j], busy.get(u_home[j], 0) + 1)
    var yy = max(cy - SPREAD_TILES, 0)
    while yy < min(cy + SPREAD_TILES + 1, H):
        var xx = max(cx - SPREAD_TILES, 0)
        while xx < min(cx + SPREAD_TILES + 1, W):
            let c = yy * W + xx
            xx++
            if c == except or amount[c] <= 0 or res_at(c) != kind or taken(c, i): continue
            if spotted(c) and not open_beside(c, i): continue
            let nb = busy.get(c, 0)
            var score = nb * BUSY_COST + dist2(cx * 1000, cy * 1000, (xx - 1) * 1000, yy * 1000)
            if i >= 0 and nb > 0 and spotted(c) and free_spot(i, c) < 0: score += 1 << 40
            if score < best_score:
                best_score = score
                best = c
        yy++
    return best

// The nearest cell with this resource within SEARCH_TILES, or -1 (ties to the lower cell).
def nearest_resource(x:int, y:int, kind:int, i:int, farms:bool, roomy_only:bool, seen:bool) -> int:
    return nearest_resource_within(x, y, kind, i, farms, roomy_only, seen, SEARCH_TILES)

// A gatherer whose patch ran out looks near first, then further out over ground its side has seen (#336): a worker
// only stands idle when there's none of it about.
def next_patch(i:int, kind:int) -> int:
    var c = nearest_resource(u_x[i], u_y[i], kind, i, false, true, true)
    if c < 0: c = nearest_resource(u_x[i], u_y[i], kind, i, false, false, true)
    if c < 0: c = nearest_resource_within(u_x[i], u_y[i], kind, i, false, true, true, FAR_SEARCH_TILES)
    if c < 0: c = nearest_resource_within(u_x[i], u_y[i], kind, i, false, false, true, FAR_SEARCH_TILES)
    return c

def nearest_resource_within(x:int, y:int, kind:int, i:int, farms:bool, roomy_only:bool, seen:bool, r:int) -> int:
    let cx = x / TILE
    let cy = y / TILE
    var best = -1
    var best_d2 = 1 << 62
    var yy = max(cy - r, 0)
    while yy < min(cy + r + 1, H):
        var xx = max(cx - r, 0)
        while xx < min(cx + r + 1, W):
            let c = yy * W + xx
            let d2 = dist2(x, y, xx * TILE + 500, yy * TILE + 500)
            xx++
            if amount[c] <= 0 or res_at(c) != kind or (farms and pool[c] < 0): continue
            if d2 >= best_d2 or (i >= 0 and taken(c, i)) or (seen and not explored(u_owner[i], c)) or (spotted(c) and not open_beside(c, i)): continue
            if roomy_only and spotted(c) and free_spot(i, c) < 0: continue
            best_d2 = d2
            best = c
        yy++
    return best

// Where worker i gathers when sent to `cell` (Economy._pick).
def pick(i:int, cell:int, kind:int) -> int:
    let c = least_busy(cell, kind, -1, i)
    let to_farm = pool[cell] >= 0
    let x = (cell % W) * TILE + TILE / 2
    let y = (cell / W) * TILE + TILE / 2
    if spotted(c) and free_spot(i, c) < 0:
        let roomy_c = nearest_resource(x, y, kind, i, false, true, false)
        if roomy_c >= 0: return roomy_c
    if not taken(c, i) and (not to_farm or pool[c] >= 0): return c
    let farm = nearest_resource(x, y, kind, i, true, false, false)
    if farm >= 0: return farm
    return if not taken(c, i): c else: nearest_resource(x, y, kind, i, false, false, false)

// The owner's nearest finished building that takes what unit i carries, or -1.
def nearest_drop_off(i:int) -> int:
    var best = -1
    var best_d2 = 1 << 62
    for(b_id.length) b:
        if b_owner[b] == u_owner[i] and b_done[b] != 0 and u_carry_kind[i] > 0 and bt_drop[b_kind[b]][u_carry_kind[i] - 1] != 0:
            let d2 = dist2(u_x[i], u_y[i], b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2)
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

// ---- tasks

// Send worker i to gather `kind` at `cell` (Economy.start_gather).
def start_gather(i:int, cell:int, kind:int):
    let c = pick(i, cell, kind)
    if u_carry[i] > 0 and u_carry_kind[i] != kind: u_carry[i] = 0
    u_carry_kind[i] = kind
    u_task[i] = GATHER
    u_target[i] = if c >= 0: c else: cell
    u_home[i] = c
    u_gspot[i] = -1
    u_work[i] = 0
    approach_cell(i, u_target[i])

def start_build(i:int, bid:int):
    if u_task[i] != GATHER and u_task[i] != T_RETURN: u_home[i] = -1
    u_task[i] = BUILD
    u_target[i] = bid
    u_gspot[i] = -1
    u_work[i] = 0
    approach_building(i, b_index_of(bid))

def to_drop_off(i:int):
    let b = nearest_drop_off(i)
    if b < 0:
        clear_task(i)
        return
    u_task[i] = T_RETURN
    u_target[i] = b_id[b]
    u_work[i] = 0
    approach_building(i, b)

// ---- farms

// The finished farm of `player` whose crops cover `cell`, or -1.
def farm_at(cell:int, player:int) -> int:
    if pool[cell] < 0: return -1
    let b = b_index_of(occupied[cell])
    if b < 0 or b_owner[b] != player or b_done[b] == 0 or not bt_farm[b_kind[b]]: return -1
    return b

// Reseed finished farm b if it's worked out and its owner can pay: crops again. Whether it was.
def reseed(b:int) -> bool:
    if b < 0: return false  // (GDScript: farm_at's -1 reads the last building; never in a scenario where it matters)
    let p = b_owner[b]
    let k = b_kind[b]
    let cells = footprint(b)
    let to = tr_reseed[terrain[cells[0]]]
    if b_done[b] == 0 or not bt_farm[k] or left_at(cells[0]) > 0 or to < 0 or not can_afford(p, bt_reseed[k]): return false
    pay(p, bt_reseed[k])
    make_pool(cells, to, bm_food[p][k])
    return true

def farm_done(i:int, cell:int):
    let b = farm_at(cell, u_owner[i])
    if b < 0: return
    if auto_reseed[b_owner[b]] == 1: reseed(b)

def fallow(i:int, cell:int, kind:int):
    if u_carry[i] > 0:
        to_drop_off(i)
        return
    let x0, y0, x1, y1 = cell_rect(cell)
    if in_reach(i, x0, y0, x1, y1):
        u_moving[i] = 0
        u_stuck[i] = 0
    elif u_moving[i] == 0 and u_stuck[i] < GIVE_UP:
        approach_cell(i, cell)
    u_work[i]++
    if u_work[i] < WAIT_TICKS: return
    u_work[i] = 0
    if auto_reseed[u_owner[i]] == 1 and reseed(farm_at(cell, u_owner[i])): return
    let other = nearest_resource(u_x[i], u_y[i], kind, i, true, false, true)
    if other >= 0: start_gather(i, other, kind)

// A farm torn down leaves plain ground behind (Economy.clear_farm, SimMap.clear_pool).
def clear_farm(b:int):
    if not bt_farm[b_kind[b]] or b_done[b] == 0: return
    let cells = footprint(b)
    let to = tr_cleared[terrain[cells[0]]]
    if to < 0: return
    for(cells) c:
        pool[c] = -1
        amount[c] = 0
        walk_over[c] = 0
        set_cell_terrain(c, to)
        refresh(c)

// A finished farm turns its ground into crops; the builder who finished it starts the harvest.
def become_ground(b:int, i:int):
    let k = b_kind[b]
    let cells = footprint(b)
    let land = tr_walk[terrain[cells[0]]]
    make_pool(cells, if land: bt_land[k] else: bt_wet[k], bm_food[b_owner[b]][k])
    if not u_orders[i].length: start_gather(i, cells[0], 1)  // (food: resource index 0)
    else: clear_task(i)                                      // told what to do after (shift): that comes first, not farming forever

// ---- a tick of jobs

def gather(i:int, carry_max:int):
    if u_carry[i] >= carry_max:
        to_drop_off(i)
        return
    let cell = u_target[i]
    let kind = u_carry_kind[i]
    if res_at(cell) != kind and u_home[i] == cell and farm_at(cell, u_owner[i]) >= 0:
        fallow(i, cell, kind)
        return
    if res_at(cell) != kind:
        let more = next_patch(i, kind)
        if more >= 0:
            u_target[i] = more
            u_home[i] = more
            u_gspot[i] = -1
            u_work[i] = 0
            approach_cell(i, more)
        elif u_carry[i] > 0:
            u_home[i] = -1
            to_drop_off(i)
        else:
            clear_task(i)
        return
    if u_home[i] < 0:
        wait_by(i, cell, kind)
        return
    let x0, y0, x1, y1 = cell_rect(cell)
    if in_reach(i, x0, y0, x1, y1) and (u_reach[i] == 1 or u_moving[i] == 0 or dist2(u_x[i], u_y[i], u_tx[i], u_ty[i]) <= SPOT_NEAR * SPOT_NEAR):
        u_moving[i] = 0
        u_stuck[i] = 0
        u_work[i]++
        if u_work[i] >= gather_ticks[u_owner[i]][kind - 1]:
            u_work[i] = 0
            take(cell)
            u_carry[i]++
            if res_at(cell) != kind and pool[cell] < 0: rally_on(u_owner[i], cell, i, kind)  // (a farm fallows instead)
            if pool[cell] >= 0 and left_at(cell) <= 0: farm_done(i, cell)
    elif u_moving[i] == 0:
        if u_stuck[i] >= GIVE_UP:
            let other = least_busy(cell, kind, cell, i)
            if other != cell and not taken(other, i):
                u_target[i] = other
                u_home[i] = other
                u_gspot[i] = -1
                approach_cell(i, other)
            else:
                clear_task(i)
        elif u_reach[i] == 0 and u_gspot[i] >= 0:
            order_reach(i, x0, y0, x1, y1, cell_field(cell, true, lane(i)))
        else:
            approach_cell(i, cell)

// Waiting by a full farm: every WAIT_TICKS, look again.
def wait_by(i:int, cell:int, kind:int):
    if u_moving[i] == 0: u_stuck[i] = 0
    u_work[i]++
    if u_work[i] < WAIT_TICKS: return
    u_work[i] = 0
    let c = pick(i, cell, kind)
    if c >= 0:
        u_target[i] = c
        u_home[i] = c
        u_gspot[i] = -1
        approach_cell(i, c)

def return_home(i:int):
    let b = b_index_of(u_target[i])
    if b < 0 or b_done[b] == 0:
        to_drop_off(i)
        return
    let x0, y0, x1, y1 = building_rect(b)
    if in_reach(i, x0, y0, x1, y1):
        let p = u_owner[i]
        if u_carry_kind[i] > 0:
            stock[u_carry_kind[i] - 1][p] += u_carry[i]
            gathered[u_carry_kind[i] - 1][p] += u_carry[i]
        u_carry[i] = 0
        u_moving[i] = 0
        if u_home[i] >= 0:
            u_task[i] = GATHER
            u_target[i] = u_home[i]
            approach_cell(i, u_home[i])
        else:
            clear_task(i)
    elif u_moving[i] == 0:
        // Held up by the crowd at the drop-off (#336): try again from where it stands, never drop the load and idle.
        if u_stuck[i] >= GIVE_UP: u_stuck[i] = 0
        approach_building(i, b)

// The nearest unfinished building of the worker's owner within NEXT_BUILD_TILES, on explored ground.
def nearby_foundation(i:int) -> int:
    var best = -1
    var best_d2 = NEXT_BUILD_TILES * NEXT_BUILD_TILES * TILE * TILE + 1
    for(b_id.length) b:
        if b_owner[b] == u_owner[i] and b_done[b] != 1 and explored(u_owner[i], (b_cy[b] + b_sy[b] / 2) * W + b_cx[b] + b_sx[b] / 2):
            let d2 = dist2(u_x[i], u_y[i], b_cx[b] * TILE + b_sx[b] * TILE / 2, b_cy[b] * TILE + b_sy[b] * TILE / 2)
            if d2 < best_d2:
                best_d2 = d2
                best = b
    return best

// A builder done: back to the resource it gathered before building, if that's near. Whether it went.
def back_to_work(i:int) -> bool:
    var h = u_home[i]
    let kind = u_carry_kind[i]
    if h < 0 or kind <= 0: return false
    let hx = (h % W) * TILE + TILE / 2
    let hy = (h / W) * TILE + TILE / 2
    let far = BACK_TO_WORK_TILES * TILE
    if dist2(u_x[i], u_y[i], hx, hy) > far * far: return false
    if res_at(h) != kind or amount[h] <= 0:
        h = nearest_resource(hx, hy, kind, i, false, false, true)
        if h < 0: return false
    start_gather(i, h, kind)
    return true

// A finished camp (taking in some resources, not all): its builders go and gather the nearest of them.
def gather_after_camp(b:int):
    let k = b_kind[b]
    let kinds = []::int
    for(bt_drop[k]) d, r:
        if d == 1: kinds.push(r + 1)
    if not kinds.length or kinds.length == bt_drop[k].length: return
    let bid = b_id[b]
    for(u_x.length) j:
        if u_task[j] == BUILD and u_target[j] == bid and not u_orders[j].length:
            var best = -1
            var best_kind = 0
            var best_d2 = 1 << 62
            for(kinds) kind:
                let c = nearest_resource(u_x[j], u_y[j], kind, j, false, false, true)
                if c >= 0:
                    let d2 = dist2(u_x[j], u_y[j], (c % W) * TILE + 500, (c / W) * TILE + 500)
                    if d2 < best_d2:
                        best_d2 = d2
                        best = c
                        best_kind = kind
            if best >= 0: start_gather(j, best, best_kind)

def build_job(i:int):
    let b = b_index_of(u_target[i])
    if b < 0:
        let br = bridge_index(u_target[i])
        if br >= 0:
            if not bridge_work(i, br, in_reach(i, br_x0[br], br_y0[br], br_x1[br], br_y1[br])): clear_task(i)
            return
    if b < 0 or b_done[b] == 1:
        let nb = if u_orders[i].length: -1 else: nearby_foundation(i)
        if nb >= 0:
            u_target[i] = b_id[nb]
            approach_building(i, nb)
        elif u_orders[i].length or not back_to_work(i):
            clear_task(i)
        return
    let x0, y0, x1, y1 = building_rect(b)
    if in_reach(i, x0, y0, x1, y1):
        u_moving[i] = 0
        u_stuck[i] = 0
        let k = b_kind[b]
        let max_hp = bm_hp[b_owner[b]][k]
        let pct = t_build_pct[u_kind[i]]
        var st = 1
        if pct != 0:
            u_work[i]++
            st += u_work[i] * pct / 100 - (u_work[i] - 1) * pct / 100
        b_progress[b] = min(bt_build_ticks[k], b_progress[b] + st)
        b_hp[b] = max(1, max_hp * b_progress[b] / bt_build_ticks[k])
        if b_progress[b] >= bt_build_ticks[k]:
            b_done[b] = 1
            b_hp[b] = max_hp
            if bt_farm[k]: become_ground(b, i)
            elif bt_pen_animals[k] > 0: pen_opened(b)  // a pen: walked into
            else: gather_after_camp(b)
    elif u_moving[i] == 0:
        if u_stuck[i] >= GIVE_UP: clear_task(i)
        else: approach_building(i, b)

// One tick of every worker's job (Economy.work). Runs before movement.
def work():
    for(u_x.length) i:
        let task = u_task[i]
        if task == GATHER: gather(i, r_carry + t_carry_add[u_kind[i]])
        elif task == T_RETURN: return_home(i)
        elif task == BUILD: build_job(i)

// ---- training and pop

def update_pop():
    for(num_players) p:
        pop[p] = 0
        pop_cap[p] = 0
    for(u_x.length) i:
        if u_owner[i] != gaia: pop[u_owner[i]] += t_pop[u_kind[i]]
    for(b_id.length) b:  // those sheltering inside still count
        var o = 0
        while o < b_inside[b].length:
            pop[b_owner[b]] += t_pop[b_inside[b][o + REC_KIND]]
            o += REC_SIZE
    for(b_id.length) b:
        if b_done[b] == 1:
            let p = b_owner[b]
            var add = bt_pop[b_kind[b]]
            if add > 0: add += bm_pop[p][b_kind[b]]
            pop_cap[p] += add
    for(num_players) p: pop_cap[p] = min(pop_cap[p], r_pop_max)

def spawn_cell(b:int, k:int) -> int:
    let c = spawn_cell_loose(b, k)
    assert c >= 0
    return c

// Where a unit of kind k (radius r) coming out at (x, y) for side p stands: there if no one's body is in the way, or else
// the nearest point round it clear of everyone, rings a body apart (#394: on top of the last one out, the two were
// shoved apart and every new one pushed the crowd at the rally point further out). For unit `skip` itself, retargeting
// beside a spot taken (#396), also clear of where its side's others on their way are going.
def clear_point(p:int, k:int, x:int, y:int, skip:int = -1) -> int, int:
    let r = t_radius[k]
    let ln = lane_base[p] + t_mclass[k]
    let air = t_air[k]
    def free(px:int, py:int) -> bool:
        if not walkable(px, py, ln): return false
        for(u_x.length) j:
            if j != skip and t_air[u_kind[j]] == air:
                let rr = r + u_radius[j]
                if dist2(px, py, u_x[j], u_y[j]) < rr * rr: return false
                if skip >= 0 and u_moving[j] == 1 and u_owner[j] == p and u_reach[j] == 0 and dist2(px, py, u_tx[j], u_ty[j]) < rr * rr: return false  // (nor where another on its way is going)
        return true
    if free(x, y): return x, y
    for(CLEAR_RINGS) rg:
        let d = (rg + 1) * r * 2
        let n = (rg + 1) * 8
        var bx = -1
        var by = -1
        var bd = -1
        for(n) a:
            let ang = a * 256 / n
            let px, py = off_walls(x + cos_a(ang) * d / ONE, y + sin_a(ang) * d / ONE, r, ln)
            if free(px, py) and clear_path(x, y, px, py, r, ln):  // (on its own side of a wall or the water)
                if skip < 0: return px, py
                let dd = dist2(px, py, u_x[skip], u_y[skip])  // (the one beside the spot nearest where it is)
                if bd < 0 or dd < bd:
                    bd = dd
                    bx = px
                    by = py
        if bd >= 0: return bx, by
    return x, y

// The walkable cell beside building b nearest its rally point (or its front corner), or -1.
def spawn_cell_loose(b:int, k:int) -> int:
    let cx = b_cx[b]
    let cy = b_cy[b]
    let sx = b_sx[b]
    let sy = b_sy[b]
    let gx = if b_rally_x[b] >= 0: b_rally_x[b] else: (cx + sx) * TILE
    let gy = if b_rally_x[b] >= 0: b_rally_y[b] else: (cy + sy) * TILE
    var best = -1
    var best_d2 = 1 << 62
    var y = cy - 1
    while y < cy + sy + 1:
        var x = cx - 1
        while x < cx + sx + 1:
            let edge = x == cx - 1 or x == cx + sx or y == cy - 1 or y == cy + sy
            if edge and cell_walkable(x, y, lane_base[b_owner[b]] + t_mclass[k]):
                let d2 = dist2(gx, gy, x * TILE + 500, y * TILE + 500)
                if d2 < best_d2:
                    best_d2 = d2
                    best = y * W + x
            x++
        y++
    return best

def go_to_rally(b:int, i:int):
    if b_rally_x[b] < 0: return
    let cell = cell_of(b_rally_x[b], b_rally_y[b])
    let kind = res_at(cell)
    if kind > 0 and is_worker(i): start_gather(i, cell, kind)
    else: order_move(i, b_rally_x[b], b_rally_y[b], 200, 0, -1, -1, 0)

// The tree (or mine) a side rallies to has run out (#336): its rallies move to the next of it the worker would go to,
// so those still to come gather instead of standing by a stump.
def rally_on(p:int, cell:int, i:int, kind:int):
    let more = next_patch(i, kind)
    if more < 0: return
    for(b_id.length) b:
        if b_owner[b] == p and b_rally_x[b] >= 0 and cell_of(b_rally_x[b], b_rally_y[b]) == cell:
            b_rally_x[b] = (more % W) * TILE + TILE / 2
            b_rally_y[b] = (more / W) * TILE + TILE / 2

// Advance every building's train queue; training waits at the pop cap (Economy.train).
// A unit of kind k just trained at building b: out beside it, nearest its rally point, clear of anyone standing there.
def trained(b:int, k:int) -> int:
    let c = spawn_cell(b, k)
    let x, y = clear_point(b_owner[b], k, (c % W) * TILE + 500, (c / W) * TILE + 500)
    return add_unit(b_owner[b], k, x, y)

def train():
    update_pop()
    for(b_id.length) b:
        let q = b_queue[b]
        if b_done[b] != 0 and q.length and q[0] >= 0:
            let p = b_owner[b]
            let k = q[0]
            if not (b_train[b] == 0 and pop[p] + t_pop[k] > pop_cap[p]):
                b_train[b]++
                if b_train[b] >= t_train_ticks[k]:
                    b_train[b] = 0
                    q.remove(0)
                    let i = trained(b, k)
                    pop[p] += t_pop[k]
                    if t_hero[k]: hero_spawned(i)
                    go_to_rally(b, i)

// ---- commands

def cmd_gather(player:int, ids:[int], cell:int):
    // A bot that found nothing sends cell -1: GDScript's arrays read that as the last cell (in practice
    // no resource there), so its gatherers walk to -1's tile: (-500, 500).
    let kind = res_at(if cell < 0: cell + W * H else: cell)
    assert cell >= 0 or kind <= 0
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player:
            if kind <= 0 or not is_worker(i):
                order_move(i, (cell % W) * 1000 + 500, (cell / W) * 1000 + 500, 200, 0, -1, -1, 0)
            else:
                start_gather(i, cell, kind)

// Why this player can't start a building of type k anywhere just now: false if it can.
def build_barred(player:int, k:int) -> bool:
    if bm_lacks[player][k]: return true
    if ages[player] < bt_age[k]: return true
    if bt_more_from_age[k] > 0 and ages[player] < bt_more_from_age[k]:
        for(b_id.length) b:
            if b_owner[b] == player and b_kind[b] == k: return true
    return false

def can_place(player:int, k:int, cx:int, cy:int, along:int = 0) -> bool:
    let mc = t_mclass[worker_type(player)]
    let sx, sy = dims(k, along)
    if cx < 0 or cy < 0 or cx + sx > W or cy + sy > H: return false
    for(cells_of(cx, cy, sx, sy, diag_of(along))) c:
        if not can_build(c % W, c / W, 1, mc, bt_water[k] != 0, bt_line[k] != 0) and not replaceable(player, k, c): return false
        if bt_gate[k] and cliff[c] == 1: return false
    if bt_ladder[k] and not against_enemy_wall(player, cy * W + cx): return false  // a ladder only leans on an enemy walkway
    return true

// Pay for and place a BUILD's foundation; its id, or 0 when it can't be built there.
def lay_foundation(player:int, ids:[int], k:int, cx:int, cy:int, along0:int = 0) -> int:
    if k < 0: return 0
    if not own_workers(player, ids).length or build_barred(player, k): return 0
    let along = along_for(k, along0)
    if not can_place(player, k, cx, cy, along): return 0
    let sx, sy = dims(k, along)
    let cells = cells_of(cx, cy, sx, sy, diag_of(along))
    let cost = repair_cost(player, k, cells)
    if not can_afford(player, cost): return 0
    pay(player, cost)
    for(cells) c:
        if replaceable(player, k, c): demolish(b_index_of(occupied[c]))  // a gate dropped into a wall takes its place
    return b_id[place(player, k, cx, cy, along)]

def cmd_build(player:int, ids:[int], k:int, cx:int, cy:int, along:int = 0):
    let bid = lay_foundation(player, ids, k, cx, cy, along)
    if bid == 0: return
    for(own_workers(player, ids)) i: start_build(i, bid)

def cmd_help_build(player:int, ids:[int], target:int):
    if bridge_help(player, target, own_workers(player, ids)): return  // a map bridge: rebuilt by anyone
    let b = b_index_of(target)
    if b < 0 or b_owner[b] != player or b_done[b] == 1: return
    for(own_workers(player, ids)) i: start_build(i, target)

// TRAIN, its unit type worked out by the exporter (k, -1 for none; ok 0 if the race lacks the line).
def cmd_train(player:int, bid:int, k:int, ok:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != player or b_done[b] == 0: return
    if not contains(bm_trains[player][b_kind[b]], k): return
    if k < 0 or b_queue[b].length >= r_queue_max or not ok: return
    let cost = unit_cost(k)  // (a revived hero's share of its price)
    if not can_afford(player, cost) or ages[player] < t_age[k]: return
    if t_hero[k] and hero_barred(player, k): return
    pay(player, cost)
    b_queue[b].push(k)

// Reseed a worked-out farm: pay, crops again, the workers start the harvest.
def cmd_reseed(player:int, ids:[int], bid:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != player or not reseed(b): return
    let cells = footprint(b)
    for(own_workers(player, ids)) i: start_gather(i, cells[0], 1)

def cmd_rally(player:int, bid:int, ax:int, ay:int):
    let b = b_index_of(bid)
    if b < 0 or b_owner[b] != player: return
    var x = clamp(ax, 0, W * TILE - 1)
    var y = clamp(ay, 0, H * TILE - 1)
    let cell = cell_of(x, y)
    if res_at(cell) != 0:
        x = (cell % W) * TILE + TILE / 2
        y = (cell / W) * TILE + TILE / 2
    b_rally_x[b] = x
    b_rally_y[b] = y

// World._run's prelude for unit orders (GATHER, BUILD, HELP_BUILD): the player's own units, their
// fights forgotten (orders are never shift-queued here).
def own_units_cleared(player:int, ids:[int]) -> [int]:
    let now = []::int
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == player: now.push(uid)
    for(now) uid: combat_clear(index_of(uid))
    return now
