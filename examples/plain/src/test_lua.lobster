// Lua for mods (#82): the language, its refusals and its limits, headless. ../../../check.sh runs it.
//   lobster test_lua.lobster
import sim_modules
import testkit.invariants
import testkit.pack_tests

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

var load_budget = L_BUDGET_LOAD  // (smaller for the fuzz: a mutant that loops forever stops soon)

// A pack of one file, loaded fresh: what it printed, joined by "|", or its error.
def run(src:string) -> string:
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_quiet = true
    stops_forgotten()
    let why = lua_load_pack("t", [ "t.lua" ], [ src ], load_budget)
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

let given = []::string  // every gives(): its source, then what it printed (lua_diff.sh runs them in real Lua too)

def gives(src:string, want:string):
    given.push(src)
    given.push(want)
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
    fails_with("local x = -8 >> 1", "negative number shifted right")
    fails_with("local x = -8 << -1", "negative number shifted right")
    gives("print(8 >> 1, -8 << 1, 8 << -1, 1 << 64, 5 >> 70)", "4\t-16\t4\t0\t0")
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
    // the panel's read can't change the sim, and a failure there doesn't stop the pack (it runs on one machine)
    run("function task_name(i) set_u_task(i, 3) return \'x\' end")
    lua_on = true
    check(lua_task_name(0) == "" and find_string(l_packs[0].view_error, "only reads") >= 0, "task_name can\'t write")
    check(l_packs[0].error == "", "and the pack runs on")
    lua_on = false

def test_check_source():
    check(lua_check_source("a.lua", "local x = 1") == "", "a good file checks")
    check(find_string(lua_check_source("a.lua", "local x = 1.0"), "a.lua:1") >= 0, "a bad file says where")

// A call as the sim makes it (lua/api's lua_hook_run: the call's and the tick's budgets): "ok", or the error.
def hook(name:string, args:[int]) -> string:
    lprint = []
    let pk = l_packs[0]
    let f = lua_hook_fn(pk, name)
    if f == LV_NIL: return "error: off ({pk.error})"
    let ok = lua_hook_run(pk, f, args)
    lua_region_end()
    return if not ok: "error: " + pk.error else: "ok"

def stops_forgotten():
    hook_stopped = []
    hook_stopped_why = []

def test_crashes():  // (each was a crash of the VM, not an error in the pack)
    gives("print(select(-1, \'a\', \'b\', \'c\'))", "c")
    gives("print(select(-2, \'a\', \'b\', \'c\'))", "b\tc")
    fails_with("select(-4, 1, 2)", "out of range")
    fails_with("select(0, 1)", "out of range")
    fails_with("local t = {{ 3, 1, 2, 5, 4 }} table.sort(t, function(a, b) t[#t] = nil return a < b end)", "table.sort")
    fails_with("local t = {{ 3, 1, 2 }} table.sort(t, function(a, b) table.insert(t, 9) return a < b end)", "table.sort")
    fails_with("local t = {{ 3, 1, 2 }} table.sort(t, function(a, b) error(\'cmp\') end)", "cmp")
    fails_with("local s = \'x\' for i = 1, 40 do s = s .. s end", "over 1 MB")
    fails_with("local s = string.rep(\'ab\', 1 << 59)", "string.rep")
    fails_with("local s = string.rep(\'ab\', 1 << 58)", "string.rep")
    fails_with("local t = {{}} for i = 1, 20 do t[i] = string.rep(\'x\', 100000) end local s = table.concat(t)", "over 1 MB")
    fails_with("for i = 1, 400 do local s = string.rep(\'x\', 99990 + i % 10) .. i end", "16 MB")
    fails_with("for i = 1, 400 do local s = string.format(\'%s%d\', string.rep(\'y\', 99999), i) end", "16 MB")
    fails_with("local s = string.rep(\'z\', 100000) for i = 1, 400 do local u = s:sub(i) end", "16 MB")
    // nesting: an error, never the stack
    fails_with("local x = " + repeat_string("(", 5000) + "1" + repeat_string(")", 5000), "nested too deep")
    fails_with("local x = " + repeat_string("{{", 5000) + repeat_string("}}", 5000), "nested too deep")
    fails_with(repeat_string("do ", 5000) + repeat_string("end ", 5000), "nested too deep")
    fails_with("local x = " + repeat_string("- ", 5000) + "1", "nested too deep")
    fails_with("local x = " + repeat_string("not ", 5000) + "1", "nested too deep")
    fails_with("local x = 1" + repeat_string(" + 1", 5000), "nested too deep")
    fails_with("local x = \'a\'" + repeat_string(" .. \'a\'", 5000), "nested too deep")
    fails_with("local t = {{}} local x = t" + repeat_string(".a", 5000), "nested too deep")
    fails_with("local f = print " + repeat_string("f = function() ", 300) + repeat_string("end ", 300), "nested too deep")
    gives("print(" + repeat_string("(", 150) + "1" + repeat_string(")", 150) + ")", "1")
    // as deep as it goes, at the call limit too: still fine
    gives("local function f(n) if n == 0 then return 0 end return " + repeat_string("1 + (", 10) + "f(n - 1)" + repeat_string(")", 10) + " end print(f(100))", "1000")
    // deep code, deep calls: what's running is limited all together, not only call by call
    fails_with("local function f(n) if n == 0 then return 0 end return " + repeat_string("1 + (", 90) + "f(n - 1)" + repeat_string(")", 90) + " end print(f(190))", "nested too deep")
    fails_with("local function f(n) if n == 0 then return 0 end return " + repeat_string("1 + (", 20) + "f(n - 1)" + repeat_string(")", 20) + " end print(f(190))", "nested too deep")

def test_view():  // (the placement preview and the panel ask too, on one machine: they mustn't change the sim)
    lua_on = true
    run("function task_name(i) error(\'boom\') end function on_tick() print(\'ticked\') end")
    check(lua_task_name(0) == "" and l_packs[0].error == "", "a task_name that fails doesn\'t stop the pack")
    check(call("on_tick", []) == "ticked", "and its on_tick still runs")
    run("function can_place(p, k, x, y, sx, sy) if x > 5 then error(\'far\') end return x < 3 end")
    hook_view = true
    check(lua_can_place(0, 0, 9, 0, 1, 1) and l_packs[0].error == "", "the preview\'s can_place fails: allowed, and the pack runs on")
    check(not lua_can_place(0, 0, 4, 0, 1, 1) and lua_can_place(0, 0, 1, 0, 1, 1), "and it still refuses and allows")
    run("function can_place() while true do end end")
    check(lua_can_place(0, 0, 1, 0, 1, 1) and l_packs[0].error == "" and find_string(l_packs[0].view_error, "budget ({L_BUDGET_VIEW}") >= 0,
        "the preview has a small budget")
    hook_view = false
    check(lua_can_place(0, 0, 1, 0, 1, 1) and find_string(l_packs[0].error, "budget") >= 0, "the sim\'s can_place stops the pack")
    check(hook_stopped.length == 1 and hook_stopped[0] == "t" and find_string(hook_stopped_why[0], "budget") >= 0, "and the match\'s state says so")
    stops_forgotten()
    // can_place only reads, even from the sim
    run("function can_place(p, k, x, y, sx, sy) set_pop(0, 1) return true end")
    lua_can_place(0, 0, 1, 0, 1, 1)
    check(find_string(l_packs[0].error, "only reads") >= 0, "can_place can\'t write")
    stops_forgotten()
    // every writer is refused to a reader
    for(LA_WRITE_NAMES) name:
        run("function task_name(i) {name}() return \'x\' end")
        lua_task_name(0)
        check(find_string(l_packs[0].view_error, "{name}: this hook only reads") >= 0, "{name} is refused to a reader")
    for(LA_NAMES) name:
        if starts_with(name, "set_") or ends_with(name, "_set"): check((find(LA_WRITE_NAMES) n: n == name) >= 0, "{name} is a writer")
    lua_on = false

def test_type_index():  // (#226: a building type by its buildings.json key, as place() takes it)
    bt_name = [ "hut", "hall" ]
    run("function go() print(building_type_index(\"hall\"), building_type_index(\"hut\"), building_type_index(\"keep\")) end")
    check(call("go", []) == "1\t0\t-1", "building_type_index finds a type by its key, -1 for none")
    bt_name = []

def test_pooled_goods():  // (#222: a player's goods in a pooled economy, from Lua)
    let names0 = resource_names
    resource_names = [ "food", "gold" ]
    pop = [ 0, 0 ]
    stock = [ [ 10, 3 ], [ 0, 0 ] ]
    r_stocked = 0
    events_on = true
    events = []
    run("function go() print(stock_take(0, 0, 4), stock(0, 0), stock_take(0, 0, 100), stock_put(1, 1, 7), stock(1, 1)) end")
    check(call("go", []) == "4\t6\t6\t7\t7", "stock_take takes what\'s there, stock_put adds, stock reads")
    check(stock[0][0] == 0 and stock[1][1] == 7 and stock[0][1] == 3, "from the player named only")
    check(events.length == 3 and events[0].kind == EV_STOCK_TAKEN and events[0].a == 0 and events[0].n == 4 and events[2].kind == EV_STOCK_PUT and events[2].a == 1 and events[2].c == 1, "each with its event, naming the player")
    r_stocked = 1
    run("function go() stock_take(0, 0, 1) end")
    check(find_string(call("go", []), "the economy is stocked") >= 0, "a stocked economy\'s goods are in holds: stock_take says so")
    run("function go() stock_put(2, 0, 1) end")
    check(find_string(call("go", []), "no player 2") >= 0, "a player that isn\'t there is an error")
    r_stocked = 0
    events = []
    events_on = false
    stock = []
    pop = []
    resource_names = names0

def test_events():  // (#187: a pack's own events, and reading this tick's)
    events_on = true
    events = []
    run("function go() emit(7, 1, 2, 3, 4) print(event_count(), event_get(0, 0), event_get(0, 1), event_get(0, 4)) end")
    check(call("go", []) == "1\t{EV_PACK + 7}\t1\t4", "a pack emits its own event and reads it back")
    check(events.length == 1 and events[0].kind == EV_PACK + 7 and events[0].c == 3, "and it\'s in the tick\'s events")
    run("function go() emit(900, 0, 0, 0, 0) end")
    check(find_string(call("go", []), "0 to 899") >= 0, "a pack\'s event code is 0 to 899")
    run("function go() return event_get(5, 0) end")
    check(find_string(call("go", []), "no event 5") >= 0, "an event that isn\'t there is an error")
    events = []
    events_on = false

def test_pack_tests():  // (#190: a pack's own tests, tests/*.lua, run by testkit/pack_tests)
    check(equal(pack_test_names([ "function test_a() end\nfunction test_a_2() end\nlocal function helper() end", "function test_b_x() end\nfunction test_a() end" ]), [ "test_a", "test_b_x" ]), "a pack\'s tests are its test_ functions, a later phase (_2) not one")
    let src = "function test_kept() keep(\"n\", 3) wait(2) end\n" +
        "function test_kept_2() expect(kept(\"n\") == 3, \"kept from the phase before\") expect(tick() == 2, \"two ticks on\") end\n" +
        "function test_wrong() expect(1 == 2, \"one is two\") end\n" +
        "function test_late() wait_for(\"built\", 3) end\n" +
        "function test_mine() emit(5, 0, 0, 0, 0) end\n" +
        "function test_soon() wait_for(7, 10) end\n"
    lua_quiet = true
    let got = pack_tests("plain", [ "t.lua" ], [ src ]):
        tick = 0
        events = []
    fn:
        events = []
        if tick == 4: events.push(Event { EV_PACK + 7, 0, 0, 0, 0, 0, 0 })
        tick++
    check(equal(got, [ "ok test_kept", "FAIL test_wrong: test_wrong: one is two", "FAIL test_late: after test_late: no built event in 3 ticks", "ok test_mine", "ok test_soon" ]), "a pack\'s tests pass, fail on an expect, and wait for ticks and events: {got}")
    tick = 0
    events = []
    run("function go() wait(1) end")
    check(find_string(call("go", []), "only a pack\'s tests") >= 0, "the tests\' own functions are refused to a pack\'s rules")
    run("function go() place(0, \"hut\", 1, 1, true) end")
    check(find_string(call("go", []), "only a pack\'s tests") >= 0, "place too")

def test_budgets():
    // a pack's calls in one tick share a budget: past it, the pack stops
    run("function work(n) for i = 1, n do end end")
    let n = lv_int(L_BUDGET_TICK / 3 + 1)
    tick = 1000
    check(hook("work", [ n ]) == "ok" and hook("work", [ n ]) == "ok", "two calls fit a tick")
    tick++
    check(hook("work", [ n ]) == "ok" and hook("work", [ n ]) == "ok", "and two more the next")
    let third = hook("work", [ n ])
    check(starts_with(third, "error: ") and find_string(third, "budget") >= 0, "a third the same tick is over its budget: {third}")
    check(starts_with(hook("work", [ lv_int(1) ]), "error: off"), "and the pack is off")
    stops_forgotten()
    // one call can't take the whole tick's
    run("function work(n) for i = 1, n do end end")
    tick++
    check(find_string(hook("work", [ lv_int(L_BUDGET_CALL) ]), "budget") >= 0, "one call has its own budget")
    stops_forgotten()
    tick = 0

def test_dispatch():  // (two packs: each hook asks both, in load order)
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_rules = su_rules
    lua_quiet = true
    lua_on = true
    lua_load_pack("a", [ "a.lua" ], [ "function on_hit(by, t, d) return d * 2 end function ai_train_score(p, s, k, n) return n + 1 end function can_place() return true end" ])
    lua_load_pack("b", [ "b.lua" ], [ "function on_hit(by, t, d) return d + 1 end function ai_train_score(p, s, k, n) return n * 10 end function can_place(p) return p ~= 1 end" ])
    lua_freeze()
    check(lua_on_hit(0, 0, 5) == 11, "on_hit: each pack\'s damage goes to the next")
    check(lua_ai_train_score(0, "spear", 0, 4) == 50, "ai_train_score: the same")
    check(lua_can_place(0, 0, 0, 0, 1, 1) and not lua_can_place(1, 0, 0, 0, 1, 1), "can_place: any pack refuses")
    // one pack stopping leaves the other running
    lua_reset()
    lua_api_consts()
    lua_quiet = true
    lua_load_pack("a", [ "a.lua" ], [ "function on_hit(by, t, d) error(\'a broke\') end" ])
    lua_load_pack("b", [ "b.lua" ], [ "function on_hit(by, t, d) return d + 1 end" ])
    lua_freeze()
    check(lua_on_hit(0, 0, 5) == 6 and lua_on_hit(0, 0, 5) == 6, "a stopped pack is passed over")
    check(hook_stopped.length == 1 and hook_stopped[0] == "a", "and noted once")
    stops_forgotten()
    lua_on = false

def test_tables_edges():
    gives("local t = {{}} t[2] = \'b\' t[1] = \'a\' t[2] = nil t[2] = \'c\' table.insert(t, \'d\') print(#t, t[2], t[3])", "3\tc\td")
    gives("local t = {{}} t[3] = 3 t[1] = 1 t[2] = 2 print(#t, t[3]) t[3] = nil print(#t) t[3] = 9 print(#t, t[3])", "3\t3|2|3\t9")
    gives("local t = {{ 1, 2, 3 }} for k in pairs(t) do t[k] = nil end print(#t, next(t))", "0\tnil")
    gives("local t = {{ a = 1, b = 2, c = 3 }} for k in pairs(t) do t[k] = nil end print(next(t))", "nil")
    gives("local t = {{ 1, 2, 3, x = 1 }} t[2] = nil local n = 0 for k, v in pairs(t) do n = n + 1 end print(n)", "3")
    gives("local t = {{}} t[-1] = \'m\' t[0] = \'z\' print(#t, t[-1], t[0])", "0\tm\tz")
    gives("local t = {{}} for i = 1, 20 do t[\'k\' .. i] = i end for i = 1, 20, 2 do t[\'k\' .. i] = nil end local s = 0 for k, v in pairs(t) do s = s + v end print(s)", "110")
    gives("local t = {{ 3, 1, 2 }} table.sort(t, function(a, b) return a > b end) print(t[1], t[2], t[3])", "3\t2\t1")
    gives("local t = {{}} print(table.remove(t), #t)", "nil\t0")
    fails_with("local t = {{}} t[nil] = 1", "index is nil")

def test_lexer():
    gives("print(\'a\\tb\', \"q\\\"q\", \'\\65\\066\')", "a\tb\tq\"q\tAB")
    gives("print([==[a]]b]=]c]==])", "a]]b]=]c")
    gives("print(#\'é\', #\'\\200\')", "2\t1")
    gives("print(\'héllo\')", "héllo")
    gives("print(string.format(\'é%dé\', 1))", "é1é")
    fails_with("print(string.format(\'50%\'))", "nothing after it")
    gives("print(string.format(\'50%%\'))", "50%")
    fails_with("print(\'abc)", "unfinished string")
    fails_with("print(\'abc\nd\')", "unfinished string")
    fails_with("print([[abc)", "unfinished long string")
    fails_with("--[[ never closed", "unfinished long comment")
    fails_with("local x = 0x", "malformed number")
    fails_with("local x = 12abc", "malformed number")
    fails_with("local x = \'\\q\'", "escape")
    fails_with("local x = \'\\300\'", "past 255")
    fails_with("local x = 1152921504606846976", "too big")
    fails_with("local x = 0x1000000000000000", "too big")
    gives("print(1152921504606846975, -1152921504606846975)", "1152921504606846975\t-1152921504606846975")
    fails_with("local x = @", "character")

def test_library_edges():
    gives("print(tonumber(\'0x10\'), tonumber(\' 5 \'), tonumber(\'-7\'), tonumber(\'5x\'), tonumber(\'\'), tonumber(\'1.5\'))", "16\t5\t-7\tnil\tnil\tnil")
    gives("print(tonumber(\'99999999999999999999\'))", "nil")
    gives("print((\'abc\'):upper(), (\'x\'):rep(3), (\'hello\'):sub(2, 3), (\'abc\'):len())", "ABC\txxx\tel\t3")
    gives("local s = \'hello\' print(s:find(\'l\'), s:find(\'l\', 4), s:find(\'l\', -2), s:find(\'l\', 10))", "3\t4\t4\tnil")
    fails_with("local x = (\'abc\'):nothing()", "can\'t call")
    fails_with("local x = (5):upper()", "can\'t call method")

// Bad input never crashes: snippets cut, spliced and with bits put in (a seeded walk, the same each run) load or fail
// with an error.
def test_fuzz():
    let seeds = [ "local function f(a, b) return a + b, a - b end print(f(5, 3))", "local t = {{ 10, 20, x = 1 }} for k, v in pairs(t) do print(k, v) end",
        "local s = 0 for i = 1, 10 do s = s + i end print(s)", "local x = 5 if x < 3 then print(\'a\') elseif x < 6 then print(\'b\') else print(\'c\') end",
        "local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end print(fib(10))", "print(string.format(\'%d-%s\', 5, \'x\'), (\'ab\'):rep(2))",
        "local t = {{}} table.insert(t, 1) table.sort(t, function(a, b) return a > b end) print(select(\'#\', 1, 2), #t)",
        "local n = 0 repeat n = n + 1 until n >= 3 while n > 0 do n = n - 1 if n == 1 then break end end print(n)",
        "print([[long]] .. \"x\\n\" .. 0x1f // 2 % 3 << 1 >> 1 & 7 | 8 ~ 1)" ]
    let bits = [ "(", ")", "{{", "}}", "[", "]", "=", "==", "..", "-", "--", "\'", "\"", "[[", "]]", "\\", "end", "do", "function", "local", "return",
        "1 << 62", "#", ":", ".", ",", ";", "nil", "and", "not", "0x", "9999999999999999999", "%", "//", "~", "t", "f(", "select(-9, 1)" ]
    var seed = 12345
    var tried = 0
    for(20000):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var src = seeds[seed % seeds.length]
        for(1 + seed % 4):
            seed = (seed * 1103515245 + 12345) % 2147483648
            let at = seed % (src.length + 1)
            seed = (seed * 1103515245 + 12345) % 2147483648
            let what = seed % 3
            if what == 0: src = substring(src, 0, at) + bits[(seed >> 4) % bits.length] + substring(src, at, src.length - at)
            elif what == 1: src = substring(src, 0, at) + substring(src, min(src.length, at + (seed >> 4) % 7), -1)
            else:
                let other = seeds[(seed >> 4) % seeds.length]
                let off = min(other.length, (seed >> 8) % 20)
                src = substring(src, 0, at) + substring(other, off, min(15, other.length - off)) + substring(src, at, src.length - at)
        let got = run(src)
        tried++
        check(got == concat_string(lprint, "|") or starts_with(got, "error: "), "fuzz: {src}")
    check(tried == 20000, "fuzz: every one ran")

// ------------------------------------------------------------------ process{} (#194): rules in named phases
// A pack's Lua with Creel's process library loaded first, as lua_declare loads it, and its hook columns fresh.
def run_process(src:string) -> string:
    l_api_names = LA_NAMES
    lua_reset()
    lua_api_consts()
    lua_quiet = true
    stops_forgotten()
    hook_unit_names = []
    hook_unit_cols = []
    hook_building_names = []
    hook_building_cols = []
    let why = lua_load_pack("t", [ LUA_PROCESS_FILE, "t.lua" ], [ LUA_PROCESS, src ])
    lua_freeze()
    return if why != "": "error: " + why else: concat_string(lprint, "|")

// One rule, a meal: walk till there (x 30 on), eat 3 ticks, then one that has to (y over 0) waits up to 5 ticks for a
// pack event naming it (code 7, a its id); one that doesn't, or that got it, is done; one that waited in vain walks again.
let MEAL_BY_HAND = """
local col_ph = unit_column("hand_phase")
local col_at = unit_column("hand_at")
local function enter(i, ph, ticks)
  unit_set(col_ph, i, ph)
  if ticks then unit_set(col_at, i, tick() + ticks) else unit_set(col_at, i, 0) end
  if ph == 0 then print(tick(), u_id(i), "done") else print(tick(), u_id(i), ({ "walk", "eat", "wait" })[ph]) end
end
function start(i) enter(i, 1) end
function on_tick()
  for i = 0, unit_count() - 1 do
    local ph = unit_get(col_ph, i)
    if ph == 1 then
      if u_x(i) >= 30 then enter(i, 2, 3) end
    elseif ph == 2 then
      if tick() >= unit_get(col_at, i) then
        if u_y(i) > 0 then enter(i, 3, 5) else enter(i, 0) end
      end
    elseif ph == 3 then
      local got = false
      for e = 0, event_count() - 1 do
        if event_get(e, 0) == 107 and event_get(e, 1) == u_id(i) then got = true end
      end
      if got then enter(i, 0)
      elseif tick() >= unit_get(col_at, i) then enter(i, 1) end
    end
  end
end
"""

let MEAL_AS_PROCESS = """
local function say(what) return function(i) print(tick(), u_id(i), what) end end
local meal = process{ name = "meal", leave = say("done"), phases = {
  { "walk", enter = say("walk"), done = function(i) return u_x(i) >= 30 end, next = "eat" },
  { "eat", enter = say("eat"), ticks = 3, next = function(i) if u_y(i) > 0 then return "wait" end end },
  { "wait", enter = say("wait"), event = 7, match = function(i, a) return a == u_id(i) end, ticks = 5, timeout = "walk" },
} }
function start(i) meal.start(i) end
function on_tick() meal.tick() end
function phase(i) print(tostring(meal.phase(i)) .. " " .. tostring(meal.left(i))) end
function stop(i) meal.stop(i) end
"""

// Runs a meal rule on three units for 40 ticks (each walks 5 a tick; unit 9's event comes at tick 20): what it printed.
def meal_trace(src:string) -> string:
    let loaded = run_process(src)
    if loaded != "": return loaded
    u_id = [ 4, 9, 12 ]
    u_x = [ 0, 0, 10 ]
    u_y = [ 0, 1, 1 ]
    tick = 0
    events_on = true
    var out = []::string
    for(3) i: out.push(call("start", [ lv_int(i) ]))
    for(40):
        events = []
        if tick == 20: events.push(Event { EV_PACK + 7, 9, 0, 0, 0, 0, 0 })
        for(3) i: u_x[i] += 5
        let got = call("on_tick", [])
        if got != "": out.push(got)
        tick++
    events = []
    events_on = false
    return concat_string(out, "|")

def test_process():
    let hand = meal_trace(MEAL_BY_HAND)
    let proc = meal_trace(MEAL_AS_PROCESS)
    check(find_string(hand, "done") >= 0 and find_string(hand, "\t12\twait") >= 0, "the hand-made meal runs: {hand}")
    check(proc == hand, "a rule as process\{\} does what the same rule by hand does\n  hand: {hand}\n  proc: {proc}")
    check(MEAL_AS_PROCESS.length * 2 < MEAL_BY_HAND.length + MEAL_AS_PROCESS.length, "and it\'s shorter")
    // (unit 12 waits in vain and walks again; unit 9 got its event; unit 4 never waits)
    check(find_string(proc, "20\t9\tdone") >= 0 or find_string(proc, "21\t9\tdone") >= 0, "a phase waiting on an event goes on when it comes: {proc}")
    // what it says of a unit, and stopping it
    run_process(MEAL_AS_PROCESS)
    u_id = [ 4 ]
    u_x = [ 50 ]
    u_y = [ 1 ]
    tick = 100
    call("start", [ lv_int(0) ])
    check(call("phase", [ lv_int(0) ]) == "walk 0" or find_string(call("phase", [ lv_int(0) ]), "walk") >= 0, "a unit\'s phase by name")
    call("on_tick", [])
    check(call("phase", [ lv_int(0) ]) == "eat 3", "and the ticks left of its timer: {call("phase", [ lv_int(0) ])}")
    check(call("stop", [ lv_int(0) ]) == "100\t4\tdone", "stopping it leaves it")
    check(call("phase", [ lv_int(0) ]) == "nil 0", "and then it has no phase")
    check(hook_unit_names.length == 2 and hook_unit_names[0] == "meal_phase" and hook_unit_names[1] == "meal_at", "its state is two hook columns: {hook_unit_names}")
    tick = 0
    // a declaration that's wrong is the pack's error, as it loads
    check(find_string(run_process("process\{ name = \"m\", phases = \{ \{ \"a\", next = \"b\" \} \} \}"), "goes on to b, which is no phase") >= 0, "a phase going on to one that isn\'t there")
    check(find_string(run_process("process\{ name = \"m\", phases = \{ \{ \"a\" \}, \{ \"a\" \} \} \}"), "two phases are called a") >= 0, "two phases of a name")
    check(find_string(run_process("process\{ name = \"m\", phases = \{ \{ \"a\", event = \"nope\" \} \} \}"), "no event kind nope") >= 0, "an event kind that isn\'t one")
    check(find_string(run_process("process\{ phases = \{\} \}"), "it needs a name") >= 0, "a process without a name")
    check(run_process("print(event_kind(\"built\") == {EV_BUILT}, event_kind(\"drop\") == {EV_DROP})") == "true\ttrue", "event_kind names the engine\'s kinds")
    // on buildings
    b_id = [ 7 ]
    run_process("local p = process\{ name = \"bp\", on = \"building\", phases = \{ \{ \"one\", ticks = 2, next = \"two\" \}, \{ \"two\" \} \} \}\nfunction go() p.start(0) end function on_tick() p.tick() end function ph() print(p.phase(0)) end")
    call("go", [])
    tick = 2
    call("on_tick", [])
    check(call("ph", []) == "two" and hook_building_names.length == 2, "a process on buildings")
    b_id = []
    u_id = []
    u_x = []
    u_y = []
    tick = 0

test_values()
test_statements()
test_functions()
test_tables()
test_refusals()
test_limits()
test_check_source()
test_crashes()
test_view()
test_type_index()
test_pooled_goods()
test_events()
test_process()
test_pack_tests()
test_budgets()
test_dispatch()
test_tables_edges()
test_lexer()
test_library_edges()
load_budget = 20000
test_fuzz()
load_budget = L_BUDGET_LOAD
// Integer expressions at random (seeded): what they make here, checked in real Lua by lua_diff.sh. Small enough that
// 61 bits and Lua's 64 agree: operands under 30, shifts under 5, eight at most.
def random_expr(seed:int, depth:int) -> string, int:
    let r = (seed * 1103515245 + 12345) % 2147483648
    if depth == 0 or r % 5 == 0:
        let n = (r >> 4) % 61 - 30
        return (if n < 0: "({n})" else: "{n}"), r
    let ops = [ "+", "-", "*", "//", "%", "&", "|", "~", "<<", ">>" ]
    let op = ops[(r >> 4) % ops.length]
    let a, r1 = random_expr(r, depth - 1)
    if op == "<<": return "({a} << {(r1 >> 4) % 5})", r1
    if op == ">>": return "(({a} & 1023) >> {(r1 >> 4) % 5})", r1  // (only what isn\'t negative: see test_refusals)
    let b, r2 = random_expr(r1, depth - 1)
    let un = (r2 >> 8) % 6
    let e = if op == "//" or op == "%": "({a} {op} ({b} | 1))" else: "({a} {op} {b})"  // (never by 0)
    if un == 0: return "-{e}", r2
    if un == 1: return "~{e}", r2
    return e, r2

def write_diff(dir:string):
    var seed = 777
    for(40):  // (a file of 50 a time: one that fails here fails as one)
        var src = ""
        for(50):
            let e, r = random_expr(seed, 3)
            let f, r2 = random_expr(r, 2)
            seed = r2
            let cmp = [ "==", "~=", "<", "<=", ">", ">=" ]
            src += if r2 % 4 == 0: "print({e} {cmp[(r2 >> 4) % cmp.length]} {f})\n" else: "print({e}, {f})\n"
        given.push(src)
        given.push(run(src))
    for(given.length / 2) j:
        write_file("{dir}/{j}.lua", given[j * 2], 0, 1)
        write_file("{dir}/{j}.want", given[j * 2 + 1], 0, 1)

let diff_dir = find(command_line_arguments()) a: starts_with(a, "diff:")
if diff_dir >= 0: write_diff(substring(command_line_arguments()[diff_dir], 5, -1))

print "test_lua: {passes} passed, {fails} failed"
if fails: set_exit_code(1)
