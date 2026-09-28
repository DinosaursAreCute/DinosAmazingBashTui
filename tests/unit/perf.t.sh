# perf.t.sh - lib/perf.sh span/counter/report behaviour (stage 0.2).

t_perf_span_off_by_default_records_nothing() {
	_TUI_PERF_TRACKING=0
	tui.perf.reset
	_tui_perf.begin render
	_tui_perf.end render
	eq "" "${_TUI_PERF_LOG[render]:-}"
}

t_perf_span_on_records_one_duration() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_tui_perf.begin render
	_tui_perf.end render
	local -a vals=(${_TUI_PERF_LOG[render]})
	eq "1" "${#vals[@]}"
	_TUI_PERF_TRACKING=0
}

t_perf_span_end_without_begin_is_ignored() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_tui_perf.end never_begun
	eq "" "${_TUI_PERF_LOG[never_begun]:-}"
	_TUI_PERF_TRACKING=0
}

t_perf_counter_increments() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_tui_perf.count forks
	_tui_perf.count forks
	eq "2" "${_TUI_PERF_COUNTERS[forks]}"
	_TUI_PERF_TRACKING=0
}

t_perf_counter_with_explicit_n() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_tui_perf.count nodes_painted 7
	eq "7" "${_TUI_PERF_COUNTERS[nodes_painted]}"
	_TUI_PERF_TRACKING=0
}

t_perf_counter_off_by_default_records_nothing() {
	_TUI_PERF_TRACKING=0
	tui.perf.reset
	_tui_perf.count forks
	eq "" "${_TUI_PERF_COUNTERS[forks]:-}"
}

t_perf_report_lists_span_mean_p95_count() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_TUI_PERF_LOG[layout]="10 20 30 "
	local out
	out="$(tui.perf.report)"
	match "$out" $'span\tlayout\t20\t30\t3'
	_TUI_PERF_TRACKING=0
}

t_perf_report_lists_counters() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_TUI_PERF_COUNTERS[cache_hit]=5
	local out
	out="$(tui.perf.report)"
	match "$out" $'counter\tcache_hit\t5'
	_TUI_PERF_TRACKING=0
}

t_perf_begin_end_count_never_fail_when_tracking_is_off() {
	_TUI_PERF_TRACKING=0
	tui.perf.reset
	_tui_perf.begin render
	ok '(($? == 0))'
	_tui_perf.end render
	ok '(($? == 0))'
	_tui_perf.count forks
	ok '(($? == 0))'
}

t_perf_reset_clears_spans_and_counters() {
	_TUI_PERF_TRACKING=1
	_TUI_PERF_LOG[render]="5 "
	_TUI_PERF_COUNTERS[forks]=1
	tui.perf.reset
	eq "" "${_TUI_PERF_LOG[render]:-}"
	eq "" "${_TUI_PERF_COUNTERS[forks]:-}"
	_TUI_PERF_TRACKING=0
}
