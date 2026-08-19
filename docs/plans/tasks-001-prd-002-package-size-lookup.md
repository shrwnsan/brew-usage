# Tasks: Package Size Lookup (PRD-002)

**PRD:** [prd-002-package-size-lookup.md](prd-002-package-size-lookup.md)
**Created:** 2026-02-11
**Target Version:** 0.2.0

---

## Phase 0 — Spike: Validate Data Source

> **Goal:** Confirm how to reliably fetch bottle manifest data (download size + installed size) before writing any production code. This phase blocks all subsequent phases.

### Task 0.1: Verify Homebrew manifest retrieval method

**Priority:** Critical — all implementation depends on this
**Estimate:** 1–2 hours

Investigate and document which approach works to get `sh.brew.bottle.size` and `sh.brew.bottle.installed_size`:

(Phase 0 completed retroactively-ticked 2026-08-20; the spike write-up exists as
`docs/plans/spike-bottle-manifest.md` — Status: Complete — and covers all six
bullets, including disproving `brew --bottle-tag`.)

- [x] Test `brew info --json=v2 <formula>` — check if bottle size annotations are included
- [x] Test `brew info --json=v2 --bottle <formula>` — verify this flag exists and its output shape
- [x] Test `brew --bottle-tag` — confirm it returns the correct platform tag (e.g., `arm64_sonoma`)
- [x] Inspect Homebrew's local bottle manifest cache at `~/Library/Caches/Homebrew/downloads/*--*.bottle_manifest.json`
- [x] Test on both arm64 and x86_64 if possible; note Linux differences
- [x] Document the chosen approach, the exact JSON path to size fields, and any platform caveats

**Deliverable:** A short write-up (can be a comment in this file or a `docs/plans/spike-bottle-manifest.md`) with:
1. The exact command(s) to fetch manifest data
2. Sample JSON output with paths to size fields annotated
3. Whether `jq` queries work as expected
4. Any platform-specific concerns

---

## Phase 1 — Foundation: Shared Utilities & Config

> **Goal:** Prepare shared code that later phases depend on. These subtasks are independent of each other and can be done in parallel.

### Task 1.1: Add `get_size_human_iec()` to `lib/brew-usage-utils.sh`

**Estimate:** 30 min
**Status:** ✅ Complete
**Depends on:** Nothing
**Files:** `lib/brew-usage-utils.sh`

The existing `get_size_human()` in `lib/brew-usage-calculate.sh` outputs `K/M/G/T`. The `--size` feature requires IEC units (`KiB/MiB/GiB/TiB`) per PRD output examples.

- [x] Add `get_size_human_iec()` function to `lib/brew-usage-utils.sh`
- [x] Input: byte count (integer)
- [x] Output: human-readable string using binary units — `KiB`, `MiB`, `GiB`, `TiB` (1024-based)
- [x] Handle edge cases: non-numeric input → `"0 B"`, zero → `"0 B"`
- [x] Do NOT modify the existing `get_size_human()` — it's used by the current report output

**Acceptance:**
- `get_size_human_iec 57344` → `"56 KiB"`
- `get_size_human_iec 56623104` → `"54 MiB"`
- `get_size_human_iec 202375168` → `"193 MiB"`
- `get_size_human_iec 1073741824` → `"1.0 GiB"`
- `get_size_human_iec 0` → `"0 B"`

### Task 1.2: Add size-lookup config constants to `lib/brew-usage-config.sh`

**Estimate:** 15 min
**Status:** ✅ Complete
**Depends on:** Nothing
**Files:** `lib/brew-usage-config.sh`

- [x] Add constants after existing config values:
  ```bash
  readonly DEFAULT_SIZE_MODE=false
  readonly SIZE_LOOKUP_CACHE_TTL=3600  # 1 hour
  readonly SIZE_CACHE_DIR="${CACHE_DIR}/size"
  ```
- [x] Add cache directory creation (same pattern as existing `CACHE_DIR` block)
- [x] Do NOT modify existing constants or the `verify_dependencies()` function

### Task 1.3: Add platform detection functions to `lib/brew-usage-utils.sh`

**Estimate:** 30 min
**Status:** ✅ Complete
**Depends on:** Phase 0 (to know if `brew --bottle-tag` is usable)
**Files:** `lib/brew-usage-utils.sh`

- [x] Add `get_bottle_tag()` — returns the platform bottle tag
  - Prefer `brew --bottle-tag` if available (Homebrew 4.x+)
  - Fallback: construct from `uname -m` + macOS version mapping
- [x] Add `get_macos_version_name()` — maps major version to codename
  - 15 → `sequoia`, 14 → `sonoma`, 13 → `ventura`, 12 → `monterey`
  - Unknown → return empty string (caller handles)
- [x] Add `get_platform_display()` — returns human-readable platform string for output header
  - e.g., `"macOS 14 (Sonoma), arm64"` or `"Linux, x86_64"`

---

## Phase 2 — Core: Size Lookup Module

> **Goal:** Implement the data-fetching and parsing logic as a self-contained module. No display or CLI integration yet.

### Task 2.1: Create `lib/brew-usage-size.sh` — manifest fetching

**Estimate:** 1–2 hours
**Status:** ✅ Complete
**Depends on:** Phase 0 (data source decision), Task 1.2 (cache config), Task 1.3 (platform detection)
**Files:** `lib/brew-usage-size.sh` (new file)

- [x] Add `check_size_dependencies()` — verify `jq` is installed; return 1 with helpful message if not
- [x] Add `fetch_bottle_manifest()` — fetch manifest JSON for a given formula
  - Check `$SIZE_CACHE_DIR` for cached copy (key: `{name}--{version}--{tag}.json`)
  - Validate cache freshness against `SIZE_LOOKUP_CACHE_TTL`
  - On miss: fetch via the method validated in Phase 0
  - Store result in cache
  - Return path to cached JSON file
- [x] Handle `stat` platform differences for mtime check (macOS vs Linux)

**Acceptance:**
- Calling `fetch_bottle_manifest "go"` writes a JSON file to `$SIZE_CACHE_DIR` and prints the path
- Second call within TTL returns cached path without re-fetching
- Returns non-zero if formula doesn't exist or has no bottle

### Task 2.2: Create `lib/brew-usage-size.sh` — manifest parsing

**Estimate:** 1 hour
**Status:** ✅ Complete
**Depends on:** Task 2.1
**Files:** `lib/brew-usage-size.sh`

- [x] Add `extract_package_sizes()` — parse manifest JSON to extract sizes
  - Input: package name
  - Output: `name|version|download_bytes|installed_bytes|status`
  - `status`: `ok`, `no_bottle`, `not_found`, `cask_unsupported`
- [x] Add `lookup_package_size()` — orchestrator for a single package
  - Check if formula exists via `brew info --json=v2`
  - If it's a cask, return `cask_unsupported` status
  - If formula has no bottle for current platform, return `no_bottle` status
  - Otherwise, fetch manifest and extract sizes
- [x] Add `lookup_multiple_package_sizes()` — loop over package list
  - Collect results into an output array (one line per package)
  - Track success/warning/failure counts for exit code determination

**Acceptance:**
- `lookup_package_size "go"` → `"go|1.25.7_1|56623104|202375168|ok"` (sizes will vary)
- `lookup_package_size "nonexistent"` → `"nonexistent|||0|0|not_found"`
- `lookup_package_size "visual-studio-code"` → `"visual-studio-code|||0|0|cask_unsupported"`

---

## Phase 3 — CLI Integration: Argument Parsing & Display

> **Goal:** Wire the size module into the CLI. These subtasks are independent and can be done in parallel.

### Task 3.1: Add `--size` argument parsing to `brew-usage`

**Estimate:** 45 min
**Status:** ✅ Complete
**Depends on:** Nothing (just needs to set variables; actual size logic comes from sourced module)
**Files:** `brew-usage`

- [x] Add a `MODE` variable (default: `"usage"`) and `SIZE_PACKAGES=()` array
- [x] Add `--size` case in the argument parser:
  - Set `MODE="size"`
  - Consume all subsequent non-flag arguments into `SIZE_PACKAGES`
  - Stop consuming at next `-*` flag or end of args
- [x] Add mutual exclusivity checks:
  - If `MODE="size"` and any of `--top`, `--formulae`, `--casks` are encountered → error + exit 1
  - If `--top`, `--formulae`, or `--casks` already set and `--size` encountered → error + exit 1
- [x] Validate at least one package name provided after `--size` → error + exit 1 if empty
- [x] After parsing, if `MODE="size"`:
  - Source `lib/brew-usage-size.sh`
  - Call `check_size_dependencies` (jq check)
  - Call the size display pipeline (Task 3.2) instead of the normal usage report
  - Exit with appropriate code
- [x] Preserve all existing behavior when `--size` is not used

**Acceptance:**
- `brew-usage --size go` → enters size mode
- `brew-usage --size go node python` → SIZE_PACKAGES has 3 entries
- `brew-usage --size go --no-color` → size mode with color disabled
- `brew-usage --size` → error: no packages specified
- `brew-usage --size go --top 10` → error: mutually exclusive
- `brew-usage --formulae --size go` → error: mutually exclusive
- `brew-usage --top 5` → normal usage mode (unchanged behavior)

### Task 3.2: Add size display functions to `lib/brew-usage-display.sh`

**Estimate:** 1 hour
**Status:** ✅ Complete
**Depends on:** Task 1.1 (`get_size_human_iec`)
**Files:** `lib/brew-usage-display.sh`

- [x] Add `display_size_header()` — print header with platform info
  - Single package: `"Package Size Information for: <name>"`
  - Multiple packages: `"Package Size Information"`
  - Include platform line: `"Platform: macOS 14 (Sonoma), arm64"`
- [x] Add `display_package_size()` — single package block
  - Right-align package name + version
  - Tree-style lines: `├─ Download:` and `└─ Installed:`
  - Use `get_size_human_iec()` for size values
  - Color-code sizes using existing `get_size_color()`
- [x] Add `display_size_totals()` — summary line for multiple packages
  - Separator line: `────────────────────────────────────────────`
  - `"Total Download: X MiB | Total Installed: Y MiB"`
- [x] Add `display_size_warning()` — warning messages (yellow)
  - No bottle: `"Warning: '<pkg>' has no bottle available.\nSize information unavailable for source builds."`
  - Cask: `"Warning: '<pkg>' size information unavailable.\nCasks download external artifacts; sizes cannot be determined beforehand."`
- [x] Add `display_size_error()` — error messages (red, to stderr)
  - Not found: `"Error: Package '<pkg>' not found in Homebrew"`
  - jq missing: `"Error: The --size flag requires jq.\nInstall with: brew install jq"`
- [x] Update `display_help()` — add `--size` flag documentation
  ```
      --size PKG [PKG...]  Show download and installed size for packages
  ```
  Add example:
  ```
    brew-usage --size go node     # Show package sizes before installing
  ```

**Acceptance:**
- Output matches PRD examples (single and multiple package formats)
- Colors respect `--no-color` flag
- Warning/error messages go to stderr

### Task 3.3: Implement exit code logic

**Estimate:** 30 min
**Status:** ✅ Complete
**Depends on:** Task 2.2 (status field from lookup), Task 3.1 (mode detection)
**Files:** `brew-usage`

- [x] After processing all packages in size mode, determine exit code:
  - All succeeded → exit 0
  - All failed (not_found for every package) → exit 1
  - Mixed (some ok, some failed/warning) → exit 2
- [x] "Warnings" (`no_bottle`, `cask_unsupported`) count as success for exit code purposes, not failure
- [x] Wrap size-mode operations in functions to avoid `set -e` aborting on partial failures
  - Use `|| true` or explicit return code checks on brew/jq calls

---

## Phase 4 — Polish: Documentation & Tests

> **Goal:** Update docs and add test coverage. Subtasks are independent.

### Task 4.1: Update README.md

**Estimate:** 30 min
**Status:** ✅ Complete
**Depends on:** Phase 3 complete
**Files:** `README.md`

- [x] Add `--size` to the Features list
- [x] Add usage examples for `--size` (single and multiple packages)
- [x] Add `jq` as an optional dependency (required for `--size`)
- [x] Update the architecture tree to include `lib/brew-usage-size.sh`

### Task 4.2: Update CHANGELOG.md

**Estimate:** 15 min
**Status:** ✅ Complete
**Depends on:** Phase 3 complete
**Files:** `CHANGELOG.md`

- [x] Add `[0.2.0] - YYYY-MM-DD` entry under `## [Unreleased]`
- [x] List all added features:
  - `--size` flag for pre-install package size lookup
  - Platform detection and bottle tag resolution
  - Bottle manifest caching
  - IEC unit formatting (`MiB/GiB`)
- [x] Update version statistics table

### Task 4.3: Add unit tests for utility functions

**Estimate:** 1 hour
**Status:** ✅ Complete
**Depends on:** Task 1.1, Task 1.3
**Files:** `tests/test-utils.sh` (new file) [Correction 2026-08-18: the file was actually created as `tests/test-size.sh`]

- [x] Test `get_size_human_iec()` with known byte values
- [x] Test `get_bottle_tag()` output format
- [x] Test `get_macos_version_name()` mapping
- [x] Test `get_platform_display()` output
- [x] Use simple bash assertions (no external test framework needed — match existing project style)
- [x] Make test script executable and self-contained

### Task 4.4: Add integration tests for size lookup

**Estimate:** 1–2 hours
**Status:** ✅ Complete
**Depends on:** Phase 2 + Phase 3
**Files:** `tests/test-size-lookup.sh` (new file)

- [x] Test `--size` with a known formula (e.g., `jq` since it's required anyway)
- [x] Test `--size` with a nonexistent package → exit 1
- [x] Test `--size` mutual exclusivity with `--top` → exit 1
- [x] Test `--size` mutual exclusivity with `--formulae` → exit 1
- [x] Test `--size` with no package args → exit 1
- [x] Test `--size` with `--no-color` → no ANSI codes in output
- [x] Add fixture JSON manifest for offline parsing tests if feasible

### Task 4.5: Update syntax check script

**Estimate:** 10 min
**Status:** ✅ Complete
**Depends on:** Task 2.1 (new .sh file exists)
**Files:** `scripts/syntax-check.sh`

- [x] Verify the existing `lib/*.sh` glob already picks up `lib/brew-usage-size.sh` (it should — no changes needed unless the glob is hardcoded)
- [x] Run syntax check and confirm it passes

---

## Dependency Graph

```
Phase 0: Spike
  └─ Task 0.1 ─────────────────────────────────────────┐
                                                        │
Phase 1: Foundation (parallel after Phase 0)            │
  ├─ Task 1.1 (get_size_human_iec)          ──────────┐ │
  ├─ Task 1.2 (config constants)            ────────┐ │ │
  └─ Task 1.3 (platform detection)  ←── Phase 0 ─┐ │ │ │
                                                  │ │ │ │
Phase 2: Core (after Phase 1)                     │ │ │ │
  ├─ Task 2.1 (manifest fetching)   ←── 1.2, 1.3 ┘ │ │ │
  └─ Task 2.2 (manifest parsing)    ←── 2.1 ────────┘ │ │
                                                       │ │
Phase 3: CLI Integration (parallel within phase)       │ │
  ├─ Task 3.1 (arg parsing)         ←── (standalone)   │ │
  ├─ Task 3.2 (display functions)   ←── 1.1 ──────────┘ │
  └─ Task 3.3 (exit codes)          ←── 2.2, 3.1 ───────┘
                                                          
Phase 4: Polish (parallel, after Phase 3)                 
  ├─ Task 4.1 (README)                                    
  ├─ Task 4.2 (CHANGELOG)                                 
  ├─ Task 4.3 (unit tests)                                
  ├─ Task 4.4 (integration tests)                         
  └─ Task 4.5 (syntax check)                              
```

## Parallelism Summary

| Phase | Parallel Subtasks | Sequential Dependencies |
|-------|-------------------|------------------------|
| 0     | —                 | Must complete before all others |
| 1     | 1.1 ∥ 1.2 ∥ 1.3  | 1.3 needs Phase 0 findings |
| 2     | —                 | 2.1 → 2.2 (sequential) |
| 3     | 3.1 ∥ 3.2         | 3.3 waits for 2.2 + 3.1 |
| 4     | 4.1 ∥ 4.2 ∥ 4.3 ∥ 4.4 ∥ 4.5 | All independent |

## PRD Observations

Items noted during review that deviate from or clarify the PRD:

1. **`get_size_human()` already exists** in `lib/brew-usage-calculate.sh` with `K/M/G` output. PRD asks for it in `utils` with `MiB/GiB` output. Resolution: add a *new* `get_size_human_iec()` in utils; leave existing function untouched to avoid breaking current output.

2. **`brew info --json=v2 --bottle` may not exist** as a valid Homebrew command. Phase 0 spike must validate the actual data retrieval method before implementation begins.

3. **Platform tag mapping is fragile.** PRD manually maps macOS versions to codenames. Prefer `brew --bottle-tag` (Homebrew 4.x+) with manual mapping as fallback only.

4. **`set -euo pipefail` conflicts with partial success.** The main script uses `set -e`, which will abort on any non-zero return. Size-mode code must explicitly handle errors (e.g., `|| true`, subshells, or explicit `if` checks) to support exit code 2 (partial success).

5. **Tests directory is empty.** PRD lists "Add unit tests" but there's no test framework. Tasks 4.3/4.4 establish a minimal bash test approach.

6. **Cache design confirmed.** Decision made to not include bottle checksums in cache keys. Cache key format remains `{name}--{version}--{tag}.json`. Rationale: bottle manifests are immutable once published; TTL handles edge cases; version changes produce new cache keys.

7. **Linux testing deferred.** No Linux environment available for Phase 0 spike. `brew --bottle-tag` output is well-documented and stable across platforms (`{arch}_{osname}` format). Linux compatibility will be verified via GitHub Actions CI after implementation.

## Implementation Notes

### Additional Fixes (2026-02-11)

During macOS testing, the following issues were identified and fixed:

1. **Module loaded flags missing** - The `brew-usage-size.sh` module checked for `BREW_USAGE_CONFIG_LOADED` and `BREW_USAGE_UTILS_LOADED` before sourcing dependencies, but the config and utils modules never set these flags. This caused "readonly variable" errors when modules were sourced multiple times.
   - Fixed by adding `readonly BREW_USAGE_CONFIG_LOADED=true` at the end of `lib/brew-usage-config.sh`
   - Fixed by adding `readonly BREW_USAGE_UTILS_LOADED=true` at the end of `lib/brew-usage-utils.sh`

2. **Version revision suffix handling** - Brew info returns `1.25.7` but manifest files are named with revision suffix like `go-1.25.7_1.bottle_manifest.json`. The code needed to extract the revision from `brew info --json=v2` and append it to the version string.
   - Fixed by extracting `revision` from brew info and appending `_revision` when non-zero
   - Fixed manifest search pattern to use wildcard for version matching to handle optional `_revision` suffix

### Test Results

**macOS (arm64_tahoe):**
- Unit tests: 15/15 passed
- Functional tests:
  - `brew-usage --size go` → 54.9 MiB download, 193.9 MiB installed ✓
  - `brew-usage --size node` → 17.4 MiB download, 73.8 MiB installed ✓
  - `brew-usage --size jq` → 414.2 KiB download, 1.2 MiB installed ✓
  - `brew-usage --size go node` → table format with both packages ✓
