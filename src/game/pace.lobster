// ------------------------------------------------------------------ frame pacing: how often the window draws
// A match at 60 frames a second, the lobby's pages at 30 (nothing there moves fast), a window in the background at
// 10, and a minimised window not drawn at all (Lobster sleeps a tenth of a second a frame then). A match's sim and
// network go on at their pace whatever the frames: each frame steps the sim for the time it took (lockstep's turns
// run two ahead, 400 ms, so a frame every 100 ms keeps up).
// The laptop ran hot (2026-11-03): the idle title screen took 11% of a core, nearly what a match did.

let PACE_MATCH = 60.0
let PACE_MENU = 30.0
let PACE_IDLE = 15.0        // the title screen left alone (its armies only idle)
let PACE_IDLE_AFTER = 2.0   // seconds without the mouse or the pad first
let PACE_BACKGROUND = 10.0  // a window without the focus, or hidden behind others
var pace_input_at = 0.0
var pace_fps = PACE_MATCH
var pace_background = true  // (tests and captures keep their pace: game.lobster)

def pace(fps:float):
    pace_fps = fps
    let bg = pace_background and not gl.window_focused()
    gl.set_target_delta_time(1.0 / (if bg: min(fps, PACE_BACKGROUND) else: fps))

// The lobby's pace this frame: the title at PACE_IDLE once nobody has touched it for a moment (input: they did now).
def pace_menu(title:bool, input:bool):
    let now = seconds_elapsed()
    if input: pace_input_at = now
    pace(if title and now - pace_input_at > PACE_IDLE_AFTER: PACE_IDLE else: PACE_MENU)

// Whether to draw this frame (a minimised window shows nothing); a match's pace for the window's focus.
def drawing() -> bool:
    pace(pace_fps)
    return gl.visible()
