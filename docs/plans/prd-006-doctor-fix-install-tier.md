# PRD: Doctor Fix Install Tier (`doctor --fix --yes --install`)

**Status:** ✅ Implemented (v0.9.0) — per the settled design below; all
seven test-plan scenarios covered in tests/test-doctor-fix.sh
**Created:** 2026-08-20
**Target release:** v0.9.0
**Predecessor:** PRD-004 (fix framework, v0.7.0), PRD-005 (config tier, v0.8.0)
**Task file:** tasks-008-doctor-fix-remaining-tiers.md

## Summary

The third `doctor --fix` tier: system installs. When the `jq-present`
check fails (jq missing, which blocks `--size` and `--json`), doctor can
install jq via Homebrew — the one registry tier allowed to modify state
outside brew-usage's own files, gated behind an explicit third flag.

## Settled design decisions (brainstorm gate 2026-08-20, tasks-008 Task 0)

1. **Triple-flag opt-in.** Install-tier fixes are *planned* in dry-run
   output (discoverable) but *applied* only under
   `doctor --fix --yes --install`. Plain `--fix --yes` never installs
   software: existing scripted runs keep their exact behavior.
2. **jq-only allowlist.** The registry gains exactly one install entry
   (`install-jq`). Generalizing to a user-extensible install registry is
   a future decision, not shipped shape.
3. **Brew broken → refuse clearly.** When brew itself is not on PATH,
   `install-jq` is not even due (the `brew-present` check fails with its
   own guidance); `install_jq()` also refuses defensively if brew
   vanishes between plan and apply.
4. **Confirm-gated tier dropped.** The interactive y/N tier contradicts
   the settled no-prompts scripting model (PRD-004 gate) and the
   triple-flag opt-in covers the safety concern it existed for.
   Removed from the backlog.

## Scope

### New flag

- `--install` — valid only together with `--fix --yes`. Permits
  install-tier apply functions to run. Order-independent like `--yes`.

### Flag interactions

- `--install` without `--fix` → exit 1, error (same pattern as `--yes`)
- `--install` with `--fix` but without `--yes` → exit 1, error
  (dry runs apply nothing; `--install` would be a no-op — refuse it so
  the flag surface stays honest)
- `--install` composes with `--json` exactly as `--yes` does

### Fix registry addition

| Fix id | Source check | Tier | Action |
|---|---|---|---|
| `install-jq` | `jq-present` | install | `brew install jq`, then verify jq is usable on PATH |

Due when jq is absent **and** brew is on PATH. When brew is also
missing, the fix is not due — `brew-present` already fails with install
guidance, and offering `brew install` without brew is noise.

### Dry run (`doctor --fix`)

The install fix appears in the plan like any other tier, with its
description naming the extra flag:

```
Planned fixes (dry run — nothing applied):
  install-jq  [jq-present]
    Install jq via Homebrew (--json/--size need it; apply needs --install)

1 fix planned. Re-run with --yes to apply.
Note: install-tier fixes apply only with --yes --install.
```

### Apply without consent (`doctor --fix --yes`, no `--install`)

Install-tier due fixes are skipped, not failed — the pass still applies
safe/config fixes:

```
skipped: install-jq — install tier needs --yes --install
```

Skipped fixes do not count as applied (no after-report re-run from
them) and appear in the JSON results with `"status": "skipped"`.

### Apply with consent (`doctor --fix --yes --install`)

`install_jq()`:

1. Refuse (apply FAILED) if brew is not on PATH.
2. Run `brew install jq` with combined output captured (brew is chatty;
   output goes to the result line only on failure).
3. Verify `jq --version` works in the current shell. Success → the
   version is the result line. Failure → apply FAILED ("installed but
   not usable on PATH — check PATH / open a new shell").
4. After-report re-run then shows `jq-present` passing (exit code
   improves from 2 to 0 when this was the only warning).

### JSON composition (unchanged shape, new status value)

- Plan entries already carry `tier`; `install` flows through.
- Result entries gain `"skipped"` alongside `"applied"|"failed"`.

### Exit codes

Unchanged: the doctor verdict after fixes (0/2/1). Install failures are
report-level FAILED lines, not process aborts.

## Out of scope

- Installing anything other than jq (allowlist stays closed)
- The confirm-gated (interactive y/N) tier — dropped per gate decision 4
- Doctor plugin hooks (tasks-008 Task 2, still parked)
- Repairing a broken brew installation (out of brew-usage's remit)

## Test plan

1. jq absent (PATH fixture), brew present: dry run plans `install-jq`
   with the `--install` note
2. jq absent, brew absent: `install-jq` NOT due (no plan entry)
3. `--fix --yes` without `--install`: skipped line, nothing installed,
   exit reflects the (still-warned) after verdict; JSON shows skipped
4. `--fix --yes --install` with mocked brew: applied line with version,
   after report shows jq-present pass; mock asserted to receive
   `install jq`
5. Failing brew mock: apply FAILED with captured output; no partial
   state
6. `--install` alone / with `--fix` only → exit 1 errors
7. jq present: `install-jq` never due (plan empty of it)
