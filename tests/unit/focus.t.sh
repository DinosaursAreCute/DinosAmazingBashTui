# focus.t.sh - lib/input/tui_focus.sh: tab order, groups, id->index map, autofocus (roadmap H).

_foc_pane() {
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_P_ROW[p]=1 _TUI_P_COL[p]=1 _TUI_P_H[p]=10 _TUI_P_W[p]=24
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none _TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
	_TUI_P_ALL=(p) _TUI_P_LEAVES=(p)
}

# four buttons a b c d in document order
_foc_four() {
	_foc_pane
	local i=0 id
	for id in a b c d; do tui.button "$id" p "$((i++))" "$id" ""; done
}

_foc_order() {
	_tui_focus.ensure
	_R="${_TUI_FOCUS_TAB[*]}"
}

t_focus_default_order_is_document_order() {
	_foc_four
	_foc_order
	eq "a b c d" "$_R"
}

t_focus_label_and_progress_are_not_focusable_by_default() {
	_foc_pane
	tui.label l1 p 0 "x"
	tui.button a p 1 "a" ""
	_foc_order
	eq "a" "$_R"
	eq "a" "${_TUI_FOCUSABLE[*]}"
}

t_focus_focusable_true_on_a_label_adds_it() {
	_foc_pane
	tui.label l1 p 0 "x"
	tui.button a p 1 "a" ""
	tui.focus.set l1 focusable true
	_foc_order
	eq "l1 a" "$_R"
}

t_focus_focusable_false_removes_from_everything() {
	_foc_four
	tui.focus.set b focusable false
	_foc_order
	eq "a c d" "$_R"
	eq "a c d" "${_TUI_FOCUSABLE[*]}"
}

t_focus_tabbable_false_keeps_focusable_but_skips_tab() {
	_foc_four
	tui.focus.set b tabbable false
	_foc_order
	eq "a c d" "$_R"
	eq "a b c d" "${_TUI_FOCUSABLE[*]}"
}

t_focus_tab_order_zero_first_minus_one_last() {
	_foc_four
	tui.focus.set c tab_order 0
	tui.focus.set a tab_order -1
	_foc_order
	eq "c b d a" "$_R"
}

t_focus_tab_order_positive_ascending_before_unset() {
	_foc_four
	tui.focus.set d tab_order 1
	tui.focus.set c tab_order 2
	_foc_order
	eq "d c a b" "$_R"
}

t_focus_tab_order_ties_keep_document_order() {
	_foc_four
	tui.focus.set c tab_order 1
	tui.focus.set b tab_order 1
	_foc_order
	eq "b c a d" "$_R"
}

t_focus_id_to_index_map() {
	_foc_four
	tui.focus.set a tab_order -1
	_foc_order
	eq 0 "${_TUI_FOCUS_POS[b]}"
	eq 3 "${_TUI_FOCUS_POS[a]}"
}

t_focus_next_and_prev_walk_the_tab_list_and_wrap() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	_tui_focus.step 1
	eq a "$_TUI_FOCUS_ID"
	_tui_focus.step 1
	eq b "$_TUI_FOCUS_ID"
	_tui_focus.step -1
	_tui_focus.step -1
	eq d "$_TUI_FOCUS_ID"
	eq 3 "$_TUI_FOCUS_IDX"
}

t_focus_prev_from_nothing_lands_on_last() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	_tui_focus.step -1
	eq d "$_TUI_FOCUS_ID"
}

t_focus_wrap_off_stops_at_the_ends() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	_TUI_FOCUS_WRAP=0
	tui.focus d
	_tui_focus.step 1
	eq d "$_TUI_FOCUS_ID"
	tui.focus a
	_tui_focus.step -1
	eq a "$_TUI_FOCUS_ID"
}

t_focus_explicit_focus_next_overrides_order() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	tui.focus.set a focus_next d
	tui.focus.set d focus_prev b
	tui.focus a
	_tui_focus.step 1
	eq d "$_TUI_FOCUS_ID"
	_tui_focus.step -1
	eq b "$_TUI_FOCUS_ID"
}

t_focus_group_arrows_collapse_to_one_tab_stop() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	tui.focus.set b focus_group g
	tui.focus.set c focus_group g
	tui.focus.set b focus_nav arrows
	_foc_order
	eq "a b d" "$_R"
	eq 1 "${_TUI_FOCUS_POS[c]}"
	tui.focus c
	_tui_focus.step 1
	eq d "$_TUI_FOCUS_ID"
}

t_focus_group_tab_returns_to_last_focused_member() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	tui.focus.set b focus_group g
	tui.focus.set c focus_group g
	tui.focus.set b focus_nav arrows
	tui.focus c
	tui.focus a
	_tui_focus.step 1
	eq c "$_TUI_FOCUS_ID"
}

t_focus_group_arrows_move_between_members_with_wrap() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	tui.focus.set b focus_group g
	tui.focus.set c focus_group g
	tui.focus.set b focus_nav both
	tui.focus b
	_tui_focus.arrow down
	eq c "$_TUI_FOCUS_ID"
	_tui_focus.arrow down
	eq b "$_TUI_FOCUS_ID"
	tui.focus.set c focus_wrap false
	tui.focus c
	_tui_focus.arrow down
	eq c "$_TUI_FOCUS_ID"
}

t_focus_arrow_ignored_when_group_nav_is_tab() {
	_foc_four
	tui.focus.set b focus_group g
	tui.focus.set c focus_group g
	_TUI_FOCUS_ID=b
	_tui_focus.arrow down && return 1
	return 0
}

t_focus_autofocus_applies_once_before_render() {
	_foc_four
	_tui._draw_widgets_now() { :; }
	_tui._draw_pane_borders_now() { :; }
	tui.focus.set c autofocus true
	_tui_focus.autofocus
	eq c "$_TUI_FOCUS_ID"
	_TUI_FOCUS_ID=""
	_tui_focus.autofocus
	eq "" "$_TUI_FOCUS_ID"
}

t_focus_set_rejects_unknown_attribute() {
	_foc_four
	tui.focus.set a bogus 1 2>/dev/null && return 1
	return 0
}

t_focus_rebuild_follows_widget_count() {
	_foc_four
	_foc_order
	tui.button e p 5 "e" ""
	_foc_order
	eq "a b c d e" "$_R"
}

t_focus_set_rejects_a_non_boolean_without_forking() {
	_foc_pane
	tui.button a p 0 "a" ""
	tui.focus.set a focusable yes 2>/dev/null && return 1
	eq "" "${_TUI_W_FOCUSABLE[a]:-}"
	tui.focus.set a focusable false
	eq 0 "${_TUI_W_FOCUSABLE[a]}"
	tui.focus.set a tabbable true
	eq 1 "${_TUI_W_TABBABLE[a]}"
}

t_focus_adding_a_widget_marks_the_order_dirty() {
	_foc_four
	_foc_order
	eq 0 "$_TUI_FOCUS_DIRTY"
	tui.button e p 4 "e" ""
	eq 1 "$_TUI_FOCUS_DIRTY"
	_foc_order
	eq "a b c d e" "$_R"
}

t_focus_default_comes_from_the_type_contract() {
	_tui_focus.default_focusable button || return 1
	_tui_focus.default_focusable list || return 1
	_tui_focus.default_focusable label && return 1
	_tui_focus.default_focusable progress && return 1
	_tui_focus.default_focusable nosuchtype && return 1
	return 0
}

# a focus move knows its dirty rows (the old and the new widget): one raw flush, no row diff, no border redraw
# unless the keyboard pane changes
_foc_spy() {
	_BORDERS=0 _FLUSHES=0 _DIFFS=0
	_REAL_FNS="$(declare -f _tui._draw_pane_border_buf _tui._flush _tui_paint.diff)"
	_tui._draw_pane_border_buf() { ((_BORDERS++)); }
	_tui._flush() { ((_FLUSHES++)); }
	_tui_paint.diff() { ((_DIFFS++)); }
}
_foc_unspy() { eval "$_REAL_FNS"; }

t_focus_move_inside_one_pane_draws_no_border_and_does_no_diff_and_flushes_once() {
	_foc_four
	tui.focus a
	_foc_spy
	tui.focus b
	_foc_unspy
	eq "0 1 0" "$_BORDERS $_FLUSHES $_DIFFS"
}

t_focus_move_to_another_pane_redraws_both_borders() {
	_foc_four
	_TUI_P_ALL=(p q) _TUI_P_LEAVES=(p q)
	_TUI_P_ROW[q]=11 _TUI_P_COL[q]=1 _TUI_P_H[q]=5 _TUI_P_W[q]=24 _TUI_P_BORDER[q]=none
	tui.button e q 0 "e" ""
	tui.focus a
	_foc_spy
	tui.focus e
	_foc_unspy
	eq "2 1 0" "$_BORDERS $_FLUSHES $_DIFFS"
}

# focus_dir (arrow keys between widgets) reads widget rects from the hit index instead of recomputing every
# widget's position per press
t_focus_dir_down_goes_to_the_widget_below() {
	_foc_four
	tui.focus a >/dev/null
	tui.action.focus_dir down >/dev/null
	eq b "$_TUI_FOCUS_ID"
	tui.action.focus_dir up >/dev/null
	eq a "$_TUI_FOCUS_ID"
}

t_focus_dir_computes_no_widget_position_once_the_index_is_built() {
	_foc_four
	tui.focus a >/dev/null
	tui.action.focus_dir down >/dev/null # builds the index
	local real calls=0
	real="$(declare -f _tui._widget_pos tui.focus)" # the focus move's own drawing needs positions; only the search is counted
	_tui._widget_pos() { ((calls++)); }
	tui.focus() { _TUI_FOCUS_ID="$1"; }
	tui.action.focus_dir down >/dev/null
	eval "$real"
	eq "0 c" "$calls $_TUI_FOCUS_ID"
}

t_focus_dir_sees_a_widget_that_moved() {
	_foc_four
	tui.focus a >/dev/null
	tui.action.focus_dir down >/dev/null
	_TUI_W_ROW[c]=0 # c now shares a's row: nothing below a is c any more
	_tui_w.changed
	tui.focus a >/dev/null
	tui.action.focus_dir down >/dev/null
	eq b "$_TUI_FOCUS_ID"
}
