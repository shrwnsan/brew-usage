# Tasks: PRD-005 — v0.8.0 fix tier 2 + version-specific --size

Ground rules (binding): no checkbox while stubs remain; shellcheck
warning-clean; bash 3.2 compatible (no `local var=$(cmd)`, guard
`${arr[@]}` under set -u); Conventional Commits; CI green before merge.

## Task 1: Config repair fixes (registry tier `config`) ✅

**Files:** lib/brew-usage-doctor.sh, lib/brew-usage-utils.sh (backup/atomic
helpers if shared), brew-usage, tests/test-doctor-fix.sh
**Estimate:** 3 hours

- [x] `repair-config-lines` (source: config-valid): comment out exactly the
      lines the loader flagged — malformed + unknown-key — with
      `# brew-usage-fix disabled line N: ` prefix; line numbers from a fresh
      re-parse (loader diagnostics may be stale after other edits)
- [x] `clamp-cache-ttl` (source: ttl-sane): comment old
      `CACHE_CLEANUP_DAYS=N` line with `# brew-usage-fix clamped from N`,
      write `CACHE_CLEANUP_DAYS=30` in place
- [x] Once-per-pass timestamped `cp -p` backup; backup failure aborts the
      fix with zero edits (reported as apply FAILED); atomic mktemp+mv
      write in the config file's directory
- [x] Entry point re-runs `load_config_file()` after applying a
      `config`-tier fix, before the after `doctor_run_all`
- [x] Dry-run plan lines for both fixes (counts: N line(s), TTL old→30)
- [x] Tests: fixture config with 2 malformed + 1 unknown-key line + sane
      TTL → dry-run plans 1 fix, file untouched; --yes comments exactly
      the 3 lines, backup exists, after report shows config-valid pass;
      TTL>30 fixture → clamped line pair written; unwritable dir → apply
      FAILED, zero edits

## Task 2: JSON fix plan ✅

**Files:** brew-usage, lib/brew-usage-json.sh, lib/brew-usage-doctor.sh,
tests/test-doctor-fix.sh
**Estimate:** 2 hours

- [x] Lift `--fix` × `--json` conflict; `--yes` still requires `--fix`
- [x] `--fix --json`: `{checks, summary, fixes: [{id, check, tier,
      description}]}` (empty array when nothing fixable); stdout is the
      only output (human lines suppressed/moved to stderr)
- [x] `--fix --yes --json`: apply, conditional config re-source, re-run,
      after JSON with `fixes: [{id, status, result}]`
- [x] Update the v0.7.0 exit-1 assertion for `--fix --json` to the new
      composed behavior; `--yes --json` without --fix still exits 1
- [x] Tests: all four combinations parse via `jq .`; stdout purity
      asserted (no "Planned fixes"/"applied:" on stdout); statuses correct

## Task 3: Version-specific --size (formula-first fallback) ✅

**Files:** lib/brew-usage-size.sh, tests/test-size-version.sh (new),
tests/test-size-lookup.sh (regression guard), lib/brew-usage-display.sh
**Estimate:** 2.5 hours

- [x] `get_package_size`: on brew-info failure with `@` in the arg, split
      at last `@`; suffix must pass `is_valid_version` (else invalid-name
      error); explicit version skips resolution, feeds
      `fetch_bottle_manifest` directly
- [x] Existing-formula path byte-identical to v0.7.0 (go@1.21 etc.)
- [x] New suite `tests/test-size-version.sh` (exec 755): unit tests with
      mocked brew/fetch where possible + integration on real formulae;
      invalid pinned version exits 1; nonexistent pinned version → warn
      + exit 2; `--quiet`/`--json` compose
- [x] display_help + README: document `name@version` semantics
      (formula-first, exact-version fallback)

## Task 4: Release prep

**Files:** CHANGELOG.md, README.md,
docs/plans/prd-005-v0.8.0-fix-tier2-versioned-size.md,
docs/plans/prd-004-doctor-fix.md, docs/plans/prd-002-package-size-lookup.md,
lib/brew-usage-config.sh
**Estimate:** 1 hour

- [x] CHANGELOG `[0.8.0]` entry + stats table; version bump `0.8.0`
- [x] PRD-005 Status → Implemented; PRD-004 future-list: config repairs +
      JSON plan marked delivered; PRD-002 future-list: version-specific
      lookup marked delivered
- [x] tasks-007 checkboxes honest; full battery macOS (bash5 + 3.2) + CI
      4 jobs green (merge is gated on CI green — true at merge time)
- [ ] Post-merge (user consent): tag v0.8.0, homebrew-tap bump

## Dependency graph

Task 1 → Task 2 (share doctor-fix suite + entry-point wiring) → Task 3
(independent subsystem, but shares display_help/entry) → Task 4
