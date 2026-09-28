# registry.t.sh - lib/tui_registry.sh register/lookup/override/plugin-unregister (stage 0.4).

t_registry_register_then_registered_returns_fn() {
	tui.register widget t_widget_a my_draw_fn
	tui.registered widget t_widget_a
	eq "my_draw_fn" "$_TUI_REGISTERED"
}

t_registry_registered_missing_returns_false() {
	tui.registered widget t_widget_missing
	ok '(($? != 0))'
	eq "" "$_TUI_REGISTERED"
}

t_registry_same_kind_different_name_is_independent() {
	tui.register tag t_tag_a fn_a
	tui.register tag t_tag_b fn_b
	tui.registered tag t_tag_a
	eq "fn_a" "$_TUI_REGISTERED"
	tui.registered tag t_tag_b
	eq "fn_b" "$_TUI_REGISTERED"
}

t_registry_same_name_different_kind_is_independent() {
	tui.register tag t_dup fn_tag
	tui.register widget t_dup fn_widget
	tui.registered tag t_dup
	eq "fn_tag" "$_TUI_REGISTERED"
	tui.registered widget t_dup
	eq "fn_widget" "$_TUI_REGISTERED"
}

t_registry_override_order_last_registration_wins() {
	tui.register pseudo t_override fn_first
	tui.register pseudo t_override fn_second
	tui.registered pseudo t_override
	eq "fn_first fn_second" "$_TUI_REGISTERED"
	eq "fn_second" "${_TUI_REGISTERED##* }"
}

t_registry_register_multiple_fns_in_one_call() {
	tui.register hook t_hooked fn_one fn_two fn_three
	tui.registered hook t_hooked
	eq "fn_one fn_two fn_three" "$_TUI_REGISTERED"
}

t_registry_plugin_own_records_owner() {
	_tui_registry.own demo_plugin expr t_expr_a fn_expr
	eq "demo_plugin" "${_TUI_REGISTRY_OWNER[expr:t_expr_a:fn_expr]}"
}

t_registry_register_under_current_plugin_attributes_ownership() {
	_TUI_REGISTRY_CURRENT_PLUGIN=demo_plugin
	tui.register validator t_val_a fn_val
	_TUI_REGISTRY_CURRENT_PLUGIN=""
	eq "demo_plugin" "${_TUI_REGISTRY_OWNER[validator:t_val_a:fn_val]}"
}

t_registry_unregister_plugin_removes_its_handlers() {
	_TUI_REGISTRY_CURRENT_PLUGIN=demo_plugin
	tui.register layout t_layout_a fn_layout
	_TUI_REGISTRY_CURRENT_PLUGIN=""
	tui.register layout t_layout_a fn_core_layout # framework's own, no owner
	_tui_registry.unregister_plugin demo_plugin
	tui.registered layout t_layout_a
	eq "fn_core_layout" "$_TUI_REGISTERED"
}

t_registry_unregister_plugin_clears_owner_map() {
	_TUI_REGISTRY_CURRENT_PLUGIN=demo_plugin
	tui.register expr t_expr_b fn_expr_b
	_TUI_REGISTRY_CURRENT_PLUGIN=""
	_tui_registry.unregister_plugin demo_plugin
	eq "" "${_TUI_REGISTRY_OWNER[expr:t_expr_b:fn_expr_b]:-}"
}

t_registry_style_contract_records_states_and_classes() {
	tui.register.style_contract t_style_button "states:hover focus active disabled" "classes:"
	tui.registered style t_style_button
	match "$_TUI_REGISTERED" "states:hover focus active disabled"
}

t_registry_style_contracts_cover_existing_widgets() {
	tui.registered style button
	match "$_TUI_REGISTERED" "hover"
	tui.registered style checkbox
	match "$_TUI_REGISTERED" "checked"
	tui.registered style pane
	match "$_TUI_REGISTERED" "focus"
}
