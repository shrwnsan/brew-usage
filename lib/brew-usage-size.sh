#!/usr/bin/env bash
# Bottle manifest size lookup module for brew-usage
# Handles fetching, caching, and parsing Homebrew bottle manifests

# Source dependencies
if [[ -z "${BREW_USAGE_CONFIG_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-config.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-config.sh" || {
        echo "Error: Failed to source brew-usage-config.sh" >&2
        exit 1
    }
fi

if [[ -z "${BREW_USAGE_UTILS_LOADED:-}" ]]; then
    # shellcheck source=../lib/brew-usage-utils.sh
    source "$(dirname "${BASH_SOURCE[0]}")/brew-usage-utils.sh" || {
        echo "Error: Failed to source brew-usage-utils.sh" >&2
        exit 1
    }
fi

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_SIZE_LOADED:-} when standalone-sourced
readonly BREW_USAGE_SIZE_LOADED=true

# =============================================================================
# Cache file path generation
# =============================================================================

# Generate manifest cache filename from package, version, and bottle tag
# Input: package_name, version, bottle_tag
# Output: Cache filename (not full path)
# Example: get_manifest_filename "go" "1.25.7_1" "arm64_sonoma"
#         Output: "go--1.25.7_1--arm64_sonoma.json"
get_manifest_filename() {
    local package_name="$1"
    local version="$2"
    local bottle_tag="$3"

    if [[ -z "$package_name" || -z "$version" || -z "$bottle_tag" ]]; then
        log_error "get_manifest_filename: missing required arguments"
        return 1
    fi

    echo "${package_name}--${version}--${bottle_tag}.json"
}

# Get full path to manifest cache file
# Input: package_name, version, bottle_tag
# Output: Full path to cache file
get_manifest_cache_path() {
    local package_name="$1"
    local version="$2"
    local bottle_tag="$3"

    local filename
    filename=$(get_manifest_filename "$package_name" "$version" "$bottle_tag") || return 1

    echo "${BREW_BOTTLE_CACHE_DIR}/${filename}"
}

# =============================================================================
# Cache validation
# =============================================================================

# Check if cached manifest exists and is within TTL
# Input: cache_file_path
# Output: 0 (valid) or 1 (invalid/expired)
is_cache_valid() {
    local cache_file="$1"

    # File must exist
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check file age against TTL
    # NOTE: stat is not flag-portable — GNU `stat -f` means *filesystem mode*
    # (exits 0 with garbage output for %m), so a BSD-first fallback idiom
    # silently breaks on Linux. Select the invocation by platform instead.
    local mtime
    if is_macos; then
        mtime=$(stat -f %m "$cache_file" 2>/dev/null)
    else
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
    fi
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 1

    local file_age
    file_age=$(( $(date +%s) - mtime ))

    if [[ $file_age -lt $BREW_BOTTLE_CACHE_TTL ]]; then
        return 0
    fi

    return 1
}

# =============================================================================
# Platform matching
# =============================================================================

# Find the best matching platform tag in bottle manifest
# Accounts for newer macOS versions falling back to older bottles
# Input: manifest_json_path, desired_bottle_tag
# Output: Matching platform tag from manifest or empty string
find_matching_platform_tag() {
    local manifest_path="$1"
    local desired_tag="$2"

    if [[ ! -f "$manifest_path" ]]; then
        log_error "find_matching_platform_tag: manifest file not found: $manifest_path"
        return 1
    fi

    # Extract architecture from desired tag
    local desired_arch="${desired_tag%_*}"

    # Try exact match first (match tag suffix in ref.name)
    # The tag is passed via --arg (data, not program) so metacharacters in it
    # can never alter the jq filter below.
    local exact_match
    exact_match=$(jq -r --arg tag "$desired_tag" \
        '.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] | endswith($tag)) | .annotations["org.opencontainers.image.ref.name"]' \
        "$manifest_path" 2>/dev/null | head -n 1)

    if [[ -n "$exact_match" ]]; then
        echo "$exact_match"
        return 0
    fi

    # No exact match: try fallback for newer macOS versions
    # Fallback order: tahoe -> sequoia -> sonoma -> ventura -> monterey -> big_sur
    local codenames=("tahoe" "sequoia" "sonoma" "ventura" "monterey" "big_sur")

    # Find which codename we want
    local desired_codename="${desired_tag#*_}"

    # Skip fallback for Linux (no version codenames)
    if [[ "$desired_codename" != "linux" ]]; then
        for codename in "${codenames[@]}"; do
            [[ "$codename" == "$desired_codename" ]] && continue

            local fallback_tag="${desired_arch}_${codename}"
            local fallback_match
            fallback_match=$(jq -r --arg tag "$fallback_tag" \
                '.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] | endswith($tag)) | .annotations["org.opencontainers.image.ref.name"]' \
                "$manifest_path" 2>/dev/null | head -n 1)

            if [[ -n "$fallback_match" ]]; then
                log_warning "Platform tag '$desired_tag' not found, using fallback '$fallback_match'"
                echo "$fallback_match"
                return 0
            fi
        done
    fi

    # Try architecture-independent bottles (tag ends in '.all', e.g. '1.10.17.all')
    local all_match
    all_match=$(jq -r '.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] | endswith(".all")) | .annotations["org.opencontainers.image.ref.name"]' "$manifest_path" 2>/dev/null | head -n 1)

    if [[ -n "$all_match" ]]; then
        log_warning "Platform tag '$desired_tag' not found, using architecture-independent bottle '$all_match'"
        echo "$all_match"
        return 0
    fi

    # No matching platform found
    log_error "No matching platform tag found for '$desired_tag'"
    return 1
}

# =============================================================================
# Bottle manifest fetching
# =============================================================================

# Fetch bottle manifest from cache or download it
# Input: package_name, version, bottle_tag
# Output: Path to manifest file (cached or downloaded)
# Exit codes: 0 (success), 1 (failure)
fetch_bottle_manifest() {
    local package_name="$1"
    local version="$2"
    local bottle_tag="$3"

    # Generate cache file path
    local cache_path
    cache_path=$(get_manifest_cache_path "$package_name" "$version" "$bottle_tag") || return 1

    # Check if cached version is valid
    if is_cache_valid "$cache_path"; then
        echo "$cache_path"
        return 0
    # File exists but is expired - remove it
    elif [[ -f "$cache_path" ]]; then
        rm -f "$cache_path"
    fi

    # Not in cache or expired: need to download
    # First, try to find existing manifest in Homebrew's cache
    # Homebrew caches manifests with different filenames (using SHA256 prefix)
    # Version in manifest may include _revision suffix, so search with wildcard
    local version_base="${version%%_*}"  # Remove _revision suffix if present
    local cached_manifest
    cached_manifest=$(find "$BREW_BOTTLE_CACHE_DIR" -name "*--${package_name}-${version_base}*.bottle_manifest.json" 2>/dev/null | head -n 1)

    if [[ -n "$cached_manifest" && -f "$cached_manifest" ]]; then
        # Verify the manifest has our platform (or compatible fallback)
        local matching_tag
        matching_tag=$(find_matching_platform_tag "$cached_manifest" "$bottle_tag")

        if [[ -n "$matching_tag" ]]; then
            # Copy to our cache location
            cp "$cached_manifest" "$cache_path" 2>/dev/null || {
                log_error "Failed to copy manifest from Homebrew cache"
                return 1
            }
            echo "$cache_path"
            return 0
        fi
    fi

    # Not found in Homebrew cache: download from ghcr.io
    download_manifest_from_ghcr "$package_name" "$version" "$cache_path" || return 1

    echo "$cache_path"
    return 0
}

# Download bottle manifest from ghcr.io (Homebrew's container registry)
# Versioned formulae use '/' in ghcr paths (e.g. node@20 -> homebrew/core/node/20)
# Input: package_name, version, cache_path (destination for validated manifest)
# Output: Writes manifest JSON to cache_path on success
# Exit codes: 0 (success), 1 (download/validation failure)
download_manifest_from_ghcr() {
    local package_name="$1"
    local version="$2"
    local cache_path="$3"

    # Defense in depth: this function builds the ghcr URL, so it re-checks
    # its inputs even though get_package_size already validated them
    if ! is_valid_package_name "$package_name" || ! is_valid_version "$version"; then
        log_warning "Skipping manifest download for '$package_name': invalid name or version '$version'"
        return 1
    fi

    # Translate versioned formula separator for ghcr repository path
    local ghcr_repo="homebrew/core/${package_name//@//}"

    # Fetch anonymous pull token
    local token
    token=$(curl -fsSL --max-time 30 \
        "https://ghcr.io/token?scope=repository:${ghcr_repo}:pull" 2>/dev/null \
        | jq -r '.token // empty' 2>/dev/null) || {
        log_warning "Could not reach ghcr.io to fetch manifest for '$package_name' (offline or network error)"
        return 1
    }

    if [[ -z "$token" ]]; then
        log_error "Failed to obtain ghcr.io token for '$package_name'"
        return 1
    fi

    # Download manifest to a temp file first - never write partial/invalid data to cache
    mkdir -p "$BREW_BOTTLE_CACHE_DIR" 2>/dev/null || true
    local tmp_manifest
    tmp_manifest=$(mktemp "${BREW_BOTTLE_CACHE_DIR}/.manifest.XXXXXX") || {
        log_error "Failed to create temp file for manifest download"
        return 1
    }

    if ! curl -fsSL --max-time 30 \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        -o "$tmp_manifest" \
        "https://ghcr.io/v2/${ghcr_repo}/manifests/${version}" 2>/dev/null; then
        rm -f "$tmp_manifest"
        log_warning "Manifest download failed for '$package_name' $version (not found on ghcr.io or network error)"
        return 1
    fi

    # Validate: file must be non-empty JSON with .manifests[] entries
    if [[ ! -s "$tmp_manifest" ]] || \
       ! jq -e '(.manifests | type == "array" and length > 0)' "$tmp_manifest" >/dev/null 2>&1; then
        rm -f "$tmp_manifest"
        log_error "Downloaded manifest for '$package_name' is invalid or has no platform entries"
        return 1
    fi

    # Atomically move validated manifest into cache
    if ! mv "$tmp_manifest" "$cache_path" 2>/dev/null; then
        rm -f "$tmp_manifest"
        log_error "Failed to write manifest to cache: $cache_path"
        return 1
    fi

    return 0
}

# =============================================================================
# Input validation
# =============================================================================

# Validate a package name before it reaches jq programs, ghcr.io URLs,
# cache filenames, or find patterns. Homebrew formula/cask names are
# lowercase alphanumerics plus . _ @ + - (covers versioned formulae like
# node@20 and names like gtk+). Everything else — whitespace, slashes
# (including fully-qualified tap paths), shell/glob/URL metacharacters —
# is rejected up front.
# Input: package_name
# Output: 0 (valid) or 1 (invalid)
is_valid_package_name() {
    [[ "$1" =~ ^[a-z0-9._@+-]+$ ]]
}

# Validate a version string. Must allow '+' (pre-release builds) and '_'
# (revision suffix, e.g. 1.25.7_1); rejects path and URL metacharacters
# that would corrupt ghcr URLs or cache filenames.
# Input: version
# Output: 0 (valid) or 1 (invalid)
is_valid_version() {
    [[ "$1" =~ ^[a-zA-Z0-9._+-]+$ ]]
}

# =============================================================================
# Size extraction from manifest
# =============================================================================

# Extract size information from bottle manifest for a specific platform
# Input: manifest_path, bottle_tag
# Output: JSON with download_size and installed_size (in bytes)
# Exit codes: 0 (success), 1 (failure)
extract_sizes_from_manifest() {
    local manifest_path="$1"
    local bottle_tag="$2"

    # Find matching platform tag (handles fallback for newer macOS)
    local matching_tag
    matching_tag=$(find_matching_platform_tag "$manifest_path" "$bottle_tag") || return 1

    # Extract sizes using jq
    jq -r --arg tag "$matching_tag" '
        .manifests[]
        | select(.annotations["org.opencontainers.image.ref.name"] == $tag)
        | {
            download: .annotations["sh.brew.bottle.size"],
            installed: .annotations["sh.brew.bottle.installed_size"],
            platform: $tag
          }
    ' "$manifest_path"
}

# =============================================================================
# Main API: Get package size information
# =============================================================================

# Get bottle size information for a Homebrew package
# Input: package_name (e.g., "go", "node@20")
# Output: JSON with package name, version, download size, installed size, platform
# Exit codes: 0 (success), 1 (failure), 2 (no bottle available)
get_package_size() {
    local package_name="$1"

    if [[ -z "$package_name" ]]; then
        log_error "get_package_size: package name is required"
        return 1
    fi

    # Reject hostile names before any brew/network/cache interaction
    if ! is_valid_package_name "$package_name"; then
        log_error "Invalid package name: '$package_name'"
        return 1
    fi

    # Get package info from Homebrew
    local brew_info
    brew_info=$(brew info --json=v2 "$package_name" 2>/dev/null)

    if [[ -z "$brew_info" ]]; then
        log_error "Package '$package_name' not found"
        return 1
    fi

    # Extract version using jq (handle both formulae and casks)
    local version
    version=$(echo "$brew_info" | jq -r '
        if .formulae and (.formulae | length) > 0 then
            .formulae[0].versions.stable // .formulae[0].version
        elif .casks and (.casks | length) > 0 then
            .casks[0].version
        else
            empty
        end
    ' 2>/dev/null)

    if [[ -z "$version" || "$version" == "null" ]]; then
        log_error "Could not determine version for '$package_name'"
        return 1
    fi

    # For formulae, append revision if present (manifests use version_revision format)
    local revision
    revision=$(echo "$brew_info" | jq -r '
        if .formulae and (.formulae | length) > 0 then
            .formulae[0].revision // 0
        else
            0
        end
    ' 2>/dev/null)

    if [[ "$revision" != "0" && "$revision" != "null" && -n "$revision" ]]; then
        version="${version}_${revision}"
    fi

    # A malformed version (from a stubbed or third-party tap) must not
    # reach the ghcr URL, cache filename, or find pattern below
    if ! is_valid_version "$version"; then
        log_error "Invalid version string for '$package_name': '$version'"
        return 1
    fi

    # Get current bottle tag
    local bottle_tag
    bottle_tag=$(get_bottle_tag) || {
        log_error "Failed to determine bottle tag"
        return 1
    }

    # Fetch bottle manifest
    local manifest_path
    manifest_path=$(fetch_bottle_manifest "$package_name" "$version" "$bottle_tag")

    if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
        log_warning "No bottle manifest available for '$package_name'"
        return 2
    fi

    # Extract and output sizes as JSON
    local sizes
    sizes=$(extract_sizes_from_manifest "$manifest_path" "$bottle_tag") || return 1

    # Output complete JSON
    jq -n \
        --arg name "$package_name" \
        --arg version "$version" \
        --arg download "$(echo "$sizes" | jq -r '.download')" \
        --arg installed "$(echo "$sizes" | jq -r '.installed')" \
        --arg platform "$(echo "$sizes" | jq -r '.platform')" \
        '{
            name: $name,
            version: $version,
            download_size: ($download | tonumber),
            installed_size: ($installed | tonumber),
            platform: $platform
        }'
}
