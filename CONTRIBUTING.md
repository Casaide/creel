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

## Pull requests

- `main` is protected: changes land through a pull request, with its checks green.
- Pull requests that depend on each other are a stack, each based on the one before it.
- No links to AI chat threads, sessions or projects in issues, pull requests, commits or comments, and no `Claude-Session:` trailers.
  A `Co-Authored-By` line and a plain "Generated with Claude Code" line are fine.
