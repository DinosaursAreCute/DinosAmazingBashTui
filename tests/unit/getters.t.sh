# getters.t.sh - the VAR forms of tui.config.get, tui.hist.get and tui.list.item / tui.table.row (no subshell on a hot path).

t_config_get_stores_in_a_variable() {
	_TUI_CFG[gt.k]=value
	tui.config.get gt.k dflt OUT
	eq value "$OUT"
}

t_config_get_var_form_uses_the_default() {
	tui.config.get gt.missing dflt OUT
	eq dflt "$OUT"
}

t_config_get_print_form_is_unchanged() {
	_TUI_CFG[gt.k]=value
	eq value "$(tui.config.get gt.k dflt)"
	eq dflt "$(tui.config.get gt.missing dflt)"
}

t_hist_get_stores_in_a_variable() {
	_TA_HIST[gt]="one two"
	tui.hist.get gt OUT
	eq "one two" "$OUT"
	tui.hist.get gt_missing OUT
	eq "" "$OUT"
}

t_list_item_stores_the_selected_item_in_a_variable() {
	_WXA_RESET=1
	tui.list.set gtl a b c
	tui.list.select gtl 1
	tui.list.item gtl "" OUT
	eq b "$OUT"
	tui.list.item gtl 2 OUT
	eq c "$OUT"
}

t_list_item_var_form_is_empty_out_of_range() {
	tui.list.set gtl a
	OUT=stale
	tui.list.item gtl 5 OUT
	eq "" "$OUT"
}

t_table_row_stores_the_selected_row_in_a_variable() {
	tui.table.set gtt "K|V" "a|1" "b|2"
	tui.table.select gtt 1
	tui.table.row gtt "" OUT
	eq "b|2" "$OUT"
}
