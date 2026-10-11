# table.t.sh - lib/widgets/tui_widgets.sh: tui.table.set --keep, tui.table.align, tui.table.heat.

# the _WX* widget tables are not in the runner snapshot: start every test clean
_tb_reset() { _WXAL=() _WXHW=() _WXHH=() _WXSEL=() _WXTOP=() _WXCOLS=(); }

_tb_draw() { # ROWS: paints table tb into a 40x6 area
	_TUI_FRAME=""
	_tui_wx.draw_rows tb table 1 1 40 "${1:-6}" 0 tb_normal tbp_normal
}

t_table_set_resets_the_selection_by_default() {
	_tb_reset
	tui.table.set tb "K|V" "a|1" "b|2" "c|3"
	tui.table.select tb 2
	tui.table.set tb "K|V" "a|1" "b|2" "c|3"
	tui.table.selected tb SEL
	eq 0 "$SEL"
}

t_table_set_keep_follows_the_row_with_the_same_key() {
	_tb_reset
	tui.table.set tb "K|V" "a|1" "b|2" "c|3"
	tui.table.select tb 2
	tui.table.set --keep 0 tb "K|V" "x|9" "c|4" "a|1" "b|2"
	tui.table.selected tb SEL
	eq 1 "$SEL"
}

t_table_set_keep_clamps_when_the_key_is_gone() {
	_tb_reset
	tui.table.set tb "K|V" "a|1" "b|2" "c|3"
	tui.table.select tb 2
	tui.table.set --keep 0 tb "K|V" "x|1" "y|2"
	tui.table.selected tb SEL
	eq 1 "$SEL"
}

t_table_set_keep_on_an_empty_table_selects_nothing() {
	_tb_reset
	tui.table.set tb "K|V" "a|1"
	tui.table.set --keep 0 tb "K|V"
	tui.table.selected tb SEL
	eq -1 "$SEL"
}

t_table_set_keep_holds_the_row_at_the_same_screen_position() {
	_tb_reset
	local -a rows=()
	local i
	for ((i = 0; i < 40; i++)); do rows+=("r$i|$i"); done
	tui.table.set tb "K|V" "${rows[@]}"
	_WXTOP[tb]=10
	tui.table.select tb 13      # 3 rows below the top of the view
	rows=("new|0" "${rows[@]}") # everything moves down one
	tui.table.set --keep 0 tb "K|V" "${rows[@]}"
	tui.table.selected tb SEL
	eq 14 "$SEL"
	eq 11 "${_WXTOP[tb]}"
}

t_table_align_right_pads_on_the_left() {
	_tb_reset
	tui.table.set tb "Name|Sz" "a|7" "b|42"
	tui.table.select tb -1
	tui.table.align tb "l|r"
	_tb_draw
	match "$_TUI_FRAME" 'a {6}7'
	match "$_TUI_FRAME" 'b {5}42'
}

t_table_align_left_is_the_default() {
	_tb_reset
	tui.table.set tb "Name|Sz" "a|7"
	tui.table.select tb -1
	_tb_draw
	match "$_TUI_FRAME" 'a {3}  7 '
}

t_table_heat_colours_cells_over_the_thresholds() {
	_tb_reset
	tui.table.set tb "Name|Cpu" "a|10" "b|70" "c|90"
	tui.table.select tb -1
	tui.table.heat tb 1 60 85
	_tb_draw
	match "$_TUI_FRAME" $'\e\\[33m70'
	match "$_TUI_FRAME" $'\e\\[31m90'
	[[ "$_TUI_FRAME" != *$'\e[33m10'* && "$_TUI_FRAME" != *$'\e[31m10'* ]]
}

t_table_heat_leaves_the_selected_row_alone() {
	_tb_reset
	tui.table.set tb "Name|Cpu" "a|90"
	tui.table.heat tb 1 60 85
	_tb_draw
	[[ "$_TUI_FRAME" != *$'\e[31m'* && "$_TUI_FRAME" != *$'\e[39m'* ]]
}
