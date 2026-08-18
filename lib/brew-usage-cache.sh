#!/usr/bin/env bash
# Cache analysis module for brew-usage (-C/--cache)
# Analyzes the Homebrew download cache: total size, file count, downloads
# vs other subdirectories, and cleanup candidates (files older than
# CACHE_CLEANUP_DAYS, default 30).
#
# Strictly read-only: this module never deletes or modifies cache files.

# Source dependencies
if [[ -z "${BREW_USAGE_CONFIG_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-config.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-config.sh" || {
        echo "Error: Failed to source brew-usage-config.sh" >&2
        exit 1
    }
fi

if [[ -z "${BREW_USAGE_UTILS_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-utils.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-utils.sh" || {
        echo "Error: Failed to source brew-usage-utils.sh" >&2
        exit 1
    }
fi

# Resolve the Homebrew cache directory.
# Order: $BREW_USAGE_CACHE_ANALYSIS_DIR (explicit override, used by tests)
#        -> brew --cache -> $HOMEBREW_CACHE -> platform default
# Output: cache directory path on stdout
cache_get_dir() {
    if [[ -n "$BREW_USAGE_CACHE_ANALYSIS_DIR" ]]; then
        printf '%s\n' "$BREW_USAGE_CACHE_ANALYSIS_DIR"
        return 0
    fi

    local cache_dir
    cache_dir=$(brew --cache 2>/dev/null) || cache_dir=""
    if [[ -z "$cache_dir" ]]; then
        cache_dir="${HOMEBREW_CACHE:-}"
    fi
    if [[ -z "$cache_dir" ]]; then
        if is_macos; then
            cache_dir="${HOME}/Library/Caches/Homebrew"
        else
            cache_dir="${HOME}/.cache/Homebrew"
        fi
    fi

    printf '%s\n' "$cache_dir"
}

# Emit "mtime|bytes|path" for every file under $1, in one batched stat pass.
# stat flags are platform-specific (GNU `stat -f` is filesystem mode and can
# emit garbage to stdout even while failing), so select by platform — do not
# use try-both-fallback idioms here.
# Batched for speed on large caches.
# Caveat: file names containing newlines would split across lines — brew cache
# file names are sanitized download URLs, so this is not a practical concern.
# Input: $1 = directory to scan
# Output: "mtime|bytes|path" lines on stdout
cache_stat_files() {
    local dir="$1"
    if is_macos; then
        find "$dir" -type f -exec stat -f '%m|%z|%N' {} + 2>/dev/null
    else
        find "$dir" -type f -exec stat -c '%Y|%s|%n' {} + 2>/dev/null
    fi
}

# Analyze the Homebrew cache (read-only).
# Sets globals:
#   CACHE_ANALYSIS_DIR     resolved cache directory
#   CACHE_TOTAL_BYTES      total size of all cache files
#   CACHE_FILE_COUNT       number of cache files
#   CACHE_DOWNLOADS_BYTES  size of files under <cache>/downloads
#   CACHE_OTHER_BYTES      size of files outside <cache>/downloads
#   CACHE_CLEANUP_BYTES    size of files older than CACHE_CLEANUP_DAYS
#   CACHE_CLEANUP_COUNT    number of cleanup candidate files
# Output: 0 (always; a missing cache dir logs a warning and yields zeros)
cache_analyze() {
    CACHE_ANALYSIS_DIR=""
    CACHE_TOTAL_BYTES=0
    CACHE_FILE_COUNT=0
    CACHE_DOWNLOADS_BYTES=0
    CACHE_OTHER_BYTES=0
    CACHE_CLEANUP_BYTES=0
    CACHE_CLEANUP_COUNT=0

    local cache_dir
    cache_dir=$(cache_get_dir) || return 1
    # shellcheck disable=SC2034 # informational global for callers/tests
    CACHE_ANALYSIS_DIR="$cache_dir"

    if [[ ! -d "$cache_dir" ]]; then
        log_warning "Homebrew cache directory not found: $cache_dir"
        return 0
    fi

    # Guard the threshold against non-numeric overrides (env or future
    # config-file support): fall back to the 30-day default.
    local cleanup_days="$CACHE_CLEANUP_DAYS"
    if ! [[ "$cleanup_days" =~ ^[0-9]+$ ]]; then
        cleanup_days="$DEFAULT_CACHE_CLEANUP_DAYS"
    fi
    local cutoff
    cutoff=$(( $(date +%s) - cleanup_days * 86400 ))

    local mtime size file
    while IFS='|' read -r mtime size file; do
        [[ "$mtime" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ && -n "$file" ]] || continue

        CACHE_TOTAL_BYTES=$((CACHE_TOTAL_BYTES + size))
        CACHE_FILE_COUNT=$((CACHE_FILE_COUNT + 1))

        case "$file" in
            "$cache_dir"/downloads/*)
                CACHE_DOWNLOADS_BYTES=$((CACHE_DOWNLOADS_BYTES + size))
                ;;
            *)
                CACHE_OTHER_BYTES=$((CACHE_OTHER_BYTES + size))
                ;;
        esac

        if (( mtime < cutoff )); then
            CACHE_CLEANUP_BYTES=$((CACHE_CLEANUP_BYTES + size))
            CACHE_CLEANUP_COUNT=$((CACHE_CLEANUP_COUNT + 1))
        fi
    done < <(cache_stat_files "$cache_dir")

    return 0
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_CACHE_LOADED:-} when standalone-sourced
readonly BREW_USAGE_CACHE_LOADED=true
