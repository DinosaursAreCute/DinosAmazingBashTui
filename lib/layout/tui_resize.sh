#!/usr/bin/env bash
# tui_resize.sh - resizable panes.
#
#   resizable="x|y|both"            which axes the pane may be resized on (any pane)
#   handle="corner|edge|divider|none"   mouse zones, default none: no zones, keyboard resize only
#   on_resize=FN                    FN PANE W H runs for every pane with the attribute whose size changed
#
# A resize moves weight between two siblings of a split (their size specs in _TUI_P_WEIGHTS, 2A units), in
# proportion to the weights they hold now; every other child and the split's total stay as they are. Results are
# clamped to the siblings' min_* / max_*; a fused pane (fuse="true") never gets below 3 rows / 5 columns, the size at
# which its border would be dropped.
#   edge | divider   drag a border the pane shares with a sibling: with a next sibling the trailing border (zone: the
#                    pane's last column / row, arg rz-h / rz-v); the LAST child of a split its leading border, shared
#                    with the previous sibling (zone: its first column / row, arg rz-hl / rz-vl), so it can be resized too
#   corner           drag the pane's bottom-right cell: moves the nearest ancestor h-split edge horizontally and the
#                    nearest v-split edge vertically
# Keyboard: alt+r (tui.action.resize_mode) enters resize mode on the focused pane's nearest resizable ancestor:
# arrows +-1, shift+arrows +-5 (the last pane of a split grows / shrinks against its previous sibling), Enter / Esc leave. The mode is the global _TUI_RESIZE_PANE.
# Zones are rebuilt with the hit index (_tui_hit.rebuild calls _tui_resize.zones); a double press on a zone resets.

declare -gA _TUI_P_RESIZABLE=() _TUI_P_HANDLE=() _TUI_P_ON_RESIZE=()
declare -gA _TUI_P_WEIGHTS0=()                                     # split -> its weights before the first resize (what tui.resize.reset restores)
declare -g _TUI_RESIZE_PANE=""                                     # pane in keyboard resize mode, empty = off
declare -g _TUI_RZ_ID="" _TUI_RZ_ARG="" _TUI_RZ_X=0 _TUI_RZ_Y=0    # active drag: pane, zone arg, anchor column / row
declare -g _TUI_RZ_LAST_ID="" _TUI_RZ_LAST_ARG="" _TUI_RZ_LAST_T=0 # previous press, for the double press
declare -gi _TUI_RZ_DOUBLE_US=400000
declare -g _RZ_P="" _RZ_I=0 _RZ_N=0 _RZ_T=0 _RZ_S=""
declare -gA _RZ_SNAP=()

# tui.pane_resizable ID MODE - x|y|both|none: the axes the pane may be resized on.
tui.pane_resizable() {
	case "$2" in
		x | y | both) _TUI_P_RESIZABLE[$1]="$2" ;;
		none) unset '_TUI_P_RESIZABLE[$1]' ;;
		*)
			tui.log.warn "tui.pane_resizable: '$2' is not x|y|both|none" 2>/dev/null
			return 1
			;;
	esac
	_TUI_HZ_DIRTY=1
}

# tui.pane_handle ID KIND - corner|edge|divider|none: which mouse zone resizes the pane.
tui.pane_handle() {
	case "$2" in
		corner | edge | divider) _TUI_P_HANDLE[$1]="$2" ;;
		none) unset '_TUI_P_HANDLE[$1]' ;;
		*)
			tui.log.warn "tui.pane_handle: '$2' is not corner|edge|divider|none" 2>/dev/null
			return 1
			;;
	esac
	_TUI_HZ_DIRTY=1
}

# tui.resize ID DW DH - grows pane ID by DW columns and DH rows (negative shrinks), clamped like a drag.
tui.resize() {
	local moved=1
	_tui_resize.snap
	((${2:-0} != 0)) && _tui_resize.grow "$1" h "$2" && moved=0
	((${3:-0} != 0)) && _tui_resize.grow "$1" v "$3" && moved=0
	((moved == 0)) && _tui_resize.commit
	return $moved
}

# tui.resize.reset ID - restores the weights ID's split (and every split above it) had before the first resize.
tui.resize.reset() {
	local node="$1" p restored=1
	_tui_resize.snap
	while _tui_resize.parent "$node"; do
		p="$_RZ_P"
		if [[ -n "${_TUI_P_WEIGHTS0[$p]+x}" ]]; then
			_ps.panes.set "$p" weights "${_TUI_P_WEIGHTS0[$p]}"
			unset '_TUI_P_WEIGHTS0[$p]'
			restored=0
		fi
		node="$p"
	done
	((restored == 0)) && {
		_tui.layout_bump
		_tui_resize.commit
	}
	return $restored
}

# _tui_resize.build ID RESIZABLE HANDLE ON_RESIZE - the markup build step: empty values are skipped.
_tui_resize.build() {
	[[ -n "$2" ]] && tui.pane_resizable "$1" "$2"
	[[ -n "$3" ]] && tui.pane_handle "$1" "$3"
	[[ -n "$4" ]] && _TUI_P_ON_RESIZE[$1]="$4"
	return 0
}

# _tui_resize.clear - tui.reset_ui: nothing survives a page change.
_tui_resize.clear() {
	_TUI_P_RESIZABLE=() _TUI_P_HANDLE=() _TUI_P_ON_RESIZE=() _TUI_P_WEIGHTS0=()
	_TUI_RESIZE_PANE="" _TUI_RZ_TITLE="" _TUI_RZ_ID="" _TUI_RZ_LAST_ID=""
}

# _tui_resize.parent CHILD -> _RZ_P (the split holding it) and _RZ_I (its index there); rc 1 for root
_tui_resize.parent() {
	local p ch i
	for p in "${_TUI_P_ALL[@]}"; do
		[[ " ${_TUI_P_CHILDREN[$p]:-} " == *" $1 "* ]] || continue
		read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
		for i in "${!ch[@]}"; do [[ "${ch[i]}" == "$1" ]] && break; done
		_RZ_P="$p" _RZ_I=$i _RZ_N=${#ch[@]}
		return 0
	done
	return 1
}

# ── weight transfer ───────────────────────────────────────────────────────

# _tui_resize.fmt WEIGHT PLAIN -> _RZ_S: a weight (1000 = 1fr) as a size spec; whole numbers stay plain when PLAIN=1
_tui_resize.fmt() {
	local w=$1 fp
	if ((w % 1000 == 0)); then
		((${2:-0})) && _RZ_S=$((w / 1000)) || _RZ_S="$((w / 1000))fr"
		return
	fi
	printf -v fp '%03d' $((w % 1000))
	fp="${fp%%0}"
	fp="${fp%%0}"
	_RZ_S="$((w / 1000)).${fp}fr"
}

# _tui_resize.limit PANE AXIS AVAIL -> _RZ_MIN _RZ_MAX (cells; max -1 = none): PANE's min_* / max_* on AXIS
# state:direct
_tui_resize.limit() {
	local mn mx
	if [[ "$2" == h ]]; then mn="${_TUI_P_MINW[$1]:-}" mx="${_TUI_P_MAXW[$1]:-}"; else mn="${_TUI_P_MINH[$1]:-}" mx="${_TUI_P_MAXH[$1]:-}"; fi
	_RZ_MIN=1 _RZ_MAX=-1
	# a fused pane keeps its border (3 rows / 5 columns): below that the box drops its frame and the shared line with it
	if [[ "${_TUI_P_FUSE[$1]:-}" == true ]] && [[ "${_TUI_P_BORDER[$1]:-single}" != none ]]; then [[ "$2" == h ]] && _RZ_MIN=5 || _RZ_MIN=3; fi
	if [[ -n "$mn" ]]; then
		_tui.layout_resolve "$mn" "$3"
		((_LY_R > _RZ_MIN)) && _RZ_MIN=$_LY_R
	fi
	if [[ -n "$mx" ]]; then
		_tui.layout_resolve "$mx" "$3"
		((_LY_R > 0)) && _RZ_MAX=$_LY_R
	fi
}

# _tui_resize.move SPLIT I DELTA - moves the border between children I and I+1 of SPLIT by DELTA cells (child I grows).
# rc 0 when the weights changed. Only those two children's specs are rewritten.
_tui_resize.move() {
	local p="$1" i=$2 d=$3 dir="${_TUI_P_DIR[$1]}" axis a b sa sb tot avail lo hi nsa
	local -a ch spec
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
	read -ra spec <<<"${_TUI_P_WEIGHTS[$p]}"
	a="${ch[i]}" b="${ch[i + 1]}"
	if [[ "$dir" == h ]]; then
		axis=h sa=${_TUI_P_W[$a]} sb=${_TUI_P_W[$b]} avail=${_TUI_P_W[$p]}
	else
		axis=v sa=${_TUI_P_H[$a]} sb=${_TUI_P_H[$b]} avail=${_TUI_P_H[$p]}
	fi
	tot=$((sa + sb))
	lo=1 hi=$((tot - 1))
	_tui_resize.limit "$a" "$axis" "$avail"
	((_RZ_MIN > lo)) && lo=$_RZ_MIN
	((_RZ_MAX >= 0 && _RZ_MAX < hi)) && hi=$_RZ_MAX
	_tui_resize.limit "$b" "$axis" "$avail"
	((tot - _RZ_MIN < hi)) && hi=$((tot - _RZ_MIN))
	((_RZ_MAX >= 0 && tot - _RZ_MAX > lo)) && lo=$((tot - _RZ_MAX))
	((lo > hi)) && return 1
	nsa=$((sa + d))
	((nsa > hi)) && nsa=$hi
	((nsa < lo)) && nsa=$lo
	((d > 0 && nsa <= sa || d < 0 && nsa >= sa || d == 0)) && return 1
	d=$((nsa - sa))

	local sp_a="${spec[i]:-1}" sp_b="${spec[i + 1]:-1}" wa wb tw nwa plain=0
	if [[ "$sp_a" =~ ^[0-9]+%$ && "$sp_b" =~ ^[0-9]+%$ ]]; then
		wa=${sp_a%\%} wb=${sp_b%\%} tw=$((wa + wb))
		nwa=$(((2 * nsa * tw + tot) / (2 * tot))) # from the target size, not from wa: rounding must not compound
		((nwa < 1)) && nwa=1
		((nwa > tw - 1)) && nwa=$((tw - 1))
		spec[i]="${nwa}%" spec[i + 1]="$((tw - nwa))%"
	else
		if [[ "$sp_a" =~ ^([0-9]+(\.[0-9]+)?fr|[0-9]+|auto|fill)$ && "$sp_b" =~ ^([0-9]+(\.[0-9]+)?fr|[0-9]+|auto|fill)$ ]]; then
			_tui.layout_fr_weight "$sp_a"
			wa=$_LY_R
			_tui.layout_fr_weight "$sp_b"
			wb=$_LY_R
			[[ "$sp_a" =~ ^[0-9]+$ && "$sp_b" =~ ^[0-9]+$ ]] && plain=1
		else
			wa=$((sa * 1000)) wb=$((sb * 1000)) # percent / clamp() mixed with fr: continue in cells
		fi
		tw=$((wa + wb))
		((tw < 2)) && wa=1000 wb=1000 tw=2000
		nwa=$(((2 * nsa * tw + tot) / (2 * tot))) # from the target size, not from wa: rounding must not compound
		((nwa < 1)) && nwa=1
		((nwa > tw - 1)) && nwa=$((tw - 1))
		_tui_resize.fmt "$nwa" "$plain"
		spec[i]="$_RZ_S"
		_tui_resize.fmt "$((tw - nwa))" "$plain"
		spec[i + 1]="$_RZ_S"
	fi
	[[ -n "${_TUI_P_WEIGHTS0[$p]+x}" ]] || _TUI_P_WEIGHTS0[$p]="${_TUI_P_WEIGHTS[$p]}"
	_ps.panes.set "$p" weights "${spec[*]}"
	_tui.layout_bump
}

# _tui_resize.grow PANE AXIS DELTA [OWN] - grows PANE by DELTA cells on AXIS (h = width, v = height) at the nearest
# ancestor split of that axis in which PANE's branch has a next sibling (else the previous one). With OWN=1 the split
# is simply the nearest one of that axis with two or more children: the branch moves its trailing edge, the last
# branch its leading edge (shared with the previous sibling). rc 1 = nothing moved.
_tui_resize.grow() {
	local node="$1" axis="$2" d="$3" own="${4:-0}" first="" first_i=0 first_n=0
	while _tui_resize.parent "$node"; do
		if [[ "${_TUI_P_DIR[$_RZ_P]}" == "$axis" ]]; then
			if ((own && _RZ_N > 1)); then
				if ((_RZ_I < _RZ_N - 1)); then
					_tui_resize.move "$_RZ_P" "$_RZ_I" "$d"
				else
					_tui_resize.move "$_RZ_P" "$((_RZ_I - 1))" "$((-d))"
				fi && _tui._layout root
				return
			fi
			if ((_RZ_I < _RZ_N - 1)); then
				_tui_resize.move "$_RZ_P" "$_RZ_I" "$d" && _tui._layout root # later axes read the new rects
				return
			fi
			[[ -n "$first" ]] || { first="$_RZ_P" first_i=$_RZ_I first_n=$_RZ_N; }
		fi
		node="$_RZ_P"
	done
	if [[ -n "$first" ]] && ((first_n > 1)); then
		_tui_resize.move "$first" "$((first_i - 1))" "$((-d))" && _tui._layout root
		return
	fi
	return 1
}

# ── commit: relayout, callbacks, repaint ──────────────────────────────────

# _tui_resize.snap - remember the size of every pane with an on_resize callback
_tui_resize.snap() {
	local p
	_RZ_SNAP=()
	for p in "${!_TUI_P_ON_RESIZE[@]}"; do _RZ_SNAP[$p]="${_TUI_P_W[$p]:-0}x${_TUI_P_H[$p]:-0}"; done
}

# _tui_resize.commit - lays out again, calls on_resize for the panes whose size changed, asks for a repaint
_tui_resize.commit() {
	local p cb
	_tui._layout root
	for p in "${!_RZ_SNAP[@]}"; do
		[[ "${_RZ_SNAP[$p]}" == "${_TUI_P_W[$p]:-0}x${_TUI_P_H[$p]:-0}" ]] && continue
		cb="${_TUI_P_ON_RESIZE[$p]:-}"
		[[ -n "$cb" ]] && declare -F "$cb" >/dev/null && "$cb" "$p" "${_TUI_P_W[$p]}" "${_TUI_P_H[$p]}"
	done
	tui.frame.request
}

# ── mouse ─────────────────────────────────────────────────────────────────

# _tui_resize.allows PANE AXIS - rc 0 when resizable permits AXIS (h = x, v = y)
_tui_resize.allows() {
	case "${_TUI_P_RESIZABLE[$1]:-}" in
		both) return 0 ;;
		x) [[ "$2" == h ]] ;;
		y) [[ "$2" == v ]] ;;
		*) return 1 ;;
	esac
}

declare -gi _TUI_RZ_ZONES=0

# _tui_resize.zones - (re)registers the handle / divider zones of every resizable pane that has a handle
# state:direct
_tui_resize.zones() {
	((${#_TUI_P_HANDLE[@]} || _TUI_RZ_ZONES)) || return 0
	local -a keep=()
	local i dirty=$_TUI_HZ_DIRTY
	for ((i = 0; i < ${#_TUI_HZ_EXTRA[@]}; i += _TUI_HZ_EXTRA_FIELDS)); do
		[[ "${_TUI_HZ_EXTRA[i + 2]}" == rz-* ]] || keep+=("${_TUI_HZ_EXTRA[@]:i:_TUI_HZ_EXTRA_FIELDS}")
	done
	_TUI_HZ_EXTRA=("${keep[@]}")
	_TUI_RZ_ZONES=0
	local p kind r c h w
	for p in "${_TUI_P_ALL[@]}"; do
		kind="${_TUI_P_HANDLE[$p]:-}"
		[[ -n "$kind" && -n "${_TUI_P_RESIZABLE[$p]:-}" ]] || continue
		r=${_TUI_P_ROW[$p]:-0} c=${_TUI_P_COL[$p]:-0} h=${_TUI_P_H[$p]:-0} w=${_TUI_P_W[$p]:-0}
		((h < 1 || w < 1)) && continue
		_TUI_RZ_ZONES=1
		if [[ "$kind" == corner ]]; then
			_tui_hit.extra_add handle "$p" rz-corner "$((r + h - 1))" "$((c + w - 1))" 1 1
			continue
		fi
		_tui_resize.parent "$p" && ((_RZ_N > 1)) || continue
		if ((_RZ_I < _RZ_N - 1)); then # trailing border, shared with the next sibling
			if [[ "${_TUI_P_DIR[$_RZ_P]}" == h ]]; then
				_tui_resize.allows "$p" h && _tui_hit.extra_add "${kind/edge/handle}" "$p" rz-h "$r" "$((c + w - 1))" "$h" 1
			else
				_tui_resize.allows "$p" v && _tui_hit.extra_add "${kind/edge/handle}" "$p" rz-v "$((r + h - 1))" "$c" 1 "$w"
			fi
		elif [[ "${_TUI_P_DIR[$_RZ_P]}" == h ]]; then # the last pane: leading border, shared with the previous sibling
			_tui_resize.allows "$p" h && _tui_hit.extra_add "${kind/edge/handle}" "$p" rz-hl "$r" "$c" "$h" 1
		else
			_tui_resize.allows "$p" v && _tui_hit.extra_add "${kind/edge/handle}" "$p" rz-vl "$r" "$c" 1 "$w"
		fi
	done
	_TUI_HZ_DIRTY=$dirty
}

# _tui_resize.seg_buf PANE ARG - appends a repaint of the border segment of zone PANE|ARG (a handle / divider /
# corner): its cells with the pane's border glyphs, the ring colour at rest, theme class .resize_handle:hover (default
# bold white) while _TUI_HZ_HOVER names it. Title tag cells and nothing outside the zone are touched.
# state:direct
_tui_resize.seg_buf() {
	local p="$1" arg="$2" zr zc zh zw pr pc ph pw y x g b ov="" t0=0 t1=-1 hov=0 st=border
	pr=${_TUI_P_ROW[$p]:-0} pc=${_TUI_P_COL[$p]:-0} ph=${_TUI_P_H[$p]:-0} pw=${_TUI_P_W[$p]:-0}
	((ph < 1 || pw < 1)) && return 0
	case "$arg" in # the zone's rect from the pane's current rect (the zone table lags a drag until the next lookup)
		rz-h) zr=$pr zc=$((pc + pw - 1)) zh=$ph zw=1 ;;
		rz-hl) zr=$pr zc=$pc zh=$ph zw=1 ;;
		rz-v) zr=$((pr + ph - 1)) zc=$pc zh=1 zw=$pw ;;
		rz-vl) zr=$pr zc=$pc zh=1 zw=$pw ;;
		rz-corner) zr=$((pr + ph - 1)) zc=$((pc + pw - 1)) zh=1 zw=1 ;;
		*) return 0 ;;
	esac
	_tui._eff_border "$p"
	[[ "$_TB" == none ]] && return 0
	b=$_TB
	if [[ "${_TUI_P_FUSE[$p]:-}" == true ]]; then # the shared line takes the divider style of the later pane
		ov="${_TUI_P_DIVIDER[$p]:-}"
		if [[ "$arg" == @(rz-h|rz-v) ]] && _tui_resize.parent "$p"; then
			local -a ch
			read -ra ch <<<"${_TUI_P_CHILDREN[$_RZ_P]}"
			ov="${_TUI_P_DIVIDER[${ch[_RZ_I + 1]}]:-$ov}"
		fi
	fi
	_tui_canvas.glyphs "${ov:-$b}"
	local tl=$_TC_TL tr=$_TC_TR bl=$_TC_BL br=$_TC_BR hz=$_TC_HZ vt=$_TC_VT
	if ((zh == 1)) && [[ -n "${_TUI_P_TITLE[$p]:-}" ]]; then # a title on this row stays
		local ty=$pr
		[[ "${_TUI_P_TITLE_POS[$p]:-top}" == bottom ]] && ty=$((pr + ph - 1))
		if ((zr == ty)); then _tui_frame.title_span "$p" && t0=$_TS0 t1=$_TS1; fi
	fi
	[[ "$_TUI_HZ_HOVER" == "$p|$arg" ]] && hov=1
	[[ "$_TUI_PANE_FOCUS" == "$p" || -n "$_TUI_FOCUS_ID" && "${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}" == "$p" ]] && st=focus
	if ((hov)) && _tui_hit.class_sgr resize_handle 1 "$p"; then
		_tui.emit "$_SGR"
	elif ((hov)); then
		_tui.emit $'\e[1;97m'
	else _tui.emit_ring "${p}_${st}" "${p}_border" "$p"; fi
	for ((y = zr; y < zr + zh; y++)); do
		for ((x = zc; x < zc + zw; x++)); do
			((x >= t0 && x <= t1)) && continue
			if ((y == pr)); then
				g=$hz
				((x == pc)) && g=$tl
				((x == pc + pw - 1)) && g=$tr
			elif ((y == pr + ph - 1)); then
				g=$hz
				((x == pc)) && g=$bl
				((x == pc + pw - 1)) && g=$br
			else g=$vt; fi
			_tui.emit_goto "$y" "$x"
			_tui.emit "$g"
		done
	done
	_tui.emit_reset
}

# _tui_resize.now -> _RZ_T (microseconds; tests override this)
_tui_resize.now() { _RZ_T=${EPOCHREALTIME//[!0-9]/}; }

# _tui_resize.drag DX DY - moves the dragged border by the pointer's offset from its anchor; the anchor follows the
# border by what actually moved, so a clamped drag does not run ahead of the pointer
_tui_resize.drag() {
	local id="$_TUI_RZ_ID" arg="$_TUI_RZ_ARG" dx=$1 dy=$2 before
	_tui_resize.snap
	local moved=1
	if [[ "$arg" == rz-hl ]] && ((dx != 0)) && _tui_resize.allows "$id" h; then # leading border: the pane grows as it moves left
		_ps.panes.get "$id" w
		before=$_V
		if _tui_resize.grow "$id" h "$((-dx))" 1; then
			moved=0
			((_TUI_RZ_X -= _TUI_P_W[$id] - before))
		fi
	fi
	if [[ "$arg" == rz-vl ]] && ((dy != 0)) && _tui_resize.allows "$id" v; then
		_ps.panes.get "$id" h
		before=$_V
		if _tui_resize.grow "$id" v "$((-dy))" 1; then
			moved=0
			((_TUI_RZ_Y -= _TUI_P_H[$id] - before))
		fi
	fi
	if [[ "$arg" == rz-h || "$arg" == rz-corner ]] && ((dx != 0)) && _tui_resize.allows "$id" h; then
		_ps.panes.get "$id" w
		before=$_V
		if _tui_resize.grow "$id" h "$dx"; then
			moved=0
			((_TUI_RZ_X += _TUI_P_W[$id] - before))
		fi
	fi
	if [[ "$arg" == rz-v || "$arg" == rz-corner ]] && ((dy != 0)) && _tui_resize.allows "$id" v; then
		_ps.panes.get "$id" h
		before=$_V
		if _tui_resize.grow "$id" v "$dy"; then
			moved=0
			((_TUI_RZ_Y += _TUI_P_H[$id] - before))
		fi
	fi
	((moved == 0)) && _tui_resize.commit
	return 0
}

# _tui_resize.mouse NAME X Y - the pointer hook of _tui_input.mouse_event: press on a zone starts a drag (a second
# press within 0.4 s resets the pane), drag moves the border, release ends it. rc 0 = the event was consumed.
_tui_resize.mouse() {
	case "$1" in
		mouse:left)
			[[ "$_HIT_ARG" == rz-* ]] || return 1
			_tui_resize.now
			if [[ "$_TUI_RZ_LAST_ID" == "$_HIT_ID" && "$_TUI_RZ_LAST_ARG" == "$_HIT_ARG" ]] && ((_RZ_T - _TUI_RZ_LAST_T <= _TUI_RZ_DOUBLE_US)); then
				_TUI_RZ_LAST_ID="" _TUI_RZ_ID=""
				tui.resize.reset "$_HIT_ID"
				return 0
			fi
			_TUI_RZ_LAST_ID="$_HIT_ID" _TUI_RZ_LAST_ARG="$_HIT_ARG" _TUI_RZ_LAST_T=$_RZ_T
			_TUI_RZ_ID="$_HIT_ID" _TUI_RZ_ARG="$_HIT_ARG" _TUI_RZ_X=$2 _TUI_RZ_Y=$3
			return 0
			;;
		drag:left)
			[[ -n "$_TUI_RZ_ID" ]] || return 1
			_tui_resize.drag "$(($2 - _TUI_RZ_X))" "$(($3 - _TUI_RZ_Y))"
			return 0
			;;
		release)
			[[ -n "$_TUI_RZ_ID" ]] || return 1
			_TUI_RZ_ID=""
			_tui_hit.hover # the drag is over: the border is only hovered if the pointer is still on it
			return 0
			;;
	esac
	return 1
}

# ── keyboard ──────────────────────────────────────────────────────────────

# _tui_resize.find - the pane resize mode would act on -> _RZ_P: the focused pane or its nearest resizable ancestor;
# when there is none (focus in the prompt pane, nothing focused) the first resizable pane of the page in layout order
_tui_resize.find() {
	local p
	_tui_input.pane_current
	p="$_PC"
	while [[ -n "$p" ]]; do
		[[ -n "${_TUI_P_RESIZABLE[$p]:-}" ]] && {
			_RZ_P="$p"
			return 0
		}
		_tui_resize.parent "$p" || break
		p="$_RZ_P"
	done
	for p in "${_TUI_P_ALL[@]}"; do
		[[ -n "${_TUI_P_RESIZABLE[$p]:-}" ]] && {
			_RZ_P="$p"
			return 0
		}
	done
	return 1
}

# _tui_resize.can_enter - rc 0 when a resizable pane exists and none is in resize mode (footer predicate).
_tui_resize.can_enter() { [[ -z "$_TUI_RESIZE_PANE" ]] && ((${#_TUI_P_RESIZABLE[@]})) && _tui_resize.find; }

# _tui_resize.in_mode - rc 0 when a pane is in keyboard resize mode.
_tui_resize.in_mode() { [[ -n "$_TUI_RESIZE_PANE" ]]; }

declare -g _TUI_RZ_TITLE="" # the target pane's title as it was before the mode added its " [resize]" tag
declare -g _TUI_RZ_TAG=" [resize]"

# _tui_resize.enter PANE - enters resize mode: pane's title gets the "[resize]" tag and border is highlighted.
_tui_resize.enter() {
	_TUI_RESIZE_PANE="$1"
	_TUI_RZ_TITLE="${_TUI_P_TITLE[$1]:-}"
	_ps.panes.set "$1" title "${_TUI_RZ_TITLE}${_TUI_RZ_TAG}"
	_TUI_HZ_DIRTY=1
}

# _tui_resize.leave - exits resize mode: restores pane's title if unchanged since entering.
_tui_resize.leave() {
	local p="$_TUI_RESIZE_PANE"
	[[ -n "$p" ]] || return 0
	[[ "${_TUI_P_TITLE[$p]:-}" == "${_TUI_RZ_TITLE}${_TUI_RZ_TAG}" ]] && _TUI_P_TITLE[$p]="$_TUI_RZ_TITLE"
	_TUI_RESIZE_PANE="" _TUI_RZ_TITLE=""
	_TUI_HZ_DIRTY=1
}

# tui.action.resize_mode - alt+r: enters resize mode on the focused pane's nearest resizable ancestor (else the first
# resizable pane of the page); again leaves it. Nothing resizable: a toast and rc 1.
tui.action.resize_mode() {
	if [[ -n "$_TUI_RESIZE_PANE" ]]; then
		_tui_resize.leave
	else
		_tui_resize.find || {
			tui.notify "Nothing resizable here" warn
			return 1
		}
		_tui_resize.enter "$_RZ_P"
	fi
	tui.frame.request
}

# _tui_resize.key NAME [COUNT] - the keyboard hook of _tui_input.key_event while the mode is on; rc 0 = the key was
# consumed. COUNT identical presses the input loop merged (_tui_input.coalesce) move the border COUNT times as far in
# one step, so a held arrow costs one layout and one frame per batch, not per repeat.
_tui_resize.key() {
	local n=1 id="$_TUI_RESIZE_PANE" cnt="${2:-1}"
	case "$1" in
		enter | esc)
			_tui_resize.leave
			tui.frame.request
			return 0
			;;
		shift+*) n=5 ;;
	esac
	local ax=h sign=1 moved=1 i
	case "${1#shift+}" in
		left) sign=-1 ;;
		right) ;;
		up) ax=v sign=-1 ;;
		down) ax=v ;;
		*) return 1 ;;
	esac
	_tui_resize.allows "$id" "$ax" || return 0
	_tui_resize.snap
	# COUNT merged presses = COUNT single steps (the weights round per step, so one big move could land a cell off), but
	# one commit: one repaint for the whole batch
	for ((i = 0; i < cnt; i++)); do
		_tui_resize.grow "$id" "$ax" "$((sign * n))" 1 && moved=0 || break
	done
	((moved == 0)) && _tui_resize.commit
	return 0
}
