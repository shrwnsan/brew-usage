#!/usr/bin/env bash
# Tests for brew-usage JSON output (--json flag, report and size modes)

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

set -uo pipefail

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Assert functions
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
    local message="${3:-Expected '$haystack' to contain '$needle'}"

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

assert_success() {
    local exit_code="$1"
    local message="${2:-Command should succeed (exit code 0)}"

    ((TESTS_RUN++))

    if [[ "$exit_code" -eq 0 ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message (got exit code $exit_code)"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected '$haystack' to not contain '$needle'}"

    ((TESTS_RUN++))

    if [[ "$haystack" != *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message"
        return 1
    fi
}

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$TEST_DIR")/lib"
BREW_USAGE="$(dirname "$TEST_DIR")/brew-usage"

# Source libraries (unit-test portion)
source "$LIB_DIR/brew-usage-config.sh"
source "$LIB_DIR/brew-usage-utils.sh"
source "$LIB_DIR/brew-usage-calculate.sh"
source "$LIB_DIR/brew-usage-json.sh"

echo "========================================"
echo "brew-usage JSON Output Tests"
echo "========================================"
echo ""

# =============================================================================
# Unit tests for lib/brew-usage-json.sh
# =============================================================================
echo "Testing json module functions..."

# json_packages_array: builds objects from name|bytes|human lines
result=$(printf 'go|100|100B\nnode|200|200B\n' | json_packages_array | jq -c '.[0]')
assert_contains "$result" '"name":"go"' "json_packages_array builds package objects"
assert_contains "$result" '"size":100' "json_packages_array includes numeric size"
assert_contains "$result" '"size_human":"100B"' "json_packages_array includes human size"

# Empty input yields empty array
result=$(printf '' | json_packages_array)
assert_equals "[]" "$result" "json_packages_array with no input is empty array"

# Package names with JSON-special characters are safely escaped via jq --arg
result=$(printf 'weird"pkg\\name|10|10B\n' | json_packages_array | jq -r '.[0].name')
assert_equals 'weird"pkg\name' "$result" "json_packages_array escapes special characters safely"

# json_section_block: totals included
result=$(printf 'go|100|100B\n' | json_section_block 100 | jq -c '.')
assert_contains "$result" '"total_bytes":100' "json_section_block includes total_bytes"
assert_contains "$result" '"total_human":"100B"' "json_section_block includes total_human"
assert_contains "$result" '"packages":' "json_section_block includes packages"

# json_render_report: omitted sections (null) are absent
result=$(json_render_report "null" "null" "null" 42 | jq -c 'keys')
assert_equals '["grand_total_bytes","grand_total_human"]' "$result" "json_render_report omits null sections"

# json_render_report: present sections included
result=$(json_render_report "$(printf '{}' | json_section_block 0)" "null" "null" 7 | jq -c 'keys')
assert_contains "$result" '"formulae"' "json_render_report includes formulae when provided"
assert_not_contains "$result" '"casks"' "json_render_report omits casks when null"

# json_render_report: cache block included when provided
result=$(json_render_report "null" "null" "$(json_cache_block 100 40 5)" 100 | jq -c '.cache')
assert_contains "$result" '"total_bytes":100' "json_render_report includes cache block when provided"
assert_contains "$result" '"file_count":5' "json_cache_block includes file_count"

# json_size_entry_failed: null size fields with status
result=$(json_size_entry_failed "ghost-pkg" "not_found" | jq -c '.')
assert_equals '{"name":"ghost-pkg","version":null,"download_size":null,"installed_size":null,"platform":null,"status":"not_found"}' "$result" "json_size_entry_failed builds not_found entry"

echo ""

# =============================================================================
# CLI integration tests (require brew; skipped otherwise)
# =============================================================================
if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found - skipping CLI integration tests"
else
    echo "Testing CLI --json integration..."

    # Report mode: valid JSON with formulae/casks and numeric totals
    output=$("$BREW_USAGE" --json 2>/dev/null | jq -e '
        (.formulae.total_bytes | type == "number")
        and (.casks.total_bytes | type == "number")
        and (.grand_total_bytes | type == "number")
        and (.formulae.packages | type == "array")
        and (.casks.packages | type == "array")' 2>&1)
    assert_equals "true" "$output" "--json produces valid report JSON with numeric totals"

    # --top 3 limits both package arrays
    output=$("$BREW_USAGE" --json --top 3 2>/dev/null | jq -e '
        (.formulae.packages | length <= 3)
        and (.casks.packages | length <= 3)' 2>&1)
    assert_equals "true" "$output" "--json --top 3 limits packages arrays to 3"

    # --formulae --json omits casks
    output=$("$BREW_USAGE" --formulae --json 2>/dev/null | jq -e 'has("casks") | not' 2>&1)
    assert_equals "true" "$output" "--formulae --json omits casks key"

    # --casks --json omits formulae
    output=$("$BREW_USAGE" --casks --json 2>/dev/null | jq -e 'has("formulae") | not' 2>&1)
    assert_equals "true" "$output" "--casks --json omits formulae key"

    # No ANSI escapes in JSON stream (validate first so empty output fails)
    json_out=$("$BREW_USAGE" --json 2>/dev/null)
    assert_equals "true" "$(printf '%s' "$json_out" | jq -e 'type == "object"' 2>&1)" "--json output is a valid JSON object"
    output=$(printf '%s' "$json_out" | grep -c $'\033' || true)
    assert_equals "0" "$output" "--json output contains no ANSI escapes"

    # Size mode: single known package resolves with status ok
    output=$("$BREW_USAGE" --size --json jq 2>/dev/null | jq -e '
        (.packages | length == 1)
        and (.packages[0].status == "ok")
        and (.packages[0].installed_size | type == "number")' 2>&1)
    assert_equals "true" "$output" "--size --json jq yields ok entry"

    # Size mode partial failure: valid JSON on stdout, both statuses, exit 2
    "$BREW_USAGE" --size --json jq nonexistent-x >/tmp/brew-usage-test-json.out 2>/dev/null
    exit_code=$?
    assert_equals 2 "$exit_code" "--size --json with unknown package exits 2"
    output=$(jq -e '
        (.packages | length == 2)
        and (.packages[] | select(.name == "jq") | .status == "ok")
        and (.packages[] | select(.name == "nonexistent-x") | .status == "not_found")' \
        /tmp/brew-usage-test-json.out 2>&1)
    assert_equals "true" "$output" "partial failure JSON is valid and has correct statuses"
    rm -f /tmp/brew-usage-test-json.out
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
