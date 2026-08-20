#!/usr/bin/env bash
# Tests for brew-usage doctor --fix / --fix --yes (PRD-004)
# Unit checks run everywhere (subshell export-before-source fixture pattern,
# same conventions as tests/test-doctor.sh); CLI checks exercise the real
# entry point with fixture cache dirs via exported BREW_BOTTLE_CACHE_DIR.

# isolate from developer's ~/.brew-usage-config
BREW_USAGE_CONFIG_FILE="$(mktemp -u)/nonexistent-config"
export BREW_USAGE_CONFIG_FILE

# isolate from the developer's real brew-change export (PRD-010): without
# this the flush-stale-manifests fix is due whenever the machine's export
# names a package matching a fixture cache file — nondeterministic tests
BREW_CHANGE_EXPORT_FILE="$(mktemp -u)/nonexistent-brew-change-export"
export BREW_CHANGE_EXPORT_FILE

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

# Count files in a directory whose names match a glob pattern
# (shellcheck-clean alternative to ls | grep -c)
# Input: directory, glob pattern (e.g. 'config.bak-*')
count_glob_matches() {
    local dir="$1"
    local pattern="$2"
    local n=0 f
    # shellcheck disable=SC2086 # the pattern must glob, not split
    for f in "$dir"/$pattern; do
        [[ -f "$f" ]] && n=$((n + 1))
    done
    printf '%s' "$n"
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

# Registry: the v0.7.0 + PRD-010 safe-tier entries, both PRD-005
# config-tier entries, the PRD-006 install-tier entry
UNIT_OUT=$(/bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_fixes
')
assert_equals "flush-expired-manifests|manifest-cache|safe|flush_expired_manifests
flush-stale-manifests|brew-change-stale|safe|flush_stale_manifests
repair-config-lines|config-valid|config|repair_config_lines
clamp-cache-ttl|ttl-sane|config|clamp_cache_ttl
install-jq|jq-present|install|install_jq" \
    "$UNIT_OUT" "registry has both safe + both config + install tier entries"

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

# --- flush-stale-manifests (PRD-010): surgical, export-driven -----------------
echo ""
echo "Testing flush-stale-manifests..."

BCF_EXPORT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-bc.XXXXXX")
printf '%s\n' '{"schema_version":1,"generated_at":"2026-08-21T00:00:00Z","packages":[
 {"name":"go","installed_version":"1.25.5","available_version":"1.26.7"},
 {"name":"node","installed_version":"20.0","available_version":"22.9.0"}]}' \
    > "$BCF_EXPORT_DIR/good.json"

BCF_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-bc-cache.XXXXXX")
printf '{}' > "$BCF_CACHE_DIR/go--1.25.5--arm64_sonoma.json"   # stale: goes
printf '{}' > "$BCF_CACHE_DIR/go--1.26.7--arm64_sonoma.json"   # fresh: stays
printf '{}' > "$BCF_CACHE_DIR/node--20.0--arm64_sonoma.json"   # stale: goes
printf '{}' > "$BCF_CACHE_DIR/wget--1.0--arm64_sonoma.json"    # untracked: stays
printf '{}' > "$BCF_CACHE_DIR/abcdef--go-1.25.bottle_manifest.json"  # decoy: stays

# Not due without a usable export (absent file)
UNIT_OUT=$(BREW_CHANGE_EXPORT_FILE="$BCF_EXPORT_DIR/missing.json" BREW_BOTTLE_CACHE_DIR="$BCF_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    flush_stale_manifests
')
assert_equals "0 stale manifest(s) removed (0 package(s) changed upstream)" "$UNIT_OUT" \
    "flush_stale_manifests: no usable export removes nothing"

# Apply removes exactly the stale files; fresh/untracked/decoy survive
UNIT_OUT=$(BREW_CHANGE_EXPORT_FILE="$BCF_EXPORT_DIR/good.json" BREW_BOTTLE_CACHE_DIR="$BCF_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-size.sh" 2>/dev/null
    flush_stale_manifests
')
assert_equals "2 stale manifest(s) removed (2 package(s) changed upstream)" "$UNIT_OUT" \
    "flush_stale_manifests: removes exactly the stale-version files"
for survivor in "go--1.26.7--arm64_sonoma.json" "wget--1.0--arm64_sonoma.json" \
                "abcdef--go-1.25.bottle_manifest.json"; do
    if [[ -f "$BCF_CACHE_DIR/$survivor" ]]; then
        assert_equals "yes" "yes" "stale flush leaves '$survivor' untouched"
    else
        assert_equals "yes" "no" "stale flush leaves '$survivor' untouched"
    fi
done
for removed in "go--1.25.5--arm64_sonoma.json" "node--20.0--arm64_sonoma.json"; do
    if [[ ! -f "$BCF_CACHE_DIR/$removed" ]]; then
        assert_equals "yes" "yes" "stale flush removes '$removed'"
    else
        assert_equals "yes" "no" "stale flush removes '$removed'"
    fi
done

# Registry plan composition: dry run names the fix with the count
printf '{}' > "$BCF_CACHE_DIR/go--1.25.5--arm64_sonoma.json"   # re-add stale
UNIT_OUT=$(BREW_CHANGE_EXPORT_FILE="$BCF_EXPORT_DIR/good.json" BREW_BOTTLE_CACHE_DIR="$BCF_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_plan_fixes
' | grep "flush-stale-manifests" | head -1)
assert_equals "  flush-stale-manifests  [brew-change-stale]" "$UNIT_OUT" \
    "dry run plans flush-stale-manifests when the export proves staleness"

# CLI end-to-end: doctor --fix --yes applies it and the after report clears
OUT=$(BREW_CHANGE_EXPORT_FILE="$BCF_EXPORT_DIR/good.json" BREW_BOTTLE_CACHE_DIR="$BCF_CACHE_DIR" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "applied: flush-stale-manifests — 1 stale manifest(s) removed" \
    "CLI --fix --yes applies the stale-manifest flush"
assert_contains "$OUT" "cache agrees with brew-change" \
    "after report shows brew-change-stale passing again"
rm -rf "$BCF_EXPORT_DIR" "$BCF_CACHE_DIR"

# --- config fix helpers and apply functions (PRD-005) ------------------------
echo ""
echo "Testing config fix helpers..."

UNIT_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-cfg-unit.XXXXXX")
cat > "$UNIT_CONFIG_DIR/config" << 'EOF'
TOP_N=5
junk line here
MYSTERY_KEY=1
EOF

# doctor_count_config_bad_lines: fresh re-parse with the loader's rules
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/config" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_count_config_bad_lines)"
')
assert_equals "2" "$UNIT_OUT" "count_config_bad_lines counts malformed + unknown-key lines"

UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/missing" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_count_config_bad_lines)"
')
assert_equals "0" "$UNIT_OUT" "count_config_bad_lines: 0 when the file is missing"

# repair-config-lines is not due without a config file (config-valid only
# warns when the file exists and has bad lines)
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/missing" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_fix_description repair-config-lines)"
')
assert_equals "" "$UNIT_OUT" "repair-config-lines not due without a config file"

# Standalone repair_config_lines: disables exactly the bad lines, making
# its own backup when no apply pass made one
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/config" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    out=$(repair_config_lines); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "2 line(s) disabled|exit=0" "$UNIT_OUT" \
    "repair_config_lines disables both bad lines (standalone, self backup)"
assert_equals "2" "$(grep -c '^# brew-usage-fix disabled line ' "$UNIT_CONFIG_DIR/config")" \
    "exactly the 2 bad lines carry the disabled marker"
assert_contains "$(cat "$UNIT_CONFIG_DIR/config")" \
    "# brew-usage-fix disabled line 2: junk line here" \
    "disabled marker names the offending line number"
assert_equals "TOP_N=5" "$(sed -n '1p' "$UNIT_CONFIG_DIR/config")" \
    "valid lines survive the repair untouched"
assert_equals "1" "$(count_glob_matches "$UNIT_CONFIG_DIR" 'config.bak-*')" \
    "repair made exactly one timestamped backup"

# clamp_cache_ttl standalone: comments the old value, writes 30 in place
printf 'CACHE_CLEANUP_DAYS=90\nTOP_N=3\n' > "$UNIT_CONFIG_DIR/ttl"
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/ttl" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    out=$(clamp_cache_ttl); rc=$?
    printf "%s|exit=%s\n" "$out" "$rc"
')
assert_equals "CACHE_CLEANUP_DAYS=90 -> 30|exit=0" "$UNIT_OUT" \
    "clamp_cache_ttl reports old -> 30"
assert_equals "# brew-usage-fix clamped from 90" "$(sed -n '1p' "$UNIT_CONFIG_DIR/ttl")" \
    "old CACHE_CLEANUP_DAYS line commented with the clamp marker"
assert_equals "CACHE_CLEANUP_DAYS=30" "$(sed -n '2p' "$UNIT_CONFIG_DIR/ttl")" \
    "clamped value written in place"

# clamp due-check driven by the effective value (non-numeric is impossible
# post-loader); sane values are not due
UNIT_OUT=$(CACHE_CLEANUP_DAYS=400 BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/missing" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_fix_description clamp-cache-ttl)"
')
assert_equals "Clamp CACHE_CLEANUP_DAYS: 400 -> 30" "$UNIT_OUT" \
    "clamp-cache-ttl due when effective CACHE_CLEANUP_DAYS > 30"
UNIT_OUT=$(CACHE_CLEANUP_DAYS=30 BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/missing" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    printf "%s" "$(doctor_fix_description clamp-cache-ttl)"
')
assert_equals "" "$UNIT_OUT" "clamp-cache-ttl not due when CACHE_CLEANUP_DAYS is sane"

# doctor_apply_fixes with both config fixes due: one shared backup, tier
# flag set for the entry-point re-source, per-fix results recorded
printf 'CACHE_CLEANUP_DAYS=400\nWHO_KNOWS=9\n' > "$UNIT_CONFIG_DIR/apply"
UNIT_OUT=$(BREW_USAGE_CONFIG_FILE="$UNIT_CONFIG_DIR/apply" BREW_BOTTLE_CACHE_DIR="$UNIT_CONFIG_DIR/missing-cache" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_apply_fixes >/dev/null
    printf "%s|%s|%s|%s|%s" "$DOCTOR_FIX_APPLIED" "$DOCTOR_FIX_DUE" \
        "$DOCTOR_CONFIG_FIX_APPLIED" "${DOCTOR_FIX_RESULT_IDS[*]}" \
        "${DOCTOR_FIX_RESULT_STATUSES[*]}"
')
assert_equals "2|2|true|repair-config-lines clamp-cache-ttl|applied applied" "$UNIT_OUT" \
    "apply pass: both config fixes applied, tier flag set, results recorded"
assert_equals "1" "$(count_glob_matches "$UNIT_CONFIG_DIR" 'apply.bak-*')" \
    "two config fixes in one pass share exactly one backup"
rm -rf "$UNIT_CONFIG_DIR"

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

ERR=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --yes --json 2>&1); RC=$?
assert_exit_code 1 "$RC" "--yes --json without --fix still exits 1"

# --- --fix composes with --json (PRD-005): dry-run JSON fix plan ------------
# v0.7.0 rejected this combination; it now emits the checks+summary report
# plus a fixes array, with the human plan lines moved to stderr
if command -v jq >/dev/null 2>&1; then
    CLI_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/brew-usage-doctor-fix-err.XXXXXX")
    JSON_OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --json 2>"$CLI_ERR_FILE"); RC=$?
    assert_equals "1" "$(printf '%s' "$JSON_OUT" | jq '.fixes | length')" \
        "doctor --fix --json: fixes array carries the one due fix"
    assert_equals "flush-expired-manifests" "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].id')" \
        "doctor --fix --json: fixes entry has the fix id"
    assert_equals "manifest-cache" "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].check')" \
        "doctor --fix --json: fixes entry names the source check"
    assert_equals "safe" "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].tier')" \
        "doctor --fix --json: fixes entry names the tier"
    assert_contains "$JSON_OUT" '"summary"' "doctor --fix --json keeps checks+summary"
    if [[ "$JSON_OUT" == *"Planned fixes"* ]]; then
        assert_equals "pure JSON stdout" "polluted" "doctor --fix --json stdout has no plan lines"
    else
        assert_equals "yes" "yes" "doctor --fix --json stdout has no plan lines"
    fi
    assert_contains "$(cat "$CLI_ERR_FILE")" "Planned fixes" \
        "doctor --fix --json moves plan lines to stderr"

    JSON_OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" --json --fix doctor 2>/dev/null)
    assert_equals "1" "$(printf '%s' "$JSON_OUT" | jq '.fixes | length')" \
        "--json --fix doctor composes order-independently"
else
    echo "(skipping --fix --json composition tests: jq not found)"
fi

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

# --- config repair fixes (PRD-005): repair-config-lines + clamp-cache-ttl -----
echo ""
echo "Testing doctor --fix config repairs..."

CLI_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-config.XXXXXX")
CLI_CONFIG_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-cfgcache.XXXXXX")
# One fresh manifest only: keeps the flush fix out of the way
printf '{}' > "$CLI_CONFIG_CACHE/go--1.25.7--arm64_sonoma.json"

BAD_CONFIG="$CLI_CONFIG_DIR/config"
cat > "$BAD_CONFIG" << 'EOF'
TOP_N=5
CACHE_CLEANUP_DAYS=7
this is bad
FOO=bar123
lowercase=3
SIZE_WARNING_THRESHOLD=200
EOF
cp -p "$BAD_CONFIG" "$BAD_CONFIG.orig"

# Dry run: plans exactly 1 fix, file byte-identical, no backup yet
OUT=$(BREW_USAGE_CONFIG_FILE="$BAD_CONFIG" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix 2>/dev/null); RC=$?
assert_contains "$OUT" "repair-config-lines  [config-valid]" \
    "config dry run lists repair-config-lines"
assert_contains "$OUT" "Comment out 3 malformed/unknown-key line(s) (config backed up first)" \
    "config dry run description carries the bad-line count"
assert_contains "$OUT" "1 fix planned. Re-run with --yes to apply." \
    "config dry run plans exactly 1 fix (TTL sane, manifests fresh)"
if cmp -s "$BAD_CONFIG" "$BAD_CONFIG.orig"; then
    assert_equals "yes" "yes" "config dry run leaves the file byte-identical"
else
    assert_equals "byte-identical" "changed" "config dry run leaves the file byte-identical"
fi
assert_equals "0" "$(count_glob_matches "$CLI_CONFIG_DIR" 'config.bak-*')" \
    "config dry run makes no backup"

# Apply: exactly the 3 bad lines commented, one backup holding the original
OUT=$(BREW_USAGE_CONFIG_FILE="$BAD_CONFIG" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "applied: repair-config-lines — 3 line(s) disabled" \
    "--yes applies repair-config-lines with the disabled count"
assert_equals "3" "$(grep -c '^# brew-usage-fix disabled line ' "$BAD_CONFIG")" \
    "exactly 3 lines carry the disabled marker"
assert_contains "$(cat "$BAD_CONFIG")" "# brew-usage-fix disabled line 3: this is bad" \
    "marker disabled line 3 (malformed)"
assert_contains "$(cat "$BAD_CONFIG")" "# brew-usage-fix disabled line 4: FOO=bar123" \
    "marker disabled line 4 (unknown key)"
assert_contains "$(cat "$BAD_CONFIG")" "# brew-usage-fix disabled line 5: lowercase=3" \
    "marker disabled line 5 (malformed)"
assert_equals "TOP_N=5" "$(sed -n '1p' "$BAD_CONFIG")" "valid line 1 untouched"
assert_equals "CACHE_CLEANUP_DAYS=7" "$(sed -n '2p' "$BAD_CONFIG")" "valid line 2 untouched"
assert_equals "1" "$(count_glob_matches "$CLI_CONFIG_DIR" 'config.bak-*')" \
    "apply pass made exactly one backup"
BAD_BACKUP=$(ls "$CLI_CONFIG_DIR"/config.bak-* | head -1)
if cmp -s "$BAD_BACKUP" "$BAD_CONFIG.orig"; then
    assert_equals "yes" "yes" "backup holds the pre-edit original"
else
    assert_equals "original" "modified" "backup holds the pre-edit original"
fi
assert_equals "2" "$(printf '%s\n' "$OUT" | grep -c '^brew-usage doctor$')" \
    "before + after reports printed"
assert_equals "1" "$(printf '%s\n' "$OUT" | grep -c '3 malformed line(s)')" \
    "before report warned about the 3 bad lines"
assert_equals "1" "$(printf '%s\n' "$OUT" | grep -c 'config file parses cleanly')" \
    "after report shows config-valid pass (0 malformed)"

# TTL>30 + one unknown-key line: both config fixes due in one pass ->
# ONE shared backup, clamp pair written, after report effective 30
TTL_CONFIG="$CLI_CONFIG_DIR/ttl-config"
printf 'CACHE_CLEANUP_DAYS=400\nWHO_KNOWS=9\n' > "$TTL_CONFIG"
OUT=$(BREW_USAGE_CONFIG_FILE="$TTL_CONFIG" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix 2>/dev/null); RC=$?
assert_contains "$OUT" "Clamp CACHE_CLEANUP_DAYS: 400 -> 30" \
    "TTL dry run plans the clamp with old -> 30"
assert_contains "$OUT" "2 fixes planned. Re-run with --yes to apply." \
    "TTL fixture plans both config fixes"

OUT=$(BREW_USAGE_CONFIG_FILE="$TTL_CONFIG" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "applied: repair-config-lines — 1 line(s) disabled" \
    "--yes applies repair-config-lines in the same pass"
assert_contains "$OUT" "applied: clamp-cache-ttl — CACHE_CLEANUP_DAYS=400 -> 30" \
    "--yes applies clamp-cache-ttl"
assert_equals "# brew-usage-fix clamped from 400" "$(sed -n '1p' "$TTL_CONFIG")" \
    "old TTL line commented with the clamp marker"
assert_equals "CACHE_CLEANUP_DAYS=30" "$(sed -n '2p' "$TTL_CONFIG")" \
    "clamped value written on the next line"
assert_equals "1" "$(count_glob_matches "$CLI_CONFIG_DIR" 'ttl-config.bak-*')" \
    "two config fixes in one pass share ONE backup"
assert_contains "$OUT" "TOP_N=10 thresholds=104857600/1073741824 CACHE_CLEANUP_DAYS=30" \
    "after report shows the effective value 30"

# Unwritable config dir: the shared backup fails -> apply FAILED, zero edits
RO_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-ro.XXXXXX")
printf 'TOP_N=abc\n' > "$RO_CONFIG_DIR/config"
cp -p "$RO_CONFIG_DIR/config" "$RO_CONFIG_DIR/config.orig"
chmod 555 "$RO_CONFIG_DIR"
OUT=$(BREW_USAGE_CONFIG_FILE="$RO_CONFIG_DIR/config" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "apply FAILED: repair-config-lines — config backup failed" \
    "unwritable config dir: apply FAILED names the backup failure"
chmod 755 "$RO_CONFIG_DIR"
if cmp -s "$RO_CONFIG_DIR/config" "$RO_CONFIG_DIR/config.orig"; then
    assert_equals "yes" "yes" "failed backup leaves the config file untouched"
else
    assert_equals "untouched" "edited" "failed backup leaves the config file untouched"
fi
assert_equals "0" "$(( $(count_glob_matches "$RO_CONFIG_DIR" 'config.bak-*') + $(count_glob_matches "$RO_CONFIG_DIR" '.brew-usage-fix.*') ))" \
    "failed pass leaves no backup or staging droppings"
rm -rf "$RO_CONFIG_DIR"

# Symlinked config: the atomic mv would replace the symlink itself —
# both config fixes refuse with zero edits (dotfiles-manager safety)
SYM_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-sym.XXXXXX")
printf 'TOP_N=5\nBROKEN LINE\n' > "$SYM_CONFIG_DIR/real-config"
ln -s "$SYM_CONFIG_DIR/real-config" "$SYM_CONFIG_DIR/link-config"
OUT=$(BREW_USAGE_CONFIG_FILE="$SYM_CONFIG_DIR/link-config" BREW_BOTTLE_CACHE_DIR="$CLI_CONFIG_CACHE" "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "apply FAILED: repair-config-lines — config file is a symlink" \
    "symlinked config: repair refuses with the symlink message"
if [[ -L "$SYM_CONFIG_DIR/link-config" ]]; then
    assert_equals "yes" "yes" "symlink survives the refused fix"
else
    assert_equals "symlink" "regular file" "symlink survives the refused fix"
fi
assert_equals "BROKEN LINE" "$(sed -n '2p' "$SYM_CONFIG_DIR/real-config")" \
    "symlink target content untouched by the refused fix"
assert_equals "0" "$(count_glob_matches "$SYM_CONFIG_DIR" 'real-config.bak-*')" \
    "refused fix creates no backup"
rm -rf "$SYM_CONFIG_DIR"

# --- --fix --yes --json: single after document with per-fix results -----------
if command -v jq >/dev/null 2>&1; then
    make_fixture_cache "$CLI_CACHE_DIR"   # re-add the 2 expired manifests

    JSON_OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --yes --json 2>"$CLI_ERR_FILE"); RC=$?
    assert_equals "1" "$(printf '%s' "$JSON_OUT" | jq '.fixes | length')" \
        "--fix --yes --json: one fix result entry"
    assert_equals "flush-expired-manifests" "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].id')" \
        "--fix --yes --json: result carries the fix id"
    assert_equals "applied" "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].status')" \
        "--fix --yes --json: status is applied"
    assert_contains "$(printf '%s' "$JSON_OUT" | jq -r '.fixes[0].result')" \
        "2 expired manifest(s) removed" \
        "--fix --yes --json: result carries the apply line"
    if [[ "$JSON_OUT" == *"applied:"* || "$JSON_OUT" == *"Planned fixes"* ]]; then
        assert_equals "pure JSON stdout" "polluted" "--fix --yes --json stdout has no human lines"
    else
        assert_equals "yes" "yes" "--fix --yes --json stdout has no human lines"
    fi
    assert_contains "$(cat "$CLI_ERR_FILE")" "applied: flush-expired-manifests" \
        "--fix --yes --json moves applied lines to stderr"
    assert_equals "1" "$(printf '%s' "$JSON_OUT" | jq -s 'length')" \
        "stdout carries exactly one JSON document"

    # Nothing fixable: fixes is an empty array
    JSON_OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor --fix --json 2>/dev/null)
    assert_equals "0" "$(printf '%s' "$JSON_OUT" | jq '.fixes | length')" \
        "nothing fixable: fixes is an empty array"

    # Result entries can carry the "skipped" status (install tier without
    # --install consent; PRD-006). A CLI-level test is impossible here —
    # JSON mode requires jq, install-jq requires jq absent — so the
    # result globals are simulated and only the JSON rendering is proven
    UNIT_OUT=$(/bin/bash -c '
        DOCTOR_FIX_RESULT_IDS=(install-jq)
        DOCTOR_FIX_RESULT_STATUSES=(skipped)
        DOCTOR_FIX_RESULT_LINES=("install tier needs --yes --install")
        source "'"$SCRIPT_DIR"'/lib/brew-usage-json.sh" 2>/dev/null
        json_doctor_fixes_results
    ')
    assert_equals "skipped" "$(printf '%s' "$UNIT_OUT" | jq -r '.[0].status')" \
        "json_doctor_fixes_results renders the skipped status"
    assert_equals "install-jq" "$(printf '%s' "$UNIT_OUT" | jq -r '.[0].id')" \
        "skipped result keeps the fix id"
else
    echo "(skipping --fix --yes --json tests: jq not found)"
fi

# --- install tier (PRD-006): install-jq due/skip/apply ------------------------
echo ""
echo "Testing install tier (install-jq)..."

# jq-free PATH with a brew mock: jq absent by construction, brew present.
# The mock logs every invocation and installs a jq stub on `install jq`
# unless a mode marker exists (.brew-fails → install errors; .brew-nojq →
# install succeeds but installs nothing). chmod's absolute path is
# resolved here (full PATH) because the mock itself runs under the
# stripped PATH where a bare chmod is unresolvable.
INSTALL_BIN=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-bin.XXXXXX")
BREW_LOG="$INSTALL_BIN/brew.log"
MOCK_CHMOD=$(command -v chmod)
for tool in dirname mkdir; do
    tool_path=$(command -v "$tool") && ln -s "$tool_path" "$INSTALL_BIN/$tool"
done
cat > "$INSTALL_BIN/brew" <<MOCK
#!/bin/sh
printf '%s\n' "\$*" >> "$BREW_LOG"
case "\$1 \$2" in
    "install jq")
        if [ -e "$INSTALL_BIN/.brew-fails" ]; then
            echo "Error: jq formula unavailable"
            exit 1
        fi
        if [ ! -e "$INSTALL_BIN/.brew-nojq" ]; then
            printf '#!/bin/sh\necho "jq-1.7.1"\n' > "$INSTALL_BIN/jq"
            "$MOCK_CHMOD" +x "$INSTALL_BIN/jq"
        fi
        ;;
    "--prefix") echo "/opt/homebrew" ;;
esac
exit 0
MOCK
chmod +x "$INSTALL_BIN/brew"

# Minimal PATH with neither brew nor jq (due-condition negative)
NO_BREW_BIN=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-nobrew.XXXXXX")
for tool in dirname mkdir; do
    tool_path=$(command -v "$tool") && ln -s "$tool_path" "$NO_BREW_BIN/$tool"
done

# Clean cache (no fixtures): only install-jq is due in this environment
INSTALL_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-usage-doctor-fix-icache.XXXXXX")

# Due: jq absent + brew present
UNIT_OUT=$(PATH="$INSTALL_BIN" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_fix_description "install-jq"
')
assert_equals "Install jq via Homebrew (--json/--size need it; apply needs --install)" "$UNIT_OUT" \
    "install-jq due when jq is absent and brew is on PATH"

# Not due: brew also absent (brew-present already fails with guidance)
UNIT_OUT=$(PATH="$NO_BREW_BIN" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_fix_description "install-jq"
')
assert_equals "" "$UNIT_OUT" \
    "install-jq NOT due when brew is also missing"

# Not due: jq present (jq-present passes; no install offer)
if command -v jq >/dev/null 2>&1; then
    UNIT_OUT=$(/bin/bash -c '
        source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
        doctor_fix_description "install-jq"
    ')
    assert_equals "" "$UNIT_OUT" \
        "install-jq never due when jq is present"
else
    echo "(skipping jq-present due test: jq not found)"
fi

# Apply without consent: skipped, brew never invoked, nothing installed
rm -f "$BREW_LOG"
UNIT_OUT=$(PATH="$INSTALL_BIN" BREW_BOTTLE_CACHE_DIR="$INSTALL_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_apply_fixes
    printf "|DUE=%s|APPLIED=%s" "$DOCTOR_FIX_DUE" "$DOCTOR_FIX_APPLIED"
')
assert_contains "$UNIT_OUT" "skipped: install-jq — install tier needs --yes --install" \
    "apply without --install skips install-jq with the consent hint"
assert_contains "$UNIT_OUT" "|DUE=1|APPLIED=0" \
    "skipped install counts as due, never as applied"
if [[ -f "$BREW_LOG" ]]; then
    assert_equals "not invoked" "invoked" "skipped install never calls brew"
else
    assert_equals "yes" "yes" "skipped install never calls brew"
fi

# Apply with consent: brew install jq runs, jq verified, applied counted
rm -f "$BREW_LOG"
UNIT_OUT=$(PATH="$INSTALL_BIN" DOCTOR_INSTALL_CONSENT=true BREW_BOTTLE_CACHE_DIR="$INSTALL_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_apply_fixes
    printf "|DUE=%s|APPLIED=%s" "$DOCTOR_FIX_DUE" "$DOCTOR_FIX_APPLIED"
')
assert_contains "$UNIT_OUT" "applied: install-jq — jq installed (jq-1.7.1)" \
    "apply with consent installs jq and reports the verified version"
assert_contains "$UNIT_OUT" "|DUE=1|APPLIED=1" \
    "consented install counts as due and applied"
assert_contains "$(cat "$BREW_LOG")" "install jq" \
    "the brew mock received 'install jq'"
rm -f "$INSTALL_BIN/jq"

# Apply with consent, brew install fails: FAILED with captured output
rm -f "$BREW_LOG"
touch "$INSTALL_BIN/.brew-fails"
UNIT_OUT=$(PATH="$INSTALL_BIN" DOCTOR_INSTALL_CONSENT=true BREW_BOTTLE_CACHE_DIR="$INSTALL_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_apply_fixes
    printf "|DUE=%s|APPLIED=%s" "$DOCTOR_FIX_DUE" "$DOCTOR_FIX_APPLIED"
')
assert_contains "$UNIT_OUT" "apply FAILED: install-jq — brew install jq failed: Error: jq formula unavailable" \
    "failing brew install reports FAILED with brew's error line"
assert_contains "$UNIT_OUT" "|DUE=1|APPLIED=0" \
    "failed install counts as due, never as applied"
if [[ -f "$INSTALL_BIN/jq" ]]; then
    assert_equals "no jq stub" "stub created" "failed install leaves no partial state"
else
    assert_equals "yes" "yes" "failed install leaves no partial state"
fi
rm -f "$INSTALL_BIN/.brew-fails"

# Apply with consent, brew succeeds but jq still unusable: FAILED
rm -f "$BREW_LOG"
touch "$INSTALL_BIN/.brew-nojq"
UNIT_OUT=$(PATH="$INSTALL_BIN" DOCTOR_INSTALL_CONSENT=true BREW_BOTTLE_CACHE_DIR="$INSTALL_CACHE_DIR" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    doctor_apply_fixes
    printf "|DUE=%s|APPLIED=%s" "$DOCTOR_FIX_DUE" "$DOCTOR_FIX_APPLIED"
')
assert_contains "$UNIT_OUT" "apply FAILED: install-jq — brew install jq completed but jq is not usable on PATH" \
    "install that leaves jq unusable reports FAILED with PATH guidance"
rm -f "$INSTALL_BIN/.brew-nojq"

# install_jq direct: brew absent -> defensive refusal
UNIT_OUT=$(PATH="$NO_BREW_BIN" /bin/bash -c '
    source "'"$SCRIPT_DIR"'/lib/brew-usage-doctor.sh" 2>/dev/null
    out=$(install_jq); rc=$?
    printf "%s|rc=%s" "$out" "$rc"
')
assert_contains "$UNIT_OUT" "brew not found on PATH — fix the brew-present check first" \
    "install_jq refuses clearly when brew vanished"
assert_contains "$UNIT_OUT" "|rc=1" "install_jq refusal exits 1"

# --- CLI: --install flag validation -------------------------------------------
ERR=$("$BREW_USAGE" --install 2>&1 >/dev/null); RC=$?
assert_exit_code 1 "$RC" "--install without --fix --yes exits 1"
assert_contains "$ERR" "--install is only valid together with --fix --yes" \
    "--install alone explains the requirement"

ERR=$("$BREW_USAGE" doctor --fix --install 2>&1 >/dev/null); RC=$?
assert_exit_code 1 "$RC" "--install with --fix but without --yes exits 1"

# --- CLI e2e (human mode, jq-free PATH + brew mock) ---------------------------
# Invoked via /bin/bash (shebang bypass): brew-usage's own shebang is
# `#!/usr/bin/env bash`, which cannot resolve bash on the stripped PATH
# Dry run: install-jq planned with the consent note
rm -f "$BREW_LOG"
OUT=$(PATH="$INSTALL_BIN" BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" /bin/bash "$BREW_USAGE" doctor --fix 2>/dev/null); RC=$?
assert_contains "$OUT" "install-jq  [jq-present]" \
    "dry run lists install-jq when jq is missing"
assert_contains "$OUT" "Install jq via Homebrew (--json/--size need it; apply needs --install)" \
    "dry-run description names the --install requirement"
assert_contains "$OUT" "Note: install-tier fixes apply only with --yes --install." \
    "dry run prints the install-tier note"

# --fix --yes (no --install): skipped, brew never asked to install
rm -f "$BREW_LOG"
OUT=$(PATH="$INSTALL_BIN" BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" /bin/bash "$BREW_USAGE" doctor --fix --yes 2>/dev/null); RC=$?
assert_contains "$OUT" "skipped: install-jq — install tier needs --yes --install" \
    "CLI --fix --yes without --install skips install-jq"
if grep -q "install jq" "$BREW_LOG" 2>/dev/null; then
    assert_equals "not invoked" "invoked" "CLI skip never runs brew install jq"
else
    assert_equals "yes" "yes" "CLI skip never runs brew install jq"
fi

# --fix --yes --install: applied, after report shows the installed jq
rm -f "$BREW_LOG"
OUT=$(PATH="$INSTALL_BIN" BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" /bin/bash "$BREW_USAGE" doctor --fix --yes --install 2>/dev/null); RC=$?
assert_contains "$OUT" "applied: install-jq — jq installed (jq-1.7.1)" \
    "CLI --fix --yes --install applies the install"
assert_contains "$(cat "$BREW_LOG")" "install jq" \
    "CLI run reaches the brew mock with install jq"
assert_contains "$OUT" "jq-1.7.1" \
    "after report reflects the now-present jq"
rm -f "$INSTALL_BIN/jq"

rm -rf "$INSTALL_BIN" "$NO_BREW_BIN" "$INSTALL_CACHE_DIR"

# --- existing doctor behavior unchanged --------------------------------------
OUT=$(BREW_BOTTLE_CACHE_DIR="$CLI_CACHE_DIR" "$BREW_USAGE" doctor 2>/dev/null); RC=$?
assert_contains "$OUT" "Summary:" "plain doctor still prints a Summary line"
if [[ "$OUT" == *"Planned fixes"* ]]; then
    assert_equals "no plan section" "found one" "plain doctor has no fix plan section"
else
    assert_equals "yes" "yes" "plain doctor has no fix plan section"
fi

# --- display_help documents --fix, --yes and --install ------------------------
OUT=$("$BREW_USAGE" --help 2>/dev/null)
assert_contains "$OUT" "--fix" "display_help documents --fix"
assert_contains "$OUT" "--yes" "display_help documents --yes"
assert_contains "$OUT" "--install" "display_help documents --install"
assert_contains "$OUT" "composes with --json" \
    "display_help documents --fix composing with --json"
assert_contains "$OUT" "brew-usage --size go@1.21.13 # Pin an exact version (falls back from formula lookup)" \
    "display_help documents version pinning for --size"

rm -rf "$CLI_CACHE_DIR" "$CLI_CONFIG_DIR" "$CLI_CONFIG_CACHE"
rm -f "$CLI_ERR_FILE"

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
