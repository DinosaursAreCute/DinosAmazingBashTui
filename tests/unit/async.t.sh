# async.t.sh - lib/render/tui_async.sh: background painters in a process of their own.

_as_ticker() { # FILE - a painter that appends a line every 20 ms
	local i=0
	while :; do
		printf '%s\n' "$((++i))" >>"$1"
		tui.async.wait 0.02
	done
}

ti_async_start_runs_a_function_in_the_background_and_stop_ends_it() {
	local f="$_T_ROOT/as_ticks_$RANDOM" pid n
	: >"$f"
	tui.async.start tick _as_ticker "$f"
	pid="${_TUI_ASYNC_PID[tick]}"
	ok 'tui.async.active tick'
	ok 'kill -0 "$pid" 2>/dev/null'
	tui.async.wait 0.25
	n=$(wc -l <"$f")
	ok '(( n >= 4 ))' # it ticked meanwhile, without the main loop doing anything
	tui.async.stop tick
	ok '! kill -0 "$pid" 2>/dev/null'
	ok '! tui.async.active tick'
	n=$(wc -l <"$f")
	tui.async.wait 0.1
	eq "$n" "$(wc -l <"$f")" # and no more after the stop
	tui.async.stop_all
}

ti_async_a_second_start_with_the_same_name_replaces_the_first() {
	local f="$_T_ROOT/as_two_$RANDOM" first
	: >"$f"
	tui.async.start tick _as_ticker "$f"
	first="${_TUI_ASYNC_PID[tick]}"
	tui.async.start tick _as_ticker "$f"
	ok '[[ "${_TUI_ASYNC_PID[tick]}" != "$first" ]]'
	ok '! kill -0 "$first" 2>/dev/null'
	eq 1 "${#_TUI_ASYNC_PID[@]}"
	tui.async.stop_all
}

ti_async_put_and_get_pass_small_values_to_the_painter_and_stop_all_cleans_up() {
	local v dir
	tui.async.put job rect "10 20 30 40"
	tui.async.get job.rect v
	eq "10 20 30 40" "$v"
	tui.async.get job.nothing v
	eq "" "$v"
	dir="$_TUI_ASYNC_DIR"
	ok '[[ -d "$dir" ]]'
	tui.async.stop_all
	ok '[[ ! -d "$dir" && -z "$_TUI_ASYNC_DIR" ]]'
}

ti_async_covered_flag_follows_a_modal_or_a_layer() {
	_TUI_MODAL="" _TUI_L_N=0
	tui.async.put job x 1 # makes the folder
	_tui_async.cover_changed
	ok '! tui.async.covered'
	_TUI_MODAL=palette
	_tui_async.cover_changed
	ok 'tui.async.covered'
	_TUI_MODAL=""
	_tui_async.cover_changed
	ok '! tui.async.covered'
	_TUI_L_N=1
	_tui_async.cover_changed
	ok 'tui.async.covered'
	_TUI_L_N=0
	_tui_async.cover_changed
	tui.async.stop_all
}

ti_async_reset_ui_ends_the_painters_of_the_page() {
	local f="$_T_ROOT/as_reset_$RANDOM" pid
	: >"$f"
	tui.async.start tick _as_ticker "$f"
	pid="${_TUI_ASYNC_PID[tick]}"
	tui.reset_ui
	ok '! kill -0 "$pid" 2>/dev/null'
	eq 0 "${#_TUI_ASYNC_PID[@]}"
}

ti_async_a_page_repaint_under_the_command_palette_carries_the_palette_in_the_same_write() {
	local out saved
	_palette_draw() {
		_tui.emit_goto 3 3
		_tui.emit "PALETTE-BOX"
	}
	tui.modal.open palette true _palette_draw >/dev/null 2>&1
	_TUI_RUNNING=1
	_TUI_FRAME=""
	_tui.emit_goto 3 5
	_tui.emit "TICK"
	out="$(_tui._flush "$_TUI_FRAME" 2>&1)"
	_TUI_RUNNING=0
	ok '[[ "$out" == *"TICK"*"PALETTE-BOX"* ]]' # the palette follows the page's bytes: never under them, not even for a frame
	tui.modal.close >/dev/null 2>&1
	unset -f _palette_draw
}

ti_async_a_canvas_made_for_another_size_is_not_drawn_until_the_page_makes_a_new_one() {
	_TUI_P_ROW[cv]=1 _TUI_P_COL[cv]=1 _TUI_P_H[cv]=4 _TUI_P_W[cv]=20 _TUI_P_BORDER[cv]=none _TUI_P_BORDER_EXPL[cv]=1 _TUI_P_HPAD[cv]=0 _TUI_P_VPAD[cv]=0
	tui.set_canvas cv $'abc\nabc'
	_tui._content_rect cv
	eq "$_CR_W $_CR_H" "${_TUI_PANE_RAW_SIZE[cv]}" # the content area, not the pane
	_TUI_FRAME=""
	_tui._render_raw_buf cv
	ok '[[ "$_TUI_FRAME" == *"abc"* ]]'
	_TUI_P_W[cv]=10 # the terminal got narrower: the frame is for 20 columns
	_TUI_FRAME=""
	_tui._render_raw_buf cv
	eq "" "$_TUI_FRAME"
	tui.set_canvas cv $'xyz\nxyz'
	_TUI_FRAME=""
	_tui._render_raw_buf cv
	ok '[[ "$_TUI_FRAME" == *"xyz"* ]]'
}

ti_async_hold_pauses_the_painters_until_the_next_cover_check() {
	_TUI_MODAL="" _TUI_L_N=0
	tui.async.put job x 1
	_tui_async.cover_changed
	_tui_async.hold
	ok 'tui.async.covered'
	_tui_async.cover_changed # nothing is open over the page: they go on
	ok '! tui.async.covered'
	tui.async.stop_all
}

_as_stray_writer() { # a painter that prints to stdout instead of using tui.async.emit
	printf 'STRAY'
	tui.async.emit "PAINT"
	tui.async.wait 0.05
}

ti_async_a_painters_stdout_goes_nowhere_and_only_emit_reaches_the_terminal() {
	local out="$_T_ROOT/as_out_$RANDOM"
	tui.async.start stray _as_stray_writer >"$out"
	tui.async.wait 0.2
	tui.async.stop_all
	ok '[[ "$(cat "$out")" != *STRAY* ]]'
	ok '[[ "$(cat "$out")" == *PAINT* ]]'
}

ti_async_the_main_loops_writes_are_counted_for_painters_only_while_one_runs() {
	local g
	_TUI_ASYNC_PID=() _TUI_WRITE_GEN=0 _TUI_OUT_FD=1
	_tui.write "x" >/dev/null
	eq 0 "$_TUI_WRITE_GEN" # no painter: nothing to tell
	tui.async.put job x 1  # makes the folder
	_TUI_ASYNC_PID[job]=$$
	_tui.write "x" >/dev/null
	_tui.write "y" >/dev/null
	tui.async.get gen g
	eq 2 "$g"
	_TUI_ASYNC_PID=()
	tui.async.stop_all
}

ti_canvas_sends_only_the_rows_that_changed_while_nothing_else_painted() {
	_TUI_P_ROW[cv]=1 _TUI_P_COL[cv]=1 _TUI_P_H[cv]=3 _TUI_P_W[cv]=20 _TUI_P_BORDER[cv]=none _TUI_P_BORDER_EXPL[cv]=1 _TUI_P_HPAD[cv]=0 _TUI_P_VPAD[cv]=0
	local out
	_TUI_RAW_ROWS=() _TUI_RAW_GEN=-1 _TUI_PANE_RAW[cv]=$'aaa\nbbb\nccc'
	_TUI_FRAME=""
	_tui._render_raw_buf cv diff
	ok '[[ "$_TUI_FRAME" == *aaa*bbb*ccc* ]]' # nothing is known to be on screen: every row goes out
	_TUI_RAW_GEN=$_TUI_FLUSH_GEN
	_TUI_PANE_RAW[cv]=$'aaa\nBBB\nccc'
	_TUI_FRAME=""
	_tui._render_raw_buf cv diff
	ok '[[ "$_TUI_FRAME" == *BBB* && "$_TUI_FRAME" != *aaa* && "$_TUI_FRAME" != *ccc* ]]'
	_TUI_FLUSH_GEN+=1 # something else painted: what the screen shows is no longer known
	_TUI_FRAME=""
	_tui._render_raw_buf cv diff
	ok '[[ "$_TUI_FRAME" == *aaa*BBB*ccc* ]]'
	_TUI_RAW_GEN=-1 _TUI_RAW_ROWS=()
	unset '_TUI_PANE_RAW[cv]'
}
