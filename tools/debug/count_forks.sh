#!/usr/bin/env bash
# count_forks.sh - how many processes does a framework call create? (headless)
#   tools/debug/count_forks.sh [-p PAGE] [-n RUNS] 'COMMAND ARGS' ['COMMAND ARGS' ...]
#   tools/debug/count_forks.sh -p components '_tui._handle_mouse "[<35;40;10M"' 'tui.render' 'tui.update lbl_status x'
# Loads PAGE (default components) as a fixture, then runs each command in this shell and reports how many processes
# were created meanwhile: the "last PID" field of /proc/loadavg advances by one per fork/exec (a bash `$(...)`, a
# `< <(...)`, each stage of a pipeline and each external command is one). Reading it is a builtin `read`, so the
# measurement itself is free. Repeats RUNS times (default 3) and reports the minimum, which filters out unrelated
# processes starting on the machine. 0 = fork-free. Each fork costs ~0.7-1 ms; an awk/sed/date exec ~2-4 ms.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
PAGE=components
RUNS=3
while [[ "$1" == -* ]]; do case "$1" in -p)
	PAGE="$2"
	shift 2
	;;
-n)
	RUNS="$2"
	shift 2
	;;
*) break ;; esac done
(($#)) || {
	sed -n '2,12p' "$0" | sed 's/^# \?//'
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
tui.load "$ROOT/share/demo/$PAGE.xml" >/dev/null 2>&1
_TUI_RUNNING=1
lastpid() { read -r _ _ _ _ _LP </proc/loadavg; }
for c in "$@"; do
	best=999999
	for ((r = 0; r < RUNS; r++)); do
		lastpid
		a=$_LP
		eval "$c" >/dev/null 2>&1
		lastpid
		d=$((_LP - a))
		((d < best)) && best=$d
	done
	printf '%4d forks   %s\n' "$best" "$c"
done
