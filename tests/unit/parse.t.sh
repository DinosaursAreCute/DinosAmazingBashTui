# parse.t.sh - lib/markup/tui_parse.sh tokenizer -> node store (stage 1.1).

_parse_fixture() { # NAME CONTENT -> writes CONTENT to $_T_ROOT/NAME, sets _PF to its path
	_PF="$_T_ROOT/$1"
	printf '%s' "$2" >"$_PF"
}

t_parse_simple_tag_becomes_a_node_under_the_document_root() {
	_parse_fixture a.xml '<tui><pane id="root"/></tui>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	eq "1" "${#_N_CHILDREN[@]}"
	local tui_n="${_N_CHILDREN[0]}"
	eq "tui" "${_N_TYPE[$tui_n]}"
	tui_node.children "$tui_n"
	eq "1" "${#_N_CHILDREN[@]}"
	eq "pane" "${_N_TYPE[${_N_CHILDREN[0]}]}"
}

t_parse_reads_double_quoted_attribute() {
	_parse_fixture a.xml '<pane id="p1" title="Hello"/>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local n="${_N_CHILDREN[0]}"
	tui_node.attr_get "$n" title
	eq "Hello" "$_N_ATTR_V"
}

t_parse_reads_single_quoted_attribute() {
	_parse_fixture a.xml "<pane id='p1' title='Hi there'/>"
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local n="${_N_CHILDREN[0]}"
	tui_node.attr_get "$n" title
	eq "Hi there" "$_N_ATTR_V"
}

t_parse_decodes_xml_entities_in_attribute_values() {
	_parse_fixture a.xml '<label id="l1" text="a &lt;b&gt; &amp; c"/>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local n="${_N_CHILDREN[0]}"
	tui_node.attr_get "$n" text
	eq 'a <b> & c' "$_N_ATTR_V"
}

t_parse_handles_multi_line_tag() {
	_parse_fixture a.xml $'<pane id="p1"\n      title="Multi"\n      border="single"/>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local n="${_N_CHILDREN[0]}"
	tui_node.attr_get "$n" title
	eq "Multi" "$_N_ATTR_V"
	tui_node.attr_get "$n" border
	eq "single" "$_N_ATTR_V"
}

t_parse_skips_comments_anywhere() {
	_parse_fixture a.xml $'<!-- top comment -->\n<pane id="p1"/> <!-- trailing --> \n<!-- multi\nline -->\n<pane id="p2"/>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	eq "2" "${#_N_CHILDREN[@]}"
	eq "p1" "${_N_ID[${_N_CHILDREN[0]}]}"
	eq "p2" "${_N_ID[${_N_CHILDREN[1]}]}"
}

t_parse_nests_children_between_open_and_close_tags() {
	_parse_fixture a.xml '<pane id="outer"><pane id="inner"/></pane>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local outer="${_N_CHILDREN[0]}"
	tui_node.children "$outer"
	eq "1" "${#_N_CHILDREN[@]}"
	eq "inner" "${_N_ID[${_N_CHILDREN[0]}]}"
}

t_parse_records_file_and_line_on_each_node() {
	_parse_fixture a.xml $'<pane id="p1"/>\n<pane id="p2"/>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local n2="${_N_CHILDREN[1]}"
	tui_node.attr_get "$n2" __line
	eq "2" "$_N_ATTR_V"
	tui_node.attr_get "$n2" __file
	eq "$_PF" "$_N_ATTR_V"
}

t_parse_expands_include_inline_at_parent_level() {
	_parse_fixture inc.xml '<pane id="included"/>'
	_parse_fixture a.xml '<tui><include src="inc.xml"/><pane id="after"/></tui>'
	tui.parse.file "$_PF"
	tui_node.children "$_P_ROOT"
	local tui_n="${_N_CHILDREN[0]}"
	tui_node.children "$tui_n"
	eq "2" "${#_N_CHILDREN[@]}"
	eq "included" "${_N_ID[${_N_CHILDREN[0]}]}"
	eq "after" "${_N_ID[${_N_CHILDREN[1]}]}"
}

t_parse_detects_include_cycle_without_hanging() {
	_parse_fixture cyc.xml '<include src="cyc.xml"/><pane id="ok"/>'
	tui.parse.file "$_PF" 2>/dev/null
	true
}
