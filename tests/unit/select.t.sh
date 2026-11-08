# select.t.sh - tui.select / the :selected button look and tabs marking the active tab selected.

_sl_pane() {
	_TUI_P_ROW[p]=2 _TUI_P_COL[p]=3 _TUI_P_H[p]=10 _TUI_P_W[p]=24
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none
	_TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
	_TUI_FOCUS_ID="" _TUI_HOVERED_WIDGET=""
}

_sl_draw() { # ID -> bytes in _SL_OUT
	_TUI_FRAME=""
	_tui._draw_widget_buf "$1"
	_SL_OUT="$_TUI_FRAME"
}

t_tabsel_select_toggles_the_flag() {
	tui.select b1 >/dev/null # no such widget: only the flag changes, nothing draws
	eq 1 "${_TUI_W_SELECTED[b1]:-}"
	tui.select b1 false >/dev/null
	eq "" "${_TUI_W_SELECTED[b1]:-}"
}

t_tabsel_selected_button_draws_its_selected_style_when_unfocused() {
	_sl_pane
	tui.button b1 p 0 "Go" ""
	tui.style b1 "#112233" "#445566" "" selected
	_sl_draw b1
	local plain="$_SL_OUT"
	tui.select b1 >/dev/null
	_sl_draw b1
	[[ "$_SL_OUT" != "$plain" ]] || return 1
	match "$_SL_OUT" "48;2;68;85;102" # the selected bg, not served from the unselected cached row
}

t_tabsel_focus_still_wins_over_selected() {
	_sl_pane
	tui.button b1 p 0 "Go" ""
	tui.style b1 "#112233" "#445566" "" selected
	tui.style b1 "#aa0000" "#bb0000" "" focus
	tui.select b1 >/dev/null
	_TUI_FOCUS_ID=b1
	_sl_draw b1
	match "$_SL_OUT" "48;2;187;0;0"
}

t_tabsel_tabs_activate_selects_only_the_active_tab() {
	_TUI_TAB_GROUP[ta]=g _TUI_TAB_GROUP[tb]=g # no widgets: only the selection flags are exercised
	tui.tabs.activate ta >/dev/null
	eq "1:" "${_TUI_W_SELECTED[ta]:-}:${_TUI_W_SELECTED[tb]:-}"
	tui.tabs.activate tb >/dev/null
	eq ":1" "${_TUI_W_SELECTED[ta]:-}:${_TUI_W_SELECTED[tb]:-}"
}

t_tabsel_activate_clears_a_stale_flag_left_by_another_page() {
	_TUI_TAB_GROUP[ta]=g _TUI_TAB_GROUP[tb]=g _TUI_W_SELECTED[ta]=1 # ta stayed flagged from a page with another tabs group
	tui.tabs.activate tb >/dev/null
	eq ":1" "${_TUI_W_SELECTED[ta]:-}:${_TUI_W_SELECTED[tb]:-}"
}
