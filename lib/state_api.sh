#!/usr/bin/env bash
# state_api.sh - fork-free accessors for per-widget and per-pane state, so modules stop indexing the
# _TUI_W_* / _TUI_P_* arrays directly.
#
# A getter leaves its result in _V (read it on the next line), a setter takes the value as its last
# argument. FIELD is the array's suffix in lower case: _TUI_W_VALUE is field "value".
#
#   _ps.widgets.get ID FIELD            widget field -> _V ("" when unset)
#   _ps.widgets.set ID FIELD VALUE      widget field = VALUE
#   _ps.panes.get ID FIELD            pane field -> _V ("" when unset)
#   _ps.panes.set ID FIELD VALUE      pane field = VALUE
#
# Hot render loops may index the arrays directly; mark each such line `# state:direct` so
# tools/map.sh can list the known exceptions.
# requires:

declare -g _V=""

# _ps.widgets.get ID FIELD -> _V - widget field value. A nameref keeps the field lookup generic at one call's cost.
_ps.widgets.get() {
	local -n _ps_arr="_TUI_W_${2^^}"
	_V=${_ps_arr[$1]-}
}

# _ps.widgets.set ID FIELD VALUE - sets a widget field.
_ps.widgets.set() {
	local -n _ps_arr="_TUI_W_${2^^}"
	_ps_arr[$1]=$3
}

# _ps.panes.get ID FIELD -> _V - pane field value.
_ps.panes.get() {
	local -n _ps_arr="_TUI_P_${2^^}"
	_V=${_ps_arr[$1]-}
}

# _ps.panes.set ID FIELD VALUE - sets a pane field.
_ps.panes.set() {
	local -n _ps_arr="_TUI_P_${2^^}"
	_ps_arr[$1]=$3
}
