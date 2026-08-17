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

# Display cache analysis
display_cache_analysis() {
    local cache_size="$1"
    local cleanup_candidates="$2"
    local cleanup_age="${3:-30}"  # days
    local use_color="${4:-true}"

    local bold reset yellow
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    yellow=$(get_color_code "yellow" "$use_color")

    local cache_human
    cache_human=$(get_size_human "$cache_size")

    local cleanup_human
    cleanup_human=$(get_size_human "$cleanup_candidates")

    echo ""
    echo "   ${cache_human}   Total cache size"
    if (( cleanup_candidates > 0 )); then
        echo "   ${yellow}${cleanup_human}${reset}   Cleanup candidates (>${cleanup_age} days old)"
        echo "   ───────────────"
        echo "${bold}Suggestion:${reset} brew cleanup -s --prune=${cleanup_age}"
    else
        echo "   ${bold}No cleanup needed${reset}"
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

# Display JSON output
display_json() {
    local formulae_json="$1"
    local casks_json="$2"
    local cache_json="$3"
    local grand_total="$4"

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_error "JSON output requires jq. Install with: brew install jq"
        return 1
    fi

    local grand_total_human
    grand_total_human=$(get_size_human "$grand_total")

    # Build JSON structure
    local json_output
    json_output=$(jq -n \
        --argjson formulae "$formulae_json" \
        --argjson casks "$casks_json" \
        --argjson cache "$cache_json" \
        --argjson grand_total_bytes "$grand_total" \
        --arg grand_total_human "$grand_total_human" \
        '{
            formulae: $formulae,
            casks: $casks,
            cache: $cache,
            grand_total_bytes: $grand_total_bytes | tonumber,
            grand_total_human: $grand_total_human
        }')

    echo "$json_output"
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
  -s, --sort ORDER     Sort order: size, name (default: size)
      --no-color       Disable color output
  -v, --version        Show version information

Examples:
  brew-usage                    # Show all Homebrew usage
  brew-usage --top 20          # Show top 20 largest packages
  brew-usage --formulae        # Show only formulae
  brew-usage --casks           # Show only casks
  brew-usage --sort name       # Sort by package name

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

