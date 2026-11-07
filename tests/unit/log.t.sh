# log.t.sh - lib/tui_log.sh: the app log and its level (debug < info < warn < error < off).

_lg_setup() { # LEVEL -> an empty log folder under the runner root, today's log file in _LG_FILE
	TUI_LOG_DIR="$_T_ROOT/lg_${RANDOM}${RANDOM}"
	_TUI_LOG_DIR_OK=""
	tui.log.level "$1"
	_LG_FILE="$(tui.log.file)"
}

_lg_teardown() { tui.log.level info; } # the runner does not reset the level: a leak would hide the log of later tests

_lg_content() { [[ -f "$_LG_FILE" ]] && printf '%s' "$(<"$_LG_FILE")"; }

ti_log_default_level_is_info() {
	local out
	out="$(
		unset TUI_LOG_LEVEL
		bash -c 'source "$1/lib/tui_configuration.sh"; source "$1/lib/tui_log.sh"; tui.log.level' _ "$REPO"
	)"
	eq "info" "$out"
	_lg_teardown
}

ti_log_info_level_drops_debug_and_keeps_the_rest() {
	_lg_setup info
	tui.log.debug "d"
	tui.log.info "i"
	tui.log.warn "w"
	tui.log.error "e"
	match "$(_lg_content)" '\[info\] i'
	match "$(_lg_content)" '\[warn\] w'
	match "$(_lg_content)" '\[error\] e'
	eq "3" "$(wc -l <"$_LG_FILE")"
	_lg_teardown
}

ti_log_debug_level_keeps_everything() {
	_lg_setup debug
	tui.log.debug "d"
	tui.log "x"
	eq "2" "$(wc -l <"$_LG_FILE")"
	match "$(_lg_content)" '\[debug\] d'
	_lg_teardown
}

ti_log_warn_level_drops_info_and_debug() {
	_lg_setup warn
	tui.log.debug "d"
	tui.log.info "i"
	tui.log.warn "w"
	tui.log.error "e"
	eq "2" "$(wc -l <"$_LG_FILE")"
	_lg_teardown
}

ti_log_error_level_keeps_only_errors() {
	_lg_setup error
	tui.log.warn "w"
	tui.log "free text" error
	eq "1" "$(wc -l <"$_LG_FILE")"
	match "$(_lg_content)" 'free text'
	_lg_teardown
}

ti_log_off_writes_nothing_and_creates_no_file() {
	_lg_setup off
	tui.log.error "e"
	tui.log "x" error
	[[ -e "$_LG_FILE" ]]
	eq "1" "$?"
	_lg_teardown
}

ti_log_a_level_name_it_does_not_know_counts_as_info() {
	_lg_setup warn
	tui.log "x" success
	eq "" "$(_lg_content)"
	tui.log.level info
	tui.log "x" success
	match "$(_lg_content)" '\[success\] x'
	_lg_teardown
}

ti_log_level_rejects_an_unknown_name_and_keeps_the_old_one() {
	tui.log.level warn
	tui.log.level loud 2>/dev/null
	eq "1" "$?"
	eq "warn" "$(tui.log.level)"
	_lg_teardown
}

ti_log_level_follows_tui_log_level_when_the_module_is_sourced() {
	local out
	out="$(TUI_LOG_LEVEL=debug bash -c 'source "$1/lib/tui_log.sh"; tui.log.level' _ "$REPO")"
	eq "debug" "$out"
	_lg_teardown
}
