#!/usr/bin/env bash
# tui_log.sh - the app log: one file per day under $TUI_LOG_DIR, filtered by a level (stdout is the screen).
#
#   tui.log MSG [LEVEL]      append "[HH:MM:SS] [LEVEL] MSG" when LEVEL is at or above the log level
#   tui.log.debug MSG        tui.log with level debug
#   tui.log.info MSG         tui.log with level info
#   tui.log.warn MSG         tui.log with level warn
#   tui.log.error MSG        tui.log with level error
#   tui.log.level [NAME]     print the log level, or set it: debug, info, warn, error or off
#   tui.log.file             print the path tui.log writes to today
#
# requires: tui_configuration

# 0 debug, 1 info, 2 warn, 3 error, 4 off (a number so the filter in every call is one arithmetic test)
declare -gi _TUI_LOG_LV=1
declare -g _TUI_LOG_DIR_OK=""

# tui.log.level [NAME] - prints the log level; with NAME sets it (rc 1 and unchanged for an unknown name)
tui.log.level() {
	if (($# == 0)); then
		printf '%s\n' "$TUI_LOG_LEVEL"
		return 0
	fi
	case "$1" in
		debug) _TUI_LOG_LV=0 ;;
		info) _TUI_LOG_LV=1 ;;
		warn) _TUI_LOG_LV=2 ;;
		error) _TUI_LOG_LV=3 ;;
		off) _TUI_LOG_LV=4 ;;
		*)
			echo "tui.log.level: debug|info|warn|error|off" >&2
			return 1
			;;
	esac
	TUI_LOG_LEVEL="$1"
}
tui.log.level "${TUI_LOG_LEVEL:-info}" 2>/dev/null || tui.log.level info

# tui.log.file -> stdout : today's log file; the name follows the date, so a run past midnight rolls over
tui.log.file() {
	local d
	printf -v d '%(%Y-%m-%d)T' -1
	printf '%s\n' "$TUI_LOG_DIR/${d}_${TUI_APP_NAME}.log"
}

# tui.log MSG [LEVEL] - appends to tui.log.file. Fork-free once the folder exists. A level the filter does not know
# counts as info; one below the log level writes nothing, not even the folder.
tui.log() {
	local level="${2:-info}" n ts
	case "$level" in
		debug) n=0 ;;
		warn | warning) n=2 ;;
		error) n=3 ;;
		*) n=1 ;;
	esac
	((n >= _TUI_LOG_LV)) || return 0
	printf -v ts '%(%Y-%m-%d %H:%M:%S)T' -1
	if [[ "$_TUI_LOG_DIR_OK" != "$TUI_LOG_DIR" ]]; then
		[[ -d "$TUI_LOG_DIR" ]] || mkdir -p "$TUI_LOG_DIR" 2>/dev/null
		_TUI_LOG_DIR_OK="$TUI_LOG_DIR"
	fi
	printf '[%s] [%s] %s\n' "${ts#* }" "$level" "$1" 2>/dev/null >>"$TUI_LOG_DIR/${ts%% *}_${TUI_APP_NAME}.log" || return 0 # never fail a caller
}
# the level shortcuts test the level first: a dropped debug line costs one call and one comparison
tui.log.debug() {
	((_TUI_LOG_LV)) && return 0
	tui.log "$1" debug
}
tui.log.info() {
	((_TUI_LOG_LV > 1)) && return 0
	tui.log "$1" info
}
tui.log.warn() {
	((_TUI_LOG_LV > 2)) && return 0
	tui.log "$1" warn
}
tui.log.error() {
	((_TUI_LOG_LV > 3)) && return 0
	tui.log "$1" error
}
