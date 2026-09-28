# node.t.sh - lib/markup/tui_node.sh struct-of-arrays node table (stage 0.5).

t_node_create_assigns_increasing_ids() {
	tui_node.reset
	tui_node.create pane
	local a=$_N
	tui_node.create pane
	local b=$_N
	ok '(( b > a ))'
}

t_node_create_records_type() {
	tui_node.reset
	tui_node.create button
	eq "button" "${_N_TYPE[$_N]}"
}

t_node_create_with_parent_appends_to_parent_kids() {
	tui_node.reset
	tui_node.create pane
	local parent=$_N
	tui_node.create label "" "$parent"
	local child=$_N
	eq "$child" "${_N_KIDS[$parent]}"
	eq "$parent" "${_N_PARENT[$child]}"
}

t_node_create_with_id_registers_by_id_map() {
	tui_node.reset
	tui_node.create button btn_home
	eq "$_N" "${_N_BY_ID[btn_home]}"
}

t_node_attr_set_then_get_roundtrips() {
	tui_node.reset
	tui_node.create label
	local n=$_N
	tui_node.attr_set "$n" text "Hello"
	tui_node.attr_get "$n" text
	eq "Hello" "$_N_ATTR_V"
}

t_node_attr_get_missing_returns_false() {
	tui_node.reset
	tui_node.create label
	tui_node.attr_get "$_N" missing_attr
	ok '(($? != 0))'
	eq "" "$_N_ATTR_V"
}

t_node_children_lists_kids_in_order() {
	tui_node.reset
	tui_node.create pane
	local parent=$_N
	tui_node.create label "" "$parent"
	local c1=$_N
	tui_node.create label "" "$parent"
	local c2=$_N
	tui_node.children "$parent"
	eq "$c1 $c2" "${_N_CHILDREN[*]}"
}

t_node_walk_visits_pre_order() {
	tui_node.reset
	tui_node.create pane
	local root=$_N
	tui_node.create pane "" "$root"
	local mid=$_N
	tui_node.create label "" "$mid"
	local leaf=$_N

	_T_WALK_SEEN=()
	_t_walk_collect() { _T_WALK_SEEN+=("$1"); }
	tui_node.walk "$root" _t_walk_collect
	eq "$root $mid $leaf" "${_T_WALK_SEEN[*]}"
}

t_node_dump_reset_load_roundtrips() {
	tui_node.reset
	tui_node.create pane root_page
	local root=$_N
	tui_node.create button btn_a "$root"
	local btn=$_N
	tui_node.attr_set "$btn" text "Click me"

	local dumped
	dumped="$(tui_node.dump)"

	tui_node.reset
	eq "" "${_N_TYPE[$btn]:-}"

	tui_node.load "$dumped"
	eq "button" "${_N_TYPE[$btn]}"
	eq "$root" "${_N_PARENT[$btn]}"
	tui_node.attr_get "$btn" text
	eq "Click me" "$_N_ATTR_V"
	eq "$root" "${_N_BY_ID[root_page]}"
}

t_node_reset_clears_every_table() {
	tui_node.reset
	tui_node.create pane some_id
	tui_node.attr_set "$_N" x 1
	tui_node.reset
	eq "0" "${#_N_TYPE[@]}"
	eq "0" "${#_N_PARENT[@]}"
	eq "0" "${#_N_KIDS[@]}"
	eq "0" "${#_N_ATTR[@]}"
	eq "0" "${#_N_BY_ID[@]}"
}

t_node_walk_over_1000_nodes_is_fast() {
	tui_node.reset
	tui_node.create pane
	local root=$_N
	local i prev=$root
	for ((i = 0; i < 1000; i++)); do
		tui_node.create label "" "$prev"
	done
	_T_WALK_COUNT=0
	_t_walk_count() { ((_T_WALK_COUNT++)); }
	local t0=$SECONDS
	tui_node.walk "$root" _t_walk_count
	eq "1001" "$_T_WALK_COUNT"
	ok '(( SECONDS - t0 <= 2 ))'
}
