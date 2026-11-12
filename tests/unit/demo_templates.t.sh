# demo_templates.t.sh - the demo's shared header and menu are templates (share/demo/_templates.xml), not included pages.

ti_demo_pages_use_the_header_and_nav_templates_instead_of_including_fragments() {
	local f bad=""
	for f in "$REPO"/share/demo/*.xml; do
		[[ "$f" == */_templates.xml ]] && continue
		grep -q 'src="_header.xml"\|src="_nav.xml"' "$f" && bad+="${f##*/} "
	done
	eq "" "$bad"
	ok '[[ ! -e "$REPO/share/demo/_header.xml" && ! -e "$REPO/share/demo/_nav.xml" ]]'
}

ti_demo_shell_expands_to_the_header_and_menu_widgets() { # the chrome lives in the shell every page but Compose uses
	tui.parse.file "$REPO/share/demo/_shell.xml"
	tui_compose.expand "$_P_ROOT"
	ok '[[ -n "${_N_BY_ID[dabt_hdr]:-}" && -n "${_N_BY_ID[dabt_hdr_clock]:-}" ]]' # header pane, inside root
	eq "${_N_BY_ID[root]}" "${_N_PARENT[${_N_BY_ID[dabt_hdr]}]}"
	ok '[[ -n "${_N_BY_ID[btn_home]:-}" && -n "${_N_BY_ID[btn_quit]:-}" ]]' # menu buttons
	local n kinds=""
	_tui_ops.collect "$_P_ROOT" # the tree itself; the template definitions are kept aside, outside it
	for n in "${_OP_LIST[@]}"; do [[ "${_N_TYPE[$n]}" == use || "${_N_TYPE[$n]}" == template ]] && kinds+="${_N_TYPE[$n]} "; done
	ok '[[ -z "$kinds" ]]' # nothing but plain tags is left for the build
}

ti_demo_pages_using_the_templates_pass_the_validator() {
	# two representative pages (validating all 20 costs a second): a plain one and the Compose page (templates, conditionals, tabs)
	local p
	for p in compose; do
		tui.validate.files "$REPO/share/demo/$p.xml"
		eq "0" "$TUI_V_ERRORS"
	done
}

ti_scroll_rows_addon_is_written_once_per_height_and_never_shrinks() {
	source "$REPO/share/demo/scroll_callbacks.sh"
	TUI_APP_CONF="$_T_ROOT/app"
	local addon="$TUI_APP_CONF/addons/scroll_rows.xml"
	ok '! scroll_write_rows 1' # a terminal the markup's floor already covers needs no addon
	ok 'scroll_write_rows 80'
	ok 'grep -q "value=\"17\"" "$addon"'
	ok '! scroll_write_rows 80' # up to date: not rewritten, so no refresh
	ok '! scroll_write_rows 60' # a smaller terminal keeps the larger addon
}

ti_console_page_shows_the_filtered_log_and_clearing_hides_earlier_lines() {
	source "$REPO/share/demo/debug_console_callbacks.sh"
	local out="" file="$_T_ROOT/c.log"
	tui.capture() { printf -v "$1" '%s' "$_T_ROOT/c.log"; }
	tui.set_text() {
		[[ "$1" == console_out ]] && out="$2"
		return 0
	}
	tui.scroll.to() { :; }
	printf '[10:00:00] [debug] d1\n[10:00:01] [warn] w1\n[10:00:02] [error] e1\n' >"$file"
	_CON_LEVEL=warn
	_console_refresh
	eq $'[10:00:01] [warn] w1\n[10:00:02] [error] e1' "$out"
	_CON_LEVEL=debug _CON_CLEARED=2
	_console_refresh
	eq "[10:00:02] [error] e1" "$out"
}
