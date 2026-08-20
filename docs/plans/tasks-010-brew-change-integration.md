# Tasks: brew-change integration — doctor cross-checks (pre-PRD)

**Status:** Pre-PRD — blocked on an export surface in brew-change (see
the dependency note); brainstorm gate required before PRD.
**Created:** 2026-08-20
**Predecessor:** PRD-003 §Future (brew-change cross-checks)

# Scope

brew-usage doctor checks that consume brew-change's knowledge. The
original PRD-003 sketch: "recently-changed packages vs cache staleness."
Recorded concretely now that brew-change's internals are understood
(2026-08-20 recon: it already computes per-package breaking-change
verdicts and writes assessment.jsonl during `-u` runs, but has no stable
machine-readable export for other tools).

## Task 0: Brainstorm gate (blocking)

1. Which cross-checks are USEFUL, not just possible (the standing bar
   for this item):
   - (a) **Cache staleness**: packages brew-change recently reported
     upgraded → brew-usage's cached manifests for them are necessarily
     stale → doctor warns / `--fix` flushes just those
   - (b) **Pending-upgrade sizes**: outdated list from brew-change ×
     `--size` manifests → "disk delta if you upgrade everything"
   - (c) Both / neither / something else
2. Where does brew-usage read brew-change state from?
   - Stable export file (brew-change writes e.g.
     ~/.brew-change/last-assessment.json)? A `brew-change --json` mode
     brew-usage shells out to? Both have versioning/coupling questions —
     this is the design conversation
3. Failure posture: brew-change absent/stale/mismatched schema must be a
   doctor "pass (not installed)" style non-event, never a fail

## Dependency

Any implementation needs an agreed export surface on the brew-change
side (tracked there as docs/tasks-004-breaking-summary-and-llm-triage.md
covers the adjacent UX work; the export contract may deserve its own
brew-change research doc). Do not design brew-usage-side parsing around
brew-change's internal assessment.jsonl — it is explicitly internal.

## Task 1: Cross-check implementation (after gate + export exists)

- [ ] PRD section: chosen checks, data contract, versioning posture
- [ ] Doctor check(s) in a new group; --json composition; exit semantics
      unchanged (cross-check unavailable ≠ warn)
- [ ] `--fix` interplay if (a) chosen: flush-only-those-manifests needs a
      new surgical flush variant (name-filtered)
- [ ] Suite with brew-change-absent / -stale / -present fixtures

## Dependency graph

Task 0 → (blocked on brew-change export) → Task 1
