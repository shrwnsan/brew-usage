# Tasks: doctor --fix remaining tiers + doctor hooks (pre-PRD)

**Status:** Pre-PRD — Task 0 (brainstorm gate) is mandatory before any
implementation; the scope questions below settle the PRD.
**Created:** 2026-08-20
**Predecessor:** PRD-004/PRD-005 (fix framework, tiers `safe` + `config`)

# Scope

The two deliberately deferred `doctor --fix` tiers plus the doctor plugin
hook idea (PRD-003 §Future). Nothing here is settled design — each item
carries its open questions.

## Task 0: Brainstorm gate (blocking)

Settle these scope questions (1-2 AskUserQuestion rounds):

1. **System installs tier** (`brew install jq` when jq-present fails):
   - Is a silent `--yes` install ever acceptable, or does this tier
     require a distinct acknowledgment (e.g. `--fix --yes --install`
     opt-in) on top of --yes?
   - jq-only allowlist at first, or a general registry the user extends?
   - Behavior when brew itself is the broken check (jq can't install
     without brew; refuse with a clear message?)
2. **Confirm-gated tier** (interactive y/N per fix):
   - Contradicts the settled no-prompts scripting model (PRD-004 gate,
     2026-08-20). Is there a real use case that `--fix` dry-run + `--fix
     --yes` doesn't already cover?
   - If kept: TTY-only prompting, non-interactive fallback = skip +
     report, and it must never block piped/scripted runs.
   - Recommendation on record: drop this tier unless Task 0 finds a
     concrete need.
3. **Doctor plugin hooks** (user-supplied extra checks):
   - Registration surface: a directory of executable scripts
     (~/.brew-usage-doctor.d/)? A config key?
   - Contract: exit 0/2/1 + one-line stdout, mapped into the report as a
     new group; timeouts enforced (a hung plugin must not hang doctor).
   - Security: scripts are EXECUTED, never sourced; documented loudly.

## Task 1: System installs tier (after gate)

- [ ] PRD section (own-state rule amendment: installs are the explicit
      exception, gated how the gate decides)
- [ ] Registry entry `install-jq|jq-present|install|install_jq` (tier
      label per gate outcome), apply fn wraps `brew install jq` with
      output capture; failure → apply FAILED, no partial state
- [ ] `doctor --fix --json` composition unchanged (statuses flow through)
- [ ] Tests: jq absent fixture (PATH manipulation), install success/failure
      mocks, after-report jq-present pass

## Task 2: Doctor plugin hooks (after gate, if kept)

- [ ] Discovery + contract per gate outcome; hung-plugin timeout
- [ ] Report integration (group + verdicts); `--json` includes plugin
      checks; exit code aggregation
- [ ] Tests: passing/warning/failing/hanging plugin fixtures

## Dependency graph

Task 0 → (Task 1, Task 2 in either order; independent)
