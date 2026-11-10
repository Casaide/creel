// ------------------------------------------------------------------ how fast a shot looks
// View only (#175): a shot is drawn over part of its flight, launched late, and lands on the sim's tick. When it lands, and
// so dodging and balance, is the sim's alone: the sim never reads this.

let SHOT_DRAWN_SHARE = 0.5  // of its flight a shot is seen flying
let SHOT_DRAWN_MIN = 0.2    // seconds, at least (a short shot isn't a flicker)

// Seconds a flight of that many seconds is seen for.
def shot_drawn_time(flight:float) -> float: return min(flight, max(flight * SHOT_DRAWN_SHARE, SHOT_DRAWN_MIN))

// How far along its way a shot is drawn, that many seconds into its flight (1: landed); below 0: not yet launched.
def shot_drawn_u(elapsed:float, flight:float, gun = false) -> float:
    let drawn = if gun: flight else: shot_drawn_time(flight)  // (a gun's flash and its shell go together: all its flight, #265)
    if drawn <= 0.0: return 1.0
    return min(1.0, (elapsed - (flight - drawn)) / drawn)

// ------------------------------------------------------------------ what a shot left standing in the ground looks like

class ShotLine:
    a:float2
    b:float2
    w:float
    col:float4
    ball:bool  // a round end at b

// A plain shot stuck in the ground at pos, its other end at pos + up, in width w and colour col.
def stuck_lines(pos:float2, up:float2, w:float, col:float4, alpha:float) -> [ShotLine]:
    return [ ShotLine { pos, pos + up, min(w, 1.3), float4 { col.x * 0.65, col.y * 0.65, col.z * 0.65, alpha }, false } ]

// An arrow's lines, its point at tip and its nock at tail: a thin shaft, small fletching, and if its point shows a head narrowing to it.
def arrow_lines(tip:float2, tail:float2, w:float, shaft:float4, head:float4, fletch:float4, point_shows:bool) -> [ShotLine]:
    let d = tail - tip
    let len = magnitude(d)
    let n = d / max(len, 0.0001)
    let flet = min(1.6, len * 0.3)
    let out = [ ShotLine { tip, tail, w, shaft, false },
                ShotLine { tail - n * flet, tail, w * 2.0, fletch, false } ]
    if point_shows:
        out.push(ShotLine { tip + n * 0.7, tip + n * 1.6, w * 1.7, head, false })
        out.push(ShotLine { tip, tip + n * 0.8, w * 0.8, head, false })
    return out
