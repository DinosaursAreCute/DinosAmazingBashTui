#!/usr/bin/env bash
# tui_frame.sh - fused panes and pane titles.
#
#   fuse="true"      on every child of a split: siblings overlap by one cell so they share ONE border line
#                    (tui_layout's seam: _tui._layout_r asks _tui_frame.fused and uses a gap of -1). A split
#                    only fuses when ALL its children are fuse panes and it has no gap of its own.
#   divider=STYLE    border style of the shared line (single|double|heavy), default: the pane's own border.
#   divider_class=C  theme class (.C) the shared line is coloured with, default: the pane's border colour.
#   title_pos=top|bottom, title_align=left|center|right   where the title sits on the border.
#
# Fused boxes each still draw their full border; _tui_frame.junctions then redraws every cell that two or more
# fused boxes share, with the glyph for the lines meeting there (junction table: lib/render/tui_canvas.sh).
# requires:

declare -gA _TUI_P_FUSE=() _TUI_P_DIVIDER=() _TUI_P_DIVIDER_CLASS=() _TUI_P_TITLE_POS=() _TUI_P_TITLE_ALIGN=()

# tui.pane_fuse ID BOOL - true|false (anything else is ignored with a warning).
tui.pane_fuse() {
	[[ "$2" == @(true|false) ]] || {
		tui.log.warn "tui.pane_fuse: '$2' is not true|false" 2>/dev/null
		return 1
	}
	if [[ "$2" == true ]]; then _TUI_P_FUSE[$1]=true; else unset '_TUI_P_FUSE[$1]'; fi
	_tui.epoch_bump layout # fusing moves every sibling's rect
}

# tui.pane_divider ID STYLE - border style of the line ID shares with its fused neighbour (empty: the pane's border).
tui.pane_divider() { _TUI_P_DIVIDER[$1]="$2"; }

# tui.pane_divider_class ID CLASS - theme class the shared line is drawn with (empty: the pane's border colour).
tui.pane_divider_class() { _TUI_P_DIVIDER_CLASS[$1]="$2"; }

# tui.pane_title_pos ID POS - top|bottom: which border line carries the title.
tui.pane_title_pos() {
	[[ "$2" == @(top|bottom) ]] || {
		tui.log.warn "tui.pane_title_pos: '$2' is not top|bottom" 2>/dev/null
		return 1
	}
	_ps.panes.set "$1" title_pos "$2"
}

# tui.pane_title_align ID ALIGN - left|center|right: where along the border line the title sits.
tui.pane_title_align() {
	[[ "$2" == @(left|center|right) ]] || {
		tui.log.warn "tui.pane_title_align: '$2' is not left|center|right" 2>/dev/null
		return 1
	}
	_ps.panes.set "$1" title_align "$2"
}

# _tui_frame.build ID FUSE DIVIDER DIVIDER_CLASS TITLE_POS TITLE_ALIGN - the markup build step: empty values are skipped.
_tui_frame.build() {
	[[ -n "$2" ]] && tui.pane_fuse "$1" "$2"
	[[ -n "$3" ]] && tui.pane_divider "$1" "$3"
	[[ -n "$4" ]] && tui.pane_divider_class "$1" "$4"
	[[ -n "$5" ]] && tui.pane_title_pos "$1" "$5"
	[[ -n "$6" ]] && tui.pane_title_align "$1" "$6"
	return 0
}

# _tui_frame.fused PARENT - true when PARENT is a split whose children are all fuse panes and which has no gap.
_tui_frame.fused() {
	local p="$1" c
	[[ "${_TUI_P_DIR[$p]:-}" == @(h|v) && "${_TUI_P_GAP[$p]:-0}" == 0 ]] || return 1
	local -a ch
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]:-}"
	((${#ch[@]} > 1)) || return 1
	for c in "${ch[@]}"; do [[ "${_TUI_P_FUSE[$c]:-}" == true ]] || return 1; done
}

# _tui_frame.edge ID WHICH LC RC HZ INNER TITLE RING_KEY TITLE_FB - appends one border line (top|bottom) with the
# ring colour, the corners LC/RC, HZ runs and, when ID's title_pos is WHICH, the title tag placed by title_align.
# The caller has already moved the cursor to the line's first cell.
# _tui_frame.title_parse TITLE -> _TT_PLAIN _TT_ACC: a "^" marks the next character as an accent (a hotkey): "^1cpu" is "1cpu"
# with index 0 accented. "^^" is a literal caret; a caret at the end is kept. _TT_ACC lists the indices, each led by a space.
_tui_frame.title_parse() {
	_TT_PLAIN="$1" _TT_ACC=""
	[[ "$1" == *'^'* ]] || return 0
	local t="$1" out="" i c n=${#1}
	for ((i = 0; i < n; i++)); do
		c="${t:i:1}"
		if [[ "$c" == '^' ]] && ((i + 1 < n)); then
			i=$((i + 1))
			c="${t:i:1}"
			[[ "$c" != '^' ]] && _TT_ACC+=" ${#out}"
		fi
		out+="$c"
	done
	_TT_PLAIN="$out"
}

# _tui_frame.title_accented ID TFB TITLE ACC CAP_L CAP_R - the title tag with its accent characters in the title_key class
# (bold red without a theme rule), the rest in the pane's title style
_tui_frame.title_accented() {
	local id="$1" tfb="$2" title="$3" acc="$4" pos=0 idx
	_tui.emit "$5"
	for idx in $acc; do
		((idx >= ${#title})) && break
		_tui.emit "${title:pos:idx-pos}"
		tui.class.sgr title_key
		_tui.emit "${TUI_SGR:-$'\e[1;31m'}"
		_tui.emit "${title:idx:1}"
		_tui.emit_reset
		_tui.emit_style "${id}_title" "$tfb" "${id}_normal"
		pos=$((idx + 1))
	done
	_tui.emit "${title:pos}"
	_tui.emit "$6"
}

_tui_frame.edge() {
	local id="$1" which="$2" lc="$3" rc="$4" hz="$5" inner="$6" title="$7" key="$8" tfb="$9" acc=""
	_tui.emit_ring "$key" "${id}_border" "$id"
	if [[ -z "$title" || "${_TUI_P_TITLE_POS[$id]:-top}" != "$which" ]]; then
		_tui.emit "$lc"
		_tui.emit_repeat "$hz" "$inner"
		_tui.emit "$rc"
		_tui.emit_reset
		return
	fi
	_tui_frame.title_parse "$title"
	title="$_TT_PLAIN" acc="$_TT_ACC"
	local max_t=$((inner - 4))
	((max_t < 1)) && max_t=1
	((${#title} > max_t)) && title="${title:0:$max_t}"
	_tui._eff_border "$id"
	_tui_canvas.glyphs "$_TB"
	local tag="${_TC_CAP_L}${title}${_TC_CAP_R}"
	local rest=$((inner - ${#tag})) left right
	((rest < 0)) && rest=0
	case "${_TUI_P_TITLE_ALIGN[$id]:-left}" in
		right) left=$((rest - 1)) right=1 ;;
		center) left=$((rest / 2)) right=$((rest - rest / 2)) ;;
		*) left=1 right=$((rest - 1)) ;;
	esac
	((left < 0)) && left=0
	((right < 0)) && right=0
	if [[ "${_TUI_P_TITLE_ALIGN[$id]:-left}" == left ]]; then
		# historic: the literal single-line dash for the built-in styles, so their titles stay byte-identical; a registered style
		# leads in with its own edge glyph
		if [[ -n "${_TC_CUSTOM[$_TB]:-}" ]]; then _tui.emit "${lc}${hz}"; else _tui.emit "${lc}─"; fi
	else
		_tui.emit "$lc"
		_tui.emit_repeat "$hz" "$left"
	fi
	_tui.emit_reset
	_tui.emit_style "${id}_title" "$tfb" "${id}_normal"
	if [[ -z "$acc" ]]; then _tui.emit "$tag"; else _tui_frame.title_accented "$id" "$tfb" "$title" "$acc" "$_TC_CAP_L" "$_TC_CAP_R"; fi
	_tui.emit_reset
	_tui.emit_ring "$key" "${id}_border" "$id"
	_tui.emit_repeat "$hz" "$right"
	_tui.emit "$rc"
	_tui.emit_reset
}

# _tui_frame.title_span ID -> _TS0 _TS1: the first and last screen column of ID's title tag (" Title ") on its title
# line, as _tui_frame.edge places it; rc 1 when ID has no title or no border.
_tui_frame.title_span() {
	local id="$1" title="${_TUI_P_TITLE[$1]:-}" inner max_t rest left
	[[ -n "$title" ]] || return 1
	_tui_frame.title_parse "$title"
	title="$_TT_PLAIN"
	_tui._eff_border "$id"
	[[ "$_TB" == none ]] && return 1
	inner=$((${_TUI_P_W[$id]} - 2))
	max_t=$((inner - 4))
	((max_t < 1)) && max_t=1
	((${#title} > max_t)) && title="${title:0:$max_t}"
	rest=$((inner - ${#title} - 2))
	((rest < 0)) && rest=0
	case "${_TUI_P_TITLE_ALIGN[$id]:-left}" in
		right) left=$((rest - 1)) ;;
		center) left=$((rest / 2)) ;;
		*) left=1 ;;
	esac
	((left < 0)) && left=0
	_TS0=$((${_TUI_P_COL[$id]} + 1 + left))
	_TS1=$((_TS0 + ${#title} + 1))
}

# _tui_frame.junctions - redraws every cell shared by two or more fused boxes with the glyph for the lines
# meeting there. Appends to _TUI_FRAME; a no-op (one test) on a page without fused panes.
# state:direct
_tui_frame.junctions() {
	((${#_TUI_P_FUSE[@]})) || return 0
	local -A mask=() cnt=() hst=() vst=() dvd=() last=()
	local p r c h w b st ov x y k
	for p in "${_TUI_P_ALL[@]}"; do
		[[ "${_TUI_P_FUSE[$p]:-}" == true ]] || continue
		_tui._eff_border "$p"
		[[ "$_TB" == none ]] && continue
		r=${_TUI_P_ROW[$p]} c=${_TUI_P_COL[$p]} h=${_TUI_P_H[$p]} w=${_TUI_P_W[$p]}
		b=$_TB ov="${_TUI_P_DIVIDER[$p]:-}"
		for ((x = c; x < c + w; x++)); do
			for y in "$r" $((r + h - 1)); do
				k="$y,$x"
				((mask[$k] |= (x < c + w - 1 ? 2 : 0) | (x > c ? 8 : 0)))
				[[ "${last[$k]:-}" == "$p" ]] || {
					((cnt[$k]++))
					last[$k]=$p
				}
				hst[$k]=$b dvd[$k]=$ov
			done
		done
		for ((y = r; y < r + h; y++)); do
			for x in "$c" $((c + w - 1)); do
				k="$y,$x"
				((mask[$k] |= (y < r + h - 1 ? 4 : 0) | (y > r ? 1 : 0)))
				[[ "${last[$k]:-}" == "$p" ]] || {
					((cnt[$k]++))
					last[$k]=$p
				}
				vst[$k]=$b dvd[$k]=$ov
			done
		done
	done
	local hs vs cls fg bg mods
	for k in "${!cnt[@]}"; do
		((cnt[$k] > 1)) || continue
		hs="${hst[$k]:-}" vs="${vst[$k]:-}"
		if [[ -n "${dvd[$k]}" ]]; then
			st="${dvd[$k]}"
		elif [[ -z "$hs" || "$hs" == "$vs" ]]; then
			st="$vs"
		elif [[ -z "$vs" ]]; then
			st="$hs"
		elif [[ "$hs" == double && "$vs" == single ]]; then
			st=hdouble
		elif [[ "$vs" == double && "$hs" == single ]]; then
			st=vdouble
		else st="$vs"; fi
		_tui_canvas.junction "$st" "${mask[$k]}"
		p="${last[$k]}"
		_tui.emit_goto "${k%,*}" "${k#*,}"
		cls="${_TUI_P_DIVIDER_CLASS[$p]:-}"
		if [[ -n "$cls" ]] && _tui._sgr_from "${_TUI_CLASS_FG[$cls]:-}" "${_TUI_CLASS_BG[$cls]:-${_TUI_STYLE_BG[${p}_border]:-}}" "${_TUI_CLASS_MOD[$cls]:-}"; then
			_tui.emit "$_SGR"
		else
			_tui.emit_ring "${p}_border" "${p}_border" "$p"
		fi
		_tui.emit "$_TC_J"
		_tui.emit_reset
	done
	_tui_frame.shared_titles mask cnt
}

# _tui_frame.shared_titles MASK CNT - the title tags the junction pass just wiped: a fused box whose title line is
# shared with a neighbour (the lower pane's top row, the upper pane's bottom row) draws its tag again over the plain
# horizontal cells (mask 2|8) of that line. It stops at the first junction cell, so the tag is cut to fit, and a tag
# that would land on an earlier pane's tag moves to the right of it. MASK / CNT are the pass's cell tables (by name).
# state:direct
_tui_frame.shared_titles() {
	local -n _m="$1" _n="$2"
	local -A end=()
	local p r c h w y x0 x run title tag inner rest left max_t al
	for p in "${_TUI_P_ALL[@]}"; do
		[[ "${_TUI_P_FUSE[$p]:-}" == true && -n "${_TUI_P_TITLE[$p]:-}" ]] || continue
		_tui._eff_border "$p"
		[[ "$_TB" == none ]] && continue
		r=${_TUI_P_ROW[$p]} c=${_TUI_P_COL[$p]} h=${_TUI_P_H[$p]} w=${_TUI_P_W[$p]}
		[[ "${_TUI_P_TITLE_POS[$p]:-top}" == bottom ]] && y=$((r + h - 1)) || y=$r
		_ps.panes.get "$p" title
		title=$_V
		inner=$((w - 2))
		max_t=$((inner - 4))
		((max_t < 1)) && max_t=1
		((${#title} > max_t)) && title="${title:0:$max_t}"
		tag=" ${title} "
		rest=$((inner - ${#tag}))
		((rest < 0)) && rest=0
		al="${_TUI_P_TITLE_ALIGN[$p]:-left}"
		case "$al" in
			right) left=$((rest - 1)) ;;
			center) left=$((rest / 2)) ;;
			*) left=1 ;;
		esac
		((left < 0)) && left=0
		x=$((c + 1 + left))
		((x <= ${end[$y]:-0})) && x=$((${end[$y]} + 2)) # right of the tag already on this line
		for ((run = 0; run < ${#tag} && x + run < c + w - 1; run++)); do
			[[ "${_m[$y,$((x + run))]:-}" == 10 ]] && ((${_n[$y,$((x + run))]:-0} > 1)) || break
		done
		((run > 0)) || continue
		end[$y]=$((x + run - 1))
		_tui.emit_goto "$y" "$x"
		_tui.emit_style "${p}_title" "" "${p}_normal"
		_tui.emit "${tag:0:run}"
		_tui.emit_reset
	done
}
