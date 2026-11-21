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
| `on_hit(by, target, damage)` | a blow is about to land on unit slot `target` from unit id `by` | the damage |
| `on_hurt(target, by)` | after the tick's blows, for each unit hurt | |
| `on_death(i, killer)` | unit slot `i` is dying | |
| `on_order(code, p, ids, x, y)` | an order with a code from `HOOK_ORDER_BASE` up | |
| `ai_train_score(p, slot, k, score)` | a bot weighs training type `k` | the score |
| `task_name(i)` | the panel names what unit `i` is doing; may only read | a string, `""` for none |

## The API

The sim's own names, with its 0-based slots: `u_task(i)` is unit slot `i`'s task, `b_kind(b)` building slot `b`'s type,
`b_hold(b, r)` what it holds of resource `r`. Ids (`u_id`, `b_id`) are stable; slots change as units come and go, so keep
ids in columns. Every function checks its arguments: a bad one is an error in the pack.

- **Units:** `unit_count`, `u_id`, `u_x`, `u_y`, `u_kind`, `u_owner`, `u_task`, `u_target`, `u_carry`, `u_carry_kind`,
  `u_moving`, `u_stuck`, `u_work`, `u_hp`, `u_orders` (how many queued), `unit_index(id)`; `set_u_task`,
  `set_u_target`, `set_u_work`, `set_u_stuck`, `set_u_moving`.
- **Buildings:** `building_count`, `b_id`, `b_kind`, `b_owner`, `b_done`, `b_progress`, `b_hp`, `b_hold(b, r)`,
  `b_want(b, r)`, `b_coming(b, r)`, `offered(b, r)`, `b_is_site`, `site_permille`, `building_index(id)`,
  `building_rect(b)` (four values), `entry_rect(b)` (where a unit stands to reach it: its door tile with economy `doors`, else the same as building_rect; #133), `mid_dist2(b, x, y)`.
- **Types:** `building_type_count`, `building_type(k)` (its buildings.json entry, as a table), `bt_road`, `bt_drag` (laid a cell at a time: a road or a field; #126), `bt_line`,
  `bt_ladder`, `bt_store`, `bt_hold(k, r)`, `bt_build_ticks`; `unit_type_count`, `t_pop`, `t_slot`, `t_worker`,
  `t_animal`.
- **Players and resources:** `player_count`, `pop`, `pop_cap`, `set_pop`, `worker_type(p)`, `resource_count`,
  `resource_index(name)`.
- **The map:** `W`, `H`, `TILE`, `cell_of(x, y)`, `road(c)`, `occupied(c)`, `amount(c)`, `res_at(c)`,
  `nearest_resource(x, y, kind, i, farms, roomy_only, seen)`, `terrain_at(c)`, `terrain_type(id)` (-1 if there's none),
  `plant(c, t)` (terrain t, one that `grows` in terrain.json, on free walkable ground at c; it grows on by itself,
  and through a save; whether it was planted; #109).
- **The economy and orders:** `stocked()`, `tick()`, `b_making(b)` (ticks left in a recipe's round, 0 if none), `want(b, r, n)`, `hold_take(b, r, n)`, `trained(b, k)` (a new
  unit at its door: its slot), `start_gather(i, c, kind)`, `start_build(i, id)`, `approach_building(i, b)`, `approach_cell(i, c)`,
  `clear_task(i)`, `in_reach(i, x0, y0, x1, y1)`, `fits(p, k, cx, cy)` (whether the ground lets p lay type k there, the packs' own rules aside),
  `lay_foundation(p, k, cx, cy)` (a site, paid or asking its goods, where `fits` and its type is open to p: its id, or
  0; #105).
- **State:** `unit_column`, `building_column`, `player_column` (at load); `unit_get(col, i)`, `unit_set(col, i, v)`,
  `building_get`, `building_set`, `player_get`, `player_set`.
- **Data:** `rules()` (the match's rules, as a table; a fraction is nil).
- **Constants:** `TICK_HZ`, `T_NONE`, `GATHER`, `T_RETURN`, `BUILD`, `T_CARRY`, `GIVE_UP`, `HOOK_ORDER_BASE`. A pack
  that makes up a task of its own uses a code from 100 up.

New API functions are added in `src/lua/api.lobster` (`LA_NAMES` and the switch in `lua_api`), when a rule needs one.

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
