// ------------------------------------------------------------------ Lua for mods' rules (#82)
// A Lua interpreter, written in Lobster so it needs nothing from outside it and runs the same in every build. It runs
// the part of Lua 5.4 that rule code needs, cut to what lockstep allows:
// - integers only (61 bits, signed): float literals, `/` and `^` are refused when a file loads; `//` and `%` floor as in Lua.
// - no hidden state: a pack's files run once, at the match start; after that the tables, globals and file-level locals
//   they made are read-only, and state that lasts goes in the sim's declared hook columns (lua/api.lobster).
// - `pairs` goes in insertion order, the same on every machine.
// - nothing but what's given: no io, os, require, load, debug, metatables or coroutines.
// - a step budget per call: over it, or on any error, the pack's hooks are off for the match, everywhere alike.
// - what a call makes (tables, strings, closures) is dropped when it returns, so there's no collector to differ.
// The sim's API and the hook points are lua/api.lobster's.

import std
import dictionary

// ------------------------------------------------------------------ values
// A value is one int: its low 3 bits say what it is. An integer is n << 3 (so + and - need no unpacking); nil, false
// and true are fixed; a string, table, closure or builtin is its index << 3 with its tag.
let LV_NIL = 1
let LV_FALSE = 2
let LV_TRUE = 10
let LT_INT = 0
let LT_NIL = 1
let LT_BOOL = 2
let LT_STR = 3
let LT_TAB = 4
let LT_FUN = 5
let LT_BUILTIN = 6

def lv_int(n:int) -> int: return n << 3
def lv_bool(b:bool) -> int: return if b: LV_TRUE else: LV_FALSE
def lv_tag(v:int) -> int: return v & 7
def lv_n(v:int) -> int: return v >> 3
def lv_truthy(v:int) -> bool: return v != LV_NIL and v != LV_FALSE
def lv_is_int(v:int) -> bool: return (v & 7) == 0

// Strings, interned: equal strings are the same value.
var ls_text = []::string
var ls_ids = dictionary<string, int>(1009)

def lv_str(s:string) -> int:
    let known = ls_ids.get(s, -1)
    if known >= 0: return (known << 3) | LT_STR
    ls_text.push(s)
    ls_ids.set(s, ls_text.length - 1)
    return ((ls_text.length - 1) << 3) | LT_STR

def lv_text(v:int) -> string: return ls_text[v >> 3]

// Tables: an array part (keys 1..n) and the rest in insertion order, looked up through a dictionary once it grows.
var lt_arr = []::[int]
var lt_keys = []::[int]
var lt_vals = []::[int]
var lt_map = []::dictionary<int, int>?

def lv_table() -> int:
    lt_arr.push([])
    lt_keys.push([])
    lt_vals.push([])
    lt_map.push(nil)
    return ((lt_arr.length - 1) << 3) | LT_TAB

// Closures: a prototype and the boxes it captured. Boxes hold the locals closures share.
var lc_proto = []::int
var lc_ups = []::[int]
var lbox = []::int

// The builtins' names, by id (the base library's, then lua/api's).
var lb_names = []::string

var l_env = LV_NIL  // the running pack's globals (a table)

// The base library's builtins, by id.
let B_PRINT = 0
let B_TYPE = 1
let B_TOSTRING = 2
let B_TONUMBER = 3
let B_ERROR = 4
let B_ASSERT = 5
let B_IPAIRS = 6
let B_PAIRS = 7
let B_IPAIRS_NEXT = 8
let B_PAIRS_NEXT = 9
let B_SELECT = 10
let B_NEXT = 11
let B_MATH_MIN = 12
let B_MATH_MAX = 13
let B_MATH_ABS = 14
let B_STR_SUB = 15
let B_STR_LEN = 16
let B_STR_FORMAT = 17
let B_STR_REP = 18
let B_STR_BYTE = 19
let B_TAB_INSERT = 20
let B_TAB_REMOVE = 21
let B_TAB_SORT = 22
let B_TAB_CONCAT = 23
let B_STR_UPPER = 24
let B_STR_LOWER = 25
let B_STR_FIND = 26
let B_COUNT = 27
let L_BASE_NAMES = [ "print", "type", "tostring", "tonumber", "error", "assert", "ipairs", "pairs", "(ipairs)", "(pairs)",
    "select", "next", "math.min", "math.max", "math.abs", "string.sub", "string.len", "string.format", "string.rep",
    "string.byte", "table.insert", "table.remove", "table.sort", "table.concat", "string.upper", "string.lower",
    "string.find" ]

// ------------------------------------------------------------------ the syntax tree
let N_NIL = 0
let N_TRUE = 1
let N_FALSE = 2
let N_CONST = 3     // n: the value (an integer or a string)
let N_LOCAL = 4     // n: slot
let N_UPV = 5       // n: upvalue
let N_GLOBAL = 6    // n: the name (a string value)
let N_INDEX = 7     // a: object, key
let N_CALL = 8      // a: function, args...
let N_METHOD = 9    // n: name; a: object, args...
let N_FUNC = 10     // n: prototype
let N_BIN = 11      // n: operator; a: left, right
let N_AND = 12
let N_OR = 13
let N_NOT = 14
let N_NEG = 15
let N_LEN = 16
let N_BNOT = 17
let N_TABLE = 18    // a: items; an N_TPAIR is a keyed one
let N_TPAIR = 19    // a: key, value
let N_PAREN = 20    // a: the expression, cut to one value
let N_LOCALS = 30   // n: names; s: their slots; a: the values
let N_ASSIGN = 31   // n: targets; a: targets, then values
let N_CALLST = 32   // a: the call
let N_IF = 33       // a: cond, block, cond, block, ... (else block when n is 1)
let N_WHILE = 34    // a: cond, block
let N_REPEAT = 35   // a: block, cond
let N_NUMFOR = 36   // n: slot; a: start, limit, step, block
let N_GENFOR = 37   // s: slots; a: the values, block (last)
let N_RETURN = 38   // a: values
let N_BREAK = 39
let N_BLOCK = 40    // a: statements
let N_LOCALFN = 41  // n: slot; a: the function

let OP_ADD = 0
let OP_SUB = 1
let OP_MUL = 2
let OP_IDIV = 3
let OP_MOD = 4
let OP_CONCAT = 5
let OP_EQ = 6
let OP_NE = 7
let OP_LT = 8
let OP_LE = 9
let OP_GT = 10
let OP_GE = 11
let OP_BAND = 12
let OP_BOR = 13
let OP_BXOR = 14
let OP_SHL = 15
let OP_SHR = 16

class LNode:
    k:int
    n:int
    line:int
    a:[LNode]
    s:[int]
    c = -1  // a global's value, once the load is over (they're read-only then); -1 until it's looked up

class LProto:
    name:string
    file:string
    params:int
    slots:int
    boxed:[bool]  // per slot: a closure captures it, so it lives in a box
    ups:[int]     // per upvalue: the parent's slot * 2, or its upvalue * 2 + 1
    body:LNode

var l_protos = []::LProto

// ------------------------------------------------------------------ errors and the budget
var lerr = ""         // the error the running code stopped on ("" while all is well)
var lfail = false     // lerr is set
var lerr_file = ""
var lline = 0
var lsteps = 0
var lbudget = 0
var ldepth = 0
let L_MAX_DEPTH = 200

def lua_fail(msg:string):
    if not lfail:
        lerr = "{lerr_file}:{lline}: {msg}"
        lfail = true

def lv_type_name(v:int) -> string:
    let t = v & 7
    return if t == LT_INT: "number" elif t == LT_NIL: "nil" elif t == LT_BOOL: "boolean" elif t == LT_STR: "string" elif t == LT_TAB: "table" else: "function"

// ------------------------------------------------------------------ the lexer
let TK_EOF = 0
let TK_NAME = 1
let TK_INT = 2
let TK_STR = 3
let TK_OP = 4

var tk_kind = []::int
var tk_int = []::int
var tk_text = []::string
var tk_line = []::int
var lex_err = ""

let L_KEYWORDS = [ "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while" ]
let L_OPS3 = [ "..." ]
let L_OPS2 = [ "==", "~=", "<=", ">=", "//", "..", "<<", ">>", "::" ]

def lx_is_name_start(c:int) -> bool: return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
def lx_is_digit(c:int) -> bool: return c >= '0' and c <= '9'
def lx_is_hex(c:int) -> bool: return lx_is_digit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')
def lx_hex_val(c:int) -> int: return if lx_is_digit(c): c - '0' elif c >= 'a': c - 'a' + 10 else: c - 'A' + 10

def lx_lex_push(kind:int, n:int, text:string, line:int):
    tk_kind.push(kind)
    tk_int.push(n)
    tk_text.push(text)
    tk_line.push(line)

// A long bracket's level at i ("[[" is 0, "[=[" is 1), or -1 if there's none.
def lx_long_level(src:string, i:int) -> int:
    if src[i] != '[': return -1
    var j = i + 1
    while j < src.length and src[j] == '=': j++
    return if j < src.length and src[j] == '[': j - i - 1 else: -1

// The end of a long bracket opened at i with this level: the index after it, or -1.
def lx_long_end(src:string, i:int, lvl:int) -> int:
    var j = i + lvl + 2
    while j < src.length:
        if src[j] == ']':
            var e = j + 1
            while e < src.length and src[e] == '=': e++
            if e < src.length and src[e] == ']' and e - j - 1 == lvl: return e + 1
        j++
    return -1

def lx_lex(src:string):
    tk_kind = []
    tk_int = []
    tk_text = []
    tk_line = []
    lex_err = ""
    var i = 0
    var line = 1
    let n = src.length
    while i < n and lex_err == "":
        let c = src[i]
        if c == '\n':
            line++
            i++
        elif c == ' ' or c == '\t' or c == '\r':
            i++
        elif c == '-' and i + 1 < n and src[i + 1] == '-':
            let lv = if i + 2 < n: lx_long_level(src, i + 2) else: -1
            if lv >= 0:
                let e = lx_long_end(src, i + 2, lv)
                if e < 0:
                    lex_err = "{line}: unfinished long comment"
                else:
                    for(e - i) k:
                        if src[i + k] == '\n': line++
                    i = e
            else:
                while i < n and src[i] != '\n': i++
        elif lx_is_name_start(c):
            let s = i
            while i < n and (lx_is_name_start(src[i]) or lx_is_digit(src[i])): i++
            let w = substring(src, s, i - s)
            if has_s(L_KEYWORDS, w): lx_lex_push(TK_OP, 0, w, line)
            else: lx_lex_push(TK_NAME, 0, w, line)
        elif lx_is_digit(c) or (c == '.' and i + 1 < n and lx_is_digit(src[i + 1])):
            var v = 0
            if c == '0' and i + 1 < n and (src[i + 1] == 'x' or src[i + 1] == 'X'):
                i += 2
                if i >= n or not lx_is_hex(src[i]): lex_err = "{line}: a malformed number"
                while i < n and lx_is_hex(src[i]):
                    v = v * 16 + lx_hex_val(src[i])
                    i++
            else:
                while i < n and lx_is_digit(src[i]):
                    v = v * 10 + (src[i] - '0')
                    i++
            if i < n and (src[i] == '.' or src[i] == 'e' or src[i] == 'E' or src[i] == 'p' or src[i] == 'P'):
                lex_err = "{line}: numbers are integers here (lockstep): no fractions or exponents"
            elif i < n and lx_is_name_start(src[i]):
                lex_err = "{line}: a malformed number"
            lx_lex_push(TK_INT, v, "", line)
        elif c == '\"' or c == '\'':
            i++
            var out = ""
            while i < n and src[i] != c and lex_err == "":
                var ch = src[i]
                if ch == '\n':
                    lex_err = "{line}: unfinished string"
                elif ch == '\\':
                    i++
                    if i >= n:
                        lex_err = "{line}: unfinished string"
                    else:
                        let e = src[i]
                        if e == 'n': out += "\n"
                        elif e == 't': out += "\t"
                        elif e == 'r': out += "\r"
                        elif e == '\\': out += "\\"
                        elif e == '\"': out += "\""
                        elif e == '\'': out += "\'"
                        elif e == '\n':
                            out += "\n"
                            line++
                        elif lx_is_digit(e):
                            var v = 0
                            var k = 0
                            while k < 3 and i < n and lx_is_digit(src[i]):
                                v = v * 10 + (src[i] - '0')
                                i++
                                k++
                            i--
                            if v > 255: lex_err = "{line}: an escape past 255"
                            out += unicode_to_string([ v ])
                        else:
                            lex_err = "{line}: an escape this Lua doesn\'t know"
                        i++
                else:
                    out += unicode_to_string([ ch ])
                    i++
            if i >= n and lex_err == "": lex_err = "{line}: unfinished string"
            i++
            lx_lex_push(TK_STR, 0, out, line)
        elif c == '[' and lx_long_level(src, i) >= 0:
            let lv = lx_long_level(src, i)
            let e = lx_long_end(src, i, lv)
            if e < 0:
                lex_err = "{line}: unfinished long string"
            else:
                var s = i + lv + 2
                if s < n and src[s] == '\n': s++
                let text = substring(src, s, e - lv - 2 - s)
                lx_lex_push(TK_STR, 0, text, line)
                for(e - i) k:
                    if src[i + k] == '\n': line++
                i = e
        else:
            var op = ""
            if i + 3 <= n and has_s(L_OPS3, substring(src, i, 3)): op = substring(src, i, 3)
            elif i + 2 <= n and has_s(L_OPS2, substring(src, i, 2)): op = substring(src, i, 2)
            elif find_string("+-*/%^#&~|<>=(){{}}[];:,.", unicode_to_string([ c ])) >= 0: op = unicode_to_string([ c ])
            if op == "":
                lex_err = "{line}: a character this Lua doesn\'t read"
            else:
                lx_lex_push(TK_OP, 0, op, line)
                i += op.length
    lx_lex_push(TK_EOF, 0, "<eof>", line)

// ------------------------------------------------------------------ the parser
class LScope:  // a function being parsed
    parent:LScope?
    proto:LProto
    names:[string]  // the locals in scope, innermost last
    slots:[int]
    upnames:[string]

var ltp = 0           // the token being looked at
var perr = ""        // the first parse error
var pfile = ""
var pscopes = []::LScope  // the functions being parsed, innermost last

def lx_node(k:int, n:int, a:[LNode]) -> LNode: return LNode { k, n, tk_line[min(ltp, tk_line.length - 1)], a, [] }

def lx_tk_is(op:string) -> bool: return tk_kind[ltp] == TK_OP and tk_text[ltp] == op

def lx_perror(msg:string):
    if perr == "": perr = "{pfile}:{tk_line[ltp]}: {msg}"

def lx_expect(op:string):
    if lx_tk_is(op): ltp++
    else: lx_perror("\'{op}\' expected near \'{tk_text[ltp]}\'")

def lx_accept(op:string) -> bool:
    if lx_tk_is(op):
        ltp++
        return true
    return false

def lx_name_tok() -> string:
    if tk_kind[ltp] != TK_NAME:
        lx_perror("a name expected near \'{tk_text[ltp]}\'")
        return "_"
    ltp++
    return tk_text[ltp - 1]

def lx_block_ends() -> bool:
    return tk_kind[ltp] == TK_EOF or lx_tk_is("end") or lx_tk_is("else") or lx_tk_is("elseif") or lx_tk_is("until")

def lx_scope() -> LScope: return top(pscopes)

def lx_new_local(name:string) -> int:
    let sc = lx_scope()
    let slot = sc.proto.slots
    sc.proto.slots++
    sc.proto.boxed.push(false)
    sc.names.push(name)
    sc.slots.push(slot)
    return slot

// Where a name is: (N_LOCAL, slot), (N_UPV, index) or (N_GLOBAL, 0).
def lx_resolve_in(sc:LScope, name:string) -> int, int:
    var j = sc.names.length - 1
    while j >= 0:
        if sc.names[j] == name: return N_LOCAL, sc.slots[j]
        j--
    let up = find(sc.upnames): _ == name
    if up >= 0: return N_UPV, up
    let parent = sc.parent
    if not parent: return N_GLOBAL, 0
    let k, at = lx_resolve_in(parent, name)
    if k == N_GLOBAL: return N_GLOBAL, 0
    if k == N_LOCAL:
        parent.proto.boxed[at] = true
        sc.proto.ups.push(at * 2)
    else:
        sc.proto.ups.push(at * 2 + 1)
    sc.upnames.push(name)
    return N_UPV, sc.upnames.length - 1

def lx_name_node(name:string) -> LNode:
    let k, at = lx_resolve_in(lx_scope(), name)
    return lx_node(k, if k == N_GLOBAL: lv_str(name) else: at, [])

def lx_parse_block() -> LNode:
    let sc = lx_scope()
    let depth = sc.names.length
    let stmts = []::LNode
    while not lx_block_ends() and perr == "":
        if lx_tk_is("return"):
            let r = lx_node(N_RETURN, 0, [])
            ltp++
            if not lx_block_ends() and not lx_tk_is(";"): r.a = lx_parse_exprs()
            lx_accept(";")
            stmts.push(r)
            if not lx_block_ends(): lx_perror("\'return\' must end its block")
            break
        let s = lx_parse_statement()
        if s: stmts.push(s)
    truncate(sc.names, depth)
    truncate(sc.slots, depth)
    return lx_node(N_BLOCK, 0, stmts)

def lx_parse_statement() -> LNode?:
    let line = tk_line[ltp]
    if lx_accept(";"): return nil
    if lx_tk_is("::") or lx_tk_is("goto"):
        lx_perror("goto and labels aren\'t in this Lua")
        return nil
    if lx_accept("break"): return lx_node(N_BREAK, 0, [])
    if lx_accept("do"):
        let b = lx_parse_block()
        lx_expect("end")
        return b
    if lx_accept("while"):
        let c = lx_parse_expr(0)
        lx_expect("do")
        let b = lx_parse_block()
        lx_expect("end")
        return lx_node(N_WHILE, 0, [ c, b ])
    if lx_accept("repeat"):
        let sc = lx_scope()
        let depth = sc.names.length
        let stmts = []::LNode
        while not lx_block_ends() and perr == "":
            let s = lx_parse_statement()
            if s: stmts.push(s)
        lx_expect("until")
        let c = lx_parse_expr(0)  // (it sees the block's locals, as in Lua)
        truncate(sc.names, depth)
        truncate(sc.slots, depth)
        return lx_node(N_REPEAT, 0, [ lx_node(N_BLOCK, 0, stmts), c ])
    if lx_accept("if"):
        let parts = []::LNode
        parts.push(lx_parse_expr(0))
        lx_expect("then")
        parts.push(lx_parse_block())
        var has_else = 0
        while perr == "":
            if lx_accept("elseif"):
                parts.push(lx_parse_expr(0))
                lx_expect("then")
                parts.push(lx_parse_block())
            elif lx_accept("else"):
                parts.push(lx_parse_block())
                has_else = 1
                lx_expect("end")
                break
            else:
                lx_expect("end")
                break
        return lx_node(N_IF, has_else, parts)
    if lx_accept("for"):
        let n1 = lx_name_tok()
        if lx_accept("="):
            let start = lx_parse_expr(0)
            lx_expect(",")
            let limit = lx_parse_expr(0)
            let step = if lx_accept(","): lx_parse_expr(0) else: lx_node(N_CONST, lv_int(1), [])
            lx_expect("do")
            let sc = lx_scope()
            let depth = sc.names.length
            let slot = lx_new_local(n1)
            let b = lx_parse_block()
            truncate(sc.names, depth)
            truncate(sc.slots, depth)
            lx_expect("end")
            return lx_node(N_NUMFOR, slot, [ start, limit, step, b ])
        let names = [ n1 ]
        while lx_accept(","): names.push(lx_name_tok())
        lx_expect("in")
        let vals = lx_parse_exprs()
        lx_expect("do")
        let sc = lx_scope()
        let depth = sc.names.length
        let slots = map(names) nm: lx_new_local(nm)
        let b = lx_parse_block()
        truncate(sc.names, depth)
        truncate(sc.slots, depth)
        lx_expect("end")
        let f = lx_node(N_GENFOR, 0, append(vals, [ b ]))
        f.s = slots
        return f
    if lx_accept("function"):
        // function a.b.c:m(...)
        var target = lx_name_node(lx_name_tok())
        var fname = tk_text[ltp - 1]
        var method = false
        while perr == "" and (lx_tk_is(".") or lx_tk_is(":")):
            method = lx_tk_is(":")
            ltp++
            let key = lx_name_tok()
            fname += "." + key
            target = lx_node(N_INDEX, 0, [ target, lx_node(N_CONST, lv_str(key), []) ])
            if method: break
        let f = lx_parse_function(fname, method)
        return lx_node(N_ASSIGN, 1, [ target, f ])
    if lx_accept("local"):
        if lx_accept("function"):
            let nm = lx_name_tok()
            let slot = lx_new_local(nm)  // (in scope in its own body: it can call itself)
            let f = lx_parse_function(nm, false)
            return lx_node(N_LOCALFN, slot, [ f ])
        let names = [ lx_name_tok() ]
        while lx_accept(","): names.push(lx_name_tok())
        if lx_tk_is("<"): lx_perror("attributes (<const>, <close>) aren\'t in this Lua")
        let vals = if lx_accept("="): lx_parse_exprs() else: []
        let slots = map(names) nm: lx_new_local(nm)  // (after the values: `local x = x` reads the outer x)
        let l = lx_node(N_LOCALS, names.length, vals)
        l.s = slots
        return l
    // an assignment or a call
    let e = lx_parse_suffixed()
    if lx_tk_is("=") or lx_tk_is(","):
        let targets = [ e ]
        while lx_accept(","): targets.push(lx_parse_suffixed())
        lx_expect("=")
        let vals = lx_parse_exprs()
        for(targets) t:
            if t.k != N_LOCAL and t.k != N_UPV and t.k != N_GLOBAL and t.k != N_INDEX: lx_perror("can\'t assign to that")
        return lx_node(N_ASSIGN, targets.length, append(targets, vals))
    if e.k != N_CALL and e.k != N_METHOD:
        lx_perror("a statement expected near \'{tk_text[ltp]}\' (line {line})")
        return nil
    return lx_node(N_CALLST, 0, [ e ])

def lx_parse_function(name:string, method:bool) -> LNode:
    let proto = LProto { name, pfile, 0, 0, [], [], lx_node(N_BLOCK, 0, []) }
    let sc = LScope { if pscopes.length: top(pscopes) else: nil, proto, [], [], [] }
    pscopes.push(sc)
    if method: lx_new_local("self")
    lx_expect("(")
    if not lx_tk_is(")"):
        while perr == "":
            if lx_tk_is("..."):
                lx_perror("varargs (...) aren\'t in this Lua")
                break
            lx_new_local(lx_name_tok())
            if not lx_accept(","): break
    lx_expect(")")
    proto.params = proto.slots
    proto.body = lx_parse_block()
    lx_expect("end")
    pscopes.pop()
    l_protos.push(proto)
    return lx_node(N_FUNC, l_protos.length - 1, [])

def lx_parse_exprs() -> [LNode]:
    let out = [ lx_parse_expr(0) ]
    while lx_accept(","): out.push(lx_parse_expr(0))
    return out

def lx_parse_primary() -> LNode:
    if tk_kind[ltp] == TK_NAME:
        ltp++
        return lx_name_node(tk_text[ltp - 1])
    if lx_accept("("):
        let e = lx_parse_expr(0)
        lx_expect(")")
        return lx_node(N_PAREN, 0, [ e ])
    lx_perror("an expression expected near \'{tk_text[ltp]}\'")
    ltp++
    return lx_node(N_NIL, 0, [])

def lx_parse_args() -> [LNode]:
    if tk_kind[ltp] == TK_STR:
        ltp++
        return [ lx_node(N_CONST, lv_str(tk_text[ltp - 1]), []) ]
    if lx_tk_is("{{"): return [ lx_parse_table() ]
    lx_expect("(")
    if lx_accept(")"): return []
    let args = lx_parse_exprs()
    lx_expect(")")
    return args

def lx_parse_suffixed() -> LNode:
    var e = lx_parse_primary()
    while perr == "":
        if lx_accept("."):
            e = lx_node(N_INDEX, 0, [ e, lx_node(N_CONST, lv_str(lx_name_tok()), []) ])
        elif lx_accept("["):
            let key = lx_parse_expr(0)
            lx_expect("]")
            e = lx_node(N_INDEX, 0, [ e, key ])
        elif lx_accept(":"):
            let m = lx_name_tok()
            e = lx_node(N_METHOD, lv_str(m), append([ e ], lx_parse_args()))
        elif lx_tk_is("(") or lx_tk_is("{{") or tk_kind[ltp] == TK_STR:
            e = lx_node(N_CALL, 0, append([ e ], lx_parse_args()))
        else:
            break
    return e

def lx_parse_table() -> LNode:
    lx_expect("{{")
    let items = []::LNode
    while not lx_tk_is("}}") and perr == "":
        if lx_accept("["):
            let key = lx_parse_expr(0)
            lx_expect("]")
            lx_expect("=")
            items.push(lx_node(N_TPAIR, 0, [ key, lx_parse_expr(0) ]))
        elif tk_kind[ltp] == TK_NAME and tk_kind[ltp + 1] == TK_OP and tk_text[ltp + 1] == "=":
            let key = tk_text[ltp]
            ltp += 2
            items.push(lx_node(N_TPAIR, 0, [ lx_node(N_CONST, lv_str(key), []), lx_parse_expr(0) ]))
        else:
            items.push(lx_parse_expr(0))
        if not lx_accept(",") and not lx_accept(";"): break
    lx_expect("}}")
    return lx_node(N_TABLE, 0, items)

def lx_parse_simple() -> LNode:
    let k = tk_kind[ltp]
    if k == TK_INT:
        ltp++
        return lx_node(N_CONST, lv_int(tk_int[ltp - 1]), [])
    if k == TK_STR:
        ltp++
        return lx_node(N_CONST, lv_str(tk_text[ltp - 1]), [])
    if lx_accept("nil"): return lx_node(N_NIL, 0, [])
    if lx_accept("true"): return lx_node(N_TRUE, 0, [])
    if lx_accept("false"): return lx_node(N_FALSE, 0, [])
    if lx_tk_is("..."):
        lx_perror("varargs (...) aren\'t in this Lua")
        ltp++
        return lx_node(N_NIL, 0, [])
    if lx_tk_is("{{"): return lx_parse_table()
    if lx_accept("function"): return lx_parse_function("(anonymous)", false)
    return lx_parse_suffixed()

// Binary operators: their codes (100 or, 101 and, 200 refused) and left and right priorities, as Lua's ("..": right
// associative).
let BIN_TOKS = [ "or", "and", "<", ">", "<=", ">=", "~=", "==", "|", "~", "&", "<<", ">>", "..", "+", "-", "*", "//", "%", "/", "^" ]
let BIN_OPS = [ 100, 101, OP_LT, OP_GT, OP_LE, OP_GE, OP_NE, OP_EQ, OP_BOR, OP_BXOR, OP_BAND, OP_SHL, OP_SHR, OP_CONCAT,
    OP_ADD, OP_SUB, OP_MUL, OP_IDIV, OP_MOD, 200, 200 ]
let BIN_LEFT = [ 1, 2, 3, 3, 3, 3, 3, 3, 4, 5, 6, 7, 7, 9, 10, 10, 11, 11, 11, 11, 11 ]
let BIN_RIGHT = [ 1, 2, 3, 3, 3, 3, 3, 3, 4, 5, 6, 7, 7, 8, 10, 10, 11, 11, 11, 11, 11 ]

def lx_binop() -> int, int, int:
    if tk_kind[ltp] != TK_OP: return -1, 0, 0
    let t = tk_text[ltp]
    let j = find(BIN_TOKS) x: x == t
    if j < 0: return -1, 0, 0
    return BIN_OPS[j], BIN_LEFT[j], BIN_RIGHT[j]

let L_UNARY = 12

def lx_parse_expr(limit:int) -> LNode:
    var e = lx_node(N_NIL, 0, [])
    if lx_tk_is("not") or lx_tk_is("-") or lx_tk_is("#") or lx_tk_is("~"):
        let t = tk_text[ltp]
        ltp++
        let x = lx_parse_expr(L_UNARY)
        if t == "-" and x.k == N_CONST and lv_is_int(x.n): e = lx_node(N_CONST, lv_int(-lv_n(x.n)), [])
        else: e = lx_node(if t == "not": N_NOT elif t == "-": N_NEG elif t == "#": N_LEN else: N_BNOT, 0, [ x ])
    else:
        e = lx_parse_simple()
    while perr == "":
        let op, left, right = lx_binop()
        if op < 0 or left <= limit: break
        if op == 200:
            lx_perror("\'{tk_text[ltp]}\' makes floats: use // for integer division (lockstep)")
            break
        ltp++
        let r = lx_parse_expr(right)
        e = if op == 100: lx_node(N_OR, 0, [ e, r ]) elif op == 101: lx_node(N_AND, 0, [ e, r ]) else: lx_node(N_BIN, op, [ e, r ])
    return e

// A file's source as a function of no arguments (its chunk), or "" and why it can't be.
def lua_compile(file:string, src:string) -> int, string:
    lx_lex(src)
    if lex_err != "": return -1, "{file}:{lex_err}"
    ltp = 0
    perr = ""
    pfile = file
    let proto = LProto { "(main chunk)", file, 0, 0, [], [], lx_node(N_BLOCK, 0, []) }
    pscopes = [ LScope { nil, proto, [], [], [] } ]
    proto.body = lx_parse_block()
    if perr == "" and tk_kind[ltp] != TK_EOF: lx_perror("\'{tk_text[ltp]}\' unexpected")
    pscopes = []
    if perr != "": return -1, perr
    l_protos.push(proto)
    return l_protos.length - 1, ""

// ------------------------------------------------------------------ tables
var l_frozen_tab = 0  // tables, boxes and strings below these were made at load: read-only, kept
var l_frozen_box = 0
var l_frozen_clo = 0
var l_frozen_str = 0
var l_loaded = false  // past the load: the frozen marks hold

def lx_tab_find(t:int, key:int) -> int:
    let m = lt_map[t]
    if m: return m.get(key, -1)
    let keys = lt_keys[t]
    for(keys) k2, at:
        if k2 == key: return at
    return -1

def lua_get(tv:int, key:int) -> int:
    let t = tv >> 3
    if lv_is_int(key):
        let arr = lt_arr[t]
        let n = key >> 3
        if n >= 1 and n <= arr.length: return arr[n - 1]
    let at = lx_tab_find(t, key)
    return if at >= 0: lt_vals[t][at] else: LV_NIL

def lua_set_raw(tv:int, key:int, v:int):
    let t = tv >> 3
    if lv_is_int(key):
        let arr = lt_arr[t]
        let n = key >> 3
        if n >= 1 and n <= arr.length:
            arr[n - 1] = v
            if n == arr.length and v == LV_NIL:
                while arr.length and top(arr) == LV_NIL: arr.pop()
            return
        if n == arr.length + 1 and v != LV_NIL and lx_tab_find(t, key) < 0:
            arr.push(v)
            if lt_keys[t].length:  // (keys after it, set before, move into the array)
                while true:
                    let next = lv_int(arr.length + 1)
                    let at = lx_tab_find(t, next)
                    if at < 0 or lt_vals[t][at] == LV_NIL: break
                    arr.push(lt_vals[t][at])
                    lt_vals[t][at] = LV_NIL
            return
    let at = lx_tab_find(t, key)
    if at >= 0:
        lt_vals[t][at] = v
    elif v != LV_NIL:
        lt_keys[t].push(key)
        lt_vals[t].push(v)
        let m = lt_map[t]
        if m: m.set(key, lt_keys[t].length - 1)
        elif lt_keys[t].length > 8:
            let d = dictionary<int, int>(67)
            for(lt_keys[t]) k2, i: d.set(k2, i)
            lt_map[t] = d

def lua_set(tv:int, key:int, v:int):
    if l_loaded and (tv >> 3) < l_frozen_tab:
        lua_fail("a table made at load is read-only (state that lasts goes in hook columns)")
        return
    if key == LV_NIL:
        lua_fail("a table index is nil")
        return
    lua_set_raw(tv, key, v)

def lua_len(tv:int) -> int: return lt_arr[tv >> 3].length

// ------------------------------------------------------------------ running
var lst = []::int     // the locals of the functions running, a frame each
var lfb = 0           // the running function's frame
var lclo = -1         // the running closure
var lboxed = []::bool // its prototype's boxed slots
var rets = []::int    // what the last call returned
let RUN_OK = 0
let RUN_BREAK = 1
let RUN_RETURN = 2
let RUN_ERR = 3

def lx_step_count() -> bool:
    lsteps++
    if lsteps > lbudget:
        lua_fail("over its step budget ({lbudget} steps)")
        return false
    return true

def lx_get_local(slot:int) -> int:
    let v = lst[lfb + slot]
    return if lboxed[slot]: lbox[v] else: v

def lx_set_local(slot:int, v:int):
    if lboxed[slot]: lbox[lst[lfb + slot]] = v
    else: lst[lfb + slot] = v

// A local coming into scope: a fresh box if a closure captures it.
def lx_init_local(slot:int, v:int):
    if lboxed[slot]:
        lbox.push(v)
        lst[lfb + slot] = lbox.length - 1
    else:
        lst[lfb + slot] = v

def lx_set_box(b:int, v:int):
    if l_loaded and b < l_frozen_box: lua_fail("a file-level local is read-only after load (state that lasts goes in hook columns)")
    else: lbox[b] = v

def lua_tostring(v:int) -> string:
    let t = v & 7
    return if t == LT_INT: "{v >> 3}"
    elif t == LT_STR: lv_text(v)
    elif v == LV_NIL: "nil"
    elif v == LV_TRUE: "true"
    elif v == LV_FALSE: "false"
    elif t == LT_TAB: "table: {v >> 3}"
    elif t == LT_BUILTIN: "builtin: {lb_names[v >> 3]}"
    else: "function: {l_protos[lc_proto[v >> 3]].name}"

def lx_floor_div(a:int, b:int) -> int:
    let q = a / b
    return if (a % b != 0) and ((a < 0) != (b < 0)): q - 1 else: q

def lx_floor_mod(a:int, b:int) -> int:
    let r = a % b
    return if r != 0 and ((r < 0) != (b < 0)): r + b else: r

def lx_arith(op:int, a:int, b:int) -> int:
    if ((a | b) & 7) == 0:  // (both integers: the usual case first)
        if op == OP_ADD: return a + b
        if op == OP_SUB: return a - b
        if op == OP_LT: return lv_bool(a < b)
        if op == OP_EQ: return lv_bool(a == b)
        if op == OP_NE: return lv_bool(a != b)
        if op == OP_LE: return lv_bool(a <= b)
        if op == OP_GT: return lv_bool(a > b)
        if op == OP_GE: return lv_bool(a >= b)
    return lx_arith_slow(op, a, b)

def lx_arith_slow(op:int, a:int, b:int) -> int:
    if op == OP_EQ: return lv_bool(a == b)
    if op == OP_NE: return lv_bool(a != b)
    if op == OP_CONCAT:
        let ta = a & 7
        let tb = b & 7
        if (ta != LT_INT and ta != LT_STR) or (tb != LT_INT and tb != LT_STR):
            lua_fail("can\'t join a {lv_type_name(if ta != LT_INT and ta != LT_STR: a else: b)} into a string")
            return LV_NIL
        return lv_str(lua_tostring(a) + lua_tostring(b))
    if op >= OP_LT and op <= OP_GE and (a & 7) == LT_STR and (b & 7) == LT_STR:
        let x = lv_text(a)
        let y = lv_text(b)
        return lv_bool(if op == OP_LT: x < y elif op == OP_LE: x <= y elif op == OP_GT: x > y else: x >= y)
    if not lv_is_int(a) or not lv_is_int(b):
        lua_fail("can\'t do arithmetic or compare a {lv_type_name(if lv_is_int(a): b else: a)}")
        return LV_NIL
    let x = a >> 3
    let y = b >> 3
    if op == OP_ADD: return a + b
    if op == OP_SUB: return a - b
    if op == OP_MUL: return lv_int(x * y)
    if op == OP_IDIV or op == OP_MOD:
        if y == 0:
            lua_fail("integer division by zero")
            return LV_NIL
        return lv_int(if op == OP_IDIV: lx_floor_div(x, y) else: lx_floor_mod(x, y))
    if op == OP_LT: return lv_bool(x < y)
    if op == OP_LE: return lv_bool(x <= y)
    if op == OP_GT: return lv_bool(x > y)
    if op == OP_GE: return lv_bool(x >= y)
    if op == OP_BAND: return lv_int(x & y)
    if op == OP_BOR: return lv_int(x | y)
    if op == OP_BXOR: return lv_int(x ^ y)
    if op == OP_SHL: return lv_int(if y >= 64 or y <= -64: 0 elif y >= 0: x << y else: x >> -y)
    if op == OP_SHR: return lv_int(if y >= 64 or y <= -64: 0 elif y >= 0: x >> y else: x << -y)
    return LV_NIL

def lx_eval(e:LNode) -> int:
    switch e.k:
        case N_CONST: return e.n
        case N_LOCAL: return lx_get_local(e.n)
        case N_UPV: return lbox[lc_ups[lclo][e.n]]
        case N_NIL: return LV_NIL
        case N_TRUE: return LV_TRUE
        case N_FALSE: return LV_FALSE
        case N_GLOBAL:
            if e.c != -1: return e.c
            let v = lua_get(l_env, e.n)
            if l_loaded: e.c = v
            return v
        case N_INDEX:
            let o = lx_eval(e.a[0])
            let key = lx_eval(e.a[1])
            if (o & 7) != LT_TAB:
                if not lfail: lua_fail("can\'t index a {lv_type_name(o)}{lx_index_hint(e)}")
                return LV_NIL
            return lua_get(o, key)
        case N_CALL, N_METHOD:
            if not lx_eval_call(e): return LV_NIL
            return if rets.length: rets[0] else: LV_NIL
        case N_BIN: return lx_arith(e.n, lx_eval(e.a[0]), lx_eval(e.a[1]))
        case N_AND:
            let x = lx_eval(e.a[0])
            return if lv_truthy(x): lx_eval(e.a[1]) else: x
        case N_OR:
            let x = lx_eval(e.a[0])
            return if lv_truthy(x): x else: lx_eval(e.a[1])
        case N_NOT: return lv_bool(not lv_truthy(lx_eval(e.a[0])))
        case N_NEG:
            let x = lx_eval(e.a[0])
            if not lv_is_int(x):
                lua_fail("can\'t negate a {lv_type_name(x)}")
                return LV_NIL
            return -x
        case N_BNOT:
            let x = lx_eval(e.a[0])
            if not lv_is_int(x):
                lua_fail("can\'t do bitwise not on a {lv_type_name(x)}")
                return LV_NIL
            return lv_int(~(x >> 3))
        case N_LEN:
            let x = lx_eval(e.a[0])
            let t = x & 7
            if t == LT_STR: return lv_int(lv_text(x).length)
            if t == LT_TAB: return lv_int(lua_len(x))
            lua_fail("can\'t take the length of a {lv_type_name(x)}")
            return LV_NIL
        case N_TABLE:
            let tv = lv_table()
            var n = 1
            for(e.a) item, j:
                if item.k == N_TPAIR:
                    let key = lx_eval(item.a[0])
                    let v = lx_eval(item.a[1])
                    if key == LV_NIL: lua_fail("a table index is nil")
                    else: lua_set_raw(tv, key, v)
                elif j == e.a.length - 1 and (item.k == N_CALL or item.k == N_METHOD):
                    if lx_eval_call(item):
                        for(copy(rets)) v:
                            lua_set_raw(tv, lv_int(n), v)
                            n++
                else:
                    lua_set_raw(tv, lv_int(n), lx_eval(item))
                    n++
            return tv
        case N_FUNC:
            let proto = l_protos[e.n]
            let ups = map(proto.ups) u: if u & 1: lc_ups[lclo][u >> 1] else: lst[lfb + (u >> 1)]
            lc_proto.push(e.n)
            lc_ups.push(ups)
            return ((lc_proto.length - 1) << 3) | LT_FUN
        case N_PAREN: return lx_eval(e.a[0])
        default: return LV_NIL
    return LV_NIL

def lx_index_hint(e:LNode) -> string:
    let key = e.a[1]
    let base = e.a[0]
    let what = if base.k == N_GLOBAL: " (global \'{lv_text(base.n)}\')" else: ""
    return if key.k == N_CONST and (key.n & 7) == LT_STR: " to read \'{lv_text(key.n)}\'{what}" else: what

// The values of a list of expressions, the last one's all if it's a call.
def lx_eval_list(es:[LNode], first:int) -> [int]:
    let out = []::int
    var j = first
    while j < es.length:
        let x = es[j]
        if j == es.length - 1 and (x.k == N_CALL or x.k == N_METHOD):
            if lx_eval_call(x): for(rets) v: out.push(v)
        else:
            out.push(lx_eval(x))
        j++
    return out

def lx_eval_call(e:LNode) -> bool:
    var f = LV_NIL
    var args = []::int
    if e.k == N_METHOD:
        let o = lx_eval(e.a[0])
        if (o & 7) != LT_TAB:
            lua_fail("can\'t call method \'{lv_text(e.n)}\' on a {lv_type_name(o)}")
            return false
        f = lua_get(o, e.n)
        args.push(o)
        for(lx_eval_list(e.a, 1)) v: args.push(v)
    else:
        f = lx_eval(e.a[0])
        args = lx_eval_list(e.a, 1)
    if lfail: return false
    let t = f & 7
    if t != LT_FUN and t != LT_BUILTIN:
        let fnode = e.a[0]
        var what = ""
        if e.k == N_METHOD: what = " (method \'{lv_text(e.n)}\')"
        elif fnode.k == N_GLOBAL: what = " (global \'{lv_text(fnode.n)}\')"
        elif fnode.k == N_INDEX and fnode.a[1].k == N_CONST and (fnode.a[1].n & 7) == LT_STR: what = " (field \'{lv_text(fnode.a[1].n)}\')"
        lua_fail("can\'t call a {lv_type_name(f)}{what}")
        return false
    let line = lline
    let ok = lua_call(f, args)
    lline = line
    return ok

// Calls a function value with these arguments: its results in rets. False on an error (lerr says it).
def lua_call(f:int, args:[int]) -> bool:
    if lfail: return false
    if not lx_step_count(): return false
    if (f & 7) == LT_BUILTIN:
        truncate(rets, 0)
        lua_builtin(f >> 3, args)
        return not lfail
    if (f & 7) != LT_FUN:
        lua_fail("can\'t call a {lv_type_name(f)}")
        return false
    if ldepth >= L_MAX_DEPTH:
        lua_fail("calls nested too deep (over {L_MAX_DEPTH})")
        return false
    let c = f >> 3
    let proto = l_protos[lc_proto[c]]
    let fb0 = lfb
    let clo0 = lclo
    let boxed0 = lboxed
    let file0 = lerr_file
    lfb = lst.length
    lclo = c
    lboxed = proto.boxed
    lerr_file = proto.file
    for(proto.slots): lst.push(LV_NIL)
    for(proto.params) j: lx_init_local(j, if j < args.length: args[j] else: LV_NIL)
    ldepth++
    let r = lx_exec_block(proto.body)
    ldepth--
    if r != RUN_RETURN: truncate(rets, 0)
    truncate(lst, lfb)
    lfb = fb0
    lclo = clo0
    lboxed = boxed0
    if r != RUN_ERR: lerr_file = file0
    return r != RUN_ERR

def lx_exec_block(b:LNode) -> int:
    for(b.a) s:
        let r = lx_exec(s)
        if r != RUN_OK: return r
    return RUN_OK

def lx_assign(t:LNode, v:int):
    switch t.k:
        case N_LOCAL: lx_set_local(t.n, v)
        case N_UPV: lx_set_box(lc_ups[lclo][t.n], v)
        case N_GLOBAL: lua_set(l_env, t.n, v)
        case N_INDEX:
            let o = lx_eval(t.a[0])
            let key = lx_eval(t.a[1])
            if (o & 7) != LT_TAB:
                if not lfail: lua_fail("can\'t index a {lv_type_name(o)}{lx_index_hint(t)}")
            else:
                lua_set(o, key, v)
        default: lua_fail("can\'t assign to that")

def lx_exec(s:LNode) -> int:
    lline = s.line
    if not lx_step_count(): return RUN_ERR
    switch s.k:
        case N_LOCALS:
            let vals = lx_eval_list(s.a, 0)
            if lfail: return RUN_ERR
            for(s.s) slot, j: lx_init_local(slot, if j < vals.length: vals[j] else: LV_NIL)
        case N_LOCALFN:
            lx_init_local(s.n, LV_NIL)
            lx_set_local(s.n, lx_eval(s.a[0]))
        case N_ASSIGN:
            if s.n == 1:
                let v = lx_eval(s.a[1])
                if lfail: return RUN_ERR
                lx_assign(s.a[0], v)
            else:
                let vals = lx_eval_list(s.a, s.n)
                if lfail: return RUN_ERR
                for(s.n) j: lx_assign(s.a[j], if j < vals.length: vals[j] else: LV_NIL)
        case N_CALLST:
            lx_eval_call(s.a[0])
        case N_IF:
            var j = 0
            let conds = s.a.length - s.n
            while j < conds:
                let c = lx_eval(s.a[j])
                if lfail: return RUN_ERR
                if lv_truthy(c): return lx_exec_block(s.a[j + 1])
                j += 2
            if s.n == 1: return lx_exec_block(s.a[s.a.length - 1])
        case N_WHILE:
            while true:
                let c = lx_eval(s.a[0])
                if lfail: return RUN_ERR
                if not lv_truthy(c): break
                if not lx_step_count(): return RUN_ERR
                let r = lx_exec_block(s.a[1])
                if r == RUN_BREAK: break
                if r != RUN_OK: return r
        case N_REPEAT:
            while true:
                if not lx_step_count(): return RUN_ERR
                let r = lx_exec_block(s.a[0])
                if r == RUN_BREAK: break
                if r != RUN_OK: return r
                let c = lx_eval(s.a[1])
                if lfail: return RUN_ERR
                if lv_truthy(c): break
        case N_NUMFOR:
            let a0 = lx_eval(s.a[0])
            let a1 = lx_eval(s.a[1])
            let a2 = lx_eval(s.a[2])
            if lfail: return RUN_ERR
            if not lv_is_int(a0) or not lv_is_int(a1) or not lv_is_int(a2):
                lua_fail("a \'for\' needs integers")
                return RUN_ERR
            let step = a2 >> 3
            if step == 0:
                lua_fail("a \'for\' step is zero")
                return RUN_ERR
            var i = a0 >> 3
            let limit = a1 >> 3
            while (step > 0 and i <= limit) or (step < 0 and i >= limit):
                if not lx_step_count(): return RUN_ERR
                lx_init_local(s.n, lv_int(i))
                let r = lx_exec_block(s.a[3])
                if r == RUN_BREAK: break
                if r != RUN_OK: return r
                i += step
        case N_GENFOR:
            return lx_exec_genfor(s)
        case N_RETURN:
            let vals = lx_eval_list(s.a, 0)
            if lfail: return RUN_ERR
            rets = vals
            return RUN_RETURN
        case N_BREAK:
            return RUN_BREAK
        case N_BLOCK:
            return lx_exec_block(s)
        default:
            lua_fail("a statement this Lua can\'t run")
    return if lfail: RUN_ERR else: RUN_OK

// for k, v in f, s, ctl: ipairs and pairs (in insertion order) are walked directly; any other f is called as Lua does.
def lx_exec_genfor(s:LNode) -> int:
    let block = s.a[s.a.length - 1]
    let vals = lx_eval_list(s.a.slice(0, s.a.length - 1), 0)
    if lfail: return RUN_ERR
    let f = if vals.length > 0: vals[0] else: LV_NIL
    let st = if vals.length > 1: vals[1] else: LV_NIL
    var ctl = if vals.length > 2: vals[2] else: LV_NIL
    let v1 = if s.s.length > 1: s.s[1] else: -1
    if f == ((B_IPAIRS_NEXT << 3) | LT_BUILTIN) or f == ((B_PAIRS_NEXT << 3) | LT_BUILTIN):
        if (st & 7) != LT_TAB:
            lua_fail("ipairs or pairs over a {lv_type_name(st)}")
            return RUN_ERR
        let t = st >> 3
        var j = 0
        let pairs = f == ((B_PAIRS_NEXT << 3) | LT_BUILTIN)
        while true:
            var key = LV_NIL
            var v = LV_NIL
            if j < lt_arr[t].length:
                key = lv_int(j + 1)
                v = lt_arr[t][j]
                if v == LV_NIL: break  // (ipairs stops at a hole; pairs skips it below)
            elif pairs and j - lt_arr[t].length < lt_keys[t].length:
                let at = j - lt_arr[t].length
                key = lt_keys[t][at]
                v = lt_vals[t][at]
            else:
                break
            j++
            if v != LV_NIL:
                lx_init_local(s.s[0], key)
                if v1 >= 0: lx_init_local(v1, v)
                for(s.s.length - 2) n: lx_init_local(s.s[n + 2], LV_NIL)
                let r = lx_exec_block(block)
                if r == RUN_BREAK: break
                if r != RUN_OK: return r
                if not lx_step_count(): return RUN_ERR
        return RUN_OK
    while true:
        if not lua_call(f, [ st, ctl ]): return RUN_ERR
        let got = copy(rets)
        let first = if got.length: got[0] else: LV_NIL
        if first == LV_NIL: break
        ctl = first
        for(s.s) slot, n: lx_init_local(slot, if n < got.length: got[n] else: LV_NIL)
        let r = lx_exec_block(block)
        if r == RUN_BREAK: break
        if r != RUN_OK: return r
    return RUN_OK

// ------------------------------------------------------------------ the base library
var lprint = []::string  // what print printed (the log reads it too)
var lua_quiet = false

def lx_arg_of(a:[int], j:int) -> int: return if j < a.length: a[j] else: LV_NIL

def lx_want_int(a:[int], j:int, fname:string) -> int:
    let v = lx_arg_of(a, j)
    if not lv_is_int(v):
        lua_fail("{fname}: argument {j + 1} should be an integer, not a {lv_type_name(v)}")
        return 0
    return v >> 3

def lx_want_str(a:[int], j:int, fname:string) -> string:
    let v = lx_arg_of(a, j)
    if (v & 7) == LT_INT: return "{v >> 3}"
    if (v & 7) != LT_STR:
        lua_fail("{fname}: argument {j + 1} should be a string, not a {lv_type_name(v)}")
        return ""
    return lv_text(v)

def lx_want_tab(a:[int], j:int, fname:string) -> int:
    let v = lx_arg_of(a, j)
    if (v & 7) != LT_TAB:
        lua_fail("{fname}: argument {j + 1} should be a table, not a {lv_type_name(v)}")
        return LV_NIL
    return v

def lx_ret(v:int): rets.push(v)

// string.sub's and string.find's positions, Lua style (1-based, negative from the end), as a 0-based start and length.
def lx_str_range(len:int, i:int, j:int) -> int, int:
    var s = if i < 0: max(len + i + 1, 1) elif i == 0: 1 else: i
    var e = if j < 0: len + j + 1 elif j > len: len else: j
    if s > e: return 0, 0
    return s - 1, e - s + 1

def lua_builtin(id:int, a:[int]):
    if id >= B_COUNT:
        lua_api(id - B_COUNT, a)
        return
    switch id:
        case B_PRINT:
            let line = concat_string(map(a) v: lua_tostring(v), "\t")
            lprint.push(line)
            if not lua_quiet: print "lua: {line}"
        case B_TYPE: lx_ret(lv_str(lv_type_name(lx_arg_of(a, 0))))
        case B_TOSTRING: lx_ret(lv_str(lua_tostring(lx_arg_of(a, 0))))
        case B_TONUMBER:
            let v = lx_arg_of(a, 0)
            if lv_is_int(v): lx_ret(v)
            elif (v & 7) == LT_STR:
                let n, ok = string_to_int(lv_text(v))
                lx_ret(if ok: lv_int(n) else: LV_NIL)
            else: lx_ret(LV_NIL)
        case B_ERROR: lua_fail(lua_tostring(lx_arg_of(a, 0)))
        case B_ASSERT:
            if not lv_truthy(lx_arg_of(a, 0)): lua_fail(if a.length > 1: lua_tostring(a[1]) else: "assertion failed!")
            else: for(a) v: lx_ret(v)
        case B_IPAIRS:
            lx_ret(((B_IPAIRS_NEXT << 3) | LT_BUILTIN))
            lx_ret(lx_want_tab(a, 0, "ipairs"))
            lx_ret(lv_int(0))
        case B_PAIRS:
            lx_ret(((B_PAIRS_NEXT << 3) | LT_BUILTIN))
            lx_ret(lx_want_tab(a, 0, "pairs"))
            lx_ret(LV_NIL)
        case B_IPAIRS_NEXT:
            let t = lx_want_tab(a, 0, "ipairs")
            let n = lx_want_int(a, 1, "ipairs") + 1
            if not lfail:
                let v = lua_get(t, lv_int(n))
                if v != LV_NIL:
                    lx_ret(lv_int(n))
                    lx_ret(v)
                else: lx_ret(LV_NIL)
        case B_PAIRS_NEXT, B_NEXT:
            let tv = lx_want_tab(a, 0, "next")
            if not lfail:
                let t = tv >> 3
                let key = lx_arg_of(a, 1)
                // the position after key: the array part, then the rest in insertion order
                var j = 0
                if key != LV_NIL:
                    if lv_is_int(key) and (key >> 3) >= 1 and (key >> 3) <= lt_arr[t].length: j = key >> 3
                    else:
                        let at = lx_tab_find(t, key)
                        if at < 0: lua_fail("next: a key that isn\'t in the table")
                        j = lt_arr[t].length + at + 1
                var done = false
                while not done and not lfail:
                    if j < lt_arr[t].length:
                        if lt_arr[t][j] != LV_NIL:
                            lx_ret(lv_int(j + 1))
                            lx_ret(lt_arr[t][j])
                            done = true
                    elif j - lt_arr[t].length < lt_keys[t].length:
                        let at = j - lt_arr[t].length
                        if lt_vals[t][at] != LV_NIL:
                            lx_ret(lt_keys[t][at])
                            lx_ret(lt_vals[t][at])
                            done = true
                    else:
                        lx_ret(LV_NIL)
                        done = true
                    j++
        case B_SELECT:
            let first = lx_arg_of(a, 0)
            if first == lv_str("#"): lx_ret(lv_int(a.length - 1))
            else:
                let n = lx_want_int(a, 0, "select")
                if n < 1: lua_fail("select: index out of range")
                var j = n
                while j < a.length:
                    lx_ret(a[j])
                    j++
        case B_MATH_MIN, B_MATH_MAX:
            if not a.length: lua_fail("math.min/max: no arguments")
            else:
                var best = lx_want_int(a, 0, L_BASE_NAMES[id])
                for(a.length - 1) j:
                    let v = lx_want_int(a, j + 1, L_BASE_NAMES[id])
                    if (id == B_MATH_MIN and v < best) or (id == B_MATH_MAX and v > best): best = v
                lx_ret(lv_int(best))
        case B_MATH_ABS: lx_ret(lv_int(abs(lx_want_int(a, 0, "math.abs"))))
        case B_STR_SUB:
            let s = lx_want_str(a, 0, "string.sub")
            let i = if a.length > 1: lx_want_int(a, 1, "string.sub") else: 1
            let j = if a.length > 2: lx_want_int(a, 2, "string.sub") else: -1
            let at, n = lx_str_range(s.length, i, j)
            lx_ret(lv_str(substring(s, at, n)))
        case B_STR_LEN: lx_ret(lv_int(lx_want_str(a, 0, "string.len").length))
        case B_STR_UPPER: lx_ret(lv_str(uppercase(lx_want_str(a, 0, "string.upper"))))
        case B_STR_LOWER: lx_ret(lv_str(lowercase(lx_want_str(a, 0, "string.lower"))))
        case B_STR_BYTE:
            let s = lx_want_str(a, 0, "string.byte")
            let i = if a.length > 1: lx_want_int(a, 1, "string.byte") else: 1
            let at, n = lx_str_range(s.length, i, i)
            lx_ret(if n > 0: lv_int(s[at]) else: LV_NIL)
        case B_STR_FIND:  // (plain text only: no patterns)
            let s = lx_want_str(a, 0, "string.find")
            let pat = lx_want_str(a, 1, "string.find")
            let at = find_string(s, pat)
            if at >= 0:
                lx_ret(lv_int(at + 1))
                lx_ret(lv_int(at + pat.length))
            else: lx_ret(LV_NIL)
        case B_STR_REP:
            let s = lx_want_str(a, 0, "string.rep")
            let n = lx_want_int(a, 1, "string.rep")
            if s.length * n > 100000: lua_fail("string.rep: over 100000 characters")
            else: lx_ret(lv_str(repeat_string(s, max(n, 0))))
        case B_STR_FORMAT:
            let fmt = lx_want_str(a, 0, "string.format")
            var out = ""
            var j = 0
            var arg = 1
            while j < fmt.length and not lfail:
                let c = fmt[j]
                if c == '%' and j + 1 < fmt.length:
                    let d = fmt[j + 1]
                    if d == '%': out += "%"
                    elif d == 'd' or d == 'i':
                        out += "{lx_want_int(a, arg, "string.format")}"
                        arg++
                    elif d == 's':
                        out += lua_tostring(lx_arg_of(a, arg))
                        arg++
                    else: lua_fail("string.format: only %d, %s and %% here")
                    j += 2
                else:
                    out += unicode_to_string([ c ])
                    j++
            lx_ret(lv_str(out))
        case B_TAB_INSERT:
            let t = lx_want_tab(a, 0, "table.insert")
            if not lfail:
                let n = lua_len(t)
                if a.length == 2: lua_set(t, lv_int(n + 1), a[1])
                elif a.length == 3:
                    let pos = lx_want_int(a, 1, "table.insert")
                    if pos < 1 or pos > n + 1: lua_fail("table.insert: position out of bounds")
                    else:
                        var j = n
                        while j >= pos and not lfail:
                            lua_set(t, lv_int(j + 1), lua_get(t, lv_int(j)))
                            j--
                        lua_set(t, lv_int(pos), a[2])
                else: lua_fail("table.insert: wrong number of arguments")
        case B_TAB_REMOVE:
            let t = lx_want_tab(a, 0, "table.remove")
            if not lfail:
                let n = lua_len(t)
                let pos = if a.length > 1: lx_want_int(a, 1, "table.remove") else: n
                if n == 0: lx_ret(LV_NIL)
                elif pos < 1 or pos > n: lua_fail("table.remove: position out of bounds")
                else:
                    lx_ret(lua_get(t, lv_int(pos)))
                    var j = pos
                    while j < n and not lfail:
                        lua_set(t, lv_int(j), lua_get(t, lv_int(j + 1)))
                        j++
                    lua_set(t, lv_int(n), LV_NIL)
        case B_TAB_CONCAT:
            let t = lx_want_tab(a, 0, "table.concat")
            let sep = if a.length > 1: lx_want_str(a, 1, "table.concat") else: ""
            if not lfail:
                let parts = map(lt_arr[t >> 3]) v: lua_tostring(v)
                lx_ret(lv_str(concat_string(parts, sep)))
        case B_TAB_SORT:  // (a stable merge sort: the same order everywhere)
            let t = lx_want_tab(a, 0, "table.sort")
            let cmp = lx_arg_of(a, 1)
            if not lfail:
                if l_loaded and (t >> 3) < l_frozen_tab: lua_fail("a table made at load is read-only (state that lasts goes in hook columns)")
                else:
                    let arr = lt_arr[t >> 3]
                    let sorted = lua_sort(copy(arr), cmp)
                    for(sorted) v, j: arr[j] = v
        default: lua_fail("an unknown builtin")

def lua_less(x:int, y:int, cmp:int) -> bool:
    if cmp == LV_NIL: return lv_truthy(lx_arith(OP_LT, x, y))
    if not lua_call(cmp, [ x, y ]): return false
    return rets.length > 0 and lv_truthy(rets[0])

def lua_sort(v:[int], cmp:int) -> [int]:
    if v.length <= 1 or lfail: return v
    let half = v.length / 2
    let l = lua_sort(v.slice(0, half), cmp)
    let r = lua_sort(v.slice(half, -1), cmp)
    let out = []::int
    var i = 0
    var j = 0
    while i < l.length and j < r.length and not lfail:
        if lua_less(r[j], l[i], cmp):
            out.push(r[j])
            j++
        else:
            out.push(l[i])
            i++
    while i < l.length:
        out.push(l[i])
        i++
    while j < r.length:
        out.push(r[j])
        j++
    return out

// ------------------------------------------------------------------ packs
// A pack's code: its own globals (the builtins and lua/api's names in them) and whether it still runs.
class LPack:
    id:string
    env:int
    error = ""  // why it stopped ("" while it runs)

var l_packs = []::LPack
var l_api_names = []::string  // lua/api's functions, by id
var l_consts = []::string     // lua/api's constants
var l_const_vals = []::int
let L_BUDGET_LOAD = 10000000
let L_BUDGET_CALL = 2000000

// Everything goes: a new match starts from nothing.
def lua_reset():
    ls_text = []
    ls_ids = dictionary<string, int>(1009)
    lt_arr = []
    lt_keys = []
    lt_vals = []
    lt_map = []
    lc_proto = []
    lc_ups = []
    lbox = []
    l_protos = []
    lst = []
    rets = []
    l_packs = []
    l_loaded = false
    lerr = ""
    lfail = false
    lprint = []
    ldepth = 0
    lb_names = append(L_BASE_NAMES, l_api_names)

def lx_set_path(env:int, path:string, v:int):
    let parts = tokenize(path, ".", "")
    var t = env
    for(parts.length - 1) j:
        var sub = lua_get(t, lv_str(parts[j]))
        if sub == LV_NIL:
            sub = lv_table()
            lua_set_raw(t, lv_str(parts[j]), sub)
        t = sub
    lua_set_raw(t, lv_str(top(parts)), v)

// A pack's globals: the builtins, then the API's functions and constants.
def lua_new_env() -> int:
    let env = lv_table()
    for(lb_names) name, id:
        if name[0] != '(': lx_set_path(env, name, (id << 3) | LT_BUILTIN)
    for(l_consts) name, j: lx_set_path(env, name, l_const_vals[j])
    return env

// Runs a pack's files (name, source pairs, in order) in a new environment. "" or why it can't.
def lua_load_pack(id:string, files:[string], sources:[string]) -> string:
    let pk = LPack { id, lua_new_env() }
    l_packs.push(pk)
    for(files) file, j:
        let proto, why = lua_compile(file, sources[j])
        if why != "":
            pk.error = why
            return why
        lc_proto.push(proto)
        lc_ups.push([])
        let chunk = ((lc_proto.length - 1) << 3) | LT_FUN
        if not lua_run(pk, chunk, [], L_BUDGET_LOAD):
            return pk.error
    return ""

// After every pack loaded: what they made stays, read-only.
def lua_freeze():
    l_frozen_tab = lt_arr.length
    l_frozen_box = lbox.length
    l_frozen_clo = lc_proto.length
    l_frozen_str = ls_text.length
    l_loaded = true

// What a call made goes when it's done (it can't have kept any of it: what was made at load is read-only).
def lua_region_end():
    if not l_loaded or ldepth > 0: return
    truncate(lt_arr, l_frozen_tab)
    truncate(lt_keys, l_frozen_tab)
    truncate(lt_vals, l_frozen_tab)
    truncate(lt_map, l_frozen_tab)
    truncate(lc_proto, l_frozen_clo)
    truncate(lc_ups, l_frozen_clo)
    truncate(lbox, l_frozen_box)
    var j = l_frozen_str
    while j < ls_text.length:
        ls_ids.del(ls_text[j])
        j++
    truncate(ls_text, l_frozen_str)

// Calls f in pack pk with a budget: false if it failed (the pack is then off, and says why).
def lua_run(pk:LPack, f:int, args:[int], budget:int) -> bool:
    if pk.error != "": return false
    let env0 = l_env
    let steps0 = lsteps
    let budget0 = lbudget
    let line0 = lline
    let file0 = lerr_file
    l_env = pk.env
    if ldepth == 0:
        lsteps = 0
        lbudget = budget
    let ok = lua_call(f, args)
    if not ok:
        pk.error = lerr
        lerr = ""
        lfail = false
        print "Lua: the pack \'{pk.id}\' stopped: {pk.error}"
    l_env = env0
    if ldepth == 0:
        lsteps = steps0
        lbudget = budget0
    lline = line0
    lerr_file = file0
    return ok

// A pack's global function by name, or nil if it has none.
def lua_hook_fn(pk:LPack, name:string) -> int:
    if pk.error != "": return LV_NIL
    let known = ls_ids.get(name, -1)
    if known < 0: return LV_NIL
    let f = lua_get(pk.env, (known << 3) | LT_STR)
    let t = f & 7
    return if t == LT_FUN or t == LT_BUILTIN: f else: LV_NIL

// Calls each pack's `name` that it defines, in load order; then the region ends.
// (The callback gets each call's results, before they go.)
def lua_each(name:string, args:[int], got):
    for(l_packs) pk:
        let f = lua_hook_fn(pk, name)
        if f != LV_NIL:
            if lua_run(pk, f, args, L_BUDGET_CALL): got(rets)
    lua_region_end()

// Parse only: "" or why a file can't load (for a mod's check before it's used).
def lua_check_source(file:string, src:string) -> string:
    let n = l_protos.length
    let _, why = lua_compile(file, src)
    truncate(l_protos, n)
    return why

// Lua's own table, made from Lobster's: a list of values (Lua's 1..n).
def lua_list(vs:[int]) -> int:
    let t = lv_table()
    for(vs) v, j: lua_set_raw(t, lv_int(j + 1), v)
    return t
