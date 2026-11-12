# update_changed.t.sh - tui.update_changed: draws a widget only when its value differs.

_uc_draws=()
_uc_stub() {
	_uc_draws=()
	_tui._draw_widget() { _uc_draws+=("$1"); }
	_TUI_W_TYPE[a]=label
	_TUI_RUNNING=1
}

ti_update_changed_draws_a_new_value() {
	_uc_stub
	tui.update_changed a hello
	eq "a" "${_uc_draws[*]}"
	eq hello "${_TUI_W_VALUE[a]}"
}

ti_update_changed_skips_the_same_value() {
	_uc_stub
	tui.update_changed a hello
	tui.update_changed a hello
	eq "1" "${#_uc_draws[@]}"
}

ti_update_changed_draws_again_after_a_change() {
	_uc_stub
	tui.update_changed a one
	tui.update_changed a two
	eq "2" "${#_uc_draws[@]}"
}

ti_update_changed_reports_an_unknown_widget() {
	_uc_stub
	tui.notify() { :; }
	tui.update_changed nope x
	eq 1 "$?"
}
