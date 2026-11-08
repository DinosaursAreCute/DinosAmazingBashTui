# glyph_widgets.t.sh - widgets draw their glyphs from theme slots, per-widget `variant=` picks a design.

_gw_pane() {
	_TUI_P_ROW[p]=2 _TUI_P_COL[p]=3 _TUI_P_H[p]=10 _TUI_P_W[p]=30
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none
	_TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
	_TUI_FOCUS_ID="" _TUI_HOVERED_WIDGET=""
	_TUI_G=() _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
}

_gw_draw() { # ID -> bytes in _GW_OUT
	_TUI_FRAME=""
	_tui._draw_widget_buf "$1"
	_GW_OUT="$_TUI_FRAME"
}

ti_variant_setter_stores_the_name_per_widget() {
	tui.variant gv1 thin
	tui.variant gv2 dots
	eq thin "${_TUI_W_VARIANT[gv1]}"
	eq dots "${_TUI_W_VARIANT[gv2]}"
	tui.variant gv1 ""
	eq "" "${_TUI_W_VARIANT[gv1]-}"
}

ti_glyph_get_has_defaults_for_every_widget_slot() {
	local slot
	for slot in checkbox.left checkbox.on checkbox.off checkbox.right select.left select.arrow select.right scrollbar.thumb scrollbar.track; do
		ok '[[ -n "${_TUI_G_DEFAULT[$slot]+x}" ]]'
	done
	eq "▐" "${_TUI_G_DEFAULT[scrollbar.thumb]}"
	eq "▾" "${_TUI_G_DEFAULT[select.arrow]}"
}

ti_glyph_empty_is_allowed_for_bracket_slots_only() {
	_TUI_G=()
	ok 'tui.glyph.set checkbox left ""'
	ok 'tui.glyph.set select right ""'
	tui.glyph.set progress fill "" 2>/dev/null && return 1
	tui.glyph.set checkbox on "" 2>/dev/null && return 1
	return 0
}

ti_checkbox_draws_default_brackets() {
	_gw_pane
	tui.checkbox gc p 0 "Opt" 0
	_gw_draw gc
	match "$_GW_OUT" '\[ \] Opt'
	tui.checkbox gc2 p 1 "Opt" 1
	_gw_draw gc2
	match "$_GW_OUT" '\[x\] Opt'
}

ti_checkbox_draws_slots_without_brackets() {
	_gw_pane
	tui.glyph.set checkbox left ""
	tui.glyph.set checkbox right ""
	tui.glyph.set checkbox on "✔"
	tui.glyph.set checkbox off "·"
	tui.checkbox gc p 0 "Opt" 1
	_gw_draw gc
	match "$_GW_OUT" '✔ Opt'
}

ti_checkbox_variant_overrides_only_its_slots() {
	_gw_pane
	tui.glyph.set checkbox on "●" round
	tui.glyph.set checkbox off "○" round
	tui.checkbox gc p 0 "Opt" 1
	tui.variant gc round
	_gw_draw gc
	match "$_GW_OUT" '\[●\] Opt' # left and right come from the base
}

ti_checkbox_redraws_with_new_glyphs_after_tui_glyph_set() {
	_gw_pane
	tui.checkbox gc p 0 "Opt" 1
	_gw_draw gc # primes the row cache
	tui.glyph.set checkbox on "#"
	_gw_draw gc
	match "$_GW_OUT" '\[#\] Opt'
}

ti_select_draws_default_and_themed_frame() {
	_gw_pane
	tui.select gs p 0 "Mode:" ""
	tui.set gs fast
	_gw_draw gs
	match "$_GW_OUT" '\[ fast ▾ \]'
	tui.glyph.set select arrow "v"
	tui.glyph.set select left "<"
	tui.glyph.set select right ">"
	_gw_draw gs
	match "$_GW_OUT" '< fast v >'
}

ti_progress_variant_uses_its_glyphs_and_falls_back_per_slot() {
	_gw_pane
	tui.progress gp p 0 ""
	tui.set gp 50
	tui.glyph.set progress fill "=" thin # no `empty` for thin: the base's default shows
	tui.variant gp thin
	_gw_draw gp
	match "$_GW_OUT" '=+'
	match "$_GW_OUT" '░+'
}

ti_progress_variant_colours_override_per_field() {
	_gw_pane
	_TUI_CLASS_FG[progress_fill]="#010101" _TUI_CLASS_FG["progress_fill.thin"]="#020202"
	tui.progress gp p 0 ""
	tui.set gp 50
	_gw_draw gp
	match "$_GW_OUT" '38;2;1;1;1'
	tui.variant gp thin
	_gw_draw gp
	match "$_GW_OUT" '38;2;2;2;2'
}

ti_scroll_cell_draws_thumb_and_track_from_slots() {
	_gw_pane
	_TUI_FRAME=""
	_tui_wx.scroll_cell gl 1
	eq "▐" "$_TUI_FRAME"
	_TUI_FRAME=""
	_tui_wx.scroll_cell gl 0
	eq " " "$_TUI_FRAME"
	tui.glyph.set scrollbar thumb "#"
	tui.glyph.set scrollbar track "|"
	tui.glyph.set scrollbar thumb "O" fancy
	tui.variant gl fancy
	_TUI_FRAME=""
	_tui_wx.scroll_cell gl 1
	eq "O" "$_TUI_FRAME"
	_TUI_FRAME=""
	_tui_wx.scroll_cell gl 0
	eq "|" "$_TUI_FRAME"
}

ti_markup_variant_attribute_sets_the_widget_variant() {
	_t_needs_caches || return 0
	printf '%s' '<tui><pane id="root" split="v"><progress id="gvp" variant="thin" value="10"/><checkbox id="gvc" label="x" variant="round"/></pane></tui>' >"$_T_ROOT/gv.xml"
	tui.reset_ui
	tui.cache.record "$_T_ROOT/gv.xml"
	eq thin "${_TUI_W_VARIANT[gvp]:-}"
	eq round "${_TUI_W_VARIANT[gvc]:-}"
}

ti_default_theme_ships_the_built_in_variants() {
	_TUI_G=()
	_tui.theme_parse "$REPO/share/defaults/theme.css"
	_tui.theme_commit
	local spec t k v want
	for spec in progress:thin:fill:━ progress:dots:fill:● progress:ascii:empty:- progress:squares:fill:■ checkbox:round:left:'(' checkbox:plain:on:✔ select:plain:arrow:▾ scrollbar:thin:thumb:┃ scrollbar:dot:track:·; do
		IFS=: read -r t v k want <<<"$spec"
		tui.glyph.get "$t" "$k" "$v"
		eq "$want" "$TUI_GLYPH"
	done
}

ti_every_shipped_variant_slot_is_a_known_slot() {
	_TUI_G=()
	_tui.theme_parse "$REPO/share/defaults/glyphs/variants.css"
	local n=${#_TP_G[@]} slot bad=""
	for slot in "${!_TP_G[@]}"; do
		IFS=. read -r t v k <<<"$slot"
		[[ -n "${_TUI_G_DEFAULT[$t.$k]+x}" ]] || bad+="$slot "
	done
	eq "" "$bad"
	ok '((n > 20))'
}
