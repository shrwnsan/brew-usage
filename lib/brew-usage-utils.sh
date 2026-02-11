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

# Get the Homebrew bottle tag for the current platform
# Uses brew ruby to query Homebrew's own platform detection
# Falls back to manual mapping if brew ruby fails
# Output: Bottle tag (e.g., "arm64_sonoma", "x86_64_linux")
get_bottle_tag() {
    # Try Homebrew's internal method first (most reliable)
    local tag
    tag=$(brew ruby -e 'puts Homebrew::SimulateSystem.current_tag' 2>/dev/null)

    if [[ -n "$tag" ]]; then
        echo "$tag"
        return 0
    fi

    # Fallback: manual mapping
    local arch
    arch=$(uname -m)

    # Normalize architecture names
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) ;;  # Keep as-is for other architectures
    esac

    if is_linux; then
        echo "${arch}_linux"
        return 0
    fi

    # macOS: map version to codename
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null) || return 1
    local macos_major
    macos_major=$(echo "$macos_version" | cut -d. -f1)

    local codename
    case "$macos_major" in
        15) codename="sequoia" ;;
        14) codename="sonoma" ;;
        13) codename="ventura" ;;
        12) codename="monterey" ;;
        11) codename="big_sur" ;;
        # For very new macOS versions, try to find closest match
        # This allows forward compatibility without code updates
        *)
            # Default to sonoma as a safe fallback for modern macOS
            codename="sonoma"
            ;;
    esac

    echo "${arch}_${codename}"
    return 0
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
            printf '\033[0;31m'
            ;;
        green)
            printf '\033[0;32m'
            ;;
        yellow)
            printf '\033[0;33m'
            ;;
        blue)
            printf '\033[0;34m'
            ;;
        magenta)
            printf '\033[0;35m'
            ;;
        cyan)
            printf '\033[0;36m'
            ;;
        reset)
            printf '\033[0m'
            ;;
        bold)
            printf '\033[1m'
            ;;
        *)
            printf ''
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

# Format bytes to IEC binary units (KiB/MiB/GiB/TiB/EiB/PiB)
# Input: Bytes (integer or string)
# Output: Formatted string with IEC binary suffix, rounded to 1 decimal place
# Example: 203292092 → "193.9 MiB"
# Example: 57531075 → "54.9 MiB"
# Example: 1024 → "1.0 KiB"
# Example: 512 → "512 B"
get_size_human_iec() {
    local bytes="$1"
    local units=("B" "KiB" "MiB" "GiB" "TiB" "EiB" "PiB")
    local unit_index=0

    # Convert to integer if needed
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        bytes="${bytes%.*}"
        bytes="${bytes:-0}"
    fi

    # Use awk for proper floating point calculation
    awk -v bytes="$bytes" 'BEGIN {
        units[0] = "B";
        units[1] = "KiB";
        units[2] = "MiB";
        units[3] = "GiB";
        units[4] = "TiB";
        units[5] = "EiB";
        units[6] = "PiB";

        value = bytes;
        unit_index = 0;

        while (value >= 1024 && unit_index < 6) {
            value /= 1024;
            unit_index++;
        }

        # Format with 1 decimal place for units above bytes, no decimal for bytes
        if (unit_index == 0) {
            printf "%.0f %s", value, units[unit_index];
        } else {
            printf "%.1f %s", value, units[unit_index];
        }
    }'
}
