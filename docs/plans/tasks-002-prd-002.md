# Tasks: Complete Size Lookup + Release Fixes (PRD-002)

**PRD:** [prd-002-package-size-lookup.md](prd-002-package-size-lookup.md)
**Created:** 2026-08-18
**Target Version:** 0.3.0
**Branch:** `feat/v0.3.0-size-fix-pack`

---

## Background

v0.2.0 shipped `--size` reading only manifests already present in Homebrew's local
download cache. The PRD's core use case — size lookup **before** installation — does not
work: any package whose bottle has never been downloaded on this machine fails with
"download not yet implemented" (`lib/brew-usage-size.sh:197`). Additionally, a project
review (2026-08-18) found exit-code, argument-parsing, test, and documentation defects
detailed below.

## Verified Facts (2026-08-18)

1. **Anonymous ghcr.io manifest fetch works** (empirically tested):
   ```bash
   TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:homebrew/core/<pkg>:pull" | jq -r .token)
   curl -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/homebrew/core/<pkg>/manifests/<version>"
   # e.g. go 1.25.7_1 → HTTP 200 with sh.brew.bottle.size / installed_size annotations
   ```
   Response has the same OCI shape as locally cached manifests. No new dependencies
   beyond `curl` + `jq`.

2. **Partial-success bug:** `size_json=$(get_package_size "$pkg")` in `brew-usage`
   aborts under `set -e` on a failing package before results are displayed — mixed runs
   discard successful results and violate PRD edge case 7.

3. **Mutual exclusivity is order-dependent:** checks at `brew-usage:100-113` only catch
   `--top/--formulae/--casks/--sort` when they appear *before* `--size`;
   `brew-usage --size go --top 10` silently ignores `--top`.

4. **Exit-code spec conflict:** PRD says `0`=all ok, `1`=total failure, `2`=partial with
   usable results. `tests/test-size-lookup.sh:131` asserts latch-at-1 instead.
   **Decision:** adopt PRD semantics; fix the test, not the spec.

5. **Test framework defects:** counter drift (summary "Tests run: 14 / Passed: 15"),
   duplicated nested `if` block at `tests/test-size.sh:125-139`.

6. **shellcheck:** 26 warnings — 21× SC2034 (unused `DEFAULT_*` readonlys in config),
   5× SC2155 (declare+assign masking return codes).

7. **Doc staleness:** `CHANGELOG.md:16` credits nonexistent `brew --bottle-tag` (code
   uses `brew ruby`); `CHANGELOG.md:64` + `prd-001:317` claim Top N unimplemented (it is
   implemented); `prd-001:155-156` mark `-f`/`-c` "Partial" (they work); README
   architecture tree omits `tests/test-size-lookup.sh`; tasks-001 references
   `tests/test-utils.sh` which was created as `test-size.sh`.

8. **No CI exists** (`.github/workflows` absent) despite tasks-001 promising
   GitHub Actions verification for Linux compatibility.

---

## Task 1: Implement ghcr.io manifest download

**Files:** `lib/brew-usage-size.sh`
**Estimate:** 1–2 hours

Replace the stubbed branch in `fetch_bottle_manifest()` (line ~197) with a real
download path:

- [x] Fetch anonymous token: `https://ghcr.io/token?scope=repository:homebrew/core/<pkg>:pull`
- [x] GET `https://ghcr.io/v2/homebrew/core/<pkg>/manifests/<version>` with OCI Accept
      headers and bearer token
- [x] Handle HTTP failure / empty body / invalid JSON gracefully (non-zero return, no
      partial cache writes)
- [x] Validate downloaded JSON contains `.manifests[]` entries before caching
- [x] Write to the existing cache path (`get_manifest_cache_path`), preserving the
      current cache-first flow and 1-hour TTL
- [x] Token scope uses the formula name as-is (handles `node@20` etc. — verify path
      encoding for `@` if needed; document any caveat)
- [x] `curl` failure (offline) must degrade to the same "no bottle" outcome as today,
      with a clear warning
- [x] Keep existing Homebrew-cache reuse path (no behavior change when manifest is
      already local)
- [x] Add integration test: `--size <formula-never-cached>` succeeds after this change
      (pick a small formula; clear brew-usage's own cache copy first)

**Acceptance:**
- `brew-usage --size go` succeeds on a machine where go's manifest is absent from
  Homebrew's cache (verified live today: this machine is in that state)
- Second call within TTL hits our cache (no network) — verify with cache file mtime

## Task 2: Exit codes, partial success, mutual exclusivity

**Files:** `brew-usage`, `tests/test-size-lookup.sh`
**Estimate:** 1–2 hours

- [x] Capture `get_package_size` return codes safely (`size_json=$(...) || result_code=$?`
      or equivalent) so `set -e` cannot abort the per-package loop
- [x] Display all successful results and warnings, then exit `0` (all ok) / `2` (mixed —
      usable results with warnings or failures) / `1` (total failure or invalid args)
      per PRD §Exit Codes
- [x] Add a single post-parse validation block: `--size` combined with `--top`,
      `--formulae`, `--casks`, or `--sort` (any order) → error, exit 1
- [x] Remove the now-redundant inline checks at `brew-usage:100-113`
- [x] Update `tests/test-size-lookup.sh`:
  - [x] Mixed run (`--size <good> <nonexistent>`) asserts exit 2 **and** that the good
        package's output is present
  - [x] `--size go --top 10` (flag after `--size`) asserts exit 1
  - [x] All-failed run asserts exit 1

**Acceptance:**
- `./brew-usage --size jq nonexistent-x` → prints jq's results, exit 2
- `./brew-usage --size nonexistent-x` → exit 1
- `./brew-usage --size jq` → exit 0 (verified working today)
- `./brew-usage --size go --top 10` and `--top 10 --size go` both → exit 1

## Task 3: Test framework + shellcheck cleanup

**Files:** `tests/test-size.sh`, `lib/*.sh`, `brew-usage`
**Estimate:** 1 hour

- [x] Fix counter drift in `tests/test-size.sh` (manual `((TESTS_PASSED++))` blocks not
      incrementing `TESTS_RUN`; summary said 14 run / 15 passed)
- [x] Remove duplicated nested `if` block at `tests/test-size.sh:125-139`
- [x] Fix all 5 SC2155 warnings (declare and assign separately) — these mask return
      codes and interact dangerously with `set -e`
- [x] Address 21 SC2034 warnings: wire the `DEFAULT_*` constants up as actual defaults
      in argument parsing, or remove them — pick one, don't leave dead constants
- [x] `shellcheck --severity=warning brew-usage lib/*.sh tests/*.sh` exits clean
      (explicitly-waived directives acceptable with justification comments)

**Acceptance:**
- Both test suites report `Tests run == Tests passed count`, all passing
- shellcheck exits 0 at warning severity

## Task 4: CI workflow

**Files:** `.github/workflows/ci.yml` (new)
**Estimate:** 1 hour

- [x] Trigger: push + pull_request
- [x] Jobs:
  - [x] **lint** (ubuntu): `shellcheck` (warning severity) + `bash -n` via
        `scripts/syntax-check.sh` + stub gate: fail if
        `grep -rn "not yet implemented" lib/` matches
  - [x] **unit-tests** (ubuntu): run `tests/test-size.sh` (needs `jq` installed)
  - [x] **integration-macos** (macos-runner): install nothing (brew present), ensure
        `jq`, run `tests/test-size-lookup.sh`
- [x] Keep the workflow minimal — no matrix gymnastics, no caching complexity

**Acceptance:**
- Workflow green on the PR branch (this is the first CI the repo has ever had)

## Task 5: Documentation sweep + release prep

**Files:** `CHANGELOG.md`, `README.md`, `docs/plans/prd-001-brew-usage.md`,
`docs/plans/prd-002-package-size-lookup.md`, `lib/brew-usage-config.sh`
**Estimate:** 1 hour

- [x] `CHANGELOG.md:16`: correct `brew --bottle-tag` claim → `brew ruby` (SimulateSystem)
- [x] `CHANGELOG.md:64` + `prd-001:317`: Top N filtering **is** implemented since v0.1.0
- [x] `prd-001:155-156`: `-f`/`-c` status → Implemented
- [x] README architecture tree: add `tests/test-size-lookup.sh`; note new CI
- [x] tasks-001 Task 4.3: correct filename reference (`test-utils.sh` → `test-size.sh`)
- [x] Add `CHANGELOG.md` `[0.3.0]` entry: ghcr download, exit-code semantics fix
      (2 = partial success — **behavior change from 0.2.0**), order-independent mutual
      exclusivity, CI, test/shellcheck fixes; update version statistics table
- [x] Bump `BREW_USAGE_VERSION` to `0.3.0` in `lib/brew-usage-config.sh`
- [x] Update PRD-002: status reflects reality (core use case now fulfilled), note
      exit-code decision

**Acceptance:**
- `./brew-usage --version` → `0.3.0`
- No stale claims remain (grep for `brew --bottle-tag`, "Top N filtering not yet")

---

## Dependency Graph

```
Task 1 (ghcr download)  ──┐
Task 2 (CLI fixes)       ──┼── all independent file-wise; run sequentially on one branch
Task 3 (tests+shellcheck)─┤    (Task 3 touches lib files Task 1 edits — order 1 → 3)
Task 4 (CI)              ──┤
Task 5 (docs+release)    ──┘   last: includes version bump + changelog
```

## Definition of Done (PR-level)

- All tests pass locally; shellcheck clean; `bash -n` clean
- CI green on the PR
- Conventional Commits, `Co-Authored-By: GLM <zai-org@users.noreply.github.com>`
- No checkbox in this file marked ✅ while any stub remains in delivered code
- Post-merge (separate step, with user): tag v0.3.0, homebrew-tap bump
