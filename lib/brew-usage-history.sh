#!/usr/bin/env bash
# Size history module for brew-usage (PRD-008: --snapshot / --history)
#
# Historical size tracking: --snapshot records the installed-package
# inventory with actual du sizes as one JSONL line in the history file;
# --history diffs the two most recent snapshots. Storage is an append
# log, count-capped (the newest HISTORY_SNAPSHOT_KEEP lines survive).
# Local-only data: never uploaded, never sourced.

# History file location (overridable via BREW_USAGE_HISTORY_FILE for
# tests and alternate layouts; resolved at source time like
# BREW_USAGE_CONFIG_FILE)
BREW_USAGE_HISTORY_FILE="${BREW_USAGE_HISTORY_FILE:-${HOME}/.brew-usage/history/snapshots.jsonl}"

# Retention cap: keep the newest N snapshots (documented constant, not a
# config key — a tool about disk waste must not itself grow unbounded)
readonly HISTORY_SNAPSHOT_KEEP=90

# Scan installed formulae and casks and emit "name<TAB>bytes" lines
# (du-based, the report's own size source). A formula and a cask sharing
# a name sum — the map records total disk per name. Names accumulate in
# this shell first (loops feeding a pipe would run in a subshell and
# lose the found-any flag); only the sort/aggregate is piped.
# Output: sorted name<TAB>bytes lines on stdout
# Exit codes: 0 (at least one scan produced names), 1 (both scans
#             failed — nothing to record)
history_scan_sizes() {
    local name path bytes
    local raw=""

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        path=$(get_package_path "$name" "formula") || continue
        bytes=$(get_size_bytes "$path")
        [[ -n "$bytes" ]] || continue
        raw+="${name}"$'\t'"${bytes}"$'\n'
    done < <(scan_formulae 2>/dev/null)

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        path=$(get_package_path "$name" "cask") || continue
        bytes=$(get_size_bytes "$path")
        [[ -n "$bytes" ]] || continue
        raw+="${name}"$'\t'"${bytes}"$'\n'
    done < <(scan_casks 2>/dev/null)

    # Nothing installed (or both brew list calls failed): nothing to
    # record — caller reports it
    [[ -n "$raw" ]] || return 1

    printf '%b' "$raw" | sort | awk -F'\t' '
        { sum[$1] += $2 }
        END { for (n in sum) printf "%s\t%d\n", n, sum[n] }
    '
    return 0
}

# Record one snapshot: scan, build the JSONL line, append, prune
# Sets globals: none
# Output: the recorded JSON line on stdout (the caller prints the
#         confirmation); errors to stderr
# Exit codes: 0 recorded, 1 scan or write failure (no partial state:
#             the append is the last mutation and a failed prune keeps
#             the pre-prune file — over-retention, never data loss)
write_snapshot() {
    local history_file="$BREW_USAGE_HISTORY_FILE"
    local history_dir
    history_dir=$(dirname "$history_file")

    if ! mkdir -p "$history_dir" 2>/dev/null || [[ ! -d "$history_dir" ]]; then
        log_error "Cannot create history directory: $history_dir"
        return 1
    fi
    if [[ ! -w "$history_dir" ]]; then
        log_error "History directory not writable: $history_dir"
        return 1
    fi

    local size_lines
    size_lines=$(history_scan_sizes) || {
        log_error "Scanning installed packages failed (is brew working?)"
        return 1
    }
    if [[ -z "$size_lines" ]]; then
        log_error "No installed packages found — nothing to snapshot"
        return 1
    fi

    # name<TAB>bytes lines -> {"name":bytes,...} (sorted input keeps the
    # object deterministic; brew names cannot contain tabs)
    local packages_json
    packages_json=$(printf '%s\n' "$size_lines" | jq -Rn '
        reduce inputs as $line (
            {};
            . + {($line | split("\t")[0]): (($line | split("\t")[1]) | tonumber)}
        )
    ' 2>/dev/null) || {
        log_error "Building the snapshot object failed"
        return 1
    }

    local timestamp
    timestamp=$(date +%Y-%m-%dT%H:%M:%S%z)

    local snapshot_json
    snapshot_json=$(jq -nc \
        --arg timestamp "$timestamp" \
        --argjson packages "$packages_json" \
        '{
            timestamp: $timestamp,
            package_count: ($packages | length),
            total_bytes: ($packages | ([.[]] | add // 0)),
            packages: $packages
        }') || {
        log_error "Building the snapshot line failed"
        return 1
    }

    if ! printf '%s\n' "$snapshot_json" >> "$history_file" 2>/dev/null; then
        log_error "Cannot append to history file: $history_file"
        return 1
    fi

    # Prune to the newest HISTORY_SNAPSHOT_KEEP lines (atomic rewrite;
    # a failed prune leaves the longer file — never data loss)
    local line_count
    line_count=$(wc -l < "$history_file" 2>/dev/null | tr -d ' ')
    if [[ "$line_count" =~ ^[0-9]+$ ]] && (( line_count > HISTORY_SNAPSHOT_KEEP )); then
        local tmp
        tmp=$(mktemp "${history_dir}/.brew-usage-history.XXXXXX" 2>/dev/null)
        if [[ -n "$tmp" ]]; then
            if tail -n "$HISTORY_SNAPSHOT_KEEP" "$history_file" > "$tmp" 2>/dev/null \
               && mv -f "$tmp" "$history_file" 2>/dev/null; then
                :
            else
                rm -f "$tmp" 2>/dev/null || true
                log_warning "History prune failed (file keeps $line_count snapshots)"
            fi
        fi
    fi

    printf '%s\n' "$snapshot_json"
    return 0
}

# Number of snapshots currently in the history file
# Output: count (0 when the file is missing/empty)
history_snapshot_count() {
    local history_file="$BREW_USAGE_HISTORY_FILE"
    if [[ ! -f "$history_file" || ! -r "$history_file" ]]; then
        printf '0'
        return 0
    fi
    wc -l < "$history_file" | tr -d ' '
}

# Diff the two most recent snapshots into change records
# Output: TSV lines "name<TAB>from<TAB>to<TAB>delta<TAB>change" sorted
#         by absolute delta descending, capped at $1 entries (default
#         TOP_N); change is grew|shrank|added|removed
# Exit codes: 0 diffed, 1 fewer than two snapshots / unreadable /
#             malformed lines
history_diff_changes() {
    local limit="${1:-${TOP_N:-10}}"
    local history_file="$BREW_USAGE_HISTORY_FILE"

    if [[ ! -f "$history_file" || ! -r "$history_file" ]]; then
        log_error "No history file at $history_file — record one with --snapshot"
        return 1
    fi

    local count
    count=$(history_snapshot_count)
    if (( count < 2 )); then
        log_error "Need at least 2 snapshots to compare (have $count) — record more with --snapshot"
        return 1
    fi

    local old_json new_json
    old_json=$(tail -n 2 "$history_file" | sed -n '1p')
    new_json=$(tail -n 2 "$history_file" | sed -n '2p')

    if ! printf '%s' "$old_json" | jq -e . >/dev/null 2>&1 \
       || ! printf '%s' "$new_json" | jq -e . >/dev/null 2>&1; then
        log_error "History file contains malformed lines — inspect $history_file"
        return 1
    fi

    jq -rn \
        --argjson old "$old_json" \
        --argjson new "$new_json" \
        --argjson limit "$limit" '
        ($old.packages) as $op | ($new.packages) as $np |
        [ ($np | keys[]) as $k
          | (select($op | has($k)) |
             select($op[$k] != $np[$k]) |
             {name: $k, from: $op[$k], to: $np[$k],
              delta: ($np[$k] - $op[$k]),
              change: (if $np[$k] > $op[$k] then "grew" else "shrank" end)})
            ,
            (select(($op | has($k)) | not) |
             {name: $k, from: 0, to: $np[$k], delta: $np[$k], change: "added"})
        ]
        +
        [ ($op | keys[]) as $k
          | select(($np | has($k)) | not)
          | {name: $k, from: $op[$k], to: 0, delta: (-$op[$k]), change: "removed"}
        ]
        | sort_by(.delta | if . < 0 then -. else . end) | reverse
        | .[0:$limit][]
        | [.name, (.from | tostring), (.to | tostring), (.delta | tostring), .change]
        | join("\t")
    ' 2>/dev/null
}

# Snapshot summaries for the history header (old line, then new line)
# Output: two lines "timestamp<TAB>package_count<TAB>total_bytes"
# Exit codes: mirror history_diff_changes
history_summary_lines() {
    local history_file="$BREW_USAGE_HISTORY_FILE"

    if [[ ! -f "$history_file" || ! -r "$history_file" ]]; then
        log_error "No history file at $history_file — record one with --snapshot"
        return 1
    fi
    if (( $(history_snapshot_count) < 2 )); then
        log_error "Need at least 2 snapshots to compare — record more with --snapshot"
        return 1
    fi

    tail -n 2 "$history_file" | jq -r '
        [.timestamp, (.package_count | tostring), (.total_bytes | tostring)] | join("\t")
    ' 2>/dev/null
}

# Render the human history view: old/new summary + top movers
# Exit codes: 0 rendered, 1 propagated from the readers
render_history() {
    local use_color="${1:-true}"

    local summary
    summary=$(history_summary_lines) || return 1

    local old_line new_line
    old_line=$(printf '%s\n' "$summary" | sed -n '1p')
    new_line=$(printf '%s\n' "$summary" | sed -n '2p')

    local old_ts old_count old_total new_ts new_count new_total
    IFS=$'\t' read -r old_ts old_count old_total <<< "$old_line"
    IFS=$'\t' read -r new_ts new_count new_total <<< "$new_line"

    local total_delta=$((new_total - old_total))
    local total_delta_cell
    total_delta_cell="(+$(get_size_human_iec "$total_delta"))"
    if (( total_delta < 0 )); then
        total_delta_cell="(-$(get_size_human_iec "${total_delta#-}"))"
    elif (( total_delta == 0 )); then
        total_delta_cell="(no change)"
    fi

    local bold reset
    bold=$(get_color_code "bold" "$use_color")
    reset=$(get_color_code "reset" "$use_color")

    echo ""
    echo "${bold}Size History — last two snapshots${reset}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf 'Old: %s   %s packages   %s\n' "$old_ts" "$old_count" "$(get_size_human_iec "$old_total")"
    printf 'New: %s   %s packages   %s %s\n' "$new_ts" "$new_count" \
        "$(get_size_human_iec "$new_total")" "$total_delta_cell"

    local changes
    changes=$(history_diff_changes) || return 1

    if [[ -z "$changes" ]]; then
        echo ""
        echo "No per-package changes between the last two snapshots."
        return 0
    fi

    echo ""
    echo "${bold}Top changes (by absolute delta)${reset}"
    echo "────────────────────────────────────────────────────────────────"

    local name from to delta change from_cell to_cell delta_cell
    while IFS=$'\t' read -r name from to delta change; do
        [[ -n "$name" ]] || continue
        from_cell="$(get_size_human_iec "$from")"
        to_cell="$(get_size_human_iec "$to")"
        case "$change" in
            added)   name="$name (new)" ;;
            removed) name="$name (removed)" ;;
        esac
        if (( delta > 0 )); then
            delta_cell="+$(get_size_human_iec "$delta")"
        elif (( delta < 0 )); then
            delta_cell="-$(get_size_human_iec "${delta#-}")"
        else
            delta_cell="0"
        fi
        printf '  %-24s %14s   %12s -> %s\n' "$name" "$delta_cell" "$from_cell" "$to_cell"
    done <<< "$changes"

    return 0
}

# Render the --history --json document: {old, new, changes:[...]}
# Output: one JSON document on stdout
# Exit codes: 0 rendered, 1 propagated from the readers
render_history_json() {
    local summary
    summary=$(history_summary_lines) || return 1

    local old_line new_line
    old_line=$(printf '%s\n' "$summary" | sed -n '1p')
    new_line=$(printf '%s\n' "$summary" | sed -n '2p')

    local history_file="$BREW_USAGE_HISTORY_FILE"
    local old_json new_json
    old_json=$(tail -n 2 "$history_file" | sed -n '1p')
    new_json=$(tail -n 2 "$history_file" | sed -n '2p')

    local changes_tsv
    changes_tsv=$(history_diff_changes "${HISTORY_JSON_LIMIT:-1000}") || return 1

    local changes_json="[]"
    if [[ -n "$changes_tsv" ]]; then
        changes_json=$(printf '%s\n' "$changes_tsv" | jq -Rn '
            [inputs | split("\t") as [$n, $f, $t, $d, $c]
             | {name: $n, from: ($f | tonumber), to: ($t | tonumber),
                delta: ($d | tonumber), change: $c}]
        ' 2>/dev/null) || changes_json="[]"
    fi

    jq -nc \
        --argjson old "$old_json" \
        --argjson new "$new_json" \
        --argjson changes "$changes_json" \
        '{old: {timestamp: $old.timestamp, package_count: $old.package_count,
                total_bytes: $old.total_bytes},
          new: {timestamp: $new.timestamp, package_count: $new.package_count,
                total_bytes: $new.total_bytes},
          changes: $changes}'
}

# Mark this module as loaded
# shellcheck disable=SC2034 # guard read via ${BREW_USAGE_HISTORY_LOADED:-} when standalone-sourced
readonly BREW_USAGE_HISTORY_LOADED=true
