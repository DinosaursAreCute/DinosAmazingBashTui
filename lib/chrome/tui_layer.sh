#!/usr/bin/env bash
# tui_layer.sh - layers: panes that float above the page (stage 3B of docs/concepts/markup-v2-implementation-plan.md,
# rationale in docs/design/layers.md).
#
#   <window id= title= x= y= width= height= anchor= float= shadow= closable= fullscreen= minimizable= modal= open=> ...</window>
#
# A layer is a pane that hangs outside the page's split tree: it has a rectangle of its own, children like any pane, and
# is drawn after the page (as an overlay: it is redrawn after every full render and whenever something painted under it).
#   anchor   screen (default) | parent (the pane the tag sits in) | #id (a pane or widget)
#   x, y     offset from the anchor's top-left, in cells; x: center|right, y: center|bottom|below|above
#   width, height   cells, N% of the screen, or fill; the rectangle is clamped to the screen
#   float    the header drags it, the bottom-right corner resizes it, a click raises it
#   modal    Tab, clicks and keys stay inside it until it closes; focus returns to where it was
# State (all page-scoped, part of the page cache):
#   _TUI_L_ORDER         layer ids, bottom to top           _TUI_L_N   how many
#   _TUI_P_LAYER[pane]   the layer a pane belongs to (the layer's own root pane included)
#   _TUI_L_ROW/COL/H/W   the layer's current rectangle      _TUI_L_F[L.flag]   float modal shadow closable fullscreen minimizable
#                                                           hidden minimized zoomed moved
# The page's own loops (render, hit index, focus order) see a layer's panes and widgets like any other; the three places
# that must treat them differently ask _TUI_P_LAYER: tui.render skips them (the overlay draws them on top), the hit index
# ranks a layer's zones above the page's, the focus order drops what is outside a modal layer.
# requires: tui_registry

declare -ga _TUI_L_ORDER=()
declare -gi _TUI_L_N=0
declare -gA _TUI_L_ANCHOR=() _TUI_L_PARENT=() _TUI_L_SX=() _TUI_L_SY=() _TUI_L_SW=() _TUI_L_SH=() _TUI_L_F=()
declare -gA _TUI_L_TIMEOUT=() _TUI_L_EXPIRES=()
declare -gA _TUI_L_TIMEOUT=() _TUI_L_EXPIRES=() _TUI_L_ROW=() _TUI_L_COL=() _TUI_L_H=() _TUI_L_W=() _TUI_L_RANK=() _TUI_L_PANES=() _TUI_L_SAVED_FOCUS=()
declare -gA _TUI_P_LAYER=() _TUI_P_DETACHABLE=() _TUI_P_DOCK_GROUP=() _TUI_P_LEAVE=() _TUI_P_ON_DETACH=() _TUI_P_ON_DOCK=() _TUI_P_LAYOUT_KEEP=()
declare -gA _TUI_L_ORIGIN=() # a detached pane's way home: "PARENT INDEX SPEC"
declare -gi _TUI_L_DRAWING=0 # 1 while the layers are being drawn into a write that is on its way out (_tui._flush)
declare -g _TUI_L_TRAP="" # the topmost visible modal layer: the focus scope
declare -g _TUI_L_DRAG="" _TUI_L_DRAG_ARG="" _TUI_L_DX=0 _TUI_L_DY=0 # active drag: layer, move|size, pointer offset

# ── registry ──────────────────────────────────────────────────────────────

# _tui_layer.add ID ANCHOR PARENT X Y WIDTH HEIGHT FLAGS [TIMEOUT] - registers pane ID (built by the pane handler, attached to no
# split) as the topmost layer. FLAGS: words from the list above; a layer is visible unless it carries "hidden".
_tui_layer.add() {
	local id="$1" f
	_tui_layer.forget "$id"
	_TUI_L_ORDER+=("$id")
	_TUI_L_N=${#_TUI_L_ORDER[@]}
	_TUI_L_ANCHOR[$id]="${2:-screen}" _TUI_L_PARENT[$id]="$3"
	_TUI_L_SX[$id]="$4" _TUI_L_SY[$id]="$5" _TUI_L_SW[$id]="$6" _TUI_L_SH[$id]="$7"
	for f in $8; do _TUI_L_F["$id.$f"]=1; done
	_TUI_L_TIMEOUT[$id]="${9:-}"
	_tui_layer.sync
	tui.overlay.add _tui_layer.draw
	_TUI_P_ALL=() _TUI_P_LEAVES=()
	_tui._collect_leaves root
	_TUI_FOCUS_DIRTY=1
	_tui_layer.arm "$id"
}

# _tui_layer.arm ID - a layer with a timeout hides itself that many seconds after it is shown (a toast)
_tui_layer.arm() {
	local s="${_TUI_L_TIMEOUT[$1]:-}"
	[[ "$s" == +([0-9]) ]] && _tui_layer.is_visible "$1" || return 0
	_TUI_L_EXPIRES[$1]=$((${EPOCHREALTIME%[.,]*} + s))
	tui.after "$s" _tui_layer.expire "layer-expire:$1"
}
_tui_layer.expire() {
	local id now=${EPOCHREALTIME%[.,]*}
	for id in "${!_TUI_L_EXPIRES[@]}"; do
		((_TUI_L_EXPIRES[$id] <= now)) || continue
		unset '_TUI_L_EXPIRES[$id]'
		tui.layer.hide "$id"
	done
}

# _tui_layer.forget ID - drops layer ID's bookkeeping (not its panes: tui.reset_ui or the shell does that)
_tui_layer.forget() {
	local id="$1" f k
	local -a keep=()
	for f in "${_TUI_L_ORDER[@]}"; do [[ "$f" == "$id" ]] || keep+=("$f"); done
	_TUI_L_ORDER=("${keep[@]}")
	_TUI_L_N=${#_TUI_L_ORDER[@]}
	for k in "${!_TUI_L_F[@]}"; do [[ "$k" == "$id."* ]] && unset '_TUI_L_F[$k]'; done
	unset '_TUI_L_TIMEOUT[$id]' '_TUI_L_EXPIRES[$id]' '_TUI_L_ANCHOR[$id]' '_TUI_L_PARENT[$id]' '_TUI_L_SX[$id]' '_TUI_L_SY[$id]' '_TUI_L_SW[$id]' '_TUI_L_SH[$id]' \
		'_TUI_L_ROW[$id]' '_TUI_L_COL[$id]' '_TUI_L_H[$id]' '_TUI_L_W[$id]' '_TUI_L_SAVED_FOCUS[$id]'
	for k in ${_TUI_L_PANES[$id]:-}; do unset '_TUI_P_LAYER[$k]'; done
	unset '_TUI_L_PANES[$id]'
	_tui_layer.sync
}

# _tui_layer.clear - every layer goes (tui.reset_ui)
_tui_layer.clear() {
	_TUI_L_ORDER=() _TUI_L_N=0 _TUI_L_TRAP="" _TUI_L_DRAG=""
	_TUI_L_ANCHOR=() _TUI_L_PARENT=() _TUI_L_SX=() _TUI_L_SY=() _TUI_L_SW=() _TUI_L_SH=() _TUI_L_F=()
	_TUI_L_ROW=() _TUI_L_COL=() _TUI_L_H=() _TUI_L_W=() _TUI_L_RANK=() _TUI_L_PANES=() _TUI_L_SAVED_FOCUS=() _TUI_P_LAYER=() _TUI_L_ORIGIN=()
	_TUI_P_DETACHABLE=() _TUI_P_DOCK_GROUP=() _TUI_P_LEAVE=() _TUI_P_ON_DETACH=() _TUI_P_ON_DOCK=() _TUI_P_LAYOUT_KEEP=()
	tui.overlay.remove _tui_layer.draw
}

# _tui_layer.is_visible ID - rc 0 for a layer that is shown
_tui_layer.is_visible() { [[ -n "${_TUI_L_ANCHOR[$1]+x}" && -z "${_TUI_L_F[$1.hidden]:-}" ]]; }

# _tui_layer.sync - ranks, subtree membership, the focus scope and the hidden state of the layers' widgets, after any
# change to the stack. Rank 1 is the lowest layer; the page is rank 0.
_tui_layer.sync() {
	local L p i=0 w k top=""
	for k in "${!_TUI_P_LAYER[@]}"; do unset '_TUI_P_LAYER[$k]'; done
	_TUI_L_RANK=()
	for L in "${_TUI_L_ORDER[@]}"; do
		_TUI_L_RANK[$L]=$((++i))
		_EF_PANES=()
		_tui_engine.collect_panes "$L"
		_TUI_L_PANES[$L]="${_EF_PANES[*]}"
		for p in "${_EF_PANES[@]}"; do _TUI_P_LAYER[$p]="$L"; done
		_tui_layer.is_visible "$L" && [[ -n "${_TUI_L_F[$L.modal]:-}" ]] && top="$L"
	done
	_TUI_L_TRAP="$top"
	for w in "${_TUI_W_ORDER[@]}"; do
		L="${_TUI_P_LAYER[${_TUI_W_PANE[$w]:-_}]:-}"
		[[ -n "$L" ]] || continue
		if _tui_layer.is_visible "$L" && [[ -z "${_TUI_L_F[$L.minimized]:-}" ]]; then
			[[ "${_TUI_W_HIDDEN[$w]:-}" == layer ]] && unset '_TUI_W_HIDDEN[$w]'
		else _TUI_W_HIDDEN[$w]=layer; fi
	done
	_TUI_FOCUS_DIRTY=1
	_tui.epoch_bump hit widgets
	_tui_async.cover_changed
}

# _tui_layer.collect - appends the visible layers' panes to _TUI_P_ALL / _TUI_P_LEAVES, bottom layer first
# (_tui._collect_leaves calls it once, after the page's own panes)
_tui_layer.collect() {
	local L
	((_TUI_L_N)) || return 0
	_tui_layer.sync
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" && _tui._collect_leaves "$L"
	done
}

# _tui_layer.in_scope WIDGET - rc 0 when the focus order may contain WIDGET (always, unless a modal layer traps it)
_tui_layer.in_scope() {
	[[ -z "$_TUI_L_TRAP" ]] || [[ "${_TUI_P_LAYER[${_TUI_W_PANE[$1]:-_}]:-}" == "$_TUI_L_TRAP" ]]
}

# ── geometry ──────────────────────────────────────────────────────────────

# _tui_layer.dim SPEC TOTAL DEFAULT -> _LD: cells, N% of TOTAL, fill, or DEFAULT
_tui_layer.dim() {
	case "$1" in
		*%) _LD=$((${1%\%} * $2 / 100)) ;;
		fill) _LD=$2 ;;
		'' | *[!0-9]*) _LD=$3 ;;
		*) _LD=$1 ;;
	esac
}

# _tui_layer.anchor_rect L -> _AR_R _AR_C _AR_H _AR_W: the rectangle L's x / y are measured from
_tui_layer.anchor_rect() {
	local L="$1" a="${_TUI_L_ANCHOR[$1]:-screen}" p
	case "$a" in
		parent) p="${_TUI_L_PARENT[$L]:-}" ;;
		'#'*) p="${a#\#}" ;;
		*) p="" ;;
	esac
	if [[ -n "$p" && -n "${_TUI_W_TYPE[$p]:-}" ]]; then
		_tui._widget_pos "$p"
		_AR_R=$_WSR _AR_C=$_WSC _AR_H=$_WSH _AR_W=$_WSW
	elif [[ -n "$p" && -n "${_TUI_P_ROW[$p]:-}" ]]; then
		_AR_R=${_TUI_P_ROW[$p]} _AR_C=${_TUI_P_COL[$p]} _AR_H=${_TUI_P_H[$p]} _AR_W=${_TUI_P_W[$p]}
	else
		_AR_R=${_TUI_P_ROW[root]:-1} _AR_C=${_TUI_P_COL[root]:-1} _AR_H=${_TUI_P_H[root]:-$_TUI_ROWS} _AR_W=${_TUI_P_W[root]:-$_TUI_COLS}
	fi
}

# _tui_layer.place L - the rectangle L's attributes ask for, clamped to the screen -> _TUI_L_ROW/COL/H/W
_tui_layer.place() {
	local L="$1" sr sc sh sw w h r c
	sr=${_TUI_P_ROW[root]:-1} sc=${_TUI_P_COL[root]:-1} sh=${_TUI_P_H[root]:-$_TUI_ROWS} sw=${_TUI_P_W[root]:-$_TUI_COLS}
	if [[ -n "${_TUI_L_F[$L.zoomed]:-}" ]]; then
		_TUI_L_ROW[$L]=$sr _TUI_L_COL[$L]=$sc _TUI_L_H[$L]=$sh _TUI_L_W[$L]=$sw
		return 0
	fi
	_tui_layer.dim "${_TUI_L_SW[$L]:-}" "$sw" 40
	w=$_LD
	_tui_layer.dim "${_TUI_L_SH[$L]:-}" "$sh" 10
	h=$_LD
	# never smaller than what is inside: a layer that is too small only shows the size warning
	_tui._content_need_index
	_TUI_CN_ON=1
	_tui._pane_content_need "$L"
	_TUI_CN_ON=0
	((_TUI_CONTENT_NEED_W > w)) && w=$_TUI_CONTENT_NEED_W
	((_TUI_CONTENT_NEED_H > h)) && h=$_TUI_CONTENT_NEED_H
	((w > sw)) && w=$sw
	((h > sh)) && h=$sh
	((w < 3)) && w=3
	((h < 3)) && h=3
	_tui_layer.anchor_rect "$L"
	case "${_TUI_L_SX[$L]:-}" in
		center) c=$((_AR_C + (_AR_W - w) / 2)) ;;
		right) c=$((_AR_C + _AR_W - w)) ;;
		'' | *[!0-9]*) c=$_AR_C ;;
		*) c=$((_AR_C + _TUI_L_SX[$L])) ;;
	esac
	case "${_TUI_L_SY[$L]:-}" in
		center) r=$((_AR_R + (_AR_H - h) / 2)) ;;
		bottom) r=$((_AR_R + _AR_H - h)) ;;
		below) r=$((_AR_R + _AR_H)) ;;
		above) r=$((_AR_R - h)) ;;
		'' | *[!0-9]*) r=$_AR_R ;;
		*) r=$((_AR_R + _TUI_L_SY[$L])) ;;
	esac
	_tui_layer.clamp "$r" "$c" "$h" "$w"
	_TUI_L_ROW[$L]=$_CL_ROW _TUI_L_COL[$L]=$_CL_COL _TUI_L_H[$L]=$h _TUI_L_W[$L]=$w
}

# _tui_layer.clamp ROW COL H W -> _CL_ROW _CL_COL: the rectangle moved inside the screen
_tui_layer.clamp() {
	local sr=${_TUI_P_ROW[root]:-1} sc=${_TUI_P_COL[root]:-1} sh=${_TUI_P_H[root]:-$_TUI_ROWS} sw=${_TUI_P_W[root]:-$_TUI_COLS}
	_CL_ROW=$1 _CL_COL=$2
	((_CL_ROW + $3 > sr + sh)) && _CL_ROW=$((sr + sh - $3))
	((_CL_COL + $4 > sc + sw)) && _CL_COL=$((sc + sw - $4))
	((_CL_ROW < sr)) && _CL_ROW=$sr
	((_CL_COL < sc)) && _CL_COL=$sc
	return 0
}

# _tui_layer.layout - places every visible layer that was not moved by hand and lays out its children; runs after the
# page's own layout (the anchors read it)
_tui_layer.layout() {
	local L
	((_TUI_L_N)) || return 0
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" || continue
		if [[ -z "${_TUI_L_F[$L.moved]:-}" || -n "${_TUI_L_F[$L.zoomed]:-}" ]]; then
			_tui_layer.place "$L"
		else
			_tui_layer.clamp "${_TUI_L_ROW[$L]}" "${_TUI_L_COL[$L]}" "${_TUI_L_H[$L]}" "${_TUI_L_W[$L]}"
			_TUI_L_ROW[$L]=$_CL_ROW _TUI_L_COL[$L]=$_CL_COL
		fi
		_tui_layer.apply_rect "$L"
	done
}

# _tui_layer.apply_rect L - L's rectangle into its root pane's geometry, then the layout of what is inside
_tui_layer.apply_rect() {
	local L="$1"
	_TUI_P_ROW[$L]=${_TUI_L_ROW[$L]} _TUI_P_COL[$L]=${_TUI_L_COL[$L]}
	_TUI_P_H[$L]=${_TUI_L_H[$L]} _TUI_P_W[$L]=${_TUI_L_W[$L]}
	_tui.epoch_bump layout
	_tui._layout_r "$L"
}

# ── drawing ───────────────────────────────────────────────────────────────

# _tui_layer.buttons L -> _LB: the header buttons of L from the right edge inward (2 cells each)
_tui_layer.buttons() {
	local L="$1"
	_LB=""
	[[ -n "${_TUI_L_F[$L.closable]:-}" ]] && _LB="close"
	[[ -n "${_TUI_L_F[$L.minimizable]:-}" ]] && _LB+="${_LB:+ }min"
	[[ -n "${_TUI_L_F[$L.fullscreen]:-}" ]] && _LB+="${_LB:+ }full"
	[[ -n "${_TUI_L_F[$L.float]:-}" ]] && _LB+="${_LB:+ }reset"
	[[ -n "${_TUI_L_ORIGIN[$L]:-}" ]] && _LB+="${_LB:+ }dock"
	# only as many as the width holds
	local -a b
	read -ra b <<<"$_LB"
	while ((${#b[@]} && ${_TUI_L_W[$L]:-0} < 8 + 2 * ${#b[@]})); do unset 'b[-1]'; done
	_LB="${b[*]}"
}

# _tui_layer.glyph NAME -> _LG
_tui_layer.glyph() {
	case "$1" in
		close) _LG="✕" ;;
		min) _LG="–" ;;
		full) _LG="⛶" ;;
		reset) _LG="↺" ;;
		dock) _LG="⇲" ;;
		*) _LG="?" ;;
	esac
}

# _tui_layer.header_buf L - the header buttons on the layer's top border row
_tui_layer.header_buf() {
	local L="$1" b i=0 col hov k pane_sgr
	local r=${_TUI_L_ROW[$L]} c=${_TUI_L_COL[$L]} w=${_TUI_L_W[$L]}
	_tui_layer.buttons "$L"
	for b in $_LB; do
		col=$((c + w - 3 - 2 * i++))
		hov=0
		[[ "$_TUI_HZ_HOVER" == "$L|ly-$b" ]] && hov=1
		_tui_layer.glyph "$b"
		_tui.emit_goto "$r" "$col"
		if _tui_hit.class_sgr layer_button "$hov" "$L"; then
			_tui.emit "$_SGR"
		elif ((hov)); then
			_tui.emit $'\e[1;7m'
		else
			_tui.emit_ring "${L}_border" "${L}_border" "$L"
		fi
		_tui.emit "$_LG "
		_tui.emit_reset
	done
}

# _tui_layer.shadow_buf L - one column right of the layer and one row below it, glyph ▒ in class .layer_shadow
_tui_layer.shadow_buf() {
	local L="$1" r c h w row line
	[[ -n "${_TUI_L_F[$L.shadow]:-}" ]] || return 0
	r=${_TUI_L_ROW[$L]} c=${_TUI_L_COL[$L]} h=${_TUI_L_H[$L]} w=${_TUI_L_W[$L]}
	local right=$((c + w)) bottom=$((r + h))
	((right > _TUI_COLS && bottom > _TUI_ROWS)) && return 0
	if _tui_hit.class_sgr layer_shadow 0 root; then _tui.emit "$_SGR"; else _tui.emit $'\e[2m'; fi
	if ((right <= _TUI_COLS)); then
		for ((row = r + 1; row <= bottom && row <= _TUI_ROWS; row++)); do
			_tui.emit_goto "$row" "$right"
			_tui.emit "▒"
		done
	fi
	if ((bottom <= _TUI_ROWS)); then
		printf -v line '%*s' "$((right <= _TUI_COLS ? w : w - 1))" ""
		_tui.emit_goto "$bottom" "$((c + 1))"
		_tui.emit "${line// /▒}"
	fi
	_tui.emit_reset
}

# _tui_layer.draw - draws every visible layer, bottom to top, into _TUI_FRAME (an overlay: tui.overlay.add)
_tui_layer.draw() {
	((_TUI_L_N || ${#_TUI_P_DETACHABLE[@]})) || return 0
	local L p w
	local -A per=()
	for w in "${_TUI_W_ORDER[@]}"; do
		L="${_TUI_P_LAYER[${_TUI_W_PANE[$w]:-_}]:-}"
		[[ -n "$L" ]] && per[$L]+="${per[$L]:+ }$w"
	done
	for p in "${!_TUI_P_DETACHABLE[@]}"; do _tui_layer.detach_buf "$p"; done # under the layers
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" || continue
		[[ -n "${_TUI_P_H[$L]:-}" ]] || continue
		_tui_layer.shadow_buf "$L"
		if [[ -n "${_TUI_L_F[$L.minimized]:-}" ]]; then
			_tui_layer.bar_buf "$L"
			continue
		fi
		for p in ${_TUI_L_PANES[$L]}; do _tui._paint_pane_buf "$p"; done
		for w in ${per[$L]:-}; do _tui._draw_widget_buf "$w"; done
		_tui_layer.header_buf "$L"
	done
}

# _tui_layer.bar_buf L - a minimized layer: its title on one row at the top of its rectangle
_tui_layer.bar_buf() {
	local L="$1" t="${_TUI_P_TITLE[$1]:-$1}" w=${_TUI_L_W[$1]}
	local line
	printf -v line ' ▸ %-*s' "$((w - 3))" "${t:0:$((w - 3))}"
	_tui.emit_goto "${_TUI_L_ROW[$L]}" "${_TUI_L_COL[$L]}"
	_tui.emit_ring "${L}_title" "${L}_border" "$L"
	_tui.emit "${line:0:w}"
	_tui.emit_reset
}

# ── hit zones ─────────────────────────────────────────────────────────────

# _tui_layer.zones - at the end of _tui_hit.rebuild: each visible layer's header, buttons and corner, a zone that blocks
# the page under it, then every row's zone list is reordered so higher layers come first
_tui_layer.zones() {
	local L b i col r c h w left p
	for p in "${!_TUI_P_DETACHABLE[@]}"; do # the detach button of a pane that is docked
		_tui_layer.detach_cell "$p" && _tui_hit.add layer "$p" dt "$_DT_R" "$_DT_C" 1 2
	done
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" || continue
		r=${_TUI_L_ROW[$L]} c=${_TUI_L_COL[$L]} h=${_TUI_L_H[$L]} w=${_TUI_L_W[$L]}
		left=$((c + w - 1))
		i=0
		_tui_layer.buttons "$L"
		for b in $_LB; do
			col=$((c + w - 3 - 2 * i++))
			_tui_hit.add layer "$L" "btn:$b" "$r" "$col" 1 2
			left=$col
		done
		if [[ -n "${_TUI_L_F[$L.float]:-}" && -z "${_TUI_L_F[$L.zoomed]:-}" ]]; then
			_tui_hit.add layer "$L" drag "$r" "$((c + 1))" 1 "$((left - c - 1))"
			[[ -n "${_TUI_L_F[$L.minimized]:-}" ]] || _tui_hit.add layer "$L" size "$((r + h - 1))" "$((c + w - 2))" 1 2
		fi
		[[ -n "${_TUI_L_F[$L.passive]:-}" ]] || _tui_hit.add pane "$L" "" "$r" "$c" "$h" "$w" # a tooltip does not catch the pointer
	done
	_tui_layer.rank_rows
}

# _tui_layer.rank_rows - every screen row's zone list: highest layer first; inside a layer the header / button / corner
# zones, then its other zones, then the zone that blocks the layers and page below
_tui_layer.rank_rows() {
	local z id p L key row list n=${#_TUI_L_ORDER[@]}
	local -a rank=()
	for ((z = 0; z < _TUI_HZ_N; z++)); do
		id="${_TUI_HZ_ID[z]}"
		p="$id"
		[[ -n "${_TUI_W_TYPE[$id]:-}" ]] && p="${_TUI_W_PANE[$id]:-}"
		L="${_TUI_P_LAYER[${p:-_}]:-}"
		key=${_TUI_L_RANK[${L:-_}]:-0}
		case "${_TUI_HZ_KIND[z]}" in
			pane) rank[z]=$((key * 3)) ;;
			layer) rank[z]=$((key * 3 + 2)) ;;
			*) rank[z]=$((key * 3 + 1)) ;;
		esac
	done
	local -a bucket
	for row in "${!_TUI_HZ_ROW[@]}"; do
		bucket=()
		for z in ${_TUI_HZ_ROW[row]}; do bucket[rank[z]]+="${bucket[rank[z]]:+ }$z"; done
		list=""
		for ((key = 3 * n + 2; key >= 0; key--)); do [[ -n "${bucket[key]:-}" ]] && list+="${list:+ }${bucket[key]}"; done
		_TUI_HZ_ROW[row]="$list"
	done
}

# ── stack operations ──────────────────────────────────────────────────────

# _tui_layer.changed - after any change of the stack or a rectangle: layout, repaint
_tui_layer.changed() {
	_tui_layer.sync
	_TUI_P_ALL=() _TUI_P_LEAVES=() # a hidden layer's panes are out of every loop (hit zones included), a shown one's are in
	_tui._collect_leaves root
	_TUI_HZ_DIRTY=1
	_tui_layer.repaint
}

# _tui_layer.repaint - layout, then the page and its layers in one write. No erase: the page paints every cell above the
# footer row, so what a layer vacated is covered by it, and the footer (which an erase would blank and redraw) stays put.
_tui_layer.repaint() {
	_tui._layout root
	((_TUI_RUNNING)) && tui.render
	return 0
}

# tui.layer.raise ID - ID becomes the topmost layer
tui.layer.raise() {
	local id="$1" f
	local -a keep=()
	_tui_layer.is_visible "$id" || return 1
	[[ "${_TUI_L_ORDER[-1]:-}" == "$id" ]] && return 0
	for f in "${_TUI_L_ORDER[@]}"; do [[ "$f" == "$id" ]] || keep+=("$f"); done
	_TUI_L_ORDER=("${keep[@]}" "$id")
	_tui_layer.sync
	_tui.epoch_bump layout
	_TUI_P_ALL=() _TUI_P_LEAVES=()
	_tui._collect_leaves root
	_TUI_HZ_DIRTY=1
	((_TUI_RUNNING)) && tui.render
	return 0
}

# tui.layer.show ID / hide ID / toggle ID - a hidden layer is not drawn, hit or focused; a modal layer takes the focus
# scope while it is shown (the focused widget is remembered and comes back when it hides)
tui.layer.show() {
	local id="$1"
	[[ -n "${_TUI_L_ANCHOR[$id]+x}" ]] || return 1
	_tui_layer.is_visible "$id" && return 0
	unset '_TUI_L_F[$id.hidden]'
	_TUI_L_SAVED_FOCUS[$id]="$_TUI_FOCUS_ID"
	_tui_layer.restack "$id"
	_tui_layer.enter_focus "$id"
	_tui_layer.changed
	_tui_layer.arm "$id"
}
tui.layer.hide() {
	local id="$1"
	_tui_layer.is_visible "$id" || return 1
	_TUI_L_F[$id.hidden]=1
	_tui_layer.leave_focus "$id"
	_tui_layer.changed
}
tui.layer.close() { tui.layer.hide "$@"; }
tui.layer.toggle() { if _tui_layer.is_visible "$1"; then tui.layer.hide "$1"; else tui.layer.show "$1"; fi; }

# _tui_layer.restack ID - ID to the top of the stack and the page's pane list rebuilt around it
_tui_layer.restack() {
	local f
	local -a keep=()
	for f in "${_TUI_L_ORDER[@]}"; do [[ "$f" == "$1" ]] || keep+=("$f"); done
	_TUI_L_ORDER=("${keep[@]}" "$1")
	_tui_layer.sync
	_TUI_P_ALL=() _TUI_P_LEAVES=()
	_tui._collect_leaves root
}

# _tui_layer.enter_focus ID - a layer that takes the scope puts the focus on its first widget
_tui_layer.enter_focus() {
	local w
	[[ -n "${_TUI_L_F[$1.modal]:-}" ]] || return 0
	_tui_focus.ensure
	for w in "${_TUI_FOCUS_TAB[@]}"; do
		[[ "${_TUI_P_LAYER[${_TUI_W_PANE[$w]:-_}]:-}" == "$1" ]] || continue
		_tui_focus.set "$w"
		return 0
	done
	_TUI_FOCUS_ID="" _TUI_FOCUS_IDX=-1
}

# _tui_layer.leave_focus ID - focus goes back to the widget that had it before ID opened, if it is still there
_tui_layer.leave_focus() {
	local w="${_TUI_L_SAVED_FOCUS[$1]:-}"
	unset '_TUI_L_SAVED_FOCUS[$1]'
	[[ -n "${_TUI_L_F[$1.modal]:-}" ]] || return 0
	_tui_layer.sync
	if [[ -n "$w" && -n "${_TUI_W_TYPE[$w]:-}" && -z "${_TUI_W_HIDDEN[$w]:-}" ]]; then _tui_focus.set "$w"; else _tui._unfocus 2>/dev/null; fi
}

# tui.layer.move ID ROW COL - the layer's top-left corner, kept inside the screen; the layer stays where it was put
tui.layer.move() {
	local id="$1"
	_tui_layer.is_visible "$id" || return 1
	_tui_layer.clamp "$2" "$3" "${_TUI_L_H[$id]}" "${_TUI_L_W[$id]}"
	_TUI_L_ROW[$id]=$_CL_ROW _TUI_L_COL[$id]=$_CL_COL
	_TUI_L_F[$id.moved]=1
	_tui_layer.apply_rect "$id"
	_TUI_HZ_DIRTY=1
	_tui_layer.repaint
	return 0
}

# tui.layer.size ID HEIGHT WIDTH - the layer's size (at least 3x3, at most the screen)
tui.layer.size() {
	local id="$1" h="$2" w="$3"
	_tui_layer.is_visible "$id" || return 1
	((h < 3)) && h=3
	((w < 8)) && w=8
	((h > _TUI_P_H[root])) && h=${_TUI_P_H[root]}
	((w > _TUI_P_W[root])) && w=${_TUI_P_W[root]}
	_TUI_L_H[$id]=$h _TUI_L_W[$id]=$w
	_TUI_L_F[$id.moved]=1
	_tui_layer.clamp "${_TUI_L_ROW[$id]}" "${_TUI_L_COL[$id]}" "$h" "$w"
	_TUI_L_ROW[$id]=$_CL_ROW _TUI_L_COL[$id]=$_CL_COL
	_tui_layer.apply_rect "$id"
	_TUI_HZ_DIRTY=1
	_tui_layer.repaint
	return 0
}

# tui.layer.reset ID - back to the position and size the markup asked for
tui.layer.reset() {
	_tui_layer.is_visible "$1" || return 1
	unset '_TUI_L_F[$1.moved]' '_TUI_L_F[$1.zoomed]' '_TUI_L_F[$1.minimized]'
	_tui_layer.changed
}

# tui.layer.zoom ID - toggles the layer over the whole screen
tui.layer.zoom() {
	_tui_layer.is_visible "$1" || return 1
	if [[ -n "${_TUI_L_F[$1.zoomed]:-}" ]]; then unset '_TUI_L_F[$1.zoomed]'; else _TUI_L_F[$1.zoomed]=1; fi
	_tui_layer.changed
}

# tui.layer.minimize ID - toggles the layer down to its one-row title bar
tui.layer.minimize() {
	_tui_layer.is_visible "$1" || return 1
	if [[ -n "${_TUI_L_F[$1.minimized]:-}" ]]; then unset '_TUI_L_F[$1.minimized]'; else _TUI_L_F[$1.minimized]=1; fi
	_tui_layer.changed
}

# tui.layer.active [ID] - rc 0 while a layer (that one) is shown
tui.layer.active() {
	local f
	if [[ -n "${1:-}" ]]; then _tui_layer.is_visible "$1"; return; fi
	for f in "${_TUI_L_ORDER[@]}"; do _tui_layer.is_visible "$f" && return 0; done
	return 1
}

# tui.layer.top [VAR] - the topmost visible layer's id ("" when none)
tui.layer.top() {
	local f t=""
	for f in "${_TUI_L_ORDER[@]}"; do _tui_layer.is_visible "$f" && t="$f"; done
	if [[ -n "${1:-}" ]]; then
		local -n _lt_out="$1"
		_lt_out="$t"
	elif [[ -n "$t" ]]; then printf '%s\n' "$t"; fi
	[[ -n "$t" ]]
}

# ── pointer ───────────────────────────────────────────────────────────────

# _tui_layer.snap L ROW COL -> _SN_ROW _SN_COL: ROW COL pulled to a screen edge when the layer is within 2 cells of it
_tui_layer.snap() {
	local sr=${_TUI_P_ROW[root]:-1} sc=${_TUI_P_COL[root]:-1} sh=${_TUI_P_H[root]:-$_TUI_ROWS} sw=${_TUI_P_W[root]:-$_TUI_COLS}
	_SN_ROW=$2 _SN_COL=$3
	((_SN_ROW - sr < 3)) && _SN_ROW=$sr
	((_SN_COL - sc < 3)) && _SN_COL=$sc
	((sr + sh - (_SN_ROW + _TUI_L_H[$1]) < 3)) && _SN_ROW=$((sr + sh - _TUI_L_H[$1]))
	((sc + sw - (_SN_COL + _TUI_L_W[$1]) < 3)) && _SN_COL=$((sc + sw - _TUI_L_W[$1]))
	return 0
}

# _tui_layer.mouse NAME X Y - the pointer hook of _tui_input.mouse_event: a press on the header starts a move, on the
# corner a resize, on a header button runs it; drag follows the pointer; release ends it. Any press inside a layer raises
# it. rc 0 = the event was consumed.
_tui_layer.mouse() {
	local name="$1" mx="$2" my="$3" L="$_HIT_ID" arg="$_HIT_ARG"
	case "$name" in
		mouse:left)
			[[ "$_HIT_KIND" == layer ]] || return 1
			tui.layer.raise "$L"
			case "$arg" in
				drag)
					_TUI_L_DRAG="$L" _TUI_L_DRAG_ARG=move
					_TUI_L_DX=$((mx - _TUI_L_COL[$L])) _TUI_L_DY=$((my - _TUI_L_ROW[$L]))
					;;
				size)
					_TUI_L_DRAG="$L" _TUI_L_DRAG_ARG=size
					_TUI_L_DX=$((_TUI_L_COL[$L] + _TUI_L_W[$L] - 1 - mx)) _TUI_L_DY=$((_TUI_L_ROW[$L] + _TUI_L_H[$L] - 1 - my))
					;;
				btn:close) tui.layer.close "$L" ;;
				btn:min) tui.layer.minimize "$L" ;;
				btn:full) tui.layer.zoom "$L" ;;
				btn:reset) tui.layer.reset "$L" ;;
				btn:dock) tui.layer.dock "$L" ;;
				dt) tui.layer.detach "$L" ;;
			esac
			return 0
			;;
		drag:left)
			[[ -n "$_TUI_L_DRAG" ]] || return 1
			if [[ "$_TUI_L_DRAG_ARG" == move ]]; then
				_tui_layer.snap "$_TUI_L_DRAG" "$((my - _TUI_L_DY))" "$((mx - _TUI_L_DX))"
				tui.layer.move "$_TUI_L_DRAG" "$_SN_ROW" "$_SN_COL"
			else
				tui.layer.size "$_TUI_L_DRAG" "$((my + _TUI_L_DY - _TUI_L_ROW[$_TUI_L_DRAG] + 1))" "$((mx + _TUI_L_DX - _TUI_L_COL[$_TUI_L_DRAG] + 1))"
			fi
			return 0
			;;
		release)
			[[ -n "$_TUI_L_DRAG" ]] || return 1
			_TUI_L_DRAG=""
			return 0
			;;
	esac
	return 1
}

# _tui_layer.outside - a left press with the pointer over a page (or a lower layer) while a modal or auto-closing layer is
# up: the modal swallows it, a popup closes. A press inside a layer raises that layer. rc 0 = consumed
_tui_layer.outside() {
	local L top="" p="${_HIT_PANE:-}" H="" rank
	[[ "$_HIT_KIND" == layer ]] && p="$_HIT_ID"
	H="${_TUI_P_LAYER[${p:-_}]:-}"
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" && [[ -n "${_TUI_L_F[$L.modal]:-}" || -n "${_TUI_L_F[$L.autoclose]:-}" ]] && top="$L"
	done
	if [[ -n "$top" ]] && ((${_TUI_L_RANK[${H:-_}]:-0} < ${_TUI_L_RANK[$top]})); then
		if [[ -n "${_TUI_L_F[$top.autoclose]:-}" ]]; then tui.layer.hide "$top"; fi
		return 0
	fi
	[[ -n "$H" ]] && tui.layer.raise "$H"
	return 1
}

# _tui_layer.dismiss_key - Esc closes the topmost closable layer; rc 1 when there is none
_tui_layer.dismiss_key() {
	local L top=""
	for L in "${_TUI_L_ORDER[@]}"; do
		_tui_layer.is_visible "$L" && [[ -n "${_TUI_L_F[$L.closable]:-}" || -n "${_TUI_L_F[$L.autoclose]:-}" ]] && top="$L"
	done
	[[ -n "$top" ]] || return 1
	tui.layer.hide "$top"
}

# _tui_layer.on_focus WIDGET - focus moving into a layer raises it
_tui_layer.on_focus() {
	local L="${_TUI_P_LAYER[${_TUI_W_PANE[$1]:-_}]:-}"
	[[ -n "$L" && "${_TUI_L_ORDER[-1]}" != "$L" ]] && tui.layer.raise "$L"
	return 0
}

# ── markup ────────────────────────────────────────────────────────────────

# kind -> the flags it starts with (an attribute of the same name, true|false, overrides)
declare -gA _TUI_L_PRESET=([window]="float shadow closable" [modal]="modal shadow closable" [dialog]="modal shadow closable"
	[popup]="shadow autoclose" [tooltip]="passive" [contextmenu]="shadow autoclose" [toast]="shadow")

# _tui_layer.tag NODE KIND - the handler of every layer tag: builds the pane, registers it as the topmost layer
_tui_layer.tag() {
	local node="$1" kind="$2" anchor x y w h open timeout flag v flags="" parent="$_TUI_BUILD_CTX_PANE"
	_tui_build.attrv "$node" anchor anchor
	_tui_build.attrv "$node" x x
	_tui_build.attrv "$node" y y
	_tui_build.attrv "$node" width w
	_tui_build.attrv "$node" height h
	_tui_build.attrv "$node" open open
	_tui_build.attrv "$node" timeout timeout
	tui_node.attr_get "$node" border || tui_node.attr_set "$node" border single
	_tui_build.tag.pane "$node"
	local id="$_TUI_BUILD_LAST_ID"
	for flag in ${_TUI_L_PRESET[$kind]} fullscreen minimizable; do
		_tui_build.attrv "$node" "$flag" v
		[[ "$v" == false ]] && continue
		[[ "$v" == true || " ${_TUI_L_PRESET[$kind]} " == *" $flag "* ]] && flags+="${flags:+ }$flag"
	done
	for flag in float modal shadow closable; do # attributes that switch a flag on for a kind that does not start with it
		[[ " $flags " == *" $flag "* ]] && continue
		_tui_build.attrv "$node" "$flag" v
		[[ "$v" == true ]] && flags+="${flags:+ }$flag"
	done
	[[ "$open" == false ]] && flags+="${flags:+ }hidden"
	_TUI_BUILD_LAST_ID="$id"
	_tui_build.attrv "$node" persist v
	[[ "$v" == layout ]] && _TUI_P_LAYOUT_KEEP[$id]=1
	_tui_layer.add "$id" "${anchor:-screen}" "$parent" "$x" "$y" "$w" "$h" "$flags" "$timeout"
}
_tui_build.tag.window() { _tui_layer.tag "$1" window; }
_tui_build.tag.modal() { _tui_layer.tag "$1" modal; }
_tui_build.tag.dialog() { _tui_layer.tag "$1" dialog; }
_tui_build.tag.popup() { _tui_layer.tag "$1" popup; }
_tui_build.tag.tooltip() { _tui_layer.tag "$1" tooltip; }
_tui_build.tag.contextmenu() { _tui_layer.tag "$1" contextmenu; }
_tui_build.tag.toast() { _tui_layer.tag "$1" toast; }
tui.register tag window _tui_build.tag.window
tui.register tag modal _tui_build.tag.modal
tui.register tag dialog _tui_build.tag.dialog
tui.register tag popup _tui_build.tag.popup
tui.register tag tooltip _tui_build.tag.tooltip
tui.register tag contextmenu _tui_build.tag.contextmenu
tui.register tag toast _tui_build.tag.toast

# ── detach and dock ───────────────────────────────────────────────────────

# _tui_layer.detach_cell PANE -> _DT_R _DT_C: where PANE's detach button sits (its top border, right end); rc 1 when
# the pane is not showing one (detached already, or too small)
_tui_layer.detach_cell() {
	[[ -n "${_TUI_P_LAYER[$1]+x}" || ${_TUI_P_W[$1]:-0} -lt 12 || ${_TUI_P_H[$1]:-0} -lt 3 ]] && return 1
	_DT_R=${_TUI_P_ROW[$1]} _DT_C=$((${_TUI_P_COL[$1]} + ${_TUI_P_W[$1]} - 4))
}

# _tui_layer.detach_buf PANE - the detach button, drawn like a title-bar control
_tui_layer.detach_buf() {
	_tui_layer.detach_cell "$1" || return 0
	local hov=0
	[[ "$_TUI_HZ_HOVER" == "$1|dt" ]] && hov=1
	_tui.emit_goto "$_DT_R" "$_DT_C"
	if _tui_hit.class_sgr layer_button "$hov" "$1"; then
		_tui.emit "$_SGR"
	elif ((hov)); then
		_tui.emit $'\e[1;7m'
	else
		_tui.emit_ring "${1}_border" "${1}_border" "$1"
	fi
	_tui.emit "⇱ "
	_tui.emit_reset
}

# _tui_layer.parent PANE -> _LP_PARENT _LP_INDEX: the split PANE is a member of
_tui_layer.parent() {
	local p c i
	local -a kids
	for p in "${_TUI_P_ALL[@]}"; do
		[[ -n "${_TUI_P_CHILDREN[$p]:-}" ]] || continue
		read -ra kids <<<"${_TUI_P_CHILDREN[$p]}"
		for i in "${!kids[@]}"; do
			[[ "${kids[i]}" == "$1" ]] && { _LP_PARENT="$p" _LP_INDEX=$i; return 0; }
		done
	done
	return 1
}

# tui.layer.detach PANE - PANE leaves its split and floats as a window of its own, over the place it left. The siblings
# take the space (leave="placeholder" keeps an empty pane of the same size there instead). rc 1 when PANE is not in an
# h / v split.
tui.layer.detach() {
	local id="$1" par idx spec slot orow ocol oh ow # not c: _tui._collect_leaves (called below) loops on a global c
	local -a kids specs
	[[ -n "${_TUI_P_ROW[$id]+x}" && -z "${_TUI_P_LAYER[$id]+x}" ]] || return 1
	_tui_layer.parent "$id" || return 1
	par="$_LP_PARENT" idx=$_LP_INDEX
	[[ "${_TUI_P_DIR[$par]:-}" == @(h|v) ]] || return 1
	read -ra kids <<<"${_TUI_P_CHILDREN[$par]}"
	read -ra specs <<<"${_TUI_P_WEIGHTS[$par]}"
	((${#kids[@]} == ${#specs[@]})) || return 1
	orow=${_TUI_P_ROW[$id]} ocol=${_TUI_P_COL[$id]} oh=${_TUI_P_H[$id]} ow=${_TUI_P_W[$id]}
	spec="${specs[idx]}"
	# the way home is the place between its neighbours (their order changes if another pane floats or docks meanwhile)
	_TUI_L_ORIGIN[$id]="$par $idx $spec ${kids[idx + 1]:--} ${kids[idx - 1]:--}"
	((idx == 0)) && _TUI_L_ORIGIN[$id]="$par $idx $spec ${kids[idx + 1]:--} -"
	if [[ "${_TUI_P_LEAVE[$id]:-}" == placeholder ]]; then
		slot="${id}__slot"
		_ps.panes.set "$slot" border single
		_ps.panes.set "$slot" title "${_TUI_P_TITLE[$id]:-$id} (detached)"
		kids[idx]="$slot" # the placeholder keeps the pane's place and spec
	else
		unset 'kids[idx]' 'specs[idx]'
	fi
	if ((${#kids[@]})); then
		_TUI_P_CHILDREN[$par]="${kids[*]}"
		_TUI_P_WEIGHTS[$par]="${specs[*]}"
	else
		unset '_TUI_P_CHILDREN[$par]' '_TUI_P_WEIGHTS[$par]' '_TUI_P_DIR[$par]'
	fi
	unset '_TUI_P_WEIGHTS0[$par]'
	((ow < 14)) && ow=14
	((oh < 5)) && oh=5
	_tui_layer.add "$id" screen "$par" "" "" "$ow" "$oh" "float shadow closable"
	_TUI_L_F[$id.moved]=1
	_tui_layer.clamp "$((orow + 1))" "$((ocol + 2))" "$oh" "$ow"
	_TUI_L_ROW[$id]=$_CL_ROW _TUI_L_COL[$id]=$_CL_COL _TUI_L_H[$id]=$oh _TUI_L_W[$id]=$ow
	_tui.epoch_bump layout
	local fn="${_TUI_P_ON_DETACH[$id]:-}"
	[[ -n "$fn" ]] && "$fn" "$id"
	_tui_layer.changed
}

# tui.layer.dock LAYER [PANE] - the floating pane goes back into its split, between the neighbours it left (or, given
# PANE of the same dock_group, as the last child of that split pane). A placeholder it left behind is replaced, or removed.
tui.layer.dock() {
	local id="$1" target="${2:-}" par idx spec next prev j slot_at=-1 home
	local -a kids specs
	[[ -n "${_TUI_L_ORIGIN[$id]:-}" ]] || return 1
	read -r par idx spec next prev <<<"${_TUI_L_ORIGIN[$id]}"
	home="$par"
	if [[ -n "$target" ]]; then
		[[ -n "${_TUI_P_DOCK_GROUP[$target]:-}" && "${_TUI_P_DOCK_GROUP[$target]}" == "${_TUI_P_DOCK_GROUP[$id]:-}" ]] || return 1
		par="$target" idx=999 next="-" prev="-"
	fi
	[[ "${_TUI_P_DIR[$par]:-}" == @(h|v) || -z "${_TUI_P_CHILDREN[$par]:-}" ]] || return 1
	[[ -n "${_TUI_P_ROW[$par]+x}" ]] || return 1
	# the placeholder lives in the home split, wherever it is by now
	read -ra kids <<<"${_TUI_P_CHILDREN[$home]:-}"
	read -ra specs <<<"${_TUI_P_WEIGHTS[$home]:-}"
	for j in "${!kids[@]}"; do [[ "${kids[j]}" == "${id}__slot" ]] && slot_at=$j; done
	if ((slot_at >= 0)); then
		if [[ -z "$target" ]]; then
			kids[slot_at]="$id" specs[slot_at]="$spec"
		else
			unset 'kids[slot_at]' 'specs[slot_at]'
			kids=("${kids[@]}") specs=("${specs[@]}")
		fi
		_TUI_P_CHILDREN[$home]="${kids[*]}" _TUI_P_WEIGHTS[$home]="${specs[*]}"
		unset '_TUI_P_WEIGHTS0[$home]'
		_tui_engine.forget_pane "${id}__slot"
	fi
	if [[ -n "$target" || $slot_at -lt 0 ]]; then
		read -ra kids <<<"${_TUI_P_CHILDREN[$par]:-}"
		read -ra specs <<<"${_TUI_P_WEIGHTS[$par]:-}"
		for j in "${!kids[@]}"; do # between the neighbours it had, else where it was
			[[ "${kids[j]}" == "$next" ]] && { idx=$j; break; }
			[[ "${kids[j]}" == "$prev" ]] && idx=$((j + 1))
		done
		((idx > ${#kids[@]})) && idx=${#kids[@]}
		kids=("${kids[@]:0:idx}" "$id" "${kids[@]:idx}")
		specs=("${specs[@]:0:idx}" "$spec" "${specs[@]:idx}")
		[[ -n "${_TUI_P_DIR[$par]:-}" ]] || _TUI_P_DIR[$par]=v
		_TUI_P_CHILDREN[$par]="${kids[*]}"
		_TUI_P_WEIGHTS[$par]="${specs[*]}"
		unset '_TUI_P_WEIGHTS0[$par]'
	fi
	unset '_TUI_L_ORIGIN[$id]'
	_tui_layer.forget "$id"
	_TUI_P_ALL=() _TUI_P_LEAVES=()
	_tui._collect_leaves root
	_tui.epoch_bump layout
	local fn="${_TUI_P_ON_DOCK[$id]:-}"
	[[ -n "$fn" ]] && "$fn" "$id"
	_tui_layer.changed
}

# _tui_layer.build_pane ID DETACHABLE DOCK_GROUP LEAVE ON_DETACH ON_DOCK PERSIST - the markup build step of a pane
_tui_layer.build_pane() {
	local id="$1"
	[[ "$2" == true ]] && _TUI_P_DETACHABLE[$id]=1
	[[ -n "$3" ]] && _TUI_P_DOCK_GROUP[$id]="$3"
	[[ -n "$4" ]] && _TUI_P_LEAVE[$id]="$4"
	[[ -n "$5" ]] && _TUI_P_ON_DETACH[$id]="$5"
	[[ -n "$6" ]] && _TUI_P_ON_DOCK[$id]="$6"
	[[ "$7" == layout ]] && _TUI_P_LAYOUT_KEEP[$id]=1
	[[ "$2" == true ]] && tui.overlay.add _tui_layer.draw
	return 0
}

# ── persist="layout" ──────────────────────────────────────────────────────

# the state of a layer (or of a detachable pane that is docked) as the page store keeps it: "docked", or
# "FLAGS|ROW|COL|H|W" with FLAGS the words detached hidden zoomed minimized moved
_tui_layer.state_get() {
	local id="$1" f flags=""
	if [[ -n "${_TUI_L_ANCHOR[$id]+x}" ]]; then
		[[ -n "${_TUI_L_ORIGIN[$id]:-}" ]] && flags="detached"
		for f in hidden zoomed minimized moved; do [[ -n "${_TUI_L_F[$id.$f]:-}" ]] && flags+="${flags:+,}$f"; done
		_SF="${flags:--}|${_TUI_L_ROW[$id]:-0}|${_TUI_L_COL[$id]:-0}|${_TUI_L_H[$id]:-0}|${_TUI_L_W[$id]:-0}"
	elif [[ -n "${_TUI_P_DETACHABLE[$id]:-}" ]]; then _SF=docked
	else return 1; fi
}
_tui_layer.state_put() {
	local id="$1" flags lr lc lh lw f # lr/lc, not r/c: the calls below clobber global names
	if [[ "$2" == docked ]]; then
		[[ -n "${_TUI_L_ORIGIN[$id]:-}" ]] && tui.layer.dock "$id"
		return 0
	fi
	IFS='|' read -r flags lr lc lh lw <<<"$2"
	if [[ -z "${_TUI_L_ANCHOR[$id]+x}" ]]; then
		[[ "$flags" == *detached* ]] && tui.layer.detach "$id" || return 0
	fi
	[[ -n "${_TUI_L_ANCHOR[$id]+x}" ]] || return 0
	for f in hidden zoomed minimized; do
		if [[ ",$flags," == *",$f,"* ]]; then _TUI_L_F[$id.$f]=1; else unset "_TUI_L_F[$id.$f]"; fi
	done
	if [[ ",$flags," == *",moved,"* ]]; then
		_TUI_L_F[$id.moved]=1
		_TUI_L_ROW[$id]=$lr _TUI_L_COL[$id]=$lc _TUI_L_H[$id]=$lh _TUI_L_W[$id]=$lw
	fi
	_tui_layer.sync
	_TUI_P_ALL=() _TUI_P_LEAVES=()
	_tui._collect_leaves root
	_TUI_HZ_DIRTY=1
}
