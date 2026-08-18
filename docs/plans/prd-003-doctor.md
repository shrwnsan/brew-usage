# PRD 003: brew-usage doctor

**Created:** 2026-08-19
**Last Updated:** 2026-08-19
**Version:** 0.6.0 (target)
**Status:** Approved design, pending implementation

## Overview

`brew-usage doctor` is a diagnostics mode that verifies the tool's operating
environment and surfaces problems before they become confusing failures. It follows
the `brew doctor` contract: **diagnose and suggest, never mutate**. Every problem
comes with the exact command to run; the tool itself changes nothing.

## Problem Statement

brew-usage now has real environmental surface area: optional `jq`, an optional strict
config file, a manifest cache with TTL, platform-specific `stat`, and ghcr.io network
dependence for `--size`. When something in that stack is off (jq missing, config
malformed, cache dir unwritable, offline), features degrade to warnings — as designed
— but users have no single command that answers "is my setup healthy, and if not,
what do I fix?".

## Scope

### In Scope
- `doctor` / `-d` / `--doctor` subcommand-style flag
- Four check groups (environment/deps, config health, cache & manifests, brew
  surfaces & network), detailed below
- Human-readable report + `--json` output
- Exit codes signalling overall health
- Suggestions = printed commands only (never executed)

### Out of Scope (v1)
- `--fix` or any repair action (separate PRD if ever)
- brew-change integration
- Homebrew installation repair (that's `brew doctor`'s job)

## Command Interface

```
brew-usage doctor          # run all checks
brew-usage doctor --json   # machine-readable
brew-usage -d --no-color   # aliases work, color respects --no-color/tty
```

Mutually exclusive with all mode flags (`--top`, `--formulae`, `--casks`, `--sort`,
`--all`, `-C`, `--size`) — order-independent per the `*_FLAG_PASSED` pattern.
Composes with `--json` and `--no-color` only.

## Checks

Each check: `name`, `group`, verdict (`pass` | `warn` | `fail`), one-line `detail`,
optional `suggestion` (exact command string).

### Group: environment
| Check | Verdict rules |
|---|---|
| `brew-present` | fail if `command -v brew` empty |
| `brew-prefix` | fail if `brew --prefix` empty or non-directory; detail includes prefix |
| `jq-present` | warn if missing (detail: required for `--size`/`--json`; suggest `brew install jq`) |
| `bash-version` | pass; detail notes version (3.2 supported, 4+ noted) |

### Group: config
| Check | Verdict rules |
|---|---|
| `config-present` | pass with "no config file (defaults)" or detail of path |
| `config-valid` | warn if malformed lines found (detail: count + first file:line) |
| `config-effective` | pass; detail: `TOP_N=<n> thresholds=<w>/<c> CACHE_CLEANUP_DAYS=<d>` (effective values after config merge) |

### Group: cache
| Check | Verdict rules |
|---|---|
| `cache-dir` | warn if missing/unreadable; fail if brew cache resolves but is not a directory |
| `manifest-cache` | pass; detail: `<n> manifests, <m> expired by TTL` |
| `ttl-sane` | warn if `CACHE_CLEANUP_DAYS` > 30 (stale cleanup suggestions); the manifest TTL (3600s) is a readonly constant, not configurable, so is not checked |

### Group: brew surfaces
| Check | Verdict rules |
|---|---|
| `scan-formulae` | fail if `brew list --formula` errors |
| `scan-casks` | warn if `brew list --cask` errors (cask-less Linux) |
| `cellar-caskroom` | warn per missing dir (with paths); fail if both missing |
| `ghcr-reachable` | warn if token endpoint unreachable (detail: `--size` downloads degraded; check network) |

## Output

### Human (default)
```
brew-usage doctor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment
  ✓ brew-present       Homebrew 4.x at /opt/homebrew
  ✓ brew-prefix        /opt/homebrew
  ✓ jq-present         jq 1.8.2
  ✓ bash-version       5.2 (3.2+ supported)
Config
  ✓ config-present     using ~/.brew-usage-config
  ...
Summary: 12 passed, 2 warnings, 0 failures
Suggested fixes:
  • brew install jq
```
Verdict coloring: ✓ green, ⚠ yellow, ✗ red (respects `--no-color`/non-tty).

### JSON (--json)
```json
{
  "checks": [
    {"name": "brew-present", "group": "environment", "verdict": "pass",
     "detail": "Homebrew 4.6 at /opt/homebrew"}
  ],
  "summary": {"pass": 12, "warn": 2, "fail": 0}
}
```
Valid JSON on stdout regardless of verdicts; all diagnostics-adjacent output to stderr.

## Exit Codes
- `0` — all pass (warnings permitted)
- `2` — ≥1 warn, 0 fail
- `1` — ≥1 fail, or invalid arguments

(Consistent with `--size` semantics: 2 = "usable but attention needed".)

## Architecture

- New module `lib/brew-usage-doctor.sh`, following module conventions (header
  comments, `BREW_USAGE_DOCTOR_LOADED` guard, sources config+utils via existing
  guards)
- Check registry: indexed array of `check_fn` names iterated by `doctor_run_all()`;
  each `doctor_check_<name>()` sets `VERDICT`, `DETAIL`, optional `SUGGESTION` via a
  shared `doctor_result <verdict> <detail> [suggestion]` helper (globals, matching
  codebase idiom)
- Display via `lib/brew-usage-display.sh` additions; JSON via `lib/brew-usage-json.sh`
  additions — both follow existing section/block patterns
- Entry point: `DOCTOR_MODE` parsing + post-parse mutual-exclusivity chain +
  `doctor`/`-d`/`--doctor` aliases; runs before report generation
- bash 3.2 compatible throughout (no assoc arrays; guarded `"${arr[@]}"`)

## Testing

- **Unit** (`tests/test-doctor.sh`): each check with fixture/env overrides
  (`BREW_USAGE_CONFIG_FILE` malformed file → config-valid warn;
  `BREW_USAGE_CACHE_ANALYSIS_DIR` fixture with known mtimes → manifest-cache detail;
  jq hidden via PATH manipulation → jq-present warn)
- **Integration**: healthy machine → exit 0, no ✗; `--json` parses with summary
  counts matching human output; `doctor --top 5` → exit 1 both orders; PATH-broken
  brew → brew-present fail + exit 1
- Wired into CI: the ubuntu unit job runs only the fixture-driven unit checks
  (brew-independent); full CLI doctor integration runs in the macOS and Linux
  integration jobs (brew required), following the existing suite guard convention

## Success Criteria
1. One command answers "is my setup healthy" across all four groups
2. Zero mutations — read-only, ever
3. Exit codes scriptable; JSON composable
4. All suites green on macOS (bash 5 + 3.2), Linux CI, shellcheck clean
5. Follows existing code/style/module patterns; no new dependencies

## Future Enhancements (out of scope)
- `--fix` flag with a repair-safety taxonomy
- brew-change cross-checks (e.g., recently-changed packages vs. cache staleness)
- Doctor hooks for plugin/extension checks
