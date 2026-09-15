#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
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
# ║  Commands: box, divider, alert, table, kv, hbar, gauge, sparkline,      ║
# ║            vbar, linechart, csv_hbar, csv_vbar, csv_linechart, banner,   ║
# ║            tree, columns, badges, list, quote                            ║
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

# Default color cycle used by multi-series/multi-bar charts when the user
# doesn't pass an explicit -c list.
_TR_DEFAULT_PALETTE=(CYAN MAGENTA GREEN YELLOW BLUE RED BRIGHT_CYAN BRIGHT_MAGENTA BRIGHT_GREEN BRIGHT_YELLOW)

# Resolve a color name (e.g. "RED", "bright_cyan") to its escape sequence.
# Accepts a raw escape sequence too (passed through unchanged).
# Unknown names resolve to "" (no color).
_tr_resolve_color() {
    local name="$1"
    [[ -z "$name" ]] && { printf ''; return; }
    if [[ "$name" == *$'\033'* ]]; then printf '%s' "$name"; return; fi
    local varname="${name^^}"
    if [[ -n "${!varname+x}" ]]; then
        printf '%s' "${!varname}"
    else
        printf ''
    fi
}

# Split a comma-separated -c argument into the _TR_COLORS array.
# Falls back to _TR_DEFAULT_PALETTE when no argument was given.
_tr_colors_or_default() {
    local arg="$1"
    if [[ -n "$arg" ]]; then
        IFS=',' read -ra _TR_COLORS <<< "$arg"
    else
        _TR_COLORS=("${_TR_DEFAULT_PALETTE[@]}")
    fi
}

# Resample a value series to exactly _TR_RESAMPLE_TARGET points via
# nearest-neighbor mapping, so a chart can be pinned to a fixed width
# regardless of how many samples the caller actually has (fewer samples
# get stretched, more get thinned) — first/last points always map through
# unchanged. Input in _TR_RESAMPLE_IN, output in _TR_RESAMPLE_OUT.
_tr_resample() {
    local target="$1"
    local -a in=("${_TR_RESAMPLE_IN[@]}")
    local n=${#in[@]}
    _TR_RESAMPLE_OUT=()
    (( n == 0 || target <= 0 )) && return
    if (( target == n )); then
        _TR_RESAMPLE_OUT=("${in[@]}")
        return
    fi
    local i idx
    for (( i = 0; i < target; i++ )); do
        if (( target == 1 || n == 1 )); then
            idx=0
        else
            idx=$(( i * (n - 1) / (target - 1) ))
        fi
        _TR_RESAMPLE_OUT+=("${in[$idx]}")
    done
}

# Parse a simple "label,value,label,value" CSV-like file into _TR_CSV_ROWS,
# one entry per row with fields joined by \x01. Blank lines are skipped and
# fields are whitespace-trimmed.
_tr_csv_parse() {
    local file="$1" delim="${2:-,}"
    _TR_CSV_ROWS=()
    [[ -f "$file" ]] || return 1

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        local -a fields=()
        IFS="$delim" read -ra fields <<< "$line"
        for i in "${!fields[@]}"; do
            local f="${fields[$i]}"
            f="${f#"${f%%[![:space:]]*}"}"
            f="${f%"${f##*[![:space:]]}"}"
            fields[$i]="$f"
        done
        _TR_CSV_ROWS+=("$(IFS=$'\x01'; printf '%s' "${fields[*]}")")
    done < "$file"

    [[ ${#_TR_CSV_ROWS[@]} -eq 0 ]] && return 1
    return 0
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

    # 1. Expand user escape sequences (like \e, \n, \t) into raw bytes immediately.
    # This ensures _tr_wordwrap and _tr_visible_len evaluate the actual ANSI codes.
    msg="$(printf '%b' "$msg")"

    local icon label
    case "$type" in
        info)    icon="${BOLD}${CYAN}ℹ${RESET}"; label="INFO"    ;;
        warn)    icon="${BOLD}${YELLOW}⚠${RESET}"; label="WARNING" ;;
        error)   icon="${BOLD}${RED}✖${RESET}"; label="ERROR"   ;;
        success) icon="${BOLD}${GREEN}✔${RESET}"; label="SUCCESS" ;;
        *)       icon="●"; label="${type^^}" ;;
    esac

    # Expand the icons and labels so literal '\e' codes become real 0-width ESC bytes
    icon="$(printf '%b' "$icon")"
    label="$(printf '%b' "$label")"

    local tw; tw="$(_tr_term_width)"
    local chrome=4 min_inner=36
    local max_inner=$(( tw - chrome ))
    (( max_inner < min_inner )) && max_inner=$min_inner

    _tr_wordwrap "$msg" "$max_inner"

    local longest=0
    for ln in "${_TR_WRAPPED[@]}"; do
        local ln_len="$(_tr_visible_len "$ln")"
        (( ln_len > longest )) && longest=$ln_len
    done
    
    local icon_len="$(_tr_visible_len "$icon")"
    local label_len="$(_tr_visible_len "$label")"
    local header_len=$(( icon_len + 1 + label_len ))
    
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
        local ln_len="$(_tr_visible_len "$ln")"
        local pad=$(( inner - ln_len ))
        # 2. Add ${RESET} before the padding. If the user passes unclosed 
        # color sequences, this stops the color from bleeding into the right border.
        TR_RESULT+=("$(printf '┃ %s%b%*s ┃' "$ln" "${RESET:-\e[0m}" "$pad" "")")
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
#         hbar -n 0 -m 100 "A:30" "B:90"  ← explicit min+max (baseline other than 0)
#         hbar -w 50 "X:40" "Y:60"        ← fixed bar area width
#         hbar -lw 12 "X:40" "LongLabel:60"  ← fixed label column width (pad/truncate)
#         hbar -c "GREEN" "A:30" "B:90"          ← single color for all bars
#         hbar -c "GREEN,YELLOW,RED" "A:30" "B:90" "C:10"  ← per-bar colors
#  Delimiter between label and value is : by default, override with -d.
#  No color is applied unless -c is given (keeps plain output for embedding
#  in tables/columns where escape codes would break alignment).
#  Pass both -m and -lw (and -w) with a fixed value across calls to get an
#  identically-sized chart every render regardless of the data/labels that
#  particular call happens to have — see linechart/vbar for the same idea.

_hbar_build() {
    local delim=":" max_val="" min_val=0 bar_width=0 label_width=0 color_arg=""
    local entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)  delim="$2"; shift 2 ;;
            -m)  max_val="$2"; shift 2 ;;
            -n)  min_val="$2"; shift 2 ;;
            -w)  bar_width="$2"; shift 2 ;;
            -lw) label_width="$2"; shift 2 ;;
            -c)  color_arg="$2"; shift 2 ;;
            *)   entries+=("$1"); shift ;;
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
    local auto_max=""

    for entry in "${entries[@]}"; do
        local label="${entry%%${delim}*}"
        local val="${entry#*${delim}}"
        labels+=("$label")
        values+=("$val")
        (( ${#label} > max_label )) && max_label=${#label}
        [[ -z "$auto_max" || "$val" -gt "$auto_max" ]] && auto_max=$val
    done

    [[ -z "$max_val" ]] && max_val=$auto_max
    (( max_val == min_val )) && max_val=$(( min_val + 1 ))

    (( label_width > 0 )) && max_label=$label_width

    local tw; tw="$(_tr_term_width)"
    # bar_width: label + " " + bar + " " + value(up to 7 chars)
    if (( bar_width == 0 )); then
        bar_width=$(( tw - max_label - 10 ))
        (( bar_width < 10 )) && bar_width=10
        (( bar_width > 60 )) && bar_width=60
    fi

    local -a colors=()
    [[ -n "$color_arg" ]] && IFS=',' read -ra colors <<< "$color_arg"

    local span=$(( max_val - min_val ))
    for (( i = 0; i < ${#labels[@]}; i++ )); do
        local l="${labels[$i]}" v="${values[$i]}"
        (( label_width > 0 && ${#l} > label_width )) && l="${l:0:label_width}"

        local clamped=$v
        (( clamped < min_val )) && clamped=$min_val
        (( clamped > max_val )) && clamped=$max_val
        local filled=$(( (clamped - min_val) * bar_width / span ))
        local empty=$(( bar_width - filled ))

        local bar_full; bar_full="$(_tr_repeat "█" "$filled")"
        local bar_empty; bar_empty="$(_tr_repeat "░" "$empty")"

        if [[ ${#colors[@]} -gt 0 ]]; then
            local colval; colval="$(_tr_resolve_color "${colors[$(( i % ${#colors[@]} ))]}")"
            TR_RESULT+=("$(printf '%-*s %b%s%b%s %s' "$max_label" "$l" "$colval" "$bar_full" "$RESET" "$bar_empty" "$v")")
        else
            TR_RESULT+=("$(printf '%-*s %s%s %s' "$max_label" "$l" "$bar_full" "$bar_empty" "$v")")
        fi
    done
}

hbar() {
    _hbar_build "$@" || return; _tr_print
}
hbar_string() {
    _hbar_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6b. GAUGE — single-value meter (single-element chart)
# ===========================================================================
#  Usage: gauge 72                          → auto-colored (red/yellow/green)
#         gauge -l "CPU" 85                 → with label
#         gauge -m 200 150                  → explicit max (default 100)
#         gauge -n 10 -m 200 150            → explicit min+max (default min 0)
#         gauge -c CYAN 60                  → force a color
#         gauge -w 40 72                    → bar area width (default 30)
#         gauge -lw 8 -l "RAM" 72           → fixed label-column width, so
#                                              lines stay the same length
#                                              across different labels
#  Without -c, color is chosen by threshold: <40 red, <70 yellow, else green.
#  Pass -w (and -lw, if using labels) with a fixed value across refreshes to
#  get a gauge that's exactly the same width every render.

_gauge_build() {
    local color="" width=30 label="" label_width=0 max=100 min=0 value=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c)  color="$2"; shift 2 ;;
            -w)  width="$2"; shift 2 ;;
            -l)  label="$2"; shift 2 ;;
            -lw) label_width="$2"; shift 2 ;;
            -m)  max="$2"; shift 2 ;;
            -n)  min="$2"; shift 2 ;;
            *)   value="$1"; shift ;;
        esac
    done

    TR_RESULT=()
    [[ -z "$value" ]] && return 1
    (( max == min )) && max=$(( min + 1 ))

    local clamped=$value
    (( clamped < min )) && clamped=$min
    (( clamped > max )) && clamped=$max
    local pct=$(( (clamped - min) * 100 / (max - min) ))

    local col
    if [[ -n "$color" ]]; then
        col="$(_tr_resolve_color "$color")"
    elif (( pct >= 70 )); then
        col="$GREEN"
    elif (( pct >= 40 )); then
        col="$YELLOW"
    else
        col="$RED"
    fi

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_full; bar_full="$(_tr_repeat "█" "$filled")"
    local bar_empty; bar_empty="$(_tr_repeat "░" "$empty")"

    local prefix=""
    if [[ -n "$label" ]]; then
        if (( label_width > 0 )); then
            prefix="$(printf '%-*s ' "$label_width" "$label")"
        else
            prefix="${label} "
        fi
    fi

    TR_RESULT+=("$(printf '%s[%b%s%b%s] %3d%%' "$prefix" "$col" "$bar_full" "$RESET" "$bar_empty" "$pct")")
}

gauge() {
    _gauge_build "$@" || return; _tr_print
}
gauge_string() {
    _gauge_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6c. SPARKLINE — single-line mini chart from a series of numbers
# ===========================================================================
#  Usage: sparkline "3 5 8 2 9 4"
#         sparkline -d "," "1,4,2,8,5,9,3"
#         sparkline -c CYAN "1 4 2 8 5"
#         sparkline -w 20 "1 4 2 8 5"      ← resampled to exactly 20 chars,
#                                             however many values were given
#         sparkline -n 0 -m 100 "40 55 62" ← fixed scale instead of auto-range
#         printf "3\n5\n8\n2\n" | sparkline
#  Single-element chart — one line of block characters scaled to the range
#  of the data. No color by default; pass -c to color it. Pass -w with a
#  fixed value across refreshes to keep it a constant width regardless of
#  how many samples are fed in each time (fills available space).

_sparkline_build() {
    local color="" delim=" " data="" width=0 max_val="" min_val=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c) color="$2"; shift 2 ;;
            -d) delim="$2"; shift 2 ;;
            -w) width="$2"; shift 2 ;;
            -m) max_val="$2"; shift 2 ;;
            -n) min_val="$2"; shift 2 ;;
            *)  data="$1"; shift ;;
        esac
    done

    if [[ -z "$data" && ! -t 0 ]]; then
        data="$(cat | tr '\n' ' ')"
        delim=" "
    fi

    TR_RESULT=()
    [[ -z "$data" ]] && return 1

    local -a values=()
    IFS="$delim" read -ra values <<< "$data"
    [[ ${#values[@]} -eq 0 ]] && return 1

    if (( width > 0 )); then
        _TR_RESAMPLE_IN=("${values[@]}")
        _tr_resample "$width"
        values=("${_TR_RESAMPLE_OUT[@]}")
    fi

    local levels=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
    local min="$min_val" max="$max_val"
    for v in "${values[@]}"; do
        [[ -z "$min" || "$v" -lt "$min" ]] && min=$v
        [[ -z "$max" || "$v" -gt "$max" ]] && max=$v
    done
    local range=$(( max - min ))
    (( range == 0 )) && range=1

    local out=""
    for v in "${values[@]}"; do
        local clamped=$v
        (( clamped < min )) && clamped=$min
        (( clamped > max )) && clamped=$max
        local idx=$(( (clamped - min) * (${#levels[@]} - 1) / range ))
        out+="${levels[$idx]}"
    done

    if [[ -n "$color" ]]; then
        local colval; colval="$(_tr_resolve_color "$color")"
        TR_RESULT+=("$(printf '%b%s%b' "$colval" "$out" "$RESET")")
    else
        TR_RESULT+=("$out")
    fi
}

sparkline() {
    _sparkline_build "$@" || return; _tr_print
}
sparkline_string() {
    _sparkline_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6d. VBAR — vertical bar / column chart (single or multiple columns)
# ===========================================================================
#  Usage: vbar "CPU:72"                              ← single column
#         vbar "Q1:60" "Q2:72" "Q3:98" "Q4:85"        ← multiple columns
#         vbar -h 12 "A:30" "B:90"                    ← chart height in rows
#         vbar -n 0 -m 100 "A:30" "B:90"              ← fixed min/max scale
#         vbar -c "GREEN,YELLOW,RED" "A:30" "B:90" "C:10"
#         vbar -cw 5 "A:30" "B:90"                    ← fixed column width
#         vbar -tw 40 "A:30" "B:90" "C:10"            ← fixed TOTAL width,
#                                                         columns divide it evenly
#  Colored with the default palette unless -c overrides it. Pass -h and
#  either -cw or -tw with fixed values across refreshes (e.g. sized from
#  the pane's actual dimensions) to get a chart that always renders at
#  exactly the same size and fills the available space, regardless of how
#  the data/labels happen to look that particular call.

_vbar_build() {
    local delim=":" height=8 max_val="" min_val=0 color_arg="" total_width=0 col_width_arg=0
    local entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)  delim="$2"; shift 2 ;;
            -h)  height="$2"; shift 2 ;;
            -m)  max_val="$2"; shift 2 ;;
            -n)  min_val="$2"; shift 2 ;;
            -c)  color_arg="$2"; shift 2 ;;
            -tw) total_width="$2"; shift 2 ;;
            -cw) col_width_arg="$2"; shift 2 ;;
            *)   entries+=("$1"); shift ;;
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
    local auto_max=""
    for entry in "${entries[@]}"; do
        local label="${entry%%${delim}*}"
        local val="${entry#*${delim}}"
        labels+=("$label"); values+=("$val")
        [[ -z "$auto_max" || "$val" -gt "$auto_max" ]] && auto_max=$val
    done
    [[ -z "$max_val" ]] && max_val=$auto_max
    (( max_val == min_val )) && max_val=$(( min_val + 1 ))

    local -a colors=()
    _tr_colors_or_default "$color_arg"
    colors=("${_TR_COLORS[@]}")

    local n=${#labels[@]}
    local col_width=0
    if (( col_width_arg > 0 )); then
        col_width=$col_width_arg
    elif (( total_width > 0 )); then
        col_width=$(( (total_width - (n - 1)) / n ))
        (( col_width < 1 )) && col_width=1
    else
        for l in "${labels[@]}"; do (( ${#l} > col_width )) && col_width=${#l}; done
        for v in "${values[@]}"; do (( ${#v} > col_width )) && col_width=${#v}; done
        (( col_width < 3 )) && col_width=3
    fi

    local span=$(( max_val - min_val ))
    local -a heights=()
    for v in "${values[@]}"; do
        local clamped=$v
        (( clamped < min_val )) && clamped=$min_val
        (( clamped > max_val )) && clamped=$max_val
        local h=$(( (clamped - min_val) * height / span ))
        (( h == 0 && clamped > min_val )) && h=1
        heights+=("$h")
    done

    for (( r = height; r >= 1; r-- )); do
        local row=""
        for (( i = 0; i < n; i++ )); do
            local colval; colval="$(_tr_resolve_color "${colors[$(( i % ${#colors[@]} ))]}")"
            local cell
            if (( heights[i] >= r )); then
                cell="$(_tr_repeat "█" "$col_width")"
                [[ -n "$colval" ]] && cell="$(printf '%b%s%b' "$colval" "$cell" "$RESET")"
            else
                cell="$(_tr_repeat " " "$col_width")"
            fi
            (( i > 0 )) && row+=" "
            row+="$cell"
        done
        TR_RESULT+=("$row")
    done

    local base=""
    for (( i = 0; i < n; i++ )); do
        (( i > 0 )) && base+=" "
        base+="$(_tr_repeat "─" "$col_width")"
    done
    TR_RESULT+=("$base")

    local lbl_row=""
    for (( i = 0; i < n; i++ )); do
        (( i > 0 )) && lbl_row+=" "
        local l="${labels[$i]}"
        (( ${#l} > col_width )) && l="${l:0:col_width}"
        local pad=$(( col_width - ${#l} ))
        local lp=$(( pad / 2 )) rp=$(( pad - pad / 2 ))
        lbl_row+="$(_tr_repeat " " "$lp")${l}$(_tr_repeat " " "$rp")"
    done
    TR_RESULT+=("$lbl_row")

    local val_row=""
    for (( i = 0; i < n; i++ )); do
        (( i > 0 )) && val_row+=" "
        local v="${values[$i]}"
        (( ${#v} > col_width )) && v="${v:0:col_width}"
        local pad=$(( col_width - ${#v} ))
        (( pad < 0 )) && pad=0
        local lp=$(( pad / 2 )) rp=$(( pad - pad / 2 ))
        val_row+="$(_tr_repeat " " "$lp")${v}$(_tr_repeat " " "$rp")"
    done
    TR_RESULT+=("$val_row")
}

vbar() {
    _vbar_build "$@" || return; _tr_print
}
vbar_string() {
    _vbar_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6e. LINECHART — multi-series line/point chart
# ===========================================================================
#  Usage: linechart "CPU:10,20,15,30,45,40"
#         linechart "CPU:10,20,15,30" "Mem:40,42,41,45"
#         linechart -h 12 -c "GREEN,RED" "A:1,5,3,8" "B:8,4,6,2"
#         linechart -m 100 -n 0 "Load:20,55,80,60"     ← fixed y-axis range
#         linechart -w 30 "Load:20,55,80,60"           ← fixed plot width;
#                                                          each series is
#                                                          resampled to
#                                                          exactly 30 points
#  Plots each series as points against a shared y-axis, colored with the
#  default palette unless -c overrides it. A legend is printed below.
#  Without -w, plot width tracks the longest series (so it grows/shrinks
#  as a live history buffer fills up); pass -w with a fixed value (e.g.
#  sized from the pane's actual width) to keep the chart a constant size
#  and fill the available space regardless of how much history exists yet.

_linechart_build() {
    local height=10 max_val="" min_val="" color_arg="" plot_width=0
    local -a series_labels=() series_data=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h) height="$2"; shift 2 ;;
            -m) max_val="$2"; shift 2 ;;
            -n) min_val="$2"; shift 2 ;;
            -c) color_arg="$2"; shift 2 ;;
            -w) plot_width="$2"; shift 2 ;;
            *)
                series_labels+=("${1%%:*}")
                series_data+=("${1#*:}")
                shift ;;
        esac
    done

    TR_RESULT=()
    [[ ${#series_labels[@]} -eq 0 ]] && return 1

    _tr_colors_or_default "$color_arg"
    local -a colors=("${_TR_COLORS[@]}")

    local -a parsed=()
    local width=0
    for vals in "${series_data[@]}"; do
        local -a arr=()
        IFS=',' read -ra arr <<< "$vals"
        if (( plot_width > 0 )); then
            _TR_RESAMPLE_IN=("${arr[@]}")
            _tr_resample "$plot_width"
            arr=("${_TR_RESAMPLE_OUT[@]}")
        fi
        (( ${#arr[@]} > width )) && width=${#arr[@]}
        parsed+=("$(IFS=$'\x01'; printf '%s' "${arr[*]}")")
    done
    (( width == 0 )) && return 1

    local gmin="" gmax=""
    for pd in "${parsed[@]}"; do
        local -a arr=()
        IFS=$'\x01' read -ra arr <<< "$pd"
        for v in "${arr[@]}"; do
            [[ -z "$gmin" || "$v" -lt "$gmin" ]] && gmin=$v
            [[ -z "$gmax" || "$v" -gt "$gmax" ]] && gmax=$v
        done
    done
    [[ -n "$min_val" ]] && gmin=$min_val
    [[ -n "$max_val" ]] && gmax=$max_val
    (( gmax == gmin )) && gmax=$(( gmin + 1 ))

    local rows=$height
    local total=$(( rows * width ))
    local -a grid=() gridcolor=()
    for (( k = 0; k < total; k++ )); do grid[$k]=" "; gridcolor[$k]=""; done

    local marker="●"
    for (( s = 0; s < ${#parsed[@]}; s++ )); do
        local -a arr=()
        IFS=$'\x01' read -ra arr <<< "${parsed[$s]}"
        local colval; colval="$(_tr_resolve_color "${colors[$(( s % ${#colors[@]} ))]}")"
        for (( x = 0; x < ${#arr[@]}; x++ )); do
            local v="${arr[$x]}"
            local row=$(( (gmax - v) * (rows - 1) / (gmax - gmin) ))
            (( row < 0 )) && row=0
            (( row >= rows )) && row=$(( rows - 1 ))
            local idx=$(( row * width + x ))
            grid[$idx]="$marker"
            gridcolor[$idx]="$colval"
        done
    done

    local label_width=${#gmax}
    (( ${#gmin} > label_width )) && label_width=${#gmin}

    for (( r = 0; r < rows; r++ )); do
        local yval=""
        (( r == 0 )) && yval=$gmax
        (( r == rows - 1 )) && yval=$gmin
        local line; line="$(printf '%*s │' "$label_width" "$yval")"
        for (( x = 0; x < width; x++ )); do
            local idx=$(( r * width + x ))
            local ch="${grid[$idx]}" cv="${gridcolor[$idx]}"
            if [[ -n "$cv" && "$ch" != " " ]]; then
                line+="$(printf '%b%s%b' "$cv" "$ch" "$RESET")"
            else
                line+="$ch"
            fi
        done
        TR_RESULT+=("$line")
    done

    TR_RESULT+=("$(_tr_repeat " " "$label_width") └$(_tr_repeat "─" "$width")")

    local legend=""
    for (( s = 0; s < ${#series_labels[@]}; s++ )); do
        local colval; colval="$(_tr_resolve_color "${colors[$(( s % ${#colors[@]} ))]}")"
        (( s > 0 )) && legend+="  "
        legend+="$(printf '%b%s%b %s' "$colval" "$marker" "$RESET" "${series_labels[$s]}")"
    done
    TR_RESULT+=("$legend")
}

linechart() {
    _linechart_build "$@" || return; _tr_print
}
linechart_string() {
    _linechart_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  6f. CSV-DRIVEN CHARTS — build multi-element graphs straight from a CSV file
# ===========================================================================
#  csv_hbar / csv_vbar expect rows of "label,value" (no header by default):
#    label,value
#    Q1,60
#    Q2,72
#  Usage: csv_hbar data.csv
#         csv_hbar -d ";" --header data.csv     ← skip a header row
#         csv_hbar -c "GREEN,YELLOW,RED" data.csv
#         csv_vbar -h 12 data.csv
#
#  csv_linechart expects a header row naming each series, first column is
#  the x-axis label (kept for future use, not currently plotted):
#    x,CPU,Memory
#    t0,10,40
#    t1,20,42
#  Usage: csv_linechart data.csv
#         csv_linechart -h 12 -c "GREEN,RED" data.csv

_csv_hbar_build() {
    local file="" delim="," header=0
    local -a extra=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) delim="$2"; shift 2 ;;
            --header) header=1; shift ;;
            -c)  extra+=("-c" "$2"); shift 2 ;;
            -m)  extra+=("-m" "$2"); shift 2 ;;
            -n)  extra+=("-n" "$2"); shift 2 ;;
            -w)  extra+=("-w" "$2"); shift 2 ;;
            -lw) extra+=("-lw" "$2"); shift 2 ;;
            *)   file="$1"; shift ;;
        esac
    done

    TR_RESULT=()
    [[ -z "$file" ]] && return 1
    _tr_csv_parse "$file" "$delim" || return 1

    local -a entries=()
    local start=0
    (( header )) && start=1
    for (( i = start; i < ${#_TR_CSV_ROWS[@]}; i++ )); do
        local -a f=()
        IFS=$'\x01' read -ra f <<< "${_TR_CSV_ROWS[$i]}"
        entries+=("${f[0]}:${f[1]}")
    done

    _hbar_build "${extra[@]}" "${entries[@]}"
}

csv_hbar() {
    _csv_hbar_build "$@" || return; _tr_print
}
csv_hbar_string() {
    _csv_hbar_build "$@" || return; _tr_to_string
}

_csv_vbar_build() {
    local file="" delim="," header=0
    local -a extra=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) delim="$2"; shift 2 ;;
            --header) header=1; shift ;;
            -c)  extra+=("-c" "$2"); shift 2 ;;
            -h)  extra+=("-h" "$2"); shift 2 ;;
            -m)  extra+=("-m" "$2"); shift 2 ;;
            -n)  extra+=("-n" "$2"); shift 2 ;;
            -tw) extra+=("-tw" "$2"); shift 2 ;;
            -cw) extra+=("-cw" "$2"); shift 2 ;;
            *)   file="$1"; shift ;;
        esac
    done

    TR_RESULT=()
    [[ -z "$file" ]] && return 1
    _tr_csv_parse "$file" "$delim" || return 1

    local -a entries=()
    local start=0
    (( header )) && start=1
    for (( i = start; i < ${#_TR_CSV_ROWS[@]}; i++ )); do
        local -a f=()
        IFS=$'\x01' read -ra f <<< "${_TR_CSV_ROWS[$i]}"
        entries+=("${f[0]}:${f[1]}")
    done

    _vbar_build "${extra[@]}" "${entries[@]}"
}

csv_vbar() {
    _csv_vbar_build "$@" || return; _tr_print
}
csv_vbar_string() {
    _csv_vbar_build "$@" || return; _tr_to_string
}

_csv_linechart_build() {
    local file="" delim=","
    local -a extra=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) delim="$2"; shift 2 ;;
            -h) extra+=("-h" "$2"); shift 2 ;;
            -c) extra+=("-c" "$2"); shift 2 ;;
            -m) extra+=("-m" "$2"); shift 2 ;;
            -n) extra+=("-n" "$2"); shift 2 ;;
            -w) extra+=("-w" "$2"); shift 2 ;;
            *)  file="$1"; shift ;;
        esac
    done

    TR_RESULT=()
    [[ -z "$file" ]] && return 1
    _tr_csv_parse "$file" "$delim" || return 1
    (( ${#_TR_CSV_ROWS[@]} < 2 )) && return 1

    local -a header=()
    IFS=$'\x01' read -ra header <<< "${_TR_CSV_ROWS[0]}"
    local ncols=${#header[@]}
    (( ncols < 2 )) && return 1

    local -a series_vals=()
    for (( c = 1; c < ncols; c++ )); do series_vals[$c]=""; done

    for (( i = 1; i < ${#_TR_CSV_ROWS[@]}; i++ )); do
        local -a f=()
        IFS=$'\x01' read -ra f <<< "${_TR_CSV_ROWS[$i]}"
        for (( c = 1; c < ncols; c++ )); do
            [[ -n "${series_vals[$c]}" ]] && series_vals[$c]+=","
            series_vals[$c]+="${f[$c]:-0}"
        done
    done

    local -a series_args=()
    for (( c = 1; c < ncols; c++ )); do
        series_args+=("${header[$c]}:${series_vals[$c]}")
    done

    _linechart_build "${extra[@]}" "${series_args[@]}"
}

csv_linechart() {
    _csv_linechart_build "$@" || return; _tr_print
}
csv_linechart_string() {
    _csv_linechart_build "$@" || return; _tr_to_string
}


# ===========================================================================
#  7. BANNER — big block-letter text (5-high font)
# ===========================================================================
#  Usage: banner "HELLO"
#  Supports A-Z, 0-9, space, and common punctuation.

declare -gA _BANNER_FONT
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
  hbar      "Label:Value" ... [-m max] [-n min] [-w width] [-lw label_width] [-c "COLOR,..."]
  vbar      "Label:Value" ... [-h rows] [-m max] [-n min] [-tw total_width] [-cw col_width] [-c "COLOR,..."]
  gauge     <value> [-m max] [-n min] [-l label] [-lw label_width] [-w width] [-c COLOR]
  sparkline "v1 v2 v3 ..." [-d delim] [-w width] [-m max] [-n min] [-c COLOR]
  linechart "Series:v1,v2,.." ... [-h rows] [-w plot_width] [-m max] [-n min] [-c "C,.."]
  csv_hbar      <file.csv> [--header] [-d delim] [-m max] [-n min] [-w width] [-lw label_width] [-c "C,.."]
  csv_vbar      <file.csv> [--header] [-h rows] [-m max] [-n min] [-tw total_width] [-cw col_width] [-c "C,.."]
  csv_linechart <file.csv> [-h rows] [-w plot_width] [-m max] [-n min] [-c "C,.."]
  banner    "TEXT"                            Big block letters
  tree      "root" "  child" ...             Tree hierarchy
  columns   [-h "Hdr"] "col1" "col2" ...     Side-by-side
  badges    "pass:Build" "fail:Test" ...      Status tags
  list      [-n] [-s "▸"] "item" ...         Bullet/numbered
  quote     [-a "Author"] "text"             Block quote

Coloring:
  Chart commands accept -c with color name(s) matching bin/colors.sh vars
  (e.g. RED, BRIGHT_CYAN, DIM_YELLOW), comma-separated for multiple
  bars/series. hbar and sparkline are uncolored by default (safe to embed
  in tables); vbar, linechart and gauge apply sensible defaults
  automatically when -c is omitted.

Fixed-size / fill-available-space charts:
  Every chart above accepts -m/-n (explicit max/min, instead of scaling to
  whatever that particular call's data happens to contain) and a sizing
  flag — -w/-h/-tw/-cw/-lw depending on the chart — so it can be pinned to
  an exact, unchanging size (e.g. computed once from a pane's real
  dimensions via `tui.content_area`) instead of resizing itself between
  refreshes as the data changes. linechart/sparkline resample their data
  to fit -w exactly, rather than growing one column per sample, so a live
  history buffer that's still filling up already renders at full width.
  See config/monitor_callbacks.sh for a live example driving all four.

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
        box|divider|alert|table|kv|hbar|vbar|gauge|sparkline|linechart|csv_hbar|csv_vbar|csv_linechart|banner|tree|columns|badges|list|quote)
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