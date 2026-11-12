#!/usr/bin/env bash
# debug.sh - debug event bus behind `dabt --debug`: counters plus a ring buffer of recent events.
#
#   tui.debug.event NAME [DETAIL]   record one event (NAME is CATEGORY.what, e.g. cache.page.miss); no-op unless TUI_DEBUG=1
#   tui.debug.enable [CATEGORIES]   turn debugging on; CATEGORIES is a comma list (cache,render), empty = all
#   tui.debug.reset                 clear the ring buffer, the counters and the page-visit tallies
#
# Hot paths guard the call with ((TUI_DEBUG)) so a normal run pays one arithmetic test and no function call.
# requires: perf tui_configuration

declare -gi TUI_DEBUG="${TUI_DEBUG:-0}"
declare -g TUI_DEBUG_CATS="${TUI_DEBUG_CATS:-}"
declare -ga _TUI_DBG_RING=()  # "TIME_US NAME DETAIL", oldest first
declare -gA _TUI_DBG_COUNT=() # event name -> total
declare -gi _TUI_DBG_RING_MAX="$TUI_DEBUG_RING_MAX"
declare -g _TUI_DBG_LAST_VISIT=""                     # "PAGE hit|miss Nms" of the latest tui.load_cached
declare -g _TUI_DBG_LAST_SWITCH=""                    # "PAGE Nms": the whole tui.goto (save, load or replay, focus, render)
declare -g _TUI_DBG_LAST_INPUT="" _TUI_DBG_IN_NAME="" # "KEY|MOUSE NAME Nms": event received until the loop pass that handled it ends
declare -gi _TUI_DBG_IN_T0=0
declare -gA _TUI_DBG_SEEN=()                         # page -> 1 once visited: only a page's first visit says whether it was prepared
declare -gi _TUI_DBG_FIRST_N=0 _TUI_DBG_FIRST_HIT=0  # first visits, and how many of them found the page already cached
declare -gi _TUI_DBG_SEQ=0                           # events recorded so far: a cheap "did anything change" stamp for the panels
declare -gi _TUI_DBG_T0=${EPOCHREALTIME//[!0-9]/}    # start of the run: the dev-tools Events tab shows times relative to it
declare -gA _TUI_DBG_VISITS=() _TUI_DBG_PAGE_LAST=() # page -> loads, and "hit|miss Nms" of its latest load
declare -gi _TUI_DBG_DOCK=0 _TUI_DBG_ROWS=0          # rows the dev-tools dock takes; rows the debug UI reserves in all (strip + dock)
declare -gi _TUI_DBG_BAR=0                           # 1 while the status strip (chrome/tui_debugbar.sh) owns the row above the footer

# tui.debug.event NAME [DETAIL] - counts NAME and appends it to the ring when its category is enabled.
tui.debug.event() {
	((TUI_DEBUG)) || return 0
	local name="$1" category="${1%%.*}"
	[[ -z "$TUI_DEBUG_CATS" || ",$TUI_DEBUG_CATS," == *",$category,"* ]] || return 0
	_TUI_DBG_COUNT[$name]=$((${_TUI_DBG_COUNT[$name]:-0} + 1))
	_TUI_DBG_SEQ+=1
	_TUI_DBG_RING+=("${EPOCHREALTIME//[!0-9]/} $name ${2:-}")
	# amortised trim: drop the oldest half-budget only once the ring doubles
	((${#_TUI_DBG_RING[@]} > _TUI_DBG_RING_MAX * 2)) && _TUI_DBG_RING=("${_TUI_DBG_RING[@]: -_TUI_DBG_RING_MAX}")
	return 0
}

# _tui_debug.switch PAGE START_US - one tui.goto finished: the total time from the call to the repainted page.
_tui_debug.switch() {
	((TUI_DEBUG)) || return 0
	local name="${1##*/}"
	_TUI_DBG_LAST_SWITCH="${name%.xml} $(((${EPOCHREALTIME//[!0-9]/} - $2) / 1000))ms"
	tui.debug.event page.switch "$_TUI_DBG_LAST_SWITCH"
	_tui_debugbar.refresh
}

# _tui_debug.input_begin NAME - an event (key or click) was received; the clock runs until _tui_debug.input_end.
_tui_debug.input_begin() {
	((TUI_DEBUG)) || return 0
	_TUI_DBG_IN_NAME="$1"
	_TUI_DBG_IN_T0=${EPOCHREALTIME//[!0-9]/}
}

# _tui_debug.input_end - the main-loop pass that handled the event is over (its frame is flushed): records the duration.
_tui_debug.input_end() {
	((TUI_DEBUG && _TUI_DBG_IN_T0)) || return 0
	_TUI_DBG_LAST_INPUT="$_TUI_DBG_IN_NAME $(((${EPOCHREALTIME//[!0-9]/} - _TUI_DBG_IN_T0) / 1000))ms"
	_TUI_DBG_IN_T0=0
	tui.debug.event input.done "$_TUI_DBG_LAST_INPUT"
	_tui_debugbar.refresh
}

# _tui_debug.reserve - recomputes the rows the strip and the dock take from the page (_tui._root_h subtracts them).
_tui_debug.reserve() { _TUI_DBG_ROWS=$((_TUI_DBG_BAR + _TUI_DBG_DOCK)); }

# tui.debug.enable [CATEGORIES] - turns debugging on (and perf tracking, which feeds the counters).
tui.debug.enable() {
	TUI_DEBUG=1
	TUI_DEBUG_CATS="${1:-}"
	_TUI_PERF_TRACKING=1
}

tui.debug.reset() {
	_TUI_DBG_RING=()
	_TUI_DBG_COUNT=()
	_TUI_DBG_LAST_VISIT="" _TUI_DBG_LAST_SWITCH="" _TUI_DBG_LAST_INPUT="" _TUI_DBG_IN_NAME=""
	_TUI_DBG_IN_T0=0
	_TUI_DBG_SEEN=() _TUI_DBG_VISITS=() _TUI_DBG_PAGE_LAST=()
	_TUI_DBG_FIRST_N=0 _TUI_DBG_FIRST_HIT=0 _TUI_DBG_SEQ=0
}

# _tui_debug.visit PAGE hit|miss START_US - one page load finished: records how long it took, and whether it was cached.
_tui_debug.visit() {
	((TUI_DEBUG)) || return 0
	local name="${1##*/}" kind="$2" ms=$(((${EPOCHREALTIME//[!0-9]/} - $3) / 1000))
	name="${name%.xml}"
	_TUI_DBG_LAST_VISIT="$name $kind ${ms}ms"
	_TUI_DBG_VISITS[$1]=$((${_TUI_DBG_VISITS[$1]:-0} + 1))
	_TUI_DBG_PAGE_LAST[$1]="$kind ${ms}ms"
	if [[ -z "${_TUI_DBG_SEEN[$1]:-}" ]]; then
		_TUI_DBG_SEEN[$1]=1
		_TUI_DBG_FIRST_N+=1
		[[ "$kind" == hit ]] && _TUI_DBG_FIRST_HIT+=1
	fi
	tui.debug.event page.visit "$_TUI_DBG_LAST_VISIT"
}

((TUI_DEBUG)) && _TUI_PERF_TRACKING=1
