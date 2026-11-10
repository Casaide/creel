// ------------------------------------------------------------------ Rng (src/rng.gd): xorshift32, FNV-1a

let RNG_MASK = 0xFFFFFFFF

class Rng:
    state:int

def new_rng(seed_value:int) -> Rng:
    let s = seed_value & RNG_MASK
    return Rng { if s == 0: 0x9E3779B9 else: s }

// FNV-1a 32-bit over the string's UTF-8 bytes.
def hash_text(text:string) -> int:
    var h = 0x811C9DC5
    for(text.length) n:
        h = h ^ (text[n] & 0xFF)
        h = (h * 0x01000193) & RNG_MASK
    return h

def next_u32(r:Rng) -> int:
    var x = r.state
    x ^= (x << 13) & RNG_MASK
    x ^= x >> 17
    x ^= (x << 5) & RNG_MASK
    r.state = x & RNG_MASK
    return r.state

def range_int(r:Rng, lo:int, hi:int) -> int: return lo + next_u32(r) % (hi - lo + 1)
def chance(r:Rng, percent:int) -> bool: return next_u32(r) % 100 < percent
def rpick(r:Rng, items):
    assert items.length
    return items[next_u32(r) % items.length]

def shuffled(r:Rng, items):
    let out = copy(items)
    var i = out.length - 1
    while i > 0:
        let j = next_u32(r) % (i + 1)
        let t = out[i]
        out[i] = out[j]
        out[j] = t
        i--
    return out
