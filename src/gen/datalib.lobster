// ------------------------------------------------------------------ DataLib (src/data_lib.gd)
// The data contract, read once: parts by id, creatures, cultures, uniques, heroes, palettes, the
// lexicon, resources, cost curves. It comes from packs: the game's first, then the mods gen/mods.lobster checks (mods_use).

var lib_root = "data"
var lib_pack = jobj()  // the game's manifest (data/pack.json)
var lib_parts = jobj()
var lib_part_ids:[string] = []  // sorted
var lib_creatures = jobj()
var lib_families = jobj()
var lib_uniques = jobj()
var lib_heroes = jobj()
var lib_palettes = jobj()
var lib_lexicon = jobj()
var lib_stopwords:[string] = []  // sorted
var lib_resources:[string] = []
let lib_curves = dictionary<string, [int]>(17)
var lib_cands = dictionary<string, [JV]>(31)  // slot|eras -> candidates
var lib_mods:[string] = []
var mod_shots = jobj()  // shot looks chosen by tag (kind -> look)

def any_in(xs:[string], ys:[string]) -> bool: return exists(xs) x: has_s(ys, x)

// Whether a bonus reaches a unit with these tags (Identity.reaches).
def reaches(fx:JV, tags:[string]) -> bool:
    if not has(fx, "tag"): return false
    let t = as_str(at(fx, "tag"))
    if not (t == "all" or has_s(tags, t)): return false
    for(gstrs(fx, "and")) x:
        if not has_s(tags, x): return false
    for(gstrs(fx, "not")) x:
        if has_s(tags, x): return false
    return true

def push_new(xs:[string], s:string):
    if not has_s(xs, s): xs.push(s)

def has_s(xs:[string], s:string) -> bool:
    for(xs) x:
        if x == s: return true
    return false

def sorted_strs(xs:[string]) -> [string]:
    let out = copy(xs)
    insertion_sort(out) a, b: a < b
    return out

// Saves: the format this build writes, and what stops one loading. A save names the packs it was made with, and a
// match only makes sense with those. A save from before formats reads as format 0 with no packs: the base game.
let SAVE_FORMAT = 4
var save_refused = ""  // why the last load didn't happen

def sig_id(sig:string) -> string:
    let n = find_string(sig, "@")
    return if n < 0: sig else: substring(sig, 0, n)

// Why a save can't load here, or "".
def save_refusal(format:int, packs:[string]) -> string:
    if format > SAVE_FORMAT: return "This save is from a newer build of the game."
    for(packs) sig:
        if not has_s(lib_mods, sig): return "This save needs the mod {sig_id(sig)} ({sig})."
    for(lib_mods) sig:
        if not has_s(packs, sig): return "This save was made without the mod {sig_id(sig)}."
    return ""

// A pack: the game (data/pack.json, always first) or a mod. Everything in lib_* comes from packs, through pack_apply.
class Pack:
    id:string
    dir:string   // its folder
    root:string  // its data folder
    manifest:JV
    data:JV  // relative path (parts.json, rules/<id>.json, maps/<id>.json) -> parsed, as far as read
    sig = ""

var lib_packs = []::Pack  // in load order, the game first

def pack_open(id:string, dir:string, manifest:JV) -> Pack:
    let d = gstr(manifest, "data", "data")
    return Pack { id, dir, if d == ".": dir else: dir + "/" + d, manifest, jobj() }

def pack_mods() -> [Pack]: return lib_packs.slice(1, -1)

// One of a pack's data files, or nil if it hasn't that file. (A mod's were all read and checked before this.)
def pack_file(p:Pack, file:string) -> JV?:
    let known = get(p.data, file)
    if known: return known
    let text = read_file(p.root + "/" + file)
    if not text: return nil
    let parsed = parse_json(text)
    set(p.data, file, parsed)
    return parsed

def extended(all:JV, e:JV) -> JV:
    if not has(e, "extends"): return e
    return jobj_without(mod_merge(at(all, gstr(e, "extends", "")), e), "extends")

// A pack's data over what's there: the one way anything gets in, for the game and for mods.
def pack_apply(p:Pack):
    let parts = pack_file(p, "parts.json")
    if parts:
        for(parts.a) part: set(lib_parts, gstr(part, "id", ""), deep_copy(part))
    let cs = pack_file(p, "creatures.json")
    if cs:
        for(cs.keys) id:
            if not starts_with(id, "_"): set(lib_creatures, id, extended(lib_creatures, at(cs, id)))
    let fs = pack_file(p, "families.json")
    if fs:
        for(fs.keys) id:
            if not starts_with(id, "_"): set(lib_families, id, extended(lib_families, at(fs, id)))
    let pal = pack_file(p, "palettes.json")
    if pal: lib_palettes = mod_merge(lib_palettes, pal)
    let uq = pack_file(p, "uniques.json")
    if uq: lib_uniques = mod_merge(lib_uniques, at(uq, "themes"))
    let hr = pack_file(p, "heroes.json")
    if hr: lib_heroes = mod_merge(lib_heroes, hr)
    let lex = pack_file(p, "lexicon.json")
    if lex:
        let words = gobj(lex, "words")
        for(words.keys) w:
            if not starts_with(w, "_"): set(lib_lexicon, w, at(words, w))
        for(gstrs(lex, "stopwords")) w: push_new(lib_stopwords, w)
        lib_stopwords = sorted_strs(lib_stopwords)
    let res = pack_file(p, "resources.json")
    if res: lib_resources = map(at(res, "resources").a) r: as_str(at(r, "id"))
    let cc = pack_file(p, "cost_curves.json")
    if cc:
        for(cc.keys) id, n:
            if not starts_with(id, "_"): lib_curves.set(id, map(at(cc.a[n], "permille").a) v: as_int(v))
    let looks = pack_file(p, "shots.json")
    if looks:
        for(looks.keys) k:
            if has(at(looks, k), "tag"): set(mod_shots, k, at(looks, k))  // (only a look with a tag is chosen by it)
    let kits = pack_file(p, "creature_kit.json")
    if kits: lib_kit_parts(kits)
    if p.sig != "": lib_mods.push(p.sig)
    lib_part_ids = sorted_strs(lib_parts.keys)
    lib_cands = dictionary<string, [JV]>(31)

// The game alone, as its pack says.
def lib_load(root:string):
    lib_root = root
    let manifest = load_json(root + "/pack.json")
    lib_pack = manifest
    lib_parts = jobj()
    lib_creatures = jobj()
    lib_families = jobj()
    lib_uniques = jobj()
    lib_heroes = jobj()
    lib_palettes = jobj()
    lib_lexicon = jobj()
    lib_stopwords = []
    lib_resources = []
    mod_shots = jobj()
    lib_mods = []
    let game = pack_open(gstr(manifest, "id", ""), root, manifest)
    lib_packs = [ game ]
    pack_apply(game)

// Creature-kit bodies (the bears): their head and leg parts made, as CreatureKit.complete() makes
// them. (What it fills in on the body itself, sockets, legs and poses, is for the views: 6b.)
def lib_kit_parts(file:JV):
    let kits = at(file, "kits")
    for(sorted_strs(lib_parts.keys)) id:
        let p = at(lib_parts, id)
        if has(p, "kit"):
            let k = at(kits, as_str(at(p, "kit")))
            let kp = at(k, "parts")
            let made = []::JV
            if has(k, "head"): made.push(made_part(as_str(at(kp, "head")), "head"))
            made.push(made_part(as_str(at(kp, "leg")), "leg"))
            if has(kp, "hind"): made.push(made_part(as_str(at(kp, "hind")), "leg"))
            for(made) m:
                let mid = as_str(at(m, "id"))
                if not has(lib_parts, mid): set(lib_parts, mid, m)

def made_part(id:string, slot:string) -> JV:
    let o = jobj()
    set(o, "id", jstr(id))
    set(o, "slot", jstr(slot))
    set(o, "tags", jarr([]))
    set(o, "stats", jobj())
    set(o, "points", jint(0))
    return o

// Deep merge: b's keys over a's; objects merge; "+key": [...] appends to a's list at key.
def mod_merge(a:JV, b:JV) -> JV:
    let out = deep_copy(a)
    for(b.keys) key, n:
        let v = b.a[n]
        if starts_with(key, "+"):
            let k = substring(key, 1, key.length - 1)
            let list = copy(glist(out, k))
            for(v.a) x:
                var seen = false
                for(list) y:
                    if stringify(y) == stringify(x): seen = true
                if not seen: list.push(x)
            set(out, k, jarr(list))
        elif starts_with(key, "-"):
            let k = substring(key, 1, key.length - 1)
            let gone = map(v.a) x: stringify(x)
            set(out, k, jarr(filter(glist(out, k)) x: not has_s(gone, stringify(x)) and not has_s(gone, stringify(jstr(item_key(x))))))
        elif has(out, key) and at(out, key).kind == J_OBJ and v.kind == J_OBJ: set(out, key, mod_merge(at(out, key), v))
        else: set(out, key, deep_copy(v))
    return out

def jobj_without(o:JV, key:string) -> JV:
    let out = jobj()
    for(o.keys) k, n:
        if k != key: set(out, k, o.a[n])
    return out

// A data file with every mod's change to it, in load order: same id replaces (objects merge), "remove": true takes an entry
// out, "extends": id copies a sibling, "+key" appends to a list, "-key" takes items out, and a list whose items have
// an id (or an age) merges item by item.
def lib_data(file:string) -> JV:
    var out = load_json(lib_root + "/" + file)
    for(pack_mods()) p:
        let m = get(p.data, file)
        if m: out = data_merge(out, m)
    return out

def item_key(x:JV) -> string:
    if x.kind != J_OBJ: return ""
    if has(x, "id"): return gstr(x, "id", "")
    if has(x, "slot"): return gstr(x, "slot", "")
    return if has(x, "age"): "age " + string(as_int(at(x, "age"))) else: ""

def data_merge(a:JV, b:JV) -> JV:
    var out = deep_copy(a)
    for(b.keys) key, n:
        let v = b.a[n]
        let old = get(out, key)
        if starts_with(key, "+") or starts_with(key, "-"): out = mod_merge(out, jobj_with(key, v))
        elif v.kind == J_OBJ and gbool(v, "remove", false): out = jobj_without(out, key)
        elif v.kind == J_OBJ and has(v, "extends"): set(out, key, data_merge(at(out, gstr(v, "extends", "")), jobj_without(v, "extends")))
        elif old and old.kind == J_OBJ and v.kind == J_OBJ: set(out, key, data_merge(old, v))
        elif old and old.kind == J_ARR and v.kind == J_ARR and v.a.length and item_key(v.a[0]) != "": set(out, key, jarr(list_merge(old.a, v.a)))
        else: set(out, key, deep_copy(v))
    return out

// A list with ids: the same id merges where it stands or goes, a new one goes at the end.
def list_merge(a:[JV], b:[JV]) -> [JV]:
    var out = map(a) x: x
    for(b) m:
        let k = item_key(m)
        let at_ = find(out) x: item_key(x) == k
        if gbool(m, "remove", false): out = filter(out) x: item_key(x) != k
        elif at_ >= 0: out[at_] = data_merge(out[at_], m)
        else: out.push(deep_copy(m))
    return out

def jobj_with(key:string, v:JV) -> JV:
    let o = jobj()
    set(o, key, v)
    return o

// A host rule with every mod's change to it, in load order (Mods.rules): a mod's rules/<id>.json
// deep-merges into a game rule ("+key" appends), or adds a rule of its own ("extends" another, or whole).
def load_rules(id:string) -> JV:
    let text = read_file(lib_root + "/rules/" + id + ".json")
    var out = if text: parse_json(text) else: jobj()
    for(pack_mods()) p:
        let r = get(p.data, "rules/{id}.json")
        if r:
            if not out.keys.length and has(r, "extends"):
                out = load_rules(gstr(r, "extends", ""))
                set(out, "id", jstr(id))
            out = mod_merge(out, jobj_without(r, "extends"))
    if not out.keys.length: print "No rule \'{id}\' in {lib_root}/rules or the mods in use ({lib_mods})"
    assert out.keys.length
    return out

// Where a data file comes from: the last mod in load order that has it, else the game's (Mods.data_path).
def data_path(rel:string) -> string:
    var k = lib_packs.length - 1
    while k >= 1:
        if has(lib_packs[k].data, rel): return lib_packs[k].root + "/" + rel
        k--
    return lib_root + "/" + rel

def part(id:string) -> JV:
    let p = get(lib_parts, id)
    if not p:
        print "Unknown part: " + id
        assert false
    return p or jobj()

def creature(id:string) -> JV: return at(lib_creatures, id)
def family(id:string) -> JV: return at(lib_families, id)

def curve(id:string, points:int) -> int:
    let table = lib_curves.get(id)
    assert table
    assert points >= 0 and points < table.length
    return table[points]

def era_ok(p:JV, eras:[string]) -> bool:
    if not has(p, "era"): return true
    for(glist(p, "era")) e:
        if has_s(eras, as_str(e)): return true
    return false

// Parts for a slot allowed in the given eras, in sorted id order (innate parts are grown, never picked).
def candidates(slot:string, eras:[string]) -> [JV]:
    let key = slot + "|" + concat_string(eras, ",")
    let hit = lib_cands.get(key)
    if hit: return hit
    let out = []::JV
    for(lib_part_ids) id:
        let p = at(lib_parts, id)
        if gstr(p, "slot", "") == slot and era_ok(p, eras) and not gbool(p, "innate", false): out.push(p)
    lib_cands.set(key, out)
    return out

def creature_ids(flag:string) -> [string]:
    let ids = sorted_strs(lib_creatures.keys)
    if flag == "": return ids
    return filter(ids) id: gbool(at(lib_creatures, id), flag, false)

def architecture(race:JV) -> string:
    let c = creature(as_str(at(race, "creature")))
    let f = family(as_str(at(race, "family")))
    return gstr(c, "architecture", gstr(f, "architecture", "thatch"))

// Every architecture a race can have (the creatures' and cultures', and the default), sorted.
def all_architectures() -> [string]:
    let out = [ "thatch" ]
    for([ lib_creatures, lib_families ]) table:
        for(table.keys) k:
            let a = gstr(at(table, k), "architecture", "")
            if a != "" and not has_s(out, a): out.push(a)
    return sorted_strs(out)

// How loud a unit's loop is with this many units making it, 0 to 1: the first is clearly heard, more add less and less,
// and past a dozen they add nothing (#182).
def loop_share(count:int) -> float:
    if count <= 0: return 0.0
    return sqrt(float(min(count, 12))) / sqrt(12.0)
