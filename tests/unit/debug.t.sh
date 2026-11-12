# debug.t.sh - lib/debug.sh event bus: off by default, ring buffer, counters, category filter.

t_debug_event_off_records_nothing() {
	TUI_DEBUG=0
	tui.debug.event cache.page.miss home
	eq "0" "${#_TUI_DBG_RING[@]}"
	eq "" "${_TUI_DBG_COUNT[cache.page.miss]:-}"
}

t_debug_event_on_counts_and_records() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	tui.debug.event cache.page.miss home
	tui.debug.event cache.page.miss about
	eq "2" "${_TUI_DBG_COUNT[cache.page.miss]}"
	eq "2" "${#_TUI_DBG_RING[@]}"
	match "${_TUI_DBG_RING[1]}" ' cache\.page\.miss about$'
}

t_debug_category_filter_drops_other_categories() {
	TUI_DEBUG=1 TUI_DEBUG_CATS="render"
	tui.debug.event cache.page.miss home
	tui.debug.event render.slow 40ms
	eq "" "${_TUI_DBG_COUNT[cache.page.miss]:-}"
	eq "1" "${_TUI_DBG_COUNT[render.slow]}"
}

t_debug_ring_keeps_newest_when_over_budget() {
	TUI_DEBUG=1 TUI_DEBUG_CATS="" _TUI_DBG_RING_MAX=3
	local i
	for i in 1 2 3 4 5 6 7; do tui.debug.event e.x "$i"; done
	ok "((${#_TUI_DBG_RING[@]} <= 6))"
	match "${_TUI_DBG_RING[-1]}" ' e\.x 7$'
}

t_debug_enable_sets_flag_categories_and_perf_tracking() {
	TUI_DEBUG=0 _TUI_PERF_TRACKING=0
	tui.debug.enable "cache,render"
	eq "1" "$TUI_DEBUG"
	eq "cache,render" "$TUI_DEBUG_CATS"
	eq "1" "$_TUI_PERF_TRACKING"
}

t_debug_reset_clears_ring_and_counts() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	tui.debug.event e.x 1
	tui.debug.reset
	eq "0" "${#_TUI_DBG_RING[@]}"
	eq "" "${_TUI_DBG_COUNT[e.x]:-}"
}

t_debug_visit_hit_records_event_and_last_visit() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.visit /app/pages/home.xml hit "${EPOCHREALTIME//[!0-9]/}"
	eq "1" "${_TUI_DBG_COUNT[page.visit]}"
	match "$_TUI_DBG_LAST_VISIT" '^home hit [0-9]+ms$'
}

t_debug_first_visit_counts_prepared_pages_once_per_page() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	local t=${EPOCHREALTIME//[!0-9]/}
	_tui_debug.visit /a/home.xml hit "$t"
	_tui_debug.visit /a/home.xml miss "$t"
	_tui_debug.visit /a/about.xml miss "$t"
	eq "2" "$_TUI_DBG_FIRST_N"
	eq "1" "$_TUI_DBG_FIRST_HIT"
}

t_debug_visit_is_ignored_when_debug_is_off() {
	TUI_DEBUG=0
	_tui_debug.visit /a/home.xml hit 0
	eq "" "$_TUI_DBG_LAST_VISIT"
}

t_debug_reset_clears_visits() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.visit /a/home.xml hit "${EPOCHREALTIME//[!0-9]/}"
	tui.debug.reset
	eq "0" "$_TUI_DBG_FIRST_N"
	eq "" "$_TUI_DBG_LAST_VISIT"
}

t_debug_switch_records_page_and_total_time() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.switch /a/about.xml "${EPOCHREALTIME//[!0-9]/}"
	match "$_TUI_DBG_LAST_SWITCH" '^about [0-9]+ms$'
	eq "1" "${_TUI_DBG_COUNT[page.switch]}"
}

t_debug_input_done_records_what_ran_and_how_long() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.input_begin "key ctrl+p"
	_tui_debug.input_end
	match "$_TUI_DBG_LAST_INPUT" '^key ctrl\+p [0-9]+ms$'
	eq "1" "${_TUI_DBG_COUNT[input.done]}"
}

t_debug_input_end_without_begin_records_nothing() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.input_end
	eq "" "$_TUI_DBG_LAST_INPUT"
}

t_debug_input_end_closes_the_measurement_once() {
	TUI_DEBUG=1 TUI_DEBUG_CATS=""
	_tui_debug.input_begin "key a"
	_tui_debug.input_end
	_tui_debug.input_end
	eq "1" "${_TUI_DBG_COUNT[input.done]}"
}

t_debug_input_and_switch_are_ignored_when_off() {
	TUI_DEBUG=0
	_tui_debug.input_begin "key a"
	_tui_debug.input_end
	_tui_debug.switch /a/x.xml 0
	eq "" "$_TUI_DBG_LAST_INPUT$_TUI_DBG_LAST_SWITCH"
}
