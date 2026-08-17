#!/usr/bin/env bash
# Integration tests for brew-usage --size CLI flag

set -uo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREW_USAGE="$(dirname "$SCRIPT_DIR")/brew-usage"

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$expected" -eq "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message (expected exit $expected, got $actual)"
    fi
}

assert_output_contains() {
    local output="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$output" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message (output did not contain '$needle')"
    fi
}

assert_output_not_empty() {
    local output="$1"
    local message="$2"

    ((TESTS_RUN++))

    if [[ -n "$output" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message (output was empty)"
    fi
}

echo "========================================"
echo "brew-usage --size Integration Tests"
echo "========================================"
echo ""

# =============================================================================
# Argument parsing tests
# =============================================================================
echo "Testing argument parsing..."

# --size with no packages should show usage and exit 0
output=$("$BREW_USAGE" --size 2>&1)
exit_code=$?
assert_exit_code 0 "$exit_code" "--size with no packages exits 0 (usage)"
assert_output_contains "$output" "Usage:" "--size with no packages shows usage text"

# --size is mutually exclusive with --formulae
output=$("$BREW_USAGE" --formulae --size go 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--formulae --size should fail (mutually exclusive)"

# --size is mutually exclusive with --casks
output=$("$BREW_USAGE" --casks --size go 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--casks --size should fail (mutually exclusive)"

echo ""

# =============================================================================
# Invalid package tests
# =============================================================================
echo "Testing invalid packages..."

output=$("$BREW_USAGE" --size nonexistent-package-xyz123 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "Non-existent package should exit 1"

echo ""

# =============================================================================
# Valid package tests (requires brew and jq)
# =============================================================================
if command -v brew >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    echo "Testing with real packages..."

    # Pick a commonly installed formula
    installed=$(brew list --formula -1 2>/dev/null | head -1)
    if [[ -n "$installed" ]]; then
        output=$("$BREW_USAGE" --size "$installed" 2>&1)
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            assert_exit_code 0 "$exit_code" "--size $installed succeeds"
            assert_output_not_empty "$output" "--size $installed produces output"
        else
            assert_exit_code 2 "$exit_code" "--size $installed exits 2 (no bottle, expected for some packages)"
        fi
    else
        echo "(skipping: no formulae installed)"
    fi

    echo ""

    # =============================================================================
    # Exit code latching: error should not be downgraded by warning
    # =============================================================================
    echo "Testing exit code priority..."

    output=$("$BREW_USAGE" --size nonexistent-package-xyz123 "$installed" 2>&1)
    exit_code=$?
    assert_exit_code 1 "$exit_code" "Error exit code (1) should not be downgraded when mixed with valid packages"

    echo ""

    # =============================================================================
    # ghcr.io download path: manifest not in Homebrew's cache nor ours
    # =============================================================================
    echo "Testing ghcr.io manifest download..."

    # Clear only brew-usage's own cache copies for 'hello'
    # (never touch Homebrew's '*--*bottle_manifest.json' originals)
    rm -f "${HOME}/Library/Caches/Homebrew/downloads/hello--"*.json 2>/dev/null

    output=$("$BREW_USAGE" --size hello 2>&1)
    exit_code=$?
    assert_exit_code 0 "$exit_code" "--size hello succeeds via ghcr.io download"
    assert_output_contains "$output" "Download:" "--size hello shows download size"
else
    echo "(skipping real-package tests: brew or jq not available)"
fi

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
