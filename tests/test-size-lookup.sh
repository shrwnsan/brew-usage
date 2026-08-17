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
        if [[ -n "${output:-}" ]]; then
            echo "  --- captured output ---"
            printf '  %s\n' "$output"
            echo "  -----------------------"
        fi
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
        echo "  --- captured output ---"
        printf '  %s\n' "$output"
        echo "  -----------------------"
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

# Mutual exclusivity is order-independent (flag AFTER --size)
output=$("$BREW_USAGE" --size go --top 10 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--size go --top 10 should fail (flag after --size)"

# --top passed explicitly with the default value still conflicts
output=$("$BREW_USAGE" --top 10 --size go 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--top 10 --size go should fail (explicit default value)"

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
    # PRD exit code semantics (partial success = 2)
    # =============================================================================
    echo "Testing exit code semantics..."

    output=$("$BREW_USAGE" --size "$installed" nonexistent-package-xyz123 2>&1)
    exit_code=$?
    assert_exit_code 2 "$exit_code" "Mixed run (good + bad package) should exit 2 (partial success)"
    assert_output_contains "$output" "$installed" "Mixed run still displays the good package's results"

    output=$("$BREW_USAGE" --size nonexistent-package-xyz123 "$installed" 2>&1)
    exit_code=$?
    assert_exit_code 2 "$exit_code" "Mixed run (bad + good package, reversed order) should exit 2"

    output=$("$BREW_USAGE" --size nonexistent-package-xyz123 nonexistent-other-xyz321 2>&1)
    exit_code=$?
    assert_exit_code 1 "$exit_code" "All-failed run should exit 1 (total failure)"

    echo ""

    # =============================================================================
    # ghcr.io download path: manifest not in Homebrew's cache nor ours
    # =============================================================================
    echo "Testing ghcr.io manifest download..."

    # Clear brew-usage's own cache copies for 'hello' plus Homebrew's cached
    # manifests (safe to delete - brew re-downloads on demand) so the test
    # actually exercises the ghcr.io download path.
    rm -f "${HOME}/Library/Caches/Homebrew/downloads/hello--"*.json 2>/dev/null
    rm -f "${HOME}/Library/Caches/Homebrew/downloads/"*--hello-*.bottle_manifest.json 2>/dev/null

    if ! code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
        "https://ghcr.io/token?scope=repository:homebrew/core/hello:pull" 2>/dev/null) \
        || [[ "$code" != "200" ]]; then
        echo "(skipping ghcr download test: no network)"
    else
    output=$("$BREW_USAGE" --size hello 2>&1)
    exit_code=$?
    assert_exit_code 0 "$exit_code" "--size hello succeeds via ghcr.io download"
    assert_output_contains "$output" "Download:" "--size hello shows download size"
    fi
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
