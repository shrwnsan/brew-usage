# brew-usage

Homebrew Disk Usage Analyzer - Shows disk usage information for installed Homebrew packages.

## Overview

`brew-usage` provides detailed breakdowns of storage consumption across formulas, casks, and cache - functionality not available in native Homebrew commands.

## Features

- Per-package size breakdown (formulae and casks)
- Human-readable formatting with color coding
- Top N filtering by size
- Category filtering (formulae-only or casks-only)
- Cross-platform compatibility (macOS/Linux)
- Fast, parallel processing

## 🚀 Installation

### Quick Install
```bash
# Install directly via Homebrew tap
brew install shrwnsan/tap/brew-usage

# Verify installation
brew-usage --version
```

### Local Development
```bash
git clone https://github.com/shrwnsan/brew-usage.git ~/Developer/personal/brew-usage
```

## 📖 Usage

```bash
# Show all Homebrew usage
brew-usage

# Show top 20 largest packages
brew-usage --top 20

# Show only formulae
brew-usage --formulae

# Show only casks
brew-usage --casks

# Show help
brew-usage --help

# Show version
brew-usage --version
```

## 🏗️ Architecture

```
brew-usage/
├── brew-usage                      # Main entry point
├── lib/
│   ├── brew-usage-config.sh        # Configuration & defaults
│   ├── brew-usage-scan.sh          # Package discovery
│   ├── brew-usage-calculate.sh     # Portable size calculation
│   ├── brew-usage-display.sh       # Output formatting
│   └── brew-usage-utils.sh         # Shared utilities
└── tests/
```

## 📦 Dependencies

- **Homebrew**: Core package manager
- **bash**: Version 4.0+ for associative arrays

## 🌐 Platform Support

brew-usage works seamlessly across all platforms where Homebrew is available:

| Platform | Homebrew Path | Status |
|----------|---------------|--------|
| **macOS (Intel)** | `/usr/local/bin/brew` | ✅ Fully supported |
| **macOS (Apple Silicon)** | `/opt/homebrew/bin/brew` | ✅ Fully supported |
| **Linux** | `/home/linuxbrew/.linuxbrew/bin/brew` | ✅ Fully supported |
| **WSL** | `/home/linuxbrew/.linuxbrew/bin/brew` | ✅ Fully supported |

The script automatically detects the correct library path using `brew --prefix`, ensuring compatibility across all Homebrew installations.

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

shrwnsan

## See Also

- [brew-change](https://github.com/shrwnsan/brew-change) - Changelog tracking for Homebrew packages
