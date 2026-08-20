#!/usr/bin/env bash
# Tests for version-specific --size lookup (PRD-005 Feature 3)
# Covers the formula-first / explicit-version fallback in get_package_size():
# a pinned "name@version" argument whose brew-info lookup fails is split at
# the LAST '@' and the explicit suffix is used verbatim for the manifest.

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

# isolate the manifest cache (read at config source time) so unit tests can
# pre-seed cache files and never touch Homebrew's real downloads cache
BREW_BOTTLE_CACHE_DIR="$(mktemp -d)"
export BREW_BOTTLE_CACHE_DIR

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

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

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$TEST_DIR")/lib"
BREW_USAGE="$(dirname "$TEST_DIR")/brew-usage"

# Source libraries
source "$LIB_DIR/brew-usage-config.sh"
source "$LIB_DIR/brew-usage-utils.sh"
source "$LIB_DIR/brew-usage-size.sh"

echo "========================================"
echo "brew-usage Version-Specific Size Tests"
echo "========================================"
echo ""

# =============================================================================
# Offline mocks: brew (info always "not found", ruby serves a stable tag) and
# curl (token endpoint answers, manifest fetches fail like a 404)
# =============================================================================
MOCK_BIN="$(mktemp -d)"
cat >"${MOCK_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ruby" ]]; then
    echo "arm64_sonoma"
    exit 0
fi
# brew info and everything else: simulate "no such formula"
exit 1
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
# Offline curl stub: the anonymous-token endpoint answers; every other
# request (manifest fetches) fails like a 404
for arg in "$@"; do
    case "$arg" in
        https://ghcr.io/token*) printf '{"token":"stub-token"}\n'; exit 0 ;;
    esac
done
exit 1
EOF
chmod +x "${MOCK_BIN}/brew" "${MOCK_BIN}/curl"
OLD_PATH="$PATH"
PATH="${MOCK_BIN}:${PATH}"

# =============================================================================
# Invalid pinned versions keep the existing error paths (exit 1)
# =============================================================================
echo "Testing invalid pinned versions (unit, mocked brew)..."

# Empty version suffix fails is_valid_version -> not-found error, not fallback
result=$(get_package_size "foo@" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "get_package_size 'foo@' (empty version) exits 1"
assert_contains "$result" "not found" "'foo@' keeps the not-found error path"

# Empty name prefix fails is_valid_package_name -> not-found error
result=$(get_package_size "@1.2" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "get_package_size '@1.2' (empty name) exits 1"
assert_contains "$result" "not found" "'@1.2' keeps the not-found error path"

# Path traversal in the pin is rejected by the whole-name gate before brew
result=$(get_package_size "foo@../etc" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "get_package_size 'foo@../etc' exits 1"
assert_contains "$result" "Invalid package name" "'foo@../etc' rejected as invalid name"

# Whitespace in the pin is likewise rejected up front
result=$(get_package_size "foo@a b" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "get_package_size 'foo@a b' exits 1"
assert_contains "$result" "Invalid package name" "'foo@a b' rejected as invalid name"

# Unversioned names never enter the fallback: not-found stays an error
result=$(get_package_size "nonexistent-package-xyz123" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "unversioned not-found still exits 1 (no fallback)"
assert_contains "$result" "not found" "unversioned not-found message unchanged"

echo ""

# =============================================================================
# Valid split: explicit version used verbatim (unit, mocked brew + cache)
# =============================================================================
echo "Testing pinned-version fallback (unit, mocked brew)..."

# Cache filename contract: pinned lookups cache under the base name
result=$(get_manifest_filename "go" "1.21.13" "arm64_sonoma")
assert_equals "go--1.21.13--arm64_sonoma.json" "$result" "Pinned cache filename is name--version--tag"

# Seed the cache where the fallback must look: base name + explicit version
cat >"${BREW_BOTTLE_CACHE_DIR}/go--1.21.13--arm64_sonoma.json" <<'EOF'
{"manifests":[
  {"annotations":{
    "org.opencontainers.image.ref.name":"1.21.13.arm64_sonoma",
    "sh.brew.bottle.size":"12345678",
    "sh.brew.bottle.installed_size":"23456789"}}
]}
EOF

# brew info is mocked to fail, so resolving proves the fallback ran; the
# version must come out verbatim (no brew-info resolution, no revision append)
result=$(get_package_size "go@1.21.13" 2>&1)
exit_code=$?
assert_equals 0 "$exit_code" "get_package_size 'go@1.21.13' resolves via fallback"
assert_equals "1.21.13" "$(printf '%s' "$result" | jq -r '.version')" "explicit version used verbatim"
assert_equals "go@1.21.13" "$(printf '%s' "$result" | jq -r '.name')" "result names the pinned argument"
assert_equals "12345678" "$(printf '%s' "$result" | jq -r '.download_size')" "sizes come from the pinned manifest"

# A user-pinned revision suffix also stays verbatim
cat >"${BREW_BOTTLE_CACHE_DIR}/go--1.21.13_1--arm64_sonoma.json" <<'EOF'
{"manifests":[
  {"annotations":{
    "org.opencontainers.image.ref.name":"1.21.13_1.arm64_sonoma",
    "sh.brew.bottle.size":"12345678",
    "sh.brew.bottle.installed_size":"23456789"}}
]}
EOF
result=$(get_package_size "go@1.21.13_1" 2>&1)
exit_code=$?
assert_equals 0 "$exit_code" "get_package_size 'go@1.21.13_1' resolves via fallback"
assert_equals "1.21.13_1" "$(printf '%s' "$result" | jq -r '.version')" "pinned revision suffix stays verbatim"

# Plausible version with no manifest anywhere -> partial-failure path (exit 2)
result=$(get_package_size "go@9.9.9" 2>&1)
exit_code=$?
assert_equals 2 "$exit_code" "get_package_size 'go@9.9.9' exits 2 (no bottle available)"
assert_contains "$result" "No bottle manifest available for 'go@9.9.9'" "no-manifest warning names the pinned argument"

echo ""

# =============================================================================
# CLI behavior with the offline mocks (argument wiring and --quiet)
# =============================================================================
echo "Testing CLI paths (mocked brew/curl)..."

output=$("$BREW_USAGE" --size "foo@a b" 2>&1)
exit_code=$?
assert_equals 1 "$exit_code" "--size 'foo@a b' exits 1"
assert_contains "$output" "Invalid package name" "CLI rejects invalid pinned name"

output=$("$BREW_USAGE" --size go@9.9.9 2>&1)
exit_code=$?
assert_equals 0 "$exit_code" "--size go@9.9.9 alone: warning-only run exits 0"
assert_contains "$output" "go@9.9.9" "no-bottle output names the pinned package"

# --json composes unchanged: the pinned no-manifest package becomes a
# no_bottle entry in a valid JSON document on stdout
output=$("$BREW_USAGE" --size --json go@9.9.9 2>/dev/null)
exit_code=$?
assert_equals 0 "$exit_code" "--json with pinned nonexistent version exits 0"
if echo "$output" | jq -e '.packages[0].status == "no_bottle"' >/dev/null 2>&1; then
    assert_equals 0 0 "--json reports no_bottle for the pinned package"
else
    assert_equals 0 1 "--json reports no_bottle for the pinned package (got: $output)"
fi

# --quiet prints values only for resolved packages: a pinned version with no
# manifest contributes nothing to stdout (failure story stays on stderr)
stdout=$("$BREW_USAGE" --size go@9.9.9 --quiet download 2>/dev/null)
exit_code=$?
assert_equals 0 "$exit_code" "--quiet with pinned nonexistent version exits 0"
assert_equals "" "$stdout" "--quiet prints nothing on stdout for the pinned package"
stderr=$("$BREW_USAGE" --size go@9.9.9 --quiet download 2>&1 >/dev/null)
assert_contains "$stderr" "go@9.9.9" "--quiet keeps the pinned package's failure story on stderr"

# Restore the real PATH for the integration section below
PATH="$OLD_PATH"

echo ""

# =============================================================================
# Integration tests (real brew + network), guarded like test-size-lookup.sh
# =============================================================================
if command -v brew >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if ! code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
        "https://ghcr.io/token?scope=repository:homebrew/core/hello:pull" 2>/dev/null) \
        || [[ "$code" != "200" ]]; then
        echo "(skipping integration tests: no network)"
    else
        echo "Testing with real brew + network..."

        # Regression: an existing versioned formula keeps today's as-is path
        # (resolved = 0, or 2 when it has no bottle for this platform; a
        # not-found 1 would mean the brew-info path regressed)
        versioned_formula=""
        for candidate in go@1.25 go@1.24 go@1.23 go@1.22 node@22 node@20 python@3.13 python@3.12; do
            if brew info --json=v2 "$candidate" >/dev/null 2>&1; then
                versioned_formula="$candidate"
                break
            fi
        done
        if [[ -n "$versioned_formula" ]]; then
            output=$("$BREW_USAGE" --size "$versioned_formula" 2>&1)
            exit_code=$?
            if [[ $exit_code -eq 0 || $exit_code -eq 2 ]]; then
                assert_equals 0 0 "--size $versioned_formula (existing formula) still resolves via brew info"
            else
                assert_equals 0 1 "--size $versioned_formula (existing formula) still resolves via brew info (got exit $exit_code)"
            fi
        else
            echo "(skipping versioned-formula regression: no versioned formula found)"
        fi

        # Fallback happy path: pin go's currently hosted version — there is
        # no formula by that name, so only the fallback can resolve it
        current_version=$(brew info --json=v2 go 2>/dev/null | jq -r '
            .formulae[0] as $f
            | ($f.versions.stable // $f.version) as $v
            | (if ($f.revision // 0) != 0 then "\($v)_\($f.revision)" else $v end)')
        if [[ -n "$current_version" && "$current_version" != "null" ]]; then
            output=$("$BREW_USAGE" --size "go@${current_version}" 2>&1)
            exit_code=$?
            assert_equals 0 "$exit_code" "--size go@${current_version} resolves the exact pinned manifest"
            assert_contains "$output" "Download:" "pinned-version result shows sizes"
        else
            echo "(skipping pinned-current test: could not determine go's version)"
        fi

        # Plausible nonexistent pinned version: warning, and in a mixed run
        # with a hard failure the process exits 2 (partial success)
        output=$("$BREW_USAGE" --size go@9.9.9 nonexistent-package-xyz123 2>&1)
        exit_code=$?
        assert_equals 2 "$exit_code" "pinned nonexistent + hard failure exits 2 (partial success)"
        assert_contains "$output" "go@9.9.9" "partial run still reports the pinned package"

        # --quiet with the pinned nonexistent version: stdout carries no line
        # for it (values only for resolved packages)
        stdout=$("$BREW_USAGE" --size go@9.9.9 --quiet download 2>/dev/null)
        exit_code=$?
        assert_equals 0 "$exit_code" "--quiet pinned nonexistent version (real network) exits 0"
        assert_equals "" "$stdout" "--quiet stdout stays empty for the pinned package (real network)"
    fi
else
    echo "(skipping integration tests: brew or jq not available)"
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
