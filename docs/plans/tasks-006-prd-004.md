# Tasks: PRD-004 — doctor --fix (v0.7.0)

Ground rules (binding): no checkbox while stubs remain; shellcheck
warning-clean; bash 3.2 compatible (no `local var=$(cmd)`, guard
`${arr[@]}` under set -u); Conventional Commits; CI green before merge.

## Task 1: Flag parsing + conflicts ✅

**Files:** brew-usage, lib/brew-usage-display.sh, tests/test-doctor-fix.sh (new)
**Estimate:** 1.5 hours

- [x] New suite `tests/test-doctor-fix.sh` with fixtures: subshell
      export-before-source pattern (copy tests/test-doctor.sh conventions)
- [x] `--fix`/`--yes` parsed order-independently; doctor-mode-only
- [x] `--fix` outside doctor mode → exit 1; `--yes` without `--fix` → exit 1;
      `--fix` + `--json` → exit 1; conflicts with all non-doctor mode flags
      both orders; composes with `--no-color`
- [x] display_help: `--fix` and `--yes` documented

## Task 2: Fix registry + dry-run plan ✅

**Files:** lib/brew-usage-doctor.sh, tests/test-doctor-fix.sh
**Estimate:** 2 hours

- [x] Fix registry: fix id → check id, tier, description, apply function;
      `flush-expired-manifests` (source: manifest-cache, tier: safe)
- [x] `doctor --fix` prints normal report + "Planned fixes (dry run)"
      section + count footer; applies nothing (assert cache dir unchanged)
- [x] Zero fixable findings → "No fixes available" line

## Task 3: Apply path (surgical flush + re-run) ✅

**Files:** lib/brew-usage-size.sh, lib/brew-usage-doctor.sh, brew-usage,
tests/test-doctor-fix.sh
**Estimate:** 2 hours

- [x] `flush_expired_manifests()` in lib/brew-usage-size.sh: removes only
      `*--*--*.json` files failing `is_cache_valid`; output
      "<n> expired manifest(s) removed"; exit 0 always
- [x] `doctor --fix --yes`: applies planned fixes (one `applied:` line
      each), re-runs full doctor pass, prints after report; exit code =
      after-verdict (0/2/1)
- [x] Fixture: 2 expired + 1 fresh brew-usage manifest + Homebrew
      `x.bottle_manifest.json` decoy → only the 2 expired removed
- [x] `doctor --fix` (dry run) on same fixture → zero files removed

## Task 4: Release prep

**Files:** CHANGELOG.md, README.md, docs/plans/prd-004-doctor-fix.md,
lib/brew-usage-config.sh
**Estimate:** 1 hour

- [x] CHANGELOG `[0.7.0]` entry + stats table; version bump `0.7.0`
- [x] PRD-004 Status → Implemented; README doctor section documents
      `--fix`/`--yes`
- [x] tasks-006 checkboxes honest; full battery macOS (bash5 + 3.2) + CI
      4 jobs green (merge is gated on CI green — true at merge time)
- [x] Post-merge (user consent): tag v0.7.0, homebrew-tap bump (done: release v0.7.0, tap PR #37 merged, verified live from tap)

## Dependency graph

Task 1 → Task 2 → Task 3 → Task 4 (strictly linear; 2 and 3 share the new
suite file)
