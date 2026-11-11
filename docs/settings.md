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
| `ground_litter_fringe` | `0.0` | More than 0: the edge of the forest floor (the litter laid under trees) is scattered a pixel at a time over this much of its weight, so leaves thin out onto the grass with no drawn line. |

## Raised ground

| Setting | In | Default | What it does |
|---|---|---|---|
| `relief_sharp` | `game/relief` | `false` | `false`: an outer corner of raised ground is cut down to the ground below, a hill's rounded shoulder. `true`: corners are kept, for sheer cliffs several levels high that jog square. Set it before the map's relief is built. |

## The light

The baker's light, set before the first bake. Put each one in the bake cache's key, because they change the baked art.

| Setting | In | Default | What it does |
|---|---|---|---|
| `VM_SUN` | `view/voxel_mesh` | `{ -48, -58, 0 }` | The direction the buildings and props are lit from. A lower first angle is a lower sun, with longer shadows. |
| `vx_SUN` | `view/voxel` | upper left | Toward the sun as the camera sees it, for the units and their shadows. Set it to match `VM_SUN`. |
| `vg_dither` | `view/voxel_grid` | `1.0` | How much each voxel's light is jittered before it is banded. 1 is Age of Anything's painterly speckle; low (Smyana: 0.15) is crisp. |
| `vg_leaf_tones` | `view/voxel_grid` | `5.0` | How many hard bands of light a leaf has. |

The rest of the light is data, not settings: a game's `atmosphere.json` moods. Each mood's knobs (grade, haze, bloom,
glow, and the sun's optional `sun_shade`, `shade_colour`, `shade_grey`, `woods`, `mist`, `deep`, `unit_lift` and others),
moving between moods with `atmo_set_between`, and the shade buffer a game draws its shadows, canopy and units into
are all in [`atmosphere.md`](atmosphere.md). One setting there is read every frame (any time):

| Setting | In | Default | What it does |
|---|---|---|---|
| `atmo_sun_dir` | `view/atmosphere` | `{ -0.6, 0.8 }` | Toward the sun on the screen (y up), for the rays in the air (`shafts`). Set it from the game's sun. |
## Voxel models that shade themselves

Set in `view/voxel_grid` before a model is baked. A game that changes one puts it in its bake key.

| Setting | Default | What it does |
|---|---|---|
| `vg_sun_shadow` | `false` | `false`: a model's own shadow is found by marching toward the sun in steps of the lighting unit, which steps over twigs and thin boughs. `true`: it is found from a picture of the model seen from the sun, exact to a voxel and hard-edged, so a crown shades its own boughs and trunk. |
| `vg_shade` | `0.0` | How much of its sky light a voxel in that shadow loses as well, from 0 (none) to 1 (all). Only read when `vg_sun_shadow` is on. |

## Features a game switches on from its data

- **Map bridges** (`lib/bridges`): a map's `"bridges"` (tile rectangles `x0, y0, x1, y1`) are timber decks over water
  that units walk. They start standing; `bridge_hurt(k, damage)` breaks one, and workers rebuild a broken one with
  `CMD_HELP_BUILD` on its id. `bridges.json` gives its strength and the rebuild's cost and time.
- **Ground you can work** (`terrain.json`): a terrain with `"resource"`, `"amount"` and `"depleted"` is gathered with
  `CMD_GATHER` and turns into the `depleted` terrain when it is used up. Trees are the usual case; anything that
  should be cleared by work can use it.
