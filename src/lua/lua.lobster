// ------------------------------------------------------------------ running Lua (#82)
// What lua/parse.lobster read, run: the budget, tables, the interpreter, the base library and packs.

import lua.parse

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

// Lua's own table, made from Lobster's: a list of values (Lua's 1..n).
def lua_list(vs:[int]) -> int:
    let t = lv_table()
    for(vs) v, j: lua_set_raw(t, lv_int(j + 1), v)
    return t
