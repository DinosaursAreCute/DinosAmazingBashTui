#!/usr/bin/env bash
# widget_tests.sh [OUTDIR] [ROWSxCOLS] - headless test of the text engine and the richer widgets: feeds real key sequences /
# mouse events through the input layer, checks the results, and dumps frames (OUTDIR/*.ans). Exit status = failures.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; DIR="$ROOT/lib"; OUT="${1:-/tmp/dabt_widgets}"; SIZE="${2:-34x100}"
ROWS="${SIZE%x*}"; COLS="${SIZE#*x}"; mkdir -p "$OUT"
export XDG_CONFIG_HOME="$(mktemp -d)"; trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
stty() { [[ "$1" == size ]] && echo "$ROWS $COLS"; }
cd "$DIR" && source ./tui.sh
_TUI_ROWS=$ROWS; _TUI_COLS=$COLS; _TUI_P_ROW[root]=1; _TUI_P_COL[root]=1; _TUI_P_W[root]=$COLS; _tui._root_h
FAIL=0; N=0
exec 3>&1 1>/dev/null                                                  # drawing goes to /dev/null; results to fd 3
ok() { (( N++ )); if [[ "$2" == "$3" ]]; then :; else (( FAIL++ )); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "${2//$'\n'/\\n}" "${3//$'\n'/\\n}" >&3; fi; }
# key helpers: raw bytes exactly as a terminal sends them
K()  { _tui_input.key_event "$1" "" >/dev/null; }                 # a character
S()  { _tui_input.key_event "" "$1" >/dev/null; }                 # an escape sequence (bytes after ESC)
T()  { local i; for (( i = 0; i < ${#1}; i++ )); do K "${1:i:1}"; done; }
CL="[1;5D"; CR="[1;5C"; SL="[1;2D"; SR="[1;2C"; CSL="[1;6D"; CSR="[1;6C"; UP="[A"; DN="[B"; LT="[D"; RT="[C"; HOME="[H"; END="[F"; DEL="[3~"
CHOME="[1;5H"; CEND="[1;5F"; SHOME="[1;2H"; SEND="[1;2F"; SUP="[1;2A"; SDN="[1;2B"; CINS="[2;5~"; SINS="[2;2~"; SDEL="[3;2~"

tui.vsplit root left:1 right:1 >/dev/null 2>&1
tui.pane_border left single; tui.pane_border right single
tui.input   in1  left 0 "type here" "Name:"
tui.password pw1 left 2 "secret" "Pass:"
tui.textarea ta1 right 0 "notes..." 8
tui.list    li1  left 4 "" 5;   tui.list.set li1 alpha beta gamma delta epsilon zeta eta theta
tui.table   tb1  left 10 "" 5;  tui.table.set tb1 "Name|Size|Type" "readme.md|1.2k|text" "run.sh|300|script" "photo.png|48k|image"
tui.select  se1  right 10 "Mode:"; tui.select.set se1 fast balanced careful; tui.set se1 balanced
tui.progress pr1 right 12 "Load:"; tui.set pr1 40
_TUI_RUNNING=1
tui.render >/dev/null

# ── single-line editing ──
tui.focus in1; T "hello world"
ok "typed"            "$(tui.get in1)" "hello world"
S "$CL"; S "$CL";  T "big "                                       # ctrl+left twice then insert
ok "ctrl+left"        "$(tui.get in1)" "big hello world"
S "$SR"; S "$SR"; S "$SR"                                          # shift+right x3 selects 'hel'
ok "shift+right sel"  "$(tui.text.selection in1)" "hel"
T "J"
ok "typing replaces selection" "$(tui.get in1)" "big Jlo world"
S "$END"; S "$CSL"                                                 # ctrl+shift+left selects last word
ok "ctrl+shift+left"  "$(tui.text.selection in1)" "world"
S "$CINS"                                                          # copy
S "$HOME"; S "$SINS"                                               # paste at start
ok "copy/paste"       "$(tui.get in1)" "worldbig Jlo world"
S "$END"; K $'\b'                                                  # ctrl+backspace deletes the word
ok "ctrl+backspace"   "$(tui.get in1)" "worldbig Jlo "
K $'\x01'; ok "ctrl+a selects all" "$(tui.text.selection in1)" "worldbig Jlo "
S "$SDEL"                                                          # shift+delete = cut
ok "cut"              "$(tui.get in1)|$TUI_CLIPBOARD" "|worldbig Jlo "
K $'\x1a'                                                         # ctrl+z undo
ok "undo"             "$(tui.get in1)" "worldbig Jlo "
K $'\x19'; ok "redo (ctrl+y)" "$(tui.get in1)" ""
K $'\x01'; TUI_CLIPBOARD=""; K $'\x03'; ok "ctrl+c copies (empty text: nothing)" "$TUI_CLIPBOARD" ""
tui.set in1 "copy me"; _TXC[in1]=7; K $'\x01'; K $'\x03'; ok "ctrl+c copies the selection" "$TUI_CLIPBOARD" "copy me"
# ── password ──
TUI_CLIPBOARD="worldbig Jlo "
tui.focus pw1; T "s3cret"
ok "password value"   "$(tui.get pw1)" "s3cret"
K $'\x01'; S "$SINS"; ok "password: ctrl+a then paste replaces" "$(tui.get pw1)" "worldbig Jlo "
K $'\x01'; S "$CINS"; ok "password: copy refused" "$TUI_CLIPBOARD" "worldbig Jlo "
# ── textarea ──
tui.focus ta1; T "line one"; K $'\r'; T "second line"; K $'\r'; T "third"
ok "textarea newlines" "$(tui.get ta1)" $'line one\nsecond line\nthird'
ok "cursor row/col"    "$(tui.text.cursor ta1)" "3 6"
S "$UP"; ok "up keeps column" "$(tui.text.cursor ta1)" "2 6"
S "$HOME"; ok "home = line start" "$(tui.text.cursor ta1)" "2 1"
S "$SDN"; S "$SEND"; ok "shift+down then shift+end selects to end of line 3" "$(tui.text.selection ta1)" $'second line\nthird'
T "X"; ok "replace multi-line selection" "$(tui.get ta1)" $'line one\nX'
S "$CHOME"; ok "ctrl+home" "$(tui.text.cursor ta1)" "1 1"
S "$UP"; ok "up on first line falls through to focus movement (focus changed or unchanged, text intact)" "$(tui.get ta1)" $'line one\nX'
tui.focus ta1
S "$CEND"; K $'\r'; T "tail"; ok "ctrl+end + enter" "$(tui.text.cursor ta1)" "3 5"
S "$CL"; ok "ctrl+left" "$(tui.text.cursor ta1)" "3 1"
K $'\x0b'; ok "ctrl+k kills to end of line" "${_TUI_W_VALUE[ta1]}|$TUI_CLIPBOARD" $'line one\nX\n|tail'
tui.set ta1 $'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\nl12'; tui.focus ta1; tui.render >/dev/null; S "$CHOME"
S "[6;2~"; ok "shift+pgdn selects a page down" "$(tui.text.cursor ta1)" "8 1"
S "$SEND"; S "[5;2~"; ok "shift+pgup goes a page up, keeping the column" "$(tui.text.cursor ta1)" "1 3"
# paragraph moves and selection
tui.set ta1 $'a\nb\n\nc\nd\n\ne'; tui.focus ta1; tui.render >/dev/null; S "$CHOME"
CUP="[1;5A"; CDN="[1;5B"; CSUP="[1;6A"; CSDN="[1;6B"
SEL() { _tui_text.sel "$1"; SELV="${_TUI_W_VALUE[$1]:_SA:_SB-_SA}"; }
S "$CDN"; ok "ctrl+down: next empty line" "$(tui.text.cursor ta1)" "3 1"
S "$CDN"; ok "ctrl+down again: the one after" "$(tui.text.cursor ta1)" "6 1"
S "$CUP"; ok "ctrl+up: previous empty line" "$(tui.text.cursor ta1)" "3 1"
S "$CHOME"; S "$CSDN"; SEL ta1; ok "ctrl+shift+down selects to the empty line" "$SELV" $'a\nb\n'
S "$CSDN"; SEL ta1; ok "and on to the next one" "$SELV" $'a\nb\n\nc\nd\n'
S "$CSL"; SEL ta1; ok "ctrl+shift+left selects back a word" "$SELV" $'a\nb\n\nc\n'
ASL="[1;4D"; ASR="[1;4C"
tui.set ta1 "one two three"; tui.focus ta1; S "$CHOME"; S "$ASR"; SEL ta1; ok "alt+shift+right selects a word" "$SELV" "one"
S "$ASR"; SEL ta1; ok "and the next" "$SELV" "one two"
_tui_input.name_seq "Od"; ok "rxvt ctrl+left" "$_KEY" "ctrl+left"; _tui_input.name_seq "[d"; ok "rxvt shift+left" "$_KEY" "shift+left"
# scrolling: alt+arrows scroll a scrollable pane, else they move between panes
tui.pane_scroll left both; _TUI_P_LINES[left]=200; _TUI_P_MAX_W[left]=300; _TUI_P_SOFF_V[left]=0; _TUI_P_SOFF_H[left]=0
tui.focus in1; TUI_EVENT_TYPE=key; tui.action.scroll_or_pane down; tui.action.scroll_or_pane right
ok "alt+down / alt+right scroll a scrollable pane" "${_TUI_P_SOFF_V[left]} ${_TUI_P_SOFF_H[left]}" "3 5"
tui.pane_scroll left none
# the wheel over a textarea that cannot scroll falls through (rc 1), one that can scrolls itself
tui.set ta1 "short"; TUI_EVENT_TYPE=mouse; TUI_EVENT_WIDGET=ta1; TUI_EVENT_COUNT=1
_tui_wx.wheel down 3; ok "wheel on a textarea with nothing to scroll -> pane" "$?" "1"
tui.set ta1 "$(seq 1 40)"; tui.render >/dev/null; _tui_wx.wheel down 3; ok "wheel scrolls a long textarea" "$?|${_TXT[ta1]}" "0|3"
tui.render >/dev/null; ok "the scroll position survives a redraw" "${_TXT[ta1]}" "3"
TUI_EVENT_TYPE=key; TUI_EVENT_WIDGET=""
# help
tui.action.text_keys; ok "text keys viewer opens" "$(tui.dialog.active && echo yes)" "yes"; tui.render > "$OUT/textkeys.ans"; _tui_dialog.key esc
# ── mouse: click places the cursor, drag selects, double-click selects a word ──
tui.set ta1 $'alpha beta gamma\nsecond row here'; tui.focus ta1; tui.render >/dev/null
R0=${_TXG_R[ta1]}; C0=${_TXG_C[ta1]}
_tui_text.press ta1 $(( C0 + 3 )) $(( R0 + 1 ));  ok "click places cursor" "$(tui.text.cursor ta1)" "2 4"
_tui_text.drag  ta1 $(( C0 + 8 )) $(( R0 + 1 ));  ok "drag selects" "$(tui.text.selection ta1)" "ond r"
_tui_text.press ta1 $(( C0 + 8 )) $(( R0 ));      _tui_text.press ta1 $(( C0 + 8 )) $(( R0 ))
ok "double click selects a word" "$(tui.text.selection ta1)" "beta"
_tui_text.press ta1 $(( C0 + 8 )) $(( R0 ));      ok "triple click selects the line" "$(tui.text.selection ta1)" "alpha beta gamma"
# ── list / table / select / progress ──
tui.focus li1; S "$DN"; S "$DN"; ok "list down x2" "$(tui.list.selected li1)|$(tui.list.item li1)" "2|gamma"
S "$END"; ok "list end" "$(tui.list.item li1)" "theta"
S "[5~"; ok "list pgup" "$(tui.list.selected li1)" "3"
tui.focus tb1; S "$DN"; ok "table down" "$(tui.table.row tb1)" "run.sh|300|script"
tui.select.pick se1 2; ok "select pick" "$(tui.get se1)|$(tui.select.index se1)" "careful|2"
tui.progress.set pr1 3 4; ok "progress" "$(tui.get pr1)" "75"
tui.focus in1; tui.render > "$OUT/widgets.ans"
tui.focus ta1; S "$SDN"; tui.set ta1 $'one\ntwo\nthree\nfour'; T ""; tui.render > "$OUT/widgets_area.ans"
echo "$N checks, $FAIL failed" >&3
exit $FAIL
