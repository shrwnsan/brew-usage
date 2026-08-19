#!/usr/bin/env bash
# Tests for brew-usage doctor --fix / --fix --yes (PRD-004)
# Unit checks run everywhere (subshell export-before-source fixture pattern,
# same conventions as tests/test-doctor.sh); CLI checks exercise the real
# entry point with fixture cache dirs via exported BREW_BOTTLE_CACHE_DIR.

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

# Build a fixture cache dir with the standard manifest mix:
# 2 expired (old mtime), 1 fresh brew-usage manifests + Homebrew decoy
# Input: dir path
make_fixture_cache() {
    local dir="$1"
    mkdir -p "$dir"
    printf '{}' > "$dir/go--1.25.7--arm64_sonoma.json"
    touch -t 202001010000 "$dir/go--1.25.7--arm64_sonoma.json"
    printf '{}' > "$dir/wget--1.0--x86_64_linux.json"
    touch -t 202001010000 "$dir/wget--1.0--x86_64_linux.json"
    printf '{}' > "$dir/node--20.0--arm64_sonoma.json"   # fresh (just created)
    # Decoy: Homebrew's own manifest naming, must always survive
    printf '{}' > "$dir/abcdef--go-1.25.bottle_manifest.json"
}

# Count brew-usage-owned manifests (*--*--*.json) present in a dir
count_own_manifests() {
    local n=0 f
    for f in "$1"/*--*--*.json; do
        [[ -f "$f" ]] && n=$((n + 1))
    done
    printf '%s' "$n"
}

echo "========================================"
echo "Doctor --fix Tests (brew-usage doctor --fix)"
echo "========================================"
echo ""

# =============================================================================
# Unit tests (brew-independent): flush_expired_manifests + registry helpers
# in fresh /bin/bash shells with fixture env overrides
# =============================================================================
echo "Testing flush_expired_manifests unit behavior..."

UNIT_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-unit.XXXXXX")
trap 'rm -rf "$UNIT_CACHE_DIR"' EXIT
make_fixture_cache "$UNIT_CACHE_DIR"

UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$UNIT_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    out=$(flush_expired_manifests); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "2 expired manifest(s) removed|exit=0" "$UNIT_OUT" \
    "flush_expired_manifests removes exactly the 2 expired manifests"

for survivor in "node--20.0--arm64_sonoma.json" \
                "abcdef--go-1.25.bottle_manifest.json"; do
    if [[ -f "$UNIT_CACHE_DIR/$survivor" ]]; then
        assert_equals "yes" "yes" "unit flush leaves '$survivor' untouched"
    else
        assert_equals "yes" "no" "unit flush leaves '$survivor' untouched"
    fi
done
assert_equals "1" "$(count_own_manifests "$UNIT_CACHE_DIR")" \
    "exactly the fresh manifest remains after unit flush"

# Nothing expired: 0 removed, fresh files survive
FRESH_ONLY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-fresh.XXXXXX")
printf '{}' > "$FRESH_ONLY_DIR/go--1.25.7--arm64_sonoma.json"
UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$FRESH_ONLY_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    out=$(flush_expired_manifests); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "0 expired manifest(s) removed|exit=0" "$UNIT_OUT" \
    "nothing expired: 0 removed, exit 0"
if [[ -f "$FRESH_ONLY_DIR/go--1.25.7--arm64_sonoma.json" ]]; then
    assert_equals "yes" "yes" "fresh manifest survives when nothing is expired"
else
    assert_equals "yes" "no" "fresh manifest survives when nothing is expired"
fi
rm -rf "$FRESH_ONLY_DIR"

echo ""
echo "Testing fix registry helpers..."

# doctor_count_expired_manifests: 2 on the standard fixture, 0 without dir
UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$UNIT_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_count_expired_manifests)"
')
assert_equals "0" "$UNIT_OUT" \
    "count_expired_manifests: 0 after the unit flush removed them"

UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$UNIT_CACHE_DIR/missing" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_count_expired_manifests)"
')
assert_equals "0" "$UNIT_OUT" "count_expired_manifests: 0 when dir is missing"

# Registry: exactly one entry, flush-expired-manifests (manifest-cache, safe)
UNIT_OUT=$(/bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_fixes
')
assert_equals "flush-expired-manifests|manifest-cache|safe|flush_expired_manifests" \
    "$UNIT_OUT" "registry has exactly the v0.7.0 fix entry"

# doctor_plan_fixes on the fresh fixture: no fixes available
FRESH2_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-fresh2.XXXXXX")
printf '{}' > "$FRESH2_DIR/go--1.25.7--arm64_sonoma.json"
UNIT_OUT=$(BREW_BOTTLE_CACHE_DIR="$FRESH2_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_plan_fixes >/dev/null
    printf "%s|%s" "$DOCTOR_FIX_PLANNED" "$DOCTOR_FIX_APPLIED"
')
assert_equals "0|" "$UNIT_OUT" "plan with nothing expired: 0 fixes planned"
rm -rf "$FRESH2_DIR"

# =============================================================================
# CLI tests: flags, conflicts, dry run, apply (fixture cache dir via env)
# =============================================================================
echo ""
echo "Testing doctor --fix CLI behavior..."

CLI_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-cli.XXXXXX")
make_fixture_cache "$CLI_CACHE_DIR"

# --- invalid combos (exit 1, clear stderr) ---------------------------------
ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --fix 2>&1); RC=$?
assert_exit_code 1 "$RC" "--fix without doctor mode exits 1"
assert_contains "$ERR" "doctor" "--fix error mentions doctor mode"

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --yes 2>&1); RC=$?
assert_exit_code 1 "$RC" "--yes without --fix exits 1"
assert_contains "$ERR" "--fix" "--yes error mentions --fix"

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --yes 2>&1); RC=$?
assert_exit_code 1 "$RC" "doctor --yes without --fix exits 1"

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --json 2>&1); RC=$?
assert_exit_code 1 "$RC" "doctor --fix --json exits 1"
assert_contains "$ERR" "mutually exclusive" "--fix --json error names the conflict"

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --json --fix doctor 2>&1); RC=$?
assert_exit_code 1 "$RC" "--json --fix doctor exits 1 (order-independent)"

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --fix --top 5 2>&1); RC=$?
assert_exit_code 1 "$RC" "--fix --top 5 (no doctor) exits 1"

# --- conflicts with every non-doctor mode flag, both orders -----------------
for pair in "--top 5|doctor --fix" "doctor --fix|--top 5" \
            "--formulae|doctor --fix" "doctor --fix|--formulae" \
            "--casks|doctor --fix" "doctor --fix|--casks" \
            "--sort name|doctor --fix" "doctor --fix|--sort name" \
            "--cache|doctor --fix" "doctor --fix|--cache" \
            "--all|doctor --fix" "doctor --fix|--all" \
            "--size go|doctor --fix" "doctor --fix|--size go" \
            "--flush-cache|doctor --fix" "doctor --fix|--flush-cache"; do
    before="${pair%%|*}"
    after="${pair##*|}"
    # shellcheck disable=SC2086 # intentional word splitting of flag pairs
    OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" $before $after 2>&1)
    RC=$?
    assert_exit_code 1 "$RC" "'$before $after' conflicts (exit 1)"
done

# --- dry run: plan printed, NOTHING applied --------------------------------
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix 2>/dev/null); RC=$?
assert_contains "$OUT" "Planned fixes (dry run — nothing applied):" \
    "dry run prints the plan header"
assert_contains "$OUT" "flush-expired-manifests  [manifest-cache]" \
    "dry run lists the fix id and source check"
assert_contains "$OUT" "Remove 2 expired manifest cache file(s) (brew-usage-owned only)" \
    "dry run description includes the expired count"
assert_contains "$OUT" "1 fix planned. Re-run with --yes to apply." \
    "dry run prints the count footer"
assert_equals "3" "$(count_own_manifests "$CLI_CACHE_DIR")" \
    "dry run removes zero files (all 3 manifests still present)"
if [[ -f "$CLI_CACHE_DIR/abcdef--go-1.25.bottle_manifest.json" ]]; then
    assert_equals "yes" "yes" "dry run leaves Homebrew's manifest originals alone"
else
    assert_equals "yes" "no" "dry run leaves Homebrew's manifest originals alone"
fi
if [[ "$OUT" == *"applied:"* ]]; then
    assert_equals "no applied lines" "found applied:" "dry run applies nothing"
else
    assert_equals "yes" "yes" "dry run applies nothing"
fi

# --- dry run composes with --no-color ---------------------------------------
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --no-color 2>/dev/null); RC=$?
assert_contains "$OUT" "Planned fixes" "doctor --fix --no-color composes"
assert_equals "3" "$(count_own_manifests "$CLI_CACHE_DIR")" \
    "--no-color dry run still removes zero files"

# --- apply: --yes removes exactly the 2 expired, then after report ----------
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "applied: flush-expired-manifests — 2 expired manifest(s) removed" \
    "--yes prints the applied line with removal count"
assert_equals "1" "$(count_own_manifests "$CLI_CACHE_DIR")" \
    "--yes removes exactly the 2 expired manifests"
if [[ -f "$CLI_CACHE_DIR/abcdef--go-1.25.bottle_manifest.json" ]]; then
    assert_equals "yes" "yes" "--yes leaves Homebrew's manifest originals alone"
else
    assert_equals "yes" "no" "--yes leaves Homebrew's manifest originals alone"
fi

# After report: two doctor reports in the output (before + after)
assert_equals "2" "$(printf '%s\n' "$OUT" | grep -c '^brew-usage doctor$')" \
    "--fix --yes prints the before and after reports"

# Exit code equals the after-report verdict: compare with a follow-up bare run
BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor >/dev/null 2>&1; RC_AFTER=$?
assert_exit_code "$RC_AFTER" "$RC" \
    "--fix --yes exit code equals the after-report (bare doctor) verdict"

# Re-running --fix --yes with nothing expired: no fixes available, exit matches bare doctor
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "No fixes available (findings are report-only)." \
    "--fix --yes with nothing fixable prints the no-fixes line"
assert_exit_code "$RC_AFTER" "$RC" \
    "no-op --fix --yes exit code still matches the bare doctor verdict"

# Plain doctor --fix with nothing expired: no fixes available
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix 2>/dev/null); RC=$?
assert_contains "$OUT" "No fixes available (findings are report-only)." \
    "doctor --fix with nothing fixable prints the no-fixes line"

# --- existing doctor behavior unchanged --------------------------------------
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor 2>/dev/null); RC=$?
assert_contains "$OUT" "Summary:" "plain doctor still prints a Summary line"
if [[ "$OUT" == *"Planned fixes"* ]]; then
    assert_equals "no plan section" "found one" "plain doctor has no fix plan section"
else
    assert_equals "yes" "yes" "plain doctor has no fix plan section"
fi

# --- display_help documents --fix and --yes ----------------------------------
OUT=$("$BREW_USAGE" --help 2>/dev/null)
assert_contains "$OUT" "--fix" "display_help documents --fix"
assert_contains "$OUT" "--yes" "display_help documents --yes"

rm -rf "$CLI_CACHE_DIR"

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
