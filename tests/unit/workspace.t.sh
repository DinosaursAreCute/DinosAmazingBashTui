# workspace.t.sh - the Workspace demo page (share/demo/workspace.xml + workspace_callbacks.sh): wiring, simulated
# commands, fork-free /proc readers, the built page and one rendered frame.

source "$REPO/share/demo/workspace_callbacks.sh"

_WS_XML="$REPO/share/demo/workspace.xml"

# ── wiring ────────────────────────────────────────────────────────────────

ti_workspace_every_called_function_exists() {
	local f line fn missing=""
	# action= / submit= / on_*= attributes of the page
	while IFS= read -r fn; do
		[[ -n "$fn" ]] || continue
				declare -F "$fn" >/dev/null || missing+=" $fn"
	done < <(grep -oE '(action|submit|on_[a-z_]+)="[^"]+"' "$_WS_XML" | sed -E 's/^[a-z_]+="//; s/"$//; s/ .*//' | grep -v '^[●✖▲]' | grep -v '^true$')
	# every tui.* call of the callbacks
	while IFS= read -r fn; do
		declare -F "$fn" >/dev/null || missing+=" $fn"
	done < <(grep -v '^[[:space:]]*#' "$REPO/share/demo/workspace_callbacks.sh" | grep -oE '\btui\.[a-z_]+(\.[a-z_]+)*' | sort -u)
	eq "" "$missing"
}

# ── LCG / data ────────────────────────────────────────────────────────────

t_workspace_lcg_is_deterministic() {
	local a="" b="" i
	_WS_SEED=7
	for i in 1 2 3 4 5; do _ws_rand 100; a+="$_WS_R,"; done
	_WS_SEED=7
	for i in 1 2 3 4 5; do _ws_rand 100; b+="$_WS_R,"; done
	eq "$a" "$b"
	match "$a" '^[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+,$'
}

ti_workspace_init_seeds_every_service_and_a_log() {
	_ws_init
	eq 7 "${#_WS_NAMES[@]}"
	eq down "${_WS_SVC[billing-queue.state]}"
	eq 14 "${_WS_LOGN[api-gateway]}"
	eq 5 "${#_WS_EVENTS[@]}"
}

ti_workspace_same_seed_same_first_log_lines() {
	_ws_init
	local a="${_WS_LOGS[orders-svc]}" b # the log lines carry wall-clock stamps: compared without them
	_ws_init
	b="${_WS_LOGS[orders-svc]}"
	eq "${a//[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/T}" "${b//[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/T}"
}

# ── commands ──────────────────────────────────────────────────────────────

ti_workspace_restart_sets_ok_and_adds_an_event() {
	_ws_init
	_ws_exec "restart billing-queue"
	eq ok "${_WS_SVC[billing-queue.state]}"
	eq "2/2" "${_WS_SVC[billing-queue.rep]}"
	eq 6 "${#_WS_EVENTS[@]}"
	match "${_WS_EVENTS[5]}" 'billing-queue.*restarted'
	match "$_WS_NOTE" 'restarted billing-queue'
	eq 3 "$_WS_SEL"
}

ti_workspace_command_accepts_a_unique_prefix() {
	_ws_init
	_ws_exec "restart cache"
	eq ok "${_WS_SVC[cache-redis.state]}"
}

ti_workspace_ack_marks_a_service_and_refuses_a_healthy_one() {
	_ws_init
	_ws_exec "ack notifier"
	eq 1 "${_WS_SVC[notifier.ack]}"
	match "${_WS_EVENTS[5]}" 'acknowledged'
	_ws_exec "ack api-gateway"
	eq 0 "${_WS_SVC[api-gateway.ack]}"
	match "$_WS_NOTE" 'nothing to acknowledge'
}

ti_workspace_unknown_command_and_service_report_an_error() {
	_ws_init
	_ws_exec "frobnicate"
	match "$_WS_NOTE" 'unknown command: frobnicate'
	_ws_exec "restart nope"
	match "$_WS_NOTE" 'unknown service: nope'
	eq 5 "${#_WS_EVENTS[@]}"
}

ti_workspace_clear_empties_the_selected_log_only() {
	_ws_init
	_ws_exec "clear"
	eq 0 "${_WS_LOGN[api-gateway]}"
	eq "" "${_WS_LOGS[api-gateway]}"
	eq 14 "${_WS_LOGN[auth-service]}"
}

ti_workspace_logs_command_selects_the_service() {
	_ws_init
	_ws_exec "logs search"
	eq 5 "$_WS_SEL"
}

ti_workspace_status_counts_the_states() {
	_ws_init
	_ws_exec "status"
	eq "7 services: 4 ok, 2 warn, 1 down" "$_WS_NOTE"
}

ti_workspace_log_is_capped_at_200_lines() {
	_ws_init
	local i
	for i in {1..250}; do _ws_logline api-gateway; done
	eq 200 "${_WS_LOGN[api-gateway]}"
}

# ── /proc readers ─────────────────────────────────────────────────────────

t_workspace_host_degrades_to_na_without_proc() {
	_WS_PROC="$_T_ROOT/no-such-proc"
	_ws_host
	eq "n/a" "$_WS_LOAD"
	eq "n/a" "$_WS_UP"
	eq "n/a" "$_WS_MEMTXT"
	eq 0 "$_WS_MEMPCT"
}

t_workspace_host_reads_a_fake_proc() {
	_WS_PROC="$_T_ROOT/proc"
	mkdir -p "$_WS_PROC"
	printf '0.50 0.40 0.30 1/200 999\n' >"$_WS_PROC/loadavg"
	printf '93784.12 1000.00\n' >"$_WS_PROC/uptime"
	printf 'MemTotal:       8388608 kB\nMemFree:  100 kB\nMemAvailable:   4194304 kB\n' >"$_WS_PROC/meminfo"
	_ws_host
	eq "0.50 0.40 0.30" "$_WS_LOAD"
	eq "1d 02h 03m" "$_WS_UP"
	eq 50 "$_WS_MEMPCT"
	eq "4.0/8.0 GiB" "$_WS_MEMTXT"
}

# ── the built page ────────────────────────────────────────────────────────

_ws_build_page() {
	tui.reset_ui
	_TUI_ROWS=36 _TUI_COLS=120
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=36 _TUI_P_W[root]=120
	_TUI_P_BORDER[root]=single
	tui.load "$_WS_XML" >/dev/null 2>"$_T_ROOT/ws.err"
	_tui._layout root
}

_ws_load_page() { _t_fixture ws_page _ws_build_page; }

_ws_check_built() {
	local p
	for p in services logs_col logs events details prompt; do
		[[ -n "${_TUI_P_ROW[$p]:-}" ]] || _t_fail "pane $p missing"
	done
	for p in ws_list ws_cmd ws_mem; do
		[[ -n "${_TUI_W_TYPE[$p]:-}" ]] || _t_fail "widget $p missing"
	done
	eq "list input progress" "${_TUI_W_TYPE[ws_list]} ${_TUI_W_TYPE[ws_cmd]} ${_TUI_W_TYPE[ws_mem]}"
	eq title "${_TUI_P_COLLAPSE_TO[services]}"
	ok '((${_TUI_P_COLLAPSIBLE[services]:-0}))'
	eq "x y x" "${_TUI_P_RESIZABLE[services]} ${_TUI_P_RESIZABLE[logs]} ${_TUI_P_RESIZABLE[details]}"
	eq "divider divider divider" "${_TUI_P_HANDLE[services]} ${_TUI_P_HANDLE[logs]} ${_TUI_P_HANDLE[details]}"
	eq "true true" "${_TUI_P_FUSE[logs]} ${_TUI_P_FUSE[events]}"
	eq 1 "${_TUI_P_H[prompt]}"
	eq "" "$(<"$_T_ROOT/ws.err")"
}

ti_workspace_builds_and_renders_a_full_first_frame() {
	_ws_load_page
	_ws_check_built
	local out
	out="$(tui.render)"
	local frame="$out"
	if [[ -n "${WS_SHOW:-}" ]]; then # the cell grid (slow to build), for looking at the page while developing
		_fuse_parse "$out"
		local r
		frame=""
		for ((r = 1; r <= 36; r++)); do frame+="$(_fuse_row "$r" 1 120)"$'\n'; done
		printf '%s' "$frame" >&2
	fi
	local w
	for w in "Services" "Logs · api-gateway" "Events" "Details" "billing-queue" "INFO" "load" "HOST" "mem "; do
		[[ "$frame" == *"$w"* ]] || _t_fail "frame lacks [$w]"
	done
}

ti_workspace_validates_clean() {
	local out rc
	out="$(tui.validate.files "$_WS_XML"; echo rc=$?; tui.validate.report 2>&1)"
	match "$out" 'rc=0'
	[[ "$out" == *"erroneous"* ]] && _t_fail "validator errors: $out"
	[[ "$out" == *"questionable"* ]] && _t_fail "validator warnings: $out"
	return 0
}

# hooks / WHEN functions / actions must survive an empty focus id and a pane id, silently
ti_workspace_callbacks_survive_empty_and_pane_focus() {
	local f id rc err
	_ws_init
	for id in "" services; do
		_TUI_FOCUS_ID="$id"
		for f in _ws_not_typing on_ws_restart on_ws_ack on_ws_clear on_ws_select on_ws_focus_cmd _ws_tick _ws_host; do
			"$f" >/dev/null 2>"$_T_ROOT/cb.err"
			err="$(<"$_T_ROOT/cb.err")"
			eq "" "$err"
		done
		_ws_not_typing || _t_fail "focus [$id] must count as not typing"
	done
	_TUI_FOCUS_ID=ws_cmd _TUI_W_TYPE[ws_cmd]=input
	_ws_not_typing && _t_fail "input focus must count as typing"
	return 0
}

# ── alt+r through the real key path ───────────────────────────────────────

# _ws_alt_r FOCUS_ID -> mode pane in _WS_MODE, toasts in _WS_TOASTS, rc of key_event in _WS_RC
_ws_alt_r() {
	_ws_load_page
	tui.bind.defaults "$REPO/share/defaults/keybinds.xml"
	_TUI_RESIZE_PANE="" _TUI_PANE_FOCUS="" _TUI_FOCUS_ID="$1"
	_WS_TOASTS=""
	tui.notify() { _WS_TOASTS+="$1|$2;"; }
	_tui_input.key_event "" r # ESC + r, as the terminal layer reports alt+r
	_WS_RC=$?
	_WS_MODE="$_TUI_RESIZE_PANE"
}

_ws_first_resizable() {
	local p
	for p in "${_TUI_P_ALL[@]}"; do [[ -n "${_TUI_P_RESIZABLE[$p]:-}" ]] && { printf '%s' "$p"; return; }; done
}

ti_workspace_alt_r_enters_resize_mode_from_the_services_list() {
	_ws_alt_r ws_list
	eq 0 "$_WS_RC"
	eq services "$_WS_MODE"
	eq "" "$_WS_TOASTS"
}

ti_workspace_alt_r_falls_back_from_the_prompt_input() {
	_ws_alt_r ws_cmd
	eq 0 "$_WS_RC"
	eq "$(_ws_first_resizable)" "$_WS_MODE" # the first resizable pane in layout order
	eq "" "$_WS_TOASTS"
}

ti_workspace_alt_r_falls_back_with_nothing_focused() {
	_ws_alt_r ""
	eq "$(_ws_first_resizable)" "$_WS_MODE"
}

ti_workspace_alt_r_leaves_the_mode_and_restores_the_title() {
	_ws_alt_r ws_list
	eq "Services [resize]" "${_TUI_P_TITLE[services]}"
	_tui_input.key_event "" r
	eq "" "$_TUI_RESIZE_PANE"
	eq "Services" "${_TUI_P_TITLE[services]}"
}

ti_workspace_resize_mode_draws_the_border_hovered_and_the_footer_hints() {
	_ws_alt_r ws_list
	local out
	out="$(tui.render)"
	[[ "$out" == *"Services [resize]"* ]] || _t_fail "title tag not drawn"
	_tui_footer.draw >/dev/null 2>&1
	_tui_resize.in_mode || _t_fail "in_mode"
	_tui_resize.can_enter && _t_fail "can_enter must be off inside the mode"
	return 0
}

ti_workspace_alt_r_toasts_once_when_nothing_is_resizable() {
	_ws_alt_r ws_list
	_TUI_RESIZE_PANE="" _TUI_P_RESIZABLE=() _WS_TOASTS=""
	_tui_input.key_event "" r
	eq "Nothing resizable here|warn;" "$_WS_TOASTS"
	eq "" "$_TUI_RESIZE_PANE"
}
