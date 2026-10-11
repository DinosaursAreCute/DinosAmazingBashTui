# theme_switch.t.sh - a theme switch starts from the framework default: classes the new theme leaves out lose the old colours.
# Integration-style (ti_): each test resets the shared class tables inside a subshell, so nothing leaks into the other tests.

ti_theme_reset_empties_every_class_table() {
	local left
	left=$(
		TUI_DEFAULTS_DIR=/nonexistent # the default-theme reload is not under test
		_TUI_CLASS_FG[ts_x]="#ff0000" _TUI_CLASS_BG[ts_x]="#00ff00" _TUI_CLASS_MOD[ts_x]="bold"
		_tui.theme_reset
		printf '%s' "${_TUI_CLASS_FG[ts_x]-}${_TUI_CLASS_BG[ts_x]-}${_TUI_CLASS_MOD[ts_x]-}"
	)
	eq "" "$left"
}

ti_theme_reload_resets_before_the_page_is_reloaded() {
	local bg
	bg=$(
		TUI_DEFAULTS_DIR=/nonexistent _TUI_MARKUP_FILE="" # no page to go to: only the reset runs
		_TUI_CLASS_BG[ts_stale]="#123456"
		tui.theme.reload
		printf '%s' "${_TUI_CLASS_BG[ts_stale]-unset}"
	)
	eq unset "$bg"
}
