#!/usr/bin/env bash
# Tests for brew-usage cache analysis (-C/--cache)

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

set -uo pipefail

# Test framework (same conventions as test-json-output.sh)
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

echo "========================================"
echo "Cache Analysis Tests (-C/--cache)"
echo "========================================"
echo ""

# =============================================================================
# Unit tests: cache_analyze() against a temp dir with known contents
# =============================================================================
echo "Testing cache_analyze() with a controlled cache directory..."

TEST_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-cache-test.XXXXXX")
trap 'rm -rf "$TEST_CACHE_DIR"' EXIT
mkdir -p "$TEST_CACHE_DIR/downloads"

# Old files (cleanup candidates): mtime 2020-01-01 via portable touch -t
printf '%.0sX' {1..100} > "$TEST_CACHE_DIR/downloads/old-bottle.tar.gz"
printf '%.0sX' {1..50} > "$TEST_CACHE_DIR/old-cask.dmg"
touch -t 202001010000 "$TEST_CACHE_DIR/downloads/old-bottle.tar.gz"
touch -t 202001010000 "$TEST_CACHE_DIR/old-cask.dmg"

# Fresh files (not cleanup candidates)
printf '%.0sX' {1..10} > "$TEST_CACHE_DIR/downloads/new-bottle.tar.gz"
touch "$TEST_CACHE_DIR/downloads/new-bottle.tar.gz"

# Run the analyzer in a fresh shell with the override in place
CACHE_ANALYSIS_OUTPUT=$(BREW_USAGE_CACHE_ANALYSIS_DIR="$TEST_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-cache.sh"
    cache_analyze || exit 1
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
        "$CACHE_ANALYSIS_DIR" "$CACHE_TOTAL_BYTES" "$CACHE_FILE_COUNT" \
        "$CACHE_DOWNLOADS_BYTES" "$CACHE_OTHER_BYTES" \
        "$CACHE_CLEANUP_BYTES" "$CACHE_CLEANUP_COUNT"
')
assert_equals 0 "$?" "cache_analyze succeeds on temp cache dir"
assert_equals "$TEST_CACHE_DIR|160|3|110|50|150|2" "$CACHE_ANALYSIS_OUTPUT" \
    "cache_analyze computes totals, breakdown, and cleanup candidates"

# =============================================================================
# CLI tests
# =============================================================================
echo ""
echo "Testing CLI -C/--cache integration..."

# Standalone mode: only the cache section renders (no Formulae/Casks headers)
output=$("$BREW_USAGE" --cache --no-color 2>/dev/null)
assert_contains "$output" "Total cache size" "--cache renders cache section"
assert_contains "$output" "Cleanup candidates" "--cache shows cleanup candidates line"
if [[ "$output" == *"Formulae (Cellar)"* ]]; then
    assert_equals "yes" "no" "--cache standalone omits formulae section"
else
    assert_equals "yes" "yes" "--cache standalone omits formulae section"
fi
if [[ "$output" == *"Casks (Caskroom)"* ]]; then
    assert_equals "yes" "no" "--cache standalone omits casks section"
else
    assert_equals "yes" "yes" "--cache standalone omits casks section"
fi

# Short flag matches long flag
output=$("$BREW_USAGE" -C --no-color 2>/dev/null)
assert_contains "$output" "Total cache size" "-C short flag works"

# Cache section composes with report mode as a third section
output=$("$BREW_USAGE" --formulae --cache --no-color 2>/dev/null)
assert_contains "$output" "Formulae (Cellar)" "--formulae --cache shows formulae section"
assert_contains "$output" "Total cache size" "--formulae --cache shows cache section"

# --json: expected keys, valid document
json_out=$("$BREW_USAGE" --cache --json 2>/dev/null)
output=$(printf '%s' "$json_out" | jq -e '
    (has("formulae") | not)
    and (.cache.total_bytes | type == "number")
    and (.cache.file_count | type == "number")
    and (.cache.cleanup_candidates_bytes | type == "number")
    and (.cache.total_human | type == "string")
    and (.cache.cleanup_candidates_human | type == "string")
    and (.grand_total_bytes | type == "number")' 2>&1)
assert_equals "true" "$output" "--cache --json has expected cache keys"

# Grand total includes cache when cache section is shown (PRD-001 JSON schema;
# human output kept consistent)
output=$(printf '%s' "$json_out" | jq -e '
    .grand_total_bytes == .cache.total_bytes' 2>&1)
assert_equals "true" "$output" "--cache --json grand total includes cache bytes"

# Default --json has no cache block (cache only appears with -C)
output=$("$BREW_USAGE" --json 2>/dev/null | jq -e 'has("cache") | not' 2>&1)
assert_equals "true" "$output" "--json without -C omits cache key"

# Composed report JSON: grand total = formulae + cache
output=$("$BREW_USAGE" --formulae --cache --json 2>/dev/null | jq -e '
    .grand_total_bytes == (.formulae.total_bytes + .cache.total_bytes)' 2>&1)
assert_equals "true" "$output" "composed --cache --json grand total = formulae + cache"

# Controlled end-to-end: BREW_USAGE_CACHE_ANALYSIS_DIR override drives the CLI numbers
json_out=$(BREW_USAGE_CACHE_ANALYSIS_DIR="$TEST_CACHE_DIR" "$BREW_USAGE" --cache --json 2>/dev/null)
output=$(printf '%s' "$json_out" | jq -e '
    .cache.total_bytes == 160
    and .cache.file_count == 3
    and .cache.cleanup_candidates_bytes == 150' 2>&1)
assert_equals "true" "$output" "BREW_USAGE_CACHE_ANALYSIS_DIR override drives CLI cache numbers"

# Mutual exclusivity with --size: exit 1 in both orders
"$BREW_USAGE" -C --size go >/dev/null 2>&1
assert_exit_code 1 "$?" "-C --size go exits 1"
"$BREW_USAGE" --size go -C >/dev/null 2>&1
assert_exit_code 1 "$?" "--size go -C exits 1"

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
