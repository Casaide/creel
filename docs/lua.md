# Lua for packs' rules

A pack (the game's own, or a mod) can carry rules as Lua: `data/hooks/*.lua`. Creel runs them with an interpreter of its
own (`src/lua/`), written in Lobster, so it needs nothing outside Creel and runs the same in every build. Steading's
town rules (homes, eating, doors on roads) are the worked example, in Age of Anything's `mods/steading/data/hooks/`.

## How a pack's Lua runs

- Its files run once as a match starts (and again when a save loads), in name order, in one environment per pack.
  That's when a pack reads its settings (`rules()`, `building_type(k)`), builds lookup tables and declares its state.
- Then the hooks it defines are called, pack by pack in load order. A hook a pack doesn't define costs nothing.
- **State that lasts lives in hook columns**, which the sim saves and hashes like its own: `unit_column(name)`,
  `building_column(name)` and `player_column(name)`, declared while the files load. After the load, the files' globals,
  their file-level locals and the tables they made are read-only: writing to one is an error. A call's own locals and
  tables are fine; they're dropped when it returns.
- An error, or going over a step budget, turns that pack's hooks off for the rest of the match, the same way on every
  machine, and the log says why. The budgets: 2,000,000 steps a call, 4,000,000 a tick for all of a pack's calls
  together, 10,000,000 for the load. A stopped pack is part of the match's state: it's saved and hashed, and stays
  stopped when the save loads. `lua_errors()` lists the stopped packs, for the game to show.
- The view asks two hooks too: `can_place` for the placement preview (through `view_can_place`) and `task_name` for
  the panel. Those calls run on one machine only, so they may only read, have a budget of 100,000 steps, and a failure
  there is logged and passed over (the hook answers as if the pack had none); it never stops the pack. `can_place` only
  reads from the sim as well.
- Limits that keep a bad pack from taking the game down with it: no string over 1 MB and no more than 16 MB of strings
  made in one call; code nested no deeper than 200 (in the parser and in the tree it makes); calls no deeper than 200,
  and their code no deeper than 4,000 all together. Each is an error in the pack, never a crash.
- The files are part of the pack's signature, so a changed rule is a different pack in network play and saves. A file
  that doesn't read (a syntax error, a float, a refused word) refuses the mod when it loads, with the file and line.

## The language

Lua 5.4, cut to what lockstep needs:

- **Integers only**, 61 bits signed. Float literals, `/` and `^` are refused: use `//` (floor division) and `%`.
  Bitwise `& | ~ << >>` work, but a negative number shifted right is an error (Lua fills from the top with 0 bits,
  which takes 64). Literals must be under 2^60.
- Values: nil, booleans, integers, strings, tables, functions. Closures, multiple returns, method calls (`t:m()`),
  table constructors, `#`, `..`, all the loops, `break`.
- Not here: varargs (`...`), `goto`, metatables, coroutines, `<const>`/`<close>`.
- `pairs` goes in insertion order (array part first), the same everywhere. `#` of a table with holes is a border, as
  Lua's is, but not always the one Lua picks.
- The library: `print`, `type`, `tostring`, `tonumber`, `error`, `assert`, `select`, `ipairs`, `pairs`, `next`,
  `math.min/max/abs`, `string.sub/len/byte/upper/lower/rep/find` (plain text, no patterns), `string.format` (`%d %s %%`),
  string methods (`s:upper()`),
  `table.insert/remove/sort/concat` (`sort` is stable). Nothing else: no `io`, `os`, `require`, `load`, `debug`.

## Hooks a pack can define

| Function | When | Returns |
|---|---|---|
| `on_tick()` | once a tick, after the economy's steps | |
| `on_unit_tick(i)` | each tick, for each unit whose type has `"tick": true` | |
| `can_place(p, k, cx, cy, sx, sy)` | player `p` places building type `k` at `cx, cy` (size `sx, sy`) | false refuses |
| `can_make(b)` | building slot `b` is about to start a round of its recipe (its inputs are in) | false holds it back this tick |
| `on_hit(by, target, damage)` | a blow is about to land on unit slot `target` from unit id `by` | the damage (the `hit` event gives what it returns) |
| `on_hurt(target, by)` | after the tick's blows, for each unit hurt | |
| `on_death(i, killer)` | unit slot `i` is dying (animals too: `t_animal(u_kind(i))` tells them apart) | |
| `on_order(code, p, ids, x, y)` | an order with a code from `HOOK_ORDER_BASE` up | |
| `ai_train_score(p, slot, k, score)` | a bot weighs training type `k` | the score |
| `delivery_level(b, r, level, kind)` | the delivery market (rules economy `deliveries`, #191) weighs a delivery of good `r`: kind 0 a want of building slot `b`, 1 a full workshop `b`'s goods out, 2 workshop `b`'s spare goods to a store | its level: higher goes first |
| `task_name(i)` | the panel names what unit `i` is doing; may only read | a string, `""` for none |
| `invariants()` | after a tick, when the testkit or the MCP checks the invariants (`src/testkit/invariants.lobster`); may only read, on the view's budget | `nil` while the pack's rules hold, else a string saying which broke and where. The engine's `stuck` check is on when the rules say how long a walker may be held up: `"invariants": {"stuck_limit": <ticks>}` |

## The API

The sim's own names, with its 0-based slots: `u_task(i)` is unit slot `i`'s task, `b_kind(b)` building slot `b`'s type,
`b_hold(b, r)` what it holds of resource `r`. Ids (`u_id`, `b_id`) are stable; slots change as units come and go, so keep
ids in columns. Every function checks its arguments: a bad one is an error in the pack.

- **Units:** `unit_count`, `u_id`, `u_x`, `u_y`, `u_kind`, `u_owner`, `u_task`, `u_target`, `u_carry`, `u_carry_kind`,
  `u_moving`, `u_stuck`, `u_work`, `u_hp`, `u_orders` (how many queued), `unit_index(id)`; `set_u_task`,
  `set_u_target`, `set_u_work`, `set_u_stuck`, `set_u_moving`; `hurt(i, n)` takes n hit points from unit i (its hit
  points left): at none it dies in that tick's blows as a blow would kill it, with `on_death(i, 0)` (no killer), so a
  rule can starve, poison or drop a unit.
- **Buildings:** `building_count`, `b_id`, `b_kind`, `b_owner`, `b_done`, `b_progress`, `b_hp`, `b_hold(b, r)`,
  `b_want(b, r)`, `b_coming(b, r)`, `offered(b, r)`, `b_is_site`, `site_permille`, `site_phase` (0 levelling, 1 waiting for goods, 2 building, 3 standing), `build_stage` (the stage of its type's `"stages"` it is at, from 0), `building_index(id)`,
  `building_rect(b)` (four values: x0, y0, x1, y1 in sim units, `TILE` a tile, both edges inside it), `entry_rect(b)` (where a unit stands to reach it: its door tile with economy `doors`, else the same as building_rect; #133), `mid_dist2(b, x, y)`.
- **Types:** `building_type_count`, `building_type(k)` (its buildings.json entry, as a table; the entry has no id of its own), `building_type_index(name)` (the type whose buildings.json key is `name`, as `place()` takes it, or -1), `bt_road`, `bt_drag` (laid a cell at a time: a road or a field; #126), `bt_line`,
  `bt_ladder`, `bt_store`, `bt_hold(k, r)`, `bt_build_ticks`; `unit_type_count`, `t_pop`, `t_slot`, `t_worker`,
  `t_animal`.
- **Players and resources:** `player_count`, `pop`, `pop_cap`, `set_pop`, `worker_type(p)`, `resource_count`,
  `resource_index(name)`.
- **Goods, by economy.** In a pooled economy (each player keeps its goods in one pool, the default) `stock(p, r)` reads
  player p's goods of r, and `stock_take(p, r, n)` and `stock_put(p, r, n)` change them: how many moved, with a
  `stock_taken` or `stock_put` event (a the player, c the good, n how many; #222). In a stocked economy (rules economy
  `model: "stocked"`: goods are in buildings' holds, sites ask for them and carriers fetch them) `stock` reads the sum of
  the player's stores, and the goods move by building: `b_hold`, `hold_take`, `hold_put`, `want`. Each function
  refuses the other economy's goods with an error that says so.
- **The map:** `W`, `H`, `TILE`, `cell_of(x, y)`, `road(c)`, `occupied(c)`, `amount(c)`, `res_at(c)`,
  `nearest_resource(x, y, kind, i, farms, roomy_only, seen)`, `terrain_at(c)`, `terrain_type(id)` (-1 if there's none),
  `plant(c, t)` (terrain t, one that `grows` in terrain.json, on free walkable ground at c; it grows on by itself,
  and through a save; whether it was planted; #109).
- **The economy and orders:** `stocked()`, `tick()`, `b_making(b)` (ticks left in a recipe's round, 0 if none), `want(b, r, n)`, `hold_take(b, r, n)`, `hold_put(b, r, n)` (into b, as much as it has room for; how many went in, #142), `trained(b, k)` (a new
  unit at its door: its slot), `start_gather(i, c, kind)`, `start_build(i, id)`, `approach_building(i, b)`, `approach_cell(i, c)`,
  `clear_task(i)`, `in_reach(i, x0, y0, x1, y1)`, `fits(p, k, cx, cy)` (whether the ground lets p lay type k there, the packs' own rules aside),
  `lay_foundation(p, k, cx, cy)` (a site, paid or asking its goods, where `fits` and its type is open to p: its id, or
  0; #105).
- **Deliveries (#191):** `delivery_count()` and `delivery_get(j, field)` read the deliveries under way (field 0 the
  carrier's id, 1 from, 2 to (building ids), 3 the good, 4 how many, 5 its phase: 0 fetching, 1 bringing). Each one
  starts with a `sent` event. What's still asked for is `b_want(b, r)`, what's on its way `b_coming(b, r)`, and what a
  building offers `offered(b, r)`. What goes first is the rules' (economy `deliveries`: `src/lib/carry.lobster`, "the
  delivery market") and `delivery_level`'s.
- **Sight, secrets, healing and holding still (#239):** `reveal(p, x, y, r, ticks)` lends player p's team sight of `r`
  tiles (0 to 32) round `x, y` (sim units) for `ticks`, stamped with its fog as a unit's sight is. `hide_cell(c)` makes
  cell c a secret no player knows (again, if it was one), `discover_cell(p, c)` gives it to player p and its team, and
  `cell_known(p, c)` asks: a resource on a cell its side doesn't know isn't drawn for it, isn't gathered (a gather order
  there is a walk), and `nearest_resource` and the bots pass over it. `heal(i, n)` gives unit i back up to n hit points,
  never past its type's (its hit points then). `take_cell(c, n)` takes up to n of cell c's resource as gathering
  takes it (the last turns the cell into its depleted terrain, #245); how many it took. `freeze(i, ticks)` holds unit i still, no moves and no blows, for `ticks`
  (the longer of two); `frozen(i)` is how many are left. `t_tag(k, name)` says whether type k's line carries a tag (its
  row in the race's table), `t_ranged(k)` whether it shoots.
- **Events (#187):** `emit(code, a, b, c, n)` puts the pack's own event in this tick's (kind 100 + code, code 0 to 899; the
  sim only), `event_count()` and `event_get(i, field)` read this tick's so far (field 0 kind, 1 a, 2 b, 3 c, 4 n, 5 x,
  6 y). The engine's kinds are `EV_*` in `src/lib/state.lobster`; `hold_take` and `hold_put` add `taken` and `put` events (a 0, b the building's id, c the good, n how many).
  Events aren't state: they're never saved or hashed.
  How a pack's own events look is its rules' `"event_fx"` (#243): per code, `"at"` (`a` or `b`: that unit's feet; `bc`: b and c as
  a point in sim units), `"ring"` (tiles a ring grows to, on the ground), `"colour"`, `"text"` (floating up; `{n}` is the
  event's n) and `"to"` (`owner`: unit a's owner sees it; `seen`: whoever sees the spot). The view draws them; the sim never.
- **State:** `unit_column`, `building_column`, `player_column` (at load); `unit_get(col, i)`, `unit_set(col, i, v)`,
  `building_get`, `building_set`, `player_get`, `player_set`.
- **Events by name:** `event_kind(name)` is the kind of an engine event (`pick`, `drop`, `built` ...), as `event_get`'s
  field 0 gives it. A pack's Lua always has this tick's events: they're kept whenever a pack has Lua.
- **Data:** `rules()` (the match's rules, as a table; a fraction is nil).
- **Constants:** `TICK_HZ`, `T_NONE`, `GATHER`, `T_RETURN`, `BUILD`, `T_CARRY`, `GIVE_UP`, `HOOK_ORDER_BASE`. A pack
  that makes up a task of its own uses a code from 100 up.

New API functions are added in `src/lua/api.lobster` (`LA_NAMES` and the switch in `lua_api`), when a rule needs one.

## Rules in phases: `process{}`

Most rules of a town are a unit (or a building) going through steps: walk to the inn, eat, wait for the next dish, go
back to work. Creel loads a small library into every pack's Lua before its own files (`src/lua/process.lobster`), and
`process{}` declares such a rule as named phases. Declare it as the files load, call its `tick()` from `on_tick`:

```lua
local meal = process{ name = "meal", leave = function(i) back_to_work(i) end, phases = {
  { "walk", enter = go_to_inn, done = at_inn, next = "eat" },
  { "eat", enter = sit_down, ticks = 3 * TICK_HZ, next = function(i) if still_hungry(i) then return "wait" end end },
  { "wait", event = "drop", match = function(i, a, b, c, n) return b == inn_of(i) end, ticks = 10 * TICK_HZ, timeout = "walk" },
} }

function on_tick() meal.tick() end
function task_name(i) return meal.phase(i) or "" end
```

A phase is a table: its name first, then any of these.

| Field | What it does |
| --- | --- |
| `enter(i)` | called as `i` comes into the phase |
| `done(i)` | checked each tick: true goes on to `next` |
| `event`, `match(i, a, b, c, n)` | an event of this kind this tick (a name, as `event_kind` takes, or a pack's own code, as `emit` takes) for which `match` is true (or any, without `match`) goes on to `next` |
| `ticks` | a timer: once it runs out, a phase with nothing else to wait for goes on to `next`, and one waiting on `done` or an event goes to `timeout` |
| `next`, `timeout` | the phase after: a name, or `function(i)` that returns one; `nil` (or none) ends the process |

The process's own fields: `name` (its columns are `<name>_phase` and `<name>_at`, so its state is saved, loaded and
hashed like any hook column), `on` (`"unit"`, the default, or `"building"`), `phases`, and `leave(i)`, called when it
ends (and when it's stopped). What it gives back:

| Function | What it does |
| --- | --- |
| `start(i)`, `go(i, name)` | puts `i` in the first phase, or in the one named (`nil` ends it) |
| `stop(i)` | ends it now, if `i` is in it |
| `phase(i)` | the phase `i` is in, by name, or `nil` |
| `left(i)` | the ticks left on its phase's timer (0 for none) |
| `step(i)`, `tick()` | one tick for `i`, or for every unit (building) in it: an event first, then `done`, then the timer; at most one move a tick |

A declaration that's wrong (a phase going on to one that isn't there, two of a name, an event kind that isn't one) is
the pack's error as it loads. `examples/plain/src/test_lua.lobster`'s `test_process` has one rule written by hand and
as a process, doing the same tick for tick.

## A pack's own tests

A pack can carry tests of its rules: `data/tests/*.lua`. They're checked when the pack loads, like its hooks, but never
run in a match, and they aren't in its signature (a pack with new tests plays the same). Each global
`function test_<name>()` is a test. It runs in a fresh match the game makes, with the pack's rules loaded and every
invariant (`src/testkit/invariants.lobster`) checked on every tick.

A test runs in phases: `test_<name>`, then `test_<name>_2`, `_3` and on, as long as there are more. A phase sets things
up or checks them, then says what to run before the next one. Besides the whole API, a phase may call:

| Function | What it does |
| --- | --- |
| `place(p, type, cx, cy, built)` | Building type `type` (its id) for player `p` with its corner on cell `cx, cy`, where it fits: a site asking for its goods, or with `built` finished. Its id, or 0 if it doesn't fit. |
| `give(b, r, n)` | Puts `n` of resource `r` into building slot `b`, as far as it has room. How many went in. |
| `spawn(p, slot, x, y)` | A unit of player `p`'s type in roster slot `slot` (`worker`, `spear` ...) at `x, y` in sim units. Its slot. |
| `wait(n)` | After this phase, run `n` ticks. |
| `wait_for(kind, max, a, b, c)` | After this phase, run until an event of this kind happens with these `a, b, c` (`nil` for any), at most `max` ticks. The kind is a name (`pick`, `drop`, `gather`, `made`, `used`, `built`, `trained`, `lost`, `taken`, `put` ...) or a pack's own code, as `emit` takes. |
| `expect(ok, what)` | A check: the test fails with `what` if `ok` isn't true. |
| `keep(name, n)`, `kept(name)` | An integer kept for a later phase (a phase's locals are gone when it ends). |

A test can run with rules of its own: a global table `test_<name>_rules` is merged into the match's rules for that
test only (objects merge, as a mod's data does), and the packs load with them, so `rules()` gives the merged ones. Use
it to reach a row the default numbers never reach (a feast longer than a minute). It changes what the packs read; the
engine's own settings come from the match's start.

A test fails on an `expect` that doesn't hold, an error, an invariant that breaks (with the tick and what broke), or an
event that doesn't come in time. These functions are refused to a pack's rules: only its tests may call them.

The tests are a pack of their own, with their own Lua: a test can't call the rules' functions or read their locals. It
reads their state the way the sim keeps it: a column declared by the same name (`unit_column("meal_phase")`) is the
same column, and the API reads the rest. In a phase, and in `invariants()`, `tick()` is how many ticks have run: the
tick that just ran is `tick() - 1`.

```lua
-- data/tests/roads.lua: a road cell takes one stone, carried to it by a carrier, then it's laid
function test_road_takes_one_stone()
  keep("road", place(0, "road", 14, 12, false))
  wait_for("drop", 2400, nil, kept("road"), resource_index("stone"))
end

function test_road_takes_one_stone_2()
  wait_for("built", 1200, nil, kept("road"))
end
```

A game runs them with `pack_tests_of(id, make_world, one_tick)` (`src/testkit/pack_tests.lobster`): `make_world` makes
a fresh match, `one_tick` runs one tick the game's way. The MCP's `creel_pack_tests` does the same with `creel_start`'s
args.

## A game's side

A game chains each of its hook points (`hooks/active.lobster`) on to `lua_<hook>` after its own rules, and calls
`lua_declare()` from `hook_declare`. `examples/plain/src/hooks/active.lobster` does only that. A program that reads
packs imports `lua.parse` before `gen.mods`; one that runs the sim imports `lua.lua` and `lua.api` after `gen.start`.

## Cost

The interpreter walks the syntax tree: roughly 100 ns a simple statement and 300 ns an API call in a JIT build. Keep
per-unit work in `on_tick` small, and look at things once a second (`tick() % 20 == 0`) where a rule allows.
`examples/plain/src/test_lua.lobster` is the reference for what works and what is refused: it also mutates its own
snippets into 20,000 broken programs that must load or fail with an error. `./lua_diff.sh` runs its programs and 2,000
random integer expressions in `lua5.4` too, and they must print the same but for the differences above (`check.sh`
runs it when `lua5.4` is installed).
