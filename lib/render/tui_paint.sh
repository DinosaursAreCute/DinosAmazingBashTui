#!/usr/bin/env bash
# tui_paint.sh - per-row damage tracking for _tui._flush (markup-v2 stage
# 2B). Every draw path already funnels through one string buffer
# (_TUI_FRAME, tui_emit.sh) addressed with \e[ROW;COLH cursor-goto
# sequences before each run of content; _tui._flush was the single point
# those bytes ever reached the terminal, but it always sent the whole
# buffer, however small the actual change. This slots in right there:
# split the buffer into per-row chunks, drop any row whose bytes are
# byte-identical to what was physically sent for that row last time, and
# flush only what's left - one write, still, just a smaller one.
#
# Deliberately row-granularity, not a full column-addressed display list:
# two chunks landing on the same row (e.g. two adjacent panes' borders
# meeting mid-row) are compared as their whole concatenation, not
# recomposited cell-by-cell. That can occasionally re-send a row whose
# visible result didn't actually change (a mixed full-render / partial-
# redraw history for the same row), but it can never wrongly SUPPRESS a
# row that did change - the byte comparison is exact, so a false "changed"
# is the only possible failure mode, never a false "same". Simpler, and
# the plan's own "bytes flushed per hover shrink" target doesn't need
# more than that.
#
# Fork-free: everything here is bash builtins/parameter expansion, no
# command substitution, matching every other hot-render-path helper.

declare -gA _TUI_PAINT_PREV=() # row number -> bytes physically flushed for that row last time
declare -gA _TP_ROW=()         # scratch (this call only): row number (see _TP_PRE_ROW) -> concatenated bytes
declare -ga _TP_ROW_ORDER=()   # rows touched this call, first-seen order
# Sentinel key for content before the first goto (rare - e.g. a bare control
# sequence). A row number is never negative, so this can't collide with a
# real one; plain "" isn't usable here - bash rejects an empty string as an
# associative-array subscript outright (confirmed: a[""]=1 errors "bad
# array subscript" even quoted, not just a quoting gotcha).
declare -g _TP_PRE_ROW="-1"

# tui.paint.reset - forget every remembered row (a full erase.all just
# blanked the physical screen, or the terminal was just taken over/resized
# drastically enough that comparing against old bytes would be meaningless
# - either way, the next flush must resend everything unconditionally).
tui.paint.reset() { _TUI_PAINT_PREV=(); }

# _tui_paint.split_rows BUF - fills _TP_ROW/_TP_ROW_ORDER: BUF cut at every
# \e[ROW;COLH boundary, each goto (kept verbatim) plus the content up to
# the next goto attributed to that ROW. Content before the first goto goes
# under _TP_PRE_ROW, always treated as changed, never cached (see
# _tui_paint.diff).
_tui_paint.split_rows() {
	local buf="$1" esc=$'\x1b'
	_TP_ROW=()
	_TP_ROW_ORDER=()
	local goto_re="$esc\[([0-9]+);[0-9]+H"
	local rest="$buf" cur_row="$_TP_PRE_ROW"
	while [[ -n "$rest" ]]; do
		if [[ "$rest" =~ $goto_re ]]; then
			local match="${BASH_REMATCH[0]}" row="${BASH_REMATCH[1]}"
			local before="${rest%%"$match"*}"
			if [[ -n "$before" ]]; then
				[[ -z "${_TP_ROW[$cur_row]+x}" ]] && _TP_ROW_ORDER+=("$cur_row")
				_TP_ROW[$cur_row]+="$before"
			fi
			rest="${rest#"$before""$match"}"
			cur_row="$row"
			[[ -z "${_TP_ROW[$cur_row]+x}" ]] && _TP_ROW_ORDER+=("$cur_row")
			_TP_ROW[$cur_row]+="$match"
		else
			[[ -z "${_TP_ROW[$cur_row]+x}" ]] && _TP_ROW_ORDER+=("$cur_row")
			_TP_ROW[$cur_row]+="$rest"
			rest=""
		fi
	done
}

# _tui_paint.diff BUF -> sets _TP_OUT to BUF with every unchanged row's
# chunk removed, and records the rows it kept as the new "last sent" bytes
# for next time.
_tui_paint.diff() {
	_tui_paint.split_rows "$1"
	_TP_OUT=""
	local row
	for row in "${_TP_ROW_ORDER[@]}"; do
		if [[ "$row" == "$_TP_PRE_ROW" || "${_TP_ROW[$row]}" != "${_TUI_PAINT_PREV[$row]:-}" ]]; then
			_TP_OUT+="${_TP_ROW[$row]}"
			[[ "$row" != "$_TP_PRE_ROW" ]] && _TUI_PAINT_PREV[$row]="${_TP_ROW[$row]}"
		fi
	done
}
