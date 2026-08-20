#!/usr/bin/env bash
# Tests for --size --compare (PRD-007): installed vs latest bottle size
# per package. get_versioned_size() + get_package_comparison() unit
# checks and CLI wiring, all offline (mocked brew/curl, seeded cache).

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

# isolate the manifest cache (read at config source time) so unit tests
# can pre-seed cache files and never touch Homebrew's real downloads cache
BREW_BOTTLE_CACHE_DIR="$(mktemp -d)"
export BREW_BOTTLE_CACHE_DIR

set -uo pipefail

# Test framework (same conventions as tests/test-size-version.sh)
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

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$TEST_DIR")/lib"
BREW_USAGE="$(dirname "$TEST_DIR")/brew-usage"

source "$LIB_DIR/brew-usage-config.sh"
source "$LIB_DIR/brew-usage-utils.sh"
source "$LIB_DIR/brew-usage-size.sh"

echo "========================================"
echo "brew-usage Size Compare Tests"
echo "========================================"
echo ""

# =============================================================================
# Offline mocks:
#   brew ruby  -> stable bottle tag
#   brew list --versions NAME -> "NAME <version>..." or nothing (not installed)
#   brew info --json=v2 NAME -> formula document (or fail = not found)
#   curl -> token endpoint answers, manifest fetches fail like a 404
# =============================================================================
MOCK_BIN="$(mktemp -d)"
LIST_STATE_DIR="$(mktemp -d)"   # presence of $LIST_STATE_DIR/<name> = installed
export LIST_STATE_DIR           # read inside the mock brew at runtime
cat >"${MOCK_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ruby" ]]; then
    echo "arm64_sonoma"
    exit 0
fi
if [[ "$1" == "list" && "$2" == "--versions" ]]; then
    name="$3"
    if [[ -f "$LIST_STATE_DIR/$name" ]]; then
        echo "$name $(cat "$LIST_STATE_DIR/$name")"
        exit 0
    fi
    exit 1
fi
if [[ "$1" == "info" ]]; then
    case "$3" in
        go)
            printf '%s' '{"formulae":[{"name":"go","versions":{"stable":"1.26.6"},"revision":0}]}'
            exit 0 ;;
        shrink)
            printf '%s' '{"formulae":[{"name":"shrink","versions":{"stable":"2.0"},"revision":1}]}'
            exit 0 ;;
        samver)
            printf '%s' '{"formulae":[{"name":"samver","versions":{"stable":"3.1.4"},"revision":0}]}'
            exit 0 ;;
        newpkg)
            printf '%s' '{"formulae":[{"name":"newpkg","versions":{"stable":"5.0"},"revision":0}]}'
            exit 0 ;;
        oldpkg)
            printf '%s' '{"formulae":[{"name":"oldpkg","versions":{"stable":"1.2"},"revision":0}]}'
            exit 0 ;;
    esac
    exit 1
fi
exit 1
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
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

# Seed helper: one brew-usage-owned manifest with given installed_size
seed_manifest() {
    local name="$1" version="$2" installed_size="$3"
    cat >"${BREW_BOTTLE_CACHE_DIR}/${name}--${version}--arm64_sonoma.json" <<EOF
{"manifests":[
  {"annotations":{
    "org.opencontainers.image.ref.name":"${version}.arm64_sonoma",
    "sh.brew.bottle.size":"1000000",
    "sh.brew.bottle.installed_size":"${installed_size}"}}
]}
EOF
}

mark_installed() {  # name version -> brew list --versions answer
    printf '%s' "$2" > "$LIST_STATE_DIR/$1"
}

# =============================================================================
# get_versioned_size unit behavior
# =============================================================================
echo "Testing get_versioned_size (unit, seeded cache)..."

seed_manifest "go" "1.25.5" "115000000"
result=$(get_versioned_size "go" "1.25.5")
exit_code=$?
assert_exit_code 0 "$exit_code" "seeded cache resolves without network"
assert_equals "1.25.5" "$(printf '%s' "$result" | jq -r '.version')" \
    "version passes through verbatim"
assert_equals "115000000" "$(printf '%s' "$result" | jq -r '.installed_size')" \
    "installed_size comes from the seeded manifest"
assert_equals "go" "$(printf '%s' "$result" | jq -r '.name')" \
    "result names the bare package"

result=$(get_versioned_size "go" "9.9.9" 2>/dev/null)
exit_code=$?
assert_exit_code 2 "$exit_code" "no manifest anywhere: exit 2, no error text"

result=$(get_versioned_size "go" "../etc" 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "invalid version rejected before cache/URL"
assert_contains "$result" "Invalid version string" "invalid version names the gate"

result=$(get_versioned_size "ba d" "1.0" 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "invalid name rejected"
assert_contains "$result" "Invalid package name" "invalid name names the gate"

echo ""

# =============================================================================
# get_package_comparison unit behavior
# =============================================================================
echo "Testing get_package_comparison (unit, mocked brew + seeded cache)..."

# ok: both sides resolved, delta arithmetic exact
mark_installed "go" "1.25.5"
seed_manifest "go" "1.26.6" "119000000"
result=$(get_package_comparison "go")
exit_code=$?
assert_exit_code 0 "$exit_code" "both sides seeded: comparison resolves"
assert_equals "ok" "$(printf '%s' "$result" | jq -r '.status')" "status ok"
assert_equals "1.25.5" "$(printf '%s' "$result" | jq -r '.installed_version')" \
    "installed version from brew list --versions"
assert_equals "1.26.6" "$(printf '%s' "$result" | jq -r '.latest_version')" \
    "latest version from brew info"
assert_equals "4000000" "$(printf '%s' "$result" | jq -r '.size_delta')" \
    "delta = latest installed_size - installed installed_size"
assert_equals "119000000" "$(printf '%s' "$result" | jq -r '.latest_size')" \
    "latest_size carried through"

# shrink: negative delta + revision append on the latest version
mark_installed "shrink" "1.9"
seed_manifest "shrink" "1.9" "9000000"
seed_manifest "shrink" "2.0_1" "7000000"
result=$(get_package_comparison "shrink")
assert_equals "2.0_1" "$(printf '%s' "$result" | jq -r '.latest_version')" \
    "revision appended to the latest version"
assert_equals "-2000000" "$(printf '%s' "$result" | jq -r '.size_delta')" \
    "shrinking upgrade reports a negative delta"
assert_equals "ok" "$(printf '%s' "$result" | jq -r '.status')" "shrink case status ok"

# up_to_date: equal versions, delta 0, sizes still attempted
mark_installed "samver" "3.1.4"
seed_manifest "samver" "3.1.4" "5000000"
result=$(get_package_comparison "samver")
assert_equals "up_to_date" "$(printf '%s' "$result" | jq -r '.status')" \
    "equal versions: status up_to_date"
assert_equals "0" "$(printf '%s' "$result" | jq -r '.size_delta')" \
    "equal versions: delta 0"

# not_installed: brew list empty, latest side still resolved
seed_manifest "newpkg" "5.0" "1000000"
result=$(get_package_comparison "newpkg")
assert_equals "not_installed" "$(printf '%s' "$result" | jq -r '.status')" \
    "missing brew list entry: status not_installed"
assert_equals "null" "$(printf '%s' "$result" | jq -r '.installed_version')" \
    "not_installed: installed_version null"
assert_equals "1000000" "$(printf '%s' "$result" | jq -r '.latest_size')" \
    "not_installed: latest side still resolved"

# partial: installed side's manifest unavailable (only latest seeded)
mark_installed "oldpkg" "0.9"
seed_manifest "oldpkg" "1.2" "1400000"
result=$(get_package_comparison "oldpkg")
assert_equals "partial" "$(printf '%s' "$result" | jq -r '.status')" \
    "unavailable installed manifest: status partial"
assert_equals "null" "$(printf '%s' "$result" | jq -r '.installed_size')" \
    "partial: installed_size null"
assert_equals "null" "$(printf '%s' "$result" | jq -r '.size_delta')" \
    "partial: delta null"
assert_equals "1.2" "$(printf '%s' "$result" | jq -r '.latest_version')" \
    "partial: latest side still reported"

# not found: brew info fails and nothing installed
result=$(get_package_comparison "ghost-pkg-xyz" 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "unknown package + not installed: exit 1"
assert_contains "$result" "not found" "unknown package: not-found error"

# invalid names keep the hard gate
result=$(get_package_comparison "ba d" 2>&1)
exit_code=$?
assert_exit_code 1 "$exit_code" "invalid name: exit 1"
assert_contains "$result" "Invalid package name" "invalid name: gate message"

echo ""

# =============================================================================
# CLI behavior (offline mocks still active)
# =============================================================================
echo "Testing CLI paths (mocked brew/curl)..."

output=$("$BREW_USAGE" --compare 2>&1 >/dev/null); exit_code=$?
assert_exit_code 1 "$exit_code" "--compare without --size exits 1"
assert_contains "$output" "--compare is only valid in --size mode" \
    "--compare without --size explains the requirement"

output=$("$BREW_USAGE" --size go --compare --quiet installed 2>&1 >/dev/null); exit_code=$?
assert_exit_code 1 "$exit_code" "--compare with --quiet exits 1"
assert_contains "$output" "--compare is mutually exclusive with --quiet" \
    "--compare/--quiet exclusivity explained"

output=$("$BREW_USAGE" --size go --compare 2>/dev/null); exit_code=$?
assert_exit_code 0 "$exit_code" "resolved compare run exits 0"
assert_contains "$output" "Package Size Comparison" "human table header"
assert_contains "$output" "1.25.5" "table shows the installed version"
assert_contains "$output" "1.26.6" "table shows the latest version"
if [[ "$output" == *"+"* ]]; then
    assert_equals "yes" "yes" "growing delta rendered with a plus sign"
else
    assert_equals "+delta" "missing" "growing delta rendered with a plus sign"
fi

output=$("$BREW_USAGE" --size go ghost-pkg-xyz --compare 2>/dev/null); exit_code=$?
assert_exit_code 2 "$exit_code" "mixed found/not-found compare exits 2"
assert_contains "$output" "go" "mixed run still renders the resolved entry"

output=$("$BREW_USAGE" --size ghost-pkg-xyz --compare 2>/dev/null); exit_code=$?
assert_exit_code 1 "$exit_code" "all-failed compare exits 1"

# --json composition: same envelope, compare entry schema
output=$("$BREW_USAGE" --size go --compare --json 2>/dev/null); exit_code=$?
assert_exit_code 0 "$exit_code" "--compare --json exits 0"
assert_equals "ok" "$(printf '%s' "$output" | jq -r '.packages[0].status')" \
    "--json entry carries the ok status"
assert_equals "4000000" "$(printf '%s' "$output" | jq -r '.packages[0].size_delta')" \
    "--json entry carries the delta"

output=$("$BREW_USAGE" --size ghost-pkg-xyz --compare --json 2>/dev/null); exit_code=$?
assert_exit_code 1 "$exit_code" "--json all-failed compare exits 1"
assert_equals "not_found" "$(printf '%s' "$output" | jq -r '.packages[0].status')" \
    "--json failed entry uses the not_found status"
assert_equals "null" "$(printf '%s' "$output" | jq -r '.packages[0].size_delta')" \
    "--json failed entry has null delta"

# not_installed entries surface through the CLI too
output=$("$BREW_USAGE" --size newpkg --compare 2>/dev/null)
assert_contains "$output" "not installed" "table names the not-installed case"

# display_help documents --compare
output=$("$BREW_USAGE" --help 2>/dev/null)
assert_contains "$output" "--compare" "display_help documents --compare"

# Restore the real PATH
PATH="$OLD_PATH"

rm -rf "$MOCK_BIN" "$LIST_STATE_DIR"

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
