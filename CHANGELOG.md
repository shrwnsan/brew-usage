# Changelog

All notable changes to brew-usage are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-11

### Added
- **`--size` flag** for querying package download and installed sizes before installation
  - Shows download and installed sizes from bottle manifests
  - Supports multiple packages in table format: `brew-usage --size go node python`
  - Platform-specific bottle tag detection (macOS codenames, Linux, arm64/x86_64)
  - Automatic fallback to compatible older macOS versions when exact match unavailable
- **Platform detection** via `brew --bottle-tag` with manual fallback
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
- Top N filtering not yet implemented (Phase 2)
- Separate formulae/casks display not yet implemented (Phase 2)
- Configuration file support not yet implemented (Phase 2)

---

## Version Statistics

| Version | Release Date | Changes | Key Features |
|---------|---------------|---------|--------------|
| 0.2.0 | 2026-02-11 | 1 feature, 2 changed, 3 fixed | `--size` flag, bottle manifest lookup, IEC units, platform detection |
| 0.1.1 | 2026-02-10 | 1 fix | Fixed ANSI color code output |
| 0.1.0 | 2026-02-10 | Initial release | Core functionality, modular architecture |

## Technical Debt

### Future Improvements (Phase 2)
- [ ] Add cache analysis with cleanup recommendations
- [ ] Implement JSON output format
- [ ] Add top N filtering by size
- [ ] Implement category filtering (formulae-only or casks-only)
- [ ] Add configuration file support
- [ ] Add test suite coverage
- [ ] Implement CI/CD pipeline

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
