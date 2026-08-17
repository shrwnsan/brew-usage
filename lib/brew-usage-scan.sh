#!/usr/bin/env bash
# Package scanning module for brew-usage

# Scan installed formulae
# Returns list of formula names
scan_formulae() {
    if ! brew list --formula 1>/dev/null 2>&1; then
        return 1
    fi

    brew list --formula 2>/dev/null
}

# Scan installed casks
# Returns list of cask names
scan_casks() {
    if ! brew list --cask 1>/dev/null 2>&1; then
        return 1
    fi

    brew list --cask 2>/dev/null
}

# Get package path
# For formulae: $(brew --prefix)/Cellar/package-name
# For casks: $(brew --prefix)/Caskroom/package-name
get_package_path() {
    local package_name="$1"
    local package_type="${2:-formula}"  # formula or cask

    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null)

    if [[ -z "$brew_prefix" ]]; then
        echo "Error: Unable to determine Homebrew prefix" >&2
        return 1
    fi

    local package_path
    if [[ "$package_type" == "formula" ]]; then
        package_path="${brew_prefix}/Cellar/${package_name}"
    elif [[ "$package_type" == "cask" ]]; then
        package_path="${brew_prefix}/Caskroom/${package_name}"
    else
        echo "Error: Invalid package type: $package_type" >&2
        return 1
    fi

    if [[ ! -d "$package_path" ]]; then
        return 1
    fi

    echo "$package_path"
}

# Validate package exists and is accessible
validate_package() {
    local package_name="$1"
    local package_type="${2:-formula}"

    local package_path
    package_path=$(get_package_path "$package_name" "$package_type")

    if [[ -z "$package_path" ]]; then
        return 1
    fi

    if [[ ! -d "$package_path" ]]; then
        return 1
    fi

    if [[ ! -r "$package_path" ]]; then
        return 1
    fi

    return 0
}

# Scan installed packages and print their names, one per line, to stdout
# (bash 3.2-safe: no namerefs, no associative arrays)
# Returns non-zero only for an invalid scan type
scan_packages() {
    local scan_type="${1:-all}"  # all, formulae, casks

    case "$scan_type" in
        formulae|formula)
            scan_formulae || true
            ;;
        casks|cask)
            scan_casks || true
            ;;
        all)
            scan_formulae || true
            scan_casks || true
            ;;
        *)
            echo "Error: Invalid scan type: $scan_type" >&2
            return 1
            ;;
    esac

    return 0
}
