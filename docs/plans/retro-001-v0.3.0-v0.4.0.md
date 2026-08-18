# Retro: v0.3.0 + v0.4.0 — From Review to Release

**Milestone:** v0.3.0 (2026-08-18, PR #5) + v0.4.0 (2026-08-18, PRs #6, #7)
**Period:** 2026-02-11 (v0.2.0) → 2026-08-18
**Inputs:** 2026-08-18 project review, tasks-002, tasks-003, PR #5/#6/#7 review trails

---

## Where we started

v0.2.0 (February) shipped `--size` marked "✅ Implemented" while its core promise —
size lookup *before* installation — didn't work: manifest download was a stub
(`"download not yet implemented"`), and the tasks file said ✅ anyway. A project review
on 2026-08-18 also found: exit-code spec violations, order-dependent argument parsing,
a test suite enshrining wrong behavior, 26 shellcheck warnings, stale docs in five
places, and zero CI despite tasks-001 promising it.

## What shipped

### v0.3.0 — fix pack (PR #5)
- ghcr.io manifest download (anonymous token + OCI GET, atomic cache writes,
  `@`-scoped formulae, `.all` bottle-tag fallback)
- PRD exit codes: 0 / 2-partial (behavior change) / 1, partial runs display results
- Order-independent mutual exclusivity
- First CI ever: lint (shellcheck + syntax + stub gate) / unit (ubuntu) /
  integration (macOS)
- Test-harness counter fix, shellcheck clean, doc staleness sweep

### v0.4.0 — PRD-001 Phase 2 (PR #6, #7)
- `--json` for report and size modes (stdout valid JSON even on partial failure)
- `-C/--cache` analysis with cleanup candidates (read-only)
- `-a/--all` with SIGPIPE-safe pager
- `~/.brew-usage-config` (strict regex parse, never sourced)
- **Critical:** report mode fixed for stock macOS bash 3.2 (broken since v0.1.0)

## What went right

1. **The spike pattern paid off twice.** The February spike validated the ghcr fetch
   method empirically before anyone wrote code; the August review re-verified it live
   (HTTP 200, correct annotations), which de-risked the v0.3.0 estimate to "afternoon,
   low end."
2. **CI-first was the single highest-leverage decision.** Every task passed spec +
   quality review locally — and CI still caught: (a) a bash 3.2 `set -u` empty-array
   crash, (b) the missing `.all` bottle-tag fallback (v0.3.0), and (c) ubuntu/no-brew
   suite failures (v0.4.0). None were reproducible on the dev machine.
3. **Subagent pipeline with two-stage review worked.** Fresh implementer per task,
   spec review (adversarial, "do not trust the report"), then quality review. Real
   findings at every stage: a dead function trimmed into a latent bug (caught), test
   isolation gaps vs a developer's real config (caught, repro'd, fixed), swallowed
   scan failures (caught).
4. **Honest checkboxes held.** tasks-002/tasks-003 were written with "no ✅ while a
   stub remains" and a CI grep gate enforcing it. The original sin of tasks-001
   (stub marked complete) did not recur.
5. **Spec-over-implementation discipline.** The exit-code conflict (PRD said 2, test
   asserted latch-at-1) was resolved by fixing the test to match the documented
   contract — the opposite of the v0.2.0 failure mode.
6. **Self-review caught the scariest bugs.** An 83 GB runaway temp file in the pager's
   first draft and a readonly-assignment crash never reached review.

## What went wrong / to improve

1. **Squash merges dropped exec bits on test scripts** (PR #6; CI stayed green because
   it invokes `bash tests/x.sh`). Fix landed in #7. Lesson: exec-bit drift is invisible
   to green CI — consider a `git ls-files -s tests/` mode check in the lint job.
2. **v0.2.0 shipped with a stub and checked boxes.** Root cause: no CI, no stub gate,
   and tests asserting observed behavior instead of spec. All three now have structural
   defenses; the habit is the last line.
3. **The oldest bug in the repo survived three versions.** Report mode needed bash 4
   (`declare -A`) on a tool whose primary audience is stock macOS. Nothing exercised
   report mode under `/bin/bash` until Phase 2's JSON tests forced the question.
   Ground rule now written into tasks-003: everything runs under 3.2.
4. **Docs rotted between releases.** Five stale claims (nonexistent `brew --bottle-tag`,
   "Top N not implemented", `-f`/`-c` "Partial") were only found by the review.
   Countermeasure adopted: PRD "Last Updated" + status bumped every release; the
   tasks-005-style doc sweep is now a standing release-prep task.
5. **Direct push discipline.** During cleanup, one `git reset --hard origin/main` was
   used to reconcile main after a squash merge (no work lost — content was identical
   to the merged PR). Should have been `git fetch + merge --ff-only` or a fresh
   checkout; noted here for the record.

## Metrics

| | v0.2.0 → review | After v0.4.0 |
|---|---|---|
| CI | none | 3 jobs, green on main |
| Tests | 2 suites, ~23 tests, counter bug | 6 suites, 105+ tests, bash 5 + 3.2 |
| shellcheck (warning) | 26 findings | 0 |
| Stubs in lib/ | 1 (download) | 0 (CI-gated) |
| bash 3.2 | report mode broken | everything green |
| Docs claims verified | 5 stale | swept, release-task standing |
| PRs merged this stretch | — | #5, #6, #7 (+ homebrew-tap #20) |

## Carry-forward

- [ ] Lint job: exec-bit check on tests/ (from #1 above)
- [ ] `--sort name` still a parsed no-op (documented; oldest remaining known gap)
- [ ] PRD-002 future enhancements remain open (version-specific lookup, --flush-cache,
      --quiet) — pick up only with a fresh tasks file
- [ ] Consider `retro-` cadence: one per release stretch, not per release

## Verdict

The process changes made after the v0.2.0 review — spike before code, CI before trust,
spec over implementation, honest checkboxes — each caught at least one real bug this
stretch that the old process had already proven it misses. Ship small, verify hard.
