// ------------------------------------------------------------------ mods (src/mods.gd, docs/modding.md)
// A mod is a folder of more data (parts, creatures, cultures, palettes, words, rules, maps, shot looks)
// plus models for the bake, with a manifest (pack.json, as the game has in data/). Used only when asked for (mods_use, from the
// game's mods:a,b option). Merged over the base data in load order (the manifest's load_order, then
// id), each checked first: a mod that fails is refused with the reason and none of it is used. Each
// mod's signature ("id@version#hash" of its parsed data) goes into the races made with it (the race
// key), as in GDScript. The models are the bake's (Godot's, until step 6c).

let mod_roots = [ "../mods", "../mods_private" ]  // (a later folder's copy of a mod wins)
let MOD_DATA_FILES = [ "parts.json", "creatures.json", "families.json", "palettes.json", "lexicon.json", "shots.json", "buildings.json", "tech.json", "ai.json", "audio.json", "atmosphere.json" ]
let MOD_DATA_DIRS = [ "rules", "maps", "voxel" ]
let MOD_BASE_ERAS = [ "bronze", "medieval", "gunpowder" ]

var mods_refused = dictionary<string, string>(8)
let AUDIO_DIR = "../assets/audio"
let audio_found = dictionary<string, string>(63)

// A sound's file: the last mod in load order that has it (<mod>/audio/<rel>), else the game's.
def audio_file(rel:string) -> string:
    if not pack_mods().length: return AUDIO_DIR + "/" + rel
    let known = audio_found.get(rel, "")
    if known != "": return known
    var path = AUDIO_DIR + "/" + rel
    for(pack_mods()) rec:
        if read_file(rec.dir + "/audio/" + rel, true): path = rec.dir + "/audio/" + rel
    audio_found.set(rel, path)
    return path

// Every file under dir, relative, sorted (the bake's leftovers left out).
def mod_files(dir:string, rel:string) -> [string]:
    let out = []::string
    let here = if rel == "": dir else: dir + "/" + rel
    let names, sizes = scan_folder(here, true)
    if not names or not sizes: return out
    let files = []::string
    let dirs = []::string
    for(names) n, k:
        if sizes[k] < 0:
            if n != "." and n != "..": dirs.push(n)
        elif not ends_with(n, ".import") and not ends_with(n, ".uid") and n != ".DS_Store": files.push(n)
    for(sorted_strs(files)) f: out.push(if rel == "": f else: rel + "/" + f)
    for(sorted_strs(dirs)) d:
        for(mod_files(dir, if rel == "": d else: rel + "/" + d)) f: out.push(f)
    return out

// The options the mods in a mods: list start the game with (their manifests' `launch`: how a mod says what it is to play).
def mods_launch_args(ids:[string]) -> [string]:
    let out = []::string
    for(ids) id:
        for(mod_roots) root:
            let text = read_file(root + "/" + id + "/pack.json")
            if text:
                for(gstrs(parse_json(text), "launch")) a: out.push(a)
    return out

def mods_discover(roots:[string]) -> dictionary<string, Pack>:
    let out = dictionary<string, Pack>(8)
    for(roots) root:
        let names, sizes = scan_folder(root, true)
        if names and sizes:
            let dirs = []::string
            for(names) n, k:
                if sizes[k] < 0 and n != "." and n != "..": dirs.push(n)
            for(sorted_strs(dirs)) d:
                let dir = root + "/" + d
                let text = read_file(dir + "/pack.json")
                if text:
                    let m = parse_json(text)
                    let id = if m.kind == J_OBJ: gstr(m, "id", d) else: d
                    out.set(id, pack_open(id, dir, m))
    return out

// Whether a pack made for version `want` runs on `have`: the same major, and a minor no newer.
def version_ok(want:string, have:string) -> bool:
    let w = tokenize(want, ".", "")
    let h = tokenize(have, ".", "")
    return w[0] == h[0] and string_to_int(w[1]) <= string_to_int(h[1])

// A depends entry, "id" or "id@version": its id and version ("": any).
def dep_parts(dep:string) -> string, string:
    let n = find_string(dep, "@")
    return if n < 0: dep else: substring(dep, 0, n), if n < 0: "" else: substring(dep, n + 1, dep.length - n - 1)

def mod_check_manifest(id:string, m:JV) -> string:
    if m.kind != J_OBJ: return "pack.json isn\'t a JSON object"
    for([ "id", "name", "version" ]) key:
        if not has(m, key): return "pack.json has no \'{key}\'"
    if gstr(m, "id", "") != id: return "pack.json\'s id \'{gstr(m, "id", "")}\' isn\'t the folder\'s"
    let game = gstr(lib_pack, "id", "")
    let have = gstr(lib_pack, "version", "")
    for(gstrs(m, "depends")) dep:
        let dep_id, want = dep_parts(dep)
        if dep_id == game:
            if want == "": return "pack.json: depends names {game} with no version"
            if not version_ok(want, have): return "made for {game} {want}; this is {have}"
            return ""
    return "pack.json: depends doesn\'t name the game ({game}@<version>)"

// The mod's data files, parsed; "" or why it can't be read.
def mod_read(rec:Pack) -> string:
    let root = rec.root
    var models = ""  // (MagicaVoxel models, voxel/models/*.vox: their bytes, read by the voxel kit itself)
    for(mod_files(root, "")) f:
        let base = if has_char(f, '/'): substring(f, 0, find_string(f, "/")) else: ""
        let model = starts_with(f, "voxel/models/") and ends_with(f, ".vox")
        if not (has_s(MOD_DATA_FILES, f) or (has_s(MOD_DATA_DIRS, base) and ends_with(f, ".json")) or model):
            return "data/{f} can\'t be modded yet (moddable: {concat_string(MOD_DATA_FILES, ", ")}, rules/*.json, maps/*.json, voxel/**.json, voxel/models/*.vox)"
        let text = read_file(root + "/" + f)
        if not text: return "data/{f} can\'t be read"
        if model: models += f + sha256_text(text)
        else: set(rec.data, f, parse_json(text))
    // (the hash is of the parsed data, not the files' bytes: line endings differ between checkouts)
    rec.sig = "{rec.id}@{gstr(rec.manifest, "version", "")}#{substring(sha256_text(stringify(jobj_without(jobj_without(rec.data, "audio.json"), "atmosphere.json")) + models), 0, 8)}"
    return ""

// What's wrong with a mod's data against the data before it (the base and earlier mods), or "".
// (A part's look is the voxel kit's: data/voxel/gear.json's rules, a mod's own first. No model files.)

// The mods a race was made with that aren't in use here ([]: it can be played; Mods.missing).
def mods_missing(race:JV) -> [string]: return filter(gstrs(race, "mods")) s: not has_s(lib_mods, s)

// What's wrong with a shot look's knobs (see data/shots.json), or "".
// What's wrong with a shot's muzzle or impact knobs, or "".
def mod_check_shot_look(k:string, name:string, o:JV, known:[string]) -> string:
    if o.kind != J_OBJ: return "shots.json {k}: \'{name}\' needs knobs"
    for(o.keys) key, n:
        if not has_s(known, key): return "shots.json {k}: {name} has no knob \'{key}\' (knobs: {concat_string(known, ", ")})"
        if key != "col" and (o.a[n].kind != J_INT and o.a[n].kind != J_FLOAT or as_float(o.a[n]) < 0.0): return "shots.json {k}: {name} \'{key}\' must be a number, 0 or more"
    return ""

def mod_check_shot(k:string, m:JV) -> string:
    let known = [ "_doc", "extends", "tag", "speed", "sound", "sticks", "arc", "form", "len", "w", "shaft", "head", "fletch", "hold", "pulses", "scatter", "wobble", "jag", "col", "glow", "fade", "hit", "trail", "muzzle", "impact" ]
    for(m.keys) key:
        if not has_s(known, key): return "shots.json {k}: no knob \'{key}\' (knobs: {concat_string(known, ", ")})"
    for([ "arc", "len", "w", "hold", "wobble", "jag", "fade", "trail" ]) key:
        if has(m, key) and (at(m, key).kind != J_INT and at(m, key).kind != J_FLOAT or as_float(at(m, key)) < 0.0): return "shots.json {k}: \'{key}\' must be a number, 0 or more"
    if has(m, "fade") and as_float(at(m, "fade")) > 1.0: return "shots.json {k}: \'fade\' is a share of its life, 0 to 1"
    if has(m, "muzzle"):
        let e = mod_check_shot_look(k, "muzzle", at(m, "muzzle"), [ "flash", "col", "smoke", "ring", "dust", "recoil" ])
        if e != "": return e
    if has(m, "impact"):
        let e = mod_check_shot_look(k, "impact", at(m, "impact"), [ "blast", "col", "smoke", "scorch", "debris", "shake" ])
        if e != "": return e
    let form = gstr(m, "form", "bolt")
    if form != "bolt" and form != "beam": return "shots.json {k}: form \'{form}\' isn\'t bolt or beam"
    if form != "beam":
        for([ "hold", "wobble", "jag" ]) key:
            if has(m, key): return "shots.json {k}: \'{key}\' is for a beam, and this is a bolt"
    for([ [ "pulses", "gap" ], [ "scatter", "spread" ] ]) knob:
        if has(m, knob[0]):
            let o = at(m, knob[0])
            if o.kind != J_OBJ or gint(o, "count", 0) < 1: return "shots.json {k}: \'{knob[0]}\' needs a \'count\' of 1 or more"
            if not has(o, knob[1]) or as_float(at(o, knob[1])) < 0.0: return "shots.json {k}: \'{knob[0]}\' needs a \'{knob[1]}\' of 0 or more"
    for([ "col", "glow" ]) key:
        if has(m, key) and (at(m, key).kind != J_STR or at(m, key).s.length != 7 or at(m, key).s[0] != '#'): return "shots.json {k}: \'{key}\' must be \"#rrggbb\""
    return ""

// A mod's buildings, tech, AI and sound, against what's there before it: "" or what's wrong.
def mod_check_match_data(d:JV) -> string:
    let bfile = gobj(d, "buildings.json")
    let before = at(lib_data("buildings.json"), "buildings")
    let mine = gobj(bfile, "buildings")
    for(mine.keys) id:
        let b = at(mine, id)
        if b.kind != J_OBJ: return "buildings.json {id}: isn\'t an object"
        if not has(before, id) and not has(b, "extends"): return "buildings.json {id}: a new building needs \'extends\' (it takes that one\'s model)"
        if has(b, "extends") and not has(before, gstr(b, "extends", "")): return "buildings.json {id}: extends unknown building \'{gstr(b, "extends", "")}\'"
    let after = data_merge(before, mine)
    let roles = []::string
    for(after.keys) id:
        if gstr(at(after, id), "status", "") != "planned":
            for(gstrs(at(after, id), "roles")) r: push_new(roles, r)
    for([ "hub", "housing" ]) r:
        if not has_s(roles, r): return "buildings.json: leaves no \'{r}\' building, and a match needs one"
    let slots = []::string
    for(d.keys) f:
        if starts_with(f, "rules/"):
            for(glist(at(d, f), "roster")) e: push_new(slots, gstr(e, "slot", ""))
    for(glist(load_rules("default"), "roster")) e: push_new(slots, gstr(e, "slot", ""))
    for(after.keys) id:
        for(append(gstrs(at(after, id), "trains"), gstrs(at(after, id), "+trains"))) s:
            if has(mine, id) and not has_s(slots, s) and not has_s(gstrs(at(before, id), "trains"), s):
                return "buildings.json {id}: trains \'{s}\', which no roster has"
    let there = filter(after.keys) id: not starts_with(id, "_")
    let tech = data_merge(lib_data("tech.json"), gobj(d, "tech.json"))
    if has(d, "tech.json") or has(d, "buildings.json"):
        for(glist(tech, "ages")) a, k:
            if as_int(at(a, "age")) != k + 1: return "tech.json: the ages must run 1, 2, 3 with none missing"
            if not has_s(there, gstr(a, "building", "")): return "tech.json age {k + 1}: at \'{gstr(a, "building", "")}\', which isn\'t a building"
        for(glist(gobj(d, "tech.json"), "research")) r:
            if not gbool(r, "remove", false) and has(r, "building") and gstr(r, "building", "") != "all" and not has_s(there, gstr(r, "building", "")):
                return "tech.json {gstr(r, "id", "")}: at \'{gstr(r, "building", "")}\', which isn\'t a building"
    let snd = gobj(gobj(d, "audio.json"), "sounds")
    for(snd.keys) name:
        if not starts_with(name, "_") and gint(at(snd, name), "takes", 0) < 1: return "audio.json {name}: needs \'takes\'"
    return ""

def mod_check_data(rec:Pack, eras:[string]) -> string:
    let d = rec.data
    let slots = []::string
    for(lib_parts.keys) id: push_new(slots, gstr(at(lib_parts, id), "slot", ""))
    let replaces = gstrs(rec.manifest, "replaces")
    let new_parts = []::string
    for(glist(d, "parts.json")) p:
        if p.kind != J_OBJ or gstr(p, "id", "") == "": return "parts.json: a part without an id"
        let id = gstr(p, "id", "")
        let at_ = "parts.json {id}: "
        if has(lib_parts, id) and not has_s(replaces, id): return at_ + "already a part (list it in the manifest\'s \'replaces\' to replace it)"
        if not has_s(slots, gstr(p, "slot", "")): return at_ + "unknown slot \'{gstr(p, "slot", "")}\'"
        let pts = get(p, "points")
        if not pts or (pts.kind != J_INT and pts.kind != J_FLOAT) or as_float(pts) < 0.0: return at_ + "needs whole \'points\' (its price comes from them)"
        let tags = get(p, "tags")
        if not tags or tags.kind != J_ARR: return at_ + "needs \'tags\' (a list)"
        for(gstrs(p, "era")) e:
            if not has_s(eras, e): return at_ + "era \'{e}\' isn\'t the game\'s or in the manifest\'s \'eras\'"
        let tier = gint(p, "tier", 1)
        if tier < 1 or tier > 3: return at_ + "tier must be 1-3"
        new_parts.push(id)
    def has_part(id:string) -> bool: return has(lib_parts, id) or has_s(new_parts, id)
    let creatures = gobj(d, "creatures.json")
    let families = gobj(d, "families.json")
    for(creatures.keys) id:
        if not starts_with(id, "_"):
            var c = at(creatures, id)
            if has(c, "extends"):
                if not has(lib_creatures, gstr(c, "extends", "")): return "creatures.json {id}: extends unknown creature \'{gstr(c, "extends", "")}\'"
                c = mod_merge(at(lib_creatures, gstr(c, "extends", "")), c)
            for([ "body", "head" ]) key:
                if not has_part(gstr(c, key, "")): return "creatures.json {id}: its {key} \'{gstr(c, key, "")}\' isn\'t a part"
            for(gstrs(c, "families")) f:
                if not has(lib_families, f) and not has(families, f): return "creatures.json {id}: unknown culture \'{f}\'"
    for(families.keys) id:
        if not starts_with(id, "_") and has(at(families, id), "extends") and not has(lib_families, gstr(at(families, id), "extends", "")):
            return "families.json {id}: extends unknown culture \'{gstr(at(families, id), "extends", "")}\'"
    let words = gobj(gobj(d, "lexicon.json"), "words")
    for(words.keys) w:
        if not starts_with(w, "_"):
            let e = at(words, w)
            if has(e, "creature") and not has(lib_creatures, gstr(e, "creature", "")) and not has(creatures, gstr(e, "creature", "")):
                return "lexicon.json \'{w}\': unknown creature \'{gstr(e, "creature", "")}\'"
            if has(e, "family") and not has(lib_families, gstr(e, "family", "")) and not has(families, gstr(e, "family", "")):
                return "lexicon.json \'{w}\': unknown culture \'{gstr(e, "family", "")}\'"
            if has(e, "era") and not has_s(eras, gstr(e, "era", "")): return "lexicon.json \'{w}\': unknown era \'{gstr(e, "era", "")}\'"
            if has(e, "era") and not has(e, "note"): return "lexicon.json \'{w}\': an era word needs a \'note\' for hosts that keep that era out"
    for(d.keys) f:
        if starts_with(f, "rules/"):
            let r = at(d, f)
            if not read_file(lib_root + "/" + f) and not has(r, "extends") and not has(r, "roster"):
                return "{f}: neither a game rule to change, nor \'extends\' one, nor a whole rule"
            for(append(gstrs(r, "+era"), gstrs(r, "era"))) e:
                if not has_s(eras, e): return "{f}: unknown era \'{e}\'"
    let mshots = gobj(d, "shots.json")
    for(mshots.keys) k:
        if not starts_with(k, "_"):
            for(if has(at(mshots, k), "extends"): [ "tag" ] else: [ "tag", "speed", "col" ]) key:
                if not has(at(mshots, k), key): return "shots.json {k}: needs \'{key}\'"
            let bad = mod_check_shot(k, at(mshots, k))
            if bad != "": return bad
            let hit = get(at(mshots, k), "hit")
            if hit:
                if gint(hit, "sparks", 0) < 1: return "shots.json {k}: its hit needs \'sparks\'"
                if gstr(hit, "col", "").length != 7: return "shots.json {k}: its hit needs \'col\' as \"#rrggbb\""
                let sound = gstr(hit, "sound", "")
                if sound != "" and not has(gobj(data_merge(lib_data("audio.json"), gobj(d, "audio.json")), "sounds"), sound): return "shots.json {k}: its hit\'s sound \'{sound}\' isn\'t in audio.json"
    return mod_check_match_data(d)

// Use exactly these mods (after lib_load): checked against the data before them, in load order.
// Returns the ids in use; mods_refused says why the others weren't.
def mods_use(ids:[string], roots = mod_roots) -> [string]:
    audio_found.clear()
    lib_load(lib_root)  // (the game alone: what another mods_use put in goes)
    mods_refused = dictionary<string, string>(8)
    let found = mods_discover(roots)
    let picked = []::Pack
    for(ids) id:
        let rec = found.get(id)
        if not rec: mods_refused.set(id, "not found in {concat_string(roots, ", ")}")
        else:
            let why = mod_check_manifest(id, rec.manifest)
            if why != "": mods_refused.set(id, why)
            else: picked.push(rec)
    insertion_sort(picked) a, b: gint(a.manifest, "load_order", 100) < gint(b.manifest, "load_order", 100) or
        (gint(a.manifest, "load_order", 100) == gint(b.manifest, "load_order", 100) and a.id < b.id)
    var eras = copy(MOD_BASE_ERAS)
    for(picked) rec:
        var why = ""
        for(gstrs(rec.manifest, "depends")) dep:
            let dep_id, want = dep_parts(dep)
            if why == "" and dep_id != gstr(lib_pack, "id", ""):
                let there = find(pack_mods()) a: a.id == dep_id
                if there < 0: why = "needs the mod \'{dep_id}\' loaded before it"
                elif want != "" and not version_ok(want, gstr(pack_mods()[there].manifest, "version", "")): why = "needs {dep_id} {want}"
        if why == "": why = mod_read(rec)
        let with_own = append(eras, gstrs(rec.manifest, "eras"))
        if why == "": why = mod_check_data(rec, with_own)
        if why != "": mods_refused.set(rec.id, why)
        else:
            eras = with_own
            lib_packs.push(rec)
            pack_apply(rec)
    packs_loaded(lib_root)  // (the game's turn: what it works out from the merged data)
    for(mods_refused.get_keys()) id: print "Mod \'{id}\' refused: {mods_refused.get(id, "")}"
    return map(pack_mods()) p: p.id
