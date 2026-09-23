#!/usr/bin/env bash
# debug_callbacks.sh - wires up the debug/observability page: a dynamic
# grid of interactive elements to hover/focus/click, a live tape of every
# dispatched mouse/keyboard event, a status readout of what's currently
# (and was last) hovered/focused, and a rolling mean render time. Exists
# to make this session's debugging visible from inside the app itself,
# not just from throwaway test scripts.

# Opt in to render-time tracking for this page only - off by default
# everywhere else, since it costs a timestamp pair per flushed frame.
_TUI_PERF_TRACKING=1

# ── Input tape ──────────────────────────────────────────────────────────
# A capped ring buffer, same idea as tui.exec's own _EXEC_BUF: replace the
# pane's content each time rather than tui.output_append forever, so the
# tape can't grow memory unboundedly.
declare -a _DEBUG_TAPE=()
_DEBUG_TAPE_MAX=300

_debug_on_input_event() {
	local desc="$1"
	_DEBUG_TAPE+=("$(date +%H:%M:%S) $desc")
	if ((${#_DEBUG_TAPE[@]} > _DEBUG_TAPE_MAX)); then
		_DEBUG_TAPE=("${_DEBUG_TAPE[@]: -${_DEBUG_TAPE_MAX}}")
	fi
	tui.output "tape" "$(printf '%s\n' "${_DEBUG_TAPE[@]}")"
}
_TUI_ON_INPUT_EVENT="_debug_on_input_event"

on_clear_tape() {
	_DEBUG_TAPE=()
	tui.output_clear "tape"
}

# ── Dynamic interactive-elements grid ───────────────────────────────────
# Built via the factory API so its shape (and item count) can change at
# runtime - the whole point of tui.factory.grid over a fixed <pane
# split="grid">. Mixes buttons, checkboxes, and an input to give hover
# and focus something varied to move across.

_debug_noop_action() { :; }

_debug_build_grid() {
	local count="$1"
	tui.factory.clear "demo"

	tui.factory.grid "demo" "interactive_demo" "$count"

	local i cell kind
	for i in "${!_TUI_FACTORY_GRID_CELLS[@]}"; do
		cell="${_TUI_FACTORY_GRID_CELLS[$i]}"
		kind=$((i % 3))
		case "$kind" in
			0) tui.factory.button "demo" "$cell" 0 "Button $i" _debug_noop_action ;;
			1) tui.factory.checkbox "demo" "$cell" 0 "Toggle $i" "false" _debug_noop_action ;;
			2) tui.factory.input "demo" "$cell" 0 "type here" "F$i:" ;;
		esac
	done

	((_TUI_RUNNING)) && tui.render
}

on_rebuild_grid() {
	local count=$(((RANDOM % 8) + 3)) # 3..10 items - shape changes every click
	_debug_build_grid "$count"
}

# ── Status readout: hover/focus + mean render time ──────────────────────
# Reuses _TUI_TICK_FN (free for this page - it isn't also driving a
# tui.exec process) rather than polling from the main loop. Only redraws
# when hover/focus actually changed, same change-gating discipline as the
# rest of the framework's hover/focus handling; the perf readout refreshes
# on its own slower cadence since recomputing it every tick would be pure
# waste for something that only needs to feel "live", not instantaneous.

declare -g _DEBUG_LAST_HOVER_W="" _DEBUG_LAST_FOCUS=""
declare -g _DEBUG_TICK_COUNT=0

_debug_tick() {
	((_DEBUG_TICK_COUNT++))

	if [[ "$_TUI_HOVERED_WIDGET" != "$_DEBUG_LAST_HOVER_W" || "$_TUI_FOCUS_ID" != "$_DEBUG_LAST_FOCUS" ]]; then
		_DEBUG_LAST_HOVER_W="$_TUI_HOVERED_WIDGET"
		_DEBUG_LAST_FOCUS="$_TUI_FOCUS_ID"
		_debug_refresh_status
	fi

	# Perf readout: refresh roughly twice a second rather than every tick.
	if ((_DEBUG_TICK_COUNT % 10 == 0)); then
		_debug_refresh_status
	fi
}
_TUI_TICK_FN="_debug_tick"

_debug_refresh_status() {
	local mean
	mean="$(tui.perf.mean_render_ms 5)"
	[[ -z "$mean" ]] && mean="n/a"

	local lines=""
	lines+="Hovered pane:    ${_TUI_HOVERED_PANE:-<none>}\n"
	lines+="Hovered widget:  ${_TUI_HOVERED_WIDGET:-<none>}\n"
	lines+="Focused widget:  ${_TUI_FOCUS_ID:-<none>}\n"
	lines+="\n"
	lines+="Mean render time (last 5s): ${mean} ms\n"
	lines+="Frames tracked: ${#_TUI_RENDER_LOG_T[@]}\n"

	tui.output "status" "$(printf '%b' "$lines")"
}

# ── Initial build ───────────────────────────────────────────────────────
_debug_build_grid 6
