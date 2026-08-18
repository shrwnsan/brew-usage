#!/usr/bin/env bash
# Tests for brew-usage config file support (~/.brew-usage-config)

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

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected exit code $expected, got $actual}"

    ((TESTS_RUN++))

    if [[ "$actual" -eq "$expected" ]]; then
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
BREW_USAGE="$SCRIPT_DIR/brew-usage"

# A nonexistent config path: guarantees no user config interferes with tests
NO_CONFIG=$(mktemp -u "${TMPDIR:-/tmp}/brew-usage-no-config.XXXXXX")
# Only created in the brew-gated CLI section; predefine for cleanup under set -u
TOP_CONFIG=""

echo "========================================"
echo "Config File Tests (~/.brew-usage-config)"
echo "========================================"
echo ""

# =============================================================================
# Unit tests: load_config_file() in a fresh /bin/bash shell
# =============================================================================
echo "Testing load_config_file() parsing..."

UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$NO_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh" 2>&1 1>/dev/null
    printf "STATUS:%s\n" "$?"
' 2>/dev/null)
assert_equals "STATUS:0" "$UNIT_OUT" "missing config file: no warnings, no failure"

UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$NO_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s|%s|%s|%s\n" "$SIZE_WARNING_THRESHOLD" "$SIZE_CRITICAL_THRESHOLD" \
        "$CACHE_CLEANUP_DAYS" "${BREW_USAGE_CONFIG_TOP_N:-unset}"
')
assert_equals "104857600|1073741824|30|unset" "$UNIT_OUT" \
    "missing config file: built-in defaults apply"

# Valid values are applied
TEST_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-test.XXXXXX")
cat > "$TEST_CONFIG" << 'EOF'
# comment line (ignored)
TOP_N=3
SIZE_WARNING_THRESHOLD=1000
SIZE_CRITICAL_THRESHOLD=9000
CACHE_CLEANUP_DAYS=7
EOF

UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$TEST_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s|%s|%s|%s\n" "$SIZE_WARNING_THRESHOLD" "$SIZE_CRITICAL_THRESHOLD" \
        "$CACHE_CLEANUP_DAYS" "$BREW_USAGE_CONFIG_TOP_N"
' 2>/dev/null)
assert_equals "1000|9000|7|3" "$UNIT_OUT" "valid KEY=number lines override defaults"

# CRLF (Windows-edited) line endings are tolerated
CRLF_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-crlf.XXXXXX")
printf 'TOP_N=3\r\nCACHE_CLEANUP_DAYS=7\r\n' > "$CRLF_CONFIG"
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$CRLF_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s|%s\n" "$BREW_USAGE_CONFIG_TOP_N" "$CACHE_CLEANUP_DAYS"
' 2>/dev/null)
assert_equals "3|7" "$UNIT_OUT" "CRLF line endings are stripped and values applied"

# Absurdly long values (>9 digits) are rejected as malformed
ABSURD_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-absurd.XXXXXX")
printf 'CACHE_CLEANUP_DAYS=1234567890123\n' > "$ABSURD_CONFIG"
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$ABSURD_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
' 2>&1 >/dev/null)
assert_contains "$UNIT_OUT" "malformed" "absurdly long value rejected as malformed"
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$ABSURD_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s\n" "$CACHE_CLEANUP_DAYS"
' 2>/dev/null)
assert_equals "30" "$UNIT_OUT" "absurdly long value ignored, default kept"

# Malformed lines: warning names line numbers, values skipped, no crash
MALFORMED_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-bad.XXXXXX")
cat > "$MALFORMED_CONFIG" << 'EOF'
TOP_N=abc
rm -rf ~
$(reboot)
lowercase=5
SIZE_CRITICAL_THRESHOLD=notanumber
TOP_N=3
EOF

UNIT_ERR=$(BREW_USAGE_CONFIG_FILE="$MALFORMED_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s|%s\n" "$SIZE_CRITICAL_THRESHOLD" "${BREW_USAGE_CONFIG_TOP_N:-unset}" >&2
' 2>&1 >/dev/null)
# Lines 1-5 are malformed; line 6 (TOP_N=3) still applies.
# Critical threshold keeps its default; TOP_N is picked up.
if [[ "$UNIT_ERR" == *"line 1"* && "$UNIT_ERR" == *"line 2"* \
    && "$UNIT_ERR" == *"line 4"* && "$UNIT_ERR" == *"line 5"* ]]; then
    assert_equals "yes" "yes" "malformed lines produce warnings naming line numbers"
else
    assert_equals "with-line-numbers" "$UNIT_ERR" "malformed lines produce warnings naming line numbers"
fi
assert_contains "$UNIT_ERR" "1073741824|3" \
    "malformed lines skipped (default kept), later valid line applied"
assert_contains "$UNIT_ERR" "rm -rf ~" "malformed warning quotes the offending line"

# Malicious content is never executed
DESTRUCTIVE_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-evil.XXXXXX")
MARKER=$(mktemp -u "${TMPDIR:-/tmp}/brew-usage-marker.XXXXXX")
cat > "$DESTRUCTIVE_CONFIG" << EOF
TOP_N=2; touch "$MARKER"
EOF
BREW_USAGE_CONFIG_FILE="$DESTRUCTIVE_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
' >/dev/null 2>&1
if [[ -e "$MARKER" ]]; then
    assert_equals "not-executed" "executed" "config file content is never executed"
else
    assert_equals "not-executed" "not-executed" "config file content is never executed"
fi

# Unknown keys: warning + ignored
UNKNOWN_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-unknown.XXXXXX")
cat > "$UNKNOWN_CONFIG" << 'EOF'
SOMETHING_ELSE=42
TOP_N=4
EOF
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNKNOWN_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    printf "%s|%s\n" "$BREW_USAGE_CONFIG_TOP_N" "${SOMETHING_ELSE:-unset}"
' 2>/dev/null)
UNIT_ERR=$(BREW_USAGE_CONFIG_FILE="$UNKNOWN_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
' 2>&1 >/dev/null)
assert_equals "4|unset" "$UNIT_OUT" "unknown key ignored, known key applied"
assert_contains "$UNIT_ERR" "unknown key 'SOMETHING_ELSE'" "unknown key produces a warning"

# =============================================================================
# Unit tests: thresholds from config affect get_size_color()
# =============================================================================
echo ""
echo "Testing config thresholds drive get_size_color()..."

COLOR_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-color.XXXXXX")
cat > "$COLOR_CONFIG" << 'EOF'
SIZE_WARNING_THRESHOLD=1000
SIZE_CRITICAL_THRESHOLD=9000
EOF
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$COLOR_CONFIG" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-config.sh"
    source "'"$SCRIPT_DIR"'/lib/brew-usage-utils.sh"
    printf "%s|%s|%s\n" "$(get_size_color 500)" "$(get_size_color 5000)" "$(get_size_color 9500)"
' 2>/dev/null)
assert_equals "$(printf '\033[0;32m')|$(printf '\033[0;33m')|$(printf '\033[0;31m')" "$UNIT_OUT" \
    "config thresholds drive green/yellow/red color coding"

# =============================================================================
# Unit tests: CACHE_CLEANUP_DAYS from config drives cache_analyze()
# =============================================================================
echo ""
echo "Testing CACHE_CLEANUP_DAYS from config drives cache_analyze()..."

TEST_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-config-cache.XXXXXX")
mkdir -p "$TEST_CACHE_DIR/downloads"
printf '%.0sX' {1..100} > "$TEST_CACHE_DIR/downloads/old-bottle.tar.gz"
touch -t 202001010000 "$TEST_CACHE_DIR/downloads/old-bottle.tar.gz"
printf '%.0sX' {1..10} > "$TEST_CACHE_DIR/downloads/new-bottle.tar.gz"
touch "$TEST_CACHE_DIR/downloads/new-bottle.tar.gz"

CACHE_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-cache-days.XXXXXX")
printf 'CACHE_CLEANUP_DAYS=36500\n' > "$CACHE_CONFIG"

# Default (30 days): the 2020-mtime file is a candidate
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$NO_CONFIG" BREW_USAGE_CACHE_ANALYSIS_DIR="$TEST_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-cache.sh"
    cache_analyze || exit 1
    printf "%s|%s\n" "$CACHE_CLEANUP_BYTES" "$CACHE_CLEANUP_COUNT"
' 2>/dev/null)
assert_equals "100|1" "$UNIT_OUT" "default CACHE_CLEANUP_DAYS flags old file as candidate"

# Config (36500 days): the old file is younger than the threshold
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$CACHE_CONFIG" BREW_USAGE_CACHE_ANALYSIS_DIR="$TEST_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-cache.sh"
    cache_analyze || exit 1
    printf "%s|%s\n" "$CACHE_CLEANUP_BYTES" "$CACHE_CLEANUP_COUNT"
' 2>/dev/null)
assert_equals "0|0" "$UNIT_OUT" "config CACHE_CLEANUP_DAYS changes cleanup candidates"

# =============================================================================
# CLI integration tests (require brew; skipped otherwise)
# =============================================================================
if ! command -v brew >/dev/null 2>&1; then
    echo ""
    echo "brew not found - skipping CLI integration tests"
else
    echo ""
    echo "Testing CLI integration..."

    TOP_CONFIG=$(mktemp "${TMPDIR:-/tmp}/brew-usage-config-top.XXXXXX")
    printf 'TOP_N=3\n' > "$TOP_CONFIG"

    # Config TOP_N=3: default report shows 3 formulae (3 + 7 decoration lines,
    # same counting convention as test-all.sh)
    formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$formula_count" -ge 3 ]]; then
        out_lines=$(BREW_USAGE_CONFIG_FILE="$TOP_CONFIG" "$BREW_USAGE" --formulae --no-color 2>/dev/null | grep -c .)
        assert_equals "10" "$out_lines" "config TOP_N=3 limits default report to 3 per section"
    else
        echo "(skipping TOP_N line-count check: fewer than 3 formulae installed)"
    fi

    # CLI --top beats config TOP_N
    out_lines=$(BREW_USAGE_CONFIG_FILE="$TOP_CONFIG" "$BREW_USAGE" --formulae --top 1 --no-color 2>/dev/null | grep -c .)
    assert_equals "8" "$out_lines" "CLI --top 1 beats config TOP_N=3"

    # Malformed config: warning on stderr, stdout report still works, exit 0
    output=$(BREW_USAGE_CONFIG_FILE="$MALFORMED_CONFIG" "$BREW_USAGE" --formulae --top 1 --no-color 2>"$TEST_CACHE_DIR/stderr.txt")
    status=$?
    assert_exit_code 0 "$status" "malformed config: exit code unaffected"
    assert_contains "$(cat "$TEST_CACHE_DIR/stderr.txt")" "malformed line" \
        "malformed config: warning on stderr"
    assert_contains "$output" "Formulae (Cellar)" "malformed config: report still rendered"

    # No config file: defaults, no warning
    err=$(BREW_USAGE_CONFIG_FILE="$NO_CONFIG" "$BREW_USAGE" --formulae --top 5 --no-color 2>&1 >/dev/null)
    assert_equals "" "$err" "no config file: no warnings on stderr"

    # --help documents the Config section
    help_out=$(BREW_USAGE_CONFIG_FILE="$NO_CONFIG" "$BREW_USAGE" --help 2>/dev/null)
    assert_contains "$help_out" "Config:" "--help shows Config section"
    assert_contains "$help_out" "TOP_N=N" "--help documents TOP_N key"
fi

# Cleanup
rm -f "$TEST_CONFIG" "$MALFORMED_CONFIG" "$DESTRUCTIVE_CONFIG" "$UNKNOWN_CONFIG" \
    "$COLOR_CONFIG" "$CACHE_CONFIG" "$TOP_CONFIG" 2>/dev/null || true
rm -rf "$TEST_CACHE_DIR" 2>/dev/null || true

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
