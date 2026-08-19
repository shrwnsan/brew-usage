#!/usr/bin/env bash
# Doctor module for brew-usage (brew-usage doctor / -d / --doctor)
# Diagnoses the operating environment: Homebrew presence and paths,
# configuration health, manifest cache state, brew surfaces, and ghcr.io
# reachability. Follows the `brew doctor` contract: diagnose and suggest,
# never mutate — every check is strictly read-only and suggestions are
# printed commands only (never executed).

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

# is_cache_valid() is defined in brew-usage-size.sh and cache_get_dir() in
# brew-usage-cache.sh; source both through their own guards (each also
# brings config+utils, already loaded here)
if [[ -z "${BREW_USAGE_SIZE_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-size.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-size.sh" || {
        echo "Error: Failed to source brew-usage-size.sh" >&2
        exit 1
    }
fi

if [[ -z "${BREW_USAGE_CACHE_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-cache.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-cache.sh" || {
        echo "Error: Failed to source brew-usage-cache.sh" >&2
        exit 1
    }
fi

# =============================================================================
# Result recording
# =============================================================================

# Record the current check's outcome (globals, matching codebase idiom).
# Every doctor_check_<name>() reports through this helper exactly once.
# Input: verdict (pass|warn|fail), detail (one line), optional suggestion
# Sets globals for doctor_run_all() to collect:
#   DOCTOR_VERDICT, DOCTOR_DETAIL, DOCTOR_SUGGESTION
doctor_result() {
    local verdict="$1"
    local detail="$2"
    local suggestion="${3:-}"

    case "$verdict" in
        pass|warn|fail) ;;
        *)
            log_error "doctor_result: invalid verdict '$verdict'"
            return 1
            ;;
    esac

    DOCTOR_VERDICT="$verdict"
    DOCTOR_DETAIL="$detail"
    DOCTOR_SUGGESTION="$suggestion"
    return 0
}

# =============================================================================
# Check registry (indexed array; bash 3.2 compatible)
# Order matches the PRD-003 check table: environment, config, cache,
# brew surfaces.
# =============================================================================
doctor_checks() {
    printf '%s\n' \
        doctor_check_brew_present \
        doctor_check_brew_prefix \
        doctor_check_jq_present \
        doctor_check_bash_version \
        doctor_check_config_present \
        doctor_check_config_valid \
        doctor_check_config_effective \
        doctor_check_cache_dir \
        doctor_check_manifest_cache \
        doctor_check_ttl_sane \
        doctor_check_scan_formulae \
        doctor_check_scan_casks \
        doctor_check_cellar_caskroom \
        doctor_check_ghcr_reachable
}

# Check name (without the doctor_check_ prefix) for a check function name
# Input: check function name (e.g. doctor_check_brew_present)
# Output: check name (e.g. brew-present)
doctor_check_name() {
    local fn="$1"
    local name="${fn#doctor_check_}"
    printf '%s' "${name//_/-}"
}

# Group (per PRD-003 table) for a check function name
# Input: check function name
# Output: group name (environment|config|cache|brew surfaces)
doctor_check_group() {
    local fn="$1"
    case "$fn" in
        doctor_check_brew_present|doctor_check_brew_prefix|doctor_check_jq_present|doctor_check_bash_version)
            printf 'environment'
            ;;
        doctor_check_config_present|doctor_check_config_valid|doctor_check_config_effective)
            printf 'config'
            ;;
        doctor_check_cache_dir|doctor_check_manifest_cache|doctor_check_ttl_sane)
            printf 'cache'
            ;;
        *)
            printf 'brew surfaces'
            ;;
    esac
}

# =============================================================================
# Group: environment
# =============================================================================

# fail if brew is not on PATH
doctor_check_brew_present() {
    if command -v brew >/dev/null 2>&1; then
        doctor_result "pass" "brew found on PATH"
    else
        doctor_result "fail" "brew not found on PATH" \
            "install Homebrew: https://brew.sh (or fix PATH)"
    fi
}

# fail if `brew --prefix` is empty or not a directory; detail includes prefix
doctor_check_brew_prefix() {
    local prefix=""
    prefix=$(brew --prefix 2>/dev/null) || prefix=""
    if [[ -n "$prefix" && -d "$prefix" ]]; then
        doctor_result "pass" "$prefix"
    elif [[ -z "$prefix" ]]; then
        doctor_result "fail" "brew --prefix returned nothing" \
            "run: brew doctor"
    else
        doctor_result "fail" "prefix '$prefix' is not a directory" \
            "run: brew doctor"
    fi
}

# warn if jq is missing (required for --size/--json); suggest brew install jq
doctor_check_jq_present() {
    local version=""
    version=$(jq --version 2>/dev/null) || version=""
    if [[ -n "$version" ]]; then
        doctor_result "pass" "$version"
    else
        doctor_result "warn" "jq missing (required for --size/--json)" \
            "brew install jq"
    fi
}

# pass; detail notes bash version (3.2 supported, 4+ noted)
doctor_check_bash_version() {
    local major
    major="${BASH_VERSION%%.*}"
    if (( major >= 4 )); then
        doctor_result "pass" "bash $BASH_VERSION (4+; 3.2 also supported)"
    else
        doctor_result "pass" "bash $BASH_VERSION (3.2 supported)"
    fi
}

# =============================================================================
# Group: config
# =============================================================================

# pass with "no config file (defaults)" or the path in use
doctor_check_config_present() {
    local config_file="$BREW_USAGE_CONFIG_FILE"
    if [[ -f "$config_file" && -r "$config_file" ]]; then
        doctor_result "pass" "using $config_file"
    else
        doctor_result "pass" "no config file (defaults)"
    fi
}

# warn if malformed/unknown-key lines were found by load_config_file()
# (count + first file:line from the loader's diagnostic globals)
doctor_check_config_valid() {
    local count="${BREW_USAGE_CONFIG_MALFORMED:-0}"
    local first_bad="${BREW_USAGE_CONFIG_FIRST_BAD:-}"
    if [[ "$count" -eq 0 ]]; then
        doctor_result "pass" "config file parses cleanly"
    else
        doctor_result "warn" \
            "$count malformed line(s) in $BREW_USAGE_CONFIG_FILE (first at $first_bad)" \
            "edit $BREW_USAGE_CONFIG_FILE: KEY=VALUE, numeric values only"
    fi
}

# pass; detail shows effective values after config merge (mirrors the
# brew-usage entrypoint's initialization: TOP_N from BREW_USAGE_CONFIG_TOP_N
# with DEFAULT_TOP_N fallback)
doctor_check_config_effective() {
    local top_n thresholds cleanup_days
    top_n="${BREW_USAGE_CONFIG_TOP_N:-$DEFAULT_TOP_N}"
    thresholds="${SIZE_WARNING_THRESHOLD}/${SIZE_CRITICAL_THRESHOLD}"
    cleanup_days="$CACHE_CLEANUP_DAYS"
    doctor_result "pass" \
        "TOP_N=$top_n thresholds=$thresholds CACHE_CLEANUP_DAYS=$cleanup_days"
}

# =============================================================================
# Group: cache
# =============================================================================

# warn if the Homebrew cache is missing/unreadable; fail if it resolves to
# a path that exists but is not a directory
doctor_check_cache_dir() {
    local cache_dir=""
    cache_dir=$(cache_get_dir 2>/dev/null) || cache_dir=""
    if [[ -z "$cache_dir" ]]; then
        doctor_result "warn" "could not resolve Homebrew cache directory" \
            "run: brew --cache"
    elif [[ ! -d "$cache_dir" ]]; then
        doctor_result "fail" "cache path '$cache_dir' is not a directory"
    elif [[ ! -r "$cache_dir" ]]; then
        doctor_result "warn" "cache directory '$cache_dir' is not readable"
    else
        doctor_result "pass" "$cache_dir"
    fi
}

# pass; detail: <n> manifests, <m> expired by TTL. When expired manifests
# exist, suggest --flush-cache to force-refresh them.
# Scans only brew-usage's own cache naming (*--*--*.json) — never
# Homebrew's *bottle_manifest.json originals.
doctor_check_manifest_cache() {
    local cache_dir="$BREW_BOTTLE_CACHE_DIR"
    if [[ ! -d "$cache_dir" || ! -r "$cache_dir" ]]; then
        doctor_result "pass" "0 manifests, 0 expired by TTL"
        return 0
    fi

    local count=0 expired=0 f
    # Unmatched globs expand to the literal pattern; filter with -f
    for f in "$cache_dir"/*--*--*.json; do
        [[ -f "$f" ]] || continue
        count=$((count + 1))
        if ! is_cache_valid "$f"; then
            expired=$((expired + 1))
        fi
    done
    if (( expired > 0 )); then
        doctor_result "pass" "$count manifests, $expired expired by TTL" \
            "run: brew-usage --flush-cache to drop $expired expired manifest(s)"
    else
        doctor_result "pass" "$count manifests, 0 expired by TTL"
    fi
}

# warn if CACHE_CLEANUP_DAYS > 30 (stale cleanup suggestions); the manifest
# TTL is a readonly constant, not configurable, so is not checked
doctor_check_ttl_sane() {
    local days="$CACHE_CLEANUP_DAYS"
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        doctor_result "warn" "CACHE_CLEANUP_DAYS is not a number ('$days')" \
            "set CACHE_CLEANUP_DAYS to a number of days (default $DEFAULT_CACHE_CLEANUP_DAYS)"
    elif (( days > 30 )); then
        doctor_result "warn" "CACHE_CLEANUP_DAYS=$days (>30; cleanup suggestions may be stale)" \
            "set CACHE_CLEANUP_DAYS to $DEFAULT_CACHE_CLEANUP_DAYS or lower"
    else
        doctor_result "pass" "CACHE_CLEANUP_DAYS=$days"
    fi
}

# =============================================================================
# Group: brew surfaces
# =============================================================================

# fail if `brew list --formula` errors
doctor_check_scan_formulae() {
    if brew list --formula >/dev/null 2>&1; then
        doctor_result "pass" "brew list --formula works"
    else
        doctor_result "fail" "brew list --formula failed" \
            "run: brew doctor"
    fi
}

# warn if `brew list --cask` errors (cask-less Linux)
doctor_check_scan_casks() {
    if brew list --cask >/dev/null 2>&1; then
        doctor_result "pass" "brew list --cask works"
    else
        doctor_result "warn" "brew list --cask failed (normal on cask-less Linux)"
    fi
}

# warn per missing directory (with paths); fail if both missing
doctor_check_cellar_caskroom() {
    local prefix=""
    prefix=$(brew --prefix 2>/dev/null) || prefix=""
    if [[ -z "$prefix" ]]; then
        doctor_result "fail" "cannot determine prefix for Cellar/Caskroom"
        return 0
    fi

    local cellar="$prefix/Cellar" caskroom="$prefix/Caskroom"
    local cellar_ok=false caskroom_ok=false
    if [[ -d "$cellar" ]]; then cellar_ok=true; fi
    if [[ -d "$caskroom" ]]; then caskroom_ok=true; fi

    if $cellar_ok && $caskroom_ok; then
        doctor_result "pass" "$cellar and $caskroom present"
    elif $cellar_ok; then
        doctor_result "warn" "Caskroom missing: $caskroom"
    elif $caskroom_ok; then
        doctor_result "warn" "Cellar missing: $cellar" \
            "run: brew doctor"
    else
        doctor_result "fail" "Cellar and Caskroom both missing under $prefix" \
            "run: brew doctor"
    fi
}

# warn if the ghcr.io anonymous token endpoint is unreachable (degrades
# --size downloads; probe only — nothing is downloaded or written)
doctor_check_ghcr_reachable() {
    local probe_url="https://ghcr.io/token?scope=repository:homebrew/core/hello:pull"
    if ! command -v curl >/dev/null 2>&1; then
        doctor_result "warn" "curl not installed (--size downloads need it)" \
            "brew install curl"
    elif curl -fsS --max-time 5 -o /dev/null "$probe_url" 2>/dev/null; then
        doctor_result "pass" "ghcr.io reachable"
    else
        doctor_result "warn" "ghcr.io unreachable (--size downloads degraded; check network)"
    fi
}

# =============================================================================
# Runner
# =============================================================================

# Run every registered check, tally verdicts, collect results and
# suggestions. Strictly read-only; safe under set -euo pipefail (each check
# guards its own external commands).
# Sets globals:
#   DOCTOR_RESULT_NAMES/ GROUPS / VERDICTS / DETAILS / SUGGESTIONS (arrays)
#   DOCTOR_PASS, DOCTOR_WARN, DOCTOR_FAIL (counts)
#   DOCTOR_SUGGESTION_LIST (deduped suggestions, display order)
# Output: 0 always
doctor_run_all() {
    DOCTOR_RESULT_NAMES=()
    DOCTOR_RESULT_GROUPS=()
    DOCTOR_RESULT_VERDICTS=()
    DOCTOR_RESULT_DETAILS=()
    DOCTOR_RESULT_SUGGESTIONS=()
    DOCTOR_PASS=0
    DOCTOR_WARN=0
    DOCTOR_FAIL=0
    DOCTOR_SUGGESTION_LIST=()

    local fn name group verdict suggestion
    while IFS= read -r fn; do
        [[ -n "$fn" ]] || continue
        name=$(doctor_check_name "$fn")
        group=$(doctor_check_group "$fn")

        DOCTOR_VERDICT=""
        DOCTOR_DETAIL=""
        DOCTOR_SUGGESTION=""
        if ! "$fn"; then
            # A crashing check is itself a failure, never an abort
            DOCTOR_VERDICT="fail"
            DOCTOR_DETAIL="check crashed"
            DOCTOR_SUGGESTION="report a bug: https://github.com/shrwnsan/brew-usage/issues"
        fi
        [[ -n "$DOCTOR_VERDICT" ]] || DOCTOR_VERDICT="fail"
        [[ -n "$DOCTOR_DETAIL" ]] || DOCTOR_DETAIL="(no detail)"

        case "$DOCTOR_VERDICT" in
            pass) DOCTOR_PASS=$((DOCTOR_PASS + 1)) ;;
            warn) DOCTOR_WARN=$((DOCTOR_WARN + 1)) ;;
            fail) DOCTOR_FAIL=$((DOCTOR_FAIL + 1)) ;;
        esac

        DOCTOR_RESULT_NAMES+=("$name")
        DOCTOR_RESULT_GROUPS+=("$group")
        DOCTOR_RESULT_VERDICTS+=("$DOCTOR_VERDICT")
        DOCTOR_RESULT_DETAILS+=("$DOCTOR_DETAIL")
        DOCTOR_RESULT_SUGGESTIONS+=("$DOCTOR_SUGGESTION")

        suggestion="$DOCTOR_SUGGESTION"
        if [[ -n "$suggestion" ]]; then
            local seen=false existing
            # bash 3.2: guard the empty-array expansion
            for existing in ${DOCTOR_SUGGESTION_LIST[@]+"${DOCTOR_SUGGESTION_LIST[@]}"}; do
                if [[ "$existing" == "$suggestion" ]]; then
                    seen=true
                    break
                fi
            done
            if ! $seen; then
                DOCTOR_SUGGESTION_LIST+=("$suggestion")
            fi
        fi
    done < <(doctor_checks)

    return 0
}

# =============================================================================
# Fix registry and repair actions (doctor --fix / --fix --yes, PRD-004)
#
# The registry maps fixable findings to repairs. Each entry is one line
# (bash 3.2: indexed text, no associative arrays):
#   fix_id|source_check|tier|apply_function
# --fix is dry-run by default; --yes applies safe-tier fixes and the entry
# point re-runs the full doctor pass afterwards. Fixes may only touch
# brew-usage-owned state (own-state rule).
# =============================================================================

# Count brew-usage-owned manifest cache files whose TTL expired (same scan
# as doctor_check_manifest_cache, minus the verdict)
# Output: expired count (0 when the cache dir is missing/unreadable)
doctor_count_expired_manifests() {
    local cache_dir="$BREW_BOTTLE_CACHE_DIR"
    local expired=0 f

    if [[ ! -d "$cache_dir" || ! -r "$cache_dir" ]]; then
        printf '0'
        return 0
    fi

    # Unmatched globs expand to the literal pattern; filter with -f
    for f in "$cache_dir"/*--*--*.json; do
        [[ -f "$f" ]] || continue
        if ! is_cache_valid "$f"; then
            expired=$((expired + 1))
        fi
    done
    printf '%s' "$expired"
}

# Fix registry (line format: fix_id|source_check|tier|apply_function)
doctor_fixes() {
    printf '%s\n' \
        "flush-expired-manifests|manifest-cache|safe|flush_expired_manifests"
}

# Whether a registry entry currently has fixable findings, and per-fix
# description for the plan listing
# Input: fix_id
# Output: description line when the fix is due, nothing otherwise
doctor_fix_description() {
    local fix_id="$1"

    case "$fix_id" in
        flush-expired-manifests)
            local expired
            expired=$(doctor_count_expired_manifests)
            if (( expired > 0 )); then
                printf 'Remove %s expired manifest cache file(s) (brew-usage-owned only)' "$expired"
            fi
            ;;
    esac
}

# Print the dry-run plan for `doctor --fix` (nothing is applied)
# Sets globals: DOCTOR_FIX_PLANNED (number of fixes with findings)
doctor_plan_fixes() {
    DOCTOR_FIX_PLANNED=0

    local fix_id check_id description
    echo ""
    echo "Planned fixes (dry run — nothing applied):"
    while IFS='|' read -r fix_id check_id _ _; do
        [[ -n "$fix_id" ]] || continue
        description=""
        description=$(doctor_fix_description "$fix_id")
        [[ -n "$description" ]] || continue

        printf '  %s  [%s]\n' "$fix_id" "$check_id"
        printf '    %s\n' "$description"
        DOCTOR_FIX_PLANNED=$((DOCTOR_FIX_PLANNED + 1))
    done < <(doctor_fixes)

    echo ""
    if (( DOCTOR_FIX_PLANNED == 0 )); then
        echo "No fixes available (findings are report-only)."
    elif (( DOCTOR_FIX_PLANNED == 1 )); then
        echo "1 fix planned. Re-run with --yes to apply."
    else
        echo "$DOCTOR_FIX_PLANNED fixes planned. Re-run with --yes to apply."
    fi
    return 0
}

# Apply every registry fix with current findings (doctor --fix --yes).
# Prints one "applied:" line per fix. Own-state rule: apply functions may
# only touch brew-usage-owned files.
# Sets globals: DOCTOR_FIX_APPLIED (fixes successfully applied),
#               DOCTOR_FIX_DUE (fixes with findings, applied or failed)
doctor_apply_fixes() {
    DOCTOR_FIX_APPLIED=0
    DOCTOR_FIX_DUE=0

    local fix_id apply_fn description result
    while IFS='|' read -r fix_id _ _ apply_fn; do
        [[ -n "$fix_id" ]] || continue
        description=""
        description=$(doctor_fix_description "$fix_id")
        [[ -n "$description" ]] || continue
        DOCTOR_FIX_DUE=$((DOCTOR_FIX_DUE + 1))

        # Capture the apply function's summary line; a failing apply must
        # never abort the pass (set -e safety in the entry point) and must
        # not count as applied (it would trigger a pointless re-run)
        result=""
        if result=$("$apply_fn"); then
            printf 'applied: %s — %s\n' "$fix_id" "$result"
            DOCTOR_FIX_APPLIED=$((DOCTOR_FIX_APPLIED + 1))
        else
            printf 'apply FAILED: %s — %s\n' "$fix_id" "${result:-no output}"
        fi
    done < <(doctor_fixes)

    if (( DOCTOR_FIX_DUE == 0 )); then
        echo "No fixes available (findings are report-only)."
    fi
    return 0
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_DOCTOR_LOADED:-} when standalone-sourced
readonly BREW_USAGE_DOCTOR_LOADED=true
