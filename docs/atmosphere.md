# The atmosphere pass

`src/view/atmosphere.lobster`. The world is drawn into a texture, then onto the screen through one pass
that grades its colour, lays air over it, shades it and adds glow. Every value comes from a mood in the
game's `data/atmosphere.json`, and a mod's file merges over it. A mood of zeros draws the frame straight.
The pass has no game rules: the game says where the glows, shadows, canopy and units are.

This page documents settings and features as they are added. A full API reference comes later.

## Moods

`atmosphere.json` has `"moods"`: named objects, each with every number and colour below.

### Numbers (all required)

| Knob | Range | What it does |
|---|---|---|
| `exposure` | -1 to 1 | Brighter or darker overall. |
| `contrast` | -1 to 1 | Around mid grey. |
| `saturation` | -1 to 1 | -1 is grey. |
| `shadow` | 0 to 1 | How much `shadow_tint` colours the darks. |
| `highlight` | 0 to 1 | How much `highlight_tint` colours the lights. |
| `haze` | 0 to 1 | Air in `haze_colour`, stronger up the screen. |
| `haze_start` | 0 to 1 | How far up the screen the haze starts to thicken. |
| `haze_drift` | 0 to 1 | How much the haze drifts and varies. |
| `vignette` | 0 to 1 | Darkened corners. |
| `vignette_radius` | 0 to 2 | Where the darkening starts. |
| `bloom` | 0 to 2 | Soft glow round bright things. |
| `bloom_threshold` | 0 to 1 | How bright something must be to bloom. |
| `glow` | 0 to 4 | How strongly glows light what they fall on. |
| `glow_air` | 0 to 1 | Glow in the air round a light, not only on surfaces. |

### Colours (all required, `"#rrggbb"`)

| Knob | What it does |
|---|---|
| `shadow_tint` | Colour of the darks. |
| `highlight_tint` | Colour of the lights. |
| `haze_colour` | Colour of the haze and the mist. |

### The sun's knobs (optional; left out means 0, and a colour left out means white)

These act on the **shade buffer** (below). They do nothing while the game draws no shade.

| Knob | Range | What it does |
|---|---|---|
| `sun_shade` | 0 to 1 | How deep the shade is. Above 0, `atmo_shading()` is true and the game draws its shadows into the buffer. |
| `shade_colour` | colour | Multiplied into what's in shade. A light blue-grey gives cool, light shade. |
| `shade_grey` | 0 to 1 | How much colour the shade loses. |
| `sun` | 0 to 1 | How much `sun_colour` warms what's lit. |
| `sun_colour` | colour | The sun's colour. |
| `shafts` | 0 to 2 | Rays through gaps in the shade toward the sun (`atmo_sun_dir`). Off in Smyana: they smudge. |
| `shaft_length` | 0 to 1 | How far the rays reach, as a share of the screen's height. |
| `shaft_colour` | colour | The rays' colour. |
| `deep` | 0 to 1 | Darkens the top of the frame, where the far woods are. |
| `woods` | 0 to 1 | Darkens and greys what lies under a closed canopy (the buffer's green). A clearing stays lit. |
| `mist` | 0 to 1 | Lays the haze (at 85% of `haze_colour`) over what lies under a closed canopy. It takes the haze's colour but never lightens: shade under a closed canopy stays at least as dark as one lone tree's. |
| `unit_lift` | 0 to 1 | Keeps marked units (the buffer's blue) readable: less shade, deep wood, mist and haze on them, their own colour kept (the grade desaturates them less), and a little light. |
| `unit_rim` | 0 to 1 | Lights a marked unit's edge toward the sun (`atmo_sun_dir`), one art pixel wide, so it stands out of the shade behind it. Crisp, with no blur. |

Water keeps most of its light in shade. It is told by its colour (blue over red), so a stream in shade
doesn't read as a road.

### Glows

`"glows"` names each source the game can place (`building_fire`, `ruin_fire`, `window`, `flash`,
`shot`) with:
- `colour`: `"#rrggbb"`, or `"own"` for the thing's own colour.
- `radius`: canvas px.
- `strength`: 0 to 4.
- `flicker`: 0 to 1.

The game calls `atmo_glow(src, p, col, k, seed)` each frame for each one.

### Setting a mood

- `atmo_set(j, mood)` sets a mood by name. It returns an error string, or `""`. `"off"` turns the pass off.
- `atmo_set_between(j, a, b, t)` sets the light `t` of the way from mood `a` to mood `b` (0 is all `a`,
  1 is all `b`), mixing every number and colour. A game uses it to turn the day through its moods instead
  of switching. Smyana blends over `hours._blend` hours before each mood starts, and sets the light again
  only when the turn has moved a step.
- `atmo_problems(j)` lists everything wrong with a file: a missing knob, a value out of range, or a knob
  that doesn't exist.

## The shade buffer

The ground's shadows are drawn into a buffer of their own instead of onto the world. Where they overlap
they join into one shade instead of piling up black, and whatever stands in them is shaded too. The
buffer is the screen's size and sampled pixel for pixel, with no blur, so shade edges are as crisp as
the art.

Each frame, before `atmo_begin`:
1. Call `atmo_shade_begin()`. It clears the buffer to lit and places it as the world is (the game sets
   its own camera transform).
2. Draw the game's sprites into it with these shaders, in this order:

| Shader | Writes | Draw with |
|---|---|---|
| `atmo_shade_cast` | red: in shade | Shadows on the ground. Blending off. |
| `atmo_shade_canopy` | red and green: in shade, under a closed canopy | The canopy's shade (deep wood). Blending off. |
| `atmo_shade_clear` | clears all channels, by the colour's red | What stands up out of the shade (trees, rocks), so it is lit by its own bake. Alpha blending. |
| `atmo_shade_unit` | blue: a unit stands here (its shade kept) | Units the player must not lose. Additive blending. |
| `atmo_shade_stand` | red and green from the ground at the unit's foot, blue: a unit | Units, in place of `atmo_shade_unit`, after `atmo_shade_standing()`. Blending off. Colour from `atmo_stand_colour(foot)`. |

### A unit takes the shade where it stands

The buffer is a picture of the screen, so with `atmo_shade_unit` a unit keeps the shade of whatever ground lies
behind it on the screen: a tree's shadow on the ground further back is painted flat across a horse's body. To give a
unit the shade of the ground at its own feet instead:

1. Draw the ground's shade (casts, canopy) as above.
2. Call `atmo_shade_standing()`. It keeps a copy of the ground's shade and binds it for `atmo_shade_stand`. It resets
   the drawing transform, so set the camera again after it.
3. Draw each unit with the `atmo_shade_stand` shader, blending off, with the colour `atmo_stand_colour(foot)`, where
   `foot` is where the unit stands on the screen in pixels from the top left. The whole unit takes the ground's shade
   there, read at five places across its feet, so it goes into a shadow by degrees. Its blue is set, as
   `atmo_shade_unit` sets it. Read the ground a few pixels behind the feet, toward the sun: the unit's own shadow
   falls the other way.

Smyana does this for its men, horses and mules.

Draw the clears and the unit marks **back to front, interleaved**. Then a tree in front of a man wipes
his mark, and a tree behind him doesn't. A sunfleck (a spot of light through the canopy) is just a
clear: Smyana draws small ovals in black with the plain colour shader after the canopy.

The channels:
- **red**: in shade (`sun_shade`, `shade_colour`, `shade_grey`, `shafts`).
- **green**: under a closed canopy (`woods`, `mist`).
- **blue**: a unit (`unit_lift`).

A fire's light cancels the shade near it.

## The baker's light (voxel grids)

`src/view/voxel_grid.lobster` and `voxel_mesh.lobster`. These are globals a game sets before it bakes.
They change the baked art, so a game should put them in its bake keys.

| Setting | Default | What it does |
|---|---|---|
| `VM_SUN` | -48, -58, 0 | The light's direction. A lower sun casts longer shadows. |
| `vx_SUN` | upper left | Toward the sun as the camera sees it, for unit sprites and their shadows. |
| `vg_dither` | 1.0 | How much each voxel's light is jittered before banding. Lower is crisper: Smyana uses 0.15, where Age of Anything is painterly. |
| `vg_leaf_tones` | 5 | How many hard bands of light a leaf has. |
| `vg_sun_shadow`, `vg_shade` | false, 0 | A model's own shadow, exact to a voxel, and how much sky light a voxel in it loses. Added by the trees work. |

## Smyana's settings, as an example

Smyana's `data/atmosphere.json` has:
- Moods: `day`, `dawn`, `dusk` and `night`, with season variants such as `day.autumn`, `dawn.winter`
  and `dusk.summer`. The game picks the season's variant where there is one.
- `"hours"`: when each mood starts, plus `_blend`.
- `"sun"`: elevation, dither, leaf tones, and the canopy settings (`canopy`, `canopy_reach`,
  `canopy_trees`, `canopy_dim`, `flecks`), which are Smyana's own and not Creel's.
