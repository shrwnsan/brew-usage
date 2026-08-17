#!/usr/bin/env bash
# Size calculation module for brew-usage
# Handles cross-platform du commands (macOS BSD vs Linux GNU)

# Get size in bytes for a given path
# Handles platform-specific du commands
get_size_bytes() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "0"
        return
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use du -k and convert KB to bytes
        # BSD du doesn't have -b flag, so we use -k (kilobytes) and multiply
        local size_kb
        size_kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
        if [[ -n "$size_kb" && "$size_kb" =~ ^[0-9]+$ ]]; then
            echo $((size_kb * 1024))
        else
            echo "0"
        fi
    else
        # Linux: use du -b directly (GNU du has -b flag for bytes)
        local size_bytes
        size_bytes=$(du -sb "$path" 2>/dev/null | awk '{print $1}')
        if [[ -n "$size_bytes" && "$size_bytes" =~ ^[0-9]+$ ]]; then
            echo "$size_bytes"
        else
            echo "0"
        fi
    fi
}

# Convert bytes to human-readable format
# Returns value with appropriate unit (B, K, M, G, T)
get_size_human() {
    local bytes="$1"

    # Validate input is a number
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return
    fi

    # Use awk for floating point arithmetic
    if (( bytes >= 1099511627776 )); then
        # 1 TB or more
        awk -v size="$bytes" 'BEGIN { printf "%.1fT", size/1099511627776 }'
    elif (( bytes >= 1073741824 )); then
        # 1 GB or more
        awk -v size="$bytes" 'BEGIN { printf "%.1fG", size/1073741824 }'
    elif (( bytes >= 1048576 )); then
        # 1 MB or more
        awk -v size="$bytes" 'BEGIN { printf "%.1fM", size/1048576 }'
    elif (( bytes >= 1024 )); then
        # 1 KB or more
        awk -v size="$bytes" 'BEGIN { printf "%.1fK", size/1024 }'
    else
        # Less than 1 KB
        echo "${bytes}B"
    fi
}

# Calculate size for a single package
# Returns associative array with name, size_bytes, size_human
calculate_package_size() {
    local package_name="$1"
    local package_path="$2"

    if [[ ! -d "$package_path" ]]; then
        return 1
    fi

    local size_bytes
    size_bytes=$(get_size_bytes "$package_path")

    local size_human
    size_human=$(get_size_human "$size_bytes")

    # Output as space-separated values for easy parsing
    echo "${package_name}|${size_bytes}|${size_human}"
}

# Calculate total size for all packages in a list
calculate_total_size() {
    local -n packages_ref=$1  # nameref to associative array
    local total_bytes=0

    for package in "${!packages_ref[@]}"; do
        local size="${packages_ref[$package]}"
        # Extract bytes from format "name|bytes|human"
        local bytes
        bytes=$(echo "$size" | cut -d'|' -f2)
        if [[ -n "$bytes" && "$bytes" =~ ^[0-9]+$ ]]; then
            total_bytes=$((total_bytes + bytes))
        fi
    done

    echo "$total_bytes"
}
