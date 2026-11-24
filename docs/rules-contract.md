# A pack's rules contract

A rules contract is a pack's rules written down before they're coded, so that each one can be tested and an agent knows
which parts are the engine's and which are the pack's. It's one Markdown file in the pack, `RULES.md`, kept next to its
`data/`. Copy the template below and fill it in. The `make-rules-mod` skill (`.claude/skills/make-rules-mod/`) walks
through it. `examples/plain/rules-contract.md` is a filled-in contract: each of its rows names a test that passes.

## What goes in it

- **Where the rules come from.** The game or the design the rules follow, and what "follows it" means. If a rule is
  looked up, say where it was looked up. If it's guessed, say so.
- **The rules, one row each.** A row is one thing that happens in the sim, and it must be checkable:
  - **Id:** short and stable (`R12`). Tests and commits name it.
  - **The rule as tick steps:** what is true, what happens on a tick, and what is true after. Write "a site asks for its
    planks once its ground is levelled", not "sites are built realistically". Name the numbers: they go in data.
  - **Its test:** the test that checks it, by file and name (a pack's `data/tests/*.lua` test, or a game's own). A row with
    no test yet says `none yet`, and that row isn't done.
  - **Side of the line:** `engine` (a Creel primitive the pack only sets with its data), `data` (the pack's JSON),
    `Lua` (the pack's hooks), or `gap` (no hook can carry it yet: it needs a Creel issue for a general hook, named here).
    The three questions are in [CONTRIBUTING.md](../CONTRIBUTING.md#what-belongs-in-creel).
- **The invariants.** What must be true after every tick, as the pack's `invariants()` hook checks it (docs/lua.md), on top
  of the engine's (`src/testkit/invariants.lobster`). For example: "every good is in a building, on a carrier or on its
  way", or "no unit stands inside a building it isn't in".
- **The looks.** What a player must be able to see for a rule to read: a carried good, a working pose, a site's stage.
  Each look gets a check where there is one (the draw probe, a capture to look at), or `by eye` with what to look for.
- **Deliberate differences.** Where the pack doesn't follow its source, and why. A difference that isn't written down is
  a bug.
- **Open questions.** What isn't settled, and who decides it.

## The template

```markdown
# <pack>: rules contract

Follows: <the game or design these rules come from, and where they were looked up>.

## Rules

| Id | The rule, as tick steps | Test | Side |
|---|---|---|---|
| R1 | <what is true> → <what happens on a tick> → <what is true after> | `data/tests/<file>.lua` `test_<name>` | engine / data / Lua / gap (#issue) |

## Invariants

| Id | Holds after every tick | Checked by |
|---|---|---|
| I1 | <a statement about the whole state> | `invariants()` in `data/hooks/<file>.lua` |

## Looks

| Id | What the player sees | Check |
|---|---|---|
| L1 | <a carried good, a pose, a stage> | <draw probe / capture / by eye: what to look for> |

## Deliberate differences

- <where this pack differs from its source, and why>

## Open questions

- <what isn't settled, and who decides>
```

## How it's used

1. The contract is written first, row by row, before any code. Rules that are unclear go to the open questions, not into
   code.
2. Each row gets a failing test first: a pack test (`data/tests/*.lua`, docs/lua.md, "A pack's own tests") that sets up
   the state, runs ticks or waits for an event, and checks the row's "after".
3. The rule is written to make it pass: data where it's a number, Lua through hooks where it's behaviour, with
   `process{}` (docs/lua.md, "Rules in phases") for anything in steps.
4. The invariants go in the pack's `invariants()` hook, so every test and every MCP or runner step checks them.
5. A whole match is run through the runner (`mcp/creel-run.js`) or the MCP with the invariants on, and the looks are
   checked.
6. A row whose side is `gap` gets a Creel issue for a general hook, worded as what any game gains. The pack's rule never
   goes into Creel.
