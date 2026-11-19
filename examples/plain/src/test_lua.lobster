// Lua for mods (#82): the language, its refusals and its limits, headless. ../../../check.sh runs it.
//   lobster test_lua.lobster
import sim_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// A pack of one file, loaded fresh: what it printed, joined by "|", or its error.
def run(src:string) -> string:
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_quiet = true
    let why = lua_load_pack("t", [ "t.lua" ], [ src ])
    lua_freeze()
    return if why != "": "error: " + why else: concat_string(lprint, "|")

// Calls the loaded pack's global `name` (as a hook is called): what it printed since the load, or its error.
def call(name:string, args:[int]) -> string:
    lprint = []
    let pk = l_packs[0]
    let f = lua_hook_fn(pk, name)
    if f == LV_NIL: return "error: no {name}"
    let ok = lua_run(pk, f, args, L_BUDGET_CALL)
    lua_region_end()
    return if not ok: "error: " + pk.error else: concat_string(lprint, "|")

def gives(src:string, want:string):
    let got = run(src)
    check(got == want, "{src}\n  want: {want}\n  got:  {got}")

def fails_with(src:string, part:string):
    let got = run(src)
    check(starts_with(got, "error: ") and find_string(got, part) >= 0, "{src}\n  want an error with: {part}\n  got: {got}")

def test_values():
    gives("print(1 + 2 * 3, 7 // 2, -7 // 2, 7 % 3, -7 % 3, 7 % -3)", "7\t3\t-4\t1\t2\t-2")
    gives("print(0x10, 1 << 4, 256 >> 4, 6 & 3, 6 | 3, 6 ~ 3, ~0)", "16\t16\t16\t2\t7\t5\t-1")
    gives("print(\"a\" .. 1 .. \'b\', #\"hello\", \"x\" < \"y\")", "a1b\t5\ttrue")
    gives("print(nil, true, false, not nil, not 0, 1 == 1, 1 ~= 1)", "nil\ttrue\tfalse\ttrue\tfalse\ttrue\tfalse")
    gives("print(nil or 5, false and 1, 2 and 3, nil and nil)", "5\tfalse\t3\tnil")
    gives("print(type(1), type(\'s\'), type({{}}), type(print), type(nil), type(true))", "number\tstring\ttable\tfunction\tnil\tboolean")
    gives("print(\"tab\\tline\\n\" .. [[long\nstring]])", "tab\tline\nlong\nstring")
    gives("--[[ a long\ncomment ]] print(1) -- and a short one", "1")
    gives("print(tostring(12) .. \"!\", tonumber(\"42\") + 1, tonumber(\"x\"))", "12!\t43\tnil")
    gives("print(2 + 3 == 5, 1 < 2, 2 <= 2, 3 > 4, 3 >= 4)", "true\ttrue\ttrue\tfalse\tfalse")

def test_statements():
    gives("local s = 0 for i = 1, 10 do s = s + i end print(s)", "55")
    gives("local s = 0 for i = 10, 1, -3 do s = s * 10 + i end print(s)", "10741")
    gives("local n = 0 while n < 5 do n = n + 1 if n == 3 then break end end print(n)", "3")
    gives("local n = 0 repeat local m = n n = n + 1 until m >= 2 print(n)", "3")
    gives("local x = 5 if x < 3 then print(\'a\') elseif x < 6 then print(\'b\') else print(\'c\') end", "b")
    gives("local a, b, c = 1, 2 print(a, b, c) a, b = b, a print(a, b)", "1\t2\tnil|2\t1")
    gives("local x = 1 do local x = 2 print(x) end print(x)", "2|1")
    gives("local x = 1 local x = x + 1 print(x)", "2")

def test_functions():
    gives("local function f(a, b) return a + b, a - b end print(f(5, 3)) print((f(5, 3)))", "8\t2|8")
    gives("local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end print(fib(15))", "610")
    gives("function g(x) return x * 2 end print(g(21))", "42")
    gives("local t = {{}} function t.add(a, b) return a + b end function t:get() return self.v end t.v = 9 print(t.add(1, 2), t:get())", "3\t9")
    gives("local function counter() local n = 0 return function() n = n + 1 return n end end local c = counter() c() c() print(c())", "3")
    gives("local fs = {{}} for i = 1, 3 do fs[i] = function() return i end end print(fs[1](), fs[3]())", "1\t3")
    gives("local function f() return 1, 2, 3 end local t = {{ f() }} print(#t, select(\'#\', f()), select(2, f()))", "3\t3\t2\t3")
    gives("print(string.format(\'%d-%s-%%\', 5, \'x\'), string.sub(\'hello\', 2, 3), string.sub(\'hello\', -3))", "5-x-%\tel\tllo")
    gives("print(math.min(3, 1, 2), math.max(3, 1, 2), math.abs(-4))", "1\t3\t4")

def test_tables():
    gives("local t = {{ 10, 20, 30, x = 1, [\'y\'] = 2 }} print(#t, t[2], t.x, t.y, t.z)", "3\t20\t1\t2\tnil")
    gives("local t = {{}} t[1] = \'a\' t[2] = \'b\' t[4] = \'d\' print(#t) t[3] = \'c\' print(#t, t[4])", "2|4\td")
    gives("local t = {{}} table.insert(t, 1) table.insert(t, 2) table.insert(t, 1, 0) print(table.concat(t, \',\'), table.remove(t), #t)", "0,1,2\t2\t2")
    gives("local t = {{ 5, 2, 8, 1 }} table.sort(t) print(table.concat(t, \' \')) table.sort(t, function(a, b) return a > b end) print(table.concat(t, \' \'))", "1 2 5 8|8 5 2 1")
    gives("local s = \'\' for i, v in ipairs({{ \'a\', \'b\', \'c\' }}) do s = s .. i .. v end print(s)", "1a2b3c")
    // pairs: the array part, then the rest in the order it was set
    gives("local t = {{ 1, 2, z = 3, a = 4 }} t.m = 5 local s = \'\' for k, v in pairs(t) do s = s .. k .. v .. \' \' end print(s)", "11 22 z3 a4 m5 ")
    gives("local t = {{ a = 1, b = 2 }} t.a = nil local n = 0 for k in pairs(t) do n = n + 1 end print(n, next(t))", "1\tb\t2")
    gives("local t = {{}} for i = 1, 50 do t[\'k\' .. i] = i end print(t.k1 + t.k50, t.k25)", "51\t25")

def test_refusals():
    fails_with("local x = 1.5", "integers")
    fails_with("local x = 1e3", "integers")
    fails_with("local x = 6 / 2", "//")
    fails_with("local x = 2 ^ 3", "floats")
    fails_with("local f = function(...) end", "varargs")
    fails_with("goto done", "goto")
    fails_with("io.write(\'x\')", "global \'io\'")
    fails_with("os.exit()", "global \'os\'")
    fails_with("load(\'x = 1\')()", "global \'load\'")
    fails_with("require(\'socket\')", "global \'require\'")
    fails_with("setmetatable({{}}, {{}})", "global \'setmetatable\'")
    fails_with("debug.getinfo(1)", "global \'debug\'")
    fails_with("string.dump(print)", "field \'dump\'")
    fails_with("local x = 1 + nil", "arithmetic")
    fails_with("local x = 1 // 0", "division by zero")
    fails_with("local t = nil local y = t.x", "index a nil")
    fails_with("error(\'mine\')", "t.lua:1: mine")
    fails_with("local x = 1\nlocal y = {{}} + 1", "t.lua:2:")
    fails_with("local x = = 1", "expression expected")
    fails_with("local function f() return f() end f()", "nested too deep")

def test_limits():
    fails_with("while true do end", "step budget")
    // the files run once; then what they made is read-only, and state lasts only in hook columns
    gives("count = 0 local t = {{}} function bump() count = count + 1 end function grow() t[1] = 1 end local n = 0 function inc() n = n + 1 end function temp() local u = {{}} u[1] = 5 print(u[1]) end", "")
    check(starts_with(call("bump", []), "error: ") and find_string(l_packs[0].error, "read-only") >= 0, "a global can\'t change after the load")
    run("local t = {{}} function grow() t[1] = 1 end")
    check(find_string(call("grow", []), "read-only") >= 0, "a table made at load can\'t change after it")
    run("local n = 0 function inc() n = n + 1 end")
    check(find_string(call("inc", []), "read-only") >= 0, "a file-level local can\'t change after the load")
    run("function temp(a) local u = {{ a }} u[2] = a .. \'!\' print(u[1], u[2]) end")
    let tables = lt_arr.length
    let strings = ls_text.length
    check(call("temp", [ lv_int(7) ]) == "7\t7!", "a call\'s own tables and strings work")
    check(lt_arr.length == tables and ls_text.length == strings, "and go when it returns")
    check(call("temp", [ lv_int(8) ]) == "8\t8!", "and again")
    // a pack that failed is off from then on
    run("function boom() error(\'once\') end")
    check(starts_with(call("boom", []), "error: "), "an error stops the call")
    check(lua_hook_fn(l_packs[0], "boom") == LV_NIL, "and the pack\'s hooks are off")
    // the panel's read can't change the sim
    run("function task_name(i) set_u_task(i, 3) return \'x\' end")
    lua_on = true
    check(lua_task_name(0) == "" and find_string(l_packs[0].error, "only reads") >= 0, "task_name can\'t write")
    lua_on = false

def test_check_source():
    check(lua_check_source("a.lua", "local x = 1") == "", "a good file checks")
    check(find_string(lua_check_source("a.lua", "local x = 1.0"), "a.lua:1") >= 0, "a bad file says where")

test_values()
test_statements()
test_functions()
test_tables()
test_refusals()
test_limits()
test_check_source()
print "test_lua: {passes} passed, {fails} failed"
if fails: set_exit_code(1)
