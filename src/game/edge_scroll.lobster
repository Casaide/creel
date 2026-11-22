// ------------------------------------------------------------------ edge scrolling (#175)
// Which way the camera pans with the mouse against the window's edge: -1, 0 or 1 on each axis. Pure (no window), so
// check.sh tests it headless (test_edge_scroll); scroll (game/controls) moves the camera by it.
// In fullscreen the OS holds the mouse on the screen, so against the left or top edge it reads exactly 0: that is an
// edge. Only the mouse at 0, 0 itself (where it reads before it has moved, and off the window) and beyond the window
// pans nowhere, so a mouse working in another window doesn't drag the camera.

let EDGE_BAND = 4.0  // px from the window's side that count as its edge

def edge_pan(m:float2, ws:float2) -> float2:
    if m.x < 0.0 or m.y < 0.0 or m.x >= ws.x or m.y >= ws.y: return float2_0
    if m.x == 0.0 and m.y == 0.0: return float2_0
    var d = float2_0
    if m.x < EDGE_BAND: d.x -= 1.0
    if m.y < EDGE_BAND: d.y -= 1.0
    if m.x >= ws.x - EDGE_BAND: d.x += 1.0
    if m.y >= ws.y - EDGE_BAND: d.y += 1.0
    return d
