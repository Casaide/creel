# Roadmap

What's planned, roughly in order within each list. Nothing here has a date.

## Lighting and atmosphere

Done: one full-screen pass over the world (`src/view/atmosphere.lobster`) with a colour grade (exposure, contrast,
saturation, tinted shadows and highlights), haze that thickens up the screen, a vignette, a small bloom, and glow from
light sources such as fires. A mood is a set of those numbers in a pack's `atmosphere.json`; each map picks one. The UI
is drawn after the pass, ungraded.

To do:

- [ ] **A sun per map.** Units and props are baked with one fixed sun and one ground shadow per facing. Give each
  map or mood its sun direction and height, with longer, softer shadows for low light.
- [ ] **God rays and cloud shadows.** A moving overlay in the pass: slow cloud shadows across the ground, and shafts
  of light where the mood asks for them.
- [ ] **Fog with depth.** Haze today depends only on height up the screen. Layered fog that sits in low ground and
  between trees, and drifts.
- [ ] **Warm light sources that light things.** Fires and torches glow today but don't light the units and ground
  near them. Night and dusk moods need that.
- [ ] **Time of day inside a match**: a mood that moves between two others over the match.
- [ ] **The pass at a lower size** as an option, for slower machines. The cost today is about 1 ms a frame at
  3024 x 1834, nearly all of it the world texture and the full-size composite, not the bloom.
- [ ] **Steam Deck check.** The pass has never been measured there.
- [ ] **Height and water**: cliffs and raised ground that catch the light, rivers with reflections. The costly part,
  mostly map work.
- [ ] **Painterly trees and ground cover**: fuller canopies, layered undergrowth, ground textures that blend. Art
  work more than engine work, but the bakers need to carry it.

Rules that came out of the first pass: no mood may look flat and dead (flat is only for when the pass is off for
speed), and too much warm haze with a strong vignette turns team colours muddy in the corners.

## The split

Creel was one tree with Age of Anything until 2026-11-10. What moved first is every module that compiles without the
game. Still to come:

- [x] The camera, world drawing, selection, orders and minimap (`game/world_view`, `world_draw`, `controls`,
  `voxel_units`). The game's share comes in through the functions in `examples/plain/src/hooks/view.lobster`; their
  names are still the ones Age of Anything used and will change as a second game shows what they should be.
- [ ] The frame loop and the options every game wants (captures, recording, the frame budget, watch, speed). Until it
  moves, a new game copies that part of Age of Anything's main program.
- [x] The panels (`game/panel`, `topbar`, `techtree`, `techtree_page`), pad and touch play (`game/pad`, `touch`), the
  cursors and research in words (`gen/effect_words`). They read `su_races` (per player, what the game made it from)
  for a side's name and family, and still carry one game's ideas (crests, age badges, a wonder clock).
- [ ] Names in the moved code that are a game's: the hub is still looked up as `town_center` in one capture tool.
- [ ] Saving and loading: the code is generated from the sim's globals plus the game's. The generator moves here.
- [ ] A small test pack (a flat map, a worker, a spear, a hub, a farm), and the engine's tests running on it here:
  determinism, saves, lockstep, pathing, movement, the frame budget.
- [ ] Folder names that say what they hold (`lib` is the sim, `gen` is packs and setup, `game` is drawing and UI).

## The `creel` command

- [ ] `creel` as one script over the tools that exist: `run`, `check`, `test`, `build`, `pack`.
- [ ] `creel new <game>` from a template on the test pack.
- [ ] `creel voxel`: a live preview window for voxel bodies and `.vox` files that reloads on save, and export.
- [ ] Errors for bad data with file and line, and JSON Schemas for the data files.
- [ ] A dev overlay, command logs and replays (`creel replay`).
- [ ] Data reload, then hook reload, while the game runs.
- [ ] A tutorial and reference docs.

## Mods and hooks

- [ ] Hook mods in sandboxed Lua, with step budgets and deterministic maths.
- [ ] More hook points, found from real needs: abilities, victory rules, match modes, UI.
- [ ] New movement classes (ships), and orders and abilities from data.
