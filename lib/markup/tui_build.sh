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
}

# ── <tui> / <script> / <theme> ─────────────────────────────────────────────

_tui_build.tag.tui() {
	local node="$1"
	local visit
	visit="$(_tui_build.attr "$node" on_visit)"
	[[ -n "$visit" ]] && _TUI_BUILD_ON_VISIT="$visit"
	local ddef dg
	local -a dgs=()
	ddef="$(_tui_build.attr "$node" defaults)"
	if [[ -n "$ddef" ]]; then
		IFS=',' read -ra dgs <<<"$ddef"
		for dg in "${dgs[@]}"; do [[ "$dg" == -* ]] && tui.defaults.off --page "${dg#-}"; done
	fi
	_tui_build.dispatch_children "$node" # <tui> is a transparent wrapper: its children build at the same level
}

_tui_build.tag.script() {
	local node="$1" src resolved
	src="$(_tui_build.attr "$node" src)"
	[[ -z "$src" ]] && return 0
	resolved="$src"
	[[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR}/${src}"
	_tui_cache_source "$resolved"
}

_tui_build.tag.theme() {
	local node="$1" tsrc tresolved
	tsrc="$(_tui_build.attr "$node" src)"
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
		id="$(_tui_build.auto_id pane)"
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
	local k ctype pending="" row=1
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

_tui_build.pane_of() {
	local v
	v="$(_tui_build.attr "$1" pane)"
	printf '%s' "${v:-$_TUI_BUILD_CTX_PANE}"
}
_tui_build.row_of() {
	local v
	v="$(_tui_build.attr "$1" row)"
	printf '%s' "${v:-$_TUI_BUILD_CTX_ROW}"
}

_tui_build.tag.label() {
	local node="$1"
	local lid lpane lrow lalign lvalign lminw lmaxw lclass
	lid="$(_tui_build.attr "$node" id)"
	lpane="$(_tui_build.pane_of "$node")"
	lrow="$(_tui_build.row_of "$node")"
	lalign="$(_tui_build.attr "$node" align)"
	lvalign="$(_tui_build.attr "$node" valign)"
	lminw="$(_tui_build.attr "$node" min_width)"
	lmaxw="$(_tui_build.attr "$node" max_width)"
	lclass="$(_tui_build.attr "$node" class)"
	tui.label "$lid" "$lpane" "$lrow" "$(_tui_build.attr "$node" text)"
	tui.align "$lid" "$lalign"
	tui.valign "$lid" "$lvalign"
	tui.minsize "$lid" "$lminw"
	tui.maxsize "$lid" "$lmaxw"
	local lwidth lheight lpadding
	lwidth="$(_tui_build.attr "$node" width)"
	lheight="$(_tui_build.attr "$node" height)"
	lpadding="$(_tui_build.attr "$node" padding)"
	[[ -n "$lwidth" ]] && tui.width "$lid" "$lwidth"
	[[ -n "$lheight" ]] && tui.height "$lid" "$lheight"
	_tui_cache_class "$lid" "$lclass"
	local lhpad lvpad
	lhpad="$(_tui_build.attr "$node" hpad)"
	lvpad="$(_tui_build.attr "$node" vpad)"
	tui.pad "$lid" "${lhpad:-$lpadding}" "${lvpad:-$lpadding}"
}
tui.register tag label _tui_build.tag.label

_tui_build.tag.input() {
	local node="$1"
	local iid ipane irow ialign ivalign iminw imaxw ilalign ilwidth iclass
	iid="$(_tui_build.attr "$node" id)"
	ipane="$(_tui_build.pane_of "$node")"
	irow="$(_tui_build.row_of "$node")"
	ialign="$(_tui_build.attr "$node" align)"
	ivalign="$(_tui_build.attr "$node" valign)"
	iminw="$(_tui_build.attr "$node" min_width)"
	imaxw="$(_tui_build.attr "$node" max_width)"
	ilalign="$(_tui_build.attr "$node" label_align)"
	ilwidth="$(_tui_build.attr "$node" label_width)"
	iclass="$(_tui_build.attr "$node" class)"
	local iminh imaxh iexpand
	iminh="$(_tui_build.attr "$node" min_height)"
	imaxh="$(_tui_build.attr "$node" max_height)"
	iexpand="$(_tui_build.attr "$node" expand)"
	tui.input "$iid" "$ipane" "$irow" "$(_tui_build.attr "$node" placeholder)" \
		"$(_tui_build.attr "$node" label)" "$(_tui_build.attr "$node" submit)"
	tui.align "$iid" "$ialign"
	tui.valign "$iid" "$ivalign"
	tui.minsize "$iid" "$iminw" "$iminh"
	tui.maxsize "$iid" "$imaxw" "$imaxh"
	[[ -n "$iexpand" ]] && tui.expand "$iid" "$iexpand"
	local iwidth iheight ipadding
	iwidth="$(_tui_build.attr "$node" width)"
	iheight="$(_tui_build.attr "$node" height)"
	ipadding="$(_tui_build.attr "$node" padding)"
	[[ -n "$iwidth" ]] && tui.width "$iid" "$iwidth"
	[[ -n "$iheight" ]] && tui.height "$iid" "$iheight"
	tui.label_align "$iid" "$ilalign"
	tui.label_width "$iid" "$ilwidth"
	local iretain
	iretain="$(_tui_build.attr "$node" retain_input_on_submit)"
	[[ -n "$iretain" ]] && tui.input.retain "$iid" "$iretain"
	[[ "$(_tui_build.attr "$node" sticky)" == true ]] && tui.input.sticky "$iid"
	_tui_cache_class "$iid" "$iclass"
	local ihpad ivpad
	ihpad="$(_tui_build.attr "$node" hpad)"
	ivpad="$(_tui_build.attr "$node" vpad)"
	tui.pad "$iid" "${ihpad:-$ipadding}" "${ivpad:-$ipadding}"
}
tui.register tag input _tui_build.tag.input

_tui_build.tag.button() {
	local node="$1"
	local bid bpane brow btext baction bpage balign bvalign bminw bmaxw bclass
	bid="$(_tui_build.attr "$node" id)"
	bpane="$(_tui_build.pane_of "$node")"
	brow="$(_tui_build.row_of "$node")"
	btext="$(_tui_build.attr "$node" text)"
	baction="$(_tui_build.attr "$node" action)"
	bpage="$(_tui_build.attr "$node" page)"
	balign="$(_tui_build.attr "$node" align)"
	bvalign="$(_tui_build.attr "$node" valign)"
	bminw="$(_tui_build.attr "$node" min_width)"
	bmaxw="$(_tui_build.attr "$node" max_width)"
	bclass="$(_tui_build.attr "$node" class)"
	local bminh bmaxh bexpand
	bminh="$(_tui_build.attr "$node" min_height)"
	bmaxh="$(_tui_build.attr "$node" max_height)"
	bexpand="$(_tui_build.attr "$node" expand)"

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
	bwidth="$(_tui_build.attr "$node" width)"
	bheight="$(_tui_build.attr "$node" height)"
	bpadding="$(_tui_build.attr "$node" padding)"
	[[ -n "$bwidth" ]] && tui.width "$bid" "$bwidth"
	[[ -n "$bheight" ]] && tui.height "$bid" "$bheight"
	_tui_cache_class "$bid" "$bclass"
	local bhpad bvpad
	bhpad="$(_tui_build.attr "$node" hpad)"
	bvpad="$(_tui_build.attr "$node" vpad)"
	tui.pad "$bid" "${bhpad:-$bpadding}" "${bvpad:-$bpadding}"
}
tui.register tag button _tui_build.tag.button

_tui_build.tag.checkbox() {
	local node="$1"
	local kid kpane krow klabel kchecked kaction kalign kvalign kminw kmaxw kclass
	kid="$(_tui_build.attr "$node" id)"
	kpane="$(_tui_build.pane_of "$node")"
	krow="$(_tui_build.row_of "$node")"
	klabel="$(_tui_build.attr "$node" label)"
	kchecked="$(_tui_build.attr "$node" checked)"
	kaction="$(_tui_build.attr "$node" action)"
	kalign="$(_tui_build.attr "$node" align)"
	kvalign="$(_tui_build.attr "$node" valign)"
	kminw="$(_tui_build.attr "$node" min_width)"
	kmaxw="$(_tui_build.attr "$node" max_width)"
	kclass="$(_tui_build.attr "$node" class)"
	local kminh kmaxh kexpand
	kminh="$(_tui_build.attr "$node" min_height)"
	kmaxh="$(_tui_build.attr "$node" max_height)"
	kexpand="$(_tui_build.attr "$node" expand)"

	tui.checkbox "$kid" "$kpane" "$krow" "$klabel" "$kchecked" "$kaction"
	tui.align "$kid" "$kalign"
	tui.valign "$kid" "$kvalign"
	tui.minsize "$kid" "$kminw" "$kminh"
	tui.maxsize "$kid" "$kmaxw" "$kmaxh"
	[[ -n "$kexpand" ]] && tui.expand "$kid" "$kexpand"
	local kwidth kheight kpadding
	kwidth="$(_tui_build.attr "$node" width)"
	kheight="$(_tui_build.attr "$node" height)"
	kpadding="$(_tui_build.attr "$node" padding)"
	[[ -n "$kwidth" ]] && tui.width "$kid" "$kwidth"
	[[ -n "$kheight" ]] && tui.height "$kid" "$kheight"
	_tui_cache_class "$kid" "$kclass"
	local khpad kvpad
	khpad="$(_tui_build.attr "$node" hpad)"
	kvpad="$(_tui_build.attr "$node" vpad)"
	tui.pad "$kid" "${khpad:-$kpadding}" "${kvpad:-$kpadding}"
}
tui.register tag checkbox _tui_build.tag.checkbox

# password/textarea/list/table/select/progress: still built by
# lib/widgets/tui_widgets.sh's _markup_wx (that file's, not this task's, to
# change) - it takes a raw attribute line, so one is reassembled from the
# node's own attributes rather than duplicating its five widget bodies here.
_tui_build.tag.wx() {
	local node="$1" type="${_N_TYPE[$1]}" line="<$type" k v
	for k in "${!_N_ATTR[@]}"; do
		[[ "$k" == "$node."* ]] || continue
		v="${k#"$node".}"
		[[ "$v" == __* ]] && continue
		line+=" $v=\"${_N_ATTR[$k]//\"/&quot;}\""
	done
	line+="/>"
	local pane row
	pane="$(_tui_build.pane_of "$node")"
	row="$(_tui_build.row_of "$node")"
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
	tui.footer.set "$(_tui_build.attr "$1" items)"
}
tui.register tag footer _tui_build.tag.footer

_tui_build.tag.bind() {
	local node="$1" bkey bact bpane_s bpass balways bdesc bscope
	bkey="$(_tui_build.attr "$node" key)"
	bact="$(_tui_build.attr "$node" action)"
	bpane_s="$(_tui_build.attr "$node" pane)"
	bpass="$(_tui_build.attr "$node" pass)"
	balways="$(_tui_build.attr "$node" always)"
	bdesc="$(_tui_build.attr "$node" desc)"
	bscope="$(_tui_build.attr "$node" scope)"
	local -a bflags=(--page)
	[[ "$bscope" == global ]] && bflags=()
	[[ -n "$bpane_s" ]] && bflags+=(--pane "$bpane_s")
	[[ "$bpass" == true ]] && bflags+=(--pass)
	[[ "$balways" == true ]] && bflags+=(--always)
	[[ -n "$bdesc" ]] && bflags+=(--desc "$bdesc")
	tui.bind "$bkey" "$bact" "${bflags[@]}"
}
tui.register tag bind _tui_build.tag.bind

# <tabs> children are read straight off the tree - no open/close stash
# needed now that the whole document is parsed up front.
_tui_build.tag.tabs() {
	local node="$1" tabsid thp tcp tstyle
	tabsid="$(_tui_build.attr "$node" id)"
	thp="$(_tui_build.attr "$node" header_pane)"
	tcp="$(_tui_build.attr "$node" content_pane)"
	tstyle="$(_tui_build.attr "$node" style)"
	[[ "$tstyle" == "compact" ]] && tui.tabs.compact "$tabsid" true

	tui_node.children "$node"
	local -a kids=("${_N_CHILDREN[@]}")
	local -a tab_ids=()
	local k
	for k in "${kids[@]}"; do
		[[ "${_N_TYPE[$k]}" == "tab" ]] || continue
		local tid tabtext tabaction tabdefault
		tid="$(_tui_build.attr "$k" id)"
		tabtext="$(_tui_build.attr "$k" text)"
		tabaction="$(_tui_build.attr "$k" action)"
		tabdefault="$(_tui_build.attr "$k" default)"
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
	_tui_perf.end parse

	_tui_perf.begin build
	tui_build.build "$_P_ROOT"
	_tui_perf.end build

	local n
	for n in "${_P_ERRORS[@]}"; do echo "tui.load: $n" >&2; done
}
