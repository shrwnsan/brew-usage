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

## Installation

### Via Homebrew Tap (recommended)

```bash
brew install shrwnsan/tap/brew-usage
```

### Local Development

```bash
git clone https://github.com/shrwnsan/brew-usage.git ~/Developer/personal/brew-usage
```

Then add the Zsh wrapper (see below).

## Usage

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

## Zsh Integration

Add to your `~/.zshrc`:

```zsh
fpath=($HOME/.zsh/functions $fpath)
autoload -Uz brew_usage
```

The wrapper will automatically check for `brew-usage` in PATH (from Homebrew tap) or fall back to the local development directory.

## Architecture

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

## Dependencies

- **Homebrew**: Core package manager
- **bash**: Version 4.0+ for associative arrays

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

shrwnsan

## See Also

- [brew-change](https://github.com/shrwnsan/brew-change) - Changelog tracking for Homebrew packages
