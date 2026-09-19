#!/usr/bin/env bash
# tui_input.sh - keyboard + mouse bindings.
#
# Raw terminal bytes / escape sequences / SGR mouse reports are decoded into
# readable NAMES here, once, and everything the framework does in response
# (focus movement, scrolling, clicking a widget, ...) is an ordinary binding
# to a named ACTION that you can rebind, add to, or remove.
#
#   tui.bind KEY COMMAND [--pane ID] [--pass] [--always] [--page] [--desc TEXT]
#   tui.unbind KEY [--pane ID]         drop your binding (the default comes back)
#   tui.bind.reset                     drop every user binding
#   tui.bind.list                      table of all bindings (user + default)
#   tui.get.event                      "key=.. type=.. x=.. y=.. pane=.. widget=.."
#   _TUI_ON_KEY_EVENT=fn   hook: fn NAME runs for every decoded key/mouse name (used by the Debug keyboard view)
#
#   COMMAND is a function name (optionally with args): "on_quit", "tui.action.scroll down 10".
#           Several can be chained with ';' :  "log_key; tui.action.quit"
#   --pane ID  only while that pane is focused (keys) / under the pointer (mouse)
#   --pass     after running, also run the next binding (e.g. the default) - adds
#              behavior instead of replacing it
#   --always   also fire while a text input has focus (normally typing keys don't)
#   --page     dropped on the next page change (markup <bind> uses this)
#
# KEY names (case-insensitive except single letters):
#   a  Q  1  /  space  enter  tab  esc  backspace  delete  insert
#   up down left right  home end  pgup pgdn  f1..f12
#   modifiers:  ctrl+c  alt+x  shift+tab  ctrl+alt+up  shift+up   ("shift+q" == "Q")
#   mouse:      mouse:left  mouse:right  mouse:middle   drag:left  release
#               wheel:up  wheel:down  wheel:left  wheel:right   (also ctrl+/alt+/shift+ prefixed)
#
# Inside a handler these are set:
#   TUI_EVENT_TYPE   key | mouse         TUI_EVENT_KEY     canonical name ("ctrl+c")
#   TUI_EVENT_X/Y    pointer col/row     TUI_EVENT_PANE    pane (focused / under pointer)
#   TUI_EVENT_WIDGET widget id           TUI_EVENT_BUTTON  left|middle|right|""
#
# Built-in actions (all bound by default, all rebindable):
#   tui.action.quit  focus_next  focus_prev  activate  unfocus  click
#   tui.action.scroll up|down|left|right [N]   tui.action.page up|down
#   tui.action.scroll_top  tui.action.scroll_bottom

declare -gA _TUI_BIND=()          # "scope|key" -> command        (user; scope = "" or "pane:ID")
declare -gA _TUI_BIND_DEF=()      # key -> command                (built-in defaults)
declare -gA _TUI_BIND_PASS=() _TUI_BIND_ALWAYS=() _TUI_BIND_PAGE=() _TUI_BIND_DESC=()
declare -g  TUI_EVENT_TYPE="" TUI_EVENT_KEY="" TUI_EVENT_X=0 TUI_EVENT_Y=0
declare -g  TUI_EVENT_PANE="" TUI_EVENT_WIDGET="" TUI_EVENT_BUTTON="" TUI_EVENT_RAWBTN=0
declare -g  _KEY=""
declare -g  TUI_EVENT_COUNT=1 _TUI_REPEAT=1        # >1: that many identical scroll events were merged into this one
declare -g  _TUI_KEYS_SUSPENDED=0 _TUI_SUSPEND_NAME="ctrl+alt+k"
declare -g  _TUI_PASSTHROUGH=0 _TUI_PT_NAME="ctrl+alt+p"
declare -g  TUI_PASSTHROUGH_KEY="ctrl+alt+p"     # chord that hands mouse+keyboard back to the terminal (and back again)
declare -g  TUI_KEYS_SUSPEND_KEY="ctrl+alt+k"    # toggle chord for the keybind kill-switch (tui.keys.suspend_key to change)
# Repeat coalescing (wheel spins, held scroll keys): identical back-to-back events
# already buffered are merged into ONE dispatch with TUI_EVENT_COUNT=n, so a fast
# scroll costs one redraw, not n. Only events bound to tui.action.scroll/page merge.
declare -g  TUI_INPUT_COALESCE=1 TUI_INPUT_COALESCE_MAX=60
declare -g  _TUI_ON_KEY_EVENT=""   # optional hook: called with every decoded key/mouse name ("move" for pointer motion)

# ── key-spec normalisation (what the developer types) ───────────────────

# _tui_input.norm SPEC -> _KEY
_tui_input.norm() {
    local s="$1"
    if (( ${#s} <= 1 )); then _KEY="$s"; return; fi
    s="${s,,}"
    local -a parts=(); local ctrl=0 alt=0 shift=0 key p
    IFS='+' read -ra parts <<< "${s//-/+}"
    # "ctrl++"-style specs split oddly; the name "plus" exists for that
    key="${parts[-1]}"; unset 'parts[-1]'
    for p in "${parts[@]}"; do
        case "$p" in
            ctrl|control|c) ctrl=1 ;;
            alt|meta|a|m)   alt=1 ;;
            shift|s)        shift=1 ;;
        esac
    done
    case "$key" in
        return|ret) key=enter ;;   escape) key=esc ;;        del) key=delete ;;
        ins) key=insert ;;         bs) key=backspace ;;      spc) key=space ;;
        pageup|page_up) key=pgup ;; pagedown|page_down) key=pgdn ;;
        plus) key="+" ;;           minus) key="-" ;;
    esac
    if [[ "$key" == [a-z] ]] && (( shift && !ctrl && !alt )); then
        key="${key^^}"; shift=0
    fi
    _KEY="${ctrl:+}"
    (( ctrl )) && _KEY+="ctrl+"
    (( alt ))  && _KEY+="alt+"
    (( shift )) && _KEY+="shift+"
    _KEY+="$key"
}

# ── decoding (what the terminal sends) ──────────────────────────────────

# _tui_input.mods N -> _MODS ("ctrl+alt+shift+" prefix) from an xterm modifier param
_tui_input.mods() {
    local m=$(( ${1:-1} - 1 ))
    _MODS=""
    (( m & 4 )) && _MODS+="ctrl+"
    (( m & 2 )) && _MODS+="alt+"
    (( m & 1 )) && _MODS+="shift+"
}

# _tui_input.name_char CHAR -> _KEY
_tui_input.name_char() {
    local c="$1" code oct
    case "$c" in
        $'\t')          _KEY=tab ;;
        $'\n'|$'\r')    _KEY=enter ;;
        $'\x7f'|$'\b')  _KEY=backspace ;;
        ' ')            _KEY=space ;;
        *)
            printf -v code '%d' "'$c"
            if (( code >= 1 && code <= 26 )); then
                printf -v oct '%03o' $(( code + 96 ))
                printf -v _KEY "\\$oct"
                _KEY="ctrl+$_KEY"
            else
                _KEY="$c"
            fi ;;
    esac
}

# _tui_input.name_codepoint N -> _KEY : base key name for a Unicode codepoint (CSI u)
_tui_input.name_codepoint() {
    _KEY=""
    [[ "$1" =~ ^[0-9]+$ ]] || return
    case "$1" in
        9) _KEY=tab ;; 13) _KEY=enter ;; 27) _KEY=esc ;; 32) _KEY=space ;; 127) _KEY=backspace ;;
        *) local hex; printf -v hex '%08x' "$1"; printf -v _KEY "\\U$hex" ;;
    esac
}

# _tui_input.name_seq SEQ -> _KEY   (SEQ = bytes after ESC; "" is a bare ESC)
_tui_input.name_seq() {
    local seq="$1" body final mod=1 num third
    _KEY=""
    if [[ -z "$seq" ]]; then _KEY=esc; return; fi
    case "$seq" in
        "[Z") _KEY="shift+tab"; return ;;
        "["*)
            body="${seq#\[}"; final="${body: -1}"; body="${body%?}"
            IFS=';' read -r num mod third <<< "$body"
            [[ "$mod" =~ ^[0-9]+$ ]] || mod=1
            _tui_input.mods "$mod"
            # CSI u (kitty/foot/wezterm) and xterm modifyOtherKeys (CSI 27;mods;cp ~) carry a codepoint
            if [[ "$final" == u ]]; then _tui_input.name_codepoint "$num"
            elif [[ "$final" == "~" && "$num" == 27 ]]; then _tui_input.name_codepoint "$third"; fi
            if [[ -n "$_KEY" ]]; then
                [[ "$_MODS" == "shift+" && "$_KEY" == [a-z] ]] && { _KEY="${_KEY^^}"; _MODS=""; }
                if [[ "$_KEY" == [A-Z] && ( "$_MODS" == *ctrl+* || "$_MODS" == *alt+* ) ]]; then _KEY="${_KEY,,}"; [[ "$_MODS" == *shift+ ]] || _MODS+="shift+"; fi
                _KEY="${_MODS}${_KEY}"; return
            fi
            case "$final" in
                A) _KEY=up ;; B) _KEY=down ;; C) _KEY=right ;; D) _KEY=left ;;
                H) _KEY=home ;; F) _KEY=end ;;
                P) _KEY=f1 ;; Q) _KEY=f2 ;; R) _KEY=f3 ;; S) _KEY=f4 ;;
                "~") case "$num" in
                        1|7) _KEY=home ;; 2) _KEY=insert ;; 3) _KEY=delete ;; 4|8) _KEY=end ;;
                        5) _KEY=pgup ;; 6) _KEY=pgdn ;;
                        11) _KEY=f1 ;; 12) _KEY=f2 ;; 13) _KEY=f3 ;; 14) _KEY=f4 ;;
                        15) _KEY=f5 ;; 17) _KEY=f6 ;; 18) _KEY=f7 ;; 19) _KEY=f8 ;;
                        20) _KEY=f9 ;; 21) _KEY=f10 ;; 23) _KEY=f11 ;; 24) _KEY=f12 ;;
                     esac ;;
            esac
            [[ -n "$_KEY" ]] && _KEY="${_MODS}${_KEY}"
            return ;;
        "O"?)   # SS3 (application mode): arrows, F1-F4
            case "${seq:1:1}" in
                A) _KEY=up ;; B) _KEY=down ;; C) _KEY=right ;; D) _KEY=left ;;
                H) _KEY=home ;; F) _KEY=end ;;
                P) _KEY=f1 ;; Q) _KEY=f2 ;; R) _KEY=f3 ;; S) _KEY=f4 ;;
            esac
            return ;;
    esac
    if (( ${#seq} == 1 )); then      # ESC + char = alt+char
        _tui_input.name_char "${seq}"
        if [[ "$_KEY" == ctrl+* ]]; then _KEY="ctrl+alt+${_KEY#ctrl+}"; else _KEY="alt+${_KEY}"; fi
    fi
}

# _tui_input.name_mouse BTN END -> _KEY ("" for a bare move) + TUI_EVENT_BUTTON
_tui_input.name_mouse() {
    local btn="$1" end="$2" pre="" b kind
    (( btn & 16 )) && pre+="ctrl+"
    (( btn & 8 ))  && pre+="alt+"
    (( btn & 4 ))  && pre+="shift+"
    TUI_EVENT_BUTTON=""
    if (( btn & 64 )); then
        case $(( btn & 3 )) in 0) kind=up ;; 1) kind=down ;; 2) kind=left ;; 3) kind=right ;; esac
        _KEY="${pre}wheel:${kind}"; return
    fi
    case $(( btn & 3 )) in 0) b=left ;; 1) b=middle ;; 2) b=right ;; 3) b="" ;; esac
    TUI_EVENT_BUTTON="$b"
    if [[ "$end" == "m" ]]; then _KEY="${pre}release"
    elif (( btn & 32 )); then
        [[ -z "$b" ]] && { _KEY=""; return; }
        _KEY="${pre}drag:${b}"
    else _KEY="${pre}mouse:${b}"
    fi
}

# Keys the focused text input consumes itself; user/default bindings on
# these are skipped while an input has focus (unless bound with --always).
_tui_input.is_typing() {
    case "$1" in
        backspace|delete|space|left|right|home|end) return 0 ;;
        [[:print:]]) return 0 ;;
    esac
    return 1
}

# ── registration ────────────────────────────────────────────────────────
# Two binding tables: CODE binds (tui.bind from app code / markup <bind>: never persisted) and USER binds
# (tui.bind --user: made by the person using the app; saved/loaded/discarded as a set, see the persistence
# section at the end of this file). A user bind beats a code bind on the same key.
declare -gA _TUI_UBIND=() _TUI_UBIND_PASS=() _TUI_UBIND_ALWAYS=() _TUI_UBIND_DESC=()
declare -g  _TUI_UBIND_BASESTR=""                     # serialized user binds as last saved/loaded (dirty check)

tui.bind() {
    (( _TUI_BIND_GEN++ ))
    local spec="$1" cmd="$2" pane="" pass="" always="" page="" desc="" user=""
    [[ -z "$spec" || -z "$cmd" ]] && { echo "tui.bind: usage: tui.bind KEY COMMAND [flags]" >&2; return 1; }
    shift 2
    while (( $# )); do
        case "$1" in
            --pane)   pane="$2"; shift ;;
            --pass)   pass=1 ;;
            --always) always=1 ;;
            --page)   page=1 ;;
            --user)   user=1 ;;
            --desc)   desc="$2"; shift ;;
        esac
        shift
    done
    _tui_input.norm "$spec"
    local id="${pane:+pane:$pane}|${_KEY}"
    if [[ -n "$user" ]]; then
        _TUI_UBIND[$id]="$cmd"
        [[ -n "$pass" ]]   && _TUI_UBIND_PASS[$id]=1   || unset '_TUI_UBIND_PASS[$id]'
        [[ -n "$always" ]] && _TUI_UBIND_ALWAYS[$id]=1 || unset '_TUI_UBIND_ALWAYS[$id]'
        [[ -n "$desc" ]]   && _TUI_UBIND_DESC[$id]="$desc" || unset '_TUI_UBIND_DESC[$id]'
        return 0
    fi
    _TUI_BIND[$id]="$cmd"
    [[ -n "$pass" ]]   && _TUI_BIND_PASS[$id]=1   || unset '_TUI_BIND_PASS[$id]'
    [[ -n "$always" ]] && _TUI_BIND_ALWAYS[$id]=1 || unset '_TUI_BIND_ALWAYS[$id]'
    [[ -n "$page" ]]   && _TUI_BIND_PAGE[$id]=1   || unset '_TUI_BIND_PAGE[$id]'
    [[ -n "$desc" ]]   && _TUI_BIND_DESC[$id]="$desc" || unset '_TUI_BIND_DESC[$id]'
    return 0
}

# tui.unbind KEY [--pane ID] [--user]   (--user: remove your own binding; without it, a code binding)
tui.unbind() {
    (( _TUI_BIND_GEN++ ))
    local spec="$1" pane="" user=""; shift
    while (( $# )); do
        case "$1" in --pane) pane="$2"; shift ;; --user) user=1 ;; esac
        shift
    done
    _tui_input.norm "$spec"
    local id="${pane:+pane:$pane}|${_KEY}"
    if [[ -n "$user" ]]; then
        unset '_TUI_UBIND[$id]' '_TUI_UBIND_PASS[$id]' '_TUI_UBIND_ALWAYS[$id]' '_TUI_UBIND_DESC[$id]'
    else
        unset '_TUI_BIND[$id]' '_TUI_BIND_PASS[$id]' '_TUI_BIND_ALWAYS[$id]' '_TUI_BIND_PAGE[$id]' '_TUI_BIND_DESC[$id]'
    fi
}

# tui.bind.reset [--user]   drop all code binds, or (--user) all user binds
tui.bind.reset() {
    (( _TUI_BIND_GEN++ ))
    if [[ "$1" == --user ]]; then _TUI_UBIND=(); _TUI_UBIND_PASS=(); _TUI_UBIND_ALWAYS=(); _TUI_UBIND_DESC=(); return 0; fi
    _TUI_BIND=(); _TUI_BIND_PASS=(); _TUI_BIND_ALWAYS=(); _TUI_BIND_PAGE=(); _TUI_BIND_DESC=()
}

# Called by tui.reset_ui: drops bindings made with --page (markup <bind>).
_tui_input.clear_page() {
    (( _TUI_BIND_GEN++ ))
    local id
    for id in "${!_TUI_BIND_PAGE[@]}"; do
        unset '_TUI_BIND[$id]' '_TUI_BIND_PASS[$id]' '_TUI_BIND_ALWAYS[$id]' '_TUI_BIND_PAGE[$id]' '_TUI_BIND_DESC[$id]'
    done
    _TUI_DEF_OFF_PAGE=()          # page-scoped default-group switches end with the page
}

# tui.bind.list - "SCOPE<TAB>KEY<TAB>COMMAND<TAB>NOTE": your binds, then code binds, then defaults.
# _tui_input.bind_rows builds them into _BL (fork-free); tui.bind.list prints, tui.bind.table formats.
declare -ga _BL=()
_tui_input.bind_rows() {
    local id key scope note; local -A shadowed=()
    _BL=()
    _tui_input.sorted_ids _TUI_UBIND
    for id in "${_SIDS[@]}"; do
        scope="${id%%|*}"; key="${id#*|}"
        note="${_TUI_UBIND_DESC[$id]:-}${_TUI_UBIND_PASS[$id]:+ (pass)} (yours)"
        [[ "${_TUI_UBIND_BASE_CMD[$id]-}" != "${_TUI_UBIND[$id]}" ]] && note+=" (unsaved)"
        _BL+=("${scope:-global}"$'\t'"$key"$'\t'"${_TUI_UBIND[$id]}"$'\t'"$note")
        [[ -z "$scope" ]] && shadowed[$key]=1
    done
    _tui_input.sorted_ids _TUI_BIND
    for id in "${_SIDS[@]}"; do
        scope="${id%%|*}"; key="${id#*|}"
        _BL+=("${scope:-global}"$'\t'"$key"$'\t'"${_TUI_BIND[$id]}"$'\t'"${_TUI_BIND_DESC[$id]:-}${_TUI_BIND_PASS[$id]:+ (pass)}${_TUI_BIND_PAGE[$id]:+ (page)}${shadowed[$key]:+ (overridden)}")
        [[ -z "$scope" ]] && shadowed[$key]=1
    done
    _tui_input.sorted_ids _TUI_BIND_DEF
    for key in "${_SIDS[@]}"; do
        _BL+=("default"$'\t'"$key"$'\t'"${_TUI_BIND_DEF[$key]}"$'\t'"[${_TUI_BIND_DEF_GROUP[$key]}] ${_TUI_BIND_DEF_DESC[$key]:-}${shadowed[$key]:+ (overridden)}${_TUI_DEF_OFF[${_TUI_BIND_DEF_GROUP[$key]}]:+ (off)}")
    done
}
tui.bind.list() { _tui_input.bind_rows; (( ${#_BL[@]} )) && printf '%s\n' "${_BL[@]}"; }

# tui.bind.table -> _TBL: the same rows as an aligned text table (header, rule, rows), no forks and no renderer.
tui.bind.table() {
    local -a w=(5 3 7 4); local row c i out="" line sp
    local -a hdr=(Scope Key Command Note) cells
    _tui_input.bind_rows
    for row in "${_BL[@]}"; do
        IFS=$'\t' read -ra cells <<< "$row"
        for i in 0 1 2 3; do c="${cells[i]:-}"; (( ${#c} > w[i] )) && w[i]=${#c}; done
    done
    line="│"; for i in 0 1 2 3; do printf -v sp '%*s' "$(( w[i] - ${#hdr[i]} ))" ''; line+=" ${hdr[i]}${sp} │"; done
    out+="$line"$'\n'
    line="├"; for i in 0 1 2 3; do printf -v sp '%*s' "$(( w[i] + 2 ))" ''; line+="${sp// /─}"; (( i < 3 )) && line+="┼"; done; line+="┤"
    out+="$line"$'\n'
    for row in "${_BL[@]}"; do
        IFS=$'\t' read -ra cells <<< "$row"
        line="│"
        for i in 0 1 2 3; do c="${cells[i]:-}"; printf -v sp '%*s' "$(( w[i] - ${#c} ))" ''; line+=" ${c}${sp} │"; done
        out+="$line"$'\n'
    done
    _TBL="${out%$'\n'}"
}
# _tui_input.sorted_ids ARRAYNAME -> _SIDS: the array's keys, sorted (insertion sort: tables are small, no fork)
_tui_input.sorted_ids() {
    local -n _t="$1"; local k i j
    _SIDS=()
    for k in "${!_t[@]}"; do
        for (( i = 0; i < ${#_SIDS[@]}; i++ )); do [[ "$k" < "${_SIDS[i]}" ]] && break; done
        _SIDS=("${_SIDS[@]:0:i}" "$k" "${_SIDS[@]:i}")
    done
}

tui.get.event() {
    printf 'type=%s key=%s x=%s y=%s pane=%s widget=%s button=%s\n' "$TUI_EVENT_TYPE" "$TUI_EVENT_KEY" \
        "$TUI_EVENT_X" "$TUI_EVENT_Y" "$TUI_EVENT_PANE" "$TUI_EVENT_WIDGET" "$TUI_EVENT_BUTTON"
}

# ── dispatch ────────────────────────────────────────────────────────────

# _tui_input.run CMD - runs "fn arg; fn2 arg" (no eval: split on ';' then words). A command that isn't
# defined (a saved user bind whose page/callback isn't loaded right now) is skipped, not an error.
_tui_input.run() {
    local cmd="$1" part
    local -a words
    while [[ -n "$cmd" ]]; do
        part="${cmd%%;*}"
        [[ "$cmd" == *";"* ]] && cmd="${cmd#*;}" || cmd=""
        read -ra words <<< "$part"
        (( ${#words[@]} )) || continue
        if declare -F "${words[0]}" >/dev/null || type -t "${words[0]}" >/dev/null; then "${words[@]}"
        else TUI_LAST_BIND_ERROR="no such command: ${words[0]}"; fi
    done
}

# _tui_input.dispatch NAME - run the binding(s) for NAME. Order, for the focused pane's scope then global:
# your bind, code bind; then the built-in default. A binding stops the chain unless it was bound with
# --pass. rc 0 = something ran.
declare -g TUI_LAST_BIND_ERROR=""
_tui_input.dispatch() {
    local name="$1" id i handled=1 typing=0
    if [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]:-}" == input ]] && _tui_input.is_typing "$name"; then
        typing=1
    fi
    TUI_EVENT_KEY="$name"
    local -a ck=() cid=()
    if [[ -n "$TUI_EVENT_PANE" ]]; then ck+=(U C); cid+=("pane:$TUI_EVENT_PANE|$name" "pane:$TUI_EVENT_PANE|$name"); fi
    ck+=(U C D); cid+=("|$name" "|$name" "$name")
    for i in "${!ck[@]}"; do
        id="${cid[i]}"
        case "${ck[i]}" in
            D)
                _tui_input.default_active "$name" || continue        # no default, or its group is switched off
                (( typing )) && [[ -z "${_TUI_BIND_DEF_ALWAYS[$name]:-}" ]] && continue
                _tui_input.run "${_TUI_BIND_DEF[$name]}"; handled=0
                break ;;
            U)
                [[ -n "${_TUI_UBIND[$id]:-}" ]] || continue
                (( typing )) && [[ -z "${_TUI_UBIND_ALWAYS[$id]:-}" ]] && continue
                _tui_input.run "${_TUI_UBIND[$id]}"; handled=0
                [[ -n "${_TUI_UBIND_PASS[$id]:-}" ]] || break ;;
            C)
                [[ -n "${_TUI_BIND[$id]:-}" ]] || continue
                (( typing )) && [[ -z "${_TUI_BIND_ALWAYS[$id]:-}" ]] && continue
                _tui_input.run "${_TUI_BIND[$id]}"; handled=0
                [[ -n "${_TUI_BIND_PASS[$id]:-}" ]] || break ;;
        esac
    done
    return $handled
}

# _tui_input.key_event RAW_CHAR RAW_SEQ - entry point from the main loop for
# every non-mouse key. rc 1 = nothing bound it (caller feeds a focused input).
_tui_input.key_event() {
    local char="$1" seq="$2"
    if [[ -n "$char" ]]; then _tui_input.name_char "$char"; else _tui_input.name_seq "$seq"; fi
    local name="$_KEY"
    [[ -z "$name" ]] && return 1
    # Terminal-control mode: only the chord is heard; everything else is swallowed.
    if [[ "$name" == "$_TUI_PT_NAME" ]]; then tui.passthrough toggle; return 0; fi
    (( _TUI_PASSTHROUGH )) && return 0
    TUI_EVENT_TYPE=key; TUI_EVENT_BUTTON=""
    TUI_EVENT_WIDGET="$_TUI_FOCUS_ID"
    TUI_EVENT_PANE=""
    if [[ -n "$_TUI_FOCUS_ID" ]]; then TUI_EVENT_PANE="${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}"
    else TUI_EVENT_PANE="${_TUI_HOVERED_PANE:-}"; fi
    [[ -n "$_TUI_ON_INPUT_EVENT" ]] && _tui._notify_input "key $name"
    TUI_EVENT_COUNT=$_TUI_REPEAT; _TUI_REPEAT=1
    [[ -n "$_TUI_ON_KEY_EVENT" ]] && "$_TUI_ON_KEY_EVENT" "$name" "$TUI_EVENT_COUNT"

    # Keybind kill-switch (keyboard only; the mouse is never affected).
    if [[ "$name" == "$_TUI_SUSPEND_NAME" ]]; then tui.keys.suspend toggle; return 0; fi
    # An open modal (command palette, dialogs) owns the keyboard: bindings, focus and scrolling are suspended.
    if [[ -n "$_TUI_MODAL" ]]; then "$_TUI_MODAL_KEYFN" "$name"; return 0; fi
    if (( _TUI_KEYS_SUSPENDED )); then
        # Every binding, user and default, is off. A focused text input still
        # works: typing/cursor keys fall through (rc 1), Enter still submits.
        if [[ "$name" == enter && -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]:-}" == input ]]; then
            tui.action.activate; return 0
        fi
        return 1
    fi
    _tui_input.dispatch "$name"
}

# _tui_input.mouse_event BTN END MX MY - called by _tui._handle_mouse after it
# has updated hover state.
_tui_input.mouse_event() {
    _tui_input.name_mouse "$1" "$2"
    local name="$_KEY"
    TUI_EVENT_TYPE=mouse; TUI_EVENT_X="$3"; TUI_EVENT_Y="$4"; TUI_EVENT_RAWBTN="$1"
    TUI_EVENT_PANE="${_TUI_HOVERED_PANE:-}"
    TUI_EVENT_WIDGET="${_TUI_HOVERED_WIDGET:-}"
    TUI_EVENT_COUNT=$_TUI_REPEAT; _TUI_REPEAT=1
    if [[ -n "$_TUI_ON_KEY_EVENT" ]]; then "$_TUI_ON_KEY_EVENT" "${name:-move}" "$TUI_EVENT_COUNT"; fi
    [[ -z "$name" ]] && return 1
    # A modal owns the pointer too: its handler gets the event, everything else is ignored.
    if [[ -n "$_TUI_MODAL" ]]; then [[ -n "$_TUI_MODAL_MOUSEFN" ]] && "$_TUI_MODAL_MOUSEFN" "$name" "$3" "$4"; return 0; fi
    _tui_input.dispatch "$name"
}

# ── built-in actions ────────────────────────────────────────────────────

tui.action.quit()       { tui.stop; }
tui.action.focus_next() { _tui._focus_next; }
tui.action.focus_prev() { _tui._focus_prev; }
tui.action.unfocus()    { [[ -n "$_TUI_FOCUS_ID" ]] && _tui._unfocus; }

# Enter on the focused widget: press a button, toggle a checkbox, submit an input.
tui.action.activate() {
    [[ -n "$_TUI_FOCUS_ID" ]] || return 0
    local ftype="${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" faction="${_TUI_W_ACTION[$_TUI_FOCUS_ID]:-}"
    case "$ftype" in
        button)   [[ -n "$faction" ]] && "$faction" "$_TUI_FOCUS_ID" ;;
        checkbox) tui.checkbox.toggle "$_TUI_FOCUS_ID" ;;
        input)
            local wid="$_TUI_FOCUS_ID" submit_fn="${_TUI_W_SUBMIT[$_TUI_FOCUS_ID]:-}"
            if [[ -n "$submit_fn" ]]; then "$submit_fn" "$(tui.get "$wid")"
            elif [[ -n "$faction" ]]; then "$faction" "$wid"; fi
            # Retain Input On Submit (tui.input.retain / retain_input_on_submit=): the cursor stays in the input.
            # The callback may have changed page or removed the widget: re-check first.
            if [[ "$_TUI_FOCUS_ID" == "$wid" && -n "${_TUI_W_TYPE[$wid]:-}" ]]; then
                if [[ "${_TUI_W_RETAIN[$wid]:-$TUI_INPUT_RETAIN_ON_SUBMIT}" != 1 ]]; then _tui._unfocus
                else
                    local vlen=${#_TUI_W_VALUE[$wid]}          # the callback may have cleared the text
                    (( _TUI_CURSOR > vlen )) && _TUI_CURSOR=$vlen
                    _tui._draw_widget "$wid"
                fi
            fi ;;
    esac
}

# _tui_input.scroll_target -> _ST : the pane a scroll action should move.
_tui_input.scroll_target() {
    local p=""
    if [[ "$TUI_EVENT_TYPE" == mouse ]]; then p="$TUI_EVENT_PANE"
    else
        # keys: the keyboard pane (f6 / alt+arrows / clicking it) wins; else under the pointer; else the focused widget's pane
        p="$_TUI_PANE_FOCUS"
        [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" == none ]] && p=""
        [[ -z "$p" ]] && p="${_TUI_HOVERED_PANE:-}"
        [[ -z "$p" && -n "$_TUI_FOCUS_ID" ]] && p="${_TUI_W_PANE[$_TUI_FOCUS_ID]}"
    fi
    if [[ -z "$p" || "${_TUI_P_SCROLL[$p]:-none}" == none ]]; then
        [[ "$TUI_EVENT_TYPE" == mouse ]] && { _ST=""; return 1; }
        local t
        p=""
        for t in "${_TUI_P_ALL[@]}"; do
            [[ "${_TUI_P_SCROLL[$t]:-none}" != none ]] && { p="$t"; break; }
        done
    fi
    _ST="$p"
    [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != none ]]
}

# tui.action.scroll up|down|left|right [N]
tui.action.scroll() {
    _tui_input.scroll_target || return 0
    local p="$_ST" n="${2:-}" c=${TUI_EVENT_COUNT:-1}   # c > 1 when repeats were merged
    case "$1" in
        up)    (( _TUI_P_SOFF_V[$p] -= ${n:-3} * c )) ;;
        down)  (( _TUI_P_SOFF_V[$p] += ${n:-3} * c )) ;;
        left)  (( _TUI_P_SOFF_H[$p] -= ${n:-5} * c )) ;;
        right) (( _TUI_P_SOFF_H[$p] += ${n:-5} * c )) ;;
    esac
    _tui._queue_render "$p"
}

# tui.action.page up|down - one viewport at a time
tui.action.page() {
    _tui_input.scroll_target || return 0
    local p="$_ST" step=$(( ${_TUI_P_H[$_ST]} - 3 ))
    (( step < 1 )) && step=1
    (( step *= ${TUI_EVENT_COUNT:-1} ))
    case "$1" in up) (( _TUI_P_SOFF_V[$p] -= step )) ;; down) (( _TUI_P_SOFF_V[$p] += step )) ;; esac
    _tui._queue_render "$p"
}

tui.action.scroll_top()    { _tui_input.scroll_target || return 0; _TUI_P_SOFF_V[$_ST]=0; _TUI_P_SOFF_H[$_ST]=0; _tui._queue_render "$_ST"; }
tui.action.scroll_bottom() { _tui_input.scroll_target || return 0; _TUI_P_SOFF_V[$_ST]=999999; _tui._queue_render "$_ST"; }

# Left press/drag: scrollbar jump, else activate the widget under the pointer,
# else drop focus.
tui.action.click() {
    local mx="$TUI_EVENT_X" my="$TUI_EVENT_Y" btn="$TUI_EVENT_RAWBTN" p="$TUI_EVENT_PANE"
    local hover_widget="$TUI_EVENT_WIDGET"

    # Scrollbar jump: only while the left button is actually down (press or
    # drag), never on bare hover.
    if [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != "none" ]] && (( (btn & 3) == 0 )); then
        if (( mx == _TUI_P_COL[$p] + _TUI_P_W[$p] - 1 )); then
            local rel_y=$(( my - _TUI_P_ROW[$p] )) total_lines=${_TUI_P_LINES[$p]:-1}
            _TUI_P_SOFF_V[$p]=$(( (rel_y * total_lines) / _TUI_P_H[$p] ))
            _tui._queue_render "$p"
            return
        fi
        if (( my == _TUI_P_ROW[$p] + _TUI_P_H[$p] - 1 )); then
            local rel_x=$(( mx - _TUI_P_COL[$p] )) max_w=${_TUI_P_MAX_W[$p]:-1}
            _TUI_P_SOFF_H[$p]=$(( (rel_x * max_w) / _TUI_P_W[$p] ))
            _tui._queue_render "$p"
            return
        fi
    fi

    [[ "$TUI_EVENT_KEY" == drag:* ]] && return      # drags only move scrollbars

    if [[ -n "$hover_widget" ]]; then
        local wid="$hover_widget" wtype="${_TUI_W_TYPE[$hover_widget]}"
        case "$wtype" in
            button)
                tui.focus "$wid"
                local action="${_TUI_W_ACTION[$wid]:-}"
                [[ -n "$action" ]] && "$action" "$wid" ;;
            checkbox)
                tui.focus "$wid"
                tui.checkbox.toggle "$wid" ;;
            input)
                tui.focus "$wid"
                _tui._widget_pos "$wid"
                local prefix="${_TUI_W_LABEL[$wid]}" plen=0
                [[ -n "$prefix" ]] && plen=$(( ${#prefix} + 1 ))
                local click=$(( mx - _WSC - plen ))
                (( click < 0 )) && click=0
                local vlen=${#_TUI_W_VALUE[$wid]}
                (( click > vlen )) && click=$vlen
                _TUI_CURSOR=$click
                _tui._draw_widget "$wid" ;;
        esac
    else
        # clicking a scrollable pane makes it the keyboard pane too
        [[ -n "$p" && "${_TUI_P_SCROLL[$p]:-none}" != none ]] && tui.pane.focus "$p"
        # a sticky input (shell prompt) keeps focus when you click empty space
        [[ -n "$_TUI_FOCUS_ID" && -n "${_TUI_W_STICKY[$_TUI_FOCUS_ID]:-}" ]] && return 0
        _tui._unfocus
    fi
}

# ── defaults (loaded from config/default/keybinds.xml) ──────────────────
# The built-in bindings are DATA, not code: one <bind key= action= group= [always=] [desc=]/> per line
# in ${TUI_DEFAULTS_DIR}/keybinds.xml (default: <repo>/config/default). Each belongs to a GROUP, and a
# group can be switched off - that is how defaults are opt-out:
#   tui.defaults.off GROUP... [--page]   e.g. tui.defaults.off quit scroll   (--page: until the page changes)
#   tui.defaults.on  GROUP...
#   tui.defaults.list                    GROUP<TAB>state<TAB>keys
# Markup: <tui defaults="-quit,-scroll"> switches groups off for that page.
declare -g  TUI_DEFAULTS_DIR="${TUI_DEFAULTS_DIR:-${SCRIPT_DIR:-.}/../config/default}"
declare -gA _TUI_BIND_DEF_GROUP=() _TUI_BIND_DEF_DESC=() _TUI_BIND_DEF_ALWAYS=()
declare -gA _TUI_DEF_OFF=() _TUI_DEF_OFF_PAGE=()

# _tui_input.attr LINE NAME -> _ATTR (fork-free attribute read)
_tui_input.attr() {
    _ATTR=""
    [[ "$1" =~ (^|[[:space:]])$2=\"([^\"]*)\" ]] && _ATTR="${BASH_REMATCH[2]}"
    return 0
}

# tui.bind.defaults [FILE] - (re)load the default bindings.
tui.bind.defaults() {
    (( _TUI_BIND_GEN++ ))
    local file="${1:-$TUI_DEFAULTS_DIR/keybinds.xml}" line key act
    _TUI_BIND_DEF=(); _TUI_BIND_DEF_GROUP=(); _TUI_BIND_DEF_DESC=(); _TUI_BIND_DEF_ALWAYS=()
    if [[ ! -r "$file" ]]; then echo "tui.bind.defaults: cannot read '$file' (no default keybinds)" >&2; return 1; fi
    while IFS= read -r line; do
        [[ "$line" == *"<bind "* ]] || continue
        _tui_input.attr "$line" key;    key="$_ATTR"
        _tui_input.attr "$line" action; act="$_ATTR"
        [[ -z "$key" || -z "$act" ]] && continue
        _tui_input.norm "$key"; key="$_KEY"
        _TUI_BIND_DEF[$key]="$act"
        _tui_input.attr "$line" group;  _TUI_BIND_DEF_GROUP[$key]="${_ATTR:-misc}"
        _tui_input.attr "$line" desc;   _TUI_BIND_DEF_DESC[$key]="$_ATTR"
        _tui_input.attr "$line" always; [[ "$_ATTR" == true ]] && _TUI_BIND_DEF_ALWAYS[$key]=1
    done < "$file"
}

tui.defaults.off() {
    (( _TUI_BIND_GEN++ ))
    local page="" g
    for g in "$@"; do
        [[ "$g" == --page ]] && page=1
    done
    for g in "$@"; do
        [[ "$g" == --page ]] && continue
        if [[ -n "$page" ]]; then _TUI_DEF_OFF_PAGE[$g]=1; else _TUI_DEF_OFF[$g]=1; fi
    done
}
tui.defaults.on() { (( _TUI_BIND_GEN++ )); local g; for g in "$@"; do unset '_TUI_DEF_OFF[$g]' '_TUI_DEF_OFF_PAGE[$g]'; done; }

tui.defaults.list() {
    local k g state; local -A keys=()
    for k in "${!_TUI_BIND_DEF_GROUP[@]}"; do g="${_TUI_BIND_DEF_GROUP[$k]}"; keys[$g]+="${keys[$g]:+ }$k"; done
    for g in $(printf '%s\n' "${!keys[@]}" | sort); do
        state=on; [[ -n "${_TUI_DEF_OFF[$g]:-}${_TUI_DEF_OFF_PAGE[$g]:-}" ]] && state=off
        printf '%s\t%s\t%s\n' "$g" "$state" "${keys[$g]}"
    done
}

# true when the default bound to NAME exists and its group is not switched off
_tui_input.default_active() {
    local g="${_TUI_BIND_DEF_GROUP[$1]:-}"
    [[ -n "${_TUI_BIND_DEF[$1]:-}" && -z "${_TUI_DEF_OFF[$g]:-}${_TUI_DEF_OFF_PAGE[$g]:-}" ]]
}

tui.bind.defaults

# ── keybind kill-switch (keyboard only) ─────────────────────────────────
#   tui.keys.suspend [on|off|toggle]   suspend every keyboard binding, user AND default
#   tui.keys.suspended                 rc 0 while suspended
#   tui.keys.suspend_key SPEC          change the toggle chord (default ctrl+alt+k)
# Global: it survives page changes. Mouse input is untouched. While it is on a
# warning box is drawn bottom-right over everything, showing the chord to leave.
# Only the chord, a focused input's typing/cursor keys and Enter-to-submit work.

tui.keys.suspended() { (( _TUI_KEYS_SUSPENDED )); }

tui.keys.suspend_key() {
    _tui_input.norm "$1"
    TUI_KEYS_SUSPEND_KEY="$1"; _TUI_SUSPEND_NAME="$_KEY"
}

tui.keys.suspend() {
    local v
    case "${1:-toggle}" in on) v=1 ;; off) v=0 ;; *) v=$(( !_TUI_KEYS_SUSPENDED )) ;; esac
    (( v == _TUI_KEYS_SUSPENDED )) && return 0
    _TUI_KEYS_SUSPENDED=$v
    (( _TUI_RUNNING )) || return 0
    if (( v )); then _tui_input.draw_overlay
    else tui.relayout            # full repaint wipes the box
    fi
}

# Drawn over whatever is there: on toggle, at the end of tui.render, and once per
# main-loop iteration, so nothing that repaints underneath can leave it covered.
_tui_input.draw_overlay() {
    (( _TUI_KEYS_SUSPENDED )) || return 0
    _tui_input.draw_box " KEYBINDS OFF (keyboard) " " ${TUI_KEYS_SUSPEND_KEY} = turn back on " "1;97;41"
}

# _tui_input.draw_box LINE1 LINE2 SGR - a 2-line framed box, bottom-right, drawn over everything.
_tui_input.draw_box() {
    local l1="$1" l2="$2" sgr="$3" w bar pad1 pad2 row col
    w=${#l1}; (( ${#l2} > w )) && w=${#l2}
    printf -v bar '%*s' "$w" ''; bar="${bar// /─}"
    printf -v pad1 '%-*s' "$w" "$l1"; printf -v pad2 '%-*s' "$w" "$l2"
    row=$(( _TUI_ROWS - 3 )); col=$(( _TUI_COLS - w - 1 ))
    (( row < 1 )) && row=1; (( col < 1 )) && col=1
    printf '\e7\e[%sm\e[%d;%dH┌%s┐\e[%d;%dH│%s│\e[%d;%dH│%s│\e[%d;%dH└%s┘\e[0m\e8' \
        "$sgr" "$row" "$col" "$bar" $((row+1)) "$col" "$pad1" $((row+2)) "$col" "$pad2" $((row+3)) "$col" "$bar"
}

# ── repeat coalescing ───────────────────────────────────────────────────

# _tui_input.coalescible NAME - true when NAME's effective binding is a scroll/page
# action (the only ones that understand TUI_EVENT_COUNT) and nobody scoped it to a pane.
_tui_input.coalescible() {
    local n="$1" id cmd
    [[ -n "$n" ]] || return 1          # unknown/undecodable key: nothing to look up
    for id in "${!_TUI_BIND[@]}" "${!_TUI_UBIND[@]}"; do [[ "$id" == pane:*"|$n" ]] && return 1; done
    cmd="${_TUI_UBIND[|$n]:-${_TUI_BIND[|$n]:-}}"
    [[ -z "$cmd" ]] && _tui_input.default_active "$n" && cmd="${_TUI_BIND_DEF[$n]}"
    [[ "$cmd" == "tui.action.scroll "* || "$cmd" == "tui.action.page "* ]]
}

# _tui_input.same_event KIND FIRST NEXT - is NEXT a repeat of FIRST? (mouse: same
# button code, position ignored)
_tui_input.same_event() {
    if [[ "$1" == mouse ]]; then
        local a="${2#\[<}" b="${3#\[<}"
        [[ "${2: -1}" == M && "${3: -1}" == M && "${a%%;*}" == "${b%%;*}" ]]
    else
        [[ "$2" == "$3" ]]
    fi
}

# _tui_input.coalesce KIND FIRST_RAW  (KIND: mouse|key; FIRST_RAW: the SGR seq / a
# char / an escape seq). Peeks at already-buffered input and swallows immediate
# repeats. Sets _TUI_REPEAT=n and, for mouse, _TUI_SEQ_BUF to the newest seq. A
# non-matching event is pushed back byte-for-byte (same rewind trick as the
# mouse-motion coalescer). TUI_MOUSE_DRAIN_PEEK_TIMEOUT must stay > 0.
_tui_input.coalesce() {
    local kind="$1" first="$2" c next n=1 latest="$2"
    while (( n < TUI_INPUT_COALESCE_MAX )); do
        IFS= read -rsn1 -t "$TUI_MOUSE_DRAIN_PEEK_TIMEOUT" c || break
        if [[ "$c" != $'\e' ]]; then
            if [[ "$kind" == key && "$c" == "$first" ]]; then (( n++ )); continue; fi
            _TUI_PENDING_INPUT+="$c"; break
        fi
        _tui._read_escape_seq
        next="$_TUI_SEQ_BUF"
        if [[ "$kind" == mouse && "$next" == "[<"* ]] && _tui_input.same_event mouse "$first" "$next"; then
            (( n++ )); latest="$next"; continue
        elif [[ "$kind" == key && "$next" == "$first" ]]; then
            (( n++ )); continue
        fi
        _TUI_PENDING_INPUT+=$'\e'"$next"; break
    done
    _TUI_REPEAT=$n; _TUI_SEQ_BUF="$latest"
}

# Entry points used by the main loop. Both leave _TUI_REPEAT=1 when nothing merged.
_tui_input.coalesce_mouse() {   # SEQ  -> may replace _TUI_SEQ_BUF with the newest repeat
    _TUI_REPEAT=1; _TUI_SEQ_BUF="$1"
    (( TUI_INPUT_COALESCE )) || return 0
    [[ -n "$_TUI_PENDING_INPUT" ]] && return 0
    local b="${1#\[<}"; b="${b%%;*}"
    [[ "$b" =~ ^[0-9]+$ ]] && (( b & 64 )) && [[ "${1: -1}" == M ]] || return 0
    _tui_input.name_mouse "$b" M
    _tui_input.coalescible "$_KEY" || return 0
    _tui_input.coalesce mouse "$1"
}

_tui_input.coalesce_key() {     # CHAR SEQ
    _TUI_REPEAT=1
    (( _TUI_PASSTHROUGH )) && return 0
    (( TUI_INPUT_COALESCE )) || return 0
    (( _TUI_KEYS_SUSPENDED )) && return 0
    [[ -n "$_TUI_PENDING_INPUT" ]] && return 0
    [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]:-}" == input ]] && return 0
    if [[ -n "$1" ]]; then _tui_input.name_char "$1"; else _tui_input.name_seq "$2"; fi
    _tui_input.coalescible "$_KEY" || return 0
    if [[ -n "$1" ]]; then _tui_input.coalesce key "$1"; else _tui_input.coalesce key "$2"; fi
}

# ── terminal-control mode (pass-through) ────────────────────────────────
#   tui.passthrough [on|off|toggle]   hand the mouse and keyboard back to the terminal
#   tui.passthrough.active            rc 0 while on
#   tui.passthrough.key SPEC          change the chord (default ctrl+alt+p)
# While on: mouse reporting is switched OFF, so the terminal does native selection,
# right-click menus, URL clicking and its own wheel scrolling; the screen is FROZEN
# (no timers, no pane redraws, no resize relayout - a repaint would drop the selection);
# every key except the chord is ignored, so the terminal's own shortcuts (ctrl+shift+c ...)
# work. Background jobs keep running and their output is applied when you leave.
# A small box, drawn once, shows how to get back. Independent of the keybind kill-switch.

tui.passthrough.active() { (( _TUI_PASSTHROUGH )); }

tui.passthrough.key() {
    _tui_input.norm "$1"
    TUI_PASSTHROUGH_KEY="$1"; _TUI_PT_NAME="$_KEY"
}

tui.passthrough() {
    local v
    case "${1:-toggle}" in on) v=1 ;; off) v=0 ;; *) v=$(( !_TUI_PASSTHROUGH )) ;; esac
    (( v == _TUI_PASSTHROUGH )) && return 0
    _TUI_PASSTHROUGH=$v
    (( _TUI_RUNNING )) || return 0
    if (( v )); then
        printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l'
        _TUI_PENDING_INPUT=""            # drop half-read input; reports still in flight are ignored
        _tui_input.draw_box " TERMINAL MODE - mouse & keyboard are yours " " ${TUI_PASSTHROUGH_KEY} = back to the app " "1;30;46"
    else
        mouse.any_on; mouse.sgr_on
        tui.relayout                     # one full repaint: applies everything queued while frozen
        declare -F _tui_api.on_resize >/dev/null && _tui_api.on_resize
    fi
    return 0
}

# ── pane focus (keyboard-selected pane: scroll target + highlighted border) ─
#   tui.pane.focus PANE         make PANE the keyboard pane ("" clears)
#   tui.get.pane_focus          current keyboard pane
# Widgets keep their own focus; focusing a widget moves pane focus to its pane.
declare -g  _TUI_PANE_FOCUS=""
declare -gA _TUI_PANE_LAST_WIDGET=()      # pane -> last widget that had focus there

tui.pane.focus() {
    local old="$_TUI_PANE_FOCUS"
    _TUI_PANE_FOCUS="$1"
    [[ "$old" == "$1" ]] && return 0
    (( _TUI_RUNNING )) && _tui._draw_pane_borders_now "$old" "$1"
    return 0
}
tui.get.pane_focus() { printf '%s\n' "$_TUI_PANE_FOCUS"; }

# _tui_input.nav_panes -> _NAVP: visible leaf panes worth keyboard-focusing: scrollable ones, or ones with 2+
# widgets (a menu, a form). Single-widget cells - toolbar buttons, tab headers - are reached with Tab / arrows.
_tui_input.nav_panes() {
    local -A has=(); local w p
    for w in "${_TUI_FOCUSABLE[@]}"; do (( has[${_TUI_W_PANE[$w]:-}]++ )); done
    _NAVP=()
    for p in "${_TUI_P_LEAVES[@]}"; do
        (( ${_TUI_P_H[$p]:-0} < 1 || ${_TUI_P_W[$p]:-0} < 1 )) && continue
        if [[ "${_TUI_P_SCROLL[$p]:-none}" != none || "${has[$p]:-0}" -ge 2 ]]; then _NAVP+=("$p"); fi
    done
}

# _tui_input.pane_current -> _PC: the pane keyboard actions start from
_tui_input.pane_current() {
    _PC="$_TUI_PANE_FOCUS"
    [[ -z "$_PC" && -n "$_TUI_FOCUS_ID" ]] && _PC="${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}"
    [[ -z "$_PC" ]] && _PC="${_TUI_HOVERED_PANE:-}"
    return 0
}

# tui.action.focus_pane PANE - keyboard focus lands on PANE: its last (or first) widget if it has any,
# otherwise it just becomes the scroll pane.
tui.action.focus_pane() {
    local p="$1" w first="" last="${_TUI_PANE_LAST_WIDGET[$1]:-}"
    [[ -n "${_TUI_P_H[$p]:-}" ]] || return 1
    for w in "${_TUI_FOCUSABLE[@]}"; do
        [[ "${_TUI_W_PANE[$w]:-}" == "$p" ]] || continue
        [[ -z "$first" ]] && first="$w"
    done
    if [[ -n "$last" && -n "${_TUI_W_TYPE[$last]:-}" ]]; then tui.focus "$last"
    elif [[ -n "$first" ]]; then tui.focus "$first"
    else
        [[ -n "$_TUI_FOCUS_ID" ]] && _tui._unfocus
        tui.pane.focus "$p"
    fi
}

_tui_input.pane_step() {      # +1 / -1
    _tui_input.nav_panes
    (( ${#_NAVP[@]} )) || return 0
    _tui_input.pane_current
    local i idx=-1
    for i in "${!_NAVP[@]}"; do [[ "${_NAVP[i]}" == "$_PC" ]] && { idx=$i; break; }; done
    if (( idx < 0 )); then (( $1 > 0 )) && idx=-1 || idx=0; fi
    idx=$(( (idx + $1 + ${#_NAVP[@]}) % ${#_NAVP[@]} ))
    tui.action.focus_pane "${_NAVP[idx]}"
}
tui.action.pane_next() { _tui_input.pane_step 1; }
tui.action.pane_prev() { _tui_input.pane_step -1; }

# tui.action.pane_dir up|down|left|right - nearest navigable pane in that direction (by geometry)
tui.action.pane_dir() {
    _tui_input.nav_panes
    _tui_input.pane_current
    local cur="$_PC" p best="" bs=999999 cy cx py px dy dx s
    if [[ -z "$cur" || -z "${_TUI_P_H[$cur]:-}" ]]; then tui.action.pane_next; return; fi
    (( cy = _TUI_P_ROW[$cur] * 2 + _TUI_P_H[$cur], cx = _TUI_P_COL[$cur] * 2 + _TUI_P_W[$cur] ))   # doubled centres: integer math
    for p in "${_NAVP[@]}"; do
        [[ "$p" == "$cur" ]] && continue
        (( py = _TUI_P_ROW[$p] * 2 + _TUI_P_H[$p], px = _TUI_P_COL[$p] * 2 + _TUI_P_W[$p], dy = py - cy, dx = px - cx ))
        case "$1" in
            up)    (( dy < 0 )) || continue; s=$(( -dy * 2 + (dx < 0 ? -dx : dx) )) ;;
            down)  (( dy > 0 )) || continue; s=$(( dy * 2 + (dx < 0 ? -dx : dx) )) ;;
            left)  (( dx < 0 )) || continue; s=$(( -dx + (dy < 0 ? -dy : dy) * 4 )) ;;
            right) (( dx > 0 )) || continue; s=$(( dx + (dy < 0 ? -dy : dy) * 4 )) ;;
        esac
        (( s < bs )) && { bs=$s; best="$p"; }
    done
    [[ -n "$best" ]] && tui.action.focus_pane "$best"
    return 0
}

# ── spatial widget navigation ───────────────────────────────────────────
# tui.action.focus_dir up|down|left|right - move focus to the widget you would EXPECT in that direction.
# "Beam" model, so uneven grids (rows with different column counts, panes of different widths) behave:
#   left/right: only widgets on the SAME screen row, nearest first. Nothing to the right = stay put.
#   up/down:    only widgets whose column span overlaps the current one (the beam straight above/below);
#               nearest row first, and within that row the one whose centre is closest.
# Nothing in the beam = stay put. It never falls back to list order: that is what made Down at the
# bottom of a toolbar hop sideways along the row. Tab / shift+tab still walk the whole list.
# (An earlier "nearest by weighted distance" rule let a button one row up win over the next button in the
#  same row whenever the columns didn't line up, which made repeated Right hop between rows.)
tui.action.focus_dir() {
    local dir="$1" w cr cc cw r c wd dr s ccx cx best="" bs=999999999
    (( ${#_TUI_FOCUSABLE[@]} )) || return 0
    if [[ -z "$_TUI_FOCUS_ID" ]]; then
        case "$dir" in down|right) tui.focus "${_TUI_FOCUSABLE[0]}" ;; *) tui.focus "${_TUI_FOCUSABLE[-1]}" ;; esac
        return 0
    fi
    _tui._widget_pos "$_TUI_FOCUS_ID"; cr=$_WSR; cc=$_WSC; cw=$_WSW
    (( ccx = cc * 2 + cw ))                                  # doubled centre: integer math
    for w in "${_TUI_FOCUSABLE[@]}"; do
        [[ "$w" == "$_TUI_FOCUS_ID" ]] && continue
        (( ${_TUI_P_H[${_TUI_W_PANE[$w]}]:-0} < 1 )) && continue
        _tui._widget_pos "$w"; r=$_WSR; c=$_WSC; wd=$_WSW
        (( dr = r - cr ))
        case "$dir" in
            right) (( dr == 0 && c > cc )) || continue; s=$(( c - cc )) ;;
            left)  (( dr == 0 && c < cc )) || continue; s=$(( cc - c )) ;;
            up|down)
                if [[ "$dir" == up ]]; then (( dr < 0 )) || continue; else (( dr > 0 )) || continue; fi
                (( c < cc + cw && cc < c + wd )) || continue          # column spans must overlap
                (( cx = c * 2 + wd - ccx )); (( cx < 0 )) && (( cx = -cx ))
                (( dr < 0 )) && (( dr = -dr ))
                s=$(( dr * 100000 + cx )) ;;
        esac
        (( s < bs )) && { bs=$s; best="$w"; }
    done
    [[ -n "$best" ]] && tui.focus "$best"        # nothing there: stay put (Tab still walks the list)
}

# ── page actions ────────────────────────────────────────────────────────
declare -gA _TUI_PAGES=()        # page file -> title (registered by nav buttons with page=)
tui.action.goto() { [[ -n "$1" ]] && tui.goto "$1"; }
tui.get.pages() { local p; for p in "${!_TUI_PAGES[@]}"; do printf '%s\t%s\n' "$p" "${_TUI_PAGES[$p]}"; done | sort; }

# ── bracketed paste + clipboard ─────────────────────────────────────────
# tui.init enables bracketed paste (ESC[?2004h): a paste arrives as ESC[200~ ... ESC[201~ instead of a
# stream of fake keystrokes, so a pasted newline can't submit and pasted letters can't fire bindings.
# It becomes the key name "paste" (bindable: tui.bind paste fn) with the text in TUI_EVENT_PASTE.
declare -g  TUI_EVENT_PASTE="" TUI_LAST_PASTE=""

_tui_input.read_paste() {
    local buf="" chunk end=$'\e[201~' idle=0
    if [[ -n "$_TUI_PENDING_INPUT" ]]; then buf="$_TUI_PENDING_INPUT"; _TUI_PENDING_INPUT=""; fi
    while [[ "$buf" != *"$end"* ]]; do
        chunk=""
        if IFS= read -rs -d '' -n 4096 -t 0.5 chunk; then idle=0; else (( idle++ )); fi
        buf+="$chunk"
        (( idle >= 4 )) && break                # terminal never sent the end marker: give up after ~2 s
    done
    TUI_EVENT_PASTE="${buf%%"$end"*}"
    [[ "$buf" == *"$end"* ]] && _TUI_PENDING_INPUT="${buf#*"$end"}${_TUI_PENDING_INPUT}"
}

_tui_input.paste_event() {
    (( _TUI_PASSTHROUGH )) && return 0
    TUI_LAST_PASTE="$TUI_EVENT_PASTE"
    TUI_EVENT_TYPE=paste; TUI_EVENT_KEY=paste; TUI_EVENT_BUTTON=""
    TUI_EVENT_WIDGET="$_TUI_FOCUS_ID"
    TUI_EVENT_PANE="${_TUI_HOVERED_PANE:-}"
    [[ -n "$_TUI_FOCUS_ID" ]] && TUI_EVENT_PANE="${_TUI_W_PANE[$_TUI_FOCUS_ID]:-$TUI_EVENT_PANE}"     # empty id = bad array subscript
    [[ -n "$_TUI_ON_KEY_EVENT" ]] && "$_TUI_ON_KEY_EVENT" paste 1
    if [[ -n "$_TUI_MODAL" ]]; then "$_TUI_MODAL_KEYFN" paste; return 0; fi
    if (( _TUI_KEYS_SUSPENDED )); then tui.action.paste; return 0; fi     # keyboard kill-switch: typing still works
    _tui_input.dispatch paste
}

# tui.action.paste - insert the pasted text at the cursor of the focused input (single line: newlines and
# control characters become spaces / are dropped).
tui.action.paste() {
    [[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]:-}" == input ]] || return 0
    local wid="$_TUI_FOCUS_ID" t="$TUI_EVENT_PASTE" v
    t="${t//$'\r\n'/ }"; t="${t//$'\n'/ }"; t="${t//$'\r'/ }"; t="${t//$'\t'/ }"
    t="${t//[[:cntrl:]]/}"
    [[ -z "$t" ]] && return 0
    v="${_TUI_W_VALUE[$wid]}"
    _TUI_W_VALUE[$wid]="${v:0:$_TUI_CURSOR}${t}${v:$_TUI_CURSOR}"
    (( _TUI_CURSOR += ${#t} ))
    _tui._draw_widget "$wid"
}

# _tui_b64 STRING -> _B64 (pure bash, byte-wise)
_tui_b64() {
    local LC_ALL=C s="$1" out="" i n a b c t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" v
    n=${#s}
    for (( i = 0; i < n; i += 3 )); do
        printf -v a '%d' "'${s:i:1}"; (( a &= 255 ))
        if (( i + 1 < n )); then printf -v b '%d' "'${s:i+1:1}"; (( b &= 255 )); else b=0; fi
        if (( i + 2 < n )); then printf -v c '%d' "'${s:i+2:1}"; (( c &= 255 )); else c=0; fi
        v=$(( (a << 16) | (b << 8) | c ))
        out+="${t:(v >> 18) & 63:1}${t:(v >> 12) & 63:1}"
        if (( i + 1 < n )); then out+="${t:(v >> 6) & 63:1}"; else out+="="; fi
        if (( i + 2 < n )); then out+="${t:v & 63:1}"; else out+="="; fi
    done
    _B64="$out"
}

# tui.clipboard.copy TEXT - OSC 52 (kitty, foot, wezterm, alacritty, iTerm2, tmux with set-clipboard on).
# GNOME Terminal / VTE ignores OSC 52.   tui.clipboard.paste - the text of the last bracketed paste.
tui.clipboard.copy()  { _tui_b64 "$1"; printf '\e]52;c;%s\a' "$_B64"; }
tui.clipboard.paste() { printf '%s' "$TUI_LAST_PASTE"; }

# ── user keybinds: save / load / discard ────────────────────────────────
# Bindings made with `tui.bind --user` are the person's own. They are held in memory as a DRAFT until saved:
#   tui.bind.save [FILE]     write them to disk (default $TUI_USER_KEYBINDS) - they load automatically next start
#   tui.bind.discard         throw the unsaved changes away (reload from the saved file; no file = none)
#   tui.bind.load [FILE]     replace the user binds with the file's
#   tui.bind.dirty           rc 0 while there are unsaved changes
#   tui.bind.saved_file      print the path in use
# File: ${XDG_CONFIG_HOME:-~/.config}/${TUI_APP_NAME:-dabt}/keybinds.xml - the same <bind .../> line format as
# config/default/keybinds.xml. Set TUI_APP_NAME (before sourcing tui.sh) to give your app its own directory.
declare -g  TUI_APP_NAME="${TUI_APP_NAME:-dabt}"
declare -g  TUI_USER_KEYBINDS="${TUI_USER_KEYBINDS:-${XDG_CONFIG_HOME:-$HOME/.config}/$TUI_APP_NAME/keybinds.xml}"
declare -gA _TUI_UBIND_BASE_CMD=()                       # id -> command as saved (per-entry "(unsaved)" marks)

tui.bind.saved_file() { printf '%s\n' "$TUI_USER_KEYBINDS"; }

_tui_input.esc() { _ESC="$1"; _ESC="${_ESC//&/\&amp;}"; _ESC="${_ESC//</\&lt;}"; _ESC="${_ESC//>/\&gt;}"; _ESC="${_ESC//\"/\&quot;}"; }
_tui_input.unesc() { _UNESC="$1"; _UNESC="${_UNESC//&lt;/<}"; _UNESC="${_UNESC//&gt;/>}"; _UNESC="${_UNESC//&quot;/\"}"; _UNESC="${_UNESC//&amp;/\&}"; }

# _tui_input.serialize -> _SER : the user binds as <bind/> lines, sorted (also the dirty-check fingerprint)
_tui_input.serialize() {
    local id key scope line
    _SER=""
    _tui_input.sorted_ids _TUI_UBIND
    for id in "${_SIDS[@]}"; do
        scope="${id%%|*}"; key="${id#*|}"
        _tui_input.esc "$key"; line="<bind key=\"$_ESC\""
        _tui_input.esc "${_TUI_UBIND[$id]}"; line+=" action=\"$_ESC\""
        [[ -n "$scope" ]] && { _tui_input.esc "${scope#pane:}"; line+=" pane=\"$_ESC\""; }
        [[ -n "${_TUI_UBIND_PASS[$id]:-}" ]]   && line+=" pass=\"true\""
        [[ -n "${_TUI_UBIND_ALWAYS[$id]:-}" ]] && line+=" always=\"true\""
        [[ -n "${_TUI_UBIND_DESC[$id]:-}" ]]   && { _tui_input.esc "${_TUI_UBIND_DESC[$id]}"; line+=" desc=\"$_ESC\""; }
        _SER+="$line/>"$'\n'
    done
}

tui.bind.dirty() { _tui_input.serialize; [[ "$_SER" != "$_TUI_UBIND_BASESTR" ]]; }

_tui_input.mark_saved() {
    local id
    _tui_input.serialize; _TUI_UBIND_BASESTR="$_SER"
    _TUI_UBIND_BASE_CMD=()
    for id in "${!_TUI_UBIND[@]}"; do _TUI_UBIND_BASE_CMD[$id]="${_TUI_UBIND[$id]}"; done
}

tui.bind.save() {
    local file="${1:-$TUI_USER_KEYBINDS}" dir="${1:-$TUI_USER_KEYBINDS}"
    dir="${dir%/*}"
    mkdir -p "$dir" 2>/dev/null || { echo "tui.bind.save: cannot create '$dir'" >&2; return 1; }
    _tui_input.serialize
    if [[ -z "$_SER" ]]; then rm -f "$file"       # nothing left to keep: an empty saved set is no file
    else
        { printf '<!-- your keybinds (tui.bind --user). Edit freely; the Keys page and tui.bind.save rewrite this file. -->\n<binds>\n%s</binds>\n' "$_SER"; } > "$file.tmp" \
            && mv -f "$file.tmp" "$file" || { echo "tui.bind.save: cannot write '$file'" >&2; return 1; }
    fi
    _tui_input.mark_saved
}

tui.bind.load() {
    local file="${1:-$TUI_USER_KEYBINDS}" line key act pane pass always desc
    tui.bind.reset --user
    if [[ -r "$file" ]]; then
        while IFS= read -r line; do
            [[ "$line" == *"<bind "* ]] || continue
            _tui_input.attr "$line" key;    _tui_input.unesc "$_ATTR"; key="$_UNESC"
            _tui_input.attr "$line" action; _tui_input.unesc "$_ATTR"; act="$_UNESC"
            [[ -z "$key" || -z "$act" ]] && continue
            _tui_input.attr "$line" pane;   _tui_input.unesc "$_ATTR"; pane="$_UNESC"
            _tui_input.attr "$line" pass;   pass="$_ATTR"
            _tui_input.attr "$line" always; always="$_ATTR"
            _tui_input.attr "$line" desc;   _tui_input.unesc "$_ATTR"; desc="$_UNESC"
            local -a fl=(--user)
            [[ -n "$pane" ]] && fl+=(--pane "$pane")
            [[ "$pass" == true ]] && fl+=(--pass)
            [[ "$always" == true ]] && fl+=(--always)
            [[ -n "$desc" ]] && fl+=(--desc "$desc")
            tui.bind "$key" "$act" "${fl[@]}"
        done < "$file"
    fi
    _tui_input.mark_saved
}

tui.bind.discard() { tui.bind.load "$TUI_USER_KEYBINDS"; }

tui.bind.load          # user keybinds from the last run apply from the start (unresolved commands are skipped)

# _tui_input.reverse_keys -> _REVK (assoc): command -> the key shown for it (global scope only). Your own binds win over
# code binds, which win over active defaults; within a tier the LONGEST name wins, so a chord (ctrl+q, ctrl+p) is preferred
# to a bare key (q, :), the way footers and menus usually show them.
declare -gA _REVK=()
_tui_input.reverse_keys() {
    local -A ru=() rc=() rd=(); local k a
    _REVK=()
    for k in "${!_TUI_UBIND[@]}"; do [[ "$k" == \|* ]] || continue; a="${_TUI_UBIND[$k]}"; [[ -z "${ru[$a]:-}" || ${#k} -gt $(( ${#ru[$a]} + 1 )) ]] && ru[$a]="${k#|}"; done
    for k in "${!_TUI_BIND[@]}";  do [[ "$k" == \|* ]] || continue; a="${_TUI_BIND[$k]}";  [[ -z "${rc[$a]:-}" || ${#k} -gt $(( ${#rc[$a]} + 1 )) ]] && rc[$a]="${k#|}"; done
    for k in "${!_TUI_BIND_DEF[@]}"; do
        _tui_input.default_active "$k" || continue
        a="${_TUI_BIND_DEF[$k]}"; [[ -z "${rd[$a]:-}" || ${#k} -gt ${#rd[$a]} ]] && rd[$a]="$k"
    done
    for a in "${!ru[@]}" "${!rc[@]}" "${!rd[@]}"; do _REVK[$a]="${ru[$a]:-${rc[$a]:-${rd[$a]:-}}}"; done
}
