#!/usr/bin/env bash
# tui_canvas.sh - line canvas: the single glyph table for every border style
# (markup-v2 stage 2B). Was duplicated verbatim in _tui._draw_pane_buf and
# _tui._draw_pane_border_buf (lib/tui.sh) - one `case "$border" in ...`
# each, always kept in sync by hand. This is that one place.
#
# _tui_canvas.glyphs STYLE -> sets _TC_TL/_TC_TR/_TC_BL/_TC_BR (corners),
# _TC_HZ/_TC_VT (edges) for STYLE ("single"/"double"/"heavy"; anything else,
# including empty, falls back to "single" - the callers' own `*)` default).
# Fork-free (a case statement, no command substitution), same convention as
# every other hot-render-path helper in this file.
_tui_canvas.glyphs() {
	case "$1" in
		double) _TC_TL="╔" _TC_TR="╗" _TC_BL="╚" _TC_BR="╝" _TC_HZ="═" _TC_VT="║" ;;
		heavy) _TC_TL="┏" _TC_TR="┓" _TC_BL="┗" _TC_BR="┛" _TC_HZ="━" _TC_VT="┃" ;;
		*) _TC_TL="┌" _TC_TR="┐" _TC_BL="└" _TC_BR="┘" _TC_HZ="─" _TC_VT="│" ;;
	esac
}
