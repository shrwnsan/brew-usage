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
readonly BREW_USAGE_VERSION="0.10.0"

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
readonly DEFAULT_SIZE_WARNING_THRESHOLD=104857600    # 100MB
readonly DEFAULT_SIZE_CRITICAL_THRESHOLD=1073741824  # 1GB
# Working values: mutable so the config file can override them.
# Read by get_size_color() in brew-usage-utils.sh.
SIZE_WARNING_THRESHOLD=$DEFAULT_SIZE_WARNING_THRESHOLD
SIZE_CRITICAL_THRESHOLD=$DEFAULT_SIZE_CRITICAL_THRESHOLD

# Cache analysis configuration
# Cleanup candidate threshold (days): cache files older than this are flagged
# as cleanup candidates by cache_analyze() in brew-usage-cache.sh.
readonly DEFAULT_CACHE_CLEANUP_DAYS=30
# Working value: mutable; initialized from env (tests) or default, then
# overridable via the config file.
CACHE_CLEANUP_DAYS="${CACHE_CLEANUP_DAYS:-$DEFAULT_CACHE_CLEANUP_DAYS}"

# Optional user configuration file (KEY=VALUE, numeric values only).
# Location overridable via BREW_USAGE_CONFIG_FILE (used by tests).
# Loaded by load_config_file() below; see its comment for the format rules.
BREW_USAGE_CONFIG_FILE="${BREW_USAGE_CONFIG_FILE:-${HOME}/.brew-usage-config}"

# Load the optional user configuration file.
#
# SECURITY: the file is parsed, never sourced — sourcing would execute
# arbitrary shell. Only lines matching ^[A-Z_][A-Z0-9_]*=[0-9]+$ are
# accepted (all supported keys are numeric; values capped at 9 digits) and
# only whitelisted keys are
# applied. Malformed lines and unknown keys produce a warning on stderr and
# are skipped; this never affects the exit code.
#
# Diagnostics globals (read by doctor_check_config_valid in
# brew-usage-doctor.sh): BREW_USAGE_CONFIG_MALFORMED (count of malformed
# lines and unknown-key lines) and BREW_USAGE_CONFIG_FIRST_BAD ("line N" of
# the first one). Warnings on stderr are unchanged.
#
# Overrides (applied here): SIZE_WARNING_THRESHOLD, SIZE_CRITICAL_THRESHOLD,
# CACHE_CLEANUP_DAYS, and BREW_USAGE_CONFIG_TOP_N (consumed by the
# brew-usage entrypoint to initialize TOP_N; CLI --top still wins).
load_config_file() {
    local config_file="$BREW_USAGE_CONFIG_FILE"

    # Missing or unreadable file: silently use defaults
    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        return 0
    fi

    local line line_no=0 key value
    BREW_USAGE_CONFIG_MALFORMED=0
    BREW_USAGE_CONFIG_FIRST_BAD=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))

        # Strip trailing CR from CRLF (Windows-edited) files
        line="${line%$'\r'}"

        # Skip blank lines and comments
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=[0-9]{1,9}$ ]]; then
            key="${line%%=*}"
            value="${line#*=}"
            # Assignments are consumed in other modules (get_size_color(),
            # cache_analyze(), TOP_N init in brew-usage)
            # shellcheck disable=SC2034
            case "$key" in
                TOP_N)
                    BREW_USAGE_CONFIG_TOP_N="$value"
                    ;;
                SIZE_WARNING_THRESHOLD)
                    SIZE_WARNING_THRESHOLD="$value"
                    ;;
                SIZE_CRITICAL_THRESHOLD)
                    SIZE_CRITICAL_THRESHOLD="$value"
                    ;;
                CACHE_CLEANUP_DAYS)
                    CACHE_CLEANUP_DAYS="$value"
                    ;;
                *)
                    echo "Warning: ${config_file}: line ${line_no}: unknown key '${key}', ignoring" >&2
                    BREW_USAGE_CONFIG_MALFORMED=$((BREW_USAGE_CONFIG_MALFORMED + 1))
                    if [[ -z "$BREW_USAGE_CONFIG_FIRST_BAD" ]]; then
                        BREW_USAGE_CONFIG_FIRST_BAD="line ${line_no}"
                    fi
                    ;;
            esac
        else
            # Replace non-printable bytes before echoing: raw escape
            # sequences in the file must not reach the terminal
            local safe_line
            safe_line="${line//[![:print:]]/?}"
            echo "Warning: ${config_file}: line ${line_no}: malformed line, ignoring: ${safe_line}" >&2
            BREW_USAGE_CONFIG_MALFORMED=$((BREW_USAGE_CONFIG_MALFORMED + 1))
            if [[ -z "$BREW_USAGE_CONFIG_FIRST_BAD" ]]; then
                BREW_USAGE_CONFIG_FIRST_BAD="line ${line_no}"
            fi
        fi
    done < "$config_file"
}

load_config_file

# Homebrew cache directory override for cache analysis (-C/--cache).
# Empty by default; cache_get_dir() in brew-usage-cache.sh resolves the real
# cache path lazily. Tests point this at a temp dir with known contents.
BREW_USAGE_CACHE_ANALYSIS_DIR="${BREW_USAGE_CACHE_ANALYSIS_DIR:-}"

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
