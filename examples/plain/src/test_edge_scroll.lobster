// Edge scrolling (#175): which way the camera pans with the mouse at each edge, headless. ../../../check.sh runs it.
//   lobster test_edge_scroll.lobster
import from "../../../src"
import std
import vec
import game.edge_scroll

// A fullscreen window on a Retina Mac: 1512 x 982 points, 3024 x 1964 px. The mouse reads in px, held on the screen,
// so its last px at the right and bottom is 2 short of the size (the last point times 2).
let ws = float2 { 3024.0, 1964.0 }

var fails = 0
var passes = 0

def check(m:float2, want:float2, what:string):
    let got = edge_pan(m, ws)
    if got == want: passes++
    else:
        fails++
        print "FAIL: {what}: the mouse at {m} pans {got}, not {want}"

check(float2 { 1512.0, 982.0 }, float2_0, "the middle")
check(float2 { 0.0, 982.0 }, float2 { -1.0, 0.0 }, "held against the left edge")
check(float2 { 1512.0, 0.0 }, float2 { 0.0, -1.0 }, "held against the top edge")
check(float2 { 3022.0, 982.0 }, float2 { 1.0, 0.0 }, "held against the right edge")
check(float2 { 1512.0, 1962.0 }, float2 { 0.0, 1.0 }, "held against the bottom edge")
check(float2 { 3022.0, 1962.0 }, float2 { 1.0, 1.0 }, "the bottom right corner")
check(float2 { 0.0, 1962.0 }, float2 { -1.0, 1.0 }, "the bottom left corner")
check(float2 { 3022.0, 0.0 }, float2 { 1.0, -1.0 }, "the top right corner")
check(float2 { 2.0, 2.0 }, float2 { -1.0, -1.0 }, "by the top left corner")
check(float2 { 10.0, 982.0 }, float2_0, "near the left edge but not on it")
check(float2 { 0.0, 0.0 }, float2_0, "0, 0: not moved yet, or off the window")
check(float2 { -1.0, -1.0 }, float2_0, "never moved")
check(float2 { 3024.0, 982.0 }, float2_0, "past the right edge")
print "test_edge_scroll: {passes} passed, {fails} failed"
