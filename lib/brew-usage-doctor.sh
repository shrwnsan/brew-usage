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
# Fix registry and repair actions (doctor --fix / --fix --yes, PRD-004 +
# PRD-005)
#
# The registry maps fixable findings to repairs. Each entry is one line
# (bash 3.2: indexed text, no associative arrays):
#   fix_id|source_check|tier|apply_function
# --fix is dry-run by default; --yes applies due fixes and the entry
# point re-runs the full doctor pass afterwards. Fixes may only touch
# brew-usage-owned state (own-state rule). The config tier (PRD-005)
# crosses that line deliberately: the user config file is edited only by
# commenting lines out — never deleted, never rewritten wholesale — and
# only after a timestamped backup.
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

# Count malformed and unknown-key lines in the config file by re-parsing it
# with the exact load_config_file() rules (the loader's diagnostic globals
# may be stale after earlier edits in the same pass). Unknown keys count as
# bad lines, matching load_config_file()'s BREW_USAGE_CONFIG_MALFORMED
# tally; comments, blanks and valid whitelisted lines do not.
# Output: bad-line count (0 when the config file is missing/unreadable)
doctor_count_config_bad_lines() {
    local config_file="$BREW_USAGE_CONFIG_FILE"

    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        printf '0'
        return 0
    fi

    local line check_line key count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        check_line="${line%$'\r'}"
        if [[ -z "$check_line" || "$check_line" == \#* ]]; then
            continue
        fi
        if [[ "$check_line" =~ ^[A-Z_][A-Z0-9_]*=[0-9]{1,9}$ ]]; then
            key="${check_line%%=*}"
            case "$key" in
                TOP_N|SIZE_WARNING_THRESHOLD|SIZE_CRITICAL_THRESHOLD|CACHE_CLEANUP_DAYS) ;;
                *) count=$((count + 1)) ;;
            esac
        else
            count=$((count + 1))
        fi
    done < "$config_file"
    printf '%s' "$count"
}

# Make the once-per-apply-pass timestamped backup of the config file
# (PRD-005 safety: the pre-edit original stays recoverable next to it).
# Output: 0 (backup created), 1 (backup impossible — no edits may proceed)
doctor_backup_config_file() {
    local config_file="$BREW_USAGE_CONFIG_FILE"
    local backup
    backup="${config_file}.bak-$(date +%Y%m%d%H%M%S)"

    if cp -p "$config_file" "$backup" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Guard for config-tier apply functions: the shared once-per-pass backup
# must exist before any config edit. doctor_apply_fixes() performs the
# backup in the main shell (apply functions run in subshells and cannot
# record pass state there); standalone apply calls (unit tests) fall
# through to their own backup attempt.
# Output: 0 (backup ready for this pass), 1 (backup impossible)
doctor_config_backup_ready() {
    case "${DOCTOR_CONFIG_BACKUP_OK:-}" in
        true) return 0 ;;
        false) return 1 ;;  # already attempted and failed this pass
    esac
    doctor_backup_config_file
}

# Create the atomic-write staging file in the config file's own directory
# (same filesystem, so the final mv is atomic). mktemp creates it 0600, so
# the original config file's permissions are restored on the staging file.
# Output: staging file path; exit 1 (no output) when creation fails
doctor_config_staging_file() {
    local config_file="$BREW_USAGE_CONFIG_FILE"
    local config_dir tmp perms
    config_dir=$(dirname "$config_file")
    tmp=$(mktemp "${config_dir}/.brew-usage-fix.XXXXXX" 2>/dev/null) || return 1

    # Preserve the user's config file permissions (stat is not flag-portable)
    if is_macos; then
        perms=$(stat -f %Lp "$config_file" 2>/dev/null) || perms=""
    else
        perms=$(stat -c %a "$config_file" 2>/dev/null) || perms=""
    fi
    if [[ -n "$perms" ]]; then
        chmod "$perms" "$tmp" 2>/dev/null || true
    fi
    printf '%s' "$tmp"
}

# Fix registry (line format: fix_id|source_check|tier|apply_function)
# Tiers: safe (brew-usage cache state), config (user config file — edited
# only by commenting lines out, always preceded by a timestamped backup)
doctor_fixes() {
    printf '%s\n' \
        "flush-expired-manifests|manifest-cache|safe|flush_expired_manifests" \
        "repair-config-lines|config-valid|config|repair_config_lines" \
        "clamp-cache-ttl|ttl-sane|config|clamp_cache_ttl"
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
        repair-config-lines)
            local bad
            bad=$(doctor_count_config_bad_lines)
            if (( bad > 0 )); then
                printf 'Comment out %s malformed/unknown-key line(s) (config backed up first)' "$bad"
            fi
            ;;
        clamp-cache-ttl)
            # Only due when the CURRENT effective value fails the sane test;
            # non-numeric is impossible post-loader (the loader never assigns
            # non-numeric values)
            local days="$CACHE_CLEANUP_DAYS"
            if [[ "$days" =~ ^[0-9]+$ ]] && (( days > 30 )); then
                printf 'Clamp CACHE_CLEANUP_DAYS: %s -> 30' "$days"
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
# only touch brew-usage-owned files (the config tier additionally never
# deletes a line — it comments lines out, after a timestamped backup).
# Before the first config edit, one shared timestamped backup of the config
# file is made in this (main) shell — apply functions run in subshells and
# cannot share pass state; a failed backup fails every config fix with
# zero edits.
# Sets globals: DOCTOR_FIX_APPLIED (fixes successfully applied),
#               DOCTOR_FIX_DUE (fixes with findings, applied or failed),
#               DOCTOR_CONFIG_FIX_APPLIED (true when a config-tier fix
#               applied — the entry point then re-runs load_config_file),
#               DOCTOR_FIX_RESULT_IDS/STATUSES/LINES (per-due-fix id,
#               "applied"|"failed", and result line; PRD-005 JSON plan)
doctor_apply_fixes() {
    DOCTOR_FIX_APPLIED=0
    DOCTOR_FIX_DUE=0
    DOCTOR_CONFIG_FIX_APPLIED=false
    DOCTOR_FIX_RESULT_IDS=()
    DOCTOR_FIX_RESULT_STATUSES=()
    DOCTOR_FIX_RESULT_LINES=()

    # Once-per-pass config backup: made as soon as any config-tier fix is
    # due, so two config fixes share one backup (PRD-005 review note)
    DOCTOR_CONFIG_BACKUP_OK=""
    local fix_id tier description
    while IFS='|' read -r fix_id _ tier _; do
        [[ -n "$fix_id" ]] || continue
        [[ "$tier" == "config" ]] || continue
        description=""
        description=$(doctor_fix_description "$fix_id")
        [[ -n "$description" ]] || continue
        if doctor_backup_config_file; then
            DOCTOR_CONFIG_BACKUP_OK=true
        else
            DOCTOR_CONFIG_BACKUP_OK=false
        fi
        break
    done < <(doctor_fixes)

    local apply_fn result status
    while IFS='|' read -r fix_id _ tier apply_fn; do
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
            status="applied"
            if [[ "$tier" == "config" ]]; then
                # shellcheck disable=SC2034 # read by the brew-usage entry point (config re-source)
                DOCTOR_CONFIG_FIX_APPLIED=true
            fi
        else
            printf 'apply FAILED: %s — %s\n' "$fix_id" "${result:-no output}"
            status="failed"
        fi
        DOCTOR_FIX_RESULT_IDS+=("$fix_id")
        DOCTOR_FIX_RESULT_STATUSES+=("$status")
        DOCTOR_FIX_RESULT_LINES+=("${result:-no output}")
    done < <(doctor_fixes)

    if (( DOCTOR_FIX_DUE == 0 )); then
        echo "No fixes available (findings are report-only)."
    fi
    return 0
}

# Apply function for the repair-config-lines fix (tier: config).
# Re-parses the config file fresh — the loader's diagnostics may be stale
# after earlier edits — applying the exact load_config_file() rules (strip
# trailing CR, skip blanks/comments, ^[A-Z_][A-Z0-9_]*=[0-9]{1,9}$ plus the
# 4 whitelisted keys), and comments out every malformed or unknown-key line
# with the '# brew-usage-fix disabled line N: ' prefix (originals stay
# readable behind the marker). Lines are emitted byte-for-byte, so CRLF
# files keep their line endings; the write is atomic (staging file in the
# config directory + mv).
# Output: "<n> line(s) disabled"
# Exit codes: 0 (lines disabled, or nothing left to disable), 1 (no edit
#             was possible — nothing was written)
repair_config_lines() {
    local config_file="$BREW_USAGE_CONFIG_FILE"

    # config-valid only warns when the file exists and has bad lines; with
    # no file the fix is not due and there is nothing to repair
    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        echo "config file not found"
        return 1
    fi

    # The atomic replace (mv) would swap a symlink for a regular file and
    # desync dotfile-manager setups — refuse with zero edits instead
    if [[ -L "$config_file" ]]; then
        echo "config file is a symlink; repair manually"
        return 1
    fi

    # The shared once-per-pass backup must exist before any edit
    if ! doctor_config_backup_ready; then
        echo "config backup failed"
        return 1
    fi

    local tmp
    tmp=$(doctor_config_staging_file) || {
        echo "cannot create staging file in the config directory"
        return 1
    }

    local line check_line key disabled=0 line_no=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        # Evaluate the CR-stripped line with the loader's exact rules, but
        # emit the original bytes (CRLF files stay CRLF)
        check_line="${line%$'\r'}"
        if [[ -z "$check_line" || "$check_line" == \#* ]]; then
            printf '%s\n' "$line"
        elif [[ "$check_line" =~ ^[A-Z_][A-Z0-9_]*=[0-9]{1,9}$ ]]; then
            key="${check_line%%=*}"
            case "$key" in
                TOP_N|SIZE_WARNING_THRESHOLD|SIZE_CRITICAL_THRESHOLD|CACHE_CLEANUP_DAYS)
                    printf '%s\n' "$line"
                    ;;
                *)
                    printf '# brew-usage-fix disabled line %s: %s\n' "$line_no" "$line"
                    disabled=$((disabled + 1))
                    ;;
            esac
        else
            printf '# brew-usage-fix disabled line %s: %s\n' "$line_no" "$line"
            disabled=$((disabled + 1))
        fi
    done < "$config_file" > "$tmp"

    if (( disabled == 0 )); then
        # Nothing to disable (file changed under us): leave it untouched
        rm -f "$tmp"
        echo "0 line(s) disabled"
        return 0
    fi

    if ! mv -f "$tmp" "$config_file" 2>/dev/null; then
        rm -f "$tmp"
        echo "cannot replace config file"
        return 1
    fi
    echo "$disabled line(s) disabled"
    return 0
}

# Apply function for the clamp-cache-ttl fix (tier: config).
# Only due when the CURRENT effective CACHE_CLEANUP_DAYS exceeds 30
# (non-numeric is impossible post-loader). Re-parses the config file
# fresh; each valid CACHE_CLEANUP_DAYS=N line is commented with
# '# brew-usage-fix clamped from N' and CACHE_CLEANUP_DAYS=30 is written
# in its place (when the value came from the environment rather than the
# file, the pair is appended). Atomic write as in repair_config_lines().
# Output: "CACHE_CLEANUP_DAYS=<old> -> 30"
# Exit codes: 0 (clamped, or already sane at apply time), 1 (no edit
#             was possible — nothing was written)
clamp_cache_ttl() {
    local config_file="$BREW_USAGE_CONFIG_FILE"
    local current="$CACHE_CLEANUP_DAYS"

    if ! [[ "$current" =~ ^[0-9]+$ ]] || (( current <= 30 )); then
        echo "CACHE_CLEANUP_DAYS=$current already sane"
        return 0
    fi

    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        echo "config file not found"
        return 1
    fi

    # Symlinked config: see repair_config_lines — refuse, zero edits
    if [[ -L "$config_file" ]]; then
        echo "config file is a symlink; repair manually"
        return 1
    fi

    # The shared once-per-pass backup must exist before any edit
    if ! doctor_config_backup_ready; then
        echo "config backup failed"
        return 1
    fi

    local tmp
    tmp=$(doctor_config_staging_file) || {
        echo "cannot create staging file in the config directory"
        return 1
    }

    local line check_line value clamped=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        check_line="${line%$'\r'}"
        if [[ "$check_line" =~ ^CACHE_CLEANUP_DAYS=[0-9]{1,9}$ ]]; then
            value="${check_line#CACHE_CLEANUP_DAYS=}"
            printf '# brew-usage-fix clamped from %s\nCACHE_CLEANUP_DAYS=30\n' "$value"
            clamped=true
        else
            printf '%s\n' "$line"
        fi
    done < "$config_file" > "$tmp"

    if ! $clamped; then
        # Effective value came from the environment, not the file: pin the
        # clamped value explicitly by appending the pair
        printf '# brew-usage-fix clamped from %s\nCACHE_CLEANUP_DAYS=30\n' "$current" >> "$tmp"
    fi

    if ! mv -f "$tmp" "$config_file" 2>/dev/null; then
        rm -f "$tmp"
        echo "cannot replace config file"
        return 1
    fi
    echo "CACHE_CLEANUP_DAYS=$current -> 30"
    return 0
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_DOCTOR_LOADED:-} when standalone-sourced
readonly BREW_USAGE_DOCTOR_LOADED=true
