# demo_refresh_jobs.t.sh - demo pages refresh on tui.every jobs (batched, wall-clock) and skip unchanged redraws.

source "$REPO/share/demo/monitor_callbacks.sh"
source "$REPO/share/demo/widgets_callbacks.sh"

ti_monitor_visit_registers_one_refresh_job_at_the_default_interval() {
	_MON_REFRESH_S=1
	_TA_IDS=() _TA_FN=() _TA_INT=()
	on_monitor_visit
	eq "mon_refresh_job" "${_TA_IDS[*]}"
	eq "_mon_refresh_job" "${_TA_FN[mon_refresh_job]}"
	eq 1000 "${_TA_INT[mon_refresh_job]}"
}

ti_monitor_interval_input_reschedules_the_job_without_a_second_one() {
	_TA_IDS=() _TA_FN=() _TA_INT=()
	_TUI_RUNNING=0
	on_monitor_visit
	on_monitor_set_interval x 0.5
	eq "mon_refresh_job" "${_TA_IDS[*]}"
	eq 500 "${_TA_INT[mon_refresh_job]}"
}

ti_monitor_has_no_main_loop_tick_hook() {
	eq "" "${_TUI_TICK_FN:-}"
}

ti_widget_status_tick_draws_an_unchanged_line_once() {
	local draws=0
	_tui._draw_widget() { ((draws++)); }
	_TUI_W_TYPE[wx_stat1]=label
	_TUI_RUNNING=1
	tui.get.focused() { printf ''; }
	wx_status_tick
	wx_status_tick
	wx_status_tick
	eq 1 "$draws"
}

ti_widget_job_step_counts_without_reading_the_widget_back() {
	tui.progress.set() { _seen="$2"; }
	tui.every.cancel() { :; }
	tui.notify() { :; }
	_WX_JOB_PCT=0
	wx_job_step
	wx_job_step
	eq 8 "$_seen"
}
