# demo_addons.t.sh - the Addons demo page (share/demo/addons.xml) and its five example addons (share/demo/addon_examples).
# Each addon is checked on the parsed tree (cheap); one case builds the page with all five through the whole engine.

_da_dir() { # NAME... : an addons folder holding only the named examples
	local n
	rm -rf "$_T_ROOT/da"
	mkdir -p "$_T_ROOT/da"
	for n; do cp "$REPO/share/demo/addon_examples/$n.xml" "$_T_ROOT/da/"; done
	_TUI_ADDON_DIRS=("$_T_ROOT/da")
}

_da_tree() { # NAME... : parse the demo page, apply the named addons, expand -> node tree in the store
	_da_dir "$@"
	tui.parse.file "$REPO/share/demo/addons.xml"
	tui_addon.apply "$_P_ROOT" "$REPO/share/demo/addons.xml"
	tui_compose.expand "$_P_ROOT"
}

_da_attr() { tui_node.attr_get "${_N_BY_ID[$1]}" "$2"; }

ti_demo_banner_toolbar_and_tidy_add_remove_replace_and_wrap() {
	_da_tree banner toolbar tidy
	local body="${_N_BY_ID[body]}" k ids=""
	for k in ${_N_KIDS[$body]}; do ids+="${_N_ID[$k]} "; done
	eq "banner_msg lbl_hello tidy_swapped toolbar_refresh toolbar_export " "$ids" # prepend, replace in place, append
	ok '[[ -z "${_N_BY_ID[lbl_legacy]:-}" ]]'                                     # removed
	_da_attr tidy_frame border
	eq "double" "$_N_ATTR_V"
	eq "${_N_BY_ID[tidy_frame]}" "${_N_PARENT[${_N_BY_ID[note]}]}" # note is wrapped
}

ti_demo_retitle_sets_attributes() {
	_da_tree retitle
	_da_attr body title
	match "$_N_ATTR_V" "Retitled by the 'retitle'"
	_da_attr lbl_hello text
	eq "Hello from the 'retitle' addon" "$_N_ATTR_V"
}

ti_demo_shout_wins_over_retitle_by_priority() {
	_da_tree retitle shout
	_da_attr body title
	match "$_N_ATTR_V" "SHOUT"
}

ti_demo_all_five_build_into_the_engine_without_errors() {
	_da_dir banner toolbar retitle shout tidy
	tui.reset_ui
	tui.load "$REPO/share/demo/addons.xml" 2>"$_T_ROOT/da.err"
	eq "" "$(cat "$_T_ROOT/da.err")"
	eq "button" "${_TUI_W_TYPE[toolbar_export]}"
	eq "label" "${_TUI_W_TYPE[banner_msg]}"
	eq "button" "${_TUI_W_TYPE[tidy_swapped]}"
	eq "" "${_TUI_W_TYPE[lbl_legacy]:-}"
	eq "double" "${_TUI_P_BORDER[tidy_frame]}"
	match "${_TUI_P_TITLE[body]}" "SHOUT"
}

ti_demo_example_files_pass_the_validator() {
	local f
	for f in "$REPO"/share/demo/addon_examples/*.xml "$REPO/share/demo/addons.xml"; do
		tui.validate.files "$f"
		eq "0" "$TUI_V_ERRORS"
	done
}
