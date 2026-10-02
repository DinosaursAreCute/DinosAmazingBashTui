# addon.t.sh - lib/markup/tui_addon.sh: addon files applied to a parsed page (stage 2D).
# Cases write and parse files, so they are ti_ (integration budget).

_ad_run() { # PAGE_XML ADDON_XML -> parses the page, applies the addon (target defaults to this page)
	mkdir -p "$_T_ROOT/addons"
	rm -f "$_T_ROOT"/addons/*.xml
	printf '%s' "$1" >"$_T_ROOT/pg.xml"
	[[ -n "$2" ]] && printf '%s' "$2" >"$_T_ROOT/addons/a.xml"
	[[ -n "$3" ]] && printf '%s' "$3" >"$_T_ROOT/addons/b.xml"
	_TUI_ADDON_DIRS=("$_T_ROOT/addons")
	tui.parse.file "$_T_ROOT/pg.xml"
	tui_addon.apply "$_P_ROOT" "$_T_ROOT/pg.xml"
}

_ad_dump() { _cmp_xml "$_P_ROOT"; }

_ad_page='<pane id="side"><label id="a"/></pane><pane id="foot"/>'

ti_addon_append_prefixes_ids_with_the_addon_id() {
	_ad_run "$_ad_page" '<addon id="x" target="pg.xml"><append ref="#side"><label id="n"/></append></addon>'
	_ad_dump
	eq "document(pane#side(label#a,label#x_n),pane#foot)" "$_CX"
}

ti_addon_prefix_false_keeps_ids() {
	_ad_run "$_ad_page" '<addon id="x" target="*" prefix="false"><prepend ref="#side"><label id="n"/></prepend></addon>'
	_ad_dump
	eq "document(pane#side(label#n,label#a),pane#foot)" "$_CX"
}

ti_addon_before_after_and_prepend_keep_the_written_order() {
	_ad_run "$_ad_page" '<addon id="x" target="*"><prepend ref="#side"><label id="p1"/><label id="p2"/></prepend><after ref="#foot"><label id="f1"/><label id="f2"/></after></addon>'
	_ad_dump
	eq "document(pane#side(label#x_p1,label#x_p2,label#a),pane#foot,label#x_f1,label#x_f2)" "$_CX"
}

ti_addon_for_another_page_is_skipped() {
	_ad_run "$_ad_page" '<addon id="x" target="other.xml"><append ref="#side"><label id="n"/></append></addon>'
	_ad_dump
	eq "document(pane#side(label#a),pane#foot)" "$_CX"
}

ti_addon_lower_priority_runs_first() {
	_ad_run "$_ad_page" '<addon id="hi" target="*" priority="5"><append ref="#side"><label id="n"/></append></addon>' \
		'<addon id="lo" target="*" priority="1"><append ref="#side"><label id="n"/></append></addon>'
	_ad_dump
	eq "document(pane#side(label#a,label#lo_n,label#hi_n),pane#foot)" "$_CX"
}

ti_addon_replace_remove_set_and_wrap() {
	_ad_run "$_ad_page" '<addon id="x" target="*" prefix="false"><replace ref="#a"><label id="b"/></replace><set ref="#foot" attr="title" value="T"/><wrap ref="#foot" type="pane" id="w"/><remove ref="#b"/></addon>'
	_ad_dump
	eq "document(pane#side,pane#w(pane#foot))" "$_CX"
	tui_node.attr_get "${_N_BY_ID[foot]}" title
	eq "T" "$_N_ATTR_V"
}

ti_addon_ref_matching_nothing_is_reported() {
	_ad_run "$_ad_page" '<addon id="x" target="*"><append ref="#nope"><label id="n"/></append></addon>'
	match "${_P_ERRORS[0]}" "matches nothing"
}

ti_addon_without_directories_is_a_no_op() {
	_TUI_ADDON_DIRS=()
	printf '%s' "$_ad_page" >"$_T_ROOT/pg.xml"
	tui.parse.file "$_T_ROOT/pg.xml"
	tui_addon.apply "$_P_ROOT" "$_T_ROOT/pg.xml"
	_ad_dump
	eq "document(pane#side(label#a),pane#foot)" "$_CX"
}

ti_addon_deps_lists_the_directory_and_its_files() {
	_ad_run "$_ad_page" '<addon id="x" target="*"/>'
	local -a d=()
	tui_addon.deps d
	eq "$_T_ROOT/addons $_T_ROOT/addons/a.xml" "${d[*]}"
}

ti_addon_dir_given_twice_or_equal_to_the_app_default_is_read_once() {
	_ad_run "$_ad_page" '<addon id="x" target="*"><append ref="#side"><label id="n"/></append></addon>'
	TUI_APP_CONF="$_T_ROOT"
	_TUI_ADDON_DIRS=("$_T_ROOT/addons" "$_T_ROOT/addons")
	tui.parse.file "$_T_ROOT/pg.xml"
	tui_addon.apply "$_P_ROOT" "$_T_ROOT/pg.xml"
	eq "" "${_P_ERRORS[*]}"
	_ad_dump
	eq "document(pane#side(label#a,label#x_n),pane#foot)" "$_CX"
}

t_addon_folder_of_a_plugin_goes_when_the_plugin_is_released() {
	_TUI_ADDON_DIRS=()
	_TPL_CUR=pl_addon_test
	tui.addon.dir /x/addons
	_TPL_CUR=""
	tui.addon.dir /y/addons # registered by the app itself: not the plugin's
	eq "/x/addons /y/addons" "${_TUI_ADDON_DIRS[*]}"
	_tui_plugin.release pl_addon_test
	eq "/y/addons" "${_TUI_ADDON_DIRS[*]}"
	tui.addon.undir /y/addons
	eq "" "${_TUI_ADDON_DIRS[*]}"
}
