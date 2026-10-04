#!/usr/bin/env bash
# tui_loop.sh - the main event loop.
#
#   tui.run     runs the event loop: input, ticks, resize, frames; returns when tui.stop is called
#   tui.stop    asks the loop to end
# requires:

# ═══════════════════════════════════════════════════════════════════════
#  MAIN EVENT LOOP
# ═══════════════════════════════════════════════════════════════════════

# _tui._secs_to_us SECS VAR - decimal seconds ("0.05") to integer microseconds in VAR, fork-free.
_tui._secs_to_us() {
	local s="$1" whole frac
	whole="${s%%.*}"
	frac="${s#"$whole"}"
	frac="${frac#.}000000"
	printf -v "$2" '%d' "$((10#${whole:-0} * 1000000 + 10#${frac:0:6}))"
}

tui.run() {
	tui.log.debug "tui.run() starting"
	_TUI_RUNNING=1
	if ((! _TPL_READY)); then
		_TPL_READY=1
		tui.hook.fire ready
	fi

	trap '_master_cleanup; exit 1' INT TERM
	# WINCH trap: installed in tui.init, not here - see its comment. A
	# resize caught between tui.init and here must still be applied before
	# the very first frame draws, not silently dropped by an unconditional
	# `_TUI_RESIZED=0` reset (that was the bug: this function used to zero
	# the flag unread, so a window still settling behind a warm-up splash
	# laid the first frame out at whatever stale size tui.init happened to
	# read, with no correction until the terminal's NEXT resize, if any).
	if ((_TUI_RESIZED)); then
		_tui._apply_resize
	fi
	_TUI_RESIZED=0

	tui.render
	tui.log.debug "tui.run() rendered"

	# Tick cadence is a property of time, not of loop iterations: any input
	# byte ends the poll read early, so ticking per iteration would run
	# every registered tick function faster whenever the pointer moves.
	local _tick_period_us _tick_last_us=0 _tick_now_us
	_tui._secs_to_us "$TUI_INPUT_POLL_TIMEOUT" _tick_period_us

	while ((_TUI_RUNNING)); do

		if ((_TUI_RESIZED && ! _TUI_PASSTHROUGH)); then # while frozen (terminal-control mode) resize waits
			_tui._apply_resize
			mode.sync_start
			erase.all
			tui.render
			mode.sync_end
			tui.hook.fire resize "$_TUI_ROWS" "$_TUI_COLS"
			declare -F _tui_api.on_resize >/dev/null && _tui_api.on_resize
			[[ -n "${_TUI_ON_RESIZE_FN:-}" ]] && "$_TUI_ON_RESIZE_FN"
		fi

		local char=""
		local got_char=0
		local poll_timeout="$TUI_INPUT_IDLE_TIMEOUT"
		if [[ -n "${_TUI_TICK_FN:-}" ]] || ((${#_TUI_TICK_LISTENERS[@]} > 0)); then
			poll_timeout="$TUI_INPUT_POLL_TIMEOUT"
		fi
		# A queued pane render (tui.output, scroll batching) is flushed once the input goes quiet; waiting the
		# full poll timeout for that made every scroll step and page load ~50 ms slower than its work.
		((${#_TUI_PENDING_OUTPUT[@]})) && poll_timeout="$TUI_INPUT_SETTLE_TIMEOUT"
		((_TUI_PASSTHROUGH)) && poll_timeout="$TUI_INPUT_IDLE_TIMEOUT" # frozen: nothing to tick

		_tui._next_byte char "$poll_timeout" && got_char=1

		[[ -z "$char" && got_char -eq 1 ]] && char=$'\n'

		if [[ -n "$char" ]]; then
			if [[ "$char" == $'\e' ]]; then
				_tui._read_escape_seq
				local seq="$_TUI_SEQ_BUF"
				if [[ "$seq" == "[200~" ]]; then
					_tui_input.read_paste
					_tui_input.paste_event # always consumed, even in pass-through
				elif [[ "$seq" == "[<"* ]]; then
					if _tui._mouse_seq_is_motion "$seq"; then
						_tui._coalesce_mouse_motion "$seq"
						seq="$_TUI_SEQ_BUF"
					else
						_tui_input.coalesce_mouse "$seq" # wheel spins: merge into one
						seq="$_TUI_SEQ_BUF"
					fi
					_tui._handle_mouse "$seq"
				elif
					_tui_input.coalesce_key "" "$seq"
					! _tui_input.key_event "" "$seq"
				then
					# unbound: a focused text input gets the raw sequence (cursor keys...)
					false && _tui._input_seq "$_TUI_FOCUS_ID" "$seq"
				fi
			elif
				_tui_input.coalesce_key "$char" ""
				! _tui_input.key_event "$char" ""
			then
				false && _tui._input_key "$_TUI_FOCUS_ID" "$char"
			fi
		fi

		# Terminal-control mode: input is drained (chord only) but nothing is drawn or ticked.
		((_TUI_PASSTHROUGH)) && continue

		# ── SCROLL BATCHING / DEBOUNCING ──
		# Pane content queued by _tui._queue_render (wheel spins, drag-jumps)
		# is flushed together, once, when the burst settles (timeout hits
		# zero) or the input stream goes idle (got_char==0). Hover/focus
		# redraws never enter this queue - they draw immediately where they
		# happen, so this block is scroll-only.
		if ((_TUI_RENDER_TIMEOUT > 0)); then
			((_TUI_RENDER_TIMEOUT--))
		fi

		if ((_TUI_RENDER_TIMEOUT == 0)) || ((got_char == 0)); then
			_tui._flush_pending_render
			_TUI_RENDER_TIMEOUT=-1
		fi

		_tick_now_us=${EPOCHREALTIME//[!0-9]/}
		if ((_tick_now_us - _tick_last_us >= _tick_period_us)); then
			_tick_last_us=$_tick_now_us
			[[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
		fi
		((_TUI_KEYS_SUSPENDED)) && _tui_input.draw_overlay
		((${#_TUI_OVERLAY_FNS[@]} && _TUI_FLUSH_GEN != _TUI_OVL_GEN)) && {
			_TUI_OVL_GEN=$_TUI_FLUSH_GEN
			_tui_overlay.draw_all
		}
		if ((_tick_last_us == _tick_now_us && ${#_TUI_TICK_LISTENERS[@]} > 0)); then
			local _tick_listener
			for _tick_listener in "${_TUI_TICK_LISTENERS[@]}"; do
				"$_tick_listener"
			done
		fi
		_tui.frame_present
	done

	_master_cleanup
}

tui.stop() {
	tui.hook.fire quit
	_TUI_RUNNING=0
}
