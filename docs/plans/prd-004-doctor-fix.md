# PRD: Doctor Repair Actions (`doctor --fix`)

**Status:** ✅ Implemented (v0.7.0) — fix framework + `flush-expired-manifests`,
per the settled design below
**Created:** 2026-08-20
**Completed:** 2026-08-20 (v0.7.0)
**Target release:** v0.7.0
**Predecessor:** PRD-003 (brew-usage doctor, v0.6.0)

## Summary

`brew-usage doctor --fix` plans and applies repairs for fixable doctor
findings. v0.7.0 ships the fix framework with one fix in the registry;
config repairs and system installs are explicitly out of scope (they were
declined at the brainstorm gate for this release and remain future tiers).

## Settled design decisions (brainstorm gate 2026-08-20)

1. **Dry-run default.** `doctor --fix` prints the plan and applies nothing.
   `doctor --fix --yes` executes the safe-tier fixes. No interactive
   prompts — scriptable, consistent with `--quiet` style.
2. **Own-state only.** Fixes may only touch brew-usage-owned state. No user
   config edits, no package installs, no Homebrew-owned directories.

## Scope

### New flags

- `--fix` — valid only in doctor mode (`doctor --fix`). After the normal
  report, prints a "Planned fixes" section and applies nothing.
- `--yes` — valid only together with `--fix`. Applies every planned fix,
  then re-runs the full doctor pass and prints the after report.

### Flag interactions (order-independent, mirroring existing conventions)

- `--fix` without doctor mode → exit 1, error (same pattern as `--quiet`
  requiring `--size`)
- `--yes` without `--fix` → exit 1, error
- `--fix` + `--json` → exit 1, error (JSON fix plan is a future tier)
- `--fix` composes with `--no-color`; it conflicts with every non-doctor
  mode flag, exactly like bare doctor mode

### Fix registry

A registry maps fixable findings to repairs, each carrying: fix id, source
check id, safety tier (`safe` in v0.7.0), description, and an apply
function. The registry is the extension point for future tiers.

| Fix id | Source check | Tier | Action |
|---|---|---|---|
| `flush-expired-manifests` | `manifest-cache` | safe | Remove only brew-usage-owned manifest cache files (`*--*--*.json`) whose TTL expired |

`flush-expired-manifests` is deliberately surgical: unlike `--flush-cache`
(which drops all our manifests), it removes only files failing
`is_cache_valid`. New function `flush_expired_manifests()` in
lib/brew-usage-size.sh, sibling of `flush_manifest_cache()`.

### Dry-run output (doctor --fix)

After the normal doctor report:

```
Planned fixes (dry run — nothing applied):
  flush-expired-manifests  [manifest-cache]
    Remove 2 expired manifest cache file(s) (brew-usage-owned only)

1 fix planned. Re-run with --yes to apply.
```

Zero fixable findings → "No fixes available (findings are report-only)".

### Apply output (doctor --fix --yes)

Apply each planned fix, print one line per fix (`applied:
flush-expired-manifests — 2 expired manifest(s) removed`), then re-run the
full doctor pass and print the after report. Final exit code is the
after-report verdict (0/2/1, unchanged semantics).

### Exit codes

Unchanged: 0 healthy, 2 warnings, 1 failures (verdict of the final doctor
pass shown). Invalid flag combos exit 1.

## Out of scope (future tiers, in likely order)

- Config repairs (comment out malformed lines, clamp out-of-range TTL)
- System installs (`brew install jq`)
- JSON fix plan (`doctor --fix --json`)
- Confirm-gated tier (interactive y/N)

## Success criteria

1. `doctor --fix` never mutates anything; `--fix --yes` mutates only
   brew-usage-owned files matching the registry
2. Expired-manifest fix removes exactly the expired `*--*--*.json` files;
   Homebrew's `*bottle_manifest.json` originals and unexpired manifests
   untouched
3. Exit codes 0/2/1 and `--json` doctor behavior unchanged for existing
   invocations (no regression in tests/test-doctor.sh)
4. All suites green on macOS (bash 5 + 3.2), Linux CI, shellcheck clean,
   bash 3.2 compatible
5. display_help, README doctor section, CHANGELOG updated
