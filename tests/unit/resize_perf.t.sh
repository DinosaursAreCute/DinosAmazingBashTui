# resize_perf.t.sh - a held arrow in resize mode is one batch: merged repeats move like the same number of single presses.

source "$REPO/share/demo/workspace_callbacks.sh"

_rzp_build() {
	tui.reset_ui
	_TUI_ROWS=40 _TUI_COLS=140
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=40 _TUI_P_W[root]=140
	_TUI_P_BORDER[root]=single
	tui.load "$REPO/share/demo/workspace.xml" >/dev/null 2>&1
	_tui._layout root
	_tui_resize.enter services
	_TUI_FRAME_REQ=0 _TUI_RUNNING=0 _TUI_PERF_TRACKING=0
	_TUI_REPAINT=() _TUI_REPAINT_OLD=()
}

_rzp_load() { _t_fixture rzp _rzp_build; }

_rzp_state() {
	local p out=""
	for p in "${_TUI_P_ALL[@]}"; do out+="$p=${_TUI_P_ROW[$p]},${_TUI_P_COL[$p]},${_TUI_P_H[$p]},${_TUI_P_W[$p]};"; done
	printf '%s' "$out"
}

ti_resize_coalesced_presses_move_like_single_presses() {
	local a b k
	for k in "right 5 1" "left 3 1" "shift+right 2 5" "right 300 1"; do
		set -- $k
		_rzp_load
		local i
		for ((i = 0; i < $2; i++)); do _tui_resize.key "$1"; done
		a="$(_rzp_state)"
		_rzp_load
		_tui_resize.key "$1" "$2"
		b="$(_rzp_state)"
		eq "$a" "$b"
	done
}

ti_resize_held_arrow_coalesces_in_resize_mode_only() {
	_rzp_load
	TUI_INPUT_COALESCE=1 _TUI_PENDING_INPUT=""
	_tui_input.coalesce_key "" "[C" < <(printf '\e[C\e[C\e[C')
	eq 4 "$_TUI_REPEAT"
	_tui_resize.leave
	_tui_input.coalesce_key "" "[C" < <(printf '\e[C\e[C\e[C')
	eq 1 "$_TUI_REPEAT"
}
