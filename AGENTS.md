# AGENTS.md

Instructions for AI coding agents working on Creel, the engine. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md) and the README.

## Commands

```
LOBSTER=<path to lobster> ./check.sh   # Creel's modules compile with nothing from a game but examples/plain's hooks
```

A game on Creel can be run headless through MCP while you work on it: start a match, step, order, query, hash, save, capture,
run its tests ([mcp/README.md](mcp/README.md)).

Creel is built with [Lobster](https://github.com/aardappel/lobster); `LOBSTER_VERSION` names the commit it was last tested with.
Games use Creel as a git submodule pinned to a commit, so a change here only reaches a game when it bumps its pin.

## Rules

Read [CONTRIBUTING.md](CONTRIBUTING.md); these are the parts agents most often get wrong.

- **Issue first.** Find or open a GitHub issue (problem, plan, how we'll know it's done) before writing code. Commits name it (`#12`).
- **Conventional Commits** for every commit and PR title: `type(scope): summary`. The `PR title` check fails anything else.
- **Branches** are `type/<issue>-<short-description>`, e.g. `fix/5-voxel-post-description`. Never `claude/...` or other tool defaults.
- **No links to AI chat threads, sessions or projects** in issues, PRs, commits or comments, and no `Claude-Session:` trailers.
  A `Co-Authored-By` line is fine.
- **Labels:** `type: bug`, `type: feature`, `type: chore`, `type: perf`, `type: docs`; `status: needs-triage`, `status: needs-decision`,
  `status: blocked`; plus the repo's `area: ...` labels.
- **`main` is protected.** Everything lands through a PR with green checks. PRs that depend on each other are a stack, each based
  on the one before. Never force-push someone else's branch.
- **Never weaken a test or check to get green.** Fix the cause.
