#!/usr/bin/env bash
# hit.t.sh - lib/input/tui_hit.sh: per-row interval index of interaction zones (roadmap E base).

# one leaf pane "p": rows 1..10, cols 1..24, no border, no padding
_hit_pane() { # [SCROLL]
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_P_ROW[p]=1 _TUI_P_COL[p]=1 _TUI_P_H[p]=10 _TUI_P_W[p]=24
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none _TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
	_TUI_P_SCROLL[p]="${1:-none}"
	_TUI_P_ALL=(p) _TUI_P_LEAVES=(p)
}

# _hit_at ROW COL -> "kind:id" (":" if nothing but the pane)
_hit_at() {
	_tui_hit.at "$2" "$1"
	_R="$_HIT_KIND:$_HIT_ID"
}

t_hit_widget_hit_and_miss() {
	_hit_pane
	tui.button b1 p 0 "Go" ""
	_tui._widget_pos b1
	local r=$_WSR c=$_WSC w=$_WSW
	_tui_hit.rebuild
	_hit_at "$r" "$c"
	eq "widget:b1" "$_R"
	eq p "$_HIT_PANE"
	eq b1 "$_HIT"
	_hit_at "$r" "$((c + w - 1))"
	eq "widget:b1" "$_R"
	_hit_at "$r" "$((c + w))"
	eq ":" "$_R"
	eq p "$_HIT_PANE"
	_hit_at "$((r + 1))" "$c"
	eq ":" "$_R"
}

t_hit_label_is_not_a_zone() {
	_hit_pane
	tui.label l1 p 0 "hello"
	_tui_hit.rebuild
	_hit_at 1 1
	eq ":" "$_R"
}

t_hit_outside_every_pane_is_empty() {
	_hit_pane
	_tui_hit.rebuild
	_tui_hit.at 70 20
	eq "" "$_HIT_PANE"
	eq "" "$_HIT_KIND"
	_tui_hit.at 70 20 && return 1
	return 0
}

t_hit_hit_pad_extends_widget_area() {
	_hit_pane
	tui.button b1 p 1 "Go" ""
	_tui._widget_pos b1
	local r=$_WSR c=$_WSC
	tui.hit.set b1 hit_pad 1
	_tui_hit.rebuild
	_hit_at "$((r - 1))" "$((c - 1))"
	eq "hitbox:b1" "$_R"
	_hit_at "$r" "$c"
	eq "widget:b1" "$_R"
}

t_hit_pad_never_steals_a_neighbours_own_area() {
	_hit_pane
	tui.button b1 p 0 "Go" ""
	tui.button b2 p 1 "Go" ""
	_tui._widget_pos b2
	local r=$_WSR c=$_WSC
	tui.hit.set b1 hit_pad 3
	_tui_hit.rebuild
	_hit_at "$r" "$c"
	eq "widget:b2" "$_R"
}

t_hit_explicit_hitbox_offsets() {
	_hit_pane
	tui.button b1 p 2 "Go" ""
	_tui._widget_pos b1
	local r=$_WSR c=$_WSC
	tui.hit.set b1 hitbox "-1 5 1 4" # dy dx h w, relative to the widget origin
	_tui_hit.rebuild
	_hit_at "$((r - 1))" "$((c + 5))"
	eq "hitbox:b1" "$_R"
	_hit_at "$((r - 1))" "$((c + 9))"
	eq ":" "$_R"
}

t_hit_vertical_scrollbar_is_three_columns_wide() {
	_hit_pane v
	_tui_hit.rebuild
	_hit_at 5 24
	eq "scrollbar:p" "$_R"
	eq v "$_HIT_ARG"
	_hit_at 5 22
	eq "scrollbar:p" "$_R"
	_hit_at 5 21
	eq ":" "$_R"
}

t_hit_vertical_scrollbar_spans_pane_rows_only() {
	_hit_pane v
	_tui_hit.rebuild
	_hit_at 1 24
	eq "scrollbar:p" "$_R"
	_hit_at 10 24
	eq "scrollbar:p" "$_R"
	_hit_at 11 24
	eq ":" "$_R"
	_hit_at 0 24
	eq ":" "$_R"
}

t_hit_horizontal_scrollbar_is_three_rows_high() {
	_hit_pane h
	_tui_hit.rebuild
	_hit_at 10 5
	eq "scrollbar:p" "$_R"
	eq h "$_HIT_ARG"
	_hit_at 8 5
	eq "scrollbar:p" "$_R"
	_hit_at 7 5
	eq ":" "$_R"
}

t_hit_scrollbar_clamped_to_a_narrow_pane() {
	_hit_pane v
	_TUI_P_W[p]=2
	_tui_hit.rebuild
	_hit_at 5 1
	eq "scrollbar:p" "$_R"
	_hit_at 5 2
	eq "scrollbar:p" "$_R"
	_hit_at 5 0
	eq ":" "$_R"
	_hit_at 5 3
	eq ":" "$_R"
}

t_hit_both_mode_vertical_wins_the_corner() {
	_hit_pane both
	_tui_hit.rebuild
	_hit_at 10 24
	eq "scrollbar:p" "$_R"
	eq v "$_HIT_ARG"
	_hit_at 10 10
	eq h "$_HIT_ARG"
}

t_hit_scrollbar_wins_over_widget_beneath() {
	_hit_pane v
	tui.button b1 p 0 "A long button label here" ""
	_tui_hit.rebuild
	_hit_at 1 23
	eq "scrollbar:p" "$_R"
	eq "" "$_HIT"
}

t_hit_extra_zone_kinds_beat_widgets() {
	_hit_pane
	tui.button b1 p 0 "Go" ""
	local k
	for k in divider handle chevron title; do
		_tui_hit.extra_clear
		_tui_hit.extra_add "$k" z1 "" 1 1 1 5
		_tui_hit.rebuild
		_hit_at 1 1
		eq "$k:z1" "$_R"
	done
}

t_hit_extra_zone_rejects_unknown_kind() {
	_tui_hit.extra_clear
	_tui_hit.extra_add bogus z1 "" 1 1 1 5 && return 1
	return 0
}

ti_hit_row_lists_stay_short_with_many_widgets() {
	_hit_pane
	_TUI_ROWS=200
	_TUI_P_H[p]=150
	local i
	for i in {0..99}; do tui.button "b$i" p "$i" "Go" ""; done
	_tui_hit.rebuild
	local -a zs=(${_TUI_HZ_ROW[50]})
	ok '((${#zs[@]} <= 3))'
	_hit_at 51 2
	eq "widget:b50" "$_R"
}

t_hit_layout_marks_index_dirty() {
	_t_needs_caches || return 0
	_hit_pane
	_tui_hit.rebuild
	eq 0 "$_TUI_HZ_DIRTY"
	_TUI_P_CHILDREN[p]=""
	unset '_TUI_P_CHILDREN[p]'
	_tui._layout p
	eq 1 "$_TUI_HZ_DIRTY"
}

t_hit_click_on_scrollbar_zone_scrolls() {
	_hit_pane v
	_TUI_P_LINES[p]=100
	TUI_EVENT_ZONE=scrollbar TUI_EVENT_ZONE_ID=p TUI_EVENT_ZONE_ARG=v
	TUI_EVENT_X=24 TUI_EVENT_Y=6 TUI_EVENT_RAWBTN=0 TUI_EVENT_PANE=p TUI_EVENT_WIDGET="" TUI_EVENT_KEY=mouse:left
	tui.action.click
	eq 50 "${_TUI_P_SOFF_V[p]}"
}

t_hit_at_rc_is_zone_not_widget() {
	_hit_pane v
	_tui_hit.at 24 5
	eq scrollbar "$_HIT_KIND"
	eq "" "$_HIT"
	ok '_tui_hit.at 24 5'
	ok '! _tui_hit.at 3 5' # only the pane fallback
	eq p "$_HIT_PANE"
}

t_hit_title_zone_sits_on_the_top_border_after_the_rule() {
	_hit_pane
	_TUI_P_BORDER[p]=single
	_TUI_P_TITLE[p]="Hi"
	_hit_at 1 3 # corner at col 1, rule at col 2, " Hi " at cols 3..6
	eq "title:p" "$_R"
	_hit_at 1 6
	eq "title:p" "$_R"
	_hit_at 1 7
	eq ":" "$_R"
	_hit_at 1 2
	eq ":" "$_R"
	_hit_at 2 3
	eq ":" "$_R"
}

t_hit_no_title_zone_without_a_frame() {
	_hit_pane
	_TUI_P_TITLE[p]="Hi"
	_hit_at 1 3 # border=none: nothing is drawn, nothing to hit
	eq ":" "$_R"
}

t_hit_adding_a_widget_marks_the_index_dirty() {
	_t_needs_caches || return 0
	_hit_pane
	tui.button b1 p 0 "Go" ""
	_tui_hit.rebuild
	eq 0 "$_TUI_HZ_DIRTY"
	tui.button b2 p 1 "Go" ""
	eq 1 "$_TUI_HZ_DIRTY"
}

t_hit_rebuild_restores_the_callers_widget_pos_reuse() {
	_hit_pane
	tui.button b1 p 0 "Go" ""
	_TUI_WP_REUSE=1
	_tui_hit.rebuild
	eq 1 "$_TUI_WP_REUSE"
	_TUI_WP_REUSE=0
	_tui_hit.rebuild
	eq 0 "$_TUI_WP_REUSE"
}

# Scrolling pane hit tests
t_hit_visible_scrolled_widget_is_hittable() {
	_hit_pane v
	tui.button b1 p 5 "Go" ""
	_TUI_P_SOFF_V[p]=2
	_tui._widget_pos b1
	local r=$_WSR c=$_WSC w=$_WSW
	# Widget should be visible and hittable
	((r >= 1 && r < 11)) && {
		_tui_hit.rebuild
		_hit_at "$r" "$c"
		eq "widget:b1" "$_R"
	}
}

t_hit_scrolled_out_widget_above_viewport_not_hittable() {
	_hit_pane v
	tui.button b1 p 0 "Go" ""
	_TUI_P_SOFF_V[p]=5
	_tui._widget_pos b1
	local r=$_WSR c=$_WSC
	# Widget should be scrolled out (negative row)
	((r < 1)) && {
		_tui_hit.rebuild
		_hit_at "$r" "$c"
		eq ":" "$_R" # No widget hit, just pane
	}
}
