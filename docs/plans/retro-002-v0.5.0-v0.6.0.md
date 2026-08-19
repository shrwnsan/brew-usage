# Retro: v0.5.0 + v0.5.1 + v0.5.2 + v0.6.0 — Quick Wins to Doctor

**Milestone:** v0.5.0–v0.6.0 (2026-08-19, PRs #9, #10, #12(security), #13; tap #26, #28, #30, #33)
**Period:** 2026-08-18 (v0.4.1) → 2026-08-19
**Inputs:** retro-001 carry-forwards, PR review trails, this stretch's session records

---

## Where we started

retro-001 closed the v0.3.0/v0.4.0 milestone with every process fix earned the hard
way, and left carry-forwards: exec-bit drift, the `--sort name` no-op, the unverified
Linux claim, and the bigger bets (#4). This stretch cleared all of them.

## What shipped

| Version | What |
|---|---|
| 0.5.0 | `--sort name` implemented (was a parsed no-op since v0.1.0); exec-bit CI gate |
| 0.5.1 | **Linux `--size` stat portability fix** (real bug); `integration-linux` CI job |
| 0.5.2 | Security hardening: `--size` input validation (name/version charset), jq `--arg` injection closure, escape-stripped config warnings |
| 0.6.0 | **`brew-usage doctor`** — 14 read-only checks, 4 groups, `--json`, exit 0/2/1, diagnose-and-suggest contract |

## What went right

1. **The verification ladder worked exactly as designed.** Linux recon (OrbStack amd64
   container → x86_64 Ubuntu 24.04 VM matching `ubuntu-latest`) found the GNU-stat
   bug locally, TDD'd the fix red→green on both platforms, and the new
   `integration-linux` job landed already-green. Push-and-watch became
   verify-then-push.
2. **Recon honesty paid twice.** The suspected `%n` stat bug was a false alarm —
   disproved empirically before changing code (evidence over assumption). And the
   real bug was in a *different* stat idiom nobody suspected. Prediction with stated
   odds (~70% one real bug) beat false certainty.
3. **Process immunity held.** Every retro-001 defense caught something this stretch:
   CI caught nothing *because* local verification preceded pushes; the exec-bit gate
   closed its drift class; user bug reports (`--all` pager) went
   systematic-debugging → root cause → TDD → release in one pass.
4. **Review discipline caught controller errors, not just implementer errors.** A fix
   agent rejected a wrong variable name in the controller's own instructions; the
   interrupted-dispatch residue was quarantined by an extra-suspicion spec review.
5. **The brainstorm gate earned its keep for doctor.** Two scope questions
   (diagnose-vs-fix, check-set) settled in minutes what would otherwise have been
   rework; PRD-003's one real ambiguity (13 vs 14 checks) was caught in review.

## What went wrong / to improve

1. **The interrupted T2 dispatch left orphaned staged work.** The re-run adopted it
   after line-by-line review, but the failure mode (half-finished agent state
   silently becoming someone else's starting point) is real. Countermeasure adopted:
   reviewers told explicitly when a commit may contain interrupted work; consider
   `git status` check before every implementer dispatch.
2. **Stale assumptions about remote state.** The tap was at 0.5.2 (bumped during the
   security merge), not 0.5.1 as assumed — first bump attempt was a no-op sed.
   Cheap fix: read the formula before editing it, always.
3. **PRD counting drift** ("13 checks" prose vs 14-row table) — caught in review but
   originated in the design doc. Rule: count table rows when writing the summary line.
4. **Session-start commit on main** (PRD-003) required a reconciliation reset.
   Benign, but branch-first habit would have avoided it entirely.

## Metrics

| | retro-001 close | now |
|---|---|---|
| CI jobs | 3 | 4 (lint, unit, macOS, Linux) |
| Test suites / assertions | 6 / ~105 | 7 / ~150 (doctor alone: 45) |
| Platform claims verified | macOS only | macOS + Linux, continuously |
| Known no-op flags | 1 (`--sort name`) | 0 |
| Open retro carry-forwards | 4 | 0 |
| Security posture | jq-injection surface | validated inputs, `--arg` everywhere, escape-stripping |

## Carry-forward

- [ ] None owed. Optional backlog lives in PRD-003 §Future Enhancements and the
      #2 list (`--flush-cache`, `--quiet`) — pull only with fresh tasks files.

## Verdict

The streak where "every claim is continuously verified" held across four releases,
two platforms, and one user-reported bug — with zero regressions shipped. The
process is now the boring kind of reliable, which is the goal.
