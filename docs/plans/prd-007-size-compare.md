# PRD: Package Size Comparison (`--size --compare`)

**Status:** ✅ Implemented (v0.10.0) — per the settled design below;
test-plan scenarios covered in tests/test-size-compare.sh (51 assertions)
**Created:** 2026-08-20
**Target release:** v0.10.0
**Predecessor:** PRD-002 (size lookup), PRD-005 (version pinning)
**Task file:** tasks-009-size-intelligence.md

## Summary

The first size-intelligence feature: for each named package, show the
installed version's bottle size against the latest version's bottle
size and the delta — "what will upgrading this cost (or save) me on
disk?". Settled reading (a) of PRD-002's underspecified "comparison
view": installed vs latest-bottle per package. Side-by-side of two
named packages (b) and snapshot diffs (c) remain unimplemented.

## Settled design decisions (gate: priority round 2026-08-20)

1. **Reading (a)** — per-package installed-vs-latest disk delta. The
   user aligned on this reading when prioritizing tasks-009.
2. **Modifier on `--size`** — `--compare` takes the same package list
   (`brew-usage --size go node --compare`), mirroring `--quiet` as a
   size-mode modifier rather than a new mode.
3. **Installed sizes, not download sizes** — the delta is
   installed_size(latest) − installed_size(installed). Download sizes
   stay out of the compare output in v1 (the question is disk cost).
4. **Explicit package list only** — no "compare everything installed"
   mode in v1 (N network fetches; a future decision).
5. Historical tracking stays parked (tasks-009 Task 2 — storage
   design questions on record there).

## Scope

### Data sources per package

1. **Installed version** — `brew list --versions <name>`, last field
   (brew may list multiple; the last is the current link). Empty →
   package not installed locally.
2. **Latest version** — `brew info --json=v2 <name>`,
   `versions.stable` (+ `_revision` append), same extraction rules as
   `get_package_size`. Failure → not found (existing `--size` error
   path) when the package is not installed either; otherwise latest
   side is null and the status is `partial`.
3. **Both sizes** — the manifest machinery via a new
   `get_versioned_size(name, version)`: cache-first
   (`name--version--tag.json`), Homebrew downloads-cache fallback,
   ghcr fetch last — identical semantics to `get_package_size`'s
   pinned path but without re-running `brew info` (the caller already
   resolved both versions). Historical versions often resolve from
   Homebrew's own downloads cache (the installed bottle is usually
   still there); when neither cache holds them the side is null and
   the status is `partial` — honest, not an error.

### Output

Human (`display_size_comparison`), styled like the existing size
table:

```
Package Size Comparison (installed vs latest bottle)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Package              Installed             Latest                Delta
go                   1.25.5 (115 MiB)      1.26.6 (119 MiB)      +4 MiB
node                 20.11.1 (96 MiB)      22.9.0 (102 MiB)      +6 MiB
wget                 — not installed —     1.25.3 (4 MiB)        —
oldpkg               1.0 (12 MiB)          1.2 (14 MiB)          +2 MiB (partial: sizes estimated)
```

- Unavailable sides render `—`; `not installed` names the reason.
- Delta is signed (`+` grows on upgrade, `−` shrinks); green when the
  upgrade shrinks or holds, yellow when it grows; `—` when unknown.

JSON (`--size --compare --json`): same envelope as size mode
(`{"packages":[...]}`, `json_render_size_report`), entries:

```json
{
  "name": "go",
  "installed_version": "1.25.5",
  "installed_size": 115000000,
  "latest_version": "1.26.6",
  "latest_size": 119000000,
  "size_delta": 4000000,
  "status": "ok"
}
```

`status`: `ok` (both sides resolved) | `up_to_date` (versions equal)
| `partial` (a side or its size unresolved) | `not_installed`.
Unresolved fields are `null`. Not-found packages keep the existing
`not_found` entry shape adapted to compare fields, on stderr warnings
like size mode.

### Flag interactions

- `--compare` without `--size` → exit 1 (same pattern as `--quiet`)
- `--compare` + `--quiet` → exit 1 (mutually exclusive: `--quiet`
  prints one field per package; compare has no single-field reading)
- `--compare` + `--json` → composes
- jq requirement inherited from `--size` mode

### Exit codes

Size-mode semantics unchanged: 0 all resolved (any status incl.
`not_installed`/`partial` counts as resolved — the comparison itself
succeeded), 2 partial success (≥1 not_found + ≥1 resolved), 1 total
failure.

## Out of scope

- Download-size deltas, per-platform comparison
- Comparing all installed packages in one run
- Snapshot/historical tracking (tasks-009 Task 2)
- Actual on-disk (du) measurements — compare stays manifest-based,
  apples-to-apples with `--size`

## Test plan

1. `get_versioned_size`: seeded cache manifest → sizes + verbatim
   version; no manifest → exit 2; invalid version → exit 1 before
   any cache/URL touch
2. `get_package_comparison` (mocked brew: `ruby` tag,
   `list --versions`, `info --json=v2`; offline curl):
   both sides seeded → `ok` + correct delta arithmetic
   equal versions → `up_to_date`, delta 0
   `list` empty → `not_installed`, latest side still resolved
   installed manifest missing (only latest seeded) → `partial`, null
   installed_size, null delta
   `info` fails + not installed → exit 1 not-found
   `info` fails + installed → `partial` with null latest_version
   revision append `_1` on latest version
3. CLI: human table renders installed/latest/delta columns;
   `--json` envelope + entry fields; `--compare` without `--size`
   exits 1; `--compare --quiet` exits 1; exit code 2 mixed
   found/not-found
