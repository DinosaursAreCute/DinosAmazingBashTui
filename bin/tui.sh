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

declare -g _TUI_DRAG_LINES=0
declare -g _TUI_DRAG_MAX_W=0
declare -g _TUI_HOVERED_PANE=""
declare -gA _TUI_PENDING_RENDER=()
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

    mouse.button_on
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
    mouse.button_off
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
    printf "\e[0m\e[?25h\e[?1000l\e[?1002l\e[?1006l\e[?1049l\r\n"
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

_tui._pane_too_small() {
    local id="$1"
    local minw="${_TUI_P_MINW[$id]:-0}" minh="${_TUI_P_MINH[$id]:-0}"
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

    if _tui._pane_too_small "$id"; then
        _tui._draw_size_warning "$r" "$c" "$h" "$w" "${_TUI_P_MINW[$id]:-0}" "${_TUI_P_MINH[$id]:-0}"
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

_tui._draw_widget() {
    local id="$1"
    local type="${_TUI_W_TYPE[$id]:-}"
    [[ -z "$type" ]] && return
    local focused=0
    [[ "$_TUI_FOCUS_ID" == "$id" ]] && focused=1

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
    (( focused )) && style_key="${id}_focus"

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

tui.render() {
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
    mode.sync_start
    printf '%s' "$buf"
    mode.sync_end
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

_tui._pane_at() {
    local mx="$1" my="$2"
    for p in "${_TUI_P_ALL[@]}"; do
        [[ -z "${_TUI_P_CHILDREN[$p]:-}" ]] || continue
        if (( my >= _TUI_P_ROW[$p] && my < _TUI_P_ROW[$p] + _TUI_P_H[$p] &&
              mx >= _TUI_P_COL[$p] && mx < _TUI_P_COL[$p] + _TUI_P_W[$p] )); then
            printf '%s' "$p"
            return
        fi
    done
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

_tui._queue_render() {
    local p="$1"
    _TUI_PENDING_RENDER[$p]=1
    [[ $_TUI_RENDER_TIMEOUT -lt 0 ]] && _TUI_RENDER_TIMEOUT=3
}

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

    [[ -n "$old" && "$old" != "$id" ]] && _tui._draw_widget "$old"
    [[ -n "$id" ]] && _tui._draw_widget "$id"
}

_tui._unfocus() {
    local old="$_TUI_FOCUS_ID"
    _TUI_FOCUS_ID=""
    _TUI_FOCUS_IDX=-1
    [[ -n "$old" ]] && _tui._draw_widget "$old"
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

_tui._handle_mouse() {
    local seq="$1"
    seq="${seq#\[<}"
    local end="${seq: -1}"
    seq="${seq%[Mm]}"

    IFS=';' read -r btn mx my <<< "$seq"
    
    _TUI_HOVERED_PANE="$(_tui._pane_at "$mx" "$my")"

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

    local p="$_TUI_HOVERED_PANE"
    if [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != "none" ]]; then
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

    if _tui._hit_test "$mx" "$my"; then
        local wid="$_HIT"
        local wtype="${_TUI_W_TYPE[$wid]}"

        if [[ "$wtype" == "button" ]]; then
            tui.focus "$wid"
            local action="${_TUI_W_ACTION[$wid]:-}"
            [[ -n "$action" ]] && "$action" "$wid"

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

    tui.update "_xstat" "$icon"

    local short="$_EXEC_CMD"
    _tui._widget_pos "_xhdr"
    (( ${#short} > _WSW - 2 )) && short="${short:0:$((_WSW - 5))}..."
    tui.update "_xhdr" "$ ${short}"
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

    # 3. Draw Scrollbars
    if [[ "$scroll" == "v" || "$scroll" == "both" ]] && (( total_lines > ct_h )); then
        local track_x=$(( pc + pw - 1 ))
        local thumb_h=$(( ct_h * ct_h / total_lines ))
        (( thumb_h < 1 )) && thumb_h=1
        local thumb_y=$(( ct_row + (v_off * (ct_h - thumb_h) / (total_lines - ct_h)) ))

        for (( i = 0; i < ct_h; i++ )); do
            if (( ct_row + i >= thumb_y && ct_row + i < thumb_y + thumb_h )); then
                frame_buf+=$(printf "\033[%d;%dH\033[7m \033[0m" $((ct_row + i)) "$track_x")
            else
                frame_buf+=$(printf "\033[%d;%dH\033[2m│\033[0m" $((ct_row + i)) "$track_x")
            fi
        done
    fi

    if [[ "$scroll" == "h" || "$scroll" == "both" ]] && (( max_w > ct_w )); then
        local track_y=$(( pr + ph - 1 ))
        local thumb_w=$(( ct_w * ct_w / max_w ))
        (( thumb_w < 1 )) && thumb_w=1
        local thumb_x=$(( ct_col + (h_off * (ct_w - thumb_w) / (max_w - ct_w)) ))

        for (( i = 0; i < ct_w; i++ )); do
            if (( ct_col + i >= thumb_x && ct_col + i < thumb_x + thumb_w )); then
                frame_buf+=$(printf "\033[%d;%dH\033[7m \033[0m" "$track_y" $((ct_col + i)))
            else
                frame_buf+=$(printf "\033[%d;%dH\033[2m─\033[0m" "$track_y" $((ct_col + i)))
            fi
        done
    fi

    mode.sync_start
    printf '%s' "$frame_buf"
    mode.sync_end
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

        if [[ -n "${_TUI_TICK_FN:-}" ]]; then
            IFS= read -rsn1 -t 0.05 char && got_char=1
        else
            IFS= read -rsn1 -t 0.2 char && got_char=1
        fi

        [[ -z "$char" && got_char -eq 1 ]] && char=$'\n'

        if [[ -n "$char" ]]; then
            if [[ "$char" == $'\e' ]]; then
                local seq=""
                while IFS= read -rsn1 -t 0.01 c; do
                    seq+="$c"
                    [[ "$c" =~ [A-Za-z~Mm] ]] && break
                done

                if [[ -z "$seq" ]]; then
                    if [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                        _tui._unfocus
                    fi
                elif [[ "$seq" == "[<"* ]]; then
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
        if (( _TUI_RENDER_TIMEOUT > 0 )); then
            (( _TUI_RENDER_TIMEOUT-- ))
        fi

        if (( _TUI_RENDER_TIMEOUT == 0 )) || [[ $got_char -eq 0 && ${#_TUI_PENDING_RENDER[@]} -gt 0 ]]; then
            for p in "${!_TUI_PENDING_RENDER[@]}"; do
                _tui._render_output "$p"
            done
            _TUI_PENDING_RENDER=()
            _TUI_RENDER_TIMEOUT=-1
        fi

        [[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
    done

    _master_cleanup
}

tui.stop() { _TUI_RUNNING=0; }