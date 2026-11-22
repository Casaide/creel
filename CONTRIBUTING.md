# Contributing

## Issues first

Every change starts with a GitHub issue: the problem, the plan, and how we'll know it's done. Commits and pull requests name it.

## Commits and pull request titles

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): summary`, lower case, no full stop.
Add `!` after the type or scope for a breaking change.

Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`.

```
fix(devlog): fit the voxel creatures summary in 160 characters
ci: install libopengl0 for the Deck build
feat(units)!: one weapon mount list per unit
```

The `PR title` check fails a pull request whose title doesn't follow this.

## Branches

`type/<issue>-<short-description>`, the same types as above: `fix/5-voxel-post-description`, `chore/64-contributing-rules`.

## What belongs in Creel

Creel is an engine for RTS games that are deterministic, testable, locked and safe for an AI to build on. It holds what any
RTS needs, and nothing that only one game needs. Ask three questions of every change:

1. **Would a battle game, a town builder and a reskin mod all use it, each with its own data?** Then it's a Creel
   primitive. Example: flow fields, or a market where places ask for goods and carriers take the jobs.
2. **Does it name a good, a trade, a building, a number or an order of priorities?** Then it's a rule of a game or a mod,
   kept in its data or in Lua through hooks. Example: "a road tile takes one stone", or "gold goes to the school first".
3. **Does it keep the sim deterministic, checkable or sealed?** Then it's Creel's, and a pack can't turn it off.
   Example: the state hash, Lua's step budgets, or the per-tick invariants.

When a pack needs something no hook gives, Creel gets a general hook, and the rule stays in the pack. Issues and pull
requests here are worded as what the engine gains, not as one game's feature.

## Pull requests

- `main` is protected: changes land through a pull request, with its checks green.
- Pull requests that depend on each other are a stack, each based on the one before it.
- No links to AI chat threads, sessions or projects in issues, pull requests, commits or comments, and no `Claude-Session:` trailers.
  A `Co-Authored-By` line and a plain "Generated with Claude Code" line are fine.
