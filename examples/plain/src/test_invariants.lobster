// The per-tick invariants (src/testkit/invariants.lobster, #186), headless: a small world by hand where every one holds,
// then one break planted for each, caught by its own name. ../../../check.sh runs it.
//   lobster test_invariants.lobster
import sim_modules
import testkit.invariants

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// A 12 x 12 map, one unit type (radius a third of a tile), two resources, two players, stocked: two units apart, a store.
def tiny_world():
    W = 12
    H = 12
    for([ t_hp, t_posture, t_speed, t_radius, t_mclass, t_air, t_carry_add ]) col: col.remove_range(0, col.length)
    t_hp.push(10)
    t_posture.push(0)
    t_speed.push(100)
    t_radius.push(TILE / 3)
    t_mclass.push(0)
    t_air.push(0)
    t_carry_add.push(0)
    resource_names = [ "wood", "stone" ]
    num_resources = 2
    stock = [ [ 0, 0 ], [ 0, 0 ] ]
    r_stocked = 1
    r_solid = 1
    for(unit_columns()) col: col.remove_range(0, col.length)
    u_orders = []
    u_mount = []
    u_inside = []
    for(building_columns()) col: col.remove_range(0, col.length)
    b_queue = []
    b_inside = []
    b_hold = []
    b_want = []
    b_resv = []
    b_coming = []
    b_make = []
    b_site = []
    for([ jb_id, jb_unit, jb_from, jb_to, jb_res, jb_n, jb_phase, jb_want ]) col: col.remove_range(0, col.length)
    next_id = 1
    add_unit(0, 0, 2 * TILE + TILE / 2, 2 * TILE + TILE / 2)
    add_unit(0, 0, 6 * TILE + TILE / 2, 2 * TILE + TILE / 2)
    add_unit(1, 0, 9 * TILE + TILE / 2, 9 * TILE + TILE / 2)
    add_building(100, 0, 0, 4, 6, 2, 2, 0)
    b_hold[0] = [ 5, 3 ]
    sp_cell = map(u_id.length): 0
    sp_items = map(u_id.length + 1): 0
    spatial_clear()
    spatial_build()
    inv_stuck_limit = 0

// The world as tiny_world() leaves it, a tick "run" by change(), then the invariants: the first broken ("" for none).
def after(change) -> string:
    tiny_world()
    inv_before()
    change()
    sp_cell = map(u_id.length): 0
    sp_items = map(u_id.length + 1): 0
    spatial_build()
    return inv_after()

def caught(name:string, change):
    let why = after(change)
    check(starts_with(why, name + ":"), "a planted {name} break is caught as {name}: \"{why}\"")

def test_invariants():
    let none = after(): pass()
    check(none == "", "every invariant holds in the tiny world: \"{none}\"")
    let clear = after(): u_x[1] = 4 * TILE
    check(clear == "", "a step that keeps clear of everyone holds: \"{clear}\"")
    caught("columns"): u_hp.pop()
    caught("columns"): b_hold.push([ 0, 0 ])
    caught("ids"): u_id[1] = u_id[0]
    caught("ids"): u_id[2] = 0
    caught("on_map"): u_x[2] = W * TILE
    caught("on_map"): b_cx[0] = W - 1
    caught("carry"): u_carry[0] = -1
    caught("carry"):
        u_carry[0] = 2
        u_carry_kind[0] = 0
    caught("carry"): u_carry_kind[0] = 3
    caught("stock"): stock[1][0] = -4
    caught("holds"): b_hold[0][1] = -1
    caught("holds"): b_resv[0] = [ 0, -1 ]
    caught("jobs"):
        jb_id.push(1)
        for([ jb_unit, jb_from, jb_to, jb_res, jb_n, jb_phase, jb_want ]) col: col.push(0)
        jb_unit[0] = 99
        jb_n[0] = 1
    caught("jobs"):
        jb_id.push(1)
        for([ jb_unit, jb_from, jb_to, jb_res, jb_n, jb_phase, jb_want ]) col: col.push(0)
        jb_unit[0] = u_id[0]
    caught("solid"): u_x[1] = u_x[0] + TILE / 4
    let soft = after():
        r_solid = 0
        u_x[1] = u_x[0] + TILE / 4
    check(soft == "", "with bodies not solid, walking into one holds: \"{soft}\"")
    caught("stuck"):
        inv_stuck_limit = 80
        u_moving[0] = 1
        u_stuck[0] = 81
    let unlimited = after():
        u_moving[0] = 1
        u_stuck[0] = 81
    check(unlimited == "", "held up long holds when no limit is set: \"{unlimited}\"")

def test_pack():
    lua_on = true
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_quiet = true
    lua_load_pack("t", [ "t.lua" ], [ "function invariants() if unit_count() > 3 then return \'too many: \' .. unit_count() end end" ], L_BUDGET_LOAD)
    lua_freeze()
    let held = after(): pass()
    check(held == "", "a pack\'s invariant that holds: \"{held}\"")
    caught("pack"): add_unit(1, 0, 10 * TILE, 10 * TILE)
    let words = after(): add_unit(1, 0, 10 * TILE, 10 * TILE)
    check(find_string(words, "too many: 4") >= 0, "and says the pack\'s words: \"{words}\"")
    lua_load_pack("u", [ "u.lua" ], [ "function invariants() set_pop(0, 1) end" ], L_BUDGET_LOAD)
    lua_freeze()
    caught("pack"): pass()  // (only reads: a pack's invariants that writes is a break, and the sim is untouched)
    check(l_packs[1].error == "", "and the pack runs on")
    lua_on = false

// A builder on its way to a site others finish, with no other site near and no job to go back to, stops where it is
// with no job, not walking on to the finished building (#214).
def test_builder_stops():
    tiny_world()
    b_done[0] = 1
    u_task[0] = BUILD
    u_target[0] = b_id[0]
    u_home[0] = -1
    u_moving[0] = 1
    u_wx[0] = 5 * TILE
    u_wy[0] = 6 * TILE
    build_job(0)
    check(u_task[0] == T_NONE and u_moving[0] == 0, "a builder whose site is finished on its way stops where it is (task {u_task[0]}, moving {u_moving[0]})")

// An idle carrier on a door tile steps off it: onto a free road tile beside it if there is one, else onto free ground,
// never staying in the doorway for want of a road (#216).
def test_aside_off_door():
    tiny_world()
    walks = [ map(W * H): 1 ]
    for(footprint(0)) c: walks[0][c] = 0
    roomy = []
    tight = []
    make_room()
    lane_base = [ 0, 0 ]
    occupied = map(W * H): 0
    for(footprint(0)) c: occupied[c] = b_id[0]
    road = []
    bt_road = [ -1 ]  // (the store is no road plan)
    let door = door_cell(0)
    u_x[0] = (door % W) * TILE + TILE / 2
    u_y[0] = (door / W) * TILE + TILE / 2
    let to = aside_cell(0, door, [ door ])
    check(to >= 0 and to != door and occupied[to] == 0 and max(abs(to % W - door % W), abs(to / W - door / W)) == 1,
          "with no road near, a carrier in a doorway steps onto free ground beside it ({door} -> {to})")
    road = map(W * H): 0
    let rc = door + 2  // (two to the right: free road one ring further than the free ground)
    road[rc] = 1
    let on_ring1 = aside_cell(0, door, [ door ])
    check(on_ring1 >= 0 and road[on_ring1] == 0, "free ground beside it comes before a road two tiles off ({on_ring1})")
    road[door + 1] = 1
    check(aside_cell(0, door, [ door ]) == door + 1, "and a free road tile beside it before free ground ({aside_cell(0, door, [ door ])})")
    // A wall to its right: the free road and ground past it aren't a step away, so it steps left (#216).
    for(3) k: walks[0][door - W + 1 + k * W] = 0
    for(3) k: walks[0][door - W + 2 + k * W] = 0
    roomy = []
    tight = []
    make_room()
    road[door + 1] = 0
    road[door + 3] = 1
    let past_wall = aside_cell(0, door, [ door ])
    check(past_wall >= 0 and past_wall % W < door % W + 1, "with a wall beside it, it steps the other way, not round the wall ({past_wall})")

test_invariants()
test_pack()
test_builder_stops()
test_aside_off_door()
print "test_invariants: {passes} passed, {fails} failed"
