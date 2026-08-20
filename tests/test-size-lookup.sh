#!/usr/bin/env bash
# Integration tests for brew-usage --size CLI flag

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

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

# =============================================================================
# --quiet flag: argument validation and conflicts
# =============================================================================
echo "Testing --quiet argument parsing..."

# --quiet without --size is invalid
output=$("$BREW_USAGE" --quiet download 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--quiet without --size should fail"

# --quiet requires a known field
output=$("$BREW_USAGE" --size go --quiet bogus 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--quiet with unknown field should fail"
assert_output_contains "$output" "Invalid --quiet field" "--quiet unknown field yields clear error"

# --quiet without a value is invalid
output=$("$BREW_USAGE" --size go --quiet 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--quiet without a field value should fail"

# --quiet is mutually exclusive with --json (both orders)
output=$("$BREW_USAGE" --size go --quiet download --json 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--size go --quiet download --json should fail"

output=$("$BREW_USAGE" --json --size go --quiet download 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "--json --size go --quiet download should fail"

echo ""

# =============================================================================
# Invalid package tests
# =============================================================================
echo "Testing invalid packages..."

output=$("$BREW_USAGE" --size nonexistent-package-xyz123 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "Non-existent package should exit 1"
assert_output_contains "$output" "not found" "Non-existent package error mentions not found"

# Regression guard for the version-specific --size fallback (PRD-005):
# plain unversioned lookups keep the not-found error path — a JSON run
# reports not_found, never a pinned-version fallback attempt
output=$("$BREW_USAGE" --size --json nonexistent-package-xyz123 2>/dev/null)
exit_code=$?
assert_exit_code 1 "$exit_code" "--json non-existent package still exits 1"
if echo "$output" | jq -e '.packages[0].status == "not_found"' >/dev/null 2>&1; then
    assert_exit_code 0 0 "--json non-existent package reports not_found entry"
else
    assert_exit_code 0 1 "--json non-existent package reports not_found entry (got: $output)"
fi

# =============================================================================
# Hostile package names (input validation hardening)
# =============================================================================
echo "Testing hostile package names..."

for hostile_name in "a b c" "../etc/passwd" "foo#bar" "x?y" "*" "homebrew/core/node"; do
    output=$("$BREW_USAGE" --size "$hostile_name" 2>&1)
    exit_code=$?
    assert_exit_code 1 "$exit_code" "hostile name '$hostile_name' exits 1"
    assert_output_contains "$output" "Invalid package name" "hostile name '$hostile_name' yields clear error"
done

# In JSON mode, stdout stays valid JSON with a not_found entry
output=$("$BREW_USAGE" --size --json "../etc/passwd" 2>/dev/null)
exit_code=$?
assert_exit_code 1 "$exit_code" "--json hostile name still exits 1"
if echo "$output" | jq -e '.packages[0].status == "not_found"' >/dev/null 2>&1; then
    assert_exit_code 0 0 "--json hostile name reports not_found entry"
else
    assert_exit_code 0 1 "--json hostile name reports not_found entry (got: $output)"
fi

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

    output=$("$BREW_USAGE" --size "$installed" "a b c" 2>&1)
    exit_code=$?
    assert_exit_code 2 "$exit_code" "Mixed run (good + hostile name) should exit 2 (partial success)"
    assert_output_contains "$output" "$installed" "Hostile-name mixed run still displays the good package's results"

    echo ""

    # =============================================================================
    # --quiet FIELD: value-only stdout for scripting
    # =============================================================================
    echo "Testing --quiet output..."

    # Single package: exactly one value line on stdout
    stdout=$("$BREW_USAGE" --size hello --quiet installed 2>/dev/null)
    exit_code=$?
    assert_exit_code 0 "$exit_code" "--size hello --quiet installed exits 0"
    line_count=$(printf '%s\n' "$stdout" | grep -c .)
    if [[ "$line_count" -eq 1 ]]; then
        assert_exit_code 0 0 "--quiet single package prints exactly one line"
    else
        assert_exit_code 0 "$line_count" "--quiet single package prints exactly one line"
    fi
    if [[ "$stdout" =~ ^[0-9]+(\.[0-9]+)?[[:space:]]?(KiB|MiB|GiB|B)$ ]]; then
        assert_exit_code 0 0 "--quiet value is a human-readable size (got: $stdout)"
    else
        assert_exit_code 0 1 "--quiet value is a human-readable size (got: $stdout)"
    fi

    # Both fields produce the same single-line shape
    stdout=$("$BREW_USAGE" --size hello --quiet download 2>/dev/null)
    exit_code=$?
    assert_exit_code 0 "$exit_code" "--size hello --quiet download exits 0"
    line_count=$(printf '%s\n' "$stdout" | grep -c .)
    if [[ "$line_count" -eq 1 ]]; then
        assert_exit_code 0 0 "--quiet download single package prints exactly one line"
    else
        assert_exit_code 0 "$line_count" "--quiet download single package prints exactly one line"
    fi

    # Multiple packages: one line each, in argument order (strongest check:
    # combined output must equal the per-package single lookups concatenated,
    # which pins both the values and their order)
    stdout=$("$BREW_USAGE" --size go hello --quiet download 2>/dev/null)
    exit_code=$?
    assert_exit_code 0 "$exit_code" "--size go hello --quiet download exits 0"
    line_count=$(printf '%s\n' "$stdout" | grep -c .)
    if [[ "$line_count" -eq 2 ]]; then
        assert_exit_code 0 0 "--quiet multiple packages print one line each"
    else
        assert_exit_code 0 "$line_count" "--quiet multiple packages print one line each"
    fi
    go_value=$("$BREW_USAGE" --size go --quiet download 2>/dev/null)
    hello_value=$("$BREW_USAGE" --size hello --quiet download 2>/dev/null)
    expected=$(printf '%s\n%s\n' "$go_value" "$hello_value")
    if [[ "$stdout" == "$expected" ]]; then
        assert_exit_code 0 0 "--quiet multiple packages print values in argument order"
    else
        assert_exit_code 0 1 "--quiet multiple packages print values in argument order (got: $stdout, want: $expected)"
    fi

    # Mixed run: good value on stdout only, failure story on stderr, exit 2
    stdout=$("$BREW_USAGE" --size hello nonexistent-package-xyz123 --quiet download 2>/dev/null)
    exit_code=$?
    assert_exit_code 2 "$exit_code" "--quiet mixed run exits 2 (partial success)"
    line_count=$(printf '%s\n' "$stdout" | grep -c .)
    if [[ "$line_count" -eq 1 ]]; then
        assert_exit_code 0 0 "--quiet mixed run prints only the good package's value"
    else
        assert_exit_code 0 "$line_count" "--quiet mixed run prints only the good package's value"
    fi
    stderr=$("$BREW_USAGE" --size hello nonexistent-package-xyz123 --quiet download 2>&1 >/dev/null)
    assert_output_contains "$stderr" "nonexistent-package-xyz123" \
        "--quiet mixed run keeps the failure story on stderr"

    # --quiet implies no color: no ANSI escapes on stdout
    stdout=$("$BREW_USAGE" --size hello --quiet installed 2>/dev/null)
    if [[ "$stdout" != *$'\033'* ]]; then
        assert_exit_code 0 0 "--quiet output contains no color escapes"
    else
        assert_exit_code 0 1 "--quiet output contains no color escapes"
    fi

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
