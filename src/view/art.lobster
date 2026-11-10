// ------------------------------------------------------------------ the parts' bakes (PartShape's side of it)
// Every part bake in the pack: its frame, its origin (texture px of the part's 0,0) and scale
// (texture px a part unit); legs' soles and spans; the rigs the bakes made (sockets, hips, depth,
// facing directions; rigs.json); which parts have hand-built models. A part's bake is found by its
// bake key: its id and the colours of the channels its shapes use (the team's is always the key).

class Bake:
    ox:float
    oy:float
    scale:float

// The art scale (D-173, "heroic at 2x"): art pixels a canvas unit. The world stays in the art pixels it had before
// (ART_BASE: a tile is 96 x 48), so sprites baked at ART_SCALE draw at 1 / ART_K of their texture's size. On a high-DPI
// screen the game raises both at its start, so a baked pixel is a device pixel (art_density in game.lobster, #358).
let ART_BASE = 1.5
var ART_SCALE = 3.0
var ART_K = ART_SCALE / ART_BASE

let bakes = dictionary<string, Bake>(8191)

def jf(o:JV, k:string, fallback:float) -> float:
    let v = get(o, k)
    return if v: as_float(v) else: fallback

// ---- colours (UnitView.colours_for)

def hex_of(html:string) -> string:  // "#RRGGBB(AA)" -> "rrggbb", as Color.to_html(false)
    let h = if html.length and html[0] == '#': substring(html, 1, html.length - 1) else: html
    return lowercase(substring(h, 0, 6))

// ---- bake keys and lookups (PartShape)

var type_gen = 0  // bumped by the game when any unit type changes its look mid-match (the views rebuild)
