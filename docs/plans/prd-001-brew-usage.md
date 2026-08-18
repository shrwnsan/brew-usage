# PRD 001: brew-usage - Homebrew Disk Usage Analyzer

**Last Updated:** 2026-08-18
**Version:** 1.1.0
**Status:** Released (v0.4.0)

## Overview

Complete disk usage analysis tool for Homebrew installations. `brew-usage` provides detailed breakdowns of storage consumption across formulas, casks, and cache - functionality not available in native Homebrew commands.

## Problem Statement

Homebrew lacks built-in disk usage reporting for installed packages. Users cannot easily:
- Identify which packages consume the most space
- See total disk usage by formulae vs casks
- Understand cache footprint and cleanup opportunities
- Make informed decisions about package removal

## Solution

A standalone command-line tool that provides comprehensive disk usage analysis for Homebrew installations, with:
- Per-package size breakdown (formulae and casks)
- Cache analysis with cleanup recommendations
- Unified view of total Homebrew footprint
- Cross-platform compatibility (macOS/Linux)
- Fast, parallel processing

## Scope

### In Scope
- Formulae disk usage (`$(brew --prefix)/Cellar/`)
- Cask disk usage (`$(brew --prefix)/Caskroom/`)
- Cache analysis (`$(brew --cache)`)
- Human-readable formatting with sorting
- Total aggregation by category
- Cleanup recommendations for cache

### Out of Scope
- Package removal functionality (use `brew uninstall`)
- Dependency analysis (use `brew deps`)
- Update information (use `brew-change`)
- Installation tracking

## Architecture

### Repository Structure

```
brew-usage/
├── brew-usage                      # Main entry point (executable)
├── lib/
│   ├── brew-usage-config.sh        # Configuration & defaults
│   ├── brew-usage-scan.sh          # Package discovery
│   ├── brew-usage-calculate.sh     # Portable size calculation
│   ├── brew-usage-display.sh       # Output formatting
│   └── brew-usage-utils.sh         # Shared utilities
├── LICENSE                         # Apache-2.0 License
└── README.md                       # Project overview
```

### Module Responsibilities

**brew-usage-config.sh**
- Load configuration from ~/.brew-usage-config (optional)
- Define default thresholds and paths
- Handle platform-specific path detection
- Export configuration via environment variables

**brew-usage-scan.sh**
- Discover installed formulae via `brew list --formula`
- Discover installed casks via `brew list --cask`
- Validate package existence and accessibility
- Return scanned package list

**brew-usage-calculate.sh**
- Calculate individual package sizes (portable `du` handling)
- Aggregate totals by category (formulae, casks, cache)
- Handle platform-specific `du` commands (macOS BSD vs GNU)
- Return size data in bytes and human-readable format

**brew-usage-cache.sh** (delivered v0.4.0)
- Analyze cache directory size and contents
- Identify cleanup opportunities based on age
- Calculate potential space recovery
- Provide cleanup command suggestions

**brew-usage-display.sh**
- Format output with categories and sorting
- Display totals and summaries

**brew-usage-utils.sh**
- Shared utility functions
- Error handling and logging
- Platform detection

## Cross-Platform Compatibility

### Platform Support

| Platform | Homebrew Path | `du` Type | Status |
|----------|---------------|-----------|--------|
| macOS (Intel) | `/usr/local/bin/brew` | BSD du | Supported |
| macOS (Apple Silicon) | `/opt/homebrew/bin/brew` | BSD du | Supported |
| Linux | `/home/linuxbrew/.linuxbrew/bin/brew` | GNU du | Supported |
| WSL | `/home/linuxbrew/.linuxbrew/bin/brew` | GNU du | Supported |

### Portable `du` Implementation

```bash
# brew-usage-calculate.sh
get_size_bytes() {
    local path="$1"

    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use du -k and convert KB to bytes
        echo $(($(du -sk "$path" 2>/dev/null | awk '{print $1}') * 1024))
    else
        # Linux: use du -b directly (GNU du)
        echo $(($(du -sb "$path" 2>/dev/null | awk '{print $1}')))
    fi
}

get_size_human() {
    local bytes="$1"

    if (( bytes >= 1073741824 )); then
        awk -v size="$bytes" 'BEGIN { printf "%.1fG", size/1073741824 }'
    elif (( bytes >= 1048576 )); then
        awk -v size="$bytes" 'BEGIN { printf "%.1fM", size/1048576 }'
    elif (( bytes >= 1024 )); then
        awk -v size="$bytes" 'BEGIN { printf "%.1fK", size/1024 }'
    else
        echo "${bytes}B"
    fi
}
```

## Command-Line Interface

### Usage

```bash
brew-usage [OPTIONS]
```

### Options

| Option | Description | Status |
|--------|-------------|--------|
| `-h, --help` | Show help message | Implemented |
| `-t, --top N` | Show top N packages by size (default: 10) | Implemented |
| `-s, --sort` | Sort order: size, name (default: size) | Parsed (name-order not yet implemented; always sorts by size) |
| `--no-color` | Disable color output | Implemented |
| `-v, --version` | Show version information | Implemented |
| `-f, --formulae` | Show formulae only | Implemented |
| `-c, --casks` | Show casks only | Implemented |
| `-a, --all` | Show all packages with pagination | Implemented |
| `-C, --cache` | Show cache analysis only | Implemented |
| `--json` | Output in JSON format | Implemented |

### Examples

```bash
# Show top 10 largest packages (default)
brew-usage

# Show top 20 largest packages
brew-usage --top 20

# Show top 5 largest packages
brew-usage -t 5

# Show version information
brew-usage --version

# Show help
brew-usage --help

# Show all packages with pagination
brew-usage --all

# Show only formulae
brew-usage --formulae

# Show cache analysis with cleanup suggestions
brew-usage --cache

# JSON output for scripting
brew-usage --json
```

## Output Format

### Default Output (Human-Readable)

```
Homebrew Usage Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Formulae (Cellar)
  499.2M  aider
   13.0M  bash
   10.2M  aom
    8.1M  autoconf
    5.3M  cairo
   ────────────────
  Total: 8.5G

Casks (Caskroom)
  250.3M  visual-studio-code
  180.1M  docker
  120.5M  slack
   95.2M  rectangle
   80.1M  1password
   ────────────────
  Total: 995.0M

Cache (~/Library/Caches/Homebrew) - Phase 2
  Total cache size: N/A
  Cleanup candidates: N/A

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Grand Total: 9.5G
```

### JSON Output (Phase 2)

```json
{
  "formulae": {
    "packages": [
      {"name": "aider", "size": 499000000, "size_human": "499M"},
      {"name": "bash", "size": 13000000, "size_human": "13M"}
    ],
    "total_bytes": 8500000000,
    "total_human": "8.5G"
  },
  "casks": {
    "packages": [
      {"name": "visual-studio-code", "size": 250000000, "size_human": "250M"}
    ],
    "total_bytes": 994000000,
    "total_human": "994M"
  },
  "cache": {
    "total_bytes": 11000000000,
    "total_human": "11G",
    "cleanup_candidates": 8200000000,
    "cleanup_candidates_human": "8.2G"
  },
  "grand_total_bytes": 20500000000,
  "grand_total_human": "20.5G"
}
```

## Dependencies

- **Homebrew**: Core package manager
- **bash**: Version 4.0+ for associative arrays
- **jq**: JSON parsing (for JSON output mode only)

## Implementation Roadmap

### Phase 1: MVP (Minimum Viable Product) ✅ COMPLETE (v0.1.0)
- [x] Basic formulae size calculation
- [x] Basic cask size calculation
- [x] Human-readable output with sorting
- [x] Total aggregation
- [x] Help system
- [x] Version information
- [x] Apache-2.0 licensing
- [x] Modular architecture (lib/ modules)
- [x] Cross-platform `du` handling (macOS/Linux)

### Phase 2: Enhanced Features ✅ COMPLETE (v0.4.0)
- [x] Show all packages with pagination (`--all` / `-a`)
- [x] Separate formulae/casks display (`--formulae` / `--casks`) (already delivered in v0.1.0)
- [x] Cache analysis (`-C` / `--cache`; shown only with `-C`, grand total includes cache bytes when shown)
- [x] JSON output format (`--json`, report + size modes)
- [x] Configuration file support (`~/.brew-usage-config`, strictly parsed)

### Phase 3: Polish & Distribution ✅ COMPLETE (v0.1.0)
- [x] Homebrew tap creation
- [x] README documentation
- [x] GitHub release (v0.1.0)

## Related Tools

| Tool | Purpose | Relationship |
|------|---------|--------------|
| `brew cleanup` | Remove old downloads | Uses recommendations from brew-usage |
| `brew info` | Package metadata | Different focus (no size info) |

## References

- [brew-change](https://github.com/shrwnsan/brew-change) - Architectural pattern reference
- [Homebrew Documentation](https://docs.brew.sh/) - API and command reference

## Release Notes

### v0.1.0 (2026-02-10) - Initial Release

**Implemented Features:**
- Formulae disk usage calculation with sorting
- Cask disk usage calculation with sorting
- Human-readable size formatting (B, K, M, G)
- Total aggregation by category
- Grand total calculation
- Help system (`--help`)
- Version information (`--version`)
- Cross-platform support (macOS/Linux with BSD/GNU `du`)
- Modular bash architecture with lib/ modules

**Known Limitations:**
- Cache analysis not yet implemented (Phase 2)
- JSON output not yet implemented (Phase 2)
- Separate formulae/casks display not yet implemented (Phase 2)

**Installation:**
```bash
brew install shrwnsan/tap/brew-usage
```

**Repository:** https://github.com/shrwnsan/brew-usage
**Release:** https://github.com/shrwnsan/brew-usage/releases/tag/v0.1.0
