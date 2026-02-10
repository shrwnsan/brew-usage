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

# Display package list
display_packages() {
    local -n packages_ref=$1  # nameref to associative array
    local max_width="${2:-30}"
    local use_color="${3:-true}"

    local reset
    reset=$(get_color_code "reset" "$use_color")

    # Sort by size (descending)
    for entry in $(for pkg in "${!packages_ref[@]}"; do
        echo "${packages_ref[$pkg]}"
    done | sort_by_size); do
        local name=$(echo "$entry" | cut -d'|' -f1)
        local bytes=$(echo "$entry" | cut -d'|' -f2)
        local human=$(echo "$entry" | cut -d'|' -f3)

        # Get color based on size
        local color
        color=$(get_size_color "$bytes" "$use_color")

        # Format with proper spacing
        local size_width=8
        printf "${color}%${size_width}s${reset}  %s\n" "$human" "$name"
    done
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
