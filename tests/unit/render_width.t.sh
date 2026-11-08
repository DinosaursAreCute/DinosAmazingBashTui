# render_width.t.sh - _tui._vwidth_v (display width without escape codes) and _tui._calc_bounds, which no longer forks awk.

t_vwidth_plain_text() {
	_tui._vwidth_v "hello"
	eq 5 "$_VW"
}

t_vwidth_strips_csi() {
	_tui._vwidth_v $'\e[1;31mred\e[0m!'
	eq 4 "$_VW"
}

t_vwidth_strips_osc_with_bel_and_st() {
	_tui._vwidth_v $'\e]0;title\a text'
	eq 5 "$_VW"
	_tui._vwidth_v $'\e]8;;http://x\e\\link\e]8;;\e\\'
	eq 4 "$_VW"
}

t_vwidth_strips_two_character_escapes() {
	_tui._vwidth_v $'a\eMb'
	eq 2 "$_VW"
}

t_vwidth_keeps_a_lone_escape() {
	_tui._vwidth_v $'ab\e'
	eq 3 "$_VW"
}

t_vwidth_memo_returns_the_same_width() {
	_tui._vwidth_v $'\e[1mx\e[0m'
	local a=$_VW
	_tui._vwidth_v $'\e[1mx\e[0m'
	eq "$a" "$_VW"
}

t_calc_bounds_measures_coloured_lines_without_their_codes() {
	_TUI_PANE_CONTENT_wpane=($'\e[31mabc\e[0m' "abcdefg" $'\e[1mab\e[0m')
	_tui._calc_bounds wpane
	eq 7 "${_TUI_P_MAX_W[wpane]}"
	eq 3 "${_TUI_P_LINES[wpane]}"
}

t_calc_bounds_widest_line_can_be_the_coloured_one() {
	_TUI_PANE_CONTENT_wpane=("ab" $'\e[32mabcdefgh\e[0m')
	_tui._calc_bounds wpane
	eq 8 "${_TUI_P_MAX_W[wpane]}"
}

t_calc_bounds_empty_pane() {
	_TUI_PANE_CONTENT_wpane=()
	_tui._calc_bounds wpane
	eq 0 "${_TUI_P_MAX_W[wpane]}"
}
