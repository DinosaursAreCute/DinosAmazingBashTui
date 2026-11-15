# paced_updates.t.sh - concurrent live updates: one flush per tick, nothing drawn that did not change, at most one
# timer-driven flush per frame budget; input feedback is never paced.

# _pu_paced CMD... - CMD with the paced flag on, off again after (a temporary assignment on a function call leaks)
_pu_paced() {
	_TUI_BATCH_PACED=1
	"$@"
	_TUI_BATCH_PACED=0
}

_pu_draws=()
_pu_stub() {
	_pu_draws=()
	_tui._draw_widget() { _pu_draws+=("one:$1"); }
	_tui._draw_batch_now() { _pu_draws+=("batch:$*"); }
	tui.notify() { :; }
	_TUI_W_TYPE[a]=label _TUI_W_TYPE[b]=label
	_TUI_RUNNING=1
}

ti_set_label_inside_a_batch_is_drawn_once_with_the_batch() {
	_pu_stub
	_pu_cb() {
		tui.set_label a x
		tui.set_label b y
	}
	_tui.batch_call _pu_cb
	eq "batch:a b" "${_pu_draws[*]}"
}

ti_set_label_outside_a_batch_draws_at_once() {
	_pu_stub
	tui.set_label a x
	eq "one:a" "${_pu_draws[*]}"
}

ti_set_label_with_the_same_text_draws_nothing() {
	_pu_stub
	tui.set_label a x
	_pu_draws=()
	tui.set_label a x
	eq "0" "${#_pu_draws[@]}"
}

ti_update_inside_a_batch_skips_an_unchanged_value() {
	_pu_stub
	tui.set a 5
	_pu_cb() {
		tui.update a 5
		tui.update b 1
	}
	_tui.batch_call _pu_cb
	eq "batch:b" "${_pu_draws[*]}"
}

ti_update_outside_a_batch_still_draws_an_unchanged_value() {
	_pu_stub
	tui.set a 5
	tui.update a 5
	eq "one:a" "${_pu_draws[*]}"
}

ti_bound_widgets_changed_by_a_callback_join_its_one_flush() {
	_pu_stub
	local saved_fn
	saved_fn="$(declare -f tui.data.flush)" # functions are not part of the per-test state snapshot
	_TD_PENDING=1
	tui.data.flush() {
		_TD_PENDING=0
		tui.set_label a 1
		tui.set_label b 2
	}
	_pu_cb() { :; }
	_tui.batch_call _pu_cb
	eval "$saved_fn"
	eq "batch:a b" "${_pu_draws[*]}"
}

ti_paced_batch_flushes_the_first_draw_at_once() {
	_pu_stub
	_TUI_PACE_LAST_US=0
	_pu_cb() { tui.update a 1; }
	_pu_paced _tui.batch_call _pu_cb
	eq "batch:a" "${_pu_draws[*]}"
}

ti_paced_batch_inside_the_frame_budget_waits_for_the_next_frame() {
	_pu_stub
	_TUI_PACE_LAST_US=${EPOCHREALTIME//[!0-9]/}
	_pu_cb() { tui.update a 1; }
	_pu_paced _tui.batch_call _pu_cb
	eq "0" "${#_pu_draws[@]}"
	eq "a" "${_TUI_PACED_IDS[*]}"
	_TUI_PACE_LAST_US=$((_TUI_PACE_LAST_US - 20000))
	_tui.paced_flush
	eq "batch:a" "${_pu_draws[*]}"
	eq "0" "${#_TUI_PACED_IDS[@]}"
}

ti_two_paced_ticks_in_one_frame_fold_into_one_flush() {
	_pu_stub
	_TUI_PACE_LAST_US=${EPOCHREALTIME//[!0-9]/}
	_pu_cb() { tui.update a 1; }
	_pu_cb2() { tui.update b 2; }
	_pu_paced _tui.batch_call _pu_cb
	_pu_paced _tui.batch_call _pu_cb2
	_TUI_PACE_LAST_US=$((_TUI_PACE_LAST_US - 20000))
	_tui.paced_flush
	eq "batch:a b" "${_pu_draws[*]}"
}

ti_an_unpaced_batch_is_not_held_back_by_the_budget() {
	_pu_stub
	_TUI_PACE_LAST_US=${EPOCHREALTIME//[!0-9]/}
	_pu_cb() { tui.update a 1; }
	_tui.batch_call _pu_cb
	eq "batch:a" "${_pu_draws[*]}"
}

ti_a_full_render_drops_the_paced_queue() {
	_TUI_PACED_IDS=(a b)
	tui.render >/dev/null 2>&1
	eq "0" "${#_TUI_PACED_IDS[@]}"
}

ti_output_with_the_same_text_is_not_rendered_again() {
	_TUI_RUNNING=1
	_TUI_P_H[p]=5 _TUI_P_W[p]=20
	tui.output p "one
two"
	_TUI_PENDING_OUTPUT=()
	tui.output p "one
two"
	eq "0" "${#_TUI_PENDING_OUTPUT[@]}"
	tui.output p "one
three"
	eq "1" "${#_TUI_PENDING_OUTPUT[@]}"
}

ti_output_append_forgets_the_remembered_text() {
	_TUI_RUNNING=1
	_TUI_P_H[p]=5 _TUI_P_W[p]=20
	tui.output p "one"
	tui.output_append p "two"
	_TUI_PENDING_OUTPUT=()
	tui.output p "one"
	eq "1" "${#_TUI_PENDING_OUTPUT[@]}"
}

ti_an_overdue_timer_counts_its_missed_ticks_and_rests_as_long_as_it_ran() {
	_TUI_PERF_TRACKING=1
	tui.perf.reset
	_pu_slow() {
		local t=${EPOCHREALTIME//[!0-9]/}
		while (($((${EPOCHREALTIME//[!0-9]/} - t)) < 60000)); do :; done
	}
	tui.every 0.02 _pu_slow pu_slow
	_TA_NEXT[pu_slow]=0
	_tui_api._tick
	local now_ms=$((${EPOCHREALTIME//[!0-9]/} / 1000))
	ok '((_TA_NEXT[pu_slow] >= now_ms + 50))' # idle at least about as long as the 60 ms it ran
	_TA_NEXT[pu_slow]=$((now_ms - 100))
	_tui_api._tick
	ok '((${_TUI_PERF_COUNTERS[ticks_dropped]:-0} >= 4))'
	ok '[[ -n "${_TUI_PERF_LOG[tick:pu_slow]:-}" ]]'
	_TUI_PERF_TRACKING=0 # a global the per-test snapshot does not restore, and it slows the timing tests after this one
	tui.every.clear
}
