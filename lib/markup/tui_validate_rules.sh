#!/usr/bin/env bash
# tui_validate_rules.sh - the default markup rules (engine and registration API: tui_validate.sh).
# Add, drop or loosen a check here; nothing else needs to change. Apps/plugins can register more the same way.

# -- vocabulary ----------------------------------------------------------
tui.validate.container tui pane tabs
tui.validate.widget label input button checkbox password textarea list table select progress
tui.validate.tag script theme include footer bind tab
# composition (lib/markup/tui_compose.sh) and addons (tui_addon.sh): expanded away before the build
tui.validate.container template use slot fill for if else addon append prepend before after replace
tui.validate.tag component remove set wrap
tui.validate.self_closing script theme include footer bind tab \
	label input button checkbox password textarea list table select progress

# -- required attributes -------------------------------------------------
tui.validate.require pane id
tui.validate.require script src
tui.validate.require theme src
tui.validate.require include src
tui.validate.require template name
tui.validate.require use template
tui.validate.require fill slot
tui.validate.require if test
tui.validate.require component name src
tui.validate.require addon id
tui.validate.require append ref
tui.validate.require prepend ref
tui.validate.require before ref
tui.validate.require after ref
tui.validate.require replace ref
tui.validate.require remove ref
tui.validate.require set ref attr value
tui.validate.require wrap ref
tui.validate.require bind key action
tui.validate.require tabs id header_pane content_pane
tui.validate.require tab id
for _tv_t in label input button checkbox password textarea list table select progress; do
	tui.validate.require "$_tv_t" id
done
unset _tv_t

# -- allowed values ------------------------------------------------------
tui.validate.enum '*' align "left|center|right|fill"
tui.validate.enum '*' valign "top|middle|bottom"
tui.validate.enum '*' label_align "left|center|right"
tui.validate.enum pane split "h|v|grid|fixed"
tui.validate.enum pane border "single|double|heavy|none"
tui.validate.enum pane scroll "none|v|h|both"
tui.validate.enum pane fit "pack|stretch"
tui.validate.enum tabs style "framed|compact"
tui.validate.enum bind scope "global"
tui.validate.enum '*' focus_nav "arrows|tab|both"
for _tv_a in focusable tabbable focus_wrap autofocus; do tui.validate.enum '*' "$_tv_a" "true|false"; done
for _tv_a in pane.strict_fit pane.newline input.retain_input_on_submit input.sticky checkbox.checked \
	tab.default bind.pass bind.always; do
	tui.validate.enum "${_tv_a%%.*}" "${_tv_a#*.}" "true|false"
done
unset _tv_a

# -- numbers -------------------------------------------------------------
for _tv_a in min_width min_height max_width max_height hpad vpad label_width rows; do tui.validate.int '*' "$_tv_a" 0; done
tui.validate.int '*' row -9999
tui.validate.int '*' tab_order -1
for _tv_a in weight rows cols size_w size_h span; do tui.validate.int pane "$_tv_a" 1; done
tui.validate.int pane grid_row 0
tui.validate.int pane grid_col 0
unset _tv_a

# -- attributes that only work in a given context ------------------------
for _tv_a in rows cols fit row_weights col_weights; do tui.validate.needs pane "$_tv_a" split grid; done
tui.validate.needs pane size_w split fixed
tui.validate.needs pane size_h split fixed
tui.validate.parent_split pane grid_row grid
tui.validate.parent_split pane grid_col grid
tui.validate.parent_split pane span fixed
tui.validate.parent_split pane newline fixed
unset _tv_a

# -- conflicts / placement -----------------------------------------------
tui.validate.conflict button page action "the page link is ignored when an action is set"
tui.validate.parent tab tabs

# ═══ custom rules ═══════════════════════════════════════════════════════
declare -gA _TVR_GRID_ROWS=() _TVR_GRID_COLS=() _TVR_GRID_CELL=() _TVR_TABS_AT=() _TVR_TABS_HP=() _TVR_TABS_CP=() _TVR_TABS_N=() _TVR_TABS_DEF=()
declare -gA _TVR_TABORD_N=() _TVR_TABORD_AT=()

# a <component name="box"/> makes <box> a known tag for the rest of that page
declare -ga _TVR_COMP=()
_tui_vrule.component_reset() {
	local n
	for n in "${_TVR_COMP[@]}"; do unset '_TV_TAGS[$n]' '_TV_CONTAINER[$n]'; done
	_TVR_COMP=()
}
tui.validate.rule page _tui_vrule.component_reset
_tui_vrule.component() {
	if [[ "$TUI_V_TAG" == component ]] && tui.validate.attr name; then
		_TV_TAGS[$REPLY]=1 _TV_CONTAINER[$REPLY]=1
		_TVR_COMP+=("$REPLY")
	fi
	return 0
}
tui.validate.rule element _tui_vrule.component

_tui_vrule.reset() { _TVR_GRID_ROWS=() _TVR_GRID_COLS=() _TVR_GRID_CELL=() _TVR_TABS_AT=() _TVR_TABS_HP=() _TVR_TABS_CP=() _TVR_TABS_N=() _TVR_TABS_DEF=() _TVR_TABORD_N=() _TVR_TABORD_AT=(); }
tui.validate.rule page _tui_vrule.reset

# a widget written directly under <tui> (or in an included fragment) names its pane and row; one written inside a
# <pane> takes both from where it stands, and inside a template/for/if/addon it may land anywhere, so it is not checked
_tui_vrule.widget_place() {
	[[ -n "${_TV_WIDGET[$TUI_V_TAG]:-}" ]] || return 0
	[[ -z "$TUI_V_PARENT_TAG" || "$TUI_V_PARENT_TAG" == tui ]] || return 0
	local a
	for a in pane row; do
		tui.validate.attr "$a" && [[ -n "$REPLY" ]] || tui.validate.error "<$TUI_V_TAG> is missing the required attribute '$a'"
	done
	return 0
}
tui.validate.rule element _tui_vrule.widget_place

# <tui> wraps the whole page, once
_tui_vrule.root() {
	if [[ "$TUI_V_TAG" == tui ]]; then
		((TUI_V_DEPTH == 0)) || tui.validate.error "<tui> cannot be nested inside <$TUI_V_PARENT_TAG>"
	elif ((TUI_V_DEPTH == 0)) && [[ "$TUI_V_FILE" == "$TUI_V_PAGE" && "$TUI_V_TAG" != addon ]]; then # an addon file is its own document
		tui.validate.error "<$TUI_V_TAG> is outside <tui>…</tui> - everything in a page belongs inside the <tui> root"
	fi
}
tui.validate.rule element _tui_vrule.root

# pane nesting: children need a split parent, grid cells are leaves (<pane …></pane> on two lines is fine)
_tui_vrule.pane() {
	[[ "$TUI_V_TAG" == pane ]] || return 0
	local id="${_TV_A[id]:-?}"
	if [[ "$TUI_V_PARENT_TAG" == pane && -z "$TUI_V_PARENT_SPLIT" ]]; then
		tui.validate.error "pane '$id' is inside pane '$TUI_V_PARENT_ID', which has no split= - give '$TUI_V_PARENT_ID' split=\"h|v|grid|fixed\" or move '$id' out"
	fi
	if [[ "$TUI_V_PARENT_TAG" == pane && "$TUI_V_GRANDPARENT_SPLIT" == grid ]]; then
		tui.validate.error "pane '$id' is inside grid cell '$TUI_V_PARENT_ID' - panes within grid cells are not allowed, a grid cell must be a leaf pane"
	fi
}
tui.validate.rule element _tui_vrule.pane

# min_* larger than max_*
_tui_vrule.minmax() {
	local d mn mx
	for d in width height; do
		mn="${_TV_A[min_$d]:-}" mx="${_TV_A[max_$d]:-}"
		[[ "$mn" =~ ^[0-9]+$ && "$mx" =~ ^[0-9]+$ ]] || continue
		((10#$mx > 0 && 10#$mn > 10#$mx)) && tui.validate.error "min_$d=\"$mn\" is larger than max_$d=\"$mx\"" "min_$d"
	done
	return 0
}
tui.validate.rule element _tui_vrule.minmax

# split="grid": explicit cells must be inside the grid, not collide, and give both grid_row and grid_col
_tui_vrule.grid() {
	[[ "$TUI_V_TAG" == pane ]] || return 0
	local id="${_TV_A[id]:-}"
	if [[ -n "$id" && "${_TV_A[split]:-}" == grid ]]; then
		_TVR_GRID_ROWS[$id]="${_TV_A[rows]:-}" _TVR_GRID_COLS[$id]="${_TV_A[cols]:-}"
	fi
	[[ "$TUI_V_PARENT_SPLIT" == grid && -n "$TUI_V_PARENT_ID" ]] || return 0
	local g="$TUI_V_PARENT_ID" r="${_TV_A[grid_row]:-}" c="${_TV_A[grid_col]:-}"
	[[ -z "$r" && -z "$c" ]] && return 0
	if [[ -z "$r" || -z "$c" ]]; then
		tui.validate.warn "pane '$id' gives only one of grid_row/grid_col - both are needed for a fixed cell, it is placed automatically" "${r:+grid_row}${c:+grid_col}"
		return 0
	fi
	[[ "$r$c" =~ ^[0-9]+$ ]] || return 0 # already reported by the number check
	local rows="${_TVR_GRID_ROWS[$g]:-}" cols="${_TVR_GRID_COLS[$g]:-}"
	[[ -n "$rows" ]] && ((10#$r >= 10#$rows)) && tui.validate.error "grid_row=\"$r\" is outside grid '$g' (rows=\"$rows\", counted from 0)" grid_row
	[[ -n "$cols" ]] && ((10#$c >= 10#$cols)) && tui.validate.error "grid_col=\"$c\" is outside grid '$g' (cols=\"$cols\", counted from 0)" grid_col
	local key="$g:$((10#$r)):$((10#$c))"
	if [[ -n "${_TVR_GRID_CELL[$key]:-}" ]]; then
		tui.validate.error "grid '$g' cell ($r,$c) is already taken by '${_TVR_GRID_CELL[$key]}' - '$id' would replace it" grid_row
	fi
	_TVR_GRID_CELL[$key]="$id"
}
tui.validate.rule element _tui_vrule.grid

# <tabs>: only <tab> children, at most one default tab (panes are checked at the end of the page)
_tui_vrule.tabs() {
	if [[ "$TUI_V_TAG" == tabs ]]; then
		local id="${_TV_A[id]:-}"
		[[ -n "$id" ]] || return 0
		tui.validate.here
		_TVR_TABS_AT[$id]="$REPLY" _TVR_TABS_HP[$id]="${_TV_A[header_pane]:-}" _TVR_TABS_CP[$id]="${_TV_A[content_pane]:-}" _TVR_TABS_N[$id]=0
		[[ -n "${_TV_A[header_pane]:-}" && "${_TV_A[header_pane]}" == "${_TV_A[content_pane]:-}" ]] &&
			tui.validate.error "tabs '$id' uses pane '${_TV_A[header_pane]}' as both header_pane and content_pane" content_pane
		return 0
	fi
	[[ "$TUI_V_PARENT_TAG" == tabs && -n "$TUI_V_PARENT_ID" ]] || return 0
	if [[ "$TUI_V_TAG" != tab ]]; then
		tui.validate.error "<$TUI_V_TAG> is not allowed inside <tabs> - only <tab> elements go there"
		return 0
	fi
	local t="$TUI_V_PARENT_ID"
	((_TVR_TABS_N[$t]++))
	if [[ "${_TV_A[default]:-}" == true ]]; then
		[[ -n "${_TVR_TABS_DEF[$t]:-}" ]] && tui.validate.warn "tabs '$t' already has a default tab ('${_TVR_TABS_DEF[$t]}') - the first one wins" default
		_TVR_TABS_DEF[$t]="${_TVR_TABS_DEF[$t]:-${_TV_A[id]:-}}"
	fi
}
tui.validate.rule element _tui_vrule.tabs

# script/theme/include sources and page links must exist (script/theme/page resolve against the page's folder)
_tui_vrule.files() {
	local a="" base="${TUI_V_PAGE%/*}" p
	case "$TUI_V_TAG" in
		script | theme) a=src ;;
		button) a=page ;;
		*) return 0 ;;
	esac
	p="${_TV_A[$a]:-}"
	[[ -n "$p" && "$p" != *'$'* ]] || return 0
	[[ "$p" != /* ]] && p="$base/$p"
	[[ -r "$p" ]] || tui.validate.error "$a=\"${_TV_A[$a]}\" on <$TUI_V_TAG> points to a file that does not exist ($p)" "$a"
}
tui.validate.rule element _tui_vrule.files

# end of page: widgets sit in a declared leaf pane; tabs have children and their panes exist
_tui_vrule.refs() {
	local w p t loc hp cp
	for w in "${!TUI_V_WIDGET_PANE[@]}"; do
		p="${TUI_V_WIDGET_PANE[$w]}"
		[[ -n "$p" ]] || continue
		if [[ -z "${TUI_V_PANES[$p]:-}" ]]; then
			tui.validate.error_at "${TUI_V_WIDGET_PANE_AT[$w]}" "widget '$w' refers to pane '$p', which this page never declares"
		elif [[ -n "${TUI_V_PANE_SPLIT[$p]}" ]]; then
			tui.validate.error_at "${TUI_V_WIDGET_PANE_AT[$w]}" "widget '$w' is placed in pane '$p', which is split into child panes - widgets go into a leaf pane"
		fi
	done
	for t in "${!_TVR_TABS_AT[@]}"; do
		loc="${_TVR_TABS_AT[$t]}" hp="${_TVR_TABS_HP[$t]}" cp="${_TVR_TABS_CP[$t]}"
		((${_TVR_TABS_N[$t]:-0})) || tui.validate.error_at "$loc" "tabs '$t' has no <tab> children"
		[[ -n "$hp" && -z "${TUI_V_PANES[$hp]:-}" ]] && tui.validate.error_at "$loc" "tabs '$t' header_pane '$hp' is not a pane on this page"
		[[ -n "$cp" && -z "${TUI_V_PANES[$cp]:-}" ]] && tui.validate.error_at "$loc" "tabs '$t' content_pane '$cp' is not a pane on this page"
	done
	return 0
}
tui.validate.rule end _tui_vrule.refs

# focus: tabbable needs focusable; tab_order values 1..N should each appear once (gaps and duplicates are warnings)
_tui_vrule.focus() {
	[[ -n "${_TV_WIDGET[$TUI_V_TAG]:-}" ]] || return 0
	local n="${_TV_A[tab_order]:-}"
	if [[ "${_TV_A[tabbable]:-}" == true ]]; then
		local can=1
		if [[ "${_TV_A[focusable]:-}" == false ]]; then
			can=0
		elif [[ -z "${_TV_A[focusable]:-}" ]]; then
			_tui_focus.default_focusable "$TUI_V_TAG" || can=0
		fi
		((can)) || tui.validate.error "'${_TV_A[id]:-?}' is tabbable but not focusable - add focusable=\"true\" or drop tabbable" tabbable
	fi
	[[ "$n" =~ ^[1-9][0-9]*$ ]] || return 0
	n=$((10#$n))
	((_TVR_TABORD_N[$n]++))
	tui.validate.here tab_order
	_TVR_TABORD_AT[$n]="${_TVR_TABORD_AT[$n]:-$REPLY}"
}
tui.validate.rule element _tui_vrule.focus

_tui_vrule.tab_order_end() {
	local n max=0 k
	for n in "${!_TVR_TABORD_N[@]}"; do
		((n > max)) && max=$n
		((_TVR_TABORD_N[$n] > 1)) && tui.validate.warn_at "${_TVR_TABORD_AT[$n]}" "tab_order=\"$n\" is used by ${_TVR_TABORD_N[$n]} widgets - ties fall back to document order"
	done
	for ((k = 1; k < max; k++)); do
		[[ -n "${_TVR_TABORD_N[$k]:-}" ]] || tui.validate.warn_at "${_TVR_TABORD_AT[$max]}" "tab_order skips $k (the page uses up to $max) - Tab still follows the numeric order"
	done
	return 0
}
tui.validate.rule end _tui_vrule.tab_order_end
