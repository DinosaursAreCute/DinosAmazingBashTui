#!/usr/bin/env bash
# live_updates.sh [TICKS] - many live widgets updated by one timer callback: flushes (terminal writes) and time per tick.
#   legacy   every widget drawn and flushed on its own (what tui.set_label did before batching)
#   batched  tui.set_label inside the timer batch, half the values unchanged, paced to the 60 fps budget
# Prints: scenario  mean_us_per_tick  flushes_per_tick  bytes_per_tick. Headless, writes go to /dev/null.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib.sh
source "$REPO/tools/bench/lib.sh"
_bench_setup_env
_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=30 _TUI_P_W[root]=100 # the page-less setup leaves the pane at 0 x 0
_LU_N=40
_LU_TICKS="${1:-200}"
for ((_lu_i = 0; _lu_i < _LU_N; _lu_i++)); do tui.label "lu$_lu_i" root "$((_lu_i % 20 + 1))" "v"; done
_TUI_RUNNING=1
_LU_FLUSHES=0 _LU_BYTES=0
_tui.write() { ((_LU_FLUSHES++, _LU_BYTES += ${#1})); }
_lu_tick=0
_lu_legacy() { # an old-style callback: all widgets change, each is drawn and flushed alone
	local i
	for ((i = 0; i < _LU_N; i++)); do
		_TUI_W_LABEL[lu$i]="t$_lu_tick" _TUI_W_VALUE[lu$i]="t$_lu_tick"
		_tui._draw_widget "lu$i"
	done
}
_lu_batched() { # half the widgets change, half are set to what they show
	local i
	for ((i = 0; i < _LU_N; i++)); do
		if ((i % 2)); then tui.set_label "lu$i" "t$_lu_tick"; else tui.set_label "lu$i" "same"; fi
	done
}
_lu_run() { # NAME FN PACED
	local t0 t1 n
	_LU_FLUSHES=0 _LU_BYTES=0
	t0=${EPOCHREALTIME//[!0-9]/}
	for ((n = 0; n < _LU_TICKS; n++)); do
		_lu_tick=$n
		_TUI_PACE_LAST_US=0 # a tick per frame: the budget is spent
		_TUI_BATCH_PACED=$3
		_tui.batch_call "$2"
		_TUI_BATCH_PACED=0
	done
	t1=${EPOCHREALTIME//[!0-9]/}
	printf '%s\t%d\t%d\t%d\n' "$1" "$(((t1 - t0) / _LU_TICKS))" "$((_LU_FLUSHES / _LU_TICKS))" "$((_LU_BYTES / _LU_TICKS))"
}
_lu_run legacy _lu_legacy 0
_lu_run batched _lu_batched 1
