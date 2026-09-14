#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  tui.sh — Terminal UI & Background Execution Framework                     ║
# ║                                                                          ║
# ║  Built on terminal_controls.sh + colors.sh                               ║
# ║  Provides: weighted layout panes, buttons, input fields, labels,         ║
# ║  mouse click routing, Tab/Shift-Tab focus cycling, and live              ║
# ║  background process streaming with pseudo-terminal (PTY) support.        ║
# ║                                                                          ║
# ║  Usage:                                                                  ║
# ║    source tui.sh                                                         ║
# ║                                                                          ║
# ║    tui.init                                                              ║
# ║    tui.hsplit "root" "main:75" "sidebar:25"                              ║
# ║    tui.exec "ping google.com" "main" "sidebar"                           ║
# ║    tui.run                                                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/terminal_controls.sh"
source "${SCRIPT_DIR}/colors.sh"
source "${SCRIPT_DIR}/tui_markup.sh"
source "${SCRIPT_DIR}/tui_style.sh"

# ═══════════════════════════════════════════════════════════════════════
#  INPUT TUNABLES — override any of these (after sourcing, before tui.run)
#  to trade responsiveness for CPU usage or vice versa. None of this is
#  "private" framework state, so it's plain TUI_*, not _TUI_*.
# ═══════════════════════════════════════════════════════════════════════

# How long the main loop blocks waiting for the first byte of the next
# input event. Lower = more responsive to a live tui.exec tick, higher =
# less idle CPU. Two knobs because a live tick function (a running
# tui.exec process) wants to be polled more eagerly than a fully idle UI.
declare -g TUI_INPUT_POLL_TIMEOUT=0.05   # used while _TUI_TICK_FN is set
declare -g TUI_INPUT_IDLE_TIMEOUT=0.2    # used otherwise

# How long to wait for each subsequent byte while assembling an escape
# sequence that's already begun (arrow keys, SGR mouse reports, …).
declare -g TUI_ESCSEQ_BYTE_TIMEOUT=0.01

# Mouse-motion coalescing (see _tui._coalesce_mouse_motion): once a pure
# hover/drag motion report is decoded, the loop peeks ahead for more
# already-buffered motion before resolving hover state or drawing anything,
# so a fast sweep resolves/redraws once against the newest position instead
# of once per crossed cell. TUI_MOUSE_DRAIN_PEEK_TIMEOUT is how long each
# peek waits for the next byte. It can NOT be 0: bash documents `read -t 0`
# as a pure availability probe that reports success but never actually
# consumes the byte, so a 0 timeout here would silently drain nothing every
# time. A tiny nonzero value (the default) still returns in about a
# millisecond when a byte is already sitting in the buffer — raise it only
# to make the eventual "buffer's empty, stop draining" timeout more
# forgiving on a laggy pty. TUI_MOUSE_DRAIN_MAX caps how many motion reports
# one pass will collapse, purely as a safety net against an unbroken flood
# starving the rest of the loop.
declare -g TUI_MOUSE_DRAIN_PEEK_TIMEOUT=0.001
declare -g TUI_MOUSE_DRAIN_MAX=200

# ═══════════════════════════════════════════════════════════════════════
#  INTERNAL STATE (UI & LAYOUT)
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_P_ROW=()  _TUI_P_COL=()
declare -gA _TUI_P_H=()    _TUI_P_W=()
declare -gA _TUI_P_DIR=()      
declare -gA _TUI_P_CHILDREN=() 
declare -gA _TUI_P_WEIGHTS=()  
declare -gA _TUI_P_TITLE=()    
declare -gA _TUI_P_BORDER=()   
declare -gA _TUI_P_ALIGN=()    
declare -gA _TUI_P_VALIGN=()   
declare -gA _TUI_P_MINW=() _TUI_P_MINH=()
declare -gA _TUI_P_MAXW=() _TUI_P_MAXH=()
declare -ga _TUI_P_LEAVES=()
declare -ga _TUI_P_ALL=()
declare -gA _TUI_P_CONTENT=()
declare -gA _TUI_P_SCROLL=()
declare -gA _TUI_P_SOFF_V=()
declare -gA _TUI_P_SOFF_H=()
declare -g _TUI_DRAG_PANE=""
declare -g _TUI_DRAG_AXIS=""
declare -gA _TUI_P_LINES=()
declare -gA _TUI_P_MAX_W=()

declare -gA _TUI_W_TYPE=()     
declare -gA _TUI_W_PANE=()     
declare -gA _TUI_W_ROW=()      
declare -gA _TUI_W_LABEL=()    
declare -gA _TUI_W_VALUE=()    
declare -gA _TUI_W_ACTION=()   
declare -gA _TUI_W_SUBMIT=()  
declare -gA _TUI_W_PH=()       
declare -gA _TUI_W_ALIGN=()    
declare -gA _TUI_W_VALIGN=()   
declare -gA _TUI_W_MINW=() _TUI_W_MAXW=()
declare -gA _TUI_W_LABEL_ALIGN=()
declare -gA _TUI_W_LABEL_WIDTH=()
declare -ga _TUI_W_ORDER=()    
declare -ga _TUI_FOCUSABLE=()  

declare -g  _TUI_FOCUS_ID=""
declare -g  _TUI_FOCUS_IDX=-1
declare -g  _TUI_CURSOR=0      
declare -g  _TUI_RUNNING=0
declare -g  _TUI_OLD_STTY=""
declare -g  _TUI_ROWS=0
declare -g  _TUI_COLS=0
declare -g  _WSR=0 _WSC=0 _WSW=0 _WSW_AVAIL=0
declare -g  _HIT=""

# Raw-byte pushback FIFO: bytes that were already read from stdin (while
# peeking ahead to coalesce mouse motion — see _tui._coalesce_mouse_motion)
# but turned out to belong to a different, non-coalescible event. They're
# stashed here and replayed through _tui._next_byte before the next real
# read, so nothing downstream has to know a peek ever happened.
declare -g _TUI_PENDING_INPUT=""
# Scratch output slot for _tui._read_escape_seq (a plain global instead of
# a command-substitution return, so assembling a sequence never forks).
declare -g _TUI_SEQ_BUF=""

declare -g _TUI_DRAG_LINES=0
declare -g _TUI_DRAG_MAX_W=0
declare -g _TUI_HOVERED_PANE=""
declare -g _TUI_HOVERED_WIDGET=""

# Debounced render queue for pane *content* only (tui.output / scroll).
# Scroll-wheel spins and drag-jumps can arrive in bursts much faster than
# the AWK shader needs to run, so they mark a pane dirty and arm one shared
# countdown instead of redrawing on every event; tui.run() flushes whatever
# is pending at most once per settled moment. Hover/focus restyling is a
# single cheap widget or border redraw and is drawn immediately instead
# (see _tui._draw_widgets_now) — debouncing it added latency without a
# throughput problem to justify it.
declare -gA _TUI_PENDING_OUTPUT=()   # pane id -> content awaiting re-render
declare -g  _TUI_RENDER_TIMEOUT=-1

# ═══════════════════════════════════════════════════════════════════════
#  INTERNAL STATE (BACKGROUND EXECUTION)
# ═══════════════════════════════════════════════════════════════════════

declare -ga _EXEC_BUF=()
declare -g  _EXEC_PID=0
declare -g  _EXEC_CMD=""
declare -g  _EXEC_OUTFILE=""
declare -g  _EXEC_FIFO=""
declare -g  _EXEC_FIFO_FD=""
declare -g  _EXEC_STATUS="idle"
declare -g  _EXEC_EXIT=""
declare -g  _EXEC_TMPDIR=""
declare -g  _EXEC_OUT_PANE=""
declare -g  _EXEC_CTL_PANE=""
declare -g  _EXEC_VROWS=0
declare -g  _EXEC_LAST_READ=0
declare -g  _TUI_TICK_FN=""

# Optional observability hook, same idiom as _TUI_TICK_FN: if set, called
# with a one-line description of every DISPATCHED input event (a motion
# report the mouse-coalescer discarded never reaches this — only what
# actually got acted on). The framework doesn't know or care who sets
# this; it exists so a page (e.g. the debug page) can log/display input
# without the framework needing any debug-specific code of its own.
declare -g  _TUI_ON_INPUT_EVENT=""
_tui._notify_input() { [[ -n "$_TUI_ON_INPUT_EVENT" ]] && "$_TUI_ON_INPUT_EVENT" "$1"; }

# ═══════════════════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════════════════

tui.log(){
    local msg="$1"
    local level="${2:-info}"
    printf "[%s] [%s] %s\n" "$(date +%H:%M:%S)" "$level" "$msg" >> ".tui_exec.log"
}
tui.log.debug() { tui.log "$1" "debug"; }
tui.log.info()  { tui.log "$1" "info"; }
tui.log.warn()  { tui.log "$1" "warn"; }
tui.log.error() { tui.log "$1" "error"; }

# ═══════════════════════════════════════════════════════════════════════
#  INIT / CLEANUP
# ═══════════════════════════════════════════════════════════════════════

tui.init() {
    _TUI_OLD_STTY=$(stty -g 2>/dev/null)
    stty -echo -icanon min 1 time 0 2>/dev/null

    term.alt_screen
    cur.hide
    erase.all

    mouse.any_on
    mouse.sgr_on

    term.size _TUI_ROWS _TUI_COLS

    _TUI_P_ROW[root]=1    ; _TUI_P_COL[root]=1
    _TUI_P_H[root]=$_TUI_ROWS ; _TUI_P_W[root]=$_TUI_COLS
    _TUI_P_BORDER[root]="single"
    _TUI_P_TITLE[root]=""
    _TUI_P_LEAVES=(root)
    _TUI_P_ALL=(root)
}

_kill_process_tree() {
    local pid=$1
    local children
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        _kill_process_tree "$child"
    done
    kill -TERM "$pid" 2>/dev/null
    sleep 0.05
    kill -KILL "$pid" 2>/dev/null
}

_exec_cleanup_process() {
    if (( _EXEC_PID > 0 )) && kill -0 "$_EXEC_PID" 2>/dev/null; then
        _kill_process_tree "$_EXEC_PID"
        wait "$_EXEC_PID" 2>/dev/null
    fi
    _EXEC_PID=0

    if [[ -n "${_EXEC_FIFO_FD:-}" ]]; then
        exec {_EXEC_FIFO_FD}>&- 2>/dev/null
        _EXEC_FIFO_FD=""
    fi
}

_exec_cleanup_all() {
    _exec_cleanup_process
    _TUI_TICK_FN=""
    [[ -n "$_EXEC_TMPDIR" && -d "$_EXEC_TMPDIR" ]] && rm -rf "$_EXEC_TMPDIR"
}

tui.cleanup() {
    mouse.any_off
    mouse.sgr_off
    style.reset
    cur.show
    term.main_screen
    stty "$_TUI_OLD_STTY" 2>/dev/null
}

_master_cleanup() {
    _exec_cleanup_all 2>/dev/null
    tui.cleanup 2>/dev/null
    # Hard reset terminal state (ANSI resets + stty cooked mode)
    printf "\e[0m\e[?25h\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1049l\r\n"
    stty sane 2>/dev/null
    stty echo 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════
#  PANE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════

tui.hsplit() { _tui._split "h" "$@"; }
tui.vsplit() { _tui._split "v" "$@"; }

_tui._split() {
    local dir="$1" parent="$2"; shift 2
    local names="" weights=""

    for spec in "$@"; do
        local n="${spec%%:*}"
        local w="${spec#*:}"
        names+="${names:+ }$n"
        weights+="${weights:+ }$w"
        _TUI_P_BORDER[$n]="single"
        _TUI_P_TITLE[$n]=""
    done

    _TUI_P_DIR[$parent]="$dir"
    _TUI_P_CHILDREN[$parent]="$names"
    _TUI_P_WEIGHTS[$parent]="$weights"

    _tui._layout "$parent"

    _TUI_P_LEAVES=()
    _TUI_P_ALL=()
    _tui._collect_leaves "root"
}

# Smallest integer i such that i*i >= n (i.e. ceil(sqrt(n))), for picking a
# roughly-square grid shape when neither rows nor cols was specified. n is
# always a small cell count here, so a linear search is fine — this runs
# once per grid build, never per-frame.
_tui._ceil_sqrt() {
    local n="$1" i=1
    (( n <= 1 )) && { printf '1'; return; }
    while (( i * i < n )); do (( i++ )); done
    printf '%s' "$i"
}

# tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS COL_WEIGHTS NAME...
#
# Pure-geometry grid constructor, sitting alongside tui.hsplit/tui.vsplit:
# builds PARENT as a vsplit of ROWS row-panes, each an hsplit of COLS
# cell-panes, and assigns the given NAME... list to cells in row-major
# order (one name per cell; an empty string leaves that cell blank).
#
# ROWS and/or COLS may be passed as "" to size the grid from how many
# names were given: only COLS given -> ROWS = ceil(N/COLS); only ROWS
# given -> COLS = ceil(N/ROWS); neither given -> a roughly-square grid.
#
# FIT is "pack" (default: every row gets the full COLS cells, blanks
# render as empty placeholder panes) or "stretch" (a row's blank cells are
# dropped instead, so its populated cells expand to fill the row).
#
# This function does not know about "explicit vs. auto-flow placement" —
# callers (the markup parser's <pane split="grid"> handler, or
# tui.factory.grid) are responsible for resolving that into a flat,
# row-major NAME list before calling this, the same way callers of
# tui.hsplit/tui.vsplit are responsible for deciding their own name:weight
# lists.
declare -ga _TUI_LAST_GRID_ROWS=()   # row-wrapper pane ids from the most recent tui.grid call
declare -ga _TUI_LAST_GRID_CELLS=()  # cell pane ids from it, row-major, blanks included

tui.grid() {
    local parent="$1" rows="$2" cols="$3" fit="${4:-pack}"
    local row_weights="$5" col_weights="$6"
    shift 6
    local -a names=("$@")
    local n=${#names[@]}

    if [[ -z "$cols" && -z "$rows" ]]; then
        cols=$(_tui._ceil_sqrt "$n")
        rows=$(( (n + cols - 1) / cols ))
    elif [[ -z "$cols" ]]; then
        cols=$(( (n + rows - 1) / rows ))
    elif [[ -z "$rows" ]]; then
        rows=$(( (n + cols - 1) / cols ))
    fi
    (( rows < 1 )) && rows=1
    (( cols < 1 )) && cols=1

    local -a rw cw
    read -ra rw <<< "${row_weights:-}"
    read -ra cw <<< "${col_weights:-}"

    local -a row_specs=()
    local r c
    for (( r = 0; r < rows; r++ )); do
        row_specs+=("${parent}_row${r}:${rw[$r]:-1}")
    done
    tui.vsplit "$parent" "${row_specs[@]}"

    _TUI_LAST_GRID_ROWS=()
    _TUI_LAST_GRID_CELLS=()
    for (( r = 0; r < rows; r++ )); do
        local rid="${parent}_row${r}"
        _TUI_LAST_GRID_ROWS+=("$rid")
        local -a cell_specs=()
        for (( c = 0; c < cols; c++ )); do
            local ni=$(( r * cols + c ))
            local nm="${names[$ni]:-}"
            if [[ -z "$nm" ]]; then
                [[ "$fit" == "stretch" ]] && continue
                nm="${rid}_c${c}_blank"
            fi
            cell_specs+=("${nm}:${cw[$c]:-1}")
            _TUI_LAST_GRID_CELLS+=("$nm")
        done
        (( ${#cell_specs[@]} == 0 )) && continue
        tui.hsplit "$rid" "${cell_specs[@]}"
    done
}

_tui._collect_leaves() {
    local id="$1"
    _TUI_P_ALL+=("$id")
    if [[ -z "${_TUI_P_CHILDREN[$id]:-}" ]]; then
        _TUI_P_LEAVES+=("$id")
    else
        local ch; read -ra ch <<< "${_TUI_P_CHILDREN[$id]}"
        for c in "${ch[@]}"; do _tui._collect_leaves "$c"; done
    fi
}

_tui._layout() {
    local p="$1"
    local dir="${_TUI_P_DIR[$p]:-}"
    [[ -z "$dir" ]] && return

    local pr=${_TUI_P_ROW[$p]}  pc=${_TUI_P_COL[$p]}
    local ph=${_TUI_P_H[$p]}    pw=${_TUI_P_W[$p]}

    local -a ch wt
    read -ra ch <<< "${_TUI_P_CHILDREN[$p]}"
    read -ra wt <<< "${_TUI_P_WEIGHTS[$p]}"

    local total=0
    for w in "${wt[@]}"; do (( total += w )); done

    local i offset=0 last=$(( ${#ch[@]} - 1 ))
    for (( i = 0; i <= last; i++ )); do
        local name="${ch[$i]}" w="${wt[$i]}"

        if [[ "$dir" == "h" ]]; then
            local cw=$(( pw * w / total ))
            (( i == last )) && cw=$(( pw - offset ))
            [[ -n "${_TUI_P_MAXW[$name]:-}" ]] && (( cw > _TUI_P_MAXW[$name] )) && cw=${_TUI_P_MAXW[$name]}
            _TUI_P_ROW[$name]=$pr
            _TUI_P_COL[$name]=$(( pc + offset ))
            _TUI_P_H[$name]=$ph
            _TUI_P_W[$name]=$cw
            (( offset += cw ))
        else
            local ch_h=$(( ph * w / total ))
            (( i == last )) && ch_h=$(( ph - offset ))
            [[ -n "${_TUI_P_MAXH[$name]:-}" ]] && (( ch_h > _TUI_P_MAXH[$name] )) && ch_h=${_TUI_P_MAXH[$name]}
            _TUI_P_ROW[$name]=$(( pr + offset ))
            _TUI_P_COL[$name]=$pc
            _TUI_P_H[$name]=$ch_h
            _TUI_P_W[$name]=$pw
            (( offset += ch_h ))
        fi

        [[ -n "${_TUI_P_CHILDREN[$name]:-}" ]] && _tui._layout "$name"
    done
}

tui.pane_title()   { _TUI_P_TITLE[$1]="$2"; }
tui.pane_border()  { _TUI_P_BORDER[$1]="$2"; }
tui.pane_align()   { [[ -n "$2" ]] && _TUI_P_ALIGN[$1]="$2"; }
tui.pane_valign()  { [[ -n "$2" ]] && _TUI_P_VALIGN[$1]="$2"; }
tui.pane_minsize() { [[ -n "$2" ]] && _TUI_P_MINW[$1]="$2"; [[ -n "$3" ]] && _TUI_P_MINH[$1]="$3"; }
tui.pane_maxsize() { [[ -n "$2" ]] && _TUI_P_MAXW[$1]="$2"; [[ -n "$3" ]] && _TUI_P_MAXH[$1]="$3"; }

tui.pane_scroll() {
    [[ -n "$2" ]] && _TUI_P_SCROLL[$1]="$2"
    _TUI_P_SOFF_V[$1]=0
    _TUI_P_SOFF_H[$1]=0
}

# ═══════════════════════════════════════════════════════════════════════
#  WIDGETS
# ═══════════════════════════════════════════════════════════════════════

tui.label() {
    local id="$1"
    if [[ -z "$id" || -z "$2" ]]; then
        echo "tui.label: missing id or pane, skipping widget" >&2
        return 1
    fi
    _TUI_W_TYPE[$id]="label"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_LABEL[$id]="$4"
    _TUI_W_VALUE[$id]="$4"
    _TUI_W_ORDER+=("$id")
}

tui.button() {
    local id="$1"
    if [[ -z "$id" || -z "$2" ]]; then
        echo "tui.button: missing id or pane, skipping widget" >&2
        return 1
    fi
    _TUI_W_TYPE[$id]="button"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_LABEL[$id]="$4"
    _TUI_W_VALUE[$id]=""
    _TUI_W_ACTION[$id]="${5:-}"
    _TUI_W_ORDER+=("$id")
    _TUI_FOCUSABLE+=("$id")
}

tui.input() {
    local id="$1"
    if [[ -z "$id" || -z "$2" ]]; then
        echo "tui.input: missing id or pane, skipping widget" >&2
        return 1
    fi
    local submit_fn="${6:-}"
    _TUI_W_TYPE[$id]="input"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_PH[$id]="${4:-}"
    _TUI_W_LABEL[$id]="${5:-}"
    _TUI_W_VALUE[$id]=""
    _TUI_W_ACTION[$id]=""
    _TUI_W_SUBMIT[$id]="${submit_fn}"
    _TUI_W_ORDER+=("$id")
    _TUI_FOCUSABLE+=("$id")
}

tui.checkbox() {
    local id="$1"
    if [[ -z "$id" || -z "$2" ]]; then
        echo "tui.checkbox: missing id or pane, skipping widget" >&2
        return 1
    fi
    local checked="${5:-}"
    _TUI_W_TYPE[$id]="checkbox"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_LABEL[$id]="$4"
    case "$checked" in
        1|true|yes) _TUI_W_VALUE[$id]="1" ;;
        *)          _TUI_W_VALUE[$id]="0" ;;
    esac
    _TUI_W_ACTION[$id]="${6:-}"
    _TUI_W_ORDER+=("$id")
    _TUI_FOCUSABLE+=("$id")
}

# tui.checkbox.toggle ID — flips a checkbox's value, redraws it, and calls
# its action (if any) with the new value ("0"/"1"). The one place both
# activation paths (Enter on a focused checkbox, a mouse click on one)
# funnel through, so they can't drift out of sync with each other.
tui.checkbox.toggle() {
    local id="$1"
    [[ "${_TUI_W_TYPE[$id]:-}" == "checkbox" ]] || return
    local new="1"
    [[ "${_TUI_W_VALUE[$id]}" == "1" ]] && new="0"
    tui.update "$id" "$new"
    local action="${_TUI_W_ACTION[$id]:-}"
    [[ -n "$action" ]] && "$action" "$new"
}

# ═══════════════════════════════════════════════════════════════════════
#  TABS — a thin convenience layer over buttons + tui.grid, formalizing
#  the "row of header buttons that swap a content pane" pattern already
#  hand-rolled identically in more than one demo page. No new drawing or
#  hit-testing primitive: a tab header is an ordinary button living in an
#  ordinary tui.grid cell, and "active" reuses the widget focus this
#  framework already has rather than inventing a second notion of it.
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_TABS_ACTIVE=()        # tabs id -> currently active tab id
declare -gA _TUI_TABS_CONTENT_PANE=()  # tabs id -> its content pane id
declare -gA _TUI_TABS_COMPACT=()       # tabs id -> "true" for the borderless header style
declare -gA _TUI_TAB_TEXT=()           # tab id -> header button text
declare -gA _TUI_TAB_ACTION=()         # tab id -> developer's on-activate callback
declare -gA _TUI_TAB_DEFAULT=()        # tab id -> "true" if it starts active
declare -gA _TUI_TAB_GROUP=()          # tab id -> owning tabs id

# tui.tabs.compact TABS_ID [true|false] — call before tui.tabs.build to pick
# the header style: framed (default) draws each header cell as its own
# bordered box, needing at least 3 rows (top border, label, bottom border).
# compact drops the frame entirely — each header is a borderless,
# background-color-filled cell needing only 1 row, with the active tab
# indicated by a bg color change (via the .tab_header_compact:focus class)
# instead of a border. Pick compact wherever the header's own pane doesn't
# have 3 rows to spare.
tui.tabs.compact() { _TUI_TABS_COMPACT[$1]="${2:-true}"; }

# tui.tabs.add TAB_ID TEXT ACTION [DEFAULT] — registers one tab's data
# ahead of tui.tabs.build, which needs the full set of tabs at once (to
# lay out the header row as a single tui.grid).
tui.tabs.add() {
    local tab_id="$1" text="$2" action="$3" is_default="${4:-}"
    _TUI_TAB_TEXT[$tab_id]="$text"
    _TUI_TAB_ACTION[$tab_id]="$action"
    _TUI_TAB_DEFAULT[$tab_id]="$is_default"
}

# tui.tabs.build TABS_ID HEADER_PANE CONTENT_PANE TAB_ID...
# Lays the header buttons out as a 1-row tui.grid across HEADER_PANE, then
# activates whichever tab was marked default (or the first one).
tui.tabs.build() {
    local tabs_id="$1" header_pane="$2" content_pane="$3"; shift 3
    local -a tab_ids=("$@")
    (( ${#tab_ids[@]} == 0 )) && return

    _TUI_TABS_CONTENT_PANE[$tabs_id]="$content_pane"

    local -a cell_names=()
    local tid
    for tid in "${tab_ids[@]}"; do
        cell_names+=("${header_pane}_${tid}_cell")
    done
    tui.grid "$header_pane" 1 "${#tab_ids[@]}" pack "" "" "${cell_names[@]}"

    # A tab header clipping its label when there isn't room is normal,
    # expected UI behavior (the same as nav sidebar buttons already do) —
    # not a real "this pane is broken" situation the content-fit checker
    # should flag, especially with more tabs than a header row has spare
    # width for. Opt every cell out of it.
    local cell
    for cell in "${cell_names[@]}"; do
        tui.pane_strict_fit "$cell" false
    done

    local compact=0
    [[ "${_TUI_TABS_COMPACT[$tabs_id]:-}" == "true" ]] && compact=1
    local cell_class="tab_header"
    if (( compact )); then
        cell_class="tab_header_compact"
        local cell
        for cell in "${cell_names[@]}"; do
            tui.pane_border "$cell" "none"
        done
    fi

    local default_tab=""
    for tid in "${tab_ids[@]}"; do
        _TUI_TAB_GROUP[$tid]="$tabs_id"
        tui.button "$tid" "${header_pane}_${tid}_cell" 0 "${_TUI_TAB_TEXT[$tid]:-$tid}" _tui._tab_activate
        tui.align "$tid" fill
        tui.class "$tid" "$cell_class"
        [[ "${_TUI_TAB_DEFAULT[$tid]:-}" == "true" ]] && default_tab="$tid"
    done
    [[ -z "$default_tab" ]] && default_tab="${tab_ids[0]}"
    tui.tabs.activate "$default_tab"
}

_tui._tab_activate() { tui.tabs.activate "$1"; }

# tui.tabs.activate TAB_ID — makes TAB_ID the active tab in its group:
# focuses its header button (reusing this framework's existing focus
# styling as the "active" indicator instead of a second style state) and
# calls the developer's own action, which is exactly the unchanged body
# of whatever callback already populates that content pane today.
tui.tabs.activate() {
    local tab_id="$1"
    local tabs_id="${_TUI_TAB_GROUP[$tab_id]:-}"
    [[ -z "$tabs_id" ]] && return
    _TUI_TABS_ACTIVE[$tabs_id]="$tab_id"
    tui.focus "$tab_id"
    local action="${_TUI_TAB_ACTION[$tab_id]:-}"
    [[ -n "$action" ]] && "$action" "$tab_id"
}

# ═══════════════════════════════════════════════════════════════════════
#  FACTORY — namespace-scoped construction and bulk teardown for layouts
#  whose shape isn't known until runtime. Generalizes the one dynamic-
#  widget-group pattern that already existed in this file (tui.exec's own
#  "_x"-prefixed controls, built by _exec_setup_controls and torn down by
#  _exec_remove_widgets) into a reusable primitive keyed by a caller-
#  chosen namespace instead of a hardcoded prefix, so independent dynamic
#  groups can coexist without id collisions. Deliberately not a
#  templating engine — just auto-id generation plus bulk teardown wrapped
#  around the existing imperative constructors (tui.label/button/input/
#  checkbox/grid).
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_FACTORY_IDS=()          # namespace -> "id1 id2 ..." (widgets + panes)
declare -gA _TUI_FACTORY_GRID_PARENTS=() # namespace -> "parent1 ..." (split state to reset, not remove)
declare -gA _TUI_FACTORY_COUNTER=()      # namespace -> next auto-id suffix
declare -ga _TUI_FACTORY_GRID_CELLS=()   # last tui.factory.grid call's cell ids, in order

# Sets _TUI_FACTORY_LAST_ID rather than printing its result: this
# increments _TUI_FACTORY_COUNTER as a side effect, and a command
# substitution (id="$(...)") runs in a subshell, which would silently
# discard that increment — every id in a loop would come back identical.
# Same fork-free convention as _HIT/_HIT_PANE elsewhere in this file.
declare -g _TUI_FACTORY_LAST_ID=""
_tui._factory_next_id() {
    local ns="$1" n="${_TUI_FACTORY_COUNTER[$ns]:-0}"
    _TUI_FACTORY_COUNTER[$ns]=$(( n + 1 ))
    _TUI_FACTORY_LAST_ID="__f_${ns}_${n}"
}

_tui._factory_track() {
    local ns="$1" id="$2"
    _TUI_FACTORY_IDS[$ns]="${_TUI_FACTORY_IDS[$ns]:+${_TUI_FACTORY_IDS[$ns]} }${id}"
}

# Each tui.factory.* constructor leaves the id it generated in
# _TUI_FACTORY_LAST_ID: `tui.factory.button ...; id="$_TUI_FACTORY_LAST_ID"`.
# Deliberately does NOT also print it. In a TUI, stdout is the screen — a
# constructor typically called in a loop the caller doesn't wrap in a
# command substitution (see tui.factory.grid's own usage pattern) would
# otherwise leak raw id text straight onto the terminal outside any pane's
# clipping the moment someone forgets the `$(...)`, which is exactly the
# failure mode this avoids by only ever writing to a variable.
tui.factory.label() {
    local ns="$1" pane="$2" row="$3" text="$4"
    _tui._factory_next_id "$ns"
    local id="$_TUI_FACTORY_LAST_ID"
    _tui._factory_track "$ns" "$id"
    tui.label "$id" "$pane" "$row" "$text"
}

tui.factory.button() {
    local ns="$1" pane="$2" row="$3" text="$4" action="$5"
    _tui._factory_next_id "$ns"
    local id="$_TUI_FACTORY_LAST_ID"
    _tui._factory_track "$ns" "$id"
    tui.button "$id" "$pane" "$row" "$text" "$action"
}

tui.factory.input() {
    local ns="$1" pane="$2" row="$3" placeholder="$4" label="${5:-}" submit="${6:-}"
    _tui._factory_next_id "$ns"
    local id="$_TUI_FACTORY_LAST_ID"
    _tui._factory_track "$ns" "$id"
    tui.input "$id" "$pane" "$row" "$placeholder" "$label" "$submit"
}

tui.factory.checkbox() {
    local ns="$1" pane="$2" row="$3" label="$4" checked="${5:-}" action="${6:-}"
    _tui._factory_next_id "$ns"
    local id="$_TUI_FACTORY_LAST_ID"
    _tui._factory_track "$ns" "$id"
    tui.checkbox "$id" "$pane" "$row" "$label" "$checked" "$action"
}

# tui.factory.grid NAMESPACE PARENT COUNT [COLS] [FIT] [ROW_WEIGHTS] [COL_WEIGHTS]
# The dynamic-sizing counterpart to <pane split="grid">: takes an item
# COUNT rather than a fixed shape (COLS optional — auto-square if
# omitted), builds it via tui.grid with COUNT freshly auto-generated,
# namespace-tracked ids, and leaves them in order in
# _TUI_FACTORY_GRID_CELLS for the caller to populate:
#   for i in "${!items[@]}"; do
#       tui.factory.button "$ns" "${_TUI_FACTORY_GRID_CELLS[$i]}" 0 "${items[$i]}" my_action
#   done
tui.factory.grid() {
    local ns="$1" parent="$2" count="$3" cols="${4:-}" fit="${5:-pack}"
    local roww="${6:-}" colw="${7:-}"

    _TUI_FACTORY_GRID_PARENTS[$ns]="${_TUI_FACTORY_GRID_PARENTS[$ns]:+${_TUI_FACTORY_GRID_PARENTS[$ns]} }${parent}"

    local -a cell_ids=()
    local i
    for (( i = 0; i < count; i++ )); do
        _tui._factory_next_id "$ns"
        _tui._factory_track "$ns" "$_TUI_FACTORY_LAST_ID"
        cell_ids+=("$_TUI_FACTORY_LAST_ID")
    done

    tui.grid "$parent" "" "$cols" "$fit" "$roww" "$colw" "${cell_ids[@]}"

    local r
    for r in "${_TUI_LAST_GRID_ROWS[@]}"; do
        _tui._factory_track "$ns" "$r"
    done
    _TUI_FACTORY_GRID_CELLS=("${cell_ids[@]}")
}

# tui.factory.clear NAMESPACE — tears down every widget/pane created under
# NAMESPACE (removing it from _TUI_W_ORDER/_TUI_FOCUSABLE and its widget
# or pane state entirely) and resets any grid parent it built back to a
# plain, childless leaf pane, ready for a fresh build. Safe to call on a
# namespace that was never used, or has already been cleared.
tui.factory.clear() {
    local ns="$1"
    local -a ids=()
    read -ra ids <<< "${_TUI_FACTORY_IDS[$ns]:-}"

    if (( ${#ids[@]} > 0 )); then
        local -a keep_order=() keep_focus=()
        local w drop id
        for w in "${_TUI_W_ORDER[@]}"; do
            drop=0
            for id in "${ids[@]}"; do [[ "$w" == "$id" ]] && { drop=1; break; }; done
            (( drop )) || keep_order+=("$w")
        done
        for w in "${_TUI_FOCUSABLE[@]}"; do
            drop=0
            for id in "${ids[@]}"; do [[ "$w" == "$id" ]] && { drop=1; break; }; done
            (( drop )) || keep_focus+=("$w")
        done
        _TUI_W_ORDER=("${keep_order[@]}")
        _TUI_FOCUSABLE=("${keep_focus[@]}")

        for id in "${ids[@]}"; do
            [[ "${_TUI_FOCUS_ID:-}" == "$id" ]] && { _TUI_FOCUS_ID=""; _TUI_FOCUS_IDX=-1; }
            unset '_TUI_W_TYPE[$id]' '_TUI_W_PANE[$id]' '_TUI_W_ROW[$id]' '_TUI_W_LABEL[$id]' \
                  '_TUI_W_VALUE[$id]' '_TUI_W_ACTION[$id]' '_TUI_W_SUBMIT[$id]' '_TUI_W_PH[$id]' \
                  '_TUI_W_ALIGN[$id]' '_TUI_W_VALIGN[$id]' '_TUI_W_MINW[$id]' '_TUI_W_MAXW[$id]' \
                  '_TUI_W_LABEL_ALIGN[$id]' '_TUI_W_LABEL_WIDTH[$id]'
            unset '_TUI_P_ROW[$id]' '_TUI_P_COL[$id]' '_TUI_P_H[$id]' '_TUI_P_W[$id]' \
                  '_TUI_P_DIR[$id]' '_TUI_P_CHILDREN[$id]' '_TUI_P_WEIGHTS[$id]' \
                  '_TUI_P_TITLE[$id]' '_TUI_P_BORDER[$id]' '_TUI_P_ALIGN[$id]' '_TUI_P_VALIGN[$id]' \
                  '_TUI_P_MINW[$id]' '_TUI_P_MINH[$id]' '_TUI_P_MAXW[$id]' '_TUI_P_MAXH[$id]' \
                  '_TUI_P_SCROLL[$id]' '_TUI_P_SOFF_V[$id]' '_TUI_P_SOFF_H[$id]'
        done
    fi

    local -a parents=()
    read -ra parents <<< "${_TUI_FACTORY_GRID_PARENTS[$ns]:-}"
    local p
    for p in "${parents[@]}"; do
        unset '_TUI_P_DIR[$p]' '_TUI_P_CHILDREN[$p]' '_TUI_P_WEIGHTS[$p]'
    done

    unset '_TUI_FACTORY_IDS[$ns]' '_TUI_FACTORY_GRID_PARENTS[$ns]'

    if (( ${#ids[@]} > 0 || ${#parents[@]} > 0 )); then
        _TUI_P_LEAVES=(); _TUI_P_ALL=()
        _tui._collect_leaves "root"
    fi
}

tui.get()          { printf '%s' "${_TUI_W_VALUE[$1]:-}"; }
tui.set()          { _TUI_W_VALUE[$1]="$2"; }
tui.update()       { _TUI_W_VALUE[$1]="$2"; _tui._draw_widget "$1"; }
tui.on_action()    { _TUI_W_ACTION[$1]="$2"; }
tui.on_submit()    { _TUI_W_SUBMIT[$1]="$2"; }
tui.align()        { [[ -n "$2" ]] && _TUI_W_ALIGN[$1]="$2"; }
tui.valign()       { [[ -n "$2" ]] && _TUI_W_VALIGN[$1]="$2"; }
tui.minsize()      { [[ -n "$2" ]] && _TUI_W_MINW[$1]="$2"; }
tui.maxsize()      { [[ -n "$2" ]] && _TUI_W_MAXW[$1]="$2"; }
tui.label_align()  { [[ -n "$2" ]] && _TUI_W_LABEL_ALIGN[$1]="$2"; }
tui.label_width()  { [[ -n "$2" ]] && _TUI_W_LABEL_WIDTH[$1]="$2"; }

# ═══════════════════════════════════════════════════════════════════════
#  GEOMETRY & RENDERING
# ═══════════════════════════════════════════════════════════════════════

_tui._repeat() {
    local ch="$1" n="$2" out=""
    (( n <= 0 )) && return
    printf -v out '%*s' "$n" ""
    printf '%s' "${out// /$ch}"
}

# Safe pane lookup for a possibly-empty widget id. Subscripting an
# associative array with "" is a bash error ("bad array subscript"), not
# just an empty lookup — this matters here because callers routinely pass
# the previously-focused id, which is "" before anything has been focused.
_tui._widget_pane() {
    [[ -z "$1" ]] && return
    printf '%s' "${_TUI_W_PANE[$1]:-}"
}

_tui._widget_align() {
    local id="$1" pane="${_TUI_W_PANE[$1]}" default="left"
    [[ "${_TUI_W_TYPE[$1]}" == "button" ]] && default="center"
    printf '%s' "${_TUI_W_ALIGN[$id]:-${_TUI_P_ALIGN[$pane]:-$default}}"
}

_tui._widget_valign() {
    local id="$1" pane="${_TUI_W_PANE[$1]}"
    printf '%s' "${_TUI_W_VALIGN[$id]:-${_TUI_P_VALIGN[$pane]:-top}}"
}

_tui._align_pad() {
    local align="$1" content_len="$2" width="$3" pad=0
    case "$align" in
        center) pad=$(( (width - content_len) / 2 )) ;;
        right)  pad=$(( width - content_len )) ;;
        *)      pad=0 ;;
    esac
    (( pad < 0 )) && pad=0
    printf '%s' "$pad"
}

_tui._resolve_text() {
    local text="$1" out="" pre expr result
    local rest="$text"
    while [[ "$rest" == *'${'*'}'* ]]; do
        pre="${rest%%\$\{*}"
        rest="${rest#*\$\{}"
        expr="${rest%%\}*}"
        rest="${rest#*\}}"
        result="$(PATH="${SCRIPT_DIR:-.}:$PATH" eval "$expr" 2>/dev/null)"
        out+="${pre}${result}"
    done
    out+="$rest"
    printf '%s' "$out"
}

# Whether a leaf pane's content actually fits is normally inferred
# automatically (see _tui._pane_content_need) rather than requiring the
# author to precompute and declare min_width/min_height by hand. Set
# strict_fit="false" on a specific pane (tui.pane_strict_fit ID false) to
# opt back out and rely on explicit min_width/min_height only, the way
# every pane behaved before this check existed.
declare -gA _TUI_P_STRICT_FIT=()
tui.pane_strict_fit() { _TUI_P_STRICT_FIT[$1]="$2"; }

declare -g _TUI_CONTENT_NEED_W=0
declare -g _TUI_CONTENT_NEED_H=0

# _tui._pane_content_need ID — infers how much space a leaf pane's actual
# content needs, into _TUI_CONTENT_NEED_W/_H (0 when nothing applies).
# Two sources, each best-effort and consistent with this framework's
# existing "static declared text" warnings rather than attempting to
# re-resolve ${...} runtime template expressions:
#   - widgets placed in it: height from the furthest row used, width from
#     the longest label/value text among them;
#   - tui.output/tui.output_append content: reuses _TUI_P_LINES/_TUI_P_MAX_W
#     directly — _tui._calc_bounds already maintains these on every
#     tui.output call, so there's nothing new to measure here.
# A container pane (has children) or one with scroll enabled is exempt:
# a container's own children enforce their own fit, and a scrollable
# pane's whole purpose is holding content taller/wider than its viewport.
_tui._pane_content_need() {
    local id="$1"
    _TUI_CONTENT_NEED_W=0
    _TUI_CONTENT_NEED_H=0
    [[ -n "${_TUI_P_CHILDREN[$id]:-}" ]] && return
    [[ "${_TUI_P_SCROLL[$id]:-none}" != "none" ]] && return

    local wid maxrow=-1 maxlen=0 row txt
    for wid in "${_TUI_W_ORDER[@]}"; do
        [[ "${_TUI_W_PANE[$wid]:-}" == "$id" ]] || continue
        row=${_TUI_W_ROW[$wid]:-0}
        (( row > maxrow )) && maxrow=$row
        txt="${_TUI_W_LABEL[$wid]:-${_TUI_W_VALUE[$wid]:-}}"
        (( ${#txt} > maxlen )) && maxlen=${#txt}
    done
    (( maxrow >= 0 )) && _TUI_CONTENT_NEED_H=$(( maxrow + 1 ))
    (( maxlen > _TUI_CONTENT_NEED_W )) && _TUI_CONTENT_NEED_W=$maxlen

    local lines=${_TUI_P_LINES[$id]:-0} maxw=${_TUI_P_MAX_W[$id]:-0}
    (( lines > _TUI_CONTENT_NEED_H )) && _TUI_CONTENT_NEED_H=$lines
    (( maxw > _TUI_CONTENT_NEED_W )) && _TUI_CONTENT_NEED_W=$maxw

    # Both sources above are content-AREA sizes; _tui._pane_too_small
    # compares against the pane's OUTER w/h (same as min_width/min_height
    # already do), so translate using the same border inset
    # tui.content_area uses in the other direction.
    if [[ "${_TUI_P_BORDER[$id]:-single}" != "none" ]]; then
        (( _TUI_CONTENT_NEED_W > 0 )) && _TUI_CONTENT_NEED_W=$(( _TUI_CONTENT_NEED_W + 4 ))
        (( _TUI_CONTENT_NEED_H > 0 )) && _TUI_CONTENT_NEED_H=$(( _TUI_CONTENT_NEED_H + 2 ))
    else
        (( _TUI_CONTENT_NEED_W > 0 )) && _TUI_CONTENT_NEED_W=$(( _TUI_CONTENT_NEED_W + 2 ))
    fi
}

declare -gA _TUI_P_EFFECTIVE_MINW=()
declare -gA _TUI_P_EFFECTIVE_MINH=()

# _tui._refresh_content_fit ID — recomputes and caches the effective
# min width/height (explicit min_width/min_height, or the pane's actual
# inferred content need, whichever is larger) for one pane. This is the
# only place that does the O(widgets-in-this-pane) work behind
# _tui._pane_content_need — deliberately called from just one place,
# _tui._draw_pane, which only ever runs on a full render (tui.render:
# once at startup, once per resize). _tui._pane_too_small itself stays a
# cheap cache read below, because it's also called from the per-event hot
# path (_tui._draw_widget, hit-tested and redrawn on every hover/focus
# change) and _tui._draw_pane_border (every focus change) — recomputing
# there would reintroduce exactly the kind of per-event cost this
# session spent most of its effort removing.
_tui._refresh_content_fit() {
    local id="$1"
    local minw="${_TUI_P_MINW[$id]:-0}" minh="${_TUI_P_MINH[$id]:-0}"
    if [[ "${_TUI_P_STRICT_FIT[$id]:-}" != "false" ]]; then
        _tui._pane_content_need "$id"
        (( _TUI_CONTENT_NEED_W > minw )) && minw=$_TUI_CONTENT_NEED_W
        (( _TUI_CONTENT_NEED_H > minh )) && minh=$_TUI_CONTENT_NEED_H
    fi
    _TUI_P_EFFECTIVE_MINW[$id]=$minw
    _TUI_P_EFFECTIVE_MINH[$id]=$minh
}

_tui._pane_too_small() {
    local id="$1"
    local minw="${_TUI_P_EFFECTIVE_MINW[$id]:-${_TUI_P_MINW[$id]:-0}}"
    local minh="${_TUI_P_EFFECTIVE_MINH[$id]:-${_TUI_P_MINH[$id]:-0}}"
    local w=${_TUI_P_W[$id]:-0} h=${_TUI_P_H[$id]:-0}
    (( minw > 0 && w < minw )) && return 0
    (( minh > 0 && h < minh )) && return 0
    return 1
}

_tui._widget_pos() {
    local pane="${_TUI_W_PANE[$1]}"
    local wrow="${_TUI_W_ROW[$1]}"
    local pr=${_TUI_P_ROW[$pane]}  pc=${_TUI_P_COL[$pane]}
    local pw=${_TUI_P_W[$pane]}    ph=${_TUI_P_H[$pane]}
    local border="${_TUI_P_BORDER[$pane]:-single}"
    local content_top content_h

    if [[ "$border" == "none" ]]; then
        content_top=$pr; content_h=$ph
        _WSC=$(( pc + 1 ))
        _WSW=$(( pw - 2 ))
    else
        content_top=$(( pr + 1 )); content_h=$(( ph - 2 ))
        _WSC=$(( pc + 2 ))
        _WSW=$(( pw - 4 ))
    fi
    (( _WSW < 1 )) && _WSW=1
    (( content_h < 1 )) && content_h=1

    case "$(_tui._widget_valign "$1")" in
        middle) _WSR=$(( content_top + content_h / 2 + wrow )) ;;
        bottom) _WSR=$(( content_top + content_h - 1 - wrow )) ;;
        *)      _WSR=$(( content_top + wrow )) ;;
    esac

    _WSW_AVAIL=$_WSW
    local maxw="${_TUI_W_MAXW[$1]:-}"
    if [[ -n "$maxw" ]] && (( _WSW > maxw )); then _WSW=$maxw; fi
    (( _WSW < 1 )) && _WSW=1
}

tui.content_area() {
    local id="$1"
    local b="${_TUI_P_BORDER[$id]:-single}"
    if [[ "$b" == "none" ]]; then
        echo "${_TUI_P_ROW[$id]} $(( ${_TUI_P_COL[$id]} + 1 )) ${_TUI_P_H[$id]} $(( ${_TUI_P_W[$id]} - 2 ))"
    else
        echo "$(( ${_TUI_P_ROW[$id]} + 1 )) $(( ${_TUI_P_COL[$id]} + 2 )) $(( ${_TUI_P_H[$id]} - 2 )) $(( ${_TUI_P_W[$id]} - 4 ))"
    fi
}

_tui._draw_size_warning() {
    local r="$1" c="$2" h="$3" w="$4" minw="$5" minh="$6"
    (( h < 1 )) && h=1
    (( w < 1 )) && w=1

    style.reset; style.bold; fg.hex "FF3333" 2>/dev/null
    local blank; printf -v blank '%*s' "$w" ""
    local row
    for (( row = 0; row < h; row++ )); do
        cur.goto $(( r + row )) "$c"
        echo -n "$blank"
    done

    local msg="min space = ${minw}x${minh}"
    local shown="${msg:0:$w}"
    local pad=$(( (w - ${#shown}) / 2 ))
    (( pad < 0 )) && pad=0
    cur.goto $(( r + h / 2 )) $(( c + pad ))
    echo -n "$shown"
    style.reset
}

_tui._apply_style() {
    local key="$1" fallback="${2:-}"
    local fg="${_TUI_STYLE_FG[$key]:-}"
    local bg="${_TUI_STYLE_BG[$key]:-}"
    local mods="${_TUI_STYLE_MOD[$key]:-}"

    if [[ -n "$fallback" ]]; then
        [[ -z "$fg" ]]   && fg="${_TUI_STYLE_FG[$fallback]:-}"
        [[ -z "$bg" ]]   && bg="${_TUI_STYLE_BG[$fallback]:-}"
        [[ -z "$mods" ]] && mods="${_TUI_STYLE_MOD[$fallback]:-}"
    fi

    if [[ -n "$fg" ]]; then
        if [[ "$fg" == \#* ]]; then fg.hex "$fg"; else "fg.$fg" 2>/dev/null; fi
    fi
    if [[ -n "$bg" ]]; then
        if [[ "$bg" == \#* ]]; then bg.hex "$bg"; else "bg.$bg" 2>/dev/null; fi
    fi
    if [[ -n "$mods" ]]; then
        for m in $mods; do "style.$m" 2>/dev/null; done
    fi
}

_tui._fill_pane_bg() {
    local id="$1" r="$2" c="$3" h="$4" w="$5"
    local key="${id}_normal"
    [[ -z "${_TUI_STYLE_FG[$key]:-}${_TUI_STYLE_BG[$key]:-}${_TUI_STYLE_MOD[$key]:-}" ]] && return
    (( h < 1 )) && h=1
    (( w < 1 )) && w=1
    local blank; printf -v blank '%*s' "$w" ""
    _tui._apply_style "$key"
    local row
    for (( row = 0; row < h; row++ )); do
        cur.goto $(( r + row )) "$c"
        echo -n "$blank"
    done
    style.reset
}

_tui._draw_pane() {
    local id="$1"
    local r=${_TUI_P_ROW[$id]}  c=${_TUI_P_COL[$id]}
    local h=${_TUI_P_H[$id]}    w=${_TUI_P_W[$id]}
    local border="${_TUI_P_BORDER[$id]:-single}"
    local title="${_TUI_P_TITLE[$id]:-}"

    _tui._refresh_content_fit "$id"
    if _tui._pane_too_small "$id"; then
        _tui._draw_size_warning "$r" "$c" "$h" "$w" "${_TUI_P_EFFECTIVE_MINW[$id]:-0}" "${_TUI_P_EFFECTIVE_MINH[$id]:-0}"
        return
    fi

    if [[ "$border" == "none" ]]; then
        _tui._fill_pane_bg "$id" "$r" "$c" "$h" "$w"
        return
    fi

    local tl tr bl br hz vt
    case "$border" in
        double) tl="╔" tr="╗" bl="╚" br="╝" hz="═" vt="║" ;;
        heavy)  tl="┏" tr="┓" bl="┗" br="┛" hz="━" vt="┃" ;;
        *)      tl="┌" tr="┐" bl="└" br="┘" hz="─" vt="│" ;;
    esac

    local inner=$(( w - 2 ))
    (( inner < 1 )) && inner=1

    cur.goto "$r" "$c"
    _tui._apply_style "${id}_border"
    
    if [[ -n "$title" ]]; then
        local max_t=$(( inner - 4 ))
        (( max_t < 1 )) && max_t=1
        (( ${#title} > max_t )) && title="${title:0:$max_t}"
        
        local tag=" ${title} "
        local tag_len=${#tag}
        local right_len=$(( inner - tag_len - 1 ))
        (( right_len < 0 )) && right_len=0
        
        echo -n "${tl}─"
        style.reset; _tui._apply_style "${id}_title"
        echo -n "$tag"
        style.reset; _tui._apply_style "${id}_border"
        echo -n "$(_tui._repeat "$hz" "$right_len")${tr}"
    else
        echo -n "${tl}$(_tui._repeat "$hz" "$inner")${tr}"
    fi
    style.reset

    local blank
    printf -v blank '%*s' "$inner" ""
    for (( row = 1; row < h - 1; row++ )); do
        cur.goto $(( r + row )) "$c"
        _tui._apply_style "${id}_border"; echo -n "$vt"; style.reset
        _tui._apply_style "${id}_normal"; echo -n "$blank"; style.reset
        _tui._apply_style "${id}_border"; echo -n "$vt"; style.reset
    done

    cur.goto $(( r + h - 1 )) "$c"
    _tui._apply_style "${id}_border"
    echo -n "${bl}$(_tui._repeat "$hz" "$inner")${br}"
    style.reset
}

# Redraws only a pane's border ring (corners/edges/title), resolving its own
# style state: a pane containing the currently focused widget draws
# "${id}_focus" (falling back to "${id}_border" when the class has no
# :focus rule), otherwise "${id}_border". Hovering a pane has no effect on
# its border — only focus does; this keeps the same self-contained
# resolution _tui._draw_widget uses for its own focus/hover, just against
# _TUI_FOCUS_ID instead of _TUI_HOVERED_PANE. Never touches the pane's
# interior, so it's safe to call whenever focus moves without disturbing
# scrollback/tui.output content or child widgets — no awk, no subshell text
# processing, just a handful of builtin echo/printf calls.
_tui._draw_pane_border() {
    local id="$1"
    local r=${_TUI_P_ROW[$id]}  c=${_TUI_P_COL[$id]}
    local h=${_TUI_P_H[$id]}    w=${_TUI_P_W[$id]}
    local border="${_TUI_P_BORDER[$id]:-single}"
    local title="${_TUI_P_TITLE[$id]:-}"

    [[ "$border" == "none" ]] && return
    _tui._pane_too_small "$id" && return

    local tl tr bl br hz vt
    case "$border" in
        double) tl="╔" tr="╗" bl="╚" br="╝" hz="═" vt="║" ;;
        heavy)  tl="┏" tr="┓" bl="┗" br="┛" hz="━" vt="┃" ;;
        *)      tl="┌" tr="┐" bl="└" br="┘" hz="─" vt="│" ;;
    esac

    local inner=$(( w - 2 ))
    (( inner < 1 )) && inner=1
    local state="border"
    [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}" == "$id" ]] && state="focus"
    local style_key="${id}_${state}"

    cur.goto "$r" "$c"
    _tui._apply_style "$style_key" "${id}_border"

    if [[ -n "$title" ]]; then
        local max_t=$(( inner - 4 ))
        (( max_t < 1 )) && max_t=1
        (( ${#title} > max_t )) && title="${title:0:$max_t}"

        local tag=" ${title} "
        local tag_len=${#tag}
        local right_len=$(( inner - tag_len - 1 ))
        (( right_len < 0 )) && right_len=0

        echo -n "${tl}─"
        style.reset; _tui._apply_style "${id}_title" "$style_key"
        echo -n "$tag"
        style.reset; _tui._apply_style "$style_key" "${id}_border"
        echo -n "$(_tui._repeat "$hz" "$right_len")${tr}"
    else
        echo -n "${tl}$(_tui._repeat "$hz" "$inner")${tr}"
    fi
    style.reset

    local row
    for (( row = 1; row < h - 1; row++ )); do
        cur.goto $(( r + row )) "$c"
        _tui._apply_style "$style_key" "${id}_border"; echo -n "$vt"; style.reset
        cur.goto $(( r + row )) $(( c + w - 1 ))
        _tui._apply_style "$style_key" "${id}_border"; echo -n "$vt"; style.reset
    done

    cur.goto $(( r + h - 1 )) "$c"
    _tui._apply_style "$style_key" "${id}_border"
    echo -n "${bl}$(_tui._repeat "$hz" "$inner")${br}"
    style.reset
}

_tui._draw_widget() {
    local id="$1"
    local type="${_TUI_W_TYPE[$id]:-}"
    [[ -z "$type" ]] && return
    local focused=0
    [[ "$_TUI_FOCUS_ID" == "$id" ]] && focused=1
    local hovered=0
    [[ "$_TUI_HOVERED_WIDGET" == "$id" ]] && hovered=1

    _tui._pane_too_small "${_TUI_W_PANE[$id]}" && return

    _tui._widget_pos "$id"
    local sr=$_WSR sc=$_WSC sw=$_WSW

    local minw="${_TUI_W_MINW[$id]:-0}"
    if (( minw > 0 && _WSW_AVAIL < minw )); then
        cur.goto "$sr" "$sc"
        printf '%*s' "$_WSW_AVAIL" ""
        cur.goto "$sr" "$sc"
        style.reset; style.bold; fg.hex "FF3333" 2>/dev/null
        printf '%.*s' "$_WSW_AVAIL" "min space = ${minw}"
        style.reset
        return
    fi

    cur.goto "$sr" "$sc"
    printf '%*s' "$sw" ""
    cur.goto "$sr" "$sc"

    local pane_id="${_TUI_W_PANE[$id]}"
    local pane_key="${pane_id}_normal"
    local style_key="${id}_normal"
    if (( focused )); then
        style_key="${id}_focus"
    elif (( hovered )); then
        style_key="${id}_hover"
    fi

    case "$type" in
        label)
            local calign; calign="$(_tui._widget_align "$id")"
            local text; text="$(_tui._resolve_text "${_TUI_W_VALUE[$id]}")"
            text="${text:0:$sw}"
            _tui._apply_style "$style_key" "$pane_key"
            if [[ "$calign" == "fill" ]]; then
                local pad=$(( (sw - ${#text}) / 2 )); (( pad < 0 )) && pad=0
                local rem=$(( sw - pad - ${#text} )); (( rem < 0 )) && rem=0
                cur.goto "$sr" "$sc"
                printf '%*s%s%*s' "$pad" "" "$text" "$rem" ""
            else
                cur.goto "$sr" "$sc"
                printf '%*s' "$sw" ""
                local pad; pad=$(_tui._align_pad "$calign" "${#text}" "$sw")
                cur.goto "$sr" $(( sc + pad ))
                echo -n "$text"
            fi
            style.reset
            ;;
        button)
            local calign; calign="$(_tui._widget_align "$id")"
            local lbl; lbl="$(_tui._resolve_text "${_TUI_W_LABEL[$id]}")"

            _tui._apply_style "$style_key" "$pane_key"
            if (( focused )); then
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" && -z "${_TUI_STYLE_BG[$style_key]:-}" ]] && style.reverse
            else
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && style.dim
            fi

            if [[ "$calign" == "fill" ]]; then
                local pad=$(( (sw - ${#lbl}) / 2 )); (( pad < 0 )) && pad=0
                local rem=$(( sw - pad - ${#lbl} )); (( rem < 0 )) && rem=0
                cur.goto "$sr" "$sc"
                printf '%*s%s%*s' "$pad" "" "$lbl" "$rem" ""
            else
                cur.goto "$sr" "$sc"
                printf '%*s' "$sw" ""
                local pad; pad=$(_tui._align_pad "$calign" "${#lbl}" "$sw")
                cur.goto "$sr" $(( sc + pad ))
                echo -n "$lbl"
            fi
            style.reset
            ;;
        checkbox)
            local calign; calign="$(_tui._widget_align "$id")"
            local mark="[ ]"
            [[ "${_TUI_W_VALUE[$id]}" == "1" ]] && mark="[x]"
            local lbl; lbl="${mark} $(_tui._resolve_text "${_TUI_W_LABEL[$id]}")"

            _tui._apply_style "$style_key" "$pane_key"
            if (( focused )); then
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" && -z "${_TUI_STYLE_BG[$style_key]:-}" ]] && style.reverse
            else
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && style.dim
            fi

            if [[ "$calign" == "fill" ]]; then
                local pad=$(( (sw - ${#lbl}) / 2 )); (( pad < 0 )) && pad=0
                local rem=$(( sw - pad - ${#lbl} )); (( rem < 0 )) && rem=0
                cur.goto "$sr" "$sc"
                printf '%*s%s%*s' "$pad" "" "$lbl" "$rem" ""
            else
                cur.goto "$sr" "$sc"
                printf '%*s' "$sw" ""
                local pad; pad=$(_tui._align_pad "$calign" "${#lbl}" "$sw")
                cur.goto "$sr" $(( sc + pad ))
                echo -n "$lbl"
            fi
            style.reset
            ;;
        input)
            local prefix="${_TUI_W_LABEL[$id]}"
            local value="${_TUI_W_VALUE[$id]}"
            local placeholder="${_TUI_W_PH[$id]:-}"

            local plen=0
            if [[ -n "$prefix" ]]; then
                local lbox="${_TUI_W_LABEL_WIDTH[$id]:-$(( ${#prefix} + 1 ))}"
                (( lbox < 1 )) && lbox=1
                local lshown="${prefix:0:$lbox}"
                local lpad; lpad=$(_tui._align_pad "${_TUI_W_LABEL_ALIGN[$id]:-left}" "${#lshown}" "$lbox")

                style.bold
                printf '%*s' "$lpad" ""
                printf '%s' "$lshown"
                printf '%*s' "$(( lbox - lpad - ${#lshown} ))" ""
                style.reset
                plen=$lbox
            fi

            local fw=$(( sw - plen ))       
            (( fw < 2 )) && fw=2

            _tui._apply_style "$style_key" "$pane_key"
            if (( focused )); then
                local scroll=0
                if (( _TUI_CURSOR >= fw )); then
                    scroll=$(( _TUI_CURSOR - fw + 1 ))
                fi
                local visible="${value:$scroll:$fw}"

                style.underline
                printf '%-*s' "$fw" "$visible"
                style.reset; _tui._apply_style "$style_key" "$pane_key"

                local cpos=$(( _TUI_CURSOR - scroll ))
                cur.goto "$sr" $(( sc + plen + cpos ))
                style.reverse
                if (( _TUI_CURSOR < ${#value} )); then
                    echo -n "${value:$_TUI_CURSOR:1}"
                else
                    echo -n " "
                fi
            else
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && style.dim
                local shown="${value:-$placeholder}"
                shown="${shown:0:$fw}"
                local pad; pad=$(_tui._align_pad "$(_tui._widget_align "$id")" "${#shown}" "$fw")
                printf '%*s' "$pad" ""
                printf '%-*s' "$(( fw - pad ))" "$shown"
            fi
            style.reset
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════
#  PERFORMANCE TRACKING — opt-in, off by default. When on, every frame
#  written through _tui._flush (the single choke point every synchronized
#  write in this file goes through) is timestamped, so tui.perf.mean_render_ms
#  can answer "how expensive has rendering actually been lately" from
#  inside a running page — see docs/ui_markup.md.
# ═══════════════════════════════════════════════════════════════════════

declare -g  _TUI_PERF_TRACKING=0
declare -ga _TUI_RENDER_LOG_T=()   # integer microseconds-since-epoch per tracked flush
declare -ga _TUI_RENDER_LOG_MS=()  # that flush's duration, integer ms
declare -g  _TUI_NOW_US=0

# _tui._now_us — sets _TUI_NOW_US to the current time in integer
# microseconds. Fork-free via bash 5's $EPOCHREALTIME (plain integer
# arithmetic on its two halves) when available; falls back to a forking
# `date` call on older bash. Only ever called while _TUI_PERF_TRACKING is
# on, so this cost is opt-in, never paid by a page that doesn't ask for it.
#
# $EPOCHREALTIME's decimal separator follows LC_NUMERIC, not always a
# literal "." (e.g. de_DE.UTF-8 uses ","), so splitting on "." silently
# failed under that locale — both halves came back as the whole,
# unsplit string, and `10#` on a comma-containing value crashed with
# "value too great for base". Splitting on the first/last NON-DIGIT
# character instead works regardless of what that separator is.
_tui._now_us() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local s="${EPOCHREALTIME%%[^0-9]*}" us="${EPOCHREALTIME##*[^0-9]}"
        _TUI_NOW_US=$(( 10#$s * 1000000 + 10#$us ))
    else
        _TUI_NOW_US=$(( $(date +%s%N) / 1000 ))
    fi
}

# _tui._flush BUF — the one place a fully-composed frame actually reaches
# the terminal: wraps it in DEC synchronized-output mode and prints it in
# a single write, exactly as every call site here already did before this
# existed — consolidated so there's one place to add instrumentation
# instead of five near-identical copies of the same three lines. Timing
# only happens while _TUI_PERF_TRACKING is on.
_tui._flush() {
    local buf="$1"
    if (( ! _TUI_PERF_TRACKING )); then
        mode.sync_start
        printf '%s' "$buf"
        mode.sync_end
        return
    fi

    _tui._now_us; local t0=$_TUI_NOW_US
    mode.sync_start
    printf '%s' "$buf"
    mode.sync_end
    _tui._now_us; local t1=$_TUI_NOW_US

    _TUI_RENDER_LOG_T+=("$t1")
    _TUI_RENDER_LOG_MS+=("$(( (t1 - t0) / 1000 ))")
    if (( ${#_TUI_RENDER_LOG_T[@]} > 2000 )); then
        _TUI_RENDER_LOG_T=("${_TUI_RENDER_LOG_T[@]: -1000}")
        _TUI_RENDER_LOG_MS=("${_TUI_RENDER_LOG_MS[@]: -1000}")
    fi
}

# tui.perf.mean_render_ms SECONDS — mean duration (ms) of every tracked
# frame flushed within the trailing SECONDS window. Empty string if
# tracking is off or nothing fell in the window (a caller can treat that
# the same as "no data yet").
tui.perf.mean_render_ms() {
    local window="$1"
    (( _TUI_PERF_TRACKING )) || return
    local n=${#_TUI_RENDER_LOG_T[@]}
    (( n == 0 )) && return

    _tui._now_us
    local cutoff=$(( _TUI_NOW_US - window * 1000000 ))
    local i sum=0 count=0
    for (( i = n - 1; i >= 0; i-- )); do
        (( _TUI_RENDER_LOG_T[i] < cutoff )) && break
        (( sum += _TUI_RENDER_LOG_MS[i] ))
        (( count++ ))
    done
    (( count == 0 )) && return
    printf '%s' "$(( sum / count ))"
}

tui.render() {
    # Refresh the content-fit cache in THIS shell, before the buffer-
    # building command substitution below. _tui._draw_pane (called inside
    # that subshell) also calls _tui._refresh_content_fit, but writes an
    # associative array makes inside a subshell never reach the parent —
    # only that subshell's own stdout survives. Without this pre-pass,
    # _TUI_P_EFFECTIVE_MINW/_MINH stayed permanently empty in the running
    # shell, so every later hover/focus/click-triggered redraw (which runs
    # outside this subshell) silently fell back to "no minimum" instead of
    # the real, just-computed one — the pane's border/content correctly
    # showed a size warning on the very first render, then losing and
    # regaining that warning on every redraw after, depending on which
    # code path happened to read the (actually empty) cache.
    local pane
    for pane in "${_TUI_P_ALL[@]}"; do
        [[ -z "${_TUI_P_CHILDREN[$pane]:-}" ]] && _tui._refresh_content_fit "$pane"
    done

    local buf
    buf="$(
        for pane in "${_TUI_P_ALL[@]}"; do
            if [[ -n "${_TUI_P_CHILDREN[$pane]:-}" ]]; then
                _tui._fill_pane_bg "$pane" "${_TUI_P_ROW[$pane]}" "${_TUI_P_COL[$pane]}" "${_TUI_P_H[$pane]}" "${_TUI_P_W[$pane]}"
            else
                _tui._draw_pane "$pane"
            fi
        done
        for wid in "${_TUI_W_ORDER[@]}"; do
            _tui._draw_widget "$wid"
        done
        for _oid in "${!_TUI_PANE_CONTENT[@]}"; do
            [[ -n "${_TUI_PANE_CONTENT[$_oid]}" ]] && _tui._render_output "$_oid"
        done
    )"
    _tui._flush "$buf"
}

tui.redraw() { tui.render; }

tui.clear_pane() {
    local id="$1"
    local r=${_TUI_P_ROW[$id]}  c=${_TUI_P_COL[$id]}
    local h=${_TUI_P_H[$id]}    w=${_TUI_P_W[$id]}
    local b="${_TUI_P_BORDER[$id]:-single}"

    local sr sc sh sw
    if [[ "$b" == "none" ]]; then
        sr=$r; sc=$((c+1)); sh=$h; sw=$((w-2))
    else
        sr=$((r+1)); sc=$((c+1)); sh=$((h-2)); sw=$((w-2))
    fi

    local blank; printf -v blank '%*s' "$sw" ""
    for (( row = 0; row < sh; row++ )); do
        cur.goto $(( sr + row )) "$sc"
        echo -n "$blank"
    done
}

# ═══════════════════════════════════════════════════════════════════════
#  Scrolling
# ═══════════════════════════════════════════════════════════════════════

declare -g _HIT_PANE=""

# Full linear scan over every leaf pane, resolving into _HIT_PANE (empty if
# none matched) rather than printing — a caller capturing the old printf
# via `$(...)` was forking a subshell on every single mouse event, the one
# unconditional per-event cost hover-crossing a pane ever had left after
# borders stopped reacting to hover. Called directly only on the first
# resolution and after _tui._locate_pane's cache below has confirmed the
# pointer actually left the previously hovered pane.
_tui._pane_at() {
    local mx="$1" my="$2"
    _HIT_PANE=""
    for p in "${_TUI_P_ALL[@]}"; do
        [[ -z "${_TUI_P_CHILDREN[$p]:-}" ]] || continue
        if (( my >= _TUI_P_ROW[$p] && my < _TUI_P_ROW[$p] + _TUI_P_H[$p] &&
              mx >= _TUI_P_COL[$p] && mx < _TUI_P_COL[$p] + _TUI_P_W[$p] )); then
            _HIT_PANE="$p"
            return
        fi
    done
}

# _tui._locate_pane MX MY — resolves the pane under the pointer into
# _HIT_PANE, short-circuiting the full scan above: as long as the pointer
# is still inside whichever pane was hovered last, this is four integer
# comparisons and nothing else — no loop, no function call into the scan,
# no fork. The O(panes) scan only runs at an actual boundary crossing.
_tui._locate_pane() {
    local mx="$1" my="$2" cur="$_TUI_HOVERED_PANE"
    if [[ -n "$cur" ]] && (( my >= _TUI_P_ROW[$cur] && my < _TUI_P_ROW[$cur] + _TUI_P_H[$cur] &&
                              mx >= _TUI_P_COL[$cur] && mx < _TUI_P_COL[$cur] + _TUI_P_W[$cur] )); then
        _HIT_PANE="$cur"
        return
    fi
    _tui._pane_at "$mx" "$my"
}

_tui._scroll_kb() {
    local dir="$1"
    local p="${_TUI_HOVERED_PANE:-}"
    
    [[ -z "$p" && -n "$_TUI_FOCUS_ID" ]] && p="${_TUI_W_PANE[$_TUI_FOCUS_ID]}"
    
    if [[ -z "$p" || "${_TUI_P_SCROLL[$p]:-none}" == "none" ]]; then
        for target in "${_TUI_P_ALL[@]}"; do
            if [[ "${_TUI_P_SCROLL[$target]:-none}" != "none" ]]; then
                p="$target"
                break
            fi
        done
    fi
    
    [[ -z "$p" || "${_TUI_P_SCROLL[$p]:-none}" == "none" ]] && return

    case "$dir" in
        up)    (( _TUI_P_SOFF_V[$p] -= 3 )) ;;
        down)  (( _TUI_P_SOFF_V[$p] += 3 )) ;;
        left)  (( _TUI_P_SOFF_H[$p] -= 5 )) ;;
        right) (( _TUI_P_SOFF_H[$p] += 5 )) ;;
    esac
    
    _tui._queue_render "$p"
}

# _tui._queue_render PANE — marks a pane's content dirty and arms the
# shared debounce countdown if it isn't already running. The actual AWK
# render is deferred to _tui._flush_pending_render, so a burst of scroll
# events (wheel spin, drag-jump) collapses into one redraw of wherever the
# viewport ends up, not one redraw per event.
_tui._queue_render() {
    local pane="$1"
    [[ -z "$pane" ]] && return
    _TUI_PENDING_OUTPUT[$pane]=1
    [[ $_TUI_RENDER_TIMEOUT -lt 0 ]] && _TUI_RENDER_TIMEOUT=3
}

# _tui._flush_pending_render — the single writer for debounced pane-content
# redraws. Builds every pending pane's AWK-rendered frame into ONE buffer
# via one command substitution and emits it as one synchronized write.
_tui._flush_pending_render() {
    (( ${#_TUI_PENDING_OUTPUT[@]} == 0 )) && return

    local buf
    buf="$(
        local id
        for id in "${!_TUI_PENDING_OUTPUT[@]}"; do _tui._render_output "$id"; done
    )"
    _TUI_PENDING_OUTPUT=()

    _tui._flush "$buf"
}

# _tui._draw_ids_now DRAW_FN ID… — calls DRAW_FN once per unique, non-empty
# id, capturing all of it in ONE command substitution and emitting ONE
# synchronized write. This is the "batch, don't debounce" half of the
# picture: for a discrete action (focus moving, a status line updating)
# there's no burst to collapse, just no reason to split one logical update
# across N separate writes to the terminal.
_tui._draw_ids_now() {
    local draw_fn="$1"; shift
    local buf id seen=" "
    buf="$(
        for id in "$@"; do
            [[ -z "$id" || "$seen" == *" $id "* ]] && continue
            seen+="$id "
            "$draw_fn" "$id"
        done
    )"
    [[ -z "$buf" ]] && return
    _tui._flush "$buf"
}

_tui._draw_widgets_now()      { _tui._draw_ids_now _tui._draw_widget "$@"; }
_tui._draw_pane_borders_now() { _tui._draw_ids_now _tui._draw_pane_border "$@"; }

_tui._calc_bounds() {
    local pane="$1"
    declare -n arr="_TUI_PANE_CONTENT_${pane}"
    local total=${#arr[@]}
    _TUI_P_LINES[$pane]=$total
    
    if (( total == 0 )); then
        _TUI_P_MAX_W[$pane]=0
        return
    fi
    
    local max_w=$(printf '%s\n' "${arr[@]}" | awk '{
        gsub(/\033\[[0-9;?]*[A-Za-z]/, "")
        gsub(/\033\][^\007\033]*(\007|\033\\)/, "")
        gsub(/\033[@A-Z\\\-_]/, "")
        l = length($0)
        if (l > max) max = l
    } END { print max+0 }')
    _TUI_P_MAX_W[$pane]=$max_w
}

# ═══════════════════════════════════════════════════════════════════════
#  FOCUS & INPUT MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════

tui.focus() {
    local id="$1" old="$_TUI_FOCUS_ID"
    _TUI_FOCUS_ID="$id"

    for (( i = 0; i < ${#_TUI_FOCUSABLE[@]}; i++ )); do
        [[ "${_TUI_FOCUSABLE[$i]}" == "$id" ]] && { _TUI_FOCUS_IDX=$i; break; }
    done

    [[ "${_TUI_W_TYPE[$id]:-}" == "input" ]] && _TUI_CURSOR=${#_TUI_W_VALUE[$id]}

    _tui._draw_widgets_now "$old" "$id"
    _tui._draw_pane_borders_now "$(_tui._widget_pane "$old")" "$(_tui._widget_pane "$id")"
}

_tui._unfocus() {
    local old="$_TUI_FOCUS_ID"
    _TUI_FOCUS_ID=""
    _TUI_FOCUS_IDX=-1
    _tui._draw_widgets_now "$old"
    _tui._draw_pane_borders_now "$(_tui._widget_pane "$old")"
}

_tui._focus_next() {
    (( ${#_TUI_FOCUSABLE[@]} == 0 )) && return
    _TUI_FOCUS_IDX=$(( (_TUI_FOCUS_IDX + 1) % ${#_TUI_FOCUSABLE[@]} ))
    tui.focus "${_TUI_FOCUSABLE[$_TUI_FOCUS_IDX]}"
}

_tui._focus_prev() {
    (( ${#_TUI_FOCUSABLE[@]} == 0 )) && return
    _TUI_FOCUS_IDX=$(( (_TUI_FOCUS_IDX - 1 + ${#_TUI_FOCUSABLE[@]}) % ${#_TUI_FOCUSABLE[@]} ))
    tui.focus "${_TUI_FOCUSABLE[$_TUI_FOCUS_IDX]}"
}

_tui._hit_test() {
    local mx="$1" my="$2"
    _HIT=""
    for wid in "${_TUI_W_ORDER[@]}"; do
        [[ "${_TUI_W_TYPE[$wid]}" == "label" ]] && continue
        _tui._widget_pos "$wid"
        if (( my == _WSR && mx >= _WSC && mx < _WSC + _WSW )); then
            _HIT="$wid"
            return 0
        fi
    done
    return 1
}

_tui._input_key() {
    local id="$1" key="$2"
    local value="${_TUI_W_VALUE[$id]}"

    case "$key" in
        $'\x7f'|$'\b')
            if (( _TUI_CURSOR > 0 )); then
                _TUI_W_VALUE[$id]="${value:0:$((_TUI_CURSOR-1))}${value:$_TUI_CURSOR}"
                (( _TUI_CURSOR-- ))
            fi
            ;;
        *)
            if [[ ${#key} -eq 1 && "$key" =~ [[:print:]] ]]; then
                _TUI_W_VALUE[$id]="${value:0:$_TUI_CURSOR}${key}${value:$_TUI_CURSOR}"
                (( _TUI_CURSOR++ ))
            fi
            ;;
    esac
    _tui._draw_widget "$id"
}

_tui._input_seq() {
    local id="$1" seq="$2"
    local value="${_TUI_W_VALUE[$id]}"

    case "$seq" in
        "[D")   (( _TUI_CURSOR > 0 ))           && (( _TUI_CURSOR-- ))  ;;
        "[C")   (( _TUI_CURSOR < ${#value} ))    && (( _TUI_CURSOR++ ))  ;;
        "[H"|"[1~")  _TUI_CURSOR=0                                       ;;
        "[F"|"[4~")  _TUI_CURSOR=${#value}                               ;;
        "[3~")
            if (( _TUI_CURSOR < ${#value} )); then
                _TUI_W_VALUE[$id]="${value:0:$_TUI_CURSOR}${value:$((_TUI_CURSOR+1))}"
            fi
            ;;
        *)  return ;;
    esac
    _tui._draw_widget "$id"
}

# _tui._set_hovered_pane tracks which pane the pointer is over purely as
# routing state for scroll-wheel/keyboard-scroll targeting (_tui._scroll_kb,
# the wheel branch of _tui._handle_mouse) — it does NOT trigger any redraw.
# Pane borders only ever change for focus (see _tui._draw_pane_border), so
# hovering a pane costs one assignment and nothing else.
_tui._set_hovered_pane() { _TUI_HOVERED_PANE="$1"; }

# _tui._set_hovered_widget is change-gated (a no-op unless the hovered
# widget actually differs) but, unlike the deferred scroll queue, draws
# immediately via _tui._draw_widgets_now. A button redraw is one cheap,
# single-widget write — there's no fan-out to collapse the way a multi-pane
# sweep used to cause when panes also redrew their borders on hover, so
# debouncing it only added latency between "pointer arrives" and "button
# lights up" without saving any real work. Trading "many more small draws"
# for "instant feedback" is the right side of that tradeoff here.
_tui._set_hovered_widget() {
    local new="$1"
    [[ "$new" == "$_TUI_HOVERED_WIDGET" ]] && return
    local old="$_TUI_HOVERED_WIDGET"
    _TUI_HOVERED_WIDGET="$new"
    (( _TUI_RUNNING )) || return
    _tui._draw_widgets_now "$old" "$new"
}

# _tui._next_byte VARNAME TIMEOUT — reads one byte into VARNAME, like
# `read -rsn1 -t TIMEOUT VARNAME`, except it drains _TUI_PENDING_INPUT
# first if anything was stashed there. Every "give me the next input byte"
# read in tui.run goes through this, so a rewind from the mouse-motion
# coalescer is invisible to the rest of the loop.
_tui._next_byte() {
    local __outvar="$1" __timeout="$2"
    if [[ -n "$_TUI_PENDING_INPUT" ]]; then
        printf -v "$__outvar" '%s' "${_TUI_PENDING_INPUT:0:1}"
        _TUI_PENDING_INPUT="${_TUI_PENDING_INPUT:1}"
        return 0
    fi
    IFS= read -rsn1 -t "$__timeout" "$__outvar"
}

# _tui._read_escape_seq — assembles the rest of an escape sequence (the
# part after ESC) one byte at a time until a terminator or the per-byte
# timeout, leaving the result in _TUI_SEQ_BUF. A `case` terminator check
# instead of a regex match keeps the per-byte cost as low as bash allows;
# it's still one read() per byte, which is exactly what the mouse-motion
# coalescer below exists to stop paying for on events nobody will ever see.
# Goes through _tui._next_byte (not a raw `read`) so that bytes rewound
# into _TUI_PENDING_INPUT by the coalescer are consumed here first, before
# falling through to the real fd — otherwise a rewound sequence would never
# be seen.
_tui._read_escape_seq() {
    _TUI_SEQ_BUF=""
    local c
    while _tui._next_byte c "$TUI_ESCSEQ_BYTE_TIMEOUT"; do
        _TUI_SEQ_BUF+="$c"
        case "$c" in
            [A-Za-z~Mm]) break ;;
        esac
    done
}

# _tui._mouse_seq_is_motion SEQ — true for a pure movement report (bare
# hover, or a drag with a button held): the SGR protocol sets bit 32 on
# the button field for any motion sample and terminates it with 'M'. These
# are the only reports safe to discard in favor of a newer one — presses,
# releases, and wheel notches are one-shot state transitions and must
# never be dropped.
_tui._mouse_seq_is_motion() {
    local seq="${1#\[<}"
    [[ "${seq: -1}" == "M" ]] || return 1
    local btn
    IFS=';' read -r btn _ _ <<< "${seq%[Mm]}"
    (( (btn & 32) != 0 ))
}

# _tui._coalesce_mouse_motion SEQ — given a just-decoded motion sequence,
# peeks ahead for more input already sitting in the buffer and keeps only
# the newest motion report, so hover/drag state is resolved (and redrawn)
# at most once per settled position instead of once per crossed cell.
# Anything peeked that ISN'T a coalescible motion report (a click, a wheel
# notch, a keystroke, a non-mouse escape sequence) is not discarded — it's
# rewound into _TUI_PENDING_INPUT byte-for-byte so the normal dispatch
# logic in tui.run handles it next, in its original order, completely
# unaware a peek ever happened. Leaves the resolved sequence in
# _TUI_SEQ_BUF. TUI_MOUSE_DRAIN_MAX bounds the peek loop so an unbroken
# flood can't stall the rest of the event loop indefinitely.
_tui._coalesce_mouse_motion() {
    local pending="$1" drained=0 c
    while (( drained < TUI_MOUSE_DRAIN_MAX )); do
        IFS= read -rsn1 -t "$TUI_MOUSE_DRAIN_PEEK_TIMEOUT" c || break
        (( drained++ ))

        if [[ "$c" != $'\e' ]]; then
            _TUI_PENDING_INPUT+="$c"
            break
        fi

        _tui._read_escape_seq
        local next="$_TUI_SEQ_BUF"

        if [[ "$next" == "[<"* ]] && _tui._mouse_seq_is_motion "$next"; then
            pending="$next"
            continue
        fi

        _TUI_PENDING_INPUT+=$'\e'"$next"
        break
    done
    _TUI_SEQ_BUF="$pending"
}

_tui._handle_mouse() {
    local seq="$1"
    seq="${seq#\[<}"
    local end="${seq: -1}"
    seq="${seq%[Mm]}"

    IFS=';' read -r btn mx my <<< "$seq"

    _tui._locate_pane "$mx" "$my"
    _tui._set_hovered_pane "$_HIT_PANE"

    local hover_widget=""
    _tui._hit_test "$mx" "$my" && hover_widget="$_HIT"
    _tui._set_hovered_widget "$hover_widget"

    if [[ -n "$_TUI_ON_INPUT_EVENT" ]]; then
        local kind="move"
        if (( btn >= 64 && btn <= 69 )); then kind="wheel"
        elif [[ "$end" == "m" ]]; then kind="release"
        elif ! _tui._mouse_seq_is_motion "$1"; then kind="press"
        fi
        _tui._notify_input "mouse $kind btn=$btn (${mx},${my}) widget=${hover_widget:--} pane=${_HIT_PANE:--}"
    fi

    [[ "$end" == "m" ]] && return

    if (( btn >= 64 && btn <= 69 )); then
        local p="$_TUI_HOVERED_PANE"
        if [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != "none" ]]; then
            case "$btn" in
                64) (( _TUI_P_SOFF_V[$p] -= 3 )) ;;
                65) (( _TUI_P_SOFF_V[$p] += 3 )) ;;
                68) (( _TUI_P_SOFF_H[$p] -= 5 )) ;;
                69) (( _TUI_P_SOFF_H[$p] += 5 )) ;;
            esac
            _tui._queue_render "$p"
        fi
        return
    fi

    # Jump-to-click only applies while the left button is actually down
    # (0 = press, 32 = drag with it held) — bare hover motion (btn 35, no
    # button) must fall through untouched, or hovering a scrollbar track
    # would snap the viewport as if it had been clicked.
    local p="$_TUI_HOVERED_PANE"
    if [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != "none" ]] && (( btn == 0 || btn == 32 )); then
        if (( mx == _TUI_P_COL[$p] + _TUI_P_W[$p] - 1 )); then
            local rel_y=$(( my - _TUI_P_ROW[$p] ))
            local total_lines=${_TUI_P_LINES[$p]:-1}
            local target=$(( (rel_y * total_lines) / _TUI_P_H[$p] ))
            _TUI_P_SOFF_V[$p]=$target
            _tui._queue_render "$p"
            return
        fi
        if (( my == _TUI_P_ROW[$p] + _TUI_P_H[$p] - 1 )); then
            local rel_x=$(( mx - _TUI_P_COL[$p] ))
            local max_w=${_TUI_P_MAX_W[$p]:-1}
            local target=$(( (rel_x * max_w) / _TUI_P_W[$p] ))
            _TUI_P_SOFF_H[$p]=$target
            _tui._queue_render "$p"
            return
        fi
    fi
    
    (( btn != 0 )) && return

    if [[ -n "$hover_widget" ]]; then
        local wid="$hover_widget"
        local wtype="${_TUI_W_TYPE[$wid]}"

        if [[ "$wtype" == "button" ]]; then
            tui.focus "$wid"
            local action="${_TUI_W_ACTION[$wid]:-}"
            [[ -n "$action" ]] && "$action" "$wid"

        elif [[ "$wtype" == "checkbox" ]]; then
            tui.focus "$wid"
            tui.checkbox.toggle "$wid"

        elif [[ "$wtype" == "input" ]]; then
            tui.focus "$wid"
            local prefix="${_TUI_W_LABEL[$wid]}"
            local plen=0
            [[ -n "$prefix" ]] && plen=$(( ${#prefix} + 1 ))
            local click=$(( mx - _WSC - plen ))
            (( click < 0 )) && click=0
            local vlen=${#_TUI_W_VALUE[$wid]}
            (( click > vlen )) && click=$vlen
            _TUI_CURSOR=$click
            _tui._draw_widget "$wid"
        fi
    else
        _tui._unfocus
    fi
}

# ═══════════════════════════════════════════════════════════════════════
#  GENERIC BACKGROUND EXECUTION (tui.exec)
# ═══════════════════════════════════════════════════════════════════════

tui.exec() {
    local cmd="$1" out_pane="$2" ctl_pane="$3"
    tui.log.info "tui.exec() initiating command: '$cmd'"

    if [[ -z "$cmd" || -z "$out_pane" || -z "$ctl_pane" ]]; then
        tui.log.error "tui.exec: Fatal config error. Missing arguments."
        return 1
    fi

    if [[ -z "${_TUI_P_ROW[$out_pane]:-}" || -z "${_TUI_P_ROW[$ctl_pane]:-}" ]]; then
        tui.log.warn "tui.exec: Pane configuration broken. '$out_pane' or '$ctl_pane' missing."
        printf '\e7\e[1;1H\e[41;37m ERROR: Pane configuration broken. Launching in degraded mode. \e[0m\e8'
    fi

    _exec_cleanup_process
    _exec_remove_widgets

    _EXEC_CMD="$cmd"
    _EXEC_OUT_PANE="$out_pane"
    _EXEC_CTL_PANE="$ctl_pane"
    _EXEC_BUF=()
    _EXEC_LAST_READ=0
    _EXEC_STATUS="running"
    _EXEC_EXIT=""

    _EXEC_TMPDIR=$(mktemp -d /tmp/tui_exec.XXXXXX)
    _EXEC_OUTFILE="${_EXEC_TMPDIR}/out"
    _EXEC_FIFO="${_EXEC_TMPDIR}/in"

    touch "$_EXEC_OUTFILE"
    mkfifo "$_EXEC_FIFO"

    exec {_EXEC_FIFO_FD}<>"$_EXEC_FIFO"

    script -q -e -c "$cmd" /dev/null < "$_EXEC_FIFO" >> "$_EXEC_OUTFILE" 2>&1 &    
    _EXEC_PID=$!

    _exec_setup_output_pane
    _exec_setup_controls

    _TUI_TICK_FN="_exec_tick"

    if (( _TUI_RUNNING )); then
        tui.clear_pane "$out_pane"
        tui.clear_pane "$ctl_pane"
        _tui._draw_pane "$out_pane"
        _tui._draw_pane "$ctl_pane"
        for wid in "${_TUI_W_ORDER[@]}"; do
            [[ "$wid" == _x* ]] && _tui._draw_widget "$wid"
        done
        _exec_render_status
    fi
}

_exec_setup_output_pane() {
    local pane="$_EXEC_OUT_PANE"
    local ph=${_TUI_P_H[$pane]}
    local border="${_TUI_P_BORDER[$pane]:-single}"

    if [[ "$border" == "none" ]]; then
        _EXEC_VROWS=$ph
    else
        _EXEC_VROWS=$(( ph - 2 ))
    fi

    tui.label "_xhdr" "$pane" 0 ""
}

_exec_setup_controls() {
    tui.log.debug "_exec_setup_controls() called"
    local pane="$_EXEC_CTL_PANE"

    tui.label  "_xstat"    "$pane" 0 ""
    tui.button "_xcancel"  "$pane" 1 "[ Cancel ]"        _exec_on_cancel
    tui.button "_xsave"    "$pane" 2 "[ Save Output ]"   _exec_on_save
    tui.button "_xview"    "$pane" 3 "[ View Command ]"  _exec_on_view
    tui.button "_xretry"   "$pane" 4 "[ Retry ]"         _exec_on_retry
    tui.button "_xback"    "$pane" 5 "[ Back ]"          _exec_on_back
    
    tui.input  "_xinput"   "$pane" 6 "type and press Enter…" "stdin▸"
    tui.on_action "_xinput" _exec_on_send
}

_exec_remove_widgets() {
    tui.log.debug "_exec_remove_widgets() called"
    local new_order=() new_focus=()
    for w in "${_TUI_W_ORDER[@]}"; do
        [[ "$w" == _x* ]] || new_order+=("$w")
    done
    for w in "${_TUI_FOCUSABLE[@]}"; do
        [[ "$w" == _x* ]] || new_focus+=("$w")
    done
    _TUI_W_ORDER=("${new_order[@]}")
    _TUI_FOCUSABLE=("${new_focus[@]}")

    [[ "${_TUI_FOCUS_ID:-}" == _x* ]] && _TUI_FOCUS_ID="" && _TUI_FOCUS_IDX=-1
}

_exec_strip_ansi() {
    local raw="$1"
  printf '%s' "$1" | awk '{
    gsub(/\r/, "")
    gsub(/\033\[[0-9;?]*[A-Za-z]/, "")
    gsub(/\033\][^\007\033]*(\007|\033\\)/, "")
    gsub(/\033[@A-Z\\\-_]/, "")
    gsub(/\033P[^\033]*\033\\/, "")
    printf "%s", $0
  }'
}

_exec_clean_line() {
    printf '%s' "$1" | awk '{
        gsub(/\r/, "")
        gsub(/\033\][^\007\033]*(\007|\033\\)/, "")
        gsub(/\033P[^\033]*\033\\/, "")
        gsub(/\033[@A-Z\\\-_]/, "")
        out = ""
        s = $0
        while (s != "") {
            p = index(s, "\033")
            if (p == 0) { out = out s; break }
            if (p > 1)  { out = out substr(s, 1, p - 1) }
            s = substr(s, p)
            if (substr(s, 2, 1) == "[") {
                if (match(s, /^\033\[[0-9;?]*[a-zA-Z]/)) {
                    seq = substr(s, 1, RLENGTH)
                    fin = substr(seq, RLENGTH, 1)
                    if (fin == "m") out = out seq
                    s = substr(s, RLENGTH + 1)
                } else { s = substr(s, 2) }
            } else { s = substr(s, 2) }
        }
        printf "%s", out
    }'
}

_exec_is_screen_clear() {
    local raw="$1"
    [[ "$raw" == *$'\033c'* ]] || [[ "$raw" == *$'\033[H'* ]] || [[ "$raw" == *$'\033[J'* ]] || [[ "$raw" == *$'\033[2J'* ]]
}

_exec_is_alt_buffer_toggle() {
    local raw="$1"
    [[ "$raw" == *$'\033[?1049h'* ]] || [[ "$raw" == *$'\033[?1049l'* ]] ||
    [[ "$raw" == *$'\033[?47h'* ]] || [[ "$raw" == *$'\033[?47l'* ]] ||
    [[ "$raw" == *$'\033[?1047h'* ]] || [[ "$raw" == *$'\033[?1047l'* ]]
}

_exec_is_line_clear() {
    local raw="$1"
    [[ "$raw" == *$'\033[K'* ]] || [[ "$raw" == *$'\033[2K'* ]]
}

_exec_tick() {
    [[ "$_EXEC_STATUS" == "running" ]] || return

    local changed=0
    if [[ -s "$_EXEC_OUTFILE" ]]; then
        local new_lines=()
        mapfile -t new_lines < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        if (( ${#new_lines[@]} > 0 )); then
            local raw_line clean_line
            for raw_line in "${new_lines[@]}"; do
                if _exec_is_screen_clear "$raw_line" || _exec_is_alt_buffer_toggle "$raw_line"; then
                    _EXEC_BUF=()
                    changed=1
                    continue
                fi

                if _exec_is_line_clear "$raw_line"; then
                    if (( ${#_EXEC_BUF[@]} > 0 )); then
                        _EXEC_BUF[$(( ${#_EXEC_BUF[@]} - 1 ))]=""
                        changed=1
                    fi
                    continue
                fi

                clean_line="$(_exec_clean_line "$raw_line")"
                _EXEC_BUF+=("$clean_line")
                
                if (( ${#_EXEC_BUF[@]} > 2500 )); then
                    _EXEC_BUF=("${_EXEC_BUF[@]:500}")
                fi
                _TUI_P_LINES[$_EXEC_OUT_PANE]=${#_EXEC_BUF[@]}
                local last_len=$(printf '%s' "${_EXEC_BUF[-1]:-}" | awk '{gsub(/\033\[[0-9;?]*[A-Za-z]/,""); print length($0)}')
                (( last_len > ${_TUI_P_MAX_W[$_EXEC_OUT_PANE]:-0} )) && _TUI_P_MAX_W[$_EXEC_OUT_PANE]=$last_len
                
                changed=1
            done
            (( _EXEC_LAST_READ += ${#new_lines[@]} ))
        fi
    fi

    if ! kill -0 "$_EXEC_PID" 2>/dev/null; then
        wait "$_EXEC_PID" 2>/dev/null
        _EXEC_EXIT=$?

        local leftover=()
        mapfile -t leftover < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        if (( ${#leftover[@]} > 0 )); then
            local raw_line clean_line
            for raw_line in "${leftover[@]}"; do
                if _exec_is_screen_clear "$raw_line" || _exec_is_alt_buffer_toggle "$raw_line"; then
                    _EXEC_BUF=()
                    changed=1
                    continue
                fi

                if _exec_is_line_clear "$raw_line"; then
                    if (( ${#_EXEC_BUF[@]} > 0 )); then
                        _EXEC_BUF[$(( ${#_EXEC_BUF[@]} - 1 ))]=""
                        changed=1
                    fi
                    continue
                fi

                clean_line="$(_exec_clean_line "$raw_line")"
                _EXEC_BUF+=("$clean_line")
                
                if (( ${#_EXEC_BUF[@]} > 2500 )); then
                    _EXEC_BUF=("${_EXEC_BUF[@]:500}")
                fi
                _TUI_P_LINES[$_EXEC_OUT_PANE]=${#_EXEC_BUF[@]}
                local last_len=$(printf '%s' "${_EXEC_BUF[-1]:-}" | awk '{gsub(/\033\[[0-9;?]*[A-Za-z]/,""); print length($0)}')
                (( last_len > ${_TUI_P_MAX_W[$_EXEC_OUT_PANE]:-0} )) && _TUI_P_MAX_W[$_EXEC_OUT_PANE]=$last_len
                
                changed=1
            done
        fi

        if (( _EXEC_EXIT == 0 )); then _EXEC_STATUS="done"; else _EXEC_STATUS="error"; fi

        _exec_render_status
        changed=1
    fi

    (( changed )) && _exec_render_output
}

_exec_render_status() {
    tui.log.debug "_exec_render_status() called"
    local icon
    case "$_EXEC_STATUS" in
        running)   icon="● RUNNING  PID ${_EXEC_PID}"  ;;
        done)      icon="✔ DONE     exit ${_EXEC_EXIT}" ;;
        error)     icon="✖ ERROR    exit ${_EXEC_EXIT}" ;;
        cancelled) icon="■ CANCELLED"                    ;;
        *)         icon="○ IDLE"                         ;;
    esac

    tui.set "_xstat" "$icon"

    local short="$_EXEC_CMD"
    _tui._widget_pos "_xhdr"
    (( ${#short} > _WSW - 2 )) && short="${short:0:$((_WSW - 5))}..."
    tui.set "_xhdr" "$ ${short}"

    _tui._draw_widgets_now "_xstat" "_xhdr"
}

_exec_render_output() {
    declare -g -a "_TUI_PANE_CONTENT_${_EXEC_OUT_PANE}"
    declare -n pane_arr="_TUI_PANE_CONTENT_${_EXEC_OUT_PANE}"
    pane_arr=("${_EXEC_BUF[@]}")
    _tui._render_output "$_EXEC_OUT_PANE"
}

_exec_on_cancel() {
    [[ "$_EXEC_STATUS" != "running" ]] && return
    kill -TERM "$_EXEC_PID" 2>/dev/null
    { sleep 0.15; kill -KILL "$_EXEC_PID" 2>/dev/null; } &
    wait "$_EXEC_PID" 2>/dev/null

    _EXEC_STATUS="cancelled"
    _EXEC_BUF+=("--- process cancelled (PID ${_EXEC_PID}) ---")
    _exec_render_status
    _exec_render_output
}

_exec_on_save() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local savefile="exec_output_${ts}.log"

    if printf '%s\n' "${_EXEC_BUF[@]}" > "$savefile" 2>/dev/null; then
        _EXEC_BUF+=("── saved → $(pwd)/${savefile} ──")
    else
        savefile="${_EXEC_TMPDIR}/output_${ts}.log"
        printf '%s\n' "${_EXEC_BUF[@]}" > "$savefile"
        _EXEC_BUF+=("── saved → ${savefile} ──")
    fi
    _exec_render_output
}

_exec_on_view() {
    _EXEC_BUF+=("┈┈┈ command ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")
    _EXEC_BUF+=("${_EXEC_CMD}")
    local first="${_EXEC_CMD%% *}"
    if [[ -f "$first" && -r "$first" ]]; then
        _EXEC_BUF+=("┈┈┈ source: ${first} ┈┈┈┈┈┈┈┈┈")
        while IFS= read -r src_line; do
            _EXEC_BUF+=("  ${src_line}")
        done < "$first"
    fi
    _EXEC_BUF+=("┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")
    _exec_render_output
}

_exec_on_send() {
    local text
    text=$(tui.get "_xinput")
    [[ -z "$text" ]] && return
    
    if [[ "$_EXEC_STATUS" == "running" ]]; then
        ( printf "%s\n" "$text" >&"$_EXEC_FIFO_FD" & ) 2>/dev/null
        local masked
        masked="$(printf '%*s' "${#text}" | tr ' ' '*')"
        _EXEC_BUF+=("▸ ${masked}")
    else
        _EXEC_BUF+=("(process not running — input discarded)")
    fi

    tui.set "_xinput" ""
    _tui._draw_widget "_xinput"
    _exec_render_output
}

# ═══════════════════════════════════════════════════════════════════════
#  PANE OUTPUT — render arbitrary multi-line content into a pane
# ═══════════════════════════════════════════════════════════════════════

tui.output() {
    local pane="$1"; shift
    _TUI_PANE_CONTENT[$pane]=1
    declare -g -a "_TUI_PANE_CONTENT_${pane}"
    declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"

    pane_arr=()
    if [[ $# -gt 0 ]]; then
        mapfile -t pane_arr < <(printf '%s' "$*")
    else
        mapfile -t pane_arr
    fi
    _tui._calc_bounds "$pane"
    (( _TUI_RUNNING )) && _tui._queue_render "$pane"
}

tui.output_append() {
    local pane="$1"; shift
    _TUI_PANE_CONTENT[$pane]=1
    declare -g -a "_TUI_PANE_CONTENT_${pane}"
    declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"

    if [[ $# -gt 0 ]]; then
        local -a new_lines
        mapfile -t new_lines < <(printf '%s' "$*")
        pane_arr+=("${new_lines[@]}")
    else
        local -a new_lines
        mapfile -t new_lines
        pane_arr+=("${new_lines[@]}")
    fi
    _tui._calc_bounds "$pane"
    (( _TUI_RUNNING )) && _tui._queue_render "$pane"
}

tui.output_clear() {
    local pane="$1"
    _TUI_PANE_CONTENT[$pane]=""
    declare -g -a "_TUI_PANE_CONTENT_${pane}"
    declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"
    pane_arr=()
    
    if (( _TUI_RUNNING )); then
        tui.clear_pane "$pane"
        _tui._draw_pane "$pane"
    fi
}

_tui._render_output() {
    local pane="$1"
    declare -n lines="_TUI_PANE_CONTENT_${pane}"
    local scroll="${_TUI_P_SCROLL[$pane]:-none}"

    local pr=${_TUI_P_ROW[$pane]}  pc=${_TUI_P_COL[$pane]}
    local ph=${_TUI_P_H[$pane]}    pw=${_TUI_P_W[$pane]}
    local border="${_TUI_P_BORDER[$pane]:-single}"

    local ct_row ct_col ct_w ct_h
    if [[ "$border" == "none" ]]; then
        ct_row=$pr; ct_col=$(( pc + 1 )); ct_w=$(( pw - 2 )); ct_h=$ph
    else
        ct_row=$(( pr + 1 )); ct_col=$(( pc + 2 )); ct_w=$(( pw - 4 )); ct_h=$(( ph - 2 ))
    fi
    (( ct_w < 1 )) && ct_w=1
    (( ct_h < 1 )) && ct_h=1

    local total_lines=${_TUI_P_LINES[$pane]:-0}
    local max_w=${_TUI_P_MAX_W[$pane]:-0}
    
    # 1. Enforce Offset Clamping
    local v_off=${_TUI_P_SOFF_V[$pane]:-0}
    local h_off=${_TUI_P_SOFF_H[$pane]:-0}
    
    (( total_lines <= ct_h )) && v_off=0
    (( v_off > total_lines - ct_h && total_lines > ct_h )) && v_off=$(( total_lines - ct_h ))
    (( v_off < 0 )) && v_off=0
    _TUI_P_SOFF_V[$pane]=$v_off

    (( max_w <= ct_w )) && h_off=0
    (( h_off > max_w - ct_w && max_w > ct_w )) && h_off=$(( max_w - ct_w ))
    (( h_off < 0 )) && h_off=0
    _TUI_P_SOFF_H[$pane]=$h_off

    # Collect visible slice directly from memory
    local -a view_lines=()
    local start_idx=$v_off
    local end_idx=$(( v_off + ct_h ))
    (( end_idx > total_lines )) && end_idx=$total_lines
    
    for (( i=start_idx; i<end_idx; i++ )); do
        view_lines+=("${lines[$i]:-}")
    done

    local pane_style="${pane}_normal"
    local sty="$(printf '%b' "$(_tui._apply_style "$pane_style")")"
    local res="$(printf '%b' "\e[0m")"

    # 2. Render Text Area via AWK (SINGLE PASS)
    local frame_buf=""
    if (( ct_h > 0 )); then
        frame_buf=$(
            { (( ${#view_lines[@]} > 0 )) && printf '%s\n' "${view_lines[@]}"; } | awk -v r="$ct_row" -v c="$ct_col" -v w="$ct_w" -v h="$ct_h" -v hoff="$h_off" -v sty="$sty" -v res="$res" '
            function visible_slice(s, off, max) {
                out = ""; vis = 0; skipped = 0
                while (s != "" && vis < max) {
                    p = index(s, "\033")
                    if (p == 0) {
                        if (skipped < off) {
                            chunk_len = length(s)
                            if (skipped + chunk_len <= off) { skipped += chunk_len; break }
                            s = substr(s, off - skipped + 1)
                            skipped = off
                        }
                        remain = max - vis
                        out = out (length(s) > remain ? substr(s, 1, remain) : s)
                        break
                    }
                    if (p > 1) {
                        chunk = substr(s, 1, p - 1)
                        if (skipped < off) {
                            chunk_len = length(chunk)
                            if (skipped + chunk_len <= off) { skipped += chunk_len; chunk = "" } 
                            else { chunk = substr(chunk, off - skipped + 1); skipped = off }
                        }
                        if (length(chunk) > 0) {
                            remain = max - vis
                            if (length(chunk) > remain) chunk = substr(chunk, 1, remain)
                            out = out chunk
                            vis += length(chunk)
                        }
                        if (vis >= max) break
                        s = substr(s, p)
                    }
                    if (substr(s, 2, 1) == "[" && match(s, /^\033\[[0-9;?]*[a-zA-Z]/)) {
                        out = out substr(s, 1, RLENGTH)
                        s = substr(s, RLENGTH + 1)
                    } else if (length(s) >= 2) { s = substr(s, 3) } else { break }
                }
                return out res
            }
            BEGIN { clear_spaces = sprintf("%*s", w, "") }
            {
                sliced = visible_slice($0, hoff, w)
                printf "\033[%d;%dH%s%s%s\033[%d;%dH%s", r + NR - 1, c, sty, clear_spaces, res, r + NR - 1, c, sliced
            }
            END {
                for (i = NR; i < h; i++) {
                    printf "\033[%d;%dH%s%s%s", r + i, c, sty, clear_spaces, res
                }
            }'
        )
    fi

    # 3. Draw Scrollbars — built with printf -v (a builtin) into the same
    # frame_buf instead of `frame_buf+=$(printf ...)`. Command substitution
    # forks a subshell per iteration; printf -v does not. Same rule the AWK
    # shader exists to satisfy for the text body above, just applied here
    # with a builtin instead of a compiled helper since each cell is a
    # handful of literal bytes, not a line of text to slice.
    local seg
    if [[ "$scroll" == "v" || "$scroll" == "both" ]] && (( total_lines > ct_h )); then
        local track_x=$(( pc + pw - 1 ))
        local thumb_h=$(( ct_h * ct_h / total_lines ))
        (( thumb_h < 1 )) && thumb_h=1
        local thumb_y=$(( ct_row + (v_off * (ct_h - thumb_h) / (total_lines - ct_h)) ))

        for (( i = 0; i < ct_h; i++ )); do
            if (( ct_row + i >= thumb_y && ct_row + i < thumb_y + thumb_h )); then
                printf -v seg '\033[%d;%dH\033[7m \033[0m' $(( ct_row + i )) "$track_x"
            else
                printf -v seg '\033[%d;%dH\033[2m│\033[0m' $(( ct_row + i )) "$track_x"
            fi
            frame_buf+="$seg"
        done
    fi

    if [[ "$scroll" == "h" || "$scroll" == "both" ]] && (( max_w > ct_w )); then
        local track_y=$(( pr + ph - 1 ))
        local thumb_w=$(( ct_w * ct_w / max_w ))
        (( thumb_w < 1 )) && thumb_w=1
        local thumb_x=$(( ct_col + (h_off * (ct_w - thumb_w) / (max_w - ct_w)) ))

        for (( i = 0; i < ct_w; i++ )); do
            if (( ct_col + i >= thumb_x && ct_col + i < thumb_x + thumb_w )); then
                printf -v seg '\033[%d;%dH\033[7m \033[0m' "$track_y" $(( ct_col + i ))
            else
                printf -v seg '\033[%d;%dH\033[2m─\033[0m' "$track_y" $(( ct_col + i ))
            fi
            frame_buf+="$seg"
        done
    fi

    _tui._flush "$frame_buf"
}

# ═══════════════════════════════════════════════════════════════════════
#  MAIN EVENT LOOP
# ═══════════════════════════════════════════════════════════════════════

declare -g _TUI_RESIZED=0

tui.on_resize() {
    tui.log.debug "tui.run detected terminal resize: setting _TUI_RESIZED=1"
    _TUI_RESIZED=1
}

tui.run() {
    tui.log.debug "tui.run() starting"
    _TUI_RUNNING=1
    _TUI_RESIZED=0

    trap '_master_cleanup; exit 1' INT TERM
    trap 'tui.on_resize' WINCH

    tui.render
    tui.log.debug "tui.run() rendered"

    while (( _TUI_RUNNING )); do

        if (( _TUI_RESIZED )); then
            tui.log.debug "Received resize event: recalculating layout and redrawing"
            _TUI_RESIZED=0
            term.size _TUI_ROWS _TUI_COLS
            _TUI_P_ROW[root]=1; _TUI_P_COL[root]=1
            _TUI_P_H[root]=$_TUI_ROWS; _TUI_P_W[root]=$_TUI_COLS
            _tui._layout "root"
            erase.all
            tui.render
        fi

        local char=""
        local got_char=0
        local poll_timeout="$TUI_INPUT_IDLE_TIMEOUT"
        [[ -n "${_TUI_TICK_FN:-}" ]] && poll_timeout="$TUI_INPUT_POLL_TIMEOUT"

        _tui._next_byte char "$poll_timeout" && got_char=1

        [[ -z "$char" && got_char -eq 1 ]] && char=$'\n'

        if [[ -n "$char" ]]; then
            if [[ -n "$_TUI_ON_INPUT_EVENT" && "$char" != $'\e' ]]; then
                _tui._notify_input "key $(printf '%q' "$char")"
            fi
            if [[ "$char" == $'\e' ]]; then
                _tui._read_escape_seq
                local seq="$_TUI_SEQ_BUF"
                if [[ -n "$_TUI_ON_INPUT_EVENT" && "$seq" != "[<"* ]]; then
                    _tui._notify_input "key esc:${seq:-<bare-esc>}"
                fi

                if [[ -z "$seq" ]]; then
                    if [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                        _tui._unfocus
                    fi
                elif [[ "$seq" == "[<"* ]]; then
                    if _tui._mouse_seq_is_motion "$seq"; then
                        _tui._coalesce_mouse_motion "$seq"
                        seq="$_TUI_SEQ_BUF"
                    fi
                    _tui._handle_mouse "$seq"
                elif [[ "$seq" == "[Z" ]]; then
                    _tui._focus_prev
                elif [[ "$seq" == "[A" || "$seq" == "[B" ]]; then
                    [[ "$seq" == "[A" ]] && _tui._focus_prev || _tui._focus_next
                
                # --- SHIFT ARROWS (Keyboard Scrolling) ---
                elif [[ "$seq" == "[1;2A" ]]; then _tui._scroll_kb "up"
                elif [[ "$seq" == "[1;2B" ]]; then _tui._scroll_kb "down"
                elif [[ "$seq" == "[1;2C" ]]; then _tui._scroll_kb "right"
                elif [[ "$seq" == "[1;2D" ]]; then _tui._scroll_kb "left"
                
                elif [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                    _tui._input_seq "$_TUI_FOCUS_ID" "$seq"
                fi
            elif [[ "$char" == $'\t' ]]; then
                _tui._focus_next
            elif [[ "$char" == $'\n' || "$char" == $'\r' ]]; then
                if [[ -n "$_TUI_FOCUS_ID" ]]; then
                    local ftype="${_TUI_W_TYPE[$_TUI_FOCUS_ID]}"
                    local faction="${_TUI_W_ACTION[$_TUI_FOCUS_ID]:-}"
                    if [[ "$ftype" == "button" ]]; then
                        [[ -n "$faction" ]] && "$faction" "$_TUI_FOCUS_ID"
                    elif [[ "$ftype" == "checkbox" ]]; then
                        tui.checkbox.toggle "$_TUI_FOCUS_ID"
                    elif [[ "$ftype" == "input" ]]; then
                        local submit_fn="${_TUI_W_SUBMIT[$_TUI_FOCUS_ID]:-}"
                        if [[ -n "$submit_fn" ]]; then
                            "$submit_fn" "$(tui.get "$_TUI_FOCUS_ID")"
                        elif [[ -n "$faction" ]]; then
                            "$faction" "$_TUI_FOCUS_ID"
                        fi
                        _tui._unfocus
                    fi
                fi
            
            # --- VIM KEYS (Gated by Input Focus) ---
            elif [[ "$char" == "k" || "$char" == "j" || "$char" == "h" || "$char" == "l" ]]; then
                if [[ -z "$_TUI_FOCUS_ID" || "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" != "input" ]]; then
                    case "$char" in
                        k) _tui._scroll_kb "up" ;;
                        j) _tui._scroll_kb "down" ;;
                        h) _tui._scroll_kb "left" ;;
                        l) _tui._scroll_kb "right" ;;
                    esac
                else
                    _tui._input_key "$_TUI_FOCUS_ID" "$char"
                fi
            
            # --- ALL OTHER TYPING ---
            elif [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                _tui._input_key "$_TUI_FOCUS_ID" "$char"
            fi
        fi

        # ── SCROLL BATCHING / DEBOUNCING ──
        # Pane content queued by _tui._queue_render (wheel spins, drag-jumps)
        # is flushed together, once, when the burst settles (timeout hits
        # zero) or the input stream goes idle (got_char==0). Hover/focus
        # redraws never enter this queue — they draw immediately where they
        # happen, so this block is scroll-only.
        if (( _TUI_RENDER_TIMEOUT > 0 )); then
            (( _TUI_RENDER_TIMEOUT-- ))
        fi

        if (( _TUI_RENDER_TIMEOUT == 0 )) || (( got_char == 0 )); then
            _tui._flush_pending_render
            _TUI_RENDER_TIMEOUT=-1
        fi

        [[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
    done

    _master_cleanup
}

tui.stop() { _TUI_RUNNING=0; }