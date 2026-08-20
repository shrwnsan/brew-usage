# PRD: Size History Snapshots (`--snapshot` / `--history`)

**Status:** ✅ Implemented (v0.11.0) — per the settled design below;
test-plan scenarios covered in tests/test-snapshot.sh (54 assertions)
**Created:** 2026-08-20
**Target release:** v0.11.0
**Predecessor:** PRD-007 (compare), tasks-009 Task 2
**Task file:** tasks-009-size-intelligence.md

## Summary

Historical size tracking: record what is installed and how much disk
it uses, then diff consecutive recordings — "what grew since last
time?". Completes tasks-009 (size intelligence).

## Settled design decisions (brainstorm gate 2026-08-20)

1. **Explicit `--snapshot`** — recording is opt-in; the tool stays
   read-only unless asked (no hidden writes on report runs).
2. **Append log** — `~/.brew-usage/history/snapshots.jsonl`, one JSON
   line per snapshot; diff = last two lines. Count-capped: the last 90
   snapshots are kept (a tool about disk waste must not itself grow
   unbounded). The cap is a documented constant, not a config key
   (adding keys touches the loader whitelist + doctor checks; revisit
   if asked).
3. **du-based sizes** — snapshots record actual on-disk usage (the
   report's scan machinery: `brew list` names → Cellar/Caskroom du),
   not manifest estimates; growth tracking is about real disk. A
   package with both a formula and a cask of the same name sums both.
4. **Local-only** — history never leaves the machine; no telemetry.

## Scope

### New flags (both standalone modes, like `--flush-cache`)

- `brew-usage --snapshot` — scan installed formulae + casks, record
  `{timestamp, package_count, total_bytes, packages:{name:bytes}}` as
  one JSONL line, prune to the last 90, print a confirmation. Needs
  brew and jq. Exit 0 recorded, 1 scan/write failure.
- `brew-usage --history` — diff the two most recent snapshots: old/new
  summaries, then top movers by absolute delta (grew, shrank, added,
  removed), capped at `TOP_N`. Needs jq, not brew. Exit 0 rendered,
  1 fewer than two snapshots / unreadable history.

### Flag interactions

- `--snapshot` and `--history` conflict with every other mode flag and
  with each other (standalone modes; order-independent)
- `--history --json` composes: one JSON document on stdout
  (`{old, new, changes:[{name, from, to, delta, change}]}`); human
  lines never on stdout in JSON mode
- `--snapshot --json` composes the same way (the recorded line,
  pretty-printed, is the document) — stdout stays pure JSON

### Storage details

- Path overridable via `BREW_USAGE_HISTORY_FILE` (tests, alternate
  layouts); default `${HOME}/.brew-usage/history/snapshots.jsonl`
- Directory created on first snapshot (0700, mirroring the cache dir)
- Append failure → exit 1, no partial state
- Prune: when line count exceeds 90, rewrite keeping the newest 90 via
  mktemp + atomic mv (same discipline as the config-tier writes)
- Malformed lines (future/corrupt): the reader tolerates a trailing
  malformed line by erroring clearly rather than silently miscounting

### Rendering (human)

```
Size History — last two snapshots
Old: 2026-08-01T10:00:00+08:00   312 packages   4.2 GiB
New: 2026-08-20T16:12:03+08:00   318 packages   4.4 GiB (+210 MiB)

Top changes (by absolute delta):
  go               +92.8 KiB    218.1 MiB -> 218.2 MiB
  docker          -300.0 MiB     2.1 GiB  -> 1.8 GiB
  wget (new)       +4.5 MiB             0 B -> 4.5 MiB
  python@3.12 (removed)         96.0 MiB -> 0 B
```

`change`: `grew` | `shrank` | `added` | `removed`. Zero-delta packages
are omitted (nothing changed).

## Out of scope

- Trend lines over N>2 snapshots, growth-rate math, `--history --since`
  date selection (the JSONL is the data; a future flag can select)
- Automatic/cron snapshots, launchd agents
- Configurable retention cap
- Snapshotting manifest/download sizes

## Test plan

1. `write_snapshot` against a fixture prefix (mocked brew `list`
   --formula/--cask + `--prefix`): recorded line has correct
   package_count, total_bytes, per-package du bytes; dir 0700; second
   snapshot appends
2. Prune: seed 90+ lines, snapshot, exactly 90 newest remain, ordering
   preserved, atomic (no droppings)
3. `--history` from seeded lines: summary lines, top movers sorted by
   |delta|, grew/shrank/added/removed tags, TOP_N cap
4. Edge: <2 snapshots → exit 1 with message; unreadable file → exit 1;
   both scans failing → exit 1
5. CLI: `--snapshot`/`--history` conflict with report flags and each
   other (both orders); `--history --json` single document, pure
   stdout; `--snapshot --json` echoes the entry
6. display_help documents both flags
