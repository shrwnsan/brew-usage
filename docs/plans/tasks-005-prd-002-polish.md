# Tasks: Size-lookup polish — --quiet and --flush-cache (v0.6.1)

**PRD:** [prd-002-package-size-lookup.md](prd-002-package-size-lookup.md) (§Future Enhancements)
**Created:** 2026-08-19
**Target Version:** 0.6.1
**Branch:** `feat/v0.6.1-quiet-flush`

---

## Ground Rules (binding, as ever)

No ✅ while stubs remain; shellcheck warning-clean; syntax-check clean; bash 3.2
compatible; Conventional Commits with GLM trailer; CI green (4 jobs) before merge.

## Task 1: `--quiet` — single-value output for scripting

**Files:** `brew-usage`, `lib/brew-usage-display.sh` (or size display), tests
**Design (settled):**
- `--quiet FIELD` where FIELD ∈ `download` | `installed` (REQUIRED value; unknown →
  error exit 1) — e.g. `brew-usage --size go --quiet installed` → `193.9 MiB`
- Only valid in size mode (`--quiet` without `--size` → error exit 1); mutually
  exclusive with `--json` (both orders, exit 1); joins the existing conflict chains
- Output: one line per package, value only (`jq`-style consumers get clean values);
  failed/not-found packages print nothing on stdout — their story stays on stderr
  and in exit codes (0/2/1 semantics unchanged)
- No color ever (implies --no-color)
- Tests: single package value line; multiple packages one line each in order;
  mixed run → good value on stdout, exit 2; `--quiet` without `--size` → exit 1;
  `--quiet download --json` → exit 1 both orders; unknown field → exit 1

## Task 2: `--flush-cache` — force-refresh manifest cache

**Files:** `brew-usage`, `lib/brew-usage-size.sh`, tests
**Design (settled):**
- `--flush-cache` (standalone mode, like doctor): removes ONLY brew-usage's own
  manifest cache files (glob `*--*--*.json` in `$BREW_BOTTLE_CACHE_DIR`) — NEVER
  Homebrew's `*bottle_manifest.json` originals or anything else in that directory
- Prints `<n> cached manifest(s) removed` (0 is fine), exit 0
- Mutually exclusive with every mode flag (all chains, both orders)
- Mutation is scoped to files we created — acceptable by design (our cache, our
  cleanup), documented in help
- Doctor synergy: update `ttl-sane`/`manifest-cache` suggestion to mention
  `brew-usage --flush-cache` where expired manifests exist
- Tests: fixture cache dir with our files + decoys (`bottle_manifest.json` original,
  `.txt`) → only ours removed, decoys untouched, correct count; empty cache → 0
  removed, exit 0; conflicts both orders → exit 1
  (BREW_BOTTLE_CACHE_DIR is readonly-once — use the subshell export-before-source
  pattern from tests/test-doctor.sh)

## Task 3: Release prep

- CHANGELOG `[0.6.1]`, version bump, stats table, README + help updates
- PRD-002: move `--quiet` and `--flush-cache` from Future Enhancements to delivered
- Full battery bash5+3.2, CI 4 jobs green, merge; post-merge (user consent):
  tag v0.6.1 + tap bump
