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
	tui.paint.reset
	local buf
	buf="$(_paint_goto 3 5)AAA$(_paint_goto 7 2)BBB"
	_tui_paint.diff "$buf" # primes _TUI_PAINT_PREV
	_tui_paint.diff "$buf" # nothing changed this time
	eq "" "$_TP_OUT"
}

t_paint_only_the_changed_row_survives() {
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
