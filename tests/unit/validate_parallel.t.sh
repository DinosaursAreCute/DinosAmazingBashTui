# validate_parallel.t.sh - tui.validate.files: pages validate in parallel workers, results merge in page order.

_vp_pages() { # writes three pages (clean, error, duplicate id) -> _VP_FILES
	_VPD="$_T_ROOT/vp_${RANDOM}${RANDOM}"
	mkdir -p "$_VPD"
	printf '%s\n' '<tui><pane id="root"><button id="b" text="ok"/></pane></tui>' >"$_VPD/a.xml"
	printf '%s\n' '<tui><pane id="root"><button id="b" text="x"/>' >"$_VPD/b.xml"
	printf '%s\n' '<tui><pane id="root"><button id="d" text="x"/><button id="d" text="y"/></pane></tui>' >"$_VPD/c.xml"
	_VP_FILES=("$_VPD/a.xml" "$_VPD/b.xml" "$_VPD/c.xml")
}

_vp_run() { # JOBS -> _VP_OUT: status, counts, messages and files read, as one string
	local rc=0
	TUI_VALIDATE_JOBS="$1" tui.validate.files "${_VP_FILES[@]}" || rc=$?
	tui.validate.messages
	local IFS=$'\n'
	_VP_OUT="$rc $TUI_V_ERRORS $TUI_V_WARNINGS ${_TV_LINES[*]} ${!_TV_READ[*]}"
}

ti_validate_parallel_result_equals_serial_result() {
	_vp_pages
	_vp_run 1
	local serial="$_VP_OUT"
	_vp_run 3
	eq "$serial" "$_VP_OUT"
	eq "1" "$((${#_TV_LINES[@]} > 0))"
}

ti_validate_parallel_runs_each_page_in_its_own_process() {
	_vp_pages
	eval "$(declare -f tui.validate.page | sed '1s/.*/_vp_orig_page()/')"
	tui.validate.page() {
		printf '%s\n' "$BASHPID" >>"$_VPD/pids"
		_vp_orig_page "$@"
	}
	TUI_VALIDATE_JOBS=3 tui.validate.files "${_VP_FILES[@]}"
	local -A seen=()
	local pid
	while read -r pid; do seen[$pid]=1; done <"$_VPD/pids"
	eq "3" "${#seen[@]}"
	eq "" "${seen[$BASHPID]:-}"
	unset -f tui.validate.page
	eval "$(declare -f _vp_orig_page | sed '1s/.*/tui.validate.page()/')"
}

ti_validate_single_job_runs_in_this_shell() {
	_vp_pages
	_VP_PID=""
	eval "$(declare -f tui.validate.page | sed '1s/.*/_vp_orig_page()/')"
	tui.validate.page() {
		_VP_PID="$BASHPID"
		_vp_orig_page "$@"
	}
	TUI_VALIDATE_JOBS=1 tui.validate.files "${_VP_FILES[@]}"
	eq "$BASHPID" "$_VP_PID"
	unset -f tui.validate.page
	eval "$(declare -f _vp_orig_page | sed '1s/.*/tui.validate.page()/')"
}
