# config_stage.t.sh - tui.config.stage / tui.config.flush: change settings in memory while a control is being dragged or
# stepped through, write the file once afterwards.

_cs_file() {
	TUI_CONFIG_FILE="$_T_ROOT/cs_${RANDOM}.conf"
	_TUI_CFG=()
	_TUI_CFG_DIRTY=0
}

ti_config_stage_changes_memory_but_not_the_file() {
	_cs_file
	tui.config.stage glyph.progress.fill "+"
	eq "+" "$(tui.config.get glyph.progress.fill)"
	ok '[[ ! -e "$TUI_CONFIG_FILE" ]]'
}

ti_config_flush_writes_once_and_only_when_something_changed() {
	_cs_file
	tui.config.stage a 1
	tui.config.stage b 2
	tui.config.flush
	ok '[[ -r "$TUI_CONFIG_FILE" ]]'
	eq "a=1" "$(grep '^a=' "$TUI_CONFIG_FILE")"
	eq "b=2" "$(grep '^b=' "$TUI_CONFIG_FILE")"
	rm -f "$TUI_CONFIG_FILE"
	tui.config.flush # nothing staged since: no write
	ok '[[ ! -e "$TUI_CONFIG_FILE" ]]'
}

ti_config_stage_without_a_value_removes_the_key() {
	_cs_file
	tui.config.set k v
	tui.config.stage k
	tui.config.flush
	eq "" "$(grep '^k=' "$TUI_CONFIG_FILE" 2>/dev/null)"
	eq "none" "$(tui.config.get k none)"
}

ti_config_set_still_writes_at_once() {
	_cs_file
	tui.config.set k v
	eq "k=v" "$(grep '^k=' "$TUI_CONFIG_FILE")"
}
