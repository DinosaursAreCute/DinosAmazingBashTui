# canvas.t.sh - lib/render/tui_canvas.sh line canvas / border glyph table (stage 2B).

t_canvas_glyphs_single_is_the_default() {
	_tui_canvas.glyphs single
	eq "┌" "$_TC_TL"
	eq "┐" "$_TC_TR"
	eq "└" "$_TC_BL"
	eq "┘" "$_TC_BR"
	eq "─" "$_TC_HZ"
	eq "│" "$_TC_VT"
}

t_canvas_glyphs_unknown_style_falls_back_to_single() {
	_tui_canvas.glyphs bogus
	eq "┌" "$_TC_TL"
	eq "─" "$_TC_HZ"
}

t_canvas_glyphs_double() {
	_tui_canvas.glyphs double
	eq "╔" "$_TC_TL"
	eq "╗" "$_TC_TR"
	eq "╚" "$_TC_BL"
	eq "╝" "$_TC_BR"
	eq "═" "$_TC_HZ"
	eq "║" "$_TC_VT"
}

t_canvas_glyphs_heavy() {
	_tui_canvas.glyphs heavy
	eq "┏" "$_TC_TL"
	eq "┓" "$_TC_TR"
	eq "┗" "$_TC_BL"
	eq "┛" "$_TC_BR"
	eq "━" "$_TC_HZ"
	eq "┃" "$_TC_VT"
}

# edge masks: N=1 E=2 S=4 W=8
t_canvas_junction_single_pieces() {
	_tui_canvas.junction single 7
	eq "├" "$_TC_J"
	_tui_canvas.junction single 13
	eq "┤" "$_TC_J"
	_tui_canvas.junction single 14
	eq "┬" "$_TC_J"
	_tui_canvas.junction single 11
	eq "┴" "$_TC_J"
	_tui_canvas.junction single 15
	eq "┼" "$_TC_J"
	_tui_canvas.junction single 6
	eq "┌" "$_TC_J"
}

t_canvas_junction_double_and_heavy() {
	_tui_canvas.junction double 7
	eq "╠" "$_TC_J"
	_tui_canvas.junction double 15
	eq "╬" "$_TC_J"
	_tui_canvas.junction heavy 14
	eq "┳" "$_TC_J"
	_tui_canvas.junction heavy 15
	eq "╋" "$_TC_J"
}

t_canvas_junction_mixed_single_double() {
	_tui_canvas.junction hdouble 15
	eq "╪" "$_TC_J"
	_tui_canvas.junction hdouble 7
	eq "╞" "$_TC_J"
	_tui_canvas.junction vdouble 15
	eq "╫" "$_TC_J"
	_tui_canvas.junction vdouble 13
	eq "╢" "$_TC_J"
}

t_canvas_junction_straights_match_the_edge_glyphs() {
	local s
	for s in single double heavy; do
		_tui_canvas.glyphs "$s"
		_tui_canvas.junction "$s" 10
		eq "$_TC_HZ" "$_TC_J"
		_tui_canvas.junction "$s" 5
		eq "$_TC_VT" "$_TC_J"
	done
}

t_canvas_junction_corners_match_the_corner_glyphs() {
	local s
	for s in single double heavy; do
		_tui_canvas.glyphs "$s"
		_tui_canvas.junction "$s" 6
		eq "$_TC_TL" "$_TC_J"
		_tui_canvas.junction "$s" 12
		eq "$_TC_TR" "$_TC_J"
		_tui_canvas.junction "$s" 3
		eq "$_TC_BL" "$_TC_J"
		_tui_canvas.junction "$s" 9
		eq "$_TC_BR" "$_TC_J"
	done
}

t_canvas_junction_unknown_style_is_single_and_empty_mask_blank() {
	_tui_canvas.junction bogus 15
	eq "┼" "$_TC_J"
	_tui_canvas.junction single 0
	eq " " "$_TC_J"
}

t_canvas_register_adds_a_border_style() {
	tui.border.register notch ┌ ┐ └ ┘ ─ │ ┐ ┌
	_tui_canvas.glyphs notch
	eq "┌" "$_TC_TL"
	eq "│" "$_TC_VT"
	eq "┐" "$_TC_CAP_L"
	eq "┌" "$_TC_CAP_R"
}

t_canvas_builtin_styles_cap_titles_with_spaces() {
	tui.border.register notch ┌ ┐ └ ┘ ─ │ ┐ ┌
	_tui_canvas.glyphs notch
	_tui_canvas.glyphs heavy
	eq " " "$_TC_CAP_L"
	eq " " "$_TC_CAP_R"
}

t_canvas_register_without_caps_uses_spaces() {
	tui.border.register plain ╭ ╮ ╰ ╯ ─ │
	_tui_canvas.glyphs plain
	eq "╭" "$_TC_TL"
	eq " " "$_TC_CAP_L"
	eq " " "$_TC_CAP_R"
}

t_canvas_register_needs_seven_glyphs() {
	! tui.border.register short ┌ ┐ └
	eq "" "${_TC_CUSTOM[short]:-}"
}

t_canvas_register_extends_the_border_validator_once() {
	tui.border.register notch ┌ ┐ └ ┘ ─ │
	tui.border.register notch ┌ ┐ └ ┘ ─ │
	match "${_TV_ENUM[pane.border]}" '(^|\|)notch(\||$)'
	eq 1 "$(grep -o 'notch' <<<"${_TV_ENUM[pane.border]}" | wc -l)"
	match "${_TV_ENUM[pane.divider]}" 'notch'
}
