# pane_resize.t.sh - resizable panes: weight transfer, min/max clamp, handles, drag, keyboard mode, reset.
# The mode / drag globals sit outside the runner's snapshot: _rz_setup clears them.

_rz_setup() {
	_TUI_ROWS=24 _TUI_RESIZE_PANE="" _TUI_RZ_ID="" _TUI_RZ_LAST_ID="" _TUI_RZ_LAST_T=0 _TUI_RZ_ZONES=0 _TUI_PANE_FOCUS="" _TUI_FOCUS_ID=""
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=${1:-80}
	_tui_resize.now() { _RZ_T=${_RZ_NOW:-0}; }
}
_rz_w() { printf '%s' "${_TUI_P_W[$1]}"; }
_rz_h() { printf '%s' "${_TUI_P_H[$1]}"; }
# _rz_zones - "kind:id:arg@row,col,h,w" per registered resize zone
_rz_zones() {
	local i out=()
	for ((i = 0; i < ${#_TUI_HZ_EXTRA[@]}; i += 7)); do
		out+=("${_TUI_HZ_EXTRA[i]}:${_TUI_HZ_EXTRA[i + 1]}:${_TUI_HZ_EXTRA[i + 2]}@${_TUI_HZ_EXTRA[i + 3]},${_TUI_HZ_EXTRA[i + 4]},${_TUI_HZ_EXTRA[i + 5]},${_TUI_HZ_EXTRA[i + 6]}")
	done
	printf '%s' "${out[*]}"
}

t_resize_moves_weight_between_two_siblings() {
	_rz_setup
	tui.hsplit root a b
	_tui._layout root
	tui.resize a 10 0
	eq "50 30" "$(_rz_w a) $(_rz_w b)"
	eq "1.25fr 0.75fr" "${_TUI_P_WEIGHTS[root]}"
}

ti_resize_with_three_siblings_leaves_the_third_alone() {
	_rz_setup 90
	tui.hsplit root a b c
	_tui._layout root
	tui.resize a 6 0
	eq "36 24 30" "$(_rz_w a) $(_rz_w b) $(_rz_w c)"
	eq "1" "${_TUI_P_WEIGHTS[root]##* }"
}

t_resize_is_proportional_to_the_weights_held_now() {
	_rz_setup
	tui.hsplit root a:1 b:3
	_tui._layout root
	tui.resize a 10 0 # a=20 b=60 -> a=30 b=50: weights 4 split 1.5 / 2.5
	eq "30 50" "$(_rz_w a) $(_rz_w b)"
	eq "1.5fr 2.5fr" "${_TUI_P_WEIGHTS[root]}"
}

t_resize_keeps_percent_units() {
	_rz_setup
	tui.hsplit root a:30% b:70%
	_tui._layout root
	tui.resize a 8 0
	eq "40% 60%" "${_TUI_P_WEIGHTS[root]}"
}

t_resize_respects_the_next_siblings_min_width() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_minsize b 35 ""
	_tui._layout root
	tui.resize a 30 0
	eq "45 35" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_respects_max_width() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_maxsize a 45 ""
	_tui._layout root
	tui.resize a 30 0
	eq "45 35" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_never_shrinks_below_min_width() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_minsize a 30 ""
	_tui._layout root
	tui.resize a -30 0
	eq "30 50" "$(_rz_w a) $(_rz_w b)"
}

t_resize_vertical_split_moves_rows() {
	_rz_setup
	tui.vsplit root a b
	_tui._layout root
	tui.resize a 0 4
	eq "14 6" "$(_rz_h a) $(_rz_h b)"
}

ti_resize_corner_moves_the_nearest_edge_on_each_axis() {
	_rz_setup
	tui.vsplit root top bottom
	tui.hsplit top l r
	_tui._layout root
	tui.resize l 5 3 # l: the h-split edge to its right; l has no v-split edge of its own, so top / bottom moves
	eq "45 35" "$(_rz_w l) $(_rz_w r)"
	eq "13 7" "$(_rz_h top) $(_rz_h bottom)"
}

ti_resize_last_child_grows_at_the_expense_of_its_previous_sibling() {
	_rz_setup
	tui.hsplit root a b
	_tui._layout root
	tui.resize b 10 0
	eq "30 50" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_climbs_to_an_ancestor_split_when_the_parent_axis_differs() {
	_rz_setup
	tui.hsplit root left right
	tui.vsplit right up down
	_tui._layout root
	tui.resize up 10 0 # up sits in a v-split: its width moves the h-split edge above it
	eq "30 50" "$(_rz_w left) $(_rz_w right)"
}

t_resize_reports_no_change_when_clamped_flat() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_maxsize a 40 ""
	_tui._layout root
	tui.resize a 5 0 && return 1
	eq "40 40" "$(_rz_w a) $(_rz_w b)"
}

t_resize_bumps_the_layout_generation() {
	_rz_setup
	tui.hsplit root a b
	_tui._layout root
	local g=$_TUI_LY_GEN
	tui.resize a 3 0
	ok '((_TUI_LY_GEN > g))'
}

ti_resize_reset_restores_the_first_weights() {
	_rz_setup
	tui.hsplit root a b
	_tui._layout root
	tui.resize a 10 0
	tui.resize a 5 0
	tui.resize.reset a
	eq "40 40" "$(_rz_w a) $(_rz_w b)"
	eq "1 1" "${_TUI_P_WEIGHTS[root]}"
}

t_resize_on_resize_gets_the_pane_and_its_new_size() {
	_rz_setup
	_rz_cb() { _RZ_CB="$1 $2 $3"; }
	_RZ_CB=""
	tui.hsplit root a b
	_TUI_P_ON_RESIZE[a]=_rz_cb
	_tui._layout root
	tui.resize a 10 0
	eq "a 50 20" "$_RZ_CB"
}

t_resize_on_resize_skips_unchanged_panes() {
	_rz_setup 90
	_rz_cb() { _RZ_CB+="$1;"; }
	_RZ_CB=""
	tui.hsplit root a b c
	_TUI_P_ON_RESIZE[c]=_rz_cb
	_tui._layout root
	tui.resize a 6 0
	eq "" "$_RZ_CB"
}

t_resize_attrs_reject_bad_values() {
	tui.pane_resizable a diagonal 2>/dev/null && return 1
	tui.pane_handle a grip 2>/dev/null && return 1
	eq "" "${_TUI_P_RESIZABLE[a]:-}${_TUI_P_HANDLE[a]:-}"
	tui.pane_resizable a both
	eq both "${_TUI_P_RESIZABLE[a]}"
}

# ── mouse zones ──────────────────────────────────────────────────────────

t_resize_handle_none_registers_no_zones() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a both
	_tui._layout root
	_tui_hit.rebuild
	eq "" "$(_rz_zones)"
}

t_resize_edge_zone_is_the_last_column_of_the_pane() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a x
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
	eq "handle:a:rz-h@1,40,20,1" "$(_rz_zones)"
}

t_resize_divider_zone_in_a_vertical_split_is_the_last_row() {
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable a both
	tui.pane_handle a divider
	_tui._layout root
	_tui_hit.rebuild
	eq "divider:a:rz-v@10,1,1,80" "$(_rz_zones)"
}

t_resize_edge_on_the_wrong_axis_has_no_zone() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a y
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
	eq "" "$(_rz_zones)"
}

t_resize_last_sibling_edge_zone_sits_on_its_leading_column() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b both
	tui.pane_handle b edge
	_tui._layout root
	_tui_hit.rebuild
	eq "handle:b:rz-hl@1,41,20,1" "$(_rz_zones)"
}

t_resize_last_sibling_divider_zone_sits_on_its_leading_row() {
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable b y
	tui.pane_handle b divider
	_tui._layout root
	_tui_hit.rebuild
	eq "divider:b:rz-vl@11,1,1,80" "$(_rz_zones)"
}

t_resize_only_child_has_no_edge_zone() {
	_rz_setup
	tui.hsplit root a
	tui.pane_resizable a both
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
	eq "" "$(_rz_zones)"
}

t_resize_middle_pane_edge_keeps_its_trailing_zone() {
	_rz_setup 90
	tui.hsplit root a b c
	tui.pane_resizable b x
	tui.pane_handle b edge
	_tui._layout root
	_tui_hit.rebuild
	eq "handle:b:rz-h@1,60,20,1" "$(_rz_zones)"
}

ti_resize_last_pane_leading_drag_moves_the_border_it_shares_with_the_previous() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	tui.pane_handle b edge
	_tui._layout root
	_tui_hit.rebuild
	_HIT_ID=b _HIT_ARG=rz-hl
	_tui_resize.mouse mouse:left 41 5
	_tui_resize.mouse drag:left 31 5 # border left by 10: b grows
	eq "30 50" "$(_rz_w a) $(_rz_w b)"
	_tui_resize.mouse drag:left 36 5 # back right by 5, relative to the followed border
	eq "35 45" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_last_pane_leading_drag_vertical() {
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable b y
	tui.pane_handle b divider
	_tui._layout root
	_HIT_ID=b _HIT_ARG=rz-vl
	_tui_resize.mouse mouse:left 5 11
	_tui_resize.mouse drag:left 5 15
	eq "14 6" "$(_rz_h a) $(_rz_h b)"
}

ti_resize_last_pane_leading_drag_is_clamped_and_anchor_follows() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	tui.pane_handle b edge
	tui.pane_minsize a 30 ""
	_tui._layout root
	_HIT_ID=b _HIT_ARG=rz-hl
	_tui_resize.mouse mouse:left 41 5
	_tui_resize.mouse drag:left 1 5
	eq "30 50" "$(_rz_w a) $(_rz_w b)"
	_tui_resize.mouse drag:left 32 5 # border sits at 31: still left of the pointer, so b shrinks by the overshoot
	eq "31 49" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_last_pane_in_a_nested_split_moves_its_own_leading_edge() {
	_rz_setup 90
	tui.hsplit root a b c
	tui.hsplit b x y
	tui.pane_resizable y x
	tui.pane_handle y edge
	_tui._layout root
	_tui_hit.rebuild
	eq "handle:y:rz-hl@1,46,20,1" "$(_rz_zones)"
	_HIT_ID=y _HIT_ARG=rz-hl
	_tui_resize.mouse mouse:left 46 5
	_tui_resize.mouse drag:left 41 5
	eq "30 10 20 30" "$(_rz_w a) $(_rz_w x) $(_rz_w y) $(_rz_w c)"
}

t_resize_last_pane_on_resize_callback_fires() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	tui.pane_on_resize b _rz_cb 2>/dev/null || _TUI_P_ON_RESIZE[b]=_rz_cb
	_rz_cb() { _RZ_GOT="$1 $2 $3"; }
	_tui._layout root
	tui.resize b 10 0
	eq "b 50 20" "$_RZ_GOT"
}

ti_resize_mode_grows_the_last_pane_against_its_previous_sibling() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b both
	_tui._layout root
	_TUI_PANE_FOCUS=b
	tui.action.resize_mode
	_tui_resize.key left # left shrinks the focused pane: b gives a column to a
	eq "41 39" "$(_rz_w a) $(_rz_w b)"
	_tui_resize.key shift+right
	eq "36 44" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_mode_last_pane_in_a_nested_split_uses_its_own_split() {
	_rz_setup 90
	tui.hsplit root a b c
	tui.hsplit b x y
	tui.pane_resizable y both
	_tui._layout root
	_TUI_PANE_FOCUS=y
	tui.action.resize_mode
	_tui_resize.key left
	eq "30 16 14 30" "$(_rz_w a) $(_rz_w x) $(_rz_w y) $(_rz_w c)"
}

t_resize_handle_none_last_pane_stays_keyboard_only() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	_tui._layout root
	_tui_hit.rebuild
	eq "" "$(_rz_zones)"
}

t_resize_corner_zone_is_the_bottom_right_cell() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b both
	tui.pane_handle b corner
	_tui._layout root
	_tui_hit.rebuild
	eq "handle:b:rz-corner@20,80,1,1" "$(_rz_zones)"
}

ti_resize_zones_follow_the_layout() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a x
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
	tui.resize a 10 0
	_tui_hit.rebuild
	eq "handle:a:rz-h@1,50,20,1" "$(_rz_zones)"
	_tui_hit.at 50 5
	eq "handle a rz-h" "$_HIT_KIND $_HIT_ID $_HIT_ARG"
}

t_resize_zones_vanish_with_the_handle() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a x
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
	tui.pane_handle a none
	_tui_hit.rebuild
	eq "" "$(_rz_zones)"
}

_rz_edge_page() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a x
	tui.pane_handle a edge
	_tui._layout root
	_tui_hit.rebuild
}

ti_resize_drag_press_move_release() {
	_rz_edge_page
	_HIT_ID=a _HIT_ARG=rz-h
	_tui_resize.mouse mouse:left 40 5
	eq a "$_TUI_RZ_ID"
	_tui_resize.mouse drag:left 50 5
	eq "50 30" "$(_rz_w a) $(_rz_w b)"
	_tui_resize.mouse drag:left 45 5
	eq "45 35" "$(_rz_w a) $(_rz_w b)"
	_tui_resize.mouse release 45 5
	eq "" "$_TUI_RZ_ID"
	_tui_resize.mouse drag:left 20 5 && return 1
	eq "45 35" "$(_rz_w a) $(_rz_w b)"
}

ti_resize_drag_anchor_follows_the_clamped_border() {
	_rz_edge_page
	tui.pane_maxsize a 45 ""
	_HIT_ID=a _HIT_ARG=rz-h
	_tui_resize.mouse mouse:left 40 5
	_tui_resize.mouse drag:left 60 5
	eq 45 "$(_rz_w a)"
	_tui_resize.mouse drag:left 46 5 # still right of the border: nothing moves
	eq 45 "$(_rz_w a)"
	_tui_resize.mouse drag:left 41 5
	eq 41 "$(_rz_w a)"
}

ti_resize_drag_ignores_an_axis_the_pane_does_not_allow() {
	_rz_setup
	tui.vsplit root top bottom
	tui.hsplit top l r
	tui.pane_resizable r x
	tui.pane_handle r corner
	_tui._layout root
	_tui_hit.rebuild
	_HIT_ID=r _HIT_ARG=rz-corner
	_tui_resize.mouse mouse:left 80 10
	_tui_resize.mouse drag:left 75 14
	eq "45 35 10" "$(_rz_w l) $(_rz_w r) $(_rz_h top)"
}

ti_resize_corner_drag_moves_both_axes() {
	_rz_setup
	tui.vsplit root top bottom
	tui.hsplit top l r
	tui.pane_resizable l both
	tui.pane_handle l corner
	_tui._layout root
	_tui_hit.rebuild
	_HIT_ID=l _HIT_ARG=rz-corner
	_tui_resize.mouse mouse:left 40 10
	_tui_resize.mouse drag:left 45 12
	eq "45 35 12" "$(_rz_w l) $(_rz_w r) $(_rz_h top)"
}

ti_resize_double_press_resets_the_pane() {
	_rz_edge_page
	_HIT_ID=a _HIT_ARG=rz-h
	_RZ_NOW=1000000
	_tui_resize.mouse mouse:left 40 5
	_tui_resize.mouse drag:left 50 5
	_tui_resize.mouse release 50 5
	_RZ_NOW=1200000
	_tui_resize.mouse mouse:left 50 5
	eq "40 40" "$(_rz_w a) $(_rz_w b)"
	eq "" "$_TUI_RZ_ID"
}

ti_resize_slow_second_press_only_starts_a_drag() {
	_rz_edge_page
	_HIT_ID=a _HIT_ARG=rz-h
	_RZ_NOW=1000000
	_tui_resize.mouse mouse:left 40 5
	_tui_resize.mouse drag:left 50 5
	_tui_resize.mouse release 50 5
	_RZ_NOW=1900000
	_tui_resize.mouse mouse:left 50 5
	eq "50 30" "$(_rz_w a) $(_rz_w b)"
	eq a "$_TUI_RZ_ID"
}

t_resize_mouse_hook_ignores_other_zones() {
	_rz_edge_page
	_HIT_ID=a _HIT_ARG=v
	_tui_resize.mouse mouse:left 3 3 && return 1
	_tui_resize.mouse drag:left 3 3 && return 1
	return 0
}

# ── keyboard mode ────────────────────────────────────────────────────────

_rz_key_page() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a both
	_tui._layout root
	_TUI_PANE_FOCUS=a
	tui.action.resize_mode
}

t_resize_mode_enters_on_the_focused_resizable_pane() {
	_rz_key_page
	eq a "$_TUI_RESIZE_PANE"
	tui.action.resize_mode
	eq "" "$_TUI_RESIZE_PANE"
}

t_resize_mode_needs_a_resizable_pane() {
	_rz_setup
	tui.hsplit root a b
	_TUI_PANE_FOCUS=a
	tui.action.resize_mode && return 1
	eq "" "$_TUI_RESIZE_PANE"
}

t_resize_mode_finds_a_resizable_ancestor() {
	_rz_setup
	tui.hsplit root a b
	tui.vsplit b c d
	tui.pane_resizable b x
	_TUI_PANE_FOCUS=d
	tui.action.resize_mode
	eq b "$_TUI_RESIZE_PANE"
}

ti_resize_mode_arrows_step_one_and_shift_arrows_five() {
	_rz_key_page
	_tui_resize.key right
	eq 41 "$(_rz_w a)"
	_tui_resize.key shift+right
	eq 46 "$(_rz_w a)"
	_tui_resize.key left
	eq 45 "$(_rz_w a)"
	_tui_resize.key shift+left
	eq 40 "$(_rz_w a)"
}

ti_resize_mode_down_and_up_move_rows() {
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable a y
	_tui._layout root
	_TUI_PANE_FOCUS=a
	tui.action.resize_mode
	_tui_resize.key down
	_tui_resize.key shift+down
	eq 16 "$(_rz_h a)"
	_tui_resize.key up
	eq 15 "$(_rz_h a)"
}

t_resize_mode_x_only_pane_ignores_vertical_keys() {
	_rz_setup
	tui.vsplit root top bottom
	tui.hsplit top a b
	tui.pane_resizable a x
	_tui._layout root
	_TUI_PANE_FOCUS=a
	tui.action.resize_mode
	_tui_resize.key down
	eq "10" "$(_rz_h top)"
}

t_resize_mode_enter_and_esc_leave() {
	_rz_key_page
	_tui_resize.key enter
	eq "" "$_TUI_RESIZE_PANE"
	tui.action.resize_mode
	_tui_resize.key esc
	eq "" "$_TUI_RESIZE_PANE"
}

t_resize_mode_passes_other_keys_on() {
	_rz_key_page
	_tui_resize.key x && return 1
	eq a "$_TUI_RESIZE_PANE"
}

t_resize_mode_respects_clamps() {
	_rz_key_page
	tui.pane_maxsize a 41 ""
	_tui_resize.key shift+right
	eq 41 "$(_rz_w a)"
}

# ── footer ───────────────────────────────────────────────────────────────

t_resize_footer_items_follow_focus_and_mode() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a both
	_TUI_PANE_FOCUS=a
	_tui_resize.can_enter || return 1
	_tui_resize.in_mode && return 1
	tui.action.resize_mode
	_tui_resize.can_enter && return 1
	_tui_resize.in_mode
}

t_resize_footer_hides_resize_when_nothing_is_resizable() {
	_rz_setup
	tui.hsplit root a b
	_TUI_PANE_FOCUS=a
	_tui_resize.can_enter && return 1
	return 0
}

# ── markup + validator (integration tier: they load a page / run the validator) ──

_rz_validate() { # ATTRS -> $_RV: severity+message lines for a pane carrying ATTRS
	local f="$HOME/rv.xml" i
	printf '<tui>\n<pane id="p" split="h">\n<pane id="q" %s/>\n</pane>\n</tui>\n' "$1" >"$f"
	tui.validate.files "$f"
	_RV=""
	for i in "${!_TV_F_MSG[@]}"; do _RV+="${_TV_F_SEV[i]} ${_TV_F_MSG[i]}"$'\n'; done
}

ti_resize_validator_accepts_the_new_attributes() {
	_rz_validate 'resizable="both" handle="corner" on_resize="cb"'
	eq "" "$_RV"
}

ti_resize_validator_rejects_bad_values() {
	_rz_validate 'resizable="z" handle="grip"'
	match "$_RV" "resizable"
	match "$_RV" "handle"
}

ti_resize_validator_warns_for_a_handle_without_resizable() {
	_rz_validate 'handle="edge"'
	match "$_RV" "warn pane 'q' has handle=\"edge\" but no resizable"
	_rz_validate 'handle="none"'
	eq "" "$_RV"
}

ti_resize_markup_sets_the_attributes() {
	_rz_setup
	printf '<tui>\n<pane id="r" split="h">\n<pane id="a" resizable="both" handle="edge" on_resize="cb"/>\n<pane id="b"/>\n</pane>\n</tui>\n' >"$HOME/rb.xml"
	tui.load "$HOME/rb.xml" 2>/dev/null
	eq "both edge cb" "${_TUI_P_RESIZABLE[a]} ${_TUI_P_HANDLE[a]} ${_TUI_P_ON_RESIZE[a]}"
	eq "" "${_TUI_P_RESIZABLE[b]:-}"
}

# ── fused splits: the drag stops where both panes keep their border ──────

_rz_fused_v() {
	_rz_setup 40
	tui.vsplit root a b
	tui.pane_fuse a true
	tui.pane_fuse b true
	tui.pane_resizable a y
	tui.pane_handle a divider
	_tui._layout root
}

ti_resize_fused_top_pane_stops_at_three_rows_and_keeps_its_top_border() {
	_rz_fused_v
	tui.resize a 0 -40
	eq "1 3 3 18" "${_TUI_P_ROW[a]} $(_rz_h a) ${_TUI_P_ROW[b]} $(_rz_h b)"
	_fuse_draw
	eq "┌" "${_FS[1,1]}"
	eq "├" "${_FS[3,1]}"
}

ti_resize_fused_bottom_pane_stops_at_three_rows_and_keeps_its_bottom_border() {
	_rz_fused_v
	tui.resize a 0 40
	eq "18 3" "$(_rz_h a) $(_rz_h b)"
	_fuse_draw
	eq "└" "${_FS[20,1]}"
	eq "├" "${_FS[18,1]}"
}

ti_resize_fused_h_split_stops_at_five_columns() {
	_rz_setup 40
	tui.hsplit root a b
	tui.pane_fuse a true
	tui.pane_fuse b true
	_tui._layout root
	tui.resize a -40 0
	eq "5" "$(_rz_w a)"
	tui.resize a 40 0
	eq "5" "$(_rz_w b)"
}

ti_resize_fused_min_attributes_beat_the_border_floor() {
	_rz_fused_v
	tui.pane_minsize a "" 7
	tui.pane_minsize b "" 9
	tui.resize a 0 -40
	eq "7" "$(_rz_h a)"
	tui.resize a 0 40
	eq "9" "$(_rz_h b)"
}

t_resize_unfused_panes_still_shrink_to_one_row() {
	_rz_setup
	tui.vsplit root a b
	_tui._layout root
	tui.resize a 0 -40
	eq "1" "$(_rz_h a)"
}

# ── hover (tui_hit.sh _tui_hit.hover, _tui_resize.seg_buf) ───────────────

# _TUI_RUNNING and function definitions are not snapshotted by the runner: _rz_capture swaps in a flush that records to
# _RZ_PAINT and _rz_hover_end (last line of each test using it) puts the real one and the flag back.
_rz_capture() {
	[[ -n "${_RZ_FLUSH_DEF:-}" ]] || _RZ_FLUSH_DEF="$(declare -f _tui_paint.flush)"
	_TUI_HZ_HOVER="" _TUI_RUNNING=1 _RZ_PAINT=""
	_tui_paint.flush() { _RZ_PAINT+="$1"; }
}
_rz_hover_end() {
	_TUI_RUNNING=0
	eval "$_RZ_FLUSH_DEF"
}
_rz_hover_page() { # edge page, hover tracking on, paints captured in _RZ_PAINT
	_rz_edge_page
	_rz_capture
}
_rz_over() {
	_tui_hit.at "$1" "$2"
	_tui_hit.hover
} # pointer to COL ROW

t_resize_hover_enter_sets_the_zone_and_repaints_its_segment() {
	_rz_hover_page
	_rz_over 40 5
	eq "a|rz-h" "$_TUI_HZ_HOVER"
	match "$_RZ_PAINT" $'\e\\[5;40H'
	match "$_RZ_PAINT" $'\e\\[20;40H' # the whole 20-row segment
	_rz_hover_end
}

t_resize_hover_leave_clears_and_restores_the_segment() {
	_rz_hover_page
	_rz_over 40 5
	_RZ_PAINT=""
	_rz_over 10 5
	eq "" "$_TUI_HZ_HOVER"
	match "$_RZ_PAINT" $'\e\\[5;40H'
	_rz_hover_end
}

t_resize_hover_unchanged_repaints_nothing() {
	_rz_hover_page
	_rz_over 40 5
	_RZ_PAINT=""
	_rz_over 40 6
	eq "" "$_RZ_PAINT"
	_rz_hover_end
}

t_resize_hover_stays_while_dragging() {
	_rz_hover_page
	_rz_over 40 5
	_TUI_RZ_ID=a _TUI_RZ_ARG=rz-h
	_rz_over 10 5
	eq "a|rz-h" "$_TUI_HZ_HOVER"
	_rz_hover_end
}

t_resize_hover_clears_when_the_drag_ends_away_from_the_border() {
	_rz_hover_page
	_rz_over 40 5
	_HIT_ID=a _HIT_ARG=rz-h
	_RZ_NOW=1000000
	_tui_resize.mouse mouse:left 40 5
	_rz_over 10 5
	eq "a|rz-h" "$_TUI_HZ_HOVER"
	_tui_resize.mouse release 10 5
	eq "" "$_TUI_HZ_HOVER"
	_rz_hover_end
}

t_resize_hover_stays_when_the_drag_ends_on_the_border() {
	_rz_hover_page
	_HIT_ID=a _HIT_ARG=rz-h
	_RZ_NOW=1000000
	_tui_resize.mouse mouse:left 40 5
	_tui_hit.at 40 5
	_tui_resize.mouse release 40 5
	eq "a|rz-h" "$_TUI_HZ_HOVER"
	_rz_hover_end
}

t_resize_hover_applies_the_hover_class() {
	_rz_hover_page
	_TUI_CLASS_FG[resize_handle_hover]="#010203"
	_TUI_FRAME=""
	_TUI_HZ_HOVER="a|rz-h"
	_tui_resize.seg_buf a rz-h
	match "$_TUI_FRAME" "38;2;1;2;3"
	unset '_TUI_CLASS_FG[resize_handle_hover]'
	_rz_hover_end
}

t_resize_segment_at_rest_does_not_use_the_hover_class() {
	_rz_hover_page
	_TUI_CLASS_FG[resize_handle_hover]="#010203"
	_TUI_FRAME=""
	_tui_resize.seg_buf a rz-h
	[[ "$_TUI_FRAME" != *"38;2;1;2;3"* ]] || return 1
	unset '_TUI_CLASS_FG[resize_handle_hover]'
	_rz_hover_end
}

t_resize_hover_covers_a_leading_edge_and_a_corner_zone() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	tui.pane_handle b edge
	tui.pane_resizable a both
	tui.pane_handle a corner
	_tui._layout root
	_tui_hit.rebuild
	_rz_capture
	_rz_over 41 5 # b's leading column
	eq "b|rz-hl" "$_TUI_HZ_HOVER"
	_rz_over 40 20 # a's bottom-right corner
	eq "a|rz-corner" "$_TUI_HZ_HOVER"
	_rz_hover_end
}

# ── segment glyphs and rects (every orientation, every state) ────────────

# _rz_seg PANE ARG [hover] -> $_TUI_FRAME: the segment paint; "hover" names it as the hovered zone
_rz_seg() {
	_TUI_HZ_HOVER=""
	[[ "${3:-}" == hover ]] && _TUI_HZ_HOVER="$1|$2"
	_TUI_FRAME=""
	_tui_resize.seg_buf "$1" "$2"
	_TUI_HZ_HOVER=""
}
# _rz_seg_rows / _rz_seg_cols: the distinct goto rows / cols of $_TUI_FRAME, one line each
_rz_cells() {
	local f="$_TUI_FRAME" out="" re=$'\e'"\\[([0-9]+);([0-9]+)H([^[:cntrl:]]+)"
	while [[ "$f" =~ $re ]]; do
		out+="${BASH_REMATCH[1]},${BASH_REMATCH[2]}${BASH_REMATCH[3]} "
		f="${f#*"${BASH_REMATCH[0]}"}"
	done
	printf '%s' "$out"
}

ti_resize_segment_of_a_v_split_divider_is_a_horizontal_run() {
	local st
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable a y
	tui.pane_handle a divider
	_tui._layout root
	for st in rest hover; do
		_rz_seg a rz-v "$([[ $st == hover ]] && echo hover)"
		local cells
		cells="$(_rz_cells)"
		[[ "$cells" == "10,1"*"10,80"* && "$cells" != *"│"* ]] || _t_fail "v divider $st: $cells"
		[[ "$cells" == *"10,40─"* ]] || _t_fail "v divider $st: no ─ mid-run: $cells"
	done
}

ti_resize_segment_of_an_h_split_divider_is_a_vertical_run() {
	local st
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a x
	tui.pane_handle a divider
	_tui._layout root
	for st in rest hover; do
		_rz_seg a rz-h "$([[ $st == hover ]] && echo hover)"
		local cells
		cells="$(_rz_cells)"
		[[ "$cells" == "1,40"* && "$cells" == *"20,40"* && "$cells" != *"─"* && "$cells" == *"10,40│"* ]] || _t_fail "h divider $st: $cells"
	done
}

ti_resize_segment_follows_the_pane_when_the_divider_moves() {
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable a y
	tui.pane_handle a divider
	_tui._layout root
	_tui_hit.rebuild
	tui.resize a 0 4 # the zone table still holds the old row
	_rz_seg a rz-v hover
	local cells
	cells="$(_rz_cells)"
	[[ "$cells" == "14,1"* && "$cells" != *"10,"* && "$cells" != *"│"* ]] || _t_fail "moved divider: $cells"
	_rz_seg a rz-v # at rest: the plain border colour, same cells
	[[ "$(_rz_cells)" == "$cells" ]] || _t_fail "rest differs from hover cells"
}

ti_resize_segment_of_leading_edges_and_corner() {
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable b x
	tui.pane_handle b divider
	_tui._layout root
	_rz_seg b rz-hl hover
	local cells
	cells="$(_rz_cells)"
	[[ "$cells" == "1,41"* && "$cells" == *"10,41│"* && "$cells" != *"─"* ]] || _t_fail "rz-hl: $cells"
	_rz_setup
	tui.vsplit root a b
	tui.pane_resizable b y
	tui.pane_handle b divider
	_tui._layout root
	_rz_seg b rz-vl hover
	cells="$(_rz_cells)"
	[[ "$cells" == "11,1"*"11,80"* && "$cells" != *"│"* ]] || _t_fail "rz-vl: $cells"
	_rz_setup
	tui.hsplit root a b
	tui.pane_resizable a both
	tui.pane_handle a corner
	_tui._layout root
	_rz_seg a rz-corner hover
	eq "20,40" "$(_rz_cells | cut -d' ' -f1 | tr -d '┘└┐┌─│')"
}
