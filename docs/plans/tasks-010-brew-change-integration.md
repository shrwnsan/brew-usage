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

## Task 1: Cross-check implementation (v0.13.0, PRD-010 — done)

Gate resolved 2026-08-21 (best judgment under standing proceed
authorization): cache-staleness only (upgrade sizes declined — covered
by v0.10.0 `--size --compare`); read the versioned export file
(brew-change tasks-005, schema_version 1), never shell out;
unavailable ≠ warn. The export dependency is satisfied: brew-change
v1.16.0 writes `~/.brew-change/last-assessment.json` + `export` cmd.

- [x] PRD section: chosen checks, data contract, versioning posture
      (PRD-010)
- [x] Doctor check `brew-change-stale` (group: cache); --json via the
      shared result arrays; exit semantics unchanged
- [x] Surgical name-filtered flush: `flush-stale-manifests` fix entry
      (tier safe) removes only stale-version files of changed names
- [x] Suite coverage with brew-change-absent / -unsupported-schema /
      -present fixtures (test-doctor.sh + test-doctor-fix.sh)

## Dependency graph

Task 0 → (blocked on brew-change export) → Task 1
