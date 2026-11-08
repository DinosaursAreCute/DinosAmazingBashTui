# Widget sizing constraints in _tui._widget_pos (2A): min/max width+height,
# and expand as the generic replacement for the old hardcoded
# textarea/list/table case - "one constraint model for panes and widgets".

_wsize_reset_pane() {
	_TUI_P_ROW[p]=1 _TUI_P_COL[p]=1 _TUI_P_H[p]=10 _TUI_P_W[p]=24
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none
	_TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
}

t_widget_pos_no_expand_is_one_row() {
	_wsize_reset_pane
	tui.button b1 p 0 "Go" ""
	_tui._widget_pos b1
	eq 1 "$_WSH"
}

t_widget_pos_expand_y_fills_content_height() {
	_wsize_reset_pane
	tui.button b1 p 0 "Go" ""
	tui.expand b1 y
	_tui._widget_pos b1
	_tui._content_rect p
	eq "$_CR_H" "$_WSH"
}

t_widget_pos_list_and_table_default_to_expand_y() {
	_wsize_reset_pane
	tui.list mylist p 0
	tui.table mytable p 0
	_tui._content_rect p
	local want=$_CR_H
	_tui._widget_pos mylist
	eq "$want" "$_WSH"
	_tui._widget_pos mytable
	eq "$want" "$_WSH"
}

t_widget_pos_textarea_can_opt_out_of_its_default_expand() {
	_wsize_reset_pane
	tui.textarea ta p 0
	tui.expand ta x
	_tui._widget_pos ta
	eq 1 "$_WSH"
}

t_widget_pos_min_height_is_enforced() {
	_wsize_reset_pane
	tui.button b1 p 0 "Go" ""
	tui.minsize b1 "" 999
	_tui._widget_pos b1
	eq 999 "$_WSH"
}

t_widget_pos_max_height_caps_expand() {
	_wsize_reset_pane
	tui.list mylist p 0
	tui.maxsize mylist "" 2
	_tui._widget_pos mylist
	eq 2 "$_WSH"
}

t_widget_pos_min_width_is_enforced() {
	_wsize_reset_pane
	tui.button b1 p 0 "Go" ""
	tui.minsize b1 999
	_tui._widget_pos b1
	eq 999 "$_WSW"
}

t_widget_pos_max_width_caps_available_width() {
	_wsize_reset_pane
	tui.button b1 p 0 "Go" ""
	tui.maxsize b1 3
	_tui._widget_pos b1
	eq 3 "$_WSW"
}

t_get_with_a_variable_name_stores_the_value_without_printing() {
	_TUI_W_VALUE[gv1]="hello"
	local out got=""
	out="$(tui.get gv1)"
	eq "hello" "$out"
	tui.get gv1 got
	eq "hello" "$got"
	tui.get gv_missing got
	eq "" "$got"
}

t_list_selected_with_a_variable_name_stores_the_index() {
	_WXSEL[ls1]=3
	local got=""
	tui.list.selected ls1 got
	eq 3 "$got"
	eq 3 "$(tui.list.selected ls1)"
	tui.list.selected ls_none got
	eq -1 "$got"
	tui.table.selected ls1 got
	eq 3 "$got"
}
