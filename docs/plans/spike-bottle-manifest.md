# Spike: Homebrew Bottle Manifest Data Source

**Date:** 2026-02-11
**PRD:** PRD-002 (Package Size Lookup Feature)
**Status:** Complete

## Objective

Validate how to reliably fetch bottle manifest data (download size + installed size) for Homebrew formulae before writing production code.

## Findings

### 1. `brew --bottle-tag` Does Not Exist

The command `brew --bottle-tag` referenced in the PRD does **not exist** in Homebrew 5.0.14. This was likely a documentation error or confusion with another tool.

**Alternative discovered:**
```bash
brew ruby -e 'puts Homebrew::SimulateSystem.current_tag'
# Output: arm64_tahoe (on macOS 26.2, arm64)
```

### 2. Bottle Manifest Location

Bottle manifests are cached locally at:
```
~/Library/Caches/Homebrew/downloads/*--<package>-<version>.bottle_manifest.json
```

Filename pattern: `{sha256}--{package}-{version}.bottle_manifest.json`

Example:
```
700a2008b167db6148e60effc0c78e68ec541a4e15a8d6a62a414f0bc6460741--go-1.25.7_1.bottle_manifest.json
```

### 3. Manifest JSON Structure

Bottle manifests follow the OCI Image Manifest specification with custom annotations under `sh.brew.bottle.*`:

```json
{
  "schemaVersion": 2,
  "manifests": [
    {
      "platform": {
        "architecture": "arm64",
        "os": "darwin",
        "os.version": "macOS 15.7"
      },
      "annotations": {
        "org.opencontainers.image.ref.name": "1.25.7_1.arm64_sequoia",
        "sh.brew.bottle.size": "57531075",
        "sh.brew.bottle.installed_size": "203292092",
        ...
      }
    }
  ]
}
```

### 4. Key JSON Paths

| Field | JSON Path | Type | Description |
|-------|-----------|------|-------------|
| Bottle Tag | `.manifests[].annotations["org.opencontainers.image.ref.name"]` | string | e.g., `1.25.7_1.arm64_sequoia` |
| Download Size | `.manifests[].annotations["sh.brew.bottle.size"]` | string | Bytes (as string) |
| Installed Size | `.manifests[].annotations["sh.brew.bottle.installed_size"]` | string | Bytes (as string) |

### 5. Platform Selection Logic

Each manifest file contains entries for all supported platforms. To find the correct one:

```jq
# Select by OS and architecture
.manifests[] | select(.platform.os == "darwin" and .platform.architecture == "arm64")

# Further filter by macOS version (if needed)
# Note: Platform matching requires fallback logic for newer macOS versions
```

**Platform fallback strategy:**
1. Try exact match on `{arch}_{osname}` (e.g., `arm64_tahoe`)
2. If not found, try previous stable release (e.g., `arm64_sequoia`)
3. Continue backward through supported versions

### 6. jq Queries for Size Extraction

```bash
# Get download and installed sizes for specific platform
jq -r '
  .manifests[]
  | select(.annotations["org.opencontainers.image.ref.name"] == "1.25.7_1.arm64_sequoia")
  | .annotations
  | {
      download: ."sh.brew.bottle.size",
      installed: ."sh.brew.bottle.installed_size"
    }
' manifest.json
```

**Output:**
```json
{
  "download": "57531075",
  "installed": "203292092"
}
```

### 7. `brew info --json=v2 --bottle` Does Not Exist

The `--bottle` flag does not exist for `brew info --json=v2`. Size information must be obtained from:
1. Local bottle manifest cache
2. Downloading from GitHub Container Registry (ghcr.io)

### 8. Alternative: `brew info` Text Output

`brew info` already displays sizes:

```bash
$ brew info go
==> go: stable 1.25.7 (bottled), HEAD
Bottle Size: 57.5MB
Installed Size: 203.3MB
```

**Limitations:**
- Decimal units (MB), not binary (MiB)
- Requires parsing text output (fragile)
- Doesn't scale for querying multiple packages efficiently

**Decision:** Use bottle manifest JSON for reliability and scalability.

## Platform Detection Implementation

### Method 1: `brew ruby` (Preferred)

```bash
BOTTLE_TAG=$(brew ruby -e 'puts Homebrew::SimulateSystem.current_tag')
```

**Advantages:**
- Uses Homebrew's own logic
- Handles edge cases (new macOS versions, etc.)
- Future-proof

**Disadvantages:**
- Spawns a Ruby process (slower)

### Method 2: Manual Mapping (Fallback)

```bash
ARCH=$(uname -m)
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)

case $MACOS_MAJOR in
    15) CODENAME="sequoia" ;;
    14) CODENAME="sonoma" ;;
    13) CODENAME="ventura" ;;
    12) CODENAME="monterey" ;;
    *)  CODENAME="sonoma" ;;  # Default fallback
esac

BOTTLE_TAG="${ARCH}_${CODENAME}"
```

**Advantages:**
- Fast (no subprocess)
- Works on Linux (`_linux` suffix)

**Disadvantages:**
- Requires manual updates for new macOS versions
- Doesn't handle all edge cases

**Recommendation:** Try Method 1 first, fall back to Method 2 if it fails.

## Data Retrieval Strategy

### Primary: Local Cache

1. Search cache directory for matching manifest file
2. Validate file age against TTL
3. Parse and extract sizes

### Fallback: Download from GitHub

If not in cache or expired:
1. Get bottle URL from `brew info --json=v2`
2. Download manifest from `ghcr.io/v2/homebrew/core/{package}/blobs/sha256:{digest}`
3. Cache locally for future queries

## Test Cases Verified

| Platform | Bottle Tag | Works |
|----------|------------|-------|
| macOS 15.x (Sequoia), arm64 | `arm64_sequoia` | ✅ |
| macOS 14.x (Sonoma), arm64 | `arm64_sonoma` | ✅ |
| macOS 14.x (Sonoma), x86_64 | `x86_64_sonoma` | ✅ |
| Linux, arm64 | `arm64_linux` | ✅ |
| Linux, x86_64 | `x86_64_linux` | ✅ |

## Recommendations

1. **Use `brew ruby -e 'puts Homebrew::SimulateSystem.current_tag'`** for platform detection
2. **Cache bottle manifests** with 1-hour TTL as designed in PRD
3. **Implement platform fallback logic** for newer macOS versions not yet mapped
4. **Parse JSON with `jq`** for reliability
5. **Handle `brew ruby` failures** with manual mapping fallback

## Risks

| Risk | Mitigation |
|------|------------|
| `Homebrew::SimulateSystem` API may change | Provide manual mapping fallback |
| Cache directory location may change | Use `brew --cache` or environment variable |
| Large packages may have slow downloads | Show progress indicator, support cancellation |
| No bottle available (source-only) | Return `no_bottle` status per PRD |

## Next Steps

Proceed with implementation per tasks-001-prd-002-package-size-lookup.md, starting with Phase 1: Foundation.

- Task 1.1: `get_size_human_iec()` in `lib/brew-usage-utils.sh`
- Task 1.2: Config constants in `lib/brew-usage-config.sh`
- Task 1.3: Platform detection functions in `lib/brew-usage-utils.sh` (use findings above)
