# frame.t.sh - tui.frame.request: redraw requests coalesce into one frame per loop iteration.

t_frame_request_sets_the_flag_without_painting() {
	_TUI_FRAME_REQ=0
	local out
	tui.frame.request >"$_T_ROOT/fr.out"
	eq "" "$(<"$_T_ROOT/fr.out")"
	eq 1 "$_TUI_FRAME_REQ"
}

t_frame_present_runs_one_relayout_for_many_requests() {
	_FR_N=0
	local _orig
	_orig="$(declare -f tui.relayout)"
	tui.relayout() { _FR_N=$((_FR_N + 1)); }
	_TUI_FRAME_REQ=0
	tui.frame.request
	tui.frame.request
	tui.frame.request
	_tui.frame_present
	_tui.frame_present
	eval "$_orig"
	eq 1 "$_FR_N"
	eq 0 "$_TUI_FRAME_REQ"
}

t_frame_present_without_request_does_nothing() {
	_FR_N=0
	local _orig
	_orig="$(declare -f tui.relayout)"
	tui.relayout() { _FR_N=$((_FR_N + 1)); }
	_TUI_FRAME_REQ=0
	_tui.frame_present
	eval "$_orig"
	eq 0 "$_FR_N"
}

t_frame_immediate_render_satisfies_a_pending_request() {
	_TUI_FRAME_REQ=1
	tui.render >/dev/null 2>&1
	eq 0 "$_TUI_FRAME_REQ"
}

# ── fused panes + titles ────────────────────────────────────────────────────

_fuse_reset_root() { _TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=${1:-20} _TUI_P_W[root]=${2:-80}; }
_fuse_all() {
	local p
	for p in "$@"; do tui.pane_fuse "$p" true; done
	_tui._layout root
}
_fuse_rect() { printf '%s,%s,%s,%s' "${_TUI_P_ROW[$1]}" "${_TUI_P_COL[$1]}" "${_TUI_P_H[$1]}" "${_TUI_P_W[$1]}"; }

# _fuse_draw - draws every bordered pane + the junction pass into _TUI_FRAME, then parses it into _FS["row,col"]=glyph
_fuse_draw() {
	local p
	_TUI_FRAME=""
	for p in "${_TUI_P_ALL[@]}"; do
		_tui._eff_border "$p"
		[[ -n "${_TUI_P_CHILDREN[$p]:-}" && "$_TB" == none ]] && continue
		_tui._draw_pane_buf "$p"
	done
	_tui_frame.junctions
	_fuse_parse "$_TUI_FRAME"
}
_fuse_parse() {
	declare -gA _FS=()
	local s="$1" r=1 c=1 tok ch
	while [[ "$s" =~ ^($'\e'\[([0-9]+)\;([0-9]+)H|$'\e'\[[0-9\;?]*[a-zA-Z]|[^$'\e']+)(.*)$ ]]; do
		tok="${BASH_REMATCH[1]}" s="${BASH_REMATCH[4]}"
		if [[ -n "${BASH_REMATCH[2]}" ]]; then
			r="${BASH_REMATCH[2]}" c="${BASH_REMATCH[3]}"
		elif [[ "$tok" != $'\e'* ]]; then
			while [[ "$tok" =~ ^([^$'\x80'-$'\xbf'][$'\x80'-$'\xbf']*)(.*)$ ]]; do
				_FS["$r,$c"]="${BASH_REMATCH[1]}" tok="${BASH_REMATCH[2]}"
				c=$((c + 1))
			done
		fi
	done
}
_fuse_row() {
	local c r="$1" out=""
	for ((c = $2; c <= $3; c++)); do out+="${_FS[$r,$c]:- }"; done
	printf '%s' "$out"
}

t_fuse_default_is_false_and_layout_unchanged() {
	_fuse_reset_root
	tui.hsplit root a b
	eq "1,1,20,40" "$(_fuse_rect a)"
	eq "1,41,20,40" "$(_fuse_rect b)"
}

t_fuse_two_h_siblings_share_one_column() {
	_fuse_reset_root
	tui.hsplit root a b
	_fuse_all a b
	eq "1,1,20,41" "$(_fuse_rect a)"
	eq "1,41,20,40" "$(_fuse_rect b)"
}

t_fuse_three_h_siblings_overlap_by_one() {
	_fuse_reset_root 20 82
	tui.hsplit root a b c
	_fuse_all a b c
	eq "1,1,20,28" "$(_fuse_rect a)"
	eq "1,28,20,28" "$(_fuse_rect b)"
	eq "1,55,20,28" "$(_fuse_rect c)"
}

t_fuse_two_v_siblings_share_one_row() {
	_fuse_reset_root 20 80
	tui.vsplit root a b
	_fuse_all a b
	eq "1,1,11,80" "$(_fuse_rect a)"
	eq "11,1,10,80" "$(_fuse_rect b)"
}

ti_fuse_three_v_siblings_overlap_by_one() {
	_fuse_reset_root 22 80
	tui.vsplit root a b c
	_fuse_all a b c
	eq "1,1,8,80" "$(_fuse_rect a)"
	eq "8,1,8,80" "$(_fuse_rect b)"
	eq "15,1,8,80" "$(_fuse_rect c)"
}

t_fuse_needs_every_sibling_fused() {
	_fuse_reset_root
	tui.hsplit root a b
	_fuse_all a
	eq "1,1,20,40" "$(_fuse_rect a)"
	eq "1,41,20,40" "$(_fuse_rect b)"
}

t_fuse_false_restores_layout() {
	_fuse_reset_root
	tui.hsplit root a b
	_fuse_all a b
	tui.pane_fuse a false
	tui.pane_fuse b false
	_tui._layout root
	eq "1,41,20,40" "$(_fuse_rect b)"
}

t_fuse_setter_rejects_a_bad_value() {
	tui.pane_fuse a maybe 2>/dev/null
	eq "" "${_TUI_P_FUSE[a]:-}"
}

ti_fuse_shared_edge_draws_t_junctions() {
	_fuse_reset_root 6 21
	tui.hsplit root a b
	_fuse_all a b
	_fuse_draw
	# seam is column 11 (a: 1..11, b: 11..21)
	eq "┬" "${_FS[1,11]}"
	eq "│" "${_FS[3,11]}"
	eq "┴" "${_FS[6,11]}"
}

ti_fuse_nested_split_draws_a_cross_and_side_tees() {
	_fuse_reset_root 9 21
	tui.hsplit root a b
	tui.vsplit b c d
	_fuse_all a b c d
	_fuse_draw
	# a: cols 1..11, b: 11..21; c rows 1..5, d rows 5..9 -> tee on the seam at (5,11), end tees on the outer edge
	eq "├" "${_FS[5,11]}"
	eq "┤" "${_FS[5,21]}"
	eq "┬" "${_FS[1,11]}"
	eq "┴" "${_FS[9,11]}"
}

ti_fuse_two_by_two_grid_draws_a_cross() {
	_fuse_reset_root 9 21
	tui.vsplit root p q
	tui.hsplit p p1 p2
	tui.hsplit q q1 q2
	_fuse_all p q p1 p2 q1 q2
	_fuse_draw
	eq "┼" "${_FS[5,11]}"
	eq "├" "${_FS[5,1]}"
	eq "┤" "${_FS[5,21]}"
}

ti_fuse_mixed_borders_use_the_mixed_glyphs() {
	_fuse_reset_root 6 21
	tui.hsplit root a b
	tui.pane_border a double
	tui.pane_border b single
	tui.pane_divider b single
	_fuse_all a b
	_fuse_draw
	eq "┬" "${_FS[1,11]}"
}

ti_fuse_divider_overrides_the_shared_line_style() {
	_fuse_reset_root 6 21
	tui.hsplit root a b
	tui.pane_border a single
	tui.pane_border b single
	tui.pane_divider b double
	_fuse_all a b
	_fuse_draw
	eq "╦" "${_FS[1,11]}"
	eq "║" "${_FS[3,11]}"
	eq "╩" "${_FS[6,11]}"
}

t_fuse_unfused_pass_draws_nothing() {
	_fuse_reset_root 6 21
	tui.hsplit root a b
	_TUI_FRAME=""
	_tui_frame.junctions
	eq "" "$_TUI_FRAME"
}

# ── titles ──────────────────────────────────────────────────────────────

_title_line() { # ID ROW -> the pane's drawn text on that row
	_TUI_FRAME=""
	_tui._draw_pane_buf "$1"
	_fuse_parse "$_TUI_FRAME"
	_fuse_row "$2" "${_TUI_P_COL[$1]}" $((${_TUI_P_COL[$1]} + ${_TUI_P_W[$1]} - 1))
}
_dash() {
	local o
	printf -v o "%*s" "$1" ""
	printf "%s" "${o// /─}"
}
_title_pane() {
	_fuse_reset_root 6 20
	tui.hsplit root a
	tui.pane_title a "Hi"
}

ti_title_default_is_top_left() {
	_title_pane
	eq "┌─ Hi $(_dash 13)┐" "$(_title_line a 1)"
	eq "└$(_dash 18)┘" "$(_title_line a 6)"
}

ti_title_align_right_and_center() {
	_title_pane
	tui.pane_title_align a right
	eq "┌$(_dash 13) Hi ─┐" "$(_title_line a 1)"
}

ti_title_align_center_places_the_tag_in_the_middle() {
	_title_pane
	tui.pane_title_align a center
	eq "┌$(_dash 7) Hi $(_dash 7)┐" "$(_title_line a 1)"
}

ti_title_pos_bottom_moves_the_tag_to_the_last_line() {
	_title_pane
	tui.pane_title_pos a bottom
	eq "┌$(_dash 18)┐" "$(_title_line a 1)"
	eq "└─ Hi $(_dash 13)┘" "$(_title_line a 6)"
}

ti_title_longer_than_the_width_is_cut() {
	_title_pane
	tui.pane_title a "A very long title indeed"
	eq "┌─ A very long ti ─┐" "$(_title_line a 1)"
}

t_title_setters_reject_bad_values() {
	tui.pane_title_pos a middle 2>/dev/null
	tui.pane_title_align a justify 2>/dev/null
	eq "" "${_TUI_P_TITLE_POS[a]:-}${_TUI_P_TITLE_ALIGN[a]:-}"
}

ti_title_pos_and_align_are_part_of_the_cache_key() {
	_title_pane
	_title_line a 1 >/dev/null
	tui.pane_title_align a right
	local right
	right="$(_title_line a 1)"
	tui.pane_title_align a left
	[[ "$(_title_line a 1)" != "$right" ]] || _t_fail "left and right rendered the same bytes (stale cache entry)"
}

# ── titles on the shared line of fused splits ───────────────────────────

_fuse_titles_v() { # two fused v-siblings a above b on 9 x 24; the shared line is row 5
	_fuse_reset_root 9 24
	tui.vsplit root a b
	tui.pane_title a "Up"
	tui.pane_title b "Low"
	_fuse_all a b
}

ti_fuse_lower_title_is_drawn_on_the_shared_line() {
	_fuse_titles_v
	_fuse_draw
	eq "5" "${_TUI_P_ROW[b]}"
	eq "├─ Low $(_dash 16)┤" "$(_fuse_row 5 1 24)"
	eq "┌─ Up $(_dash 17)┐" "$(_fuse_row 1 1 24)"
}

ti_fuse_lower_title_follows_its_alignment() {
	_fuse_titles_v
	tui.pane_title_align b right
	_fuse_draw
	eq "├$(_dash 16) Low ─┤" "$(_fuse_row 5 1 24)"
	tui.pane_title_align b center
	_fuse_draw
	eq "├$(_dash 8) Low $(_dash 9)┤" "$(_fuse_row 5 1 24)"
}

ti_fuse_lower_title_sits_right_of_the_upper_bottom_title() {
	_fuse_titles_v
	tui.pane_title_pos a bottom
	_fuse_draw
	eq "├─ Up ─ Low $(_dash 11)┤" "$(_fuse_row 5 1 24)"
}

ti_fuse_shared_title_is_truncated_and_never_hits_a_junction() {
	_fuse_reset_root 9 24
	tui.vsplit root top b
	tui.hsplit top p q
	tui.pane_title b "A title far too long for this line"
	_fuse_all top p q b
	_fuse_draw
	# the line p / q / b share is row 5; p and q meet at column 13: the tag stops before that tee
	eq "┴" "${_FS[5,13]}"
	eq "├─ A title f┴" "$(_fuse_row 5 1 13)"
}

ti_fuse_right_pane_title_in_an_h_split_keeps_its_top_row() {
	_fuse_reset_root 6 24
	tui.hsplit root a b
	tui.pane_title a "L"
	tui.pane_title b "R"
	_fuse_all a b
	_fuse_draw
	eq "┌─ L ───────┬─ R ──────┐" "$(_fuse_row 1 1 24)"
}

# ── golden frame: nested fused panes with mixed borders ─────────────────

ti_fuse_golden_nested_mixed_borders() {
	local got
	# frame.sh prints a one-time update banner before the first frame; the golden starts at the synchronized-output marker
	got="$("$REPO/tools/frame.sh" "$REPO/tests/unit/golden/fuse_nested.xml" 60x14 --sgr | sed -n $'/\e\\[?2026h/,$p')"
	if [[ ! -r "$REPO/tests/unit/golden/fuse_nested.frame" ]]; then
		printf '%s\n' "$got" >"$REPO/tests/unit/golden/fuse_nested.frame"
		_t_fail "golden recorded; review tests/unit/golden/fuse_nested.frame and re-run"
		return
	fi
	eq "$(<"$REPO/tests/unit/golden/fuse_nested.frame")" "$got"
}

ti_fuse_golden_titles_on_the_shared_line() {
	local got
	got="$("$REPO/tools/frame.sh" "$REPO/tests/unit/golden/fuse_titles.xml" 50x10 --sgr | sed -n $'/\e\\[?2026h/,$p')"
	if [[ ! -r "$REPO/tests/unit/golden/fuse_titles.frame" ]]; then
		printf '%s\n' "$got" >"$REPO/tests/unit/golden/fuse_titles.frame"
		_t_fail "golden recorded; review tests/unit/golden/fuse_titles.frame and re-run"
		return
	fi
	eq "$(<"$REPO/tests/unit/golden/fuse_titles.frame")" "$got"
}

# ── validator ───────────────────────────────────────────────────────────

_fuse_validate() { # ATTRS -> $_FV: severity+message lines for a pane carrying ATTRS
	local f="$HOME/fv.xml" i
	printf '<tui>\n<pane id="p" split="h">\n<pane id="q" %s/>\n</pane>\n</tui>\n' "$1" >"$f"
	tui.validate.files "$f"
	_FV=""
	for i in "${!_TV_F_MSG[@]}"; do _FV+="${_TV_F_SEV[i]} ${_TV_F_MSG[i]}"$'\n'; done
}

ti_fuse_validator_accepts_the_new_attributes() {
	_fuse_validate 'fuse="true" divider="double" divider_class="x" title_pos="bottom" title_align="center" title="T"'
	eq "" "$_FV"
}

ti_fuse_validator_rejects_bad_values() {
	_fuse_validate 'fuse="yes" title_pos="middle" title_align="justify" divider="dotted"'
	match "$_FV" "fuse"
	match "$_FV" "title_pos"
	match "$_FV" "title_align"
	match "$_FV" "divider"
}
