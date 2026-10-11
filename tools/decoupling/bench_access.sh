#!/usr/bin/env bash
# bench_access.sh - cost of one widget-field read/write per access style (mean ns over N iterations):
# direct index, the _ps wrapper (nameref per call), a case-based getter (no nameref), a hoisted nameref.
# Usage: tools/decoupling/bench_access.sh [N]
N=${1:-200000}
declare -gA _TUI_W_VALUE=([w1]=hello)
_V=""

_get_case() { case $2 in value) _V=${_TUI_W_VALUE[$1]-} ;; esac }
_get_nameref() {
	local -n _arr="_TUI_W_${2^^}"
	_V=${_arr[$1]-}
}
_set_case() { case $2 in value) _TUI_W_VALUE[$1]=$3 ;; esac }
_set_nameref() {
	local -n _arr="_TUI_W_${2^^}"
	_arr[$1]=$3
}

# time LABEL BODY: runs BODY N times, prints mean ns per iteration (loop overhead subtracted)
time_body() {
	local label=$1 body=$2 start end i
	start=${EPOCHREALTIME//[!0-9]/}
	for ((i = 0; i < N; i++)); do eval "$body"; done
	end=${EPOCHREALTIME//[!0-9]/}
	printf '%s\t%d\n' "$label" $(((end - start) * 1000 / N - loop_ns))
}

start=${EPOCHREALTIME//[!0-9]/}
for ((i = 0; i < N; i++)); do eval ':'; done
end=${EPOCHREALTIME//[!0-9]/}
loop_ns=$(((end - start) * 1000 / N))

declare -n hoisted=_TUI_W_VALUE
time_body "read  direct          " 'x=${_TUI_W_VALUE[w1]-}'
time_body "read  hoisted -n      " 'x=${hoisted[w1]-}'
time_body "read  case getter     " '_get_case w1 value'
time_body "read  nameref getter  " '_get_nameref w1 value'
time_body "write direct          " '_TUI_W_VALUE[w1]=x'
time_body "write hoisted -n      " 'hoisted[w1]=x'
time_body "write case setter     " '_set_case w1 value x'
time_body "write nameref setter  " '_set_nameref w1 value x'
