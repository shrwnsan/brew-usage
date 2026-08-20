# PRD: brew-change Cache-Staleness Cross-Check

**Status:** ✅ Implemented (v0.13.0) — per the settled design below;
test-plan scenarios covered in tests/test-doctor.sh (+6) and
tests/test-doctor-fix.sh (+10)
**Created:** 2026-08-21
**Target release:** v0.13.0
**Predecessor:** PRD-003/PRD-004 (doctor + fix framework), brew-change
tasks-005 (export surface, v1.16.0)
**Task file:** tasks-010-brew-change-integration.md

## Summary

The one settled brew-change cross-check (tasks-010 gate, 2026-08-21):
doctor warns when brew-change's export proves brew-usage's cached
manifests stale, and `doctor --fix --yes` removes exactly those files.

## Settled design decisions (gate round 2026-08-21)

Settled by best judgment under the user's standing "proceed with
remaining backlog" authorization (gate round unanswered; recommended
options taken):

1. **Cache staleness only.** The pending-upgrade-sizes cross-check was
   declined — v0.10.0's `--size --compare` already answers "what will
   this upgrade cost me on disk?" per package on demand.
2. **Read the versioned export file** (`~/.brew-change/last-assessment.json`,
   `BREW_CHANGE_EXPORT_FILE` overridable) — no shelling out to
   brew-change, no runtime coupling to its CLI/version/performance.
3. **Failure posture: unavailable ≠ warn.** brew-change absent, no
   export yet, unreadable file, unsupported `schema_version`, or jq
   missing → the check PASSES with a non-event detail. The cross-check
   decorates doctor; it must never fail because another tool is
   absent, unrun, or newer than we understand.

## Semantics

- Export lists packages brew-change assessed (they changed upstream);
  each carries `name` and `available_version` (what was current at
  assessment time)
- A brew-usage-owned manifest `name--version--tag.json` is stale when
  its version differs from the export's `available_version` for that
  name — it describes a pre-change lookup
- New check `brew-change-stale` (group: cache, after ttl-sane):
  stale > 0 → warn with counts + `doctor --fix` suggestion; else pass
- New fix registry entry `flush-stale-manifests|brew-change-stale|safe|flush_stale_manifests`
  (tier safe: removes only brew-usage-owned files; fresh-version
  files, other names, and Homebrew's originals untouched)

## Out of scope

- Upgrade-size cross-checks (covered by `--size --compare`)
- Writing anything back to brew-change state
- Trend data from multiple exports (single last-assessment only)

## Test plan

1. Check unit: no export file → pass non-event; unsupported
   schema_version → pass non-event; export with stale manifests → warn
   with counts; all-fresh → pass with tracked count
2. Counting unit: stale counted only for changed names with differing
   versions; same-version files and other names not counted;
   null available_version never marks stale
3. Fix unit: dry run plans the removal with the count; `--yes` removes
   exactly the stale files (fresh version files, other names, and the
   Homebrew decoy survive); nothing due without a usable export
4. Registry assertions updated (15 checks; 5 fix entries)
5. CLI: end-to-end doctor --fix with fixture export + cache
