#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_addon.sh                                                         ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui_addon.apply ROOT PAGE_FILE   applies every matching addon to the parsed page tree under ROOT, before the
#                                  compose pass (tui_compose.sh), so addon content may use templates, <for> and <if>.
# tui.addon.dir DIR                adds a directory whose *.xml files hold addons (a plugin's own; an app's
#                                  TUI_APP_CONF/addons is always read); files are read in name order.
# tui.addon.undir DIR              takes it away again (a plugin's folder goes with the plugin when it is disabled).
#
#   <addon id="stats" target="home.xml" priority="10" prefix="true">
#     <append  ref="#sidebar"><label id="n" text="x"/></append>      last child of #sidebar
#     <prepend ref="#sidebar">…</prepend>   <before ref="#footer">…</before>   <after ref=".row">…</after>
#     <replace ref="#old">…</replace>
#     <remove  ref=".legacy"/>
#     <set     ref="#title" attr="text" value="New"/>
#     <wrap    ref="#form" type="pane" id="boxed"/>
#   </addon>
#
# target: a page file name (home.xml) or * for every page. priority: lower runs first (default 0), so the higher
# number has the last word; equal priorities keep file order. ref: the selectors of tui_ops.sh (#id .class tag >).
# Insert and replace use the first match, remove and set every match. Inserted content is copied with every id
# prefixed "ADDONID_" unless prefix="false", so an addon cannot collide with the page or another addon.
# A ref that matches nothing is reported in _P_ERRORS. Everything is node ops (lib/markup/tui_ops.sh).
#
# Runtime tui.addon.load/unload (rebuilding only the affected subtree) is not here: it needs an incremental build.

declare -ga _TUI_ADDON_DIRS=()
declare -ga _TA_DIRS=() # _tui_addon.dirs result

# tui.addon.dir DIR - register a folder of addons; a plugin that calls it in on_enable gets it removed again on disable
tui.addon.dir() {
	_TUI_ADDON_DIRS+=("$1")
	_tui_plugin.own addondir "$1"
}

# tui.addon.undir DIR - forget a folder registered with tui.addon.dir
tui.addon.undir() {
	local d
	local -a keep=()
	for d in "${_TUI_ADDON_DIRS[@]}"; do [[ "$d" == "$1" ]] || keep+=("$d"); done
	_TUI_ADDON_DIRS=("${keep[@]}")
}

# _tui_addon.dirs - _TA_DIRS = the registered directories plus $TUI_APP_CONF/addons, only those that exist.
_tui_addon.dirs() {
	local d
	_TA_DIRS=()
	for d in "${_TUI_ADDON_DIRS[@]}" "${TUI_APP_CONF:+$TUI_APP_CONF/addons}"; do
		[[ -n "$d" && -d "$d" && " ${_TA_DIRS[*]} " != *" $d "* ]] && _TA_DIRS+=("$d") # once each: a twice-read file is a "cycle"
	done
}

# tui_addon.deps ARRAYNAME - appends every addon directory and *.xml file to the array (a nameref): the page
# cache covers them, and a directory's mtime changes when a file is added or removed.
tui_addon.deps() {
	local -n _ad_deps="$1"
	local _ad_dir _ad_file
	_tui_addon.dirs
	for _ad_dir in "${_TA_DIRS[@]}"; do
		_ad_deps+=("$_ad_dir")
		for _ad_file in "$_ad_dir"/*.xml; do [[ -r "$_ad_file" ]] && _ad_deps+=("$_ad_file"); done
	done
}

# tui_addon.apply ROOT PAGE_FILE
tui_addon.apply() {
	_tui_addon.dirs
	((${#_TA_DIRS[@]})) || return 0
	local root="$1" base="${2##*/}" scratch dir f a target i j t
	local -a found=() prio=()
	tui_node.create addons
	scratch=$_N
	for dir in "${_TA_DIRS[@]}"; do
		for f in "$dir"/*.xml; do [[ -s "$f" ]] && _tui_parse.include "$f" "$scratch"; done # an empty file is a switched-off addon: skipped without a parse
	done
	for a in ${_N_KIDS[$scratch]:-}; do
		[[ "${_N_TYPE[$a]}" == addon ]] || continue
		target="*"
		tui_node.attr_get "$a" target && target="$_N_ATTR_V"
		[[ "$target" == '*' || "${target##*/}" == "$base" ]] || continue
		t=0
		tui_node.attr_get "$a" priority && t="$_N_ATTR_V"
		[[ "$t" =~ ^-?[0-9]+$ ]] || t=0
		found+=("$a")
		prio+=("$t")
	done
	for ((i = 1; i < ${#found[@]}; i++)); do # stable insertion sort by priority
		a="${found[i]}" t="${prio[i]}"
		for ((j = i - 1; j >= 0 && prio[j] > t; j--)); do found[j + 1]="${found[j]}" prio[j + 1]="${prio[j]}"; done
		found[j + 1]="$a" prio[j + 1]="$t"
	done
	for a in "${found[@]}"; do _tui_addon.run "$a" "$root"; done
	tui_ops.remove "$scratch"
}

# _tui_addon.run ADDON ROOT - apply ADDON's op tags in document order.
_tui_addon.run() {
	local addon="$1" root="$2" id="addon" prefix="" op ref mode k n attr
	tui_node.attr_get "$addon" id && id="$_N_ATTR_V"
	tui_node.attr_get "$addon" prefix && mode="$_N_ATTR_V" || mode=true
	[[ "$mode" == false ]] || prefix="${id}_"
	local -a kids targets
	for op in ${_N_KIDS[$addon]:-}; do
		ref=""
		tui_node.attr_get "$op" ref && ref="$_N_ATTR_V"
		if ! tui_ops.select "$root" "$ref"; then
			_P_ERRORS+=("addon '$id': <${_N_TYPE[$op]}> ref '$ref' matches nothing")
			continue
		fi
		targets=("${_OP_NODES[@]}")
		kids=(${_N_KIDS[$op]:-})
		case "${_N_TYPE[$op]}" in
			append | before) for k in "${kids[@]}"; do tui_ops.clone "$k" "$prefix" && tui_ops.insert "${_N_TYPE[$op]}" "${targets[0]}" "$_N"; done ;;
			prepend | after) for ((n = ${#kids[@]} - 1; n >= 0; n--)); do tui_ops.clone "${kids[n]}" "$prefix" && tui_ops.insert "${_N_TYPE[$op]}" "${targets[0]}" "$_N"; done ;;
			replace)
				for k in "${kids[@]}"; do tui_ops.clone "$k" "$prefix" && tui_ops.insert before "${targets[0]}" "$_N"; done
				tui_ops.remove "${targets[0]}"
				;;
			remove) for n in "${targets[@]}"; do [[ -n "${_N_TYPE[$n]+x}" ]] && tui_ops.remove "$n"; done ;;
			set)
				attr=""
				tui_node.attr_get "$op" attr && attr="$_N_ATTR_V"
				tui_node.attr_get "$op" value || _N_ATTR_V=""
				for n in "${targets[@]}"; do tui_ops.set "$n" "$attr" "$_N_ATTR_V"; done
				;;
			wrap)
				tui_node.attr_get "$op" type && attr="$_N_ATTR_V" || attr=pane
				mode=""
				tui_node.attr_get "$op" id && mode="$prefix$_N_ATTR_V"
				tui_ops.wrap "${targets[0]}" "$attr" "$mode"
				;;
			*) _P_ERRORS+=("addon '$id': unknown op <${_N_TYPE[$op]}>") ;;
		esac
	done
}
