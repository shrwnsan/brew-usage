# Tasks: brew-usage doctor (PRD-003)

**PRD:** [prd-003-doctor.md](prd-003-doctor.md)
**Created:** 2026-08-19
**Target Version:** 0.6.0
**Branch:** `feat/v0.6.0-doctor`

---

## Ground Rules (carried from tasks-002/003, binding)

- No checkbox ✅ while any stub remains; shellcheck warning-clean; syntax-check clean
- bash 3.2 compatible (indexed arrays only, guarded `"${arr[@]}"`, no `local var=$(cmd)`)
- Conventional Commits; trailer `Co-Authored-By: GLM <zai-org@users.noreply.github.com>`
- CI green (all four jobs) before merge

## Implementation notes from spec review (2026-08-19)

- `config-valid` needs loader instrumentation: `load_config_file()` gains
  `BREW_USAGE_CONFIG_MALFORMED` (count) and `BREW_USAGE_CONFIG_FIRST_BAD`
  ("line N" of first malformed/unknown-key line) globals — warnings to stderr stay
  unchanged. Read-only addition, no behavior change
- `-d` is unused in the parser; bare word `doctor` added as a case (like `help`)
- Doctor runs AFTER arg parsing (so TOP_N etc. are initialized) and BEFORE report
  generation; `DOCTOR_FLAG_PASSED` joins the post-parse conflict chain against all
  mode flags
- Manifest-cache check reuses `is_cache_valid()` per file over
  `$BREW_BOTTLE_CACHE_DIR/*--*--*.json` (our cache naming only — never
  Homebrew's `*bottle_manifest.json` originals)
- ghcr probe reuses the anonymous token endpoint pattern from the test suite

## Task 1: `lib/brew-usage-doctor.sh` — check registry + all 14 checks + unit tests

**Files:** `lib/brew-usage-doctor.sh` (new), `lib/brew-usage-config.sh` (counters),
`tests/test-doctor.sh` (new)
**Estimate:** 3–4 hours

- [x] Loader counters (see notes above)
- [x] `doctor_result <verdict> <detail> [suggestion]` helper + `doctor_check_<name>`
      registry pattern; `doctor_run_all()` iterates and tallies
- [x] All 14 checks per PRD table with exact verdict rules
- [x] Unit tests (brew-independent subset runs on ubuntu): config-valid via malformed
      fixture, ttl-sane via CACHE_CLEANUP_DAYS, manifest-cache via fixture dir with
      touch -t mtimes, bash-version, jq-present (PATH manipulation)
- [x] shellcheck clean; bash 3.2 clean

## Task 2: CLI wiring + display + JSON + integration tests

**Files:** `brew-usage`, `lib/brew-usage-display.sh`, `lib/brew-usage-json.sh`,
`tests/test-doctor.sh` (integration section), README, `.github/workflows/ci.yml`
**Estimate:** 2–3 hours

- [x] `doctor` / `--doctor` / `-d` parsing; post-parse mutual exclusivity vs
      `--top/--formulae/--casks/--sort/--all/-C/--size` (both orders); composes with
      `--json`, `--no-color`
- [x] Human display: grouped, ✓/⚠/✗ colored (respects --no-color/tty), summary line,
      deduped suggestions block
- [x] JSON: `{checks:[...], summary:{pass,warn,fail}}`; stdout valid JSON always
- [x] Exit codes 0 (all pass, warns allowed) / 2 (warns, no fail) / 1 (any fail or
      invalid args)
- [x] Integration tests: healthy machine exit 0 + no ✗; `--json` parses + summary
      counts match; `doctor --top 5` both orders exit 1; broken PATH → brew-present
      fail + exit 1
- [x] CI wiring: unit subset in unit-tests job, full in both integration jobs
- [x] README (usage + features) and display_help()

## Task 3: Release prep

- [x] CHANGELOG `[0.6.0]`, version bump, stats table, PRD-003 status → Implemented
- [x] tasks-004 checkboxes honest; full battery macOS (bash5+3.2) + CI four jobs green
- [ ] Post-merge (user consent): tag v0.6.0, homebrew-tap bump
