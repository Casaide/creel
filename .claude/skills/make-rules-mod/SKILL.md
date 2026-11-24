---
name: make-rules-mod
description: Make or change the rules of a game or mod on Creel (an economy, a town, a whole new game's rules) from a written rules contract, test-first, in data and Lua. Use when asked to build a rules mod or total conversion, to follow another game's rules, or to fix a rule that plays wrong.
---

# Make a rules mod

A rules mod is a pack whose data and Lua change how the game plays. Each rule is written down, tested and then coded, in
that order. The engine is never changed for one pack's rule. A game on Creel has Creel as a submodule at `creel/`, so the
paths below are under it there.

Read first: `docs/rules-contract.md` (the template), `docs/lua.md` (hooks, the API, `process{}`, a pack's own tests) and
CONTRIBUTING.md's "What belongs in Creel".

## 1. Write the contract

Copy the template from `docs/rules-contract.md` into the pack as `RULES.md`.
- **Find out what the rules are.** If the mod follows a game, look its rules up: don't invent them, and note where each
  one came from.
- **One row per thing that happens**, as tick steps: what's true, what a tick does, what's true after. Put numbers in data.
- **Mark each row's side:** `engine`, `data`, `Lua` or `gap`. A rule that names a good, a trade, a building, a number or an
  order is never `engine`.
- **Write down the invariants and the looks**, and every place the mod deliberately differs from its source.
- **Unclear rules go in the open questions.** Take the answer that best fits the source and the game, write it down, and go
  on.

## 2. A failing test per row

Write a pack test for each row in `data/tests/*.lua` (docs/lua.md, "A pack's own tests"). Each phase of a test:
- sets up the state with `place`, `give` or `spawn`;
- runs ticks with `wait(n)`, or waits for an event with `wait_for(kind, max, ...)`;
- checks the row's "after" with `expect`.

Run the tests: through the game's MCP `creel_pack_tests`, or a game's own runner that calls `pack_tests_of`. A new row's
test must fail before its rule is written. A test that passes from the start isn't testing the row. Put the test's name
in the row.

## 3. The rules

- **Numbers and lists are data:** costs, stages (`"stages"` on a building type), the delivery order (rules economy
  `deliveries`), what a terrain gives.
- **Behaviour is Lua**, through the hooks in docs/lua.md. Its state lives in hook columns, never in Lua globals.
- **A rule in steps** (a meal, a rest, a trip to fetch something) is a `process{}`: phases with `enter`, and `done`,
  `ticks` or an `event` to wait for. Don't hand-build task codes and timers.
- **Run each row's test as you go.** Never weaken a test or an invariant to get green: fix the rule, or fix the row if the
  rule was wrong (and say so in the contract).

## 4. Invariants and looks

- **Invariants:** put the contract's invariants in the pack's `invariants()` hook. They're checked on every tick of every
  pack test, every MCP `creel_step` with `invariants`, and every runner step.
- **Looks:** check each one with the draw probe where it applies, or a capture you look at. Name what was checked in the
  row.

## 5. A whole match

Run a match headless with the runner. Here's a script: it starts from the mod's args, steps a few game minutes with the
invariants on, then reads the buildings and the delivery events.

```
node creel/mcp/creel-run.js creel-mcp.json run.json out.json
```

The same script must give the same JSON every time. A save resumed must give the same hashes as the run that wasn't
stopped. The MCP gives the same view, live (`creel_start`, `creel_step`, `creel_events`, `creel_buildings`).

## 6. When no hook can carry a rule

Mark the row `gap`. Open a Creel issue for a general hook, worded as what any game gains: "a hook when a unit enters a
building", not "the inn seats serfs". Write the issue's number in the row. When the hook lands, the rule goes in the
pack's Lua. Nothing of the pack goes into Creel.

## Done when

- Every row names a test, and every test passes.
- The invariants hold through a whole match run by the runner.
- The looks are checked.
- The contract says where the mod differs from its source.
