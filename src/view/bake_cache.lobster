// The bakes' shared settings: the cache (bake_cache/: buildings, props and voxel units baked once are kept on disk,
// and loaded by a later start), the shipped bakes (baked/, by prebake.sh), and the progress a long bake draws.
// BAKE_VERSION goes up when the building or prop models or their baker change, so old bakes aren't reused.

let BAKE_VERSION = 24              // (24: trees, rocks, stone and gold built voxel by voxel, #410; 23: the bake density in the keys, a high-DPI screen bakes at its own, #358; 22: the future architecture's own buildings, #248; 21: no floating or lit pieces in stages and rubble, scorch by size; 20: its beam stops at the posts; 19: the palisade gate's posts apart; 18: gates' shadows apart; 17: a gate's towers and middle apart; 16: a gate tower's frame only its tower; 15: walls' shadows apart, the turned post at corners; 14: a wall post turned for diagonal runs; 13: softened: smooth normals, a smooth light ramp, a soft outline only outside; 12: their contact shadows; 11: buildings and props as voxels, D-203; 2: Godot's full PI in the models; 3: engines' members in front or behind; 4: whole-pixel frames as Godot's, 2026-10-27; 7: Godot's bicubic shrink in pixelize, in Godot's square frame; 8: the art at 2x (D-173), 2026-10-28; 9: the bears' neck leans with them, 2026-10-31; 10: the bears lofted (D-189))
var bake_cache_dir = "bake_cache"  // (play.sh makes it; Lobster can't make a folder)
var bake_shipped_dir = "baked"     // the buildings and props a build ships, baked by prebake.sh (read before bake_cache/)

// While the art bakes (a first start with no cache: minutes), the window stays alive: ten times a second a frame
// says how far it is, and the window's events are read, so closing it (or Ctrl-C, which SDL makes a quit) stops the
// baking (bake_quit; the game then quits), and macOS doesn't call it unresponsive when it's clicked or resized. The
// game turns it on; checks bake without it.
let BAKE_FRAME_EVERY = 0.1
var bake_live = false
var bake_loading = false  // a match's load, when a long bake may draw in its middle (bake_pulse); not during play
var bake_quit = false
var bake_done = 0  // things baked since the game began
// The progress drawn by the game's match loader while it's up (game.lobster sets it to fe_loader, game/lobby.lobster):
// its bar runs from bake_progress_from to bake_progress_to over this bake.
def bake_progress_fn(status:string, frac:float) -> void
var bake_progress:bake_progress_fn = fn(s, f): pass()
var bake_progress_on = false
var bake_progress_from = 0.0
var bake_progress_to = 1.0
var bake_what = ""  // what's baking (the game says: "the armies", "the town")
var bake_total = 0  // how many things this bake has to make (0: not counted), and how many it has
var bake_count = 0
var bake_said = 0.0

def bake_frame():
    gl.switch_to_framebuffer(nil)
    gl.ortho()
    gl.clear(float4 { 0.07, 0.06, 0.05, 1.0 })
    gl.set_shader("color")
    let ws = float(gl.window_size())
    if bake_progress_on:  // the game's match loader, its bar this bake's share
        let done = if bake_total > 0: float(bake_count) / float(bake_total) else: 0.0
        bake_progress("Making {bake_what}", bake_progress_from + (bake_progress_to - bake_progress_from) * done)
        if not gl.frame(): bake_quit = true
        bake_said = seconds_elapsed()
        return
    gl.set_font_size(int(max(16.0, ws.y / 36.0)))
    gl.color(float4 { 0.92, 0.86, 0.7, 1.0 }):
        gl.translate(float2 { ws.x * 0.08, ws.y * 0.45 }):
            gl.text(if bake_total > 0: "Making {bake_what}: {bake_count} of {bake_total}" else: "Making {bake_what}: {bake_done} done")
    gl.color(float4 { 0.6, 0.56, 0.48, 1.0 }):
        gl.translate(float2 { ws.x * 0.08, ws.y * 0.45 + ws.y / 22.0 }):
            gl.text("The first start bakes every picture; later starts take them from bake_cache. Close the window to stop.")
    if not gl.frame(): bake_quit = true
    bake_said = seconds_elapsed()

def bake_due() -> bool:
    return bake_live and not bake_quit and seconds_elapsed() - bake_said >= BAKE_FRAME_EVERY

// Between two things baked.
def bake_breath():
    bake_done++
    if bake_due(): bake_frame()

// In the middle of one: only where no framebuffer is bound and nothing the frame draws is half made.
def bake_pulse():
    if bake_loading and bake_due(): bake_frame()

// Where x is in xs (-1: not there).
def find_s(xs:[string], x:string) -> int:
    for(xs) v, i:
        if v == x: return i
    return -1

// A part's tags (parts.json).
def ptags_of(id:string) -> [string]: return gstrs(part(id), "tags")

// Godot's String.hash (djb2 over the characters): the doodads' seeds (kept bit for bit).
def jstr_hash(s:string) -> int:
    var h = 5381
    let cs = string_to_unicode(s)
    for(cs) c: h = ((h << 5) + h + c) & 0xFFFFFFFF
    return h
