#!/usr/bin/env bash
# tui_factory.sh - namespace-scoped widget and pane constructor utilities.
#
# tui.factory.* creates widgets/panes with auto-generated, globally unique
# namespace-scoped ids and tracks them for batch teardown. Sourced by tui.sh.
# requires:

# shellcheck source=../state.sh
source "${SCRIPT_DIR}/state.sh"

_tui_factory.next_id() {
	local ns="$1" n="${_TUI_FACTORY_COUNTER[$ns]:-0}"
	_TUI_FACTORY_COUNTER[$ns]=$((n + 1))
	_TUI_FACTORY_LAST_ID="__f_${ns}_${n}"
}

_tui_factory.track() {
	local ns="$1" id="$2"
	_TUI_FACTORY_IDS[$ns]="${_TUI_FACTORY_IDS[$ns]:+${_TUI_FACTORY_IDS[$ns]} }${id}"
}

# _tui_factory.make NS TUID_FUNC [ARGS...] - internal helper: generates next id,
# tracks it, and calls TUID_FUNC with id as first arg plus remaining ARGS
_tui_factory.make() {
	local ns="$1" tui_func="$2"
	shift 2
	_tui_factory.next_id "$ns"
	local id="$_TUI_FACTORY_LAST_ID"
	_tui_factory.track "$ns" "$id"
	"$tui_func" "$id" "$@"
}

# Each tui.factory.* constructor leaves the id it generated in
# _TUI_FACTORY_LAST_ID: `tui.factory.button ...; id="$_TUI_FACTORY_LAST_ID"`.
# Deliberately does NOT also print it. In a TUI, stdout is the screen - a
# constructor typically called in a loop the caller doesn't wrap in a
# command substitution (see tui.factory.grid's own usage pattern) would
# otherwise leak raw id text straight onto the terminal outside any pane's
# clipping the moment someone forgets the `$(...)`, which is exactly the
# failure mode this avoids by only ever writing to a variable.
tui.factory.label() {
	local ns="$1" pane="$2" row="$3" text="$4"
	_tui_factory.make "$ns" "tui.label" "$pane" "$row" "$text"
}

tui.factory.button() {
	local ns="$1" pane="$2" row="$3" text="$4" action="$5"
	_tui_factory.make "$ns" "tui.button" "$pane" "$row" "$text" "$action"
}

tui.factory.input() {
	local ns="$1" pane="$2" row="$3" placeholder="$4" label="${5:-}" submit="${6:-}"
	_tui_factory.make "$ns" "tui.input" "$pane" "$row" "$placeholder" "$label" "$submit"
}

tui.factory.checkbox() {
	local ns="$1" pane="$2" row="$3" label="$4" checked="${5:-}" action="${6:-}"
	_tui_factory.make "$ns" "tui.checkbox" "$pane" "$row" "$label" "$checked" "$action"
}

# tui.factory.grid NAMESPACE PARENT COUNT [COLS] [FIT] [ROW_WEIGHTS] [COL_WEIGHTS]
# The dynamic-sizing counterpart to <pane split="grid">: takes an item
# COUNT rather than a fixed shape (COLS optional - auto-square if
# omitted), builds it via tui.grid with COUNT freshly auto-generated,
# namespace-tracked ids, and leaves them in order in
# _TUI_FACTORY_GRID_CELLS for the caller to populate:
#   for i in "${!items[@]}"; do
#       tui.factory.button "$ns" "${_TUI_FACTORY_GRID_CELLS[$i]}" 0 "${items[$i]}" my_action
#   done
tui.factory.grid() {
	local ns="$1" parent="$2" count="$3" cols="${4:-}" fit="${5:-pack}"
	local roww="${6:-}" colw="${7:-}"

	_TUI_FACTORY_GRID_PARENTS[$ns]="${_TUI_FACTORY_GRID_PARENTS[$ns]:+${_TUI_FACTORY_GRID_PARENTS[$ns]} }${parent}"

	local -a cell_ids=()
	local i
	for ((i = 0; i < count; i++)); do
		_tui_factory.next_id "$ns"
		_tui_factory.track "$ns" "$_TUI_FACTORY_LAST_ID"
		cell_ids+=("$_TUI_FACTORY_LAST_ID")
	done

	tui.grid "$parent" "" "$cols" "$fit" "$roww" "$colw" "${cell_ids[@]}"

	local r
	for r in "${_TUI_LAST_GRID_ROWS[@]}"; do
		_tui_factory.track "$ns" "$r"
	done
	_TUI_FACTORY_GRID_CELLS=("${cell_ids[@]}")
}

# tui.factory.clear NAMESPACE - tears down every widget/pane created under
# NAMESPACE (removing it from _TUI_W_ORDER and its widget
# or pane state entirely) and resets any grid parent it built back to a
# plain, childless leaf pane, ready for a fresh build. Safe to call on a
# namespace that was never used, or has already been cleared.
tui.factory.clear() {
	local ns="$1"
	local -a ids=()
	read -ra ids <<<"${_TUI_FACTORY_IDS[$ns]:-}"

	if ((${#ids[@]} > 0)); then
		local -a keep_order=()
		local w drop id
		for w in "${_TUI_W_ORDER[@]}"; do
			drop=0
			for id in "${ids[@]}"; do [[ "$w" == "$id" ]] && {
				drop=1
				break
			}; done
			((drop)) || keep_order+=("$w")
		done
		_TUI_W_ORDER=("${keep_order[@]}")
		_tui_w.changed

		for id in "${ids[@]}"; do
			[[ "${_TUI_FOCUS_ID:-}" == "$id" ]] && {
				_TUI_FOCUS_ID=""
				_TUI_FOCUS_IDX=-1
			}
			_tui_engine.forget_widget "$id"
			_tui_engine.forget_pane "$id"
		done
		_tui_engine.forget_styles "${ids[@]}"
	fi

	local -a parents=()
	read -ra parents <<<"${_TUI_FACTORY_GRID_PARENTS[$ns]:-}"
	local p
	for p in "${parents[@]}"; do
		unset '_TUI_P_DIR[$p]' '_TUI_P_CHILDREN[$p]' '_TUI_P_WEIGHTS[$p]'
	done

	unset '_TUI_FACTORY_IDS[$ns]' '_TUI_FACTORY_GRID_PARENTS[$ns]'

	if ((${#ids[@]} > 0 || ${#parents[@]} > 0)); then
		_TUI_P_LEAVES=()
		_TUI_P_ALL=()
		_tui._collect_leaves "root"
	fi
}
