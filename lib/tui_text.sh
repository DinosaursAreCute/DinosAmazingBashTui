#!/usr/bin/env bash
# tui_text.sh - the text-editing engine behind <input>, <password> and <textarea>: cursor, selection, word jumps,
# cut / copy / paste, undo / redo, mouse placement and drag-select. Every text widget keeps its text in
# _TUI_W_VALUE[id] (a plain string; a textarea separates lines with \n) and its editor state in the arrays below,
# so the same code edits one line or many, and tui.get / tui.set / tui.update work as they always did.
#
# KEYS (while a text widget has focus; they beat the default keybinds and lose only to --always binds)
#   move        left right  ctrl+left ctrl+right (word)  home end (line)  ctrl+home ctrl+end (whole text)
#               up down pgup pgdn (textarea; at the first/last line they fall through so focus can leave)
#   select      shift + any move key (arrows, home, end, pgup, pgdn, ctrl+arrows),  ctrl+a (all),  double-click (word),  triple-click (line / all),  mouse drag
#   delete      backspace delete  ctrl+backspace / ctrl+w / alt+backspace (word left)  ctrl+delete / alt+d (word right)
#               ctrl+u (to line start)  ctrl+k (to line end)   - the killed text goes to the clipboard
#   clipboard   copy ctrl+c / ctrl+insert / alt+c   cut ctrl+x / shift+delete / alt+x
#               paste ctrl+v / shift+insert / alt+v (also a terminal paste, which arrives as one event)
#   undo        ctrl+z / alt+z undo, ctrl+y / alt+y redo   (the app runs the tty with -isig, so ctrl+c / ctrl+z are plain keys)
#   enter       inserts a newline in a textarea; submits an input. alt+enter / ctrl+enter submit a textarea.
# The clipboard is TUI_CLIPBOARD (internal) and every copy is also sent to the terminal (OSC 52, tui.clipboard.copy).
#
# API (ID = a text widget)
#   tui.text.selection ID            print the selected text          tui.text.select ID START END   (offsets)
#   tui.text.select_all ID           tui.text.cursor ID -> "ROW COL" (1-based)     tui.text.set_cursor ID OFFSET
#   tui.text.insert ID TEXT          replace the selection / insert at the cursor  tui.text.delete_selection ID
#   tui.text.undo ID | tui.text.redo ID     tui.text.line_count ID
#   tui.on_change ID FN              FN ID runs after every edit
#
# EXTENSION POINT (planned): syntax-aware editing, e.g. Markdown. The draw path paints a visible line at a time
# through _tui_text.paint (a window of text plus a selection range and a cursor column); a per-widget highlighter
# (tui.text.highlighter ID FN, FN LINE -> a list of "START LEN STYLE" spans) would slot in there without touching the
# editor state, and a `mode="markdown"` on <textarea> could switch it on together with a preview (see
# docs/guide/widgets.md, "Roadmap"). Nothing in the engine assumes plain text beyond that one function.

declare -gA _TXC=() _TXA=() _TXS=() _TXT=() _TXW=() _TXH=()       # cursor, anchor(-1), hscroll, top row, wanted column, rows shown
declare -gA _TXUV=() _TXUC=() _TXUN=() _TXRV=() _TXRC=() _TXRN=() _TXLK=() _TXLP=()   # undo / redo
declare -gA _TUI_W_CHANGE=() _TUI_W_MASK=() _TXF=()               # _TXF: 1 = keep the cursor in view on the next draw (0 after a wheel scroll)
declare -g  TUI_CLIPBOARD=""
declare -g  _TX_CLICK_T=0 _TX_CLICK_ID="" _TX_CLICK_POS=-1 _TX_CLICK_N=0 _TX_DRAG=""

# ── small helpers ────────────────────────────────────────────────────────

_tui_text.is_text() { case "${_TUI_W_TYPE[$1]:-}" in input|password|textarea) return 0 ;; esac; return 1; }

# _tui_text.padc TEXT WIDTH -> _PADC : cut / pad by CHARACTERS (printf %-*s pads by bytes, wrong for non-ASCII)
_tui_text.padc() {
    local t="${1:0:$2}" sp
    printf -v sp '%*s' "$(( $2 - ${#t} ))" ''
    _PADC="$t$sp"
}

# clamp cursor / anchor to the current text
_tui_text.norm() {
    local id="$1" n=${#_TUI_W_VALUE[$1]}
    local c=${_TXC[$id]:-0} a=${_TXA[$id]:--1}
    (( c > n )) && c=$n; (( c < 0 )) && c=0
    (( a > n )) && a=$n
    _TXC[$id]=$c; _TXA[$id]=$a
}

# _tui_text.sel ID -> _SA _SB (start,end) ; rc 0 when something is selected
_tui_text.sel() {
    local a=${_TXA[$1]:--1} c=${_TXC[$1]:-0}
    (( a < 0 || a == c )) && { _SA=$c; _SB=$c; return 1; }
    if (( a < c )); then _SA=$a; _SB=$c; else _SA=$c; _SB=$a; fi
    return 0
}

_tui_text.multiline() { [[ "${_TUI_W_TYPE[$1]:-}" == textarea ]]; }

# ── line index ───────────────────────────────────────────────────────────
# Counting newlines with ${v//[!$'\n']/} costs a glob match per character - far too slow for a few KB per keystroke.
# Instead the start offset of every line is computed once per text change and kept for the widget last used.
declare -ga _TXLS=(0)
declare -g  _TXLS_ID="" _TXLS_TEXT=$'\x01'

_tui_text.index() {   # ID -> _TXLS (line start offsets)
    local v="${_TUI_W_VALUE[$1]}"
    [[ "$1" == "$_TXLS_ID" && "$v" == "$_TXLS_TEXT" ]] && return 0
    _TXLS_ID="$1"; _TXLS_TEXT="$v"; _TXLS=()
    local line off=0
    while IFS= read -r line; do _TXLS+=("$off"); (( off += ${#line} + 1 )); done <<< "$v"     # a here-string adds the final newline
}

# _tui_text.rc ID POS -> _ROW _COL (0-based)
_tui_text.rc() {
    _tui_text.index "$1"
    local lo=0 hi=$(( ${#_TXLS[@]} - 1 )) mid
    while (( lo < hi )); do                                   # last line whose start <= POS
        mid=$(( (lo + hi + 1) / 2 ))
        if (( _TXLS[mid] <= $2 )); then lo=$mid; else hi=$(( mid - 1 )); fi
    done
    _ROW=$lo; _COL=$(( $2 - _TXLS[lo] ))
}

# _tui_text.line ID ROW -> _LS _LE _LROW : offsets of that line (clamped to the last line)
_tui_text.line() {
    _tui_text.index "$1"
    local r=$2 n=${#_TXLS[@]}
    (( r >= n )) && r=$(( n - 1 )); (( r < 0 )) && r=0
    _LS=${_TXLS[r]}; _LROW=$r
    if (( r + 1 < n )); then _LE=$(( _TXLS[r+1] - 1 )); else _LE=${#_TUI_W_VALUE[$1]}; fi
}

_tui_text.line_count() { _tui_text.index "$1"; _LC=${#_TXLS[@]}; }

# word helpers: _tui_text.wleft TEXT POS / wright -> _P
_tui_text.wleft() {
    local v="$1" p=$2
    while (( p > 0 )) && [[ "${v:p-1:1}" != [[:alnum:]_] ]]; do (( p-- )); done
    while (( p > 0 )) && [[ "${v:p-1:1}" == [[:alnum:]_] ]]; do (( p-- )); done
    _P=$p
}
_tui_text.wright() {
    local v="$1" p=$2 n=${#1}
    while (( p < n )) && [[ "${v:p:1}" != [[:alnum:]_] ]]; do (( p++ )); done
    while (( p < n )) && [[ "${v:p:1}" == [[:alnum:]_] ]]; do (( p++ )); done
    _P=$p
}

# ── undo / redo ──────────────────────────────────────────────────────────
# A snapshot (text + cursor) is taken before each edit; a run of single-character typing shares one snapshot.
_tui_text.undo_push() {   # ID KIND
    local id="$1" kind="$2" n=${_TXUN[$1]:-0} i
    if [[ "$kind" == type && "${_TXLK[$id]:-}" == type && "${_TXLP[$id]:--1}" == "${_TXC[$id]:-0}" ]]; then return; fi
    if (( n >= 200 )); then
        for (( i = 1; i < n; i++ )); do _TXUV["$id:$((i-1))"]="${_TXUV[$id:$i]}"; _TXUC["$id:$((i-1))"]="${_TXUC[$id:$i]}"; done
        n=199
    fi
    _TXUV["$id:$n"]="${_TUI_W_VALUE[$id]}"; _TXUC["$id:$n"]="${_TXC[$id]:-0}"; _TXUN[$id]=$(( n + 1 ))
    _TXRN[$id]=0                                                     # a new edit forgets the redo stack
    _TXLK[$id]="$kind"
}

tui.text.undo() {
    local id="$1" n=${_TXUN[$1]:-0} r=${_TXRN[$1]:-0}
    (( n > 0 )) || return 1
    _TXRV["$id:$r"]="${_TUI_W_VALUE[$id]}"; _TXRC["$id:$r"]="${_TXC[$id]:-0}"; _TXRN[$id]=$(( r + 1 ))
    (( n-- )); _TXUN[$id]=$n
    _TUI_W_VALUE[$id]="${_TXUV[$id:$n]}"; _TXC[$id]="${_TXUC[$id:$n]}"; _TXA[$id]=-1; _TXLK[$id]=undo
    _tui_text.norm "$id"; _tui_text.changed "$id"
}
tui.text.redo() {
    local id="$1" r=${_TXRN[$1]:-0} n=${_TXUN[$1]:-0}
    (( r > 0 )) || return 1
    _TXUV["$id:$n"]="${_TUI_W_VALUE[$id]}"; _TXUC["$id:$n"]="${_TXC[$id]:-0}"; _TXUN[$id]=$(( n + 1 ))
    (( r-- )); _TXRN[$id]=$r
    _TUI_W_VALUE[$id]="${_TXRV[$id:$r]}"; _TXC[$id]="${_TXRC[$id:$r]}"; _TXA[$id]=-1; _TXLK[$id]=undo
    _tui_text.norm "$id"; _tui_text.changed "$id"
}

_tui_text.changed() {
    local fn="${_TUI_W_CHANGE[$1]:-}"
    [[ -n "$fn" ]] && "$fn" "$1"
    return 0
}

# ── editing primitives ───────────────────────────────────────────────────

# _tui_text.replace ID START END TEXT KIND : the one place text changes
_tui_text.replace() {
    local id="$1" a="$2" b="$3" t="$4" kind="${5:-edit}" v="${_TUI_W_VALUE[$1]}"
    _tui_text.undo_push "$id" "$kind"
    _TUI_W_VALUE[$id]="${v:0:a}${t}${v:b}"
    _TXC[$id]=$(( a + ${#t} )); _TXA[$id]=-1; _TXW[$id]=-1
    _TXLP[$id]=${_TXC[$id]}
    _tui_text.changed "$id"
}

# _tui_text.clean ID TEXT -> _CLEAN : what may be inserted into that widget
_tui_text.clean() {
    local t="$2"
    t="${t//$'\r\n'/$'\n'}"; t="${t//$'\r'/$'\n'}"; t="${t//$'\t'/    }"
    if _tui_text.multiline "$1"; then
        local nl=$'\n'; t="${t//[![:print:]$nl]/}"
    else t="${t//$'\n'/ }"; t="${t//[[:cntrl:]]/}"; fi
    _CLEAN="$t"
}

tui.text.insert() {
    local id="$1"; _tui_text.clean "$id" "$2"
    [[ -n "$_CLEAN" ]] || return 0
    _tui_text.norm "$id"
    local a b
    if _tui_text.sel "$id"; then a=$_SA; b=$_SB; else a=${_TXC[$id]}; b=$a; fi
    _tui_text.replace "$id" "$a" "$b" "$_CLEAN" "${3:-edit}"
}

tui.text.delete_selection() {
    _tui_text.sel "$1" || return 1
    _tui_text.replace "$1" "$_SA" "$_SB" "" del
}

tui.text.selection() { _tui_text.sel "$1" && printf '%s' "${_TUI_W_VALUE[$1]:_SA:_SB-_SA}"; return 0; }
tui.text.select()     { local n=${#_TUI_W_VALUE[$1]}; (( $2 > n )) && set -- "$1" "$n" "$3"; (( $3 > n )) && set -- "$1" "$2" "$n"; _TXA[$1]=$2; _TXC[$1]=$3; _tui_text.redraw "$1"; }
tui.text.select_all() { _TXA[$1]=0; _TXC[$1]=${#_TUI_W_VALUE[$1]}; _tui_text.redraw "$1"; }
tui.text.set_cursor() { _TXC[$1]=$2; _TXA[$1]=-1; _tui_text.norm "$1"; _tui_text.redraw "$1"; }
tui.text.cursor()     { _tui_text.rc "$1" "${_TXC[$1]:-0}"; printf '%s %s\n' $(( _ROW + 1 )) $(( _COL + 1 )); }
tui.text.line_count() { _tui_text.line_count "$1"; printf '%s\n' "$_LC"; }
tui.on_change()       { _TUI_W_CHANGE[$1]="$2"; }

_tui_text.redraw() { _TXF[$1]=1; [[ -n "${_TUI_W_PANE[$1]:-}" ]] && (( _TUI_RUNNING )) && _tui._draw_widget "$1"; return 0; }

# clipboard: internal + terminal (OSC 52)
_tui_text.copy() {
    _tui_text.sel "$1" || return 1
    [[ "${_TUI_W_TYPE[$1]}" == password ]] && return 1                # never leak a password to the clipboard
    TUI_CLIPBOARD="${_TUI_W_VALUE[$1]:_SA:_SB-_SA}"
    tui.clipboard.copy "$TUI_CLIPBOARD"
}
_tui_text.cut() {
    _tui_text.copy "$1" || return 1
    _tui_text.replace "$1" "$_SA" "$_SB" "" cut
}
_tui_text.paste() {
    local t="${TUI_CLIPBOARD:-$TUI_LAST_PASTE}"
    [[ -n "$t" ]] && tui.text.insert "$1" "$t" paste
}

# ── movement ─────────────────────────────────────────────────────────────

# _tui_text.move ID KIND EXTEND(0|1)
_tui_text.move() {
    local id="$1" kind="$2" ext="$3" v="${_TUI_W_VALUE[$1]}" c=${_TXC[$1]:-0} p n=${#_TUI_W_VALUE[$1]}
    local a=${_TXA[$id]:--1} had=0 lo hi ml=0
    _tui_text.multiline "$id" && ml=1
    _tui_text.sel "$id" && { had=1; lo=$_SA; hi=$_SB; }
    (( ext )) && (( a < 0 )) && _TXA[$id]=$c
    p=$c
    case "$kind" in
        left)  if (( had && ! ext )); then p=$lo; else (( p > 0 )) && (( p-- )); fi ;;
        right) if (( had && ! ext )); then p=$hi; else (( p < n )) && (( p++ )); fi ;;
        wleft)  _tui_text.wleft "$v" "$c"; p=$_P ;;
        wright) _tui_text.wright "$v" "$c"; p=$_P ;;
        home)  if (( ml )); then _tui_text.rc "$id" "$c"; p=$(( c - _COL )); else p=0; fi ;;
        end)   if (( ml )); then _tui_text.rc "$id" "$c"; _tui_text.line "$id" "$_ROW"; p=$_LE; else p=$n; fi ;;
        docstart) p=0 ;;
        docend)   p=$n ;;
        pup|pdown)                                              # previous / next empty line
            (( ml )) || { [[ "$kind" == pup ]] && p=0 || p=$n; }
            if (( ml )); then
                _tui_text.rc "$id" "$c"; local r=$_ROW last; _tui_text.line_count "$id"; last=$(( _LC - 1 ))
                if [[ "$kind" == pdown ]]; then
                    while (( r < last )); do _tui_text.blank "$id" "$r" && (( r++ )) || break; done
                    while (( r < last )); do _tui_text.blank "$id" "$r" && break; (( r++ )); done
                    _tui_text.line "$id" "$r"; if _tui_text.blank "$id" "$r"; then p=$_LS; else p=$_LE; fi
                else
                    while (( r > 0 )); do _tui_text.blank "$id" "$r" && (( r-- )) || break; done
                    while (( r > 0 )); do _tui_text.blank "$id" "$r" && break; (( r-- )); done
                    _tui_text.line "$id" "$r"; p=$_LS
                fi
            fi ;;
        up|down|pgup|pgdn)
            (( ml )) || return 0
            _tui_text.rc "$id" "$c"
            local row=$_ROW col=$_COL want=${_TXW[$id]:--1} step=1 target
            (( want < 0 )) && want=$col
            [[ "$kind" == pgup || "$kind" == pgdn ]] && step=$(( ${_TXH[$id]:-10} - 1 )); (( step < 1 )) && step=1
            [[ "$kind" == up || "$kind" == pgup ]] && target=$(( row - step )) || target=$(( row + step ))
            _tui_text.line_count "$id"
            (( target < 0 )) && target=0; (( target >= _LC )) && target=$(( _LC - 1 ))
            _tui_text.line "$id" "$target"
            p=$(( _LS + want )); (( p > _LE )) && p=$_LE
            _TXC[$id]=$p
            (( ext )) || _TXA[$id]=-1
            _TXW[$id]=$want; _TXLK[$id]=move
            return 0 ;;
    esac
    _TXC[$id]=$p; _TXW[$id]=-1; _TXLK[$id]=move
    (( ext )) || _TXA[$id]=-1
}

# does the key move the cursor of a textarea off its first / last line? (else it falls through to focus movement)
_tui_text.can_vmove() {   # ID up|down
    _tui_text.rc "$1" "${_TXC[$1]:-0}"
    if [[ "$2" == up ]]; then (( _ROW > 0 )); else _tui_text.line_count "$1"; (( _ROW < _LC - 1 )); fi
}

# a line with nothing (or only spaces) on it
_tui_text.blank() {
    _tui_text.line "$1" "$2"
    local t="${_TUI_W_VALUE[$1]:_LS:_LE-_LS}"
    [[ -z "${t//[[:space:]]/}" ]]
}

# ── keys ─────────────────────────────────────────────────────────────────

# _tui_text.consumes ID NAME : rc 0 when the focused text widget wants that key
_tui_text.consumes() {
    local id="$1" name="$2" ml=0
    _tui_text.multiline "$id" && ml=1
    case "$name" in
        [[:print:]]|space|backspace|delete|left|right|home|end) return 0 ;;
        ctrl+left|ctrl+right|shift+left|shift+right|shift+home|shift+end|ctrl+shift+left|ctrl+shift+right) return 0 ;;
        alt+shift+left|alt+shift+right) return 0 ;;                # same as ctrl+shift+arrows, for terminals that keep those chords
        ctrl+home|ctrl+end|ctrl+shift+home|ctrl+shift+end|ctrl+a|ctrl+u|ctrl+k|ctrl+w|ctrl+backspace|ctrl+delete) return 0 ;;
        alt+backspace|alt+d|alt+c|alt+x|alt+v|alt+z|alt+y|ctrl+x|ctrl+v|ctrl+insert|shift+insert|shift+delete) return 0 ;;
        ctrl+c|ctrl+z|ctrl+y) return 0 ;;                        # the tty no longer eats these (-isig), so they are ours
        enter)  (( ml )); return ;;
        shift+up|shift+down|shift+pgup|shift+pgdn|ctrl+up|ctrl+down|ctrl+shift+up|ctrl+shift+down|alt+shift+up|alt+shift+down) (( ml )); return ;;
        up)   (( ml )) && _tui_text.can_vmove "$id" up; return ;;
        down) (( ml )) && _tui_text.can_vmove "$id" down; return ;;
        pgup|pgdn) (( ml )); return ;;
    esac
    return 1
}

# _tui_text.key ID NAME : apply the key (call only when consumes said yes)
_tui_text.key() {
    local id="$1" name="$2" c v n
    _tui_text.multiline "$id" && _tui_text.geom "$id"
    _tui_text.norm "$id"
    c=${_TXC[$id]}; v="${_TUI_W_VALUE[$id]}"; n=${#v}
    case "$name" in
        left|right|home|end|up|down|pgup|pgdn) _tui_text.move "$id" "$name" 0 ;;
        shift+left)  _tui_text.move "$id" left 1 ;;
        shift+right) _tui_text.move "$id" right 1 ;;
        shift+home)  _tui_text.move "$id" home 1 ;;
        shift+end)   _tui_text.move "$id" end 1 ;;
        shift+up|shift+down|shift+pgup|shift+pgdn) _tui_text.move "$id" "${name#shift+}" 1 ;;
        ctrl+up)     _tui_text.move "$id" pup 0 ;;
        ctrl+down)   _tui_text.move "$id" pdown 0 ;;
        ctrl+shift+up|alt+shift+up)     _tui_text.move "$id" pup 1 ;;
        ctrl+shift+down|alt+shift+down) _tui_text.move "$id" pdown 1 ;;
        ctrl+left)   _tui_text.move "$id" wleft 0 ;;
        ctrl+right)  _tui_text.move "$id" wright 0 ;;
        ctrl+shift+left|alt+shift+left)   _tui_text.move "$id" wleft 1 ;;
        ctrl+shift+right|alt+shift+right) _tui_text.move "$id" wright 1 ;;
        ctrl+home)   _tui_text.move "$id" docstart 0 ;;
        ctrl+end)    _tui_text.move "$id" docend 0 ;;
        ctrl+shift+home) _tui_text.move "$id" docstart 1 ;;
        ctrl+shift+end)  _tui_text.move "$id" docend 1 ;;
        ctrl+a)      _TXA[$id]=0; _TXC[$id]=$n ;;
        backspace)
            if _tui_text.sel "$id"; then tui.text.delete_selection "$id"
            elif (( c > 0 )); then _tui_text.replace "$id" $(( c - 1 )) "$c" "" del; fi ;;
        delete)
            if _tui_text.sel "$id"; then tui.text.delete_selection "$id"
            elif (( c < n )); then _tui_text.replace "$id" "$c" $(( c + 1 )) "" del; fi ;;
        ctrl+backspace|ctrl+w|alt+backspace)
            if _tui_text.sel "$id"; then tui.text.delete_selection "$id"
            else _tui_text.wleft "$v" "$c"; (( _P < c )) && _tui_text.replace "$id" "$_P" "$c" "" del; fi ;;
        ctrl+delete|alt+d)
            if _tui_text.sel "$id"; then tui.text.delete_selection "$id"
            else _tui_text.wright "$v" "$c"; (( _P > c )) && _tui_text.replace "$id" "$c" "$_P" "" del; fi ;;
        ctrl+u)      # to the start of the line (killed text -> clipboard)
            _tui_text.rc "$id" "$c"
            if (( _COL > 0 )); then TUI_CLIPBOARD="${v:c-_COL:_COL}"; _tui_text.replace "$id" $(( c - _COL )) "$c" "" del; fi ;;
        ctrl+k)      # to the end of the line (or the newline itself when already there)
            _tui_text.rc "$id" "$c"; _tui_text.line "$id" "$_ROW"
            if (( c < _LE )); then TUI_CLIPBOARD="${v:c:_LE-c}"; _tui_text.replace "$id" "$c" "$_LE" "" del
            elif (( c < n )); then _tui_text.replace "$id" "$c" $(( c + 1 )) "" del; fi ;;
        ctrl+c|ctrl+insert|alt+c) _tui_text.copy "$id" ;;             # ctrl+c with nothing selected does nothing
        ctrl+x|shift+delete|alt+x) _tui_text.cut "$id" ;;
        ctrl+v|shift+insert|alt+v) _tui_text.paste "$id" ;;
        alt+z|ctrl+z) tui.text.undo "$id" ;;
        alt+y|ctrl+y) tui.text.redo "$id" ;;
        paste) tui.text.insert "$id" "$TUI_EVENT_PASTE" paste ;;
        enter) tui.text.insert "$id" $'\n' edit ;;
        space) tui.text.insert "$id" " " type ;;
        *)     (( ${#name} == 1 )) && tui.text.insert "$id" "$name" type ;;
    esac
    _tui_text.redraw "$id"
    return 0
}

# ── mouse ────────────────────────────────────────────────────────────────

# _tui_text.geom ID : where the widget is RIGHT NOW (recomputed from the layout, because full renders draw inside a
# subshell and cannot leave their geometry behind)
_tui_text.geom() {
    local id="$1" plen=0 prefix="${_TUI_W_LABEL[$1]:-}" fw
    _tui._widget_pos "$id"
    if [[ "${_TUI_W_TYPE[$id]}" != textarea && -n "$prefix" ]]; then plen="${_TUI_W_LABEL_WIDTH[$id]:-$(( ${#prefix} + 1 ))}"; (( plen < 1 )) && plen=1; fi
    fw=$(( _WSW - plen ))
    if [[ "${_TUI_W_TYPE[$id]}" == textarea ]]; then
        _tui_text.line_count "$id"; (( _LC > _WSH && fw > 2 )) && (( fw-- ))
        _TXH[$id]=$_WSH
    fi
    _TXG_R[$id]=$_WSR; _TXG_C[$id]=$(( _WSC + plen )); _TXG_W[$id]=$fw; _TXG_H[$id]=$_WSH
}

# _tui_text.hit ID X Y -> _POS : text offset under an absolute cell (uses the geometry the last draw stored)
declare -gA _TXG_R=() _TXG_C=() _TXG_W=() _TXG_H=()               # field origin row/col, width, rows of the last draw
_tui_text.hit() {
    local id="$1" x="$2" y="$3" v="${_TUI_W_VALUE[$1]}" col row
    _tui_text.geom "$id"
    col=$(( x - ${_TXG_C[$id]:-1} + ${_TXS[$id]:-0} ))
    (( col < 0 )) && col=0
    if _tui_text.multiline "$id"; then
        local top=${_TXT[$id]:-0}
        _tui_text.line_count "$id"; (( top > _LC - ${_TXG_H[$id]:-1} )) && top=$(( _LC - ${_TXG_H[$id]:-1} )); (( top < 0 )) && top=0     # the text may have shrunk since the last draw
        row=$(( y - ${_TXG_R[$id]:-1} + top ))
        (( row < 0 )) && row=0
        _tui_text.line "$id" "$row"
        _POS=$(( _LS + col )); (( _POS > _LE )) && _POS=$_LE
    else
        _POS=$col; (( _POS > ${#v} )) && _POS=${#v}
    fi
}

# a press: place the cursor, or select a word (double click) / line (triple click)
_tui_text.press() {   # ID X Y
    local id="$1" now=${EPOCHREALTIME//[.,]/} v="${_TUI_W_VALUE[$1]}"
    now=$(( now / 1000 ))
    _tui_text.hit "$id" "$2" "$3"
    local pos=$_POS
    if [[ "$_TX_CLICK_ID" == "$id" ]] && (( now - _TX_CLICK_T < 450 )) && (( pos - _TX_CLICK_POS <= 1 && _TX_CLICK_POS - pos <= 1 )); then
        (( _TX_CLICK_N++ ))
    else _TX_CLICK_N=1; fi
    _TX_CLICK_T=$now; _TX_CLICK_ID="$id"; _TX_CLICK_POS=$pos
    case $(( _TX_CLICK_N > 3 ? 3 : _TX_CLICK_N )) in
        1) _TXC[$id]=$pos; _TXA[$id]=-1; _TX_DRAG="$id" ;;
        2) _tui_text.wleft "$v" $(( pos < ${#v} ? pos + 1 : pos )); local s=$_P
           _tui_text.wright "$v" "$s"; _TXA[$id]=$s; _TXC[$id]=$_P; _TX_DRAG="" ;;
        3) if _tui_text.multiline "$id"; then
               _tui_text.rc "$id" "$pos"; _tui_text.line "$id" "$_ROW"; _TXA[$id]=$_LS; _TXC[$id]=$_LE
           else _TXA[$id]=0; _TXC[$id]=${#v}; fi
           _TX_DRAG="" ;;
    esac
    _TXW[$id]=-1
    _tui_text.redraw "$id"
}

_tui_text.drag() {    # ID X Y
    local id="$1"
    [[ "$_TX_DRAG" == "$id" ]] || return 1
    _tui_text.hit "$id" "$2" "$3"
    [[ ${_TXA[$id]:--1} -lt 0 ]] && _TXA[$id]=${_TXC[$id]}
    if _tui_text.multiline "$id"; then                              # dragging past the top / bottom scrolls
        local h=${_TXH[$id]:-1} r0=${_TXG_R[$id]:-1}
        if (( $3 < r0 )); then (( ${_TXT[$id]:-0} > 0 )) && (( _TXT[$id]-- )); _tui_text.hit "$id" "$2" "$r0"
        elif (( $3 >= r0 + h )); then (( _TXT[$id]++ )); _tui_text.hit "$id" "$2" $(( r0 + h - 1 )); fi
    fi
    _TXC[$id]=$_POS
    _tui_text.redraw "$id"
}

# ── focus ────────────────────────────────────────────────────────────────
_tui_text.on_focus() {
    local id="$1"
    if [[ "${_TUI_W_TYPE[$id]}" == textarea ]]; then _TXC[$id]=${_TXC[$id]:-0}
    else _TXC[$id]=${#_TUI_W_VALUE[$id]}; fi
    _TXA[$id]=-1
    _tui_text.norm "$id"
}

# ── drawing ──────────────────────────────────────────────────────────────

declare -g _TX_SGR_SEL="" _TX_SGR_SEL_AT=-1
_tui_text.sel_style() {
    (( _TX_SGR_SEL_AT == _TUI_BIND_GEN )) && [[ -n "$_TX_SGR_SEL" ]] && return
    tui.class.sgr selection
    _TX_SGR_SEL="${TUI_SGR:-$'\e[0;97;48;2;62;92;138m'}"; _TX_SGR_SEL_AT=$_TUI_BIND_GEN
}

# _tui_text.paint_v WINDOW SELA SELB CURCOL FW BASE_SGR -> _PV : one line of a text widget, padded to FW.
#   WINDOW = the visible slice; SELA..SELB = highlighted range inside it (SELA<0: none); CURCOL = cursor cell (-1: none)
_tui_text.paint_v() {
    local w="$1" a=$2 b=$3 cur=$4 fw=$5 base="$6" pad
    local len=${#w}
    printf -v pad '%*s' "$(( fw > len ? fw - len : 0 ))" ''
    w+="$pad"
    if (( a >= 0 && b > a )); then
        _tui_text.sel_style
        _PV="${w:0:a}${_TX_SGR_SEL}${w:a:b-a}"$'\e[0m'"${base}${w:b:fw-b}"
    elif (( cur >= 0 && cur < fw )); then
        _PV="${w:0:cur}"$'\e[7m'"${w:cur:1}"$'\e[27m'"${base}${w:cur+1:fw-cur-1}"
    else _PV="${w:0:fw}"; fi
}
_tui_text.paint() { _tui_text.paint_v "$@"; printf '%s' "$_PV"; }

# single-line input / password
_tui_text.draw_line() {   # ID SR SC SW FOCUSED STYLE_KEY PANE_KEY
    local id="$1" sr="$2" sc="$3" sw="$4" focused="$5" style_key="$6" pane_key="$7"
    local prefix="${_TUI_W_LABEL[$id]:-}" value="${_TUI_W_VALUE[$id]}" placeholder="${_TUI_W_PH[$id]:-}" plen=0 fw
    if [[ -n "$prefix" ]]; then
        local lbox="${_TUI_W_LABEL_WIDTH[$id]:-$(( ${#prefix} + 1 ))}" lshown lpad
        (( lbox < 1 )) && lbox=1
        lshown="${prefix:0:$lbox}"
        _tui._align_pad_v "${_TUI_W_LABEL_ALIGN[$id]:-left}" "${#lshown}" "$lbox"; lpad=$_R
        style.bold
        printf '%*s%s%*s' "$lpad" "" "$lshown" "$(( lbox - lpad - ${#lshown} ))" ""
        style.reset
        plen=$lbox
    fi
    fw=$(( sw - plen )); (( fw < 2 )) && fw=2
    local shown="$value"
    [[ "${_TUI_W_TYPE[$id]}" == password ]] && shown="${value//?/•}"
    _tui._apply_style "$style_key" "$pane_key"
    _TXG_R[$id]=$sr; _TXG_C[$id]=$(( sc + plen )); _TXG_W[$id]=$fw; _TXG_H[$id]=1
    if (( focused )); then
        _tui_text.norm "$id"
        local c=${_TXC[$id]} s=${_TXS[$id]:-0}
        (( c < s )) && s=$c
        (( c >= s + fw )) && s=$(( c - fw + 1 ))
        (( s < 0 )) && s=0
        _TXS[$id]=$s
        _tui._style_v "$style_key" "$pane_key"; local base="$_SGR"$'\e[4m'
        local a=-1 b=-1 cc=$(( c - s ))
        if _tui_text.sel "$id"; then a=$(( _SA - s )); b=$(( _SB - s )); (( a < 0 )) && a=0; (( b > fw )) && b=$fw; fi
        style.underline
        _tui_text.paint "${shown:s:fw}" "$a" "$b" "$cc" "$fw" "$base"
    else
        [[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && style.dim
        _TXS[$id]=0
        local t="${shown:-$placeholder}" pad
        t="${t:0:fw}"
        _tui._widget_align_v "$id"; _tui._align_pad_v "$_R" "${#t}" "$fw"; pad=$_R
        printf '%*s' "$pad" ""
        _tui_text.padc "$t" "$(( fw - pad ))"; printf '%s' "$_PADC"
    fi
    style.reset
}

# multi-line textarea: fills its rows, scrolls, highlights the selection, shows the cursor
_tui_text.draw_area() {   # ID SR SC SW SH FOCUSED STYLE_KEY PANE_KEY
    local id="$1" sr="$2" sc="$3" sw="$4" sh="$5" focused="$6" style_key="$7" pane_key="$8"
    local fw=$sw i
    (( sh < 1 )) && sh=1
    _tui_text.line_count "$id"; local lc=$_LC
    (( lc > sh && fw > 2 )) && fw=$(( sw - 1 ))                        # the last column is the scroll indicator
    _TXG_R[$id]=$sr; _TXG_C[$id]=$sc; _TXG_W[$id]=$fw; _TXG_H[$id]=$sh; _TXH[$id]=$sh
    _tui_text.norm "$id"
    local v="${_TUI_W_VALUE[$id]}" c=${_TXC[$id]} top=${_TXT[$id]:-0} left=${_TXS[$id]:-0}
    _tui_text.rc "$id" "$c"; local crow=$_ROW ccol=$_COL
    if (( ${_TXF[$id]:-1} )); then                                     # keep the cursor in view (not after a wheel scroll)
        (( crow < top )) && top=$crow
        (( crow >= top + sh )) && top=$(( crow - sh + 1 ))
        (( ccol < left )) && left=$ccol
        (( ccol >= left + fw )) && left=$(( ccol - fw + 1 ))
    fi
    (( top > lc - sh )) && top=$(( lc - sh )); (( top < 0 )) && top=0        # never scroll past the end
    (( left < 0 )) && left=0
    _TXT[$id]=$top; _TXS[$id]=$left

    local -a VL=() VS=()
    _tui_text.index "$id"
    for (( i = top; i < top + sh && i < lc; i++ )); do
        VS+=("${_TXLS[i]}")
        if (( i + 1 < lc )); then VL+=("${v:_TXLS[i]:_TXLS[i+1]-1-_TXLS[i]}"); else VL+=("${v:_TXLS[i]}"); fi
    done

    _tui._apply_style "$style_key" "$pane_key"
    _tui._style_v "$style_key" "$pane_key"; local base="$_SGR"
    local sa=-1 sb=-1 hasel=0
    _tui_text.sel "$id" && { hasel=1; sa=$_SA; sb=$_SB; }
    local placeholder="${_TUI_W_PH[$id]:-}"
    for (( i = 0; i < sh; i++ )); do
        cur.goto $(( sr + i )) "$sc"
        if (( i < ${#VL[@]} )); then
            local t="${VL[i]}" ls=${VS[i]} le a=-1 b=-1 cc=-1
            le=$(( ls + ${#t} ))
            if (( hasel && sb > ls && sa <= le )); then                # this line intersects the selection
                a=$(( (sa > ls ? sa : ls) - ls - left )); b=$(( (sb < le ? sb : le) - ls - left ))
                (( sb > le )) && (( b++ ))                             # the selected newline shows as one extra cell
                (( a < 0 )) && a=0; (( b > fw )) && b=$fw
            fi
            (( focused && ! hasel && top + i == crow )) && cc=$(( ccol - left ))
            (( focused )) || { a=-1; cc=-1; }
            _tui_text.paint "${t:left:fw}" "$a" "$b" "$cc" "$fw" "$base"
        elif (( i == 0 && ${#v} == 0 && ! focused )) && [[ -n "$placeholder" ]]; then
            style.dim; _tui_text.padc "$placeholder" "$fw"; printf '%s' "$_PADC"; style.reset; _tui._apply_style "$style_key" "$pane_key"
        else
            printf '%*s' "$fw" ""
        fi
        # scroll indicator in the last column
        if (( lc > sh && sw > fw )); then
            local thumb=$(( top * (sh - 1) / (lc - sh > 0 ? lc - sh : 1) ))
            cur.goto $(( sr + i )) $(( sc + fw ))
            (( i == thumb )) && printf '▐' || printf ' '
        fi
    done
    style.reset
}


# ── help: every text-editing key, as data (shown by tui.action.text_keys / the command bar / f1) ─────────────
declare -ga TUI_TEXT_KEYS=(
    "Move|left  right|one character"
    "Move|ctrl+left  ctrl+right|previous / next word"
    "Move|home  end|start / end of the line"
    "Move|ctrl+home  ctrl+end|start / end of the text"
    "Move|up  down  pgup  pgdn|lines / pages (textarea)"
    "Move|ctrl+up  ctrl+down|previous / next empty line (textarea)"
    "Select|shift + any move key|extend the selection"
    "Select|ctrl+shift+left  ctrl+shift+right|select to the previous / next word"
    "Select|ctrl+shift+up  ctrl+shift+down|select up to the previous / next empty line"
    "Select|alt+shift+arrows|the same, for terminals that keep ctrl+shift+arrows"
    "Select|shift+home  shift+end|select to the start / end of the line"
    "Select|shift+pgup  shift+pgdn|select a page up / down"
    "Select|ctrl+a|select all"
    "Select|mouse drag|select with the mouse"
    "Select|double-click  triple-click|select a word / a line"
    "Cursor|click|place the cursor"
    "Delete|backspace  delete|one character"
    "Delete|ctrl+backspace  ctrl+w  alt+backspace|word to the left"
    "Delete|ctrl+delete  alt+d|word to the right"
    "Delete|ctrl+u  ctrl+k|to the start / end of the line (goes to the clipboard)"
    "Clipboard|ctrl+c  ctrl+insert  alt+c|copy"
    "Clipboard|ctrl+x  shift+delete  alt+x|cut"
    "Clipboard|ctrl+v  shift+insert  alt+v|paste (a terminal paste works too)"
    "History|ctrl+z  alt+z|undo"
    "History|ctrl+y  alt+y|redo"
    "Lines|enter|new line (textarea) / submit (input)"
    "Lines|alt+enter  ctrl+enter|submit a textarea"
    "Panes|alt+arrows|scroll a scrollable pane (else move to the next pane)"
    "Panes|mouse wheel|scroll the box, or the pane when the box cannot scroll"
    "Help|f1|this list"
)

# tui.action.text_keys : a scrollable list of every text-editing key. Register your own with tui.cmd.add.
tui.action.text_keys() {
    local row grp keys what last="" text=""
    for row in "${TUI_TEXT_KEYS[@]}"; do
        IFS='|' read -r grp keys what <<< "$row"
        [[ "$grp" != "$last" ]] && { [[ -n "$last" ]] && text+=$'\n'; text+="$grp"$'\n'; last="$grp"; }
        printf -v row '  %-42s %s' "$keys" "$what"
        text+="$row"$'\n'
    done
    tui.view "Text editing keys" "${text%$'\n'}"
}
