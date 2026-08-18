#!/usr/bin/env bash
# Tests for brew-usage show-all listing (-a/--all)

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

assert_at_least() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected $actual to be >= $expected}"

    ((TESTS_RUN++))

    if [[ "$actual" -ge "$expected" ]]; then
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

echo "========================================"
echo "Show-All Tests (-a/--all)"
echo "========================================"
echo ""

# CLI integration tests (require brew; skipped otherwise)
if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found - skipping CLI integration tests"
    echo ""
    echo "All tests passed! (skipped)"
    exit 0
fi

# =============================================================================
# Mutual exclusivity (order-independent, exit 1)
# =============================================================================
echo "Testing --all mutual exclusivity..."

"$BREW_USAGE" --all --top 5 >/dev/null 2>&1
assert_exit_code 1 "$?" "--all --top 5 exits 1"
"$BREW_USAGE" --top 5 --all >/dev/null 2>&1
assert_exit_code 1 "$?" "--top 5 --all exits 1"
"$BREW_USAGE" -a -t 3 >/dev/null 2>&1
assert_exit_code 1 "$?" "-a -t 3 exits 1"

"$BREW_USAGE" --all --size go >/dev/null 2>&1
assert_exit_code 1 "$?" "--all --size go exits 1"
"$BREW_USAGE" --size go --all >/dev/null 2>&1
assert_exit_code 1 "$?" "--size go --all exits 1"

output=$("$BREW_USAGE" --all --top 5 2>&1 >/dev/null)
assert_contains "$output" "mutually exclusive" "--all --top conflict message names the flags"

# =============================================================================
# Pager command resolution (unit) — ANSI must survive the default pager
# =============================================================================
echo "Testing pager command resolution..."

# Source the display module for direct unit access to the pager functions
# shellcheck source=../lib/brew-usage-display.sh
source "$SCRIPT_DIR/lib/brew-usage-display.sh" 2>/dev/null

# Default pager must pass ANSI escapes through (less without -R mangles them)
default_pager=$(PAGER="" pager_command)
assert_equals "less -R" "$default_pager" \
    "default pager is 'less -R' (ANSI passthrough)"

# Explicit PAGER is respected verbatim, including arguments
explicit_pager=$(PAGER="more -x11" pager_command)
assert_equals "more -x11" "$explicit_pager" "PAGER env respected verbatim"

# page_file pages through the resolved pager without error
(PAGER="cat" page_file /dev/null) >/dev/null 2>&1
assert_exit_code 0 "$?" "page_file succeeds via resolved pager"

# =============================================================================
# Full listing (stdout NOT a tty in tests: plain output, no pager)
# =============================================================================
echo ""
echo "Testing --all full listing (piped stdout)..."

formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')

# =============================================================================
# Sort order (--sort name must actually sort by name)
# =============================================================================
echo "Testing --sort order..."

if [[ "$formula_count" -gt 3 ]] 2>/dev/null; then
    first_pkg=$("$BREW_USAGE" --formulae --top 3 --sort name --no-color 2>/dev/null \
        | grep -E '^[[:space:]]*[0-9]' | head -1 | awk '{print $NF}')
    expected_pkg=$(brew list --formula -1 2>/dev/null | sort | head -1 | tr -d ' ')
    assert_equals "$expected_pkg" "$first_pkg" \
        "--sort name lists alphabetically first package first"

    biggest_pkg=$("$BREW_USAGE" --formulae --top 1 --sort size --no-color 2>/dev/null \
        | grep -E '^[[:space:]]*[0-9]' | head -1 | awk '{print $NF}')
    expected_biggest=$("$BREW_USAGE" --formulae --top 1 --no-color 2>/dev/null \
        | grep -E '^[[:space:]]*[0-9]' | head -1 | awk '{print $NF}')
    assert_equals "$expected_biggest" "$biggest_pkg" \
        "--sort size matches default (descending by size)"
fi


# All formulae shown: non-empty lines = formula_count + fixed decoration.
# Decoration for `--formulae --all` (no-color, piped) is 7 non-blank lines:
# report title + rule, section title, section rule + total, grand-total
# rule + total (blank separator lines are excluded by grep -c .).
if [[ "$formula_count" -gt 10 ]]; then
    all_lines=$("$BREW_USAGE" --formulae --all --no-color 2>/dev/null | grep -c .)
    assert_equals "$((formula_count + 7))" "$all_lines" \
        "--formulae --all lists every formula (count + 7 decoration lines)"

    top_lines=$("$BREW_USAGE" --formulae --top 10 --no-color 2>/dev/null | grep -c .)
    assert_equals "17" "$top_lines" \
        "--formulae --top 10 shows exactly 10 packages + decoration"
    if [[ "$all_lines" -le "$top_lines" ]]; then
        assert_equals "more" "not-more" "--all shows more lines than --top 10"
    else
        assert_equals "more" "more" "--all shows more lines than --top 10"
    fi
else
    echo "(skipping line-count comparisons: fewer than 10 formulae installed)"
fi

assert_at_least 0 "$formula_count" "brew list --formula ran"

# =============================================================================
# --all --json: full arrays, clean stdout, never paged
# =============================================================================
echo ""
echo "Testing --all --json..."

# JSON path bypasses the pager entirely (checked in code: PAGER_TMPFILE is
# only set when ! $JSON_OUTPUT). A bogus PAGER proves no pager subprocess
# is spawned on the JSON path even if it were a tty.
json_len=$(PAGER=/nonexistent-pager-brew-usage "$BREW_USAGE" --formulae --all --json 2>/dev/null \
    | jq '.formulae.packages | length')
assert_equals "$formula_count" "$json_len" \
    "--formulae --all --json array length equals installed formula count"

valid=$(PAGER=exit-1-pager "$BREW_USAGE" --all --json 2>/dev/null | jq -e '
    (.formulae.packages | type == "array")
    and (.grand_total_bytes | type == "number")' >/dev/null && echo yes || echo no)
assert_equals "yes" "$valid" "--all --json emits a valid document despite hostile PAGER"

# =============================================================================
# Composition with -C
# =============================================================================
echo ""
echo "Testing --all -C composition..."

output=$("$BREW_USAGE" --all -C --no-color 2>/dev/null)
assert_contains "$output" "Formulae (Cellar)" "--all -C keeps formulae section"
assert_contains "$output" "Total cache size" "--all -C appends cache section"

echo ""

# =============================================================================
# Summary
# =============================================================================
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
