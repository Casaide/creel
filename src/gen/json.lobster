// ------------------------------------------------------------------ JSON (the data contract, Godot's JSON)
// A JSON value that keeps its keys in file order (as Godot's Dictionary does), read from text and
// written back as Godot's JSON.stringify(v, "", true) writes it: no spaces, keys sorted, integers
// without a point. Numbers keep whether they were written as integers.

let J_NULL = 0
let J_BOOL = 1
let J_INT = 2
let J_FLOAT = 3
let J_STR = 4
let J_ARR = 5
let J_OBJ = 6

class JV:
    kind:int
    i = 0
    f = 0.0
    s = ""
    a:[JV] = []
    keys:[string] = []
    index:dictionary<string, int>? = nil  // made once an object is looked up often

def jnull() -> JV: return JV { J_NULL }
def jint(v:int) -> JV:
    let o = JV { J_INT }
    o.i = v
    return o
def jbool(v:bool) -> JV:
    let o = JV { J_BOOL }
    o.i = if v: 1 else: 0
    return o
def jstr(v:string) -> JV:
    let o = JV { J_STR }
    o.s = v
    return o
def jarr(vs:[JV]) -> JV:
    let o = JV { J_ARR }
    o.a = vs
    return o
def jobj() -> JV: return JV { J_OBJ }
def jstrs(vs:[string]) -> JV: return jarr(map(vs) v: jstr(v))

// ---- objects

def key_at(o:JV, k:string) -> int:
    if o.kind != J_OBJ: return -1
    if o.keys.length > 12:
        if not o.index:
            let ix = dictionary<string, int>(o.keys.length * 2 + 1)
            for(o.keys) key, n: ix.set(key, n)
            o.index = ix
        let ix = o.index
        return ix.get(k, -1)
    for(o.keys) key, n:
        if key == k: return n
    return -1

def has(o:JV, k:string) -> bool: return key_at(o, k) >= 0

def get(o:JV, k:string) -> JV?:
    let n = key_at(o, k)
    return if n >= 0: o.a[n] else: nil

def at(o:JV, k:string) -> JV:
    let n = key_at(o, k)
    if n < 0: print "no key \"{k}\" in {o.keys}"  // (which, before the assertion stops it)
    assert n >= 0
    return o.a[n]

def set(o:JV, k:string, v:JV):
    assert o.kind == J_OBJ
    let n = key_at(o, k)
    if n >= 0: o.a[n] = v
    else:
        o.keys.push(k)
        o.a.push(v)
        let ix = o.index
        if ix: ix.set(k, o.keys.length - 1)

def erase(o:JV, k:string):
    let n = key_at(o, k)
    if n >= 0:
        o.keys.remove(n)
        o.a.remove(n)
        o.index = nil

// ---- reading values (as GDScript's int(), String(), .get(k, default) read them)

def as_int(v:JV) -> int:
    if v.kind == J_INT or v.kind == J_BOOL: return v.i
    if v.kind == J_FLOAT: return int(v.f)
    assert false
    return 0

def as_float(v:JV) -> float: return if v.kind == J_FLOAT: v.f else: float(as_int(v))
def as_str(v:JV) -> string:
    assert v.kind == J_STR
    return v.s
def as_bool(v:JV) -> bool: return if v.kind == J_BOOL or v.kind == J_INT: v.i != 0 else: v.kind != J_NULL

def gint(o:JV, k:string, fallback:int) -> int:
    let v = get(o, k)
    return if v: as_int(v) else: fallback
def gstr(o:JV, k:string, fallback:string) -> string:
    let v = get(o, k)
    return if v: as_str(v) else: fallback
def gbool(o:JV, k:string, fallback:bool) -> bool:
    let v = get(o, k)
    return if v: as_bool(v) else: fallback
def glist(o:JV, k:string) -> [JV]:
    let v = get(o, k)
    return if v: v.a else: []::JV
def gstrs(o:JV, k:string) -> [string]: return map(glist(o, k)) v: as_str(v)
def gobj(o:JV, k:string) -> JV:
    let v = get(o, k)
    return v or jobj()

def has_str(vs:[JV], s:string) -> bool:
    for(vs) v:
        if v.kind == J_STR and v.s == s: return true
    return false

// ---- copies and equality

def deep_copy(v:JV) -> JV:
    let o = JV { v.kind }
    o.i = v.i
    o.f = v.f
    o.s = v.s
    o.a = []
    for(v.a) x: o.a.push(deep_copy(x))
    o.keys = copy(v.keys)
    return o

def shallow_copy(v:JV) -> JV:
    let o = JV { v.kind }
    o.i = v.i
    o.f = v.f
    o.s = v.s
    o.a = copy(v.a)
    o.keys = copy(v.keys)
    return o

// Godot's == on values: objects equal whatever their key order.
def jequal(x:JV, y:JV) -> bool:
    if x.kind != y.kind:
        if (x.kind == J_INT or x.kind == J_FLOAT) and (y.kind == J_INT or y.kind == J_FLOAT): return as_float(x) == as_float(y)
        return false
    switch x.kind:
        case J_NULL: return true
        case J_BOOL, J_INT: return x.i == y.i
        case J_FLOAT: return x.f == y.f
        case J_STR: return x.s == y.s
        case J_ARR:
            if x.a.length != y.a.length: return false
            for(x.a) v, n:
                if not jequal(v, y.a[n]): return false
            return true
        default:
            if x.keys.length != y.keys.length: return false
            for(x.keys) k, n:
                let w = get(y, k)
                if not w or not jequal(x.a[n], w): return false
            return true

// ---- parsing

var jp_text = ""
var jp_at = 0

def jp_space():
    while jp_at < jp_text.length:
        let c = jp_text[jp_at]
        if c == ' ' or c == '\n' or c == '\r' or c == '\t': jp_at++
        else: return

def jp_string() -> string:
    assert jp_text[jp_at] == '\"'
    jp_at++
    var out = ""
    var start = jp_at
    while jp_text[jp_at] != '\"':
        if jp_text[jp_at] == '\\':
            out += substring(jp_text, start, jp_at - start)
            let e = jp_text[jp_at + 1]
            jp_at += 2
            switch e:
                case 'n': out += "\n"
                case 't': out += "\t"
                case 'r': out += "\r"
                case 'b': out += unicode_to_string([ 8 ])
                case 'f': out += unicode_to_string([ 12 ])
                case 'u':
                    let code, ok = string_to_int(substring(jp_text, jp_at, 4), 16)
                    assert ok
                    out += unicode_to_string([ code ])
                    jp_at += 4
                default: out += unicode_to_string([ e ])
            start = jp_at
        else: jp_at++
    out += substring(jp_text, start, jp_at - start)
    jp_at++
    return out

def jp_value() -> JV:
    jp_space()
    let c = jp_text[jp_at]
    if c == '{':
        jp_at++
        let o = jobj()
        jp_space()
        if jp_text[jp_at] == '}':
            jp_at++
            return o
        while true:
            jp_space()
            let k = jp_string()
            jp_space()
            assert jp_text[jp_at] == ':'
            jp_at++
            let v = jp_value()
            o.keys.push(k)
            o.a.push(v)
            jp_space()
            if jp_text[jp_at] == ',': jp_at++
            else:
                assert jp_text[jp_at] == '}'
                jp_at++
                return o
    if c == '[':
        jp_at++
        let o = jarr([]::JV)
        jp_space()
        if jp_text[jp_at] == ']':
            jp_at++
            return o
        while true:
            o.a.push(jp_value())
            jp_space()
            if jp_text[jp_at] == ',': jp_at++
            else:
                assert jp_text[jp_at] == ']'
                jp_at++
                return o
    if c == '\"': return jstr(jp_string())
    if c == 't':
        jp_at += 4
        return jbool(true)
    if c == 'f':
        jp_at += 5
        return jbool(false)
    if c == 'n':
        jp_at += 4
        return jnull()
    let start = jp_at
    var is_float = false
    while jp_at < jp_text.length:
        let d = jp_text[jp_at]
        if (d >= '0' and d <= '9') or d == '-' or d == '+': jp_at++
        elif d == '.' or d == 'e' or d == 'E':
            is_float = true
            jp_at++
        else: break
    let num = substring(jp_text, start, jp_at - start)
    // (Godot reads every number as a float, and writes a whole one back as "40.0")
    let o = JV { J_FLOAT }
    if is_float: o.f = string_to_float(num)
    else:
        let v, ok = string_to_int(num)
        assert ok
        o.f = float(v)
    return o

def parse_json(text:string) -> JV:
    jp_text = text
    jp_at = 0
    return jp_value()

def load_json(path:string) -> JV: return parse_json(assert read_file(path))

// ---- writing, as Godot's JSON.stringify(v, "", true)

def json_escape(s:string) -> string:
    var out = ""
    var start = 0
    for(s.length) n:
        let c = s[n]
        var esc = ""
        if c == '\"': esc = "\\\""
        elif c == '\\': esc = "\\\\"
        elif c == '\n': esc = "\\n"
        elif c == '\t': esc = "\\t"
        elif c == '\r': esc = "\\r"
        elif c == 8: esc = "\\b"
        elif c == 12: esc = "\\f"
        if esc.length:
            out += substring(s, start, n - start) + esc
            start = n + 1
    return out + substring(s, start, s.length - start)

// A float as Godot's JSON writes it: whole ones with ".0", others in their shortest form, no exponent.
def godot_float(f:float) -> string:
    if f == floor(f) and abs(f) < 1000000000000000.0: return string(int(f)) + ".0"
    let s = number_to_string_f(f)
    return s

def number_to_string_f(f:float) -> string:
    var digits = 1
    while digits < 17:
        let old = set_print_decimals(digits)
        let s = string(f)
        set_print_decimals(old)
        if string_to_float(s) == f: return trim_zeros(s)
        digits++
    let old = set_print_decimals(17)
    let s = string(f)
    set_print_decimals(old)
    return trim_zeros(s)

def trim_zeros(s:string) -> string:
    if find_string(s, ".") < 0: return s
    var e = s.length
    while e > 0 and s[e - 1] == '0': e--
    if e > 0 and s[e - 1] == '.': e--
    return substring(s, 0, e)

def stringify(v:JV) -> string:
    switch v.kind:
        case J_NULL: return "null"
        case J_BOOL: return if v.i != 0: "true" else: "false"
        case J_INT: return string(v.i)
        case J_FLOAT: return godot_float(v.f)
        case J_STR: return "\"" + json_escape(v.s) + "\""
        case J_ARR:
            let parts = []::string
            for(v.a) x: parts.push(stringify(x))
            return "[" + concat_string(parts, ",") + "]"
        default:
            let order = copy(v.keys)
            insertion_sort(order) a, b: a < b
            let parts = []::string
            for(order) k: parts.push("\"" + json_escape(k) + "\":" + stringify(at(v, k)))
            return "\{" + concat_string(parts, ",") + "\}"

def starts_with(s:string, pre:string) -> bool: return s.length >= pre.length and substring(s, 0, pre.length) == pre
def ends_with(s:string, post:string) -> bool: return s.length >= post.length and substring(s, s.length - post.length, post.length) == post
def has_char(s:string, c:int) -> bool:
    for(s.length) n:
        if s[n] == c: return true
    return false

def rstr(r:JV, k:string) -> string: return as_str(at(r, k))
def prompt_words(s:string) -> [string]: return filter(tokenize(s, " ", "")) w: w.length > 0

// A string without the blanks at its ends.
def strip_edges(s:string) -> string:
    var a = 0
    var b = s.length
    while a < b and s[a] <= ' ': a++
    while b > a and s[b - 1] <= ' ': b--
    return substring(s, a, b - a)
