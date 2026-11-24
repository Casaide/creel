// ------------------------------------------------------------------ process(): rules in named phases, in Lua (#194)
// A small Lua library every pack's Lua gets, loaded before its own files (lua/api's lua_declare): `process{...}`
// declares a multi-step rule (a meal, a rest, a job) as named phases, each with what it does on entering and what it
// waits for (a check, a number of ticks, an event), and the phase after. Its state is two hook columns (<name>_phase,
// <name>_at), so it saves, loads and hashes like any. docs/lua.md says how to use it; examples/plain's test_lua checks it.

let LUA_PROCESS_FILE = "creel/process.lua"

let LUA_PROCESS = """
function process(def)
  assert(type(def) == "table" and type(def.name) == "string", "process{}: it needs a name")
  local pname = "process " .. def.name
  assert(type(def.phases) == "table" and #def.phases > 0, pname .. ": it needs phases")
  local on_b = def.on == "building"
  assert(def.on == nil or on_b or def.on == "unit", pname .. ": on is unit or building")
  local col_phase, col_at
  if on_b then
    col_phase = building_column(def.name .. "_phase")
    col_at = building_column(def.name .. "_at")
  else
    col_phase = unit_column(def.name .. "_phase")
    col_at = unit_column(def.name .. "_at")
  end
  local function get(c, i) if on_b then return building_get(c, i) end return unit_get(c, i) end
  local function set(c, i, v) if on_b then building_set(c, i, v) else unit_set(c, i, v) end end
  local function count() if on_b then return building_count() end return unit_count() end

  local index, list = {}, {}
  for j, ph in ipairs(def.phases) do
    local name = ph[1]
    assert(type(name) == "string", pname .. ": phase " .. tostring(j) .. " has no name")
    assert(index[name] == nil, pname .. ": two phases are called " .. name)
    assert(ph.ticks == nil or (type(ph.ticks) == "number" and ph.ticks > 0), pname .. ": " .. name .. "s ticks must be over 0")
    local kind = nil
    if type(ph.event) == "number" then
      assert(ph.event >= 0 and ph.event < 900, pname .. ": " .. name .. "s event code must be 0 to 899")
      kind = 100 + ph.event
    elseif ph.event ~= nil then
      kind = event_kind(ph.event)
    end
    index[name] = j
    list[j] = { name = name, enter = ph.enter, done = ph.done, ticks = ph.ticks, kind = kind, match = ph.match,
                next = ph.next, timeout = ph.timeout, waits = kind ~= nil or ph.done ~= nil }
  end
  for j, ph in ipairs(list) do
    assert(type(ph.next) ~= "string" or index[ph.next] ~= nil, pname .. ": " .. ph.name .. " goes on to " .. tostring(ph.next) .. ", which is no phase")
    assert(type(ph.timeout) ~= "string" or index[ph.timeout] ~= nil, pname .. ": " .. ph.name .. " times out to " .. tostring(ph.timeout) .. ", which is no phase")
  end

  local function go(i, name)
    if name == nil then
      set(col_phase, i, 0)
      set(col_at, i, 0)
      if def.leave then def.leave(i) end
      return
    end
    local j = index[name]
    if j == nil then error(pname .. ": no phase " .. tostring(name)) end
    local ph = list[j]
    set(col_phase, i, j)
    if ph.ticks then set(col_at, i, tick() + ph.ticks) else set(col_at, i, 0) end
    if ph.enter then ph.enter(i) end
  end
  local function then_(i, to)
    if type(to) == "function" then return to(i) end
    return to
  end

  local p = {}
  function p.start(i) go(i, list[1].name) end
  function p.go(i, name) go(i, name) end
  function p.stop(i) if get(col_phase, i) ~= 0 then go(i, nil) end end
  function p.phase(i)
    local j = get(col_phase, i)
    if j == 0 then return nil end
    return list[j].name
  end
  function p.left(i)
    local j = get(col_phase, i)
    if j == 0 or not list[j].ticks then return 0 end
    return math.max(0, get(col_at, i) - tick())
  end
  function p.step(i)
    local j = get(col_phase, i)
    if j == 0 then return end
    local ph = list[j]
    if ph.kind then
      for e = 0, event_count() - 1 do
        if event_get(e, 0) == ph.kind and (not ph.match or ph.match(i, event_get(e, 1), event_get(e, 2), event_get(e, 3), event_get(e, 4))) then
          go(i, then_(i, ph.next))
          return
        end
      end
    end
    if ph.done and ph.done(i) then
      go(i, then_(i, ph.next))
    elseif ph.ticks and tick() >= get(col_at, i) then
      if ph.waits then go(i, then_(i, ph.timeout)) else go(i, then_(i, ph.next)) end
    end
  end
  function p.tick()
    for i = 0, count() - 1 do p.step(i) end
  end
  return p
end
"""
