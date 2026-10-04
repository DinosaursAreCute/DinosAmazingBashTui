#!/usr/bin/env bash
# tui_exec.sh - background execution: tui.exec runs a command as its own tracked instance and streams it into a pane.
#
#   tui.exec CMD OUT_PANE [CTL_PANE]    starts CMD as a tracked instance; its id is left in $_TUI_EXEC_LAST_ID
#   tui.exec.cancel_pane PANE           cancels the instances feeding PANE

# ═══════════════════════════════════════════════════════════════════════
#  INTERNAL STATE (BACKGROUND EXECUTION)
# ═══════════════════════════════════════════════════════════════════════
#  tui.exec is multi-instance: every call starts its own tracked instance
#  (its own PID, its own dedicated named pipe - never shared/multiplexed
#  across processes), keyed by an opaque instance id ("e1", "e2", ...).
#  Instances are also indexed by output pane (_EXEC_PANE_INSTANCES), so
#  several concurrently-running processes can feed the SAME pane - their
#  lines interleave into that pane's buffer, tagged with their instance id
#  once more than one instance is sharing it. A control pane is optional
#  per instance: pass "" (or omit it) for a headless/background process
#  with no Cancel/Save/Retry/etc. buttons and no stdin input box.
#  The _EXEC_* registries themselves live in state.sh.
# ═══════════════════════════════════════════════════════════════════════
# Exec control rows configured in tui_configuration.sh
_EXEC_CTL_ROWS_PER_INSTANCE="$TUI_EXEC_CTL_ROWS_PER_INSTANCE"

# Kills one instance's process (if still alive) and closes its fifo fd.
# Leaves its tmpdir/state in place - a still-tracked, no-longer-running
# instance is exactly what "done"/"error"/"cancelled" status means, and
# its output/Save/View controls (if any) stay usable until _exec_dismiss.
_exec_cleanup_instance() {
	local iid="$1"
	local pid="${_EXEC_PID[$iid]:-0}"
	if ((pid > 0)) && kill -0 "$pid" 2>/dev/null; then
		_kill_process_tree "$pid"
		wait "$pid" 2>/dev/null
	fi

	local fd="${_EXEC_FIFO_FD[$iid]:-}"
	if [[ -n "$fd" ]]; then
		exec {fd}>&- 2>/dev/null
		_EXEC_FIFO_FD[$iid]=""
	fi
}

_exec_cleanup_all() {
	local iid
	for iid in "${!_EXEC_STATUS[@]}"; do
		_exec_cleanup_instance "$iid"
		local tmpdir="${_EXEC_TMPDIR[$iid]:-}"
		[[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
	done
	tui.tick.remove "_exec_master_tick"
}

# ═══════════════════════════════════════════════════════════════════════
#  GENERIC BACKGROUND EXECUTION (tui.exec)
# ═══════════════════════════════════════════════════════════════════════
#  tui.exec CMD OUT_PANE [CTL_PANE] starts CMD as its own tracked instance
#  (own PID, own dedicated fifo) and returns its id via $_TUI_EXEC_LAST_ID
#  (set, not printed - same convention as $_TUI_FACTORY_LAST_ID). CTL_PANE
#  is optional: give it one to get Cancel/Save/View/Retry/Back buttons and
#  a stdin input box (auto-stacked below any other instance's controls
#  already using that pane); omit it for a plain background/streaming
#  process with no controls at all. Multiple instances can target the
#  same OUT_PANE at once - their output interleaves into that pane's
#  shared buffer, tagged "[iid] " once more than one instance is sharing
#  it - see _EXEC_PANE_INSTANCES at this file's top for the bookkeeping.

declare -gA _EXEC_STAT_WIDGET=() # iid -> its status-label widget id (only set if it has controls)

tui.exec() {
	local cmd="$1" out_pane="$2" ctl_pane="${3:-}"
	tui.log.info "tui.exec() initiating command: '$cmd' -> pane '$out_pane'${ctl_pane:+ (controls: $ctl_pane)}"

	if [[ -z "$cmd" || -z "$out_pane" ]]; then
		tui.log.error "tui.exec: Fatal config error. Missing cmd or out_pane."
		return 1
	fi

	if [[ -z "${_TUI_P_ROW[$out_pane]:-}" ]]; then
		tui.log.warn "tui.exec: output pane '$out_pane' missing or not yet laid out."
	fi
	if [[ -n "$ctl_pane" && -z "${_TUI_P_ROW[$ctl_pane]:-}" ]]; then
		tui.log.warn "tui.exec: control pane '$ctl_pane' missing or not yet laid out."
	fi

	local iid="e$((_EXEC_NEXT_ID++))"
	_EXEC_CMD[$iid]="$cmd"
	_EXEC_OUT_PANE[$iid]="$out_pane"
	_EXEC_CTL_PANE[$iid]="$ctl_pane"
	_EXEC_NS[$iid]=""
	declare -g -a "_EXEC_BUF_${iid}"

	# First use of this output pane creates its shared render buffer -
	# every instance that ever targets this pane appends into the SAME
	# array, which is what lets several concurrent processes share one
	# pane instead of one clobbering another's transcript.
	if ! declare -p "_EXEC_PANE_BUF_${out_pane}" &>/dev/null; then
		declare -g -a "_EXEC_PANE_BUF_${out_pane}"
	fi
	local already_active="${_EXEC_PANE_INSTANCES[$out_pane]:-}"
	_EXEC_PANE_INSTANCES[$out_pane]="${already_active:+${already_active} }${iid}"
	if [[ -n "$already_active" ]]; then
		local -n _tx_pbuf="_EXEC_PANE_BUF_${out_pane}"
		_tx_pbuf+=("── [${iid}] started: ${cmd} ──")
	fi

	_exec_launch_process "$iid"

	[[ -n "$ctl_pane" ]] && _exec_setup_controls "$iid"

	# Additive - does not disturb a page's own _TUI_TICK_FN (see the
	# _TUI_TICK_LISTENERS comment near this file's top).
	tui.tick.add "_exec_master_tick"

	((_TUI_RUNNING)) && _exec_render_pane "$out_pane"

	_TUI_EXEC_LAST_ID="$iid"
}

# tui.exec.cancel_pane PANE - cancel and fully dismiss every instance
# currently targeting PANE (running or already finished), clearing its
# shared buffer too. Not called automatically by tui.exec itself - that
# would silently cap every pane back to "one process at a time", which is
# exactly the restriction this rewrite removes. It exists for callers
# that specifically want that restart-cleanly behavior for one pane (a
# page that re-launches its own interactive shell on every revisit, say):
# call this right before a fresh tui.exec targeting the same pane.
tui.exec.cancel_pane() {
	local pane="$1"
	local -a ids=()
	read -ra ids <<<"${_EXEC_PANE_INSTANCES[$pane]:-}"
	local iid
	for iid in "${ids[@]}"; do
		_exec_dismiss_instance "$iid"
	done
	if declare -p "_EXEC_PANE_BUF_${pane}" &>/dev/null; then
		local -n _txc_pbuf="_EXEC_PANE_BUF_${pane}"
		_txc_pbuf=()
	fi
	((_TUI_RUNNING)) && _exec_render_pane "$pane"
}

# Launches (or, from retry, relaunches) the OS process for an already-
# registered instance: fresh tmpdir/fifo/outfile, fresh PID. Split out of
# tui.exec so _exec_on_retry can reuse it without re-registering the
# instance (same iid, same widgets, same pane slot).
_exec_launch_process() {
	local iid="$1" cmd="${_EXEC_CMD[$iid]}"

	local tmpdir
	tmpdir=$(mktemp -d /tmp/tui_exec.XXXXXX)
	local outfile="${tmpdir}/out"
	local fifo="${tmpdir}/in"
	touch "$outfile"
	mkfifo "$fifo"

	local fd
	exec {fd}<>"$fifo"

	script -q -e -c "$cmd" /dev/null <"$fifo" >>"$outfile" 2>&1 &
	local pid=$!

	_EXEC_TMPDIR[$iid]="$tmpdir"
	_EXEC_OUTFILE[$iid]="$outfile"
	_EXEC_FIFO[$iid]="$fifo"
	_EXEC_FIFO_FD[$iid]="$fd"
	_EXEC_PID[$iid]="$pid"
	_EXEC_LAST_READ[$iid]=0
	_EXEC_STATUS[$iid]="running"
	_EXEC_EXIT[$iid]=""
}

_exec_relaunch_process() {
	local iid="$1"
	_exec_cleanup_instance "$iid"
	local old_tmpdir="${_EXEC_TMPDIR[$iid]:-}"
	[[ -n "$old_tmpdir" && -d "$old_tmpdir" ]] && rm -rf "$old_tmpdir"
	_exec_launch_process "$iid"
}

# Builds one instance's control cluster (status label + 5 buttons + a
# stdin input) as a factory-tracked widget group under namespace
# "exec_<iid>", stacked at the next free row block in ctl_pane - so a
# second instance told to use the SAME ctl_pane gets its own cluster
# below the first's rather than overlapping it.
_exec_setup_controls() {
	local iid="$1" pane="${_EXEC_CTL_PANE[$iid]}"
	local ns="exec_${iid}"
	_EXEC_NS[$iid]="$ns"

	local row0="${_EXEC_PANE_CTL_ROW[$pane]:-0}"
	_EXEC_PANE_CTL_ROW[$pane]=$((row0 + _EXEC_CTL_ROWS_PER_INSTANCE))

	tui.factory.label "$ns" "$pane" "$row0" "$ ${_EXEC_CMD[$iid]}"
	_EXEC_STAT_WIDGET[$iid]="$_TUI_FACTORY_LAST_ID"
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"

	tui.factory.button "$ns" "$pane" "$((row0 + 1))" "[ Cancel ]" _exec_on_cancel
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"
	tui.factory.button "$ns" "$pane" "$((row0 + 2))" "[ Save Output ]" _exec_on_save
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"
	tui.factory.button "$ns" "$pane" "$((row0 + 3))" "[ View Command ]" _exec_on_view
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"
	tui.factory.button "$ns" "$pane" "$((row0 + 4))" "[ Retry ]" _exec_on_retry
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"
	tui.factory.button "$ns" "$pane" "$((row0 + 5))" "[ Back ]" _exec_on_back
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"

	tui.factory.input "$ns" "$pane" "$((row0 + 6))" "type and press Enter…" "stdin▸"
	_ps.widgets.set "$_TUI_FACTORY_LAST_ID" sticky 1 # a shell prompt: stays focused after Enter and after clicking the output
	_EXEC_WIDGET_TO_IID[$_TUI_FACTORY_LAST_ID]="$iid"
	tui.on_action "$_TUI_FACTORY_LAST_ID" _exec_on_send

	if ((_TUI_RUNNING)); then
		local w
		for w in ${_TUI_FACTORY_IDS[$ns]}; do
			_tui._draw_widget "$w"
		done
	fi
	_exec_render_status "$iid"
}

# Tears an instance down completely: kills it if still running, drops its
# tmpdir, removes its control widgets (if any) and redraws whatever else
# still shares that ctl_pane, and unregisters it from its pane's instance
# list. Used by the "Back" button and by tui.exec.cancel_pane.
_exec_dismiss_instance() {
	local iid="$1"
	[[ -z "${_EXEC_STATUS[$iid]:-}" ]] && return

	[[ "${_EXEC_STATUS[$iid]}" == "running" ]] && _exec_cleanup_instance "$iid"

	local tmpdir="${_EXEC_TMPDIR[$iid]:-}"
	[[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"

	local ns="${_EXEC_NS[$iid]:-}" ctl_pane="${_EXEC_CTL_PANE[$iid]:-}"
	if [[ -n "$ns" ]]; then
		local w
		for w in ${_TUI_FACTORY_IDS[$ns]:-}; do
			unset '_EXEC_WIDGET_TO_IID[$w]'
		done
		tui.factory.clear "$ns"

		if ((_TUI_RUNNING)) && [[ -n "$ctl_pane" ]]; then
			tui.clear_pane "$ctl_pane"
			_tui._draw_pane "$ctl_pane"
			# Blanking the whole pane above also blanked any OTHER
			# instance's still-active controls sharing it - redraw them.
			local other ow
			for other in "${!_EXEC_NS[@]}"; do
				[[ "$other" == "$iid" ]] && continue
				[[ "${_EXEC_CTL_PANE[$other]:-}" == "$ctl_pane" ]] || continue
				for ow in ${_TUI_FACTORY_IDS[${_EXEC_NS[$other]}]:-}; do
					_tui._draw_widget "$ow"
				done
				_exec_render_status "$other"
			done
		fi
	fi

	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -a existing=() remaining=()
	read -ra existing <<<"${_EXEC_PANE_INSTANCES[$pane]:-}"
	local e
	for e in "${existing[@]}"; do [[ "$e" == "$iid" ]] || remaining+=("$e"); done
	_EXEC_PANE_INSTANCES[$pane]="${remaining[*]}"

	unset '_EXEC_CMD[$iid]' '_EXEC_OUT_PANE[$iid]' '_EXEC_CTL_PANE[$iid]' '_EXEC_NS[$iid]' \
		'_EXEC_PID[$iid]' '_EXEC_STATUS[$iid]' '_EXEC_EXIT[$iid]' '_EXEC_TMPDIR[$iid]' \
		'_EXEC_OUTFILE[$iid]' '_EXEC_FIFO[$iid]' '_EXEC_FIFO_FD[$iid]' '_EXEC_LAST_READ[$iid]' \
		'_EXEC_STAT_WIDGET[$iid]'
	unset "_EXEC_BUF_${iid}"
}

_exec_strip_ansi() {
	local raw="$1"
	printf '%s' "$1" | awk '{
    gsub(/\r/, "")
    gsub(/\033\[[0-9;?]*[A-Za-z]/, "")
    gsub(/\033\][^\007\033]*(\007|\033\\)/, "")
    gsub(/\033[@A-Z\\\-_]/, "")
    gsub(/\033P[^\033]*\033\\/, "")
    printf "%s", $0
  }'
}

_exec_clean_line() {
	printf '%s' "$1" | awk '{
        gsub(/\r/, "")
        gsub(/\033\][^\007\033]*(\007|\033\\)/, "")
        gsub(/\033P[^\033]*\033\\/, "")
        gsub(/\033[@A-Z\\\-_]/, "")
        out = ""
        s = $0
        while (s != "") {
            p = index(s, "\033")
            if (p == 0) { out = out s; break }
            if (p > 1)  { out = out substr(s, 1, p - 1) }
            s = substr(s, p)
            if (substr(s, 2, 1) == "[") {
                if (match(s, /^\033\[[0-9;?]*[a-zA-Z]/)) {
                    seq = substr(s, 1, RLENGTH)
                    fin = substr(seq, RLENGTH, 1)
                    if (fin == "m") out = out seq
                    s = substr(s, RLENGTH + 1)
                } else { s = substr(s, 2) }
            } else { s = substr(s, 2) }
        }
        printf "%s", out
    }'
}

_exec_is_screen_clear() {
	local raw="$1"
	[[ "$raw" == *$'\033c'* ]] || [[ "$raw" == *$'\033[H'* ]] || [[ "$raw" == *$'\033[J'* ]] || [[ "$raw" == *$'\033[2J'* ]]
}

_exec_is_alt_buffer_toggle() {
	local raw="$1"
	[[ "$raw" == *$'\033[?1049h'* ]] || [[ "$raw" == *$'\033[?1049l'* ]] ||
		[[ "$raw" == *$'\033[?47h'* ]] || [[ "$raw" == *$'\033[?47l'* ]] ||
		[[ "$raw" == *$'\033[?1047h'* ]] || [[ "$raw" == *$'\033[?1047l'* ]]
}

_exec_is_line_clear() {
	local raw="$1"
	[[ "$raw" == *$'\033[K'* ]] || [[ "$raw" == *$'\033[2K'* ]]
}

# Appends one raw line from an instance's outfile into both its own
# private buffer (_EXEC_BUF_<iid>, used by Save/View) and its pane's
# shared render buffer (_EXEC_PANE_BUF_<pane>, tagged "[iid] " once that
# pane has more than one instance sharing it). Screen/line-clear control
# sequences only wipe the buffers when this instance has its pane to
# itself - with several processes sharing one pane, a full-screen TUI
# clearing "its screen" makes little sense and must not be allowed to
# erase a sibling process's history, so those codes are just stripped
# instead of acted on (matches _exec_clean_line already stripping
# everything but SGR color codes from every line's own content).
_exec_append_raw_line() {
	local iid="$1" raw_line="$2"
	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -a siblings=()
	read -ra siblings <<<"${_EXEC_PANE_INSTANCES[$pane]:-}"
	local solo=1
	((${#siblings[@]} > 1)) && solo=0

	local -n ibuf="_EXEC_BUF_${iid}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"

	if ((solo)) && { _exec_is_screen_clear "$raw_line" || _exec_is_alt_buffer_toggle "$raw_line"; }; then
		ibuf=()
		pbuf=()
		return
	fi
	if ((solo)) && _exec_is_line_clear "$raw_line"; then
		((${#ibuf[@]} > 0)) && ibuf[$((${#ibuf[@]} - 1))]=""
		((${#pbuf[@]} > 0)) && pbuf[$((${#pbuf[@]} - 1))]=""
		return
	fi

	local clean
	clean="$(_exec_clean_line "$raw_line")"
	local prefix=""
	((${#siblings[@]} > 1)) && prefix="[${iid}] "

	ibuf+=("$clean")
	((${#ibuf[@]} > 2500)) && ibuf=("${ibuf[@]:500}")

	pbuf+=("${prefix}${clean}")
	((${#pbuf[@]} > 2500)) && pbuf=("${pbuf[@]:500}")

	_ps.panes.set "$pane" lines "${#pbuf[@]}"
	local last_len
	last_len=$(printf '%s' "${pbuf[$((${#pbuf[@]} - 1))]:-}" | awk '{gsub(/\033\[[0-9;?]*[A-Za-z]/,""); print length($0)}')
	((last_len > ${_TUI_P_MAX_W[$pane]:-0})) && _TUI_P_MAX_W[$pane]=$last_len
}

# One instance's share of the per-frame tick: drain whatever it's written
# to its outfile since last time (non-blocking - just a file read, same
# mechanism whether the instance is an interactive shell or a headless
# polling loop with no controls), and detect+finalize on process exit.
_exec_tick_one() {
	local iid="$1"
	local pane="${_EXEC_OUT_PANE[$iid]}"
	local outfile="${_EXEC_OUTFILE[$iid]}"
	local changed=0

	if [[ -s "$outfile" ]]; then
		local -a new_lines=()
		mapfile -t new_lines < <(tail -n +"$((${_EXEC_LAST_READ[$iid]} + 1))" "$outfile" 2>/dev/null)
		if ((${#new_lines[@]} > 0)); then
			local raw_line
			for raw_line in "${new_lines[@]}"; do
				_exec_append_raw_line "$iid" "$raw_line"
			done
			_EXEC_LAST_READ[$iid]=$((${_EXEC_LAST_READ[$iid]} + ${#new_lines[@]}))
			changed=1
		fi
	fi

	local pid="${_EXEC_PID[$iid]}"
	if ! kill -0 "$pid" 2>/dev/null; then
		wait "$pid" 2>/dev/null
		_EXEC_EXIT[$iid]=$?

		local -a leftover=()
		mapfile -t leftover < <(tail -n +"$((${_EXEC_LAST_READ[$iid]} + 1))" "$outfile" 2>/dev/null)
		if ((${#leftover[@]} > 0)); then
			local raw_line
			for raw_line in "${leftover[@]}"; do
				_exec_append_raw_line "$iid" "$raw_line"
			done
			_EXEC_LAST_READ[$iid]=$((${_EXEC_LAST_READ[$iid]} + ${#leftover[@]}))
		fi

		if ((${_EXEC_EXIT[$iid]} == 0)); then _EXEC_STATUS[$iid]="done"; else _EXEC_STATUS[$iid]="error"; fi

		local -n pbuf_done="_EXEC_PANE_BUF_${pane}"
		pbuf_done+=("--- [${iid}] finished, exit ${_EXEC_EXIT[$iid]} ---")

		_exec_render_status "$iid"
		changed=1
	fi

	((changed)) && _exec_render_pane "$pane"
}

# Registered once (idempotently) via tui.tick.add the first time tui.exec
# runs; ticks every currently-running instance regardless of which pane
# or which page's own _TUI_TICK_FN is active.
_exec_master_tick() {
	local iid
	for iid in "${!_EXEC_STATUS[@]}"; do
		[[ "${_EXEC_STATUS[$iid]}" == "running" ]] && _exec_tick_one "$iid"
	done
}

# No-op for a headless instance (_EXEC_NS[$iid] empty - no controls to update).
_exec_render_status() {
	local iid="$1"
	local ns="${_EXEC_NS[$iid]:-}"
	[[ -z "$ns" ]] && return

	local icon
	case "${_EXEC_STATUS[$iid]}" in
		running) icon="● RUNNING  PID ${_EXEC_PID[$iid]}" ;;
		done) icon="✔ DONE     exit ${_EXEC_EXIT[$iid]}" ;;
		error) icon="✖ ERROR    exit ${_EXEC_EXIT[$iid]}" ;;
		cancelled) icon="■ CANCELLED" ;;
		*) icon="○ IDLE" ;;
	esac

	local stat_id="${_EXEC_STAT_WIDGET[$iid]}"
	local cmd="${_EXEC_CMD[$iid]}"
	_tui._widget_pos "$stat_id"
	local suffix="  -  ${icon}" room
	room=$((_WSW - 2 - ${#suffix}))
	if ((room < 4)); then # too narrow for both: status wins
		cmd=""
		suffix="${icon}"
	elif ((${#cmd} > room)); then
		cmd="${cmd:0:$((room - 3))}..."
	fi
	tui.set "$stat_id" "$ ${cmd}${suffix}"

	((_TUI_RUNNING)) && _tui._draw_widgets_now "$stat_id"
}

_exec_render_pane() {
	local pane="$1"
	_TUI_PANE_CONTENT[$pane]=1
	declare -g -a "_TUI_PANE_CONTENT_${pane}"
	local -n content="_TUI_PANE_CONTENT_${pane}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"
	content=("${pbuf[@]}")
	_tui._calc_bounds "$pane"
	_tui._render_output "$pane"
}

_exec_on_cancel() {
	local iid="${_EXEC_WIDGET_TO_IID[$1]:-}"
	[[ -z "$iid" ]] && return
	[[ "${_EXEC_STATUS[$iid]}" != "running" ]] && return

	local pid="${_EXEC_PID[$iid]}"
	kill -TERM "$pid" 2>/dev/null
	{
		sleep 0.15
		kill -KILL "$pid" 2>/dev/null
	} &
	wait "$pid" 2>/dev/null

	_EXEC_STATUS[$iid]="cancelled"
	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"
	pbuf+=("--- [${iid}] cancelled (PID ${pid}) ---")

	_exec_render_status "$iid"
	_exec_render_pane "$pane"
}

_exec_on_save() {
	local iid="${_EXEC_WIDGET_TO_IID[$1]:-}"
	[[ -z "$iid" ]] && return

	local ts
	ts=$(date +%Y%m%d_%H%M%S)
	local savefile="exec_output_${iid}_${ts}.log"
	local -n ibuf="_EXEC_BUF_${iid}"
	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"

	if printf '%s\n' "${ibuf[@]}" >"$savefile" 2>/dev/null; then
		pbuf+=("── [${iid}] saved → $(pwd)/${savefile} ──")
	else
		savefile="${_EXEC_TMPDIR[$iid]}/output_${ts}.log"
		printf '%s\n' "${ibuf[@]}" >"$savefile"
		pbuf+=("── [${iid}] saved → ${savefile} ──")
	fi
	_exec_render_pane "$pane"
}

_exec_on_view() {
	local iid="${_EXEC_WIDGET_TO_IID[$1]:-}"
	[[ -z "$iid" ]] && return

	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"
	local cmd="${_EXEC_CMD[$iid]}"

	pbuf+=("┈┈┈ [${iid}] command ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")
	pbuf+=("${cmd}")
	local first="${cmd%% *}"
	if [[ -f "$first" && -r "$first" ]]; then
		pbuf+=("┈┈┈ source: ${first} ┈┈┈┈┈┈┈┈┈")
		local src_line
		while IFS= read -r src_line; do
			pbuf+=("  ${src_line}")
		done <"$first"
	fi
	pbuf+=("┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")
	_exec_render_pane "$pane"
}

_exec_on_retry() {
	local iid="${_EXEC_WIDGET_TO_IID[$1]:-}"
	[[ -z "$iid" ]] && return
	[[ "${_EXEC_STATUS[$iid]}" == "running" ]] && _exec_on_cancel "$1"

	local cmd="${_EXEC_CMD[$iid]}" pane="${_EXEC_OUT_PANE[$iid]}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"
	pbuf+=("── [${iid}] retrying: ${cmd} ──")

	_exec_relaunch_process "$iid"
	_exec_render_status "$iid"
	_exec_render_pane "$pane"
}

_exec_on_back() {
	local iid="${_EXEC_WIDGET_TO_IID[$1]:-}"
	[[ -z "$iid" ]] && return
	_exec_dismiss_instance "$iid"
}

_exec_on_send() {
	local widget_id="$1"
	local iid="${_EXEC_WIDGET_TO_IID[$widget_id]:-}"
	[[ -z "$iid" ]] && return

	local text
	text=$(tui.get "$widget_id")
	[[ -z "$text" ]] && return

	local pane="${_EXEC_OUT_PANE[$iid]}"
	local -n pbuf="_EXEC_PANE_BUF_${pane}"
	local -a siblings=()
	read -ra siblings <<<"${_EXEC_PANE_INSTANCES[$pane]:-}"
	local prefix=""
	((${#siblings[@]} > 1)) && prefix="[${iid}] "

	if [[ "${_EXEC_STATUS[$iid]}" == "running" ]]; then
		local fd="${_EXEC_FIFO_FD[$iid]}"
		(printf "%s\n" "$text" >&"$fd" &) 2>/dev/null
		local masked
		masked="$(printf '%*s' "${#text}" | tr ' ' '*')"
		pbuf+=("${prefix}▸ ${masked}")
	else
		pbuf+=("${prefix}(process not running - input discarded)")
	fi

	tui.set "$widget_id" ""
	_tui._draw_widget "$widget_id"
	_exec_render_pane "$pane"
}
