// ------------------------------------------------------------------ Godot's RandomNumberGenerator for the models
// The art seeds Godot's generator to shape a fleece, a rock, a tree (cosmetic, view side: never the sim, which
// has src/rng.gd's). view/node.lobster has the generator (Pcg: pcg_seed, randf, randf_range, randi); these are
// the rest of it, number for number (rng_check.lobster holds them to rng_dump.gd's).

def grng(seed:int) -> Pcg: return pcg_seed(seed)  // RandomNumberGenerator.new() with .seed = seed

def randi_range(r:Pcg, lo:int, hi:int) -> int:
    if lo == hi: return lo
    let bound = abs(lo - hi) + 1
    let threshold = ((-bound) & M32) % bound
    while true:
        let v = pcg_next(r)
        if v >= threshold: return v % bound + min(lo, hi)
    return lo

// Normal (Box-Muller), as RandomPCG::randfn (in floats).
def randfn(r:Pcg, mean:float, dev:float) -> float:
    var t = randf(r)
    if t < 0.00001: t += 0.00001
    return f32(mean + dev * (sqrt(-2.0 * log(t)) * cos(360.0 * randf(r))))
