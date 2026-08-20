# Tasks: doctor --fix remaining tiers + doctor hooks

**Status:** Task 1 (system installs tier) done in v0.9.0 (PRD-006);
Task 2 (plugin hooks) parked pending its own gate round.
**Created:** 2026-08-20
**Predecessor:** PRD-004/PRD-005 (fix framework, tiers `safe` + `config`)

# Scope

The two deliberately deferred `doctor --fix` tiers plus the doctor plugin
hook idea (PRD-003 §Future). The gate below was resolved 2026-08-20.

## Task 0: Brainstorm gate (resolved 2026-08-20)

1. **System installs tier** — settled:
   - Triple-flag opt-in: planned in dry-run output, applied only under
     `--fix --yes --install`. Plain `--fix --yes` never installs.
   - jq-only allowlist at first; the registry stays the extension point.
   - Brew itself broken → `install-jq` not even due (`brew-present`
     already fails with guidance); apply fn refuses defensively too.
2. **Confirm-gated tier** — **dropped.** No concrete need surfaced;
     the triple-flag opt-in covers the safety concern without
     contradicting the no-prompts scripting model.
3. **Doctor plugin hooks** — still parked (no gate round yet; open
   questions below).

Open questions remaining for Task 2 only:

- Registration surface: a directory of executable scripts
  (~/.brew-usage-doctor.d/)? A config key?
- Contract: exit 0/2/1 + one-line stdout, mapped into the report as a
  new group; timeouts enforced (a hung plugin must not hang doctor).
- Security: scripts are EXECUTED, never sourced; documented loudly.

## Task 1: System installs tier (v0.9.0, PRD-006 — done)

- [x] PRD section (PRD-006: own-state rule amendment — installs are the
      explicit exception, gated by `--install`)
- [x] Registry entry `install-jq|jq-present|install|install_jq`; apply fn
      wraps `brew install jq` with output capture; failure → apply
      FAILED, no partial state; skip (not fail) when `--install` absent
- [x] `doctor --fix --json` composition unchanged (statuses flow
      through; results gain `"skipped"`)
- [x] Tests: jq absent fixture (PATH manipulation), install success/failure
      mocks, after-report jq-present pass (29 new assertions, 148 total)

## Task 2: Doctor plugin hooks (parked)

- [ ] Discovery + contract per a future gate; hung-plugin timeout
- [ ] Report integration (group + verdicts); `--json` includes plugin
      checks; exit code aggregation
- [ ] Tests: passing/warning/failing/hanging plugin fixtures

## Dependency graph

Task 0 (done) → Task 1 (v0.9.0); Task 2 parked independently
