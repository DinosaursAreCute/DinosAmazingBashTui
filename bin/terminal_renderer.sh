#!/usr/bin/env bash

source colors.sh
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  terminal_renderer.sh — pure-bash terminal rendering toolkit             ║
# ║                                                                          ║
# ║  Source this file to get all functions, or run it directly:               ║
# ║    source terminal_renderer.sh                                           ║
# ║    bash terminal_renderer.sh <command> [flags] [args...]                 ║
# ║                                                                          ║
# ║  Every command has two forms:                                            ║
# ║    cmd  "args"              → prints to stdout                           ║
# ║    cmd_string "args"        → returns single string with literal \n      ║
# ║  CLI flag -s triggers string mode.                                       ║
# ║                                                                          ║
# ║  Commands: box, divider, alert, table, kv, hbar, banner, tree,          ║
# ║            columns, badges, list, quote                                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ===========================================================================
#  SHARED HELPERS
# ===========================================================================

_tr_term_width() {
    tput cols 2>/dev/null || echo 80
}

# Turn a TR_RESULT array into a \n-literal string
_tr_to_string() {
    local out=""
    for (( i = 0; i < ${#TR_RESULT[@]}; i++ )); do
        (( i > 0 )) && out+='\n'
        out+="${TR_RESULT[$i]}"
    done
    printf '%s' "$out"
}

# Print TR_RESULT array
_tr_print() {
    printf '%b\n' "${TR_RESULT[@]}"
}

# Repeat a character N times
_tr_repeat() {
    local ch="$1" n="$2" out=""
    for (( i = 0; i < n; i++ )); do out+="$ch"; done
    printf '%s' "$out"
}

# Word-wrap a string to a max width, results in _TR_WRAPPED array
_tr_wordwrap() {
    local text="$1" max="$2"
    _TR_WRAPPED=()

    local expanded
    expanded="$(printf '%b' "$text")"
    local raw_lines=()
    while IFS= read -r ln; do
        raw_lines+=("$ln")
    done <<< "$expanded"

    for raw in "${raw_lines[@]}"; do
        if [[ ${#raw} -le $max ]]; then
            _TR_WRAPPED+=("$raw")
        else
            local buf="" words=()
            read -ra words <<< "$raw"
            for word in "${words[@]}"; do
                if [[ -z "$buf" ]]; then
                    while [[ ${#word} -gt $max ]]; do
                        _TR_WRAPPED+=("${word:0:$max}")
                        word="${word:$max}"
                    done
                    buf="$word"
                elif (( ${#buf} + 1 + ${#word} <= max )); then
                    buf+=" $word"
                else
                    _TR_WRAPPED+=("$buf")
                    while [[ ${#word} -gt $max ]]; do
                        _TR_WRAPPED+=("${word:0:$max}")
                        word="${word:$max}"
                    done
                    buf="$word"
                fi
            done
            [[ -n "$buf" ]] && _TR_WRAPPED+=("$buf")
        fi
    done
}

# Strip ANSI escape sequences for length counting
_tr_strip_ansi() {
    local text="$1"
    # Remove CSI sequences (ESC[ ... final byte)
    text="$(printf '%s' "$text" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || printf '%s' "$text")"
    printf '%s' "$text"
}

_tr_visible_len() {
    local stripped
    stripped="$(_tr_strip_ansi "$1")"
    printf '%d' "${#stripped}"
}


# ===========================================================================
#  1. BOX — draw a Unicode box around a message
# ===========================================================================
#  Usage: box "message"    box "line1\nline2"    echo "text" | box
#  Min width 40, max terminal width, word-wraps long lines.

_box_build() {
    local input="$1"
    TR_RESULT=()
    [[ -z "$input" ]] && return 1

    local tw; tw="$(_tr_term_width)"
    local chrome=4 min_inner=36
    local max_inner=$(( tw - chrome ))
    (( max_inner < min_inner )) && max_inner=$min_inner

    _tr_wordwrap "$input" "$max_inner"

    local longest=0
    for ln in "${_TR_WRAPPED[@]}"; do
        (( ${#ln} > longest )) && longest=${#ln}
    done

    local inner=$longest
    (( inner < min_inner )) && inner=$min_inner

    local hbar; hbar="$(_tr_repeat "═" $(( inner + 2 )))"
    TR_RESULT+=("╔${hbar}╗")
    for ln in "${_TR_WRAPPED[@]}"; do
        local pad=$(( inner - ${#ln} ))
        TR_RESULT+=("$(printf '║ %s%*s ║' "$ln" "$pad" "")")
    done
    TR_RESULT+=("╚${hbar}╝")
}

box() {
    local input; if [[ $# -gt 0 ]]; then input="$*"; else input="$(cat)"; fi
    _box_build "$input" || return; _tr_print
}
box_string() {
    local input; if [[ $# -gt 0 ]]; then input="$*"; else input="$(cat)"; fi
    _box_build "$input" || return; _tr_to_string
}


# ===========================================================================
#  2. DIVIDER — horizontal rule with optional centered label
# ===========================================================================
#  Usage: divider                  → ────────────────────────────────────────
#         divider "SECTION"        → ──────────── SECTION ─────────────────

_divider_build() {
    local label="$1"
    TR_RESULT=()

    local tw; tw="$(_tr_term_width)"
    local width=$tw
    (( width < 40 )) && width=40

    if [[ -z "$label" ]]; then
        TR_RESULT+=("$(_tr_repeat "─" "$width")")
    else
        local tag=" ${label} "
        local tag_len=${#tag}
        local remaining=$(( width - tag_len ))
        local left=$(( remaining / 2 ))
        local right=$(( remaining - left ))
        TR_RESULT+=("$(_tr_repeat "─" "$left")${tag}$(_tr_repeat "─" "$right")")
    fi
}

divider() {
    _divider_build "$1"; _tr_print
}
divider_string() {
    _divider_build "$1"; _tr_to_string
}


# ===========================================================================
#  3. ALERT — styled callout box with type icon
# ===========================================================================
#  Usage: alert info "Server started on port 3000"
#         alert warn "Disk usage above 90%"
#         alert error "Connection refused"
#         alert success "Deployment complete"

_alert_build() {
    local type="${1:-info}" msg="$2"
    TR_RESULT=()
    [[ -z "$msg" ]] && return 1

    local icon label
    case "$type" in
        info)    icon="ℹ"; label="INFO"    ;;
        warn)    icon="⚠"; label="WARNING" ;;
        error)   icon="✖"; label="ERROR"   ;;
        success) icon="✔"; label="SUCCESS" ;;
        *)       icon="●"; label="${type^^}" ;;
    esac

    local tw; tw="$(_tr_term_width)"
    local chrome=4 min_inner=36
    local max_inner=$(( tw - chrome ))
    (( max_inner < min_inner )) && max_inner=$min_inner

    _tr_wordwrap "$msg" "$max_inner"

    local longest=0
    for ln in "${_TR_WRAPPED[@]}"; do
        (( ${#ln} > longest )) && longest=${#ln}
    done
    local header_len=$(( ${#icon} + 1 + ${#label} ))
    (( header_len > longest )) && longest=$header_len

    local inner=$longest
    (( inner < min_inner )) && inner=$min_inner

    local hbar; hbar="$(_tr_repeat "─" $(( inner + 2 )))"
    local hbar_heavy; hbar_heavy="$(_tr_repeat "━" $(( inner + 2 )))"

    TR_RESULT+=("┏${hbar_heavy}┓")
    local hpad=$(( inner - header_len ))
    TR_RESULT+=("$(printf '┃ %s %s%*s ┃' "$icon" "$label" "$hpad" "")")
    TR_RESULT+=("┠${hbar}┨")
    for ln in "${_TR_WRAPPED[@]}"; do
        local pad=$(( inner - ${#ln} ))
        TR_RESULT+=("$(printf '┃ %s%*s ┃' "$ln" "$pad" "")")
    done
    TR_RESULT+=("┗${hbar_heavy}┛")
}

alert() {
    _alert_build "$1" "$2" || return; _tr_print
}
alert_string() {
    _alert_build "$1" "$2" || return; _tr_to_string
}


# ===========================================================================
#  4. TABLE — data table from delimited input
# ===========================================================================
#  Usage: table "Name|Age|City" "Alice|30|NYC" "Bob|25|LA"
#         printf "Name,Age\nAlice,30\n" | table -d ","
#  First argument is the header row. Delimiter defaults to |.

_table_build() {
    local delim="|"
    local rows=()

    # Parse args: look for -d flag
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-d" ]]; then
            delim="$2"; shift 2
        else
            rows+=("$1"); shift
        fi
    done

    # If no rows, try stdin
    if [[ ${#rows[@]} -eq 0 ]]; then
        while IFS= read -r ln; do
            [[ -n "$ln" ]] && rows+=("$ln")
        done
    fi

    TR_RESULT=()
    [[ ${#rows[@]} -eq 0 ]] && return 1

    # Parse into 2D — find column widths
    local -a col_widths=()
    local -a all_cells=()
    local num_cols=0

    for row in "${rows[@]}"; do
        IFS="$delim" read -ra cells <<< "$row"
        local nc=${#cells[@]}
        (( nc > num_cols )) && num_cols=$nc
        for (( c = 0; c < nc; c++ )); do
            # Trim whitespace
            local cell="${cells[$c]}"
            cell="${cell#"${cell%%[![:space:]]*}"}"
            cell="${cell%"${cell##*[![:space:]]}"}"
            cells[$c]="$cell"
            local clen=${#cell}
            if (( c >= ${#col_widths[@]} )); then
                col_widths+=("$clen")
            elif (( clen > col_widths[c] )); then
                col_widths[$c]=$clen
            fi
        done
        all_cells+=("$(IFS=$'\x01'; printf '%s' "${cells[*]}")")
    done

    # Enforce minimum col width of 3
    for (( c = 0; c < num_cols; c++ )); do
        (( col_widths[c] < 3 )) && col_widths[$c]=3
    done

    # Build horizontal bars
    local bar_top="" bar_mid="" bar_bot="" bar_hdr=""
    for (( c = 0; c < num_cols; c++ )); do
        local seg; seg="$(_tr_repeat "─" $(( col_widths[c] + 2 )))"
        local seg_heavy; seg_heavy="$(_tr_repeat "═" $(( col_widths[c] + 2 )))"
        if (( c == 0 )); then
            bar_top="┌${seg}"; bar_mid="├${seg}"; bar_bot="└${seg}"; bar_hdr="╞${seg_heavy}"
        else
            bar_top+="┬${seg}"; bar_mid+="┼${seg}"; bar_bot+="┴${seg}"; bar_hdr+="╪${seg_heavy}"
        fi
    done
    bar_top+="┐"; bar_mid+="┤"; bar_bot+="┘"; bar_hdr+="╡"

    TR_RESULT+=("$bar_top")

    local row_idx=0
    for row_data in "${all_cells[@]}"; do
        IFS=$'\x01' read -ra cells <<< "$row_data"
        local line=""
        for (( c = 0; c < num_cols; c++ )); do
            local cell="${cells[$c]:-}"
            local pad=$(( col_widths[c] - ${#cell} ))
            line+="$(printf '│ %s%*s ' "$cell" "$pad" "")"
        done
        line+="│"
        TR_RESULT+=("$line")

        if (( row_idx == 0 )); then
            TR_RESULT+=("$bar_hdr")
        elif (( row_idx < ${#all_cells[@]} - 1 )); then
            TR_RESULT+=("$bar_mid")
        fi
        (( row_idx++ ))
    done

    TR_RESULT+=("$bar_bot")
}

table() {
    _table_build "$@" || return; _tr_print
}
table_string() {
    _table_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  5. KV — aligned key-value display
# ===========================================================================
#  Usage: kv "Host: server-01" "CPU: Intel i7" "RAM: 32 GB" "Uptime: 42 days"
#  Separator defaults to ": " — override with -d flag.
#  Styles: dots (default), plain, dashes  — set with -t flag.

_kv_build() {
    local delim=": " style="dots"
    local entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) delim="$2"; shift 2 ;;
            -t) style="$2"; shift 2 ;;
            *)  entries+=("$1"); shift ;;
        esac
    done

    # Stdin fallback
    if [[ ${#entries[@]} -eq 0 ]]; then
        while IFS= read -r ln; do
            [[ -n "$ln" ]] && entries+=("$ln")
        done
    fi

    TR_RESULT=()
    [[ ${#entries[@]} -eq 0 ]] && return 1

    local -a keys=() vals=()
    local max_key=0

    for entry in "${entries[@]}"; do
        local key="${entry%%${delim}*}"
        local val="${entry#*${delim}}"
        keys+=("$key")
        vals+=("$val")
        (( ${#key} > max_key )) && max_key=${#key}
    done

    local tw; tw="$(_tr_term_width)"

    for (( i = 0; i < ${#keys[@]}; i++ )); do
        local k="${keys[$i]}" v="${vals[$i]}"
        local gap=$(( max_key - ${#k} ))
        local fill=""

        case "$style" in
            dots)
                fill="$(_tr_repeat "·" $(( gap + 2 )))"
                TR_RESULT+=("$(printf '%s %s %s' "$k" "$fill" "$v")")
                ;;
            dashes)
                fill="$(_tr_repeat "-" $(( gap + 2 )))"
                TR_RESULT+=("$(printf '%s %s %s' "$k" "$fill" "$v")")
                ;;
            plain)
                TR_RESULT+=("$(printf '%-*s  %s' "$max_key" "$k" "$v")")
                ;;
        esac
    done
}

kv() {
    _kv_build "$@" || return; _tr_print
}
kv_string() {
    _kv_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6. HBAR — horizontal bar chart
# ===========================================================================
#  Usage: hbar "Revenue:78" "Costs:45" "Profit:33"
#         hbar -m 100 "A:30" "B:90"       ← explicit max
#         hbar -w 50 "X:40" "Y:60"        ← bar area width
#  Delimiter between label and value is : by default, override with -d.

_hbar_build() {
    local delim=":" max_val=0 bar_width=0
    local entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) delim="$2"; shift 2 ;;
            -m) max_val="$2"; shift 2 ;;
            -w) bar_width="$2"; shift 2 ;;
            *)  entries+=("$1"); shift ;;
        esac
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        while IFS= read -r ln; do
            [[ -n "$ln" ]] && entries+=("$ln")
        done
    fi

    TR_RESULT=()
    [[ ${#entries[@]} -eq 0 ]] && return 1

    local -a labels=() values=()
    local max_label=0

    for entry in "${entries[@]}"; do
        local label="${entry%%${delim}*}"
        local val="${entry#*${delim}}"
        labels+=("$label")
        values+=("$val")
        (( ${#label} > max_label )) && max_label=${#label}
        (( val > max_val )) && max_val=$val
    done

    (( max_val == 0 )) && max_val=1

    local tw; tw="$(_tr_term_width)"
    # bar_width: label + " " + bar + " " + value(up to 7 chars)
    if (( bar_width == 0 )); then
        bar_width=$(( tw - max_label - 10 ))
        (( bar_width < 10 )) && bar_width=10
        (( bar_width > 60 )) && bar_width=60
    fi

    for (( i = 0; i < ${#labels[@]}; i++ )); do
        local l="${labels[$i]}" v="${values[$i]}"
        local filled=$(( v * bar_width / max_val ))
        local empty=$(( bar_width - filled ))

        local bar_full; bar_full="$(_tr_repeat "█" "$filled")"
        local bar_empty; bar_empty="$(_tr_repeat "░" "$empty")"

        TR_RESULT+=("$(printf '%-*s %s%s %s' "$max_label" "$l" "$bar_full" "$bar_empty" "$v")")
    done
}

hbar() {
    _hbar_build "$@" || return; _tr_print
}
hbar_string() {
    _hbar_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  7. BANNER — big block-letter text (5-high font)
# ===========================================================================
#  Usage: banner "HELLO"
#  Supports A-Z, 0-9, space, and common punctuation.

declare -A _BANNER_FONT
_banner_font_init() {
    [[ -n "${_BANNER_FONT[A]+x}" ]] && return
    # Each letter is 5 rows, pipe-separated
    _BANNER_FONT[A]=" ██ |████|█  █|████|█  █"
    _BANNER_FONT[B]="███ |█  █|███ |█  █|███ "
    _BANNER_FONT[C]=" ███|█   |█   |█   | ███"
    _BANNER_FONT[D]="███ |█  █|█  █|█  █|███ "
    _BANNER_FONT[E]="████|█   |███ |█   |████"
    _BANNER_FONT[F]="████|█   |███ |█   |█   "
    _BANNER_FONT[G]=" ███|█   |█ ██|█  █| ███"
    _BANNER_FONT[H]="█  █|█  █|████|█  █|█  █"
    _BANNER_FONT[I]="███| █ | █ | █ |███"
    _BANNER_FONT[J]="████|  █ |  █ |█ █ | █  "
    _BANNER_FONT[K]="█  █|█ █ |██  |█ █ |█  █"
    _BANNER_FONT[L]="█   |█   |█   |█   |████"
    _BANNER_FONT[M]="█   █|██ ██|█ █ █|█   █|█   █"
    _BANNER_FONT[N]="█   █|██  █|█ █ █|█  ██|█   █"
    _BANNER_FONT[O]=" ██ |█  █|█  █|█  █| ██ "
    _BANNER_FONT[P]="███ |█  █|███ |█   |█   "
    _BANNER_FONT[Q]=" ██ |█  █|█ ██| ███|   █"
    _BANNER_FONT[R]="███ |█  █|███ |█ █ |█  █"
    _BANNER_FONT[S]=" ███|█   | ██ |   █|███ "
    _BANNER_FONT[T]="█████|  █  |  █  |  █  |  █  "
    _BANNER_FONT[U]="█  █|█  █|█  █|█  █| ██ "
    _BANNER_FONT[V]="█   █|█   █| █ █ | █ █ |  █  "
    _BANNER_FONT[W]="█   █|█   █|█ █ █|██ ██|█   █"
    _BANNER_FONT[X]="█  █|█  █| ██ |█  █|█  █"
    _BANNER_FONT[Y]="█   █| █ █ |  █  |  █  |  █  "
    _BANNER_FONT[Z]="████|  █ | █  |█   |████"
    _BANNER_FONT[0]=" ██ |█  █|█  █|█  █| ██ "
    _BANNER_FONT[1]=" █ |██ | █ | █ |███"
    _BANNER_FONT[2]=" ██ |█  █|  █ | █  |████"
    _BANNER_FONT[3]="███ |   █| ██ |   █|███ "
    _BANNER_FONT[4]="█  █|█  █|████|   █|   █"
    _BANNER_FONT[5]="████|█   |███ |   █|███ "
    _BANNER_FONT[6]=" ███|█   |███ |█  █| ██ "
    _BANNER_FONT[7]="████|   █|  █ | █  | █  "
    _BANNER_FONT[8]=" ██ |█  █| ██ |█  █| ██ "
    _BANNER_FONT[9]=" ██ |█  █| ███|   █|███ "
    _BANNER_FONT[' ']="   |   |   |   |   "
    _BANNER_FONT['!']="█|█|█| |█"
    _BANNER_FONT['.']=" | | | |█"
    _BANNER_FONT['-']="    |    |████|    |    "
    _BANNER_FONT[':']=" | |█| |█"
    _BANNER_FONT['?']=" ██ |█  █|  █ |    |  █ "
    _BANNER_FONT['/']="   █|  █ | █  |█   |    "
    _BANNER_FONT['_']="    |    |    |    |████"
}

_banner_build() {
    local text="${1^^}"   # uppercase
    TR_RESULT=()
    [[ -z "$text" ]] && return 1

    _banner_font_init

    # Build 5 rows
    local rows=("" "" "" "" "")
    for (( c = 0; c < ${#text}; c++ )); do
        local ch="${text:$c:1}"
        local glyph="${_BANNER_FONT[$ch]:-}"

        if [[ -z "$glyph" ]]; then
            # Unknown char — render as space
            glyph="${_BANNER_FONT[' ']}"
        fi

        # Split glyph rows
        IFS='|' read -ra glyph_rows <<< "$glyph"
        for (( r = 0; r < 5; r++ )); do
            [[ -n "${rows[$r]}" ]] && rows[$r]+=" "
            rows[$r]+="${glyph_rows[$r]:-}"
        done
    done

    for (( r = 0; r < 5; r++ )); do
        TR_RESULT+=("${rows[$r]}")
    done
}

banner() {
    _banner_build "$1" || return; _tr_print
}
banner_string() {
    _banner_build "$1" || return; _tr_to_string
}


# ===========================================================================
#  8. TREE — directory/hierarchy tree view
# ===========================================================================
#  Usage: tree "root" "  child1" "  child2" "    grandchild" "  child3"
#  Indent with 2 spaces per level. Or pipe indented text.

_tree_build() {
    local lines=()

    if [[ $# -gt 0 ]]; then
        for arg in "$@"; do
            local expanded
            expanded="$(printf '%b' "$arg")"
            while IFS= read -r ln; do
                lines+=("$ln")
            done <<< "$expanded"
        done
    else
        while IFS= read -r ln; do
            lines+=("$ln")
        done
    fi

    TR_RESULT=()
    [[ ${#lines[@]} -eq 0 ]] && return 1

    local count=${#lines[@]}

    # Determine indent level for each line (2 spaces = 1 level)
    local -a levels=()
    local -a texts=()
    for ln in "${lines[@]}"; do
        local stripped="${ln#"${ln%%[![:space:]]*}"}"
        local indent_chars=$(( ${#ln} - ${#stripped} ))
        local level=$(( indent_chars / 2 ))
        levels+=("$level")
        texts+=("$stripped")
    done

    for (( i = 0; i < count; i++ )); do
        local level=${levels[$i]}
        local text="${texts[$i]}"

        if (( level == 0 )); then
            TR_RESULT+=("$text")
            continue
        fi

        # Determine if this is the last sibling at its level
        local is_last=1
        for (( j = i + 1; j < count; j++ )); do
            if (( levels[j] == level )); then
                is_last=0; break
            elif (( levels[j] < level )); then
                break
            fi
        done

        # Build prefix
        local prefix=""
        for (( d = 1; d < level; d++ )); do
            # Check if ancestor at depth d has more siblings below
            local ancestor_has_more=0
            for (( j = i + 1; j < count; j++ )); do
                if (( levels[j] == d )); then
                    ancestor_has_more=1; break
                elif (( levels[j] < d )); then
                    break
                fi
            done
            if (( ancestor_has_more )); then
                prefix+="│   "
            else
                prefix+="    "
            fi
        done

        if (( is_last )); then
            prefix+="└── "
        else
            prefix+="├── "
        fi

        TR_RESULT+=("${prefix}${text}")
    done
}

tree() {
    if [[ $# -gt 0 ]]; then _tree_build "$@"; else _tree_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_print
}
tree_string() {
    if [[ $# -gt 0 ]]; then _tree_build "$@"; else _tree_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_to_string
}


# ===========================================================================
#  9. COLUMNS — side-by-side text blocks
# ===========================================================================
#  Usage: columns "Left block text" "Right block text"
#         columns -h "Before" -h "After" "old content" "new content"
#         columns "Col A" "Col B" "Col C"     ← 2 or 3 columns

_columns_build() {
    local -a headers=() bodies=()

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-h" ]]; then
            headers+=("$2"); shift 2
        else
            bodies+=("$1"); shift
        fi
    done

    TR_RESULT=()
    local ncols=${#bodies[@]}
    (( ncols < 2 )) && return 1

    local tw; tw="$(_tr_term_width)"
    # 3 chars separator between columns: " │ "
    local sep=" │ "
    local sep_len=3
    local total_sep=$(( (ncols - 1) * sep_len ))
    local col_width=$(( (tw - total_sep) / ncols ))
    (( col_width < 10 )) && col_width=10

    # Word-wrap each body into its column
    local -a col_lines=()   # flattened: col_lines[col * max_rows + row]
    local max_rows=0

    local -a col_data=()
    for (( c = 0; c < ncols; c++ )); do
        _tr_wordwrap "${bodies[$c]}" "$col_width"
        local rows_str=""
        for ln in "${_TR_WRAPPED[@]}"; do
            [[ -n "$rows_str" ]] && rows_str+=$'\x01'
            rows_str+="$ln"
        done
        col_data+=("$rows_str")
        (( ${#_TR_WRAPPED[@]} > max_rows )) && max_rows=${#_TR_WRAPPED[@]}
    done

    # Header row if present
    if [[ ${#headers[@]} -gt 0 ]]; then
        local hdr_line=""
        for (( c = 0; c < ncols; c++ )); do
            local h="${headers[$c]:-}"
            local hpad=$(( col_width - ${#h} ))
            (( hpad < 0 )) && hpad=0
            (( c > 0 )) && hdr_line+="$sep"
            hdr_line+="$(printf '%-*s' "$col_width" "$h")"
        done
        TR_RESULT+=("$hdr_line")

        # Header underline
        local hul=""
        for (( c = 0; c < ncols; c++ )); do
            (( c > 0 )) && hul+="─┼─"
            hul+="$(_tr_repeat "─" "$col_width")"
        done
        TR_RESULT+=("$hul")
    fi

    # Content rows
    for (( r = 0; r < max_rows; r++ )); do
        local line=""
        for (( c = 0; c < ncols; c++ )); do
            # Extract row r from col c
            local data="${col_data[$c]}"
            IFS=$'\x01' read -ra col_rows <<< "$data"
            local cell="${col_rows[$r]:-}"
            local cpad=$(( col_width - ${#cell} ))
            (( cpad < 0 )) && cpad=0
            (( c > 0 )) && line+="$sep"
            line+="$(printf '%-*s' "$col_width" "$cell")"
        done
        TR_RESULT+=("$line")
    done
}

columns() {
    _columns_build "$@" || return; _tr_print
}
columns_string() {
    _columns_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  10. BADGES — inline status tags
# ===========================================================================
#  Usage: badges "pass:Build" "fail:Tests" "skip:Lint" "info:v2.1.0"
#         badges "warn:Deprecated" "run:Deploying"
#  Types: pass, fail, warn, skip, info, run, custom

_badges_build() {
    TR_RESULT=()
    [[ $# -eq 0 ]] && return 1

    local line=""
    for entry in "$@"; do
        local type="${entry%%:*}"
        local label="${entry#*:}"

        local icon
        case "$type" in
            pass|ok)      icon="${BRIGHT_GREEN}✔${RESET}" ;;
            fail|error)   icon="${BRIGHT_RED}✖${RESET}" ;;
            warn)         icon="${BRIGHT_YELLOW}⚠${RESET}" ;;
            skip)         icon="${BRIGHT_CYAN}○${RESET}" ;;
            info)         icon="${BRIGHT_BLUE}ℹ${RESET}" ;;
            run|running)  icon="${BRIGHT_MAGENTA}◆${RESET}" ;;
            *)            icon="${BRIGHT_WHITE}●${RESET}" ;;
        esac

        [[ -n "$line" ]] && line+="  "
        line+="[ ${icon} ${label} ]"
    done

    TR_RESULT+=("$line")
}

badges() {
    _badges_build "$@" || return; _tr_print
}
badges_string() {
    _badges_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  11. LIST — bullet and numbered lists with wrapping
# ===========================================================================
#  Usage: list "First item" "Second item" "Third item"
#         list -n "Step one" "Step two"          ← numbered
#         list -s "▸" "Item A" "Item B"          ← custom bullet
#         list "Top level" "  Nested item" "    Deep nested"

_list_build() {
    local style="bullet" bullet="•"
    local items=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n) style="numbered"; shift ;;
            -s) bullet="$2"; style="custom"; shift 2 ;;
            *)  items+=("$1"); shift ;;
        esac
    done

    if [[ ${#items[@]} -eq 0 ]]; then
        while IFS= read -r ln; do
            [[ -n "$ln" ]] && items+=("$ln")
        done
    fi

    TR_RESULT=()
    [[ ${#items[@]} -eq 0 ]] && return 1

    local tw; tw="$(_tr_term_width)"
    local bullets=("•" "◦" "▸" "‣")
    local num=1

    for item in "${items[@]}"; do
        # Detect indent level
        local stripped="${item#"${item%%[![:space:]]*}"}"
        local indent_chars=$(( ${#item} - ${#stripped} ))
        local level=$(( indent_chars / 2 ))

        local prefix_pad=""
        for (( d = 0; d < level; d++ )); do prefix_pad+="  "; done

        local marker
        if [[ "$style" == "numbered" ]]; then
            marker="${num}."
            (( num++ ))
        elif [[ "$style" == "custom" ]]; then
            marker="$bullet"
        else
            marker="${bullets[$level % ${#bullets[@]}]}"
        fi

        local full_prefix="${prefix_pad}${marker} "
        local prefix_len=${#full_prefix}
        local content_width=$(( tw - prefix_len ))
        (( content_width < 10 )) && content_width=10

        _tr_wordwrap "$stripped" "$content_width"

        local first=1
        for wln in "${_TR_WRAPPED[@]}"; do
            if (( first )); then
                TR_RESULT+=("${full_prefix}${wln}")
                first=0
            else
                TR_RESULT+=("$(printf '%*s%s' "$prefix_len" "" "$wln")")
            fi
        done
    done
}

list() {
    if [[ $# -gt 0 ]]; then _list_build "$@"; else _list_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_print
}
list_string() {
    if [[ $# -gt 0 ]]; then _list_build "$@"; else _list_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_to_string
}


# ===========================================================================
#  12. QUOTE — block quote with left bar
# ===========================================================================
#  Usage: quote "To be or not to be, that is the question."
#         quote -a "Shakespeare" "To be or not to be..."
#         echo "some text" | quote

_quote_build() {
    local attribution="" text=""
    local args=()

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-a" ]]; then
            attribution="$2"; shift 2
        else
            args+=("$1"); shift
        fi
    done

    if [[ ${#args[@]} -gt 0 ]]; then
        text="${args[*]}"
    else
        text="$(cat)"
    fi

    TR_RESULT=()
    [[ -z "$text" ]] && return 1

    local tw; tw="$(_tr_term_width)"
    local bar="│"
    local bar_len=2
    local content_width=$(( tw - bar_len - 2 ))
    (( content_width < 20 )) && content_width=20

    _tr_wordwrap "$text" "$content_width"

    TR_RESULT+=("${bar}")
    for ln in "${_TR_WRAPPED[@]}"; do
        TR_RESULT+=("${bar}  ${ln}")
    done

    if [[ -n "$attribution" ]]; then
        TR_RESULT+=("${bar}")
        TR_RESULT+=("${bar}  — ${attribution}")
    fi

    TR_RESULT+=("${bar}")
}

quote() {
    if [[ $# -gt 0 ]]; then _quote_build "$@"; else _quote_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_print
}
quote_string() {
    if [[ $# -gt 0 ]]; then _quote_build "$@"; else _quote_build; fi
    [[ ${#TR_RESULT[@]} -eq 0 ]] && return 1; _tr_to_string
}


# ===========================================================================
#  CLI DISPATCHER
# ===========================================================================

_tr_usage() {
    cat <<'USAGE'
terminal_renderer.sh — pure-bash terminal rendering toolkit

Usage: terminal_renderer.sh <command> [-s] [args...]

Commands:
  box       "message"                        Box with border
  divider   ["label"]                        Horizontal rule
  alert     <info|warn|error|success> "msg"  Callout box
  table     "H1|H2" "r1|r2" ...             Data table
  kv        "Key: Val" ... [-t dots|plain|dashes]
  hbar      "Label:Value" ... [-m max]       Bar chart
  banner    "TEXT"                            Big block letters
  tree      "root" "  child" ...             Tree hierarchy
  columns   [-h "Hdr"] "col1" "col2" ...     Side-by-side
  badges    "pass:Build" "fail:Test" ...      Status tags
  list      [-n] [-s "▸"] "item" ...         Bullet/numbered
  quote     [-a "Author"] "text"             Block quote

Flags:
  -s    String mode — returns \n-joined string, no stdout
USAGE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    [[ $# -eq 0 ]] && { _tr_usage; exit 0; }

    cmd="$1"; shift
    string_mode=0
    args=()

    for arg in "$@"; do
        [[ "$arg" == "-s" ]] && string_mode=1 && continue
        args+=("$arg")
    done

    # Map to function
    case "$cmd" in
        box|divider|alert|table|kv|hbar|banner|tree|columns|badges|list|quote)
            if (( string_mode )); then
                "${cmd}_string" "${args[@]}"
            else
                "$cmd" "${args[@]}"
            fi
            ;;
        help|-h|--help) _tr_usage ;;
        *)
            echo "Unknown command: $cmd" >&2
            _tr_usage >&2
            exit 1
            ;;
    esac
fi