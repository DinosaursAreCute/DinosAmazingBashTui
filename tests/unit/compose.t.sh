# compose.t.sh - lib/markup/tui_compose.sh: template/use/slot/fill, component, include params, for/if (stage 2D).
# Page-parsing cases are ti_ (integration budget): each one writes and parses files.

_cmp_page() { # XML -> parse + expand; sets _P_ROOT
	printf '%s' "$1" >"$_T_ROOT/cmp.xml"
	tui.parse.file "$_T_ROOT/cmp.xml"
	tui_compose.expand "$_P_ROOT"
}

_cmp_xml() { # NODE -> _CX : compact "type#id(kids)" form of the subtree
	local n="$1" k s
	s="${_N_TYPE[$n]}"
	[[ -n "${_N_ID[$n]:-}" ]] && s+="#${_N_ID[$n]}"
	if [[ -n "${_N_KIDS[$n]:-}" ]]; then
		s+="("
		for k in ${_N_KIDS[$n]}; do
			_cmp_xml "$k"
			s+="$_CX,"
		done
		s="${s%,})"
	fi
	_CX="$s"
}

_cmp_dump() { _cmp_xml "$_P_ROOT"; }

ti_compose_use_instantiates_template_with_params() {
	_cmp_page '<template name="card" title="Untitled"><pane id="c" title="{{@title}}"/></template>
<use template="card" title="Hi"/>'
	local c="${_N_BY_ID[c]}"
	tui_node.attr_get "$c" title
	eq "Hi" "$_N_ATTR_V"
	_cmp_dump
	eq "document(pane#c)" "$_CX"
}

ti_compose_template_default_param_used_when_missing() {
	_cmp_page '<template name="card" title="Untitled"><pane id="c" title="{{@title}}"/></template><use template="card"/>'
	tui_node.attr_get "${_N_BY_ID[c]}" title
	eq "Untitled" "$_N_ATTR_V"
}

ti_compose_use_id_prefixes_template_ids_so_two_uses_coexist() {
	_cmp_page '<template name="t"><label id="l"/></template><use template="t" id="a"/><use template="t" id="b"/>'
	_cmp_dump
	eq "document(label#a_l,label#b_l)" "$_CX"
}

ti_compose_slot_filled_by_fill_and_default_content() {
	_cmp_page '<template name="t"><pane id="p"><slot name="body"><label id="dflt"/></slot></pane></template>
<use template="t" id="x"><fill slot="body"><label id="mine"/></fill></use><use template="t" id="y"/>'
	_cmp_dump
	eq "document(pane#x_p(label#mine),pane#y_p(label#y_dflt))" "$_CX"
}

ti_compose_loose_children_fill_the_default_slot() {
	_cmp_page '<template name="t"><pane id="p"><slot/></pane></template><use template="t"><label id="k"/></use>'
	_cmp_dump
	eq "document(pane#p(label#k))" "$_CX"
}

ti_compose_template_may_use_another_template() {
	_cmp_page '<template name="in"><label id="i"/></template><template name="out"><use template="in" id="n"/></template><use template="out"/>'
	_cmp_dump
	eq "document(label#n_i)" "$_CX"
}

ti_compose_recursive_template_stops_with_an_error() {
	_cmp_page '<template name="r"><use template="r"/></template><use template="r"/>'
	ok '((${#_P_ERRORS[@]} > 0))'
	match "${_P_ERRORS[0]}" "recursion"
}

ti_compose_component_src_defines_a_tag() {
	printf '<pane id="box" title="{{@title}}"><slot/></pane>' >"$_T_ROOT/box.xml"
	_cmp_page '<component name="box" src="box.xml"/><box title="T"><label id="in"/></box>'
	_cmp_dump
	eq "document(pane#box(label#in))" "$_CX"
	tui_node.attr_get "${_N_BY_ID[box]}" title
	eq "T" "$_N_ATTR_V"
}

ti_compose_for_repeats_body_per_item() {
	_cmp_page '<for each="a b c" as="x"><label id="l_{{@x}}" text="{{@x}}"/></for>'
	_cmp_dump
	eq "document(label#l_a,label#l_b,label#l_c)" "$_CX"
}

ti_compose_for_index_variable() {
	_cmp_page '<for count="2" index="i"><label id="r{{@i}}"/></for>'
	_cmp_dump
	eq "document(label#r0,label#r1)" "$_CX"
}

ti_compose_if_keeps_children_when_true_and_drops_when_false() {
	_cmp_page '<if test="a==a"><label id="y"/></if><if test="a==b"><label id="n"/></if>'
	_cmp_dump
	eq "document(label#y)" "$_CX"
}

ti_compose_if_truthiness_and_not_equal_and_else() {
	_cmp_page '<if test="false"><label id="t"/><else><label id="e"/></else></if><if test="x!=y"><label id="ne"/></if><if test=""><label id="z"/></if>'
	_cmp_dump
	eq "document(label#e,label#ne)" "$_CX"
}

ti_compose_if_tests_a_template_param() {
	_cmp_page '<template name="t"><if test="{{@mode}}==big"><label id="b"/></if></template><use template="t" mode="big"/><use template="t" id="s" mode="small"/>'
	_cmp_dump
	eq "document(label#b)" "$_CX"
}

ti_compose_include_with_params_substitutes_in_included_file() {
	printf '<label id="{{@name}}" text="{{@text}}"/>' >"$_T_ROOT/inc.xml"
	printf '<pane id="p"><include src="inc.xml" name="hello" text="World"/></pane>' >"$_T_ROOT/cmp.xml"
	tui.parse.file "$_T_ROOT/cmp.xml"
	tui_node.attr_get "${_N_BY_ID[hello]}" text
	eq "World" "$_N_ATTR_V"
	eq "${_N_BY_ID[p]}" "${_N_PARENT[${_N_BY_ID[hello]}]}"
}

ti_compose_if_branches_may_share_an_id() {
	_cmp_page '<if test="a==a"><label id="x"/><else><label id="x"/></else></if>'
	ok '[[ -n "${_N_BY_ID[x]:-}" ]]'
	eq "${_N_BY_ID[x]}" "${_N_KIDS[$_P_ROOT]}"
}
