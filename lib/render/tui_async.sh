#!/usr/bin/env bash
# tui_async.sh - background painters: a function that runs in a process of its own and draws straight to the terminal, so its
# frames cost the main loop nothing (a hover or a focus highlight is never queued behind them).
#
#   tui.async.start NAME FN [ARG...]   forks FN ARG... into the background. FN runs with the process's own copy of everything
#                                      (it sees the page as it was at the fork) and paints with absolute cursor moves; its
#                                      stdin is /dev/null. At most one process per NAME (a second start replaces the first).
#   tui.async.stop NAME                ends it. tui.async.stop_all (also called by tui.reset_ui and on exit) ends every one.
#   tui.async.put NAME KEY VALUE       the main loop's way to tell a painter something (a size, a mask): a small file.
#   tui.async.get KEY VAR              the painter's side: VAR = the file's content ("" when absent).
#   tui.async.wait SECONDS             inside a painter: sleep without a fork (it waits on a pipe nobody writes to).
#   tui.async.covered                  inside a painter: rc 0 while something is open over the page (a modal, the command
#                                      palette, a layer): paint nothing then, so what is on top stays intact.
#
# One more thing keeps painters out of the way: _tui_async.cover_changed (called when a modal or a layer opens or closes)
# writes the "covered" flag the painters read.
# A painter writes a whole frame in one printf, as small as it can (changes only): the tty takes one write call whole, so a
# frame is never torn by what the main loop writes between two of its own.
# requires:

declare -gA _TUI_ASYNC_PID=()
declare -g _TUI_ASYNC_DIR="" _TUI_ASYNC_PARENT=""

# _tui_async.dir - the folder of the state files and the pipe painters wait on (made on first use, removed on exit)
_tui_async.dir() {
	[[ -n "$_TUI_ASYNC_DIR" && -d "$_TUI_ASYNC_DIR" ]] && return 0
	_TUI_ASYNC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dabt_async.XXXXXX")" || return 1
	mkfifo "$_TUI_ASYNC_DIR/pipe"
	printf '0' >"$_TUI_ASYNC_DIR/covered"
	_TUI_ASYNC_COVER=0
	_tui_async.cover_changed
}

tui.async.start() {
	local name="$1" fn="$2"
	shift 2
	_tui_async.dir || return 1
	tui.async.stop "$name"
	_TUI_ASYNC_PARENT=$BASHPID
	(
		trap 'exit 0' TERM HUP INT
		exec </dev/null
		"$fn" "$@"
	) &
	_TUI_ASYNC_PID[$name]=$!
	return 0
}

tui.async.stop() {
	local pid="${_TUI_ASYNC_PID[$1]:-}"
	[[ -n "$pid" ]] || return 0
	unset '_TUI_ASYNC_PID[$1]'
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
	return 0
}

tui.async.stop_all() {
	local name
	for name in "${!_TUI_ASYNC_PID[@]}"; do tui.async.stop "$name"; done
	[[ -n "$_TUI_ASYNC_DIR" && -d "$_TUI_ASYNC_DIR" ]] && rm -rf "$_TUI_ASYNC_DIR"
	_TUI_ASYNC_DIR=""
	return 0
}

# tui.async.active [NAME] - rc 0 while a painter (that one) runs
tui.async.active() {
	local name pid
	for name in "${!_TUI_ASYNC_PID[@]}"; do
		[[ -n "${1:-}" && "$name" != "$1" ]] && continue
		pid="${_TUI_ASYNC_PID[$name]}"
		kill -0 "$pid" 2>/dev/null && return 0
	done
	return 1
}

tui.async.put() {
	_tui_async.dir || return 1
	printf '%s' "$3" >"$_TUI_ASYNC_DIR/$1.$2"
}

tui.async.get() {
	local -n _ag_out="$2"
	_ag_out=""
	[[ -r "$_TUI_ASYNC_DIR/$1" ]] && IFS= read -r _ag_out <"$_TUI_ASYNC_DIR/$1"
	return 0
}

# tui.async.wait SECONDS - a fork-free sleep: a read with a timeout on a pipe that is held open and never written
tui.async.wait() {
	local _aw
	exec 8<>"$_TUI_ASYNC_DIR/pipe"
	read -r -t "$1" -u 8 _aw
	exec 8<&-
	return 0
}

# tui.async.covered - rc 0 while the flag says something is open over the page
tui.async.covered() {
	local c
	tui.async.get covered c
	[[ "$c" == 1 ]]
}

# _tui_async.hold - the flag at 1 until the next _tui_async.cover_changed: tui.run holds the painters while a resize is applied
# (their rectangles are the old screen's) and lets go once the page's resize hook has run
_tui_async.hold() {
	[[ -n "$_TUI_ASYNC_DIR" ]] || return 0
	_TUI_ASYNC_COVER=1
	printf '1' >"$_TUI_ASYNC_DIR/covered"
}

# _tui_async.cover_changed - the flag for the painters: 1 while a modal (the command palette, a dialog) or a layer is open.
# Written only when it changes.
declare -g _TUI_ASYNC_COVER=0
_tui_async.cover_changed() {
	local now=0
	[[ -n "$_TUI_ASYNC_DIR" ]] || return 0
	{ [[ -n "$_TUI_MODAL" ]] || ((_TUI_L_N)); } && now=1
	((now == _TUI_ASYNC_COVER)) && return 0
	_TUI_ASYNC_COVER=$now
	printf '%s' "$now" >"$_TUI_ASYNC_DIR/covered"
}
