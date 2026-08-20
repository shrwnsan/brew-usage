#!/usr/bin/env bash
# Tests for --snapshot / --history (PRD-008: size history snapshots)
# Unit checks exercise lib/brew-usage-history.sh with a fixture prefix
# (mocked brew list/--prefix, real du) and a fixture history file; CLI
# checks run the entry point with BREW_USAGE_HISTORY_FILE overridden.

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

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
        return 0
    fi
    ((TESTS_FAILED++))
    echo -e "${RED}✗${NC} $message"
    return 1
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
    fi
    ((TESTS_FAILED++))
    echo -e "${RED}✗${NC} $message"
    return 1
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
    fi
    ((TESTS_FAILED++))
    echo -e "${RED}✗${NC} $message"
    return 1
}

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$TEST_DIR")/lib"
BREW_USAGE="$(dirname "$TEST_DIR")/brew-usage"

# Fixture history file (BREW_USAGE_HISTORY_FILE is read at source time)
HIST_FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-snapshot-hist.XXXXXX")
BREW_USAGE_HISTORY_FILE="$HIST_FIXTURE_DIR/snapshots.jsonl"
export BREW_USAGE_HISTORY_FILE

source "$LIB_DIR/brew-usage-config.sh"
source "$LIB_DIR/brew-usage-utils.sh"
source "$LIB_DIR/brew-usage-scan.sh"
source "$LIB_DIR/brew-usage-calculate.sh"
source "$LIB_DIR/brew-usage-display.sh"
source "$LIB_DIR/brew-usage-history.sh"

echo "========================================"
echo "brew-usage Snapshot/History Tests"
echo "========================================"
echo ""

# =============================================================================
# Fixture prefix: a fake Homebrew with two formulae and one cask, plus a
# mock brew whose list/--prefix answer from it
# =============================================================================
FIXTURE_PREFIX=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-snapshot-prefix.XXXXXX")
mkdir -p "$FIXTURE_PREFIX/Cellar/go/1.26.5/bin" "$FIXTURE_PREFIX/Cellar/jq/1.8.2/bin" \
         "$FIXTURE_PREFIX/Caskroom/wget/1.25.0"
head -c 200000 /dev/zero > "$FIXTURE_PREFIX/Cellar/go/1.26.5/bin/go"
head -c 50000 /dev/zero > "$FIXTURE_PREFIX/Cellar/jq/1.8.2/bin/jq"
head -c 10000 /dev/zero > "$FIXTURE_PREFIX/Caskroom/wget/1.25.0/wget"

MOCK_BIN=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-snapshot-bin.XXXXXX")
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "--prefix" ]]; then
    echo "$FIXTURE_PREFIX"
    exit 0
fi
if [[ "\$1" == "list" && "\$2" == "--formula" ]]; then
    printf 'go\njq\n'
    exit 0
fi
if [[ "\$1" == "list" && "\$2" == "--cask" ]]; then
    printf 'wget\n'
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/brew"
OLD_PATH="$PATH"
PATH="$MOCK_BIN:$PATH"

# =============================================================================
# write_snapshot unit behavior
# =============================================================================
echo "Testing write_snapshot (fixture prefix, mocked brew)..."

snapshot=$(write_snapshot); rc=$?
assert_exit_code 0 "$rc" "first snapshot records successfully"
assert_equals "3" "$(printf '%s' "$snapshot" | jq -r '.package_count')" \
    "two formulae + one cask recorded"
assert_equals "3" "$(printf '%s' "$snapshot" | jq -r '.packages | length')" \
    "packages object has all three names"
assert_equals "true" "$(printf '%s' "$snapshot" | jq -r '.packages | has("go") and has("jq") and has("wget")')" \
    "package names from brew list land in the map"

# du is block-based: expected bytes come from the same machinery
go_expected=$(get_size_bytes "$FIXTURE_PREFIX/Cellar/go")
assert_equals "$go_expected" "$(printf '%s' "$snapshot" | jq -r '.packages.go')" \
    "go size matches du of its Cellar path"
total_expected=$(( go_expected + $(get_size_bytes "$FIXTURE_PREFIX/Cellar/jq") + $(get_size_bytes "$FIXTURE_PREFIX/Caskroom/wget") ))
assert_equals "$total_expected" "$(printf '%s' "$snapshot" | jq -r '.total_bytes')" \
    "total_bytes sums the three packages"

assert_equals "1" "$(wc -l < "$BREW_USAGE_HISTORY_FILE" | tr -d ' ')" \
    "first snapshot appended exactly one line"
assert_equals "700" "$(stat -f %Lp "$HIST_FIXTURE_DIR" 2>/dev/null || stat -c %a "$HIST_FIXTURE_DIR")" \
    "history dir created 0700"

snapshot2=""
snapshot2=$(write_snapshot); rc=$?
assert_exit_code 0 "$rc" "second snapshot records successfully"
assert_equals "$(printf '%s' "$snapshot" | jq -cS '.packages')" \
    "$(printf '%s' "$snapshot2" | jq -cS '.packages')" \
    "second snapshot sees the same packages (deterministic scan)"
assert_equals "2" "$(wc -l < "$BREW_USAGE_HISTORY_FILE" | tr -d ' ')" \
    "second snapshot appends (2 lines)"

# =============================================================================
# Prune: 90-snapshot cap
# =============================================================================
echo "Testing the retention cap..."

rm -f "$BREW_USAGE_HISTORY_FILE"
i=1
while (( i <= 95 )); do
    printf '{"timestamp":"t%s","package_count":1,"total_bytes":%s,"packages":{"go":%s}}\n' "$i" "$i" "$i" >> "$BREW_USAGE_HISTORY_FILE"
    i=$((i + 1))
done
snapshot=$(write_snapshot); rc=$?
assert_exit_code 0 "$rc" "snapshot after 95 seeded lines records"
assert_equals "90" "$(wc -l < "$BREW_USAGE_HISTORY_FILE" | tr -d ' ')" \
    "cap enforced: exactly 90 lines remain"
assert_equals "t7" "$(sed -n '1p' "$BREW_USAGE_HISTORY_FILE" | jq -r '.timestamp')" \
    "oldest survivors start at the 7th seeded line (newest 90 kept)"
assert_equals "0" "$(find "$HIST_FIXTURE_DIR" -name '.brew-usage-history.*' | wc -l | tr -d ' ')" \
    "prune leaves no staging droppings"

# =============================================================================
# history readers (seeded lines, no brew needed)
# =============================================================================
echo "Testing history diff readers..."

rm -f "$BREW_USAGE_HISTORY_FILE"
cat > "$BREW_USAGE_HISTORY_FILE" <<'EOF'
{"timestamp":"2026-08-01T10:00:00+08:00","package_count":3,"total_bytes":4000000,"packages":{"go":1000000,"jq":2000000,"old":1000000}}
{"timestamp":"2026-08-20T16:00:00+08:00","package_count":3,"total_bytes":4500000,"packages":{"go":1500000,"jq":2000000,"new":1000000}}
EOF

changes=$(history_diff_changes); rc=$?
assert_exit_code 0 "$rc" "two seeded snapshots diff"
# Sorted by absolute delta: old removed (1M) and new added (1M) tie
# ahead of go's growth (500K); jq is unchanged and therefore omitted
assert_equals "3" "$(printf '%s\n' "$changes" | grep -c .)" \
    "three changes (grew, added, removed); unchanged jq omitted"
assert_equals "1" "$(printf '%s\n' "$changes" | grep -c '^go	1000000	1500000	500000	grew$')" \
    "grew change recorded with from/to/delta"
assert_equals "1" "$(printf '%s\n' "$changes" | grep -c '^old	1000000	0	-1000000	removed$')" \
    "removed change recorded"
assert_equals "1" "$(printf '%s\n' "$changes" | grep -c '^new	0	1000000	1000000	added$')" \
    "added change recorded"

rm -f "$BREW_USAGE_HISTORY_FILE"
printf '%s\n' '{"timestamp":"t1","package_count":1,"total_bytes":1,"packages":{"go":1}}' > "$BREW_USAGE_HISTORY_FILE"
err=$(history_diff_changes 2>&1); rc=$?
assert_exit_code 1 "$rc" "one snapshot: exit 1"
assert_contains "$err" "at least 2 snapshots" "one snapshot: explains the requirement"

rm -f "$BREW_USAGE_HISTORY_FILE"
err=$(history_diff_changes 2>&1); rc=$?
assert_exit_code 1 "$rc" "no history file: exit 1"
assert_contains "$err" "record one with --snapshot" "missing file suggests --snapshot"

printf '%s\n' 'not json' >> "$BREW_USAGE_HISTORY_FILE"
printf '%s\n' '{"timestamp":"t1","package_count":1,"total_bytes":1,"packages":{"go":1}}' >> "$BREW_USAGE_HISTORY_FILE"
err=$(history_diff_changes 2>&1); rc=$?
assert_exit_code 1 "$rc" "malformed line: exit 1"
assert_contains "$err" "malformed" "malformed line named"

# =============================================================================
# render_history (human + JSON) from seeded lines
# =============================================================================
echo "Testing render_history / render_history_json..."

rm -f "$BREW_USAGE_HISTORY_FILE"
cat > "$BREW_USAGE_HISTORY_FILE" <<'EOF'
{"timestamp":"2026-08-01T10:00:00+08:00","package_count":2,"total_bytes":3000000,"packages":{"go":1000000,"old":2000000}}
{"timestamp":"2026-08-20T16:00:00+08:00","package_count":3,"total_bytes":4000000,"packages":{"go":3000000,"new":1000000}}
EOF

out=$(render_history false); rc=$?
assert_exit_code 0 "$rc" "render_history succeeds"
assert_contains "$out" "2026-08-01T10:00:00+08:00" "old summary line shown"
assert_contains "$out" "2026-08-20T16:00:00+08:00" "new summary line shown"
assert_contains "$out" "new (new)" "added package tagged (new)"
assert_contains "$out" "old (removed)" "removed package tagged (removed)"
assert_contains "$out" "+1.9" "growth rendered with a plus sign"

json=$(render_history_json); rc=$?
assert_exit_code 0 "$rc" "render_history_json succeeds"
assert_equals "old" "$(printf '%s' "$json" | jq -r '.changes[0].name')" \
    "JSON: biggest mover first (removed package, 2M delta)"
assert_equals "-2000000" "$(printf '%s' "$json" | jq -r '.changes[0].delta')" \
    "JSON: delta carried"
assert_equals "2026-08-01T10:00:00+08:00" "$(printf '%s' "$json" | jq -r '.old.timestamp')" \
    "JSON: old timestamp"
assert_equals "added" "$(printf '%s' "$json" | jq -r '.changes[] | select(.name == "new") | .change')" \
    "JSON: added change tag"

# =============================================================================
# CLI behavior (mocked brew still on PATH)
# =============================================================================
echo "Testing CLI paths..."

rm -f "$BREW_USAGE_HISTORY_FILE"
out=$("$BREW_USAGE" --snapshot 2>/dev/null); rc=$?
assert_exit_code 0 "$rc" "--snapshot exits 0"
assert_contains "$out" "Snapshot #1 recorded" "confirmation names the snapshot number"
assert_contains "$out" "3 packages" "confirmation names the package count"
assert_contains "$out" "keeping the last 90" "confirmation states the retention cap"

out=$("$BREW_USAGE" --snapshot --json 2>/dev/null); rc=$?
assert_exit_code 0 "$rc" "--snapshot --json exits 0"
assert_equals "3" "$(printf '%s' "$out" | jq -r '.package_count')" \
    "--snapshot --json: the recorded line is the document"

"$BREW_USAGE" --snapshot >/dev/null 2>&1
out=$("$BREW_USAGE" --history 2>/dev/null); rc=$?
assert_exit_code 0 "$rc" "--history after two snapshots exits 0"
assert_contains "$out" "No per-package changes" "identical snapshots report no changes"

err=$("$BREW_USAGE" --snapshot --top 5 2>&1 >/dev/null); rc=$?
assert_exit_code 1 "$rc" "--snapshot --top exits 1"
assert_contains "$err" "mutually exclusive" "--snapshot conflict explained"

err=$("$BREW_USAGE" --history --size go 2>&1 >/dev/null); rc=$?
assert_exit_code 1 "$rc" "--history --size exits 1"

err=$("$BREW_USAGE" --snapshot --history 2>&1 >/dev/null); rc=$?
assert_exit_code 1 "$rc" "--snapshot --history exits 1"
assert_contains "$err" "mutually exclusive" "snapshot/history exclusivity explained"

err=$("$BREW_USAGE" --history --flush-cache 2>&1 >/dev/null); rc=$?
assert_exit_code 1 "$rc" "--history --flush-cache exits 1"

out=$("$BREW_USAGE" --history --json 2>/dev/null); rc=$?
assert_exit_code 0 "$rc" "--history --json exits 0"
assert_equals "1" "$(printf '%s' "$out" | jq -s 'length')" "stdout is exactly one JSON document"

out=$("$BREW_USAGE" --help 2>/dev/null)
assert_contains "$out" "--snapshot" "display_help documents --snapshot"
assert_contains "$out" "--history" "display_help documents --history"

# Restore the real PATH
PATH="$OLD_PATH"
rm -rf "$MOCK_BIN" "$FIXTURE_PREFIX" "$HIST_FIXTURE_DIR"

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
