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
declare -gA _TC_CUSTOM=()              # NAME -> "TL US TR US ... CAP_R", US = 0x1f (tui.border.register)
declare -g _TC_CAP_L=" " _TC_CAP_R=" " # the glyphs either side of a pane title; a space for the built-in styles

# tui.border.register NAME TL TR BL BR HZ VT [CAP_L CAP_R] - adds a border style usable as border="NAME" (and divider="NAME").
# CAP_L / CAP_R replace the spaces around a pane title, e.g. "┤" and "├" for btop's  ┤ cpu ├  look. Each argument is one cell.
# Junctions of a registered style are drawn as "single".
tui.border.register() {
	(($# >= 7)) || return 1
	local us=$'\x1f'
	_TC_CUSTOM[$1]="$2$us$3$us$4$us$5$us$6$us$7$us${8:- }$us${9:- }"
	local k
	for k in pane.border pane.divider; do
		[[ "|${_TV_ENUM[$k]:-}|" == *"|$1|"* ]] || _TV_ENUM[$k]="${_TV_ENUM[$k]:+${_TV_ENUM[$k]}|}$1"
	done
}

_tui_canvas.glyphs() {
	_TC_CAP_L=" " _TC_CAP_R=" "
	if [[ -n "${_TC_CUSTOM[$1]:-}" ]]; then
		IFS=$'\x1f' read -r _TC_TL _TC_TR _TC_BL _TC_BR _TC_HZ _TC_VT _TC_CAP_L _TC_CAP_R <<<"${_TC_CUSTOM[$1]}"
		return
	fi
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
