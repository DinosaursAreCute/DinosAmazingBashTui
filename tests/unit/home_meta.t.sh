# home_meta.t.sh - lib/tui_home.sh: app.meta is written by one process at a time and only for real app runs.

_hmeta_conf() { # -> TUI_APP_CONF set to a fresh folder under the runner root
	TUI_APP_CONF="$_T_ROOT/hmeta_${RANDOM}${RANDOM}"
	mkdir -p "$TUI_APP_CONF"
	_TUI_META=()
	TUI_APP_NAME="hmeta_app"
}

t_home_meta_save_does_not_use_a_temp_name_other_processes_share() {
	_hmeta_conf
	mkdir "$TUI_APP_CONF/app.meta.tmp" # another process holding the fixed name must not stop this one
	_TUI_META[name]="x"
	_tui_home.meta_save
	eq "# DABT application metadata (written by tui.init; add your own keys with tui.app.meta_set)
name=x" "$(<"$TUI_APP_CONF/app.meta")"
}

t_home_touch_is_skipped_in_a_cache_worker() {
	_hmeta_conf
	_TUI_WARM_WORKER=1 _tui_home.touch
	[[ -e "$TUI_APP_CONF/app.meta" ]]
	eq "1" "$?"
}

t_home_touch_counts_a_run_outside_a_cache_worker() {
	_hmeta_conf
	_tui_home.touch
	_tui_home.touch
	_tui_home.meta_load
	eq "2" "${_TUI_META[runs]}"
}
