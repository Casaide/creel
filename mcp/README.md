# Creel's MCP server

An agent working on a game built on Creel can run that game headless while it works: start a match, step it, give
orders, read every unit and building, check the hash, save and load, take a picture and run the game's tests. It's the
same sim that the game and its tests run, so what the agent sees is what the game does ([#196](https://github.com/Casaide/creel/issues/196)).

There are two halves:

- **`src/mcp/serve.lobster`** is the sim side. The game writes a small Lobster program that imports its sim, defines four
  hooks and calls `mcp_serve()`. It then answers one JSON request a line on stdin, and every reply starts with `@mcp `.
  It knows only what every game on Creel has: ticks, orders, units, buildings, players, cells and the hash.
- **`mcp/creel-mcp.js`** speaks MCP (JSON-RPC over stdio) to the agent and drives the sim side. It's plain Node 18 or
  newer, with no packages.

## A game's side

```lobster
import <the game's sim modules>
import mcp.serve

def mcp_start(args:JV) -> string:      // a fresh match from the agent's args: "" or why not
def mcp_step():                        // one tick, the game's way (its bots, then the sim's step)
def mcp_save(path:string) -> string:   // "" or why not
def mcp_load(path:string) -> string:

mcp_serve()
```

`examples/plain/src/mcp_server.lobster` is the smallest one. Then the game adds a `creel-mcp.json`:

```json
{
  "name": "my-game",
  "lobster": "~/Dev/lobster/bin/lobster",
  "cwd": "src",
  "server": "mcp_server.lobster",
  "start_help": "args: {\"map\": ..., \"seed\": ...}",
  "tests": { "sim": ["{lobster}", "test_sim.lobster"] },
  "capture": ["{lobster}", "game.lobster", "mods:{start.mods}", "loadsave:{save}", "shot:{png}", "at:3"],
  "timeout_s": 600
}
```

It also adds an `.mcp.json`, so that Claude Code in the game's folder offers the server:

```json
{ "mcpServers": { "my-game": { "command": "node", "args": ["creel/mcp/creel-mcp.js", "creel-mcp.json"] } } }
```

`LOBSTER` in the environment overrides `lobster`. Commands can use `{lobster}`, `{save}`, `{png}` and `{scratch}`. They can
also use `{start.<key>}`, which is that arg of the last `creel_start`, with a list joined by commas. An argument whose key
is missing is left out.

## Tools

| Tool | What it does |
| --- | --- |
| `creel_start` | Starts a fresh match. The args are the game's own; `start_help` says what they are. |
| `creel_step` | Runs the sim for this many ticks (20 a second, up to an hour per call), then gives the tick and the hash. With `invariants`, it checks every tick and stops on the first that breaks. |
| `creel_events` | What happened since the start: goods picked up, dropped, gathered, made, used, lost; built, trained, deaths; packs' own. Filtered by kind, unit, building, resource, tick. `creel_step`'s `until` stops on one. A pack's own events show as `pack:<code>`, and a filter takes that name or `100 + code`. |
| `creel_invariants` | Checks the invariants now: the engine's and the packs' own (`src/testkit/invariants.lobster`). |
| `creel_pack_tests` | Runs a pack's own tests (`data/tests/*.lua`, [docs/lua.md](../docs/lua.md#a-packs-own-tests)), each in a fresh match from the start args, with every invariant checked each tick. It gives a line a test, `ok` or `FAIL` and why. |
| `creel_state` | Gives the tick, the hash and whether a match is running. |
| `creel_names` | Gives unit types, building types, resources and order names by index, plus the tile size and the map size. |
| `creel_units`, `creel_buildings` | Give the state of units or buildings, filtered by ids, owner, kind or a rectangle. A unit on a pack's own task has its `task_name`, as the panel says it. |
| `creel_players`, `creel_cell` | Give each player's population and stock, or one cell's road, building and resource. |
| `creel_order` | Gives a player's order. Like any player's order, it runs at the start of the turn after next. |
| `creel_save`, `creel_load` | Save or load a match by name. |
| `creel_capture` | Takes a picture of the match as it is now. Only offered when the game sets `capture`. |
| `creel_run_tests` | Runs one of the suites the game names under `tests`. |
| `creel_restart` | Starts a fresh sim process, after a code or data change. |

## The runner

`mcp/creel-run.js` drives the same sim side from a script instead of an agent, for scripts and CI (#195). It needs no
window or GPU, and prints one JSON document:

```
node creel/mcp/creel-run.js creel-mcp.json run.json [out.json]
```

```json
{ "start": { "mods": ["steading"] }, "hash_every": 30, "invariants": true,
  "steps": [ { "step": 1200 }, { "order": { "player": 0, "command": "move", "ids": [3], "a": 5000, "b": 4000 } },
             { "step": 600, "until": { "kinds": ["built"] } }, { "buildings": { "owner": 0 } }, { "events": { "kinds": ["drop"] } },
             { "save": "noon" } ] }
```

- **`start`** is the game's start args, as `creel_start` takes them. With **`load`** too, the run resumes that save instead:
  it starts a match from the args first, then loads the save into it.
- Each step does one thing:
  - **`step`** runs that many ticks. With `until`, it stops on the first event like it, as `creel_step` does.
  - **`order`**, **`units`**, **`buildings`**, **`players`**, **`cell`**, **`events`**, **`invariants`**, **`state`** and **`names`** take the same fields as their tools.
  - **`save`** and **`load`** take a name.
- **`hash_every`** (default 30) puts `[tick, hash]` in `hashes` every that many ticks.
- **`invariants`** (default true) checks every invariant on every tick.

The run stops at the first step that fails, the first invariant that breaks, or an `until` that never came. The JSON
holds `ok`, `start`, each step's result, `hashes` and the last `tick` and `hash`; when a run stops, it also holds
`error` and `failed_step`. The exit code is 0 only when every step held. A run is deterministic: the same script gives
the same JSON on any machine, so two machines' outputs can be diffed.

## What it can't do

It's locked the way the sim is. An agent can only act through a player's orders, so it can't write the sim's state. It
can only run the commands the game's config names. Saves and pictures go in one scratch folder, by name only. Calls run
one at a time and in order, so the same calls from the same start give the same hashes.

## Talking to it without an MCP client

`creel-mcp.js` reads one JSON-RPC message a line on stdin and answers one a line on stdout: `initialize`, then
`tools/list` and `tools/call` with `{"name": ..., "arguments": ...}`. A shell script can drive it by writing those lines;
`mcp/test/test.js` does it from Node. For a scripted run, the runner (above) is simpler.

`mcp/test/test.js` drives the server as an agent would. `check.sh` runs it when there's a Node.
