#!/usr/bin/env bash
# Display module for brew-usage
# Handles output formatting and presentation

# Display header
display_header() {
    local use_color="${1:-true}"

    local bold reset
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo ""
    echo "${bold}Homebrew Usage Report${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Display section header
display_section_header() {
    local title="$1"
    local icon="$2"
    local use_color="${3:-true}"

    local bold reset
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo ""
    echo "${bold}${icon} ${title}${reset}"
}

# Display section total
display_section_total() {
    local total_bytes="$1"
    local use_color="${2:-true}"

    local bold reset cyan
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")

    local total_human
    total_human=$(get_size_human "$total_bytes")

    echo "   ───────────────"
    echo "${cyan}Total: ${total_human}${reset}"
}

# Display cache analysis section (read-only; cleanup is left to `brew cleanup`)
# Input: $1 = total bytes, $2 = downloads bytes, $3 = other bytes,
#        $4 = file count, $5 = cleanup candidates bytes,
#        $6 = cleanup candidates count, $7 = cleanup age (days),
#        $8 = use color
display_cache_section() {
    local total_bytes="$1"
    local downloads_bytes="$2"
    local other_bytes="$3"
    local file_count="$4"
    local cleanup_bytes="$5"
    local cleanup_count="$6"
    local cleanup_days="$7"
    local use_color="${8:-true}"

    local bold reset cyan yellow
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")
    yellow=$(get_color_code "yellow" "$use_color")

    local total_human downloads_human other_human cleanup_human
    total_human=$(get_size_human "$total_bytes")
    downloads_human=$(get_size_human "$downloads_bytes")
    other_human=$(get_size_human "$other_bytes")
    cleanup_human=$(get_size_human "$cleanup_bytes")

    echo "   ${total_human}   Total cache size ($(format_number "$file_count") files)"
    echo "   ${downloads_human}   Downloads"
    echo "   ${other_human}   Other"
    echo "   ───────────────"
    if (( cleanup_bytes > 0 )); then
        echo "   ${yellow}${cleanup_human}${reset}   Cleanup candidates: ${cleanup_human} (${cleanup_count} files)"
        echo "${bold}Suggestion:${reset} run \`brew cleanup --prune=${cleanup_days}\` to reclaim"
    else
        echo "   ${bold}No cleanup candidates (>${cleanup_days} days old)${reset}"
    fi
}

# Resolve the pager command (single line, words split by the caller).
# An explicit $PAGER is respected verbatim; the default enables ANSI
# passthrough (-R) because plain `less` mangles color escapes (shown as
# literal "ESC[" text or stripped, depending on less version).
pager_command() {
    printf '%s\n' "${PAGER:-less -R}"
}

# Page a file through the resolved pager (see pager_command)
# Errexit-safe by design: the file is fully written before paging, so an
# early pager quit cannot SIGPIPE the report generation, and pager failures
# (non-zero exit, missing binary) never abort the caller. Falls back to
# plain cat when the configured pager is not installed.
page_file() {
    local file="$1"

    local pager_cmd
    pager_cmd=$(pager_command)

    local pager_args=()
    read -r -a pager_args <<< "$pager_cmd"

    if command -v "${pager_args[0]}" >/dev/null 2>&1; then
        "${pager_args[@]}" < "$file" || true
    else
        cat "$file" || true
    fi
}

# Display grand total
display_grand_total() {
    local grand_total="$1"
    local use_color="${2:-true}"

    local bold reset green
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    green=$(get_color_code "green" "$use_color")

    local total_human
    total_human=$(get_size_human "$grand_total")

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${green}${bold}Grand Total: ${total_human}${reset}"
    echo ""
}

# Display empty state
display_empty_state() {
    local message="${1:-No packages found}"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}${message}${reset}"
}

# Display error message
display_error() {
    local message="$1"
    local use_color="${2:-true}"

    local red reset
    red=$(get_color_code "red" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${red}Error: ${message}${reset}" >&2
}

# Display help message
display_help() {
    cat << 'EOF'
Usage: brew-usage [OPTIONS]

Shows disk usage information for installed Homebrew packages.

Options:
  -h, --help           Show this help message
  -f, --formulae       Show formulae only
  -c, --casks          Show casks only
  -t, --top N          Show top N packages by size (default: 10)
  -a, --all            Show all packages (no top-N cut); output is paged
                       when stdout is a terminal (respects $PAGER)
  -s, --sort ORDER     Sort order: size, name (default: size)
      --size PKG...    Show bottle sizes for specific packages
      --quiet FIELD    With --size: print one value per package (FIELD:
                       download or installed); no color, no decorations;
                       failed packages print nothing on stdout
  -C, --cache          Show Homebrew cache analysis (standalone, or as an
                       extra section when combined with report flags)
  doctor, -d, --doctor Diagnose the brew-usage environment (read-only; exit 0
                       healthy, 2 warnings, 1 failures)
      --fix            With doctor: plan repairs for fixable findings
                       (dry run — nothing applied); conflicts with --json
      --yes            With doctor --fix: apply the planned fixes (only
                       brew-usage-owned state), then re-run doctor and show
                       the after report
      --flush-cache    Remove brew-usage's cached bottle manifests (only its
                       own *--*--*.json files, never Homebrew's) and print
                       how many were removed
      --json           Machine-readable JSON output (report and --size modes)
      --no-color       Disable color output
  -v, --version        Show version information

Examples:
  brew-usage                    # Show all Homebrew usage
  brew-usage --top 20          # Show top 20 largest packages
  brew-usage --formulae        # Show only formulae
  brew-usage --casks           # Show only casks
  brew-usage --sort name       # Sort by package name
  brew-usage --all             # Show every package (paged on a terminal)
  brew-usage --json            # JSON output for scripting
  brew-usage --size go node    # Bottle sizes for go and node
  brew-usage --size go --quiet installed  # Just the installed size value
  brew-usage --flush-cache     # Remove brew-usage's cached manifests
  brew-usage --cache           # Homebrew cache analysis only
  brew-usage --formulae --cache # Report with cache section appended
  brew-usage doctor            # Diagnose the brew-usage environment
  brew-usage doctor --json     # Diagnostics as JSON
  brew-usage doctor --fix      # Plan repairs for fixable findings (dry run)
  brew-usage doctor --fix --yes # Apply the planned repairs, re-run doctor

Config:
  Optional ~/.brew-usage-config with KEY=VALUE lines (numeric values only):
    TOP_N=N                    Default number of packages to show
    SIZE_WARNING_THRESHOLD=N   Warning color threshold in bytes (default: 100MB)
    SIZE_CRITICAL_THRESHOLD=N  Critical color threshold in bytes (default: 1GB)
    CACHE_CLEANUP_DAYS=N       Cache cleanup-candidate age in days (default: 30)
  Precedence: CLI flags > config file > built-in defaults.
  The file is strictly parsed (never sourced); malformed lines and unknown
  keys are warned about on stderr and ignored.

For more information, visit: https://github.com/shrwnsan/brew-usage
EOF
}

# Display version
display_version() {
    echo "brew-usage version $BREW_USAGE_VERSION"
}

# =============================================================================
# Doctor display functions (brew-usage doctor)
# =============================================================================

# Title-case a group name ("brew surfaces" -> "Brew surfaces")
# bash 3.2-safe (no ${var^})
doctor_group_title() {
    local group="$1"
    local first
    first=$(printf '%s' "${group:0:1}" | tr '[:lower:]' '[:upper:]')
    printf '%s%s' "$first" "${group:1}"
}

# Display the doctor report from doctor_run_all() result globals
# (DOCTOR_RESULT_NAMES/GROUPS/VERDICTS/DETAILS, DOCTOR_PASS/WARN/FAIL,
# DOCTOR_SUGGESTION_LIST; set by lib/brew-usage-doctor.sh)
# Input: $1 = use color
# Verdict coloring: ✓ green / ⚠ yellow / ✗ red (respects --no-color/non-tty)
display_doctor_report() {
    local use_color="${1:-true}"

    local bold reset green yellow red
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    green=$(get_color_code "green" "$use_color")
    yellow=$(get_color_code "yellow" "$use_color")
    red=$(get_color_code "red" "$use_color")

    echo ""
    echo "${bold}brew-usage doctor${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # bash 3.2-safe index loop (no ${!arr[@]} under set -u)
    local i group last_group="" verdict mark color
    local count=${#DOCTOR_RESULT_NAMES[@]}
    for ((i = 0; i < count; i++)); do
        group="${DOCTOR_RESULT_GROUPS[$i]}"
        if [[ "$group" != "$last_group" ]]; then
            echo ""
            echo "${bold}$(doctor_group_title "$group")${reset}"
            last_group="$group"
        fi

        verdict="${DOCTOR_RESULT_VERDICTS[$i]}"
        case "$verdict" in
            pass) mark="✓"; color="$green" ;;
            warn) mark="⚠"; color="$yellow" ;;
            *)    mark="✗"; color="$red" ;;
        esac

        printf '  %s%s%s %-18s %s\n' "$color" "$mark" "$reset" \
            "${DOCTOR_RESULT_NAMES[$i]}" "${DOCTOR_RESULT_DETAILS[$i]}"
    done

    echo ""
    echo "${bold}Summary:${reset} $DOCTOR_PASS passed, $DOCTOR_WARN warnings, $DOCTOR_FAIL failures"

    if [[ ${#DOCTOR_SUGGESTION_LIST[@]} -gt 0 ]]; then
        echo "${bold}Suggested fixes:${reset}"
        local suggestion
        for suggestion in "${DOCTOR_SUGGESTION_LIST[@]}"; do
            echo "  • $suggestion"
        done
    fi
    echo ""
}

# =============================================================================
# Size display functions for --size mode
# =============================================================================

# Display size information for a single package
# Input: JSON output from get_package_size()
display_package_size() {
    local size_json="$1"
    local use_color="${2:-true}"

    local name version download_size installed_size platform
    name=$(echo "$size_json" | jq -r '.name')
    version=$(echo "$size_json" | jq -r '.version')
    download_size=$(echo "$size_json" | jq -r '.download_size')
    installed_size=$(echo "$size_json" | jq -r '.installed_size')
    platform=$(echo "$size_json" | jq -r '.platform')

    local download_human installed_human
    download_human=$(get_size_human_iec "$download_size")
    installed_human=$(get_size_human_iec "$installed_size")

    local bold reset cyan green
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")
    green=$(get_color_code "green" "$use_color")

    echo ""
    echo "${bold}${name}${reset} ${green}${version}${reset}"
    echo "  Platform:      ${cyan}${platform}${reset}"
    echo "  Download:      ${cyan}${download_human}${reset}"
    echo "  Installed:     ${cyan}${installed_human}${reset}"
}

# Display size information for multiple packages in table format
# Input: Array of JSON objects from get_package_size()
display_multiple_package_sizes() {
    local -n size_results_ref=$1
    local use_color="${2:-true}"

    local bold reset cyan
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")
    cyan=$(get_color_code "cyan" "$use_color")

    echo ""
    echo "${bold}Package Sizes${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    printf "${bold}%-20s  %-12s  %-12s  %-12s${reset}\n" "Package" "Download" "Installed" "Platform"
    echo "──────────────────────────────────────────────────────────"

    for size_json in "${size_results_ref[@]}"; do
        local name version download_size installed_size platform
        name=$(echo "$size_json" | jq -r '.name')
        version=$(echo "$size_json" | jq -r '.version')
        download_size=$(echo "$size_json" | jq -r '.download_size')
        installed_size=$(echo "$size_json" | jq -r '.installed_size')
        platform=$(echo "$size_json" | jq -r '.platform')

        local download_human installed_human
        download_human=$(get_size_human_iec "$download_size")
        installed_human=$(get_size_human_iec "$installed_size")

        printf "%-20s  ${cyan}%-12s${reset}  ${cyan}%-12s${reset}  %-12s\n" \
            "$name" "$download_human" "$installed_human" "$platform"
    done
}

# Display a single value line for --quiet FIELD (size mode scripting output)
# Input: JSON from get_package_size(), field name (download|installed)
# Output: the field's human-readable size, value only, no decorations
display_quiet_size() {
    local size_json="$1"
    local field="$2"

    local bytes
    bytes=$(echo "$size_json" | jq -r ".${field}_size")

    # get_size_human_iec emits no trailing newline; printf supplies it
    printf '%s\n' "$(get_size_human_iec "$bytes")"
}

# Display warning message for size mode
# Input: warning message
display_size_warning() {
    local message="$1"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}Warning: ${message}${reset}" >&2
}

# Display error message for size mode
# Input: error message
display_size_error() {
    local message="$1"
    local use_color="${2:-true}"

    local red reset
    red=$(get_color_code "red" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${red}Error: ${message}${reset}" >&2
}

# Display "no bottle available" message
# Input: package name
display_no_bottle() {
    local package_name="$1"
    local use_color="${2:-true}"

    local yellow reset
    yellow=$(get_color_code "yellow" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo "${yellow}No bottle available for '${package_name}'${reset}" >&2
    echo "  This package may be source-only or not available for your platform." >&2
}

