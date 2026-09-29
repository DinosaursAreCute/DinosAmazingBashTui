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
