# glyph_panebar.t.sh - the scrollbars of scrolling panes (vertical and horizontal) draw from the `panebar` glyph slots.

_gpb_pane() { # a 10x20 pane at 5,5 with a 6x16 content rect, scrolling both ways
	_TUI_P_ROW[gp]=5 _TUI_P_COL[gp]=5 _TUI_P_H[gp]=10 _TUI_P_W[gp]=20
	_CR_R=6 _CR_C=6 _CR_H=8 _CR_W=18
	_TUI_G=() _TUI_G_USER=() _TUI_V_DEFAULT=() _TUI_W_VARIANT=()
}

ti_panebar_slots_default_to_todays_look() {
	eq " " "${_TUI_G_DEFAULT[panebar.vthumb]}"
	eq "│" "${_TUI_G_DEFAULT[panebar.vtrack]}"
	eq " " "${_TUI_G_DEFAULT[panebar.hthumb]}"
	eq "─" "${_TUI_G_DEFAULT[panebar.htrack]}"
}

ti_panebar_vertical_default_is_a_reversed_blank_thumb_over_a_dim_line() {
	_gpb_pane
	_tui_scroll.bar_v gp 40 0 "S"
	[[ "$_SC_BAR" == *$'S\e[7m \e[0m'* ]] || eq "reversed blank thumb" "$_SC_BAR"
	[[ "$_SC_BAR" == *$'S\e[2m│\e[0m'* ]] || eq "dim │ track" "$_SC_BAR"
}

ti_panebar_vertical_uses_the_slot_glyphs_and_only_blank_thumbs_are_reversed() {
	_gpb_pane
	tui.glyph.set panebar vthumb "█"
	tui.glyph.set panebar vtrack "░"
	_tui_scroll.bar_v gp 40 0 "S"
	[[ "$_SC_BAR" == *$'S█\e[0m'* ]] || eq "plain █ thumb" "$_SC_BAR"
	[[ "$_SC_BAR" == *$'S\e[2m░\e[0m'* ]] || eq "dim ░ track" "$_SC_BAR"
	[[ "$_SC_BAR" != *$'\e[7m'* ]] || eq "no reverse video" "$_SC_BAR"
}

ti_panebar_horizontal_default_and_slots() {
	_gpb_pane
	_tui_scroll.bar_h gp 60 0 "S"
	[[ "$_SC_BAR" == *$'S\e[7m \e[0m'* ]] || eq "reversed blank thumb" "$_SC_BAR"
	[[ "$_SC_BAR" == *$'S\e[2m─\e[0m'* ]] || eq "dim ─ track" "$_SC_BAR"
	tui.glyph.set panebar hthumb "━"
	tui.glyph.set panebar htrack "·"
	_tui_scroll.bar_h gp 60 0 "S"
	[[ "$_SC_BAR" == *$'S━\e[0m'* ]] || eq "plain ━ thumb" "$_SC_BAR"
	[[ "$_SC_BAR" == *$'S\e[2m·\e[0m'* ]] || eq "dim · track" "$_SC_BAR"
}

ti_panebar_horizontal_sits_on_the_last_row_and_spans_the_content_width() {
	_gpb_pane
	_tui_scroll.bar_h gp 60 0 ""
	[[ "$_SC_BAR" == $'\e[14;6H'* ]] || eq "first cell at row 14 (pane bottom), col 6" "$_SC_BAR"
	[[ "$_SC_BAR" == *$'\e[14;23H'* ]] || eq "last cell at col 23" "$_SC_BAR"
	[[ "$_SC_BAR" != *$'\e[14;24H'* ]] || eq "nothing past the content" "$_SC_BAR"
}

ti_panebar_no_horizontal_bar_when_the_content_fits() {
	_gpb_pane
	_tui_scroll.bar_h gp 18 0 "S"
	eq "" "$_SC_BAR"
}

ti_panebar_thumb_moves_with_the_offset() {
	_gpb_pane
	_tui.glyph_v panebar hthumb "" # warm
	tui.glyph.set panebar hthumb "#"
	tui.glyph.set panebar htrack "-"
	_tui_scroll.bar_h gp 36 0 ""
	local at_start="$_SC_BAR"
	_tui_scroll.bar_h gp 36 18 ""
	[[ "$at_start" != "$_SC_BAR" ]] || eq "bar differs between offsets" "same"
	[[ "$at_start" == $'\e[14;6H#'* ]] || eq "thumb at the left edge at offset 0" "${at_start:0:20}"
}

ti_panebar_pane_variant_picks_its_design() {
	_gpb_pane
	_TUI_G[panebar.line.htrack]="="
	tui.variant gp line
	_tui_scroll.bar_h gp 60 0 "S"
	[[ "$_SC_BAR" == *$'S\e[2m=\e[0m'* ]] || eq "variant track" "$_SC_BAR"
}

ti_panebar_default_variant_applies_to_panes_without_their_own() {
	_gpb_pane
	_TUI_G[panebar.line.vtrack]="!"
	tui.variant.default panebar line
	_tui_scroll.bar_v gp 40 0 "S"
	[[ "$_SC_BAR" == *$'S\e[2m!\e[0m'* ]] || eq "default variant track" "$_SC_BAR"
	_TUI_V_DEFAULT=()
}

ti_panebar_default_theme_ships_its_variants() {
	_TUI_G=()
	_tui.theme_parse "$REPO/share/defaults/theme.css"
	_tui.theme_commit
	tui.variant.list panebar
	eq "block dot line" "${TUI_VARIANTS[*]}"
	tui.glyph.get panebar hthumb line
	eq "━" "$TUI_GLYPH"
	tui.glyph.get panebar vtrack block
	eq "░" "$TUI_GLYPH"
}

ti_panebar_catalog_offers_the_bar_list() {
	TUI_DEFAULTS_DIR="$REPO/share/defaults" _TUI_G_AVAIL=() _TUI_G_AVAIL_LOADED=0
	local a b
	tui.glyph.available panebar vthumb
	a="${TUI_GLYPHS[*]}"
	tui.glyph.available panebar htrack
	b="${TUI_GLYPHS[*]}"
	eq "$a" "$b"
	tui.glyph.available progress fill
	eq "$a" "${TUI_GLYPHS[*]}" # the same list as every other bar-like part
}

ti_panebar_border_redraw_keeps_an_output_panes_bars() {
	_gpb_pane
	_TUI_P_BORDER[gp]=single _TUI_P_SCROLL[gp]=both _TUI_P_LINES[gp]=40 _TUI_P_MAX_W[gp]=60
	_TUI_P_SOFF_V[gp]=0 _TUI_P_SOFF_H[gp]=0 _TUI_P_HPAD[gp]=0 _TUI_P_VPAD[gp]=0
	_TUI_FRAME=""
	_tui._draw_pane_border_buf gp
	[[ "$_TUI_FRAME" == *$'\e[2m│\e[0m'* ]] || eq "vertical bar after border" "$_TUI_FRAME"
	[[ "$_TUI_FRAME" == *$'\e[2m─\e[0m'* ]] || eq "horizontal bar after border" "$_TUI_FRAME"
	_TUI_FRAME=""
}
