# glyph_user.t.sh - the user's own choices (Settings page): a base-glyph override that beats the theme, and a default variant per widget type.

_gu_pane() {
	_TUI_P_ROW[p]=2 _TUI_P_COL[p]=3 _TUI_P_H[p]=10 _TUI_P_W[p]=30
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none
	_TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
	_TUI_FOCUS_ID="" _TUI_HOVERED_WIDGET=""
	_TUI_G=() _TUI_G_USER=() _TUI_V_DEFAULT=() _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
}

_gu_reset() { _TUI_G=() _TUI_G_USER=() _TUI_V_DEFAULT=() _TUI_CFG=() _TUI_G_GEN=0; } # ti_ tests are not restored between runs

_gu_draw() { _TUI_FRAME=""; _tui._draw_widget_buf "$1"; _GU_OUT="$_TUI_FRAME"; }

ti_glyph_user_applies_only_to_the_custom_design() {
	_gu_pane
	_TUI_G[progress.fill]="#" _TUI_G[progress.thin.fill]="-"
	tui.glyph.user progress fill "+"
	tui.glyph.get progress fill
	eq "#" "$TUI_GLYPH" # no design: the theme's base
	tui.glyph.get progress fill thin
	eq "-" "$TUI_GLYPH"
	tui.glyph.get progress fill custom
	eq "+" "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_custom_falls_back_to_the_theme_base_per_part() {
	_gu_pane
	_TUI_G[progress.empty]="."
	tui.glyph.user progress fill "+"
	tui.glyph.get progress empty custom
	eq "." "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_user_survives_a_theme_reset() {
	_gu_pane
	tui.glyph.user progress fill "+"
	TUI_DEFAULTS_DIR=/nonexistent _tui.theme_reset
	tui.glyph.get progress fill custom
	eq "+" "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_user_missing_or_empty_glyph_removes_the_part() {
	_gu_pane
	_TUI_G[progress.fill]="#"
	tui.glyph.user progress fill "+"
	tui.glyph.user progress fill
	tui.glyph.get progress fill custom
	eq "#" "$TUI_GLYPH"
	tui.glyph.user progress fill "+"
	tui.glyph.user progress fill ""
	tui.glyph.get progress fill custom
	eq "#" "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_user_empty_glyph_blanks_a_bracket_slot() {
	_gu_pane
	tui.glyph.user checkbox left ""
	tui.glyph.get checkbox left custom
	eq "" "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_user_space_is_a_glyph() {
	_gu_pane
	tui.glyph.user progress empty " "
	tui.glyph.get progress empty custom
	eq " " "$TUI_GLYPH"
	_gu_reset
}

ti_glyph_user_rejects_unknown_slots_and_bad_glyphs() {
	_gu_pane
	tui.glyph.user progress bogus "x" 2>/dev/null && { _gu_reset; return 1; }
	tui.glyph.user progress fill $'\e' 2>/dev/null && { _gu_reset; return 1; }
	eq 0 "${#_TUI_G_USER[@]}"
	_gu_reset
}

ti_variant_default_applies_to_widgets_without_their_own() {
	_gu_pane
	_TUI_G[progress.thin.fill]="=" _TUI_G[progress.dots.fill]="o"
	tui.progress gp p 0 ""
	tui.set gp 50
	tui.variant.default progress thin
	_gu_draw gp
	match "$_GU_OUT" '=+'
	tui.variant.default progress custom
	tui.glyph.user progress fill "~"
	_gu_draw gp
	match "$_GU_OUT" '~+'
	tui.variant gp dots # the widget's own variant wins
	_gu_draw gp
	match "$_GU_OUT" 'o+'
	_gu_reset
}

ti_variant_default_clears_with_an_empty_name() {
	_gu_pane
	tui.variant.default progress thin
	tui.variant.default progress ""
	eq "" "${_TUI_V_DEFAULT[progress]-}"
	_gu_reset
}

ti_variant_default_redraws_a_cached_checkbox() {
	_gu_pane
	_TUI_G[checkbox.round.on]="●"
	tui.checkbox gc p 0 "Opt" 1
	_gu_draw gc
	tui.variant.default checkbox round
	_gu_draw gc
	match "$_GU_OUT" '●'
	_gu_reset
}

ti_variant_list_names_the_variants_a_theme_defines_for_a_type() {
	_gu_pane
	_tui.theme_parse "$REPO/share/defaults/theme.css"
	_tui.theme_commit
	tui.variant.list progress
	eq "ascii dots squares thin" "${TUI_VARIANTS[*]}"
	tui.variant.list scrollbar
	eq "block dot thin" "${TUI_VARIANTS[*]}"
	tui.variant.list nosuchtype
	eq 0 "${#TUI_VARIANTS[@]}"
	_gu_reset
}

ti_config_apply_restores_glyph_and_variant_choices() {
	_gu_pane
	_TUI_CFG[glyph.progress.fill]="+" _TUI_CFG[variant.progress]="thin"
	tui.config.apply
	eq "+" "${_TUI_G_USER[progress.fill]}"
	eq thin "${_TUI_V_DEFAULT[progress]}"
	_gu_reset
}
