# Jobs due at once (lib/tui_api.sh): the main loop must not wait out its slow poll before a new job's first run.

_jd_ran=0
_jd_job() { _jd_ran=$((_jd_ran + 1)); }

t_job_a_new_every_job_is_due_at_once() {
	_TA_DUE_NOW=0
	tui.every 1 _jd_job jd_every
	eq 1 "$_TA_DUE_NOW"
}

t_job_the_tick_runs_the_due_job_and_clears_the_flag() {
	_jd_ran=0
	tui.every 1 _jd_job jd_every
	_tui_api._tick
	eq 1 "$_jd_ran"
	eq 0 "$_TA_DUE_NOW"
}

t_job_a_delayed_after_job_is_not_due_at_once() {
	_TA_DUE_NOW=0
	tui.after 5 _jd_job jd_after
	eq 0 "$_TA_DUE_NOW"
}

t_job_resuming_a_paused_job_makes_it_due_at_once() {
	tui.every 1 _jd_job jd_every
	_tui_api._tick
	tui.every.pause jd_every
	eq 0 "$_TA_DUE_NOW"
	tui.every.resume jd_every
	eq 1 "$_TA_DUE_NOW"
}
