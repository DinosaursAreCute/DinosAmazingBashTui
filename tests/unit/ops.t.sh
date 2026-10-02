# ops.t.sh - lib/markup/tui_ops.sh node ops and minimal selectors (stage 2D).

# _ops_page XML -> parses XML into the node store, sets _P_ROOT
_ops_page() {
	printf '%s' "$1" >"$_T_ROOT/ops.xml"
	tui.parse.file "$_T_ROOT/ops.xml"
}

# _ops_ids ROOT SELECTOR -> _OIDS : space-joined ids of the matches, document order
_ops_ids() {
	tui_ops.select "$1" "$2"
	_OIDS=""
	local n
	for n in "${_OP_NODES[@]}"; do _OIDS+="${_OIDS:+ }${_N_ID[$n]:-?}"; done
}

_ops_kids_ids() { # NODE -> _OIDS
	tui_node.children "$1"
	_OIDS=""
	local n
	for n in "${_N_CHILDREN[@]}"; do _OIDS+="${_OIDS:+ }${_N_ID[$n]:-?}"; done
}

# ── selectors ────────────────────────────────────────────────────────────
t_ops_select_by_id() {
	_ops_page '<pane id="a"><label id="b"/></pane>'
	_ops_ids "$_P_ROOT" '#b'
	eq "b" "$_OIDS"
}

t_ops_select_by_tag_in_document_order() {
	_ops_page '<pane id="a"><label id="b"/><button id="c"/><label id="d"/></pane>'
	_ops_ids "$_P_ROOT" 'label'
	eq "b d" "$_OIDS"
}

t_ops_select_by_class_matches_whole_words_only() {
	_ops_page '<pane id="a" class="big red"/><pane id="b" class="bigger"/>'
	_ops_ids "$_P_ROOT" '.big'
	eq "a" "$_OIDS"
}

t_ops_select_compound_tag_and_class() {
	_ops_page '<pane id="a" class="x"/><label id="b" class="x"/>'
	_ops_ids "$_P_ROOT" 'label.x'
	eq "b" "$_OIDS"
}

t_ops_select_child_combinator_skips_grandchildren() {
	_ops_page '<pane id="a"><label id="b"/><pane id="c"><label id="d"/></pane></pane>'
	_ops_ids "$_P_ROOT" '#a > label'
	eq "b" "$_OIDS"
}

t_ops_select_descendant_combinator_reaches_grandchildren() {
	_ops_page '<pane id="a"><label id="b"/><pane id="c"><label id="d"/></pane></pane>'
	_ops_ids "$_P_ROOT" '#a label'
	eq "b d" "$_OIDS"
}

t_ops_select_no_match_is_empty_and_false() {
	_ops_page '<pane id="a"/>'
	tui_ops.select "$_P_ROOT" '#zzz'
	local rc=$?
	eq "0" "${#_OP_NODES[@]}"
	ok '((rc != 0))'
}

t_ops_select_is_scoped_to_root() {
	_ops_page '<pane id="a"><label id="b"/></pane><pane id="c"><label id="d"/></pane>'
	tui_ops.select "$_P_ROOT" '#c'
	_ops_ids "${_OP_NODES[0]}" 'label'
	eq "d" "$_OIDS"
}

# ── clone ────────────────────────────────────────────────────────────────
t_ops_clone_copies_subtree_and_attrs_detached() {
	_ops_page '<pane id="a" title="T"><label id="b" text="hi"/></pane>'
	local a="${_N_BY_ID[a]}"
	tui_ops.clone "$a" k_
	local c=$_N
	eq "" "${_N_PARENT[$c]}"
	tui_node.attr_get "$c" title
	eq "T" "$_N_ATTR_V"
	tui_node.children "$c"
	tui_node.attr_get "${_N_CHILDREN[0]}" text
	eq "hi" "$_N_ATTR_V"
	ok '[[ "${_N_CHILDREN[0]}" != "${_N_BY_ID[b]}" ]]'
	eq "k_b" "${_N_ID[${_N_CHILDREN[0]}]}"
}

t_ops_clone_prefixes_ids_and_registers_them() {
	_ops_page '<pane id="a"><label id="b"/></pane>'
	tui_ops.clone "${_N_BY_ID[a]}" x_
	eq "x_a" "${_N_ID[$_N]}"
	eq "$_N" "${_N_BY_ID[x_a]}"
	ok '[[ -n "${_N_BY_ID[x_b]:-}" ]]'
	eq "${_N_BY_ID[b]}" "${_N_BY_ID[b]}"
	tui_node.attr_get "$_N" id
	eq "x_a" "$_N_ATTR_V"
}

t_ops_clone_leaves_original_untouched() {
	_ops_page '<pane id="a"><label id="b"/></pane>'
	local a="${_N_BY_ID[a]}" b="${_N_BY_ID[b]}"
	tui_ops.clone "$a" x_
	eq "$b" "${_N_BY_ID[b]}"
	eq "$b" "${_N_KIDS[$a]}"
}

# ── insert ───────────────────────────────────────────────────────────────
_ops_new() { tui_node.create "$1" "$2"; }

t_ops_insert_append() {
	_ops_page '<pane id="a"><label id="b"/></pane>'
	_ops_new label n
	tui_ops.insert append "${_N_BY_ID[a]}" "$_N"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "b n" "$_OIDS"
	eq "${_N_BY_ID[a]}" "${_N_PARENT[$_N]}"
}

t_ops_insert_prepend() {
	_ops_page '<pane id="a"><label id="b"/></pane>'
	_ops_new label n
	tui_ops.insert prepend "${_N_BY_ID[a]}" "$_N"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "n b" "$_OIDS"
}

t_ops_insert_before_and_after() {
	_ops_page '<pane id="a"><label id="b"/><label id="c"/></pane>'
	_ops_new label x
	tui_ops.insert before "${_N_BY_ID[c]}" "$_N"
	_ops_new label y
	tui_ops.insert after "${_N_BY_ID[c]}" "$_N"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "b x c y" "$_OIDS"
}

t_ops_insert_existing_node_detaches_it_from_old_parent() {
	_ops_page '<pane id="a"><label id="b"/></pane><pane id="c"/>'
	tui_ops.insert append "${_N_BY_ID[c]}" "${_N_BY_ID[b]}"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "" "$_OIDS"
	_ops_kids_ids "${_N_BY_ID[c]}"
	eq "b" "$_OIDS"
}

# ── remove / replace / set / wrap / move ─────────────────────────────────
t_ops_remove_detaches_and_forgets_subtree_ids() {
	_ops_page '<pane id="a"><pane id="b"><label id="c"/></pane></pane>'
	local a="${_N_BY_ID[a]}"
	tui_ops.remove "${_N_BY_ID[b]}"
	eq "" "${_N_KIDS[$a]}"
	eq "" "${_N_BY_ID[b]:-}"
	eq "" "${_N_BY_ID[c]:-}"
}

t_ops_replace_puts_new_node_in_old_position() {
	_ops_page '<pane id="a"><label id="b"/><label id="c"/><label id="d"/></pane>'
	_ops_new button n
	tui_ops.replace "${_N_BY_ID[c]}" "$_N"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "b n d" "$_OIDS"
	eq "" "${_N_BY_ID[c]:-}"
}

t_ops_set_updates_attribute() {
	_ops_page '<label id="b" text="old"/>'
	tui_ops.set "${_N_BY_ID[b]}" text new
	tui_node.attr_get "${_N_BY_ID[b]}" text
	eq "new" "$_N_ATTR_V"
}

t_ops_set_id_reindexes_by_id() {
	_ops_page '<label id="b"/>'
	local n="${_N_BY_ID[b]}"
	tui_ops.set "$n" id z
	eq "$n" "${_N_BY_ID[z]}"
	eq "" "${_N_BY_ID[b]:-}"
	eq "z" "${_N_ID[$n]}"
}

t_ops_wrap_inserts_wrapper_in_place() {
	_ops_page '<pane id="a"><label id="b"/><label id="c"/></pane>'
	tui_ops.wrap "${_N_BY_ID[c]}" pane w
	local w=$_N
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "b w" "$_OIDS"
	_ops_kids_ids "$w"
	eq "c" "$_OIDS"
	eq "pane" "${_N_TYPE[$w]}"
}

t_ops_move_relocates_node() {
	_ops_page '<pane id="a"><label id="b"/></pane><pane id="c"><label id="d"/></pane>'
	tui_ops.move "${_N_BY_ID[b]}" before "${_N_BY_ID[d]}"
	_ops_kids_ids "${_N_BY_ID[c]}"
	eq "b d" "$_OIDS"
	_ops_kids_ids "${_N_BY_ID[a]}"
	eq "" "$_OIDS"
}

t_ops_subst_replaces_params_and_follows_id_changes() {
	_ops_page '<pane id="p_{{@i}}" title="n={{@i}}"><label id="l_{{@i}}"/></pane>'
	local p="${_N_BY_ID[p_{{@i\}\}]}"
	_OP_PARAMS=([i]=7)
	tui_ops.subst "$_P_ROOT"
	tui_node.attr_get "$p" title
	eq "n=7" "$_N_ATTR_V"
	eq "$p" "${_N_BY_ID[p_7]}"
	ok '[[ -n "${_N_BY_ID[l_7]:-}" ]]'
}

t_ops_params_skips_internal_and_named_attrs() {
	_ops_page '<use template="t" id="u" a="1" b="2"/>'
	tui_ops.select "$_P_ROOT" use
	_OP_PARAMS=()
	tui_ops.params "${_OP_NODES[0]}" template id
	eq "2" "${#_OP_PARAMS[@]}"
	eq "2" "${_OP_PARAMS[b]}"
	eq "1" "${_OP_PARAMS[a]}"
}

t_ops_subst_keeps_an_ampersand_in_the_value_literal() {
	tui_node.reset
	tui_node.create document
	local d=$_N
	tui_node.create label "" "$d"
	tui_node.attr_set "$_N" text "a {{@v}} b"
	_OP_PARAMS=([v]='X&Y')
	tui_ops.subst "$d"
	tui_node.attr_get "${_N_KIDS[$d]}" text
	eq "a X&Y b" "$_N_ATTR_V"
}
