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
| `creel_step` | Runs the sim for this many ticks (20 a second, up to an hour per call), then gives the tick and the hash. |
| `creel_state` | Gives the tick, the hash and whether a match is running. |
| `creel_names` | Gives unit types, building types, resources and order names by index, plus the tile size and the map size. |
| `creel_units`, `creel_buildings` | Give the state of units or buildings, filtered by ids, owner, kind or a rectangle. |
| `creel_players`, `creel_cell` | Give each player's population and stock, or one cell's road, building and resource. |
| `creel_order` | Gives a player's order. Like any player's order, it runs at the start of the turn after next. |
| `creel_save`, `creel_load` | Save or load a match by name. |
| `creel_capture` | Takes a picture of the match as it is now. Only offered when the game sets `capture`. |
| `creel_run_tests` | Runs one of the suites the game names under `tests`. |
| `creel_restart` | Starts a fresh sim process, after a code or data change. |

## What it can't do

It's locked the way the sim is. An agent can only act through a player's orders, so it can't write the sim's state. It
can only run the commands the game's config names. Saves and pictures go in one scratch folder, by name only. Calls run
one at a time and in order, so the same calls from the same start give the same hashes.

## Coming next

As the engine work lands, each piece adds its tool here: invariants ([#186](https://github.com/Casaide/creel/issues/186)),
the event log and stepping until an event ([#187](https://github.com/Casaide/creel/issues/187)), the draw probe
([#188](https://github.com/Casaide/creel/issues/188)) and packs' own Lua tests ([#190](https://github.com/Casaide/creel/issues/190)).

`mcp/test/test.js` drives the server as an agent would. `check.sh` runs it when there's a Node.
