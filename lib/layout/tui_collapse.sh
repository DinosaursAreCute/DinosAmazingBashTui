#!/usr/bin/env bash
# tui_collapse.sh - collapsible panes.
#
#   collapsible="true"             the pane gets a collapse button on its border and tui.collapse works on it (a leaf pane in an h/v split)
#   default="expanded|collapsed"   first-build state and what a reset returns to (default expanded)
#   collapsed="true"               alias for default="collapsed" (a conflicting default is a validator error)
#   keep_collapsed="true"          parsed and stored only; 3D keeps the state across page switches
#   collapse_to="title|0|rail"     what a collapsed pane shrinks to, along the parent's split axis (default title)
#   collapse_key="KEY"             a direct bind (any key name the bind table takes, e.g. ctrl+1) toggling the pane from
#                                  anywhere on the page; removed with the page
#   collapse_class="NAME"          theme class of the button (default collapse_button); NAME:hover and NAME:collapsed too
#   on_toggle=FN                   FN PANE STATE runs after a toggle, STATE is collapsed|expanded
#   <button collapsed_text="..">   the text a button shows on a rail; widgets without it are hidden while collapsed
#
# collapse_to:
#   title  v-split parent: one row (the title bar "   Title"); h-split parent: a column as wide as the bordered title,
#          full height. Widgets are hidden.
#   0      size 0 on the split axis, nothing drawn, no button (expand with tui.collapse or the keyboard action).
#   rail   h-split parent: as wide as the longest collapsed_text + 4 (at least 7); v-split parent: 3 rows.
#          Buttons with collapsed_text show it, every other widget is hidden.
# The freed space goes to the siblings that have an fr weight; the pane's previous size spec is restored on expand.
#
# State (the single place 3D reads):
#   _TUI_P_COLLAPSED[ID]=1         set while ID is collapsed, absent otherwise
#   _TUI_P_COLLAPSE_DEFAULT[ID]    expanded|collapsed        _TUI_P_KEEP_COLLAPSED[ID]  true
#   _TUI_P_COLLAPSE_SAVED[ID]      the size spec ID had in its parent's _TUI_P_WEIGHTS before collapsing
#   _TUI_W_HIDDEN[ID]=1            widgets that are not drawn, focusable or hit-testable while their pane is collapsed
# <accordion> is a split whose collapsible children are mutually exclusive (_TUI_P_ACCORDION[ID]=exclusive|multiple).
#
# The collapse button: 2 cells x 1 row drawn ON the border at the corner of the edge that moves (_tui_collapse.cell):
# h split: the right edge's top corner, the left edge's for the last pane; v split: the bottom edge's left corner, the
# top edge's for the last pane. Arrow = direction the edge moves (first/middle pane expanded: left / up; last pane
# expanded: right / down; collapsed: reversed). On a rail or title bar it stays, pointing the expand direction; with
# collapse_to=0 there is none. Theme classes .collapse_button, :hover and :collapsed (collapse_class= picks another). Its zone (kind chevron, arg
# cv-toggle, 2 wide) is rebuilt with the hit index (_tui_collapse.zones); the button is painted after the frame by
# _tui_hit.overlay, hover redraws just it.
# requires:

declare -gA _TUI_P_COLLAPSIBLE=() _TUI_P_COLLAPSED=() _TUI_P_COLLAPSE_DEFAULT=() _TUI_P_COLLAPSE_TO=()
declare -gA _TUI_P_KEEP_COLLAPSED=() _TUI_P_ON_TOGGLE=() _TUI_P_COLLAPSE_SAVED=() _TUI_P_ACCORDION=()
declare -gA _TUI_P_COLLAPSE_KEY=() _TUI_P_COLLAPSE_CLASS=()
declare -gA _TUI_W_COLLAPSED_TEXT=() _TUI_W_HIDDEN=() _TUI_W_LABEL_SAVED=()
declare -gi _TUI_CV_ZONES=0
declare -g _CL_S="" _CL_G="" _CL_R=0 _CL_C=0
declare -ga _CL_CHANGED=()

# tui.collapse ID [toggle|on|off] - collapses (on), expands (off) or toggles (default) pane ID, then lays out again.
tui.collapse() {
	local id="$1" st c cb state
	[[ -n "${_TUI_P_COLLAPSIBLE[$id]:-}" ]] || return 1
	case "${2:-toggle}" in
		toggle) [[ -n "${_TUI_P_COLLAPSED[$id]:-}" ]] && st=0 || st=1 ;;
		on) st=1 ;;
		off) st=0 ;;
		*)
			tui.log.warn "tui.collapse: '$2' is not toggle|on|off" 2>/dev/null
			return 1
			;;
	esac
	_CL_CHANGED=()
	_tui_collapse.flip "$id" "$st" || return 1
	_tui.epoch_bump layout
	_tui_resize.snap
	_tui_resize.commit
	_tui_collapse.refocus
	for c in "${_CL_CHANGED[@]}"; do
		cb="${_TUI_P_ON_TOGGLE[$c]:-}"
		[[ -n "$cb" ]] && declare -F "$cb" >/dev/null || continue
		[[ -n "${_TUI_P_COLLAPSED[$c]:-}" ]] && state=collapsed || state=expanded
		"$cb" "$c" "$state"
	done
	return 0
}

# tui.collapsed ID - rc 0 while pane ID is collapsed.
tui.collapsed() { [[ -n "${_TUI_P_COLLAPSED[$1]:-}" ]]; }

# tui.action.collapse_toggle - alt+c: toggles the nearest collapsible pane around the focus (or the pane the keyboard
# last collapsed, so it can be opened again).
tui.action.collapse_toggle() {
	local p
	_tui_input.pane_current
	p="$_PC"
	while [[ -n "$p" && -z "${_TUI_P_COLLAPSIBLE[$p]:-}" ]]; do _tui_resize.parent "$p" && p="$_RZ_P" || p=""; done
	[[ -n "$p" ]] || return 1
	tui.collapse "$p" toggle
	[[ -n "${_TUI_P_COLLAPSED[$p]:-}" ]] && _TUI_PANE_FOCUS="$p"
	return 0
}

# _tui_collapse.forget_pane ID / forget_widget ID - drops the collapse state of a pane / widget that is leaving the page
_tui_collapse.forget_pane() {
	unset '_TUI_P_COLLAPSIBLE[$1]' '_TUI_P_COLLAPSED[$1]' '_TUI_P_COLLAPSE_DEFAULT[$1]' '_TUI_P_COLLAPSE_TO[$1]' \
		'_TUI_P_KEEP_COLLAPSED[$1]' '_TUI_P_ON_TOGGLE[$1]' '_TUI_P_COLLAPSE_SAVED[$1]' '_TUI_P_ACCORDION[$1]' \
		'_TUI_P_COLLAPSE_KEY[$1]' '_TUI_P_COLLAPSE_CLASS[$1]'
}
_tui_collapse.forget_widget() {
	unset '_TUI_W_HIDDEN[$1]' '_TUI_W_COLLAPSED_TEXT[$1]' '_TUI_W_LABEL_SAVED[$1]'
}

# _tui_collapse.build ID COLLAPSIBLE DEFAULT COLLAPSED KEEP COLLAPSE_TO ON_TOGGLE - the markup build step: empty values
# are skipped. Bad values are the validator's to report; here they fall back to the defaults.
_tui_collapse.build() {
	[[ "$2" == true ]] || return 0
	local id="$1" state=expanded
	_ps.panes.set "$id" collapsible 1
	[[ "$4" == true ]] && state=collapsed
	[[ "$3" == @(expanded|collapsed) ]] && state="$3"
	_ps.panes.set "$id" collapse_default "$state"
	[[ "$5" == true ]] && _TUI_P_KEEP_COLLAPSED[$id]=true
	[[ "$6" == @(title|0|rail) ]] && _TUI_P_COLLAPSE_TO[$id]="$6"
	[[ -n "$7" ]] && _TUI_P_ON_TOGGLE[$id]="$7"
	[[ -n "${9:-}" ]] && _TUI_P_COLLAPSE_CLASS[$id]="$9"
	[[ -n "${8:-}" ]] && _tui_collapse.bind "$id" "$8"
	_tui.epoch_bump hit
	return 0
}

# _tui_collapse.bind ID KEY - the direct toggle bind of collapse_key=; a page bind, recorded for a cache replay like <bind>
_tui_collapse.bind() {
	local _q _a _rec="tui.bind"
	_ps.panes.set "$1" collapse_key "$2"
	for _a in "$2" "tui.collapse $1 toggle" --page --always --desc "Collapse or expand ${_TUI_P_TITLE[$1]:-${_TUI_BUILD_TITLE[$1]:-$1}}"; do
		printf -v _q '%q' "$_a"
		_rec+=" $_q"
	done
	_TUI_CACHE_REC_GOTOS+=("$_rec")
	tui.bind "$2" "tui.collapse $1 toggle" --page --always --desc "Collapse or expand ${_TUI_P_TITLE[$1]:-${_TUI_BUILD_TITLE[$1]:-$1}}"
}

# _tui_collapse.focus_pane - rc 0 when focus is in a collapsible pane; sets _CL_P (footer predicate).
_tui_collapse.focus_pane() {
	((${#_TUI_P_COLLAPSIBLE[@]})) || return 1
	local p
	_tui_input.pane_current
	p="$_PC"
	while [[ -n "$p" && -z "${_TUI_P_COLLAPSIBLE[$p]:-}" ]]; do _tui_resize.parent "$p" && p="$_RZ_P" || p=""; done
	[[ -n "$p" ]] || return 1
	_CL_P="$p"
}

# _tui_collapse.can_collapse - rc 0 when the focused pane is collapsible and expanded.
_tui_collapse.can_collapse() { _tui_collapse.focus_pane && [[ -z "${_TUI_P_COLLAPSED[$_CL_P]:-}" ]]; }

# _tui_collapse.can_expand - rc 0 when the focused pane is collapsible and collapsed.
_tui_collapse.can_expand() { _tui_collapse.focus_pane && [[ -n "${_TUI_P_COLLAPSED[$_CL_P]:-}" ]]; }

# _tui_collapse.clear - tui.reset_ui: nothing survives a page change.
_tui_collapse.clear() {
	_TUI_P_COLLAPSIBLE=() _TUI_P_COLLAPSED=() _TUI_P_COLLAPSE_DEFAULT=() _TUI_P_COLLAPSE_TO=() _TUI_P_KEEP_COLLAPSED=()
	_TUI_P_ON_TOGGLE=() _TUI_P_COLLAPSE_SAVED=() _TUI_P_ACCORDION=()
	_TUI_P_COLLAPSE_KEY=() _TUI_P_COLLAPSE_CLASS=()
	_TUI_W_COLLAPSED_TEXT=() _TUI_W_HIDDEN=() _TUI_W_LABEL_SAVED=()
}

# _tui_collapse.init_children PARENT NODE - the markup build step run right after PARENT's split is made: collapses the
# children whose first-build state is collapsed; on an <accordion> only the first expanded child stays open.
_tui_collapse.init_children() {
	local p="$1" c m="" open=0
	local -a ch
	if [[ "${_N_TYPE[$2]:-}" == accordion ]]; then
		_tui_build.attrv "$2" multiple m
		[[ "$m" == true ]] && _TUI_P_ACCORDION[$p]=multiple || _TUI_P_ACCORDION[$p]=exclusive
	fi
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]:-}"
	for c in "${ch[@]}"; do
		[[ -n "${_TUI_P_COLLAPSIBLE[$c]:-}" ]] || continue
		if [[ "${_TUI_P_COLLAPSE_DEFAULT[$c]:-}" == collapsed ]]; then
			_tui_collapse.flip "$c" 1
		elif [[ "${_TUI_P_ACCORDION[$p]:-}" == exclusive ]] && ((open++)); then
			_tui_collapse.flip "$c" 1
		fi
	done
	_CL_CHANGED=()
}

# _tui_collapse.size ID AXIS -> _CL_S: the size spec (fixed cells) of collapsed pane ID along AXIS (h|v)
# state:direct
_tui_collapse.size() {
	local id="$1" n w t ml=0
	case "${_TUI_P_COLLAPSE_TO[$id]:-title}" in
		0) n=0 ;;
		rail)
			if [[ "$2" == h ]]; then
				for w in "${_TUI_W_ORDER[@]}"; do
					[[ "${_TUI_W_PANE[$w]:-}" == "$id" ]] && ((${#_TUI_W_COLLAPSED_TEXT[$w]} > ml)) && ml=${#_TUI_W_COLLAPSED_TEXT[$w]}
				done
				n=$((ml + 4))
				((n < 7)) && n=7
			else
				n=3
			fi
			;;
		*)
			t="${_TUI_P_TITLE[$id]:-${_TUI_BUILD_TITLE[$id]:-}}"
			if [[ "$2" == v ]]; then n=1; elif [[ -n "$t" ]]; then n=$((${#t} + 7)); else n=6; fi
			;;
	esac
	_CL_S="clamp($n,$n,$n)"
}

# _tui_collapse.flip ID STATE - STATE 1 collapses, 0 expands: rewrites ID's size spec in its parent, hides or relabels
# its widgets and, in an exclusive accordion, collapses the siblings of an expanded pane. No layout, no callbacks; the
# changed panes are appended to _CL_CHANGED. rc 1 when nothing changed.
# _tui_collapse.subtree ID SKIP -> _CL_SUB: " ID child grandchild ... " (space-padded for glob matching). With SKIP=1 a nested collapsed pane
# and everything under it is left out, so expanding ID does not reveal what that pane still hides.
_tui_collapse.subtree() {
	_CL_SUB=" $1 "
	_tui_collapse.subtree_add "$1" "$2"
}
_tui_collapse.subtree_add() {
	local c
	for c in ${_TUI_P_CHILDREN[$1]:-}; do
		((${2})) && [[ -n "${_TUI_P_COLLAPSED[$c]:-}" ]] && continue
		_CL_SUB+="$c "
		_tui_collapse.subtree_add "$c" "$2"
	done
}

_tui_collapse.flip() {
	local id="$1" st="$2" p i axis w ct sib
	local -a spec ch
	[[ -n "${_TUI_P_COLLAPSED[$id]:-}" ]] && ((st)) && return 1
	[[ -z "${_TUI_P_COLLAPSED[$id]:-}" ]] && ((! st)) && return 1
	_tui_resize.parent "$id" || return 1
	[[ "${_TUI_P_DIR[$_RZ_P]:-}" == @(h|v) ]] || return 1
	p="$_RZ_P" i=$_RZ_I axis="${_TUI_P_DIR[$_RZ_P]}"
	read -ra spec <<<"${_TUI_P_WEIGHTS[$p]}"
	if ((st)); then
		_ps.panes.set "$id" collapse_saved "${spec[i]:-1}"
		_tui_collapse.size "$id" "$axis"
		spec[i]="$_CL_S"
		_ps.panes.set "$id" collapsed 1
	else
		spec[i]="${_TUI_P_COLLAPSE_SAVED[$id]:-1}"
		unset '_TUI_P_COLLAPSE_SAVED[$id]' '_TUI_P_COLLAPSED[$id]'
	fi
	_ps.panes.set "$p" weights "${spec[*]}"
	_tui_collapse.subtree "$id" "$((! st))" # widgets of nested panes follow their ancestor: hidden with it, shown again with it
	for w in "${_TUI_W_ORDER[@]}"; do
		[[ "$_CL_SUB" == *" ${_TUI_W_PANE[$w]:-} "* ]] || continue
		ct="${_TUI_W_COLLAPSED_TEXT[$w]:-}"
		if ((st)); then
			if [[ "${_TUI_P_COLLAPSE_TO[$id]:-title}" == rail && -n "$ct" && "${_TUI_W_PANE[$w]}" == "$id" ]]; then
				_ps.widgets.set "$w" label_saved "${_TUI_W_LABEL[$w]:-}"
				_ps.widgets.set "$w" label "$ct"
			else
				_ps.widgets.set "$w" hidden 1
			fi
		else
			unset '_TUI_W_HIDDEN[$w]'
			if [[ -n "${_TUI_W_LABEL_SAVED[$w]+x}" ]]; then
				_ps.widgets.set "$w" label "${_TUI_W_LABEL_SAVED[$w]}"
				unset '_TUI_W_LABEL_SAVED[$w]'
			fi
		fi
	done
	_tui.epoch_bump widgets
	_CL_CHANGED+=("$id")
	if ((! st)) && [[ "${_TUI_P_ACCORDION[$p]:-}" == exclusive ]]; then
		read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
		for sib in "${ch[@]}"; do
			[[ "$sib" != "$id" && -n "${_TUI_P_COLLAPSIBLE[$sib]:-}" ]] && _tui_collapse.flip "$sib" 1
		done
	fi
	return 0
}

# _tui_collapse.refocus - focus on a widget that was just hidden moves to the next focusable one (document order, wrapping)
_tui_collapse.refocus() {
	[[ -n "$_TUI_FOCUS_ID" && -n "${_TUI_W_HIDDEN[$_TUI_FOCUS_ID]:-}" ]] || return 0
	_tui_focus.ensure
	local w seen=0 first="" next=""
	for w in "${_TUI_W_ORDER[@]}"; do
		if [[ "$w" == "$_TUI_FOCUS_ID" ]]; then
			seen=1
			continue
		fi
		[[ -n "${_TUI_FOCUS_POS[$w]+x}" ]] || continue
		[[ -z "$first" ]] && first="$w"
		if ((seen)); then
			next="$w"
			break
		fi
	done
	_TUI_FOCUS_ID="${next:-$first}"
	_TUI_PANE_FOCUS="${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}"
}

# ── drawing ───────────────────────────────────────────────────────────────

# _tui_collapse.bar ID - draws the one-row title bar of a collapsed pane (the border cannot: it needs 3 rows); rc 1 when
# ID is not such a pane. The first two cells are left for the button (_tui_collapse.button_buf paints it on top).
# state:direct
_tui_collapse.bar() {
	[[ -n "${_TUI_P_COLLAPSED[$1]:-}" && "${_TUI_P_H[$1]}" == 1 ]] || return 1
	local t="${_TUI_P_TITLE[$1]:-}" w=${_TUI_P_W[$1]} pad
	((${#t} > w - 3)) && t="${t:0:w-3}"
	pad=$((w - 3 - ${#t}))
	((pad < 0)) && pad=0
	_tui.emit_goto "${_TUI_P_ROW[$1]}" "${_TUI_P_COL[$1]}"
	_tui.emit_style "${1}_title" "" "${1}_normal"
	printf -v pad '%*s' "$pad" ""
	_tui.emit "   $t$pad"
	_tui.emit_reset
}

# ── collapse button ───────────────────────────────────────────────────────

# _tui_collapse.cell ID -> _CL_R _CL_C _CL_G: the button of collapsible pane ID, 2 cells wide at row _CL_R from column
# _CL_C, drawn on the border at the corner of the edge that moves when ID collapses: in an h split the edge ID shares
# with its neighbour (the right edge, the left one for the last pane), in a v split the bottom edge (the top one for
# the last pane); the cells are the edge's first row / left corner. _CL_G is the arrow, pointing where the edge will
# move (collapsed: back where it came from). rc 1 when no button is drawn (size 0, too small, no split parent).
# state:direct
_tui_collapse.cell() {
	local id="$1" r c h w last=0 coll=0 ax
	r=${_TUI_P_ROW[$id]:-0} c=${_TUI_P_COL[$id]:-0} h=${_TUI_P_H[$id]:-0} w=${_TUI_P_W[$id]:-0}
	((h < 1 || w < 1)) && return 1
	[[ -n "${_TUI_P_COLLAPSED[$id]:-}" ]] && coll=1
	_tui._eff_border "$id"
	if [[ "$_TB" == none ]]; then
		((coll && h == 1 && w >= 3)) || return 1 # the one-row title bar of a collapsed v pane
	else
		((w >= 4)) || return 1
	fi
	_tui_resize.parent "$id" || return 1
	ax="${_TUI_P_DIR[$_RZ_P]:-}"
	[[ "$ax" == @(h|v) ]] || return 1
	((_RZ_N > 1 && _RZ_I == _RZ_N - 1)) && last=1
	if [[ "$ax" == h ]]; then
		_CL_R=$r
		if ((last)); then _CL_C=$c _CL_G='▶'; else _CL_C=$((c + w - 2)) _CL_G='◀'; fi
	else
		_CL_C=$c
		if ((last)); then _CL_R=$r _CL_G='▼'; else _CL_R=$((r + h - 1)) _CL_G='▲'; fi
	fi
	if ((coll)); then
		case "$_CL_G" in '◀') _CL_G='▶' ;; '▶') _CL_G='◀' ;; '▲') _CL_G='▼' ;; *) _CL_G='▲' ;; esac
	fi
}

# _tui_collapse.button_buf ID - appends the button of ID (nothing when it has none); hovered while _TUI_HZ_HOVER names it
_tui_collapse.button_buf() {
	_tui_collapse.cell "$1" || return 0
	local hov=0 coll=0 k="${_TUI_P_COLLAPSE_CLASS[$1]:-collapse_button}"
	[[ "$_TUI_HZ_HOVER" == "$1|cv-toggle" ]] && hov=1
	[[ -n "${_TUI_P_COLLAPSED[$1]:-}" ]] && coll=1
	_tui.emit_goto "$_CL_R" "$_CL_C"
	if _tui_hit.class_sgr "$k" "$hov" "$1" "$coll"; then
		_tui.emit "$_SGR"
	elif ((hov)); then
		_tui.emit $'\e[1;7m'
	else
		_tui.emit_ring "${1}_border" "${1}_border" "$1"
	fi
	_tui.emit "$_CL_G "
	_tui.emit_reset
}

# _tui_collapse.zones - (re)registers the button zone of every collapsible pane: 2 cells x 1 row
# state:direct
_tui_collapse.zones() {
	((${#_TUI_P_COLLAPSIBLE[@]} || _TUI_CV_ZONES)) || return 0
	local -a keep=()
	local i dirty=$_TUI_HZ_DIRTY p
	for ((i = 0; i < ${#_TUI_HZ_EXTRA[@]}; i += _TUI_HZ_EXTRA_FIELDS)); do
		[[ "${_TUI_HZ_EXTRA[i + 2]}" == cv-* ]] || keep+=("${_TUI_HZ_EXTRA[@]:i:_TUI_HZ_EXTRA_FIELDS}")
	done
	_TUI_HZ_EXTRA=("${keep[@]}")
	_TUI_CV_ZONES=0
	for p in "${_TUI_P_ALL[@]}"; do
		[[ -n "${_TUI_P_COLLAPSIBLE[$p]:-}" ]] && _tui_collapse.cell "$p" || continue
		_TUI_CV_ZONES=1
		_tui_hit.extra_add chevron "$p" cv-toggle "$_CL_R" "$_CL_C" 1 2
	done
	_TUI_HZ_DIRTY=$dirty
}

# _tui_collapse.mouse NAME - the pointer hook of _tui_input.mouse_event for a button press; rc 0 = consumed
_tui_collapse.mouse() {
	[[ "$1" == mouse:left ]] || return 1
	tui.collapse "$_HIT_ID" toggle
	return 0
}
