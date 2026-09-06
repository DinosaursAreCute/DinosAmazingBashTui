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
declare -ga _TUI_P_LEAVES=()

declare -gA _TUI_W_TYPE=()     
declare -gA _TUI_W_PANE=()     
declare -gA _TUI_W_ROW=()      
declare -gA _TUI_W_LABEL=()    
declare -gA _TUI_W_VALUE=()    
declare -gA _TUI_W_ACTION=()   
declare -gA _TUI_W_PH=()       
declare -ga _TUI_W_ORDER=()    
declare -ga _TUI_FOCUSABLE=()  

declare -g  _TUI_FOCUS_ID=""
declare -g  _TUI_FOCUS_IDX=-1
declare -g  _TUI_CURSOR=0      
declare -g  _TUI_RUNNING=0
declare -g  _TUI_OLD_STTY=""
declare -g  _TUI_ROWS=0
declare -g  _TUI_COLS=0
declare -g  _WSR=0 _WSC=0 _WSW=0
declare -g  _HIT=""

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
    echo "[$(date +%H:%M:%S)] [$level] $msg" >> ".tui_exec.log"
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
    _tui._collect_leaves "root"
}

_tui._collect_leaves() {
    local id="$1"
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

    local offset=0 last=$(( ${#ch[@]} - 1 ))

    for (( i = 0; i <= last; i++ )); do
        local name="${ch[$i]}" w="${wt[$i]}"

        if [[ "$dir" == "h" ]]; then
            local cw=$(( pw * w / total ))
            (( i == last )) && cw=$(( pw - offset ))
            _TUI_P_ROW[$name]=$pr
            _TUI_P_COL[$name]=$(( pc + offset ))
            _TUI_P_H[$name]=$ph
            _TUI_P_W[$name]=$cw
            (( offset += cw ))
        else
            local ch_h=$(( ph * w / total ))
            (( i == last )) && ch_h=$(( ph - offset ))
            _TUI_P_ROW[$name]=$(( pr + offset ))
            _TUI_P_COL[$name]=$pc
            _TUI_P_H[$name]=$ch_h
            _TUI_P_W[$name]=$pw
            (( offset += ch_h ))
        fi

        [[ -n "${_TUI_P_CHILDREN[$name]:-}" ]] && _tui._layout "$name"
    done
}

tui.pane_title()  { _TUI_P_TITLE[$1]="$2"; }
tui.pane_border() { _TUI_P_BORDER[$1]="$2"; }

# ═══════════════════════════════════════════════════════════════════════
#  WIDGETS
# ═══════════════════════════════════════════════════════════════════════

tui.label() {
    local id="$1"
    _TUI_W_TYPE[$id]="label"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_LABEL[$id]="$4"
    _TUI_W_VALUE[$id]="$4"
    _TUI_W_ORDER+=("$id")
}

tui.button() {
    local id="$1"
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
    _TUI_W_TYPE[$id]="input"
    _TUI_W_PANE[$id]="$2"
    _TUI_W_ROW[$id]="$3"
    _TUI_W_PH[$id]="${4:-}"
    _TUI_W_LABEL[$id]="${5:-}"
    _TUI_W_VALUE[$id]=""
    _TUI_W_ACTION[$id]=""
    _TUI_W_ORDER+=("$id")
    _TUI_FOCUSABLE+=("$id")
}

tui.get()       { printf '%s' "${_TUI_W_VALUE[$1]:-}"; }
tui.set()       { _TUI_W_VALUE[$1]="$2"; }
tui.update()    { _TUI_W_VALUE[$1]="$2"; _tui._draw_widget "$1"; }
tui.on_action() { _TUI_W_ACTION[$1]="$2"; }

# ═══════════════════════════════════════════════════════════════════════
#  GEOMETRY & RENDERING
# ═══════════════════════════════════════════════════════════════════════

_tui._repeat() {
    local ch="$1" n="$2" out=""
    (( n <= 0 )) && return
    printf -v out '%*s' "$n" ""
    printf '%s' "${out// /$ch}"
}

_tui._widget_pos() {
    local pane="${_TUI_W_PANE[$1]}"
    local wrow="${_TUI_W_ROW[$1]}"
    local pr=${_TUI_P_ROW[$pane]}  pc=${_TUI_P_COL[$pane]}
    local pw=${_TUI_P_W[$pane]}
    local border="${_TUI_P_BORDER[$pane]:-single}"

    if [[ "$border" == "none" ]]; then
        _WSR=$(( pr + wrow ))
        _WSC=$(( pc + 1 ))
        _WSW=$(( pw - 2 ))
    else
        _WSR=$(( pr + 1 + wrow ))
        _WSC=$(( pc + 2 ))
        _WSW=$(( pw - 4 ))
    fi
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

# ── Style Applier ──
_tui._apply_style() {
    local key="$1"
    local fg="${_TUI_STYLE_FG[$key]:-}"
    local bg="${_TUI_STYLE_BG[$key]:-}"
    local mods="${_TUI_STYLE_MOD[$key]:-}"
    
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

_tui._draw_pane() {
    local id="$1"
    local r=${_TUI_P_ROW[$id]}  c=${_TUI_P_COL[$id]}
    local h=${_TUI_P_H[$id]}    w=${_TUI_P_W[$id]}
    local border="${_TUI_P_BORDER[$id]:-single}"
    local title="${_TUI_P_TITLE[$id]:-}"

    [[ "$border" == "none" ]] && return

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
        # Leave room for corners and spaces (at least 4 chars smaller than inner width)
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

    local blank
    printf -v blank '%*s' "$inner" ""
    for (( row = 1; row < h - 1; row++ )); do
        cur.goto $(( r + row )) "$c"
        echo -n "${vt}${blank}${vt}"
    done

    cur.goto $(( r + h - 1 )) "$c"
    echo -n "${bl}$(_tui._repeat "$hz" "$inner")${br}"
    style.reset
}

_tui._draw_widget() {
    local id="$1"
    local type="${_TUI_W_TYPE[$id]}"
    local focused=0
    [[ "$_TUI_FOCUS_ID" == "$id" ]] && focused=1

    _tui._widget_pos "$id"
    local sr=$_WSR sc=$_WSC sw=$_WSW

    cur.goto "$sr" "$sc"
    printf '%*s' "$sw" ""
    cur.goto "$sr" "$sc"

    # Determine which style key to use
    local style_key="${id}_normal"
    (( focused )) && style_key="${id}_focus"

    case "$type" in
        label)
            _tui._apply_style "$style_key"
            echo -n "${_TUI_W_VALUE[$id]:0:$sw}"
            style.reset
            ;;
        button)
            local lbl="${_TUI_W_LABEL[$id]}"
            local pad=$(( (sw - ${#lbl}) / 2 ))
            (( pad < 0 )) && pad=0
            cur.goto "$sr" $(( sc + pad ))
            
            _tui._apply_style "$style_key"
            if (( focused )); then
                # Fallback in case yaml didn't define a focus style
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" && -z "${_TUI_STYLE_BG[$style_key]:-}" ]] && style.reverse
            else
                [[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && style.dim
            fi
            echo -n "$lbl"
            style.reset
            ;;
        input)
            local prefix="${_TUI_W_LABEL[$id]}"
            local value="${_TUI_W_VALUE[$id]}"
            local placeholder="${_TUI_W_PH[$id]:-}"

            local plen=0
            if [[ -n "$prefix" ]]; then
                style.bold
                echo -n "${prefix} "
                style.reset
                plen=$(( ${#prefix} + 1 ))
            fi

            local fw=$(( sw - plen ))       
            (( fw < 2 )) && fw=2

            _tui._apply_style "$style_key"
            if (( focused )); then
                local scroll=0
                if (( _TUI_CURSOR >= fw )); then
                    scroll=$(( _TUI_CURSOR - fw + 1 ))
                fi
                local visible="${value:$scroll:$fw}"

                style.underline
                printf '%-*s' "$fw" "$visible"
                style.reset; _tui._apply_style "$style_key"

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
                if [[ -z "$value" ]]; then
                    printf '%-*s' "$fw" "${placeholder:0:$fw}"
                else
                    printf '%-*s' "$fw" "${value:0:$fw}"
                fi
            fi
            style.reset
            ;;
    esac
}

tui.render() {
    mode.sync_start
    for pane in "${_TUI_P_LEAVES[@]}"; do
        _tui._draw_pane "$pane"
    done
    for wid in "${_TUI_W_ORDER[@]}"; do
        _tui._draw_widget "$wid"
    done
    mode.sync_end
}

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

    [[ "$end" == "m" ]] && return
    (( btn != 0 && btn != 32 )) && return

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
    local orows=$(( _EXEC_VROWS - 1 ))
    for (( i = 0; i < orows; i++ )); do
        tui.label "_xo_${i}" "$pane" $(( i + 1 )) ""
    done
}

_exec_setup_controls() {
    local pane="$_EXEC_CTL_PANE"

    tui.label  "_xstat"    "$pane" 0 ""
    tui.button "_xcancel"  "$pane" 1 "[ Cancel ]"        _exec_on_cancel
    tui.button "_xsave"    "$pane" 2 "[ Save Output ]"   _exec_on_save
    tui.button "_xview"    "$pane" 3 "[ View Command ]"  _exec_on_view
    tui.button "_xretry"   "$pane" 4 "[ Retry ]"         _exec_on_retry
    
    # New Back button
    tui.button "_xback"    "$pane" 5 "[ Back ]"          _exec_on_back
    
    tui.input  "_xinput"   "$pane" 6 "type and press Enter…" "stdin▸"
    tui.on_action "_xinput" _exec_on_send
}

_exec_remove_widgets() {
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

_exec_tick() {
    [[ "$_EXEC_STATUS" == "running" ]] || return

    local changed=0
    if [[ -s "$_EXEC_OUTFILE" ]]; then
        local new_lines=()
        mapfile -t new_lines < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        if (( ${#new_lines[@]} > 0 )); then
            _EXEC_BUF+=("${new_lines[@]}")
            (( _EXEC_LAST_READ += ${#new_lines[@]} ))
            changed=1
        fi
    fi

    if ! kill -0 "$_EXEC_PID" 2>/dev/null; then
        wait "$_EXEC_PID" 2>/dev/null
        _EXEC_EXIT=$?

        local leftover=()
        mapfile -t leftover < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        (( ${#leftover[@]} > 0 )) && _EXEC_BUF+=("${leftover[@]}")

        _EXEC_STATUS=$(( _EXEC_EXIT == 0 )) && _EXEC_STATUS="done" || _EXEC_STATUS="error"
        if (( _EXEC_EXIT == 0 )); then _EXEC_STATUS="done"; else _EXEC_STATUS="error"; fi

        _exec_render_status
        changed=1
    fi

    (( changed )) && _exec_render_output
}

_exec_render_status() {
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
    local orows=$(( _EXEC_VROWS - 1 ))
    local total=${#_EXEC_BUF[@]}
    local start=0
    (( total > orows )) && start=$(( total - orows ))

    mode.sync_start
    for (( i = 0; i < orows; i++ )); do
        local idx=$(( start + i ))
        local text=""
        (( idx < total )) && text="${_EXEC_BUF[$idx]}"

        _tui._widget_pos "_xo_${i}"
        tui.update "_xo_${i}" "${text:0:$_WSW}"
    done
    mode.sync_end
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
    
    tui.log.debug "Sending input: [REDACTED]"

    if [[ "$_EXEC_STATUS" == "running" ]]; then
        ( printf "%s\n" "$text" >&"$_EXEC_FIFO_FD" & ) 2>/dev/null
        local masked
        masked="$(printf '%*s' "${#text}" | tr ' ' '*')"
        _EXEC_BUF+=("▸ ${masked}")
    else
        tui.log.warn "Attempted to send input, but process is not running."
        _EXEC_BUF+=("(process not running — input discarded)")
    fi

    tui.set "_xinput" ""
    _tui._draw_widget "_xinput"
    _exec_render_output
}


# ═══════════════════════════════════════════════════════════════════════
#  MAIN EVENT LOOP
# ═══════════════════════════════════════════════════════════════════════

tui.run() {
    tui.log.debug "tui.run() starting"
    _TUI_RUNNING=1
    
    trap '_master_cleanup; exit 1' INT TERM

    tui.render
    tui.log.debug "tui.run() rendered"
    while (( _TUI_RUNNING )); do

        local char=""
        local got_char=0
        
        if [[ -n "${_TUI_TICK_FN:-}" ]]; then
            IFS= read -rsn1 -t 0.05 char && got_char=1
        else
            IFS= read -rsn1 char && got_char=1 || break
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
                        [[ -n "$faction" ]] && "$faction" "$_TUI_FOCUS_ID"
                        _tui._unfocus
                    fi
                fi
            elif [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                _tui._input_key "$_TUI_FOCUS_ID" "$char"
            fi
        fi

        [[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
    done

    _master_cleanup
}

tui.stop() { _TUI_RUNNING=0; }