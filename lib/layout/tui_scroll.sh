#!/usr/bin/env bash
# tui_scroll.sh - scroll offset calculations: pure arithmetic over existing
# engine state (pane geometry, widget positions, scroll settings). No rendering
# or input handling - only sets offset values and measures content height.
#
# Globals for results:
#   _SC_MAX        (max_off): max offset value for the pane
#   _TUI_P_CONTENT_H (measure): total height in rows of widgets in pane

# _tui_scroll.measure PANE - sets _TUI_P_CONTENT_H[PANE] = height of all
# widgets in PANE stacked vertically: max over widgets w with
# _TUI_W_PANE[w]==PANE of (_TUI_W_ROW[w] + h), where h = _TUI_W_HEIGHT[w] when
# it is a plain integer, else 1. Returns 0 when the pane has no widgets.
_tui_scroll.measure() {
	local pane="$1"
	local max_row=0
	local w
	for w in "${_TUI_W_ORDER[@]}"; do
		[[ "${_TUI_W_PANE[$w]:-}" == "$pane" ]] || continue
		local row="${_TUI_W_ROW[$w]:-0}"
		local height="${_TUI_W_HEIGHT[$w]:-1}"
		# not a plain integer (a unit token): rows= if the widget has them (list, table, textarea), else 1
		if ! [[ "$height" =~ ^[0-9]+$ ]]; then
			height=1
		fi
		((${_TUI_W_ROWSPAN[$w]:-0} > height)) && height=${_TUI_W_ROWSPAN[$w]}
		local end_row=$((row + height))
		if ((end_row > max_row)); then
			max_row=$end_row
		fi
	done
	_TUI_P_CONTENT_H[$pane]=$max_row
}

# _tui_scroll.max_off PANE - sets _SC_MAX = max(0, _TUI_P_CONTENT_H[PANE] -
# viewport rows), where viewport rows = _CR_H from _tui._content_rect PANE.
# Must be called after measure and after _tui._content_rect to get the
# viewport height.
_tui_scroll.max_off() {
	local pane="$1"
	local content_h="${_TUI_P_CONTENT_H[$pane]:-0}"
	_tui._content_rect "$pane" # this pane's own viewport: _CR_H is whatever pane was measured last
	local viewport_h="$_CR_H"
	_SC_MAX=$((content_h - viewport_h))
	((_SC_MAX < 0)) && _SC_MAX=0
}

# _tui_scroll.clamp PANE - clamps _TUI_P_SOFF_V[PANE] into [0, _SC_MAX].
# Returns 0 if the value changed, 1 if it was already in range.
# _SC_MAX must be set by max_off before calling this.
_tui_scroll.clamp() {
	local pane="$1"
	local offset="${_TUI_P_SOFF_V[$pane]:-0}"
	if ((offset < 0)); then
		_TUI_P_SOFF_V[$pane]=0
		_TUI_HZ_DIRTY=1 # every widget of the pane moved on screen: the hit index is stale
		return 0
	elif ((offset > _SC_MAX)); then
		_TUI_P_SOFF_V[$pane]=$_SC_MAX
		_TUI_HZ_DIRTY=1
		return 0
	fi
	return 1
}

# _tui_scroll.reveal WIDGET - only when the widget's pane has _TUI_P_SCROLL v
# or both: sets _TUI_P_SOFF_V of its pane so the widget's rows [row, row+h)
# lie inside the viewport (scroll up when row < offset, down when row+h >
# offset+viewport, otherwise leave it), then clamps. Returns 0 if the offset
# changed, 1 if not (also 1 for a widget in a pane that does not scroll
# vertically).
_tui_scroll.reveal() {
	local widget="$1"
	local pane="${_TUI_W_PANE[$widget]:-}"
	[[ -z "$pane" ]] && return 1

	local scroll="${_TUI_P_SCROLL[$pane]:-none}"
	# Only scroll if v or both
	[[ "$scroll" != "v" && "$scroll" != "both" ]] && return 1

	local widget_row="${_TUI_W_ROW[$widget]:-0}"
	local widget_height="${_TUI_W_HEIGHT[$widget]:-1}"
	if ! [[ "$widget_height" =~ ^[0-9]+$ ]]; then
		widget_height=1
	fi
	((${_TUI_W_ROWSPAN[$widget]:-0} > widget_height)) && widget_height=${_TUI_W_ROWSPAN[$widget]}

	_tui_scroll.measure "$pane"
	_tui._content_rect "$pane" # this pane's own viewport, not the last pane measured
	local offset="${_TUI_P_SOFF_V[$pane]:-0}"
	local viewport_h="$_CR_H"
	local widget_end=$((widget_row + widget_height))

	local new_offset=$offset
	local reveal_changed=1

	# Scroll up if widget starts above viewport
	if ((widget_row < offset)); then
		new_offset=$widget_row
		reveal_changed=0
	# Scroll down if widget ends below viewport
	elif ((widget_end > offset + viewport_h)); then
		new_offset=$((widget_end - viewport_h))
		reveal_changed=0
	fi

	_TUI_P_SOFF_V[$pane]=$new_offset
	((new_offset != offset)) && _TUI_HZ_DIRTY=1
	_tui_scroll.max_off "$pane"
	_tui_scroll.clamp "$pane"
	local clamp_changed=$?

	# Return 0 if either reveal or clamp changed the offset
	if ((reveal_changed == 0 || clamp_changed == 0)); then
		return 0
	fi
	return 1
}

# _tui_scroll.settle PANE - ensure the vertical scroll offset is valid for
# a leaf pane: measures content height, computes max offset, and clamps the
# offset into [0, max]. Called after layout is final (when pane geometry is set).
# Does nothing for panes that do not scroll vertically.
_tui_scroll.settle() {
	local pane="$1"
	local scroll="${_TUI_P_SCROLL[$pane]:-none}"
	# Only settle if v or both
	[[ "$scroll" != "v" && "$scroll" != "both" ]] && return 0

	# Measure content height, get viewport height, compute and clamp max offset
	_tui_scroll.measure "$pane"
	_tui._content_rect "$pane"
	_tui_scroll.max_off "$pane"
	_tui_scroll.clamp "$pane"
	_tui_scroll.stuck "$pane"
}

# _tui_scroll.stuck PANE - sets/unsets _TUI_P_STUCK[PANE]: among widgets with
# pin="top" and _TUI_W_ROW <= _TUI_P_SOFF_V (scrolled past or at the top edge),
# the one with the largest row wins (one pin sticks at a time). Clears the stuck
# entry if no pinned widget qualifies.
_tui_scroll.stuck() {
	local pane="$1"
	local offset="${_TUI_P_SOFF_V[$pane]:-0}"
	local stuck_id="" stuck_row=-1
	local w
	for w in "${_TUI_W_ORDER[@]}"; do
		[[ "${_TUI_W_PANE[$w]:-}" == "$pane" ]] || continue
		[[ "${_TUI_W_PIN[$w]:-}" == "top" ]] || continue
		local wrow="${_TUI_W_ROW[$w]:-0}"
		# Only stick if row <= offset (scrolled past or at the edge)
		if ((wrow <= offset)); then
			# Keep the one with the largest row
			if ((wrow > stuck_row)); then
				stuck_id="$w"
				stuck_row=$wrow
			fi
		fi
	done
	if [[ -n "$stuck_id" ]]; then
		_TUI_P_STUCK[$pane]="$stuck_id"
	else
		unset '_TUI_P_STUCK[$pane]'
	fi
}

# _tui_scroll.bar_v PANE TOTAL OFF STYLE - draws a vertical scrollbar into _SC_BAR.
# PANE: pane id (used to get _TUI_P_ROW, _TUI_P_H for pane geometry)
# TOTAL: total content height
# OFF: current scroll offset
# STYLE: SGR style string to apply to the bar (e.g., $sty)
# Sets global _SC_BAR to the scrollbar escape string. No output.
# Draws nothing if total <= viewport (no scrollbar needed).
_tui_scroll.bar_v() {
	local pane="$1" total="$2" off="$3" sty="$4"
	_SC_BAR=""

	# No bar needed if content fits in viewport
	if ((total <= _CR_H)); then
		return
	fi

	# Compute track position and dimensions
	local pc=${_TUI_P_COL[$pane]}
	local pw=${_TUI_P_W[$pane]}
	local track_x=$((pc + pw - 1))

	# Compute thumb height (at least 1)
	local thumb_h=$(((_CR_H * _CR_H) / total))
	((thumb_h < 1)) && thumb_h=1

	# Compute thumb position
	local thumb_y=$((_CR_R + (off * (_CR_H - thumb_h) / (total - _CR_H))))

	# Draw track and thumb
	local i seg
	for ((i = 0; i < _CR_H; i++)); do
		if (((_CR_R + i >= thumb_y && _CR_R + i < thumb_y + thumb_h))); then
			printf -v seg '\033[%d;%dH%s\033[7m \033[0m' $((_CR_R + i)) "$track_x" "$sty"
		else
			printf -v seg '\033[%d;%dH%s\033[2m│\033[0m' $((_CR_R + i)) "$track_x" "$sty"
		fi
		_SC_BAR+="$seg"
	done
}

# _tui_scroll.bars_buf - appends scrollbars for widget panes to _TUI_FRAME.
# Loops through _TUI_P_LEAVES and draws vertical scrollbars for leaf panes
# that have scrolling enabled and content that overflows the viewport.
# Called once after the widget drawing loop in tui.render.
_tui_scroll.bars_buf() {
	local pane
	for pane in "${_TUI_P_LEAVES[@]}"; do
		# Skip if not scrollable or has output content
		local scroll="${_TUI_P_SCROLL[$pane]:-none}"
		[[ "$scroll" != "v" && "$scroll" != "both" ]] && continue
		[[ -n "${_TUI_PANE_CONTENT[$pane]:-}" ]] && continue

		# Check if content overflows
		local content_h="${_TUI_P_CONTENT_H[$pane]:-0}"
		_tui._content_rect "$pane"
		if ((content_h > _CR_H)); then
			local soff="${_TUI_P_SOFF_V[$pane]:-0}"
			_tui._style_v "${pane}_normal"
			local sty="$_SGR"

			local _SC_BAR
			_tui_scroll.bar_v "$pane" "$content_h" "$soff" "$sty"
			_TUI_FRAME+="$_SC_BAR"
		fi
	done
}

# _tui_scroll.repaint PANE - repaints a widget pane by calling _tui._draw_pane_full_buf.
# Saves and restores _TUI_FRAME. Only actually flushes if _TUI_RUNNING.
_tui_scroll.repaint() {
	local pane="$1"
	((! _TUI_RUNNING)) && return 0

	local saved_frame="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui._draw_pane_full_buf "$pane"
	local buf="$_TUI_FRAME"
	_TUI_FRAME="$saved_frame"
	[[ -n "$buf" ]] && _tui._flush "$buf"
}

# _tui_scroll.apply PANE - applies scroll offset clamping and repaints a widget pane
# if the offset changed. For output panes, queues a render instead.
# Caller must set _SC_OLD before calling to the offset BEFORE mutation.
# For widget panes: measures content, computes max, clamps offset, repaints if moved.
# For output panes: calls _tui._queue_render.
# _tui_scroll.is_output PANE - rc 0 for a pane that scrolls tui.output text (content or a line count), 1 for one that scrolls widgets
_tui_scroll.is_output() { [[ -n "${_TUI_PANE_CONTENT[$1]:-}" ]] || ((${_TUI_P_LINES[$1]:-0} > 0)); }

_tui_scroll.apply() {
	local pane="$1"
	local old_offset="${_SC_OLD:-0}"

	if _tui_scroll.is_output "$pane"; then
		# Output pane: queue render as before
		_tui._queue_render "$pane"
	else
		# Widget pane: clamp the offset, repaint if moved
		_tui_scroll.measure "$pane"
		_tui._content_rect "$pane" 2>/dev/null || true
		_tui_scroll.max_off "$pane"
		_tui_scroll.clamp "$pane"
		_tui_scroll.stuck "$pane"

		local new_offset="${_TUI_P_SOFF_V[$pane]:-0}"
		if ((old_offset != new_offset)); then
			_TUI_HZ_DIRTY=1 # the widgets moved on screen: clicks and hovers must see the new places
			_tui_scroll.repaint "$pane"
		fi
	fi
}

# tui.scroll.to TARGET [top|center|bottom] - scrolls the pane containing a
# widget (or the pane itself) so the widget or pane sits at the specified
# viewport position. With no position, shows the target with the minimal move
# needed (or top for panes). Returns 0 on success, 1 for unknown id,
# non-scrolling pane, or bad position. Repaints only when offset changed.
tui.scroll.to() {
	local target="$1" position="${2:-}" pane widget old_offset new_offset

	# Try to determine if target is a widget or pane
	if [[ -n "${_TUI_W_PANE[$target]:-}" ]]; then
		# It's a widget
		widget="$target"
		pane="${_TUI_W_PANE[$widget]}"
	elif [[ -n "${_TUI_P_ROW[$target]:-}" ]]; then
		# It's a pane
		pane="$target"
		widget=""
	else
		# Unknown id
		return 1
	fi

	# Check if pane scrolls vertically
	local scroll="${_TUI_P_SCROLL[$pane]:-none}"
	[[ "$scroll" != "v" && "$scroll" != "both" ]] && return 1

	# Get viewport height
	_tui._content_rect "$pane"
	local viewport_h="$_CR_H"

	old_offset="${_TUI_P_SOFF_V[$pane]:-0}"

	if [[ -n "$widget" ]]; then
		# Widget: calculate offset based on position and widget geometry
		local widget_row="${_TUI_W_ROW[$widget]:-0}"
		local widget_height="${_TUI_W_HEIGHT[$widget]:-1}"
		if ! [[ "$widget_height" =~ ^[0-9]+$ ]]; then
			widget_height=1
		fi

		case "$position" in
			top)
				new_offset=$widget_row
				;;
			center)
				# offset = row - (viewport - h)/2
				new_offset=$((widget_row - (viewport_h - widget_height) / 2))
				;;
			bottom)
				# offset = row + h - viewport
				new_offset=$((widget_row + widget_height - viewport_h))
				;;
			*)
				# no position: the smallest move that shows the widget
				new_offset=$old_offset
				((widget_row < old_offset)) && new_offset=$widget_row
				((widget_row + widget_height > old_offset + viewport_h)) && new_offset=$((widget_row + widget_height - viewport_h))
				;;
		esac
	else
		# Pane: calculate max offset
		local content_h max_offset
		if [[ -n "${_TUI_P_LINES[$pane]:-}" ]]; then
			# Output pane: max from _TUI_P_LINES
			content_h="${_TUI_P_LINES[$pane]:-0}"
		else
			# Widget pane: max from _TUI_P_CONTENT_H (already measured)
			content_h="${_TUI_P_CONTENT_H[$pane]:-0}"
		fi

		max_offset=$((content_h - viewport_h))
		((max_offset < 0)) && max_offset=0

		case "$position" in
			top | "")
				new_offset=0
				;;
			center)
				new_offset=$((max_offset / 2))
				;;
			bottom)
				new_offset=$max_offset
				;;
			*)
				# Invalid position
				return 1
				;;
		esac
	fi

	# Clamp offset to [0, max]
	local content_h_clamp
	if [[ -n "${_TUI_P_LINES[$pane]:-}" ]]; then
		# Output pane: max from _TUI_P_LINES
		content_h_clamp="${_TUI_P_LINES[$pane]:-0}"
	else
		# Widget pane: max from _TUI_P_CONTENT_H
		_tui_scroll.max_off "$pane" # sets _SC_MAX
		content_h_clamp="${_TUI_P_CONTENT_H[$pane]:-0}"
	fi

	local max_clamp=$((content_h_clamp - viewport_h))
	((max_clamp < 0)) && max_clamp=0

	if ((new_offset < 0)); then
		new_offset=0
	elif ((new_offset > max_clamp)); then
		new_offset=$max_clamp
	fi

	_TUI_P_SOFF_V[$pane]=$new_offset

	# Check if offset changed
	if ((old_offset != new_offset)); then
		_TUI_HZ_DIRTY=1
		if ((_TUI_RUNNING)); then
			# Repaint if UI is running
			if [[ -n "${_TUI_PANE_CONTENT[$pane]:-}" ]]; then
				# Output pane: queue render
				_tui._queue_render "$pane"
			else
				# Widget pane: use shared repaint helper
				_tui_scroll.repaint "$pane"
			fi
		fi
	fi

	return 0
}
