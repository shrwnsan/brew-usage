# Tasks: size intelligence — comparison view + historical tracking (pre-PRD)

**Status:** Pre-PRD — both items are underspecified in PRD-002 §Future;
Task 0 (brainstorm gate) settles what they even mean before any PRD.
**Created:** 2026-08-20
**Predecessor:** PRD-002 (size lookup), PRD-005 (version pinning)

# Scope

The two PRD-002 future items that need a design conversation, not just
implementation. Recorded here so the backlog is explicit.

## Task 0: Brainstorm gate (blocking)

1. **Comparison view** — PRD-002 says "show difference between installed
   packages" but never defines the comparison. Candidate readings:
   - (a) Installed size vs latest-bottle size per package ("what will
     this upgrade cost/gain me on disk?") — composes with the v0.8.0
     version-pinning machinery
   - (b) Side-by-side of two named packages (`--size go node --compare`)
   - (c) Before/after snapshot diff (overlaps with historical tracking)
   - Question: which (if any) is the real need?
2. **Historical size tracking** — needs a storage story before anything
   else:
   - Snapshot trigger: explicit flag (`--snapshot`)? automatic on each
     report run? cron/launchd out of scope?
   - Storage: `~/.brew-usage/history/` as dated snapshots vs an append
     log; size bounds and retention (a tool about disk waste must not
     itself grow unbounded — cap + prune policy needed)
   - Rendering: trend per package? "packages that grew the most since
     last snapshot"?
   - Privacy/scope: local-only data, never uploaded; document it

## Task 1: Comparison view (after gate picks a reading)

- [ ] PRD section with the settled semantics + exit codes
- [ ] Implementation reusing get_package_size / manifest cache; bash 3.2
      constraints; composes with --json/--quiet where meaningful
- [ ] Suite + regression battery; help/README/CHANGELOG

## Task 2: Historical tracking (after gate settles storage)

- [ ] PRD section: schema, retention/prune policy, snapshot trigger
- [ ] Snapshot writer + prune; trend renderer (or diff view)
- [ ] Suite + regression battery; help/README/CHANGELOG

## Dependency graph

Task 0 → Task 1 and Task 2 independently (different subsystems; may ship
as separate releases)
