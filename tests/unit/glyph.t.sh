# glyph.t.sh - theme glyph properties: `.type.variant { key: "glyph"; }` parsed into _TUI_G, resolved variant -> base -> default.

_glyph_theme() { # CSS -> parses and commits it from a file in the test root
	printf '%s\n' "$1" >"$_T_ROOT/glyph.css"
	_tui.theme_parse "$_T_ROOT/glyph.css"
	_tui.theme_commit
}

ti_glyph_base_rule_sets_the_type_slot() {
	_TUI_G=()
	_glyph_theme '.progress { fill: "#"; empty: "-"; }'
	eq "#" "${_TUI_G[progress.fill]}"
	eq "-" "${_TUI_G[progress.empty]}"
}

ti_glyph_variant_selector_sets_its_own_slot_and_keeps_colours() {
	_TUI_G=() _TUI_CLASS_FG=()
	_glyph_theme '.progress.thin {
  fill: "━";
  fg: red;
}'
	eq "━" "${_TUI_G[progress.thin.fill]}"
	eq "red" "${_TUI_CLASS_FG[progress.thin]}"
	eq "" "${_TUI_G[progress.fill]-}"
}

ti_glyph_get_falls_back_variant_then_base_then_default() {
	_TUI_G=()
	_glyph_theme '.progress { empty: "-"; }
.progress.dots { fill: "o"; }'
	tui.glyph.get progress fill dots
	eq "o" "$TUI_GLYPH"
	tui.glyph.get progress empty dots
	eq "-" "$TUI_GLYPH"
	_TUI_G=()
	tui.glyph.get progress fill nosuch
	eq "█" "$TUI_GLYPH"
}

ti_glyph_unknown_key_and_unquoted_value_are_ignored() {
	_TUI_G=()
	_glyph_theme '.progress { bogus: "x"; fill: #; }'
	eq 0 "${#_TUI_G[@]}"
}

ti_glyph_control_characters_are_rejected() {
	_TUI_G=()
	_glyph_theme '.progress { fill: ""; empty: "'$'\e''"; }'
	eq 0 "${#_TUI_G[@]}"
}

ti_glyph_must_be_one_cell_wide_under_utf8() {
	local LC_ALL=C.UTF-8 u=$'\xc3\xa9'
	((${#u} == 1)) || return 0 # no UTF-8 locale on this host: nothing to measure
	_TUI_G=()
	_glyph_theme '.progress { fill: "ab"; empty: "█"; }'
	eq "" "${_TUI_G[progress.fill]-}"
	eq "█" "${_TUI_G[progress.empty]}"
}

ti_glyph_theme_reset_clears_glyphs() {
	_TUI_G[progress.fill]="#"
	TUI_DEFAULTS_DIR=/nonexistent _tui.theme_reset
	eq 0 "${#_TUI_G[@]}"
}

ti_glyph_memoized_theme_reapplies_glyphs() {
	_t_needs_caches || return 0
	printf '%s\n' '.progress.thin { fill: "━"; }' >"$_T_ROOT/gm.css"
	_TUI_G=()
	_tui.theme_load_file "$_T_ROOT/gm.css"
	_TUI_G=()
	_tui.theme_load_file "$_T_ROOT/gm.css"
	eq "━" "${_TUI_G[progress.thin.fill]}"
}

ti_glyph_set_stores_a_valid_slot() {
	_TUI_G=()
	ok 'tui.glyph.set progress fill "#"'
	eq "#" "${_TUI_G[progress.fill]}"
	ok 'tui.glyph.set progress fill "~" thin'
	eq "~" "${_TUI_G[progress.thin.fill]}"
}

ti_glyph_set_rejects_unknown_slots_and_bad_glyphs() {
	_TUI_G=()
	tui.glyph.set progress bogus "x" 2>/dev/null && return 1
	tui.glyph.set progress fill "" 2>/dev/null && return 1
	eq 0 "${#_TUI_G[@]}"
}

ti_glyph_progress_bar_draws_from_the_glyph_slots() {
	_TUI_G=()
	_TUI_W_LABEL[gp]="" _TUI_W_VALUE[gp]=50
	_TUI_FRAME=""
	_tui_wx.draw_progress gp 1 1 20 s p
	match "$_TUI_FRAME" '█+[^░]*░+[^ ]* +50%'
	_TUI_G[progress.fill]="#" _TUI_G[progress.empty]="-"
	_TUI_FRAME=""
	_tui_wx.draw_progress gp 1 1 20 s p
	match "$_TUI_FRAME" '#+[^-]*-+[^ ]* +50%'
}

ti_glyph_progress_cells_take_the_pane_background_unless_the_class_sets_one() {
	_TUI_G=() _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_TUI_STYLE_BG[pb]="#112233"
	_TUI_CLASS_FG[progress]="#445566" _TUI_CLASS_FG[progress_fill]="#778899"
	_TUI_W_LABEL[gp]="" _TUI_W_VALUE[gp]=50
	_TUI_FRAME=""
	_tui_wx.draw_progress gp 1 1 20 s pb
	local bg=$'\e[38;2;119;136;153;48;2;17;34;51m' # fill: class fg, pane bg
	[[ "$_TUI_FRAME" == *"$bg"* ]] || { eq "pane bg on the fill" "$_TUI_FRAME"; }
	[[ "$_TUI_FRAME" == *$'\e[38;2;68;85;102;48;2;17;34;51m'* ]] || eq "pane bg on the empty part" "$_TUI_FRAME"
	[[ "$_TUI_FRAME" == *$'48;2;17;34;51m'*'50%'* ]] || eq "pane bg on the percentage" "$_TUI_FRAME"
	_TUI_CLASS_BG[progress_fill]="#ff0000"
	_TUI_FRAME=""
	_tui_wx.draw_progress gp 1 1 20 s pb
	[[ "$_TUI_FRAME" == *$'38;2;119;136;153;48;2;255;0;0m'* ]] || eq "class bg wins" "$_TUI_FRAME"
}

ti_glyph_bar_sgr_without_a_class_uses_the_fallback_plus_the_pane_background() {
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_tui_wx.bar_sgr progress "" "#112233" $'\e[2;37m'
	eq $'\e[2;37m\e[48;2;17;34;51m' "$_BSGR"
}

ti_glyph_bar_sgr_without_a_class_or_pane_background_is_the_bare_fallback() {
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_tui_wx.bar_sgr progress "" "" $'\e[2;37m'
	eq $'\e[2;37m' "$_BSGR"
}

ti_glyph_bar_sgr_with_an_unknown_colour_name_falls_back() {
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_TUI_CLASS_FG[progress]="not_a_colour"
	_tui_wx.bar_sgr progress "" "" $'\e[2;37m'
	eq $'\e[2;37m' "$_BSGR"
}

ti_glyph_bar_sgr_class_background_beats_the_pane() {
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_TUI_CLASS_BG[progress]="#ff0000"
	_tui_wx.bar_sgr progress "" "#112233" $'\e[2;37m'
	eq $'\e[48;2;255;0;0m' "$_BSGR"
}

ti_glyph_get_of_an_unknown_slot_is_empty() {
	_TUI_G=()
	TUI_GLYPH=stale
	tui.glyph.get progress nosuchkey thin
	eq "" "$TUI_GLYPH"
}

ti_glyph_progress_bar_without_any_theme_uses_built_in_glyphs_and_colours() {
	_TUI_G=() _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=() _TUI_STYLE_BG=()
	_TUI_W_LABEL[gp]="" _TUI_W_VALUE[gp]=50
	_TUI_FRAME=""
	_tui_wx.draw_progress gp 1 1 20 s nopane
	[[ "$_TUI_FRAME" == $'\e[0;32m'█*$'\e[2;37m'░*" 50%"* ]] || eq "built-in look" "$_TUI_FRAME"
}
