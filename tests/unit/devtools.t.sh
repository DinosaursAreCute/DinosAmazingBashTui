# devtools.t.sh - lib/chrome/tui_devtools.sh: the dev-tools dock (tabs, scrolling, pause, filter, reserved rows, focus keys).

_dtl_setup() {
	TUI_DEBUG=1 TUI_DEBUG_CATS="" _TUI_ROWS=24 _TUI_COLS=80 _TUI_FOOTER_ON=0 _TUI_FRAME="" _TUI_RUNNING=0
	_TUI_DBG_PAINTED="" _TUI_DTL_PAINTED="" _TUI_DTL_STAMP=""
	tui.debug.reset
}
_dtl_end() { tui.debug.devtools close; tui.debug.bar off; }

t_devtools_closed_by_default() {
	eq "0" "$_TUI_DTL_ON"
	eq "0" "$_TUI_DBG_DOCK"
}

t_devtools_open_reserves_rows_and_close_gives_them_back() {
	_dtl_setup
	tui.debug.devtools open
	_tui._root_h
	eq "8" "$_TUI_DBG_DOCK"
	eq "16" "${_TUI_P_H[root]}"
	tui.debug.devtools close
	_tui._root_h
	eq "24" "${_TUI_P_H[root]}"
}

t_devtools_dock_sits_above_strip_and_footer() {
	_dtl_setup
	_TUI_FOOTER_ON=1
	tui.debug.bar on
	tui.debug.devtools open
	_tui._root_h
	eq "14" "${_TUI_P_H[root]}"
	_tui_devtools.draw
	_dtl_end
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[15;1H'"'"'* ]]'
}

t_devtools_maximise_takes_everything_but_three_rows_and_restores() {
	_dtl_setup
	tui.debug.devtools open
	_tui_devtools.key m
	eq "21" "$_TUI_DBG_DOCK"
	_tui_devtools.key m
	eq "8" "$_TUI_DBG_DOCK"
	_dtl_end
}

t_devtools_dock_shrinks_to_fit_a_tiny_terminal() {
	_dtl_setup
	_TUI_ROWS=10
	tui.debug.devtools open
	eq "7" "$_TUI_DBG_DOCK"
	_dtl_end
}

t_devtools_f11_cycles_open_blur_focus_close() {
	_dtl_setup
	_tui_devtools.f11
	eq "1 1" "$_TUI_DTL_ON $_TUI_DTL_FOCUS"
	tui.debug.devtools blur
	eq "1 0" "$_TUI_DTL_ON $_TUI_DTL_FOCUS"
	_tui_devtools.f11
	eq "1 1" "$_TUI_DTL_ON $_TUI_DTL_FOCUS"
	_tui_devtools.f11
	eq "0 0" "$_TUI_DTL_ON $_TUI_DTL_FOCUS"
}

t_devtools_keys_are_bound_only_while_focused() {
	_dtl_setup
	tui.debug.devtools open
	ok '[[ -n "${_TUI_BIND[|left]:-}" && -n "${_TUI_BIND[|p]:-}" ]]'
	tui.debug.devtools blur
	ok '[[ -z "${_TUI_BIND[|left]:-}" && -z "${_TUI_BIND[|p]:-}" ]]'
	_dtl_end
}

t_devtools_tabs_wrap_with_arrows_and_jump_with_digits() {
	_dtl_setup
	_tui_devtools.key right
	eq "1" "$_TUI_DTL_TAB"
	_tui_devtools.key left
	_tui_devtools.key left
	eq "3" "$_TUI_DTL_TAB"
	_tui_devtools.key 3
	eq "2" "$_TUI_DTL_TAB"
}

t_devtools_events_show_newest_last_with_relative_time() {
	_dtl_setup
	tui.debug.event cache.page.miss home
	tui.debug.event page.visit "about hit 3ms"
	_tui_devtools.build 6
	eq "2" "${#_TUI_DTL_LINES[@]}"
	match "${_TUI_DTL_LINES[0]}" '^ +\+[0-9]+\.[0-9]{3}  cache\.page\.miss +home$'
	match "${_TUI_DTL_LINES[1]}" 'page\.visit +about hit 3ms$'
}

t_devtools_events_mark_misses_as_warnings() {
	_dtl_setup
	tui.debug.event cache.page.miss home
	tui.debug.event page.visit x
	_tui_devtools.build 6
	eq "1 0" "${_TUI_DTL_SEV[*]}"
}

t_devtools_events_scroll_back_shows_older_rows() {
	_dtl_setup
	local i
	for i in 1 2 3 4 5; do tui.debug.event e.x "n$i"; done
	_TUI_DTL_SCROLL=2
	_tui_devtools.build 2
	match "${_TUI_DTL_LINES[0]}" 'n2$'
	match "${_TUI_DTL_LINES[1]}" 'n3$'
}

t_devtools_events_scroll_is_clamped_to_the_oldest_row() {
	_dtl_setup
	tui.debug.event e.x a
	tui.debug.event e.x b
	_TUI_DTL_SCROLL=99
	_tui_devtools.build 4
	eq "0" "$_TUI_DTL_SCROLL"
}

t_devtools_pause_freezes_the_event_list() {
	_dtl_setup
	tui.debug.event e.x before
	_tui_devtools.key p
	tui.debug.event e.x after
	_tui_devtools.build 6
	eq "1" "${#_TUI_DTL_LINES[@]}"
	_tui_devtools.key p
	_tui_devtools.build 6
	eq "2" "${#_TUI_DTL_LINES[@]}"
}

t_devtools_filter_cycles_through_seen_categories() {
	_dtl_setup
	tui.debug.event cache.page.miss a
	tui.debug.event page.visit b
	_tui_devtools.key f
	eq "cache" "$_TUI_DTL_FILTER"
	_tui_devtools.build 6
	eq "1" "${#_TUI_DTL_LINES[@]}"
	_tui_devtools.key f
	eq "page" "$_TUI_DTL_FILTER"
	_tui_devtools.key f
	eq "" "$_TUI_DTL_FILTER"
}

t_devtools_clear_empties_events_and_counts() {
	_dtl_setup
	tui.debug.event e.x a
	_tui_devtools.key c
	eq "0" "${#_TUI_DBG_RING[@]}"
	eq "" "${_TUI_DBG_COUNT[e.x]:-}"
}

t_devtools_events_tab_says_so_when_empty() {
	_dtl_setup
	_tui_devtools.build 6
	match "${_TUI_DTL_LINES[0]}" 'no events yet'
}

t_devtools_pages_tab_lists_cached_and_building_pages() {
	_dtl_setup
	_TUI_CACHE_TOTAL=3 _TUI_CACHE_PAGE=([/a/home.xml]=sss) _TUI_LAZY_PENDING=(/a/about.xml) _TUI_LAZY_REFRESH=()
	_TUI_DBG_VISITS=([/a/home.xml]=2) _TUI_DBG_PAGE_LAST=([/a/home.xml]="hit 9ms")
	_TUI_DTL_TAB=1
	_tui_devtools.build 12
	match "${_TUI_DTL_LINES[0]}" 'cached 1/3'
	match "${_TUI_DTL_LINES[3]}" 'home +cached +0K +2 +hit 9ms$'
	match "${_TUI_DTL_LINES[2]}" 'about +building'
	eq "1" "${_TUI_DTL_SEV[2]}"
}

t_devtools_perf_tab_shows_span_stats_in_ms() {
	_dtl_setup
	_TUI_PERF_LOG=([layout]="1000 3000 ")
	_TUI_DTL_TAB=2
	_tui_devtools.build 12
	match "${_TUI_DTL_LINES[1]}" '^ +layout +3\.0 +2\.0 +3\.0 +2$'
}

t_devtools_counters_tab_lists_perf_counters_and_event_totals_sorted() {
	_dtl_setup
	_TUI_PERF_COUNTERS=([zeta]=1 [alpha]=7)
	tui.debug.event cache.page.miss x
	_TUI_DTL_TAB=3
	_tui_devtools.build 20
	match "${_TUI_DTL_LINES[1]}" 'alpha +7$'
	match "${_TUI_DTL_LINES[2]}" 'zeta +1$'
	match "${_TUI_DTL_LINES[4]}" 'cache\.page\.miss +1$'
}

t_devtools_other_tabs_scroll_from_the_top_and_clamp() {
	_dtl_setup
	_TUI_PERF_COUNTERS=([a]=1 [b]=2 [c]=3 [d]=4 [e]=5 [f]=6)
	_TUI_DTL_TAB=3
	_TUI_DTL_SCROLL=99
	_tui_devtools.build 3
	eq "3" "${#_TUI_DTL_LINES[@]}"
	eq "5" "$_TUI_DTL_SCROLL"
}

t_devtools_header_marks_the_active_tab_and_draws_the_body_rows() {
	_dtl_setup
	tui.debug.event e.x hello
	tui.debug.devtools open
	_tui_devtools.draw
	_dtl_end
	ok '[[ "$_TUI_FRAME" == *" 1 Events "* && "$_TUI_FRAME" == *" 4 Counters "* && "$_TUI_FRAME" == *hello* ]]'
}

t_devtools_unchanged_dock_adds_nothing_to_the_frame() {
	_dtl_setup
	tui.debug.devtools open
	_tui_devtools.draw
	_TUI_FRAME=""
	_tui_devtools.draw
	_dtl_end
	eq "" "$_TUI_FRAME"
}

t_devtools_new_event_repaints_the_dock() {
	_dtl_setup
	tui.debug.devtools open
	_tui_devtools.draw
	_TUI_FRAME=""
	tui.debug.event e.x fresh
	_tui_devtools.draw
	_dtl_end
	ok '[[ "$_TUI_FRAME" == *fresh* ]]'
}

t_devtools_snapshot_signature_changes_with_the_reserved_rows() {
	_dtl_setup
	tui.debug.devtools open
	eq "8" "$_TUI_DBG_ROWS"
	_dtl_end
	eq "0" "$_TUI_DBG_ROWS"
}
