# Tasks: size intelligence — comparison view + historical tracking

**Status:** Task 1 (comparison view, reading (a)) done in v0.10.0
(PRD-007); Task 2 (historical tracking) parked with its storage
questions pending a future gate round.
**Created:** 2026-08-20
**Predecessor:** PRD-002 (size lookup), PRD-005 (version pinning)

# Scope

The two PRD-002 future items that need a design conversation, not just
implementation. Recorded here so the backlog is explicit.

## Task 0: Brainstorm gate (resolved 2026-08-20)

1. **Comparison view** — settled as reading **(a)**: installed vs
   latest-bottle size per package ("what will this upgrade cost/gain
   me on disk?"), composing with the PRD-005 version-pinning
   machinery. Settled in the backlog-prioritization round; readings
   (b) side-by-side and (c) snapshot diff remain unimplemented.
2. **Historical size tracking** — still parked; the storage questions
   below need their own gate round before any PRD.

## Task 1: Comparison view (v0.10.0, PRD-007 — done)

- [x] PRD section with the settled semantics + exit codes (PRD-007)
- [x] Implementation reusing get_package_size / manifest cache; bash 3.2
      constraints; composes with --json (not --quiet)
- [x] Suite + regression battery; help/README/CHANGELOG
      (`tests/test-size-compare.sh`, 51 assertions; total 490 across
      11 suites)

## Task 2: Historical tracking (parked — needs storage design first)

- Snapshot trigger: explicit flag (`--snapshot`)? automatic on each
  report run? cron/launchd out of scope?
- Storage: `~/.brew-usage/history/` as dated snapshots vs an append
  log; size bounds and retention (a tool about disk waste must not
  itself grow unbounded — cap + prune policy needed)
- Rendering: trend per package? "packages that grew the most since
  last snapshot"?
- Privacy/scope: local-only data, never uploaded; document it

## Dependency graph

Task 0 (done) → Task 1 (v0.10.0); Task 2 parked independently
(different subsystem; may ship as its own release after a gate round)
