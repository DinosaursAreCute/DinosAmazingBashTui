# job.t.sh - lib/tui_job.sh: background work with a delayed spinner and a completion callback.
# The loop is not running here, so the tests call _tui_job.tick themselves (as the main loop does once per pass).

_jb_done() { _JB_LOG+="done:$1:$2:$(<"$3");"; }
_jb_work_ok() { printf 'result %s' "$1"; }
_jb_work_fail() {
	printf 'partial'
	return 3
}
_jb_work_slow() {
	sleep 0.12
	printf slow
}
_jb_work_state() {
	_JB_STATE=changed-in-child
	printf x
}

# _jb_wait ID [TRIES] : tick until the job has been finished (or give up after TRIES x 20 ms)
_jb_wait() {
	local i
	for ((i = 0; i < ${2:-100}; i++)); do
		tui.job.running "$1" || return 0
		_tui_job.tick
		sleep 0.01
	done
	return 1
}

_jb_reset() { _JB_LOG="" _JB_STATE=""; }

ti_job_runs_work_in_the_background_and_hands_over_its_output() {
	_jb_reset
	tui.job.run j1 _jb_work_ok _jb_done 42
	ok 'tui.job.running j1'
	ok '_jb_wait j1'
	eq "done:j1:0:result 42;" "$_JB_LOG"
	ok '! tui.job.running j1'
}

ti_job_work_cannot_change_the_main_shells_state() {
	_jb_reset
	tui.job.run j1 _jb_work_state _jb_done
	_jb_wait j1
	eq "" "$_JB_STATE"
}

ti_job_nonzero_exit_status_reaches_the_done_function() {
	_jb_reset
	tui.job.run j1 _jb_work_fail _jb_done
	_jb_wait j1
	eq "done:j1:3:partial;" "$_JB_LOG"
}

ti_job_done_runs_once_and_its_temp_files_are_emptied() {
	_jb_reset
	tui.job.run j1 _jb_work_ok _jb_done 1
	local files="${_TJ_FILES[j1]}"
	_jb_wait j1
	_tui_job.tick
	_tui_job.tick
	eq "done:j1:0:result 1;" "$_JB_LOG"
	ok '[[ ! -s "${files}out" && ! -s "${files}err" ]]' # nothing left to read; the files go with the root at exit
}

ti_job_shutdown_removes_the_temp_root_and_stops_pending_jobs() {
	tui.job.run j1 _jb_work_slow _jb_done
	local root="$_TJ_ROOT" pid="${_TJ_PID[j1]}"
	_tui_job.shutdown
	ok '[[ ! -e "$root" ]]'
	eq "" "$_TJ_ROOT"
	sleep 0.05
	ok '! kill -0 "$pid" 2>/dev/null'
}

ti_job_spinner_appears_only_after_the_delay() {
	_jb_reset
	tui.job.run --delay 60000 j1 _jb_work_slow _jb_done
	_tui_job.tick
	eq 0 "$_TJ_ON" # far from the delay
	tui.job.cancel j1
	tui.job.run --delay 0 j1 _jb_work_slow _jb_done
	_tui_job.tick
	eq 1 "$_TJ_ON"
	ok '[[ " ${_TUI_FL_ORDER[*]} " == *" _tui_job.spinner_draw "* ]]'
	tui.job.cancel j1
	eq 0 "$_TJ_ON"
	ok '[[ " ${_TUI_FL_ORDER[*]} " != *" _tui_job.spinner_draw "* ]]'
}

ti_job_spinner_is_gone_before_the_done_function_runs() {
	_jb_reset
	_jb_done_spin() { _JB_LOG+="on=$_TJ_ON;overlay=${_TUI_FL_ORDER[*]};"; }
	tui.job.run --delay 0 j1 _jb_work_slow _jb_done_spin
	_tui_job.tick # past the delay: the spinner is on
	eq 1 "$_TJ_ON"
	_jb_wait j1
	eq "on=0;overlay=${_TUI_FL_ORDER[*]};" "$_JB_LOG"
	ok '[[ "$_JB_LOG" != *_tui_job.spinner_draw* ]]'
}

ti_job_spinner_draw_shows_a_glyph_and_the_label_top_right() {
	_TUI_COLS=80
	tui.job.run --delay 0 --label "Building page" j1 _jb_work_slow _jb_done
	_tui_job.tick
	_TUI_FRAME=""
	_tui_job.spinner_draw
	match "$_TUI_FRAME" "Building page"
	match "$_TUI_FRAME" $'\e\\[1;[0-9]+H' # on row 1
	tui.job.cancel j1
}

ti_job_cancel_stops_the_work_and_skips_the_done_function() {
	_jb_reset
	tui.job.run j1 _jb_work_slow _jb_done
	local pid="${_TJ_PID[j1]}"
	ok 'tui.job.cancel j1'
	ok '! tui.job.running j1'
	ok '! tui.job.cancel j1' # nothing left to cancel
	sleep 0.05
	_tui_job.tick
	eq "" "$_JB_LOG"
}

ti_job_same_id_replaces_the_pending_job() {
	_jb_reset
	tui.job.run j1 _jb_work_slow _jb_done
	tui.job.run j1 _jb_work_ok _jb_done 7
	_jb_wait j1
	eq "done:j1:0:result 7;" "$_JB_LOG"
}

ti_job_rejects_missing_or_undefined_functions() {
	tui.job.run j1 no_such_fn _jb_done 2>/dev/null && return 1
	tui.job.run j1 _jb_work_ok no_such_done 2>/dev/null && return 1
	tui.job.run --delay abc j1 _jb_work_ok _jb_done 2>/dev/null && return 1
	return 0
}

ti_job_two_jobs_finish_independently() {
	_jb_reset
	tui.job.run a _jb_work_ok _jb_done 1
	tui.job.run b _jb_work_ok _jb_done 2
	_jb_wait a
	_jb_wait b
	match "$_JB_LOG" "done:a:0:result 1;"
	match "$_JB_LOG" "done:b:0:result 2;"
}

ti_page_rebuild_builds_in_the_background_then_goes_to_the_page_once() {
	local f="$_T_ROOT/rb.xml" gotos=""
	printf '<tui><pane id="root"><label id="l" text="x"/></pane></tui>' >"$f"
	local saved
	saved="$(declare -f tui.goto)"
	tui.goto() { gotos+="$1;"; }
	tui.reset_ui
	_TUI_MARKUP_FILE="$f"
	tui.page.rebuild --delay 0 "$f"
	ok 'tui.job.running "page:$f"'
	eq "" "$gotos" # nothing shown while it is being calculated
	_jb_wait "page:$f" 300
	eq "$f;" "$gotos"
	ok '[[ -n "${_TUI_CACHE_PAGE[$f]:-}" ]]'
	eval "$saved"
}

ti_page_rebuild_does_not_yank_the_user_back_from_another_page() {
	local f="$_T_ROOT/rb2.xml" gotos=""
	printf '<tui><pane id="root"><label id="l" text="x"/></pane></tui>' >"$f"
	local saved
	saved="$(declare -f tui.goto)"
	tui.goto() { gotos+="$1;"; }
	_TUI_MARKUP_FILE="$_T_ROOT/other.xml"
	tui.page.rebuild "$f"
	_jb_wait "page:$f" 300
	eq "" "$gotos"
	ok '[[ -n "${_TUI_CACHE_PAGE[$f]:-}" ]]'
	eval "$saved"
}

t_page_rebuild_failure_keeps_the_page_and_reports_why() {
	local f="$_T_ROOT/rb3.xml" toasts=""
	TUI_JOB_PREFIX="$_T_ROOT/jobfiles."
	printf 'unterminated tag\nsecond line\n' >"${TUI_JOB_PREFIX}err"
	local saved_n saved_g
	saved_n="$(declare -f tui.notify)" saved_g="$(declare -f tui.goto)"
	tui.notify() { toasts+="$1|$2;"; }
	tui.goto() { toasts+="GOTO;"; }
	_TUI_MARKUP_FILE="$f"
	_tui_job.page_done "page:$f" 1 /dev/null
	eval "$saved_n"
	eval "$saved_g"
	TUI_JOB_PREFIX=""
	eq "Could not build rb3.xml: unterminated tag|error;" "$toasts" # no GOTO: the old page stays
}

ti_job_runs_in_the_foreground_when_background_jobs_are_off() {
	_jb_reset
	TUI_JOB_BACKGROUND=0 tui.job.run j9 _jb_work_fail _jb_done
	TUI_JOB_BACKGROUND=0 tui.job.run j8 _jb_work_state _jb_done
	eq "done:j9:3:partial;done:j8:0:x;" "$_JB_LOG" # finished before tui.job.run returned, same arguments to DONEFN
	ok '! tui.job.running j9'
	eq "" "$_JB_STATE" # still a child process: the work cannot change this shell
}
