# brew-usage

Homebrew Disk Usage Analyzer - Shows disk usage information for installed Homebrew packages.

## Overview

`brew-usage` provides detailed breakdowns of storage consumption across formulas and casks - functionality not available in native Homebrew commands.

## Features

- Per-package size breakdown (formulae and casks)
- Package size lookup from bottle manifests (`--size`)
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

# Show bottle manifest size for a package
brew-usage --size go

# Show sizes for multiple packages
brew-usage --size go node python

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
│   └── brew-usage-utils.sh         # Shared utilities
├── tests/
│   ├── test-size.sh                # Size lookup unit tests
│   └── test-size-lookup.sh         # Size lookup integration tests
├── .github/workflows/ci.yml        # CI: lint, unit, macOS integration
├── LICENSE                         # Apache-2.0 License
└── README.md                       # This file
```

## 📦 Dependencies

- **Homebrew**: Core package manager
- **bash**: Version 4.0+ for associative arrays
- **jq** (optional): Required for `--size` mode (install with `brew install jq`)

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
