# validate_async.t.sh - _tui_validate.begin / finish: validation runs in a background process while the caller works on
# something else, and finish brings its findings back; _tui_validate.gate stays begin + finish in one call.

_va_pages() { # -> _VA_FILES: a clean page, one with an unclosed tag, one with a duplicate id
	_VAD="$_T_ROOT/va_${RANDOM}${RANDOM}"
	mkdir -p "$_VAD"
	printf '%s\n' '<tui>' '  <pane id="root" split="v">' '    <button id="b" text="ok"/>' '  </pane>' '</tui>' >"$_VAD/a.xml"
	printf '%s\n' '<tui><pane id="root"><button id="b" text="x"/>' >"$_VAD/b.xml"
	printf '%s\n' '<tui><pane id="root"><button id="d" text="x"/><button id="d" text="y"/></pane></tui>' >"$_VAD/c.xml"
	_VA_FILES=("$_VAD/a.xml" "$_VAD/b.xml" "$_VAD/c.xml")
}

_va_clean_page() { # -> _VA_FILES: one valid page, no stamp yet
	_VAD="$_T_ROOT/va_${RANDOM}${RANDOM}"
	mkdir -p "$_VAD"
	printf '%s\n' '<tui>' '  <pane id="root" split="v">' '    <button id="b" text="ok"/>' '  </pane>' '</tui>' >"$_VAD/a.xml"
	_VA_FILES=("$_VAD/a.xml")
	rm -f "$TUI_HOME/cache/validated"
}

_va_record_pid() { # makes tui.validate.page note which process ran it
	eval "$(declare -f tui.validate.page | sed '1s/.*/_va_orig_page()/')"
	tui.validate.page() {
		printf '%s\n' "$BASHPID" >>"$_VAD/pids"
		_va_orig_page "$@"
	}
}

_va_restore_page() {
	unset -f tui.validate.page
	eval "$(declare -f _va_orig_page | sed '1s/.*/tui.validate.page()/')"
}

ti_validate_begin_runs_the_validation_in_another_process() {
	_va_pages
	_va_record_pid
	TUI_VALIDATE_JOBS=1 _tui_validate.begin 1 "${_VA_FILES[@]}"
	TUI_IGNORE_INVALID_XML=1 _tui_validate.finish 2>/dev/null
	local pid
	while read -r pid; do [[ "$pid" != "$BASHPID" ]] || {
		echo "parent ran a page"
		break
	}; done <"$_VAD/pids"
	eq "3" "$(wc -l <"$_VAD/pids")"
	_va_restore_page
}

ti_validate_finish_brings_back_the_findings_of_a_synchronous_run() {
	_va_pages
	TUI_VALIDATE_JOBS=1 tui.validate.files "${_VA_FILES[@]}"
	tui.validate.messages
	local want="$TUI_V_ERRORS $TUI_V_WARNINGS ${_TV_LINES[*]} ${!_TV_READ[*]}"
	_TV_F_SEV=() _TV_F_LOC=() _TV_F_MSG=() _TV_READ=() TUI_V_ERRORS=0 TUI_V_WARNINGS=0
	TUI_VALIDATE_JOBS=1 _tui_validate.begin 1 "${_VA_FILES[@]}"
	TUI_IGNORE_INVALID_XML=1 _tui_validate.finish 2>/dev/null
	tui.validate.messages
	eq "$want" "$TUI_V_ERRORS $TUI_V_WARNINGS ${_TV_LINES[*]} ${!_TV_READ[*]}"
	eq "1" "$((TUI_V_ERRORS > 0))"
	_TV_NOTIFY=""
}

ti_validate_finish_fails_on_an_error_and_ignore_invalid_xml_lets_the_start_go_on() {
	_va_pages
	TUI_VALIDATE_JOBS=1 _tui_validate.begin 1 "${_VA_FILES[@]}"
	_tui_validate.finish 2>/dev/null
	eq "1" "$?"
	TUI_VALIDATE_JOBS=1 _tui_validate.begin 1 "${_VA_FILES[@]}"
	TUI_IGNORE_INVALID_XML=1 _tui_validate.finish 2>/dev/null
	eq "0" "$?"
	_TV_NOTIFY=""
}

ti_validate_finish_stamps_a_clean_run_and_the_next_begin_has_nothing_to_do() {
	_va_clean_page
	_tui_validate.begin 1 "${_VA_FILES[@]}"
	_tui_validate.finish
	eq "0" "$?"
	_tui_validate.begin 1 "${_VA_FILES[@]}"
	eq "" "$_TV_JOB_PID" # the stamp is fresh: no process started
	eq "0" "$_TV_PENDING"
}

ti_validate_finish_without_begin_is_a_no_op() {
	_TV_PENDING=0
	_tui_validate.finish
	eq "0" "$?"
}

ti_validate_finish_validates_here_when_the_background_run_left_no_result() {
	_va_pages
	_TV_PAGES=("${_VA_FILES[@]}")
	_TV_PENDING=1 _TV_JOB_PID="" _TV_JOB_FILE="$_VAD/missing"
	TUI_VALIDATE_JOBS=1 _tui_validate.finish 2>/dev/null
	eq "1" "$?"
	eq "1" "$((TUI_V_ERRORS > 0))"
}

ti_validate_gate_is_begin_and_finish_in_the_calling_process() {
	_va_pages
	_va_record_pid
	TUI_VALIDATE_JOBS=1 _tui_validate.gate "${_VA_FILES[@]}" 2>/dev/null
	eq "1" "$?"
	local n=0 pid
	while read -r pid; do [[ "$pid" == "$BASHPID" ]] && ((n++)); done <"$_VAD/pids"
	eq "3" "$n"
	_va_restore_page
}
