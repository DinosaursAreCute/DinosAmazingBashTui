# epoch.t.sh - lib/state/tui_epoch.sh: the one entry point that invalidates caches.

t_epoch_bump_layout_advances_the_layout_generation() {
	local before=$_TUI_LY_GEN
	_tui.epoch_bump layout
	eq $((before + 1)) "$_TUI_LY_GEN"
}

t_epoch_bump_style_advances_the_style_epoch() {
	local before=$_TUI_RC_EPOCH
	_tui.epoch_bump style
	eq $((before + 1)) "$_TUI_RC_EPOCH"
}

t_epoch_bump_widgets_dirties_focus_order_and_hit_index() {
	_TUI_FOCUS_DIRTY=0 _TUI_HZ_DIRTY=0
	_tui.epoch_bump widgets
	eq "1 1" "$_TUI_FOCUS_DIRTY $_TUI_HZ_DIRTY"
}

t_epoch_bump_hit_dirties_only_the_hit_index() {
	_TUI_FOCUS_DIRTY=0 _TUI_HZ_DIRTY=0
	_tui.epoch_bump hit
	eq "0 1" "$_TUI_FOCUS_DIRTY $_TUI_HZ_DIRTY"
}

t_epoch_bump_takes_several_kinds_at_once() {
	local before=$_TUI_LY_GEN
	_TUI_HZ_DIRTY=0
	_tui.epoch_bump layout hit
	eq "$((before + 1)) 1" "$_TUI_LY_GEN $_TUI_HZ_DIRTY"
}

t_epoch_bump_rejects_an_unknown_kind() {
	local out
	out=$(_tui.epoch_bump nonsense 2>&1)
	ok '[[ "$out" == *"unknown kind"* ]]'
}
