// Fullscreen or a window (#223): desktop fullscreen by default (no display mode change, the Mac gives it its own Space, as
// Game Mode expects), the window with `windowed` or the setting. Tests, captures and tools stay in a window, unless they
// ask for `fullscreen`. Cmd or Alt + Enter switches while playing.

let WINDOW_TOOLS = [ "windowed", "mute", "selftest", "padtest", "labtest", "prebake", "vbcheck", "propframes", "loadershot", "wheelshot", "savegame", "tillend", "lobbyloop", "lobbytree" ]
let WINDOW_TOOL_KEYS = [ "shot", "perf", "reload", "record", "lookframes", "meshes", "dump", "treehover" ]

def starts_fullscreen(args:[string], setting_windowed:bool) -> bool:
    if (exists(args) a: a == "fullscreen"): return true
    if setting_windowed: return false
    return not exists(args) a:
        let key, val = split_string(a, ":")
        (exists(WINDOW_TOOLS) t: t == a) or (val != "" and exists(WINDOW_TOOL_KEYS) t: t == key)

def window_flags(no_vsync:bool, fullscreen:bool) -> int:
    var flags = 0
    if no_vsync: flags |= gl.window_init_no_vsync
    if fullscreen: flags |= gl.window_init_fullscreen
    return flags
