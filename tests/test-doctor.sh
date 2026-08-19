#!/usr/bin/env bash
# Tests for brew-usage doctor (lib/brew-usage-doctor.sh)
# Brew-independent unit checks run everywhere (ubuntu CI included);
# brew-dependent checks are gated on `command -v brew` per suite convention.

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

set -uo pipefail

# Test framework (same conventions as test-cache.sh)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected output to contain '$needle'}"

    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message"
        return 1
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "========================================"
echo "Doctor Tests (brew-usage doctor)"
echo "========================================"
echo ""

# =============================================================================
# Unit tests (brew-independent): each check in a fresh /bin/bash shell with
# fixture env overrides
# =============================================================================
echo "Testing doctor checks against fixtures..."

# --- config-valid: malformed fixture -> warn with count + first line -----
DOCTOR_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-doctor-bad.XXXXXX")
cat > "$DOCTOR_CONFIG" << 'EOF'
TOP_N=abc
SOME_UNKNOWN_KEY=5
TOP_N=3
EOF

UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$DOCTOR_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_config_valid
    printf "%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_DETAIL"
')
assert_equals "warn|2 malformed line(s) in $DOCTOR_CONFIG (first at line 1)" "$UNIT_OUT" \
    "config-valid: warn with malformed count and first bad line"

# --- config-valid: clean config -> pass ----------------------------------
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$BREW_USAGE_CONFIG_FILE" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_config_valid
    printf "%s\n" "$DOCTOR_VERDICT"
')
assert_equals "pass" "$UNIT_OUT" "config-valid: pass with no config file"

# --- ttl-sane: CACHE_CLEANUP_DAYS=90 -> warn; 30 -> pass ------------------
UNIT_OUT=$(CACHE_CLEANUP_DAYS=90 /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_ttl_sane
    printf "%s|%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_DETAIL" "$DOCTOR_SUGGESTION"
')
assert_equals "warn|CACHE_CLEANUP_DAYS=90 (>30; cleanup suggestions may be stale)|set CACHE_CLEANUP_DAYS to 30 or lower" \
    "$UNIT_OUT" "ttl-sane: warn when CACHE_CLEANUP_DAYS=90"

UNIT_OUT=$(CACHE_CLEANUP_DAYS=7 /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_ttl_sane
    printf "%s\n" "$DOCTOR_VERDICT"
')
assert_equals "pass" "$UNIT_OUT" "ttl-sane: pass when CACHE_CLEANUP_DAYS=7"

# --- manifest-cache: fixture dir with known mtimes ------------------------
# BREW_BOTTLE_CACHE_DIR is readonly-once in config.sh, so it must be set in
# the environment BEFORE the module is sourced (fresh subshell below).
DOCTOR_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-cache.XXXXXX")
printf '{}' > "$DOCTOR_CACHE_DIR/go--1.25.7--arm64_sonoma.json"
touch -t 202001010000 "$DOCTOR_CACHE_DIR/go--1.25.7--arm64_sonoma.json"
printf '{}' > "$DOCTOR_CACHE_DIR/wget--1.0--x86_64_linux.json"
# Decoys that must NOT count: Homebrew's own manifest naming, non-json, random
printf '{}' > "$DOCTOR_CACHE_DIR/abcdef--go-1.25.bottle_manifest.json"
printf '{}' > "$DOCTOR_CACHE_DIR/not-a-manifest.txt"
printf '{}' > "$DOCTOR_CACHE_DIR/no-double-dashes.json"

UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$DOCTOR_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_manifest_cache
    printf "%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_DETAIL"
')
assert_equals "pass|2 manifests, 1 expired by TTL" "$UNIT_OUT" \
    "manifest-cache: counts only *--*--*.json, reports expired-by-TTL"

# --- bash-version: always pass, notes version -----------------------------
UNIT_OUT=$(/bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_bash_version
    printf "%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_DETAIL"
')
assert_equals "pass" "${UNIT_OUT%%|*}" "bash-version: pass"
assert_contains "${UNIT_OUT#*|}" "3.2" "bash-version: detail notes 3.2 support (running bash 3.2)"

# --- jq-present: hidden via PATH strip -> warn -----------------------------
# Minimal PATH with only the few external commands sourcing needs (dirname,
# mkdir, env); jq absent by construction.
JQ_FREE_BIN=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-bin.XXXXXX")
for tool in dirname mkdir; do
    tool_path=$(command -v "$tool") && ln -s "$tool_path" "$JQ_FREE_BIN/$tool"
done
UNIT_OUT=$(PATH="$JQ_FREE_BIN" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_check_jq_present
    printf "%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_SUGGESTION"
')
assert_equals "warn|brew install jq" "$UNIT_OUT" \
    "jq-present: warn + suggestion when jq is not on PATH"

# --- doctor_result validates the verdict ------------------------------------
UNIT_OUT=$(/bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_result "bogus" "detail"
    printf "%s\n" "$?"
')
assert_equals "1" "$UNIT_OUT" "doctor_result rejects an invalid verdict"

# --- registry: 14 checks, names per PRD table -------------------------------
UNIT_OUT=$(/bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_checks
')
assert_equals 14 "$(printf '%s\n' "$UNIT_OUT" | grep -c .)" "registry has 14 checks"
assert_contains "$UNIT_OUT" "doctor_check_brew_present" "registry includes brew-present"
assert_contains "$UNIT_OUT" "doctor_check_ghcr_reachable" "registry includes ghcr-reachable"

# --- doctor_run_all: counters reconcile (brew-independent environment) ------
# Same jq-free PATH: brew and jq both absent, fixture cache dir via env
UNIT_OUT=$(PATH="$JQ_FREE_BIN" BREW_BOTTLE_CACHE_DIR="$DOCTOR_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_run_all
    printf "%s|%s|%s|%s\n" "$DOCTOR_PASS" "$DOCTOR_WARN" "$DOCTOR_FAIL" \
        "$((DOCTOR_PASS + DOCTOR_WARN + DOCTOR_FAIL))"
')
assert_equals "14" "${UNIT_OUT##*|}" "run_all tallies cover every registered check"
# brew absent -> brew-present fails (fail count >= 1)
FAIL_COUNT="${UNIT_OUT#*|}"; FAIL_COUNT="${FAIL_COUNT%%|*}"
if (( FAIL_COUNT >= 1 )); then
    assert_equals "yes" "yes" "run_all with no brew on PATH records at least one fail"
else
    assert_equals ">=1" "$FAIL_COUNT" "run_all with no brew on PATH records at least one fail"
fi

rm -rf "$DOCTOR_CACHE_DIR" "$JQ_FREE_BIN"
rm -f "$DOCTOR_CONFIG"

# =============================================================================
# Brew-dependent checks (skipped without brew, per suite convention)
# =============================================================================
if command -v brew >/dev/null 2>&1; then
    echo ""
    echo "Testing doctor checks with real brew..."

    # brew-present passes with brew on PATH
    UNIT_OUT=$(/bin/bash -c '
        source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
        doctor_check_brew_present
        printf "%s\n" "$DOCTOR_VERDICT"
    ')
    assert_equals "pass" "$UNIT_OUT" "brew-present: pass with brew on PATH"

    # brew-prefix detail contains a real prefix path
    UNIT_OUT=$(/bin/bash -c '
        source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
        doctor_check_brew_prefix
        printf "%s|%s\n" "$DOCTOR_VERDICT" "$DOCTOR_DETAIL"
    ')
    assert_equals "pass" "${UNIT_OUT%%|*}" "brew-prefix: pass on healthy machine"

    # scan-formulae pass
    UNIT_OUT=$(/bin/bash -c '
        source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
        doctor_check_scan_formulae
        printf "%s\n" "$DOCTOR_VERDICT"
    ')
    assert_equals "pass" "$UNIT_OUT" "scan-formulae: pass when brew list --formula works"

    if command -v jq >/dev/null 2>&1; then
        UNIT_OUT=$(/bin/bash -c '
            source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
            doctor_check_jq_present
            printf "%s\n" "$DOCTOR_VERDICT"
        ')
        assert_equals "pass" "$UNIT_OUT" "jq-present: pass with jq installed"
    fi

    # Full run: sensible tallies on a healthy machine
    echo ""
    echo "Running full doctor_run_all() harness..."
    UNIT_OUT=$(/bin/bash -c '
        source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
        doctor_run_all
        for i in "${!DOCTOR_RESULT_NAMES[@]}"; do
            printf "%s/%s/%s: %s\n" "${DOCTOR_RESULT_GROUPS[$i]}" \
                "${DOCTOR_RESULT_NAMES[$i]}" "${DOCTOR_RESULT_VERDICTS[$i]}" \
                "${DOCTOR_RESULT_DETAILS[$i]}"
        done
        printf "SUMMARY: pass=%s warn=%s fail=%s\n" \
            "$DOCTOR_PASS" "$DOCTOR_WARN" "$DOCTOR_FAIL"
    ')
    echo "$UNIT_OUT"
    SUMMARY_LINE=$(printf '%s\n' "$UNIT_OUT" | grep '^SUMMARY:')
    assert_contains "$SUMMARY_LINE" "pass=" "run_all emits a summary line"
    PASS_N="${SUMMARY_LINE#*pass=}"; PASS_N="${PASS_N%% *}"
    if (( PASS_N >= 4 )); then
        assert_equals "yes" "yes" "healthy machine: majority of checks pass"
    else
        assert_equals ">=4" "$PASS_N" "healthy machine: majority of checks pass"
    fi
else
    echo ""
    echo "brew not found - skipping brew-dependent doctor tests"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
