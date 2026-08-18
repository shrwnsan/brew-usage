#!/usr/bin/env bash
# Unit tests for brew-usage size lookup functionality

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

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

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local message="${3:-Expected '$actual' to match '$pattern'}"

    ((TESTS_RUN++))

    if [[ "$actual" =~ $pattern ]]; then
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

# Source libraries
source "$LIB_DIR/brew-usage-config.sh"
source "$LIB_DIR/brew-usage-utils.sh"
source "$LIB_DIR/brew-usage-size.sh"

echo "========================================"
echo "brew-usage Size Lookup Tests"
echo "========================================"
echo ""

# =============================================================================
# Tests for get_size_human_iec()
# =============================================================================
echo "Testing get_size_human_iec()..."

# Test bytes (no decimal)
result=$(get_size_human_iec 512)
assert_equals "512 B" "$result" "512 bytes should format as '512 B'"

# Test kilobyte boundary
result=$(get_size_human_iec 1024)
assert_contains "$result" "KiB" "1024 bytes should contain 'KiB'"

# Test megabytes
result=$(get_size_human_iec 57531075)
assert_contains "$result" "MiB" "57MB should contain 'MiB'"
assert_contains "$result" "54" "57MB should start with ~54"

result=$(get_size_human_iec 203292092)
assert_contains "$result" "MiB" "203MB should contain 'MiB'"
assert_contains "$result" "193" "203MB should start with ~193"

# Test gigabytes
result=$(get_size_human_iec 1073741824)
assert_contains "$result" "GiB" "1GB should contain 'GiB'"

result=$(get_size_human_iec 2147483648)
assert_contains "$result" "GiB" "2GB should contain 'GiB'"
assert_contains "$result" "2.0" "2GB should format as '2.0 GiB'"

echo ""

# =============================================================================
# Tests for get_bottle_tag()
# =============================================================================
echo "Testing get_bottle_tag()..."

# Test that function returns something
result=$(get_bottle_tag)
assert_success $? "get_bottle_tag should succeed"

# Test format (should be arch_codename or arch_linux)
assert_contains "$result" "_" "Bottle tag should contain underscore"

# Check for known architectures (arm64, x86_64, etc.)
assert_matches "arm64|_linux|x86_64|aarch64" "$result" "Bottle tag contains known architecture"

echo ""

# =============================================================================
# Tests for cache functions
# =============================================================================
echo "Testing cache functions..."

# Test get_manifest_filename format
result=$(get_manifest_filename "go" "1.25.7" "arm64_sonoma")
assert_equals "go--1.25.7--arm64_sonoma.json" "$result" "Cache filename format"

# Test is_cache_valid with non-existent file
is_cache_valid "/nonexistent/file.json"
exit_code=$?
assert_equals 1 "$exit_code" "Non-existent cache file should be invalid"

echo ""

# =============================================================================
# Tests for platform tag matching
# =============================================================================
echo "Testing platform tag matching..."

# Build a synthetic manifest with platform-specific and '.all' bottles
MANIFEST_DIR="$(mktemp -d)"
ALL_MANIFEST="${MANIFEST_DIR}/all-manifest.json"
cat >"$ALL_MANIFEST" <<'EOF'
{"manifests":[
  {"annotations":{"org.opencontainers.image.ref.name":"1.10.17.all"}},
  {"annotations":{"org.opencontainers.image.ref.name":"1.26.0.x86_64_sequoia"}}
]}
EOF

# Exact tag match
result=$(find_matching_platform_tag "$ALL_MANIFEST" "x86_64_sequoia")
assert_equals "1.26.0.x86_64_sequoia" "$result" "Exact platform tag match"

# '.all' fallback when no platform-specific bottle matches
result=$(find_matching_platform_tag "$ALL_MANIFEST" "arm64_tahoe")
assert_equals "1.10.17.all" "$result" "Fallback to architecture-independent '.all' bottle"

# Older macOS codename fallback (tahoe -> sequoia)
ONLY_ARCH_MANIFEST="${MANIFEST_DIR}/arch-manifest.json"
cat >"$ONLY_ARCH_MANIFEST" <<'EOF'
{"manifests":[
  {"annotations":{"org.opencontainers.image.ref.name":"1.26.0.arm64_sequoia"}}
]}
EOF
result=$(find_matching_platform_tag "$ONLY_ARCH_MANIFEST" "arm64_tahoe")
assert_equals "1.26.0.arm64_sequoia" "$result" "Older macOS codename fallback"

# No match at all -> failure
find_matching_platform_tag "$ONLY_ARCH_MANIFEST" "x86_64_tahoe" >/dev/null 2>&1
exit_code=$?
assert_equals 1 "$exit_code" "No matching platform tag should fail"

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
