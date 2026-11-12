#!/usr/bin/env bash
# debug_console_callbacks.sh - Debug > Console: a live view of today's app log (tui.log), the counterpart of a
# browser's console. Follows new lines, filters by minimum level, pauses and clears. Public tui.* API only.

declare -g _CON_LEVEL=debug _CON_PAUSED=0 _CON_FOLLOW=1
declare -gi _CON_CLEARED=0 # file lines before this index are hidden (Clear does not touch the file)
declare -gi _CON_MAX=500   # rows shown; older ones stay in the file

# level name -> rank, matching tui.log's filter
declare -gA _CON_RANK=([debug]=0 [info]=1 [warn]=2 [error]=3)

console_visit() {
	_CON_PAUSED=0 _CON_FOLLOW=1
	tui.every 0.25 _console_refresh console_job
	_console_refresh
}

# console_visible LINE MIN_RANK - true when LINE's "[level]" tag is at or above MIN_RANK; untagged lines count as info
_console_visible() {
	local tag="${1#*\] \[}" # "level] msg"
	tag="${tag%%\]*}"
	local rank="${_CON_RANK[$tag]:-1}"
	((rank >= $2))
}

_console_refresh() {
	((_CON_PAUSED)) && return 0
	local file
	tui.capture file tui.log.file
	local -a all=() shown=()
	[[ -r "$file" ]] && mapfile -t -s "$_CON_CLEARED" all <"$file"
	local min=${_CON_RANK[$_CON_LEVEL]:-0} line
	for line in "${all[@]}"; do
		_console_visible "$line" "$min" && shown+=("$line")
	done
	((${#shown[@]} > _CON_MAX)) && shown=("${shown[@]: -_CON_MAX}")
	local text=""
	((${#shown[@]})) && printf -v text '%s\n' "${shown[@]}"
	[[ -z "$text" ]] && text="(no log lines at level ${_CON_LEVEL} or above in $file)"
	tui.set_text console_out "${text%$'\n'}"
	((_CON_FOLLOW)) && tui.scroll.to console_out bottom
	tui.set_text console_state "file    $file"$'\n'"level   >= ${_CON_LEVEL}"$'\n'"shown   ${#shown[@]} of $((${#all[@]})) lines"$'\n'"follow  $((_CON_FOLLOW ? 1 : 0))   paused $((_CON_PAUSED))   log level ${TUI_LOG_LEVEL}"
}

console_cycle_level() {
	case "$_CON_LEVEL" in
		debug) _CON_LEVEL=info ;;
		info) _CON_LEVEL=warn ;;
		warn) _CON_LEVEL=error ;;
		*) _CON_LEVEL=debug ;;
	esac
	_console_refresh
}

console_toggle_pause() {
	((_CON_PAUSED ^= 1))
	((_CON_PAUSED)) || _console_refresh
}

console_toggle_follow() {
	((_CON_FOLLOW ^= 1))
	_console_refresh
}

console_clear() {
	local file
	tui.capture file tui.log.file
	_CON_CLEARED=0
	[[ -r "$file" ]] && {
		mapfile -t _CON_TMP <"$file"
		_CON_CLEARED=${#_CON_TMP[@]}
		_CON_TMP=()
	}
	_console_refresh
}

# sample writers: exercise each level so the viewer has something to show
console_log_debug() {
	tui.log.level debug
	tui.log "debug sample" debug
	_console_refresh
}
console_log_info() {
	tui.log "info sample"
	_console_refresh
}
console_log_warn() {
	tui.log "warn sample" warn
	_console_refresh
}
console_log_error() {
	tui.log "error sample" error
	_console_refresh
}
