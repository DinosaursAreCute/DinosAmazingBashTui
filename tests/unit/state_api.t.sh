#!/usr/bin/env bash
# state_api.t.sh - lib/state_api.sh fork-free widget/pane state accessors.

t_ps_widgets_get_sets_V_from_field_array() {
	_TUI_W_VALUE[ps_a]="hello"
	_ps.widgets.get ps_a value
	ok '[[ "$_V" == hello ]]'
	unset '_TUI_W_VALUE[ps_a]'
}

t_ps_widgets_get_unset_id_gives_empty() {
	_V=stale
	_ps.widgets.get ps_missing type
	ok '[[ -z "$_V" ]]'
}

t_ps_widgets_set_writes_field_array() {
	_ps.widgets.set ps_b type input
	ok '[[ "${_TUI_W_TYPE[ps_b]}" == input ]]'
	unset '_TUI_W_TYPE[ps_b]'
}

t_ps_panes_get_set_roundtrip() {
	_ps.panes.set ps_pane h 12
	_ps.panes.get ps_pane h
	ok '[[ "$_V" == 12 ]]'
	unset '_TUI_P_H[ps_pane]'
}

t_ps_get_forks_nothing() {
	_TUI_W_VALUE[ps_c]="x"
	local before=$BASHPID
	_ps.widgets.get ps_c value
	ok '[[ $BASHPID == $before ]]'
	unset '_TUI_W_VALUE[ps_c]'
}
