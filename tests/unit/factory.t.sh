# factory.t.sh - tui.factory.*: widgets created under a namespace go away together (the teardown is shared with tui.page.refresh).

t_factory_clear_forgets_every_widget_and_style_of_the_namespace() {
	tui.factory.button ns root 0 "Go" ""
	local id="$_TUI_FACTORY_LAST_ID"
	_TUI_STYLE_FG[${id}_normal]="red"
	_TUI_FOCUS_ID="$id"
	ok '[[ "${_TUI_W_TYPE[$id]:-}" == button && " ${_TUI_W_ORDER[*]} " == *" $id "* ]]'
	tui.factory.clear ns
	eq "" "${_TUI_W_TYPE[$id]:-}"
	eq "" "${_TUI_STYLE_FG[${id}_normal]:-}"
	eq "" "$_TUI_FOCUS_ID"
	ok '[[ " ${_TUI_W_ORDER[*]} " != *" $id "* ]]'
}

t_factory_clear_leaves_other_namespaces_alone() {
	tui.factory.label a root 0 "A"
	local ida="$_TUI_FACTORY_LAST_ID"
	tui.factory.label b root 1 "B"
	local idb="$_TUI_FACTORY_LAST_ID"
	tui.factory.clear a
	eq "" "${_TUI_W_TYPE[$ida]:-}"
	eq "label" "${_TUI_W_TYPE[$idb]:-}"
	tui.factory.clear b
}

t_factory_ids_unique_across_calls_and_namespaces() {
	tui.factory.label ns1 root 0 "A"
	local id1="$_TUI_FACTORY_LAST_ID"
	tui.factory.label ns1 root 1 "B"
	local id2="$_TUI_FACTORY_LAST_ID"
	tui.factory.label ns2 root 0 "C"
	local id3="$_TUI_FACTORY_LAST_ID"
	ok '[[ "$id1" != "$id2" && "$id2" != "$id3" ]]'
	tui.factory.clear ns1
	tui.factory.clear ns2
}

t_factory_grid_cells_tracked_and_parent_reset() {
	tui.factory.grid gns root 3
	eq 3 "${#_TUI_FACTORY_GRID_CELLS[@]}"
	ok '[[ "${_TUI_FACTORY_IDS[gns]}" == *"${_TUI_FACTORY_GRID_CELLS[0]}"* ]]'
	ok '[[ -n "${_TUI_P_DIR[root]:-}" ]]'
	tui.factory.clear gns
	eq "" "${_TUI_P_DIR[root]:-}"
	eq "" "${_TUI_P_CHILDREN[root]:-}"
}

t_factory_clear_on_never_used_and_twice() {
	tui.factory.clear x
	eq 0 $?
	tui.factory.label y root 0 "T"
	tui.factory.clear y
	tui.factory.clear y
	eq 0 $?
}

t_factory_after_clear_ids_unset_counter_continues() {
	tui.factory.label cs root 0 "A"
	local id1="$_TUI_FACTORY_LAST_ID"
	tui.factory.clear cs
	ok '[[ -z "${_TUI_FACTORY_IDS[cs]:-}" ]]'
	tui.factory.label cs root 0 "B"
	local id2="$_TUI_FACTORY_LAST_ID"
	ok '[[ "$id1" != "$id2" ]]'
	tui.factory.clear cs
}
