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
// This file reads Lua (values, the lexer, the parser); lua/lua.lobster runs it, and the sim's API and the hook
// points are lua/api.lobster's. A program that only checks packs (gen/mods) needs this file alone.

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

// Parse only: "" or why a file can't load (for a mod's check before it's used).
def lua_check_source(file:string, src:string) -> string:
    let n = l_protos.length
    let _, why = lua_compile(file, src)
    truncate(l_protos, n)
    return why
