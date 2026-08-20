# Tasks: doctor plugin hooks (PRD-009)

**Status:** In progress (v0.12.0) — gate resolved 2026-08-21 by best
judgment under the user's standing "proceed" authorization (gate round
unanswered; recommended options taken: executable dir, verdicts
aggregate into the exit code, 5s timeout, no plugin fixes).
**Created:** 2026-08-21
**Predecessor:** tasks-008 Task 2, PRD-003 (doctor)

# Scope

PRD-009 implements the last parked doctor item. tasks-008 Task 2
points here.

## Task 1: Plugin hooks (v0.12.0)

- [x] PRD section (PRD-009 — done at gate)
- [x] Discovery + execution + timeout in lib/brew-usage-doctor.sh;
      results appended to the existing arrays (JSON falls out)
- [x] Report integration (plugins group last); exit aggregation;
      `doctor --fix` untouched
- [x] Suite tests/test-doctor-plugins.sh covering the PRD-009 test
      plan; help/README/CHANGELOG; version bump v0.12.0

## Dependency graph

Single task; no blockers.
