#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_build.sh                                                         ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui_build.build ROOT   walks the node tree tui_parse.sh produced (ROOT is
#                        tui.parse.file's _P_ROOT) and dispatches every node
#                        to its registered "tag" handler (lib/tui_registry.sh),
#                        calling the same tui.* builder API tui_markup.sh's
#                        old per-line case dispatch called.
#
# Markup-v2 stage 1.2: each `case` branch tui_markup.sh's tui.load loop used
# to run per line now lives as one `_tui_build.tag.<name>` handler,
# registered under the "tag" registry kind instead of hard-coded in a
# switch - a plugin can add a handler for a new tag with tui.register tag
# the same way. Nesting is now the real parse tree (0.5/1.1), not a manual
# stack of (id, split-direction) pairs: a pane's split-member list is just
# its pane-typed children, in document order, and a <tabs>'s <tab> children
# are read directly instead of being stashed between open and close.
#
# Nested widgets (new): a widget with no explicit pane=/row= that is a child
# of a <pane> (or a row/col/group helper tag, all pane aliases) is built
# into that pane, at a row inferred from its position among that pane's
# non-pane children. Legacy `pane="…" row="…"` still wins when given -
# every existing page uses only the explicit form and is unaffected.

declare -gA _TUI_BUILD_TITLE=()  # pane id -> title, applied once every split is done (see tui_build.build)
declare -gA _TUI_BUILD_BORDER=() # pane id -> border, same reason
declare -g _TUI_BUILD_ON_VISIT=""
declare -gi _TUI_BUILD_AUTO_N=0
declare -g _TUI_BUILD_CTX_PANE="" # nearest enclosing pane id, for nested-widget pane inference
declare -gi _TUI_BUILD_CTX_ROW=0  # inferred row within that pane
declare -g _TUI_BUILD_LAST_ID=""  # set by the pane handler: the id it built, read by its caller

# _tui_build.attr NODE NAME -> stdout : one attribute's value, or empty.
# Same shape as tui_markup.sh's old `_markup_attr "$line" NAME` so a case
# body moved here needed only `"$line"` -> `"$node"` at each call site.
# Forks in a `$(...)` capture - fine for the widget handlers (one node
# each), but a pane handler reads ~20 of these per node, so the pane
# handler itself uses _tui_build.attrv (below) instead: same lookup with no
# fork, a var name instead of stdout.
_tui_build.attr() {
	tui_node.attr_get "$1" "$2" && printf '%s' "$_N_ATTR_V"
	return 0
}

# _tui_build.attrv NODE NAME VARNAME - like _tui_build.attr, but assigns
# into VARNAME (a nameref) instead of stdout: no `$(...)` fork.
_tui_build.attrv() {
	local -n _bv_out="$3"
	tui_node.attr_get "$1" "$2" && _bv_out="$_N_ATTR_V" || _bv_out=""
}

_tui_build.auto_id() {
	printf '_auto_%s_%d' "$1" "$((++_TUI_BUILD_AUTO_N))"
}

# tui_build.build ROOT - builds every node under ROOT (tui.parse.file's
# _P_ROOT). Title/border are applied last, after every split call, so a
# split's own default border/title reset (_tui._split) never clobbers a
# user-declared one - same two-pass shape the old tui.load used.
tui_build.build() {
	_TUI_BUILD_TITLE=()
	_TUI_BUILD_BORDER=()
	_TUI_BUILD_ON_VISIT=""
	_TUI_BUILD_AUTO_N=0
	_TUI_BUILD_CTX_PANE=""
	_TUI_BUILD_CTX_ROW=0
	_tui_build.dispatch_children "$1"

	local pid
	for pid in "${!_TUI_BUILD_TITLE[@]}"; do tui.pane_title "$pid" "${_TUI_BUILD_TITLE[$pid]}"; done
	for pid in "${!_TUI_BUILD_BORDER[@]}"; do tui.pane_border "$pid" "${_TUI_BUILD_BORDER[$pid]}"; done
}

_tui_build.dispatch_children() {
	tui_node.children "$1"
	local -a kids=("${_N_CHILDREN[@]}")
	local k
	for k in "${kids[@]}"; do _tui_build.dispatch "$k"; done
}

_tui_build.dispatch() {
	local node="$1" type="${_N_TYPE[$1]}"
	tui.registered tag "$type" || return 0
	local fn="${_TUI_REGISTERED##* }" # last registration wins, same rule as every other registry kind
	"$fn" "$node"
	case "$type" in label | input | button | checkbox | password | textarea | list | table | select | progress) _tui_build.focus_attrs "$node" ;; esac
}

# focus and hit attributes shared by every widget tag (see lib/input/tui_focus.sh, tui_hit.sh)
_tui_build.focus_attrs() {
	local node="$1" id a v
	_tui_build.attrv "$node" id id
	[[ -n "$id" ]] || return 0
	for a in focusable tabbable tab_order focus_group focus_nav focus_wrap focus_next focus_prev autofocus; do
		_tui_build.attrv "$node" "$a" v
		[[ -n "$v" ]] && tui.focus.set "$id" "$a" "$v"
	done
	for a in hit_pad hitbox; do
		_tui_build.attrv "$node" "$a" v
		[[ -n "$v" ]] && tui.hit.set "$id" "$a" "$v"
	done
	return 0
}

# ── <tui> / <script> / <theme> ─────────────────────────────────────────────

_tui_build.tag.tui() {
	local node="$1"
	local visit
	_tui_build.attrv "$node" on_visit visit
	[[ -n "$visit" ]] && _TUI_BUILD_ON_VISIT="$visit"
	local ddef dg fwrap
	local -a dgs=()
	_tui_build.attrv "$node" focus_wrap fwrap
	[[ "$fwrap" == false ]] && _TUI_FOCUS_WRAP=0
	_tui_build.attrv "$node" defaults ddef
	if [[ -n "$ddef" ]]; then
		IFS=',' read -ra dgs <<<"$ddef"
		for dg in "${dgs[@]}"; do [[ "$dg" == -* ]] && tui.defaults.off --page "${dg#-}"; done
	fi
	_tui_build.dispatch_children "$node" # <tui> is a transparent wrapper: its children build at the same level
}

_tui_build.tag.script() {
	local node="$1" src resolved
	_tui_build.attrv "$node" src src
	[[ -z "$src" ]] && return 0
	resolved="$src"
	[[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR}/${src}"
	_tui_cache_source "$resolved"
}

_tui_build.tag.theme() {
	local node="$1" tsrc tresolved
	_tui_build.attrv "$node" src tsrc
	[[ -z "$tsrc" ]] && return 0
	tresolved="$tsrc"
	[[ "$tresolved" != /* ]] && tresolved="${_TUI_MARKUP_DIR}/${tsrc}"
	_tui_cache_theme "$tresolved"
}

tui.register tag tui _tui_build.tag.tui
tui.register tag script _tui_build.tag.script
tui.register tag theme _tui_build.tag.theme

# ── <pane> and its row/col/spacer/divider/group aliases ───────────────────

# A pane node's split member list is exactly its pane-typed children (in
# document order): each carries its own weight (plain split), grid_row/
# grid_col (split="grid") or span/newline (split="fixed"). Built post-order
# so a nested pane's own split call runs before its parent's, matching the
# old bottom-up (child closes before parent) order.
_tui_build.tag.pane() {
	local node="$1" id
	_tui_build.attrv "$node" id id
	if [[ -z "$id" ]]; then
		printf -v id \'_auto_%s_%d\' pane "$((++_TUI_BUILD_AUTO_N))"
		_N_ID[$node]="$id"
	fi

	local split weight title border align valign minw minh maxw maxh class scroll strictfit
	local rows cols fit roww colw sizew sizeh hpad vpad gap
	_tui_build.attrv "$node" split split
	_tui_build.attrv "$node" weight weight
	_tui_build.attrv "$node" title title
	_tui_build.attrv "$node" border border
	_tui_build.attrv "$node" align align
	_tui_build.attrv "$node" valign valign
	_tui_build.attrv "$node" min_width minw
	_tui_build.attrv "$node" min_height minh
	_tui_build.attrv "$node" max_width maxw
	_tui_build.attrv "$node" max_height maxh
	_tui_build.attrv "$node" class class
	_tui_build.attrv "$node" scroll scroll
	_tui_build.attrv "$node" strict_fit strictfit
	_tui_build.attrv "$node" rows rows
	_tui_build.attrv "$node" cols cols
	_tui_build.attrv "$node" fit fit
	_tui_build.attrv "$node" row_weights roww
	_tui_build.attrv "$node" col_weights colw
	_tui_build.attrv "$node" size_w sizew
	_tui_build.attrv "$node" size_h sizeh
	_tui_build.attrv "$node" hpad hpad
	_tui_build.attrv "$node" vpad vpad
	_tui_build.attrv "$node" gap gap

	[[ -n "$title" ]] && _TUI_BUILD_TITLE[$id]="$title"
	[[ -n "$border" ]] && _TUI_BUILD_BORDER[$id]="$border"
	tui.pane_align "$id" "$align"
	tui.pane_valign "$id" "$valign"
	tui.pane_minsize "$id" "$minw" "$minh"
	tui.pane_maxsize "$id" "$maxw" "$maxh"
	tui.pane_pad "$id" "$hpad" "$vpad"
	tui.pane_gap "$id" "$gap"
	_tui_cache_class "$id" "$class"
	tui.pane_scroll "$id" "$scroll"
	[[ -n "$strictfit" ]] && tui.pane_strict_fit "$id" "$strictfit"

	tui_node.children "$node"
	local -a kids=("${_N_CHILDREN[@]}")
	local k ctype pending="" row=0 # the first widget in a pane sits on its first line (rows count from 0, as in an explicit row="0")
	for k in "${kids[@]}"; do
		ctype="${_N_TYPE[$k]}"
		case "$ctype" in
			pane | row | col | spacer | divider | group)
				_tui_build.dispatch "$k"
				local cid="$_TUI_BUILD_LAST_ID"
				if [[ "$split" == "grid" ]]; then
					local cgr cgc
					_tui_build.attrv "$k" grid_row cgr
					_tui_build.attrv "$k" grid_col cgc
					pending="${pending:+$pending }${cid}:${cgr:--}:${cgc:--}"
				elif [[ "$split" == "fixed" ]]; then
					local cspan cnl
					_tui_build.attrv "$k" span cspan
					_tui_build.attrv "$k" newline cnl
					pending="${pending:+$pending }${cid}:${cspan:-1}:${cnl:+1}"
				else
					# Size spec for this child on the split's own axis: an explicit
					# width= (h split) / height= (v split) wins - a 2A unit token
					# (N%, Nfr, auto, fill, clamp(...)) - else the legacy weight=
					# (plain integer, "maps to fr" per the plan: _tui.layout_arrange
					# treats a bare integer exactly like an "Nfr" token).
					local cw cweight
					_tui_build.attrv "$k" weight cweight
					if [[ "$split" == "v" ]]; then
						_tui_build.attrv "$k" height cw
					else
						_tui_build.attrv "$k" width cw
					fi
					pending="${pending:+$pending }${cid}:${cw:-${cweight:-1}}"
				fi
				;;
			*)
				_TUI_BUILD_CTX_PANE="$id"
				_TUI_BUILD_CTX_ROW=$row
				_tui_build.dispatch "$k"
				((row++))
				;;
		esac
	done

	if [[ "$split" == "grid" ]]; then
		_tui_build.resolve_grid "$id" "$pending" "$rows" "$cols" "$fit" "$roww" "$colw"
	elif [[ "$split" == "fixed" ]]; then
		tui.fixed "$id" "${sizew:-4}" "${sizeh:-3}" $pending
	elif [[ -n "$pending" ]]; then
		if [[ "$split" == "v" ]]; then tui.vsplit "$id" $pending; else tui.hsplit "$id" $pending; fi
	fi
	_TUI_BUILD_LAST_ID="$id"
}

# _tui_build.resolve_grid ID PENDING ROWS COLS FIT ROWW COLW - same
# explicit-cells-first-then-loose-fill placement as the old
# _tui_markup_resolve_grid, just taking its inputs as arguments (the tree
# already has them) instead of reading them back out of stash arrays.
_tui_build.resolve_grid() {
	local id="$1" pending="$2" rows="$3" cols="$4" fit="${5:-pack}" roww="$6" colw="$7"
	local -a entries=()
	read -ra entries <<<"$pending"
	local total=${#entries[@]}

	if ((total == 0)); then
		tui.grid "$id" "${rows:-1}" "${cols:-1}" "$fit" "$roww" "$colw"
		return
	fi

	if [[ -z "$cols" && -z "$rows" ]]; then
		cols=$(_tui._ceil_sqrt "$total")
		rows=$(((total + cols - 1) / cols))
	elif [[ -z "$cols" ]]; then
		cols=$(((total + rows - 1) / rows))
	elif [[ -z "$rows" ]]; then
		rows=$(((total + cols - 1) / cols))
	fi
	((rows < 1)) && rows=1
	((cols < 1)) && cols=1

	local total_cells=$((rows * cols))
	local -a flat=()
	local i
	for ((i = 0; i < total_cells; i++)); do flat[i]=""; done

	local -a loose=()
	local entry cid gr gc
	for entry in "${entries[@]}"; do
		IFS=: read -r cid gr gc <<<"$entry"
		[[ "$gr" == "-" ]] && gr=""
		[[ "$gc" == "-" ]] && gc=""
		if [[ -n "$gr" && -n "$gc" ]]; then
			local ci=$((gr * cols + gc))
			if ((ci >= 0 && ci < total_cells)); then
				if [[ -n "${flat[$ci]}" ]]; then
					echo "tui.load: grid '$id' cell (${gr},${gc}) already occupied by '${flat[$ci]}' - '$cid' overrides it" >&2
				fi
				flat[ci]="$cid"
			else
				echo "tui.load: grid '$id' child '$cid' grid_row/grid_col out of bounds - treating as loose" >&2
				loose+=("$cid")
			fi
		else
			loose+=("$cid")
		fi
	done

	local li=0
	for ((i = 0; i < total_cells && li < ${#loose[@]}; i++)); do
		if [[ -z "${flat[$i]}" ]]; then
			flat[i]="${loose[$li]}"
			((li++))
		fi
	done
	while ((li < ${#loose[@]})); do
		((rows++))
		local base=$(((rows - 1) * cols)) c
		for ((c = 0; c < cols && li < ${#loose[@]}; c++)); do
			flat[$((base + c))]="${loose[$li]}"
			((li++))
		done
	done

	tui.grid "$id" "$rows" "$cols" "$fit" "$roww" "$colw" "${flat[@]}"
}

tui.register tag pane _tui_build.tag.pane

# Helper tags: an alias table mapping to <pane> plus one forced attribute -
# row/col fix the split direction, group is a plain (unsplit) wrapper pane,
# spacer/divider are borderless/bordered leaf panes respectively.
_tui_build.tag.row() {
	tui_node.attr_get "$1" split || tui_node.attr_set "$1" split h
	_tui_build.tag.pane "$1"
}
_tui_build.tag.col() {
	tui_node.attr_get "$1" split || tui_node.attr_set "$1" split v
	_tui_build.tag.pane "$1"
}
_tui_build.tag.group() { _tui_build.tag.pane "$1"; }
_tui_build.tag.spacer() { _tui_build.tag.pane "$1"; }
_tui_build.tag.divider() {
	tui_node.attr_get "$1" border || tui_node.attr_set "$1" border single
	_tui_build.tag.pane "$1"
}
tui.register tag row _tui_build.tag.row
tui.register tag col _tui_build.tag.col
tui.register tag group _tui_build.tag.group
tui.register tag spacer _tui_build.tag.spacer
tui.register tag divider _tui_build.tag.divider

# ── widgets ─────────────────────────────────────────────────────────────
# Every widget handler resolves pane/row the same way: an explicit
# pane="…"/row="…" attribute wins (legacy pages, always); otherwise it
# falls back to the nearest enclosing pane and its inferred row (nested
# widgets, new in 1.2 - see tui_build.build's doc comment).

# _tui_build.pane_ofv NODE VAR / row_ofv NODE VAR - pane_of / row_of into VAR, no `$(...)` fork (they were two forks each)
_tui_build.pane_ofv() {
	local -n _po_out="$2"
	tui_node.attr_get "$1" pane && _po_out="$_N_ATTR_V" || _po_out=""
	_po_out="${_po_out:-$_TUI_BUILD_CTX_PANE}"
}
_tui_build.row_ofv() {
	local -n _ro_out="$2"
	tui_node.attr_get "$1" row && _ro_out="$_N_ATTR_V" || _ro_out=""
	_ro_out="${_ro_out:-$_TUI_BUILD_CTX_ROW}"
}
_tui_build.pane_of() {
	local v
	_tui_build.attrv "$1" pane v
	printf '%s' "${v:-$_TUI_BUILD_CTX_PANE}"
}
_tui_build.row_of() {
	local v
	_tui_build.attrv "$1" row v
	printf '%s' "${v:-$_TUI_BUILD_CTX_ROW}"
}

_tui_build.tag.label() {
	local node="$1"
	local lid lpane lrow lalign lvalign lminw lmaxw lclass
	_tui_build.attrv "$node" id lid
	_tui_build.pane_ofv "$node" lpane
	_tui_build.row_ofv "$node" lrow
	_tui_build.attrv "$node" align lalign
	_tui_build.attrv "$node" valign lvalign
	_tui_build.attrv "$node" min_width lminw
	_tui_build.attrv "$node" max_width lmaxw
	_tui_build.attrv "$node" class lclass
	local ltext
	_tui_build.attrv "$node" text ltext
	tui.label "$lid" "$lpane" "$lrow" "$ltext"
	tui.align "$lid" "$lalign"
	tui.valign "$lid" "$lvalign"
	tui.minsize "$lid" "$lminw"
	tui.maxsize "$lid" "$lmaxw"
	local lwidth lheight lpadding
	_tui_build.attrv "$node" width lwidth
	_tui_build.attrv "$node" height lheight
	_tui_build.attrv "$node" padding lpadding
	[[ -n "$lwidth" ]] && tui.width "$lid" "$lwidth"
	[[ -n "$lheight" ]] && tui.height "$lid" "$lheight"
	_tui_cache_class "$lid" "$lclass"
	local lhpad lvpad
	_tui_build.attrv "$node" hpad lhpad
	_tui_build.attrv "$node" vpad lvpad
	tui.pad "$lid" "${lhpad:-$lpadding}" "${lvpad:-$lpadding}"
}
tui.register tag label _tui_build.tag.label

_tui_build.tag.input() {
	local node="$1"
	local iid ipane irow ialign ivalign iminw imaxw ilalign ilwidth iclass
	_tui_build.attrv "$node" id iid
	_tui_build.pane_ofv "$node" ipane
	_tui_build.row_ofv "$node" irow
	_tui_build.attrv "$node" align ialign
	_tui_build.attrv "$node" valign ivalign
	_tui_build.attrv "$node" min_width iminw
	_tui_build.attrv "$node" max_width imaxw
	_tui_build.attrv "$node" label_align ilalign
	_tui_build.attrv "$node" label_width ilwidth
	_tui_build.attrv "$node" class iclass
	local iminh imaxh iexpand
	_tui_build.attrv "$node" min_height iminh
	_tui_build.attrv "$node" max_height imaxh
	_tui_build.attrv "$node" expand iexpand
	local iph ilabel isubmit
	_tui_build.attrv "$node" placeholder iph
	_tui_build.attrv "$node" label ilabel
	_tui_build.attrv "$node" submit isubmit
	tui.input "$iid" "$ipane" "$irow" "$iph" "$ilabel" "$isubmit"
	tui.align "$iid" "$ialign"
	tui.valign "$iid" "$ivalign"
	tui.minsize "$iid" "$iminw" "$iminh"
	tui.maxsize "$iid" "$imaxw" "$imaxh"
	[[ -n "$iexpand" ]] && tui.expand "$iid" "$iexpand"
	local iwidth iheight ipadding
	_tui_build.attrv "$node" width iwidth
	_tui_build.attrv "$node" height iheight
	_tui_build.attrv "$node" padding ipadding
	[[ -n "$iwidth" ]] && tui.width "$iid" "$iwidth"
	[[ -n "$iheight" ]] && tui.height "$iid" "$iheight"
	tui.label_align "$iid" "$ilalign"
	tui.label_width "$iid" "$ilwidth"
	local iretain
	_tui_build.attrv "$node" retain_input_on_submit iretain
	[[ -n "$iretain" ]] && tui.input.retain "$iid" "$iretain"
	local isticky
	_tui_build.attrv "$node" sticky isticky
	[[ "$isticky" == true ]] && tui.input.sticky "$iid"
	_tui_cache_class "$iid" "$iclass"
	local ihpad ivpad
	_tui_build.attrv "$node" hpad ihpad
	_tui_build.attrv "$node" vpad ivpad
	tui.pad "$iid" "${ihpad:-$ipadding}" "${ivpad:-$ipadding}"
}
tui.register tag input _tui_build.tag.input

_tui_build.tag.button() {
	local node="$1"
	local bid bpane brow btext baction bpage balign bvalign bminw bmaxw bclass
	_tui_build.attrv "$node" id bid
	_tui_build.pane_ofv "$node" bpane
	_tui_build.row_ofv "$node" brow
	_tui_build.attrv "$node" text btext
	_tui_build.attrv "$node" action baction
	_tui_build.attrv "$node" page bpage
	_tui_build.attrv "$node" align balign
	_tui_build.attrv "$node" valign bvalign
	_tui_build.attrv "$node" min_width bminw
	_tui_build.attrv "$node" max_width bmaxw
	_tui_build.attrv "$node" class bclass
	local bminh bmaxh bexpand
	_tui_build.attrv "$node" min_height bminh
	_tui_build.attrv "$node" max_height bmaxh
	_tui_build.attrv "$node" expand bexpand

	if [[ -n "$bpage" && -z "$baction" ]]; then
		local fn="_tui_goto_${bid//[^A-Za-z0-9_]/_}"
		_tui_cache_define_goto "$fn" "$bpage" "$btext"
		baction="$fn"
	fi

	tui.button "$bid" "$bpane" "$brow" "$btext" "$baction"
	tui.align "$bid" "$balign"
	tui.valign "$bid" "$bvalign"
	tui.minsize "$bid" "$bminw" "$bminh"
	tui.maxsize "$bid" "$bmaxw" "$bmaxh"
	[[ -n "$bexpand" ]] && tui.expand "$bid" "$bexpand"
	local bwidth bheight bpadding
	_tui_build.attrv "$node" width bwidth
	_tui_build.attrv "$node" height bheight
	_tui_build.attrv "$node" padding bpadding
	[[ -n "$bwidth" ]] && tui.width "$bid" "$bwidth"
	[[ -n "$bheight" ]] && tui.height "$bid" "$bheight"
	_tui_cache_class "$bid" "$bclass"
	local bhpad bvpad
	_tui_build.attrv "$node" hpad bhpad
	_tui_build.attrv "$node" vpad bvpad
	tui.pad "$bid" "${bhpad:-$bpadding}" "${bvpad:-$bpadding}"
}
tui.register tag button _tui_build.tag.button

_tui_build.tag.checkbox() {
	local node="$1"
	local kid kpane krow klabel kchecked kaction kalign kvalign kminw kmaxw kclass
	_tui_build.attrv "$node" id kid
	_tui_build.pane_ofv "$node" kpane
	_tui_build.row_ofv "$node" krow
	_tui_build.attrv "$node" label klabel
	_tui_build.attrv "$node" checked kchecked
	_tui_build.attrv "$node" action kaction
	_tui_build.attrv "$node" align kalign
	_tui_build.attrv "$node" valign kvalign
	_tui_build.attrv "$node" min_width kminw
	_tui_build.attrv "$node" max_width kmaxw
	_tui_build.attrv "$node" class kclass
	local kminh kmaxh kexpand
	_tui_build.attrv "$node" min_height kminh
	_tui_build.attrv "$node" max_height kmaxh
	_tui_build.attrv "$node" expand kexpand

	tui.checkbox "$kid" "$kpane" "$krow" "$klabel" "$kchecked" "$kaction"
	tui.align "$kid" "$kalign"
	tui.valign "$kid" "$kvalign"
	tui.minsize "$kid" "$kminw" "$kminh"
	tui.maxsize "$kid" "$kmaxw" "$kmaxh"
	[[ -n "$kexpand" ]] && tui.expand "$kid" "$kexpand"
	local kwidth kheight kpadding
	_tui_build.attrv "$node" width kwidth
	_tui_build.attrv "$node" height kheight
	_tui_build.attrv "$node" padding kpadding
	[[ -n "$kwidth" ]] && tui.width "$kid" "$kwidth"
	[[ -n "$kheight" ]] && tui.height "$kid" "$kheight"
	_tui_cache_class "$kid" "$kclass"
	local khpad kvpad
	_tui_build.attrv "$node" hpad khpad
	_tui_build.attrv "$node" vpad kvpad
	tui.pad "$kid" "${khpad:-$kpadding}" "${kvpad:-$kpadding}"
}
tui.register tag checkbox _tui_build.tag.checkbox

# password/textarea/list/table/select/progress: still built by
# lib/widgets/tui_widgets.sh's _markup_wx (that file's, not this task's, to
# change) - it takes a raw attribute line, so one is reassembled from the
# node's own attributes rather than duplicating its five widget bodies here.
_tui_build.tag.wx() {
	local node="$1" type="${_N_TYPE[$1]}" line="<$type" k v
	for v in ${_N_ANAMES[$node]:-}; do
		[[ "$v" == __* ]] && continue
		k="${_N_ATTR["$node.$v"]}"
		line+=" $v=\"${k//\"/"&quot;"}\"" # quoted replacement: a bare & would stand for the matched quote (bash 5.2+)
	done
	line+="/>"
	local pane row
	_tui_build.pane_ofv "$node" pane
	_tui_build.row_ofv "$node" row
	[[ "$line" == *' pane='* ]] || line="${line/ $type/ $type pane=\"$pane\"}"
	[[ "$line" == *' row='* ]] || line="${line/ pane=/ row=\"$row\" pane=}"
	_markup_wx "$type" "$line"
}
tui.register tag password _tui_build.tag.wx
tui.register tag textarea _tui_build.tag.wx
tui.register tag list _tui_build.tag.wx
tui.register tag table _tui_build.tag.wx
tui.register tag select _tui_build.tag.wx
tui.register tag progress _tui_build.tag.wx

# ── page-level tags ─────────────────────────────────────────────────────

_tui_build.tag.footer() {
	local fitems
	_tui_build.attrv "$1" items fitems
	tui.footer.set "$fitems"
}
tui.register tag footer _tui_build.tag.footer

_tui_build.tag.bind() {
	local node="$1" bkey bact bpane_s bpass balways bdesc bscope
	_tui_build.attrv "$node" key bkey
	_tui_build.attrv "$node" action bact
	_tui_build.attrv "$node" pane bpane_s
	_tui_build.attrv "$node" pass bpass
	_tui_build.attrv "$node" always balways
	_tui_build.attrv "$node" desc bdesc
	_tui_build.attrv "$node" scope bscope
	local -a bflags=(--page)
	[[ "$bscope" == global ]] && bflags=()
	[[ -n "$bpane_s" ]] && bflags+=(--pane "$bpane_s")
	[[ "$bpass" == true ]] && bflags+=(--pass)
	[[ "$balways" == true ]] && bflags+=(--always)
	[[ -n "$bdesc" ]] && bflags+=(--desc "$bdesc")
	# A cache replay skips tag dispatch, so the bind is recorded with the page's other replayed calls
	# (see _tui_cache_define_goto); without it a cached page has none of its <bind>s.
	local _rec="tui.bind" _q _a
	for _a in "$bkey" "$bact" "${bflags[@]}"; do
		printf -v _q '%q' "$_a"
		_rec+=" $_q"
	done
	_TUI_CACHE_REC_GOTOS+=("$_rec")
	tui.bind "$bkey" "$bact" "${bflags[@]}"
}
tui.register tag bind _tui_build.tag.bind

# <tabs> children are read straight off the tree - no open/close stash
# needed now that the whole document is parsed up front.
_tui_build.tag.tabs() {
	local node="$1" tabsid thp tcp tstyle
	_tui_build.attrv "$node" id tabsid
	_tui_build.attrv "$node" header_pane thp
	_tui_build.attrv "$node" content_pane tcp
	_tui_build.attrv "$node" style tstyle
	[[ "$tstyle" == "compact" ]] && tui.tabs.compact "$tabsid" true

	tui_node.children "$node"
	local -a kids=("${_N_CHILDREN[@]}")
	local -a tab_ids=()
	local k
	for k in "${kids[@]}"; do
		[[ "${_N_TYPE[$k]}" == "tab" ]] || continue
		local tid tabtext tabaction tabdefault
		_tui_build.attrv "$k" id tid
		_tui_build.attrv "$k" text tabtext
		_tui_build.attrv "$k" action tabaction
		_tui_build.attrv "$k" default tabdefault
		tui.tabs.add "$tid" "$tabtext" "$tabaction" "$tabdefault"
		tab_ids+=("$tid")
	done
	tui.tabs.build "$tabsid" "$thp" "$tcp" "${tab_ids[@]}"
}
tui.register tag tabs _tui_build.tag.tabs
tui.register tag tab : # consumed by the tabs handler above; nothing to do standalone

# ── entry point tui.load calls (see tui_markup.sh) ─────────────────────

tui_build.load() {
	local file="$1"
	_tui_perf.begin parse
	tui.parse.file "$file"
	_TUI_P_RAW="$(tui_node.dump)" # the tree as written: tui.page.refresh starts from it instead of parsing again
	tui_addon.apply "$_P_ROOT" "$file"
	tui_compose.expand "$_P_ROOT"
	_tui_perf.end parse

	_tui_perf.begin build
	tui_build.build "$_P_ROOT"
	_tui_refresh.sign_tree # what was just built, pane by pane: the baseline tui.page.refresh compares against
	_tui_refresh.adopt
	_tui_perf.end build

	local n
	for n in "${_P_ERRORS[@]}"; do echo "tui.load: $n" >&2; done
}
