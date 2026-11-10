// ------------------------------------------------------------------ what the view and the controls share
// The state every way of playing reads and sets (mouse and keys, a pad, touch) and every panel draws from: who you are,
// where the camera is, what's selected, what the next click means. View only: none of it is the sim's, none is saved.

var ME = 0  // the side you command (1 for the one who joins a network match)

// The camera.
var cam = float2_0  // art px at the middle of the window
var zoom = 2.0  // screen px per art px

def to_screen(p:float2) -> float2: return (p - cam) * zoom + float(gl.window_size()) / 2.0
def from_screen(p:float2) -> float2: return (p - float(gl.window_size()) / 2.0) / zoom + cam

// What's selected.
var selected = []::int  // unit ids
var sel_building = 0  // building id
var sel_foreign = 0  // a unit that isn't mine, shown in the panel: view-only, so never in selected

// What the next click means.
var build_menu = false
var placing = -1  // building type being placed
var wall_from = int2 { -1, -1 }  // where a wall's drag began (a cell), while placing walls or gates (bt_line)
var arming_attack = false  // the Attack-move button (or R): the next left click is where
var arming_ability = false  // the ability button: the next left click is where
var pad_lb_held = false  // LB held on a pad (game/pad.lobster): orders queue, A adds to the selection

// What's open over the world.
var menu_open = false  // the pause menu (Esc)
var tree_open = false  // the tech tree page
var typing_text = false  // a text field has the keys

var touch_play = false  // touch: play by touch, through the pad's controls (game/touch.lobster; the Android build)
