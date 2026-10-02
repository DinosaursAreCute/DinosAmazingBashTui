# demo_generated.t.sh - the Generated demo page (share/demo/generated.xml): a template and loops driven by the values
# the control panel writes as an addon (share/demo/generated_callbacks.sh).

source "$REPO/share/demo/generated_callbacks.sh"

t_generated_int_is_clamped_and_falls_back() {
	_gn_int 4 1 5 3
	eq 4 "$_GN_INT"
	_gn_int 99 1 5 3
	eq 5 "$_GN_INT"
	_gn_int 0 1 5 3
	eq 1 "$_GN_INT"
	_gn_int abc 1 5 3
	eq 3 "$_GN_INT"
	_gn_int " 07 " 0 6 2
	eq 6 "$_GN_INT" # 7 clamped; the leading zero is not read as octal
}

t_generated_xml_escapes_and_shortens() {
	_gn_xml 'A&B <"x">'
	eq 'A&amp;B &lt;&quot;x&quot;&gt;' "$_GN_XML"
	_gn_xml '123456789012345678901234567890'
	eq '12345678901234567890' "$_GN_XML"
}

_gg_apply() { # CARDS ITEMS TITLE COMPACT(1|0) : press "Generate" with these entries, return the addon folder set up
	TUI_APP_CONF="$_T_ROOT/ga"
	rm -rf "$TUI_APP_CONF"
	local _gg_saved
	_gg_saved="$(declare -f tui.page.refresh)"
	_GG_GOTO=""
	tui.page.refresh() { _GG_GOTO="refreshed"; }
	tui.set inp_cards "$1"
	tui.set inp_items "$2"
	tui.set inp_title "$3"
	tui.set chk_compact "$4"
	on_gen_apply
	eval "$_gg_saved" # the mock must not outlive this call: later tests use the real one
	_TUI_ADDON_DIRS=("$TUI_APP_CONF/addons")
	tui.parse.file "$REPO/share/demo/generated.xml"
	tui_addon.apply "$_P_ROOT" "$REPO/share/demo/generated.xml"
	tui_compose.expand "$_P_ROOT"
}

ti_generated_values_become_cards_items_and_title() {
	_gg_apply 2 8 'A&B "x"' 0                                                                            # 8 items: past the page's old limit of 6
	eq "refreshed" "$_GG_GOTO"                                                                           # the callback ends in tui.page.refresh
	ok '[[ -n "${_N_BY_ID[card0_c]:-}" && -n "${_N_BY_ID[card1_c]:-}" && -z "${_N_BY_ID[card2_c]:-}" ]]' # two cards: 0..1
	tui_node.attr_get "${_N_BY_ID[card1_c]}" title
	eq 'A&B "x" #1' "$_N_ATTR_V"
	ok '[[ -n "${_N_BY_ID[card0_item7]:-}" && -z "${_N_BY_ID[card0_item8]:-}" ]]' # eight items: 0..7
	tui_node.attr_get "${_N_BY_ID[card1_foot_full]}" text
	eq "(full view)" "$_N_ATTR_V"
}

ti_generated_compact_switches_the_if_branch() {
	_gg_apply 7 0 Mini 1 # 7 cards: past the page's old limit of 5
	tui_node.attr_get "${_N_BY_ID[card0_foot_compact]}" text
	eq "(compact)" "$_N_ATTR_V"
	ok '[[ -z "${_N_BY_ID[card0_item0]:-}" ]]' # zero items
	tui_node.attr_get "${_N_BY_ID[card6_c]}" title
	eq "Mini #6" "$_N_ATTR_V"
}

ti_generated_page_builds_with_default_values_and_validates() {
	TUI_APP_CONF="$_T_ROOT/gb"
	rm -rf "$TUI_APP_CONF"
	_TUI_ADDON_DIRS=()
	tui.reset_ui
	tui.load "$REPO/share/demo/generated.xml" 2>"$_T_ROOT/gb.err"
	eq "" "$(cat "$_T_ROOT/gb.err")"
	eq "Card #2" "${_TUI_P_TITLE[card2_c]}"
	eq "label" "${_TUI_W_TYPE[card0_head]}"
	tui.validate.files "$REPO/share/demo/generated.xml"
	eq "0" "$TUI_V_ERRORS" # the same check `dabt --demo` runs at start
}

t_generated_zero_cards_is_allowed() {
	_gn_int 0 0 999999 3
	eq 0 "$_GN_INT"
}
