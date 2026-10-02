# demo_compose.t.sh - the Compose demo page (share/demo/compose.xml): a project board whose cards, view switch and
# Workspace conditionals come from the addon that share/demo/compose_callbacks.sh writes, plus the five example addons.

source "$REPO/share/demo/compose_callbacks.sh"

_cpt_state() { # VIEW : the default state with these tasks (4 seeds) showing VIEW
	_CP_VIEW="${1:-board}" _CP_ENV=dev _CP_ROLE=guest _CP_BETA=false
	_cp_seed
}

_cpt_tree() { # [EXAMPLE...] : parse the page, apply the state addon (_CP_* as set) and the examples, expand
	local n
	rm -rf "$_T_ROOT/cp"
	mkdir -p "$_T_ROOT/cp"
	_cp_render
	printf '%s\n' "$_CP_XML" >"$_T_ROOT/cp/compose_state.xml"
	for n; do cp "$REPO/share/demo/addon_examples/$n.xml" "$_T_ROOT/cp/"; done
	_TUI_ADDON_DIRS=("$_T_ROOT/cp")
	if [[ -z "${_CPT_RAW:-}" ]]; then # the parse is the costly part and the same for every case: keep the raw tree
		tui.parse.file "$REPO/share/demo/compose.xml"
		_CPT_ROOT="$_P_ROOT" _CPT_RAW="$(tui_node.dump)"
	else
		_P_ROOT="$_CPT_ROOT" _P_ERRORS=() _P_SEEN=() # what tui.page.refresh resets before it re-applies addons
		tui_node.load "$_CPT_RAW"
	fi
	tui_addon.apply "$_P_ROOT" "$REPO/share/demo/compose.xml"
	tui_compose.expand "$_P_ROOT"
}

_cpt_attr() { tui_node.attr_get "${_N_BY_ID[$1]}" "$2"; }
_cpt_has() { [[ -n "${_N_BY_ID[$1]:-}" ]]; }

t_compose_clean_escapes_limits_and_defuses_separators() {
	_cp_clean 'A&B <"x">'
	eq 'A&amp;B &lt;&quot;x&quot;&gt;' "$_CP_CLEAN"
	_cp_clean '123456789012345678901234567890'
	eq '12345678901234567890' "$_CP_CLEAN"
	_cp_clean $'a|b{{@x}}\nc'
	eq 'a/b((@x)) c' "$_CP_CLEAN"
}

t_compose_next_cycles_and_wraps() {
	_cp_next dev dev staging prod
	eq staging "$_CP_NEXT"
	_cp_next prod dev staging prod
	eq dev "$_CP_NEXT"
	_cp_next unknown guest member admin
	eq guest "$_CP_NEXT"
}

t_compose_add_appends_and_stops_at_the_cap() {
	_cpt_state
	_cp_add " New " "me" high true
	eq " New |me|high|false|true" "${_CP_TASKS[4]}"
	_cp_add "" "" normal false
	eq "Untitled||normal|false|false" "${_CP_TASKS[5]}"
	while _cp_add x "" low false; do :; done
	eq "$_CP_MAX" "${#_CP_TASKS[@]}"
}

t_compose_complete_skips_blocked_and_done_tasks() {
	_cpt_state
	_cp_complete_next
	eq "Write release notes|dino|high|true|false" "${_CP_TASKS[0]}"
	_cp_complete_next # "Fix flaky test" is blocked: Ship v0.1 is next
	eq "Ship v0.1|dino|high|true|false" "${_CP_TASKS[3]}"
	eq "Fix flaky test||normal|false|true" "${_CP_TASKS[1]}"
	ok '! _cp_complete_next' # only a blocked task is left
}

t_compose_block_toggles_the_first_open_task() {
	_cpt_state
	_cp_toggle_block_next
	eq "Write release notes|dino|high|false|true" "${_CP_TASKS[0]}"
	_cp_toggle_block_next
	eq "Write release notes|dino|high|false|false" "${_CP_TASKS[0]}"
}

t_compose_remove_last_and_reset() {
	_cpt_state
	_cp_remove_last
	eq 3 "${#_CP_TASKS[@]}"
	_CP_TASKS=()
	ok '! _cp_remove_last'
	_cp_seed
	eq 4 "${#_CP_TASKS[@]}"
}

t_compose_render_sets_views_workspace_and_sorts_cards_into_lanes() {
	_cpt_state cond
	_CP_ENV=prod
	_cp_render
	match "$_CP_XML" '<set ref="#view_board" attr="test" value="cond==board"/>'
	match "$_CP_XML" '<set ref="#view_cond" attr="test" value="cond==cond"/>'
	match "$_CP_XML" '<set ref="#acct" attr="env" value="prod"/>'
	match "$_CP_XML" '<remove ref="#lane_todo_empty"/>'
	match "$_CP_XML" '<append ref="#lane_todo"><use template="task" id="t0" title="Write release notes" owner="dino" prio="high" done="false" blocked="false"/>'
	match "$_CP_XML" '<append ref="#lane_done"><use template="task" id="t2" title="Update docs" owner="sam" prio="low" done="true" blocked="false"/></append>'
	eq "3 1" "$_CP_OPEN $_CP_DONE"
}

t_compose_render_of_an_empty_board_keeps_the_placeholders() {
	_cpt_state
	_CP_TASKS=()
	_cp_render
	ok '[[ "$_CP_XML" != *lane_* ]]'
	eq "0 0" "$_CP_OPEN $_CP_DONE"
}

# A visit runs after the first frame: a value stored with tui.set stays invisible until the widget is drawn again.
ti_compose_visit_redraws_the_checkboxes_of_active_addons() {
	local saved drawn=""
	saved="$(declare -f _tui._draw_widget)"
	_tui._draw_widget() { drawn+="$1 "; }
	TUI_APP_CONF="$_T_ROOT/cpv"
	rm -rf "$TUI_APP_CONF"
	mkdir -p "$TUI_APP_CONF/addons"
	echo '<addon id="banner" target="compose.xml"/>' >"$TUI_APP_CONF/addons/banner.xml"
	: >"$TUI_APP_CONF/addons/toolbar.xml" # switched off
	_TUI_W_TYPE[chk_banner]=checkbox _TUI_W_TYPE[chk_toolbar]=checkbox _TUI_W_TYPE[lbl_state]=label
	_CP_VIEW=addons
	_cp_sync
	eval "$saved"
	eq "1" "${_TUI_W_VALUE[chk_banner]}"
	match "$drawn" "chk_banner"
	ok '[[ "$drawn" != *chk_toolbar* ]]'
}

ti_compose_adding_a_task_redraws_the_cleared_inputs() {
	local saved_draw saved_refresh drawn=""
	saved_draw="$(declare -f _tui._draw_widget)" saved_refresh="$(declare -f tui.page.refresh)"
	_tui._draw_widget() { drawn+="$1 "; }
	tui.page.refresh() { :; }
	TUI_APP_CONF="$_T_ROOT/cpa"
	_cpt_state
	_TUI_W_TYPE[inp_title]=input _TUI_W_TYPE[inp_owner]=input _TUI_W_TYPE[lbl_status]=label
	_TUI_W_VALUE[inp_title]="Typed" _TUI_W_VALUE[sel_prio]=high _TUI_W_VALUE[chk_blocked]=0
	on_cp_add
	eval "$saved_draw"
	eval "$saved_refresh"
	eq "" "${_TUI_W_VALUE[inp_title]}"
	match "$drawn" "inp_title inp_owner"
	eq "Typed||high|false|false" "${_CP_TASKS[4]}"
}

ti_compose_board_cards_show_status_owner_priority_and_lane() {
	_cpt_state
	_cpt_tree
	_cpt_attr t1_st_blocked text # Fix flaky test: blocked, unassigned, normal priority
	match "$_N_ATTR_V" "blocked"
	_cpt_has t1_who_none
	ok '! _cpt_has t1_st_open && ! _cpt_has t1_pri_high && ! _cpt_has t1_pri_low'
	eq "${_N_BY_ID[lane_todo]}" "${_N_PARENT[${_N_BY_ID[t1_card]}]}"
	_cpt_has t0_st_open # Write release notes: open, owner, high
	_cpt_has t0_pri_high
	_cpt_attr t0_who text
	eq "owner: dino" "$_N_ATTR_V"
	_cpt_has t2_st_done # Update docs: done, low
	_cpt_has t2_pri_low
	eq "${_N_BY_ID[lane_done]}" "${_N_PARENT[${_N_BY_ID[t2_card]}]}"
	ok '! _cpt_has lane_todo_empty && ! _cpt_has lane_done_empty && ! _cpt_has cond && ! _cpt_has view_addons'
}

ti_compose_workspace_conditionals_follow_env_role_and_beta() {
	_cpt_state cond
	_cpt_tree
	_cpt_has acct_env_other                             # dev: not production
	ok '! _cpt_has lane_todo && ! _cpt_has view_addons' # the other views are not built
	ok '! _cpt_has acct_row_edit && ! _cpt_has acct_adm_prod && ! _cpt_has acct_adm_tools'
	_cpt_has acct_beta_off
	_cpt_has acct_role_guest # the else chain ends on guest
	_CP_ENV=prod _CP_ROLE=admin _CP_BETA=true
	_cpt_tree
	_cpt_has acct_env_prod
	_cpt_has acct_row_edit # role!=guest
	_cpt_has acct_beta_on
	_cpt_has acct_adm_prod # nested: admin, then prod
	_CP_ENV=staging _CP_ROLE=member
	_cpt_tree
	_cpt_has acct_role_member
	ok '! _cpt_has acct_adm_prod && ! _cpt_has acct_adm_tools'
	_CP_ROLE=admin
	_cpt_tree
	_cpt_has acct_adm_tools
}

ti_compose_example_addons_change_the_addons_view() {
	_cpt_state addons
	_cpt_tree banner toolbar tidy
	local body="${_N_BY_ID[body]}" k ids=""
	for k in ${_N_KIDS[$body]}; do ids+="${_N_ID[$k]} "; done
	eq "banner_msg lbl_hello tidy_swapped toolbar_refresh toolbar_export " "$ids" # prepend, replace in place, append
	ok '! _cpt_has lbl_legacy'
	_cpt_attr tidy_frame border
	eq "double" "$_N_ATTR_V"
	eq "${_N_BY_ID[tidy_frame]}" "${_N_PARENT[${_N_BY_ID[note]}]}" # note is wrapped
	_cpt_tree retitle shout
	_cpt_attr body title
	match "$_N_ATTR_V" "SHOUT" # priority 20 wins over retitle's 10
}

ti_compose_example_files_pass_the_validator() {
	local f
	for f in "$REPO"/share/demo/addon_examples/*.xml; do
		tui.validate.files "$f"
		eq "0" "$TUI_V_ERRORS"
	done
}
