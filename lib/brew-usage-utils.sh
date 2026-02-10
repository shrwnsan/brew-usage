#!/usr/bin/env bash
# Utility functions for brew-usage

# Logging functions
log_info() {
    echo "$*" >&2
}

log_error() {
    echo "Error: $*" >&2
}

log_warning() {
    echo "Warning: $*" >&2
}

# Platform detection
is_macos() {
    [[ "$OSTYPE" == darwin* ]]
}

is_linux() {
    [[ "$OSTYPE" == linux* ]]
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Sort packages by size (descending)
# Input format: "name|bytes|human" lines
sort_by_size() {
    sort -t'|' -k2 -nr
}

# Sort packages by name (ascending)
# Input format: "name|bytes|human" lines
sort_by_name() {
    sort -t'|' -k1
}

# Filter to top N packages
# Input format: "name|bytes|human" lines
filter_top_n() {
    local n="${1:-10}"
    head -n "$n"
}

# Format number with thousands separator
format_number() {
    local num="$1"
    printf "%'d" "$num" 2>/dev/null || echo "$num"
}

# Get color codes (if supported)
get_color_code() {
    local color_type="$1"
    local use_color="${2:-true}"

    if [[ "$use_color" != "true" ]]; then
        echo ""
        return
    fi

    case "$color_type" in
        red)
            echo "\033[0;31m"
            ;;
        green)
            echo "\033[0;32m"
            ;;
        yellow)
            echo "\033[0;33m"
            ;;
        blue)
            echo "\033[0;34m"
            ;;
        magenta)
            echo "\033[0;35m"
            ;;
        cyan)
            echo "\033[0;36m"
            ;;
        reset)
            echo "\033[0m"
            ;;
        bold)
            echo "\033[1m"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Determine color based on size
get_size_color() {
    local bytes="$1"
    local use_color="${2:-true}"

    if [[ "$use_color" != "true" ]]; then
        echo ""
        return
    fi

    if (( bytes >= SIZE_CRITICAL_THRESHOLD )); then
        get_color_code "red" "$use_color"
    elif (( bytes >= SIZE_WARNING_THRESHOLD )); then
        get_color_code "yellow" "$use_color"
    else
        get_color_code "green" "$use_color"
    fi
}

# Check if output is a terminal
is_terminal() {
    [[ -t 1 ]]
}

# Safe cleanup function
safe_cleanup() {
    local temp_file="$1"
    if [[ -n "$temp_file" && -f "$temp_file" ]]; then
        rm -f "$temp_file" 2>/dev/null || true
    fi
}

# Create temporary file securely
create_temp_file() {
    local prefix="${1:-brew-usage}"
    mktemp -t "${prefix}.XXXXXX" 2>/dev/null || mktemp
}

# Parse size string back to bytes
# Input: "1.5G", "500M", "250K", "1024B"
parse_size_to_bytes() {
    local size_str="$1"
    local num="${size_str%[GMKBTgmkbti]}"
    local unit="${size_str#$num}"

    # Handle floating point for non-B units
    if [[ "$unit" =~ ^[GMK] ]]; then
        # Use awk for floating point
        awk -v n="$num" -v u="$unit" '
        BEGIN {
            if (u == "T" || u == "t") print int(n * 1099511627776)
            else if (u == "G" || u == "g") print int(n * 1073741824)
            else if (u == "M" || u == "m") print int(n * 1048576)
            else if (u == "K" || u == "k") print int(n * 1024)
            else print int(n)
        }'
    else
        # For bytes, just return the integer
        echo "${num%.*}"
    fi
}
