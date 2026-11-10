// ------------------------------------------------------------------ fixed.gd

def sin_a(angle:int) -> int: return SIN[angle & 255]
def cos_a(angle:int) -> int: return SIN[(angle + 64) & 255]

// Floor of the square root, for n >= 0 (Fixed.isqrt: Newton's steps from a power of two above the root).
def isqrt(n:int) -> int:
    if n < 2: return n
    var m = n
    var b = 1
    if m >= (1 << 32):
        m = m >> 32
        b += 16
    if m >= (1 << 16):
        m = m >> 16
        b += 8
    if m >= (1 << 8):
        m = m >> 8
        b += 4
    if m >= (1 << 4):
        m = m >> 4
        b += 2
    if m >= (1 << 2):
        b += 1
    var x = 1 << b
    var y = (x + n / x) >> 1
    while y < x:
        x = y
        y = (x + n / x) >> 1
    return x

def contains(xs:[int], v:int) -> bool:
    for(xs) x:
        if x == v: return true
    return false

def dist2(ax:int, ay:int, bx:int, by:int) -> int:
    let dx = bx - ax
    let dy = by - ay
    return dx * dx + dy * dy

def mix(h:int, v:int) -> int:
    let a = ((h ^ (v & MASK)) * FNV_PRIME) & MASK
    return ((a ^ ((v >> 32) & MASK)) * FNV_PRIME) & MASK
