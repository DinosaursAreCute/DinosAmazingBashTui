#!/usr/bin/env bash
# tui_hit.sh - the hit index: every interaction zone on screen, looked up by (row, col) without a scan over widgets.
#
# Zones are rectangles with a kind: scrollbar, title (built from the layout), divider, handle, chevron (registered by
# the features that draw them, see _tui_hit.extra_add) - all ranked ahead of widgets,
# widget (a widget's exact rect), hitbox (its extra hit area: hit_pad / hitbox), pane (a leaf pane, the fallback).
# Each screen row keeps the indices of the zones crossing it, highest priority first, so a lookup walks only the
# zones of one row: its cost does not grow with the number of widgets on the page.
#
#   _tui_hit.at COL ROW          resolve the topmost zone -> _HIT_KIND _HIT_ID _HIT_ARG, the leaf pane -> _HIT_PANE,
#                                the widget under the pointer -> _HIT (kinds widget/hitbox only);
#                                rc 0 if any zone above the pane fallback was hit, rc 1 if only the pane (or nothing)
#   _tui_hit.rebuild             rebuild the index from the current layout (tui.render and the first lookup after a
#                                layout do it; _TUI_HZ_DIRTY marks it stale)
#   _tui_hit.extra_add KIND ID ARG ROW COL H W   register a divider/handle/chevron/title zone (kept across rebuilds)
#   tui.hit.set ID hit_pad|hitbox VALUE          per-widget hit area
#   _tui_hit.hover               after _tui_hit.at: tracks the hovered resize handle / divider / collapse button zone in
#                                _TUI_HZ_HOVER ("PANE|ARG", kept while a resize drag runs) and repaints just that segment
#   _tui_hit.overlay [PANE]      appends the collapse button(s) and the hovered segment; runs after _tui_frame.junctions
#
# Scrollbars: the bar is drawn 1 cell wide, its zone is 3 columns wide (the bar +-1, clamped to the pane); the
# horizontal bar's zone is 3 rows high. The vertical zone wins the shared corner.

declare -gA _TUI_W_HITPAD=() _TUI_W_HITBOX=() # id -> "N" or "V H" cells; id -> "dy dx h w" relative to the widget origin
declare -ga _TUI_HZ_C0=() _TUI_HZ_C1=()
declare -ga _TUI_HZ_KIND=() _TUI_HZ_ID=() _TUI_HZ_ARG=()
declare -ga _TUI_HZ_ROW=()   # screen row -> "i j k": zone indices, highest priority first
declare -ga _TUI_HZ_EXTRA=() # registered extra zones, _TUI_HZ_EXTRA_FIELDS fields each: KIND ID ARG ROW COL H W
declare -gi _TUI_HZ_EXTRA_FIELDS=7
declare -g _TUI_HZ_N=0 _TUI_HZ_DIRTY=1
declare -gA _TUI_HZ_WR=() _TUI_HZ_WC=() _TUI_HZ_WW=() # widget id -> unclipped row / col / width (read by tui.action.focus_dir); labels without a hit area are absent
declare -g _TUI_HZ_HOVER=""                           # "PANE|ARG" of the hovered rz-* / cv-* zone, "" when none
declare -g _HIT="" _HIT_KIND="" _HIT_ID="" _HIT_ARG="" _HIT_PANE=""
declare -g _HR=0 _HC=0 _HH=0 _HW=0 # _tui_hit.clip result

# _tui_hit.add KIND ID ARG ROW COL H W - append a zone to every screen row it crosses
_tui_hit.add() {
	local kind=$1 id=$2 arg=$3 row=$4 col=$5 h=$6 w=$7 i=$_TUI_HZ_N last
	last=$((row + h - 1))
	((row < 0)) && row=0
	((last > _TUI_ROWS)) && last=$_TUI_ROWS
	((h < 1 || w < 1 || row > last)) && return 0
	_TUI_HZ_KIND[i]=$kind _TUI_HZ_ID[i]=$id _TUI_HZ_ARG[i]=$arg _TUI_HZ_C0[i]=$col _TUI_HZ_C1[i]=$((col + w - 1))
	_TUI_HZ_N=$((i + 1))
	for (( ; row <= last; row++)); do _TUI_HZ_ROW[row]+="${_TUI_HZ_ROW[row]:+ }$i"; done
}

# _tui_hit.extra_add KIND ID ARG ROW COL H W - a divider/handle/chevron zone a feature draws (kept across rebuilds,
# ranked with the scrollbars); rc 1 for a kind this index does not know
_tui_hit.extra_add() {
	case "$1" in
		divider | handle | chevron | title) ;;
		*) return 1 ;;
	esac
	_TUI_HZ_EXTRA+=("$1" "$2" "$3" "$4" "$5" "$6" "$7")
	_TUI_HZ_DIRTY=1
}

# _tui_hit.extra_clear - clears the registered extra zones (divider, handle, chevron, title).
_tui_hit.extra_clear() {
	_TUI_HZ_EXTRA=()
	_TUI_HZ_DIRTY=1
}

# _tui_hit.clip ROW COL H W PANE - intersect a rect with PANE's rect -> _HR _HC _HH _HW (_HH/_HW 0 if disjoint)
_tui_hit.clip() {
	local r0=$1 c0=$2 r1=$(($1 + $3)) c1=$(($2 + $4)) pane=$5
	local pr=${_TUI_P_ROW[$pane]} pc=${_TUI_P_COL[$pane]}
	((r0 < pr)) && r0=$pr
	((c0 < pc)) && c0=$pc
	((r1 > pr + ${_TUI_P_H[$pane]})) && r1=$((pr + ${_TUI_P_H[$pane]}))
	((c1 > pc + ${_TUI_P_W[$pane]})) && c1=$((pc + ${_TUI_P_W[$pane]}))
	_HR=$r0 _HC=$c0 _HH=$((r1 - r0)) _HW=$((c1 - c0))
	((_HH < 0)) && _HH=0
	((_HW < 0)) && _HW=0
	return 0
}

# _tui_hit.clip_content ROW COL H W PANE - for scrolling panes, clip to content rect
# (inside border/padding), not the outer rect. For non-scrolling panes, same as clip.
_tui_hit.clip_content() {
	local pane=$5
	local scroll="${_TUI_P_SCROLL[$pane]:-none}"
	# Only use content clipping for scrolling panes; others use regular clip
	if [[ "$scroll" != "v" && "$scroll" != "both" ]]; then
		_tui_hit.clip "$@"
		return
	fi

	local r0=$1 c0=$2 r1=$(($1 + $3)) c1=$(($2 + $4))
	# Get pane's content rect (inside border/padding)
	_tui._inset "$pane"
	local pr=$((${_TUI_P_ROW[$pane]} + _IV))
	local pc=$((${_TUI_P_COL[$pane]} + _IH))
	local r1_max=$((pr + ${_TUI_P_H[$pane]} - 2 * _IV))
	local c1_max=$((pc + ${_TUI_P_W[$pane]} - 2 * _IH))

	((r0 < pr)) && r0=$pr
	((c0 < pc)) && c0=$pc
	((r1 > r1_max)) && r1=$r1_max
	((c1 > c1_max)) && c1=$c1_max
	_HR=$r0 _HC=$c0 _HH=$((r1 - r0)) _HW=$((c1 - c0))
	((_HH < 0)) && _HH=0
	((_HW < 0)) && _HW=0
	return 0
}

# _tui_hit.zones_scrollbars - registers scrollbar zones for every scrollable leaf pane.
_tui_hit.zones_scrollbars() {
	local p mode pr pc ph pw
	for p in "${_TUI_P_ALL[@]}"; do
		[[ -z "${_TUI_P_CHILDREN[$p]:-}" ]] || continue
		mode="${_TUI_P_SCROLL[$p]:-none}"
		[[ "$mode" == none ]] && continue
		pr=${_TUI_P_ROW[$p]} pc=${_TUI_P_COL[$p]} ph=${_TUI_P_H[$p]} pw=${_TUI_P_W[$p]}
		((ph < 1 || pw < 1)) && continue
		case "$mode" in v | both) _tui_hit.add scrollbar "$p" v "$pr" "$((pw > 3 ? pc + pw - 3 : pc))" "$ph" "$((pw > 3 ? 3 : pw))" ;; esac
		case "$mode" in h | both) _tui_hit.add scrollbar "$p" h "$((ph > 3 ? pr + ph - 3 : pr))" "$pc" "$((ph > 3 ? 3 : ph))" "$pw" ;; esac
	done
}

# _tui_hit.zones_titles - registers title text zones for panes with titles.
_tui_hit.zones_titles() {
	local p title max_t
	for p in "${_TUI_P_ALL[@]}"; do
		title="${_TUI_P_TITLE[$p]:-}"
		[[ -n "$title" ]] || continue
		_tui._eff_border "$p"
		[[ "$_TB" != none ]] || continue
		max_t=$((${_TUI_P_W[$p]} - 2 - 4))
		((max_t < 1)) && max_t=1
		((${#title} > max_t)) && title="${title:0:max_t}"
		_tui_hit.add title "$p" "" "${_TUI_P_ROW[$p]}" "$((${_TUI_P_COL[$p]} + 2))" 1 "$((${#title} + 2))"
	done
}

# _tui_hit.zones_extras [cv] - registers extra zones (divider/handle/chevron/title); cv=collapse buttons only.
_tui_hit.zones_extras() {
	local i n=$_TUI_HZ_EXTRA_FIELDS want=0 is
	[[ "${1:-}" == cv ]] && want=1
	for ((i = 0; i < ${#_TUI_HZ_EXTRA[@]}; i += n)); do
		is=0
		[[ "${_TUI_HZ_EXTRA[i + 2]}" == cv-* ]] && is=1
		((is == want)) || continue
		_tui_hit.add "${_TUI_HZ_EXTRA[@]:i:n}"
	done
}

# _tui_hit.zones_widgets - registers widget zones (exact rect, then padded hit areas).
_tui_hit.zones_widgets() {
	local id p hp hb vp hw dy dx hh reuse=$_TUI_WP_REUSE
	local -a pads=()
	_TUI_WP_LAST="" _TUI_WP_REUSE=1 # widgets of one pane share its inset
	for id in "${_TUI_W_ORDER[@]}"; do
		p="${_TUI_W_PANE[$id]:-}"
		[[ -n "$p" ]] && ((${_TUI_P_H[$p]:-0} > 0)) || continue
		[[ -n "${_TUI_W_HIDDEN[$id]:-}" ]] && continue # in a collapsed pane
		hp="${_TUI_W_HITPAD[$id]:-}" hb="${_TUI_W_HITBOX[$id]:-}"
		[[ "${_TUI_W_TYPE[$id]}" == label && -z "$hp" && -z "$hb" ]] && continue
		_tui._widget_pos "$id"
		_TUI_HZ_WR[$id]=$_WSR _TUI_HZ_WC[$id]=$_WSC _TUI_HZ_WW[$id]=$_WSW
		_tui_hit.clip_content "$_WSR" "$_WSC" "$_WSH" "$_WSW" "$p"
		_tui_hit.add widget "$id" "" "$_HR" "$_HC" "$_HH" "$_HW"
		if [[ -n "$hb" ]]; then
			read -r dy dx hh hw <<<"$hb"
			pads+=("$id" "$((_WSR + dy))" "$((_WSC + dx))" "$hh" "$hw" "$p")
		elif [[ -n "$hp" ]]; then
			read -r vp hw <<<"$hp"
			hw=${hw:-$vp}
			pads+=("$id" "$((_WSR - vp))" "$((_WSC - hw))" "$((_WSH + 2 * vp))" "$((_WSW + 2 * hw))" "$p")
		fi
	done
	_TUI_WP_REUSE=$reuse
	for ((dy = 0; dy < ${#pads[@]}; dy += 6)); do
		_tui_hit.clip "${pads[dy + 1]}" "${pads[dy + 2]}" "${pads[dy + 3]}" "${pads[dy + 4]}" "${pads[dy + 5]}"
		_tui_hit.add hitbox "${pads[dy]}" "" "$_HR" "$_HC" "$_HH" "$_HW"
	done
}

# _tui_hit.zones_panes - registers fallback pane zones (whole rect of every leaf pane).
_tui_hit.zones_panes() {
	local p
	for p in "${_TUI_P_ALL[@]}"; do
		[[ -z "${_TUI_P_CHILDREN[$p]:-}" ]] && _tui_hit.add pane "$p" "" "${_TUI_P_ROW[$p]}" "${_TUI_P_COL[$p]}" "${_TUI_P_H[$p]}" "${_TUI_P_W[$p]}"
	done
}

# _tui_hit.rebuild - rebuilds the whole hit index from the current layout (zones added in priority order).
_tui_hit.rebuild() {
	_tui_perf.begin hit_index
	_TUI_HZ_ROW=() _TUI_HZ_C0=() _TUI_HZ_C1=() _TUI_HZ_KIND=() _TUI_HZ_ID=() _TUI_HZ_ARG=()
	_TUI_HZ_N=0 _TUI_HZ_DIRTY=0
	_TUI_HZ_WR=() _TUI_HZ_WC=() _TUI_HZ_WW=()
	_tui_hit.zones_scrollbars
	_tui_collapse.zones      # chevron zones (registered into the extras)
	_tui_hit.zones_extras cv # the button's second cell sits on the border's divider zone and must win it
	_tui_resize.zones        # handle / divider zones follow the layout
	_tui_hit.zones_extras    # before the titles
	_tui_hit.zones_titles
	_tui_hit.zones_widgets
	_tui_hit.zones_panes
	_tui_perf.end hit_index
}

# _tui_hit.at COL ROW - fork-free: one array read, then the few zones crossing that row (not all zones on the page)
_tui_hit.at() {
	local mx="$1" my="$2" z
	((_TUI_HZ_DIRTY)) && _tui_hit.rebuild
	_HIT="" _HIT_KIND="" _HIT_ID="" _HIT_ARG="" _HIT_PANE=""
	# shellcheck disable=SC2086 # word-splitting the index list is the point
	for z in ${_TUI_HZ_ROW[my]:-}; do
		((mx >= _TUI_HZ_C0[z] && mx <= _TUI_HZ_C1[z])) || continue
		if [[ "${_TUI_HZ_KIND[z]}" == pane ]]; then
			_HIT_PANE="${_TUI_HZ_ID[z]}"
			break
		elif [[ -z "$_HIT_KIND" ]]; then
			_HIT_KIND="${_TUI_HZ_KIND[z]}" _HIT_ID="${_TUI_HZ_ID[z]}" _HIT_ARG="${_TUI_HZ_ARG[z]}"
		fi
	done
	case "$_HIT_KIND" in widget | hitbox) _HIT="$_HIT_ID" ;; esac
	[[ -n "$_HIT_KIND" ]]
}

# _tui_hit.scrollbar_jump PANE v|h COL ROW - scroll PANE so the pointer's position on the bar becomes the offset
_tui_hit.scrollbar_jump() {
	local p="$1" total
	_SC_OLD=${_TUI_P_SOFF_V[$p]:-0}
	if [[ "$2" == v ]]; then
		if _tui_scroll.is_output "$p"; then total=${_TUI_P_LINES[$p]:-1}; else total=${_TUI_P_CONTENT_H[$p]:-1}; fi # tui.output lines, or the widgets' rows
		_TUI_P_SOFF_V[$p]=$((($4 - _TUI_P_ROW[$p]) * total / _TUI_P_H[$p]))
	else
		_TUI_P_SOFF_H[$p]=$((($3 - _TUI_P_COL[$p]) * ${_TUI_P_MAX_W[$p]:-1} / _TUI_P_W[$p]))
	fi
	_tui_scroll.apply "$p"
}

# tui.hit.set ID hit_pad|hitbox VALUE - widen the area that counts as a hit on widget ID
tui.hit.set() {
	case "$2" in
		hit_pad) _TUI_W_HITPAD[$1]="$3" ;;
		hitbox) _TUI_W_HITBOX[$1]="$3" ;;
		*)
			echo "tui.hit.set: unknown attribute '$2' (hit_pad|hitbox)" >&2
			return 1
			;;
	esac
	_TUI_HZ_DIRTY=1
}

# ── zone hover ────────────────────────────────────────────────────────────

# _tui_hit.class_sgr CLASS HOVER PANE [COLLAPSED] -> _SGR: the look of theme class CLASS (COLLAPSED=1: its :collapsed rule, HOVER=1: its
# :hover rule, each over the base class, field by field), the background falling back to PANE's. rc 1 when the theme defines neither.
_tui_hit.class_sgr() {
	local k="$1" fg bg mo
	fg="${_TUI_CLASS_FG[$k]:-}" bg="${_TUI_CLASS_BG[$k]:-}" mo="${_TUI_CLASS_MOD[$k]:-}"
	if ((${4:-0})); then # :collapsed over the base, :hover over both
		fg="${_TUI_CLASS_FG[${k}_collapsed]:-$fg}" bg="${_TUI_CLASS_BG[${k}_collapsed]:-$bg}" mo="${_TUI_CLASS_MOD[${k}_collapsed]:-$mo}"
	fi
	if (($2)); then
		fg="${_TUI_CLASS_FG[${k}_hover]:-$fg}" bg="${_TUI_CLASS_BG[${k}_hover]:-$bg}" mo="${_TUI_CLASS_MOD[${k}_hover]:-$mo}"
	fi
	[[ -n "$fg$bg$mo" ]] || return 1
	_tui._sgr_from "$fg" "${bg:-${_TUI_STYLE_BG[${3}_normal]:-}}" "$mo"
}

# _tui_hit.key_buf KEY - appends the repaint of zone KEY ("PANE|ARG") in its current (hovered or not) look
_tui_hit.key_buf() {
	case "${1#*|}" in
		cv-*) _tui_collapse.button_buf "${1%%|*}" ;;
		rz-*) _tui_resize.seg_buf "${1%%|*}" "${1#*|}" ;;
	esac
}

# _tui_hit.hover - the hovered zone follows the pointer; while a resize drag runs it stays the dragged border. A change
# repaints only the two segments (the old one at rest, the new one hovered), through one flush.
_tui_hit.hover() {
	local new=""
	if [[ "$_HIT_ARG" == @(rz-*|cv-*) ]]; then
		new="$_HIT_ID|$_HIT_ARG"
	elif [[ -n "$_TUI_RZ_ID" ]]; then new="$_TUI_RZ_ID|$_TUI_RZ_ARG"; fi
	[[ "$new" == "$_TUI_HZ_HOVER" ]] && return 0
	local old="$_TUI_HZ_HOVER" saved="$_TUI_FRAME"
	_TUI_HZ_HOVER="$new"
	((_TUI_RUNNING)) || return 0
	_TUI_FRAME=""
	((_TUI_HZ_DIRTY)) && _tui_hit.rebuild
	[[ -n "$old" ]] && _tui_hit.key_buf "$old"
	_tui_frame.junctions # a fused border's shared cells are the frame's to draw: back to their own look
	[[ -n "$new" ]] && _tui_hit.key_buf "$new"
	local buf="$_TUI_FRAME"
	_TUI_FRAME="$saved"
	[[ -n "$buf" ]] && _tui_paint.flush "$buf"
	return 0
}

# _tui_hit.overlay [PANE] - appends what is drawn over the frame: the collapse button of PANE (of every pane without
# one) and the hovered segment. A no-op on a page with neither.
_tui_hit.overlay() {
	local p
	if ((${#_TUI_P_COLLAPSIBLE[@]})); then
		if [[ -n "${1:-}" ]]; then
			[[ -n "${_TUI_P_COLLAPSIBLE[$1]:-}" ]] && _tui_collapse.button_buf "$1"
		else for p in "${_TUI_P_ALL[@]}"; do [[ -n "${_TUI_P_COLLAPSIBLE[$p]:-}" ]] && _tui_collapse.button_buf "$p"; done; fi
	fi
	[[ -n "$_TUI_HZ_HOVER" ]] && _tui_hit.key_buf "$_TUI_HZ_HOVER"
	return 0
}
