// Sound synthesis for the game, offline (render_audio.lobster), never in the game.
// A sound is a vector of floats at RATE Hz, mono, in roughly -1..1. Everything is deterministic: noise comes from the
// seeded rng below (Mersenne Twister, as the sounds were first rendered with), so a re-render gives the same files.
// A "contour" is a vector with one value per sample (curve() makes one), for a pitch or cutoff that moves.

let RATE = 44100
let PI = 3.141592653589793
let TAU = 6.283185307179586
let E = 2.718281828459045

def rsin(x:float) -> float: return sin(x * 57.29577951308232)  // (Lobster's sin and cos take degrees)

def rcos(x:float) -> float: return cos(x * 57.29577951308232)

def exp(x:float) -> float: return pow(E, x)

def tanh(x:float) -> float:
    let a = exp(x)
    let b = exp(-x)
    return (a - b) / (a + b)

// ------------------------------------------------------------------ the rng

var mt:[int] = []
var mti = 624

def seed_rng(seed:int):
    mt = [].vector_capacity(624)
    mt.push(19650218)
    for(623) k: mt.push((1812433253 * (mt[k] ^ (mt[k] >> 30)) + k + 1) & 0xFFFFFFFF)
    var i = 1
    for(624):
        let p = mt[i - 1]
        mt[i] = ((mt[i] ^ ((p ^ (p >> 30)) * 1664525)) + seed) & 0xFFFFFFFF
        i++
        if i >= 624:
            mt[0] = mt[623]
            i = 1
    for(623):
        let p = mt[i - 1]
        mt[i] = ((mt[i] ^ ((p ^ (p >> 30)) * 1566083941)) - i) & 0xFFFFFFFF
        i++
        if i >= 624:
            mt[0] = mt[623]
            i = 1
    mt[0] = 0x80000000
    mti = 624

def next32() -> int:
    if mti >= 624:
        for(624) k:
            let y = (mt[k] & 0x80000000) | (mt[(k + 1) % 624] & 0x7FFFFFFF)
            mt[k] = mt[(k + 397) % 624] ^ (y >> 1) ^ (if y & 1 == 1: 0x9908B0DF else: 0)
        mti = 0
    var y = mt[mti]
    mti++
    y = y ^ (y >> 11)
    y = y ^ ((y << 7) & 0x9D2C5680)
    y = y ^ ((y << 15) & 0xEFC60000)
    return y ^ (y >> 18)

def rand01() -> float:
    let a = next32() >> 5
    let b = next32() >> 6
    return (a * 67108864.0 + b) / 9007199254740992.0

def j(lo:float, hi:float) -> float: return lo + (hi - lo) * rand01()

def randbelow(n:int) -> int:
    var k = 0
    while(n >> k) > 0: k++
    var r = next32() >> (32 - k)
    while r >= n: r = next32() >> (32 - k)
    return r

def randint(lo:int, hi:int) -> int: return lo + randbelow(hi - lo + 1)

// ------------------------------------------------------------------ sources

def seconds(s:float) -> int: return int(s * RATE)

def zeros(n:int) -> [float]: return map(n): 0.0

def curve(n:int, f) -> [float]: return map(n) i: f(float(i) / RATE)

def noise(n:int) -> [float]: return map(n): j(-1.0, 1.0)

def sine(n:int, freq:float) -> [float]:
    let inc = TAU * freq / RATE
    var ph = 0.0
    return map(n):
        let v = rsin(ph)
        ph += inc
        v

def sinec(freq:[float]) -> [float]:
    var ph = 0.0
    return map(freq) f:
        let v = rsin(ph)
        ph += TAU * f / RATE
        v

// A band-limited sawtooth (summed harmonics).
def saw(n:int, freq:float, harmonics:int) -> [float]:
    var ph = 0.0
    return map(n):
        ph += TAU * freq / RATE
        var v = 0.0
        for(harmonics) k:
            if (k + 1) * freq <= RATE * 0.45: v += 1.0 / (k + 1) * rsin(ph * (k + 1))
        v * 0.6

// A glottal-ish pulse: a raised-cosine bump of `width` of each period (a voice source).
def pulsec(freq:[float], width:float) -> [float]:
    var ph = 0.0
    return map(freq) f:
        ph += f / RATE
        if ph >= 1.0: ph -= 1.0
        if ph < width: 0.5 - 0.5 * rcos(TAU * ph / width) else: 0.0

def pulse(n:int, freq:float, width:float) -> [float]: return pulsec(map(n): freq, width)

// ------------------------------------------------------------------ envelopes

// Attack, decay and release in seconds; the release ends at the end.
def env(n:int, attack:float, dec:float, sustain = 0.0, release = 0.0) -> [float]:
    let a = max(1, seconds(attack))
    let d = max(1, seconds(dec))
    let r = max(1, seconds(release))
    let h = n - r
    return map(n) i:
        var v = sustain
        if i < a: v = float(i) / a
        elif i < a + d: v = 1.0 - (1.0 - sustain) * (i - a) / d
        if i > h: v *= max(0.0, 1.0 - float(i - h) / r)
        v

// A fast attack then an exponential fall; rate in 1/s.
def decay(n:int, rate:float, attack = 0.002) -> [float]:
    let a = max(1, seconds(attack))
    return map(n) i: min(1.0, float(i) / a) * exp(-rate * i / RATE)

// Rises over `up` seconds, falls over the last `down` (a bowed or blown note).
def swell(n:int, up:float, down:float) -> [float]:
    let a = max(1, seconds(up))
    let r = max(1, seconds(down))
    return map(n) i:
        var v = min(1.0, float(i) / a)
        if i > n - r: v *= float(n - i) / r
        v

def mul(a:[float], b:[float]) -> [float]: return map(min(a.length, b.length)) i: a[i] * b[i]

def gain(a:[float], g:float) -> [float]: return map(a) x: x * g

def add(bufs:[[float]]) -> [float]:
    var n = 0
    for(bufs) b: n = max(n, b.length)
    let out = zeros(n)
    for(bufs) b:
        for(b) x, i: out[i] += x
    return out

// Adds src into dst starting at sample `at`; past the end it wraps (for loops) or grows.
def mix_into(dst:[float], src:[float], at:int, g = 1.0, wrap = false):
    if not wrap:
        while dst.length < at + src.length: dst.push(0.0)
    let n = dst.length
    for(src) x, i:
        let k = at + i
        dst[if k >= n: k % n else: k] += x * g

def concat(a:[float], b:[float]) -> [float]: return append(a, b)

def delay_start(buf:[float], s:float) -> [float]: return append(zeros(seconds(s)), buf)

// ------------------------------------------------------------------ filters

// One-pole low-pass.
def lowpass(buf:[float], cutoff:float) -> [float]:
    let a = 1.0 - exp(-TAU * cutoff / RATE)
    var y = 0.0
    return map(buf) x:
        y += a * (x - y)
        y

def lowpassc(buf:[float], cutoff:[float]) -> [float]:
    var y = 0.0
    return map(buf) x, i:
        y += (1.0 - exp(-TAU * cutoff[i] / RATE)) * (x - y)
        y

def highpass(buf:[float], cutoff:float) -> [float]:
    let lo = lowpass(buf, cutoff)
    return map(buf) x, i: x - lo[i]

// A resonant band-pass (biquad).
def bandpass(buf:[float], centre:float, q:float, g = 1.0) -> [float]:
    let w = TAU * centre / RATE
    let alpha = rsin(w) / (2.0 * q)
    let a0 = 1.0 + alpha
    let b0 = alpha / a0
    let b2 = -alpha / a0
    let a1 = -2.0 * rcos(w) / a0
    let a2 = (1.0 - alpha) / a0
    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0
    return map(buf) x:
        let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        y * g

def bandpassc(buf:[float], centre:[float], q:float, g = 1.0) -> [float]:
    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0
    return map(buf) x, i:
        let w = TAU * centre[i] / RATE
        let alpha = rsin(w) / (2.0 * q)
        let a0 = 1.0 + alpha
        let y = (alpha * x - alpha * x2 + 2.0 * rcos(w) * y1 - (1.0 - alpha) * y2) / a0
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        y * g

// One partial or formant: hz, then decay per second and amp (modal), or q and gain (formants).
def p3(a:float, b:float, c:float) -> float3: return float3 { a, b, c }

// Sums resonant band-passes (a throat, a body).
def formants(buf:[float], table:[float3]) -> [float]:
    let out = zeros(buf.length)
    for(table) t:
        for(bandpass(buf, t.x, t.y, t.z)) x, i: out[i] += x
    return out

// A struck body: decaying sine partials plus a click.
def modal(n:int, partials:[float3], strike:float) -> [float]:
    let out = zeros(n)
    for(partials) p:
        let inc = TAU * p.x / RATE
        var ph = j(0.0, TAU)
        for(n) i:
            out[i] += p.z * rsin(ph) * exp(-p.y * i / RATE)
            ph += inc
    if strike > 0.0:
        mix_into(out, mul(noise(seconds(0.004)), decay(seconds(0.004), 900.0, 0.0002)), 0, strike)
    return out

def soft_clip(buf:[float], drive = 1.5) -> [float]:
    let d = tanh(drive)
    return map(buf) x: tanh(x * drive) / d

// Schroeder: four combs in parallel then two all-passes, a soft room, not a hall.
def reverb(buf:[float], size:float, mix:float) -> [float]:
    let n = buf.length
    let wet = zeros(n)
    for([ 1116, 1188, 1277, 1356 ]) base:
        let l = int(base * (0.5 + size))
        let fb = 0.72 + 0.12 * size
        let line = zeros(l)
        var p = 0
        var lp = 0.0
        for(n) i:
            let y = line[p]
            lp += 0.6 * (y - lp)
            line[p] = buf[i] + lp * fb
            p++
            if p == l: p = 0
            wet[i] += y * 0.25
    for([ 225, 556 ]) l:
        let line = zeros(l)
        var p = 0
        for(n) i:
            let d = line[p]
            let x = wet[i]
            line[p] = x + d * 0.5
            wet[i] = d - x * 0.5
            p++
            if p == l: p = 0
    return map(buf) d, i: d * (1.0 - mix) + wet[i] * mix

// ------------------------------------------------------------------ levels and files

def peak(buf:[float]) -> float:
    var p = 0.000000001
    for(buf) x: p = max(p, abs(x))
    return p

def normalize(buf:[float], db:float) -> [float]: return gain(buf, pow(10.0, db / 20.0) / peak(buf))

// Cuts the silence a decay leaves at the end (keeps 20 ms after the last sound).
def trim_tail(buf:[float]) -> [float]:
    let th = pow(10.0, -3.0)
    var last = buf.length
    while last > 0 and abs(buf[last - 1]) < th: last--
    return buf.slice(0, min(buf.length, last + seconds(0.02)))

def fade_out(buf:[float], s:float) -> [float]:
    let n = buf.length
    let r = seconds(s)
    return map(buf) x, i: if i >= n - r: x * (n - i) / r else: x

// 16-bit PCM; mono when right is empty.
def write_wav(path:string, left:[float], right:[float]):
    let chans = if right.length > 0: 2 else: 1
    let n = if chans == 2: min(left.length, right.length) else: left.length
    let bytes = n * 2 * chans
    def sample(v:float) -> int: return if v >= 1.0: 32767 else: (if v <= -1.0: -32768 else: int(v * 32767.0))
    var s = ensure_size("", 44 + bytes, 0)
    var k = 0
    s, k = write_substring(s, k, "RIFF", false)
    s, k = write_int32_le(s, k, 36 + bytes)
    s, k = write_substring(s, k, "WAVEfmt ", false)
    s, k = write_int32_le(s, k, 16)
    s, k = write_int16_le(s, k, 1)
    s, k = write_int16_le(s, k, chans)
    s, k = write_int32_le(s, k, RATE)
    s, k = write_int32_le(s, k, RATE * 2 * chans)
    s, k = write_int16_le(s, k, 2 * chans)
    s, k = write_int16_le(s, k, 16)
    s, k = write_substring(s, k, "data", false)
    s, k = write_int32_le(s, k, bytes)
    for(n) i:
        s, k = write_int16_le(s, k, sample(left[i]))
        if chans == 2: s, k = write_int16_le(s, k, sample(right[i]))
    assert write_file(path, s, 0, 1)
