#!/usr/bin/env bash
# tui_validate_rules.sh - the default markup rules (engine and registration API: tui_validate.sh).
# Add, drop or loosen a check here; nothing else needs to change. Apps/plugins can register more the same way.

# -- vocabulary ----------------------------------------------------------
tui.validate.container tui pane tabs details accordion
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
tui.validate.enum pane divider "single|double|heavy"
tui.validate.enum pane title_pos "top|bottom"
tui.validate.enum pane title_align "left|center|right"
tui.validate.enum pane resizable "x|y|both"
tui.validate.enum pane handle "corner|edge|divider|none"
tui.validate.enum pane fit "pack|stretch"
for _tv_a in pane details; do
	tui.validate.enum "$_tv_a" collapse_to "title|0|rail"
	tui.validate.enum "$_tv_a" default "expanded|collapsed"
	for _tv_b in collapsible collapsed keep_collapsed; do tui.validate.enum "$_tv_a" "$_tv_b" "true|false"; done
done
tui.validate.enum accordion multiple "true|false"
tui.validate.enum tui keep_state "true|false"
tui.validate.enum pane keep_size "true|false"
tui.validate.enum details keep_size "true|false"
for _tv_b in input password textarea checkbox select list table progress; do tui.validate.enum "$_tv_b" keep_value "true|false"; done
tui.validate.enum '*' persist "session|disk"
tui.validate.enum '*' keep_focus "true|false"
unset _tv_b
tui.validate.enum tabs style "framed|compact"
tui.validate.enum bind scope "global"
tui.validate.enum '*' focus_nav "arrows|tab|both"
for _tv_a in focusable tabbable focus_wrap autofocus; do tui.validate.enum '*' "$_tv_a" "true|false"; done
for _tv_a in pane.fuse pane.strict_fit pane.newline input.retain_input_on_submit input.sticky checkbox.checked \
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
declare -gA _TVR_TABORD_N=() _TVR_TABORD_AT=() _TVR_RAIL_AT=() _TVR_RAIL_OK=() _TVR_CKEY=() _TVR_CCLASS=()
declare -ga _TVR_THEMES=()
declare -g _TVR_FOE="" _TVR_FOE_AT=""

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

_tui_vrule.reset() { _TVR_GRID_ROWS=() _TVR_GRID_COLS=() _TVR_GRID_CELL=() _TVR_TABS_AT=() _TVR_TABS_HP=() _TVR_TABS_CP=() _TVR_TABS_N=() _TVR_TABS_DEF=() _TVR_TABORD_N=() _TVR_TABORD_AT=() _TVR_RAIL_AT=() _TVR_RAIL_OK=() _TVR_CKEY=() _TVR_CCLASS=() _TVR_THEMES=() _TVR_FOE="" _TVR_FOE_AT=""; }
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

# handle draws mouse zones for a resizable pane: without resizable it does nothing
_tui_vrule.handle() {
	[[ "$TUI_V_TAG" == pane && -n "${_TV_A[handle]:-}" && "${_TV_A[handle]}" != none && -z "${_TV_A[resizable]:-}" ]] &&
		tui.validate.warn "pane '${_TV_A[id]:-?}' has handle=\"${_TV_A[handle]}\" but no resizable - the handle is ignored" handle
	return 0
}
tui.validate.rule element _tui_vrule.handle

# collapse: default and the collapsed alias must agree; collapse_to="rail" needs a button with collapsed_text to show
_tui_vrule.collapse() {
	if [[ "$TUI_V_TAG" == button && -n "${_TV_A[collapsed_text]:-}" ]]; then
		_TVR_RAIL_OK[${_TV_A[pane]:-$TUI_V_PARENT_ID}]=1
		return 0
	fi
	[[ "$TUI_V_TAG" == @(pane|details) ]] || return 0
	local d="${_TV_A[default]:-}" c="${_TV_A[collapsed]:-}"
	if [[ -n "$d" && -n "$c" && ("$d" == expanded && "$c" == true || "$d" == collapsed && "$c" == false) ]]; then
		tui.validate.error "${TUI_V_TAG} '${_TV_A[id]:-?}' has default=\"$d\" and collapsed=\"$c\" - they contradict, use one" collapsed
	fi
	if [[ "${_TV_A[collapse_to]:-}" == rail && -n "${_TV_A[id]:-}" ]]; then
		tui.validate.here collapse_to
		_TVR_RAIL_AT[${_TV_A[id]}]="$REPLY"
	fi
	return 0
}
tui.validate.rule element _tui_vrule.collapse

_tui_vrule.collapse_end() {
	local id
	for id in "${!_TVR_RAIL_AT[@]}"; do
		[[ -n "${_TVR_RAIL_OK[$id]:-}" ]] || tui.validate.warn_at "${_TVR_RAIL_AT[$id]}" "pane '$id' has collapse_to=\"rail\" but no button with collapsed_text - the rail would be empty"
	done
	return 0
}
tui.validate.rule end _tui_vrule.collapse_end

# collapse_key="KEY": a valid key name, unique on the page (also against the page's own <bind key=>s);
# collapse_class="NAME": a class the effective theme (the loaded one, the defaults, the page's <theme src>) defines
declare -g _TVR_KEY_RE='^((ctrl|control|alt|meta|shift)[+-])*(.|space|spc|enter|return|ret|tab|esc|escape|backspace|bs|delete|del|insert|ins|up|down|left|right|home|end|pgup|pgdn|pageup|pagedown|page_up|page_down|plus|minus|f([1-9]|1[0-2]))$'
_tui_vrule.collapse_key() {
	local k n
	if [[ "$TUI_V_TAG" == theme && -n "${_TV_A[src]:-}" ]]; then
		_TVR_THEMES+=("${TUI_V_FILE%/*}/${_TV_A[src]}")
		return 0
	fi
	if [[ "$TUI_V_TAG" == bind && -n "${_TV_A[key]:-}" && -z "${_TV_A[pane]:-}" ]]; then
		_tui_input.norm "${_TV_A[key]}"
		[[ -n "${_TVR_CKEY[$_KEY]:-}" ]] || _TVR_CKEY[$_KEY]="bind"
		return 0
	fi
	[[ "$TUI_V_TAG" == @(pane|details) ]] || return 0
	if [[ -n "${_TV_A[collapse_class]:-}" ]]; then
		tui.validate.here collapse_class
		_TVR_CCLASS[${_TV_A[collapse_class]}]="$REPLY|${_TV_A[id]:-?}"
	fi
	k="${_TV_A[collapse_key]:-}"
	[[ -n "$k" ]] || return 0
	if [[ ! "${k,,}" =~ $_TVR_KEY_RE ]]; then
		tui.validate.error "${TUI_V_TAG} '${_TV_A[id]:-?}' has collapse_key=\"$k\" - not a key name (e.g. ctrl+1, alt+c, f5)" collapse_key
		return 0
	fi
	_tui_input.norm "$k"
	n="$_KEY"
	if [[ -n "${_TVR_CKEY[$n]:-}" ]]; then
		tui.validate.error "collapse_key=\"$k\" on '${_TV_A[id]:-?}' is already used on this page (by ${_TVR_CKEY[$n]})" collapse_key
	else
		_TVR_CKEY[$n]="'${_TV_A[id]:-?}'"
	fi
	return 0
}
tui.validate.rule element _tui_vrule.collapse_key

_tui_vrule.collapse_class_end() {
	local c f at id found
	for c in "${!_TVR_CCLASS[@]}"; do
		at="${_TVR_CCLASS[$c]%|*}" id="${_TVR_CCLASS[$c]##*|}" found=0
		if [[ -n "${_TUI_CLASS_FG[$c]:-}${_TUI_CLASS_BG[$c]:-}${_TUI_CLASS_MOD[$c]:-}" ]]; then
			found=1
		else
			for f in "${_TVR_THEMES[@]}" "${TUI_DEFAULTS_DIR:-}/theme.css"; do
				[[ -r "$f" ]] && grep -qE "^[[:space:]]*\.$c[[:space:]]*[{:]" "$f" && {
					found=1
					break
				}
			done
		fi
		((found)) || tui.validate.warn_at "$at" "pane '$id' has collapse_class=\"$c\", which no theme defines - the button falls back to the plain look"
	done
	return 0
}
tui.validate.rule end _tui_vrule.collapse_class_end

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
	if [[ "$TUI_V_TAG" == tui && -n "${_TV_A[focus_on_enter]:-}" ]]; then
		_TVR_FOE="${_TV_A[focus_on_enter]}"
		tui.validate.here focus_on_enter
		_TVR_FOE_AT="$REPLY"
	fi
	[[ -n "${_TV_WIDGET[$TUI_V_TAG]:-}" ]] || return 0
	local n="${_TV_A[tab_order]:-}"
	if [[ "${_TV_A[keep_focus]:-}" == true ]]; then
		local kf=1
		if [[ "${_TV_A[focusable]:-}" == false ]]; then
			kf=0
		elif [[ -z "${_TV_A[focusable]:-}" ]]; then
			_tui_focus.default_focusable "$TUI_V_TAG" || kf=0
		fi
		((kf)) || tui.validate.warn "'${_TV_A[id]:-?}' has keep_focus but is not focusable: there is no focus to keep" keep_focus
	fi
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

# focus_on_enter on <tui>: keep, first or the id of a widget on the page
_tui_vrule.focus_on_enter_end() {
	[[ -n "$_TVR_FOE" && "$_TVR_FOE" != keep && "$_TVR_FOE" != first ]] || return 0
	[[ -n "${TUI_V_WIDGETS[$_TVR_FOE]:-}" ]] || tui.validate.error_at "$_TVR_FOE_AT" "focus_on_enter=\"$_TVR_FOE\" is not keep, first or the id of a widget on this page"
	return 0
}
tui.validate.rule end _tui_vrule.focus_on_enter_end

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
