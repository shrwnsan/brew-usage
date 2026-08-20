# Changelog

All notable changes to brew-usage are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2026-08-20

### Added
- **`--snapshot`** — record a size snapshot of installed packages
  (PRD-008, tasks-009 historical tracking): scans formulae + casks with
  the report's du machinery and appends one JSONL line
  `{timestamp, package_count, total_bytes, packages:{name:bytes}}` to
  `~/.brew-usage/history/snapshots.jsonl` (path overridable via
  `BREW_USAGE_HISTORY_FILE`; dir created 0700). Retention is
  count-capped: the newest 90 snapshots survive (atomic prune; a failed
  prune over-retains, never loses data). Explicit flag by design — the
  tool stays read-only unless asked; local-only data, never uploaded
- **`--history`** — diff the two most recent snapshots: old/new
  summaries (packages, total, total delta) and top movers by absolute
  delta with `grew`/`shrank`/`added`/`removed` tags (capped at `TOP_N`;
  zero-delta packages omitted). `--history --json` emits
  `{old, new, changes:[{name, from, to, delta, change}]}` with pure-JSON
  stdout; `--snapshot --json` echoes the recorded line. Both flags are
  standalone modes conflicting with every mode flag and each other;
  `--history` needs jq but not brew, `--snapshot` needs both
- Twelfth test suite (`tests/test-snapshot.sh`, 54 assertions);
  total 545 assertions across 12 suites

## [0.10.0] - 2026-08-20

### Added
- **`--size --compare`** — installed-vs-latest bottle size comparison per
  package (PRD-007, reading (a) of PRD-002's comparison view): for each
  named package, resolves the installed version (`brew list --versions`)
  and the latest stable version (`brew info --json=v2`, revision
  appended), pulls both versions' manifests through the existing
  cache-first machinery (a new `get_versioned_size()` skips the
  redundant per-side `brew info` of `get_package_size`), and reports
  `size_delta = latest installed_size − installed installed_size`.
  Historical installed versions resolve from brew-usage's cache or
  Homebrew's downloads cache exactly like pinned lookups; when neither
  holds one, that side is `null` and the entry status is `partial` —
  honest, not an error
- Per-entry statuses: `ok` (both sides resolved), `up_to_date`
  (versions equal), `partial` (a side or its size unresolved),
  `not_installed`. Human table renders version+size cells with a signed,
  colored delta (yellow grows / green shrinks or holds); `--compare
  --json` emits the same `{"packages":[...]}` envelope as size mode with
  the compare entry schema. `--compare` requires `--size`, composes
  with `--json`, and is mutually exclusive with `--quiet`; exit codes
  mirror size mode (0 resolved, 2 mixed, 1 total failure)
- Eleventh test suite (`tests/test-size-compare.sh`, 51 assertions);
  total 490 assertions across 11 suites

## [0.9.0] - 2026-08-20

### Added
- **`doctor --fix` install tier** — a third fix-registry tier that can modify
  system state: `install-jq` (source check: jq-present) runs
  `brew install jq` when jq is missing, then verifies jq is usable on PATH
  (the installed version is the apply result line; a brew failure is
  reported as apply FAILED with brew's error line, and an install that
  leaves jq unusable fails with PATH guidance). Due only when jq is absent
  AND brew is on PATH — when brew itself is broken, the brew-present check
  already fails with guidance and no install is offered
- **`--fix --yes --install`** — installs are opt-in on top of `--yes`:
  dry runs plan `install-jq` like any tier (with a note naming the extra
  flag), but plain `--fix --yes` never installs anything — the fix is
  `skipped` (a new fix status that also flows into
  `doctor --fix --yes --json` results), and existing scripted
  `--fix --yes` runs keep their exact behavior. `--install` without
  `--fix --yes` exits 1
- The confirm-gated (interactive y/N) tier is dropped from the backlog:
  the triple-flag opt-in covers the safety concern within the settled
  no-prompts scripting model
- `tests/test-doctor-fix.sh` extended to 148 assertions; total 439

## [0.8.0] - 2026-08-20

### Added
- **`doctor --fix` config repair tier** — two new fix-registry entries that
  repair `~/.brew-usage-config` by commenting lines out (never deleting or
  rewriting wholesale): `repair-config-lines` disables exactly the malformed
  and unknown-key lines the loader flagged, `clamp-cache-ttl` clamps
  `CACHE_CLEANUP_DAYS>30` to 30 with the old value preserved as a comment.
  Every apply pass makes one timestamped backup first (failure aborts with
  zero edits), writes atomically (mktemp + mv, permissions preserved,
  CRLF files stay CRLF), refuses symlinked config files rather than
  desyncing dotfile-manager setups, and the entry point re-runs
  `load_config_file()` so the after report reflects the repaired config
- **`doctor --fix --json`** — the `--fix` × `--json` conflict is lifted and
  the modes now compose: dry run embeds
  `fixes: [{id, check, tier, description}]` in the report, and
  `--fix --yes --json` applies (human lines on stderr) and emits one after
  document with `fixes: [{id, status, result}]`. stdout alone is always
  valid JSON; plain `doctor --json` output is unchanged
- **Version-specific `--size name@version`** — formula-first, exact-version
  fallback: existing versioned formulae (`go@1.22`) behave exactly as
  before; when `brew info` fails on a pinned argument (`go@1.26.6`), the
  suffix is used verbatim as the version for the manifest lookup (no
  resolution, no revision append). Pinned versions resolve from ghcr when
  current or from Homebrew's local downloads cache when previously fetched;
  otherwise the existing warn + partial path applies. Invalid pins
  (`foo@../etc`) exit 1
- Tenth test suite (`tests/test-size-version.sh`, 35 assertions);
  `tests/test-doctor-fix.sh` extended to 119; total 410 assertions

## [0.7.0] - 2026-08-20

### Added
- **`doctor --fix`** — repair planning for fixable doctor findings. Dry run by
  default: after the normal report it prints a "Planned fixes" section (fix id,
  source check, action) and applies **nothing**. Ships with a fix registry
  holding one entry — `flush-expired-manifests` (source check: manifest-cache) —
  as the extension point for future tiers. Own-state rule: fixes may only touch
  brew-usage-owned files; no config edits, no installs
- **`doctor --fix --yes`** — apply the planned fixes (one `applied:` line each),
  then re-run the full doctor pass and show the after report; the exit code is
  the after-verdict (0/2/1 semantics unchanged). The apply is surgical: only
  expired `*--*--*.json` manifests are removed (fresh manifests and Homebrew's
  originals untouched), unlike `--flush-cache` which drops all of ours
- `--fix` is doctor-mode-only and conflicts with `--json` (JSON fix plan is a
  future tier); `--yes` is only valid together with `--fix`; both orders of
  every conflict exit 1. Ninth test suite
  (`tests/test-doctor-fix.sh`, 56 assertions)

## [0.6.1] - 2026-08-19

### Added
- **`--quiet FIELD`** — single-value scripting output for `--size`: prints only the
  field's value (`download` | `installed`), one line per package in argument order,
  never colored. Failed packages print nothing on stdout — their story stays on
  stderr and in the exit codes (0/2/1 semantics unchanged). Only valid in size mode
  and mutually exclusive with `--json`
- **`--flush-cache`** — remove brew-usage's own manifest cache files only (the
  `*--*--*.json` files we created in `$BREW_BOTTLE_CACHE_DIR`); Homebrew's
  `*bottle_manifest.json` originals are never touched. Prints the removed count,
  exits 0, and is mutually exclusive with every mode flag. `doctor` now suggests
  `brew-usage --flush-cache` when expired manifests exist

## [0.6.0] - 2026-08-19

### Added
- **`brew-usage doctor`** (`doctor`, `-d`, `--doctor`) — environment diagnostics with
  14 read-only checks across four groups: environment/deps (brew-present,
  brew-prefix, jq-present, bash-version), config health (config-present,
  config-valid, config-effective), cache & manifests (cache-dir, manifest-cache,
  ttl-sane), and brew surfaces & network (scan-formulae, scan-casks,
  cellar-caskroom, ghcr-reachable). Follows the `brew doctor` contract:
  **diagnose and suggest, never mutate** — suggestions are printed as exact
  commands, never executed
- `--json` support: `{checks: [...], summary: {pass, warn, fail}}` on stdout,
  always valid JSON
- Exit codes: 0 all pass (warns allowed) / 2 warns but no fails / 1 any fail or
  invalid usage (e.g. combining doctor with mode flags)
- Runs even when brew itself is missing — a missing brew is one of the diagnosed
  checks, not a crash
- Config loader now exposes malformed-line counters
  (`BREW_USAGE_CONFIG_MALFORMED`, `BREW_USAGE_CONFIG_FIRST_BAD`) consumed by
  doctor; existing config warnings are unchanged

## [0.5.2] - 2026-08-19

### Security
- **Input validation for `--size` lookups** — package names are now checked against
  Homebrew's name charset (lowercase alphanumerics plus `. _ @ + -`) and versions against
  `[A-Za-z0-9._+-]` (still permits `+` pre-releases and `_revision` suffixes) *before*
  any value reaches a jq program, a ghcr.io URL, a cache filename, or a `find` pattern.
  Hostile inputs (`a b c`, `../etc/passwd`, `foo#bar`, `*`, fully-qualified
  `tap/formula` paths) now fail fast with `Invalid package name` and exit 1 — or a
  `not_found` entry in `--json` mode — instead of producing confusing 404s or corrupted
  cache paths. **Behavior change:** `--size homebrew/core/node` was previously a
  confusing lookup failure; it is now a clean validation error
- **jq filter injection hardened** — `find_matching_platform_tag` now passes platform
  tags to jq via `--arg` (data) instead of splicing them into the program string,
  matching the pattern already used in `extract_sizes_from_manifest`
- **Config warnings strip terminal escapes** — malformed lines echoed to stderr from
  `~/.brew-usage-config` have non-printable bytes replaced with `?` so escape sequences
  in the file cannot inject into the terminal

### Added
- Hostile-input test coverage: validation unit tests (names, versions, jq-injection
  regression payload), integration tests for every rejected name shape, `--json`
  `not_found` behavior, partial-success (exit 2) with a hostile name, and config
  escape-byte sanitization

## [0.5.1] - 2026-08-19

### Fixed
- **`--size` was broken on Linux when a manifest was cached** — `is_cache_valid` used a
  BSD-first `stat` idiom; GNU `stat -f` means *filesystem mode*, which exits 0 with
  garbage output (or dumps filesystem info to stdout even while failing), poisoning the
  age arithmetic under `set -u`. Cached manifests were always treated as expired and
  lookups degraded to "no bottle" warnings. Both `stat` call sites
  (`is_cache_valid`, `cache_stat_files`) now select the invocation by platform
  explicitly — no try-both-fallback idioms
- Regression test added (`is_cache_valid` on the current platform)

### Added
- **`integration-linux` CI job** — ubuntu-latest + linuxbrew, full integration suite.
  The README's Linux support claim is now continuously verified (this job found the
  stat bug on its first local run)

## [0.5.0] - 2026-08-19

### Added
- **`--sort name` now actually sorts by name** — the flag parsed (and validated) since
  v0.1.0 but silently always sorted by size; `sort_by_name` now drives the report
  pipeline (`--sort size` remains the default, unchanged)

### Changed
- CI lint job gained an **executable-bit gate** — squash merges previously dropped
  exec bits on test scripts without CI noticing (suites run via `bash x.sh`); any
  non-`100755` entry under `tests/`, `scripts/`, or the entry point now fails the build

## [0.4.1] - 2026-08-18

### Fixed
- **`--all` pager mangled colors** — the default pager was bare `less`, which renders
  ANSI escapes as literal `ESC[` text (or strips them, depending on less version).
  The default is now `less -R` (ANSI passthrough); an explicit `$PAGER` is still
  respected verbatim. Verified in a pseudo-terminal: colors pass through intact.

## [0.4.0] - 2026-08-18

### Added
- **`--json` machine-readable output** for both report mode and `--size` mode;
  composes with `--top N`, `--formulae`, `--casks`, and `--size`. Color and
  decorations are disabled automatically; warnings and errors go to stderr so
  stdout stays valid JSON even on partial failure (requires `jq`)
- **Cache analysis `-C` / `--cache`**: Homebrew download cache size, file count,
  downloads-vs-other breakdown, and cleanup candidates (files older than
  `CACHE_CLEANUP_DAYS`, default 30) with a `brew cleanup --prune` hint.
  Strictly read-only; works standalone or appended as a third report section
- **`--all` / `-a`**: list every installed package (no top-N cut), paged
  through `${PAGER:-less}` when stdout is a terminal (plain output when piped;
  never paged for `--json`)
- **Optional `~/.brew-usage-config`**: `KEY=VALUE` defaults for `TOP_N`,
  `SIZE_WARNING_THRESHOLD`, `SIZE_CRITICAL_THRESHOLD`, and `CACHE_CLEANUP_DAYS`.
  Strictly parsed (never sourced); only known keys with numeric values apply.
  Precedence: CLI flags > config file > built-in defaults

### Changed
- Grand total now includes cache bytes whenever the cache section is shown
  (i.e. with `-C`); without `-C` totals are unchanged
- Scan failures are propagated instead of being reported as empty results, and
  duplicate section processing was removed

### Fixed
- **Report mode now works on stock macOS bash 3.2** — it had been broken since
  v0.1.0 for users without a Homebrew bash (associative arrays require bash 4;
  the report path no longer uses them)
- Swallowed scan errors no longer silently produce empty output

## [0.3.0] - 2026-08-18

### Added
- **ghcr.io bottle manifest download** for `--size`: manifests are fetched from
  `ghcr.io/v2/homebrew/core/<pkg>` (anonymous token) when not present locally, so
  pre-install size lookup now works for never-installed packages
- **CI workflow** (`.github/workflows/ci.yml`): shellcheck lint, unit tests, and
  macOS integration tests, with a stub gate (`grep "not yet implemented" lib/`)
- **`@`-scoped formula support** for `--size` (e.g., `node@20`)

### Changed
- **Behavior change**: exit code `2` now means partial success for `--size`
  (≥1 package resolved + ≥1 failed; successful results are displayed). Previously
  any failure exited `1`. `0` = all ok, `1` = total failure / invalid args
- Mutual exclusivity errors (`--size` with `--top`/`--formulae`/`--casks`/`--sort`)
  are now order-independent — both `--size go --top 10` and `--top 10 --size go` exit 1
- Dev checkouts now run their own `lib/` instead of an installed tap's

### Fixed
- Partial-success `--size` runs display successful results instead of aborting
  under `set -e` before output
- Test harness counter drift (summary "Tests run" vs "Passed" mismatch)
- shellcheck warnings (SC2155 declare-and-assign masking return codes, SC2034
  unused variables)
- Dead code removed (`display_packages`)

## [0.2.0] - 2026-02-11

### Added
- **`--size` flag** for querying package download and installed sizes before installation
  - Shows download and installed sizes from bottle manifests
  - Supports multiple packages in table format: `brew-usage --size go node python`
  - Platform-specific bottle tag detection (macOS codenames, Linux, arm64/x86_64)
  - Automatic fallback to compatible older macOS versions when exact match unavailable
- **Platform detection** via `brew ruby -e 'puts Homebrew::SimulateSystem.current_tag'` with manual fallback
- **Bottle manifest caching** with 1-hour TTL to avoid repeated fetches
- **IEC binary unit formatting** (`KiB`, `MiB`, `GiB`) for `--size` output
- **Unit tests** for size lookup functionality (15 tests)

### Changed
- Added `jq` as an optional dependency (required for `--size` flag)
- Improved module loading with `*_LOADED` guards to prevent re-sourcing errors

### Fixed
- Version revision suffix handling for manifest filenames (e.g., `1.25.7_1`)
- Platform matching for newer macOS versions (tahoe/Sequoia 15.x) with proper fallback

## [0.1.1] - 2026-02-10

### Fixed
- **Critical**: ANSI color codes were being printed literally instead of being interpreted
- Changed from `echo "\033[...m"` to `printf '\033[...m'` for proper escape sequence handling
- Output now displays correctly with colors and formatting

## [0.1.0] - 2026-02-10

### Added
- **Initial release** with core functionality
- Formulae disk usage calculation with sorting
- Cask disk usage calculation with sorting
- Human-readable size formatting (B, K, M, G)
- Total aggregation by category (Cellar, Caskroom)
- Grand total calculation
- Help system (`--help`)
- Version information (`--version`)
- Cross-platform support (macOS/Linux with BSD/GNU `du`)
- Modular bash architecture with lib/ modules
  - `brew-usage-config.sh` - Configuration & defaults
  - `brew-usage-scan.sh` - Package discovery
  - `brew-usage-calculate.sh` - Portable size calculation
  - `brew-usage-display.sh` - Output formatting
  - `brew-usage-utils.sh` - Shared utilities

### Features
- Per-package size breakdown showing largest packages first
- Automatic platform detection for correct `du` command usage
- Apache-2.0 licensing
- Homebrew tap distribution via `shrwnsan/tap/brew-usage`

### Known Limitations
- Cache analysis not yet implemented (Phase 2)
- JSON output format not yet implemented (Phase 2)
- Separate formulae/casks display not yet implemented (Phase 2)
- Configuration file support not yet implemented (Phase 2)

---

## Version Statistics

| Version | Release Date | Changes | Key Features |
|---------|---------------|---------|--------------|
| 0.11.0 | 2026-08-20 | 2 added | `--snapshot` local size-history recording (JSONL, newest 90 kept); `--history` last-two diff (top movers, added/removed, `--json`) |
| 0.10.0 | 2026-08-20 | 2 added | `--size --compare` installed-vs-latest upgrade delta (`ok`/`up_to_date`/`partial`/`not_installed`); `--compare --json` composition |
| 0.9.0 | 2026-08-20 | 2 added | `doctor --fix` install tier (`install-jq`); `--fix --yes --install` opt-in + `skipped` fix status |
| 0.8.0 | 2026-08-20 | 3 added | `doctor --fix` config repairs (backup+atomic, symlink-safe), `--fix --json` composition, version-specific `--size name@version` |
| 0.7.0 | 2026-08-20 | 2 added | `doctor --fix` dry-run repair planning; `--fix --yes` surgical apply + after report |
| 0.6.1 | 2026-08-19 | 2 added | `--quiet FIELD` scripting output for `--size`; `--flush-cache` manifest cache removal |
| 0.6.0 | 2026-08-19 | 5 added | `brew-usage doctor` (14 read-only checks, `--json`, exit 0/2/1), config malformed-line counters |
| 0.5.2 | 2026-08-19 | 3 security, 1 added | `--size` input validation, jq `--arg` hardening, escape-stripped config warnings |
| 0.5.1 | 2026-08-19 | 1 added, 1 fixed | Linux `--size` stat portability fix, `integration-linux` CI job |
| 0.5.0 | 2026-08-19 | 1 added, 1 changed | `--sort name` implemented, exec-bit CI gate |
| 0.4.1 | 2026-08-18 | 1 fixed | `--all` pager ANSI passthrough (`less -R`) |
| 0.4.0 | 2026-08-18 | 4 added, 2 changed, 2 fixed | `--json` output, cache analysis (`-C`), `--all` with pager, config file, bash 3.2 report fix |
| 0.3.0 | 2026-08-18 | 3 added, 3 changed, 4 fixed | ghcr.io manifest download, exit code 2 = partial success, CI workflow |
| 0.2.0 | 2026-02-11 | 1 feature, 2 changed, 3 fixed | `--size` flag, bottle manifest lookup, IEC units, platform detection |
| 0.1.1 | 2026-02-10 | 1 fix | Fixed ANSI color code output |
| 0.1.0 | 2026-02-10 | Initial release | Core functionality, modular architecture |

## Technical Debt

### Future Improvements
- [x] Add cache analysis with cleanup recommendations (v0.4.0)
- [x] Implement JSON output format (v0.4.0)
- [x] Add top N filtering by size (v0.1.0)
- [x] Implement category filtering (formulae-only or casks-only) (v0.1.0)
- [x] Add configuration file support (v0.4.0)
- [x] Add test suite coverage (v0.2.0)
- [x] Implement CI/CD pipeline (v0.3.0)

### Known Limitations
- Requires internet connection for `brew list` commands
- Large installations (>500 packages) may take several seconds
- No historical tracking or growth rate analysis
- No integration with `brew-change` for changelog display

## Performance Benchmarks

### Version 0.1.0
- **~50 formulae**: < 2 seconds
- **~20 casks**: < 1 second
- **Total execution**: < 5 seconds for typical installations
- **Memory usage**: ~5MB peak
- **Platform support**: macOS (Intel/ARM), Linux, WSL
