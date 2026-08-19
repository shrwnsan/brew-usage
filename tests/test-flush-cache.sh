#!/usr/bin/env bash
# Tests for brew-usage --flush-cache (manifest cache removal)

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

set -uo pipefail

# Test framework (same conventions as test-doctor.sh)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREW_USAGE="$SCRIPT_DIR/brew-usage"

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

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected exit code $expected, got $actual}"

    ((TESTS_RUN++))

    if [[ "$expected" -eq "$actual" ]]; then
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

echo "========================================"
echo "brew-usage --flush-cache Tests"
echo "========================================"
echo ""

# =============================================================================
# Unit tests: flush_manifest_cache (subshell export-before-source; the cache
# dir is readonly-once in config.sh, so it must be set in the environment
# BEFORE the module is sourced — same pattern as tests/test-doctor.sh)
# =============================================================================
echo "Testing flush_manifest_cache unit behavior..."

FLUSH_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-flush-cache.XXXXXX")
trap 'rm -rf "$FLUSH_CACHE_DIR"' EXIT

# Our cache files (naming: name--version--tag.json) + decoys that must survive
printf '{}' > "$FLUSH_CACHE_DIR/go--1.25.7--arm64_sonoma.json"
printf '{}' > "$FLUSH_CACHE_DIR/wget--1.0--x86_64_linux.json"
printf '{}' > "$FLUSH_CACHE_DIR/node@20--20.0--arm64_sonoma.json"
printf '{}' > "$FLUSH_CACHE_DIR/abcdef--go-1.25.bottle_manifest.json"  # Homebrew original
printf 'text' > "$FLUSH_CACHE_DIR/notes.txt"                            # non-JSON
printf '{}' > "$FLUSH_CACHE_DIR/no-double-dashes.json"                  # wrong shape

UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$FLUSH_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    out=$(flush_manifest_cache); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "3 cached manifests removed|exit=0" "$UNIT_OUT" \
    "flush removes exactly our *--*--*.json files, reports count"

for survivor in \
    "abcdef--go-1.25.bottle_manifest.json" \
    "notes.txt" \
    "no-double-dashes.json"; do
    if [[ -f "$FLUSH_CACHE_DIR/$survivor" ]]; then
        assert_equals "yes" "yes" "decoy '$survivor' untouched"
    else
        assert_equals "yes" "no" "decoy '$survivor' untouched"
    fi
done
remaining=0
for leftover in "$FLUSH_CACHE_DIR"/*--*--*.json; do
    [[ -f "$leftover" ]] && remaining=$((remaining + 1))
done
assert_equals "0" "$remaining" "no brew-usage cache files remain after flush"

# Empty cache dir: 0 removed, exit 0
EMPTY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-flush-empty.XXXXXX")
UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$EMPTY_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    out=$(flush_manifest_cache); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "0 cached manifests removed|exit=0" "$UNIT_OUT" \
    "empty cache dir: 0 removed, exit 0"

# Missing cache dir: 0 removed, exit 0 (unmatched glob filtered by -f check)
UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$EMPTY_DIR/does-not-exist" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    out=$(flush_manifest_cache); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "0 cached manifests removed|exit=0" "$UNIT_OUT" \
    "missing cache dir: 0 removed, exit 0"
rm -rf "$EMPTY_DIR"

echo ""

# =============================================================================
# CLI tests (fixture cache dir via exported BREW_BOTTLE_CACHE_DIR)
# =============================================================================
echo "Testing --flush-cache CLI behavior..."

CLI_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-flush-cli.XXXXXX")
printf '{}' > "$CLI_DIR/go--1.25.7--arm64_sonoma.json"
printf '{}' > "$CLI_DIR/abcdef--go-1.25.bottle_manifest.json"

output=$(BREW_BOTTLE_CACHE_DIR="$CLI_DIR" "$BREW_USAGE" --flush-cache 2>&1)
exit_code=$?
assert_exit_code 0 "$exit_code" "--flush-cache exits 0"
assert_contains "$output" "1 cached manifest" "--flush-cache prints removal count"

output=$(BREW_BOTTLE_CACHE_DIR="$CLI_DIR" "$BREW_USAGE" --flush-cache 2>&1)
exit_code=$?
assert_exit_code 0 "$exit_code" "second --flush-cache run exits 0"
assert_contains "$output" "0 cached manifests removed" "second --flush-cache run removes 0"

if [[ -f "$CLI_DIR/abcdef--go-1.25.bottle_manifest.json" ]]; then
    assert_equals "yes" "yes" "CLI flush leaves Homebrew's manifest originals alone"
else
    assert_equals "yes" "no" "CLI flush leaves Homebrew's manifest originals alone"
fi

# =============================================================================
# Mutual exclusivity (both orders, every mode flag)
# =============================================================================
echo "Testing --flush-cache conflicts..."

for pair in "--size go|--flush-cache" "--flush-cache|--size go" \
            "--doctor|--flush-cache" "--flush-cache|doctor" \
            "--cache|--flush-cache" "--flush-cache|--cache" \
            "--all|--flush-cache" "--flush-cache|--all" \
            "--top 5|--flush-cache" "--flush-cache|--top 5" \
            "--formulae|--flush-cache" "--flush-cache|--formulae" \
            "--casks|--flush-cache" "--flush-cache|--casks" \
            "--sort name|--flush-cache" "--flush-cache|--sort name"; do
    before="${pair%%|*}"
    after="${pair##*|}"
    # shellcheck disable=SC2086 # intentional word splitting of flag pairs
    output=$(BREW_BOTTLE_CACHE_DIR="$CLI_DIR" "$BREW_USAGE" $before $after 2>&1)
    exit_code=$?
    assert_exit_code 1 "$exit_code" "'$before $after' conflicts (exit 1)"
done

rm -rf "$CLI_DIR"

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
