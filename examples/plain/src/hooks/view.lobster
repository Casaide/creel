// What a game must define for Creel's world drawing and controls to compile (game/world_draw.lobster,
// game/controls.lobster). These do nothing or give the plainest answer, which is a valid game.

// A wall look's tile for the neighbours it joins (a bit per neighbour): its name in the pack, and its frame (-1: none,
// draw it from its arms).
def akb_tile_name(look:string, links:int) -> string: return "{look}@L{links}"
def akb_wall_tile(look:string, links:int) -> int: return -1

// Paths worn between buildings: re-plan them (true if anything was rebuilt), and is this tile on one?
def refresh_paths() -> bool: return false
def on_path(t:float2) -> bool: return false

// Town life: add to the draw list, then draw what goes over it.
def collect_town(): return
def draw_town(): return

// Cracks over building slot b when it's damaged.
def draw_cracks_of(b:int): return

// The top bar, and the HUD's scale.
def draw_topbar(speed:float, paused:bool): return
def hud_s() -> float: return ui()
