// Research effects in words: what a research in tech.json does, as a line of text. The tech tree page shows them.

def signed(n:int) -> string: return if n >= 0: "+{n}" else: "{n}"

def effect_subject(e:JV) -> string:
    if has(e, "building"):
        let b = at(e, "building")
        if b.kind == J_ARR:
            let names = map(b.a) v: capitalize(as_str(v)) + "s"
            return if names.length == 1: names[0] else: concat_string(names.slice(0, names.length - 1), ", ") + " and " + names[names.length - 1]
        return if as_str(b) == "all": "Buildings" else: capitalize(as_str(b)) + "s"
    let nots = gstrs(e, "not")
    let tag = gstr(e, "tag", "")
    var who = if tag == "worker": "Workers" elif tag == "all": "Every unit" else: capitalize(tag) + " units"
    if has_s(nots, "mounted"): who = "Foot " + lowercase(who)
    let rest = filter(nots) t: t != "mounted"
    if rest.length: who += " (not " + concat_string(rest, ", ") + ")"
    return who

def effect_phrase(stat:string, n:int, pct:bool) -> string:
    let a = abs(n)
    if pct:
        if stat == "reload": return "reload {a}% " + (if n < 0: "faster" else: "slower")
        if stat == "train_time": return "train {a}% " + (if n < 0: "faster" else: "slower")
        if stat == "research_time": return "research {a}% " + (if n < 0: "faster" else: "slower")
        if stat == "age_time": return "advance ages {a}% " + (if n < 0: "faster" else: "slower")
        if stat == "build_speed": return "build {a}% " + (if n > 0: "faster" else: "slower")
        if stat == "cost": return "{a}% " + (if n < 0: "cheaper" else: "dearer")
        if stat == "food": return "hold {a}% " + (if n > 0: "more" else: "less") + " food"
        if stat == "hp": return signed(n) + "% HP"
        return signed(n) + "% " + concat_string(tokenize(stat, "_", ""), " ")
    if stat == "hp": return signed(n) + " HP"
    if stat == "carry": return "carry " + signed(n)
    if stat == "range": return signed(n) + " range"
    if stat == "trade_fee": return "trade fee {a} points " + (if n < 0: "lower" else: "higher") + " (selling pays more)"
    if starts_with(stat, "armour."): return signed(n) + " " + substring(stat, 7, stat.length - 7) + " armour"
    return signed(n) + " " + concat_string(tokenize(stat, "_", ""), " ")

def effect_text(effects:[JV]) -> string:
    let out = []::string
    var last = ""
    for(effects) e:
        if has(e, "gather"):
            out.push(capitalize(gstr(e, "gather", "")) + " gathered {gint(e, "pct", 0)}% faster")
            last = ""
        elif has(e, "start"):
            out.push(signed(gint(e, "add", 0)) + " " + gstr(e, "start", "") + " at the start")
            last = ""
        elif has(e, "becomes"):  // tower_upgrade
            out.push(capitalize(gstr(e, "building", "")) + "s become " + capitalize(gstr(e, "becomes", "")) + "s")
            last = ""
        else:
            let who = effect_subject(e)
            let pct = has(e, "pct")
            let what = effect_phrase(gstr(e, "stat", ""), if pct: gint(e, "pct", 0) else: gint(e, "add", 0), pct)
            if who == last: out[out.length - 1] = out[out.length - 1] + ", " + what
            else: out.push(who + " " + what)
            last = who
    var commas = false
    for(out) o:
        if find_string(o, ",") >= 0: commas = true
    return concat_string(out, if commas: "; " else: ", ")
