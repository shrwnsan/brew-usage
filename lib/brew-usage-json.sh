#!/usr/bin/env bash
# JSON output module for brew-usage
# Builds machine-readable JSON for report mode and size mode
#
# stdout carries only valid JSON; warnings and errors go to stderr
# (log_* functions) so the JSON stream stays parseable on partial failure.
# All user-influenced values (package names, etc.) are passed through
# jq --arg / --argjson — never hand-escaped into JSON strings.

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

# Verify jq is available for JSON output
# Output: 0 (available) or 1 (missing, error logged)
json_verify_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "JSON output requires jq. Install with: brew install jq"
        return 1
    fi
    return 0
}

# Build a JSON array of package objects from "name|bytes|human" lines
# Input: lines of "name|bytes|human" on stdin (may be empty)
# Output: JSON array [{name, size, size_human}, ...]
json_packages_array() {
    jq -Rn '
        [ inputs
          | select(length > 0)
          | split("|")
          | select(length == 3)
          | { name: .[0], size: (.[1] | tonumber), size_human: .[2] } ]'
}

# Build a report section block from "name|bytes|human" lines
# Input: $1 = total bytes (integer), lines of "name|bytes|human" on stdin
# Output: JSON object {packages: [...], total_bytes, total_human}
json_section_block() {
    local total_bytes="$1"

    local total_human
    total_human=$(get_size_human "$total_bytes")

    local packages
    packages=$(json_packages_array) || return 1

    jq -n \
        --argjson packages "$packages" \
        --argjson total_bytes "$total_bytes" \
        --arg total_human "$total_human" \
        '{
            packages: $packages,
            total_bytes: $total_bytes,
            total_human: $total_human
        }'
}

# Build the top-level report JSON object
# Absent sections (null) are omitted from the output entirely
# Input: $1 = formulae block JSON or "null", $2 = casks block JSON or "null",
#        $3 = grand total bytes (integer)
# Output: report JSON on stdout
json_render_report() {
    local formulae_block="$1"
    local casks_block="$2"
    local grand_total_bytes="$3"

    local grand_total_human
    grand_total_human=$(get_size_human "$grand_total_bytes")

    jq -n \
        --argjson formulae "$formulae_block" \
        --argjson casks "$casks_block" \
        --argjson grand_total_bytes "$grand_total_bytes" \
        --arg grand_total_human "$grand_total_human" \
        '(if $formulae != null then {formulae: $formulae} else {} end)
        + (if $casks != null then {casks: $casks} else {} end)
        + {
            grand_total_bytes: $grand_total_bytes,
            grand_total_human: $grand_total_human
          }'
}

# Build a size-mode package entry for a successfully resolved package
# Input: $1 = package name, $2 = size JSON from get_package_size()
# Output: JSON object with status "ok" added; if the size JSON fails to
# parse, a "parse_error" entry is emitted instead of dropping the package
json_size_entry_ok() {
    local package_name="$1"
    local size_json="$2"

    local entry
    entry=$(printf '%s' "$size_json" | jq -c '. + {status: "ok"}' 2>/dev/null) || {
        log_warning "Failed to parse size data for '$package_name'"
        json_size_entry_failed "$package_name" "parse_error"
        return 0
    }
    [[ -n "$entry" ]] || {
        log_warning "Failed to parse size data for '$package_name'"
        json_size_entry_failed "$package_name" "parse_error"
        return 0
    }
    printf '%s\n' "$entry"
}

# Build a size-mode package entry for an unresolved package
# Input: $1 = package name, $2 = status ("not_found", "no_bottle" or "parse_error")
# Output: JSON object with null size fields
json_size_entry_failed() {
    local package_name="$1"
    local status="$2"

    jq -nc \
        --arg name "$package_name" \
        --arg status "$status" \
        '{
            name: $name,
            version: null,
            download_size: null,
            installed_size: null,
            platform: null,
            status: $status
        }'
}

# Assemble the size-mode JSON document from entry objects
# Input: entry JSON objects (one per line) on stdin
# Output: {"packages": [...]} on stdout
json_render_size_report() {
    jq -s '{packages: .}'
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_JSON_LOADED:-} when standalone-sourced
readonly BREW_USAGE_JSON_LOADED=true
