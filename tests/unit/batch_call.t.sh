# batch_call.t.sh - _tui.batch_call: widget updates inside a callback are drawn once, after it returns.

_bc_draws=()
_bc_stub_draws() {
	_bc_draws=()
	_tui._draw_widget() { _bc_draws+=("$1"); }
	_tui._draw_batch_now() { _bc_draws+=("batch:$*"); }
	tui.notify() { :; }
	_TUI_W_TYPE[a]=label _TUI_W_TYPE[b]=label
	_TUI_RUNNING=1
}
_bc_cb() { tui.update a 1; tui.update b 2; tui.update a 3; }

ti_batch_call_flushes_all_updates_of_a_callback_once() {
	_bc_stub_draws
	_tui.batch_call _bc_cb
	eq "batch:a b a" "${_bc_draws[*]}"
	eq 3 "$(tui.get a)"
}

ti_update_outside_a_batch_draws_immediately() {
	_bc_stub_draws
	tui.update a 1
	eq "a" "${_bc_draws[*]}"
}

ti_nested_batch_calls_flush_only_at_the_outermost_level() {
	_bc_stub_draws
	_bc_outer() { tui.update a 1; _tui.batch_call _bc_cb; }
	_tui.batch_call _bc_outer
	eq "1" "${#_bc_draws[@]}"
}

ti_batch_call_returns_the_callbacks_status() {
	_bc_stub_draws
	_bc_fail() { return 7; }
	_tui.batch_call _bc_fail
	eq 7 "$?"
	eq 0 "$_TUI_BATCH_DEPTH"
}

ti_list_key_redraws_the_widget_before_its_on_change_callback_runs() {
	_kc_list
	_bc_log=()
	_tui_wx.redraw() { _bc_log+=("draw:$1"); }
	_bc_cb2() { _bc_log+=("cb:$1"); }
	tui.on_change kcl _bc_cb2
	_tui_wx.key kcl down
	eq "draw:kcl cb:kcl" "${_bc_log[*]}"
}

ti_text_key_redraws_the_widget_before_its_on_change_callback_runs() {
	_bc_stub_draws
	_bc_log=()
	_tui_text.redraw() { _bc_log+=("draw:$1"); }
	_bc_cb2() { _bc_log+=("cb:$1"); }
	_TUI_W_VALUE[a]="" _TUI_W_TYPE[a]=input _TUI_W_CHANGE[a]=_bc_cb2
	_tui_text.key a x
	eq "draw:a cb:a" "${_bc_log[*]}"
}

ti_bound_command_updates_are_flushed_once() {
	_bc_stub_draws
	_tui_input.run "_bc_cb"
	eq "batch:a b a" "${_bc_draws[*]}"
}

ti_scheduled_job_updates_are_flushed_once() {
	_bc_stub_draws
	_bc_job() { tui.update a 1; tui.update b 2; }
	tui.every 1 _bc_job
	_TA_NEXT[_bc_job]=0
	_tui_api._tick
	tui.every.cancel _bc_job
	eq "batch:a b" "${_bc_draws[*]}"
}

ti_table_column_widths_are_scanned_once_per_data_change() {
	_kc_reset
	tui.table wtb kcp 0 "" 5
	tui.table.set wtb "A|B" "x|yy" "xxxx|y"
	_tui_wx.draw_rows wtb table 1 1 20 6 0 "" "" >/dev/null 2>&1
	eq "4 2" "${_WXCW[wtb]}"
	_WXCW[wtb]="9 9" # a cached entry is used as is, not rescanned
	_tui_wx.draw_rows wtb table 1 1 20 6 0 "" "" >/dev/null 2>&1
	eq "9 9" "${_WXCW[wtb]}"
	tui.table.add wtb "xxxxxx|z"
	[[ -z ${_WXCW[wtb]+x} ]]; eq 0 "$?" # the next row change drops the entry
	tui.table.set wtb "A|B" "q|q"
	_tui_wx.draw_rows wtb table 1 1 20 6 0 "" "" >/dev/null 2>&1
	eq "1 1" "${_WXCW[wtb]}"
}

ti_split_gives_the_cells_of_a_row_including_empty_ones() {
	_tui_wx.split "a||c|"
	eq "4" "${#_WXC[@]}" # the trailing empty cell is kept: harmless, a missing cell reads as empty too
	eq "a||c|" "${_WXC[0]}|${_WXC[1]}|${_WXC[2]}|${_WXC[3]}"
	_tui_wx.split "solo"
	eq "1 solo" "${#_WXC[@]} ${_WXC[0]}"
}

ti_table_row_text_is_cached_and_follows_data_changes() {
	_kc_reset
	tui.table wtr kcp 0 "" 5
	tui.table.set wtr "A|B" "x|yy" "xxxx|y"
	_tui_wx.draw_rows wtr table 1 1 20 6 0 "" "" >/dev/null 2>&1
	[[ ${_WXRL[wtr:0]} == *$'\x1f'* ]]; eq 0 "$?"
	local first=${_WXRL[wtr:0]}
	tui.table.set wtr "A|B" "q|q" "z|z"
	_tui_wx.draw_rows wtr table 1 1 20 6 0 "" "" >/dev/null 2>&1
	[[ ${_WXRL[wtr:0]} != "$first" ]]; eq 0 "$?" # same index, new data: redrawn
	tui.table.set wtr "A|B" "x|yy" "xxxx|y"
	_tui_wx.draw_rows wtr table 1 1 20 6 0 "" "" >/dev/null 2>&1
	first=${_WXRL[wtr:0]}
	tui.table.align wtr "r|l"
	_tui_wx.draw_rows wtr table 1 1 20 6 0 "" "" >/dev/null 2>&1
	[[ ${_WXRL[wtr:0]} != "$first" ]]; eq 0 "$?" # a changed alignment is not served from the cache
}

ti_a_full_render_drops_the_widget_draws_queued_by_a_batch() {
	_TUI_BATCH_IDS=(a b)
	tui.render >/dev/null 2>&1
	eq 0 "${#_TUI_BATCH_IDS[@]}"
}
