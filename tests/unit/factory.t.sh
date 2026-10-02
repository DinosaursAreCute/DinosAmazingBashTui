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
