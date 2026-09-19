#!/usr/bin/env bash
# tui_api.sh - public helper API for callback/app code (sourced by tui.sh
# after tui_style.sh). Wraps private internals so callbacks never touch
# _TUI_* / _tui.* directly.
#
# tui.ansi ID [STATE]        prints the ANSI prefix (fg+bg+mods) of a pane/widget id's style.
# tui.class.ansi CLASS [STATE]  same, straight from a theme.css class (no pane needed).
# tui.paint ID TEXT [STATE]  prints TEXT wrapped in ID's style + reset.
# tui.class.paint CLASS TEXT [STATE]
#
# STATE: normal (default) | focus | border | title | hover
# A non-normal STATE with no rules falls back to normal.
# Usage:
#   printf '%s%s%s\n' "$(tui.ansi mypane title)" "hi" "$(style.reset)"
#   tui.paint mypane "hi" title

# _tui_api._build FG BG MODS - emits ANSI prefix for resolved values.
_tui_api._build() {
    local fg="$1" bg="$2" mods="$3" m
    for m in $mods; do "style.$m" 2>/dev/null; done
    if [[ -n "$fg" ]]; then
        if [[ "$fg" == \#* ]]; then fg.hex "$fg"; else "fg.$fg" 2>/dev/null; fi
    fi
    if [[ -n "$bg" ]]; then
        if [[ "$bg" == \#* ]]; then bg.hex "$bg"; else "bg.$bg" 2>/dev/null; fi
    fi
}

tui.ansi() {
    local id="$1" state="${2:-normal}" key="${1}_${2:-normal}"
    if [[ -z "${_TUI_STYLE_FG[$key]:-}${_TUI_STYLE_BG[$key]:-}${_TUI_STYLE_MOD[$key]:-}" ]]; then
        key="${id}_normal"
    fi
    _tui_api._build "${_TUI_STYLE_FG[$key]:-}" "${_TUI_STYLE_BG[$key]:-}" "${_TUI_STYLE_MOD[$key]:-}"
}

tui.class.ansi() {
    local cls="$1" state="${2:-normal}" key="$1"
    [[ "$state" != "normal" ]] && key="${cls}_${state}"
    if [[ -z "${_TUI_CLASS_FG[$key]:-}${_TUI_CLASS_BG[$key]:-}${_TUI_CLASS_MOD[$key]:-}" ]]; then
        key="$cls"
    fi
    _tui_api._build "${_TUI_CLASS_FG[$key]:-}" "${_TUI_CLASS_BG[$key]:-}" "${_TUI_CLASS_MOD[$key]:-}"
}

tui.paint() {
    printf '%s%s\e[0m' "$(tui.ansi "$1" "${3:-normal}")" "$2"
}

tui.class.paint() {
    printf '%s%s\e[0m' "$(tui.class.ansi "$1" "${3:-normal}")" "$2"
}

# ═══════════════════════════════════════════════════════════════════════
#  LIVE UPDATES - timers, clocks, watchers, system monitor
# ═══════════════════════════════════════════════════════════════════════
#  Everything below rides ONE shared tick listener (tui.tick.add), so a
#  page never touches _TUI_TICK_FN and the loop only drops to its fast
#  poll rate while at least one job exists. Design rules:
#    - no subshell / fork per update: time from $EPOCHREALTIME and
#      printf %()T, /proc read via `read < file`, text into panes via
#      here-strings (see tui.set_text)
#    - output is change-detected: an unchanged frame is never redrawn
#    - slow external work runs in ONE background producer per watch,
#      streaming frames through a fifo that the tick drains with
#      non-blocking `read -t 0` - the UI never waits on a command
#    - jobs are cleared on page change (tui.reset_ui) and on exit
#
#  tui.set_text PANE TEXT             fork-free, change-detected tui.output
#  tui.every SEC FN [ID]              call FN ID every SEC (decimals ok, min ~0.05)
#  tui.after SEC FN [ID]              call FN ID once
#  tui.every.cancel ID | .pause ID | .resume ID | .clear | .list
#  tui.clock PANE [FMT] [FONT] [ID]   live clock; FMT = strftime (default %H:%M:%S),
#                                     FONT = any banner font (box3, seg3, block5…) or empty
#  tui.watch PANE CMD [SEC] [ID]      run shell CMD every SEC (default 2) off-thread,
#                                     show its stdout in PANE (like `watch`)
#  tui.watch.stop ID | tui.watch.now ID
#  tui.sys.cpu|mem|load|uptime        fork-free samplers → TUI_SYS_* vars
#  tui.monitor PANE [SEC] [ID]        ready-made CPU/MEM/SWAP/load dashboard
#  tui.hist.push NAME VAL [MAX] / tui.hist.get NAME   rolling sample series

_TUI_API_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -gA _TA_LAST=()                  # pane -> last text set
declare -gA _TA_FN=() _TA_INT=() _TA_NEXT=() _TA_ONCE=() _TA_ALIGN=() _TA_PAUSED=() _TA_ARGS=()
declare -ga _TA_IDS=()
declare -gi _TA_NOW=0                    # ms, refreshed once per tick
declare -gA _TA_HIST=()

_tui_api._now() { local t=${EPOCHREALTIME//[.,]/}; _TA_NOW=$(( t / 1000 )); }

# _tui_api._ms SEC → _TA_MS (accepts 2, 0.5, .25)
_tui_api._ms() {
    local s="${1:-1}" i f
    i="${s%%[.,]*}"; f=""
    [[ "$s" == *[.,]* ]] && f="${s#*[.,]}"
    f="${f}000"; f="${f:0:3}"
    _TA_MS=$(( 10#${i:-0} * 1000 + 10#$f ))
    (( _TA_MS < 50 )) && _TA_MS=50
}

tui.set_text() {
    local pane="$1" text="$2"
    [[ "${_TA_LAST[$pane]-}" == "$text" && -n "${_TUI_PANE_CONTENT[$pane]:-}" ]] && return 0
    _TA_LAST[$pane]="$text"
    _TUI_PANE_CONTENT[$pane]=1
    declare -g -a "_TUI_PANE_CONTENT_${pane}"
    local -n _ta_arr="_TUI_PANE_CONTENT_${pane}"
    _ta_arr=()
    [[ -n "$text" ]] && mapfile -t _ta_arr <<< "${text%$'\n'}"
    _tui._calc_bounds "$pane"
    (( _TUI_RUNNING )) && _tui._queue_render "$pane"
    return 0
}

# ── scheduler ────────────────────────────────────────────────────────────

_tui_api._job_add() {   # ID FN SEC ONCE [ALIGN]
    local id="$1"
    _tui_api._ms "$3"
    if [[ -z "${_TA_FN[$id]:-}" ]]; then _TA_IDS+=("$id"); fi
    _TA_FN[$id]="$2"; _TA_INT[$id]=$_TA_MS; _TA_ONCE[$id]="$4"; _TA_ALIGN[$id]="${5:-}"
    _TA_NEXT[$id]=0; unset '_TA_PAUSED[$id]'
    tui.tick.add "_tui_api._tick"
}

_tui_api._job_del() {
    local id="$1" x; local -a keep=()
    for x in "${_TA_IDS[@]}"; do [[ "$x" == "$id" ]] || keep+=("$x"); done
    _TA_IDS=("${keep[@]}")
    unset '_TA_FN[$id]' '_TA_INT[$id]' '_TA_NEXT[$id]' '_TA_ONCE[$id]' '_TA_ALIGN[$id]' '_TA_PAUSED[$id]' '_TA_ARGS[$id]'
    _tui_api._maybe_idle
}

# Drop the tick listener when nothing needs it, so the main loop goes back
# to its slow idle poll.
_tui_api._maybe_idle() {
    (( ${#_TA_IDS[@]} == 0 && ${#_TA_WIDS[@]} == 0 )) && tui.tick.remove "_tui_api._tick"
    return 0
}

_tui_api._tick() {
    _tui_api._now
    local id
    if (( ${#_TA_IDS[@]} > 0 )); then
        for id in "${_TA_IDS[@]}"; do
            [[ -z "${_TA_FN[$id]:-}" ]] && continue
            [[ -n "${_TA_PAUSED[$id]:-}" ]] && continue
            (( _TA_NOW < ${_TA_NEXT[$id]:-0} )) && continue
            if [[ -n "${_TA_ALIGN[$id]:-}" ]]; then
                _TA_NEXT[$id]=$(( _TA_NOW - _TA_NOW % _TA_INT[$id] + _TA_INT[$id] ))
            else
                _TA_NEXT[$id]=$(( _TA_NOW + _TA_INT[$id] ))
            fi
            if [[ -n "${_TA_ONCE[$id]:-}" ]]; then
                local fn="${_TA_FN[$id]}"
                _tui_api._job_del "$id"
                "$fn" "$id"
            else
                "${_TA_FN[$id]}" "$id"
            fi
        done
    fi
    (( ${#_TA_WIDS[@]} > 0 )) && _tui_api._watch_drain
    return 0
}

tui.every()         { _tui_api._job_add "${3:-$2}" "$2" "$1" ""; }
tui.after()         { _tui_api._job_add "${3:-$2}" "$2" "$1" 1; }
tui.every.cancel()  { _tui_api._job_del "$1"; }
tui.every.pause()   { _TA_PAUSED[$1]=1; }
tui.every.resume()  { unset '_TA_PAUSED[$1]'; _TA_NEXT[$1]=0; }
tui.every.clear()   { local id; for id in "${_TA_IDS[@]}"; do _tui_api._job_del "$id"; done; }
tui.every.list()    { local id; for id in "${_TA_IDS[@]}"; do printf '%s\t%sms\t%s\n' "$id" "${_TA_INT[$id]}" "${_TA_FN[$id]}"; done; }

# ── clock ────────────────────────────────────────────────────────────────

tui.clock() {
    local pane="$1" fmt="${2:-%H:%M:%S}" font="${3:-}" id="${4:-clock_$1}"
    if [[ -n "$font" ]] && ! declare -F _banner_build >/dev/null; then
        source "${_TUI_API_DIR}/terminal_renderer.sh"
    fi
    _TA_ARGS[$id]="${pane}"$'\x1f'"${fmt}"$'\x1f'"${font}"
    _tui_api._job_add "$id" "_tui_api._clock_run" 1 "" 1     # aligned to whole seconds
}

_tui_api._clock_run() {
    local id="$1" pane fmt font t
    IFS=$'\x1f' read -r pane fmt font <<< "${_TA_ARGS[$id]}"
    [[ -z "${_TUI_P_ROW[$pane]:-}" ]] && { _tui_api._job_del "$id"; return; }
    printf -v t "%(${fmt})T" -1
    if [[ -n "$font" ]]; then
        tui.style.sgr "$pane"; local ansi="$TUI_SGR"          # fork-free (tui.ansi was a subshell per tick)
        _banner_build "$t" "$font"
        local out="" l
        for l in "${TR_RESULT[@]}"; do
            printf -v l '%b' "$l"
            out+="${ansi}${l}"$'\e[0m\n'
        done
        t="${out%$'\n'}"
    fi
    tui.set_text "$pane" "$t"
}

# ── watch: background producer → fifo → non-blocking drain ───────────────

declare -ga _TA_WIDS=()
declare -gA _TA_WPANE=() _TA_WFD=() _TA_WPID=() _TA_WBUF=() _TA_WCMD=() _TA_WSEC=()
declare -g  _TA_TMP="" _TA_SLEEP_FD=""

_tui_api._tmp_init() {
    [[ -n "$_TA_TMP" && -d "$_TA_TMP" ]] && return
    _TA_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tui_api.XXXXXX")"
    mkfifo "$_TA_TMP/sleep"
}

tui.watch() {
    local pane="$1" cmd="$2" sec="${3:-2}" id="${4:-watch_$1}"
    [[ -z "$pane" || -z "$cmd" ]] && { echo "tui.watch: need PANE and CMD" >&2; return 1; }
    tui.watch.stop "$id"
    _tui_api._tmp_init
    _tui_api._ms "$sec"
    local fifo="$_TA_TMP/$id" fd
    mkfifo "$fifo"
    exec {fd}<>"$fifo"                        # r/w open: never blocks, never EOFs
    local s; printf -v s "%d.%03d" $(( _TA_MS / 1000 )) $(( _TA_MS % 1000 ))
    (
        exec {out}>"$fifo" {sl}<>"$_TA_TMP/sleep"
        while :; do
            { eval "$cmd"; printf '\x1e'; } >&$out 2>/dev/null
            read -rt "$s" -u $sl              # fork-free sleep
        done
    ) &
    _TA_WPID[$id]=$!; _TA_WFD[$id]=$fd; _TA_WPANE[$id]="$pane"; _TA_WBUF[$id]=""
    _TA_WCMD[$id]="$cmd"; _TA_WSEC[$id]="$sec"
    _TA_WIDS+=("$id")
    tui.tick.add "_tui_api._tick"
}

tui.watch.stop() {
    local id="$1" x; local -a keep=()
    [[ -z "${_TA_WFD[$id]:-}" ]] && return 0
    kill "${_TA_WPID[$id]}" 2>/dev/null; wait "${_TA_WPID[$id]}" 2>/dev/null
    local cfd=${_TA_WFD[$id]}; exec {cfd}<&-
    rm -f "$_TA_TMP/$id"
    for x in "${_TA_WIDS[@]}"; do [[ "$x" == "$id" ]] || keep+=("$x"); done
    _TA_WIDS=("${keep[@]}")
    unset '_TA_WFD[$id]' '_TA_WPID[$id]' '_TA_WPANE[$id]' '_TA_WBUF[$id]' '_TA_WCMD[$id]' '_TA_WSEC[$id]'
    _tui_api._maybe_idle
}

# Restart the producer so the next frame arrives immediately.
tui.watch.now() {
    local id="$1"
    [[ -z "${_TA_WFD[$id]:-}" ]] && return 1
    tui.watch "${_TA_WPANE[$id]}" "${_TA_WCMD[$id]}" "${_TA_WSEC[$id]}" "$id"
}

_tui_api._watch_drain() {
    local id fd frame f got
    for id in "${_TA_WIDS[@]}"; do
        fd="${_TA_WFD[$id]}"; got=0
        while read -t 0 -u "$fd"; do
            if IFS= read -r -d $'\x1e' -t 0.02 -u "$fd" f; then
                frame="${_TA_WBUF[$id]}$f"; _TA_WBUF[$id]=""; got=1   # keep newest complete frame only
            else
                _TA_WBUF[$id]+="$f"; break                             # partial: finish next tick
            fi
        done
        (( got )) || continue
        if [[ -z "${_TUI_P_ROW[${_TA_WPANE[$id]}]:-}" ]]; then tui.watch.stop "$id"; continue; fi
        tui.set_text "${_TA_WPANE[$id]}" "$frame"
    done
}

_tui_api.shutdown() {
    local id
    for id in "${_TA_WIDS[@]}"; do tui.watch.stop "$id"; done
    tui.every.clear
    [[ -n "$_TA_TMP" ]] && rm -rf "$_TA_TMP"; _TA_TMP=""
    _TA_LAST=()
}

# ── system samplers (no forks; read /proc directly) ──────────────────────

declare -gi TUI_SYS_CPU=0 TUI_SYS_MEM_PCT=0 TUI_SYS_MEM_USED_MB=0 TUI_SYS_MEM_TOTAL_MB=0 TUI_SYS_SWAP_PCT=0 TUI_SYS_UPTIME=0
declare -g  TUI_SYS_LOAD1=0 TUI_SYS_LOAD5=0 TUI_SYS_LOAD15=0 TUI_SYS_UPTIME_STR=""
declare -gi _TA_CPU_T=0 _TA_CPU_I=0

tui.sys.cpu() {
    local _ u n s i io irq sirq st
    read -r _ u n s i io irq sirq st _ < /proc/stat || return 1
    local t=$(( u + n + s + i + io + irq + sirq + st )) idle=$(( i + io ))
    local dt=$(( t - _TA_CPU_T )) di=$(( idle - _TA_CPU_I ))
    (( dt > 0 )) && TUI_SYS_CPU=$(( 100 * (dt - di) / dt ))
    _TA_CPU_T=$t; _TA_CPU_I=$idle
}

tui.sys.mem() {
    local k v _ total=0 avail=0 stot=0 sfree=0
    while read -r k v _; do
        case "$k" in
            MemTotal:) total=$v ;; MemAvailable:) avail=$v ;;
            SwapTotal:) stot=$v ;; SwapFree:) sfree=$v; break ;;
        esac
    done < /proc/meminfo
    (( total > 0 )) && TUI_SYS_MEM_PCT=$(( 100 * (total - avail) / total ))
    TUI_SYS_MEM_USED_MB=$(( (total - avail) / 1024 )); TUI_SYS_MEM_TOTAL_MB=$(( total / 1024 ))
    (( stot > 0 )) && TUI_SYS_SWAP_PCT=$(( 100 * (stot - sfree) / stot )) || TUI_SYS_SWAP_PCT=0
}

tui.sys.load() { read -r TUI_SYS_LOAD1 TUI_SYS_LOAD5 TUI_SYS_LOAD15 _ < /proc/loadavg; }

tui.sys.uptime() {
    local up _
    read -r up _ < /proc/uptime
    TUI_SYS_UPTIME=${up%%.*}
    local d=$(( TUI_SYS_UPTIME / 86400 )) h=$(( TUI_SYS_UPTIME % 86400 / 3600 )) m=$(( TUI_SYS_UPTIME % 3600 / 60 ))
    printf -v TUI_SYS_UPTIME_STR '%dd %02dh %02dm' "$d" "$h" "$m"
}

# ── rolling history ──────────────────────────────────────────────────────

tui.hist.push() {
    local name="$1" val="$2" max="${3:-60}"
    local -a a; read -ra a <<< "${_TA_HIST[$name]:-}"
    a+=("$val")
    (( ${#a[@]} > max )) && a=("${a[@]: -max}")
    _TA_HIST[$name]="${a[*]}"
}
tui.hist.get() { printf '%s' "${_TA_HIST[$1]:-}"; }

# ── ready-made monitor ───────────────────────────────────────────────────

tui.monitor() {
    local pane="$1" sec="${2:-1}" id="${3:-monitor_$1}"
    declare -F _gauge_build >/dev/null || source "${_TUI_API_DIR}/terminal_renderer.sh"
    _TA_ARGS[$id]="$pane"
    tui.sys.cpu
    _tui_api._job_add "$id" "_tui_api._monitor_run" "$sec" ""
}

_tui_api._monitor_run() {
    local id="$1" pane="${_TA_ARGS[$1]}"
    [[ -z "${_TUI_P_ROW[$pane]:-}" ]] && { _tui_api._job_del "$id"; return; }
    _tui._content_rect "$pane"
    local gw=$(( _CR_W - 12 )); (( gw < 8 )) && gw=8
    tui.sys.cpu; tui.sys.mem; tui.sys.load; tui.sys.uptime
    tui.hist.push "${id}_cpu" "$TUI_SYS_CPU" "$gw"

    local out="" line
    _gauge_build -w "$gw" -lw 5 -l "CPU"  "$TUI_SYS_CPU";      printf -v line '%b' "${TR_RESULT[0]}"; out+="$line"$'\n'
    _gauge_build -w "$gw" -lw 5 -l "MEM"  "$TUI_SYS_MEM_PCT";  printf -v line '%b' "${TR_RESULT[0]}"; out+="$line"$'\n'
    _gauge_build -w "$gw" -lw 5 -l "SWAP" "$TUI_SYS_SWAP_PCT"; printf -v line '%b' "${TR_RESULT[0]}"; out+="$line"$'\n\n'
    if _sparkline_build -w "$gw" -n 0 -m 100 -c CYAN "${_TA_HIST[${id}_cpu]}"; then
        printf -v line '%b' "${TR_RESULT[0]}"; out+="CPU   $line"$'\n\n'
    fi
    out+="Mem    ${TUI_SYS_MEM_USED_MB} / ${TUI_SYS_MEM_TOTAL_MB} MB"$'\n'
    out+="Load   ${TUI_SYS_LOAD1} ${TUI_SYS_LOAD5} ${TUI_SYS_LOAD15}"$'\n'
    out+="Uptime ${TUI_SYS_UPTIME_STR}"
    tui.set_text "$pane" "$out"
}

# ═══════════════════════════════════════════════════════════════════════
#  GETTERS - read-only introspection (print to stdout; unknown id → rc 1)
# ═══════════════════════════════════════════════════════════════════════
#  tui.get.dimensions [-r|--rows | -c|--columns] [--content] [PANE]
#        no flag: "ROWS COLS". No PANE: the terminal. --content: usable
#        area inside border+padding (what tui.output can fill).
#  tui.get.position PANE            "ROW COL" (1-based, top-left)
#  tui.get.rect PANE                "ROW COL ROWS COLS"
#  tui.get.content_area PANE        "ROW COL ROWS COLS" of the usable area
#  tui.get.border PANE              effective border: single|double|heavy|none
#  tui.get.title PANE
#  tui.get.pad PANE                 "HPAD VPAD"
#  tui.get.split PANE               h | v | (empty for leaf)
#  tui.get.children PANE            child pane ids
#  tui.get.parent PANE
#  tui.get.panes [leaves]           all pane ids (or leaves only)
#  tui.get.scroll PANE              "MODE V_OFF H_OFF TOTAL_LINES MAX_WIDTH"
#  tui.get.lines PANE               number of output lines held
#  tui.get.style ID FIELD [STATE]   FIELD = fg|bg|mods, STATE = normal|focus|border|title|hover
#  tui.get.widgets [PANE]           widget ids (all, or those in PANE)
#  tui.get.type ID                  label|button|input|checkbox
#  tui.get.pane ID                  pane a widget lives in
#  tui.get.action ID                callback fn bound to a widget
#  tui.get.checked ID               rc 0 if checked checkbox
#  tui.get.focused                  focused widget id
#  tui.get.hovered [pane|widget]    hovered id (default widget)
#  tui.get.terminal                 "ROWS COLS"
#  tui.get.page                     current markup file

tui.get.dimensions() {
    local mode="" content=0 pane=""
    while (( $# )); do
        case "$1" in
            -r|--rows)    mode=r ;;
            -c|--columns) mode=c ;;
            --content)    content=1 ;;
            *)            pane="$1" ;;
        esac
        shift
    done
    local r c
    if [[ -z "$pane" ]]; then
        r=$_TUI_ROWS; c=$_TUI_COLS
    else
        [[ -z "${_TUI_P_H[$pane]:-}" ]] && return 1
        if (( content )); then _tui._content_rect "$pane"; r=$_CR_H; c=$_CR_W
        else r=${_TUI_P_H[$pane]}; c=${_TUI_P_W[$pane]}; fi
    fi
    case "$mode" in r) printf '%s\n' "$r" ;; c) printf '%s\n' "$c" ;; *) printf '%s %s\n' "$r" "$c" ;; esac
}

_tui_api._need_pane() { [[ -n "${_TUI_P_H[$1]:-}" ]]; }

tui.get.position()     { _tui_api._need_pane "$1" || return 1; printf '%s %s\n' "${_TUI_P_ROW[$1]}" "${_TUI_P_COL[$1]}"; }
tui.get.rect()         { _tui_api._need_pane "$1" || return 1; printf '%s %s %s %s\n' "${_TUI_P_ROW[$1]}" "${_TUI_P_COL[$1]}" "${_TUI_P_H[$1]}" "${_TUI_P_W[$1]}"; }
tui.get.content_area() { _tui_api._need_pane "$1" || return 1; tui.content_area "$1"; }
tui.get.border()       { _tui_api._need_pane "$1" || return 1; _tui._eff_border "$1"; printf '%s\n' "$_TB"; }
tui.get.title()        { _tui_api._need_pane "$1" || return 1; printf '%s\n' "${_TUI_P_TITLE[$1]:-}"; }
tui.get.pad()          { _tui_api._need_pane "$1" || return 1; printf '%s %s\n' "${_TUI_P_HPAD[$1]:-0}" "${_TUI_P_VPAD[$1]:-0}"; }
tui.get.split()        { _tui_api._need_pane "$1" || return 1; printf '%s\n' "${_TUI_P_DIR[$1]:-}"; }
tui.get.children()     { _tui_api._need_pane "$1" || return 1; printf '%s\n' "${_TUI_P_CHILDREN[$1]:-}"; }
tui.get.lines()        { printf '%s\n' "${_TUI_P_LINES[$1]:-0}"; }

tui.get.parent() {
    local p
    for p in "${!_TUI_P_CHILDREN[@]}"; do
        [[ " ${_TUI_P_CHILDREN[$p]} " == *" $1 "* ]] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

tui.get.panes() {
    if [[ "${1:-}" == leaves ]]; then printf '%s\n' "${_TUI_P_LEAVES[@]}"
    else printf '%s\n' "${_TUI_P_ALL[@]}"; fi
}

tui.get.scroll() {
    _tui_api._need_pane "$1" || return 1
    printf '%s %s %s %s %s\n' "${_TUI_P_SCROLL[$1]:-none}" "${_TUI_P_SOFF_V[$1]:-0}" "${_TUI_P_SOFF_H[$1]:-0}" \
        "${_TUI_P_LINES[$1]:-0}" "${_TUI_P_MAX_W[$1]:-0}"
}

tui.get.style() {
    local id="$1" field="${2:-}" state="${3:-normal}" key
    key="${id}_${state}"
    if [[ -z "${_TUI_STYLE_FG[$key]:-}${_TUI_STYLE_BG[$key]:-}${_TUI_STYLE_MOD[$key]:-}" ]]; then key="${id}_normal"; fi
    case "$field" in
        fg)   printf '%s\n' "${_TUI_STYLE_FG[$key]:-}" ;;
        bg)   printf '%s\n' "${_TUI_STYLE_BG[$key]:-}" ;;
        mods) printf '%s\n' "${_TUI_STYLE_MOD[$key]:-}" ;;
        *)    echo "tui.get.style: FIELD must be fg|bg|mods" >&2; return 2 ;;
    esac
}

tui.get.widgets() {
    local w
    for w in "${_TUI_W_ORDER[@]}"; do
        [[ -z "${1:-}" || "${_TUI_W_PANE[$w]:-}" == "$1" ]] && printf '%s\n' "$w"
    done
}
tui.get.type()    { [[ -n "${_TUI_W_TYPE[$1]:-}" ]] || return 1; printf '%s\n' "${_TUI_W_TYPE[$1]}"; }
tui.get.pane()    { [[ -n "${_TUI_W_PANE[$1]:-}" ]] || return 1; printf '%s\n' "${_TUI_W_PANE[$1]}"; }
tui.get.action()  { printf '%s\n' "${_TUI_W_ACTION[$1]:-}"; }
tui.get.checked() { [[ "${_TUI_W_TYPE[$1]:-}" == checkbox && "${_TUI_W_VALUE[$1]:-}" == 1 ]]; }
tui.get.focused() { printf '%s\n' "${_TUI_FOCUS_ID:-}"; }
tui.get.hovered() {
    if [[ "${1:-widget}" == pane ]]; then printf '%s\n' "${_TUI_HOVERED_PANE:-}"
    else printf '%s\n' "${_TUI_HOVERED_WIDGET:-}"; fi
}
tui.get.terminal() { printf '%s %s\n' "$_TUI_ROWS" "$_TUI_COLS"; }
tui.get.page()     { printf '%s\n' "${_TUI_MARKUP_FILE:-}"; }

#  tui.get.classes                  every key the loaded theme defines (pseudo-states appear as CLASS_focus, CLASS_hover, ...)
#  tui.get.class.style CLASS FIELD [STATE]   fg|bg|mods of a theme class (no pane needed)
tui.get.classes() {
    local k; local -A seen=()
    for k in "${!_TUI_CLASS_FG[@]}" "${!_TUI_CLASS_BG[@]}" "${!_TUI_CLASS_MOD[@]}"; do
        [[ -z "${seen[$k]:-}" ]] && { seen[$k]=1; printf '%s\n' "$k"; }
    done | sort
}
tui.get.class.style() {
    local cls="$1" field="${2:-}" state="${3:-normal}" key="$1"
    [[ "$state" != normal ]] && key="${cls}_${state}"
    if [[ -z "${_TUI_CLASS_FG[$key]:-}${_TUI_CLASS_BG[$key]:-}${_TUI_CLASS_MOD[$key]:-}" ]]; then key="$cls"; fi
    case "$field" in
        fg)   printf '%s\n' "${_TUI_CLASS_FG[$key]:-}" ;;
        bg)   printf '%s\n' "${_TUI_CLASS_BG[$key]:-}" ;;
        mods) printf '%s\n' "${_TUI_CLASS_MOD[$key]:-}" ;;
        *)    echo "tui.get.class.style: FIELD must be fg|bg|mods" >&2; return 2 ;;
    esac
}

# tui.pane_size PANE — fork-free: sets TUI_PANE_ROWS / TUI_PANE_COLS to the
# pane's usable content area (inside border + padding).
declare -gi TUI_PANE_ROWS=0 TUI_PANE_COLS=0
tui.pane_size() {
    _tui_api._need_pane "$1" || return 1
    _tui._content_rect "$1"
    TUI_PANE_ROWS=$_CR_H; TUI_PANE_COLS=$_CR_W
}

# ═══════════════════════════════════════════════════════════════════════
#  APP-WIDE THEME OVERLAY
# ═══════════════════════════════════════════════════════════════════════
#  tui.theme.set FILE    layer FILE over every page's own stylesheet (persists across
#                        tui.goto) and reload the current page so it takes effect
#  tui.theme.clear       drop the overlay and reload
#  tui.theme.current     print the overlay path (empty = page defaults)
tui.theme.set()     { _TUI_THEME_OVERLAY="$1"; tui.theme.reload; }
tui.theme.clear()   { _TUI_THEME_OVERLAY=""; tui.theme.reload; }
tui.theme.current() { printf '%s\n' "${_TUI_THEME_OVERLAY:-}"; }
tui.theme.reload()  { [[ -n "${_TUI_MARKUP_FILE:-}" ]] && tui.goto "$_TUI_MARKUP_FILE"; }

# tui.relayout [PANE] - repaint after tui.pane_border / tui.pane_pad / split changes.
#   PANE (a leaf): only that pane is cleared and redrawn - no full-screen clear,
#   nothing else flickers. No PANE (or a parent): recompute geometry and redraw
#   everything. Either way it is one synchronized-output frame (mode.sync_*), so
#   the terminal never shows the intermediate blank screen.
tui.relayout() {
    local pane="${1:-}"
    (( _TUI_RUNNING )) || { _tui._layout root; return 0; }
    mode.sync_start
    if [[ -n "$pane" && -n "${_TUI_P_H[$pane]:-}" && -z "${_TUI_P_CHILDREN[$pane]:-}" ]]; then
        _tui_api._repaint_pane "$pane"
    else
        _tui._layout root
        erase.all
        tui.render
    fi
    mode.sync_end
    return 0
}

_tui_api._repaint_pane() {
    local id="$1" row blank
    (( ${_TUI_P_H[$1]:-0} < 1 || ${_TUI_P_W[$1]:-0} < 1 )) && return
    local r=${_TUI_P_ROW[$id]} c=${_TUI_P_COL[$id]} h=${_TUI_P_H[$id]} w=${_TUI_P_W[$id]}
    printf -v blank '%*s' "$w" ""
    _tui._apply_style "${id}_normal"
    for (( row = 0; row < h; row++ )); do cur.goto $(( r + row )) "$c"; printf '%s' "$blank"; done
    style.reset
    _tui._draw_pane "$id"
    local wid
    for wid in "${_TUI_W_ORDER[@]}"; do
        [[ "${_TUI_W_PANE[$wid]:-}" == "$id" ]] && _tui._draw_widget "$wid"
    done
    [[ -n "${_TUI_PANE_CONTENT[$id]:-}" ]] && _tui._render_output "$id"
}

# tui.set_label ID TEXT — change a button/checkbox caption (tui.update only
# changes a widget's value, which buttons don't display) and redraw it.
tui.set_label() {
    [[ -n "${_TUI_W_TYPE[$1]:-}" ]] || return 1
    _TUI_W_LABEL[$1]="$2"
    [[ "${_TUI_W_TYPE[$1]}" == label ]] && _TUI_W_VALUE[$1]="$2"
    (( _TUI_RUNNING )) && _tui._draw_widget "$1"
    return 0
}

#  tui.get.label ID                 caption of a widget (button text, checkbox label, label text)
tui.get.label() { printf '%s\n' "${_TUI_W_LABEL[$1]:-}"; }

# Called by the resize handler after re-layout: run every timer job on the next
# tick so size-dependent output (monitor gauges, charts, clocks) re-fits now
# instead of waiting for its next interval.
_tui_api.on_resize() {
    local id
    for id in "${_TA_IDS[@]}"; do _TA_NEXT[$id]=0; done
    return 0
}

# tui.require terminal_renderer | terminal_controls - source a bundled library ONCE per process. Page callback
# files are re-sourced on every visit (see tui_cache.sh); sourcing the 2000-line renderer each time was a cost
# on every page switch for nothing.
declare -gA _TUI_REQUIRED=()
tui.require() {
    [[ -n "${_TUI_REQUIRED[$1]:-}" ]] && return 0
    case "$1" in
        terminal_renderer|terminal_controls) source "${SCRIPT_DIR}/$1.sh" ;;
        *) echo "tui.require: unknown library '$1'" >&2; return 1 ;;
    esac
    _TUI_REQUIRED[$1]=1
}

# ── fork-free style getters (set variables instead of printing: no $(...) needed) ──
#   tui.class.style CLASS [STATE]   -> TUI_FG TUI_BG TUI_MODS   (STATE falls back to the class itself)
#   tui.class.sgr   CLASS [STATE]   -> TUI_SGR                  (the ANSI prefix; wrap text: "$TUI_SGR text $TUI_RESET")
declare -g TUI_FG="" TUI_BG="" TUI_MODS="" TUI_SGR="" TUI_RESET=$'\e[0m'
tui.class.style() {
    local cls="$1" state="${2:-normal}" key="$1"
    [[ "$state" != normal ]] && key="${cls}_${state}"
    if [[ -z "${_TUI_CLASS_FG[$key]:-}${_TUI_CLASS_BG[$key]:-}${_TUI_CLASS_MOD[$key]:-}" ]]; then key="$cls"; fi
    TUI_FG="${_TUI_CLASS_FG[$key]:-}"; TUI_BG="${_TUI_CLASS_BG[$key]:-}"; TUI_MODS="${_TUI_CLASS_MOD[$key]:-}"
}
tui.class.sgr() {
    tui.class.style "$@"
    _tui._sgr_from "$TUI_FG" "$TUI_BG" "$TUI_MODS" && TUI_SGR="$_SGR" || TUI_SGR="$(tui.class.ansi "$@")"
}

#   tui.class.names                 -> TUI_CLASSES (array, sorted): every class/pseudo-state key in the loaded theme
#   tui.style.sgr ID [STATE]        -> TUI_SGR TUI_FG TUI_BG: the resolved style of a pane/widget (STATE: normal|focus|border|title|hover)
tui.class.names() {
    local -A seen=(); local k
    for k in "${!_TUI_CLASS_FG[@]}" "${!_TUI_CLASS_BG[@]}" "${!_TUI_CLASS_MOD[@]}"; do seen[$k]=1; done
    _tui_input.sorted_ids seen
    TUI_CLASSES=("${_SIDS[@]}")
}
declare -ga TUI_CLASSES=()
tui.style.sgr() {
    local id="$1" state="${2:-normal}" key
    key="${id}_${state}"
    [[ -z "${_TUI_STYLE_FG[$key]:-}${_TUI_STYLE_BG[$key]:-}${_TUI_STYLE_MOD[$key]:-}" ]] && key="${id}_normal"
    TUI_FG="${_TUI_STYLE_FG[$key]:-}"; TUI_BG="${_TUI_STYLE_BG[$key]:-}"
    _tui._style_v "$key"; TUI_SGR="$_SGR"
}
