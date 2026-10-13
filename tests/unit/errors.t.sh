# Captured stderr (lib/tui.sh, "ERRORS"): logged with context, one notification per distinct message.

_err_setup() {
	TUI_LOG_DIR="$_T_ROOT/log"
	_TUI_LOG_DIR_OK=""
	_TUI_ERR_SEEN=() _TUI_ERR_RING=() _TUI_ERR_TOASTED=0
}

t_errors_report_logs_message_location_and_context() {
	_err_setup
	TUI_EVENT_KEY=alt+left _TUI_ERR_ACTION="_tui_md.key_hist left"
	_tui_errors.report "lib/x.sh: line 481: _TUI_W_PANE: bad array subscript" ""
	local log
	log=$(<"$(tui.log.file)")
	match "$log" '\[error\] lib/x.sh: line 481: _TUI_W_PANE: bad array subscript'
	match "$log" 'at: lib/x.sh:481'
	match "$log" 'key=alt\+left action=_tui_md.key_hist left'
}

t_errors_the_same_message_is_counted_and_toasted_once() {
	_err_setup
	local i
	for i in 1 2 3; do _tui_errors.report "f.sh: line 1: boom" ""; done
	eq 1 "$(tui.errors.count)"
	eq 1 "$_TUI_ERR_TOASTED"
	eq 3 "${#_TUI_ERR_RING[@]}"
	local log
	log=$(<"$(tui.log.file)")
	eq 1 "$(grep -c 'f.sh: line 1: boom' <<<"$log")"
}

t_errors_a_repeat_is_logged_again_at_ten() {
	_err_setup
	local i
	for i in {1..10}; do _tui_errors.report "f.sh: line 2: again" ""; done
	match "$(<"$(tui.log.file)")" 'again \(x10\)'
}

t_errors_distinct_messages_each_get_a_toast() {
	_err_setup
	_tui_errors.report "a.sh: line 1: one" ""
	_tui_errors.report "b.sh: line 2: two" ""
	eq 2 "$_TUI_ERR_TOASTED"
	eq 2 "$(tui.errors.count)"
}

t_errors_stderr_is_captured_and_reported_from_the_tick() {
	_err_setup
	tui.errors.capture on
	printf 'q.sh: line 9: nope\n' >&2
	_tui_errors.drain
	tui.errors.capture off
	match "$(<"$(tui.log.file)")" 'q.sh: line 9: nope'
	eq 0 "$_TUI_ERR_ON"
}

t_errors_an_xtrace_prefix_becomes_the_stack() {
	_err_setup
	tui.errors.capture on
	printf '\x1einner mid outer @ x.sh:5\x1f echo hi\n' >&2
	printf 'x.sh: line 5: oops\n' >&2
	_tui_errors.drain
	tui.errors.capture off
	match "$(<"$(tui.log.file)")" 'stack: inner < mid < outer @ x.sh:5'
}

t_errors_capture_off_without_on_is_harmless() {
	tui.errors.capture off
	eq 0 $?
}

t_errors_the_message_hides_the_install_path() {
	_err_setup
	_tui_errors.report "$TUI_ROOT/lib/y.sh: line 4: z" ""
	match "$(<"$(tui.log.file)")" '\[error\] lib/y.sh: line 4: z'
}

t_errors_a_real_bad_subscript_and_a_missing_command_are_captured() {
	_err_setup
	tui.errors.capture on
	local -A bad=([a]=1)
	local key=""
	: "${bad[$key]}"
	dabt_no_such_command_for_the_test
	ls /dabt_no_such_directory_for_the_test
	_tui_errors.drain
	tui.errors.capture off
	local log
	log=$(<"$(tui.log.file)")
	match "$log" 'bad array subscript'
	match "$log" 'dabt_no_such_command_for_the_test: command not found'
	match "$log" 'dabt_no_such_directory_for_the_test'
	eq 3 "$(tui.errors.count)"
}
