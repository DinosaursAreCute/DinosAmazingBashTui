# collapse.t.sh - collapsible panes: rects, restore, rail, accordion, focus, collapse button, callbacks.

_cl_setup() {
	_TUI_ROWS=24 _TUI_FOCUS_ID="" _TUI_PANE_FOCUS="" _TUI_HZ_EXTRA=() _TUI_CV_ZONES=0
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=80
}
# _cl_pane ID [TO] - makes ID collapsible (collapse_to TO)
_cl_pane() { _tui_collapse.build "$1" true "" "" "" "${2:-}" ""; }
_cl_rect() { printf '%s' "${_TUI_P_ROW[$1]},${_TUI_P_COL[$1]},${_TUI_P_H[$1]},${_TUI_P_W[$1]}"; }
_cl_zones() { # "kind:id:arg@row,col,h,w" per registered zone
	local i out=()
	for ((i = 0; i < ${#_TUI_HZ_EXTRA[@]}; i += 7)); do
		out+=("${_TUI_HZ_EXTRA[i]}:${_TUI_HZ_EXTRA[i + 1]}:${_TUI_HZ_EXTRA[i + 2]}@${_TUI_HZ_EXTRA[i + 3]},${_TUI_HZ_EXTRA[i + 4]},${_TUI_HZ_EXTRA[i + 5]},${_TUI_HZ_EXTRA[i + 6]}")
	done
	printf '%s' "${out[*]}"
}

# ── rects ────────────────────────────────────────────────────────────────

t_collapse_title_in_a_v_split_is_one_row_and_gives_the_rest_to_the_sibling() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	tui.collapse a on
	eq "1,1,1,80 2,1,19,80" "$(_cl_rect a) $(_cl_rect b)"
}

t_collapse_title_in_an_h_split_is_a_column_as_wide_as_the_bordered_title() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a
	tui.pane_title a Logs
	_tui._layout root
	tui.collapse a on
	eq "1,1,20,11 1,12,20,69" "$(_cl_rect a) $(_cl_rect b)"
}

t_collapse_to_0_has_size_0() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a 0
	_tui._layout root
	tui.collapse a on
	eq "0 80" "${_TUI_P_W[a]} ${_TUI_P_W[b]}"
}

t_collapse_rail_in_an_h_split_is_as_wide_as_the_longest_collapsed_text_plus_4() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a rail
	tui.button svc a 0 Services
	_TUI_W_COLLAPSED_TEXT[svc]="Svc"
	_tui._layout root
	tui.collapse a on
	eq "7 73" "${_TUI_P_W[a]} ${_TUI_P_W[b]}"
}

t_collapse_rail_in_a_v_split_is_three_rows() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a rail
	_tui._layout root
	tui.collapse a on
	eq "3 17" "${_TUI_P_H[a]} ${_TUI_P_H[b]}"
}

t_collapse_rail_shows_collapsed_text_and_hides_widgets_without_one() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a rail
	tui.button svc a 0 Services
	tui.button other a 1 Other
	_TUI_W_COLLAPSED_TEXT[svc]="Svc"
	_tui._layout root
	tui.collapse a on
	eq "Svc" "${_TUI_W_LABEL[svc]}"
	eq "" "${_TUI_W_HIDDEN[svc]:-}"
	eq "1" "${_TUI_W_HIDDEN[other]:-}"
	tui.collapse a off
	eq "Services" "${_TUI_W_LABEL[svc]}"
	eq "" "${_TUI_W_HIDDEN[other]:-}"
}

t_collapse_expand_restores_the_previous_size_spec() {
	_cl_setup
	tui.hsplit root a:30% b:70%
	_cl_pane a
	_tui._layout root
	tui.collapse a on
	tui.collapse a off
	eq "30% 70%" "${_TUI_P_WEIGHTS[root]}"
	eq "24 56" "${_TUI_P_W[a]} ${_TUI_P_W[b]}"
	tui.collapsed a && return 1
	return 0
}

t_collapse_expand_restores_weights_after_a_resize() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a
	_tui._layout root
	tui.resize a 10 0
	tui.collapse a on
	tui.collapse a off
	eq "50 30" "${_TUI_P_W[a]} ${_TUI_P_W[b]}"
}

t_collapsed_query_and_toggle() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	tui.collapsed a && return 1
	tui.collapse a
	tui.collapsed a || return 1
	eq "1" "${_TUI_P_COLLAPSED[a]}"
	tui.collapse a toggle
	tui.collapsed a && return 1
	return 0
}

t_collapse_rejects_a_pane_that_is_not_collapsible_and_a_bad_mode() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	tui.collapse b on && return 1
	tui.collapse a sideways 2>/dev/null && return 1
	return 0
}

# ── build attributes ─────────────────────────────────────────────────────

t_collapse_build_stores_the_attributes() {
	_tui_collapse.build a true "" true true rail cb
	eq "1 collapsed true rail cb" "${_TUI_P_COLLAPSIBLE[a]} ${_TUI_P_COLLAPSE_DEFAULT[a]} ${_TUI_P_KEEP_COLLAPSED[a]} ${_TUI_P_COLLAPSE_TO[a]} ${_TUI_P_ON_TOGGLE[a]}"
}

t_collapse_build_defaults_to_expanded_and_title() {
	_tui_collapse.build a true "" "" "" "" ""
	eq "expanded" "${_TUI_P_COLLAPSE_DEFAULT[a]}"
	eq "" "${_TUI_P_COLLAPSE_TO[a]:-}"
}

t_collapse_build_ignores_a_pane_without_collapsible() {
	_tui_collapse.build a "" collapsed "" "" "" ""
	eq "" "${_TUI_P_COLLAPSIBLE[a]:-}"
}

t_collapse_init_children_applies_the_first_build_state() {
	_cl_setup
	tui.hsplit root a b
	_tui_collapse.build a true collapsed "" "" "" ""
	_tui_collapse.init_children root ""
	tui.collapsed a
}

# ── accordion ────────────────────────────────────────────────────────────

_cl_accordion() {
	_cl_setup
	tui.vsplit root d1 d2 d3
	_cl_pane d1
	_cl_pane d2
	_cl_pane d3
	_TUI_P_ACCORDION[root]="$1"
	_tui._layout root
	tui.collapse d2 on
	tui.collapse d3 on
}

ti_collapse_accordion_opening_one_collapses_the_others() {
	_cl_accordion exclusive
	tui.collapse d2 off
	eq "1 0 1" "$(tui.collapsed d1 && echo 1 || echo 0) $(tui.collapsed d2 && echo 1 || echo 0) $(tui.collapsed d3 && echo 1 || echo 0)"
	eq "1 18 1" "${_TUI_P_H[d1]} ${_TUI_P_H[d2]} ${_TUI_P_H[d3]}"
}

t_collapse_accordion_multiple_keeps_the_others_open() {
	_cl_accordion multiple
	tui.collapse d2 off
	tui.collapsed d1 && return 1
	tui.collapsed d2 && return 1
	tui.collapsed d3
}

# ── focus and hit-testing ────────────────────────────────────────────────

_cl_focus_page() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a
	tui.button b1 a 0 One
	tui.button b2 a 1 Two
	tui.button b3 b 0 Three
	_tui._layout root
}

t_collapse_focus_inside_a_collapsing_pane_moves_to_the_next_focusable() {
	_cl_focus_page
	_TUI_FOCUS_ID=b2
	tui.collapse a on
	eq "b3" "$_TUI_FOCUS_ID"
	eq "b" "$_TUI_PANE_FOCUS"
}

t_collapse_hidden_widgets_are_not_focusable_or_tabbable() {
	_cl_focus_page
	tui.collapse a on
	_tui_focus.ensure
	eq "b3" "${_TUI_FOCUS_TAB[*]}"
	eq "b3" "${_TUI_FOCUSABLE[*]}"
	tui.collapse a off
	_tui_focus.ensure
	eq "b1 b2 b3" "${_TUI_FOCUS_TAB[*]}"
}

t_collapse_hidden_widgets_are_not_hit_testable() {
	_cl_focus_page
	_tui_hit.rebuild
	[[ -n "${_TUI_HZ_WR[b1]:-}" ]] || return 1
	tui.collapse a on
	_tui_hit.rebuild
	eq "" "${_TUI_HZ_WR[b1]:-}"
}

# ── collapse button: zone, position, arrow, hover ────────────────────────

t_collapse_button_zone_is_2x1_on_the_moving_edge_corner() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root # a = rows 1-10: its bottom edge (row 10) is the one that moves
	_tui_hit.rebuild
	eq "chevron:a:cv-toggle@10,1,1,2" "$(_cl_zones)"
	_tui_hit.at 2 10
	eq "chevron a" "$_HIT_KIND $_HIT_ID"
	_tui_hit.at 3 10
	eq "" "$_HIT_KIND"
}

t_collapse_button_zone_follows_a_collapsed_title_bar() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	tui.collapse a on
	_tui_hit.rebuild
	eq "chevron:a:cv-toggle@1,1,1,2" "$(_cl_zones)"
}

t_collapse_button_zone_does_not_depend_on_the_title() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	tui.pane_title_align a right
	tui.pane_title_pos a bottom
	_tui._layout root
	_tui_hit.rebuild
	eq "chevron:a:cv-toggle@10,1,1,2" "$(_cl_zones)"
}

t_collapse_no_button_zone_for_collapse_to_0() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a 0
	_tui._layout root
	tui.collapse a on
	_tui_hit.rebuild
	eq "" "$(_cl_zones)"
}

# _cl_btn ID -> "ROW,COL,GLYPH" of its button
_cl_btn() { _tui_collapse.cell "$1" && printf '%s' "$_CL_R,$_CL_C,$_CL_G"; }

ti_collapse_button_position_and_arrow_table() {
	local out="" ax st
	for ax in h v; do
		_cl_setup
		_tui_collapse.clear
		_TUI_P_W[root]=90
		[[ $ax == h ]] && tui.hsplit root a b c || tui.vsplit root a b c
		_cl_pane a; _cl_pane b; _cl_pane c
		_tui._layout root
		for st in expanded collapsed; do
			[[ $st == collapsed ]] && { tui.collapse a on; tui.collapse b on; tui.collapse c on; }
			out+="$ax-$st: $(_cl_btn a) $(_cl_btn b) $(_cl_btn c); "
		done
	done
	# h (cols 1-30 | 31-60 | 61-90, rows 1-20): a/b trailing (right) edge, c leading (left) edge, top row
	# v (rows 1-6 | 7-12 | 13-20, cols 1-90): a/b bottom edge row, c top edge row, left corner
	local h_exp="1,29,◀ 1,59,◀ 1,61,▶"
	eq "h-expanded: $h_exp; " "${out%%h-collapsed*}"
	local rest="${out#*h-collapsed: }"
	match "${rest%%v-expanded*}" "^1,[0-9]+,▶ 1,[0-9]+,▶ 1,[0-9]+,◀; $"
	rest="${out#*v-expanded: }"
	match "${rest%%v-collapsed*}" "^6,1,▲ 12,1,▲ 13,1,▼; $"
	rest="${out#*v-collapsed: }"
	match "$rest" "^[0-9]+,1,▼ [0-9]+,1,▼ [0-9]+,1,▲; $"
}

t_collapse_button_rail_keeps_a_button_pointing_the_expand_direction() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a rail
	_tui._layout root
	tui.collapse a on # rail: 7 columns wide
	eq "1,6,▶" "$(_cl_btn a)"
}

t_collapse_button_to_0_has_none_when_collapsed() {
	_cl_setup
	tui.hsplit root a b
	_cl_pane a 0
	_tui._layout root
	tui.collapse a on
	_cl_btn a && return 1
	return 0
}

t_collapse_button_click_toggles() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	_tui_hit.at 2 10
	_tui_collapse.mouse mouse:left || return 1
	tui.collapsed a || return 1
	_tui_hit.at 1 1 # the same button, now on the title bar
	_tui_collapse.mouse mouse:left || return 1
	tui.collapsed a && return 1
	return 0
}

t_collapse_button_hover_tracks_and_repaints_just_the_button() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	[[ -n "${_RZ_FLUSH_DEF:-}" ]] || _RZ_FLUSH_DEF="$(declare -f _tui_paint.flush)" # not snapshotted: restored below
	_TUI_HZ_HOVER="" _TUI_RUNNING=1 _CL_PAINT=""
	_tui_paint.flush() { _CL_PAINT+="$1"; }
	_tui_hit.at 2 10
	_tui_hit.hover
	eq "a|cv-toggle" "$_TUI_HZ_HOVER"
	match "$_CL_PAINT" $'10;1H.*▲ '
	_CL_PAINT=""
	_tui_hit.at 40 3
	_tui_hit.hover
	eq "" "$_TUI_HZ_HOVER"
	match "$_CL_PAINT" $'10;1H.*▲ '
	_TUI_RUNNING=0
	eval "$_RZ_FLUSH_DEF"
}

t_collapse_button_hover_class_is_applied() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	_TUI_CLASS_FG[collapse_button_hover]="#010203"
	_TUI_FRAME=""
	_tui_collapse.button_buf a
	[[ "$_TUI_FRAME" != *"38;2;1;2;3"* ]] || return 1
	_TUI_HZ_HOVER="a|cv-toggle" _TUI_FRAME=""
	_tui_collapse.button_buf a
	match "$_TUI_FRAME" "38;2;1;2;3"
	unset '_TUI_CLASS_FG[collapse_button_hover]'
}

t_collapse_action_toggles_the_pane_around_the_focus() {
	_cl_focus_page
	_TUI_FOCUS_ID=b1
	tui.action.collapse_toggle
	tui.collapsed a || return 1
	eq "a" "$_TUI_PANE_FOCUS" # the keyboard can open it again
	tui.action.collapse_toggle
	tui.collapsed a && return 1
	return 0
}

# ── on_toggle ────────────────────────────────────────────────────────────

_cl_cb() { _CL_LOG+="$1:$2 "; }

t_collapse_on_toggle_gets_the_pane_and_the_new_state() {
	_cl_setup
	_CL_LOG=""
	tui.vsplit root a b
	_tui_collapse.build a true "" "" "" "" _cl_cb
	_tui._layout root
	tui.collapse a on
	tui.collapse a off
	eq "a:collapsed a:expanded " "$_CL_LOG"
}

t_collapse_on_toggle_fires_for_accordion_siblings_too() {
	_cl_setup
	_CL_LOG=""
	tui.vsplit root d1 d2
	_tui_collapse.build d1 true "" "" "" "" _cl_cb
	_tui_collapse.build d2 true "" "" "" "" _cl_cb
	_TUI_P_ACCORDION[root]=exclusive
	_tui._layout root
	tui.collapse d2 on
	_CL_LOG=""
	tui.collapse d2 off
	eq "d2:expanded d1:collapsed " "$_CL_LOG"
}

# ── drawing ──────────────────────────────────────────────────────────────

t_collapse_title_bar_draws_one_row_and_the_button_on_top() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	tui.pane_title a Logs
	_tui._layout root
	tui.collapse a on
	_TUI_FRAME=""
	_tui._draw_pane_buf a
	match "$_TUI_FRAME" "   Logs"
	_TUI_FRAME=""
	_tui_hit.overlay
	match "$_TUI_FRAME" $'1;1H.*▼ '
}

t_collapse_title_has_no_chevron_glyph() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	tui.pane_title a Logs
	_tui._layout root
	_TUI_FRAME=""
	_tui._draw_pane_buf a
	[[ "$_TUI_FRAME" != *"▾"* && "$_TUI_FRAME" != *"▸"* ]] || return 1
	match "$_TUI_FRAME" " Logs "
}

# ── markup + validator (integration tier) ────────────────────────────────

_cl_validate() { # TEXT (tui body) -> $_RV: severity+message lines
	local f="$HOME/cv.xml" i
	printf '<tui>\n%s\n</tui>\n' "$1" >"$f"
	tui.validate.files "$f"
	_RV=""
	for i in "${!_TV_F_MSG[@]}"; do _RV+="${_TV_F_SEV[i]} ${_TV_F_MSG[i]}"$'\n'; done
}

ti_collapse_validator_accepts_the_attributes_and_tags() {
	_cl_validate '<accordion id="acc" multiple="true">
<details id="d1" title="One"/>
<details id="d2" title="Two" collapsed="true"/>
</accordion>
<pane id="p" split="h">
<pane id="q" collapsible="true" default="collapsed" collapse_to="title" keep_collapsed="true" on_toggle="cb"/>
</pane>'
	eq "" "$_RV"
}

ti_collapse_validator_rejects_a_bad_collapse_to() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_to="gone"/>
</pane>'
	match "$_RV" "collapse_to"
}

ti_collapse_validator_errors_on_conflicting_default_and_collapsed() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" default="expanded" collapsed="true"/>
</pane>'
	match "$_RV" "^error .*contradict"
}

ti_collapse_validator_accepts_agreeing_default_and_collapsed() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" default="collapsed" collapsed="true"/>
</pane>'
	eq "" "$_RV"
}

ti_collapse_validator_warns_on_a_rail_without_collapsed_text() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_to="rail">
<button id="b" pane="q" row="0" text="Go"/>
</pane>
<pane id="r"/>
</pane>'
	match "$_RV" "^warn .*collapsed_text"
}

ti_collapse_validator_accepts_a_rail_with_collapsed_text() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_to="rail">
<button id="b" pane="q" row="0" text="Go" collapsed_text="G"/>
</pane>
<pane id="r"/>
</pane>'
	eq "" "$_RV"
}

ti_collapse_markup_details_in_an_accordion() {
	_cl_setup
	printf '<tui>\n<accordion id="acc">\n<details id="d1" title="One" height="1"/>\n<details id="d2" title="Two" collapsed="true"/>\n<details id="d3" title="Three"/>\n</accordion>\n</tui>\n' >"$HOME/ac.xml"
	tui.load "$HOME/ac.xml" 2>/dev/null
	eq "exclusive" "${_TUI_P_ACCORDION[acc]}"
	tui.collapsed d1 && return 1
	tui.collapsed d2 || return 1
	tui.collapsed d3 # the first open one stays, the later one is closed
}

ti_collapse_markup_collapsed_text_and_pane_attributes() {
	_cl_setup
	printf '<tui>\n<pane id="r" split="h">\n<pane id="a" collapsible="true" collapse_to="rail" default="collapsed" keep_collapsed="true" on_toggle="cb">\n<button id="b" pane="a" row="0" text="Services" collapsed_text="Svc"/>\n</pane>\n<pane id="m"/>\n</pane>\n</tui>\n' >"$HOME/cr.xml"
	tui.load "$HOME/cr.xml" 2>/dev/null
	eq "rail true cb" "${_TUI_P_COLLAPSE_TO[a]} ${_TUI_P_KEEP_COLLAPSED[a]} ${_TUI_P_ON_TOGGLE[a]}"
	tui.collapsed a || return 1
	eq "Svc" "${_TUI_W_LABEL[b]}"
}

# ── collapse_key / collapse_class / :collapsed / footer hints ─────────────

t_collapse_button_collapsed_class_is_applied() {
	_cl_setup
	tui.vsplit root a b
	_cl_pane a
	_tui._layout root
	_TUI_CLASS_BG[collapse_button_collapsed]="#040506"
	_TUI_FRAME=""
	_tui_collapse.button_buf a
	[[ "$_TUI_FRAME" != *"48;2;4;5;6"* ]] || return 1
	tui.collapse a on
	_TUI_FRAME=""
	_tui_collapse.button_buf a
	match "$_TUI_FRAME" "48;2;4;5;6"
}

t_collapse_class_picks_the_buttons_theme_class() {
	_cl_setup
	tui.vsplit root a b
	_tui_collapse.build a true "" "" "" "" "" "" my_btn
	_tui._layout root
	_TUI_CLASS_FG[my_btn]="#0a0b0c"
	_TUI_CLASS_FG[collapse_button]="#0d0e0f"
	_TUI_FRAME=""
	_tui_collapse.button_buf a
	match "$_TUI_FRAME" "38;2;10;11;12"
	[[ "$_TUI_FRAME" != *"38;2;13;14;15"* ]] || return 1
}

t_collapse_footer_predicates_follow_the_focus_and_the_state() {
	_cl_focus_page
	_TUI_FOCUS_ID=b3
	_tui_collapse.can_collapse && return 1
	_tui_collapse.can_expand && return 1
	_TUI_FOCUS_ID=b1
	_tui_collapse.can_collapse || return 1
	_tui_collapse.can_expand && return 1
	tui.collapse a on
	_TUI_PANE_FOCUS=a
	_tui_collapse.can_expand || return 1
	_tui_collapse.can_collapse && return 1
	return 0
}

t_collapse_key_binds_a_direct_toggle_from_anywhere() {
	_cl_focus_page
	_tui_collapse.build a true "" "" "" "" "" ctrl+1 ""
	_TUI_FOCUS_ID=b3
	TUI_EVENT_PANE=b
	_tui_input.dispatch ctrl+1
	tui.collapsed a || return 1
	_tui_input.dispatch ctrl+1
	tui.collapsed a && return 1
	eq "tui.collapse a toggle" "${_TUI_BIND[|ctrl+1]}"
	ok '[[ -n "${_TUI_BIND_PAGE[|ctrl+1]:-}" ]]' # dropped with the page
}

t_collapse_key_survives_the_cache_record() {
	_TUI_CACHE_REC_GOTOS=()
	_cl_setup
	tui.vsplit root a b
	_tui_collapse.build a true "" "" "" "" "" ctrl+1 ""
	match "${_TUI_CACHE_REC_GOTOS[*]}" "tui.bind ctrl\+1 .*--page"
}

ti_collapse_key_builds_from_markup_and_leaves_with_the_page() {
	tui.reset_ui
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=24 _TUI_P_W[root]=80
	printf '<tui>\n<pane id="root" split="h">\n<pane id="q" collapsible="true" collapse_key="ctrl+2" collapse_class="my_btn" title="Q"/>\n<pane id="z"/>\n</pane>\n</tui>\n' >"$HOME/ck.xml"
	tui.load "$HOME/ck.xml" >/dev/null 2>&1
	eq "tui.collapse q toggle" "${_TUI_BIND[|ctrl+2]:-}"
	eq my_btn "${_TUI_P_COLLAPSE_CLASS[q]:-}"
	tui.reset_ui
	eq "" "${_TUI_BIND[|ctrl+2]:-}"
}

ti_collapse_validator_rejects_a_bad_collapse_key() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_key="ctrl+nonsense"/>
</pane>'
	match "$_RV" "^error .*collapse_key"
}

ti_collapse_validator_accepts_good_collapse_keys() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_key="ctrl+1"/>
<pane id="r" collapsible="true" collapse_key="alt+f5"/>
</pane>'
	eq "" "$_RV"
}

ti_collapse_validator_errors_on_a_duplicate_collapse_key() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_key="ctrl+1"/>
<pane id="r" collapsible="true" collapse_key="CTRL-1"/>
</pane>'
	match "$_RV" "^error .*already used"
}

ti_collapse_validator_warns_on_an_unknown_collapse_class() {
	_cl_validate '<pane id="p" split="h">
<pane id="q" collapsible="true" collapse_class="no_such_class_xyz"/>
<pane id="r" collapsible="true" collapse_class="collapse_button"/>
</pane>'
	match "$_RV" "^warn .*no_such_class_xyz"
	[[ "$_RV" != *"'r'"* ]] || _t_fail "a defined class must not warn: $_RV"
}

# every bundled theme, the demo's and the default one style the resize handle and the collapse button
ti_every_theme_defines_the_resize_handle_and_collapse_button_classes() {
	local f sel miss=""
	for f in "$REPO"/share/defaults/themes/*.css "$REPO/share/demo/theme.css" "$REPO/share/defaults/theme.css"; do
		for sel in collapse_button collapse_button:hover collapse_button:collapsed resize_handle resize_handle:hover; do
			grep -qE "^\.${sel}[[:space:]]*\{" "$f" || miss+=" ${f##*/}:$sel"
		done
	done
	eq "" "$miss"
}

# ── the button through the real pointer path on the workspace page ───────

_CL_TOGGLES=""
_cl_on_toggle() { _CL_TOGGLES+="$1:$2;"; }

# _cl_ws_click ROW COL - a left press and release at the cell through _tui._handle_mouse, then the frame the main loop
# presents; $_T_ROOT/cl.out holds what was drawn from the press's effect on (the press's own pre-click hover paint excluded)
_cl_ws_click() {
	_TUI_RUNNING=1
	_tui._handle_mouse "[<0;$2;${1}M" >/dev/null
	{
		_tui.frame_present
		_tui._handle_mouse "[<0;$2;${1}m"
		_tui.frame_present
	} >"$_T_ROOT/cl.out"
	_TUI_RUNNING=0
}

# _cl_painted ROW COL GLYPH - true when the output of the last click draws GLYPH at the cell
_cl_painted() { LC_ALL=C grep -aqP $'\e\\['"$1;${2}"$'H(\e\\[[0-9;]*m)*'"$3" "$_T_ROOT/cl.out"; }

# _cl_ws_ready - the workspace page rendered, its Services pane reporting toggles in _CL_TOGGLES; _CL_R/_CL_C = its button
_cl_ws_ready() {
	_ws_load_page
	tui.render >/dev/null
	_TUI_P_ON_TOGGLE[services]=_cl_on_toggle
	_CL_TOGGLES=""
	_tui_collapse.cell services
}

ti_collapse_button_click_paints_the_moved_button_and_drops_the_old_one() {
	_cl_ws_ready
	local r=$_CL_R c=$_CL_C g=$_CL_G nr nc ng
	_cl_ws_click "$r" "$c"
	ok 'tui.collapsed services'
	_tui_collapse.cell services
	nr=$_CL_R nc=$_CL_C ng=$_CL_G
	ok '((nc != c))'
	_cl_painted "$nr" "$nc" "$ng" || _t_fail "no $ng painted at $nr,$nc"
	_cl_painted "$r" "$c" "$g" && _t_fail "old $g painted at $r,$c"
	_cl_ws_click "$nr" "$nc" # the new position is the live zone
	ok '! tui.collapsed services'
	_cl_painted "$r" "$c" "$g" || _t_fail "no $g painted at $r,$c"
	_cl_painted "$nr" "$nc" "$ng" && _t_fail "collapsed $ng painted at $nr,$nc"
	eq "services:collapsed;services:expanded;" "$_CL_TOGGLES"
}

ti_collapse_button_second_cell_toggles_and_the_zone_follows_the_button() {
	_cl_ws_ready
	local r=$_CL_R c=$_CL_C
	_cl_ws_click "$r" $((c + 1)) # the cell shared with the resize border
	ok 'tui.collapsed services'
	_tui_collapse.cell services
	_tui_hit.at $((_CL_C + 1)) "$_CL_R"
	eq "chevron services cv-toggle" "$_HIT_KIND $_HIT_ID $_HIT_ARG"
	_cl_ws_click "$_CL_R" $((_CL_C + 1))
	ok '! tui.collapsed services'
	eq "services:collapsed;services:expanded;" "$_CL_TOGGLES"
}
