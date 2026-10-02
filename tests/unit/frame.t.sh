# frame.t.sh - tui.frame.request: redraw requests coalesce into one frame per loop iteration (stage 2B).

t_frame_request_sets_the_flag_without_painting() {
	_TUI_FRAME_REQ=0
	local out
	tui.frame.request >"$_T_ROOT/fr.out"
	eq "" "$(<"$_T_ROOT/fr.out")"
	eq 1 "$_TUI_FRAME_REQ"
}

t_frame_present_runs_one_relayout_for_many_requests() {
	_FR_N=0
	local _orig
	_orig="$(declare -f tui.relayout)"
	tui.relayout() { _FR_N=$((_FR_N + 1)); }
	_TUI_FRAME_REQ=0
	tui.frame.request
	tui.frame.request
	tui.frame.request
	_tui.frame_present
	_tui.frame_present
	eval "$_orig"
	eq 1 "$_FR_N"
	eq 0 "$_TUI_FRAME_REQ"
}

t_frame_present_without_request_does_nothing() {
	_FR_N=0
	local _orig
	_orig="$(declare -f tui.relayout)"
	tui.relayout() { _FR_N=$((_FR_N + 1)); }
	_TUI_FRAME_REQ=0
	_tui.frame_present
	eval "$_orig"
	eq 0 "$_FR_N"
}

t_frame_immediate_render_satisfies_a_pending_request() {
	_TUI_FRAME_REQ=1
	tui.render >/dev/null 2>&1
	eq 0 "$_TUI_FRAME_REQ"
}
