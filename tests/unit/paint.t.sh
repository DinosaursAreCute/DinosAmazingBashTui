# paint.t.sh - lib/render/tui_paint.sh per-row damage tracking (stage 2B).

_paint_goto() { printf '\e[%d;%dH' "$1" "$2"; }

t_paint_first_flush_keeps_everything() {
	tui.paint.reset
	local buf
	buf="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	_tui_paint.diff "$buf"
	eq "$buf" "$_TP_OUT"
}

t_paint_second_identical_flush_drops_unchanged_rows() {
	_t_needs_caches || return 0
	tui.paint.reset
	local buf
	buf="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	_tui_paint.diff "$buf" # primes _TUI_PAINT_PREV
	_tui_paint.diff "$buf" # nothing changed this time
	eq "" "$_TP_OUT"
}

t_paint_only_the_changed_row_survives() {
	_t_needs_caches || return 0
	tui.paint.reset
	local buf1 buf2
	buf1="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	buf2="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)CCC" # row 7's content changed
	_tui_paint.diff "$buf1"
	_tui_paint.diff "$buf2"
	eq "$(_paint_goto 7 2)CCC" "$_TP_OUT"
}

t_paint_content_before_the_first_goto_is_never_suppressed() {
	tui.paint.reset
	local buf
	buf="PRELUDE$(_paint_goto 1 1)X"
	_tui_paint.diff "$buf"
	_tui_paint.diff "$buf" # same buf again - the addressed row (1) would be dropped, "PRELUDE" must not be
	match "$_TP_OUT" '^PRELUDE'
}

t_paint_reset_forces_a_full_resend() {
	tui.paint.reset
	local buf
	buf="$(_paint_goto 3 5)AAA"
	_tui_paint.diff "$buf"
	tui.paint.reset
	_tui_paint.diff "$buf"
	eq "$buf" "$_TP_OUT"
}

t_paint_row_touched_twice_in_one_buffer_is_compared_as_one_unit() {
	tui.paint.reset
	local buf1 buf2
	buf1="$(_paint_goto 3 1)AA$(_paint_goto 3 10)BB"
	buf2="$(_paint_goto 3 1)AA$(_paint_goto 3 10)ZZ" # only the second chunk on row 3 changed
	_tui_paint.diff "$buf1"
	_tui_paint.diff "$buf2"
	eq "$buf2" "$_TP_OUT" # whole row 3 resent, not just the ZZ chunk - row granularity, not column
}

t_paint_flush_second_identical_frame_writes_nothing() {
	_t_needs_caches || return 0
	tui.paint.reset
	local buf out="$_T_ROOT/pf.out"
	buf="$(_paint_goto 3 5)AAA"
	_tui_paint.flush "$buf" >/dev/null
	_tui_paint.flush "$buf" >"$out"
	eq "" "$(<"$out")"
}

t_paint_flush_sends_only_the_changed_row() {
	_t_needs_caches || return 0
	tui.paint.reset
	local b1 b2 out="$_T_ROOT/pf.out"
	b1="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	b2="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)CCC"
	_tui_paint.flush "$b1" >/dev/null
	_tui_paint.flush "$b2" >"$out"
	match "$(<"$out")" 'CCC'
	[[ "$(<"$out")" != *AAA* ]] || _t_fail "resent the unchanged row"
}

t_paint_flush_foreign_flush_invalidates_the_memory() {
	tui.paint.reset
	local buf out="$_T_ROOT/pf.out"
	buf="$(_paint_goto 3 5)AAA"
	_tui_paint.flush "$buf" >/dev/null
	_tui._flush "OTHER" >/dev/null # something else painted: PREV no longer describes the screen
	_tui_paint.flush "$buf" >"$out"
	match "$(<"$out")" 'AAA'
}

t_paint_flush_full_erase_in_buffer_is_never_diffed() {
	tui.paint.reset
	local buf out="$_T_ROOT/pf.out"
	buf=$'\e[2J'"$(_paint_goto 3 5)AAA"
	_tui_paint.flush "$buf" >/dev/null
	_tui_paint.flush "$buf" >"$out"
	match "$(<"$out")" 'AAA'
}

t_paint_flush_still_folds_the_full_frame_into_the_base() {
	_t_needs_caches || return 0
	tui.paint.reset
	_TUI_BASE_FRAME="B" _TUI_DISMISS_REPLAY=1 _TUI_FLUSH_GEN=5 _TUI_OVL_FLUSHES=0 _TUI_BASE_GEN=5
	_TUI_BASE_EPOCH=$_TUI_RC_EPOCH _TUI_BASE_ROWS=$_TUI_ROWS _TUI_BASE_COLS=$_TUI_COLS
	local buf
	buf="$(_paint_goto 3 5)AAA"
	_tui_paint.flush "$buf" >/dev/null
	_tui_paint.flush "$buf" >/dev/null # fully suppressed, still folded
	eq "B${buf}${buf}" "$_TUI_BASE_FRAME"
}

t_paint_identical_buffer_skips_the_row_split() {
	_t_needs_caches || return 0
	tui.paint.reset
	local buf
	buf="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	_tui_paint.diff "$buf"
	_tui_paint.split_rows() { _t_fail "split ran for a byte-identical buffer"; }
	_tui_paint.diff "$buf"
	eq "" "$_TP_OUT"
	unset -f _tui_paint.split_rows
	source "$REPO/lib/render/tui_paint.sh"
}

t_paint_identical_buffer_with_a_leading_run_is_never_suppressed() {
	_t_needs_caches || return 0
	tui.paint.reset
	_tui_paint.diff "XX$(_paint_goto 3 5)AAA"
	_tui_paint.diff "XX$(_paint_goto 3 5)AAA"
	eq "XX" "$_TP_OUT"
}
