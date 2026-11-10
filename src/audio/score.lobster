// What the pieces share: a piece's clock (Grid), notes as text (parse), and steps in the white-key scale all three
// pieces live in (D Dorian, G Mixolydian and E Phrygian are the same seven notes).

// A piece's clock: its beat and loop length.
class Grid:
    beat:float
    loop:int

    // A sound placed on a beat (tails wrap round the loop).
    def place(buf:[float], sound:[float], on:float, human = 0.012):
        let at = int(on * beat * RATE + j(-human, human) * RATE)
        mix_into(buf, sound, max(0, at) % loop, 1.0, true)

def new_grid(bpm:int, bars:int, per = 4) -> Grid:
    let beat = 60.0 / bpm
    return Grid { beat, seconds(bars * per * beat) }

class Note:
    on:float
    name:string
    beats:float

// "D4:1 r:.5" from a bar -> its notes, each beat counted from the loop's start.
def parse(text:string, bar = 0, per = 4) -> [Note]:
    let out = []::Note
    var on = float(bar * per)
    for(tokenize(replace_string(text, "|", " "), " ", "")) tok:
        if tok.length > 0:
            let colon = find_string(tok, ":")
            let beats, ok = string_to_float(substring(tok, colon + 1, -1))
            assert ok
            let name = substring(tok, 0, colon)
            if name != "r": out.push(Note { on, name, beats })
            on += beats
    return out

def tune_of(parts:[[Note]]) -> [Note]: return fold(parts, []::Note): append(_a, _b)

let NATURALS = "CDEFGAB"  // the scale is all naturals; octave numbers turn over at C

// A note some scale steps up (or down) from another: "A4", 2 -> "C5".
def step(name:string, degrees:int) -> string:
    let octave, ok = string_to_int(substring(name, 1, -1))
    assert ok
    let i = find_string(NATURALS, substring(name, 0, 1)) + octave * 7 + degrees
    return "{substring(NATURALS, i % 7, 1)}{i / 7}"

def third_up(name:string) -> string: return step(name, 2)

def triad(root:string, octave:int) -> [string]:
    let base = "{root}{octave}"
    return [ base, step(base, 2), step(base, 4) ]

// The roots' run lengths: the first bar of each run of the same root, as (bar, bars).
def root_runs(roots:[string]) -> [int2]:
    let out = []::int2
    var bar = 0
    while bar < roots.length:
        var end = bar + 1
        while end < roots.length and roots[end] == roots[bar]: end++
        out.push(int2 { bar, end - bar })
        bar = end
    return out
