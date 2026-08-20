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

# Build the cache analysis JSON block from cache_analyze() results
# Input: $1 = total bytes, $2 = cleanup candidates bytes, $3 = file count
# Output: JSON object {total_bytes, total_human, cleanup_candidates_bytes,
#         cleanup_candidates_human, file_count}
json_cache_block() {
    local total_bytes="$1"
    local cleanup_bytes="$2"
    local file_count="$3"

    local total_human cleanup_human
    total_human=$(get_size_human "$total_bytes")
    cleanup_human=$(get_size_human "$cleanup_bytes")

    jq -n \
        --argjson total_bytes "$total_bytes" \
        --arg total_human "$total_human" \
        --argjson cleanup_candidates_bytes "$cleanup_bytes" \
        --arg cleanup_candidates_human "$cleanup_human" \
        --argjson file_count "$file_count" \
        '{
            total_bytes: $total_bytes,
            total_human: $total_human,
            cleanup_candidates_bytes: $cleanup_candidates_bytes,
            cleanup_candidates_human: $cleanup_candidates_human,
            file_count: $file_count
        }'
}

# Build the top-level report JSON object
# Absent sections (null) are omitted from the output entirely.
# Grand-total decision: when the cache section is shown, its bytes are
# included in grand_total_bytes/grand_total_human (the PRD-001 JSON schema
# counts cache in the grand total; the human grand total matches the JSON).
# Input: $1 = formulae block JSON or "null", $2 = casks block JSON or "null",
#        $3 = cache block JSON or "null", $4 = grand total bytes (integer,
#        caller-computed; includes cache bytes when a cache block is given)
# Output: report JSON on stdout
json_render_report() {
    local formulae_block="$1"
    local casks_block="$2"
    local cache_block="$3"
    local grand_total_bytes="$4"

    local grand_total_human
    grand_total_human=$(get_size_human "$grand_total_bytes")

    jq -n \
        --argjson formulae "$formulae_block" \
        --argjson casks "$casks_block" \
        --argjson cache "$cache_block" \
        --argjson grand_total_bytes "$grand_total_bytes" \
        --arg grand_total_human "$grand_total_human" \
        '(if $formulae != null then {formulae: $formulae} else {} end)
        + (if $casks != null then {casks: $casks} else {} end)
        + (if $cache != null then {cache: $cache} else {} end)
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

# Build the doctor report JSON from doctor_run_all() result globals
# (DOCTOR_RESULT_NAMES/GROUPS/VERDICTS/DETAILS/SUGGESTIONS,
# DOCTOR_PASS/WARN/FAIL; set by lib/brew-usage-doctor.sh)
# Input: $1 (optional) = fixes JSON array to embed as "fixes" — the planned
#        fixes ([{id, check, tier, description}]) from
#        json_doctor_fixes_plan() for `doctor --fix --json`, or the apply
#        results ([{id, status, result}]) from json_doctor_fixes_results()
#        for `doctor --fix --yes --json`. Omitted/empty for the plain
#        doctor report, which has no fixes key (PRD-005).
# Output: {checks: [{name, group, verdict, detail, suggestion?} ...],
#          summary: {pass, warn, fail}, fixes?: [...]} on stdout
# Empty suggestions are omitted from the entry entirely (PRD-003).
json_doctor_report() {
    local fixes="${1:-}"
    local checks="[]"
    if [[ ${#DOCTOR_RESULT_NAMES[@]} -gt 0 ]]; then
        local i
        checks=$(
            for i in "${!DOCTOR_RESULT_NAMES[@]}"; do
                jq -nc \
                --arg name "${DOCTOR_RESULT_NAMES[$i]}" \
                --arg group "${DOCTOR_RESULT_GROUPS[$i]}" \
                --arg verdict "${DOCTOR_RESULT_VERDICTS[$i]}" \
                --arg detail "${DOCTOR_RESULT_DETAILS[$i]}" \
                --arg suggestion "${DOCTOR_RESULT_SUGGESTIONS[$i]}" \
                'if $suggestion == "" then
                    {name: $name, group: $group, verdict: $verdict, detail: $detail}
                 else
                    {name: $name, group: $group, verdict: $verdict,
                     detail: $detail, suggestion: $suggestion}
                 end'
            done | jq -s '.'
        ) || return 1
    fi

    if [[ -n "$fixes" ]]; then
        jq -n \
            --argjson checks "$checks" \
            --argjson pass "$DOCTOR_PASS" \
            --argjson warn "$DOCTOR_WARN" \
            --argjson fail "$DOCTOR_FAIL" \
            --argjson fixes "$fixes" \
            '{
                checks: $checks,
                summary: {pass: $pass, warn: $warn, fail: $fail},
                fixes: $fixes
            }'
    else
        jq -n \
            --argjson checks "$checks" \
            --argjson pass "$DOCTOR_PASS" \
            --argjson warn "$DOCTOR_WARN" \
            --argjson fail "$DOCTOR_FAIL" \
            '{
                checks: $checks,
                summary: {pass: $pass, warn: $warn, fail: $fail}
            }'
    fi
}

# Build the planned-fixes JSON array for `doctor --fix --json` (dry run):
# [{id, check, tier, description}] for each registry fix with findings,
# [] when nothing is fixable. Reads the fix registry through
# doctor_fixes() / doctor_fix_description() (lib/brew-usage-doctor.sh).
# Output: fixes array JSON on stdout
json_doctor_fixes_plan() {
    local plan
    plan=$(
        while IFS='|' read -r fix_id check_id tier _; do
            [[ -n "$fix_id" ]] || continue
            description=""
            description=$(doctor_fix_description "$fix_id")
            [[ -n "$description" ]] || continue
            jq -nc \
                --arg id "$fix_id" \
                --arg check "$check_id" \
                --arg tier "$tier" \
                --arg description "$description" \
                '{id: $id, check: $check, tier: $tier, description: $description}'
        done < <(doctor_fixes) | jq -s '.'
    ) || return 1
    printf '%s\n' "$plan"
}

# Build the applied-fixes JSON array for `doctor --fix --yes [--install]
# --json`: [{id, status: "applied"|"failed"|"skipped", result}] for each
# due fix, from the result globals doctor_apply_fixes() sets
# (lib/brew-usage-doctor.sh); [] when nothing was due. "skipped" marks
# install-tier fixes withheld for lack of --install consent (PRD-006).
# Output: fixes array JSON on stdout
json_doctor_fixes_results() {
    local results="[]"
    if [[ ${#DOCTOR_FIX_RESULT_IDS[@]} -gt 0 ]]; then
        local i
        results=$(
            for i in "${!DOCTOR_FIX_RESULT_IDS[@]}"; do
                jq -nc \
                    --arg id "${DOCTOR_FIX_RESULT_IDS[$i]}" \
                    --arg status "${DOCTOR_FIX_RESULT_STATUSES[$i]}" \
                    --arg result "${DOCTOR_FIX_RESULT_LINES[$i]}" \
                    '{id: $id, status: $status, result: $result}'
            done | jq -s '.'
        ) || return 1
    fi
    printf '%s\n' "$results"
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_JSON_LOADED:-} when standalone-sourced
readonly BREW_USAGE_JSON_LOADED=true
