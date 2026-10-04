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
# requires:
_tui_canvas.glyphs() {
	case "$1" in
		double) _TC_TL="╔" _TC_TR="╗" _TC_BL="╚" _TC_BR="╝" _TC_HZ="═" _TC_VT="║" ;;
		heavy) _TC_TL="┏" _TC_TR="┓" _TC_BL="┗" _TC_BR="┛" _TC_HZ="━" _TC_VT="┃" ;;
		*) _TC_TL="┌" _TC_TR="┐" _TC_BL="└" _TC_BR="┘" _TC_HZ="─" _TC_VT="│" ;;
	esac
}

# Junction table: glyph per edge mask (N=1 E=2 S=4 W=8; a lone edge or an opposite pair
# draws the straight line, 0 is blank), masks 1..15 per style. "hdouble" is double
# horizontals over single verticals (╤ ╪), "vdouble" the reverse (╥ ╫); the box-drawing
# block has no other single/double mixes. Arrays, not string slicing: ${s:i:1} is
# byte-indexed under LC_ALL=C.
declare -gA _TC_JUNCTIONS=()
_tui_canvas.init_junctions() {
	local style row
	local -a g
	while read -r style row; do
		read -ra g <<<"$row"
		_TC_JUNCTIONS[$style]="${g[*]}"
	done <<'TABLE'
single │ ─ └ │ │ ┌ ├ ─ ┘ ─ ┴ ┐ ┤ ┬ ┼
double ║ ═ ╚ ║ ║ ╔ ╠ ═ ╝ ═ ╩ ╗ ╣ ╦ ╬
heavy ┃ ━ ┗ ┃ ┃ ┏ ┣ ━ ┛ ━ ┻ ┓ ┫ ┳ ╋
hdouble │ ═ ╘ │ │ ╒ ╞ ═ ╛ ═ ╧ ╕ ╡ ╤ ╪
vdouble ║ ─ ╙ ║ ║ ╓ ╟ ─ ╜ ─ ╨ ╖ ╢ ╥ ╫
TABLE
}
_tui_canvas.init_junctions

# _tui_canvas.junction STYLE MASK -> _TC_J; unknown STYLE falls back to "single".
_tui_canvas.junction() {
	if (($2 == 0)); then
		_TC_J=" "
		return
	fi
	local -a g
	read -ra g <<<"${_TC_JUNCTIONS[$1]:-${_TC_JUNCTIONS[single]}}"
	_TC_J="${g[$(($2 - 1))]}"
}
