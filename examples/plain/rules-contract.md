# plain: rules contract

Follows: no game. examples/plain has no data and no pack of its own, so this contract covers the building and carrying
rules its tests set up by hand: the engine's primitives, as a pack would set them with its data. It's the filled-in
example of [docs/rules-contract.md](../../docs/rules-contract.md). Every row names a test that `check.sh` runs and that
passes.

## Rules

| Id | The rule, as tick steps | Test | Side |
|---|---|---|---|
| R1 | A site of a type with `"stages"` is laid → while its ground is levelled it asks for no goods → once levelled it is at stage 1 | `src/test_build_stages.lobster`: "a new hall is levelled first", "it's levelled with no goods, no further" | engine (stages in data) |
| R2 | A levelled site → asks only for its first stage's goods (wood) → waits for them, and goes up as they come | `src/test_build_stages.lobster`: "wood", "and waits for it", "half its wood in, it goes up half its wood stage" | engine |
| R3 | A site whose wood is all in but whose wood stage isn't built → asks for no stone yet → stone is asked for once that stage is built | `src/test_build_stages.lobster`: "its wood all in but its wood stage not yet built, no stone is asked for", "stone" | engine |
| R4 | With rules `stages_ahead: 1` → a site asks for wood and stone together → it still uses them in order: stone in before wood, it waits for the wood | `src/test_build_stages.lobster`: "wood stone", "its stone in before its wood, it waits for the wood" | data (rules) |
| R5 | A site is built up as each good comes → never past what was brought | `src/test_build_stages.lobster`: "built up as each stone comes, never past what was brought" | engine |
| R6 | A type without `"stages"` → asks for all its goods at once | `src/test_build_stages.lobster`: "a type without stages asks for all its goods at once, as before" | engine |
| R7 | A site's foundation is its type's own share, else the rules' → a house with no stone goes no further than its foundation | `src/test_site_phase.lobster`: "a type's own foundation share, else the rules'", "the house with no stone goes no further than its foundation" | data |
| R8 | A road site → is dug to half with no goods → its stone in, it's laid | `src/test_site_phase.lobster`: "the road dug to half, the field all the way", "its stone in, the road is laid" | data |
| R9 | The rules' delivery order says gold to the school first → the market plans that delivery before the rest | `src/test_market.lobster`: "want:school:gold full:mint:gold want:hut:stone" | data (rules `deliveries`) |
| R10 | The same rules and the same state → the same deliveries, in the same order | `src/test_market.lobster`: the plan asked twice gives one answer | engine (determinism) |
| R11 | Goods can come from a workshop or a store → from the workshop first → from the nearer store once stores cost nothing more | `src/test_market.lobster`: "gold from the mint before the store", "and from the nearer store when stores cost nothing more" | data |
| R12 | A builder walking to a site that others finish → stops where it is, not walking on | `src/test_invariants.lobster` `test_builder_stops` | engine |
| R13 | An idle carrier in a doorway → steps aside to a free tile beside it (a road first, else free ground), one it walks to in a straight line | `src/test_invariants.lobster` `test_aside_off_door` | engine (rules `idle_aside`) |
| R14 | A rule in steps written as `process{}` → does on every tick what the same rule written by hand does | `src/test_lua.lobster` `test_process` | Lua |

## Invariants

| Id | Holds after every tick | Checked by |
|---|---|---|
| I1 | Every hook column is as long as it must be (`columns`); ids are unique and rising (`ids`); every unit is on the map (`on_map`) | `src/testkit/invariants.lobster`, in `test_invariants` |
| I2 | What a unit carries is a good it can carry (`carry`); no stock or hold is negative or over its room (`stock`, `holds`) | the same |
| I3 | Every delivery's carrier, source and target exist (`jobs`); units don't walk into each other (`solid`); none is held up too long (`stuck`) | the same |
| I4 | A pack's own `invariants()` hook holds, and a break says the pack's own words (`pack`) | `test_invariants` `test_pack` |

## Looks

| Id | What the player sees | Check |
|---|---|---|
| L1 | Nothing: examples/plain draws no world | the draw probe's own test (`src/test_draw_probe.lobster`) checks the probe, not a look |

## Deliberate differences

- None: these rules follow no game. A pack's contract lists where it leaves its source.

## Open questions

- None here. examples/plain grows a pack of its own when a contract needs pack tests (`data/tests/*.lua`) to run in
  Creel's own checks.
