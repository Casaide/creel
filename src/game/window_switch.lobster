// The window while playing (#223): fullscreen or not, and the keys that switch it (game/window_mode.lobster starts it).

var window_fullscreen = false
var window_shown = int2_0
var window_toggles = []::float  // fsat:<seconds>,<seconds>: switch then, whatever the keys (tests and captures)
var window_report = ""          // fsreport:<file>: write each size the window takes
var window_sizes = ""

def window_combo() -> bool:
    if gl.button("return") != 1: return false
    return gl.button("left gui") >= 1 or gl.button("right gui") >= 1 or gl.button("left alt") >= 1 or gl.button("right alt") >= 1

def window_set(on:bool):
    window_fullscreen = on
    gl.fullscreen(if on: gl.window_init_fullscreen else: 0)

// The player's switch: the Settings row and the keys. Kept for next time.
def window_toggle():
    window_set(not window_fullscreen)
    windowed_setting = not window_fullscreen
    volume_save()

// Once a frame, in the lobby and in a match. (The window's new size comes in a moment later: everything reads
// gl.window_size each frame, and the ground's cached picture checks it too.)
def window_tick():
    if window_combo(): window_toggle()
    if window_toggles.length and seconds_elapsed() >= window_toggles[0]:
        window_toggles.remove(0)
        window_set(not window_fullscreen)
    if window_shown != gl.window_size():
        window_shown = gl.window_size()
        if window_report != "":
            window_sizes += "window: {window_shown} fullscreen {window_fullscreen}\n"
            write_file(window_report, window_sizes, 0, 1)
