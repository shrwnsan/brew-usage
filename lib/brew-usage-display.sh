#!/usr/bin/env bash
# Display module for brew-usage
# Handles output formatting and presentation

# Display header
display_header() {
    local use_color="${1:-true}"

    local bold reset
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo ""
    echo "${bold}Homebrew Usage Report${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Display section header
display_section_header() {
    local title="$1"
    local icon="$2"
    local use_color="${3:-true}"

    local bold reset
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo ""
    echo "${bold}${icon} ${title}${reset}"
}

# Display section total
display_section_total() {
    local total_bytes="$1"
    local use_color="${2:-true}"

    local bold reset cyan
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")

    local total_human
    total_human=$(get_size_human "$total_bytes")

    echo "   ───────────────"
    echo "${cyan}Total: ${total_human}${reset}"
}

# Display cache analysis section (read-only; cleanup is left to `brew cleanup`)
# Input: $1 = total bytes, $2 = downloads bytes, $3 = other bytes,
#        $4 = file count, $5 = cleanup candidates bytes,
#        $6 = cleanup candidates count, $7 = cleanup age (days),
#        $8 = use color
display_cache_section() {
    local total_bytes="$1"
    local downloads_bytes="$2"
    local other_bytes="$3"
    local file_count="$4"
    local cleanup_bytes="$5"
    local cleanup_count="$6"
    local cleanup_days="$7"
    local use_color="${8:-true}"

    local bold reset cyan yellow
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")
    yellow=$(get_color_code "yellow" "$use_color")

    local total_human downloads_human other_human cleanup_human
    total_human=$(get_size_human "$total_bytes")
    downloads_human=$(get_size_human "$downloads_bytes")
    other_human=$(get_size_human "$other_bytes")
    cleanup_human=$(get_size_human "$cleanup_bytes")

    echo "   ${total_human}   Total cache size ($(format_number "$file_count") files)"
    echo "   ${downloads_human}   Downloads"
    echo "   ${other_human}   Other"
    echo "   ───────────────"
    if (( cleanup_bytes > 0 )); then
        echo "   ${yellow}${cleanup_human}${reset}   Cleanup candidates: ${cleanup_human} (${cleanup_count} files)"
        echo "${bold}Suggestion:${reset} run \`brew cleanup --prune=${cleanup_days}\` to reclaim"
    else
        echo "   ${bold}No cleanup candidates (>${cleanup_days} days old)${reset}"
    fi
}

# Page a file through ${PAGER:-less}
# Errexit-safe by design: the file is fully written before paging, so an
# early pager quit cannot SIGPIPE the report generation, and pager failures
# (non-zero exit, missing binary) never abort the caller. Falls back to
# plain cat when the configured pager is not installed.
page_file() {
    local file="$1"

    local pager_args=()
    read -r -a pager_args <<< "${PAGER:-less}"

    if command -v "${pager_args[0]}" >/dev/null 2>&1; then
        "${pager_args[@]}" < "$file" || true
    else
        cat "$file" || true
    fi
}

# Display grand total
display_grand_total() {
    local grand_total="$1"
    local use_color="${2:-true}"

    local bold reset green
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    green=$(get_color_code "green" "$use_color")

    local total_human
    total_human=$(get_size_human "$grand_total")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${green}${bold}Grand Total: ${total_human}${reset}"
    echo ""
}

# Display empty state
display_empty_state() {
    local message="${1:-No packages found}"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}${message}${reset}"
}

# Display error message
display_error() {
    local message="$1"
    local use_color="${2:-true}"

    local red reset
    red=$(get_color_code "red" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${red}Error: ${message}${reset}" >&2
}

# Display help message
display_help() {
    cat << 'EOF'
Usage: brew-usage [OPTIONS]

Shows disk usage information for installed Homebrew packages.

Options:
  -h, --help           Show this help message
  -f, --formulae       Show formulae only
  -c, --casks          Show casks only
  -t, --top N          Show top N packages by size (default: 10)
  -a, --all            Show all packages (no top-N cut); output is paged
                       when stdout is a terminal (respects $PAGER)
  -s, --sort ORDER     Sort order: size, name (default: size)
      --size PKG...    Show bottle sizes for specific packages
  -C, --cache          Show Homebrew cache analysis (standalone, or as an
                       extra section when combined with report flags)
      --json           Machine-readable JSON output (report and --size modes)
      --no-color       Disable color output
  -v, --version        Show version information

Examples:
  brew-usage                    # Show all Homebrew usage
  brew-usage --top 20          # Show top 20 largest packages
  brew-usage --formulae        # Show only formulae
  brew-usage --casks           # Show only casks
  brew-usage --sort name       # Sort by package name
  brew-usage --all             # Show every package (paged on a terminal)
  brew-usage --json            # JSON output for scripting
  brew-usage --size go node    # Bottle sizes for go and node
  brew-usage --cache           # Homebrew cache analysis only
  brew-usage --formulae --cache # Report with cache section appended

For more information, visit: https://github.com/shrwnsan/brew-usage
EOF
}

# Display version
display_version() {
    echo "brew-usage version $BREW_USAGE_VERSION"
}

# =============================================================================
# Size display functions for --size mode
# =============================================================================

# Display size information for a single package
# Input: JSON output from get_package_size()
display_package_size() {
    local size_json="$1"
    local use_color="${2:-true}"

    local name version download_size installed_size platform
    name=$(echo "$size_json" | jq -r '.name')
    version=$(echo "$size_json" | jq -r '.version')
    download_size=$(echo "$size_json" | jq -r '.download_size')
    installed_size=$(echo "$size_json" | jq -r '.installed_size')
    platform=$(echo "$size_json" | jq -r '.platform')

    local download_human installed_human
    download_human=$(get_size_human_iec "$download_size")
    installed_human=$(get_size_human_iec "$installed_size")

    local bold reset cyan green
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")
    green=$(get_color_code "green" "$use_color")

    echo ""
    echo "${bold}${name}${reset} ${green}${version}${reset}"
    echo "  Platform:      ${cyan}${platform}${reset}"
    echo "  Download:      ${cyan}${download_human}${reset}"
    echo "  Installed:     ${cyan}${installed_human}${reset}"
}

# Display size information for multiple packages in table format
# Input: Array of JSON objects from get_package_size()
display_multiple_package_sizes() {
    local -n size_results_ref=$1
    local use_color="${2:-true}"

    local bold reset cyan
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")

    echo ""
    echo "${bold}Package Sizes${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    printf "${bold}%-20s  %-12s  %-12s  %-12s${reset}\n" "Package" "Download" "Installed" "Platform"
    echo "──────────────────────────────────────────────────────────"

    for size_json in "${size_results_ref[@]}"; do
        local name version download_size installed_size platform
        name=$(echo "$size_json" | jq -r '.name')
        version=$(echo "$size_json" | jq -r '.version')
        download_size=$(echo "$size_json" | jq -r '.download_size')
        installed_size=$(echo "$size_json" | jq -r '.installed_size')
        platform=$(echo "$size_json" | jq -r '.platform')

        local download_human installed_human
        download_human=$(get_size_human_iec "$download_size")
        installed_human=$(get_size_human_iec "$installed_size")

        printf "%-20s  ${cyan}%-12s${reset}  ${cyan}%-12s${reset}  %-12s\n" \
            "$name" "$download_human" "$installed_human" "$platform"
    done
}

# Display warning message for size mode
# Input: warning message
display_size_warning() {
    local message="$1"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}Warning: ${message}${reset}" >&2
}

# Display error message for size mode
# Input: error message
display_size_error() {
    local message="$1"
    local use_color="${2:-true}"

    local red reset
    red=$(get_color_code "red" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${red}Error: ${message}${reset}" >&2
}

# Display "no bottle available" message
# Input: package name
display_no_bottle() {
    local package_name="$1"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}No bottle available for '${package_name}'${reset}" >&2
    echo "  This package may be source-only or not available for your platform." >&2
}

