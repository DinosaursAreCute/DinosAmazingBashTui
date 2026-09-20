#!/usr/bin/env bash
# debug_input_callbacks.sh - Debug > "Keyboard & mouse": every key and mouse
# control drawn as a same-sized cell (tui.fixed grid), dark grey at rest and lit
# when tui_input.sh decodes it (_TUI_ON_KEY_EVENT). Keys pulse (a terminal only
# reports presses); mouse buttons stay lit until the release report.


# name:label[:span] ; a leading "!" starts a new row ; "~" = display-only (no events)
_DBG_KB_ROWS=(
    "!esc:Esc f1:F1 f2:F2 f3:F3 f4:F4 f5:F5 f6:F6 f7:F7 f8:F8 f9:F9 f10:F10 f11:F11 f12:F12"
    "!\`:\`  1:1 2:2 3:3 4:4 5:5 6:6 7:7 8:8 9:9 0:0 -:- =:= backspace:Bksp:2"
    "!tab:Tab:2 q:Q w:W e:E r:R t:T y:Y u:U i:I o:O p:P [:[ ]:] \\:\\"
    "!~caps:Caps:2 a:A s:S d:D f:F g:G h:H j:J k:K l:L ;:; ':' enter:Enter:2"
    "!shift:Shift:3 z:Z x:X c:C v:V b:B n:N m:M ,:, .:. /:/ up:↑"
    "!ctrl:Ctrl:2 alt:Alt:2 space:Space:6 left:← down:↓ right:→"
    "!insert:Ins delete:Del home:Hom end:End pgup:PgU pgdn:PgD"
)
_DBG_MOUSE=(
    "!m_left:Left:2 m_middle:Mid:2 m_right:Right:2"
    "!m_wheel_up:▲ m_wheel_down:▼ m_wheel_left:◀ m_wheel_right:▶ m_drag:Drag:2 m_release:Rel:2"
)
declare -g TUI_KEY_LIT_TICKS=${TUI_KEY_LIT_TICKS:-6}     # how many loop ticks a pressed key stays lit
declare -gA _DBG_LIT=()
declare -g _DBG_COUNT=0 _DBG_LAST="" _DBG_NKEYS=0

# _dbg_id NAME -> _DBG_ID  (pane id for a key name; punctuation is hex-escaped)
_dbg_id() {
    local n="$1" out="" c i
    if [[ "$n" == m_* ]]; then _DBG_ID="$n"; return; fi
    for (( i = 0; i < ${#n}; i++ )); do
        c="${n:i:1}"
        if [[ "$c" == [A-Za-z0-9] ]]; then out+="$c"; else printf -v c '_x%02x' "'$c"; out+="$c"; fi
    done
    _DBG_ID="k_$out"
}

# Fixed-size grid: recomputed from the frame size on every visit / resize.
_dbg_layout() {
    local frame="$1" unit="$2" kh="$3"; shift 3
    local -a rows=("$@") specs=() row tok name label span nl first
    local -a toks
    for row in "${rows[@]}"; do
        first=1
        read -ra toks <<< "${row#!}"
        for tok in "${toks[@]}"; do
            nl=""; (( first )) && nl=1; first=0
            [[ "$tok" == "~"* ]] && tok="${tok#\~}"
            IFS=: read -r name label span <<< "$tok"
            _dbg_id "$name"
            specs+=("${_DBG_ID}:${span:-1}:${nl}")
        done
    done
    tui.fixed "$frame" "$unit" "$kh" "${specs[@]}"

    local w text pad
    for row in "${rows[@]}"; do
        read -ra toks <<< "${row#!}"
        for tok in "${toks[@]}"; do
            local dim=0; [[ "$tok" == "~"* ]] && { dim=1; tok="${tok#\~}"; }
            IFS=: read -r name label span <<< "$tok"
            _dbg_id "$name"
            # kh>=3: a keycap frame (border costs 4 cols, leaves one label row); else frameless
            if (( kh >= 3 )); then w=$(( ${span:-1} * unit - 4 )); tui.pane_border "$_DBG_ID" single
            else w=$(( ${span:-1} * unit - 2 )); fi
            (( w < 1 )) && w=1
            label="${label:0:w}"
            pad=$(( (w - ${#label}) / 2 ))
            printf -v text '%*s%s' "$pad" "" "$label"
            tui.output "$_DBG_ID" "$text"
            tui.class "$_DBG_ID" "$([[ $dim == 1 ]] && echo key_dim || echo key)"
        done
    done
}

_dbg_build() {
    tui.pane_size kb_frame
    local unit=$(( TUI_PANE_COLS / 15 )) kh=3
    (( unit > 9 )) && unit=9
    (( unit < 6 )) && unit=6
    (( TUI_PANE_ROWS < 21 )) && kh=2
    _dbg_layout kb_frame "$unit" "$kh" "${_DBG_KB_ROWS[@]}"

    tui.pane_size mouse_frame
    local mu=$(( TUI_PANE_COLS / 9 )) mh=3
    (( mu > 9 )) && mu=9
    (( mu < 6 )) && mu=6
    (( TUI_PANE_ROWS < 6 )) && mh=2
    _dbg_layout mouse_frame "$mu" "$mh" "${_DBG_MOUSE[@]}"
    _dbg_readout
}

_dbg_readout() {
    tui.set_text readout "last:    ${_DBG_LAST:--}"$'\n'"events:  $_DBG_COUNT"$'\n'"pointer: ${TUI_EVENT_X},${TUI_EVENT_Y}"$'\n'"pane:    ${TUI_EVENT_PANE:--}"$'\n'"widget:  ${TUI_EVENT_WIDGET:--}"$'\n'"button:  ${TUI_EVENT_BUTTON:--}"
}

# ── lighting ──────────────────────────────────────────────────────────────
_dbg_light() {           # NAME [hold]
    _dbg_id "$1"
    [[ -n "${_TUI_P_H[$_DBG_ID]:-}" ]] || return 0
    tui.class "$_DBG_ID" key_hot
    tui.relayout "$_DBG_ID"
    if [[ -n "$2" ]]; then unset '_DBG_LIT[$_DBG_ID]'       # held until an explicit unlight
    else _DBG_LIT[$_DBG_ID]=$TUI_KEY_LIT_TICKS; tui.tick.add _dbg_tick   # re-press restarts the count
    fi
}
_dbg_unlight() {         # job id "un_<pane>" or a pane id
    local id="${1#un_}"
    unset '_DBG_LIT[$id]'
    [[ -n "${_TUI_P_H[$id]:-}" ]] || return 0
    tui.class "$id" key
    tui.relayout "$id"
}

# Lit for a few main-loop ticks (~50 ms each), not a wall-clock timer.
_dbg_tick() {
    (( ${#_DBG_LIT[@]} )) || { tui.tick.remove _dbg_tick; return 0; }
    local id
    for id in "${!_DBG_LIT[@]}"; do
        (( --_DBG_LIT[$id] <= 0 )) && _dbg_unlight "$id"
    done
}

# shifted symbol -> its base key (US layout)
_dbg_unshift() {
    case "$1" in
        '!') _DBG_BASE=1 ;; '@') _DBG_BASE=2 ;; '#') _DBG_BASE=3 ;; '$') _DBG_BASE=4 ;; '%') _DBG_BASE=5 ;;
        '^') _DBG_BASE=6 ;; '&') _DBG_BASE=7 ;; '*') _DBG_BASE=8 ;; '(') _DBG_BASE=9 ;; ')') _DBG_BASE=0 ;;
        '_') _DBG_BASE=- ;; '+') _DBG_BASE== ;; '{') _DBG_BASE='[' ;; '}') _DBG_BASE=']' ;; '|') _DBG_BASE='\' ;;
        ':') _DBG_BASE=';' ;; '"') _DBG_BASE="'" ;; '<') _DBG_BASE=, ;; '>') _DBG_BASE=. ;; '?') _DBG_BASE=/ ;;
        '~') _DBG_BASE='`' ;;
        [A-Z]) _DBG_BASE="${1,,}" ;;
        *) return 1 ;;
    esac
}

_dbg_on_key() {
    local name="$1" mods="" base
    (( _DBG_COUNT++ )); _DBG_LAST="$name"
    if [[ "$name" == move ]]; then _dbg_readout; return; fi
    while [[ "$name" == ctrl+* || "$name" == alt+* || "$name" == shift+* ]]; do
        mods+="${name%%+*} "; name="${name#*+}"
    done
    local m; for m in $mods; do _dbg_light "$m"; done
    case "$name" in
        mouse:*) _dbg_light "m_${name#mouse:}" hold ;;
        drag:*)  _dbg_light m_drag hold; _dbg_light "m_${name#drag:}" hold ;;
        release) _dbg_light m_release; local b; for b in m_left m_middle m_right m_drag; do _dbg_unlight "un_$b"; done ;;
        wheel:*) _dbg_light "m_wheel_${name#wheel:}" ;;
        *)
            if [[ ${#name} -eq 1 ]] && _dbg_unshift "$name"; then
                _dbg_light shift; _dbg_light "$_DBG_BASE"
            else
                _dbg_light "$name"
            fi ;;
    esac
    _dbg_readout
}

_dbg_on_resize() { _dbg_build; tui.relayout; }

dbg_input_visit() {
    _DBG_COUNT=0; _DBG_LAST=""
    _DBG_LIT=()
    _TUI_ON_KEY_EVENT="_dbg_on_key"
    _TUI_ON_RESIZE_FN="_dbg_on_resize"
    _dbg_build
}
