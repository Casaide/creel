<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/creel-mark-dark.svg">
    <img src="docs/logo/creel-mark.svg" alt="" width="96">
  </picture>
</p>

<h1 align="center">Creel</h1>

An engine for classic-style real-time strategy games, written in [Lobster](https://github.com/aardappel/lobster).
It was built for Age of Anything and split out of it so other games can stand on it.

It's early. The engine runs a full game today, but it has only ever had one game on it, so expect rough edges and
changes without notice.

## What's in it

- **The sim** (`src/lib`): integers only, a fixed 20 Hz tick, driven only by commands, so it plays the same on every
  machine. Movement and flow fields, formations, fog, combat, economy, tech, sieges, walls, garrisons, trade, animals.
- **Bots** (`src/lib`): a reference AI that plays through the same commands a player does.
- **Packs** (`src/gen`): a game and its mods are folders of data in one format, merged in load order. Match setup from
  a plain table of unit types.
- **Voxel art** (`src/view`): units, buildings and props built from data or from `.vox` files, baked to sprites in
  8 facings.
- **Drawing** (`src/view`, `src/game`): the world (units, buildings, walls and gates, ruins, props), the ground, fog,
  effects, a sprite batcher, a widget layer, and the atmosphere pass (colour grade, haze, vignette, bloom, glow from
  fires, with moods per map).
- **Playing** (`src/game`): the camera, selection and orders, control groups, placing buildings and walls, the
  minimap.
- **Network** (`src/net`): lockstep over TCP, and finding games on the local network.
- **Sound** (`src/audio`, `src/game/audio.lobster`): an offline synth and the in-game player.

## Docs

- [`docs/settings.md`](docs/settings.md): the settings a game can change (the camera's angle, the ground, cliffs), kept
  up to date as they are added.
- [`docs/roadmap.md`](docs/roadmap.md): what is still to move into the engine.

## Using it

A game keeps Creel beside its own code, usually as a git submodule, and starts each program with:

```
import from "../creel/src"
```

That adds Creel's folder to Lobster's search path, so `import lib.world` and the rest find it. The game brings its
data, its main program, and the functions Creel calls into: the sim's hooks (`examples/plain/src/hooks/active.lobster`)
and the view's (`hooks/view.lobster`). The example's versions do nothing.

Creel needs the `master` branch of [this Lobster fork](https://github.com/Drache93/lobster), which is upstream Lobster
plus a few changes that are being offered upstream. `LOBSTER_VERSION` has the commit it was last tested with.

```
./check.sh    # Creel's modules compile with nothing from a game but the example's hooks
```

## Coming soon

- `creel new <game>`: a new game from a template that runs on the first try.
- `creel run`, `creel test`, `creel check`: one command over the tools that are separate scripts today.
- `creel voxel <file>`: open a voxel model or `.vox` file in a live preview, and write one back out.
- `creel pack`, `creel build`: zip a pack with its signature; release builds for Mac, Steam Deck, Android, Windows.
- The frame loop, and pad and touch play, as engine modules. The camera, world drawing, selection, orders, minimap
  and the kit a HUD is drawn with are here; the loop that runs them is still in Age of Anything's main program. A
  game's own panels (top bar, command panel, tech tree) stay in the game.
- A small test pack, so the engine's tests run here without a game.
- Docs: a tutorial, and a reference for the data files and hooks.

`docs/roadmap.md` has the longer list, including what's left of the lighting and atmosphere work.

## Licence

Apache 2.0. See `LICENSE` and `NOTICE`.

The code was written by Claude (Anthropic's AI), directed by Dominic.
