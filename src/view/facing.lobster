// ------------------------------------------------------------------ which way a walking unit faces
// Shared by the game and test_formations. View only: floats, never read by the sim.

// The camera's elevation is a setting (30 degrees unless a game says otherwise): a game that wants another sets
// these before anything is baked or drawn, all from the one angle e: iso_k = 0.048 * sin(e) here, vx_ELEV = e
// (view/voxel), VM_VIEW.x = -e (view/voxel_mesh), LEVEL_PX = 20 * cos(e) / cos(30) (game/relief).
var iso_k = 0.024  // how far down the screen a milli-tile along x or y goes (0.048 across: a tile is 2:1 at 30 degrees)

def iso(x:float, y:float) -> float2: return float2 { (x - y) * 0.048, (x + y) * iso_k }

def iso_inv(p:float2) -> float2:
    let a = p.x / 0.048
    let b = p.y / iso_k
    return float2 { (a + b) / 2.0, (b - a) / 2.0 }

def dir_of(v:float2) -> int:
    if v.x == 0.0 and v.y == 0.0: return -1
    let a = atan2(normalize(v))
    return (int(floor(a / 45.0 + 0.5)) % 8 + 8) % 8

// Facing d, now heading along v: d kept until v is clearly past the next direction's edge (so a heading along an edge doesn't flip).
def dir_settled(d:int, v:float2) -> int:
    let nd = dir_of(v)
    if nd < 0 or nd == d: return nd
    let off = abs((atan2(normalize(v)) - float(d) * 45.0 + 540.0) % 360.0 - 180.0)
    return if off > 32.0: nd else: d

let WITH_BLOCK = 400  // milli-tiles from its place: nearer than this a unit in a block is only keeping up with it

// Is unit i going along with its block, not at a foe or back to its place? (#252)
def with_block(i:int) -> bool:
    let b = u_block[i] - 1
    return b >= 0 and fb_state[b] == BLOCK_MARCHING and fb_held[b] == 0 and u_foe[i] == 0 and dist2(u_x[i], u_y[i], fb_x[b] + u_bx[i], fb_y[b] + u_by[i]) <= WITH_BLOCK * WITH_BLOCK

// Is unit i walking this tick (by its own order: the crowd's pushes move it too, every way, and don't count), and the way
// it then faces, from d: where it's making for, not this tick's step; a unit going along with its block as the block does. (px, py): where it was.
def unit_walk(i:int, d:int, px:int, py:int) -> bool, int:
    if u_moving[i] != 1 or (px == u_x[i] and py == u_y[i]): return false, d
    let b = u_block[i] - 1
    let nd = dir_settled(d, if with_block(i): iso(float(fb_dx[b]), float(fb_dy[b])) else: iso(float(u_wx[i] - u_x[i]), float(u_wy[i] - u_y[i])))
    return true, if nd >= 0: nd else: d
