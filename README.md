# brew-usage

Homebrew Disk Usage Analyzer - Shows disk usage information for installed Homebrew packages.

## Overview

`brew-usage` provides detailed breakdowns of storage consumption across formulas and casks - functionality not available in native Homebrew commands.

## Features

- Per-package size breakdown (formulae and casks)
- Sort by size or name (`-s`, `--sort size|name`)
- Color output with `--no-color` opt-out
- Environment diagnostics with suggested fixes (`doctor`, `-d`, `--doctor`; read-only)
  plus dry-run repair planning (`doctor --fix`, apply with `--fix --yes`; installs
  opt in with `--fix --yes --install`)
- Doctor plugin hooks: user-supplied extra checks from `~/.brew-usage-doctor.d/`
  (override via `$BREW_USAGE_DOCTOR_DIR`) become first-class checks in a
  "plugins" group, with a 5-second timeout per plugin; scripts are EXECUTED,
  never sourced (contract: exit 0/2/1 maps to pass/warn/fail, first stdout line
  = detail)
- Package size lookup from bottle manifests (`--size`), with exact-version
  pinning (`--size go@1.26.6`) and installed-vs-latest upgrade deltas
  (`--size go --compare`)
- Local size history: record installed-package sizes (`--snapshot`) and
  diff the last two recordings (`--history` — top movers, added/removed;
  newest 90 snapshots kept)
- Homebrew cache analysis with cleanup candidates (`-C`, `--cache`; read-only)
- Machine-readable JSON output for scripting (`--json`, composes with both modes)
- Show-all listing with terminal paging (`-a`, `--all`)
- Optional `~/.brew-usage-config` for default overrides (strictly parsed, never sourced)
- Top N filtering by size (default: 10)
- Human-readable size formatting (B, K, M, G)
- Total aggregation by category
- Cross-platform compatibility (macOS/Linux)
- Modular bash architecture for easy maintenance

## 🚀 Installation

```bash
# Install directly via Homebrew tap
brew install shrwnsan/tap/brew-usage

# Verify installation
brew-usage --version
```

## 📖 Usage

```bash
# Show top 10 largest packages (default)
brew-usage

# Show top 20 largest packages
brew-usage --top 20

# Show top 5 largest packages
brew-usage -t 5

# Show every installed package (no top-N cut), paged on a terminal
brew-usage --all

# Sort packages by name instead of size
brew-usage --sort name

# Disable color output (e.g., for dumb terminals or plain-text logs)
brew-usage --no-color

# Show bottle manifest size for a package
brew-usage --size go

# Show sizes for multiple packages
brew-usage --size go node python

# Machine-readable JSON output (report mode)
brew-usage --json

# JSON output composes with report flags
brew-usage --json --top 3 --formulae

# Machine-readable JSON output (size mode)
brew-usage --size --json go node

# Homebrew cache analysis (standalone)
brew-usage --cache

# Report with the cache section appended (after Casks)
brew-usage --formulae --cache

# Diagnose the brew-usage environment (read-only, suggests fixes)
brew-usage doctor

# Diagnostics as JSON
brew-usage doctor --json

# Plan repairs for fixable findings (dry run — nothing applied)
brew-usage doctor --fix

# Apply the planned repairs, then re-run doctor and show the after report
brew-usage doctor --fix --yes

# Also consent to install-tier fixes (installs jq when missing)
brew-usage doctor --fix --yes --install

# Fix plan as JSON (fixes array embedded in the report)
brew-usage doctor --fix --json

# doctor cross-checks brew-change's export when present (absent = non-event):
# manifests stale vs upstream changes warn; --fix removes exactly those
brew-usage doctor

# Pin an exact version (falls back from formula lookup)
brew-usage --size go@1.26.6

# Compare installed vs latest bottle size (upgrade disk delta)
brew-usage --size go node --compare

# Record installed sizes to the local history (du-based, local-only)
brew-usage --snapshot

# Diff the last two snapshots: top movers, added/removed packages
brew-usage --history

# Show help
brew-usage --help

# Show version
brew-usage --version
```

### Package Size Lookup (`--size`)

The `--size` flag shows download and installed sizes from Homebrew bottle manifests:

```bash
$ brew-usage --size go

go 1.25.7
  Platform:      arm64_sonoma
  Download:      54.9 MiB
  Installed:     193.9 MiB
```

**Note**: `--size` mode requires `jq` for JSON parsing. Install with:
```bash
brew install jq
```

If the bottle manifest is not already in the local Homebrew cache, it is
downloaded from ghcr.io — so `--size` works for packages that have never been
installed on this machine (network required for uncached packages; cached
manifests are reused for 1 hour).

**Exit codes** for `--size`: `0` = all packages resolved, `1` = invalid
arguments or no package resolved, `2` = partial success (at least one package
resolved and at least one failed; successful results are still displayed).

#### Single-value output (`--size --quiet FIELD`)

For scripting, `--quiet FIELD` (FIELD: `download` or `installed`) prints one
value per package — in argument order, no color, no decorations. Failed or
not-found packages print nothing on stdout (their story stays on stderr and
in the unchanged 0/1/2 exit codes):

```bash
$ brew-usage --size go node --quiet installed
193.9 MiB
141.7 MiB
```

`--quiet` is only valid with `--size`, is mutually exclusive with `--json`,
and an unknown field exits 1.

#### Flushing the manifest cache (`--flush-cache`)

`brew-usage --size` caches bottle manifests in the Homebrew downloads cache
under its own `name--version--tag.json` naming. `--flush-cache` removes only
those files (never Homebrew's `*bottle_manifest.json` originals or anything
else in that directory) and prints the count:

```bash
$ brew-usage --flush-cache
3 cached manifests removed
```

`--flush-cache` is a standalone mode — it conflicts with every other mode
flag (exit 1). Doctor suggests it when expired manifests are present.

### JSON Output (`--json`)

The `--json` flag produces machine-readable output in both report mode and
`--size` mode, and composes with `--top N`, `--formulae`, `--casks`, and
`--size`. Color and decorations are disabled automatically. Omitted sections
(e.g. `casks` with `--formulae`) are absent from the document.

Report mode:
```json
{
  "formulae": {
    "packages": [{"name": "go", "size": 203292092, "size_human": "193.9M"}],
    "total_bytes": 203292092,
    "total_human": "193.9M"
  },
  "casks": {"packages": [], "total_bytes": 0, "total_human": "0B"},
  "grand_total_bytes": 203292092,
  "grand_total_human": "193.9M"
}
```

Size mode — `status` is `ok`, `not_found`, or `no_bottle`; warnings and errors
go to stderr so stdout stays valid JSON even on partial failure (exit codes
unchanged: 0/1/2):
```json
{
  "packages": [
    {"name": "go", "version": "1.25.7", "download_size": 57531075,
     "installed_size": 203292092, "platform": "1.25.7.arm64_sonoma", "status": "ok"}
  ]
}
```

**Note**: `--json` requires `jq` (install with `brew install jq`).

### Cache Analysis (`-C`, `--cache`)

The `--cache` flag analyzes the Homebrew download cache (resolved via
`brew --cache`, falling back to `$HOMEBREW_CACHE` or the platform default).
It reports the total cache size, file count, a downloads-vs-other breakdown,
and cleanup candidates — files older than 30 days (`CACHE_CLEANUP_DAYS`):

```bash
$ brew-usage --cache

🗑️ Cache (Homebrew downloads)
   2.5G    Total cache size (412 files)
   2.1G    Downloads
   400.0M  Other
   ───────────────
   1.2G    Cleanup candidates: 1.2G (87 files)
Suggestion: run `brew cleanup --prune=30` to reclaim
```

`--cache` is strictly **read-only** — it never deletes anything; reclaiming
space is left to `brew cleanup`. With `--json`, a `cache` block
(`total_bytes`, `total_human`, `cleanup_candidates_bytes`,
`cleanup_candidates_human`, `file_count`) is emitted, and the grand total
includes cache bytes whenever the cache section is shown. `--cache` is
mutually exclusive with `--size` (exit 1).

### Show All Packages (`--all` / `-a`)

`--all` removes the top-N cut and lists every installed package. When stdout
is a terminal the report is paged through `${PAGER:-less}` (plain output when
piped, and never paged for `--json`, which emits full arrays):

```bash
brew-usage --all          # every formula and cask, paged
brew-usage --formulae -a  # every formula
brew-usage --all --json   # full JSON arrays, no pager
```

`--all` is mutually exclusive with `--top` and `--size` (exit 1, any order).

### Configuration File

An optional `~/.brew-usage-config` customizes defaults with `KEY=VALUE` lines
(numeric values only). Supported keys:

```bash
# ~/.brew-usage-config
TOP_N=20                    # default number of packages to show
SIZE_WARNING_THRESHOLD=52428800     # yellow color at >= 50MB
SIZE_CRITICAL_THRESHOLD=2147483648  # red color at >= 2GB
CACHE_CLEANUP_DAYS=14       # cache cleanup candidates older than 14 days
```

- **Precedence**: CLI flags > config file > built-in defaults
  (e.g. `--top 5` beats `TOP_N=20`).
- **Safety**: the file is strictly parsed, never sourced — only lines matching
  `KEY=number` with a known key are applied. Malformed lines and unknown keys
  produce a warning on stderr and are ignored; nothing is ever executed.
- The location can be overridden with the `BREW_USAGE_CONFIG_FILE`
  environment variable (used by the test suite).

## 🏗️ Architecture

```
brew-usage/
├── brew-usage                      # Main entry point
├── lib/
│   ├── brew-usage-config.sh        # Configuration & defaults
│   ├── brew-usage-scan.sh          # Package discovery
│   ├── brew-usage-calculate.sh     # Portable size calculation
│   ├── brew-usage-display.sh       # Output formatting
│   ├── brew-usage-size.sh          # Bottle manifest size lookup
│   ├── brew-usage-json.sh          # JSON output (--json)
│   ├── brew-usage-cache.sh         # Cache analysis (-C/--cache)
│   ├── brew-usage-doctor.sh        # Environment diagnostics (doctor)
│   ├── brew-usage-history.sh       # Size history (--snapshot/--history)
│   └── brew-usage-utils.sh         # Shared utilities
├── tests/
│   ├── test-all.sh                 # Report + --all tests
│   ├── test-config.sh              # Config file tests
│   ├── test-size.sh                # Size lookup unit tests
│   ├── test-size-lookup.sh         # Size lookup integration tests
│   ├── test-size-version.sh        # Version-pinned --size tests
│   ├── test-size-compare.sh        # --size --compare tests
│   ├── test-snapshot.sh            # --snapshot/--history tests
│   ├── test-json-output.sh         # JSON output tests
│   ├── test-cache.sh               # Cache analysis tests
│   ├── test-doctor.sh              # Doctor diagnostics tests
│   ├── test-doctor-fix.sh          # doctor --fix / --yes tests
│   ├── test-doctor-plugins.sh      # Doctor plugin hooks tests (PRD-009)
│   └── test-flush-cache.sh         # --flush-cache tests
├── .github/workflows/ci.yml        # CI: lint, unit, macOS + Linux integration
├── LICENSE                         # Apache-2.0 License
└── README.md                       # This file
```

## 📦 Dependencies

- **Homebrew**: Core package manager
- **bash**: Version 3.2+ (stock macOS `/bin/bash` works)
- **jq** (optional): Required for `--size` and `--json` modes (install with `brew install jq`)

## 🌐 Platform Support

brew-usage works seamlessly across all platforms where Homebrew is available:

| Platform | Homebrew Path | Status |
|----------|---------------|--------|
| **macOS (Intel)** | `/usr/local/bin/brew` | ✅ Fully supported |
| **macOS (Apple Silicon)** | `/opt/homebrew/bin/brew` | ✅ Fully supported |
| **Linux** | `/home/linuxbrew/.linuxbrew/bin/brew` | ✅ Fully supported |
| **WSL** | `/home/linuxbrew/.linuxbrew/bin/brew` | ✅ Fully supported |

The script automatically detects the correct library path using `brew --prefix`, ensuring compatibility across all Homebrew installations.

## 📈 Recent Updates

- **v0.13.0**: brew-change cross-check — doctor reads brew-change's versioned export (`~/.brew-change/last-assessment.json`) and warns when cached manifests are stale vs upstream changes; `doctor --fix` removes exactly those files (brew-change absent/unsupported = non-event)
- **v0.12.0**: doctor plugin hooks — user-supplied extra checks from `~/.brew-usage-doctor.d/` become first-class checks in a "plugins" group, with a 5-second timeout per plugin (exit 0/2/1 maps to pass/warn/fail, first stdout line = detail; scripts EXECUTED, never sourced; `--json` composes)
- **v0.11.0**: size history — `--snapshot` records installed sizes to a local append log (newest 90 kept); `--history` diffs the last two (top movers, added/removed; `--json` composes)
- **v0.10.0**: `--size --compare` — installed vs latest bottle size and the upgrade disk delta per package (`ok`/`up_to_date`/`partial`/`not_installed` statuses; composes with `--json`)
- **v0.9.0**: `doctor --fix` install tier — `brew install jq` when jq is missing, behind an explicit `--fix --yes --install` opt-in (planned but skipped without it)
- **v0.8.0**: `doctor --fix` config repair tier (comment-out only, backup + atomic, symlink-safe); `doctor --fix --json` composition; version-specific `--size name@version`
- **v0.7.0**: `doctor --fix` dry-run repair planning (own-state fixes only) + `--fix --yes` surgical apply with after report
- **v0.6.1**: `--quiet FIELD` scripting output for `--size`; `--flush-cache` manifest cache removal (doctor suggests it when expired)
- **v0.6.0**: `brew-usage doctor` — 14 read-only environment checks with suggested fixes, `--json` support
- **v0.5.2**: Security hardening for `--size` inputs (name/version validation, jq `--arg`, escape-stripped config warnings)
- **v0.5.1**: Linux `--size` stat fix; `integration-linux` CI job
- **v0.5.0**: `--sort name` implemented; exec-bit CI gate
- **v0.4.1**: Fixed `--all` pager ANSI passthrough (`less -R`)
- **v0.4.0**: `--json` output, cache analysis (`-C`), `--all` with pager, `~/.brew-usage-config`; report mode fixed on stock macOS bash 3.2
- **v0.3.0**: `--size` downloads manifests from ghcr.io (works pre-install); exit code 2 = partial success; CI
- **v0.2.0**: Added `--size` flag for bottle manifest size lookup
- **v0.1.1**: Fixed ANSI color code output
- **v0.1.0**: Initial release with formulae and cask disk usage analysis, cross-platform support

**Full changelog**: [CHANGELOG.md](CHANGELOG.md)

## License

Apache-2.0 License - see [LICENSE](LICENSE) file.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

shrwnsan

## See Also

- [brew-change](https://github.com/shrwnsan/brew-change) - Changelog tracking for Homebrew packages
