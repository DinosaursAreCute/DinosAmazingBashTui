# render_emit.t.sh - lib/render/tui_emit.sh buffer-mode paint primitives (stage 0.3).

t_emit_appends_to_frame() {
	_TUI_FRAME=""
	_tui.emit "abc"
	_tui.emit "def"
	eq "abcdef" "$_TUI_FRAME"
}

t_emit_goto_appends_cursor_escape() {
	_TUI_FRAME=""
	_tui.emit_goto 3 7
	eq $'\e[3;7H' "$_TUI_FRAME"
}

t_emit_reset_appends_sgr_reset() {
	_TUI_FRAME=""
	_tui.emit_reset
	eq $'\e[0m' "$_TUI_FRAME"
}

t_emit_pad_appends_n_blanks() {
	_TUI_FRAME=""
	_tui.emit_pad 4
	eq "    " "$_TUI_FRAME"
}

t_emit_repeat_appends_n_copies_of_char() {
	_TUI_FRAME=""
	_tui.emit_repeat "-" 5
	eq "-----" "$_TUI_FRAME"
}

t_emit_repeat_zero_appends_nothing() {
	_TUI_FRAME="x"
	_tui.emit_repeat "-" 0
	eq "x" "$_TUI_FRAME"
}

t_emit_style_appends_known_fg_color_sgr() {
	_TUI_FRAME=""
	_TUI_STYLE_FG=([k]=red)
	_TUI_STYLE_BG=()
	_TUI_STYLE_MOD=()
	_tui.emit_style k
	eq $'\e[31m' "$_TUI_FRAME"
	_TUI_STYLE_FG=()
}

t_emit_style_appends_hex_bg_and_mod() {
	_TUI_FRAME=""
	_TUI_STYLE_FG=()
	_TUI_STYLE_BG=([k]="#112233")
	_TUI_STYLE_MOD=([k]="bold")
	_tui.emit_style k
	eq $'\e[48;2;17;34;51;1m' "$_TUI_FRAME"
	_TUI_STYLE_BG=()
	_TUI_STYLE_MOD=()
}

t_emit_ring_resolves_fg_from_key_falls_back_to_id_normal_bg() {
	_TUI_FRAME=""
	_TUI_STYLE_FG=([b_border]=cyan)
	_TUI_STYLE_BG=([id_normal]=blue)
	_TUI_STYLE_MOD=()
	_tui.emit_ring b_border b_border id
	eq $'\e[36;44m' "$_TUI_FRAME"
	_TUI_STYLE_FG=()
	_TUI_STYLE_BG=()
}

t_emit_multiple_calls_accumulate_in_order() {
	_TUI_FRAME=""
	_tui.emit_goto 1 1
	_tui.emit "hi"
	_tui.emit_reset
	eq $'\e[1;1Hhi\e[0m' "$_TUI_FRAME"
}
