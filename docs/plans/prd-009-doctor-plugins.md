# PRD: Doctor Plugin Hooks (`~/.brew-usage-doctor.d/`)

**Status:** ✅ Implemented
**Created:** 2026-08-21
**Target release:** v0.12.0
**Predecessor:** PRD-003 (doctor), tasks-008 Task 2
**Task file:** tasks-011-doctor-plugin-hooks.md

## Summary

User-supplied extra doctor checks: executable scripts in a directory
become first-class checks rendered in a `plugins` group, with a
timeout so a hung plugin can never hang doctor.

## Settled design decisions (gate round 2026-08-21)

Settled by best judgment under the user's standing "proceed with
remaining backlog" authorization (no answers in the gate round; the
recommended options were taken):

1. **Registration = executable directory.**
   `~/.brew-usage-doctor.d/` by default; `BREW_USAGE_DOCTOR_DIR`
   overrides (tests, alternate layouts). Creating the dir is the
   opt-in — no config keys, no whitelisting changes. Only regular
   files with the executable bit run; everything else is skipped
   silently.
2. **Verdicts aggregate into the exit code.** Plugin pass/warn/fail
   counts in the summary and the 0/2/1 exit code, like built-in
   checks — one exit code tells the whole story. Report-only was
   rejected: a genuinely broken environment would report 0.
3. **Contract is exit-code + first stdout line.** No args, no stdin;
   exit 0 = pass, 2 = warn, 1 = fail; any other exit code = fail
   ("exit code N"); first stdout line is the detail (empty stdout is
   fine — generic detail). Scripts are EXECUTED, never sourced —
   documented loudly.
4. **5-second timeout, bash-3.2-safe.** Background pid + 1s poll loop
   ×5 + kill. A timed-out plugin records fail ("timed out after 5s")
   and doctor continues.
5. **No plugin fixes.** `doctor --fix` never runs plugin code — the
   fix registry is untouched; plugins are read-only checks.

## Scope

### Discovery and execution

- Directory scanned after the static check registry, files sorted by
  name (deterministic report order)
- Check name = filename; group = `plugins` (rendered last)
- `doctor_check_group`/`doctor_check_name` stay keyed to static
  checks; plugin entries are appended to the same result arrays the
  renderers already consume (JSON inclusion falls out for free)
- Missing/empty dir → no group, nothing appended, exit semantics
  unchanged (a non-event)

### Report integration

- Human report: `plugins` group section after `brew surfaces`
- `doctor --json`: plugin entries appear in `checks` with
  `"group": "plugins"`; summary counts include them
- Exit codes: unchanged rules (0 pass / 2 warn / 1 fail) over the
  combined verdict set

### Timeout implementation (portable)

```
run plugin with stdout captured to a temp file, backgrounded
poll kill -0 up to 5 × sleep 1
still alive → kill (TERM, then KILL if needed), verdict fail,
detail "timed out after 5s"
```

Temp files cleaned up on all paths (errexit-safe).

## Out of scope

- Plugin arguments, per-plugin timeout configuration
- A `--no-plugins` flag (empty/renamed dir achieves it; add if asked)
- Plugin-driven fixes, plugin stdout beyond the first line
- Windows/WSL-specific plugin handling

## Test plan

1. Missing dir → no plugins group, counts unchanged
2. Passing plugin (exit 0 + stdout detail) → pass entry in group,
   exit 0
3. Warn plugin (exit 2) → warn entry, doctor exit 2
4. Fail plugin (exit 1) → fail entry, doctor exit 1
5. Weird exit code (3) → fail entry naming the code
6. Hanging plugin (`sleep 30`) → fail "timed out after 5s", suite
   time budget ~5s
7. Non-executable file in the dir → skipped silently
8. Empty-stdout plugin → generic detail, verdict from exit code
9. Multiple plugins → sorted by filename
10. `--json` includes plugin checks; summary counts reconcile
11. Plugins render after brew surfaces in the human report
