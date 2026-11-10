// ------------------------------------------------------------------ the tech tree's model (src/view/tech_tree_model.gd)
// From data alone: the ages as rows (data/tech.json: each with what it needs), the buildings as columns
// (data/buildings.json, its "tree" order), under each building its unit lines (the rules' roster: a node where
// the unit changes, from the age it's first trained) and its research (tracks joined by `after` share a lane),
// packed into lanes so a line or a track runs straight down. For a race: its own unit names and pictures, other
// races' own research left off, what it lacks crossed out, research only some races get marked, and the race in
// words (bonuses and where each comes from, its own research, what it lacks, how it moves). Planned things show
// as blank frames. The page that draws it is game/techtree_page.lobster.

class TNode:
    key:string
    kind:string  // building, unit, research
    name:string
    desc:string
    age:int
    planned:bool
    col:int
    lane = -1
    id = ""        // the building's or research's id, a line's slot
    building = ""  // where it is (a building's own id)
    lacks = false
    race_only = false  // research only some races get, and this race does
    cost = ""          // in words ("35 food, 40 wood")
    costv:JV? = nil    // the cost as data (the card colours each resource)
    effect = ""        // a research's effects in words
    icon = ""          // a research's icon (icons/<icon>.png)
    only = []::string  // the creatures or cultures a research is for
    line_name = ""     // a unit's line
    first = false      // a line's first step (trained where it's built, from its age)
    tier = 1
    early_kit = ""  // a line generated before its building opens: its first kit's name
    stats = ""      // a unit's numbers in words
    hotkey = ""
    recipe:JV? = nil  // a unit's look (its portrait)

class TColumn:
    id:string
    name:string
    age:int
    planned:bool
    lanes:int

class TAge:
    age:int
    name:string
    planned:bool
    needs:string  // "Needs a Barracks", "Where everyone starts"

class TTree:
    ages:[TAge]
    columns:[TColumn]
    nodes:[TNode]
    joins:[int2]  // node indexes: a line's steps, a research track

def cost_text(c:JV) -> string:
    let parts = []::string
    for(c.keys) r, n:
        let v = as_int(c.a[n])
        if v > 0: parts.push("{v} {r}")
    return concat_string(parts, ", ")

def race_lacks(ident:JV, id:string, rules:JV) -> bool:
    if gbool(rules, "full_tech_tree", false): return false
    return has_str(glist(ident, "lacks"), id) or has_str(glist(ident, "lacks_slots"), id)

// The race's unit for a roster slot, and the step of its line at an age (or nil).
def race_unit(race:JV, slot:string) -> JV?:
    for(glist(race, "units")) u:
        if rstr(at(u, "recipe"), "slot") == slot: return u
    return nil

def line_step(unit:JV?, age:int) -> JV?:
    if not unit: return nil
    for(glist(unit, "line")) l:
        if gint(l, "age", 0) == age: return l
    return nil

// A unit's numbers in words, from its eval.
def unit_stats(e:JV) -> string:
    let arm = gobj(e, "armour")
    return "HP {gint(e, "hp", 0)}  Attack {gint(e, "attack", 0)}  Armour {gint(arm, "melee", 0)}/{gint(arm, "pierce", 0)}  Range {gint(e, "range", 0)}  Speed {gint(e, "speed", 0)}"

def build_tree(p:int) -> TTree: return build_tree_of(su_races[p], su_sides[p], su_rules)

// Any race's tree (the lobby's banners open it before there's a match).
def build_tree_of(race:JV, ident:JV, rules:JV) -> TTree:
    let full = gbool(rules, "full_tech_tree", false)
    let bdata = lib_data("buildings.json")
    let tdata = lib_data("tech.json")
    let blds = at(bdata, "buildings")
    let ages_d = glist(tdata, "ages")
    let last_age = gint(ages_d[ages_d.length - 1], "age", 1)
    def age_planned(age:int) -> bool:
        for(ages_d) a:
            if gint(a, "age", 0) == age: return gstr(a, "status", "built") == "planned"
        return true
    def bname(id:string) -> string: return if has(blds, id): gstr(at(blds, id), "name", id) else: id
    let rows = map(ages_d) a:
        let planned = gstr(a, "status", "built") == "planned"
        // (a race that lacks a building the age needs needs its stand-in: no Stable, an Archery Range)
        let reqs = map(gstrs(a, "requires")) id: if race_lacks(ident, id, rules) and has(gobj(a, "requires_else"), id): gstr(gobj(a, "requires_else"), id, id) else: id
        var needs = "Where everyone starts"
        if gstr(a, "requires_text", "") != "": needs = "Needs " + gstr(a, "requires_text", "")
        elif reqs.length: needs = "Needs a " + concat_string(map(reqs) id: bname(id), " and a ")
        TAge { gint(a, "age", 1), gstr(a, "name", ""), planned, needs + (if planned: " (planned)" else: "") }
    var ids = filter(gstrs(bdata, "tree")) id: has(blds, id)
    let rest = filter(sorted_strs(blds.keys)) id: not has_s(ids, id)
    insertion_sort(rest) a, b: gint(at(blds, a), "age", 1) < gint(at(blds, b), "age", 1) or (gint(at(blds, a), "age", 1) == gint(at(blds, b), "age", 1) and a < b)
    ids = append(ids, rest)
    // Research a creature or culture names as its own (Identity.owners).
    let owners = dictionary<string, [string]>(64)
    for([ lib_creatures, lib_families ]) src:
        for(sorted_strs(src.keys)) id:
            for(gstrs(at(src, id), "research")) r:
                let o = owners.get(r) or []::string
                o.push(id)
                owners.set(r, o)
    let nodes = []::TNode
    let joins = []::int2
    let columns = []::TColumn
    for(ids) id:
        let b = at(blds, id)
        let col = columns.length
        let bplanned = gstr(b, "status", "built") == "planned"
        let bn = TNode { "b:" + id, "building", gstr(b, "name", id), gstr(b, "desc", ""), gint(b, "age", 1), bplanned, col }
        bn.id = id
        bn.building = id
        bn.lacks = race_lacks(ident, id, rules)
        bn.cost = cost_text(gobj(b, "cost"))
        bn.costv = gobj(b, "cost")
        bn.hotkey = gstr(b, "hotkey", "")
        nodes.push(bn)
        let lanes_g = []::[TNode]
        for(glist(rules, "roster")) sd:
            let slot = gstr(sd, "slot", "")
            let trainers = filter(blds.keys) t: has_s(gstrs(at(blds, t), "trains"), slot)  // (a mod can move a line; a planned one has only its label)
            if (if trainers.length: has_s(trainers, id) else: gstr(sd, "building", "") == id) and gstr(sd, "status", "") != "parked":
                let tier = gint(sd, "tier", 1)
                let first_age = max(tier, gint(b, "age", 1))
                let line_planned = gstr(sd, "status", "") == "planned"
                let line_name = gstr(sd, "name", capitalize(slot))
                def unit_node(key:string, name:string, desc:string, age:int, planned:bool) -> TNode:
                    let n = TNode { key, "unit", name, desc, age, planned, col }
                    n.id = slot
                    n.building = id
                    n.line_name = line_name
                    n.first = age == first_age
                    n.tier = tier
                    return n
                if not line_planned and (has_str(glist(race, "lacks"), slot) or race_lacks(ident, slot, rules)):
                    // no such line for this race (centaurs' archers already ride): one crossed-out node
                    let n = unit_node("u:{slot}@{first_age}", line_name, gstr(sd, "desc", ""), first_age, false)
                    n.lacks = true
                    lanes_g.push([ n ])
                elif gstr(sd, "role", "") == "hero":  // the race's heroes (D-138): one node each, where they're first trained
                    for(glist(race, "units")) hu:
                        let rec = at(hu, "recipe")
                        if rstr(rec, "slot") == slot:
                            let hs = at(at(lib_heroes, "hero_signatures"), rstr(rec, "hero"))
                            let n = unit_node("u:{slot}.{rstr(rec, "hero")}@{first_age}", gstr(rec, "name", line_name),
                                              gstr(hs, "temper", "") + "\nAura: " + gstr(gobj(hs, "aura"), "text", ""), first_age, false)
                            let st = line_step(hu, first_age)
                            n.recipe = if st: at(st, "recipe") else: rec
                            if st:
                                n.cost = cost_text(gobj(at(st, "eval"), "cost"))
                                n.costv = gobj(at(st, "eval"), "cost")
                                n.stats = unit_stats(at(st, "eval"))
                            lanes_g.push([ n ])
                else:
                    let unit = race_unit(race, slot)
                    let group = []::TNode
                    var prev = ""
                    var age = first_age
                    while age <= gint(sd, "last_age", last_age):
                        let st = line_step(unit, age)
                        let planned = line_planned or not st or age_planned(age)
                        let rk = if st: stringify(at(st, "recipe")) else: ""
                        // (the same unit as the age before: no node; Dominic: "if unit doesn't change, shouldn't show every age")
                        if planned or rk != prev:
                            if not planned: prev = rk
                            var name = line_name
                            var desc = gstr(sd, "desc", "")
                            if st:
                                name = gstr(at(st, "recipe"), "name", name)
                                let un = gstr(at(st, "recipe"), "unique", "")
                                if un != "": desc = gstr(at(lib_uniques, un), "desc", desc)
                            let n = unit_node("u:{slot}@{age}", name, desc, age, planned)
                            if st and not planned:
                                n.cost = cost_text(gobj(at(st, "eval"), "cost"))
                                n.costv = gobj(at(st, "eval"), "cost")
                                n.stats = unit_stats(at(st, "eval"))
                                n.recipe = at(st, "recipe")
                            if age == first_age and first_age > tier:
                                let early = line_step(unit, tier)
                                if early: n.early_kit = gstr(at(early, "recipe"), "name", "")
                            n.lacks = age > first_age and race_lacks(ident, "line.{slot}.{age}", rules)  // (royals' skirmishers stop at age 2)
                            group.push(n)
                        age++
                    if group.length: lanes_g.push(group)
        let here = filter(glist(tdata, "research")) r: gstr(r, "building", "") == id and (not has(r, "own") or full or has_str(glist(ident, "research"), gstr(r, "id", "")))
        let here_ids = map(here) r: gstr(r, "id", "")
        let done = []::string
        for(here) r:
            let rid = gstr(r, "id", "")
            if not has_s(done, rid) and not has_s(here_ids, gstr(r, "after", "")):
                let group = []::TNode
                var c = r
                while true:
                    let cid = gstr(c, "id", "")
                    done.push(cid)
                    let only = if has(c, "only"): gstrs(c, "only") else: owners.get(cid) or []::string
                    var lacks = only.length > 0 and not full and not (has_s(only, rstr(race, "creature")) or has_s(only, rstr(race, "family")))
                    lacks = lacks or race_lacks(ident, cid, rules)  // (what the race lacks)
                    let n = TNode { "r:" + cid, "research", gstr(c, "name", cid), gstr(c, "desc", ""), gint(c, "age", 1), gstr(c, "status", "built") == "planned", col }
                    n.id = cid
                    n.building = id
                    n.lacks = lacks
                    n.only = only
                    n.race_only = only.length > 0 and not lacks
                    n.cost = cost_text(gobj(c, "cost"))
                    n.costv = gobj(c, "cost")
                    n.effect = if has(c, "effect"): gstr(c, "effect", "") else: effect_text(glist(c, "effects"))
                    n.icon = gstr(c, "icon", cid)
                    group.push(n)
                    var nxt:JV? = nil
                    for(here) r2:
                        if gstr(r2, "after", "") == cid: nxt = r2
                    if not nxt: break
                    c = nxt
                lanes_g.push(group)
        // Pack: each group in the first lane free at all its ages (lines and tracks first, then singles).
        let ordered = append(filter(lanes_g) g: g.length > 1 or g[0].kind == "unit", filter(lanes_g) g: not (g.length > 1 or g[0].kind == "unit"))
        let used = []::[int]
        for(ordered) g:
            var lane = 0
            while lane < used.length and (filter(g) n: has_int(used[lane], n.age)).length > 0: lane++
            if lane == used.length: used.push([])
            for(g) n, k:
                used[lane].push(n.age)
                n.lane = lane
                if k > 0: joins.push(int2 { nodes.length - 1, nodes.length })
                nodes.push(n)
        columns.push(TColumn { id, gstr(b, "name", id), gint(b, "age", 1), bplanned, max(1, used.length) })
    return TTree { rows, columns, nodes, joins }

def has_int(xs:[int], v:int) -> bool:
    for(xs) x:
        if x == v: return true
    return false

// The race in words (TechTreeModel.identity_text, _race_panel): its bonuses and where each comes from, its own
// research, what it lacks, how its units move.
class RaceWords:
    bonuses:[string]
    own:[string]
    lacks:[string]
    moves:[string]

def slot_word(slot:string, rules:JV) -> string:
    for(glist(rules, "roster")) sd:
        if gstr(sd, "slot", "") == slot: return gstr(sd, "name", capitalize(slot))
    return capitalize(slot)

def race_words(p:int) -> RaceWords: return race_words_of(su_races[p], su_sides[p], su_rules)

def race_words_of(race:JV, ident:JV, rules:JV) -> RaceWords:
    let tdata = lib_data("tech.json")
    let blds = at(lib_data("buildings.json"), "buildings")
    def research_of(id:string) -> JV?:
        for(glist(tdata, "research")) r:
            if gstr(r, "id", "") == id: return r
        return nil
    let bonuses = map(glist(ident, "bonuses")) b: "{gstr(b, "text", "")} ({gstr(b, "from", "")})"
    let own = []::string
    for(gstrs(ident, "research")) id:
        let r = research_of(id)
        if r: own.push("{gstr(r, "name", id)}: {gstr(r, "desc", "")}" + (if gstr(r, "status", "") == "planned": " (planned)" else: ""))
    let lacks = []::string
    if not gbool(rules, "full_tech_tree", false):
        for(gstrs(ident, "lacks")) id:
            let r = research_of(id)
            if r: lacks.push(gstr(r, "name", id))
            elif has(blds, id): lacks.push(gstr(at(blds, id), "name", id) + (if glist(at(blds, id), "trains").length: " (and what it trains)" else: ""))
            elif id == "trade": lacks.push("Market trade (buying and selling)")
            elif starts_with(id, "line."):
                let parts = tokenize(id, ".", "")
                lacks.push("{slot_word(parts[1], rules)}\'s age-{parts[2]} step")
            else: lacks.push(slot_word(id, rules) + " line")
    for(gstrs(race, "lacks")) slot:
        let w = slot_word(slot, rules) + " line"
        if not has_s(lacks, w): lacks.push(w)
    // How it moves: the class each unit gets (rules.movement.classes, the first tag it has), in words.
    let words = gobj(lib_data("groups.json"), "movement")
    let classes = dictionary<string, [string]>(8)
    for(glist(race, "units")) u:
        let tags = gstrs(at(u, "eval"), "tags")
        var cls = "ground"
        for(glist(gobj(rules, "movement"), "classes")) e:
            if cls == "ground" and has_s(tags, gstr(e, "tag", "")): cls = gstr(e, "class", "ground")
        let names = classes.get(cls) or []::string
        names.push(gstr(at(u, "recipe"), "name", rstr(at(u, "recipe"), "slot")))
        classes.set(cls, names)
    let cnames = sorted_strs(classes.get_keys())
    let moves = map(cnames) cls:
        let text = gstr(words, cls, capitalize(cls))
        if cnames.length == 1: text else: "{text} ({concat_string(classes.get(cls) or []::string, ", ")})"
    return RaceWords { bonuses, own, lacks, moves }

// The page's state (game/techtree_page.lobster draws it; the lobby and the match open it).
var tree_lobby = false  // opened from the lobby: no F1
var tree_title = ""
var tree_page:TTree? = nil
var tree_words:RaceWords? = nil
var tree_scroll = 0.0  // screen px across
var tree_waiting = 0   // pictures still being painted (captures wait for them)
