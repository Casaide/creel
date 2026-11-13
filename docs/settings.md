# Settings a game can change

Creel's look has settings: plain variables with a default, which a game sets to make the engine its own. A game that
sets none draws exactly as Creel does by default. This page lists them, with what they do and when to set them.

It is kept up to date as settings are added: **a change that adds or alters a setting adds or alters its row here, in
the same pull request.** The full API reference, the command line and the data formats will get their own pages later.

How to set one: assign it from the game's own code after the imports. "Before the first bake" means before any unit,
building or prop is baked to a sprite; "any time" means it is read every frame.

## The camera's angle

The camera looks down on the ground at 30 degrees by default (a tile is twice as wide as it is tall on screen). A game
can ask for another angle. Four values follow from the one angle `e`, and all four must be set together, before the
first bake:

| Setting | In | Default | For an angle `e` (degrees) | What it is |
|---|---|---|---|---|
| `iso_k` | `view/facing` | `0.024` | `0.048 * sin(e)` | How far down the screen a milli-tile along x or y goes. `iso` and `iso_inv` use it, and the ground's shaders follow it. |
| `vx_ELEV` | `view/voxel` | `30.0` | `e` | The elevation the voxel units are baked from. |
| `VM_VIEW` | `view/voxel_mesh` | `{ -30, 45, 0 }` | `{ -e, 45, 0 }` | The view the voxel buildings and props are baked from. |
| `LEVEL_PX` | `game/relief` | `20.0` | `20 * cos(e) / cos(30)` | How many canvas pixels one level of height lifts the ground. |

A bake cache made at one angle is wrong at another: put the angle in the cache's key. Lower angles show more of what
stands up (trees, cliffs, walls) and less of the ground, and things further up the screen hide more of what is behind
them.

## The ground

All in `game/ground`, read every frame (any time).

| Setting | Default | What it does |
|---|---|---|
| `ground_water_edge` | `0.5` | Where on its mask the water begins. More than 0.5 draws the water narrower than its tiles. |
| `ground_bank_px` | `0.0` | The water lies this many art pixels below its banks, with a cut bank drawn above it. 0: level with the ground. |
| `ground_shore_soft` | `0.0` | More than 0: no sand at the shore. The ground slopes down to the water over this much of the water mask, its own cover going damper and darker in steps, earth by the waterline. |
| `ground_water_shallow`, `ground_water_deep` | a teal, a deep teal | The water's colour at its edge and where it is deep. |
| `ground_water_ripples` | `0.0` | How many ripples the water carries. 0: a calm water's few pale glints. Toward 1: more of them, whiter, all along the water, as on a running stream. |
| `relief_snow` | `0.0` | 0 to 1: how much snow lies on cliff faces: on the lip at the top, on the ledges' tops and in the scree at the foot, a pixel at a time. Set it with the ground's own snow. Read by the `cliff` shader. |
| `ground_litter_fringe` | `0.0` | More than 0: the edge of the forest floor (the litter laid under trees) is scattered a pixel at a time over this much of its weight, so leaves thin out onto the grass with no drawn line. |
| `ground_atlas_next`, `ground_atlas_mix` | none, `0.0` | A second set of ground textures turning in over `ground_atlas_tex`, for ground that changes while you watch (a season coming on, snow settling). At mix 0 the ground is all the first set, at 1 all the second. Between them each texel is one or the other, never a blend, and the second comes in a texel at a time in small patches, so the ground stays crisp. Set `ground_stale = true` when you move the mix, because the ground is kept in a texture between changes. Both atlases must have the same layout. |

## Raised ground

| Setting | In | Default | What it does |
|---|---|---|---|
| `relief_sharp` | `game/relief` | `false` | `false`: an outer corner of raised ground is cut down to the ground below, a hill's rounded shoulder. `true`: corners are kept, for sheer cliffs several levels high that jog square. Set it before the map's relief is built. |
| `relief_rough` | `game/relief` | `0.0` | Levels. More than 0: wherever the height changes (a cliff, a step, a ramp), the raised ground about it rises and falls by up to this much on a smooth noise, and those tiles are drawn in strips (4 each way) so a rim wanders and bends instead of running ruled along a tile's edge. Flat ground (level 0) and ground away from any change of height stay flat. Units stand on it (`lift_at` includes it), and the light on raised ground is found per corner from the slope, so it runs smoothly over the strips and turns sharply only at a rim. About 1 makes a stepped rock wall read as broken rock. Set it before the map's relief is built. |
| `relief_rough_size` | `game/relief` | `1.5` | Tiles: the size of the rough's broad swells. A finer ripple a third the size rides on them. Set it with `relief_rough`. |
| `relief_cliffs` | `game/relief` | `0.0` | Tiles, 0 to 1. More than 0: proper cliffs, drawn off the grid. The sim's levels are unchanged (a tile beside higher ground is still cliff, and nothing walks on it); only the drawing changes. Each level's drop is a curve through the unwalkable tile below it, half a tile out from the higher ground give or take half this much, on a noise of its own, so a rim runs at any angle and never along a tile's edge. Where two levels' drops wander apart there is a ledge between them; where they meet, one taller face. Scree lies at each face's foot. A ramp is drawn as a straight slope, a level over its tile, with any wall above it cut into it. The ground is kept on a fine lattice (8 points a tile) near any change of height: its steep parts are drawn by the `cliff` shader (rock), the rest by the terrain shader, and units stand on it (`lift_at`). Walkable ground keeps its level all over. It takes the place of `relief_rough` and `relief_sharp`. 0.7 suits a mountain gorge. Set it before the map's relief is built. |

| `relief_occlude` | `game/ground` | `2` | Tiles. Raised ground with lower ground within this many tiles behind it (up the screen) is a hill's near edge: its tops are kept as `occluders`, which a game draws again in its back-to-front order so they hide what stands behind and below them. 2 hides what's behind a drop of a level or two. A higher drop hides more of the ground behind it (about 1.8 rows of tiles a level at 22 degrees), so raise it to cover that: 4 suits a ridge four levels above a valley. More costs more draws. Set it before the map's relief is built. |

A game that draws its own `cliff` shader (a shader of that name loaded after Creel's takes its place) reads its inputs
as Creel's does: the texture coordinate is (along the face, height in levels); the colour is (rim's level / 9, which way
the face looks from 0 to 1, foot's level / 9, 1 for a face on a tile's edge or 0.5 for one drawn off the grid by
`relief_cliffs`), and the uniforms are `art_px`, `level_px` and `snow`.

## The light

The baker's light, set before the first bake. Put each one in the bake cache's key, because they change the baked art.

| Setting | In | Default | What it does |
|---|---|---|---|
| `VM_SUN` | `view/voxel_mesh` | `{ -48, -58, 0 }` | The direction the buildings and props are lit from. A lower first angle is a lower sun, with longer shadows. |
| `vx_SUN` | `view/voxel` | upper left | Toward the sun as the camera sees it, for the units and their shadows. Set it to match `VM_SUN`. |
| `vg_dither` | `view/voxel_grid` | `1.0` | How much each voxel's light is jittered before it is banded. 1 is Age of Anything's painterly speckle; low (Smyana: 0.15) is crisp. |
| `vg_leaf_tones` | `view/voxel_grid` | `5.0` | How many hard bands of light a leaf has. |

The rest of the light is data, not settings: a game's `atmosphere.json` moods. Each mood's knobs (grade, haze, bloom,
glow, and the sun's optional `sun_shade`, `shade_colour`, `shade_grey`, `woods`, `mist`, `deep`, `unit_lift`, `unit_rim`, `paint` (a watercolour softening over the whole picture) and others),
moving between moods with `atmo_set_between`, and the shade buffer a game draws its shadows, canopy and units into
are all in [`atmosphere.md`](atmosphere.md). One setting there is read every frame (any time):

| Setting | In | Default | What it does |
|---|---|---|---|
| `atmo_sun_dir` | `view/atmosphere` | `{ -0.6, 0.8 }` | Toward the sun on the screen (y up), for the rays in the air (`shafts`). Set it from the game's sun. |
| `atmo_low_fog_at(top, depth)` | `view/atmosphere` | top `0` (none) | The low fog's place in this map, in levels: its `top`, and how far below that it is at its thickest. The mood says how thick (`low_fog`), what colour (`low_fog_colour`) and how much its top drifts (`low_fog_drift`). Call it when a map is entered. See [`atmosphere.md`](atmosphere.md). |
## Drawing sprites

Read every frame (any time).

| Setting | In | Default | What it does |
|---|---|---|---|
| `sprite_even` | `game/pack` | `false` | Every art pixel the same size at a zoom between whole numbers. Off, sprites are sampled nearest, and at a zoom of 2.75 one art pixel is drawn two screen pixels wide and the next three, so edges look jagged. On, they are sampled sharp bilinear: each art pixel is solid, and only the one screen pixel where two meet is a mix of them. At a whole-number zoom it is the same as nearest. |

## Voxel models that shade themselves

Set in `view/voxel_grid` before a model is baked. A game that changes one puts it in its bake key.

| Setting | Default | What it does |
|---|---|---|
| `vg_sun_shadow` | `false` | `false`: a model's own shadow is found by marching toward the sun in steps of the lighting unit, which steps over twigs and thin boughs. `true`: it is found from a picture of the model seen from the sun, exact to a voxel and hard-edged, so a crown shades its own boughs and trunk. |
| `vg_shade` | `0.0` | How much of its sky light a voxel in that shadow loses as well, from 0 (none) to 1 (all). Only read when `vg_sun_shadow` is on. |

## Voxel units

Set in `view/voxel` before a unit is baked, and put in the bake key. Both are off by default, so Age of Anything's
units bake as before.

| Setting | Default | What it does |
|---|---|---|
| `vx_set_res(res)` | `2.0` | Voxels a body unit, and the sprite cell to fit. A unit made of `.vox` models has `vx_VOX_RES` (2) model voxels a body unit, so a unit of size `s` bakes a model voxel to `res * s / 2` pixels. Under 1, rows of the model are lost and a thin coat breaks up into flecks of what is under it; exactly 1 puts rows on the half pixel and can open holes. A little over 1 (Smyana: `2 / 0.73 * 1.15` for its men of size 0.73) keeps every voxel. Draw the sprites smaller to match. |
| `vx_smooth_normals` | `0` | Passes evening out the shading: each surface voxel's normal and occlusion averaged with those round it that face the same way. A model's voxel stairs then light smoothly, not in flecks. Smyana: 2. |
| `vx_despeckle` | `0` | Passes softening the shaded picture: each pixel the mean of itself and those beside it of the same material at near the same depth. Lines one pixel wide, seams between colours and the outline stay sharp. Smyana: 1. |

## Features a game switches on from its data

- **Map bridges** (`lib/bridges`): a map's `"bridges"` (tile rectangles `x0, y0, x1, y1`) are timber decks over water
  that units walk. They start standing; `bridge_hurt(k, damage)` breaks one, and workers rebuild a broken one with
  `CMD_HELP_BUILD` on its id. `bridges.json` gives its strength and the rebuild's cost and time.
- **Ground you can work** (`terrain.json`): a terrain with `"resource"`, `"amount"` and `"depleted"` is gathered with
  `CMD_GATHER` and turns into the `depleted` terrain when it is used up. Trees are the usual case; anything that
  should be cleared by work can use it.
- **A model held along the hand** (`view/voxel`, `gear.json`): a gear shape `{ "model": ..., "at": ..., "to": ...,
  "side": [x, y, z] }` turns the model so its +x points along `side` (in the hold's frame) and its +z is x cross y.
  Without `side` the model's x is the frame's first axis, so a model can't lie along it; with `side` a long gun's
  barrel (`"to": ["hand", 1, 0, 0]`) can point where the hand points, its lock to one side (`"side": [0, 0, 1]`).
  Thin parts (a barrel one voxel wide) can drop out when a model is baked at an angle: give them a `cap` of their own
  over the model.
- **A rider's legs astride** (`view/voxel`, a body's `"seat"`): the rider's legs now hang down the mount's sides clear
  of it. The knee is at least the mount's `seat.wide` out, and the shin hangs straight down, as far out as the mount
  is wide anywhere along it, so it lies against the barrel rather than through it. The rider's `"seat": { "legs":
  [thigh, shin] }` sets how long they are, in body units (default `[6.7, 5.0]`, as before). Smyana's men use
  `[9.0, 8.5]` so their feet hang below the horse's belly.

## Sounds

Set from the game's data, `data/audio.json`, read by `sounds_load()` (`game/audio`), which a game calls once before its
first sound:

| Key | What it is |
|---|---|
| `sounds.<name>` | A sound: `takes` (how many files: `assets/audio/sfx/<name>_1.wav` and on, played in turn), `gap` (seconds it won't play again within, default 0) and `bus` (a name in `buses`). A name starting with `_` is a note. |
| `buses.<name>` | A bus's volume in dB, added to every sound on it. |

`play_sound(name, db)` plays the next take at `db` over its bus; `play_sound_at(name, db, pan)` does the same from the
left or right, `pan` from -1 (all left) to 1 (all right). The player's own `sound_level` (settings.txt) is on top.
