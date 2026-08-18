# Changelog

All notable changes to brew-usage are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
