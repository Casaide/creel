// Instruments: a note in, a mono buffer out. Hand-made and acoustic by design (wood, hide, reed, bronze): the game's
// music and its jingles share these so the stings sit in the music.

// A plucked gut string (Karplus-Strong with a tuned fractional delay): a lute, a harp.
def pluck(freq:float, dur:float, vel = 1.0, bright = 0.6, sustain = 0.996) -> [float]:
    let n = seconds(dur)
    let l = float(RATE) / freq - 0.5
    let size = int(l) + 2
    let frac = l - int(l)
    let line = lowpass(noise(size), 1200.0 + 6000.0 * bright)  // a soft pick: fewer high partials
    var p = 0
    var prev = 0.0
    let raw = map(n):
        let a = line[p]
        let x = a + (line[(p + 1) % size] - a) * frac
        let y = sustain * 0.5 * (x + prev)
        prev = x
        line[p] = y
        p = (p + 1) % size
        y
    let out = add([ raw, bandpass(raw, 220.0, 0.8, 0.6) ])  // the sound box
    let tail = max(1, seconds(min(0.05, dur * 0.3)))
    for(tail) i: out[n - 1 - i] *= float(i) / tail
    return gain(out, vel * 0.9)

// A wooden flute: a near-sine with a touch of second partial, breath noise, slow vibrato.
def flute(freq:float, dur:float, vel = 1.0) -> [float]:
    let n = seconds(dur)
    let f = curve(n) t: freq * (1.0 + 0.006 * rsin(TAU * 5.5 * t) * min(1.0, t * 2.5))
    let tone = add([ sinec(f), gain(sinec(map(f) x: x * 2.0), 0.18), gain(sinec(map(f) x: x * 3.0), 0.05) ])
    let air = bandpass(noise(n), freq * 2.0, 2.0, 0.3)
    let chiff = mul(bandpass(noise(seconds(0.03)), freq * 1.5, 1.5, 1.5), decay(seconds(0.03), 90.0))
    return gain(add([ mul(add([ tone, air ]), swell(n, 0.06, min(0.15, dur * 0.4))), chiff ]), vel * 0.55)

// A horn (an animal horn, a bronze trumpet): brass harmonics that bloom as it swells.
def horn(freq:float, dur:float, vel = 1.0, bright = 1.0) -> [float]:
    let n = seconds(dur)
    let sw = swell(n, 0.09, min(0.25, dur * 0.4))
    var ph = 0.0
    let raw = map(n) i:
        let t = float(i) / RATE
        ph += TAU * freq * (1.0 + 0.004 * rsin(TAU * 4.8 * t)) / RATE
        let e = sw[i]
        let v = rsin(ph) + 0.55 * e * rsin(2.0 * ph) + 0.35 * e * bright * rsin(3.0 * ph) + 0.22 * e * bright * rsin(4.0 * ph) +
            0.12 * e * bright * rsin(5.0 * ph) + 0.06 * e * bright * rsin(6.0 * ph)
        v * e
    return gain(lowpass(soft_clip(raw, 1.3 + 0.8 * bright), 2600.0 + 1400.0 * bright), vel * 0.5)

// A deep ragged horn call: a horn with a growl (a slow beat against a detuned copy).
def war_horn(freq:float, dur:float, vel = 1.0) -> [float]:
    return gain(lowpass(add([ horn(freq, dur, vel, 1.3), horn(freq * 1.006, dur, vel * 0.7, 1.3) ]), 1800.0), 0.75)

// Two bowed-string-like saws a few cents apart, kept dark; a bass drone.
def drone(freq:float, dur:float, vel = 1.0) -> [float]:
    let n = seconds(dur)
    let mixed = add([ saw(n, freq, 10), saw(n, freq * 1.004, 10), gain(saw(n, freq * 0.5, 6), 0.7) ])
    let out = lowpassc(mixed, curve(n) t: 300.0 + 220.0 * rsin(TAU * 0.11 * t))
    return gain(mul(out, swell(n, min(0.6, dur * 0.3), min(0.8, dur * 0.4))), vel * 0.35)

// A hide drum: a pitched thump falling in pitch (dum) or a sharper rim tap (tek).
def frame_drum(vel = 1.0, low = true) -> [float]:
    let n = seconds(0.35)
    if low:
        let body = mul(sinec(curve(n) t: 62.0 + 33.0 * exp(-t * 18.0)), decay(n, 9.0, 0.001))
        let skin = mul(lowpass(noise(n), 900.0), decay(n, 60.0, 0.0005))
        return gain(add([ body, gain(skin, 0.35) ]), vel * 0.8)
    let body = modal(n, [ p3(420.0, 28.0, 0.5), p3(640.0, 40.0, 0.3), p3(1100.0, 60.0, 0.15) ], 0.0)
    let skin = mul(bandpass(noise(n), 2400.0, 1.0, 2.0), decay(n, 70.0, 0.0005))
    return gain(add([ body, skin ]), vel * 0.8)

// A big war drum: deep, slow, a long skin tail.
def low_drum(vel = 1.0, dur = 0.7) -> [float]:
    let n = seconds(dur)
    let body = mul(sinec(curve(n) t: 44.0 + 40.0 * exp(-t * 14.0)), decay(n, 5.0, 0.002))
    let thud = mul(lowpass(noise(n), 400.0), decay(n, 30.0, 0.001))
    return gain(soft_clip(add([ body, gain(thud, 0.5) ]), 1.4), vel * 0.9)

// Seeds in a gourd.
def shaker(vel = 1.0) -> [float]:
    let n = seconds(0.12)
    return gain(mul(bandpass(noise(n), 5200.0, 1.2, 2.5), env(n, 0.012, 0.06, 0.1, 0.03)), vel * 0.5)

// A struck note: a wooden tongue drum (warm, few partials) or a small bronze bell.
def bell(freq:float, dur:float, vel = 1.0, wood = true) -> [float]:
    let n = seconds(dur)
    if wood:
        return gain(modal(n, [ p3(freq, 6.0, 0.9), p3(freq * 2.76, 14.0, 0.3), p3(freq * 5.4, 28.0, 0.12) ], 0.25), vel * 0.7)
    let table = [ p3(freq, 3.0, 0.8), p3(freq * 2.0, 5.0, 0.4), p3(freq * 2.92, 8.0, 0.3), p3(freq * 4.2, 11.0, 0.15),
                  p3(freq * 5.4, 15.0, 0.08) ]
    return gain(modal(n, table, 0.5), vel * 0.7)

// "D4", "C#5", "Bb3" -> Hz (A4 = 440).
def note_hz(name:string) -> float:
    var semi = [ 9, 11, 0, 2, 4, 5, 7 ][name[0] - 'A']
    var i = 1
    while name[i] == '#' or name[i] == 'b':
        semi += if name[i] == '#': 1 else: -1
        i++
    let octave, ok = string_to_int(substring(name, i, -1))
    assert ok
    return 440.0 * pow(2.0, (octave - 4) + (semi - 9) / 12.0)
