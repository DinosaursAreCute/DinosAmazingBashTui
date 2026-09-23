#!/usr/bin/env bash
# profile_calls.sh - time framework calls in isolation (per-call cost, headless).
#   tools/debug/profile_calls.sh [-n ITERATIONS] 'COMMAND ARGS' ['COMMAND ARGS' ...]
#   tools/debug/profile_calls.sh 'tui.output p "hello"' 'tui.class p panel' 'tui.bind.table'
# Runs each command ITERATIONS times (default 50) in the current shell (after sourcing tui.sh, with a small fixture:
# a root pane and a pane called "p") and prints microseconds per call. A call that costs milliseconds is either doing
# a fork ($(...), < <(...), a pipe to awk/sed) or looping over something large.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
N=50
[[ "$1" == -n ]] && {
	N="$2"
	shift 2
}
(($#)) || {
	sed -n '2,9p' "$0" | sed 's/^# \?//'
	exit 1
}
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
cd "$DIR" && source ./tui.sh
_TUI_ROWS=45
_TUI_COLS=150
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_H[root]=45
_TUI_P_W[root]=150
tui.hsplit root p:1 q:1 >/dev/null 2>&1
for c in "$@"; do
	a=${EPOCHREALTIME/[.,]/}
	for ((i = 0; i < N; i++)); do eval "$c" >/dev/null 2>&1; done
	b=${EPOCHREALTIME/[.,]/}
	printf '%8d us/call   %s\n' $(((b - a) / N)) "$c"
done
