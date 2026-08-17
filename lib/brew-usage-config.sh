#!/usr/bin/env bash
# Configuration module for brew-usage

# Set UTF-8 locale to handle emojis and special characters
if locale -a 2>/dev/null | grep -q "^en_US.UTF-8"; then
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
elif locale -a 2>/dev/null | grep -q "^C.UTF-8"; then
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8
fi

# Version information
# shellcheck disable=SC2034 # read by display_version() in brew-usage-display.sh
readonly BREW_USAGE_VERSION="0.3.0"

# Script name
if [[ -z "${SCRIPT_NAME:-}" ]]; then
    readonly SCRIPT_NAME="brew-usage"
fi

# Cache directory
if [[ -z "${CACHE_DIR:-}" ]]; then
    readonly CACHE_DIR="${BREW_USAGE_CACHE_DIR:-${HOME}/.cache/brew-usage}"
fi

# Default configuration values (consumed by the brew-usage entrypoint)
# shellcheck disable=SC2034
readonly DEFAULT_TOP_N=10
# shellcheck disable=SC2034
readonly DEFAULT_SHOW_FORMULAE=true
# shellcheck disable=SC2034
readonly DEFAULT_SHOW_CASKS=true
# shellcheck disable=SC2034
readonly DEFAULT_COLOR_OUTPUT=true

# Size thresholds for color coding (in bytes)
# shellcheck disable=SC2034 # read by get_size_color() in brew-usage-utils.sh
readonly SIZE_WARNING_THRESHOLD=104857600    # 100MB
# shellcheck disable=SC2034 # read by get_size_color() in brew-usage-utils.sh
readonly SIZE_CRITICAL_THRESHOLD=1073741824  # 1GB

# Bottle manifest cache configuration
# shellcheck disable=SC2034 # read by is_cache_valid() in brew-usage-size.sh
readonly BREW_BOTTLE_CACHE_TTL=3600                    # 1 hour in seconds

# Homebrew bottle manifest cache directory
# Uses Homebrew's own downloads cache where bottle manifests are stored
if [[ -z "${BREW_BOTTLE_CACHE_DIR:-}" ]]; then
    if is_macos 2>/dev/null || [[ "$OSTYPE" == darwin* ]]; then
        readonly BREW_BOTTLE_CACHE_DIR="${HOMEBREW_CACHE:-${HOME}/Library/Caches/Homebrew}/downloads"
    else
        # Linux: use XDG cache directory
        readonly BREW_BOTTLE_CACHE_DIR="${HOMEBREW_CACHE:-${HOME}/.cache/Homebrew}/downloads"
    fi
fi

# Ensure cache directory exists (suppress errors for read-only filesystems)
if [[ ! -d "$CACHE_DIR" ]]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    if [[ -d "$CACHE_DIR" ]]; then
        chmod 700 "$CACHE_DIR" 2>/dev/null || true
    fi
fi

# Function to verify dependencies
verify_dependencies() {
    local missing_deps=()

    # Check for required commands
    if ! command -v brew >/dev/null 2>&1; then
        missing_deps+=("brew")
    fi

    # Check for optional commands
    local optional_deps=()
    if ! command -v jq >/dev/null 2>&1; then
        optional_deps+=("jq")
    fi

    # Report missing required dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing commands and try again." >&2
        return 1
    fi

    return 0
}

# Function to get Homebrew paths
get_brew_paths() {
    # Get brew prefix
    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null)

    if [[ -z "$brew_prefix" ]]; then
        echo "Error: Unable to determine Homebrew prefix" >&2
        return 1
    fi

    # Define paths
    local cellar_path="${brew_prefix}/Cellar"
    local caskroom_path="${brew_prefix}/Caskroom"
    local cache_path
    cache_path=$(brew --cache 2>/dev/null)

    # Validate paths exist
    if [[ ! -d "$cellar_path" ]]; then
        echo "Warning: Cellar path not found: $cellar_path" >&2
    fi

    if [[ ! -d "$caskroom_path" ]]; then
        echo "Warning: Caskroom path not found: $caskroom_path" >&2
    fi

    if [[ -n "$cache_path" && ! -d "$cache_path" ]]; then
        echo "Warning: Cache path not found: $cache_path" >&2
    fi

    echo "$cellar_path|$caskroom_path|$cache_path"
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_CONFIG_LOADED:-} when standalone-sourced
readonly BREW_USAGE_CONFIG_LOADED=true
