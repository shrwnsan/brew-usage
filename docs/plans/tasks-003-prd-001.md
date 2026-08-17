# Tasks: PRD-001 Phase 2 — JSON Output, Cache Analysis, --all, Config File

**PRD:** [prd-001-brew-usage.md](prd-001-brew-usage.md)
**Created:** 2026-08-18
**Target Version:** 0.4.0
**Branch:** `feat/v0.4.0-phase-2`

---

## Background

v0.3.0 (merged PR #5, 2026-08-18) completed PRD-002 and hardened the CLI: PRD exit
codes (0/1/2), order-independent mutual exclusivity, CI (lint/unit/macOS-integration),
shellcheck-clean at warning severity, bash 3.2 compatibility verified on CI runners.
Phase 2 of PRD-001 is now unblocked. Implementation order below follows the goal
decision: `--json` first (highest scripting value, serves both modes), then cache
analysis, then `--all` pagination, then config file support.

## Ground Rules (from tasks-002, still binding)

- No checkbox ✅ while any stub remains in delivered code
- shellcheck warning-severity clean; `bash scripts/syntax-check.sh` clean
- bash 3.2 compatible (CI runners use stock /bin/bash): no `local var=$(cmd)`,
  guard `"${arr[@]}"` expansions under `set -u`, no bash-4-only features
- Conventional Commits; `Co-Authored-By: GLM <zai-org@users.noreply.github.com>`
- CI green on the PR before merge

---

## Task 1: `--json` flag — both report mode and size mode

**Files:** `brew-usage`, `lib/brew-usage-display.sh` (new display functions or new
`lib/brew-usage-json.sh` module), `lib/brew-usage-size.sh` (minor), tests
**Estimate:** 3–4 hours

- [ ] `--json` flag parses in both modes; mutually exclusive with nothing (composes
      with `--top N`, `--formulae`, `--casks`, and `--size`)
- [ ] Report-mode JSON schema per PRD-001 §JSON Output:
      `{formulae: {packages: [{name, size, size_human}], total_bytes, total_human},
       casks: {...}, grand_total_bytes, grand_total_human}`
      (PRD also sketches a cache block — omit until Task 2 lands, then add)
- [ ] Size-mode JSON: `{packages: [{name, version, download_size, installed_size,
      platform, status}], exit codes unchanged (0/1/2); warnings/errors to stderr,
      NOT into stdout JSON}` — stdout must remain valid JSON even on partial failure
- [ ] `--no-color` implied when `--json` (no ANSI in JSON stream)
- [ ] Human-readable default output unchanged when `--json` absent
- [ ] Tests: report JSON parses (`jq -e .`), contains formulae/casks keys; size JSON
      parses for `--size --json jq`; partial-failure size JSON still valid
- [ ] README + `display_help()` updated

## Task 2: Cache analysis (`-C` / `--cache`)

**Files:** `lib/brew-usage-config.sh`, new `lib/brew-usage-cache.sh`,
`lib/brew-usage-display.sh`, `brew-usage`, tests
**Estimate:** 2–3 hours

- [ ] `-C/--cache` shows cache section: total size of `$(brew --cache)` (fallback to
      BREW_BOTTLE_CACHE_DIR parent), breakdown by downloads/other, file count
- [ ] Cleanup candidates: files older than a threshold (default 30 days, constant in
      config) → "Cleanup candidates: X (Y files) — run `brew cleanup` to reclaim"
- [ ] Cache section added to report mode (PRD-001 output format shows it as a third
      section after Casks) AND works standalone with `-C`
- [ ] With `--json`: `cache: {total_bytes, total_human, cleanup_candidates_bytes,
      cleanup_candidates_human}` per PRD-001 schema
- [ ] Portable `stat` mtime (BSD/GNU — pattern exists in lib/brew-usage-size.sh)
- [ ] Read-only: never deletes anything, only reports
- [ ] Tests: cache section renders on a machine with a non-empty brew cache;
      `--cache --json` parses
- [ ] README + help updated

## Task 3: `--all` / `-a` pagination

**Files:** `brew-usage`, `lib/brew-usage-display.sh`, tests
**Estimate:** 1 hour

- [ ] `-a/--all` shows all packages (no top-N cut); conflicts with `--top` (exit 1,
      order-independent — reuse the `*_FLAG_PASSED` pattern)
- [ ] Paged via `less` when stdout is a terminal (respect `PAGER`, fall back to
      `less`, plain output when not a terminal — reuse `is_terminal`)
- [ ] `--all --json`: full list in JSON (no pager)
- [ ] Tests: `--all --top 5` → exit 1 both orders; `--all` with stdout not a tty
      prints everything without pager
- [ ] README + help updated

## Task 4: Config file support

**Files:** `lib/brew-usage-config.sh`, tests, docs
**Estimate:** 1–2 hours

- [ ] Optional `~/.brew-usage-config` sourced if present (KEY=VALUE lines; support at
      minimum: `TOP_N`, `SIZE_WARNING_THRESHOLD`, `SIZE_CRITICAL_THRESHOLD`,
      `CACHE_CLEANUP_DAYS` (Task 2's threshold))
- [ ] CLI flags override config file; config file overrides built-in defaults
- [ ] Malformed config file → warning to stderr, continue with defaults (never crash)
- [ ] Documented in README (with example file)
- [ ] Tests: config file with TOP_N=3 changes default report; malformed line warns
      but doesn't fail; CLI `--top` beats config

## Task 5: Release prep

**Files:** CHANGELOG.md, README.md, docs/plans/prd-001-brew-usage.md,
lib/brew-usage-config.sh
**Estimate:** 1 hour

- [ ] CHANGELOG `[0.4.0]` entry + stats table; version bump `0.4.0`
- [ ] PRD-001: Phase 2 checkboxes checked where delivered; options table statuses
      updated (`-a`, `-C`, `--json` → Implemented); Last Updated date
- [ ] README: features list, usage examples for all new flags, config file section
- [ ] tasks-003 checkboxes ✅ (honestly — after verification)
- [ ] Post-merge (user consent): tag v0.4.0, homebrew-tap bump

## Dependency Graph

```
Task 1 (--json)  → Task 2 (cache analysis adds its JSON block)
Task 3 (--all)   → depends on Task 1 only for --all --json composition
Task 4 (config)  → independent, but CACHE_CLEANUP_DAYS lands with Task 2
Task 5 (release) → last
```

## Definition of Done (PR-level)

- All suites green locally + CI (lint/unit/macOS) green on the PR
- shellcheck + syntax check clean
- `./brew-usage --version` → 0.4.0
- Squash-merge after CI green
