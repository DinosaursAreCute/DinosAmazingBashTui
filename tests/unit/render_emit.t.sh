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

_re_frame() { # ROWS -> REPLY: rows of an absolute cursor move, a style and 100 cells, each ending in a reset
	local r
	REPLY=""
	for ((r = 1; r <= $1; r++)); do REPLY+=$'\e['"$r;1H"$'\e[38;5;99m'"$(printf 'x%.0s' {1..100})"$'\e[0m'; done
}

t_write_chunks_a_small_frame_is_one_piece() {
	_tui._write_chunks "abc" ""
	eq 1 "${#_TW_CHUNKS[@]}"
	eq abc "${_TW_CHUNKS[0]}"
}

t_write_chunks_cuts_only_before_a_cursor_move_and_every_piece_stands_alone() {
	local sty=$'\e[48;2;1;2;3m' c n=0 bad=0
	_re_frame 120
	_tui._write_chunks "$sty$REPLY" "$sty"
	ok '(( ${#_TW_CHUNKS[@]} > 2 ))'
	for c in "${_TW_CHUNKS[@]}"; do
		((${#c} <= _TUI_WRITE_MAX)) || bad=1
		[[ "$c" == "$sty"* || $((n)) == 0 ]] || bad=1
		[[ "${c#"$sty"}" == $'\e['[0-9]*';'[0-9]*H* ]] || bad=1 # starts at a cursor move
		((n++ < ${#_TW_CHUNKS[@]} - 1)) && { [[ "$c" == *$'\e[0m' ]] || bad=1; }
	done
	eq 0 "$bad"
}

t_write_wraps_in_one_synchronized_update_and_loses_nothing() {
	local out="$_T_ROOT/tw_$RANDOM" sty=$'\e[48;2;1;2;3m'
	_re_frame 120
	_tui.write "$sty$REPLY" "$sty" >"$out"
	local got
	got="$(
		cat "$out"
		printf x
	)"
	got="${got%x}"
	ok '[[ "$got" == $'"'"'\e[?2026h'"'"'* && "$got" == *$'"'"'\e[?2026l'"'"' ]]'
	eq 1 "$(grep -o $'\e\\[?2026h' "$out" | wc -l)"
	eq 1 "$(grep -o $'\e\\[?2026l' "$out" | wc -l)"
	eq 120 "$(grep -o $'\e\\[[0-9]*;1H' "$out" | wc -l)" # every row arrived, none twice
}

t_write_chunks_a_long_row_of_single_cell_styles_is_cut_between_sequences_and_in_bytes() {
	local cell=$'\e[38;2;201;214;227;48;2;28;35;54m│\e[0m' row=$'\e[10;1H' c i n=0 bad=0
	for ((i = 0; i < 300; i++)); do row+="$cell"; done # one row of 300 cells: ~12 KB in bytes, no second cursor move
	_tui._write_chunks "$row" ""
	ok '(( ${#_TW_CHUNKS[@]} >= 3 ))'
	for c in "${_TW_CHUNKS[@]}"; do
		(($(
			LC_ALL=C
			echo -n "${#c}"
		) <= _TUI_WRITE_MAX)) || bad=1
		[[ "$c" == *$'\e[38;2;201;214;227;48;2;28;35;54m' || "$c" == *$'\e[0m' ]] || bad=1 # never ends inside a sequence
	done
	eq 0 "$bad"
}
