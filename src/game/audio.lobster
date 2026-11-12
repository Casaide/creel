// ------------------------------------------------------------------ sound (src/view/audio.gd, data/audio.json)
// Every sound and voice is a WAV in assets/audio, rendered by src/render_audio.sh. A sound has takes played in
// turn, a gap it won't repeat within, and a bus (a volume in dB); voices are a creature's
// select / ack / die takes.

class Sound:
    takes:int
    gap:float  // seconds
    bus:string
    next:int = 0  // the take to play next
    last:float = -10.0

let sounds = dictionary<string, Sound>(64)
let buses = dictionary<string, float>(8)
let voice_takes = dictionary<string, int>(8)
var voice_of = []::string  // per player: its creature's voice
var voice_last = -10.0
var sound_on = true
var music_level = 5  // the player's volumes, 0..10 (settings.txt beside the saves)
var sound_level = 10
var hud_size = 115            // the match HUD's size in percent (Ctrl/Cmd + and -), in settings.txt too
var windowed_setting = false  // a window rather than fullscreen (#223), in settings.txt too
let SETTINGS_FILE = "settings.txt"

def volume_load():
    let t = read_file(SETTINGS_FILE, true)
    if not t: return
    for(tokenize(t, "\n", " ")) line:
        let kv = tokenize(line, "=", " ")
        if kv.length == 2:
            if kv[0] == "music": music_level = clamp(string_to_int(kv[1]), 0, 10)
            elif kv[0] == "sound": sound_level = clamp(string_to_int(kv[1]), 0, 10)
            elif kv[0] == "hud": hud_size = clamp(string_to_int(kv[1]), 70, 200)
            elif kv[0] == "windowed": windowed_setting = kv[1] == "1"

def volume_save(): write_file(SETTINGS_FILE, "music={music_level}\nsound={sound_level}\nhud={hud_size}\nwindowed={if windowed_setting: 1 else: 0}\n")

def db_to_volume(db:float) -> float: return pow(10.0, db / 20.0)

// The game's sounds and buses, from data/audio.json: "sounds" { name: { "takes", "gap", "bus" } } (a name starting
// with _ is a note) and "buses" { name: dB }. A game calls it once, before its first sound; it can be called again.
def sounds_load():
    let a = lib_data("audio.json")
    let snd = gobj(a, "sounds")
    for(snd.keys) name, k:
        if not starts_with(name, "_"):
            let s = snd.a[k]
            sounds.set(name, Sound { max(1, gint(s, "takes", 1)), if has(s, "gap"): as_float(at(s, "gap")) else: 0.0, gstr(s, "bus", "") })
    let b = gobj(a, "buses")
    for(b.keys) name, k: buses.set(name, as_float(b.a[k]))

// One of a sound's takes, in turn (sfx/<name>_<take>.wav), at db over its bus: its channel, or 0 (no sound, sound off,
// or played within its gap).
def sound_take(name:string, db:float) -> int:
    if not sound_on: return 0
    let s = sounds.get(name)
    if not s: return 0
    let now = gl.time()
    if now - s.last < s.gap: return 0
    s.last = now
    let n = s.next % s.takes + 1
    s.next++
    let ch = play_wav(audio_file("sfx/{name}_{n}.wav"))
    if ch > 0: sound_volume(ch, db_to_volume(buses.get(s.bus, 0.0) + db) * float(sound_level) / 10.0)
    return ch

def play_sound(name:string, db:float):
    sound_take(name, db)

// A sound from somewhere left or right of the listener: pan -1 (all left) .. 1 (all right), 0 straight ahead.
def play_sound_at(name:string, db:float, pan:float):
    let ch = sound_take(name, db)
    if ch > 0 and pan != 0.0:
        let k = clamp(pan, -1.0, 1.0)
        sound_position(ch, float3 { sin(k * 70.0), cos(k * 70.0), 0.0 }, float3 { 0.0, 1.0, 0.0 }, 1.0)

// One of the player's creature voices: "select", "ack" or "die".
def say(p:int, kind:string):
    if not sound_on or p < 0 or p >= voice_of.length: return
    let now = gl.time()
    if now - voice_last < 0.4: return
    voice_last = now
    let n = rnd(max(1, voice_takes.get(kind, 1))) + 1
    let ch = play_wav(audio_file("voice/{voice_of[p]}_{kind}_{n}.wav"))
    if ch > 0: sound_volume(ch, db_to_volume(buses.get("Voice", 0.0)) * float(sound_level) / 10.0)

// ---- the music (Audio.music, battle): three pieces (data/audio.json music.pieces, each a loop's
// seconds), each in the same stems. A piece's stems play together, in step, each faded to the mix
// (the lobby's, then by the player's age; the battle layer while there's fighting on screen; none
// with the sound off). The lobby plays the rotation's first piece; a match turns the rotation over
// every `plays` loops, and tense_after_s of fighting brings the tense piece in at once, kept till the
// fighting has cooled off and its loop is done. Each stem is a music track; a piece going out fades
// down and is halted.

let music_ids = []::int
let music_names = []::string  // each track's stem
let music_gens = []::int      // and which start of a piece it belongs to
let music_now = []::float     // each track's volume now (0..1)
var music_cfg:JV? = nil
var music_piece = ""
var music_gen = 0
var music_since = 0.0  // when the piece playing started
var music_turn = 0     // the rotation's piece
var music_heat = 0.0   // seconds of recent fighting

def music_play(m:JV, piece:string):
    music_piece = piece
    music_gen++
    music_since = gl.time()
    for(gstrs(m, "stems")) stem:
        let id = play_music(audio_file("music/{piece}_{stem}.ogg"), -1)
        if id > 0:
            music_volume(id, 0.0)
            music_ids.push(id)
            music_names.push(stem)
            music_gens.push(music_gen)
            music_now.push(0.0)
    print "music: {piece}, {music_ids.length} tracks playing"

def music_start():
    let m = at(lib_data("audio.json"), "music")
    music_cfg = m
    music_play(m, gstrs(m, "rotation")[0])

def music_tick(mix:string, battle:bool, dt:float):
    let m = music_cfg
    if not m: return
    let rotation = gstrs(m, "rotation")
    let tense = gstr(m, "tense", "")
    let after = as_float(at(m, "tense_after_s"))
    music_heat = if battle and mix != "lobby": min(music_heat + dt, after * 2.0) else: max(0.0, music_heat - dt)
    let played = gl.time() - music_since
    let loop_s = as_float(at(gobj(m, "pieces"), music_piece))
    var piece = music_piece
    if mix == "lobby":
        music_turn = 0
        piece = rotation[0]
    elif music_heat >= after: piece = tense
    elif music_piece == tense:
        if music_heat <= 0.0 and played >= loop_s: piece = rotation[music_turn % rotation.length]
    elif played >= loop_s * float(gint(m, "plays", 1)):
        music_turn++
        piece = rotation[music_turn % rotation.length]
        music_since = gl.time()  // (a rotation of one goes round again)
    if piece != music_piece: music_play(m, piece)
    let levels = gobj(gobj(m, "mixes"), mix)
    let master = db_to_volume(buses.get("Music", 0.0)) * float(music_level) / 10.0
    let rate = dt / max(0.1, as_float(at(m, "fade_s")))
    var k = 0
    while k < music_ids.length:
        let stem = music_names[k]
        let current = music_gens[k] == music_gen
        var want = 0.0
        if sound_on and current:
            if stem == "battle":
                if battle and mix != "lobby": want = db_to_volume(as_float(at(m, "battle_db"))) * master
            elif has(levels, stem): want = db_to_volume(as_float(at(levels, stem))) * master
        music_now[k] = move_toward(music_now[k], want, rate)
        if not current and music_now[k] <= 0.0:
            music_halt(music_ids[k])
            music_ids.remove(k)
            music_names.remove(k)
            music_gens.remove(k)
            music_now.remove(k)
        else:
            music_volume(music_ids[k], music_now[k])
            k++

// ---- the ambience (Audio.ambience, town): the meadow loop under a match, the town's quiet and busy
// loops on top by town_level (0: no town or the camera far away .. 1: a big town right below): the
// quiet one comes in first, the busy one joins past the middle. Each a music track, looping, faded.

let amb_ids = []::int  // meadow, town_quiet, town_busy
let amb_now = [ 0.0, 0.0, 0.0 ]

def ambience_start():
    for([ "sfx/meadow_1.wav", "sfx/town_quiet_1.wav", "sfx/town_busy_1.wav" ]) f:
        let id = play_music(audio_file(f), -1)
        if id > 0: music_volume(id, 0.0)
        amb_ids.push(id)
    print "ambience: {(filter(amb_ids) id: id > 0).length} loops playing"

def ambience_tick(town_level:float, dt:float):
    let master = db_to_volume(buses.get("Ambience", 0.0)) * float(sound_level) / 10.0
    let want = [ db_to_volume(-6.0),
                 if town_level * 2.5 > 0.01: db_to_volume(4.0) * clamp(town_level * 2.5, 0.0, 1.0) else: 0.0,
                 if town_level > 0.41: db_to_volume(4.0) * clamp((town_level - 0.4) / 0.6, 0.0, 1.0) else: 0.0 ]
    for(amb_ids) id, k:
        if id > 0:
            amb_now[k] = move_toward(amb_now[k], (if sound_on: want[k] * master else: 0.0), dt * 0.5)
            music_volume(id, amb_now[k])

// ---- units' loops (#182): what a body sounds like by state (data/audio.json units). One channel a sound, however many
// units are making it: its volume grows with how many are on screen, up to a cap, so twenty tanks are a louder rumble
// and not twenty rumbles. Sound can't change pitch here: an engine "revs" by fading from its idle loop into its move loop.

class UnitLoop:
    id:int
    now:float   // its volume now
    want:float  // its share this frame

let unit_loops = dictionary<string, UnitLoop>(8)
let UNIT_LOOP_FADE = 1.6  // how fast a loop comes and goes, volume a second

// The sound a body makes in that state, or "". Called for every unit every frame, and lib_data reads the files: each body
// once a match.
let UNIT_SOUND_STATES = [ "idle", "move", "turret" ]
let unit_sound_of = dictionary<string, [string]>(16)
def unit_sound(body:string, state:int) -> string:
    var s = unit_sound_of.get(body)
    if not s:
        let u = gobj(gobj(lib_data("audio.json"), "units"), body)
        s = map(UNIT_SOUND_STATES) n: gstr(u, n, "")
        unit_sound_of.set(body, s)
    return s[state]

// A sound heard from units this frame: the loudest of it so far.
def unit_loop_hear(name:string, count:int):
    if name == "" or not sound_on: return
    var l = unit_loops.get(name)
    if not l:
        let s = sounds.get(name)
        if not s: return
        let id = play_music(audio_file("sfx/{name}_1.wav"), -1)
        if id <= 0: return
        music_volume(id, 0.0)
        l = UnitLoop { id, 0.0, 0.0 }
        unit_loops.set(name, l)
    l.want = loop_share(count)

// Every loop eased to what it was asked for this frame (a loop nobody asked for fades out, and keeps its channel).
def unit_loops_fade(dt:float):
    for(unit_loops.get_keys()) name:
        let l = unit_loops.get(name)
        if l:
            let s = sounds.get(name)
            let bus = if s: buses.get(s.bus, 0.0) else: 0.0
            l.now = move_toward(l.now, if sound_on: l.want else: 0.0, dt * UNIT_LOOP_FADE)
            music_volume(l.id, l.now * db_to_volume(bus) * float(sound_level) / 10.0)
            l.want = 0.0
