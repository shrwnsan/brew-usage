# Tasks: size intelligence — comparison view + historical tracking

**Status:** Complete — Task 1 (comparison view) shipped in v0.10.0
(PRD-007); Task 2 (historical tracking) shipped in v0.11.0 (PRD-008;
gate resolved 2026-08-20: explicit `--snapshot`, JSONL append log,
count-capped retention).
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
2. **Historical size tracking** — settled in the second gate round:
   explicit `--snapshot` flag, append-log storage, count-capped
   retention (see Task 2).

## Task 1: Comparison view (v0.10.0, PRD-007 — done)

- [x] PRD section with the settled semantics + exit codes (PRD-007)
- [x] Implementation reusing get_package_size / manifest cache; bash 3.2
      constraints; composes with --json (not --quiet)
- [x] Suite + regression battery; help/README/CHANGELOG
      (`tests/test-size-compare.sh`, 51 assertions; total 490 across
      11 suites)

## Task 2: Historical tracking (v0.11.0, PRD-008 — done)

Gate resolution 2026-08-20: explicit `--snapshot` (recording is
opt-in — no hidden writes on report runs); append log
`~/.brew-usage/history/snapshots.jsonl` count-capped to the newest 90
(a tool about disk waste must not itself grow unbounded); du-based
sizes; local-only data, never uploaded.

- [x] PRD section: schema, retention/prune policy, snapshot trigger
      (PRD-008)
- [x] Snapshot writer + prune; diff renderer (`--history`)
- [x] Suite + regression battery; help/README/CHANGELOG
      (`tests/test-snapshot.sh`, 54 assertions)

## Dependency graph

Task 0 (done) → Task 1 (v0.10.0) and Task 2 (v0.11.0)
