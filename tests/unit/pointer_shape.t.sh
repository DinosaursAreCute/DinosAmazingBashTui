# pointer_shape.t.sh - the `cursor:` CSS property and the mouse pointer shape (OSC 22) under the hovered widget.

_ps_setup() {
	TUI_POINTER_SHAPE=1 _TUI_POINTER_NOW="" _TUI_HZ_HOVER="" _TUI_OUT_FD=1
	_TUI_W_TYPE=([b1]=button [i1]=input [l1]=label) _TUI_STYLE_CUR=()
}

t_theme_parses_cursor_into_the_class_table() {
	printf '%s\n' '.ps_btn { cursor: pointer; }' >"$_T_ROOT/ps.css"
	_TUI_CLASS_CUR=()
	_tui.theme_parse "$_T_ROOT/ps.css"
	_tui.theme_commit
	eq pointer "${_TUI_CLASS_CUR[ps_btn]}"
}

t_class_bakes_cursor_onto_the_widget() {
	_TUI_CLASS_CUR[ps_x]=grab _TUI_STYLE_CUR=()
	tui.class w1 ps_x
	eq grab "${_TUI_STYLE_CUR[w1_normal]}"
}

# _ps_hover ID... - hovers each id in turn (after _ps_setup); prints the bytes written to the terminal
_ps_hover() { local id arg; for id in "$@"; do arg=""; [[ $id == *:* ]] && arg=${id#*:}; _tui._pointer_update "${id%%:*}" "$arg"; done; }

t_interactive_types_get_a_default_shape() {
	_ps_setup
	eq $'\e]22;pointer\e\\\e]22;text\e\\' "$(_ps_hover b1 i1)"
}

t_css_cursor_overrides_the_type_default() {
	_ps_setup
	_TUI_STYLE_CUR[b1_normal]=not-allowed
	eq $'\e]22;not-allowed\e\\' "$(_ps_hover b1)"
}

t_unchanged_shape_is_not_re_emitted() {
	_ps_setup
	eq $'\e]22;pointer\e\\' "$(_ps_hover b1 b1)"
}

t_leaving_a_widget_restores_the_default_shape() {
	_ps_setup
	eq $'\e]22;pointer\e\\\e]22;default\e\\' "$(_ps_hover b1 "")"
}

t_non_interactive_widget_keeps_the_default_shape() {
	_ps_setup
	eq "" "$(_ps_hover l1)"
}

t_disabled_setting_emits_nothing() {
	_ps_setup
	TUI_POINTER_SHAPE=0
	eq "" "$(_ps_hover b1)"
}

t_pointer_reset_returns_the_terminal_default() {
	_ps_setup
	eq $'\e]22;pointer\e\\\e]22;\e\\' "$(_ps_hover b1; _tui._pointer_reset)"
}

t_config_apply_reads_pointer_shape() {
	_TUI_CFG[pointer.shape]=0 TUI_POINTER_SHAPE=1
	tui.config.apply
	eq 0 "$TUI_POINTER_SHAPE"
	unset '_TUI_CFG[pointer.shape]'
}

t_switching_the_setting_off_restores_the_pointer() {
	_ps_setup
	eq $'\e]22;pointer\e\\\e]22;\e\\' "$(_ps_hover b1; TUI_POINTER_SHAPE=0; _ps_hover b1)"
}

t_hover_and_focus_rules_bake_per_state() {
	_TUI_CLASS_CUR=([ps_y]=text [ps_y_hover]=grab [ps_y_focus]=wait) _TUI_STYLE_CUR=()
	tui.class w2 ps_y
	eq "text grab wait" "${_TUI_STYLE_CUR[w2_normal]} ${_TUI_STYLE_CUR[w2_hover]} ${_TUI_STYLE_CUR[w2_focus]}"
}

t_hover_rule_beats_focus_rule_beats_base() {
	_ps_setup
	_TUI_STYLE_CUR=([b1_normal]=a [b1_focus]=b [b1_hover]=c)
	_tui._pointer_shape_of "" b1
	local hover=$_PS
	unset '_TUI_STYLE_CUR[b1_hover]'
	_TUI_FOCUS_ID=b1
	_tui._pointer_shape_of "" b1
	local focus=$_PS
	_TUI_FOCUS_ID=""
	_tui._pointer_shape_of "" b1
	eq "c b a" "$hover $focus $_PS"
}

t_resize_and_collapse_zones_get_their_own_shapes() {
	_ps_setup
	local arg out=""
	for arg in rz-h rz-hl rz-v rz-vl rz-corner cv-p; do _tui._pointer_shape_of "$arg" ""; out+="$_PS "; done
	eq "col-resize col-resize row-resize row-resize nwse-resize pointer " "$out"
}

t_zone_shape_beats_the_widget_under_it() {
	_ps_setup
	eq $'\e]22;col-resize\e\\' "$(_ps_hover b1:rz-h)"
}

# _ps_mouse_over HANDLE COL ROW - a resizable split a|b (b/a for "v"), the pointer moved to the cell; prints what was written
_ps_mouse_over() { # DIR HANDLE COL ROW
	_TUI_ROWS=24 _TUI_RZ_ZONES=0 _TUI_HZ_HOVER="" _TUI_RUNNING=0 _TUI_FOCUS_ID="" _TUI_PANE_FOCUS=""
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=80
	if [[ $1 == h ]]; then tui.hsplit root a b; else tui.vsplit root a b; fi
	tui.pane_resizable a both
	tui.pane_handle a "$2"
	_tui._layout root
	_tui_hit.rebuild
	_ps_setup
	_tui._handle_mouse "[<35;$3;${4}M"
}

t_pointer_over_a_vertical_divider_is_col_resize() {
	eq $'\e]22;col-resize\e\\' "$(_ps_mouse_over h divider 40 5)"
}

t_pointer_over_a_horizontal_divider_is_row_resize() {
	eq $'\e]22;row-resize\e\\' "$(_ps_mouse_over v divider 5 10)"
}

t_pointer_over_a_resizable_pane_edge_is_a_resize_shape() {
	eq $'\e]22;col-resize\e\\' "$(_ps_mouse_over h edge 40 5)"
}

t_pointer_off_the_divider_restores_the_default() {
	eq $'\e]22;col-resize\e\\\e]22;default\e\\' "$(_ps_mouse_over h divider 40 5; _tui._handle_mouse "[<35;10;5M")"
}

t_layer_chrome_gets_pointer_move_and_resize_shapes() {
	_ps_setup
	_TUI_L_N=0
	local arg out=""
	for arg in ly-btn:close ly-dt ly-drag ly-size; do _tui._pointer_shape_of "$arg" "" 1 1; out+="$_PS "; done
	eq "pointer pointer move nwse-resize " "$out"
}

t_open_modal_decides_the_shape_alone() {
	_ps_setup
	_TUI_MODAL=m _TUI_MODAL_POINTERFN=_ps_modal_fn
	_ps_modal_fn() { _PS=text; }
	_tui._pointer_shape_of "" b1 1 1
	local hooked=$_PS
	_TUI_MODAL_POINTERFN=""
	_tui._pointer_shape_of "" b1 1 1
	eq "text default" "$hooked $_PS"
}

t_page_under_a_blocking_layer_keeps_the_default_pointer() {
	_ps_setup
	_TUI_L_N=1
	_TUI_STYLE_CUR[b1_normal]=grab
	# a subshell keeps the stub out of the other tests
	eq default "$(_tui_layer.blocked() { return 0; }; _tui._pointer_shape_of "" b1 1 1; printf %s "$_PS")"
}

t_dialog_buttons_and_list_rows_are_pointers() {
	_ps_setup
	_DLG_KIND=confirm _DLG_BROW=10 _DLG_BTN=(a b) _DLG_BLO=(5 15) _DLG_BHI=(9 19)
	_tui_dialog.pointer 6 10
	local on_button=$_PS
	_tui_dialog.pointer 12 10
	local between=$_PS
	_tui_dialog.pointer 6 9
	local above=$_PS
	_DLG_KIND=choose _DLG_X=2 _DLG_W=30 _DLG_LROW=5 _DLG_ROWS=3
	_tui_dialog.pointer 4 6
	eq "pointer default default pointer" "$on_button $between $above $_PS"
}

t_palette_query_is_text_and_rows_are_pointers() {
	_ps_setup
	_PAL_BX=10 _PAL_BY=3 _PAL_BW=40 _PAL_RY=6 _PAL_ROWS=5 _PAL_TOP=0 _PAL_IDS=(a b c)
	_tui_cmd.palette_pointer 20 4
	local query=$_PS
	_tui_cmd.palette_pointer 20 7
	local row=$_PS
	_tui_cmd.palette_pointer 20 9
	eq "text pointer default" "$query $row $_PS"
}

ti_demo_menu_edge_shows_col_resize_through_the_real_pointer_path() {
	local out
	out=$( # a subshell: loading a page changes state the runner does not restore
		tui.reset_ui
		tui.load "$REPO/share/demo/layers.xml" 2>/dev/null
		tui.render >/dev/null
		_ps_setup
		_TUI_W_TYPE=()
		_TUI_RUNNING=1
		_tui._handle_mouse "[<35;$((${_TUI_P_COL[nav]} + ${_TUI_P_W[nav]} - 1));$((${_TUI_P_ROW[nav]} + 6))M" 2>&1 | LC_ALL=C grep -ao $'\e\\]22;[a-z-]*'
	)
	eq $'\e]22;col-resize' "$out"
}
