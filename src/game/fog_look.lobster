// How the fog looks (#334): one grey fog. The land is no secret: ground, trees, gold, stone, bushes and the map's
// doodads show everywhere, as the map was made or as you last saw them, dimmed where you can't see now. What the fog
// hides is the other side: their units, and their buildings until you've seen them. Never-seen land looks just like
// land you've seen and walked away from; no black.

let FOG_SEEN = 2  // fog[p][c]: 0 never seen, 1 seen before, 2 in sight (lib/fog.lobster)

def fog_in_sight(f:int) -> bool: return f == FOG_SEEN

// The ground's colour, times this.
def fog_ground_shade(f:int) -> float: return if fog_in_sight(f): 1.0 else: 0.55

// The fog mesh's darkness over a tile.
def fog_dark(f:int) -> float: return if fog_in_sight(f): 0.0 else: 0.45

// A resource's or doodad's brightness.
def fog_prop_shade(f:int) -> float: return if fog_in_sight(f): 1.0 else: 0.6

// Resources and doodads show under any fog.
def fog_shows_land(f:int) -> bool: return f >= 0
