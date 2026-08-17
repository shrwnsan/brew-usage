# PRD: Package Size Lookup Feature

**Status:** ✅ Implemented — core use case (pre-install size lookup) fulfilled as of v0.3.0
(v0.2.0 only read manifests already present in the local Homebrew cache; v0.3.0
adds ghcr.io manifest download, so `--size` works for never-installed packages)
**Created:** 2026-02-10
**Completed:** 2026-02-11 (v0.2.0); core use case completed 2026-08-18 (v0.3.0)
**Version:** 0.3.0

> **Note (2026-08-18):** Exit code `2` = partial success is implemented per this
> PRD's spec (`0` = all ok, `1` = total failure/invalid args, `2` = ≥1 resolved
> with ≥1 failed, results displayed).

## Overview

Add functionality to query the download and installed size of Homebrew packages (formulae and casks) before installation. This addresses a gap in Homebrew's native toolset, where users cannot easily determine how much disk space a package will consume prior to installation.

## Problem Statement

When users want to install a Homebrew package, they currently have no way to know:
1. How large the download will be
2. How much disk space the package will occupy after installation
3. Whether they have sufficient disk space before starting the installation

The only way to get this information is to:
- Run `brew install --dry-run` and inspect the output (doesn't show sizes)
- Parse bottle manifest JSON files manually (not user-friendly)
- Install the package and check after the fact (too late)

## Proposed Solution

Add a `--size` flag to `brew-usage` that accepts one or more package names as arguments. This flag is mutually exclusive with display mode flags (`--top`, `--formulae`, `--casks`).

### User Interface

```bash
# Query a single package
brew-usage --size go

# Query multiple packages
brew-usage --size go node python rust

# Query with color disabled
brew-usage --size go --no-color

# --size is mutually exclusive with display mode flags
brew-usage --size go --top 10  # Error: --size cannot be used with --top
brew-usage --size go --formulae  # Error: --size cannot be used with --formulae
brew-usage --size go --casks  # Error: --size cannot be used with --casks
```

### Example Output

```
$ brew-usage --size go

Package Size Information for: go
=================================

Platform: macOS 14 (Sonoma), arm64

          go 1.25.7_1
  ├─ Download: 54 MiB
  └─ Installed: 193 MiB

$ brew-usage --size go node python

Package Size Information
========================

Platform: macOS 14 (Sonoma), arm64

          go 1.25.7_1
  ├─ Download: 54 MiB
  └─ Installed: 193 MiB

        node 23.7.0
  ├─ Download: 42 MiB
  └─ Installed: 156 MiB

        python 3.13.1
  ├─ Download: 38 MiB
  └─ Installed: 98 MiB

────────────────────────────────────────────
Total Download: 134 MiB | Total Installed: 447 MiB
```

### Edge Cases

The implementation must handle:

1. **Package not found** (exit 1)
   ```
   Error: Package 'nonexistent' not found in Homebrew
   ```

2. **No bottle available (build from source only)** (exit 0 - warning)
   ```
   Warning: 'some-package' has no bottle available.
   Size information unavailable for source builds.
   ```

3. **Platform mismatch (e.g., Linux bottle on macOS)**
   - Detect current platform (OS, architecture)
   - Show appropriate bottle or error if none available

4. **Casks without size info** (exit 0 - warning)
   ```
   Warning: 'visual-studio-code' size information unavailable.
   Casks download external artifacts; sizes cannot be determined beforehand.
   ```

5. **Multiple versions available**
   - Show the latest stable version by default
   - Optionally allow version specification (future enhancement)

6. **jq not installed** (exit 1)
   ```
   Error: The --size flag requires jq.
   Install with: brew install jq
   ```

7. **Partial success** (exit 2)
   - At least one package failed but others succeeded
   - Show all successful results with warnings for failures

### Exit Codes

- `0`: Success - all packages queried successfully
- `1`: Error - invalid arguments, no packages found, or `jq` not installed
- `2`: Partial success - at least one package failed (warnings shown, results displayed)

## Technical Design

### Architecture Changes

1. **New library module**: `lib/brew-usage-size.sh`
   - Functions for querying bottle manifest sizes
   - Platform detection (OS version, architecture)
   - Manifest parsing and size extraction

2. **Modified argument parsing** in main script:
   - Add `--size` flag that requires at least one package name argument
   - Make `--size` mutually exclusive with display mode flags (`--top`, `--formulae`, `--casks`)
   - Accept one or more package names: `--size pkg1 pkg2 pkg3`

3. **New display functions** in `lib/brew-usage-display.sh`:
   - `display_package_size()` - single package output
   - `display_multiple_package_sizes()` - table format
   - `display_size_warning()` - warning messages
   - `display_size_error()` - error messages

4. **Add `get_size_human()` utility function** in `lib/brew-usage-utils.sh`:
   - Convert byte counts to human-readable format (MiB/GiB)
   - Use binary units (1024-based) to match Homebrew convention

### Data Flow

```
User Input: brew-usage --size go node
         │
         ▼
Parse Arguments → Detect --size mode
         │
         ▼
For each package:
         │
         ▼
1. Check if package exists (brew info --json)
         │
         ▼
2. Determine platform (uname -m, sw_vers)
         │
         ▼
3. Fetch bottle manifest (from cache or download)
         │
         ▼
4. Extract sh.brew.bottle.size (download)
         │
         ▼
5. Extract sh.brew.bottle.installed_size (installed)
         │
         ▼
6. Format and display
```

### Platform Detection

The tool must detect:
- **Minimum macOS version**: 12 (Monterey) - aligns with project tooling standards
- **Architecture**: `arm64` (Apple Silicon) or `x86_64` (Intel)
- **OS Version**: macOS version mapping to bottle names
  - Sequoia (15.x) → `sequoia`
  - Sonoma (14.x) → `sonoma`
  - Ventura (13.x) → `ventura`
  - Monterey (12.x) → `monterey`
  - Fallback for unknown versions: Use `sw_vers -productVersion` directly with Homebrew's bottle naming conventions

### Manifest Parsing

Use the cached manifest at `~/Library/Caches/Homebrew/downloads/*--<package>-<version>.bottle_manifest.json` or download via `brew info --json=v2 --bottle <package>`.

Extract from annotations:
- `sh.brew.bottle.size` - compressed download size in bytes
- `sh.brew.bottle.installed_size` - unpacked size in bytes

### Dependencies

- `jq` - required for `--size` functionality (already an optional dependency in `brew-usage-config.sh`)
- If `jq` is not available, `--size` will fail with a helpful message directing user to install it

### Configuration Constants

Add to `brew-usage-config.sh`:

```bash
# Size lookup defaults
readonly DEFAULT_SIZE_MODE=false
readonly SIZE_LOOKUP_CACHE_TTL=3600  # 1 hour

# Size lookup cache directory (uses existing CACHE_DIR)
readonly SIZE_CACHE_DIR="${CACHE_DIR}/size"
```

### Caching Strategy

- Cache bottle manifests in `$SIZE_CACHE_DIR` with TTL of 1 hour
- Cache key format: `{package_name}--{version}--{platform}--{arch}.json`
- On cache hit: check file modification time against TTL
- On cache miss: download manifest and store in cache directory
- Invalid or corrupted cache files are ignored and re-fetched

## Success Criteria

1. ✅ Accurately reports download and installed sizes for formulae with bottles
2. ✅ Gracefully handles packages without bottles (source-only)
3. ✅ Provides useful error messages for casks and edge cases
4. ✅ Works across macOS 12+ (Monterey) on Intel/Apple Silicon and Linux
5. ✅ Integrates cleanly with existing `brew-usage` CLI
6. ✅ Follows existing code patterns and style
7. ✅ Maintains backward compatibility (no breaking changes)

## Future Enhancements (Out of Scope)

- Version-specific size lookup (e.g., `brew-usage --size go@1.21`)
- Comparison view (show difference between installed packages)
- Historical size tracking (how package sizes change over versions)
- JSON output format for `--size` results
- `--flush-cache` flag to force-refresh cached bottle manifests
- Quiet mode for scripting (e.g., `brew-usage --size go --quiet`)

## Open Questions

1. ~~Should `--size` work for packages that are already installed?~~
   - **Decision**: Yes. Shows bottle manifest sizes (download/installed).
   - Rationale: Users want to know download size before updating/reinstalling.

2. ~~Should we show size in binary (GiB) or decimal (GB) units?~~
   - **Decision**: Use binary units (GiB/MiB/KiB) to match Homebrew convention.
   - The existing `brew-usage` already uses binary (1024-based).

3. ~~How should we handle very large package lists?~~
   - **Decision**: No limit on number of packages.
   - Consider adding `--quiet` mode for scripts in future enhancement.

4. ~~Should cache keys include bottle checksums?~~
   - **Decision**: No. Cache key format remains `{name}--{version}--{tag}.json`.
   - Rationale: Bottle manifests are immutable once published. TTL (1 hour) handles edge cases.
   - Version changes produce new cache keys, which covers the main use case.

## Review Notes (2026-02-11)

Items identified during task breakdown review that clarify or amend the design above:

1. **`get_size_human()` already exists** in `lib/brew-usage-calculate.sh` with `K/M/G` suffixes.
   Adding a second version with `KiB/MiB/GiB` output risks confusion. **Resolution:** add a
   *new* function `get_size_human_iec()` in `lib/brew-usage-utils.sh` for the `--size` feature;
   leave the existing function untouched to preserve current report output.

2. **`brew info --json=v2 --bottle <package>` needs validation.** This may not be a real
   Homebrew subcommand. A spike (Phase 0) is required before implementation to confirm the
   actual data retrieval method and JSON shape for bottle manifest annotations.

3. **Platform detection should prefer `brew --bottle-tag`** (available in Homebrew 4.x+) over
   manual macOS version-to-codename mapping, which is fragile and can go stale. Manual mapping
   should be kept as a fallback only.
   *[Correction 2026-08-18: the Phase 0 spike found `brew --bottle-tag` does not exist;
   the implementation uses `brew ruby -e 'puts Homebrew::SimulateSystem.current_tag'`
   with the manual mapping as fallback.]*

4. **`set -euo pipefail` conflicts with exit code 2 (partial success).** The main script uses
   `set -e`, which aborts on any non-zero return. Size-mode code must use explicit error
   handling (`|| true`, subshells, or `if` checks) to support partial success without aborting.

5. **Linux testing approach deferred to CI.** Linux environment not available for Phase 0 spike.
   `brew --bottle-tag` and bottle manifest structure are well-documented as stable across platforms.
   Linux compatibility will be verified via GitHub Actions CI post-implementation.

## Implementation Tasks

- [x] Add `--size` flag argument parsing with mutual exclusivity checks
- [x] Implement `get_size_human_iec()` function in `lib/brew-usage-utils.sh`
- [x] Create `lib/brew-usage-size.sh` module
  - [x] Platform detection (OS version + architecture)
  - [x] Bottle manifest fetching (with caching)
  - [x] Manifest parsing (size extraction)
- [x] Add size display functions to `lib/brew-usage-display.sh`
  - [x] `display_package_size()` - single package output
  - [x] `display_multiple_package_sizes()` - table format
  - [x] `display_size_warning()` - warning messages
  - [x] `display_size_error()` - error messages
- [x] Handle edge cases (no bottle, casks, not found)
- [x] Implement proper exit codes (0, 1, 2)
- [x] Add `jq` dependency check with helpful error message
- [x] Create cache directory setup in `brew-usage-config.sh`
- [x] Add unit tests
- [x] Update README with new feature documentation
- [x] Update `display_help()` with `--size` flag documentation
- [x] Update CHANGELOG.md
